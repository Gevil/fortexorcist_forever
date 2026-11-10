-- addon/Forte_Timer/tests/test_data_feeds.lua
-- The three DATA FEEDS the Spell Timer was built to receive (wave 4 `Feeds`,
-- docs/design-spell-timer.md §3.4): the generated row's `tickEvery` (the
-- periodic effect's period, SECONDS), `maxStack` (the aura's stack cap) and
-- `noTarget` (every effect of the row targets the caster -- the original's
-- `Track[spell][1]` `notTarget` column). The sources, in order (the law in
-- `tools/gen_spell_data.py`, pinned by test "the feeds ride base rows
-- first..."): the mythicsim BASE rows' `Effects[].PeriodMs`, `MaxStack` and
-- effect `Target` pair answer first; a picked row with no base row of its
-- own inherits the same-family rank SIBLING's base shape (wave M3a,
-- docs/research/data-diff-live-2026-11-07.md); the live store's per-id feed
-- captures (the 1.60.1.70790 overlay's `periodMs`/`targetCode`/`maxStack`)
-- fill what neither can speak to. Absence is absence -- a feed the data
-- says nothing about is absent, never zero.
--
-- The chain under test is data row -> `Registry:Build` -> registry entry ->
-- the row the renderer draws, whose tick-mark branch (`Forte_Timer/UI/Rows.lua`
-- `row.tickEvery`, delta D6) is the reason `tickEvery` exists at all. The
-- renderer is not called here (its own suite is `test_perf_gates.lua` /
-- `test_rows.lua`): the tick branch is asserted through a SEEDED row -- the
-- row's own fields fed to the branch's own arithmetic -- which is what proves
-- the feed reaches it with the right unit and sign.
--
-- Name-keyed throughout: no spell ID is read, written or asserted (AGENTS.md,
-- PLAN §10.2 rule 8 -- IDs drift per build, the data is keyed by NAME).

local FX = ForteXorcist
local Registry = FX.Timer.Registry
local Rows = FX.Timer.Rows

local CLASSES = { "Hunter", "Warlock", "Mage", "Priest", "Druid", "Rogue",
    "Shaman", "Paladin", "Warrior" }

-- The census is nine-class, the sim profile is one class, and a
-- `## LoadOnDemand: 1` add-on is not parsed by `run-tests` (test_00's note):
-- ask for every add-on the fixtures name through the login path's own entry
-- point, so no assertion can run over a nil data table.
for i = 1, #CLASSES do
    FX.LoadClassAddOn(CLASSES[i]:upper())
end

--- The generated data row of a NAME (the data is keyed by id; the registry and
--- every runtime path are keyed by name).
local function dataRow(classFile, name)
    local data = Registry.DataFor(classFile)
    if type(data) ~= "table" then return nil end
    for _, sp in pairs(data) do
        if type(sp) == "table" and sp.name == name then return sp end
    end
    return nil
end

--- The live registry of one class, built the way the module builds it.
--- `Registry.entries` is the module's ONE live table: building the next class
--- wipes it, so a test that compares two classes copies the fields it asserts
--- out of it before it builds the next one.
local function registryFor(classFile)
    Registry:AttachStorage({})
    local n = Registry:Build(classFile)
    assertTrue(n and n > 0, "no registry for " .. tostring(classFile))
    local out = {}
    for name, entry in pairs(Registry.entries) do
        out[name] = {
            name = name, dataId = entry.dataId, duration = entry.duration,
            kind = entry.kind, tickEvery = entry.tickEvery,
            maxStack = entry.maxStack, noTarget = entry.noTarget,
        }
    end
    return out
end

-- ------------------------------------------------------------------- data --

test("the generated rows carry the Timer's three feed columns", function()
    -- A per-class census with a floor, not a spot check: the feeds are data,
    -- and a class that stops emitting them is the Timer losing a feature.
    local floors = {
        -- class: at least this many rows with a tick / a stack cap / self-only
        Hunter = { tick = 5, stack = 2, self = 10 },
        Warlock = { tick = 8, stack = 2, self = 12 },
        Mage = { tick = 5, stack = 1, self = 12 },
        Priest = { tick = 5, stack = 0, self = 5 },
        Druid = { tick = 8, stack = 2, self = 10 },
        Rogue = { tick = 4, stack = 3, self = 8 },
        Shaman = { tick = 2, stack = 0, self = 10 },
        Paladin = { tick = 2, stack = 1, self = 12 },
        Warrior = { tick = 2, stack = 2, self = 12 },
    }
    for i = 1, #CLASSES do
        local cls = CLASSES[i]
        local want = floors[cls]
        local tick, stack, self, rows = 0, 0, 0, 0
        local data = Registry.DataFor(cls)
        assertNotNil(data, cls .. "'s generated data did not load")
        for _, sp in pairs(data) do
            if type(sp) == "table" and type(sp.name) == "string" then
                rows = rows + 1
                -- The columns are typed and in range where they are present:
                -- seconds (never ms), a real cap, a true flag. A 0/0.0/false
                -- in the data would be the generator emitting absence as a
                -- value, which the registry's readers treat as a number.
                if sp.tickEvery ~= nil then
                    assertTrue(type(sp.tickEvery) == "number",
                        cls .. " " .. sp.name .. ": tickEvery is not a number")
                    assertTrue(sp.tickEvery > 0 and sp.tickEvery <= 120,
                        cls .. " " .. sp.name .. ": tickEvery out of the"
                        .. " seconds range (" .. tostring(sp.tickEvery) .. ")")
                    tick = tick + 1
                end
                if sp.maxStack ~= nil then
                    assertTrue(type(sp.maxStack) == "number" and sp.maxStack > 1,
                        cls .. " " .. sp.name .. ": maxStack is not a cap above 1")
                    stack = stack + 1
                end
                if sp.noTarget ~= nil then
                    assertTrue(sp.noTarget == true,
                        cls .. " " .. sp.name .. ": noTarget is not `true`")
                    self = self + 1
                end
            end
        end
        assertTrue(tick >= want.tick,
            cls .. ": only " .. tick .. " rows carry a tickEvery, floor " .. want.tick)
        assertTrue(stack >= want.stack,
            cls .. ": only " .. stack .. " rows carry a maxStack, floor " .. want.stack)
        assertTrue(self >= want.self,
            cls .. ": only " .. self .. " rows carry noTarget, floor " .. want.self)
        print(string.format("[feeds] %s: %d rows, %d tickEvery, %d maxStack, %d noTarget",
            cls, rows, tick, stack, self))
    end
end)

test("a periodic DoT carries the data's tick interval, in seconds", function()
    -- The tick marks are spaced by SECONDS (`UI/Rows.lua`: `t * every /
    -- maxTime` over the row's scale), so the generator's ms -> s division is
    -- the whole feature: a ms value here draws 12 marks where the row has 4.
    local h = registryFor("HUNTER")
    assertEquals(3, h["Serpent Sting"].tickEvery, "Serpent Sting ticks every 3 s")
    local w = registryFor("WARLOCK")
    assertEquals(3, w["Corruption"].tickEvery, "Corruption ticks every 3 s")
    -- A faster one, to prove the value is per-spell and not a constant.
    assertEquals(2, h["Viper Sting"].tickEvery, "Viper Sting ticks every 2 s")
    local p = registryFor("PRIEST")
    assertEquals(3, p["Renew"].tickEvery, "Renew ticks every 3 s")
    -- A DoT is a window ON a target: it is never a self window.
    assertEquals(false, h["Serpent Sting"].noTarget)
    assertEquals(false, w["Corruption"].noTarget)
    -- The interval is a fraction of the window: four marks on a 12 s row.
    assertTrue(h["Serpent Sting"].tickEvery < h["Serpent Sting"].duration)
end)

test("a stacking aura carries its stack cap", function()
    local h = registryFor("HUNTER")
    assertEquals(5, h["Scorpid Poison"].maxStack, "Scorpid Poison caps at 5")
    -- The pet poison is also periodic: a row may carry more than one feed.
    assertEquals(2, h["Scorpid Poison"].tickEvery)
    local wr = registryFor("WARRIOR")
    assertEquals(5, wr["Sunder Armor"].maxStack, "Sunder Armor caps at 5")
    -- A non-stacking window carries no cap at all (absence, not 1, not 0).
    assertNil(h["Serpent Sting"].maxStack)
    assertNil(wr["Sunder Armor"].tickEvery)
end)

test("a self window is noTarget and a window on a target is not", function()
    -- The original's `notTarget` column: such a cast is exactly ONE row,
    -- because every effect of it lands on the caster (design §3.3's targetKey
    -- "none", `Registry.IsNoTarget`).
    local h = registryFor("HUNTER")
    assertTrue(h["Deterrence"].noTarget, "Deterrence is a self window")
    assertTrue(h["Rapid Fire"].noTarget, "Rapid Fire is a self window")
    assertTrue(Registry.IsNoTarget("Deterrence"))
    assertTrue(Registry.IsNoTarget("Rapid Fire"))
    -- A window the caster puts ON something else is not one.
    assertFalse(h["Serpent Sting"].noTarget)
    assertFalse(Registry.IsNoTarget("Serpent Sting"))
    -- A party-wide window is not a caster-only one: Mark of the Wild rides the
    -- party target code, so it draws a row per unit it lands on.
    local d = registryFor("DRUID")
    assertFalse(d["Mark of the Wild"].noTarget,
        "a party-wide window is not a caster-only window")
    assertFalse(Registry.IsNoTarget("Mark of the Wild"))
    -- An untracked name is never a self window.
    assertFalse(Registry.IsNoTarget("Totally Made Up Nonsense"))
end)

test("the feeds ride base rows first, the store's captures and the rank siblings fill the gaps",
function()
    -- The law (gen_spell_data.py's feed sources, upstream-data §7.5 as the
    -- 1.60.1.70790 capture moved it): the row's OWN base `Effects`/`MaxStack`
    -- answer first; a picked row with no base row of its own INHERITS the
    -- same-family rank sibling's base shape (the M3a law); the store's own
    -- per-id feed captures (`periodMs`/`targetCode`/`maxStack`) fill what
    -- neither can speak to. The old "BASE DATA ONLY" shape -- the 70707
    -- overlay carrying no capture at all -- is what this test used to pin;
    -- the 70790 store captures feeds, so the pin is now the SHAPE of each
    -- source, one row per source, each failing on the pre-M3a data.
    -- (1) The store's own capture: Consume Shadows (the Warlock pet kit row,
    -- sourced -- no base row, no sibling) rides `periodMs` 2000 as the tick
    -- feed. A sourced row with a capture is the old law's death; a sourced
    -- row WITHOUT one still carries nothing (2).
    local w = registryFor("WARLOCK")
    assertEquals(2, w["Consume Shadows"].tickEvery,
        "the store's 2000 ms period capture arrives in SECONDS")
    for _, name in ipairs({ "Seduction", "Spell Lock", "Tainted Blood",
                            "Lesser Invisibility" }) do
        local entry = w[name]
        assertNotNil(entry, name .. " is not tracked")
        assertNil(entry.tickEvery,
            name .. ": a sourced row with no capture carries no tick feed")
        assertNil(entry.maxStack,
            name .. ": a sourced row with no capture carries no stack cap")
        assertEquals(false, entry.noTarget,
            name .. ": nothing proves a caster-only shape for it")
    end
    -- Seduction's targetCode capture answers the targeting half: 0 (a pet
    -- CV on a target), so noTarget stays a proven false, not an absence.
    assertEquals(false, w["Seduction"].noTarget)
    -- (2) The base row answers for a name the overlay MOVED: Immolate
    -- re-picked Rank 8 -> Rank 7 on 70707 and kept the base 3 s period.
    assertEquals(3, w["Immolate"].tickEvery)
    -- (3) The rank-sibling inheritance (M3a): the paladin's Oath of Light
    -- 1328548 is sourced (no base row); its class carries no sibling base
    -- row; the store's OWN capture answers the 1500 ms period. Live 70862
    -- store / review 2026-11-10: the target-code half moved -- noTarget is a
    -- proven FALSE now (paladin.json `_feeds`: the oath is cast on an ALLY,
    -- every store effect targets code 21; live-paladin-2026-11-09.md §1.1);
    -- re-pinned from `true`. The tick stays 1.5 s.
    local p = registryFor("PALADIN")
    assertEquals(1.5, p["Oath of Light"].tickEvery)
    assertEquals(false, p["Oath of Light"].noTarget)
    -- The echo family and Shieldsworn are the caster-side ones (`_feeds`):
    assertEquals(true, p["Shieldsworn"].noTarget)
    assertEquals(true, p["Echo of Fury"].noTarget)
    assertEquals(true, p["Echo of Command"].noTarget)
    -- (4) The sibling law proper: Holy Shield re-picked 20928 -> 1239570
    -- (Rank 4). The store's 1239570 capture carries NO Target field -- the
    -- caster-only shape comes from the base 20928 row, the name's SAME-
    -- FAMILY sibling. Before the sibling law the re-pick lost the flag
    -- (data-diff-live-2026-11-07.md §3 "loses noTarget -- check").
    assertEquals(true, p["Holy Shield"].noTarget,
        "the noTarget flag rode the rank move on the sibling's base shape")
    -- (5) The Mage pin: the 400573 self-buff brings its OWN feeds (a base
    -- row's Effects/MaxStack: 4 stacks, caster-targeted, an 18 s window --
    -- the store capture confirms the 4). Pre-M3a the name keyed the 18091
    -- proc row: no window, so no registry entry at all.
    local m = registryFor("MAGE")
    local ab = m["Arcane Blast"]
    assertNotNil(ab, "Arcane Blast is not in the Mage tracked set")
    assertEquals(18, ab.duration)
    assertEquals(4, ab.maxStack)
    assertEquals(true, ab.noTarget)
    assertNil(ab.tickEvery)
    -- The registry law that keeps the bar honest: a noTarget row draws
    -- exactly ONE self row (the target key is the constant "none").
    assertTrue(Registry.IsNoTarget("Arcane Blast"))
end)

-- -------------------------------------------------------------------- row --

test("the row born of a cast carries the feed the tick branch reads", function()
    -- The renderer's tick-mark branch (`UI/Rows.lua`, delta D6) reads
    -- `row.tickEvery`. A row built from a registry-fed insert therefore has to
    -- carry the entry's interval, or the feature stops at the registry.
    --
    -- `Rows.options` is the MODULE's live table (`Module.lua`'s `Init` hands it
    -- over), so a suite that replaces it has to give it back: a leaked stand-in
    -- table starves the suites that run after this one (the announce row's
    -- `expireMsgAt` stamp is read out of it).
    registryFor("HUNTER")
    local savedOptions = Rows.options
    Rows.options = {
        smooth = FX.Timer.Laws.SMOOTH, maxOn = false, maxRows = 32,
        oneMax = true, maxTimeOn = true, maxTime = FX.Timer.Laws.MAXTIME,
        groupID = true, outwands = true, blink = true,
        blinkAt = FX.Timer.Laws.BLINK, hideLonger = false,
        hideTime = FX.Timer.Laws.HIDE_TIME,
        expireMessage = true,
    }
    Rows:Clear()
    local row = Rows:InsertFromCast("Serpent Sting", "Vile Poacher", 12, 5000,
        5000, 1)
    assertNotNil(row)
    assertEquals(3, row.tickEvery, "the row carries the data's tick interval")
    -- A window the data gives no period for carries no tick feed at all, which
    -- is what keeps the branch's `every and every > 0` gate closed.
    local plain = Rows:InsertFromCast("Hunter's Mark", "Vile Poacher", 120,
        5000, 5000, 1)
    assertNotNil(plain)
    assertNil(plain.tickEvery)
    Rows:Clear()
    Rows.options = savedOptions
end)

test("the tick branch lays the marks the interval implies, from the row", function()
    -- Not a render call (that is the renderer suite's job): the branch's OWN
    -- arithmetic over the row's fields, which is the shape the feed has to
    -- arrive in. `UI/Rows.lua`:
    --     local every = row.tickEvery
    --     if o.ticks and every and every > 0 and row.maxTime > 0 then
    --         local count = math.min(12, math.floor(row.maxTime / every))
    registryFor("HUNTER")
    Rows:Clear()
    local row = Rows:InsertFromCast("Serpent Sting", "Vile Poacher", 12, 5000,
        5000, 1)
    assertNotNil(row)
    row.maxTime = row.total                        -- the compression scale
    local function marksFor(r)
        local every = r.tickEvery
        if not (every and every > 0 and r.maxTime > 0) then return 0 end
        return math.min(12, math.floor(r.maxTime / every))
    end
    -- Serpent Sting: a 12 s window on a 3 s period = 4 marks.
    assertEquals(4, marksFor(row))
    -- Haste scales the window, so the marks follow it (12 s * 2 = 8 at 3 s).
    local hasted = Rows:InsertFromCast("Serpent Sting", "Ravasaur", 12, 5000,
        5000, 2)
    assertNotNil(hasted)
    hasted.maxTime = hasted.total
    assertEquals(8, marksFor(hasted))
    -- The 12-mark ceiling (a Warlock DoT: 600 s of window on a 3 s period is
    -- 200 periods), and no marks at all without a period.
    registryFor("WARLOCK")
    local long = Rows:InsertFromCast("Corruption", "Ravasaur", 600, 5000,
        5000, 1)
    assertNotNil(long)
    assertEquals(3, long.tickEvery)
    long.maxTime = long.total
    assertEquals(12, marksFor(long), "the branch caps at 12 marks")
    local plain = Rows:InsertFromCast("Hunter's Mark", "Vile Poacher", 120,
        5000, 5000, 1)
    assertNotNil(plain)
    plain.maxTime = plain.total
    assertEquals(0, marksFor(plain), "no period, no marks")
    Rows:Clear()
end)
