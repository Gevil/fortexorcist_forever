-- addon/Forte_Cooldown/tests/test_engine.lua
-- wow-ui-sim tests for Core/Engine.lua against the REAL engine, the REAL
-- ForteXorcist.Compat and the REAL generated class data -- no stubbing of
-- engine/compat internals. Runs in the sim (not luajit) because the last two
-- tests check every generated spell row against the live C_Spell DB, which
-- only exists here.
--
-- Isolation: every test attaches a private throwaway storage table via
-- Engine:AttachStorage and rebuilds its own tracked set, so tests are
-- order-independent. The module's original storage is re-attached by the last
-- registered test (the framework runs tests in registration order and offers
-- no teardown hook).
--
-- Secret-read note (test 7): the sim exposes no A_Admin control to force a
-- secret value from C_Spell.GetSpellCooldown (the v0.1.39 AddOns have no
-- secret-related admin verb), so the secret path is exercised through its
-- exact downstream contract: Compat.GetSpellCooldown forwards
-- info.startTime/info.duration raw, and Engine:OnRead's first act is
-- Compat.PlainOrNil on them -- a sentinel therefore arrives as
-- OnRead(name, nil, nil, now). That call shape is what we drive.

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine

-- Secret sentinel seam (the tests/test_reconcile.lua pattern): the sim
-- exposes no A_Admin verb to mint a real secret value, so PlainOrNil is
-- wrapped so a string sentinel classifies as nil -- the exact downstream
-- contract a live secret read has. Used by the charges m3 test; restored
-- inside it (the framework has no teardown).
local SECRET = "FXTEST-SECRET-VALUE"
local realPlainOrNil = FX.Compat.PlainOrNil
local function patchPlain()
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlainOrNil(v)
    end
end
local function restorePlain()
    FX.Compat.PlainOrNil = realPlainOrNil
end

-- Durations that arrive through the `cooldownMs / 1000` division are floats;
-- compare them with a tolerance, never exact equality (measured 2026-11-01: a
-- hard 79.2 assertion died on the float32 round-trip with 79.199996948242).
local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

-- What Module.lua attached (FX.db.cooldownLearned, or a session table) at
-- file-load time; the final test hands it back.
local originalStorage = Engine.learned

local function freshStorage()
    local storage = {}
    Engine:AttachStorage(storage)
    return storage
end

--- Mirror of Engine:Build's tracking predicate (Core/Engine.lua), computed
--- from the data table itself -- no magic constants. isKnown stubs true.
--- Wave M3a: the `racial = true` rows (the racials group) are Build's
--- deliberate SKIP -- Engine:AddExtras tracks them from the same data
--- after Build (the Module's Rebuild), so the class-kit count this mirror
--- pins stays the pre-M3a number.
local function expectedTrackedCount(data)
    local n = 0
    for _, spell in pairs(data) do
        local cd = spell.cooldownMs and spell.cooldownMs / 1000
        if cd and cd >= Engine.MIN_COOLDOWN and spell.name
            and not spell.racial then
            n = n + 1
        end
    end
    return n
end

local function trackedCount()
    local n = 0
    for _ in pairs(Engine.tracked) do n = n + 1 end
    return n
end

local function allKnown() return true end

-- 1. Build over the real generated data.
test("Build tracks every Hunter cooldown row", function()
    freshStorage()
    local data = FX.Data and FX.Data.Hunter
    if not data then
        print("[skip] ForteXorcist.Data.Hunter not loaded (Forte_Hunter absent)")
        return
    end
    local expected = expectedTrackedCount(data)
    assertTrue(expected > 0)

    local n, reason = Engine:Build("HUNTER", allKnown)
    assertNil(reason)
    assertEquals(expected, n)
    assertEquals(expected, trackedCount())
    -- Spot-check one row landed with the right base duration (ms -> s, float
    -- division -> tolerance).
    local bw = Engine.tracked["Bestial Wrath"]
    assertNotNil(bw)
    assertEquals(19574, bw.dataId)
    near(120, bw.baseDuration)

    -- Rapid Fire, tracked iff the DATA row carries a cooldown: GenFix
    -- (2026-11-01) resolved it to id 3045, cooldownMs 300000 -- the old
    -- hardcoded "has no cooldown" assertion (test_engine.lua:77) went stale
    -- the moment the data fixed. Derive the expectation from the row itself.
    local rfRow, rfId
    for id, spell in pairs(data) do
        if spell.name == "Rapid Fire" then
            rfRow, rfId = spell, id
        end
    end
    assertNotNil(rfRow)
    local rfCd = rfRow.cooldownMs and rfRow.cooldownMs / 1000
    if rfCd and rfCd >= Engine.MIN_COOLDOWN then
        local rf = Engine.tracked["Rapid Fire"]
        assertNotNil(rf)
        near(rfCd, rf.baseDuration)
        if rfRow.cooldownMs == 300000 then
            -- The measured fact of this build (GenFix wave): 300 s.
            near(300, rf.baseDuration)
            assertEquals(3045, rfId)
            assertEquals(3045, rf.dataId)
        end
    else
        assertNil(Engine.tracked["Rapid Fire"])
    end

    -- "Rows without a cooldown are not tracked" -- pick the negative case
    -- from the data (alphabetically first name whose row has no cooldownMs),
    -- never a hand-picked spell whose row may grow a cooldown next build.
    local noCdName
    for _, spell in pairs(data) do
        local nm = spell.name
        if nm and not spell.cooldownMs and (noCdName == nil or nm < noCdName) then
            noCdName = nm
        end
    end
    assertNotNil(noCdName)
    assertNil(Engine.tracked[noCdName])
end)

test("Build reports missing class data", function()
    freshStorage()
    -- Deathknight: not in the Forever build, so no generated data and no toc ever loads for it.
    local n, reason = Engine:Build("DEATHKNIGHT", allKnown)
    assertNil(n)
    assertNotNil(reason)
    assertContains(tostring(reason), "no generated data")
    assertEquals(0, trackedCount())
end)

-- 2. Cast prediction.
test("OnCast predicts entry at now + BestDuration", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    local now = 1000
    local e = Engine:OnCast("Bestial Wrath", now)
    assertNotNil(e)
    near(120, Engine:BestDuration("Bestial Wrath")) -- generated base, nothing learned yet
    assertEquals(now, e.start)
    near(120, e.duration)
    near(now + Engine:BestDuration("Bestial Wrath"), e.endTime)
    assertTrue(e.predicted)
    -- A cast of a spell we do not track starts nothing.
    assertNil(Engine:OnCast("Soul Fire", now))
    assertEquals(1, (function()
        local n = 0
        for _ in pairs(Engine.entries) do n = n + 1 end
        return n
    end)())
end)

-- 3. Sweep pops expired entries.
test("Sweep pops expired entries to ready", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    Engine:OnCast("Disengage", 1100)     -- endTime 1105
    Engine:OnCast("Bestial Wrath", 1000) -- endTime 1120

    local out = Engine:Sweep(1104, {})
    assertEquals(0, #out) -- nothing due yet
    assertNotNil(Engine.entries["Bestial Wrath"])

    out = Engine:Sweep(1105, {})
    assertEquals(1, #out)
    assertEquals("Disengage", out[1]) -- exactly at endTime is due
    assertNil(Engine.entries["Disengage"])
    assertNotNil(Engine.entries["Bestial Wrath"])

    out = Engine:Sweep(1120, {})
    assertEquals(1, #out)
    assertEquals("Bestial Wrath", out[1])
    assertNil(Engine.entries["Bestial Wrath"])
end)

-- 4. Plain read anchors + learns.
test("Plain OnRead anchors entry and learns the real duration", function()
    local storage = freshStorage()
    Engine:Build("HUNTER", allKnown)
    Engine:OnCast("Bestial Wrath", 1000) -- predicted, 120 s

    local result = Engine:OnRead("Bestial Wrath", 1010, 110, 1012)
    assertEquals("anchored", result)
    local e = Engine.entries["Bestial Wrath"]
    assertNotNil(e)
    assertEquals(1010, e.start)
    assertEquals(110, e.duration)
    assertEquals(1010 + 110, e.endTime)
    assertFalse(e.predicted)
    -- The real (shorter) duration is learned into the attached storage and
    -- beats the generated base for the next prediction.
    assertEquals(110, storage["Bestial Wrath"])
    assertEquals(110, Engine:BestDuration("Bestial Wrath"))
    local e2 = Engine:OnCast("Bestial Wrath", 2000)
    assertEquals(2110, e2.endTime) -- predicts 110, not 120
    assertTrue(e2.predicted)
end)

-- The other two plain-read outcomes: GCD-masked ready under a fresh
-- prediction, and a real ready clearing an older entry.
test("Ready read: fresh prediction GCD-masked, older entry cleared", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    Engine:OnCast("Bestial Wrath", 1000) -- predicted, endTime 1120

    -- 0.5 s after the cast a "ready" read is the GCD masking the real
    -- cooldown: trust the cast, keep the prediction.
    assertEquals("ignored", Engine:OnRead("Bestial Wrath", 0, 0, 1000.5))
    assertNotNil(Engine.entries["Bestial Wrath"])

    -- 2 s after the cast (outside the 1.6 s window): trust the read.
    assertEquals("cleared", Engine:OnRead("Bestial Wrath", 0, 0, 1002))
    assertNil(Engine.entries["Bestial Wrath"])

    -- Reads for untracked spells are ignored outright.
    assertEquals("ignored", Engine:OnRead("Soul Fire", 1010, 60, 1012))
end)

-- 6. Secret-read tolerance (see file header for the substitution).
test("Secret read leaves engine state untouched", function()
    local storage = freshStorage()
    Engine:Build("HUNTER", allKnown)
    local e = Engine:OnCast("Bestial Wrath", 1000) -- predicted, 120 s

    -- OnRead(name, nil, nil, now) is exactly what a secret
    -- C_Spell.GetSpellCooldown arrives as after Compat.PlainOrNil.
    local result = Engine:OnRead("Bestial Wrath", nil, nil, 1005)
    assertEquals("secret", result)

    -- Same entry, unchanged: still the 120 s prediction, not overwritten.
    local same = Engine.entries["Bestial Wrath"]
    assertEquals(e, same)
    assertEquals(1000, same.start)
    near(120, same.duration)
    near(1120, same.endTime)
    assertTrue(same.predicted)
    -- Nothing learned from a secret read.
    assertNil(storage["Bestial Wrath"])
    near(120, Engine:BestDuration("Bestial Wrath"))
end)

-- m3 (review 2026-11-01): a charges read with a SECRET pair and no previous
-- clock used to build charges = { max, current } with nextAt = nil. The
-- charge Sweep advances only through nextAt and clears only at the full
-- bar, so such an entry can never be done -- it rides Engine.entries for
-- the rest of the session. The fix arms the clock on OnCast's rule.
test("OnReadCharges: a secret pair with no clock arms one and the bar sweeps out", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    Engine.tracked["Bestial Wrath"].maxCharges = 2
    local dur = Engine:BestDuration("Bestial Wrath") -- 120 (data-pinned)

    -- The shape: charges read, every number secret, no entry (so no
    -- previous clock). The plain currentCharges is NOT secret here -- with
    -- a secret count the read is "secret" and changes nothing at all,
    -- which is the test_reconcile.lua case, not this one.
    patchPlain()
    assertEquals("anchored", Engine:OnReadCharges("Bestial Wrath",
        0, SECRET, SECRET, 1000))
    restorePlain()

    local e = Engine.entries["Bestial Wrath"]
    assertNotNil(e, "the drained bar is modelled")
    assertEquals(2, e.charges.max)
    assertEquals(0, e.charges.current)
    assertNotNil(e.charges.nextAt, "the bar carries a clock")
    near(1000 + dur, e.charges.nextAt) -- OnCast's arming rule
    near(dur, e.duration)              -- the Sweep's step is the recharge

    -- The clock ticks: one charge per window, no pop before the full bar,
    -- and the entry LEAVES the bar at the full one (the old shape left it
    -- in entries forever).
    local out = Engine:Sweep(1000 + dur, {})
    assertEquals(0, #out)
    assertNotNil(Engine.entries["Bestial Wrath"])
    assertEquals(1, e.charges.current)
    near(1000 + 2 * dur, e.charges.nextAt)

    out = Engine:Sweep(1000 + 2 * dur, {})
    assertEquals(1, #out)
    assertEquals("Bestial Wrath", out[1])
    assertNil(Engine.entries["Bestial Wrath"])
end)

test("OnReadCharges: no duration known means no entry is created", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    -- A tracked, multi-charge spell with NO duration to predict from: no
    -- learned value and no generated base row.
    Engine.tracked["No Clock Spell"] = { name = "No Clock Spell", maxCharges = 2 }
    assertNil(Engine:BestDuration("No Clock Spell"))
    assertEquals("ignored", Engine:OnReadCharges("No Clock Spell", 0, 0, 0, 5000))
    assertNil(Engine.entries["No Clock Spell"])
    Engine.tracked["No Clock Spell"] = nil
end)

-- 5. Data sanity against the live spell DB (the reason this file runs in the
-- sim).
--
-- Build-skew rules (measured 2026-11-01, confirmed with the main session): the
-- data is pinned to mythicsim client_build 70425, the sim's spell DB is
-- 70532, the installed client is 70707, and Forever renumbers spell IDs
-- between builds. So:
--   * HARD: every row the sim DB resolves BY NAME (C_Spell.GetSpellInfo(name)
--     yields a plain spellID) must come back with exactly the data row's
--     name, case-insensitively -- a name change on the live DB is real drift.
--   * WARNING (reported, not asserted): the spellID the name resolves to
--     equals the data row's id; a by-ID lookup whose name differs from the
--     data row's name. Both are expected under build skew (rank/ID
--     renumbering; e.g. data id 603 = "Bane of Doom" resolves in 70532 to the
--     unrelated retail-era "Doom").
--   * Rows the sim's (partial, profile-driven) DB cannot see at all are a
--     coverage gap, not drift, and are reported as such.
--   * A whole class table with zero resolvable rows IS a failure (broken
--     addon load order or data), as is a class table that is nil-guarded to
--     skip when the class addon is absent.
local coverageStats = {}

local function probeLive(identifier)
    local ok, info = pcall(C_Spell.GetSpellInfo, identifier)
    if not ok or not info then return nil, nil end
    local name = FX.Compat.PlainOrNil(info.name)
    local spellID = FX.Compat.PlainOrNil(info.spellID)
    if type(name) ~= "string" or name == "" then name = nil end
    if type(spellID) ~= "number" then spellID = nil end
    return name, spellID
end

local function checkDataNames(dataKey)
    local data = FX.Data and FX.Data[dataKey]
    if not data then
        print(string.format("[skip] ForteXorcist.Data.%s not loaded (class addon absent)", dataKey))
        return
    end
    local rows = 0
    local nameResolved, byIdResolved, idDrift, idCollide, unseen = 0, 0, {}, {}, {}
    for id, spell in pairs(data) do
        rows = rows + 1
        local dname = tostring(spell.name)
        local lname, lid = probeLive(spell.name)
        if lname then
            nameResolved = nameResolved + 1
            -- HARD: live name for the data name must equal the data name.
            if lname:lower() ~= dname:lower() then
                error(string.format(
                    "%s [%s]: live DB renames it: GetSpellInfo(%q) -> %q",
                    dname, tostring(id), dname, lname), 2)
            end
            -- HARD: the name must resolve to a plain spellID.
            if lid == nil then
                error(string.format("%s [%s]: resolves with no plain spellID", dname, tostring(id)), 2)
            end
            -- WARNING: id equality across builds.
            if lid ~= id then
                idDrift[#idDrift + 1] = string.format("%s: data id %s, live id %s", dname, tostring(id), lid)
            end
        end
        local iname = probeLive(id)
        if iname then
            byIdResolved = byIdResolved + 1
            -- WARNING only: by-ID name equality is build-invalid (IDs
            -- renumber per patch), so a mismatch is a reported collision.
            if iname:lower() ~= dname:lower() then
                idCollide[#idCollide + 1] = string.format(
                    "%s: data id %s is %q on the live DB", dname, tostring(id), iname)
            end
        end
        if not lname and not iname then
            unseen[#unseen + 1] = dname
        end
    end
    assertTrue(rows > 0)
    -- Wiring guard: the sim DB must know at least one row of a loaded table.
    assertTrue(nameResolved + byIdResolved > 0)
    coverageStats[dataKey] = {
        rows = rows, nameResolved = nameResolved, byIdResolved = byIdResolved,
        idDrift = idDrift, idCollide = idCollide, unseen = unseen,
    }
end

test("Data.Hunter names match the live C_Spell DB", function()
    checkDataNames("Hunter")
end)

test("Data.Warlock names match the live C_Spell DB", function()
    checkDataNames("Warlock")
end)

-- Registered last => runs last: hand the module's storage back and leave the
-- engine empty for anything that runs after this file.
test("Restore module storage and clear engine state", function()
    Engine:AttachStorage(originalStorage)
    wipe(Engine.tracked)
    wipe(Engine.entries)
    assertEquals(originalStorage, Engine.learned)
end)
