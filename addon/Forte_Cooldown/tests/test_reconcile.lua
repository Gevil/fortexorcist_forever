-- addon/Forte_Cooldown/tests/test_reconcile.lua
-- wow-ui-sim tests for the reconcile hardening (2026-11-01 wave):
--   * the cast-secrecy counters (Module:RecordCastEvent, PLAN §8 mitigation 1)
--   * the active-edge fallback (Engine:OnActiveEdge + Module:ReadAll,
--     PLAN §8 mitigation 2)
--   * the multi-charge engine model (Engine:OnCast/Sweep/Sorted/
--     OnReadCharges/DetectCharges -- owner ruling: built NEW, data untouched)
--
-- Seams (the sim exposes no A_Admin verb to mint a real secret value):
-- FX.Compat.PlainOrNil is wrapped so a string sentinel classifies as nil --
-- the exact downstream contract a live secret value has (Engine:OnRead's
-- first act IS PlainOrNil). The FX.Compat cooldown/charges readers are
-- swapped for scripted SpellCooldownInfo/SpellChargeInfo tables. Every seam
-- is restored inside the test that took it (the framework has no teardown).
-- Durations arriving via `cooldownMs / 1000` are floats -> compare with a
-- tolerance (test_engine.lua's measured law).

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local M = FX.Cooldown.Module

local SECRET = "FXTEST-SECRET-VALUE"

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

local function freshStorage()
    local storage = {}
    Engine:AttachStorage(storage)
    return storage
end

local function allKnown() return true end

local function countEntries()
    local n = 0
    for _ in pairs(Engine.entries) do n = n + 1 end
    return n
end

-- What the module bound at PLAYER_LOGIN; the last test hands them back.
local originalStorage = Engine.learned
local savedDbDiag = FX.db and FX.db.diag and FX.db.diag.casts

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

--- First generated Hunter row the SIM's spell DB resolves to a plain
--- spellID (the sim profile DB is sparse and renumbered -- test_engine.lua's
--- build-skew law -- so the probe, not the data pin, decides).
local function anyResolvableSpellID()
    local data = FX.Data and FX.Data.Hunter
    for _, spell in pairs(data or {}) do
        local ok, info = pcall(C_Spell.GetSpellInfo, spell.name)
        local id = ok and info and realPlainOrNil(info.spellID)
        if id ~= nil then return id end
    end
    return nil
end

-- ---------------------------------------------------------------- counters --

test("cast counters classify plain/secret/unresolved, split combat, persist", function()
    local savedCasts = FX.db and FX.db.diag and FX.db.diag.casts
    if FX.db then FX.db.diag = nil end
    local d = M:InitCastDiag()
    assertNotNil(FX.db)
    assertEquals(FX.db.diag.casts, d)

    local liveID = anyResolvableSpellID()
    assertNotNil(liveID)
    local bogus = 987654321
    local okB, infoB = pcall(C_Spell.GetSpellInfo, bogus)
    local bogusResolves = (okB and infoB and realPlainOrNil(infoB.name)) ~= nil

    patchPlain()
    M:RecordCastEvent(liveID, false)   -- plain, resolves: drives Engine:OnCast
    M:RecordCastEvent(SECRET, true)    -- classifies as a secret id, in combat
    M:RecordCastEvent(bogus, false)    -- plain number, resolves to nothing
    restorePlain()

    assertEquals(3, d.seen)
    assertEquals(2, d.plainId)
    assertEquals(1, d.secretId)
    assertEquals(1, d.resolved)
    assertEquals(1 + (bogusResolves and 1 or 0), d.unresolved)
    -- In-combat split (out-of-combat is totals minus this).
    assertEquals(1, d.inSeen)
    assertEquals(0, d.inPlain)
    assertEquals(1, d.inSecret)
    assertEquals(0, d.inResolved)
    assertEquals(1, d.inUnresolved)
    -- Persistence: the live counters ARE FX.db.diag.casts; rebinding keeps
    -- the cumulative numbers.
    local rebound = M:InitCastDiag()
    assertEquals(d, rebound)
    assertEquals(3, rebound.seen)
    -- The plain, resolved event fed Engine:OnCast for its spell.
    local found = false
    for _ in pairs(Engine.entries) do found = true end
    assertTrue(found)

    wipe(Engine.entries)
    if FX.db then FX.db.diag.casts = savedCasts end
    M:InitCastDiag()
end)

test("/fx status prints the casts line and the combat split", function()
    local savedCasts = FX.db and FX.db.diag and FX.db.diag.casts
    if FX.db then FX.db.diag = nil end
    local d = M:InitCastDiag()
    d.seen, d.plainId, d.secretId, d.resolved, d.unresolved = 7, 5, 2, 4, 3
    d.inSeen, d.inPlain, d.inSecret, d.inResolved, d.inUnresolved = 4, 2, 2, 2, 2

    local lines = {}
    local realPrint = FX.Print
    FX.Print = function(msg) lines[#lines + 1] = tostring(msg) end
    M:Status()
    FX.Print = realPrint

    local joined = table.concat(lines, "\n")
    assertContains(joined, "casts seen 7 | plain 5 | secret 2 | unresolved 3")
    assertContains(joined, "in-combat seen 4 | plain 2 | secret 2 | unresolved 2")
    assertContains(joined, "out-of-combat seen 3 | plain 3 | secret 0 | unresolved 1")

    if FX.db then FX.db.diag.casts = savedCasts end
    M:InitCastDiag()
end)

-- ------------------------------------------------------------- active edge --

test("OnActiveEdge creates exactly one edge entry and defers to live entries", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    -- Untracked: no entry.
    assertNil(Engine:OnActiveEdge("Soul Fire", 1000))
    assertEquals(0, countEntries())

    local e = Engine:OnActiveEdge("Bestial Wrath", 1000)
    assertNotNil(e)
    assertEquals("edge", e.source)
    assertTrue(e.predicted)
    assertEquals(1000, e.start)
    near(Engine:BestDuration("Bestial Wrath"), e.duration)
    near(1000 + Engine:BestDuration("Bestial Wrath"), e.endTime)
    assertEquals(1, countEntries()) -- exactly one entry

    -- A live entry owns the spell: the edge never duplicates it.
    assertNil(Engine:OnActiveEdge("Bestial Wrath", 1050))
    assertEquals(1, countEntries())
    Engine:OnCast("Disengage", 1100)
    assertNil(Engine:OnActiveEdge("Disengage", 1150))
    assertEquals("cast", Engine.entries["Disengage"].source)
end)

test("Read pass: active non-GCD starts the edge, GCD-only and live entries do not", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)

    local realInfo = FX.Compat.GetSpellCooldownInfo
    local realCharges = FX.Compat.GetSpellCharges
    patchPlain()
    FX.Compat.GetSpellCooldownInfo = function(name)
        if name == "Bestial Wrath" then
            -- Numbers secret (the combat-locked shape), booleans plain:
            -- a tracked cooldown is running that no event ever named.
            return { startTime = SECRET, duration = SECRET,
                     isActive = true, isOnGCD = false }
        elseif name == "Rapid Fire" then
            -- Active, but the GCD's doing: not an edge.
            return { startTime = SECRET, duration = SECRET,
                     isActive = true, isOnGCD = true }
        end
        return { startTime = 0, duration = 0,
                 isActive = false, isOnGCD = false }
    end
    FX.Compat.GetSpellCharges = function()
        return { currentCharges = SECRET, maxCharges = 1,
                 cooldownStartTime = SECRET, cooldownDuration = SECRET }
    end
    M:ReadAll()
    FX.Compat.GetSpellCooldownInfo = realInfo
    FX.Compat.GetSpellCharges = realCharges
    restorePlain()

    local e = Engine.entries["Bestial Wrath"]
    assertNotNil(e)
    assertEquals("edge", e.source)
    assertTrue(e.predicted)
    assertNil(Engine.entries["Rapid Fire"]) -- isOnGCD: GCD is not an edge
    assertEquals(1, countEntries())
    -- A second pass: the live entry owns the spell, the edge adds nothing.
    FX.Compat.GetSpellCooldownInfo = realInfo
    M:ReadAll()
    assertEquals(1, countEntries())
    assertEquals("edge", Engine.entries["Bestial Wrath"].source)
end)

test("edge entries never pop ready without an anchoring plain read", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    local dur = Engine:BestDuration("Bestial Wrath") -- 120 (data-pinned)
    Engine:OnActiveEdge("Bestial Wrath", 1000)       -- endTime 1120

    local out = Engine:Sweep(1119, {})
    assertEquals(0, #out)
    assertNotNil(Engine.entries["Bestial Wrath"])
    out = Engine:Sweep(1120, {})                     -- window lapsed
    assertEquals(0, #out)                            -- ... swept in silence
    assertNil(Engine.entries["Bestial Wrath"])

    -- The same entry, vouched for by a plain read: the pop fires.
    Engine:OnActiveEdge("Bestial Wrath", 2000)
    assertEquals("anchored", Engine:OnRead("Bestial Wrath", 2005, dur, 2006))
    assertEquals("read", Engine.entries["Bestial Wrath"].source)
    out = Engine:Sweep(2005 + dur, {})
    assertEquals(1, #out)
    assertEquals("Bestial Wrath", out[1])

    -- Baseline law (test_engine.lua): a plain "cast" entry still pops.
    Engine:OnCast("Disengage", 3000)
    out = Engine:Sweep(3000 + Engine:BestDuration("Disengage"), {})
    assertEquals(1, #out)
    assertEquals("Disengage", out[1])
end)

-- ------------------------------------------------------------------ charges --

test("DetectCharges marks only spells the live read shows as multi-charge", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    local fake = {
        ["Bestial Wrath"] = { maxCharges = 2 },
        ["Rapid Fire"] = { maxCharges = 1 },
        -- Absent rows: the reader says nothing -> unmarked.
    }
    Engine:DetectCharges(function(name) return fake[name] end)
    assertEquals(2, Engine.tracked["Bestial Wrath"].maxCharges)
    assertNil(Engine.tracked["Rapid Fire"].maxCharges)
end)

test("charges: two casts drain the bar; the sweep lands one charge per window", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    Engine.tracked["Bestial Wrath"].maxCharges = 2
    local dur = Engine:BestDuration("Bestial Wrath") -- 120

    local e1 = Engine:OnCast("Bestial Wrath", 1000)
    assertNotNil(e1.charges)
    assertEquals(2, e1.charges.max)
    assertEquals(1, e1.charges.current)
    near(1000 + dur, e1.charges.nextAt) -- the clock armed at the first cast
    local e2 = Engine:OnCast("Bestial Wrath", 1005)
    assertEquals(e1, e2)                -- same entry, restarted window
    assertEquals(0, e2.charges.current) -- drained
    near(1000 + dur, e2.charges.nextAt) -- next recharge lands at +dur

    -- Drained (current == 0) is the genuinely-cooling state: the row rides
    -- the cooling list carrying the flattened charge trio.
    local rows = Engine:Sorted({})
    assertEquals(1, #rows)
    assertEquals("Bestial Wrath", rows[1].name)
    assertEquals(0, rows[1].charges)
    assertEquals(2, rows[1].maxCharges)
    near(1000 + dur, rows[1].rechargeEnd)

    -- One recharge window: one charge lands, the clock steps one window on.
    -- Not the full bar -> no pop.
    local out = Engine:Sweep(1000 + dur, {})
    assertEquals(0, #out)
    assertEquals(1, e1.charges.current)
    near(1000 + 2 * dur, e1.charges.nextAt)
    -- current > 0: castable -> NOT on cooldown -> out of the cooling list.
    assertEquals(0, #Engine:Sorted({}))

    -- Full bar: that is the ready moment.
    out = Engine:Sweep(1000 + 2 * dur, {})
    assertEquals(1, #out)
    assertEquals("Bestial Wrath", out[1])
    assertNil(Engine.entries["Bestial Wrath"])
end)

test("charges: plain reads re-anchor, secret reads leave the model, full bar clears", function()
    local storage = freshStorage()
    Engine:Build("HUNTER", allKnown)
    Engine.tracked["Bestial Wrath"].maxCharges = 2
    Engine:OnCast("Bestial Wrath", 1000) -- charges {2,1,nextAt 1120}

    patchPlain()
    -- Secret currentCharges: nothing moves.
    assertEquals("secret", Engine:OnReadCharges("Bestial Wrath",
        SECRET, SECRET, SECRET, 1010))
    local e = Engine.entries["Bestial Wrath"]
    assertEquals(1, e.charges.current)
    near(1120, e.charges.nextAt)
    assertEquals("cast", e.source)

    -- Plain charges: current re-anchors from currentCharges, nextAt from
    -- cooldownStartTime + cooldownDuration; the read certifies the bar.
    assertEquals("anchored", Engine:OnReadCharges("Bestial Wrath", 0, 1010, 120, 1012))
    restorePlain()
    e = Engine.entries["Bestial Wrath"]
    assertEquals(0, e.charges.current)
    near(1130, e.charges.nextAt)
    assertEquals(1010, e.start)
    near(120, e.duration)
    assertEquals("read", e.source)
    assertTrue(e.anchored)

    -- The plain GetSpellCooldown "ready" read never clears a charge bar
    -- (its last-cast window lapses mid-bar; the charge read owns it).
    assertEquals("ignored", Engine:OnRead("Bestial Wrath", 0, 0, 1125))
    assertNotNil(Engine.entries["Bestial Wrath"])

    -- Plain full-bar read: the spell is ready -- the entry goes, silently.
    assertEquals("cleared", Engine:OnReadCharges("Bestial Wrath", 2, 0, 0, 1200))
    assertNil(Engine.entries["Bestial Wrath"])

    -- Charges of a spell we never detected as multi-charge: ignored.
    assertEquals("ignored", Engine:OnReadCharges("Disengage", 1, 0, 0, 1200))
    -- Charges reads learn nothing (the plain cooldown read is the teacher).
    assertNil(storage["Bestial Wrath"])
end)

-- Registered last => runs last: hand the module's storage and diag back and
-- leave the engine empty for anything that runs after this file.
test("Restore module storage, cast diag and engine state", function()
    restorePlain()
    Engine:AttachStorage(originalStorage)
    wipe(Engine.tracked)
    wipe(Engine.entries)
    if FX.db then FX.db.diag.casts = savedDbDiag end
    M:InitCastDiag()
    assertEquals(originalStorage, Engine.learned)
end)
