-- addon/Forte_Timer/Core/Rows.lua
-- FX.Timer.Rows: the live row table and its laws -- §3.2's row record, §3.3's
-- keying, §3.5's insert/reconcile numbers, §3.6's smoothing and the §1.9
-- lifetime machine. **Zero game API in this file**: every number arrives as an
-- argument from Module.lua / Core/Casts.lua / Core/Reconcile.lua, which is what
-- makes the whole law testable in the sim with an injected clock
-- (tests/test_rows.lua) and what keeps the secret-value rules in the two files
-- that read the game.
--
-- The row (design §3.2): a fixed-shape named table, not the original's 28-slot
-- positional tuple (which the source repeats at every insert site, spec
-- ST-13). Each field names the column it replaces:
--
--   name           col 8   the spell NAME (never an id)
--   targetKey      col 4+11  "none" (self/no-target) | the cast-target string
--                          while unconfirmed | the resolved unit token once an
--                          aura read confirmed it
--   groupKey       col 13  our monotonic per-target id (the CA:GiveID port) or
--                          a Laws.PRIOR_* sentinel for self/no-target
--   expireAt       col 1   the authoritative expiry (the fact or the prediction)
--   drawExpireAt   col 20  the smoothed value the renderer draws (:1046)
--   castTime       col 2   the cast instant (GetTime() units)
--   total          col 3   the window the bar is scaled against
--   state          col 14  -1..4, Laws.* values
--   kind           col 6   the spell type (the colour + fade class)
--   stacks         col 16  written ONLY by an aura read; a predicted row shows
--                          none (Forte_Timer.lua:2467-2471 draws from >0)
--   removeAt       col 17  stamped by Fade()
--   expireMsgAt    col 12  the expiry-message stamp (fires exactly once)
--   id             --      our row id (the CA:GiveID counter of the row itself)
--   hasteFactor    col 22  the frozen out-of-combat haste factor
--   predicted      new     true until an aura read adopts it (UI marking §5.5)
--   unitToken      col 27  the resolved unit token, nil while unconfirmed
--   guid           col 11  the target unit's GUID as the CONFIRMING aura read
--                          saw it (`:1161 st[i][11] = guid`), stamped only
--                          where the unit identity is readable and only
--                          after PlainOrNil; nil = unknown. It is the aura
--                          law's ADOPTION key (the identity the confirming
--                          read of that unit must match) and the liveness
--                          gate's aura-side half: the cast path never writes
--                          it, because a stamp here would make a prediction
--                          adoptable by identity and move `predicted` with it.
--   castToken      --      the unit token the CAST's target string resolved
--   castGuid            to at the insert, plus the plain `UnitGUID` that token
--                          had then (Core/Casts.lua's Pump). The liveness gate
--                          of `TargetIsDead` is its ONLY consumer; it is not
--                          an adoption key and changes nothing else. nil =
--                          no cast identity, which fails that gate open.
--   maxTime        link col 6  the compression scale (:2192-2235)
--   hiddenSince    link col 7  the HideLonger gate's trip stamp (:2151-2162)
--   alpha          link col 4  the visibility computed per pass (:2146-2168)
--
-- The laws, verbatim numbers in Core/Laws.lua:
--   MAXLAG 1.00  the adopt/extend/refresh tolerance (:33, :899-905, :1159-1207)
--   BUFF_DELAY 4.0 the grace before a row may be judged gone (:69, :1186-1187)
--   removal permitted while more than MAXLAG of the window is left, refused
--     in its last MAXLAG (:1207 "dont remove if only maxlag left")
--   shorter by more than MAXLAG => REFRESH: fade the row, re-insert (:924, ST-25)
--   SMOOTH 5 the drawn-expire interpolation (:1046)

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Timer = FX.Timer or {}

local Rows = {}
FX.Timer.Rows = Rows

local Laws = FX.Timer.Laws

--- Forte_Core/Core/TestMode.lua's tag reader. The four public legs of the row
--- machine (FX_TIMER_FADING / TIMER_EXPIRED / TIMER_BROKEN and the
--- announce channel) skip a row the `/fx test` demo invented, and the tag is a
--- field of OUR row table -- this file reads no game API and this is not one.
--- Captured at load (Forte_Core is a hard dependency and loads first), with the
--- nil test so a Core without the feature leaves the fires exactly as they
--- were.
local TestMode = FX.TestMode
local function isSynthetic(row)
    return TestMode ~= nil and TestMode.IsSynthetic(row)
end

Rows.rows = {}          -- array 1..rows_n; holes are compacted by Sweep
Rows.rows_n = 0
Rows.byKey = {}         -- Laws.RowKey(name, targetKey) -> index
Rows.nextId = 1         -- the CA:GiveID port: monotonic, recycled from live rows
Rows.links = {}         -- the sort/draw link table, reused every pass
Rows.options = nil      -- set by Module.lua: the live options/gate table

--- The injectable liveness reader (the `Reconcile.readers` convention, and
--- the reason this file keeps its "zero game API" header law):
--- `liveness(unitToken) -> guid, dead, ghost`, every value PLAIN-or-nil (a
--- sealed read arrives nil). Module.lua installs the real one, which is
--- `UnitGUID` / `UnitIsDead` / `UnitIsDeadOrGhost` pcall'd; a test injects an
--- exact fact. nil = no reader, which reads as "the client tells me nothing"
--- and fails the `OnAuraAbsent` gate OPEN.
Rows.liveness = nil

--- The unit tokens `OnAuraAbsent` may probe for the death gate. A row's
--- `unitToken` is a sweep token ("player", "target" -- the tokens
--- Core/Reconcile.lua sweeps, "focus"/"mouseover" the day it grows them); a
--- cast-target string ("Vile Poacher") names no unit, and a `partyN`/`raidN`
--- target token is OUT OF SCOPE: Rows has no token resolver, so a row whose
--- target it cannot point at keeps today's behaviour (the break fires).
Rows.LIVENESS_TOKENS = { player = true, target = true, focus = true,
    mouseover = true }

-- ------------------------------------------------------------------- pool --
--- A fresh, fixed-shape row. Allocating only on a genuinely new (spell,
--- target) pair is the whole allocation story: the draw pass allocates nothing
--- (PLAN §3.4).
local function newRow()
    return {
        name = nil, targetKey = nil, groupKey = nil, id = nil,
        expireAt = 0, drawExpireAt = 0, castTime = 0, total = 0,
        state = Laws.NORMAL, kind = "Default", stacks = 0, removeAt = 0,
        expireMsgAt = 0, hasteFactor = 1, predicted = true, unitToken = nil,
        guid = nil,
        -- The CAST-side identity pair (E5, code-review-4): the token the
        -- cast's target string resolved to, and the plain guid that token
        -- had at the insert. `Rows:TargetIsDead` is the only consumer; the
        -- aura law's `unitToken`/`guid` pair is the adoption key and these
        -- two fields never touch it.
        castToken = nil, castGuid = nil,
        -- The FX_TIMER_EXPIRED bus stamp (review 4 E3): the Sweep fires the
        -- event once, at the moment the window ENDS, and zeroes this so a
        -- re-extended row (an adopt/extend at the last second) can not
        -- announce the same expiry twice. Independent of `expireMsgAt`,
        -- which is the source's col-12 CHAT stamp (the m7 AnnounceExpiry
        -- gate) and is 0 for every row born under the gate's default OFF.
        expiredFired = false,
        maxTime = 0, hiddenSince = 0, alpha = 1, raidMark = 0, tickEvery = nil,
        -- The fade-warning stamp (the original's column 12,
        -- ST_GetFadeTime(spell) at the st:insert sites :888/:937): seconds
        -- before expiry at which this row fires FX_TIMER_FADING once, 0 for
        -- an unregistered spell. Rows:FadeWarnFor's answer at insert; the
        -- Sweep zeroes it when it fires (the `st[i][12] = 0` law,
        -- Forte_Timer.lua:1050).
        fadeWarn = 0,
    }
end

--- The row's fade threshold: FX.Timer.FadeWarnings[spell] (a plain seconds
--- number; the registry is populated by Forte_Messages -- name-keyed,
--- class-agnostic), 0 when unregistered. The ST_GetFadeTime law
--- (Forte_Timer.lua:1590-1603) reads the threshold from the fade message's
--- text; that parse lives with the message (Forte_Messages), the row carries
--- the number.
function Rows:FadeWarnFor(spell)
    local W = FX.Timer.FadeWarnings
    if type(spell) ~= "string" then return 0 end
    local n = W and tonumber(W[spell])
    return (n and n > 0) and n or 0
end

--- The per-target group id (the `CA:GiveID` port, Forte_Casting.lua:680-686:
--- monotonic, per-mob, recycled from live rows). Keyed on the targetKey, which
--- is the cast-target string (design §2: the SENT target string is kept as an
--- opaque key), the resolved unit token once confirmed, or "none" for a self
--- window -- in which case the caller uses a PRIOR_* sentinel instead
--- (Laws.SentinelGroupKey, the :979-985 law).
function Rows:IdFor(targetKey)
    self._ids = self._ids or {}
    local id = self._ids[targetKey]
    if not id then
        id = self.nextId
        self.nextId = self.nextId + 1
        self._ids[targetKey] = id
    end
    return id
end

--- Recycle a target's id when no row of its group survives (spec CA-20).
function Rows:ReleaseId(targetKey)
    if self._ids then self._ids[targetKey] = nil end
end

-- ------------------------------------------------------------------ index --
local function reindex(self)
    wipe(self.byKey)
    for i = 1, self.rows_n do
        local r = self.rows[i]
        if r then self.byKey[Laws.RowKey(r.name, r.targetKey)] = i end
    end
end

--- Close the holes `removeAt` left, keeping the array dense so every pass is a
--- plain 1..n loop.
local function compact(self)
    local n = 0
    local out = self.rows
    for i = 1, self.rows_n do
        local r = out[i]
        if r then
            n = n + 1
            out[n] = r
        end
    end
    for i = n + 1, self.rows_n do out[i] = nil end
    self.rows_n = n
    reindex(self)
end

--- Find a live row by (spell, target) -- the port of `ST_FindSimilarSimple`
--- (:832-841), which matches the spell and the caster identity.
function Rows:Find(name, targetKey)
    local i = self.byKey[Laws.RowKey(name, targetKey)]
    local r = i and self.rows[i]
    if r and r.state <= Laws.REMOVE then return r, i end
    return nil
end

--- Every live row of a spell name into `out` (the aura sweep's lookup: the
--- fact arrives keyed by spell, the rows are keyed by spell+target).
function Rows:AllForName(name, out)
    out = out or {}
    local n = 0
    for i = 1, self.rows_n do
        local r = self.rows[i]
        if r and r.name == name and r.state <= Laws.REMOVE then
            n = n + 1
            out[n] = r
        end
    end
    for i = n + 1, #out do out[i] = nil end
    return out, n
end

--- Append a fully-shaped row and index it. `row` arrives complete.
local function place(self, row)
    local n = self.rows_n + 1
    self.rows[n] = row
    self.rows_n = n
    self.byKey[Laws.RowKey(row.name, row.targetKey)] = n
    return row
end

--- The registry entry a NAME has (the source of the row's DATA FEEDS, the
--- same seam `kind` is read from below). The registry is keyed by name and is
--- built from the generated data, so a feed is never hand-typed here; nil when
--- the spell is not registered, which leaves every feed off the row.
local function feedFor(spell)
    local entries = FX.Timer.Registry and FX.Timer.Registry.entries
    return entries and entries[spell]
end

-- ---------------------------------------------------------------- insert --
--- The insert of a settled own cast (§3.5's `insertFromCast`, the
--- `ST:AddNewTimer` law :888-940 with §3.3's (spell, target) keying).
---
--- `spell` the resolved name, `targetKey` the cast target ("none" for a
--- self/no-target window), `duration` seconds (Registry:BestDuration's
--- answer), `now` the insert instant (GetTime units), `castTime` the cast
--- instant (SETTLE defers the insert, so they differ; the col-2 cast-time
--- value), `hasteFactor` the frozen factor.
---
--- The insert loop's law (:896-935): a same-key row whose expiry matches
--- inside MAXLAG is CORRECTED in place (nothing new is drawn, `exact = true`
--- so no insert happens); a same-key row whose expiry does not match is
--- REMOVED and the row re-inserted (the refresh: a new icon, a new fade,
--- ST-25).
function Rows:InsertFromCast(spell, targetKey, duration, now, castTime,
        hasteFactor, kind)
    if type(spell) ~= "string" or type(duration) ~= "number"
        or duration <= 0 then
        return nil
    end
    targetKey = targetKey or "none"
    hasteFactor = (type(hasteFactor) == "number" and hasteFactor > 0)
        and hasteFactor or 1
    kind = kind or FX.Timer.Registry.KindFor(spell)
    -- The DATA FEED of the registry entry rides the row: the renderer's
    -- tick-mark branch (`UI/Rows.lua`, delta D6) reads `row.tickEvery`, and the
    -- entry -- built from the generated data, keyed by name -- is the only
    -- lawful source of an interval (no spell data is hand-typed in this file).
    -- nil in, nil out: a row of a spell the data gives no period for carries
    -- none, which is what keeps the branch's `every and every > 0` gate closed.
    local entry = feedFor(spell)
    local total = duration * hasteFactor
    local expire = now + total

    local existing, idx = self:Find(spell, targetKey)
    if existing then
        local verdict = Laws.ReconcileVerdict(expire, existing.expireAt)
        if verdict == "adopt" then
            -- :900-905 "exact match, just correct time"
            existing.expireAt = expire
            if math.abs(existing.drawExpireAt - expire) > Laws.MAXLAG then
                existing.total = total
                existing.drawExpireAt = expire
            end
            existing.castTime = castTime or now
            existing.hasteFactor = hasteFactor
            existing.kind = kind
            return existing, "adopted"
        end
        -- :924 `st:remove(i)` -- the window moved by more than MAXLAG: the
        -- old row is dropped (the source removes, it does not fade) and a
        -- fresh row is inserted below.
        self:removeAt(idx)
    end

    local row = newRow()
    row.name = spell
    row.targetKey = targetKey
    row.kind = kind
    row.total = total
    row.expireAt = expire
    row.drawExpireAt = expire
    row.castTime = castTime or now
    row.state = Laws.NORMAL
    row.stacks = 0
    row.removeAt = 0
    row.expireMsgAt = (self.options and self.options.expireMessage) and 1 or 0
    row.hasteFactor = hasteFactor
    row.predicted = true
    row.unitToken = nil
    row.alpha = 1
    row.hiddenSince = 0
    row.raidMark = 0
    row.tickEvery = entry and entry.tickEvery
    row.fadeWarn = self:FadeWarnFor(spell)
    row.id = self.nextId
    self.nextId = self.nextId + 1
    row.groupKey = (targetKey == "none")
        and Laws.SentinelGroupKey(kind) or self:IdFor(targetKey)
    place(self, row)
    return row, existing and "refreshed" or "inserted"
end

--- The insert of a *confirmed* aura (the `ST_ScanForMissing` (:1103),
--- `ST_TargetDebuffs` (:1225-1271) and `ST_PlayerBuffs` (:1272-1351) path): a
--- spell we registered whose real aura the sweep found with no row of its own.
---
--- `guid` is the target unit's GUID as the sweeping unit token reads it
--- (the original's `st[i][11] = guid`, `:1161`) — the row's identity anchor
--- for the death gate of `OnAuraAbsent`. It arrives PLAIN (Core/Reconcile.lua
--- has run it through PlainOrNil): a secret identity arrives nil and the row
--- simply carries no guid, which fails the gate open.
function Rows:InsertFromAura(spell, targetKey, expire, total, stacks,
        unitToken, raidMark, now, guid)
    if type(spell) ~= "string" then return nil end
    if type(expire) ~= "number" or type(total) ~= "number" or total <= 0 then
        return nil
    end
    targetKey = targetKey or "none"
    now = now or GetTime()
    local existing = self:Find(spell, targetKey)
    if existing then
        local verdict = self:OnAuraFact(existing, expire, total, stacks, now,
            unitToken, raidMark, guid)
        return existing, verdict
    end
    local row = newRow()
    local entry = feedFor(spell)
    row.name = spell
    row.targetKey = targetKey
    row.kind = FX.Timer.Registry.KindFor(spell)
    row.tickEvery = entry and entry.tickEvery
    row.total = total
    row.expireAt = expire
    row.drawExpireAt = expire
    row.castTime = now
    row.state = Laws.NORMAL
    row.stacks = (type(stacks) == "number" and stacks) or 0
    row.expireMsgAt = 0
    row.predicted = false
    row.unitToken = unitToken
    row.guid = (type(guid) == "string") and guid or nil
    row.raidMark = (type(raidMark) == "number" and raidMark) or 0
    row.fadeWarn = self:FadeWarnFor(spell)
    row.id = self.nextId
    self.nextId = self.nextId + 1
    row.groupKey = (targetKey == "none")
        and Laws.SentinelGroupKey(row.kind) or self:IdFor(targetKey)
    place(self, row)
    return row, "inserted"
end

-- ------------------------------------------------------------- reconciliation
--- The fact half of the law (§3.5's `onAuraFact`, the :1159-1207 quotes).
--- `factExpire`/`factTotal`/`stacks` arrive PLAIN: Core/Reconcile.lua has
--- already run every field through PlainOrNil and dropped a secret read
--- entirely (a secret read never overwrites known state).
---
---  adopt   |fact - row.expireAt| <= MAXLAG (:900-905, :1159-1164): the fact IS
---           the prediction. Fill the row in: the window, the stacks, the
---           target identity; the row stops being a prediction.
---  extend  the fact is longer (:1184 `if expire > st[i][1] ... then
---           st[i][1] = expire`) -- `total` is NOT rewritten, the source line.
---  refresh shorter by more than MAXLAG (:924, ST-25): fade the row REMOVED
---           (it keeps drawing, fading out) and insert a fresh row with the
---           fact's window, marked confirmed.
---
--- `unitToken`/`raidMark`/`guid` are the identity the confirming read saw
--- (the original's col 27/19/11, `:1159-1164`: "the row is FILLED IN (guid,
--- group id, raid mark)" at the adopt). All three arrive PLAIN; a secret half
--- arrives nil and simply does not fill in. The guid is the row's identity
--- anchor for the death gate of `OnAuraAbsent` — stamped once, never
--- rewritten by a later row of a different unit under the same key.
function Rows:OnAuraFact(row, factExpire, factTotal, stacks, now,
        unitToken, raidMark, guid)
    if not row then return nil end
    if type(factExpire) ~= "number" then return nil end
    now = now or GetTime()
    local verdict, delta = Laws.ReconcileVerdict(factExpire, row.expireAt)
    if verdict == "adopt" then
        row.expireAt = factExpire
        row.predicted = false
        if type(guid) == "string" and type(row.guid) ~= "string" then
            row.guid = guid
        end
        if type(factTotal) == "number" and factTotal > 0 then
            row.total = factTotal
        end
        if math.abs(row.drawExpireAt - factExpire) > Laws.MAXLAG then
            row.drawExpireAt = factExpire
        end
        if type(stacks) == "number" then row.stacks = stacks end
        if type(unitToken) == "string" then row.unitToken = unitToken end
        if type(raidMark) == "number" then row.raidMark = raidMark end
        return "adopt", delta
    elseif verdict == "extend" then
        row.expireAt = factExpire
        row.predicted = false
        if type(stacks) == "number" then row.stacks = stacks end
        if type(unitToken) == "string" then row.unitToken = unitToken end
        return "extend", delta
    end
    -- refresh (:924 + the ST-25 law "the row is removed and re-inserted: new
    -- icon, new fade")
    self:Fade(row, Laws.REMOVE, now)
    local fresh = newRow()
    fresh.name = row.name
    fresh.targetKey = row.targetKey
    fresh.kind = row.kind
    fresh.total = (type(factTotal) == "number" and factTotal > 0)
        and factTotal or math.max(0, factExpire - now)
    fresh.expireAt = factExpire
    fresh.drawExpireAt = factExpire
    fresh.castTime = now
    fresh.state = Laws.NORMAL
    fresh.predicted = false
    fresh.stacks = (type(stacks) == "number" and stacks) or 0
    fresh.hasteFactor = row.hasteFactor
    -- The data feed rides the (spell, target) pair like the kind and the haste
    -- factor: the refreshed row is the same window on the same unit, so its
    -- tick-mark schedule (the renderer's `row.tickEvery`, delta D6) is the old
    -- row's -- and the row's is the registry entry's, read at its insert.
    fresh.tickEvery = row.tickEvery
    fresh.expireMsgAt = 0
    -- "the row is removed and re-inserted: new icon, new fade" (ST-25, the
    -- law this refresh site quotes): a re-applied CC gets a fresh
    -- fade-warning stamp, exactly the insert law.
    fresh.fadeWarn = self:FadeWarnFor(row.name)
    fresh.id = self.nextId
    self.nextId = self.nextId + 1
    fresh.groupKey = (row.targetKey == "none")
        and Laws.SentinelGroupKey(row.kind) or self:IdFor(row.targetKey)
    if type(unitToken) == "string" then fresh.unitToken = unitToken end
    if type(raidMark) == "number" then fresh.raidMark = raidMark end
    -- The identity anchor rides the (spell, target) key, not the row: the
    -- refreshed row faces the same unit the old one did, and a confirming
    -- read of that unit is the better answer.
    fresh.guid = (type(guid) == "string") and guid or row.guid
    -- The cast-side pair rides with it (the same law: it describes the
    -- (spell, target) pair, and the liveness gate reads it only when no aura
    -- guid has arrived for the row).
    fresh.castToken, fresh.castGuid = row.castToken, row.castGuid
    -- The refreshed row owns the (spell, target) key from now on; the old row
    -- stays in the array fading out, outside the index.
    self.byKey[Laws.RowKey(row.name, row.targetKey)] = nil
    place(self, fresh)
    return "refresh", delta
end

--- Is the unit-identity read (the `UnitGUID` the gate compares) known to come
--- back secret RIGHT NOW? `C_Secrets.ShouldUnitIdentityBeSecret()` is the
--- catalog's own mode query (pinned 1.60.1.70532,
--- `C_Secrets`/`ShouldUnitIdentityBeSecret`; the same family
--- Forte_Core/Core/Compat.lua caches as `aurasSecret`/`cooldownsSecret`),
--- pcall'd with the answer passed through PlainOrNil. The SecretState
--- consumer law: ONLY a plain `true` answers "sealed" -- an absent API, a
--- raise, a secret answer and `false` all answer "not known sealed", and the
--- guid comparison below decides. It exists so the sealed case is an explicit
--- law with a name, never an accident of a nil compare; like every mode read
--- it never suppresses anything (a sealed identity FAILS THE GATE OPEN).
local function identityIsSealed()
    local query = _G.C_Secrets and _G.C_Secrets.ShouldUnitIdentityBeSecret
    if type(query) ~= "function" then return false end
    local ok, secret = pcall(query)
    if not ok then return false end
    return FX.Compat.PlainOrNil(secret) == true
end

--- The source's liveness gate of the break site, verbatim in shape
--- (`Forte_Timer.lua:1207-1211`):
---
---   elseif st[i][10] == 1 and (st[i][1]==0 or st[i][1]-t>maxlag) then
---       if not UnitIsDead(unit) then
---           ST_BreakMessages(st[i][4], st[i][19], spell_name);
---       end
---       ST:Fade(i, REMOVE);
---
--- A CC row whose unit is confirmed DEAD does not announce a break: a
--- CC that drops because the target died is the kill, not a break. The row is
--- faded exactly as before, in both branches.
---
--- "Confirmed" is the identity PAIR, and which pair is consulted follows the
--- law that stamped the row: a row whose `guid` the aura law set (the
--- original's col 11, stamped only by the confirming read) is answered by
--- `unitToken`/`guid`; a row nothing has confirmed yet is answered by the pair
--- the CAST stamped (`castToken`/`castGuid`, Core/Casts.lua's Pump -- the
--- token the cast's target string resolved to and the guid that token had at
--- the insert). A bare `unitToken` is no pair: the cast promotes it with no
--- identity read behind it. Either way the token's PLAIN `UnitGUID` must
--- PLAIN-equal the row's PLAIN guid, and the same token's PLAIN liveness must
--- say dead (`UnitIsDead` -- the source's call -- or `UnitIsDeadOrGhost`, which
--- also catches a released spirit; the ghost half is the project's addition,
--- the source's own `UnitIsDead` includes feign death).
---
--- FAIL-OPEN LAW: anything short of that pair -- no identity stamped at all,
--- no liveness reader, a token outside `LIVENESS_TOKENS`, a sealed unit
--- identity, a secret/absent guid on either side, a guid of a different unit, a
--- raising read, a secret liveness answer -- returns false and the break FIRES
--- AS IT DID BEFORE THIS GATE EXISTED. The asymmetry is deliberate: a missed
--- break is a missing sound, a false one shouts about a break that never
--- happened.
function Rows:TargetIsDead(row)
    if type(row) ~= "table" then return false end
    local token, rowGuid
    if type(row.guid) == "string" then
        -- The aura law has confirmed this row: its pair is the answer.
        token, rowGuid = row.unitToken, row.guid
    else
        -- Nothing has confirmed it: the cast-time pair, if the cast knew the
        -- unit. (`row.unitToken` alone is no pair: the cast's token promotion
        -- sets it without any identity read.)
        token, rowGuid = row.castToken, row.castGuid
    end
    if type(token) ~= "string"
        or not (self.LIVENESS_TOKENS and self.LIVENESS_TOKENS[token]) then
        return false
    end
    if identityIsSealed() then return false end
    local probe = self.liveness
    if type(probe) ~= "function" then return false end
    local ok, guid, dead, ghost = pcall(probe, token)
    if not ok then return false end
    guid = FX.Compat.PlainOrNil(guid)
    rowGuid = FX.Compat.PlainOrNil(rowGuid)
    if type(guid) ~= "string" or type(rowGuid) ~= "string" then return false end
    if guid ~= rowGuid then return false end
    dead = FX.Compat.PlainOrNil(dead)
    ghost = FX.Compat.PlainOrNil(ghost)
    return dead == true or ghost == true
end

function Rows:OnAuraAbsent(row, now)
    if not row then return nil end
    now = now or GetTime()
    if now < Laws.CheckableAt(row.castTime, row.total) then
        return "grace"
    end
    if Laws.RemovalRefused(row.expireAt, now) then
        return "refused"
    end
    -- The early break (the ST_BreakMessages site, Forte_Timer.lua:1207-1211:
    -- the absence fact with more than MAXLAG of window left is the CC
    -- breaking, and that branch is the original's break-message call). The
    -- original wraps that call in `if not UnitIsDead(unit) then` (:1208) --
    -- the gate is ported as `Rows:TargetIsDead` above, on the row's identity
    -- (token + guid) instead of the source's loop variable, and it fails
    -- open: with nothing readable to say so, a kill that dropped the aura
    -- fires BROKEN, exactly the behaviour this file had before. The
    -- renderer of the break message/sound is Forte_Messages.
    if not self:TargetIsDead(row) and FX.Fire
        and not isSynthetic(row) then
        FX.Fire(FX.EVENTS.TIMER_BROKEN, row.name, row.targetKey, row.kind)
    end
    self:Fade(row, Laws.REMOVE, now)
    return "removed"
end

-- ------------------------------------------------------------- the machine --
--- `ST:Fade` (:1008-1017): stamp col 17 with now and col 14 with the mode; an
--- already-IGNORE row goes to zero instantly.
function Rows:Fade(row, mode, now)
    if not row then return end
    now = now or GetTime()
    if row.state == Laws.IGNORE then
        row.expireAt = 0
    elseif row.state ~= mode then
        row.removeAt = now
        row.state = mode
    end
end

--- One logic sweep: `ST_UpdateSpellTimers` (:1038-1077) as a port --
--- smoothing, the expiry message, the NORMAL -> FADING promotion and the
--- delete of a spent row. Deleting here is the source's own discipline
--- ("preferably only remove timers in this function and not outside", :1038).
function Rows:Sweep(now)
    local opts = self.options or {}
    local smooth = opts.smooth or Laws.SMOOTH
    local i = 1
    while i <= self.rows_n do
        local row = self.rows[i]
        if not row then
            i = i + 1
        else
            local remaining = row.expireAt - now
            -- :1046, the smoothing law
            row.drawExpireAt = Laws.Smooth(row.drawExpireAt, row.expireAt,
                smooth)
            -- The fade warning (ST_UpdateSpellTimers :1049-1056 verbatim in
            -- shape: `st[i][12] > 0 and timeleft <= st[i][12] and
            -- t14<=NORMAL` -> stamp to 0 (once) -> the message + the bell).
            -- The message/sound renderers live in Forte_Messages (it owns
            -- the sounds and the legality gate); this pass fires the bus
            -- event and nothing else. The raid-icon prefix of :1051 is a
            -- delta we do not port: the event carries the plain row fields
            -- (the shared FX_TIMER_FADING contract).
            if row.fadeWarn > 0 and remaining <= row.fadeWarn
                and row.state <= Laws.NORMAL then
                row.fadeWarn = 0
                -- TEST MODE SILENCE (`/fx test`, Forte_Core/Core/TestMode.lua):
                -- the tag is on OUR row table, and the consumer that speaks to
                -- the world (Forte_Messages renders FX_TIMER_FADING into a chat
                -- line + a bell) must not hear for a made-up row. The row's own
                -- machine -- the stamp, the fade, the draw -- runs untouched, so
                -- the demo panel behaves exactly like a live one.
                if FX.Fire and not isSynthetic(row) then
                    FX.Fire(FX.EVENTS.TIMER_FADING, row.name, row.targetKey,
                        row.kind, remaining)
                end
            end
            -- :1049-1056, the expire message (col 12 stamps once -> 0)
            if row.expireMsgAt > 0 and remaining <= row.expireMsgAt
                and row.state <= Laws.NORMAL then
                row.expireMsgAt = 0
                -- The CHAT leg of the pair: `opts.onExpire` is the module's
                -- `announceExpiry`, a printed line. Silenced for a synthetic
                -- row by the same law as the fires above.
                if opts.onExpire and not isSynthetic(row) then
                    FX.Timer.NotifyExpiry = (FX.Timer.NotifyExpiry or 0) + 1
                    opts.onExpire(row)
                end
            end
            -- THE EXPIRY EVENT (review 4 E3): `FX_TIMER_EXPIRED` is fired
            -- HERE, at the Timer's own expiry site, and nowhere else. The
            -- subscriber that renders it is Forte_Messages, which used to
            -- install a wrapper over `opts.onExpire` at ITS enable -- a seam
            -- the real enable order never reached (Forte_Messages enables
            -- before Forte_Timer builds `options`, and a Timer re-enable
            -- rebuilds the table), so the whole "Timer Expiry" group was dead
            -- on the client while the tests, firing the event by hand, stayed
            -- green. Firing at the fact makes the enable order irrelevant.
            -- Independent of the CHAT gate above (m7's AnnounceExpiry): the
            -- bus event always rides a true expiry, and the subscriber's own
            -- rows (`ExpireEnable`/`TimerExpire*`/`ExpireAnnounce*`, all
            -- opt-in) decide whether anything is heard. `FX.Fire` is
            -- nil-guarded; the payload is the row's plain fields.
            if not row.expiredFired and remaining <= 0
                and row.state <= Laws.NORMAL then
                row.expiredFired = true
                -- The stamp is set either way (a re-extended row can not
                -- announce the same expiry twice), and a synthetic row says
                -- nothing out loud: Forte_Messages' whole "Timer Expiry" group
                -- -- its chat rows, its sounds, its announces -- rides this
                -- fire, and test mode sends no chat.
                if FX.Fire and not isSynthetic(row) then
                    FX.Fire(FX.EVENTS.TIMER_EXPIRED, row.name, row.targetKey,
                        row.kind)
                end
            end
            if row.state == Laws.IGNORE then
                -- :1058-1063 an ignored row dies at zero
                if remaining <= 0 then
                    self:removeAt(i)
                else
                    i = i + 1
                end
            elseif row.state == Laws.NORMAL then
                -- :1064-1068 promote at expiry; the type picks instant vs fade
                if remaining <= 0 and row.total > 0 then
                    local mode = Laws.INSTANT_FADE[row.kind]
                        and Laws.FADING_INSTANT or Laws.FADING
                    self:Fade(row, mode, now)
                end
                i = i + 1
            else
                -- :1070-1076 keep a faded row for its band, then delete it
                if Laws.DeathAt(row.removeAt, row.kind) < now then
                    self:removeAt(i)
                else
                    i = i + 1
                end
            end
        end
    end
    if self._dirty then
        self._dirty = nil
        compact(self)
    end
end

function Rows:removeAt(i)
    local row = self.rows[i]
    if not row then return end
    self.rows[i] = nil
    self._dirty = true
    if self.byKey[Laws.RowKey(row.name, row.targetKey)] == i then
        self.byKey[Laws.RowKey(row.name, row.targetKey)] = nil
    end
end

--- Close the holes `removeAt` left, on demand. `Sweep` runs this at its tail,
--- so the panel needs no caller that knows about `_dirty`; this is the seam for
--- a caller that removes rows OUT of the sweep -- the `/fx test` scrub
--- (Forte_Timer/Module.lua) is the one today -- and must not leave a hole for
--- the next `Sorted` pass to walk past.
function Rows:Compact()
    if not self._dirty then return 0 end
    local before = self.rows_n
    self._dirty = nil
    compact(self)
    return before - self.rows_n
end

--- Drop every row: the leave-world / class-change purge (the original's
--- leave-combat purge :2880-2884, the queue erase :776-777).
function Rows:Clear()
    for i = 1, self.rows_n do self.rows[i] = nil end
    self.rows_n = 0
    wipe(self.byKey)
    self._ids = nil
    self._dirty = nil
end

-- ------------------------------------------------------------- the link pass --
--- The sort's option pair, module scope, refreshed at the top of every
--- `Rows:Sorted` (docs/perf.md §4 fix 5). They live here, not in the
--- comparator's enclosing expression, so the comparator below is a CONSTANT
--- function: `table.sort` is handed the one function this file was loaded
--- with, so a 25 Hz pass creates zero closures even at 0 rows (the closure the
--- inline form allocated was part of the 0-row GC floor). The shape is the
--- Timeline's: `Forte_Cooldown/Core/Engine.lua:536-539` hands table.sort a
--- comparator that reads nothing from the call site.
local sortGrouping = true
local sortOutwands = true

--- The comparator: `Laws.CompareLinks` with the two option halves already
--- resolved, so the law itself stays the single source.
local function compareLinks(a, b)
    return Laws.CompareLinks(a, b, sortGrouping, sortOutwands)
end

--- The link pass's option pair, read back by the tests that prove the sort
--- order rides the options and not a captured closure.
function Rows:SortOptions()
    return sortGrouping, sortOutwands
end

--- The draw pass's bookkeeping, the port of :2140-2241: build the link table
--- (row index, group key, drawn expire, visibility, hide-gate stamp, scale),
--- sort it, then apply the per-instance visible cap and the time-band
--- compression. Returns the reused link array plus its length: the renderer
--- takes the index array and touches no allocation (PLAN §3.4).
function Rows:Sorted(out, now)
    out = out or self.links
    local opts = self.options or {}
    -- The comparator's options, resolved here (fix 5) — the hoisted
    -- `compareLinks` reads these module-scope values.
    sortGrouping = opts.groupID ~= false
    sortOutwands = opts.outwands ~= false
    local n = 0
    for i = 1, self.rows_n do
        local row = self.rows[i]
        if row then
            n = n + 1
            local link = out[n]
            if not link then link = {}; out[n] = link end
            link[1] = i
            link[2] = row.groupKey
            link[3] = row.drawExpireAt
            link[6] = row.maxTime
            link[7] = row.hiddenSince
            -- the visibility of this row (:2146-2168 + the HideLonger gate);
            -- the gate's trip stamp rides the row (link col 7)
            opts.hiddenSince = row.hiddenSince
            local a = Laws.GateAlpha(row.state, row.expireAt, row.removeAt,
                now, opts)
            row.hiddenSince = opts.hiddenSince
            row.alpha = a
            link[4] = a
            link[5] = row.hiddenSince
        end
    end
    for i = n + 1, #out do out[i] = nil end
    table.sort(out, compareLinks)

    -- the visible cap (:2192 `(not s.Max[0] or visible < s.Max[1]) and
    -- links[k][4] > 0`) + the time-band target (:2195-2212)
    local visible = 0
    local highest = 0
    local cap = (opts.maxTimeOn ~= false) and (opts.maxTime or Laws.MAXTIME)
    for k = 1, n do
        local link = out[k]
        local row = self.rows[link[1]]
        if (not opts.maxOn or visible < (opts.maxRows or 15)) and link[4] > 0 then
            visible = visible + 1
            if opts.oneMax ~= false and not opts.forceMax then
                if row.total > highest then
                    highest = math.min(cap or math.huge, row.total)
                end
            elseif opts.oneMax == false and not opts.forceMax then
                link[6] = math.min(cap or math.huge, row.total)
            end
        else
            link[4] = 0
            row.alpha = 0
        end
    end
    -- :2228-2241, the scale easing: links[k][6] += (target - links[k][6])/smooth
    local smooth = opts.smooth or Laws.SMOOTH
    for k = 1, n do
        local link = out[k]
        local row = self.rows[link[1]]
        if link[4] == 1 then
            local target
            if opts.forceMax then
                target = cap
            elseif opts.oneMax == false then
                target = math.min(cap or math.huge, row.total)
            else
                target = highest
            end
            link[6] = link[6] + (target - link[6]) / smooth
        end
        row.maxTime = link[6]
    end
    return out, n
end

function Rows:Count()
    local n = 0
    for i = 1, self.rows_n do if self.rows[i] then n = n + 1 end end
    return n
end
