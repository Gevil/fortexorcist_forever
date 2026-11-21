-- addon/Forte_Timer/tests/test_owned_rows_sweep.lua
-- A row a CLASS tracker owns (`Casts:DeclareOwnedRows`, the Shaman totem slots,
-- the Hunter hawks) is not an aura on the player, so the aura sweep must not
-- judge it "gone". The hazard (PLAN §11.16): a `(name, "none")` self row is
-- swept by `Reconcile:SweepUnit("player")`; with no player aura of that name
-- the read is "absent", and `Rows:OnAuraAbsent` fades the row REMOVE (and fires
-- TIMER_BROKEN) once BUFF_DELAY has passed and more than MAXLAG is left.
--
-- Driven through the real paths: the module's own Logic pass (Casts.now clock)
-- and its event frame's PLAYER_REGEN_ENABLED script. Readers/combat predicate
-- are the suite's injectable seams (Reconcile.readers / Reconcile.inCombat).

local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Casts = FX.Timer.Casts
local Reconcile = FX.Timer.Reconcile

local OWNER = "SweepTestOwner"
local OWNED = "Sweep Owned Self"        -- no aura of this name exists anywhere
local PLAIN = "Rapid Fire"              -- a normal self row: the aura IS the truth
local BASE = 5000

local function withRig(fn)
    local saved = {
        readers = Reconcile.readers, inCombat = Reconcile.inCombat,
        now = Casts.now, getTime = _G.GetTime, options = Rows.options,
    }
    local clock = { BASE }
    Casts.now = function() return clock[1] end
    _G.GetTime = function() return clock[1] end
    Rows.options = M.options or Rows.options
    Rows:Clear()
    Reconcile.inCombat = function() return false end
    -- The API answered and there is no such aura: the removal fact.
    Reconcile.readers = {
        byName = function() return false end,
        bulk = function() return false end,
    }
    Casts:DeclareOwnedRows({ OWNED }, OWNER, function() return true end)
    local ok, err = pcall(fn, clock)
    Casts:UndeclareOwnedRows(OWNER)
    Rows:Clear()
    Reconcile.readers, Reconcile.inCombat = saved.readers, saved.inCombat
    Casts.now, _G.GetTime, Rows.options = saved.now, saved.getTime, saved.options
    if not ok then error(err, 0) end
end

local function seed()
    local owned = Rows:InsertFromCast(OWNED, "none", 18, BASE, BASE, 1, "SelfBuff")
    local plain = Rows:InsertFromCast(PLAIN, "none", 18, BASE, BASE, 1, "SelfBuff")
    assertNotNil(owned) assertNotNil(plain)
    return owned, plain
end

test("an out-of-combat Logic pass past BUFF_DELAY leaves an owned self row", function()
    withRig(function(clock)
        local owned, plain = seed()
        clock[1] = BASE + Laws.BUFF_DELAY + 1          -- 13 s of the window left
        M:Logic()
        assertEquals(Laws.NORMAL, owned.state,
            "the owned row is not an aura: the sweep leaves it")
        assertEquals(Laws.REMOVE, plain.state,
            "a normal self row with no aura is still faded, as before")
    end)
end)

test("the PLAYER_REGEN_ENABLED sweep leaves an owned self row", function()
    withRig(function(clock)
        local owned, plain = seed()
        clock[1] = BASE + Laws.BUFF_DELAY + 1
        local f = M._eventFrame
        local h = f and f:GetScript("OnEvent")
        assertNotNil(h, "the Timer's event script")
        h(f, "PLAYER_REGEN_ENABLED")
        assertEquals(Laws.NORMAL, owned.state)
        assertEquals(Laws.REMOVE, plain.state)
    end)
end)

test("the unit sweep skips an owned row and counts only the swept one", function()
    withRig(function(clock)
        local owned, plain = seed()
        clock[1] = BASE + Laws.BUFF_DELAY + 1
        assertEquals(1, Reconcile:SweepUnit("player", "HELPFUL", clock[1]),
            "one row judged: the plain one")
        assertEquals(Laws.NORMAL, owned.state)
        assertEquals(Laws.REMOVE, plain.state)
    end)
end)

test("an owned row is judged again once its owner lets go", function()
    withRig(function(clock)
        local owned = seed()
        Casts:UndeclareOwnedRows(OWNER)
        clock[1] = BASE + Laws.BUFF_DELAY + 1
        Reconcile:SweepUnit("player", "HELPFUL", clock[1])
        assertEquals(Laws.REMOVE, owned.state)
    end)
end)

test("a missing or partial Casts module cannot raise in the sweep", function()
    withRig(function(clock)
        local owned, plain = seed()
        clock[1] = BASE + Laws.BUFF_DELAY + 1
        local realCasts = FX.Timer.Casts
        FX.Timer.Casts = nil
        local ok, err = pcall(Reconcile.SweepUnit, Reconcile, "player",
            "HELPFUL", clock[1])
        FX.Timer.Casts = realCasts
        assertTrue(ok, tostring(err))
        assertEquals(Laws.REMOVE, owned.state, "no Casts, no ownership: swept")
        assertEquals(Laws.REMOVE, plain.state)

        local owned2 = Rows:InsertFromCast(OWNED .. " 2", "none", 18, BASE, BASE,
            1, "SelfBuff")
        FX.Timer.Casts = {}
        ok, err = pcall(Reconcile.SweepUnit, Reconcile, "player", "HELPFUL",
            clock[1])
        FX.Timer.Casts = realCasts
        assertTrue(ok, tostring(err))
        assertEquals(Laws.REMOVE, owned2.state,
            "a Casts without RowIsOwned owns nothing")
    end)
end)

test("a totem-style owned row (element key) is untouched by the player sweep", function()
    withRig(function(clock)
        Casts:DeclareOwnedRows({ "Sweep Totem" }, OWNER, function() return true end)
        local totem = Rows:InsertFromCast("Sweep Totem", "Fire", 18, BASE, BASE,
            1, "Cooldown")
        clock[1] = BASE + Laws.BUFF_DELAY + 1
        Reconcile:SweepUnit("player", "HELPFUL", clock[1])
        assertEquals(Laws.NORMAL, totem.state,
            "an element-keyed row never belonged to the player sweep")
    end)
end)
