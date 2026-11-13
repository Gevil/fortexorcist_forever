-- dev/Forte_Dev/tests/test_motion.lua
-- The motion suite (Suites/Motion.lua) against a STUBBED frame stream and clock: the simulator delivers no
-- OnUpdate and no C_Timer callback inside a test, so every frame and every timer is fired by hand through
-- the suite's seams (M.after / M.newDriver / M.buildTargets / M.testMode). What this pins: the pacing and
-- ratio maths, the demo state restore, the combat refusal, the skips (module missing / disabled / no rows),
-- the idle-script wait, the per-frame no-allocation law and the real observers against the sim's displays.
-- What only the real client can tell: whether OnUpdate really fires every frame, the true frame times and
-- whether the widgets' read-back values really change (see dev/README.md).

local FX = ForteXorcist
local Dev = FX.Dev
local S = Dev.Selftest
local M = Dev.Motion

local REAL_NEW_DRIVER = M.newDriver
local REAL_LOADED_FORTE = M.loadedForteAddOns
local SEAMS = { "after", "newDriver", "buildTargets", "testMode", "getFramerate", "profilerApi", "loadedForteAddOns" }

-- ------------------------------------------------------------- scaffolding --

local function sandbox()
    local saved = { db = _G.ForteDevDB, after = Dev.After, combat = _G.InCombatLockdown, suites = Dev.suites,
        secret = _G.issecretvalue, state = {}, seams = {} }
    for k, v in pairs(Dev.state) do saved.state[k] = v end
    for _, k in ipairs(SEAMS) do saved.seams[k] = M[k] end
    _G.ForteDevDB = nil
    Dev.InitDB()
    for k in pairs(Dev.state) do Dev.state[k] = nil end
    Dev.state.panelOn = true
    local env = { timers = {}, drivers = 0, stops = 0, onFrame = nil }
    Dev.After = function(sec, fn) env.timers[#env.timers + 1] = { sec = sec, fn = fn } end
    _G.InCombatLockdown = function() return false end
    M.newDriver = function(onFrame)
        env.onFrame = onFrame
        env.drivers = env.drivers + 1
        return { Stop = function()
            env.stops = env.stops + 1
            env.onFrame = nil
        end }
    end
    M.getFramerate = function() return 144.5 end
    M.profilerApi = function() return nil, nil end              -- no profiler unless a test installs one
    M.loadedForteAddOns = function() return {} end
    --- Fire the first pending timer armed with `sec` seconds.
    function env.fire(sec)
        for i, t in ipairs(env.timers) do
            if t.sec == sec then
                table.remove(env.timers, i)
                t.fn()
                return true
            end
        end
        return false
    end
    return env, function()
        _G.ForteDevDB = saved.db
        Dev.After = saved.after
        _G.InCombatLockdown = saved.combat
        _G.issecretvalue = saved.secret
        Dev.suites = saved.suites
        for _, k in ipairs(SEAMS) do M[k] = saved.seams[k] end
        for k in pairs(Dev.state) do Dev.state[k] = nil end
        for k, v in pairs(saved.state) do Dev.state[k] = v end
        Dev.Repaint()
    end
end

local function motionSuite()
    for _, s in ipairs(Dev.suites) do
        if s.name == "motion" then return s end
    end
end

local function find(run, name)
    for _, t in ipairs(run.tests) do
        if t.name == name then return t end
    end
end

--- A TestMode stand-in: IsActive / Start / Stop with call counters; `refuse` makes Start answer false.
local function stubTM(active)
    local tm = { active = active or false, starts = 0, stops = 0 }
    function tm:IsActive() return self.active end
    function tm:Start()
        if self.refuse then return false, "combat" end
        self.active = true
        self.starts = self.starts + 1
        return true, "on"
    end
    function tm:Stop(why)
        if not self.active then return false, "off" end
        self.active = false
        self.stops = self.stops + 1
        self.why = why
        return true, why
    end
    return tm
end

--- A display stand-in with ONE element whose value the test moves (`x.v`). o.unavailable = reason,
--- o.rows = row count (default 3), o.scriptGoneAfter = hasScript answers true that many times, then false
--- (nil = the script never goes away).
local function stubTarget(key, o)
    o = o or {}
    local x, polls = { v = 0 }, 0
    local t = { key = key, x = x }
    function t.available()
        if o.unavailable then return false, o.unavailable end
        return true
    end
    function t.rows() return o.rows or 3 end
    function t.hasScript()
        polls = polls + 1
        if o.scriptGoneAfter and polls > o.scriptGoneAfter then return false end
        return true
    end
    t.observer = {
        count = function() return 1 end,
        read = function() return x.v, 0, x end,
        label = function() return "stub x" end,
    }
    return t
end

--- Drive one whole suite run with stubbed timers/frames. `feed()` is called when the sampler's OnUpdate
--- exists (after the warm-up timer); the pacing window gets 20 frames of 1/165 s. `beforeWarm()` runs
--- once the demo has been started and just before the warm-up timer fires.
local function drive(env, feed, stopAt, beforeWarm)
    local run, pending = S.RunList({ motionSuite() }, "motion")
    if env.onFrame then
        for _ = 1, 20 do env.onFrame(1 / 165) end
    end
    env.fire(M.PACING_SECONDS)
    if beforeWarm then beforeWarm() end
    env.fire(M.WARM_SECONDS)
    if env.onFrame and feed then feed() end
    if stopAt == "timeout" then
        env.fire(M.WINDOW_TIMEOUT)
    else
        env.fire(M.SAMPLE_SECONDS)
    end
    local guard = 0
    while Dev.state.running and guard < 100 do
        guard = guard + 1
        if not env.fire(M.IDLE_POLL_SECONDS) then break end
    end
    return run, pending
end

local function allTargets(cd, tmr, sw)
    return function() return { cd, tmr, sw } end
end

local NAMES = M.TEST_NAMES

-- ------------------------------------------------------------ pacing maths --

test("pacing: frames, mean fps, min / 95th percentile / max frame ms from bucket counts", function()
    local p = M.NewPacing()
    for _ = 1, 94 do M.PacingAdd(p, 0.006) end
    for _ = 1, 6 do M.PacingAdd(p, 0.020) end
    local n, fps, mn, p95, mx = M.PacingStats(p)
    assertEquals(100, n)
    assertTrue(math.abs(fps - 100 / (94 * 0.006 + 6 * 0.020)) < 1e-6, "fps " .. fps)
    assertTrue(math.abs(mn - 6) < 1e-9, "min " .. mn)
    assertTrue(math.abs(mx - 20) < 1e-9, "max " .. mx)
    assertTrue(math.abs(p95 - 20) < 1e-9, "p95 reaches the slow 6%: " .. p95)

    local q = M.NewPacing()
    for _ = 1, 96 do M.PacingAdd(q, 0.006) end
    for _ = 1, 4 do M.PacingAdd(q, 0.020) end
    local _, _, _, p95b = M.PacingStats(q)
    assertTrue(p95b > 5.9 and p95b <= 6.5, "p95 stays in the fast bucket when only 4% are slow: " .. p95b)

    local empty = M.PacingStats(M.NewPacing())
    assertEquals(0, empty)
end)

test("pacing: a hitch beyond the histogram lands in the overflow bucket; max stays exact", function()
    local p = M.NewPacing()
    for _ = 1, 99 do M.PacingAdd(p, 0.005) end
    M.PacingAdd(p, 0.75)
    local n, _, _, _, mx = M.PacingStats(p)
    assertEquals(100, n)
    assertTrue(math.abs(mx - 750) < 1e-6, "max " .. mx)
    assertEquals(1, p.b[M.BUCKETS + 1])
end)

test("no table growth per frame: pacing and sampler frames allocate nothing", function()
    local p = M.NewPacing()
    local x = { v = 0 }
    local s = M.NewSampler({ count = function() return 2 end,
        read = function(i) return x.v + i, 0, x end, label = function() return "n" end })
    for i = 1, 200 do M.PacingAdd(p, 0.006 + (i % 5) * 0.001); x.v = i; M.SamplerFrame(s, 0.006) end
    collectgarbage("collect")
    collectgarbage("collect")
    local c0 = collectgarbage("count")
    for i = 1, 20000 do
        M.PacingAdd(p, 0.006 + (i % 7) * 0.001)
        x.v = i
        M.SamplerFrame(s, 0.006)
    end
    local c1 = collectgarbage("count")
    assertTrue(c1 - c0 < 2, string.format("heap grew %.1f KB over 20000 frames", c1 - c0))
    assertEquals(20200, p.n)
end)

-- ------------------------------------------------------------- ratio maths --

local function stream(frames, moves)
    local x = { v = 0 }
    local s = M.NewSampler({ count = function() return 1 end, read = function() return x.v, 0, x end,
        label = function() return "stub" end })
    for i = 1, frames do
        if moves(i) then x.v = x.v + 1 end
        M.SamplerFrame(s, 1 / 164)
    end
    return s
end

test("ratio: every frame moves -> pass with ratio 1; the first frame has no previous and is not compared", function()
    local s = stream(100, function() return true end)
    local status, ratio, detail = M.Verdict(s)
    assertEquals("pass", status)
    assertEquals(1, ratio)
    assertEquals("moved 99/99 frames (1.00) via stub fps 164", detail)
end)

test("ratio: every 3rd frame moves -> fail with ratio 0.33", function()
    local s = stream(100, function(i) return i % 3 == 0 end)
    local status, ratio, detail = M.Verdict(s)
    assertEquals("fail", status)
    assertTrue(math.abs(ratio - 33 / 99) < 1e-9, tostring(ratio))
    assertTrue(detail:find("moved 33/99 frames (0.33)", 1, true) ~= nil, detail)
end)

test("ratio: 243 of 247 comparable frames is the spec's 0.98 pass, and the threshold is inclusive at 0.9", function()
    local miss = { [10] = true, [90] = true, [150] = true, [200] = true }
    local s = stream(248, function(i) return not miss[i] end)
    local status, _, detail = M.Verdict(s)
    assertEquals("pass", status)
    assertEquals("moved 243/247 frames (0.98) via stub fps 164", detail)
    -- exactly 9 of 10 comparable frames
    local edge = stream(11, function(i) return i ~= 5 end)
    local st2, ratio2 = M.Verdict(edge)
    assertEquals("pass", st2)
    assertTrue(math.abs(ratio2 - 0.9) < 1e-9, tostring(ratio2))
    local under = stream(11, function(i) return i ~= 5 and i ~= 6 end)
    assertEquals("fail", (M.Verdict(under)))
end)

test("ratio: the best of several elements counts (parked rows do not move), an identity change is not a move", function()
    local a, b, c = { v = 0 }, { v = 0 }, { v = 0 }
    local rebound = 0
    local els = { a, b, c }
    local s = M.NewSampler({
        count = function() return 3 end,
        read = function(i) return els[i].v, 0, (i == 3) and { rebound } or els[i] end,   -- element 3: new identity each frame
        label = function(i) return "el" .. i end,
    })
    for i = 1, 60 do
        b.v = b.v + 1                       -- element 2 moves on every frame
        if i % 3 == 0 then a.v = a.v + 1 end
        c.v = c.v + 1
        M.SamplerFrame(s, 1 / 120)
    end
    local best, changed, compared = M.Best(s)
    assertEquals(2, best)
    assertEquals(59, changed)
    assertEquals(59, compared)
    assertEquals(0, s.compared[3], "a rebound identity is never compared")
    assertEquals("pass", (M.Verdict(s)))
end)

test("ratio: nothing readable on two frames in a row -> 'none'", function()
    local s = M.NewSampler({ count = function() return 1 end, read = function() return nil end,
        label = function() return "x" end })
    for _ = 1, 10 do M.SamplerFrame(s, 0.01) end
    local status, ratio, detail = M.Verdict(s)
    assertEquals("none", status)
    assertEquals(nil, ratio)
    assertTrue(detail:find("no element could be read", 1, true) ~= nil, detail)
end)

-- ------------------------------------------------------------ the real driver --

test("driver: a shown, anchored 1x1 frame whose OnUpdate passes a plain elapsed (a secret becomes nil), Stop removes it", function()
    local _, restore = sandbox()
    local seen = {}
    local d = REAL_NEW_DRIVER(function(e) seen[#seen + 1] = e == nil and "nil" or e end)
    local f = M.frame
    local shown, w, h, np = f:IsShown(), f:GetWidth(), f:GetHeight(), f:GetNumPoints()
    local script = f:GetScript("OnUpdate")
    _G.issecretvalue = function(v) return v == 5 end
    if script then
        script(f, 0.01)
        script(f, 5)
        script(f, "x")
    end
    d.Stop()
    local goneScript, goneShown = f:GetScript("OnUpdate"), f:IsShown()
    restore()
    assertEquals(true, shown)
    assertTrue(math.abs(w - 1) < 0.01 and math.abs(h - 1) < 0.01, "1x1: " .. w .. "x" .. h)
    assertEquals(1, np)
    assertNotNil(script)
    assertEquals(0.01, seen[1])
    assertEquals("nil", seen[2], "a secret elapsed is dropped")
    assertEquals("nil", seen[3], "a non-number elapsed is dropped")
    assertNil(goneScript)
    assertEquals(false, goneShown)
end)

-- ------------------------------------------------------------ the whole suite --

test("suite: pacing, all three displays and CPU report; every frame moving passes, every 3rd frame failing fails", function()
    local env, restore = sandbox()
    local tm = stubTM(false)
    M.testMode = function() return tm end
    local cd = stubTarget("cooldown", { scriptGoneAfter = 2 })
    local tmr = stubTarget("timer", { scriptGoneAfter = 0 })
    local sw = stubTarget("swing", { unavailable = "not a Hunter (class PALADIN)" })
    M.buildTargets = allTargets(cd, tmr, sw)
    local run, pending = drive(env, function()
        for i = 1, 100 do
            cd.x.v = cd.x.v + 1
            if i % 3 == 0 then tmr.x.v = tmr.x.v + 1 end
            env.onFrame(1 / 165)
        end
    end)
    local running, finished = Dev.state.running, Dev.state.finished
    restore()
    assertEquals(true, pending, "the run was pending when RunList returned")
    assertEquals(false, running)
    assertEquals(true, finished)
    local pace = find(run, "motion: frame pacing")
    assertEquals("pass", pace.status)
    assertTrue(pace.detail:find("20 frames", 1, true) ~= nil and pace.detail:find("GetFramerate 144.5", 1, true) ~= nil,
        pace.detail)
    assertTrue(#pace.detail <= Dev.DETAIL_MAX)
    local c = find(run, NAMES.cooldown)
    assertEquals("pass", c.status, c.detail)
    assertTrue(c.detail:find("moved 99/99 frames (1.00)", 1, true) ~= nil, c.detail)
    assertTrue(c.detail:find("idle script removed: yes", 1, true) ~= nil, c.detail)
    local t = find(run, NAMES.timer)
    assertEquals("fail", t.status)
    assertTrue(t.detail:find("(0.33)", 1, true) ~= nil, t.detail)
    local s = find(run, NAMES.swing)
    assertEquals("skip", s.status)
    assertTrue(s.detail:find("not a Hunter", 1, true) ~= nil, s.detail)
    local cpu = find(run, "motion: addon CPU")
    assertEquals("skip", cpu.status)
    assertTrue(cpu.detail:find("C_AddOnProfiler is absent", 1, true) ~= nil, cpu.detail)
    assertEquals(nil, find(run, "motion: demo window"), "the window records nothing when it works")
    assertEquals(1, tm.starts)
    assertEquals(1, tm.stops)
    assertEquals(2, env.drivers, "one pacing driver, one shared sampling driver")
    assertEquals(2, env.stops)
end)

test("suite: the shared window reads every display from ONE frame stream, so each sees the same frames", function()
    local env, restore = sandbox()
    M.testMode = function() return stubTM(false) end
    local a = stubTarget("cooldown")
    local b = stubTarget("timer")
    local c = stubTarget("swing")
    M.buildTargets = allTargets(a, b, c)
    local run = drive(env, function()
        for _ = 1, 50 do
            a.x.v, b.x.v, c.x.v = a.x.v + 1, b.x.v + 1, c.x.v + 1
            env.onFrame(1 / 100)
        end
    end)
    restore()
    for _, key in ipairs(M.ORDER) do
        local t = find(run, NAMES[key])
        assertEquals("pass", t.status, key .. " " .. t.detail)
        assertTrue(t.detail:find("moved 49/49 frames", 1, true) ~= nil, key .. " " .. t.detail)
        assertTrue(t.detail:find("fps 100", 1, true) ~= nil, key .. " " .. t.detail)
    end
end)

test("suite: the demo state is restored -- stopped when the window started it, left on when it was already on", function()
    local env, restore = sandbox()
    local off = stubTM(false)
    local on = stubTM(true)
    M.buildTargets = function() return { stubTarget("cooldown", { scriptGoneAfter = 1 }), stubTarget("timer", { unavailable = "x" }),
        stubTarget("swing", { unavailable = "y" }) } end
    local function feed() for _ = 1, 10 do env.onFrame(1 / 60) end end
    M.testMode = function() return off end
    local runOff = drive(env, feed)
    local offAfter = { active = off.active, starts = off.starts, stops = off.stops, why = off.why }
    env.timers = {}
    M.testMode = function() return on end
    local runOn = drive(env, feed)
    local onAfter = { active = on.active, starts = on.starts, stops = on.stops }
    restore()
    assertEquals(false, offAfter.active, "the window started the demo and stopped it again")
    assertEquals(1, offAfter.starts)
    assertEquals(1, offAfter.stops)
    assertEquals("stopped", offAfter.why)
    assertTrue(find(runOff, NAMES.cooldown).detail:find("idle script removed: yes", 1, true) ~= nil,
        find(runOff, NAMES.cooldown).detail)
    assertEquals(true, onAfter.active, "an already-running demo is left running")
    assertEquals(0, onAfter.starts)
    assertEquals(0, onAfter.stops)
    assertTrue(find(runOn, NAMES.cooldown).detail:find("n/a (demo was already running)", 1, true) ~= nil,
        find(runOn, NAMES.cooldown).detail)
end)

test("suite: a window that never finishes times out, records a FAIL, stops the driver and puts the demo back", function()
    local env, restore = sandbox()
    local tm = stubTM(false)
    M.testMode = function() return tm end
    M.buildTargets = allTargets(stubTarget("cooldown"), stubTarget("timer"), stubTarget("swing"))
    local run = drive(env, function() env.onFrame(1 / 60) end, "timeout")
    local after = { active = tm.active, stops = tm.stops, running = Dev.state.running, onFrame = env.onFrame }
    restore()
    assertEquals(false, after.active, "the demo was stopped by the timeout cleanup")
    assertEquals(1, after.stops)
    assertEquals(nil, after.onFrame, "the sampling driver was stopped")
    assertEquals(false, after.running, "the run still ended")
    local w = find(run, "motion: demo window")
    assertEquals("fail", w.status)
    assertTrue(w.detail:find("timeout", 1, true) ~= nil, w.detail)
    assertEquals("skip", find(run, NAMES.cooldown).status)
    assertTrue(find(run, NAMES.cooldown).detail:find("did not complete", 1, true) ~= nil)
end)

test("suite: in combat nothing is started or touched; every display skips with the reason", function()
    local env, restore = sandbox()
    local tm = stubTM(false)
    M.testMode = function() return tm end
    M.buildTargets = allTargets(stubTarget("cooldown"), stubTarget("timer"), stubTarget("swing"))
    _G.InCombatLockdown = function() return true end
    local run = drive(env)
    local starts, drivers = tm.starts, env.drivers
    restore()
    assertEquals(0, starts, "the demo refuses in combat and the suite never asks")
    assertEquals(1, drivers, "only the pacing frame ran; no sampling frame")
    for _, key in ipairs(M.ORDER) do
        local t = find(run, NAMES[key])
        assertEquals("skip", t.status, key)
        assertTrue(t.detail:find("in combat", 1, true) ~= nil, t.detail)
    end
    assertEquals("pass", find(run, "motion: frame pacing").status, "the pacing probe touches no addon frame")
end)

test("suite: combat beginning inside the window discards the samples (test mode scrubs the demo itself)", function()
    local env, restore = sandbox()
    local tm = stubTM(false)
    M.testMode = function() return tm end
    M.buildTargets = allTargets(stubTarget("cooldown"), stubTarget("timer"), stubTarget("swing"))
    local run = drive(env, function()
        for _ = 1, 10 do env.onFrame(1 / 60) end
        _G.InCombatLockdown = function() return true end
        tm.active = false                      -- TestMode:OnEvent stops the demo on PLAYER_REGEN_DISABLED
    end)
    local stops = tm.stops
    restore()
    assertEquals(0, stops, "nothing left to stop")
    for _, key in ipairs(M.ORDER) do
        local t = find(run, NAMES[key])
        assertEquals("skip", t.status, key)
        assertTrue(t.detail:find("combat began", 1, true) ~= nil, t.detail)
    end
end)

test("suite: a refused demo start skips every display with the refusal", function()
    local env, restore = sandbox()
    local tm = stubTM(false)
    tm.refuse = true
    M.testMode = function() return tm end
    M.buildTargets = allTargets(stubTarget("cooldown"), stubTarget("timer"), stubTarget("swing"))
    local run = drive(env)
    local drivers = env.drivers
    restore()
    assertEquals(1, drivers, "no sampling frame")
    for _, key in ipairs(M.ORDER) do
        local t = find(run, NAMES[key])
        assertEquals("skip", t.status, key)
        assertTrue(t.detail:find("test mode did not start: combat", 1, true) ~= nil, t.detail)
    end
end)

test("suite: TestMode absent skips every display", function()
    local env, restore = sandbox()
    M.testMode = function() return nil end
    M.buildTargets = allTargets(stubTarget("cooldown"), stubTarget("timer"), stubTarget("swing"))
    local run = drive(env)
    restore()
    for _, key in ipairs(M.ORDER) do
        local t = find(run, NAMES[key])
        assertEquals("skip", t.status, key)
        assertTrue(t.detail:find("TestMode absent", 1, true) ~= nil, t.detail)
    end
end)

test("suite: a missing module skips ITS display with the reason and the others still run", function()
    local env, restore = sandbox()
    local tm = stubTM(false)
    M.testMode = function() return tm end
    local cd = stubTarget("cooldown")
    M.buildTargets = allTargets(cd, stubTarget("timer", { unavailable = "Forte_Timer display absent" }),
        stubTarget("swing", { unavailable = "not a Hunter (class MAGE)" }))
    local run = drive(env, function()
        for _ = 1, 20 do cd.x.v = cd.x.v + 1; env.onFrame(1 / 90) end
    end)
    restore()
    assertEquals("pass", find(run, NAMES.cooldown).status, find(run, NAMES.cooldown).detail)
    assertEquals("skip", find(run, NAMES.timer).status)
    assertTrue(find(run, NAMES.timer).detail:find("Forte_Timer display absent", 1, true) ~= nil)
    assertEquals("skip", find(run, NAMES.swing).status)
    assertEquals(1, tm.starts)
    assertEquals(1, tm.stops)
end)

test("suite: when every display is unavailable the demo is never started", function()
    local env, restore = sandbox()
    local tm = stubTM(false)
    M.testMode = function() return tm end
    M.buildTargets = allTargets(stubTarget("cooldown", { unavailable = "a" }), stubTarget("timer", { unavailable = "b" }),
        stubTarget("swing", { unavailable = "c" }))
    local run = drive(env)
    local starts = tm.starts
    restore()
    assertEquals(0, starts)
    assertEquals("a", find(run, NAMES.cooldown).detail)
    assertEquals("b", find(run, NAMES.timer).detail)
    assertEquals("c", find(run, NAMES.swing).detail)
end)

test("suite: no rows after the warm-up skips that display, restores the demo and drives no sampler for it", function()
    local env, restore = sandbox()
    local tm = stubTM(false)
    M.testMode = function() return tm end
    M.buildTargets = allTargets(stubTarget("cooldown", { rows = 0 }), stubTarget("timer", { rows = 0 }),
        stubTarget("swing", { rows = 0 }))
    local run = drive(env)
    local after = { active = tm.active, stops = tm.stops, drivers = env.drivers }
    restore()
    assertEquals(false, after.active)
    assertEquals(1, after.stops)
    assertEquals(1, after.drivers, "no sampling driver without any row")
    for _, key in ipairs(M.ORDER) do
        local t = find(run, NAMES[key])
        assertEquals("skip", t.status, key)
        assertTrue(t.detail:find("no rows after 0.5 s", 1, true) ~= nil, t.detail)
    end
end)

test("suite: an OnUpdate script that stays after the demo ended is reported 'no' after the bounded wait", function()
    local env, restore = sandbox()
    M.testMode = function() return stubTM(false) end
    local cd = stubTarget("cooldown")             -- the script never goes away (e.g. real cooldowns animate)
    M.buildTargets = allTargets(cd, stubTarget("timer", { unavailable = "x" }), stubTarget("swing", { unavailable = "y" }))
    local run = drive(env, function()
        for _ = 1, 20 do cd.x.v = cd.x.v + 1; env.onFrame(1 / 60) end
    end)
    local pollsLeft = 0
    for _, t in ipairs(env.timers) do if t.sec == M.IDLE_POLL_SECONDS then pollsLeft = pollsLeft + 1 end end
    restore()
    local c = find(run, NAMES.cooldown)
    assertEquals("pass", c.status, "idle is informational: it never fails the test")
    assertTrue(c.detail:find("idle script removed: no", 1, true) ~= nil, c.detail)
    assertEquals(0, pollsLeft, "the wait is bounded")
end)

test("suite: a raising availability probe is a skip; a raising observer is switched off and reported once", function()
    local env, restore = sandbox()
    M.testMode = function() return stubTM(false) end
    local bad = stubTarget("cooldown")
    bad.available = function() error("probe boom") end
    local broken = stubTarget("timer")
    local good = stubTarget("swing")
    local reads = 0
    broken.observer.read = function() reads = reads + 1; error("read boom") end
    M.buildTargets = allTargets(bad, broken, good)
    local run = drive(env, function()
        for _ = 1, 10 do
            good.x.v = good.x.v + 1
            env.onFrame(1 / 60)               -- the frame handler never raises
        end
    end)
    restore()
    local c = find(run, NAMES.cooldown)
    assertEquals("skip", c.status)
    assertTrue(c.detail:find("availability check raised", 1, true) ~= nil, c.detail)
    local t = find(run, NAMES.timer)
    assertEquals("fail", t.status)
    assertTrue(t.detail:find("observer raised: ", 1, true) ~= nil and t.detail:find("read boom", 1, true) ~= nil, t.detail)
    assertEquals(1, reads, "switched off after the first raise: no error every frame")
    assertEquals("pass", find(run, NAMES.swing).status, "the other displays are unaffected")
end)

test("suite: rows exist but nothing is readable -> FAIL (a broken observer is never a silent pass)", function()
    local env, restore = sandbox()
    M.testMode = function() return stubTM(false) end
    local unreadable = stubTarget("timer")
    unreadable.observer.read = function() return nil end
    M.buildTargets = allTargets(stubTarget("cooldown", { unavailable = "x" }), unreadable,
        stubTarget("swing", { unavailable = "y" }))
    local run = drive(env, function() for _ = 1, 5 do env.onFrame(1 / 60) end end)
    restore()
    local t = find(run, NAMES.timer)
    assertEquals("fail", t.status)
    assertTrue(t.detail:find("no element could be read", 1, true) ~= nil, t.detail)
end)

-- ---------------------------------------------------- the real displays (sim) --

test("real targets: a missing module skips with the reason and the demo is never started", function()
    local env, restore = sandbox()
    local tm = stubTM(false)
    M.testMode = function() return tm end
    local savedCD, savedTimer = FX.Cooldown, FX.Timer
    FX.Cooldown, FX.Timer = nil, nil
    local run = drive(env)
    FX.Cooldown, FX.Timer = savedCD, savedTimer
    local starts = tm.starts
    restore()
    assertEquals(0, starts)
    assertTrue(find(run, NAMES.cooldown).detail:find("Forte_Cooldown display/module absent", 1, true) ~= nil,
        find(run, NAMES.cooldown).detail)
    assertTrue(find(run, NAMES.timer).detail:find("Forte_Timer display absent", 1, true) ~= nil,
        find(run, NAMES.timer).detail)
    assertEquals("skip", find(run, NAMES.swing).status)
end)

test("real targets: a disabled module is reported as disabled", function()
    local enabled = FX._enabledModules
    local savedCD, savedTimer = enabled.Cooldown, enabled.Timer
    enabled.Cooldown, enabled.Timer = nil, nil
    local real = M.buildTargets()
    local okC, whyC = real[1].available()
    local okT, whyT = real[2].available()
    enabled.Cooldown, enabled.Timer = savedCD, savedTimer
    assertEquals(false, okC)
    assertEquals("Cooldown module disabled", whyC)
    assertEquals(false, okT)
    assertEquals("Timer module disabled", whyT)
end)

--- The Hunter swing display with a stand-in bar (the simulator has no Hunter add-on).
local function withSwing(engine, fn)
    local savedHunter, savedClass = FX.Hunter, FX._playerClass
    local savedFlag = FX._enabledModules.HunterUI
    local script = function() end
    local shown = true
    local anchor = { GetScript = function(_, k) return k == "OnUpdate" and script or nil end }
    local state = { x = 10, w = 20, v = 0.1 }
    local bar = {
        anchor = anchor,
        _shown = true,
        spark = { GetPoint = function() return "CENTER", anchor, "TOPLEFT", state.x, 6 end },
        fill = { GetWidth = function() return state.w end, GetValue = function() return state.v end },
        UsesEngineFill = function() return engine end,
    }
    local demo = { Live = function() return shown and 1 or 0 end }
    FX.Hunter = { Swing = bar, SwingDemo = demo }
    FX._playerClass = "HUNTER"
    FX._enabledModules.HunterUI = true
    local ok, err = pcall(fn, bar, state, function(v) script = v end, function(v) shown = v end)
    FX.Hunter, FX._playerClass, FX._enabledModules.HunterUI = savedHunter, savedClass, savedFlag
    if not ok then error(err, 0) end
end

test("real swing target: Lua fill = spark x + fill width; engine fill adds the fill value; rows need the demo", function()
    withSwing(false, function(bar, state, setScript, setDemoLive)
        local sw = M.buildTargets()[3]
        local ok = sw.available()
        assertEquals(true, ok)
        assertEquals(2, sw.observer.count(), "Lua path: spark x and fill width")
        local x, y, id = sw.observer.read(1)
        assertEquals(10, x)
        assertEquals(6, y)
        assertEquals(bar.spark, id)
        local w, _, id2 = sw.observer.read(2)
        assertEquals(20, w)
        assertEquals(bar.fill, id2)
        assertEquals("spark x", sw.observer.label(1))
        assertEquals(1, sw.rows())
        setDemoLive(false)
        assertEquals(0, sw.rows(), "no demo row -> not sampled")
        assertEquals(true, sw.hasScript(), "the bar's anchor carries an OnUpdate while the demo runs")
        setScript(nil)
        assertEquals(false, sw.hasScript(), "the idle script removal is read from the bar's anchor")
    end)
    withSwing(true, function()
        local sw = M.buildTargets()[3]
        assertEquals(3, sw.observer.count(), "engine path adds GetValue")
        local v = sw.observer.read(3)
        assertEquals(0.1, v)
        assertEquals("fill value", sw.observer.label(3))
    end)
end)

test("real swing target through the suite: a bar that moves every frame passes, one parked fails", function()
    local env, restore = sandbox()
    local tm = stubTM(false)
    M.testMode = function() return tm end
    local runs = {}
    withSwing(false, function(bar, state)
        local real = M.buildTargets
        M.buildTargets = function()
            local t = real()
            t[1].available = function() return false, "x" end
            t[2].available = function() return false, "y" end
            return t
        end
        runs.moving = drive(env, function()
            for _ = 1, 30 do
                state.x = state.x + 0.7
                env.onFrame(1 / 144)
            end
        end)
        env.timers = {}
        runs.parked = drive(env, function()
            for _ = 1, 30 do env.onFrame(1 / 144) end
        end)
    end)
    restore()
    local m = find(runs.moving, NAMES.swing)
    assertEquals("pass", m.status, m.detail)
    assertTrue(m.detail:find("via spark x", 1, true) ~= nil and m.detail:find("fps 144", 1, true) ~= nil, m.detail)
    local p = find(runs.parked, NAMES.swing)
    assertEquals("fail", p.status, p.detail)
    assertTrue(p.detail:find("moved 0/29 frames (0.00)", 1, true) ~= nil, p.detail)
end)

test("real observers: they read the live sim displays without raising; the Timer's motion counter is element 1", function()
    local _, restore = sandbox()
    local targets = M.buildTargets()
    local reads = {}
    for k, t in ipairs(targets) do
        local ok, n = pcall(t.observer.count)
        reads[k] = { ok = ok, n = n }
        if ok then
            for i = 1, n do
                local okR = pcall(t.observer.read, i)
                reads[k].ok = reads[k].ok and okR
                pcall(t.observer.label, i)
            end
        end
    end
    local D = FX.Timer and FX.Timer.Display
    local counts = D and D.counts
    local a, b, id = targets[2].observer.read(1)
    restore()
    for k = 1, 3 do
        assertTrue(reads[k].ok, "display " .. k .. " observer raised")
        assertEquals("number", type(reads[k].n))
    end
    if counts then
        assertEquals(counts.motionPass, a, "element 1 is the shipped motion-pass counter")
        assertEquals(counts, id)
        assertEquals(0, b)
    end
end)

test("real displays + real TestMode in the sim: demo started and stopped, the cooldown icons and the Timer counter move per frame", function()
    local env, restore = sandbox()
    local TM = FX.TestMode
    local TD = FX.Timer and FX.Timer.Display
    local CD = FX.Cooldown and FX.Cooldown.Display
    local CM = FX.Cooldown and FX.Cooldown.Module
    if not (TM and TD and TD.MotionPass and TD.counts and CD and CD.Motion and CM and CM.RefreshDisplay) then
        restore()
        return
    end
    -- tripwires: the demo must never chat or touch gameplay
    local hits, saved = {}, {}
    for _, name in ipairs({ "SendChatMessage", "SendAddonMessage", "CastSpellByName", "TargetUnit", "UseAction" }) do
        saved[name] = _G[name]
        _G[name] = function() hits[#hits + 1] = name end
    end
    local wasActive = TM:IsActive()
    local base = _G.GetTime()
    local run = drive(env, function()
        for i = 1, 40 do
            pcall(TD.MotionPass, TD)                    -- what the Timer's OnUpdate does each frame
            pcall(CD.Motion, CD, base + i / 165)        -- what the Cooldown render frame does each frame
            env.onFrame(1 / 165)
        end
    end, nil, function()
        pcall(CM.RefreshDisplay, CM, base)              -- the simulator never ticks: one full pass puts rows on the bar
    end)
    local isActive = TM:IsActive()
    if TM:IsActive() and not wasActive then TM:Stop("stopped") end
    for name, fn in pairs(saved) do _G[name] = fn end
    restore()
    assertEquals(0, #hits, "tripwires hit: " .. table.concat(hits, ","))
    assertEquals(wasActive, isActive, "the demo state was put back")
    assertEquals(nil, find(run, "motion: demo window"), "the window itself did not fail")
    local t = find(run, NAMES.timer)
    assertEquals("pass", t.status, t.detail)
    assertTrue(t.detail:find("passes 39/39", 1, true) ~= nil, t.detail)
    local c = find(run, NAMES.cooldown)
    assertEquals("pass", c.status, c.detail)
    assertTrue(c.detail:find("via icon x", 1, true) ~= nil, c.detail)
    for _, key in ipairs(M.ORDER) do
        assertTrue(find(run, NAMES[key]).detail:find("^raise: ") == nil, key .. ": " .. find(run, NAMES[key]).detail)
    end
end)

-- ============================================================== addon CPU ==

--- A C_AddOnProfiler + Enum stand-in. `reading.addons[name]` are the values GetAddOnMetric answers for the
--- RecentAverageTime metric ONLY (id `recent`, deliberately not 1, so a wrong pick by position fails).
local function stubProfiler(o)
    o = o or {}
    local recent = o.recent or 7
    local reading = { addons = {} }
    local api = {
        IsEnabled = function()
            if o.raises then error("IsEnabled boom") end
            if o.enabled == nil then return true end
            return o.enabled
        end,
        GetAddOnMetric = function(name, metric)
            if metric ~= recent then return nil end
            return reading.addons[name]
        end,
        GetOverallMetric = function(metric) if metric == recent then return reading.overall end end,
        GetApplicationMetric = function(metric) if metric == recent then return reading.application end end,
        GetTicksPerSecond = function() return o.ticks or 1000000 end,
    }
    local enum = { AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = recent, LastTime = 3, PeakTime = 4 } }
    if o.noRecent then enum.AddOnProfilerMetric.RecentAverageTime = nil end
    return api, enum, reading
end

local function installProfiler(api, enum, names)
    M.profilerApi = function() return api, enum end
    M.loadedForteAddOns = function() return names or { "Forte_Core", "Forte_Cooldown", "Forte_Dev" } end
end

test("cpu probe: the metric is picked by NAME from the enumerated Enum, every missing piece is a SKIP with its reason", function()
    local _, restore = sandbox()
    local function why(api, enum)
        M.profilerApi = function() return api, enum end
        local ctx, reason = M.CpuProbe()
        return ctx, reason
    end
    local api, enum = stubProfiler({ recent = 7 })
    local ctx = why(api, enum)
    local picked = ctx and ctx.metric
    local ticks = ctx and ctx.ticks
    local _, noNs = why(nil, enum)
    local apiNoFn = { IsEnabled = api.IsEnabled }
    local _, noFn = why(apiNoFn, enum)
    local _, noEnum = why(api, nil)
    local _, noMetricTable = why(api, {})
    local a2, e2 = stubProfiler({ noRecent = true })
    local _, noRecent = why(a2, e2)
    local a3, e3 = stubProfiler({ enabled = false })
    local _, off = why(a3, e3)
    local a4, e4 = stubProfiler({ raises = true })
    local _, raised = why(a4, e4)
    _G.issecretvalue = function(v) return v == "SECRETBOOL" end
    local a5, e5 = stubProfiler({ enabled = "SECRETBOOL" })
    local _, secret = why(a5, e5)
    restore()
    assertEquals(7, picked, "RecentAverageTime, not the first member and not the Session one")
    assertEquals(1000000, ticks)
    assertEquals("C_AddOnProfiler is absent", noNs)
    assertEquals("C_AddOnProfiler.GetAddOnMetric is missing", noFn)
    assertEquals("Enum.AddOnProfilerMetric is missing", noEnum)
    assertEquals("Enum.AddOnProfilerMetric is missing", noMetricTable)
    assertEquals("Enum.AddOnProfilerMetric.RecentAverageTime is missing", noRecent)
    assertEquals("C_AddOnProfiler.IsEnabled() is false (profiler off)", off)
    assertTrue(raised:find("IsEnabled() raised", 1, true) ~= nil, raised)
    assertEquals("C_AddOnProfiler.IsEnabled() returned a secret value", secret)
end)

test("cpu: loaded Forte_ add-ons are enumerated through C_AddOns (prefix, loaded, table or multi-return info)", function()
    local _, restore = sandbox()
    local real = REAL_LOADED_FORTE
    local saved = _G.C_AddOns
    local names = { "Forte_Core", "Blizzard_X", "Forte_Dev", "Forte_Off", "ForteNot", { name = "Forte_Timer" } }
    local loaded = { Forte_Core = true, Forte_Dev = true, Forte_Timer = true, ForteNot = true }
    _G.C_AddOns = {
        GetNumAddOns = function() return #names end,
        GetAddOnInfo = function(i)
            local n = names[i]
            if type(n) == "table" then return n end
            return n, "title"
        end,
        IsAddOnLoaded = function(n) return loaded[n] and true or false, loaded[n] and true or false end,
    }
    local list = real()
    _G.C_AddOns = saved
    restore()
    assertEquals("Forte_Core,Forte_Dev,Forte_Timer", table.concat(list, ","))
end)

test("cpu: with a profiler the test reports idle / demo ms per frame, the percent of the frame, dev and totals, and stores the table", function()
    local env, restore = sandbox()
    local api, enum, reading = stubProfiler({ recent = 7 })
    installProfiler(api, enum)
    M.getFramerate = function() return 165 end
    reading.addons = { Forte_Core = 0.010, Forte_Cooldown = 0.002, Forte_Dev = 0.001 }
    local tm = stubTM(false)
    M.testMode = function() return tm end
    local cd = stubTarget("cooldown")
    M.buildTargets = allTargets(cd, stubTarget("timer", { unavailable = "x" }), stubTarget("swing", { unavailable = "y" }))
    local run = drive(env, function()
        for _ = 1, 10 do cd.x.v = cd.x.v + 1; env.onFrame(1 / 165) end
        -- the (b) reading is taken at the end of this window, with the demo running
        reading.addons = { Forte_Core = 0.080, Forte_Cooldown = 0.005, Forte_Dev = 0.030 }
        reading.overall, reading.application = 1.9, 2.4
    end)
    local stored = _G.ForteDevDB.runs[#_G.ForteDevDB.runs]
    restore()
    local c = find(run, "motion: addon CPU")
    assertEquals("pass", c.status, c.detail)
    assertEquals("FX idle 0.012 ms/frame, demo 0.085 ms/frame (1.4% of a 6.06 ms frame @165 fps); dev 0.030; all addons 1.9; app 2.4",
        c.detail)
    assertTrue(#c.detail <= Dev.DETAIL_MAX)
    local d = stored.motion and stored.motion.cpu
    assertNotNil(d, "run.motion.cpu is stored with the run")
    assertEquals("ms", d.unit)
    assertEquals("RecentAverageTime", d.metric)
    assertEquals(0.01, d.idle.Forte_Core)
    assertEquals(0.08, d.demo.Forte_Core)
    assertEquals(0.002, d.idle.Forte_Cooldown)
    assertEquals(nil, d.idle.Forte_Dev, "Forte_Dev is not part of the product numbers")
    assertEquals(0.012, d.product.idle)
    assertEquals(0.085, d.product.demo)
    assertEquals(0.03, d.dev.demo)
    assertEquals(0.001, d.dev.idle)
    assertEquals(1.9, d.overall)
    assertEquals(2.4, d.application)
    assertEquals(165, d.fps)
    assertEquals(1.4025, d.percent)
end)

test("cpu: the idle reading is taken BEFORE the demo starts, the demo reading while it is running", function()
    local env, restore = sandbox()
    local api, enum, reading = stubProfiler({ recent = 7 })
    installProfiler(api, enum, { "Forte_Core" })
    reading.addons = { Forte_Core = 1 }
    local tm = stubTM(false)
    local seen = {}
    local baseAfter = api.GetAddOnMetric
    api.GetAddOnMetric = function(name, metric)
        seen[#seen + 1] = (tm.active and "demo" or "idle") .. ":" .. (tm.starts == 0 and "never-started" or "started")
        return baseAfter(name, metric)
    end
    M.testMode = function() return tm end
    local cd = stubTarget("cooldown")
    M.buildTargets = allTargets(cd, stubTarget("timer", { unavailable = "x" }), stubTarget("swing", { unavailable = "y" }))
    drive(env, function() for _ = 1, 5 do cd.x.v = cd.x.v + 1; env.onFrame(1 / 60) end end)
    restore()
    assertEquals(2, #seen)
    assertEquals("idle:never-started", seen[1])
    assertEquals("demo:started", seen[2])
end)

test("cpu: the suite SKIPs with the probe's reason (profiler off) and with 'no demo reading' when the window took no sample", function()
    local env, restore = sandbox()
    local api, enum, reading = stubProfiler({ enabled = false })
    installProfiler(api, enum)
    M.testMode = function() return stubTM(false) end
    M.buildTargets = allTargets(stubTarget("cooldown"), stubTarget("timer"), stubTarget("swing"))
    local off = drive(env, function() env.onFrame(1 / 60) end)
    env.timers = {}
    local api2, enum2, reading2 = stubProfiler({})
    reading2.addons = { Forte_Core = 1 }
    installProfiler(api2, enum2, { "Forte_Core" })
    _G.InCombatLockdown = function() return true end             -- the window takes no sample in combat
    local combat = drive(env)
    restore()
    assertEquals("skip", find(off, "motion: addon CPU").status)
    assertEquals("C_AddOnProfiler.IsEnabled() is false (profiler off)", find(off, "motion: addon CPU").detail)
    assertEquals("skip", find(combat, "motion: addon CPU").status)
    assertTrue(find(combat, "motion: addon CPU").detail:find("no demo reading", 1, true) ~= nil,
        find(combat, "motion: addon CPU").detail)
end)

test("cpu: values that are secret or unreadable SKIP; a few unreadable add-ons do not stop the rest", function()
    local env, restore = sandbox()
    _G.issecretvalue = function(v) return v == 123 end
    local api, enum, reading = stubProfiler({ recent = 7 })
    installProfiler(api, enum, { "Forte_Core", "Forte_Cooldown" })
    reading.addons = { Forte_Core = 123, Forte_Cooldown = 123 }          -- 123 is "secret"
    local tm = stubTM(false)
    M.testMode = function() return tm end
    local cd = stubTarget("cooldown")
    M.buildTargets = allTargets(cd, stubTarget("timer", { unavailable = "x" }), stubTarget("swing", { unavailable = "y" }))
    local feed = function() for _ = 1, 5 do cd.x.v = cd.x.v + 1; env.onFrame(1 / 60) end end
    local allSecret = drive(env, feed)
    env.timers = {}
    reading.addons = { Forte_Core = 0.5, Forte_Cooldown = 123 }
    local partial = drive(env, feed)
    restore()
    local a = find(allSecret, "motion: addon CPU")
    assertEquals("skip", a.status)
    assertTrue(a.detail:find("secret or unreadable", 1, true) ~= nil, a.detail)
    local p = find(partial, "motion: addon CPU")
    assertEquals("pass", p.status, p.detail)
    assertTrue(p.detail:find("idle 0.500 ms/frame", 1, true) ~= nil, p.detail)
end)

test("cpu: no Forte_ add-on loaded -> SKIP", function()
    local env, restore = sandbox()
    local api, enum = stubProfiler({ recent = 7 })
    installProfiler(api, enum, {})
    M.testMode = function() return stubTM(false) end
    local cd = stubTarget("cooldown")
    M.buildTargets = allTargets(cd, stubTarget("timer", { unavailable = "x" }), stubTarget("swing", { unavailable = "y" }))
    local run = drive(env, function() env.onFrame(1 / 60) end)
    restore()
    assertEquals("skip", find(run, "motion: addon CPU").status)
end)

test("cpu: if the unit is ticks the value is converted through GetTicksPerSecond (and an unreadable frequency skips)", function()
    local _, restore = sandbox()
    local savedUnit = M.METRIC_UNIT
    M.METRIC_UNIT = "ticks"
    local api, enum, reading = stubProfiler({ recent = 7, ticks = 2000000 })
    installProfiler(api, enum, { "Forte_Core", "Forte_Dev" })
    reading.addons = { Forte_Core = 24000, Forte_Dev = 4000 }
    reading.overall = 100000
    local ctx = M.CpuProbe()
    local r = M.CpuRead(ctx)
    api.GetTicksPerSecond = function() return nil end
    local ctx2, why = M.CpuProbe()
    M.METRIC_UNIT = "ms"
    local ms = M.toMs(5, nil)
    M.METRIC_UNIT = savedUnit
    restore()
    assertEquals(2000000, ctx.ticks)
    assertEquals(12, r.product, "24000 ticks at 2 MHz = 12 ms")
    assertEquals(2, r.dev, "Forte_Dev 4000 ticks = 2 ms, reported apart")
    assertEquals(50, r.overall)
    assertEquals(nil, ctx2)
    assertTrue(why:find("GetTicksPerSecond", 1, true) ~= nil, why)
    assertEquals(5, ms, "ms values pass through unchanged")
end)

test("cpu: the percent maths and the clipped detail without fps, dev or totals", function()
    local detail, data = M.CpuSummary({ forte = { Forte_Core = 0.5 }, product = 0.5, read = 1, unreadable = 0 },
        { forte = { Forte_Core = 3 }, product = 3, read = 1, unreadable = 0 })
    assertEquals("FX idle 0.500 ms/frame, demo 3.000 ms/frame; dev n/a", detail)
    assertEquals(nil, data.percent)
    local d2, data2 = M.CpuSummary({ forte = {}, product = 0, read = 1, unreadable = 0 },
        { forte = { Forte_Core = 0.5 }, product = 0.5, dev = 0.1, fps = 100, read = 1, unreadable = 0 })
    assertEquals("FX idle 0.000 ms/frame, demo 0.500 ms/frame (5.0% of a 10.00 ms frame @100 fps); dev 0.100", d2)
    assertEquals(5, data2.percent)
end)
