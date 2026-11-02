-- addon/Forte_Core/tests/test_probe.lua
-- wow-ui-sim tests for Core/Probe.lua (the launch-day data collector).
--
-- Secret seam: the sim exposes no verb to mint a real secret value, so the
-- sentinel seam patches _G.issecretvalue itself -- Probe.K reads that
-- global per call (that indirection IS the tested contract), and a sentinel
-- string flowing through a scripted API table is classified exactly like a
-- live secret. Every seam is restored inside the test that took it (the
-- framework has no teardown).

local FX = ForteXorcist
local Probe = FX.Probe

local SENT = "FXTEST-SENTINEL-SECRET"

local function withSeam(fn)
    local real = _G.issecretvalue
    _G.issecretvalue = function(v) return v == SENT end
    local ok, err = pcall(fn)
    _G.issecretvalue = real
    assertTrue(ok)
    return err
end

--- Capture FX.Print + drive the real slash path (lower-cased in OnSlash).
local function slash(msg)
    local lines = {}
    local real = FX.Print
    FX.Print = function(m) lines[#lines + 1] = tostring(m) end
    local ok = pcall(FX.OnSlash, msg)
    FX.Print = real
    assertTrue(ok)
    return lines
end

local function joined(lines)
    return table.concat(lines, "\n")
end

--- Deep scan: does any stored value EQUAL the sentinel (a stored secret)?
local function deepFind(t, needle, seen)
    seen = seen or {}
    seen[t] = true
    for _, v in pairs(t) do
        if v == needle then return true end
        if type(v) == "table" and not seen[v] then
            if deepFind(v, needle, seen) then return true end
        end
    end
    return false
end

local function findGroup(run, prefix)
    for _, e in ipairs(run.results) do
        if e.group:find(prefix) then return e end
    end
    return nil
end

local function oneGroup(label)
    return { { label = "G1",
        fn = function() return { alpha = "number:7" } end } }
end

local savedEpoch = FX.db and FX.db.probeEpoch
local savedRuns = FX.db and FX.db.probes

-- 1. Registration surfaces.
test("probe registered: slash seam, module, API shape", function()
    assertNotNil(FX.slashSubs["probe"])
    assertNotNil(FX.modules["Probe"])
    assertEquals(Probe, FX.modules["Probe"])
    assertNotNil(Probe.K)
    assertNotNil(Probe.Run)
    assertNotNil(Probe.RunPlan)
    assertEquals(20, Probe.MAX_RUNS)
end)

-- 2. The login epoch: OnEnable rides the Forte_Core bootstrap's
-- PLAYER_LOGIN (the file's frame is the only top-level registrant), so it
-- runs exactly once per login; a /reload must NOT re-run it.
test("probeEpoch increments once per OnEnable (login), readable on runs", function()
    assertNotNil(savedEpoch)
    assertTrue(savedEpoch >= 1)
    Probe:OnEnable()
    assertEquals(savedEpoch + 1, FX.db.probeEpoch)
    local run = Probe:RunPlan("epoch-check", oneGroup())
    assertEquals(savedEpoch + 1, run.epoch)
    FX.db.probeEpoch = savedEpoch
end)

-- 3. The classifier law under the sentinel seam.
test("K: SECRET for secrets, typed renderings for plain values", function()
    withSeam(function()
        assertEquals("SECRET", Probe.K(SENT))
        assertEquals("number:5", Probe.K(5))
        assertEquals("number:12.3", Probe.K(12.3))
        assertEquals("boolean:true", Probe.K(true))
        assertEquals("boolean:false", Probe.K(false))
        assertEquals("nil", Probe.K(nil))
        assertEquals("string:Rapid Fire", Probe.K("Rapid Fire"))
        assertEquals("table", Probe.K({}))
    end)
    -- The real issecretvalue must classify the sentinel as plain again.
    assertEquals("string:" .. SENT, Probe.K(SENT))
end)

-- 4. Group-level protection: a group function that raises leaves a
-- recorded raise string in its result entry -- never a Lua error.
test("group pcall: a raising group fn records raise=, run completes", function()
    local plan4 = {
        { label = "OK1", fn = function() return { v = "number:1" } end },
        { label = "RAISER", fn = function() error("FXTEST-GROUP-RAISE", 0) end },
    }
    local ok, run = pcall(Probe.RunPlan, Probe, "pt-group-raise", plan4)
    assertTrue(ok)
    assertEquals("OK1", run.results[1].group)
    assertEquals("number:1", run.results[1].values.v)
    assertEquals("RAISER", run.results[2].group)
    assertNil(run.results[2].values)
    assertNotNil(run.results[2].raise)
    assertContains(run.results[2].raise, "FXTEST-GROUP-RAISE")
end)

-- 5. API-level protection: a raising Blizzard API inside a group leaves the
-- recorded error string in the group values (the call-site pcall), and the
-- run completes.
test("raising API: group values carry the recorded error string", function()
    local CS = _G.C_Spell
    local real = CS.GetSpellCooldown
    CS.GetSpellCooldown = function() error("FXTEST-API-RAISE", 0) end
    local ok, run = pcall(Probe.Run, Probe, "pt-api-raise")
    CS.GetSpellCooldown = real
    assertTrue(ok)
    local found = 0
    for _, e in ipairs(run.results) do
        if e.group:find("^CD ") then
            assertNotNil(e.values)
            assertContains(e.values.cd, "FXTEST-API-RAISE")
            found = found + 1
        end
    end
    assertTrue(found >= 1)
end)

-- 6. The storage law: a sentinel secret flowing out of a scripted API is
-- stored as "SECRET" and the sentinel value appears nowhere in the run.
test("secrets are stored as SECRET; the sentinel never enters storage", function()
    withSeam(function()
        local CS = _G.C_Spell
        local realCD, realCH = CS.GetSpellCooldown, CS.GetSpellCharges
        CS.GetSpellCooldown = function()
            return { isEnabled = true, isActive = true, isOnGCD = false,
                     startTime = SENT, duration = SENT, modRate = 1 }
        end
        CS.GetSpellCharges = function()
            return { maxCharges = 2, isActive = SENT, currentCharges = SENT,
                     cooldownStartTime = 0, cooldownDuration = 0 }
        end
        local ok, run = pcall(Probe.Run, Probe, "pt-secret")
        CS.GetSpellCooldown, CS.GetSpellCharges = realCD, realCH
        assertTrue(ok)
        local g = findGroup(run, "^CD ")
        assertNotNil(g)
        g = g.values
        assertEquals("boolean:true", g.en)
        assertEquals("boolean:true", g.act)
        assertEquals("SECRET", g.st)
        assertEquals("SECRET", g.dur)
        assertEquals("number:2", g.mx)
        assertEquals("SECRET", g.chAct)
        assertEquals("SECRET", g.cur)
        assertFalse(deepFind(run, SENT))
    end)
end)

-- 7. The store is a bounded ring of the last MAX_RUNS runs.
test("runs bounded to 20: the 21st..25th evict the oldest", function()
    local saved = FX.db.probes
    FX.db.probes = {}
    for i = 1, 25 do
        Probe:RunPlan("cap" .. i, { { label = "X",
            fn = function() return { v = "number:1" } end } })
    end
    assertEquals(20, #FX.db.probes)
    assertEquals("cap6", FX.db.probes[1].label)
    assertEquals("cap25", FX.db.probes[20].label)
    FX.db.probes = saved
end)

-- 8. show / clear through the real slash path.
test("probe show reprints the last run; probe clear empties the store", function()
    local saved = FX.db.probes
    FX.db.probes = {}
    local ok = pcall(Probe.RunPlan, Probe, "shown-label", oneGroup())
    assertTrue(ok)
    local text = joined(slash("probe show"))
    assertContains(text, "shown-label")
    assertContains(text, "alpha=7") -- compact print strips the type prefix
    local lines = slash("probe clear")
    assertContains(lines[1], "clear")
    assertEquals(0, #FX.db.probes)
    lines = slash("probe show")
    assertContains(lines[1], "no stored runs")
    FX.db.probes = saved
end)

-- 9. The default label rides InCombatLockdown.
test("default label: combat under InCombatLockdown, ooc outside", function()
    local real = _G.InCombatLockdown
    local plan = { { label = "X", fn = function() return { v = "nil" } end } }
    _G.InCombatLockdown = function() return true end
    local run = Probe:RunPlan(nil, plan)
    assertEquals("combat", run.label)
    assertTrue(run.combat)
    _G.InCombatLockdown = function() return false end
    run = Probe:RunPlan(nil, plan)
    assertEquals("ooc", run.label)
    assertFalse(run.combat)
    _G.InCombatLockdown = real
end)

-- 10. The bar probe: self-built C_DurationUtil duration feeding a StatusBar
-- + Cooldown; K-classified readback; bar off hides.
test("probe bar: widgets shown, K readback (set/secret/rem), bar off hides", function()
    local text = joined(slash("probe bar"))
    assertContains(text, "PROBE bar: on")
    assertContains(text, "secret=")
    assertContains(text, "rem=")
    local bar = Probe._bar
    assertNotNil(bar)
    assertNotNil(bar.sb)
    assertNotNil(bar.sb.IsShown)
    assertTrue(bar.sb:IsShown())
    assertNotNil(bar.last)
    assertNotNil(bar.last.rem)
    assertNotNil(bar.last.rem:find("^number:"))
    slash("probe bar off")
    assertFalse(bar.sb:IsShown())
    if bar.cd and bar.cd.IsShown then
        assertFalse(bar.cd:IsShown())
    end
end)

-- 11. Event capture: a UNIT_SPELLCAST_SUCCEEDED payload seen by the
-- capture frame rides the CAST group as K strings (Q1's day-1 instrument).
test("captured cast payload classifies into the CAST group", function()
    local f = Probe._frame
    assertNotNil(f)
    local h = f:GetScript("OnEvent")
    assertNotNil(h)
    h(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "FXTEST-GUID", 350005, 12)
    local run = Probe:Run("cap-cast")
    local e = findGroup(run, "^CAST$")
    assertNotNil(e)
    assertEquals("string:FXTEST-GUID", e.values.cGuid)
    assertEquals("number:350005", e.values.cId)
    assertNotNil(e.values.cap)
    assertFalse(deepFind(run, "FXTEST-GUID")) -- stored as the K string, not raw
end)

-- 12. /fx status gains exactly the Probe line (module Status contract).
test("/fx status prints the Probe epoch/runs line", function()
    local text = joined(slash("status"))
    assertContains(text, "Probe: epoch=")
    assertContains(text, "runs=")
end)

-- Restore the SavedVariables shapes the file's runs touched.
test("state restored: epoch and the stored run list", function()
    -- The store is created lazily by Run; a pre-run session had no key at
    -- all, so the honest restore of "absent" is an empty list.
    FX.db.probes = savedRuns or {}
    assertEquals(savedEpoch, FX.db.probeEpoch)
    assertNotNil(FX.db.probes)
    if not savedRuns then assertEquals(0, #FX.db.probes) end
end)
