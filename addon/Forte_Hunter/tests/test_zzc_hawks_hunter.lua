-- =============================================================================
-- test_zzc_hawks_hunter.lua -- the Summon Hawk tracker (PLAN §11.16): the
-- hawks a Hunter's Summon Hawk leaves behind, as Spell Timer rows.
--
-- NAME LAW: sorts after test_zzb_aspect_hunter.lua and rides the same
-- manual-clock opt-in (SetManualClock is enable-once and process-wide); when
-- this file runs alone it enables the clock itself. `C_Timer.After` fires on
-- AdvanceTime, so the dive delay is real sim time.
--
-- WHAT RIDES REAL: the Hunter tools' registered frame OnEvent script (the
-- module's real `onToolEvent`, fed UNIT_SPELLCAST_SUCCEEDED / PLAYER_DEAD /
-- PLAYER_ENTERING_WORLD), the real dive timer, the real Spell Timer row table,
-- the Timer's own tickers and aura sweep. WHAT IS INJECTED: the client's
-- spell-name table (`C_Spell.GetSpellInfo`) and the spellbook answer
-- (`IsPlayerSpell`) -- the sim profile is a Paladin and knows no Hunter spell
-- -- and the aspect aura reader. Every number asserted is derived from the
-- generated data row or from the module's exported constants.
-- =============================================================================
local FX = ForteXorcist
local Tools = FX.Hunter.Tools
local Locale = FX.Locale
local SPELL = "Summon Hawk"

local function step(dt)
    local left = dt
    while left > 1e-9 do
        local d = math.min(0.1, left)
        local ok, err = pcall(A_Admin.AdvanceTime, d)
        assertTrue(ok, "AdvanceTime raised: " .. tostring(err))
        left = left - d
    end
end

local function ensureClock()
    if pcall(A_Admin.AdvanceTime, 0.01) then return end
    local ok, err = pcall(A_Admin.SetManualClock, 140000)
    assertTrue(ok, "SetManualClock raised: " .. tostring(err))
end

local function near(a, b, msg)
    assertTrue(math.abs(a - b) < 1e-6,
        (msg or "near") .. ": got " .. tostring(a) .. ", expected " .. tostring(b))
end

local DATA_ID = FX.Data.HunterByName[SPELL]
local DATA_ROW = FX.Data.Hunter[DATA_ID]
local LIFE = (DATA_ROW.summonDurationMs or 0) / 1000   -- the data's hawk lifetime
local CAP = DATA_ROW.summonMax
local DIVE = FX.Hunter.Hawks and FX.Hunter.Hawks.DIVE_SECONDS
local RANK_ID = DATA_ID + 1                  -- fixture: another rank's id
local OTHER_ID = FX.Data.HunterByName["Arcane Shot"]
local GERMAN = "Falkenruf"

local function hawks() return FX.Hunter.Hawks end

--- The live (NORMAL-state) hawk rows of the Spell Timer.
local function hawkRows()
    local R, L = FX.Timer.Rows, FX.Timer.Laws
    local out = {}
    for i = 1, R.rows_n do
        local r = R.rows[i]
        if r and r.state == L.NORMAL and r.name:find("^" .. SPELL) then
            out[#out + 1] = r
        end
    end
    return out
end

local function find(slot) return FX.Timer.Rows:Find(SPELL .. " " .. slot, "none") end

--- Run `fn(rig)` with the client stubs in, the tools' real event script wired.
--- opts.talent = false: the player knows nothing; opts.rank = true: the player
--- knows only RANK_ID (not the data's id); opts.german: a deDE client.
local function withRig(opts, fn)
    opts = opts or {}
    ensureClock()
    local R, L = FX.Timer.Rows, FX.Timer.Laws
    local saved = {
        enabled = Tools._eventsEnabled == true,
        reader = FX.Hunter.DefaultAuraReader,
        C_Spell = _G.C_Spell, isp = _G.IsPlayerSpell,
        showSelf = R.options and R.options.showSelf,
    }
    local rig = { known = {}, names = {
        [DATA_ID] = SPELL, [RANK_ID] = SPELL, [OTHER_ID] = "Arcane Shot" } }
    if opts.german then
        rig.names[DATA_ID], rig.names[RANK_ID] = GERMAN, GERMAN
    end
    if opts.rank then rig.known[RANK_ID] = true
    elseif opts.talent ~= false then rig.known[DATA_ID] = true end
    local clientName = opts.german and GERMAN or SPELL
    _G.C_Spell = setmetatable({
        GetSpellInfo = function(x)
            if type(x) == "number" then
                local n = rig.names[x]
                return n and { spellID = x, name = n } or nil
            elseif type(x) == "string" and x == clientName then
                for id in pairs(rig.known) do
                    if rig.names[id] == x then return { spellID = id, name = x } end
                end
            end
            return nil
        end,
    }, { __index = saved.C_Spell })
    _G.IsPlayerSpell = function(id) return rig.known[id] == true end
    FX.Hunter.DefaultAuraReader = function() return false end
    if opts.german then
        Locale.Reset()
        Locale.stubLocale = function() return "deDE" end
        Locale.stubSpellName = function(id) return rig.names[id] end
        Locale.BuildSpellAliases()
    end
    R:Clear()
    Tools:DisableEvents()
    Tools:EnableEvents()
    local f = Tools._eventFrame
    local script = f:GetScript("OnEvent")
    assertNotNil(script, "the enable path installs the real OnEvent script")
    rig.fire = function(event, ...) script(f, event, ...) end
    rig.cast = function(id) rig.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "G:1", id or DATA_ID) end

    local ok, err = pcall(fn, rig)
    step(1.5)                                  -- drain armed timers
    Tools:DisableEvents()
    if opts.german then
        Locale.Reset()
    end
    _G.C_Spell, _G.IsPlayerSpell = saved.C_Spell, saved.isp
    FX.Hunter.DefaultAuraReader = saved.reader
    if R.options then R.options.showSelf = saved.showSelf end
    R:Clear()
    if saved.enabled then Tools:EnableEvents() end
    if not ok then error(err, 0) end
end

-- ------------------------------------------------------------------ data --
test("the generated Summon Hawk row carries the hawk window beside its cooldown", function()
    assertEquals(SPELL, DATA_ROW.name)
    assertEquals(18000, DATA_ROW.summonDurationMs, "the summon spell's lifetime")
    assertEquals(2, DATA_ROW.summonMax, "the hawks up at once")
    -- The cooldown bar's row is exactly as before: the 6 s cooldown shared
    -- with Arcane Shot, no duration (so the Timer registry draws nothing).
    assertEquals(6000, DATA_ROW.cooldownMs)
    assertEquals(1173, DATA_ROW.cooldownCategory)
    assertEquals("Arcane Shot", DATA_ROW.shares)
    assertEquals(true, DATA_ROW.racial)
    assertNil(DATA_ROW.durationMs, "a durationMs would put a cast row on the Timer")
    -- (the Timer registry registers only rows with durationMs > 0, so with
    -- none on this row it registers nothing for Summon Hawk)
end)

-- ------------------------------------------------------- cast -> one row --
test("a cast draws no row before the dive delay, one row after, lifetime = data", function()
    withRig(nil, function(rig)
        local H = hawks()
        assertTrue(H.active, "the player knows the spell")
        local t0 = GetTime()
        rig.cast()
        step(DIVE - 0.1)
        assertEquals(0, #hawkRows(), "the hawk is still diving")
        step(0.2)
        local rows = hawkRows()
        assertEquals(1, #rows)
        local row = find(1)
        assertNotNil(row)
        assertEquals(SPELL .. " 1", row.name)
        assertEquals("none", row.targetKey)
        assertTrue(FX.Timer.Rows.IsSelfRow(row), "a hawk is a self row")
        assertEquals("SelfBuff", row.kind, "the self-buff band")
        near(row.total, LIFE, "total = the data lifetime")
        near(row.expireAt, t0 + DIVE + LIFE, "the window starts when the hawk lands")
    end)
end)

test("the cast of another spell does nothing", function()
    withRig(nil, function(rig)
        rig.cast(OTHER_ID)
        step(DIVE + 0.5)
        assertEquals(0, #hawkRows())
        assertEquals(0, hawks():Live())
    end)
end)

test("a second cast makes a second row with its own label and countdown", function()
    withRig(nil, function(rig)
        local t0 = GetTime()
        rig.cast()
        step(6)                                -- the shared cooldown apart
        rig.cast()
        step(DIVE + 0.1)
        assertEquals(2, #hawkRows())
        local a, b = find(1), find(2)
        assertNotNil(a) assertNotNil(b)
        assertTrue(a.name ~= b.name, "distinguishable labels")
        near(a.expireAt, t0 + DIVE + LIFE)
        near(b.expireAt, t0 + 6 + DIVE + LIFE)
        step(3)
        near(b.expireAt - a.expireAt, 6, "independent windows stay 6 s apart")
        local remA = a.expireAt - GetTime()
        local remB = b.expireAt - GetTime()
        assertTrue(remB > remA, "each counts down on its own")
    end)
end)

test("a third cast with both up restarts the hawk with the least time left", function()
    withRig(nil, function(rig)
        local t0 = GetTime()
        rig.cast()
        step(6)
        rig.cast()
        step(6)
        local castC = GetTime()
        rig.cast()
        step(DIVE + 0.1)
        assertEquals(CAP, #hawkRows(), "exactly the data's number of rows")
        local a, b = find(1), find(2)
        near(a.expireAt, castC + DIVE + LIFE, "the older hawk restarted")
        near(b.expireAt, t0 + 6 + DIVE + LIFE, "the newer one is untouched")
    end)
end)

test("the replaced hawk is the one with least time left, not slot 1", function()
    withRig(nil, function(rig)
        local t0 = GetTime()
        rig.cast()                             -- A -> slot 1
        step(6)
        rig.cast()                             -- B -> slot 2
        step(t0 + LIFE + 2 - GetTime())        -- A has expired, B is still up
        local castC = GetTime()
        rig.cast()                             -- C: slot 1 is FREE
        step(DIVE + 0.1)
        near(find(1).expireAt, castC + DIVE + LIFE, "C took the free slot 1")
        step(1.9)
        local castD = GetTime()
        rig.cast()                             -- D: both up, B has less left
        step(DIVE + 0.1)
        near(find(2).expireAt, castD + DIVE + LIFE, "D replaced B (slot 2)")
        near(find(1).expireAt, castC + DIVE + LIFE, "C (slot 1) untouched")
        assertEquals(CAP, #hawkRows())
    end)
end)

test("a hawk expires at its lifetime and the row leaves through the normal fade", function()
    withRig(nil, function(rig)
        local t0 = GetTime()
        rig.cast()
        step(DIVE + 0.1)
        local row = find(1)
        assertEquals(1, (hawks():Live()))
        step(t0 + DIVE + LIFE + 0.05 - GetTime())
        assertEquals(0, (hawks():Live()), "the model frees the slot at the lifetime")
        FX.Timer.Rows:Sweep(GetTime())
        assertTrue(row.state ~= FX.Timer.Laws.NORMAL, "the row fades like any expired row")
    end)
end)

-- ---------------------------------------------------------------- resets --
test("death clears the hawks, the dives in flight and their rows", function()
    withRig(nil, function(rig)
        rig.cast()
        step(0.5)
        rig.fire("PLAYER_DEAD")
        step(DIVE + 1)
        assertEquals(0, #hawkRows(), "a dive in flight never lands after death")
        assertEquals(0, (hawks():Live()))
        rig.cast()
        step(DIVE + 0.1)
        assertEquals(1, #hawkRows())
        rig.fire("PLAYER_DEAD")
        assertEquals(0, #hawkRows(), "a landed hawk's row is gone at once")
        assertNil(find(1))
        assertEquals(0, (hawks():Live()))
    end)
end)

test("a loading screen clears the hawks, and the tracker stays armed", function()
    withRig(nil, function(rig)
        rig.cast()
        step(DIVE + 0.1)
        rig.cast()
        rig.fire("PLAYER_ENTERING_WORLD", false, true)
        step(DIVE + 0.2)
        assertEquals(0, #hawkRows(), "no hawk survived, the pending dive included")
        assertEquals(0, (hawks():Live()))
        assertTrue(hawks().active, "still a hunter who knows the spell")
        rig.cast()
        step(DIVE + 0.1)
        assertEquals(1, #hawkRows(), "and it tracks again")
    end)
end)

-- --------------------------------------------------- knowledge / inactive --
test("no talent: nothing declared, registered, scheduled or drawn", function()
    ensureClock()
    local saved = { create = _G.CreateFrame, frame = Tools._eventFrame,
        enabled = Tools._eventsEnabled, C_Spell = _G.C_Spell,
        isp = _G.IsPlayerSpell, After = C_Timer.After }
    local unit, plain, script = {}, {}, nil
    local fake = {}
    function fake:RegisterUnitEvent(e, u) unit[e] = u end
    function fake:RegisterEvent(e) plain[e] = true end
    function fake:UnregisterUnitEvent(e, u) if unit[e] == u then unit[e] = nil end end
    function fake:UnregisterEvent(e) plain[e] = nil end
    function fake:SetScript(k, fn) if k == "OnEvent" then script = fn end end
    function fake:GetScript(k) if k == "OnEvent" then return script end end
    _G.CreateFrame = function() return fake end
    Tools._eventFrame, Tools._eventsEnabled = nil, false
    local known = false
    _G.C_Spell = setmetatable({
        GetSpellInfo = function(x)
            if type(x) == "number" and x == DATA_ID then
                return { spellID = x, name = SPELL }
            end
            return nil
        end,
    }, { __index = saved.C_Spell })
    _G.IsPlayerSpell = function() return known end
    local afters = 0
    C_Timer.After = function(...) afters = afters + 1; return saved.After(...) end
    local ok, err = pcall(function()
        Tools:EnableEvents()
        assertFalse(hawks().active)
        assertNil(plain.PLAYER_DEAD, "no PLAYER_DEAD registration without the talent")
        assertNil(FX.Timer.Casts.owners[SPELL], "no owned-row declaration")
        assertNil(FX.Timer.Casts.owners[SPELL .. " 1"])
        script(fake, "UNIT_SPELLCAST_SUCCEEDED", "player", "G:1", DATA_ID)
        step(DIVE + 0.5)
        assertEquals(0, afters, "no dive timer armed")
        assertEquals(0, #hawkRows())
        assertFalse(Tools:StatusLine():find("hawks", 1, true) ~= nil,
            "no status segment")
        -- Learning it later: the next cast re-asks the spellbook and arms.
        known = true
        script(fake, "UNIT_SPELLCAST_SUCCEEDED", "player", "G:2", DATA_ID)
        assertTrue(hawks().active)
        assertTrue(plain.PLAYER_DEAD, "PLAYER_DEAD registered once active")
        assertNotNil(FX.Timer.Casts.owners[SPELL .. " 1"])
        step(DIVE + 0.2)
        assertEquals(1, #hawkRows())
        Tools:DisableEvents()
        assertNil(plain.PLAYER_DEAD, "the teardown unregisters it")
        assertNil(FX.Timer.Casts.owners[SPELL .. " 1"], "and drops the declaration")
        assertFalse(hawks().active)
        assertEquals(0, #hawkRows(), "and the rows")
    end)
    C_Timer.After = saved.After
    _G.CreateFrame = saved.create
    Tools._eventFrame, Tools._eventsEnabled = saved.frame, saved.enabled
    _G.C_Spell, _G.IsPlayerSpell = saved.C_Spell, saved.isp
    FX.Timer.Rows:Clear()
    if not ok then error(err, 0) end
end)

test("a hunter who knows only another rank is active (client name path)", function()
    withRig({ rank = true }, function(rig)
        assertTrue(hawks().active, "RANK_ID is known, the data's id is not")
        rig.cast(RANK_ID)
        step(DIVE + 0.1)
        assertEquals(1, #hawkRows())
    end)
end)

test("a localized client's cast resolves under the data name", function()
    withRig({ german = true }, function(rig)
        assertEquals(SPELL, Locale.CanonicalName(GERMAN), "the alias exists")
        assertTrue(hawks().active)
        rig.cast(RANK_ID)
        step(DIVE + 0.1)
        assertEquals(1, #hawkRows(), "the German-named cast reached the tracker")
        assertNotNil(find(1))
    end)
end)

-- ------------------------------------------------------------ Timer seams --
test("ShowSelf = false hides both hawk rows", function()
    withRig(nil, function(rig)
        rig.cast()
        step(6)
        rig.cast()
        step(DIVE + 0.1)
        local R = FX.Timer.Rows
        assertEquals(2, #hawkRows())
        local opts = R.options
        assertNotNil(opts, "the Timer's live options")
        opts.showSelf = true
        local _, n = R:Sorted(nil, GetTime())
        assertTrue(n >= 2)
        local shown = n
        opts.showSelf = false
        local _, n2 = R:Sorted(nil, GetTime())
        assertEquals(shown - 2, n2, "both hawk rows left the draw list")
        assertEquals(2, #hawkRows(), "but stay in the model")
        opts.showSelf = true
    end)
end)

test("the owned-row declaration keeps the cast spine and the aura sweep off the hawks", function()
    withRig(nil, function(rig)
        local C, Rec, L = FX.Timer.Casts, FX.Timer.Reconcile, FX.Timer.Laws
        assertTrue(C:RowIsOwned(SPELL), "the cast spine draws no prediction")
        assertTrue(C:RowIsOwned(SPELL .. " 1"))
        assertTrue(C:RowIsOwned(SPELL .. " " .. CAP))
        rig.cast()
        step(DIVE + 0.1)
        local row = find(1)
        local savedReaders, savedCombat = Rec.readers, Rec.inCombat
        Rec.inCombat = function() return false end
        Rec.readers = { byName = function() return false end,
            bulk = function() return false end }
        step(L.BUFF_DELAY + 1)                  -- the real Logic passes sweep
        Rec:SweepUnit("player", "HELPFUL", GetTime())
        Rec.readers, Rec.inCombat = savedReaders, savedCombat
        assertEquals(L.NORMAL, row.state, "the hawk is not an aura on the player")
        Tools:DisableEvents()
        assertFalse(C:RowIsOwned(SPELL), "released with the tracker")
        Tools:EnableEvents()
    end)
end)

test("an absent Spell Timer: no raise, no rows, the model still counts", function()
    withRig(nil, function(rig)
        -- (the Timer's own tickers keep their captured upvalues; the hawk
        -- module looks the row table up through FX.Timer at call time)
        local rowsTable = FX.Timer.Rows
        FX.Timer.Rows = nil
        local ok, err = pcall(function()
            rig.cast()
            step(DIVE + 0.1)
            assertEquals(1, (hawks():Live()))
        end)
        FX.Timer.Rows = rowsTable
        assertTrue(ok, tostring(err))
        assertEquals(0, #hawkRows(), "no Timer, no rows")
    end)
end)

-- ---------------------------------------------------------------- status --
test("/fx status carries 'hawks n/max (next gone in x s)' only while active", function()
    withRig(nil, function(rig)
        assertTrue(Tools:StatusLine():find("hawks 0/" .. CAP, 1, true) ~= nil,
            Tools:StatusLine())
        rig.cast()
        step(DIVE + 0.1)
        local line = Tools:StatusLine()
        local left = line:match("hawks 1/" .. CAP .. " %(next gone in (%d+%.%d) s%)")
        assertNotNil(left, line)
        assertTrue(math.abs(tonumber(left) - (LIFE - 0.1)) < 0.11, line)
    end)
    withRig({ talent = false }, function(rig)
        assertFalse(Tools:StatusLine():find("hawks", 1, true) ~= nil)
    end)
end)
