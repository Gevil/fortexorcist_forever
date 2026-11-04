-- addon/Forte_Cooldown/tests/test_zzb_carry.lua
-- FX7a (PLAN §11.2 "Fix round FX7" row 1, source I2f finding 1): a debounced
-- SPELLS_CHANGED rebuild is a re-learn of the KNOWN set, not a statement
-- about the cooldowns running right now. It used to run `Engine:Build`, and
-- Build WIPED `Engine.entries` -- every row running on the bar was LOST, and
-- inside a combat lockdown the follow-up reads may be secret, so the bar
-- stayed empty for the rest of the fight. The law now: a rebuild of the SAME
-- class carries every running entry whose key the fresh state still tracks
-- (the SAME object: start, duration, source, certification, the charge clock,
-- the display tags, the cached display row), drops the entries whose names
-- left the tracked set, and the proc tracker's ICD windows ride the same rule
-- -- their `seen` stamps ride with the windows they armed, so a window is
-- never re-enlisted after a rebuild (the entry rides, so no second window
-- opens for a proc whose ICD is running). A CLASS CHANGE (`FX._playerClass`
-- differs from the last build) is a fresh question: it starts clean.
--
-- The ride is measured through the real path (the test_zz_combat_bar.lua
-- law): SPELLS_CHANGED lands on the module's real event frame, the module's
-- real `C_Timer.After(REBUILD_DEBOUNCE)` fires on the real sim clock, and the
-- assertions read the Engine's own state. This file runs AFTER
-- test_zz_combat_bar.lua (file order) and rides ITS manual-clock opt-in --
-- the enable-once is process-wide, so this file never calls SetManualClock
-- and `A_Admin.AdvanceTime` (which requires manual mode) is available.
-- The riders enter through the real cast path (a resolved
-- UNIT_SPELLCAST_SUCCEEDED, the 4-slot catalog payload) and through the
-- Engine's own cast feed (`Engine:OnCast` -- the exact state a resolved cast
-- leaves, the suite's multi-row convention), because the sim's class profile
-- knows one cast (I2f measured). The known gate is scripted through the
-- suite's `_G.IsPlayerSpell` seam (test_reconcile.lua's law) so the fresh
-- build tracks every rider: this leg is about what the rebuild does to the
-- RUNNING rows, not about who is known. The sim's name-keyed reads are blind
-- (I2f), so nothing here re-anchors a row behind the test's back.
--
-- State discipline: every seam this file takes (the Display's frame state,
-- FX._playerClass, Engine.Build, _G.IsPlayerSpell, the proc feature and its
-- readers, Engine's storage) is handed back inside the file, and the last
-- test drains the bar.

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local M = FX.Cooldown.Module
local Display = FX.Cooldown.Display
local Locale = FX.Locale
local Procs = Engine.Procs

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

local function step(dt)
    local ok, err = pcall(A_Admin.AdvanceTime, dt)
    assertTrue(ok, "AdvanceTime raised: " .. tostring(err))
end

--- The real frame-script path (the frame is argument 1).
local function dispatch(event, ...)
    local f = M._eventFrame
    assertNotNil(f, "the event frame is bound at OnEnable")
    local h = f:GetScript("OnEvent")
    assertNotNil(h, "the frame carries its OnEvent script")
    local ok, err = pcall(h, f, event, ...)
    assertTrue(ok, "the real OnEvent script raised: " .. tostring(err))
end

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function countEntries()
    return countKeys(Engine.entries)
end

local function liveSlots()
    local n = 0
    for _ in pairs(Display._byName or {}) do n = n + 1 end
    return n
end

local function freshStorage()
    local storage = {}
    Engine:AttachStorage(storage)
    return storage
end

--- Sweep + pop + release the display slots, the 10 Hz ticker's own order.
local function drain()
    local now = GetTime()
    Engine:Sweep(now + 100000, {}, {})
    M:ProcessReadyPops(now + 100000)
    Display:Init()
    Display:Update(Engine:Sorted({}), now)
end

--- The facts a carried row owes: the window, its provenance and its
--- certification, the charge clock, the display tags and the row object.
local function chargesOf(e)
    local c = e.charges
    return c and (c.current .. "/" .. c.max .. "/" .. tostring(c.nextAt))
end

local function snapshotOf(e)
    return {
        start = e.start, duration = e.duration, endTime = e.endTime,
        source = e.source, predicted = e.predicted, anchored = e.anchored,
        charges = chargesOf(e), name = e.name, category = e.category,
        icon = e.icon, row = e.row,
    }
end

local function snapshotOfKeys(keys)
    local out = {}
    for _, key in ipairs(keys) do
        local e = Engine.entries[key]
        assertNotNil(e, "the rider is on the bar before the rebuild: " .. key)
        out[key] = snapshotOf(e)
    end
    return out
end

local function assertRode(key, before)
    local e = Engine.entries[key]
    assertNotNil(e, "the row rode the rebuild: " .. key)
    near(before.start, e.start)
    near(before.duration, e.duration)
    near(before.endTime, e.endTime)
    assertEquals(before.source, e.source, "the source stamp rode: " .. key)
    assertEquals(before.predicted, e.predicted)
    assertEquals(before.anchored, e.anchored)
    assertEquals(before.charges, chargesOf(e), "the charge clock rode: " .. key)
    assertEquals(before.name, e.name)
    assertEquals(before.category, e.category)
    assertEquals(before.icon, e.icon)
    assertTrue(e.row == before.row, "the display row object rode: " .. key)
    return e
end

local saved = {}
local taken = {}

--- A tracked spell of the class data with a base duration in [minS, maxS]
--- the run has not claimed yet.
local function pickRider(minS, maxS)
    for name, row in pairs(Engine.tracked) do
        local cd = row.baseDuration
        if cd and cd >= minS and cd <= maxS and not taken[name] then
            taken[name] = true
            return name, cd
        end
    end
    return nil
end

--- The same shape plus the client half the REAL cast path needs:
--- `C_Spell.GetSpellInfo(<data id>)` names the spell and the name
--- canonicalizes back onto the tracked data key (the RecordCastEvent
--- resolve), and the client resolves the data name to an id (the event's
--- spellID slot).
local function pickCastRider(minS, maxS)
    for name, row in pairs(Engine.tracked) do
        local cd = row.baseDuration
        if cd and cd >= minS and cd <= maxS and not taken[name] then
            local okD, infoD = pcall(C_Spell.GetSpellInfo, row.dataId)
            local nm = okD and infoD and infoD.name
            if type(nm) == "string" then
                nm = (Locale and Locale.CanonicalName(nm)) or nm
                if nm == name then
                    local okN, infoN = pcall(C_Spell.GetSpellInfo, name)
                    local clientId = okN and infoN and infoN.spellID
                    if type(clientId) == "number" then
                        taken[name] = true
                        return { name = name, id = clientId, cd = cd }
                    end
                end
            end
        end
    end
    return nil
end

--- A watched proc row that rides exactly ONE buff id, so a seen edge of that
--- id opens exactly one window and the counts below are exact.
local function pickProcRow()
    for key, row in pairs(Procs.tracked) do
        local rows = Procs.byBuff[row.buffId]
        if rows and #rows == 1 and not Engine.entries[key] then
            return key, row
        end
    end
    return nil
end

--- A bulk aura read that gives NO answer (the sealed-read half): the sweep
--- skips, so the seen model and the windows are untouched. An EMPTY answer is
--- not the inert reader -- the falling edge reads that as "no buffs up".
local function silentReaders()
    return { bulk = function() error("FXTEST: no sweep in this test") end }
end

--- The suite's spell-known seam (test_reconcile.lua's law): the leg's rebuild
--- must track every rider.
local function allKnownOn()
    saved.IPS = _G.IsPlayerSpell
    saved.IPSrc = FX.Compat.isPlayerSpellSource
    _G.IsPlayerSpell = function() return true end
end
local function allKnownOff()
    _G.IsPlayerSpell = saved.IPS
    FX.Compat.isPlayerSpellSource = saved.IPSrc
end

--- The module's chat voice (the unknown-class notice) is not this file's
--- subject: capture it so the legs read only the state. The last capture
--- stays readable as `saved.lastPrinted` for a leg that counts it.
local function captureChat()
    local lines = {}
    saved.printed = lines
    saved.lastPrinted = lines
    saved.realPrint = FX.Print
    FX.Print = function(msg) lines[#lines + 1] = tostring(msg) end
end
local function releaseChat()
    if saved.realPrint then FX.Print = saved.realPrint end
    saved.realPrint = nil
    saved.printed = nil
end

-- ------------------------------------------------------------------ gate ----
test("aa the carry gate: the clock rides, the data, the riders, the bar",
function()
    assertNotNil(M._eventFrame, "the module enabled at login")
    assertNotNil(FX._playerClass)
    saved.class = FX._playerClass
    saved.storage = Engine.learned
    saved.procsEnabled = Procs and Procs:IsEnabled()
    saved.procsReaders = Procs and Procs.readers
    saved.enabled = Display.frameState.enabled
    saved.hideCombat = Display.frameState.hideCombat
    saved.hideZero = Display.frameState.hideZero
    if Locale and Locale.stubLocale then
        assertNil(Locale.stubLocale,
            "no locale stub is left behind by an earlier file")
    end
    -- The module's readKey memo keys on the locale, and every rider here is
    -- the generated data's ENGLISH name: the enUS-client shape.
    if Locale then Locale.stubLocale = function() return "enUS" end end
    Display:SetEnabled(true)
    Display:SetHideCombat(false)
    Display:SetHideZero(false)
    Display:Init()

    -- The manual clock: the enable-once opt-in belongs to
    -- test_zz_combat_bar.lua, whose file runs ahead of this one.
    local t0 = GetTime()
    step(1.0)
    near(t0 + 1.0, GetTime())

    freshStorage()
    assertNotNil(Engine:Build(FX._playerClass, M.IsKnown),
        "the profile's class has generated data")
    drain()
    assertEquals(0, countEntries(), "the gate starts with an empty bar")

    local rider = pickCastRider(5, 900)
    assertNotNil(rider, "the profile resolves a tracked 5..900 s cast")
    castRider = rider
    secondRider = pickRider(20, 600)
    assertNotNil(secondRider, "the class data carries a second tracked spell")
    dropRider = pickRider(20, 600)
    assertNotNil(dropRider, "the class data carries a third tracked spell")
    assertTrue(castRider.name ~= secondRider and secondRider ~= dropRider
        and castRider.name ~= dropRider, "three distinct riders")
end)

-- ----------------------------------------------------------------- the ride --
--- The bug, at the shape the finding named: three spells are running, a
--- SPELLS_CHANGED burst lands on the module's real event frame, the 0.5 s
--- debounce fires the rebuild -- and the rows ride the bar through it, with
--- their own remaining time, while the spell that left the tracked set falls
--- off the bar.
test("a SPELLS_CHANGED rebuild through the real event frame rides the bar",
function()
    drain()
    -- The combat ENTER edge fires SPELLS_CHANGED (I2f measured): settle its
    -- storm BEFORE the rows open, so this test measures only the burst it
    -- injects itself.
    A_Admin.SetInCombat(true)
    step(0.75)
    drain()
    assertEquals(0, countEntries(), "the rows open on settled state")

    allKnownOn()
    -- Rider 1: the real cast path (the 4-slot payload through the frame ->
    -- RecordCastEvent -> Engine:OnCast).
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Fx7a-1",
        castRider.id, 11)
    assertNotNil(Engine.entries[castRider.name],
        "the injected cast opened the tracked window")
    -- Riders 2 and 3: the Engine's own cast feed, the exact state a resolved
    -- cast leaves (the sim's profile knows one cast -- I2f measured).
    assertNotNil(Engine:OnCast(secondRider, GetTime()),
        "the engine feed opened the second window")
    assertNotNil(Engine:OnCast(dropRider, GetTime()),
        "the engine feed opened the third window")

    -- The bar binds all three on the module's real 10 Hz ticker.
    step(0.2)
    assertEquals(3, countEntries(), "three windows are running")
    assertEquals(3, liveSlots(), "the bar shows all three")

    local keys = { castRider.name, secondRider, dropRider }
    local before = snapshotOfKeys(keys)
    local tStorm = GetTime()

    -- The burst: three events, ONE debounced rebuild. Half-way through it
    -- the third spell leaves the tracked set -- the shape of a talent/spec
    -- swap: the fresh build no longer tracks that name.
    dispatch("SPELLS_CHANGED")
    dispatch("SPELLS_CHANGED")
    local realBuild = Engine.Build
    Engine.Build = function(self, ...)
        local n, reason = realBuild(self, ...)
        self.tracked[dropRider] = nil
        return n, reason
    end
    dispatch("SPELLS_CHANGED")
    step(0.75)                                  -- the 0.5 s debounce lands
    Engine.Build = realBuild

    local now = GetTime()
    assertTrue(now > tStorm, "the real clock ran past the debounce")
    for _, key in ipairs(keys) do
        local b = before[key]
        if key == dropRider then
            assertNil(Engine.entries[key],
                "a name the fresh build no longer tracks is dropped: " .. key)
        else
            local e = assertRode(key, b)
            assertTrue(e.endTime > now,
                "the row is still counting down, not re-armed at the rebuild")
            local was = b.endTime - tStorm
            local is = e.endTime - now
            assertTrue(is <= was + 1e-6 and is >= was - 1.0,
                "the remaining time is the row's own countdown (" .. key
                .. ": " .. tostring(was) .. " -> " .. tostring(is) .. ")")
        end
    end
    assertEquals(2, countEntries(), "only the untracked row left the bar")

    -- The ride is a carry, not a re-entry: no cast event and no read named
    -- these spells again (the sim's name-keyed reads are blind -- I2f), and
    -- the rows kept their `cast` provenance and their prediction.
    assertEquals("cast", Engine.entries[castRider.name].source)
    assertTrue(Engine.entries[castRider.name].predicted)
    step(0.2)
    assertEquals(2, liveSlots(), "the bar keeps the two rows it carried")

    allKnownOff()
    A_Admin.SetInCombat(false)
    step(0.75)
    drain()
    assertEquals(0, countEntries(), "the leg leaves no row")
end)

-- -------------------------------------------------- the class-change half --
--- A class change is a fresh question -- the tracked set is a different
--- class's data, so nothing of the old bar carries over: it starts clean.
test("a class change starts the bar clean", function()
    drain()
    allKnownOn()
    assertNotNil(Engine:OnCast(castRider.name, GetTime()))
    assertNotNil(Engine:OnCast(secondRider, GetTime()))
    step(0.1)
    assertEquals(2, countEntries(), "two windows are running")

    captureChat()
    dispatch("SPELLS_CHANGED")
    FX._playerClass = "DEATHKNIGHT"                 -- no generated data
    step(0.75)
    FX._playerClass = saved.class
    releaseChat()
    allKnownOff()
    assertEquals(0, countEntries(),
        "the class change starts the bar clean")
    assertTrue(#(saved.lastPrinted or {}) <= 1,
        "the unknown-class notice speaks at most once")

    -- The clean start is the CLASS CHANGE, not the empty data set: the class
    -- riding back into a same-class rebuild is the same question, and a
    -- running row of it rides.
    M:Rebuild()
    assertEquals(0, countEntries(), "the class is back and the bar is empty")
    assertNotNil(Engine:OnCast(castRider.name, GetTime()))
    step(0.1)
    assertEquals(1, countEntries(), "a row is open on the settled class")
    M:Rebuild()
    assertEquals(1, countEntries(),
        "a same-class rebuild carries the row of the class that rode back")
    drain()
end)

-- ---------------------------------------------------------- the proc half --
--- The proc tracker's ICD windows ride the same rule (the Module's rebuild
--- comment used to say the Build took them, so the `seen` model had to go
--- with them). The stamp of a window that rode rides WITH it: the ICD is
--- clock-driven and `seen` is the record of the aura that armed it -- so a
--- rebuild must not re-arm the edge of a window that is still running.
test("a proc ICD window rides the rebuild and its seen stamp rides with it",
function()
    drain()
    Procs.readers = silentReaders()
    local n = Procs:SetEnabled(true)
    assertTrue(type(n) == "number" and n > 0,
        "the proc data carries watched rows (n=" .. tostring(n) .. ")")
    local key, row = pickProcRow()
    assertNotNil(key, "a watched proc row that rides one buff id")
    wipe(Procs.seen)
    Engine.entries[key] = nil

    -- The seen edge, through the module's real UNIT_AURA leg.
    local at = GetTime()
    dispatch("UNIT_AURA", "player",
        { addedAuras = { { spellId = row.buffId } } })
    local e = Engine.entries[key]
    assertNotNil(e, "the proc aura armed the ICD window")
    assertEquals("proc", e.source)
    local seenStamp = Procs.seen[row.buffId]
    assertNotNil(seenStamp, "the seen model carries the id")
    near(at, seenStamp)
    local before = snapshotOf(e)
    local added0, edges0 = Procs.counts.added, Procs.counts.edges

    -- The debounced rebuild's own call, on an unchanged class: the window is
    -- the same question it was.
    captureChat()
    M:Rebuild()
    releaseChat()
    local after = assertRode(key, before)
    assertTrue(after.endTime > GetTime(), "the window is still running")
    local seenAfter = Procs.seen[row.buffId]
    assertNotNil(seenAfter, "the stamp of a riding window rides with it")
    near(seenStamp, seenAfter)

    -- And the stamp is load-bearing: the SAME aura event again is no new
    -- edge, so no second window opens for a proc whose ICD is running.
    dispatch("UNIT_AURA", "player",
        { addedAuras = { { spellId = row.buffId } } })
    assertEquals(added0, Procs.counts.added,
        "a riding window is not re-enlisted by the same aura")
    assertEquals(edges0, Procs.counts.edges, "and it is no new edge")
    local live = 0
    for watchKey in pairs(Procs.tracked) do
        if Engine.entries[watchKey] then live = live + 1 end
    end
    assertEquals(1, live, "still exactly one window for that proc")

    -- The class change takes the windows -- and every stamp with them. The
    -- picked row's own class filter is not this leg's subject, so the class
    -- rides back first and the fresh question is read on the class that owns
    -- the row: the stamp is gone, so the aura is an edge and arms a window.
    captureChat()
    FX._playerClass = "DEATHKNIGHT"
    M:Rebuild()
    FX._playerClass = saved.class
    M:Rebuild()
    releaseChat()
    assertNil(Engine.entries[key], "the class change took the window")
    assertNil(Procs.seen[row.buffId], "and the stamp went with the window")
    local edges1 = Procs.counts.edges
    dispatch("UNIT_AURA", "player",
        { addedAuras = { { spellId = row.buffId } } })
    assertEquals(edges1 + 1, Procs.counts.edges, "the aura is a fresh edge")
    assertNotNil(Engine.entries[key], "and it arms a fresh window")

    Engine.entries[key] = nil
    wipe(Procs.seen)
    Procs:SetEnabled(false)
    Procs.readers = nil
    M:Rebuild()
    assertEquals(0, countEntries(), "the proc feature left the bar clean")
end)

-- --------------------------------------------------------- the re-enlist --
--- The carry is a carry, not a re-entry: a window that rode is never
--- re-opened by a plain read of the aura that armed it. The old law had the
--- sweep re-enlist the window after every rebuild -- on the live client that
--- restarts the ICD bar from the read every time a rebuild storm lands.
test("a plain aura sweep never re-enlists a window that rode the rebuild",
function()
    drain()
    assertFalse(InCombatLockdown(), "the sweep is the out-of-combat half")
    local n = Procs:SetEnabled(true)
    assertTrue(type(n) == "number" and n > 0, "the watched set is built")
    local key, row = pickProcRow()
    assertNotNil(key, "a watched proc row that rides one buff id")
    Engine.entries[key] = nil
    wipe(Procs.seen)

    Procs.readers = { bulk = function() return { { spellId = row.buffId } } end }
    local at = GetTime()
    assertEquals(1, Procs:Scan(at, Procs.readers), "the sweep armed the window")
    local added0 = Procs.counts.added
    local before = snapshotOf(Engine.entries[key])

    captureChat()
    M:Rebuild()
    releaseChat()
    assertRode(key, before)

    -- The same aura list, one sweep later: the id is (model-wise) still up,
    -- so there is no edge and the riding window is not touched.
    local later = at + 3
    assertEquals(0, Procs:Scan(later, Procs.readers),
        "the sweep saw no new edge for a window that rode")
    assertEquals(added0, Procs.counts.added, "and created no window")
    local after = Engine.entries[key]
    near(before.start, after.start)
    near(before.endTime, after.endTime)
    assertNotNil(Procs.seen[row.buffId], "the stamp of the window is kept")
    near(at, Procs.seen[row.buffId])

    -- The falling edge: the aura leaves the list, the stamp goes, so the
    -- next proc of that aura is an edge again.
    Procs.readers = { bulk = function() return {} end }
    Procs:Scan(later + 1, Procs.readers)
    assertNil(Procs.seen[row.buffId], "the falling edge cleared the stamp")

    Engine.entries[key] = nil
    wipe(Procs.seen)
    Procs:SetEnabled(false)
    Procs.readers = nil
    M:Rebuild()
    assertEquals(0, countEntries(), "the bar is left clean")
end)

-- -------------------------------------------------------------- teardown --
test("zzz the carry suite leaves the module state as it found it", function()
    drain()
    A_Admin.SetInCombat(false)
    releaseChat()
    allKnownOff()
    Procs:SetEnabled(saved.procsEnabled and true or false)
    Procs.readers = saved.procsReaders
    for key in pairs(Procs.tracked) do Engine.entries[key] = nil end
    wipe(Procs.seen)
    FX._playerClass = saved.class
    if Locale then Locale.stubLocale = nil end
    if saved.storage then Engine:AttachStorage(saved.storage) end
    Display:SetEnabled(saved.enabled)
    Display:SetHideCombat(saved.hideCombat)
    Display:SetHideZero(saved.hideZero)
    Display:Init()
    Engine:Build(FX._playerClass, M.IsKnown)
    M:ReadAll()
    assertEquals(0, countEntries(), "no row survives this file")
    assertEquals(0, liveSlots())
    assertEquals(saved.class, FX._playerClass)
end)
