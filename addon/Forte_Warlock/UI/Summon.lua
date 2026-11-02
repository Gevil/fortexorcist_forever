-- addon/Forte_Warlock/UI/Summon.lua
-- FX.Warlock.Summon: the Summon Assistant's channel indicator. One
-- Classic-skinned bar that fills while the SUMMONING channel runs and retires
-- when it ends. All STATE lives in Core/Tools.lua's SummonTracker; this file
-- is a pure renderer of `:Channeling()`, `:Target()`, `:Progress()` (the
-- assignment's names) plus the channel window (PLAN §3.4 "pure renderer").
--
-- The original's Summon Assistant was a raid chat conductor (spec §6,
-- SU-01…SU-09: the portal/summon queues, whisper traffic, the role map, the
-- "SUMMON ME" spam). docs/warlock-tools.md deliberately drops ALL of it: the
-- v1 keeps the state machine — the channel, the target, the success and the
-- cancel — and the one widget that state machine needs: the short channel
-- indicator. Nothing is announced, nothing is queued.
--
-- The channel law (the 2012 baseline's `Forte_Summon` geometry, the
-- 140x12 bar with the label above it and the summoning-purple fill,
-- /tmp/fxref/Forte_Summon/Forte_Summon.lua:11-21): the fill runs FORWARD with
-- the channel (the bar fills as the cast proceeds, the way the original's
-- `SummoningTime` bar does), the label reads `Summoning <target> mm:ss` with
-- the seconds running out, and the bar lives only while the channel does —
-- SU-09's "the indicator retires the moment the cast ends", no lingering.
--
-- The target law: the tracker hands over ONE string it owns (captured at the
-- channel's first signal, from the combat-log payload,
-- docs/spell-sweep-2026-11-01.md); an unread target prints `(target unread)`.
--
-- The 10 Hz law: `Update` returns TRUE while a channel is live.
--
-- Skin/position/settings/lock/clock: the shared law in UI/Frame.lua.
-- Settings (module "Warlock"): SummonWidth/Height/Color/Strikethrough.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}

local Frame = FX.Warlock.Frame
local Summon = Frame:new({
    name = "Summon",
    dbKey = "summon",
    size = { Width = 140, Height = 12, Point = "CENTER", X = 60, Y = -240 },
    module = "Warlock",
    sharedModule = "General",
    lockKey = "Lock",
    keys = { "SummonWidth", "SummonHeight", "SummonColor",
             "SummonStrikethrough" },
    keymap = {
        SummonEnable = "SetEnabled",
        SummonWidth = "SetWidth",
        SummonHeight = "SetHeight",
        SummonColor = "SetBarColor",
        SummonStrikethrough = "SetStrikethrough",
    },
})
FX.Warlock.Summon = Summon

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.Warlock.SummonSkin = setmetatable({
    Width = 140, Height = 12,
    Inset = 3,
    EdgeTexture = TEX .. "Aluminium",       -- the bar's frame art
    FillTexture = TEX .. "Smooth.tga",      -- the vendored smooth fill
    BarColor = { 0.64, 0.21, 0.93, 1 },   -- the summoning category tint
    TextOffset = 11,
    TextSize = 11,
}, { __index = FX.Warlock.FrameSkin })
Summon.skin = FX.Warlock.SummonSkin
Summon.sizeDefaults = { Width = 140, Height = 12, Point = "CENTER",
                        X = 60, Y = -240 }
Summon.TEXT_DY = 11

function Summon:_NewBar()
    local h = self.skin.Height - 2 * self.skin.Inset
    self.barHeight = h
    local bar = self:_NewPlate(self.skin.Width, self.skin.Height,
        self.skin.Inset, self.skin.BgColor)
    self.plate:Hide()
    return bar
end

--- The fill runs forward with the channel, left-anchored inside the bar.
function Summon:_NewFillBar()
    local c = self.skin.BarColor
    self.fillBarColor = c
    self.fill = self.anchor:CreateTexture()
    self.fill:SetTexture(self.skin.FillTexture or (TEX .. "Aluminium"))
    self.fill:SetPoint("LEFT", self.bar, "LEFT", 0, 0)
    self.fill:SetSize(0, self.barHeight)
    self.fill:SetDrawLayer("OVERLAY")
    self.fill:SetVertexColor(c[1], c[2], c[3], c[4])
end

function Summon:_Build()
    Frame._Build(self)
    if self.icon or self.fill then return end
    self:_NewFillBar()
end

function Summon:SizeChangedHook()
    self:SetFillFraction(self._fillFrac or 0)
end

--- `Summoning <target> mm:ss` (the original's `SummoningText` content,
--- Forte_Summon.lua:142).
function Summon:FormatText(target, remaining)
    local who = target
    if type(who) ~= "string" or who == "" then who = "(target unread)" end
    return string.format("Summoning %s %s", who, Frame.FormatClock(remaining))
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
    if frac ~= self._frac then
        self._frac = frac
        self:SetFillFraction(frac)
    end
    local key = Frame.ClockKey(remaining)
    if key ~= self._timeKey then
        self._timeKey = key
        self.text:SetText(self:FormatText(t:Snapshot().target, remaining))
    end
    return true
end

function Summon:RenderIdle()
    self._frac, self._timeKey = nil, nil
    self:SetShown(false)
    if self.text then self.text:SetText("") end
end

--- The injected-tracker seam (tests, launch-day probes).
function Summon:SetTracker(tracker)
    self.Tracker = tracker
    self._frac, self._timeKey = nil, nil
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
