-- addon/Forte_Timer/tests/test_timer_display_rows.lua
-- Wave 4 "Options Timer" (PLAN §11.1, docs/research/options-fidelity.md fix
-- list items 2, 3 and 5 for the Spell Timer page): the labels, the shipped
-- defaults and the new rows -- `Outwands`/`Flip` (:3148-3149, defs :3332-3333),
-- `LabelHeight` (:3242, def 18 :3344), the `Max`/`MaxOn` pair (:3315
-- `{[0]=false,15}`), `TicksNext` (:3182, def true :3404), `FadeTime` (:3193,
-- def 1 :3339) and the `Blink` pair (:3195, def `{[0]=true,3}` :3335), plus the
-- `ExpiredColor` gate (:3371 `{[0]=false,0.5,0.5,0.5,1}`) and its colour.
--
-- THE LAW THIS FILE ENFORCES: a setting is real only where the panel changes.
-- Every test therefore drives the REAL settings path -- `FX.Settings:Set`
-- (the same write the page's widget makes, which reaches the module through
-- the `OnChange` wire of Module:_WireSettings) -- seeds the rows through the
-- PUBLIC row API the `/fx timer test` debug feed uses
-- (`Rows:InsertFromCast`, Module.lua's own slash seam), draws through the
-- public tick body `Module:Draw`, and asserts on the FRAMES: the group box's
-- height, a header's anchored y, a bar's value, a fill texture's width, a
-- spark's and a tick mark's anchored x, a texture's vertex alpha. No test
-- calls a private render helper and none reads a law table as a substitute for
-- the screen.
--
-- FAILS-ON-THE-OLD-CODE (PLAN §11.1, per test):
--   * the defaults test: the page shipped `Max = 32`, `ColourExpired`
--     `{1,1,1}` (white, gate absent) and had no `MaxOn`/`LabelHeight`/
--     `Outwands`/`Flip`/`TicksNext`/`FadeTime`/`Blink`/`BlinkTime`/
--     `ExpiredColor` keys at all (GetDefault answers nil);
--   * the label test: the shipped labels read "Show group labels",
--     "Show the buff id", "Grow upwards", "Max rows";
--   * the LabelHeight test: `o.labelHeight` was Skin-only, so the store write
--     reached no setter and the box height and the header y did not move;
--   * the MaxOn test: the gate key did not exist, so the cap could never be
--     armed from the page;
--   * the Outwands test: the key did not exist on the page (the module's
--     `options.outwands` was unreachable from the UI), so the stack order
--     never moved;
--   * the Flip test: there was no `flip` consumer and no mirrored fill
--     texture at all (`r.fill` nil -> the test raises);
--   * the TicksNext test: every mark of the schedule was shown, so the shown
--     count read 4, not 1, and the "next" mark was not selected;
--   * the FadeTime test: `Laws.GateAlpha` added the FADING constant, so the
--     ramp ignored the setting and the group alpha stayed 0.50;
--   * the Blink test: no `Blink`/`BlinkTime` rows existed, so the row
--     background alpha could not be switched off;
--   * the ExpiredColor test: the gate row did not exist, and a row past its
--     end took the store's WHITE default.

local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Casts = FX.Timer.Casts
local D = FX.Timer.Display
local ST = FX.Settings

local function nearpx(actual, expected)
    assertTrue(math.abs(actual - expected) <= 0.5,
        string.format("expected %.3f, got %.3f", expected, actual))
end
local function near3(actual, expected)
    assertTrue(math.abs(actual - expected) < 1e-3,
        string.format("expected %.6f, got %.6f", expected, actual))
end

--- The rows' windows ride the RENDERER's clock (Display:Update reads the
--- global GetTime) while the sort, the gates and the ramps ride the module's
--- injectable one (Casts.now) -- the pair Forte_Timer/tests/test_perf_gates.lua
--- installs, and for the same reason: the sim's GetTime advances in whole
--- seconds, which is a shown value changing under a measurement.
local clock
local function epoch()
    return GetTime()
end
local function installClock(base)
    clock = { base }
    Casts.now = function() return clock[1] end
    return clock
end

local function withFixedClock(base, body)
    local saved = _G.GetTime
    _G.GetTime = function() return base end
    local ok, err = pcall(body)
    _G.GetTime = saved
    assertEquals(ok and "ok" or tostring(err), "ok")
end

local savedRowsOptions, savedCastsOptions
local function ensureEnabled()
    if not M.options then M:OnEnable() end
    assertNotNil(D.anchor, "the display is built")
    local o = M.options
    o.enable, o.hide = true, false
    if not D.anchor:IsShown() then D.anchor:Show() end
    -- The row table's option view is the sort's and the cap's source
    -- (`Rows:Sorted` reads `self.options`), and the suites assign it freely
    -- (test_rows.lua's fixture, the census's proxy) -- a suite that runs before
    -- this one leaves ITS table in place, which is how a cap or a sort gate
    -- written through the store stops reaching the draw. This file drives the
    -- module's own table everywhere (the census's `Rows.options = oProxy`
    -- pattern), and hands the previous table back in `cleanUp`.
    if savedRowsOptions == nil then
        savedRowsOptions = Rows.options
        savedCastsOptions = FX.Timer.Casts.options
    end
    Rows.options = o
    FX.Timer.Casts.options = o
    return o
end

--- One live row through the PUBLIC insert API (the `/fx timer test` feed's
--- own call, Module.lua:InsertFromCast): a window of `dur` seconds cast at
--- `base - startedAgo`, drawn as `kind`.
local function seedOne(name, base, dur, target, kind, startedAgo)
    local started = base - (startedAgo or 0.75)
    local row = Rows:InsertFromCast(name or "Serpent Sting",
        target or "Dummy-1", dur, started, started, 1,
        kind or "TargetDebuff")
    assertNotNil(row)
    return row
end

--- Pin the drawn window to `secs` of remaining time -- the only time input a
--- geometry test needs to move (the smoothing's drawn copy).
local function remaining(row, base, secs)
    row.drawExpireAt = base + secs
    return row
end

--- The pool slot carrying `row` (the pool order is the SORTED order).
local function slotOf(row)
    for s = 1, #D.rows do
        if D.rows[s]._row == row then return D.rows[s] end
    end
    return nil
end

local function shownBars()
    local n = 0
    for s = 1, #D.rows do
        if D.rows[s].bar:IsShown() then n = n + 1 end
    end
    return n
end

--- The anchored offsets of one object: (x, y) of its last SetPoint.
local function offsets(obj)
    local _, _, _, x, y = obj:GetPoint()
    return x, y
end

local function cleanUp()
    Rows:Clear()
    Casts.now = nil
    installClock(epoch())
    if M.options then
        M.options.maxOn, M.options.maxRows = false, 15
        M.options.flip, M.options.ticksNext = false, true
        M.options.blink, M.options.blinkAt = true, 3
        M.options.fadeTime, M.options.labelHeight = Laws.FADE, 18
        M.options.expiredColor, M.options.outwands = false, true
    end
    -- The STORE rides every write this file makes, and a later suite's
    -- `ApplyStoredSettings` would re-apply it: hand each key back its shipped
    -- default through the same public path.
    ST:Set("SpellTimer", "MaxOn", false)
    ST:Set("SpellTimer", "Max", 15)
    ST:Set("SpellTimer", "LabelHeight", 18)
    ST:Set("SpellTimer", "Outwands", true)
    ST:Set("SpellTimer", "Flip", false)
    ST:Set("SpellTimer", "TicksNext", true)
    ST:Set("SpellTimer", "FadeTime", 1)
    ST:Set("SpellTimer", "Blink", true)
    ST:Set("SpellTimer", "BlinkTime", 3)
    ST:Set("SpellTimer", "ExpiredColor", false)
    if savedRowsOptions ~= nil then
        Rows.options = savedRowsOptions
        FX.Timer.Casts.options = savedCastsOptions
    end
    D:RenderIdle()
end

-- ==================================================== item 2 + 3: the page ==

test("the page ships the source's labels for the Timer rows", function()
    ensureEnabled()
    local O = FX.Options
    assertNotNil(O)
    O:Open("SpellTimer")
    local page = O.pagesBuilt and O.pagesBuilt["SpellTimer"]
    assertNotNil(page, "the page builds")
    local byKey = {}
    for si = 1, #page.sections do
        for _, wd in ipairs(page.sections[si].widgets or {}) do
            byKey[wd.spec.key] = wd.spec.label
        end
    end
    -- The original's own words (options-fidelity.md item 2; the cites are the
    -- label constants): "Expand up" Forte_Core/Localization.lua:243,
    -- "Show unit #" Forte_Timer/Localization.lua:73,
    -- "Show name tags/headers" :77, "Maximum shown" Forte_Core/Localization.lua:276.
    assertEquals("Expand up", byKey.ExpandUpwards)
    assertEquals("Show unit #", byKey.ShowID)
    assertEquals("Show name tags/headers", byKey.Label)
    assertEquals("Maximum shown", byKey.Max)
    -- The five new rows, also the source's words: "Highest timers outwards"
    -- Forte_Timer/Localization.lua:183, "Flip bar direction"
    -- Forte_Core/Localization.lua:510, "Unit label height"
    -- Forte_Timer/Localization.lua:55, "Next Tick only" :168,
    -- "Standard fade delay" :107, "Blink expiring bars" :103.
    assertEquals("Highest timers outwards", byKey.Outwands)
    assertEquals("Flip bar direction", byKey.Flip)
    assertEquals("Unit label height", byKey.LabelHeight)
    assertEquals("Next Tick only", byKey.TicksNext)
    assertEquals("Standard fade delay (s)", byKey.FadeTime)
    assertEquals("Blink expiring bars", byKey.Blink)
    assertEquals("Limit rows shown", byKey.MaxOn)
    assertEquals("Tint expired rows", byKey.ExpiredColor)
    O:Close()
    cleanUp()
end)

test("the shipped defaults are the source's pair-shape defaults", function()
    ensureEnabled()
    -- `Max = {[0]=false,15}` (Forte_Timer.lua:3315): value 15, gate OFF.
    assertEquals(15, ST:GetDefault("SpellTimer", "Max"))
    assertEquals(false, ST:GetDefault("SpellTimer", "MaxOn"))
    -- `LabelHeight = 18` (:3344).
    assertEquals(18, ST:GetDefault("SpellTimer", "LabelHeight"))
    -- `Outwands = true` / `Flip = false` (:3333/:3332).
    assertEquals(true, ST:GetDefault("SpellTimer", "Outwands"))
    assertEquals(false, ST:GetDefault("SpellTimer", "Flip"))
    -- `TicksNext = true` (:3404).
    assertEquals(true, ST:GetDefault("SpellTimer", "TicksNext"))
    -- `FadeTime = 1` (:3339) and `Blink = {[0]=true,3}` (:3335).
    assertEquals(1, ST:GetDefault("SpellTimer", "FadeTime"))
    assertEquals(true, ST:GetDefault("SpellTimer", "Blink"))
    assertEquals(3, ST:GetDefault("SpellTimer", "BlinkTime"))
    -- `ExpiredColor = {[0]=false,0.50,0.50,0.50,1.00}` (:3371): the gate ships
    -- OFF and the grey is the source's triple, not the port's white.
    assertEquals(false, ST:GetDefault("SpellTimer", "ExpiredColor"))
    local col = ST:GetDefault("SpellTimer", "ColourExpired")
    assertNotNil(col)
    near3(col[1], 0.50); near3(col[2], 0.50); near3(col[3], 0.50)
    near3(col[4] or 1, 1.00)
    -- The store's shipped value is the same one the module applied.
    assertEquals(15, M.options.maxRows)
    assertEquals(false, M.options.maxOn)
    assertEquals(18, M.options.labelHeight)
    assertEquals(true, M.options.outwands)
    assertEquals(false, M.options.flip)
    assertEquals(true, M.options.ticksNext)
    assertEquals(1, M.options.fadeTime)
    assertEquals(true, M.options.blink)
    assertEquals(3, M.options.blinkAt)
    assertEquals(false, M.options.expiredColor)
    cleanUp()
end)

-- ============================================== item 5: unit label height ====

test("the unit label height moves the group box and the header", function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        Rows:Clear()
        seedOne("Serpent Sting", base, 12, "Vile Poacher")
        seedOne("Hunter's Mark", base, 20, "Vile Poacher")
        M:Draw()
        local g = D.groups[1]
        assertNotNil(g, "the stack drew a group")
        assertTrue(g.label:IsShown(), "the group carries its unit header")
        -- The box is count*Height + (count-1)*Space + LabelHeight (:2282).
        nearpx(g.frame:GetHeight(), 2 * o.height + o.space + 18)
        local _, headerY = offsets(g.label)
        nearpx(headerY, 2 * o.height + o.space + 18 - 18)
        -- The row: the store write the widget makes.
        ST:Set("SpellTimer", "LabelHeight", 30)
        assertEquals(30, M.options.labelHeight)
        M:Draw()
        nearpx(g.frame:GetHeight(), 2 * o.height + o.space + 30)
        local _, headerY2 = offsets(g.label)
        nearpx(headerY2, 2 * o.height + o.space + 30 - 30)
        ST:Set("SpellTimer", "LabelHeight", 18)
        M:Draw()
        nearpx(D.groups[1].frame:GetHeight(), 2 * o.height + o.space + 18)
        Rows:Clear()
    end)
    cleanUp()
end)

-- =================================================== item 3: the row cap ====

test("the row cap rides its gate: 15 off draws all, the gate arms the cap",
function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        Rows:Clear()
        for i = 1, 6 do
            seedOne("Serpent Sting", base, 12 + i, "Dummy-" .. i)
        end
        -- The shipped state: the gate is OFF, so all six rows are drawn.
        assertEquals(false, o.maxOn)
        assertEquals(15, o.maxRows)
        M:Draw()
        assertEquals(6, shownBars())
        -- The gate, through the store.
        ST:Set("SpellTimer", "MaxOn", true)
        ST:Set("SpellTimer", "Max", 3)
        assertEquals(true, M.options.maxOn)
        assertEquals(3, M.options.maxRows)
        M:Draw()
        assertEquals(3, shownBars())
        ST:Set("SpellTimer", "MaxOn", false)
        ST:Set("SpellTimer", "Max", 15)
        M:Draw()
        assertEquals(6, shownBars())
        Rows:Clear()
    end)
    cleanUp()
end)

-- ============================================== item 5: Outwands + Flip ======

test("Outwands turns the stack around: the short rows ride the far end",
function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        Rows:Clear()
        -- One group, two windows: the group key is shared, so the sort's
        -- second key -- the drawn expire time -- is what the gate turns.
        local short = remaining(seedOne("Serpent Sting", base, 12,
            "Vile Poacher"), base, 3)
        local long = remaining(seedOne("Hunter's Mark", base, 60,
            "Vile Poacher"), base, 50)
        assertEquals(true, o.outwands)
        M:Draw()
        local sShort, sLong = slotOf(short), slotOf(long)
        assertNotNil(sShort) assertNotNil(sLong)
        -- `Outwands` true (:3333): the longest remaining times furthest from
        -- the anchor, so the short row is drawn EARLIER in the cascade -- the
        -- smaller bar offset, and the bar rides the group box at that offset.
        assertTrue(sShort._ay < sLong._ay,
            string.format("outwands: short %.1f, long %.1f",
                sShort._ay, sLong._ay))
        local _, ys = offsets(sShort.bar)
        local _, yl = offsets(sLong.bar)
        assertTrue(ys < yl, "the drawn bars agree with the cascade")
        -- The gate off: the order mirrors.
        ST:Set("SpellTimer", "Outwands", false)
        assertEquals(false, M.options.outwands)
        M:Draw()
        sShort, sLong = slotOf(short), slotOf(long)
        assertTrue(sShort._ay > sLong._ay,
            string.format("inwards: short %.1f, long %.1f",
                sShort._ay, sLong._ay))
        ST:Set("SpellTimer", "Outwands", true)
        Rows:Clear()
    end)
    cleanUp()
end)

test("Flip mirrors the fill, the spark and the tick marks", function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        Rows:Clear()
        local row = remaining(seedOne("Serpent Sting", base, 12, "Dummy-1"),
            base, 9)                    -- a 12 s scale: barval 0.75
        -- A frozen scale: `Rows:Sorted`'s band easing runs `maxTime` from the
        -- insert value toward the tallest visible window, and a bar's fill
        -- fraction is the drawn time OVER that scale (the
        -- test_perf_gates.lua tick test freezes it for the same reason).
        row.maxTime = 12
        row.tickEvery = 3              -- a schedule: marks at .25/.50/.75/1.00
        --- The scale, frozen for every pass of this test: the band easing
        --- runs `maxTime` toward the tallest visible window, and the fill,
        --- the spark and the marks all divide by it.
        local function freeze()
            row.maxTime = 12
            row.tickEvery = 3
        end
        assertEquals(false, o.flip)
        freeze()
        M:Draw()
        local r = slotOf(row)
        assertNotNil(r)
        local w = o.barWidth
        -- The marks' LAYOUT is what the Flip law mirrors, so this test runs
        -- in the whole-schedule mode (the selection itself is the next test).
        local savedNext = o.ticksNext
        o.ticksNext = false
        -- The default direction: the fill rides the engine StatusBar, the
        -- mirrored texture is hidden, the spark at barval * width.
        assertFalse(r.fill:IsShown(), "no mirrored fill while unflipped")
        nearpx(offsets(r.spark), 0.75 * w)
        nearpx(offsets(r.ticks[3]), 0.75 * w)
        -- The store write: the fill moves to the mirrored texture, its width
        -- is the same fraction of the bar and it rides the RIGHT edge; the
        -- spark and the marks mirror ((1-barval) * width, :2536-2540,
        -- :1797/:1806).
        ST:Set("SpellTimer", "Flip", true)
        assertEquals(true, M.options.flip)
        freeze()
        M:Draw()
        assertTrue(r.fill:IsShown(), "the flipped fill rides the texture")
        nearpx(r.fill:GetWidth(), 0.75 * w)
        -- The texture's one anchoring is the bar's TOPRIGHT with no offset,
        -- so its own right edge IS the bar's right edge (the source's flipped
        -- `SetPoint("TOPRIGHT", ...)` :1650-1652).
        nearpx(offsets(r.fill), 0)
        nearpx(offsets(r.spark), 0.25 * w)
        nearpx(offsets(r.ticks[3]), 0.25 * w)
        -- And back.
        ST:Set("SpellTimer", "Flip", false)
        freeze()
        M:Draw()
        assertFalse(r.fill:IsShown())
        nearpx(offsets(r.spark), 0.75 * w)
        nearpx(offsets(r.ticks[3]), 0.75 * w)
        o.ticksNext = savedNext
        Rows:Clear()
    end)
    cleanUp()
end)

-- ================================================== item 5: TicksNext =======

test("Next Tick only draws the one mark of the schedule that fires next",
function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        Rows:Clear()
        local row = remaining(seedOne("Serpent Sting", base, 12, "Dummy-1"),
            base, 9)                    -- barval 0.75 of a 12 s scale
        row.maxTime = 12               -- the frozen scale (see the Flip test)
        row.tickEvery = 3              -- four marks: 3, 6, 9, 12 s
        local function freeze()
            row.maxTime = 12
            row.tickEvery = 3
        end
        assertEquals(true, o.ticksNext)
        freeze()
        M:Draw()
        local r = slotOf(row)
        local function shownTicks()
            local n, idx = 0, 0
            for t = 1, #r.ticks do
                if r.ticks[t]:IsShown() then n = n + 1; idx = t end
            end
            return n, idx
        end
        --- The fill's live edge in px, from the row's OWN drawn numbers --
        --- the same pair the renderer's bar value divides.
        local function fillEdge()
            local scale = row.maxTime > 0 and row.maxTime or 1
            local v = (row.drawExpireAt - base) / scale
            if v > 1 then v = 1 elseif v < 0 then v = 0 end
            return v * o.barWidth
        end
        --- The mark that "fires next" is the schedule step at the fill's
        --- live edge: the far-most mark that is still inside the drawn fill
        --- (the source's `dist = (ceil(barval/interval)-1)*interval`,
        --- :1775-1791). Asserted on the anchored geometry, so the band easing
        --- that runs the scale cannot move the law.
        local function assertNextAtEdge()
            local edge = fillEdge()
            local n, idx = shownTicks()
            assertEquals(1, n, "Next Tick only draws one mark")
            local x = (offsets(r.ticks[idx]))
            assertTrue(x <= edge + 0.5, string.format(
                "the shown mark sits at %.1f, past the fill edge %.1f",
                x, edge))
            for t = 1, #r.ticks do
                local tx = (offsets(r.ticks[t]))
                if tx > x + 0.5 and tx <= edge - 0.5 then
                    assertNil(nil, string.format(
                        "mark %d at %.1f is inside the fill (edge %.1f) and "
                        .. "nearer the edge than the shown %.1f",
                        t, tx, edge, x))
                end
            end
            return x
        end
        assertEquals(true, o.ticksNext)
        M:Draw()
        local x9 = assertNextAtEdge()
        -- Half the window drawn away: the next mark moves in with the fill.
        remaining(row, base, 6)
        freeze()
        M:Draw()
        local x6 = assertNextAtEdge()
        assertTrue(x6 < x9,
            string.format("the next mark followed the edge: %.1f -> %.1f",
                x9, x6))
        -- The row gate off: the WHOLE schedule rides the bar (the D6 law).
        ST:Set("SpellTimer", "TicksNext", false)
        assertEquals(false, M.options.ticksNext)
        freeze()
        M:Draw()
        -- The whole schedule rides the bar: `min(12, maxTime / every)` marks.
        local expected = math.min(12, math.floor(row.maxTime / row.tickEvery))
        assertTrue(expected >= 3, "the schedule laid out its marks")
        assertEquals(expected, (shownTicks()))
        ST:Set("SpellTimer", "TicksNext", true)
        freeze()
        M:Draw()
        assertEquals(1, (shownTicks()))
        -- A row with nothing of its schedule left inside the fill: no mark.
        remaining(row, base, 0.5)
        freeze()
        M:Draw()
        assertEquals(0, (shownTicks()))
        Rows:Clear()
    end)
    cleanUp()
end)

-- ==================================================== item 5: FadeTime ======

test("FadeTime is the ghost time the fade ramp starts after", function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        Rows:Clear()
        local row = seedOne("Serpent Sting", base, 12, "Dummy-1")
        -- The row is FADING with its fade start half a second BEFORE the
        -- draw. `FadeTime` 1 (:3339) covers that half second: the row rides
        -- full visibility (the `Alpha(removeAt + FadeTime, t)` law, :2166),
        -- and the group's alpha is full * NormalAlpha.
        Rows:Fade(row, Laws.FADING, base - 0.5)
        assertEquals(1, o.fadeTime)
        M:Draw()
        local g = D.groups[1]
        assertNotNil(g)
        assertTrue(g.frame:IsShown(), "the row is drawn inside its ghost time")
        near3(row.alpha, 1)
        near3(g.frame:GetAlpha(), o.normalAlpha)
        -- With the ghost time gone the ramp has run its whole course: the
        -- row's own visibility is 0 and the stack draws nothing.
        ST:Set("SpellTimer", "FadeTime", 0)
        assertEquals(0, M.options.fadeTime)
        M:Draw()
        near3(row.alpha, 0)
        assertFalse(D.groups[1].frame:IsShown(),
            "a row past the ramp leaves the stack")
        -- Back to the shipped ghost time: the row rides full visibility
        -- again.
        ST:Set("SpellTimer", "FadeTime", 1)
        M:Draw()
        near3(D.groups[1].frame:GetAlpha(), o.normalAlpha)
        Rows:Clear()
    end)
    cleanUp()
end)

-- ================================================= item 5: Blink + lead time

test("Blink is the row background's expiry pulse, gated by its lead time",
function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        Rows:Clear()
        -- 2 s of a 12 s window: inside the 3 s Blink lead (:3335), so the
        -- row's background rides the pulse (:1562-1569), not its plain alpha.
        local row = remaining(seedOne("Serpent Sting", base, 12, "Dummy-1"),
            base, 2)
        assertEquals(true, o.blink)
        assertEquals(3, o.blinkAt)
        M:Draw()
        local r = slotOf(row)
        local _, _, _, alpha = r.back:GetVertexColor()
        local pulse = 0.25 * (1 - math.cos(25 * math.sqrt(2)))
        near3(alpha, o.barBgAlpha + pulse)
        -- The gate off: the plain BarBackgroundAlpha.
        ST:Set("SpellTimer", "Blink", false)
        assertEquals(false, M.options.blink)
        M:Draw()
        local _, _, _, off = r.back:GetVertexColor()
        near3(off, o.barBgAlpha)
        -- The gate back on with a 1 s lead: 2 s left is outside it, so the
        -- row is steady again; at a 3 s lead it pulses.
        ST:Set("SpellTimer", "Blink", true)
        ST:Set("SpellTimer", "BlinkTime", 1)
        assertEquals(1, M.options.blinkAt)
        M:Draw()
        local _, _, _, out = r.back:GetVertexColor()
        near3(out, o.barBgAlpha)
        ST:Set("SpellTimer", "BlinkTime", 3)
        M:Draw()
        local _, _, _, back = r.back:GetVertexColor()
        near3(back, o.barBgAlpha + pulse)
        ST:Set("SpellTimer", "Blink", true)
        ST:Set("SpellTimer", "BlinkTime", 3)
        Rows:Clear()
    end)
    cleanUp()
end)

-- ============================================ item 3: the Expired pair ======

test("the Expired colour rides its gate: off by default, grey when on",
function()
    local o = ensureEnabled()
    local base = epoch()
    withFixedClock(base, function()
        installClock(base)
        Rows:Clear()
        -- A NORMAL row PAST its end (the shape the colour law's expired band
        -- needs, :1560): the window ended a second ago.
        local row = seedOne("Serpent Sting", base, 12, "Dummy-1")
        row.expireAt = base - 1
        row.drawExpireAt = base - 1
        assertEquals(false, o.expiredColor)
        M:Draw()
        local r = slotOf(row)
        local red, green, blue = r.back:GetVertexColor()
        -- Off: the row rides its CATEGORY colour (TargetDebuff, :3389).
        near3(red, FX.Timer.Skin.TargetDebuff[1])
        near3(green, FX.Timer.Skin.TargetDebuff[2])
        near3(blue, FX.Timer.Skin.TargetDebuff[3])
        -- On: the source's grey (:3371), which is the shipped default.
        ST:Set("SpellTimer", "ExpiredColor", true)
        assertEquals(true, M.options.expiredColor)
        M:Draw()
        local er, eg, eb = r.back:GetVertexColor()
        near3(er, 0.50); near3(eg, 0.50); near3(eb, 0.50)
        ST:Set("SpellTimer", "ExpiredColor", false)
        M:Draw()
        near3(r.back:GetVertexColor(), FX.Timer.Skin.TargetDebuff[1])
        Rows:Clear()
    end)
    cleanUp()
end)
