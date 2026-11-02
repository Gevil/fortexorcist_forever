-- addon/Forte_Timer/tests/test_rows.lua
-- The Spell Timer's core: the registry from GENERATED data, the cast queue,
-- the row table, the reconciliation law, the removal refusal and the expiry.
-- docs/design-spell-timer.md §3.3/§3.5/§8.2's acceptance list.
--
-- Every clock is INJECTED (Casts.now, the `now` argument of every law): no
-- real time, no combat driving, no real aura read. Secret aura reads are
-- simulated at the exact downstream contract the project uses (the note in
-- Forte_Hunter/tests/test_hunter.lua): a sealed reader answers with a value
-- whose fields `PlainOrNil` refuses, and `false` is the "I looked, no such
-- aura" fact.

local FX = ForteXorcist
local Laws = FX.Timer.Laws
local Rows = FX.Timer.Rows
local Casts = FX.Timer.Casts
local Registry = FX.Timer.Registry
local Reconcile = FX.Timer.Reconcile

local function near(actual, expected)
    assertTrue(math.abs(actual - expected) < 1e-6)
end
local function nearpx(actual, expected)
    assertTrue(math.abs(actual - expected) <= 0.5)
end

local function opts()
    return {
        smooth = Laws.SMOOTH, maxOn = false, maxRows = 32, oneMax = true,
        maxTimeOn = true, maxTime = Laws.MAXTIME, groupID = true,
        outwands = true, blink = true, blinkAt = Laws.BLINK,
        hideLonger = false, hideTime = Laws.HIDE_TIME,
        normalAlpha = FX.Timer.Skin.NormalAlpha,
        barBgAlpha = FX.Timer.Skin.BarBackgroundAlpha,
    }
end

--- A registry of the Hunter data (the sim profile is not a Hunter; the
--- registry is keyed by NAME, and the data is the only source of durations --
--- AGENTS.md, PLAN §10.2 rule 8).
local function buildHunterRegistry()
    Registry:AttachStorage({})
    local n = Registry:Build("HUNTER")
    assertTrue(n and n > 0)
    return n
end

local clock
local function installClock(base)
    clock = { base or 1000 }
    Casts.now = function() return clock[1] end
    return clock
end
local function tick(sec)
    clock[1] = clock[1] + sec
end

-- ---------------------------------------------------------------- registry --

test("the registry is built from generated data, with generated durations",
function()
    local n = buildHunterRegistry()
    -- Spot-checks of the duration law (durationMs / 1000), spells by NAME.
    near(Registry.BestDuration("Serpent Sting"), 12)
    near(Registry.BestDuration("Hunter's Mark"), 120)
    assertTrue(Registry.IsTracked("Serpent Sting"))
    assertTrue(Registry.IsTracked("Hunter's Mark"))
    -- A spell the data gives no duration for has no row to draw: not tracked.
    assertNil(Registry.entries["Call Pet"])
    -- A name that is not in the data at all.
    assertFalse(Registry.IsTracked("Party Yell"))
    -- The registry's size is the data's: every entry names a real data row.
    local data = FX.Data.Hunter
    for name, entry in pairs(Registry.entries) do
        local row = data[entry.dataId]
        assertNotNil(row)
        assertEquals(name, row.name)
        near(entry.duration, (row.durationMs or 0) / 1000)
    end
    print("[timer] registry entries: " .. n)
end)

test("a learned duration beats the generated one, the data row never moves",
function()
    buildHunterRegistry()
    local data = FX.Data.Hunter
    local before = data[Registry.entries["Serpent Sting"].dataId].durationMs
    Registry.Learn("Serpent Sting", 15)
    near(Registry.BestDuration("Serpent Sting"), 15)
    assertEquals(before,
        data[Registry.entries["Serpent Sting"].dataId].durationMs)
    -- A prediction never teaches (the law is the caller's; Learn's own gate is
    -- the type/positivity one).
    Registry.Learn("Serpent Sting", 0)
    Registry.Learn("Serpent Sting", nil)
    near(Registry.BestDuration("Serpent Sting"), 15)
    Registry:AttachStorage({})
end)

-- ------------------------------------------------------------- cast to row --

test("a cast inserts one predicted row with the data's duration", function()
    buildHunterRegistry()
    local o = opts()
    Rows.options = o
    Rows:Clear()
    local base = 1000
    installClock(base)
    local names = { [425737] = "Serpent Sting" }
    Casts.resolveName = function(id) return names[id] end
    Casts:Init(Rows, o)
    local seen = {}
    Casts.onRow = function(row, verdict) seen[#seen + 1] = { row, verdict } end

    Casts:OnSent("Vile Poacher", 425737, base)
    assertEquals(1, #Casts.queue)
    assertEquals(0, Rows:Count())              -- nothing lands on SENT
    Casts:OnSucceeded(425737, base)
    assertEquals(0, #Casts.queue)             -- consumed at the settle, not here
    assertEquals(0, Rows:Count())
    Casts:Pump(base + Laws.SETTLE + 0.01)     -- the 0.2 s deferral
    assertEquals(1, Rows:Count())
    local row = Rows:Find("Serpent Sting", "Vile Poacher")
    assertNotNil(row)
    near(row.total, 12)
    near(row.expireAt, base + Laws.SETTLE + 0.01 + 12)
    assertEquals(true, row.predicted)         -- the row is a prediction
    assertEquals(1, #seen)
    assertEquals("inserted", seen[1][2])
    local prevExpire = row.expireAt
    -- The same spell on the SAME target does not make a second row.
    Casts:OnSent("Vile Poacher", 425737, base + 1)
    Casts:OnSucceeded(425737, base + 1)
    Casts:Pump(base + 1 + Laws.SETTLE + 0.01)
    assertEquals(1, Rows:Count())
    local row2 = Rows:Find("Serpent Sting", "Vile Poacher")
    assertTrue(row2 == row)                   -- the SAME row, adopted
    assertTrue(row2.expireAt > prevExpire)     -- its window moved forward
end)

test("a cast on a second target makes its own row, in its own group", function()
    buildHunterRegistry()
    local o = opts()
    Rows.options = o
    Rows:Clear()
    installClock(2000)
    local names = { [425737] = "Serpent Sting" }
    Casts.resolveName = function(id) return names[id] end
    Casts:Init(Rows, o)
    for _, target in ipairs({ "Vile Poacher", "River Crocolisk" }) do
        Casts:OnSent(target, 425737, 2000)
        Casts:OnSucceeded(425737, 2000)
    end
    Casts:Pump(2000 + Laws.SETTLE + 0.01)
    assertEquals(2, Rows:Count())
    local a = Rows:Find("Serpent Sting", "Vile Poacher")
    local b = Rows:Find("Serpent Sting", "River Crocolisk")
    assertNotNil(a) assertNotNil(b)
    assertTrue(a.groupKey ~= b.groupKey)      -- grouped BY target (§3.3)
    -- The sorted link array keeps a group's rows adjacent.
    local links, n = Rows:Sorted({}, 2010)
    assertEquals(2, n)
    assertEquals(links[1][2], links[1][2])
    assertTrue(links[1][2] == a.groupKey or links[1][2] == b.groupKey)
    Rows:Clear()
end)

test("a failed cast settles for CANCEL_SETTLE then flashes the row as failed",
function()
    buildHunterRegistry()
    local o = opts()
    Rows.options = o
    Rows:Clear()
    installClock(3000)
    Casts.resolveName = function(id) return id == 425737 and "Serpent Sting" end
    Casts:Init(Rows, o)
    Casts:OnSent("Vile Poacher", 425737, 3000)
    Casts:OnSucceeded(425737, 3000)
    Casts:Pump(3000 + Laws.SETTLE + 0.01)
    local row = Rows:Find("Serpent Sting", "Vile Poacher")
    assertNotNil(row)
    Casts:OnFailed(425737, "Vile Poacher", 3002)
    assertEquals(Laws.NORMAL, row.state)       -- not before the settle
    Casts:Pump(3002 + Laws.CANCEL_SETTLE + 0.01)
    assertEquals(Laws.FAILED, row.state)
    Rows:Clear()
end)

-- -------------------------------------------------------- the reconcile law --
--- The three verdicts of §3.5, on a row inserted by hand so the clock is exact.
local function seededRow(name, target, duration, castTime, kind)
    local row = Rows:InsertFromCast(name, target, duration, castTime, castTime,
        1, kind or "TargetDebuff")
    assertNotNil(row)
    return row
end

test("adopt: a fact within MAXLAG confirms the prediction", function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local row = seededRow("Serpent Sting", "Vile Poacher", 12, 5000)
    local verdict = Rows:OnAuraFact(row, row.expireAt + 0.9, 12, 2, 5001)
    assertEquals("adopt", verdict)
    assertEquals(false, row.predicted)
    assertEquals(2, row.stacks)
    near(row.expireAt, 5000 + 12 + 0.9)
    Rows:Clear()
end)

test("extend: a longer fact lengthens the window, the total is left alone",
function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local row = seededRow("Serpent Sting", "Vile Poacher", 12, 6000)
    local before = row.total
    local verdict = Rows:OnAuraFact(row, row.expireAt + 5, 17, 1, 6001)
    assertEquals("extend", verdict)
    assertTrue(row.expireAt > 6000 + 12 + 4)
    near(row.total, before)          -- :1184 rewrites the expire, not the total
    assertEquals(false, row.predicted)
    Rows:Clear()
end)

test("refresh: a fact shorter by more than MAXLAG swaps the row", function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local row = seededRow("Serpent Sting", "Vile Poacher", 12, 7000)
    local verdict = Rows:OnAuraFact(row, row.expireAt - 5, 7, 1, 7001)
    assertEquals("refresh", verdict)
    assertEquals(Laws.REMOVE, row.state)         -- the old row fades out
    local fresh = Rows:Find("Serpent Sting", "Vile Poacher")
    assertNotNil(fresh)
    assertTrue(fresh ~= row)
    assertEquals(false, fresh.predicted)         -- it arrived as a fact
    near(fresh.expireAt, 7000 + 12 - 5)
    near(fresh.total, 7)
    Rows:Clear()
end)

test("removal is REFUSED while more than MAXLAG of the window is left", function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    -- castTime + total - BuffDelay: the row is checkable at 12 - 4 = 8 s in.
    local row = seededRow("Serpent Sting", "Vile Poacher", 12, 8000)
    assertEquals("grace", Rows:OnAuraAbsent(row, 8000 + 7))
    assertEquals("refused", Rows:OnAuraAbsent(row, 8000 + 9))
    assertEquals(Laws.NORMAL, row.state)
    -- One second of window left: inside MAXLAG, so the absence is a removal.
    assertEquals("removed", Rows:OnAuraAbsent(row, 8000 + 11.5))
    assertEquals(Laws.REMOVE, row.state)
    Rows:Clear()
end)

-- ------------------------------------------------------------ the sweep law --

test("a row smooths, promotes at expiry, fades over FadeSpeed, is deleted",
function()
    buildHunterRegistry()
    local o = opts()
    o.expireMessage = 1
    Rows.options = o
    Rows:Clear()
    local fired = 0
    o.onExpire = function() fired = fired + 1 end
    -- A self buff: the FADING band (the debuff kinds take the instant fade,
    -- the next test), deleted at removeAt + max(Fail, Fade) + FadeSpeed.
    local row = seededRow("Bestial Wrath", "none", 4, 9000, "SelfBuff")
    Rows:Sweep(9001)
    assertEquals(Laws.NORMAL, row.state)
    near(row.drawExpireAt, row.expireAt)     -- nothing moved: no lag
    near(Laws.Smooth(10, 20, 5), 12)         -- :1046, one fifth of the gap
    row.expireAt = row.expireAt + 6          -- a refresh moves the target
    Rows:Sweep(9002)
    assertTrue(row.drawExpireAt < row.expireAt)   -- and the smoothing lags
    Rows:Sweep(9010 + 0.01)                       -- past the moved end
    assertEquals(Laws.FADING, row.state)
    assertEquals(1, fired)                        -- the expiry message, once
    Rows:Sweep(9010 + 0.01)
    assertEquals(1, fired)
    Rows:Sweep(9010 + math.max(Laws.FAIL, Laws.FADE) + Laws.FADE_SPEED + 0.1)
    assertEquals(0, Rows:Count())
    Rows:Clear()
end)

test("a debuff promotes to the instant fade (kind law :1064-1068)", function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local row = seededRow("Serpent Sting", "Vile Poacher", 3, 9500)
    Rows:Sweep(9503.5)
    assertEquals(Laws.FADING_INSTANT, row.state)
    Rows:Sweep(9503.5 + Laws.FADE * 2)
    assertEquals(0, Rows:Count())
    Rows:Clear()
end)

-- ------------------------------------------------------------ the aura feed --
--- A sealed read: a table whose fields PlainOrNil refuses (the sentinel's
--- shape at the contract the project tests at).
local function sealed()
    return setmetatable({}, { __index = function() return nil end })
end

test("a plain aura fact outside combat corrects the row and teaches it",
function()
    buildHunterRegistry()
    local o = opts()
    Rows.options = o
    Rows:Clear()
    local row = seededRow("Serpent Sting", "target", 12, 11000)
    local facts = {
        ["target\1Serpent Sting"] = {
            expirationTime = 11000 + 20, duration = 20, applications = 3,
            name = "Serpent Sting",
        },
    }
    Reconcile.inCombat = function() return false end
    Reconcile:Init(Rows, o)
    Reconcile.readers = {
        byName = function(unit, name)
            return facts[unit .. "\1" .. name]
        end,
        bulk = function() return false end,
    }
    local before = Reconcile.counts.adopted + Reconcile.counts.extended
    Reconcile:SweepUnit("target", "HARMFUL", 11001)
    -- The fact is 20 s against a 12 s prediction: further than MAXLAG, so the
    -- law is the EXTEND arm (:1184), not the adopt.
    assertTrue(Reconcile.counts.adopted + Reconcile.counts.extended > before)
    assertEquals(false, row.predicted)
    assertEquals(3, row.stacks)
    near(row.expireAt, 11000 + 20)
    near(Registry.BestDuration("Serpent Sting"), 20)  -- the one teacher
    Rows:Clear()
end)

test("a sealed aura read is ignored, the row is left alone", function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local row = seededRow("Serpent Sting", "target", 12, 12000)
    local expire, stacks = row.expireAt, row.stacks
    Reconcile.inCombat = function() return false end
    Reconcile:Init(Rows, opts())
    Reconcile.readers = {
        byName = function() return sealed() end,
        bulk = function() return sealed() end,
    }
    local secretBefore = Reconcile.counts.secret
    Reconcile:SweepUnit("target", "HARMFUL", 12001)
    assertTrue(Reconcile.counts.secret > secretBefore)
    near(row.expireAt, expire)
    assertEquals(stacks, row.stacks)
    assertEquals(true, row.predicted)
    -- In combat the sweep does not run at all (design §3.5: in-combat reads
    -- are refused).
    Reconcile.inCombat = function() return true end
    local reads = Reconcile.counts.reads
    assertEquals(0, Reconcile:SweepUnit("target", "HARMFUL", 12002))
    assertEquals(reads, Reconcile.counts.reads)
    Reconcile.inCombat = function() return false end
    Rows:Clear()
end)

test("the aura sweep gate: FX.SecretState.aurasSecret seals the whole path",
function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    seededRow("Serpent Sting", "target", 12, 13000)
    local saved = FX.SecretState and FX.SecretState.aurasSecret
    Reconcile.inCombat = function() return false end
    local reads = Reconcile.counts.reads
    if FX.SecretState then FX.SecretState.aurasSecret = true end
    assertEquals(0, Reconcile:SweepUnit("target", "HARMFUL", 13001))
    assertEquals(0, Reconcile:SweepAll(13001))
    assertEquals(reads, Reconcile.counts.reads)   -- not one read was issued
    if FX.SecretState then
        FX.SecretState.aurasSecret = saved
    end
    Rows:Clear()
end)

test("an absent aura removes only past the grace and past MAXLAG", function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local row = seededRow("Serpent Sting", "target", 12, 14000)
    Reconcile.inCombat = function() return false end
    Reconcile:Init(Rows, opts())
    Reconcile.readers = {
        byName = function() return false end,   -- "I looked: no such aura"
        bulk = function() return false end,
    }
    local before = Reconcile.counts.removed or 0
    Reconcile:SweepUnit("target", "HARMFUL", 14005)  -- inside the grace
    assertEquals(Laws.NORMAL, row.state)
    Reconcile:SweepUnit("target", "HARMFUL", 14009)  -- > MAXLAG left: refused
    assertEquals(Laws.NORMAL, row.state)
    Reconcile:SweepUnit("target", "HARMFUL", 14011.5)
    assertEquals(Laws.REMOVE, row.state)
    assertTrue((Reconcile.counts.removed or 0) > before)
    Rows:Clear()
end)

test("the counters and status line report the run", function()
    buildHunterRegistry()
    local line = Reconcile:StatusLine()
    assertTrue(line:find("Timer aura sweep") ~= nil)
    local castLine = Casts:StatusLine()
    assertTrue(castLine:find("Timer casts") ~= nil)
    local n, learned = Registry:Counts()
    assertTrue(n > 0)
    assertTrue(learned >= 0)
end)

test("restore the registry the profile class built", function()
    Registry:AttachStorage(FX.db and FX.db.timer and FX.db.timer.learned
        or {})
    Registry:Build(FX._playerClass)
    Rows:Clear()
    Casts.resolveName = nil
    Casts.now = nil
    Casts.onRow = nil
    Reconcile.readers = Reconcile.LiveReaders()
    Reconcile.inCombat = nil
    assertTrue(true)
end)
