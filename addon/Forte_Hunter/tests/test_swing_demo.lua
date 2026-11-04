-- addon/Forte_Hunter/tests/test_swing_demo.lua
-- The `/fx test` swing demo (Core/SwingDemo.lua, PLAN §11.4 row K2): the
-- feeder registration, the real slash path running a CYCLING demo on the
-- real bar with the real markers, the untouched-and-restored real tracker,
-- the combat scrub's restore, and the class gate.
--
-- The drives are the real ones: `FX.OnSlash("test")` (the real slash
-- registry), the TestMode frame's own OnEvent script for the combat edge,
-- the bar's REAL `Update` render pass sampled over the cycle (the
-- test_swing2/3 idiom), and `SwingDemo:Beat` for the ticker the C_Timer
-- surface cannot fire headless. The player class is scripted through
-- `FX._playerClass` (the tests/test_items.lua idiom) and handed back.
--
-- The tracker-equality law of K2: the demo rides a SWAPPED tracker (the
-- public `D:SetTracker` seam), so `FX.Hunter.Tools.Swing` must be
-- bit-identical across the whole demo cycle -- every field stringed, not
-- just the headline ones.

local FX = ForteXorcist
local T = FX.TestMode
local Tools = FX.Hunter.Tools
local Swing = FX.Hunter.Swing
local Demo = FX.Hunter.SwingDemo

local savedClass = FX._playerClass

local function enableAll()
    if not T._eventFrame then T:OnEnable() end
    Demo:OnEnable()                     -- idempotent by feeder name
    Swing:Init()                        -- idempotent; the test_swing3 idiom
end

local function asHunter() FX._playerClass = "HUNTER" end

local function feederCount()
    local n = 0
    for _, f in ipairs(T.feeders) do
        if f.Name == "HunterSwing" then
            n = n + 1
            assertNotNil(f.Fill, "the demo fills")
            assertNotNil(f.Scrub, "the demo scrubs")
            assertNotNil(f.Live, "the demo counts")
        end
    end
    return n
end

--- The whole field face of the REAL tracker, stringed. The demo must leave
--- every bit of it exactly as it found it (the swap is the point: the demo
--- never feeds the real machine).
local function realFace()
    local t = Tools.Swing
    local parts = {}
    for _, k in ipairs({ "active", "start", "duration", "lastDuration",
        "aimLen", "shooting", "moving", "movePulseAt", "flying", "at",
        "cast", "pending", "retryUntil", "factsInRange", "rangeEdges",
        "lastShotTime", "feignPending", "base", "baseOverride" }) do
        parts[#parts + 1] = k .. "=" .. tostring(t[k])
    end
    return table.concat(parts, "|")
end

local function stopQuietly()
    if T.active then T:Stop("test") end
    if Swing.Tracker ~= Tools.Swing then Swing:SetTracker(Tools.Swing) end
    Swing:RenderIdle()
end

--- One demo drive: `beat` + the real render pass over [from, to], sampled.
--- The drive walks the DEMO'S OWN beat plan (`SwingDemo.beatPlan`) -- the
--- cycle stamps plus the aim-window centre and the cycle tail -- so every
--- window is sampled BY CONSTRUCTION: the demo's cycle phase rides the
--- drive's clock (the arming base modulo the cycle) and a fixed 0.2 s grid
--- can starve a phase at unlucky phases (the flake post-mortem; the plan
--- walk makes the drive deterministic in what it samples at ANY base).
--- The observations ride the bar's own draw state (the test_swing3 shape):
--- phase, fill intent, aim slice, interlock slice, clip marker (the safe
--- mode's band and the growing modes' stripe), flying shown.
local function drive(from, to)
    local obs = {}
    for _, b in ipairs(FX.Hunter.SwingDemo.beatPlan(from, to)) do
        Demo:Beat(b.t)
        Swing:Update(b.t)
        obs[#obs + 1] = string.format("%s|f%.2f|a%.2f|c%.2f|m%.2f",
            tostring(Swing._phase), Swing._fillIntent or -1,
            Swing._aimW or -1, Swing._castW or -1,
            math.max(Swing._clipW or 0, Swing._clipBandW or 0))
    end
    return obs
end

local function countPhase(obs, prefix)
    local n = 0
    for _, o in ipairs(obs) do
        if o:find("^" .. prefix) then n = n + 1 end
    end
    return n
end

-- ------------------------------------------------------------------ module --

test("the demo module registers the swing feeder exactly once", function()
    assertNotNil(Demo, "FX.Hunter.SwingDemo is loaded")
    assertNotNil(FX.modules["HunterSwingDemo"],
        "registered through FX.RegisterModule")
    enableAll()
    assertEquals(1, feederCount(), "one feeder, not two (idempotent enable)")
    assertEquals(false, T.active, "the enable does not start the demo")
    assertEquals(0, Demo:Live(), "and arms no demo")
    assertEquals(0, Demo:Scrub(), "a Scrub of an unarmed demo is a no-op")
end)

-- ------------------------------------------------------------ the slash pass --

test("the real slash path cycles the demo on the real bar, markers live",
function()
    enableAll()
    stopQuietly()
    asHunter()
    local faceBefore = realFace()
    FX.OnSlash("test")                        -- the real slash dispatch
    assertTrue(T.active, "the mode is on")
    assertEquals(1, Demo:Live(), "the demo bar is a live synthetic row")
    assertTrue(Swing.Tracker ~= Tools.Swing,
        "the bar rides the swapped demo tracker, not the real one")
    assertTrue(Swing.Tracker ~= nil and Swing.Tracker.active,
        "and the demo tracker runs a cycle")
    -- The drive window rides the Fill instant (the arming base): the plan's
    -- cycle 0 starts AT the Fill, the demo's cycle phase is aligned to the
    -- plan from the first beat (the stamp-plan law: cycle 0 of the plan IS
    -- the Fill's cycle, so every window carries its stamps at every phase).
    local base = GetTime() + 1e-6      -- the Fill cycle's stamps are the arming's
    local plan = FX.Hunter.SwingDemo.beatPlan(base, base + 14)
    local obs = drive(base, base + 14)
    assertTrue(#obs >= #plan - 2,
        "the plan was walked whole (" .. #obs .. " of " .. #plan .. ")")
    assertTrue(countPhase(obs, "reload") > 0, "the reload span shows")
    assertTrue(countPhase(obs, "aim") >= 3,
        "the non-interlock cycles carry the aim phase (the visibility law)")
    assertTrue(countPhase(obs, "flying") >= 3,
        "full cycles prove their shots' flights ("
        .. countPhase(obs, "flying") .. ")")
    -- The markers: the aim slice, the clip marker (the safe band / growing
    -- stripe), and the interlock slice on the every-third-cycle cast.
    local sawAim, sawClip, sawCast = false, false, false
    for _, o in ipairs(obs) do
        local phase, aim, cast, clip = o:match("^(%a+)|f([%-%d%.]+)|a"
            .. "([%-%d%.]+)|c([%-%d%.]+)|m([%-%d%.]+)")
        assertNotNil(phase, "observation shape: " .. tostring(o))
        if tonumber(aim) > 0 then sawAim = true end
        if tonumber(cast) > 0 then sawCast = true end
        if tonumber(clip) > 0 then sawClip = true end
    end
    assertTrue(sawAim, "the aim slice draws")
    assertTrue(sawClip, "the clip marker draws")
    assertTrue(sawCast, "the every-third-cycle Aimed Shot interlock draws")
    -- The real tracker was untouched by the whole ride.
    assertEquals(faceBefore, realFace(),
        "the real tracker's face is identical across the demo")
    -- The second press: OFF, real tracker back, bar idle.
    FX.OnSlash("test")
    assertEquals(false, T.active)
    assertEquals(0, Demo:Live(), "no demo row survives the stop")
    assertTrue(Swing.Tracker == Tools.Swing,
        "the real tracker is back on the bar")
    Swing:Update(10013)
    assertEquals(false, Swing._shown and true or false,
        "the bar returned to its idle state")
    assertEquals(faceBefore, realFace(),
        "and it is STILL untouched")
end)

test("a combat start restores the real tracker through the real event",
function()
    enableAll()
    stopQuietly()
    asHunter()
    local faceBefore = realFace()
    FX.OnSlash("test")
    assertTrue(T.active)
    assertEquals(1, Demo:Live())
    drive(10100, 10103)
    -- The real script, on the real frame (PLAYER_REGEN_DISABLED
    -- @UnitDocumentation.lua:3884 -- TestMode's own combat edge).
    T._eventFrame:GetScript("OnEvent")(T._eventFrame, "PLAYER_REGEN_DISABLED")
    assertEquals(false, T.active, "the mode is off")
    assertEquals("combat", T.reason)
    assertEquals(0, Demo:Live(), "the demo row is gone")
    assertTrue(Swing.Tracker == Tools.Swing,
        "the real tracker is restored on the combat scrub")
    assertEquals(faceBefore, realFace(), "the real tracker is untouched")
end)

test("a logout scrubs the demo through the real event", function()
    enableAll()
    stopQuietly()
    asHunter()
    FX.OnSlash("test")
    drive(10200, 10202)
    T._eventFrame:GetScript("OnEvent")(T._eventFrame, "PLAYER_LOGOUT")
    assertEquals(false, T.active)
    assertEquals(0, Demo:Live())
    assertTrue(Swing.Tracker == Tools.Swing, "the logout restored the bar")
    assertEquals(false, Swing._shown and true or false, "idle bar")
end)

-- ---------------------------------------------------------------- the gate --

test("a non-Hunter class shows no swing demo", function()
    enableAll()
    stopQuietly()
    FX._playerClass = "WARLOCK"
    local faceBefore = realFace()
    FX.OnSlash("test")
    assertTrue(T.active, "the mode runs for every class")
    assertEquals(0, Demo:Live(), "no swing demo row for a non-Hunter")
    assertTrue(Swing.Tracker == Tools.Swing, "the bar never left its tracker")
    local topped = T:Pump()                       -- the pump tops the OTHERS up
    assertNotNil(topped)
    assertEquals(0, Demo:Live(), "and the pump can not arm one either")
    FX.OnSlash("test")
    assertEquals(faceBefore, realFace(), "the real tracker never moved")
end)

test("the demo writes no settings", function()
    enableAll()
    stopQuietly()
    asHunter()
    local keys = {}
    for _, module in ipairs(FX.Settings:GetModuleNames()) do
        keys[#keys + 1] = tostring(FX.Settings:Get(module, "SwingDemo"))
    end
    FX.OnSlash("test")
    drive(10300, 10305)
    FX.OnSlash("test")
    for i, module in ipairs(FX.Settings:GetModuleNames()) do
        assertEquals(keys[i], tostring(FX.Settings:Get(module, "SwingDemo")),
            module .. " gained no SwingDemo key")
    end
    assertNil(Demo._ticker, "no beat ticker outlives the demo")
end)

test("the suite leaves the shipped state as it found it", function()
    stopQuietly()
    FX._playerClass = savedClass
    assertEquals(savedClass, FX._playerClass)
    assertEquals(false, T.active)
    assertEquals(0, Demo:Live())
    assertTrue(Swing.Tracker == Tools.Swing, "the real tracker rides on")
    assertNil(Demo._ticker, "no ticker is left running")
end)
