local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local Items = Engine and Engine.Items
local M = FX.Cooldown.Module
local Locale = FX.Locale
local _C_Spell, _IsPlayerSpell = C_Spell, IsPlayerSpell

-- H1 Localization: the German client, stubbed. wow-ui-sim is enUS-FIXED (a
-- non-enUS text locale is not modelled there), so the client seams --
-- GetLocale, the Locale module's name seams, the C_Spell name lookups, the
-- spell-known seam and the inventory readers -- are the test's stub surface.
-- Generated-data ids stand in for the client spell ids (the sim resolves
-- 3045 to nil; the data row's id IS the join key isKnown now uses).
local DE_SPELL = { [3045] = "Schnellfeuer" }                    -- Rapid Fire
local DE_ITEM = { [19336] = "Arkane Verstaerkte Essenz" }       -- Arcane Infused Gem

local function german(on)
    Locale.stubLocale = on and function() return "deDE" end or nil
    Locale.stubSpellName = on and function(id) return DE_SPELL[id] end or nil
    Locale.stubItemName = on and function(id) return DE_ITEM[id] end or nil
    if on then
        local real = _C_Spell
        _G.C_Spell = setmetatable({
            GetSpellInfo = function(x)
                if type(x) == "number" then
                    local name = DE_SPELL[x]
                    if name then return { spellID = x, name = name } end
                    if real and real.GetSpellInfo then return real.GetSpellInfo(x) end
                    return nil
                end
                -- The German client resolves ITS names, never the English
                -- ones the generated data carries.
                if type(x) == "string" then
                    for id, name in pairs(DE_SPELL) do
                        if name == x then return { spellID = id, name = name } end
                    end
                    return nil
                end
                return nil
            end,
        }, { __index = real })
        _G.IsPlayerSpell = function(id) return DE_SPELL[id] ~= nil end
    else
        _G.C_Spell = _C_Spell
        _G.IsPlayerSpell = _IsPlayerSpell
    end
end

local function rebuildEnglish()
    german(false)
    Locale.Reset()
    Locale.BuildSpellAliases()
    Engine:Build(FX._playerClass, function() return true end)
    if Items then Items:Rescan() end
end


test("locale: the alias maps carry the German client's names", function()
    assertNotNil(Locale, "Forte_Core ships the Locale module")
    FX.LoadClassAddOn("HUNTER")
    Locale.Reset()
    german(true)
    Locale.BuildSpellAliases()
    assertEquals("Rapid Fire", Locale.CanonicalName("Schnellfeuer"),
        "the German name canonicalizes to the generated data key")
    assertEquals("Schnellfeuer", FX.L("Rapid Fire"),
        "FX.L displays the German client's name (the FW:SpellName law)")
    assertEquals("Rapid Fire", Locale.CanonicalName("Rapid Fire"),
        "an English name passes through")
    assertEquals("Schnellfeuer",
        FX.L(Locale.CanonicalName("Schnellfeuer")),
        "the display seam round-trips")
    rebuildEnglish()
end)

test("locale: the build path tracks by data id with the name lookups dead", function()
    FX.LoadClassAddOn("HUNTER")
    Locale.Reset()
    german(true)
    Locale.BuildSpellAliases()
    local n = Engine:Build("HUNTER", M.IsKnown)
    assertTrue(type(n) == "number" and n > 0,
        "the set built with every English name lookup dead (n=" .. tostring(n) .. ")")
    local rf = Engine.tracked["Rapid Fire"]
    assertNotNil(rf, "Rapid Fire is tracked through its data row id")
    assertNil(Engine.tracked["Schnellfeuer"],
        "the client's name is never a key")
    rebuildEnglish()
end)

test("locale: the cast name canonicalizes onto the tracked key", function()
    FX.LoadClassAddOn("HUNTER")
    Locale.Reset()
    german(true)
    Locale.BuildSpellAliases()
    assertEquals("Rapid Fire", Locale.CanonicalName("Schnellfeuer"),
        "the Module's cast-name resolve reaches the tracked data key")
    local ids = Locale.RankIDsForName("Rapid Fire")
    assertEquals(3045, ids and ids[1],
        "the data row id drives the locale-free known check")
    rebuildEnglish()
end)

test("locale: the trinket name join carries the localized item name", function()
    Locale.Reset()
    german(true)
    Locale.BuildItemAliases(FX.Data.Items)
    Locale.AddTableAlias(FX.Data.Items.OnUseByName, "Arcane Infused Gem",
        "Arkane Verstaerkte Essenz", FX.Data.Items.OnUseByName["Arcane Infused Gem"])
    assertEquals("Arcane Infused Gem",
        Locale.CanonicalName("Arkane Verstaerkte Essenz"),
        "the localized bag name canonicalizes to the on-use row key")
    assertEquals("Arcane Infused Gem", Locale.EnglishItemName(19336),
        "the id join carries the data label")
    rebuildEnglish()
end)

test("locale: an enUS client adds zero aliases", function()
    german(false)
    Locale.Reset()
    local added = Locale.BuildSpellAliases()
    assertEquals(0, added, "the English client builds no aliases")
    assertEquals("Rapid Fire", FX.L("Rapid Fire"),
        "FX.L is the identity on enUS")
    assertEquals("Schnellfeuer", Locale.CanonicalName("Schnellfeuer"),
        "with no alias the German name is its own key")
end)
