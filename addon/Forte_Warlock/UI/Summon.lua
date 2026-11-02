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
-- All STATE lives in Core/Tools.lua's SummonTracker; this file is a pure
-- renderer of `:Channeling()`, `:Progress()` (the assignment's names) plus
-- the channel window (PLAN §3.4 "pure renderer").
--
-- The original's Summon Assistant was a raid chat conductor (spec §6,
-- SU-01…SU-09: the portal/summon queues, whisper traffic, the role map, the
-- "SUMMON ME" spam). docs/warlock-tools.md deliberately drops ALL of it: the
-- v1 keeps the state machine — the channel, the target, the success and the
-- cancel — and the one widget that state machine needs: the channel plate.
-- Nothing is announced, nothing is queued.
--
-- The channel law: the plate lives only while the channel does — SU-09's
-- "the indicator retires the moment the cast ends", no lingering. Unlike the
-- Soulstone plate (a standing readout), the original's Summon frame rides
-- the live summons (`SU_DrawSummon` prints counts of CURRENT summoners,
-- Forte_Summon.lua:156-166), and an idle Summon plate would claim a ritual
-- that is not running: no channel, no plate.
--
-- The target law: the tracker hands over ONE string it owns (captured at the
-- channel's first signal, from the combat-log payload,
-- docs/spell-sweep-2026-11-01.md); an unread target prints `(target unread)`.
--
-- The 10 Hz law: `Update` returns TRUE while a channel is live.
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

-- ------------------------------------------------------------------ update --

--- One render pass; TRUE while a channel is live.
function Summon:Update(now)
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
    self:SetShown(live)
    if not live then return false end
    self:SetRowShown(true)
    if frac ~= self._frac then
        self._frac = frac
        self:SetFillFraction(frac)
    end
    -- The count: one ritual channeling (the plate's count slot,
    -- Forte_Summon.lua:165).
    if self.amountFS:GetText() ~= "x1" then
        self.amountFS:SetText("x1")
    end
    local key = Frame.ClockKey(remaining)
    if key ~= self._timeKey then
        self._timeKey = key
        local clock = Frame.FormatClock(remaining)
        self.timeFS:SetText(clock)
        self.infoFS:SetText(clock)               -- the plate's Info slot,
    end                                          -- Forte_Summon.xml:107-111
    local who = Frame.FormatTarget(t:Snapshot().target)
    if who ~= self._target then
        self._target = who
        self.nameFS:SetText(who)
    end
    self:ApplyTextVisibility()
    return true
end

function Summon:RenderIdle()
    self._frac, self._timeKey, self._target = nil, nil, nil
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
end

function Summon:StatusLine()
    local t = self.Tracker
    local live = t and t:Channeling()
    local remaining = live and (select(2, t:Progress()))
    return string.format("Summon Assistant: %s%s | %dx%d | %s",
        live and "channel" or "idle",
        live and (" " .. Frame.FormatClock(remaining)) or "",
        self.skin.Width, self.skin.Height,
        self:Enabled() and "on" or "off")
end
