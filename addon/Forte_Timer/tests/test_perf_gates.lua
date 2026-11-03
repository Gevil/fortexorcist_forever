-- addon/Forte_Timer/tests/test_perf_gates.lua
-- The gate for docs/perf.md §4 fixes 2-5, measured on the panel's own 25 Hz
-- tick body:
--   * the time and name texts ride numeric display keys, so `string.format`
--     and the `NameText` concats run when the SHOWN value changes and not per
--     tick (fix 2);
--   * geometry is touched on a layout change only: bars, group boxes, headers
--     and the static tick marks keep their positions across ticks, while the
--     bar spark is re-anchored every pass (fix 3);
--   * the aura sweep allocates on its readers, not on itself (fix 4);
--   * `Rows:Sorted` hands table.sort a hoisted comparator, so a pass creates
--     zero closures, and it orders exactly as `Laws.CompareLinks` prescribes
--     (fix 5).
--
-- The evidence seams are `FX.Timer.Display.counts` (how many times a pass
-- APPLIED a geometry, an anchoring or a text) and a counted stand-in for
-- `Laws.TimeText`/`Laws.NameText` (the only paths to the panel's
-- `string.format`s). `Forte_Timer/Core/Reconcile.lua`'s `counts.reads` is the
-- same pattern for the aura law.
--
-- Every measurement drives the PUBLIC tick body (`Module:Draw`, the ticker's
-- body; `Reconcile:SweepAll`) with the module's injectable clock, as
-- Forte_Timer/tests/test_module.lua does: no test relies on a ticker firing
-- (the headless sim never fires a C_Timer.NewTicker callback) and none reaches
-- for a private render helper.
--
-- FAILS-ON-THE-OLD-CODE (PLAN §11.1): on the pre-fix renderer `D.counts` does
-- not exist (the first access raises), the text counters read one format per
-- row per pass (20, not 0), the group/row/label/tick anchors rise by one per
-- group and per row per pass (40, not 0), `Rows:Sorted` allocates the
-- comparator closure (docs/perf.md §6 "before": 168 B/call) and the sweep
-- allocates one closure per aura read (§1: 15.2 KB per call).
-- `Forte_Timer/Core/Reconcile.lua`, `Core/Rows.lua` and `UI/Rows.lua` were
-- reverted to their pre-fix bodies on 2026-11-02 (each seam's revert run on
-- its own, and all together) and this file failed on them.

local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Casts = FX.Timer.Casts
local Reconcile = FX.Timer.Reconcile
local D = FX.Timer.Display

local function nearpx(actual, expected)
    assertTrue(math.abs(actual - expected) <= 0.5)
end

local clock
local function installClock(base)
    clock = { base }
    Casts.now = function() return clock[1] end
    return clock
end

--- The rows' windows ride the RENDERER's clock: `Display:Update` reads
--- `GetTime()` for the times and the fills (only the sort, the gates and the
--- logic cadence ride the module's injectable clock).
local function epoch()
    return GetTime()
end

local function ensureEnabled()
    if not M.options then M:OnEnable() end
    assertNotNil(D.anchor, "the display is built")
    assertNotNil(D.counts, "the renderer carries its counted seams")
    local o = M.options
    o.enable, o.hide = true, false
    return o
end

--- The clock a text or geometry test measures. `Display:Update` reads the
--- global `GetTime()` for the times, the fills and the spark (the module's
--- injectable clock reaches the sort, the gates and the logic cadence), and
--- the sim's `GetTime` advances in WHOLE seconds — a 40-pass measurement body
--- crosses a second boundary, which is a shown value changing under the test.
--- The suite's law is an injected clock, so the test injects the one clock the
--- renderer has: the global, stubbed for the body and restored around it (the
--- `_G.InCombatLockdown` stub of test_rows.lua:757 is the precedent).
local function withFixedClock(base, body)
    local saved = _G.GetTime
    _G.GetTime = function() return base end
    local ok, err = pcall(body)
    _G.GetTime = saved
    assertEquals(ok and "ok" or tostring(err), "ok")
end

--- The GC byte counter of docs/perf.md: `collectgarbage("count")` counts
--- KILOBYTES in this LuaJIT, so the delta times 1024 is bytes per call.
local gcBytes
if type(collectgarbage) == "function" then
    gcBytes = function(n, fn)
        collectgarbage("count")
        local g0 = collectgarbage("count")
        for _ = 1, n do fn() end
        return (collectgarbage("count") - g0) * 1024 / n
    end
end

local function assertBelow(label, value, ceiling)
    assertTrue(value < ceiling, string.format(
        "%s measured %.0f, ceiling %.0f", label, value, ceiling))
end

--- `n` live rows, each with `dur` seconds of window. Two fake targets by
--- default (the group runs are part of what the draw pass lays out); pass
--- `"none"` for self rows, which is the shape `Reconcile:SweepAll` walks.
local function seed(n, base, dur, targetKey)
    Rows:Clear()
    for i = 1, n do
        Rows:InsertFromCast("PerfRow" .. i,
            targetKey or ((i % 2 == 0) and "Dummy-1" or "Dummy-2"),
            dur, base + dur, base, 1, "Magic")
    end
    assertEquals(n, Rows:Count())
end

--- The row's remaining time, set through the smoothed value the renderer
--- draws — the only input of the time column a test needs to move.
local function remaining(i, base, secs)
    local row = Rows.rows[i]
    assertNotNil(row)
    row.drawExpireAt = base + secs
    return row
end

--- The POOL slot that carries `Rows.rows[i]`: the pool's order is the SORTED
--- order, so a test that wants one specific row's strings asks the row, not
--- the index. `BindRow` stamps `_row` on every live slot.
local function slotOf(i)
    local row = Rows.rows[i]
    for s = 1, #D.rows do
        if D.rows[s]._row == row then return D.rows[s] end
    end
    return nil
end

--- The counter set, snapshotted and compared.
local function snapshot()
    local c, out = D.counts, {}
    for k in pairs(c) do out[k] = c[k] end
    return out
end
local function moved(before, key)
    return D.counts[key] - before[key]
end
local function assertStatic(before, key)
    assertEquals(0, moved(before, key), key .. " was applied "
        .. moved(before, key) .. " times by a steady pass")
end
local function assertMoved(before, key)
    assertTrue(D.counts[key] > before[key],
        key .. " did not move on a layout change")
end

--- Runs `body(counts)` with `Laws.<fn>` replaced by a counting stand-in.
local function counting(fnName, body)
    local real = Laws[fnName]
    local c = { n = 0 }
    Laws[fnName] = function(...)
        c.n = c.n + 1
        return real(...)
    end
    local ok, err = pcall(body, c)
    Laws[fnName] = real
    assertEquals(ok and "ok" or tostring(err), "ok")
    return c.n
end

local function cleanUp(o)
    if o then
        o.maxOn, o.ticks = true, true
        o.showStacks = true
    end
    Rows:Clear()
    installClock(epoch())
    Casts.now = nil
    M:Draw()
end

-- ------------------------------------------------- fix 2: the time column --

test("a steady pass formats NO time text while the shown value is unchanged",
function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        seed(1, base, 12)
        remaining(1, base, 6)
        M:Draw()
        assertEquals("6.0", D.rows[1].timeFS:GetText())
        -- 20 passes on an unmoved clock: the shown string is "6.0" every
        -- time, so neither the law (`Laws.TimeText` -> `string.format`) nor
        -- the two setters run. The pre-fix pass formatted once per row per
        -- pass = 20.
        local formats = counting("TimeText", function(c)
            local before = snapshot()
            for _ = 1, 20 do M:Draw() end
            assertStatic(before, "timeText")
            assertEquals(0, c.n, "20 steady passes formatted " .. c.n)
        end)
        assertEquals(0, formats)
        assertEquals("6.0", D.rows[1].timeFS:GetText())
    end)
    cleanUp(o)
end)

test("a row's time text updates when the displayed second changes", function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        seed(1, base, 600)
        remaining(1, base, 300)
        M:Draw()
        assertEquals("5:00", D.rows[1].timeFS:GetText())
        -- A half-second of window lost: the SHOWN second did not change.
        local formats = counting("TimeText", function(c)
            local before = snapshot()
            remaining(1, base, 300.1)     -- still "5:00"
            M:Draw()
            assertEquals(0, c.n, "a sub-second step formatted " .. c.n)
            assertStatic(before, "timeText")
        end)
        assertEquals(0, formats)
        assertEquals("5:00", D.rows[1].timeFS:GetText())
        -- The shown second changes: the text follows, once.
        formats = counting("TimeText", function(c)
            local before = snapshot()
            remaining(1, base, 298.4)
            M:Draw()
            assertEquals(1, c.n, "the crossed second formatted " .. c.n)
            assertMoved(before, "timeText")
        end)
        assertEquals(1, formats)
        assertEquals("4:58", D.rows[1].timeFS:GetText())
    end)
    cleanUp(o)
end)

test("the sub-minute band keys tenths, the shown precision", function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        seed(1, base, 12)
        remaining(1, base, 6)
        M:Draw()
        assertEquals("6.0", D.rows[1].timeFS:GetText())
        -- A step that does NOT cross the printed tenth stays silent.
        local formats = counting("TimeText", function(c)
            remaining(1, base, 5.96)          -- prints "6.0"
            M:Draw()
            assertEquals(0, c.n, "a sub-tenth step formatted " .. c.n)
        end)
        assertEquals(0, formats)
        assertEquals("6.0", D.rows[1].timeFS:GetText())
        -- A printed tenth crossing: one format, one SetText.
        formats = counting("TimeText", function(c)
            remaining(1, base, 5.9)          -- prints "5.9"
            M:Draw()
            assertEquals(1, c.n, "the crossed tenth formatted " .. c.n)
        end)
        assertEquals(1, formats)
        assertEquals("5.9", D.rows[1].timeFS:GetText())
    end)
    cleanUp(o)
end)

test("each row of a stack rides its own key", function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        seed(5, base, 600)
        for i = 1, 5 do remaining(i, base, 300) end
        M:Draw()
        local formats = counting("TimeText", function(c)
            for _ = 1, 10 do M:Draw() end
            assertEquals(0, c.n,
                "10 steady passes over 5 rows formatted " .. c.n)
            for i = 1, 5 do remaining(i, base, 299) end
            M:Draw()
            assertEquals(5, c.n,
                "one crossed second over 5 rows formatted " .. c.n)
        end)
        assertEquals(5, formats)
        assertEquals("4:59", D.rows[1].timeFS:GetText())
        assertEquals("4:59", D.rows[5].timeFS:GetText())
    end)
    cleanUp(o)
end)

test("the constant texts ride sentinels, not the numeric keys", function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        -- The fail band: the word "gone", applied once and then carried.
        seed(1, base, 12)
        local row = remaining(1, base, 6)
        M:Draw()
        assertEquals("6.0", D.rows[1].timeFS:GetText())
        local formats = counting("TimeText", function(c)
            row.state = Laws.FAILED
            row.removeAt = base + 900
            M:Draw()
            assertEquals(1, c.n, "the fail band formatted " .. c.n)
            for _ = 1, 10 do M:Draw() end
            assertEquals(1, c.n, "the fail band re-formatted " .. c.n)
        end)
        assertEquals(1, formats)
        assertEquals("gone", D.rows[1].timeFS:GetText())
        Rows:Clear()
        M:Draw()
        -- A zero-total row is the other constant, on a key no live value can
        -- reach (the sentinels sit below every numeric key).
        Rows:InsertFromCast("PerfRow1", "none", 12, base + 12, base, 1, "Magic")
        local zrow = remaining(1, base, 6)
        M:Draw()
        assertEquals("6.0", D.rows[1].timeFS:GetText())
        zrow.total = 0
        M:Draw()
        assertEquals("", D.rows[1].timeFS:GetText())
    end)
    cleanUp(o)
end)

-- ------------------------------------------------- fix 2: the name column --

test("the name text rebuilds only when one of its inputs changes", function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        seed(4, base, 12)
        for i = 1, 4 do remaining(i, base, 6) end
        M:Draw()
        local slot = slotOf(1)
        assertNotNil(slot, "the pass bound a slot to row 1")
        assertEquals("Dummy-2", slot.nameFS:GetText())
        counting("NameText", function(c)
            local before = snapshot()
            for _ = 1, 20 do M:Draw() end
            assertEquals(0, c.n, "20 steady passes rebuilt " .. c.n .. " names")
            assertStatic(before, "nameText")
            -- One row's stacks: exactly that row's name is rebuilt.
            c.n = 0
            Rows.rows[1].stacks = 3
            M:Draw()
            assertEquals(1, c.n, "a stacks change rebuilt " .. c.n)
            -- The option that gates the suffix: every row of the stack.
            c.n = 0
            o.showStacks = false
            M:Draw()
            assertEquals(4, c.n,
                "the stacks switch rebuilt " .. c.n .. " of 4 names")
        end)
        assertEquals("Dummy-2", slot.nameFS:GetText())
        o.showStacks = true
        M:Draw()
        assertEquals("Dummy-2 (3)", slot.nameFS:GetText())
        Rows.rows[1].stacks = 0
    end)
    cleanUp(o)
end)

-- ------------------------------------------------------- fix 3: geometry --

local function rectOf(f)
    return { x = f:GetLeft(), y = f:GetBottom(),
        w = f:GetWidth(), h = f:GetHeight() }
end

local function assertShape(label, a, b)
    assertEquals(#a, #b, label .. ": the shown count changed")
    for i = 1, #a do
        nearpx(a[i].x, b[i].x)
        nearpx(a[i].y, b[i].y)
        nearpx(a[i].w, b[i].w)
        nearpx(a[i].h, b[i].h)
    end
end

--- The live options with `height` replaced, for a law-side expectation.
local function tallOpts(o, height)
    local copy = {}
    for k, v in pairs(o) do copy[k] = v end
    copy.height = height
    return copy
end

test("rows, boxes and headers keep their positions across ticks", function()
    local o = ensureEnabled()
    -- The layout this test measures, pinned (the settings tests that ran
    -- before own the stored values, not this one).
    local saved = { maxOn = o.maxOn, ticks = o.ticks, groupID = o.groupID,
        outwands = o.outwands, label = o.label, showTarget = o.showTarget }
    o.maxOn, o.ticks = false, false
    o.groupID, o.outwands = true, true
    o.label, o.showTarget = true, true
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        seed(6, base, 120)
        for i = 1, 6 do remaining(i, base, 60) end
        M:Draw()
        -- The rects keyed by the ROW they draw, not by the pool slot: the
        -- pool's slot order is the sorted order, so a slot carries a
        -- different row from pass to pass.
        local function bars()
            local out = {}
            for s = 1, #D.rows do
                local slot, row = D.rows[s], D.rows[s]._row
                if row and slot.bar:IsShown() then
                    out[#out + 1] = { id = row.spell or "", r = rectOf(slot.bar) }
                end
            end
            table.sort(out, function(a, b) return a.id < b.id end)
            return out
        end
        local function rects(list)
            local out = {}
            for i = 1, #list do out[i] = list[i].r end
            return out
        end
        local shapes = bars()
        assertEquals(6, #shapes, "six bars are shown")
        -- 40 passes with the fills and the times running (each pass shortens
        -- every row's window). Every geometry seam must stay untouched, which
        -- is the mechanical proof that no bar, box or header moved: the only
        -- code that puts a bar, a box or a header anywhere on the panel is
        -- the geometry, the anchoring and the sizing the counters pin at zero.
        local before = snapshot()
        local sparkBefore = D.counts.spark
        for i = 1, 40 do
            for k = 1, 6 do
                Rows.rows[k].drawExpireAt = base + 60 - i * 0.04
            end
            M:Draw()
        end
        assertStatic(before, "anchorGroup")
        assertStatic(before, "anchorRow")
        assertStatic(before, "anchorLabel")
        assertStatic(before, "anchorTicks")
        assertStatic(before, "sizeGroup")
        assertStatic(before, "geometry")
        local after = bars()
        assertEquals(#shapes, #after, "the shown bars changed")
        for i = 1, #shapes do
            assertEquals(shapes[i].id, after[i].id, "the row in slot " .. i)
            assertShape("bars", { shapes[i].r }, { after[i].r })
        end
        -- The bar spark is the element that MUST keep moving: it rides the
        -- fill, so it is re-anchored once per live bar per pass, all 40
        -- passes through (240), while NOTHING else is anchored.
        assertEquals(40 * 6, D.counts.spark - sparkBefore,
            "the bar spark moved " .. (D.counts.spark - sparkBefore)
            .. " times in 40 passes of 6 rows")
        local sp0 = D.counts.spark
        for k = 1, 6 do
            Rows.rows[k].drawExpireAt = base + 40
        end
        M:Draw()
        assertEquals(6, D.counts.spark - sp0,
            "the bar spark stopped riding the fill")
        -- A LAYOUT change re-anchors: the page's own height writer, the
        -- option path that recomputes barWidth/barInset and invalidates the
        -- geometry caches.
        local h = o.height
        local bar0 = rectOf(D.rows[1].bar)
        -- `Layouts.Compute`'s own arithmetic: a row of `Height` carries
        -- BarHeight = (Height - Header - TopInset - 2*(Border+RowGap)) / 2,
        -- so +6 of row height is +3 of bar height (docs/perf.md §5's row:
        -- Height 22 -> 28 moves BarHeight 15 -> 18).
        M:SetHeight(h + 6)
        M:Draw()
        assertMoved(before, "geometry")
        assertMoved(before, "anchorGroup")
        assertMoved(before, "anchorRow")
        assertMoved(before, "anchorLabel")
        assertMoved(before, "sizeGroup")
        local bar1 = rectOf(D.rows[1].bar)
        -- The witness that a LAYOUT change reaches the geometry: the bar's
        -- box moves off its old size. The profile's exact arithmetic is
        -- `Forte_Timer/tests/test_rows.lua`'s geometry tests' subject.
        assertTrue(bar1.h ~= bar0.h and bar1.h > 0,
            "a height change did not reach the bar geometry")
        M:SetHeight(h)
        M:Draw()
    end)
    for k, v in pairs(saved) do o[k] = v end
    cleanUp(o)
end)

test("the tick marks are laid out on a layout change, not every tick",
function()
    local o = ensureEnabled()
    local saved = { maxOn = o.maxOn, ticks = o.ticks,
        ticksNext = o.ticksNext }
    -- This test measures the mark LAYOUT, which is the whole-schedule mode;
    -- `TicksNext` (:3404, the shipped default true) shows one mark at a time,
    -- which would read "zero marks on row 1" here and measure nothing.
    o.maxOn, o.ticks = false, true
    o.ticksNext = false
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        seed(3, base, 120)
        local function freeze()
            for i = 1, 3 do
                local row = remaining(i, base, 60)
                row.tickEvery = 3
                -- A frozen scale: `Rows:Sorted`'s band easing moves maxTime,
                -- and a moving scale legitimately re-lays the marks.
                row.maxTime = 60
            end
        end
        freeze()
        M:Draw()
        local marks = 0
        local shapes = {}
        for i = 1, #D.rows do
            local tk = D.rows[i].ticks[1]
            if tk and tk:IsShown() then
                marks = marks + 1
                shapes[#shapes + 1] = rectOf(tk)
            end
        end
        assertEquals(3, marks, "the tick marks are on for the 3 rows")
        local before = snapshot()
        for i = 1, 30 do
            clock[1] = base + i * 0.04
            freeze()
            M:Draw()
        end
        assertStatic(before, "anchorTicks")
        local after = {}
        for i = 1, #D.rows do
            local tk = D.rows[i].ticks[1]
            if tk and tk:IsShown() then after[#after + 1] = rectOf(tk) end
        end
        assertShape("tick marks", shapes, after)
        -- The data's schedule moving IS a layout change for the marks.
        before = snapshot()
        for i = 1, 3 do Rows.rows[i].tickEvery = 4 end
        M:Draw()
        assertMoved(before, "anchorTicks")
        for i = 1, 3 do Rows.rows[i].tickEvery = 3 end
    end)
    for k, v in pairs(saved) do o[k] = v end
    cleanUp(o)
end)

-- -------------------------------------------------- fix 5: the comparator --

--- The CPU counter of docs/perf.md: seconds per call, times 1e6.
local function cpuUsPerCall(n, fn)
    local c0 = os.clock()
    for _ = 1, n do fn() end
    return (os.clock() - c0) * 1e6 / n
end

test("the zero-row sort pass costs the hoisted comparator's time", function()
    local o = ensureEnabled()
    local base = epoch()
    installClock(base)
    Rows:Clear()
    -- docs/perf.md §6, 0 rows, per call: 3.9 us with the comparator closure
    -- built per call (the pre-fix `Rows:Sorted`), 2.4 us with `compareLinks`
    -- hoisted to module scope. The ceiling is between the two.
    --
    -- The GC byte counter is NOT the seam for this one: a closure whose
    -- upvalues are loop-invariant is hoisted out of the call by this LuaJIT's
    -- compiler, so the bytestream reads the same at 0 rows on both builds.
    -- Time is the seam that sees the cost the interpreter charges for it.
    local out = {}
    local us = 0
    for _ = 1, 3 do
        cpuUsPerCall(20000, function() Rows:Sorted(out, base) end)
        us = cpuUsPerCall(20000, function() Rows:Sorted(out, base) end)
    end
    assertTrue(us < 3.4, string.format(
        "the 0-row sort pass costs %.2f us/call, ceiling 3.40 "
        .. "(pre-fix 3.90, hoisted 2.40)", us))
    cleanUp(o)
end)

test("the hoisted comparator orders exactly as the law prescribes", function()
    local o = ensureEnabled()
    local base = epoch()
    installClock(base)
    local groupID, outwands = o.groupID, o.outwands
    for _, gi in ipairs({ true, false }) do
        for _, ow in ipairs({ true, false }) do
            o.groupID, o.outwands = gi, ow
            seed(9, base, 120)
            for i = 1, 9 do remaining(i, base, 60 - i * 3) end
            local links, n = Rows:Sorted({}, base)
            assertEquals(9, n)
            local want = {}
            for k = 1, n do want[k] = links[k] end
            table.sort(want, function(a, b)
                return Laws.CompareLinks(a, b, gi, ow)
            end)
            for k = 1, n do
                assertEquals(want[k][1], links[k][1], string.format(
                    "groupID=%s outwands=%s slot %d", tostring(gi),
                    tostring(ow), k))
            end
        end
    end
    o.groupID, o.outwands = groupID, outwands
    cleanUp(o)
end)

test("the comparator's option pair is refreshed by every pass", function()
    local o = ensureEnabled()
    local base = epoch()
    installClock(base)
    local groupID, outwands = o.groupID, o.outwands
    o.groupID, o.outwands = false, false
    Rows:Sorted({}, base)
    local g, w = Rows:SortOptions()
    assertEquals(false, g, "grouping rides the live option")
    assertEquals(false, w, "outwands rides the live option")
    o.groupID, o.outwands = true, true
    Rows:Sorted({}, base)
    g, w = Rows:SortOptions()
    assertEquals(true, g)
    assertEquals(true, w)
    o.groupID, o.outwands = groupID, outwands
    cleanUp(o)
end)

-- ------------------------------------------------------ fix 4: the sweep --

test("the aura sweep allocates on its readers, not on itself", function()
    local o = ensureEnabled()
    if not gcBytes then
        print("[perf] collectgarbage absent: the sweep test is skipped")
        return
    end
    local base = epoch()
    installClock(base)
    -- "none" rows: the "player" half of `SweepAll` is the leg that walks them.
    seed(12, base, 120, "none")
    for i = 1, 12 do remaining(i, base, 60) end
    local savedReaders, savedCombat = Reconcile.readers, Reconcile.inCombat
    local savedLiveness, savedRowsLiveness = Reconcile.liveness, Rows.liveness
    -- A SEALED aura: every field read raises, which is the path the law is
    -- about (the sweep classifies it and moves on) and the one that costs the
    -- sweep its per-read work. The raising accessor and the pcall'd field
    -- reader are the two allocations fix 4 hoists out of the sweep.
    local sealed = setmetatable({}, {
        __index = function() error("sealed", 0) end,
    })
    local sealedList = { sealed }
    Reconcile.readers = {
        byName = function() return sealedList end,
        bulk = function() return nil end,
    }
    Reconcile.inCombat = function() return false end
    Reconcile.liveness = function() return "GUID-x", false, false end
    Rows.liveness = Reconcile.liveness
    Reconcile:SweepAll(base + 1)
    local readsBefore = Reconcile.counts.reads
    assertTrue(readsBefore >= 12,
        "a pass over 12 rows issued " .. readsBefore .. " reads")
    local bytes = 0
    for _ = 1, 3 do
        bytes = gcBytes(300, function() Reconcile:SweepAll(base + 1) end)
    end
    -- 12 sealed reads per call. Each one used to build the field-accessor
    -- closure `pcall` was handed (~56 B in this LuaJIT) = ~670 B/call, and a
    -- sealed read exits the row's leg, so the closure IS the per-row cost.
    -- Measured after the hoist: 36 B/call.
    assertBelow("SweepAll 12sealed bytes/call", bytes, 150)
    Reconcile.readers = savedReaders
    Reconcile.inCombat = savedCombat
    Reconcile.liveness = savedLiveness
    Rows.liveness = savedRowsLiveness
    cleanUp(o)
end)

test("the hoisted field readers keep the sweep's reads counted", function()
    local o = ensureEnabled()
    local base = epoch()
    installClock(base)
    seed(3, base, 120, "none")
    for i = 1, 3 do remaining(i, base, 60) end
    local savedReaders, savedCombat = Reconcile.readers, Reconcile.inCombat
    local savedLiveness, savedRowsLiveness = Reconcile.liveness, Rows.liveness
    -- PREALLOCATED facts (one aura LIST per read, as the live readers hand
    -- one), so a pass over 3 rows costs the sweep its own bookkeeping only.
    local facts, lists = {}, {}
    for i = 1, 3 do
        facts[i] = { name = "PerfRow" .. i, expirationTime = base + 130,
            duration = 120, applications = 1 }
        lists[i] = { facts[i] }
    end
    local index = {}
    for i = 1, 3 do index[facts[i].name] = lists[i] end
    Reconcile.readers = {
        byName = function(unit, name) return index[name] end,
        bulk = function() return nil end,
    }
    Reconcile.inCombat = function() return false end
    Reconcile.liveness = function() return "GUID-x", false, false end
    Rows.liveness = Reconcile.liveness
    local readsBefore = Reconcile.counts.reads
    local rowsBefore = Rows:Count()
    Reconcile:SweepAll(base + 1)
    local reads = Reconcile.counts.reads - readsBefore
    assertTrue(reads >= 3,
        "the pass issued " .. reads .. " counted reads for 3 rows")
    assertTrue(Rows:Count() >= rowsBefore,
        "the pass dropped rows: " .. rowsBefore .. " -> " .. Rows:Count())
    for i = 1, 3 do
        assertNotNil(Rows.rows[i], "row " .. i .. " survived the pass")
    end
    Reconcile.readers = savedReaders
    Reconcile.inCombat = savedCombat
    Reconcile.liveness = savedLiveness
    Rows.liveness = savedRowsLiveness
    cleanUp(o)
end)

-- ------------------------------------------- the fixed panel's GC floor --

test("the 25 Hz draw pass is allocation-free at the measured rate", function()
    local o = ensureEnabled()
    if not gcBytes then
        print("[perf] collectgarbage absent: the draw test is skipped")
        return
    end
    local saved = { maxOn = o.maxOn }
    o.maxOn = false
    local base = epoch()
    installClock(base)
    seed(30, base, 3600)
    for i = 1, 30 do remaining(i, base, 1800 - i * 10) end
    local bytes = 0
    for _ = 1, 3 do
        bytes = gcBytes(1000, function() M:Draw() end)
    end
    -- docs/perf.md §1: 6 342 B/tick at 30 rows = 158 KB/s of session; §6:
    -- 437 B/tick.
    assertBelow("Draw 30row bytes/tick", bytes, 1500)
    for k, v in pairs(saved) do o[k] = v end
    cleanUp(o)
end)

test("the gates leave the module in its production shape", function()
    Rows:Clear()
    Reconcile.readers = Reconcile.LiveReaders()
    Reconcile.inCombat = nil
    Reconcile.liveness = Reconcile.LiveLiveness()
    Rows.liveness = Reconcile.liveness
    installClock(epoch())
    Casts.now = nil
    M:Draw()
    assertNotNil(FX.Timer.Module.options)
    assertEquals(0, Rows:Count())
    for k, v in pairs(D.counts) do
        assertTrue(type(v) == "number" and v >= 0, "counter " .. k)
    end
end)
