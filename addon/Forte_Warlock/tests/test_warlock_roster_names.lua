-- addon/Forte_Warlock/tests/test_warlock_roster_names.lua
-- FX8 (PLAN §11.2 "Fix FX8", 2026-11-04): the roster scan of
-- `Forte_Warlock/Core/Comms.lua` named a groupmate with `UnitName(unit)`'s
-- FIRST return alone. The uiforever identity probe (PLAN §9 rows of
-- 2026-11-04) measured what that is on Forever: `UnitName("player")` answers
-- `("Morvessa", "Ashveil")` — the SECOND return is the SURNAME, part of the
-- character — `UnitFullName("player")` answers `("Morvessa Ashveil",
-- "Nethergarde")`, `UnitNameUnmodified("player")` answers `"Morvessa"`, and a
-- `CHAT_MSG_ADDON` sender reads `"Morvessa Ashveil-Nethergarde"`. So the scan
-- keyed the groupmate `morvessa` while her own comms lines keyed her
-- `morvessaashveil`, and Core/Group.lua's canonical key — the very thing that
-- folds the spellings (its header's spelling law) — had nothing to fold:
-- `SetRoster`'s keep-set carried `morvessa`, the inbound line created
-- `morvessaashveil`, and the DeleteOld sweep could never see the twin. Every
-- Warlock plate that rides comms (the Healthstone Spy's active/stones/missing
-- counts, the Shard Spy's rows, the summon queue's warlock column) showed the
-- SAME player twice the moment comms were on.
--
-- The fix is `FX.Identity.NameOf(unit)` (Core/Identity.lua): the same
-- fullest-plain-name law `SelfName` runs for "player", for any token. These
-- tests drive the shape the shipped client presents — the REAL
-- `GetNumGroupMembers`/`IsInRaid` globals and the `rosterScan` seam NIL — and
-- deliver the peer's line through the comms frame's own `OnEvent` script, the
-- catalog payload order (prefix, text, channel, sender) of
-- ChatInfoDocumentation.lua:800.
--
-- THE STATE LEDGER — this file is a guest in a suite that shares one module.
-- Delivering a line through the real handler is NOT a read-only act: it runs
-- `KickViews`, and the Healthstone plate's `SetIconForCount` swaps the icon's
-- art off the built module art the moment the plate renders a count
-- (UI/Healthstone.lua:191-201) — an art the later `test_warlock_ui.lua`
-- icon-law test asserts as the built one, so a leaked render fails it. The
-- scan plus `SetRoster` also leaves members and summon entries on the live
-- model. EVERYTHING this file moves is therefore snapshotted before a body
-- and restored after it, in a cleanup that runs on the failure path too: the
-- body runs under pcall, the restore runs unconditionally, the failure is
-- re-raised after. The ledger: the comms module's whole mutable surface
-- (readers, rate stamps, outbox and its pumps, prefixState, the event frame
-- and its enabled flag, the counters, the live Group with its members and
-- summons), the four plates' icon art/texture/visibility and their injected
-- Tracker/Spy references, and every game global stubbed.
--

local FX = ForteXorcist
local WK = FX.Warlock
local C = FX.Warlock.Comms

-- ------------------------------------------------------------------ ledger --

--- The comms module's mutable surface, by value where a table is handed out
--- by reference (the Group's member table, the outbox array).
local function snapshotComms()
    local s = {
        readers = C.readers,
        _lastAt = C._lastAt, _lastSent = C._lastSent,
        _lastTarget = C._lastTarget,
        outbox = C.outbox,
        _throttleStrikes = C._throttleStrikes,
        _pausedUntil = C._pausedUntil,
        _pumpArmed = C._pumpArmed,
        _stopped = C._stopped,
        prefixState = C.prefixState,
        group = C.group,
        eventsEnabled = C._eventsEnabled,
        eventFrame = C._eventFrame,
    }
    local counts = {}
    for k, v in pairs(C.counts) do counts[k] = v end
    s.counts = counts
    if type(C.group) == "table" then
        s.members = C.group.members
        s.summons = C.group.summons
    end
    return s
end

local function restoreComms(s)
    if C._eventsEnabled then pcall(C.DisableEvents, C) end
    C.readers = s.readers
    C._lastAt = s._lastAt
    C._lastSent = s._lastSent
    C._lastTarget = s._lastTarget
    C.outbox = s.outbox
    C._throttleStrikes = s._throttleStrikes
    C._pausedUntil = s._pausedUntil
    C._pumpArmed = s._pumpArmed
    C._stopped = s._stopped
    C.prefixState = s.prefixState
    C.group = s.group
    if s.group and s.members then
        s.group.members = s.members
        s.group.summons = s.summons
    end
    if type(C.counts) == "table" then
        for k in pairs(C.counts) do C.counts[k] = s.counts[k] end
    end
    -- A suite that found the comms enabled is left finding them enabled.
    if s.eventsEnabled and not C._eventsEnabled then
        pcall(C.EnableEvents, C)
    end
end

--- The four plates: the icon art a render can swap, the drawn visibility, and
--- the injected objects a Kick reads through.
local PLATE_NAMES = { "Shards", "Soulstone", "Healthstone", "Summon" }

local function snapshotPlates()
    local out = {}
    local w = FX.Warlock
    if type(w) ~= "table" then return out end
    for _, name in ipairs(PLATE_NAMES) do
        local v = w[name]
        if type(v) == "table" then
            local row = { view = v, name = name,
                tracker = v.Tracker, spy = v.Spy, icon = v.icon,
                iconArt = v._iconArt }
            if v.icon then
                row.texture = v.icon:GetTexture()
                row.shown = v.icon:IsShown()
                row.artParent = v.icon:GetParent()
            end
            out[#out + 1] = row
        end
    end
    return out
end

local function restorePlates(rows)
    for _, row in ipairs(rows) do
        local v = row.view
        v.Tracker = row.tracker
        v.Spy = row.spy
        v._iconArt = row.iconArt
        if row.icon then
            if row.artParent and row.icon:GetParent() ~= row.artParent then
                pcall(row.icon.SetParent, row.icon, row.artParent)
            end
            if row.texture ~= nil then
                pcall(row.icon.SetTexture, row.icon, row.texture)
            end
            if row.shown == true then
                pcall(row.icon.Show, row.icon)
            elseif row.shown == false then
                pcall(row.icon.Hide, row.icon)
            end
        end
    end
end

--- A party of two spelled the way the live client spells it: `UnitName`
--- answers (first, SURNAME), `UnitFullName` the joined name plus the
--- connection label, `UnitNameUnmodified` the bare first name.
local PARTY = {
    party1 = { first = "Aria", sur = "Dawnsong", full = "Aria Dawnsong",
        class = "WARLOCK" },
    party2 = { first = "Bob", sur = "Firespark", full = "Bob Firespark",
        class = "WARRIOR" },
}

local globalsName = {
    "IsInRaid", "GetNumGroupMembers", "UnitName", "UnitClass",
    "UnitFullName", "UnitNameUnmodified",
}

local function useRealParty()
    local saved = {}
    for _, n in ipairs(globalsName) do saved[n] = _G[n] end
    _G.IsInRaid = function() return false end
    _G.GetNumGroupMembers = function() return 2 end
    _G.UnitName = function(unit)
        local n = PARTY[unit]
        if not n then return nil end
        return n.first, n.sur
    end
    _G.UnitFullName = function(unit)
        local n = PARTY[unit]
        if not n then return nil end
        return n.full, "Nethergarde"
    end
    _G.UnitNameUnmodified = function(unit)
        local n = PARTY[unit]
        if not n then return nil end
        return n.first
    end
    _G.UnitClass = function(unit)
        local n = PARTY[unit]
        if not n then return nil end
        return n.class, n.class
    end
    return saved
end

local function restoreGlobals(saved)
    if type(saved) ~= "table" then return end
    for _, n in ipairs(globalsName) do _G[n] = saved[n] end
end

--- One body, and the whole ledger back — on the passing path and on the
--- failing one alike: the body runs under pcall, the restore runs
--- unconditionally, the failure is re-raised last.
local function guarded(body)
    local savedGlobals = useRealParty()
    local savedComms = snapshotComms()
    local savedPlates = snapshotPlates()
    local ok, err = pcall(body)
    restoreGlobals(savedGlobals)
    restoreComms(savedComms)
    restorePlates(savedPlates)
    if not ok then error(err, 0) end
end

--- Every member row of one canonical identity: the row count the plates draw.
local function rowsFor(g, name)
    local key = FX.Identity.Canonical(name)
    local hits, names = 0, {}
    for k, m in pairs(g.members) do
        if k == key then
            hits = hits + 1
            names[#names + 1] = tostring(m.name)
        end
    end
    return hits, key, table.concat(names, " | ")
end

-- ------------------------------------------------------------ the scan read --

test("FX8: the roster scan names a groupmate with her FULL name (UnitName's "
.. "first return alone is `Aria`; her comms lines say `Aria Dawnsong`)",
function()
    guarded(function()
        assertEquals(nil, C.readers.rosterScan,
            "no seam: this is the read the shipped client walks")
        local rows = C:ScanRoster()
        assertNotNil(rows, "the scan walked the party tokens")
        assertEquals(2, #rows)
        assertEquals("Aria Dawnsong", rows[1].name,
            "the name must carry the surname, or the comms key never folds")
        assertEquals("Bob Firespark", rows[2].name)
        assertEquals("WARLOCK", rows[1].class, "the class half rides unchanged")
    end)
end)

-- ------------------------------------------- one player, one row, end to end --

test("FX8: the scan's row and the sender's line fold into EXACTLY ONE row for "
.. "Aria (the split showed her twice on every Warlock plate)", function()
    guarded(function()
        C.readers.selfName = function() return "Me" end
        local g = C.group
        local rows = C:ScanRoster()
        assertNotNil(rows)
        g:SetRoster(rows)
        assertEquals(2, g:ActiveCount(), "the party's two members")

        -- Her own line, delivered through the comms frame's OnEvent script.
        C:EnableEvents()
        local frame = C._eventFrame
        assertNotNil(frame, "the comms frame exists once enabled")
        local handler = frame:GetScript("OnEvent")
        assertEquals("function", type(handler))
        handler(frame, "CHAT_MSG_ADDON", "FXWK", "HS1 4", "party",
            "Aria Dawnsong-Nethergarde")
        C:DisableEvents()

        local ariaKey = FX.Identity.Canonical("Aria Dawnsong")
        local ariaShort = FX.Identity.Canonical("Aria")
        local split = 0
        for key in pairs(g.members) do
            if key == ariaKey or key == ariaShort then split = split + 1 end
        end
        assertEquals(1, split,
            "one row for Aria, not a scan row AND a sender row")
        local hits, _, spelled = rowsFor(g, "Aria Dawnsong")
        assertEquals(1, hits,
            "exactly one row carries her full name: " .. spelled)
        assertEquals(2, g:ActiveCount(),
            "the sender added no twin to the spy's denominator")

        -- The fold is not a coincidence of the key: the row is ONE row with
        -- BOTH halves on it — the scan's class/presence and her count.
        local m = g.members[ariaKey]
        assertNotNil(m, "her row is keyed by the full name")
        assertEquals(4, m.hs, "her comms count landed on the scan's row")
        assertEquals("WARLOCK", m.class, "and the scan's class rode it")
        assertEquals(true, m.addon, "the sender marked HER row")
        assertEquals(true, m.present)

        -- The next scan keeps her: the DeleteOld sweep sees the one key.
        g:SetRoster(C:ScanRoster())
        assertEquals(2, g:ActiveCount(), "a re-scan adds no twin")
        local m2 = g.members[ariaKey]
        assertNotNil(m2, "she survived the sweep")
        assertEquals(4, m2.hs, "her count rode the sweep")

        -- The plate maths is the reason the row count matters: one warlock,
        -- not a warlock and a phantom.
        local sum = g:HealthstoneSummary()
        assertNotNil(sum)
        assertEquals(1, sum.active, "Aria counted once as an addon member")
        assertEquals(1, sum.stones, "one stone carrier")
    end)
end)
