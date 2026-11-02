-- Load-on-demand bootstrap: Forte_Warlock's OWN files are the subject of this
-- suite, and the sim's profile class (Paladin) never loads them -- a
-- load-on-demand add-on's files run only when it is loaded
-- (docs/reference/wow-ui-sim-specs/addon-lod-metadata.md), and `run-tests`
-- does not run them for their own tests. So the suite pulls its subject in
-- through the same entry point Forte_Core's PLAYER_LOGIN path uses -- the real
-- `C_AddOns.LoadAddOn`, not a fake.
--
-- That is also the law this split adds: a module that registers AFTER
-- Forte_Core's login loop is enabled at once, in registration order (see
-- addon/Forte_Core/tests/test_loader.lua). Here the Warlock modules register
-- and enable against a Paladin profile, so their class gates keep them off --
-- the state the rest of this suite asserts from.
local FX = ForteXorcist

FX.LoadClassAddOn("WARLOCK")

test("the add-on under test is loaded, and its modules are enabled", function()
    assertNotNil(FX.Data and FX.Data.Warlock, "Forte_Warlock's data did not load")
    assertNotNil(FX.modules.Warlock, "the Tools module did not register")
    assertNotNil(FX.modules.WarlockUI, "the UI module did not register")
    assertEquals(true, FX._enabledModules.Warlock, "enabled at once after login")
    assertEquals(true, FX._enabledModules.WarlockUI, "enabled at once after login")
    assertFalse(FX.modules.Warlock._eventsEnabled, "a Paladin profile wires no Warlock events")
    assertNil(FX.modules.WarlockUI._driver, "a Paladin profile builds no Warlock UI")
end)
