-- addon/Forte_Warlock/tests/test_warlock_group.lua
-- H6: the group comms wire (Core/Comms.lua encode/decode/gates/rates), the
-- roster model (Core/Group.lua) and the Healthstone Spy's plate half — the
-- solo-testable halves the wave-2b row names: encode/decode round trip, a
-- STUBBED CHAT_MSG_ADDON from a fake party member (driven through the
-- comms event frame's own OnEvent script, the payload order of
-- ChatInfoDocumentation.lua:800) moving the spy display (IsShown via the
-- kick path), a restricted send skipped AND counted, a malformed message
-- ignored. The lockdown readers are the documented seam (Comms.readers, the
-- Announce.readers convention) and FX.SecretState.chat is set directly — the
-- sim ships no C_ChatInfo lockdown controls; the CONTRACT under test is what
-- a true/false/nil answer does to the send, not the client's plumbing.
-- The multiplayer-only behaviours (live delivery, prefix registration on the
-- real client, in-instance lockdown bite) are the launch-day probes listed
-- in docs/warlock-tools.md.

local FX = ForteXorcist
local WK = FX.Warlock
local C = FX.Warlock.Comms
local Tools = FX.Warlock.Tools
local HS = FX.Warlock.Healthstone
local UI = FX.Warlock.UI

local function freshGroup() return WK.NewGroup() end

local savedCounts
local function resetComms()
    C.readers = {}
    C._lastAt = {}
    C._lastSent = {}
    C._lastTarget = nil
    C.group = freshGroup()
    if not savedCounts then
        savedCounts = {}
        for k, v in pairs(C.counts) do savedCounts[k] = v end
    end
    for k in pairs(C.counts) do C.counts[k] = 0 end
end

-- =============================================================== the wire --

test("encode/decode round-trips every command, mirrors rejecting junk",
function()
    resetComms()
    local pairs = {
        { C.Encode("HG"), "HG1" },
        { C.Encode("SG"), "SG1" },
        { C.Encode("HS", 0), "HS1 0" },
        { C.Encode("HS", 7), "HS1 7" },
        { C.Encode("SH", 32), "SH1 32" },
        { C.Encode("SU", "Alice", "Bob"), "SU1 Alice Bob" },
        { C.Encode("SE", "Alice", "Bob"), "SE1 Alice Bob" },
    }
    for _, p in ipairs(pairs) do
        assertEquals(p[2], p[1], "wire text")
    end
    -- The mirror: every encoded line decodes back to its inputs.
    local cmd, a = C.Decode("HS1 7")
    assertEquals("HS", cmd); assertEquals(7, a)
    cmd, a = C.Decode("SH1 0")
    assertEquals("SH", cmd); assertEquals(0, a)
    local c2, by, target = C.Decode("SU1 Alice Bob")
    assertEquals("SU", c2); assertEquals("Alice", by); assertEquals("Bob", target)
    cmd = C.Decode("HG1")
    assertEquals("HG", cmd)
    -- Encode refuses what Decode would refuse (no half-grammar).
    assertNil(C.Encode("HS", -1))
    assertNil(C.Encode("HS", 1.5))
    assertNil(C.Encode("HS"))
    assertNil(C.Encode("XX", 1))
    assertNil(C.Encode("SU", "A B", "C"))       -- the separator IS structural
    assertNil(C.Encode("SU", string.rep("x", 65), "C"))
    assertNil(C.Encode())
    -- Decode refuses: unknown prefix, foreign version, junk payloads,
    -- lowercase, trailing junk, the empty line.
    assertNil(C.Decode("XX1"))
    assertNil(C.Decode("HS2 3"))
    assertNil(C.Decode("HS1"))
    assertNil(C.Decode("HS1 x"))
    assertNil(C.Decode("HS1 1 2"))
    assertNil(C.Decode("HG1 3"))
    assertNil(C.Decode("hs1 3"))
    assertNil(C.Decode("SU1 Alice"))
    assertNil(C.Decode("SU1 Alice B C"))
    assertNil(C.Decode(""))
    assertNil(C.Decode(nil))
    assertNil(C.Decode(string.rep("x", 220)))
end)

-- ============================================================ the model ----

test("the roster model counts the spy the original's pass counts", function()
    local g = freshGroup()
    g:SetRoster({
        { name = "Alice", class = "WARLOCK", present = true, alive = true },
        { name = "Bob", class = "WARRIOR", present = true, alive = true },
        { name = "Cara", class = "WARLOCK", present = true, alive = true },
    })
    g:MarkAddon("Alice")
    g:MarkAddon("Bob")
    assertEquals(true, g:SetCount("Alice", "hs", 2))
    assertEquals(false, g:SetCount("Bob", "hs", -3))   -- junk never mutates
    assertEquals(false, g:SetCount("Bob", "nope", 3))
    g:SetCount("Cara", "shards", 5)
    g:MarkAddon("Cara")
    local s = g:HealthstoneSummary()
    assertEquals(3, s.active)          -- all three report in
    assertEquals(1, s.stones)          -- only Alice carries (HS-…:181-197)
    assertEquals(2, s.missing)
    assertEquals(0, s.unknown)
    g:SetRoster({ { name = "Alice", class = "WARLOCK", present = true } })
    s = g:HealthstoneSummary()        -- departed members drop out
    assertEquals(1, s.active)
    -- The shard spy column: warlocks only, the total over the reporters.
    g:SetRoster({
        { name = "Alice", class = "WARLOCK", present = true },
        { name = "Cara", class = "WARLOCK", present = true },
        { name = "Bob", class = "WARRIOR", present = true },
    })
    g:MarkAddon("Alice"); g:MarkAddon("Cara")
    g:SetCount("Cara", "shards", 9)
    local shard = g:ShardTotal()
    assertEquals(2, shard.warlocks)
    assertEquals(1, shard.known)
    assertEquals(9, shard.total)
    local rows = g:ShardRows(6)
    assertEquals(2, #rows)
    assertEquals("Alice", rows[1].name)   -- sorted, deterministic
    assertNil(rows[1].shards)
    -- The summon queue (SU-07): one entry per warlock, an end clears the
    -- sender's claim, a foreign <by> claim is the transport's job (below).
    g:SummonStart("Alice", "Bob")
    g:SummonStart("Cara", "Cara")
    assertEquals(2, g:QueueCount())
    local q = g:Queue(10)
    assertEquals("Alice", q[1].warlock); assertEquals("Bob", q[1].target)
    g:SummonEnd("Alice", "Bob")
    assertEquals(1, g:QueueCount())
    g:SummonEnd("Cara", "Bob")           -- a late end for an old target
    assertEquals(1, g:QueueCount())
    g:SummonEnd("Cara")                  -- target-agnostic end
    assertEquals(0, g:QueueCount())
end)

-- =================================================== inbound: chat message --

test("a stubbed CHAT_MSG_ADDON from a fake party member moves the spy",
function()
    resetComms()
    C.readers.selfName = function() return "Me" end
    local g = C.group
    g:SetRoster({
        { name = "Alice", class = "WARRIOR", present = true, alive = true },
        { name = "Bob", class = "WARLOCK", present = true, alive = true },
    })
    -- Through the comms frame's OWN OnEvent script, the catalog payload
    -- order (prefix, text, channel, sender, ...): the sender is the 4th.
    C:EnableEvents()
    local handler = C._eventFrame:GetScript("OnEvent")
    assertEquals("function", type(handler))
    local frame = C._eventFrame
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "HS1 2", "party", "Alice")
    assertEquals(2, g.members.Alice.hs)
    assertEquals(true, g.members.Alice.addon)
    -- A foreign prefix is not even counted as ours.
    assertEquals("foreignPrefix",
        C:OnAddonMessage("DBM", "HS1 9", "Alice"))
    assertEquals(2, g.members.Alice.hs)
    -- The self-echo law (CA-24): our own line never re-enters the model.
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "HS1 9", "party", "Me")
    assertEquals(2, g.members.Alice.hs)
    assertEquals(1, C.counts.selfIgnored)
    -- Malformed: counted, dropped, state untouched.
    local junk0 = C.counts.malformedIgnored
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "HS1 banana", "party", "Alice")
    assertEquals(junk0 + 1, C.counts.malformedIgnored)
    assertEquals(2, g.members.Alice.hs)
    -- A summon claim about a third player (sender != by) is ignored.
    local q0 = g:QueueCount()
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "SU1 Zelda Bob", "party", "Alice")
    assertEquals(q0, g:QueueCount())
    assertEquals(1, C.counts.foreignIgnored)
    -- The clean summon pair rides the model.
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "SU1 Alice Bob", "party", "Alice")
    assertEquals(1, g:QueueCount())
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "SE1 Alice Bob", "party", "Alice")
    assertEquals(0, g:QueueCount())
    -- Queries answered, rate-limited: HG1 from Alice pulls our HS1; the
    -- second HG1 inside the 5 s window answers nothing.
    local sent = {}
    C.readers.send = function(prefix, text, channel)
        sent[#sent + 1] = { prefix = prefix, text = text, ch = channel }
        return 0
    end
    C.readers.isRaid = function() return true end
    local box = { 100 }
    C.readers.now = function() return box[1] end
    local hs = Tools.Healthstone
    local savedPresent, savedCount = hs.present, hs.count
    hs.present, hs.count = true, 3
    C:OnAddonMessage("FXWK", "HG1", "Alice")
    assertEquals(1, #sent)
    assertEquals("FXWK", sent[1].prefix)
    assertEquals("HS1 3", sent[1].text)
    assertEquals("RAID", sent[1].ch)
    C:OnAddonMessage("FXWK", "HG1", "Alice")      -- inside the window
    assertEquals(1, #sent)
    box[1] = 106                                   -- the window has passed
    C:OnAddonMessage("FXWK", "HG1", "Alice")
    assertEquals(2, #sent)
    hs.present, hs.count = savedPresent, savedCount
    C:DisableEvents()
    C.readers = {}
end)

-- ============================================================ the gates ----

test("a restricted send is silently SKIPPED and COUNTED; solo too",
function()
    resetComms()
    local sent = {}
    C.readers.send = function(prefix, text) sent[#sent + 1] = text; return 0 end
    C.readers.isRaid = function() return true end
    -- FX.SecretState.chat = the C_RestrictedActions Chat=5 snapshot.
    local SS = FX.SecretState
    local savedChat, savedRefresh = SS and SS.chat, SS and SS.Refresh
    if SS then
        SS.Refresh = function() end
        SS.chat = true
    end
    local locked0 = C.counts.lockedSkipped
    assertEquals("locked", C:SendCmd("HS", 3))
    assertEquals(locked0 + 1, C.counts.lockedSkipped)
    assertEquals(0, C.counts.sent)
    assertEquals(0, #sent)
    if SS then SS.chat = nil end
    -- The InChatMessagingLockdown half.
    C.readers.inLockdown = function() return true end
    assertEquals("locked", C:SendCmd("HS", 3))
    C.readers.inLockdown = nil
    -- The AreOutgoingAddonChatMessagesRestricted half (the NeedRoll pair).
    C.readers.outgoingRestricted = function() return true end
    assertEquals("locked", C:SendCmd("HS", 3))
    C.readers.outgoingRestricted = nil
    -- An UNKNOWN lockdown state does not suppress (the consumer law).
    local sent0 = C.counts.sent
    C.readers.inLockdown = function() return nil end
    assertEquals("sent", C:SendCmd("HS", 4))
    assertEquals(sent0 + 1, C.counts.sent)
    C.readers.inLockdown = nil
    if SS then
        SS.chat = savedChat
        SS.Refresh = savedRefresh
    end
    -- Solo: the law, not the switch — counted as noGroup, nothing sent.
    C.readers.isRaid = function() return false end
    C.readers.groupCount = function() return 0 end
    local solo0 = C.counts.noGroupSkipped
    assertEquals("noGroup", C:SendCmd("HS", 3))
    assertEquals(solo0 + 1, C.counts.noGroupSkipped)
    -- A party routes PARTY, a raid routes RAID.
    C.readers.groupCount = function() return 3 end
    assertEquals("sent", C:SendCmd("HS", 3))
    assertEquals("PARTY", C:Channel())
    C.readers.isRaid = function() return true end
    assertEquals("RAID", C:Channel())
    -- The raising send is counted, never propagated.
    C.readers.send = function() error("chat raise") end
    local failed0 = C.counts.sendFailed
    assertEquals("raised", C:SendCmd("HS", 3))
    assertEquals(failed0 + 1, C.counts.sendFailed)
end)

test("the rate law: one query burst per window, announces only on change",
function()
    resetComms()
    local box = { 1000 }
    C.readers.now = function() return box[1] end
    local sent = {}
    C.readers.send = function(prefix, text) sent[#sent + 1] = text; return 0 end
    C.readers.isRaid = function() return true end
    C.readers.rosterScan = function()
        return { { name = "Alice", class = "WARLOCK" } }
    end
    local hs, sh = Tools.Healthstone, Tools.Shards
    local saved = { hs.present, hs.count, sh.count, sh.source }
    hs.present, hs.count = true, 2
    sh.count, sh.source = 4, "bag"
    C:OnRosterChanged()                     -- join burst: two queries,
    assertEquals(4, #sent)                   -- then the own-state pair
    assertEquals("HG1", sent[1]); assertEquals("SG1", sent[2])
    assertEquals("HS1 2", sent[3]); assertEquals("SH1 4", sent[4])
    box[1] = 1001                            -- one second later: the query
                                             -- window (5 s) and the announce
                                             -- window (2 s) both still shut
    C:OnRosterChanged()
    assertEquals(4, #sent)
    hs.present, hs.count = saved[1], saved[2]
    sh.count, sh.source = saved[3], saved[4]
    C.readers.rosterScan = nil
end)

-- ============================================================ the plate ----

test("the spy rows ride the Healthstone plate through the kick path",
function()
    UI:_InitViews()                     -- the ensureBuilt convention
    resetComms()
    local group = C.group
    group:SetRoster({
        { name = "Alice", class = "WARRIOR", present = true, alive = true },
        { name = "Bob", class = "WARRIOR", present = true, alive = true },
    })
    group:MarkAddon("Alice")
    group:SetCount("Alice", "hs", 2)
    local hs = HS.Tracker
    if not hs then
        HS:SetTracker(Tools.Healthstone)
        hs = HS.Tracker
    end
    local saved = { hs.present, hs.count, hs.cdStart, hs.cdDuration }
    hs.present, hs.count = false, 0          -- the OWN bags are empty
    HS:SetTracker(hs)
    HS:SetSpy(group)
    HS:Init()
    local savedUnknown = HS.state.showUnknown
    HS.state.showUnknown = true
    UI:Kick({ "Healthstone" })               -- the event path, no OnUpdate
    assertTrue(HS.anchor:IsShown(),
        "the roster is a claim even with empty own bags")
    assertEquals("Total", HS.nameFS:GetText())
    assertEquals("1", HS.timeFS:GetText())   -- stones over active (HS:199)
    assertTrue(HS._frac == 1)
    local e = HS.extraRows and HS.extraRows[1]
    assertNotNil(e, "the No-info bar is built")
    assertTrue(e.row:IsShown(), "unknown > 0 shows the bar")
    assertEquals("No info", e.nameFS:GetText())
    assertEquals("1", e.timeFS:GetText())
    assertEquals("x0", HS.infoFS:GetText())  -- Amount2 x<missing> (:165)
    -- The HealthstoneUnknown switch drops the bar live.
    HS:SetShowUnknown(false)
    UI:Kick({ "Healthstone" })
    assertTrue(not HS.extraRows[1].row:IsShown())
    HS:SetShowUnknown(true)
    -- Leaving the group: the roster clears, an empty roster is no claim,
    -- the plate retires (no own stones).
    group:Clear()
    UI:Kick({ "Healthstone" })
    assertTrue(not HS.anchor:IsShown())
    HS:SetShowUnknown(savedUnknown)
    HS:SetSpy(nil)
    resetComms()                     -- the singleton leaves clean state
    -- The Update above rode the icon through the HS1/HS2 art law; restore
    -- the vendored module art the suite's icon census expects.
    HS._iconArt = nil
    HS.icon:SetTexture(HS.skin.IconTexture)
    hs.present, hs.count = saved[1], saved[2]
    hs.cdStart, hs.cdDuration = saved[3], saved[4]
end)
