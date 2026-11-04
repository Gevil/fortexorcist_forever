-- addon/Forte_Hunter/tests/test_swing2.lua
-- wow-ui-sim tests for the Hunter swing v2 gap table
-- (docs/research/weaponswingtimer.md rows 1-10, agent HunterSwing2):
-- the two-phase cycle (aim length = 0.5 x duration/base, the floor clamp),
-- the shot cast-event machine incl. the FAILED_QUIET 0.5 s retry, the
-- event-proven white "projectile left" phase, the movement handling with
-- the sustained-pulse law, the Feign-Death movement reset, the
-- autorepeat shooting flag, the readiness gate, the Aimed/Multi cast
-- interlock (opens on SENT -- the Forever no-START law), the base-speed
-- seam, and the bar geometry per phase (safe-window fill, aim/retry/cast
-- slices, white fill, single-phase fallback).
--
-- Every tracker here is INJECTED (clock + gate readers): no real time, no
-- live target reads. The bar draws through its real Update path; the
-- event-machine tests drive the REAL OnEvent script on Tools._eventFrame
-- (the test_hunter.lua law -- a payload contract is only proven when the
-- frame script dispatches it), spelling the spells through ids the SIM
-- client resolves (probed below; the sim profile's ids are the client's,
-- never asserted equal to our generated data). Every behavioural test
-- fails on the pre-v2 code (Progress had no CycleState/CastRemaining;
-- the bar drew fraction x width unconditionally).

local FX = ForteXorcist
local Tools = FX.Hunter.Tools
local Swing = FX.Hunter.Swing
local S = FX.Hunter.SwingSkin
local ST = FX.Settings

local function nearpx(actual, expected)
    return assertTrue(math.abs(actual - expected) <= 0.5)
end

-- The file's bar tests read the DRAWN fill width (the v2 geometry law), so
-- the fill mode is pinned to the lua path here -- which is also Wave I-3's
-- default posture (UI/Swing.lua's Fill law: the engine-armed fill is built,
-- feature-detected, tested and selectable, and its default flip is a
-- launch-day probe). The engine path, its arms and the parity of the two
-- paths are tests/test_swing3.lua's subject.
Swing:SetFillEngineMode("lua")
assertFalse(Swing:UsesEngineFill())

--- Probe a client spell id by name (the sim resolves its own spell book
--- through C_Spell.GetSpellInfo -- the same seam the production event
--- frame runs). nil = this build has no such row: the tests that ride it
--- print and skip that leg.
local function probeID(englishName)
    for _, id in ipairs({ 75, 20904, 2643, 5384, 11305, 409593 }) do
        local name = Tools.ResolveCastName(id)
        local canon = name and Tools.CanonicalCastName(name)
        if canon == englishName then return id end
    end
    return nil
end
local AUTO_SHOT_ID = probeID("Auto Shot")
local AIMED_ID = probeID("Aimed Shot")
local FEIGN_ID = probeID("Feign Death")

-- A permissive-gate tracker: the cycle tests want the gate OPEN so the
-- inferred aim window fires; the gate itself has its own tests.
local function v2Tracker(clock, extra)
    local opts = {
        now = function() return clock[1] end,
        speedReader = function() return nil end,
        rangedType = 2,
        targetReader = function() return true end,
        deadReader = function() return false end,
        attackReader = function() return true end,
        speedSampler = function() return nil end,
        rangeReader = function() return nil end,
        castLenReader = function() return nil end,
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local t = FX.Hunter.NewSwingTracker(opts)
    t.shooting = true
    return t
end

-- ------------------------------------------------------------ tracker --

test("swing v2: the aim length is 0.5 x duration / base, floored at 0.5",
function()
    local clock = { 1000 }
    -- Base 2.0, cycle 3.0 (haste 1.5x): the aim window stretches with the
    -- cycle (the WST native_cycle_cast_time law, Hunter.lua:283-286).
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    t:OnSwingStart(3.0, 2)
    nearpx(t.aimLen, 0.75)
    -- No base knowledge: the 0.5 s floor (GetAutoCastTime's :139 floor).
    local u = v2Tracker(clock)
    u:OnSwingStart(3.0, 2)
    nearpx(u.aimLen, 0.5)
    -- The settings override re-pins the next cycle.
    u:SetBaseSpeed(1.5)
    u:OnSwingStart(3.0, 2)
    nearpx(u.aimLen, 1.0)
end)

test("swing v2: the base speed learns from a clean no-haste pair", function()
    local clock = { 1000 }
    local t = v2Tracker(clock, {
        speedReader = function() return 2.0 end,
    })
    -- cycle == speed: the clean pair -- the speed IS the base.
    t:OnSwingStart(2.0, 2)
    nearpx(t.base or 0, 2.0)
    -- A hasted pair (cycle 3.0 != speed 2.0) marks nothing.
    local u = v2Tracker(clock, { speedReader = function() return 2.0 end })
    u:OnSwingStart(3.0, 2)
    assertNil(u.base)
end)

test("swing v2: the cycle floors at the aim window -- the aim phase runs",
function()
    local clock = { 1000 }
    local t = v2Tracker(clock, { baseSpeed = 1.0 })
    t:OnSwingStart(2.0, 2)        -- aimLen 0.5
    local phase = t:CycleState(1000)
    assertEquals("reload", phase)
    phase = t:CycleState(1001.0)  -- remaining 1.0 > 0.5
    assertEquals("reload", phase)
    phase = t:CycleState(1001.6)  -- remaining 0.4 <= 0.5: the aim window
    assertEquals("aim", phase)
    -- The cycle is still alive at its end (the floor law: the countdown
    -- never counts below the aim window).
    phase = t:CycleState(1002.0)
    assertEquals("aim", phase)
    -- A fresh PLAYER_SWING re-arms (the cycle re-pins at every event).
    clock[1] = 1002.0
    t:OnSwingStart(2.0, 2)
    assertEquals("reload", t:CycleState(1002.0))
end)

test("swing v2: the inferred aim window is the readiness gate's servant",
function()
    local clock = { 1000 }
    local t = v2Tracker(clock)
    t:OnSwingStart(2.0, 2)
    -- Gate closed (not shooting): the floor never opens the aim phase.
    t.shooting = false
    assertEquals("reload", t:CycleState(1001.6))
    -- A live movement blocks it (the aim window is cancelled by movement).
    t.shooting = true
    t.moving = true
    assertEquals("reload", t:CycleState(1001.6))
    -- A dead target blocks it...
    t.moving = false
    local saved = t.deadReader
    t.deadReader = function() return true end
    assertEquals("reload", t:CycleState(1001.6))
    -- ...as does a non-attackable one, and a range-read false.
    t.deadReader = saved
    t.attackReader = function() return false end
    assertEquals("reload", t:CycleState(1001.6))
    t.attackReader = function() return true end
    t.rangeReader = function() return false end
    assertEquals("reload", t:CycleState(1001.6))
    -- Gate re-opened (the range knowledge learned true): the aim runs.
    t.rangeReader = function() return true end
    assertEquals("aim", t:CycleState(1001.6))
    -- A movement DROPS a live inferred aim mid-window (:361-366 law).
    t.moving = true
    assertEquals("reload", t:CycleState(1001.7))
end)

test("swing v2: the shot cast-event machine drives the aim phase", function()
    local clock = { 1000 }
    local t = v2Tracker(clock, { baseSpeed = 1.0 })
    t:OnSwingStart(2.0, 2)                          -- aimLen 0.5
    -- SENT is tentative (a FAILED_QUIET may follow): no aim opens.
    t:OnShotCast("SENT", "Auto Shot", 75, "G1")
    assertNotNil(t.pending)
    assertNil(t.at)
    -- START is authoritative: the aim phase opens (and the pendings go).
    t:OnShotCast("START", "Auto Shot", 75, "G1")
    assertNil(t.pending)
    assertNotNil(t.at)
    assertEquals(false, t.at.inferred)
    assertEquals(true, t.at.ev)
    -- The aim phase is the cycle's END window: outside the floor the
    -- reload keeps drawing; inside it, the aim slice runs.
    assertEquals("reload", t:CycleState(1000.5))
    assertEquals("aim", t:CycleState(1001.6))
    -- Movement does NOT drop an event-proven aim (its truth is the
    -- events; the server ends it via INTERRUPTED/FAILED_QUIET).
    t.moving = true
    assertEquals("aim", t:CycleState(1001.7))
    t.moving = false
    -- A live aim with a non-matching guid stays; the quiet failure of an
    -- extra rejected request pays its own 0.5 s penalty.
    clock[1] = 1001.7
    t:OnShotCast("FAILED_QUIET", "Auto Shot", 75, "G2")
    assertNotNil(t.at)
    nearpx(t.retryUntil, 1002.2)
    assertEquals("aim", t:CycleState(1001.7))
    -- INTERRUPTED for the live GUID ends the phase.
    t:OnShotCast("INTERRUPTED", "Auto Shot", 75, "G1")
    assertNil(t.at)
    -- The countdown is inside its floor: the inferred aim picks the
    -- window back up (the shot never left; the cycle runs on).
    assertEquals("aim", t:CycleState(1001.8))
    assertNotNil(t.at)
end)

test("swing v2: SUCCEEDED stamps the facts + the white flying phase",
function()
    local clock = { 1000 }
    local t = v2Tracker(clock)
    t:OnSwingStart(2.0, 2)
    t:OnShotCast("START", "Auto Shot", 75, "G1")
    t:OnShotCast("SUCCEEDED", "Auto Shot", 75, "G1")
    assertEquals("flying", t:CycleState(1000.5))
    assertEquals(true, t.factsInRange)      -- the :536-538 fact stamps
    assertNil(t.at)
    -- The flight rides on past the cycle end to the next PLAYER_SWING
    -- (Progress reports the completed cycle instead of going idle).
    local f, r = t:Progress(1002.5)
    assertNotNil(f)
    nearpx(f, 1); nearpx(r, 0)
    assertEquals("flying", t:CycleState(1002.5))
    -- The next swing ends it (the shot fired, the new cycle is not proven
    -- in flight).
    t:OnSwingStart(2.0, 2)
    assertEquals("reload", t:CycleState(1002.5))
    -- A flight that never sees the next swing self-clears (staleness):
    -- the expired cycle keeps reporting the full bar, never the white.
    local u = v2Tracker({ 2000 })
    u:OnSwingStart(2.0, 2)
    u.flying = 2001.9
    assertEquals("flying", u:CycleState(2001.95))
    assertEquals("reload", u:CycleState(2001.9 + 2.0 + 10.0 + 0.1))
    assertNil(u.flying)
end)

test("swing v2: FAILED_QUIET pays the 0.5 s retry and raises the floor",
function()
    local clock = { 1000 }
    local t = v2Tracker(clock)
    t:OnSwingStart(2.0, 2)               -- aimLen 0.5
    clock[1] = 1001.0                     -- at the cycle's aim edge
    t:OnShotCast("FAILED_QUIET", "Auto Shot", 75, "G9")
    nearpx(t.retryUntil, 1001.5)
    -- The floor is raised by the open retry (aim 0.5 + retry 0.5).
    local phase, aimLen, floor = t:CycleState(1001.0)
    assertEquals("aim", phase)
    nearpx(floor, 1.0)
    -- The floor decays with the retry...
    floor = ({ t:CycleState(1001.3) })[3]
    nearpx(floor, 0.7)
    -- ...and expires.
    t:CycleState(1001.6)
    local left = math.max(0, (t.retryUntil or 0) - 1001.6)
    nearpx(left, 0)
    -- A live aim with a DIFFERENT guid is left alone; every genuine
    -- failed start pays the 0.5 s retry (WST law: the indicator restarts
    -- at the quiet failure, the extra request is a real rejection).
    local u = v2Tracker({ 500 })
    u:OnSwingStart(2.0, 2)
    u:OnShotCast("START", "Auto Shot", 75, "GA")
    u:OnShotCast("FAILED_QUIET", "Auto Shot", 75, "GB")
    assertNotNil(u.at)
    nearpx(u.retryUntil, 500.5)
end)

test("swing v2: movement edges + the sustained-pulse law", function()
    local clock = { 1000 }
    local t = v2Tracker(clock)
    -- A live speed read rules continuously.
    local speed = 0
    t.speedSampler = function() return speed end
    t:OnPlayerStartedMoving(t)
    assertEquals(false, t:SampleMovement(1000.01))
    speed = 3
    assertEquals(true, t:SampleMovement(1000.02))
    speed = 0
    t:OnPlayerStoppedMoving(t)
    assertEquals(false, t.moving)
    -- The speed read goes secret: a short PLAYER_STARTED_MOVING pulse is
    -- NOT movement; a sustained one IS.
    t.speedSampler = function() return nil end
    t:OnPlayerStartedMoving(t)
    assertEquals(false, t:SampleMovement(1000.03))
    assertEquals(true, t:SampleMovement(1000.15))
    t:OnPlayerStoppedMoving(t)
    assertEquals(false, t:SampleMovement(1000.2))
end)

test("swing v2: Feign Death re-arms the cycle on the next movement",
function()
    local clock = { 1000 }
    local t = v2Tracker(clock)
    t:OnSwingStart(2.0, 2)
    t:OnShotCast("SUCCEEDED", "Feign Death", 5384, "GF")
    assertEquals(true, t.feignPending and true or false)
    -- No re-arm until movement.
    t:CycleState(1000.4)
    assertNotNil(t.feignPending)
    -- The movement edge fires the full re-arm (the jump-out leg rides the
    -- same movement in law; hooksecurefunc is undeclared, survey §B7).
    t:OnPlayerStartedMoving(t)
    assertNil(t.feignPending)
    nearpx(t.start, 1000)                    -- re-armed at Clock()
    local phase = t:CycleState(1000.1)
    assertEquals("reload", phase)
    nearpx(t.duration, 2.0)
    -- The +0.15 first-shot stretch is NOT ported (launch probe #7): the
    -- re-arm rides the plain last cycle length.
    -- Any other cast start cancels the pending re-arm (WST :488 law).
    local u = v2Tracker({ 3000 })
    u:OnSwingStart(2.0, 2)
    u:OnShotCast("SUCCEEDED", "Feign Death", 5384, "GF2")
    assertNotNil(u.feignPending)
    u:OnShotCast("START", "Aimed Shot", 20904, "GA1")
    assertNil(u.feignPending)
end)

test("swing v2: START/STOP_AUTOREPEAT_SPELL own the shooting flag",
function()
    local clock = { 1000 }
    local t = v2Tracker(clock)
    t.shooting = false
    t:OnSwingStart(2.0, 2)
    assertEquals("reload", t:CycleState(1001.7))   -- gate closed: no aim
    t:OnAutoRepeatStart()
    assertEquals(true, t.shooting)
    assertEquals("aim", t:CycleState(1001.7))      -- gate open: the aim
    t:OnAutoRepeatStop()
    assertEquals(false, t.shooting)
    assertEquals("reload", t:CycleState(1001.7))   -- gate closed again
    assertNil(t.at)
    -- STOP clears the aim phase / pendings / retry.
    t.shooting = true
    t:OnShotCast("START", "Auto Shot", 75, "G7")
    assertNotNil(t.at)
    t:OnAutoRepeatStop()
    assertNil(t.at)
    assertNil(t.pending)
    assertNil(t.retryUntil)
end)

test("swing v2: the Aimed/Multi interlock opens on SENT (no-START law)",
function()
    local clock = { 1000 }
    local t = v2Tracker(clock, {
        castLenReader = function() return 1.5 end,
    })
    t:OnSwingStart(3.0, 2)
    -- FOREVER law (the WST Castbar.lua:195-205 finding): Multi-Shot sends
    -- SENT then SUCCEEDED with NO START -- the interlock must be live
    -- from the SENT alone.
    t:OnShotCast("SENT", "Multi-Shot", 2643, "GM")
    local left = t:CastRemaining(1000.2)
    assertNotNil(left, "the interlock opened on SENT")
    -- A START for the same cast is idempotent (no double length).
    t:OnShotCast("START", "Multi-Shot", 2643, "GM")
    local _, len = t:CastRemaining(1000.3)
    nearpx(len, 1.5)
    -- SUCCEEDED ends it.
    t:OnShotCast("SUCCEEDED", "Multi-Shot", 2643, "GM")
    assertNil(t:CastRemaining(1001))
    -- The cast length precedence: live reader > ResolveCastLength(id) >
    -- data castMs.
    local u = v2Tracker({ 4000 }, {
        castLenReader = function() return 1.5 end,
    })
    u:OnShotCast("SENT", "Aimed Shot", 20904, "GX")
    local _, len2 = u:CastRemaining(4000.1)
    nearpx(len2, 1.5)
    -- The data fallback (no live read, no id).
    local v = v2Tracker({ 4000 })
    v:OnShotCast("SENT", "Aimed Shot", nil, "GY")
    local _, len3 = v:CastRemaining(4000.1)
    nearpx(len3, 2.0)
    -- A live UnitCastingInfo window beats the data (the pushback shape:
    -- RefreshCastLength re-anchors from the live read).
    local w = v2Tracker({ 5000 }, {
        castLenReader = function() return 2.0 end,
    })
    w:OnShotCast("SENT", "Aimed Shot", nil, "GZ")
    local _, l0 = w:CastRemaining(5000.1)
    nearpx(l0, 2.0)
    w.castLenReader = function() return 1.2 end
    w:RefreshCastLength(nil)
    local _, l1 = w:CastRemaining(5000.3)
    nearpx(l1, 1.2)
    -- Non-cycle spells never open the interlock.
    local x = v2Tracker({ 6000 })
    x:OnShotCast("SENT", "Kill Shot", 409593, "GK")
    assertNil(x:CastRemaining(6000.1))
end)

test("swing v2: ResolveCastLength converts ms; NetLatency is guarded",
function()
    assertNil(Tools.ResolveCastLength(nil))
    assertNil(Tools.ResolveCastLength(987654321))
    -- The sim client resolves its own Aimed Shot row: ms -> seconds.
    local v = AIMED_ID and Tools.ResolveCastLength(AIMED_ID) or nil
    if v ~= nil then nearpx(v, 2.0)
    else print("[swing2] sim resolves no Aimed Shot row -- ms leg skipped")
    end
    -- The index of data cast times is data-keyed and id-less.
    local idx = Tools.DataCastMsByName()
    nearpx(idx["Aimed Shot"] / 1000, 2.0)
    assertNil(idx["Kill Shot"])
    -- NetLatency: guarded, numeric-or-nil, never a raise (the 4th-return
    -- probe leg -- Gap-12; no timing math rides it).
    local ok, r = pcall(Tools.NetLatency)
    assertTrue(ok)
    assertTrue(r == nil or type(r) == "number")
end)

-- ------------------------------------------------------------- bar draw --

test("swing v2 bar: the safe-window fill shrinks toward the aim slice",
function()
    local clock = { 3000 }
    local t = v2Tracker(clock, { baseSpeed = 1.0 })
    Swing:SetTracker(t)
    Swing:SetShowSafeWindow(true)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)                        -- aimLen 0.5
    Swing:Update(clock[1])
    -- full safe window: (2.0 - 0.5)/2.0 * 200 = 150
    nearpx(Swing.fill:GetWidth(), 150)
    local fr = Swing.fill:GetVertexColor()
    nearpx(fr, S.BarColor[1])
    clock[1] = 3001.0
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 50)             -- (1.0-0.5)/2*200
    clock[1] = 3001.6
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 0)              -- inside the aim window
    assertTrue(Swing.aim:IsShown())
    nearpx(Swing.aim:GetWidth(), 0.5 * (200 / 2.0))   -- aimLen x scale
    local r, g, b = Swing.aim:GetVertexColor()
    nearpx(r - g, 1)                                  -- Debuff red
    nearpx(r - b, 1)
    Swing:RenderIdle()
    assertFalse(Swing.aim:IsShown())
end)

test("swing v2 bar: the aim slice tracks readiness -- gate-closed hidden",
function()
    local clock = { 3100 }
    local t = v2Tracker(clock, {
        baseSpeed = 1.0,
        attackReader = function() return false end,
    })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    clock[1] = 3101.6
    assertTrue(Swing:Update(clock[1]))
    assertFalse(Swing.aim:IsShown())              -- phase reload: no slice
    -- The event-proven aim draws through the floor, gate-closed and all.
    t:OnShotCast("START", "Auto Shot", 75, "GS")
    Swing:Update(clock[1])
    assertTrue(Swing.aim:IsShown())
    Swing:RenderIdle()
end)

test("swing v2 bar: the white projectile-left state + the spark pulse",
function()
    local clock = { 3200 }
    local t = v2Tracker(clock, { baseSpeed = 1.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    clock[1] = 3201.0
    Swing:Update(clock[1])
    local r = Swing.fill:GetVertexColor()
    nearpx(r, S.BarColor[1])                       -- the Spell tint
    t:OnShotCast("SUCCEEDED", "Auto Shot", 75, "GW")
    Swing:Update(clock[1])
    r = Swing.fill:GetVertexColor()
    nearpx(r, 1)
    local fg = select(2, Swing.fill:GetVertexColor())
    nearpx(fg, 1)                                  -- Buff white
    -- The Spark2 pulse: alpha > 0 at the shot moment, linear to 0 in 1 s.
    local a = select(4, Swing.spark:GetVertexColor())
    assertTrue(a > 0.9)
    clock[1] = 3201.5
    Swing:Update(clock[1])
    a = select(4, Swing.spark:GetVertexColor())
    nearpx(a, 0.5)
    clock[1] = 3202.05
    Swing:Update(clock[1])
    a = select(4, Swing.spark:GetVertexColor())
    nearpx(a, 0)
    -- ShowFlying off keeps the tint.
    Swing:SetShowFlying(false)
    Swing:Update(3201.0)
    r = Swing.fill:GetVertexColor()
    nearpx(r, S.BarColor[1])
    Swing:SetShowFlying(true)
    Swing:RenderIdle()
    Swing:SetTracker(FX.Hunter.Tools.Swing)
end)

test("swing v2 bar: the retry slice counts down left of the aim slice",
function()
    local clock = { 3300 }
    local t = v2Tracker(clock, { baseSpeed = 1.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    clock[1] = 3301.0                              -- at the aim edge
    t:OnShotCast("FAILED_QUIET", "Auto Shot", 75, "GR")
    Swing:Update(3301.2)
    assertTrue(Swing.retry:IsShown())
    nearpx(Swing.retry:GetWidth(), 0.3 * (200 / 2.0))
    local r, g = Swing.retry:GetVertexColor()
    nearpx(r, 1); nearpx(g, 1)                             -- Item yellow
    Swing:Update(3301.4)
    nearpx(Swing.retry:GetWidth(), 0.1 * (200 / 2.0))
    Swing:Update(3301.6)                                     -- expired
    assertFalse(Swing.retry:IsShown())
    Swing:RenderIdle()
end)

test("swing v2 bar: the cast interlock freezes the fill, red slice, cast text",
function()
    local clock = { 3400 }
    local t = v2Tracker(clock, { baseSpeed = 1.0,
        castLenReader = function() return 1.5 end })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    clock[1] = 3401.0
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 50)           -- (1.0-0.5)/2*200
    t:OnShotCast("SENT", "Aimed Shot", 20904, "GA")
    Swing:Update(clock[1])
    assertTrue(Swing.cast:IsShown())
    nearpx(Swing.cast:GetWidth(), 200)             -- the full-width slice
    local w0 = Swing.fill:GetWidth()
    -- F1 (code-review-8): the freeze is THIS mode's fill law read at the
    -- press instant (3401.0: remaining 1.0, floor 0.5, duration 2.0 => 50
    -- px) — the fill exactly where it stood when the cast opened, the
    -- same number the live safe law drew one line above. The v2 law drew
    -- the cycle's REMAINING fraction x W = 100 (the shrinking bar's
    -- measure drawn raw).
    nearpx(w0, 50)
    clock[1] = 3401.4                              -- 1.1 s of cast left
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), w0)              -- frozen at the edge
    assertEquals("1.1", Swing.text:GetText())
    t:OnShotCast("SUCCEEDED", "Aimed Shot", 20904, "GA")
    Swing:Update(clock[1])
    assertFalse(Swing.cast:IsShown())
    Swing:RenderIdle()
end)

test("swing v2 bar: ShowSafeWindow off is the single-phase law", function()
    local clock = { 3500 }
    local t = v2Tracker(clock, { baseSpeed = 1.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    Swing:SetShowSafeWindow(false)
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 0)              -- the pre-v2 law
    clock[1] = 3501.6                              -- inside the aim window
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 160)
    assertFalse(Swing.aim:IsShown())
    Swing:SetShowSafeWindow(true)
    Swing:RenderIdle()
end)

test("swing v2 bar: the combat alpha pair rides InCombatLockdown", function()
    Swing:Init()
    local savedUC = _G.InCombatLockdown
    _G.InCombatLockdown = function() return true end
    Swing._combatAlpha = nil
    Swing:_ApplyCombatAlpha()
    nearpx(Swing.anchor:GetAlpha(), S.InCombatAlpha)
    _G.InCombatLockdown = function() return false end
    Swing._combatAlpha = nil
    Swing:_ApplyCombatAlpha()
    nearpx(Swing.anchor:GetAlpha(), S.OutOfCombatAlpha)
    _G.InCombatLockdown = savedUC
    ST:Set("Hunter", "InCombatAlpha", 0.5)
    nearpx(S.InCombatAlpha, 0.5)
    ST:Set("Hunter", "OutOfCombatAlpha", 0.25)
    nearpx(S.OutOfCombatAlpha, 0.25)
    ST:Reset("Hunter", "InCombatAlpha")
    ST:Reset("Hunter", "OutOfCombatAlpha")
    nearpx(S.InCombatAlpha, 1.0); nearpx(S.OutOfCombatAlpha, 1.0)
    Swing._combatAlpha = nil
    Swing:_ApplyCombatAlpha()
end)

test("swing v2 settings: the new keys drive the bar + tracker live",
function()
    assertNotNil(ST)
    assertTrue(ST:IsRegistered("Hunter"))
    ST:Set("Hunter", "ShowAimSlice", false)
    assertEquals(false, FX.Hunter.Swing.state.showAimSlice)
    ST:Set("Hunter", "ShowAimSlice", true)
    ST:Set("Hunter", "ShowFlying", false)
    assertEquals(false, FX.Hunter.Swing.state.showFlying)
    ST:Set("Hunter", "ShowFlying", true)
    ST:Set("Hunter", "ShowRetry", false)
    assertEquals(false, FX.Hunter.Swing.state.showRetry)
    ST:Set("Hunter", "ShowRetry", true)
    ST:Set("Hunter", "ShowSafeWindow", false)
    assertEquals(false, FX.Hunter.Swing.state.showSafeWindow)
    ST:Set("Hunter", "ShowSafeWindow", true)
    ST:Set("Hunter", "ShowLatency", true)
    assertEquals(true, FX.Hunter.Swing.state.showLatency)
    ST:Set("Hunter", "ShowLatency", false)
    -- The BaseSpeed key reaches the production tracker seam (the bar
    -- drives the production tracker for this leg — earlier tests inject
    -- stand-ins).
    local prod = Tools.Swing
    local Swing2 = FX.Hunter.Swing
    local savedTracker = Swing2.Tracker
    Swing2:SetTracker(prod)
    ST:Set("Hunter", "BaseSpeed", 2.5)
    nearpx(prod.baseOverride, 2.5)
    ST:Set("Hunter", "BaseSpeed", 0)
    assertNil(prod.baseOverride)
    Swing2:SetTracker(savedTracker)
    Swing2:RenderIdle()
end)

-- ------------------------------------------------------- event plumbing --

test("swing v2: the REAL Tools OnEvent script drives the shot machine",
function()
    if not AUTO_SHOT_ID then
        print("[swing2] the sim resolves no Auto Shot row -- skipped")
        return
    end
    local wasEnabled = Tools._eventsEnabled and true or false
    local savedSwing = Tools.Swing
    local clock = { 7000 }
    local sw = v2Tracker(clock, { rangedType = savedSwing.rangedType })
    sw:OnSwingStart(2.0, sw.rangedType)
    Tools.Swing = sw
    Tools:EnableEvents()
    local f = Tools._eventFrame
    local script = f:GetScript("OnEvent")
    assertNotNil(script)
    -- (unitTarget, castGUID, spellID) -- the frame must route the START
    -- payload onto the machine.
    script(f, "UNIT_SPELLCAST_START", "player", "EG", AUTO_SHOT_ID)
    assertNotNil(sw.at, "UNIT_SPELLCAST_START through the frame script "
        .. "must open the aim phase")
    script(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "EG", AUTO_SHOT_ID)
    assertEquals("flying", sw:CycleState(7000.5))
    script(f, "UNIT_SPELLCAST_FAILED_QUIET", "player", "EH", AUTO_SHOT_ID)
    assertNotNil(sw.retryUntil)
    -- Movement + autorepeat edges through the same script.
    sw:OnSwingStart(2.0, sw.rangedType)
    script(f, "PLAYER_STARTED_MOVING")
    assertNotNil(sw.movePulseAt)
    script(f, "PLAYER_STOPPED_MOVING")
    assertNil(sw.movePulseAt)
    script(f, "START_AUTOREPEAT_SPELL")
    assertEquals(true, sw.shooting)
    script(f, "STOP_AUTOREPEAT_SPELL")
    assertEquals(false, sw.shooting)
    -- TARGET_CHANGED clears the target facts + the aim/pendings.
    sw.factsInRange = true
    sw:OnShotCast("START", "Auto Shot", AUTO_SHOT_ID, "EI")
    assertNotNil(sw.at)
    script(f, "PLAYER_TARGET_CHANGED")
    assertNil(sw.at)
    assertNil(sw.factsInRange)
    -- ENTERING_WORLD clears the flight/retry/cast state.
    sw.flying = 7000
    sw.retryUntil = 7001
    script(f, "PLAYER_ENTERING_WORLD")
    assertNil(sw.flying)
    assertNil(sw.retryUntil)
    Tools.Swing = savedSwing
    if not wasEnabled then Tools:DisableEvents() Tools._eventFrame = nil end
end)

test("swing v2: the interlock opens on SENT through the REAL event script",
function()
    if not AIMED_ID then
        print("[swing2] the sim resolves no Aimed Shot row -- skipped")
        return
    end
    local wasEnabled = Tools._eventsEnabled and true or false
    local savedSwing = Tools.Swing
    local clock = { 8000 }
    local sw = v2Tracker(clock, { rangedType = savedSwing.rangedType,
        castLenReader = function() return 2.0 end })
    sw:OnSwingStart(3.0, sw.rangedType)
    Tools.Swing = sw
    Tools:EnableEvents()
    local script = Tools._eventFrame:GetScript("OnEvent")
    script(Tools._eventFrame, "UNIT_SPELLCAST_SENT",
        "player", "Target of Training", "ES", AIMED_ID)
    assertNotNil(sw:CastRemaining(8000.1),
        "UNIT_SPELLCAST_SENT through the frame script must open the "
        .. "Aimed Shot interlock (the Forever no-START law)")
    script(Tools._eventFrame, "UNIT_SPELLCAST_SUCCEEDED",
        "player", "ES", AIMED_ID)
    assertNil(sw:CastRemaining(8000.2))
    Tools.Swing = savedSwing
    if not wasEnabled then Tools:DisableEvents() Tools._eventFrame = nil end
end)

test("swing v2: the REAL event script routes the catalog payload shapes",
function()
    -- CAT (UnitDocumentation.lua): UNIT_SPELLCAST_SENT(unitTarget, target,
    -- castGUID, spellID) -- FOUR payload slots, the target string in slot
    -- two (ConditionalSecret: it rides through UNREAD). The rest are
    -- (unitTarget, castGUID, spellID[, castBarID]). The live-review law:
    -- tests ride the EXACT client payload shapes, never the machine's
    -- internal calling convention.
    if not (AUTO_SHOT_ID and AIMED_ID) then
        print("[swing2] the sim resolves no probe rows -- skipped")
        return
    end
    local wasEnabled = Tools._eventsEnabled and true or false
    local savedSwing = Tools.Swing
    local clock = { 13000 }
    local sw = v2Tracker(clock, { rangedType = savedSwing.rangedType,
        castLenReader = function() return 2.0 end })
    sw:OnSwingStart(3.0, sw.rangedType)
    Tools.Swing = sw
    Tools:EnableEvents()
    local f = Tools._eventFrame
    local script = f:GetScript("OnEvent")
    assertNotNil(script)
    -- The four-slot SENT opens the Aimed Shot interlock.
    script(f, "UNIT_SPELLCAST_SENT",
        "player", "Target of Training", "GA", AIMED_ID)
    assertNotNil(sw:CastRemaining(13000.1),
        "the four-slot SENT payload must open the Aimed Shot interlock")
    script(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "GA", AIMED_ID)
    assertNil(sw:CastRemaining(13000.2))
    -- Auto Shot: the four-slot SENT pends, the three-slot START opens the
    -- aim window (Main's live proof: pending AND at were nil pre-fix).
    script(f, "UNIT_SPELLCAST_SENT",
        "player", "Target of Training", "GB", AUTO_SHOT_ID)
    assertNotNil(sw.pending,
        "the four-slot SENT payload must pend the Auto Shot attempt")
    script(f, "UNIT_SPELLCAST_START", "player", "GB", AUTO_SHOT_ID)
    assertNil(sw.pending)
    assertNotNil(sw.at, "UNIT_SPELLCAST_START must open the aim window")
    assertEquals(true, sw.at.ev)
    -- The three-slot FAILED_QUIET pays the 0.5 s retry.
    clock[1] = 13001.0
    script(f, "UNIT_SPELLCAST_FAILED_QUIET", "player", "GC", AUTO_SHOT_ID)
    assertNotNil(sw.retryUntil)
    -- The three-slot INTERRUPTED ends the window for the live guid.
    script(f, "UNIT_SPELLCAST_START", "player", "GD", AUTO_SHOT_ID)
    assertNotNil(sw.at)
    script(f, "UNIT_SPELLCAST_INTERRUPTED", "player", "GD", AUTO_SHOT_ID)
    assertNil(sw.at)
    Tools.Swing = savedSwing
    if not wasEnabled then Tools:DisableEvents() Tools._eventFrame = nil end
end)

test("swing v2: the Feign SUCCEEDED arms through the REAL event script",
function()
    if not FEIGN_ID then
        print("[swing2] the sim resolves no Feign Death row -- skipped")
        return
    end
    local wasEnabled = Tools._eventsEnabled and true or false
    local savedSwing = Tools.Swing
    local clock = { 9000 }
    local sw = v2Tracker(clock, { rangedType = savedSwing.rangedType })
    sw:OnSwingStart(2.0, sw.rangedType)
    Tools.Swing = sw
    Tools:EnableEvents()
    local script = Tools._eventFrame:GetScript("OnEvent")
    script(Tools._eventFrame, "UNIT_SPELLCAST_SUCCEEDED",
        "player", "EF", FEIGN_ID)
    assertNotNil(sw.feignPending, "Feign SUCCEEDED through the frame "
        .. "script must arm the movement reset")
    script(Tools._eventFrame, "PLAYER_STARTED_MOVING")
    assertNil(sw.feignPending)
    nearpx(sw.start, 9000)
    Tools.Swing = savedSwing
    if not wasEnabled then Tools:DisableEvents() Tools._eventFrame = nil end
end)

test("swing v2: the UI event script kicks the bar on movement/target",
function()
    local U = FX.Hunter.UI
    local wasEnabled = U._eventsEnabled and true or false
    U:EnableEvents()
    local f = U._eventFrame
    local script = f:GetScript("OnEvent")
    local savedKick, kicks = FX.Hunter.Swing.Kick, 0
    FX.Hunter.Swing.Kick = function(...) kicks = kicks + 1 end
    script(f, "PLAYER_STARTED_MOVING")
    script(f, "PLAYER_STOPPED_MOVING")
    script(f, "PLAYER_TARGET_CHANGED")
    FX.Hunter.Swing.Kick = savedKick
    assertTrue(kicks >= 3, "movement/target edges through the UI frame "
        .. "script must kick the bar")
    if not wasEnabled then U:DisableEvents() U._eventFrame = nil end
end)

test("swing v2: the out-of-combat alpha pair defaults VISIBLE",
function()
    -- A pre-pull Aimed Shot must be on screen: the bar already hides
    -- when idle, so the out-of-combat default parks it visible, not
    -- transparent (the live-review law).
    assertEquals(1.0, FX.Hunter.SwingSkin.OutOfCombatAlpha)
    assertEquals(1.0, ST:GetDefault("Hunter", "OutOfCombatAlpha"))
    assertEquals(1.0, FX.Hunter.SwingSkin.InCombatAlpha)
    assertEquals(1.0, ST:GetDefault("Hunter", "InCombatAlpha"))
end)

test("swing v2 live: the manager drive -- aim slice without a target and"
    .. " the full-width white flight",
function()
    if not AUTO_SHOT_ID then
        print("[swing2] the sim resolves no Auto Shot row -- skipped")
        return
    end
    local Swing = FX.Hunter.Swing
    Swing:Init()
    local savedSwing, savedTracker = Tools.Swing, Swing.Tracker
    local wasTools = Tools._eventsEnabled and true or false
    local U = FX.Hunter.UI
    local wasUI = U._eventsEnabled and true or false
    local clock = { 12000 }
    local sw = v2Tracker(clock, { rangedType = 2 })
    -- The live drive has NO target: the readiness gate is closed.
    sw.targetReader = function() return false end
    Tools.Swing = sw
    Swing:SetTracker(sw)
    Tools:EnableEvents()
    U:EnableEvents()
    local tf, uf = Tools._eventFrame, U._eventFrame
    local ts, us = tf:GetScript("OnEvent"), uf:GetScript("OnEvent")
    assertNotNil(ts)
    assertNotNil(us)
    -- Main's drive, as the client dispatches: autorepeat on, swing armed,
    -- the shot machine, SUCCEEDED, the next swing re-arms.
    ts(tf, "START_AUTOREPEAT_SPELL")
    ts(tf, "PLAYER_SWING", 3.0, 2)
    us(uf, "PLAYER_SWING", 3.0, 2)
    clock[1] = 12002.35
    ts(tf, "UNIT_SPELLCAST_SENT", "player", "Target of Training", "G1",
        AUTO_SHOT_ID)
    ts(tf, "UNIT_SPELLCAST_START", "player", "G1", AUTO_SHOT_ID)
    clock[1] = 12002.6                          -- remaining 0.4 <= floor
    local phase = sw:CycleState(clock[1])
    assertEquals("aim", phase)
    assertEquals(false, sw:CanAim(clock[1]))    -- the gate IS closed
    Swing:Update(clock[1])
    assertTrue(Swing.aim:IsShown() and Swing.aim:GetWidth() > 0,
        "the aim window is INFORMATION: the readiness gate must not hide "
        .. "the slice (the live drive rendered an empty bar)")
    -- The white flight: the WHOLE bar turns white from SUCCEEDED.
    clock[1] = 12003.0
    ts(tf, "UNIT_SPELLCAST_SUCCEEDED", "player", "G1", AUTO_SHOT_ID)
    assertEquals("flying", sw:CycleState(clock[1]))
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 200)
    local r = Swing.fill:GetVertexColor()
    nearpx(r, 1)
    -- A shot confirmed BEFORE the cycle's end (the fire->swing latency
    -- window): the flight is the FULL bar, the fraction be damned.
    sw:OnSwingStart(3.0, 2)
    clock[1] = 12004.0
    ts(tf, "UNIT_SPELLCAST_START", "player", "G2", AUTO_SHOT_ID)
    ts(tf, "UNIT_SPELLCAST_SUCCEEDED", "player", "G2", AUTO_SHOT_ID)
    assertEquals("flying", sw:CycleState(clock[1]))
    Swing:Update(clock[1])
    nearpx(Swing.fill:GetWidth(), 200)
    -- The re-arm ends the flight state (no white strip rides the next
    -- cycle).
    clock[1] = 12004.25
    ts(tf, "PLAYER_SWING", 3.0, 2)
    us(uf, "PLAYER_SWING", 3.0, 2)
    clock[1] = 12003.5
    Swing:Update(clock[1])
    assertNil(sw.flying)
    local r2 = Swing.fill:GetVertexColor()
    assertTrue(r2 < 0.99, "the flying tint must end at the re-arm")
    -- restore
    Swing:RenderIdle()
    Tools.Swing, Swing.Tracker = savedSwing, savedTracker
    if not wasTools then Tools:DisableEvents(); Tools._eventFrame = nil end
    if not wasUI then U:DisableEvents(); U._eventFrame = nil end
end)

-- ------------------------------------------------------------ range light --

test("range light: the band ladder (fake readers, full decision table)",
function()
    local flags = {
        target = true, dead = false, attack = true, melee = false,
        scatter = false, ranged = true, close = false, mark = true,
    }
    local meter = FX.Hunter.NewRangeMeter({
        targetReader = function() return flags.target end,
        deadReader = function() return flags.dead end,
        attackReader = function() return flags.attack end,
        meleeReader = function() return flags.melee end,
        scatterReader = function() return flags.scatter end,
        rangedReader = function() return flags.ranged end,
        closeReader = function() return flags.close end,
        markReader = function() return flags.mark end,
    })
    local band, text = meter:GetBand()
    assertEquals("ranged", band)
    assertEquals("8-35", text)
    flags.scatter = true
    assertEquals("close", meter:GetBand())          -- the 8-15 rung
    flags.ranged = false
    assertEquals("deadzone", meter:GetBand())       -- 5-8 with Scatter in
    assertEquals("DEAD 5-8", ({ meter:GetBand() })[2])
    flags.scatter = false
    flags.close = true
    assertEquals("deadzone", meter:GetBand())       -- too-close split
    flags.close = false
    flags.mark = true
    assertEquals("far", meter:GetBand())            -- 35..100
    flags.mark = false
    assertEquals("out", meter:GetBand())            -- 100+
    flags.melee = true
    assertEquals("melee", meter:GetBand())          -- Wing Clip rules first
    flags.melee = false
    flags.ranged = nil                              -- no knowledge
    flags.scatter = true
    assertEquals("close", meter:GetBand())          -- the nil fallback
    flags.scatter = false
    flags.mark = true
    assertEquals("far", meter:GetBand())
    flags.mark = nil
    assertNil(meter:GetBand())
    flags.target = false
    assertNil(meter:GetBand())                      -- no target
    flags.target = true
    flags.dead = true
    assertNil(meter:GetBand())                      -- a dead target
    flags.dead = false
    flags.attack = false
    assertNil(meter:GetBand())                      -- unattackable
    -- A RAISING reader is "no knowledge", never a crash.
    flags.attack = true
    local boom = FX.Hunter.NewRangeMeter({
        targetReader = function() error("restricted", 0) end,
    })
    local ok = pcall(boom.GetBand, boom)
    assertTrue(ok)
    assertNil(select(1, boom:GetBand()))
end)

test("range light: the UI frame shows/hides through the meter seam",
function()
    local RL = FX.Hunter.RangeLight
    assertNotNil(RL)
    RL:Init()
    assertNotNil(RL.anchor)
    local saved = RL.Meter
    RL:SetMeter(FX.Hunter.NewRangeMeter({
        targetReader = function() return true end,
        attackReader = function() return true end,
        rangedReader = function() return true end,
    }))
    RL:SetEnabled(true)
    assertTrue(RL.anchor:IsShown())
    assertEquals("ranged", RL._band)
    assertEquals("8-35", RL.text:GetText())
    local c = RL.BandColor("ranged")
    nearpx(c[1], 0); nearpx(c[2], 1)                -- Potion green
    RL:SetMeter(FX.Hunter.NewRangeMeter({
        targetReader = function() return false end,
    }))
    RL:Refresh()
    assertFalse(RL.anchor:IsShown())
    RL:SetEnabled(false)
    assertNil(RL.anchor:GetScript("OnUpdate"))
    RL:SetMeter(saved)
    -- The live key rides the store (the meter with no knowledge keeps the
    -- strip hidden -- no fake show).
    local liveMeter = RL.Meter
    RL:SetMeter(FX.Hunter.NewRangeMeter({
        targetReader = function() return true end,
        attackReader = function() return true end,
        rangedReader = function() return true end,
    }))
    ST:Set("Hunter", "ShowRangeLight", true)
    assertTrue(RL.state.enabled)
    assertTrue(RL.anchor:IsShown())
    ST:Set("Hunter", "ShowRangeLight", false)
    assertFalse(RL.state.enabled)
    assertFalse(RL.anchor:IsShown())
    RL:SetMeter(liveMeter)
end)

test("range light: the default meter is guarded on every API leg",
function()
    -- The production meter runs against the sim's emulated client with no
    -- target: a full GetBand must not raise and must answer nil.
    local meter = FX.Hunter.RangeMeter
    assertNotNil(meter)
    local ok, band = pcall(meter.GetBand, meter)
    assertTrue(ok)
    assertNil(band)
end)
