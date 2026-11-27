-- addon/Forte_Cooldown/tests/test_zzd_ready_read_pop.lua
-- Issue #1 follow-up: "the cooldown splash does not play at the end of the
-- cooldown, even with the option on". The READY MOMENT was never popped when
-- the game's own plain read said "ready" a little before our predicted /
-- anchored endTime: Engine:OnRead deleted the live entry (no pop -> no bar
-- pulse, no Secondary Splash, no FX_COOLDOWN_READY). The read now LANDS the
-- window (endTime = now, like OnReadActive's early-end branch) and the next
-- Sweep retires it with the NORMAL ready pop, exactly once.
--
-- Every case runs through BOTH seams: "engine" (Engine:OnRead called directly)
-- and "module" (the REAL Module:ReadAll with scripted SpellCooldownInfo and a
-- fake clock); the pop always goes through the REAL Module:ProcessReadyPops,
-- observed at Display:OnReady, Splash:OnReady (+ the Secondary Splash icon
-- slot) and the FX_COOLDOWN_READY bus event. Clocks are injected; the epoch
-- sits far above every other file's so the live 10 Hz ticker never pops ours.
-- Seams are restored inside the test that took them (no teardown hook).

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local M = FX.Cooldown.Module
local Display = FX.Cooldown.Display
local Splash = FX.Cooldown.Splash

local SPELL = "Bestial Wrath"   -- Hunter, 120 s in the generated data
local BASE = 700000

local PATHS = { "engine", "module" }

local originalStorage = Engine.learned
local realPlainOrNil = FX.Compat.PlainOrNil

local function allKnown() return true end

--- A clean Hunter build with a private storage; returns SPELL's duration.
local function setup()
    Engine:AttachStorage({})
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)
    return Engine:BestDuration(SPELL)
end

local function statsMark()
    local s = Engine.stats
    return { ready = s.readyFromRead, lock = s.lockoutsSkipped }
end

-- ============================================================== the seams ==

--- Run the REAL Module:ReadAll at `now` with `script[name]` as that spell's
--- SpellCooldownInfo (every other spell reads "ready": zeros, no booleans on).
local function readAll(now, script)
    local saved = {
        info = FX.Compat.GetSpellCooldownInfo,
        charges = FX.Compat.GetSpellCharges,
        dur = FX.Compat.GetSpellCooldownDurationObject,
        time = _G.GetTime,
        secretMode = FX.SecretState and FX.SecretState.cooldownsSecret,
    }
    FX.Compat.GetSpellCooldownInfo = function(key)
        return script[key] or { startTime = 0, duration = 0,
                                isActive = false, isOnGCD = false }
    end
    FX.Compat.GetSpellCharges = function() return nil end
    FX.Compat.GetSpellCooldownDurationObject = function() return nil end
    if FX.SecretState then FX.SecretState.cooldownsSecret = nil end
    _G.GetTime = function() return now end
    local ok, err = pcall(M.ReadAll, M)
    FX.Compat.GetSpellCooldownInfo = saved.info
    FX.Compat.GetSpellCharges = saved.charges
    FX.Compat.GetSpellCooldownDurationObject = saved.dur
    _G.GetTime = saved.time
    if FX.SecretState then FX.SecretState.cooldownsSecret = saved.secretMode end
    if not ok then error(err, 0) end
end

--- A plain "ready" read of SPELL (start 0, duration 0) at `now`.
local function readyRead(path, now)
    if path == "engine" then
        return Engine:OnRead(SPELL, 0, 0, now)
    end
    return readAll(now, {})
end

--- A GCD-sized read (start > 0, duration < MIN_COOLDOWN) of SPELL.
local function gcdRead(path, now)
    if path == "engine" then
        return Engine:OnRead(SPELL, now - 0.5, 1.5, now)
    end
    return readAll(now, { [SPELL] = { startTime = now - 0.5, duration = 1.5,
                                      isActive = true, isOnGCD = true } })
end

--- A plain cooldown read of SPELL: the window (start, duration) seen at `now`.
local function windowRead(path, start, duration, now, sharedPair)
    if path == "engine" then
        return Engine:OnRead(SPELL, start, duration, now, sharedPair)
    end
    return readAll(now, { [SPELL] = { startTime = start, duration = duration,
                                      isActive = true, isOnGCD = false } })
end

local spy
--- Count what a pop reaches: Display:OnReady, Splash:OnReady, and the bus
--- fire. test_splash.lua leaves `FX.Fire` nil for every later file (its
--- "inert without the bus" row) and no other reference to the real entry
--- survives, so a recording `FX.Fire` stands in for the bus for the duration
--- of the spy (test_splash.lua's own seam): the pop's own
--- `FX.Fire("FX_COOLDOWN_READY", name, ...)` call lands in it. Taken away again.
local function spyOn()
    spy = { display = {}, splash = {}, bus = {}, restore = {} }
    local function wrap(owner, key, bucket)
        local real = owner[key]
        owner[key] = function(self, name, ...)
            bucket[name] = (bucket[name] or 0) + 1
            return real(self, name, ...)
        end
        spy.restore[#spy.restore + 1] = function() owner[key] = real end
    end
    wrap(Display, "OnReady", spy.display)
    wrap(Splash, "OnReady", spy.splash)
    local fireBefore = FX.Fire
    FX.Fire = function(event, name, ...)
        if event == "FX_COOLDOWN_READY" then
            spy.bus[name] = (spy.bus[name] or 0) + 1
        end
        if fireBefore then return fireBefore(event, name, ...) end
    end
    spy.restore[#spy.restore + 1] = function() FX.Fire = fireBefore end
end

local function spyOff()
    for _, r in ipairs(spy.restore) do r() end
end

local function pops(name)
    return spy.display[name] or 0, spy.splash[name] or 0, spy.bus[name] or 0
end

local function assertPops(n, name, what)
    local d, s, b = pops(name)
    assertEquals(n, d, what .. ": Display:OnReady count")
    assertEquals(n, s, what .. ": Splash:OnReady count")
    assertEquals(n, b, what .. ": FX_COOLDOWN_READY count")
end

local function activeIcons()
    local n = 0
    for _, slot in ipairs(Splash._icons or {}) do
        if slot.active then n = n + 1 end
    end
    return n
end

--- Run `body(path, t0)` once per seam with a fresh engine, spies, and (for
--- the Secondary Splash window check) the Splash enabled.
local function perPath(k, body)
    for i, path in ipairs(PATHS) do
        local dur = setup()
        local t0 = BASE + k * 1000 + i * 100
        Display:Init()
        Splash:OnEnable()
        Splash:SetEnabled(false)
        Splash:SetEnabled(true)
        spyOn()
        local ok, err = pcall(body, path, t0, dur)
        spyOff()
        Splash:SetEnabled(false)
        Splash:Update(GetTime() + 100)
        wipe(Engine.entries)
        if not ok then error("[" .. path .. "] " .. tostring(err), 0) end
    end
end

-- ================================================================= tests ==

test("(a) a cast entry, grace over, plain ready read 0.4 s early: ONE ready pop reaches bar, splash, bus",
function()
    perPath(1, function(path, t0, dur)
        local m = statsMark()
        Engine:OnCast(SPELL, t0)
        local endT = t0 + dur
        local at = endT - 0.4
        readyRead(path, at)
        local e = Engine.entries[SPELL]
        assertNotNil(e, "the entry is LANDED, not deleted")
        assertEquals(at, e.endTime, "the window ends at the read")
        assertEquals(at - t0, e.duration, "duration stays consistent with start")
        assertPops(0, SPELL, "before the Sweep")
        M:ProcessReadyPops(at + 0.05)
        assertPops(1, SPELL, "the Sweep pop")
        assertEquals(1, activeIcons(), "the Secondary Splash window is shown")
        assertNil(Engine.entries[SPELL], "retired by the Sweep")
        assertEquals(m.ready + 1, Engine.stats.readyFromRead, "counted once")
        M:ProcessReadyPops(endT + 1)            -- the old clock lapsing
        assertPops(1, SPELL, "no second pop at the old endTime")
    end)
end)

test("(b) an anchored read entry ended early by a plain ready read (a reset): one pop",
function()
    perPath(2, function(path, t0, dur)
        assertEquals("anchored", Engine:OnRead(SPELL, t0, dur, t0 + 1))
        local e = Engine.entries[SPELL]
        assertEquals("read", e.source)
        assertTrue(e.anchored)
        local at = t0 + 50
        readyRead(path, at)
        e = Engine.entries[SPELL]
        assertNotNil(e)
        assertEquals(at, e.endTime)
        assertTrue(e.anchored, "the flags are kept as they were")
        assertEquals(false, e.predicted)
        M:ProcessReadyPops(at + 0.1)
        assertPops(1, SPELL, "the reset pops")
        M:ProcessReadyPops(t0 + dur + 1)
        assertPops(1, SPELL, "and only once")
    end)
end)

test("(c) two ready reads in a row before the Sweep: still one pop, no re-land, one count",
function()
    perPath(3, function(path, t0, dur)
        local m = statsMark()
        Engine:OnCast(SPELL, t0)
        local first = t0 + dur - 0.5   -- READY_SKEW rule: re-timed from dur - 3
        readyRead(path, first)
        readyRead(path, first + 0.05)
        readyRead(path, first + 0.08)
        local e = Engine.entries[SPELL]
        assertNotNil(e)
        assertEquals(first, e.endTime, "the second read did not re-land")
        M:ProcessReadyPops(first + 0.1)
        assertPops(1, SPELL, "two reads, one pop")
        readyRead(path, first + 0.2)            -- entry gone: a no-op
        M:ProcessReadyPops(first + 0.3)
        assertPops(1, SPELL, "a read after the pop pops nothing")
        assertEquals(m.ready + 1, Engine.stats.readyFromRead)
    end)
end)

test("(c2) a landed entry is not resurrected by a late read of the SAME window; a NEW window is",
function()
    perPath(4, function(path, t0, dur)
        assertEquals("anchored", Engine:OnRead(SPELL, t0, dur, t0 + 1))
        local at = t0 + 30
        readyRead(path, at)
        assertTrue(Engine.entries[SPELL].landed)
        -- The old window read again (it started before the landing).
        windowRead(path, t0, dur, at + 0.02)
        local e = Engine.entries[SPELL]
        assertEquals(at, e.endTime, "still landed at the read")
        M:ProcessReadyPops(at + 0.1)
        assertPops(1, SPELL, "popped once, not resurrected")
    end)
    -- A genuinely new window (started after the landing) re-anchors.
    local dur = setup()
    local t0 = BASE + 4900
    assertEquals("anchored", Engine:OnRead(SPELL, t0, dur, t0 + 1))
    Engine:OnRead(SPELL, 0, 0, t0 + 30)
    assertTrue(Engine.entries[SPELL].landed)
    assertEquals("anchored", Engine:OnRead(SPELL, t0 + 30.2, dur, t0 + 30.3))
    local e = Engine.entries[SPELL]
    assertNil(e.landed)
    assertEquals(t0 + 30.2 + dur, e.endTime)
    wipe(Engine.entries)
    -- And a fresh cast of a landed entry clears the mark.
    Engine:OnCast(SPELL, t0)
    Engine:OnRead(SPELL, 0, 0, t0 + 119.5)   -- re-timed from +30 (READY_SKEW rule)
    assertTrue(Engine.entries[SPELL].landed)
    Engine:OnCast(SPELL, t0 + 30.1)
    assertNil(Engine.entries[SPELL].landed)
    wipe(Engine.entries)
end)

test("(d) a ready read inside the prediction grace: no pop, entry kept (existing law)",
function()
    perPath(5, function(path, t0, dur)
        local m = statsMark()
        Engine:OnCast(SPELL, t0)
        readyRead(path, t0 + 1.0)               -- grace is 1.6 s
        local e = Engine.entries[SPELL]
        assertNotNil(e, "kept")
        assertEquals(t0 + dur, e.endTime, "window untouched")
        assertNil(e.landed)
        M:ProcessReadyPops(t0 + 1.1)
        assertPops(0, SPELL, "no pop in the grace")
        assertEquals(m.ready, Engine.stats.readyFromRead, "not counted")
        if path == "engine" then
            assertEquals("ignored", Engine:OnRead(SPELL, 0, 0, t0 + 1.2))
        end
    end)
end)

test("(e) lockout reads clear nothing and pop nothing; a never-anchored edge entry dies silent",
function()
    perPath(6, function(path, t0, dur)
        local m = statsMark()
        assertEquals("anchored", Engine:OnRead(SPELL, t0, dur, t0 + 1))
        local endT = t0 + dur
        -- (a) shorter than half the known duration.
        local verdict = windowRead(path, t0 + 9, 10, t0 + 10)
        if path == "engine" then assertEquals("lockout", verdict) end
        local e = Engine.entries[SPELL]
        assertNotNil(e)
        assertEquals(endT, e.endTime, "the window is untouched")
        assertNil(e.landed)
        -- (b) the caller flags a shared pair (engine seam only: ReadAll's
        -- own pass flag needs three unrelated spells on one pair).
        if path == "engine" then
            assertEquals("lockout", windowRead(path, t0 + 20, 100, t0 + 21, true))
            assertEquals(endT, Engine.entries[SPELL].endTime)
        end
        assertEquals(m.lock + (path == "engine" and 2 or 1), Engine.stats.lockoutsSkipped)
        M:ProcessReadyPops(t0 + 22)
        assertPops(0, SPELL, "a lockout pops nothing")
        assertEquals(m.ready, Engine.stats.readyFromRead)
        wipe(Engine.entries)

        -- A never-anchored edge entry: silence, as the inferred-entries law.
        Engine:OnActiveEdge(SPELL, t0 + 100)
        readyRead(path, t0 + 105)
        assertNil(Engine.entries[SPELL], "swept in silence")
        M:ProcessReadyPops(t0 + 106)
        assertPops(0, SPELL, "an inferred entry never claims the ready moment")
        assertEquals(m.ready, Engine.stats.readyFromRead)
    end)
end)

test("(f) charge entries are unchanged: a plain ready read is ignored, nothing lands, nothing pops",
function()
    perPath(8, function(path, t0)
        local m = statsMark()
        Engine.tracked[SPELL].maxCharges = 2
        Engine:OnCast(SPELL, t0)
        local e = Engine.entries[SPELL]
        assertNotNil(e.charges)
        local endT = e.endTime
        readyRead(path, t0 + 5)
        assertEquals("ignored", Engine:OnRead(SPELL, 0, 0, t0 + 6))
        e = Engine.entries[SPELL]
        assertNotNil(e, "the charge read owns the lifecycle")
        assertEquals(endT, e.endTime)
        assertNil(e.landed)
        M:ProcessReadyPops(t0 + 7)
        assertPops(0, SPELL, "no pop")
        assertEquals(m.ready, Engine.stats.readyFromRead)
    end)
end)

test("a GCD-sized read (the spell has no cooldown of its own) is a ready read: lands, one pop",
function()
    perPath(9, function(path, t0, dur)
        Engine:OnCast(SPELL, t0)
        local at = t0 + dur - 0.5   -- re-timed from dur - 10 (READY_SKEW rule)
        gcdRead(path, at)
        assertEquals(at, Engine.entries[SPELL].endTime)
        M:ProcessReadyPops(at + 0.1)
        assertPops(1, SPELL, "the GCD read lands the window")
    end)
end)

test("(g) readyFromRead counts windows a read ended, and /fx status shows it only when non-zero",
function()
    setup()
    local t0 = BASE + 10000
    local s = Engine.stats
    local saved = s.readyFromRead
    s.readyFromRead = 0

    local function readTiersLine()
        local out = {}
        local realPrint = FX.Print
        FX.Print = function(msg) out[#out + 1] = tostring(msg) end
        local savedTime = _G.GetTime
        _G.GetTime = function() return t0 end
        local ok, err = pcall(M.Status, M)
        FX.Print = realPrint
        _G.GetTime = savedTime
        if not ok then error(err, 0) end
        for _, l in ipairs(out) do
            if l:find("^readTiers:") then return l end
        end
    end

    local ok, err = pcall(function()
        local line0 = readTiersLine()
        assertNotNil(line0)
        assertNil(line0:find("ready-from-read", 1, true), "zero: no part")
        -- A read-ended window counts once; a clock-ended one does not.
        Engine:OnCast(SPELL, t0)
        Engine:OnRead(SPELL, 0, 0, t0 + 119.5)  -- re-timed from +20 (READY_SKEW rule)
        Engine:OnRead(SPELL, 0, 0, t0 + 119.55) -- idempotent
        assertEquals(1, s.readyFromRead)
        Engine:OnCast("Rapid Fire", t0)
        Engine:Sweep(t0 + 1000, {})             -- by its own clock
        assertEquals(1, s.readyFromRead)
        local line1 = readTiersLine()
        assertTrue(line1:find(" | ready-from-read 1", 1, true) ~= nil, line1)
        s.readyFromRead = 12
        assertTrue(readTiersLine():find(" | ready-from-read 12", 1, true) ~= nil)
        s.readyFromRead = 0
        assertEquals(line0, readTiersLine())
    end)
    s.readyFromRead = saved
    wipe(Engine.entries)
    if not ok then error(err, 0) end
end)

test("(h) plausibility: a PREDICTED 10 s entry + ready read at +2.0 s is a wrong prediction: no pop, deleted, counted",
function()
    for i, path in ipairs(PATHS) do
        local name = SPELL
        setup()
        Engine.tracked[name].baseDuration = 10
        Engine.learned[name] = nil
        local t0 = BASE + 11000 + i * 100
        spyOn()
        local ok, err = pcall(function()
            local m = Engine.stats.predictionsDropped
            local r = Engine.stats.readyFromRead
            Engine:OnCast(name, t0)
            readyRead(path, t0 + 2.0)
            assertNil(Engine.entries[name], "the wrong prediction is deleted")
            M:ProcessReadyPops(t0 + 2.1)
            M:ProcessReadyPops(t0 + 11)
            assertPops(0, name, "no ready moment happened")
            assertEquals(m + 1, Engine.stats.predictionsDropped)
            assertEquals(r, Engine.stats.readyFromRead)
        end)
        spyOff()
        wipe(Engine.entries)
        if not ok then error("[" .. path .. "] " .. tostring(err), 0) end
    end
end)

test("(i) plausibility: predicted 10 s + ready at 9.5 s pops once; anchored 10 s + ready at +2 s (reset) pops once",
function()
    for i, path in ipairs(PATHS) do
        setup()
        Engine.tracked[SPELL].baseDuration = 10
        local t0 = BASE + 12000 + i * 100
        spyOn()
        local ok, err = pcall(function()
            local m = Engine.stats.predictionsDropped
            Engine:OnCast(SPELL, t0)
            readyRead(path, t0 + 9.5)
            M:ProcessReadyPops(t0 + 9.6)
            assertPops(1, SPELL, "predicted, within READY_SKEW of its end")
            assertEquals(m, Engine.stats.predictionsDropped)
            -- Anchored: a real cooldown was confirmed, so an early ready is real.
            local t1 = t0 + 100
            assertEquals("anchored", Engine:OnRead(SPELL, t1, 10, t1 + 0.1))
            readyRead(path, t1 + 2)
            M:ProcessReadyPops(t1 + 2.1)
            assertPops(2, SPELL, "anchored early ready (a reset)")
            assertEquals(m, Engine.stats.predictionsDropped)
        end)
        spyOff()
        wipe(Engine.entries)
        if not ok then error("[" .. path .. "] " .. tostring(err), 0) end
    end
end)

test("(j) /fx status shows predictions-dropped only when non-zero; READY_SKEW is the named 1.0 s",
function()
    assertEquals(1.0, Engine.READY_SKEW)
    local s = Engine.stats
    local saved = s.predictionsDropped
    local function line()
        local out = {}
        local realPrint, realTime = FX.Print, _G.GetTime
        FX.Print = function(msg) out[#out + 1] = tostring(msg) end
        _G.GetTime = function() return BASE end
        local ok, err = pcall(M.Status, M)
        FX.Print, _G.GetTime = realPrint, realTime
        if not ok then error(err, 0) end
        for _, l in ipairs(out) do
            if l:find("^readTiers:") then return l end
        end
    end
    s.predictionsDropped = 0
    local ok, err = pcall(function()
        assertNil(line():find("predictions-dropped", 1, true))
        s.predictionsDropped = 3
        assertTrue(line():find(" | predictions-dropped 3", 1, true) ~= nil)
    end)
    s.predictionsDropped = saved
    if not ok then error(err, 0) end
end)

test("zzd: the module's own storage is handed back", function()
    Engine:AttachStorage(originalStorage)
    FX.Compat.PlainOrNil = realPlainOrNil
    assertEquals(originalStorage, Engine.learned)
end)
