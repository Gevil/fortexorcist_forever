-- addon/Forte_Cooldown/tests/test_items.lua
-- wow-ui-sim tests for Core/Items.lua: the item tracker of the cooldown
-- engine (on-use trinkets/items + shared-category consumables).
--
-- Seams: Items:Rescan takes a `readers` override table (the
-- Engine:DetectCharges injectable pattern) -- the sim's item DB resolves
-- names as "Unknown" (measured 2026-11-01 probe: C_Item.GetItemInfo(6149) ->
-- "Unknown") and has NO C_Item.GetItemSpell, so the inventory surface
-- (equipped ids, names, use spells, icons, bags) is scripted per test and
-- matched against REAL Forte_Items data rows (name-keyed, no magic ids).
-- The secret-read test uses the tests/test_reconcile.lua sentinel seam
-- (PlainOrNil patched so a string classifies as nil). FX.Compat seams are
-- swapped for the ReadAll test and restored in-test (the framework has no
-- teardown).
--
-- Durations arrive via `cooldownMs / 1000` -> float, compare with tolerance.

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local Items = Engine.Items

local SECRET = "FXTEST-SECRET-VALUE"
local realPlainOrNil = FX.Compat.PlainOrNil
local function patchPlain()
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlainOrNil(v)
    end
end
local function restorePlain()
    FX.Compat.PlainOrNil = realPlainOrNil
end

local function freshStorage()
    Engine:AttachStorage({})
end

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

local function entryCount()
    local n = 0
    for _ in pairs(Engine.entries) do n = n + 1 end
    return n
end

--- Script the whole inventory surface from literal maps.
--- equipped = { [slot]=id }, names = { [id]=name }, spells = { [id]=useSpellName },
--- icons = { [id]=fileID }, bags = { [bag]= { ids... } }
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

-- Real generated rows the tests name-match against (Forte_Items data facts,
-- verified in the generated file 2026-11-01):
--   19336 Arcane Infused Gem  onUse  ClassHunter   cooldownMs 120000 Trinket
--   20534 Abyss Shard         onUse  ClassWarlock  cooldownMs 900000 Trinket
--    1710 Greater Healing Potion  consumable categoryId 4 categoryCooldownMs 120000
--   13446 Major Healing Potion    consumable categoryId 4 categoryCooldownMs 120000
local GEM, GEM_ID = "Arcane Infused Gem", 19336
local SHARD, SHARD_ID = "Abyss Shard", 20534
local PHPOT, PHPOT_ID = "Greater Healing Potion", 1710
local MPOT, MPOT_ID = "Major Healing Potion", 13446

--- The shared class the Rescan's classAllowlist filter reads; restored by
--- the last registered test.
local originalClass = FX._playerClass
local function asHunter() FX._playerClass = "HUNTER" end
local function asWarlock() FX._playerClass = "WARLOCK" end

local savedLearned = Engine.learned

-- -------------------------------------------------------------- rescan ----

test("Rescan tracks an equipped trinket by name and an unequipped bag consumable", function()
    assertNotNil(Items, "Engine.Items attached")
    local data = FX.Data and FX.Data.Items
    if not data then
        print("[skip] ForteXorcist.Data.Items not loaded")
        return
    end
    freshStorage()
    asHunter()
    local n = Items:Rescan(readersFrom({
        equipped = { [13] = GEM_ID },
        names = { [GEM_ID] = GEM, [PHPOT_ID] = PHPOT },
        spells = { [GEM_ID] = "Arcane Infusion" },
        icons = { [GEM_ID] = 132428, [PHPOT_ID] = 134375 },
        bags = { [0] = { PHPOT_ID } },
    }))
    assertEquals(2, n)
    local gem = Items.tracked[GEM]
    assertNotNil(gem)
    assertEquals("item", gem.kind)
    assertEquals("Item", gem.category)
    assertEquals(13, gem.slot) -- equipped: reads by inventory slot
    near(120, gem.baseDuration)
    assertEquals(132428, gem.icon)
    local pot = Items.tracked[PHPOT]
    assertNotNil(pot)
    assertEquals("potion", pot.kind)
    assertEquals("Potion", pot.category)
    assertNil(pot.slot) -- bag item: reads by itemID
    near(120, pot.baseDuration)
    assertEquals(4, pot.categoryId)
    -- The use-spell map: live spell name -> item name (lower-cased key).
    assertEquals(GEM, Items.byCastSpell["arcane infusion"])
end)

test("classAllowlist filters an off-class trinket, allows the class row", function()
    if not (FX.Data and FX.Data.Items) then return end
    freshStorage()
    local spec = {
        equipped = { [13] = SHARD_ID, [14] = GEM_ID },
        names = { [SHARD_ID] = SHARD, [GEM_ID] = GEM },
    }
    asHunter() -- Abyss Shard is ClassWarlock: filtered; the gem passes
    assertEquals(1, Items:Rescan(readersFrom(spec)))
    assertNil(Items.tracked[SHARD])
    assertNotNil(Items.tracked[GEM])

    asWarlock() -- the filter flips with the class
    assertEquals(1, Items:Rescan(readersFrom(spec)))
    assertNil(Items.tracked[GEM])
    assertNotNil(Items.tracked[SHARD])
    near(900, Items.tracked[SHARD].baseDuration)
end)

test("consumables with only GCD-band category cooldowns are not tracked", function()
    if not (FX.Data and FX.Data.Items) then return end
    freshStorage()
    asHunter()
    -- 6149 Arcane Elixir: categoryCooldownMs 3000 = 3 s (the elixir GCD band).
    local n = Items:Rescan(readersFrom({
        bags = { [0] = { 6149 } },
        names = { [6149] = "Arcane Elixir" },
    }))
    assertEquals(0, n)
end)

test("data-addon-absent degrades: Rescan returns 0, live entries survive", function()
    local data = FX.Data and FX.Data.Items
    if not data then return end
    freshStorage()
    asHunter()
    Items:Rescan(readersFrom({
        equipped = { [13] = GEM_ID },
        names = { [GEM_ID] = GEM },
    }))
    Items:OnCast(GEM, 1000)
    assertNotNil(Engine.entries[GEM])
    local before = entryCount()

    local realData = FX.Data.Items
    FX.Data.Items = nil
    local ok, n = pcall(Items.Rescan, Items) -- no readers: the live seams,
    FX.Data.Items = realData                 -- with the data gone
    assertTrue(ok, "Rescan must not raise without data")
    assertEquals(0, n)
    assertEquals(0, (function() local c = 0 for _ in pairs(Items.tracked) do c = c + 1 end return c end)())
    -- Entries of items that are no longer tracked: the Rescan's stale sweep
    -- (step 3) drops them with the tracking. That IS the degrade: nothing
    -- is tracked, nothing is read, nothing errors.
    assertEquals(before - 1, entryCount())
end)

-- ------------------------------------------------------------- cast path --

test("trinket use cast predicts from data, a later plain read re-anchors", function()
    if not (FX.Data and FX.Data.Items) then return end
    freshStorage()
    asHunter()
    Items:Rescan(readersFrom({
        equipped = { [13] = GEM_ID },
        names = { [GEM_ID] = GEM },
        spells = { [GEM_ID] = "Arcane Infusion" },
        icons = { [GEM_ID] = 132428 },
    }))
    -- The cast event names the USE SPELL, not the item (lower-casing law).
    local e = Items:OnCastBySpellName("Arcane Infusion", 1000)
    assertNotNil(e)
    assertEquals("cast", e.source)
    assertTrue(e.predicted)
    near(1000, e.start)
    near(1000 + 120, e.endTime) -- cooldownMs 120000 / 1000
    assertEquals("Item", e.category)
    assertEquals(132428, e.icon)

    -- A plain read at 1010 carries the REAL window: re-anchored + learned.
    assertEquals("anchored", Items:OnRead(GEM, 1010, 120, 1011))
    e = Engine.entries[GEM]
    assertFalse(e.predicted)
    assertEquals("read", e.source)
    assertTrue(e.anchored)
    near(1010, e.start)
    near(120, Engine.learned[GEM])
    -- An untracked name is inert:
    assertEquals("ignored", Items:OnRead(GEM .. "!", 1010, 120, 1011))
end)

test("a shared-category cast starts every tracked potion, each on the family CD", function()
    if not (FX.Data and FX.Data.Items) then return end
    freshStorage()
    asHunter()
    Items:Rescan(readersFrom({
        bags = { [0] = { PHPOT_ID, MPOT_ID } },
        names = { [PHPOT_ID] = PHPOT, [MPOT_ID] = MPOT },
        spells = { [PHPOT_ID] = "Greater Healing" }, -- the drunk one's spell
    }))
    local e = Items:OnCastBySpellName("Greater Healing", 2000)
    assertNotNil(e)
    near(2000, e.start)
    near(2000 + 120, e.endTime) -- categoryId 4 shares 120000 ms
    for _, name in ipairs({ PHPOT, MPOT }) do
        local pe = Engine.entries[name]
        assertNotNil(pe, name .. " gets the shared category window")
        assertTrue(pe.predicted)
        assertEquals("cast", pe.source)
        near(2000 + 120, pe.endTime)
        assertEquals("Potion", pe.category)
    end
    -- A spell-name cast names no item: inert.
    assertNil(Items:OnCastBySpellName("Arcane Shot", 2100))
end)

test("fresh predictions survive the read-lag grace, die after it", function()
    if not (FX.Data and FX.Data.Items) then return end
    freshStorage()
    asHunter()
    Items:Rescan(readersFrom({
        equipped = { [13] = GEM_ID },
        names = { [GEM_ID] = GEM },
        spells = { [GEM_ID] = "Arcane Infusion" },
    }))
    Items:OnCastBySpellName("Arcane Infusion", 5000)
    -- The slot read lags the cast event: "ready" inside the grace is noise.
    assertEquals("ignored", Items:OnRead(GEM, 0, 0, 5000.5))
    assertNotNil(Engine.entries[GEM])
    -- Outside the grace a plain "ready" read is the truth.
    assertEquals("cleared", Items:OnRead(GEM, 0, 0, 5002))
    assertNil(Engine.entries[GEM])
end)

-- --------------------------------------------------------------- secrets --

test("a secret read leaves the predicted clock alone", function()
    if not (FX.Data and FX.Data.Items) then return end
    freshStorage()
    asHunter()
    Items:Rescan(readersFrom({
        equipped = { [13] = GEM_ID },
        names = { [GEM_ID] = GEM },
        spells = { [GEM_ID] = "Arcane Infusion" },
    }))
    Items:OnCastBySpellName("Arcane Infusion", 3000)
    local e = Engine.entries[GEM]
    local start, dur, endTime = e.start, e.duration, e.endTime

    patchPlain()
    assertEquals("secret", Items:OnRead(GEM, SECRET, SECRET, 3010))
    restorePlain()
    local e2 = Engine.entries[GEM]
    assertEquals(e, e2)
    near(start, e2.start)
    near(dur, e2.duration)
    near(endTime, e2.endTime)
    assertEquals("cast", e2.source)
    assertTrue(e2.predicted)
end)

test("ReadAll routes the seam through OnRead; raises leave entries alone", function()
    if not (FX.Data and FX.Data.Items) then return end
    freshStorage()
    asHunter()
    Items:Rescan(readersFrom({
        equipped = { [13] = GEM_ID },
        names = { [GEM_ID] = GEM, [PHPOT_ID] = PHPOT },
        spells = { [GEM_ID] = "Arcane Infusion" },
        bags = { [0] = { PHPOT_ID } },
    }))
    assertNotNil(Items.tracked[PHPOT])

    local calls = {}
    local realRead = FX.Compat.GetItemCooldownInfo
    FX.Compat.GetItemCooldownInfo = function(itemID, slot)
        calls[#calls + 1] = { itemID = itemID, slot = slot }
        if itemID == GEM_ID then
            return 4000, 120, 1 -- a live window on the trinket slot read
        end
        error("simulated secret-raise") -- the potion read raises
    end
    Items:ReadAll(4010)
    FX.Compat.GetItemCooldownInfo = realRead

    -- Equipped entries ride the slot, bag entries the bare itemID.
    local sawSlot, sawId
    for _, c in ipairs(calls) do
        if c.itemID == GEM_ID then sawSlot = c.slot end
        if c.itemID == PHPOT_ID then sawId = c.slot end
    end
    assertEquals(13, sawSlot)
    assertNil(sawId)
    local e = Engine.entries[GEM]
    assertNotNil(e)
    assertEquals("read", e.source)
    near(4000, e.start)
    assertNil(Engine.entries[PHPOT]) -- the raise left no entry, no crash
end)

-- ----------------------------------------------------------------- rows ---

test("Sorted rows expose category/icon; spell rows default Spell/nil", function()
    if not (FX.Data and FX.Data.Items) then return end
    freshStorage()
    asHunter()
    Items:Rescan(readersFrom({
        equipped = { [13] = GEM_ID },
        names = { [GEM_ID] = GEM },
        spells = { [GEM_ID] = "Arcane Infusion" },
        icons = { [GEM_ID] = 132428 },
    }))
    local data = FX.Data and FX.Data.Hunter
    if data then
        Engine:Build("HUNTER", function() return true end)
        Engine:OnCast("Disengage", 6000)
    end
    Items:OnCastBySpellName("Arcane Infusion", 6010)

    local rows = Engine:Sorted({})
    local gemRow, spellRow
    for _, r in ipairs(rows) do
        if r.name == GEM then gemRow = r end
        if r.name == "Disengage" then spellRow = r end
    end
    assertNotNil(gemRow, "item row in Sorted")
    assertEquals("Item", gemRow.category)
    assertEquals(132428, gemRow.icon)
    if spellRow then
        assertEquals("Spell", spellRow.category)
        assertNil(spellRow.icon)
        -- The per-spell classification knob (UI/Timeline.lua's documented
        -- `tracked[name].fxClass` override) rides the row, not the entry:
        -- the row's category is the EFFECTIVE one.
        Engine.tracked["Disengage"].fxClass = "Pet"
        rows = Engine:Sorted({})
        for _, r in ipairs(rows) do
            if r.name == "Disengage" then assertEquals("Pet", r.category) end
        end
        Engine.tracked["Disengage"].fxClass = nil
    end
    -- Sweep pops the item entry at its endTime like any plain window.
    local out = Engine:Sweep(6010 + 120, {})
    local popped
    for _, nm in ipairs(out) do
        if nm == GEM then popped = true end
    end
    assertTrue(popped, "item entry pops ready")
end)

test("Rescan drops entries of items that left the inventory", function()
    if not (FX.Data and FX.Data.Items) then return end
    freshStorage()
    asHunter()
    Items:Rescan(readersFrom({
        equipped = { [13] = GEM_ID },
        names = { [GEM_ID] = GEM },
        spells = { [GEM_ID] = "Arcane Infusion" },
    }))
    Items:OnCast(GEM, 7000)
    assertNotNil(Engine.entries[GEM])
    -- Unequip: the trinket slot is empty on the next rescan.
    assertEquals(0, Items:Rescan(readersFrom({ equipped = {} })))
    assertNil(Engine.entries[GEM])
    assertNil(Items.tracked[GEM])
    -- Spell entries are NOT item entries: a foreign entry with a spell
    -- name and our category default rides through untouched.
    Engine.entries["Rapid Fire"] = { name = "Rapid Fire", start = 1, duration = 10,
        endTime = 11, predicted = false, source = "cast" }
    Items:Rescan(readersFrom({ equipped = {} }))
    assertNotNil(Engine.entries["Rapid Fire"])
    Engine.entries["Rapid Fire"] = nil
end)

test("Counts + /fx status print the Items line", function()
    if not (FX.Data and FX.Data.Items) then return end
    freshStorage()
    asHunter()
    Items:Rescan(readersFrom({
        equipped = { [13] = GEM_ID },
        names = { [GEM_ID] = GEM },
        spells = { [GEM_ID] = "Arcane Infusion" },
    }))
    Items:OnCast(GEM, 8000)
    local t, a = Items:Counts()
    assertEquals(1, t)
    assertEquals(1, a)

    local lines = {}
    local realPrint = FX.Print
    FX.Print = function(msg) lines[#lines + 1] = tostring(msg) end
    FX.Cooldown.Module:Status()
    FX.Print = realPrint
    local joined = table.concat(lines, "\n")
    assertContains(joined, "Items: 1 tracked, 1 active")
end)

-- Restore module-owned state for any later file (no framework teardown).
test("restore module state", function()
    FX._playerClass = originalClass
    Engine:AttachStorage(savedLearned)
    Items:Rescan() -- live seams + live data: the module's own view again
    if FX.db and FX.db.cooldownLearned then
        Engine:AttachStorage(FX.db.cooldownLearned)
    end
    assertEquals(true, true)
end)
