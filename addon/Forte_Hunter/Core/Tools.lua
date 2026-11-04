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
--    models the Ranged swing only. The range edge's law
--    (upstream-addons-2026-11-03 §3): `isInRange = nil` is "no check
--    possible", NOT out of range, and a `checksRange` that is not plain-true
--    means the edge carries no knowledge at all; the edges themselves only
--    arrive after the C_SwingTimer.EnableRangeCheck opt-in, which
--    M.RequestRangeCheck owns (the swing tracker + the range light each
--    request it; every leg is feature-detected).
--    Speed: the event duration is the anchor; UnitRangedDamage and the
--    PER-SLOT UnitAttackSpeed read (SlotSpeed: the declared
--    (main, offhand, ranged) trio, the leg picked by the modelled slot --
--    the shipped row law reads the slot's own speed) -- both
--    SecretWhenUnitStatsRestricted, routed through PlainOrNil -- are
--    consulted only when it is unusable, and the last observed duration is
--    the final fallback. "Auto Shot" cast events are the event-based
--    fallback start when no swing events arrive (live probe item,
--    docs/hunter-tools.md).
--
-- 3. Swing v2 (docs/research/weaponswingtimer.md gap table, agent
--    HunterSwing2): the Auto Shot cycle is TWO phases -- the reload span
--    (safe to move/cast) and the aim window at the cycle's floor, whose
--    length is 0.5 x hastedSpeed/baseSpeed per cycle (the aim-length
--    formula + the floor clamp adapted from WeaponSwingTimer SixxFix,
--    GPLv3 -- see the notes at AIM_SECONDS and the floor clamp). On top:
--    the GUID-keyed shot cast-event machine (UNIT_SPELLCAST_SENT/START/
--    SUCCEEDED/INTERRUPTED/FAILED/FAILED_QUIET for Auto Shot incl. the
--    0.5 s FAILED_QUIET retry penalty), the event-proven "projectile left"
--    (flying) phase, the Aimed/Multi/Steady cast interlock (opens on SENT
--    -- Forever Multi-Shot emits no START, the Castbar.lua:195-205 finding),
--    the readiness gate (shooting + target + movement), movement via
--    PLAYER_STARTED/STOPPED_MOVING with the sustained-pulse law, the
--    Feign-Death reset on the next movement, START/STOP_AUTOREPEAT_SPELL
--    as the shooting flag, and the base-speed seam for the aim ratio.
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
    -- K9 m3 (code-review-9 MINOR 3): the lockdown read rides the Melee
    -- UI/Melee.lua `_InCombat` shape -- pcall + PlainOrNil, a
    -- raising/secret/absent read is "no knowledge" = nil, never a raise.
    -- This runs inside OnEvent bodies (the reminder's `not self:IsCombat()`
    -- gate on PLAYER_REGEN_ENABLED/DISABLED, PLAYER_ENTERING_WORLD), and a
    -- raise there is the Lua popup the K4 F3 fix removed from the rail.
    -- The consumer `Missing` reads nil as "not proven in combat" -- the
    -- same reminder posture the absent global has always had.
    local function verdict(v)
        v = FX.Compat.PlainOrNil(v)
        if v == true or v == 1 then return true end
        if v == false or v == 0 then return false end
        return nil
    end
    local f = self.inCombat
    if f then
        local ok, v = pcall(f)
        if not ok then return nil end
        return verdict(v)
    end
    -- No injected predicate: sample the live lockdown (catalog:
    -- InCombatLockdown, RestrictedActionsDocumentation.lua:44, unannotated).
    if type(_G.InCombatLockdown) ~= "function" then return nil end
    local ok, v = pcall(_G.InCombatLockdown)
    if not ok then return nil end
    return verdict(v)
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

--- The unhasted Auto Shot windup in seconds. The aim window of a hasted
--- cycle is AIM_SECONDS x hastedSpeed / baseSpeed (the cycle stretches
--- with haste, the 0.5 s windup does not). Adapted from WeaponSwingTimer
--- SixxFix (GPLv3, WatchYourSixx; original WST by LeftHandedGlove),
--- WeaponSwingTimer_Hunter.lua:96 (auto_delay_duration) + :109-141
--- (GetAutoCastTime; changes: the cache ladder is ours, the tooltip
--- base-speed scan is NOT ported -- §B13 crash risk).
local AIM_SECONDS = 0.5
--- The FAILED_QUIET retry penalty: a rejected Auto Shot start costs this
--- many seconds before the shot may begin again. Adapted from
--- WeaponSwingTimer SixxFix, WeaponSwingTimer_Hunter.lua:95-96 +
--- :604-631 (changes: our field names; the penalty folds into the cycle
--- floor as `remaining - retryUntil`, not a separate countdown).
local RETRY_SECONDS = 0.5
--- A cast-time shot whose phase gates the cycle display (the interlock
--- set). Name-keyed (AGENTS.md: resolve by NAME; the Steady id 34120 WST
--- hard-codes does not exist on Forever -- §B9).
local SHOT_CAST_SET = {
    ["Aimed Shot"] = true, ["Multi-Shot"] = true, ["Steady Shot"] = true,
}
--- The flying stamp self-clears after this many seconds past the cycle
--- (a SUCCEEDED whose next PLAYER_SWING never arrives).
local FLY_STALE_GRACE = 10
--- How fresh the InCombatLockdown sample of the UI may be (0 = every pass).
local COMBAT_SAMPLE_SECONDS = 0.5
--- The sustained-pulse floor for movement when the speed read is
--- unavailable. Adapted from WeaponSwingTimer SixxFix,
--- WeaponSwingTimer_Hunter.lua:150-154 (changes: our field names).
local MOVE_PULSE_SECONDS = 0.05

local function rangedSwingType()
    local e = _G.Enum and _G.Enum.PlayerSwingType
    return (e and e.Ranged) or 2   -- catalog value: Ranged = 2
end

--- The Ranged swing type as a plain number (nil when absent) -- every
--- Enum touch of ours is pcall-guarded so a secret table can never raise.
local function rangedTypePlain()
    local ok, v = pcall(function()
        local e = _G.Enum and _G.Enum.PlayerSwingType
        return FX.Compat.PlainOrNil(e and e.Ranged)
    end)
    return (ok and type(v) == "number") and v or nil
end

--- Seal a cast GUID: a stable, PLAIN, comparison-safe string, nil for a
--- secret/absent id. The GUID values themselves are
--- SecretWhenUnitSpellCastRestricted -- nothing outside these two helpers
--- ever touches a raw guid (mirrors the resolveCastName M3 law).
local function sealGUID(guid)
    if guid == nil then return nil end
    local t = type(guid)
    if t == "string" then return guid end
    if t == "number" then
        local ok, s = pcall(tostring, guid)
        if ok and type(s) == "string" then return s end
        return nil
    end
    local ok, s = pcall(tostring, guid)
    if ok and type(s) == "string" then return s end
    return nil
end

--- Match two seals. nil (secret/absent guid) = "no key" = permissive
--- match -- the WST `not cast_guid or ... == cast_guid` end-the-phase law.
local function sealsMatch(a, b)
    if a == nil or b == nil then return true end
    return a == b
end

function SwingTracker:Clock()
    if self.now then return self.now() end
    return GetTime()
end

--- Which `UnitAttackSpeed` return belongs to which swing slot: the
--- declared trio (attackSpeed, offhandAttackSpeed, rangedAttackSpeed)
--- (UnitDocumentation.lua:681) keyed by Enum.PlayerSwingType
--- (MainHand=0, OffHand=1, Ranged=2). The shipped swing-timer family reads
--- the speed PER SLOT ("a row exists while UnitAttackSpeed reports a speed
--- for its slot", upstream-addons-2026-11-03 §3 row law, re-derived here
--- from the declared return list -- the shape only, no code taken).
--- nil = a slot we do not model.
local ATTACK_SPEED_LEG = { [0] = 1, [1] = 2, [2] = 3 }

--- The slot speed read: this tracker models ONE slot, the Ranged one, so
--- its leg is ATTACK_SPEED_LEG[self.rangedType] -- an OffHand/MH twin ever
--- rides the same read with its own type. Plain seconds, nil = the slot
--- reports no speed (measured in the sim: UnitAttackSpeed("player") =
--- 2, 2, nil with no ranged weapon -- the "no row" statement of the row
--- law). SecretWhenUnitStatsRestricted: every return passes PlainOrNil.
function SwingTracker:SlotSpeed()
    if type(_G.UnitAttackSpeed) ~= "function" then return nil end
    local leg = ATTACK_SPEED_LEG[self.rangedType]
    if leg == nil then return nil end
    local ok, a, b, c = pcall(_G.UnitAttackSpeed, "player")
    if not ok then return nil end
    local plain = FX.Compat.PlainOrNil(( { a, b, c } )[leg])
    if type(plain) == "number" and plain > 0 then return plain end
    return nil
end

--- Ranged weapon speed as a plain seconds-per-shot number, or nil.
--- An injected speedReader (tests, later gear models) replaces the live
--- reads. Live path: UnitRangedDamage(unit) -> speed is the FIRST return
--- (UnitDocumentation.lua:2961) as the event-duration anchor's twin, then
--- the per-slot UnitAttackSpeed read (SlotSpeed above); both are
--- SecretWhenUnitStatsRestricted, so every return passes through
--- PlainOrNil and a secret/absent read yields nil.
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
    return self:SlotSpeed()
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
    self.lastShotTime = self:Clock()
    self.at = nil          -- a fresh cycle ends any aim phase
    self.flying = nil      -- a fresh cycle ends the proven flight (shot fired)
    -- The per-cycle aim length. Adapted from WeaponSwingTimer SixxFix
    -- (GPLv3, WatchYourSixx; original WST by LeftHandedGlove),
    -- WeaponSwingTimer_Hunter.lua:283-286 + GetAutoCastTime :109-141
    -- (changes: our field names, no tooltip base-speed scan -- the
    -- undeclared GetInventoryItemID/INVSLOT_RANGED/SPEED legs are NOT
    -- copied per the survey §B13; the base speed rides the settings
    -- override / the learned sample / the no-haste floor).
    local base = self:GetBaseSpeed()
    if base and base > 1 then
        self.aimLen = AIM_SECONDS * duration / base
    else
        self.aimLen = AIM_SECONDS
        -- The clean-pair base-speed sample (gap row 7a, [INFERENCE] seed):
        -- a plain speed read at a cycle whose length equals the speed is a
        -- no-haste cycle -- its speed IS the base.
        self:LearnBaseSpeed(self:SpeedFromUnit(), duration)
    end
end

--- PLAYER_SWING_RANGE_UPDATE handler -- the payload has THREE returns,
--- (swingType, isInRange, checksRange), swingType LEADS (the shipped
--- SwingTimerDocumentation shape our survey recorded as two --
--- upstream-addons-2026-11-03 §3). The edges only exist after the
--- C_SwingTimer.EnableRangeCheck opt-in (RequestRangeCheck, module below).
---
--- The law: `nil` means "no check possible" (no target / untargetable / no
--- weapon), NOT out of range -- the shipped family's own words: "so it is
--- not a reason to stop the bar". A `checksRange` that is not plain-true
--- means the edge carries no range knowledge at all (isInRange is
--- meaningless then), and a plain `false` is the one stop: the timer goes
--- idle and the next PLAYER_SWING restarts it. A plain `true`/`false`
--- stamps the range fact the readiness gate reads (the same fact a
--- completed shot stamps).
function SwingTracker:OnSwingRange(swingType, isInRange, checksRange)
    if swingType ~= self.rangedType then return end
    checksRange = FX.Compat.PlainOrNil(checksRange)
    isInRange = FX.Compat.PlainOrNil(isInRange)
    local checked = (checksRange == true or checksRange == 1)
    if not checked then return end
    if isInRange == nil then return end       -- no check possible: permissive
    local inRange = (isInRange == true or isInRange == 1) and true or false
    self.factsInRange = inRange
    if not inRange then
        self.active, self.start, self.duration = false, nil, nil
    end
end

--- Event-based fallback (PLAN §8 Auto Shot model): with no PLAYER_SWING
--- events reaching addons (catalog evidence level: declaration only), the
--- Auto Shot CAST event restarts the timer using the speed read / last
--- observed duration. `name` is the CANONICAL name (the event seam runs
--- canonicalName; the tracker key space is the generated data's English).
function SwingTracker:OnCast(name)
    if name ~= "Auto Shot" then return end
    local d = self:SpeedFromUnit() or self.lastDuration
    if d == nil then return end
    self.active, self.start, self.duration = true, self:Clock(), d
    self.lastShotTime = self:Clock()
    local aim = self:GetBaseSpeed()
    self.aimLen = (aim and aim > 1) and (AIM_SECONDS * d / aim) or AIM_SECONDS
    self.at, self.flying = nil, nil
end

-- --------------------------------------------------------- swing v2 legs --
--- The un-hasted weapon base speed for the aim ratio (gap row 7, NO
--- tooltip scan): the settings override (Hunter.BaseSpeed, 0 = auto)
--- first, then a learned plain sample (see LearnBaseSpeed). nil = unknown
--- (the aim window floors at AIM_SECONDS, the no-haste reading).
function SwingTracker:GetBaseSpeed()
    local ov = self.baseOverride
    if type(ov) == "number" and ov > 1 then return ov end
    local b = self.base
    if type(b) == "number" and b > 1 then return b end
    return nil
end

--- Learn the base speed from a clean pair: a plain speed read taken when
--- the observed cycle length shows no haste delta (cycle == speed) marks
--- the speed as the un-hasted base. [INFERENCE] seed (survey gap row 7a):
--- the launch probe (docs/research/weaponswingtimer.md §6.9) is what
--- promotes it beyond the inference; a wrong sample only ever floors the
--- aim window (the safe direction).
function SwingTracker:LearnBaseSpeed(speed, cycle)
    if type(speed) ~= "number" or speed <= 1 then return end
    if type(cycle) ~= "number" then return end
    if math.abs(cycle - speed) <= 0.05 then self.base = speed end
end

--- The cycle floor law: the countdown never counts below the aim window
--- (plus an open retry penalty). Adapted from WeaponSwingTimer SixxFix,
--- WeaponSwingTimer_Hunter.lua:359-360 (`math.max(shot_timer - elapsed,
--- cast_time)`) + :625-627 (the FAILED_QUIET floor raise; changes: the
--- penalty rides an absolute `retryUntil` stamp, no separate countdown).
function SwingTracker:FloorAt(now)
    return self.aimLen + math.max(0, (self.retryUntil or 0) - now)
end

--- The readiness gate (gap row 4): what "safe to begin the aim window"
--- means. Gates the DRAW (the aim slice) and drops the inferred aim --
--- the cycle math runs regardless. Law adapted from WeaponSwingTimer
--- SixxFix, WeaponSwingTimer_Hunter.lua:182-215 (CanBeginAutoVisual;
--- changes: the range read is nil-permissive per the gap contract --
--- WST's range-module fallback band is our Range light's job, the
--- spellbook rung is not duplicated here; the target-fact stamps :536-538
--- are adopted verbatim in law).
function SwingTracker:CanAim(now)
    now = now or self:Clock()
    if not self.shooting then return false end
    local tr = self.targetReader
    local exists = tr and tr()
    if exists == nil then return false end
    local dr = self.deadReader
    local dead = dr and dr()
    if dead == true then return false end
    local ar = self.attackReader
    local can = ar and ar()
    if can == false then return false end
    local moving = self:SampleMovement(now)
    if moving == true then return false end
    local rr = self.rangeReader
    local rng = rr and rr()
    if rng == true then
        self.factsInRange = true
    elseif rng == false then
        self.factsInRange = false
        return false
    end
    -- nil = no knowledge (the API is a launch-day probe for third-party
    -- addons): permissive, matching the gap-row contract "nil =
    -- permissive"; a learned `false` fact from the gate read above stays
    -- authoritative until a `true` read (a SUCCEEDED stamp) replaces it.
    if self.factsInRange == false then return false end
    return true
end

--- Movement truth for the gate. Continuous GetUnitSpeed cross-check
--- through PlainOrNil; with the read secret/absent a PLAYER_STARTED_MOVING
--- pulse counts only once sustained >= MOVE_PULSE_SECONDS. Law adapted
--- from WeaponSwingTimer SixxFix, WeaponSwingTimer_Hunter.lua:145-156
--- (UpdateAutoMovement; changes: the pulse stamp rides `movePulseAt`,
--- PLAYER_STOPPED_MOVING clears it outright).
function SwingTracker:SampleMovement(now)
    now = now or self:Clock()
    local sr = self.speedSampler
    local speed = sr and sr()
    if type(speed) == "number" then
        self.moving = speed > 0
        return self.moving
    end
    if self.movePulseAt and (now - self.movePulseAt) >= MOVE_PULSE_SECONDS then
        self.moving = true
    end
    return self.moving
end

function SwingTracker:OnPlayerStartedMoving()
    self.movePulseAt = self.movePulseAt or self:Clock()
    -- A pulse alone is not movement yet (the sustained-pulse law above),
    -- unless the speed read already proves it.
    self.moving = self.moving and true or false
    -- The Feign-Death movement reset rides the same event.
    if self.feignPending then self:ApplyFeignReset() end
end

function SwingTracker:OnPlayerStoppedMoving()
    self.movePulseAt = nil
    self.moving = false
end

--- Feign Death: the shot cycle re-arms on the NEXT movement after the cast
--- (gap row 5). Adapted from WeaponSwingTimer SixxFix,
--- WeaponSwingTimer_Hunter.lua:309-329 (FeignDeath + ResetShotTimer;
--- changes: the +0.15 first-shot stretch is NOT ported (launch probe #7;
--- the movement leg covers jump-away; hooksecurefunc/JumpOrAscendStart are
--- undeclared §B7), no range_speed fudge -- the re-arm rides the last
--- observed cycle length).
function SwingTracker:NoteFeignDeath()
    if not self.active then return end
    self.feignPending = true
end

function SwingTracker:ApplyFeignReset()
    if not self.feignPending then return end
    self.feignPending = nil
    self.at, self.flying, self.pending, self.cast = nil, nil, nil, nil
    self.retryUntil = nil
    local d = self.duration or self.lastDuration
    if d then
        self.active, self.start = true, self:Clock()
        self.duration = d
        self.lastShotTime = self:Clock()
    end
end

--- START/STOP_AUTOREPEAT_SPELL (no payload -- the Auto Shot / wand Shoot
--- paths share this one seam, §B2): the `shooting` flag the readiness gate
--- starts from. Law adapted from WeaponSwingTimer SixxFix,
--- WeaponSwingTimer_Hunter.lua:433-461 (changes: the stale native-pin drop
--- has no twin in our design -- the aimLen re-pins at every OnSwingStart;
--- the "toggling on at the floor re-arms a shot" leg is WST's separate
--- shot_timer model, our cycle re-arms through PLAYER_SWING/OnCast).
function SwingTracker:OnAutoRepeatStart()
    if not self.shooting then
        self.shooting = true
        -- Toggling on with the last cycle a full span in the past: the
        -- live reads retake over -- drop any stale aim pin (§B4 :433-442
        -- in law; our pin is the per-cycle aimLen, re-pinned by the next
        -- OnSwingStart).
        local last = self.lastShotTime
        local d = self.duration or self.lastDuration
        if last and d and (self:Clock() - last) >= d then
            self.aimLen = AIM_SECONDS
        end
    end
end

function SwingTracker:OnAutoRepeatStop()
    self.shooting = false
    self.pending = nil
    self.at = nil
    self.retryUntil = nil
end

--- The settings seam for the aim-ratio base speed (Hunter.BaseSpeed).
function SwingTracker:SetBaseSpeed(v)
    if type(v) == "number" and v > 1 then
        self.baseOverride = v
    else
        self.baseOverride = nil
    end
end

-- ------------------------------------------------- shot cast-event machine --
--- The Aimed/Multi/Steady interlock opens. THE FOREVER LAW this encodes
--- (a finding adapted from WeaponSwingTimer SixxFix,
--- WeaponSwingTimer_Castbar.lua:195-205: "Forever Multi-Shot does not emit
--- UNIT_SPELLCAST_START ... SENT followed by SUCCEEDED"): the interlock
--- MUST open on SENT, never on START. `castLenReader` (live:
--- UnitCastingInfo) is authoritative; the event spellID's
--- C_Spell.GetSpellInfo.castTime second; the generated data's castMs
--- third. Latency is NOT folded in (the GetNetStats 4th-return shape is a
--- launch probe, survey Gap-12 -- no unvalidated number rides the bar).
function SwingTracker:BeginCast(name, id)
    if not SHOT_CAST_SET[name] then return end
    if self.cast then self:RefreshCastLength(id) end
    if self.cast then return end
    local t = self:CastLength(id, name)
    if not t then return end
    local now = self:Clock()
    local freeze
    if self.active and self.duration and self.duration > 0 then
        freeze = 1 - (now - self.start) / self.duration
        if freeze < 0 then freeze = 0 elseif freeze > 1 then freeze = 1 end
    end
    self.cast = { seal = sealGUID(self._evtSeal), name = name, len = t,
        startAt = now, endAt = now + t, freeze = freeze }
end

function SwingTracker:CastLength(id, name)
    local r = self.castLenReader
    local t = r and r()
    if type(t) == "number" and t > 0 then return t end
    local T = FX.Hunter.Tools
    if id ~= nil and T and T.ResolveCastLength then
        t = T.ResolveCastLength(id)
        if type(t) == "number" and t > 0 then return t end
    end
    local idx = T and T.DataCastMsByName and T.DataCastMsByName()
    local ms = idx and idx[name]
    if type(ms) == "number" and ms > 0 then return ms / 1000 end
    return nil
end

--- UNIT_SPELLCAST_DELAYED (pushback): adopt the authoritative live window
--- (the WST Castbar.lua:224-263 law, changes: we re-anchor start/end from
--- the live UnitCastingInfo read only -- no pushback-value bookkeeping,
--- the bar prints the live remaining).
function SwingTracker:RefreshCastLength(id)
    local c = self.cast
    if not c then return end
    local t = self:CastLength(id, c.name)
    if type(t) ~= "number" or t <= 0 then return end
    local now = self:Clock()
    c.len, c.startAt, c.endAt = t, now, now + t
end

function SwingTracker:EndCast()
    self.cast = nil
end

--- The single event seam of the shot machine (tests + the event frame
--- drive it; `name` canonical, `id` the raw payload spellID -- resolved
--- only, never compared, `guid` sealed). Auto Shot's
--- SENT/START/SUCCEEDED/INTERRUPTED/FAILED/FAILED_QUIET ladder drives the
--- aim phase; the cast-time shots drive the interlock. Law adapted from
--- WeaponSwingTimer SixxFix, WeaponSwingTimer_Hunter.lua:465-631
--- (changes: name-keyed not id-keyed, seal-hashed GUIDs, one seam, our
--- field names, the spell_GCD leg NOT ported (vestigial §B4), the legacy
--- reset table NOT ported (§B8: PLAYER_SWING is the sole authority)).
function SwingTracker:OnShotCast(event, name, id, guid)
    local seal = sealGUID(guid)
    self._evtSeal = seal
    if SHOT_CAST_SET[name] then
        if event == "SENT" then
            self:BeginCast(name, id)
        elseif event == "START" then
            self:BeginCast(name, id)
        elseif event == "SUCCEEDED" or event == "FAILED"
            or event == "INTERRUPTED" then
            local c = self.cast
            if not c or sealsMatch(c.seal, seal) then self:EndCast() end
        end
        -- Any cast start clears a pending Feign re-arm (WST :488 law:
        -- FeignStatus = false on every UNIT_SPELLCAST_START).
        if event == "START" then self.feignPending = nil end
        return
    end
    if name == "Feign Death" then
        if event == "SUCCEEDED" then self:NoteFeignDeath()
        elseif event == "START" then self.feignPending = nil end
        return
    end
    if name ~= "Auto Shot" then return end
    local now = self:Clock()
    if event == "SENT" then
        -- Tentative: the same batch may still report FAILED_QUIET.
        self.pending = { seal = seal, at = now, len = self.aimLen }
    elseif event == "START" then
        self.pending = nil
        self.retryUntil = nil
        if self.at and sealsMatch(self.at.seal, seal) then
            self.at.ev = true
            if not self.at.inferred then self.at.seal = seal end
        else
            self.at = { seal = seal, startAt = now, endAt = now + self.aimLen,
                ev = true, inferred = false }
        end
    elseif event == "SUCCEEDED" then
        local at = self.at
        if at and sealsMatch(at.seal, seal) then
            self.at = nil
            self.retryUntil = nil
        end
        self.pending = nil
        -- A completed shot proves these (WST :536-538 -- readable
        -- negative checks keep priority; the gate re-samples live values).
        self.factsInRange = true
        -- The white moment: the projectile left the player.
        self.flying = now
    elseif event == "INTERRUPTED" or event == "FAILED" then
        local at = self.at
        if at and sealsMatch(at.seal, seal) then self.at = nil end
        self.pending = nil
    elseif event == "FAILED_QUIET" then
        -- "can't begin": the 0.5 s retry penalty + the floor raise.
        local at = self.at
        if at and sealsMatch(at.seal, seal) then
            self.at = nil
        elseif not at then
            self.pending = nil
        end
        self.retryUntil = now + RETRY_SECONDS
    end
end

--- The interlock clock: seconds of the tracked cast left, nil when no
--- cast is on the bar.
function SwingTracker:CastRemaining(now)
    local c = self.cast
    if not c then return nil end
    now = now or self:Clock()
    local left = c.endAt - now
    if left <= 0 then
        self.cast = nil
        return nil
    end
    return left, c.len, c.name
end

--- The cycle fraction frozen at the interlock's start (the "this cycle
--- gets clipped" signal of the bar; gap row 8).
function SwingTracker:CastingCycleFraction()
    local c = self.cast
    if not c then return nil end
    return c.freeze
end

--- The phase of the current cycle (nil idle, "reload" the safe-to-move
--- span, "flying" the proven flight after the shot left, "aim" the
--- stand-still window) plus the aim length, the floor (aim + open retry)
--- and the readiness gate. The event-proven aim survives every gate
--- (its truth is the events -- §B11); an inferred aim is gate-gated
--- (movement/target-loss drops it -- law adapted from WeaponSwingTimer
--- SixxFix, WeaponSwingTimer_Hunter.lua:361-366).
function SwingTracker:CycleState(now)
    now = now or self:Clock()
    local fly = self.flying
    if fly and now - fly > (self.duration or 0) + FLY_STALE_GRACE then
        self.flying = nil
        fly = nil
    end
    local at = self.at
    if at and now > at.endAt + FLY_STALE_GRACE then
        self.at = nil
        at = nil
    end
    local ready
    if not self.active then
        ready = self:CanAim(now)
        if at and at.ev and now <= at.endAt and (ready or not at.inferred) then
            return "aim", self.aimLen, self:FloorAt(now), ready
        end
        return nil, self.aimLen, 0, false
    end
    local elapsed = math.max(0, now - self.start)
    local remaining = self.duration - elapsed
    local floor = self:FloorAt(now)
    ready = self:CanAim(now)
    if at then
        if at.inferred and not ready then
            at = nil
            self.at = nil
        elseif remaining <= floor then
            return "aim", self.aimLen, floor, true
        end
    end
    -- A proven flight outranks a fresh inferred aim: after the shot left,
    -- the tail of the countdown is the fire->swing latency, not a new
    -- stand-still window (the next PLAYER_SWING re-arms the cycle).
    if fly then return "flying", self.aimLen, floor, ready end
    if at == nil and remaining > 0 and remaining <= floor and ready then
        self.at = { seal = nil, startAt = now, endAt = self.start
            + self.duration, ev = false, inferred = true }
        return "aim", self.aimLen, floor, true
    end
    return "reload", self.aimLen, floor, ready
end

--- Fraction completed (0..1) and seconds remaining of the current ranged
--- swing, nil when idle. Observing completion finalises the swing (the
--- next call reports idle), so "nil after completion" holds without a
--- ticker. The one exception is swing v2: a shot whose flight the events
--- proved (flying) keeps the cycle reporting through the server gap to
--- the next PLAYER_SWING, so the white "projectile left" state survives
--- the cycle boundary (the raw countdown runs on under the bar's
--- CycleState clamp).
function SwingTracker:Progress(now)
    if not self.active then return nil end
    now = now or self:Clock()
    local elapsed = now - self.start
    if elapsed < 0 then elapsed = 0 end
    if elapsed >= self.duration then
        self.lastDuration = self.duration
        if self.flying then
            -- The flight span: report the finished cycle (fraction 1,
            -- remaining 0) until the next PLAYER_SWING re-arms it.
            return 1, 0
        end
        self.active, self.start, self.duration = false, nil, nil
        return nil
    end
    self.lastDuration = self.duration
    return elapsed / self.duration, self.duration - elapsed
end

--- Plain copy of the swing state (seconds, booleans; no live objects).
function SwingTracker:Snapshot()
    local fraction, remaining = self:Progress()
    local phase = self:CycleState()
    return {
        active = self.active and true or false,
        duration = self.duration,
        lastDuration = self.lastDuration,
        fraction = fraction,
        remaining = remaining,
        phase = phase,
        aimLen = self.aimLen,
        shooting = self.shooting and true or false,
        moving = self.moving and true or false,
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
        -- ---- swing v2 (docs/research/weaponswingtimer.md gap table) ----
        aimLen = AIM_SECONDS, -- this cycle's aim-window length (B1 pin)
        base = nil,           -- learned un-hasted base speed
        baseOverride = (type(opts.baseSpeed) == "number"
            and opts.baseSpeed > 1) and opts.baseSpeed or nil,
        aimFloor = AIM_SECONDS,     -- the no-haste floor (gap row 7c)
        retryUntil = nil,           -- open FAILED_QUIET penalty deadline
        flying = nil,               -- Clock() stamp of a proven shot flight
        at = nil,                   -- the live aim phase
        --   {seal, startAt, endAt, ev=event-proven, inferred}
        pending = nil,              -- the tentative SENT record
        cast = nil,                 -- the Aimed/Multi/Steady interlock
        --   {seal, name, len, startAt, endAt}
        shooting = false,           -- START/STOP_AUTOREPEAT_SPELL flag
        moving = false,             -- PLAYER_STARTED/STOPPED_MOVING flag
        movePulseAt = nil,          -- PLAYER_STARTED_MOVING pulse stamp
        feignPending = nil,         -- Feign Death awaiting its movement
        lastShotTime = nil,         -- Clock() at the last cycle/shot event
        factsInRange = nil,         -- learned range fact (a completed shot
                                    -- or a plain-true range edge stamps it)
        _evtSeal = nil,             -- the seal of the event being handled
        -- Injectable gate/seam readers (tests; the live defaults are the
        -- pcall-guarded unit reads wired by the module below).
        speedSampler = opts.speedSampler,       -- () -> plain speed|nil
        targetReader = opts.targetReader,       -- () -> bool|nil
        deadReader = opts.deadReader,           -- () -> bool|nil
        attackReader = opts.attackReader,       -- () -> bool|nil
        rangeReader = opts.rangeReader,         -- () -> bool|nil
        castLenReader = opts.castLenReader,     -- () -> cast seconds|nil
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

--- The live gate/seam readers of the production tracker (the tests inject
--- their own). Every read is pcall-guarded and every result passes
--- PlainOrNil (a secret read = "no knowledge" = nil -- the gate law);
--- the reads run at the 10 Hz draw cadence, never per frame.
local function plainBool(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok then return nil end
    v = FX.Compat.PlainOrNil(v)
    if v == true then return true end
    if v == false then return false end
    if v == 1 then return true end
    if v == 0 then return false end
    return nil
end
local SW = M.Swing
SW.targetReader = function()
    return plainBool(_G.UnitExists, "target") and true or false
end
SW.deadReader = function()
    return plainBool(_G.UnitIsDead, "target")
end
SW.attackReader = function()
    return plainBool(_G.UnitCanAttack, "player", "target")
end
SW.speedSampler = function()
    if type(_G.GetUnitSpeed) ~= "function" then return nil end
    local ok, v = pcall(_G.GetUnitSpeed, "player")
    return ok and FX.Compat.PlainOrNil(v) or nil
end
--- The range rungs: C_SwingTimer.IsTargetWithinSwingRange(Ranged) first
--- (CAT-declared; nil = "no check possible", NOT out of range, so only a
--- plain true/false is knowledge; the third-party runtime reachability is a
--- launch probe, the nil-permissive gate law), the spellbook Auto Shot
--- rung as its fallback.
---
--- A plain `false` is a real answer and must not be eaten: the idiom
--- `v = ok and PlainOrNil(v) or nil` maps it to nil (Lua's `or`), which
--- would leave this rung unable to ever say out of range -- so the ok test
--- and the PlainOrNil pass are separate statements.
local function spellBookInRange(englishName)
    local ns = _G.C_SpellBook
    if not (ns and ns.FindSpellBookSlotForSpell
        and ns.IsSpellBookItemInRange) then return nil end
    local ok, slot, bank = pcall(ns.FindSpellBookSlotForSpell,
        FX.L(englishName))
    if not ok or slot == nil then return nil end
    local ok2, res = pcall(ns.IsSpellBookItemInRange, slot, bank, "target")
    if not ok2 then return nil end
    res = FX.Compat.PlainOrNil(res)
    if res == true or res == 1 then return true end
    if res == false or res == 0 then return false end
    return nil
end
SW.rangeReader = function()
    local t = rangedTypePlain()
    if t ~= nil and _G.C_SwingTimer
        and _G.C_SwingTimer.IsTargetWithinSwingRange then
        local ok, v = pcall(_G.C_SwingTimer.IsTargetWithinSwingRange, t)
        if ok then
            v = FX.Compat.PlainOrNil(v)
            if v == true or v == 1 then return true end
            if v == false or v == 0 then return false end
        end
    end
    return spellBookInRange("Auto Shot")
end
--- The interlock's live length: UnitCastingInfo("player") ->
--- (endMs - startMs)/1000 (the WST Castbar.lua:141-147 reading; the
--- function is SecretWhenUnitSpellCastRestricted -- every return passes
--- PlainOrNil inside the pcall).
SW.castLenReader = function()
    if type(_G.UnitCastingInfo) ~= "function" then return nil end
    local ok, _, _, _, startMs, endMs = pcall(_G.UnitCastingInfo, "player")
    if not ok then return nil end
    startMs = FX.Compat.PlainOrNil(startMs)
    endMs = FX.Compat.PlainOrNil(endMs)
    if type(startMs) ~= "number" or type(endMs) ~= "number"
        or endMs <= startMs then return nil end
    return (endMs - startMs) / 1000
end

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

--- The live cast length of a spellID in seconds (the Aimed/Multi/Steady
--- interlock's data leg): `C_Spell.GetSpellInfo(id).castTime` is MILLISECONDS
--- (the WST Castbar.lua:150-165 reading, catalog CAT-checked). The payload
--- id is SecretWhenUnitSpellCastRestricted -- the lookup, the info truth
--- test and the field read run inside ONE pcall (the resolveCastName M3
--- law), and the returned number passes PlainOrNil before any arithmetic.
function M.ResolveCastLength(spellID)
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, resolved = pcall(function()
        local info = C_Spell.GetSpellInfo(spellID)
        return info and FX.Compat.PlainOrNil(info.castTime)
    end)
    if not ok then return nil end
    local ms = type(resolved) == "number" and resolved or nil
    if ms and ms > 0 then return ms / 1000 end
    return nil
end

--- The generated data's cast times as { [English name] = castMs } (the
--- interlock's fallback length when the live reads give nothing; the
--- data table is the English key space -- AGENTS.md locale law: the
--- trackers key on data names, the event seam canonicalizes).
function M.DataCastMsByName()
    local idx = {}
    local data = FX.Data and FX.Data.Hunter
    if not data then return idx end
    for _, spell in pairs(data) do
        local name, ms = spell and spell.name, spell and spell.castMs
        if type(name) == "string" and type(ms) == "number" and ms > 0 then
            idx[name] = ms
        end
    end
    return idx
end

--- The 4th GetNetStats return, the latency WST folds into its cast length
--- (Castbar.lua:183-187). The pinned declaration's return list carries
--- (in, out, latencyList) -- the 4th value is NOT in it (§B12), so this
--- helper exists for the launch probe ONLY; no timing math of ours rides
--- it today (Gap-12: skip-until-probe). Returns plain milliseconds or nil.
function M.NetLatency()
    if type(GetNetStats) ~= "function" then return nil end
    local ok, _, _, _, latency = pcall(GetNetStats)
    if not ok then return nil end
    local v = FX.Compat.PlainOrNil(latency)
    return (type(v) == "number" and v >= 0) and v or nil
end

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

local function onToolEvent(self, event, a1, a2, a3, a4)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unitTarget, castGUID, spellID[, castBarID]) -- a2 guid, a3 id.
        local name = canonicalName(resolveCastName(a3))
        if name then
            self.Aspects:OnCast(name)
            self.Swing:OnCast(name)
            self.Swing:OnShotCast("SUCCEEDED", name, a3, a2)
        end
    elseif event == "UNIT_SPELLCAST_SENT" then
        -- CAT (UnitDocumentation.lua): SENT(unitTarget, target, castGUID,
        -- spellID) -- FOUR payload slots: slot two is the target string
        -- (ConditionalSecret, rides UNREAD), the guid is slot three and
        -- the spell id slot four (the live-review #2 finding: reading the
        -- 3-slot shape here resolved the spell from the GUID -- nil --
        -- and the whole SENT leg died).
        local name = canonicalName(resolveCastName(a4))
        if name then
            self.Swing:OnShotCast("SENT", name, a4, a3)
        end
    elseif event == "UNIT_SPELLCAST_START"
        or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED"
        or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        local name = canonicalName(resolveCastName(a3))
        if name then
            -- "UNIT_SPELLCAST_" is 15 characters: the kind starts at 16
            -- (sub(15) yields "_START" and never matches -- the
            -- live-review #2 finding).
            self.Swing:OnShotCast(event:sub(16), name, a3, a2)
        end
    elseif event == "PLAYER_SWING" then
        -- a1, a2 = swingDuration, swingType
        self.Swing:OnSwingStart(a1, a2)
    elseif event == "PLAYER_SWING_RANGE_UPDATE" then
        -- a1, a2, a3 = swingType, isInRange, checksRange
        self.Swing:OnSwingRange(a1, a2, a3)
    elseif event == "PLAYER_REGEN_ENABLED" then
        self.Aspects:Reconcile()
    elseif event == "PLAYER_STARTED_MOVING" then
        self.Swing:OnPlayerStartedMoving()
    elseif event == "PLAYER_STOPPED_MOVING" then
        self.Swing:OnPlayerStoppedMoving()
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Target facts are target-scoped: drop them (WST :158-175 law;
        -- the pendings/GUID ride the same drop -- an aim in flight belongs
        -- to the old target's cycle).
        local sw = self.Swing
        sw.factsInRange = nil
        sw.at, sw.pending = nil, nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        local sw = self.Swing
        sw.factsInRange, sw.at, sw.pending, sw.cast = nil, nil, nil, nil
        sw.flying, sw.feignPending, sw.retryUntil = nil, nil, nil
        sw.movePulseAt = nil
    elseif event == "START_AUTOREPEAT_SPELL" then
        -- No payload (the pinned declaration carries none): Auto Shot and
        -- wand Shoot share this one path -- the §B2 finding.
        self.Swing:OnAutoRepeatStart()
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        self.Swing:OnAutoRepeatStop()
    end
end

-- ------------------------------------------------- the swing range check --
--- `C_SwingTimer.EnableRangeCheck(swingType, bool)` is the OPT-IN that
--- makes PLAYER_SWING_RANGE_UPDATE carry a `checksRange` that is ever true
--- (upstream-addons-2026-11-03 §3: "opt in to range edges"), so a consumer
--- of those edges has to ask for them. One owner of the switch, a request
--- table, the check riding the union of the requests: the swing tracker
--- (this file, for the readiness gate's second range signal) and the range
--- light (UI/Range.lua, whose "showing the light enables the check" law is
--- unchanged by the routing). Feature-detected on every leg: the symbol is
--- catalog-declared and absent from the simulator (C_SwingTimer = nil,
--- measured 2026-11-03), so the arm is a no-op there.
local function armRangeCheck(on)
    local t = rangedTypePlain()
    if t == nil then return end
    local CST = _G.C_SwingTimer
    if not (CST and CST.EnableRangeCheck) then return end
    pcall(CST.EnableRangeCheck, t, on and true or false)
end

M._rangeCheckRequests = {}

function M.RequestRangeCheck(key, on)
    local wants = M._rangeCheckRequests
    if type(key) ~= "string" then return end
    on = not not on
    if wants[key] == on then return end
    if on then wants[key] = true else wants[key] = nil end
    local any = next(wants) ~= nil
    if M._rangeCheckOn == any then return end
    M._rangeCheckOn = any
    armRangeCheck(any)
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
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
    f:RegisterEvent("PLAYER_SWING")
    f:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_STARTED_MOVING")
    f:RegisterEvent("PLAYER_STOPPED_MOVING")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("START_AUTOREPEAT_SPELL")
    f:RegisterEvent("STOP_AUTOREPEAT_SPELL")
    -- OnEvent receives (frame, event, ...): swallow the frame, or `event`
    -- would be the frame and no branch would ever match. Four payload
    -- slots: UNIT_SPELLCAST_SENT is (unitTarget, target, castGUID,
    -- spellID) -- a three-slot binding drops its spell id.
    f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
        onToolEvent(M, event, a1, a2, a3, a4)
    end)
    -- The gate's second range signal rides the range edges, and those
    -- edges need the opt-in (no-op where C_SwingTimer is absent).
    M.RequestRangeCheck("swing", true)
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
            f:UnregisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_START", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_FAILED_QUIET", "player")
        end
        if f.UnregisterEvent then
            f:UnregisterEvent("PLAYER_SWING")
            f:UnregisterEvent("PLAYER_SWING_RANGE_UPDATE")
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            f:UnregisterEvent("PLAYER_STARTED_MOVING")
            f:UnregisterEvent("PLAYER_STOPPED_MOVING")
            f:UnregisterEvent("PLAYER_TARGET_CHANGED")
            f:UnregisterEvent("PLAYER_ENTERING_WORLD")
            f:UnregisterEvent("START_AUTOREPEAT_SPELL")
            f:UnregisterEvent("STOP_AUTOREPEAT_SPELL")
        end
        f:SetScript("OnEvent", nil)
    end
    M.RequestRangeCheck("swing", false)
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
    local phase = M.Swing:CycleState()
    return string.format(
        "Hunter: %d aspects | current=%s%s | ranged swing: %s%s",
        #snap.aspects,
        tostring(snap.current),
        snap.missing and " (no aspect -- cast one)" or "",
        fraction and string.format("%.0f%% (%.1fs left)", fraction * 100, remaining)
            or "idle",
        phase and string.format(" | phase=%s aim=%.2f", phase,
            M.Swing.aimLen) or "")
end

--- `/fx status` integration: prints its own line (review m6 -- modules
--- print, the Core registry only loops).
function M:Status()
    FX.Print(M:StatusLine())
end

FX.RegisterModule("Hunter", M)
