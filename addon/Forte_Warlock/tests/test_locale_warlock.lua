-- addon/Forte_Warlock/tests/test_locale_warlock.lua
-- H1b (docs/localization.md, the `Forte_Warlock/Core/Tools.lua:147-157`
-- audit rows) on the German client, stubbed -- the law of the
-- Forte_Cooldown locale suite. Three lookup families in the Warlock tools
-- were keyed on English words:
--
--   * the soulstone / healthstone / summon family gates
--     (`^Create Soulstone`, `^Soulstone`, `Healthstone$`,
--     `^Ritual of Summoning`): the cast events name the spell in the
--     CLIENT's language, so on a German client `Seelenstein erstellen`
--     matched no family -- no soulstone window, no ritual channel, and the
--     `^Create ` bag re-read never ran;
--   * the bag counts: `C_Item.GetItemCount("Soul Shard" / "Major
--     Healthstone")` resolves the name in the client's item table.
--
-- The gates now canonicalize the client name onto the DATA key
-- (`FX.MatchesFamily`), and the bag reads ask the client's own display name
-- (`FX.L`). The German stubs answer the generated row's id and the German
-- name and never the English data name, so these tests pass only through the
-- joins.
local FX = ForteXorcist
local Tools = FX.Warlock.Tools
local WK = FX.Warlock
local Locale = FX.Locale
local _C_Spell, _C_Item, _IsPlayerSpell = C_Spell, C_Item, IsPlayerSpell

-- The generated ForteXorcist.Data.Warlock rows of the three families.
local DE_SPELL = {
    [20757] = "Seelenstein erstellen",   -- Create Soulstone
    [11730] = "Heilstein erstellen",     -- Create Healthstone
    [698] = "Ritual der Beschwörung",    -- Ritual of Summoning
    [11732] = "Großer Heilstein",        -- Major Healthstone
}

local function german(on)
    Locale.stubLocale = on and function() return "deDE" end or nil
    Locale.stubSpellName = on and function(id) return DE_SPELL[id] end or nil
    if on then
        _G.C_Spell = setmetatable({
            GetSpellInfo = function(x)
                if type(x) == "number" then
                    local name = DE_SPELL[x]
                    if name then return { spellID = x, name = name } end
                    if _C_Spell and _C_Spell.GetSpellInfo then
                        return _C_Spell.GetSpellInfo(x)
                    end
                    return nil
                end
                if type(x) == "string" then
                    for id, name in pairs(DE_SPELL) do
                        if name == x then return { spellID = id, name = name } end
                    end
                    return nil
                end
                return nil
            end,
        }, { __index = _C_Spell })
        _G.IsPlayerSpell = function(id) return DE_SPELL[id] ~= nil end
    else
        _G.C_Spell = _C_Spell
        _G.IsPlayerSpell = _IsPlayerSpell
    end
end

-- The bag seam: an item is counted under the client's German name only --
-- the English data label answers 0, the way a localized client answers a
-- name it has no item for.
local counts
local function germanItems(on)
    if not on then
        if _C_Item ~= nil then _G.C_Item = _C_Item end
        counts = nil
        return
    end
    counts = {}
    _G.C_Item = setmetatable({
        GetItemCount = function(name)
            counts[name] = (counts[name] or 0) + 1
            if name == "Großer Heilstein" then return 3 end
            if name == "Seelenscherbe" then return 7 end
            return 0
        end,
    }, { __index = _C_Item })
end

-- The H1 pattern: Reset FIRST (it clears the stubs and the build flag), then
-- install the German seams, then build. Building without the Reset hits the
-- builder's idempotence flag and adds nothing.
local function germanBuild()
    Locale.Reset()
    german(true)
    Locale.BuildSpellAliases()
end

local function restore()
    german(false)
    germanItems(false)
    Locale.Reset()
end

--- Drive the module's OWN event script (the public kick path).
local function dispatch(event, a1, a2, a3, a4)
    local wasEnabled = Tools._eventsEnabled
    if not wasEnabled then Tools:EnableEvents() end
    local f = Tools._eventFrame
    assertNotNil(f, "the tools' event frame exists once enabled")
    local h = f:GetScript("OnEvent")
    assertEquals("function", type(h))
    local ok, err = pcall(h, f, event, a1, a2, a3, a4)
    if not wasEnabled then
        Tools:DisableEvents()
        Tools._eventFrame = nil
    end
    assertTrue(ok, tostring(err))
end

local function isolation()
    local saved = {
        Tools.Soulstone.active, Tools.Soulstone.target, Tools.Soulstone.start,
        Tools.Soulstone.duration, Tools.Soulstone.now, Tools.Soulstone.name,
        Tools.Soulstone.casts, Tools.Soulstone.pending,
    }
    local clock = { 900000 }
    Tools.Soulstone.now = function() return clock[1] end
    Tools.Soulstone.duration = 1800
    Tools.Soulstone.active, Tools.Soulstone.target, Tools.Soulstone.start =
        false, nil, nil
    Tools.Soulstone.pending, Tools.Soulstone.name, Tools.Soulstone.casts =
        nil, nil, 0
    return saved, clock
end

test("locale: the soulstone family gate reads the German cast name", function()
    FX.LoadClassAddOn("WARLOCK")
    restore()
    germanBuild()
    assertTrue(FX.MatchesFamily("Seelenstein erstellen", WK.SoulstonePatterns),
        "the German `Create Soulstone` reaches the English family pattern")
    assertTrue(FX.MatchesFamily("Create Soulstone", WK.SoulstonePatterns),
        "the English data name keeps matching")
    assertFalse(FX.MatchesFamily("Heilstein erstellen", WK.SoulstonePatterns),
        "a healthstone cast is not in the family")
    restore()
end)

test("locale: a German soulstone cast opens the predicted window", function()
    FX.LoadClassAddOn("WARLOCK")
    restore()
    isolation()
    germanBuild()
    dispatch("UNIT_SPELLCAST_SENT", "player", "Gevil", "F:1", 20757)
    assertEquals("Gevil", Tools.Soulstone.pending,
        "the SENT target is claimed through the localized family gate")
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "F:1", 20757)
    assertTrue(Tools.Soulstone:Active(),
        "the German-named family cast starts the stone window")
    assertEquals("Gevil", Tools.Soulstone:Target())
    assertEquals(1, Tools.Soulstone.casts)
    restore()
end)

test("locale: a German ritual cast predicts the channel", function()
    FX.LoadClassAddOn("WARLOCK")
    restore()
    germanBuild()
    Tools.Summon.channeling, Tools.Summon.target, Tools.Summon.start,
        Tools.Summon.duration, Tools.Summon.last = false, nil, nil, nil, nil
    dispatch("UNIT_SPELLCAST_SENT", "player", "Alice", "F:2", 698)
    assertTrue(Tools.Summon:Channeling(),
        "the German `Ritual of Summoning` reaches the summon family")
    assertEquals("Alice", Tools.Summon.target)
    dispatch("UNIT_SPELLCAST_CHANNEL_STOP", "player", "F:2", 698, "player", nil)
    assertFalse(Tools.Summon:Channeling())
    restore()
end)

test("locale: the healthstone bag count asks the client's item name", function()
    FX.LoadClassAddOn("WARLOCK")
    restore()
    german(true)
    -- The stone rows are item rows of the generated item data: their aliases
    -- ride the id join (Locale.BuildItemAliases), not the spell walk.
    Locale.englishByItemID[11732] = "Major Healthstone"
    Locale.englishToLocal["Major Healthstone"] = "Großer Heilstein"
    Locale.localizedToEnglish["Großer Heilstein"] = "Major Healthstone"
    germanItems(true)
    assertEquals(3, WK.DefaultHealthstoneCountReader(),
        "the count is summed over the client's German stone names")
    assertTrue(counts["Großer Heilstein"] ~= nil,
        "the read asked the localized item name")
    assertTrue(counts["Major Healthstone"] == nil,
        "the English data label was never asked of this client")
    restore()
end)

test("locale: the shard bag count asks the client's item name", function()
    FX.LoadClassAddOn("WARLOCK")
    restore()
    german(true)
    germanItems(true)
    -- The shard has no generated data row, so its alias is the item half the
    -- Locale records when a client name arrives for a tracked item id.
    Locale.englishByItemID[1128] = "Soul Shard"
    Locale.englishToLocal["Soul Shard"] = "Seelenscherbe"
    Locale.localizedToEnglish["Seelenscherbe"] = "Soul Shard"
    assertEquals(7, WK.DefaultShardCountReader(),
        "the shard count is read under the client's German item name")
    assertTrue(counts["Seelenscherbe"] ~= nil,
        "the read asked the localized shard name")
    restore()
end)

test("locale: the enUS gates keep asking the English names", function()
    FX.LoadClassAddOn("WARLOCK")
    restore()
    local asked = {}
    _G.C_Item = setmetatable({
        GetItemCount = function(name)
            asked[#asked + 1] = name
            return 0
        end,
    }, { __index = _C_Item })
    WK.DefaultHealthstoneCountReader()
    WK.DefaultShardCountReader()
    _G.C_Item = _C_Item
    assertTrue(#asked > 0, "the bag passes ran")
    for _ = 1, #asked do
        assertEquals("string", type(asked[_]))
    end
    assertEquals("Soul Shard", asked[#asked],
        "enUS: the shard is asked under its English data label")
    assertTrue(FX.MatchesFamily("Create Soulstone", WK.SoulstonePatterns),
        "the English family gate is unchanged")
    restore()
end)

-- ============================================================ shard alias
-- The 2026-11-04 uiforever finding (deDE client): a Warlock carrying four
-- Soul Shards reads x0. `C_Item.GetItemCount(6265)` = 4, the bag slot and
-- `C_Item.GetItemInfo(6265)` say `Seelensplitter`, but the counter asks
-- `FX.L("Soul Shard")` -- and the Locale item aliases rode only the
-- GENERATED item rows, so the data-less shard name had no alias and the
-- English string counted 0 on every non-English client. The fix is the
-- `Locale.RegisterItemName` seam and the `WK.SHARD_ITEMS = { [6265] =
-- "Soul Shard" }` registration: warm cache records the alias at the
-- module's init, a cold cache REQUESTS the id and the
-- GET_ITEM_INFO_RECEIVED reply records the alias AND re-reads the counter
-- (the `Locale.SubscribeLateNames` leg of `EnableEvents`). These tests
-- drive the real `WK.DefaultShardCountReader`, the real `Tools.Shards`
-- counter, the real Locale watch frame and the real registration path.

local SHARD_ID = 6265
local SHARD_DE = "Seelensplitter"          -- the live deDE name, measured
local shardCounts, shardRequests
local function shardSeam(on)
    if not on then
        if _C_Item ~= nil then _G.C_Item = _C_Item end
        shardCounts, shardRequests = nil, nil
        return
    end
    shardCounts, shardRequests = {}, {}
    _G.C_Item = setmetatable({
        -- The localized client counts the item under ITS name only.
        GetItemCount = function(name)
            shardCounts[name] = (shardCounts[name] or 0) + 1
            if name == SHARD_DE then return 4 end
            return 0
        end,
        RequestLoadItemDataByID = function(id)
            shardRequests[#shardRequests + 1] = id
        end,
    }, { __index = _C_Item })
end

test("locale: the registered shard counts under the client's German name",
function()
    FX.LoadClassAddOn("WARLOCK")
    restore()
    german(true)
    shardSeam(true)
    Locale.stubItemName = function(id)
        if id == SHARD_ID then return SHARD_DE end
        return nil
    end
    WK.RegisterShardItemAliases()
    assertEquals(SHARD_DE, Locale.LocalizedName("Soul Shard"),
        "the registration records the alias from the client's own id read")
    local count, source = Tools.Shards:Read()
    assertEquals(4, count,
        "the real shard counter reads the German-named bag (x0 before)")
    assertEquals("bag", source)
    assertTrue(shardCounts[SHARD_DE] ~= nil,
        "the read asked the client's shard name")
    assertTrue(shardCounts["Soul Shard"] == nil,
        "the English data label was never asked of this client")
    shardSeam(false)
    restore()
end)

test("locale: a cold-cache login self-corrects the shard count on the "
.. "late item name", function()
    FX.LoadClassAddOn("WARLOCK")
    restore()
    german(true)
    shardSeam(true)
    local cached = false
    Locale.stubItemName = function(id)
        if cached and id == SHARD_ID then return SHARD_DE end
        return nil
    end
    WK.RegisterShardItemAliases()
    assertEquals("Soul Shard", Locale.LocalizedName("Soul Shard"),
        "a cold cache has no alias yet")
    assertEquals(SHARD_ID, shardRequests[#shardRequests],
        "the registration REQUESTED the shard's item data")
    local before = Tools.Shards:Read()
    assertEquals(0, before, "the cold pass reads the English name: x0")
    -- The name arrives. Drive the REAL Locale watch frame the way the
    -- client does, with the tools' enable live (the late-name
    -- subscription -- and with it the self-correcting re-read -- rides it).
    cached = true
    local frame = Locale.WatchItemLoads()
    assertNotNil(frame, "the item-name watch frame exists")
    local handler = frame:GetScript("OnEvent")
    assertNotNil(handler, "the watch installs the handler")
    local wasEnabled = Tools._eventsEnabled
    if not wasEnabled then Tools:EnableEvents() end
    handler(frame, "GET_ITEM_INFO_RECEIVED", SHARD_ID, true)
    assertEquals(SHARD_DE, Locale.LocalizedName("Soul Shard"),
        "the arrival records the alias")
    local count, source = Tools.Shards:Count()
    assertEquals(4, count,
        "the late-name subscription re-read the counter: no bag event")
    assertEquals("bag", source)
    if not wasEnabled then
        Tools:DisableEvents()
        Tools._eventFrame = nil
    end
    shardSeam(false)
    restore()
end)

test("locale: on enUS the shard registration adds no alias and no request",
function()
    FX.LoadClassAddOn("WARLOCK")
    restore()
    local asked, requests = {}, {}
    _G.C_Item = setmetatable({
        GetItemCount = function(name)
            asked[#asked + 1] = name
            if name == "Soul Shard" then return 4 end
            return 0
        end,
        RequestLoadItemDataByID = function(id)
            requests[#requests + 1] = id
        end,
    }, { __index = _C_Item })
    WK.RegisterShardItemAliases()
    assertEquals(0, #requests, "the English client requests nothing")
    assertEquals(0, Locale.state.aliases, "the English client gains no alias")
    assertEquals("Soul Shard", FX.L("Soul Shard"), "FX.L stays the identity")
    local count = Tools.Shards:Read()
    assertEquals(4, count, "enUS counts under the English name as before")
    assertEquals("Soul Shard", asked[#asked],
        "the English name is what the pass asked")
    -- The registered row is durable: a Reset re-seeds it (the shard row is
    -- not lost), and the re-seed is labels only, no aliases.
    Locale.Reset()
    assertEquals("Soul Shard", Locale.englishByItemID[SHARD_ID],
        "the registered shard row survives Locale.Reset")
    assertEquals(0, Locale.state.aliases, "the re-seed records no alias")
    _G.C_Item = _C_Item
    restore()
end)
