-- addon/Forte_Options/tests/test_font_law.lua
-- PLAN §11.12 on the options window (Core/Widgets.lua, UI/Window.lua): a font
-- file the client has not rendered yet answers SetFont false / GetFont nil /
-- width 0 and is still perfectly usable; only a RAISE means unusable.
--   * W.validateFont / W.applyFont / W.fontString: a pending file is kept, the
--     fontstring's own template is used only when SetFont raised;
--   * the General BarFont picker's preview (tryPreviewFont, driven through the
--     real widget): a raising typed path is rejected with the template, any
--     other path is drawn in;
--   * measuring while pending: a 0 label width is not turned into a column (the
--     ratio column is used), a 0 tab caption width uses the fallback and the tab
--     row is laid out again once the file has rendered.
--
-- The stub patches the sim's one shared FontString method table (see
-- Forte_Core/tests/test_font_law.lua); the headless sim never fires a
-- C_Timer ticker, so the ticker is captured and driven by hand.
--
-- FAILS-ON-THE-OLD-CODE: validateFont / applyFont / tryPreviewFont all read
-- `GetFont()` back (nil on the pending stub -> fontFile nil, template, preview
-- refused), and the label/tab measures used the raw 0 width.

local FX = ForteXorcist
local O = FX.Options
local W = O.Widgets
local WC = W.C
local S = FX.Settings
local SHIPPED = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"

local function withFontStub(mode, body)
    local fs0 = UIParent:CreateFontString(nil, "OVERLAY")
    local idx = getmetatable(fs0).__index
    local real = { SetFont = idx.SetFont, GetFont = idx.GetFont,
        SetFontObject = idx.SetFontObject,
        GetUnboundedStringWidth = idx.GetUnboundedStringWidth }
    local st = { mode = mode, set = {}, obj = {}, tickers = {}, zeroWidth = false,
        raiseFor = function() return true end }
    idx.SetFont = function(self, path, size, flags)
        st.set[#st.set + 1] = { fs = self, path = path, size = size, flags = flags }
        if st.mode == "raise" and st.raiseFor(path) then
            error("FontString:SetFont(): invalid font asset (" .. tostring(path)
                .. "): file not found", 0)
        end
        self._stubFont = path
        return st.mode == "loaded"
    end
    idx.GetFont = function(self)
        if st.mode == "loaded" then return self._stubFont end
        return nil
    end
    idx.SetFontObject = function(self, name)
        st.obj[#st.obj + 1] = { fs = self, name = name }
        self._stubFont = nil
    end
    idx.GetUnboundedStringWidth = function(self)
        if st.zeroWidth then return 0 end
        return real.GetUnboundedStringWidth(self)
    end
    local realTicker = C_Timer.NewTicker
    C_Timer.NewTicker = function(interval, fn, iterations)
        local t = { interval = interval, fn = fn, iterations = iterations }
        function t:Cancel() self.cancelled = true end
        st.tickers[#st.tickers + 1] = t
        return t
    end
    local ok, err = pcall(body, st)
    st.mode, st.zeroWidth = "loaded", false
    for _, t in ipairs(st.tickers) do
        if not t.cancelled then pcall(t.fn) end
    end
    C_Timer.NewTicker = realTicker
    idx.SetFont, idx.GetFont, idx.SetFontObject, idx.GetUnboundedStringWidth =
        real.SetFont, real.GetFont, real.SetFontObject, real.GetUnboundedStringWidth
    if not ok then error(err, 0) end
end

--- The Options font verdict is cached on FX.Options (validate-once): reset it
--- around a leg so the stub is what the validator sees.
local function freshVerdict(body)
    local f, v = O.fontFile, O.fontVerified
    O.fontFile, O.fontVerified = nil, nil
    local ok, err = pcall(body)
    O.fontFile, O.fontVerified = f, v
    assertTrue(ok, tostring(err))
end

test("pending file: validateFont keeps the shipped file; fontStrings are applied in it",
function()
    assertEquals(FX.CLASSIC_FONT, WC.FONT_FILE, "the one shared constant")
    freshVerdict(function()
        withFontStub("pending", function(st)
            assertEquals(WC.FONT_FILE, W.validateFont(),
                "the validator must not veto a pending file")
            local fs = W.fontString(UIParent, "GameFontHighlightSmall", "x", WC.WHITE)
            assertEquals(WC.FONT_FILE, fs._stubFont)
            assertEquals(0, #st.obj, "no template while the file is merely pending")
        end)
    end)
end)

test("SetFont raising: validateFont is nil, fontStrings take their OWN template, nothing escapes",
function()
    freshVerdict(function()
        withFontStub("raise", function(st)
            assertNil(W.validateFont())
            local ok, fs = pcall(W.fontString, UIParent, "GameFontNormalSmall", "x", WC.WHITE)
            assertTrue(ok, tostring(fs))
            assertEquals("GameFontNormalSmall", st.obj[#st.obj].name,
                "the string's creation template, so per-role sizing survives")
        end)
    end)
end)

test("General BarFont picker preview: a raising path is refused, anything else is drawn in",
function()
    local D = FX.Cooldown.Display
    D:Init()
    O:Open("General")
    local page = O.pagesBuilt["General"]
    local sel
    for _, wd in ipairs(page.sections[3].widgets) do
        if wd.spec.key == "BarFont" then sel = wd end
    end
    assertNotNil(sel, "the Appearance section carries the Bar Font picker")
    local bad = "Interface\\AddOns\\Forte_Core\\Fonts\\FXTEST-RAISES.ttf"
    local fine = "Interface\\AddOns\\Forte_Core\\Fonts\\FXTEST-PENDING.ttf"
    withFontStub("raise", function(st)
        st.raiseFor = function(p) return p == bad end
        S:Set("General", "BarFont", bad)
        sel.refresh()
        local sawTemplate = false
        for _, call in ipairs(st.obj) do
            if call.fs == sel.caption and call.name == sel.caption._fxTemplate then
                sawTemplate = true
            end
        end
        assertTrue(sawTemplate, "the raising path leaves the caption on its template")
        S:Set("General", "BarFont", fine)
        sel.refresh()
        assertEquals(fine, sel.caption._stubFont,
            "a path that did not raise is drawn in, though SetFont says false")
    end)
    S:Reset("General", "BarFont")
    sel.refresh()                -- the caption follows the store again
    O:Close()
end)

-- ------------------------------------------------- measuring while pending --

test("a 0 label width is pending: the row uses the ratio column, not a collapsed one",
function()
    local spec = { label = "A reasonably long option label", width = 500 }
    local measured = W.BTN(UIParent, { label = spec.label, width = 500 })
    local mw = measured.label:GetUnboundedStringWidth()
    assertTrue(mw > 0, "the sim measures the label")
    assertTrue(math.abs(measured.labelWidth - (mw + 2)) < 0.01,
        "a measurable label gets its measured column")
    withFontStub("pending", function(st)
        st.zeroWidth = true
        local w = W.BTN(UIParent, { label = spec.label, width = 500 })
        local want = 500 * WC.LABEL_COL_RATIO
        assertTrue(math.abs(w.labelWidth - want) < 0.01,
            "pending: the ratio column, got " .. tostring(w.labelWidth))
        assertTrue(w.labelWidth > 2, "never collapsed to the 0 + 2 of a failed measure")
    end)
end)

test("a 0 tab caption width uses the fallback; the tab row is laid out again when the file renders",
function()
    O:Open("General")
    local refreshed = 0
    local realRefresh = O.RefreshProfileTabs
    O.RefreshProfileTabs = function(self, ...)
        refreshed = refreshed + 1
        return realRefresh(self, ...)
    end
    local ok, err = pcall(function()
        withFontStub("pending", function(st)
            st.zeroWidth = true
            local tab = O:MakeTab(O.window, "Profiles", false, function() end, "tip")
            assertEquals(math.max(O.C.TAB_MIN_W, 60 + O.C.TAB_TEXT_PAD), tab:GetWidth(),
                "the fallback width, not 0 + padding")
            assertEquals(1, #st.tickers, "one wait for the file")
            -- A second pending tab does not stack a second registration.
            O:MakeTab(O.window, "Other", false, function() end, "tip")
            assertEquals(1, #st.tickers)
            assertEquals(0, refreshed)
            st.zeroWidth = false
            st.mode = "loaded"
            st.tickers[1].fn()
            assertEquals(1, refreshed, "the late measure re-laid the tabs once")
        end)
    end)
    O.RefreshProfileTabs = realRefresh
    O:Close()
    assertTrue(ok, tostring(err))
end)
