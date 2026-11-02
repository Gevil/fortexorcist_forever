-- addon/Forte_Warlock/UI/Shards.lua
-- FX.Warlock.Shards: the Shard Manager. One small plate carrying the soul
-- shard COUNT; the source label (`[bag]` / `[power]`) rides in its tooltip.
-- All STATE lives in Core/Tools.lua's ShardCounter; this file is a pure
-- renderer of `FX.Warlock.Tools.Shards:Count()` (the
-- Forte_Hunter/UI/Swing.lua shape).
--
-- The original's Shard subsystem is a REMOVED module (spec FE-35:
-- `FX_Saved.Shards = nil; -- module removed` — "the removed module has no
-- reference law"), so there is no 2012 geometry to copy: the v1 is our own
-- compact readout in the Classic skin. The count is DISPLAYED and never
-- gates anything (docs/warlock-tools.md: the two shard sources are trusted
-- for a count only).
--
-- Show law: the plate is on screen while a shard count is KNOWN (`Count()`
-- non-nil). A count changes on bag events, never with time, so this frame
-- never asks the driver for a tick. No read yet, nothing to show.
--
-- Skin/position/settings/lock/clock: the shared law in UI/Frame.lua.
-- Settings (module "Warlock"): ShardSize, ShardColor, plus the shared
-- Enable/Scale/Alpha/EnableMouse/Lock/ShowTime/BgColor/BarColor. The
-- tooltip needs the mouse and a locked frame is click-through by law, so the
-- tooltip is live while UNLOCKED (the source is in `/fx status` always).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}

local Frame = FX.Warlock.Frame
local Shards = Frame:new({
    name = "Shards",
    dbKey = "shards",
    skin = nil,                                  -- filled in below
    size = { Width = 34, Height = 34, Point = "CENTER", X = -180, Y = -215 },
    module = "Warlock",
    sharedModule = "General",
    lockKey = "Lock",
    keys = { "ShardSize", "ShardColor", "ShardStrikethrough" },
    keymap = {
        ShardEnable = "SetEnabled",
        ShardSize = "SetSize",                   -- one square
        ShardColor = "SetTextColor",
        ShardStrikethrough = "SetStrikethrough",
    },
})
FX.Warlock.Shards = Shards

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.Warlock.ShardsSkin = setmetatable({
    Width = 34, Height = 34,
    Inset = 3,
    TextSize = 16,
    PlateTexture = TEX .. "SH1.blp",        -- the vendored shard art
    EdgeTexture = TEX .. "Aluminium",
    TextColor = { 1, 1, 1, 1 },
    BarColor = { 0.64, 0.21, 0.93, 0.85 },        -- the Soulstone category tint
    PlateTexture = TEX .. "SH1.blp",        -- the vendored shard art
    EdgeTexture = TEX .. "Aluminium",
}, { __index = FX.Warlock.FrameSkin })
Shards.skin = FX.Warlock.ShardsSkin
Shards.sizeDefaults = { Width = 34, Height = 34, Point = "CENTER",
                        X = -180, Y = -215 }

-- ----------------------------------------------------------------- the art --

function Shards:_NewText(_dy)
    local fs = self:_NewFont(0, 0, self.skin.TextSize, "CENTER")
    fs:SetText("")
    return fs
end

function Shards:_Build()
    Frame._Build(self)
    if self.sourceFS then return end        -- idempotence (a rebuild is a leak)
    self.sourceFS = self:_NewFont(0, -(self.skin.Height / 2) - 7, 10, "CENTER")
    self.sourceFS:SetText("")
end

--- The source label as the frame's tooltip: the `[bag]`/`[power]` read is a
--- launch-day probe reading, and a tooltip is where a label that detailed
--- lives; the plate stays a clean number. The Forte_Options/Core/Widgets.lua
--- GameTooltip idiom.
function Shards:_AttachTip()
    if not self.anchor then return end
    self.tip = CreateFrame("Frame", nil, self.anchor)
    self.tip:SetAllPoints(self.anchor)
    self.tip:EnableMouse(true)
    self.tip:SetScript("OnEnter", function()
        local source = (self.Tracker and self.Tracker:Snapshot() or {}).source
        if not GameTooltip or source == nil then return end
        GameTooltip:SetOwner(self.tip)
        GameTooltip:SetTipTitle("Soul shards")
        GameTooltip:SetTipLines({ tostring(source) })
        GameTooltip:Show(true)
    end)
    self.tip:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:HideOwner(self.tip) end
    end)
end

--- A plate is square: one number drives both edges.
function Shards:SetSize(w, _h)
    if type(w) ~= "number" then return end
    self.skin.Width, self.skin.Height = w, w
    self:SizeChanged()
end

-- ------------------------------------------------------------------ update --

--- One render pass. A count is not time-driven, so the return is always
--- false (the driver stops ticking on this frame's account).
function Shards:Update(_now)
    local show = false
    local count, source
    local t = self.Tracker
    if t and self:Enabled() then
        -- Count is the pair (count, source): the source label is the
        -- launch-day probe reading that rides the same read.
        count, source = t:Count()
    end
    if type(count) == "number" and self:Enabled() then
        show = true
    end
    self:SetShown(show)
    if not show then return false end
    local n = tostring(count)
    if n ~= self._count then
        self._count = n
        self.text:SetText(n)
    end
    -- The source label rides ShowTime, keyed by its own text.
    local src = source ~= nil and tostring(source) or ""
    local showSrc = self.state.showTime and src ~= ""
    if showSrc ~= self._srcShown then
        self._srcShown = showSrc
        if self.sourceFS then
            if showSrc then self.sourceFS:Show() else self.sourceFS:Hide() end
        end
    end
    if showSrc and src ~= self._source then
        self._source = src
        self.sourceFS:SetText(src)
    end
    return false
end

--- The plate's count text always shows; the source label under it is the
--- ShowTime-owned text.
function Shards:ApplyTextVisibility()
    if not self._shown then return end
    if self.text then self.text:Show() end
    if self.sourceFS then
        if self.state.showTime and self._srcShown then self.sourceFS:Show()
        else self.sourceFS:Hide() end
    end
end

function Shards:RenderIdle()
    self._count, self._source, self._srcShown = nil, nil, nil
    self:SetShown(false)
    if self.text then self.text:SetText("") end
    if self.sourceFS then self.sourceFS:SetText("") end
end

function Shards:StatusLine()
    local count, source
    if self.Tracker then count, source = self.Tracker:Count() end
    return string.format("Shard Manager: %s%s | %dx%d | %s",
        type(count) == "number" and tostring(count) or "unread",
        source ~= nil and ("[" .. tostring(source) .. "]") or "",
        self.skin.Width, self.skin.Height,
        self:Enabled() and "on" or "off")
end

--- The injected-tracker seam (tests, launch-day probes).
function Shards:SetTracker(tracker)
    self.Tracker = tracker
    self._count, self._source, self._srcShown = nil, nil, nil
end
