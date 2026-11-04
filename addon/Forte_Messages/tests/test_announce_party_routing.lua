-- addon/Forte_Messages/tests/test_announce_party_routing.lua
-- FX7b: the ToGroup routing on the REAL client, where the `Announce.readers`
-- seam is NIL and the gate reads the game's own `IsInRaid` /
-- `GetNumGroupMembers`.
--
-- `plainCall` here is the BOOLEAN half of the plain-read family (it answers
-- `plain and true or false`), and every boolean in this file belongs to it:
-- `InChatMessagingLockdown`, `AreOutgoingAddonChatMessagesRestricted`,
-- `C_CVar.GetCVarBool(addonChatRestrictionsForced)` and `IsInRaid`.
-- `GetNumGroupMembers` is NOT one of them: it answers a COUNT. 4 through the
-- boolean helper is `true`, `tonumber(true)` is nil, `(nil or 0) > 0` is
-- false, and `Announce:Group` fell through to the no-group local echo — so an
-- opted-in party announce never reached the party on the shipped client
-- (same shape, same line, as Forte_Warlock/Core/Comms.lua's Channel()). The
-- count needs the NUMERIC plain read (pcall, PlainOrNil, tonumber).
--
-- The suite's other announce tests drive the `groupCount` seam — a function
-- answering a plain number, the one shape the buggy line handled — which is
-- exactly why the defect survived every green run. These tests stub the
-- game's globals and leave the seam nil, with the three chat-restriction
-- readers answering plain false so the gate is open and the ROUTING is what
-- is under test.
--
-- Every body runs under pcall with its row/gate/global cleanups outside it:
-- the suite shares one `M.cfg`, one `Announce` singleton and one chat frame,
-- so a body that fails half-way through must not leave a send row ticked for
-- the next file.

local FX = ForteXorcist
local M = FX.Messages.Module
local Announce = FX.Messages.Announce
local ST = FX.Settings

local sent
local savedGroup          -- the game globals this file borrowed, once

local function enable()
    if not M.cfg then M:OnEnable() end
end

local function resetAnnounce()
    Announce.readers = {}
    if FX.SecretState then FX.SecretState.chat = nil end
    sent = {}
end

--- The open gate: every legality reader answers a plain false (no lockdown),
--- the send is captured. `isRaid` / `groupCount` are DELIBERATELY absent —
--- nil seam slots are the real client.
local function openGate()
    Announce.readers = {
        inLockdown = function() return false end,
        outgoingRestricted = function() return false end,
        chatRestrictionsForced = function() return false end,
        send = function(text, chatType)
            sent[#sent + 1] = { text = text, chatType = chatType }
        end,
    }
end

--- The game's own group surface: the REAL globals answer, so the module
--- walks the path the shipped client presents.
local function useRealGroup(isRaid, members)
    if not savedGroup then
        savedGroup = { raid = _G.IsInRaid, members = _G.GetNumGroupMembers }
    end
    _G.IsInRaid = function() return isRaid end
    _G.GetNumGroupMembers = function()
        return type(members) == "function" and members() or members
    end
end
local function restoreRealGroup()
    if savedGroup then
        _G.IsInRaid, _G.GetNumGroupMembers = savedGroup.raid, savedGroup.members
        savedGroup = nil
    end
end

--- The spell-name surface the family rows resolve through.
local savedSpellNames = nil      -- a table once saved: { fn = ... }
local function useRealSpellNames(names)
    if not savedSpellNames then
        savedSpellNames = { fn = C_Spell and C_Spell.GetSpellInfo }
    end
    _G.C_Spell = _G.C_Spell or {}
    C_Spell.GetSpellInfo = function(id)
        local n = names[id]
        return n and { spellID = id, name = n } or nil
    end
end
local function restoreRealSpellNames()
    if savedSpellNames then
        if C_Spell then C_Spell.GetSpellInfo = savedSpellNames.fn end
        savedSpellNames = nil
    end
end

--- A body that fails must leave the shared suite exactly as it found it.
local function guarded(body)
    enable()
    resetAnnounce()
    openGate()
    local ok, err = pcall(body)
    ST:Set("RaidMsg", "ReadyAnnounce", false)
    ST:Set("RaidMsg", "SoulstoneAnnounce", false)
    restoreRealGroup()
    restoreRealSpellNames()
    resetAnnounce()
    if not ok then error(err, 0) end
end

-- ------------------------------------------------------------ the ToGroup --

test("FX7b: an opted-in party announce with 4 members from the REAL "
.. "GetNumGroupMembers goes out on PARTY (the boolean plainCall read the "
.. "count as `true` and the line fell to the no-group echo)", function()
    guarded(function()
        ST:Set("RaidMsg", "OutputRaid", true)
        ST:Set("RaidMsg", "ReadyAnnounce", true)
        useRealGroup(false, 4)

        -- The seam is nil: the shipped client's path, not the suite's.
        assertEquals(nil, Announce.readers.groupCount, "no seam on the client")
        assertEquals(nil, Announce.readers.isRaid)

        local echo0 = Announce.counts.noGroup
        local sent0 = Announce.counts.sent
        local locked0 = Announce.counts.lockedSkipped
        FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 1.0, nil, nil)
        assertEquals(1, #sent,
            "the party received the ready line the owner ticked the box for")
        assertEquals("PARTY", sent[1].chatType)
        assertEquals(">> Rapid Fire is ready <<", sent[1].text)
        assertEquals(sent0 + 1, Announce.counts.sent)
        assertEquals(echo0, Announce.counts.noGroup,
            "a four-man party is not an echo-locally no-group")
        assertEquals(locked0, Announce.counts.lockedSkipped,
            "the open gate stayed open: this is the routing, not the gate")

        -- The zero half: an empty count is still no group — the local echo,
        -- the original's FW:Show law, with no send.
        resetAnnounce(); openGate()
        useRealGroup(false, 0)
        local echo1 = Announce.counts.noGroup
        FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 2.0, nil, nil)
        assertEquals(0, #sent, "no members, no party line")
        assertEquals(echo1 + 1, Announce.counts.noGroup)

        -- The raid half rides the BOOLEAN helper (`IsInRaid` answers a bool)
        -- and keeps working.
        resetAnnounce(); openGate()
        useRealGroup(true, 20)
        FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 3.0, nil, nil)
        assertEquals(1, #sent)
        assertEquals("RAID", sent[1].chatType)

        -- A count API with no surface (it raises) is no evidence of an
        -- audience: the line echoes locally, the gate never guesses a channel.
        resetAnnounce(); openGate()
        useRealGroup(false, function() error("FXTEST-NO-GROUP-SURFACE", 0) end)
        local echo2 = Announce.counts.noGroup
        FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 4.0, nil, nil)
        assertEquals(0, #sent, "a raising read names no audience")
        assertEquals(echo2 + 1, Announce.counts.noGroup)
    end)
end)

test("FX7b: a Warlock family announce on the real group surface routes to "
.. "the party through the event frame (the shipped cast path)", function()
    guarded(function()
        useRealSpellNames({ [706] = "Create Soulstone" })
        ST:Set("RaidMsg", "SoulstoneAnnounce", true)
        useRealGroup(false, 5)
        local echo0 = Announce.counts.noGroup

        local f = M._eventFrame
        assertNotNil(f)
        local onEvent = f:GetScript("OnEvent")
        assertNotNil(onEvent)
        onEvent(f, "UNIT_SPELLCAST_SENT", "player", "Vile Poacher", "G:1", 706)
        onEvent(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "G:1", 706)

        assertEquals(1, #sent, "the party heard the soulstone")
        assertEquals("PARTY", sent[1].chatType)
        assertEquals("Soulstoned >> Vile Poacher << Use it well!", sent[1].text)
        assertEquals(echo0, Announce.counts.noGroup,
            "a five-man party is no echo: the line went out")
    end)
end)

-- ------------------------------------------- the default install stays mute --

test("FX7b: a party the real globals name changes NOTHING for a default "
.. "install — every send row is OFF and the party is silent", function()
    guarded(function()
        useRealGroup(false, 5)
        local sent0 = Announce.counts.sent
        local off0 = Announce.counts.offSkipped
        local echo0 = Announce.counts.noGroup
        -- Every shipped row is off by E2; a full party must not move the
        -- SEND. The off rows are read by the MODULE before the gate is
        -- entered, and an opt-out read there is the same opt-out the gate
        -- counts when it reads the row inside itself, so the party half and
        -- the channel half each count one off-skip (test "a module-side
        -- announce pre-check COUNTS as an off-skip" in test_announce.lua): a
        -- default install reporting `off-skipped 0` to `/fx messages` is the
        -- instrument reading a fully opted-out install as if it had spoken.
        FX.Fire(FX.EVENTS.COOLDOWN_READY, "Rapid Fire", 5.0, nil, nil)
        assertEquals(0, #sent, "a default install speaks to no party")
        assertEquals(sent0, Announce.counts.sent)
        assertEquals(off0 + 2, Announce.counts.offSkipped,
            "the row's own opt-out is read, and counted, by the module")
        assertEquals(echo0, Announce.counts.noGroup,
            "a party is not a no-group echo, and an off row reaches no echo")
    end)
end)
