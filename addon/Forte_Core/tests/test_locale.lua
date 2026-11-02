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
