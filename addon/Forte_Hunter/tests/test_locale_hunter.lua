-- addon/Forte_Hunter/tests/test_locale_hunter.lua
-- H1b (docs/localization.md, the `Forte_Hunter/Core/Tools.lua:271` audit row)
-- on the German client, stubbed -- the law of the Forte_Cooldown locale
-- suite. Two lookups in the Hunter tools used to be keyed on English words:
--
--   * the cast seam: `C_Spell.GetSpellInfo(spellID).name` answers the
--     CLIENT's name, while the aspect set is derived from the generated data
--     by the `^Aspect of` DATA-name pattern -- so a `Aspekt des Falken` cast
--     matched nothing and the aspect reminder never stopped;
--   * the out-of-combat reconcile: `C_UnitAuras.GetAuraDataBySpellName`
--     resolves a NAME in the client's table, and the English data name is not
--     in a German one, so every aspect read answered "absent" and a real
--     prediction was cleared out of existence.
--
-- The German stubs below answer the generated row's ID and the German name,
-- and NEVER the English data name, so these tests pass only when the module
-- resolves through the id/alias joins (the `Locale.RankIDsForName` +
-- `Locale.CanonicalName` legs of Core/Tools.lua).
local FX = ForteXorcist
local Tools = FX.Hunter.Tools
local Locale = FX.Locale
local _C_Spell, _C_UnitAuras, _IsPlayerSpell = C_Spell, C_UnitAuras, IsPlayerSpell

-- The generated ForteXorcist.Data.Hunter aspect rows (Core/Tools.lua's
-- `^Aspect of` family); the ids are the data's own, the join key
-- Locale.BuildSpellAliases walks.
local DE_SPELL = {
    [5118] = "Aspekt der Cheetah",      -- Aspect of the Cheetah
    [469145] = "Aspekt des Falken",     -- Aspect of the Falcon
    [25296] = "Aspekt des Habichts",    -- Aspect of the Hawk
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
                -- A German client resolves ITS names, never the data's.
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

-- The aura seam. `active` is the aspect the German client reports on the
-- player; the id lookup answers the id, the name lookup only the German name
-- -- an English data name answers "no such aura" exactly as the live
-- localized client answers it.
local active
local function germanAuras(on)
    if not on then
        if _C_UnitAuras ~= nil then _G.C_UnitAuras = _C_UnitAuras end
        active = nil
        return
    end
    _G.C_UnitAuras = setmetatable({
        GetPlayerAuraBySpellID = function(id)
            if active ~= nil and id == active then
                return { name = DE_SPELL[id] or "?" }
            end
            return nil
        end,
        GetAuraDataBySpellName = function(_, name)
            for id, de in pairs(DE_SPELL) do
                if de == name and id == active then return { name = de } end
            end
            return nil
        end,
    }, { __index = _C_UnitAuras })
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
    germanAuras(false)
    Locale.Reset()
    Tools.Aspects.current = nil
end

--- Drive the module's OWN event script. The frame is the public kick path
--- (the Forte_Hunter suite's law: no private handler is called, no render).
local function dispatch(event, a1, a2, a3)
    local wasEnabled = Tools._eventsEnabled
    if not wasEnabled then Tools:EnableEvents() end
    local f = Tools._eventFrame
    assertNotNil(f, "the tools' event frame exists once enabled")
    local h = f:GetScript("OnEvent")
    assertEquals("function", type(h))
    local ok, err = pcall(h, f, event, a1, a2, a3)
    if not wasEnabled then
        Tools:DisableEvents()
        Tools._eventFrame = nil
    end
    assertTrue(ok, tostring(err))
end

test("locale: the aspect family is the data's, the alias carries German", function()
    FX.LoadClassAddOn("HUNTER")
    restore()
    germanBuild()
    assertEquals("Aspekt des Falken", FX.L("Aspect of the Falcon"),
        "FX.L displays the client's German aspect name")
    assertEquals("Aspect of the Falcon",
        Locale.CanonicalName("Aspekt des Falken"),
        "the German name canonicalizes onto the data key")
    local sawFalcon = false
    for _ = 1, #Tools.aspectNames do
        if Tools.aspectNames[_] == "Aspect of the Falcon" then sawFalcon = true end
    end
    assertTrue(sawFalcon, "the derived family is keyed on the data's names")
    restore()
end)

test("locale: a German aspect cast is adopted under the data key", function()
    FX.LoadClassAddOn("HUNTER")
    restore()
    germanBuild()
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "F:1", 469145)
    assertEquals("Aspect of the Falcon", Tools.Aspects:Current(),
        "the German-named cast reaches the data-keyed aspect tracker")
    assertFalse(Tools.Aspects:Missing(),
        "the reminder is satisfied: an aspect is known active")
    restore()
end)

test("locale: the out-of-combat reconcile reads the German client's aura", function()
    FX.LoadClassAddOn("HUNTER")
    restore()
    germanBuild()
    germanAuras(true)
    active = 469145
    Tools.Aspects.current = nil
    assertEquals("adopted", Tools.Aspects:Reconcile(),
        "the plain aura read reaches the aspect through the data row id")
    assertEquals("Aspect of the Falcon", Tools.Aspects:Current(),
        "the reconcile adopted the data-keyed aspect")
    active = nil
    assertEquals("cleared", Tools.Aspects:Reconcile(),
        "every aspect confirmed absent clears the tracker")
    restore()
end)

test("locale: the enUS aura seam keeps asking the English data name", function()
    FX.LoadClassAddOn("HUNTER")
    restore()
    local asked = {}
    _G.C_UnitAuras = setmetatable({
        GetAuraDataBySpellName = function(_, name)
            asked[#asked + 1] = name
            return nil
        end,
        GetPlayerAuraBySpellID = function(id)
            asked[#asked + 1] = id
            return nil
        end,
    }, { __index = _C_UnitAuras })
    Tools.Aspects:Reconcile()
    _G.C_UnitAuras = _C_UnitAuras
    assertTrue(#asked > 0, "the reconcile pass ran")
    for _ = 1, #asked do
        assertEquals("string", type(asked[_]),
            "enUS: the reader asks the English data name (bit-identical)")
    end
    restore()
end)
