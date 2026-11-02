-- addon/Forte_Shaman/tests/test_00_class_data.lua
-- Load-on-demand bootstrap: Forte_Shaman's OWN files are the subject of this
-- suite, and the sim's profile class (Paladin) never loads them -- a
-- load-on-demand add-on's files run only when it is loaded
-- (docs/reference/wow-ui-sim-specs/addon-lod-metadata.md), and `run-tests`
-- does not run them for their own tests. So the suite pulls its subject in
-- through the same entry point Forte_Core's PLAYER_LOGIN path uses -- the real
-- `C_AddOns.LoadAddOn`, not a fake -- before test_totems.lua derefs
-- `ForteXorcist.Shaman`.
--
-- A module that registers AFTER Forte_Core's login loop is enabled at once
-- (addon/Forte_Core/tests/test_loader.lua), so the Shaman module registers and
-- enables against a PALADIN profile here: its class gate (Core/Totems.lua's
-- OnEnable, the Forte_Hunter/Core/Tools.lua:467 shape) must keep the event
-- wiring off, and that is the state the rest of this suite asserts from.
--
-- One call is the whole bootstrap: Core/Loader.lua does not accept the runner's
-- `IsAddOnLoaded` listing as proof that the files ran (its own probe is the
-- add-on's data table), so the listed-but-not-parsed add-on goes through
-- `C_AddOns.LoadAddOn` for real -- the gap that used to need a hand-written
-- loader call here (F-B, 2026-11-02).
local FX = ForteXorcist

FX.LoadClassAddOn("SHAMAN")

test("the add-on under test is loaded, and its module is enabled", function()
    assertNotNil(FX.Data and FX.Data.Shaman, "Forte_Shaman's data did not load")
    assertNotNil(FX.modules.Shaman, "the Totems module did not register")
    assertEquals(true, FX._enabledModules.Shaman, "enabled at once after login")
    assertNotNil(FX.Shaman and FX.Shaman.TotemTracker,
        "the totem tracker class did not load")
    assertFalse(FX.modules.Shaman._eventsEnabled,
        "a Paladin profile wires no Shaman events")
    assertNil(FX.modules.Shaman._eventFrame,
        "a Paladin profile builds no Shaman event frame")
end)
