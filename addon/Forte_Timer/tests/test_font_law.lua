-- addon/Forte_Timer/tests/test_font_law.lua
-- PLAN §11.12 on the Spell Timer (Forte_Timer/UI/Rows.lua): a font file the
-- client has not rendered yet reads SetFont false / GetFont nil / width 0 and
-- is still perfectly usable; only a RAISE means unusable.
--   * pending file -> D:ValidateFonts keeps the shipped path and every pooled
--     string (name, time, the hidden measuring dummy, group label, stack tag)
--     is applied in it, nothing goes to the template;
--   * SetFont raising -> fontFile nil, the template through SetFontObject, no
--     error escapes;
--   * the time column is sized off the hidden dummy's width: a 0 width for real
--     text is PENDING -- the row keeps its last good width (or an estimate),
--     the 0 is never cached, and once Compat.WhenFontLoaded fires, the Timer
--     drops its _timeKey/_gBarW caches and measures again.
--
-- The stub patches the sim's one shared FontString method table (see
-- Forte_Core/tests/test_font_law.lua). The headless sim never fires a
-- C_Timer ticker, so the ticker is captured and driven by hand.
--
-- FAILS-ON-THE-OLD-CODE: the old validateFontFile compared `probe:GetFont()`
-- with the path (nil on the pending stub -> fontFile nil -> the template), and
-- the old Update used `dummy:GetWidth()` raw (0 -> a 0-wide time column and a
-- full-width name, never revisited).

local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Casts = FX.Timer.Casts
local D = FX.Timer.Display

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
    local realTicker = C_Timer.NewTicker
    C_Timer.NewTicker = function(interval, fn, iterations)
        local t = { interval = interval, fn = fn, iterations = iterations }
        function t:Cancel() self.cancelled = true end
        st.tickers[#st.tickers + 1] = t
        return t
    end
    local ok, err = pcall(body, st)
    -- Let every armed wait resolve, so no waiter outlives the test.
    st.mode = "loaded"
    for _, t in ipairs(st.tickers) do
        if not t.cancelled then pcall(t.fn) end
    end
    C_Timer.NewTicker = realTicker
    idx.SetFont, idx.GetFont, idx.SetFontObject =
        real.SetFont, real.GetFont, real.SetFontObject
    if not ok then error(err, 0) end
end

local function ensureEnabled()
    if not M.options then M:OnEnable() end
    assertNotNil(D.anchor, "the display is built")
    local o = M.options
    o.enable, o.hide = true, false
    if not D.anchor:IsShown() then D.anchor:Show() end
    return o
end

local savedRowsOptions, savedCastsOptions
local function bindOptions(o)
    if savedRowsOptions == nil then
        savedRowsOptions, savedCastsOptions = Rows.options, Casts.options
    end
    Rows.options, Casts.options = o, o
end

local function cleanUp()
    Rows:Clear()
    Casts.now = nil
    if savedRowsOptions ~= nil then
        Rows.options, Casts.options = savedRowsOptions, savedCastsOptions
    end
    D:RenderIdle()
end

local function withFixedClock(base, body)
    local saved = _G.GetTime
    _G.GetTime = function() return base end
    Casts.now = function() return base end
    local ok, err = pcall(body)
    _G.GetTime = saved
    assertEquals(ok and "ok" or tostring(err), "ok")
end

local function slotOf(row)
    for s = 1, #D.rows do
        if D.rows[s]._row == row then return D.rows[s] end
    end
end

-- ------------------------------------------------------------- the file law --

test("pending file: ValidateFonts keeps the shipped path; new pooled strings are applied in it",
function()
    ensureEnabled()
    local file = D.skin.Font[1]
    assertEquals(FX.CLASSIC_FONT, file, "the skin reads the one shared constant")
    withFontStub("pending", function(st)
        D:ValidateFonts()
        assertEquals(file, D.fontFile, "the validator must not veto a pending file")
        assertEquals(file, D.stacksFontFile)
        local ri, gi = #D.rows + 1, #D.groups + 1
        local row = D:AcquireRow(ri)
        local group = D:AcquireGroup(gi)
        for _, fs in ipairs({ row.nameFS, row.timeFS, row.dummy, row.tag, group.label }) do
            assertEquals(file, fs._stubFont, "applied in the shipped file")
        end
        local tagCall
        for _, call in ipairs(st.set) do
            if call.fs == row.tag then tagCall = call end
        end
        assertNotNil(tagCall, "the stack tag asked for the file")
        assertEquals("OUTLINE", tagCall.flags, "the stack tag keeps its OUTLINE flag")
        assertEquals(0, #st.obj, "no string went to the template")
        -- Leave the pool as it was.
        row.bar:Hide()
        D.rows[ri] = nil
        group.frame:Hide()
        group.label:Hide()
        D.groups[gi] = nil
    end)
    D:ValidateFonts()
end)

test("SetFont raising: fontFile nil, template through SetFontObject, no error escapes",
function()
    ensureEnabled()
    withFontStub("raise", function(st)
        local ok, err = pcall(D.ValidateFonts, D)
        assertTrue(ok, tostring(err))
        assertNil(D.fontFile)
        assertNil(D.stacksFontFile)
        local ri = #D.rows + 1
        local ok2, row = pcall(D.AcquireRow, D, ri)
        assertTrue(ok2, tostring(row))
        assertTrue(#st.obj >= 4, "name/time/dummy/tag took the template")
        for _, call in ipairs(st.obj) do
            assertEquals("GameFontHighlightSmall", call.name)
        end
        row.bar:Hide()
        D.rows[ri] = nil
    end)
    D:ValidateFonts()
    assertEquals(FX.CLASSIC_FONT, D.fontFile, "the shipped file is back once nothing raises")
end)

-- ---------------------------------------------------- measuring while pending --

test("a 0 dummy width for real text is pending: no collapse, no cache; the late hook re-measures",
function()
    local o = ensureEnabled()
    bindOptions(o)
    local base = GetTime()
    withFixedClock(base, function()
        Rows:Clear()
        local row = Rows:InsertFromCast("Serpent Sting", "Dummy-1", 12,
            base - 0.75, base - 0.75, 1, "TargetDebuff")
        assertNotNil(row)
        M:Draw()
        local r = slotOf(row)
        assertNotNil(r, "the row drew")
        local good = r.dummy:GetWidth()
        assertTrue(good > 0, "the sim measures the dummy text")
        assertEquals(good, r._goodW, "a real measure is remembered")

        withFontStub("pending", function(st)
            D:ValidateFonts()                       -- arms the late measure
            assertEquals(1, #st.tickers, "one ticker waits for the file")
            -- The client before the first render: the dummy reads 0.
            r.dummy.GetWidth = function() return 0 end
            M:Draw()
            assertEquals(good, r._goodW, "the 0 is not cached over the good width")
            assertEquals(good, r._twWidth, "the column keeps the previous good width")
            assertTrue(r.timeFS:GetWidth() > 0, "the time column did not collapse")

            -- A row with NO earlier measure: an estimate, never 0, never cached.
            r._goodW, r._twWidth, r._nwWidth = nil, nil, nil
            M:Draw()
            assertNil(r._goodW, "an estimate is not a measure")
            assertTrue(r._twWidth > 0, "estimated from the text, not 0")

            -- The file renders: the hook drops the caches...
            r.dummy.GetWidth = nil                   -- the real method again
            st.mode = "loaded"
            r._gBarW = 123
            st.tickers[1].fn()
            assertTrue(st.tickers[1].cancelled, "the wait is over")
            assertNil(r._timeKey, "_timeKey dropped")
            assertNil(r._gBarW, "_gBarW dropped")
            assertNil(r._goodW, "the stale estimate state is gone")
            -- ...and the next pass measures for real.
            M:Draw()
            assertEquals(good, r._goodW)
            assertEquals(good, r._twWidth)
            assertNotNil(r._timeKey, "the text was set again")
        end)
        Rows:Clear()
    end)
    cleanUp()
end)
