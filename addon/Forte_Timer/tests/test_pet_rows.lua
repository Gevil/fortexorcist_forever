-- addon/Forte_Timer/tests/test_pet_rows.lua
-- PetRows v2 (PLAN §11.1 wave 2b): Spell Timer rows for the PLAYER'S PET'S
-- OWN casts. The original harvested them from the combat log -- the `FW.pet`
-- branch of its one dispatcher (`/tmp/fxref/Forte_Casting/Forte_Casting.lua:
-- 835-855`, the SPELL_CAST_START/SUCCESS/FAILED sweep feeding the
-- `CA:RegisterOnPetCastSuccess/Failed/Start` seam at :653-664), consumed by
-- the Warlock add-on for the Succubus kit (`/tmp/fxref/Forte_Class/Warlock/
-- Warlock.lua:197-219`), the Seduce message naming `UnitName("pettarget")`
-- (:214, the `UseTokens = "pet pettarget ..."` law at Forte_Casting.lua:880).
-- The log is closed on Forever, so the rows ride the modern half of the
-- same family: UNIT_SPELLCAST_SENT / UNIT_SPELLCAST_SUCCEEDED registered for
-- the `pet` unit (Module.lua's OnEnable set), routed by the payload's unit
-- token.
--
-- Every test drives the REAL event frame (the dispatch idiom of
-- test_module.lua: the frame is argument 1), the injected clock, and the
-- generated WARLOCK data (the pet kit -- Seduction 6358 -- is D3's 70707
-- data; the fixtures name spell ids only through the `Casts.resolveName`
-- seam, the row keys are names -- AGENTS.md rule 8).
local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Registry = FX.Timer.Registry
local Casts = FX.Timer.Casts
local D = FX.Timer.Display

-- The data set the fixtures are: the Warlock pet kit lives there, and the
-- suite runs under the sim's default (Paladin) profile, so the add-on is
-- asked for through the same loader the login path uses (the
-- test_00_class_data.lua idiom).
FX.LoadClassAddOn("WARLOCK")

local function near(actual, expected)
    assertTrue(math.abs(actual - expected) < 1e-6)
end

local clock
local function installClock(base)
    clock = { base }
    Casts.now = function() return clock[1] end
    return clock
end

local function useWarlockData()
    Registry:AttachStorage({})
    local n = Registry:Build("WARLOCK")
    assertTrue(n and n > 0)
    -- The id -> name seam stands where C_Spell.GetSpellInfo reads on a live
    -- client; the ids are the generated data's, never hand-invented.
    Casts.resolveName = function(id)
        return id == 6358 and "Seduction"          -- the pet CC, 15 s window
            or id == 1223963 and "Corruption"       -- the player DoT, 12 s
            or id == 999999 and "Bite"              -- not in any data row
            or nil
    end
end

local function dispatch(event, a1, a2, a3, a4)
    local f = M._eventFrame
    assertNotNil(f)
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    -- The frame is argument 1 (the binding law of PLAN §10.2).
    onEvent(f, event, a1, a2, a3, a4)
end

--- The unit-identity trio, installed for the duration of a test (the
--- test_expiry_identity.lua idiom): the cast path resolves its target
--- through the client's own UnitExists/UnitName/UnitIsDead, and this suite
--- owns the shape of those answers.
local function installUnits(names)
    local saved = {
        UnitExists = _G.UnitExists, UnitName = _G.UnitName,
        UnitIsDead = _G.UnitIsDead,
    }
    _G.UnitExists = function(token) return names[token] ~= nil end
    _G.UnitName = function(token) return names[token] end
    _G.UnitIsDead = function() return false end
    return saved
end
local function restoreUnits(saved)
    _G.UnitExists, _G.UnitName, _G.UnitIsDead =
        saved.UnitExists, saved.UnitName, saved.UnitIsDead
end

-- ------------------------------------------------------------------ setup --

test("the pet feed is live: the module is enabled and the Warlock kit tracked",
function()
    assertNotNil(FX.Data and FX.Data.Warlock, "Forte_Warlock's data loaded")
    if not M.options then M:OnEnable() end
    assertNotNil(M._eventFrame)
    useWarlockData()
    -- The tracked set is the CLASS's, and it already carries the pet kit:
    -- Seduction 6358 is a data row WITH a window, so it is a row the panel
    -- can draw; Mesmerize 24594 (no window in the data) is not.
    assertTrue(Registry.IsTracked("Seduction"))
    near(Registry.BestDuration("Seduction"), 15)
    assertFalse(Registry.IsTracked("Mesmerize"))
end)

-- ------------------------------------------------- the pet cast to a row --

test("a pet Seduction SUCCEEDED rides the real events into a 15 s row",
function()
    useWarlockData()
    Rows:Clear()
    installClock(50000)
    D:RenderIdle()
    local saved = installUnits({ pettarget = "Vile Poacher" })
    -- SENT (unitTarget, target, castGUID, spellID) / SUCCEEDED (unitTarget,
    -- castGUID, spellID, castBarID): the unit token is the pet's, and the
    -- pet's token is what routes the feeds.
    dispatch("UNIT_SPELLCAST_SENT", "pet", "Vile Poacher",
        "GUID:1:6:1:1", 6358)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet",
        "GUID:1:6:1:1", 6358, 7)
    assertEquals(0, Rows:Count(), "the settle defers, pet rows included")
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    assertEquals(1, Rows:Count())
    local row = Rows:Find("Seduction", "Vile Poacher")
    assertNotNil(row)
    near(row.total, 15, "the DATA duration (durationMs 15000), not a guess")
    assertEquals(true, row.predicted)
    assertEquals("Crowds", row.kind, "Seduction is the CC band")
    restoreUnits(saved)
    Rows:Clear()
end)

test("the pet row keys on pettarget, then the player's target, then none",
function()
    useWarlockData()
    -- (a) the payload target string is secret/absent: the pet's OWN target
    -- answers -- the original's `UnitName("pettarget")` (Warlock.lua:214).
    Rows:Clear()
    installClock(51000)
    local saved = installUnits({ pet = "Voidwalker", pettarget = "Dummy-Pet" })
    dispatch("UNIT_SPELLCAST_SENT", "pet", nil, "G:a", 6358)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:a", 6358, 3)
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    assertNotNil(Rows:Find("Seduction", "Dummy-Pet"),
        "the pet's target, readable, is the row's key")
    assertEquals(1, Rows:Count())
    restoreUnits(saved)
    Rows:Clear()
    -- (b) no readable pettarget: the player's target (the pet attacks what
    -- its master points at, the `pet pettarget` token pair).
    installClock(51200)
    saved = installUnits({ pet = "Voidwalker", target = "Dummy-Master-Target" })
    dispatch("UNIT_SPELLCAST_SENT", "pet", nil, "G:b", 6358)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:b", 6358, 4)
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    assertNotNil(Rows:Find("Seduction", "Dummy-Master-Target"),
        "the fall-back is the player's target")
    restoreUnits(saved)
    Rows:Clear()
end)

test("a pet SUCCEEDED with no SENT is one window row, not a crash",
function()
    -- The pet dismissed mid-cast, the SENT lost, the SUCCEEDED of a spell
    -- whose SENT was evicted: the lone-success law, pet half. No pet, no
    -- target readable at all -> the "none" window. No raise on any path.
    useWarlockData()
    Rows:Clear()
    installClock(52000)
    local saved = installUnits({})
    local ok = pcall(dispatch, "UNIT_SPELLCAST_SUCCEEDED", "pet",
        "G:c", 6358, 5)
    assertTrue(ok, "no pet, no target: the path must not raise")
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    assertEquals(1, Rows:Count())
    assertNotNil(Rows:Find("Seduction", "none"))
    restoreUnits(saved)
    Rows:Clear()
end)

-- ------------------------------------------------------------------ fading --

test("the pet Seduction row fires FX_TIMER_FADING ONCE, at 3 s of window left",
function()
    useWarlockData()
    -- The threshold is Forte_Messages' published fact (the fade text ">>
    -- Seduction on %s Fading in 3 seconds! <<", the ST_GetFadeTime law):
    -- enabling the Messages module is what republishes FX.Timer.
    -- FadeWarnings. The bell consumer stubs what it plays with.
    local MM = FX.Messages and FX.Messages.Module
    if MM and not MM.cfg then MM:OnEnable() end
    local W = FX.Timer.FadeWarnings
    assertNotNil(W, "the fade-threshold registry is live")
    assertEquals(3, W.Seduction, "the Seduction fade text carries 3")
    if FX.Messages and FX.Messages.Sounds then
        FX.Messages.Sounds.playFn = function() end
    end
    Rows:Clear()
    installClock(53000)
    local saved = installUnits({ pettarget = "Vile Poacher" })
    local events = {}
    local h = FX.On(FX.EVENTS.TIMER_FADING, function(s, t, k, left)
        events[#events + 1] = { s, t, k, left }
    end)
    dispatch("UNIT_SPELLCAST_SENT", "pet", "Vile Poacher", "G:f", 6358)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:f", 6358, 6)
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    local row = Rows:Find("Seduction", "Vile Poacher")
    assertNotNil(row)
    assertEquals(3, row.fadeWarn, "the insert-time column-12 stamp")
    local expire = row.expireAt
    clock[1] = expire - 3.1                       -- 3.1 s left: silence
    M:Logic()
    assertEquals(0, #events)
    clock[1] = expire - 2.9                       -- the crossing
    M:Logic()
    assertEquals(1, #events)
    assertEquals("Seduction", events[1][1])
    assertEquals("Vile Poacher", events[1][2])
    assertEquals("Crowds", events[1][3])
    clock[1] = expire - 1.0                       -- pumping on: NO second fire
    M:Logic()
    assertEquals(1, #events, "the stamp zeroes at the fire (the st[i][12]=0 law)")
    FX.Off(h)
    if FX.Messages and FX.Messages.Sounds then
        FX.Messages.Sounds.playFn = nil
    end
    restoreUnits(saved)
    Rows:Clear()
end)

-- ------------------------------------------------------------ the gates ----

test("an untracked pet spell creates NOTHING and counts untracked",
function()
    useWarlockData()
    Rows:Clear()
    installClock(54000)
    local saved = installUnits({ pettarget = "Vile Poacher" })
    local untracked0 = Casts.status.untracked
    -- "Bite" (999999): a pet ability with no row in the data. The tracked-
    -- set gate is the class registry's, the same one the player feed runs.
    dispatch("UNIT_SPELLCAST_SENT", "pet", "Vile Poacher", "G:u", 999999)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "pet", "G:u", 999999, 8)
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    assertEquals(0, Rows:Count())
    assertTrue(Casts.status.untracked >= untracked0 + 1,
        "the instrument counted the gate's answer")
    assertEquals(0, #Casts.queue, "no record rides on to the flush")
    restoreUnits(saved)
end)

test("a SENT evicts the pet's own stale record, the player's records ride",
function()
    useWarlockData()
    Rows:Clear()
    installClock(55000)
    local saved = installUnits({ pettarget = "Vile Poacher" })
    -- The player's cast is in flight (a record, not yet settled)...
    dispatch("UNIT_SPELLCAST_SENT", "player", "Dummy-Pet", "G:p", 1223963)
    -- ...and the pet fires. The fresh pet SENT runs the "garbage sent"
    -- sweep over the PET's records only (the feeds never eat each other's
    -- queue entries).
    dispatch("UNIT_SPELLCAST_SENT", "pet", "Dummy-Pet", "G:q", 6358)
    assertEquals(2, #Casts.queue)
    local pet, self
    for i = 1, #Casts.queue do
        if Casts.queue[i].pet then pet = Casts.queue[i] else self = Casts.queue[i] end
    end
    assertNotNil(pet); assertNotNil(self)
    assertEquals("Seduction", pet.name)
    assertEquals("Corruption", self.name)
    -- A second pet SENT (a second cast: the clock moved) evicts the FIRST
    -- pet record, never the player's.
    clock[1] = clock[1] + 1
    dispatch("UNIT_SPELLCAST_SENT", "pet", "Dummy-Pet", "G:r", 6358)
    assertEquals(2, #Casts.queue)
    local petN, selfN, playerRides = 0, 0, false
    for i = 1, #Casts.queue do
        local rec = Casts.queue[i]
        if rec.pet then
            petN = petN + 1
        else
            selfN = selfN + 1
            if rec.name == "Corruption" then playerRides = true end
        end
    end
    assertEquals(1, petN, "the stale pet record is evicted, one rides")
    assertEquals(1, selfN)
    assertTrue(playerRides, "the player's in-flight record rides untouched")
    restoreUnits(saved)
    Rows:Clear()
end)

test("the player cast path is unchanged: its own events make its own row",
function()
    -- The routing gate is the payload's unit token: "player" rides the v1
    -- path with the payload target string as the row key (the token-free
    -- dispatch shape rides it too).
    useWarlockData()
    Rows:Clear()
    installClock(56000)
    local saved = installUnits({ target = "Dummy-Pet" })
    dispatch("UNIT_SPELLCAST_SENT", "player", "Dummy-Pet", "G:s", 1223963)
    dispatch("UNIT_SPELLCAST_SUCCEEDED", "player", "G:s", 1223963, 9)
    clock[1] = clock[1] + Laws.SETTLE + 0.01
    M:Logic()
    assertEquals(1, Rows:Count())
    local row = Rows:Find("Corruption", "Dummy-Pet")
    assertNotNil(row)
    near(row.total, 12)
    restoreUnits(saved)
    Rows:Clear()
end)

test("restore the live seams", function()
    Registry:AttachStorage(FX.db and FX.db.timer and FX.db.timer.learned or {})
    Registry:Build(FX._playerClass)
    Casts.resolveName = nil
    Casts.now = nil
    Casts.onRow = Casts.onRow     -- the module's own kick, untouched
    Rows:Clear()
    D:RenderIdle()
    assertTrue(true)
end)
