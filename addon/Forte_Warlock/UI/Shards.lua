-- addon/Forte_Warlock/UI/Shards.lua
-- FX.Warlock.Shards: the Shard Manager — a labelled plate in the original's
-- plate law (UI/Frame.lua, every constant cited there): the SH shard icon at
-- the plate's left, the count `x<n>` next to it (the original's count format,
-- Forte_Soulstone.lua:292 / Forte_Healthstone.lua:164 / Forte_Summon.lua:165),
-- the right-aligned `<n> total` label (the plate's Info slot,
-- Forte_Soulstone.xml:140-146; the "Total" word is the original's own count
-- label, Forte_Healthstone/Localization.lua:48), and a second line carrying
-- the source label (`bag` / `power`).
--
-- The original's Shard subsystem is a REMOVED module (spec FE-35:
-- `FX_Saved.Shards = nil; -- module removed`, Forte_Core.lua:1531 — "the
-- removed module has no reference law"), so there is no 2012 shard geometry to
-- copy: the plate geometry is the geometry the Soulstone/Healthstone/Summon
-- plates share (Forte_Soulstone.xml:122-146), the label formats are the ones
-- those three files print.
--
-- All STATE lives in Core/Tools.lua's ShardCounter; this file is a pure
-- renderer of `FX.Warlock.Tools.Shards:Count()` (the
-- Forte_Hunter/UI/Swing.lua shape). The count is DISPLAYED and never gates
-- anything (docs/warlock-tools.md: the two shard sources are trusted for a
-- count only).
--
-- Show law: the plate is on screen while a shard count is KNOWN (`Count()`
-- non-nil). A count changes on bag events, never with time, so this frame
-- never asks the driver for a tick. No read yet, nothing to show.
--
-- Skin/position/settings/lock/clock: the shared law in UI/Frame.lua.
-- Settings (module "Warlock"): ShardSize (the plate width), ShardColor, plus
-- the shared Enable/Scale/Alpha/EnableMouse/Lock/ShowTime/BgColor/BarColor.
-- The tooltip needs the mouse and a locked frame is click-through by law, so
-- the tooltip is live while UNLOCKED (the source is in `/fx status` always).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}

local Frame = FX.Warlock.Frame
local Shards = Frame:new({
    name = "Shards",
    dbKey = "shards",
    skin = nil,                                  -- filled in below
    size = { Width = 106, Height = 20, Point = "CENTER", X = -180, Y = -215 },
    module = "Warlock",
    sharedModule = "General",
    lockKey = "Lock",
    keys = { "ShardSize", "ShardColor", "ShardStrikethrough" },
    keymap = {
        ShardEnable = "SetEnabled",
        ShardSize = "SetWidth",                  -- the plate width
        ShardColor = "SetTextColor",
        ShardStrikethrough = "SetStrikethrough",
    },
})
FX.Warlock.Shards = Shards

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.Warlock.ShardsSkin = setmetatable({
    Width = 106, Height = 20,
    TextSize = 11,                               -- Forte_Core.lua:2547
    IconTexture = TEX .. "SH1",                  -- the vendored shard art
}, { __index = FX.Warlock.FrameSkin })
Shards.skin = FX.Warlock.ShardsSkin
Shards.sizeDefaults = { Width = 106, Height = 20, Point = "CENTER",
                        X = -180, Y = -215 }

-- ----------------------------------------------------------------- the art --

--- The source label as the frame's tooltip: the `[bag]`/`[power]` read is a
--- launch-day probe reading, and a tooltip is where a label that detailed
--- lives; the second line carries the plain source word. The
--- Forte_Options/Core/Widgets.lua GameTooltip idiom.
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

--- The plate's right label: `<n> total` (the plate's Info slot,
--- Forte_Soulstone.xml:140-146; the "Total" word is the original's count
--- label, Forte_Healthstone/Localization.lua:48).
function Shards:FormatInfo(count)
    return string.format("%d total", count)
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
    local n = Frame.FormatAmount(count)
    if n ~= self._count then
        self._count = n
        self.amountFS:SetText(n)
    end
    local info = self:FormatInfo(count)
    if info ~= self._info then
        self._info = info
        self.infoFS:SetText(info)
    end
    -- The second line: the source label; it rides ShowTime (label text),
    -- keyed by its own text.
    local src = source ~= nil and tostring(source) or ""
    local rowOn = self.state.showTime and src ~= ""
    self:SetRowShown(rowOn)
    self:SetFillFraction(0)
    if rowOn and src ~= self._source then
        self._source = src
        self.nameFS:SetText(src)
    end
    self:ApplyTextVisibility()
    return false
end

--- The plate's count and the `<n> total` label law: the count always shows;
--- the Info label and the source second line are the ShowTime-owned text.
function Shards:ApplyTextVisibility()
    if not self._shown then return end
    if self.amountFS then self.amountFS:Show() end
    if self.infoFS then
        if self.state.showTime then self.infoFS:Show() else self.infoFS:Hide() end
    end
    if self.nameFS then
        if self._rowShown then self.nameFS:Show() else self.nameFS:Hide() end
    end
    if self.timeFS then self.timeFS:Hide() end
end

function Shards:RenderIdle()
    self._count, self._info, self._source = nil, nil, nil
    self:SetRowShown(false)
    self:SetShown(false)
    self.amountFS:SetText("")
    self.infoFS:SetText("")
    self.nameFS:SetText("")
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
    self._count, self._info, self._source = nil, nil, nil
end
