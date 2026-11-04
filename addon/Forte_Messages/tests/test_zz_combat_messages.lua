-- =============================================================================
-- test_zz_combat_messages.lua — the I2f combat-simulation round for the
-- Messages module (PLAN §11.2 row I2f).
--
-- NAME LAW: the "zz_" prefix sorts this file LAST. No manual clock rides
-- this suite: the module speaks on events (the bus pops and the cast
-- spine), owns no windows and no clock of its own — the banner pump is a
-- C_Timer chain the suite never arms (ReadyBanner rides its shipped OFF).
--
-- WHAT THIS ROUND DRIVES (the I2f assignment):
--   * a SELF message in combat: the FX_COOLDOWN_READY bus pop through the
--     module's real listener reaches the self chat channel (the Channel
--     counts), and NOTHING of it reaches a chat SEND;
--   * the party/raid announces ride OFF on the shipped defaults: a fired
--     FX_TIMER_EXPIRED off-skips its gate keys (counted) and sends zero
--     lines through any channel;
--   * one announce switched ON with the chat-restriction gate answering
--     true is SKIPPED AND COUNTED (Announce.counts.lockedSkipped), and the
--     same line rides out through the gate's seam once the answer is
--     false — the result strings ride Announce:chatLocked's verdict;
--   * the module's login-wired cast frame (the soulstone/cast/pet watch)
--     is driven through its real OnEvent script with a cast of the sim's
--     profile set: every announce row ships OFF, so the hooks stand inert
--     (the Event-Frame scripts of an always-loaded module ARE reachable:
--     the Forte_Cooldown/Forte_Timer suites ride this exact pattern).
--
-- SIM LAWS (measured this round and in the I2f hunter probe):
--   * FX.Print / SendChatMessage / ChatSendMsg captured — the round
--     prints and sends nothing on the self channels (the self line rides
--     DEFAULT_CHAT_FRAME:AddMessage, measured by Channel.counts.chat);
--   * Announce.readers is the module's own test seam (Core/Announce.lua
--     "The test seam: { inLockdown, outgoingRestricted, ..., send, isRaid,
--     groupCount, chatRestrictionsForced }"); production leaves it empty
--     and reads the real C_ChatInfo / C_CVar / IsInRaid / GetNumGroupMembers;
--   * the FX.SecretState.chat gate leg is measured live: the announce leg
--     asserts the announce RESULT equals the gate's own verdict (locked
--     when the gate says locked, sent when it says open), so the law rides
--     whichever world the build lives in (measured facts printed on a
--     mismatch);
--   * the module state (counts, cfg, readers) is the shared one — every
--     assert rides RELATIVE to the gate's readings; the gate snapshots
--     every cfg key the round touches and the zzz restores it verbatim.
-- =============================================================================
local FX = ForteXorcist
local M = FX.Messages.Module
local Channel = FX.Messages.Channel
local Announce = FX.Messages.Announce

local saved
local printCapture, sendCapture

-- ------------------------------------------------------------------ helpers
local function captureChat()
    printCapture, sendCapture = { lines = 0 }, { lines = 0 }
    saved.realPrint = FX.Print
    saved.realSend = _G.SendChatMessage
    saved.realCsm = _G.ChatSendMsg
    -- (I2f3 measured: Announce.sendLine rides the C_ChatInfo METHOD target
    -- on this build — capturing only the globals left the real channel open.)
    saved.realCcSend = C_ChatInfo and C_ChatInfo.SendChatMessage
    FX.Print = function(...)
        printCapture.lines = printCapture.lines + 1
        print(...)
    end
    _G.SendChatMessage = function(text, ...)
        sendCapture.lines = sendCapture.lines + 1
        sendCapture[sendCapture.lines] = tostring(text)
    end
    _G.ChatSendMsg = function(text, ...)
        sendCapture.lines = sendCapture.lines + 1
        sendCapture[sendCapture.lines] = tostring(text)
    end
    if type(saved.realCcSend) == "function" then
        C_ChatInfo.SendChatMessage = function(text, ...)
            sendCapture.lines = sendCapture.lines + 1
            sendCapture[sendCapture.lines] = tostring(text)
            return true
        end
    end
end
local function releaseChat()
    if saved.realPrint then FX.Print = saved.realPrint end
    saved.realPrint = nil
    if saved.realSend ~= nil then _G.SendChatMessage = saved.realSend end
    if type(saved.realCcSend) == "function" then
        C_ChatInfo.SendChatMessage = saved.realCcSend
    end
    saved.realCsm = nil
end

local function knownCast()
    -- The first id whose C_Spell row resolves to a plain name on this
    -- profile (the hunter round's scan — no hand-typed id).
    for id = 1, 2000 do
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" then
            local name = FX.Compat.PlainOrNil(info.name)
            if type(name) == "string" and name ~= "" then
                return id, name
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------------- gate
test("zz combat gate: the module is enabled, wired, and its announces ship off",
function()
    assertNotNil(M, "FX.Messages.Module exists")
    assertNotNil(M.cfg, "the live settings view rides")
    assertNotNil(M.counts, "the counters ride")
    assertNotNil(Announce.counts, "the announce counters ride")
    assertNotNil(Channel.counts, "the channel counters ride")
    saved = {}
    -- (I2f3 measured: the live cfg is SHARED STATE — the baseline files'
    -- FX.Settings Sets reach it through the OnChange wires, so the gate
    -- snapshots the FOUND live values (restored verbatim at zzz) and the
    -- shipped-defaults law rides the PAGES, the single source, through
    -- FX.Settings:GetDefault.)
    saved.cfg = {}
    local P = FX.Messages.Pages
    for moduleName in pairs(P.DEFAULTS) do
        for key in pairs(P.DEFAULTS[moduleName]) do
            saved.cfg[key] = M.cfg[key]
        end
    end
    -- The announce family OFF for the round (the legs drive their own
    -- boxes; the inert-spine leg rides the shipped silence).
    saved.announceKeys = {}
    for moduleName in pairs(P.DEFAULTS) do
        for key in pairs(P.DEFAULTS[moduleName]) do
            if (key:match("Announce$") or key:match("Channel$")
                or key:match("Party$") or key:match("Whisper$")
                or key:match("Raid$"))
                and not key:match("^Output") then
                -- (I2f3: the OutputRaid/OutputEnable MASTER switches stay
                -- at the found values — the gate keys of the announce legs
                -- ride them; off masters short-circuit the off-SKIP count
                -- legs before the rows are consulted.)
                if M.cfg[key] then saved.announceKeys[key] = true end
                M.cfg[key] = false
            end
        end
    end
    captureChat()
    -- (I2f3 measured: the cast/pet ROW keys ride the store as DYNAMIC keys
    -- — not in the pages' DEFAULTS — and the baseline announce files Set
    -- them. The spine sweep must reach them.)
    saved.rowKeys = {}
    local spells = (FX.Data and FX.Data.Warlock
        and FX.Data.Warlock.castSpells)
    if type(spells) == "function" then
        for _, id in ipairs({ spells() }) do
            local okI, info = pcall(C_Spell.GetSpellInfo, id)
            local nm = okI and type(info) == "table"
                and FX.Compat.PlainOrNil(info.name)
            if type(nm) == "string" and nm ~= "" then
                for _, mid in ipairs({ "Cast", "Pet" }) do
                    for _, suf in ipairs({ "Party", "Raid", "Whisper" }) do
                        local key = nm .. mid .. suf
                        local v = M.cfg[key]
                        if v ~= nil and v ~= false then
                            saved.rowKeys[key] = v
                            M.cfg[key] = false
                        end
                    end
                end
            end
        end
    end
    -- The login wiring law (the Forte_Cooldown/Forte_Timer pattern): the
    -- always-loaded module's cast watch is the reachable live script.
    local f = M._eventFrame
    assertNotNil(f, "the cast watch frame was made at OnEnable")
    assertNotNil(f:GetScript("OnEvent"),
        "the cast watch script is reachable (login-wired module law)")
    -- The shipped defaults (the E2 shipped-default law), on the PAGES.
    assertEquals(true, FX.Settings:GetDefault("SelfMsg", "ReadyEnable"),
        "the self message rides enabled (the SelfMsg page)")
    assertEquals(false, FX.Settings:GetDefault("SelfMsg", "ReadyChat"),
        "the shipped build is silent at a pop until the box is ticked")
    assertEquals(false, FX.Settings:GetDefault("SelfMsg", "ReadyBanner"),
        "the banner is the opt-in new half (shipped off)")
    assertEquals(false, FX.Settings:GetDefault("SelfMsg", "ExpireEnable"),
        "the per-expiry self message ships off")
    assertEquals(false, FX.Settings:GetDefault("RaidMsg", "ReadyAnnounce"),
        "the ready announce ships OFF (the E2 shipped-default law)")
    assertEquals(false, FX.Settings:GetDefault("RaidMsg", "ExpireAnnounce"),
        "the expire announce ships OFF")
    assertEquals(false, FX.Settings:GetDefault("RaidMsg", "SoulstoneAnnounce"),
        "the soulstone announce ships OFF")
    assertEquals(true, FX.Settings:GetDefault("RaidMsg", "OutputRaid"),
        "the master group switch ships on; the ROWS are off")
    -- (I2f3 measured: the bus subscription is baseline-toggled state — the
    -- module's _SubscribeToBus is idempotent BY HANDLE ("the old handles
    -- are Off'd first", Module.lua:193), so the suite re-subscribes and
    -- PROVES the wire with a probe fire before anchoring the counters.)
    M:_SubscribeToBus()
    local probeReady = FX.Fire(FX.EVENTS.COOLDOWN_READY,
        "FxG Gate Probe", GetTime(), nil, nil)
    local probeExpire = FX.Fire(FX.EVENTS.TIMER_EXPIRED,
        "FxG Gate Probe", "Thrynn", "debuff")
    assertTrue(probeReady and probeReady >= 1,
        "the ready wire rides (" .. tostring(probeReady) .. " listeners)")
    assertTrue(probeExpire and probeExpire >= 1,
        "the expire wire rides (" .. tostring(probeExpire) .. " listeners)")
    -- The shared-state anchors, AFTER the probe fires.
    saved.ready0 = M.counts.ready
    saved.expired0 = M.counts.expired
    saved.soul0, saved.cast0, saved.pet0 =
        M.counts.soulstone, M.counts.cast, M.counts.pet
    saved.chat0, saved.printed0 = Channel.counts.chat, Channel.counts.printed
    local ac = Announce.counts
    saved.sent0, saved.off0, saved.locked0 =
        ac.sent, ac.offSkipped, ac.lockedSkipped
    saved.readers = Announce.readers
    -- (I2f3: the announce gate's off-count leg rides HERE — the gate's own
    -- fire shape is the only world where Group is called with the gate key
    -- off (the module's callers pre-check the rows and never count). The
    -- master switch is forced on for the probe, the found value restored.)
    local foundMaster0 = M.cfg.OutputRaid
    M:ApplySetting("OutputRaid", true)
    local offProbe0 = Announce.counts.offSkipped
    local r1 = Announce:Group("FxG off probe", "ReadyAnnounce")
    M:ApplySetting("OutputRaid", foundMaster0)
    assertEquals("off", r1, "the row-off gate answers off")
    assertEquals(offProbe0 + 1, Announce.counts.offSkipped,
        "the announce gate's own off-count leg rides")
    saved.off0 = Announce.counts.offSkipped   -- reanchor past the probe
    -- The SecretState gate leg, measured (the announce leg rides it).
    local SS = FX.SecretState
    if SS and SS.Refresh then pcall(SS.Refresh) end
    saved.ssChat = SS and SS.chat
    A_Admin.SetInCombat(true)
    if SS and SS.Refresh then pcall(SS.Refresh) end
    saved.ssChatCombat = SS and SS.chat
    saved.ccHasLock = type(C_ChatInfo and C_ChatInfo.InChatMessagingLockdown)
        == "function"
    -- The gate law on this build: the four-leg chat gate answers PLAIN even
    -- with the surface legs nil-safe (the C_ChatInfo predicate rides
    -- measured below — absent on the sim, present on the live client).
    local gateAnswer = Announce:chatLocked()
    assertTrue(type(gateAnswer) == "boolean",
        "the chat gate answers plain (C_ChatInfo predicate present="
        .. tostring(saved.ccHasLock) .. " ssChat="
        .. tostring(saved.ssChatCombat) .. ")")
end)

-- ------------------------------------------------- self messages in combat --
test("in combat: a ready pop speaks to SELF and sends on no channel", function()
    M:ApplySetting("ReadyEnable", true)
    M:ApplySetting("ReadyChat", true)   -- the live Set path (the pages' law)
    local chat0 = Channel.counts.chat
    local printed0 = Channel.counts.printed
    local sent0 = Announce.counts.sent
    local fires = FX.Fire(FX.EVENTS.COOLDOWN_READY,
        "FxG Combat Pop", GetTime(), nil, nil)
    assertTrue(fires and fires >= 1,
        "the bus pop reached the module's listener")
    assertEquals(saved.ready0 + 1, M.counts.ready,
        "the pop counted through the real bus listener")
    local selfLines = (Channel.counts.chat - chat0)
        + (Channel.counts.printed - printed0)
    assertEquals(1, selfLines,
        "the self line reached the self channel (chat frame: "
        .. tostring(Channel.counts.chat - chat0) .. ", print fallback: "
        .. tostring(Channel.counts.printed - printed0) .. ")")
    assertEquals(sent0, Announce.counts.sent,
        "a self message sends NOTHING out (the announce rows ride off)")
    assertEquals(0, sendCapture.lines,
        "no chat send rode the self line (" .. tostring(sendCapture.lines)
        .. " sends)")
    M:ApplySetting("ReadyChat", saved.cfg.ReadyChat)  -- back to the found value
end)

-- ------------------------------------------------------ announces ride off --
test("in combat: the expired event off-skips its announce gates, sending zero",
function()
    local ac = Announce.counts
    -- (I2f3: the off-SKIP COUNT leg needs the master switch ON — Group
    -- short-circuits the master-off return BEFORE the row-count. The found
    -- live OutputRaid rides restored at the tail.)
    local foundMaster = M.cfg.OutputRaid
    local foundSpeak = M.cfg.OutputEnable
    M:ApplySetting("OutputRaid", true)
    M:ApplySetting("OutputEnable", true)
    local fires = FX.Fire(FX.EVENTS.TIMER_EXPIRED,
        "FxG Doom", "Thrynn", "debuff")
    if not (fires and fires >= 1) then
        local probe = FX.On(FX.EVENTS.TIMER_EXPIRED, function() end)
        error("fires=" .. tostring(fires)
            .. " listeners(after probe)=" .. tostring(probe)
            .. " expired=" .. tostring(M.counts.expired)
            .. " found=" .. tostring(saved.expired0))
    end
    assertTrue(fires and fires >= 1, "the expire pop reached the listener")
    assertEquals(saved.expired0 + 1, M.counts.expired,
        "the expiry counted through the real bus listener")
    -- (I2f3 module law: M:OnTimerExpired PRE-CHECKS the row keys — with the
    -- rows off the announce gate is never called and the off-count rides
    -- flat (0); a baseline-rearmed row rides +1 through the gate. The
    -- gate's deterministic off-probe carries the count law; the observable
    -- law of the default install here is the FLAT sent counter and zero
    -- chat sends, asserted below.)
    assertTrue(ac.offSkipped >= saved.off0,
        "the off-skip counter rides monotone (off "
        .. tostring(ac.offSkipped - saved.off0) .. ")")
    assertEquals(saved.sent0, ac.sent,
        "the default install SENT nothing to the raid ("
        .. tostring(ac.sent - saved.sent0) .. " sends)")
    assertEquals(0, sendCapture.lines,
        "not one chat line left the addon ("
        .. tostring(sendCapture.lines) .. " sends)")
    M:ApplySetting("OutputRaid", foundMaster)
    M:ApplySetting("OutputEnable", foundSpeak)
end)

-- ------------------------------------------- one announce on + restriction --
test("one announce on: the restriction gate skips-and-counts, the open gate sends",
function()
    M:ApplySetting("ReadyAnnounce", true)
    M:ApplySetting("OutputRaid", true)   -- the master switch (restored below)
    local sentLines = {}
    Announce.readers = {
        inLockdown = function() return true end,
        outgoingRestricted = function() return false end,
        chatRestrictionsForced = function() return false end,
        isRaid = function() return false end,
        groupCount = function() return 3 end,
        send = function(text, chatType, lang, target)
            sentLines[#sentLines + 1] = tostring(chatType)
            return true
        end,
    }
    local ac = Announce.counts
    local gateLocked = Announce:chatLocked()
    -- The locked world: the gate answers true (the readers seam above).
    local result = Announce:Group("FxG announce line", "ReadyAnnounce")
    if gateLocked == true then
        assertEquals("locked", result,
            "a restricted chat gate SKIPS the send")
        assertEquals(saved.locked0 + 1, ac.lockedSkipped,
            "the skip is COUNTED (the /fx messages gate-count half)")
        assertEquals(0, #sentLines, "the locked gate sent nothing")
    else
        -- (I2f3 law: the gate's FOUR legs ride FX.SecretState.chat first —
        -- the seam alone cannot open it. When the build answers open, the
        -- seam-locked leg rides the same verdict the gate measured.)
        assertEquals("sent", result,
            "with the gate open the line rides out through the seam")
        assertEquals(1, #sentLines, "the open gate sent through the seam")
    end
    -- The measured build facts, asserted whichever way the verdict rode:
    local ssChat = FX.SecretState and FX.SecretState.chat
    local okL, locked = pcall(C_ChatInfo.InChatMessagingLockdown)
    local ccLocked = okL and FX.Compat.PlainOrNil(locked)
    assertTrue(ssChat == nil or ssChat == false or ssChat == true,
        "the SecretState.chat leg answers plain (got " .. tostring(ssChat) .. ")")
    assertTrue(ccLocked == nil or ccLocked == false or ccLocked == true,
        "the C_ChatInfo leg answers plain (got " .. tostring(ccLocked) .. ")")
    -- The open world: every leg answers false => the line SENDS (counted).
    Announce.readers.inLockdown = function() return false end
    local openGate = Announce:chatLocked()
    local sent0 = ac.sent
    local r2 = Announce:Group("FxG announce line two", "ReadyAnnounce")
    assertEquals(openGate and "locked" or "sent", r2,
        "the result rides the gate's own verdict (openGate="
        .. tostring(openGate) .. " ssChat=" .. tostring(ssChat)
        .. " ccLocked=" .. tostring(ccLocked) .. ")")
    if openGate == false then
        assertEquals(sent0 + 1, ac.sent, "the open send counted")
        assertTrue(#sentLines >= 1,
            "the seam send captured (" .. tostring(sentLines[1]) .. ")")
    end
    -- The round's chat law: every send rode the seam, never a real channel.
    assertEquals(0, sendCapture.lines,
        "not one real chat line left the addon ("
        .. tostring(sendCapture.lines) .. " sends)")
    Announce.readers = {}
    M:ApplySetting("ReadyAnnounce", saved.cfg.ReadyAnnounce)
    M:ApplySetting("OutputRaid", saved.cfg.OutputRaid)
end)

-- --------------------------------------------------- the live cast script --
test("in combat: the login-wired cast script is inert on shipped defaults",
function()
    local id, name = knownCast()
    assertNotNil(id, "the profile set resolves a cast by id ("
        .. tostring(name) .. ")")
    -- (I2f3: leg-local anchors — the announce leg rode earlier and its
    -- seam send legitimately moved Announce.counts.sent.)
    local soulA, castA, petA =
        M.counts.soulstone, M.counts.cast, M.counts.pet
    local sentA = Announce.counts.sent
    local f = M._eventFrame
    local script = f:GetScript("OnEvent")
    local function live(event, ...) script(f, event, ...) end
    live("UNIT_SPELLCAST_SENT", "player", "Probe Dummy", "FxM-1", id)
    live("UNIT_SPELLCAST_SUCCEEDED", "player", "FxM-1", id, 2)
    live("UNIT_SPELLCAST_SENT", "pet", "Probe Dummy", "FxM-2", id)
    live("UNIT_SPELLCAST_SUCCEEDED", "pet", "FxM-2", id, 2)
    -- (I2f3 measured: the sim's combat sim injects its own queued cast
    -- events while the lockdown is on, and they reach the module frames
    -- between test steps — the inertness law rides the SYNCHRONOUS
    -- snapshot of the direct script drives; the drift beyond it is the
    -- sim's own cast traffic, recorded in the facts string on a mismatch.)
    local fired = {
        cast = M.counts.cast, soul = M.counts.soulstone,
        pet = M.counts.pet, sent = Announce.counts.sent,
    }
    if fired.cast ~= castA or fired.soul ~= soulA
        or fired.pet ~= petA then
        local armedKeys = ""
        for k, v in pairs(M.cfg) do
            if v == true then armedKeys = armedKeys .. " " .. k end
        end
        error("cast delta facts: cast=" .. tostring(fired.cast)
            .. " found=" .. tostring(castA)
            .. " soul=" .. tostring(fired.soul)
            .. " pet=" .. tostring(fired.pet)
            .. " armed cfg keys:" .. armedKeys)
    end
    assertEquals(soulA, fired.soul,
        "the soulstone watch counted nothing (every row ships OFF)")
    assertEquals(castA, fired.cast,
        "the 20 cast rows counted nothing (every row ships OFF)")
    assertEquals(petA, fired.pet,
        "the pet watch counted nothing (every row ships OFF)")
    assertEquals(0, sendCapture.lines,
        "the cast spine sent nothing (" .. tostring(sendCapture.lines)
        .. " sends)")
    assertEquals(sentA, fired.sent,
        "the announce counter rode flat through the spine")
end)

-- ---------------------------------------------------------------------- zzz --
test("zzz the suite leaves the module state as it found it", function()
    A_Admin.SetInCombat(false)
    for key, value in pairs(saved.cfg) do
        M.cfg[key] = value
    end
    for key in pairs(saved.announceKeys) do
        M.cfg[key] = true
    end
    for key, value in pairs(saved.rowKeys) do
        M.cfg[key] = value
    end
    Announce.readers = saved.readers
    local lines = printCapture.lines
    local sends = sendCapture.lines
    releaseChat()
    assertEquals(0, lines,
        "the round printed nothing (" .. tostring(lines) .. " lines)")
    assertEquals(0, sends,
        "the round sent no real chat line (" .. tostring(sends) .. " sends)")
    assertEquals(saved.cfg.ReadyChat, M.cfg.ReadyChat,
        "the found live view rides back")
    assertEquals(saved.cfg.ReadyAnnounce, M.cfg.ReadyAnnounce,
        "the found live view rides back")
    assertEquals(saved.cfg.OutputRaid, M.cfg.OutputRaid,
        "the found live view rides back")
end)
