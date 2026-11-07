-- addon/Forte_Timer/tests/test_unit_died.lua
-- Code-review-5 M4 + code-review-10 M1: the `UNIT_DIED` registration
-- (Module.lua:802, the BASE-event form `f:RegisterEvent("UNIT_DIED")`) is
-- payload-bearing (the pinned catalog hands (unitGUID, WOWGUID),
-- SecretWhenUnitIdentityRestricted), and its branch (Module.lua's OnEvent) is
-- the target-death cleanup -- the OPPORTUNISTIC half of the E5 liveness law:
-- my target died inside the window, so the rows keyed against the target unit
-- die with it, SILENT -- no FX_TIMER_BROKEN, no announce (the kill law
-- test_expiry_identity.lua proved at the Rows:TargetIsDead seam, here and
-- there the same verdict).
--
-- M1 (code-review-10): this suite used to certify a feature that could not
-- fire on the shipped client -- it drove the branch by hand while the
-- registration (`pcall(RegisterUnitEvent, ..., "target")`) lost the whole
-- feature on the live client, and no test touched the registration at all.
-- The first test below pins the REGISTRATION SHAPE (the base-event
-- `IsEventRegistered` pin, MT-1/MT-2 of the review), so the suite can not stay
-- green on dead code; the payload legs then drive the REAL event frame.
--
-- The branch reads: the payload classifies through PlainOrNil and must be a
-- PLAIN string (the guid is SecretWhenUnitIdentityRestricted -- it is
-- classified, never compared; a plain GUID string like the catalog's WOWGUID
-- payload is a plain string, and the content is inert to the branch); every
-- live row whose `unitToken` names the "target" unit then faces the gate --
-- THE 2026-11-07 DEAD-CORPSE GATE (iteration M, the live-client finding):
-- the gate is the client's own `UnitIsDeadOrGhost("target")` answering PLAIN
-- TRUE (a dead mob's corpse, a released player's ghost -- both names in the
-- pinned catalog, UnitToken in, bool out) with `UnitExists("target")`
-- answering PLAIN FALSE riding as the SECOND trigger (the token gone
-- outright: corpse looted, target cleared). The old gate was UnitExists
-- ALONE -- and the client keeps the token alive over a fresh corpse, so on
-- the real client the cleanup almost never fired; the dead-corpse legs pin
-- the fix. The payload's CONTENT is not compared: the dead read is the
-- answer, and a raise or a sealed read is no answer at all.
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

--- The liveness answers the branch reads (the module pcalls the GLOBALS, so
--- the install is `_G.UnitExists` / `_G.UnitIsDeadOrGhost`, the
--- test_pet_rows.lua idiom). `target` says whether the TARGET token still
--- exists; the DEAD read is installed INERT (a nil answer falls the
--- 2026-11-07 gate through to the UnitExists trigger), so these legs keep
--- pinning exactly what they always pinned. Every other token answers its
--- default.
local function installUnitExists(target)
    local saved = { UnitExists = _G.UnitExists,
        UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost }
    _G.UnitExists = function(token)
        if token == "target" then return target end
        return false
    end
    _G.UnitIsDeadOrGhost = function() return nil end
    return saved
end
local function restoreUnitExists(saved)
    _G.UnitExists = saved.UnitExists
    _G.UnitIsDeadOrGhost = saved.UnitIsDeadOrGhost
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

-- ------------------------------------------------- the registration shape --
-- MT-1 / MT-2 (code-review-10 section (c) 1+2): before this pair the suite
-- grepped zero `IsEventRegistered` -- the multi-unit registration shape (the
-- headline fix of d490e2e) and the UNIT_DIED base-event registration were
-- BOTH unpinned, which is exactly how M1 stayed green while the live client
-- lost the feature. These legs drive the real frame's registration, so the
-- suite cannot stay green on dead code.

--- The frame's registration report for one (event, unit) pair — the query
--- form the client answers (`IsEventRegistered(event, unit)`; the event-only
--- form answers nil for a unit-keyed event). The multi-unit law of
--- d490e2e: one call carrying BOTH units registers BOTH, so the pair query is
--- the shape that proves it — a per-event second call replacing the first
--- unit set shows up here as the pet pair answering falsy.
local function registration(f, event, unit)
    local ok, isReg = pcall(f.IsEventRegistered, f, event, unit)
    assertTrue(ok, "the client frame answers IsEventRegistered("
        .. event .. ", " .. tostring(unit) .. ")")
    if not ok then return nil end
    return isReg and true or false
end

test("MT-2: UNIT_DIED is registered as a BASE event (M1: the feature fires on the live client)",
function()
    enableTimer()
    local f = M._eventFrame
    -- The base-event query (no unit) is the base form's own answer.
    local base = registration(f, "UNIT_DIED", nil)
    print(string.format("[unit-died] IsEventRegistered(UNIT_DIED): %s",
        tostring(base)))
    assertEquals(true, base, "UNIT_DIED is registered on the event frame (M1:"
        .. " the base RegisterEvent form; the old RegisterUnitEvent leg lost"
        .. " the whole feature on the live client and NO test touched the"
        .. " registration, so the suite stayed green on dead code)")
    -- The per-unit half of the M1 shape: a unit-keyed registration must
    -- answer the (event, "target") pair. The pinned catalog answers it; the
    -- SIM answers every pair query for a registered event as true (its
    -- IsEventRegistered is event-keyed), so on the sim the falsy assertion
    -- is NOT observable -- it prints what the client answers, and the
    -- shipped client is where the pair query answering falsy (the base
    -- form's whole point) is the fact the review's M1 rides.
    local keyed = registration(f, "UNIT_DIED", "target")
    print(string.format("[unit-died] IsEventRegistered(UNIT_DIED, target): %s"
        .. " (the strict falsy leg is the real client's pair query)",
        tostring(keyed)))
    if keyed ~= nil and keyed ~= true then
        assertFalse(keyed,
            "UNIT_DIED is not registered for the target unit: the catalog"
            .. " payload is unitGUID, so the base form is the shape")
    end
end)

test("MT-1: the cast spine registers the multi-unit shape (player,pet), one call per event",
function()
    enableTimer()
    local f = M._eventFrame
    for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_SUCCEEDED" }) do
        assertEquals(true, registration(f, event, "player"),
            event .. " rides the player unit")
        assertEquals(true, registration(f, event, "pet"),
            event .. " rides the pet unit in the SAME registration (a second"
            .. " call replaces the first unit set: the live finding of"
            .. " 2026-11-06 -- the shape d490e2e fixed)")
    end
    for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED" }) do
        assertEquals(true, registration(f, event, "player"),
            event .. " rides the player unit")
    end
    -- UNIT_AURA: the player/target pair, one call.
    assertEquals(true, registration(f, "UNIT_AURA", "player"),
        "UNIT_AURA rides the player unit")
    assertEquals(true, registration(f, "UNIT_AURA", "target"),
        "UNIT_AURA rides the target unit in the same call")
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

test("the catalog payload itself (a WOWGUID string) retires the target rows",
function()
    -- M1: the base event hands a GUID, not a unit token -- the live client's
    -- every real payload of this event is shaped like this. The branch is
    -- content-agnostic (a plain string is a plain string), so a GUID-shaped
    -- payload retires the rows exactly as the token-shaped ones do: this leg
    -- is the shape the token-only legs could not answer for.
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    local killed = seedTargetRow("Serpent Sting", "Vile Poacher")
    local selfRow = seedSelfRow("Hunter's Mark")
    local saved = installUnitExists(false)
    -- The catalog's payload type for UNIT_DIED: unitGUID, a WOWGUID string.
    dispatch("UNIT_DIED", "Creature-0-1142-65-1-1096-0")
    restoreUnitExists(saved)
    assertEquals(Laws.REMOVE, killed.state,
        "the GUID-shaped payload retires the target row")
    assertEquals(Laws.NORMAL, selfRow.state, "the self row rides on")
    Rows:Clear()
end)

-- ------------------------------------------------------- the dead corpse --
-- THE 2026-11-07 LIVE-CLIENT FINDING (iteration M): UnitExists("target")
-- answers TRUE over a fresh corpse -- the token dies only when the corpse
-- is looted, the player releases, the target is cleared -- so the old
-- UnitExists-ALONE gate let a dead target's rows ride their full duration
-- on the real client. The gate is now the catalog's
-- UnitIsDeadOrGhost("target") first (docs/api/wow-addon-api-agents: UnitIs-
-- Dead and UnitIsDeadOrGhost are BOTH pinned, (unit UnitToken) -> bool, the
-- bool return not secret-annotated; the ghost half covers a released
-- player), UnitExists == false riding as the second trigger. Every leg
-- installs BOTH reads and drives the real frame with the catalog's GUID
-- payload; the first leg fails on the UnitExists-alone branch.

--- The sentinel that makes an installed read RAISE (the branch pcalls every
--- global read, so a raise is the client's own failing-read shape).
local RAISE = { "fx-test-raise" }
--- Install BOTH liveness reads for one leg: `exists` answers
--- UnitExists("target"), `isDead` answers UnitIsDeadOrGhost("target").
local function installUnitState(exists, isDead)
    local saved = { UnitExists = _G.UnitExists,
        UnitIsDeadOrGhost = _G.UnitIsDeadOrGhost }
    _G.UnitExists = function(token)
        if token ~= "target" then return false end
        if exists == RAISE then error("fx-test: UnitExists raise") end
        return exists
    end
    _G.UnitIsDeadOrGhost = function(token)
        if token ~= "target" then return nil end
        if isDead == RAISE then error("fx-test: UnitIsDeadOrGhost raise") end
        return isDead
    end
    return saved
end
local function restoreUnitState(saved)
    _G.UnitExists = saved.UnitExists
    _G.UnitIsDeadOrGhost = saved.UnitIsDeadOrGhost
end

test("the dead corpse: the token EXISTS, the target is DEAD -> its rows fade (2026-11-07; fails on the UnitExists-alone gate)",
function()
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    local killed = seedTargetRow("Serpent Sting", "Vile Poacher")
    local selfRow = seedSelfRow("Hunter's Mark")
    local broken, hb = capture(FX.EVENTS.TIMER_BROKEN)
    -- The real client's every UNIT_DIED for my own kill answers THIS pair:
    -- the corpse keeps the token alive, the dead verdict is true.
    local saved = installUnitState(true, true)
    dispatch("UNIT_DIED", "Creature-0-1142-65-1-1096-0")
    restoreUnitState(saved)
    assertEquals(Laws.REMOVE, killed.state,
        "the corpse keeps the token alive; the DEAD read retires the row"
        .. " (the UnitExists-alone gate let it ride)")
    assertTrue(killed.removeAt > 0, "the fade stamp rides the removal")
    assertEquals(Laws.NORMAL, selfRow.state, "the self row rides on")
    assertEquals(0, #broken, "the kill is SILENT: no BROKEN, no announce")
    FX.Off(hb)
    Rows:Clear()
end)

test("the second trigger stands: token GONE (UnitExists false, no dead read) retires the rows",
function()
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    local killed = seedTargetRow("Serpent Sting", "Vile Poacher")
    local selfRow = seedSelfRow("Hunter's Mark")
    -- The corpse looted / the target cleared: no dead verdict, a plain
    -- false liveness read. The dead gate falls through, UnitExists fires.
    local saved = installUnitState(false, nil)
    dispatch("UNIT_DIED", "Creature-0-1142-65-1-1096-0")
    restoreUnitState(saved)
    assertEquals(Laws.REMOVE, killed.state,
        "the gone token retires the row through the second trigger")
    assertEquals(Laws.NORMAL, selfRow.state, "the self row rides on")
    Rows:Clear()
end)

test("the target lives: token exists, not dead -> nothing moves",
function()
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    local kept = seedTargetRow("Serpent Sting", "Vile Poacher")
    -- Somebody else died (the base event fires for EVERY death in range)
    -- while my target stands: both reads answer alive.
    local saved = installUnitState(true, false)
    dispatch("UNIT_DIED", "Creature-0-1142-65-1-2001-0")
    restoreUnitState(saved)
    assertEquals(Laws.NORMAL, kept.state,
        "an alive target answers the whole event")
    Rows:Clear()
end)

test("a RAISING read is no verdict: pcall'd, inert, rows ride",
function()
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    local kept = seedTargetRow("Serpent Sting", "Vile Poacher")
    -- Both reads raise (a client that refuses the read): the branch pcalls
    -- them, no verdict classifies, the rows ride row-expiry.
    local saved = installUnitState(RAISE, RAISE)
    dispatch("UNIT_DIED", "Creature-0-1142-65-1-1096-0")
    restoreUnitState(saved)
    assertEquals(Laws.NORMAL, kept.state,
        "a raising read ran the cleanup (or raised through the frame)")
    Rows:Clear()
end)

test("SEALED reads are no verdict: classified nil on both triggers, rows ride",
function()
    enableTimer()
    buildHunterRegistry()
    Rows:Clear()
    local kept = seedTargetRow("Serpent Sting", "Vile Poacher")
    -- Both reads return the sentinel: PlainOrNil classifies it nil -- nil
    -- is neither the true the dead gate wants nor the false the liveness
    -- gate wants, so the branch stays inert (the plain nil is no verdict;
    -- a sealed read never overwrites known state, the module law).
    local saved = installUnitState(SECRET, SECRET)
    patchPlain()
    dispatch("UNIT_DIED", "Creature-0-1142-65-1-1096-0")
    restorePlain()
    restoreUnitState(saved)
    assertEquals(Laws.NORMAL, kept.state,
        "a sealed read ran the cleanup")
    Rows:Clear()
end)

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
