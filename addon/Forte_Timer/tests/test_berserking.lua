-- addon/Forte_Timer/tests/test_berserking.lua
-- Owner report 2026-11-14 (live client, Troll Hunter): "Berserking does not
-- show on the Spell Timer when used (it does show on the cooldown bar)".
--
-- Cause: `Registry:Build` registers only rows with `durationMs > 0`, and the
-- generated Berserking row carried only `cooldownMs = 180000` (the live store
-- has value-less name shells for Berserking and nothing else supplies the
-- buff's length). The fix is DATA: `tools/overrides_devnotes_2026-11-03.json`
-- row 20554 `durationMs = 15000` (the 26/27 Oct dev notes "Troll Berserking
-- 15 s", wowsims/forever sim/core/racials.go @ 264068ee -- NOT yet confirmed
-- on the live client tooltip) and every `tools/spell_lists/<class>.json`
-- `_feeds` entry `Berserking = noTarget` (the racial is a self haste buff and
-- the store's shells carry no Effects/Targets the generator could read).
--
-- Driven through the real paths: the generated data -> `Registry:Build` ->
-- the module's real event frame (UNIT_SPELLCAST_SENT / SUCCEEDED, the
-- test_module.lua dispatch idiom) -> the settle pump -> the row; the
-- dead-target cleanup is the real UNIT_DIED branch (test_unit_died.lua idiom).
-- Name-keyed: the spell id is read OFF the generated data row, never typed.
local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Registry = FX.Timer.Registry
local Casts = FX.Timer.Casts

-- The sim profile is not a Hunter / Troll: ask for the add-ons through the
-- login path's own loader (the test_data_feeds.lua idiom).
local TROLL_CLASSES = { "DRUID", "HUNTER", "MAGE", "PRIEST", "ROGUE", "SHAMAN",
    "WARLOCK", "WARRIOR" }
for i = 1, #TROLL_CLASSES do FX.LoadClassAddOn(TROLL_CLASSES[i]) end

local function near(actual, expected)
    assertTrue(math.abs(actual - expected) < 1e-6,
        "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function buildRegistry(classFile)
    Registry:AttachStorage({})
    local n = Registry:Build(classFile)
    assertTrue(n and n > 0, "no registry for " .. tostring(classFile))
end

local function enableTimer()
    if not M.options then M:OnEnable() end
    assertNotNil(M._eventFrame, "the event frame is bound")
end

local function dispatch(event, a1, a2, a3, a4)
    local f = M._eventFrame
    assertNotNil(f)
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    onEvent(f, event, a1, a2, a3, a4)
end

local clock
local function installClock(base)
    clock = { base }
    Casts.now = function() return clock[1] end
    return clock
end

--- The unit-identity trio of test_pet_rows.lua, plus UnitIsDeadOrGhost for
--- the UNIT_DIED gate (test_unit_died.lua installUnitState): `names` maps a
--- unit token to the name it answers, `dead` is the dead verdict of "target".
local function installUnits(names, dead)
    local saved = {
        UnitExists = _G.UnitExists, UnitName = _G.UnitName,
        UnitIsDead = _G.UnitIsDead, UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost,
    }
    _G.UnitExists = function(token) return names[token] ~= nil end
    _G.UnitName = function(token) return names[token] end
    _G.UnitIsDead = function(token) return token == "target" and dead or false end
    _G.UnitIsDeadOrGhost = function(token)
        return token == "target" and dead or false
    end
    return saved
end
local function restoreUnits(saved)
    _G.UnitExists, _G.UnitName = saved.UnitExists, saved.UnitName
    _G.UnitIsDead, _G.UnitIsDeadOrGhost =
        saved.UnitIsDead, saved.UnitIsDeadOrGhost
end

--- Hunter registry + the id -> name seam, the id read off the data row.
local savedResolve, savedNow
local function useHunterData()
    buildRegistry("HUNTER")
    local entry = Registry.entries["Berserking"]
    assertNotNil(entry, "Berserking is not on the Hunter's Spell Timer registry")
    local id = entry.dataId
    Casts.resolveName = function(spellId)
        return spellId == id and "Berserking" or nil
    end
    return id
end

local savedUnits
local function setup()
    enableTimer()
    savedResolve, savedNow = Casts.resolveName, Casts.now
    savedUnits = {
        UnitExists = _G.UnitExists, UnitName = _G.UnitName,
        UnitIsDead = _G.UnitIsDead, UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost,
    }
    Casts:Erase()
    Rows:Clear()
end
local function teardown()
    Rows:Clear()
    Casts:Erase()
    Casts.resolveName, Casts.now = savedResolve, savedNow
    if savedUnits then restoreUnits(savedUnits) end
end

--- A test whose stubs (the unit trio, the Casts seams, the rows) are put
--- back even when an assertion fails: a failing leg must not poison the
--- suites that run after it (test_module.lua's UNIT_AURA leg reads the live
--- unit globals).
local function case(name, fn)
    test(name, function()
        setup()
        local ok, err = pcall(fn)
        teardown()
        if not ok then error(err, 0) end
    end)
end

-- ------------------------------------------------------------------ data --

test("the generated row carries the 15 s buff, self-only, beside the 180 s cooldown",
function()
    -- Eight classes roll a Troll in the rosters (the paladin roster is Human/
    -- Dwarf only): each carries the SAME row. Pre-fix the row had no
    -- `durationMs` and no `noTarget`, so the registry had no Berserking entry.
    for i = 1, #TROLL_CLASSES do
        local cls = TROLL_CLASSES[i]
        local data = Registry.DataFor(cls)
        assertNotNil(data, cls .. "'s generated data did not load")
        local row
        for _, sp in pairs(data) do
            if type(sp) == "table" and sp.name == "Berserking" then row = sp end
        end
        assertNotNil(row, cls .. " carries no Berserking row")
        assertEquals(true, row.racial, cls .. ": the racial flag")
        assertEquals(15000, row.durationMs, cls .. ": the buff's length (ms)")
        assertEquals(true, row.noTarget, cls .. ": a self haste buff")
        -- The cooldown bar's own value is untouched (Forte_Cooldown suites).
        assertEquals(180000, row.cooldownMs, cls .. ": the bar's 180 s")
        buildRegistry(cls)
        local e = Registry.entries["Berserking"]
        assertNotNil(e, cls .. ": Berserking is not on the Spell Timer registry")
        near(e.duration, 15)
        assertEquals("SelfBuff", e.kind, cls .. ": the self-buff band")
        assertEquals(true, e.noTarget, cls .. ": noTarget")
        assertTrue(Registry.IsNoTarget("Berserking"))
    end
end)

test("the Dwarf racial stays untracked: no evidence for a Rapid Regeneration length",
function()
    -- Assignment item 3: nothing supplies a duration for Rapid Regeneration,
    -- so it has no Spell Timer row (it keeps its 180 s cooldown bar). The day
    -- a measured duration lands this pin moves with it, deliberately.
    buildRegistry("HUNTER")
    assertNil(Registry.entries["Rapid Regeneration"])
    assertNotNil(Registry.entries["Berserking"])
end)

-- ------------------------------------------------------------------ cast --

--- One Berserking cast through the real event frame, the row landed by the
--- module's own pump after the settle. `sentTarget` is the SENT payload's
--- target string (nil = no SENT at all: the lone SUCCEEDED path).
local function castBerserking(id, sentTarget, guid)
    local before = Rows:Count()
    if sentTarget ~= nil then
        dispatch("UNIT_SPELLCAST_SENT", "player", sentTarget, guid, id)
    end
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", guid, id, 7)
    assertEquals(before, Rows:Count(), "the settle defers the insert (CA-04)")
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
end

case("a cast with an ENEMY targeted makes exactly ONE row, keyed \"none\", 15 s (fails on the unfixed data)",
function()
    local id = useHunterData()
    installClock(70000)
    -- The worst case for the key: the client's SENT names the enemy target.
    local saved = installUnits({ target = "Vile Poacher" }, false)
    castBerserking(id, "Vile Poacher", "GUID:1:20:1:1")
    restoreUnits(saved)
    assertEquals(1, Rows:Count(), "exactly one row")
    local row = Rows:Find("Berserking", "none")
    assertNotNil(row, "the row is keyed \"none\" (the self-buff law, design §3.3)")
    assertNil(Rows:Find("Berserking", "Vile Poacher"),
        "no row keyed to the enemy target")
    near(row.total, 15)
    assertEquals("SelfBuff", row.kind)
    assertNil(row.unitToken, "a self row carries no target token")
    assertTrue(row.predicted, "a cast-born row is a prediction until a read adopts it")
end)

case("a cast whose SENT carries no target, and a lone SUCCEEDED, make the same one self row",
function()
    local id = useHunterData()
    installClock(71000)
    local saved = installUnits({ target = "Vile Poacher" }, false)
    castBerserking(id, "", "GUID:1:20:2:1")
    assertEquals(1, Rows:Count())
    assertNotNil(Rows:Find("Berserking", "none"))
    Rows:Clear()
    Casts:Erase()
    castBerserking(id, nil, "GUID:1:20:3:1")
    restoreUnits(saved)
    assertEquals(1, Rows:Count())
    assertNotNil(Rows:Find("Berserking", "none"))
end)

case("a second cast refreshes the one row, never a second one",
function()
    local id = useHunterData()
    installClock(72000)
    local saved = installUnits({ target = "Vile Poacher" }, false)
    castBerserking(id, "Vile Poacher", "GUID:1:20:4:1")
    clock[1] = clock[1] + 1
    castBerserking(id, "Vile Poacher", "GUID:1:20:5:1")
    restoreUnits(saved)
    local live = 0
    for _, r in ipairs(Rows:AllForName("Berserking")) do
        if r.state <= Laws.NORMAL then live = live + 1 end
    end
    assertEquals(1, live, "one live Berserking row")
end)

-- ----------------------------------------------------------- target death --

case("the row survives its enemy target's death (the dead-target cleanup is not for it)",
function()
    local id = useHunterData()
    installClock(73000)
    local saved = installUnits({ target = "Vile Poacher" }, false)
    castBerserking(id, "Vile Poacher", "GUID:1:20:6:1")
    local row = Rows:Find("Berserking", "none")
    assertNotNil(row)
    -- A target-token row on the same enemy: proves the leg is live (it IS
    -- retired by the same event), so the survival below is not vacuous.
    local now = GetTime()
    local sting = Rows:InsertFromAura("Serpent Sting", "Vile Poacher",
        now + 60, 60, 0, "target", 0, now, "000000000000FE00\1Vile Poacher\1D")
    assertNotNil(sting)
    restoreUnits(saved)
    -- The kill: the corpse keeps the token, the DEAD read answers true.
    saved = installUnits({ target = "Vile Poacher" }, true)
    dispatch("UNIT_DIED", "Creature-0-1142-65-1-1096-0")
    restoreUnits(saved)
    assertEquals(Laws.REMOVE, sting.state, "the enemy's own row died with it")
    assertEquals(Laws.NORMAL, row.state, "the Berserking row rides on")
    -- And the token-gone trigger (corpse looted / target cleared).
    saved = installUnits({}, nil)
    dispatch("UNIT_DIED", "Creature-0-1142-65-1-1096-0")
    restoreUnits(saved)
    assertEquals(Laws.NORMAL, row.state, "still riding after the target token is gone")
    assertNotNil(Rows:Find("Berserking", "none"))
end)

-- ----------------------------------------------------------------- expiry --

case("the window ends after 15 s, not before",
function()
    local id = useHunterData()
    installClock(74000)
    local saved = installUnits({ target = "Vile Poacher" }, false)
    castBerserking(id, "Vile Poacher", "GUID:1:20:7:1")
    restoreUnits(saved)
    local row = Rows:Find("Berserking", "none")
    assertNotNil(row)
    local start = row.expireAt - row.total
    near(row.expireAt - start, 15)
    Rows:Sweep(start + 14.5)
    assertEquals(Laws.NORMAL, row.state, "alive at 14.5 s")
    Rows:Sweep(start + 15.05)
    assertTrue(row.state > Laws.NORMAL, "past 15 s the row leaves its window")
end)
