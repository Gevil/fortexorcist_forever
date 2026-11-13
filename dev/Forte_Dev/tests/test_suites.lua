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
    assertNotNil(suiteNamed("motion"))
    assertEquals("ooc", suiteNamed("motion").group)
    local lastOoc
    for _, s in ipairs(Dev.suites) do if s.group == "ooc" then lastOoc = s.name end end
    assertEquals("motion", lastOoc, "the motion suite runs after the existing ooc suites")
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
    -- The motion suite is async and needs real frames + timers, which the simulator never delivers inside
    -- a test (test_motion.lua drives it with stubs): this run covers the synchronous suites.
    local savedSuites, sync = Dev.suites, {}
    for _, s in ipairs(Dev.suites) do if s.name ~= "motion" then sync[#sync + 1] = s end end
    Dev.suites = sync
    local run = S.RunGroup("ooc", "ooc")
    Dev.suites = savedSuites
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

local function stubBeacon(w, h, x, y)
    return {
        GetWidth = function() return w end,
        GetHeight = function() return h end,
        GetScale = function() return 1 end,
        GetAlpha = function() return 1 end,
        GetPoint = function() return "TOPLEFT", _G.UIParent, "TOPLEFT", x, y end,
    }
end

local BEACON_TEST = "frames: Forte_Dev beacon is 96x6 at the top-left"

test("frames: the beacon check tolerates client float noise (95.99999 x 6.00001, offsets 0.0001)", function()
    local restore = sandbox()
    local B = Dev.Beacon
    local saved = B.frame
    B.frame = stubBeacon(95.99999, 6.00001, 0.0001, -0.0001)
    local run = runOne("frames")
    B.frame = saved
    restore()
    local t = find(run, BEACON_TEST)
    assertEquals("pass", t.status, t.detail)
end)

test("frames: the beacon check still fails a real size error and prints the decimals", function()
    local restore = sandbox()
    local B = Dev.Beacon
    local saved = B.frame
    B.frame = stubBeacon(94.5, 6, 0, 0)
    local run = runOne("frames")
    B.frame = stubBeacon(96, 6, 0, 3)
    local run2 = runOne("frames")
    B.frame = saved
    restore()
    local t = find(run, BEACON_TEST)
    assertEquals("fail", t.status)
    assertTrue(t.detail:find("beacon width: expected 96.0000 got 94.5000", 1, true) ~= nil, t.detail)
    local t2 = find(run2, BEACON_TEST)
    assertEquals("fail", t2.status)
    assertTrue(t2.detail:find("beacon y offset", 1, true) ~= nil, t2.detail)
end)

-- ----------------------------------------------------------- the font probe --

local FP = Dev.FontProbe
local SHIPPED = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
local SHORT = "Forte_Core\\Fonts\\URWGothic-Book.ttf"

--- A FontString stub modelling the live client: `rule(path)` returns what SetFont returns (or raises).
--- GetFont reads back the path only after a `true` (the font has rendered once); false = pending render.
local function fontStub(rule)
    local fs = { rendered = nil }
    function fs:SetFont(path)
        local r = rule(path)
        if r == true then self.rendered = path end
        return r
    end
    function fs:GetFont() return self.rendered end
    return fs
end

local function ruleNotRenderedYet() return false end   -- the client's answer before the first render

test("font probe: only a raise is unusable; true/false/nil are information", function()
    local took, word = FP.Try(fontStub(function() return true end), SHIPPED)
    assertEquals(true, took); assertEquals("true", word)

    local pending = fontStub(ruleNotRenderedYet)
    took, word = FP.Try(pending, SHIPPED)
    assertEquals(true, took, "false is NOT a rejection"); assertEquals("false", word)
    assertEquals(nil, pending:GetFont(), "pending first render reads back nil")

    took, word = FP.Try(fontStub(function() return nil end), SHIPPED)
    assertEquals(true, took); assertEquals("nil", word)

    local missing = fontStub(function(path)
        error("FontString:SetFont(): invalid font asset (" .. path .. "): file not found", 0)
    end)
    took, word = FP.Try(missing, "Interface\\AddOns\\Forte_Core\\Fonts\\NOPE.ttf")
    assertEquals(false, took); assertEquals("raised:notfound", word)

    took, word = FP.Try(fontStub(function() error("boom", 0) end), SHIPPED)
    assertEquals(false, took); assertEquals("raised:boom", word)
end)

test("font probe: the detail merges equal displays, abbreviates the path, stays within 160 chars", function()
    local entries = {
        { name = "cd", path = SHIPPED, word = "false" },
        { name = "tm", path = SHIPPED, word = "false" },
        { name = "sw", path = SHIPPED, word = "false" },
    }
    local d = FP.Detail("true", entries)
    assertEquals("ctl=true; cd,tm,sw=false @" .. SHORT, d)
    assertTrue(#d <= 160)
    local mixed = FP.Detail("true", {
        { name = "cd", path = SHIPPED, word = "false" },
        { name = "tm", path = "Interface\\AddOns\\Forte_Core\\Fonts\\NOPE.ttf", word = "raised:notfound" },
        { name = "sw", path = nil, word = "nopath" },
    })
    assertTrue(mixed:find("cd=false @" .. SHORT, 1, true) ~= nil, mixed)
    assertTrue(mixed:find("tm=raised:notfound @Forte_Core\\Fonts\\NOPE.ttf", 1, true) ~= nil, mixed)
    assertTrue(mixed:find("sw=nopath @-", 1, true) ~= nil, mixed)
    assertTrue(#mixed <= 160)
    local long = {}
    for i = 1, 12 do long[i] = { name = "d" .. i, path = SHIPPED .. i, word = "false" } end
    assertTrue(#FP.Detail("true", long) <= 160, "clipped")
end)

local FONT_TEST = "frames: the shipped .ttf font object is usable"
local CONTROL_TEST = "frames: font probe control (Blizzard FRIZQT__.TTF SetFont does not raise)"
local RENDERED_TEST = "frames: the shipped font has rendered"

--- Run the frames suite with the probe replaced and the three displays' fontFile set (nil = template fallback).
local function runFonts(stub, path)
    local restore = sandbox()
    local savedProbe = FP.Probe
    FP.Probe = function() return stub end
    local displays = { FX.Cooldown and FX.Cooldown.Display, FX.Timer and FX.Timer.Display,
        FX.Hunter and FX.Hunter.Swing }
    local savedPaths = {}
    for i = 1, 3 do
        if type(displays[i]) == "table" then
            savedPaths[i] = displays[i].fontFile
            displays[i].fontFile = path
        end
    end
    local run = runOne("frames")
    for i = 1, 3 do
        if type(displays[i]) == "table" then displays[i].fontFile = savedPaths[i] end
    end
    FP.Probe = savedProbe
    restore()
    return run
end

test("frames: a font pending its first render (SetFont false) PASSES; the detail says so; 'has rendered' skips", function()
    local run = runFonts(fontStub(ruleNotRenderedYet), SHIPPED)
    assertEquals("pass", find(run, CONTROL_TEST).status, find(run, CONTROL_TEST).detail)
    local t = find(run, FONT_TEST)
    assertEquals("pass", t.status, t.detail)
    assertTrue(t.detail:find("ctl=false; ", 1, true) == 1, t.detail)
    assertTrue(t.detail:find("=false @" .. SHORT, 1, true) ~= nil, t.detail)
    assertTrue(t.detail:find("pending first render", 1, true) ~= nil, t.detail)
    assertTrue(#t.detail <= 160, "detail length " .. #t.detail)
    local r = find(run, RENDERED_TEST)
    assertEquals("skip", r.status)
    assertEquals("pending first render", r.detail)
end)

test("frames: a font that already rendered (SetFont true, GetFont reads the path) passes both checks", function()
    local run = runFonts(fontStub(function() return true end), SHIPPED)
    local t = find(run, FONT_TEST)
    assertEquals("pass", t.status, t.detail)
    assertTrue(t.detail:find("=true @" .. SHORT, 1, true) ~= nil, t.detail)
    local r = find(run, RENDERED_TEST)
    assertEquals("pass", r.status, r.detail)
    assertTrue(r.detail:find(SHORT, 1, true) ~= nil, r.detail)
end)

test("frames: a missing font file is a pcall'd raise: the check FAILS with raised:notfound, not a suite error", function()
    local stub = fontStub(function(path)
        if path == FP.CONTROL_PATH then return true end
        error("FontString:SetFont(): invalid font asset (" .. path .. "): file not found", 0)
    end)
    local run = runFonts(stub, "Interface\\AddOns\\Forte_Core\\Fonts\\NOPE.ttf")
    local t = find(run, FONT_TEST)
    assertEquals("fail", t.status)
    assertTrue(t.detail:find("=raised:notfound @Forte_Core\\Fonts\\NOPE.ttf", 1, true) ~= nil, t.detail)
    assertTrue(t.detail:find("^raise: ") == nil, t.detail)
    assertEquals("skip", find(run, RENDERED_TEST).status)
    assertEquals("pass", find(run, CONTROL_TEST).status)
end)

test("frames: a display that fell back to the template (fontFile nil) FAILS the font check", function()
    local run = runFonts(fontStub(ruleNotRenderedYet), nil)
    local t = find(run, FONT_TEST)
    if FX.Cooldown and FX.Cooldown.Display then
        assertEquals("fail", t.status, t.detail)
        assertTrue(t.detail:find("=nopath @-", 1, true) ~= nil, t.detail)
    end
    assertEquals("skip", find(run, RENDERED_TEST).status)
end)

test("frames: a non-.ttf font path fails the font check", function()
    local run = runFonts(fontStub(ruleNotRenderedYet), "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.otf")
    local t = find(run, FONT_TEST)
    if t.status ~= "skip" then
        assertEquals("fail", t.status)
        assertTrue(t.detail:find("=notttf @", 1, true) ~= nil, t.detail)
    end
end)

test("frames: the control only fails when SetFont raises on Blizzard's font (a false boolean is fine)", function()
    local ok = runFonts(fontStub(ruleNotRenderedYet), SHIPPED)
    assertEquals("pass", find(ok, CONTROL_TEST).status)
    local broken = runFonts(fontStub(function() error("probe dead", 0) end), SHIPPED)
    local c = find(broken, CONTROL_TEST)
    assertEquals("fail", c.status)
    assertTrue(c.detail:find("the probe itself is broken", 1, true) ~= nil, c.detail)
    assertTrue(c.detail:find("SetFont -> raised:probe dead", 1, true) ~= nil, c.detail)
    assertTrue(find(broken, FONT_TEST).detail:find("ctl=raised:probe dead", 1, true) ~= nil, find(broken, FONT_TEST).detail)
end)
