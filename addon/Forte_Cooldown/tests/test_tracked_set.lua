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
-- The T1 seven-class cast-spell census below (see `T1_ADDED`) reads the
-- generated data of the whole wave 2b cut, so it asks for those add-ons at the
-- same entry point (docs/class-port.md §6.1; the paladin one is the sim's
-- profile class and is loaded by Forte_Core's login path already).
FX.LoadClassAddOn("DRUID")
FX.LoadClassAddOn("PRIEST")
FX.LoadClassAddOn("SHAMAN")
FX.LoadClassAddOn("WARRIOR")

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
    -- Sap is Rogue. Seduction joined this set on the 70707 data refresh
    -- (DataRefresh wave 2a): the store names 6358 with a 15 s duration, so
    -- the page's fade/break row is live now (LocaleB lights it). The page's
    -- remaining names have no trackable row on this build (see the next
    -- test), which is the E4 report.
    local warlock = tracked("WARLOCK")
    assertNotNil(warlock, "no generated Warlock data to build on")
    for _, name in ipairs({ "Fear", "Banish", "Subjugate Demon", "Seduction" }) do
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
    -- rows is a signal to light the page rows, not a silent drift. The
    -- 70707 data refresh (DataRefresh wave 2a) RESOLVED two of the three:
    -- Seduction 6358 now rides the tracked set (pinned in the test above,
    -- and in test_70707_overlay.lua), and the Mesmerize pet alias 24594 is
    -- in the data NAME-ONLY (the store's Names table has the id, its value
    -- tables carry no row) -- an inert row is no CC window, so the
    -- fade/break row for it stays dark. `Enslave Demon` (2012) remains
    -- absent: the client's 1098 name is Subjugate Demon.
    local warlock = tracked("WARLOCK")
    assertNotNil(warlock, "no generated Warlock data to build on")
    assertNil(warlock["Enslave Demon"],
        "Enslave Demon just entered the Warlock data: Forte_Messages'"
        .. " fade/break rows for it are live now -- light them")
    assertNil(warlock["Mesmerize"],
        "Mesmerize just gained a duration: Forte_Messages' fade/break rows"
        .. " for it are live now -- light them")
end)

-- addon/Forte_Cooldown/tests/test_tracked_set.lua :: T1 (wave 2b) ----------
-- The SEVEN-CLASS CAST-SPELL CUT: docs/class-port.md §6.1 as planned by
-- PLAN.md §11.1 wave 2b T1 (owner Q1 ruling: the spells the player CASTS go in
-- now, the proc buffs / passive effects ride with H7; manager Q6 ruling: the
-- family-less Forever rows go in too). The law this census holds is the one
-- the two engines already enforce: an added name is only worth a row when the
-- generated data gives it a window -- the Spell Timer registry takes
-- `durationMs > 0`, the Cooldown engine takes `cooldownMs / 1000 >=
-- Engine.MIN_COOLDOWN`. A name the data names with no window at all is a
-- tracked-by-neither row: legal in the list, useless on the bar, so it is
-- pinned with the build's reason instead of being hidden.

-- The names T1 added, per class, straight out of the seven
-- tools/spell_lists/<class>.json files (group placement is the file's own
-- intent; the generated row is what is audited here).
local T1_ADDED = {
    -- Wave I-2b: Berserk left (the post-9 notes REMOVE the talent, Primal
    -- Bite replaces it -- docs/research/forever-dev-notes-2026-11-03.md §1
    -- Druid row) and Lava Burst left with it (same §1 Shaman row: gone from
    -- the live client). docs/class-port.md 6.2 item 5.
    DRUID = { "Lifebloom", "Skull Bash", "Pounce", "Pounce Bleed", "Starfall",
              "Dash", "Thrash" },
    MAGE = { "Blizzard", "Living Bomb", "Pyroblast", "Flamestrike", "Combustion",
             "Cone of Cold", "Frost Nova", "Deep Freeze", "Frostfire Bolt",
             "Arcane Blast", "Blast Wave", "Fire Blast", "Freeze" },
    PALADIN = { "Beacon of Light", "Reckoning", "Aura Mastery", "Holy Shield",
                "Holy Shock" },
    PRIEST = { "Vampiric Touch", "Renew", "Devouring Plague", "Holy Fire",
               "Prayer of Mending", "Mind Blast", "Mind Flay", "Mind Sear" },
    ROGUE = { "Dismantle", "Crimson Tempest", "Mind-numbing Poison",
              "Deadly Poison", "Envenom" },
    SHAMAN = { "Stormstrike", "Ancestral Guidance", "Heroism" },
}
local T1_CLASS_ORDER = { "DRUID", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN" }

-- The added names the build gives NO window for, with the reason read off the
-- data row (the report's "tracked by neither" list). `d:` / `c:` name the row
-- field the engine gates on. A row that grows a window on a later data pull
-- trips the test below, which is the signal to delete its entry.
local T1_UNTRACKED = {
    DRUID = {
        ["Thrash"] = "21919 is a name-only row (no cooldownMs, no durationMs)",
    },
    PALADIN = {
        ["Beacon of Light"] = "409906 is a name-only row (no cooldownMs, no durationMs)",
        ["Reckoning"] = "1326084 rides durationMs = -1, the permanent-aura sentinel",
        ["Aura Mastery"] = "409932 is a name-only row (no cooldownMs, no durationMs)",
    },
    ROGUE = {
        ["Dismantle"] = "442206 has no window; its icdMs 12000 is a proc window (H7, docs/design-combat-procs.md)",
        ["Envenom"] = "399968 is a name-only row (a passive enabler: H7 territory)",
    },
    SHAMAN = {
        ["Ancestral Guidance"] = "the family-11 rows (409333/409337/409944) carry no window; the 60 s cooldown rides the paladin family-10 row 409324 and the family law never takes a foreign row",
        ["Heroism"] = "23689 rides durationMs = -1, the permanent-aura sentinel",
    },
}

-- The proc/passive names the owner ruling kept OUT (the `_deferred_H7` note
-- of each spell-list file): they arrive with H7 (docs/design-combat-procs.md)
-- behind the ICD/procs design, so their absence from the generated data is
-- the plan, not an omission.
local T1_DEFERRED = {
    DRUID = { "Clearcasting", "Living Seed", "Nature's Grace", "Savage Defense" },
    MAGE = { "Brain Freeze", "Chilled", "Fingers of Frost", "Ignite", "Mana Surge" },
    PALADIN = { "Ancient Power", "Forbearance", "Grand Crusader", "Infusion of Light",
                "The Art of War", "Vengeance", "Vindication" },
    PRIEST = { "Serendipity", "Surge of Light" },
    ROGUE = {},
    SHAMAN = { "Maelstrom Weapon" },
    WARRIOR = { "Deep Wounds", "Enrage", "Vigilance" },
}

local function dataKey(classToken)
    return classToken:sub(1, 1):upper() .. classToken:sub(2):lower()
end

test("every T1 cast-spell add is tracked, or is a pinned no-window row",
function()
    local Engine = FX.Cooldown.Engine
    assertNotNil(Engine, "Forte_Cooldown's Engine is not in the session")
    local allKnown = function() return true end
    local report, pinned, total = {}, 0, 0
    for _, cls in ipairs(T1_CLASS_ORDER) do
        local names = T1_ADDED[cls]
        local key = dataKey(cls)
        local data = FX.Data and FX.Data[key]
        assertNotNil(data, key .. "'s generated data did not load")
        local byName = FX.Data[key .. "ByName"]
        assertNotNil(byName, key .. "ByName did not load")
        local reg = tracked(cls)
        assertNotNil(reg, "no generated " .. key .. " data to build a registry on")
        -- The Cooldown half of the pair: the Engine's own Build over the same
        -- generated rows, with isKnown stubbed true (a data census asks what
        -- the DATA can ring a row for, not what this test character knows).
        assertNotNil(Engine:Build(cls, allKnown), "Engine:Build has no " .. key .. " data")
        local n = 0
        for _, name in ipairs(names) do
            total = total + 1
            local id = byName[name]
            assertNotNil(id, name .. " (" .. key .. ") is not in the generated data")
            local row = data[id]
            assertNotNil(row, name .. " (" .. key .. ") has no data row at " .. tostring(id))
            local entry = reg[name]
            local engineRow = Engine.tracked and Engine.tracked[name]
            local reason = (T1_UNTRACKED[cls] or {})[name]
            if entry or engineRow then
                assertNil(reason, name .. " (" .. key
                    .. ") is tracked now -- its T1_UNTRACKED entry is stale: "
                    .. tostring(reason))
                n = n + 1
                if not entry then
                    -- Cooldown-engine half: the floor is the Engine's own.
                    assertTrue(type(row.cooldownMs) == "number"
                        and row.cooldownMs / 1000 >= Engine.MIN_COOLDOWN,
                        name .. " rides no cooldown the Engine's floor accepts")
                else
                    assertTrue(entry.duration > 0,
                        name .. " has a registry row with no length")
                end
            else
                assertNotNil(reason, name .. " (" .. key .. ", row " .. tostring(id)
                    .. ") is tracked by NEITHER engine: no registry durationMs > 0"
                    .. " and no Cooldown cooldownMs over the floor -- a bar-less row")
                assertTrue(type(row.durationMs) ~= "number" or row.durationMs <= 0,
                    name .. " carries a positive duration and must be tracked")
                assertTrue(row.cooldownMs == nil
                    or row.cooldownMs / 1000 < Engine.MIN_COOLDOWN,
                    name .. " carries a floor-sized cooldown and must be tracked")
                pinned = pinned + 1
            end
        end
        report[#report + 1] = key .. " " .. n .. "/" .. #names
    end
    local line = "[T1] tracked=" .. (total - pinned) .. "/" .. total
        .. " pinned-untracked=" .. pinned .. " | " .. table.concat(report, " ")
    print(line)
    if io and io.open then
        local f = io.open("/tmp/t1_tracked_report.txt", "w")
        if f then f:write(line .. "\n"); f:close() end
    end
    -- 7 + 13 + 5 + 8 + 5 + 3 = 41 added names, 8 of them no-window rows; the
    -- Warrior adds none (all three of its §6.1 names are H7 deferrals).
    -- Wave I-2b cut the count 43 -> 41 (Berserk, Lava Burst: post-9 removals,
    -- docs/class-port.md 6.2 item 5).
    assertEquals(41, total)
    assertEquals(8, pinned)
end)

test("the H7 proc/passive deferrals are out of the generated data", function()
    -- The owner ruling's other half: these names are NOT in the lists yet, so
    -- a data pull that lands one of them is the signal to light the H7 design,
    -- not a silent drift into the class data.
    local seen = 0
    for _, cls in ipairs(T1_CLASS_ORDER) do
        local key = dataKey(cls)
        local byName = FX.Data[key .. "ByName"]
        assertNotNil(byName, key .. "ByName did not load")
        for _, name in ipairs(T1_DEFERRED[cls] or {}) do
            assertNil(byName[name], name .. " (" .. key
                .. ") entered the generated data: the H7 proc pass (docs"
                .. "/design-combat-procs.md) owns it -- land it there")
            seen = seen + 1
        end
    end
    for _, name in ipairs(T1_DEFERRED.WARRIOR) do
        assertNil(FX.Data.WarriorByName[name], name
            .. " entered the Warrior data: it is an H7 deferral")
        seen = seen + 1
    end
    -- 4 + 5 + 7 + 2 + 0 + 1 + 3 = 22 deferred names.
    assertEquals(22, seen)
end)

-- Hand the registry back to the session's own class (the Forte_Timer
-- suites' restore pattern; run-tests leaves the registry built for the
-- profile class).
test("restore the registry to the profile class", function()
    Registry:AttachStorage(FX.db and FX.db.timer and FX.db.timer.learned or {})
    Registry:Build(FX._playerClass)
end)
