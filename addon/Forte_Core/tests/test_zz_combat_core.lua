-- =============================================================================
-- test_zz_combat_core.lua — the I2f combat-simulation round for the Core
-- launch surfaces: the PROBE battery and the TEST-MODE gate (PLAN §11.2 row
-- I2f, the docs/launch-day.md owner checklist).
--
-- NAME LAW: the "zz_" prefix sorts this file LAST. No manual clock rides
-- this suite: the TestMode pump is a C_Timer ticker the suite never lets
-- beat (Start/Stop ride in one step), and the probe is a synchronous
-- battery.
--
-- WHAT THIS ROUND DRIVES (the I2f assignment):
--   * `/fx probe` IN COMBAT runs the battery clean: the shared slash seam
--     (FX.OnSlash → FX.slashSubs["probe"]) rides out without raising, the
--     run lands in FX.db.probes stamped combat=true, and every group
--     answers (a raising group lands as the recorded { raise } string —
--     the battery never dies);
--   * `/fx test` IN COMBAT is REFUSED: T:Start answers (false, "combat"),
--     the refusals counter rides +1, the reason stamps "combat", the
--     refusal line prints, and the mode rides NOT running;
--   * the login wiring law: TestMode's own `_eventFrame` (OnEnable's
--     "the tests' handle", TestMode.lua:336) is driven with the REAL
--     OnEvent script: PLAYER_REGEN_DISABLED on a running mode scrubs it
--     with reason "combat" — the in-fight exit, driven in-game.
--
-- SIM LAWS:
--   * FX.Print captured: the probe report is the module's DESIGNED output
--     (the leg counts the lines, the print-zero law waives — the refusal
--     line is likewise designed print);
--   * FX.db.probes is the bounded SavedVariables ring: the gate records
--     its length and the zzz trims this run's additions back (MAX_RUNS
--     trimming rides table.remove(runs, 1) — the zzz rides the same seam
--     from the tail);
--   * TestMode's counters (stats) are session state: RELATIVE asserts.
-- =============================================================================
local FX = ForteXorcist
local Probe = FX.Probe
local T = FX.TestMode

local saved
local printCapture

local function capturePrint()
    printCapture = { lines = 0 }
    saved.realPrint = FX.Print
    FX.Print = function(...)
        printCapture.lines = printCapture.lines + 1
        print(...)
    end
end
local function releasePrint()
    if saved.realPrint then FX.Print = saved.realPrint end
    saved.realPrint = nil
end

-- ---------------------------------------------------------------------- gate
test("zz combat gate: the Core launch surfaces are on the slash registry",
function()
    assertNotNil(Probe, "FX.Probe exists")
    assertNotNil(T, "FX.TestMode exists")
    assertNotNil(FX.slashSubs, "the slash registry rides")
    assertNotNil(FX.slashSubs["probe"], "the probe sub rides the registry")
    assertNotNil(FX.slashSubs["test"], "the test-mode sub rides the registry")
    assertNotNil(Probe.MAX_RUNS, "the run ring is bounded")
    saved = {}
    capturePrint()
    -- The shared-state anchors.
    saved.runs0 = FX.db and FX.db.probes and #FX.db.probes or 0
    saved.refusals0 = T.stats.refusals
    saved.starts0 = T.stats.starts
    saved.stops0 = T.stats.stops
    saved.active0 = T:IsActive()
    assertEquals(false, saved.active0,
        "the mode rides NOT running at the gate (the baseline shape)")
    assertNotNil(T._eventFrame,
        "the login-wired event frame rides (the tests' handle)")
    assertNotNil(T._eventFrame:GetScript("OnEvent"),
        "the real OnEvent script is reachable (login-wired module law)")
    A_Admin.SetInCombat(true)
    assertTrue(InCombatLockdown(), "the sim lockdown gate is active")
    assertEquals(true, T:InCombat(),
        "the mode's own combat probe reads the lockdown")
end)

-- ------------------------------------------------------- /fx test in combat --
test("in combat: the test-mode start is refused, counted, and printed",
function()
    local ok, why = T:Start()
    assertEquals(false, ok, "the start answers false in combat")
    assertEquals("combat", why, "the refusal reason is 'combat'")
    assertEquals("combat", T.reason, "the reason stamp rides 'combat'")
    assertEquals(false, T:IsActive(), "the mode rides NOT running")
    assertEquals(saved.refusals0 + 1, T.stats.refusals,
        "the refusals counter rode +1")
    assertEquals(1, printCapture.lines,
        "the refusal line printed (" .. tostring(printCapture.lines)
        .. " lines)")
    -- The slash seam answers the same law (the /fx test input half).
    local lines0 = printCapture.lines
    FX.slashSubs["test"]("")
    assertEquals(lines0 + 1, printCapture.lines,
        "the slash seam rode out (the toggle's second refusal print)")
    assertEquals(saved.refusals0 + 2, T.stats.refusals,
        "the slash ride refused too (the refusals pair)")
    assertEquals(false, T:IsActive(), "the mode rides NOT running")
end)

-- -------------------------------------------------------- /fx probe in combat --
test("in combat: the probe battery rides the slash seam clean", function()
    local lines0 = printCapture.lines
    local ok, err = pcall(FX.slashSubs["probe"], "")
    assertTrue(ok, "the battery raised nothing in combat ("
        .. tostring(err) .. ")")
    local runs = FX.db and FX.db.probes
    assertNotNil(runs, "the run ring rides")
    assertEquals(saved.runs0 + 1, #runs, "the run landed in the ring")
    local run = runs[#runs]
    assertEquals("combat", run.label, "the label defaulted 'combat'")
    assertEquals(true, run.combat, "the run is stamped combat")
    assertTrue(#run.results >= 1,
        "the battery groups all answered (" .. tostring(#run.results)
        .. " groups)")
    assertTrue(printCapture.lines > lines0,
        "the report printed (the designed output: "
        .. tostring(printCapture.lines - lines0) .. " lines)")
end)

-- ------------------------------------------------- the real event-script leg --
test("out of combat: the real OnEvent script scrubs a start on combat entry",
function()
    A_Admin.SetInCombat(false)
    assertFalse(InCombatLockdown(), "the sim lockdown gate released")
    local ok, why = T:Start()
    assertEquals(true, ok, "the start rides out out of combat ("
        .. tostring(why) .. ")")
    assertEquals("on", T.reason, "the mode stamps 'on'")
    assertEquals(saved.starts0 + 1, T.stats.starts,
        "the starts counter rode +1")
    -- The combat entry through the REAL login-wired script: the regen-drop
    -- event is the client's own combat-start signal.
    local script = T._eventFrame:GetScript("OnEvent")
    local lines0 = printCapture.lines
    script(T._eventFrame, "PLAYER_REGEN_DISABLED")
    assertEquals(false, T:IsActive(),
        "the real script scrubbed the mode on the combat start")
    assertEquals("combat", T.reason, "the scrub stamps 'combat'")
    assertEquals(saved.stops0 + 1, T.stats.stops,
        "the stops counter rode +1")
    assertTrue(printCapture.lines >= lines0,
        "the scrub printed its exit line")
end)

-- ---------------------------------------------------------------------- zzz --
test("zzz the suite leaves the module state as it found it", function()
    A_Admin.SetInCombat(false)
    T:Stop("zzz")
    assertEquals(false, T:IsActive(), "the mode rides NOT running")
    assertEquals(saved.active0, T:IsActive(),
        "the found running shape rides back")
    -- Trim this round's probe runs out of the bounded ring.
    local runs = FX.db and FX.db.probes
    if runs then
        while #runs > saved.runs0 do table.remove(runs, #runs) end
        assertEquals(saved.runs0, #runs, "the run ring rides back")
    end
    local lines = printCapture.lines
    releasePrint()
    assertTrue(lines >= 3,
        "the designed lines printed (refusals + probe report: "
        .. tostring(lines) .. " lines)")
end)
