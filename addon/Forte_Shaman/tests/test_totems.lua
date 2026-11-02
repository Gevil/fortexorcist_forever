-- addon/Forte_Shaman/tests/test_totems.lua
-- The Shaman totem slots as Spell Timer rows (Core/Totems.lua): the three
-- laws of /tmp/fxref/Forte_Class/Shaman/Shaman.lua:77-93 -- a placed totem
-- gets a row in its ELEMENT group, a new totem in the slot replaces that row
-- IN PLACE, and a destroyed / expired totem clears it -- plus the Forever
-- secret-value law: a read the engine seals changes NO row (the cast
-- prediction Forte_Timer's cast spine drew from the shaman's own cast of the
-- totem spell survives it untouched).
--
-- The rows ride the REAL, always-loaded FX.Timer.Rows table (the row law
-- itself is Forte_Timer's, and this suite must prove the Shaman half lands in
-- it, not in a mock of it); the slot READS are injected through
-- NewTotemTracker's readSlot seam (the FX.Timer.Reconcile.readers convention)
-- except in the last test, which drives the live globals. The 2012 addon's
-- own slot rows are the model, never a fixture.
--
-- The tracker is driven through its public event entry OnTotemUpdate, and
-- once through the module's real OnEvent script; no render function is ever
-- called (the hidden-frame law), and the 0.04 s ticker is never relied on.
local FX = ForteXorcist
local Totems = FX.modules.Shaman
local Sham = FX.Shaman
local Rows = FX.Timer.Rows
local LAWS = FX.Timer.Laws

local SENT = "FXTEST-SECRET-TOTEM"

local function liveRowsInGroup(groupKey)
    local n = 0
    for i = 1, Rows.rows_n do
        local r = Rows.rows[i]
        if r and r.groupKey == groupKey and r.state <= LAWS.REMOVE then n = n + 1 end
    end
    return n
end

--- reads[slot] == nil   -> the engine seals the read (the row must survive)
--- reads[slot].present == false                  -> an empty slot
--- reads[slot] = { name, expireAt, total }       -> a live totem
local function newTracker(reads)
    return Sham.NewTotemTracker({
        rows = Rows,
        readSlot = function(slot) return reads[slot] end,
    })
end

-- ============================================================ placed row --
test("a placed totem gets one row in its element group", function()
    Rows:Clear()
    local t0 = GetTime()
    local reads = {
        [1] = { present = true, name = "Magma Totem", expireAt = t0 + 20, total = 20 },
    }
    local t = newTracker(reads)

    assertEquals("inserted", t:OnTotemUpdate(1))

    local row = Rows:Find("Magma Totem", "Fire")
    assertNotNil(row, "the fire slot's totem has a row")
    assertEquals(Rows:IdFor("Fire"), row.groupKey,
        "the row rides the Fire element group (Shaman.lua:76)")
    assertEquals("Fire", row.targetKey, "the element is the row's group label")
    assertEquals(20, row.total, "the window is the read's duration")
    assertFalse(row.predicted, "the slot read is a fact, not a prediction")

    -- Slot 2 is the Earth element: its own group, never Fire's.
    reads[2] = { present = true, name = "Stoning Totem",
                 expireAt = GetTime() + 36, total = 36 }
    assertEquals("inserted", t:OnTotemUpdate(2))
    local earth = Rows:Find("Stoning Totem", "Earth")
    assertNotNil(earth, "the earth slot's totem has a row")
    assertEquals(Rows:IdFor("Earth"), earth.groupKey, "one group per element")
    assertEquals(1, liveRowsInGroup(Rows:IdFor("Fire")))
    assertEquals(1, liveRowsInGroup(Rows:IdFor("Earth")))
end)

-- ========================================================= replaced in place --
test("a new totem in the slot replaces the slot's row in place", function()
    Rows:Clear()
    local t0 = GetTime()
    local reads = {
        [1] = { present = true, name = "Magma Totem", expireAt = t0 + 20, total = 20 },
    }
    local t = newTracker(reads)
    t:OnTotemUpdate(1)
    assertNotNil(Rows:Find("Magma Totem", "Fire"))

    -- The shaman drops a Fire totem for another Fire totem (Shaman.lua:83-86
    -- `ST.ST:remove(i)` + insert: the slot keeps ONE row, in the same group).
    reads[1] = { present = true, name = "Stoning Totem",
                 expireAt = GetTime() + 36, total = 36 }
    assertEquals("replaced", t:OnTotemUpdate(1))

    assertNil(Rows:Find("Magma Totem", "Fire"),
        "the replaced totem's row is gone, not left to expire")
    local row = Rows:Find("Stoning Totem", "Fire")
    assertNotNil(row, "the new totem took the slot's row")
    assertEquals(Rows:IdFor("Fire"), row.groupKey, "same slot, same element group")
    assertEquals(1, liveRowsInGroup(Rows:IdFor("Fire")),
        "one row per element slot")

    -- The SAME totem read again (a re-cast / a repeat event) is a refresh, not
    -- a second row: InsertFromAura's adopt law keeps the row identity.
    local id = row.id
    reads[1] = { present = true, name = "Stoning Totem",
                 expireAt = GetTime() + 36, total = 36 }
    t:OnTotemUpdate(1)
    assertEquals(1, liveRowsInGroup(Rows:IdFor("Fire")), "still one row")
    assertEquals(id, Rows:Find("Stoning Totem", "Fire").id, "the same row")
end)

-- ==================================================== destroyed / expired --
test("a destroyed totem clears the row; an expiring one fades", function()
    Rows:Clear()
    local reads = {
        [1] = { present = true, name = "Magma Totem",
                expireAt = GetTime() + 20, total = 20 },
    }
    local t = newTracker(reads)
    t:OnTotemUpdate(1)
    local row = Rows:Find("Magma Totem", "Fire")
    assertNotNil(row)

    -- Killed long before its window ended (Shaman.lua:87: not within 0.75 of
    -- its expiry -> mode 3, the red removed band).
    reads[1] = { present = false }
    assertEquals("cleared", t:OnTotemUpdate(1))
    assertEquals(LAWS.REMOVE, row.state, "a destroyed totem reads as removed")
    assertNil(t.slots[1], "the slot is no longer shown")

    -- The row that was expiring by itself within the 0.75 s lead fades out
    -- gently instead (mode 2).
    Rows:Clear()
    reads[1] = { present = true, name = "Stoning Totem",
                 expireAt = GetTime() + 0.2, total = 36 }
    t:OnTotemUpdate(1)
    row = Rows:Find("Stoning Totem", "Fire")
    assertNotNil(row)
    reads[1] = { present = false }
    t:OnTotemUpdate(1)
    assertEquals(LAWS.FADING, row.state, "a natural expiry fades, no fail band")

    -- An empty slot with nothing tracked is a no-op, not an error.
    reads[3] = { present = false }
    assertEquals("idle", t:OnTotemUpdate(3))
end)

-- ============================================================ sealed read --
test("a sealed read mutates no row: the known window is kept", function()
    Rows:Clear()
    local t0 = GetTime()
    local reads = {
        [1] = { present = true, name = "Magma Totem", expireAt = t0 + 20, total = 20 },
    }
    local t = newTracker(reads)
    t:OnTotemUpdate(1)
    local row = Rows:Find("Magma Totem", "Fire")
    assertNotNil(row)
    local expire, state, id = row.expireAt, row.state, row.id

    -- The engine seals the slot: the read answers NOTHING, so the row that is
    -- on the panel (the cast prediction of the totem spell) is left alone.
    reads[1] = nil
    assertEquals("sealed", t:OnTotemUpdate(1))
    local after = Rows:Find("Magma Totem", "Fire")
    assertNotNil(after, "the row survives a sealed read")
    assertEquals(id, after.id, "the same row")
    assertEquals(expire, after.expireAt, "its window is untouched")
    assertEquals(state, after.state, "its life state is untouched")
    assertEquals(1, t.secretReads, "the sealed read is counted, not acted on")
    assertEquals(1, liveRowsInGroup(Rows:IdFor("Fire")))

    -- A slot payload that is not a plain slot number is ignored outright:
    -- a secret number, 0, a non-number, an out-of-range slot.
    assertEquals("ignored", t:OnTotemUpdate(SENT))
    assertEquals("ignored", t:OnTotemUpdate(nil))
    assertEquals("ignored", t:OnTotemUpdate(0))
    assertEquals("ignored", t:OnTotemUpdate(99))
    assertEquals(1, liveRowsInGroup(Rows:IdFor("Fire")), "none of them touched a row")
end)

-- ==================================================== the live event frame --
test("the module's OnEvent forwards PLAYER_TOTEM_UPDATE's slot payload", function()
    Rows:Clear()
    local t0 = GetTime()
    local reads = {
        [2] = { present = true, name = "Stoning Totem", expireAt = t0 + 36, total = 36 },
    }
    local savedClass, savedEnabled, savedFrame = FX._playerClass,
        Totems._eventsEnabled, Totems._eventFrame
    Totems.tracker, Totems._eventsEnabled, Totems._eventFrame =
        newTracker(reads), false, nil

    local ok, err = pcall(function()
        -- A shaman login: the frame exists and the handler is bound in the
        -- (frame, event, ...) form the event law demands.
        FX._playerClass = "SHAMAN"
        Totems:OnEnable()
        assertNotNil(Totems._eventFrame, "a shaman login builds the event frame")
        local handler = Totems._eventFrame:GetScript("OnEvent")
        assertEquals("function", type(handler))
        assertTrue(Totems._eventsEnabled)

        handler(Totems._eventFrame, "PLAYER_TOTEM_UPDATE", 2)
        local row = Rows:Find("Stoning Totem", "Earth")
        assertNotNil(row, "the event's slot index reached the reader")
        assertEquals(Rows:IdFor("Earth"), row.groupKey)
    end)

    local frame = Totems._eventFrame
    Totems:DisableEvents()          -- the binding going nil is the visible state
    FX._playerClass = savedClass
    Totems.tracker = nil
    Totems._eventsEnabled, Totems._eventFrame = savedEnabled, savedFrame
    Rows:Clear()
    assertNotNil(frame, "the test drove a real frame")
    assertTrue(ok, err)
end)

-- ================================================= the live API + secret law --
test("the live reader path: GetTotemInfo facts, sealed by data and by gate", function()
    Rows:Clear()
    local savedInfo, savedSlots = _G.GetTotemInfo, _G.GetNumTotemSlots
    local savedSecretGate = _G.C_Secrets and _G.C_Secrets.ShouldTotemSlotBeSecret
    local savedIsSecret = _G.issecretvalue
    local t0 = GetTime()

    local ok, err = pcall(function()
        _G.GetNumTotemSlots = function() return 4 end
        _G.GetTotemInfo = function(slot)
            if slot ~= 1 then return false, nil, 0, 0, nil, nil, nil end
            return true, "Magma Totem", t0, 20, 1234, 1, 8190
        end
        local t = Sham.NewTotemTracker({ rows = Rows })   -- no injected seam
        assertEquals("inserted", t:OnTotemUpdate(1))
        local row = Rows:Find("Magma Totem", "Fire")
        assertNotNil(row, "the live GetTotemInfo read produced the row")
        assertEquals(t0 + 20, row.expireAt,
            "startTime + duration, the client's own window law")

        -- The C_Secrets gate sealing the slot: nothing is read, nothing moves.
        _G.C_Secrets.ShouldTotemSlotBeSecret = function() return true end
        assertEquals("sealed", t:OnTotemUpdate(1))
        assertNotNil(Rows:Find("Magma Totem", "Fire"), "the row is kept")
        _G.C_Secrets.ShouldTotemSlotBeSecret = nil

        -- The values themselves sealed: every return classifies as a secret,
        -- so the read answers nothing (the sentinel seam of
        -- addon/Forte_Core/tests/test_probe.lua -- the sim mints no real
        -- secret value).
        _G.issecretvalue = function(v) return v == SENT end
        _G.GetTotemInfo = function()
            return SENT, SENT, SENT, SENT, SENT, SENT, SENT
        end
        local t2 = Sham.NewTotemTracker({ rows = Rows })
        assertEquals("sealed", t2:OnTotemUpdate(1))
        assertNotNil(Rows:Find("Magma Totem", "Fire"), "the row is kept")
        _G.issecretvalue = nil

        -- A plain empty slot clears it.
        _G.GetTotemInfo = function() return false, nil, 0, 0, nil, nil, nil end
        assertEquals("cleared", t:OnTotemUpdate(1))
        assertNil(t.slots[1])
    end)

    _G.GetTotemInfo, _G.GetNumTotemSlots = savedInfo, savedSlots
    if _G.C_Secrets then _G.C_Secrets.ShouldTotemSlotBeSecret = savedSecretGate end
    _G.issecretvalue = savedIsSecret
    Rows:Clear()
    assertTrue(ok, err)
end)

test("the module's status line names the four elements and the sealed count", function()
    local line = Totems:StatusLine()
    assertEquals("string", type(line))
    assertTrue(string.find(line, "^Shaman totems:") ~= nil)
    assertNil(string.find(line, "|", 1, true),
        "the bar is the chat colour prefix separator: never in a line")
    Totems.tracker = Sham.NewTotemTracker({
        rows = Rows,
        readSlot = function() return { present = false } end,
    })
    Totems.tracker.secretReads = 3
    local live = Totems.tracker:StatusLine()
    assertTrue(string.find(live, "fire=none") ~= nil)
    assertTrue(string.find(live, "air=none") ~= nil)
    assertTrue(string.find(live, "sealed reads 3") ~= nil)
    Totems.tracker = nil
end)
