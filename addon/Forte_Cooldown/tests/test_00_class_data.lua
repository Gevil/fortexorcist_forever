-- Load-on-demand bootstrap: the fixtures this suite audits are the Hunter and
-- Warlock data sets (`Engine:Build("HUNTER")` for the tiles/tiers/reconcile
-- probes, the `Data.<Class>` name census in `test_engine.lua`), NOT the sim
-- profile's. With `## LoadOnDemand: 1` a session parses an add-on's files only
-- when it is loaded (docs/reference/wow-ui-sim-specs/addon-lod-metadata.md):
-- Forte_Core's PLAYER_LOGIN loader pulls in the add-on of the *profile* class
-- (the sim's default is Paladin), and `run-tests` does not run a
-- load-on-demand add-on's own files. So the suite asks for the add-ons it
-- audits through the same entry point the login path uses -- Forte_Core's real
-- `C_AddOns.LoadAddOn`, not a fake -- and asserts the data arrived, so a suite
-- can never silently audit a nil data table. It runs as the first file
-- (`test_00_`) so every later file's file-scope reads see the data.
local FX = ForteXorcist

-- Forte_Core (the loader) is a dependency of every class add-on, so it is
-- always in the session.
FX.LoadClassAddOn("HUNTER")
FX.LoadClassAddOn("WARLOCK")

test("the add-ons whose data these fixtures are are loaded", function()
    assertNotNil(FX.Data and FX.Data.Hunter, "Forte_Hunter's data did not load")
    assertNotNil(FX.Data and FX.Data.Warlock, "Forte_Warlock's data did not load")
end)
