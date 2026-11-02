-- addon/Forte_Timer/Core/Casts.lua
-- FX.Timer.Casts: the own-cast feed -- the port of the original's
-- `CA_SelfQueue` (Forte_Casting.lua:40, the record schema :225-240) reduced to
-- what a Spell Timer row needs (design §4.1). This is the v1 SPINE: every row
-- the panel shows is born here, from our own cast events (owner ruling,
-- PLAN.md:549).
--
-- The four signals (all catalog-cited in docs/design-spell-timer.md §4.1, all
-- `SecretWhenUnitSpellCastRestricted`; the event names are in the pinned
-- Forever catalog and api_lint-checked):
--
--   UNIT_SPELLCAST_SENT        (unitTarget, target:cstring ConditionalSecret,
--                              castGUID, spellID)  @UnitDocumentation.lua:4802
--        the TARGET CAPTURE. The target string is kept as an OPAQUE key
--        (never compared, never arithmetic) and resolved only when plain.
--   UNIT_SPELLCAST_SUCCEEDED   (unitTarget, castGUID, spellID, castBarID
--                              NeverSecret)        @:4844
--        the settle: the row is inserted SETTLE (0.2 s) LATER, never on the
--        event itself (the original defers, Forte_Casting.lua:514-518; spec
--        CA-04).
--   UNIT_SPELLCAST_FAILED      @:4713  and
--   UNIT_SPELLCAST_INTERRUPTED @:4741  the CANCEL_SETTLE (0.5 s,
--        Forte_Casting.lua:344) band: move the row into the FAILED state
--        (Fail colour, FailTime) WITHOUT naming a cause (spec CA-08: the
--        resist/immune/reflect classification is log-only, impossible here).
--
-- Queue hygiene, verbatim: a fresh SENT evicts the records of a cast that
-- never started (`CA_SelfSent`'s "garbage sent" sweep,
-- Forte_Casting.lua:565-575); an unfired record is flushed after QUEUE_FLUSH
-- (3 s, Forte_Casting.lua:602-611); the queue is erased on PLAYER_LEAVING_WORLD
-- / PLAYER_DEAD (:776-777).
--
-- Secret law: the payload `spellID` is classified through
-- `FX.Compat.PlainOrNil` and only ever LOOKED UP (pcall'd: a tainted-argument
-- lookup may raise); the target string rides the same rule. No comparison, no
-- arithmetic, no tostring, no truth test on a raw payload value. A secret
-- spellID creates no row and is counted (launch-day probe P1 -- the counters
-- ride FX.db.diag.timerCasts, printed by /fx status).
--
-- Name resolution FIRST (`C_Spell.GetSpellInfo(spellID).name`, the
-- Forte_Cooldown/Module.lua:65-69 isKnown precedent), then the NAME is the key:
-- ids drift per build (PLAN §8), names do not.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Timer = FX.Timer or {}

local Casts = {}
FX.Timer.Casts = Casts

local Laws = FX.Timer.Laws

--- The in-flight cast records (the CA_SelfQueue port).
Casts.queue = {}
--- The deferred work (the SETTLE / CANCEL_SETTLE band).
Casts.pending = {}
--- The instrument (PLAN §8 mitigation 1).
Casts.status = { seen = 0, plain = 0, secret = 0, resolved = 0,
    unresolved = 0, rows = 0, untracked = 0, evicted = 0, flushed = 0,
    failed = 0 }
Casts.rows = nil
Casts.options = nil
--- The injectable seams (tests).
Casts.resolveName = nil
Casts.now = nil
Casts.hasteProbe = nil
Casts.settle = nil
Casts.cancelSettle = nil
Casts.flushAfter = nil
--- Called as `onRow(row, verdict)` after a row lands, so the Module can kick
--- the renderer synchronously (a HIDDEN frame never receives OnUpdate -- the
--- live uiforever finding of 2026-11-02).
Casts.onRow = nil

--- The `inCombat` sample (InCombatLockdown, the project's law for it,
--- Forte_Cooldown/Module.lua:311).
local function inCombat()
    if type(InCombatLockdown) == "function" then
        local ok, v = pcall(InCombatLockdown)
        return (ok and v) and true or false
    end
    return false
end
Casts.InCombat = inCombat

--- The name half of a payload spellID: pcall the lookup, pass the result's
--- `name` field through PlainOrNil, accept only a plain string. Never a raw
--- comparison on the id; the info table's truth test stays inside the
--- protected call (the Forte_Cooldown/Module.lua:326-334 law).
function Casts:NameOf(spellID)
    local resolved
    if self.resolveName then
        resolved = self.resolveName(spellID)
    elseif C_Spell and C_Spell.GetSpellInfo then
        local ok, value = pcall(function()
            local info = C_Spell.GetSpellInfo(spellID)
            return info and FX.Compat.PlainOrNil(info.name)
        end)
        resolved = ok and value or nil
    end
    if type(resolved) ~= "string" or resolved == "" then return nil end
    -- H1 Localization: the row key space is the generated data's English
    -- names, so the client's localized cast name canonicalizes back to it
    -- (identity on enUS, where no aliases exist). The localized name still
    -- resolves in the Registry through ITS alias table, so a row keyed by
    -- the English name reaches the localized name's kind (`KindFor`).
    if FX.Locale then return FX.Locale.CanonicalName(resolved) end
    return resolved
end

function Casts:Clock()
    if self.now then return self.now() end
    return GetTime()
end

--- The target resolver, the port of `CA_CastOn` (spec CA-19): match the plain
--- string against the token list "target targettarget focus focustarget pet
--- pettarget", keep only a live, living unit, and AMBIGUITY means the row
--- stays unconfirmed (the original returns ""). Every read passes PlainOrNil;
--- the string itself is only ever an index key, never a value we compute on.
local TOKENS = { "target", "targettarget", "focus", "focustarget", "pet",
    "pettarget" }
function Casts:ResolveTarget(targetString)
    if type(targetString) ~= "string" or targetString == "" then return nil end
    if type(UnitExists) ~= "function" or type(UnitName) ~= "function" then
        return nil
    end
    local found, ambiguous = nil, false
    for _, token in ipairs(TOKENS) do
        local ok, exists = pcall(UnitExists, token)
        if ok and FX.Compat.PlainOrNil(exists) then
            local okD, dead = pcall(UnitIsDead, token)
            local plainDead = okD and FX.Compat.PlainOrNil(dead)
            local okN, name = pcall(UnitName, token)
            local plainName = okN and FX.Compat.PlainOrNil(name)
            if type(plainName) == "string" and plainName == targetString
                and plainDead ~= true then
                if found ~= nil then ambiguous = true end
                found = token
            end
        end
    end
    if ambiguous then return nil end
    return found
end

--- The live instrument table (FX.db.diag.timerCasts, cumulative across sessions
--- like Forte_Cooldown's cast counters; session-local when SavedVariables
--- never arrived).
function Casts:InitStatus()
    local d
    if FX.db then
        FX.db.diag = FX.db.diag or {}
        if type(FX.db.diag.timerCasts) ~= "table" then
            FX.db.diag.timerCasts = {}
        end
        d = FX.db.diag.timerCasts
    else
        d = self.status
    end
    for _, k in ipairs({ "seen", "plain", "secret", "resolved", "unresolved",
        "rows", "untracked", "evicted", "flushed", "failed" }) do
        if type(d[k]) ~= "number" then d[k] = 0 end
    end
    self.status = d
    return d
end

function Casts:Init(rows, options)
    self.rows = rows
    self.options = options
    self.settle = self.settle or Laws.SETTLE
    self.cancelSettle = self.cancelSettle or Laws.CANCEL_SETTLE
    self.flushAfter = self.flushAfter or Laws.QUEUE_FLUSH
    self:InitStatus()
end

-- ---------------------------------------------------------------- SENT ----
--- The target capture. `target` arrives from the payload; it is
--- ConditionalSecret, so it passes PlainOrNil before it is used as anything,
--- and it is only ever a KEY (the row's targetKey), never a compared value.
function Casts:OnSent(target, spellID, now)
    now = now or self:Clock()
    local st = self:InitStatus()
    st.seen = st.seen + 1
    local plainTarget = FX.Compat.PlainOrNil(target)
    if FX.Compat.PlainOrNil(spellID) ~= nil then
        st.plain = st.plain + 1
    else
        st.secret = st.secret + 1
    end
    local name = self:NameOf(spellID)
    if type(name) ~= "string" then
        st.unresolved = st.unresolved + 1
        return
    end
    st.resolved = st.resolved + 1
    if not FX.Timer.Registry.IsTracked(name) then
        st.untracked = st.untracked + 1
        return
    end
    -- A fresh SENT evicts the records of casts that never started (the
    -- "garbage sent" sweep, Forte_Casting.lua:565-575).
    local q = self.queue
    for i = #q, 1, -1 do
        if not q[i].started then
            table.remove(q, i)
            st.evicted = st.evicted + 1
        end
    end
    local key
    if type(plainTarget) == "string" and plainTarget ~= "" then
        key = plainTarget
    else
        key = "none"        -- self / no-target, the :979-985 sentinel path
    end
    q[#q + 1] = {
        name = name, targetKey = key, targetString = plainTarget,
        openedAt = now, started = false,
    }
end

--- UNIT_SPELLCAST_START: mark the record as started. The row itself is created
--- by the success; the stamp keeps the eviction sweep honest.
function Casts:OnStart(spellID, now)
    now = now or self:Clock()
    local name = self:NameOf(spellID)
    if type(name) ~= "string" then return end
    for i = 1, #self.queue do
        local rec = self.queue[i]
        if rec.name == name and not rec.started then
            rec.started = true
            rec.castStart = now
            return
        end
    end
end

-- ------------------------------------------------------------ SUCCEEDED ----
--- The settle: the record is consumed now, the row inserted SETTLE seconds
--- later by Pump (never on the event -- CA-04).
function Casts:OnSucceeded(spellID, now)
    now = now or self:Clock()
    local name = self:NameOf(spellID)
    if type(name) ~= "string" then return end
    local rec, idx
    for i = #self.queue, 1, -1 do
        if self.queue[i].name == name then
            rec = self.queue[i]
            idx = i
            break
        end
    end
    if rec then
        table.remove(self.queue, idx)
    else
        -- A lone SUCCEEDED with no SENT: the events are the same family, and
        -- a spell with no target information is a self window -- exactly one
        -- row, the "none" key law (§3.3).
        if not FX.Timer.Registry.IsTracked(name) then return end
        rec = { name = name, targetKey = "none", openedAt = now }
    end
    local duration = FX.Timer.Registry.BestDuration(rec.name)
    if type(duration) ~= "number" or duration <= 0 then return end
    self:_schedule(now + (self.settle or Laws.SETTLE), "insert", rec.name,
        rec.targetKey, duration, now, self:HasteFactor(rec.name))
end

function Casts:_schedule(at, kind, name, targetKey, duration, castTime, haste)
    local p = self.pending
    p[#p + 1] = { at = at, kind = kind, name = name, targetKey = targetKey,
        duration = duration, castTime = castTime, haste = haste }
end

--- The frozen haste factor (design §3.4: the haste PROBE is out-of-combat on
--- Forever, so v1 measures it out of combat, freezes it for the fight, and
--- stores it per row). No live probe is wired (the original's
--- `SetHasted`/`SetDefaultHasted` gate is a per-spell table we do not have);
--- the factor defaults to 1 and the seam exists for the probe.
function Casts:HasteFactor(name)
    self._haste = self._haste or {}
    local probe = self.hasteProbe
    if probe then
        local ok, v = pcall(probe, name)
        local plain = ok and FX.Compat.PlainOrNil(v)
        if type(plain) == "number" and plain > 0 then
            self._haste[name] = plain
            return plain
        end
    end
    return self._haste[name] or 1
end

--- The PLAIN identity of a unit token at the insert instant, for the row's
--- CAST-identity stamp (E5). No game call lives here: the reader is
--- `FX.Timer.Reconcile:TokenGuid`, the one seam the aura path already stamps
--- through (`Reconcile:SweepRow`/`SweepBulk` pass it to `InsertFromAura`), so
--- the cast path and the aura path can not disagree about what a token's
--- identity is, and a test injects the fact once (`Reconcile.liveness`).
--- The gate is the shared one: a token outside `Rows.LIVENESS_TOKENS` and a
--- sealed identity both answer nil, and a nil leaves the row without a cast
--- identity -- which is the fail-open state `Rows:TargetIsDead` documents.
--- The answer feeds `row.castGuid` ONLY: `row.guid` is the adoption key of the
--- aura law and the cast path has no part in it.
function Casts:TokenGuid(token)
    local R = FX.Timer.Reconcile
    if R and R.TokenGuid then return R:TokenGuid(token) end
    return nil
end

--- Run the jobs that are due and flush the stale queue. Rides the module's
--- logic cadence (0.5 s), which is finer than the SETTLE window.
function Casts:Pump(now)
    now = now or self:Clock()
    local p = self.pending
    local keep = 0
    for i = 1, #p do
        local job = p[i]
        if job.at <= now then
            p[i] = nil
            if job.kind == "insert" then
                local row, verdict = self.rows:InsertFromCast(job.name,
                    job.targetKey, job.duration, now, job.castTime, job.haste)
                if row then
                    self:InitStatus()
                    self.status.rows = self.status.rows + 1
                    -- The target string is an opaque key; a plain token match
                    -- promotes the row's unit token (CA-19).
                    local token = self:ResolveTarget(job.targetKey)
                    if token then
                        row.unitToken = token
                        -- E5 (code-review-4): the SAME promotion that makes
                        -- the token legible is what makes the row's identity
                        -- testable. The source's break site reads
                        -- `UnitIsDead(unit)` of the unit its loop is walking
                        -- (`Forte_Timer.lua:1207-1211`); `Rows:TargetIsDead`
                        -- answers that only for a row that carries the
                        -- identity PAIR -- a probeable token AND the plain
                        -- guid that token had at the stamp. Aura rows have
                        -- the pair in `unitToken`/`guid`; a row born from one
                        -- of my own casts had NEITHER, so the common real
                        -- shape of a crowd-control window -- my banish on my
                        -- current target, and the target DIES inside it --
                        -- arrived as a "Broke Early!" raid line plus four
                        -- break sounds.
                        --
                        -- The pair is stamped into the SEPARATE
                        -- `castToken`/`castGuid` fields, which the LIVENESS
                        -- GATE is the only consumer of. `row.guid` is the
                        -- aura law's ADOPTION key (the source's col 11,
                        -- `:1161`): it is set by the aura-confirming read
                        -- (`InsertFromAura`/`OnAuraFact`) and by nothing
                        -- else, because stamping it here would make a
                        -- prediction adoptable by identity and would move
                        -- `row.predicted` -- the UI's prediction marking, the
                        -- §5.5 law -- with it. Stamping costs one guid read
                        -- per row, at the insert: the reader is the aura
                        -- path's own seam (no second reader, no new game call
                        -- in this file), a token outside
                        -- `Rows.LIVENESS_TOKENS` stamps nil, and a SEALED
                        -- identity stamps nil -- the row then keeps today's
                        -- fail-open break. The read is pcall'd: a row that
                        -- cannot be identified is a row with no identity,
                        -- never a job that dies mid-queue.
                        row.castToken = token
                        local identified = { pcall(self.TokenGuid, self, token) }
                        row.castGuid = (identified[1] and identified[2]) or nil
                    end
                    if self.onRow then self.onRow(row, verdict) end
                end
            elseif job.kind == "fail" then
                local faded = 0
                if job.targetKey then
                    local row = self.rows:Find(job.name, job.targetKey)
                    if row then
                        self.rows:Fade(row, Laws.FAILED, now)
                        faded = 1
                    end
                else
                    local all = self.rows:AllForName(job.name)
                    for i = 1, #all do
                        self.rows:Fade(all[i], Laws.FAILED, now)
                        faded = faded + 1
                    end
                end
                if faded > 0 then
                    self:InitStatus()
                    self.status.failed = self.status.failed + faded
                end
            end
        else
            keep = keep + 1
            p[keep] = job
        end
    end
    for i = keep + 1, #p do p[i] = nil end
    local q = self.queue
    for i = #q, 1, -1 do
        if now - q[i].openedAt > (self.flushAfter or Laws.QUEUE_FLUSH) then
            table.remove(q, i)
            self.status.flushed = self.status.flushed + 1
        end
    end
end

--- The fail / interrupt band: settle for CANCEL_SETTLE, then the row goes into
--- the FAILED band. No cause is ever named (CA-08: a resist/immune/reflect
--- classification is log-only and the log is closed).
function Casts:OnFailed(spellID, target, now)
    now = now or self:Clock()
    local name = self:NameOf(spellID)
    if type(name) ~= "string" then return end
    local key
    for i = #self.queue, 1, -1 do
        if self.queue[i].name == name then
            key = self.queue[i].targetKey
            table.remove(self.queue, i)
            break
        end
    end
    -- No queued record (the SUCCEEDED already consumed it, the common case for
    -- an interrupt after the landing): the payload of FAILED/INTERRUPTED carries
    -- NO target, so the fail band is the source's own law (CA_FailTimer
    -- :2601-2634) -- every row of this SPELL gets the flash. `key` stays nil,
    -- which Pump reads as "all rows of this name".
    self:_schedule(now + (self.cancelSettle or Laws.CANCEL_SETTLE), "fail",
        name, key, 0, now, 1)
end

--- The erase (PLAYER_LEAVING_WORLD / PLAYER_DEAD, Forte_Casting.lua:776-777).
function Casts:Erase()
    wipe(self.queue)
    wipe(self.pending)
end

--- The `/fx status` line.
function Casts:StatusLine()
    local s = self.status
    return string.format(
        "Timer casts: seen %d | plain %d | secret %d | unresolved %d | rows %d | untracked %d",
        s.seen, s.plain, s.secret, s.unresolved, s.rows, s.untracked)
end
