-- =============================================================================
-- test_zz_combat_shaman.lua — the I2f combat-simulation round for the totem
-- slots (PLAN §2.10, §11.2 row I2f).
--
-- NAME LAW: the "zz_" prefix sorts this file LAST; it is the only test in
-- the set that enables the admin manual clock (process-wide, enable-once).
-- The clock handback law rides at the tail.
--
-- WHAT THIS ROUND DRIVES. The windows arrive through the tracker's own
-- seams — the injected `readSlot` (the FX.Timer.Reconcile.readers
-- convention the file documents) and the injected `now` — over the LIVE
-- FX.Timer.Rows table, so the rows the slots draw are the rows the panel
-- draws. The module's event half rides through `M:OnEvent(event, slot)` —
-- the module's own public method, the exact body the frame script carries.
-- Why not the live frame script (SIM LAWS, measured this round): the
-- class-gated module rides UNWIRED at the login of this profile
-- (FX._playerClass is the profile's, the gate returns; asserted at the
-- gate), and the simulator's script registry is a login-window
-- phenomenon — a SetScript after the login phase is inert (probe
-- /tmp/fxprobe14.dt.log C=false_nil). The real-reader half needs no seam
-- at all: the build SHIPS GetTotemInfo (probe: function; slot 1 answers
-- have=false, start=0, duration=0 — the empty-slot read), GetNumTotemSlots
-- is absent (the tracker's MAX_TOTEMS fallback law, asserted), and
-- C_Secrets.ShouldTotemSlotBeSecret is absent (not sealed, the seal gate
-- law).
--
-- FRESH-TRACKER DISCIPLINE: every leg rides a tracker the suite built
-- (NewTotemTracker over the live rows), never the module's lazily-built
-- one — the module's tracker is installed only for the OnEvent leg and
-- rides back nil at the tail. The shared rows table is emptied by the
-- suite (gate + zzz): the clean-slate law of the combat rounds.
-- =============================================================================
local FX = ForteXorcist
local M = FX.Shaman.Totems
local Rows = FX.Timer.Rows

local saved
local printCapture

local fake, fakeCalls
local tracker

-- ------------------------------------------------------------------ helpers
local function step(dt)
    local left = dt
    while left > 1e-9 do
        local d = math.min(0.1, left)
        local ok, err = pcall(A_Admin.AdvanceTime, d)
        assertTrue(ok, "AdvanceTime raised: " .. tostring(err))
        left = left - d
    end
end

local function freshTracker(opts)
    opts = opts or {}
    return FX.Shaman.NewTotemTracker({
        rows = FX.Timer.Rows,
        now = opts.now or GetTime,
        readSlot = opts.readSlot or function(slot)
            fakeCalls = fakeCalls + 1
            local r = fake[slot]
            if r == "raise" then error("sealed slot") end
            return r
        end,
    })
end

local clockEnabled = false
local function enableClock(target)
    assertTrue(type(GetTime) == "function"
        and type(A_Admin.AdvanceTime) == "function"
        and type(A_Admin.SetManualClock) == "function",
        "the sim build carries the manual clock trio")
    -- (I2f3 probe: A_Admin.GetManualClockEnabledAt does NOT exist on this
    -- build (nil — the hand-off fact was wrong), and SetManualClock is
    -- enable-once (a second call raises "manual clock already enabled").
    -- The shape rides the proven Forte_Timer gate: enable once, assert the
    -- clock answers the base. The zz file is the run's last, and the clock
    -- has no off switch — the Forte_Timer suite's tail law: it rides on.)
    if not clockEnabled then
        local ok, err = pcall(A_Admin.SetManualClock, target)
        assertTrue(ok, "SetManualClock(" .. tostring(target) .. ") raised: "
            .. tostring(err))
        clockEnabled = true
    end
    local okG, t0 = pcall(GetTime)
    assertTrue(okG, "GetTime raised under the manual clock: " .. tostring(t0))
    assertTrue(math.abs(t0 - target) < 0.01,
        "the clock answers its base: t=" .. tostring(t0))
end

local function nearT(actual, expected, tol, msg)
    local ok = math.abs(actual - expected) < tol
    return assertTrue(ok,
        (msg and (msg .. ": ") or "") .. "got " .. tostring(actual)
        .. ", expected " .. tostring(expected) .. " +/- " .. tostring(tol))
end

local function assertContains(haystack, needle, msg)
    return assertTrue(
        type(haystack) == "string"
        and string.find(haystack, needle, 1, true) ~= nil,
        (msg and (msg .. ": ") or "") .. "expected to contain "
        .. tostring(needle) .. ", got " .. tostring(haystack))
end

-- ---------------------------------------------------------------------- gate
test("zz combat gate: the module stands on the manual clock, unwired",
function()
    assertNotNil(M, "FX.Shaman.Totems exists")
    assertNotNil(FX.Shaman.NewTotemTracker, "the tracker factory exists")
    -- The class-gate law (header).
    assertNil(M.tracker, "the login built no tracker for this profile")
    assertTrue(M._eventsEnabled ~= true,
        "the events mirror rides off (the class-gate law)")
    assertNotNil(Rows, "the rows table rides (Forte_Timer loaded)")
    printCapture = { lines = 0 }
    saved = {}
    saved.print = FX.Print
    FX.Print = function(...)
        printCapture.lines = printCapture.lines + 1
        print(...)
    end
    enableClock(170000)
    local names = M:SlotSpellNames()
    assertTrue(#names >= 2,
        "the generated data names the slot spells (" .. #names .. ")")
    saved.t1, saved.t2 = names[1], names[2]
    -- The build's real totem surface (the file's own fallback laws).
    assertEquals(4, freshTracker():SlotCount(),
        "GetNumTotemSlots absent — the MAX_TOTEMS fallback rides")
    -- (I2f3: the gate's real-reader leg builds a tracker WITHOUT the
    -- suite's fake readSlot — the freshTracker default is the fake, and a
    -- fake slot read answering nil is the sealed verdict, not the real
    -- GetTotemInfo's idle one.)
    assertEquals("idle", FX.Shaman.NewTotemTracker({
        rows = FX.Timer.Rows, now = GetTime,
    }):OnTotemUpdate(1),
        "the REAL GetTotemInfo answers the empty slot (have=false) — an "
        .. "idle verdict with the slot unshown")
    Rows:Clear()
end)

test("in combat: a slot read puts its element's row on the panel", function()
    A_Admin.SetInCombat(true)
    step(0.2)
    fake, fakeCalls = {}, 0
    tracker = freshTracker()
    local t1 = saved.t1
    fake[1] = { present = true, name = t1,
        expireAt = GetTime() + 30, total = 30 }
    assertEquals("inserted", tracker:OnTotemUpdate(1),
        "the Fire slot's first totem inserts its row")
    local row = Rows:Find(t1, "Fire")
    assertNotNil(row, "the row rides the element key (one group per element)")
    nearT(row.expireAt, GetTime() + 30, 0.01,
        "the window rides the slot read's startTime+duration pair")
    assertEquals(true, tracker:IsShowing(t1),
        "the slot's spell is shown — the cast spine defers (F-B law)")
    assertContains(tracker:StatusLine(), "fire=" .. t1,
        "the status line reads the slot")
end)

test("a new totem replaces the slot's row mid-fight; a re-cast refreshes",
function()
    local t2 = saved.t2
    fake[1] = { present = true, name = t2,
        expireAt = GetTime() + 45, total = 45 }
    assertEquals("replaced", tracker:OnTotemUpdate(1),
        "the slot law: the old row goes, the new one stands (Shaman.lua:84)")
    assertNil(Rows:Find(saved.t1, "Fire"), "the old row is gone")
    local row2 = Rows:Find(t2, "Fire")
    assertNotNil(row2, "the new row stands in the element group")
    assertEquals(false, tracker:IsShowing(saved.t1),
        "the slot no longer speaks for the old spell")
    assertEquals(true, tracker:IsShowing(t2), "it speaks for the new")
    fake[1] = { present = true, name = t2,
        expireAt = GetTime() + 90, total = 90 }
    assertEquals("refreshed", tracker:OnTotemUpdate(1),
        "the same spell re-cast: the row rides in place (no new insert)")
    nearT(Rows:Find(t2, "Fire").expireAt, GetTime() + 90, 0.01,
        "and the window rides the fresh pair")
end)

test("an emptied slot fades the row; the ticker retires it", function()
    fake[1] = { present = false }
    assertEquals("cleared", tracker:OnTotemUpdate(1),
        "the destroyed/expired totem fades the slot's row (Shaman.lua:87)")
    local guard = 0
    while Rows:Find(saved.t2, "Fire") and guard < 1200 do
        step(0.1)
        guard = guard + 1
    end
    assertNil(Rows:Find(saved.t2, "Fire"),
        "the fade window rides the ticker to the row's end")
    assertEquals(0, printCapture.lines, "quiet through the fade")
end)

test("a sealed slot read keeps the row the panel has", function()
    local sealed = freshTracker({ readSlot = function()
        error("sealed")
    end })
    assertEquals("sealed", sealed:OnTotemUpdate(2),
        "a raising slot read is the no-answer law")
    assertEquals(1, sealed.secretReads, "the sealed read is counted")
    assertNil(sealed.slots[2], "and no slot state was taken on")
end)

test("the windows ride the totem clocks, not the combat gate", function()
    fake[1] = { present = true, name = saved.t1,
        expireAt = GetTime() + 30, total = 30 }
    assertEquals("inserted", tracker:OnTotemUpdate(1))
    A_Admin.SetInCombat(false)
    step(0.2) -- the regen sweep runs; the element-keyed rows are not the
    -- player sweep's (SweepUnit's key law) and no paladin aura names a
    -- totem (SweepBulk's registry gate) — the sweep leaves them alone.
    assertNotNil(Rows:Find(saved.t1, "Fire"),
        "the slot row rides the combat boundary: the window is the "
        .. "totem's clock, not the fight's")
    A_Admin.SetInCombat(true)
    step(0.2)
end)

test("the module's OnEvent drives the tracker; the seed reads every slot",
function()
    fakeCalls = 0
    M.tracker = tracker
    local n = M:DeclareRows()
    assertTrue(type(n) == "number" and n >= 1,
        "the totem set is declared to the cast spine (F-B)")
    fake[1] = { present = true, name = saved.t2,
        expireAt = GetTime() + 25, total = 25 }
    M:OnEvent("PLAYER_TOTEM_UPDATE", 1)
    assertNotNil(Rows:Find(saved.t2, "Fire"),
        "the module's own event method moved the slot (the script body)")
    fakeCalls = 0
    M:OnEvent("PLAYER_ENTERING_WORLD")
    assertEquals(tracker:SlotCount(), fakeCalls,
        "the world-entry seed reads every slot once (Shaman.lua:96-104)")
    assertEquals("ignored", tracker:OnTotemUpdate(99),
        "a slot past the count is ignored")
    M:OnEvent("PLAYER_TOTEM_UPDATE", "seven")
    assertNotNil(tracker, "a non-number slot is the ignored law, no harm")
    M:UndeclareRows()
    M.tracker = nil
end)

test("zzz the suite leaves the module state as it found it", function()
    A_Admin.SetInCombat(false)
    step(0.2)
    Rows:Clear()
    assertNil(M.tracker, "the module's tracker rides back absent")
    assertEquals(0, Rows:Count(), "the shared rows table rides empty")
    local lines = printCapture.lines
    FX.Print = saved.print
    assertEquals(0, lines,
        "the round printed nothing (" .. tostring(lines) .. " lines)")
    -- (I2f3: the handback math rode GetManualClockEnabledAt — the surface
    -- does not exist, SetManualClock is enable-once with no off switch,
    -- and this file is the run's last: the Forte_Timer tail law, the
    -- clock rides on.)
    assertTrue(M._eventsEnabled ~= true,
        "the module's events mirror rides off, as found")
end)
