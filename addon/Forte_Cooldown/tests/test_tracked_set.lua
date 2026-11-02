-- addon/Forte_Cooldown/tests/test_tracked_set.lua
-- The DATA half of CodeReview4 E4: which spells the Spell Timer can actually
-- ring a row for. Forte_Messages' raid page registers six crowd-control
-- spells for its fade/break rows, and E4's finding was that four of them can
-- never fire, because the Spell Timer's tracked set is
-- `FX.Timer.Registry:Build(FX._playerClass)` over the GENERATED class data
-- (`Core/Registry.lua`'s `durationMs > 0` gate): a spell the data does not
-- name, or names with no positive duration, has no row, and a fade/break row
-- over a rowless spell is a bell with no clapper.
--
-- This suite lives in Forte_Cooldown because the artefact it audits is the
-- GENERATED data set (tools/spell_lists/<class>.json + gen_spell_data.py),
-- which is a repo-level artefact, not a Forte_Timer artefact -- Forte_Timer's
-- own suites are `tests/test_rows.lua` (the Build gate over the HUNTER data)
-- and `tests/test_kinds.lua` (the nine-class kind-band census). Both read the
-- same generated files; nothing here hand-lists a spell ID.
--
-- The registry Build is the game seam; the suite builds it per class and
-- hands the registry back to the profile class at the end (the framework has
-- no teardown, the established pattern of Forte_Timer/tests/test_rows.lua).

local FX = ForteXorcist

-- The add-ons whose data this census reads (the LoD bootstrap law, see
-- test_00_class_data.lua): ask for them through Forte_Core's real loader.
FX.LoadClassAddOn("MAGE")
FX.LoadClassAddOn("WARLOCK")
FX.LoadClassAddOn("ROGUE")

local Registry = FX.Timer and FX.Timer.Registry

test("the add-ons whose data this census reads are loaded", function()
    assertNotNil(FX.Data and FX.Data.Mage, "Forte_Mage's data did not load")
    assertNotNil(FX.Data and FX.Data.Warlock, "Forte_Warlock's data did not load")
    assertNotNil(FX.Data and FX.Data.Rogue, "Forte_Rogue's data did not load")
    assertNotNil(Registry, "Forte_Timer's registry is not in the session")
end)

--- Build the registry for one class and report [name] = true for every
--- tracked entry; nil when the class's data is not in the session.
local function tracked(classToken)
    if not Registry:Build(classToken) then return nil end
    local set = {}
    for name, entry in pairs(Registry.entries) do
        set[name] = entry
    end
    return set
end

test("Polymorph is in the Mage Spell Timer's tracked set (CodeReview4 E4)",
function()
    local mage = tracked("MAGE")
    assertNotNil(mage, "no generated Mage data to build on")
    -- E4 shipped the fix: tools/spell_lists/mage.json names the spell and
    -- the generator resolved it (rank 4, 12826, durationMs 50000).
    local poly = mage["Polymorph"]
    assertNotNil(poly, "Polymorph is not tracked: the Mage data lost its row")
    assertTrue(type(poly.dataId) == "number" and poly.dataId > 0)
    assertTrue(type(poly.duration) == "number" and poly.duration > 0,
        "the registry's gate is durationMs > 0; a row spec needs a length")
    -- The row spec's length is the data's, ms -> s (50 s at rank 4).
    local data = FX.Data.Mage[poly.dataId]
    assertNotNil(data)
    assertEquals("Polymorph", data.name)
    assertTrue(poly.duration * 1000 == data.durationMs)
    -- A CC window paints the crowd-control band, not the neutral Default
    -- (test_kinds.lua holds the census floor; this pins the one new name).
    assertEquals("Crowds", Registry._kindFor("Polymorph"))
end)

test("the Warlock and Rogue CC spells the pages name ARE tracked", function()
    -- Forte_Messages/Pages/RaidMsg.lua registers Fear, Banish,
    -- `Enslave Demon`, Seduction, Polymorph and Sap. The Forever names of
    -- the Warlock pair are Fear + Banish + Subjugate Demon (1098 is
    -- `Subjugate Demon` on this client, NOT the 2012 `Enslave Demon`);
    -- Sap is Rogue. The page's other two names have no generated row on
    -- this build (see the next test), which is the E4 report.
    local warlock = tracked("WARLOCK")
    assertNotNil(warlock, "no generated Warlock data to build on")
    for _, name in ipairs({ "Fear", "Banish", "Subjugate Demon" }) do
        local entry = warlock[name]
        assertNotNil(entry, name .. " is not in the Warlock tracked set")
        assertTrue(entry.duration > 0, name .. " has no positive duration")
    end
    local rogue = tracked("ROGUE")
    assertNotNil(rogue, "no generated Rogue data to build on")
    local sap = rogue["Sap"]
    assertNotNil(sap, "Sap is not in the Rogue tracked set")
    assertTrue(sap.duration > 0)
end)

test("the page names with no generated row are reported, not hidden", function()
    -- The second half of E4's fact, pinned so the day the data grows these
    -- rows is a signal to light the page rows, not a silent drift: the
    -- Forte_Messages raid page registers `Enslave Demon`, `Seduction` and
    -- the `Mesmerize` pet alias, and on this build's generated Warlock data
    -- none of the three exists (the client's name for 1098 is Subjugate
    -- Demon; Seduction 20707 and Mesmerize 115268 are not in the class list).
    local warlock = tracked("WARLOCK")
    assertNotNil(warlock, "no generated Warlock data to build on")
    for _, name in ipairs({ "Enslave Demon", "Seduction", "Mesmerize" }) do
        assertNil(warlock[name],
            name .. " just entered the Warlock data: Forte_Messages'"
            .. " fade/break rows for it are live now -- light them")
    end
end)

-- Hand the registry back to the session's own class (the Forte_Timer
-- suites' restore pattern; run-tests leaves the registry built for the
-- profile class).
test("restore the registry to the profile class", function()
    Registry:AttachStorage(FX.db and FX.db.timer and FX.db.timer.learned or {})
    Registry:Build(FX._playerClass)
end)
