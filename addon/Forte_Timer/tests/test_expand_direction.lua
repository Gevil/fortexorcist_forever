-- addon/Forte_Timer/tests/test_expand_direction.lua
-- PLAN §11.8 (owner report 2026-11-09): with 'Expand up' UNTICKED only the
-- title moved -- the bars still stacked upward and the whole stack drifted up
-- as bars appeared. Three causes, three families of test:
--   * the layout never read `options.expand` (Rows.lua Pass B always cascaded
--     up from the anchor's BOTTOMLEFT);
--   * the anchor frame is resized to the stack while its saved point was
--     CENTER, so it grew from the middle in both directions (and shifted on a
--     Width/Height/Scale change);
--   * a live Scale change moved the frame (offsets are in its own scale).
--
-- The fix pins the anchor by the FIRST-SLOT corner (cfg.corner = BOTTOMLEFT
-- growing up / TOPLEFT growing down, x/y from UIParent's BOTTOMLEFT in the
-- frame's own scale units). Every position below is read off the REAL frames
-- (GetLeft/GetTop/GetBottom of the anchor, the group boxes and the bars), the
-- bars come from the public row API through `Module:Draw`, the direction and
-- geometry are written through `FX.Settings:Set` (the page widget's own write,
-- which reaches the module through its OnChange wire), and a drag runs the
-- REAL OnMouseDown/OnDragStart/OnDragStop scripts (only the engine's native
-- move is emulated: it re-anchors the frame CENTER-style, which is exactly why
-- the save must read the rect, not GetPoint).
--
-- FAILS-ON-THE-OLD-CODE: run against the pre-change Rows.lua/Module.lua (a
-- copy of the addon tree with those two files from HEAD) every test below
-- fails on its first position assertion or on the missing seam it drives
-- (`cfg.corner`, `D.MigratePosition`, `D.SyncCorner`, `D.SetScale`):
-- the up test because the CENTER-pinned anchor moves the first bar as bars
-- are added, the down test because the bars still cascade up, the Width/
-- Height test because the CENTER anchor moves with its size, the drag test
-- because the old save stored `point/relPoint` (no corner), the migration/
-- reset tests because nothing ever converted CENTER, the toggle test because
-- the toggle only moved the title, the scale test because the frame jumped by
-- the scale ratio, the login test because the stored scale never reached the
-- anchor and Init never read the direction.

local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Casts = FX.Timer.Casts
local D = FX.Timer.Display
local ST = FX.Settings

local function near(actual, expected, what)
    if not (actual ~= nil and expected ~= nil
        and math.abs(actual - expected) < 1e-3) then
        error(string.format("%s: expected %s, got %s", what or "value",
            tostring(expected), tostring(actual)), 2)
    end
end

-- ------------------------------------------------------------------ fixture --
local savedRowsOptions, savedCastsOptions, savedCfg

local function ensure()
    if not M.options then M:OnEnable() end
    assertNotNil(D.anchor, "the display is built")
    local o = M.options
    o.enable, o.hide = true, false
    if savedRowsOptions == nil then
        savedRowsOptions = Rows.options
        savedCastsOptions = Casts.options
        savedCfg = {}
        for _, k in ipairs({ "corner", "x", "y", "point", "relPoint",
            "locked" }) do
            savedCfg[k] = D.cfg[k]
        end
    end
    Rows.options = o
    Casts.options = o
    return o
end

local function cleanUp()
    Rows:Clear()
    Casts.now = nil
    ST:Set("SpellTimer", "ExpandUpwards", true)
    ST:Set("SpellTimer", "Width", 250)
    ST:Set("SpellTimer", "Height", 14)
    ST:Set("SpellTimer", "Scale", 1.0)
    ST:Set("SpellTimer", "Label", true)
    if savedCfg then
        for k, v in pairs(savedCfg) do D.cfg[k] = v end
        D:ApplyPosition()
        D:SetLocked(savedCfg.locked and true or false)
    end
    if savedRowsOptions ~= nil then
        Rows.options = savedRowsOptions
        Casts.options = savedCastsOptions
    end
    D:RenderIdle()
end

--- `nBars` live rows over `nGroups` target groups, through the public insert
--- API (a 30 s window cast 0.75 s ago), then one real draw.
local function seedStack(nBars, nGroups)
    Rows:Clear()
    local base = GetTime()
    Casts.now = function() return base end
    local per = math.max(1, math.ceil(nBars / math.max(1, nGroups)))
    local made = 0
    for g = 1, nGroups do
        for _ = 1, per do
            if made < nBars then
                made = made + 1
                local row = Rows:InsertFromCast("DirSpell" .. made,
                    "DirTarget-" .. g, 30, base - 0.75, base - 0.75, 1,
                    "TargetDebuff")
                assertNotNil(row)
            end
        end
    end
    M:Draw()
    local shown = 0
    for i = 1, #D.groups do
        if D.groups[i].frame:IsShown() then shown = shown + 1 end
    end
    assertEquals(nGroups, shown, "the stack shows " .. nGroups .. " group(s)")
end

--- The Expand-up checkbox, through the page widget's own write.
local function setExpandUp(up)
    ST:Set("SpellTimer", "ExpandUpwards", up)
    assertEquals(up and true or false, M.options.expand ~= false)
end

--- Put the pinned corner (the first slot's bottom edge growing up / top edge
--- growing down) at (x, edge) in the current mode.
local function place(x, edge)
    D.cfg.corner = (M.options.expand == false) and "TOPLEFT" or "BOTTOMLEFT"
    D.cfg.x, D.cfg.y = x, edge
    D.cfg.point, D.cfg.relPoint = nil, nil
    D:ApplyPosition()
end

--- A drag through the REAL scripts, in the order the client fires them. The
--- native move is emulated by `StopMovingOrSizing` re-anchoring the frame
--- CENTER-style so that its rect is (left, bottom) at the current size.
local function dragTo(left, bottom)
    local f = D.anchor
    local press = f:GetScript("OnMouseDown")
    local dragStart = f:GetScript("OnDragStart")
    local dragStop = f:GetScript("OnDragStop")
    assertNotNil(press)
    assertNotNil(dragStart)
    assertNotNil(dragStop)
    local was = D.cfg.locked
    D:SetLocked(false)
    local started = 0
    local realStart, realStop = f.StartMoving, f.StopMovingOrSizing
    f.StartMoving = function() started = started + 1 end
    f.StopMovingOrSizing = function()
        local w, h = f:GetWidth(), f:GetHeight()
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", left + w / 2,
            bottom + h / 2)
    end
    press(f, "LeftButton")
    dragStart(f, "LeftButton")
    dragStop(f)
    f.StartMoving, f.StopMovingOrSizing = realStart, realStop
    D:SetLocked(was and true or false)
    assertEquals(1, started, "the unlocked drag started moving")
end

--- A second Display instance (the module's own functions, its own tables), so
--- `Init` can be driven again with a chosen saved cfg. The global frame name is
--- freed for the duration (a duplicate name is the engine's, not this test's).
local function newDisplay(overrides, cfg)
    local d = {}
    for k, v in pairs(D) do
        if type(v) == "function" then d[k] = v end
    end
    local opts = {}
    for k, v in pairs(M.options) do opts[k] = v end
    for k, v in pairs(overrides or {}) do opts[k] = v end
    local keep = _G.ForteXorcistTimerAnchor
    _G.ForteXorcistTimerAnchor = nil
    d:Init(opts, M.skin, cfg)
    _G.ForteXorcistTimerAnchor = keep
    return d, opts
end

--- The rect an idle box of the given anchoring would have on the engine.
local function refRect(point, relPoint, x, y, w, h, scale)
    local r = CreateFrame("Frame", nil, UIParent)
    r:SetSize(w, h)
    r:SetScale(scale or 1)
    r:SetPoint(point, UIParent, relPoint, x, y)
    local left, bottom, top = r:GetLeft(), r:GetBottom(), r:GetTop()
    r:Hide()
    return left, bottom, top
end

-- ======================================================== growth direction ==

test("expand UP: the first bar's bottom stays put as bars are added or leave",
function()
    local o = ensure()
    setExpandUp(true)
    place(300, 200)
    local prevTop
    for _, case in ipairs({ { 1, 1 }, { 3, 1 }, { 6, 2 }, { 1, 1 } }) do
        local n, ng = case[1], case[2]
        seedStack(n, ng)
        local a = D.anchor
        near(a:GetLeft(), 300, n .. " bars: anchor left")
        near(a:GetBottom(), 200, n .. " bars: anchor BOTTOM is the pin")
        local g1 = D.groups[1].frame
        near(g1:GetLeft(), 300, n .. " bars: group 1 left")
        near(g1:GetBottom(), 200, n .. " bars: group 1 bottom")
        near(D.rows[1].bar:GetBottom(), 200, n .. " bars: first bar bottom")
        for i = 2, n do
            assertTrue(D.rows[i].bar:GetBottom()
                > D.rows[i - 1].bar:GetBottom() + 0.5,
                "bar " .. i .. " is above bar " .. (i - 1))
        end
        if ng == 2 then
            near(D.groups[2].frame:GetBottom(),
                g1:GetTop() + o.spacingHeight, "group 2 sits on group 1")
        end
        -- the anchor box grows UP: its top is the last group's top
        near(a:GetTop(), D.groups[ng].frame:GetTop(), "anchor top = stack top")
        if n == 6 then prevTop = a:GetTop() end
    end
    -- and the stack shrinks back to the pin
    near(D.anchor:GetBottom(), 200, "after shrinking")
    assertTrue(prevTop > D.anchor:GetTop(), "the box shrank")
    cleanUp()
end)

test("default placement, expand UP: the first bar's bottom is identical for 1, 3 and 6 bars (the CENTER drift)",
function()
    ensure()
    setExpandUp(true)
    Rows:Clear()
    D:Reset()                       -- the shipped default spot
    local ref
    for _, c in ipairs({ { 1, 1 }, { 3, 1 }, { 6, 2 } }) do
        seedStack(c[1], c[2])
        local bottom = D.rows[1].bar:GetBottom()
        ref = ref or bottom
        near(bottom, ref, c[1] .. " bars: first bar bottom")
        near(D.groups[1].frame:GetBottom(), ref, c[1] .. " bars: group 1")
    end
    cleanUp()
end)

test("default placement, expand DOWN: bar 1 stays, later bars are lower (the owner's report)",
function()
    ensure()
    setExpandUp(false)
    Rows:Clear()
    D:Reset()
    local ref
    for _, c in ipairs({ { 1, 1 }, { 3, 1 }, { 6, 2 } }) do
        seedStack(c[1], c[2])
        local top = D.rows[1].bar:GetTop()
        ref = ref or top
        near(top, ref, c[1] .. " bars: first bar top")
        for i = 2, c[1] do
            assertTrue(D.rows[i].bar:GetTop() < D.rows[i - 1].bar:GetTop(),
                "bar " .. i .. " is lower than bar " .. (i - 1))
        end
    end
    cleanUp()
end)

test("expand DOWN: group 1 hangs from the pin, later bars appear BELOW it",
function()
    local o = ensure()
    setExpandUp(false)
    place(300, 700)
    local prevBottom
    for _, case in ipairs({ { 1, 1 }, { 3, 1 }, { 6, 2 }, { 1, 1 } }) do
        local n, ng = case[1], case[2]
        seedStack(n, ng)
        local a = D.anchor
        near(a:GetLeft(), 300, n .. " bars: anchor left")
        near(a:GetTop(), 700, n .. " bars: anchor TOP is the pin")
        local g1 = D.groups[1].frame
        near(g1:GetLeft(), 300, n .. " bars: group 1 left")
        -- group 1's box is raised by its label strip, so the LABEL sits above
        -- the pin and bar 1's TOP is exactly the pin, whatever follows it
        local strip = D.groups[1].label:IsShown() and o.labelHeight or 0
        assertEquals(o.labelHeight, strip, "the group is labelled")
        near(g1:GetTop(), 700 + strip, n .. " bars: group 1 raised by its strip")
        near(D.rows[1].bar:GetTop(), 700, n .. " bars: first bar top is the pin")
        near(D.rows[1].bar:GetLeft(), 300 + o.barInset, n .. " bars: bar x")
        -- visual order top -> bottom IS the link (pool) order, strictly
        for i = 2, n do
            assertTrue(D.rows[i].bar:GetTop()
                < D.rows[i - 1].bar:GetTop() - 0.5,
                "bar " .. i .. " is below bar " .. (i - 1))
        end
        if n >= 2 and ng == 1 then
            near(D.rows[1].bar:GetTop() - D.rows[2].bar:GetTop(),
                o.height + o.space, "bar pitch")
        end
        if ng == 2 then
            near(D.groups[2].frame:GetTop(), g1:GetBottom() - o.spacingHeight,
                "group 2 hangs under group 1")
            assertTrue(D.rows[4].bar:GetTop()
                < g1:GetBottom(), "group 2's bars are below group 1's box")
        end
        -- the anchor box grows DOWN: its bottom is the last group's bottom
        near(a:GetBottom(), D.groups[ng].frame:GetBottom(),
            "anchor bottom = stack bottom")
        if n == 6 then prevBottom = a:GetBottom() end
    end
    assertTrue(D.anchor:GetBottom() > prevBottom, "the box shrank back up")
    near(D.anchor:GetTop(), 700, "after shrinking")
    cleanUp()
end)

test("the group header still reads right going down: inside the box, over bar 1",
function()
    local o = ensure()
    setExpandUp(false)
    place(300, 700)
    seedStack(3, 1)
    local g = D.groups[1]
    assertTrue(g.label:IsShown())
    -- the label rides the strip directly above the first bar and inside the box
    assertTrue(g.label:GetBottom() >= D.rows[1].bar:GetTop() - 0.5,
        "the label sits above bar 1")
    assertTrue(g.label:GetTop() <= g.frame:GetTop() + 0.5,
        "the label stays inside the group box")
    near(g.frame:GetHeight(), 3 * o.height + 2 * o.space + o.labelHeight,
        "box height")
    cleanUp()
end)

--- A stack of `n` SELF rows (one unlabelled group), then one real draw.
local function seedSelf(n)
    Rows:Clear()
    local base = GetTime()
    Casts.now = function() return base end
    for i = 1, n do
        assertNotNil(Rows:InsertFromCast("DirSelf" .. i, "none", 30,
            base - 0.75, base - 0.75, 1, "SelfBuff"))
    end
    M:Draw()
end

local function bar1Edge(up)
    local bar = D.rows[1].bar
    return up and bar:GetBottom() or bar:GetTop()
end

test("bar 1 is exactly at the pin with group 1 labelled or not, 1/3/6 bars, both modes",
function()
    local o = ensure()
    for _, up in ipairs({ false, true }) do
        setExpandUp(up)
        local pin = up and 200 or 700
        place(300, pin)
        for _, mode in ipairs({ "labelled", "labels off", "self rows" }) do
            ST:Set("SpellTimer", "Label", mode ~= "labels off")
            for _, c in ipairs({ { 1, 1 }, { 3, 1 }, { 6, 2 } }) do
                local label = string.format("%s %s %d bars", up and "up" or "down",
                    mode, c[1])
                if mode == "self rows" then
                    seedSelf(c[1])
                else
                    seedStack(c[1], c[2])
                end
                assertEquals(mode == "labelled", D.groups[1].label:IsShown(),
                    label .. ": group 1 label presence")
                near(bar1Edge(up), pin, label .. ": bar 1 edge")
                near(D.anchor:GetLeft(), 300, label .. ": anchor left")
                near(up and D.anchor:GetBottom() or D.anchor:GetTop(), pin,
                    label .. ": anchor pin")
                -- the stack grows away from bar 1 in the mode's direction
                local n = #D.rows
                for i = 2, c[1] do
                    local a, b = D.rows[i - 1].bar, D.rows[i].bar
                    assertTrue(up and b:GetBottom() > a:GetBottom()
                        or (not up and b:GetTop() < a:GetTop()),
                        label .. ": bar " .. i .. " is on the growth side")
                end
                -- the anchor box is the stack: pin to the far end
                if not up then
                    near(D.anchor:GetBottom(),
                        D.groups[c[2] > 1 and 2 or 1].frame:GetBottom(),
                        label .. ": anchor bottom = stack bottom")
                end
            end
        end
    end
    cleanUp()
end)

test("replacing group 1's target row by a self row (label gone) does not move bar 1",
function()
    ensure()
    for _, up in ipairs({ false, true }) do
        setExpandUp(up)
        local pin = up and 200 or 700
        place(300, pin)
        for _, n in ipairs({ 1, 3 }) do
            seedStack(n, 1)
            assertTrue(D.groups[1].label:IsShown(), "labelled to start")
            local before = bar1Edge(up)
            near(before, pin, "bar 1 at the pin")
            seedSelf(n)                 -- the target rows gone, self rows in
            assertFalse(D.groups[1].label:IsShown(), "no label now")
            near(bar1Edge(up), before, (up and "up " or "down ") .. n
                .. " bars: bar 1 after the label left")
            seedStack(n, 1)             -- and the label comes back
            near(bar1Edge(up), before, (up and "up " or "down ") .. n
                .. " bars: bar 1 after the label returned")
        end
    end
    cleanUp()
end)

test("the pinned corner does not move when Width or Height change, in either mode",
function()
    ensure()
    for _, up in ipairs({ true, false }) do
        setExpandUp(up)
        local edge = up and 200 or 700
        place(300, edge)
        seedStack(3, 1)
        local function pinned()
            local a = D.anchor
            near(a:GetLeft(), 300, "anchor left")
            near(up and a:GetBottom() or a:GetTop(), edge, "anchor pin")
            near(D.groups[1].frame:GetLeft(), 300, "group left")
            local g1 = D.groups[1]
            near(up and g1.frame:GetBottom() or g1.frame:GetTop(),
                edge + ((not up and g1.label:IsShown())
                    and M.options.labelHeight or 0), "group pin")
        end
        pinned()
        ST:Set("SpellTimer", "Width", 320)
        M:Draw()
        pinned()
        near(D.anchor:GetWidth(), 320 + 6, "the box took the new width")
        ST:Set("SpellTimer", "Height", 22)
        M:Draw()
        pinned()
        local o = M.options
        if up then
            near(D.rows[1].bar:GetBottom(), edge, "first bar (up)")
        else
            near(D.rows[1].bar:GetTop(), edge, "first bar (down)")
        end
        ST:Set("SpellTimer", "Width", 250)
        ST:Set("SpellTimer", "Height", 14)
        M:Draw()
        pinned()
    end
    cleanUp()
end)

-- ============================================================ persistence ==

test("a drag saves the corner form for the current mode, read off the rect",
function()
    ensure()
    local cfg = D.cfg
    -- UP, with a stack showing: the frame is taller than the idle box
    setExpandUp(true)
    place(300, 200)
    seedStack(3, 1)
    dragTo(410.5, 333.25)
    assertEquals("BOTTOMLEFT", cfg.corner)
    near(cfg.x, 410.5, "saved x")
    near(cfg.y, 333.25, "saved y = the frame's BOTTOM")
    assertNil(cfg.point, "no legacy point after a save")
    assertNil(cfg.relPoint)
    -- the engine's own re-anchoring was replaced by ours
    local point, _, relPoint, x, y = D.anchor:GetPoint()
    assertEquals("BOTTOMLEFT", point)
    assertEquals("BOTTOMLEFT", relPoint)
    near(x, 410.5, "anchored x")
    near(y, 333.25, "anchored y")
    near(D.anchor:GetBottom(), 333.25, "rect bottom")
    -- DOWN: the saved y is the frame's TOP
    setExpandUp(false)
    seedStack(3, 1)
    local h = D.anchor:GetHeight()
    dragTo(500.5, 600)
    assertEquals("TOPLEFT", cfg.corner)
    near(cfg.x, 500.5, "saved x (down)")
    near(cfg.y, 600 + h, "saved y = the frame's TOP")
    near(D.anchor:GetLeft(), 500.5, "rect left (down)")
    near(D.anchor:GetTop(), 600 + h, "rect top (down)")
    -- bars keep growing from the saved pin
    seedStack(6, 2)
    near(D.anchor:GetTop(), 600 + h, "the pin survives a bigger stack")
    cleanUp()
end)

test("an unreadable rect keeps the old saved position", function()
    ensure()
    setExpandUp(true)
    place(300, 200)
    local cfg = D.cfg
    local f = D.anchor
    local realLeft, realBottom = f.GetLeft, f.GetBottom
    for _, reader in ipairs({ function() return nil end,
        function() error("rect unavailable") end }) do
        f.GetLeft = reader
        D:SavePosition(f)
        assertEquals("BOTTOMLEFT", cfg.corner)
        near(cfg.x, 300, "x kept")
        near(cfg.y, 200, "y kept")
        f.GetLeft = realLeft
    end
    f.GetBottom = function() return nil end
    D:SavePosition(f)
    near(cfg.x, 300, "x kept (bottom unreadable)")
    near(cfg.y, 200, "y kept (bottom unreadable)")
    f.GetBottom = realBottom
    cleanUp()
end)

test("Init restores the saved corner as the same rect, and syncs a stale corner to the mode",
function()
    ensure()
    local cfg = { corner = "BOTTOMLEFT", x = 300.5, y = 210.25, locked = true }
    local d = newDisplay({ expand = true }, cfg)
    near(d.anchor:GetLeft(), 300.5, "left")
    near(d.anchor:GetBottom(), 210.25, "bottom")
    assertEquals("BOTTOMLEFT", cfg.corner)
    near(cfg.y, 210.25, "an up cfg is not rewritten")
    d.anchor:Hide()

    cfg = { corner = "TOPLEFT", x = 120, y = 640, locked = true }
    d = newDisplay({ expand = false }, cfg)
    near(d.anchor:GetLeft(), 120, "left (down)")
    near(d.anchor:GetTop(), 640, "top (down)")
    d.anchor:Hide()

    -- a corner saved while growing up, loaded with the direction now DOWN
    -- (a profile switch, or the setting changed while the module was off):
    -- the first slot stays, the pin becomes its top edge.
    cfg = { corner = "BOTTOMLEFT", x = 300, y = 200, locked = true }
    d = newDisplay({ expand = false }, cfg)
    assertEquals("TOPLEFT", cfg.corner)
    near(cfg.y, 200 + M.options.height, "bottom + height")
    near(d.anchor:GetTop(), 200 + M.options.height, "top")
    near(d.anchor:GetBottom(), 200, "the idle slot's bottom is where it was")
    d.anchor:Hide()
    cleanUp()
end)

test("a legacy CENTER cfg migrates ONCE to the same visual spot (both modes, any scale)",
function()
    ensure()
    local o = M.options
    local cases = {
        { "CENTER", "CENTER", 261, -150 },       -- DEFAULT_POSITION / every install
        -- in bounds at scale 2 too (the frame is clamped to the screen)
        { "BOTTOMLEFT", "BOTTOMLEFT", 300, 200 },
        { "TOPLEFT", "TOPLEFT", 100, -100 },
        { "TOP", "TOP", 0, -50 },
    }
    for _, scale in ipairs({ 1, 2 }) do
        for _, up in ipairs({ true, false }) do
            for _, c in ipairs(cases) do
                local cfg = { point = c[1], relPoint = c[2], x = c[3],
                    y = c[4], locked = true }
                local d = newDisplay({ expand = up and true or false,
                    scale = scale }, cfg)
                local label = string.format("%s/%s scale %d %s", c[1], c[2],
                    scale, up and "up" or "down")
                local left, bottom, top = refRect(c[1], c[2], c[3], c[4],
                    o.groupWidth, o.height, scale)
                near(d.anchor:GetLeft(), left, label .. " left")
                if up then
                    near(d.anchor:GetBottom(), bottom, label .. " bottom")
                    assertEquals("BOTTOMLEFT", cfg.corner)
                else
                    near(d.anchor:GetTop(), top, label .. " top")
                    assertEquals("TOPLEFT", cfg.corner)
                end
                -- written back, legacy keys gone
                assertNil(cfg.point, label)
                assertNil(cfg.relPoint, label)
                assertEquals("number", type(cfg.x), label)
                assertEquals("number", type(cfg.y), label)
                -- ONCE: a second Init on the written-back cfg changes nothing
                local x, y, corner = cfg.x, cfg.y, cfg.corner
                local d2 = newDisplay({ expand = up and true or false,
                    scale = scale }, cfg)
                near(cfg.x, x, label .. " x stable")
                near(cfg.y, y, label .. " y stable")
                assertEquals(corner, cfg.corner)
                near(d2.anchor:GetLeft(), d.anchor:GetLeft(), label .. " again")
                d.anchor:Hide()
                d2.anchor:Hide()
            end
        end
    end
    cleanUp()
end)

test("reset restores the default spot (the old CENTER default), in either mode",
function()
    local o = ensure()
    local dp = M.DEFAULT_POSITION
    assertEquals("CENTER", dp.point)
    assertEquals(261, dp.x)
    assertEquals(-150, dp.y)
    for _, via in ipairs({ "method", "slash" }) do
        for _, up in ipairs({ true, false }) do
            setExpandUp(up)
            Rows:Clear()
            M:Draw()                    -- the idle box
            place(77, up and 55 or 400) -- somewhere else
            if via == "method" then
                D:Reset()
            else
                FX.slashSubs["timer"]("reset")
            end
            local label = via .. (up and " up" or " down")
            local left, bottom, top = refRect(dp.point, dp.relPoint, dp.x,
                dp.y, o.groupWidth, o.height, 1)
            near(D.anchor:GetLeft(), left, label .. " left")
            if up then
                near(D.anchor:GetBottom(), bottom, label .. " bottom")
                assertEquals("BOTTOMLEFT", D.cfg.corner)
            else
                near(D.anchor:GetTop(), top, label .. " top")
                assertEquals("TOPLEFT", D.cfg.corner)
            end
            assertNil(D.cfg.point, label)
            -- the same spot the old default had: the idle box's centre
            near(D.anchor:GetLeft() + D.anchor:GetWidth() / 2,
                UIParent:GetWidth() / 2 + dp.x, label .. " centre x")
            near(D.anchor:GetBottom() + D.anchor:GetHeight() / 2,
                UIParent:GetHeight() / 2 + dp.y, label .. " centre y")
        end
    end
    cleanUp()
end)

-- ============================================================= the toggle ==

test("toggling Expand keeps the first slot where it is, both ways, and relayouts",
function()
    local o = ensure()
    setExpandUp(true)
    place(300, 200)
    seedStack(3, 1)
    near(D.rows[1].bar:GetBottom(), 200, "up: first bar bottom")
    -- the Expand checkbox UNticked (the page widget's write)
    setExpandUp(false)
    assertEquals("TOPLEFT", D.cfg.corner)
    near(D.cfg.x, 300, "x kept")
    near(D.cfg.y, 200 + o.height, "top corner y = bottom + height")
    -- the redraw already ran: the groups hang from the new pin
    near(D.anchor:GetTop(), 200 + o.height, "anchor top")
    near(D.groups[1].frame:GetTop(), 200 + o.height + o.labelHeight,
        "group 1 raised by its strip")
    -- bar 1 is the SAME rect it was growing up: the slot did not move
    near(D.rows[1].bar:GetTop(), 200 + o.height, "down: first bar top")
    near(D.rows[1].bar:GetBottom(), 200, "down: first bar bottom (same rect)")
    assertTrue(D.rows[3].bar:GetTop() < D.rows[1].bar:GetTop(), "bars below")
    assertEquals("BOTTOM", (D.title:GetPoint()), "the title moved above")
    -- and back
    setExpandUp(true)
    assertEquals("BOTTOMLEFT", D.cfg.corner)
    near(D.cfg.y, 200, "exact round trip")
    near(D.rows[1].bar:GetBottom(), 200, "up again: first bar bottom")
    assertEquals("TOP", (D.title:GetPoint()), "the title is below again")
    -- a layout that is told by the option table alone (no setter) re-pins
    -- itself on the next pass: the display never draws a direction its anchor
    -- is not pinned for
    o.expand = false
    M:Draw()
    assertEquals("TOPLEFT", D.cfg.corner)
    near(D.cfg.y, 200 + o.height, "pass-driven re-pin")
    near(D.rows[1].bar:GetTop(), 200 + o.height, "pass-driven layout")
    o.expand = true
    M:Draw()
    near(D.cfg.y, 200, "pass-driven round trip")
    cleanUp()
end)

test("toggling Expand with an UNlabelled group 1 keeps bar 1 where it was too",
function()
    local o = ensure()
    setExpandUp(true)
    place(300, 200)
    seedSelf(3)
    assertFalse(D.groups[1].label:IsShown())
    near(D.rows[1].bar:GetBottom(), 200, "up: bar 1 bottom")
    setExpandUp(false)
    near(D.rows[1].bar:GetTop(), 200 + o.height, "down: bar 1 top")
    near(D.rows[1].bar:GetBottom(), 200, "down: bar 1 bottom (same rect)")
    setExpandUp(true)
    near(D.rows[1].bar:GetBottom(), 200, "back up")
    cleanUp()
end)

test("a live Scale change keeps the pinned corner on screen, in either mode",
function()
    ensure()
    for _, up in ipairs({ true, false }) do
        setExpandUp(up)
        place(300, up and 200 or 700)
        seedStack(2, 1)
        local a = D.anchor
        local function screen()
            local s = a:GetEffectiveScale()
            return a:GetLeft() * s, (up and a:GetBottom() or a:GetTop()) * s
        end
        local sx, sy = screen()
        for _, scale in ipairs({ 2, 0.5, 1.25, 1 }) do
            ST:Set("SpellTimer", "Scale", scale)
            M:Draw()
            near(a:GetScale(), scale, "the frame took the scale")
            near(M.options.scale, scale, "options.scale")
            local x, y = screen()
            near(x, sx, "screen x at scale " .. scale)
            near(y, sy, "screen y at scale " .. scale)
            near(D.cfg.x, 300 / scale, "saved x in the new units")
            near(D.cfg.y, (up and 200 or 700) / scale, "saved y")
            -- the first bar's own corner rides it
            local bar = D.rows[1].bar
            local edge = up and bar:GetBottom() or bar:GetTop()
            near(edge * a:GetEffectiveScale(),
                sy,
                "first bar at scale " .. scale)
        end
    end
    cleanUp()
end)

-- ==================================================================== login ==

test("a stored Expand-up = false reaches the layout at login, and Init pins for it",
function()
    ensure()
    ST:Set("SpellTimer", "ExpandUpwards", false)
    assertEquals(false, ST:Get("SpellTimer", "ExpandUpwards"),
        "the store keeps an explicit false (the default is true)")
    -- the login pass, as OnEnable runs it: the stored value is pulled into the
    -- fresh options table (default = up) BEFORE the display is built
    M.options.expand = true
    M:ApplyStoredSettings()
    assertEquals(false, M.options.expand, "the stored false is applied")
    -- ... then the display is built from that options table
    local cfg = { corner = "BOTTOMLEFT", x = 300, y = 200, locked = true }
    local d = newDisplay({}, cfg)
    assertEquals("TOPLEFT", cfg.corner)
    near(cfg.y, 200 + M.options.height, "pinned by the top")
    near(d.anchor:GetTop(), 200 + M.options.height, "rect top")
    assertEquals("BOTTOM", (d.title:GetPoint()), "title above")
    d.anchor:Hide()
    -- and a layout drawn from it hangs downward
    place(300, 700)
    seedStack(3, 1)
    assertTrue(D.rows[3].bar:GetTop() < D.rows[1].bar:GetTop() - 0.5)
    near(D.anchor:GetTop(), 700, "the pin")
    cleanUp()
end)

test("a stored Scale is applied to the anchor when the display is built",
function()
    ensure()
    local d = newDisplay({ scale = 1.5 },
        { corner = "BOTTOMLEFT", x = 100, y = 100, locked = true })
    near(d.anchor:GetScale(), 1.5, "the frame scale at Init")
    d.anchor:Hide()
    cleanUp()
end)

-- ======================================================================= tip ==

test("the Expand-up tip states the real behaviour, not 'not wired yet'",
function()
    local tip = FX.Timer.Pages.WIDGET_TIPS.ExpandUpwards
    assertNotNil(tip)
    assertNil(tip:lower():find("not wired"), tip)
    assertNil(tip:lower():find("always upward"), tip)
    assertNotNil(tip:lower():find("downward"), tip)
    assertNotNil(tip:lower():find("first bar"), tip)
end)
