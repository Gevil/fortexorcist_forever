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
    C.outbox = {}                 -- the I3b outbox leaves no line behind
    C._throttleStrikes = 0
    C._pausedUntil = nil
    C._pumpArmed = false
    C._stopped = nil
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
    local alice = FX.Identity.Canonical("Alice")
    assertEquals(2, g.members[alice].hs)
    assertEquals(true, g.members[alice].addon)
    -- A foreign prefix is not even counted as ours.
    assertEquals("foreignPrefix",
        C:OnAddonMessage("DBM", "HS1 9", "Alice"))
    assertEquals(2, g.members[alice].hs)
    -- The self-echo law (CA-24): our own line never re-enters the model.
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "HS1 9", "party", "Me")
    assertEquals(2, g.members[alice].hs)
    assertEquals(1, C.counts.selfIgnored)
    -- Malformed: counted, dropped, state untouched.
    local junk0 = C.counts.malformedIgnored
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "HS1 banana", "party", "Alice")
    assertEquals(junk0 + 1, C.counts.malformedIgnored)
    assertEquals(2, g.members[alice].hs)
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

-- ======================================================== identity spellings --
-- The spelling law of docs/research/upstream-api-2026-11-03.md §2 (slice
-- I2a): the CHAT_MSG_ADDON sender, the roster-scan UnitName and the wire
-- carry the SAME player in DIFFERENT spellings. The self-echo, the summon
-- claim and the roster merge ride FX.Identity's canonical form, so a
-- spelling split is no longer a reason to treat a peer as someone else.

test("a comms self-echo survives every spelling of my own two-part name",
function()
    resetComms()
    C.readers.selfName = function() return "Aria Dawnsong" end
    C:EnableEvents()
    local frame = C._eventFrame
    local handler = frame:GetScript("OnEvent")
    local s0 = C.counts.selfIgnored
    -- Sender spellings: the event layer's spaced one, the wire's joined
    -- one, the display-side short one. All three are ME.
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "HS1 9", "party", "aria dawnsong")
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "HS1 9", "party", "AriaDawnsong")
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "HS1 9", "party",
        "Aria Dawnsong-Wildhammer")
    assertEquals(s0 + 3, C.counts.selfIgnored,
        "CA-24 on every spelling: my line never re-enters the model")
    local peer = FX.Identity.Canonical("Aria Two")
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "HS1 9", "party", "Aria Two")
    assertEquals(s0 + 3, C.counts.selfIgnored, "a sibling is not me")
    assertEquals(9, (C.group:Member("Aria Two")).hs, "and rides the model")
    assertNotNil(peer)
    -- The own summon pair: the two-part name rides the wire in the
    -- identity layer's joined-parts form (the grammar is space-separated,
    -- the raw spelling would be refused by the encoder).
    local sent = {}
    C.readers.send = function(prefix, text)
        sent[#sent + 1] = { text = text }; return 0
    end
    C.readers.isRaid = function() return true end
    assertEquals("sent", C:OnSelfSummon("start", "Gvil"))
    assertEquals("SU1 AriaDawnsong Gvil", sent[1].text)
    C:DisableEvents()
    C.readers = {}
end)

test("the roster merge folds a sender spelling into the scan's member row",
function()
    resetComms()
    C.readers.selfName = function() return "Me" end
    local g = C.group
    -- The scan spells the name the UnitName way, the wire the %S+ way.
    g:SetRoster({
        { name = "Aria Dawnsong", class = "WARLOCK", present = true,
          alive = true },
    })
    local canon = FX.Identity.Canonical("Aria Dawnsong")
    assertEquals(1, g:ActiveCount())
    C:EnableEvents()
    local frame = C._eventFrame
    local handler = frame:GetScript("OnEvent")
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "SH1 12", "party", "AriaDawnsong")
    C:DisableEvents()
    assertEquals(1, g:ActiveCount(), "one member, not a twin")
    assertEquals(12, g.members[canon].shards, "the count landed on HER row")
    assertEquals("Aria Dawnsong", g.members[canon].name,
        "the row keeps the spelling the game scanned")
    -- The claim law with a spelling split: SU1 whose <by> is the sender's
    -- wire spelling, sender the spaced one -> the claim is about the
    -- sender, it rides the model.
    handler(frame, "CHAT_MSG_ADDON", "FXWK", "SU1 AriaDawnsong Gvil",
        "party", "Aria Dawnsong")
    assertEquals(1, g:QueueCount())
    assertEquals("Aria Dawnsong", g:Queue(10)[1].warlock,
        "the queue row rides the sender's own spelling")
    -- The next scan keeps her: a spelling split must not make the
    -- DeleteOld sweep delete her comms state.
    g:SetRoster({
        { name = "Aria Dawnsong", class = "WARLOCK", present = true },
    })
    assertEquals(1, g:ActiveCount())
    assertEquals(12, g.members[canon].shards, "her counts rode the scan")
    C.readers = {}
end)

test("a send over the client's 255-byte cap is dropped and counted, never sent",
function()
    resetComms()
    local sent = {}
    C.readers.send = function(prefix, text) sent[#sent + 1] = text; return 0 end
    C.readers.isRaid = function() return true end
    local t0 = C.counts.tooLongSkipped
    assertEquals("tooLong", C:Send(string.rep("x", 300), "RAID"))
    assertEquals(t0 + 1, C.counts.tooLongSkipped)
    assertEquals(0, #sent, "the client would have eaten it; we drop it counted")
    assertEquals("sent", C:Send(string.rep("x", C.MAX_WIRE_BYTES), "RAID"),
        "the cap itself rides")
    assertEquals(1, #sent)
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
    local rate0 = C.counts.rateSkipped
    C:OnRosterChanged()
    assertEquals(4, #sent)
    -- The rate law is the header's skipped send, and a skipped send is
    -- COUNTED: the query gate refused one burst and the announce gates
    -- refused the two state lines, so the trio rides `rate %d` on
    -- `/fx status`. The counter used to sit at 0 for a session of pure
    -- rate-shaving (docs/reviews/code-review-7.md F7).
    assertEquals(rate0 + 3, C.counts.rateSkipped,
        "the ate-list of the rate law is reported, not silent")
    -- The gate is the counter's home, so every rate-limited site (the query
    -- burst, the answer leg of an inbound query, the state announces) rides
    -- it: a NO counts, an opening costs nothing.
    local gate0 = C.counts.rateSkipped
    assertFalse(C:RateGate("query", 5), "inside the window the gate says no")
    assertEquals(gate0 + 1, C.counts.rateSkipped, "and the no is counted")
    box[1] = 20000
    assertTrue(C:RateGate("query", 5), "past the window the gate opens")
    assertEquals(gate0 + 1, C.counts.rateSkipped, "the opening costs no count")
    hs.present, hs.count = saved[1], saved[2]
    sh.count, sh.source = saved[3], saved[4]
    C.readers.rosterScan = nil
end)

-- ============================================ the verdict + the outbox (I3b) --
-- docs/research/upstream-addons-2026-11-03.md §4 + ranked 3: a send ANSWERS a
-- `SendAddonMessageResult` code (the pinned enumeration
-- @ChatConstantsDocumentation.lua:146, the 0..12 set named in Core/Comms.lua's
-- VERDICT LAW), and the codes fall in three classes — throttle (3
-- AddonMessageThrottle, 8 ChannelThrottle) re-queues behind a back-off, 11
-- AddOnMessageLockdown re-queues at the head, anything else drops and counts.
-- The outbox is bounded four ways (the cap, the retry budget, the TTL, the
-- group-left clear) and its pump is driven BY HAND through the module's own
-- PumpOutbox on the clock seam: the headless sim fires no timer callback, so
-- a test that waited on C_Timer would assert nothing. `readers.after` is the
-- pump's seam — capturing the armed steps is how these tests read the
-- "at most one closure in flight" law. The 255-byte gate of I2a runs ahead of
-- every send, queued lines included.

local function verdictHarness(script)
    resetComms()
    local clock = { 10000 }
    local attempts = {}      -- every call the seam saw, with its code
    local sent = {}          -- ONLY the lines the client ACCEPTED (code 0)
    local scheduled = {}     -- the pump closures the chain armed
    local codes = {}
    for i = 1, #script do codes[i] = script[i] end
    C.readers.now = function() return clock[1] end
    C.readers.isRaid = function() return true end
    C.readers.after = function(seconds, fn)
        scheduled[#scheduled + 1] = { delay = seconds, fn = fn }
    end
    C.readers.send = function(prefix, text)
        local code = codes[#attempts + 1]
        if code == nil then code = codes[#codes] end
        attempts[#attempts + 1] = { text = text, code = code }
        if code == 0 then sent[#sent + 1] = text end
        return code
    end
    return clock, sent, attempts, scheduled
end
local function attemptsOf(attempts)
    local out = {}
    for i = 1, #attempts do out[i] = attempts[i].text end
    return out
end

test("a throttled verdict (3 AddonMessageThrottle, 8 ChannelThrottle) "
.. "re-queues behind a back-off and the retry goes out exactly once",
function()
    local clock, sent, attempts, scheduled
        = verdictHarness({ 3, 0, 3, 3, 3, 0 })
    local q0 = C.counts.queued
    assertEquals("throttled", C:SendCmd("HS", 7),
        "the code is a class, not a failure")
    assertEquals(0, C.counts.sent, "the client took nothing")
    assertEquals(0, #sent)
    assertEquals(1, #attempts, "one call")
    assertEquals(1, #C.outbox, "the line waits in the outbox")
    assertEquals("HS1 7", C.outbox[1].text)
    assertEquals(q0 + 1, C.counts.queued)
    assertEquals(0, C.counts.sendFailed,
        "the pre-I3b fold of every code into sendFailed is gone")
    assertEquals(1, C.counts.throttled, "the class has its own counter")
    assertEquals(1, #scheduled, "one pump closure armed by the enqueue")
    -- The back-off: a pass before the line is due sends nothing.
    assertEquals("waiting", C:PumpOutbox())
    assertEquals(1, #attempts, "a pass before the back-off sends nothing")
    assertEquals(1, #C.outbox)
    clock[1] = clock[1] + C.BACKOFF_BASE
    assertEquals("sent", C:PumpOutbox())
    assertEquals(2, #attempts)
    assertEquals(1, #sent, "the room received the line exactly once")
    assertEquals("HS1 7", attemptsOf(attempts)[2], "the same line retried")
    assertEquals(0, #C.outbox, "and the queue drains")
    assertEquals("empty", C:PumpOutbox())
    -- 8 ChannelThrottle is the same class (TrueshotLodge src/share.lua:56's
    -- `THROTTLED = {[3]=true,[8]=true}` set).
    local q1 = C.counts.queued
    assertEquals("throttled", C:Send("SH1 4", "RAID"))    -- strike one
    assertEquals(1, #C.outbox)
    assertEquals(q1 + 1, C.counts.queued)
    assertEquals(2, C.counts.throttled)
    -- The strikes: the THIRD consecutive throttled answer keeps the WHOLE
    -- outbox quiet for THROTTLE_PAUSE (NeedRoll Drops.lua:628-630's law);
    -- two answers on their own cost nothing but the back-off.
    local p0 = C.counts.throttlePaused
    clock[1] = clock[1] + C.BACKOFF_MAX
    assertEquals("throttled", C:PumpOutbox(), "strike two")
    assertEquals(p0, C.counts.throttlePaused, "two strikes do not pause")
    clock[1] = clock[1] + C.BACKOFF_MAX
    assertEquals("throttled", C:PumpOutbox(), "strike three")
    assertEquals(p0 + 1, C.counts.throttlePaused)
    assertEquals("paused", C:PumpOutbox())
    assertEquals(5, #attempts, "a paused outbox sends nothing")
    assertEquals(1, #sent, "and the accepted half stays where it was")
    clock[1] = clock[1] + C.THROTTLE_PAUSE + 1
    assertEquals("sent", C:PumpOutbox(), "the pause is bounded, never a stop")
    assertEquals(2, #sent)
    assertEquals("SH1 4", sent[2])
end)

test("the lockdown verdict (11 AddOnMessageLockdown) holds at the head and "
.. "flushes in the order it arrived", function()
    local clock, sent, attempts, scheduled = verdictHarness({ 11, 11, 0, 0 })
    local function runPumpStep()
        -- The event path only REQUESTS a step (the chain has no cancel); the
        -- suite runs the armed closure, which is what the client's timer does.
        local step = scheduled[#scheduled]
        assertTrue(step ~= nil, "a pump step is armed")
        step.fn()
    end
    assertEquals("lockdown", C:SendCmd("HG"))
    assertEquals("lockdown", C:SendCmd("SG"))
    assertEquals(0, C.counts.sent)
    assertEquals(2, #attempts, "two calls, both answered the lockdown code")
    assertEquals(0, C.counts.sendFailed, "a lockdown is not a failure")
    assertEquals(2, C.counts.lockdownRefused)
    assertEquals(2, #C.outbox)
    assertEquals("HG1", C.outbox[1].text, "the head-run keeps the arrival order")
    assertEquals("SG1", C.outbox[2].text)
    -- The room goes shut under the queue: the pump meets the gate and the
    -- head goes back at the head with its tries UNSPENT (the client never
    -- saw it), so a long lockdown costs the lines nothing.
    C.readers.inLockdown = function() return true end
    assertEquals("locked", C:PumpOutbox())
    assertEquals(2, #attempts, "a locked pass calls the client zero times")
    assertEquals(0, #sent)
    assertEquals(2, #C.outbox, "held, not lost")
    assertEquals("HG1", C.outbox[1].text)
    assertEquals("SG1", C.outbox[2].text)
    local tries = C.outbox[1].tries
    assertEquals("locked", C:PumpOutbox())
    assertEquals(tries, C.outbox[1].tries, "the gate spends no retry")
    -- The lift: ADDON_RESTRICTION_STATE_CHANGED (RestrictedActionsDocu
    -- mentation.lua:96) pumps the head through the REAL frame script.
    C.readers.inLockdown = function() return false end
    C:EnableEvents()
    local f = C._eventFrame
    local handler = f:GetScript("OnEvent")
    assertEquals("function", type(handler))
    handler(f, "ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    runPumpStep()
    assertEquals(1, #sent)
    assertEquals("HG1", sent[1])
    assertEquals(1, #C.outbox)
    handler(f, "ADDON_RESTRICTION_STATE_CHANGED", 5, 0)
    runPumpStep()
    assertEquals(2, #sent)
    assertEquals("SG1", sent[2], "the pair left in the order it arrived")
    assertEquals(0, #C.outbox)
    C:DisableEvents()
end)

test("an out-of-class verdict drops and counts; a shape fact drops; no "
.. "answer at all is not a verdict", function()
    local clock, sent, attempts = verdictHarness({ 9 })        -- 9 GeneralError
    local failed0 = C.counts.sendFailed
    assertEquals("refused", C:SendCmd("HS", 2))
    assertEquals(failed0 + 1, C.counts.sendFailed)
    assertEquals(1, #attempts, "the client saw the attempt")
    assertEquals(0, #sent, "and accepted nothing")
    assertEquals(0, #C.outbox,
        "a shape/audience fact: a retry would send the same bad line")
    -- 5 NotInGroup, 12 TargetOffline, 1 InvalidPrefix: the drop class.
    for _, code in ipairs({ 1, 2, 4, 5, 6, 7, 10, 12 }) do
        C.readers.send = function() return code end
        assertEquals("refused", C:Send("HS1 3", "RAID"), "code " .. code)
        assertEquals(0, #C.outbox, "code " .. code .. " queues nothing")
    end
    -- An out-of-pin code (99): the class falls out to the drop side, counted.
    C.readers.send = function() return 99 end
    assertEquals("refused", C:Send("HS1 3", "RAID"))
    assertEquals(0, #C.outbox)
    -- A send that answers NOTHING (the sim's own SendChatMessage shape, and
    -- the declared-returnless chat half) is not a verdict: the pre-I3b
    -- reading stands — the send happened.
    C.readers.send = function() return nil end
    assertEquals("sent", C:Send("HS1 4", "RAID"))
    -- A secret verdict passes PlainOrNil to nil, so it is the same non-answer.
    C.readers.send = function() return nil end
    assertEquals("sent", C:Send("HS1 5", "RAID"))
end)

test("the outbox is bounded: over the cap the OLDEST line is the one that goes",
function()
    local clock, sent = verdictHarness({ 11 })        -- every answer: lockdown
    local n = C.OUTBOX_MAX + 5
    for i = 1, n do
        assertEquals("lockdown", C:Send("HS1 " .. i, "RAID"))
    end
    assertEquals(C.OUTBOX_MAX, #C.outbox,
        "the cap is the ceiling: the queue never grows past it")
    assertEquals(5, C.counts.outboxDropped, "five over-cap drops")
    assertEquals("HS1 6", C.outbox[1].text, "the five OLDEST are the ones that went")
    assertEquals("HS1 " .. n, C.outbox[#C.outbox].text,
        "the freshest restatement is the one that survives")
    -- The drop law of a STATE wire: the newest count is the truth.
    assertEquals(C.OUTBOX_MAX, C.counts.queued - C.counts.outboxDropped)
    assertEquals(0, C.counts.sent)
end)

test("a queued line that spends its retry budget is dropped and counted",
function()
    local clock, sent, attempts = verdictHarness({ 3 })         -- every answer: throttled
    assertEquals("throttled", C:SendCmd("HS", 9))
    local pumps = 0
    while #C.outbox > 0 and pumps < 40 do
        pumps = pumps + 1
        clock[1] = clock[1] + C.BACKOFF_MAX     -- never wait on a back-off
        if C:PumpOutbox() == "paused" then
            -- The strike pause is bounded too: outlast it, the line goes back.
            clock[1] = clock[1] + C.THROTTLE_PAUSE + 1
        end
    end
    assertEquals(0, #C.outbox, "the budget bounds the line's life")
    assertEquals(1, C.counts.outboxDropped, "the spent line is the counted drop")
    assertEquals(0, C.counts.sent)
    assertEquals(C.counts.throttled, #attempts, "every answer was a throttle")
    assertTrue(pumps <= C.RETRY_MAX + 4,
        "the budget bounds the attempts: " .. pumps
        .. " pumps against a " .. C.RETRY_MAX .. "-send budget")
    assertEquals("empty", C:PumpOutbox())
end)

test("a long lockdown cannot grow the outbox unbounded, and the group-left "
.. "law clears it", function()
    local clock, sent = verdictHarness({ 11 })
    local peak = 0
    for i = 1, 120 do
        C:Send("SH1 " .. (i % 50), "RAID")
        peak = math.max(peak, #C.outbox)
    end
    assertTrue(peak <= C.OUTBOX_MAX,
        "the cap is the ceiling across a whole lockdown, not the average")
    assertEquals(C.OUTBOX_MAX, #C.outbox)
    assertTrue(C.counts.outboxDropped > 0, "and every over-cap drop is counted")
    local dropped0 = C.counts.outboxDropped
    C:OnGroupLeft()
    assertEquals(0, #C.outbox,
        "the queued lines had THAT room as their audience")
    assertTrue(C.counts.outboxDropped > dropped0, "the clear is counted")
    assertEquals("empty", C:PumpOutbox())
end)

test("the pump is a self-terminating chain: one closure in flight, and none "
.. "for an empty outbox", function()
    local clock, sent, attempts, scheduled = verdictHarness({ 3 })
    C:Send("HS1 1", "RAID")
    assertEquals(1, #scheduled, "the enqueue arms exactly one step")
    for _ = 1, 5 do C:_SchedulePump(C.PUMP_STEP) end
    assertEquals(1, #scheduled,
        "while a step is in flight the arm is idempotent (the _pumpArmed flag)")
    -- Walk the chain the client would walk: every executed step arms at most
    -- the NEXT one, and the chain STOPS the pass the outbox drains (the
    -- Forte_Messages/Module.lua:249-267 law — no timer runs on an idle session).
    local steps, guard = 0, 0
    while scheduled[steps + 1] and guard < 40 do
        guard = guard + 1
        local step = scheduled[steps + 1]
        steps = steps + 1
        clock[1] = clock[1] + C.BACKOFF_MAX      -- never wait on a back-off
        step.fn()
    end
    assertEquals(0, #C.outbox, "the retry budget drained the queue")
    assertEquals(steps, #scheduled, "no closure is armed once the queue is empty")
    assertEquals(0, C.counts.sent, "every answer was a throttle")
    assertTrue(C.counts.outboxDropped >= 1, "the spent line is counted")
    -- The disable half: with the events stopped the chain stops too.
    C:Send("HS1 2", "RAID")
    assertTrue(#C.outbox > 0)
    local armed = #scheduled
    C:DisableEvents()
    assertEquals("stopped", C:PumpOutbox())
    assertEquals(armed, #scheduled, "a stopped pump arms nothing")
    assertEquals(1, #C.outbox, "the line keeps its place for the next enable")
    C:EnableEvents()
    C:ClearOutbox()
    C:DisableEvents()
end)

test("the 255-byte gate runs ahead of the outbox too", function()
    local clock, sent = verdictHarness({ 3, 0 })
    local over = string.rep("x", C.MAX_WIRE_BYTES + 1)
    local long0 = C.counts.tooLongSkipped
    assertEquals("tooLong", C:Send(over, "RAID"))
    assertEquals(long0 + 1, C.counts.tooLongSkipped)
    assertEquals(0, #C.outbox, "a line the client would eat never enters the queue")
    assertEquals("throttled", C:Send(string.rep("y", C.MAX_WIRE_BYTES), "RAID"))
    assertEquals(1, #C.outbox, "the cap itself rides, queued like any line")
    clock[1] = clock[1] + C.BACKOFF_BASE
    assertEquals("sent", C:PumpOutbox())
    assertEquals(1, #sent)
    assertEquals(C.MAX_WIRE_BYTES, #sent[1], "the full-length line arrived")
end)

test("prefixState names all four RegisterAddonMessagePrefixResult codes "
.. "(0 ok, 1 duplicate, 2 invalid, 3 toomany)", function()
    resetComms()
    local cases = {
        { 0, "ok" }, { 1, "duplicate" }, { 2, "invalid" }, { 3, "toomany" },
        { 7, "refused:7" },
    }
    for _, c in ipairs(cases) do
        C.prefixState = nil
        C.readers = { register = function() return c[1] end }
        assertEquals(c[2], C:RegisterPrefix(), "code " .. tostring(c[1]))
        assertContains(C:StatusLine(), c[2],
            "the /fx status label names it (the launch-day evidence)")
    end
    C.prefixState = nil
    C.readers = { register = function() return nil end }
    assertEquals("okUnlabelled", C:RegisterPrefix())
    C.prefixState = nil
    C.readers = { register = function() error("FXTEST-NO-PREFIX", 0) end }
    assertEquals("raised", C:RegisterPrefix())
    C.readers = {}
    C.prefixState = nil
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

-- ==================================================== shard spy rows (F-A) --
-- The remaining half of docs/warlock-tools.md "Open": the plate half of the
-- Shard Spy. The stubbed CHAT_MSG_ADDON rides the comms frame's OWN OnEvent
-- script with the catalog payload order (prefix, text, channel, sender, ...)
-- of ChatInfoDocumentation.lua:800 — the sender is the 4th — and the plate
-- renders through the comms' own KickViews, so the test drives the same
-- path the live client's chat line does. No Update call in this test.

test("the Shard Spy rows ride the Shards plate through the comms frame",
function()
    local Shards = FX.Warlock.Shards
    UI:_InitViews()                     -- the ensureBuilt convention
    resetComms()
    C.readers.selfName = function() return "Me" end
    local group = C.group
    group:SetRoster({
        { name = "Alice", class = "WARLOCK", present = true, alive = true },
        { name = "Cara", class = "WARLOCK", present = true, alive = true },
        { name = "Bob", class = "WARRIOR", present = true, alive = true },
    })
    -- NO own read: the roster alone has to be the plate's claim.
    local savedCounter = Shards.Tracker
    Shards:SetTracker(WK.NewShardCounter({
        countReader = function() return nil end,
        powerReader = function() return nil end,
    }))
    Shards:SetSpy(group)
    Shards:RenderIdle()
    assertFalse(Shards.anchor:IsShown(), "idle before the first word")
    C:EnableEvents()
    local f = C._eventFrame
    local handler = f:GetScript("OnEvent")
    assertEquals("function", type(handler))
    handler(f, "CHAT_MSG_ADDON", "FXWK", "SH1 12", "party", "Alice")
    assertTrue(Shards.anchor:IsShown(),
        "a warlock reporting shards is a claim, through the real frame")
    -- No own read is printed as unread, never guessed (the `/fx status` ?).
    assertEquals("x?", Shards.amountFS:GetText())
    -- Row 0 is the spy's TOTAL row (the Healthstone Spy's Total bar,
    -- Forte_Healthstone.lua:197-199): the raid's shards.
    assertTrue(Shards.row:IsShown())
    assertEquals("Total", Shards.nameFS:GetText())
    assertEquals("12", Shards.timeFS:GetText())
    -- The rows: one per known warlock, sorted by name (Group:ShardRows).
    local e1 = Shards.extraRows and Shards.extraRows[1]
    assertNotNil(e1, "the first row is built")
    assertTrue(e1.row:IsShown())
    assertEquals("Alice", e1.nameFS:GetText())
    assertEquals("12", e1.timeFS:GetText())
    assertTrue(e1.nameFS:IsShown(), "the row's name is on screen")
    assertTrue(e1.timeFS:IsShown(), "and its count")
    -- Cara has answered nothing: her row carries the marker and an empty
    -- bar, and the right Info slot carries the badge (the Amount2 law,
    -- Forte_Healthstone.lua:165: x<the ones that report in unanswered>).
    local e2 = Shards.extraRows[2]
    assertTrue(e2.row:IsShown())
    assertEquals("Cara", e2.nameFS:GetText())
    assertEquals("?", e2.timeFS:GetText())
    assertEquals("x1", Shards.infoFS:GetText())
    assertTrue(e2.fill:GetWidth() == 0, "an unread count draws no bar")
    -- The second answer: the badge clears, the total sums, and the bars
    -- scale to the raid's own maximum (HS_DrawHealthstone's Bar:SetValue,
    -- Forte_Healthstone.lua:148).
    handler(f, "CHAT_MSG_ADDON", "FXWK", "SH1 30", "party", "Cara")
    assertEquals("42", Shards.timeFS:GetText())
    assertEquals("x0", Shards.infoFS:GetText())
    assertEquals("30", Shards.extraRows[2].timeFS:GetText())
    assertTrue(Shards.extraRows[2].fill:GetWidth()
        > Shards.extraRows[1].fill:GetWidth(),
        "the fuller warlock draws the longer bar")
    -- A non-warlock's line counts in the roster, never as a row: the
    -- Shard Spy's row set is the roster's WARLOCK column.
    handler(f, "CHAT_MSG_ADDON", "FXWK", "SH1 9", "party", "Bob")
    assertEquals(2, #(Shards.Spy:ShardRows(Shards.MAX_ROWS)))
    assertEquals("42", Shards.timeFS:GetText())
    -- Leaving the group: the model clears, an empty roster is NO claim, the
    -- plate retires (a solo player's plate is the pre-H6 shape).
    handler(f, "GROUP_LEFT")
    assertTrue(not Shards.anchor:IsShown(), "the roster left with the group")
    assertTrue(not Shards.extraRows[1].row:IsShown(), "and the rows with it")
    Shards:RenderIdle()
    Shards:SetSpy(nil)
    Shards:SetTracker(savedCounter)
    -- The comms kicks rode the Healthstone plate through its HS1/HS2/HS3
    -- art law; restore the vendored module art the suite's icon census
    -- expects (the convention of the spy-rows test above).
    HS:RenderIdle()
    HS._iconArt = nil
    HS.icon:SetTexture(HS.skin.IconTexture)
    C:DisableEvents()
    C.readers = {}
    resetComms()                        -- the singleton leaves clean state
end)

-- =================================================== summon queue rows (F-A) --
-- SU-03/04, the other half of the same "Open" list: the queue rows on the
-- Summon plate, same driven path. The row layout is the original's
-- SU_DrawSummon (the target as the row's name, Forte_Summon.lua:152-160;
-- the `<warlock>` priority label, :322-340) and the plate's count slot is
-- `x<the rituals in flight>` (:165).

test("the summon queue rows ride the Summon plate through the comms frame",
function()
    local Summon = FX.Warlock.Summon
    UI:_InitViews()
    resetComms()
    C.readers.selfName = function() return "Me" end
    local group = C.group
    group:SetRoster({
        { name = "Alice", class = "WARLOCK", present = true, alive = true },
        { name = "Cara", class = "WARLOCK", present = true, alive = true },
    })
    local savedTracker = Summon.Tracker
    local box = { 30000 }
    Summon:SetTracker(WK.NewSummonTracker({
        now = function() return box[1] end, channelSeconds = 5,
    }))
    Summon:SetSpy(group)
    Summon:RenderIdle()
    assertFalse(Summon.anchor:IsShown(),
        "no channel and no queue is no plate (SU-09)")
    C:EnableEvents()
    local f = C._eventFrame
    local handler = f:GetScript("OnEvent")
    assertEquals("function", type(handler))
    handler(f, "CHAT_MSG_ADDON", "FXWK", "SU1 Alice Bob", "party", "Alice")
    assertTrue(Summon.anchor:IsShown(),
        "the raid's ritual is a claim, through the real frame")
    assertFalse(Summon.row:IsShown(),
        "no own channel: my channeling row stays off")
    assertEquals("x1", Summon.amountFS:GetText(),
        "the rituals in flight (:165)")
    local e = Summon.extraRows and Summon.extraRows[1]
    assertNotNil(e, "the queue row is built")
    assertTrue(e.row:IsShown())
    assertEquals("Bob", e.nameFS:GetText())        -- the target, :152-160
    assertEquals("<Alice>", e.timeFS:GetText())    -- the warlock, :322-340
    assertTrue(e.nameFS:IsShown() and e.timeFS:IsShown())
    assertTrue(e.fill:GetWidth() == 0,
        "the wire says a ritual runs, never how far (SU-02) — no bar")
    assertFalse(Summon:Update(box[1]),
        "a queue row is no countdown: the plate asks for no tick")
    -- A second ritual stacks the run (the original's bar run,
    -- Forte_Summon.lua:296-301).
    handler(f, "CHAT_MSG_ADDON", "FXWK", "SU1 Cara Cara", "party", "Cara")
    assertEquals("x2", Summon.amountFS:GetText())
    assertEquals("Cara", Summon.extraRows[2].nameFS:GetText())
    assertEquals("<Cara>", Summon.extraRows[2].timeFS:GetText())
    -- My OWN ritual joins the plate: my channel keeps the first row (the
    -- plate's second line), the clocks come back, and the count counts it.
    box[1] = 30001
    Summon.Tracker:OnCastSent("Ritual of Summoning", "Zed")
    assertTrue(Summon:Update(box[1]), "my channel asks for the 10 Hz pass")
    assertTrue(Summon.row:IsShown())
    assertEquals("Zed", Summon.nameFS:GetText())
    assertEquals("0:05", Summon.timeFS:GetText())
    assertEquals("0:05", Summon.infoFS:GetText())
    assertEquals("x3", Summon.amountFS:GetText())
    -- The ends: my channel self-retires (SU-09, its clocks with it), the
    -- SE1 pair clears the claims, and an empty queue is no plate.
    box[1] = 30006
    Summon.Tracker:End("Ritual of Summoning", "succeeded")
    handler(f, "CHAT_MSG_ADDON", "FXWK", "SE1 Alice Bob", "party", "Alice")
    assertEquals("x1", Summon.amountFS:GetText())
    assertEquals("", Summon.infoFS:GetText(), "no channel, no clock")
    handler(f, "CHAT_MSG_ADDON", "FXWK", "SE1 Cara Cara", "party", "Cara")
    assertFalse(Summon.anchor:IsShown(), "the queue emptied, the plate goes")
    assertTrue(not Summon.extraRows[1].row:IsShown())
    handler(f, "GROUP_LEFT")
    assertFalse(Summon.anchor:IsShown())
    Summon:RenderIdle()
    Summon:SetSpy(nil)
    Summon:SetTracker(savedTracker)
    -- The comms kicks rode the Healthstone plate through its HS1/HS2/HS3
    -- art law; restore the vendored module art the suite's icon census
    -- expects (the convention of the spy-rows test above).
    HS:RenderIdle()
    HS._iconArt = nil
    HS.icon:SetTexture(HS.skin.IconTexture)
    C:DisableEvents()
    C.readers = {}
    resetComms()                        -- the singleton leaves clean state
end)
