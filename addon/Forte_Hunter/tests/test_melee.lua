-- addon/Forte_Hunter/tests/test_melee.lua
-- Slice β of docs/research/wst-swing-design.md §7.8: the opt-in melee
-- rail (§7.5). Files: Core/Melee.lua (the main-hand clock), UI/Melee.lua
-- (the renderer), the two .toc lines. The six acceptance items of §7.8 β,
-- on the injected-clock / injected-reader / injected-meter law of
-- test_swing2.lua / test_swing3.lua (no real time, no live target reads;
-- the event-machine legs drive the REAL OnEvent script on
-- MeleeCore._eventFrame -- the test_hunter.lua law: a payload contract
-- is only proven when the frame script dispatches it).
--
-- The sim profile is not a Hunter, so the modules' class-gated OnEnable
-- never fires in a gate run -- Init / SetEnabled / EnableEvents are
-- driven directly (the established pattern of test_swing.lua's class
-- gate test). FX._playerClass is set for a leg and restored by that leg
-- only (later files read the sim's class).

local FX = ForteXorcist
local Tools = FX.Hunter.Tools
local Swing = FX.Hunter.Swing
local RangeLight = FX.Hunter.RangeLight
local Melee = FX.Hunter.Melee
local Core = FX.Hunter.MeleeCore

-- Frame geometry round-trips float32 in the sim; the suite's tolerance.
local function nearpx(actual, expected)
    return assertTrue(math.abs(actual - expected) <= 0.5)
end

--- The injected-clock tracker: mainHandType pinned to the catalog value
--- (Enum.PlayerSwingType.MainHand = 0) so no leg depends on the sim's
--- Enum table.
local function meleeTracker(clock, extra)
    local opts = {
        now = function() return clock[1] end,
        mainHandType = 0,
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    return FX.Hunter.NewMeleeTracker(opts)
end

local function meterReading(band)
    return {
        GetBand = function()
            if band == nil then return nil, nil end
            return band, string.upper(band)
        end,
    }
end

local function restoreRail()
    Melee:SetTracker(Core.Tracker)
    Melee:SetMeter(FX.Hunter.RangeMeter)
    Melee.combatReader = nil
    Melee:SetEnabled(false)
    RangeLight:SetEnabled(false)
    Core:DisableEvents()
end

-- ------------------------------------------------- acceptance 1: the clock --

test("melee β: default OFF builds no frame and registers no events", function()
    -- The §7.8 β off law: EnableMeleeRail defaults off -- no frame, no
    -- ticker, no event registration (the sim never enabled the rail).
    assertNil(Melee.anchor)
    assertNil(Melee._wired)
    assertFalse(Core._eventsEnabled and true or false)
    assertNil(Core._eventFrame and Core._eventFrame:GetScript("OnEvent"))
end)

test("melee β: MainHand arms from the event duration; Ranged/OffHand drop; secret/<=0 drops",
function()
    local clock = { 2000 }
    local t = meleeTracker(clock)
    t:OnSwingStart(2.0, 0)                       -- MainHand (CAT value 0)
    assertTrue(t.active)
    nearpx(t.duration, 2.0)
    local fraction, remaining = t:Progress(2000)
    nearpx(fraction, 0)
    nearpx(remaining, 2.0)

    -- Ranged (2) is the ranged tracker's slot; OffHand (1) is a non-goal
    -- (§7.5: a Hunter does not off-hand swing). Both drop.
    local u = meleeTracker(clock)
    u:OnSwingStart(2.0, 2)
    u:OnSwingStart(1.6, 1)
    assertFalse(u.active)
    assertNil(u.duration)

    -- A secret/absent duration drops -- the rail has no speed-fallback
    -- chain (unlike the ranged cycle): only the event's own length arms.
    u:OnSwingStart(nil, 0)
    assertNil(u.duration)
    u:OnSwingStart(0, 0)
    u:OnSwingStart(-1, 0)
    assertNil(u.duration)
    assertNil(u.lastDuration)
end)

test("melee β: the REAL event script arms the main clock and leaves the ranged tracker untouched",
function()
    local clock = { 2100 }
    local savedCore = Core.Tracker
    Core.Tracker = meleeTracker(clock)
    local sw = Tools.Swing
    local was = { active = sw.active, start = sw.start,
        duration = sw.duration, aimLen = sw.aimLen, phase = sw.phase }
    Core:EnableEvents()
    local f = Core._eventFrame
    local script = f:GetScript("OnEvent")
    assertNotNil(script, "the rail's event frame carries the OnEvent script")

    -- PLAYER_SWING(swingDuration, swingType) DURATION FIRST: a MainHand
    -- swing arms the rail's clock...
    script(f, "PLAYER_SWING", 2.5, 0)
    nearpx(Core.Tracker.duration, 2.5)
    assertTrue(Core.Tracker.active)
    -- ...a Ranged swing is dropped by the filter, and
    local swAfterRanged = { active = sw.active, start = sw.start,
        duration = sw.duration }
    script(f, "PLAYER_SWING", 3.0, 2)
    nearpx(Core.Tracker.duration, 2.5, "the Ranged type is not the rail's")
    -- The Ranged slot of the SAME payload stream never reaches the
    -- ranged tracker through this frame (this file owns neither filter):
    -- the ranged tracker's state is stable across both legs.
    assertEquals(was.active, sw.active)
    assertEquals(was.start, sw.start)
    assertEquals(was.duration, sw.duration)
    assertEquals(was.active, swAfterRanged.active)
    assertEquals(was.duration, swAfterRanged.duration)

    -- UNIT_ATTACK_SPEED (unitTarget): the player's edge re-reads the
    -- speed leg (the 1st UnitAttackSpeed return), a foreign unit's does
    -- not touch it.
    local savedAS = _G.UnitAttackSpeed
    _G.UnitAttackSpeed = function() return 2.2, 1.6, 3.1 end
    script(f, "UNIT_ATTACK_SPEED", "player")
    nearpx(Core.Tracker.speed, 2.2)
    _G.UnitAttackSpeed = function() return 2.9, 1.6, 3.1 end
    script(f, "UNIT_ATTACK_SPEED", "pet")
    nearpx(Core.Tracker.speed, 2.2, "a foreign unit's speed edge is not ours")
    _G.UnitAttackSpeed = savedAS

    Core:DisableEvents()
    assertNil(f:GetScript("OnEvent"),
        "the disabled state is observable (the Tools.lua DisableEvents law)")
    Core.Tracker = savedCore
end)

-- --------------------------------------------- acceptance 2: full = ready --

test("melee β: full = ready -- 0 width at the arm, full width at arm+d, tenths text",
function()
    Swing:Init()
    RangeLight:Init()
    local clock = { 4000 }
    local t = meleeTracker(clock)
    Melee:SetTracker(t)
    Melee.combatReader = function() return true end
    Melee:SetEnabled(true)
    assertNotNil(Melee.anchor, "enabled = the frame arrives")
    nearpx(Melee.anchor:GetHeight(), 8)
    nearpx(Melee.anchor:GetWidth(), 200)         -- same width as the bar
    t:OnSwingStart(2.0, 0)

    -- The arm instant: the rail is up, the fill has ZERO width, the text
    -- prints the full cycle in tenths.
    assertTrue(Melee:Refresh())
    assertTrue(Melee.anchor:IsShown())
    local W = Melee._w
    nearpx(W, 200)
    nearpx(Melee.fill:GetWidth(), 0)
    assertEquals("2.0", Melee.text:GetText())
    assertNotNil(Melee.anchor:GetScript("OnUpdate"),
        "the ticker runs only while the rail is on screen")

    clock[1] = 4001.0
    assertTrue(Melee:Refresh())
    nearpx(Melee.fill:GetWidth(), W * 0.5)
    assertEquals("1.0", Melee.text:GetText())

    clock[1] = 4001.5
    assertTrue(Melee:Refresh())
    nearpx(Melee.fill:GetWidth(), W * 0.75)
    assertEquals("0.5", Melee.text:GetText())

    -- FULL = THE SWING IS READY: at arm + d the fill spans the whole
    -- width and the text reads the zero.
    clock[1] = 4002.0
    assertTrue(Melee:Refresh())
    nearpx(Melee.fill:GetWidth(), W)
    assertEquals("0.0", Melee.text:GetText())

    -- The idle law: no clock = hidden, the per-frame script gone.
    t:Reset()
    assertFalse(Melee:Refresh())
    assertFalse(Melee.anchor:IsShown())
    assertNil(Melee.anchor:GetScript("OnUpdate"))
    restoreRail()
end)

-- -------------------------------------------------- acceptance 3: the speed --

test("melee β: UnitAttackSpeed's FIRST return is the speed leg; secret keeps; 0/nil parks",
function()
    local savedAS = _G.UnitAttackSpeed
    local clock = { 5000 }
    -- The declared (attackSpeed, offhandAttackSpeed, rangedAttackSpeed)
    -- trio (UnitDocumentation.lua:681) -- the 1st return is the main slot.
    _G.UnitAttackSpeed = function() return 2.4, 1.6, 3.1 end
    local t = meleeTracker(clock)                -- the LIVE leg, no seam
    t:ReadSpeed()
    nearpx(t.speed, 2.4)
    assertTrue(math.abs(t.speed - 1.6) > 0.01, "the off-hand leg does not ride")
    assertTrue(math.abs(t.speed - 3.1) > 0.01, "the ranged leg does not ride")

    -- A raising / locked read is NO KNOWLEDGE: the last known speed
    -- survives (the secret-value law -- nil never overwrites knowledge).
    _G.UnitAttackSpeed = function() error("locked") end
    t:ReadSpeed()
    nearpx(t.speed, 2.4)
    assertNil(t.parked)

    -- The slot PLAINLY reporting no speed parks the rail: a plain nil...
    _G.UnitAttackSpeed = function() return nil, nil, nil end
    t:ReadSpeed()
    assertTrue(t.parked)
    assertNil(t.speed)
    -- ...and a plain 0 park the same way.
    _G.UnitAttackSpeed = function() return 0, 0, 0 end
    local u = meleeTracker(clock)
    u:ReadSpeed()
    assertTrue(u.parked)

    -- The parked rail: hidden, the clock dropped, no division by zero.
    Swing:Init()
    RangeLight:Init()
    local savedCore = Core.Tracker
    Core.Tracker = t
    Melee:SetTracker(t)
    Melee.combatReader = function() return true end
    Melee:SetEnabled(true)
    t:OnSwingStart(2.0, 0)                       -- a swing lifts the park
    assertTrue(Melee:Refresh())
    assertTrue(Melee.anchor:IsShown())
    t:ReadSpeed()                                -- the 0 read parks it again
    assertTrue(t.parked)
    assertFalse(Melee:Refresh())
    assertFalse(Melee.anchor:IsShown())
    assertNil(t:Progress(5000))
    -- The no-division-by-zero guard of Progress itself.
    t.active, t.duration = true, 0
    assertNil(t:Progress(5000))
    t.active, t.duration, t.parked = false, nil, nil

    Core.Tracker = savedCore
    restoreRail()
    _G.UnitAttackSpeed = savedAS
end)

-- ------------------------------------------------- acceptance 4: the reward --

--- Probe a sim-client spell id by name (the test_swing2.lua probeID law:
--- the sim resolves its own spell book through C_Spell.GetSpellInfo --
--- the same seam the production event frame runs). The classic rank
--- family of the reference (2973 / 14260..14266 / 27014) is probed
--- alongside our data's Forever family (415335..415343) -- whichever the
--- build carries is the row the event leg rides; nil skips it.
local function probeID(englishName)
    local ids = { 2973 }
    for id = 14260, 14266 do ids[#ids + 1] = id end
    ids[#ids + 1] = 27014
    for id = 415335, 415343 do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local name = Tools.ResolveCastName(id)
        local canon = name and Tools.CanonicalCastName(name)
        if canon == englishName then return id end
    end
    return nil
end

test("melee β: Raptor Strike by NAME re-arms to the last known MH speed; Mongoose Bite and non-players do not",
function()
    local clock = { 6000 }
    local t = meleeTracker(clock, {
        speedReader = function() return 2.4 end,
    })
    t:ReadSpeed()
    nearpx(t.speed, 2.4)
    t:OnSwingStart(3.0, 0)                       -- start 6000, length 3.0
    clock[1] = 6001.0

    -- A cast by a NON-PLAYER is not the player's swing.
    t:OnCastSucceeded("pet", "Raptor Strike")
    nearpx(t.start, 6000)
    nearpx(t.duration, 3.0)
    -- Mongoose Bite is NOT in the reset set (its absence from the
    -- reference's table is the fact, Core.lua:35-39).
    t:OnCastSucceeded("player", "Mongoose Bite")
    nearpx(t.start, 6000)
    nearpx(t.duration, 3.0)
    -- Raptor Strike, by NAME: the clock re-arms NOW from the last known
    -- MH speed.
    t:OnCastSucceeded("player", "Raptor Strike")
    nearpx(t.start, 6001)
    nearpx(t.duration, 2.4)
    local fraction = t:Progress(6001.0)
    nearpx(fraction, 0)
    -- A fresh speed read rides the next re-arm (the last known speed).
    t.speed = 2.0
    clock[1] = 6002.0
    t:OnCastSucceeded("player", "Raptor Strike")
    nearpx(t.duration, 2.0)
    nearpx(t.start, 6002)
end)

test("melee β: the REAL event script re-arms on the resolved Raptor Strike name", function()
    local raptorID = probeID("Raptor Strike")
    if raptorID == nil then
        print("[melee] this sim build carries no Raptor Strike row: the "
            .. "event leg rides the injected seam above")
        return
    end
    local savedCore = Core.Tracker
    local savedAS = _G.UnitAttackSpeed
    _G.UnitAttackSpeed = function() return 2.6, 1.6, 3.1 end
    Core.Tracker = FX.Hunter.NewMeleeTracker()   -- the live clock (GetTime)
    Core.Tracker:ReadSpeed()
    nearpx(Core.Tracker.speed, 2.6)
    Core:EnableEvents()
    local f = Core._eventFrame
    local script = f:GetScript("OnEvent")
    assertNotNil(script)

    -- (unitTarget, castGUID, spellID): the GUID slot rides UNREAD, the
    -- id resolves through Tools.ResolveCastName + the canonicalize law.
    Core.Tracker:Reset()
    script(f, "UNIT_SPELLCAST_SUCCEEDED", "pet", "G1", raptorID)
    assertFalse(Core.Tracker.active, "a non-player cast does not re-arm")
    script(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "G2", raptorID)
    assertTrue(Core.Tracker.active, "the player's Raptor Strike re-arms")
    nearpx(Core.Tracker.duration, 2.6)           -- the last known MH speed

    Core:DisableEvents()
    Core.Tracker = savedCore
    _G.UnitAttackSpeed = savedAS
end)

-- ----------------------------------------------------- acceptance 5: gate --

test("melee β: the gate -- the rail draws iff (light off) or (light on and band melee), in combat",
function()
    Swing:Init()
    RangeLight:Init()
    local clock = { 7000 }
    local t = meleeTracker(clock)
    Melee:SetTracker(t)
    Melee.combatReader = function() return true end
    Melee:SetMeter(meterReading("melee"))
    Melee:SetEnabled(true)
    t:OnSwingStart(2.0, 0)

    -- The light OFF: the gate opens on the clock alone (the "the range
    -- light is off" branch).
    RangeLight:SetEnabled(false)
    assertTrue(Melee:Refresh())
    assertTrue(Melee.anchor:IsShown())

    -- The light ON: the band owns the gate.
    RangeLight:SetEnabled(true)
    Melee:SetMeter(meterReading("ranged"))
    assertFalse(Melee:Refresh())
    assertFalse(Melee.anchor:IsShown())
    Melee:SetMeter(meterReading("deadzone"))
    assertFalse(Melee:Refresh())
    Melee:SetMeter(meterReading("melee"))
    assertTrue(Melee:Refresh())
    assertTrue(Melee.anchor:IsShown())
    -- The meter's nil band (no target / no knowledge) is NOT the melee
    -- band: closed.
    Melee:SetMeter(meterReading(nil))
    assertFalse(Melee:Refresh())
    Melee:SetMeter(meterReading("melee"))
    assertTrue(Melee:Refresh())

    -- The out-of-combat law: hidden, and no ticker survives it.
    Melee.combatReader = function() return false end
    assertFalse(Melee:Refresh())
    assertFalse(Melee.anchor:IsShown())
    assertNil(Melee.anchor:GetScript("OnUpdate"))
    -- No knowledge is closed too (the rail draws on a proven fact).
    Melee.combatReader = function() return nil end
    assertFalse(Melee:Refresh())
    Melee.combatReader = function() return true end
    assertTrue(Melee:Refresh())

    -- EnableMeleeRail = false: the frame is never shown, no ticker runs,
    -- and the rail's events are NOT registered (the §7.8 β off law).
    Melee:SetEnabled(false)
    assertFalse(Melee.anchor:IsShown())
    assertNil(Melee.anchor:GetScript("OnUpdate"))
    assertFalse(Core._eventsEnabled and true or false)
    assertNil(Core._eventFrame and Core._eventFrame:GetScript("OnEvent"))

    -- And the on edge routes the registration through the class gate
    -- (the class-gate test pattern of test_swing.lua: drive it).
    local savedClass = FX._playerClass
    FX._playerClass = "HUNTER"
    Melee:SetEnabled(true)
    Melee:OnTrackerEvent()
    assertTrue(Core._eventsEnabled, "enabled = the rail's events are live")
    assertNotNil(Core._eventFrame:GetScript("OnEvent"))
    Melee:SetEnabled(false)
    assertFalse(Core._eventsEnabled and true or false)
    assertNil(Core._eventFrame:GetScript("OnEvent"))
    Melee:SetEnabled(true)
    Melee:OnTrackerEvent()
    assertTrue(Core._eventsEnabled)
    FX._playerClass = savedClass
    Melee:SetEnabled(false)
    assertFalse(Core._eventsEnabled and true or false,
        "off outside the class = no events")
    Melee:SetEnabled(true)      -- leave the flag consistent for the next leg
    restoreRail()
end)

-- ---------------------------------------------------- acceptance 6: stack --

test("melee β: the stack -- swing bar -> light -> rail, each anchored off the bar (one drag)",
function()
    Swing:Init()
    RangeLight:Init()
    local clock = { 8000 }
    local t = meleeTracker(clock)
    Melee:SetTracker(t)
    Melee.combatReader = function() return true end
    Melee:SetMeter(meterReading("melee"))
    RangeLight:SetEnabled(true)
    Melee:SetEnabled(true)
    t:OnSwingStart(2.0, 0)
    assertTrue(Melee:Refresh())
    assertTrue(Melee.anchor:IsShown())

    -- The rail rides under the light, the light rides under the bar:
    -- every frame anchored off the swing bar's frame (directly, or off
    -- it through the light), so one drag of the bar moves all three.
    local point, relTo, relPoint, x, y = Melee.anchor:GetPoint()
    assertEquals("TOPLEFT", point)
    assertEquals("BOTTOMLEFT", relPoint)
    assertTrue(relTo == RangeLight.anchor,
        "with the light on the rail anchors to the LIGHT")
    nearpx(x, 0)
    nearpx(y, -4)
    local lightPoint, lightRelTo, lightRelPoint, lx, ly =
        RangeLight.anchor:GetPoint()
    assertEquals("TOPLEFT", lightPoint)
    assertTrue(lightRelTo == Swing.anchor,
        "the light anchors to the SWING BAR -- the whole chain rides it")
    nearpx(lx, 0)
    nearpx(ly, -4)

    -- The light off: on the next show the rail retargets directly under
    -- the bar (the stack keeps its -4 law).
    RangeLight:SetEnabled(false)
    Melee:HideNow()
    assertTrue(Melee:Refresh())
    local point2, relTo2, relPoint2, x2, y2 = Melee.anchor:GetPoint()
    assertEquals("TOPLEFT", point2)
    assertTrue(relTo2 == Swing.anchor,
        "with the light off the rail rides the BAR")
    assertEquals("BOTTOMLEFT", relPoint2)
    nearpx(x2, 0)
    nearpx(y2, -4)
    restoreRail()
end)
