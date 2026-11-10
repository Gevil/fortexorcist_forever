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
    -- live 70862 store / review 2026-11-10: Thrash left the Druid list (the
    -- name-only row 21919 is gone from the store); the cast adds are six now.
    DRUID = { "Lifebloom", "Skull Bash", "Pounce", "Pounce Bleed", "Starfall",
              "Dash" },
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
    -- (DRUID: Thrash's no-window pin left with the row, 70862 / 2026-11-10;
    -- Dash 9821 is tracked: 15 s window, 300 s cooldown.)
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
-- the plan, not an omission. Wave I-3e H7 (2026-11-03, docs/class-port.md 6.3):
-- the resolvable names MOVED OUT of the note into the lists (Clearcasting,
-- Fingers of Frost, Ignite, the four paladin procs, Maelstrom Weapon, Enrage,
-- Deep Wounds, Shank, Death Mark -- the census below); what remains here is
-- the unresolvable residual: no names.json key, no client Names row, or a
-- family-law gap. The mirror now carries the full note set (Poised and
-- Reckless Swings join the mirror in the same pass).
local T1_DEFERRED = {
    -- live 70862 store / review 2026-11-10: the Druid note is Living Seed,
    -- Nature's Grace, Savage Defense and Eclipse (spell list `_deferred_H7`).
    DRUID = { "Living Seed", "Nature's Grace", "Savage Defense", "Eclipse" },
    MAGE = { "Brain Freeze", "Chilled", "Mana Surge" },
    PALADIN = { "Ancient Power", "Grand Crusader", "The Art of War" },
    PRIEST = { "Serendipity", "Surge of Light" },
    ROGUE = { "Poised" },
    SHAMAN = {},
    -- Reckless Swings left the note on 70862 / 2026-11-10: 1329555 is a value
    -- row now (cd 15 s, 8 s window) and rides H7_LANDED below.
    WARRIOR = { "Vigilance" },
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
    -- 6 + 13 + 5 + 8 + 5 + 3 = 40 added names, 7 of them no-window rows; the
    -- Warrior adds none (all three of its §6.1 names are H7 deferrals).
    -- Wave I-2b cut the count 43 -> 41 (Berserk, Lava Burst: post-9 removals,
    -- docs/class-port.md 6.2 item 5); live 70862 store / review 2026-11-10
    -- cut it 41 -> 40 and the pinned residual 8 -> 7 (Thrash left the data).
    assertEquals(40, total)
    assertEquals(7, pinned)
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
    -- Wave I-3e: 3 + 3 + 3 + 2 + 1 + 0 + 2 = 14 deferred names; 70862 /
    -- 2026-11-10: Druid +Eclipse, Warrior -Reckless Swings = still 14.
    assertEquals(14, seen)
end)

-- Wave I-3e H7 census (PLAN 11.2 I3e, docs/class-port.md 6.3, upstream-data
-- 3.1/5.1). The proc names the H7 gate kept OUT of the T1 cut landed
-- 2026-11-03: every id is wowsims names.json-keyed (MIT) and store/base
-- verified -- nothing hand-typed. The windows ride the cast spine and the
-- out-of-combat aura sweep: Forte_Timer/Core/Reconcile.lua Gates() runs ZERO
-- aura reads in combat, so a sealed read can not fabricate a row -- no row,
-- not a wrong row, the law this census pins for the proc rows.
-- The 2026-11-04 follow-up joins the census: the mage's Clearcasting (the
-- Arcane Concentration proc, id 12536) landed out of the same H7 family,
-- measured live in the uiforever Mage scenario (docs/class-port.md 6.3).
local H7_LANDED = {
    DRUID = { "Clearcasting" },
    MAGE = { "Fingers of Frost", "Ignite", "Clearcasting" },
    PALADIN = { "Forbearance", "Infusion of Light", "Vengeance", "Vindication" },
    ROGUE = { "Shank", "Death Mark" },
    SHAMAN = { "Maelstrom Weapon" },
    -- 70862 / 2026-11-10: Deep Wounds left the Warrior data (12834 is gone);
    -- Reckless Swings 1329555 landed out of _deferred_H7 (cd 15 s, 8 s window).
    WARRIOR = { "Enrage", "Reckless Swings" },
}
local H7_UNTRACKED = {
    -- Wave M3a (2026-11-07): the rogue pair LEFT. The 1.60.1.70790 capture
    -- resolved the rank ladder with values: Shank 1329549 (Rank 2) carries
    -- CooldownMs 10000 / GCDMs 1000 and Death Mark 1325758 (Rank 4) the
    -- CooldownMs 10000, the 6 s mark window (DurationMs 6000) and the 6 s
    -- tick capture -- the post-9 text the pair was pinned on is store fact
    -- now, and both ride the bar (docs/research/data-diff-live-2026-11-07.md
    -- §4/§5.1). The rows they were pinned against (15248/15617,
    -- 1316709/1325756-8) are inert shells no longer picked.
    -- (WARRIOR: the Deep Wounds no-window pin left with the row, 70862 /
    -- 2026-11-10; no pinned no-window residual remains.)
}

test("every Wave I-3e H7 proc add is tracked, or is a pinned no-window row",
function()
    local Engine = FX.Cooldown.Engine
    assertNotNil(Engine, "Forte_Cooldown's Engine is not in the session")
    local allKnown = function() return true end
    local report, pinned, total = {}, 0, 0
    for _, cls in ipairs({ "DRUID", "MAGE", "PALADIN", "ROGUE", "SHAMAN", "WARRIOR" }) do
        local key = dataKey(cls)
        local data = FX.Data and FX.Data[key]
        assertNotNil(data, key .. "'s generated data did not load")
        local byName = FX.Data[key .. "ByName"]
        assertNotNil(byName, key .. "ByName did not load")
        local reg = tracked(cls)
        assertNotNil(reg, "no generated " .. key .. " data to build a registry on")
        assertNotNil(Engine:Build(cls, allKnown), "Engine:Build has no " .. key .. " data")
        local n = 0
        for _, name in ipairs(H7_LANDED[cls] or {}) do
            total = total + 1
            local id = byName[name]
            assertNotNil(id, "I-3e " .. key .. ": " .. name .. " is not in the generated data")
            local row = data[id]
            assertNotNil(row, "I-3e " .. key .. ": " .. name .. " has no row at " .. tostring(id))
            local entry = reg[name]
            local engineRow = Engine.tracked and Engine.tracked[name]
            local reason = (H7_UNTRACKED[cls] or {})[name]
            if entry or engineRow then
                assertNil(reason, name .. " (" .. key
                    .. ") is tracked now -- its H7_UNTRACKED entry is stale: "
                    .. tostring(reason))
                n = n + 1
                if not entry then
                    assertTrue(type(row.cooldownMs) == "number"
                        and row.cooldownMs / 1000 >= Engine.MIN_COOLDOWN,
                        name .. " rides no cooldown the Engine's floor accepts")
                else
                    assertTrue(entry.duration > 0, name .. " (" .. key
                        .. ") rides no positive aura window the Registry's Build accepts")
                end
            else
                pinned = pinned + 1
                assertNotNil(reason, name .. " (" .. key
                    .. ") is in no engine and carries no pinned reason -- it is untracked by accident")
                local win = (tonumber(row.durationMs) or 0) > 0
                local engineFloor = type(row.cooldownMs) == "number"
                    and row.cooldownMs / 1000 >= Engine.MIN_COOLDOWN
                assertFalse(win, name .. " (" .. key
                    .. ") gained a Registry window -- re-read the row before editing H7_UNTRACKED")
                assertFalse(engineFloor, name .. " (" .. key
                    .. ") gained a CooldownEngine floor -- re-read the row before editing H7_UNTRACKED")
            end
            report[#report + 1] = string.format("%s %-22s id=%-9s %s%s", key, name,
                tostring(id),
                entry and string.format("dur=%dms", entry.duration)
                    or (engineRow and string.format("cd=%dms Engine-only (sub-second aura)",
                        row.cooldownMs))
                    or "NO WINDOW (pinned)",
                (not entry and not engineRow and reason) and (" -- " .. reason) or "")
        end
        print(string.format(
            "\n  [%s Wave I-3e H7 census: %d landed, %d engine-tracked, %d pinned]\n",
            key, #(H7_LANDED[cls] or {}), n, #(H7_LANDED[cls] or {}) - n))
    end
    for _, line in ipairs(report) do print("  " .. line) end
    -- Wave I-3e landed 12; the 2026-11-04 mage Clearcasting follow-up makes
    -- the census 13. Wave M3a: the rogue pair landed rows with values. Live
    -- 70862 store / review 2026-11-10: Deep Wounds left the Warrior data
    -- (-1) and Reckless Swings landed out of _deferred_H7 (+1), so the
    -- census stays 13, and with the Deep Wounds passive gone every one of
    -- the 13 is windowed: pinned 1 -> 0.
    assertEquals(13, total)
    assertEquals(0, pinned)
end)

test("the four Clearcasting rows stay on their own class (family law)",
function()
    -- "Clearcasting" is a FIVE-row name in this build's data: mage 12536
    -- (fam 3, the Arcane Concentration proc), druid 16870 (fam 7), shaman
    -- 16246 (fam 11), rogue 457342/467735 (fam 8). The generator resolves the
    -- NAME per class through the family-scoped rank law, so the mage list
    -- can not slide onto the druid row (and back). All three carried rows
    -- ride the same 15 000 ms caster-side window (base DurationMs + the
    -- 70707 store durationMs agree; the mage row is the one the uiforever
    -- Mage scenario measured live: spellId 12536, 15 s, applied, readable).
    -- The classic Holy-Concentration Clearcasting has NO priest row on this
    -- build (families 3/7/8/11 only, base + store) -- pinned absent so the
    -- day the data grows a family-6 row is a decision, not a silent drift.
    local pins = {
        { token = "DRUID",  id = 16870 },
        { token = "MAGE",   id = 12536 },
        { token = "SHAMAN", id = 16246 },
    }
    for _, p in ipairs(pins) do
        local key = dataKey(p.token)
        local data = FX.Data and FX.Data[key]
        assertNotNil(data, key .. "'s generated data did not load")
        local byName = FX.Data[key .. "ByName"]
        local id = byName and byName["Clearcasting"]
        assertEquals(p.id, id, key .. ": Clearcasting slid off its family row")
        local row = data[id]
        assertNotNil(row, key .. ": Clearcasting row missing at " .. tostring(id))
        assertEquals(15000, row.durationMs, key .. ": Clearcasting window moved")
        assertEquals(true, row.noTarget,
            key .. ": Clearcasting is not a caster-side aura")
        local reg = tracked(p.token)
        assertNotNil(reg, "no generated " .. key .. " data to build a registry on")
        local entry = reg["Clearcasting"]
        assertNotNil(entry, key .. ": Clearcasting has no Spell Timer row")
        assertTrue(entry.duration * 1000 == 15000,
            key .. ": the registry row is not the 15 s window")
    end
    assertNil(FX.Data.PriestByName and FX.Data.PriestByName["Clearcasting"],
        "a PRIEST Clearcasting row landed: the Holy-Concentration proc is on "
        .. "the client now -- add priest.json's name and re-read the data")
end)

-- Hand the registry back to the session's own class (the Forte_Timer
-- suites' restore pattern; run-tests leaves the registry built for the
-- profile class).
test("restore the registry to the profile class", function()
    Registry:AttachStorage(FX.db and FX.db.timer and FX.db.timer.learned or {})
    Registry:Build(FX._playerClass)
end)
