-- addon/Forte_Timer/Core/Casts.lua
-- FX.Timer.Casts: the own-cast feed -- the port of the original's
-- `CA_SelfQueue` (Forte_Casting.lua:40, the record schema :225-240) reduced to
-- what a Spell Timer row needs (design §4.1). This is the v1 SPINE: every row
-- the panel shows is born here, from our own cast events (owner ruling,
-- PLAN.md:549).
--
-- The PET feed (wave 2b "PetRows v2", PLAN §11.1) rides the SAME spine: the
-- original harvested the pet's casts from the combat log -- the `FW.pet`
-- branch of `FC_OnEvent` (`/tmp/fxref/Forte_Casting/Forte_Casting.lua:835-855`,
-- the `SPELL_CAST_START`/`SPELL_CAST_SUCCESS`/`SPELL_CAST_FAILED`/
-- `SPELL_MISSED` sweep) -- and published them as the registration seam
-- `CA:RegisterOnPetCastSuccess/Failed/Start` (`Forte_Casting.lua:653-664`),
-- consumed by the Warlock add-on for the Succubus kit
-- (`/tmp/fxref/Forte_Class/Warlock/Warlock.lua:197-219`: Devour Magic /
-- Spell Lock on the SUCCESS, Seduction/Mesmerize on the START, the Seduce
-- message naming `UnitName("pettarget")`). The log is closed on Forever
-- (AGENTS.md, and it is exactly what design §4.1 names as closed here), so the
-- modern feed is the same UNIT_SPELLCAST family registered for the `pet`
-- unit (`frame:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "pet")`), the
-- per-unit registration the family exists for. The target law of the record
-- is the original's token list `FW.Default.UseTokens =
-- "pet pettarget vehicle focus mouseover"` (`Forte_Casting.lua:880`): the
-- pet's own target (`pettarget`) when it is readable, the player's target
-- when it is not (the pet attacks what its master points at), the "none"
-- window last -- the same three-way shape the Seduce message reads.
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
--- The rows a CLASS tracker draws: `[spellName] = { owner = "Shaman",
--- live = fn }` (F-B, 2026-11-02, the totem dedupe). See `DeclareOwnedRows`.
Casts.owners = {}
--- The instrument (PLAN §8 mitigation 1).
Casts.status = { seen = 0, plain = 0, secret = 0, resolved = 0,
    unresolved = 0, rows = 0, untracked = 0, evicted = 0, flushed = 0,
    failed = 0, owned = 0, retired = 0 }
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
        "rows", "untracked", "evicted", "flushed", "failed", "owned",
        "retired" }) do
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

-- ------------------------------------------------- the class slot owners --
--- Declare that a CLASS tracker draws the Spell Timer rows of `names`, and
--- asks for the cast spine to leave those spells alone while its own row is on
--- the panel (F-B, 2026-11-02; the Shaman totem case of PLAN §11.1 T3/F-B).
---
--- The shape of the problem: a Shaman's `Magma Totem` produces TWO signals of
--- ONE window -- the player's own cast of the spell (this spine) and the
--- client's slot state (`PLAYER_TOTEM_UPDATE` + `GetTotemInfo`, which the
--- Forte_Shaman tracker renders as the element-slot row, ported from
--- `/tmp/fxref/Forte_Class/Shaman/Shaman.lua:77-93`, whose `ST.ST:remove(i)`
--- law is "one row per SLOT"). The tracker's in-place replacement can only see
--- rows keyed by the element (`Rows:Find(name, "Fire")`); the cast row is
--- keyed by the cast target (`"none"`, the SENT payload carries no target
--- unit), so the slot row landed BESIDE the prediction: two rows for one totem.
---
--- The dedupe keeps the tracker's row (the read is the confirmed half) and
--- keeps the spine's half where the tracker is blind: a `GetTotemInfo` read the
--- engine seals answers NOTHING (TotemDocumentation.lua:62,
--- `SecretWhenTotemSlotSecret`), and out of a plain read the cast prediction is
--- the only signal a shaman has in combat. So the rule is per spell and per
--- instant, asked of the owner itself:
---
---   the owner's row is on the panel   -> the spine draws nothing  (one row)
---   the owner's row is not            -> the spine draws its prediction
---   the spine's prediction is on first -> `RetireOwnedRows` hands the slot over
---
--- `names` an array of English data names (the cast spine keys on the
--- canonical name, `NameOf`), `owner` a label for the instrument, `isLive(name)`
--- the owner's answer at the instant a cast settles.
function Casts:DeclareOwnedRows(names, owner, isLive)
    if type(names) ~= "table" or type(owner) ~= "string" then return 0 end
    local n = 0
    for _, name in ipairs(names) do
        if type(name) == "string" and name ~= "" then
            self.owners[name] = { owner = owner, live = isLive }
            n = n + 1
        end
    end
    return n
end

--- Forget every declaration of one owner (a tracker being rebuilt).
function Casts:UndeclareOwnedRows(owner)
    local n = 0
    for name, rec in pairs(self.owners) do
        if rec.owner == owner then
            self.owners[name] = nil
            n = n + 1
        end
    end
    return n
end

--- The owner's row for `name` is on the panel right now, so the spine must not
--- draw a second one. A pcall: a tracker that cannot answer is a tracker that
--- is not drawing anything, and the cast row rides (the row we can draw beats
--- the row we hope exists).
function Casts:RowIsOwned(name)
    local rec = type(name) == "string" and self.owners[name] or nil
    if not rec then return false end
    local live = rec.live
    if type(live) ~= "function" then return true end
    local ok, v = pcall(live, name)
    return (ok and v) and true or false
end

--- Hand the window over: the owner (the Shaman slot tracker) is drawing its row
--- for `name`, so the spine's own PREDICTION of the same spell retires --
--- `Shaman.lua:84`'s `ST.ST:remove(i)` law (the slot keeps one row, removed, not
--- faded, so the new icon owns the slot's fade). `keepKey` is the key the
--- owner's row rides (the element token), which is never touched; a row that a
--- plain aura read already CONFIRMED is not ours to remove -- a prediction is
--- the only thing the spine may retire. Returns how many went.
function Casts:RetireOwnedRows(name, keepKey, now)
    if type(name) ~= "string" then return 0 end
    local rows = self.rows
    if not rows then return 0 end
    local keys = {}
    local all, n = rows:AllForName(name)
    for i = 1, n do
        local row = all[i]
        if row.predicted == true and row.targetKey ~= keepKey then
            keys[#keys + 1] = row.targetKey
        end
    end
    if #keys == 0 then return 0 end
    now = now or self:Clock()
    local removed = 0
    for i = 1, #keys do
        local row, idx = rows:Find(name, keys[i])
        if row then
            rows:removeAt(idx)
            removed = removed + 1
        end
    end
    if removed > 0 then
        self:InitStatus()
        self.status.retired = self.status.retired + removed
    end
    return removed
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
    -- A class tracker is drawing this spell's row (the Shaman's element slot,
    -- DeclareOwnedRows): no record, no row, counted. The gate is a snapshot of
    -- the owner's panel at this instant -- the slot's row going empty later is
    -- what lets the NEXT cast through, and a sealed slot read (the owner
    -- drawing nothing) is exactly the state the prediction is for.
    if self:RowIsOwned(name) then
        st.owned = st.owned + 1
        return
    end
    -- A fresh SENT evicts the records of casts that never started (the
    -- "garbage sent" sweep, Forte_Casting.lua:565-575). The sweep is the
    -- SELF feed's: a pet SENT is not a fresh self SENT, and the pet's own
    -- OnPetSent runs the same law over the pet's own records.
    local q = self.queue
    for i = #q, 1, -1 do
        if not q[i].started and not q[i].pet then
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
        openedAt = now, started = false, pet = false,
    }
end

--- UNIT_SPELLCAST_START: mark the record as started. The row itself is created
--- by the success; the stamp keeps the eviction sweep honest. The START is
--- registered for "player" only, so the sweep touches only SELF records: a
--- player START can not stamp the pet's record.
function Casts:OnStart(spellID, now)
    now = now or self:Clock()
    local name = self:NameOf(spellID)
    if type(name) ~= "string" then return end
    for i = 1, #self.queue do
        local rec = self.queue[i]
        if rec.name == name and not rec.started and not rec.pet then
            rec.started = true
            rec.castStart = now
            return
        end
    end
end

-- ------------------------------------------------------------ SUCCEEDED ----
--- The settle: the record is consumed now, the row inserted SETTLE seconds
--- later by Pump (never on the event -- CA-04). `pet` marks the record's
--- feed: the pet's success consumes the PET's record, a self success the
--- SELF's, so a (name-shared) record of one feed can never be eaten by the
--- other feed's event.
function Casts:OnSucceeded(spellID, now, pet)
    now = now or self:Clock()
    local name = self:NameOf(spellID)
    if type(name) ~= "string" then return end
    local rec, idx
    for i = #self.queue, 1, -1 do
        local rec0 = self.queue[i]
        -- The feeds never eat each other's records: the pet's success
        -- consumes a PET record, a self success a SELF one. (Both sides
        -- normalize through `not not`: `false` and `nil` are the same
        -- "self feed" answer and compare unequal in Lua.)
        local sameFeed = (not not rec0.pet) == (not not pet)
        if rec0.name == name and sameFeed then
            rec = rec0
            idx = i
            break
        end
    end
    if rec then
        table.remove(self.queue, idx)
    else
        -- A lone SUCCEEDED with no SENT: the events are the same family, and
        -- a spell with no target information is a self window -- exactly one
        -- row, the "none" key law (§3.3). The pet's window is NOT a self
        -- window: it keys on the pet's target (the PetTargetKey law).
        if not FX.Timer.Registry.IsTracked(name) then return end
        local key = "none"
        if pet then key = self:PetTargetKey() or "none" end
        rec = { name = name, targetKey = key, openedAt = now, pet = pet }
    end
    local duration = FX.Timer.Registry.BestDuration(rec.name)
    if type(duration) ~= "number" or duration <= 0 then return end
    -- The settle half of the same gate (a SUCCEEDED whose SENT never arrived,
    -- and the last word before the row is drawn): the owner's element slot is
    -- on the panel, so one row is already there.
    if self:RowIsOwned(rec.name) then
        self:InitStatus()
        self.status.owned = self.status.owned + 1
        return
    end
    self:_schedule(now + (self.settle or Laws.SETTLE), "insert", rec.name,
        rec.targetKey, duration, now, self:HasteFactor(rec.name))
end

-- ------------------------------------------------------------------ PET ----
--- The row key for a pet cast (the token law of Forte_Casting.lua:880,
--- "pet pettarget ..."; the Seduce message's `UnitName("pettarget")` read,
--- Forte_Class/Warlock/Warlock.lua:214): the PET's target when it is
--- readable, the PLAYER's target when it is not (the pet attacks what its
--- master points at), `nil` when neither answers -- the caller then rides
--- the "none" window law. Every read is pcall'd (a sealed read RAISES) and
--- every answer passes PlainOrNil; the string is only ever a KEY (the row's
--- targetKey), never a value we compute on.
function Casts:PetTargetKey()
    if type(UnitName) ~= "function" then return nil end
    for _, token in ipairs({ "pettarget", "target" }) do
        local ok, name = pcall(UnitName, token)
        local plain = ok and FX.Compat.PlainOrNil(name)
        if type(plain) == "string" and plain ~= "" then return plain end
    end
    return nil
end

--- The pet SENT: the target capture. The payload's target string rides the
--- same law as the self feed's (an OPAQUE key, classified through
--- PlainOrNil, "none" when secret/absent), and the record carries the pet's
--- feed marker so the settle consumes the right one.
function Casts:OnPetSent(target, spellID, now)
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
    -- The tracked-set gate is the class's (the registry built from the
    -- player class's generated data -- the Warlock data's pet kit:
    -- Seduction 6358, Spell Lock 19647, Lash of Pain 11780 ...). An
    -- untracked pet spell (auto-attacks, a kit spell with no window in the
    -- data) creates NOTHING.
    if not FX.Timer.Registry.IsTracked(name) then
        st.untracked = st.untracked + 1
        return
    end
    local q = self.queue
    for i = #q, 1, -1 do
        if not q[i].started and q[i].pet then
            table.remove(q, i)
            st.evicted = st.evicted + 1
        end
    end
    local key
    if type(plainTarget) == "string" and plainTarget ~= "" then
        key = plainTarget
    else
        key = self:PetTargetKey() or "none"
    end
    -- `started` rides false: the pet feed registers no START, so the pet's
    -- own fresh SENT is what evicts an unfired pet record (the same "garbage
    -- sent" law, applied inside the pet's own half of the queue), and the
    -- QUEUE_FLUSH sweep in Pump is the record's 3 s ceiling.
    q[#q + 1] = {
        name = name, targetKey = key, targetString = plainTarget,
        openedAt = now, started = false, pet = true,
    }
end

--- The pet SUCCEEDED: the pet feed registers only SENT/SUCCEEDED (the
--- assignment's set), so no START stamp marks these records started -- the
--- pet's own SENT evicts the pet's stale records, and Pump's QUEUE_FLUSH
--- (the same 3 s law, Forte_Casting.lua:602-611) is the record's ceiling.
function Casts:OnPetSucceeded(spellID, now)
    self:OnSucceeded(spellID, now, true)
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
---
--- Slot 2 is the caller's SOURCE KEY, not a target: the Module hands the
--- FAILED/INTERRUPTED payload's castGUID into it (Module.lua:682,685 -- that
--- family carries no target at all), and the band keys its rows off the
--- targetKey of its OWN queued record, so nothing here reads it. `_sourceKey`
--- says so (code-review-5 m3: a parameter named `target` on a slot that
--- receives a GUID is the contract-lie class this review exists to catch --
--- the name is the documentation of a slot a reader will otherwise trust).
function Casts:OnFailed(spellID, _sourceKey, now)
    now = now or self:Clock()
    local name = self:NameOf(spellID)
    if type(name) ~= "string" then return end
    local key
    for i = #self.queue, 1, -1 do
        -- The FAILED/INTERRUPTED registrations are the "player" half of the
        -- family: the band consumes a SELF record only, never the pet's.
        if self.queue[i].name == name and not self.queue[i].pet then
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
    local line = string.format(
        "Timer casts: seen %d | plain %d | secret %d | unresolved %d | rows %d | untracked %d",
        s.seen, s.plain, s.secret, s.unresolved, s.rows, s.untracked)
    -- The class slot owners (DeclareOwnedRows): casts the spine left to a
    -- tracker's row, and predictions a tracker's row retired. Quiet while it is
    -- all zero, which is every non-shaman session.
    if (s.owned or 0) > 0 or (s.retired or 0) > 0 then
        line = line .. string.format(
            " | slot rows %d, retired %d", s.owned or 0, s.retired or 0)
    end
    return line
end
