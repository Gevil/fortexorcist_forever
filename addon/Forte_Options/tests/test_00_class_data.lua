-- Load-on-demand bootstrap: this suite asserts a CLASS Tools table's rows land
-- in the index and that its page is registered (it uses Forte_Hunter:
-- `FX.Hunter.Swing`'s 21 rows and `Pages/Hunter.lua`). With
-- `## LoadOnDemand: 1` a session parses an add-on's files only when it is
-- loaded (docs/reference/wow-ui-sim-specs/addon-lod-metadata.md): Forte_Core's
-- PLAYER_LOGIN loader pulls in the add-on of the *profile* class (the sim's
-- default is Paladin) and `run-tests` does not run a load-on-demand add-on's
-- own files. So the suite asks for the add-on it audits through the same entry
-- point the login path uses -- Forte_Core's real `C_AddOns.LoadAddOn`, not a
-- fake -- and asserts it arrived. The class add-on is loaded at LOGIN in the
-- product, i.e. while Forte_Core's enable loop is still running, so its page is
-- in the index before any window opens; this session loads it at test time, and
-- `Window:RefreshIndexCells` is the shipped late-registration path (PLAN §10.2).
local FX = ForteXorcist

FX.LoadClassAddOn("HUNTER")
-- CodeReview3 C4 audits the four WARLOCK pages' header glyphs too, so the
-- suite asks for Forte_Warlock at the same entry point (its Pages chunk
-- registers the pages the moment FX.Options exists; its UI module is
-- class-gated, so on this Paladin profile the plates stay un-Init'ed --
-- exactly the shape C4's test drives the header through).
FX.LoadClassAddOn("WARLOCK")

test("the add-on whose Tools table and page are audited is loaded", function()
    assertNotNil(FX.Hunter, "Forte_Hunter's modules did not register")
    assertNotNil(FX.Hunter and FX.Hunter.Swing, "Forte_Hunter's Tools table is not there")
    assertNotNil(FX.Data and FX.Data.Hunter, "Forte_Hunter's data did not load")
end)
