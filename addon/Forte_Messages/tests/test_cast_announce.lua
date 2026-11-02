-- addon/Forte_Messages/tests/test_cast_announce.lua
-- The 20 own-cast announce rows (wave 2b T2, `docs/class-port.md` S17: the
-- `CA:RegisterOnSelfCastSuccess` + `CA:CastShow` raid warnings of
-- Druid.lua:190-227, Paladin.lua:125-168, Warrior.lua:79-104) driven through
-- the SAME legality gate the soulstone row rides, on the SAME cast frame.
-- The laws under test:
--   * the send goes through `Announce:Group`/`Announce:Channel`, so an
--     unrestricted cast SENDS and a locked one is SKIPPED AND COUNTED;
--   * the shipped default of every one of the 40 send keys is OFF (the
--     manager ruling of 2026-11-02, review 4 E2) while the TEXTS stay
--     verbatim, and every row's source `{[0]=bits}` value is recorded in
--     its note (the source's own Vigilance row is the bits-0 one);
--   * the key is the FOREVER name and the match canonicalizes (the German
--     half lives in test_locale_messages.lua, the H1b law);
--   * the target is the SENT stamp, `"?"` when no stamp is in hand, and a
--     no-`%s` text ignores the word.
-- These tests CANNOT pass on the pre-T2 module: `P.CAST_ROWS`, the
-- `<Prefix>Cast*` keys and `M:OnCastForAnnounce` are all of this slice, so
-- each of them is the "fails on the old code" proof a behaviour change
-- needs - no temporary revert required to know it.
--
-- The ids in `withSpellNames` maps are the live 70707 store's where a real
-- one is named (Barkskin 22812, Avenging Wrath 407788, Shield Wall 871); the
-- 20-row sweeps use SYNTHETIC ids on purpose - the hook never compares an
-- id, it resolves it to a name and keys on the name, which is the point.

local FX = ForteXorcist
local M = FX.Messages.Module
local P = FX.Messages.Pages
local Announce = FX.Messages.Announce
local ST = FX.Settings

local function enable()
    if not M.cfg then M:OnEnable() end
end

local sent
local function installReaders(extra)
    local r = {
        inLockdown = function() return false end,
        outgoingRestricted = function() return false end,
        isRaid = function() return false end,
        groupCount = function() return 4 end,
        send = function(text, chatType)
            sent[#sent + 1] = { text = text, chatType = chatType }
        end,
    }
    for k, v in pairs(extra or {}) do r[k] = v end
    Announce.readers = r
    sent = {}
end
local function restoreAll()
    Announce.readers = {}
    if FX.SecretState then FX.SecretState.chat = nil end
end

local function withSpellNames(names)
    local real = C_Spell and C_Spell.GetSpellInfo
    _G.C_Spell = _G.C_Spell or {}
    C_Spell.GetSpellInfo = function(id)
        local n = names[id]
        return n and { spellID = id, name = n } or nil
    end
    return real
end
local function restoreSpellNames(real)
    if C_Spell then C_Spell.GetSpellInfo = real end
end

local function dispatch(event, a1, a2, a3, a4)
    local f = M._eventFrame
    assertNotNil(f, "the cast watches share the one event frame")
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    onEvent(f, event, a1, a2, a3, a4)
end

local function rowByPrefix(prefix)
    for _ = 1, #P.CAST_ROWS do
        if P.CAST_ROWS[_].prefix == prefix then return P.CAST_ROWS[_] end
    end
    return nil
end

-- One announce per class, the three the survey's split names, each run
-- through the legality gate from BOTH sides: unrestricted -> a send;
-- lockdown -> no send and a counted skip.
local CLASS_CASTS = {
    { class = "Druid", prefix = "Barkskin", id = 22812, name = "Barkskin",
        text = "+++ Barkskin (10 sec) +++" },
    { class = "Paladin", prefix = "GuardianOfAncientKings", id = 407788,
        name = "Avenging Wrath",
        text = "+++ Guardian of Ancient Kings (12sec) +++" },
    { class = "Warrior", prefix = "ShieldWall", id = 871,
        name = "Shield Wall", text = "+++ Shield Wall (12 sec) +++" },
}

for _ = 1, #CLASS_CASTS do
    local cast = CLASS_CASTS[_]
    local row = rowByPrefix(cast.prefix)
    test(cast.class .. ": the own cast of " .. row.spell .. " announces the "
    .. "source's line to the group when unrestricted, and is skipped + "
    .. "counted under a lockdown", function()
        enable()
        installReaders({})
        local real = withSpellNames({ [cast.id] = cast.name })
        ST:Set("RaidMsg", cast.prefix .. "CastParty", true)
        local s0, l0 = Announce.counts.sent, Announce.counts.lockedSkipped
        local c0 = M.counts.cast
        dispatch("UNIT_SPELLCAST_SENT", "player", "Self", "G:1", cast.id)
        dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:1", cast.id)
        assertEquals(1, #sent, "the unrestricted cast sends")
        assertEquals(cast.text, sent[1].text, "the source's text verbatim")
        assertEquals("PARTY", sent[1].chatType, "ToGroup routing")
        assertEquals(s0 + 1, Announce.counts.sent)
        assertEquals(c0 + 1, M.counts.cast)
        -- The lockdown half: the same cast, now nothing goes and the skip
        -- is counted (the SecretState consumer law, Core/Announce.lua).
        installReaders({ inLockdown = function() return true end })
        dispatch("UNIT_SPELLCAST_SENT", "player", "Self", "G:2", cast.id)
        dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:2", cast.id)
        assertEquals(0, #sent, "a lockdown answers: nothing went")
        assertEquals(l0 + 1, Announce.counts.lockedSkipped)
        assertEquals(s0 + 1, Announce.counts.sent, "no send was made")
        ST:Set("RaidMsg", cast.prefix .. "CastParty", false)
        restoreSpellNames(real)
        restoreAll()
    end)
end

test("the channel half of a cast row rides OutputChannel (the SAY/YELL "
.. "routing), and the group half stays PARTY", function()
    enable()
    installReaders({})
    local real = withSpellNames({ [871] = "Shield Wall" })
    ST:Set("RaidMsg", "OutputEnable", true)
    ST:Set("RaidMsg", "OutputChannel", "SAY")
    ST:Set("RaidMsg", "ShieldWallCastParty", true)
    ST:Set("RaidMsg", "ShieldWallCastChannel", true)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Self", "G:C1", 871)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:C1", 871)
    assertEquals(2, #sent, "both halves fire: the group line and the "
        .. "channel line")
    assertEquals("PARTY", sent[1].chatType)
    assertEquals("SAY", sent[2].chatType)
    assertEquals("+++ Shield Wall (12 sec) +++", sent[1].text)
    assertEquals("+++ Shield Wall (12 sec) +++", sent[2].text)
    ST:Set("RaidMsg", "ShieldWallCastParty", false)
    ST:Set("RaidMsg", "ShieldWallCastChannel", false)
    ST:Set("RaidMsg", "OutputEnable", false)
    ST:Set("RaidMsg", "OutputChannel", "SAY")
    restoreSpellNames(real)
    restoreAll()
end)

test("the target half: the SENT stamp rides the SUCCEEDED line, a lost "
.. "SENT is the '?' word, and a no-%s text ignores the word", function()
    enable()
    installReaders({})
    local real = withSpellNames({
        [403437] = "Intervene", [22812] = "Barkskin",
    })
    ST:Set("RaidMsg", "InterveneCastParty", true)
    ST:Set("RaidMsg", "BarkskinCastParty", true)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Dead Peer", "G:T1", 403437)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:T1", 403437)
    assertEquals(1, #sent)
    assertEquals("+++ Intervene on Dead Peer (10 sec) +++", sent[1].text)
    -- A SUCCEEDED whose SENT never arrived: the '?' word, never a nil.
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:T2", 403437)
    assertEquals(2, #sent)
    assertEquals("+++ Intervene on ? (10 sec) +++", sent[2].text)
    -- A self-cast row's text carries no %s: the stamped word is ignored,
    -- the line stays the source's verbatim.
    dispatch("UNIT_SPELLCAST_SENT", "player", "Dead Peer", "G:T3", 22812)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:T3", 22812)
    assertEquals(3, #sent)
    assertEquals("+++ Barkskin (10 sec) +++", sent[3].text)
    ST:Set("RaidMsg", "InterveneCastParty", false)
    ST:Set("RaidMsg", "BarkskinCastParty", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("a cast of no row (Fireball) is silent, and a foreign unit's cast is "
.. "ignored (the player filter)", function()
    enable()
    installReaders({})
    local real = withSpellNames({
        [999] = "Fireball", [871] = "Shield Wall",
    })
    ST:Set("RaidMsg", "ShieldWallCastParty", true)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Self", "G:N1", 999)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:N1", 999)
    assertEquals(0, #sent, "no row of the name, no announce")
    dispatch("UNIT_SPELLCAST_SENT", "party1", "Self", "G:N2", 871)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "party1", "G:N2", 871)
    assertEquals(0, #sent, "the watch is the PLAYER's own casts")
    ST:Set("RaidMsg", "ShieldWallCastParty", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("the shipped defaults: every one of the 20 casts of the table is "
.. "SILENT on a fresh install, and the cast counter does not move",
function()
    enable()
    installReaders({})
    local names, ids = {}, {}
    for i = 1, #P.CAST_ROWS do
        ids[i] = 900000 + i              -- synthetic: ids are never compared
        names[ids[i]] = P.CAST_ROWS[i].spell
    end
    local real = withSpellNames(names)
    local s0, c0 = Announce.counts.sent, M.counts.cast
    for _ = 1, #ids do
        dispatch("UNIT_SPELLCAST_SENT", "player", "Self", "G:D" .. _, ids[_])
        dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:D" .. _, ids[_])
    end
    assertEquals(0, #sent, "a default install speaks to no raid")
    assertEquals(c0, M.counts.cast, "the hook gates before it counts")
    assertEquals(s0, Announce.counts.sent)
    restoreSpellNames(real)
    restoreAll()
end)

test("the table's SHAPE: 20 rows, 6 Druid / 8 Paladin / 6 Warrior, unique "
.. "prefixes, and a key triple in the shipped defaults per row", function()
    enable()
    local D = P.DEFAULTS.RaidMsg
    assertEquals(20, #P.CAST_ROWS, "the survey's 20 announce rows")
    local seen, split = {}, { Druid = 0, Paladin = 0, Warrior = 0 }
    for _ = 1, #P.CAST_ROWS do
        local row = P.CAST_ROWS[_]
        assertTrue(type(row.prefix) == "string" and row.prefix ~= "",
            "every row has a prefix")
        assertTrue(seen[row.prefix] == nil,
            "prefix " .. tostring(row.prefix) .. " is unique")
        seen[row.prefix] = true
        local class = P.CAST_ROW_CLASS[row.prefix]
        assertTrue(class ~= nil, "the census names " .. row.prefix
            .. "'s class")
        split[class] = split[class] + 1
        assertEquals(row.text, D[row.prefix .. "CastText"],
            row.prefix .. ": the shipped text is the row's verbatim text")
        assertEquals(false, D[row.prefix .. "CastParty"],
            row.prefix .. ": the group send ships OFF (E2)")
        assertEquals(false, D[row.prefix .. "CastChannel"],
            row.prefix .. ": the channel send ships OFF (E2)")
        assertTrue(row.bits == 0 or row.bits == 1,
            row.prefix .. ": the source's bits value is recorded")
        assertTrue(type(row.note) == "string"
            and row.note:find("bits") ~= nil,
            row.prefix .. ": the tip names the source's bits value")
        assertTrue(type(row.src) == "string" and row.src:find("%.lua:") ~= nil,
            row.prefix .. ": the tip cites the source file:line")
    end
    assertEquals(6, split.Druid, "six Druid rows (Druid.lua:190-227)")
    assertEquals(8, split.Paladin, "eight Paladin rows (Paladin.lua:125-168)")
    assertEquals(6, split.Warrior, "six Warrior rows (Warrior.lua:79-104)")
end)

test("the verbatim texts of the survey's 20 rows are the source's strings",
function()
    enable()
    local D = P.DEFAULTS.RaidMsg
    local want = {
        Barkskin = "+++ Barkskin (10 sec) +++",
        SurvivalInstincts = "+++ Survival Instincts (12 sec) +++",
        FrenziedRegeneration = "+++ Frenzied Regeneration (20 sec) +++",
        Rebirth = ">>> Rebirth on %s <<<",
        Innervate = ">>> Innervate on %s <<<",
        Tranquility = ">>> Tranquility up <<<",
        AuraMastery = "+++ Aura Mastery (6sec) +++",
        Salvation = "+++ Salvation on %s (10sec) +++",
        Sacrifice = "+++ Sacrifice on %s (12sec) +++",
        Freedom = "+++ Freedom on %s (6sec) +++",
        HandOfProtection = "+++ Hand of Protection on %s (12sec) +++",
        DivineProtection = "+++ Divine Protection (10sec) +++",
        GuardianOfAncientKings = "+++ Guardian of Ancient Kings (12sec) +++",
        ArdentDefender = "+++ Ardent Defender (10sec) +++",
        ShieldWall = "+++ Shield Wall (12 sec) +++",
        LastStand = "+++ Last Stand (20 sec) +++",
        RallyingCry = "+++ Rallying Cry (10 sec) +++",
        EnragedRegeneration = "+++ Enraged Regeneration (10 sec) +++",
        Intervene = "+++ Intervene on %s (10 sec) +++",
        Vigilance = ">>> Vigilance on %s (12 sec) <<<",
    }
    for prefix, text in pairs(want) do
        assertEquals(text, D[prefix .. "CastText"],
            prefix .. ": the shipped text is verbatim")
    end
    assertEquals(20, (function()
        local n = 0
        for _ in pairs(want) do n = n + 1 end
        return n
    end)(), "the census covers all 20 rows")
end)

test("the source's bits are recorded, and the ONE bits-0 row of the source "
.. "(Warrior Vigilance) is the row whose shipped default agrees with it",
function()
    enable()
    local zeros
    for _ = 1, #P.CAST_ROWS do
        local row = P.CAST_ROWS[_]
        if row.bits == 0 then
            zeros = (zeros or "") .. "," .. row.prefix
        end
    end
    assertEquals(",Vigilance", zeros,
        "VigilanceStart is the source's only silent row (Warrior.lua:104)")
    local row = rowByPrefix("Vigilance")
    assertTrue(row.note:find("SILENT") ~= nil,
        "the tip names that the source ships it silent")
    assertEquals(0, row.bits)
    -- The source's party-ON rows are the other 19, each named in its note.
    for _ = 1, #P.CAST_ROWS do
        local r = P.CAST_ROWS[_]
        if r.bits == 1 then
            assertTrue(r.note:find("bits 1") ~= nil,
                r.prefix .. ": the tip names the source's party-ON default")
        end
    end
end)

test("the two rows that cannot fire on THIS build say so, for one named "
.. "reason, and every other row keys on a name the key table carries",
function()
    enable()
    local inert = 0
    for _ = 1, #P.CAST_ROWS do
        local row = P.CAST_ROWS[_]
        assertEquals(row.prefix, P.CAST_SPELL_KEYS[row.spell],
            row.spell .. " is a key of the announce key table")
        if row.note:find("INERT ON THIS BUILD") ~= nil then
            inert = inert + 1
            assertTrue(row.note:find("70707") ~= nil
                or row.note:find("70425") ~= nil,
                row.prefix .. ": the inert tip names the data fact")
        end
    end
    assertEquals(2, inert,
        "Salvation (1038 removed on 70707) and Ardent Defender (31850, no "
        .. "row on either build) are the two inert keys")
    -- The rename aliases: the key table carries the FOREVER names.
    assertEquals("Freedom", P.CAST_SPELL_KEYS["Blessing of Freedom"])
    assertEquals("HandOfProtection", P.CAST_SPELL_KEYS["Blessing of Protection"])
    assertEquals("Sacrifice", P.CAST_SPELL_KEYS["Hand of Sacrifice"])
    assertEquals("Sacrifice", P.CAST_SPELL_KEYS["Blessing of Sacrifice"],
        "the 2012 id 6940's Forever name shares the row (the Mesmerize shape)")
    assertEquals("GuardianOfAncientKings", P.CAST_SPELL_KEYS["Avenging Wrath"])
    assertNil(P.CAST_SPELL_KEYS["Hand of Freedom"],
        "the 2012 name is not a key on this build (the Enslave Demon shape)")
    assertNil(P.CAST_SPELL_KEYS["Guardian of Ancient Kings"])
end)

test("Q5: the Druid rows carry PLAIN spell names - no form suffix, no "
.. "form-paired announce row", function()
    enable()
    for _ = 1, #P.CAST_ROWS do
        local row = P.CAST_ROWS[_]
        local class = P.CAST_ROW_CLASS[row.prefix]
        if class == "Druid" then
            assertNil(row.spell:find("%("), "no (Bear)/(Cat) suffix on "
                .. row.spell)
            assertNil(row.text:find("Bear"), row.prefix .. ": plain name")
            assertNil(row.text:find("Cat"), row.prefix .. ": plain name")
            assertNil(row.text:find("Moonkin"), row.prefix .. ": plain name")
        end
    end
    assertNil(P.CAST_SPELL_KEYS["Bear Form"])
    assertNil(P.CAST_SPELL_KEYS["Cat Form"])
end)

test("the soulstone watch is untouched by the general hook: the family cast "
.. "announces once, with a cast row ticked and with none", function()
    enable()
    installReaders({})
    local real = withSpellNames({
        [706] = "Create Soulstone", [871] = "Shield Wall",
    })
    ST:Set("RaidMsg", "SoulstoneAnnounce", true)
    ST:Set("RaidMsg", "ShieldWallCastParty", true)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Dead Peer", "G:S1", 706)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:S1", 706)
    assertEquals(1, #sent, "the family cast makes the ONE soulstone line")
    assertEquals("Soulstoned >> Dead Peer << Use it well!", sent[1].text)
    ST:Set("RaidMsg", "SoulstoneAnnounce", false)
    ST:Set("RaidMsg", "ShieldWallCastParty", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("the page registers, and every cast row's three controls and its "
.. "tip reach the Options page", function()
    enable()
    local ok = P.RegisterRaidMsgPage()
    assertTrue(ok, "the page registers")
    assertTrue(FX.Options and FX.Options.pages
        and FX.Options.pages.RaidMsg ~= nil,
        "the RaidMsg page is on FX.Options")
    for _ = 1, #P.CAST_ROWS do
        local row = P.CAST_ROWS[_]
        assertEquals(row.text, ST:Get("RaidMsg", row.prefix .. "CastText"))
        assertEquals(false, ST:Get("RaidMsg", row.prefix .. "CastParty"),
            row.prefix .. ": the store default is OFF")
        assertEquals(false, ST:Get("RaidMsg", row.prefix .. "CastChannel"),
            row.prefix .. ": the store default is OFF")
    end
    -- The gate re-reads the live view: a Set reaches the hook at once.
    installReaders({})
    local real = withSpellNames({ [871] = "Shield Wall" })
    ST:Set("RaidMsg", "ShieldWallCastParty", true)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Self", "G:L1", 871)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:L1", 871)
    assertEquals(1, #sent, "the checkbox is applied live")
    ST:Set("RaidMsg", "ShieldWallCastParty", false)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Self", "G:L2", 871)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:L2", 871)
    assertEquals(1, #sent, "and un-ticking it silences the next cast")
    restoreSpellNames(real)
    restoreAll()
end)
