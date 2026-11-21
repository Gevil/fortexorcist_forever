-- addon/Forte_Cooldown/tests/test_tiers_wand.lua
-- GitHub issue #2 ("Wand GCD triggers spell cooldown timers", Priest, in
-- combat): the boolean tier (Engine:OnReadActive) used to create a FULL-length
-- "edge" entry the first time a tracked spell read `isActive = true,
-- isOnGCD = false` with no entry. If the client reports a wand shot's
-- recovery that way for every spell, every shot put every tracked spell on
-- the bar. This file pins the three guards (Core/Engine.lua header, "Edge law"
-- and "Lockout law") and the counters /fx status prints:
--   * plain numbers are authoritative: a PLAIN numeric read never lets the
--     booleans create an edge (the OnRead verdict rides the 5th argument),
--   * edge creation needs persistence: with secret/absent numbers the same
--     spell must stay active (not on the GCD) for MIN_COOLDOWN seconds, then
--     the entry is BACK-DATED to the first sighting,
--   * a lockout read (shorter than half the known duration, or one plain
--     (start, duration) pair on >= 3 unrelated tracked spells in one pass)
--     anchors nothing, learns nothing, clears nothing.
--
-- Seams (tests/test_tiers.lua law): FX.Compat.PlainOrNil is wrapped so a
-- string sentinel classifies as nil (what a live secret does downstream), the
-- FX.Compat readers are scripted, and GetTime is a fake clock so a 20 s wand
-- fight runs in milliseconds. Every seam is restored inside `withSeams`
-- (pcall + rethrow): the framework has no teardown.

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local M = FX.Cooldown.Module

local SECRET = "FXTEST-SECRET-VALUE"
local MIN = Engine.MIN_COOLDOWN

local originalStorage = Engine.learned
local realPlainOrNil = FX.Compat.PlainOrNil
local savedStats = {}
for k, v in pairs(Engine.stats or {}) do savedStats[k] = v end

local function allKnown() return true end

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

local function countEntries()
    local n = 0
    for _ in pairs(Engine.entries) do n = n + 1 end
    return n
end

local function countPending()
    local n = 0
    for _ in pairs(Engine.pendingEdge) do n = n + 1 end
    return n
end

local function resetStats()
    local s = Engine.stats
    s.edgesCreated, s.edgesPlainGuard, s.edgesNotPersistent = 0, 0, 0
    s.lockoutsSkipped = 0
    s.lastEdgeName, s.lastEdgeAt = nil, nil
end

--- Delta helper: one snapshot of the integer counters, then `d("field")`.
local function snap()
    local s = Engine.stats
    local before = { s.edgesCreated, s.edgesPlainGuard, s.edgesNotPersistent,
                     s.lockoutsSkipped }
    local keys = { "edgesCreated", "edgesPlainGuard", "edgesNotPersistent",
                   "lockoutsSkipped" }
    return function(field)
        for i, k in ipairs(keys) do
            if k == field then return Engine.stats[k] - before[i] end
        end
        error("unknown counter " .. tostring(field))
    end
end

--- A synthetic tracked set of `n` loners (no category, no `shares`), every one
--- with `baseDuration`. Build first (it wipes entries / pending marks /
--- learned is a fresh table), then the tracked set is replaced.
local NAMES = {}
for i = 1, 8 do NAMES[i] = "FXW Spell " .. i end

local function loners(n, baseDuration)
    Engine:AttachStorage({})
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.tracked)
    wipe(Engine.entries)
    for i = 1, n do
        Engine.tracked[NAMES[i]] = { name = NAMES[i], baseDuration = baseDuration }
    end
    resetStats()
end

local function realHunterSet()
    Engine:AttachStorage({})
    local n = Engine:Build("HUNTER", allKnown)
    assertNotNil(n)
    wipe(Engine.entries)
    resetStats()
    return n
end

local clock = 0
local base = 5000

--- Run `body(pass)` with the scripted readers installed. `pass(t)` sets the
--- fake clock to base + t and runs the REAL Module:ReadAll. `infoFor(key, t)`
--- answers the SpellCooldownInfo of every tracked spell at pass time `t`.
local function withSeams(infoFor, body)
    local saved = {
        info = FX.Compat.GetSpellCooldownInfo,
        charges = FX.Compat.GetSpellCharges,
        dur = FX.Compat.GetSpellCooldownDurationObject,
        time = _G.GetTime,
        plain = FX.Compat.PlainOrNil,
        secretMode = FX.SecretState and FX.SecretState.cooldownsSecret,
    }
    local t = 0
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlainOrNil(v)
    end
    FX.Compat.GetSpellCooldownInfo = function(key) return infoFor(key, t) end
    FX.Compat.GetSpellCharges = function()
        return { currentCharges = SECRET, maxCharges = 1,
                 cooldownStartTime = SECRET, cooldownDuration = SECRET }
    end
    FX.Compat.GetSpellCooldownDurationObject = function() return nil end
    if FX.SecretState then FX.SecretState.cooldownsSecret = nil end
    _G.GetTime = function() return clock end
    clock = base
    local function pass(at)
        t = at
        clock = base + at
        M:ReadAll()
    end
    local ok, err = pcall(body, pass)
    FX.Compat.GetSpellCooldownInfo = saved.info
    FX.Compat.GetSpellCharges = saved.charges
    FX.Compat.GetSpellCooldownDurationObject = saved.dur
    FX.Compat.PlainOrNil = saved.plain
    _G.GetTime = saved.time
    if FX.SecretState then FX.SecretState.cooldownsSecret = saved.secretMode end
    if not ok then error(err, 0) end
end

local function statusLines()
    local out = {}
    local realPrint = FX.Print
    FX.Print = function(msg) out[#out + 1] = tostring(msg) end
    local ok, err = pcall(M.Status, M)
    FX.Print = realPrint
    if not ok then error(err, 0) end
    return out
end

local function tiersLine()
    for _, l in ipairs(statusLines()) do
        if l:find("^readTiers:") then return l end
    end
    return nil
end

-- A wand shot every 2.5 s whose recovery shows as active for 1.5 s.
local SHOT_PERIOD, SHOT_ACTIVE = 2.5, 1.5
local function wandActive(t) return (t % SHOT_PERIOD) < SHOT_ACTIVE end

-- ============================================== the wand pattern (a) + (b) ==

test("(a) wand pattern, secret numbers: isActive=true/isOnGCD=false on every spell for 1.5 s every 2.5 s never creates an entry", function()
    local n = realHunterSet()
    assertTrue(n > 3)
    local d = snap()
    withSeams(function(_, t)
        return { startTime = SECRET, duration = SECRET, modRate = SECRET,
                 isEnabled = true, isActive = wandActive(t), isOnGCD = false }
    end, function(pass)
        for k = 0, 40 do                 -- 20 s, a read every 0.5 s
            pass(k * 0.5)
            assertEquals(0, countEntries())
        end
    end)
    assertEquals(0, countEntries())
    assertEquals(0, d("edgesCreated"))
    assertEquals(0, d("edgesPlainGuard"))
    -- Shots at 0, 2.5 ... 17.5 each ended before MIN_COOLDOWN: one suppressed
    -- episode per spell per shot (the t=20 shot is still open: a live mark).
    assertEquals(8 * n, d("edgesNotPersistent"))
    assertEquals(n, countPending())
    assertNil(Engine.stats.lastEdgeName)
end)

test("(b) wand pattern, plain short numbers: the plain-number guard creates nothing", function()
    local n = realHunterSet()
    local d = snap()
    withSeams(function(_, t)
        if wandActive(t) then
            -- The shot's own recovery: a plain (start, 1.5 s) pair, under
            -- MIN_COOLDOWN, so not a tracked cooldown by the engine's law.
            return { startTime = base + t - (t % SHOT_PERIOD), duration = SHOT_ACTIVE,
                     modRate = 1, isEnabled = true, isActive = true, isOnGCD = false }
        end
        return { startTime = 0, duration = 0, modRate = 1, isEnabled = true,
                 isActive = false, isOnGCD = false }
    end, function(pass)
        for k = 0, 40 do
            pass(k * 0.5)
            assertEquals(0, countEntries())
        end
    end)
    assertEquals(0, countEntries())
    assertEquals(0, d("edgesCreated"))
    assertEquals(0, d("edgesNotPersistent"))
    -- One suppressed false edge per spell per shot, shots at 0 .. 20 = 9.
    assertEquals(9 * n, d("edgesPlainGuard"))
    assertEquals(0, countPending())
    -- Nothing learned from the 1.5 s recovery either.
    local learned = 0
    for _ in pairs(Engine.learned) do learned = learned + 1 end
    assertEquals(0, learned)
end)

-- ======================================================== persistence (c) ==

test("(c) a genuine in-combat cooldown (secret numbers, active for 4 s) makes ONE edge entry back-dated to first sight", function()
    loners(3, 30)
    local d = snap()
    withSeams(function(key, _)
        return { startTime = SECRET, duration = SECRET, modRate = SECRET,
                 isEnabled = true, isActive = key == NAMES[1], isOnGCD = false }
    end, function(pass)
        for k = 0, 5 do                  -- t = 0 .. 2.5: under MIN_COOLDOWN
            pass(k * 0.5)
            assertEquals(0, countEntries())
        end
        near(base, Engine.pendingEdge[NAMES[1]])   -- the mark is the first sighting
        assertNil(Engine.pendingEdge[NAMES[2]])
        assertEquals(0, d("edgesCreated"))

        pass(3.0)                        -- >= MIN_COOLDOWN: the entry appears
        assertEquals(1, countEntries())
        local e = Engine.entries[NAMES[1]]
        assertNotNil(e)
        assertEquals("edge", e.source)
        assertTrue(e.predicted)
        near(base, e.start)              -- BACK-DATED to first sight, not to t=3
        near(30, e.duration)             -- the full window
        near(base + 30, e.endTime)
        assertNil(Engine.pendingEdge[NAMES[1]])   -- the mark is spent
        assertEquals(1, d("edgesCreated"))
        assertEquals(NAMES[1], Engine.stats.lastEdgeName)
        near(base + 3.0, Engine.stats.lastEdgeAt)

        pass(3.5)
        pass(4.0)                        -- still ONE entry, still one creation
        assertEquals(1, countEntries())
        assertEquals(1, d("edgesCreated"))
    end)
    assertEquals(0, d("edgesPlainGuard"))
    assertEquals(0, d("edgesNotPersistent"))
end)

test("Persistence marks: inactive / GCD clear, a secret bit leaves it, a stale mark is dropped", function()
    loners(2, 30)
    local a = NAMES[1]
    local d = snap()

    -- First active read: a mark, no entry.
    assertEquals("pending", Engine:OnReadActive(a, true, false, 100))
    near(100, Engine.pendingEdge[a])
    assertEquals(0, countEntries())

    -- A secret/absent boolean has no voice: the mark stays.
    local savedPlain = FX.Compat.PlainOrNil
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlainOrNil(v)
    end
    assertEquals("kept", Engine:OnReadActive(a, SECRET, SECRET, 101))
    assertEquals("kept", Engine:OnReadActive(a, nil, nil, 101.5))
    FX.Compat.PlainOrNil = savedPlain
    near(100, Engine.pendingEdge[a])
    assertEquals(0, d("edgesNotPersistent"))

    -- isActive == false clears it (and counts one suppressed episode).
    assertEquals("ignored", Engine:OnReadActive(a, false, false, 102))
    assertNil(Engine.pendingEdge[a])
    assertEquals(1, d("edgesNotPersistent"))

    -- isOnGCD == true clears it too.
    assertEquals("pending", Engine:OnReadActive(a, true, false, 110))
    assertEquals("ignored", Engine:OnReadActive(a, true, true, 111))
    assertNil(Engine.pendingEdge[a])
    assertEquals(2, d("edgesNotPersistent"))

    -- A mark with no confirming read for > 10 s is dropped: the next active
    -- read starts over at ITS time, not at the old first sighting.
    assertEquals("pending", Engine:OnReadActive(a, true, false, 200))
    assertEquals("pending", Engine:OnReadActive(a, true, false, 201))
    assertEquals("pending", Engine:OnReadActive(a, true, false, 212))   -- > 10 s gap
    near(212, Engine.pendingEdge[a])
    assertEquals(0, countEntries())
    assertEquals(3, d("edgesNotPersistent"))
    -- ... and the continuous run from 212 persists to an entry at 212 + MIN.
    assertEquals("pending", Engine:OnReadActive(a, true, false, 214))
    assertEquals("edge", Engine:OnReadActive(a, true, false, 215))
    local e = Engine.entries[a]
    near(212, e.start)
    near(242, e.endTime)

    -- A live entry owns the spell: marks never coexist with it.
    assertEquals("kept", Engine:OnReadActive(a, true, false, 216))
    assertNil(Engine.pendingEdge[a])

    -- Engine:Build wipes marks; a cast event (the better signal) drops one.
    Engine:OnReadActive(NAMES[2], true, false, 300)
    assertNotNil(Engine.pendingEdge[NAMES[2]])
    Engine:OnCast(NAMES[2], 300.5)
    assertNil(Engine.pendingEdge[NAMES[2]])
    wipe(Engine.entries)
    Engine:OnReadActive(NAMES[1], true, false, 500)
    assertEquals(1, countPending())
    Engine:Build("HUNTER", allKnown)
    assertEquals(0, countPending())
end)

-- =================================================== the plain-number guard ==

test("The plain-number guard: a plain numeric verdict means no edge; the early clear needs the numbers to agree", function()
    loners(2, 30)
    local a = NAMES[1]
    local d = snap()

    -- Plain numbers present and no running cooldown >= MIN ("cleared"/"ignored"
    -- verdicts, or a lockout): the booleans never create anything.
    for _, verdict in ipairs({ "cleared", "ignored", "anchored", "lockout" }) do
        assertEquals("ignored", Engine:OnReadActive(a, true, false, 1000, verdict))
        assertEquals(0, countEntries())
        assertEquals(0, countPending())
    end
    -- One episode counts once, however many reads it spans ...
    assertEquals(1, d("edgesPlainGuard"))
    -- ... and an inactive read ends the episode, so the next one counts again.
    Engine:OnReadActive(a, false, false, 1001, "cleared")
    Engine:OnReadActive(a, true, false, 1002, "cleared")
    assertEquals(2, d("edgesPlainGuard"))
    assertEquals(0, d("edgesCreated"))
    -- A "secret" verdict is NOT plain: it falls through to persistence.
    Engine:OnReadActive(a, false, false, 1003, "secret")
    assertEquals("pending", Engine:OnReadActive(a, true, false, 1004, "secret"))
    assertEquals(2, d("edgesPlainGuard"))
    Engine:OnReadActive(a, false, false, 1005)

    -- The early clear (isActive == false on an old prediction) stays, but not
    -- when the plain numbers say the cooldown is running.
    Engine:OnCast(a, 2000)
    local endBefore = Engine.entries[a].endTime
    assertEquals("kept", Engine:OnReadActive(a, false, false, 2100, "anchored"))
    assertEquals("kept", Engine:OnReadActive(a, false, false, 2100, "lockout"))
    near(endBefore, Engine.entries[a].endTime)
    assertEquals("cleared", Engine:OnReadActive(a, false, false, 2100, "cleared"))
    near(2100, Engine.entries[a].endTime)
end)

-- ============================================================ lockout law ==

test("OnRead lockout law: a read under half the known duration anchors, learns and clears nothing", function()
    loners(2, 10)
    local a = NAMES[1]
    local d = snap()

    -- base 10: 4 s is < 50% -> a lockout.
    assertEquals("lockout", Engine:OnRead(a, 1000, 4, 1001))
    assertNil(Engine.entries[a])
    assertNil(Engine.learned[a])
    assertEquals(1, d("lockoutsSkipped"))

    -- Exactly 50% is the spell's own cooldown: anchors and learns as before.
    assertEquals("anchored", Engine:OnRead(a, 1000, 5, 1001))
    assertEquals(5, Engine.learned[a])
    assertEquals(1, d("lockoutsSkipped"))

    -- A learned value beats the base as the reference: learned 60 makes a
    -- 25 s read (< 30) a lockout even though 25 >= 50% of base 10.
    wipe(Engine.entries)
    Engine.learned[a] = 60
    assertEquals("lockout", Engine:OnRead(a, 1000, 25, 1001))
    assertEquals(60, Engine.learned[a])
    assertNil(Engine.entries[a])

    -- Clears nothing: a running prediction survives a lockout read.
    Engine:OnCast(a, 1000)
    local e = Engine.entries[a]
    local endBefore = e.endTime
    assertEquals("lockout", Engine:OnRead(a, 1000, 25, 1000.2))
    assertEquals(e, Engine.entries[a])
    assertEquals("cast", e.source)
    near(endBefore, e.endTime)
    assertEquals(60, Engine.learned[a])

    -- No reference at all (no base, nothing learned): nothing to compare to,
    -- the read anchors and learns exactly as before.
    Engine.tracked[NAMES[2]].baseDuration = nil
    assertEquals("anchored", Engine:OnRead(NAMES[2], 1000, 7, 1001))
    assertEquals(7, Engine.learned[NAMES[2]])

    -- The pass-level flag (one plain pair on >= 3 spells): a lockout however
    -- long the read is.
    wipe(Engine.entries)
    Engine.learned[a] = nil
    assertEquals("lockout", Engine:OnRead(a, 1000, 10, 1001, true))
    assertNil(Engine.entries[a])
    assertNil(Engine.learned[a])
    assertEquals(4, d("lockoutsSkipped"))

    -- A secret read still says "secret", ahead of every lockout test.
    local savedPlain = FX.Compat.PlainOrNil
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlainOrNil(v)
    end
    assertEquals("secret", Engine:OnRead(a, SECRET, SECRET, 1002, true))
    FX.Compat.PlainOrNil = savedPlain
    assertEquals(4, d("lockoutsSkipped"))
end)

test("(d) a plain real cooldown still anchors and learns exactly as before", function()
    loners(3, 10)
    local d = snap()
    withSeams(function(key, _)
        if key == NAMES[1] then
            -- Cast 2 s ago, an 8 s cooldown (>= 50% of the data's 10 s).
            return { startTime = base - 2, duration = 8, modRate = 1,
                     isEnabled = true, isActive = true, isOnGCD = false }
        end
        return { startTime = 0, duration = 0, modRate = 1, isEnabled = true,
                 isActive = false, isOnGCD = false }
    end, function(pass)
        pass(0)
        local e = Engine.entries[NAMES[1]]
        assertNotNil(e)
        assertEquals("read", e.source)
        assertTrue(e.anchored)
        assertFalse(e.predicted)
        near(base - 2, e.start)
        near(8, e.duration)
        near(base + 6, e.endTime)
        assertEquals(8, Engine.learned[NAMES[1]])
        assertNil(Engine.learned[NAMES[2]])
        assertEquals(1, countEntries())
        -- A second pass: the live entry owns the spell, nothing else happens.
        pass(1)
        assertEquals(1, countEntries())
    end)
    assertEquals(0, d("edgesCreated"))
    assertEquals(0, d("edgesPlainGuard"))
    assertEquals(0, d("edgesNotPersistent"))
    assertEquals(0, d("lockoutsSkipped"))
    assertEquals(0, countPending())
end)

test("(e) one plain (start, duration) pair on 4 spells in one pass is a shared lockout: nothing anchored or learned", function()
    loners(5, 10)
    local d = snap()
    local function sharedPair(key, _)
        for i = 1, 4 do
            if key == NAMES[i] then
                return { startTime = base - 1, duration = 8, modRate = 1,
                         isEnabled = true, isActive = true, isOnGCD = false }
            end
        end
        return { startTime = 0, duration = 0, modRate = 1, isEnabled = true,
                 isActive = false, isOnGCD = false }
    end
    withSeams(sharedPair, function(pass)
        pass(0)
        assertEquals(0, countEntries())
        for i = 1, 5 do assertNil(Engine.learned[NAMES[i]]) end
        assertEquals(4, d("lockoutsSkipped"))
        -- The booleans of those reads are the same noise: plain numbers
        -- authoritative, so no edge either.
        assertEquals(0, d("edgesCreated"))
        assertEquals(4, d("edgesPlainGuard"))
        assertEquals(0, countPending())
    end)

    -- Two spells with the same pair are NOT a lockout (< 3): their own reads.
    loners(5, 10)
    local twoOnly = function(key, _)
        if key == NAMES[1] or key == NAMES[2] then
            return { startTime = base - 1, duration = 8, modRate = 1,
                     isEnabled = true, isActive = true, isOnGCD = false }
        end
        return { startTime = 0, duration = 0, modRate = 1, isEnabled = true,
                 isActive = false, isOnGCD = false }
    end
    withSeams(twoOnly, function(pass)
        pass(0)
        assertEquals(2, countEntries())
        assertEquals(8, Engine.learned[NAMES[1]])
        assertEquals(8, Engine.learned[NAMES[2]])
    end)

    -- A DECLARED shared cooldown (equal category: the Hunter traps' 411, the
    -- Shaman shocks) legitimately reports one pair on every member: that is
    -- the members' own cooldown, not a lockout.
    loners(5, 10)
    for i = 1, 4 do Engine.tracked[NAMES[i]].category = 999 end
    resetStats()
    withSeams(sharedPair, function(pass)
        pass(0)
        assertEquals(4, countEntries())
        for i = 1, 4 do assertEquals(8, Engine.learned[NAMES[i]]) end
        assertEquals(0, Engine.stats.lockoutsSkipped)
    end)
end)

-- ========================================================== observability ==

test("(f) /fx status: the readTiers line stays one line and grows only non-zero parts", function()
    loners(1, 10)
    local base0 = M._readTiers
    local head = string.format("readTiers: numeric %d | boolean %d | duration %d",
        base0.numeric, base0.boolean, base0.duration)

    -- All counters zero: byte-identical to the pre-guard line.
    resetStats()
    assertEquals(head, tiersLine())

    local saved = _G.GetTime
    _G.GetTime = function() return 9000 end
    local ok, err = pcall(function()
        local s = Engine.stats
        s.edgesCreated, s.edgesPlainGuard = 2, 5
        assertEquals(head .. " | edges 2 | edge-plain-guard 5", tiersLine())

        s.edgesNotPersistent, s.lockoutsSkipped = 64, 4
        s.lastEdgeName, s.lastEdgeAt = "Rapid Fire", 8988
        assertEquals(head .. " | edges 2 | edge-plain-guard 5"
            .. " | edge-not-persistent 64 | lockout-skips 4"
            .. " | last edge Rapid Fire 12s ago", tiersLine())

        -- Zero parts vanish individually.
        s.edgesCreated, s.edgesNotPersistent = 0, 0
        assertEquals(head .. " | edge-plain-guard 5 | lockout-skips 4"
            .. " | last edge Rapid Fire 12s ago", tiersLine())
        s.edgesPlainGuard, s.lockoutsSkipped = 0, 0
        s.lastEdgeName, s.lastEdgeAt = nil, nil
        assertEquals(head, tiersLine())
    end)
    _G.GetTime = saved
    if not ok then error(err, 0) end
end)

test("The counters are bumped by the engine paths themselves (edge creation + last edge)", function()
    loners(1, 10)
    local d = snap()
    assertEquals("pending", Engine:OnReadActive(NAMES[1], true, false, 100))
    assertEquals("edge", Engine:OnReadActive(NAMES[1], true, false, 103))
    assertEquals(1, d("edgesCreated"))
    assertEquals(NAMES[1], Engine.stats.lastEdgeName)
    near(103, Engine.stats.lastEdgeAt)
    -- OnActiveEdge itself back-dates when handed a first-sighting start.
    wipe(Engine.entries)
    local e = Engine:OnActiveEdge(NAMES[1], 500, 497)
    near(497, e.start)
    near(507, e.endTime)
    near(10, e.duration)
end)

-- Registered last => runs last: hand the module's storage back and leave the
-- engine empty for anything that runs after this file (test_tiers.lua law).
test("Restore module storage and engine state (wand guards)", function()
    FX.Compat.PlainOrNil = realPlainOrNil
    Engine:AttachStorage(originalStorage)
    wipe(Engine.tracked)
    wipe(Engine.entries)
    wipe(Engine.pendingEdge)
    resetStats()
    for k, v in pairs(savedStats) do Engine.stats[k] = v end
    assertEquals(originalStorage, Engine.learned)
end)
