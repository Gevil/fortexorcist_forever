-- Forte_Cooldown/Core/Items.lua
-- Item-side tracker of the cooldown engine: on-use trinkets/items and
-- consumables (potions, healthstones, flasks), tracked beside spells, in
-- the SAME Engine.entries table with the SAME entry shape (name, start,
-- duration, endTime, predicted, source, anchored) plus the display tags
-- `category` ("Item" for trinkets/items, "Potion" for consumables) and
-- `icon` (fileID or nil) that Engine:Sorted rows expose for the Timeline.
--
-- Data source: ForteXorcist.Data.Items (addon Forte_Items, generated --
-- see docs/item-procs.md). Matched BY NAME, never by id (ids drift per
-- build, PLAN §8). The data addon is an OptionalDep: absent -> Rescan
-- tracks nothing and degrades silently (no error, no print).
--   * onUse rows:  name, cooldownMs, slotType, classAllowlist?  -- no cast
--     spell field exists in the data (verified in the generated file), so
--     the cast-spell name is resolved live via C_Item.GetItemSpell at
--     Rescan time (CooldownMaster's mapItemSpell pattern) and remembered
--     in `byCastSpell`. Where the API is absent (it is in the sim build)
--     in-combat cast prediction has no name to ride and only plain reads
--     drive the entries.
--   * consumables rows: name, categoryCooldownMs, categoryId -- a SHARED
--     category cooldown (potions 120 s, healthstone family 120 s, Zanza
--     3600 s). Only rows with a >= MIN_CATEGORY_CD (60 s) category are
--     tracked: the 1-3 s rows are the GCD band (elixir/flask slot cooldowns
--     in the Classic data), noise by the same law as Engine.MIN_COOLDOWN.
--
-- The in-combat model is the spell model (PLAN §3.2): a successful own
-- cast of an item's use spell (UNIT_SPELLCAST_SUCCEEDED -> name ->
-- byCastSpell) starts predicted entries -- the used item AND every tracked
-- sibling of its shared category (drinking one potion cools down them all,
-- docs/design-combat-procs.md §2). Any plain read re-anchors ("anchored"
-- source, learned duration). A secret read changes nothing: every number
-- is routed through Compat.PlainOrNil inside OnRead.
--
-- Reads (mirroring CooldownMaster's proven split, Engine:PollOneItem):
-- equipped items poll their INVENTORY SLOT (GetInventoryItemCooldown),
-- bag items poll by itemID (C_Container.GetItemCooldown) -- all through
-- FX.Compat.GetItemCooldownInfo, the seam tests script. All live C_* calls
-- are pcall'd: on a secret-restricted client a read raises, it does not
-- merely return a secret.
--  * Evidence for the inventory-slot pair (GetInventoryItemID for the id,
--    GetInventoryItemCooldown for the window): the wow-ui-sim probe
--    (measured 2026-11-01: both exist, returning plain 0/0/1 = ready),
--    uiforever.com, and CooldownMaster shipping them against the live
--    client (docs/engine-notes.md). They are NOT declared in the pinned
--    Forever catalogs (zero declarations; the nearest catalog entry is
--    C_TooltipInfo.GetInventoryItemByID) -- the earlier "verified in the
--    pinned catalog" claim at this spot was false (review 2026-11-01 m2).
--    Every call site is nil-guarded, and Compat.GetEquippedItemID falls
--    back to the catalog-declared pair
--    C_Item.GetItemID(ItemLocation:CreateFromEquipmentSlot(slot)), so a
--    client without the globals degrades to "no equipped items tracked"
--    (bag items keep working) -- never an error.
--
-- Open live probes (docs/design-combat-procs.md §5.7, first real client):
--  1. Are the item-cooldown returns plain in combat? (The catalog annotates
--     no SecretWhen… on them -- expected plain, unmeasured by us.)
--  2. Does C_Container.GetItemCooldown(potionID) report the shared CATEGORY
--     cooldown, so every potion's own read re-anchors the family? (CMC's
--     shared-cooldown dedupe implies yes; unverified by us.)
--  3. Is C_Item.GetItemInfo name-populated for never-seen items (it is
--     async-backed); do missing names arrive via GET_ITEM_INFO_RECEIVED?
--     Missing names simply leave the item untracked until the next rescan.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

local Engine = FX.Cooldown.Engine
local Items = {}
Engine.Items = Items

-- Below this a "category cooldown" is GCD-band noise (see header). Seconds.
Items.MIN_CATEGORY_CD = 60

-- Fresh-prediction grace (seconds) before a plain "ready" read may clear a
-- cast entry: the item-cooldown read can lag the cast for a moment (the
-- same law the spell side uses in Engine:OnRead).
local PREDICTION_GRACE = 1.6

Items.tracked = {}     -- [itemName] = { name, itemId, kind = "item"|"potion",
                       --   category, icon, baseDuration, slot?, categoryId? }
Items.byCastSpell = {} -- [useSpellNameLower] = itemName

local TRINKET_SLOTS -- { INVSLOT_TRINKET1, INVSLOT_TRINKET2 } resolved lazily

local function TitleCase(classFile)
    if not classFile then return nil end
    return classFile:sub(1, 1):upper() .. classFile:sub(2):lower()
end

--- The mythicsim class token for the current class ("ClassHunter"), nil
--- when the class is unknown (then every classAllowlist passes: an
--- unclassified player filters nothing).
local function classToken()
    local c = FX._playerClass
    return c and ("Class" .. TitleCase(c))
end

local function classAllows(row, token)
    local al = row.classAllowlist
    if not al then return true end
    if not token then return true end
    for _, t in ipairs(al) do
        if t == token then return true end
    end
    return false
end

--- Shared consumable category cooldown in seconds (nil when the row has
--- no category).
local function categoryDurationS(row)
    return row.categoryCooldownMs and row.categoryCooldownMs / 1000
end

--- Best duration we have for a tracked item: learned beats generated base
--- (the spell law; the learned table is shared with spells -- item and
--- spell name spaces do not collide, and a shared entry is a fact from a
--- plain read of one of them either way).
function Items:BestDuration(name)
    local learned = Engine.learned[name]
    if learned and learned >= Engine.MIN_COOLDOWN then return learned end
    local t = self.tracked[name]
    return t and t.baseDuration
end

--- The stale-entry sweep, run at the END of a Rescan against the freshly
--- built `Items.tracked` (M2 fix, 2026-11-01: the sweep used to run at the
--- top, right after the wipe, so `not self.tracked[name]` matched EVERY
--- item entry and a bag event killed every live trinket/potion timer --
--- in combat included, where no secret read can bring it back). Only an
--- entry whose item the fresh scan did not find dies.
local function pruneUntracked()
    for name, e in pairs(Engine.entries) do
        if (e.category == "Item" or e.category == "Potion")
            and not Items.tracked[name] then
            e.row = nil
            Engine.entries[name] = nil
        end
    end
end

--- Rescan equipped trinkets (slots 13/14) and bag consumables/on-use items
--- against the generated data, matched by NAME. Returns the tracked count.
--- `readers` overrides the game seams for tests
--- ({ getEquippedItemID, getItemName, getItemSpell, getItemIcon, numSlots,
--- getContainerItemID }); production uses the FX.Compat seams. Degrades
--- silently (0, no error) when the data addon is absent.
function Items:Rescan(readers)
    wipe(self.tracked)
    wipe(self.byCastSpell)
    local data = FX.Data and FX.Data.Items
    if not data or type(data.onUse) ~= "table" or type(data.consumables) ~= "table" then
        -- Forte_Items absent: the item feature simply is off. Nothing is
        -- tracked, so the sweep retires every live item entry (a mid-session
        -- loss of the data addon degrades cleanly).
        pruneUntracked()
        return 0
    end
    readers = readers or {}
    local getEquippedItemID = readers.getEquippedItemID or (FX.Compat and FX.Compat.GetEquippedItemID)
    local getItemName = readers.getItemName or (FX.Compat and FX.Compat.GetItemInfoName)
    local getItemSpell = readers.getItemSpell or (FX.Compat and FX.Compat.GetItemSpellInfo)
    local getItemIcon = readers.getItemIcon or (FX.Compat and FX.Compat.GetItemIcon)
    local numSlots = readers.numSlots or (FX.Compat and FX.Compat.GetContainerNumSlots)
    local getContainerItemID = readers.getContainerItemID or (FX.Compat and FX.Compat.GetContainerItemID)
    if not (getEquippedItemID and getItemName and numSlots and getContainerItemID) then
        -- The inventory cannot be read at all: this is blindness, not an
        -- empty inventory, so NOTHING is pruned (pruning here would be the
        -- M2 bug again -- live item entries die on an event that proved
        -- nothing). The live entries keep their clocks and retire through
        -- the reads/Sweep like any other entry.
        return 0
    end

    -- Consumables indexed by name (the data ships OnUseByName only). The
    -- array is id-ascending, so first-wins mirrors the data's "lowest id"
    -- name-collision law.
    local byConsumableName = {}
    for _, row in ipairs(data.consumables) do
        local cd = categoryDurationS(row)
        if row.name and cd and cd >= self.MIN_CATEGORY_CD
            and not byConsumableName[row.name] then
            byConsumableName[row.name] = row
        end
    end

    local token = classToken()
    local n = 0

    local function call(fn, ...)
        local ok, a, b = pcall(fn, ...)
        if not ok then return nil, nil end
        return a, b
    end

    local function track(row, itemId, kind, slot, category, baseDuration)
        if not row.name or baseDuration < Engine.MIN_COOLDOWN then return end
        if self.tracked[row.name] then return end -- one entry per name
        local icon = getItemIcon and call(getItemIcon, itemId) or nil
        self.tracked[row.name] = {
            name = row.name, itemId = itemId, kind = kind, category = category,
            icon = icon, baseDuration = baseDuration, slot = slot,
            categoryId = row.categoryId,
        }
        -- The cast-spell map (the data has no use-spell field): resolve it
        -- live. Absent API (sim) / passive item -> no in-combat signal.
        if getItemSpell then
            local spellName = call(getItemSpell, itemId)
            if type(spellName) == "string" and spellName ~= "" then
                self.byCastSpell[spellName:lower()] = row.name
            end
        end
        n = n + 1
    end

    -- 1. Equipped trinkets: slots 13/14, matched against on-use data.
    if not TRINKET_SLOTS then
        TRINKET_SLOTS = { _G.INVSLOT_TRINKET1 or 13, _G.INVSLOT_TRINKET2 or 14 }
    end
    for _, eslot in ipairs(TRINKET_SLOTS) do
        local itemId = call(getEquippedItemID, eslot)
        local name = itemId and call(getItemName, itemId)
        local row = (type(name) == "string") and data.OnUseByName[name] or nil
        if row and classAllows(row, token) and row.cooldownMs then
            track(row, itemId, "item", eslot, "Item", row.cooldownMs / 1000)
        end
    end

    -- 2. Bags: backpack (0) plus the NUM_BAG_SLOTS held bags. Consumables
    --    by their category rows, on-use items (unequipped trinkets,
    --    engineering gadgets) by the on-use rows.
    for bag = 0, (_G.NUM_BAG_SLOTS or 4) do
        local slots = call(numSlots, bag)
        if type(slots) == "number" then
            for slot = 1, slots do
                local itemId = call(getContainerItemID, bag, slot)
                local name = itemId and call(getItemName, itemId)
                if type(name) == "string" then
                    local cons = byConsumableName[name]
                    if cons then
                        track(cons, itemId, "potion", nil, "Potion",
                            categoryDurationS(cons))
                    else
                        local row = data.OnUseByName[name]
                        if row and classAllows(row, token) and row.cooldownMs then
                            track(row, itemId, "item", nil, "Item",
                                row.cooldownMs / 1000)
                        end
                    end
                end
            end
        end
    end

    -- 3. Entries of items that left the inventory (unequipped, drunk,
    --    sold): the fresh scan did not find them, so the sweep retires
    --    them. Everything the scan DID find keeps its live entry -- the
    --    bag events that trigger a rescan (looting, a potion count change)
    --    say nothing about a running cooldown (M2).
    pruneUntracked()
    return n
end

--- Start (or restart) the predicted window of a tracked item, exactly the
--- Engine:OnCast shape + the category/icon tags. Shared-category siblings
--- are the caller's business (OnCastBySpellName).
function Items:OnCast(name, now)
    local t = self.tracked[name]
    if not t then return nil end
    local duration = self:BestDuration(name)
    if not duration then return nil end
    local e = Engine.entries[name] or { name = name }
    e.start, e.duration, e.endTime, e.predicted = now, duration, now + duration, true
    e.source, e.anchored = "cast", nil
    e.category, e.icon = t.category, t.icon
    Engine.entries[name] = e
    return e
end

--- A UNIT_SPELLCAST_SUCCEEDED resolved to spell name `spellName`: if an
--- tracked item's use spell answers to that name, start its predicted
--- window -- and every tracked sibling of a shared category (the category
--- cooldown cools down the whole family, header). Returns the entry of the
--- used item, nil when the name names no item (the spell path then owns it).
function Items:OnCastBySpellName(spellName, now)
    if type(spellName) ~= "string" then return nil end
    local name = self.byCastSpell[spellName:lower()]
    if not name then return nil end
    local t = self.tracked[name]
    if not t then return nil end
    local e = self:OnCast(name, now)
    if t.categoryId then
        for sibling, st in pairs(self.tracked) do
            if sibling ~= name and st.categoryId == t.categoryId then
                self:OnCast(sibling, now)
            end
        end
    end
    return e
end

--- A live cooldown read for a tracked item (raw numbers; guarded here --
--- the same contract as Engine:OnRead). A plain, real cooldown re-anchors
--- the entry (and its learned duration); a plain "ready" read clears it; a
--- secret read changes nothing. Returns "anchored", "cleared", "secret"
--- or "ignored".
function Items:OnRead(name, start, duration, now)
    local t = self.tracked[name]
    if not t then return "ignored" end
    start = FX.Compat.PlainOrNil(start)
    duration = FX.Compat.PlainOrNil(duration)
    -- Type guard, not a nil guard: a read can hand back a non-number (the sim's
    -- name-keyed table path does), and `start > 0` would then raise. Same law as
    -- Engine:OnRead.
    if type(start) ~= "number" or type(duration) ~= "number" then return "secret" end

    if start > 0 and duration >= Engine.MIN_COOLDOWN then
        local e = Engine.entries[name] or { name = name }
        e.start, e.duration, e.endTime, e.predicted = start, duration, start + duration, false
        e.source, e.anchored = "read", true
        e.category, e.icon = t.category, t.icon
        Engine.entries[name] = e
        self:LearnFamily(name, duration)
        return "anchored"
    end

    -- Plain read says "ready". Trust it only outside the fresh-prediction
    -- grace: the bag/slot read can lag the cast event for a moment.
    local e = Engine.entries[name]
    if e and e.predicted and now < e.endTime and (now - e.start) < PREDICTION_GRACE then
        return "ignored"
    end
    Engine.entries[name] = nil
    return "cleared"
end

--- A plain anchored read of one family member is a fact about the whole
--- shared category: the same real duration is learned for its tracked
--- siblings (their own reads lag -- only the used item's bag slot carried
--- the cast). Entries are NOT force-set from here: a sibling read still
--- anchors itself on the family's real start (open probe 2, header).
function Items:LearnFamily(name, duration)
    local t = self.tracked[name]
    Engine.learned[name] = duration
    if not (t and t.categoryId) then return end
    for sibling, st in pairs(self.tracked) do
        if sibling ~= name and st.categoryId == t.categoryId then
            Engine.learned[sibling] = duration
        end
    end
end

--- One read pass over every tracked item through the Compat seam
--- (equipped by slot, bag by itemID -- header). Raises and secret values
--- leave the entry model untouched; the 1 Hz safety net re-runs it.
function Items:ReadAll(now)
    now = now or GetTime()
    local read = FX.Compat and FX.Compat.GetItemCooldownInfo
    if not read then return end
    for name, t in pairs(self.tracked) do
        local ok, start, duration = pcall(read, t.itemId, t.slot)
        -- No `start ~= nil` here: that is a comparison on an unprobed live
        -- read (m1 -- a secret number raises on `~= nil` and takes the
        -- whole 1 Hz pass down with it). OnRead is the guard: it routes
        -- every number through PlainOrNil and answers "secret".
        if ok then
            self:OnRead(name, start, duration, now)
        end
    end
end

--- Counts for Module:Status: tracked entries, live entries.
function Items:Counts()
    local tracked, active = 0, 0
    for name in pairs(self.tracked) do
        tracked = tracked + 1
        if Engine.entries[name] then active = active + 1 end
    end
    return tracked, active
end
