-- addon/Forte_Hunter/tests/test_font_law.lua
-- PLAN §11.12 on the Hunter displays (UI/Swing.lua, UI/Melee.lua, UI/Range.lua):
-- a font file the client has not rendered yet answers SetFont false / GetFont
-- nil and is still perfectly usable; only a RAISE means unusable.
--   * pending file -> every display keeps the shipped font path, no template;
--   * SetFont raising -> fontFile nil, the template through SetFontObject, no
--     error escapes;
--   * the General BarFont option (Swing:SetFont): a raising path is rejected, a
--     non-raising one applied.
--
-- The stub patches the sim's one shared FontString method table (see
-- Forte_Core/tests/test_font_law.lua). Melee and Range only validate in Init,
-- so the test rebuilds their frame in place (the global frame name freed, the
-- live fields handed back afterwards).
--
-- FAILS-ON-THE-OLD-CODE: each display's validateFontFile compared
-- `probe:GetFont()` with the path (nil on the pending stub -> fontFile nil ->
-- the template), and Swing's applyFont read `fs:GetFont() == D.fontFile` the
-- same way.

local FX = ForteXorcist
local Swing = FX.Hunter.Swing
local Melee = FX.Hunter.Melee
local RangeLight = FX.Hunter.RangeLight
local ST = FX.Settings
local SHIPPED = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"

local function withFontStub(mode, body)
    local fs0 = UIParent:CreateFontString(nil, "OVERLAY")
    local idx = getmetatable(fs0).__index
    local real = { SetFont = idx.SetFont, GetFont = idx.GetFont,
        SetFontObject = idx.SetFontObject }
    local st = { mode = mode, set = {}, obj = {},
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
    local ok, err = pcall(body, st)
    idx.SetFont, idx.GetFont, idx.SetFontObject =
        real.SetFont, real.GetFont, real.SetFontObject
    if not ok then error(err, 0) end
end

--- Rebuild a display's frame under the stub: free the global name, drop the
--- live fields, run Init, hand back what Init built, restore the live fields.
local function rebuilt(display, globalName, fields, body)
    local live = {}
    for _, k in ipairs(fields) do live[k] = display[k] end
    local liveFrame = _G[globalName]
    _G[globalName] = nil
    display.anchor = nil
    local ok, err = pcall(function()
        display:Init()
        assertNotNil(display.anchor, "the display rebuilt")
        body(display.text, display)
    end)
    if display.anchor and display.anchor ~= live.anchor then display.anchor:Hide() end
    for _, k in ipairs(fields) do display[k] = live[k] end
    _G[globalName] = liveFrame
    assertTrue(ok, tostring(err))
end

-- ------------------------------------------------------------------- Swing --

test("Swing: a pending file keeps the shipped path, a raise falls back to the template",
function()
    Swing:Init()
    withFontStub("pending", function(st)
        Swing:SetFont(SHIPPED)
        assertEquals(SHIPPED, Swing.fontFile, "the validator must not veto a pending file")
        assertEquals(SHIPPED, Swing.text._stubFont)
        assertEquals(0, #st.obj, "no template while the file is merely pending")
    end)
    withFontStub("raise", function(st)
        local ok, err = pcall(Swing.SetFont, Swing, SHIPPED)
        assertTrue(ok, "no error escapes: " .. tostring(err))
        assertNil(Swing.fontFile)
        assertEquals("GameFontHighlightSmall", st.obj[#st.obj].name)
    end)
    Swing:SetFont(SHIPPED)
    assertEquals(SHIPPED, Swing.fontFile, "restored")
end)

test("Swing: the General BarFont option rejects a raising path, applies a non-raising one",
function()
    Swing:Init()
    local bad = "Interface\\AddOns\\Forte_Core\\Fonts\\FXTEST-RAISES.ttf"
    local fine = "Interface\\AddOns\\Forte_Core\\Fonts\\FXTEST-PENDING.ttf"
    withFontStub("raise", function(st)
        st.raiseFor = function(p) return p == bad end
        ST:Set("General", "BarFont", bad)
        assertNil(Swing.fontFile, "the raising path is rejected")
        assertNil(Swing.text._stubFont)
        ST:Set("General", "BarFont", fine)
        assertEquals(fine, Swing.fontFile, "anything that does not raise is applied")
        assertEquals(fine, Swing.text._stubFont)
    end)
    ST:Reset("General", "BarFont")
    assertEquals(SHIPPED, Swing.fontFile, "the default is back")
end)

-- ------------------------------------------------------------- Melee / Range --

test("Melee: a pending file keeps the shipped path; a raise takes the template", function()
    assertNotNil(Melee, "FX.Hunter melee rail display")
    local savedEnabled = Melee.state.enabled
    Melee.state.enabled = true
    local fields = { "anchor", "fill", "text", "fontFile", "_shown", "_fillW",
        "_timeKey", "_w", "_color", "_colorKey" }
    local ok, err = pcall(function()
        withFontStub("pending", function(st)
            rebuilt(Melee, "ForteXorcistHunterMeleeAnchor", fields, function(text, d)
                assertEquals(SHIPPED, d.fontFile)
                assertEquals(SHIPPED, text._stubFont)
                assertEquals(0, #st.obj)
            end)
        end)
        withFontStub("raise", function(st)
            rebuilt(Melee, "ForteXorcistHunterMeleeAnchor", fields, function(text, d)
                assertNil(d.fontFile)
                assertNil(text._stubFont)
                assertEquals("GameFontHighlightSmall", st.obj[#st.obj].name)
            end)
        end)
    end)
    Melee.state.enabled = savedEnabled
    assertTrue(ok, tostring(err))
end)

test("Range light: a pending file keeps the shipped path; a raise takes the template",
function()
    assertNotNil(RangeLight)
    local fields = { "anchor", "text", "fontFile", "_band", "_text", "_shown" }
    withFontStub("pending", function(st)
        rebuilt(RangeLight, "ForteXorcistHunterRangeAnchor", fields, function(text, d)
            assertEquals(SHIPPED, d.fontFile)
            assertEquals(SHIPPED, text._stubFont)
            assertEquals(0, #st.obj)
        end)
    end)
    withFontStub("raise", function(st)
        rebuilt(RangeLight, "ForteXorcistHunterRangeAnchor", fields, function(text, d)
            assertNil(d.fontFile)
            assertNil(text._stubFont)
            assertEquals("GameFontHighlightSmall", st.obj[#st.obj].name)
        end)
    end)
end)
