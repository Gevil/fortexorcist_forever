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
local DE_SPELL = { [3045] = "Schnellfeuer",                 -- Rapid Fire
                   [20554] = "Berserken" }                  -- Berserking (M2)
-- The M3a German Berserking leg builds the DRUID kit on the stubbed German
-- client: Build's known-gate is the data-id path, so the druid needs at
-- least one NON-racial id the stub knows or the kit count is legitimately 0
-- (the Berserking row is `racial = true` -- Build excludes it by contract
-- and AddExtras enlists it; that split is the review-10 M2 law this leg
-- pins). Barkskin stands in for the druid's German client table.
DE_SPELL[22812] = "Rindenschild"                           -- Barkskin (M3a kit sample)
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
        "the identity on enUS")
    assertEquals("Schnellfeuer", Locale.CanonicalName("Schnellfeuer"),
        "with no alias the German name is its own key")
end)

-- ============================================================= H1b reads ==
-- The second half of the localization law: `C_Spell.GetSpellCooldown`,
-- `GetSpellCharges`, `GetSpellCooldownDuration` and `GetSpellTexture` all
-- take a SpellIdentifier (the pinned catalog, SpellDocumentation), and the
-- read pass used to hand them the ENGLISH DATA NAME. On the German client
-- below the name is a string the client's spell table does not contain, so
-- the whole read ladder answered "nothing" -- predictions never got
-- certified, the charges bar was never measured, the pop icon was nil. The
-- data row's id is the other half of the same identifier, locale-free, and it
-- is what Module.lua's `readKey` now hands the reads.
--
-- The German C_Spell stub is the strict half on purpose: it resolves a
-- NUMBER id and NOTHING else (an English name answers nil, the way a real
-- deDE client answers a name it does not have), so a test that passes only
-- because the stub is generous proves nothing.

local readHits  -- [spellIdentifier] = calls, every read the Module made

local function germanReads(on)
    if not on then
        _G.C_Spell = _C_Spell
        readHits = nil
        return
    end
    readHits = {}
    local function record(id)
        readHits[id] = (readHits[id] or 0) + 1
    end
    local function knownInfo(id)
        -- Rapid Fire (data row 3045): 300 s, 30 s gone.
        if id ~= 3045 then return nil end
        return {
            startTime = 1000, duration = 300, modRate = 1, isEnabled = true,
            isActive = true, isOnGCD = false,
            spellID = 3045, name = DE_SPELL[3045], icon = "INTERFACE\\ICONS\\RF",
        }
    end
    _G.C_Spell = setmetatable({
        GetSpellInfo = function(x)
            if type(x) == "number" then
                local name = DE_SPELL[x]
                if name then return { spellID = x, name = name } end
                return nil
            end
            return nil -- an English name is not in the German table
        end,
        GetSpellCooldown = function(id)
            record(id)
            return knownInfo(id)
        end,
        GetSpellCharges = function(id)
            record(id)
            if id ~= 3045 then return nil end
            return {
                currentCharges = 1, maxCharges = 2, cooldownStartTime = 0,
                cooldownDuration = 0, chargeModRate = 1, isActive = false,
            }
        end,
        GetSpellTexture = function(id)
            record(id)
            local info = knownInfo(id)
            return info and info.icon or nil
        end,
        GetSpellCooldownDuration = function(id)
            record(id)
            return nil -- tier 3 off: the numeric tier carries this test
        end,
    }, { __index = _C_Spell })
end

test("locale: the read pass reads by data id on a German client", function()
    FX.LoadClassAddOn("HUNTER")
    Locale.Reset()
    german(true)
    Locale.BuildSpellAliases()
    local n = Engine:Build("HUNTER", M.IsKnown)
    assertTrue(type(n) == "number" and n > 0, "the set built")
    germanReads(true)
    local now = GetTime()
    M:ReadAll()
    local rf = Engine.entries["Rapid Fire"]
    assertNotNil(rf,
        "the numeric read reached the row (the English-name read is blind here)")
    assertEquals("read", rf.source, "the entry is a certified read, not a prediction")
    assertTrue(rf.anchored == true, "the plain read certified the window")
    assertTrue((readHits[3045] or 0) > 0,
        "the read carried the data row's id")
    assertTrue(readHits["Rapid Fire"] == nil,
        "no read ever carried the English data name")
    germanReads(false)
    Engine.entries["Rapid Fire"] = nil
    rebuildEnglish()
end)

test("locale: the charges sweep measures by data id on a German client", function()
    FX.LoadClassAddOn("HUNTER")
    Locale.Reset()
    german(true)
    Locale.BuildSpellAliases()
    Engine:Build("HUNTER", M.IsKnown)
    germanReads(true)
    Engine:DetectCharges(M.ReadChargesFor)
    local rf = Engine.tracked["Rapid Fire"]
    assertNotNil(rf, "Rapid Fire is tracked")
    assertEquals(2, rf.maxCharges,
        "the NeverSecret maxCharges was measured through the id path")
    germanReads(false)
    rf.maxCharges = nil
    rebuildEnglish()
end)

test("locale: the ready pop resolves its icon by data id on a German client", function()
    FX.LoadClassAddOn("HUNTER")
    Locale.Reset()
    german(true)
    Locale.BuildSpellAliases()
    Engine:Build("HUNTER", M.IsKnown)
    germanReads(true)
    -- A live entry that lapses now: ProcessReadyPops pops it and resolves the
    -- icon through the Module's own read (the pop/splash/bus contract).
    Engine.entries["Rapid Fire"] = {
        name = "Rapid Fire", start = 1000, duration = 300,
        endTime = 1300, predicted = false, source = "read",
    }
    local seen = {}
    local handle = FX.On(FX.EVENTS.COOLDOWN_READY,
        function(name, at, texPath) seen[name] = texPath end)
    M:ProcessReadyPops(1301)
    if handle then FX.Off(handle) end
    assertNotNil(seen["Rapid Fire"], "the pop fired")
    assertEquals("INTERFACE\\ICONS\\RF", seen["Rapid Fire"],
        "the pop's icon resolved through the data row id")
    germanReads(false)
    Engine.entries["Rapid Fire"] = nil
    rebuildEnglish()
end)

test("locale: the enUS read pass keeps asking the English name", function()
    german(false)
    Locale.Reset()
    Locale.BuildSpellAliases()
    FX.LoadClassAddOn("HUNTER")
    local asked = {}
    local real = _G.C_Spell
    _G.C_Spell = setmetatable({
        GetSpellCooldown = function(id)
            asked[#asked + 1] = id
            return nil
        end,
        GetSpellCharges = function() return nil end,
        GetSpellCooldownDuration = function() return nil end,
    }, { __index = real })
    Engine:Build("HUNTER", function() return true end)
    M:ReadAll()
    _G.C_Spell = real
    assertTrue(#asked > 0, "the pass ran")
    for _, id in ipairs(asked) do
        assertEquals("string", type(id),
            "enUS: the English data name is the read key (bit-identical)")
    end
    rebuildEnglish()
end)

-- ============================================================ M3a racials ==
-- review-10 M2's repro, now the pin: on the German client the racial's
-- name is the CLIENT's word. Pre-M3a the Engine hand-keyed "Berserking"
-- (English) -- `Locale.CanonicalName("Berserken")` had no alias to ride
-- (the data named the name on no row), the racial never entered `tracked`,
-- and casting it drew nothing. Wave M3a moved the row into the GENERATED
-- data (the druid's Troll roster), so BuildSpellAliases registers
-- Berserken -> Berserking off the data row + the client's own name, the
-- known-gate rides the row id (locale-free, IsPlayerSpell(20554)), and the
-- cast -- the client's word canonicalized onto the data key -- lands.
test("locale: the German Berserking rides tracked and its cast lands (M3a)",
function()
    -- Every seam german(true) takes (the Locale stubs, _G.C_Spell,
    -- _G.IsPlayerSpell) rides rebuildEnglish at the end; an assert that
    -- throws mid-leg must not strand the German client for the files that
    -- sort after this one (the stub leak once red-spread through
    -- test_reconcile / test_tiers / test_test_mode / test_zz_* -- readKey
    -- flips to the id path the moment a German stubLocale lives on).
    local ok, err = pcall(function()
    FX.LoadClassAddOn("DRUID")
    Locale.Reset()
    german(true)
    local added = Locale.BuildSpellAliases()
    assertTrue(added > 0, "the German client registers aliases")
    assertEquals("Berserking", Locale.CanonicalName("Berserken"),
        "the client's word canonicalizes onto the generated data key")
    local n = Engine:Build("DRUID", M.IsKnown)
    assertTrue(type(n) == "number" and n > 0, "the druid kit built")
    assertNil(Engine.tracked["Berserking"],
        "Build keeps its class-kit contract (the racials ride AddExtras)")
    assertTrue(Engine:AddExtras(M.IsKnown) >= 1,
        "the id half of the known-gate enlists the racial")
    local t = Engine.tracked["Berserking"]
    assertNotNil(t, "the localized Berserking is tracked off the data row")
    assertEquals(20554, t.dataId)
    assertTrue(math.abs(t.baseDuration - 180) < 1e-6,
        "the owner's measured 180 s rides the generated row")
    -- The cast event arrives with the client's word; the Module's cast path
    -- canonicalizes it (Locale.CanonicalName is that resolve) and the
    -- Engine starts the bar.
    local e = Engine:OnCast(Locale.CanonicalName("Berserken"), 1000)
    assertNotNil(e, "the German Berserking cast drew no bar")
    assertAlmostEquals(180, e.endTime - e.start, 1e-6)
        Engine.entries["Berserking"] = nil
    end)
    rebuildEnglish()
    if not ok then error(err, 0) end
end)
