-- addon/Forte_Hunter/tests/test_swing_motion.lua
-- PLAN §11.13 (Iteration S, S3/S4): motion follows the frame, logic does not.
-- The Hunter displays split into an EDGE pass (10 Hz: phase decisions,
-- tracker reads, text, colours, show/hide) and a MOTION pass (every rendered
-- frame while something moves: fill, spark, slices, markers; the melee rail's
-- fill; the aspect reminder's pulse). Every leg here drives the REAL OnUpdate
-- scripts the frames carry (`anchor:GetScript("OnUpdate")`), through a stubbed
-- GetTime, exactly as the client does: N frames at 1/fps seconds.
--
--   (1) N consecutive 165 fps frames: the position changes on EVERY frame in
--       equal steps (a linear bar);
--   (2) identical positions for the same wall-clock span at 30/60/165/240 fps;
--   (3) the edge pass stays on its slow cadence (counted), and a phase edge
--       (aim start, cycle end, retry deadline) lands on the frame it passes,
--       not up to 100 ms later;
--   (4) idle / hidden -> no OnUpdate; it is installed again with the motion;
--   (5) zero allocation per motion pass (collectgarbage("count"));
--   (6) the motion pass and the edge pass give the same position at the same
--       instant;
--   + the engine fill is never double-driven (spark moves, fill left alone),
--     the melee rail and the aspect reminder follow the same split.

local FX = ForteXorcist
local Tools = FX.Hunter.Tools
local Swing = FX.Hunter.Swing
local Melee = FX.Hunter.Melee
local MeleeCore = FX.Hunter.MeleeCore
local RangeLight = FX.Hunter.RangeLight
local Reminder = FX.Hunter.Reminder
local S = FX.Hunter.SwingSkin
local RS = FX.Hunter.ReminderSkin

--- The harness' assertTrue drops its message; this file's legs carry numbers
--- worth reading in a failure, so the file's own asserts raise with them.
local function check(cond, msg)
    if not cond then error(msg or "expected truthy, got false", 0) end
end
local assertTrue = check

local function near(actual, expected, tol)
    tol = tol or 1e-6
    return check(math.abs(actual - expected) <= tol,
        "expected " .. tostring(expected) .. " got " .. tostring(actual))
end

--- Run `body(box)` with GetTime stubbed to `box[1]`; the bar is handed back
--- idle in its default posture whatever happens.
local function withClock(base, body)
    local saved = _G.GetTime
    local box = { base }
    _G.GetTime = function() return box[1] end
    local ok, err = pcall(body, box)
    _G.GetTime = saved
    Swing:SetFillEngineMode("lua")
    Swing:SetBarMode("safe")
    Swing:FillLog(nil)
    Swing:SetTracker(Tools.Swing)
    Swing:RenderIdle()
    assertEquals("ok", ok and "ok" or tostring(err))
end

--- A permissive-gate tracker on the box clock (aimLen = 0.5 at base 2.0).
local function v2Tracker(box, extra)
    local opts = {
        now = function() return box[1] end,
        speedReader = function() return nil end,
        rangedType = 2,
        targetReader = function() return true end,
        deadReader = function() return false end,
        attackReader = function() return true end,
        speedSampler = function() return nil end,
        rangeReader = function() return nil end,
        castLenReader = function() return nil end,
        baseSpeed = 2.0,
    }
    for k, v in pairs(extra or {}) do opts[k] = v end
    local t = FX.Hunter.NewSwingTracker(opts)
    t.shooting = true
    return t
end

--- A 2.0 s cycle starting at box[1], the bar kicked on; returns the REAL
--- OnUpdate script.
local function startBar(box, t, dur)
    Swing:Init()
    Swing:SetTracker(t)
    Swing:RenderIdle()
    t:OnSwingStart(dur or 2.0, 2)
    Swing:Kick()
    local script = Swing.anchor:GetScript("OnUpdate")
    assertNotNil(script, "a live swing installs the per-frame script")
    return script
end

--- Count the edge passes (`D:Update`) and record their instants.
local function spyUpdate()
    local real = Swing.Update
    local spy = { n = 0, at = {} }
    Swing.Update = function(self, now)
        spy.n = spy.n + 1
        spy.at[spy.n] = now
        return real(self, now)
    end
    spy.stop = function() Swing.Update = real end
    return spy
end

-- --------------------------------------------------------- (1) every frame --
test("motion: the fill and the spark move on EVERY 165 fps frame, in equal steps",
function()
    withClock(1000, function(box)
        Swing:SetBarMode("elapsed")                 -- the plain linear bar
        local script = startBar(box, v2Tracker(box))
        local dt = 1 / 165
        local prev = Swing._fillW
        near(prev, 0)
        local step
        for i = 1, 90 do
            box[1] = 1000 + i * dt
            script(Swing.anchor, dt)
            local w = Swing._fillW
            assertTrue(w > prev, "frame " .. i .. " did not move the fill")
            if step then near(w - prev, step, 1e-6) end
            step = w - prev
            prev = w
            near(Swing._sparkX, w)                  -- the spark rides the head
        end
        near(step, S.Width / 2.0 / 165)             -- W x (1/165) / 2.0 s
        near(Swing.fill:GetWidth(), Swing._fillW, 0.5)
    end)
end)

test("motion: the safe-window fill (the default mode) shrinks every frame too",
function()
    withClock(1000, function(box)
        local script = startBar(box, v2Tracker(box))
        local dt = 1 / 165
        local prev = Swing._fillW
        near(prev, 150)                             -- (2.0 - 0.5) / 2.0 x 200
        for i = 1, 60 do
            box[1] = 1000 + i * dt
            script(Swing.anchor, dt)
            assertTrue(Swing._fillW < prev, "frame " .. i .. " did not move")
            near(prev - Swing._fillW, S.Width / 2.0 / 165, 1e-6)
            prev = Swing._fillW
        end
    end)
end)

test("motion: the `one` mode's capped fill moves every frame", function()
    withClock(1000, function(box)
        Swing:SetBarMode("one")
        local script = startBar(box, v2Tracker(box))
        local dt = 1 / 165
        local prev = Swing._fillW
        for i = 1, 60 do
            box[1] = 1000 + i * dt
            script(Swing.anchor, dt)
            assertTrue(Swing._fillW > prev, "frame " .. i .. " did not move")
            prev = Swing._fillW
        end
    end)
end)

-- ----------------------------------------------------- (2) any frame rate --
test("motion: identical positions after 1 s at 30 / 60 / 165 / 240 fps",
function()
    for _, mode in ipairs({ "safe", "one", "elapsed" }) do
        local got = {}
        for _, fps in ipairs({ 30, 60, 165, 240 }) do
            withClock(1000, function(box)
                Swing:SetBarMode(mode)
                local script = startBar(box, v2Tracker(box))
                for i = 1, fps do
                    box[1] = 1000 + i / fps
                    script(Swing.anchor, 1 / fps)
                end
                near(box[1], 1001)
                got[#got + 1] = { Swing._fillW, Swing._sparkX }
            end)
        end
        for i = 2, #got do
            near(got[i][1], got[1][1], 1e-6)
            near(got[i][2], got[1][2], 1e-6)
        end
    end
end)

-- ------------------------------------------------- (3) the slow edge pass --
test("motion: the edge pass stays at 10 Hz while the fill moves every frame",
function()
    withClock(1000, function(box)
        local script = startBar(box, v2Tracker(box))
        local spy = spyUpdate()
        local dt = 1 / 165
        for i = 1, 165 do
            box[1] = 1000 + i * dt
            script(Swing.anchor, dt)
        end
        spy.stop()
        assertTrue(spy.n >= 9 and spy.n <= 11,
            "edge passes over 1 s at 165 fps: " .. spy.n)
    end)
end)

test("motion: the aim phase starts on the frame its edge passes, not 100 ms later",
function()
    withClock(1000, function(box)
        local t = v2Tracker(box)
        local script = startBar(box, t)
        local spy = spyUpdate()
        local dt = 1 / 165
        local tAim = 1002 - t.aimLen                 -- remaining <= floor
        local seen
        for i = 1, 400 do
            box[1] = 1000 + i * dt
            script(Swing.anchor, dt)
            if box[1] >= tAim and not seen then
                seen = box[1]
                assertEquals("aim", Swing._phase,
                    "the aim phase must be drawn on the first frame past "
                    .. "its edge")
                assertTrue(box[1] - tAim < dt + 1e-9)
            end
            if box[1] >= tAim + 0.2 then break end
        end
        spy.stop()
        assertNotNil(seen)
        -- ...and the edge pass that drew it ran AT that frame.
        local hit = false
        for _, at in ipairs(spy.at) do
            if at >= tAim and at - tAim < dt + 1e-9 then hit = true end
        end
        assertTrue(hit, "an edge pass ran on the frame the aim floor passed")
    end)
end)

test("motion: the cycle end tears the script down on the frame it passes",
function()
    withClock(1000, function(box)
        local script = startBar(box, v2Tracker(box))
        local dt = 1 / 165
        local gone
        for i = 1, 400 do
            box[1] = 1000 + i * dt
            script(Swing.anchor, dt)
            if Swing.anchor:GetScript("OnUpdate") == nil then
                gone = box[1]
                break
            end
        end
        assertNotNil(gone, "the idle transition removes the script")
        assertTrue(gone >= 1002 - 1e-9 and gone - 1002 < dt + 1e-9,
            "idle landed " .. tostring(gone - 1002) .. " s after the end")
        assertFalse(Swing.anchor:IsShown())
    end)
end)

test("motion: an open retry window drains per frame and closes on time",
function()
    withClock(1000, function(box)
        local t = v2Tracker(box)
        local script = startBar(box, t)
        t.retryUntil = 1000.3                        -- a FAILED_QUIET penalty
        box[1] = 1000.0 + 1 / 165
        Swing:Update(box[1])                         -- the edge sees it
        assertTrue(Swing._retryW > 0)
        local spy = spyUpdate()
        local dt = 1 / 165
        local prev = Swing._retryW
        local closed
        for i = 2, 90 do
            box[1] = 1000 + i * dt
            script(Swing.anchor, dt)
            if box[1] < 1000.3 then
                assertTrue(Swing._retryW <= prev,
                    "the retry slice must drain, frame " .. i)
                prev = Swing._retryW
            elseif not closed then
                closed = box[1]
                assertEquals(0, Swing._retryW)
            end
        end
        spy.stop()
        assertNotNil(closed)
        local hit = false
        for _, at in ipairs(spy.at) do
            if at >= 1000.3 and at - 1000.3 < dt + 1e-9 then hit = true end
        end
        assertTrue(hit, "the retry deadline requested its edge pass")
    end)
end)

-- --------------------------------------------------- (4) idle: no script --
test("motion: no OnUpdate while idle or hidden; installed again with the motion",
function()
    withClock(1000, function(box)
        local t = v2Tracker(box)
        startBar(box, t)
        Swing:RenderIdle()
        assertNil(Swing.anchor:GetScript("OnUpdate"))
        assertFalse(Swing.anchor:IsShown())
        -- Idle: a motion pass is a no-op (no cache, nothing on screen).
        Swing:_MotionPass(1000.5)
        assertFalse(Swing.anchor:IsShown())
        -- Motion starts again: the script comes back.
        t:OnSwingStart(2.0, 2)
        Swing:Kick()
        assertNotNil(Swing.anchor:GetScript("OnUpdate"))
        -- The tracker going idle by itself removes it again.
        box[1] = 1003
        Swing:Update(box[1])
        assertNil(Swing.anchor:GetScript("OnUpdate"))
    end)
end)

-- ------------------------------------------------------ (5) no allocation --
test("motion: 1000 motion passes allocate nothing (everything moving)", function()
    local weaveWas = FX.Hunter.Swing.state.showWeaveLine
    withClock(1000, function(box)
        -- `one` mode with an open retry: the fill, the spark, the retry
        -- slice, the clip stripe and the weave line ALL travel.
        Swing:SetBarMode("one")
        Swing:SetShowWeaveLine(true)
        local t = v2Tracker(box, { baseSpeed = 3.0 })   -- aim 0.5 s on a 3.0 s cycle
        local script = startBar(box, t, 3.0)
        t.retryUntil = 1000.5
        box[1] = 1000.001
        Swing:Update(box[1])
        local function measure()
            collectgarbage("collect")
            collectgarbage("stop")
            local before = collectgarbage("count")
            for i = 1, 1000 do
                box[1] = 1000.001 + i * 5e-5         -- < 0.1 s: no edge pass
                script(Swing.anchor, 5e-5)
            end
            local after = collectgarbage("count")
            collectgarbage("restart")
            return after - before
        end
        local fill0, retry0, weave0, clip0 =
            Swing._fillW, Swing._retryW, Swing._weaveX, Swing._clipW
        assertNotNil(weave0, "the weave line is on the bar")
        local real = measure()
        check(Swing._fillW ~= fill0, "the fill moved " .. tostring(fill0))
        check(Swing._retryW ~= retry0, "the retry slice moved " .. tostring(retry0))
        check(Swing._weaveX ~= weave0, "the weave line moved " .. tostring(weave0))
        check(Swing._clipW ~= clip0, "the clip stripe moved " .. tostring(clip0))
        -- The same passes over inert widgets: what OUR Lua allocates.
        local noop = function() end
        local stub = setmetatable({}, { __index = function() return noop end })
        local keep = {}
        for _, k in ipairs({ "fill", "spark", "aim", "retry", "cast",
            "aimRegion", "clip", "clipBand", "weave" }) do
            keep[k] = Swing[k]
            Swing[k] = stub
        end
        local ours = measure()
        for k, v in pairs(keep) do Swing[k] = v end
        if real > 0 or ours > 0 then
            error("motion passes allocated: real widgets " .. tostring(real)
                .. " KB, inert widgets " .. tostring(ours) .. " KB")
        end
    end)
    Swing:SetShowWeaveLine(weaveWas)
end)

-- ------------------------------------------- (6) motion pass == edge pass --
test("motion: the motion pass and the edge pass give the same position", function()
    for _, mode in ipairs({ "safe", "one", "elapsed" }) do
        withClock(1000, function(box)
            Swing:SetBarMode(mode)
            local t = v2Tracker(box)
            local script = startBar(box, t)
            local dt = 1 / 165
            for i = 1, 40 do
                box[1] = 1000 + i * dt
                script(Swing.anchor, dt)
            end
            local at = box[1]
            -- No edge pass fell on this frame's instant if the cadence says
            -- so; take the motion reading, then force the edge at the SAME
            -- instant and compare.
            Swing:_MotionPass(at)
            local w, x = Swing._fillW, Swing._sparkX
            Swing:Update(at)
            near(Swing._fillW, w, 1e-9)
            near(Swing._sparkX, x, 1e-9)
            near(Swing._fillIntent, w, 1e-9)
        end)
    end
end)

test("motion: the flight's spark alpha ramps down every frame (Spark2 pulse)",
function()
    withClock(1000, function(box)
        local t = v2Tracker(box)
        local script = startBar(box, t)
        local dt = 1 / 165
        local frames = 0
        local ramp
        for i = 1, 200 do
            box[1] = 1000 + i * dt
            if box[1] >= 1000.7 and not t._startSent then
                t._startSent = true
                t:OnShotCast("START", "Auto Shot", 75, "G1")
            elseif box[1] >= 1000.8 and not t._flightSent then
                t._flightSent = true
                t:OnShotCast("SUCCEEDED", "Auto Shot", 75, "G1")
            end
            script(Swing.anchor, dt)
            if Swing._phase == "flying" and Swing._sparkAt then
                ramp = ramp or {}
                ramp[#ramp + 1] = Swing._sparkA
                if #ramp >= 60 then break end
            end
        end
        assertNotNil(ramp, "the proven flight was drawn")
        assertTrue(#ramp >= 60)
        assertTrue(ramp[1] > 0.9)
        for i = 2, #ramp do
            near(ramp[i - 1] - ramp[i], dt / S.PulseSeconds, 1e-6)
        end
        -- The whole bar rides white in the flight and the head sits at W.
        near(Swing._fillW, S.Width)
        near(Swing._sparkX, S.Width)
        frames = #ramp
        assertTrue(frames > 0)
    end)
end)

-- ------------------------------------------- the engine path, not doubled --
test("motion: with the engine fill the per-frame pass leaves the fill alone and moves the spark",
function()
    withClock(1000, function(box)
        Swing:Init()
        Swing:SetFillEngineMode("engine")
        if not Swing:UsesEngineFill() then
            print("[motion] this build has no engine fill; leg skipped")
            return
        end
        local log = Swing:FillLog(true)
        local script = startBar(box, v2Tracker(box))
        local armed = #log
        assertTrue(armed >= 1, "the cycle edge armed the engine fill")
        local dt = 1 / 165
        local prevX = Swing._sparkX
        for i = 1, 40 do
            box[1] = 1000 + i * dt
            script(Swing.anchor, dt)
            assertTrue(Swing._sparkX ~= prevX, "the spark moves every frame")
            prevX = Swing._sparkX
        end
        -- Only edge-pass re-arms (one per state edge), never a per-frame one.
        assertTrue(#log - armed <= 1,
            "engine arms in 40 frames: " .. tostring(#log - armed))
        assertNil(Swing._fillW, "the lua fill was never sized per frame")
        Swing:FillLog(nil)
    end)
end)

-- ---------------------------------------------------------- the melee rail --
local function restoreRail()
    Melee:SetTracker(MeleeCore.Tracker)
    Melee:SetMeter(FX.Hunter.RangeMeter)
    Melee.combatReader = nil
    Melee:SetEnabled(false)
    RangeLight:SetEnabled(false)
    MeleeCore:DisableEvents()
end

test("motion: the melee rail's fill moves every frame; its gate/text stay at 10 Hz",
function()
    local saved = _G.GetTime
    local box = { 4000 }
    _G.GetTime = function() return box[1] end
    local ok, err = pcall(function()
        Swing:Init()
        RangeLight:Init()
        local t = FX.Hunter.NewMeleeTracker({
            now = function() return box[1] end, mainHandType = 0 })
        Melee:SetTracker(t)
        Melee.combatReader = function() return true end
        Melee:SetEnabled(true)
        t:OnSwingStart(2.0, 0)
        assertTrue(Melee:Refresh())
        local script = Melee.anchor:GetScript("OnUpdate")
        assertNotNil(script)
        local refreshes, real = 0, Melee.Refresh
        Melee.Refresh = function(self, ...)
            refreshes = refreshes + 1
            return real(self, ...)
        end
        local dt = 1 / 165
        local prev, step = Melee._fillW, nil
        near(prev, 0)
        for i = 1, 165 do
            box[1] = 4000 + i * dt
            script(Melee.anchor, dt)
            local w = Melee._fillW
            assertTrue(w > prev, "frame " .. i .. " did not move the rail")
            if step then near(w - prev, step, 1e-6) end
            step = w - prev
            prev = w
        end
        Melee.Refresh = real
        near(prev, Melee._w * 0.5, 1e-6)             -- 1 s of 2.0 s
        assertTrue(refreshes >= 9 and refreshes <= 11,
            "gate passes over 1 s: " .. refreshes)
        -- Same instant, either pass.
        local w0 = Melee._fillW
        Melee:Refresh()
        near(Melee._fillW, w0, 1e-9)
        -- Past the end the rail stays full and the script is still the same
        -- split (full = ready).
        box[1] = 4003
        script(Melee.anchor, 0.2)
        near(Melee._fillW, Melee._w)
        -- Idle: hidden, script gone.
        t:Reset()
        assertFalse(Melee:Refresh())
        assertNil(Melee.anchor:GetScript("OnUpdate"))
    end)
    _G.GetTime = saved
    restoreRail()
    assertEquals("ok", ok and "ok" or tostring(err))
end)

-- --------------------------------------------------- the aspect reminder --
test("motion: the reminder's pulse is computed every frame; Missing() stays at 10 Hz",
function()
    local saved = _G.GetTime
    local box = { 2000 }
    _G.GetTime = function() return box[1] end
    local aspects = Reminder.Aspects
    local ok, err = pcall(function()
        if not Reminder.anchor then Reminder:Init() end
        local fake = FX.Hunter.NewAspectTracker({
            names = Tools.aspectNames,
            inCombat = function() return false end,
        })
        local reads = 0
        local realMissing = fake.Missing
        fake.Missing = function(self, ...)
            reads = reads + 1
            return realMissing(self, ...)
        end
        Reminder:HideNow()
        Reminder:SetAspects(fake)
        assertTrue(Reminder:Refresh())
        assertTrue(Reminder.anchor:IsShown())
        local script = Reminder.anchor:GetScript("OnUpdate")
        assertNotNil(script)
        reads = 0
        local t0 = Reminder._anchor0
        local dt = 1 / 165
        local prev
        local moved = 0
        for i = 1, 165 do
            box[1] = 2000 + i * dt
            script(Reminder.anchor, dt)
            local phase = (box[1] - t0) / RS.PulsePeriod
            local wave = (1 - math.cos(phase * 2 * math.pi)) * 0.5
            local expect = RS.PulseMin + (RS.PulseMax - RS.PulseMin) * wave
            near(Reminder._alpha, expect, 1e-9)
            if prev and Reminder._alpha ~= prev then moved = moved + 1 end
            prev = Reminder._alpha
        end
        assertTrue(moved >= 160, "the pulse changed on " .. moved .. " of 164 frames")
        assertTrue(reads >= 9 and reads <= 11,
            "tracker reads over 1 s at 165 fps: " .. reads)
        -- The self-heal still lands within the slow cadence: an aspect worn
        -- hides it, the script goes away.
        fake:OnCast("Aspect of the Hawk")
        for i = 1, 20 do
            box[1] = box[1] + dt
            script(Reminder.anchor, dt)
        end
        assertFalse(Reminder.anchor:IsShown())
        assertNil(Reminder.anchor:GetScript("OnUpdate"))
    end)
    _G.GetTime = saved
    Reminder:HideNow()
    Reminder:SetAspects(aspects)
    assertEquals("ok", ok and "ok" or tostring(err))
end)
