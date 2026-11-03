-- addon/Forte_Messages/tests/test_announce.lua
-- The legality gate (docs/messages-sounds.md is the evidence trail): an
-- announce SENDS through C_ChatInfo.SendChatMessage when nothing reports a
-- lockdown, and is SILENTLY SKIPPED AND COUNTED when one does -- the
-- C_RestrictedActions Chat=5 snapshot on FX.SecretState.chat (the Compat.lua
-- RESTRICTION_TYPES seam), C_ChatInfo.InChatMessagingLockdown, the
-- C_ChatInfo.AreOutgoingAddonChatMessagesRestricted pair NeedRoll gates on,
-- and — added by I3b for the gap the 2026-11-03 note §4 names — the client's
-- own `addonChatRestrictionsForced` CVar, the fourth leg the shipped chat
-- installs gate on, read through the catalog's C_CVar.GetCVarBool
-- (@CVarDocumentation.lua:50, a bool? where unknown is distinct from false).
-- Only a PLAIN true skips (the SecretState consumer law); a raising send is
-- counted, never propagated. Routing is the original's ToGroup/ToChannel
-- (Forte_Core.lua:2046-2070); the soulstone row is the Warlock family's
-- SoulstoneSuccess text (Forte_Class/Warlock/Warlock.lua:365) driven off the
-- PLAYER's own cast events with the family name patterns (Forte_Warlock/
-- Core/Tools.lua:142).
--
-- The lockdown readers are the documented seam (Announce.readers) and
-- FX.SecretState.chat is set directly -- the sim ships no
-- C_RestrictedActions, and the CONTRACT under test is what a true/false/
-- nil answer does to the send, not the client's plumbing.

local FX = ForteXorcist
local M = FX.Messages.Module
local Announce = FX.Messages.Announce
local Sounds = FX.Messages.Sounds
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

test("unrestricted: '<spell> ready' goes to PARTY in a party and RAID in "
.. "a raid (the ToGroup routing)", function()
    enable()
    installReaders({})
    ST:Set("RaidMsg", "OutputRaid", true)
    ST:Set("RaidMsg", "ReadyAnnounce", true)
    local s0 = Announce.counts.sent
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 1.0, nil, nil)
    assertEquals(1, #sent)
    assertEquals("PARTY", sent[1].chatType)
    assertEquals(">> Rapid Fire is ready <<", sent[1].text)
    installReaders({ isRaid = function() return true end })
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 2.0, nil, nil)
    assertEquals("RAID", sent[1].chatType)
    assertEquals(s0 + 2, Announce.counts.sent)
    ST:Set("RaidMsg", "ReadyAnnounce", false)
    restoreAll()
end)

test("locked (FX.SecretState.chat = the C_RestrictedActions Chat=5 read): "
.. "the send is silently skipped and counted", function()
    enable()
    installReaders({})
    ST:Set("RaidMsg", "ReadyAnnounce", true)
    -- The Refresh freeze: on a real client Refresh REcomputes chat from
    -- C_RestrictedActions (the truth); the sim has no surface, so the
    -- injected snapshot is what the gate must read.
    local realRefresh = FX.SecretState.Refresh
    FX.SecretState.Refresh = function() end
    FX.SecretState.chat = true
    local skipped0, sent0 = Announce.counts.lockedSkipped, Announce.counts.sent
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 3.0, nil, nil)
    assertEquals(0, #sent, "nothing went")
    assertEquals(skipped0 + 1, Announce.counts.lockedSkipped)
    assertEquals(sent0, Announce.counts.sent)
    FX.SecretState.chat = nil
    FX.SecretState.Refresh = realRefresh
    ST:Set("RaidMsg", "ReadyAnnounce", false)
    restoreAll()
end)

test("locked (C_ChatInfo.InChatMessagingLockdown true): skip + count",
function()
    enable()
    installReaders({ inLockdown = function() return true end })
    ST:Set("RaidMsg", "ReadyAnnounce", true)
    local s0 = Announce.counts.lockedSkipped
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 4.0, nil, nil)
    assertEquals(0, #sent)
    assertEquals(s0 + 1, Announce.counts.lockedSkipped)
    ST:Set("RaidMsg", "ReadyAnnounce", false)
    restoreAll()
end)

test("locked (C_ChatInfo.AreOutgoingAddonChatMessagesRestricted true): the "
.. "NeedRoll pair, skip + count", function()
    enable()
    installReaders({ outgoingRestricted = function() return true end })
    ST:Set("RaidMsg", "ReadyAnnounce", true)
    local s0 = Announce.counts.lockedSkipped
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 5.0, nil, nil)
    assertEquals(0, #sent)
    assertEquals(s0 + 1, Announce.counts.lockedSkipped)
    ST:Set("RaidMsg", "ReadyAnnounce", false)
    restoreAll()
end)

test("locked (the client's addonChatRestrictionsForced CVar): the shipped "
.. "installs' fourth leg (note §4), skip + count", function()
    enable()
    installReaders({ chatRestrictionsForced = function() return true end })
    ST:Set("RaidMsg", "ReadyAnnounce", true)
    local s0 = Announce.counts.lockedSkipped
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 5.5, nil, nil)
    assertEquals(0, #sent, "the forced-restriction flag locks the send")
    assertEquals(s0 + 1, Announce.counts.lockedSkipped)
    -- A plain false is not a lock, and NEITHER is an unknown: the reader is
    -- `C_CVar.GetCVarBool(name) -> bool?` (@CVarDocumentation.lua:50) whose
    -- contract note is "unknown is distinct from false", and the SecretState
    -- consumer law reads an unknown as "no evidence", never as a suppression.
    installReaders({ chatRestrictionsForced = function() return false end })
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 5.6, nil, nil)
    assertEquals(1, #sent, "false: the send goes")
    installReaders({ chatRestrictionsForced = function() return nil end })
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 5.7, nil, nil)
    assertEquals(1, #sent, "nil/unknown: the send goes")
    -- A CVar with no surface at all (a client that has no such flag) raises:
    -- counted as no evidence, the send goes (the same law as the pair above).
    installReaders({ chatRestrictionsForced = function()
        error("FXTEST-NO-CVAR", 0)
    end })
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 5.8, nil, nil)
    assertEquals(1, #sent, "no surface: the send goes")
    -- The leg gates the whisper route too (it runs the same chatLocked gate).
    installReaders({ chatRestrictionsForced = function() return true end })
    ST:Set("RaidMsg", "SoulstoneStartWhisper", true)
    local w0 = Announce.counts.lockedSkipped
    Announce:Whisper("Soulstoning >> Bob << Now", "SoulstoneStartWhisper", "Bob")
    assertEquals(0, #sent, "the whisper route is gated by the same flag")
    assertEquals(w0 + 1, Announce.counts.lockedSkipped)
    ST:Set("RaidMsg", "SoulstoneStartWhisper", false)
    ST:Set("RaidMsg", "ReadyAnnounce", false)
    restoreAll()
end)

test("an UNKNOWN lockdown state (nil from every reader) does NOT suppress "
.. "-- the SecretState consumer law", function()
    enable()
    installReaders({
        inLockdown = function() return nil end,
        outgoingRestricted = function() error("FXTEST-NO-SURFACE", 0) end,
    })
    ST:Set("RaidMsg", "ReadyAnnounce", true)
    local s0 = Announce.counts.sent
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 6.0, nil, nil)
    assertEquals(1, #sent)
    assertEquals(s0 + 1, Announce.counts.sent)
    ST:Set("RaidMsg", "ReadyAnnounce", false)
    restoreAll()
end)

test("a raising send is counted as failed and never propagates", function()
    enable()
    installReaders({
        send = function() error("FXTEST-SEND-BLOCKED", 0) end,
    })
    ST:Set("RaidMsg", "ReadyAnnounce", true)
    local f0 = Announce.counts.sendFailed
    local ok = pcall(FX.Fire, FX.EVENTS.COOLDOWN_READY, "Rapid Fire",
        7.0, nil, nil)
    assertTrue(ok, "the bus's pcall holds the line: the fire survives")
    assertEquals(f0 + 1, Announce.counts.sendFailed)
    ST:Set("RaidMsg", "ReadyAnnounce", false)
    restoreAll()
end)

test("no group: the announce echoes locally (the ToGroup FW:Show law), no send",
function()
    enable()
    installReaders({
        isRaid = function() return false end,
        groupCount = function() return 0 end,
    })
    -- The echo lands on the chat layer (the original's FW:Show -- the
    -- DEFAULT_CHAT_FRAME stub is the capture; FX.Print is its only
    -- fallback).
    local echo
    local realChat = _G.DEFAULT_CHAT_FRAME
    _G.DEFAULT_CHAT_FRAME = {
        AddMessage = function(_, text) echo = text end,
    }
    ST:Set("RaidMsg", "ReadyAnnounce", true)
    local g0 = Announce.counts.noGroup
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 8.0, nil, nil)
    _G.DEFAULT_CHAT_FRAME = realChat
    assertEquals(0, #sent)
    assertEquals(g0 + 1, Announce.counts.noGroup)
    assertNotNil(echo, "the line echoed locally")
    assertTrue(echo:find("Rapid Fire") ~= nil)
    ST:Set("RaidMsg", "ReadyAnnounce", false)
    restoreAll()
end)

test("the master switch and the channel routing: SAY/YELL normalise, a "
.. "stray channel string is refused", function()
    enable()
    installReaders({})
    ST:Set("RaidMsg", "ReadyChannel", true)
    ST:Set("RaidMsg", "OutputChannel", "yell")
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 9.0, nil, nil)
    assertEquals("YELL", sent[1].chatType)
    ST:Set("RaidMsg", "OutputChannel", "CHANNEL3")
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 10.0, nil, nil)
    assertEquals(2, #sent)
    assertEquals("CHANNEL3", sent[2].chatType)
    local off0 = Announce.counts.offSkipped
    ST:Set("RaidMsg", "OutputChannel", "PIZZA")
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 11.0, nil, nil)
    assertEquals(2, #sent, "the stray string sent nothing")
    assertEquals(off0 + 1, Announce.counts.offSkipped)
    -- The master switch mutes the whole channel half.
    ST:Set("RaidMsg", "OutputEnable", false)
    ST:Set("RaidMsg", "OutputChannel", "SAY")
    FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 12.0, nil, nil)
    assertEquals(2, #sent)
    ST:Set("RaidMsg", "OutputEnable", true)
    ST:Set("RaidMsg", "ReadyChannel", false)
    ST:Set("RaidMsg", "OutputChannel", "SAY")
    restoreAll()
end)

-- ------------------------------------------------------------- soulstone --

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
    assertNotNil(f)
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    -- The frame is argument 1 (the binding law; the Forte_Hunter bug class).
    onEvent(f, event, a1, a2, a3, a4)
end

test("soulstone: the family cast announces the original's line to the "
.. "group, and stays silent when opt-in is off", function()
    enable()
    installReaders({})
    local real = withSpellNames({
        [706] = "Create Soulstone",
        [999] = "Fireball",
    })
    ST:Set("RaidMsg", "SoulstoneAnnounce", true)
    local s0 = Announce.counts.sent
    dispatch("UNIT_SPELLCAST_SENT", "player", "Vile Poacher", "G:1", 706)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:1", 706)
    assertEquals(1, #sent)
    -- The original's text verbatim (Warlock.lua:365).
    assertEquals("Soulstoned >> Vile Poacher << Use it well!", sent[1].text)
    assertEquals("PARTY", sent[1].chatType)
    assertEquals(s0 + 1, Announce.counts.sent)
    -- A non-family cast: silence.
    dispatch("UNIT_SPELLCAST_SENT", "player", "Vile Poacher", "G:2", 999)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:2", 999)
    assertEquals(1, #sent)
    -- Opt-in OFF is the shipped default: the same cast, total silence.
    ST:Set("RaidMsg", "SoulstoneAnnounce", false)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Vile Poacher", "G:3", 706)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:3", 706)
    assertEquals(1, #sent)
    ST:Set("RaidMsg", "SoulstoneAnnounce", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("the family pattern is the Warlock tools' law: Create Soulstone / "
.. "Soulstone Resurrection in, Use Soulstone out", function()
    enable()
    installReaders({})
    local real = withSpellNames({
        [706] = "Create Soulstone",
        [1001] = "Soulstone Resurrection",
        [1002] = "Use Soulstone",
        [1003] = "Soulstone",          -- the stone's own use spell name
    })
    ST:Set("RaidMsg", "SoulstoneAnnounce", true)
    for _, id in ipairs({ 1001 }) do
        dispatch("UNIT_SPELLCAST_SENT", "player", "Dead Peer", "G:R", id)
        dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:R", id)
    end
    assertEquals(1, #sent)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Self", "G:U", 1002)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:U", 1002)
    assertEquals(1, #sent, "Use Soulstone is not a family cast (Tools.lua "
        .. "family: Create/resurrection only)")
    ST:Set("RaidMsg", "SoulstoneAnnounce", false)
    restoreSpellNames(real)
    restoreAll()
end)

test("a SUCCEEDED with no stamped SENT carries the '?' target, never a nil",
function()
    enable()
    installReaders({})
    local real = withSpellNames({ [706] = "Create Soulstone" })
    ST:Set("RaidMsg", "SoulstoneAnnounce", true)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:LOST", 706)
    assertEquals(1, #sent)
    assertEquals("Soulstoned >> ? << Use it well!", sent[1].text)
    ST:Set("RaidMsg", "SoulstoneAnnounce", false)
    restoreSpellNames(real)
    restoreAll()
end)

-- ------------------------------------------------------------------ fade --
-- The FX_TIMER_FADING / FX_TIMER_BROKEN chain (the review correction of
-- 2026-11-02): the fires live in Forte_Timer's own passes (the Sweep fade
-- block, the :1049-1056 law; OnAuraAbsent's removal, the :1207 law), the
-- thresholds are parsed here from the fade texts (the ST_GetFadeTime law,
-- Forte_Timer.lua:1590-1603), and the ORIGINAL plays its bell + message at
-- the FADE, never at a bare expiry.

local function enableTimer()
    enable()
    local TM = FX.Timer.Module
    if not TM.options then TM:OnEnable() end
    return FX.Timer.Rows
end

test("E2: the SHIPPED defaults census -- every group and channel announce "
.. "on the page is OFF, the two masters are the source's", function()
    enable()
    local D = FX.Messages.Pages.DEFAULTS.RaidMsg
    assertNotNil(D)
    local sends, texts = 0, 0
    for key, value in pairs(D) do
        local isSend = (key:find("Party$") ~= nil)
            or (key:find("Channel$") ~= nil and key ~= "OutputChannel")
            or (key:find("Announce$") ~= nil)
        if isSend then
            sends = sends + 1
            assertEquals(false, value,
                "the shipped default of " .. key .. " is OFF (opt-in)")
        elseif key:find("Text$") ~= nil then
            texts = texts + 1
            assertEquals("string", type(value), key .. " keeps its text")
        end
    end
    -- 24 fade/break checkboxes (6 spells x Fade/Break x Party/Channel) +
    -- ReadyAnnounce/ReadyChannel + ExpireAnnounce/ExpireAnnounce +
    -- SoulstoneAnnounce/SoulstoneChannel + the 20 cast rows x Party/Channel
    -- (40, wave 2b T2 - the Druid/Paladin/Warrior raid warnings, docs/
    -- class-port.md S17) + the 9 Warlock pet rows x Party/Channel (18) +
    -- the SoulstoneStart/Cancel pair x Party/Channel (4) -- Wave 4's Warlock
    -- rows of the Party/Raid page, every one shipped OFF by the same law:
    -- every one of them OFF.
    assertEquals(92, sends, "the census walked every send row")
    -- 6 fade + 6 break CC texts, plus the announce rows' own texts
    -- (ReadyAnnounceText, ExpireAnnounceText, ExpireAnnounceNoTargetText,
    -- SoulstoneAnnounceText) and the 20 cast rows' verbatim texts, plus
    -- Wave 4's Warlock half: the 9 pet rows' texts (the source's verbatim
    -- word, Warlock.lua:355-364), the 2 soulstone cast texts (:352-353) and
    -- the 3 whisper texts (:357-359) -- the texts are the verbatim half and
    -- stay.
    assertEquals(50, texts, "twelve CC texts + four announce texts + "
        .. "twenty cast texts + nine pet texts + two soulstone cast texts "
        .. "+ three whisper texts")
    -- The two master switches are the original's rows (Forte_Core.lua:2518
    -- -2519) and stay verbatim: with every row off they gate nothing alone.
    assertEquals(true, D.OutputRaid)
    assertEquals(true, D.OutputEnable)
    assertEquals("SAY", D.OutputChannel)
    -- The rows the source ships party-ON are ON only in the tip, not in the
    -- shipped default: the bits the page records for the owner's eye.
    local P = FX.Messages.Pages
    local byPrefix = {}
    for _ = 1, #P.FADE_ROWS do
        local row = P.FADE_ROWS[_]
        byPrefix[row.prefix] = row
    end
    assertEquals(1, byPrefix.Banish.bits)
    assertEquals(1, byPrefix.Enslave.bits)
    assertEquals(1, byPrefix.Seduction.bits)
    assertEquals(0, byPrefix.Fear.bits)
    assertEquals(0, byPrefix.Polymorph.bits)
    assertEquals(0, byPrefix.Sap.bits)
    for _ = 1, #P.FADE_ROWS do
        local row = P.FADE_ROWS[_]
        local note = row.note or ""
        if row.bits == 1 then
            assertTrue(note:find("ships this ON") ~= nil,
                row.prefix .. "'s tip records the source's party-ON")
            assertTrue(note:find("Warlock%.lua:372%-391") ~= nil,
                row.prefix .. "'s tip cites the source's rows")
        end
    end
end)

test("E4: the fade registry is keyed by the FOREVER names the Timer tracks",
function()
    enable()
    local P = FX.Messages.Pages
    -- `Enslave Demon` is what the 2012 source calls it; Forever calls the
    -- spell Subjugate Demon (mythicsim spells.jsonl 1098/11725/11726,
    -- ClassFlags.Family 5) and the generated Warlock data names it that --
    -- a key of "Enslave Demon" can never meet a row.
    assertEquals("Subjugate Demon", P.FADE_ROWS[3].spell)
    assertEquals("Enslave", P.FADE_SPELL_KEYS["Subjugate Demon"])
    assertNil(P.FADE_SPELL_KEYS["Enslave Demon"],
        "the 2012 name is not a key on this build")
    assertEquals(3, FX.Timer.FadeWarnings["Subjugate Demon"],
        "the threshold is published under the name that has a row")
    assertNil(FX.Timer.FadeWarnings["Enslave Demon"])
    -- The names the data carries keep theirs.
    assertEquals("Banish", P.FADE_SPELL_KEYS.Banish)
    assertEquals("Fear", P.FADE_SPELL_KEYS.Fear)
    assertEquals("Sap", P.FADE_SPELL_KEYS.Sap)
    assertEquals(3, FX.Timer.FadeWarnings.Banish)
    -- Mesmerize keeps sharing the Seduction rows (Warlock.lua:250).
    assertEquals("Seduction", P.FADE_SPELL_KEYS.Mesmerize)
    -- And the two rows the pet feed reaches say WHY on the page:
    -- Seduction/Mesmerize are the Succubus pet's casts, so the tip must
    -- name the pet cast feed (the wave 2b "PetRows v2" registration in
    -- Forte_Timer) and the live 70707 spell store.
    local seduction
    for _ = 1, #P.FADE_ROWS do
        if P.FADE_ROWS[_].prefix == "Seduction" then
            seduction = P.FADE_ROWS[_]
        end
    end
    assertNotNil(seduction)
    assertTrue((seduction.note or ""):find("pet") ~= nil,
        "the Seduction section names the pet-cast gate")
    local text = FX.Options and FX.Options.pages
        and FX.Options.pages.RaidMsg
    assertTrue(type(FX.Settings:Get("RaidMsg", "SeductionFadeText"))
        == "string", "the text itself is shipped (the verbatim half)")
end)

test("the shipped CC texts are the original's rows verbatim (E2 moves the "
.. "SEND, never the text)", function()
    enable()
    local D = FX.Messages.Pages.DEFAULTS.RaidMsg
    assertEquals(">> Banish on %s Fading in 3 seconds! <<", D.BanishFadeText)
    assertEquals(">> Seduction on %s Broke Early! <<", D.SeductionBreakText)
    assertEquals(">> Enslave on %s Fading in 3 seconds! <<", D.EnslaveFadeText)
    -- The threshold registry: 3 from the texts (the leading number law),
    -- Mesmerize shares the Seduction rows, Corruption is absent.
    assertEquals(3, FX.Timer.FadeWarnings.Banish)
    assertEquals(3, FX.Timer.FadeWarnings.Mesmerize)
    assertNil(FX.Timer.FadeWarnings.Corruption)
end)

test("FADING: a Banish row fires the event EXACTLY ONCE crossing 3.0 s, "
.. "the fade bell rings x2, the fade line goes to the party", function()
    local Rows = enableTimer()
    installReaders({})
    -- E2: the SHIPPED default of this send is OFF -- the fade is a 3-second
    -- heads-up on a crowd control, and a default install does not speak to a
    -- party that never asked. The rest of the test is the opted-in row (the
    -- box the owner ticks), which is the source's party-ON shape.
    ST:Set("RaidMsg", "BanishFadeParty", true)
    local clock = { 40000 }
    FX.Timer.Casts.now = function() return clock[1] end
    local row = Rows:InsertFromAura("Banish", "Vile Poacher",
        clock[1] + 10, 10, 0, nil, 0, clock[1])
    assertNotNil(row)
    assertEquals(3, row.fadeWarn, "the insert-time column-12 stamp")
    local events = {}
    local h = FX.On(FX.EVENTS.TIMER_FADING, function(s, t, k, left)
        events[#events + 1] = { s, t, k, left }
    end)
    local plays = {}
    Sounds.playFn = function(path) plays[#plays + 1] = path end
    local fade0 = M.counts.fading
    clock[1] = clock[1] + 2                    -- 8 s left: silence
    Rows:Sweep(clock[1])
    assertEquals(0, #events)
    assertEquals(0, #plays)
    clock[1] = clock[1] + 5.1                 -- 2.9 s left: the threshold
    Rows:Sweep(clock[1])
    assertEquals(1, #events)
    assertEquals("Banish", events[1][1])
    assertEquals("Vile Poacher", events[1][2])
    assertEquals(fade0 + 1, M.counts.fading)
    -- E2, the half the shipped default moves: the BELL and the EVENT are the
    -- source's law and ride the row's threshold; only the SEND is gated, and
    -- the gate below is the box this test ticked.
    ST:Set("RaidMsg", "BanishFadeParty", false)
    local sent0, off0 = Announce.counts.sent, Announce.counts.offSkipped
    local rowOff = Rows:InsertFromAura("Banish", "River Crocolisk",
        clock[1] + 10, 10, 0, nil, 0, clock[1])
    clock[1] = clock[1] + 7.5
    Rows:Sweep(clock[1])
    assertEquals(2, #events, "the fade event rings for the row")
    assertEquals(sent0, Announce.counts.sent, "the un-ticked send is off")
    -- Two counted opt-outs, not one: a fade is TWO gated sends (the party
    -- half and the channel half), and `OnTimerFading` calls both, so one
    -- un-ticked fade moves `offSkipped` by two. The row's true expiry, which
    -- arrives on the bus in this same sweep (E3), moves it by NOTHING: its
    -- announce calls are behind `cfg.ExpireAnnounce`/`ExpireChannel` in the
    -- subscriber, so an off row never reaches the counting gate at all.
    assertEquals(off0 + 2, Announce.counts.offSkipped)
    ST:Set("RaidMsg", "BanishFadeParty", true)
    clock[1] = clock[1] + 0.5                 -- pumping more: no third fire
    Rows:Sweep(clock[1])
    assertEquals(2, #events)
    assertNotNil(rowOff)
    -- The original's TimerFadeSound law (Forte_Timer.lua:3297, x2) rings for
    -- EVERY row that crosses its threshold, and this test has just made two
    -- of them cross (the ticked row above, the un-ticked one here): two
    -- crossings x the x2 bell = four plays. The SEND is the gated half, the
    -- bell is the row's own law (E2's split).
    assertEquals(4, #plays)
    assertEquals("Sound\\Spells\\ShaysBell.wav", plays[1])
    -- The fade message, bit 1 = the party line (verbatim).
    assertEquals(1, #sent)
    assertEquals("PARTY", sent[1].chatType)
    assertEquals(">> Banish on Vile Poacher Fading in 3 seconds! <<",
        sent[1].text)
    Sounds.playFn = nil
    FX.Off(h)
    Rows:Clear()
    restoreAll()
end)

test("a bare expiry of an UNREGISTERED spell (Corruption) fires no FADING "
.. "and plays no bell (no per-expiry defaults -- the review law)",
function()
    local Rows = enableTimer()
    installReaders({})
    local clock = { 41000 }
    FX.Timer.Casts.now = function() return clock[1] end
    local row = Rows:InsertFromAura("Corruption", "Vile Poacher",
        clock[1] + 9, 9, 0, nil, 0, clock[1])
    assertEquals(0, row.fadeWarn)
    local events = {}
    local h = FX.On(FX.EVENTS.TIMER_FADING, function()
        events[#events + 1] = true end)
    local h2 = FX.On(FX.EVENTS.TIMER_EXPIRED, function()
        events[#events + 1] = "e" end)
    local plays = {}
    Sounds.playFn = function(path) plays[#plays + 1] = path end
    for _ = 1, 10 do
        clock[1] = clock[1] + 1.0
        Rows:Sweep(clock[1])
    end
    for _, e in ipairs(events) do
        assertTrue(e ~= true, "the fade event never rides an expiry")
    end
    assertEquals(0, #plays,
        "the true-expiry bell is opt-in and default OFF (the fade is the "
        .. "original's warning)")
    Sounds.playFn = nil
    FX.Off(h); FX.Off(h2)
    Rows:Clear()
    restoreAll()
end)

test("BROKEN: the aura sweep's early removal fires the event, the break "
.. "sound x4, and the break line to the party", function()
    local Rows = enableTimer()
    installReaders({})
    -- E2: the SHIPPED default of this send is OFF. The source's row
    -- (Warlock.lua:389) shipped bit1 party ON and the row's tip says so; a
    -- default install does not announce a crowd-control break to a party
    -- that never asked. What is NOT gated is the source's law: the event,
    -- the four sounds -- both ring on every break below.
    ST:Set("RaidMsg", "BanishBreakParty", true)
    local clock = { 42000 }
    FX.Timer.Casts.now = function() return clock[1] end
    local row = Rows:InsertFromAura("Banish", "Vile Poacher",
        clock[1] + 10, 10, 0, nil, 0, clock[1])
    local events = {}
    local h = FX.On(FX.EVENTS.TIMER_BROKEN, function(s, t, k)
        events[#events + 1] = { s, t, k } end)
    local plays = {}
    Sounds.playFn = function(path) plays[#plays + 1] = path end
    local broken0 = M.counts.broken
    -- PAST the BUFF_DELAY grace with 5 s (> MAXLAG) of window left: the
    -- absence fact is the break (the :1207 site).
    assertEquals("removed", Rows:OnAuraAbsent(row, clock[1] + 5))
    assertEquals(1, #events)
    assertEquals("Banish", events[1][1])
    assertEquals("Vile Poacher", events[1][2])
    assertEquals(broken0 + 1, M.counts.broken)
    assertEquals(4, #plays, "the original's TimerBreakSound x4, :3298")
    assertEquals("Sound\\Spells\\SimonGame_Visual_LevelStart.wav", plays[1])
    assertEquals(">> Banish on Vile Poacher Broke Early! <<", sent[1].text)
    assertEquals("PARTY", sent[1].chatType)
    -- Inside the last-MAXLAG band the absence is NOT a break: refused, no
    -- event, no sound.
    local n0 = #events
    local row2 = Rows:InsertFromAura("Banish", "River Crocolisk",
        clock[1] + 20, 20, 0, nil, 0, clock[1])
    Rows:OnAuraAbsent(row2, row2.castTime + 19.5)
    assertEquals(n0, #events)
    Sounds.playFn = nil
    FX.Off(h)
    Rows:Clear()
    restoreAll()
end)

test("E2: with the SHIPPED defaults a breaking CC row is SILENT on the chat "
.. "wire -- the event and the four sounds ring, the send does not",
function()
    local Rows = enableTimer()
    installReaders({})
    local clock = { 43500 }
    FX.Timer.Casts.now = function() return clock[1] end
    local sent0 = Announce.counts.sent
    local off0 = Announce.counts.offSkipped
    local plays = {}
    Sounds.playFn = function(path) plays[#plays + 1] = path end
    local events = {}
    local h = FX.On(FX.EVENTS.TIMER_BROKEN, function(s)
        events[#events + 1] = s end)
    local row = Rows:InsertFromAura("Sap", "Vile Crocolisk",
        clock[1] + 20, 20, 0, nil, 0, clock[1])
    assertNotNil(row)
    assertEquals(false, ST:Get("RaidMsg", "SapBreakParty"),
        "the shipped send is OFF")
    assertNil(row.unitToken, "the token stays nil: the fail-open shape")
    Rows:OnAuraAbsent(row, clock[1] + 5)
    assertEquals(1, #events, "the event is the source's law: it rings")
    assertEquals(4, #plays, "and so do the four break sounds")
    assertEquals(sent0, Announce.counts.sent, "the SEND is the box, off")
    -- Two counted opt-outs for the one break: `OnTimerBroken` runs the
    -- party half AND the channel half (the original's bits 1 and 2,
    -- Forte_Class/Warlock/Warlock.lua:389), and both of this row's shipped
    -- defaults are off, so each gate counts its own skip.
    assertEquals(off0 + 2, Announce.counts.offSkipped,
        "the gate counts both halves of the opt-out")
    assertEquals(0, #sent, "no chat line was written")
    Sounds.playFn = nil
    FX.Off(h)
    Rows:Clear()
    restoreAll()
end)

test("the threshold parses from the EDITED fade text (Fading in 5 -> 5), "
.. "and the fallback is 0.1", function()
    enable()
    ST:Set("RaidMsg", "BanishFadeText",
        ">> Banish on %s Fading in 5 seconds! <<")
    assertEquals(5, FX.Timer.FadeWarnings.Banish)
    ST:Set("RaidMsg", "BanishFadeText", ">> Banish fades soon! <<")
    assertEquals(0.1, FX.Timer.FadeWarnings.Banish,
        "no number in the text: the ST_GetFadeTime fallback 0.1 "
        .. "(Forte_Timer.lua:1597)")
    ST:Set("RaidMsg", "BanishFadeText",
        ">> Banish on %s Fading in 3 seconds! <<")
    assertEquals(3, FX.Timer.FadeWarnings.Banish)
end)

test("a foreign unit's cast is ignored (the player filter)", function()
    enable()
    installReaders({})
    local real = withSpellNames({ [706] = "Create Soulstone" })
    ST:Set("RaidMsg", "SoulstoneAnnounce", true)
    dispatch("UNIT_SPELLCAST_SENT", "party1", "Vile Poacher", "G:F", 706)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "party1", "G:F", 706)
    assertEquals(0, #sent)
    ST:Set("RaidMsg", "SoulstoneAnnounce", false)
    restoreSpellNames(real)
    restoreAll()
end)
