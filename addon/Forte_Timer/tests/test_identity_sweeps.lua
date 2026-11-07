-- addon/Forte_Timer/tests/test_identity_sweeps.lua
-- Code-review-10 section (c) MT-3 + MT-6 + m1: the sweep-identity laws of
-- Core/Reconcile.lua, none of which the suite owned before this file.
--
--   * MT-3 -- `tokenHoldsRowUnit` (the live 2026-11-06 finding): targeting
--     YOURSELF made every target-keyed row read "aura absent" (the aura is on
--     the OLD target, not on you) and fade red. Identity first (the stamped
--     guid), the cast's plain target name second; a row whose unit the token
--     demonstrably does not hold rides the sweep UNREAD.
--   * MT-6 -- the bulk sweep's adoption (the "two Hunter's Mark bars" live
--     case): a cast row keyed by the target's NAME, promoted to the sweep's
--     "target" token, is the adopt target -- the sweep must not insert a
--     second row for the aura it just confirmed on that unit.
--   * m1 -- the adoption band: the live band is NORMAL..REMOVE. `<= REMOVE`
--     alone also matches the IGNORE band (-1, the refuse-removal/zeroing
--     band a row rides while the pump evicts it), and an evicting row must
--     not be the adopt target (the confirmed bar would ride a row that is
--     leaving the array, the insert suppressed by a verdict that is never
--     "inserted").
--
-- The readers are the counted seams (Core/Reconcile.lua's own test contract),
-- and the identity is the ONE liveness reader -- installed, never real (the
-- sim has no target unit; test_expiry_identity.lua's installUnitIdentity is
-- the same idiom). The sweeps run out of combat (the sim's own answer) and
-- the gate's `Reconcile.inCombat` seam is pinned false for determinism.

local FX = ForteXorcist
local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Registry = FX.Timer.Registry
local Reconcile = FX.Timer.Reconcile
local Module = FX.Timer.Module

local TARGET_GUID = "000000000000FE00\1Vile Poacher\1A"
local PLAYER_GUID = "000000000000FE00\1Player\1P"

local function buildHunterRegistry()
    Registry:AttachStorage({})
    local n = Registry:Build("HUNTER")
    assertTrue(n and n > 0)
end

--- The enable the Reconcile.Init wiring rides (the gate run's login sequence
--- does not reach Forte_Core's module loop -- the established finding).
local function enableTimer()
    if not Module.options then Module:OnEnable() end
    return Module
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
    -- Idempotent: the legs run this at the body end AND in the pcall
    -- wrapper, and the first run clears the capture -- a second run must
    -- not write the cleared (nil) table back over the live options (that
    -- leak starves every suite that sorts after this one, the m7 stamp).
    if liveOptions == nil then return end
    Rows:Clear()
    Rows.options = liveOptions
    liveOptions = nil
end

--- Install the identity reader: which guid each token names RIGHT NOW.
local function installLiveness(map)
    local savedR, savedRows = Reconcile.liveness, Rows.liveness
    local function probe(token)
        local g = map[token]
        if g == nil then return nil end
        return g, false, false
    end
    Reconcile.liveness = probe
    Rows.liveness = probe
    return { r = savedR, rows = savedRows }
end
local function restoreLiveness(saved)
    Reconcile.liveness = saved.r
    Rows.liveness = saved.rows
end

--- Install the counted readers. `byName` answers the per-row half; the
--- `auras` list feeds the `byIndex` bounded enumeration — the SweepBulk's
--- test-contract path (the raw-list answer of a `bulk` seam rides the same
--- classified call as a single aura, and the classifier wants one aura's
--- expirationTime; the byIndex enumeration hands one aura per call, which is
--- what `call` classifies cleanly).
local function installReaders(byName, auras)
    local saved = Reconcile.readers
    local counted = { byName = 0 }
    Reconcile.readers = {
        byName = byName and function(unit, name, filter)
            counted.byName = counted.byName + 1
            return byName(unit, name, filter)
        end,
        byIndex = auras and function(unit, i, filter)
            return auras[i]
        end,
    }
    return saved, counted
end
local function restoreReaders(saved)
    Reconcile.readers = saved
end

-- ================================================= MT-3: the sweep gate ==

test("MT-3: a row confirmed on the OLD target rides a sweep of the token that now names the player",
function()
    local __ok, __err = pcall(function()
        enableTimer()
        buildHunterRegistry()
        quietRows()
        local now = 30000
        -- A row the confirming aura read confirmed on the TARGET mob.
        local row = Rows:InsertFromAura("Hunter's Mark", "Vile Poacher",
            now + 90, 90, 0, "target", 0, now, TARGET_GUID)
        assertNotNil(row)
        assertEquals(TARGET_GUID, row.guid, "the row carries the target's identity")
        -- The player now targets THEMSELVES: the "target" token names the player.
        local saved = installLiveness({ target = PLAYER_GUID, player = PLAYER_GUID })
        local readers, counted = installReaders(function() return false end)
        Reconcile.inCombat = false
        Reconcile.lastSweep["target"] = nil
        Reconcile:SweepUnit("target", "HARMFUL", now)
        Reconcile.inCombat = nil
        -- The sweep stamps lastSweep at its fixed test clock; a later file's
        -- gate reads GetTime() against it and a future stamp closes that gate.
        Reconcile.lastSweep["target"] = nil
        restoreReaders(readers)
        restoreLiveness(saved)
        assertEquals(0, counted.byName,
            "the sweep did not READ the row: the token demonstrably holds a "
            .. "different unit (the guid leg answers false)")
        assertEquals(Laws.NORMAL, row.state,
            "the self-target does not wipe the target row (the live 2026-11-06 fix)")
        restoreRows()
    
    end)
    restoreRows()
    if not __ok then error(__err, 0) end
end)

test("MT-3: the same sweep DOES read a row the token really holds (the gate does not freeze the sweep)",
function()
    local __ok, __err = pcall(function()
        enableTimer()
        buildHunterRegistry()
        quietRows()
        local now = 30500
        -- The window has more than MAXLAG left: the aura-absent fact is the
        -- REMOVAL leg (the early break). Inside the last MAXLAG second the
        -- :1207 law REFUSES the removal -- `Rows:OnAuraAbsent` answers "refused"
        -- and touches nothing -- which is the Rows law, not this gate's.
        -- The insert rides a castTime 60 s in the PAST (the 8th arg): an
        -- insert `now` rides inside the BUFF_DELAY grace and the sweep's
        -- absence fact is answered "grace" -- the grace law, not this gate's.
        local row = Rows:InsertFromAura("Hunter's Mark", "Vile Poacher",
            now + 90, 90, 0, "target", 0, now - 60, TARGET_GUID)
        assertNotNil(row)
        -- The target token still names the mob: identity answers true.
        local saved = installLiveness({ target = TARGET_GUID, player = PLAYER_GUID })
        local readers, counted = installReaders(function() return false end)
        Reconcile.inCombat = false
        Reconcile.lastSweep["target"] = nil
        Reconcile:SweepUnit("target", "HARMFUL", now)
        Reconcile.inCombat = nil
        -- The sweep stamps lastSweep at its fixed test clock; a later file's
        -- gate reads GetTime() against it and a future stamp closes that gate.
        Reconcile.lastSweep["target"] = nil
        restoreReaders(readers)
        restoreLiveness(saved)
        assertEquals(1, counted.byName,
            "the confirmed pair is the answer: the row faces the sweep")
        -- The absence fact with more than MAXLAG of window left is the
        -- REMOVAL leg (the early break) -- the row rides the sweep to REMOVE.
        assertEquals(Laws.REMOVE, row.state,
            "the gate lets the sweep run the removal leg (state="
            .. tostring(row.state) .. ")")
        restoreRows()
    
    end)
    restoreRows()
    if not __ok then error(__err, 0) end
end)

test("MT-3: a guidless cast row rides on the NAME leg (the cast's target name is not the token's unit)",
function()
    local __ok, __err = pcall(function()
        enableTimer()
        buildHunterRegistry()
        quietRows()
        local now = 31000
        -- A row born of the cast spine: keyed by the target's NAME, promoted to
        -- the "target" token, carrying NO aura identity.
        local row = Rows:InsertFromCast("Hunter's Mark", "Vile Poacher", 120,
            now, now)
        assertNotNil(row)
        row.unitToken = "target"
        assertNil(row.guid)
        assertNil(row.castGuid)
        -- The self-target: the token's UnitName answers the PLAYER's name.
        local savedU, savedN = _G.UnitExists, _G.UnitName
        _G.UnitExists = function(token) return token == "target" end
        _G.UnitName = function(token) return token == "target" and "Player" end
        local savedL = installLiveness({})          -- the client gives no guids
        local readers, counted = installReaders(function() return false end)
        Reconcile.inCombat = false
        Reconcile.lastSweep["target"] = nil
        Reconcile:SweepUnit("target", "HARMFUL", now)
        Reconcile.inCombat = nil
        -- The sweep stamps lastSweep at its fixed test clock; a later file's
        -- gate reads GetTime() against it and a future stamp closes that gate.
        Reconcile.lastSweep["target"] = nil
        restoreReaders(readers)
        restoreLiveness(savedL)
        _G.UnitExists, _G.UnitName = savedU, savedN
        assertEquals(0, counted.byName,
            "the name leg answers false: UnitName('target') is not the row's key")
        assertEquals(Laws.NORMAL, row.state, "the cast row rides")
        restoreRows()
    
    end)
    restoreRows()
    if not __ok then error(__err, 0) end
end)

-- ============================================== MT-6: the bulk adoption ==

test("MT-6: the bulk sweep ADOPTS the cast row: one bar after the sweep, not the live case's two",
function()
    local __ok, __err = pcall(function()
        enableTimer()
        buildHunterRegistry()
        quietRows()
        local now = 32000
        -- The live shape: the cast spine's row for the Hunter's Mark on the mob
        -- (keyed by the target's NAME), promoted to the sweep token.
        local castRow = Rows:InsertFromCast("Hunter's Mark", "Vile Poacher", 120,
            now, now)
        assertNotNil(castRow)
        castRow.unitToken = "target"
        local n0 = Rows:Count()
        local added0 = Reconcile.counts.added
        -- The token names the mob the cast targeted: with no guid on the row
        -- (a cast row, not yet confirmed) it is the NAME leg of
        -- `tokenHoldsRowUnit` that binds row to token -- the same leg the MT-3
        -- self-target gate rides.
        local savedU, savedN = _G.UnitExists, _G.UnitName
        _G.UnitExists = function(token) return token == "target" end
        _G.UnitName = function(token) return token == "target" and "Vile Poacher" end
        local saved = installLiveness({ target = TARGET_GUID })
        local readers, counted = installReaders(nil, {
            { name = "Hunter's Mark", expirationTime = now + 80,
                duration = 80, applications = 1 },
        })
        Reconcile.inCombat = false
        local touched, added = Reconcile:SweepBulk("target", "HARMFUL PLAYER", now)
        Reconcile.inCombat = nil
        -- Measure while the seams live; the asserts run only after every
        -- seam is back in place (a mid-assert throw must not strand the
        -- counted readers / the liveness probe / the Unit stubs for the
        -- files that sort after this one).
        local c_after, added_after = Rows:Count(), Reconcile.counts.added
        local state_after, guid_after = castRow.state, castRow.guid
        local fresh = Rows:Find("Hunter's Mark", "Vile Poacher")
        local tokenRow = Rows:Find("Hunter's Mark", "target")
        restoreReaders(readers)
        restoreLiveness(saved)
        _G.UnitExists, _G.UnitName = savedU, savedN
        assertEquals(1, touched, "the bulk sweep answered the one aura")
        assertEquals(0, added, "the insert was SUPPRESSED (no 'inserted' verdict)")
        assertEquals(n0 + 1, c_after,
            "ONE VISIBLE bar after the bulk sweep (the live case was TWO "
            .. "Hunter's Mark bars). Rows:Count() is the live count: the "
            .. "OnAuraFact REFRESH arm removes the old row and re-inserts it, "
            .. "and the removed row rides the array until Rows:Sweep compacts "
            .. "it -- the rows array length is not the visible-bar count.")
        assertEquals(added0, added_after, "the add counter did not move")
        assertNil(tokenRow, "no second row keyed to the sweep token")
        -- The fact (80 s) is shorter than the cast's predicted window (120 s)
        -- by more than MAXLAG: the pair rides the refresh arm (ST-25 "the row
        -- is removed and re-inserted") -- the old row fades, the fresh row
        -- carries the pair, and the confirming read's identity stamps THAT
        -- row (the adopt arm of OnAuraFact stamps the row it adopts; the
        -- refresh arm stamps the fresh one -- (spell, target) identity law).
        assertEquals(Laws.REMOVE, state_after,
            "the old row rides the refresh fade (ST-25)")
        assertNotNil(fresh, "the (spell, target) pair keeps a riding row")
        assertTrue(fresh ~= castRow, "the refresh law re-inserted a fresh row")
        assertEquals(TARGET_GUID, fresh.guid,
            "the confirming read stamped the adoption key on the riding row")
        restoreRows()
    
    end)
    restoreRows()
    if not __ok then error(__err, 0) end
end)

test("m1: a row in the IGNORE band (the pump is mid-evicting it) is NOT the adopt target",
function()
    local __ok, __err = pcall(function()
        enableTimer()
        buildHunterRegistry()
        quietRows()
        local now = 33000
        local leaving = Rows:InsertFromCast("Hunter's Mark", "Vile Poacher", 120,
            now, now)
        assertNotNil(leaving)
        leaving.unitToken = "target"
        -- The refuse-removal / zeroing band: state < NORMAL, below the live band.
        leaving.state = Laws.IGNORE
        local expire0 = leaving.expireAt
        local n0 = Rows.rows_n
        local saved = installLiveness({ target = TARGET_GUID })
        local readers = installReaders(nil, {
            { name = "Hunter's Mark", expirationTime = now + 80,
                duration = 80, applications = 1 },
        })
        Reconcile.inCombat = false
        -- The sweep rides 0.2 s after the insert: the Rows guid stamp is gated on
        -- `now > castTime + 0.15` (the insert's own write window, Rows.lua:399).
        local touched, added = Reconcile:SweepBulk("target", "HARMFUL PLAYER",
            now + 0.2)
        Reconcile.inCombat = nil
        restoreReaders(readers)
        restoreLiveness(saved)
        assertEquals(1, touched)
        assertEquals(1, added,
            "the sweep INSERTS its own row: the evicting row is leaving the "
            .. "array and must not carry the confirmed bar (m1)")
        assertEquals(n0 + 1, Rows:Count(), "the evicting row plus the new row")
        assertEquals(expire0, leaving.expireAt,
            "the evicting row was not mutated by OnAuraFact")
        assertEquals(nil, leaving.guid, "no adoption key rode the evicting row")
        restoreRows()
    
    end)
    restoreRows()
    if not __ok then error(__err, 0) end
end)
