-- addon/Forte_Timer/tests/test_test_mode.lua
-- The Spell Timer half of the demo pilot (`/fx test`,
-- Forte_Core/Core/TestMode.lua): the feeder the Module registers, the fill of
-- the panel through the panel's own insert path, the gates on the three row
-- WRITERS (the event spine, `Casts:Pump`, `Reconcile:SweepAll`) against the one
-- pass that must keep running (`Rows:Sweep`, the row lifecycle machine the
-- synthetic rows ride), the fire-side silence (a tagged row fires no
-- FX_TIMER_FADING / FX_TIMER_EXPIRED / announce, a real one fires them
-- exactly as it did before this slice), and the scrub, which removes tagged
-- rows only and leaves the array dense.
-- docs/research/upstream-addons-2026-11-03.md §6 "Test Mode" is the feature law
-- (CooldownMaster Core/Cooldown.lua:233-255: gate every feed; a demo entry
-- carries no dObj / itemID; keep the demo off secret-prone reads).
--
-- The drives are the real ones: the frame's own OnEvent script (the binding law
-- of PLAN §10.2, the frame is argument 1), `M:Logic()`, `Rows:Sweep`, and the
-- public draw pair `Rows:Sorted` + `Display:Update` (the idiom
-- tests/test_module.lua establishes). The gate run's login sequence does not
-- reach Forte_Core's module loop (the finding of tests/test_timeline.lua), so
-- the enable path is driven by hand. The writers are measured through the
-- module's own seams, because the gate run's client knows no spells: the
-- registry the module builds from Forte_Paladin's data is the donor pool, and
-- a spy on the writer is the sharp assertion.

local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Registry = FX.Timer.Registry
local Display = FX.Timer.Display
local T = FX.TestMode

local function enableAll()
    if not T._eventFrame then T:OnEnable() end
    if not M.options then M:OnEnable() end
end

local function dispatch(event, a1, a2, a3, a4)
    local f = M._eventFrame
    assertNotNil(f)
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    onEvent(f, event, a1, a2, a3, a4)
end

local function taggedRows()
    local names, n = {}, 0
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) then
            n = n + 1
            names[n] = row.name
        end
    end
    return names, n
end

local function dropTaggedRows()
    for i = Rows.rows_n, 1, -1 do
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) then Rows:removeAt(i) end
    end
    Rows:Compact()
end

--- The stop, plus the belt-and-braces scrub: a failed assert earlier in this
--- file must not leave synthetic rows in the panel for the suites that run
--- behind it.
local function stopQuietly()
    if T.active then T:Stop("test") end
    dropTaggedRows()
end

-- ------------------------------------------------------------------ enable --

test("the module registers the panel's feeder exactly once", function()
    assertNotNil(T, "Forte_Core's demo pilot is loaded")
    enableAll()
    local hits = 0
    for _, f in ipairs(T.feeders) do
        if f.Name == "SpellTimer" then
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

test("the fill puts tagged rows on the panel through the panel's own insert",
function()
    enableAll()
    stopQuietly()
    Rows:Clear()
    local tracked = Registry:Counts()
    if tracked == 0 then
        -- No registered data for this client's class is a fact about the gate
        -- run, not a pass: say so loudly.
        error("the Timer's registry is empty: no donor pool to fill from")
    end
    T:Start()
    assertTrue(T.active)
    local names, n = taggedRows()
    assertTrue(n > 0, "the panel has synthetic rows (" .. n .. ")")
    for _, name in ipairs(names) do
        assertTrue(type(Registry.entries[name]) == "table",
            "the donor is a registered name, never a typed id: "
            .. tostring(name))
    end
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) then
            -- No unit is invented for a made-up row: the panel's self/no-target
            -- key, so the group key is a PRIOR_* sentinel and no consumer
            -- resolves the row against a live unit (the CDM "no dObj" law).
            assertEquals("none", row.targetKey)
            -- The two legs that speak: the announce stamp (col 12, the
            -- `opts.onExpire` chat line) and the fade-warning threshold (the
            -- FX_TIMER_FADING fire) are disarmed at the seam.
            assertEquals(0, row.expireMsgAt)
            assertEquals(0, row.fadeWarn)
            assertEquals(true, row.predicted, "the insert is the cast path")
            assertEquals(nil, row.dObj)
        end
    end
    -- The fill rode the panel's own synchronous kick: the rows are drawn
    -- without any OnUpdate being relied on (the hidden-frame law).
    local now = M:Clock()
    local links, ln = Rows:Sorted({}, now)
    assertEquals(n, ln, "every synthetic row reaches the link pass")
    local drawn = Display:Update(links, ln, M.options, M.skin)
    assertTrue(drawn > 0, "and the renderer draws them (" .. drawn .. ")")
    stopQuietly()
    local _, after = taggedRows()
    assertEquals(0, after, "the exit scrubs the panel")
end)

-- ---------------------------------------------------------------- the gates --

test("the cast feed of the event spine is parked while the mode runs",
function()
    enableAll()
    stopQuietly()
    local C = FX.Timer.Casts
    local realSucceeded = C.OnSucceeded
    local hits = 0
    C.OnSucceeded = function(self, spellID)
        hits = hits + 1
        return realSucceeded(self, spellID)
    end
    T:Start()
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "GUID:1", 42)
    dispatch("UNIT_SPELLCAST_SENT", "player", "Dummy", "GUID:1", 42)
    dispatch("UNIT_SPELLCAST_START", "player", "GUID:1", 42)
    dispatch("UNIT_SPELLCAST_INTERRUPTED", "player", "GUID:1", 42)
    dispatch("UNIT_AURA", "player", {})
    dispatch("PLAYER_TARGET_CHANGED")
    assertEquals(0, hits, "no cast fact reaches the queue during the demo")
    T:Stop("test")
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "GUID:2", 42)
    assertEquals(1, hits, "and the spine runs the moment the mode is off")
    C.OnSucceeded = realSucceeded
    C:Erase()
end)

test("the two Logic writers are parked; the row machine is not", function()
    enableAll()
    stopQuietly()
    local C, R = FX.Timer.Casts, FX.Timer.Reconcile
    local realPump, realSweep = C.Pump, R.SweepAll
    local pumps, sweeps = 0, 0
    C.Pump = function(self, now) pumps = pumps + 1; return realPump(self, now) end
    R.SweepAll = function(self, now) sweeps = sweeps + 1
        return realSweep(self, now) end
    T:Start()
    M:Logic()
    assertEquals(0, pumps, "the cast pump is parked")
    assertEquals(0, sweeps, "the aura sweep is parked")
    -- The machine of the rows themselves rides on: the synthetic rows have to
    -- expire, promote to fading and leave, exactly as a real row does, or the
    -- panel is a still photograph.
    local now = M:Clock()
    Rows:InsertFromCast("DemoMachine Spell", "none", 2, now - 3, now - 3, 1)
    local row = Rows.rows[Rows.rows_n]
    assertNotNil(row)
    assertEquals(Laws.NORMAL, row.state)
    M:Logic()
    assertTrue(row.state > Laws.NORMAL,
        "Rows:Sweep ran: the window expired and promoted (" .. row.state .. ")")
    T:Stop("test")
    M:Logic()
    assertTrue(pumps > 0 and sweeps > 0,
        "and both writers run out of demo mode")
    C.Pump, R.SweepAll = realPump, realSweep
    Rows:Clear()
    Display:RenderIdle()
end)

test("the combat-end aura sweep is parked, the secrecy snapshot is not",
function()
    enableAll()
    stopQuietly()
    local R = FX.Timer.Reconcile
    local realSweep = R.SweepAll
    local sweeps = 0
    R.SweepAll = function(self, now) sweeps = sweeps + 1
        return realSweep(self, now) end
    local refreshed = 0
    local realRefresh = FX.Timer.RefreshSecretState
    FX.Timer.RefreshSecretState = function(...)
        refreshed = refreshed + 1
        return realRefresh(...)
    end
    T:Start()
    dispatch("PLAYER_REGEN_ENABLED")
    assertEquals(0, sweeps, "the sweep is parked")
    assertEquals(1, refreshed, "the snapshot is a read and keeps running")
    T:Stop("test")
    dispatch("PLAYER_REGEN_ENABLED")
    assertTrue(sweeps > 0, "and it runs out of demo mode")
    R.SweepAll = realSweep
    FX.Timer.RefreshSecretState = realRefresh
end)

-- ------------------------------------------------------------ the fire gate --

test("a synthetic row fires no bus event and prints no announce", function()
    enableAll()
    stopQuietly()
    Rows:Clear()
    local fired = { fading = 0, expired = 0, broken = 0 }
    local offs = {
        FX.On(FX.EVENTS.TIMER_FADING, function()
            fired.fading = fired.fading + 1 end),
        FX.On(FX.EVENTS.TIMER_EXPIRED, function()
            fired.expired = fired.expired + 1 end),
        FX.On(FX.EVENTS.TIMER_BROKEN, function()
            fired.broken = fired.broken + 1 end),
    }
    -- The announce gate ON, on the options table the row machine reads
    -- (`Rows.options`, the pair the module's enable publishes): a row born now
    -- carries the col-12 stamp, so the chat leg is live for a real row and
    -- disarmed for a synthetic one. The channel is counted through the seam
    -- tests/test_rows.lua uses.
    local ro = Rows.options
    assertNotNil(ro, "the enable published the row options")
    local wasMessage, wasChannel = ro.expireMessage, ro.onExpire
    local announced = 0
    ro.expireMessage = true
    ro.onExpire = function() announced = announced + 1 end
    local now = M:Clock()
    T:Start()
    local _, n = taggedRows()
    assertTrue(n > 0)
    for i = 1, Rows.rows_n do          -- run every synthetic window out
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) then
            row.expireAt = now - 1
            row.drawExpireAt = row.expireAt
        end
    end
    Rows:InsertFromCast("DemoReal Spell", "none", 2, now - 3, now - 3, 1)
    local real = Rows.rows[Rows.rows_n]
    assertNotNil(real)
    assertEquals(nil, real._source)
    assertEquals(1, real.expireMsgAt,
        "the real row carries the announce stamp the gate arms")
    Rows:Sweep(now)
    assertTrue(fired.expired >= 1,
        "the real row's expiry fired (" .. fired.expired .. ")")
    assertEquals(1, announced,
        "and exactly one announce: the synthetic rows printed nothing")
    assertEquals(0, fired.fading, "the fade leg is disarmed at the seam")
    -- A tagged row that BREAKS is silent too.
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) then
            Rows:OnAuraAbsent(row, now)
        end
    end
    assertEquals(0, fired.broken, "no FX_TIMER_BROKEN for a made-up row")
    ro.expireMessage, ro.onExpire = wasMessage, wasChannel
    for _, off in ipairs(offs) do if off then FX.Off(off) end end
    Rows:Clear()
    Display:RenderIdle()
    if T.active then T:Stop("test") end
end)

-- ---------------------------------------------------------------- the scrub --

test("the scrub removes tagged rows only and leaves the array dense",
function()
    enableAll()
    stopQuietly()
    Rows:Clear()
    local now = M:Clock()
    Rows:InsertFromCast("DemoKeeper Spell", "none", 30, now, now, 1)
    local keeper = Rows.rows[Rows.rows_n]
    assertNotNil(keeper)
    assertEquals(nil, keeper._source)
    T:Start()
    local _, filled = taggedRows()
    assertTrue(filled > 0)
    T:Stop("test")
    local _, after = taggedRows()
    assertEquals(0, after, "the tagged rows are gone")
    assertNotNil(Rows:Find("DemoKeeper Spell", "none"),
        "the real row is where it was")
    assertEquals(nil, Rows._dirty, "and the compaction ran")
    local live = 0
    for i = 1, Rows.rows_n do
        assertNotNil(Rows.rows[i], "the array has no hole at " .. i)
        live = live + 1
    end
    assertEquals(live, Rows:Count(), "the count is the array")
    Rows:Clear()
    Display:RenderIdle()
end)

test("a combat start scrubs the panel", function()
    enableAll()
    stopQuietly()
    Rows:Clear()
    T:Start()
    local _, filled = taggedRows()
    assertTrue(filled > 0)
    T._eventFrame:GetScript("OnEvent")(T._eventFrame, "PLAYER_REGEN_DISABLED")
    assertEquals(false, T.active)
    assertEquals("combat", T.reason)
    local _, after = taggedRows()
    assertEquals(0, after, "the panel is clean of the demo")
    assertEquals(nil, Rows._dirty, "and the array was compacted")
end)

test("the fill is a full, stable panel: the spread, topped up as rows run out",
function()
    -- K2 (PLAN §11.4): the panel refills per expired row (Target + the
    -- idempotent fill), not only once every row has run out.
    enableAll()
    stopQuietly()
    Rows:Clear()
    local tracked = Registry:Counts()
    assertTrue(tracked >= 3,
        "the donor pool carries the spread (" .. tracked .. ")")
    T:Start()
    local _, n = taggedRows()
    assertTrue(n >= 3, "the panel opens full (" .. n .. " >= 3)")
    assertTrue(n <= 4, "the spread is the K2 four (" .. n .. ")")
    local feeder
    for _, f in ipairs(T.feeders) do
        if f.Name == "SpellTimer" then feeder = f end
    end
    assertNotNil(feeder)
    assertEquals(4, feeder.Target, "the feed targets the full panel")
    -- Run two rows out the way the scrub removes them (the key lookup the
    -- idempotence consults must stop seeing them), keep the pair that is
    -- still running under watch.
    local kept, killed = {}, 0
    for i = Rows.rows_n, 1, -1 do
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) then
            if killed < 2 then
                Rows:removeAt(i)
                killed = killed + 1
            else
                kept[row.name] = row.expireAt
            end
        end
    end
    Rows:Compact()
    assertEquals(2, killed, "two rows ran out")
    local added = feeder.Fill(M:Clock())
    assertEquals(2, added, "the top-up re-arms exactly the run-out donors")
    local _, live = taggedRows()
    assertTrue(live >= 3, "the panel is full again (" .. live .. ")")
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and T.IsSynthetic(row) and kept[row.name] then
            assertEquals(kept[row.name], row.expireAt,
                "the running row " .. row.name .. " was not re-anchored")
        end
    end
    stopQuietly()
    Rows:Clear()
    local _, after = taggedRows()
    assertEquals(0, after, "the exit scrubs the panel")
end)

test("the suite leaves the shipped state as it found it", function()
    stopQuietly()
    assertEquals(false, T.active)
    local _, n = taggedRows()
    assertEquals(0, n)
    Rows:Clear()
    Display:RenderIdle()
    local _, rowsAfter = taggedRows()
    assertEquals(0, rowsAfter)
end)
