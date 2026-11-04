-- addon/Forte_Hunter/Core/Melee.lua
-- FX.Hunter.MeleeCore: the main-hand swing clock behind the opt-in melee
-- rail (docs/research/wst-swing-design.md §7.5, slice §7.8 β -- the P5
-- question "is my main-hand swing up (the Raptor Strike reset reward)").
-- All STATE lives here; the renderer is UI/Melee.lua (FX.Hunter.Melee).
--
-- The clock (laws adapted from WeaponSwingTimer SixxFix, GPLv3,
-- WatchYourSixx; original WST by LeftHandedGlove -- credited
-- Forte_Core/ATTRIBUTION.md:38-49; numbers and shape only, none of its
-- skin, spell-id sets, combat-log path, parry-haste leg or off-hand rail
-- -- §7.5's non-goals and §7.9):
--   * PLAYER_SWING(swingDuration, swingType) DURATION FIRST
--     (SwingTimerDocumentation.lua:42 -- the verified Forever contract,
--     Core/Tools.lua header): a MainHand type arms the clock from the
--     EVENT DURATION (the WeaponSwingTimer_Player.lua:81-102 law).
--     Ranged (2) is Core/Tools.lua's SwingTracker's slot and is dropped
--     here; OffHand (1) is dropped as a non-goal (§7.5: "a Hunter does
--     not off-hand swing -- the row could never be used"). A
--     secret/absent (PlainOrNil nil) or non-positive duration is DROPPED
--     -- unlike the ranged cycle there is no speed-fallback chain: the
--     rail is a companion signal, and arming it on an unproven number is
--     the §7.5 gate philosophy (only actionably-true information draws).
--   * Enum.PlayerSwingType MainHand = 0 (SwingTimerDocumentation.lua:70);
--     the touch is pcall-guarded through PlainOrNil (a secret table can
--     not raise), the catalog value is the fallback (the
--     Core/Tools.lua rangedTypePlain idiom).
--   * Speed per slot from UnitAttackSpeed("player")'s FIRST return (the
--     declared (attackSpeed, offhandAttackSpeed, rangedAttackSpeed) trio,
--     UnitDocumentation.lua:681 -- the main slot's leg, mirroring the
--     per-slot SwingTracker:SlotSpeed law), every return through
--     PlainOrNil; re-read on UNIT_ATTACK_SPEED (unit-only payload,
--     UnitDocumentation.lua:4142). A secret / raising read = "no
--     knowledge": the last known speed SURVIVES (the secret-value law --
--     nil never overwrites knowledge). A plain 0 / plain nil = the slot
--     reports NO speed (the measured "no row" shape: an unarmed main
--     hand) and PARKS the rail: parked = hidden, clock dropped, no
--     division by zero, nothing draws until a UNIT_ATTACK_SPEED read
--     returns a speed.
--   * The reward: a UNIT_SPELLCAST_SUCCEEDED whose resolved canonical
--     NAME is "Raptor Strike" re-arms the clock from the last known MH
--     speed (the effect of WeaponSwingTimer_Player.lua:187-189 via
--     Core.lua:30-39 + :70-82). KEYED BY NAME, never by WST's classic
--     rank ids (2973 / 14260..14266 / 27014 are not the Forever family --
--     our data ships 415335-415343, Data/Hunter.lua:63/:143; the AGENTS
--     locale law, §7.9 trap 1). Mongoose Bite is NOT in the reset set
--     (its absence from the reference's table, Core.lua:35-39, is the
--     fact). The name arrives canonicalized at the event seam (the
--     Tools.CanonicalCastName law: client name -> data-English key).
--
-- Secret-value law: every value read from a unit API passes
-- FX.Compat.PlainOrNil before any compare or arithmetic; the cast GUID
-- slot of the SUCCEEDED payload rides UNREAD (the Tools M3 law).
--
-- Events are registered inside the module's EnableEvents (run from
-- OnEnable / OnClassChanged / the rail's SetEnabled), never at file load
-- (the Init.lua taint rule), and ONLY while the rail is enabled --
-- "EnableMeleeRail default OFF: no frame, no ticker, no event
-- registration when off" (§7.8 β). The event frame therefore also KICKS
-- the renderer (FX.Hunter.Melee:OnTrackerEvent) on every leg it sees:
-- the rail needs no consumer of Core/Tools.lua's or UI/Swing.lua's
-- frames, and this file touches none of theirs.
--
-- The launch-day caveat (wst-swing-design.md §8 probe 4): if MainHand
-- PLAYER_SWING events turn out not to reach third-party addons, the
-- clock simply never arms, the rail stays hidden and the §7.5 gate makes
-- that a silent, honest degradation.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Hunter = FX.Hunter or {}

local MeleeTracker = {}
MeleeTracker.__index = MeleeTracker

--- The canonical (data key space) name of the reset reward. The event
--- seam canonicalizes the CLIENT's name onto this key (the
--- Tools.CanonicalCastName law) -- never a hand-typed spell id.
local RAPTOR_STRIKE = "Raptor Strike"

--- The MainHand swing type as a plain number, the catalog value (0) the
--- fallback (Core/Tools.lua's pcall-guarded Enum idiom).
local function mainHandTypePlain()
    local ok, v = pcall(function()
        local e = _G.Enum and _G.Enum.PlayerSwingType
        return FX.Compat.PlainOrNil(e and e.MainHand)
    end)
    if ok and type(v) == "number" then return v end
    return 0
end

function MeleeTracker:Clock()
    if self.now then return self.now() end
    return GetTime()
end

--- The main-hand leg of the declared UnitAttackSpeed trio. Returns
--- (speed, noSpeed):
---   speed > 0, nil      -- the slot's plain seconds-per-swing
---   nil, true           -- the slot PLAINLY reports no speed (0 / plain
---                        -- nil): the rail parks
---   nil, nil            -- no knowledge (raising read, secret value,
---                        -- absent API): the last known speed survives
--- An injected speedReader (tests, gear models) rides the same contract
--- through the same PlainOrNil pass (its secret shape = nil).
function MeleeTracker:SlotSpeed()
    local reader = self.speedReader
    if reader then
        local ok, v = pcall(reader)
        if not ok then return nil, nil end
        v = FX.Compat.PlainOrNil(v)
        if type(v) == "number" then
            if v > 0 then return v, nil end
            return nil, true
        end
        if v == nil then
            -- An injected reader's nil is the plain "no row" answer (the
            -- contract above); the secret shape of a nil is the LIVE leg's
            -- issecretvalue test below.
            return nil, true
        end
        return nil, nil
    end
    if type(_G.UnitAttackSpeed) ~= "function" then return nil, nil end
    -- The 1st return is the main hand (UnitDocumentation.lua:681); the
    -- 2nd/3rd (offhand, ranged) are other slots' rows, not this clock's.
    local ok, main = pcall(_G.UnitAttackSpeed, "player")
    if not ok then return nil, nil end
    local v = FX.Compat.PlainOrNil(main)
    if type(v) == "number" then
        if v > 0 then return v, nil end
        return nil, true                      -- a plain 0: no speed
    end
    if v == nil then
        -- Distinguish the secret (no knowledge -- keep the last known
        -- speed) from the plain nil (the slot reports no row -- park).
        local iss = _G.issecretvalue
        if type(iss) == "function" then
            local ok2, secret = pcall(iss, main)
            if ok2 and secret then return nil, nil end
        end
        return nil, true
    end
    return nil, nil
end

--- Re-read the speed leg and fold it into the clock's knowledge (the
--- UNIT_ATTACK_SPEED body, also run at event-enable and zone-in).
function MeleeTracker:ReadSpeed()
    local speed, none = self:SlotSpeed()
    if speed ~= nil then
        self.speed = speed
        self.parked = nil
        return
    end
    if none then
        self.speed = nil
        self.parked = true
        -- A parked rail has no clock (the no-division-by-zero law).
        self.active, self.start, self.duration = false, nil, nil
    end
end

--- PLAYER_SWING body -- payload (swingDuration, swingType), DURATION
--- FIRST. MainHand arms; Ranged/OffHand and every other type drop; a
--- secret/absent or non-positive duration drops (no fallback chain --
--- the file header).
function MeleeTracker:OnSwingStart(duration, swingType)
    if swingType ~= self.mainHandType then return end
    duration = FX.Compat.PlainOrNil(duration)
    if duration == nil then return end
    if type(duration) ~= "number" or duration <= 0 then return end
    -- A swing arriving is proof the main hand swings: lift a park.
    self.parked = nil
    self.active, self.start, self.duration = true, self:Clock(), duration
    self.lastDuration = duration
end

--- UNIT_ATTACK_SPEED body -- payload (unitTarget), unit-only
--- (UnitDocumentation.lua:4142). Any slot's edge re-reads the trio; a
--- foreign unit's edge is not ours.
function MeleeTracker:OnUnitAttackSpeed(unitTarget)
    if unitTarget ~= nil and unitTarget ~= "player" then return end
    self:ReadSpeed()
end

--- The Raptor Strike reset (the weave reward). `name` is the CANONICAL
--- (data key space) resolved name; a non-player cast is not the
--- player's swing. Re-arms from the last known MH speed (the effect of
--- WeaponSwingTimer_Player.lua:187-189); with no speed knowledge the
--- last observed cycle length stands; with neither, nothing re-arms.
function MeleeTracker:OnCastSucceeded(unitTarget, name)
    if unitTarget ~= "player" then return end
    if name ~= RAPTOR_STRIKE then return end
    if self.parked then return end
    local d = self.speed
    if type(d) ~= "number" or d <= 0 then d = self.lastDuration end
    if type(d) ~= "number" or d <= 0 then return end
    self.active, self.start, self.duration = true, self:Clock(), d
    self.lastDuration = d
end

--- The clock's fraction (0..1) and seconds remaining: the fill law's
--- two numbers. FULL = the swing is READY (the reference's fill_empty
--- law, WeaponSwingTimer_Player.lua:280 -- ours is the one reading, no
--- toggle): past the cycle's end the clock reports full until the next
--- PLAYER_SWING re-arm, the Raptor re-arm, a park, or the gate ending
--- the draw. nil = no clock (idle / parked -- the caller draws nothing).
function MeleeTracker:Progress(now)
    if not self.active or self.parked then return nil end
    local d = self.duration
    if type(d) ~= "number" or d <= 0 then return nil end
    now = now or self:Clock()
    local elapsed = now - self.start
    if elapsed < 0 then elapsed = 0 end
    if elapsed >= d then return 1, 0 end
    return elapsed / d, d - elapsed
end

--- Drop the clock (zone-in; the speed knowledge re-reads right after).
function MeleeTracker:Reset()
    self.active, self.start, self.duration = false, nil, nil
end

--- Plain copy of the tracked state (no metatable, no live objects).
function MeleeTracker:Snapshot()
    local fraction, remaining = self:Progress()
    return {
        active = self.active and true or false,
        parked = self.parked and true or false,
        duration = self.duration,
        lastDuration = self.lastDuration,
        speed = self.speed,
        fraction = fraction,
        remaining = remaining,
    }
end

function FX.Hunter.NewMeleeTracker(opts)
    opts = opts or {}
    return setmetatable({
        mainHandType = opts.mainHandType or mainHandTypePlain(),
        now = opts.now,                     -- injectable clock for tests
        speedReader = opts.speedReader,     -- injectable speed seam
        active = false,
        start = nil,        -- Clock() seconds at the swing's start
        duration = nil,     -- the active cycle length, seconds
        lastDuration = nil, -- last observed length (re-arm fallback)
        speed = nil,        -- the last known MH speed (plain seconds)
        parked = nil,       -- the slot plainly reports no speed
    }, MeleeTracker)
end

-- ================================================================ module

FX.Hunter.MeleeCore = {}
local M = FX.Hunter.MeleeCore

--- The live clock. UI/Melee.lua (FX.Hunter.Melee) renders it; tests
--- inject their own tracker through the renderer's SetTracker seam.
M.Tracker = FX.Hunter.NewMeleeTracker()

--- Kick the renderer ("the clock may have moved"). Payloads arrive
--- UNREAD by everything except the documented legs above.
local function kickRail()
    local rail = FX.Hunter.Melee
    if rail and rail.OnTrackerEvent then rail:OnTrackerEvent() end
end

local function onMeleeEvent(self, event, a1, a2, a3)
    local t = self.Tracker
    if event == "PLAYER_SWING" then
        -- a1, a2 = swingDuration, swingType (duration FIRST).
        t:OnSwingStart(a1, a2)
    elseif event == "UNIT_ATTACK_SPEED" then
        -- a1 = unitTarget (unit-only payload).
        t:OnUnitAttackSpeed(a1)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unitTarget, castGUID, spellID): a1 unit, a2 guid rides UNREAD
        -- (the Tools M3 law), a3 id through the shared resolver.
        -- F3 (docs/reviews/code-review-8.md, MAJOR): the payload spellID
        -- is SecretWhenUnitSpellCastRestricted, so it gets NO raw
        -- comparison here -- not even `~= nil` (the law this file's header
        -- adopts, Core/Tools.lua:993-996). The dispatcher hands the slot to
        -- the resolver UNTOUCHED and the resolver's own pcall + PlainOrNil
        -- decide nil / secret / raise (the shape Tools' dispatcher runs,
        -- Core/Tools.lua:1087-1091); a comparison of the raw slot in this
        -- un-guarded OnEvent body is the raise that costs the re-arm.
        local T = FX.Hunter.Tools
        if T and T.ResolveCastName then
            local raw = T.ResolveCastName(a3)      -- nil for nil/secret/raise
            if raw then
                local canon = T.CanonicalCastName
                local name = (canon and canon(raw)) or raw
                t:OnCastSucceeded(a1, name)
            end
        end
    elseif event == "PLAYER_ENTERING_WORLD" then
        t:Reset()
        t:ReadSpeed()
    end
    -- PLAYER_REGEN_ENABLED / PLAYER_REGEN_DISABLED / PLAYER_TARGET_CHANGED
    -- carry no clock fact: the kick above is their whole job (the rail's
    -- gate re-reads combat state and the range band on it).
    kickRail()
end

--- Register the rail's events (idempotent while enabled). The frame is
--- created inside an OnEnable/OnClassChanged/enable path -- never at
--- file load. Runs ONLY while the rail is enabled (the §7.8 β law: off =
--- no event registration); speed knowledge seeds at the enable.
function M:EnableEvents()
    if self._eventsEnabled then return end
    local f = self._eventFrame
    if not f then
        f = CreateFrame("Frame")
        self._eventFrame = f
    end
    f:RegisterEvent("PLAYER_SWING")
    f:RegisterUnitEvent("UNIT_ATTACK_SPEED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- OnEvent receives (frame, event, ...): swallow the frame, or `event`
    -- would be the frame and no branch would ever match.
    f:SetScript("OnEvent", function(_, event, a1, a2, a3)
        onMeleeEvent(M, event, a1, a2, a3)
    end)
    self._eventsEnabled = true
    self.Tracker:ReadSpeed()
end

--- Tear the registrations back down (rail disabled / class moved away
--- from HUNTER). The SetScript(nil) is the part that silences the module
--- everywhere (Unregister* is catalog-declared for the real client but
--- absent from the simulator's frame emulation -- both nil-guarded, the
--- Tools.lua law); GetScript going nil makes the disabled state
--- observable for the tests.
function M:DisableEvents()
    local f = self._eventFrame
    if f and self._eventsEnabled then
        if f.UnregisterUnitEvent then
            f:UnregisterUnitEvent("UNIT_ATTACK_SPEED", "player")
            f:UnregisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        end
        if f.UnregisterEvent then
            f:UnregisterEvent("PLAYER_SWING")
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            f:UnregisterEvent("PLAYER_REGEN_DISABLED")
            f:UnregisterEvent("PLAYER_TARGET_CHANGED")
            f:UnregisterEvent("PLAYER_ENTERING_WORLD")
        end
        f:SetScript("OnEvent", nil)
    end
    self._eventsEnabled = false
end

--- The one routing point: events ride the rail's enabled state (and the
--- class gate). The renderer's SetEnabled calls it; so do OnEnable /
--- OnClassChanged.
function M:RefreshEvents()
    if FX._playerClass ~= "HUNTER" then
        self:DisableEvents()
        return
    end
    local rail = FX.Hunter.Melee
    if rail and rail.state and rail.state.enabled then
        self:EnableEvents()
    else
        self:DisableEvents()
    end
end

function M:OnEnable()
    self:RefreshEvents()
end

--- Core FX.RefreshPlayerClass notification (the uiforever T4 class
--- guard): the event frame follows the class.
function M:OnClassChanged(classFile)
    if classFile == "HUNTER" then
        self:RefreshEvents()
    else
        self:DisableEvents()
    end
end

--- One-line module state as a string (the /fx status seam).
function M:StatusLine()
    local t = M.Tracker
    local fraction, remaining = t:Progress()
    return string.format(
        "Melee clock: %s%s | speed=%s",
        fraction and string.format("%.0f%% (%.1fs left)",
            fraction * 100, remaining) or "idle",
        t.parked and " (parked: no MH speed)" or "",
        tostring(t.speed))
end

--- `/fx status` integration: prints its own line (the Core status law).
function M:Status()
    FX.Print(M:StatusLine())
end

FX.RegisterModule("HunterMelee", M)
