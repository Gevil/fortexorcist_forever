-- addon/Forte_Cooldown/tests/test_zzc_motion.lua
-- (File order: this file sorts LAST on purpose. The Display's slot / splash /
-- pulse pools only grow and test_timeline.lua pins exact pool sizes from a
-- fresh pool -- these legs build several rows and must run after it.)
-- PLAN §11.13 (Iteration S, S1/S4): the cooldown bar's per-frame MOTION pass
-- and the per-frame splash/pulse curves, driven through the REAL frame
-- scripts (the render frame's OnUpdate, the splash/pulse frames' OnUpdate,
-- the Secondary Splash window's OnUpdate) fetched with GetScript and called
-- the way the client calls them, on a stubbed GetTime clock.
--
-- Pinned (the S1 contract, items 1-3 and its test list):
--   (1) N consecutive frames at 1/165 s with a row in motion -> the moved
--       value changes on EVERY frame, monotonically; for a linear bar
--       (power scale 1) in equal steps (1e-6 relative);
--   (2) identical final positions for the same wall-clock span at 30, 60,
--       165 and 240 fps (the time base is GetTime, not summed elapsed);
--   (3) full-pass call count over 1 s stays on the 10 Hz cadence while the
--       motion pass runs once per frame;
--   (4) nothing moving / display hidden -> NO OnUpdate on the render frame;
--       it is installed again when motion starts and leaves by itself when
--       the last row stops;
--   (5) zero allocation: collectgarbage("count") does not move across 1000
--       motion passes with rows in motion;
--   (6) the motion pass and the full pass give the same position at the
--       same instant (one position function), so a full pass between two
--       frames does not jump an icon along the axis, and the group
--       segments follow;
--   (+) the cast splash, the ready pulse (Timeline) and the Secondary
--       Splash bell run on every frame while shown and drop their script
--       when done.

local FX = ForteXorcist
local M = FX.Cooldown.Module
local Engine = FX.Cooldown.Engine
local Display = FX.Cooldown.Display
local Splash = FX.Cooldown.Splash
local TM = FX.Cooldown.TimelineMath
local S = FX.Cooldown.TimelineSkin

local function near(a, b, tol)
    return assertTrue(math.abs(a - b) <= (tol or 1e-6),
        "expected " .. tostring(b) .. ", got " .. tostring(a))
end

local function enable()
    if not M._eventFrame then M:OnEnable() end
    Display:Init()
    -- Start every leg from a drained pump: earlier suite files dispatch
    -- events that legitimately leave a pass request pending.
    local p = M._pump
    p.dirty, p.wanted, p.armedAt = false, false, nil
    M:SyncPump()
end

local clock = 0
--- Run `body` with the global clock stubbed (the renderer, the Module and
--- the splash scripts read GetTime at call time) and `restore` always run.
local function withClock(body)
    local saved = _G.GetTime
    _G.GetTime = function() return clock end
    local ok, err = pcall(body)
    _G.GetTime = saved
    if not ok then error(err, 0) end
end

local function row(name, endTime, duration)
    duration = duration or 100
    return { name = name, start = endTime - duration, duration = duration,
        endTime = endTime }
end

local function clearBar(now)
    Display:Update({}, now)
    -- Retire any splash/pulse a previous leg left running (the full pass is
    -- the injected-clock driver of both; their frames drop their scripts).
    Display:UpdateSplashes(now + 1000)
    Display:UpdatePulses(now + 1000)
end

local function pumpOf()
    return M._renderFrame, M._renderFrame:GetScript("OnUpdate")
end

local BASE = 50000     -- far-future epoch: the live ticker never pops these

-- ------------------------------------------------------------- the math --

test("TimelineMath.place is pos plus the position factor; moves is the open window (0, Max]",
function()
    local W, H, Max, Loga = 250, 24, 300, 0.33
    for _, t in ipairs({ -1, 0, 0.5, 10, 120, 300, 301, 900 }) do
        local x, v = TM.place(t, W, H, Max, Loga)
        near(x, TM.pos(t, W, H, Max, Loga), 1e-12)
        near(v, (x + H * 0.5) / W, 1e-12)
    end
    assertFalse(TM.moves(0, 300), "a finished row is parked at the left end")
    assertFalse(TM.moves(-2, 300))
    assertTrue(TM.moves(0.001, 300))
    assertTrue(TM.moves(300, 300), "t == Max is on the curve")
    assertFalse(TM.moves(300.5, 300), "t > Max parks at the right end")
end)

-- ---------------------------------------------------------- (1) per frame --

test("S4: 165 fps -> the icon moves on EVERY frame, monotonically, in equal steps on a linear bar",
function()
    enable()
    local savedLoga = S.Loga
    Display:SetPowerScale(1)                 -- v = f1*t/Max + f2: linear in t
    local ok, err = pcall(function()
        withClock(function()
            clock = BASE
            Display:Update({ row("MotionLin", BASE + 100) }, BASE)
            local f, pump = pumpOf()
            assertNotNil(pump, "a shown bar with a moving row carries the motion script")
            local slot = Display._byName["MotionLin"]
            local prev, firstStep = slot._cx, nil
            for i = 1, 60 do
                clock = BASE + i / 165
                pump(f, 1 / 165)
                local step = slot._cx - prev
                assertTrue(step < 0, "frame " .. i .. ": the icon slid left (" .. step .. ")")
                firstStep = firstStep or step
                assertTrue(math.abs(step - firstStep) <= 1e-6 * math.abs(firstStep),
                    "frame " .. i .. ": equal steps (" .. step .. " vs " .. firstStep .. ")")
                prev = slot._cx
            end
            -- The anchor the client holds is the cached number (float32).
            local _, _, _, ox = slot.frame:GetPoint()
            near(ox, slot._cx, 1e-3)
            -- And the segment's right edge rides the icon centre.
            near(slot._segR, slot._cx + S.Height * 0.5, 1e-9)
        end)
    end)
    Display:SetPowerScale(savedLoga)
    clock = BASE
    withClock(function() clearBar(BASE) end)
    if not ok then error(err, 0) end
end)

test("S4: a nonlinear bar (the shipped 0.33 scale) also moves on every frame",
function()
    enable()
    withClock(function()
        clock = BASE
        Display:Update({ row("MotionPow", BASE + 40) }, BASE)
        local f, pump = pumpOf()
        local slot = Display._byName["MotionPow"]
        local prev = slot._cx
        for i = 1, 100 do
            clock = BASE + i / 165
            pump(f, 1 / 165)
            assertTrue(slot._cx < prev, "frame " .. i .. " moved left")
            prev = slot._cx
        end
        clearBar(BASE)
    end)
end)

-- ------------------------------------------------- (2) any frame rate --

test("S4: identical final positions for the same wall-clock span at 30, 60, 165 and 240 fps",
function()
    enable()
    withClock(function()
        local finals = {}
        for _, fps in ipairs({ 30, 60, 165, 240 }) do
            clock = BASE
            Display:Update({ row("MotionFps", BASE + 90) }, BASE)
            local f, pump = pumpOf()
            local frames = math.floor(fps * 0.5)
            for i = 1, frames - 1 do
                clock = BASE + i / fps
                pump(f, 1 / fps)
            end
            clock = BASE + 0.5                       -- the span's last frame
            pump(f, 1 / fps)
            finals[fps] = Display._byName["MotionFps"]._cx
        end
        local expected = TM.pos(89.5, S.Width, S.Height, S.Max, S.Loga)
        for fps, x in pairs(finals) do
            near(x, expected, 1e-9)
        end
        -- A hitch: one frame that jumps 0.4 s lands on the exact position.
        clock = BASE
        Display:Update({ row("MotionFps", BASE + 90) }, BASE)
        local f, pump = pumpOf()
        clock = BASE + 0.4
        pump(f, 0.4)
        near(Display._byName["MotionFps"]._cx,
            TM.pos(89.6, S.Width, S.Height, S.Max, S.Loga), 1e-9)
        clearBar(BASE)
    end)
end)

-- --------------------------------------- (3) full pass stays on the beat --

test("S4: over 1 s at 165 fps the motion pass runs per frame and the full pass only on the 10 Hz beat",
function()
    enable()
    local realUpdate, realMotion, realReadAll = Display.Update, Display.Motion, M.ReadAll
    local nUpdate, nMotion = 0, 0
    Display.Update = function(self, ...)
        nUpdate = nUpdate + 1
        return realUpdate(self, ...)
    end
    Display.Motion = function(self, ...)
        nMotion = nMotion + 1
        return realMotion(self, ...)
    end
    M.ReadAll = function() end         -- the 1 Hz net would re-read the real client
    local ok, err = pcall(function()
        withClock(function()
            for name in pairs(Engine.entries) do Engine.entries[name] = nil end
            Engine.tracked["MotionTick1"] = { name = "MotionTick1", dataId = 1, baseDuration = 60 }
            Engine.tracked["MotionTick2"] = { name = "MotionTick2", dataId = 1, baseDuration = 120 }
            clock = BASE
            Engine:OnCast("MotionTick1", BASE)
            Engine:OnCast("MotionTick2", BASE)
            M:Tick(BASE)                           -- beat 0: rows in, script on
            local f = M._renderFrame
            assertNotNil(f:GetScript("OnUpdate"),
                "the beat's full pass found moving rows and installed the script")
            nUpdate, nMotion = 0, 0
            local nextBeat = BASE + 0.1
            for i = 1, 165 do
                clock = BASE + i / 165
                local pump = f:GetScript("OnUpdate")
                if pump then pump(f, 1 / 165) end
                while clock >= nextBeat - 1e-9 do
                    M:Tick(clock)
                    nextBeat = nextBeat + 0.1
                end
            end
            -- Every full pass runs the shared motion function once at its own
            -- clock (that is how both passes write the same value), so the
            -- count of motion calls is the frames plus the full passes.
            assertEquals(165, nMotion - nUpdate, "one motion pass per rendered frame")
            assertTrue(nUpdate >= 9 and nUpdate <= 11,
                "the full pass runs on the 10 Hz beat, got " .. nUpdate
                .. " in one second (the old pump: ~60)")
        end)
    end)
    Display.Update, Display.Motion, M.ReadAll = realUpdate, realMotion, realReadAll
    for name in pairs(Engine.entries) do Engine.entries[name] = nil end
    Engine.tracked["MotionTick1"], Engine.tracked["MotionTick2"] = nil, nil
    withClock(function() clearBar(BASE) end)
    if not ok then error(err, 0) end
end)

-- ---------------------------------------- (4) the script only while needed --

test("S4: no OnUpdate while idle or hidden; installed when motion starts; gone when the last row stops",
function()
    enable()
    withClock(function()
        local f = M._renderFrame
        clock = BASE
        clearBar(BASE)
        assertNil(f:GetScript("OnUpdate"), "an empty bar: no per-frame script")

        Display:Update({ row("MotionIdle", BASE + 100) }, BASE)
        assertNotNil(f:GetScript("OnUpdate"), "a row in motion installs it")

        -- A row parked beyond Max does not move (and, past its 1 s fade-in,
        -- nothing else animates): no script.
        Display:Update({ row("MotionIdle", BASE + S.Max + 500, S.Max + 500) }, BASE + 5)
        assertNil(f:GetScript("OnUpdate"), "a parked row (t > Max) is not motion")
        Display:Update({ row("MotionIdle", BASE + 100) }, BASE)
        assertNotNil(f:GetScript("OnUpdate"))

        -- Hidden bar: the Display's own gate. The full pass removes the
        -- script ...
        Display:SetEnabled(false)
        Display:Update({ row("MotionIdle", BASE + 100) }, BASE)
        assertNil(f:GetScript("OnUpdate"), "a hidden bar carries no per-frame script")
        Display:SetEnabled(true)
        Display:Update({ row("MotionIdle", BASE + 100) }, BASE)
        assertNotNil(f:GetScript("OnUpdate"), "shown again: installed again")

        -- ... and a hide that lands between two full passes is noticed by
        -- the very next frame (the pass answers false and the script leaves).
        Display:SetEnabled(false)
        f:GetScript("OnUpdate")(f, 1 / 165)
        assertNil(f:GetScript("OnUpdate"))
        Display:SetEnabled(true)

        -- The last row stops: the script leaves by itself on that frame.
        clock = BASE
        Display:Update({ row("MotionIdle", BASE + 1, 20) }, BASE)
        local pump = f:GetScript("OnUpdate")
        assertNotNil(pump)
        clock = BASE + 0.5
        pump(f, 0.5)
        assertNotNil(f:GetScript("OnUpdate"), "still moving at 0.5 s")
        clock = BASE + 1.02
        pump(f, 0.52)
        assertNil(f:GetScript("OnUpdate"), "the row reached the left end: no more motion")
        near(Display._byName["MotionIdle"]._cx,
            TM.pos(0, S.Width, S.Height, S.Max, S.Loga), 1e-9)
        clearBar(clock)
    end)
end)

-- ---------------------------------------------------- (5) zero allocation --

test("S4: 1000 motion passes with rows in motion allocate nothing (collectgarbage count)",
function()
    enable()
    if type(collectgarbage) ~= "function" then
        print("[motion] collectgarbage absent: the allocation test is skipped")
        return
    end
    withClock(function()
        clock = BASE
        Display._steal["MotionGcB"] = true          -- an armed attention spark too
        Display:Update({
            row("MotionGcA", BASE + 20),
            row("MotionGcB", BASE + 20.3),          -- a group with A
            row("MotionGcC", BASE + 80),
            row("MotionGcD", BASE + 150),
            row("MotionGcE", BASE + 250),
        }, BASE)
        local f, pump = pumpOf()
        assertNotNil(pump)
        for i = 1, 50 do                             -- warm: first-use caches
            clock = BASE + i / 165
            pump(f, 1 / 165)
        end
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for i = 1, 1000 do
            clock = BASE + 0.3 + i / 1650
            pump(f, 1 / 165)
        end
        local after = collectgarbage("count")
        collectgarbage("restart")
        print(string.format("[motion] 1000 passes x 5 rows: %.3f KB delta", after - before))
        assertEquals(0, after - before,
            "no table, closure or string is built per motion pass")
        clearBar(clock)
    end)
end)

-- -------------------------- (6) one position function, full == motion --

test("S4: a full pass between two frames does not move an icon along the axis; the group segments follow",
function()
    enable()
    withClock(function()
        local feed = {
            row("MotionG1", BASE + 30),
            row("MotionG2", BASE + 30.4),           -- overlaps G1: one group
            row("MotionG3", BASE + 100),            -- its own group
        }
        clock = BASE
        Display:Update(feed, BASE)
        local f, pump = pumpOf()
        for i = 1, 16 do                            -- 0.097 s: just under a beat
            clock = BASE + i / 165
            pump(f, 1 / 165)
        end
        local names = { "MotionG1", "MotionG2", "MotionG3" }
        local before = {}
        for _, name in ipairs(names) do
            local s = Display._byName[name]
            before[name] = { cx = s._cx, l = s._segL, r = s._segR,
                vl = s._segVL, v = s._segV }
        end
        -- The group's left border for G3 is G1's centre, as the full pass
        -- computed it: the segment followed the moving icon.
        near(before.MotionG3.l, Display._byName["MotionG1"]._cx + S.Height * 0.5, 1e-9)
        near(before.MotionG3.vl,
            (Display._byName["MotionG1"]._cx + S.Height * 0.5) / S.Width, 1e-9)
        near(before.MotionG1.l, 0, 1e-12)
        near(before.MotionG2.l, 0, 1e-12)

        -- The beat: a FULL pass at the same instant writes the same numbers.
        Display:Update(feed, clock)
        for _, name in ipairs(names) do
            local s, b = Display._byName[name], before[name]
            near(s._cx, b.cx, 1e-9)
            near(s._segL, b.l, 1e-9)
            near(s._segR, b.r, 1e-9)
            near(s._segVL, b.vl, 1e-9)
            near(s._segV, b.v, 1e-9)
        end
        -- And the expectation is the formula itself, at that instant.
        for i, name in ipairs(names) do
            local remaining = feed[i].endTime - clock
            near(Display._byName[name]._cx,
                TM.pos(remaining, S.Width, S.Height, S.Max, S.Loga), 1e-9)
        end
        clearBar(clock)
    end)
end)

-- ------------------------------- the bar's cast splash / ready pulse --

test("S4: the cast splash runs its curve on EVERY frame while shown and drops its script",
function()
    enable()
    withClock(function()
        clock = BASE
        clearBar(BASE)
        Display:Update({ row("MotionSplash", BASE + 200) }, BASE)   -- first sighting
        local s
        for i = 1, #Display.splashPool do
            if Display.splashPool[i]._endAt then s = Display.splashPool[i] end
        end
        assertNotNil(s, "the first sighting spawned a splash")
        local script = s.frame:GetScript("OnUpdate")
        assertNotNil(script, "a shown splash carries its per-frame script")
        local prevA, prevW = s.frame:GetAlpha(), s.tex:GetWidth()
        local frames = 0
        for i = 1, 165 do
            clock = BASE + i / 165
            local cur = s.frame:GetScript("OnUpdate")
            if not cur then break end
            cur(s.frame, 1 / 165)
            if s._endAt then
                frames = frames + 1
                local a, w = s.frame:GetAlpha(), s.tex:GetWidth()
                assertTrue(a < prevA, "frame " .. i .. ": alpha fell")
                assertTrue(w > prevW, "frame " .. i .. ": the icon grew")
                prevA, prevW = a, w
            end
        end
        assertTrue(frames >= 160, "the curve ran on (almost) every frame: " .. frames)
        clock = BASE + 1.01
        local cur = s.frame:GetScript("OnUpdate")
        if cur then cur(s.frame, 0.01) end
        assertNil(s.frame:GetScript("OnUpdate"), "the script is removed when the splash is done")
        assertFalse(s.frame:IsShown())
        clearBar(clock)
    end)
end)

test("S4: the ready pulse fades on EVERY frame while shown and drops its script",
function()
    enable()
    withClock(function()
        clock = BASE
        clearBar(BASE)
        Display:Update({ row("MotionPulse", BASE + 5, 5) }, BASE)
        Display:OnReady("MotionPulse", BASE)
        Display:Update({}, BASE)                     -- the name left the feed: pulse spawns
        local p
        for i = 1, #Display.pulsePool do
            if Display.pulsePool[i]._endAt then p = Display.pulsePool[i] end
        end
        assertNotNil(p, "the ready pop spawned a pulse")
        assertNotNil(p.frame:GetScript("OnUpdate"), "a shown pulse carries its per-frame script")
        local prev = p.frame:GetAlpha()
        local frames = 0
        for i = 1, 165 do
            clock = BASE + i / 165
            local cur = p.frame:GetScript("OnUpdate")
            if not cur then break end
            cur(p.frame, 1 / 165)
            if p._endAt then
                frames = frames + 1
                local a = p.frame:GetAlpha()
                assertTrue(a < prev, "frame " .. i .. ": the pulse faded")
                prev = a
            end
        end
        assertTrue(frames >= 160, "the fade ran on (almost) every frame: " .. frames)
        clock = BASE + 1.01
        local cur = p.frame:GetScript("OnUpdate")
        if cur then cur(p.frame, 0.01) end
        assertNil(p.frame:GetScript("OnUpdate"), "the script is removed when the pulse ends")
        assertFalse(p.frame:IsShown())
    end)
end)

-- ------------------------------------------- the Secondary (ready) Splash --

test("S4: the ready splash bell runs on EVERY frame while a splash lives; the window's script leaves with it",
function()
    enable()
    Splash:OnEnable()
    local wasLocked = Splash.cfg.locked
    Splash:SetLocked(true)
    Splash:SetEnabled(true)
    local ok, err = pcall(function()
        withClock(function()
            for name in pairs(Engine.entries) do Engine.entries[name] = nil end
            Engine.tracked["MotionSplashPop"] = { name = "MotionSplashPop", dataId = 1, baseDuration = 20 }
            Engine:OnCast("MotionSplashPop", BASE)
            clock = BASE + 21
            M:ProcessReadyPops(clock)                  -- the pop: ready at BASE + 20
            local f = Splash.anchor
            assertTrue(f:IsShown(), "the pop shows the window")
            local script = f:GetScript("OnUpdate")
            assertNotNil(script, "a live splash window carries the per-frame script")
            local slot = Splash._icons[1]
            local start = slot.startAt
            local prevA, prevS = slot.frame:GetAlpha(), slot.tex:GetWidth()
            for i = 1, 164 do
                clock = start + i / 165
                f:GetScript("OnUpdate")(f, 1 / 165)
                local a, w = slot.frame:GetAlpha(), slot.tex:GetWidth()
                if i <= 80 then                        -- the rising half of the bell
                    assertTrue(a > prevA, "frame " .. i .. ": alpha rising")
                    assertTrue(w > prevS, "frame " .. i .. ": size rising")
                elseif i >= 86 then                    -- the falling half
                    assertTrue(a < prevA, "frame " .. i .. ": alpha falling")
                    assertTrue(w < prevS, "frame " .. i .. ": size falling")
                end
                prevA, prevS = a, w
            end
            clock = start + 1.01
            local cur = f:GetScript("OnUpdate")
            if cur then cur(f, 0.01) end
            assertFalse(f:IsShown(), "the locked window hides when the window ends")
            assertNil(f:GetScript("OnUpdate"), "and its script is removed")
        end)
    end)
    Splash:SetEnabled(false)
    Splash:SetLocked(wasLocked and true or false)
    for name in pairs(Engine.entries) do Engine.entries[name] = nil end
    Engine.tracked["MotionSplashPop"] = nil
    if not ok then error(err, 0) end
end)

-- ------------------------------------------ the time-driven fades (S1.1) --
-- Every visual that is a pure function of (start stamp, duration, now) runs
-- in the motion pass: the icon fade-in, the group cross-fade, the attention
-- spark and the segment colour alpha. Each leg isolates ONE of them (rows
-- parked beyond Max do not travel) and pins: it changes on every frame at
-- 1/165 s, it reaches its end value exactly, the full pass writes the same
-- value at the same instant, and the render script leaves when the last
-- fade is over.

test("S4.fade: the icon fade-in changes on EVERY frame, ends exactly at AlphaMax, equals the full pass, and the script leaves",
function()
    enable()
    withClock(function()
        clock = BASE
        clearBar(BASE)
        local feed = { row("MotionFade", BASE + S.Max + 1000, S.Max + 1000) }  -- parked
        Display:Update(feed, BASE)
        local f, pump = pumpOf()
        assertNotNil(pump, "a fade in progress keeps the script (nothing travels)")
        local slot = Display._byName["MotionFade"]
        assertEquals(S.Alpha, slot._alpha, "the ramp starts at Alpha")
        local prev = slot._alpha
        for i = 1, 164 do
            clock = BASE + i / 165
            pump(f, 1 / 165)
            assertTrue(slot._alpha > prev, "frame " .. i .. ": alpha rose")
            near(slot._alpha, S.Alpha + (S.AlphaMax - S.Alpha) * (i / 165), 1e-9)
            prev = slot._alpha
            if i == 80 then
                Display:Update(feed, clock)         -- a full pass at the same instant
                near(slot._alpha, prev, 1e-12)
                assertNotNil(f:GetScript("OnUpdate"))
            end
        end
        clock = BASE + 1.0
        pump(f, 1 / 165)
        assertEquals(S.AlphaMax, slot._alpha, "the ramp ends EXACTLY at AlphaMax")
        near(slot.frame:GetAlpha(), S.AlphaMax, 1e-6)
        assertNil(f:GetScript("OnUpdate"), "the last fade ended: the script is removed")
        clearBar(clock)
    end)
end)

test("S4.fade: a group's cross-fade changes on EVERY frame in equal steps, is continuous across the hand-off, equals the full pass",
function()
    enable()
    withClock(function()
        clock = BASE
        clearBar(BASE)
        -- Both rows parked at the right end: they overlap (one group), nothing travels.
        local feed = {
            row("MotionXA", BASE + S.Max + 1000, S.Max + 1000),
            row("MotionXB", BASE + S.Max + 1001, S.Max + 1001),
        }
        Display:Update(feed, BASE)                   -- bind: the fade-in starts
        Display:Update(feed, BASE + 5)               -- fade-in long over; focus state caught up
        local f, pump = pumpOf()
        assertNotNil(pump, "a standing group cross-fades for as long as it stands")
        local a, b = Display._byName["MotionXA"], Display._byName["MotionXB"]
        local base = BASE + 5
        local pa, pb = a._alpha, b._alpha
        for i = 1, 200 do                            -- 1.21 s: one hand-off inside
            clock = base + i / 165
            pump(f, 1 / 165)
            near(a._alpha + b._alpha, S.AlphaMax, 1e-9)       -- frac + (1 - frac)
            near(math.abs(a._alpha - pa), 1 / 165, 1e-6)      -- equal steps, every frame
            near(math.abs(b._alpha - pb), 1 / 165, 1e-6)
            pa, pb = a._alpha, b._alpha
            if i == 50 then
                Display:Update(feed, clock)          -- full pass, same instant
                near(a._alpha, pa, 1e-9)
                near(b._alpha, pb, 1e-9)
            end
        end
        assertNotNil(f:GetScript("OnUpdate"))
        clearBar(clock)
    end)
end)

test("S4.fade: the attention spark contracts on EVERY frame, ends hidden, and the script leaves",
function()
    enable()
    withClock(function()
        clock = BASE
        clearBar(BASE)
        local feed = { row("MotionAtt", BASE + S.Max + 1000, S.Max + 1000) }   -- parked
        Display:Update(feed, BASE)
        Display:Update(feed, BASE + 5)               -- fade-in over: idle
        local f = M._renderFrame
        assertNil(f:GetScript("OnUpdate"), "a finished, parked, ungrouped icon animates nothing")
        Display._steal["MotionAtt"] = true           -- a failed cast takes attention
        Display:Update(feed, BASE + 5)
        local slot = Display._byName["MotionAtt"]
        local pump = f:GetScript("OnUpdate")
        assertNotNil(pump, "an attention window keeps the script")
        assertTrue(slot.alert:IsShown())
        local prev, frames = slot._alertSize, 0
        for i = 1, 90 do
            local cur = f:GetScript("OnUpdate")
            if not cur then break end
            clock = BASE + 5 + i / 165
            cur(f, 1 / 165)
            if slot._alertEnd then
                frames = frames + 1
                assertTrue(slot._alertSize < prev, "frame " .. i .. ": the spark contracted")
                prev = slot._alertSize
            end
        end
        assertTrue(frames >= 80, "the spark moved on (almost) every frame: " .. frames)
        assertFalse(slot.alert:IsShown(), "the window ended: the spark is hidden")
        assertNil(slot._alertEnd)
        assertNil(f:GetScript("OnUpdate"), "and the script is removed with the last fade")
        clearBar(clock)
    end)
end)

test("S4.fade: the segment colour alpha follows the icon on EVERY frame and equals the full pass",
function()
    enable()
    withClock(function()
        clock = BASE
        clearBar(BASE)
        local feed = { row("MotionSegA", BASE + 60, 60) }
        Display:Update(feed, BASE)
        local f, pump = pumpOf()
        local slot = Display._byName["MotionSegA"]
        local prev = slot._segA
        for i = 1, 100 do
            clock = BASE + i / 165
            pump(f, 1 / 165)
            assertTrue(slot._segA > prev, "frame " .. i .. ": the slice alpha follows the position")
            prev = slot._segA
            assertEquals(slot._segA, slot._segSetA, "and it was applied to the texture")
            local _, v = TM.place(BASE + 60 - clock, S.Width, S.Height, S.Max, S.Loga)
            near(slot._segA, S.AlphaMax - (S.AlphaMax - S.Alpha) * v, 1e-12)
            if i == 40 then
                Display:Update(feed, clock)
                near(slot._segA, prev, 1e-12)
            end
        end
        clearBar(clock)
    end)
end)

test("S1.2: a row parked beyond Max reports its crossing moment once; the timer's fire requests a pass",
function()
    enable()
    withClock(function()
        local timers = {}
        local savedAfter = C_Timer.After
        C_Timer.After = function(delay, fn) timers[#timers + 1] = { delay, fn } end
        local ok, err = pcall(function()
            clock = BASE
            clearBar(BASE)
            M._pump.armedAt = nil
            local feed = { row("MotionCross", BASE + S.Max + 50, S.Max + 50) }
            Display:Update(feed, BASE)
            assertEquals(1, #timers, "the parked row armed one timer")
            near(timers[1][1], 50, 1e-9)             -- it enters the curve 50 s from now
            Display:Update(feed, BASE + 0.1)
            assertEquals(1, #timers, "every beat re-reports the same moment: no second timer")
            timers[1][2]()
            assertTrue(M._pump.dirty, "the fire requests a full pass for the next frame")
            assertNotNil(M._renderFrame:GetScript("OnUpdate"))
        end)
        C_Timer.After = savedAfter
        M._pump.dirty, M._pump.armedAt = false, nil
        M:SyncPump()
        clearBar(BASE)
        if not ok then error(err, 0) end
    end)
end)
