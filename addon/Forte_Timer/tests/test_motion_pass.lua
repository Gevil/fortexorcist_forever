-- addon/Forte_Timer/tests/test_motion_pass.lua
-- PLAN §11.13 S2/S4: the Spell Timer's MOTION PASS. The rows' bar value, the
-- spark, the arrival-flash / blink colour and the fade ramp (with the group
-- alpha that follows it) move on EVERY rendered frame from an OnUpdate on the
-- shown anchor; the ticker's full `Draw` keeps everything else.
--
-- Every measurement drives the REAL frame script: `D.anchor:GetScript(
-- "OnUpdate")` is fetched and called once per simulated frame with the global
-- `GetTime` stubbed to that frame's wall clock (the renderer's one clock, the
-- way test_perf_gates.lua stubs it), and the full pass is `Module:Draw` (the
-- ticker's body; a headless ticker never fires).
--
-- FAILS-ON-THE-OLD-CODE: before the motion pass the anchor carried no
-- OnUpdate (`GetScript` returned nil), so the first test's fetch asserts.

local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Casts = FX.Timer.Casts
local D = FX.Timer.Display

local realGetTime = _G.GetTime
local clockNow

--- One wall clock for the renderer (global GetTime) and the module (the
--- injectable cast clock, which the sort and the fade gate ride).
local function setTime(t)
    clockNow = t
    _G.GetTime = function() return clockNow end
    Casts.now = function() return clockNow end
end

local function ensureEnabled()
    if not M.options then M:OnEnable() end
    assertNotNil(D.anchor, "the display is built")
    local o = M.options
    o.enable, o.hide, o.flip = true, false, false
    return o
end

local function slotOf(row)
    for s = 1, #D.rows do
        if D.rows[s]._row == row then return D.rows[s], s end
    end
    return nil
end

--- One live self row of `dur` seconds born at `base`, the full pass run until
--- the scale ease has settled (it relaxes per Draw), at the clock `base`.
local function seedOne(base, dur)
    setTime(base)
    Rows:Clear()
    Rows:InsertFromCast("MotionRow", "none", dur, base, base, 1, "Magic")
    assertEquals(1, Rows:Count())
    for _ = 1, 60 do M:Draw() end
    local row = Rows.rows[1]
    assertNotNil(row)
    local r = slotOf(row)
    assertNotNil(r, "the row is bound to a pool slot")
    return row, r
end

--- The frame script, fetched fresh from the anchor each time (the test is
--- about what the client would run).
local function frame(t)
    setTime(t)
    local fn = D.anchor:GetScript("OnUpdate")
    assertNotNil(fn, "the shown anchor carries the motion OnUpdate")
    fn(D.anchor, 1 / 165)
end

local function near(a, b, tol, label)
    assertTrue(math.abs(a - b) <= tol, string.format(
        "%s: %.9f vs %.9f", label or "value", a, b))
end

local function sparkX(r)
    local _, _, _, x = r.spark:GetPoint(1)
    return x
end

-- ---------------------------------------------------- arming and idleness --

test("the motion OnUpdate is installed while a row is live, removed when idle or hidden",
function()
    local o = ensureEnabled()
    D:RenderIdle()
    assertNil(D.anchor:GetScript("OnUpdate"), "nothing moves: no per-frame Lua")
    local base = realGetTime()
    seedOne(base, 30)
    assertTrue(D.anchor:IsShown(), "the full pass shows the anchor")
    assertNotNil(D.anchor:GetScript("OnUpdate"), "a row moves: the pass runs")
    -- arming is idempotent: the same closure stays installed
    local first = D.anchor:GetScript("OnUpdate")
    M:Draw()
    assertTrue(first == D.anchor:GetScript("OnUpdate"), "one stable closure")

    -- the last row gone: the next full pass removes the script
    Rows:Clear()
    M:Draw()
    assertNil(D.anchor:GetScript("OnUpdate"), "no live row: no OnUpdate")

    -- hidden panel: RenderIdle removes it
    seedOne(base, 30)
    assertNotNil(D.anchor:GetScript("OnUpdate"))
    o.hide = true
    D:RenderIdle()
    assertNil(D.anchor:GetScript("OnUpdate"), "hidden panel: no OnUpdate")
    assertFalse(D.anchor:IsShown())
    o.hide = false

    -- a zero-total row has no timeline: nothing moves, nothing installed
    setTime(base)
    Rows:Clear()
    Rows:InsertFromCast("StaticRow", "none", 30, base, base, 1, "Magic")
    Rows.rows[1].total = 0
    M:Draw()
    assertNil(D.anchor:GetScript("OnUpdate"), "a static row does not arm it")
    Rows:Clear()
    M:Draw()
end)

-- ------------------------------------------------------- per-frame motion --

test("165 consecutive frames: the bar value and the spark change on EVERY frame, in equal steps",
function()
    ensureEnabled()
    local base = realGetTime()
    local row, r = seedOne(base, 30)
    row.drawExpireAt = base + 20
    M:Draw()
    local o = M.options
    local prevV, prevX, prevStep, prevSteps
    for i = 1, 165 do
        local t = base + i / 165
        frame(t)
        local v = r.bar:GetValue()
        near(v, (row.drawExpireAt - t) / row.maxTime, 1e-6, "bar value")
        local x = sparkX(r)
        near(x, v * o.barWidth, 1e-3, "spark offset")
        if prevV then
            assertTrue(v < prevV, "bar value moved on frame " .. i)
            assertTrue(x < prevX, "spark moved on frame " .. i)
            local step = prevV - v
            if prevStep then
                near(step, prevStep, 1e-6 * prevStep + 1e-9, "equal step")
            end
            prevStep = step
        end
        prevV, prevX = v, x
    end
    assertEquals(1, r.spark:GetNumPoints(), "the spark keeps ONE anchor point")
    Rows:Clear()
    M:Draw()
end)

test("the mirrored (flip) fill and its spark move on every frame too",
function()
    local o = ensureEnabled()
    local base = realGetTime()
    local row, r = seedOne(base, 30)
    row.drawExpireAt = base + 20
    o.flip = true
    M:Draw()
    local prevW
    for i = 1, 60 do
        local t = base + i / 165
        frame(t)
        local v = (row.drawExpireAt - t) / row.maxTime
        local fw = r.fill:GetWidth()
        near(fw, v * o.barWidth, 1e-3, "mirrored fill width")
        near(sparkX(r), (1 - v) * o.barWidth, 1e-3, "mirrored spark")
        if prevW then assertTrue(fw < prevW, "fill moved on frame " .. i) end
        prevW = fw
    end
    o.flip = false
    Rows:Clear()
    M:Draw()
end)

test("identical final positions for the same wall-clock span at 30, 60, 165 and 240 fps",
function()
    ensureEnabled()
    local base = realGetTime()
    local row, r = seedOne(base, 30)
    row.drawExpireAt = base + 20
    M:Draw()
    local want = (row.drawExpireAt - (base + 1)) / row.maxTime
    local results = {}
    for _, fps in ipairs({ 30, 60, 165, 240 }) do
        for i = 0, fps do frame(base + i / fps) end
        results[#results + 1] = r.bar:GetValue()
        near(r.bar:GetValue(), want, 1e-6, fps .. " fps")
    end
    for i = 2, #results do near(results[i], results[1], 1e-9, "fps parity") end
    -- and after a hitch (one 0.4 s frame) the position is exact, not lagged
    frame(base + 1.4)
    near(r.bar:GetValue(), (row.drawExpireAt - (base + 1.4)) / row.maxTime,
        1e-6, "after a hitch")
    Rows:Clear()
    M:Draw()
end)

-- ------------------------------------------------- one formula, both passes --

test("the full pass and the motion pass agree at the same instant (no jump, no step back)",
function()
    local o = ensureEnabled()
    local base = realGetTime()
    for _, flip in ipairs({ false, true }) do
        o.flip = flip
        local row, r = seedOne(base, 30)
        row.drawExpireAt = base + 20
        local t = base + 3.1
        setTime(t)
        M:Draw()
        local fullV, fullW, fullX = r.bar:GetValue(), r.fill:GetWidth(),
            sparkX(r)
        local fullR, fullG, fullB = r._fillR, r._fillG, r._fillB
        frame(t)
        near(r.bar:GetValue(), fullV, 1e-9, "bar value")
        near(r.fill:GetWidth(), fullW, 1e-9, "mirrored width")
        near(sparkX(r), fullX, 1e-3, "spark")
        assertEquals(fullR, r._fillR)
        assertEquals(fullG, r._fillG)
        assertEquals(fullB, r._fillB)
        -- the next frame only ever moves forward
        frame(t + 1 / 165)
        if flip then
            assertTrue(r.fill:GetWidth() < fullW)
        else
            assertTrue(r.bar:GetValue() < fullV)
        end
    end
    o.flip = false
    Rows:Clear()
    M:Draw()
end)

test("the arrival flash fades per frame, and the blink pulse moves the background per frame",
function()
    ensureEnabled()
    local base = realGetTime()
    local row, r = seedOne(base, 30)
    -- seedOne's draws ran at `base`: the row was just born, white -> kind
    local pr, pg, pb
    for i = 1, 40 do
        local t = base + i / 165          -- 0.006 s .. 0.24 s of the 0.5 s flash
        frame(t)
        local wr, wg, wb = Laws.ColorVal(row.drawExpireAt - t, row.total,
            row.state, row.kind, M.skin, M.options)
        near(r._fillR, wr, 1e-9, "arrival flash red at frame " .. i)
        near(r._fillG, wg, 1e-9, "arrival flash green at frame " .. i)
        near(r._fillB, wb, 1e-9, "arrival flash blue at frame " .. i)
        if pr then
            if r._fillR == pr and r._fillG == pg and r._fillB == pb then
                error(string.format("flash stepped on frame %d (kind %s total"
                    .. " %s expire-base %s state %s rgb %.3f %.3f %.3f)", i,
                    tostring(row.kind), tostring(row.total),
                    tostring(row.drawExpireAt - base), tostring(row.state),
                    r._fillR, r._fillG, r._fillB))
            end
        end
        pr, pg, pb = r._fillR, r._fillG, r._fillB
    end
    -- the blink band: the last 3 s pulse the background alpha every frame
    row.drawExpireAt = base + 2
    M:Draw()
    local changed, prevA = 0, nil
    for i = 1, 60 do
        local t = base + 0.5 + i / 165
        frame(t)
        if prevA and r._bgA ~= prevA then changed = changed + 1 end
        prevA = r._bgA
    end
    assertTrue(changed >= 55, "the blink pulse moved on " .. changed
        .. " of 59 frames")
    Rows:Clear()
    M:Draw()
end)

test("the fade ramp and the group alpha that follows it move per frame",
function()
    local o = ensureEnabled()
    local base = realGetTime()
    local row, r = seedOne(base, 30)
    row.state = Laws.FADING_INSTANT
    row.removeAt = base
    setTime(base)
    M:Draw()                              -- caches the fading state, vis 1
    local g = D.groups[1]
    local prevA
    for i = 1, 60 do
        local t = base + i / 165          -- inside the 0.5 s cubic fall
        frame(t)
        local want = Laws.Alpha(base, t) * (o.normalAlpha or M.skin.NormalAlpha)
        near(g.frame:GetAlpha(), want, 1e-4, "group alpha at frame " .. i)
        near(r.bar:GetHeight(), o.height * Laws.Alpha(base, t), 0.02,
            "bar height rides the ramp")
        if prevA then
            assertTrue(g.frame:GetAlpha() < prevA, "fade stepped on frame " .. i)
        end
        prevA = g.frame:GetAlpha()
    end
    Rows:Clear()
    M:Draw()
end)

-- ------------------------------------------------- what the motion pass is not --

test("motion frames never run the full pass or touch text, widths or layout",
function()
    ensureEnabled()
    local base = realGetTime()
    local row, r = seedOne(base, 30)
    row.drawExpireAt = base + 20
    M:Draw()
    local c = D.counts
    local before = {}
    for k, v in pairs(c) do before[k] = v end
    local realUpdate, realDraw = D.Update, M.Draw
    local updates, draws = 0, 0
    D.Update = function(...) updates = updates + 1 return realUpdate(...) end
    M.Draw = function(...) draws = draws + 1 return realDraw(...) end
    for i = 1, 165 do frame(base + i / 165) end
    D.Update, M.Draw = realUpdate, realDraw
    assertEquals(0, updates, "the full pass is not run per frame")
    assertEquals(0, draws)
    assertEquals(165, c.motionPass - before.motionPass)
    assertEquals(165, c.motionRows - before.motionRows)
    for _, key in ipairs({ "anchorGroup", "anchorRow", "anchorLabel",
        "anchorTicks", "sizeGroup", "geometry", "timeText", "nameText",
        "spark" }) do
        assertEquals(before[key], c[key], key .. " is the full pass's")
    end
    Rows:Clear()
    M:Draw()
end)

test("a motion pass allocates nothing (no table, no closure)",
function()
    ensureEnabled()
    local base = realGetTime()
    local row, r = seedOne(base, 30)
    row.drawExpireAt = base + 20
    for _, flip in ipairs({ false, true }) do
        M.options.flip = flip
        M:Draw()
        for i = 1, 20 do frame(base + i / 165) end   -- warm every path
        collectgarbage("stop")
        collectgarbage("count")
        local g0 = collectgarbage("count")
        local fn = D.anchor:GetScript("OnUpdate")
        for i = 1, 1000 do
            clockNow = base + 1 + i / 165
            fn(D.anchor, 1 / 165)
        end
        local g1 = collectgarbage("count")
        collectgarbage("restart")
        assertEquals(0, g1 - g0, (flip and "mirrored" or "plain")
            .. " motion pass allocated " .. ((g1 - g0) * 1024) .. " bytes")
    end
    M.options.flip = false
    Rows:Clear()
    M:Draw()
end)

-- the cleanup test: no teardown hook, so the last test restores the world
test("motion tests leave the panel idle and the clock restored", function()
    M.options.flip = false
    Rows:Clear()
    Casts.now = nil
    _G.GetTime = realGetTime
    M:Draw()
    D:RenderIdle()
    assertNil(D.anchor:GetScript("OnUpdate"))
end)
