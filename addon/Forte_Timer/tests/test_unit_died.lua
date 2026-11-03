-- addon/Forte_Timer/tests/test_unit_died.lua
-- Code-review-5 M4: the `UNIT_DIED("target")` registration (Module.lua:577)
-- is payload-bearing (the catalog hands (unitToken)), and its branch
-- (Module.lua:672) is the target-death cleanup -- the OPPORTUNISTIC half of
-- the E5 liveness law: my target died inside the window, so the rows keyed
-- against the target unit die with it, SILENT -- no FX_TIMER_BROKEN, no
-- announce (the kill law test_expiry_identity.lua proved at the
-- Rows:TargetIsDead seam, here and there the same verdict).
--
-- The branch reads: the payload classifies through PlainOrNil and must be a
-- PLAIN string (the guid is SecretWhenUnitIdentityRestricted -- it is
-- classified, never compared); every live row whose `unitToken` names the
-- "target" unit then faces the client's own `UnitExists("target")` -- a
-- PLAIN false (the unit token is gone: the death cleanup) fades the row
-- REMOVED at once. The payload's CONTENT is not compared: the liveness read
-- is the answer.
--
-- Every test drives the REAL event frame with the exact client payload (the
-- dispatch idiom of test_module.lua: the frame is argument 1) -- a test
-- calling M:OnEvent by hand would not pin the binding, and the liveness
-- answer is installed (the sim has no target unit; test_pet_rows.lua's
-- installUnits is the same idiom).
local FX = ForteXorcist
local M = FX.Timer.Module
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Registry = FX.Timer.Registry

--- A Hunter registry (the fixture names are the data's; the sim's profile
--- class is not a Hunter -- the test_rows.lua convention).
local function buildHunterRegistry()
    Registry:AttachStorage({})
    local n = Registry:Build("HUNTER")
    assertTrue(n and n > 0)
end

--- The module's enable path, public and idempotent (the gate run's login
--- sequence does not reach Forte_Core's module loop -- test_module.lua's
--- established finding), and the only way to the frame.
local function enableTimer()
    if not M.options then M:OnEnable() end
    return M
end

local function dispatch(event, a1, a2, a3, a4)
    local f = M._eventFrame
    assertNotNil(f)
    local onEvent = f:GetScript("OnEvent")
    assertNotNil(onEvent)
    -- The frame is argument 1 (the binding law of PLAN §10.2).
    onEvent(f, event, a1, a2, a3, a4)
end

-- The sentinel seam of test_tiers.lua / test_procs.lua: the sim exposes no
-- verb to mint a real secret value, so PlainOrNil is patched so the sentinel
-- classifies as nil -- the exact downstream contract a live secret has.
local SECRET = "FXTEST-SECRET-VALUE"
local realPlainOrNil = FX.Compat.PlainOrNil
local function patchPlain()
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlainOrNil(v)
    end
end
local function restorePlain()
    FX.Compat.PlainOrNil = realPlainOrNil
end

--- The liveness answer the branch reads (the module pcalls the GLOBAL, so
--- the install is `_G.UnitExists`, the test_pet_rows.lua idiom). `target`
--- says whether the TARGET token still exists; every other token answers
--- its default.
local function installUnitExists(target)
    local saved = _G.UnitExists
    _G.UnitExists = function(token)
        if token == "target" then return target end
        return false
    end
    return saved
end
local function restoreUnitExists(saved)
    _G.UnitExists = saved
end

local function capture(event)
    local got = {}
    local h = FX.On(event, function(a, b, c, d)
        got[#got + 1] = { a, b, c, d }
    end)
    return got, h
end

--- A row confirmed against the TARGET unit (the token the confirming aura
--- read saw), plus a self row confirmed against the PLAYER.
local function seedTargetRow(spell, target)
    local now = GetTime()
    local row = Rows:InsertFromAura(spell, target, now + 60, 60, 0,
        "target", 0, now, "000000000000FE00\1" .. target .. "\1D")
    assertNotNil(row, "the target-token row is there")
    assertEquals("target", row.unitToken)
    return row
end
local function seedSelfRow(spell)
    local now = GetTime()
    local row = Rows:InsertFromAura(spell, "none", now + 60, 60, 0,
        "player", 0, now, nil)
    assertNotNil(row, "the self row is there")
    assertEquals("player", row.unitToken)
    return row
end

-- ------------------------------------------------------------------ live --

test("the feed is live: the module is enabled, the frame bound", function()
    assertNotNil(M)
    enableTimer()
    assertNotNil(M._eventFrame, "the frame is bound at OnEnable")
    buildHunterRegistry()
    assertTrue(Registry.IsTracked("Serpent Sting"))
end)

test("the target's death retires its rows at once, silent (the E5 kill law)",
function()
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    local killed = seedTargetRow("Serpent Sting", "Vile Poacher")
    local selfRow = seedSelfRow("Hunter's Mark")
    local broken, hb = capture(FX.EVENTS.TIMER_BROKEN)
    local expired, he = capture(FX.EVENTS.TIMER_EXPIRED)
    -- The dying unit token is plain text; the target token is GONE.
    local saved = installUnitExists(false)
    -- The catalog payload: (unitToken) -- the registered unit is "target".
    dispatch("UNIT_DIED", "target")
    restoreUnitExists(saved)
    assertEquals(Laws.REMOVE, killed.state,
        "the target row dies with its unit (the opportunistic cleanup)")
    assertTrue(killed.removeAt > 0, "the fade stamp rides the removal")
    assertEquals(Laws.NORMAL, selfRow.state,
        "a row that is not the target's rides on")
    assertEquals(0, #broken, "the kill is SILENT: no BROKEN, no announce")
    assertEquals(0, #expired, "the cleanup is not an expiry")
    FX.Off(hb)
    FX.Off(he)
    Rows:Clear()
end)

test("the payload content is never compared: a name-shaped token retires the rows the same",
function()
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    -- Two rows on two targets, both confirmed against the target unit: the
    -- branch sweeps EVERY live target-token row, not the row keyed on the
    -- dying name.
    local a = seedTargetRow("Serpent Sting", "Vile Poacher")
    local b = seedTargetRow("Hunter's Mark", "River Crocolisk")
    local selfRow = seedSelfRow("Hunter's Mark")
    local saved = installUnitExists(false)
    -- The review's example payload: the DYING UNIT'S NAME, not a token. The
    -- branch classifies the string and consults UnitExists("target"); the
    -- content is not a key.
    dispatch("UNIT_DIED", "Vile Poacher")
    restoreUnitExists(saved)
    assertEquals(Laws.REMOVE, a.state, "the name-shaped token retires row A")
    assertEquals(Laws.REMOVE, b.state, "and row B: the sweep is per token")
    assertEquals(Laws.NORMAL, selfRow.state, "the self row rides on")
    Rows:Clear()
end)

-- ---------------------------------------------------------------- inert --

test("a SEALED payload is inert: the classified token gates the branch",
function()
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    local killed = seedTargetRow("Serpent Sting", "Vile Poacher")
    local saved = installUnitExists(false)
    patchPlain()
    dispatch("UNIT_DIED", SECRET)
    restorePlain()
    assertEquals(Laws.NORMAL, killed.state,
        "a secret token ran the cleanup: the classification gate is gone")
    -- The nil-payload leg (a payload-less dispatch -- the Classic shape of
    -- the event): inert as well.
    dispatch("UNIT_DIED")
    assertEquals(Laws.NORMAL, killed.state, "a nil payload ran the cleanup")
    restoreUnitExists(saved)
    Rows:Clear()
end)

test("the liveness read is the answer: an ALIVE target keeps every row",
function()
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    local killed = seedTargetRow("Serpent Sting", "Vile Poacher")
    -- A pet (or a party member) died: the token is plain, and the target
    -- unit the rows were confirmed against is RIGHT THERE.
    local saved = installUnitExists(true)
    dispatch("UNIT_DIED", "pet")
    restoreUnitExists(saved)
    assertEquals(Laws.NORMAL, killed.state,
        "an alive target: the death is somebody else's")
    Rows:Clear()
end)

test("rows the gate does not own ride on: fading, removed, tokenless",
function()
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    -- (a) a row already inside the fade band (state > NORMAL) is not
    -- re-stamped -- the branch owns live rows only.
    local fading = seedTargetRow("Serpent Sting", "Vile Poacher")
    Rows:Fade(fading, Laws.FADING, GetTime())
    assertEquals(Laws.FADING, fading.state)
    -- (b) a row already removed: its stamp is its own.
    local removed = seedTargetRow("Hunter's Mark", "River Crocolisk")
    Rows:Fade(removed, Laws.REMOVE, GetTime() - 5)
    local stamp = removed.removeAt
    -- (c) a row with no target token at all: a self-buff prediction.
    local bare = Rows:InsertFromCast("Serpent Sting", "none", 60,
        GetTime(), GetTime())
    assertNotNil(bare)
    assertEquals(nil, bare.unitToken)
    local saved = installUnitExists(false)
    dispatch("UNIT_DIED", "target")
    restoreUnitExists(saved)
    assertEquals(Laws.FADING, fading.state, "the fade band was re-stamped")
    assertEquals(Laws.REMOVE, removed.state)
    assertEquals(stamp, removed.removeAt, "the removed row kept its stamp")
    assertEquals(Laws.NORMAL, bare.state, "the tokenless row was touched")
    Rows:Clear()
end)
