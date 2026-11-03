-- addon/Forte_Warlock/tests/test_warlock.lua
-- wow-ui-sim tests for Core/Tools.lua: the shard counter, the soulstone
-- tracker, the healthstone reader and the Ritual-of-Summoning channel
-- tracker, plus the module's status line, the class gate and the event-frame
-- payload orders.
--
-- Every clock, bag count, item cooldown and power read is INJECTED -- no
-- real time, no bag manipulation, no real item. The sim profile is not a
-- Warlock, so the login gate never fires in the gate run: OnEnable /
-- OnClassChanged are driven directly (the established pattern of
-- Forte_Hunter/tests/test_hunter.lua).
--
-- Secret-read note: the sim exposes no control that forces a secret out of
-- the bag/item/power APIs, so the secret path is exercised at the exact
-- downstream contract -- every live read passes FX.Compat.PlainOrNil first,
-- a secret arrives as nil, and that is what the fakes return (plus the
-- sentinel seam of test 12 on the cast-event path). The live API usage
-- itself is proven by the catalog audit in docs/warlock-tools.md and by this
-- addon loading in the sim with no Forte_* errors.

local FX = ForteXorcist
local WK = FX.Warlock
local Tools = FX.Warlock.Tools

local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end

local function fakeClock(box)
    return function() return box[1] end
end

-- =============================================================== derivations --

-- 1. Every family is DERIVED from the generated data by name pattern; no
-- spell/item ID is hand-typed, so a regenerated data file cannot desync.
test("families are derived from the generated data by name", function()
    local seen = {}
    for _, name in ipairs(WK.soulstoneNames) do seen[name] = true end
    assertNotNil(seen["Create Soulstone"]) -- the shard-spending create spell
    assertNil(seen["Create Healthstone"])  -- a different family
    assertNil(seen["Use Soulstone"])       -- not the create/apply spell

    -- The stone ITEMS: the pattern is on the name, the `Create X` SPELLS are
    -- excluded from an item list (counting a spell's item id reads 0 forever).
    local stones = {}
    for _, name in ipairs(WK.healthstoneNames) do stones[name] = true end
    assertNotNil(stones["Healthstone"])
    assertNotNil(stones["Major Healthstone"])
    assertNotNil(stones["Greater Healthstone"])
    assertNil(stones["Create Healthstone"])
    assertTrue(#WK.healthstoneNames >= 1)
    for i = 2, #WK.healthstoneNames do
        assertTrue(WK.healthstoneNames[i - 1] <= WK.healthstoneNames[i]) -- sorted
    end

    local rituals = {}
    for _, name in ipairs(WK.summonNames) do rituals[name] = true end
    assertNotNil(rituals["Ritual of Summoning"])
    assertNil(rituals["Ritual of Doom"]) -- the healthstone-giving ritual
    assertNil(rituals["Portal of Summoning"])

    -- Every derived name really is a data row, and every data row that
    -- matches the pattern is in the list (no hand-typed extras).
    for _, name in ipairs(WK.soulstoneNames) do
        assertNotNil(FX.Data.WarlockByName[name], name)
    end
    local matches = 0
    for _, spell in pairs(FX.Data.Warlock) do
        local name = spell.name
        if type(name) == "string" and name:find("Healthstone$")
            and not name:find("^Create ") then
            matches = matches + 1
        end
    end
    assertEquals(matches, #WK.healthstoneNames)
end)

-- 2. The predicted durations: the summon channel comes FROM the data; the
-- soulstone window falls back to the documented constant because the data
-- row carries no duration (the fallback itself is the launch-day probe).
test("summon channel length is data-driven, soulstone window falls back", function()
    local fromData
    for _, name in ipairs(WK.summonNames) do
        local row = FX.Data.Warlock[FX.Data.WarlockByName[name]]
        if row and row.castMs and row.castMs > 0 then
            fromData = row.castMs / 1000
            break
        end
    end
    assertEquals(fromData, WK.DeriveSummonChannelSeconds())

    local expected = WK.SOULSTONE_SECONDS
    for _, name in ipairs(WK.soulstoneNames) do
        local row = FX.Data.Warlock[FX.Data.WarlockByName[name]]
        local ms = row and row.durationMs
        if type(ms) == "number" and ms > 0 then
            expected = ms / 1000
            break
        end
    end
    assertEquals(expected, WK.DeriveSoulstoneSeconds())
    -- The Burning Crusade-era law the task set: 30 minutes, and the data is
    -- silent (a generated row with a duration would re-point it by itself).
    assertEquals(1800, WK.SOULSTONE_SECONDS)
end)

-- ================================================================= ShardCounter --

-- 3. The bag-item source answers first and is labelled as the source.
test("shard count comes from the bag source and is labelled", function()
    local calls = { bag = 0, power = 0 }
    local box = { 12 }
    local s = WK.NewShardCounter({
        countReader = function() calls.bag = calls.bag + 1; return box[1] end,
        powerReader = function() calls.power = calls.power + 1; return 4 end,
    })
    local count, source = s:Read()
    assertEquals(12, count)
    assertEquals("bag", source)
    assertEquals(1, calls.bag)
    assertEquals(0, calls.power) -- the bag source answered: the power probe is not needed
    assertEquals(12, s:Count())
    local snap = s:Snapshot()
    assertEquals(12, snap.count)
    assertEquals("bag", snap.source)

    box[1] = 0 -- a plain 0 is a real read (shards spent), not "no data"
    assertEquals(0, s:Read())
    assertEquals(0, s:Count())
    box[1] = 7
    assertEquals(7, s:Read())
end)

-- 4. Both sources exist: the power bar is the fallback, and a single-source
-- probe (what UNIT_POWER_UPDATE drives) never touches the bag source.
test("shard count falls back to the power source; probes can be single-source", function()
    local calls = { bag = 0, power = 0 }
    local s = WK.NewShardCounter({
        countReader = function() calls.bag = calls.bag + 1; return nil end,
        powerReader = function() calls.power = calls.power + 1; return 3 end,
    })
    local count, source = s:Read()
    assertEquals(3, count)
    assertEquals("power", source)
    assertEquals(1, calls.bag)

    calls = { bag = 0, power = 0 }
    s = WK.NewShardCounter({
        countReader = function() calls.bag = calls.bag + 1; return 9 end,
        powerReader = function() calls.power = calls.power + 1; return 4 end,
    })
    assertEquals(4, s:Read(nil, "power"))
    local count, source = s:Count()
    assertEquals(4, count)
    assertEquals("power", source)
    assertEquals(0, calls.bag)
    assertEquals(1, calls.power)
    assertEquals(9, s:Read(nil, "bag"))
    assertEquals(1, calls.bag)
end)

-- 5. Secret-law core: an unreadable source (nil = the secret shape) leaves
-- the last known count standing.
test("secret shard reads never overwrite the known count", function()
    local s = WK.NewShardCounter({
        countReader = function() return nil end,
        powerReader = function() return nil end,
    })
    s.count, s.source = 5, "bag"
    assertNil(s:Read())
    assertEquals(5, s:Count())
    local count, source = s:Count()
    assertEquals(5, count)
    assertEquals("bag", source)
    -- A raising source is an unreliable read, not a zero.
    s = WK.NewShardCounter({ countReader = function() error("restricted", 0) end })
    s.count, s.source = 5, "bag"
    assertNil(s:Read())
    assertEquals(5, s:Count())
    -- Nothing known at all stays unknown, and the status line prints "?".
    s = WK.NewShardCounter({ countReader = function() return nil end })
    assertNil(s:Count())
    local savedCount, savedSource = Tools.Shards.count, Tools.Shards.source
    Tools.Shards.count, Tools.Shards.source = nil, nil
    assertEquals("shards ?", Tools:ShardStatus())
    Tools.Shards.count, Tools.Shards.source = 3, "power"
    assertEquals("shards 3[power]", Tools:ShardStatus())
    Tools.Shards.count, Tools.Shards.source = savedCount, savedSource
end)

-- =============================================================== SoulstoneTracker --

-- 6. The SENT event's target name rides onto the SUCCEEDED cast; the window
-- is the predicted one and self-expires.
test("soulstone: SENT target, SUCCEEDED starts the predicted window", function()
    local box = { 1000 }
    local t = WK.NewSoulstoneTracker({
        now = fakeClock(box), duration = 1800,
    })
    assertFalse(t:Active())
    assertNil(t:Target())
    assertNil(t:Remaining())
    -- A foreign cast claims nothing.
    assertFalse(t:OnCastSent("Shadow Bolt", "Gevil"))
    assertFalse(t:OnCast("Shadow Bolt"))
    assertFalse(t:Active())
    -- The family cast: SENT claims the target, SUCCEEDED starts the stone.
    assertTrue(t:OnCastSent("Create Soulstone", "Gevil"))
    assertFalse(t:Active()) -- the stone is not live until the cast lands
    assertTrue(t:OnCast("Create Soulstone"))
    assertTrue(t:Active())
    assertEquals("Gevil", t:Target())
    near(1800, t:Remaining())
    assertEquals(1, t:Snapshot().casts)

    box[1] = 1000 + 1799.5
    assertTrue(t:Active())
    near(0.5, t:Remaining())
    box[1] = 1000 + 1800 -- ends exactly at start + duration
    assertFalse(t:Active())
    assertNil(t:Target())
    assertNil(t:Remaining())
    assertFalse(t:Active()) -- stays retired
end)

-- 7. One warlock carries one stone: the newest cast owns the slot.
test("soulstone: a newer cast replaces the tracked stone", function()
    local box = { 500 }
    local t = WK.NewSoulstoneTracker({ now = fakeClock(box), duration = 900 })
    t:OnCastSent("Create Soulstone", "Alice")
    t:OnCast("Create Soulstone")
    assertEquals("Alice", t:Target())
    box[1] = 600
    t:OnCastSent("Create Soulstone", "Bob")
    t:OnCast("Create Soulstone")
    assertEquals("Bob", t:Target())
    near(900, t:Remaining()) -- the window restarted with the new stone
    assertEquals(2, t:Snapshot().casts)
end)

-- 8. A target name that cannot be read (the ConditionalSecret SENT field)
-- costs the NAME, not the timer: a stone is live with an unknown bearer.
test("soulstone: an unreadable target name leaves the timer intact", function()
    local box = { 700 }
    local t = WK.NewSoulstoneTracker({ now = fakeClock(box), duration = 1800 })
    assertTrue(t:OnCastSent("Create Soulstone", nil)) -- the secret shape
    assertTrue(t:OnCast("Create Soulstone"))
    assertTrue(t:Active())
    assertNil(t:Target())
    near(1800, t:Remaining())
    local snap = t:Snapshot()
    assertTrue(snap.active)
    assertNil(snap.target)
    near(1800, snap.remaining)

    -- The status line labels an unknown bearer honestly.
    local keepActive, keepStart = Tools.Soulstone.active, Tools.Soulstone.start
    local keepTarget, keepDuration, keepNow =
        Tools.Soulstone.target, Tools.Soulstone.duration, Tools.Soulstone.now
    Tools.Soulstone.now = function() return 300000 end
    Tools.Soulstone.duration, Tools.Soulstone.active = 1800, true
    Tools.Soulstone.start, Tools.Soulstone.target = 300000, nil
    assertContains(Tools:SoulstoneStatus(), "soulstone (target unread) 1800s")
    Tools.Soulstone.active, Tools.Soulstone.start, Tools.Soulstone.target,
        Tools.Soulstone.duration, Tools.Soulstone.now =
        keepActive, keepStart, keepTarget, keepDuration, keepNow
end)

-- 9. A data-driven window: a row that DOES carry a duration drives it.
test("soulstone: an explicit window length expires it", function()
    local box = { 100 }
    local t = WK.NewSoulstoneTracker({ now = fakeClock(box), duration = 60 })
    t:OnCast("Create Soulstone")
    box[1] = 159
    assertTrue(t:Active())
    box[1] = 160
    assertFalse(t:Active())
    -- An unknown length (nil) never self-expires -- no event-free invention.
    t = WK.NewSoulstoneTracker({ now = fakeClock(box), duration = nil })
    box[1] = 1000
    t:OnCast("Create Soulstone")
    box[1] = 999999
    assertTrue(t:Active())
    assertNil(t:Remaining())
end)

-- 9b. The window's end is the moment the 2012 panel rings its two soulstone
-- bells (Forte_Soulstone.lua:429-445 the tracked stone's expiry,
-- :461-464 the warlock's stone-cooldown end; the seeding law that makes the
-- two one instant on this self-only port is documented in
-- Forte_Core/Core/Events.lua). The fire is the tracker's `onExpire` seam,
-- and the PRODUCTION tracker carries the closure that fires the bus pair --
-- this drives that production closure, not a test's own.
test("soulstone: the window's end fires the bus pair once, and Ready opens",
function()
    local fired = {}
    local realFire = FX.Fire
    FX.Fire = function(event, target, at)
        fired[#fired + 1] = { event = event, target = target, at = at }
    end
    local keep = {
        onExpire = Tools.Soulstone.onExpire, active = Tools.Soulstone.active,
        start = Tools.Soulstone.start, target = Tools.Soulstone.target,
        duration = Tools.Soulstone.duration, now = Tools.Soulstone.now,
        readyAt = Tools.Soulstone.readyAt,
    }
    local box = { 1000 }
    Tools.Soulstone.now = fakeClock(box)
    Tools.Soulstone.duration = 60
    Tools.Soulstone:Clear()
    Tools.Soulstone:OnCast("Create Soulstone", "Gvil")
    box[1] = 1030
    assertTrue(Tools.Soulstone:Active())
    assertEquals(0, #fired, "no bell while the stone is up")
    assertFalse(Tools.Soulstone:Ready())
    box[1] = 1060
    assertFalse(Tools.Soulstone:Active(), "the window lapsed")
    FX.Fire = realFire
    assertEquals(2, #fired, "the pair, one fire each")
    assertEquals("FX_SOULSTONE_EXPIRED", fired[1] and fired[1].event)
    assertEquals("FX_SOULSTONE_READY", fired[2] and fired[2].event)
    assertEquals("Gvil", fired[1] and fired[1].target)
    assertEquals(1060, fired[1] and fired[1].at)
    -- The ready half stays open (the plate's READY_TO_RES look rides it) and
    -- re-observing the lapsed window rings nothing a second time.
    assertTrue(Tools.Soulstone:Ready(), "ready to put a new stone up")
    assertEquals(2, #fired)
    fired = {}
    FX.Fire = function(event) fired[#fired + 1] = event end
    box[1] = 1099
    assertFalse(Tools.Soulstone:Active())
    FX.Fire = realFire
    assertEquals(0, #fired, "one window, one ring")
    Tools.Soulstone.active, Tools.Soulstone.start, Tools.Soulstone.target,
        Tools.Soulstone.duration, Tools.Soulstone.now,
        Tools.Soulstone.readyAt =
        keep.active, keep.start, keep.target, keep.duration, keep.now,
        keep.readyAt
end)

-- 9c. The owner's Clear is NOT an expiry: a class change, a re-login or a
-- disable puts the window away and rings nothing (the 2012 panel drops the
-- row in the same branch that plays the bell, so the pair needs a window
-- that RAN, not one that was taken away).
test("soulstone: the owner's Clear fires nothing and closes the ready look",
function()
    local fired = 0
    local t = WK.NewSoulstoneTracker({
        now = fakeClock({ 500 }), duration = 60,
        onExpire = function() fired = fired + 1 end,
    })
    t:OnCast("Create Soulstone", "Gvil")
    t:Clear()
    assertEquals(0, fired, "an owner's Clear is not an expiry")
    assertFalse(t:Ready(), "and it leaves no ready claim")
end)

-- 9d. A fresh stone closes the ready look: the plate prints `no ss up` (and
-- the x1 row) while a window runs, never `ready to res` beside a live stone.
test("soulstone: a new stone closes the ready look", function()
    local box = { 100 }
    local t = WK.NewSoulstoneTracker({ now = fakeClock(box), duration = 30 })
    t:OnCast("Create Soulstone", "Gvil")
    box[1] = 130
    assertFalse(t:Active())
    assertTrue(t:Ready())
    t:OnCast("Create Soulstone", "Gvil")
    assertFalse(t:Ready(), "the new stone owns the slot, not the ready look")
end)

-- ============================================================ HealthstoneTracker --

-- 10. Bag presence: a plain count is a fact; nil is not.
test("healthstone presence: count drives Present, nil changes nothing", function()
    local stones = { n = 2 }
    local h = WK.NewHealthstoneTracker({
        countReader = function() return stones.n end,
    })
    assertEquals(2, h:ReadCounts())
    assertEquals(2, h:Count())
    assertTrue(h:Present())
    stones.n = 0
    assertEquals(0, h:ReadCounts())
    assertFalse(h:Present())
    -- Unreliable reads (the secret/absent shape and a raise) keep the state.
    stones.n = 3
    h = WK.NewHealthstoneTracker({ countReader = function() return nil end })
    h.count = 4
    assertNil(h:ReadCounts())
    assertEquals(4, h:Count())
    h = WK.NewHealthstoneTracker({
        countReader = function() error("restricted", 0) end,
    })
    h.count = 4
    assertNil(h:ReadCounts())
    assertEquals(4, h:Count())
    -- Never read at all = unknown, not "empty".
    assertNil(WK.NewHealthstoneTracker({}):Present())
    -- No reader injected at all: no read, no verdict, no raise.
    local fresh = WK.NewHealthstoneTracker({})
    assertNil(fresh:ReadCounts())
    assertNil(fresh:ReadCooldown())
end)

-- 11. Item cooldown through the FX.Compat.GetItemCooldownInfo shape:
-- (startTime, duration, enable), every number secret-guarded.
test("healthstone cooldown: anchored, counted down, cleared", function()
    local box = { 1000 }
    local read = { start = 900, duration = 300, enable = 1 }
    local h = WK.NewHealthstoneTracker({
        now = fakeClock(box),
        cooldownReader = function() return read.start, read.duration, read.enable end,
    })
    assertNil(h:CooldownRemaining()) -- ready
    assertEquals("anchored", h:ReadCooldown())
    near(200, h:CooldownRemaining()) -- (900 + 300) - 1000
    box[1] = 1100
    near(100, h:CooldownRemaining())
    local snap = h:Snapshot()
    near(100, snap.cooldownRemaining)
    assertEquals(300, snap.cooldownDuration)
    -- A plain "ready" read clears it.
    read.start, read.duration = 0, 0
    assertEquals("cleared", h:ReadCooldown())
    assertNil(h:CooldownRemaining())
    -- Self-expiry on observation (no ticker).
    read.start, read.duration = 2000, 10
    box[1] = 2000
    assertEquals("anchored", h:ReadCooldown())
    near(10, h:CooldownRemaining())
    box[1] = 2010
    assertNil(h:CooldownRemaining())
    assertNil(h.cdStart)
    -- A disabled timer (the `enable` flag) is not a cooldown.
    assertEquals("ignored", h:OnReadCooldown(2000, 100, 0, 2010))
    assertNil(h:CooldownRemaining())
end)

-- 12. Secret item-cooldown reads: nils, a raise and a non-number answer
-- "secret" and leave the anchored window alone.
test("healthstone cooldown: secret reads leave the window alone", function()
    local box = { 1000 }
    local read = { start = 900, duration = 300, enable = 1, raises = false }
    local h = WK.NewHealthstoneTracker({
        now = fakeClock(box),
        cooldownReader = function()
            if read.raises then error("restricted", 0) end
            return read.start, read.duration, read.enable
        end,
    })
    assertEquals("anchored", h:ReadCooldown())
    near(200, h:CooldownRemaining())
    read.start, read.duration = nil, nil -- the secret shape
    assertEquals("secret", h:ReadCooldown())
    near(200, h:CooldownRemaining()) -- the known window stands
    read.raises = true
    assertEquals("secret", h:ReadCooldown())
    near(200, h:CooldownRemaining())
    read.raises = false
    -- A non-number (a table-shaped read) is guarded by the type check, not a
    -- raise and not a clear.
    read.start, read.duration = { 1 }, { 2 }
    assertEquals("secret", h:ReadCooldown())
    near(200, h:CooldownRemaining())
    -- No reader at all: no read, no verdict.
    assertNil(WK.NewHealthstoneTracker({}):ReadCooldown())
end)

-- ================================================================ SummonTracker --

-- 13. Ritual of Summoning: SENT (with the target) and START predict the
-- channel; the terminal events end it with a recorded outcome.
test("ritual: cast events predict the channel, targets claimed from SENT", function()
    local box = { 1000 }
    local s = WK.NewSummonTracker({ now = fakeClock(box), channelSeconds = 5 })
    assertFalse(s:Channeling())
    assertNil(s:Progress())
    assertFalse(s:OnCastSent("Create Healthstone", "Gevil"))
    assertFalse(s:Channeling())
    assertTrue(s:OnCastSent("Ritual of Summoning", "Gevil"))
    assertTrue(s:Channeling())
    assertEquals("Gevil", s:Snapshot().target)
    near(0, s:Progress())
    near(5, select(2, s:Progress()))
    box[1] = 1002.5
    near(0.5, s:Progress())
    near(2.5, select(2, s:Progress()))
    -- START of the same channel does not restart it.
    assertTrue(s:OnCastStart("Ritual of Summoning"))
    box[1] = 1002.5
    near(0.5, s:Progress())
    assertTrue(s:End("Ritual of Summoning", "succeeded"))
    assertFalse(s:Channeling())
    assertNil(s:Progress())
    local last = s:Snapshot().last
    assertEquals("succeeded", last.outcome)
    assertEquals("Gevil", last.target)
    near(2.5, last.channelled)
    assertEquals(1, s:Snapshot().starts)
    assertEquals(1, s:Snapshot().ends)
    -- A cancel: the target is dropped, the outcome recorded.
    box[1] = 2000
    s:OnCastSent("Ritual of Summoning", "Carol")
    assertTrue(s:Channeling())
    assertTrue(s:End("Ritual of Summoning", "cancelled"))
    assertFalse(s:Channeling())
    assertEquals("cancelled", s:Snapshot().last.outcome)
    assertNil(s:Snapshot().target)
    -- An out-of-combat non-event: a foreign ritual does not touch us.
    assertFalse(s:End("Ritual of Doom", "succeeded"))
end)

-- 14. The channel is a prediction, so it self-expires at the data's cast
-- length when no stop event reaches the addon.
test("ritual: the predicted channel self-expires", function()
    local box = { 300 }
    local s = WK.NewSummonTracker({ now = fakeClock(box), channelSeconds = 5 })
    s:OnCastStart("Ritual of Summoning")
    box[1] = 304.9
    assertTrue(s:Channeling())
    box[1] = 305
    assertFalse(s:Channeling())
    assertEquals("expired", s:Snapshot().last.outcome)
    -- With no length knowledge the channel is not invented away.
    s = WK.NewSummonTracker({ now = fakeClock(box), channelSeconds = nil })
    s:OnCastStart("Ritual of Summoning")
    box[1] = 9999
    assertTrue(s:Channeling())
    assertNil(s:Progress())
end)

-- ==================================================================== status --

-- 15. Status PRINTS its own one line (the Core status loop only loops), and
-- every feature of the line is a real read/prediction.
test("Status prints one line carrying all four tools", function()
    local saved = {
        shard = { Tools.Shards.count, Tools.Shards.source },
        stone = { Tools.Soulstone.active, Tools.Soulstone.target,
                  Tools.Soulstone.start, Tools.Soulstone.duration },
        stoneNow = Tools.Soulstone.now,
        stoneClock = { 100000 },
        stoneReader = Tools.Healthstone.countReader,
        stoneCD = Tools.Healthstone.cooldownReader,
        stoneCount = Tools.Healthstone.count,
        healthNow = Tools.Healthstone.now,
        cd = { Tools.Healthstone.cdStart, Tools.Healthstone.cdDuration },
        summon = { Tools.Summon.channeling, Tools.Summon.name,
                   Tools.Summon.target, Tools.Summon.start,
                   Tools.Summon.duration, Tools.Summon.last },
        summonNow = Tools.Summon.now,
    }
    local clock = { 100000 }
    Tools.Soulstone.now = fakeClock(clock)
    Tools.Summon.now = fakeClock(clock)
    Tools.Healthstone.now = fakeClock(clock)
    Tools.Shards.count, Tools.Shards.source = 12, "bag"
    Tools.Soulstone.duration = 1800
    Tools.Soulstone.active, Tools.Soulstone.start, Tools.Soulstone.target =
        true, 100000, "Gevil"
    Tools.Healthstone.count = 2
    Tools.Healthstone.cdStart, Tools.Healthstone.cdDuration = 99900, 300
    Tools.Summon.channeling, Tools.Summon.name, Tools.Summon.target =
        true, "Ritual of Summoning", "Alice"
    Tools.Summon.start, Tools.Summon.duration = 100000, 5

    local lines = {}
    local realPrint = FX.Print
    FX.Print = function(msg) lines[#lines + 1] = tostring(msg) end
    Tools:Status()
    FX.Print = realPrint
    assertEquals(1, #lines)
    local status = lines[1]
    assertContains(status, "Warlock:")
    assertContains(status, "shards 12[bag]")
    assertContains(status, "soulstone Gevil 1800s")
    assertContains(status, "healthstone 2")
    assertContains(status, "cd 200.0s")
    assertContains(status, "ritual channeling on Alice")
    assertContains(Tools:SummonStatus(), "5.0s")

    -- The unknown shapes the status line prints for a fresh session.
    Tools.Soulstone.active = false
    Tools.Healthstone.count = nil
    Tools.Healthstone.cdStart, Tools.Healthstone.cdDuration = nil, nil
    Tools.Shards.count, Tools.Shards.source = nil, nil
    Tools.Summon.channeling, Tools.Summon.name, Tools.Summon.target = false, nil, nil
    Tools.Summon.start, Tools.Summon.duration = nil, nil
    assertContains(Tools:StatusLine(), "shards ?")
    assertContains(Tools:StatusLine(), "soulstone none")
    assertContains(Tools:StatusLine(), "healthstone ?")
    assertContains(Tools:StatusLine(), "ritual idle")

    -- restore
    Tools.Soulstone.now = saved.stoneNow
    Tools.Summon.now = saved.summonNow
    Tools.Shards.count, Tools.Shards.source = saved.shard[1], saved.shard[2]
    Tools.Soulstone.active, Tools.Soulstone.target, Tools.Soulstone.start,
        Tools.Soulstone.duration =
        saved.stone[1], saved.stone[2], saved.stone[3], saved.stone[4]
    Tools.Healthstone.count = saved.stoneCount
    Tools.Healthstone.countReader = saved.stoneReader
    Tools.Healthstone.cooldownReader = saved.stoneCD
    Tools.Healthstone.now = saved.healthNow
    Tools.Healthstone.cdStart, Tools.Healthstone.cdDuration =
        saved.cd[1], saved.cd[2]
    Tools.Summon.channeling, Tools.Summon.name, Tools.Summon.target,
        Tools.Summon.start, Tools.Summon.duration, Tools.Summon.last =
        saved.summon[1], saved.summon[2], saved.summon[3], saved.summon[4],
        saved.summon[5], saved.summon[6]
end)

-- ==================================================================== gate --

-- 16. The class gate: a non-warlock logs in and NOTHING is wired (no frame,
-- no registrations); the class-change hook moves the frame with the class.
test("non-warlock class wires nothing; OnClassChanged moves the frame", function()
    local savedClass, wasEnabled = FX._playerClass, Tools._eventsEnabled
    local savedFrame = Tools._eventFrame

    -- A warlock login: the frame appears, the handler is bound.
    FX._playerClass = "WARLOCK"
    Tools._eventsEnabled, Tools._eventFrame = false, nil
    Tools:OnEnable()
    assertTrue(Tools._eventsEnabled)
    assertNotNil(Tools._eventFrame)
    assertEquals("function", type(Tools._eventFrame:GetScript("OnEvent")))

    -- The class is re-read as something else: the module goes silent.
    FX._playerClass = "HUNTER"
    Tools:OnClassChanged("HUNTER")
    assertFalse(Tools._eventsEnabled)
    assertNil(Tools._eventFrame:GetScript("OnEvent"))

    -- A fresh login of a non-warlock class wires nothing at all.
    Tools._eventFrame = nil
    Tools._eventsEnabled = false
    Tools:OnEnable()
    assertFalse(Tools._eventsEnabled)
    assertNil(Tools._eventFrame)
    -- Idempotence of the enable path (a second warlock hook re-arms once).
    FX._playerClass = "WARLOCK"
    Tools:OnEnable()
    Tools:OnEnable()
    assertTrue(Tools._eventsEnabled)

    -- Restore the pre-test state (the sim profile is not a Warlock, so the
    -- events were never live at login).
    Tools:OnClassChanged(tostring(savedClass))
    FX._playerClass = savedClass
    if not wasEnabled then
        Tools:DisableEvents()
        Tools._eventFrame = savedFrame
    end
    assertFalse(Tools._eventsEnabled)
end)

test("the module is registered under its own name", function()
    assertNotNil(FX.modules["Warlock"])
    assertEquals(Tools, FX.modules["Warlock"])
end)

-- ============================================================ event plumbing --

local function handler()
    local wasEnabled = Tools._eventsEnabled
    if not wasEnabled then
        Tools:OnClassChanged("WARLOCK") -- the frame exists only when enabled
    end
    local f = Tools._eventFrame
    assertNotNil(f, "the event frame exists once enabled")
    local h = f:GetScript("OnEvent")
    assertEquals("function", type(h))
    return h, f, wasEnabled
end

local function restoreEvents(wasEnabled)
    if not wasEnabled then
        Tools:OnClassChanged("HUNTER")
        Tools._eventFrame = nil
    end
end

--- Stub C_Spell.GetSpellInfo for the duration of `body`, mapping the fake
--- ids below to real generated names. The sim's profile DB resolves a
--- different id set than our pinned data (PLAN §8), so the payload-ORDER
--- proof cannot ride the live spell DB -- the name map is the seam, and the
--- real resolution is covered by Forte_Cooldown's own id/name tests.
local function withSpellNames(ids, body)
    local saved = _G.C_Spell
    _G.C_Spell = {
        GetSpellInfo = function(id)
            for spellID, name in pairs(ids) do
                if id == spellID then return { name = name, spellID = spellID } end
            end
            return nil
        end,
    }
    local ok, err = pcall(body)
    _G.C_Spell = saved -- the sim's real table back, exactly as found
    assertTrue(ok, tostring(err))
end

-- 17. The payload contracts, driven through the module's own event frame:
-- UNIT_SPELLCAST_SENT carries the target as its SECOND field and the
-- spellID as its FOURTH (UnitDocumentation.lua:4802), the other cast events
-- carry the spellID THIRD (…:4816/:4844/:4830/:4713/:4741/:4612/:4626).
test("SENT/START/SUCCEEDED payloads: target 2nd, spellID 4th then 3rd", function()
    local h, f, wasEnabled = handler()
    local CREATE = 910001
    local RITUAL = 910002
    local ids = { [CREATE] = "Create Soulstone", [RITUAL] = "Ritual of Summoning" }

    -- Bag/power reads are injected so the event pass is observable.
    local savedShard = Tools.Shards.countReader
    local savedStone = Tools.Healthstone.countReader
    local savedCD = Tools.Healthstone.cooldownReader
    local reads = { shard = 0, stone = 0, cd = 0 }
    Tools.Shards.countReader = function() reads.shard = reads.shard + 1; return 6 end
    Tools.Healthstone.countReader = function() reads.stone = reads.stone + 1; return 1 end
    Tools.Healthstone.cooldownReader = function() reads.cd = reads.cd + 1; return nil end
    local savedStoneT = {
        Tools.Soulstone.active, Tools.Soulstone.target, Tools.Soulstone.start,
        Tools.Soulstone.duration, Tools.Soulstone.now, Tools.Soulstone.name,
    }
    local savedSummon = {
        Tools.Summon.channeling, Tools.Summon.name, Tools.Summon.target,
        Tools.Summon.start, Tools.Summon.duration, Tools.Summon.now,
        Tools.Summon.last,
    }
    local clock = { 500000 }
    Tools.Soulstone.now = fakeClock(clock)
    Tools.Soulstone.duration = 1800
    Tools.Soulstone.active = false
    Tools.Soulstone.target, Tools.Soulstone.start = nil, nil
    Tools.Summon.now = fakeClock(clock)
    Tools.Summon.channeling, Tools.Summon.target, Tools.Summon.last = false, nil, nil
    Tools.Summon.start, Tools.Summon.duration = nil, nil

    withSpellNames(ids, function()
        -- SENT: (unit, target, castGUID, spellID)
        h(f, "UNIT_SPELLCAST_SENT", "player", "Gevil", "F", CREATE)
        assertTrue(Tools.Soulstone.pending == "Gevil",
            "the SENT target is claimed for the cast in flight")
        assertFalse(Tools.Soulstone:Active())
        -- SUCCEEDED: (unit, castGUID, spellID[, castBarID])
        h(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "F", CREATE)
        assertTrue(Tools.Soulstone:Active())
        assertEquals("Gevil", Tools.Soulstone:Target())
        near(1800, Tools.Soulstone:Remaining())
        -- A Create* success re-reads the bag (the shards + stones changed).
        assertTrue(reads.shard >= 1, "bag sources re-read on Create*")
        assertTrue(reads.stone >= 1)
        -- INTERRUPTED is (unit, castGUID, spellID, interruptedBy, castBarID):
        -- the id is the 3rd. A payload whose 3rd field is nil and whose 4th
        -- (interruptedBy) IS a resolvable id must resolve no name at all --
        -- the same holds for the 5-field CHANNEL_STOP probed below.
        Tools.Soulstone.active, Tools.Soulstone.target = false, nil
        Tools.Summon.last, Tools.Summon.channeling = nil, false
        h(f, "UNIT_SPELLCAST_INTERRUPTED", "player", "F", nil, RITUAL, nil)
        assertFalse(Tools.Soulstone:Active())
        assertNil(Tools.Summon.last, "the interruptedBy field is never read")
        -- RITUAL: SENT claims the target and predicts the channel; the
        -- CHANNEL_STOP (unit, castGUID, spellID, interruptedBy, castBarID)
        -- ends it.
        h(f, "UNIT_SPELLCAST_SENT", "player", "Alice", "F", RITUAL)
        assertTrue(Tools.Summon:Channeling())
        assertEquals("Alice", Tools.Summon.target)
        h(f, "UNIT_SPELLCAST_CHANNEL_START", "player", "F", RITUAL)
        assertTrue(Tools.Summon:Channeling())
        h(f, "UNIT_SPELLCAST_CHANNEL_STOP", "player", "F", RITUAL, "player", nil)
        assertFalse(Tools.Summon:Channeling())
        assertEquals("cancelled", Tools.Summon.last.outcome)
        assertEquals("Alice", Tools.Summon.last.target)
        -- A foreign cast names nothing: no state moves.
        clock[1] = clock[1] + 10
        h(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "F", nil)
        assertFalse(Tools.Soulstone:Active())
    end)

    -- restore
    Tools.Shards.countReader = savedShard
    Tools.Healthstone.countReader = savedStone
    Tools.Healthstone.cooldownReader = savedCD
    Tools.Soulstone.active, Tools.Soulstone.target, Tools.Soulstone.start,
        Tools.Soulstone.duration, Tools.Soulstone.now, Tools.Soulstone.name =
        savedStoneT[1], savedStoneT[2], savedStoneT[3], savedStoneT[4],
        savedStoneT[5], savedStoneT[6]
    Tools.Summon.channeling, Tools.Summon.name, Tools.Summon.target,
        Tools.Summon.start, Tools.Summon.duration, Tools.Summon.now,
        Tools.Summon.last =
        savedSummon[1], savedSummon[2], savedSummon[3], savedSummon[4],
        savedSummon[5], savedSummon[6], savedSummon[7]
    restoreEvents(wasEnabled)
end)

-- 18. The bag events drive the read pass; UNIT_POWER_UPDATE probes ONLY the
-- power source (so the bag source is not even called).
test("BAG_UPDATE_DELAYED re-reads, UNIT_POWER_UPDATE probes the power source", function()
    local h, f, wasEnabled = handler()
    local saved = {
        shardReader = Tools.Shards.countReader,
        powerReader = Tools.Shards.powerReader,
        stoneReader = Tools.Healthstone.countReader,
        cdReader = Tools.Healthstone.cooldownReader,
        count = Tools.Shards.count, source = Tools.Shards.source,
    }
    local calls = { bag = 0, power = 0, stone = 0, cd = 0 }
    Tools.Shards.countReader = function() calls.bag = calls.bag + 1; return 21 end
    Tools.Shards.powerReader = function() calls.power = calls.power + 1; return 4 end
    Tools.Healthstone.countReader = function() calls.stone = calls.stone + 1; return 3 end
    Tools.Healthstone.cooldownReader = function() calls.cd = calls.cd + 1; return nil end

    -- The frame is registered for the REAL events as well, so every
    -- expectation is the delta around its own dispatch, never a cumulative
    -- count (a stray client event between two tests must not decide this).
    local function deltas(body)
        local b, p, s, c = calls.bag, calls.power, calls.stone, calls.cd
        body()
        return calls.bag - b, calls.power - p, calls.stone - s, calls.cd - c
    end

    local bag, power, stone, cd = deltas(function() h(f, "BAG_UPDATE_DELAYED") end)
    assertEquals(1, bag)
    assertEquals(0, power) -- the bag source answered: no power probe
    assertEquals(1, stone)
    assertEquals(1, cd)
    local count, source = Tools.Shards:Count()
    assertEquals(21, count)
    assertEquals("bag", source)

    bag, power, stone, cd = deltas(function() h(f, "ITEM_COUNT_CHANGED", 12345) end)
    assertEquals(1, bag)
    assertEquals(1, stone)

    -- The power event probes ONLY the power source: the bag reader is not
    -- called at all.
    bag, power, stone, cd = deltas(function()
        h(f, "UNIT_POWER_UPDATE", "player", "SOULSHARDS")
    end)
    assertEquals(0, bag)
    assertEquals(1, power)
    assertEquals(0, stone)
    count, source = Tools.Shards:Count()
    assertEquals(4, count)
    assertEquals("power", source)

    -- Out of combat: the full pass -- the bag items (count + cooldown) and
    -- both shard sources, bag first, so the power source is not needed.
    bag, power, stone, cd = deltas(function() h(f, "PLAYER_REGEN_ENABLED") end)
    assertEquals(2, bag)
    assertEquals(0, power)
    assertEquals(1, stone)
    assertEquals(1, cd)

    bag, power, stone, cd = deltas(function()
        h(f, "SOME_UNRELATED_EVENT", "player", 1, 2, 3)
    end)
    assertEquals(0, bag)
    assertEquals(0, power)
    assertEquals(0, stone)
    assertEquals(0, cd)

    Tools.Shards.countReader = saved.shardReader
    Tools.Shards.powerReader = saved.powerReader
    Tools.Healthstone.countReader = saved.stoneReader
    Tools.Healthstone.cooldownReader = saved.cdReader
    Tools.Shards.count, Tools.Shards.source = saved.count, saved.source
    restoreEvents(wasEnabled)
end)

-- ================================================================ secret law --

-- 19. The cast-event spellID is catalog-annotated
-- SecretWhenUnitSpellCastRestricted: the lookup, the truth test and the
-- field read run inside ONE pcall, so a sentinel, a nil, a junk id and a
-- raising table all answer nil and never raise.
test("cast name resolution survives sentinel, nil, junk and raising ids", function()
    assertNotNil(Tools.ResolveCastName)
    local SECRET = "FXTEST-SECRET-VALUE"
    local realPlain = FX.Compat.PlainOrNil
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlain(v)
    end
    local okS, nameS = pcall(Tools.ResolveCastName, SECRET)
    -- The SENT target field is ConditionalSecret: the same shape on it.
    local okT, targetT = pcall(Tools.ResolveTargetName, SECRET)
    local plainTarget = Tools.ResolveTargetName("Gevil")
    FX.Compat.PlainOrNil = realPlain
    assertTrue(okS)
    assertNil(nameS)
    assertTrue(okT)
    assertNil(targetT)
    assertEquals("Gevil", plainTarget)
    assertNil(Tools.ResolveTargetName(nil))
    assertNil(Tools.ResolveTargetName(7))

    local okN, nameN = pcall(Tools.ResolveCastName, nil)
    assertTrue(okN)
    assertNil(nameN)
    local okB, nameB = pcall(Tools.ResolveCastName, 987654321)
    assertTrue(okB)
    assertNil(nameB)
    local okT2, nameT2 = pcall(Tools.ResolveCastName, setmetatable({},
        { __index = function() error("touched", 0) end }))
    assertTrue(okT2)
    assertNil(nameT2)

    -- A secret spellID on a real SENT payload: the module keeps the target
    -- it can read, resolves no name and adopts nothing -- no raise.
    local h, f, wasEnabled = handler()
    local savedStone = {
        Tools.Soulstone.active, Tools.Soulstone.target, Tools.Soulstone.pending,
    }
    Tools.Soulstone.active, Tools.Soulstone.target, Tools.Soulstone.pending =
        false, nil, nil
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlain(v)
    end
    local ok = pcall(h, f, "UNIT_SPELLCAST_SENT", "player", SECRET, SECRET, SECRET)
    FX.Compat.PlainOrNil = realPlain
    assertTrue(ok)
    assertFalse(Tools.Soulstone:Active())
    assertNil(Tools.Soulstone.pending)
    Tools.Soulstone.active, Tools.Soulstone.target, Tools.Soulstone.pending =
        savedStone[1], savedStone[2], savedStone[3]
    restoreEvents(wasEnabled)
end)

-- 20. The live read seams exist and are callable: on this build's sim profile
-- they answer plainly (0 = the empty bag) instead of raising. That is the
-- load-time proof the API names are real -- the catalog audit in
-- docs/warlock-tools.md is the signature proof, the live client is the
-- semantic one (probes P1-P4).
test("live bag/power read seams answer without raising", function()
    local ok, count = pcall(WK.DefaultShardCountReader)
    assertTrue(ok, "the bag reader is callable on this client")
    if ok then
        local plain = FX.Compat.PlainOrNil(count)
        assertTrue(plain == nil or type(plain) == "number",
            "the bag reader answers a plain number or nothing")
    end
    ok = pcall(WK.DefaultShardPowerReader)
    assertTrue(ok, "the power reader is callable on this client")
    ok = pcall(WK.DefaultHealthstoneCountReader)
    assertTrue(ok, "the healthstone count reader is callable")
    ok = pcall(WK.DefaultHealthstoneCooldownReader)
    assertTrue(ok, "the healthstone cooldown reader is callable")
    assertNotNil(WK.SHARD_ITEM_NAMES[1], "the shard item is named")
    -- The stone names come from the generated data (never hand-typed).
    for _, name in ipairs(WK.healthstoneNames) do
        assertNotNil(FX.Data.WarlockByName[name], name)
    end
    -- The item id the cooldown seam is called with is generated data, keyed
    -- by the derived NAME (never hand-typed).
    local name = WK.healthstoneNames[1]
    assertNotNil(name, "the healthstone family is derived")
    local id = WK.DataItemID(name)
    assertEquals("number", type(id))
    assertEquals(FX.Data.WarlockByName[name], id)
    assertNil(WK.DataItemID("No Such Item At All"))
end)
