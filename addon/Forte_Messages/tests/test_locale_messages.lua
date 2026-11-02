-- addon/Forte_Messages/tests/test_locale_messages.lua
-- H1b (docs/localization.md, the `Forte_Messages/Module.lua:357-407` and
-- `Pages/RaidMsg.lua:80-119` audit rows) on the German client, stubbed -- the
-- law of the Forte_Cooldown locale suite. Two lookup families here were
-- keyed on English words:
--
--   * the soulstone announce gate: the cast event's spellID resolves to the
--     CLIENT's name, the family patterns (`^Create Soulstone`, `^Soulstone`)
--     are the English data names -- a German warlock heard nothing;
--   * the CC fade/break registry: `P.FADE_SPELL_KEYS` / `FX.Timer
--     .FadeWarnings` are keyed on the generated data's names, the row keys
--     Forte_Timer publishes are English, and a row of a localized name
--     reached neither the prefix lookup nor the fade threshold.
--
-- The German stubs answer the generated row's id and the German name and
-- never the English data name, so these tests pass only through the
-- `FX.MatchesFamily` / `Locale.CanonicalName` joins.
local FX = ForteXorcist
local M = FX.Messages.Module
local P = FX.Messages.Pages
local Announce = FX.Messages.Announce
local Locale = FX.Locale
local _C_Spell = C_Spell

local DE_SPELL = {
    [20757] = "Seelenstein erstellen",  -- Create Soulstone (Warlock data)
    [12826] = "Verwandlung",            -- Polymorph (Mage data)
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
    else
        _G.C_Spell = _C_Spell
    end
end

local sent
local function installReaders()
    Announce.readers = {
        inLockdown = function() return false end,
        outgoingRestricted = function() return false end,
        isRaid = function() return false end,
        groupCount = function() return 4 end,
        send = function(text, chatType)
            sent[#sent + 1] = { text = text, chatType = chatType }
        end,
    }
    sent = {}
end
local function restoreAll()
    Announce.readers = {}
    if FX.SecretState then FX.SecretState.chat = nil end
end

local function enable()
    if not M.cfg then M:OnEnable() end
    if not M._eventFrame then M:OnEnable() end
end

-- The H1 pattern: Reset FIRST (it clears the stubs and the builder's
-- idempotence flag), then install the German seams, then build.
local function germanBuild()
    Locale.Reset()
    german(true)
    Locale.BuildSpellAliases()
end

local function dispatch(event, a1, a2, a3, a4)
    local f = M._eventFrame
    assertNotNil(f, "the soulstone watch's event frame exists once enabled")
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    onEvent(f, event, a1, a2, a3, a4)
end

test("locale: the soulstone announce gate reads the German cast name", function()
    FX.LoadClassAddOn("WARLOCK")
    enable()
    installReaders()
    M._ssPending = nil
    germanBuild()
    local real = FX.Settings
    real:Set("RaidMsg", "SoulstoneAnnounce", true)
    local before = M.counts.soulstone
    dispatch("UNIT_SPELLCAST_SENT", "player", "Vile Poacher", "G:1", 20757)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:1", 20757)
    assertEquals(before + 1, M.counts.soulstone,
        "the German-named family cast announced (the English compare was blind)")
    assertEquals(1, #sent)
    assertEquals("Soulstoned >> Vile Poacher << Use it well!", sent[1].text,
        "the original's text, verbatim")
    real:Set("RaidMsg", "SoulstoneAnnounce", false)
    german(false)
    Locale.Reset()
    Locale.BuildSpellAliases()
    restoreAll()
end)

test("locale: the fade/break rows meet the German row name", function()
    FX.LoadClassAddOn("MAGE")
    enable()
    installReaders()
    germanBuild()
    local W = FX.Timer and FX.Timer.FadeWarnings
    assertNotNil(W, "the fade registry is live")
    M:RefreshFadeWarnings()
    assertEquals("Verwandlung", FX.L("Polymorph"),
        "the alias map carries the German CC name")
    assertEquals(3, W["Polymorph"], "the English row key carries the threshold")
    assertEquals(3, W["Verwandlung"],
        "the localized row key carries the SAME threshold")
    local real = FX.Settings
    real:Set("RaidMsg", "PolymorphFadeParty", true)
    local before = M.counts.fading
    M:OnTimerFading("Verwandlung", "Gevil", "Crowds", 2.5)
    assertEquals(before + 1, M.counts.fading,
        "the German row name reaches the Polymorph prefix")
    assertEquals(1, #sent)
    assertContains(sent[1].text, "Polymorph on Gevil Fading in 3 seconds")
    local b0 = M.counts.broken
    M:OnTimerBroken("Verwandlung", "Gevil", "Crowds")
    assertEquals(b0 + 1, M.counts.broken,
        "the break row meets the German name the same way")
    real:Set("RaidMsg", "PolymorphFadeParty", false)
    german(false)
    Locale.Reset()
    Locale.BuildSpellAliases()
    W["Verwandlung"] = nil -- a localized key belongs to a localized client
    M:RefreshFadeWarnings()
    restoreAll()
end)

test("locale: the enUS gates keep asking the English names", function()
    FX.LoadClassAddOn("WARLOCK")
    enable()
    installReaders()
    german(false)
    Locale.Reset()
    Locale.BuildSpellAliases()
    assertTrue(FX.MatchesFamily("Create Soulstone", FX.SoulstonePatterns),
        "the English family gate is unchanged")
    assertFalse(FX.MatchesFamily("Use Soulstone", FX.SoulstonePatterns),
        "the family's exclusions hold")
    local W = FX.Timer.FadeWarnings
    assertEquals(3, W["Polymorph"], "the English fade key is published")
    assertNil(W["Verwandlung"],
        "an English client publishes no localized key at all")
    restoreAll()
end)

test("locale: the Seduction row's note says live on 70707, gated by pet casts", function()
    local seduction
    for _ = 1, #P.FADE_ROWS do
        if P.FADE_ROWS[_].prefix == "Seduction" then seduction = P.FADE_ROWS[_] end
    end
    assertNotNil(seduction, "the page ships the Seduction row")
    local note = seduction.note or ""
    assertTrue(note:find("pet") ~= nil,
        "the tip names the pet-cast gate (the review 4 E2 census law)")
    assertTrue(note:find("70707") ~= nil,
        "the tip records that the pair IS live on the live build's spell store")
    assertNil(note:find("no spell named", 1, true),
        "the superseded 70425 'no such spell' claim is gone from the page")
    assertNotNil(P.FADE_SPELL_KEYS.Mesmerize,
        "Mesmerize keeps sharing the Seduction rows (Warlock.lua:250)")
end)
