-- addon/Forte_Hunter/tests/test_hunter.lua
-- wow-ui-sim tests for Core/Tools.lua: the aspect tracker and the ranged
-- swing / Auto Shot timer. All clocks, combat flags, aura reads and speed
-- reads are INJECTED -- no real time, no combat driving.
--
-- Secret-read note: the sim exposes no control to force a secret value
-- from the unit/aura APIs, so secret paths are exercised at the exact
-- downstream contract -- every live read passes FX.Compat.PlainOrNil first,
-- so a secret arrives as nil, which is exactly what the fakes return. The
-- live API usage itself is proven by the catalog audit in
-- docs/hunter-tools.md and by this addon loading in the sim without
-- Forte_* lua errors.

local FX = ForteXorcist
local Tools = FX.Hunter.Tools

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

-- 1. The aspect list is DERIVED from the generated data, never hand-typed.
test("aspect list equals the data's ^Aspect of names", function()
    local derived = {}
    for _, name in ipairs(Tools.aspectNames) do derived[name] = true end
    local n = 0
    for _, spell in pairs(FX.Data.Hunter) do
        local name = spell.name
        if name and name:find("^Aspect of") then
            n = n + 1
            assertNotNil(derived[name]) -- every data aspect is in the list
        end
    end
    assertTrue(n > 0)
    assertEquals(n, #Tools.aspectNames) -- and the list carries no extras
    -- Stable, sorted order (deterministic reconcile sequence).
    for i = 2, #Tools.aspectNames do
        assertTrue(Tools.aspectNames[i - 1] <= Tools.aspectNames[i])
    end
    -- Spot-check known names (spells, never IDs).
    assertNotNil(derived["Aspect of the Hawk"])
    assertNotNil(derived["Aspect of the Cheetah"])
    -- Non-aspect names never enter the list.
    assertNil(derived["Hunter's Mark"])
    assertNil(derived["Trueshot Aura"])
end)

-- 2. Cast prediction: aspects are mutually exclusive.
test("cast sets current, a second cast replaces it, non-aspect ignored", function()
    local t = FX.Hunter.NewAspectTracker({
        names = Tools.aspectNames,
        inCombat = function() return false end,
    })
    assertNil(t:Current())
    assertTrue(t:OnCast("Aspect of the Hawk"))
    assertEquals("Aspect of the Hawk", t:Current())
    assertTrue(t:OnCast("Aspect of the Cheetah"))
    assertEquals("Aspect of the Cheetah", t:Current())
    assertFalse(t:OnCast("Hunter's Mark"))
    assertEquals("Aspect of the Cheetah", t:Current())
    assertFalse(t:OnCast(nil))
    assertEquals("Aspect of the Cheetah", t:Current())
    local snap = t:Snapshot()
    assertEquals("Aspect of the Cheetah", snap.current)
    assertEquals(#Tools.aspectNames, #snap.aspects)
    assertFalse(snap.missing)
end)

-- 3. Reconcile: a plain read corrects a wrong prediction.
test("reconcile adopts a read aspect, replacing the prediction", function()
    local t = FX.Hunter.NewAspectTracker({
        names = Tools.aspectNames,
        inCombat = function() return false end,
    })
    t:OnCast("Aspect of the Hawk") -- a wrong prediction
    -- Plain reads: Hawk absent, Falcon present.
    local result = t:Reconcile(function(name)
        if name == "Aspect of the Falcon" then return true end
        return false
    end)
    assertEquals("adopted", result)
    assertEquals("Aspect of the Falcon", t:Current())
end)

test("reconcile clears when every aspect is confirmed absent", function()
    local t = FX.Hunter.NewAspectTracker({
        names = Tools.aspectNames,
        inCombat = function() return false end,
    })
    t:OnCast("Aspect of the Monkey")
    local result = t:Reconcile(function() return false end) -- all plain-absent
    assertEquals("cleared", result)
    assertNil(t:Current())
end)

-- 4. Secret-read tolerance: nil (secret) reads never touch the state.
test("secret (nil) reads leave the tracker unchanged", function()
    local t = FX.Hunter.NewAspectTracker({
        names = Tools.aspectNames,
        inCombat = function() return false end,
    })
    t:OnCast("Aspect of the Viper")
    -- No read is reliable (the in-combat reality): nothing known present,
    -- not everything known absent -- the prediction survives untouched.
    local result = t:Reconcile(function() return nil end)
    assertEquals("unchanged", result)
    assertEquals("Aspect of the Viper", t:Current())
    -- A reader that RAISES is an unreliable read too, not a clear.
    result = t:Reconcile(function() error("restricted", 0) end)
    assertEquals("unchanged", result)
    assertEquals("Aspect of the Viper", t:Current())
    -- Unknown reads must not clear even when the rest read absent.
    result = t:Reconcile(function(name)
        if name == Tools.aspectNames[1] then return nil end
        return false
    end)
    assertEquals("unchanged", result)
    assertEquals("Aspect of the Viper", t:Current())
end)

-- 5. Missing() = reminder predicate.
test("Missing is false in combat, true out of combat with none", function()
    local inCombat = false
    local t = FX.Hunter.NewAspectTracker({
        names = Tools.aspectNames,
        inCombat = function() return inCombat end,
    })
    assertTrue(t:Missing()) -- out of combat, nothing known active
    inCombat = true
    assertFalse(t:Missing()) -- in combat: never nag, we cannot read
    inCombat = false
    t:OnCast("Aspect of the Wild")
    assertFalse(t:Missing()) -- an aspect is tracked -- no reminder
    inCombat = true
    assertFalse(t:Missing())
end)

-- 6. Ranged swing timer geometry, injected clock. Payload contract
-- verified from the catalog: PLAYER_SWING = (swingDuration, swingType)
-- DURATION FIRST; the Ranged enum value is 2.
test("swing progress: 0 at start, 0.5 mid, nil after, OnSwingStart restarts", function()
    local now = 1000
    local sw = FX.Hunter.NewSwingTracker({
        now = function() return now end,
        speedReader = function() return nil end,
        rangedType = 2,
    })
    assertNil(sw:Progress()) -- idle
    sw:OnSwingStart(2.0, 2)
    local fraction, remaining = sw:Progress()
    near(0, fraction)
    near(2.0, remaining)
    now = 1001
    fraction, remaining = sw:Progress()
    near(0.5, fraction)
    near(1.0, remaining)
    now = 1001.8
    fraction = sw:Progress()
    near(0.9, fraction)
    now = 1002 -- completes exactly at start + duration
    assertNil(sw:Progress())
    assertNil(sw:Progress()) -- stays idle after completion
    -- A new swing restarts the window.
    sw:OnSwingStart(2.0, 2)
    fraction, remaining = sw:Progress()
    near(0, fraction)
    near(2.0, remaining)
    now = 1003
    fraction = sw:Progress()
    near(0.5, fraction)
end)

test("swing ignores non-ranged swing types; range rules follow the contract", function()
    local sw = FX.Hunter.NewSwingTracker({
        now = function() return 100 end,
        speedReader = function() return 1.5 end,
        rangedType = 2,
    })
    -- MainHand (0) and OffHand (1) swings must not drive the ranged timer.
    sw:OnSwingStart(2.0, 0)
    sw:OnSwingStart(2.0, 1)
    assertNil(sw:Progress())
    -- Out-of-range for the MAIN HAND must not cancel the ranged timer.
    sw:OnSwingStart(2.0, 2)
    near(0, sw:Progress())
    sw:OnSwingRange(0, false, true)
    near(0, sw:Progress())
    -- checksRange false: isInRange is meaningless; the timer keeps running.
    sw:OnSwingRange(2, false, false)
    near(0, sw:Progress())
    -- In range: a no-op (no swing starts from the range event alone).
    sw:OnSwingRange(2, true, true)
    near(0, sw:Progress())
    -- Out-of-range for RANGED with an active check stops it.
    sw:OnSwingRange(2, false, true)
    assertNil(sw:Progress())
end)

-- 7. Speed fallback chain: event duration -> speed read (live:
-- UnitRangedDamage/UnitAttackSpeed) -> last observed duration.
test("secret speed falls back to the last observed duration", function()
    local now = 500
    local speedAvailable = true
    local sw = FX.Hunter.NewSwingTracker({
        now = function() return now end,
        speedReader = function()
            if speedAvailable then return 2.0 end
            return nil -- the secret-read shape
        end,
        rangedType = 2,
    })
    -- Secret (nil) event duration, readable speed: the speed wins.
    sw:OnSwingStart(nil, 2)
    near(0, sw:Progress())
    now = 501 -- half of the 2.0 s read
    near(0.5, sw:Progress())
    now = 502
    assertNil(sw:Progress())
    -- Speed read goes secret too -> the last observed duration is used.
    speedAvailable = false
    sw:OnSwingStart(nil, 2)
    near(0, sw:Progress())
    now = 503 -- half of the remembered 2.0
    near(0.5, sw:Progress())
end)

test("with no speed knowledge at all the swing stays idle", function()
    local sw = FX.Hunter.NewSwingTracker({
        now = function() return 7 end,
        speedReader = function() return nil end, -- secret/absent
        rangedType = 2,
    })
    sw:OnSwingStart(nil, 2) -- secret duration, secret speed, no history
    assertNil(sw:Progress())
    local snap = sw:Snapshot()
    assertFalse(snap.active)
    assertNil(snap.duration)
end)

-- 8. Auto Shot cast-event fallback (PLAN §8 Auto Shot model: PLAYER_SWING
-- has declaration-only evidence for third-party addons; the live probe
-- answers it -- docs/hunter-tools.md).
test("Auto Shot cast starts the timer from the speed read; last-known fallback", function()
    local now = 100
    local speed = 1.5
    local sw = FX.Hunter.NewSwingTracker({
        now = function() return now end,
        speedReader = function() return speed end,
        rangedType = 2,
    })
    sw:OnCast("Auto Shot")
    near(0, sw:Progress())
    now = 100.75
    near(0.5, sw:Progress())
    now = 101.5
    assertNil(sw:Progress())
    -- Speed read goes secret mid-fight: the last observed speed is used.
    speed = nil
    sw:OnCast("Auto Shot")
    near(0, sw:Progress())
    now = 102.25
    near(0.5, sw:Progress())
    now = 103.5
    assertNil(sw:Progress())
    -- Other casts never touch the swing.
    sw:OnCast("Auto Shot")
    local before = sw:Progress()
    sw:OnCast("Kill Shot")
    near(before, sw:Progress())
end)

-- 9. Module wiring sanity: registration is load-time; frame creation is
-- OnEnable-gated by class; Status() carries the module line.
test("module registered, Status string shape", function()
    assertNotNil(FX.modules["Hunter"])
    assertEquals(Tools, FX.modules["Hunter"])
    local status = Tools:Status()
    assertContains(status, "Hunter:")
    assertContains(status, "aspects")
    assertContains(status, "ranged swing")
    assertContains(status, "idle")
    -- Aspect + swing state appear once set.
    local savedAspectCurrent = Tools.Aspects:Current()
    Tools.Aspects:OnCast(Tools.aspectNames[1])
    assertContains(Tools:Status(), Tools.aspectNames[1])
    Tools.Aspects:Reconcile(function() return false end) -- restore
    assertEquals(savedAspectCurrent, Tools.Aspects:Current())
end)
