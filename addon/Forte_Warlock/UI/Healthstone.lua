-- addon/Forte_Warlock/UI/Healthstone.lua
-- FX.Warlock.Healthstone: the Healthstone Spy's plate. One Classic-skinned
-- plate carrying the HEALTHSTONE count, dimmed while the creation cooldown
-- runs, with `mm:ss` under it while it counts down. All STATE lives in
-- Core/Tools.lua's HealthstoneTracker; this file is a pure renderer of
-- `:Present()`, `:Count()`, `:CooldownRemaining()` (PLAN §3.4 "pure
-- renderer", the Forte_Warlock/UI/Shards.lua shape).
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
-- plus its cooldown, in our own Classic skin, with no reference geometry to
-- copy.
--
-- The 10 Hz law: a KNOWN count is not time-driven (bag events update it), so
-- the plate asks the driver for a tick only while a cooldown counts down.
--
-- Skin/position/settings/lock/clock: the shared law in UI/Frame.lua.
-- Settings (module "Warlock"): HealthstoneSize, HealthstoneStrikethrough,
-- plus the shared Enable/Scale/Alpha/EnableMouse/Lock/ShowTime/BgColor/
-- BarColor.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}

local Frame = FX.Warlock.Frame
local HS = Frame:new({
    name = "Healthstone",
    dbKey = "healthstone",
    size = { Width = 34, Height = 34, Point = "CENTER", X = 190, Y = -215 },
    module = "Warlock",
    sharedModule = "General",
    lockKey = "Lock",
    keys = { "HealthstoneSize", "HealthstoneStrikethrough" },
    keymap = {
        HealthstoneEnable = "SetEnabled",
        HealthstoneSize = "SetSize",
        HealthstoneStrikethrough = "SetStrikethrough",
    },
})
FX.Warlock.Healthstone = HS

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.Warlock.HealthstoneSkin = setmetatable({
    Width = 34, Height = 34,
    Inset = 3,
    TextSize = 16,
    PlateTexture = TEX .. "HS1.blp",        -- the vendored healthstone art
    EdgeTexture = TEX .. "Aluminium",
    CooldownAlpha = 0.55,               -- the plate during a creation cooldown
}, { __index = FX.Warlock.FrameSkin })
HS.skin = FX.Warlock.HealthstoneSkin
HS.sizeDefaults = { Width = 34, Height = 34, Point = "CENTER",
                    X = 190, Y = -215 }

-- ----------------------------------------------------------------- the art --

function HS:_NewText(_dy)
    local fs = self:_NewFont(0, 0, self.skin.TextSize, "CENTER")
    fs:SetText("")
    return fs
end

function HS:_Build()
    Frame._Build(self)
    if self.cdText then return end          -- idempotence (a rebuild is a leak)
    -- The cooldown text under the plate; ShowTime owns its visibility.
    self.cdText = self:_NewFont(0, -(self.skin.Height / 2) - 7, 10, "CENTER")
    self.cdText:SetText("")
end

--- A plate is square: one number drives both edges.
function HS:SetSize(w, _h)
    if type(w) ~= "number" then return end
    self.skin.Width, self.skin.Height = w, w
    self:SizeChanged()
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
    local n = (type(count) == "number" and count > 0) and tostring(count)
        or "0"
    if n ~= self._count then
        self._count = n
        self.text:SetText(n)
    end
    local cooling = type(remaining) == "number" and remaining > 0
    -- The dim is the plate's own alpha, not the frame's (the frame's alpha
    -- stays `Warlock.Alpha`'s, so a scale/alpha setting change can not fight
    -- the cooldown law).
    self:SetBarAlpha(cooling and self.skin.CooldownAlpha or 1)
    local cd = cooling and Frame.FormatClock(remaining)
    local key = cooling and Frame.ClockKey(remaining) or -1
    if key ~= self._timeKey then
        self._timeKey = key
        if self.cdText then self.cdText:SetText(cd or "") end
    end
    local showCd = cooling and self.state.showTime
    if showCd ~= self._cdShown then
        self._cdShown = showCd
        if self.cdText then
            if showCd then self.cdText:Show() else self.cdText:Hide() end
        end
    end
    return cooling
end

--- The plate's count text always shows; the cooldown text under it is the
--- ShowTime-owned text (and only rides a live cooldown).
function HS:ApplyTextVisibility()
    if not self._shown then return end
    if self.text then self.text:Show() end
    if self.cdText then
        if self.state.showTime and self._cdShown then self.cdText:Show()
        else self.cdText:Hide() end
    end
end

function HS:RenderIdle()
    self._count, self._timeKey, self._cdShown = nil, nil, nil
    self:SetShown(false)
    self:SetBarAlpha(1)
    if self.text then self.text:SetText("") end
    if self.cdText then self.cdText:SetText("") end
end

--- The injected-tracker seam (tests, launch-day probes).
function HS:SetTracker(tracker)
    self.Tracker = tracker
    self._count, self._timeKey, self._cdShown = nil, nil, nil
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
