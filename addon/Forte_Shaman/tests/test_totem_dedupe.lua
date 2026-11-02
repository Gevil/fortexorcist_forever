-- addon/Forte_Shaman/tests/test_totem_dedupe.lua
-- ONE row per totem (F-B, 2026-11-02). A Shaman's `Magma Totem` arrives as TWO
-- signals of ONE window: the player's own cast (Forte_Timer's cast spine,
-- `Core/Casts.lua`) and the client's slot state (`PLAYER_TOTEM_UPDATE` -> this
-- module's element-slot row, the port of
-- /tmp/fxref/Forte_Class/Shaman/Shaman.lua:77-93). Before F-B the slot law
-- (`Shaman.lua:83-86`) could only see rows keyed by the ELEMENT, so the cast's
-- row -- keyed by its TARGET -- sat beside the slot row: a fire totem drew two
-- rows, the second the panel never told anyone about.
--
-- The fix is a handoff in both directions, and the tests drive it the way the
-- game does: the cast through Forte_Timer's REAL event frame (the
-- `M._eventFrame:GetScript("OnEvent")(frame, event, ...)` binding law, the
-- payload shape of Forte_Timer/tests/test_pet_rows.lua), the slot through this
-- module's REAL event frame with the slot READS stubbed at the tracker's
-- readSlot seam (the injection convention of test_totems.lua), and the settle
-- through the clock + `Module:Logic()` of test_pet_rows.lua. The tracker reads
-- are stubbed, the EVENT is not.
--
-- The fixtures are the generated Shaman data addressed by NAME (AGENTS.md rule
-- 8 -- this file types no spell id: the ids come out of `FX.Data.Shaman`).
local FX = ForteXorcist
local Totems = FX.modules.Shaman
local Sham = FX.Shaman
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Registry = FX.Timer.Registry
local Casts = FX.Timer.Casts

local MAGMA = "Magma Totem"          -- 20 s, the fire-totem of Shaman.lua's era
local STONESKIN = "Stoneskin Totem"  -- 15 s, the earth slot

local magmaId, stoneskinId
local function idsFromData()
    local data = FX.Data and FX.Data.Shaman
    if type(data) ~= "table" then return end
    for id, row in pairs(data) do
        if type(row) == "table" then
            if row.name == MAGMA then magmaId = id end
            if row.name == STONESKIN then stoneskinId = id end
        end
    end
end

local clock
local function installClock(base)
    clock = { base }
    Casts.now = function() return clock[1] end
end

--- The cast through Forte_Timer's real event frame (the frame is argument 1,
--- the binding law of PLAN §10.2). SENT carries (unitToken, target, castGUID,
--- spellID), SUCCEEDED (unitToken, castGUID, spellID, baseDuration): the orders
--- of the catalog's UNIT_SPELLCAST rows, as test_pet_rows.lua dispatches them.
local function dispatch(event, a1, a2, a3, a4)
    local f = M._eventFrame
    assertNotNil(f, "the cast spine's frame is the module's own")
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    onEvent(f, event, a1, a2, a3, a4)
end

local function cast(spellId)
    dispatch("UNIT_SPELLCAST_SENT", "player", nil, "G:totem", spellId)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:totem", spellId, 2)
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
end

--- The slot through THIS module's real event frame; `reads` is the stubbed
--- readSlot answer for the slot (nil = the engine seals the read).
local function fireTotemEvent(slot)
    local f = Totems._eventFrame
    assertNotNil(f, "the totem module's frame is the real one")
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    onEvent(f, "PLAYER_TOTEM_UPDATE", slot)
end

local function liveRows()
    local shown, n = {}, 0
    for i = 1, Rows.rows_n do
        local r = Rows.rows[i]
        if r and r.state <= Laws.REMOVE then
            n = n + 1
            shown[n] = r
        end
    end
    return shown, n
end

local function rowsOfName(name)
    local n = 0
    local all = liveRows()
    for i = 1, #all do
        if all[i].name == name then n = n + 1 end
    end
    return n
end

-- reads[slot] = { present = true, name, expireAt, total } | { present = false }
--                                        | nil (the read is sealed)
local reads
local function installTracker()
    Totems.tracker = Sham.NewTotemTracker({
        rows = Rows,
        readSlot = function(slot) return reads[slot] end,
    })
    return Totems.tracker
end

local savedClass = FX._playerClass
local savedReads, savedResolve, savedNow = nil, nil, nil
local built = false

test("the shaman kit is live: the data, the class gate, both event frames",
function()
    assertNotNil(FX.Data and FX.Data.Shaman, "Forte_Shaman's data loaded")
    idsFromData()
    assertNotNil(magmaId, "the fire totem is a row of the generated data")
    assertNotNil(stoneskinId, "and the earth one")
    assertTrue(#Totems:SlotSpellNames() >= 20,
        "the class data's totem-summon spells are the declared set")

    savedClass = FX._playerClass
    FX._playerClass = "SHAMAN"
    Registry:AttachStorage({})
    local n = Registry:Build("SHAMAN")
    assertTrue(n and n > 0)
    built = true
    local data = FX.Data.Shaman
    Casts.resolveName = function(id)
        local row = data[id]
        return (type(row) == "table") and row.name or nil
    end
    savedResolve = true
    if not M.options then M:OnEnable() end
    assertNotNil(M._eventFrame)
    Totems:OnEnable()
    assertNotNil(Totems._eventFrame)
    assertTrue(Totems._eventsEnabled, "the totem events are registered")
    -- The declaration the dedupe runs on is in Forte_Timer's spine.
    local casts = FX.Timer.Casts
    assertEquals("Shaman", casts.owners[MAGMA] and casts.owners[MAGMA].owner,
        "the spine knows who draws this totem's row")
    assertEquals("Shaman", casts.owners[STONESKIN]
        and casts.owners[STONESKIN].owner)
    assertNil(casts.owners["Earth Shock"],
        "a shock is no element slot: the spine draws its rows as always")
end)

-- The cast lands FIRST, the slot report after: the prediction retires into the
-- slot's row -- `Shaman.lua:84`'s `ST.ST:remove(i)` law, the slot keeps one row.
test("a totem cast then slot-reported leaves ONE row, the element slot's",
function()
    Rows:Clear()
    reads = {}
    installTracker()
    installClock(60000)
    local owned0 = Casts.status.owned
    local retired0 = Casts.status.retired

    cast(magmaId)
    local prediction = Rows:Find(MAGMA, "none")
    assertNotNil(prediction, "the cast drew its predicted row")
    assertEquals(1, rowsOfName(MAGMA), "one row out of the cast")

    reads[1] = { present = true, name = MAGMA,
                 expireAt = GetTime() + 20, total = 20 }
    fireTotemEvent(1)

    local shown, n = liveRows()
    assertEquals(1, n, "ONE row is live: the slot took the cast's over")
    assertEquals(1, rowsOfName(MAGMA))
    assertEquals("Fire", shown[1].targetKey,
        "the surviving row is the element slot's (Shaman.lua:76)")
    assertNil(Rows:Find(MAGMA, "none"), "the prediction is gone")
    assertTrue(Casts.status.retired > retired0,
        "the spine counted the handoff")
    assertEquals(owned0, Casts.status.owned,
        "the cast that came first was no gate: nothing to skip")
    Rows:Clear()
end)

-- The slot row is on the panel when the cast settles: the spine draws nothing.
test("a totem whose slot row is live draws no cast row", function()
    Rows:Clear()
    installClock(70000)
    local t0 = GetTime()
    reads = { [1] = { present = true, name = MAGMA,
                      expireAt = t0 + 20, total = 20 } }
    installTracker()
    fireTotemEvent(1)
    assertNotNil(Rows:Find(MAGMA, "Fire"), "the slot row is on the panel")
    assertEquals(1, Rows:Count())

    local owned0 = Casts.status.owned
    cast(magmaId)
    assertEquals(1, Rows:Count(), "the cast added NO second row")
    assertEquals(1, rowsOfName(MAGMA))
    assertNil(Rows:Find(MAGMA, "none"),
        "and no prediction of it to retire later")
    assertTrue(Casts.status.owned > owned0,
        "the spine counted the cast it left to the slot")
    Rows:Clear()
end)

-- The sealed half (T3): a `GetTotemInfo` the engine seals answers nothing, so
-- the slot draws no row and the cast prediction is the shaman's only in-combat
-- signal. It stands, and it is alone.
test("a sealed slot read leaves the cast's row as the one row", function()
    Rows:Clear()
    reads = {}                                  -- every read sealed
    installTracker()
    installClock(80000)
    local retired0 = Casts.status.retired
    fireTotemEvent(1)
    assertEquals(0, Rows:Count(), "a sealed read draws no row")

    cast(magmaId)
    assertEquals(1, Rows:Count(), "ONE row: the prediction")
    assertNotNil(Rows:Find(MAGMA, "none"), "the cast's row stands")
    assertEquals(1, rowsOfName(MAGMA))
    assertEquals(retired0, Casts.status.retired, "nothing was handed off")

    -- And the sealed read that arrives WHILE the prediction lives keeps it:
    -- the tracker knows nothing, so it removes nothing (T3's row-keeping law).
    fireTotemEvent(1)
    assertEquals(1, Rows:Count(), "the sealed read left the row alone")
    assertNotNil(Rows:Find(MAGMA, "none"))
    Rows:Clear()
end)

-- The four-slot shape: two totems out of one GCD, each in its element group,
-- each one row, the casts that fed them silent.
test("two totems out of one cast chain are two rows, one per slot", function()
    Rows:Clear()
    reads = {}
    installTracker()
    installClock(90000)
    cast(magmaId)
    cast(stoneskinId)
    assertEquals(2, Rows:Count(), "two predictions out of two casts")
    local t0 = GetTime()
    reads[1] = { present = true, name = MAGMA,
                 expireAt = t0 + 20, total = 20 }
    reads[2] = { present = true, name = STONESKIN,
                 expireAt = t0 + 15, total = 15 }
    fireTotemEvent(1)
    fireTotemEvent(2)
    local shown, n = liveRows()
    assertEquals(2, n, "and two rows in all: one per totem")
    assertEquals(1, rowsOfName(MAGMA))
    assertEquals(1, rowsOfName(STONESKIN))
    local fire, earth = Rows:Find(MAGMA, "Fire"), Rows:Find(STONESKIN, "Earth")
    assertNotNil(fire, "the fire slot's row")
    assertNotNil(earth, "the earth slot's row")
    assertTrue(fire.groupKey ~= earth.groupKey,
        "the two element groups stay the two groups they were")
    Rows:Clear()
end)

-- The declaration is the class's own data, not a hand list: the census is the
-- law `SlotSpellNames` states about the generated file.
test("the declared set is every totem-summon row of the class data", function()
    local declared = {}
    for name in pairs(FX.Timer.Casts.owners) do declared[name] = true end
    local n = 0
    for _, row in pairs(FX.Data.Shaman) do
        if type(row) == "table" and type(row.name) == "string"
            and string.find(row.name, "Totem%d*$") then
            n = n + 1
            assertTrue(declared[row.name] == true,
                "the data's " .. row.name .. " is declared")
        end
    end
    assertTrue(n >= 20, "the generated Shaman list carries its totems")
    for name in pairs(FX.Timer.Casts.owners) do
        assertTrue(string.find(name, "Totem%d*$") ~= nil,
            "nothing but a totem-summon spell is declared: " .. tostring(name))
    end
end)

-- ------------------------------------------------------------ teardown ----
test("the suite leaves the Timer state as it found it", function()
    Rows:Clear()
    Totems:DisableEvents()
    Totems.tracker = nil
    FX._playerClass = savedClass
    Casts.now = nil
    Casts.resolveName = nil
    Casts:Init(Rows, M.options)
    if built then
        Registry:AttachStorage(FX.db and FX.db.timer
            and FX.db.timer.learned or {})
        Registry:Build(FX._playerClass)
    end
    assertEquals(0, Rows:Count())
end)
