-- Load-on-demand bootstrap: the rows this suite builds come from the Hunter
-- data set (`test_rows.lua` and `test_module.lua` build the real registry from
-- it), not from the sim profile's. With `## LoadOnDemand: 1` a session parses
-- an add-on's files only when it is loaded
-- (docs/reference/wow-ui-sim-specs/addon-lod-metadata.md): Forte_Core's
-- PLAYER_LOGIN loader pulls in the add-on of the *profile* class (the sim's
-- default is Paladin) and `run-tests` does not run a load-on-demand add-on's
-- own files. So the suite asks for the add-on it audits through the same entry
-- point the login path uses -- Forte_Core's real `C_AddOns.LoadAddOn`, not a
-- fake -- and asserts the data arrived, so a suite can never silently build a
-- registry over a nil data table. `test_kinds.lua`'s census prints a SKIP for
-- classes it has no data for; the census is the full nine-class coverage.
local FX = ForteXorcist

FX.LoadClassAddOn("HUNTER")

test("the add-on whose data these fixtures are is loaded", function()
    assertNotNil(FX.Data and FX.Data.Hunter, "Forte_Hunter's data did not load")
end)
