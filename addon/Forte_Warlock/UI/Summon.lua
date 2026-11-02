-- addon/Forte_Warlock/UI/Summon.lua
-- FX.Warlock.Summon: the Summon Assistant's channel plate — the original's
-- plate (Forte_Summon.xml:89-114, every constant cited in UI/Frame.lua): the
-- SU1 icon at the plate's left (Forte_Summon.xml:146), the active-count
-- `x<n>` next to it (the `x`..count format, Forte_Summon.lua:165), the right
-- label carrying the channel's `mm:ss` (the plate's Info slot,
-- Forte_Summon.xml:107-111), and the second line: the target at the bar's
-- left and the clock at its right (Forte_Summon.xml:14-25, the bar pair
-- geometry the Soulstone bars share, Forte_Soulstone.xml:42-51). The bar
-- rides the summoning purple, SummoningColor {0.64,0.21,0.93}
-- (Forte_Summon.lua:597), and runs FORWARD with the channel (the bar fills
-- as the cast proceeds).
--
-- All STATE lives in Core/Tools.lua's SummonTracker (the own ritual) and
-- Core/Group.lua's roster model (the raid's active rituals, bound through
-- `SetSpy`, Core/Comms.lua owning the live instance); this file is a pure
-- renderer of `:Channeling()`, `:Progress()` (the assignment's names) plus
-- the channel window (PLAN §3.4 "pure renderer").
--
-- The original's Summon Assistant was a raid chat conductor (spec §6,
-- SU-01…SU-09: the portal/summon queues, whisper traffic, the role map, the
-- "SUMMON ME" spam). docs/warlock-tools.md drops the map sampling (SU-02
-- NOT-feasible), the whisper queueing (SU-06) and the spam; the QUEUE half
-- is live since H6/F-A (2026-11-02): the `SU1 <by> <target>` / `SE1` pair
-- rides Core/Comms.lua into `Group:Queue()`, and the queue rows ride this
-- plate in the original's SU_DrawSummon layout — one row per active ritual,
-- the person being summoned as the row's name (`FWSUBar<i>Name` = `t1`,
-- Forte_Summon.lua:152-160) and the warlock running it as its right label
-- (the re-keyed priority `su[index][7] = "<"..player..">"`,
-- Forte_Summon.lua:322-340), the plate's count slot the rituals in flight
-- (`FWSUFrameAmount:SetText("x"..n)`, Forte_Summon.lua:165). The rows carry
-- NO bar fill: the wire says a ritual is running, never how far along it is
-- (the 5 s channel is the SENDER's own read, and the sender draws its own
-- row), and the original's far/all pair is the dropped distance sampling.
-- My own channel keeps the first row (the plate's second line), the queue
-- rows stack under it, the run capped at `SummonMax` (default 5,
-- Forte_Summon.lua:590).
--
-- The channel law: the plate's OWN channeling half lives only while the
-- channel does — SU-09's "the indicator retires the moment the cast ends",
-- no lingering. The queue half lives while a claim is in the model, so the
-- plate shows for the raid's rituals too (SU-03/04: a queue plate is the
-- module's whole point); an EMPTY roster and an empty queue retire it.
--
-- The target law: the tracker hands over ONE string it owns (captured at the
-- channel's first signal, from the combat-log payload,
-- docs/spell-sweep-2026-11-01.md); an unread target prints `(target unread)`.
--
-- The 10 Hz law: `Update` returns TRUE while a channel is live — a queue row
-- is not time-driven (the pair is the whole truth), so the queue alone asks
-- for no tick.
--
-- Skin/position/settings/lock/clock: the shared law in UI/Frame.lua.
-- Settings (module "Warlock"): SummonWidth (the plate width), SummonHeight
-- (the second-line bar height, the original's SummonHeight,
-- Forte_Summon.lua:587), SummonColor, SummonStrikethrough.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}

local Frame = FX.Warlock.Frame
local Summon = Frame:new({
    name = "Summon",
    dbKey = "summon",
    size = { Width = 106, Height = 20, Point = "CENTER", X = 60, Y = -240 },
    module = "Warlock",
    sharedModule = "General",
    lockKey = "Lock",
    keys = { "SummonWidth", "SummonHeight", "SummonColor",
             "SummonStrikethrough" },
    keymap = {
        SummonEnable = "SetEnabled",
        SummonWidth = "SetWidth",                -- the plate width
        SummonHeight = "SetRowHeight",           -- the bar height, :587
        SummonColor = "SetBarColor",             -- Forte_Summon.lua:597
        SummonStrikethrough = "SetStrikethrough",
    },
})
FX.Warlock.Summon = Summon

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.Warlock.SummonSkin = setmetatable({
    Width = 106, Height = 20,
    RowHeight = 12,                              -- Forte_Summon.lua:587
    IconTexture = TEX .. "SU1",                  -- Forte_Summon.xml:146
    BarColor = { 0.64, 0.21, 0.93, 1 },           -- Forte_Summon.lua:597
    TextSize = 11,                               -- Forte_Core.lua:2547
}, { __index = FX.Warlock.FrameSkin })
Summon.skin = FX.Warlock.SummonSkin
Summon.sizeDefaults = { Width = 106, Height = 20, Point = "CENTER",
                        X = 60, Y = -240 }

-- ----------------------------------------------------------------- the art --

function Summon:SizeChangedHook()
    self:SetFillFraction(self._fillFrac or 0)
end

-- ----------------------------------------------------------------- the spy --

--- The queue's row cap: the original's `SummonMax` (default 5,
--- Forte_Summon.lua:590) — the plate grows by whole row steps and stops
--- there.
Summon.MAX_ROWS = 5

--- The warlock label of a queue row: the original's re-keyed priority,
--- `su[index][7] = "<"..player..">"` (Forte_Summon.lua:322-340, drawn as
--- `FWSUBar<i>Info` at :154).
function Summon:FormatWarlock(by)
    return "<" .. tostring(by) .. ">"
end

--- The Group model seam (a Core/Group.lua instance; Core/Comms.lua owns the
--- live one, UI/Module.lua's `_InitViews` binds it, tests inject their own —
--- the Healthstone `SetSpy` convention).
function Summon:SetSpy(group)
    self.Spy = group
    self._count, self._frac, self._timeKey, self._target = nil, nil, nil, nil
end

--- The summon queue (SU-03/04): one row per active ritual of the raid,
--- `Group:Queue(max)` — the claims sorted by warlock name, so the draw
--- order is deterministic (the original sorts by class/distance/name,
--- Forte_Summon.lua:27, and the distance half is SU-02 NOT-feasible). The
--- target is the row's name (`Name` = `t1`, Forte_Summon.lua:152-160), the
--- warlock its right label, and the bar carries no fill (the header law).
function Summon:RenderQueueRows(rows)
    local n = 0
    for i, row in ipairs(rows or {}) do
        local e = self:ExtraRow(i)
        if e then
            self:SetExtraRowText(e, row.target,
                self:FormatWarlock(row.warlock))
            self:SetExtraRowFraction(e, 0)
            n = i
        end
    end
    self:SetExtraRowsShown(n)
end

-- ------------------------------------------------------------------ update --

--- One render pass; TRUE while MY channel is live (a queue row is not
--- time-driven).
function Summon:Update(_now)
    local t = self.Tracker
    local live, frac, remaining = false, 0
    if t and self:Enabled() and t:Channeling() then
        -- Progress is the pair (fraction 0..1, remaining seconds).
        local f, r = t:Progress()
        if type(f) == "number" then
            live = true
            frac = f
            if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
            remaining = r
        end
    end
    -- The queue half (F-A): the raid's active rituals, from the Core/Group
    -- model the SU1/SE1 pair feeds. Claims are a claim of their own; an
    -- empty queue with no channel is none.
    local rows
    local spy = self.Spy
    if spy and self:Enabled() then rows = spy:Queue(self.MAX_ROWS) end
    local queued = rows and #rows or 0
    local show = live or queued > 0
    self:SetShown(show)
    if not show then
        self:SetExtraRowsShown(0)
        return false
    end
    -- The plate's own channeling row keeps the first row (the plate's
    -- second line); it lives exactly as long as the channel (SU-09).
    self:SetRowShown(live)
    if live then
        if frac ~= self._frac then
            self._frac = frac
            self:SetFillFraction(frac)
        end
        local who = Frame.FormatTarget(t:Snapshot().target)
        if who ~= self._target then
            self._target = who
            self.nameFS:SetText(who)
        end
    end
    -- The count: the rituals in flight — the queue's plus my own
    -- (the plate's count slot, Forte_Summon.lua:165).
    local amount = "x" .. (queued + (live and 1 or 0))
    if amount ~= self._count then
        self._count = amount
        self.amountFS:SetText(amount)
    end
    -- The clocks: the channel's mm:ss at the bar's right and in the plate's
    -- Info slot (Forte_Summon.xml:107-111); no channel, no clock (the
    -- original's far/all pair is the dropped distance sampling).
    local key = live and Frame.ClockKey(remaining) or -1
    if key ~= self._timeKey then
        self._timeKey = key
        local clock = live and Frame.FormatClock(remaining) or ""
        self.timeFS:SetText(clock)
        self.infoFS:SetText(clock)
    end
    self:RenderQueueRows(rows)
    self:ApplyTextVisibility()
    return live
end

function Summon:RenderIdle()
    self._frac, self._timeKey, self._target = nil, nil, nil
    self._count = nil
    self:SetExtraRowsShown(0)
    self:SetRowShown(false)
    self:SetShown(false)
    self.amountFS:SetText("")
    self.infoFS:SetText("")
    self.nameFS:SetText("")
    self.timeFS:SetText("")
end

--- The injected-tracker seam (tests, launch-day probes).
function Summon:SetTracker(tracker)
    self.Tracker = tracker
    self._frac, self._timeKey, self._target = nil, nil, nil
    self._count = nil
end

function Summon:StatusLine()
    local t = self.Tracker
    local live = t and t:Channeling()
    local remaining = live and (select(2, t:Progress()))
    local queue = 0
    if self.Spy then queue = self.Spy:QueueCount() end
    return string.format("Summon Assistant: %s%s | queue %d | %dx%d | %s",
        live and "channel" or "idle",
        live and (" " .. Frame.FormatClock(remaining)) or "",
        queue,
        self.skin.Width, self.skin.Height,
        self:Enabled() and "on" or "off")
end
