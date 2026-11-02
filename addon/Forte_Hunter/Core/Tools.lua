-- addon/Forte_Hunter/Core/Tools.lua
-- FX.Hunter.Tools: two independent Hunter trackers, no on-screen UI.
--
-- 1. Aspect tracker -- Hunter aspects are mutually exclusive stance-like
--    buffs. Buff reads are secret in combat, so in-combat state is
--    cast-PREDICTED (our own UNIT_SPELLCAST_SUCCEEDED names, PLAN §3.2) and
--    out-of-combat a plain aura read over the aspect list reconciles (and
--    corrects) the prediction. The aspect list is DERIVED from the generated
--    ForteXorcist.Data.Hunter table by the name pattern "^Aspect of" --
--    never hard-coded spell IDs.
--
-- 2. Ranged swing / Auto Shot timer. Verified Forever contract (docs/api
--    catalog, SwingTimerDocumentation.lua:42/53, see docs/hunter-tools.md):
--      PLAYER_SWING               payload (swingDuration, swingType)  -- DURATION FIRST
--      PLAYER_SWING_RANGE_UPDATE  payload (swingType, isInRange, checksRange) -- TYPE LEADS
--    Two separate handlers, never one unpack order (PLAN §8). The
--    Enum.PlayerSwingType is MainHand=0, OffHand=1, Ranged=2; this tracker
--    models the Ranged swing only. Speed: the event duration is the anchor;
--    UnitRangedDamage / UnitAttackSpeed (both SecretWhenUnitStatsRestricted,
--    routed through PlainOrNil) are consulted only when it is unusable, and
--    the last observed duration is the final fallback. "Auto Shot" cast
--    events are the event-based fallback start when no swing events arrive
--    (live probe item, docs/hunter-tools.md).
--
-- Secret-value law: every unit/aura/cooldown read passes
-- FX.Compat.PlainOrNil before any compare or arithmetic; a secret (nil)
-- read NEVER overwrites known state.
--
-- NOTE (catalog audit, docs/hunter-tools.md): the originally-specified
-- reader `C_UnitAuras.GetPlayerAuraBySpellName` does NOT exist in the
-- Forever catalog. The name-resolving, player-scoped equivalent that does
-- is C_UnitAuras.GetAuraDataBySpellName(unit, spellName, filter)
-- (UnitAuraDocumentation.lua:244, SecretWhenUnitAuraRestricted, filter
-- Nilable) -- that is the default reader below.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Hunter = FX.Hunter or {}

-- ============================================================ AspectTracker

local AspectTracker = {}
AspectTracker.__index = AspectTracker

function AspectTracker:IsCombat()
    local f = self.inCombat
    if f then return f() and true or false end
    -- No injected predicate: sample the live lockdown (catalog:
    -- InCombatLockdown, RestrictedActionsDocumentation.lua:44, unannotated).
    return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

--- Our own successful cast of an aspect. Aspects are mutually exclusive, so
--- the newest cast replaces the tracked one. Non-aspect casts are ignored.
--- Returns true when the tracker adopted the name.
function AspectTracker:OnCast(name)
    if name ~= nil and self.byName[name] then
        self.current = name
        return true
    end
    return false
end

--- Out-of-combat correction pass over the aspect list.
--- readAura(name) -> true (plain read: this aspect is active),
---                    false (plain read: not active),
---                    nil  (no reliable read: secret/missing API/error).
--- Rules: a found aspect replaces a stale prediction; every-aspect
--- confirmed-absent clears `current`; any unknown read with nothing found
--- leaves `current` unchanged (a secret read never overwrites).
--- Returns "adopted" | "cleared" | "unchanged".
function AspectTracker:Reconcile(readAura)
    local reader = readAura or FX.Hunter.DefaultAuraReader
    local found, unknown = nil, false
    for _, name in ipairs(self.order) do
        local ok, v = pcall(reader, name)
        local state
        if ok then state = v end
        if state == true then
            found = name
            break
        elseif state == nil then
            unknown = true
        end
    end
    if found then
        self.current = found
        return "adopted"
    end
    if not unknown then
        self.current = nil
        return "cleared"
    end
    return "unchanged"
end

function AspectTracker:Current()
    return self.current
end

--- Reminder predicate: true when no aspect is known active AND we are out
--- of combat (a mid-combat reminder we cannot answer is noise).
function AspectTracker:Missing()
    if self.current ~= nil then return false end
    return not self:IsCombat()
end

--- Plain copy of the tracked state (no metatable, no live objects).
function AspectTracker:Snapshot()
    local list = {}
    for i, name in ipairs(self.order) do list[i] = name end
    return {
        current = self.current,
        missing = self:Missing(),
        aspects = list,
    }
end

function FX.Hunter.NewAspectTracker(opts)
    opts = opts or {}
    local self = setmetatable({
        order = {},       -- aspect names, stable iteration order
        byName = {},      -- [name] = true membership set
        current = nil,    -- tracked aspect name, nil = none known active
        inCombat = opts.inCombat,   -- injectable predicate for tests
    }, AspectTracker)
    for _, name in ipairs(opts.names or {}) do
        if not self.byName[name] then
            self.byName[name] = true
            self.order[#self.order + 1] = name
        end
    end
    return self
end

-- ============================================================== SwingTracker

local SwingTracker = {}
SwingTracker.__index = SwingTracker

local function rangedSwingType()
    local e = _G.Enum and _G.Enum.PlayerSwingType
    return (e and e.Ranged) or 2   -- catalog value: Ranged = 2
end

function SwingTracker:Clock()
    if self.now then return self.now() end
    return GetTime()
end

--- Ranged weapon speed as a plain seconds-per-shot number, or nil.
--- An injected speedReader (tests, later gear models) replaces the live
--- reads. Live path: UnitRangedDamage(unit) -> speed is the FIRST return
--- (UnitDocumentation.lua:2961), UnitAttackSpeed(unit) ->
--- (attackSpeed, offhandAttackSpeed, rangedAttackSpeed)
--- (UnitDocumentation.lua:681); both are SecretWhenUnitStatsRestricted, so
--- every return passes through PlainOrNil and a secret/absent read yields
--- nil.
function SwingTracker:SpeedFromUnit()
    local reader = self.speedReader
    if reader then
        local ok, v = pcall(reader)
        if not ok then return nil end
        return FX.Compat.PlainOrNil(v)
    end
    if type(UnitRangedDamage) == "function" then
        local ok, speed = pcall(UnitRangedDamage, "player")
        local plain = ok and FX.Compat.PlainOrNil(speed)
        if plain and plain > 0 then return plain end
    end
    if type(UnitAttackSpeed) == "function" then
        local ok, _, _, ranged = pcall(UnitAttackSpeed, "player")
        local plain = ok and FX.Compat.PlainOrNil(ranged)
        if plain and plain > 0 then return plain end
    end
    return nil
end

--- PLAYER_SWING handler -- payload order (swingDuration, swingType),
--- duration FIRST (verified contract, file header). A secret/unusable
--- duration falls back to the live speed read, then to the last observed
--- duration; with no speed knowledge at all the swing stays idle.
--- `swingType` is used only as the Ranged filter.
function SwingTracker:OnSwingStart(duration, swingType)
    if swingType ~= self.rangedType then return end
    duration = FX.Compat.PlainOrNil(duration)
    if duration == nil then duration = self:SpeedFromUnit() end
    if duration == nil then duration = self.lastDuration end
    if duration == nil then return end
    self.active, self.start, self.duration = true, self:Clock(), duration
end

--- PLAYER_SWING_RANGE_UPDATE handler -- payload order
--- (swingType, isInRange, checksRange), swingType LEADS (verified contract,
--- file header). isInRange is meaningless while checksRange is false. Out of
--- range the ranged swing stops: the timer goes idle and the next
--- PLAYER_SWING restarts it.
function SwingTracker:OnSwingRange(swingType, isInRange, checksRange)
    if swingType ~= self.rangedType then return end
    if checksRange and isInRange == false then
        self.active, self.start, self.duration = false, nil, nil
    end
end

--- Event-based fallback (PLAN §8 Auto Shot model): with no PLAYER_SWING
--- events reaching addons (catalog evidence level: declaration only), the
--- Auto Shot CAST event restarts the timer using the speed read / last
--- observed duration.
function SwingTracker:OnCast(name)
    if name ~= "Auto Shot" then return end
    local d = self:SpeedFromUnit() or self.lastDuration
    if d == nil then return end
    self.active, self.start, self.duration = true, self:Clock(), d
end

--- Fraction completed (0..1) and seconds remaining of the current ranged
--- swing, nil when idle. Observing completion finalises the swing (the next
--- call reports idle), so "nil after completion" holds without a ticker.
function SwingTracker:Progress(now)
    if not self.active then return nil end
    now = now or self:Clock()
    local elapsed = now - self.start
    if elapsed < 0 then elapsed = 0 end
    if elapsed >= self.duration then
        self.lastDuration = self.duration
        self.active, self.start, self.duration = false, nil, nil
        return nil
    end
    self.lastDuration = self.duration
    return elapsed / self.duration, self.duration - elapsed
end

--- Plain copy of the swing state (seconds, booleans; no live objects).
function SwingTracker:Snapshot()
    local fraction, remaining = self:Progress()
    return {
        active = self.active and true or false,
        duration = self.duration,
        lastDuration = self.lastDuration,
        fraction = fraction,
        remaining = remaining,
    }
end

function FX.Hunter.NewSwingTracker(opts)
    opts = opts or {}
    return setmetatable({
        now = opts.now,                   -- injectable clock for tests
        speedReader = opts.speedReader,   -- injectable speed source
        rangedType = opts.rangedType or rangedSwingType(),
        active = false,
        start = nil,        -- Clock() seconds at swing start
        duration = nil,     -- active swing length, seconds
        lastDuration = nil, -- last observed length (speed fallback chain)
    }, SwingTracker)
end

-- ================================================================ module

FX.Hunter.Tools = {}
local M = FX.Hunter.Tools

--- Aspect names derived from the generated data by the "^Aspect of" name
--- pattern. Never hard-coded IDs; regeneration-safe.
---
--- H1b (docs/localization.md): the pattern runs over `FX.Data.Hunter` -- the
--- GENERATED table, whose names are the data set's English labels -- so it is
--- the data key space, not a live client name, and it needs no locale leg at
--- all. What has to speak the client's language is the JOIN out of that key
--- space, and both of those are locale-safe now: the live aura probe through
--- `auraLookup` (the row's id / `FX.L` name) and the cast-name path through
--- `M.CanonicalCastName` at the event seam. A German `Aspekt des Falken`
--- canonicalizes onto `Aspect of the Falcon` (the alias map is built from the
--- row ids), so the aspect family is recognized on every client.
function M.DeriveAspectNames()
    local names = {}
    local data = FX.Data and FX.Data.Hunter
    if not data then return names end
    for _, spell in pairs(data) do
        local name = spell and spell.name
        if type(name) == "string" and name:find("^Aspect of") then
            names[#names + 1] = name
        end
    end
    table.sort(names) -- stable reconcile order across sessions
    return names
end

M.aspectNames = M.DeriveAspectNames()

--- The client-facing lookup key of one data aspect name (H1b,
--- docs/localization.md): on an English client the English name itself
--- (data name == client name, the shape this file always had), on a localized
--- client the generated row's id -- `C_UnitAuras.GetPlayerAuraBySpellID` is
--- the player-scoped, SpellIdentifier-keyed lookup the catalog ships -- and
--- for a row with no id the client's display name (`FX.L`, the FW:SpellName
--- law). Returns the key and whether it is a spellID.
local function auraLookup(name)
    local Locale = FX.Locale
    if not (Locale and Locale.IsEnglish) then return name, false end
    if Locale.IsEnglish() then return name, false end
    local ids = Locale.RankIDsForName(name)
    if ids and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        return ids[1], true
    end
    return FX.L(name), false
end

--- Default live aura reader: plain-presence probe for one aspect on the
--- player. Contract matches AspectTracker:Reconcile's readAura.
--- `C_UnitAuras.GetAuraDataBySpellName(unit, spellName, filter)` -- the
--- name-resolving player-scoped lookup the Forever catalog ships
--- (UnitAuraDocumentation.lua:244, SecretWhenUnitAuraRestricted, filter
--- Nilable so we pass nil), fed the `auraLookup` key so the name it resolves
--- is the CLIENT's. Its return is SecretWhenUnitAuraRestricted: a secret
--- value reads as "no reliable information" (nil), a plain nil as "confirmed
--- not active" (false).
function FX.Hunter.DefaultAuraReader(name)
    local key, bySpellID = auraLookup(name)
    if key == nil then return nil end
    local ok, aura
    if bySpellID then
        ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, key)
    elseif C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
        ok, aura = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", key, nil)
    else
        return nil
    end
    if not ok then return nil end
    if aura == nil then return false end
    local iss = _G.issecretvalue
    if iss and iss(aura) then return nil end
    return true
end

M.Aspects = FX.Hunter.NewAspectTracker({ names = M.aspectNames })
M.Swing = FX.Hunter.NewSwingTracker()

--- Resolve a UNIT_SPELLCAST_SUCCEEDED spellID to a plain spell name.
--- M3 (review 2026-11-01): the payload spellID is catalog-annotated
--- SecretWhenUnitSpellCastRestricted, so NO raw comparison on it is legal
--- (not even `== nil`, not even outside arithmetic -- PlainOrNil's header)
--- and the info table it returns may itself carry conditional-secret
--- contents. The whole lookup, truth test and field read therefore run
--- inside ONE pcall and only a plain string ever leaves it -- the exact
--- shape Forte_Cooldown/Module.lua:RecordCastEvent uses. Exposed on M
--- (M.ResolveCastName) so the sim tests drive the identical function the
--- event frame calls.
local function resolveCastName(spellID)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, resolved = pcall(function()
        local info = C_Spell.GetSpellInfo(spellID)
        return info and FX.Compat.PlainOrNil(info.name)
    end)
    if ok and type(resolved) == "string" then return resolved end
    return nil
end
M.ResolveCastName = resolveCastName

--- The event frame's dispatcher. Payload contracts in the file header
--- (PLAN §8): UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID[,
--- castBarID]) -- the 4th field lands past a3 and is tolerated;
--- PLAYER_SWING(swingDuration, swingType) DURATION FIRST;
--- PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange) TYPE
--- LEADS; PLAYER_REGEN_ENABLED = out of combat, the moment the cast
--- prediction gets re-anchored (PLAN §3.2).
---
--- H1b (docs/localization.md): the resolved cast name is the CLIENT's name,
--- while both trackers key on the GENERATED DATA's English names (the aspect
--- set is derived from `FX.Data.Hunter` by the `^Aspect of` data-name
--- pattern, the swing gate is the `Auto Shot` data name). On a localized
--- client the raw name therefore matched NOTHING: the aspect prediction never
--- adopted, and the Auto Shot swing fallback never started. One canonicalize
--- at the seam -- the data key space, `Locale.CanonicalName` (the identity on
--- enUS) -- puts both trackers back on their own keys; `M.ResolveCastName`
--- stays the client-name seam (the display half, unchanged).
local function canonicalName(name)
    if type(name) ~= "string" then return name end
    local Locale = FX.Locale
    if Locale and Locale.CanonicalName then return Locale.CanonicalName(name) end
    return name
end
M.CanonicalCastName = canonicalName

local function onToolEvent(self, event, a1, a2, a3)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local name = canonicalName(resolveCastName(a3))
        if name then
            self.Aspects:OnCast(name)
            self.Swing:OnCast(name)
        end
    elseif event == "PLAYER_SWING" then
        -- a1, a2 = swingDuration, swingType
        self.Swing:OnSwingStart(a1, a2)
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        -- a1, a2, a3 = swingType, isInRange, checksRange
        self.Swing:OnSwingRange(a1, a2, a3)
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.Aspects:Reconcile()
    end
end

--- Register the tools' events (idempotent while enabled). The frame is
--- created inside an OnEnable/OnClassChanged handler -- never at file
--- load (Init.lua's taint rule).
function M:EnableEvents()
    if self._eventsEnabled then return end
    local f = self._eventFrame
    if not f then
        f = CreateFrame("Frame")
        self._eventFrame = f
    end
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterEvent("PLAYER_SWING")
    f:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    -- OnEvent receives (frame, event, ...): swallow the frame, or `event`
    -- would be the frame and no branch would ever match.
    f:SetScript("OnEvent", function(_, event, a1, a2, a3) onToolEvent(M, event, a1, a2, a3) end)
    self._eventsEnabled = true
end

--- Tear the event registrations back down (class changed away from
--- HUNTER; Core FX.RefreshPlayerClass). The SetScript(nil) is the part
--- that silences the module everywhere: Unregister(Unit)Event is
--- catalog-declared for the real client (Frame) but absent from the
--- simulator's frame emulation, so both are nil-guarded. GetScript going
--- nil makes the disabled state observable for the tests.
function M:DisableEvents()
    local f = self._eventFrame
    if f and self._eventsEnabled then
        if f.UnregisterUnitEvent then
            f:UnregisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        end
        if f.UnregisterEvent then
            f:UnregisterEvent("PLAYER_SWING")
            f:UnregisterEvent("PLAYER_SWING_RANGE_UPDATE")
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
        end
        f:SetScript("OnEvent", nil)
    end
    self._eventsEnabled = false
end

function M:OnEnable()
    -- Event frame for hunters only (the shared /fx bootstrap runs
    -- OnEnable for every player class). /fx status needs no hook: the
    -- Core status loop (Init.lua, review m6) calls M:Status directly --
    -- the old one-shot wrapper on Forte_Cooldown's Status method is gone.
    if FX._playerClass ~= "HUNTER" then return end
    self:EnableEvents()
end

--- Core FX.RefreshPlayerClass notification (uiforever T4 class guard):
--- the event frame follows the class.
function M:OnClassChanged(classFile)
    if classFile == "HUNTER" then
        self:EnableEvents()
    else
        self:DisableEvents()
    end
end

--- One-line module state as a string (the shape the tests assert).
function M:StatusLine()
    local snap = M.Aspects:Snapshot()
    local fraction, remaining = M.Swing:Progress()
    return string.format(
        "Hunter: %d aspects | current=%s%s | ranged swing: %s",
        #snap.aspects,
        tostring(snap.current),
        snap.missing and " (no aspect -- cast one)" or "",
        fraction and string.format("%.0f%% (%.1fs left)", fraction * 100, remaining)
            or "idle")
end

--- `/fx status` integration: prints its own line (review m6 -- modules
--- print, the Core registry only loops).
function M:Status()
    FX.Print(M:StatusLine())
end

FX.RegisterModule("Hunter", M)
