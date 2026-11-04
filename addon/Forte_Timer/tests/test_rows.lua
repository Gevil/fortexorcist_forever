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

test("the removal law (:1207): absent + past the grace REMOVES, the last MAXLAG is refused",
function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    -- :1186 makes the row checkable at castTime + BUFF_DELAY = 8004, and
    -- :1207 ("dont remove if only maxlag left") permits the removal while
    -- MORE than maxlag of the window is left. A 12 s window cast at 8000
    -- expires at 8012.
    local row = seededRow("Serpent Sting", "Vile Poacher", 12, 8000)
    assertEquals("grace", Rows:OnAuraAbsent(row, 8003.5))
    -- 0.5 s of window left: inside MAXLAG, natural expiry owns the row.
    -- (The inverted build removed here.)
    assertEquals("refused", Rows:OnAuraAbsent(row, 8011.5))
    assertEquals(Laws.NORMAL, row.state)
    -- 7 s left, past the grace: the absence fact is a removal. (The
    -- shadowed CheckableAt answered "grace" here -- the 12 s window hides
    -- the difference only from 8008 on, see the short-window test below.)
    assertEquals("removed", Rows:OnAuraAbsent(row, 8005))
    assertEquals(Laws.REMOVE, row.state)
    Rows:Clear()
end)

test("the grace law: CheckableAt is castTime + BUFF_DELAY for every window",
function()
    -- :1186 `(st[i][3] - st[i][1] + t) >= BuffDelay` with st[3]=total and
    -- st[1]=expireAt (= castTime + total) reduces to `t >= castTime +
    -- BUFF_DELAY`: the window's total does NOT move the grace. The shadowed
    -- second definition (castTime + total - BUFF_DELAY) answered 99 for the
    -- 3 s probe below -- a short-proc row judgable "gone" before the grace
    -- ended, the exact lag case BUFF_DELAY was measured for (:69).
    near(Laws.CheckableAt(100, 12), 104)
    near(Laws.CheckableAt(100, 3), 104)
    near(Laws.CheckableAt(100, 0), 104)
    near(Laws.CheckableAt(100, nil), 104)
    -- Behaviour on a 3 s window: the grace ends at cast+4, one second AFTER
    -- the window's own end -- the sweep never retires such a row, natural
    -- expiry owns it. The shadowed build removed it at cast+2.
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local row = seededRow("Serpent Sting", "Vile Poacher", 3, 100)
    assertEquals("grace", Rows:OnAuraAbsent(row, 102))
    assertEquals("refused", Rows:OnAuraAbsent(row, 104.5))
    assertEquals(Laws.NORMAL, row.state)
    Rows:Clear()
end)

-- ------------------------------------------------- the break site's liveness gate --
-- The original wraps its break message in `if not UnitIsDead(unit) then`
-- (`Forte_Timer.lua:1207-1211`): the row of a unit that DIED is retired
-- WITHOUT an announcement, because a CC that drops with the kill is not a
-- break. The port is `Rows:TargetIsDead` (Core/Rows.lua) in the
-- early-removal branch of `OnAuraAbsent`: the row is faded exactly as before
-- in both branches, only the FX_TIMER_BROKEN fire is conditional, and the
-- gate FAILS OPEN -- with nothing readable saying "this row's unit is the
-- dead one" the event fires as it did before the gate existed. Every fact
-- arrives through the injectable `Rows.liveness` reader (the file keeps its
-- zero-game-API law; Reconcile.LiveLiveness is its production shape, and
-- Reconcile:Init installs the same function into Rows).
--- A sealed read: a table whose fields `PlainOrNil` refuses (the sentinel's
--- shape at the contract the project tests at; the aura-feed section further
--- down declares the same helper for its own tests).
local function sealed()
    return setmetatable({}, { __index = function() return nil end })
end

local function captureBroken()
    local events = {}
    local h = FX.On(FX.EVENTS.TIMER_BROKEN, function(spell, target, kind)
        events[#events + 1] = { spell, target, kind }
    end)
    return events, h
end

--- A confirmed row on a unit token, carrying its identity anchor. Cast at
--- `base`, `duration` long: past the grace from base+4, removable while
--- more than MAXLAG of the window is left, so base+5 is a clean probe.
local function targetedRow(spell, target, duration, base, token, guid)
    local row = Rows:InsertFromAura(spell, target, base + duration,
        duration, 0, token, 0, base, guid)
    assertNotNil(row)
    return row
end

test("the liveness gate: a CC row of a DEAD target is removed with no BROKEN",
function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local GUID = "000000000000FE00\1Vile Poacher\1A"
    local row = targetedRow("Serpent Sting", "target", 12, 100, "target", GUID)
    assertEquals(GUID, row.guid, "the confirming insert stamps the identity")
    local events, h = captureBroken()
    local probe = Rows.liveness
    Rows.liveness = function(token)
        assertEquals("target", token, "the gate probes the row's own token")
        return GUID, true, false            -- UnitGUID, UnitIsDead, ghost
    end
    assertEquals("removed", Rows:OnAuraAbsent(row, 105))
    assertEquals(0, #events, "the kill is not a break")
    assertEquals(Laws.REMOVE, row.state, "the row is still retired")
    Rows.liveness = probe
    FX.Off(h)
    Rows:Clear()
end)

test("the liveness gate: the ghost half (a released spirit) is dead too",
function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local GUID = "000000000000FE00\1Player\1B"
    local row = targetedRow("Serpent Sting", "target", 12, 200, "target", GUID)
    local events, h = captureBroken()
    local probe = Rows.liveness
    Rows.liveness = function() return GUID, false, true end
    assertEquals("removed", Rows:OnAuraAbsent(row, 205))
    assertEquals(0, #events)
    Rows.liveness = probe
    FX.Off(h)
    Rows:Clear()
end)

test("the liveness gate: an ALIVE target still fires BROKEN",
function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local GUID = "000000000000FE00\1Vile Poacher\1C"
    local row = targetedRow("Serpent Sting", "target", 12, 300, "target", GUID)
    local events, h = captureBroken()
    local probe = Rows.liveness
    Rows.liveness = function() return GUID, false, false end
    assertEquals("removed", Rows:OnAuraAbsent(row, 305))
    assertEquals(1, #events, "the CC broke: the break is announced")
    assertEquals("Serpent Sting", events[1][1])
    assertEquals("target", events[1][2])
    Rows.liveness = probe
    FX.Off(h)
    Rows:Clear()
end)

test("the liveness gate: a sealed/secret GUID fails OPEN (the documented delta)",
function()
    -- The task's accepted risk: the row's identity is the key of the
    -- comparison, and a sealed identity is not a fact, so a CC-dropping kill
    -- of a sealed-identity unit announces a break the source would have
    -- muted. Both sides are covered: a sealed READ and a sealed ROW.
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local row = targetedRow("Serpent Sting", "target", 12, 400, "target",
        "000000000000FE00\1Vile Poacher\1D")
    local events, h = captureBroken()
    local probe = Rows.liveness
    Rows.liveness = function() return sealed(), true, true end
    assertEquals("removed", Rows:OnAuraAbsent(row, 405))
    assertEquals(1, #events, "a secret guid on the read side fires")
    -- A sealed ROW guid (stamp-side secret read -> nil) fails open too.
    -- A fresh (spell, target) key: the first row is still indexed (fading
    -- out), and an insert of a live key is an ADOPT, not a new row.
    local row2 = targetedRow("Hunter's Mark", "target", 12, 500, "target", nil)
    assertNil(row2.guid, "no plain identity arrives, the row carries none")
    local n = #events
    assertEquals("removed", Rows:OnAuraAbsent(row2, 505))
    assertEquals(n + 1, #events, "a secret guid on the row side fires")
    Rows.liveness = probe
    FX.Off(h)
    Rows:Clear()
end)

test("the liveness gate: the sealed-identity MODE fails open, explicitly",
function()
    -- `C_Secrets.ShouldUnitIdentityBeSecret()` is the catalog's own answer
    -- to "is the guid I am about to compare readable?" The mode may name the
    -- sealed case; it may NEVER mute a row, so a sealed mode must fire.
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local GUID = "000000000000FE00\1Vile Poacher\1E"
    local row = targetedRow("Serpent Sting", "target", 12, 600, "target", GUID)
    local events, h = captureBroken()
    local probe, savedSecrets = Rows.liveness, _G.C_Secrets
    _G.C_Secrets = { ShouldUnitIdentityBeSecret = function() return true end }
    Rows.liveness = function() return GUID, true, true end
    assertEquals("removed", Rows:OnAuraAbsent(row, 605))
    assertEquals(1, #events, "a sealed identity means the row is NOT muted")
    _G.C_Secrets = savedSecrets
    -- The same facts with the mode off (the client answers plain) are the
    -- muted case of the first test: the mode is the difference.
    local n = #events
    assertEquals("removed", Rows:OnAuraAbsent(row, 605))
    assertEquals(n, #events, "with a readable identity the dead row is muted")
    Rows.liveness = probe
    FX.Off(h)
    Rows:Clear()
end)

test("the liveness gate: no reader, an out-of-scope token, no guid -> fires",
function()
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local events, h = captureBroken()
    local probe = Rows.liveness
    -- (a) no reader at all: the client gives me nothing.
    Rows.liveness = nil
    local a = targetedRow("Serpent Sting", "target", 12, 700, "target", "G-A")
    assertEquals("removed", Rows:OnAuraAbsent(a, 705))
    assertEquals(1, #events, "no reader: the break fires as it used to")
    -- (b) a reader that says dead, on a row with NO guid: nothing to match.
    Rows.liveness = function() return "G-OTHER", true, true end
    local b = targetedRow("Serpent Sting", "target", 12, 800, "target", nil)
    local n = #events
    assertEquals("removed", Rows:OnAuraAbsent(b, 805))
    assertEquals(n + 1, #events, "an unanchored row fires")
    -- (c) a guid that is not this unit: the token moved on (a retarget).
    local c = targetedRow("Serpent Sting", "target", 12, 900, "target", "G-C")
    n = #events
    assertEquals("removed", Rows:OnAuraAbsent(c, 905))
    assertEquals(n + 1, #events, "a moved-on token fires")
    -- (d) the token is not a unit Rows may read: a cast-target string, and a
    -- party/raid target (out of scope -- Rows has no token resolver).
    Rows.liveness = function() return "G-D", true, true end
    for _, token in ipairs({ "Vile Poacher", "party1target", "raid3target" }) do
        local d = targetedRow("Serpent Sting", "target", 12, 1000, token, "G-D")
        n = #events
        assertEquals("removed", Rows:OnAuraAbsent(d, 1005))
        assertEquals(n + 1, #events, "an unreadable token fires: " .. token)
    end
    -- (e) the reader raises.
    local e = targetedRow("Serpent Sting", "target", 12, 1100, "target", "G-E")
    Rows.liveness = function() error("boom") end
    n = #events
    assertEquals("removed", Rows:OnAuraAbsent(e, 1105))
    assertEquals(n + 1, #events, "a raising read fires")
    -- (f) the reader answers with sealed facts.
    local f = targetedRow("Serpent Sting", "target", 12, 1200, "target", "G-F")
    Rows.liveness = function() return "G-F", sealed(), sealed() end
    n = #events
    assertEquals("removed", Rows:OnAuraAbsent(f, 1205))
    assertEquals(n + 1, #events, "a sealed liveness answer fires")
    Rows.liveness = probe
    FX.Off(h)
    Rows:Clear()
end)

test("the liveness gate: a self row of a dead self is muted the same way",
function()
    -- The self CC has no unit the sweep reads a guid of -- `player` is
    -- readable, and a dead self carries a guid, so the row speaks for itself.
    -- The dead-self case is the source's `if not UnitIsDead(unit)` applied to
    -- a self row (the source's loop runs on player too).
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local row = targetedRow("Serpent Sting", "none", 12, 1300, "player", "G-P")
    local events, h = captureBroken()
    local probe = Rows.liveness
    Rows.liveness = function() return "G-P", true, false end
    assertEquals("removed", Rows:OnAuraAbsent(row, 1305))
    assertEquals(0, #events)
    Rows.liveness = probe
    FX.Off(h)
    Rows:Clear()
end)

test("the sweep stamps the identity, and shares the reader Rows gates on",
function()
    -- The row's guid is not decorative: Core/Reconcile.lua stamps it at the
    -- CONFIRMING read -- the original's fill-in (`st[i][11] = guid`, :1161) --
    -- through the SAME liveness seam the gate reads, so the stamp and the
    -- gate can not disagree about what a token's identity is.
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    local GUID = "000000000000FE00\1Vile Poacher\1S"
    local savedLiveness = Reconcile.liveness
    -- ONE closure for both halves: the stamp (through Reconcile) and the
    -- gate (Rows.liveness, installed by Init) read the same function, so the
    -- "the unit died" flip below is the same fact for both.
    local facts = { guid = GUID, dead = false, ghost = false }
    Reconcile.liveness = function(token)
        assertEquals("target", token)
        return facts.guid, facts.dead, facts.ghost
    end
    Reconcile.inCombat = function() return false end
    Reconcile:Init(Rows, opts())
    assertTrue(Rows.liveness == Reconcile.liveness,
        "Init installs the one reader into the row table")
    Reconcile.readers = {
        byName = function()
            -- 0.5 s from the prediction: the fact IS the prediction (adopt).
            return { name = "Serpent Sting", expirationTime = 2012.5,
                duration = 12, applications = 2 }
        end,
        bulk = function() return false end,
    }
    local row = seededRow("Serpent Sting", "target", 12, 2000)
    assertNil(row.guid, "a cast-predicted row carries no identity")
    Reconcile:SweepUnit("target", "HARMFUL", 2001)
    assertEquals(GUID, row.guid,
        "the confirming read fills the identity in (:1159-1164)")
    assertEquals("target", row.unitToken)
    -- And the row it identified is the row the gate can mute: kill the unit,
    -- sweep the absence, no announcement.
    facts.dead = true
    Reconcile.readers.byName = function() return false end
    local events, h = captureBroken()
    Reconcile:SweepUnit("target", "HARMFUL", 2005)
    assertEquals(Laws.REMOVE, row.state, "the row is retired all the same")
    assertEquals(0, #events, "and the kill is not announced")
    Reconcile.liveness = savedLiveness
    Rows.liveness = savedLiveness
    FX.Off(h)
    Reconcile.readers = Reconcile.LiveReaders()
    Rows:Clear()
end)

test("the production liveness reader answers plain-or-nil, never a guess",
function()
    -- The production reader is the API-facing half (UnitExists/UnitGUID/
    -- UnitIsDead/UnitIsDeadOrGhost, all in the pinned catalog). The sim
    -- implements those four, so the stubbed globals here exercise the real
    -- wrappers -- the pcall, the PlainOrNil gate and the unit-exists split --
    -- not just the injected seams the tests above use.
    local saved = { UnitExists = _G.UnitExists, UnitGUID = _G.UnitGUID,
        UnitIsDead = _G.UnitIsDead, UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost }
    local function restore()
        _G.UnitExists, _G.UnitGUID = saved.UnitExists, saved.UnitGUID
        _G.UnitIsDead, _G.UnitIsDeadOrGhost = saved.UnitIsDead,
            saved.UnitIsDeadOrGhost
    end
    local probe = Reconcile.LiveLiveness()
    -- (a) the surface is absent (the sim's own shape for a stripped client):
    -- no guid, no liveness -- the gate's fail-open case, never a guessed
    -- "alive" and never a guessed "missing".
    _G.UnitExists, _G.UnitGUID, _G.UnitIsDead, _G.UnitIsDeadOrGhost =
        nil, nil, nil, nil
    local guid, dead, ghost, exists = probe("target")
    assertNil(guid); assertNil(dead); assertNil(ghost); assertFalse(exists)
    -- (b) the token points at no unit at all: a PLAIN fact, not a seal.
    _G.UnitExists = function() return nil end
    _G.UnitGUID = function() return nil end
    guid, dead, ghost, exists = probe("target")
    assertNil(guid, "no unit, no identity")
    assertFalse(exists)
    -- (c) the full live shape, and the sealed-identity raise.
    _G.UnitExists = function() return true end
    _G.UnitGUID = function() return "G-1" end
    _G.UnitIsDead = function() return false end
    _G.UnitIsDeadOrGhost = function() return false end
    guid, dead, ghost, exists = probe("target")
    assertEquals("G-1", guid); assertFalse(dead); assertFalse(ghost)
    assertTrue(exists)
    _G.UnitGUID = function() error("sealed identity") end
    guid, dead, ghost = probe("target")
    assertNil(guid, "a raise on the identity is no answer, not a fact")
    assertNil(dead, "and the liveness of an unidentified unit is never read")
    restore()
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

test("a POSITIVE expiration in the past is no fact: no born-expired row, no refresh of a live one",
function()
    -- `ReadFact` is the one fact seam of both sweep halves, and a
    -- `expirationTime` behind the sweep's clock describes an aura that has
    -- ALREADY ENDED (a client stamp skew, an aura the client has not cleared
    -- out of its store yet). Today it is a fact, and both consumers turn it
    -- into a visible lie: the bulk leg inserts a row BORN expired, and the
    -- per-name leg hands a live row to `Rows:OnAuraFact`'s REFRESH arm, which
    -- removes and re-inserts it on a window that is already over.
    buildHunterRegistry()
    local o = opts()
    Rows.options = o
    Rows:Clear()
    local base = 21000
    Reconcile.inCombat = function() return false end
    Reconcile:Init(Rows, o)
    local savedLiveness, savedRowsLiveness = Reconcile.liveness, Rows.liveness
    Reconcile.liveness = function() return "GUID-x", false, false end
    Rows.liveness = Reconcile.liveness
    local ended = {
        name = "Serpent Sting",
        expirationTime = base - 5,      -- FIVE SECONDS IN THE PAST
        duration = 20,
        applications = 1,
    }
    -- The enumeration shape the production readers hand: the bulk list
    -- itself answers the seal probe with no `expirationTime`, so the sweep
    -- reaches the facts through the bounded `byIndex` fallback (the
    -- production `GetUnitAuras` raising is exactly what arms it) —
    -- `C_UnitAuras.GetAuraDataByIndex`, one aura per index.
    local facts = { ended }
    Reconcile.readers = {
        byName = function() return false end,      -- the per-name leg is inert
        bulk = function() error("FXTEST: the bulk list is sealed") end,
        byIndex = function(_token, i) return facts[i] end,
    }
    local added = Reconcile.counts.added
    local n = Reconcile:SweepBulk("player", "HELPFUL", base)
    assertEquals(0, n, "an ended aura contributes nothing to the sweep")
    assertEquals(added, Reconcile.counts.added,
        "no row is inserted BORN EXPIRED")
    assertNil(Rows:Find("Serpent Sting", "none"),
        "the panel carries no row of an aura that was over before it was read")
    -- `0` is the catalog's PERMANENT spelling, a window with no end: it
    -- stays a fact exactly as today.
    facts[1] = { name = "Serpent Sting", expirationTime = 0, duration = 20,
        applications = 1 }
    n = Reconcile:SweepBulk("player", "HELPFUL", base)
    assertEquals(1, n, "a permanent aura is a fact")
    assertNotNil(Rows:Find("Serpent Sting", "none"),
        "and it reaches the panel")
    Rows:Clear()
    -- The per-name half: the live row of a 12 s crowd control rides a past
    -- fact UNTOUCHED (the refresh arm is what used to eat it).
    local row = seededRow("Serpent Sting", "target", 12, base)
    local expire = row.expireAt
    Reconcile.readers = {
        byName = function() return ended end,
        bulk = function() return false end,
    }
    local skippedNow = Reconcile.counts.skipped
    Reconcile:SweepUnit("target", "HARMFUL", base)
    assertTrue(Reconcile.counts.skipped > skippedNow,
        "the read is classified as no-answer, the sealed read's own shape")
    near(row.expireAt, expire)
    assertEquals(true, row.predicted, "the row is still a prediction")
    assertEquals(Laws.NORMAL, row.state, "and it is still on the panel")
    Reconcile.liveness = savedLiveness
    Rows.liveness = savedRowsLiveness
    Reconcile.readers = Reconcile.LiveReaders()
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

test("the combat gate falls back to InCombatLockdown, the project's probe",
function()
    -- C3: the fallback named a global (`InCombat`) that exists on no client,
    -- so with the injectable seam cleared the production gate answered
    -- `false` mid-combat and the full sweep issued sealed reads every
    -- window. The fallback is the project's combat probe, InCombatLockdown
    -- (Casts.lua:78, Forte_Core/Core/Probe.lua:80), pcall'd the same way.
    buildHunterRegistry()
    Rows.options = opts()
    Rows:Clear()
    seededRow("Serpent Sting", "target", 12, 16000)
    Reconcile:Init(Rows, opts())
    Reconcile.readers = {
        byName = function() return false end,
        bulk = function() return false end,
    }
    local savedProbe, savedStub = Reconcile.inCombat, _G.InCombatLockdown
    local savedSS = FX.SecretState and FX.SecretState.aurasSecret
    if FX.SecretState then FX.SecretState.aurasSecret = nil end
    Reconcile.inCombat = nil
    local reads = Reconcile.counts.reads
    _G.InCombatLockdown = function() return true end
    assertTrue(Reconcile:Gates(), "in combat the sweep must be gated")
    assertEquals(0, Reconcile:SweepUnit("target", "HARMFUL", 16005))
    assertEquals(reads, Reconcile.counts.reads)   -- not one read was issued
    _G.InCombatLockdown = function() return false end
    assertFalse(Reconcile:Gates())
    assertEquals(1, Reconcile:SweepUnit("target", "HARMFUL", 16005))
    _G.InCombatLockdown = savedStub
    Reconcile.inCombat = savedProbe
    if FX.SecretState then FX.SecretState.aurasSecret = savedSS end
    Rows:Clear()
end)

test("the aura sweep retires a consumed aura's row while MAXLAG of its window remains", function()
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
    Reconcile:SweepUnit("target", "HARMFUL", 14003)   -- inside the grace
    assertEquals(Laws.NORMAL, row.state)
    Reconcile:SweepUnit("target", "HARMFUL", 14011.5) -- 0.5 s left: REFUSED (:1207)
    assertEquals(Laws.NORMAL, row.state)
    Reconcile:SweepUnit("target", "HARMFUL", 14005)   -- past the grace, 7 s left: REMOVED
    assertEquals(Laws.REMOVE, row.state)              -- a consumed aura is
    -- retired at once, not after ~11 phantom seconds (the C1/C2 reading,
    -- pinned by the inverted asserts this test used to carry).
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
    -- Leave the liveness seams as production installed them (the shared
    -- LiveLiveness, never a test's fact table).
    Reconcile.liveness = Reconcile.LiveLiveness()
    Rows.liveness = Reconcile.liveness
    assertTrue(true)
end)
