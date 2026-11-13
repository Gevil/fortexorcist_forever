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

test("Settings: the store is SPARSE -- a Set equal to the default deletes the key",
function()
    -- Wave 5: the store keeps only values that differ from the registered
    -- defaults, so a moved shipped default reaches every profile that never
    -- set the key (the frozen AltTimeFormat=false of a live profile).
    local t = S._store("TestMod")
    S:Set("TestMod", "alpha", 0.75)
    assertEquals(0.75, t.alpha, "a real choice lands in the raw table")
    S:Set("TestMod", "alpha", 0.5)
    assertEquals(nil, t.alpha, "the shipped value DELETES the stored key")
    assertEquals(0.5, S:Get("TestMod", "alpha"), "the effective value is unchanged")
    S:Set("TestMod", "flag", false)      -- false IS the registered default
    assertEquals(nil, t.flag, "a boolean default is not stored")
    S:Set("TestMod", "flag", true)
    assertEquals(true, t.flag)
    S:Reset("TestMod", "flag")
    assertEquals(nil, t.flag, "the reset is the delete")
    -- Colour rows: deep equality over the { r, g, b, a } array.
    local col = S:GetDefault("TestMod", "col")
    S:Set("TestMod", "col", { col[1], col[2], col[3], col[4] })
    assertEquals(nil, t.col, "a colour deep-equal to the default is not stored")
    S:Set("TestMod", "col", { col[1], col[2], col[3], 0.5 })
    assertNotNil(t.col, "a moved alpha is a value")
    S:Reset("TestMod", "col")
    assertEquals(nil, t.col)
    -- Get hands out a DEEP COPY of the default, never the registered table.
    local c = S:Get("TestMod", "col")
    c[1] = 0.99
    assertEquals(1, S:Get("TestMod", "col")[1],
        "mutating a read default can not corrupt the registration")
    -- A Set-to-default still notifies: the apply path of a reset, a
    -- recycle icon and a profile switch rides the listeners.
    local fired = 0
    S:OnChange("TestMod", function() fired = fired + 1 end)
    S:Set("TestMod", "alpha", 0.5)
    assertEquals(1, fired, "a Set that stores nothing still fires OnChange")
    S:Reset("TestMod")
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
    pick = "aa",
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

-- ============================================================ MT-13 ==
-- Code-review-10 section (c) item 13: the keyboard-trap fix (the live
-- 2026-11-06: opening the options page grabbed the keyboard through the
-- number boxes' default auto-focus, and Enter left it grabbed), the DIALOG
-- strata (the live Esc/X-dead fix), and the close clickability. d490e2e
-- shipped all three with no pin.

--- Every EditBox built while installed records its SetAutoFocus argument.
local function installAutoFocusRecorder()
    local rec = {}
    local real = _G.CreateFrame
    _G.CreateFrame = function(ftype, name, owner, template)
        local f = real(ftype, name, owner, template)
        if ftype == "EditBox" then
            local realAF = f.SetAutoFocus
            f.SetAutoFocus = function(self, on)
                rec[#rec + 1] = on
                return realAF(self, on)
            end
        end
        return f
    end
    return rec, function() _G.CreateFrame = real end
end

test("MT-13: every text row ships SetAutoFocus(false) -- the page never grabs the keyboard",
function()
    local rec, restore = installAutoFocusRecorder()
    W.NUM(parent, { module = "WTest", key = "num", label = "N",
        min = 1, max = 20, step = 1, width = 240 })
    W.STR(parent, { module = "WTest", key = "str", label = "T", width = 320 })
    restore()
    assertTrue(#rec >= 2, "both rows drove SetAutoFocus (" .. #rec .. " calls)")
    for i = 1, #rec do
        assertEquals(false, rec[i],
            "SetAutoFocus call " .. i .. " carries the literal false (true"
            .. " is the keyboard trap the live client showed)")
    end
end)

test("MT-13: Enter commits and RELEASES the focus (NUM and STR), Escape restores and releases",
function()
    local cleared = 0
    local function countClear(w)
        local eb = w.obj
        local real = eb.ClearFocus
        eb.ClearFocus = function(self)
            cleared = cleared + 1
            return real(self)
        end
    end
    local n = W.NUM(parent, { module = "WTest", key = "num", label = "N",
        min = 1, max = 20, step = 1, width = 240 })
    countClear(n)
    n.obj:SetText("12")
    n.obj:GetScript("OnEnterPressed")(n.obj)
    assertEquals(12, S:Get("WTest", "num"),
        "the commit is the typed value (the Enter-commit law the NUM leg of"
        .. " 'NUM: Enter commits with clamping' pins -- 12 is in range, the clamp passes it)")
    assertEquals(1, cleared, "NUM's Enter CLEARS FOCUS (the keyboard release)")
    n.obj:SetText("9")
    n.obj:GetScript("OnEscapePressed")(n.obj)
    assertEquals(2, cleared, "NUM's Escape restores AND releases")
    assertEquals(12, S:Get("WTest", "num"), "the Escape leg writes nothing")

    local st = W.STR(parent, { module = "WTest", key = "str", label = "T",
        width = 320 })
    countClear(st)
    st.obj:SetText("typed2")
    st.obj:GetScript("OnEnterPressed")(st.obj)
    assertEquals("typed2", S:Get("WTest", "str"))
    assertEquals(3, cleared, "STR's Enter CLEARS FOCUS")
    S:Reset("WTest", "num")
    S:Reset("WTest", "str")
end)

test("MT-13: the window rides the DIALOG strata and the X closes it",
function()
    O:Open("General")
    local f = O.window
    -- The strata is the Esc/X-dead fix of the live client (i10): MEDIUM strata
    -- let other addons' frames cover the window (the X APPEARED dead) and
    -- UISpecialFrames' Esc contract closes DIALOG strata windows.
    assertNotNil(f.GetFrameStrata, "the client frame answers GetFrameStrata")
    assertEquals("DIALOG", f:GetFrameStrata(),
        "the options window rides the DIALOG strata")
    -- The X is a real, clickable close: mouse-enabled, click-scripted, and
    -- the click closes.
    local x = O.closeBtn
    assertNotNil(x, "the window owns its close button")
    if x.IsMouseEnabled then
        assertEquals(true, x:IsMouseEnabled(),
            "EnableMouse(true): the X answers the mouse")
    end
    assertNotNil(x:GetScript("OnClick"))
    x:GetScript("OnClick")(x)
    assertEquals(false, O:IsOpen(), "the X click CLOSES the window")
    -- The Esc contract: the registration in UISpecialFrames is what makes the
    -- client's Esc reach this window (the array carries GLOBAL FRAME NAMES).
    local found = false
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == "ForteXorcistOptionsWindow" then
            found = true
        end
    end
    assertTrue(found, "the window is in UISpecialFrames: Esc closes it")
end)

test("SEL picker: the button names the entry, popup items write the store",
function()
    local items = {
        { value = "aa", label = "A A" },
        { value = "bb", label = "B B" },
        { value = "cc", label = "C C" },
    }
    local w = W.SEL(parent, { module = "WTest", key = "pick", label = "P",
        width = 300, items = items })
    assertEquals("A A", w.caption:GetText(), "the button names the value")
    -- The popup opens on the row's own click (the original's NewDropdown
    -- Show law; Forte_Core/Options.lua:1649-1684).
    w.obj:GetScript("OnClick")(w.obj)
    assertNotNil(w.popup)
    assertTrue(w.popup:IsShown())
    assertEquals(3, #w.popupItems)
    -- The item click is the ONE write: the store.
    local second = w.popupItems[2]
    assertTrue(second:IsShown())
    second:GetScript("OnClick")(second)
    assertEquals("bb", S:Get("WTest", "pick"))
    assertFalse(w.popup:IsShown(), "the pick closes the list")
    w.refresh()
    assertEquals("B B", w.caption:GetText())
    -- Click toggles: open, close.
    w.obj:GetScript("OnClick")(w.obj)
    assertTrue(w.popup:IsShown())
    w.obj:GetScript("OnClick")(w.obj)
    assertFalse(w.popup:IsShown())
    -- The original's show-on-hover law (NewDropdownShowButton OnEnter).
    w.obj:GetScript("OnEnter")(w.obj)
    assertTrue(w.popup:IsShown())
    w.obj:GetScript("OnLeave")(w.obj)
    assertFalse(w.popup:IsShown())
    -- Recycle -> the registered default.
    w.resetBtn:GetScript("OnClick")(w.resetBtn)
    assertEquals("aa", S:Get("WTest", "pick"))
    w.refresh()
    assertEquals("A A", w.caption:GetText())
    -- A value off the list prints its basename (the path rows' fallback).
    S:Set("WTest", "pick", "Interface\\AddOns\\Forte_Core\\Textures\\Xeon")
    w.refresh()
    assertEquals("Xeon", w.caption:GetText())
    S:Reset("WTest", "pick")
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
    -- The URW Gothic verdict of the font pipeline. PLAN §11.12 law: the file is
    -- kept unless SetFont RAISES (FX.Compat.FontUsable) -- the old "GetFont must
    -- echo the path" round trip was the bug (test_font_law.lua pins the pending
    -- case); the sim raises on no path, so the shipped file stands.
    assertEquals(WC.FONT_FILE, O.fontFile)
    print("[font] accepted=" .. tostring(O.fontFile))
end)

test("module index: 4-column grid of 16 (a full 4x4), unbuilt pages disabled",
function()
    assertEquals(16, #O.indexButtons)
    assertEquals(4, O.C.INDEX_COLS)
    assertEquals(4, math.ceil(#O.INDEX / O.C.INDEX_COLS))   -- 4x4, full
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
    assertEquals("General", O.indexButtons[1].pageId)
    assertEquals("Cooldown", O.indexButtons[3].pageId)
    assertEquals("About", O.indexButtons[16].pageId)
    assertEquals(true, O.indexButtons[1]:IsEnabled())
    assertEquals(true, O.indexButtons[3]:IsEnabled())
    assertEquals(true, O.indexButtons[16]:IsEnabled())
    -- The Spell Timer cell: Forte_Timer's page registers its `SpellTimer`
    -- page, so the cell is LIVE (the law of the next test: a cell is enabled
    -- exactly while its page is registered -- docs/design-spell-timer.md §5.4's
    -- acceptance is exactly this light-up). A genuinely unbuilt page is the
    -- disabled case.
    assertEquals("SpellTimer", O.indexButtons[2].pageId)
    assertEquals(true, O.indexButtons[2]:IsEnabled())
    assertNotNil(O.indexButtons[2]:GetScript("OnClick"))
    assertEquals(false, O.indexButtons[13]:IsEnabled())   -- Talent Spy
end)

test("module index: a cell is enabled EXACTLY while its page is registered",
function()
    -- The general law (O:RefreshIndexCells): registered page -> enabled cell
    -- + its OnClick; unregistered -> disabled + the 'not built yet' tooltip.
    -- Dropping and re-adding a live page proves it is the LIVE store, not a
    -- build-time snapshot -- that is the case Forte_Hunter creates (its page
    -- registers at PLAYER_LOGIN, the loader may have built the shell first).
    O:Open("General")
    local id = "Cooldown"
    local i
    for n, entry in ipairs(O.INDEX) do
        if entry.id == id then i = n end
    end
    assertNotNil(i)
    local btn = O.indexButtons[i]
    assertEquals(true, btn:IsEnabled())
    assertNotNil(btn:GetScript("OnClick"))
    local saved = O.pages[id]
    O.pages[id] = nil
    O:RefreshIndexCells()
    assertEquals(false, btn:IsEnabled())
    assertNil(btn:GetScript("OnClick"))
    near(0.45, btn.art:GetAlpha())
    near(0.45, btn.chip:GetAlpha())
    O.pages[id] = saved
    O:RefreshIndexCells()
    assertEquals(true, btn:IsEnabled())
    assertNotNil(btn:GetScript("OnClick"))
    near(1.0, btn.art:GetAlpha())
    near(1.0, btn.chip:GetAlpha())
    -- Idempotence: a second refresh changes nothing.
    O:RefreshIndexCells()
    assertEquals(true, btn:IsEnabled())
    O:Close()
end)

test("module index: the Hunter Tools cell lives with the page and opens it",
function()
    local P = FX.Hunter and FX.Hunter.Pages
    if not P or not P.RegisterHunterPage then
        print("[index] Forte_Hunter not installed -- skipped")
        return
    end
    local i, entry
    for n, e in ipairs(O.INDEX) do
        if e.id == "Hunter" then i, entry = n, e end
    end
    assertNotNil(entry)
    assertEquals("Hunter Tools", entry.label)
    -- The cell's colour IS the Hunter page header's tint (the same table the
    -- page def carries: O.C.BROWN, the gold/brown of Pages/Hunter.lua).
    assertEquals(true, P.RegisterHunterPage())
    assertEquals(O.pages["Hunter"].colour, entry.colour)
    assertEquals(O.C.BROWN, entry.colour)

    -- Built BEFORE the shell: the cell arrives enabled.
    O:Open("General")
    local btn = O.indexButtons[i]
    assertEquals("Hunter", btn.pageId)
    assertEquals(true, btn:IsEnabled())
    assertNotNil(btn:GetScript("OnClick"))
    local r, g = btn.label:GetTextColor()
    assertTrue(r >= 0.99 and g >= 0.7, "the live cell keeps the gold label")

    -- Registering AFTER the shell was built lights the cell in place (the
    -- Forte_Hunter PLAYER_LOGIN path).
    local saved = O.pages["Hunter"]
    O.pages["Hunter"] = nil
    O:RefreshIndexCells()
    assertEquals(false, btn:IsEnabled())
    O.pages["Hunter"] = saved
    O:RefreshIndexCells()
    assertEquals(true, btn:IsEnabled())

    -- The click opens the page.
    btn:GetScript("OnClick")(btn, "LeftButton")
    assertEquals("Hunter", O.pageId)
    local page = O.pagesBuilt["Hunter"]
    assertNotNil(page)
    assertEquals(7, #page.sections)   -- Tips/Basics/Sizing/Coloring
                                      -- + Shot Cycle/Range Light/
                                      -- Combat Alpha (swing v2)
    local _, _, _, xcell = btn:GetPoint()
    local _, _, _, xcell5 = O.indexButtons[13]:GetPoint()
    assertTrue(xcell > xcell5, "the Hunter cell sits right of Talent Spy")
    O:Close()
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

-- Wave 4 (OptionsCD) items 2 + 4 on the Cooldown page: the rows of the
-- source's SPECIFICS icon block (:1716-1719), its SPLASH block
-- (:1723-1724) and its TIME RANGE filters (:1729-1732), plus the label
-- fixes. The labels are the source's strings (Forte_Cooldown/
-- Localization.lua) and the defaults its InstanceDefault.Cooldown.
test("Cooldown page: the wave-4 rows ride Specifics with the source's labels",
function()
    O:Open("Cooldown")
    local page = O.pagesBuilt["Cooldown"]
    local byKey, inSpecifics = {}, {}
    for si, sec in ipairs(page.sections) do
        for _, wd in ipairs(sec.widgets) do
            if wd.spec.key then
                byKey[wd.spec.key] = wd
                if si == 3 then inSpecifics[wd.spec.key] = true end
            end
        end
    end
    -- key, label (the source's wording), default (:1818, :1819, :1835,
    -- :1837, :1811, :1812, :1826-:1829)
    local rows = {
        { "BarAlpha",        "Minimum bar alpha",            0.2 },
        { "BarAlphaMax",     "Maximum bar alpha",            1.0 },
        { "IconTime",        "Show Icon text",               true },
        { "IconTextColorOn", "Use custom icon text color",   false },
        { "IconTextColor",   "Icon text color",              nil },
        { "Splash",          "Splash ready cooldowns",       true },
        { "SplashFactor",    "Splash icon active scale",     4 },
        { "MinRangeOn",      "Enable minimum duration filter",   false },
        { "MinRange",        "Minimum duration",             0 },
        { "MaxRangeOn",      "Enable maximum duration filter",   false },
        { "MaxRange",        "Maximum duration",             3600 },
        { "MinRemainingOn",  "Enable minimum remaining filter",  false },
        { "MinRemaining",    "Minimum remaining",            0 },
        { "MaxRemainingOn",  "Enable maximum remaining filter",  false },
        { "MaxRemaining",    "Maximum remaining",            3600 },
    }
    for _, row in ipairs(rows) do
        local key, label, def = row[1], row[2], row[3]
        local w = byKey[key]
        assertNotNil(w, key .. " has no row on the page")
        assertTrue(inSpecifics[key], key .. " rides the Specifics section")
        assertEquals(label, w.label:GetText())
        if def ~= nil then
            assertEquals(def, S:GetDefault("Cooldown", key))
        end
    end
    local col = S:GetDefault("Cooldown", "IconTextColor")
    assertEquals(1, col[1]); assertEquals(1, col[2]); assertEquals(1, col[3])
    assertEquals(1, col[4])
    -- The section recycle covers the new keys (the keys list is the set).
    local rec = page.sections[3].bar.recycle
    S:Set("Cooldown", "SplashFactor", 11)
    S:Set("Cooldown", "MinRemaining", 77)
    S:Set("Cooldown", "IconTime", false)
    rec:GetScript("OnClick")(rec)
    assertEquals(4, S:Get("Cooldown", "SplashFactor"))
    assertEquals(0, S:Get("Cooldown", "MinRemaining"))
    assertEquals(true, S:Get("Cooldown", "IconTime"))
end)

test("Cooldown/Splash/General pages: the labels are the source's words",
function()
    -- Item 2: four relabels on the Cooldown page, three on the Splash page,
    -- one on the General page. Every string is the original's, verbatim.
    local function labelsOf(id)
        O:Open(id)
        local out = {}
        for _, sec in ipairs(O.pagesBuilt[id].sections) do
            for _, wd in ipairs(sec.widgets) do
                if wd.spec.key and wd.label then
                    out[wd.spec.key] = wd.label:GetText()
                end
            end
        end
        return out
    end
    local cd = labelsOf("Cooldown")
    assertEquals("Hide when out of combat", cd.HideCombat)   -- FWL.TIMER_HIDE
    assertEquals("Time scale max (sec)", cd.MaxTime)         -- CD_SPECIFIC6
    assertEquals("Use power of", cd.PowerScale)              -- USE_POWER_OF
    assertEquals("Show icon Glow", cd.Spark)                 -- SHOW_GLOW
    local sp = labelsOf("Splash")
    assertEquals("Enable Secondary Splash icon", sp.Enable)  -- CD_SPLASH3
    assertEquals("Splash icon active scale", sp.SecondSplashMax)
    assertEquals("Show icon Glow", sp.SplashGlow)
    local ge = labelsOf("General")
    assertEquals("Show module frame Tooltips", ge.ShowTooltips)  -- FWL.TIPS
    assertEquals("Alternate time format", ge.AltTimeFormat)      -- GENERAL_MO2
    assertEquals("Enable frame snapping", ge.FrameSnap)          -- GENERAL_MO3
    assertEquals("Global Frame Lock", ge.GlobalLock)             -- GLOBAL_LOCK
    assertEquals("Global Frame Alpha", ge.FrameAlpha)            -- GLOBAL_ALPHA
    -- Item 3: the source's `TimeFormat` ships ON (Forte_Core.lua:2487), so a
    -- fresh install prints m:ss; the consumer is the bar's SetTimeFormatAlt
    -- (Forte_Cooldown/tests/test_timeline.lua proves the text moves).
    assertEquals(true, S:GetDefault("General", "AltTimeFormat"))
    assertEquals(true, FX.Cooldown.TimelineSkin.TimeFormatAlt)
end)

test("m4: /fx lock|unlock publish into Lock AND GlobalLock", function()
    local d = FX.Cooldown.Display
    d:SetLocked(true)
    assertEquals(true, S:Get("Cooldown", "Lock"))
    assertEquals(true, S:Get("General", "GlobalLock"))
    FX.OnSlash("unlock")
    assertEquals(false, d.cfg.locked)
    assertEquals(false, S:Get("Cooldown", "Lock"))
    assertEquals(false, S:Get("General", "GlobalLock"))
    FX.OnSlash("lock")
    assertEquals(true, d.cfg.locked)
    assertEquals(true, S:Get("Cooldown", "Lock"))
    assertEquals(true, S:Get("General", "GlobalLock"))
end)

test("m4: the Cooldown page reads the LIVE lock (/fx unlock -> box unchecked)",
function()
    local d = FX.Cooldown.Display
    FX.OnSlash("unlock")
    O:Open("Cooldown")
    local page = O.pagesBuilt["Cooldown"]
    local lockW
    for _, wd in ipairs(page.sections[2].widgets) do
        if wd.spec.key == "Lock" then lockW = wd end
    end
    assertNotNil(lockW)
    lockW.refresh()
    assertEquals(false, lockW.obj:GetChecked())
    -- The header lock icon follows the live state: unlocked = gold.
    local r, g = O.header.lockText:GetTextColor()
    assertTrue(r >= 0.99 and g >= 0.7, "unlocked header icon is gold")
    -- Click the box -> the setting flips -> the bar is LOCKED.
    lockW.obj:GetScript("OnClick")(lockW.obj, "LeftButton")
    assertEquals(true, d.cfg.locked)
    assertEquals(true, S:Get("Cooldown", "Lock"))
    assertEquals(true, S:Get("General", "GlobalLock"))
    -- And the General page's mirror reads the same live truth.
    O:Open("General")
    local gl
    for _, wd in ipairs(O.pagesBuilt["General"].sections[2].widgets) do
        if wd.spec.key == "GlobalLock" then gl = wd end
    end
    assertNotNil(gl)
    gl.refresh()
    assertEquals(true, gl.obj:GetChecked())
    d:SetLocked(true)
    O:Close()
end)

-- CodeReview2 n4: BuildHeader read the *Cooldown bar's* live lock for EVERY
-- page. The Hunter page's lockKey is Hunter.Lock and its frame is the swing
-- bar -- Swing publishes Hunter.Lock only (Swing.lua:278-290), the Cooldown
-- bar's lock never moves it -- so the two states can legitimately differ.
test("n4: the Hunter page header follows Hunter.Lock, not the Cooldown bar",
function()
    local P = FX.Hunter and FX.Hunter.Pages
    local swing = FX.Hunter and FX.Hunter.Swing
    -- Forte_Hunter is in the gate's addon path for every suite; a missing
    -- page/bar here is a real regression, not a skip.
    assertNotNil(P and P.RegisterHunterPage, "the Hunter page module")
    assertNotNil(swing, "FX.Hunter.Swing")
    P.RegisterHunterPage()
    -- The Hunter UI module builds the bar for a HUNTER only (Swing.lua's
    -- OnEnable class gate); this suite's char is whatever the sim picked, so
    -- the test builds it -- Init is the module's own entry point and is
    -- idempotent.
    if not swing.cfg then swing:Init() end
    assertNotNil(swing.cfg, "the swing bar is built")
    assertNotNil(swing.cfg.locked, "and its live lock state exists")
    -- The divergence: the timeline bar LOCKED first (its publish relocks
    -- the swing bar through the Swing's Cooldown/GlobalLock listeners),
    -- then the Hunter swing bar is set free -- Hunter.Lock is the only key
    -- that moves it back, so the two frames now disagree by construction.
    local d = FX.Cooldown.Display
    d:SetLocked(true)
    swing:SetLocked(false)
    assertEquals(true, d.cfg.locked, "the bar is locked")
    assertEquals(false, swing.cfg.locked, "the swing bar is not")
    assertEquals(false, S:Get("Hunter", "Lock"))

    O:Open("Hunter")
    local r, g = O.header.lockText:GetTextColor()
    assertTrue(g >= 0.70 and r >= 0.99,
        "the Hunter header reads the swing bar (gold = unlocked)")
    -- The header's own click still moves Hunter.Lock.
    local lock = O.header.lockText:GetParent()
    lock:GetScript("OnClick")(lock)
    assertEquals(true, S:Get("Hunter", "Lock"))
    assertEquals(true, swing.cfg.locked, "and the swing bar followed")
    assertEquals(true, d.cfg.locked, "the Cooldown bar never moved")
    r, g = O.header.lockText:GetTextColor()
    assertTrue(r < 0.90 and g < 0.90, "locked Hunter header is grey")

    -- The same session, the Cooldown page: its header still reads ITS bar.
    O:Open("Cooldown")
    r, g = O.header.lockText:GetTextColor()
    assertTrue(r < 0.90 and g < 0.90, "the Cooldown header follows its bar")
    -- Shared defaults back for the tests that follow.
    swing:SetLocked(true)
    d:SetLocked(true)
    O:Close()
end)

-- CodeReview3 C4: the n4 fix above hard-branched `Hunter / everything-else
-- -> FX.Cooldown.Display`, encoding that day's module world. The pages
-- added since -- SpellTimer and the four Warlock plates -- fell into the
-- `or` branch and read the *Cooldown bar's* lock, re-opening the exact n4
-- divergence (a locked bar painting a locked glyph over an unlocked,
-- draggable frame). The law is now data: every page hands BuildHeader its
-- OWN live frame (def.lockFrame); this test pins every one of the five new
-- pages against a deliberate divergence from the Cooldown bar.
test("C4: the SpellTimer and the four Warlock headers follow THEIR frames",
function()
    local d = FX.Cooldown and FX.Cooldown.Display
    assertNotNil(d, "the timeline bar is the reference frame")
    assertNotNil(FX.Timer and FX.Timer.Display, "the spell-timer panel")
    local TM = FX.Timer and FX.Timer.Module
    assertNotNil(TM and TM.SetLocked, "the spell-timer module")
    assertNotNil(O.pages["SpellTimer"], "the SpellTimer page is registered")
    local WK = FX.Warlock
    assertNotNil(WK and WK.Shards, "the warlock plates are loaded")
    for _, id in ipairs({ "ShardManager", "Soulstone", "Healthstone",
    "Summon" }) do
        assertNotNil(O.pages[id], "the page " .. id)
    end

    -- One locked baseline: the bar's publish (Cooldown.Lock +
    -- GlobalLock, m4) moves every self-wired frame with it.
    d:SetLocked(true)

    -- SpellTimer: the module's SetLocked publishes SpellTimer.Lock
    -- ONLY -- the Cooldown bar never moves -- so the two frames
    -- legitimately diverge.
    TM:SetLocked(false)
    assertEquals(true, d.cfg.locked, "the timeline bar is locked")
    assertEquals(false, FX.Timer.Display.cfg.locked, "the panel is not")
    O:Open("SpellTimer")
    local r, g = O.header.lockText:GetTextColor()
    assertTrue(g >= 0.70 and r >= 0.99,
        "the SpellTimer header reads the panel (gold = unlocked)")
    -- The same session, the Cooldown page: its header still reads ITS bar.
    O:Open("Cooldown")
    r, g = O.header.lockText:GetTextColor()
    assertTrue(r < 0.90 and g < 0.90, "the Cooldown header follows its bar")

    -- The four Warlock pages: set the Soulstone plate free while the bar
    -- stays locked. Where the plates self-wire (a WARLOCK profile) they
    -- share the one Warlock.Lock key and move as one unit -- assert that
    -- law, then every page reads gold. On the gate's profile (not a
    -- warlock: the plates are un-Init'ed, no wiring, cfg = the skin
    -- default) only the touched plate frees itself -- its page reads gold,
    -- the locked plates' pages stay grey.
    assertEquals(true, d.cfg.locked, "the bar was never touched")
    WK.Soulstone:SetLocked(false)
    assertEquals(false, WK.Soulstone.cfg.locked)
    local movesAsOneUnit = (WK.Shards.cfg.locked == false)
    for _, pair in ipairs({
        { id = "ShardManager", view = "Shards" },
        { id = "Soulstone", view = "Soulstone" },
        { id = "Healthstone", view = "Healthstone" },
        { id = "Summon", view = "Summon" },
    }) do
        if movesAsOneUnit then
            assertEquals(false, WK[pair.view].cfg.locked,
                pair.view .. " rides the shared Warlock.Lock")
        end
        O:Open(pair.id)
        local rr, gg = O.header.lockText:GetTextColor()
        if WK[pair.view].cfg.locked then
            assertTrue(rr < 0.90 and gg < 0.90,
                pair.id .. ": the locked plate paints the grey glyph")
        else
            assertTrue(gg >= 0.70 and rr >= 0.99,
                pair.id .. ": the unlocked plate paints the gold glyph")
        end
    end

    -- Shared defaults back for the tests that follow.
    for _, name in ipairs({ "Shards", "Soulstone", "Healthstone", "Summon" }) do
        WK[name]:SetLocked(true)
    end
    TM:SetLocked(true)
    d:SetLocked(true)
    O:Close()
end)

test("T9 live wiring: a Width edit on the page resizes the live bar", function()
    O:Open("Cooldown")
    local page = O.pagesBuilt["Cooldown"]
    local widthW
    for _, wd in ipairs(page.sections[3].widgets) do
        if wd.spec.key == "Width" then widthW = wd end
    end
    assertNotNil(widthW)
    widthW.obj:SetText("320")
    widthW.obj:GetScript("OnEnterPressed")(widthW.obj)
    assertEquals(320, FX.Cooldown.Display.anchor:GetWidth())
    -- The per-row recycle restores the default AND the bar follows.
    widthW.resetBtn:GetScript("OnClick")(widthW.resetBtn)
    assertEquals(250, S:Get("Cooldown", "Width"))
    assertEquals(250, FX.Cooldown.Display.anchor:GetWidth())
    O:Close()
end)

test("T9 live wiring: the ColorSpell row retints the live segments", function()
    O:Open("Cooldown")
    local d = FX.Cooldown.Display
    local page = O.pagesBuilt["Cooldown"]
    local colW
    for _, wd in ipairs(page.sections[4].widgets) do
        if wd.spec.key == "ColorSpell" then colW = wd end
    end
    assertNotNil(colW)
    local custom = { 0.30, 0.20, 0.90, 1 }
    S:Set("Cooldown", "ColorSpell", custom)
    local now = GetTime() + 90000
    d:Update({
        { name = "OptsProbe", start = 0, duration = 120, endTime = now + 120 },
    }, now)
    local slot = d._byName["OptsProbe"]
    assertNotNil(slot)
    local r, g, b = slot.seg:GetVertexColor()
    assertTrue(math.abs(r - custom[1]) < 1e-3)
    assertTrue(math.abs(g - custom[2]) < 1e-3)
    assertTrue(math.abs(b - custom[3]) < 1e-3)
    S:Reset("Cooldown", "ColorSpell")
    d:Update({}, now + 1)
    O:Close()
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
            -- Wave 6: these rows are SEL pickers now; the overprint law
            -- rides the picker: the button starts right of the label, the
            -- caption is clipped to one line, the button sits in the row.
            local g2 = wd.obj:GetLeft() - wd.label:GetRight()
            assertTrue(g2 >= 4 - 0.5,
                "picker overprint " .. tostring(wd.spec.key))
            local ml = (wd.caption.GetMaxLines
                and wd.caption:GetMaxLines())
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

test("title: player-realm from GetRealmName, never a dangling dash", function()
    O:Open("General")
    local text = O.titleFS:GetText()
    local name = UnitName("player")
    assertTrue(text:find("by Xus - " .. name, 1, true) ~= nil, "title names the player: " .. text)
    assertTrue(text:sub(-1) ~= "-", "no trailing dash: " .. text)
    local realm = GetRealmName and GetRealmName()
    if type(realm) == "string" and realm ~= "" then
        assertTrue(text:find(name .. "-" .. realm, 1, true) ~= nil, "realm appended: " .. text)
    end
    O:Close()
end)

test("title: a raising name read costs the NAME, not the window (K9 m3)",
function()
    -- K9 m3 (docs/reviews/code-review-9.md MINOR 3): the UnitName
    -- fallback of the title read is SecretWhenUnitIdentityRestricted --
    -- raise-prone -- and rode bare. The shell is built once by O:Build,
    -- so the leg drives Build over a FRESH receiver (the file's methods
    -- take `self` = the module; the reads are Build's own lines) with the
    -- identity seams poisoned: Identity answers nil (no cache) and
    -- UnitName RAISES. Pre-fix the bare `UnitName("player")` call raised
    -- out of Build -- the first assert below fails on it.
    local saved = {
        UnitName = _G.UnitName,
        SelfName = FX.Identity.SelfName,
    }
    -- The shell's frame name is unique: hand the fresh build the NAME
    -- slot for the ride (the live shell keeps its object in O.window,
    -- only the global registration steps aside).
    local NAME = "ForteXorcistOptionsWindow"
    local savedGlobal = _G[NAME]
    local ok, built, text
    do
        _G[NAME] = nil
        FX.Identity.SelfName = function() return nil end
        _G.UnitName = function() error("FXTEST-IDENTITY-LOCKED", 0) end
        -- The fresh receiver rides `self` through Build, its callees and
        -- the module constants -- EXCEPT the live shell's own state:
        -- `window` is Build's once-built guard (inheriting it made Build
        -- early-return the LIVE shell) and `profileTabs` is the live
        -- shell's widget list (RefreshProfileTabs would hide them).
        local liveState = { window = true, profileTabs = true }
        local fresh = setmetatable({}, { __index = function(_, k)
            if liveState[k] then return nil end
            return O[k]
        end })
        ok, built = pcall(O.Build, fresh)
        if ok and built then
            text = fresh.titleFS:GetText()
            built:Hide()
            pcall(built.SetParent, built, nil)   -- the shell down
        end
        _G[NAME] = savedGlobal
    end
    _G.UnitName = saved.UnitName
    FX.Identity.SelfName = saved.SelfName
    if not ok then
        error("FXTEST-BUILD-RAISED: " .. tostring(built), 0)
    end
    assertTrue(true, "the build swallows the raising name read")
    assertNotNil(text, "the title built over the failed read")
    assertTrue(text:find("by Xus - ?", 1, true) ~= nil,
        "the name falls back to the ? placeholder: " .. text)
end)

-- ================================== CD-35 geometry + CD-31 Warn page rows ==
-- CD-35 (spec §1.5) the original's BASICS rows `Vertical` (:1705 "Flip to
-- vertical"), `Flip` (:1706 "Flip bar direction") and its auto-hide row
-- (:1707 "Auto-hide when no cooldowns"), plus CD-31's SPECIFICS `Warn` row
-- (:1714 "Spell on cooldown Warning"): the page must REGISTER the shipped
-- defaults (:1808, :1809, :1815, :1821), BUILD the row, and drive the live bar
-- through the FX.Settings -> Display:ApplySettings seam. The bar laws
-- themselves belong to Forte_Cooldown/tests/test_timeline.lua; what is proven
-- here is the page, the defaults and the live wiring.
test("Cooldown page: Vertical/Flip/HideZero/Warn register at the shipped defaults and drive the bar",
function()
    local D = FX.Cooldown.Display
    local skin = FX.Cooldown.TimelineSkin
    assertNotNil(D, "the Cooldown Display is live")
    O:Open("Cooldown")
    -- Defaults verbatim from FW.InstanceDefault.Cooldown.
    assertEquals(false, S:GetDefault("Cooldown", "Vertical"))   -- :1808
    assertEquals(false, S:GetDefault("Cooldown", "Flip"))        -- :1809
    assertEquals(false, S:GetDefault("Cooldown", "HideZero"))    -- :1815
    assertEquals(true, S:GetDefault("Cooldown", "Warn"))         -- :1821
    local page = O.pagesBuilt["Cooldown"]
    local function widget(section, key)
        for _, wd in ipairs(section.widgets) do
            if wd.spec.key == key then return wd end
        end
    end
    local basics, specifics = page.sections[2], page.sections[3]
    local vertical = widget(basics, "Vertical")
    local flip = widget(basics, "Flip")
    local hideZero = widget(basics, "HideZero")
    local warn = widget(specifics, "Warn")
    assertNotNil(vertical, "BASICS carries the Vertical row")
    assertNotNil(flip, "BASICS carries the Flip row")
    assertNotNil(hideZero, "BASICS carries the auto-hide row")
    assertNotNil(warn, "SPECIFICS carries the Warn row")

    -- Vertical: the frame swaps its width and height (Forte_Cooldown.lua
    -- :1476-1479: SetWidth(Height + 2*d) / SetHeight(Width + 2*d)) straight
    -- from the checkbox click. The measured pair is the page's live Width /
    -- Height settings swapped (a sibling test may have moved them).
    local wpx, hpx = S:Get("Cooldown", "Width"), S:Get("Cooldown", "Height")
    vertical.refresh()
    assertEquals(false, vertical.obj:GetChecked())
    vertical.obj:GetScript("OnClick")(vertical.obj, "LeftButton")
    assertEquals(true, S:Get("Cooldown", "Vertical"))
    assertEquals(true, skin.Vertical)
    assertEquals(hpx, D.anchor:GetWidth())
    assertEquals(wpx, D.anchor:GetHeight())
    S:Set("Cooldown", "Vertical", false)
    assertEquals(false, skin.Vertical)
    assertEquals(wpx, D.anchor:GetWidth())
    assertEquals(hpx, D.anchor:GetHeight())

    -- Flip: the icons run from the far end. The live witness is a slot's
    -- anchor point, so feed the bar through the Module's own seam.
    flip.obj:GetScript("OnClick")(flip.obj, "LeftButton")
    assertEquals(true, skin.Flip)
    local now = 210000
    D:Update({ { name = "FlipRow", start = 0, duration = 999,
        endTime = now + 120 } }, now)
    local slot = D._byName["FlipRow"]
    assertNotNil(slot)
    assertEquals("RIGHT", slot.frame:GetPoint())
    S:Set("Cooldown", "Flip", false)
    D:Update({ { name = "FlipRow", start = 0, duration = 999,
        endTime = now + 120 } }, now)
    assertEquals("LEFT", D._byName["FlipRow"].frame:GetPoint())
    D:Update({}, now + 1)

    -- HideZero: the visibility gate (Draw :1348). With nothing on the bar the
    -- bar itself goes away, and comes straight back.
    hideZero.obj:GetScript("OnClick")(hideZero.obj, "LeftButton")
    assertEquals(true, D.frameState.hideZero)
    D:Update({}, 210002)
    assertFalse(D.anchor:IsShown(), "an empty bar auto-hides")
    S:Set("Cooldown", "HideZero", false)
    D:Update({}, 210003)
    assertTrue(D.anchor:IsShown())

    -- Warn: the source registers / unregisters the UNIT_SPELLCAST_FAILED
    -- handler on exactly this flag (:953-960), so the box's live witness is
    -- the Display's own event frame.
    assertEquals(true, skin.Warn)
    assertNotNil(D._eventFrame:GetScript("OnEvent"))
    warn.obj:GetScript("OnClick")(warn.obj, "LeftButton")
    assertEquals(false, S:Get("Cooldown", "Warn"))
    assertNil(D._eventFrame:GetScript("OnEvent"), "the handler is unregistered")
    warn.obj:GetScript("OnClick")(warn.obj, "LeftButton")
    assertEquals(true, S:Get("Cooldown", "Warn"))
    assertNotNil(D._eventFrame:GetScript("OnEvent"), "and registered again")
end)

test("Cooldown page: the Basics / Specifics section recycles restore the new rows", function()
    O:Open("Cooldown")
    local D = FX.Cooldown.Display
    local skin = FX.Cooldown.TimelineSkin
    local page = O.pagesBuilt["Cooldown"]
    local basics, specifics = page.sections[2], page.sections[3]
    S:Set("Cooldown", "Vertical", true)
    S:Set("Cooldown", "Flip", true)
    S:Set("Cooldown", "HideZero", true)
    S:Set("Cooldown", "Warn", false)
    basics.bar.recycle:GetScript("OnClick")(basics.bar.recycle)
    assertEquals(false, S:Get("Cooldown", "Vertical"))
    assertEquals(false, S:Get("Cooldown", "Flip"))
    assertEquals(false, S:Get("Cooldown", "HideZero"))
    -- The section's other keys are intact, and so is the bar's geometry.
    assertEquals(true, S:Get("Cooldown", "Enable"))
    assertEquals(false, S:Get("Cooldown", "HideCombat"))
    assertEquals(false, skin.Vertical)
    assertEquals(false, skin.Flip)
    assertEquals(S:Get("Cooldown", "Width"), D.anchor:GetWidth())
    assertEquals(S:Get("Cooldown", "Height"), D.anchor:GetHeight())
    assertEquals(false, D.frameState.hideZero)
    assertTrue(D.anchor:IsShown())
    -- Specifics recycles Warn back to its shipped on-state, and leaves the
    -- neighbouring geometry keys of its own section alone.
    specifics.bar.recycle:GetScript("OnClick")(specifics.bar.recycle)
    assertEquals(true, S:Get("Cooldown", "Warn"))
    assertEquals(true, skin.Warn)
    assertNotNil(D._eventFrame:GetScript("OnEvent"))
    assertEquals(250, S:Get("Cooldown", "Width"))
    assertEquals(2.99, S:Get("Cooldown", "IgnoreShort"))
end)

-- ============================ F-C: the "Item proc timers (experimental)" row
-- The `Cooldown.Procs` flag (H7) got its page row on slice F-C (2026-11-03).
-- The box is the ONLY public face of Forte_Cooldown/Core/Procs.lua, and its
-- live half is THAT module's own `Procs:_WireSettings` listener (the
-- Forte_Cooldown-must-work-without-Forte_Options law): the box writes the
-- store through FX.Settings, the listener runs `Procs:SetEnabled`, and the
-- first enable asks `FX.LoadAddOnOnDemand("Forte_ItemProcs")` for the
-- load-on-demand proc data (docs/perf.md §4 fix 1) -- the reason the default
-- is OFF. The row is looked up by key in SPECIFICS, so on the pre-F-C page
-- (no Procs widget, no SPECIFICS key) this test fails at the lookup: that IS
-- the fails-on-the-old-code proof. `C_AddOns` is stubbed for the cycle, so
-- "the data add-on loads once" is a COUNT and the suite never really pulls
-- the 400 proc rows into the session; the shipped OFF default, the real
-- loader and the load ledger are restored before the test returns.
test("Cooldown page: the Item proc timers box is the live Cooldown.Procs switch",
function()
    local P = FX.Cooldown and FX.Cooldown.Engine and FX.Cooldown.Engine.Procs
    assertNotNil(P, "the proc tracker of the cooldown engine is live")
    O:Open("Cooldown")
    local page = O.pagesBuilt["Cooldown"]
    local function widget(section, key)
        for _, wd in ipairs(section.widgets) do
            if wd.spec.key == key then return wd end
        end
    end
    local procs = widget(page.sections[3], "Procs")
    assertNotNil(procs, "SPECIFICS carries the Item proc timers row")
    local label = procs.spec.label or ""
    assertTrue(label:find("Item proc timers") ~= nil, "the row names the feature")
    assertTrue(label:find("%(experimental%)") ~= nil, "and says experimental")
    local tip = (procs.spec.tip or ""):lower()
    assertTrue(tip:find("experimental") ~= nil, "the tip says experimental")
    assertTrue(tip:find("launch%-day probe") ~= nil,
        "the tip names in-combat proc detection a launch-day probe")

    -- The shipped default, and the box reading it.
    assertEquals(false, S:GetDefault("Cooldown", "Procs"))
    assertEquals(false, S:Get("Cooldown", "Procs"))
    assertEquals(false, P:IsEnabled(), "the tracker starts off")
    procs.refresh()
    assertEquals(false, procs.obj:GetChecked())

    local savedAPI = _G.C_AddOns
    local savedLedger = FX._loadedAddOns["Forte_ItemProcs"]
    local calls = 0
    FX._loadedAddOns["Forte_ItemProcs"] = nil
    _G.C_AddOns = {
        LoadAddOn = function(name)
            assertEquals("Forte_ItemProcs", name, "the loader is asked for the proc data")
            calls = calls + 1
            return true
        end,
        IsAddOnLoaded = function() return false, false end,
    }
    local ok, why = pcall(function()
        -- ON: the real widget's click. The enable must be live on the next
        -- statement -- no reload, no re-open: the OnChange path is the wire.
        procs.obj:GetScript("OnClick")(procs.obj, "LeftButton")
        assertEquals(true, S:Get("Cooldown", "Procs"))
        assertTrue(P:IsEnabled(), "the click enabled the tracker")
        assertEquals(1, calls, "the load-on-demand data add-on was asked for")
        procs.refresh()
        assertTrue(procs.obj:GetChecked(), "the box reads the store back")
        -- OFF: the same box, the flag down, the watched set gone, and no
        -- second ask of the loader.
        procs.obj:GetScript("OnClick")(procs.obj, "LeftButton")
        assertEquals(false, S:Get("Cooldown", "Procs"))
        assertFalse(P:IsEnabled(), "the same click disables it")
        assertEquals(0, (P:Counts()), "and drops every watched proc")
        assertEquals(1, calls, "no second load across the cycle")
        procs.refresh()
        assertEquals(false, procs.obj:GetChecked())
        -- ON a second time: the ledger settles the name, so the feature
        -- comes up with NO loader call at all.
        procs.obj:GetScript("OnClick")(procs.obj, "LeftButton")
        assertTrue(P:IsEnabled(), "the box drives the tracker again")
        assertEquals(1, calls, "the loader is idempotent: never asked twice")
    end)
    -- Restore, on the success path AND on a failed assert inside the pcall.
    _G.C_AddOns = savedAPI
    FX._loadedAddOns["Forte_ItemProcs"] = savedLedger
    S:Set("Cooldown", "Procs", false)
    assertFalse(P:IsEnabled(), "the session leaves with the shipped OFF flag")
    assertTrue(ok, "the box drives the tracker: " .. tostring(why))
end)

-- ==================== Wave 6 'Options cosmetics': the General pickers =======
-- The Bar Font / Bar Texture INFO placeholders became the original's FNT/TXT
-- pickers (docs/research/options-fidelity.md fix-list item 9; the original
-- General rows Forte_Core/Options.lua:5555-5556): the row's REAL widget
-- opens the REAL popup, and a pick is the single Settings write the
-- existing consumers already ride -- the Cooldown bar's SetBarFont /
-- SetBarTexture (Forte_Cooldown/UI/Timeline.lua "live settings"). The font
-- list is the one loadable vendored file (addon/Forte_Core/Fonts/; the .otf
-- twin is license source, PLAN §3.5), the texture list the 19 original
-- FW.TextureList bar textures (Forte_Core.lua:644-668) as vendored.
local function widgetIn(page, sectionNo, key)
    for _, wd in ipairs(page.sections[sectionNo].widgets) do
        if wd.spec.key == key then return wd end
    end
end

test("General Bar Font picker: a pick through the popup re-applies the bar text",
function()
    local D = FX.Cooldown.Display
    D:Init()
    local shipped = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
    local NOPE = "Interface\\AddOns\\Forte_Core\\Fonts\\NOPE.ttf"
    O:Open("General")
    local page = O.pagesBuilt["General"]
    local sel = widgetIn(page, 3, "BarFont")
    assertNotNil(sel, "the Appearance section carries the Bar Font picker")
    assertEquals("URW Gothic Book", sel.caption:GetText(),
        "the button names the stored file by its vendored label")
    local tag = D.tagFS[1]
    assertNotNil(tag, "the bar's tags are live")
    -- Leave the shipped state through the store (the seam itself is
    -- test_timeline's BarFont test); the caption falls back to the
    -- basename of the off-list path. The sim raises on no path, so NOPE is
    -- applied under the PLAN §11.12 law (only a raise rejects).
    S:Set("General", "BarFont", NOPE)
    sel.refresh()
    assertEquals("NOPE.ttf", sel.caption:GetText())
    assertTrue(tag:GetFont():lower() == NOPE:lower(), "the tag rides NOPE")
    -- THE PICK, through the real widget: open, click the list's row.
    sel.obj:GetScript("OnClick")(sel.obj)
    assertTrue(sel.popup:IsShown())
    local item = sel.popupItems[1]
    item:GetScript("OnClick")(item)
    assertEquals(shipped, S:Get("General", "BarFont"))
    assertTrue(tag:GetFont():lower() == shipped:lower(),
        "the pick re-applied the font live")
    assertFalse(sel.popup:IsShown(), "the pick closed the list")
    S:Reset("General", "BarFont")
    O:Close()
end)

test("General Bar Texture picker: a pick repaints the fill and a fresh segment",
function()
    local D = FX.Cooldown.Display
    D:Init()
    local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"
    O:Open("General")
    local page = O.pagesBuilt["General"]
    local sel = widgetIn(page, 3, "BarTexture")
    assertNotNil(sel, "the Appearance section carries the Bar Texture picker")
    assertEquals("Aluminium", sel.caption:GetText())
    -- The list is the original's own bar textures, vendored (fix-list
    -- item 9); the shipped default heads it.
    local items = sel.spec.items
    assertEquals(19, #items)
    assertEquals(TEX .. "Aluminium", items[1].value)
    local xeon
    for i, it in ipairs(items) do
        if it.value == TEX .. "Xeon" then xeon = i end
    end
    assertNotNil(xeon, "the vendored Xeon rides the list")
    -- THE PICK, through the real widget.
    sel.obj:GetScript("OnClick")(sel.obj)
    assertTrue(sel.popup:IsShown())
    sel.popupItems[xeon]:GetScript("OnClick")(sel.popupItems[xeon])
    assertEquals(TEX .. "Xeon", S:Get("General", "BarTexture"))
    assertEquals(TEX .. "Xeon", D.fill:GetTexture(), "the bar fill rides it")
    assertFalse(sel.popup:IsShown())
    -- A segment built on the next pass carries it too (SetBarTexture's
    -- live-pool + build-time law).
    local now = 33900
    D:Update({
        { name = "PickTex", start = 0, duration = 120, endTime = now + 120 },
    }, now)
    assertEquals(TEX .. "Xeon", D._byName["PickTex"].seg:GetTexture())
    S:Reset("General", "BarTexture")
    assertEquals(TEX .. "Aluminium", D.fill:GetTexture())
    D:Update({}, now + 1)
    O:Close()
end)
