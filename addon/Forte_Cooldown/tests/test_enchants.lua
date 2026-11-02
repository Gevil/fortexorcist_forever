-- addon/Forte_Cooldown/tests/test_enchants.lua
-- wow-ui-sim tests for Core/Enchants.lua: the weapon-enchant tracker
-- (one Engine.entries entry per enchanted weapon slot, category "Buff",
-- C_Item.GetWeaponEnchantInfo + WEAPON_ENCHANT_CHANGED, owner ruling
-- PLAN §9/§10.C-3).
--
-- Seams: Enchants:ReadAll(now, readers) takes { read = fn(weaponSlot),
-- getName = fn(enchantID), getTexture = fn(unit, invSlot), getEquippedID,
-- getIcon } -- the Items:Rescan(readers) pattern. The sim's weapon-enchant
-- answers are empty scripted facts, so every read is a literal map keyed
-- by the catalog's Enum.WeaponSlot ids (MainHand 0 / OffHand 1 / Ranged 2);
-- production seams ride FX.Compat. The secret-read tests use the
-- tests/test_reconcile.lua sentinel (PlainOrNil patched so a string
-- classifies as nil). Event dispatch = the module frame's own OnEvent
-- handler (test_tiers pattern) -- WEAPON_ENCHANT_CHANGED registration is
-- proven by the clean load (an unknown event raises at RegisterEvent).
--
-- The Forte_Items data fact the name-fallback test rides (generated file,
-- procs): { name = "Enchant Weapon - Crusader", itemId = 1900,
-- source = "enchant" } -- itemId IS the effect_id (file header).
--
-- Time discipline: synthetic frame times (1000, ...), the sim's GetTime()
-- is far below them; float durations compare with tolerance.

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local Enchants = Engine.Enchants

local MH, OH, RH = 0, 1, 2 -- Enum.WeaponSlot (pinned catalog values)
local MH_LABEL, OH_LABEL = "Main Hand Enchant", "Off Hand Enchant"

-- The Engine.entries KEY of a slot entry (Core/Enchants.lua key law, n3):
-- the display name plus the slot; `e.name` stays the bare display name.
local function keyOf(name, slotKey) return name .. "#" .. slotKey end
local MH_KEY = keyOf(MH_LABEL, "MainHand")
local OH_KEY = keyOf(OH_LABEL, "OffHand")

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

local savedLearned = Engine.learned
local function freshStorage()
    Engine:AttachStorage({})
end

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

local function clearEnchants()
    for _, st in pairs(Enchants.bySlot) do
        if st.entryKey then Engine.entries[st.entryKey] = nil end
    end
    wipe(Enchants.bySlot)
    wipe(Enchants.names)
end

--- readers over literal slot maps: infos = { [slot] = info-table }.
local function readersFrom(spec)
    local infos = spec.infos or {}
    local names = spec.names -- [enchantID] = name | nil (resolves nothing)
    return {
        read = function(slot)
            return infos[slot]
        end,
        getName = names and function(id) return names[id] end
            or function() return nil end,
        getTexture = function(unit, invSlot)
            local t = spec.textures
            return t and t[invSlot]
        end,
        getEquippedID = spec.itemIDs and function(invSlot)
            return spec.itemIDs[invSlot]
        end or nil,
        getIcon = spec.icons and function(itemID)
            return spec.icons[itemID]
        end or nil,
    }
end

-- ---------------------------------------------------------------- attach --

test("Engine.Enchants attached with the public surface", function()
    assertNotNil(Enchants, "Engine.Enchants set by Core/Enchants.lua")
    assertEquals("function", type(Enchants.ReadAll))
    assertEquals("function", type(Enchants.OnReadSlot))
    assertEquals("function", type(Enchants.Count))
    assertEquals("function", type(Enchants.ResolveName))
end)

-- ------------------------------------------------------------ appear -----

test("an enchanted main hand appears: label name, Buff category, endTime = now + timeLeft/1000, weapon icon", function()
    freshStorage()
    clearEnchants()
    Enchants:ReadAll(1000, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 1200000,
            charges = 0, enchantID = 999999, enchantIconID = 0 } },
        textures = { [16] = 137542 },
    }))
    local e = Engine.entries[MH_KEY]
    assertNotNil(e, "entry under the main-hand label (no name resolves 999999)")
    assertEquals("Buff", e.category)
    near(1000, e.start)
    near(1200, e.duration) -- 1200000 ms / 1000 (BuffFrame.lua:775 law)
    near(2200, e.endTime)
    assertFalse(e.predicted)
    assertEquals("read", e.source)
    assertTrue(e.anchored)
    assertEquals(137542, e.icon) -- the WEAPON's texture (GetInventoryItemTexture seam)
    assertEquals(1, Enchants:Count())
    -- The Sorted row carries the tags the Timeline draws.
    local row
    for _, r in ipairs(Engine:Sorted({})) do
        if r.name == MH_LABEL then row = r end
    end
    assertNotNil(row, "row in Engine:Sorted")
    assertEquals("Buff", row.category)
    assertEquals(137542, row.icon)
    clearEnchants()
end)

test("the enchantID resolves to the spell row, else the Forte_Items enchant row, else the label", function()
    freshStorage()
    clearEnchants()
    -- 1. C_Spell-shaped seam wins.
    Enchants:ReadAll(1000, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 600000,
            charges = 0, enchantID = 1900 } },
        names = { [1900] = "Enchant Weapon - Windfury" },
    }))
    assertNotNil(Engine.entries[keyOf("Enchant Weapon - Windfury", "MainHand")])
    assertNil(Engine.entries[MH_KEY])
    clearEnchants()

    -- 2. No spell name: the generated Forte_Items procs row by effect_id
    --    (the data ships it; itemId 1900 == the classic enchant spell id).
    local procs = FX.Data and FX.Data.Items
        and (FX.Data.Items.enchantProcs or FX.Data.Items.procs)
    if procs then
        local has
        for _, row in ipairs(procs) do
            if row.source == "enchant" and row.itemId == 1900 then has = row.name end
        end
        if has then
            Enchants:ReadAll(1000, readersFrom({
                infos = { [MH] = { hasEnchant = true, timeLeft = 600000,
                    charges = 0, enchantID = 1900 } },
            }))
            assertNotNil(Engine.entries[keyOf(has, "MainHand")],
                "Forte_Items enchant row names the entry")
            clearEnchants()
        end
    end

    -- 3. Nothing resolves: the slot label.
    Enchants:ReadAll(1000, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 600000,
            charges = 0, enchantID = 999999 } },
    }))
    assertNotNil(Engine.entries[MH_KEY])
    clearEnchants()
end)

-- ------------------------------------------------------------ re-anchor --

test("a plain re-read re-anchors the same entry key", function()
    freshStorage()
    clearEnchants()
    local info = { hasEnchant = true, timeLeft = 1200000, charges = 0,
        enchantID = 999999 }
    local r = readersFrom({ infos = { [MH] = info }, textures = { [16] = 137542 } })
    Enchants:ReadAll(1000, r)
    local e = Engine.entries[MH_KEY]
    near(2200, e.endTime)
    -- 10 s later the read reports 10 s less: the window re-anchors to the
    -- fresh fact (the plain-read law of Engine:OnRead).
    info.timeLeft = 1190000
    Enchants:ReadAll(1010, r)
    local e2 = Engine.entries[MH_KEY]
    assertNotNil(e2)
    near(1010, e2.start)
    near(1190, e2.duration)
    near(2200, e2.endTime)
    assertEquals(1, Enchants:Count(), "still one entry, no duplicate")
    clearEnchants()
end)

test("a secret read keeps the last plain anchor; a raise keeps it; the clock runs on", function()
    freshStorage()
    clearEnchants()
    Enchants:ReadAll(1000, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 1200000,
            charges = 0, enchantID = 999999 } },
    }))
    local e = Engine.entries[MH_KEY]
    local start, dur, endTime = e.start, e.duration, e.endTime
    assertNotNil(e)

    -- Secret fields (combat lockdown of the struct).
    patchPlain()
    local ok1 = pcall(Enchants.ReadAll, Enchants, 1300, readersFrom({
        infos = { [MH] = { hasEnchant = SECRET, timeLeft = SECRET,
            charges = SECRET, enchantID = SECRET } },
    }))
    -- The raising shape (a restricted client raises the read itself).
    local ok2 = pcall(Enchants.ReadAll, Enchants, 1300, {
        read = function() error("simulated secret-raise") end,
    })
    -- A non-number field (string timeLeft): no compare runs, no raise.
    local ok3 = pcall(Enchants.ReadAll, Enchants, 1300, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = "1200000",
            charges = 0, enchantID = 999999 } },
    }))
    restorePlain()
    assertTrue(ok1 and ok2 and ok3, "secret/raising/typed reads raise nothing")
    local e2 = Engine.entries[MH_KEY]
    assertNotNil(e2, "the entry rides the secret pass")
    near(start, e2.start)
    near(dur, e2.duration)
    near(endTime, e2.endTime) -- counts down from the LAST PLAIN ANCHOR
    assertEquals("read", e2.source)
    clearEnchants()
end)

-- ------------------------------------------------------------- removal ---

test("a plain hasEnchant = false removes the entry SILENTLY (no ready pop)", function()
    freshStorage()
    clearEnchants()
    Enchants:ReadAll(1000, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 1200000,
            charges = 0, enchantID = 999999 } },
    }))
    assertNotNil(Engine.entries[MH_KEY])
    Enchants:ReadAll(1100, readersFrom({
        infos = { [MH] = { hasEnchant = false, timeLeft = 0,
            charges = 0, enchantID = 0 } },
    }))
    assertNil(Engine.entries[MH_KEY], "entry removed")
    assertEquals(0, Enchants:Count())
    -- The Sweep far past the lapsed endTime pops NOTHING for this name:
    -- the entry left with the read, it never reached the Sweep.
    local popped
    for _, nm in ipairs(Engine:Sweep(90000, {})) do
        if nm == MH_LABEL then popped = true end
    end
    assertFalse(popped, "enchant burn-off is not a cooldown completing")
    clearEnchants()
end)

-- --------------------------------------------------------------- slots ---

test("off hand is independent of main hand", function()
    freshStorage()
    clearEnchants()
    -- Main hand enchanted, off hand plain.
    Enchants:ReadAll(1000, readersFrom({
        infos = {
            [MH] = { hasEnchant = true, timeLeft = 1200000, charges = 0,
                enchantID = 999999 },
            [OH] = { hasEnchant = false, timeLeft = 0, charges = 0,
                enchantID = 0 },
        },
    }))
    assertNotNil(Engine.entries[MH_KEY])
    assertNil(Engine.entries[OH_KEY])
    assertEquals(1, Enchants:Count())
    -- Now the off hand carries a poison (600 s) and the main hand goes
    -- plain: the two slots turn over independently.
    Enchants:ReadAll(1010, readersFrom({
        infos = {
            [MH] = { hasEnchant = false, timeLeft = 0, charges = 0,
                enchantID = 0 },
            [OH] = { hasEnchant = true, timeLeft = 600000, charges = 0,
                enchantID = 999998 },
        },
    }))
    assertNil(Engine.entries[MH_KEY])
    local oh = Engine.entries[OH_KEY]
    assertNotNil(oh)
    near(1610, oh.endTime)
    assertEquals(1, Enchants:Count())
    clearEnchants()
end)

-- CodeReview2 n3: the same enchant on BOTH weapon slots (one poison/oil on
-- main hand and off hand -- the dual-wield case) resolved to the SAME
-- display name, and with the entry keyed by that name both slots shared ONE
-- Engine.entries entry. The sub-floor / hasEnchant-false landing is a
-- slot-local read, so the early slot's expiry landed the shared window and
-- the Sweep retired the entry out from under the slot that still had 28
-- minutes left. The key carries the slot now (`<name>#<slot>`); `e.name`
-- stays the display name, so the Sweep pops the plain name.
test("the same enchant on both weapon slots is two independent entries", function()
    freshStorage()
    clearEnchants()
    local ID = 1900 -- resolves to ONE name for both slots -> the shared key
    local infos = {
        -- MH: 2 minutes of the enchant. OH: 30 minutes. Same id.
        [MH] = { hasEnchant = true, timeLeft = 120000, charges = 0,
            enchantID = ID },
        [OH] = { hasEnchant = true, timeLeft = 1800000, charges = 0,
            enchantID = ID },
    }
    local readers = readersFrom({
        infos = infos,
        names = { [ID] = "Enchant Weapon - Windfury" },
    })
    Enchants:ReadAll(1000, readers)
    local mhKey = keyOf("Enchant Weapon - Windfury", "MainHand")
    local ohKey = keyOf("Enchant Weapon - Windfury", "OffHand")
    local mh = Engine.entries[mhKey]
    local oh = Engine.entries[ohKey]
    assertNotNil(mh, "the main hand has its own entry")
    assertNotNil(oh, "the off hand has its own entry")
    assertTrue(mh ~= oh, "one shared entry for two slots is the n3 bug")
    assertEquals("Enchant Weapon - Windfury", mh.name,
        "the entry keeps the bare display name (the key carries the slot)")
    assertEquals("Enchant Weapon - Windfury", oh.name)
    near(1120, mh.endTime)   -- 1000 + 120 s
    near(2800, oh.endTime)   -- 1000 + 1800 s
    assertEquals(2, Enchants:Count(), "two slots, two entries")

    -- The main-hand enchant burns out: its next plain read is under the
    -- tracking floor, which lands THAT slot's window and retires it.
    infos[MH] = { hasEnchant = true, timeLeft = 1500, charges = 0,
        enchantID = ID }
    Enchants:ReadAll(1110, readersFrom({
        infos = infos,
        names = { [ID] = "Enchant Weapon - Windfury" },
    }))
    local popped
    for _, nm in ipairs(Engine:Sweep(1111, {})) do
        if nm == "Enchant Weapon - Windfury" then popped = true end
    end
    assertTrue(popped, "the expired slot pops under its DISPLAY name")
    assertNil(Engine.entries[mhKey], "the burned-out slot entry is gone")
    local ohLeft = Engine.entries[ohKey]
    assertNotNil(ohLeft,
        "the 28-minute off-hand enchant survives its twin's expiry")
    -- The 1110 pass re-read the off hand too, and a plain read RE-ANCHORS
    -- the window (the Engine:OnRead law): start 1110, the full 1800 s left.
    near(2910, ohLeft.endTime)
    assertEquals(1, Enchants:Count())
    clearEnchants()
end)

-- -------------------------------------------------------------- charges --

test("a plain charges count rides the row (maxCharges) and the entry never self-sweeps before its end", function()
    freshStorage()
    clearEnchants()
    Enchants:ReadAll(1000, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 1200000,
            charges = 13, enchantID = 999999 } },
    }))
    local e = Engine.entries[MH_KEY]
    assertNotNil(e)
    assertNotNil(e.charges, "the charge model is present")
    -- The engine's drained-bar shape (Core/Enchants.lua header): the icon
    -- rides the bar and the count number rides maxCharges; 0 >= 13 is false,
    -- so the Sweep cannot retire it early.
    local row
    for _, r in ipairs(Engine:Sorted({})) do
        if r.name == MH_LABEL then row = r end
    end
    assertNotNil(row, "the charged enchant stays on the bar")
    assertEquals(0, row.charges)
    assertEquals(13, row.maxCharges)
    local popped
    for _, nm in ipairs(Engine:Sweep(2100, {})) do
        if nm == MH_LABEL then popped = true end
    end
    assertFalse(popped, "no sweep before the window ends")
    assertNotNil(Engine.entries[MH_KEY])

    -- The landing pass: past the window with no plain read (the reads went
    -- ready-less/nil), the charge snapshot lands and the Sweep retires it
    -- with the NORMAL end pop.
    Enchants:ReadAll(2300, readersFrom({ infos = {} }))
    popped = nil
    local out = Engine:Sweep(2300, {})
    for _, nm in ipairs(out) do
        if nm == MH_LABEL then popped = true end
    end
    assertTrue(popped, "the lapsed charged entry pops exactly at its landing")
    assertNil(Engine.entries[MH_KEY])
    clearEnchants()
end)

test("timeLeft under the tracking floor: permanent enchants create nothing, a lapping entry lands", function()
    freshStorage()
    clearEnchants()
    -- Permanent enchant (timeLeft 0), no prior entry: nothing is tracked.
    Enchants:ReadAll(1000, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 0,
            charges = 0, enchantID = 999999 } },
    }))
    assertNil(Engine.entries[MH_KEY])
    -- A running entry whose next plain read says "1.5 s left": the window
    -- lands (endTime = now) and the Sweep retires it.
    Enchants:ReadAll(1100, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 300000,
            charges = 0, enchantID = 999999 } },
    }))
    local e = Engine.entries[MH_KEY]
    assertNotNil(e)
    Enchants:ReadAll(1400, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 1500,
            charges = 0, enchantID = 999999 } },
    }))
    near(1400, Engine.entries[MH_KEY].endTime)
    local popped
    for _, nm in ipairs(Engine:Sweep(1401, {})) do
        if nm == MH_LABEL then popped = true end
    end
    assertTrue(popped, "the floored read ends the entry with the normal effect")
    clearEnchants()
end)

-- --------------------------------------------------------------- events --

test("WEAPON_ENCHANT_CHANGED drives a read through the module's event frame", function()
    local M = FX.Cooldown.Module
    assertNotNil(M._eventFrame, "bound at OnEnable")
    local handler = M._eventFrame:GetScript("OnEvent")
    assertEquals("function", type(handler))
    clearEnchants()
    local real = Enchants.ReadAll
    local calls = 0
    Enchants.ReadAll = function(self, now, readers)
        calls = calls + 1
        return real(self, now, readers)
    end
    handler(M._eventFrame, "WEAPON_ENCHANT_CHANGED")
    Enchants.ReadAll = real
    assertEquals(1, calls, "the change event reads the weapon slots")
    clearEnchants()
end)

-- --------------------------------------------------------------- status --

test("/fx status prints the Enchants line", function()
    freshStorage()
    clearEnchants()
    Enchants:ReadAll(1000, readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 1200000,
            charges = 0, enchantID = 999999 } },
    }))
    local lines = {}
    local realPrint = FX.Print
    FX.Print = function(msg) lines[#lines + 1] = tostring(msg) end
    FX.Cooldown.Module:Status()
    FX.Print = realPrint
    assertContains(table.concat(lines, "\n"), "Enchants: 1")
    clearEnchants()
end)

-- ------------------------------------------------- engine rebuild safety --

test("an Engine:Build wipe (SPELLS_CHANGED rebuild) leaves no stale slot entry; the next read recreates", function()
    freshStorage()
    clearEnchants()
    local data = FX.Data and FX.Data.Hunter
    if not data then
        print("[skip] ForteXorcist.Data.Hunter not loaded")
        return
    end
    local readers = readersFrom({
        infos = { [MH] = { hasEnchant = true, timeLeft = 1200000,
            charges = 0, enchantID = 999999 } },
    })
    Enchants:ReadAll(1000, readers)
    assertNotNil(Engine.entries[MH_KEY])
    Engine:Build("HUNTER", function() return true end) -- wipes entries
    assertNil(Engine.entries[MH_KEY])
    assertEquals(0, Enchants:Count(), "Count follows the live entries")
    Enchants:ReadAll(1100, readers)
    assertNotNil(Engine.entries[MH_KEY], "the next read pass recreates the entry")
    clearEnchants()
end)

-- -------------------------------------------------------------- restore --

-- Restore module-owned state for any later file (no framework teardown).
test("restore module state", function()
    restorePlain()
    clearEnchants()
    Engine:AttachStorage(savedLearned)
    if FX.db and FX.db.cooldownLearned then
        Engine:AttachStorage(FX.db.cooldownLearned)
    end
    -- The module's live view back (no scripted readers; the live seams
    -- answer for this char: an unenchanted sim char keeps Count at 0).
    Enchants:ReadAll()
    assertEquals(true, true)
end)
