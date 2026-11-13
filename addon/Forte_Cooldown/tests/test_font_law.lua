-- addon/Forte_Cooldown/tests/test_font_law.lua
-- PLAN §11.12 on the Cooldown timeline (Forte_Cooldown/UI/Timeline.lua): the
-- client loads a font file lazily, so right after SetFont the file reads
-- `false` / GetFont nil although it is perfectly usable; only a RAISE means
-- unusable. Pinned here through the Display's real paths (SetBarFont, the
-- General BarFont setting, Update building the slot strings):
--   * pending file (SetFont false, GetFont nil, no raise) -> every string KEEPS
--     the shipped font path, no template anywhere;
--   * SetFont raising -> fontFile nil, every string on GameFontHighlightSmall
--     through SetFontObject, nothing escapes;
--   * BarFont: a raising typed path is rejected, a non-raising one applied.
--
-- The stub patches the sim's one shared FontString method table (see
-- Forte_Core/tests/test_font_law.lua).
--
-- FAILS-ON-THE-OLD-CODE: the old applyFont ran
--   `ok = pcall(fs.SetFont, ...); if ok then ok = (fs:GetFont()) == D.fontFile end`
-- and the old validateFontFile compared `probe:GetFont()` with the path -- both
-- read nil on the pending stub, so fontFile came out nil and every string took
-- the template (the pending test's `assertEquals(SHIPPED, Display.fontFile)`
-- and `_stubFont` checks fail on it).

local FX = ForteXorcist
local Display = FX.Cooldown.Display
local Settings = FX.Settings
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

local function allStrings()
    local out = {}
    for i = 1, #(Display.tagFS or {}) do out[#out + 1] = Display.tagFS[i] end
    for i = 1, #(Display.slots or {}) do
        local slot = Display.slots[i]
        if slot.timeFS then out[#out + 1] = slot.timeFS end
        if slot.chargeFS then out[#out + 1] = slot.chargeFS end
    end
    return out
end

--- Back to the real shipped state after a stubbed leg (the strings' dirty keys
--- were written under the stub).
local function restoreShipped()
    for _, fs in ipairs(allStrings()) do fs._font = nil end
    Display:SetBarFont(SHIPPED)
end

local function seedSlot(now)
    Display:Update({ { name = "FontLaw", start = 0, duration = 60,
        endTime = now + 45 } }, now)
end

test("pending file: SetFont false / GetFont nil keeps the shipped font on every string",
function()
    Display:Init()
    local now = 34000
    seedSlot(now)
    local strings = allStrings()
    assertTrue(#strings >= 3, "tag + time + charge strings exist")
    withFontStub("pending", function(st)
        for _, fs in ipairs(strings) do fs._font = nil end
        Display:SetBarFont(SHIPPED)
        assertEquals(SHIPPED, Display.fontFile,
            "the validator must not veto a file that has not rendered yet")
        for i, fs in ipairs(strings) do
            assertEquals(SHIPPED, fs._stubFont, "string " .. i .. " keeps the shipped path")
        end
        assertEquals(0, #st.obj, "no string was sent to the template")
    end)
    restoreShipped()
    Display:Update({}, now + 1)
end)

test("SetFont raising: fontFile nil, every string on the template, no error escapes",
function()
    Display:Init()
    local now = 34100
    seedSlot(now)
    local strings = allStrings()
    withFontStub("raise", function(st)
        for _, fs in ipairs(strings) do fs._font = nil end
        local ok, err = pcall(Display.SetBarFont, Display, SHIPPED)
        assertTrue(ok, "no error escapes: " .. tostring(err))
        assertNil(Display.fontFile, "a raised file is unusable")
        assertEquals(#strings, #st.obj, "every string took the template")
        for _, call in ipairs(st.obj) do
            assertEquals("GameFontHighlightSmall", call.name)
        end
        -- The template state is cached (the n6 sentinel): a repeat costs nothing.
        local before = #st.obj
        Display:SetBarFont(SHIPPED)
        assertEquals(before, #st.obj)
    end)
    restoreShipped()
    Display:Update({}, now + 1)
end)

test("General BarFont: a raising typed path is rejected, a non-raising one applied",
function()
    Display:Init()
    local tag = Display.tagFS[1]
    local bad = "Interface\\AddOns\\Forte_Core\\Fonts\\FXTEST-RAISES.ttf"
    local fine = "Interface\\AddOns\\Forte_Core\\Fonts\\FXTEST-PENDING.ttf"
    withFontStub("raise", function(st)
        st.raiseFor = function(p) return p == bad end
        Settings:Set("General", "BarFont", bad)
        assertNil(Display.fontFile, "the raising path is rejected")
        assertNil(tag._stubFont, "the tag rides the template")
        local sawTemplate = false
        for _, call in ipairs(st.obj) do
            if call.fs == tag and call.name == "GameFontHighlightSmall" then
                sawTemplate = true
            end
        end
        assertTrue(sawTemplate, "the rejection is the existing template feedback")
        -- A path that does not raise is applied, even though SetFont says false.
        Settings:Set("General", "BarFont", fine)
        assertEquals(fine, Display.fontFile)
        assertEquals(fine, tag._stubFont)
    end)
    Settings:Reset("General", "BarFont")
    assertEquals(SHIPPED, Display.fontFile, "the default is back")
    restoreShipped()
end)
