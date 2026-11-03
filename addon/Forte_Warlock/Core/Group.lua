-- addon/Forte_Warlock/Core/Group.lua
-- FX.Warlock.NewGroup: the group-side STATE model of the H6 trio — the
-- Healthstone Spy roster, the Shard Spy roster and the Summon queue — as a
-- pure, headless object: no frames, no events, no chat. The transport (the
-- C_ChatInfo comms, the legality gate, the rate limits) is Core/Comms.lua;
-- the plates are UI/Healthstone.lua, UI/Shards.lua, UI/Summon.lua. The model
-- answers "what does the raid know" from three inputs only: a roster scan
-- (`:SetRoster`), a decoded count message (`:SetCount`) and a decoded summon
-- phase (`:SummonStart` / `:SummonEnd`).
--
-- THE ORIGINAL LAW (each row cited; the comms vocabulary is the original's,
-- the state layout is the original's, the geometry lives in the UI files):
--   * roster bookkeeping: `FX.Saved.RaidStatus[name] =
--     {flag, lastUpdate, class, hasAddonString}` — a member counts as
--     "online and has fx" only while the 4th slot carries a string
--     (Forte_Healthstone.lua:186 `data[4] and type(data[4])=="string"`),
--     and the spy counts active/missing/unknown off that
--     (Forte_Healthstone.lua:176-203 `HS_ProcessHealthstone`);
--   * the version message marks "this player runs the addon"
--     (Forte_Core.lua:2444-2452 SEND_VERSION handler → `RaidStatus[f][4]`),
--     here: any inbound FXWK message marks the sender (`:MarkAddon`, the
--     CA-24 protocol row, docs/reference-functional-spec.md);
--   * the healthstone summary: `stones` = active members whose reported
--     count > 0, `missing` = active - stones, `unknown` = active members
--     with no reported data (Forte_Healthstone.lua:181-200);
--   * the shard half is the REMOVED Shard Spy's surviving comms vocabulary:
--     `FW.GET_SHARDS = "SG"` / `FW.SEND_SHARDS = "SH"`
--     (Forte_Core.lua:706, :709; the module removal is FE-35:
--     `FX_Saved.Shards = nil; -- module removed`, Forte_Core.lua:1531 —
--     "the removed module has no reference law"), so the shard rows are the
--     roster's own count column and nothing more;
--   * the summon queue: `ActiveSummons[warlock] = targetName`; a start
--     re-keys the target's row to the SUMMON priority labelled
--     "<warlock>" (`su[index][7] = "<"..player..">"`,
--     Forte_Summon.lua:322-340 `SU_SummonCastStart`); an end/cancel clears
--     the sender's entry, and a target claimed by ANOTHER warlock stays
--     claimed (Forte_Summon.lua:342-399 `SU_SummonCastCancel`/
--     `SU_SummonCastEnd`, the ActiveSummons sweep spec SU-07).
--
-- Names on this model: the KEY of a member row / a summon entry is the
-- FX.Identity canonical form of the player name (docs/research/upstream-
-- api-2026-11-03.md §2: the CHAT_MSG_ADDON sender, the roster-scan UnitName
-- and the wire carry the same player in different spellings — raw string
-- identity across those three sources is the retired assumption; the
-- canonical key is what makes `:SetRoster`'s drop-sweep keep a peer's row
-- when the two spellings differ). The row keeps the raw spelling the game
-- last handed us (`m.name`, the summon entry's `.by`) and every row the UI
-- draws carries THAT. The incoming name values are PLAIN strings (the
-- CHAT_MSG_ADDON `sender` field is a plain cstring,
-- ChatInfoDocumentation.lua:800 — no secrecy annotation on it) classified
-- through FX.Compat.PlainOrNil at the door; a name that is not a string,
-- is secret, or does not classify is refused. Counts are integers >= 0
-- (the wire format itself is Comms' decode contract); a negative/typed
-- junk value is refused, never stored.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}
local WK = FX.Warlock

local Group = {}
Group.__index = Group

--- The count fields the spies track. Each is nil = "never reported" (the
--- original's missing `FX.Saved.Healthstone[name]` slot).
Group.COUNT_FIELDS = { hs = true, shards = true }

function WK.NewGroup(opts)
    opts = opts or {}
    return setmetatable({
        now = opts.now,                       -- injectable clock
        members = {},                         -- name -> member row
        summons = {},                         -- warlock name -> { target, at }
    }, Group)
end

function Group:Clock()
    if self.now then return self.now() end
    return GetTime()
end

local function plainName(v)
    if FX.Compat and FX.Compat.PlainOrNil then v = FX.Compat.PlainOrNil(v) end
    if type(v) ~= "string" or v == "" then return nil end
    return v
end

--- The model key of a (plain, already-classified) name: the FX.Identity
--- canonical form — nil on a name that does not classify (secret, empty
--- of name parts). See the header's spelling law.
local function keyOf(plain)
    if not plain then return nil end
    return FX.Identity.Canonical(plain)
end

--- The DISPLAY spelling of a name: the raw notation the game handed for
--- that identity, first one wins (FX.Identity.Remember/Raw) — a roster
--- scan's "Aria Dawnsong" is not clobbered by a wire sender's joined
--- "AriaDawnsong", and every row the UI draws rides one stable spelling.
local function display(plain, key)
    FX.Identity.Remember(plain)
    return FX.Identity.Raw(key) or plain
end

-- ------------------------------------------------------------------ roster --

--- A member row; `present` = online, `alive` = not dead/ghost, `addon` =
--- "has answered an FXWK message" (the RaidStatus[4] slot), the counts nil
--- until reported.
local function newMember(name)
    return {
        name = name, class = nil,
        present = true, alive = true,
        addon = false,
        hs = nil, shards = nil,
    }
end

--- Get an existing member, creating the row on demand: an inbound count
--- from a name the roster scan has not listed yet is kept (the original's
--- `fx2temp` queue, Forte_Core.lua:2449 — "remember it until the next scan"
--- by the same right), and the next `:SetRoster` folds it in. Keyed by the
--- canonical form; the row's `.name` rides the identity layer's remembered
--- spelling of the player.
function Group:Member(name)
    local raw = plainName(name)
    local key = keyOf(raw)
    if not key then return nil end
    local m = self.members[key]
    if not m then
        m = newMember(display(raw, key))
        m.present = false          -- not on a scan yet: claimed, not seen
        self.members[key] = m
    else
        m.name = display(raw, key) -- the remembered spelling, not this one
    end
    return m
end

--- `rows` = array of { name, class, present, alive } from one roster scan
--- (Core/Comms.lua's ScanRoster). Members absent from the scan are DROPPED
--- together with their summon entries (the original's DeleteOld sweep,
--- Forte_Core.lua:985-990, at scan cadence); a known count rides the row when
--- the same name returns — matched by the CANONICAL key, so a scan spelling
--- ("Aria Dawnsong" from UnitName) and a sender spelling ("AriaDawnsong"
--- from the wire) fold into the ONE row instead of deleting each other's
--- state (the header's spelling law). Returns the new member count.
function Group:SetRoster(rows)
    if type(rows) ~= "table" then return self:ActiveCount() end
    local keep = {}
    for _, row in ipairs(rows) do
        local raw = plainName(row.name)
        local key = keyOf(raw)
        if key then
            keep[key] = true
            local m = self.members[key]
            if not m then
                m = newMember(display(raw, key))
                -- Presence defaults PRESENT (the original's AddMember law,
                -- Forte_Core.lua:1866 -- only a CONFIRMED death/disconnect is
                -- an absence; an unknown answer is presence).
            end
            m.name = display(raw, key)
            if type(row.class) == "string" then m.class = row.class end
            m.present = (row.present ~= false)
            m.alive = (row.alive ~= false)
            self.members[key] = m
        end
    end
    for key in pairs(self.members) do
        if not keep[key] then
            self.members[key] = nil
            self.summons[key] = nil
        end
    end
    return self:ActiveCount()
end

--- Mark "this sender runs ForteXorcist" (the RaidStatus[4] slot's job).
function Group:MarkAddon(name)
    local m = self:Member(name)
    if not m then return nil end
    m.addon = true
    return m
end

--- Store a decoded count. Returns true when the member + field + value all
--- passed the guards, false on junk (a junk message never mutates state).
function Group:SetCount(name, field, value)
    if not self.COUNT_FIELDS[field] then return false end
    if type(value) ~= "number" or value < 0
        or math.floor(value) ~= value then return false end
    local m = self:Member(name)
    if not m then return false end
    m[field] = value
    m.addon = true
    return true
end

--- Members a scan has currently listed (the spy denominators).
function Group:ActiveCount()
    local n = 0
    for _, m in pairs(self.members) do
        if m.present then n = n + 1 end
    end
    return n
end

--- Forget everything (leaving the group: the original drops the raid panel
--- with the group, `STATES.GROUPED` gates of Forte_Healthstone.lua:13 and
--- Forte_Summon.lua:51).
function Group:Clear()
    self.members = {}
    self.summons = {}
end

-- ---------------------------------------------------------- spy summaries --

--- The Healthstone Spy's three counters, the HS_ProcessHealthstone maths
--- (Forte_Healthstone.lua:176-203): `active` = online+alive members the addon
--- is confirmed on, `stones` = of those, the ones with a stone, `missing` =
--- active - stones, `unknown` = online+alive members with NO addon
--- confirmation (the original's `NO_INFO` bar, shown while
--- `HealthstoneUnknown`, Forte_Healthstone.lua:200-202).
function Group:HealthstoneSummary()
    -- An empty roster is NO summary (nil, not a zero-row): a plate whose
    -- spy has never heard a roster answers with the own-state law alone.
    if next(self.members) == nil then return nil end
    local active, stones, unknown = 0, 0, 0
    for _, m in pairs(self.members) do
        if m.present and m.alive then
            if m.addon then
                active = active + 1
                if type(m.hs) == "number" and m.hs > 0 then
                    stones = stones + 1
                end
            else
                unknown = unknown + 1
            end
        end
    end
    return {
        active = active,
        stones = stones,
        missing = active - stones,
        unknown = unknown,
    }
end

--- The Shard Spy's rows: one per WARLOCK-class member the scan saw, each
--- carrying its reported shard count (`nil` = not reported). The class
--- filter is the original's `FW:IsWarlock` role gate (Forte_Summon.lua:241
--- uses it for the queue priority; the Shard Spy module itself is FE-35
--- removed, so the row set is the roster's own warlock column). Sorted by
--- name (the spelling the game gave), capped at `max`.
function Group:ShardRows(max)
    local rows = {}
    for key, m in pairs(self.members) do
        if m.class == "WARLOCK" and m.present then
            rows[#rows + 1] = { name = m.name or key, shards = m.shards }
        end
    end
    table.sort(rows, function(a, b) return a.name < b.name end)
    if type(max) == "number" and max >= 0 and #rows > max then
        for i = #rows, max + 1, -1 do rows[i] = nil end
    end
    return rows
end

--- The shard total over the warlocks that reported it (the Shard Spy's only
--- number: how much reagent the raid's warlocks carry).
function Group:ShardTotal()
    local total, known, warlocks = 0, 0, 0
    for _, row in ipairs(self:ShardRows()) do
        warlocks = warlocks + 1
        if type(row.shards) == "number" then
            known = known + 1
            total = total + row.shards
        end
    end
    return { total = total, known = known, warlocks = warlocks }
end

-- --------------------------------------------------------------- queue -----

--- "Warlock <by> started summoning <target>" (the SU_CAST_START half,
--- Forte_Summon.lua:517-522 → `SU_SummonCastStart`, :322-340). The sender is
--- always the warlock the message is about (Comms enforces sender == by);
--- a re-entry REPLACES the target (the original's `player == from` branch
--- re-keys the same warlock's row, Forte_Summon.lua:326-329). Returns the
--- previous target when a replace happened, the new one otherwise.
function Group:SummonStart(by, target)
    by, target = plainName(by), plainName(target)
    local key = keyOf(by)
    if not key or not target then return nil end
    local prev = self.summons[key]
    self.summons[key] = { target = target, at = self:Clock(), by = by }
    return prev and prev.target or target
end

--- "Warlock <by> stopped summoning <target>" (SU_CAST_CANCEL / SU_CAST_END,
--- Forte_Summon.lua:523-533 → `SU_SummonCastCancel`/`SU_SummonCastEnd`,
--- :342-399). The sender's entry is cleared; a target another warlock still
--- lists STAYS listed (the ActiveSummons sweep, SU-07), which this data shape
--- gives for free: entries are keyed by warlock, and clearing one warlock's
--- entry never touches another's. `target` nil = "whatever it was".
function Group:SummonEnd(by, target)
    by = plainName(by)
    local key = keyOf(by)
    if not key then return nil end
    local entry = self.summons[key]
    if not entry then return nil end
    if target ~= nil and plainName(target) ~= entry.target then
        return nil                       -- a late end for an old cast
    end
    self.summons[key] = nil
    return entry.target
end

--- The queue rows for the plate: { warlock, target }, sorted by warlock name
--- (a deterministic draw order; the original sorts by class/distance/name,
--- Forte_Summon.lua:27, and distance sampling is SU-02 NOT-feasible). Capped
--- by `max` (the original's `SummonMax`, default 5, Forte_Summon.lua:590).
function Group:Queue(max)
    local rows = {}
    for key, entry in pairs(self.summons) do
        rows[#rows + 1] = { warlock = entry.by or key, target = entry.target }
    end
    table.sort(rows, function(a, b) return a.warlock < b.warlock end)
    if type(max) == "number" and max >= 0 and #rows > max then
        for i = #rows, max + 1, -1 do rows[i] = nil end
    end
    return rows
end

function Group:QueueCount()
    local n = 0
    for _ in pairs(self.summons) do n = n + 1 end
    return n
end
