-- addon/Forte_Cooldown/tests/test_test_mode.lua
-- The cooldown half of the demo pilot (`/fx test`,
-- Forte_Core/Core/TestMode.lua): the feeder the Module registers, the gates on
-- the two entry writers (M:ReadAll, M:RecordCastEvent), the pop-side silence
-- (a synthetic pop feeds the bar's pulse and the Secondary Splash and does NOT
-- fire FX_COOLDOWN_READY), the refill after `Engine:Build`'s wipe, and the
-- donor law -- the synthetic rows come from the tracked pool, carry no `dObj`
-- and no `itemID`, and touch no secret-prone read.
-- docs/research/upstream-addons-2026-11-03.md §6 "Test Mode" is the feature law
-- (CooldownMaster Core/Cooldown.lua:233-255 "all feeds are skipped while Test
-- Mode is active"; its demo law: the entries are drawn from the donor pool and
-- carry no dObj / itemID).
--
-- The pop is driven through the Module's REAL public path
-- (`Module:ProcessReadyPops`, the body of the 10 Hz ticker), the idiom
-- tests/test_splash.lua establishes; the C_Timer ticker is not reachable
-- headless. The bus is watched through `FX.On`, the real registry. The
-- gate run's login sequence does not reach Forte_Core's module loop (the
-- finding of tests/test_timeline.lua), so the enable path is driven by hand.
--
-- Every synthetic name is one THIS FILE put into `Engine.tracked` in the
-- generated data's shape (`name`, `dataId`, `baseDuration`): the fill reads the
-- pool, and the gate run's client knows no spells at all, so an unseeded pool
-- means an empty fill -- and an empty fill is what the donor tests say so.

local FX = ForteXorcist
local Module = FX.Cooldown.Module
local Engine = FX.Cooldown.Engine
local Splash = FX.Cooldown.Splash
local T = FX.TestMode

local function seedTracked(n)
    local made = {}
    for i = 1, n do
        local name = "DemoCd Spell " .. i
        Engine.tracked[name] = {
            name = name, dataId = 910000 + i, baseDuration = 8 + i * 2,
        }
        made[#made + 1] = name
    end
    return made
end

local function unseedTracked()
    for name in pairs(Engine.tracked) do
        if name:find("^DemoCd") then Engine.tracked[name] = nil end
    end
end

local function dropDemoEntries()
    for name, e in pairs(Engine.entries) do
        if T.IsSynthetic(e) then Engine.entries[name] = nil end
    end
end

local function isTrackedName(name)
    return type(name) == "string" and Engine.tracked[name] ~= nil
end

local function taggedCount()
    local n = 0
    for _, e in pairs(Engine.entries) do
        if T.IsSynthetic(e) then n = n + 1 end
    end
    return n
end

local function activeIcons()
    local n = 0
    for _, slot in ipairs(Splash._icons or {}) do
        if slot.active then n = n + 1 end
    end
    return n
end

--- The stop, plus the belt-and-braces scrub: a failed assert earlier in the
--- file must not leave synthetic rows in the bar for tests/test_splash.lua and
--- tests/test_timeline.lua, which run behind this one.
local function stopQuietly()
    if T.active then T:Stop("test") end
    dropDemoEntries()
    Splash:SetEnabled(false)
    Splash:Update(GetTime() + 100)
    unseedTracked()
end

-- ------------------------------------------------------------------ enable --

test("the module registers the bar's feeder exactly once", function()
    assertNotNil(T, "Forte_Core's demo pilot is loaded")
    if not Module._eventFrame then Module:OnEnable() end
    local hits = 0
    for _, f in ipairs(T.feeders) do
        if f.Name == "Cooldown" then
            hits = hits + 1
            assertEquals("function", type(f.Fill))
            assertEquals("function", type(f.Scrub))
            assertEquals("function", type(f.Live))
        end
    end
    assertEquals(1, hits, "the enable is idempotent: one feeder, not two")
    assertEquals(false, T.active, "the enable does not start the demo")
end)

-- ---------------------------------------------------------------- the fill --

test("the fill draws its donors from the tracked pool, tagged and bare",
function()
    stopQuietly()
    seedTracked(9)
    T:Start()
    assertTrue(T.active)
    local n = taggedCount()
    assertTrue(n > 0, "the bar has synthetic entries (" .. n .. ")")
    for name, e in pairs(Engine.entries) do
        if T.IsSynthetic(e) then
            -- The donor law: every synthetic name is a name of OUR tracked
            -- pool -- the generated class data, the spell list the player
            -- really has -- never a name typed into this file or a command
            -- line, and the fill never reads the client for one.
            assertTrue(isTrackedName(name),
                "the donor is a tracked name, never a typed id: "
                .. tostring(name))
            -- The demo-entry law of the upstream note: no data object, no item
            -- id, so no consumer resolves the row against a live unit.
            assertEquals(nil, e.dObj)
            assertEquals(nil, e.itemID)
            assertEquals(nil, e.itemId)
            assertEquals("test", e._source)
            -- The window is a plain number pair of our own making: the bar's
            -- book-keeping needs no client read, which is what keeps the demo
            -- out of the sealed-read path entirely.
            assertTrue(e.duration > 0)
            assertTrue(e.endTime > e.start)
        end
    end
    stopQuietly()
    assertEquals(0, taggedCount(), "the exit scrubs the bar")
end)

test("a charge spell is not a donor: the bar shows no spare charges",
function()
    stopQuietly()
    seedTracked(0)
    unseedTracked()
    Engine.tracked["DemoCd Charged"] = {
        name = "DemoCd Charged", dataId = 919999, baseDuration = 12,
        maxCharges = 3,
    }
    Engine.tracked["DemoCd Only Charge"] = {
        name = "DemoCd Only Charge", dataId = 919998, baseDuration = 14,
        maxCharges = 2,
    }
    T:Start()
    for name, e in pairs(Engine.entries) do
        if T.IsSynthetic(e) then
            assertEquals(nil, Engine.tracked[name].maxCharges,
                "the donor " .. tostring(name) .. " is not a charge spell")
            assertEquals(nil, e.charges)
        end
    end
    assertEquals(nil, Engine.entries["DemoCd Charged"])
    assertEquals(nil, Engine.entries["DemoCd Only Charge"])
    stopQuietly()
end)

-- ---------------------------------------------------------------- the gates --

test("the read pass is parked while the mode runs, and not while it is off",
function()
    stopQuietly()
    seedTracked(6)
    local reads = 0
    -- `OnReadActive` is the pass's unconditional leg: every tracked name goes
    -- through it on every pass, whatever the client's info read answers (the
    -- gate run's client answers nothing at all), so it is the honest witness
    -- of "did the read net run".
    local realActive = Engine.OnReadActive
    Engine.OnReadActive = function(self, name, isActive, isOnGCD, now)
        reads = reads + 1
        return realActive(self, name, isActive, isOnGCD, now)
    end
    Module:ReadAll()
    local baseline = reads
    assertTrue(baseline > 0,
        "the witness moves for a real pass (" .. baseline .. ")")
    T:Start()
    Module:ReadAll()
    assertEquals(baseline, reads, "the read net is parked during the demo")
    T:Stop("test")
    Module:ReadAll()
    assertTrue(reads > baseline,
        "and runs the moment the mode is off (" .. (reads - baseline)
        .. " reads)")
    Engine.OnReadActive = realActive
    dropDemoEntries()
    unseedTracked()
end)

test("the cast feed is parked while the mode runs, counters and entry alike",
function()
    stopQuietly()
    seedTracked(0)
    local diag = Module:InitCastDiag()
    local seen = diag.seen
    T:Start()
    Module:RecordCastEvent(12345, false)
    assertEquals(seen, diag.seen,
        "a parked event is not a seen event: the counters stay launch-day")
    assertEquals(nil, Engine.entries["DemoCd Spell 1"],
        "no entry came from the parked cast")
    T:Stop("test")
    Module:RecordCastEvent(12345, false)
    assertEquals(seen + 1, diag.seen, "and the feed runs when the mode is off")
    dropDemoEntries()
    unseedTracked()
end)

-- ------------------------------------------------------------ the pop gate --

test("a synthetic pop feeds the splash and fires no FX_COOLDOWN_READY",
function()
    stopQuietly()
    local donors = seedTracked(4)
    Splash:OnEnable()
    Splash:SetEnabled(true)
    local seen = {}
    local off = FX.On("FX_COOLDOWN_READY", function(name)
        seen[#seen + 1] = name
    end)
    T:Start()
    assertTrue(T.active)
    -- Drive the pop window of every synthetic entry to the instant of the
    -- sweep, so the whole fill pops in one pass.
    local popAt = GetTime() + 5000
    local n = 0
    for _, e in pairs(Engine.entries) do
        if T.IsSynthetic(e) then
            n = n + 1
            e.endTime = popAt - 1
        end
    end
    assertTrue(n > 0, "the fill is present to pop")
    Module:ProcessReadyPops(popAt)          -- the ticker's real body
    assertTrue(activeIcons() > 0,
        "the Secondary Splash took the pops (" .. activeIcons() .. " icons)")
    assertEquals(0, #seen,
        "the bus heard nothing: " .. table.concat(seen, ", "))
    if off then FX.Off(off) end
    stopQuietly()
end)

-- The other half of that law -- a real, untagged pop keeps firing
-- FX_COOLDOWN_READY -- is the property tests/test_splash.lua's
-- "FX_COOLDOWN_READY fires once per pop" row proves through this same
-- `Module:ProcessReadyPops` path (it drives the pop with real
-- `Engine:OnCast` entries and counts the bus events), and it is green with the
-- tag gate in the loop: the gate fires on the tag and on nothing else.

-- ------------------------------------------------------------- the rebuild --

test("a rebuild's wipe is followed by the demo's own refill", function()
    stopQuietly()
    seedTracked(8)
    T:Start()
    local before = taggedCount()
    assertTrue(before > 0, "the bar is filled")
    Module:Rebuild()          -- Engine:Build wipes entries, then the hook runs
    local after = taggedCount()
    assertTrue(after > 0, "the demo rows are back after the wipe ("
        .. before .. " -> " .. after .. ")")
    T:Stop("test")
    Module:Rebuild()          -- out of demo mode: a rebuild stays a rebuild
    assertEquals(0, taggedCount(), "and no demo row comes back on its own")
    dropDemoEntries()
    unseedTracked()
end)

test("the scrub never touches a real entry", function()
    stopQuietly()
    seedTracked(6)
    -- The read path's shape, for a name the demo has no claim on: the scrub
    -- keys on the tag and on nothing else.
    Engine.entries["DemoCd Keeper"] = {
        name = "DemoCd Keeper", start = GetTime(), duration = 30,
        endTime = GetTime() + 30, predicted = false, source = "read",
        anchored = true,
    }
    T:Start()
    T:Stop("test")
    assertNotNil(Engine.entries["DemoCd Keeper"],
        "the scrub is the tag, never the container")
    Engine.entries["DemoCd Keeper"] = nil
    dropDemoEntries()
    unseedTracked()
end)

test("the suite leaves the shipped state as it found it", function()
    stopQuietly()
    assertEquals(false, T.active)
    assertEquals(0, taggedCount())
    for name in pairs(Engine.entries) do
        if name:find("^DemoCd") then Engine.entries[name] = nil end
    end
    unseedTracked()
    assertEquals(nil, Engine.tracked["DemoCd Spell 1"])
end)
