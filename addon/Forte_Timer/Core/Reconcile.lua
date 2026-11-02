-- addon/Forte_Timer/Core/Reconcile.lua
-- FX.Timer.Reconcile: the gated aura sweep (design §4.2). The ONLY file in the
-- addon that reads an aura API, and it runs when the client says aura reads
-- are plain. This is the half of the original's `ST_CorrectionScan`
-- (Forte_Timer.lua:1142-1223) that survives Forever: the adopt / extend /
-- refresh / refused-removal reconciliation and the `learned` duration that
-- feeds Registry.Learn.
--
-- THE GATE. `C_UnitAuras.GetAuraDataBySpellName` carries
-- `SecretWhenUnitAuraRestricted` AND `RequiresNonSecretAura`, and its result
-- for a secret aura is explicitly undefined -- nil, a raise, or a secret value
-- (docs/research/secrets-unknowns.md:255-260, catalog
-- UnitAuraDocumentation.lua:244). So:
--   * `FX.SecretState.aurasSecret == true` => ZERO aura calls (T10; the mode
--     saves work and the launch-day probes P3/P4 measure whether the mode is
--     ever the whole story in combat);
--   * every call is pcall'd (a restricted read RAISES);
--   * every returned field passes FX.Compat.PlainOrNil before it is compared
--     or used in arithmetic;
--   * a nil/secret answer changes NOTHING -- the contract
--     Forte_Cooldown/Core/Engine.lua:210-213 already enforces, and the
--     `isMine` filter (Forte_Timer.lua:1095) is the reason a row of ours is the
--     only thing a sweep may touch.
--
-- The triggers (the design's §4.2 table, wired by Module.lua): `UNIT_AURA`
-- (throttled) for "player" and "target", `PLAYER_TARGET_CHANGED`, the
-- out-of-combat `PLAYER_REGEN_ENABLED` full sweep (the one teacher in the
-- system), and the timed 1 Hz safety sweep.
--
-- The readers are COUNTED SEAMS (`Reconcile.counts.reads`) so
-- tests/test_reconcile.lua can assert "zero aura calls while secret" and
-- "nothing mutates on a raising reader" -- the launch-day safety story, T10.
--
-- THE ALLOCATION LAW (docs/perf.md §4 fix 4). The sweep runs out of combat at
-- 2 Hz over every live row, so nothing on the per-read path may allocate: the
-- two pcall'd field readers are module-scope functions handed the aura as an
-- argument, and the byIndex fallback enumerates into `Reconcile._byIndexScratch`.
-- The sealed-read contract (pcall, PlainOrNil, "a nil changes nothing") rides
-- the argument, not a closure, so the safety story is unchanged.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Timer = FX.Timer or {}

local Reconcile = {}
FX.Timer.Reconcile = Reconcile

local Laws = FX.Timer.Laws

Reconcile.rows = nil
Reconcile.options = nil
Reconcile.throttle = 0.25           -- coalesce a UNIT_AURA burst
Reconcile.lastSweep = {}            -- [token] = stamp
Reconcile.counts = { reads = 0, plain = 0, secret = 0, raised = 0, adopted = 0,
    extended = 0, refreshed = 0, removed = 0, refused = 0, grace = 0, added = 0,
    learned = 0, skipped = 0 }

--- The bulk readers' fallback collector, allocated once on the first
--- byIndex sweep and reused ever after (docs/perf.md §4 fix 4).
Reconcile._byIndexScratch = nil

--- The injectable readers (tests, and the fallback shapes):
---   byName(unit, spellName, filter) -> AuraData | nil
---   bulk(unit, filter)              -> { AuraData, ... } | nil
---   byIndex(unit, i, filter)        -> AuraData | nil
Reconcile.readers = nil

--- The injectable liveness reader (Core/Rows.lua's `Rows.liveness` is THIS
--- same function, shared by `Init`): `liveness(unitToken) -> guid, dead,
--- ghost`, every value PLAIN-or-nil. It answers two questions: the identity
--- of the unit a token points at right now (which is what stamps a row's
--- guid at the confirming insert) and whether that unit is alive.
Reconcile.liveness = nil

--- The gate. True when the sweep must not read auras. ONLY a plain `true`
--- answers: FX.SecretState's nil means "this client gives me no answer", and
--- an unknown is not a reason to skip work (the SecretState consumer law).
function Reconcile:Gates()
    local SS = FX.SecretState
    if SS and SS.aurasSecret == true then return true end
    -- Out of combat is the design's precondition (§3.5: "Out-of-combat aura
    -- reconcile ... in-combat the same reads are refused"): the seal is the
    -- engine's own gate, and the combat flag is ours -- in combat the read is
    -- sealed and a nil cannot be told from a seal, so the sweep does not run.
    local probe = self.inCombat
    if probe == nil then probe = InCombatLockdown end
    if type(probe) == "function" then
        local ok, combat = pcall(probe)
        if ok and FX.Compat.PlainOrNil(combat) then return true end
    end
    return false
end

local function plain(v) return FX.Compat.PlainOrNil(v) end

--- The pcall'd field readers, HOISTED to module scope (docs/perf.md §4 fix 4):
--- a 2 Hz sweep of 30 rows used to allocate one closure per aura read, which
--- was the bulk of the sweep's out-of-combat garbage. `pcall(f, aura)` hands
--- the aura over as an argument, so the raise-on-field-read contract (the
--- sealed proxy) is untouched -- the call is still a pcall of the field read.
local function readFactFields(aura)
    return plain(aura.expirationTime), plain(aura.duration),
        plain(aura.applications)
end

local function readExpiration(aura)
    return aura.expirationTime
end

--- The plain AuraData triple the reconciliation eats:
--- (expirationTime - GetTime() => expireAt, duration seconds, applications).
--- Returns (expireAt, total, stacks) all PLAIN, or nil when any half is
--- missing/secret. `now` is the caller's clock so a test's injected clock and
--- the API's server-clock semantics stay one story: Forever hands
--- `expirationTime` in GetTime() units (docs/api
--- wow-api-unit-player/references/UNIT-AURAS.md:174-199).
function Reconcile:ReadFact(aura, now)
    if aura == nil then return nil end
    local iss = _G.issecretvalue
    if iss and iss(aura) then return nil end
    local ok, exp, dur, app = pcall(readFactFields, aura)
    if not ok then return nil end
    if type(exp) ~= "number" then return nil end
    local total = (type(dur) == "number" and dur > 0) and dur or nil
    local stacks = (type(app) == "number") and app or nil
    return exp, total, stacks
end

--- The counted, pcall'd call, and the one place a read is classified. A reader
--- answers with the AuraData, with `false` for "I looked, the aura is not
--- there" (the removal fact of :1207), or with nil for "no answer" (a raise,
--- an absent API, or a SECRET read -- `FX.Compat.PlainOrNil` cannot tell a
--- plain nil from a sealed one, and a sealed read must never be read as an
--- absence: a wrong removal kills a live row).
--- Returns (value, "ok" | "absent" | "secret" | "raise" | "absent-api").
local function call(self, fn, ...)
    if type(fn) ~= "function" then return nil, "absent-api" end
    self.counts.reads = self.counts.reads + 1
    local okCall, aura = pcall(fn, ...)
    if not okCall then
        self.counts.raised = self.counts.raised + 1
        return nil, "raise"
    end
    if aura == false then
        self.counts.plain = self.counts.plain + 1
        return false, "absent"
    end
    if aura == nil then
        -- The API ANSWERED and there is no such aura: that is the absence
        -- fact of :1207. A SEALED read is not nil -- it arrives as the sentinel
        -- value (the Forte_Core/Compat law: the sentinel passes PlainOrNil and
        -- arrives nil *as a field*, i.e. a table whose fields are nil), so nil
        -- here is a real "no aura", and a seal is caught by the two tests
        -- below.
        self.counts.plain = self.counts.plain + 1
        return false, "absent"
    end
    local iss = _G.issecretvalue
    if iss and iss(aura) then
        self.counts.secret = self.counts.secret + 1
        return nil, "secret"
    end
    -- The seal's signature is a raise on the field read (the sim's
    -- `MakeSecret` proxy) or a value `PlainOrNil` refuses; both are "no
    -- answer", never an absence.
    local okRead, exp = pcall(readExpiration, aura)
    if not okRead then
        self.counts.secret = self.counts.secret + 1
        return nil, "secret"
    end
    if plain(exp) == nil then
        self.counts.secret = self.counts.secret + 1
        return nil, "secret"
    end
    self.counts.plain = self.counts.plain + 1
    return aura, "ok"
end

--- One row of one unit: the per-name lookup, the port of
--- `UnitHasYourAura(unit, name, filter)` (Forte_Timer.lua:1124-1140) walking by
--- NAME (never an id) -- the row's own target identity decides the token.
--- Returns the verdict string, "absent" (the aura is confirmed gone), nil
--- (no answer: nothing changed).
function Reconcile:SweepRow(row, token, filter, now)
    local readers = self.readers
    local r = self.rows
    local byName = readers and readers.byName
    local aura, how = call(self, byName, token, row.name, filter)
    if how == "absent" then
        -- The removal half (:1207's "dont remove if only maxlag left" and the
        -- :1353-1363 purge live in Rows:OnAuraAbsent, with the BuffDelay grace)
        local verdict = r:OnAuraAbsent(row, now)
        self.counts[verdict] = (self.counts[verdict] or 0) + 1
        return verdict
    end
    if aura == nil then
        self.counts.skipped = self.counts.skipped + 1
        return nil
    end
    local expire, total, stacks = self:ReadFact(aura, now)
    if expire == nil then
        self.counts.skipped = self.counts.skipped + 1
        return nil
    end
    -- The one teacher: a plain (duration, expirationTime) pair is the only
    -- thing allowed to teach a duration (PLAN §3.2; Engine:OnRead's rule).
    if type(total) == "number" and total > 0 then
        local before = FX.Timer.Registry.learned[row.name]
        FX.Timer.Registry.Learn(row.name, total)
        if before ~= FX.Timer.Registry.learned[row.name] then
            self.counts.learned = self.counts.learned + 1
        end
    end
    local verdict = r:OnAuraFact(row, expire, total, stacks, now,
        row.unitToken or token, row.raidMark,
        -- The confirming read's identity, so Rows can gate a removal on the
        -- unit that wore the aura (:1161).
        self:TokenGuid(token))
    if verdict == "adopt" then
        self.counts.adopted = self.counts.adopted + 1
    elseif verdict == "extend" then
        self.counts.extended = self.counts.extended + 1
    elseif verdict == "refresh" then
        self.counts.refreshed = self.counts.refreshed + 1
    end
    return verdict
end

--- Sweep every live row that belongs to `token`: a row whose targetKey is the
--- token, whose unitToken is it, or (self rows) the "player" sweep of a
--- targetKey == "none" row.
function Reconcile:SweepUnit(token, filter, now)
    if self:Gates() then return 0 end
    now = now or GetTime()
    local r = self.rows
    local n = 0
    for i = 1, r.rows_n do
        local row = r.rows[i]
        if row and row.state <= Laws.REMOVE then
            local mine = (row.targetKey == token)
                or (row.unitToken == token)
                or (token == "player" and row.targetKey == "none")
            if mine then
                if self:SweepRow(row, token, filter, now) then n = n + 1 end
            end
        end
    end
    self.lastSweep[token] = now
    return n
end

--- The bulk half: the design's P5 path. `GetUnitAuras(unit, filter)` lists the
--- auras, `GetAuraDataByIndex` is the bounded fallback enumeration. Every row
--- is matched by NAME against the registry, and only a REGISTERED spell may be
--- added -- `ST_ScanForMissing`'s own gate (Forte_Timer.lua:1103: only spells
--- registered as OUR OWN casts), which is why this panel is not a raid-debuff
--- tracker (spec ST-24).
function Reconcile:SweepBulk(token, filter, now)
    if self:Gates() then return 0 end
    local readers = self.readers
    local added = 0
    local list, how
    if readers and readers.bulk then
        list, how = call(self, readers.bulk, token, filter)
    end
    if list == false then
        -- The bulk answer came back empty: the unit has no auras of that
        -- filter, and the enumeration would be pure cost.
        return 0
    end
    if list == nil and readers and readers.byIndex then
        -- the bounded fallback enumeration. The collector is a PREALLOCATED
        -- scratch (docs/perf.md §4 fix 4): the sweep runs at 2 Hz over every
        -- token, and a fresh table per sweep was a third of this leg's
        -- out-of-combat garbage. It is emptied by the `count` cursor plus the
        -- one trailing nil, and consumed before the next sweep can run.
        local out = self._byIndexScratch
        if not out then out = {} self._byIndexScratch = out end
        local count = 0
        for i = 1, 40 do
            local aura = call(self, readers.byIndex, token, i, filter)
            if aura == nil or aura == false then break end
            count = count + 1
            out[count] = aura
        end
        out[count + 1] = nil
        list = out
        how = "ok"
    end
    if list == nil then
        if how ~= "absent" then self.counts.skipped = self.counts.skipped + 1 end
        return 0
    end
    local n = 0
    if type(list) == "table" then
        for _, aura in ipairs(list) do
            local expire, total, stacks = self:ReadFact(aura, now)
            local name = aura and plain(aura.name)
            if type(name) == "string" and expire ~= nil
                and FX.Timer.Registry.IsTracked(name) then
                local row, verdict = self.rows:InsertFromAura(name,
                    (token == "player") and "none" or token,
                    expire, total
                        or math.max(0, expire - now), stacks, token, nil, now,
                    -- The confirming read's identity (the original's
                    -- `st[i][11] = guid`, :1161): nil when the client gives no
                    -- plain UnitGUID, which leaves the row guid-less and its
                    -- break fail-open.
                    self:TokenGuid(token))
                if row and verdict == "inserted" then
                    added = added + 1
                    self.counts.added = self.counts.added + 1
                end
                n = n + 1
            end
        end
    end
    return n, added
end

--- The full sweep: self rows on "player" (HELPFUL, the ST_PlayerBuffs port
--- :1272-1351), target rows on "target" (HARMFUL, the ST_TargetDebuffs port
--- :1225-1271). Rides PLAYER_REGEN_ENABLED (out of combat: every read is plain
--- again, the one moment predictions are re-anchored AND learned).
function Reconcile:SweepAll(now)
    if self:Gates() then return 0 end
    now = now or GetTime()
    local n = 0
    n = n + self:SweepUnit("player", "HELPFUL", now)
    n = n + self:SweepBulk("player", "HELPFUL", now)
    local hasTarget = false
    if type(UnitExists) == "function" then
        local ok, exists = pcall(UnitExists, "target")
        hasTarget = ok and FX.Compat.PlainOrNil(exists) and true or false
    end
    if hasTarget then
        n = n + self:SweepUnit("target", "HARMFUL", now)
        self:SweepBulk("target", "HARMFUL PLAYER", now)
    end
    return n
end

function Reconcile:Init(rows, options)
    self.rows = rows
    self.options = options
    self.readers = self.readers or self.LiveReaders()
    self.liveness = self.liveness or self.LiveLiveness()
    -- The death gate of `Rows:OnAuraAbsent` reads the SAME seam the guid
    -- stamp below writes: the gate and the stamp can not disagree about what
    -- a token's identity is.
    rows.liveness = self.liveness
    return self
end

--- The production liveness reader. Thin pcall-at-the-call-site wrappers over
--- the catalog globals (`UnitGUID`, `UnitExists`, `UnitIsDead`,
--- `UnitIsDeadOrGhost` -- all in the pinned 1.60.1.70532 catalog,
--- `UnitDocumentation.lua`), every answer through PlainOrNil so a sealed
--- identity arrives nil. The unit-exists half is answered separately because
--- a MISSING unit is not a sealed one: "the token points at nothing" is a
--- plain fact, and the caller must be able to tell it from "the client will
--- not tell me". A raising read of a unit that exists means exactly that --
--- sealed -- and arrives as a nil guid.
function Reconcile.LiveLiveness()
    local function plain(v) return FX.Compat.PlainOrNil(v) end
    return function(unitToken)
        local exists
        if type(UnitExists) == "function" then
            local ok, answer = pcall(UnitExists, unitToken)
            exists = ok and plain(answer) == true
        end
        local guid, dead, ghost
        if type(UnitGUID) == "function" then
            local ok, answer = pcall(UnitGUID, unitToken)
            guid = ok and plain(answer) or nil
        end
        if guid == nil then return nil, nil, nil end
        if type(UnitIsDead) == "function" then
            local ok, answer = pcall(UnitIsDead, unitToken)
            dead = ok and plain(answer) or nil
        end
        if dead == nil and type(UnitIsDeadOrGhost) == "function" then
            local ok, answer = pcall(UnitIsDeadOrGhost, unitToken)
            ghost = ok and plain(answer) or nil
        end
        return guid, dead, ghost, exists
    end
end

--- The token's own identity, PLAIN, for the guid stamp. nil when the client
--- gives no answer (the row then carries no guid and its break stays
--- fail-open).
function Reconcile:TokenGuid(token)
    local probe = self.liveness
    if type(probe) ~= "function"
        or type(self.rows) ~= "table"
        or not (self.rows.LIVENESS_TOKENS
            and self.rows.LIVENESS_TOKENS[token]) then
        return nil
    end
    local guid = probe(token)
    return (type(guid) == "string") and guid or nil
end

--- The production readers. Every one is a thin, pcall-at-the-call-site wrapper
--- over the catalog API; the sim does not ship the C_RestrictedActions /
--- C_Secrets surface, and the C_UnitAuras surface is present in the sim's
--- build, so these are exercised for real by the run.
function Reconcile.LiveReaders()
    return {
        byName = function(unit, name, filter)
            if not (C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then
                return nil
            end
            return C_UnitAuras.GetAuraDataBySpellName(unit, name, filter)
        end,
        bulk = function(unit, filter)
            if not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then
                return nil
            end
            return C_UnitAuras.GetUnitAuras(unit, filter)
        end,
        byIndex = function(unit, i, filter)
            if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then
                return nil
            end
            return C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
        end,
    }
end

function Reconcile:StatusLine()
    local c = self.counts
    return string.format(
        "Timer aura sweep: reads %d | plain %d | secret %d | raised %d | adopted %d | extended %d | refreshed %d | refused %d | grace %d | removed %d | added %d | learned %d",
        c.reads, c.plain, c.secret, c.raised, c.adopted, c.extended,
        c.refreshed, c.refused, c.grace, c.removed, c.added, c.learned)
end
