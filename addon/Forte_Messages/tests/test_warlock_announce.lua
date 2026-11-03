-- addon/Forte_Messages/tests/test_warlock_announce.lua
-- The Warlock rows of the Party/Raid page (Wave 4, Options WL+Msg item 6):
-- the nine `CA:CastShow` rows of the source's Warlock page -- the Seduce
-- trio (Warlock.lua:307-309), the Spell Lock trio (:316,:317,:320) and the
-- Devour Magic trio (:323,:324,:327) -- plus the soulstone cast pair
-- SoulstoneStart / SoulstoneCancel (:294-295) and the whisper trio
-- (:297-299). The laws under test, each the "fails on the old code" proof
-- the behaviour change needs (P.PET_ROWS, the <Key>Party/<Key>Channel/
-- <Key>Text keys, the Soulstone*Whisper keys, M:OnPetCastForAnnounce,
-- M:AnnounceSoulstone, Announce:Whisper and the INTERRUPTED registration are
-- all of this slice):
--   * the CONSUMER is real: the pet rows ride the FELGUARD's own cast events
--     (the pet spine Forte_Timer/Module.lua:616-617 registers, wave 2b
--     "PetRows v2"), driven here through the real frame's OnEvent with the
--     catalog's payload orders -- the unit token `pet` is the router, so a
--     pet event reaching the player hooks (or the reverse) fails the test;
--   * the LEGALITY GATE both ways, per row family: sent when unrestricted,
--     SKIPPED AND COUNTED under a lockdown (the SecretState consumer law,
--     Core/Announce.lua);
--   * every one of the 18 pet send boxes, the 4 soulstone group/channel
--     boxes and the 3 whisper boxes ships OFF (the shipped-default law, the
--     manager ruling of 2026-11-02 on review 4 E2) while every TEXT is the
--     source's verbatim word (:352-364);
--   * the Ready pair (`SpellLockReady`, `DevourMagicReady`, the source's two
--     `CD:RegisterOnCooldownReady` rows at :271-276) rides the cooldown the
--     GENERATED DATA carries for the pet spell -- the window is armed from
--     `FX.Data.Warlock[id].cooldownMs`, the test reads the same row for the
--     expected length, and with the Warlock data unloaded the row cannot arm
--     (no invented constant);
--   * the whisper half goes to the cast's target by name (the source's
--     `FW:Whisper(msg, to)`, Forte_Core.lua:2081-2083), and an unreadable
--     target is no whisper at all: counted, silent.
-- The ids are the live 70707 store's own (Seduction 6358, Spell Lock 19647,
-- Devour Magic 19736) because the Ready pair resolves the data ROW by them;
-- the announce half never compares an id -- it resolves it to a name.

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
        send = function(text, chatType, languageID, target)
            sent[#sent + 1] = {
                text = text, chatType = chatType, target = target,
            }
        end,
    }
    for k, v in pairs(extra or {}) do r[k] = v end
    Announce.readers = r
    sent = {}
end
local function restoreAll()
    Announce.readers = {}
    M.afterFn = nil
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

--- Drive the REAL frame's OnEvent with the catalog's payload orders (the
--- UI-test law: no test calls a handler or a render function).
local function dispatch(event, a1, a2, a3, a4)
    local f = M._eventFrame
    assertNotNil(f, "the cast watches share the one event frame")
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    onEvent(f, event, a1, a2, a3, a4)
end

local function rowByKey(key)
    for _ = 1, #P.PET_ROWS do
        if P.PET_ROWS[_].key == key then return P.PET_ROWS[_] end
    end
    return nil
end

-- ==================================================== the shipped defaults --

test("the Warlock rows exist with the source's keys, texts and groups",
function()
    enable()
    assertEquals(9, #P.PET_ROWS, "the Seduce, Spell Lock and Devour Magic "
        .. "triads of the source's Pet sub (Warlock.lua:305-328)")
    local texts = {
        SeduceStart = "Seducing >> %s << Now",
        SeduceSuccess = "Seduced >> %s << Don't hit it!",
        SeduceFailed = ">> Seduction Failed! <<",
        SpellLockSuccess = ">> Spell Lock Used <<",
        SpellLockFailed = ">> Spell Lock Failed! <<",
        SpellLockReady = ">> Spell Lock ready <<",
        DevourMagicSuccess = ">> Devour Magic Used <<",
        DevourMagicFailed = ">> Devour Magic Failed! <<",
        DevourMagicReady = ">> Devour Magic ready <<",
    }
    for key, text in pairs(texts) do
        local row = rowByKey(key)
        assertNotNil(row, key .. ": the row of the source's " .. key
            .. " (Warlock.lua)")
        assertEquals(text, row.text, key .. ": the source's text verbatim")
        assertEquals(0, row.bits, key .. ": the source ships its pet rows "
            .. "silent (bits 0, Warlock.lua:355-364)")
        assertNotNil(row.src, key .. " carries its source citation")
    end
    -- The keys of the live data (the names the pet's cast event resolves
    -- to), not 2012 names: Mesmerize is the alias row, as in the fade pair.
    assertEquals("Seduce", P.PET_SPELL_KEYS["Seduction"])
    assertEquals("Seduce", P.PET_SPELL_KEYS["Mesmerize"])
    assertEquals("SpellLock", P.PET_SPELL_KEYS["Spell Lock"])
    assertEquals("DevourMagic", P.PET_SPELL_KEYS["Devour Magic"])
    for _ = 1, #P.PET_ROWS do
        local row = P.PET_ROWS[_]
        assertNotNil(P.PET_SPELL_KEYS[row.spell],
            row.key .. " keys on the live data name " .. row.spell)
    end
    -- No Death Knight row anywhere in this tree (Forever has no DK).
    for _ = 1, #P.PET_ROWS do
        assertFalse(tostring(P.PET_ROWS[_].spell):find("Death Coil") ~= nil,
            "no DK row")
    end
end)

test("E2 census: every Warlock send box ships OFF, the texts verbatim",
function()
    enable()
    local boxes = 0
    for _ = 1, #P.PET_ROWS do
        local key = P.PET_ROWS[_].key
        assertEquals(false, P.DEFAULTS.RaidMsg[key .. "Party"],
            key .. "Party ships OFF")
        assertEquals(false, P.DEFAULTS.RaidMsg[key .. "Channel"],
            key .. "Channel ships OFF")
        assertEquals(P.PET_ROWS[_].text, P.DEFAULTS.RaidMsg[key .. "Text"],
            key .. "Text is the source's word")
        boxes = boxes + 2
    end
    for _, key in ipairs({ "SoulstoneStart", "SoulstoneCancel" }) do
        assertEquals(false, P.DEFAULTS.RaidMsg[key .. "Party"],
            key .. "Party ships OFF (the source ships it party-ON, :352-354)")
        assertEquals(false, P.DEFAULTS.RaidMsg[key .. "Channel"],
            key .. "Channel ships OFF")
        boxes = boxes + 2
    end
    -- The whisper trio: the source's Success whisper is THE row it ships ON
    -- ({[0]=true}, Warlock.lua:359) and the shipped-default law puts it OFF
    -- beside its two siblings.
    for _, key in ipairs({ "SoulstoneStartWhisper", "SoulstoneCancelWhisper",
                           "SoulstoneSuccessWhisper" }) do
        assertEquals(false, P.DEFAULTS.RaidMsg[key], key .. " ships OFF")
        boxes = boxes + 1
    end
    assertEquals(25, boxes, "18 pet + 4 soulstone group/channel + 3 whispers")
    assertEquals("Soulstoning >> %s << Now", P.DEFAULTS.RaidMsg.SoulstoneStartText)
    assertEquals("Soulstoning >> %s << Cancelled",
        P.DEFAULTS.RaidMsg.SoulstoneCancelText)
    assertEquals(">> Soulstoning you now <<",
        P.DEFAULTS.RaidMsg.SoulstoneStartWhisperText)
    assertEquals("<< Soulstoning cancelled >>",
        P.DEFAULTS.RaidMsg.SoulstoneCancelWhisperText)
    assertEquals(">> You are now soulstoned! <<",
        P.DEFAULTS.RaidMsg.SoulstoneSuccessWhisperText)
end)

test("a default install stands mute: one pet cast of each, nothing sent",
function()
    enable()
    installReaders({})
    local real = withSpellNames({
        [6358] = "Seduction", [19647] = "Spell Lock", [19736] = "Devour Magic",
    })
    dispatch("UNIT_SPELLCAST_SENT", "pet", "Sheep", "P:1", 6358)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "P:1", 6358)
    dispatch("UNIT_SPELLCAST_SENT", "pet", "Sheep", "P:2", 19647)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "P:2", 19647)
    dispatch("UNIT_SPELLCAST_SENT", "pet", "Sheep", "P:3", 19736)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "P:3", 19736)
    dispatch("UNIT_SPELLCAST_FAILED", "pet", "P:4", 19736)
    assertEquals(0, #sent, "no box ticked, no line sent")
    restoreSpellNames(real)
    restoreAll()
end)

-- ======================================================== the pet triads --

local PET_TRIO = {
    { spell = "Seduction", id = 6358, stem = "Seduce",
        startKey = "SeduceStart", successKey = "SeduceSuccess",
        failedKey = "SeduceFailed" },
    { spell = "Spell Lock", id = 19647, stem = "SpellLock",
        successKey = "SpellLockSuccess", failedKey = "SpellLockFailed",
        readyKey = "SpellLockReady" },
    { spell = "Devour Magic", id = 19736, stem = "DevourMagic",
        successKey = "DevourMagicSuccess", failedKey = "DevourMagicFailed",
        readyKey = "DevourMagicReady" },
}

for _ = 1, #PET_TRIO do
    local trio = PET_TRIO[_]
    --- Tick every box of the trio on, run the events, count the sends.
    local keys = {}
    for _, key in ipairs({ trio.startKey or "none", trio.successKey,
                           trio.failedKey, trio.readyKey or "none" }) do
        if key ~= "none" then keys[#keys + 1] = key end
    end
    local function setArmed(on)
        for _2 = 1, #keys do
            ST:Set("RaidMsg", keys[_2] .. "Party", on and true or false)
        end
    end
    test("the pet's " .. trio.spell .. ": SENT/SUCCEEDED/FAILED announce "
    .. "the source's lines through the legality gate", function()
        enable()
        installReaders({})
        local real = withSpellNames({ [trio.id] = trio.spell })
        setArmed(true)
        local s0, l0 = Announce.counts.sent, Announce.counts.lockedSkipped
        local p0 = M.counts.pet
        -- The unrestricted half: the felguard's cast events produce the
        -- source's lines, to PARTY (the ToGroup routing).
        dispatch("UNIT_SPELLCAST_SENT", "pet", "Sheep", "G:1", trio.id)
        dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:1", trio.id)
        dispatch("UNIT_SPELLCAST_FAILED", "pet", "G:2", trio.id)
        local expect = (trio.startKey and 1 or 0) + 2
        assertEquals(expect, #sent,
            "start + success + failed of " .. trio.spell)
        for _2 = 1, #sent do
            assertEquals("PARTY", sent[_2].chatType)
        end
        local at = trio.startKey and 1 or 0
        if trio.startKey then
            assertEquals("Seducing >> Sheep << Now", sent[1].text,
                "the target rides the SENT payload (the source needed a "
                .. "0.5 s pettarget settle, :366-369 -- the payload carries "
                .. "the name)")
        end
        local successRow = rowByKey(trio.successKey)
        assertNotNil(successRow)
        local expectedSuccess = (successRow.text:gsub("%%s", "Sheep"))
        assertEquals(expectedSuccess, sent[at + 1].text,
            "the success line, the source's text with the target word in")
        assertEquals(s0 + expect, Announce.counts.sent)
        assertEquals(p0 + expect, M.counts.pet)
        -- The lockdown half: the same cast trio, counted and silent.
        -- (`installReaders` resets the sink, so the post-lockdown
        -- compare is against 0, not the carried pre-lockdown count.)
        installReaders({ inLockdown = function() return true end })
        dispatch("UNIT_SPELLCAST_SENT", "pet", "Sheep", "G:3", trio.id)
        dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:3", trio.id)
        dispatch("UNIT_SPELLCAST_FAILED", "pet", "G:4", trio.id)
        assertEquals(0, #sent, "the lockdown added no send")
        assertEquals(l0 + expect, Announce.counts.lockedSkipped,
            "every skipped send is counted (the /fx status ate-list)")
        assertEquals(s0 + expect, Announce.counts.sent)
        setArmed(false)
        restoreSpellNames(real)
        restoreAll()
    end)
end

-- ============================================================ the Ready pair --

test("the Ready rows arm off the data row's cooldownMs, not a typed number",
function()
    enable()
    installReaders({})
    local armed = {}
    M.afterFn = function(seconds, fn)
        armed[#armed + 1] = { seconds = seconds, fn = fn }
    end
    local real = withSpellNames({ [19647] = "Spell Lock" })
    ST:Set("RaidMsg", "SpellLockSuccessParty", true)
    ST:Set("RaidMsg", "SpellLockReadyParty", true)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:9", 19647)
    assertEquals(1, #armed, "the pet's cast armed the Ready window")
    local row = FX.Data.Warlock[19647]
    assertNotNil(row, "the generated Warlock data carries the spell")
    assertEquals(row.cooldownMs / 1000, armed[1].seconds,
        "the window is the DATA row's cooldownMs (never a hand-typed "
        .. "constant)")
    ST:Set("RaidMsg", "SpellLockSuccessParty", false)
    ST:Set("RaidMsg", "SpellLockReadyParty", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("the Ready moment announces the source's Ready line, once per window",
function()
    enable()
    installReaders({})
    local armed = {}
    M.afterFn = function(seconds, fn) armed[#armed + 1] = fn end
    local real = withSpellNames({ [19736] = "Devour Magic" })
    ST:Set("RaidMsg", "DevourMagicSuccessParty", true)
    ST:Set("RaidMsg", "DevourMagicReadyParty", true)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:5", 19736)
    assertEquals(1, #armed)
    assertEquals(1, #sent, "the success line went at the cast")
    local r0 = M.counts.petReady
    armed[1]()                      -- the window runs out
    assertEquals(r0 + 1, M.counts.petReady)
    assertEquals(2, #sent)
    assertEquals(">> Devour Magic ready <<", sent[2].text,
        "the source's DevourMagicReady line verbatim (:364)")
    assertEquals("PARTY", sent[2].chatType)
    -- The success row off, the Ready row's own box alone is enough.
    ST:Set("RaidMsg", "DevourMagicSuccessParty", false)
    armed = {}
    sent = {}
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:6", 19736)
    assertEquals(1, #armed, "the Ready row arms on its own")
    assertEquals(0, #sent)
    ST:Set("RaidMsg", "DevourMagicReadyParty", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("no Warlock data loaded: the Ready row cannot arm (no invented number)",
function()
    enable()
    installReaders({})
    local armed = {}
    M.afterFn = function(seconds, fn) armed[#armed + 1] = seconds end
    local realData = FX.Data.Warlock
    local realNames = FX.Data.WarlockByName
    FX.Data.Warlock = nil
    FX.Data.WarlockByName = nil
    local real = withSpellNames({ [990001] = "Spell Lock" })
    ST:Set("RaidMsg", "SpellLockSuccessParty", true)
    ST:Set("RaidMsg", "SpellLockReadyParty", true)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:7", 990001)
    assertEquals(1, #sent, "the Success row still rides the event")
    assertEquals(0, #armed, "the Ready row has no number to count from")
    FX.Data.Warlock = realData
    FX.Data.WarlockByName = realNames
    ST:Set("RaidMsg", "SpellLockSuccessParty", false)
    ST:Set("RaidMsg", "SpellLockReadyParty", false)
    restoreSpellNames(real)
    restoreAll()
end)

-- ==================================================== the soulstone cast --

test("the soulstone cast: start announces, cancel rides the interrupt, the "
.. "whispers ride the target name", function()
    enable()
    installReaders({})
    local real = withSpellNames({ [20757] = "Create Soulstone" })
    ST:Set("RaidMsg", "SoulstoneStartParty", true)
    ST:Set("RaidMsg", "SoulstoneCancelParty", true)
    ST:Set("RaidMsg", "SoulstoneAnnounce", true)
    ST:Set("RaidMsg", "SoulstoneStartWhisper", true)
    ST:Set("RaidMsg", "SoulstoneCancelWhisper", true)
    ST:Set("RaidMsg", "SoulstoneSuccessWhisper", true)
    local s0 = Announce.counts.sent
    -- The start: the cast goes out on Gvil.
    dispatch("UNIT_SPELLCAST_SENT", "player", "Gvil", "C:1", 20757)
    assertEquals(2, #sent, "the group line + the whisper to the target")
    assertEquals("Soulstoning >> Gvil << Now", sent[1].text)
    assertEquals("PARTY", sent[1].chatType)
    assertEquals("WHISPER", sent[2].chatType)
    assertEquals("Gvil", sent[2].target, "the whisper rides the target")
    assertEquals(">> Soulstoning you now <<", sent[2].text)
    -- The cancel: the cast bar ends without succeeding.
    sent = {}
    dispatch("UNIT_SPELLCAST_INTERRUPTED", "player", "C:1", 20757, "Sheep")
    assertEquals(2, #sent, "the cancel line + the cancel whisper")
    assertEquals("Soulstoning >> Gvil << Cancelled", sent[1].text)
    assertEquals("WHISPER", sent[2].chatType)
    assertEquals("<< Soulstoning cancelled >>", sent[2].text)
    -- The success half: the existing announce plus its whisper twin.
    sent = {}
    local d0 = Announce.counts.sent
    dispatch("UNIT_SPELLCAST_SENT", "player", "Gvil", "C:2", 20757)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "C:2", 20757)
    assertEquals(4, #sent, "the start pair + the success pair")
    assertEquals("Soulstoned >> Gvil << Use it well!", sent[3].text)
    assertEquals("WHISPER", sent[4].chatType)
    assertEquals(">> You are now soulstoned! <<", sent[4].text)
    assertEquals("Gvil", sent[4].target)
    assertEquals(d0 + 4, Announce.counts.sent)
    for _, key in ipairs({ "SoulstoneStartParty", "SoulstoneCancelParty",
                           "SoulstoneAnnounce", "SoulstoneStartWhisper",
                           "SoulstoneCancelWhisper",
                           "SoulstoneSuccessWhisper" }) do
        ST:Set("RaidMsg", key, false)
    end
    restoreSpellNames(real)
    restoreAll()
end)

test("a default install stands mute on the soulstone cast: the full start, "
.. "cancel and success sequence sends nothing", function()
    enable()
    installReaders({})
    local real = withSpellNames({ [20757] = "Create Soulstone" })
    -- NO box ticked: the full-default RaidMsg store. The start/cancel pair
    -- rides its OWN SoulstoneStart*/SoulstoneCancel* boxes (all OFF, E2),
    -- the success half its SoulstoneAnnounce/SoulstoneChannel pair and the
    -- whisper trio its own boxes -- none of it may ride the
    -- SoulstoneAnnounce box of a sibling (the review 5 hazard: the new
    -- Start leg must not make a default install speak).
    dispatch("UNIT_SPELLCAST_SENT", "player", "Gvil", "C:D1", 20757)
    dispatch("UNIT_SPELLCAST_INTERRUPTED", "player", "C:D1", 20757, "Sheep")
    dispatch("UNIT_SPELLCAST_SENT", "player", "Gvil", "C:D2", 20757)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "C:D2", 20757)
    assertEquals(0, #sent, "start, cancel and success of a default install "
        .. "send nothing")
    restoreSpellNames(real)
    restoreAll()
end)

test("the soulstone rows are gate-gated too: a lockdown sends nothing and "
.. "counts the skip", function()
    enable()
    installReaders({ inLockdown = function() return true end })
    local real = withSpellNames({ [20757] = "Create Soulstone" })
    ST:Set("RaidMsg", "SoulstoneStartParty", true)
    ST:Set("RaidMsg", "SoulstoneStartWhisper", true)
    local l0 = Announce.counts.lockedSkipped
    local s0 = Announce.counts.sent
    dispatch("UNIT_SPELLCAST_SENT", "player", "Gvil", "C:3", 20757)
    assertEquals(0, #sent, "the lockdown swallows both legs")
    assertEquals(l0 + 2, Announce.counts.lockedSkipped)
    assertEquals(s0, Announce.counts.sent)
    ST:Set("RaidMsg", "SoulstoneStartParty", false)
    ST:Set("RaidMsg", "SoulstoneStartWhisper", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("a whisper with no readable target is not sent: counted, silent",
function()
    enable()
    installReaders({})
    local real = withSpellNames({ [20757] = "Create Soulstone" })
    ST:Set("RaidMsg", "SoulstoneStartWhisper", true)
    ST:Set("RaidMsg", "SoulstoneStartParty", true)
    -- The secret-target seam of the suites (test_warlock.lua:881,
    -- Forte_Cooldown/tests/test_procs.lua): the ConditionalSecret SENT
    -- target field is the sentinel, and PlainOrNil -- the ONLY gate the
    -- runtime may use -- answers nil for it.
    local SECRET = "FXTEST-SECRET-VALUE"
    local realPlain = FX.Compat.PlainOrNil
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlain(v)
    end
    local n0 = Announce.counts.noTarget
    dispatch("UNIT_SPELLCAST_SENT", "player", SECRET, "C:4", 20757)
    assertEquals(1, #sent, "the group line went (its text falls back to ?)")
    assertEquals("Soulstoning >> ? << Now", sent[1].text)
    assertEquals(n0 + 1, Announce.counts.noTarget,
        "a secret target names nobody: the whisper is counted away")
    FX.Compat.PlainOrNil = realPlain
    ST:Set("RaidMsg", "SoulstoneStartWhisper", false)
    ST:Set("RaidMsg", "SoulstoneStartParty", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("the whisper target rides the remembered raw spelling of the name",
function()
    enable()
    installReaders({})
    local real = withSpellNames({ [20757] = "Create Soulstone" })
    ST:Set("RaidMsg", "SoulstoneStartWhisper", true)
    -- The game spelled it "Gvil" once (a scan, an event): that notation is
    -- the identity's spelling all session (FX.Identity.Remember/Raw, the
    -- toGame law of docs/research/upstream-api-2026-11-03.md §2).
    FX.Identity.Remember("Gvil")
    dispatch("UNIT_SPELLCAST_SENT", "player", "gvil", "C:RS1", 20757)
    assertEquals(1, #sent, "the whisper leg only (the party box is off)")
    assertEquals("WHISPER", sent[1].chatType)
    assertEquals("Gvil", sent[1].target,
        "a lower-case re-spelling whispers to the client's own notation")
    -- An identity the game never spelled in its own notation: the given
    -- spelling rides out unchanged.
    sent = {}
    dispatch("UNIT_SPELLCAST_SENT", "player", "Zeph", "C:RS2", 20757)
    assertEquals("Zeph", sent[1].target, "first spelling wins: it is the game's")
    ST:Set("RaidMsg", "SoulstoneStartWhisper", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("the pet rows are not the player's rows: the unit token routes them",
function()
    enable()
    installReaders({})
    local real = withSpellNames({ [6358] = "Seduction" })
    ST:Set("RaidMsg", "SeduceStartParty", true)
    ST:Set("RaidMsg", "SeduceSuccessParty", true)
    -- The PLAYER casting Seduction (a warlock with the pet's spell): the
    -- PET rows must not answer -- the pet rows ride the pet's events.
    dispatch("UNIT_SPELLCAST_SENT", "player", "Sheep", "P:1", 6358)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "P:1", 6358)
    assertEquals(0, #sent, "a player cast is not a pet cast")
    dispatch("UNIT_SPELLCAST_SENT", "pet", "Sheep", "P:2", 6358)
    assertEquals(1, #sent, "the pet cast is")
    ST:Set("RaidMsg", "SeduceStartParty", false)
    ST:Set("RaidMsg", "SeduceSuccessParty", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("the Mesmerize alias shares the Seduce rows (the fade pair's law)",
function()
    enable()
    installReaders({})
    local real = withSpellNames({ [24594] = "Mesmerize" })
    ST:Set("RaidMsg", "SeduceSuccessParty", true)
    -- No stamp in hand: an unmatched SUCCEEDED closes any carried one (the
    -- stamp is per cast, not per test).
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "X:0", 999999)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:8", 24594)
    assertEquals(1, #sent)
    assertEquals("Seduced >> ? << Don't hit it!", sent[1].text,
        "no SENT stamp in hand: the ? target word (the soulstone law)")
    ST:Set("RaidMsg", "SeduceSuccessParty", false)
    restoreSpellNames(real)
    restoreAll()
end)
