-- addon/Forte_Options/tests/test_options.lua
-- wow-ui-sim tests for the options window: Core/Settings.lua,
-- Core/Widgets.lua (every widget type driven through its real script
-- handlers), UI/Window.lua (geometry through the real frames, page/section
-- machinery, UISpecialFrames ESC registration, position memory) and the
-- FX.RegisterSlash seam in Forte_Core/Core/Init.lua.
--
-- The harness runs these after the addon chunks; frames are created on
-- demand by Open/Build exactly as a player would.

local FX = ForteXorcist
local O = FX.Options
local W = O.Widgets
local S = FX.Settings
local WC = W.C

local function near(a, b)
    return assertTrue(math.abs(a - b) < 1e-6)
end

-- ================================================================ Settings --

S:Register("TestMod", {
    alpha = 0.5, flag = false,
    col = { 1, 0, 0, 1 },
    tags = "0 1",
})

test("Settings: Register seeds defaults (Get)", function()
    assertEquals(0.5, S:Get("TestMod", "alpha"))
    assertEquals(false, S:Get("TestMod", "flag"))
    assertEquals("0 1", S:Get("TestMod", "tags"))
    local c = S:Get("TestMod", "col")
    assertEquals(1, c[1])
    assertEquals(0, c[3])
end)

test("Settings: Set writes, Get reads back", function()
    S:Set("TestMod", "alpha", 0.75)
    assertEquals(0.75, S:Get("TestMod", "alpha"))
    S:Set("TestMod", "flag", true)
    assertEquals(true, S:Get("TestMod", "flag"))
end)

test("Settings: OnChange fires with (key, value) on Set", function()
    local seenKey, seenVal, count = nil, nil, 0
    S:OnChange("TestMod", function(k, v)
        seenKey, seenVal, count = k, v, count + 1
    end)
    S:Set("TestMod", "alpha", 0.25)
    assertEquals("alpha", seenKey)
    assertEquals(0.25, seenVal)
    assertEquals(1, count)
end)

test("Settings: Reset(key) and Reset(module) restore defaults", function()
    S:Set("TestMod", "alpha", 0.11)
    S:Set("TestMod", "tags", "9 9")
    S:Reset("TestMod", "alpha")
    assertEquals(0.5, S:Get("TestMod", "alpha"))
    assertEquals("9 9", S:Get("TestMod", "tags"))
    S:Reset("TestMod")
    assertEquals("0 1", S:Get("TestMod", "tags"))
end)

test("Settings: Register never overwrites saved values", function()
    -- Write BEFORE the module has defaults: the store exists, no seed.
    S:Set("LateMod", "x", 42)
    S:Register("LateMod", { x = 1, y = 2 })
    assertEquals(42, S:Get("LateMod", "x"))
    assertEquals(2, S:Get("LateMod", "y"))
end)

test("Settings: Reset writes a deep copy (nested colour tables)", function()
    local c = S:Get("TestMod", "col")
    c[1] = 0.55                      -- the live table is mutable by contract
    S:Reset("TestMod", "col")
    assertEquals(1, S:Get("TestMod", "col")[1])
    local d = S:GetDefault("TestMod", "col")
    d[2] = 0.99                      -- mutating a returned default must not
    assertEquals(0, S:Get("TestMod", "col")[2])
end)

-- ================================================================= Widgets --

S:Register("WTest", {
    on = false, num = 10, sld = 5,
    col = { 0.5, 0.5, 0.5, 1 },
    str = "hello",
    hScale = 1.0, hAlpha = 1.0,
})
local parent = CreateFrame("Frame", nil, UIParent)
parent:SetSize(900, 700)
parent:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -40)

test("CHK binds, click writes, refresh syncs, recycle resets", function()
    local w = W.CHK(parent, { module = "WTest", key = "on", label = "On", width = 240 })
    assertEquals(false, S:Get("WTest", "on"))
    w.obj:GetScript("OnClick")(w.obj, "LeftButton")
    assertEquals(true, S:Get("WTest", "on"))
    w.refresh()
    assertEquals(true, w.obj:GetChecked())
    -- Per-option recycle writes the default back.
    w.resetBtn:GetScript("OnClick")(w.resetBtn)
    assertEquals(false, S:Get("WTest", "on"))
    w.refresh()
    assertEquals(false, w.obj:GetChecked())
    -- The gold check tint resolved to a real method (reported + visible).
    -- Polish pass: the native checked texture is the primary path
    -- (SetCheckedVertexColor does not exist on CheckButton in the sim).
    assertTrue(W.checkedTint == "SetCheckedTexture"
        or W.checkedTint == "SetCheckedVertexColor"
        or W.checkedTint == "GetCheckedTexture")
    print("[chk] checkedTint=" .. W.checkedTint)
end)

test("NUM: Enter commits with clamping, Escape restores", function()
    local w = W.NUM(parent, { module = "WTest", key = "num", label = "N",
        min = 1, max = 20, step = 1, width = 240 })
    local eb = w.obj
    eb:SetText("42")
    eb:GetScript("OnEnterPressed")(eb)
    assertEquals(20, S:Get("WTest", "num"))           -- clamped to max
    eb:SetText("-5")
    eb:GetScript("OnEnterPressed")(eb)
    assertEquals(1, S:Get("WTest", "num"))           -- clamped to min
    eb:SetText("7")
    eb:GetScript("OnEnterPressed")(eb)
    assertEquals(7, S:Get("WTest", "num"))
    -- Escape restores the stored value (no write).
    eb:SetText("999")
    eb:GetScript("OnEscapePressed")(eb)
    assertEquals(7, S:Get("WTest", "num"))
    w.refresh()
    assertEquals("7", eb:GetText())
    -- Recycle -> default.
    w.resetBtn:GetScript("OnClick")(w.resetBtn)
    assertEquals(10, S:Get("WTest", "num"))
end)

test("NUM: live filter keeps numeric text", function()
    local w = W.NUM(parent, { module = "WTest", key = "num", label = "N",
        min = 1, max = 100, step = 1, width = 240 })
    local eb = w.obj
    eb:SetText("12ab%3")
    eb:GetScript("OnTextChanged")(eb, true)
    assertEquals("123", eb:GetText())
    eb:SetText("1.2.3")
    eb:GetScript("OnTextChanged")(eb, true)
    assertEquals("1.23", eb:GetText())
    w.refresh()
end)

test("SLD binds: value change writes the setting", function()
    local w = W.SLD(parent, { module = "WTest", key = "sld", label = "S",
        min = 0, max = 10, step = 1, width = 320 })
    local sl = w.slider
    sl:SetValue(8)
    if S:Get("WTest", "sld") ~= 8 then
        -- If programmatic SetValue stays silent, drive the handler.
        sl:GetScript("OnValueChanged")(sl)
    end
    assertEquals(8, S:Get("WTest", "sld"))
    -- refresh() must not re-fire the handler (feedback guard).
    w.refresh()
    assertEquals(8, S:Get("WTest", "sld"))
    w.resetBtn:GetScript("OnClick")(w.resetBtn)
    assertEquals(5, S:Get("WTest", "sld"))
end)

test("COL: ColorPickerFrame API exists and writes the colour setting", function()
    assertNotNil(ColorPickerFrame)
    assertNotNil(ColorPickerFrame.SetupColorPickerAndShow)
    assertNotNil(ColorPickerFrame.GetColorRGB)
    local w = W.COL(parent, { module = "WTest", key = "col", label = "C", width = 300 })
    -- Open the picker through the swatch's own click handler.
    w.swatchBtn:GetScript("OnClick")(w.swatchBtn)
    assertEquals(true, ColorPickerFrame:IsShown())
    -- Drive the wheel: the mixin's OnColorSelect fires our swatchFunc.
    ColorPickerFrame.Content.ColorPicker:SetColorRGB(0.25, 0.50, 0.75)
    local c = S:Get("WTest", "col")
    near(c[1], 0.25)
    near(c[3], 0.75)
    ColorPickerFrame:Hide()
    -- Recycle restores the registered colour.
    w.resetBtn:GetScript("OnClick")(w.resetBtn)
    assertEquals(0.5, S:Get("WTest", "col")[1])
end)

test("STR: Enter commits, Escape restores", function()
    local w = W.STR(parent, { module = "WTest", key = "str", label = "T", width = 320 })
    local eb = w.obj
    eb:SetText("typed")
    eb:GetScript("OnEnterPressed")(eb)
    assertEquals("typed", S:Get("WTest", "str"))
    eb:SetText("zzz")
    eb:GetScript("OnEscapePressed")(eb)
    assertEquals("typed", S:Get("WTest", "str"))
    w.refresh()
    assertEquals("typed", eb:GetText())
end)

test("INFO shows the value, keyless rows have no recycle icon", function()
    local w = W.INFO(parent, { label = "Path", value = "a\\b\\c" })
    assertEquals("a\\b\\c", w.valueText:GetText())
    assertTrue(w.resetBtn == nil)
end)

test("HEADER: module bar height + header scale field clamps", function()
    local h = W.HEADER(parent, {
        title = "T", colour = { 0.2, 0.5, 0.2 }, width = 500,
        scaleSpec = { module = "WTest", key = "hScale", label = "scale",
            width = 96, numWidth = 48, min = 0.2, max = 5.0, step = 0.1 },
        alphaSpec = { module = "WTest", key = "hAlpha", label = "alpha",
            width = 96, numWidth = 48, min = 0.1, max = 1.0, step = 0.05 },
    })
    assertEquals(WC.HEAD_H, h.bar:GetHeight())
    local eb = h.scale.obj
    eb:SetText("9")
    eb:GetScript("OnEnterPressed")(eb)
    assertEquals(5, S:Get("WTest", "hScale"))
    eb = h.alpha.obj
    eb:SetText("0.02")
    eb:GetScript("OnEnterPressed")(eb)
    assertEquals(0.1, S:Get("WTest", "hAlpha"))
end)

-- ================================================================== Window --

test("Open('General'): 780x650 frame, header bar height, name", function()
    O:Open("General")
    assertEquals(true, O:IsOpen())
    local f = O.window
    assertEquals("ForteXorcistOptionsWindow", f:GetName())
    assertEquals(780, f:GetWidth())
    assertEquals(650, f:GetHeight())
    assertEquals(O.C.HEAD_H, O.header.bar:GetHeight())
    -- The window is registered for ESC handling (UISpecialFrames entries
    -- are global frame NAMES).
    local found = false
    for _, name in ipairs(UISpecialFrames) do
        if name == "ForteXorcistOptionsWindow" then found = true end
    end
    assertEquals(true, found)
    -- The URW Gothic verdict of the font pipeline (accepted by the sim).
    assertEquals(WC.FONT_FILE, O.fontFile)
    print("[font] accepted=" .. tostring(O.fontFile))
end)

test("module index: 4-column grid of 15, unbuilt pages disabled", function()
    assertEquals(15, #O.indexButtons)
    assertEquals(4, O.C.INDEX_COLS)
    local cellGap = O.C.INDEX_GAP
    local cellW = (O.indexFrame:GetWidth() - (4 + 1) * cellGap) / 4
    local _, _, _, x1, y1 = O.indexButtons[1]:GetPoint()
    local _, _, _, x2, y2 = O.indexButtons[2]:GetPoint()
    assertEquals(y1, y2)                                  -- same row
    near(x2 - x1, cellW + cellGap)                       -- adjacent column
    local _, _, _, x5, y5 = O.indexButtons[5]:GetPoint()
    assertEquals(x1, x5)                                  -- next row, col 1
    assertTrue(y5 < y1)   -- WoW anchors: y offset DOWN is negative, so
                          -- the next grid row steps to a smaller offset
    -- General / Cooldown / About live; the rest render disabled.
    assertEquals(true, O.indexButtons[1]:IsEnabled())
    assertEquals(true, O.indexButtons[3]:IsEnabled())
    assertEquals(true, O.indexButtons[15]:IsEnabled())
    assertEquals(false, O.indexButtons[2]:IsEnabled())    -- Spell Timer
    assertEquals(false, O.indexButtons[13]:IsEnabled())   -- Talent Spy
end)

test("section collapse toggles content height", function()
    O:Open("General")
    local page = O.pagesBuilt["General"]
    local h0 = O.contentHeight
    local bar = page.sections[2].bar                  -- General Module Options
    bar.bar:GetScript("OnClick")(bar.bar, "LeftButton")
    assertTrue(O.contentHeight < h0)
    bar.bar:GetScript("OnClick")(bar.bar, "LeftButton")
    assertEquals(h0, O.contentHeight)
end)

test("Close/Toggle and the position is remembered", function()
    O:Open("General")
    local f = O.window
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 123, 45)
    O:Close()
    assertEquals(false, O:IsOpen())
    O:Open("General")
    local point, _, relPoint, x, y = f:GetPoint()
    assertEquals("TOPLEFT", point)
    assertEquals("TOPLEFT", relPoint)
    near(123, x)
    near(45, y)
    -- Toggle closes an open window.
    O:Toggle()
    assertEquals(false, O:IsOpen())
    O:Toggle()
    assertEquals(true, O:IsOpen())
end)

test("Global Frame Lock drives FX.Cooldown.Display lock state", function()
    O:Open("General")
    local d = FX.Cooldown and FX.Cooldown.Display
    assertNotNil(d)
    S:Set("General", "GlobalLock", false)
    assertEquals(false, d.cfg.locked)
    S:Set("General", "GlobalLock", true)
    assertEquals(true, d.cfg.locked)
    -- Header lock icon is the shared state: toggle it through the header.
    local lock = O.header.lockText:GetParent()
    local before = S:Get("General", "GlobalLock")
    lock:GetScript("OnClick")(lock)
    assertEquals(not before, S:Get("General", "GlobalLock"))
    lock:GetScript("OnClick")(lock)
    assertEquals(before, S:Get("General", "GlobalLock"))
    S:Set("General", "GlobalLock", true)
end)

test("FX.RegisterSlash: /fx options toggles; lock claim order intact", function()
    O:Close()
    assertNotNil(FX.RegisterSlash)
    FX.OnSlash("options")
    assertEquals(true, O:IsOpen())
    FX.OnSlash("options")
    assertEquals(false, O:IsOpen())
    FX.OnSlash("config")
    assertEquals(true, O:IsOpen())
    FX.OnSlash("config")
    assertEquals(false, O:IsOpen())
    -- The Display still claims lock/unlock/reset (Init.lua order): those
    -- must not open the window.
    FX.OnSlash("lock")
    assertEquals(false, O:IsOpen())
    FX.OnSlash("unlock")
    assertEquals(false, O:IsOpen())
    FX.OnSlash("status")
    assertEquals(false, O:IsOpen())
    -- Restore the locked default for anything that runs after.
    FX.Cooldown.Display:SetLocked(true)
end)

test("Cooldown page: Lock wiring, colours render, section recycles", function()
    O:Open("Cooldown")
    local d = FX.Cooldown.Display
    S:Set("Cooldown", "Lock", false)
    assertEquals(false, d.cfg.locked)
    S:Set("Cooldown", "Lock", true)
    assertEquals(true, d.cfg.locked)
    local page = O.pagesBuilt["Cooldown"]
    assertEquals(5, #page.sections)           -- Tips, Basics, Specifics,
                                             -- Coloring, Frame Appearance
    local coloring = page.sections[4]
    -- The Specifics section carries the design-law defaults.
    assertEquals(250, S:Get("Cooldown", "Width"))
    assertEquals(2.99, S:Get("Cooldown", "IgnoreShort"))
    assertEquals("0 1 10 30 60 120 300 600", S:Get("Cooldown", "TimeTags"))
    assertEquals(1, S:Get("Cooldown", "ColorSpell")[1])
    near(0.5, S:Get("Cooldown", "ColorSpell")[2])
    -- Change one colour, then the section recycle restores the section set.
    S:Set("Cooldown", "ColorSpell", { 0.11, 0.22, 0.33, 1 })
    local rec = coloring.bar.recycle          -- the recycle Button
    rec:GetScript("OnClick")(rec)
    assertEquals(1, S:Get("Cooldown", "ColorSpell")[1])
    assertEquals(2.99, S:Get("Cooldown", "IgnoreShort")) -- other sections intact
    -- Leave a sane state for the screenshots.
    S:Set("Cooldown", "Lock", true)
    d:SetLocked(true)
end)

test("About page builds and opens", function()
    O:Open("About")
    assertEquals("About", O.pageId)
    local page = O.pagesBuilt["About"]
    assertEquals(2, #page.sections)          -- Some Tips + About ForteXorcist
    O:Open("General")
    O:Close()
end)

-- =============================================================== Geometry --
-- Numeric gates for the 2026-11-01 screenshot-defect pass (items 1-7).
-- WoW anchor space: y grows UPWARD, "below" is numerically smaller.

test("General: option rows stack strictly (2-col pairs share y, step right)",
function()
    O:Open("General")
    local page = O.pagesBuilt["General"]
    for si = 2, #page.sections do                  -- 1 = Some Tips
        local sec = page.sections[si]
        local rows = sec.widgets
        for i, widget in ipairs(rows) do
            local r = widget.row
            assertTrue(r:IsShown())
            local t, l = r:GetTop(), r:GetLeft()
            if i >= 2 then
                local p = rows[i - 1].row
                if math.abs(t - p:GetTop()) < 0.5 then
                    -- side-by-side pair: same y, right column steps right
                    -- by exactly one column width + gutter.
                    near(l - p:GetLeft(), p:GetWidth() + 6)
                    assertTrue(l > p:GetLeft() + 10,
                        "pair must step right (row " .. i .. ")")
                else
                    assertTrue(t < p:GetTop(),
                        "row " .. i .. " must stack below row " .. i - 1)
                end
            end
            if i >= 3 then
                assertTrue(t < rows[i - 2].row:GetTop() - 0.5,
                    "row " .. i .. " strictly below row " .. i - 2)
            end
            -- rows live inside the section content box
            assertTrue(t <= sec.content:GetTop() + 0.5)
            assertTrue(r:GetBottom() >= sec.content:GetBottom() - 0.5)
        end
    end
    O:Close()
end)

test("Every option row: shown gold label + sized control + recycle, inside row",
function()
    O:Open("General")
    local page = O.pagesBuilt["General"]
    local n = 0
    for si = 2, #page.sections do
        for _, wd in ipairs(page.sections[si].widgets) do
            local r = wd.row
            n = n + 1
            local lab = wd.label
            assertTrue(lab:IsShown())
            assertTrue(lab:GetHeight() > 0)
            local rr, gg = lab:GetTextColor()
            assertTrue(rr >= 0.99 and gg >= 0.7, "gold label")
            assertTrue(lab:GetLeft() >= r:GetLeft() - 0.5)
            assertTrue(lab:GetRight() <= r:GetRight() + 0.5)
            assertTrue(lab:GetTop() <= r:GetTop() + 0.5)
            assertTrue(lab:GetBottom() >= r:GetBottom() - 0.5)
            local obj = wd.obj
            assertNotNil(obj)
            assertTrue(obj:IsShown())
            assertTrue(obj:GetWidth() > 0,
                "zero-width " .. tostring(wd.spec.key) .. " w="
                .. tostring(obj:GetWidth()))
            assertTrue(obj:GetHeight() > 0)
            assertTrue(obj:GetLeft() >= r:GetLeft() - 0.5)
            assertTrue(obj:GetRight() <= r:GetRight() + 0.5)
            assertTrue(obj:GetTop() <= r:GetTop() + 0.5)
            assertTrue(obj:GetBottom() >= r:GetBottom() - 0.5)
            -- the label TEXT must not run over the control
            local lt = lab.GetUnboundedStringWidth
                and lab:GetUnboundedStringWidth() or lab:GetWidth()
            assertTrue(lab:GetLeft() + lt <= obj:GetLeft() + 0.5,
                "label over control: " .. tostring(wd.spec.label))
            local rb = wd.resetBtn
            assertNotNil(rb)
            assertTrue(rb:IsShown())
            assertTrue(rb:GetWidth() > 0)
            assertTrue(rb:GetRight() <= r:GetRight() + 0.5)
            assertTrue(rb:GetLeft() >= r:GetLeft() - 0.5)
            assertTrue(rb:GetTop() <= r:GetTop() + 0.5)
            assertTrue(rb:GetBottom() >= r:GetBottom() - 0.5)
            -- the control ends at the recycle zone, not over it
            assertTrue(obj:GetRight() <= rb:GetLeft() + 0.5)
        end
    end
    assertTrue(n >= 7)
    O:Close()
end)

test("Tips FontStrings stay inside the window", function()
    O:Open("General")
    local w = O.window
    local tips = O.pagesBuilt["General"].sections[1]
    assertEquals("Some Tips", tips.title)
    assertEquals(4, #tips.lines)
    for _, line in ipairs(tips.lines) do
        local body = line.body
        assertNotNil(body)
        assertTrue(body:IsShown())
        assertTrue(body:GetTop() <= w:GetTop() + 0.5, "tips over window top")
        assertTrue(body:GetTop() >= w:GetBottom() - 0.5, "tips below window")
        assertTrue(body:GetLeft() >= w:GetLeft() - 0.5)
        assertTrue(body:GetRight() <= w:GetRight() + 0.5)
        assertTrue(body:GetWidth() > 0)           -- bounded, word-wrapped
    end
    for _, sec in ipairs(O.pagesBuilt["General"].sections) do
        local barFrame = sec.bar.bar            -- W.SECTION wrapper -> Button
        assertTrue(barFrame:GetTop() <= w:GetTop() + 0.5)
        assertTrue(barFrame:GetBottom() >= w:GetBottom() - 0.5)
    end
    O:Close()
end)

test("Header bar inside the window, directly under the title strip", function()
    O:Open("General")
    local w, h = O.window, O.header.bar
    assertTrue(h:IsShown())
    near(w:GetTop() - O.C.TITLE_H - O.C.TABS_H, h:GetTop())
    assertTrue(h:GetBottom() >= w:GetBottom())
    assertTrue(h:GetLeft() >= w:GetLeft())
    assertTrue(h:GetRight() <= w:GetRight())
    -- the scroll area starts below the header bottom
    assertTrue(O.viewport:GetTop() <= h:GetBottom() + 0.5)
    O:Close()
end)

test("Title strip: gold centred title, close X at the strip's right end",
function()
    O:Open("General")
    local w, bar = O.window, O.titleBar
    near(w:GetTop(), bar:GetTop())
    near(O.C.TITLE_H, bar:GetHeight())
    local title = O.titleFS
    assertTrue(title:IsShown())
    assertTrue(title:GetTop() <= bar:GetTop() + 0.5)
    assertTrue(title:GetBottom() >= bar:GetBottom() - 0.5)
    assertTrue(title:GetLeft() >= bar:GetLeft())
    assertTrue(title:GetRight() <= bar:GetRight())
    local r, g = title:GetTextColor()
    assertTrue(r >= 0.99 and g >= 0.7, "gold title")
    local c = O.closeBtn
    assertTrue(c:IsShown())
    assertTrue(c:GetWidth() > 0 and c:GetHeight() > 0)
    assertTrue(c:GetTop() <= w:GetTop() + 0.5)
    assertTrue(c:GetBottom() >= w:GetBottom())
    assertTrue(c:GetLeft() >= w:GetLeft())
    assertTrue(c:GetRight() <= w:GetRight())
    -- red X glyph, 14x14, inside the button
    local gt = c.glyphText
    assertNotNil(gt)
    assertTrue(gt:IsShown())
    assertTrue((gt:GetText() or ""):find("common%-icon%-redx") ~= nil)
    assertTrue((gt:GetText() or ""):find(":" .. WC.GLYPH_CLOSE .. ":"
        .. WC.GLYPH_CLOSE) ~= nil, "14x14 glyph size")
    assertTrue(c:GetWidth() >= 14 and c:GetHeight() >= 14)
    O:Close()
end)

test("Scroll area ends above the module index; grid cells inside it", function()
    O:Open("General")
    local w, vp, idx = O.window, O.viewport, O.indexFrame
    assertTrue(vp:GetBottom() >= idx:GetTop() - 0.5, "content over grid")
    assertTrue(idx:GetTop() <= w:GetTop() + 0.5)
    assertTrue(idx:GetBottom() >= w:GetBottom() - 0.5)
    for _, btn in ipairs(O.indexButtons) do
        assertTrue(btn:GetTop() <= idx:GetTop() + 0.5)
        assertTrue(btn:GetBottom() >= idx:GetBottom() - 0.5)
        assertTrue(btn:GetLeft() >= idx:GetLeft() - 0.5)
        assertTrue(btn:GetRight() <= idx:GetRight() + 0.5)
    end
    local _, _, _, _, y1 = O.indexButtons[1]:GetPoint()
    local _, _, _, _, y5 = O.indexButtons[5]:GetPoint()
    assertTrue(y5 < y1, "grid rows step down (negative WoW offsets)")
    assertEquals(0, O._scroll)
    O:Close()
end)

test("Scrolling clamps: content covers the viewport, tips stay in-window",
function()
    O:Open("Cooldown")
    local w, vp = O.window, O.viewport
    O:Scroll(-40)                                   -- wheel down one step
    near(vp:GetTop() + 40, O.content:GetTop())      -- content moved up
    O:Scroll(-4000)                                 -- over-scroll down
    assertEquals(O.contentHeight - vp:GetHeight(), O._scroll)
    assertTrue(O.content:GetBottom() <= vp:GetBottom() + 0.5)
    for _, line in ipairs(O.pagesBuilt["Cooldown"].sections[1].lines) do
        assertTrue(line.body:GetTop() >= w:GetBottom() - 0.5)
    end
    O:Scroll(4000)                                  -- back to the top
    assertEquals(0, O._scroll)
    O:Close()
end)

-- =============================================================== Polish ==
-- Numeric gates for the 2026-11-01 polish pass (defects 1-6). Positions are
-- asserted through the live frames in the sim.

local function nearT(a, b, tol)
    return assertTrue(math.abs(a - b) <= tol + 1e-9)
end

test("polish 1: every row label is LEFT-justified at row left + 8", function()
    O:Open("General")
    local page = O.pagesBuilt["General"]
    local n = 0
    for si = 2, #page.sections do
        for _, wd in ipairs(page.sections[si].widgets) do
            local lab, r = wd.label, wd.row
            n = n + 1
            assertEquals("LEFT", lab:GetJustifyH())
            near(r:GetLeft() + WC.LABEL_INSET, lab:GetLeft())
            assertTrue(lab:GetHeight() > 0)
            -- the label owns a bounded column: its column never crosses
            -- the recycle zone, so the clipped text can never overprint
            -- the control column
            assertTrue(lab:GetLeft() + wd.labelWidth
                <= r:GetRight() - (WC.ICON_W + WC.ICON_GAP) + 0.5,
                "label column crosses the recycle zone")
            -- clipped: the column is measured from the text, not the cell
            local unb = (lab.GetUnboundedStringWidth
                and lab:GetUnboundedStringWidth()) or 0
            assertTrue(wd.labelWidth >= math.min(unb, wd.labelWidth) - 0.5)
            assertTrue(wd.labelWidth > 0)
        end
    end
    assertTrue(n >= 7)
    -- the first row's label (report value: justify, left)
    local first = page.sections[2].widgets[1]
    assertEquals("LEFT", first.label:GetJustifyH())
    near(first.row:GetLeft() + 8, first.label:GetLeft())
    print(string.format("[polish1] first label justify=%s left=%.1f rowLeft=%.1f",
        first.label:GetJustifyH(), first.label:GetLeft(),
        first.row:GetLeft()))
    O:Close()
end)

test("polish 2: tips lines are plain text, LEFT at section left + 12",
function()
    O:Open("General")
    local tips = O.pagesBuilt["General"].sections[1]
    assertEquals(4, #tips.lines)
    local src = {
        "Drag the title bar to move this window; ESC closes it.",
        "/fx options opens and closes this window.",
        "Global Frame Lock protects every Forte module frame from dragging.",
        "The recycle icon left of every row restores just that option.",
    }
    for i, line in ipairs(tips.lines) do
        local body = line.body
        assertEquals(src[i], body:GetText())       -- verbatim, no marker
        local t = body:GetText()
        assertTrue(t:find("!") == nil, "stray bullet marker")
        assertEquals("LEFT", body:GetJustifyH())
        near(line:GetLeft() + WC.TIPS_INSET, body:GetLeft())
        local r, g, b = body:GetTextColor()
        assertTrue(r >= 0.99 and g >= 0.99 and b >= 0.99, "tips text is white")
        assertTrue(body:GetWidth() > 100)          -- fills the line, not centred
    end
    print(string.format("[polish2] tips body left=%.1f lineLeft=%.1f width=%.1f",
        tips.lines[1].body:GetLeft(), tips.lines[1]:GetLeft(),
        tips.lines[1].body:GetWidth()))
    O:Close()
end)

test("polish 3: STR spans its row; no value overprints its label column",
function()
    O:Open("Cooldown")
    local page = O.pagesBuilt["Cooldown"]
    local str
    for _, wd in ipairs(page.sections[3].widgets) do
        if wd.spec.key == "TimeTags" then str = wd end
    end
    assertNotNil(str)
    -- the string box spans the full row: content width minus the
    -- section's 12px inner insets (defect 3 law: STR rows get the whole
    -- row, not a half-column cell)
    near(page.sections[3].content:GetWidth() - 2 * WC.TIPS_INSET,
        str.row:GetWidth())
    -- label column ~38% of the row
    nearT(str.row:GetWidth() * WC.LABEL_COL_RATIO, str.labelWidth, 1)
    assertEquals("LEFT", str.obj:GetJustifyH())
    nearT(str.row:GetRight() - (WC.ICON_W + WC.ICON_GAP), str.obj:GetRight(), 1)
    local gap = str.obj:GetLeft() - str.label:GetRight()
    assertTrue(gap >= 4 - 0.5, "STR value overprints the label")
    print(string.format("[polish3] TimeTags labelRight=%.1f valueLeft=%.1f col=%.1f rowW=%.1f",
        str.label:GetRight(), str.obj:GetLeft(), str.labelWidth,
        str.row:GetWidth()))

    -- General: the BarFont/BarTexture INFO rows must not overprint either
    O:Open("General")
    local gp = O.pagesBuilt["General"]
    for _, wd in ipairs(gp.sections[3].widgets) do
        if wd.spec.key == "BarFont"
            or wd.spec.key == "BarTexture" then
            local g2 = wd.obj:GetLeft() - wd.label:GetRight()
            assertTrue(g2 >= 4 - 0.5,
                "INFO overprint " .. tostring(wd.spec.key))
            -- clipped to one line, inside the row box
            local ml = (wd.valueText.GetMaxLines
                and wd.valueText:GetMaxLines())
            if ml then assertEquals(1, ml) end
            assertTrue(wd.obj:GetRight() <= wd.row:GetRight() + 0.5)
            if wd.spec.key == "BarFont" then
                print(string.format("[polish3] BarFont labelRight=%.1f valueLeft=%.1f rowW=%.1f",
                    wd.label:GetRight(), wd.obj:GetLeft(),
                    wd.row:GetWidth()))
            end
        end
    end
    -- Coloring rows: the r g b a value region starts right of the label
    O:Open("Cooldown")
    for _, wd in ipairs(O.pagesBuilt["Cooldown"].sections[4].widgets) do
        assertTrue(wd.valueText:GetLeft()
            >= wd.label:GetLeft() + wd.labelWidth + 4 - 0.5,
            "COL value overprints the label")
    end
    O:Close()
end)

test("polish 4: section bars are full-width navy bars with a light top edge",
function()
    O:Open("General")
    local page = O.pagesBuilt["General"]
    for _, sec in ipairs(page.sections) do
        local bar = sec.bar
        near(sec.content:GetWidth(), bar.bar:GetWidth())
        assertEquals(WC.SECTION_H, bar.bar:GetHeight())
        assertTrue(bar.art:GetTexture() ~= nil, "bar fill has a texture")
        assertTrue(bar.edge ~= nil, "bar has a top edge")
        nearT(bar.bar:GetTop(), bar.edge:GetTop(), 0.5)
        nearT(1, bar.edge:GetHeight(), 0.5)
        nearT(bar.bar:GetWidth(), bar.edge:GetWidth(), 1)
        -- title: white, LEFT, after the collapse arrow
        assertEquals("LEFT", bar.title:GetJustifyH())
        nearT(bar.bar:GetLeft() + 24, bar.title:GetLeft(), 0.5)
        local r, g, b = bar.title:GetTextColor()
        assertTrue(r >= 0.99 and g >= 0.99 and b >= 0.99, "title white")
        assertTrue(bar.plus:IsShown())
    end
    local gmo = page.sections[2]
    print(string.format("[polish4] bar width=%.1f height=%.1f edgeW=%.1f",
        gmo.bar.bar:GetWidth(), gmo.bar.bar:GetHeight(),
        gmo.bar.edge:GetWidth()))
    O:Close()
end)

test("polish 5: recycle icons are real 12px textures, grey, gold on hover",
function()
    O:Open("General")
    local page = O.pagesBuilt["General"]
    local first
    for si = 2, #page.sections do
        for _, wd in ipairs(page.sections[si].widgets) do
            local rb = wd.resetBtn
            assertNotNil(rb)
            assertTrue(rb:IsShown())
            assertEquals(WC.ICON_W, rb:GetWidth())
            assertEquals(WC.ICON_W, rb:GetHeight())
            assertNotNil(rb.iconTex)
            assertTrue(rb.iconTex:GetTexture() ~= nil, "icon has a texture file")
            nearT(WC.ICON_GREY_A, rb:GetAlpha(), 0.01)
            if not first then first = wd end
        end
    end
    -- hover: gold at full alpha; leave: grey at rest alpha
    local enter = first.resetBtn:GetScript("OnEnter")
    local leave = first.resetBtn:GetScript("OnLeave")
    assertNotNil(enter); assertNotNil(leave)
    enter(first.resetBtn)
    nearT(1.0, first.resetBtn:GetAlpha(), 0.01)
    local r, g, _, a = first.resetBtn.iconTex:GetVertexColor()
    assertTrue(r >= 0.99 and g >= 0.7, "hover gold")
    assertTrue(a == nil or a >= 0.99, "hover icon alpha")
    leave(first.resetBtn)
    nearT(WC.ICON_GREY_A, first.resetBtn:GetAlpha(), 0.01)
    print(string.format("[polish5] row icon %.0fx%.0f shown=%s alpha=%.2f tex=%s",
        first.resetBtn:GetWidth(), first.resetBtn:GetHeight(),
        tostring(first.resetBtn:IsShown()), first.resetBtn:GetAlpha(),
        tostring(first.resetBtn.iconTex:GetTexture())))

    -- section bars + the header carry the same icon
    for _, sec in ipairs(page.sections) do
        local rec = sec.bar.recycle
        if sec.title ~= "Some Tips" then
            assertTrue(rec:IsShown(), "section recycle hidden")
            assertEquals(WC.ICON_W, rec:GetWidth())
            assertNotNil(rec.iconTex:GetTexture())
        end
    end
    local hdr = O.header
    assertTrue(hdr.recycle:IsShown())
    assertEquals(WC.ICON_W, hdr.recycle:GetWidth())
    assertNotNil(hdr.recycle.iconTex:GetTexture())
    O:Close()
end)

test("polish 6: checkboxes are 14px, dark-filled, bordered box", function()
    O:Open("General")
    local page = O.pagesBuilt["General"]
    local n = 0
    for si = 2, #page.sections do
        for _, wd in ipairs(page.sections[si].widgets) do
            if wd.boxFill then
                n = n + 1
                assertEquals(14, wd.obj:GetWidth())
                assertEquals(14, wd.obj:GetHeight())
                assertTrue(wd.boxFill:GetTexture() ~= nil, "dark fill texture")
                nearT(wd.obj:GetWidth(), wd.boxFill:GetWidth(), 0.5)
                nearT(wd.obj:GetHeight(), wd.boxFill:GetHeight(), 0.5)
            end
        end
    end
    assertTrue(n >= 3)
    local cb = page.sections[2].widgets[1]   -- Global Frame Lock
    print(string.format("[polish6] checkbox %.0fx%.0f fill=%.0fx%.0f",
        cb.obj:GetWidth(), cb.obj:GetHeight(),
        cb.boxFill:GetWidth(), cb.boxFill:GetHeight()))
    O:Close()
end)

-- ========================================================== Defect pass 2 ==
-- Numeric gates for the 2026-11-01 follow-up pass: the header alpha/scale
-- boxes must sit INSIDE the header bar on every module page, and the
-- viewport carries a scrollbar whose thumb tracks the scroll offset.

test("header alpha/scale boxes sit inside the header bar (both pages)",
function()
    for _, pageId in ipairs({ "General", "Cooldown" }) do
        O:Open(pageId)
        local h = O.header
        local bar = h.bar
        assertTrue(bar:IsShown(), pageId .. " header bar shown")
        assertTrue(h.scale ~= nil, pageId .. " scale field exists")
        assertTrue(h.alpha ~= nil, pageId .. " alpha field exists")
        for _, pair in ipairs({ { "scale", h.scale }, { "alpha", h.alpha } }) do
            local name, wd = pair[1], pair[2]
            local r = wd.row
            assertTrue(r:IsShown(), pageId .. " " .. name .. " box shown")
            assertTrue(r:GetLeft() >= bar:GetLeft() - 0.5,
                pageId .. " " .. name .. " box left of the bar")
            assertTrue(r:GetRight() <= bar:GetRight() + 0.5,
                pageId .. " " .. name .. " box right of the bar")
            nearT(bar:GetTop(), r:GetTop(), 0.5)
            nearT(r:GetBottom(), bar:GetBottom(), 0.5)
            -- the label and the edit box live inside the box
            assertTrue(wd.label:GetLeft() >= r:GetLeft() - 0.5)
            assertTrue(wd.obj:GetRight() <= r:GetRight() + 0.5)
            assertTrue(wd.obj:GetWidth() > 0, name .. " edit box width")
            print(string.format(
                "[hdr2] %s %s box L=%.1f R=%.1f T=%.1f B=%.1f (bar L=%.1f R=%.1f T=%.1f B=%.1f)",
                pageId, name, r:GetLeft(), r:GetRight(),
                r:GetTop(), r:GetBottom(),
                bar:GetLeft(), bar:GetRight(), bar:GetTop(), bar:GetBottom()))
        end
        -- the requested layout: scale ends 28px before the bar's right
        -- edge, alpha ends 90px before the scale box's left edge, and the
        -- scale box stays left of the header recycle icon.
        nearT(bar:GetRight() - WC.HEAD_CTRL_RIGHT, h.scale.row:GetRight(), 1)
        nearT(h.scale.row:GetLeft() - WC.HEAD_CTRL_GAP,
            h.alpha.row:GetRight(), 1)
        assertTrue(h.scale.row:GetRight() <= h.recycle:GetLeft() + 0.5,
            pageId .. " scale box over the recycle icon")
        assertTrue(h.alpha.row:GetRight() < h.scale.row:GetLeft(),
            pageId .. " header boxes overlap")
    end
    O:Close()
end)

test("scrollbar: 6px track + thumb tracks the offset, hidden when the page fits",
function()
    O:Open("General")
    local tr, th = O.scrollTrack, O.scrollThumb
    assertTrue(tr ~= nil and th ~= nil, "scrollbar frames exist")
    assertEquals(O.C.SCROLL_W, tr:GetWidth())
    -- General fits the viewport: no scroll indication at all.
    assertTrue(O.contentHeight <= O.viewport:GetHeight() + 0.5,
        "General content must fit")
    assertTrue(not tr:IsShown(), "track hidden on a fitting page")
    assertTrue(not th:IsShown(), "thumb hidden on a fitting page")
    print(string.format("[sb2] General contentH=%.1f vpH=%.1f hidden",
        O.contentHeight, O.viewport:GetHeight()))

    O:Open("Cooldown")
    local vp = O.viewport
    assertTrue(O.contentHeight > vp:GetHeight(), "Cooldown overflows")
    assertTrue(tr:IsShown(), "track shown on an overflowing page")
    assertTrue(th:IsShown(), "thumb shown on an overflowing page")
    -- the thumb lives inside the track
    assertTrue(th:GetLeft() >= tr:GetLeft() - 0.5)
    assertTrue(th:GetRight() <= tr:GetRight() + 0.5)
    assertTrue(th:GetTop() <= tr:GetTop() + 0.5)
    assertTrue(th:GetBottom() >= tr:GetBottom() - 0.5)
    -- height ratio = viewport / content of the track
    local want = vp:GetHeight() / O.contentHeight * tr:GetHeight()
    assertTrue(want >= O.C.SCROLL_THUMB_MIN - 0.5, "min-height clamp active")
    nearT(want, th:GetHeight(), 1)
    print(string.format(
        "[sb2] Cooldown vpH=%.1f contentH=%.1f track %.1fx%.1f thumb %.1fx%.1f ratio=%.3f",
        vp:GetHeight(), O.contentHeight, tr:GetWidth(), tr:GetHeight(),
        th:GetWidth(), th:GetHeight(), th:GetHeight() / tr:GetHeight()))

    -- offset 0: flush with the track top
    assertEquals(0, O._scroll)
    nearT(tr:GetTop(), th:GetTop(), 0.5)
    print(string.format("[sb2] offset 0: thumb T=%.1f (track T=%.1f)",
        th:GetTop(), tr:GetTop()))
    -- a mid offset: strictly between the two extremes
    local maxScroll = O.contentHeight - vp:GetHeight()
    O:Scroll(-maxScroll / 2)
    nearT(maxScroll / 2, O._scroll, 1)
    assertTrue(th:GetTop() < tr:GetTop() - 0.5, "mid scroll moves thumb down")
    assertTrue(th:GetBottom() > tr:GetBottom() + 0.5, "mid scroll lifts bottom")
    -- max offset: flush with the track bottom
    O:Scroll(-maxScroll)
    assertEquals(maxScroll, O._scroll)
    nearT(tr:GetBottom(), th:GetBottom(), 0.5)
    print(string.format(
        "[sb2] offset max: scroll=%.1f thumb T=%.1f B=%.1f (track T=%.1f B=%.1f)",
        O._scroll, th:GetTop(), th:GetBottom(), tr:GetTop(), tr:GetBottom()))
    -- back to the top: flush again, and the bar hides on a fitting page
    O:Scroll(maxScroll)
    assertEquals(0, O._scroll)
    nearT(tr:GetTop(), th:GetTop(), 0.5)
    O:Open("General")
    assertTrue(not tr:IsShown(), "track hidden again after a page switch")
    O:Close()
end)
