-- addon/Forte_Warlock/UI/Soulstone.lua
-- FX.Warlock.Soulstone: the Soulstone Tracker. One Classic-skinned bar under
-- the Shard plate that says `Soulstone: <target> mm:ss` while a soulstone
-- window is running, and is hidden otherwise. All STATE lives in
-- Core/Tools.lua's SoulstoneTracker (`docs/warlock-tools.md` — the
-- single-owner ledger, the expiry window, the one target string, the
-- "swept stone is a window, not a read"); this file is a pure renderer of
-- `:Active()`, `:Target()`, `:Remaining()`, `:Duration()` (PLAN §3.4 "pure
-- renderer").
--
-- Law line (docs/reference-functional-spec.md §4, SS-01…SS-06): the widget
-- runs its OWN timer — it is not a cooldown-bar entry — and it counts the
-- window DOWN from the tracked expiry, never from a fresh constant. The
-- 2012 mod's own widget is the shape this copies: one bar, the bearer's name
-- and a compact clock on it (the original's `SoulstoneText`,
-- /tmp/fxref/Forte_Soulstone/Forte_Soulstone.lua:206-224), the fill draining
-- with the window.
--
-- The target law: the tracker hands over ONE string it owns (the bearer
-- captured at the stone's STARTED cast); the frame never reads unit fields,
-- so it can not pick a secret value up. An unread bearer renders
-- `(target unread)` — SS-11's honesty, printed, never hidden (the
-- Hunter swing bar's unread law).
--
-- The 10 Hz law: `Update` returns TRUE while a window is live, so
-- UI/Module.lua keeps the driver running for it; when the window expires the
-- bar retires with it.
--
-- Skin/position/settings/lock/clock: the shared law in UI/Frame.lua.
-- Settings (module "Warlock"): SoulstoneWidth/Height/Color/Strikethrough;
-- the shared keys ride `General`.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Warlock = FX.Warlock or {}

local Frame = FX.Warlock.Frame
local Stone = Frame:new({
    name = "Soulstone",
    dbKey = "soulstone",
    size = { Width = 140, Height = 12, Point = "CENTER", X = 60, Y = -215 },
    module = "Warlock",
    sharedModule = "General",
    lockKey = "Lock",
    keys = { "SoulstoneWidth", "SoulstoneHeight", "SoulstoneColor",
             "SoulstoneStrikethrough" },
    keymap = {
        SoulstoneEnable = "SetEnabled",
        SoulstoneWidth = "SetWidth",
        SoulstoneHeight = "SetHeight",
        SoulstoneColor = "SetBarColor",
        SoulstoneStrikethrough = "SetStrikethrough",
    },
})
FX.Warlock.Soulstone = Stone

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.Warlock.SoulstoneSkin = setmetatable({
    Width = 140, Height = 12,
    Inset = 3,
    EdgeTexture = TEX .. "Aluminium",       -- the bar's frame art
    FillTexture = TEX .. "Smooth.tga",      -- the vendored smooth fill
    BarColor = { 0.64, 0.21, 0.93, 1 },      -- the Soulstone category tint
    TextOffset = 11,                        -- the label rides above the bar
    TextSize = 11,
}, { __index = FX.Warlock.FrameSkin })
Stone.skin = FX.Warlock.SoulstoneSkin
Stone.sizeDefaults = { Width = 140, Height = 12, Point = "CENTER",
                       X = 60, Y = -215 }
Stone.TEXT_DY = 11

-- ----------------------------------------------------------------- the art --

--- The bar box: the Aluminium plate the window drains inside.
function Stone:_NewBar()
    local h = self.skin.Height - 2 * self.skin.Inset
    self.barHeight = h
    local bar = self:_NewPlate(self.skin.Width, self.skin.Height,
        self.skin.Inset, self.skin.BgColor)
    self.plate:Hide()                 -- the bar IS the plate here
    return bar
end

--- The depleting fill, left-anchored inside the bar.
function Stone:_NewFillBar()
    local c = self.skin.BarColor
    self.fillBarColor = c
    self.fill = self.anchor:CreateTexture()
    self.fill:SetTexture(self.skin.FillTexture or (TEX .. "Aluminium"))
    self.fill:SetPoint("LEFT", self.bar, "LEFT", 0, 0)
    self.fill:SetSize(self.skin.Width - 2 * self.skin.Inset, self.barHeight)
    self.fill:SetDrawLayer("OVERLAY")
    self.fill:SetVertexColor(c[1], c[2], c[3], c[4])
end

function Stone:_Build()
    Frame._Build(self)
    if self.icon or self.fill then return end
    self:_NewFillBar()
end

function Stone:ApplyBarColor()
    Frame.ApplyBarColor(self)
end

function Stone:SizeChangedHook()
    self:SetFillFraction(self._fillFrac or 1)
end

--- `Soulstone: <target> mm:ss` (the assignment's text, SS-02: the bearer and
--- the window on one line).
function Stone:FormatText(target, remaining)
    local who = target
    if who == nil then
        who = FX.Compat and FX.Compat.PlainOrNil and FX.Compat.PlainOrNil(target)
            or nil
    end
    if type(who) ~= "string" or who == "" then who = "(target unread)" end
    return string.format("Soulstone: %s %s", who, Frame.FormatClock(remaining))
end

-- ------------------------------------------------------------------ update --

--- One render pass; TRUE while a window is live (the driver keeps ticking).
function Stone:Update(now)
    local t = self.Tracker
    local live = false
    local remaining, duration
    if t and self:Enabled() and t:Active() then
        remaining = t:Remaining()
        if type(remaining) == "number" then
            live = true
            duration = t:Snapshot().duration
        end
    end
    self:SetShown(live)
    if not live then return false end
    -- The fill drains with the window (SS-01: "fills as the timer runs").
    local frac = 1
    if type(duration) == "number" and duration > 0 then
        frac = remaining / duration
        if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
    end
    if frac ~= self._frac then
        self._frac = frac
        self:SetFillFraction(frac)
    end
    local key = Frame.ClockKey(remaining)
    if key ~= self._timeKey then
        self._timeKey = key
        self.text:SetText(self:FormatText(t:Target(), remaining))
    end
    return true
end

function Stone:RenderIdle()
    self._frac, self._timeKey = nil, nil
    self:SetShown(false)
    if self.text then self.text:SetText("") end
end

--- The injected-tracker seam (tests, launch-day probes).
function Stone:SetTracker(tracker)
    self.Tracker = tracker
    self._frac, self._timeKey = nil, nil
end

function Stone:StatusLine()
    local t = self.Tracker
    local active = t and t:Active()
    return string.format("Soulstone Tracker: %s%s | %dx%d | %s",
        active and "window" or "idle",
        active and (" " .. Frame.FormatClock(t:Remaining())) or "",
        self.skin.Width, self.skin.Height,
        self:Enabled() and "on" or "off")
end
