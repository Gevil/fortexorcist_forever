-- dev/Forte_Dev/tests/test_devcommands.lua
-- DevCommands: gated (never in combat), once per load, each verb through the /fxdev dispatcher, the
-- optional lua entry through loadstring + pcall with the outcome recorded, caps, scheduling off
-- PLAYER_ENTERING_WORLD (and the login fallback). The timer seam is injected: no sleeps.

local FX = ForteXorcist
local Dev = FX.Dev

local SECRET = setmetatable({}, { __tostring = function() return "TOPSECRET-CMD-456" end })

local function sandbox(commands)
    local saved = { db = _G.ForteDevDB, after = Dev.After, combat = _G.InCombatLockdown, cmds = _G.ForteDevCommands,
        secret = _G.issecretvalue, frame = Dev.frame, state = {} }
    for k, v in pairs(Dev.state) do saved.state[k] = v end
    _G.ForteDevDB = nil
    Dev.InitDB()
    for k in pairs(Dev.state) do Dev.state[k] = nil end
    Dev.state.panelOn = true
    _G.InCombatLockdown = function() return false end
    _G.ForteDevCommands = commands or {}
    local timers = {}
    Dev.After = function(sec, fn) timers[#timers + 1] = { sec = sec, fn = fn } end
    return timers, function()
        _G.ForteDevDB = saved.db
        Dev.After = saved.after
        _G.InCombatLockdown, _G.ForteDevCommands, _G.issecretvalue = saved.combat, saved.cmds, saved.secret
        Dev.frame = saved.frame
        for k in pairs(Dev.state) do Dev.state[k] = nil end
        for k, v in pairs(saved.state) do Dev.state[k] = v end
        Dev.Repaint()
    end
end

local function cmds() return _G.ForteDevCommands and _G.ForteDevDB.commands end

test("the shipped files: DevStamp.lua / DevCommands.lua define their globals", function()
    assertEquals("string", type(_G.ForteDevStamp))
    assertTrue(_G.ForteDevStamp:find("%+") ~= nil, "<gitsha>+<utc>: " .. _G.ForteDevStamp)
    assertEquals("table", type(_G.ForteDevCommands))
end)

test("verbs run through the dispatcher and are recorded {t, verb, ok, detail}", function()
    local _, restore = sandbox({ "status", { verb = "panel off" }, "bogus verb" })
    local ok, detail = Dev.RunCommands(false)
    local list = _G.ForteDevDB.commands
    local copy = { #list, list[1], list[2], list[3] }
    restore()
    assertTrue(ok, detail)
    assertEquals(3, copy[1])
    assertEquals("status", copy[2].verb); assertEquals(true, copy[2].ok)
    assertTrue(copy[2].detail:find("^stamp="), copy[2].detail)
    assertEquals("panel off", copy[3].verb); assertEquals(true, copy[3].ok)
    assertEquals("bogus verb", copy[4].verb); assertEquals(false, copy[4].ok)
    assertEquals("number", type(copy[2].t))
end)

test("skipped in combat: nothing runs, one skip record, and it counts as this load's run", function()
    local _, restore = sandbox({ "panel off" })
    _G.InCombatLockdown = function() return true end
    local ok, detail = Dev.RunCommands(false)
    local list = _G.ForteDevDB.commands
    local n, first = #list, list[1]
    local panelOn = Dev.state.panelOn
    local ran = Dev.state.commandsRan
    restore()
    assertEquals(false, ok)
    assertTrue(detail:find("in combat", 1, true) ~= nil)
    assertEquals(1, n)
    assertEquals(false, first.ok)
    assertEquals("devcommands", first.verb)
    assertEquals(true, panelOn, "the verb did not run")
    assertEquals(true, ran)
end)

test("combat starting mid-list stops the rest", function()
    local flag = false
    _G.FXDEV_TEST_SET_COMBAT = function(v) flag = v end
    local _, restore = sandbox({ { lua = "FXDEV_TEST_SET_COMBAT(true)" }, "panel off", "panel off" })
    _G.InCombatLockdown = function() return flag end
    Dev.RunCommands(false)
    local list = _G.ForteDevDB.commands
    local n, second = #list, list[2]
    local panelOn = Dev.state.panelOn
    restore()
    _G.FXDEV_TEST_SET_COMBAT = nil
    assertEquals(2, n)
    assertEquals(true, panelOn)
    assertTrue(second.detail:find("in combat", 1, true) ~= nil, second.detail)
end)

test("once per load: a second automatic run does nothing; the run verb forces one", function()
    local _, restore = sandbox({ "status" })
    Dev.RunCommands(false)
    local n1 = #_G.ForteDevDB.commands
    local ok2, d2 = Dev.RunCommands(false)
    local n2 = #_G.ForteDevDB.commands
    local okRun = Dev.Dispatch("run")
    local n3 = #_G.ForteDevDB.commands
    restore()
    assertEquals(1, n1)
    assertTrue(ok2 and d2:find("already", 1, true) ~= nil, d2)
    assertEquals(1, n2)
    assertTrue(okRun)
    assertEquals(2, n3)
end)

test("the run verb inside DevCommands is refused (no recursion)", function()
    local _, restore = sandbox({ "run" })
    Dev.RunCommands(false)
    local rec = _G.ForteDevDB.commands[1]
    restore()
    assertEquals(false, rec.ok)
    assertTrue(rec.detail:find("refused", 1, true) ~= nil, rec.detail)
end)

test("lua entries: loadstring + pcall, result or error recorded", function()
    local _, restore = sandbox({ { lua = "return 1 + 1" }, { lua = "error('kaboom')" }, { lua = "return (" },
        { lua = "return { 1 }" }, { lua = 5 }, 42 })
    Dev.RunCommands(false)
    local l = _G.ForteDevDB.commands
    local r = { l[1], l[2], l[3], l[4], l[5], l[6] }
    restore()
    assertEquals(true, r[1].ok); assertEquals("ok 2", r[1].detail)
    assertTrue(r[1].verb:find("^lua: return 1 %+ 1"), r[1].verb)
    assertEquals(false, r[2].ok); assertTrue(r[2].detail:find("^error: "), r[2].detail)
    assertTrue(r[2].detail:find("kaboom", 1, true) ~= nil)
    assertEquals(false, r[3].ok); assertTrue(r[3].detail:find("^compile: "), r[3].detail)
    assertEquals(true, r[4].ok); assertEquals("ok table", r[4].detail, "a table result is the type name only")
    assertEquals(false, r[5].ok)
    assertEquals(false, r[6].ok)
end)

test("a lua entry returning a secret records SECRET and stores nothing raw", function()
    _G.FXDEV_TEST_SECRET = SECRET
    local _, restore = sandbox({ { lua = "return FXDEV_TEST_SECRET" } })
    _G.issecretvalue = function(v) return rawequal(v, SECRET) end
    Dev.RunCommands(false)
    local rec = _G.ForteDevDB.commands[1]
    local blob = {}
    for k, v in pairs(rec) do blob[#blob + 1] = tostring(v) end
    restore()
    _G.FXDEV_TEST_SECRET = nil
    assertEquals(true, rec.ok)
    assertEquals("ok SECRET", rec.detail)
    assertEquals(false, table.concat(blob, "|"):find("TOPSECRET", 1, true) ~= nil)
end)

test("caps: commands keep the newest 30; one automatic pass runs at most MAX_COMMAND_ENTRIES", function()
    local many = {}
    for i = 1, 25 do many[i] = "status" end
    local _, restore = sandbox(many)
    Dev.RunCommands(false)
    local n1 = #_G.ForteDevDB.commands
    Dev.RunCommands(true)
    Dev.RunCommands(true)
    local n2 = #_G.ForteDevDB.commands
    restore()
    assertEquals(Dev.MAX_COMMAND_ENTRIES, n1)
    assertEquals(Dev.MAX_COMMANDS, n2)
end)

test("a non-table ForteDevCommands is recorded, not raised", function()
    local _, restore = sandbox()
    _G.ForteDevCommands = "nonsense"
    local ok = Dev.RunCommands(false)
    local rec = _G.ForteDevDB.commands[1]
    restore()
    assertEquals(false, ok)
    assertEquals(false, rec.ok)
end)

-- ============================================================== scheduling ==

test("PLAYER_ENTERING_WORLD schedules the run COMMANDS_DELAY s out, once per load", function()
    local timers, restore = sandbox({ "status" })
    Dev.HandleEvent("PLAYER_ENTERING_WORLD")
    local n1, sec = #timers, timers[1] and timers[1].sec
    Dev.HandleEvent("PLAYER_ENTERING_WORLD")      -- a zone change: no second schedule
    local n2 = #timers
    local before = #_G.ForteDevDB.commands
    timers[1].fn()
    local after = #_G.ForteDevDB.commands
    Dev.HandleEvent("PLAYER_ENTERING_WORLD")
    local n3 = #timers
    restore()
    assertEquals(1, n1)
    assertEquals(Dev.COMMANDS_DELAY, sec)
    assertEquals(1, n2)
    assertEquals(0, before)
    assertEquals(1, after)
    assertEquals(1, n3, "after the run, no further schedule either")
end)

test("the login fallback: no zone-in event seen -> the run still happens", function()
    local timers, restore = sandbox({ "status" })
    Dev.Module:OnEnable()
    local fallback
    for _, t in ipairs(timers) do if t.sec == Dev.COMMANDS_FALLBACK then fallback = t end end
    assertTrue(fallback ~= nil, "OnEnable armed the fallback timer")
    fallback.fn()                                   -- no PEW seen: schedules the run
    local sched = timers[#timers]
    sched.fn()
    local n = #_G.ForteDevDB.commands
    restore()
    assertEquals(1, n)
end)

test("the login fallback is a no-op when the zone-in event did arrive", function()
    local timers, restore = sandbox({ "status" })
    Dev.Module:OnEnable()
    Dev.HandleEvent("PLAYER_ENTERING_WORLD")
    local before = #timers
    for _, t in ipairs(timers) do if t.sec == Dev.COMMANDS_FALLBACK then t.fn() end end
    local after = #timers
    restore()
    assertEquals(before, after, "the fallback scheduled nothing new")
end)

test("OnEnable registers the events inside the module (no file-top registrant) and sets no OnUpdate", function()
    local _, restore = sandbox()
    Dev.Module:OnEnable()
    local f = Dev.frame
    local onUpdate = f:GetScript("OnUpdate")
    restore()
    assertEquals(nil, onUpdate)
    assertTrue(FX.modules["Dev"] == Dev.Module, "registered through FX.RegisterModule")
end)
