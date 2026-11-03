local FX = ForteXorcist
local Locale = FX.Locale

-- H1 Localization: the alias bridge's own law (the German-stub suites in
-- Forte_Cooldown/Forte_Timer cover the consumers).

test("locale: the module is loaded and FX.L is the display seam", function()
    assertNotNil(Locale, "Forte_Core ships the Locale module")
    assertNotNil(FX.L, "FX.L exists")
    assertNotNil(Locale.state, "the module's state exists")
end)

test("locale: nil and unknown names pass through unchanged", function()
    assertEquals(nil, Locale.CanonicalName(nil), "nil canonicalizes to nil")
    assertEquals(nil, Locale.LocalizedName(nil), "nil displays as nil")
    assertEquals("Schnellfeuer", Locale.CanonicalName("Schnellfeuer"),
        "an unknown name is its own canonical name")
end)

-- The profile class's own data set (Paladin: loaded at login, no LoD load
-- needed in this suite): Reckoning's generated row 31216.
test("locale: the alias maps round-trip localized names", function()
    Locale.Reset()
    -- The seam the builds write through (record()): seeded here so this
    -- unit proves the lookup seams themselves; the build legs are proven in
    -- the Forte_Cooldown/Forte_Timer locale suites.
    Locale.localizedToEnglish["Heiliger Zorn"] = "Reckoning"
    Locale.englishToLocal["Reckoning"] = "Heiliger Zorn"
    Locale.idsByEnglish["Reckoning"] = { 31216 }
    assertEquals("Reckoning", Locale.CanonicalName("Heiliger Zorn"),
        "the localized name canonicalizes to the data key")
    assertEquals("Heiliger Zorn", FX.L("Reckoning"),
        "FX.L displays the localized name (the FW:SpellName law)")
    assertEquals("Rapid Fire", Locale.CanonicalName("Rapid Fire"),
        "the data key passes through")
    assertEquals(31216, (Locale.RankIDsForName("Reckoning") or {})[1],
        "the rank ids ride the data key")
    assertEquals(nil, Locale.RankIDsForName("Nothing Of Ours"),
        "an unknown name has no rank ids")
    Locale.Reset()
    assertEquals("Heiliger Zorn", Locale.CanonicalName("Heiliger Zorn"),
        "the reset drops the alias")
end)

-- Manager regression (2026-11-02): the late item-name dispatch called an
-- undefined FX:CallSafe, so the FIRST late name on a non-English client raised
-- and no subscriber (the Cooldown item rescan) ever ran.
test("locale: a late item name wakes every subscriber, a raising one is contained", function()
    Locale.Reset()
    local savedStub, savedSubs = Locale.stubItemName, Locale.onLateNames
    Locale.onLateNames = {}
    Locale.englishByItemID[999001] = "Test Trinket"
    Locale.stubItemName = function(id) if id == 999001 then return "Testschmuck" end end
    local woke = {}
    Locale.SubscribeLateNames(function() error("subscriber boom") end)
    Locale.SubscribeLateNames(function(id) woke[#woke + 1] = id end)
    local ok, err = pcall(Locale.OnItemNameArrived, 999001)
    Locale.stubItemName, Locale.onLateNames = savedStub, savedSubs
    Locale.englishByItemID[999001] = nil
    assertTrue(ok, "the dispatch never raises: " .. tostring(err))
    assertEquals(1, #woke, "the healthy subscriber ran despite the raising one")
    assertEquals(999001, woke[1], "the subscriber got the item id")
    assertEquals("Test Trinket", Locale.CanonicalName("Testschmuck"), "the alias was recorded")
    Locale.Reset()
end)

test("locale: an enUS client is a no-op", function()
    Locale.Reset()
    assertEquals(0, Locale.BuildSpellAliases(), "no aliases on enUS")
    assertEquals("Polymorph", FX.L("Polymorph"), "FX.L is the identity")
    assertNil(FX.Data.PaladinByName["Heiliger Zorn"], "no localized keys")
end)

test("locale: item aliases and the cold-cache request path", function()
    local items = FX.Data and FX.Data.Items
    assertNotNil(items, "the generated item data is loaded")
    Locale.Reset()
    Locale.stubLocale = function() return "deDE" end
    Locale.stubItemName = function(id)
        if id == 19336 then return "Arkane Verstaerkte Essenz" end
    end
    Locale.BuildItemAliases(items)
    assertEquals("Arcane Infused Gem",
        Locale.CanonicalName("Arkane Verstaerkte Essenz"),
        "the localized item name canonicalizes to the data row name")
    assertEquals("Arcane Infused Gem", Locale.EnglishItemName(19336),
        "the id join carries the data label")
    Locale.Reset()
end)

-- Code-review-5 M3: the frame is the ONE place the build pins the
-- late-arrival contract. The direct `Locale.OnItemNameArrived(itemID)` calls
-- (the manager-regression test above, Forte_Cooldown's
-- test_locale_cooldown.lua:138) pass a swapped shape: the catalog hands BOTH
-- events as (itemID, success) (ItemDocumentation), and the frame's gate --
-- a `success == false` reply carries no name -- is the contract. Drive the
-- real frame's OnEvent with the exact client payload.
test("locale: the item-load events ride the real frame in (itemID, success)",
function()
    Locale.Reset()
    local frame = Locale.WatchItemLoads()
    assertNotNil(frame, "the watch builds the frame")
    assertEquals(frame, Locale.WatchItemLoads(), "the watch is idempotent")
    local handler = frame:GetScript("OnEvent")
    assertNotNil(handler, "the watch installs the handler")
    local savedStub, savedSubs = Locale.stubItemName, Locale.onLateNames
    Locale.onLateNames = {}
    Locale.stubItemName = function(id)
        if id == 999001 then return "Testschmuck" end
        if id == 999002 then return "Testelixier" end
        if id == 999003 then return "Testtrank" end
    end
    Locale.englishByItemID[999001] = "Test Trinket"
    Locale.englishByItemID[999002] = "Test Elixir"
    Locale.englishByItemID[999003] = "Test Potion"
    local woke = {}
    Locale.SubscribeLateNames(function(id) woke[#woke + 1] = id end)
    local lateBefore = Locale.state.lateNames
    -- GET_ITEM_INFO_RECEIVED's success leg resolves the alias.
    handler(frame, "GET_ITEM_INFO_RECEIVED", 999001, true)
    assertEquals("Test Trinket", Locale.CanonicalName("Testschmuck"),
        "the success leg resolved the alias through the frame")
    assertEquals(1, #woke, "the frame leg woke the subscriber")
    assertEquals(999001, woke[1], "the subscriber got the payload's itemID")
    -- The second registered event, the same shape.
    handler(frame, "ITEM_DATA_LOAD_RESULT", 999002, true)
    assertEquals("Test Elixir", Locale.CanonicalName("Testelixier"),
        "ITEM_DATA_LOAD_RESULT resolves through the frame too")
    assertEquals(lateBefore + 2, Locale.state.lateNames,
        "the two arrivals counted once each")
    -- The success == false gate: a failed load carries no name, and the id
    -- stays unresolved (the stub would resolve it, so the gate is the leg
    -- that speaks here).
    handler(frame, "GET_ITEM_INFO_RECEIVED", 999003, false)
    assertEquals("Testtrank", Locale.CanonicalName("Testtrank"),
        "a failed load stayed unresolved")
    assertEquals(2, #woke, "a failed load wakes nobody")
    -- An event the frame does not know says nothing.
    handler(frame, "GET_SPELL_AURAS_CHANGED", 999001, true)
    assertEquals(2, #woke, "an unregistered event wakes nobody")
    Locale.stubItemName, Locale.onLateNames = savedStub, savedSubs
    Locale.Reset()
end)

-- H1b (docs/localization.md, the `Forte_Core/Core/Constants.lua:29` audit
-- row): the soulstone family is declared as ENGLISH NAME PATTERNS
-- (`{ "^Create Soulstone", "^Soulstone" }`), and two add-ons match the
-- CLIENT's cast names against them. `FX.MatchesFamily` is the shared gate:
-- canonicalize the client name onto the data key, run the patterns on that
-- key, and keep the raw name as the leg for the half of a family no
-- generated row carries ("Soulstone Resurrection" is in the spec, not in the
-- data). On an English client CanonicalName is the identity, so the gate is
-- the plain `find` it always was.
test("locale: the family gate canonicalizes the client name first", function()
    Locale.Reset()
    Locale.localizedToEnglish["Seelenstein erstellen"] = "Create Soulstone"
    Locale.englishToLocal["Create Soulstone"] = "Seelenstein erstellen"
    assertTrue(FX.MatchesFamily("Seelenstein erstellen", FX.SoulstonePatterns),
        "the German cast name reaches the English family pattern")
    assertTrue(FX.MatchesFamily("Create Soulstone", FX.SoulstonePatterns),
        "the English data name matches as before")
    assertTrue(FX.MatchesFamily("Soulstone Resurrection", FX.SoulstonePatterns),
        "the spec-only member matches on the raw leg (no alias to ride)")
    assertFalse(FX.MatchesFamily("Use Soulstone", FX.SoulstonePatterns),
        "the family's exclusion is the pattern's law")
    assertFalse(FX.MatchesFamily("Heilstein erstellen", FX.SoulstonePatterns),
        "an unrelated German name is not in the family")
    assertFalse(FX.MatchesFamily(nil, FX.SoulstonePatterns),
        "a nil name is not in a family")
    Locale.Reset()
    assertFalse(FX.MatchesFamily("Seelenstein erstellen", FX.SoulstonePatterns),
        "with no alias the German name is not in the family (enUS shape)")
end)

-- Code-review-5 m7: the item watch's own tear-down. The module's disable
-- hook used to call `frame:UnregisterEvent(...)` straight out, against the
-- tree's guarded disable law (Forte_Hunter/UI/Swing.lua:926-941,
-- Forte_Warlock/Core/Comms.lua:639-646, Forte_Shaman/Core/Totems.lua:347-353):
-- the method is catalog-declared for the REAL client's Frame and absent from
-- the simulator's frame emulation, and a restricted client may raise on it,
-- so the hook the loader runs on every disable died on its first line -- the
-- module tore down half its own state. The hook is nil-guarded and pcall'd
-- now; this drives the REAL hook against the real frame (the shape that used
-- to raise) and against a frame whose method raises.
test("locale: the item-watch disable survives the frame shapes", function()
    local mod = FX.modules and FX.modules["Locale"]
    assertNotNil(mod, "the Locale module is registered")
    assertNotNil(mod.OnDisable, "the module ships a disable hook")
    local frame = Locale.WatchItemLoads()
    assertNotNil(frame, "the watch builds the frame")
    local ok, err = pcall(mod.OnDisable)
    assertTrue(ok, "the disable raised on this client's frame: " .. tostring(err))
    -- The idempotence half: a second pass with nothing left to do.
    local ok2, err2 = pcall(mod.OnDisable)
    assertTrue(ok2, "the second disable raised: " .. tostring(err2))
    -- The restricted-client half: the method exists and raises.
    local saved = Locale.state.frame
    Locale.state.frame = {
        UnregisterEvent = function()
            error("FXTEST: the un-register is sealed")
        end,
    }
    local ok3, err3 = pcall(mod.OnDisable)
    Locale.state.frame = saved
    assertTrue(ok3, "a raising UnregisterEvent escaped the disable: "
        .. tostring(err3))
    -- The handle rides on, so the watch's pair has one home and a re-enable
    -- re-runs against the same frame it registered on.
    assertEquals(frame, Locale.WatchItemLoads(),
        "the watch is idempotent on the frame handle")
    assertNotNil(Locale.state.frame, "the disable kept the frame handle")
end)
