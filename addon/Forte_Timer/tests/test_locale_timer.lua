local FX = ForteXorcist
local Registry = FX.Timer.Registry
local Casts = FX.Timer.Casts
local Rows = FX.Timer.Rows
local Locale = FX.Locale

-- H1 Localization (German stub, the law of the Forte_Cooldown locale suite):
-- a Polymorph cast on a deDE client is named `Verwandlung` by the client;
-- the row key space stays the generated data's English name, and the
-- Registry's alias table carries the localized name.
local DE_SPELL = { [12826] = "Verwandlung" }      -- Polymorph (data row)

local function german(on)
    Locale.stubLocale = on and function() return "deDE" end or nil
    Locale.stubSpellName = on and function(id) return DE_SPELL[id] end or nil
end

local function restore()
    german(false)
    Locale.Reset()
    Locale.BuildSpellAliases()
    Registry:Build(FX._playerClass)
    Casts.resolveName = nil
    Casts.now = nil
end


test("locale: the Registry carries the localized name as an alias", function()
    FX.LoadClassAddOn("MAGE")
    Locale.Reset()
    german(true)
    Locale.BuildSpellAliases()
    assertEquals("Verwandlung", FX.L("Polymorph"),
        "the alias map carries the German name")
    local n = Registry:Build("MAGE")
    assertTrue(type(n) == "number" and n > 0, "the registry built")
    local poly = Registry.entries["Polymorph"]
    assertNotNil(poly, "the English data key owns the row")
    assertEquals(poly, Registry.entries["Verwandlung"],
        "the German name resolves to the SAME entry table")
    assertEquals(poly.kind, Registry.KindFor("Verwandlung"),
        "KindFor of the German name reaches the Polymorph kind")
    restore()
end)

test("locale: a German cast name canonicalizes to the row key", function()
    FX.LoadClassAddOn("MAGE")
    Locale.Reset()
    german(true)
    Locale.BuildSpellAliases()
    Casts.resolveName = function(spellID) return DE_SPELL[spellID] end
    assertEquals("Polymorph", Casts:NameOf(12826),
        "NameOf of the client's Verwandlung id keys rows on the data name")
    Casts.resolveName = nil
    restore()
end)
