-- addon/Forte_Timer/tests/test_expiry_identity.lua
-- Code-review-4 E3 + E5: the Timer's OWN expiry event, and the identity a row
-- the player cast carries into the break site's liveness gate.
--
-- E3. `FX_TIMER_EXPIRED` used to be produced by a wrapper Forte_Messages
-- installed over `FX.Timer.Module.options.onExpire` at ITS enable -- a seam
-- the real enable order never reached (Forte_Messages enables before
-- Forte_Timer builds `options`, and a Timer re-enable rebuilds the table),
-- so the whole "Timer Expiry" group was dead on the client while the suite,
-- firing the event by hand, stayed green. The event is now fired by the Timer
-- itself, at its expiry site (`Core/Rows.lua`'s Sweep). The rules tested
-- here: ONE fire per row per expiry, the payload is `(spell, target, kind)`,
-- the fade and the break are NOT expiries, the Sweep is the fire's ONLY
-- producer (the module's `announceExpiry` channel is a chat line, not a
-- second event), and the bus is INDEPENDENT of the `AnnounceExpiry` chat gate
-- (m7) -- a row born under the gate's default OFF still rides the bus,
-- because the bus is the fact and the consumers' own rows (all opt-in) are
-- the gates.
--
-- E5. The source's break site (`/tmp/fxref/Forte_Timer/Forte_Timer.lua:1207
-- -1211`, "the loop's unit is live") reads `UnitIsDead(unit)`; `Rows:TargetIsDead`
-- answers that for a row carrying an identity PAIR -- a probeable token AND
-- the plain guid that token had at the stamp (the source's column 11,
-- `:1161`). The aura paths stamp that pair into `unitToken`/`guid`
-- (`Core/Reconcile.lua`'s `TokenGuid`, carried by `InsertFromAura`); a row
-- born from ONE OF MY OWN CASTS (`Core/Casts.lua`'s Pump) had NEITHER, so the
-- common real shape of a crowd control -- my banish on my CURRENT TARGET, and
-- the target DIES inside the window -- arrived as a "Broke Early!" announce
-- plus four break sounds.
--
-- THE SHAPE OF THE FIX (the manager's E5 ruling): the cast path stamps a
-- SEPARATE pair, `castToken`/`castGuid`, that the liveness gate is the only
-- consumer of. `row.guid` is the aura law's ADOPTION KEY -- the identity a
-- confirming aura read is compared against, and the thing that stops a row
-- from being adopted by a stranger -- and it is set by the confirming read
-- and by nothing else. Stamp it at the cast and a prediction becomes
-- adoptable by identity, which moves `row.predicted` (the §5.5 prediction
-- marking the panel draws) with it. So the tests below assert BOTH halves:
-- the cast stamp makes the kill silent, and the cast stamp does not touch
-- `guid`, `predicted`, the row key, or the adoption verdict.
--
-- The seams are production's: `Casts.now`, `Casts.resolveName`,
-- `Reconcile.liveness` (the ONE identity reader, which the cast stamp reads
-- through `Reconcile:TokenGuid` -- no second reader, no new game call in the
-- cast file), `Rows.liveness` (the reader the gate consults), the
-- `AnnounceExpiry` row through `FX.Settings`. The cast path resolves its
-- target through the client's own `UnitExists`/`UnitName`/`UnitIsDead`, so the
-- cast tests install those three for the duration of the test and put the
-- real ones back (`test_rows.lua`'s `_G.C_Secrets` install is the same idiom).
-- `Rows.options` is installed as a PRIVATE table for the duration of every
-- test here and the live one is put back: the live one IS
-- `FX.Timer.Module.options`, and stubbing its `hide`/`onExpire`/`onBroken`
-- fields is how this file used to leak into `test_module.lua` (a truthy
-- `options.hide` silences the module's Draw, and the panel stops showing).
local FX = ForteXorcist

local Rows = FX.Timer.Rows
local Casts = FX.Timer.Casts
local Reconcile = FX.Timer.Reconcile
local Registry = FX.Timer.Registry
local Laws = FX.Timer.Laws
local TM = FX.Timer.Module
local ST = FX.Settings

--- A Hunter registry: the names and the durations are the data's, and the
--- sim's profile class is not a Hunter (the `test_rows.lua` convention).
local function buildHunterRegistry()
    Registry:AttachStorage({})
    local n = Registry:Build("HUNTER")
    assertTrue(n and n > 0)
    return n
end

--- The module's enable path, public and idempotent (the gate run's login
--- sequence does not reach Forte_Core's module loop -- the established finding
--- of `test_module.lua`), and the ONLY way these tests reach
--- `FX.Timer.Module.options`: the enable is where that table is built.
local function enableTimer()
    if not TM.options then TM:OnEnable() end
    return TM
end

local liveOptions
local function quietRows()
    Rows:Clear()
    liveOptions = Rows.options
    Rows.options = {
        smooth = Laws.SMOOTH, maxOn = false, maxRows = 32, oneMax = true,
        maxTimeOn = true, maxTime = Laws.MAXTIME, groupID = true,
        outwands = true, blink = true, blinkAt = Laws.BLINK,
        hideLonger = false, hideTime = Laws.HIDE_TIME,
        expireMessage = false,
        onExpire = function() end,
    }
    return Rows
end
local function restoreRows()
    Rows:Clear()
    Rows.options = liveOptions
    liveOptions = nil
end

local function capture(event)
    local got = {}
    local h = FX.On(event, function(a, b, c, d)
        got[#got + 1] = { a, b, c, d }
    end)
    return got, h
end

-- =========================================================== E3: the event --

test("E3: the Sweep's true-expiry promote fires FX_TIMER_EXPIRED exactly "
.. "once, with (spell, target, kind), and pumping more does not re-fire",
function()
    buildHunterRegistry()
    quietRows()
    local fired, h = capture(FX.EVENTS.TIMER_EXPIRED)
    local clock = { 70000 }
    local row = Rows:InsertFromAura("Serpent Sting", "Vile Poacher",
        70010, 10, 0, nil, 0, 70000)
    assertNotNil(row)
    clock[1] = 70002                       -- 8 s left: not an expiry
    Rows:Sweep(clock[1])
    assertEquals(0, #fired)
    clock[1] = 70010.5                     -- the crossing
    Rows:Sweep(clock[1])
    assertEquals(1, #fired)
    assertEquals("Serpent Sting", fired[1][1])
    assertEquals("Vile Poacher", fired[1][2])
    assertEquals(Registry.KindFor("Serpent Sting"), fired[1][3],
        "the payload kind is the row's own")
    clock[1] = 70012                       -- pumping more: no second fire
    Rows:Sweep(clock[1])
    assertEquals(1, #fired)
    FX.Off(h)
    restoreRows()
end)

test("E3: the fade is a warning and the break is a BROKEN -- neither fires "
.. "the expiry on the bus", function()
    buildHunterRegistry()
    quietRows()
    local expired, he = capture(FX.EVENTS.TIMER_EXPIRED)
    local broken, hb = capture(FX.EVENTS.TIMER_BROKEN)
    local clock = { 71000 }
    local fade = Rows:InsertFromAura("Serpent Sting", "Vile Poacher",
        71010, 10, 0, nil, 0, 71000)
    assertNotNil(fade)
    clock[1] = 71007.5                     -- inside the fade band: the warning
    Rows:Sweep(clock[1])
    assertEquals(0, #expired, "the fade is not an expiry")
    assertEquals(0, #broken)
    -- A break: 5 s past the cast (past the BUFF_DELAY grace) with 5 s of
    -- window left (outside the last-MAXLAG band) -- the :1207 site.
    local brk = Rows:InsertFromAura("Hunter's Mark", "River Crocolisk",
        71010, 10, 0, nil, 0, 71000)
    assertNotNil(brk)
    assertEquals("removed", Rows:OnAuraAbsent(brk, 71005))
    assertEquals(1, #broken)
    assertEquals(0, #expired, "a break is not an expiry")
    FX.Off(he)
    FX.Off(hb)
    restoreRows()
end)

test("E3: the bus event is INDEPENDENT of the AnnounceExpiry chat gate (m7) "
.. "-- a row born under the gate's default OFF still rides the bus",
function()
    buildHunterRegistry()
    enableTimer()
    quietRows()
    -- The gate, as production ships it (the SpellTimer page's row).
    ST:Set("SpellTimer", "AnnounceExpiry", false)
    assertFalse(TM.options.expireMessage)
    local fired, h = capture(FX.EVENTS.TIMER_EXPIRED)
    local chat = 0
    Rows.options.onExpire = function() chat = chat + 1 end
    Rows.options.expireMessage = TM.options.expireMessage
    local clock = { 72000 }
    local row = Rows:InsertFromCast("Serpent Sting", "Vile Poacher",
        10, 72000, 72000)
    assertEquals(0, row.expireMsgAt,
        "the gate stamped the row's chat column 0 (the m7 gate)")
    clock[1] = 72010.5                     -- the crossing
    Rows:Sweep(clock[1])
    assertEquals(0, chat, "the gated CHAT path did not run")
    assertEquals(1, #fired, "the bus event did")
    FX.Off(h)
    restoreRows()
end)

test("E3: the Sweep is the fire's ONLY producer -- with the chat gate ON one "
.. "expiry is one bus fire and one chat line, not two events", function()
    buildHunterRegistry()
    enableTimer()
    quietRows()
    ST:Set("SpellTimer", "AnnounceExpiry", true)
    assertTrue(TM.options.expireMessage)
    local fired, h = capture(FX.EVENTS.TIMER_EXPIRED)
    -- The channel under test is the module's real one, installed by its own
    -- enable: the seam is `options.onExpire`, and this test is about what the
    -- Timer's expiry site does with it.
    local channel = TM.options.onExpire
    assertNotNil(channel, "the enable installed the announce channel")
    local chat = 0
    Rows.options.onExpire = function(row)
        chat = chat + 1
        channel(row)
    end
    local printed, realPrint = {}, FX.Print
    FX.Print = function(text) printed[#printed + 1] = text end
    local clock = { 73000 }
    -- A CAST row: the chat gate stamps the row's column 12 at the insert
    -- (`m7`), which is what makes the channel run at the crossing.
    Rows.options.expireMessage = true
    local row = Rows:InsertFromCast("Serpent Sting", "Vile Poacher",
        10, 73000, 73000)
    assertNotNil(row)
    assertEquals(1, row.expireMsgAt, "the gate ON stamped the chat column")
    local notified = FX.Timer.NotifyExpiry or 0
    clock[1] = 73010.5
    Rows:Sweep(clock[1])
    Rows:Sweep(clock[1] + 2)              -- pumping more: no second of either
    assertEquals(1, #fired, "the sweep fired the bus event ONCE")
    assertEquals(1, chat, "the chat channel ran ONCE")
    assertEquals(1, #printed, "one chat line -- a VIEW of that same expiry")
    assertEquals(notified + 1, FX.Timer.NotifyExpiry,
        "the channel's counter moved with it, not twice")
    FX.Print = realPrint
    FX.Off(h)
    restoreRows()
end)

-- ==================================================== E5: the cast identity --

--- The three client reads `Casts:ResolveTarget` walks the token list with,
--- installed for the duration of a test (the sim has no target unit), plus
--- the ONE identity reader the stamp consults. Everything is put back.
local function installUnitIdentity(guid)
    local saved = {
        UnitExists = _G.UnitExists, UnitName = _G.UnitName,
        UnitIsDead = _G.UnitIsDead, liveness = Reconcile.liveness,
    }
    _G.UnitExists = function(token) return token == "target" end
    _G.UnitName = function(token)
        return token == "target" and "Vile Poacher" or nil
    end
    _G.UnitIsDead = function() return false end
    Reconcile.liveness = function(token)
        if token == "target" then return guid, false, false end
        return nil
    end
    return saved
end
local function restoreUnitIdentity(saved)
    _G.UnitExists, _G.UnitName, _G.UnitIsDead =
        saved.UnitExists, saved.UnitName, saved.UnitIsDead
    Reconcile.liveness = saved.liveness
end

--- The public cast spine for one spell at one target: SENT, SUCCEEDED, and
--- the Pump that lands the row at the settle.
local function castAtTarget(spellID, target, now)
    Casts:OnSent(target, spellID, now)
    Casts:OnSucceeded(spellID, now)
    Casts:Pump(now + Laws.SETTLE + 0.01)
end

test("E5: the cast pump stamps its identity into the SEPARATE cast pair and "
.. "never touches the adoption key -- `guid`, `predicted`, the row key and "
.. "the adoption verdict all stay the aura law's", function()
    buildHunterRegistry()
    enableTimer()
    quietRows()
    local GUID = "000000000000FE00\1Vile Poacher\1A"
    Casts:Init(Rows, Rows.options)
    Casts:Erase()
    local savedCasts = {
        resolveName = Casts.resolveName, now = Casts.now,
        onRow = Casts.onRow,
    }
    Casts.resolveName = function(id)
        return id == 425737 and "Serpent Sting" or nil
    end
    Casts.now = function() return 15000 end
    Casts.onRow = nil                       -- no display work in this test
    local saved = installUnitIdentity(GUID)
    castAtTarget(425737, "Vile Poacher", 15000)
    local row = Rows:Find("Serpent Sting", "Vile Poacher")
    assertNotNil(row, "the predicted row is there, on the cast's key")
    -- The cast pair.
    assertEquals("target", row.castToken,
        "the cast's target string resolved to a probeable token")
    assertEquals(GUID, row.castGuid,
        "the stamp runs the aura path's OWN reader (no second reader)")
    -- The adoption key, untouched.
    assertNil(row.guid, "the cast path has no part in the adoption key")
    assertEquals(true, row.predicted,
        "a cast-time stamp does not mark the row confirmed")
    assertEquals("Vile Poacher", row.targetKey,
        "the row keeps the cast's (spell, target) key")
    -- The adoption law is untouched by the stamp: the confirming read of the
    -- SAME unit that the cast named is the plain adopt it always was.
    local verdict = Rows:OnAuraFact(row, row.expireAt, row.total, 0,
        15001, "target", nil, GUID)
    assertEquals("adopt", verdict, "the stamp did not gate the adopt")
    assertEquals(false, row.predicted,
        "the AURA read is what marks the row confirmed")
    assertEquals(GUID, row.guid, "and the aura read is what stamps the key")
    -- A SEALED identity read stamps no guid, and the row then keeps today's
    -- fail-open break; its adoption is the identical one (the pair is not a
    -- gate on the aura law, in either direction).
    Reconcile.liveness = function() return nil end
    Casts:Erase()
    castAtTarget(425737, "Vile Poacher", 20000)
    local sealed = Rows:Find("Serpent Sting", "Vile Poacher")
    assertNotNil(sealed, "the sealed row is the ADOPT of the live key")
    assertEquals("target", sealed.castToken)
    assertNil(sealed.castGuid, "nil-if-secret: no cast identity is stamped")
    assertNil(sealed.guid, "and the adoption key is still untouched")
    Casts.resolveName, Casts.now, Casts.onRow =
        savedCasts.resolveName, savedCasts.now, savedCasts.onRow
    restoreUnitIdentity(saved)
    Casts:Erase()
    restoreRows()
end)

local function captureBroken()
    local events = {}
    local h = FX.On(FX.EVENTS.TIMER_BROKEN, function(spell, target, kind)
        events[#events + 1] = { spell, target, kind }
    end)
    return events, h
end

--- A row with a cast-stamped identity, built through the public insert so the
--- pair is the only thing the test touches.
local function castStampedRow(spell, target, duration, base, token, guid)
    local row = Rows:InsertFromCast(spell, target, duration, base, base)
    assertNotNil(row)
    row.castToken, row.castGuid = token, guid
    return row
end

test("E5: the gate reads the cast pair when the aura has said nothing -- the "
.. "KILL of my cast's target is silent, the same pair ALIVE is the break, and "
.. "a sealed identity is the break (the fail-open law)", function()
    buildHunterRegistry()
    quietRows()
    local GUID = "000000000000FE00\1Vile Poacher\1B"
    local events, h = captureBroken()
    local probe = Rows.liveness
    local function L(guid, dead, ghost)
        Rows.liveness = function(token)
            assertEquals("target", token, "the gate probes the row's token")
            return guid, dead, ghost
        end
    end
    -- The kill: my cast, my target, the target died inside the window and
    -- took the debuff with it. The source mutes this one (:1208).
    local killed = castStampedRow("Serpent Sting", "P-Kill", 12, 300,
        "target", GUID)
    L(GUID, true, false)
    assertEquals("removed", Rows:OnAuraAbsent(killed, 305))
    assertEquals(0, #events, "a kill is not a break (the source's :1207)")
    assertEquals(Laws.REMOVE, killed.state, "the row is retired all the same")
    -- The real break: the same everything, a unit stamped ALIVE.
    local broke = castStampedRow("Serpent Sting", "P-Broke", 12, 400,
        "target", GUID)
    L(GUID, false, false)
    assertEquals("removed", Rows:OnAuraAbsent(broke, 405))
    assertEquals(1, #events, "a live unit's vanished aura is the break")
    assertEquals("Serpent Sting", events[1][1])
    assertEquals("P-Broke", events[1][2])
    -- The ghost half (a released spirit) is the kill shape too.
    local ghosted = castStampedRow("Serpent Sting", "P-Ghost", 12, 500,
        "target", GUID)
    L(GUID, false, true)
    assertEquals("removed", Rows:OnAuraAbsent(ghosted, 505))
    assertEquals(1, #events, "a released spirit is not a break either")
    -- A SEALED identity read: no plain guid to compare, so no answer, so the
    -- break rides on exactly as it did before the gate existed.
    local sealed = castStampedRow("Serpent Sting", "P-Sealed", 12, 600,
        "target", GUID)
    Rows.liveness = function()
        return setmetatable({}, { __index = function() return nil end }),
            true, true
    end
    assertEquals("removed", Rows:OnAuraAbsent(sealed, 605))
    assertEquals(2, #events, "a secret guid is the documented fail-open")
    Rows.liveness = probe
    FX.Off(h)
    restoreRows()
end)

test("E5: everything the gate can not read keeps today's break, and the "
.. "aura-confirmed pair still answers -- the cast pair is additive",
function()
    buildHunterRegistry()
    quietRows()
    local GUID = "000000000000FE00\1Vile Poacher\1C"
    local events, h = captureBroken()
    local probe = Rows.liveness
    Rows.liveness = function(token)
        if token == "target" then return GUID, true, false end
        return nil
    end
    -- (a) no identity at all: nothing to consult, today's answer.
    local plain = Rows:InsertFromCast("Serpent Sting", "P-Plain", 12, 700, 700)
    assertNotNil(plain)
    assertEquals("removed", Rows:OnAuraAbsent(plain, 705))
    assertEquals(1, #events, "no stamp: the break fires as it used to")
    -- (b) a token the gate is not allowed to probe: no answer, today's shape.
    local offScope = castStampedRow("Serpent Sting", "P-Off", 12, 800,
        "party1", GUID)
    assertEquals("removed", Rows:OnAuraAbsent(offScope, 805))
    assertEquals(2, #events, "a token outside LIVENESS_TOKENS is fail-open")
    -- (c) the identity MOVED: the token now names a unit that is not the
    -- row's, so the read is of no unit the row knows.
    local moved = castStampedRow("Serpent Sting", "P-Moved", 12, 900,
        "target", "SOME-OTHER-UNIT")
    assertEquals("removed", Rows:OnAuraAbsent(moved, 905))
    assertEquals(3, #events, "a guid that is not the row's is fail-open")
    -- (d) no reader at all.
    Rows.liveness = nil
    local readerless = castStampedRow("Serpent Sting", "P-NoReader", 12, 1000,
        "target", GUID)
    assertEquals("removed", Rows:OnAuraAbsent(readerless, 1005))
    assertEquals(4, #events, "no reader: the break fires as it used to")
    Rows.liveness = function(token)
        if token == "target" then return GUID, true, false end
        return nil
    end
    -- (e) the aura law's pair keeps answering exactly as before: a dead
    -- CONFIRMED row is silent, and a confirmed row wins the pair -- the token
    -- the confirming read named, not a cast stamp.
    local confirmed = Rows:InsertFromAura("Hunter's Mark", "target", 1112, 12,
        0, "target", 0, 1100, GUID)
    assertNotNil(confirmed)
    assertEquals(GUID, confirmed.guid, "the confirming read stamped the key")
    assertEquals("removed", Rows:OnAuraAbsent(confirmed, 1105))
    assertEquals(4, #events, "the aura pair is as mute on a kill as it was")
    -- (f) and a confirmed row ignores a cast stamp that would say otherwise.
    confirmed.castToken, confirmed.castGuid = "target", "SOME-OTHER-UNIT"
    assertEquals("removed", Rows:OnAuraAbsent(confirmed, 1105))
    assertEquals(4, #events,
        "the confirmed pair is the answer: the cast pair never overrides it")
    Rows.liveness = probe
    FX.Off(h)
    restoreRows()
end)

test("E5: the production consequence end to end -- the row I cast at my "
.. "current target, and my target DIES: no BROKEN, no announce, no four "
.. "sounds; the same cast at a target that lives: the break rides",
function()
    buildHunterRegistry()
    enableTimer()
    quietRows()
    local GUID = "000000000000FE00\1Vile Poacher\1D"
    Casts:Init(Rows, Rows.options)
    Casts:Erase()
    local savedCasts = {
        resolveName = Casts.resolveName, now = Casts.now,
        onRow = Casts.onRow,
    }
    Casts.resolveName = function(id)
        return id == 425737 and "Serpent Sting" or nil
    end
    Casts.now = function() return 15000 end
    Casts.onRow = nil
    local saved = installUnitIdentity(GUID)
    castAtTarget(425737, "Vile Poacher", 15000)
    local row = Rows:Find("Serpent Sting", "Vile Poacher")
    assertNotNil(row)
    assertEquals("target", row.castToken)
    assertEquals(GUID, row.castGuid)
    -- The gate now reads the same unit the cast named, and the client says it
    -- is dead: the debuff dropping is the kill.
    local events, h = captureBroken()
    local probe = Rows.liveness
    Rows.liveness = function(token)
        if token == "target" then return GUID, true, false end
        return nil
    end
    assertEquals("removed", Rows:OnAuraAbsent(row, 15005))
    assertEquals(0, #events, "the kill of my own cast's target is SILENT")
    -- The same cast, a target that lives: the break rides.
    Casts:Erase()
    castAtTarget(425737, "Vile Poacher", 20000)
    local live = Rows:Find("Serpent Sting", "Vile Poacher")
    assertNotNil(live)
    assertEquals("target", live.castToken)
    assertEquals(GUID, live.castGuid)
    Rows.liveness = function(token)
        if token == "target" then return GUID, false, false end
        return nil
    end
    assertEquals("removed", Rows:OnAuraAbsent(live, 20005))
    assertEquals(1, #events, "a live unit's vanished aura is the break")
    Rows.liveness = probe
    FX.Off(h)
    Casts.resolveName, Casts.now, Casts.onRow =
        savedCasts.resolveName, savedCasts.now, savedCasts.onRow
    restoreUnitIdentity(saved)
    Casts:Erase()
    restoreRows()
end)
