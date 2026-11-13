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
