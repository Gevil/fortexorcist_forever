-- addon/Forte_Warlock/tests/test_warlock_comms_channel.lua
-- FX7b: the two party-comms halves that only bite on the REAL client, where
-- the `readers` seam is NIL and the module reads the client's own globals.
--
-- (1) THE CHANNEL READ. `Core/Comms.lua`'s `plainCall` is the boolean half of
-- the plain-read family — it answers `plain and true or false` — and it is
-- the right tool for the boolean predicates it gates (`IsInRaid`,
-- `InChatMessagingLockdown`, `AreOutgoingAddonChatMessagesRestricted`). It is
-- NOT the tool for `GetNumGroupMembers`, which answers a COUNT: 4 through
-- `plainCall` is `true`, `tonumber(true)` is nil, `(nil or 0) > 0` is false,
-- and `Channel()` says "no group". A real four-man party therefore routed
-- every line to `noGroup` — the comms ran dark on the launch client while the
-- whole suite, which drives the `groupCount` seam (a function answering a
-- plain number, the one shape the buggy line handled), stayed green. The
-- count needs the NUMERIC plain read (pcall, PlainOrNil, tonumber).
--
-- (2) THE OUTBOX TTL. `PumpOutbox` sends a locked-down room's head home with
-- its tries unspent (the client never saw it — the right law), and `Enqueue`
-- stamped `queuedAt = now` for the re-queue, so the line's age reset on every
-- pass. OUTBOX_TTL = 300 s is the ONLY bound on such a line (its retry budget
-- is deliberately left unspent), so a long instance lockdown kept every held
-- line alive forever. The re-queue must carry the line's ORIGINAL arrival
-- stamp.
--
-- Both tests therefore stub the REAL `_G.IsInRaid` / `_G.GetNumGroupMembers`
-- and leave the seam nil — the shape the shipped client presents, and the
-- only shape that can catch this class of bug. Every body runs under pcall
-- with the global/seam cleanups outside it: the suite shares this module and
-- these game globals, so a body that fails half-way must not hand a stubbed
-- `GetNumGroupMembers` to the next file.

local FX = ForteXorcist
local WK = FX.Warlock
local C = FX.Warlock.Comms

local saved = nil           -- the game globals borrowed, once per file

local function resetComms()
    C.readers = {}
    C._lastAt = {}
    C._lastSent = {}
    C._lastTarget = nil
    C.outbox = {}
    C._throttleStrikes = 0
    C._pausedUntil = nil
    C._pumpArmed = false
    C._stopped = nil
    C.prefixState = nil
    C.group = WK.NewGroup()
    for k in pairs(C.counts) do C.counts[k] = 0 end
end

local function useRealGroup(isRaid, members)
    if not saved then
        saved = {
            raid = _G.IsInRaid, members = _G.GetNumGroupMembers,
            unitName = _G.UnitName, unitClass = _G.UnitClass,
        }
    end
    _G.IsInRaid = function() return isRaid end
    _G.GetNumGroupMembers = function()
        return type(members) == "function" and members() or members
    end
end
local function restoreRealGroup()
    if saved then
        _G.IsInRaid = saved.raid
        _G.GetNumGroupMembers = saved.members
        _G.UnitName = saved.unitName
        _G.UnitClass = saved.unitClass
        saved = nil
    end
end

local function guarded(body)
    resetComms()
    local ok, err = pcall(body)
    restoreRealGroup()
    resetComms()
    if not ok then error(err, 0) end
end

-- ------------------------------------------------------- the channel read --

test("FX7b: a party of 4 from the REAL GetNumGroupMembers is a PARTY channel "
.. "(the boolean plainCall turned the count into `true` and the comms ran "
.. "solo on the client)", function()
    guarded(function()
        useRealGroup(false, 4)
        local sent = {}
        C.readers.send = function(prefix, text, channel)
            sent[#sent + 1] = { text = text, channel = channel }
            return 0
        end
        -- The seam is nil: this is the path the shipped client walks.
        assertEquals(nil, C.readers.groupCount, "no seam: the client's own read")
        assertEquals(nil, C.readers.isRaid)

        assertEquals("PARTY", C:Channel(),
            "four members is a party, not an absent group")

        -- And the send that rides it: the line leaves on PARTY, not into
        -- the noGroup bin.
        local solo0 = C.counts.noGroupSkipped
        assertEquals("sent", C:SendCmd("HS", 3))
        assertEquals(1, #sent, "the party member's count answer left the client")
        assertEquals("PARTY", sent[1].channel)
        assertEquals("HS1 3", sent[1].text)
        assertEquals(solo0, C.counts.noGroupSkipped,
            "a party is not counted as a solo skip")

        -- The zero half of the same read: an empty count is not a party.
        useRealGroup(false, 0)
        assertEquals(nil, C:Channel(), "a count of 0 is no channel")
        local solo1 = C.counts.noGroupSkipped
        assertEquals("noGroup", C:SendCmd("HS", 3))
        assertEquals(solo1 + 1, C.counts.noGroupSkipped)

        -- The raid half keeps riding its BOOLEAN helper (`IsInRaid` answers
        -- a bool — the helper is the right tool there).
        useRealGroup(true, 25)
        assertEquals("RAID", C:Channel())

        -- A count API that raises is no evidence of a group: the channel is
        -- nil, never a guess (the consumer law).
        useRealGroup(false, function() error("FXTEST-NO-GROUP-SURFACE", 0) end)
        assertEquals(nil, C:Channel(), "a read that raises names no group")
    end)
end)

test("FX7b: the roster scan reads the same count numerically through the "
.. "real globals (the scan is the read the channel line owed)", function()
    guarded(function()
        useRealGroup(false, 2)
        _G.UnitName = function(unit)
            if unit == "party1" then return "Alice" end
            if unit == "party2" then return "Bob" end
            return nil
        end
        _G.UnitClass = function(unit)
            if unit == "party1" then return "Warlock", "WARLOCK" end
            return "Warrior", "WARRIOR"
        end
        local rows = C:ScanRoster()
        assertNotNil(rows, "the scan walked the party tokens")
        assertEquals(2, #rows)
        assertEquals("Alice", rows[1].name)
        assertEquals("Bob", rows[2].name)
    end)
end)

-- ------------------------------------------------------------ the outbox TTL --

test("FX7b: a line the lockdown gate holds for longer than OUTBOX_TTL is "
.. "dropped and counted (the gate re-queue re-stamped queuedAt, so the line "
.. "aged forever)", function()
    guarded(function()
        local clock = { 20000 }
        local attempts, sent, scheduled = {}, {}, {}
        C.readers.now = function() return clock[1] end
        C.readers.isRaid = function() return true end
        C.readers.after = function(seconds, fn)
            scheduled[#scheduled + 1] = { delay = seconds, fn = fn }
        end
        -- The client's own lockdown verdict is how the line gets INTO the
        -- queue; the gate is the thing that then holds it.
        C.readers.send = function(prefix, text)
            attempts[#attempts + 1] = text
            return 11                              -- AddOnMessageLockdown
        end
        local queued0 = C.counts.queued
        assertEquals("lockdown", C:Send("HS1 7", "RAID"))
        assertEquals(1, #C.outbox)
        assertEquals(1, #attempts)
        local born = C.outbox[1].queuedAt
        assertEquals(clock[1], born, "a fresh line stamps its arrival")
        assertEquals(queued0 + 1, C.counts.queued)

        -- The room goes shut at the client's own gate: every pump pass now
        -- meets `chatLocked()` and the head rides home with its tries
        -- UNSPENT. Walk the clock past the TTL in bounded steps — the pump is
        -- the client's timer here (the headless sim fires no callback).
        C.readers.inLockdown = function() return true end
        C.readers.send = function(prefix, text)
            attempts[#attempts + 1] = text         -- must never be reached
            return 0
        end
        local seen = {}
        local steps, limit = 0, math.ceil(C.OUTBOX_TTL / 5) + 20
        while #C.outbox > 0 and steps < limit do
            steps = steps + 1
            clock[1] = clock[1] + 5
            local word = C:PumpOutbox()
            seen[word] = (seen[word] or 0) + 1
        end

        assertEquals(0, #C.outbox,
            "the TTL retires a line the lockdown outlasted; it rode "
            .. steps .. " gate passes")
        assertTrue((seen.stale or 0) >= 1,
            "the pump names the drop the TTL owed: stale")
        assertTrue(C.counts.outboxDropped >= 1, "the TTL drop is counted")
        assertEquals(0, C.counts.sent, "the room never received the stale line")
        assertEquals(1, #attempts,
            "the gate stopped every pass before the client: one call total")
        assertTrue((seen.locked or 0) >= 1,
            "the passes before the age-out are the counted gate skips")
        assertEquals(C.OUTBOX_TTL + 5, clock[1] - born,
            "the line died at its age, not at a lucky step count")

        -- The optional carry, pinned at the seam itself: a re-queue that
        -- names a `queuedAt` keeps that stamp; a fresh line stamps the clock.
        C.readers.inLockdown = function() return false end
        C.readers.send = function() return 0 end
        C.outbox = {}
        C:Enqueue("HS1 9", "RAID", "gate", "front", 0, 20000)
        assertEquals(1, #C.outbox)
        assertEquals(20000, C.outbox[1].queuedAt,
            "the carried stamp is the line's arrival, not the re-queue's minute")
        assertEquals(0, C.outbox[1].tries, "the gate leaves the tries unspent")
        clock[1] = 20000 + C.OUTBOX_TTL + 1
        assertEquals("stale", C:PumpOutbox(), "and the TTL reads it")
    end)
end)
