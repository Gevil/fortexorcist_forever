-- addon/Forte_Warlock/UI/Healthstone.lua
-- FX.Warlock.Healthstone: the Healthstone Spy's plate — the original's plate
-- (Forte_Healthstone.xml:81-105, every constant cited in UI/Frame.lua): the
-- HS1 icon at the plate's left (Forte_Healthstone.xml:150), the count `x<n>`
-- next to it (`x`..GotHealthstone(), Forte_Healthstone.lua:164), the right
-- label carrying the stone's item cooldown clock, and the second line: the
-- `Total` label at the bar's left (FWL.TOTAL,
-- Forte_Healthstone/Localization.lua:48, printed by Forte_Healthstone.lua:197)
-- and the count at the bar's right (the bar's Amount, Forte_Healthstone.lua:139
-- with Forte_Healthstone.xml:14-26). The icon art follows the stone state the
-- way the original swaps it: HS2 while stones are in the bags, HS3 while they
-- are not (Forte_Healthstone.lua:168,172).
--
-- All STATE lives in Core/Tools.lua's HealthstoneTracker; this file is a pure
-- renderer of `:Present()`, `:Count()`, `:CooldownRemaining()` (PLAN §3.4
-- "pure renderer", the Forte_Warlock/UI/Shards.lua shape).
--
-- The plate is on screen only while the module KNOWS about stones
-- (`Present()` non-nil): a known-empty bag hides it, a bag that has never
-- been read hides it (`docs/warlock-tools.md`: no read, no claim) — the
-- widget never renders an empty plate.
--
-- The original's Healthstone Spy was a raid-wide roster spy (spec §5,
-- HS-01…HS-07: per-member aura scans, roster distance sampling, chat
-- broadcasts). docs/warlock-tools.md deliberately drops all of it, and the
-- two sources it kept are trusted "for a count only"; so the v1 is the count
-- plus its cooldown on the original's plate, with the original's own plate
-- geometry.
--
-- The 10 Hz law: a KNOWN count is not time-driven (bag events update it), so
-- the plate asks the driver for a tick only while a cooldown counts down.
--
-- Skin/position/settings/lock/clock: the shared law in UI/Frame.lua.
-- Settings (module "Warlock"): HealthstoneSize (the plate width),
-- HealthstoneStrikethrough, plus the shared Enable/Scale/Alpha/EnableMouse/
-- Lock/ShowTime/BgColor/BarColor.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}

local Frame = FX.Warlock.Frame
local HS = Frame:new({
    name = "Healthstone",
    dbKey = "healthstone",
    size = { Width = 106, Height = 20, Point = "CENTER", X = 190, Y = -215 },
    module = "Warlock",
    sharedModule = "General",
    lockKey = "Lock",
    keys = { "HealthstoneSize", "HealthstoneStrikethrough" },
    keymap = {
        HealthstoneEnable = "SetEnabled",
        HealthstoneSize = "SetWidth",            -- the plate width
        HealthstoneStrikethrough = "SetStrikethrough",
    },
})
FX.Warlock.Healthstone = HS

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.Warlock.HealthstoneSkin = setmetatable({
    Width = 106, Height = 20,
    RowHeight = 12,                              -- Forte_Healthstone.lua:339
    IconTexture = TEX .. "HS1",                  -- Forte_Healthstone.xml:150
    -- The healthstone bar colour (HealthstoneMaxColor,
    -- Forte_Healthstone.lua:328).
    BarColor = { 0.53, 1.00, 0.00, 1 },
    CooldownAlpha = 0.55,               -- the plate during a creation cooldown
    TextSize = 11,                               -- Forte_Core.lua:2547
}, { __index = FX.Warlock.FrameSkin })
HS.skin = FX.Warlock.HealthstoneSkin
HS.sizeDefaults = { Width = 106, Height = 20, Point = "CENTER",
                    X = 190, Y = -215 }

-- The second line's label (FWL.TOTAL, Forte_Healthstone/Localization.lua:48).
HS.TOTAL = "Total"

-- ----------------------------------------------------------------- the art --

--- The icon art rides the stone state (the original's NormalTexture swap,
--- Forte_Healthstone.lua:168,172).
function HS:SetIconForCount(count)
    if not self.icon then return end
    local art = (type(count) == "number" and count > 0)
        and (TEX .. "HS2") or (TEX .. "HS3")
    if art ~= self._iconArt then
        self._iconArt = art
        self.icon:SetTexture(art)
    end
end

-- ------------------------------------------------------------------ update --

--- One render pass; TRUE only while a cooldown counts down.
function HS:Update(now)
    local t = self.Tracker
    local show = false
    local count, remaining, duration
    if t and self:Enabled() then
        local present = t:Present()
        if present then
            show = true
            count = t:Count()
            remaining = t:CooldownRemaining()
            if type(remaining) == "number" then
                duration = t:Snapshot().cooldownDuration
            end
        end
    end
    self:SetShown(show)
    if not show then return false end
    self:SetIconForCount(count)
    local n = Frame.FormatAmount((type(count) == "number" and count > 0)
        and count or 0)
    if n ~= self._count then
        self._count = n
        self.amountFS:SetText(n)
    end
    -- The second line: the Total label + the count on the bar (the original's
    -- FWHSBar1, Forte_Healthstone.lua:197 + :139).
    self:SetRowShown(true)
    if self.nameFS:GetText() ~= self.TOTAL then
        self.nameFS:SetText(self.TOTAL)
    end
    local amount = tostring(type(count) == "number" and count or 0)
    if amount ~= self._amount then
        self._amount = amount
        self.timeFS:SetText(amount)
    end
    local frac = (type(count) == "number" and count > 0) and 1 or 0
    if frac ~= self._frac then
        self._frac = frac
        self:SetFillFraction(frac)
    end
    -- The right label: the creation cooldown's clock, in the plate's Info
    -- slot (Forte_Soulstone.xml:140-146 is that slot's geometry).
    local cooling = type(remaining) == "number" and remaining > 0
    -- The dim is the plate's own alpha, not the frame's (the frame's alpha
    -- stays `Warlock.Alpha`'s, so a scale/alpha setting change can not fight
    -- the cooldown law).
    self:SetBarAlpha(cooling and self.skin.CooldownAlpha or 1)
    local cd = cooling and Frame.FormatClock(remaining)
    local key = cooling and Frame.ClockKey(remaining) or -1
    if key ~= self._timeKey then
        self._timeKey = key
        self.infoFS:SetText(cd or "")
    end
    self:ApplyTextVisibility()
    return cooling
end

--- The plate's count, the Total bar and its amount are the module's core
--- readout; the cooldown clock in the right label is the ShowTime-owned text
--- (and only rides a live cooldown).
function HS:ApplyTextVisibility()
    if not self._shown then return end
    if self.amountFS then self.amountFS:Show() end
    if self.nameFS and self._rowShown then self.nameFS:Show() end
    if self.timeFS and self._rowShown then self.timeFS:Show() end
    if self.infoFS then
        if self.state.showTime and self._timeKey ~= nil
            and self._timeKey >= 0 then
            self.infoFS:Show()
        else
            self.infoFS:Hide()
        end
    end
end

function HS:RenderIdle()
    self._count, self._timeKey, self._amount, self._frac = nil, nil, nil, nil
    self:SetRowShown(false)
    self:SetShown(false)
    self:SetBarAlpha(1)
    self.amountFS:SetText("")
    self.infoFS:SetText("")
    self.nameFS:SetText("")
    self.timeFS:SetText("")
end

--- The injected-tracker seam (tests, launch-day probes).
function HS:SetTracker(tracker)
    self.Tracker = tracker
    self._count, self._timeKey, self._amount, self._frac = nil, nil, nil, nil
end

function HS:StatusLine()
    local t = self.Tracker
    local cd = t and t:CooldownRemaining()
    return string.format("Healthstone Spy: %s%s | %dx%d | %s",
        (t and t:Present()) and tostring(t:Count() or 0) or "unread",
        (type(cd) == "number" and cd > 0)
            and (" cd " .. Frame.FormatClock(cd)) or "",
        self.skin.Width, self.skin.Height,
        self:Enabled() and "on" or "off")
end
