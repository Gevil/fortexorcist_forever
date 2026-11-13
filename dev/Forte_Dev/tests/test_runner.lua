-- dev/Forte_Dev/tests/test_runner.lua
-- Runner semantics: pass/fail/skip, pcall isolation, caps, runId, ForteDevDB shape (PLAN §11.11),
-- suite selection (ooc / combat / all), combat gating, and the secret-safe store law.
-- Every leg swaps ForteDevDB / Dev.state / the globals it stubs and restores them.

local FX = ForteXorcist
local Dev = FX.Dev
local S = Dev.Selftest

local function sandbox(extra)
    local saved = { db = _G.ForteDevDB, after = Dev.After, combat = _G.InCombatLockdown,
        secret = _G.issecretvalue, suites = Dev.suites, frame = Dev.frame, state = {} }
    for k, v in pairs(Dev.state) do saved.state[k] = v end
    _G.ForteDevDB = nil
    Dev.InitDB()
    for k in pairs(Dev.state) do Dev.state[k] = nil end
    Dev.state.panelOn = true
    local timers = {}
    Dev.After = function(sec, fn) timers[#timers + 1] = { sec = sec, fn = fn } end
    return timers, function()
        _G.ForteDevDB = saved.db
        Dev.After = saved.after
        _G.InCombatLockdown = saved.combat
        _G.issecretvalue = saved.secret
        Dev.suites = saved.suites
        Dev.frame = saved.frame
        for k in pairs(Dev.state) do Dev.state[k] = nil end
        for k, v in pairs(saved.state) do Dev.state[k] = v end
        Dev.Repaint()
    end
end

local function suite(fn, name, group) return { name = name or "t", group = group or "ooc", fn = fn } end

local function find(run, name)
    for _, t in ipairs(run.tests) do
        if t.name == name then return t end
    end
end

test("pass / fail / skip are recorded, a raising body does not stop the next check", function()
    local _, restore = sandbox()
    local run = S.RunList({ suite(function(T)
        T.check("a", function() T.eq(1, 1) end)
        T.check("b", function() T.eq(1, 2, "num") end)
        T.check("c", function() T.skip("why") end)
        T.check("d", function() error("boom") end)
        T.check("e", function() T.truthy(true) end)
        T.check("f", function() local x = nil; return x.y end)
        T.check("g", function() T.falsy(1, "should be falsy") end)
        T.check("n", function() T.note("hello") end)
    end) }, "t")
    restore()
    assertEquals(2 + 1, run.pass)        -- a, e, n
    assertEquals(4, run.fail)            -- b, d, f, g
    assertEquals(1, run.skip)
    assertEquals(8, #run.tests)
    assertEquals("pass", find(run, "a").status)
    assertEquals("fail", find(run, "b").status)
    assertTrue(find(run, "b").detail:find("expected 2 got 1", 1, true) ~= nil, find(run, "b").detail)
    assertEquals("skip", find(run, "c").status)
    assertEquals("why", find(run, "c").detail)
    assertTrue(find(run, "d").detail:find("^raise: "), "raised errors are recorded as raise: ...")
    assertTrue(find(run, "f").detail:find("^raise: "), "a runtime error too")
    assertEquals("hello", find(run, "n").detail)
end)

test("a suite that raises outside any check is recorded and the next suite still runs", function()
    local _, restore = sandbox()
    local ran = false
    local run = S.RunList({
        suite(function() error("suite-level boom") end, "bad"),
        suite(function(T) ran = true; T.check("after", function() end) end, "good"),
    }, "t")
    restore()
    assertTrue(ran, "the second suite ran")
    assertEquals(1, run.fail)
    assertEquals(1, run.pass)
    assertTrue(find(run, "suite bad").detail:find("suite raised", 1, true) ~= nil)
end)

test("caps: failures recorded per run are bounded, the counts keep counting", function()
    local _, restore = sandbox()
    local run = S.RunList({ suite(function(T)
        for i = 1, 100 do T.check("f" .. i, function() T.fail("nope " .. i) end) end
    end) }, "t")
    restore()
    local failEntries = 0
    for _, t in ipairs(run.tests) do if t.status == "fail" then failEntries = failEntries + 1 end end
    assertEquals(100, run.fail)
    assertEquals(Dev.MAX_FAILS, failEntries)
    assertEquals(100 - Dev.MAX_FAILS, run.dropped)
end)

test("caps: total recorded entries are bounded; details are clipped", function()
    local _, restore = sandbox()
    local run = S.RunList({ suite(function(T)
        for i = 1, Dev.MAX_TESTS + 50 do T.check("p" .. i, function() end) end
        T.check(string.rep("n", 300), function() T.fail(string.rep("x", 500)) end)
    end) }, "t")
    restore()
    assertEquals(Dev.MAX_TESTS + 50, run.pass)
    assertEquals(1, run.fail)
    assertEquals(Dev.MAX_TESTS, #run.tests)
    assertEquals(51, run.dropped)
end)

test("clipping: long names and details are shortened in the stored entry", function()
    local _, restore = sandbox()
    local run = S.RunList({ suite(function(T)
        T.check(string.rep("n", 300), function() T.fail(string.rep("x", 500)) end)
    end) }, "t")
    restore()
    assertTrue(#run.tests[1].name <= Dev.NAME_MAX)
    assertTrue(#run.tests[1].detail <= Dev.DETAIL_MAX)
end)

test("runId increments per run; runs are capped at 5, newest last", function()
    local _, restore = sandbox()
    local empty = { suite(function() end) }
    local ids = {}
    for i = 1, 7 do ids[i] = S.RunList(empty, "t").id end
    local db = _G.ForteDevDB
    local runs = db.runs
    local runId = db.runId
    restore()
    assertEquals(1, ids[1])
    assertEquals(7, ids[7])
    assertEquals(7, runId)
    assertEquals(Dev.MAX_RUNS, #runs)
    assertEquals(3, runs[1].id)
    assertEquals(7, runs[#runs].id)
end)

test("ForteDevDB has the contract shape", function()
    local _, restore = sandbox()
    S.RunList({ suite(function(T)
        T.check("p", function() end)
        T.check("f", function() T.fail("x") end)
        T.check("s", function() T.skip("y") end)
    end) }, "ooc")
    Dev.RecordCommand("status", true, "fine")
    local db = _G.ForteDevDB
    local run = db.runs[1]
    local snapshot = { db = db, run = run }
    restore()
    db = snapshot.db
    assertEquals("string", type(db.stamp))
    assertEquals("string", type(db.build))
    assertEquals("table", type(db.runs))
    assertEquals("number", type(db.runId))
    assertEquals("table", type(db.commands))
    assertEquals("number", type(run.id))
    assertEquals("string", type(run.stamp))
    assertEquals("string", type(run.suite))
    assertEquals("number", type(run.started))
    assertEquals("number", type(run.finished))
    assertEquals("boolean", type(run.combat))
    assertEquals(1, run.pass)
    assertEquals(1, run.fail)
    assertEquals(1, run.skip)
    assertEquals(3, #run.tests)
    for _, t in ipairs(run.tests) do
        assertEquals("string", type(t.name))
        assertTrue(t.status == "pass" or t.status == "fail" or t.status == "skip")
        assertEquals("string", type(t.detail))
    end
    local cmd = db.commands[1]
    assertEquals("number", type(cmd.t))
    assertEquals("string", type(cmd.verb))
    assertEquals("boolean", type(cmd.ok))
    assertEquals("string", type(cmd.detail))
    assertEquals(Dev.stamp(), run.stamp)
    assertEquals(db.build, run.build)
    assertTrue(Dev.buildString() ~= nil)
end)

test("a repaired DB: junk SavedVariables are replaced by the contract shape", function()
    local _, restore = sandbox()
    _G.ForteDevDB = { runs = "x", commands = 5, runId = "z", stamp = 1 }
    local db = Dev.DB()
    restore()
    assertEquals("table", type(db.runs))
    assertEquals("table", type(db.commands))
    assertEquals(0, db.runId)
    assertEquals("string", type(db.stamp))
end)

test("suites: ooc runs the ooc group only; combat arms; all = ooc + armed", function()
    local timers, restore = sandbox()
    local log = {}
    Dev.suites = {
        suite(function(T) T.check("o", function() log[#log + 1] = "ooc" end) end, "o", "ooc"),
        suite(function(T) T.check("c", function() log[#log + 1] = "combat" end) end, "c", "combat"),
    }
    local ok1, d1 = S.Request("ooc")
    local afterOoc = #log
    local armedAfterOoc = Dev.state.armed
    local ok2 = S.Request("combat")
    local armed = Dev.state.armed
    local ranWhileArmed = #log
    local ok3, d3 = S.Request("all")
    restore()
    assertTrue(ok1 and d1:find("pass=1", 1, true) ~= nil, d1)
    assertEquals(1, afterOoc)
    assertEquals("ooc", log[1])
    assertEquals(false, armedAfterOoc == true)
    assertTrue(ok2 and armed, "selftest combat arms")
    assertEquals(1, ranWhileArmed, "arming runs nothing")
    assertTrue(ok3 and d3:find("armed", 1, true) ~= nil, d3)
    assertEquals(2, #log, "all ran the ooc group again")
end)

test("the armed combat suite runs COMBAT_DELAY s after PLAYER_REGEN_DISABLED, once", function()
    local timers, restore = sandbox()
    _G.InCombatLockdown = function() return false end
    local log = {}
    Dev.suites = { suite(function(T) T.check("c", function() log[#log + 1] = "c" end) end, "c", "combat") }
    S.Request("combat")
    assertEquals(0, #timers, "no timer before combat")
    _G.InCombatLockdown = function() return true end
    Dev.HandleEvent("PLAYER_REGEN_DISABLED")
    Dev.HandleEvent("PLAYER_REGEN_DISABLED")     -- a second edge must not double-schedule
    local nTimers = #timers
    local sec = timers[1] and timers[1].sec
    local before = #log
    timers[1].fn()
    local runs = _G.ForteDevDB.runs
    local run = runs[#runs]
    local armed = Dev.state.armed
    S.RunArmed()                                 -- disarmed: nothing more
    local after = #log
    restore()
    assertEquals(1, nTimers)
    assertEquals(Dev.COMBAT_DELAY, sec)
    assertEquals(0, before)
    assertEquals(1, after)
    assertEquals(false, armed)
    assertEquals("combat", run.suite)
    assertEquals(true, run.combat)
end)

test("arming while already in combat schedules at once", function()
    local timers, restore = sandbox()
    _G.InCombatLockdown = function() return true end
    Dev.suites = {}
    S.Request("combat")
    local n = #timers
    restore()
    assertEquals(1, n)
end)

test("combat gating: ooc / all / run / clear are refused in combat, status / panel / shot / selftest combat are not", function()
    local _, restore = sandbox()
    _G.InCombatLockdown = function() return true end
    Dev.suites = {}
    local results = {}
    for _, msg in ipairs({ "selftest ooc", "selftest all", "selftest", "run", "clear", "status", "panel on", "selftest combat" }) do
        local ok, detail = Dev.Dispatch(msg)
        results[msg] = { ok, detail }
    end
    local runsRecorded = #_G.ForteDevDB.runs
    restore()
    for _, msg in ipairs({ "selftest ooc", "selftest all", "selftest", "run", "clear" }) do
        assertEquals(false, results[msg][1], msg)
        assertTrue(results[msg][2]:find("refused in combat", 1, true) ~= nil, msg .. ": " .. results[msg][2])
    end
    assertEquals(true, results["status"][1])
    assertEquals(true, results["panel on"][1])
    assertEquals(true, results["selftest combat"][1])
    assertEquals(0, runsRecorded, "nothing ran")
end)

test("dispatcher: unknown verbs and bad arguments answer false, never raise", function()
    local _, restore = sandbox()
    local a = { Dev.Dispatch("bogus") }
    local b = { Dev.Dispatch("selftest nope") }
    local c = { Dev.Dispatch("panel maybe") }
    local d = { Dev.Dispatch("") }
    local e = { Dev.Dispatch("  STATUS  ") }
    restore()
    assertEquals(false, a[1]); assertEquals(false, b[1]); assertEquals(false, c[1]); assertEquals(false, d[1])
    assertEquals(true, e[1], "verbs are case/space tolerant")
end)

test("clear empties runs and commands, keeps runId, disarms", function()
    local _, restore = sandbox()
    Dev.suites = {}
    S.RunList({ suite(function() end) }, "t")
    Dev.RecordCommand("x", true, "y")
    S.Request("combat")
    local ok = Dev.Dispatch("clear")
    local db = _G.ForteDevDB
    local runs, cmds, runId, armed = #db.runs, #db.commands, db.runId, Dev.state.armed
    restore()
    assertTrue(ok)
    assertEquals(0, runs); assertEquals(0, cmds); assertEquals(1, runId); assertEquals(false, armed)
end)

-- ============================================== the secret-safe store law ==

local SECRET = setmetatable({}, { __tostring = function() return "TOPSECRET-VALUE-123" end })

local function leaks(root)
    local seen, found = {}, false
    local function walk(v)
        if rawequal(v, SECRET) then found = true return end
        if type(v) == "string" and v:find("TOPSECRET", 1, true) then found = true return end
        if type(v) ~= "table" or seen[v] then return end
        seen[v] = true
        for k, x in pairs(v) do walk(k); walk(x) end
    end
    walk(root)
    return found
end

test("secret-safe store: a stubbed secret never lands in ForteDevDB", function()
    local _, restore = sandbox()
    _G.issecretvalue = function(v) return rawequal(v, SECRET) end
    local run = S.RunList({ suite(function(T)
        T.check("eq on a secret", function() T.eq(SECRET, 5, "health") end)
        T.check("truthy on a secret", function() T.truthy(SECRET, "x") end)
        T.check("falsy on a secret", function() T.falsy(SECRET, "x") end)
        T.check("secret as the error value", function() error(SECRET) end)
        T.check("classified, not stored", function()
            T.eq(Dev.plain(SECRET), nil, "plain")
            T.eq(Dev.S(SECRET), "SECRET", "S")
            T.eq(Dev.K(SECRET), "SECRET", "K")
            T.note("raw=" .. Dev.K(SECRET))
        end)
    end) }, "t")
    Dev.RecordCommand("lua: secret", true, "ok " .. Dev.S(SECRET))
    local db = _G.ForteDevDB
    local leaked = leaks(db)
    restore()
    assertEquals(false, leaked, "no secret (nor its tostring) anywhere in ForteDevDB")
    assertEquals(4, run.fail)
    assertEquals(1, run.pass)
    assertTrue(find(run, "eq on a secret").detail:find("SECRET", 1, true) ~= nil)
    assertTrue(find(run, "secret as the error value").detail:find("raise: SECRET", 1, true) ~= nil)
end)

test("secret-safe store: the real combat suite reads secrets without raising or storing them", function()
    local _, restore = sandbox()
    local saved = { uh = _G.UnitHealth, ua = _G.C_UnitAuras, cd = FX.Compat.GetSpellCooldownInfo }
    _G.issecretvalue = function(v) return rawequal(v, SECRET) end
    _G.InCombatLockdown = function() return true end
    _G.UnitHealth = function() return SECRET end
    _G.C_UnitAuras = { GetAuraDataByIndex = function() return { name = SECRET, spellId = SECRET } end }
    FX.Compat.GetSpellCooldownInfo = function() return { startTime = SECRET, duration = SECRET } end
    Dev.state.castRing = { Dev.K(SECRET), "number:5" }
    local combat
    for _, s in ipairs(Dev.suites) do if s.group == "combat" then combat = s end end
    local run = S.RunList({ combat }, "combat")
    local leaked = leaks(_G.ForteDevDB)
    _G.UnitHealth, _G.C_UnitAuras, FX.Compat.GetSpellCooldownInfo = saved.uh, saved.ua, saved.cd
    restore()
    assertEquals(false, leaked)
    assertEquals(true, run.combat)
    assertEquals("pass", find(run, "combat: UnitHealth('target') through PlainOrNil").status)
    assertTrue(find(run, "combat: UnitHealth('target') through PlainOrNil").detail:find("raw=SECRET plain=nil", 1, true) ~= nil,
        find(run, "combat: UnitHealth('target') through PlainOrNil").detail)
    assertEquals("pass", find(run, "combat: target aura read through PlainOrNil").status)
    assertEquals("pass", find(run, "combat: own spell cooldown read through PlainOrNil").status)
    -- the cast ring holds a SECRET entry: the "own cast ids are plain" assertion must FAIL it, loudly
    assertEquals("fail", find(run, "combat: own cast spell ids are plain").status)
end)

test("geometry tolerance: Dev.near accepts 95.99999 for 96, rejects 0.6 off, nil, NaN and non-numbers", function()
    assertEquals(0.5, Dev.GEOM_TOL)
    assertTrue(Dev.near(95.99999, 96))
    assertTrue(Dev.near(96.5, 96), "exactly the tolerance is near")
    assertFalse(Dev.near(96.6, 96))
    assertFalse(Dev.near(95.4, 96))
    assertTrue(Dev.near(10.9, 10, 1), "explicit tolerance")
    assertFalse(Dev.near(nil, 96))
    assertFalse(Dev.near("96", 96))
    assertFalse(Dev.near(0 / 0, 0 / 0))
end)

test("geometry tolerance: T.near passes inside 0.5, fails outside with 4 decimals in the detail", function()
    local _, restore = sandbox()
    local run = S.RunList({ suite(function(T)
        T.check("inside", function() T.near(95.99999, 96, "w") end)
        T.check("edge", function() T.near(6.5, 6, "h") end)
        T.check("outside", function() T.near(96.75, 96, "beacon width") end)
        T.check("float shown", function() T.near(95.2, 96, "beacon width") end)
        T.check("nil", function() T.near(nil, 96, "beacon width") end)
        T.check("custom tol", function() T.near(100.9, 100, "x", 1) end)
    end) }, "t")
    restore()
    assertEquals("pass", find(run, "inside").status)
    assertEquals("pass", find(run, "edge").status)
    assertEquals("fail", find(run, "outside").status)
    assertEquals("beacon width: expected 96.0000 got 96.7500 (diff 0.7500, tol 0.50)", find(run, "outside").detail)
    assertTrue(find(run, "float shown").detail:find("got 95.2000", 1, true) ~= nil, find(run, "float shown").detail)
    assertEquals("fail", find(run, "nil").status)
    assertTrue(find(run, "nil").detail:find("expected 96.0000 got nil", 1, true) ~= nil, find(run, "nil").detail)
    assertEquals("pass", find(run, "custom tol").status)
end)

test("geometry tolerance: T.near refuses a secret actual without comparing it", function()
    local _, restore = sandbox()
    _G.issecretvalue = function(v) return v == 123 end
    local run = S.RunList({ suite(function(T)
        T.check("secret", function() T.near(123, 96, "w") end)
    end) }, "t")
    restore()
    assertEquals("fail", find(run, "secret").status)
    assertTrue(find(run, "secret").detail:find("SECRET", 1, true) ~= nil, find(run, "secret").detail)
end)

-- ============================================================ async steps ==

test("async: a check that settles later; the run, its stored result and the beacon's finished cell wait for it", function()
    local _, restore = sandbox()
    local order, settleFn = {}, nil
    local run, pending = S.RunList({
        suite(function(T)
            T.check("sync1", function() order[#order + 1] = "sync1" end)
            T.async("later", 5, function(settle) order[#order + 1] = "begin"; settleFn = settle end)
            T.step(function() order[#order + 1] = "step"; T.check("after", function() end) end)
        end, "a"),
        suite(function(T) order[#order + 1] = "suite b"; T.check("b", function() end) end, "b"),
    }, "t", function() order[#order + 1] = "done" end)
    local mid = { running = Dev.state.running, finished = Dev.state.finished, stored = #_G.ForteDevDB.runs,
        order = table.concat(order, ","), flags = Dev.Beacon.Flags(), summary = S.Summary(run, pending) }
    settleFn(function(T) T.note("late") end)
    settleFn(function() error("a second settle must be ignored") end)
    local final = { running = Dev.state.running, finished = Dev.state.finished, stored = #_G.ForteDevDB.runs,
        order = table.concat(order, ","), flags = Dev.Beacon.Flags(), last = Dev.state.lastRun }
    restore()
    assertEquals(true, pending, "the run reports pending")
    assertEquals(true, mid.running)
    assertEquals(false, mid.finished and true or false, "not finished while the async step is open")
    assertEquals(0, mid.stored, "nothing is stored before the last step")
    assertEquals("sync1,begin", mid.order, "neither the next step nor the next suite started")
    assertEquals(true, mid.flags.running, "beacon: running")
    assertEquals(false, mid.flags.finished, "beacon: finished waits")
    assertTrue(mid.summary:find("still running", 1, true) ~= nil, mid.summary)
    assertEquals("sync1,begin,step,suite b,done", final.order)
    assertEquals(false, final.running)
    assertEquals(true, final.finished)
    assertEquals(1, final.stored)
    assertEquals(true, final.flags.finished)
    assertEquals(false, final.flags.running)
    assertEquals(run, final.last)
    assertEquals(4, run.pass)
    assertEquals(0, run.fail)
    assertEquals("late", find(run, "later").detail)
    assertEquals(4, #run.tests, "the ignored second settle recorded nothing")
end)

test("async: the hard timeout records a FAIL, runs the cleanup, ignores a late settle and the run goes on", function()
    local timers, restore = sandbox()
    local cleaned, settleFn = 0, nil
    local run, pending = S.RunList({ suite(function(T)
        T.async("never", 4, function(settle)
            settleFn = settle
            return function() cleaned = cleaned + 1 end
        end)
        T.step(function() T.check("next", function() end) end)
    end) }, "t")
    local sec, running = timers[1] and timers[1].sec, Dev.state.running
    timers[1].fn()
    settleFn(function(T) T.note("too late") end)
    local after = { running = Dev.state.running, stored = #_G.ForteDevDB.runs }
    restore()
    assertEquals(true, pending)
    assertEquals(4, sec, "the timeout is armed with the step's own seconds")
    assertEquals(true, running)
    assertEquals(false, after.running)
    assertEquals(1, after.stored)
    assertEquals(1, cleaned)
    assertEquals("fail", find(run, "never").status)
    assertTrue(find(run, "never").detail:find("timeout", 1, true) ~= nil, find(run, "never").detail)
    assertEquals("pass", find(run, "next").status, "the queue went on after the timeout")
    assertEquals(2, #run.tests, "the late settle recorded nothing")
end)

test("async: a settle before the timer fires leaves the timeout inert", function()
    local timers, restore = sandbox()
    local cleaned, settleFn = 0, nil
    local run = S.RunList({ suite(function(T)
        T.async("ok", 4, function(settle)
            settleFn = settle
            return function() cleaned = cleaned + 1 end
        end)
    end) }, "t")
    settleFn(function() end)
    timers[1].fn()
    restore()
    assertEquals(0, cleaned)
    assertEquals(1, run.pass)
    assertEquals(0, run.fail)
end)

test("async: inline settles, a raising begin, a raising step and a silent settle are all contained", function()
    local _, restore = sandbox()
    local run, pending = S.RunList({ suite(function(T)
        T.async("inline", 5, function(settle) settle(function() end) end)
        T.async("silent", 5, function(settle) settle() end)
        T.async("raising", 5, function() error("begin boom") end)
        T.step(function() error("step boom") end)
        T.step(function() T.check("tail", function() end) end)
    end) }, "t")
    restore()
    assertEquals(false, pending, "everything settled inline: the run is complete on return")
    assertEquals("pass", find(run, "inline").status)
    assertEquals(nil, find(run, "silent"), "settle() with no body records nothing")
    assertEquals("fail", find(run, "raising").status)
    assertTrue(find(run, "raising").detail:find("^raise: "), find(run, "raising").detail)
    assertEquals("pass", find(run, "tail").status)
    local stepFail = find(run, "step")
    assertEquals("fail", stepFail.status)
    assertTrue(stepFail.detail:find("step boom", 1, true) ~= nil, stepFail.detail)
end)

test("async: Request answers at once with 'still running'; a second request is refused until the run ends", function()
    local _, restore = sandbox()
    local settleFn
    Dev.suites = { suite(function(T)
        T.async("slow", 5, function(settle) settleFn = settle end)
    end) }
    local ok1, d1 = S.Request("ooc")
    local ok2, d2 = S.Request("ooc")
    settleFn(function() end)
    local ok3, d3 = S.Request("ooc")
    restore()
    assertTrue(ok1 and d1:find("still running", 1, true) ~= nil, d1)
    assertEquals(false, ok2)
    assertTrue(d2:find("already in progress", 1, true) ~= nil, d2)
    assertTrue(ok3, "a new run starts once the first one finished")
end)

test("async: the armed combat suite waits for an ooc run in flight instead of being lost", function()
    local timers, restore = sandbox()
    _G.InCombatLockdown = function() return false end
    local log = {}
    Dev.suites = { suite(function(T) T.check("c", function() log[#log + 1] = "c" end) end, "c", "combat") }
    S.Request("combat")
    Dev.state.running = true
    local r1 = S.RunArmed()
    local armedWhileRunning, sec = Dev.state.armed, timers[1] and timers[1].sec
    Dev.state.running = false
    timers[1].fn()
    local armedAfter, ran = Dev.state.armed, #log
    restore()
    assertEquals(nil, r1)
    assertEquals(true, armedWhileRunning, "still armed")
    assertEquals(1, sec)
    assertEquals(false, armedAfter)
    assertEquals(1, ran, "the combat suite ran once the run had finished")
end)

test("shot: waits for a run in flight (bounded) so the screenshot shows the finished run", function()
    local timers, restore = sandbox()
    local savedShot = _G.Screenshot
    local calls = 0
    _G.Screenshot = function() calls = calls + 1 end
    Dev.state.running = true
    local ok = Dev.Dispatch("shot")
    timers[1].fn()                               -- the 0.2 s timer: the run is still open
    local whileRunning, rearmed = calls, #timers
    Dev.state.running = false
    timers[#timers].fn()                         -- the re-armed wait: the run has finished
    local afterFinish = calls
    -- a run that never finishes cannot hold the screenshot forever
    Dev.state.running = true
    Dev.Dispatch("shot")
    local guard = 0
    while calls == afterFinish and guard < 200 do
        guard = guard + 1
        timers[#timers].fn()
    end
    local waited = guard * Dev.SHOT_WAIT_STEP
    local fired = calls
    _G.Screenshot = savedShot
    restore()
    assertTrue(ok)
    assertEquals(0, whileRunning, "no screenshot while the run is open")
    assertEquals(2, rearmed, "re-armed")
    assertEquals(1, afterFinish)
    assertEquals(2, fired, "the bound fired the screenshot anyway")
    assertTrue(waited <= Dev.SHOT_WAIT_MAX + Dev.SHOT_WAIT_STEP, "waited " .. waited .. " s")
end)
