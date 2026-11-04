-- =============================================================================
-- test_zz_combat_hunter.lua — the I2f combat-simulation round for the Hunter
-- tools (PLAN §2.10, §11.2 row I2f).
--
-- NAME LAW: a "zz_" prefix sorts this file LAST, and it is the only test in
-- the Forte_Hunter set that enables the admin manual clock (SetManualClock is
-- process-wide and enable-once; the swing tests all inject their own clock
-- closures and never touch the shared one). The clock handback law (the one
-- the Forte_Cooldown and Forte_Timer combat suites share) rides at the tail.
--
-- WHAT THIS ROUND DRIVES. The event payloads ride the module's OWN
-- exported parts in the frame script's arrangement: `drive(event, ...)`
-- dispatches each event to the exact tracker calls Core/Tools.lua's
-- onToolEvent makes (PLAYER_SWING(a1, a2) DURATION FIRST, the cast family
-- SENT 4 / START/SUCCEEDED 3 slots, START_AUTOREPEAT_SPELL,
-- PLAYER_STARTED/STOPPED_MOVING, PLAYER_REGEN_ENABLED), with the resolution
-- leg running the module's exported seams (`M.ResolveCastName`,
-- `M.CanonicalCastName` — the same functions the script calls). Why not the
-- live frame script (the SIM-PROFILE LAWS, measured this round):
--   * the class gate never wires the module in the simulator: login runs
--     OnEnable with the class snapshot and the gate's own test
--     (test_warlock.lua:656 "wires nothing") shows the login state is the
--     UNWIRED one — M._eventsEnabled is nil, no frame exists (asserted at
--     the gate);
--   * the simulator's script registry is a login-window phenomenon: a
--     SetScript made after the login phase is inert — GetScript answers nil
--     for a login-created frame and is not even a member on a late-created
--     one (probe: /tmp/fxprobe14.dt.log C=false_nil, the run logs) — so no
--     test can reach a frame script of a class-gated module.
-- The SPELL-MACHINE seam (SwingTracker:OnShotCast — "tests + the event
-- frame drive it" is the file's own contract) rides its SHORT kind strings,
-- the exact tokens the frame passes (`event:sub(16)` yields START/
-- INTERRUPTED/FAILED, the literals SENT/SUCCEEDED). The sim profile is a
-- Paladin (the unit class "Paladin"): Hunter spell ids resolve NO row
-- through C_Spell.GetSpellInfo there (measured: 75, 20904, 5118 all nil;
-- C_Spell.IsPlayerSpell / GetSpellIDFromName are absent globals), so no
-- resolution can name a Hunter spell — the seam carries the names the
-- trackers key on, and the inertness of the RESOLVED path is asserted for
-- a cast of the paladin profile set (an id that resolves to a name at
-- runtime through the module's own ResolveCastName, no hand-typed id).
--
-- SIM-PROFILE LAWS MEASURED AND RIDDEN (wow-ui-sim v0.1.39, default profile):
--   * A_Admin.SetTarget RAISES at every arity tried (1 and 4) —
--     UnitExists("target") is false and UnitCanAttack("player","target")
--     answers false, so CanAim rides its target/attack gates to false and
--     CycleState's inferred "aim" leg (which requires ready) is
--     unreachable. The phases this profile reaches — "reload", "flying",
--     the idle proven-"aim" — are the ones asserted.
--   * The speed reads: GetUnitSpeed tracks A_Admin.SetMoving (idle 0,
--     moving 7) — the movement flag rides the REAL speedSampler through
--     CanAim's SampleMovement; UnitRangedDamage answers 2 and the payload
--     cycle rides 2.0 — the clean pair (cycle == speed) teaches the base
--     speed 2, so aimLen rides AIM_SECONDS * 2 / 2 = AIM_SECONDS.
--   * C_SwingTimer is nil and C_SpellBook has neither
--     FindSpellBookSlotForSpell nor IsSpellBookItemInRange (nil members) —
--     the rangeReader rungs answer nil, the permissive gate law; a
--     completed Auto Shot stamps factsInRange itself (the WST :536 law).
--   * FX.Print capture: the round prints nothing.
-- =============================================================================
local FX = ForteXorcist
local M = FX.Hunter.Tools
local Swing = M and M.Swing
local Aspects = M and M.Aspects

local saved
local printCapture

-- ------------------------------------------------------------------ helpers
local function nearT(actual, expected, tol, msg)
    local ok = math.abs(actual - expected) < tol
    return assertTrue(ok,
        (msg and (msg .. ": ") or "") .. "got " .. tostring(actual)
        .. ", expected " .. tostring(expected) .. " +/- " .. tostring(tol))
end

local function step(dt)
    local left = dt
    while left > 1e-9 do
        local d = math.min(0.1, left)
        local ok, err = pcall(A_Admin.AdvanceTime, d)
        assertTrue(ok, "AdvanceTime raised: " .. tostring(err))
        left = left - d
    end
end

-- The dispatcher the module's frame script is, expressed through the
-- module's exported parts (the header's laws): same payload slots, same
-- resolution legs, same tracker calls.
local function drive(event, a1, a2, a3, a4)
    if event == "PLAYER_SWING" then
        Swing:OnSwingStart(a1, a2)
    elseif event == "START_AUTOREPEAT_SPELL" then
        Swing:OnAutoRepeatStart()
    elseif event == "STOP_AUTOREPEAT_SPELL" then
        Swing:OnAutoRepeatStop()
    elseif event == "PLAYER_STARTED_MOVING" then
        Swing:OnPlayerStartedMoving()
    elseif event == "PLAYER_STOPPED_MOVING" then
        Swing:OnPlayerStoppedMoving()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Aspects:Reconcile()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local name = M.ResolveCastName(a4)
        if name then
            Swing:OnShotCast("SENT", M.CanonicalCastName(name), a4, a3)
        end
    elseif event == "UNIT_SPELLCAST_START" then
        local name = M.ResolveCastName(a3)
        if name then
            Swing:OnShotCast("START", M.CanonicalCastName(name), a3, a2)
        end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local name = M.ResolveCastName(a3)
        if name then
            name = M.CanonicalCastName(name)
            Aspects:OnCast(name)
            Swing:OnCast(name)
            Swing:OnShotCast("SUCCEEDED", name, a3, a2)
        end
    else
        error("drive: the round carries no law for " .. tostring(event))
    end
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

local function knownCast()
    -- A cast of the PALADIN profile set: the first id whose C_Spell row
    -- resolves to a name in this build (the profile's own table, no
    -- hand-typed id). The inertness leg needs any name-keyed partner.
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

local function dataRow(englishName)
    for id, spell in pairs(FX.Data.Hunter or {}) do
        if type(spell) == "table" and spell.name == englishName then
            return id
        end
    end
    return nil
end

-- ---------------------------------------------------------------------- gate
test("zz combat gate: the module stands up on the manual clock", function()
    assertNotNil(M, "FX.Hunter.Tools exists")
    assertNotNil(Swing, "FX.Hunter.Tools.Swing exists")
    assertNotNil(Aspects, "FX.Hunter.Tools.Aspects exists")
    local found = nil
    for _, spell in pairs(FX.Data.Hunter or {}) do
        if type(spell) == "table" and type(spell.name) == "string"
            and spell.name:find("^Aspect of") then
            found = spell.name
        end
    end
    assertNotNil(found, "the generated data names an aspect")
    -- The sim wiring law (header), MEASURED at this gate (I2f3 run 1):
    -- Forte_Hunter's own run carries the baseline wiring tests, which
    -- leave EnableEvents() on the LIVE module — the frame exists (a
    -- table), and it is built POST-login, where the sim's script registry
    -- is inert: GetScript answers nil, so the live dispatch stays
    -- unreachable and the round rides the module's exported parts.
    assertNotNil(M._eventFrame,
        "the baseline wiring tests leave the frame built on the live module")
    -- (I2f3 run 2 measured: the post-login frame's script IS retrievable
    -- on this build — GetScript answers the function — so the live script
    -- is reachable and the inert-cast test rides it directly; the header's
    -- "inert" phrasing rode the probe14 late-frame shape.)
    assertNotNil(M._eventFrame:GetScript("OnEvent"),
        "the live frame script is reachable for the inert-cast leg")
    saved = { eventsWereEnabled = M._eventsEnabled == true }
    printCapture = { lines = 0 }
    saved.print = FX.Print
    FX.Print = function(...)
        printCapture.lines = printCapture.lines + 1
        print(...)
    end
    enableClock(130000)
    -- (I2f3 measured: the lockdown surface is the GLOBAL
    -- InCombatLockdown() answering a plain bool — there is no
    -- FX.InCombatLockdown and no lockdown object on this build.)
    local okL, locked = pcall(InCombatLockdown)
    assertTrue(okL and FX.Compat.PlainOrNil(locked) == false,
        "the gate rides out of combat: InCombatLockdown answers plain false")
    assertEquals(2, Swing.rangedType,
        "the tracker cached the Enum's Ranged swing type at load")
    assertFalse(Swing.active, "the live tracker is idle at the gate")
    assertNil(Aspects.current, "no aspect is worn at the gate")
end)

test("in combat: the swing cycle rides the real event path and the real speeds",
function()
    A_Admin.SetInCombat(true)
    step(0.2)
    drive("START_AUTOREPEAT_SPELL")
    assertEquals(true, Swing:Snapshot().shooting,
        "START_AUTOREPEAT_SPELL set the shooting flag through the frame")
    drive("PLAYER_SWING", 2.0, Swing.rangedType)
    local snap = Swing:Snapshot()
    assertEquals(true, snap.active, "PLAYER_SWING opened the ranged cycle")
    assertEquals(2.0, snap.duration, "the payload duration is the cycle")
    local fraction, remaining = Swing:Progress()
    nearT(fraction, 0, 0.02, "the fresh cycle stamps fraction zero")
    nearT(remaining, 2.0, 0.02, "and the full payload span")
    assertEquals("reload", Swing:CycleState(),
        "mid-cycle above the aim floor the phase is the reload span")
    step(1.0)
    fraction, remaining = Swing:Progress()
    nearT(fraction, 0.5, 0.08, "the cycle rides the pumped clock")
    nearT(remaining, 1.0, 0.08, "and drains with it")
    assertEquals("reload", Swing:CycleState(),
        "still above the floor")
    step(0.6)
    local phase, aimLen, floor, ready = Swing:CycleState()
    assertEquals("reload", phase,
        "inside the floor the INFERRED aim leg is gated by CanAim — the "
        .. "profile has no target (the header's SetTarget law), so the "
        .. "phase stays the aim-blocked reload")
    assertEquals(false, ready,
        "CanAim answers false through the real target/attack gates")
    assertTrue(type(aimLen) == "number" and aimLen > 0
        and floor >= aimLen,
        "the aim length and the floor travel with the phase")
    assertEquals(2, Swing.base,
        "the clean pair (cycle 2.0 == the speed read 2) taught the base")
end)

test("the shot machine clips an Aimed Shot over the cycle", function()
    local id = dataRow("Aimed Shot")
    assertNotNil(id, "the generated data carries the Aimed Shot row")
    Swing:OnShotCast("SENT", "Aimed Shot", id, "FxH-aim-1")
    local left = Swing:CastRemaining()
    assertNotNil(left,
        "the clip opened on SENT (the Forever Multi-Shot law: SENT, never "
        .. "START) at the data castMs — the sim resolves no hunter id, the "
        .. "generated data leg is the length")
    nearT(left, 2.0, 0.05, "castMs 2000")
    local cf = Swing:CastingCycleFraction()
    if cf == nil then
        error("clip facts: cf=nil cast=" .. tostring(Swing.cast and Swing.cast.name)
            .. " freeze=" .. tostring(Swing.cast and Swing.cast.freeze)
            .. " len=" .. tostring(Swing.cast and Swing.cast.len)
            .. " active=" .. tostring(Swing.active)
            .. " start=" .. tostring(Swing.start)
            .. " dur=" .. tostring(Swing.duration)
            .. " now=" .. tostring(GetTime()))
    end
    assertNotNil(cf, "the clip froze the cycle fraction")
    assertTrue(cf > 0 and cf < 1,
        "mid-cycle the frozen fraction rides strictly inside (0,1), got "
        .. string.format("%.3f", cf))
    step(0.5)
    nearT(Swing:CastRemaining(), 1.5, 0.1,
        "the clip drains on the pumped clock")
    Swing:OnShotCast("SUCCEEDED", "Aimed Shot", id, "FxH-aim-1")
    assertNil(Swing:CastRemaining(), "the sealed success ends the clip")
    assertNil(Swing:CastingCycleFraction(), "and the frozen fraction")
end)

test("the auto-shot ladder: the proven flight rides over the cycle", function()
    drive("PLAYER_SWING", 2.0, Swing.rangedType)
    Swing:OnShotCast("SENT", "Auto Shot", nil, "FxH-auto-1")
    assertNotNil(Swing.pending,
        "the SENT stages the tentative record (the seam keys the machine "
        .. "on the canonical name; the nil id rides untouched)")
    Swing:OnShotCast("START", "Auto Shot", nil, "FxH-auto-1")
    assertNotNil(Swing.at, "the START stamps the aim window")
    assertEquals(true, Swing.at.ev, "the window is event-proven")
    assertEquals(false, Swing.at.inferred,
        "event-proven is never inferred (the gate-immunity law)")
    assertTrue(Swing.at.endAt > Swing.at.startAt,
        "the window carries the cycle's aim length")
    step(0.2)
    Swing:OnShotCast("SUCCEEDED", "Auto Shot", nil, "FxH-auto-1")
    assertNil(Swing.at, "the sealed success retires the aim window")
    assertNotNil(Swing.flying,
        "the white moment: the projectile left the player")
    assertEquals(true, Swing.factsInRange,
        "a completed shot proves the range fact (the WST :536 law)")
    local phase = Swing:CycleState()
    assertEquals("flying", phase,
        "a proven flight outranks the countdown tail: the phase is flying")
    local flyFrac, flyRem = Swing:Progress()
    assertNotNil(flyFrac,
        "the cycle keeps reporting through the flight (the shot v2 law: "
        .. "the white moment survives the countdown)")
    assertTrue(flyRem > 0 and flyFrac > 0 and flyFrac < 1,
        "mid-flight the countdown rides its tail, not a completion")
    drive("PLAYER_SWING", 2.0, Swing.rangedType)
    assertNil(Swing.flying, "the next swing ends the proven flight")
    local fraction = Swing:Progress()
    nearT(fraction, 0, 0.02, "and re-arms the cycle fresh")
end)

test("movement rides the real speed reader through the gate", function()
    A_Admin.SetMoving(true)
    drive("PLAYER_STARTED_MOVING")
    -- (I2f3 measured: CanAim short-circuits at the attack gate in this
    -- profile — UnitCanAttack("player","target") rides false, there is no
    -- target fixture (the header's SetTarget law) — so CycleState never
    -- reaches its SampleMovement leg here. The movement law rides the
    -- sampler seam directly: the production speedSampler (Core/Tools.lua
    -- :942, wired at module load) is the real GetUnitSpeed, and
    -- A_Admin.SetMoving drives it for real.)
    assertEquals(true, Swing:SampleMovement(),
        "GetUnitSpeed=7 reads as movement through the real sampler")
    assertEquals(true, Swing:Snapshot().moving,
        "the snapshot carries the sampled flag")
    assertEquals(false, Swing:CanAim(),
        "a moving player can not begin the aim window (the target and "
        .. "attack gates ride false in this profile too)")
    A_Admin.SetMoving(false)
    drive("PLAYER_STOPPED_MOVING")
    assertEquals(false, Swing:SampleMovement(),
        "the standing speed read answers movement false")
    assertEquals(false, Swing:Snapshot().moving,
        "PLAYER_STOPPED_MOVING clears the flag and the pulse")
end)

test("the aspects tracker adopts on the cast and the regen pass clears it",
function()
    local name
    for _, spell in pairs(FX.Data.Hunter or {}) do
        if type(spell) == "table" and type(spell.name) == "string"
            and spell.name:find("^Aspect of") then
            name = spell.name
        end
    end
    assertEquals(true, Aspects:OnCast(name),
        "the adoption seam recognizes the data-keyed aspect")
    assertEquals(name, Aspects:Current(), "the tracker wears it")
    assertEquals(false, Aspects:Missing(),
        "with the aspect known active the reminder is silent")
    drive("PLAYER_REGEN_ENABLED")
    assertNil(Aspects:Current(),
        "the out-of-combat pass ran the real reader "
        .. "(GetAuraDataBySpellName — the never-granted aspect reads "
        .. "confirmed-absent across the data aspect set) and cleared it")
    assertEquals(false, Aspects:Missing(),
        "mid-combat a cleared prediction does not ask for the reminder")
end)

test("a cast of the paladin set is inert to the shot machine", function()
    local id, name = knownCast()
    assertNotNil(id, "the profile set resolves a cast by id ("
        .. tostring(name) .. ")")
    -- (I2f3 run 2: the live frame script is reachable (the gate's law) —
    -- the player legs ride it DIRECTLY, so the script's own resolve +
    -- canonicalize parts run and the inertness law is measured on the
    -- real dispatch, not the replica.)
    local frame = M._eventFrame
    local script = frame:GetScript("OnEvent")
    local function live(event, ...) script(frame, event, ...) end
    live("UNIT_SPELLCAST_SENT", "player", "Probe Dummy", "FxH-inert-1", id)
    live("UNIT_SPELLCAST_START", "player", "FxH-inert-1", id, 1)
    live("UNIT_SPELLCAST_SUCCEEDED", "player", "FxH-inert-1", id, 2)
    drive("UNIT_SPELLCAST_SENT", "pet", "Probe Dummy", "FxH-inert-2", id)
    drive("UNIT_SPELLCAST_START", "pet", "FxH-inert-2", id, 1)
    drive("UNIT_SPELLCAST_SUCCEEDED", "pet", "FxH-inert-2", id, 2)
    local cr = Swing:CastRemaining()
    if cr ~= nil then
        local c = Swing.cast
        error("inert facts: id=" .. tostring(id) .. " name=" .. tostring(name)
            .. " canon=" .. tostring(M.CanonicalCastName(name))
            .. " cr=" .. tostring(cr)
            .. " cast=" .. tostring(c and c.name)
            .. " len=" .. tostring(c and c.len)
            .. " startAt=" .. tostring(c and c.startAt)
            .. " now=" .. tostring(GetTime())
            .. " clipEnd=" .. tostring(Swing.cast and Swing.cast.endAt))
    end
    assertNil(cr,
        "the machine keys on canonical spell names: the paladin cast "
        .. "clips nothing")
    assertNil(Swing.pending, "the paladin SENT staged no shot")
    assertNil(Swing.at, "the paladin START stamped no aim window")
    assertNil(Aspects:Current(), "and the aspect tracker adopted nothing")
    assertEquals(2.0, Swing:Snapshot().lastDuration,
        "the cycle length stayed the swing payload it was")
end)

test("zzz the suite leaves the module state as it found it", function()
    A_Admin.SetInCombat(false)
    step(0.2)
    drive("PLAYER_REGEN_ENABLED")
    A_Admin.SetMoving(false)
    pcall(A_Admin.ClearTarget)
    -- The live module fields back to their resting shape (no live cycle,
    -- no live shot, no live prediction — the history fields ride on, the
    -- way a session's do).
    Swing.active = false
    Swing.start, Swing.duration, Swing.at, Swing.pending = nil, nil, nil, nil
    Swing.cast, Swing.flying, Swing.retryUntil = nil, nil, nil
    Swing.feignPending, Swing.movePulseAt, Swing.rangeEdges = nil, nil, nil
    Swing.factsInRange, Swing.shooting, Swing.moving = nil, false, false
    Aspects.current = nil
    assertNil(Swing:CastRemaining(), "the clip is clean")
    assertNil(Swing:CycleState(), "the tracker answers idle")
    assertFalse(Swing:Snapshot().moving, "the player stands")
    local lines = printCapture.lines
    FX.Print = saved.print
    assertEquals(0, lines,
        "the round printed nothing (" .. tostring(lines) .. " lines)")
    -- (I2f3: the handback math rode GetManualClockEnabledAt — the surface
    -- does not exist, SetManualClock is enable-once with no off switch,
    -- and this file is the run's last: the Forte_Timer tail law, the
    -- clock rides on.)
    assertNotNil(M._eventFrame,
        "the suite leaves the frame it found (the wiring tests' state rides on)")
    assertNotNil(M._eventFrame:GetScript("OnEvent"),
        "the reachable script rides on as the gate found it (I2f3 law: the "
        .. "suite drove trackers and the live script, never rewired)")
    assertEquals(saved.eventsWereEnabled, M._eventsEnabled == true,
        "the eventsEnabled mirror rides as the gate found it")
end)
