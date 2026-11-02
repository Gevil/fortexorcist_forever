-- Load-on-demand bootstrap: Forte_Hunter's OWN files are the subject of this
-- suite, and the sim's profile class (Paladin) never loads them -- a
-- load-on-demand add-on's files run only when it is loaded
-- (docs/reference/wow-ui-sim-specs/addon-lod-metadata.md), and `run-tests`
-- does not run them for their own tests. So the suite pulls its subject in
-- through the same entry point Forte_Core's PLAYER_LOGIN path uses -- the real
-- `C_AddOns.LoadAddOn`, not a fake -- before the files that deref
-- `ForteXorcist.Hunter.Tools` at file scope.
--
-- That is also the law this split adds: a module that registers AFTER
-- Forte_Core's login loop is enabled at once, in registration order (see
-- addon/Forte_Core/tests/test_loader.lua). Here that means the Hunter modules
-- register and enable against a Paladin profile -- their class gates keep them
-- off, exactly as they were when this suite ran with the add-on always loaded.
local FX = ForteXorcist

FX.LoadClassAddOn("HUNTER")

test("the add-on under test is loaded, and its modules are enabled", function()
    assertNotNil(FX.Data and FX.Data.Hunter, "Forte_Hunter's data did not load")
    assertNotNil(FX.modules.Hunter, "the Tools module did not register")
    assertNotNil(FX.modules.HunterUI, "the UI module did not register")
    assertEquals(true, FX._enabledModules.Hunter, "enabled at once after login")
    assertEquals(true, FX._enabledModules.HunterUI, "enabled at once after login")
    assertFalse(FX.modules.Hunter._eventsEnabled, "a Paladin profile wires no Hunter events")
    assertNil(FX.modules.HunterUI._eventFrame, "a Paladin profile builds no Hunter UI")
end)
