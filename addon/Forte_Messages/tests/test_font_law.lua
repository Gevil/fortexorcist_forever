-- addon/Forte_Messages/tests/test_font_law.lua
-- PLAN §11.12 on the message banner (UI/Banner.lua): a font file the client
-- has not rendered yet answers SetFont false / GetFont nil and is still
-- perfectly usable; only a RAISE means unusable.
--   * pending file -> the banner text keeps URW Gothic (FX.CLASSIC_FONT) at 16
--     OUTLINE, no template;
--   * SetFont raising -> GameFontHighlightLarge through SetFontObject, no error
--     escapes.
--
-- The stub patches the sim's one shared FontString method table (see
-- Forte_Core/tests/test_font_law.lua); Banner:Init only builds once, so the
-- test frees the global frame name, rebuilds under the stub and hands the live
-- frame back.
--
-- FAILS-ON-THE-OLD-CODE: Banner:Init read `fs:GetFont()` back after SetFont
-- (nil on the pending stub -> okFont false -> SetFontTemplate). The sim has no
-- SetFontTemplate, so the stub also spies it: the old fallback is counted in
-- st.obj exactly like the new SetFontObject one.

local FX = ForteXorcist
local Banner = FX.Messages.Banner
local SHIPPED = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"

local function withFontStub(mode, body)
    local fs0 = UIParent:CreateFontString(nil, "OVERLAY")
    local idx = getmetatable(fs0).__index
    local real = { SetFont = idx.SetFont, GetFont = idx.GetFont,
        SetFontObject = idx.SetFontObject, SetFontTemplate = idx.SetFontTemplate }
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
    local function template(self, name)
        st.obj[#st.obj + 1] = { fs = self, name = name }
        self._stubFont = nil
    end
    idx.SetFontObject = template
    idx.SetFontTemplate = template
    local ok, err = pcall(body, st)
    idx.SetFont, idx.GetFont, idx.SetFontObject, idx.SetFontTemplate =
        real.SetFont, real.GetFont, real.SetFontObject, real.SetFontTemplate
    if not ok then error(err, 0) end
end

--- Rebuild the banner under the stub, then put the live frame back.
local function rebuilt(body)
    local liveFrame, liveText, liveActive = Banner.frame, Banner.text, Banner.active
    local liveGlobal = _G.FXMessagesBanner
    assertNotNil(liveFrame, "the module enabled the banner")
    Banner.frame, _G.FXMessagesBanner = nil, nil
    local ok, err = pcall(function()
        Banner:Init()
        assertNotNil(Banner.text, "the banner rebuilt")
        body(Banner.text)
    end)
    if Banner.frame and Banner.frame ~= liveFrame then Banner.frame:Hide() end
    Banner.frame, Banner.text, Banner.active = liveFrame, liveText, liveActive
    _G.FXMessagesBanner = liveGlobal
    assertTrue(ok, tostring(err))
end

test("pending file: the banner text keeps the shipped font at 16 OUTLINE, no template",
function()
    assertEquals(SHIPPED, FX.CLASSIC_FONT)
    withFontStub("pending", function(st)
        rebuilt(function(text)
            assertEquals(0, #st.obj,
                "SetFont false / GetFont nil must not send the text to a template")
            assertEquals(SHIPPED, text._stubFont)
            local call = st.set[#st.set]
            assertEquals(SHIPPED, call.path)
            assertEquals(16, call.size)
            assertEquals("OUTLINE", call.flags)
        end)
    end)
end)

test("SetFont raising: the banner text takes GameFontHighlightLarge, no error escapes",
function()
    withFontStub("raise", function(st)
        rebuilt(function(text)
            assertNil(text._stubFont)
            assertEquals("GameFontHighlightLarge", st.obj[#st.obj].name)
        end)
    end)
end)
