-- Forte_Core/Core/Locale.lua
-- H1 Localization: the bridge between the CLIENT's localized spell/item
-- names and the DATA keys the whole package indexes on (every generated
-- `Data/*.lua` row carries the English name from the Forever data set).
--
-- The original keyed its runtime tables by the CLIENT's name: every
-- registration in `/tmp/fxref/Forte_Class/*/Localization.lua` wraps the
-- constant in `FW:SpellName(...)`/`FW:ItemName(...)`
-- (`/tmp/fxref/Forte_Core/Forte_Core.lua:462-476`, `:808-814`), which resolved
-- `GetSpellInfo(name) -> localized name` per `GetLocale()` table. ForteXorcist
-- keys on the DATA name (stable across builds: the ids and names come from
-- `mythicsim-forever-engine/data/spells.jsonl`), so the localized client name
-- is a lookup INPUT, never a key. This module is the one translation point:
--
--   FX.L(english)            english data name -> client display name
--   Locale.CanonicalName(x)  client name -> english data name (identity if
--                            unknown: pass-through, never nil)
--   Locale.RankIDsForName(x) the data row's own ids (id path first:
--                            locale-independent `IsPlayerSpell`)
--
-- Aliases are built from the DATA IDS via `C_Spell.GetSpellInfo(id).name` /
-- `C_Item.GetItemNameByID(id)` -- never from hand-typed translations. On an
-- English client (`GetLocale() == "enUS"`) every builder is a NO-OP: zero
-- aliases, zero extra keys, so the English path is bit-identical to before.
-- Item names are NOT cached at login on a cold client
-- (`C_Item.GetItemNameByID` is Nilable; shipping addons gate the same window
-- with `C_Item.RequestLoadItemDataByID` + `ITEM_DATA_LOAD_RESULT`/
-- `GET_ITEM_INFO_RECEIVED`), so uncached ids are REQUESTED and the alias is
-- recorded when the reply lands (`Locale.WatchItemLoads`).
ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Locale = FX.Locale or {}
local Locale = FX.Locale

Locale. localizedToEnglish = Locale.localizedToEnglish or {}
Locale.englishToLocal = Locale.englishToLocal or {}
-- [ByName data table] = { { english = ..., localized = ... }, ... }: the
-- alias pairs the consumer adds to its own name->value table.
Locale.aliasesByTable = Locale.aliasesByTable or {}
-- [english name] = { data row id, ... } (every rank row of the name).
Locale.idsByEnglish = Locale.idsByEnglish or {}
-- [itemID] = english data name (the data set's label for a live item id).
Locale.englishByItemID = Locale.englishByItemID or {}
-- English data keys: an incoming name in this set is NEVER aliased (a
-- localized name that collides with another row's English key would poison
-- the lookup).
Locale.englishKeys = Locale.englishKeys or {}

Locale.state = Locale.state or {
    locale = nil, english = nil, spellsBuilt = false, itemsBuilt = false,
    aliases = 0, lateNames = 0, requests = 0, frame = nil,
}

Locale.REQUEST_CAP = 256

-- Tests stub these seams (the sim is enUS-fixed: a non-enUS locale is not
-- modelled there, docs/localization.md); every seam defaults to the client.
Locale.stubLocale = nil
Locale.stubSpellName = nil
Locale.stubItemName = nil
Locale.onLateNames = {}

function Locale.GetLocale()
    if Locale.stubLocale then return Locale.stubLocale() end
    if type(GetLocale) ~= "function" then return nil end
    return GetLocale()
end

function Locale.IsEnglish()
    local locale = Locale.GetLocale()
    -- No locale signal: treat as English (no aliases, English lookups work).
    if type(locale) ~= "string" then return true, locale end
    locale = locale:gsub("^en.+$", "enUS")
    return locale == "enUS", locale
end

--- The client's localized name of a SPELL ID (the alias source). The spell
--- data may be uncached (`SPELL_DATA_LOAD_RESULT` gates that on the live
--- client); a miss is simply no alias -- the English name path still works
--- on an English client.
function Locale.SpellNameForID(spellID)
    if Locale.stubSpellName then return Locale.stubSpellName(spellID) end
    if type(spellID) ~= "number" then return nil end
    if not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if not ok then return nil end
    if type(info) ~= "table" then return nil end
    local name = FX.Compat.PlainOrNil(info.name)
    if type(name) ~= "string" or name == "" then return nil end
    return name
end

--- The client's localized name of an ITEM ID. The client returns the string
--- "Unknown" for ids it cannot resolve (observed in the sim) -- as good as
--- nil: no alias. Nilable on a cold cache (the documented contract).
function Locale.ItemNameByID(itemID)
    if Locale.stubItemName then return Locale.stubItemName(itemID) end
    if type(itemID) ~= "number" then return nil end
    if not (C_Item and C_Item.GetItemNameByID) then return nil end
    local ok, name = pcall(C_Item.GetItemNameByID, itemID)
    if not ok then return nil end
    name = FX.Compat.PlainOrNil(name)
    if type(name) ~= "string" or name == "" or name == "Unknown" then return nil end
    return name
end

local function record(english, localized)
    if type(english) ~= "string" or type(localized) ~= "string" then return false end
    if localized == english then return false end
    if Locale.localizedToEnglish[localized] then return false end
    if Locale.englishKeys[localized] then return false end
    Locale.localizedToEnglish[localized] = english
    Locale.englishToLocal[english] = localized
    Locale.state.aliases = Locale.state.aliases + 1
    return true
end

--- english -> client display name (FX.L): the display seam.
function Locale.LocalizedName(name)
    if type(name) ~= "string" then return name end
    return Locale.englishToLocal[name] or name
end

--- client name -> english data key. Unknown names pass through UNCHANGED
--- (never nil): every caller's English behaviour is untouched.
function Locale.CanonicalName(name)
    if type(name) ~= "string" then return name end
    return Locale.localizedToEnglish[name] or name
end

--- The data row ids of an English data name (all ranks), for the id-first
--- "does this character know it" path.
function Locale.RankIDsForName(name)
    if type(name) ~= "string" then return nil end
    return Locale.idsByEnglish[name]
end

--- The alias pairs of one class data table, for its consumer to add as
--- extra ByName keys (Forte_Timer's Registry). Empty on English.
function Locale.SpellAliasesFor(dataTable)
    return Locale.aliasesByTable[dataTable]
end

--- Record one alias pair (the item family: the consumer knows the pair,
--- Locale owns the maps). Returns true when the pair is new.
function Locale.RecordItemAlias(english, localized, byNameTable, value)
    if not Locale.AddTableAlias(byNameTable, english, localized, value) then
        return false
    end
    return record(english, localized)
end

--- Add a localized key to one name->value table (the lookup seam used by
--- Forte_Cooldown's Items scan). English/nil/colliding pairs are skipped.
function Locale.AddTableAlias(byNameTable, english, localized, value)
    if type(english) ~= "string" or type(localized) ~= "string" then return false end
    if localized == english then return false end
    if Locale.englishKeys[localized] then return false end
    if Locale.englishKeys[english] == nil and not Locale.englishToLocal[english] then
        -- Only alias names the data set itself owns: the english key must be
        -- a data key (the alias maps ride the data key space).
        if not Locale.englishKeys[english] then
            if byNameTable == nil then return false end
        end
    end
    if value == nil then return false end
    if byNameTable ~= nil and byNameTable[localized] == nil then
        byNameTable[localized] = value
    end
    record(english, localized)
    return true
end

local function noteKey(name)
    if type(name) == "string" then Locale.englishKeys[name] = true end
end

--- Walk the loaded class data tables: every row's id joins the rank list of
--- its English name; a localized row name adds the alias maps and a
--- localized key to the class `ByName` table (id-valued, so the existing
--- `ByName[castName] -> id` consumer works for localized cast names).
--- Idempotent (`spellsBuilt`); a no-op on an English client.
function Locale.BuildSpellAliases()
    if Locale.state.spellsBuilt then return 0 end
    if not FX.Data then return 0 end
    local english = Locale.IsEnglish()
    -- Key space first: the collision guard needs EVERY English key before
    -- any alias is written.
    local classes = {}
    for key, table in pairs(FX.Data) do
        if key:match("ByName$") == nil and key ~= "Items"
            and type(table) == "table" then
            classes[#classes + 1] = { key = key, rows = table }
            for name in pairs(FX.Data[key .. "ByName"] or {}) do noteKey(name) end
        end
    end
    Locale.state.spellsBuilt = true
    if english then
        Locale.state.english = true
        return 0
    end
    local added = 0
    for i = 1, #classes do
        local key = classes[i].key
        local byName = FX.Data[key .. "ByName"]
        local pairsList
        for _, row in pairs(classes[i].rows) do
            if type(row) == "table" and type(row.id) == "number"
                and type(row.name) == "string" then
                noteKey(row.name)
                local ids = Locale.idsByEnglish[row.name]
                if not ids then ids = {}; Locale.idsByEnglish[row.name] = ids end
                ids[#ids + 1] = row.id
                local localized = Locale.SpellNameForID(row.id)
                if localized and localized ~= row.name then
                    if byName and byName[localized] == nil then
                        byName[localized] = row.id
                        Locale.writtenKeys = Locale.writtenKeys or {}
                        Locale.writtenKeys[#Locale.writtenKeys + 1] =
                            { byName, localized }
                    end
                    if record(row.name, localized) then
                        added = added + 1
                        pairsList = Locale.aliasesByTable[classes[i].rows]
                        if not pairsList then
                            pairsList = {}
                            Locale.aliasesByTable[classes[i].rows] = pairsList
                        end
                        pairsList[#pairsList + 1] =
                            { english = row.name, localized = localized }
                    end
                end
            end
        end
    end
    return added
end

--- Walk the generated item rows (Forte_Cooldown calls this with
--- `FX.Data.Items` from its scan): record the id->English label, resolve the
--- localized name from the id, and REQUEST the ids whose name is not cached
--- yet (the login window). Aliases into `OnUseByName` are added by the
--- caller's scan via `AddTableAlias` (it owns the row values).
function Locale.BuildItemAliases(Items)
    if not (type(Items) == "table" and Items.onUse) then return 0 end
    for _, row in ipairs(Items.onUse) do
        local itemID = row.itemId or row.id
        if type(itemID) == "number" and type(row.name) == "string" then
            noteKey(row.name)
            Locale.englishByItemID[itemID] = row.name
        end
    end
    if Items.consumables then
        for _, row in ipairs(Items.consumables) do
            local itemID = row.itemId or row.id
            if type(itemID) == "number" and type(row.name) == "string" then
                noteKey(row.name)
                Locale.englishByItemID[itemID] = row.name
            end
        end
    end
    if Locale.IsEnglish() then return 0 end
    local added = 0
    for itemID, english in pairs(Locale.englishByItemID) do
        local localized = Locale.ItemNameByID(itemID)
        if localized == nil then
            -- Cold-cache login window: ask, and the alias lands on the
            -- GET_ITEM_INFO_RECEIVED/ITEM_DATA_LOAD_RESULT reply.
            Locale.RequestItemName(itemID)
        elseif localized ~= english then
            if record(english, localized) then added = added + 1 end
        end
    end
    return added
end

--- The English data label of a live item id (nil when the data set has no
--- row for it: a non-tracked item costs nothing).
function Locale.EnglishItemName(itemID)
    return Locale.englishByItemID[itemID]
end

--- Ask the client to load an item's data (the cold-cache login window).
--- `ITEM_DATA_LOAD_RESULT`/`GET_ITEM_INFO_RECEIVED` carry the arrival.
function Locale.RequestItemName(itemID)
    if type(itemID) ~= "number" then return end
    if Locale.state.requests >= Locale.REQUEST_CAP then return end
    if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
    Locale.state.requests = Locale.state.requests + 1
    pcall(C_Item.RequestLoadItemDataByID, itemID)
end

--- Late item names: record the alias, then wake the subscribers (the
--- Forte_Cooldown item scan re-runs, this time seeing the localized name).
function Locale.OnItemNameArrived(itemID)
    if type(itemID) ~= "number" then return end
    local english = Locale.englishByItemID[itemID]
    if type(english) ~= "string" then return end
    local localized = Locale.ItemNameByID(itemID)
    if not localized or localized == english then return end
    if not record(english, localized) then return end
    Locale.state.lateNames = Locale.state.lateNames + 1
    -- Each subscriber in its own pcall: one raising rescan never stops the rest
    -- (there is no FX:CallSafe; the Events bus uses the same contained shape).
    for i = 1, #Locale.onLateNames do
        local ok, err = pcall(Locale.onLateNames[i], itemID)
        if not ok and FX.Print then
            FX.Print("Locale: a late-name subscriber failed: " .. tostring(err))
        end
    end
end

--- Subscribe to late item-name arrivals (Forte_Cooldown's item scan).
function Locale.SubscribeLateNames(fn)
    if type(fn) == "function" then
        Locale.onLateNames[#Locale.onLateNames + 1] = fn
    end
end

--- Drop every alias and rebuild flag (the German-stub suites' seam).
function Locale.Reset()
    -- Undo the localized keys the build wrote into the shared data tables
    -- (the residue would poison the English-key census on the next build).
    for i = 1, #(Locale.writtenKeys or {}) do
        local w = Locale.writtenKeys[i]
        w[1][w[2]] = nil
    end
    Locale.writtenKeys = {}
    Locale.localizedToEnglish = {}
    Locale.englishToLocal = {}
    Locale.aliasesByTable = {}
    Locale.idsByEnglish = {}
    Locale.englishByItemID = {}
    Locale.englishKeys = {}
    Locale.stubLocale = nil
    Locale.stubSpellName = nil
    Locale.stubItemName = nil
    Locale.state.spellsBuilt = false
    Locale.state.itemsBuilt = false
    Locale.state.aliases = 0
end

--- The event watch, from a frame-legal context (OnEnable, Init, handler).
function Locale.WatchItemLoads()
    if Locale.state.frame then return Locale.state.frame end
    if type(CreateFrame) ~= "function" then return nil end
    local frame = CreateFrame("Frame")
    frame.name = "ForteXorcistLocale"
    frame:SetScript("OnEvent", function(_, event, arg1, arg2)
        if event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" then
            -- Payload (itemID, success): only a success carries a name.
            if arg2 == false then return end
            Locale.OnItemNameArrived(arg1)
        end
    end)
    frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    Locale.state.frame = frame
    return frame
end

local LocaleModule = { name = "Locale" }

function LocaleModule.OnEnable()
    Locale.WatchItemLoads()
    Locale.BuildSpellAliases()
    return true
end

function LocaleModule.OnDisable()
    -- The tear-down pair of WatchItemLoads, guarded the way every other
    -- disable site in the tree guards it (Forte_Hunter/UI/Swing.lua:926-941,
    -- Forte_Shaman/Core/Totems.lua:347-353, Forte_Warlock/Core/Comms.lua:
    -- 639-646): `UnregisterEvent` is catalog-declared for the real client's
    -- Frame but ABSENT from the simulator's frame emulation, and a
    -- restricted client may raise on the call -- an unguarded call dies in
    -- the middle of the disable, which is the one path that must always
    -- finish. The frame handle survives on purpose: WatchItemLoads is
    -- idempotent on it, so a re-enable re-runs the pair from the same frame.
    local frame = Locale.state.frame
    if frame and frame.UnregisterEvent then
        pcall(frame.UnregisterEvent, frame, "GET_ITEM_INFO_RECEIVED")
        pcall(frame.UnregisterEvent, frame, "ITEM_DATA_LOAD_RESULT")
    end
    return true
end

function LocaleModule.OnEvents(event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Locale.state.spellsBuilt = false
        Locale.BuildSpellAliases()
    end
end

function LocaleModule.OnClassChanged()
    -- The LoadOnDemand class add-on can land AFTER this module's OnEnable
    -- (login order and a LoD class change via FX.RefreshPlayerClass both
    -- route FX_CLASS_LOADED here): rebuild against the newly loaded rows.
    -- Only the maps are rebuilt -- aliases added to a previous class's
    -- ByName table are harmless leftovers of the same key space.
    Locale.state.spellsBuilt = false
    Locale.BuildSpellAliases()
end

function Locale.StatusLine()
    local english, locale = Locale.IsEnglish()
    return string.format("Locale: locale=%s english=%s aliases=%d late=%d",
        tostring(locale), tostring(english), Locale.state.aliases,
        Locale.state.lateNames)
end

FX.RegisterModule("Locale", LocaleModule)

-- FX.L: the display seam (original law: FW:SpellName / FW:ItemName,
-- Forte_Core.lua:462-476, :808-814).
function FX.L(name)
    return Locale.LocalizedName(name)
end
