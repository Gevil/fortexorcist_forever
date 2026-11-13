-- dev/Forte_Dev/tests/test_beacon.lua
-- Beacon bit encoding (each cell's colour asserted through the texture API), geometry, repaint on
-- events, the panel (counts, first 12 failures, last 5 errors, off keeps the beacon), /fxdev shot.

local FX = ForteXorcist
local Dev = FX.Dev
local B = Dev.Beacon
local P = Dev.Panel
local S = Dev.Selftest

local function sandbox()
    local saved = { db = _G.ForteDevDB, after = Dev.After, combat = _G.InCombatLockdown, group = _G.IsInGroup,
        shot = _G.Screenshot, errors = FX.db and FX.db.errors, sinceLoad = FX.Errors and FX.Errors.sinceLoad,
        state = {} }
    for k, v in pairs(Dev.state) do saved.state[k] = v end
    _G.ForteDevDB = nil
    Dev.InitDB()
    for k in pairs(Dev.state) do Dev.state[k] = nil end
    Dev.state.panelOn = true
    _G.InCombatLockdown = function() return false end
    _G.IsInGroup = function() return false end
    local timers = {}
    Dev.After = function(sec, fn) timers[#timers + 1] = { sec = sec, fn = fn } end
    return timers, function()
        _G.ForteDevDB = saved.db
        Dev.After = saved.after
        _G.InCombatLockdown, _G.IsInGroup, _G.Screenshot = saved.combat, saved.group, saved.shot
        if FX.db then FX.db.errors = saved.errors end
        if FX.Errors then FX.Errors.sinceLoad = saved.sinceLoad end
        for k in pairs(Dev.state) do Dev.state[k] = nil end
        for k, v in pairs(saved.state) do Dev.state[k] = v end
        Dev.Repaint()
    end
end

local function near(a, b) return math.abs(a - b) < 0.01 end

--- r,g,b of cell i through the texture API.
local function cellColor(i)
    local r, g, b = B.cells[i]:GetVertexColor()
    return r, g, b
end

local function assertCell(i, want, msg)
    local r, g, b = cellColor(i)
    assertTrue(near(r, want[1]) and near(g, want[2]) and near(b, want[3]),
        string.format("%s: cell %d is (%s,%s,%s), want (%s,%s,%s)", msg or "", i, tostring(r), tostring(g),
            tostring(b), want[1], want[2], want[3]))
end

local BLACK, WHITE, MAGENTA, CYAN = { 0, 0, 0 }, { 1, 1, 1 }, { 1, 0, 1 }, { 0, 1, 1 }

local function bitsOf(cols)
    local out = {}
    for i = 1, 14 do out[#out + 1] = (cols[i][1] == 1) and "1" or "0" end
    return table.concat(out)
end

test("encode: markers, flags and the runId low byte (cell 7 = most significant)", function()
    local none = { combat = false, group = false, running = false, finished = false, failed = false, errors = false }
    local all = { combat = true, group = true, running = true, finished = true, failed = true, errors = true }
    local c0 = B.Encode(none, 0)
    assertEquals("00000000000000", bitsOf(c0))
    assertEquals(1, c0[0][1]); assertEquals(0, c0[0][2]); assertEquals(1, c0[0][3])      -- magenta
    assertEquals(0, c0[15][1]); assertEquals(1, c0[15][2]); assertEquals(1, c0[15][3])   -- cyan
    assertEquals("11111110100101", bitsOf(B.Encode(all, 0xA5)))
    assertEquals("00000000000011", bitsOf(B.Encode(none, 259)), "only the low 8 bits count (259 = 0x103)")
    assertEquals("01000000000000", bitsOf(B.Encode({ group = true }, 0)))
    assertEquals("00000000000001", bitsOf(B.Encode(none, 1)))
    assertEquals("00000010000000", bitsOf(B.Encode(none, 128)))
    assertEquals("10000000000000", bitsOf(B.Encode({ combat = true }, 0)))
    assertEquals("00100000000000", bitsOf(B.Encode({ running = true }, 0)))
    assertEquals("00010000000000", bitsOf(B.Encode({ finished = true }, 0)))
    assertEquals("00001000000000", bitsOf(B.Encode({ failed = true }, 0)))
    assertEquals("00000100000000", bitsOf(B.Encode({ errors = true }, 0)))
end)

test("geometry: 16 cells of 6 UI units, 96x6, TOPLEFT of UIParent, strata TOOLTIP, no OnUpdate", function()
    B.Build()
    local f = B.frame
    assertEquals(96, f:GetWidth())
    assertEquals(6, f:GetHeight())
    local point, rel, relPoint, x, y = f:GetPoint()
    assertEquals("TOPLEFT", point)
    assertEquals(UIParent, rel)
    assertEquals("TOPLEFT", relPoint)
    assertEquals(0, x); assertEquals(0, y)
    assertEquals("TOOLTIP", f:GetFrameStrata())
    assertEquals(nil, f:GetScript("OnUpdate"))
    for i = 0, 15 do
        local t = B.cells[i]
        assertEquals("Texture", t:GetObjectType())
        assertEquals(6, t:GetWidth()); assertEquals(6, t:GetHeight())
        local p, r, rp, px = t:GetPoint()
        assertEquals("TOPLEFT", p); assertEquals(f, r); assertEquals(i * 6, px)
    end
    P.Build()
    assertEquals(nil, P.frame:GetScript("OnUpdate"))
end)

test("paint: every cell's colour through the texture API, from a real state", function()
    local _, restore = sandbox()
    _G.InCombatLockdown = function() return true end
    _G.IsInGroup = function() return true end
    if FX.Errors then FX.Errors.sinceLoad = 3 end
    Dev.state.running, Dev.state.finished = true, true
    local db = _G.ForteDevDB
    db.runId = 0x5A
    db.runs = { { id = 0x5A, fail = 2, pass = 0, skip = 0, tests = {} } }
    B.Paint()
    assertCell(0, MAGENTA, "marker")
    assertCell(1, WHITE, "combat")
    assertCell(2, WHITE, "group")
    assertCell(3, WHITE, "running")
    assertCell(4, WHITE, "finished")
    assertCell(5, WHITE, "failed")
    assertCell(6, FX.Errors and WHITE or BLACK, "errors")
    -- 0x5A = 01011010 -> cells 7..14
    local want = { BLACK, WHITE, BLACK, WHITE, WHITE, BLACK, WHITE, BLACK }
    for i = 0, 7 do assertCell(7 + i, want[i + 1], "runId bit") end
    assertCell(15, CYAN, "marker")
    -- and back to quiet
    _G.InCombatLockdown = function() return false end
    _G.IsInGroup = function() return false end
    if FX.Errors then FX.Errors.sinceLoad = 0 end
    Dev.state.running, Dev.state.finished = false, false
    db.runs = { { id = 1, fail = 0, pass = 1, skip = 0, tests = {} } }
    db.runId = 1
    B.Paint()
    for i = 1, 13 do assertCell(i, BLACK, "quiet") end
    assertCell(14, WHITE, "runId 1")
    restore()
end)

test("an armed combat suite keeps the 'running' cell on until it fires", function()
    local timers, restore = sandbox()
    Dev.suites = Dev.suites
    S.Arm()
    assertCell(3, WHITE, "armed = running")
    S.Disarm()
    Dev.Repaint()
    assertCell(3, BLACK, "disarmed")
    restore()
end)

test("a finished failing run lights 'finished' and 'failed' and counts the runId", function()
    local _, restore = sandbox()
    S.RunList({ { name = "t", group = "ooc", fn = function(T) T.check("x", function() T.fail("no") end) end } }, "t")
    assertCell(4, WHITE, "finished")
    assertCell(5, WHITE, "failed")
    assertCell(14, WHITE, "runId 1")
    S.RunList({ { name = "t", group = "ooc", fn = function(T) T.check("x", function() end) end } }, "t")
    assertCell(5, BLACK, "last run clean")
    assertCell(13, WHITE, "runId 2")
    assertCell(14, BLACK, "runId 2")
    restore()
end)

test("repaint on PLAYER_REGEN_*, GROUP_ROSTER_UPDATE", function()
    local _, restore = sandbox()
    Dev.Repaint()
    assertCell(1, BLACK); assertCell(2, BLACK)
    _G.InCombatLockdown = function() return true end
    Dev.HandleEvent("PLAYER_REGEN_DISABLED")
    assertCell(1, WHITE, "combat on")
    _G.InCombatLockdown = function() return false end
    Dev.HandleEvent("PLAYER_REGEN_ENABLED")
    assertCell(1, BLACK, "combat off")
    _G.IsInGroup = function() return true end
    Dev.HandleEvent("GROUP_ROSTER_UPDATE")
    assertCell(2, WHITE, "group on")
    restore()
end)

-- ================================================================ the panel ==

test("panel: stamp, build, suite, counts, the first 12 failures, the last 5 errors", function()
    local _, restore = sandbox()
    S.RunList({ { name = "t", group = "ooc", fn = function(T)
        for i = 1, 15 do T.check("failing test " .. i, function() T.fail("detail " .. i) end) end
        T.check("fine", function() end)
        T.check("skipped", function() T.skip("later") end)
    end } }, "mysuite")
    local list = {}
    for i = 1, 7 do list[i] = { kind = "error", msg = "err number " .. i, count = i, first = 1, last = 2, session = 1 } end
    if FX.db then FX.db.errors = { session = 1, list = list } end
    local text = P.Text()
    restore()
    assertTrue(text:find(Dev.stamp(), 1, true) ~= nil, "stamp")
    assertTrue(text:find("suite mysuite", 1, true) ~= nil, text)
    assertTrue(text:find("pass 1  fail 15  skip 1", 1, true) ~= nil, text)
    assertTrue(text:find("failing test 12:", 1, true) ~= nil, "12th failure listed")
    assertTrue(text:find("failing test 13:", 1, true) == nil, "13th failure NOT listed")
    assertTrue(text:find("+3 more failures", 1, true) ~= nil)
    if FX.db then
        assertTrue(text:find("err number 7", 1, true) ~= nil)
        assertTrue(text:find("err number 3", 1, true) ~= nil)
        assertTrue(text:find("err number 2", 1, true) == nil, "only the last 5")
        assertTrue(text:find("of 7", 1, true) ~= nil)
    end
end)

test("panel: dynamic text is escaped (a pipe never starts a client escape)", function()
    local _, restore = sandbox()
    S.RunList({ { name = "t", group = "ooc", fn = function(T)
        T.check("pipes", function() T.fail("|cffff0000red|r and |T") end)
    end } }, "t")
    local text = P.Text()
    restore()
    assertTrue(text:find("||cffff0000red||r and ||T", 1, true) ~= nil, text)
end)

test("panel off hides the panel and keeps the beacon; on shows it again", function()
    local _, restore = sandbox()
    Dev.Repaint()
    local okOff = Dev.Dispatch("panel off")
    local panelShown, beaconShown = P.frame:IsShown(), B.frame:IsShown()
    local okOn = Dev.Dispatch("panel on")
    local panelBack = P.frame:IsShown()
    restore()
    assertTrue(okOff and okOn)
    assertEquals(false, panelShown)
    assertEquals(true, beaconShown)
    assertEquals(true, panelBack)
end)

-- ==================================================================== shot ==

test("shot: repaint now, Screenshot() on a later frame (0.2 s), once", function()
    local timers, restore = sandbox()
    local calls = 0
    _G.Screenshot = function() calls = calls + 1 end
    _G.IsInGroup = function() return true end
    local ok, detail = Dev.Dispatch("shot")
    local paintedBefore = B.cells[2]:GetVertexColor()
    local callsBefore = calls
    local sec = timers[1] and timers[1].sec
    timers[1].fn()
    local callsAfter = calls
    restore()
    assertTrue(ok, detail)
    assertEquals(0, callsBefore, "no Screenshot in the same frame")
    assertEquals(1, callsAfter)
    assertEquals(0.2, sec)
    assertEquals(1, paintedBefore, "the beacon was repainted before the screenshot was scheduled")
end)

test("shot without Screenshot() answers false", function()
    local _, restore = sandbox()
    _G.Screenshot = nil
    local ok = Dev.Dispatch("shot")
    restore()
    assertEquals(false, ok)
end)
