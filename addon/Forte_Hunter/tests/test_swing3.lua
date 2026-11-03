-- addon/Forte_Hunter/tests/test_swing3.lua
-- Wave I-3 slice I3a (docs/research/upstream-addons-2026-11-03.md §3 +
-- ranked 2) tests, on the shipped swing-timer law re-derived from the
-- declared APIs:
--
--   * the ENGINE-DRIVEN FILL: where StatusBar:SetTimerDuration +
--     C_DurationUtil.CreateDuration + the two Status-bar enums exist, the
--     reload/aim fill can be armed at the cycle's state edges and animated
--     by the client -- no Lua fill maths per frame; the v2 10 Hz SetSize
--     law is the second path and the shipped DEFAULT (UI/Swing.lua's
--     DEFAULT POSTURE: this simulator accepts the arm, its duration object
--     counts down, and its widget never consumes it -- the gate test
--     measures that and says which fact would flip the default).
--     Feature-detected once, both paths tested: the arm-edge test proves
--     the edge-only arming, the PARITY test runs one auto-shot cycle
--     through the real Update path on both paths and requires the same
--     observed state sequence, and the degrade test proves a raising widget
--     falls back to the law (one way).
--   * PLAYER_SWING_RANGE_UPDATE's THREE returns with the nil-is-not
--     out-of-range law, driven through the REAL Tools frame script, and
--     C_SwingTimer.IsTargetWithinSwingRange as the feature-detected second
--     range signal (nil in this simulator -- measured, asserted).
--   * the single C_SwingTimer.EnableRangeCheck opt-in owner (the union of
--     the swing tracker's and the range light's requests).
--   * the PER-SLOT UnitAttackSpeed read, with the 0.5 s aim window kept.
--
-- Every tracker here is INJECTED (clock + gate readers) as in
-- test_swing2.lua; the bar draws through its real Update path; the API
-- fakes are installed and restored around each leg.

local FX = ForteXorcist
local Tools = FX.Hunter.Tools
local Swing = FX.Hunter.Swing

local function nearpx(actual, expected)
    return assertTrue(math.abs(actual - expected) <= 0.5)
end

--- A permissive-gate tracker (test_swing2.lua's shape): the cycle tests
--- want the gate OPEN so the aim window runs.
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

local function restoreBar()
    Swing:SetFillEngineMode("lua")      -- the module's default posture
    Swing:SetTracker(Tools.Swing)
    Swing:RenderIdle()
    Swing:FillLog(nil)
end

-- ================================================= the engine-driven fill ==

test("fill I3a: the gate, the default posture, and the seam over both paths",
function()
    Swing:Init()
    -- The capability legs of the gate, measured on this simulator.
    assertNotNil(_G.C_DurationUtil)
    assertNotNil(_G.C_DurationUtil.CreateDuration)
    assertNotNil(_G.Enum.StatusBarTimerDirection)
    assertNotNil(_G.Enum.StatusBarInterpolation)
    assertNil(_G.C_SwingTimer)          -- the range surface: absent HERE
    local function isWidget()
        local f = Swing.fill
        local ok, name = pcall(function() return f.GetName and f:GetName() end)
        return (ok and name == "ForteXorcistHunterSwingFill") and 1 or 0
    end
    -- The shipped default: the v2 law, on a client that HAS the API.
    assertTrue(Swing._fillMode == "lua" or Swing._fillMode == nil)
    Swing:SetFillEngineMode("auto")
    assertTrue(Swing:UsesEngineFill())
    assertEquals(1, isWidget())         -- the named StatusBar the gate builds
    Swing:SetFillEngineMode("lua")
    assertFalse(Swing:UsesEngineFill())
    assertEquals(0, isWidget())         -- the v2 Aluminium texture
    Swing:SetFillEngineMode("engine")
    assertTrue(Swing:UsesEngineFill())
    assertEquals(1, isWidget())
    -- Why the default is not "auto" here (the measured reason behind
    -- UI/Swing.lua's DEFAULT POSTURE): this simulator accepts the arm and
    -- its duration object counts down on its own, but the WIDGET never
    -- consumes it -- after a span arm its value sits at its min, so an
    -- engine-armed fill renders empty in the harness the v2 bar was
    -- frame-by-frame verified in. The client's half is launch-day probe 5.
    local clock = { 6500 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    local v = Swing.fill.GetValue and Swing.fill:GetValue()
    local _, min = Swing.fill:GetMinMaxValues()
    assertTrue(v ~= nil and min ~= nil and v <= min + 1e-6,
        "the harness measured a widget that consumes the duration: v="
        .. tostring(v) .. " min=" .. tostring(min)
        .. " -- then the default posture line in UI/Swing.lua can flip")
    Swing:RenderIdle()
    restoreBar()
end)

--- One Auto Shot cycle through the REAL Update path: a 2.0 s cycle with a
--- 2.0 s base speed (aimLen = 0.5 x 2.0/2.0 = 0.5, the window the slice
--- keeps), the shot's START at the floor, SUCCEEDED (the proven flight),
--- then the next PLAYER_SWING re-arm; sampled at the 10 Hz render rate.
--- `mode` picks the fill path; returns {observations, passes}.
local function runCycle(mode)
    Swing:SetFillEngineMode(mode)
    local clock = { 5000 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:SetShowSafeWindow(true)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    local out, passes = {}, 0
    local function pass()
        passes = passes + 1
        Swing:Update(clock[1])
        out[#out + 1] = string.format("%s|i%.2f|a%.2f|r%.2f|c%.2f|k%s|s%s",
            tostring(Swing._phase), Swing._fillIntent or -1,
            Swing._aimW or -1, Swing._retryW or -1, Swing._castW or -1,
            tostring(Swing._timeKey), tostring(Swing._shown and 1 or 0))
    end
    local i = 0
    local step = 0.1
    while clock[1] <= 5003.0001 do
        if math.abs(clock[1] - 5001.5) < 1e-6 then
            t:OnShotCast("START", "Auto Shot", 75, "G1")
        elseif math.abs(clock[1] - 5001.9) < 1e-6 then
            t:OnShotCast("SUCCEEDED", "Auto Shot", 75, "G1")
        elseif math.abs(clock[1] - 5002.0) < 1e-6 then
            t:OnSwingStart(2.0, 2)              -- the next cycle re-arms
        end
        pass()
        i = i + 1
        clock[1] = 5000 + i * step
    end
    return out, passes
end

test("fill I3a: both fill paths draw the same state sequence for one cycle",
function()
    local luaObs, luaPasses = runCycle("lua")
    local engObs, engPasses = runCycle("engine")
    restoreBar()
    -- The cycle really ran on both paths (the phases, the aim slice, the
    -- white flight, the re-arm all appear).
    assertTrue(#luaObs >= 30)
    assertEquals(luaPasses, engPasses)
    local sawAim, sawFly, sawReload = 0, 0, 0
    for _, o in ipairs(luaObs) do
        if o:find("^reload") then sawReload = sawReload + 1 end
        if o:find("^aim") then sawAim = sawAim + 1 end
        if o:find("^flying") then sawFly = sawFly + 1 end
    end
    assertTrue(sawReload > 0)
    assertTrue(sawAim > 0)
    assertTrue(sawFly > 0)
    -- THE ACCEPTANCE: one observation per pass, identical on both paths.
    assertEquals(#luaObs, #engObs)
    for i = 1, #luaObs do
        assertEquals(luaObs[i], engObs[i])
    end
end)

test("fill I3a: the engine fill is armed at the cycle edges, not per frame",
function()
    Swing:SetFillEngineMode("engine")
    local clock = { 6000 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:SetShowSafeWindow(true)
    Swing:RenderIdle()
    local log = Swing:FillLog(true)
    local remDir = _G.Enum.StatusBarTimerDirection.RemainingTime
    -- A 30 Hz sample of one cycle: the shot leaves at 6001.9 (the proven
    -- flight), the next PLAYER_SWING re-arms at 6002.0.
    t:OnSwingStart(2.0, 2)
    local frames = 0
    local i = 0
    while 6000 + i * (1 / 30) <= 6003.0001 do
        local at = 6000 + i * (1 / 30)
        clock[1] = at
        if at >= 6001.9 and at < 6001.9 + (1 / 30) then
            t:OnShotCast("SUCCEEDED", "Auto Shot", 75, "G1")
        elseif at >= 6002.0 and at < 6002.0 + (1 / 30) then
            t:OnSwingStart(2.0, 2)
        end
        frames = frames + 1
        Swing:Update(at)
        i = i + 1
    end
    Swing:FillLog(nil)
    -- The edges: the re-arm span, the white flight, the next re-arm -- and
    -- the two spans carry the law's numbers.
    assertEquals(3, #log)
    assertEquals("span", log[1].kind)
    nearpx(log[1].span, 150)                     -- (2.0-0.5)/2.0 x 200
    nearpx(log[1].dur, 1.5)                      -- the span that is left
    assertEquals(remDir, log[1].dir)
    assertEquals("value", log[2].kind)
    nearpx(log[2].target, 1)                     -- the whole bar, white
    nearpx(log[2].dur, 0)                        -- a static, expired timer
    assertEquals("span", log[3].kind)
    nearpx(log[3].span, 150)
    -- Edge-only arming: three arms across a 30 Hz-sampled cycle.
    assertTrue(frames >= 85)
    assertTrue(#log < frames / 10)
    -- The widget's own geometry at the last arm equals the law's width.
    nearpx(Swing.fill:GetWidth(), log[3].span)
    Swing:RenderIdle()
    restoreBar()
end)

test("fill I3a: the cast interlock arms the frozen fraction as a static value",
function()
    Swing:SetFillEngineMode("engine")
    local clock = { 7000 }
    local t = v2Tracker(clock, { baseSpeed = 2.0,
        castLenReader = function() return 2.0 end })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    local log = Swing:FillLog(true)
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    assertEquals("span", log[1].kind)
    clock[1] = 7001.0
    t:OnShotCast("SENT", "Aimed Shot", 20904, "GA")   -- the no-START law
    Swing:Update(clock[1])
    assertEquals("value", log[2].kind)
    nearpx(log[2].target, 0.5)                  -- frozen at half the cycle
    nearpx(Swing.fill:GetWidth(), 200)          -- the span is the full bar
    Swing:FillLog(nil)
    Swing:RenderIdle()
    restoreBar()
end)

test("fill I3a: a raising widget degrades this bar to the SetSize law",
function()
    Swing:SetFillEngineMode("engine")
    local saved = Swing.fill
    local sized = {}
    local fake = {
        SetSize = function(_, w) sized[#sized + 1] = w end,
        SetStatusBarColor = function() end,
        SetMinMaxValues = function() end,
        SetValue = function() end,
        SetTimerDuration = function() error("no timer on this client") end,
    }
    Swing.fill = fake
    local clock = { 7500 }
    local t = v2Tracker(clock, { baseSpeed = 2.0 })
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(2.0, 2)
    Swing:Update(clock[1])
    assertFalse(Swing:UsesEngineFill(), "a raising SetTimerDuration must "
        .. "degrade this bar to the v2 path")
    nearpx(sized[#sized], 150)                  -- the law drew it the same pass
    clock[1] = 7501.0
    Swing:Update(clock[1])
    nearpx(sized[#sized], 50)
    Swing.fill = saved
    Swing:RenderIdle()
    restoreBar()
end)

-- ============================================================ range laws ==

test("range I3a: the REAL event script obeys the three returns and nil",
function()
    local savedSwing = Tools.Swing
    local clock = { 9000 }
    local sw = v2Tracker(clock, { rangedType = 2 })
    Tools.Swing = sw
    Tools:EnableEvents()
    local f = Tools._eventFrame
    local script = f:GetScript("OnEvent")
    assertNotNil(script)

    -- (swingType, isInRange, checksRange): a nil isInRange with no check
    -- active carries NO knowledge -- the cycle runs on (nil is not out of
    -- range), and the gate's fact stays unstamped.
    sw:OnSwingStart(2.0, 2)
    script(f, "PLAYER_SWING_RANGE_UPDATE", 2, nil, nil)
    assertNotNil(sw.duration)
    assertNil(sw.factsInRange)
    script(f, "PLAYER_SWING_RANGE_UPDATE", 2, nil, true)
    assertNotNil(sw.duration, "nil is not out of range: it is no check "
        .. "possible, not a reason to stop the bar")
    assertNil(sw.factsInRange)
    -- checksRange false: the edge is not a range statement at all.
    script(f, "PLAYER_SWING_RANGE_UPDATE", 2, false, false)
    assertNotNil(sw.duration)
    assertNil(sw.factsInRange)
    -- A non-Ranged slot's edge is not ours at all.
    script(f, "PLAYER_SWING_RANGE_UPDATE", 0, false, true)
    assertNotNil(sw.duration)
    -- The plain false with the check on is the one stop.
    script(f, "PLAYER_SWING_RANGE_UPDATE", 2, false, true)
    assertNil(sw.duration)
    assertEquals(false, sw.factsInRange)
    -- The plain true: the cycle runs on and the gate learns it.
    sw:OnSwingStart(2.0, 2)
    sw.factsInRange = nil
    script(f, "PLAYER_SWING_RANGE_UPDATE", 2, true, true)
    assertNotNil(sw.duration)
    assertEquals(true, sw.factsInRange)
    -- 1/0 are the numeric shape of the same two statements.
    sw.factsInRange = nil
    script(f, "PLAYER_SWING_RANGE_UPDATE", 2, 0, 1)
    assertNil(sw.duration)
    assertEquals(false, sw.factsInRange)
    Tools.Swing = savedSwing
    restoreBar()
end)

test("range I3a: IsTargetWithinSwingRange is the second signal, present only",
function()
    local saved = _G.C_SwingTimer
    local seen = {}
    local sw = Tools.Swing
    local savedReader = sw.rangeReader
    -- Absent (this simulator, measured): the rung answers nothing, so the
    -- spellbook rung owns the answer -- and the sim's
    -- FindSpellBookSlotForSpell takes a spellID, so the name rung answers
    -- nil here too (measured): no knowledge, and the gate's law is nil =
    -- permissive (the aim window must not be closed).
    _G.C_SwingTimer = nil
    local baseline = savedReader()
    assertNil(baseline)
    -- Present, nil: "no check possible" -- NOT out of range.
    _G.C_SwingTimer = {
        IsTargetWithinSwingRange = function(t)
            seen[#seen + 1] = t
            return nil
        end,
    }
    assertEquals(nil, savedReader())
    assertEquals(2, seen[1])                     -- the Ranged slot asked
    -- Present, true / false: the native answer wins over the rungs below.
    _G.C_SwingTimer.IsTargetWithinSwingRange = function() return true end
    assertEquals(true, savedReader())
    _G.C_SwingTimer.IsTargetWithinSwingRange = function() return false end
    assertEquals(false, savedReader())
    _G.C_SwingTimer = saved
    sw.rangeReader = savedReader
    restoreBar()
end)

test("range I3a: EnableRangeCheck is opted in by the union of the requests",
function()
    local savedCST = _G.C_SwingTimer
    local arms = {}
    _G.C_SwingTimer = {
        EnableRangeCheck = function(t, on)
            arms[#arms + 1] = tostring(t) .. "=" .. tostring(on)
        end,
    }
    local savedRequests, savedOn = Tools._rangeCheckRequests, Tools._rangeCheckOn
    Tools._rangeCheckRequests = {}
    Tools._rangeCheckOn = nil
    Tools.RequestRangeCheck("swing", true)
    assertEquals(1, #arms)                        -- the union opened
    assertEquals("2=true", arms[1])
    Tools.RequestRangeCheck("swing", true)       -- idempotent
    Tools.RequestRangeCheck("light", true)       -- the light joins the union
    assertEquals(1, #arms)
    Tools.RequestRangeCheck("swing", false)      -- the light keeps it open
    assertEquals(1, #arms)
    Tools.RequestRangeCheck("light", false)
    assertEquals(2, #arms)                        -- the union closed
    assertEquals("2=false", arms[2])
    Tools._rangeCheckRequests, Tools._rangeCheckOn = savedRequests, savedOn
    _G.C_SwingTimer = savedCST
    restoreBar()
end)

test("range I3a: the range light's opt-in routes through the one owner",
function()
    local RL = FX.Hunter.RangeLight
    assertNotNil(RL)
    local savedRequests, savedOn = Tools._rangeCheckRequests, Tools._rangeCheckOn
    Tools._rangeCheckRequests = {}
    Tools._rangeCheckOn = nil
    RL:SetEnabled(true)
    assertEquals(true, Tools._rangeCheckRequests["light"])
    RL:SetEnabled(false)
    assertNil(Tools._rangeCheckRequests["light"])
    Tools._rangeCheckRequests, Tools._rangeCheckOn = savedRequests, savedOn
    restoreBar()
end)

-- ============================================================== slot speed ==

test("speed I3a: UnitAttackSpeed is read per slot; the 0.5 s aim window kept",
function()
    local savedAS, savedRD = _G.UnitAttackSpeed, _G.UnitRangedDamage
    _G.UnitAttackSpeed = function() return 2.4, 1.6, 3.1 end
    _G.UnitRangedDamage = nil                      -- force the slot leg
    local clock = { 11000 }
    -- The declared (main, offhand, ranged) trio, the leg by the modelled
    -- slot (Enum.PlayerSwingType MainHand=0 / OffHand=1 / Ranged=2).
    assertEquals(2.4, FX.Hunter.NewSwingTracker({ rangedType = 0 }):SlotSpeed())
    assertEquals(1.6, FX.Hunter.NewSwingTracker({ rangedType = 1 }):SlotSpeed())
    assertEquals(3.1, FX.Hunter.NewSwingTracker({ rangedType = 2 }):SlotSpeed())
    -- No speed for the slot (the row law's "no row") and a non-positive
    -- one are both no knowledge.
    _G.UnitAttackSpeed = function() return 2.4, 1.6, nil end
    assertNil(FX.Hunter.NewSwingTracker({ rangedType = 2 }):SlotSpeed())
    _G.UnitAttackSpeed = function() return 2.4, 1.6, 0 end
    assertNil(FX.Hunter.NewSwingTracker({ rangedType = 2 }):SlotSpeed())
    _G.UnitAttackSpeed = function() error("locked") end
    assertNil(FX.Hunter.NewSwingTracker({ rangedType = 2 }):SlotSpeed())
    -- The speed chain: an unusable event duration falls back to the SLOT
    -- speed, and the 0.5 s aim window is kept at the no-haste floor.
    _G.UnitAttackSpeed = function() return 2.4, 1.6, 3.1 end
    local t = FX.Hunter.NewSwingTracker({
        now = function() return clock[1] end,
        rangedType = 2,
    })
    t.shooting = true
    t:OnSwingStart(nil, 2)
    nearpx(t.duration, 3.1)
    nearpx(t.aimLen, 0.5)                          -- the AIM_SECONDS floor
    -- A known base speed stretches the window with the cycle, the 0.5 s
    -- unhasted windup being the base number (0.5 x 3.1 / 2.0).
    t:SetBaseSpeed(2.0)
    t:OnSwingStart(3.1, 2)
    nearpx(t.aimLen, 0.5 * 3.1 / 2.0)
    _G.UnitAttackSpeed, _G.UnitRangedDamage = savedAS, savedRD
    restoreBar()
end)
