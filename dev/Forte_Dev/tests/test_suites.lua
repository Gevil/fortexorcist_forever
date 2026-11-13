-- dev/Forte_Dev/tests/test_suites.lua
-- The real suites in the simulator. The simulator is not the client: Screenshot() and the live spell
-- names are sim-limited, so those two checks may FAIL here and are exempt. What must hold: no check
-- RAISES (a `raise:` detail is a bug in the suite), every suite reports, the persistence round trip
-- works, and each suite's logic is pinned against stubs.

local FX = ForteXorcist
local Dev = FX.Dev
local S = Dev.Selftest

local SIM_LIMITED = {
    ["api: the dev addon's own needs"] = true,                         -- Screenshot() is absent in the sim
    ["data: every generated spell id resolves to the generated name"] = true,   -- sim spell names differ
}

local function sandbox()
    local saved = { db = _G.ForteDevDB, after = Dev.After, combat = _G.InCombatLockdown, state = {},
        since = FX.Errors and FX.Errors.sinceLoad }
    for k, v in pairs(Dev.state) do saved.state[k] = v end
    _G.ForteDevDB = nil
    Dev.InitDB()
    for k in pairs(Dev.state) do Dev.state[k] = nil end
    Dev.state.panelOn = true
    Dev.After = function() end
    -- errors the test harness itself caused earlier in this process must not leak into the
    -- "sinceLoad is 0 at the start" assertion under test
    if FX.Errors then FX.Errors.sinceLoad = 0 end
    return function()
        _G.ForteDevDB = saved.db
        Dev.After = saved.after
        _G.InCombatLockdown = saved.combat
        if FX.Errors then FX.Errors.sinceLoad = saved.since end
        for k in pairs(Dev.state) do Dev.state[k] = nil end
        for k, v in pairs(saved.state) do Dev.state[k] = v end
        Dev.Repaint()
    end
end

local function suiteNamed(name)
    for _, s in ipairs(Dev.suites) do if s.name == name then return s end end
end

local function find(run, name)
    for _, t in ipairs(run.tests) do if t.name == name then return t end end
end

local function runOne(name) return S.RunList({ suiteNamed(name) }, name) end

test("the suite registry: every contract suite is registered, ooc ones plus the armed combat one", function()
    for _, name in ipairs({ "census", "api", "frames", "persistence", "data", "errors" }) do
        assertNotNil(suiteNamed(name), name)
        assertEquals("ooc", suiteNamed(name).group)
    end
    assertNotNil(suiteNamed("combat"))
    assertEquals("combat", suiteNamed("combat").group)
end)

test("the generated API list is present and names what the addon calls", function()
    local list = Dev.ApiList
    assertEquals("table", type(list))
    assertTrue(#list.hard > 5, "hard list")
    assertTrue(#list.soft > 5, "soft list")
    local has = {}
    for _, s in ipairs(list.hard) do has[s] = true end
    assertTrue(has["CreateFrame"] and has["C_Timer.After"] and has["issecretvalue"], "core names are hard")
end)

test("a real ooc run: no check raises, every suite reports, nothing but the sim-limited checks fails", function()
    local restore = sandbox()
    local run = S.RunGroup("ooc", "ooc")
    restore()
    assertNotNil(run)
    local raised, unexpected = {}, {}
    local seen = {}
    for _, t in ipairs(run.tests) do
        seen[t.name:match("^(%w+):")] = true
        if t.detail:find("^raise: ") or t.detail:find("suite raised", 1, true) then
            raised[#raised + 1] = t.name .. " => " .. t.detail
        end
        if t.status == "fail" and not SIM_LIMITED[t.name] then unexpected[#unexpected + 1] = t.name .. " => " .. t.detail end
    end
    assertEquals(0, #raised, table.concat(raised, " || "))
    assertEquals(0, #unexpected, table.concat(unexpected, " || "))
    for _, name in ipairs({ "census", "api", "frames", "persistence", "data", "errors" }) do
        assertTrue(seen[name], "suite " .. name .. " reported")
    end
end)

test("census: the always-loaded modules and the default class pass in the sim", function()
    local restore = sandbox()
    local run = runOne("census")
    restore()
    assertEquals("pass", find(run, "census: always-loaded modules registered and enabled").status)
    assertEquals("pass", find(run, "census: Forte_Options loaded").status)
    assertEquals("pass", find(run, "census: no other class add-on is loaded").status)
end)

test("census: a missing always-loaded module fails the check and names it", function()
    local restore = sandbox()
    local saved = FX.modules["Probe"]
    FX.modules["Probe"] = nil
    local run = runOne("census")
    FX.modules["Probe"] = saved
    restore()
    local t = find(run, "census: always-loaded modules registered and enabled")
    assertEquals("fail", t.status)
    assertTrue(t.detail:find("Probe(unregistered)", 1, true) ~= nil, t.detail)
end)

test("api: a missing hard symbol fails with its name; guarded misses are only reported", function()
    local restore = sandbox()
    local savedList = Dev.ApiList
    Dev.ApiList = { files = 1, hard = { "CreateFrame", "FXDevNoSuchGlobal", "C_Timer.NoSuchFn" }, soft = { "FXDevSoftMissing" } }
    local run = runOne("api")
    Dev.ApiList = savedList
    restore()
    local hard = find(run, "api: every unguarded C_* / global the addon calls exists")
    assertEquals("fail", hard.status)
    assertTrue(hard.detail:find("FXDevNoSuchGlobal", 1, true) ~= nil and hard.detail:find("C_Timer.NoSuchFn", 1, true) ~= nil, hard.detail)
    local soft = find(run, "api: guarded references (informational)")
    assertEquals("pass", soft.status)
    assertTrue(soft.detail:find("FXDevSoftMissing", 1, true) ~= nil, soft.detail)
end)

test("persistence: first run skips 'pending first reload', a simulated reload verifies the nonce", function()
    local restore = sandbox()
    local first = runOne("persistence")
    local t1 = find(first, "persistence: nonce from the previous load survived")
    -- the reload: what Dev.InitDB captures from disk at the next load
    local db = _G.ForteDevDB
    local written = db.nonce
    Dev.InitDB()
    local second = runOne("persistence")
    local t2 = find(second, "persistence: nonce from the previous load survived")
    -- a corrupted nonce fails
    db.nonce.check = "tampered"
    Dev.InitDB()
    local third = runOne("persistence")
    local t3 = find(third, "persistence: nonce from the previous load survived")
    restore()
    assertEquals("skip", t1.status)
    assertTrue(t1.detail:find("pending first reload", 1, true) ~= nil, t1.detail)
    assertNotNil(written)
    assertEquals("pass", t2.status)
    assertEquals("fail", t3.status)
end)

test("data: matching names pass; mismatches are counted and the first 10 listed; other locales go through FX.L", function()
    local restore = sandbox()
    local title = Dev.classTitle()
    local rows = FX.Data[title]
    local savedSpell, savedEng, savedL = _G.C_Spell, FX.Locale.IsEnglish, FX.L
    _G.C_Spell = { GetSpellInfo = function(id) return { name = rows[id] and rows[id].name } end }
    local ok = runOne("data")
    local okName = find(ok, "data: every generated spell id resolves to the generated name")

    local n = 0
    _G.C_Spell = { GetSpellInfo = function(id)
        n = n + 1
        if n <= 12 then return { name = "Wrong" .. n } end
        return { name = rows[id] and rows[id].name }
    end }
    local bad = runOne("data")
    local badName = find(bad, "data: every generated spell id resolves to the generated name")

    FX.Locale.IsEnglish = function() return false end
    FX.L = function(name) return "L:" .. name end
    _G.C_Spell = { GetSpellInfo = function(id) return { name = rows[id] and ("L:" .. rows[id].name) } end }
    local loc = runOne("data")
    local locName = find(loc, "data: every generated spell id resolves to the generated name")

    _G.C_Spell, FX.Locale.IsEnglish, FX.L = savedSpell, savedEng, savedL
    restore()
    assertEquals("pass", okName.status, okName.detail)
    assertEquals("fail", badName.status)
    assertTrue(badName.detail:find("^12/"), badName.detail)
    assertEquals("pass", locName.status, locName.detail)
end)

test("data: the compat known-check answers a plain boolean", function()
    local restore = sandbox()
    local run = runOne("data")
    restore()
    local t = find(run, "data: IsPlayerSpell / the compat known-check answer plain booleans")
    assertTrue(t.status == "pass" or t.status == "skip", t.status .. " " .. t.detail)
end)

test("errors: skip while FX.Errors is absent; the deliberate pcall'd error is not recorded", function()
    local restore = sandbox()
    local saved = FX.Errors
    FX.Errors = nil
    local absent = runOne("errors")
    FX.Errors = saved
    local present = runOne("errors")
    restore()
    assertEquals(0, absent.pass + absent.fail)
    assertEquals(4, absent.skip)
    if saved then
        assertEquals("pass", find(present, "errors: a deliberate pcall'd error is not recorded").status)
        assertEquals("pass", find(present, "errors: sinceLoad is 0 at the start of the run").status)
    end
end)

test("errors: a nonzero sinceLoad fails the start-of-run check", function()
    local restore = sandbox()
    if not FX.Errors then restore() return end
    local saved = FX.Errors.sinceLoad
    FX.Errors.sinceLoad = 2
    local run = runOne("errors")
    FX.Errors.sinceLoad = saved
    restore()
    assertEquals("fail", find(run, "errors: sinceLoad is 0 at the start of the run").status)
end)

test("frames: the options window is opened and closed through the real slash handler", function()
    local restore = sandbox()
    local run = runOne("frames")
    local t = find(run, "frames: options window opens and closes through /fx options")
    local open = FX.Options and FX.Options:IsOpen()
    restore()
    assertTrue(t.status == "pass" or t.status == "skip", t.status .. " " .. t.detail)
    assertEquals(false, open and true or false, "the window is left as it was found (closed)")
end)

test("frames: the options check is skipped in combat", function()
    local restore = sandbox()
    _G.InCombatLockdown = function() return true end
    local run = S.RunList({ suiteNamed("frames") }, "frames")
    restore()
    assertEquals("skip", find(run, "frames: options window opens and closes through /fx options").status)
end)

test("frames: a legacy-form timer position (no corner) fails the corner check", function()
    local restore = sandbox()
    local d = FX.db and FX.db.timer and FX.db.timer.display
    if not d then restore() return end
    local saved = d.corner
    d.corner = nil
    local run = runOne("frames")
    d.corner = saved
    restore()
    assertEquals("fail", find(run, "frames: timer position uses the corner form (FX.db.timer.display.corner)").status)
end)
