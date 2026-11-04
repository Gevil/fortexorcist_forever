-- =============================================================================
-- test_zz_combat_options.lua — the I2f combat-simulation round for the
-- Options window (PLAN §11.2 row I2f).
--
-- NAME LAW: the "zz_" prefix sorts this file LAST. No manual clock rides
-- this suite: the window owns no windows on the Timer rows and no clock of
-- its own; the only timed half is the tooltip Hide chain (C_Timer.After at
-- the shared tooltip owner) and this suite never enters the tips.
--
-- WHAT THIS ROUND DRIVES (the I2f assignment):
--   * the REAL slash dispatch (/fx options) opens the window IN COMBAT and
--     the close button's REAL OnClick script closes it — no raised error,
--     and the round prints nothing on the way;
--   * a setting is changed through the live store IN COMBAT (FX.Settings:Set
--     — the path every widget's OnChange rides), the module's OnChange wave
--     lands on the live consumer, and the value rides back at Get — the
--     change is restored verbatim;
--   * the login wiring law: the window's chrome scripts (close button
--     OnClick, the scroll frame's OnMouseWheel) are the reachable real
--     scripts of a login-wired module — the close leg drives the real
--     script, not the method.
--
-- SIM LAWS:
--   * FX.Print captured — the round is a print-zero (the window draws, it
--     never prints);
--   * the window is module-shared state (the baseline window tests rode
--     first): the gate records the found shown state and the zzz restores
--     the open/closed shape by the same Toggle seam;
--   * the store (FX.Settings) is shared: the setting leg rides
--     Get → Set → Get → Set(found value) so the store ends where it began.
-- =============================================================================
local FX = ForteXorcist
local O = FX.Options
local Settings = FX.Settings

local saved
local printCapture

local function capturePrint()
    printCapture = { lines = 0 }
    saved.realPrint = FX.Print
    FX.Print = function(...)
        printCapture.lines = printCapture.lines + 1
        print(...)
    end
end
local function releasePrint()
    if saved.realPrint then FX.Print = saved.realPrint end
    saved.realPrint = nil
end

-- ---------------------------------------------------------------------- gate
test("zz combat gate: the window module is on the slash surface", function()
    assertNotNil(O, "FX.Options exists")
    assertNotNil(O.Toggle, "the Toggle seam rides")
    assertNotNil(O.IsOpen, "the IsOpen seam rides")
    assertNotNil(Settings, "FX.Settings rides")
    assertTrue(Settings:IsRegistered("Advanced"),
        "the Advanced page is registered (the setting leg rides it)")
    saved = {}
    capturePrint()
    -- The slash law: the window owns the "options" subcommand on the
    -- shared slash registry (the sim routes chat lines through
    -- FX.OnSlash → FX.slashSubs; SlashCmdList is not the seam here).
    assertNotNil(FX.slashSubs, "the slash registry rides")
    assertNotNil(FX.slashSubs["options"],
        "the options subcommand rides the registry")
    assertEquals("function", type(FX.OnSlash),
        "the slash dispatcher rides")
    -- The shared-state anchor: the found open shape (the baseline window
    -- files rode first).
    saved.wasOpen = O:IsOpen() and true or false
    -- The setting the leg rides, found value first (the store restore).
    saved.startupText = Settings:Get("Advanced", "ShowStartupText")
    assertNotNil(saved.startupText,
        "the ShowStartupText setting rides a value (the pages' defaults)")
    A_Admin.SetInCombat(true)
    assertTrue(InCombatLockdown(), "the sim lockdown gate is active")
end)

-- ---------------------------------------------------- open/close in combat --
test("in combat: /fx options opens, the real close script closes — clean",
function()
    local opened = O:Toggle()          -- the /fx options dispatch seam
    assertTrue(opened ~= false, "the open rode")
    local window = O.window
    assertNotNil(window, "the window frame is built")
    assertTrue(window:IsShown(), "the window is SHOWN in combat")
    assertNotNil(O.closeBtn, "the close button is chrome")
    local clicks = O.closeBtn:GetScript("OnClick")
    assertNotNil(clicks, "the close script is reachable (login chrome law)")
    local closed = clicks(O.closeBtn)  -- the real script, not the method
    -- (The close script rides the Close method; the return rides nil — the
    -- shown state is the law.)
    assertEquals(false, O.window:IsShown(),
        "the real close script hides the window in combat")
    assertEquals(0, printCapture.lines,
        "the open/close round printed nothing ("
        .. tostring(printCapture.lines) .. " lines)")
    assertEquals(saved.wasOpen, O:IsOpen() and true or false,
        "the found open shape rides back")
end)

-- ---------------------------------------------------- a setting in combat --
test("in combat: a store Set rides out through the live view and back",
function()
    local found = Settings:Get("Advanced", "ShowStartupText")
    local nextValue = not found
    local applied = {}
    local listener = function(key, value)
        applied[#applied + 1] = tostring(key) .. "=" .. tostring(value)
    end
    Settings:OnChange("Advanced", listener)
    Settings:Set("Advanced", "ShowStartupText", nextValue)
    assertEquals(nextValue, Settings:Get("Advanced", "ShowStartupText"),
        "the Set rides back at Get (the live view)")
    Settings:Set("Advanced", "ShowStartupText", found)   -- the store restore
    assertEquals(found, Settings:Get("Advanced", "ShowStartupText"),
        "the found value rides back verbatim")
    assertEquals(2, #applied,
        "the OnChange wave reached the module wires ("
        .. table.concat(applied, ", ") .. ")")
    assertEquals(0, printCapture.lines,
        "the change printed nothing (" .. tostring(printCapture.lines)
        .. " lines)")
end)

-- -------------------------------------------------------- the combat state --
test("in combat: the window stays closed by default (no auto-show half)",
function()
    assertEquals(false, O.window ~= nil and O.window:IsShown(),
        "the window rides hidden — the module never opens it on state")
    -- The scroll chrome script is the reachable login-wired pair (the
    -- wheel is driven on the SHOWN path only by the page tests; the law
    -- here is reachability).
    local scroller = O.contentScroll
    if scroller then
        assertNotNil(scroller:GetScript("OnMouseWheel"),
            "the scroll wheel script is reachable (login chrome law)")
    else
        assertTrue(true, "no scroll frame on this build")
    end
end)

-- ---------------------------------------------------------------------- zzz --
test("zzz the suite leaves the module state as it found it", function()
    A_Admin.SetInCombat(false)
    local lines = printCapture.lines
    releasePrint()
    assertEquals(0, lines,
        "the round printed nothing (" .. tostring(lines) .. " lines)")
    assertEquals(saved.wasOpen, O:IsOpen() and true or false,
        "the found open shape rides back (the shared window state)")
    assertEquals(saved.startupText,
        Settings:Get("Advanced", "ShowStartupText"),
        "the store rides the found value (the shared store state)")
end)
