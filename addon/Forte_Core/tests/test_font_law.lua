-- addon/Forte_Core/tests/test_font_law.lua
-- PLAN §11.12 (the font bug, measured live 2026-11-13): the client loads a font
-- FILE lazily, on its first render. Until then SetFont RETURNS FALSE, GetFont()
-- is nil and GetStringWidth() is 0 -- and the file is perfectly usable. Only a
-- RAISE means unusable. This file pins the shared law in FX.Compat
-- (FontUsable / FontLoaded / ApplyFont / WarmFont / WhenFontLoaded /
-- TextWidthPending) and that FX.CLASSIC_FONT lives in one place.
--
-- THE STUB. The sim shares ONE FontString method table between every
-- fontstring (measured: `getmetatable(fs).__index`, one SetFont for all), so
-- patching it for the length of a test makes every string -- the probe, the
-- warm string, a display's own -- behave like the client before the file has
-- rendered: SetFont returns false, GetFont nil, no raise. Mode "raise" makes
-- SetFont raise the client's own "file not found" error instead.
--
-- FAILS-ON-THE-OLD-CODE. The first test runs the OLD round-trip expression
-- verbatim (`okSet and probe:GetFont()` compared to the path) against the
-- pending stub: it answers nil, i.e. "reject the shipped font" -- the very
-- verdict that sent every display to the template for the whole session. The
-- new FontUsable answers true on the same stub.

local FX = ForteXorcist
local C = FX.Compat
local SHIPPED = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"

local seq = 0
local function freshPath(tag)
    seq = seq + 1
    return "Interface\\AddOns\\Forte_Core\\Fonts\\FXTEST-" .. (tag or "f") .. seq .. ".ttf"
end

local function fontClass()
    local fs = UIParent:CreateFontString(nil, "OVERLAY")
    return getmetatable(fs).__index
end

--- Run `body(st)` with the font stub installed; always restores. st.mode is
--- "pending" | "loaded" | "raise" and may be flipped mid-test; st.raiseFor(path)
--- narrows "raise" to some paths; st.set / st.obj log every SetFont /
--- SetFontObject call.
local function withFontStub(mode, body)
    local idx = fontClass()
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

--- C_Timer.NewTicker capture: the headless sim never fires a ticker, so the
--- test drives the callback by hand (the test_testmode.lua / test_zz_combat
--- convention). Returns the capture table and the restore function.
local function captureTickers()
    local cap = { made = {} }
    local real = C_Timer.NewTicker
    C_Timer.NewTicker = function(interval, fn, iterations)
        local t = { interval = interval, fn = fn, iterations = iterations,
            cancelled = false }
        function t:Cancel() self.cancelled = true end
        cap.made[#cap.made + 1] = t
        return t
    end
    return cap, function() C_Timer.NewTicker = real end
end

-- ---------------------------------------------------------------- the old law --

test("the stub reproduces the bug: the OLD round trip rejects the shipped font, FontUsable does not",
function()
    local function oldRoundTrip(path)           -- the pre-§11.12 validator, verbatim
        local probe = UIParent:CreateFontString(nil, "OVERLAY")
        local okSet = pcall(probe.SetFont, probe, path, 11)
        local got = okSet and probe:GetFont()
        if type(got) == "string" and got:lower() == path:lower() then
            return path
        end
        return nil
    end
    withFontStub("pending", function()
        assertNil(oldRoundTrip(SHIPPED),
            "the old law reads the pending file as unusable (the bug)")
        assertTrue(C.FontUsable(SHIPPED), "PLAN §11.12: a pending file is usable")
    end)
end)

test("FX.CLASSIC_FONT is the one shipped-font constant, defined in Forte_Core", function()
    assertEquals(SHIPPED, FX.CLASSIC_FONT)
end)

-- ------------------------------------------------------------------ FontUsable --

test("FontUsable: true unless SetFont RAISED; never reads the boolean or GetFont", function()
    withFontStub("pending", function(st)
        assertTrue(C.FontUsable(SHIPPED), "SetFont false + GetFont nil is still usable")
        assertTrue(#st.set >= 1, "the probe really asked the client")
    end)
    withFontStub("loaded", function()
        assertTrue(C.FontUsable(SHIPPED))
    end)
    withFontStub("raise", function(st)
        local bad = freshPath("missing")
        st.raiseFor = function(p) return p == bad end
        assertFalse(C.FontUsable(bad), "a raise is the one 'unusable'")
        assertTrue(C.FontUsable(SHIPPED), "other paths are unaffected")
    end)
    assertFalse(C.FontUsable(nil))
    assertFalse(C.FontUsable(""))
    assertFalse(C.FontUsable(42))
end)

test("FontLoaded: the probe's SetFont returned true (informational)", function()
    withFontStub("pending", function() assertFalse(C.FontLoaded(SHIPPED)) end)
    withFontStub("loaded", function() assertTrue(C.FontLoaded(SHIPPED)) end)
    withFontStub("raise", function() assertFalse(C.FontLoaded(SHIPPED)) end)
    assertFalse(C.FontLoaded(nil))
end)

-- ------------------------------------------------------------------- ApplyFont --

test("ApplyFont: a pending file stays applied; the template only on a raise", function()
    withFontStub("pending", function(st)
        local fs = UIParent:CreateFontString(nil, "OVERLAY")
        assertTrue(C.ApplyFont(fs, SHIPPED, 11, "OUTLINE"), "false/nil is not a veto")
        assertEquals(SHIPPED, fs._stubFont)
        assertEquals(0, #st.obj, "no template while the file is merely pending")
        local last = st.set[#st.set]
        assertEquals(11, last.size)
        assertEquals("OUTLINE", last.flags)
    end)
    withFontStub("raise", function(st)
        local fs = UIParent:CreateFontString(nil, "OVERLAY")
        local ok, res = pcall(C.ApplyFont, fs, freshPath("raise"), 11)
        assertTrue(ok, "no error escapes a raising SetFont")
        assertFalse(res, "unusable -> false")
        assertEquals(1, #st.obj)
        assertEquals("GameFontHighlightSmall", st.obj[1].name, "the default template")
        local fs2 = UIParent:CreateFontString(nil, "OVERLAY")
        C.ApplyFont(fs2, freshPath("raise"), 11, nil, "GameFontHighlightLarge")
        assertEquals("GameFontHighlightLarge", st.obj[2].name, "the caller's template")
        local fs3 = UIParent:CreateFontString(nil, "OVERLAY")
        assertFalse(C.ApplyFont(fs3, nil, 11), "no path = the template branch")
        assertEquals(3, #st.obj)
    end)
    -- SetFontObject itself raising must not escape either.
    local idx = fontClass()
    local realObj = idx.SetFontObject
    idx.SetFontObject = function() error("boom", 0) end
    local fs = UIParent:CreateFontString(nil, "OVERLAY")
    local ok = pcall(C.ApplyFont, fs, nil, 11)
    idx.SetFontObject = realObj
    assertTrue(ok, "the template call is pcall'd too")
end)

-- -------------------------------------------------------------------- WarmFont --

test("WarmFont: one shown, anchored, alpha-0 fontstring per path; idempotent", function()
    withFontStub("pending", function(st)
        local path = freshPath("warm")
        local fs = C.WarmFont(path)
        assertNotNil(fs, "the warm string exists")
        assertEquals(path, fs._stubFont, "it asked the client for THIS file")
        assertTrue(fs:IsShown(), "shown (a hidden string never loads the file)")
        assertTrue(fs:GetNumPoints() >= 1, "anchored (an unanchored one never loads it)")
        assertTrue(fs:GetText() ~= nil and fs:GetText() ~= "", "it carries text")
        local holder = fs:GetParent()
        assertTrue(holder:IsShown(), "the holder is always shown")
        assertEquals(0, holder:GetAlpha(), "alpha 0")
        assertEquals("BACKGROUND", holder:GetFrameStrata())
        assertEquals(UIParent, holder:GetParent())
        assertTrue(holder:GetNumPoints() >= 1, "the holder is anchored on screen")
        assertFalse(holder:IsMouseEnabled(), "no mouse")
        assertNil(holder:GetScript("OnUpdate"), "no OnUpdate")
        -- Idempotent: the same string back, no second SetFont for the path.
        local calls = 0
        for _, c in ipairs(st.set) do if c.path == path then calls = calls + 1 end end
        assertEquals(fs, C.WarmFont(path))
        assertEquals(fs, C.WarmFont(path))
        local calls2 = 0
        for _, c in ipairs(st.set) do if c.path == path then calls2 = calls2 + 1 end end
        assertEquals(calls, calls2, "no second string, no second SetFont")
        -- A second path: its own string, the SAME holder.
        local fs2 = C.WarmFont(freshPath("warm"))
        assertTrue(fs2 ~= fs)
        assertEquals(holder, fs2:GetParent(), "one tiny holder for every path")
    end)
end)

test("WarmFont: a path that raises keeps nothing and is not retried", function()
    withFontStub("raise", function(st)
        local path = freshPath("warmraise")
        local ok, fs = pcall(C.WarmFont, path)
        assertTrue(ok, "no error escapes")
        assertNil(fs)
        local n1 = #st.set
        assertNil(C.WarmFont(path))
        assertEquals(n1, #st.set, "a refused path is remembered, not retried")
    end)
    assertNil(C.WarmFont(nil))
    assertNil(C.WarmFont(""))
end)

test("the login pass warms the shipped font", function()
    local warmed
    local realWarm, realLoad, realStartup = C.WarmFont, FX.LoadClassAddOn, FX.PrintStartupLine
    local savedModules, savedOrder = FX.modules, FX._moduleOrder
    local savedLedger, savedDone = FX._enabledModules, FX._loginDone
    FX.modules, FX._moduleOrder, FX._enabledModules = {}, {}, {}
    FX._loginDone = false
    C.WarmFont = function(path) warmed = path end
    FX.LoadClassAddOn = function() end
    FX.PrintStartupLine = function() return false end
    local ok, err = pcall(FX.RunLoginPass)
    C.WarmFont, FX.LoadClassAddOn, FX.PrintStartupLine = realWarm, realLoad, realStartup
    FX.modules, FX._moduleOrder = savedModules, savedOrder
    FX._enabledModules, FX._loginDone = savedLedger, savedDone
    assertTrue(ok, tostring(err))
    assertEquals(FX.CLASSIC_FONT, warmed)
end)

-- ------------------------------------------------------------ TextWidthPending --

test("TextWidthPending: 0 for non-empty text is pending; empty text never is", function()
    assertTrue(C.TextWidthPending(0, "12.5"))
    assertTrue(C.TextWidthPending(nil, "12.5"))
    assertTrue(C.TextWidthPending("x", "12.5"))
    assertFalse(C.TextWidthPending(33.1, "12.5"))
    assertFalse(C.TextWidthPending(0, ""))
    assertFalse(C.TextWidthPending(0, nil))
end)

-- ------------------------------------------------------------- WhenFontLoaded --

test("WhenFontLoaded: ticker polls FontLoaded, fires once, stops; callbacks are pcall'd",
function()
    local cap, restore = captureTickers()
    local ok, err = pcall(function()
        withFontStub("pending", function(st)
            local path = freshPath("when")
            local hits = {}
            local function a(p) hits[#hits + 1] = "a:" .. p end
            local function bad() error("callback boom", 0) end
            local function b(p) hits[#hits + 1] = "b:" .. p end
            assertFalse(C.WhenFontLoaded(path, a), "pending: not loaded yet")
            assertFalse(C.WhenFontLoaded(path, a), "the same fn twice is one registration")
            C.WhenFontLoaded(path, bad)
            C.WhenFontLoaded(path, b)
            assertEquals(1, #cap.made, "ONE ticker per path, not one per callback")
            local t = cap.made[1]
            assertEquals(0.5, t.interval)
            assertEquals(40, t.iterations, "40 x 0.5 s = the ~20 s budget")
            assertNotNil(C.WarmFont(path), "polling a font nobody shows would never load: it is warmed")
            t.fn()
            assertEquals(0, #hits, "still pending: nothing fires")
            assertFalse(t.cancelled)
            st.mode = "loaded"                  -- the file has rendered
            t.fn()
            assertEquals(2, #hits, "a and b fired; the raising one did not stop them")
            assertEquals("a:" .. path, hits[1])
            assertEquals("b:" .. path, hits[2])
            assertTrue(t.cancelled, "the ticker stops as soon as it is true")
            t.fn()
            assertEquals(2, #hits, "and never fires twice")
            -- Already loaded: nothing is pending, nothing is polled.
            local made = #cap.made
            assertTrue(C.WhenFontLoaded(path, a))
            assertEquals(made, #cap.made)
            assertEquals(2, #hits)
        end)
    end)
    restore()
    assertTrue(ok, tostring(err))
end)

test("WhenFontLoaded: gives up after ~20 s and can be re-armed", function()
    local cap, restore = captureTickers()
    local ok, err = pcall(function()
        withFontStub("pending", function()
            local path = freshPath("giveup")
            local fired = 0
            local function fn() fired = fired + 1 end
            C.WhenFontLoaded(path, fn)
            local t = cap.made[1]
            for _ = 1, 39 do t.fn() end
            assertFalse(t.cancelled, "39 polls in: still waiting")
            t.fn()
            assertTrue(t.cancelled, "the 40th poll ends the wait")
            assertEquals(0, fired, "a font that never rendered never fires")
            C.WhenFontLoaded(path, fn)
            assertEquals(2, #cap.made, "a later request re-arms a fresh ticker")
        end)
    end)
    restore()
    assertTrue(ok, tostring(err))
end)
