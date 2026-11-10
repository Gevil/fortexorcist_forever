-- addon/Forte_Cooldown/tests/test_items_live.lua
-- wow-ui-sim tests for the LIVE ITEM LAYER: the values the 2026-11-09/10 live
-- refresh put into the generated data (tools/item_lists/live_items.json,
-- docs/research/live-items-procs-2026-11-09.md) and the two generator laws it
-- forced (the class-variant merge, the proc ICD floor).
--
-- Same seams as tests/test_items.lua: `Items:Rescan(readers)` scripts the
-- whole inventory surface (the sim's item DB resolves names as "Unknown"),
-- matched against REAL Forte_Items data rows by NAME, and durations are read
-- as `cooldownMs / 1000` -> float, so numeric compares go through `near`.
-- Nothing here asserts a row count the stage-C re-pin owns; the pins below are
-- the live layer's own values (the three corrected trinket cooldowns, the
-- Counterattack Lodestone window, the added rows, the class-variant split).
--
-- Module state touched: FX._playerClass (restored), Engine storage (saved +
-- restored), the proc feature (switched on, switched back OFF). No framework
-- teardown exists, so the last test does it, the test_items.lua way.

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local Items = Engine.Items
local Procs = Engine.Procs

local realPlainOrNil = FX.Compat.PlainOrNil

local function freshStorage()
    Engine:AttachStorage({})
end

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

local savedLearned = Engine.learned
local originalClass = FX._playerClass
local function as(class) FX._playerClass = class end

--- The scripted inventory surface (the test_items.lua reader shape).
--- equipped = { [slot]=id }, names = { [id]=name }, bags = { [bag]={ids} }
local function readersFrom(spec)
    local bagSlots = spec.bags or {}
    return {
        getEquippedItemID = function(slot)
            return spec.equipped and spec.equipped[slot]
        end,
        getItemName = function(id)
            return spec.names and spec.names[id]
        end,
        getItemSpell = function(id)
            return spec.spells and spec.spells[id]
        end,
        getItemIcon = function(id)
            return spec.icons and spec.icons[id]
        end,
        numSlots = function(bag)
            local t = bagSlots[bag]
            return t and #t or 0
        end,
        getContainerItemID = function(bag, slot)
            local t = bagSlots[bag]
            return t and t[slot]
        end,
    }
end

local function hasData()
    return (FX.Data and FX.Data.Items) ~= nil
end

--- The generated row of an on-use item, found by id (never by position).
local function onUseRow(name, id)
    for _, row in ipairs(FX.Data.Items.onUse) do
        if row.itemId == id then return row end
    end
    return nil
end

local function countWhere(list, pred)
    local n = 0
    for _, row in ipairs(list) do
        if pred(row) then n = n + 1 end
    end
    return n
end

-- ------------------------------------------------- the corrected trinkets --

-- The three Forever trinkets mythicsim's items.jsonl carries at the GCD-ish
-- 90 s and the live client legs (wowsims db.json @ 1.60.1.70862, the live
-- report §1.1) carry at 300/360 s. The live layer overrides the pull.
local CORRECTED = {
    { name = "Adaptive Combat Assistant", id = 272437, cd = 300000 },
    { name = "Weakness Analyzer",        id = 272438, cd = 360000 },
    { name = "Serenity Field",           id = 272439, cd = 360000 },
}

test("the three re-picked trinkets carry the client cooldown, not the 90 s pull",
function()
    if not hasData() then return end
    freshStorage()
    as("HUNTER")
    for _, t in ipairs(CORRECTED) do
        local row = FX.Data.Items.OnUseByName[t.name]
        assertNotNil(row, t.name .. " has no on-use row")
        assertEquals(t.id, row.itemId)
        assertEquals(t.cd, row.cooldownMs,
            t.name .. " keeps the live client cooldown (live_items.json onUseOverride)")
    end
    -- Behaviour half: the tracker's bar length is that number, read through
    -- the real Rescan path with two trinkets equipped.
    local n = Items:Rescan(readersFrom({
        equipped = { [13] = 272437, [14] = 272438 },
        names = { [272437] = "Adaptive Combat Assistant",
                  [272438] = "Weakness Analyzer" },
    }))
    assertEquals(2, n)
    near(300, Items.tracked["Adaptive Combat Assistant"].baseDuration)
    near(360, Items.tracked["Weakness Analyzer"].baseDuration)
end)

test("Counterattack Lodestone's buff window is the spell-store 10 s, not 8 s",
function()
    if not hasData() then return end
    freshStorage()
    as("HUNTER")
    local row = FX.Data.Items.OnUseByName["Counterattack Lodestone"]
    assertNotNil(row)
    assertEquals(18537, row.itemId)
    -- The store's Magnetize aura is 10 s; the item-effect leg's 8000 was the
    -- pull's effect duration, so the live layer overrides durationMs only.
    assertEquals(10000, row.durationMs,
        "Magnetize (1302356) DurationMs = 10000 in the 70425 spell store")
    assertEquals(480000, row.cooldownMs, "the 480 s use cooldown is the pull's, untouched")
    Items:Rescan(readersFrom({
        equipped = { [13] = 18537 },
        names = { [18537] = "Counterattack Lodestone" },
    }))
    near(480, Items.tracked["Counterattack Lodestone"].baseDuration)
end)

-- ------------------------------------------------------- class variants ----

-- The 16+16 Insignia rows share ONE name, each with its own classAllowlist.
-- Core/Items.lua gates the ByName row on the player's class, so a plain
-- "lowest id wins" index hands every class the Warrior's row and filters the
-- other seven out. The generator's answer (gen_item_data.py, the class-variant
-- law): OnUseByName[name] is a merged row (union allowlist) and
-- OnUseByNameClass[name][ClassToken] is that class's own row.
local function classOf(token) return token:gsub("^Class", ""):upper() end

test("every class tracks its own Insignia, and an off-class Insignia is filtered",
function()
    if not hasData() then return end
    freshStorage()
    local perClass = FX.Data.Items.OnUseByNameClass
    assertNotNil(perClass, "the generator ships no class-variant index")
    for _, name in ipairs({ "Insignia of the Horde", "Insignia of the Alliance" }) do
        local byClass = perClass[name]
        assertNotNil(byClass, name .. " has no per-class rows")
        local merged = FX.Data.Items.OnUseByName[name]
        assertNotNil(merged)
        assertEquals(300000, merged.cooldownMs)
        local union, mergedSet = {}, {}
        for token, row in pairs(byClass) do
            assertNotNil(row, name .. ": " .. token .. " has no row")
            union[row.classAllowlist[1]] = true
            assertEquals(token, row.classAllowlist[1])
        end
        for _, cls in ipairs(merged.classAllowlist) do mergedSet[cls] = true end
        for token in pairs(union) do
            assertTrue(mergedSet[token] == true,
                name .. ": the merged row drops " .. token)
        end
        -- Behaviour half: as each class, that class's own trinket is found and
        -- tracked at 300 s (the Rescan reports the equipped id it read).
        for token, row in pairs(byClass) do
            as(classOf(token))
            local n = Items:Rescan(readersFrom({
                equipped = { [13] = row.itemId },
                names = { [row.itemId] = name },
            }))
            assertEquals(1, n, name .. " tracked as " .. token)
            local t = Items.tracked[name]
            assertNotNil(t, name .. " (" .. token .. ") is filtered out of tracking")
            assertEquals(row.itemId, t.itemId,
                name .. " (" .. token .. ") resolves to the wrong variant")
            near(row.cooldownMs / 1000, t.baseDuration)
        end
    end
    -- The filter still filters: the Alliance Insignia family has no Shaman
    -- row, so a Shaman carrying the lowest Alliance id tracks nothing.
    as("SHAMAN")
    assertEquals(0, Items:Rescan(readersFrom({
        equipped = { [13] = 18854 },
        names = { [18854] = "Insignia of the Alliance" },
    })), "a Shaman tracks the Alliance Insignia")
end)

-- ------------------------------------------------------------- shadowing --

-- Names are the runtime key, so an item row named like a class spell steals
-- the name slot in Engine.tracked (one entry per name). That is a bug ONLY for
-- a spell the engine actually tracks: the Warlock Healthstone-family rows are
-- the item use-spells and carry a shared category, no cooldownMs, so the
-- consumable row IS the tracker and the clash is inert.
local CLASS_DATA = { "Druid", "Hunter", "Mage", "Paladin",
                     "Priest", "Rogue", "Shaman", "Warlock", "Warrior" }

test("no item row shadows a class spell that carries a cooldown", function()
    if not hasData() then return end
    for _, key in ipairs(CLASS_DATA) do
        local data = FX.Data[key]
        if data then
            for _, spell in pairs(data) do
                if type(spell) == "table" and type(spell.cooldownMs) == "number" then
                    local item = FX.Data.Items.OnUseByName[spell.name]
                    assertNil(item,
                        (key .. ": the item row %q shadows the tracked spell (cooldownMs %d)")
                        :format(tostring(spell.name), spell.cooldownMs))
                end
            end
        end
    end
    -- The known inert half, pinned so a future cooldownMs on it is a flag, not
    -- a silent shadow: Healthstone is an item consumable AND a Warlock use-spell.
    local healthstone = nil
    for _, row in ipairs(FX.Data.Items.consumables) do
        if row.name == "Healthstone" and row.itemId == 5509 then healthstone = row end
    end
    assertNotNil(healthstone, "the 5509 Healthstone consumable row is gone")
    assertEquals(1153, healthstone.categoryId)
    if FX.Data.Warlock then
        local byName = FX.Data.WarlockByName
        local id = byName and byName["Healthstone"]
        if id then
            assertNil(FX.Data.Warlock[id].cooldownMs,
                "the Warlock Healthstone row gained a cooldownMs: the name clash is live now")
        end
    end
end)

-- ------------------------------------------------------------ consumables --

-- The added consumable rows, one per added group, pinned at their category.
-- The tracker's floor is Items.MIN_CATEGORY_CD (60 s): the 1-3 s rows are the
-- elixir/flask GCD band and stay out of the data.
local ADDED_POTS = {
    { name = "Healing Potion",       id = 929,      s = 120, cat = 4 },
    { name = "Healthstone",          id = 5509,     s = 120, cat = 1153 },
    { name = "Heavy Dynamite",       id = 4378,     s = 60,  cat = 24 },
    { name = "Swiftfeather Token",   id = 1400,     s = 300, cat = 28 },
    { name = "Major Healing Draught", id = 17348,   s = 300, cat = 4 },
    { name = "Distilled Firewater",  id = 246948,   s = 60,  cat = nil },
}

test("the added consumables track on their shared category cooldown", function()
    if not hasData() then return end
    freshStorage()
    as("HUNTER")
    local names, bag = {}, {}
    for _, p in ipairs(ADDED_POTS) do
        names[p.id] = p.name
        bag[#bag + 1] = p.id
    end
    assertEquals(#ADDED_POTS, Items:Rescan(readersFrom({
        names = names, bags = { [0] = bag },
        spells = { [929] = "Healing Potion" }, -- the use-spell seam
    })))
    for _, p in ipairs(ADDED_POTS) do
        local t = Items.tracked[p.name]
        assertNotNil(t, p.name .. " is not tracked")
        assertEquals("potion", t.kind)
        assertEquals("Potion", t.category)
        assertEquals(p.id, t.itemId)
        near(p.s, t.baseDuration, p.name .. " rides its category length")
        assertEquals(p.cat, t.categoryId, p.name .. " carries the wrong category id")
    end
    -- The shared-category law lives in OnCastBySpellName (Items:OnCast's doc:
    -- "shared-category siblings are the caller's business"), and the cast
    -- event names the USE SPELL, not the item. categoryId 4 is shared by the
    -- 120 s potion and the 300 s draught; each runs its OWN length.
    local e = Items:OnCastBySpellName("Healing Potion", 5000)
    assertNotNil(e, "the use spell resolved to no tracked item")
    near(5000 + 120, Engine.entries["Healing Potion"].endTime)
    near(5000 + 300, Engine.entries["Major Healing Draught"].endTime)
    assertNil(Engine.entries["Healthstone"], "a healthstone is not the potion family")
    for _, p in ipairs(ADDED_POTS) do Engine.entries[p.name] = nil end
end)

-- The data SHIPS the GCD-band rows (the elixir/flask slot cooldowns of the
-- Classic data); `Items.MIN_CATEGORY_CD` (60 s) is what keeps them off the
-- bars. A census count of them drifts with every data pull, so the lock is the
-- behaviour: none of them is trackable. (The added rows' own floors are pinned
-- by the ADDED_POTS lengths above, all >= 60 s.)
test("every GCD-band consumable in the data stays untracked", function()
    if not hasData() then return end
    freshStorage()
    as("HUNTER")
    local names, bag, seen = {}, {}, {}
    for _, row in ipairs(FX.Data.Items.consumables) do
        local cd = row.categoryCooldownMs
        -- The OnUseByName guard: a bag item whose name is ALSO an on-use row
        -- falls through to the on-use branch (its own, real cooldown), which
        -- is that row's business, not the category floor's.
        if type(cd) == "number" and cd / 1000 < Items.MIN_CATEGORY_CD
            and row.name and not FX.Data.Items.OnUseByName[row.name]
            and not seen[row.itemId] then
            seen[row.itemId] = true
            names[row.itemId] = row.name
            bag[#bag + 1] = row.itemId
        end
    end
    assertTrue(#bag > 0, "the data carries no GCD-band consumable to filter")
    assertEquals(0, Items:Rescan(readersFrom({ names = names, bags = { [0] = bag } })),
        "a sub-60 s category consumable reached the bars")
end)

-- Hearthstone is the one consumable the report says to leave out UNLESS the
-- chosen source carries a cooldown: the pinned legs carry none.
test("Hearthstone stays out; the healthstone family is in", function()
    if not hasData() then return end
    assertNil(FX.Data.Items.OnUseByName["Hearthstone"])
    assertEquals(0, countWhere(FX.Data.Items.consumables, function(r)
        return r.name == "Hearthstone" end))
    assertEquals(0, countWhere(FX.Data.Items.onUse, function(r)
        return r.name == "Hearthstone" end))
    for _, n in ipairs({ "Healthstone", "Lesser Healthstone", "Major Healthstone" }) do
        assertTrue(countWhere(FX.Data.Items.consumables, function(r)
            return r.name == n end) > 0, n .. " is missing from the healthstone family")
    end
end)

-- ------------------------------------------- the added on-use items -------

-- Twelve on-use items the pull's item leg omits. Three of them (the two
-- Deflectors, Goblin Sapper Charge) are consumables in the source data but
-- carry an ITEM cooldown and no shared category, and the consumable path
-- tracks categories only (Core/Items.lua's categoryDurationS), so they ride the
-- on-use path. The 120 s Flash Bundle is the proof of the inverse: a real
-- category row stays on the consumable path.
local ADDED_ONUSE = {
    { name = "Behemoth Bones",            id = 280065,  s = 300 },
    { name = "Emblem of Slamming",        id = 275009,  s = 900 },
    { name = "Escape Plan",               id = 287026,  s = 900 },
    { name = "Flame Deflector",           id = 4376,    s = 900 },
    { name = "Flamebreak Talisman",       id = 280071,  s = 300 },
    { name = "Goblin Sapper Charge",      id = 10646,   s = 300 },
    { name = "Ice Deflector",             id = 4386,    s = 900 },
    { name = "Lucky Shovelnose Tuft",     id = 280060,  s = 300 },
    { name = "Scalding Flamehoof",        id = 280074,  s = 300 },
    { name = "Serpentbane Crown",         id = 274609,  s = 300 },
    { name = "Shen'dralar Relic",         id = 277559,  s = 420 },
    { name = "Theka's Last Breath",       id = 274641,  s = 420 },
}

test("the twelve added on-use items are complete rows and all track", function()
    if not hasData() then return end
    freshStorage()
    as("HUNTER")
    local names, bag = {}, {}
    for _, t in ipairs(ADDED_ONUSE) do
        local row = onUseRow(t.name, t.id)
        assertNotNil(row, t.name .. " is not in data.onUse")
        assertEquals("cooldown", row.trackable)
        assertEquals(t.s * 1000, row.cooldownMs)
        assertEquals(0, countWhere(FX.Data.Items.consumables, function(r)
            return r.itemId == t.id end), t.name .. " is on both tracking paths")
        names[t.id] = t.name
        bag[#bag + 1] = t.id
    end
    local n = Items:Rescan(readersFrom({ names = names, bags = { [0] = bag } }))
    assertEquals(#ADDED_ONUSE, n, "not every added on-use item is tracked")
    for _, t in ipairs(ADDED_ONUSE) do
        local tr = Items.tracked[t.name]
        assertNotNil(tr, t.name .. " is not tracked")
        assertEquals("item", tr.kind)
        near(t.s, tr.baseDuration)
    end
    -- The inverse of that split, pinned: the 120 s Flash Bundle IS a category
    -- row, so it stays on the consumable path and off the on-use one.
    assertTrue(countWhere(FX.Data.Items.consumables, function(r)
        return r.itemId == 1127 end) > 0, "the Flash Bundle consumable row is gone")
    assertNil(FX.Data.Items.OnUseByName["Flash Bundle"],
        "the Flash Bundle moved onto the on-use path")
end)

-- ------------------------------------------------------------- proc rows --

test("Fist of Stone: the droppable 17943 row wins the name index", function()
    local procs = FX.Data and FX.Data.ItemProcs
    if not procs then
        print("[skip] ForteXorcist.Data.ItemProcs not loaded")
        return
    end
    local picked = procs.ProcsByName["Fist of Stone"]
    assertNotNil(picked)
    assertEquals(17943, picked.itemId,
        "the name index fell back to the lowest id, the undroppable 17733")
    assertEquals(1294794, picked.buffId)
    local both = countWhere(procs.procs, function(r)
        return r.name == "Fist of Stone" end)
    assertEquals(2, both, "both Fist of Stone rows must stay in the list")
    assertNotNil(procs.ProcsByBuffName["Fist of Stone (21951)"], "17733's own aura index")
    assertNotNil(procs.ProcsByBuffName["Fist of Stone (1294794)"], "17943's own aura index")
    -- The buff-name shadow the layer documents: four items share the aura name
    -- "Lightning Bolt (13959)" and ProcsByBuffName keeps ONE row per buff name.
    local shared = procs.ProcsByBuffNameAll["Lightning Bolt (13959)"]
    assertNotNil(shared, "the shared buff-name index dropped Lightning Bolt (13959)")
    assertEquals(4, #shared, "ProcsByBuffNameAll lost a shadowed Lightning Bolt row")
end)

-- ------------------------------------------------------------- sub-second --

-- 33 of the 51 ICD rows are 10/100/200 ms debounces (Searing Dagger's tooltip
-- reads "10ms cooldown"), not cooldowns. Engine.MIN_COOLDOWN (2.99 by default)
-- drops them, and Procs.MIN_ICD (1 s) keeps them out when the user lowers
-- IgnoreShort on the Options page.
test("sub-second ICD rows never reach the watched set, even at IgnoreShort 0",
function()
    if not (FX.Data and FX.Data.ItemProcs) then
        print("[skip] ForteXorcist.Data.ItemProcs not loaded")
        return
    end
    assertEquals("number", type(Procs.MIN_ICD))
    assertEquals(1, Procs.MIN_ICD)
    local subSecond = 0
    for _, row in ipairs(FX.Data.ItemProcs.procs) do
        if type(row.icdMs) == "number" and type(row.buffId) == "number"
            and row.icdMs / 1000 < Procs.MIN_ICD then
            subSecond = subSecond + 1
        end
    end
    assertTrue(subSecond > 0, "the data has no sub-second ICD row to filter")

    if not Procs:IsEnabled() then Procs:SetEnabled(true) end
    assertTrue(Procs:IsEnabled(), "the proc feature will not switch on")
    local realMin = Engine.MIN_COOLDOWN
    Engine.MIN_COOLDOWN = 0 -- the Options page's lowest IgnoreShort
    Procs:Build()
    -- Why a proc sharing a class spell's NAME (the 2824 Hurricane is a Druid
    -- spell name) is inert: a watched key is `name#buffId`, never the bare
    -- name, so it can never take a spell's Engine.tracked slot.
    for key in pairs(Procs.tracked) do
        assertTrue(key:find("#", 1, true) ~= nil,
            "a watched proc key is the bare name: " .. tostring(key))
    end
    for _, t in pairs(Procs.tracked) do
        assertTrue(t.icd >= Procs.MIN_ICD,
            ("%s (%s) is watched at %s s, under the proc floor")
            :format(tostring(t.name), tostring(t.buffId), tostring(t.icd)))
    end
    for _, row in ipairs(FX.Data.ItemProcs.procs) do
        if type(row.icdMs) == "number" and type(row.buffId) == "number"
            and row.icdMs / 1000 < Procs.MIN_ICD then
            assertNil(Procs.tracked[row.name .. "#" .. row.buffId],
                (row.name .. "'s sub-second debounce is watched"))
        end
    end
    -- A 1 s row is NOT a debounce: Unbalanced Idol (1000 ms) stays eligible.
    Engine.MIN_COOLDOWN = realMin
    Procs:Build()
end)

-- ----------------------------------------------------------- restore ----

-- Module state for every later file (the framework has no teardown): the proc
-- feature back OFF (its default), no proc windows left armed, the class and
-- the learned-duration store as they were.
test("restore module state", function()
    for key in pairs(Procs.tracked) do Engine.entries[key] = nil end
    Procs:SetEnabled(false)
    assertFalse(Procs:IsEnabled())
    FX._playerClass = originalClass
    Engine:AttachStorage(savedLearned)
    FX.Compat.PlainOrNil = realPlainOrNil
    Items:Rescan() -- live seams + live data: the module's own view again
    if FX.db and FX.db.cooldownLearned then
        Engine:AttachStorage(FX.db.cooldownLearned)
    end
    assertEquals(true, true)
end)
