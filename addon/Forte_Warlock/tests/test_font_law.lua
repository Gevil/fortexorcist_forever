-- addon/Forte_Warlock/tests/test_font_law.lua
-- PLAN §11.12 on the Warlock plates (UI/Frame.lua, UI/Shards.lua): a font file
-- the client has not rendered yet answers SetFont false / GetFont nil / width 0
-- and is still perfectly usable; only a RAISE means unusable.
--   * pending file -> the plates' strings (Frame:_NewFont/_NewRowFont, the
--     Shards info label) keep the shipped file, no template;
--   * SetFont raising -> the template through SetFontObject, no error escapes
--     (the old code called fs:SetFont bare, so a raise escaped the build);
--   * the Shards info label's fit: a 0 draw width for real text is PENDING --
--     the previous fitted size is kept and not overwritten, and the fit is
--     re-run when Compat.WhenFontLoaded fires.
--
-- The stub patches the sim's one shared FontString method table (see
-- Forte_Core/tests/test_font_law.lua); the headless sim never fires a
-- C_Timer ticker, so the ticker is captured and driven by hand.
--
-- FAILS-ON-THE-OLD-CODE: Frame:_NewFont called `fs:SetFont` unprotected (a raise
-- escaped), and InfoFitSize turned a 0 width into the skin size and
-- ApplyInfoFont overwrote the fitted size with it, with no re-fit later.

local FX = ForteXorcist
local UI = FX.Warlock.UI
local Shards = FX.Warlock.Shards
local SHIPPED = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"

local function withFontStub(mode, body)
    local fs0 = UIParent:CreateFontString(nil, "OVERLAY")
    local idx = getmetatable(fs0).__index
    local real = { SetFont = idx.SetFont, GetFont = idx.GetFont,
        SetFontObject = idx.SetFontObject }
    local st = { mode = mode, set = {}, obj = {}, tickers = {},
        raiseFor = function() return true end }
    idx.SetFont = function(self, path, size, flags)
        st.set[#st.set + 1] = { fs = self, path = path, size = size, flags = flags }
        if st.mode == "raise" and st.raiseFor(path) then
            error("FontString:SetFont(): invalid font asset (" .. tostring(path)
                .. "): file not found", 0)
        end
        self._stubFont = path
        self._stubSize = size
        return st.mode == "loaded"
    end
    idx.GetFont = function(self)
        -- A string whose FILE went through the stub: nil while pending, the
        -- path once loaded. A template-font string (the Shards measuring
        -- probe) reads its template, exactly as on the client.
        if self._stubFont then
            if st.mode == "loaded" then return self._stubFont, self._stubSize end
            return nil
        end
        return real.GetFont(self)
    end
    idx.SetFontObject = function(self, name)
        st.obj[#st.obj + 1] = { fs = self, name = name }
        self._stubFont = nil
    end
    local realTicker = C_Timer.NewTicker
    C_Timer.NewTicker = function(interval, fn, iterations)
        local t = { interval = interval, fn = fn, iterations = iterations }
        function t:Cancel() self.cancelled = true end
        st.tickers[#st.tickers + 1] = t
        return t
    end
    local ok, err = pcall(body, st)
    st.mode = "loaded"
    for _, t in ipairs(st.tickers) do
        if not t.cancelled then pcall(t.fn) end
    end
    C_Timer.NewTicker = realTicker
    idx.SetFont, idx.GetFont, idx.SetFontObject =
        real.SetFont, real.GetFont, real.SetFontObject
    if not ok then error(err, 0) end
end

local function dropString(frame, fs)
    fs:Hide()
    if frame.fonts then frame.fonts[fs] = nil end
end

test("pending file: the plate strings keep the shipped file, no template", function()
    UI:_InitViews()
    assertEquals(SHIPPED, FX.CLASSIC_FONT)
    assertEquals(SHIPPED, Shards.state.fontFile)
    withFontStub("pending", function(st)
        local info = Shards:_NewInfo()
        local row = Shards:_NewRowFont("CENTER", Shards.row)
        assertEquals(SHIPPED, info._stubFont)
        assertEquals(SHIPPED, row._stubFont)
        assertEquals(0, #st.obj, "no string went to the template")
        dropString(Shards, info)
        dropString(Shards, row)
    end)
end)

test("SetFont raising: the plate strings take the template, no error escapes", function()
    UI:_InitViews()
    withFontStub("raise", function(st)
        local ok, info = pcall(Shards._NewInfo, Shards)
        assertTrue(ok, "the build must not raise: " .. tostring(info))
        local ok2, row = pcall(Shards._NewRowFont, Shards, "CENTER", Shards.row)
        assertTrue(ok2, tostring(row))
        assertTrue(#st.obj >= 2)
        for _, call in ipairs(st.obj) do
            assertEquals("GameFontHighlightSmall", call.name)
        end
        dropString(Shards, info)
        dropString(Shards, row)
    end)
end)

test("Shards info fit: a 0 draw width is pending -- keep the previous size, re-fit when the file renders",
function()
    UI:_InitViews()
    local fs = Shards.infoFS
    assertNotNil(fs)
    local text = "9 total"
    fs:SetText(text)
    local probe = Shards:_InfoProbe()
    assertNotNil(probe)
    local savedSize = Shards._infoSize
    -- A real measure first: the size is remembered.
    Shards:ApplyInfoFont()
    local fitted = Shards._infoSize
    assertTrue(type(fitted) == "number" and fitted >= 8 and fitted <= Shards.skin.TextSize)

    -- No earlier size: the skin's size, flagged pending.
    probe.GetStringWidth = function() return 0 end
    Shards._infoSize = nil
    local size, pending = Shards:InfoFitSize(text)
    assertEquals(Shards.skin.TextSize, size)
    assertTrue(pending)
    -- An empty label is not pending.
    local _, pendingEmpty = Shards:InfoFitSize("")
    assertFalse(pendingEmpty)

    withFontStub("pending", function(st)
        Shards._infoSize = 5
        Shards:ApplyInfoFont()
        assertEquals(5, fs._stubSize, "the previous fitted size is kept")
        assertEquals(5, Shards._infoSize, "and the 0 is never remembered as a size")
        assertEquals(SHIPPED, fs._stubFont, "still the shipped file")
        assertEquals(1, #st.tickers, "one wait for the file")
        -- The file renders; the probe measures for real again.
        probe.GetStringWidth = nil
        st.mode = "loaded"
        st.tickers[1].fn()
        assertTrue(st.tickers[1].cancelled)
        assertTrue(Shards._infoSize >= 8 and Shards._infoSize ~= 5,
            "the fit was re-run: " .. tostring(Shards._infoSize))
        assertEquals(Shards._infoSize, fs._stubSize)
    end)
    probe.GetStringWidth = nil
    Shards._infoSize = savedSize
    Shards:ApplyInfoFont()
end)
