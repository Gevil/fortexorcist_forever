-- addon/Forte_Cooldown/tests/test_tiers.lua
-- wow-ui-sim tests for the read-ladder wave (docs/research/secrets-unknowns.md
-- §2 + §5, ranked design changes 1-3; PLAN §8 mitigations):
--   * tier 2 -- Engine:OnReadActive, the DOCS-NeverSecret
--     SpellCooldownInfo.isActive / .isOnGCD pair (the numbers of the same
--     read are secret, the pair is not): it ends a prediction whose cooldown
--     ended EARLY (a reset/proc) and it starts the "edge" entry for a start
--     no cast event named
--   * tier 3 -- Engine:OnReadDuration, the opportunistic exact anchor off the
--     UNANNOTATED LuaDurationObject of C_Spell.GetSpellCooldownDuration
--   * FX.SecretState -- the cached "are reads secret right now" mode, plus the
--     Module wiring that refreshes it on ADDON_RESTRICTION_STATE_CHANGED /
--     PLAYER_REGEN_DISABLED / PLAYER_REGEN_ENABLED
--   * the FX.db.diag.readTiers launch-day counters and the /fx status lines
--
-- Seams (the tests/test_reconcile.lua law): the sim exposes no A_Admin verb
-- to mint a real secret value, so FX.Compat.PlainOrNil is wrapped so a string
-- sentinel classifies as nil -- the exact downstream contract a live secret
-- has, and OnRead/OnReadActive/OnReadDuration's FIRST act IS PlainOrNil. The
-- FX.Compat readers are swapped for scripted SpellCooldownInfo tables. The
-- sim ships NEITHER C_Spell.GetSpellCooldownDuration NOR a working
-- C_RestrictedActions / C_Secrets (measured 2026-11-02: the C_Spell method is
-- nil; the C_RestrictedActions / C_Secrets methods are no functions), so tier
-- 3 and the mode queries run through their seams -- and the duration-object
-- contract is pinned a second time against the sim's REAL C_DurationUtil
-- object, which is the only way to measure the method names and the SECONDS
-- unit here. Every seam is restored inside the test that took it: the
-- framework has no teardown.
--
-- Time discipline: Engine-level tests drive synthetic frame times (1000, ...).
-- Every test that runs the real M:ReadAll uses GetTime()-relative times and
-- scripted readers, because the live sim DB answers for every tracked spell.
-- Durations from `cooldownMs / 1000` are floats: compare with a tolerance.

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local M = FX.Cooldown.Module

local SECRET = "FXTEST-SECRET-VALUE"
local SS = FX.SecretState

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

--- The sim's GetTime() is a live clock, so anything measured against a
--- GetTime() captured EARLIER (a read pass takes milliseconds of it) needs a
--- real tolerance -- 1e-6 is for float round-trips, not for elapsed time.
local function closeTo(actual, expected, tolerance)
    return assertTrue(math.abs(actual - expected) < tolerance)
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

-- What Module.lua attached at PLAYER_LOGIN; the last test hands it back.
local originalStorage = Engine.learned
local savedDbDiag = FX.db and FX.db.diag and FX.db.diag.casts
assertNotNil(SS)
local savedMode = {}
for _, spec in ipairs(SS.RESTRICTION_TYPES) do savedMode[spec.field] = SS[spec.field] end
savedMode.cooldownsSecret = SS.cooldownsSecret
savedMode.aurasSecret = SS.aurasSecret

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

--- The read-tier counters are one per-session table, so every assertion on
--- them is a DELTA over a snapshot (tests share the session).
local function tiers()
    local t = M._readTiers
    assertNotNil(t)
    return t.numeric, t.boolean, t.duration
end

--- The SpellCooldownInfo of a lockdown: the NUMBERS are secret, the
--- NeverSecret pair is plain (SpellCooldownInfo
--- @SpellSharedDocumentation.lua:18 -- isEnabled/isActive/isOnGCD
--- NeverSecret, startTime/duration/modRate unannotated).
local function lockdownInfo(isActive, isOnGCD)
    return { startTime = SECRET, duration = SECRET, modRate = SECRET,
             isEnabled = true, isActive = isActive, isOnGCD = isOnGCD }
end

local function secretCharges()
    return { currentCharges = SECRET, maxCharges = 1,
             cooldownStartTime = SECRET, cooldownDuration = SECRET }
end

--- A LuaDurationObject stand-in (the sim has no C_Spell.GetSpellCooldownDuration).
local function durationObject(hasSecret, remaining, total)
    return {
        HasSecretValues = function() return hasSecret end,
        GetRemainingDuration = function() return remaining end,
        GetTotalDuration = function() return total end,
    }
end

local function statusLines()
    local out = {}
    local realPrint = FX.Print
    FX.Print = function(msg) out[#out + 1] = tostring(msg) end
    M:Status()
    FX.Print = realPrint
    return out
end

-- ================================================= tier 2: the boolean pair --

test("OnReadActive ends a prediction the booleans say ended early, and the sweep pops it", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)

    -- A predicted window: cast at 1000, base/learned duration 120 -> 1120.
    local e = Engine:OnCast("Bestial Wrath", 1000)
    near(120, e.duration)
    near(1120, e.endTime)

    -- At 1100 -- 100 s in, far outside the read-lag grace -- the NeverSecret
    -- pair says the spell is READY and that it is not the GCD: a reset, a
    -- proc, a clear ended the real cooldown.
    assertEquals("cleared", Engine:OnReadActive("Bestial Wrath", false, false, 1100))
    local live = Engine.entries["Bestial Wrath"]
    assertNotNil(live)                  -- the Sweep owns removals
    near(1100, live.endTime)            -- the window is landed right here
    near(100, live.duration)            -- start + duration == endTime holds
    assertEquals(1000, live.start)
    assertEquals("cast", live.source)   -- no re-tagging: the pop law unchanged

    -- ... and it retires through the NORMAL ready pop, not in silence.
    local out = Engine:Sweep(1100, {})
    assertEquals(1, #out)
    assertEquals("Bestial Wrath", out[1])
    assertNil(Engine.entries["Bestial Wrath"])
end)

test("OnReadActive keeps a prediction inside the read-lag grace", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)
    local e = Engine:OnCast("Bestial Wrath", 1000)
    local endBefore, durBefore = e.endTime, e.duration
    local _, b0 = tiers()

    -- 1.5 s after the cast the read may still report the PRE-cast window --
    -- Engine:OnRead's 1.6 s law, now the shared Engine.PREDICTION_GRACE.
    near(1.6, Engine.PREDICTION_GRACE)
    assertEquals("kept", Engine:OnReadActive("Bestial Wrath", false, false, 1001.5))
    local live = Engine.entries["Bestial Wrath"]
    near(endBefore, live.endTime)
    near(durBefore, live.duration)
    assertEquals("cast", live.source)
    assertEquals(1, countEntries())
    -- A kept entry is not a tier firing.
    local _, b1 = tiers()
    assertEquals(b0, b1)

    -- The very next sweep tick past the grace is the moment it speaks.
    assertEquals("cleared", Engine:OnReadActive("Bestial Wrath", false, false,
        1000 + Engine.PREDICTION_GRACE))
end)

test("OnReadActive keeps it for the GCD, the numbers, the charges and the untracked", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)

    -- isOnGCD == true: the pair names the global cooldown, not this spell.
    Engine:OnCast("Bestial Wrath", 1000)
    local endBefore = Engine.entries["Bestial Wrath"].endTime
    assertEquals("kept", Engine:OnReadActive("Bestial Wrath", false, true, 1100))
    near(endBefore, Engine.entries["Bestial Wrath"].endTime)

    -- A plain-anchored ("read") window belongs to the NUMERIC tier: its next
    -- plain read, or the Sweep, retires it -- never the booleans.
    wipe(Engine.entries)
    assertEquals("anchored", Engine:OnRead("Disengage", 2000, 30, 2000))
    assertEquals("read", Engine.entries["Disengage"].source)
    assertEquals("kept", Engine:OnReadActive("Disengage", false, false, 2010))
    assertNotNil(Engine.entries["Disengage"])

    -- A charge bar: the charges read owns that lifecycle (Engine header).
    wipe(Engine.entries)
    Engine.tracked["Bestial Wrath"].maxCharges = 2
    Engine:OnCast("Bestial Wrath", 3000)
    assertNotNil(Engine.entries["Bestial Wrath"].charges)
    assertEquals("kept", Engine:OnReadActive("Bestial Wrath", false, false, 3200))
    local live = Engine.entries["Bestial Wrath"]
    assertNotNil(live.charges)
    near(3120, live.endTime) -- untouched: the OnCast window (3000 + 120)
    Engine.tracked["Bestial Wrath"].maxCharges = nil

    -- Nothing tracked: nothing to say.
    assertEquals("ignored", Engine:OnReadActive("Not A Spell", false, false, 4000))
    -- Tracked, ready, and no entry: also nothing to say.
    assertEquals("ignored", Engine:OnReadActive("Disengage", false, false, 4000))
end)

test("OnReadActive owns the active-edge start and guards the booleans defensively", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)

    -- isActive == true, no entry, not the GCD -> the PLAN §8 "edge" entry.
    assertEquals("edge", Engine:OnReadActive("Bestial Wrath", true, false, 5000))
    local e = Engine.entries["Bestial Wrath"]
    assertNotNil(e)
    assertEquals("edge", e.source)
    assertTrue(e.predicted)
    -- A live entry owns the spell: a second active read adds nothing.
    assertEquals("kept", Engine:OnReadActive("Bestial Wrath", true, false, 5010))
    assertEquals(1, countEntries())
    -- A GCD-only active with nothing running is not an edge.
    assertEquals("ignored", Engine:OnReadActive("Disengage", true, true, 5020))
    assertEquals(1, countEntries())
    wipe(Engine.entries)

    -- The pair is documented NeverSecret, and a documentation claim is not a
    -- runtime guarantee: a sentinel isActive/isOnGCD must be classified
    -- through PlainOrNil and must change nothing.
    patchPlain()
    Engine:OnCast("Bestial Wrath", 6000)
    local endBefore = Engine.entries["Bestial Wrath"].endTime
    assertEquals("kept", Engine:OnReadActive("Bestial Wrath", SECRET, SECRET, 6200))
    near(endBefore, Engine.entries["Bestial Wrath"].endTime)
    -- A secret isActive with no entry is not an edge either.
    wipe(Engine.entries)
    assertEquals("kept", Engine:OnReadActive("Disengage", SECRET, SECRET, 6300))
    assertEquals(0, countEntries())
    -- An absent pair (nil) gives the tier no voice.
    assertEquals("kept", Engine:OnReadActive("Disengage", nil, nil, 6400))
    assertEquals(0, countEntries())
    restorePlain()
end)

test("Read pass: secret numbers + plain isActive=false past the grace clears the prediction",
function()
    -- THE launch-day case, end to end through the real M:ReadAll: the numeric
    -- read is a lockdown, the cast event resolved, and 100 s later the plain
    -- booleans say the cooldown is over. On the pre-wave code this pass left
    -- the entry sitting on the bar until its predicted window lapsed -- the
    -- inline fallback there acted only on `isActive == true` -- so every
    -- assertion below is the new behaviour.
    local n0, b0, d0 = tiers()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)

    local realInfo = FX.Compat.GetSpellCooldownInfo
    local realCharges = FX.Compat.GetSpellCharges
    local now = GetTime()
    patchPlain()
    FX.Compat.GetSpellCooldownInfo = function(name)
        return lockdownInfo(name == "Bestial Wrath" and false, false)
    end
    FX.Compat.GetSpellCharges = secretCharges
    Engine:OnCast("Bestial Wrath", now - 100) -- far outside the grace
    assertNotNil(Engine.entries["Bestial Wrath"])
    M:ReadAll()
    FX.Compat.GetSpellCooldownInfo = realInfo
    FX.Compat.GetSpellCharges = realCharges
    restorePlain()

    local live = Engine.entries["Bestial Wrath"]
    assertNotNil(live)
    assertTrue(live.endTime <= GetTime() + 1e-6) -- landed, not lapsed-ahead
    local out = Engine:Sweep(GetTime(), {})      -- ... and it POPS
    assertEquals(1, #out)
    assertEquals("Bestial Wrath", out[1])
    assertNil(Engine.entries["Bestial Wrath"])

    local n1, b1, d1 = tiers()
    assertEquals(0, n1 - n0)  -- the numeric tier was blind the whole pass
    assertEquals(1, b1 - b0)  -- the boolean tier fired exactly once
    assertEquals(0, d1 - d0)  -- this build has no duration object
end)

-- ================================================ tier 3: the duration object --

test("Read pass: a plain duration object anchors endTime exactly and tags the source", function()
    local n0, b0, d0 = tiers()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)

    local realInfo = FX.Compat.GetSpellCooldownInfo
    local realCharges = FX.Compat.GetSpellCharges
    local realDur = FX.Compat.GetSpellCooldownDurationObject
    local now = GetTime()
    patchPlain()
    FX.Compat.GetSpellCooldownInfo = function(name)
        return lockdownInfo(name == "Bestial Wrath" and true, false)
    end
    FX.Compat.GetSpellCharges = secretCharges
    -- 30 s left of a 120 s window; the object's numbers are SECONDS.
    FX.Compat.GetSpellCooldownDurationObject = function(name)
        if name == "Bestial Wrath" then return durationObject(false, 30, 120) end
        return nil
    end
    Engine:OnCast("Bestial Wrath", now - 90)
    M:ReadAll()
    FX.Compat.GetSpellCooldownInfo = realInfo
    FX.Compat.GetSpellCharges = realCharges
    FX.Compat.GetSpellCooldownDurationObject = realDur
    restorePlain()

    local e = Engine.entries["Bestial Wrath"]
    assertNotNil(e)
    closeTo(e.endTime - GetTime(), 30, 0.5) -- the exact anchor, not a guess
    near(120, e.duration)
    near(e.endTime - 120, e.start)    -- start + duration == endTime
    assertEquals("duration", e.source)
    assertTrue(e.anchored)
    assertFalse(e.predicted)
    assertNil(Engine.entries["Rapid Fire"]) -- a nil object spawns nothing

    local n1, b1, d1 = tiers()
    assertEquals(0, n1 - n0)   -- the numbers stayed secret all pass
    assertEquals(0, b1 - b0)   -- active + a live entry: nothing to do
    assertEquals(1, d1 - d0)   -- tier 3 is the one that fired
end)

test("OnReadDuration counts, learns, and keeps the window model consistent", function()
    local _, _, d0 = tiers()
    local storage = freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)

    -- (a) A full total is a length: full anchor, learn it (the OnRead law).
    Engine:OnCast("Disengage", 1000)
    assertEquals("anchored", Engine:OnReadDuration("Disengage", 20, 60, 1040))
    local e = Engine.entries["Disengage"]
    near(1060, e.endTime)
    near(60, e.duration)
    near(1000, e.start)
    assertEquals("duration", e.source)
    assertTrue(e.anchored)
    assertFalse(e.predicted)
    near(60, storage["Disengage"])
    near(60, Engine:BestDuration("Disengage"))

    -- (b) The total is GCD-band noise (below MIN_COOLDOWN): only the END is
    --     fact, the window's own length absorbs the difference, and NOTHING
    --     is learned.
    wipe(Engine.entries)
    storage["Disengage"] = nil
    Engine:OnCast("Disengage", 1000)
    local e2 = Engine.entries["Disengage"]
    assertEquals("anchored", Engine:OnReadDuration("Disengage", 15, 1, 1010))
    near(1000, e2.start)                            -- start kept
    near(1025, e2.endTime)                          -- now + remaining
    near(25, e2.duration)                           -- endTime - start
    near(e2.endTime - e2.start, e2.duration)
    assertEquals("duration", e2.source)
    assertNil(storage["Disengage"])                 -- never a GCD band
    assertNil(Engine.learned["Disengage"])

    -- (c) No entry at all needs a total to have a start.
    wipe(Engine.entries)
    assertEquals("ignored", Engine:OnReadDuration("Rapid Fire", 100, nil, 2000))
    assertEquals(0, countEntries())
    assertEquals("anchored", Engine:OnReadDuration("Rapid Fire", 100, 300, 2000))
    local rf = Engine.entries["Rapid Fire"]
    assertNotNil(rf)
    near(2100, rf.endTime)
    near(300, rf.duration)
    near(1800, rf.start)
    assertEquals("duration", rf.source)
    assertTrue(rf.anchored)

    -- (d) A drained charge bar's clock follows the real end (the header's
    --     rechargeEnd mirror); the charge COUNT is not this tier's business.
    wipe(Engine.entries)
    Engine.tracked["Bestial Wrath"].maxCharges = 2
    Engine:OnCast("Bestial Wrath", 3000)
    local bar = Engine.entries["Bestial Wrath"]
    near(3120, bar.charges.nextAt)
    assertEquals(1, bar.charges.current)
    assertEquals("anchored", Engine:OnReadDuration("Bestial Wrath", 60, 120, 3060))
    near(3120, bar.charges.nextAt)
    Engine:OnReadDuration("Bestial Wrath", 40, 120, 3080)
    near(3120, bar.charges.nextAt)
    near(3120, bar.rechargeEnd)
    assertEquals(1, bar.charges.current)            -- the count is not ours
    Engine.tracked["Bestial Wrath"].maxCharges = nil

    -- (e) The values are guarded HERE too: a secret remaining is not a
    --     number, and a secret total must not be learned.
    wipe(Engine.entries)
    patchPlain()
    Engine:OnCast("Disengage", 4000)
    local endBefore = Engine.entries["Disengage"].endTime
    assertEquals("ignored", Engine:OnReadDuration("Disengage", SECRET, SECRET, 4050))
    near(endBefore, Engine.entries["Disengage"].endTime)
    assertEquals("cast", Engine.entries["Disengage"].source)
    assertNil(Engine.entries["Disengage"].anchored)
    restorePlain()

    -- (f) Zero / spent / negative remaining is not a running cooldown, and
    --     a spell we do not track is none of our business.
    wipe(Engine.entries)
    assertEquals("ignored", Engine:OnReadDuration("Disengage", 0, 120, 5000))
    assertEquals("ignored", Engine:OnReadDuration("Disengage", -5, 120, 5000))
    assertEquals("ignored", Engine:OnReadDuration("Not A Spell", 30, 120, 5000))
    assertEquals(0, countEntries())

    local _, _, d1 = tiers()
    assertEquals(0, d1 - d0) -- the counting lives in the read PASS, not in
    -- the Engine calls: only M:ReadAll bumps the counters (the tests above).
end)

test("The duration tier does nothing on a secret, absent, broken or spent object", function()
    local _, _, d0 = tiers()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    local realDur = FX.Compat.GetSpellCooldownDurationObject
    local realInfo = FX.Compat.GetSpellCooldownInfo
    local realCharges = FX.Compat.GetSpellCharges

    patchPlain()
    FX.Compat.GetSpellCooldownInfo = function() return lockdownInfo(true, false) end
    FX.Compat.GetSpellCharges = secretCharges

    local function castAndFreeze()
        wipe(Engine.entries)
        Engine:OnCast("Bestial Wrath", 1000)
        local e = Engine.entries["Bestial Wrath"]
        return e.start, e.duration, e.endTime, e.source
    end
    local function unchanged(st, du, en, src)
        local e = Engine.entries["Bestial Wrath"]
        near(st, e.start); near(du, e.duration); near(en, e.endTime)
        assertEquals(src, e.source)
        assertNil(e.anchored)
    end

    -- (1) The object says its values ARE secret: hands off entirely.
    local st, du, en, src = castAndFreeze()
    FX.Compat.GetSpellCooldownDurationObject = function()
        return durationObject(true, 30, 120)
    end
    M:ReadAll()
    unchanged(st, du, en, src)

    -- (2) No object at all (MayReturnNothing; the API is absent on this
    --     client build): nothing moves.
    FX.Compat.GetSpellCooldownDurationObject = function() return nil end
    M:ReadAll()
    unchanged(st, du, en, src)

    -- (3) A broken object: HasSecretValues answers with a SECRET value, and
    --     a raise out of GetRemainingDuration must not escape the pass.
    FX.Compat.GetSpellCooldownDurationObject = function()
        return { HasSecretValues = function() return SECRET end,
                 GetRemainingDuration = function() error("boom") end,
                 GetTotalDuration = function() error("boom") end }
    end
    M:ReadAll()
    unchanged(st, du, en, src)
    -- A method the object does not even have: the pcall absorbs it.
    FX.Compat.GetSpellCooldownDurationObject = function()
        return { HasSecretValues = function() return false end }
    end
    M:ReadAll()
    unchanged(st, du, en, src)

    -- (4) A plain object with no running time anchors NOTHING. (Every entry
    --     this pass does have comes from tier 2 -- the scripted pair says
    --     `isActive = true` for every tracked spell and the entries table was
    --     wiped, so the edge fallback legitimately populates it. The claim
    --     here is that not one of them is a duration anchor.)
    FX.Compat.GetSpellCooldownDurationObject = function()
        return durationObject(false, 0, 120)
    end
    wipe(Engine.entries)
    M:ReadAll()
    local anchored = 0
    for _, entry in pairs(Engine.entries) do
        if entry.source == "duration" then anchored = anchored + 1 end
    end
    assertEquals(0, anchored)
    assertTrue(countEntries() > 0) -- the boolean tier did its job

    FX.Compat.GetSpellCooldownDurationObject = realDur
    FX.Compat.GetSpellCooldownInfo = realInfo
    FX.Compat.GetSpellCharges = realCharges
    restorePlain()
    local _, _, d1 = tiers()
    assertEquals(0, d1 - d0) -- not one of them counted as a firing
end)

test("The duration object contract is SECONDS (measured against the sim's real object)", function()
    -- The pinned catalog types GetRemainingDuration/GetTotalDuration as
    -- `Seconds` and GetStartTime/GetEndTime as FrameTime
    -- (@LuaDurationObjectAPIDocumentation.lua:270/:318/:302) -- the scale the
    -- entry model lives on. The sim ships C_DurationUtil, so the method NAMES
    -- and the unit are measured on a real object, not a stand-in.
    assertNotNil(_G.C_DurationUtil)
    assertNotNil(C_DurationUtil.CreateDuration)
    local dur = C_DurationUtil.CreateDuration()
    assertNotNil(dur)
    assertEquals(false, dur:HasSecretValues()) -- plain metadata, ReturnsNeverSecret
    local now = GetTime()
    dur:SetTimeFromStart(now - 70, 100, 1)      -- 30 s left of a 100 s window
    near(100, dur:GetTotalDuration())          -- SECONDS, not ms
    assertTrue(dur:GetRemainingDuration() > 28 and dur:GetRemainingDuration() < 32)
    near(now - 70, dur:GetStartTime())         -- FrameTime == GetTime() units

    local _, _, d0 = tiers()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)
    local realDur = FX.Compat.GetSpellCooldownDurationObject
    patchPlain()
    FX.Compat.GetSpellCooldownDurationObject = function(name)
        if name == "Bestial Wrath" then return dur end
        return nil
    end
    Engine:OnCast("Bestial Wrath", now - 70)
    M:ReadAll()
    FX.Compat.GetSpellCooldownDurationObject = realDur
    restorePlain()

    local e = Engine.entries["Bestial Wrath"]
    assertNotNil(e)
    assertEquals("duration", e.source)
    near(100, e.duration)                       -- the object's total, as-is
    near(e.endTime - e.start, e.duration)
    assertTrue(e.endTime - GetTime() > 28 and e.endTime - GetTime() < 32)
    local _, _, d1 = tiers()
    assertEquals(1, d1 - d0)
end)

-- ==================================================== FX.SecretState + wiring --

test("SecretState caches the six restriction types and the two predicates", function()
    -- The wow-ui-sim build ships neither C_RestrictedActions nor C_Secrets
    -- (measured 2026-11-02), so with no seam every field must land nil =
    -- UNKNOWN, and the queries themselves are driven through the documented
    -- `readers` seam.
    SS.combat, SS.encounter, SS.challenge, SS.pvp, SS.map, SS.chat = nil, nil, nil, nil, nil, nil
    SS.cooldownsSecret, SS.aurasSecret = nil, nil
    SS.Refresh()
    assertNil(SS.combat)
    assertNil(SS.encounter)
    assertNil(SS.challenge)
    assertNil(SS.pvp)
    assertNil(SS.map)
    assertNil(SS.chat)
    assertNil(SS.cooldownsSecret)
    assertNil(SS.aurasSecret)
    assertFalse(SS.CooldownReadsAreSecret()) -- unknown is never a licence

    local seen = {}
    SS.Refresh({
        isActive = function(t)
            seen[#seen + 1] = t
            return t == 0 -- the enum's Combat slot is the active one
        end,
        cooldownsSecret = function() return true end,
        aurasSecret = function() return false end,
    })
    -- The six AddOnRestrictionType values, in the enum's order.
    assertEquals("0,1,2,3,4,5", table.concat(seen, ","))
    assertTrue(SS.combat)
    assertFalse(SS.encounter)
    assertFalse(SS.challenge)
    assertFalse(SS.pvp)
    assertFalse(SS.map)
    assertFalse(SS.chat)
    assertTrue(SS.cooldownsSecret)
    assertFalse(SS.aurasSecret)
    assertTrue(SS.CooldownReadsAreSecret())

    -- A raise (a restricted client) and a secret answer are both UNKNOWN --
    -- never a false "all plain".
    SS.combat, SS.encounter, SS.cooldownsSecret = nil, nil, nil
    patchPlain()
    SS.Refresh({
        isActive = function(t)
            if t == 0 then error("restricted") end
            if t == 1 then return SECRET end
            return false
        end,
        cooldownsSecret = function() return SECRET end,
    })
    restorePlain()
    assertNil(SS.combat)
    assertNil(SS.encounter)
    assertNil(SS.cooldownsSecret)

    -- One line, the four probe columns; nil is the honest "no answer".
    SS.combat, SS.encounter, SS.cooldownsSecret, SS.aurasSecret = true, false, true, nil
    assertEquals("secret-state: combat=true encounter=false cooldowns=true auras=nil",
        SS.StatusLine())
end)

test("SecretState refreshes on each mode event (the module's own registrations)", function()
    assertNotNil(M._eventFrame) -- bound at PLAYER_LOGIN, inside OnEnable
    local handler = M._eventFrame:GetScript("OnEvent")
    assertEquals("function", type(handler))
    SS.cooldownsSecret = nil
    local realRefresh = SS.Refresh
    local calls = 0
    SS.Refresh = function() calls = calls + 1; return SS end

    -- The three events the design note prescribes. ADDON_RESTRICTION_STATE_
    -- CHANGED's (type, state) payload rides the handler's generic slots and
    -- is ignored: the queries answer the question directly.
    handler(M._eventFrame, "ADDON_RESTRICTION_STATE_CHANGED", 0, 2)
    assertEquals(1, calls)
    handler(M._eventFrame, "PLAYER_REGEN_DISABLED")
    assertEquals(2, calls)
    handler(M._eventFrame, "PLAYER_REGEN_ENABLED")
    assertEquals(3, calls) -- out of combat: refresh AND the re-anchoring pass

    -- An unrelated event does not refresh.
    handler(M._eventFrame, "SPELLS_CHANGED")
    assertEquals(3, calls)
    SS.Refresh = realRefresh
end)

test("SecretState skips the numeric reads only: the boolean and duration tiers still run", function()
    local n0, b0, d0 = tiers()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)
    local realInfo = FX.Compat.GetSpellCooldownInfo
    local realCharges = FX.Compat.GetSpellCharges
    local realDur = FX.Compat.GetSpellCooldownDurationObject
    local infoCalls = 0
    patchPlain()
    FX.Compat.GetSpellCooldownInfo = function(name)
        infoCalls = infoCalls + 1
        return { startTime = GetTime() - 10, duration = 120,
                 isActive = name == "Bestial Wrath", isOnGCD = false }
    end
    FX.Compat.GetSpellCharges = function()
        return { currentCharges = 1, maxCharges = 1,
                 cooldownStartTime = 0, cooldownDuration = 0 }
    end
    FX.Compat.GetSpellCooldownDurationObject = function(name)
        if name == "Bestial Wrath" then return durationObject(false, 40, 120) end
        return nil
    end

    -- The mode says: the numbers come back secret. Tier 1 is not even asked;
    -- tier 3 (the unannotated object) is not gated by it and anchors.
    SS.cooldownsSecret = true
    M:ReadAll()
    assertEquals(0, infoCalls)
    local e = Engine.entries["Bestial Wrath"]
    assertNotNil(e)
    assertEquals("duration", e.source)
    assertTrue(e.anchored)

    -- A live entry with the numeric read skipped: the boolean tier has no
    -- voice (the read it keys on never ran) and keeps the entry.
    FX.Compat.GetSpellCooldownDurationObject = function() return nil end
    wipe(Engine.entries)
    assertNotNil(Engine:OnActiveEdge("Bestial Wrath", GetTime()))
    M:ReadAll()
    assertNotNil(Engine.entries["Bestial Wrath"])
    assertEquals("edge", Engine.entries["Bestial Wrath"].source)
    assertEquals(0, infoCalls)

    local n1, b1, d1 = tiers()
    assertTrue(d1 - d0 >= 1) -- tier 3 fired straight through the blackout
    assertEquals(0, n1 - n0) -- tier 1 never got a chance
    assertEquals(0, b1 - b0) -- and the pair of a skipped read cannot fire

    -- Unknown (nil) asks everything: the mode may save work, never skip on a
    -- guess -- a plain numeric read that does arrive is never discarded.
    SS.cooldownsSecret = nil
    M:ReadAll()
    assertTrue(infoCalls > 0)
    FX.Compat.GetSpellCooldownInfo = realInfo
    FX.Compat.GetSpellCharges = realCharges
    FX.Compat.GetSpellCooldownDurationObject = realDur
    restorePlain()
end)

-- ============================================================ the /fx status --

test("The numeric column counts a plain read that moves state, not a no-op", function()
    -- The launch-day line needs a trustworthy numeric column: it counts the
    -- passes where tier 1 actually re-anchored (or retired a live entry), not
    -- the ~40 no-op "ready, nothing tracked" reads a second of 1 Hz produces.
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    wipe(Engine.entries)
    local realInfo = FX.Compat.GetSpellCooldownInfo
    local realCharges = FX.Compat.GetSpellCharges
    local now = GetTime()
    local function readyForAll()
        return { startTime = 0, duration = 0, isActive = false, isOnGCD = false }
    end
    FX.Compat.GetSpellCharges = function()
        return { currentCharges = 1, maxCharges = 1,
                 cooldownStartTime = 0, cooldownDuration = 0 }
    end

    -- Phase 1: every spell ready, nothing tracked -- pure no-op reads.
    FX.Compat.GetSpellCooldownInfo = readyForAll
    local t0 = M._readTiers.numeric
    M:ReadAll()
    assertEquals(0, M._readTiers.numeric - t0)

    -- Phase 2: the same ready read over a live prediction retires it: that
    -- IS the tier firing.
    Engine:OnCast("Bestial Wrath", now - 100) -- outside the read-lag grace
    t0 = M._readTiers.numeric
    M:ReadAll()
    assertEquals(1, M._readTiers.numeric - t0)

    FX.Compat.GetSpellCooldownInfo = realInfo
    FX.Compat.GetSpellCharges = realCharges
    wipe(Engine.entries)
end)

test("/fx status prints the secret-state line and the readTiers counters", function()
    M:InitReadTiers()
    if FX.db then
        assertEquals(FX.db.diag.readTiers, M._readTiers) -- the live table
    end
    local t = M._readTiers
    local joined = table.concat(statusLines(), "\n")
    assertContains(joined, "secret-state: combat=")
    assertContains(joined, string.format(
        "readTiers: numeric %d | boolean %d | duration %d",
        t.numeric, t.boolean, t.duration))

    -- The live counters reach the line.
    t.numeric, t.boolean, t.duration = t.numeric + 3, t.boolean + 1, t.duration + 2
    local again = table.concat(statusLines(), "\n")
    assertContains(again, string.format(
        "readTiers: numeric %d | boolean %d | duration %d",
        t.numeric, t.boolean, t.duration))
    t.numeric, t.boolean, t.duration = t.numeric - 3, t.boolean - 1, t.duration - 2
end)

-- Registered last => runs last: hand the module's storage, cast diag, the mode
-- cache and the engine state back, and leave the engine empty for anything
-- that runs after this file.
test("Restore module storage, mode cache and engine state", function()
    restorePlain()
    Engine:AttachStorage(originalStorage)
    wipe(Engine.tracked)
    wipe(Engine.entries)
    if FX.db then FX.db.diag.casts = savedDbDiag end
    M:InitCastDiag()
    for _, spec in ipairs(SS.RESTRICTION_TYPES) do SS[spec.field] = savedMode[spec.field] end
    SS.cooldownsSecret, SS.aurasSecret = savedMode.cooldownsSecret, savedMode.aurasSecret
    assertEquals(originalStorage, Engine.learned)
end)
