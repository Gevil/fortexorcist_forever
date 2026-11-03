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
-- broadcasts). The roster half is LIVE since H6 (2026-11-02):
-- Core/Comms.lua + Core/Group.lua feed `self.Spy` (SetSpy), and the spy rows
-- ride this plate in the original's HS_DrawHealthstone layout — the Total
-- bar is the spy's stones/active row, the second bar the No-info row
-- (`HealthstoneUnknown`), the right label the `x<missing>` Amount2. The
-- distance sampling and the per-member aura scan stay dropped
-- (docs/warlock-tools.md, HS-05 out-of-combat-only).
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
    -- The Advanced page's strata row of this plate (the source's
    -- `HealthstoneStrata`, Forte_Healthstone.lua:316).
    advancedKey = "HealthstoneStrata",
    lockKey = "Lock",
    keys = { "HealthstoneSize", "HealthstoneColor",
             "HealthstoneStrikethrough", "HealthstoneExpand",
             "HealthstoneAuto", "HealthstoneDetails",
             "HealthstoneDetailsAuto", "HealthstoneSpace",
             "HealthstoneMinColor", "HealthstoneMaxColor",
             "HealthstoneUnknownMinColor", "HealthstoneUnknownMaxColor" },
    keymap = {
        HealthstoneEnable = "SetEnabled",
        HealthstoneSize = "SetWidth",            -- the plate width
        -- The second spy bar's switch (the original's HealthstoneUnknown,
        -- Forte_Healthstone.lua:333 default true, gate at :200).
        HealthstoneUnknown = "SetShowUnknown",
        -- m3 (CodeReview3): the Count colour picker on the Healthstone
        -- page had no consumer -- the plate's count text followed only
        -- the shared TextColor. The Shards page's ShardColor pair is the
        -- law: the frame's OWN colour key is the specific answer and wins
        -- over the General page's shared key (SetTextColor's own-over-
        -- shared rule, the key arg rides it).
        HealthstoneColor = "SetTextColor",
        HealthstoneStrikethrough = "SetStrikethrough",
        -- FWL.EXPAND_UP (the original's HealthstoneExpand,
        -- Forte_Healthstone.lua:292, def false :345): the bar list grows up
        -- from the plate (the Frame's `_LayoutBody` law).
        HealthstoneExpand = "SetExpandUp",
        -- FWL.AUTO_HIDE "Auto-hide outside party/raid" (:289, def false
        -- :342) -- the original's panel-show law `not HealthstoneAuto or
        -- STATES.GROUPED` (Forte_Healthstone.lua:13).
        HealthstoneAuto = "SetAutoHide",
        -- FWL.SHOW_BARS "Show bars" (:291, def true :340) and FWL.
        -- AUTO_MINIMIZE "Auto-minimize outside party/raid" (:290, def false
        -- :341): the draw law is `Details and (not DetailsAuto or
        -- GROUPED)` (Forte_Healthstone.lua:143).
        HealthstoneDetails = "SetShowBars",
        HealthstoneDetailsAuto = "SetAutoMinimize",
        -- FWL.BAR_SPACING (the original's HealthstoneSpace, :300, def 1
        -- :344): the gap of the bar run, the plate height's step.
        HealthstoneSpace = "SetRowSpace",
        -- FWL.LITTLE_HS / MANY_HS / LITTLE_UNKNOWN / MANY_UNKNOWN
        -- (Forte_Healthstone.lua:303-306, defaults :328-331): the spy bars'
        -- colour ramp, `ColorVal` mixing MIN into MAX by the bar's value
        -- (:104-111, FW:MixColors Forte_Core.lua:2080-2084).
        HealthstoneMinColor = "SetBarColorMin",
        HealthstoneMaxColor = "SetBarColorMax",
        HealthstoneUnknownMinColor = "SetUnknownColorMin",
        HealthstoneUnknownMaxColor = "SetUnknownColorMax",
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

-- The "No info" bar's switch, the original's default (FW.Default.
-- HealthstoneUnknown = true, Forte_Healthstone.lua:333).
HS.state.showUnknown = true

function HS:SetShowUnknown(on)
    local v = not not on
    if v == self.state.showUnknown then return end
    self.state.showUnknown = v
    self._unknownKey = nil
    self:RenderIdle()
end

-- The second line's label (FWL.TOTAL, Forte_Healthstone/Localization.lua:48).
HS.TOTAL = "Total"
-- The second spy bar's label (FWL.NO_INFO, Localization.lua:53 — the bar the
-- original shows while HealthstoneUnknown, Forte_Healthstone.lua:200-202,
-- default TRUE at :333).
HS.NO_INFO = "No info"

--- The Group model seam (Core/Group.lua instance; Core/Comms.lua owns the
--- live one, tests inject their own — the SetSpy convention).
function HS:SetSpy(group)
    self.Spy = group
    self._spyKey, self._unknownKey = nil, nil
end

--- `HealthstoneAuto` (FWL.AUTO_HIDE "Auto-hide outside party/raid", the
--- original's Forte_Healthstone.lua:289, def false :342). The 2012 show law
--- is `not HealthstoneAuto or STATES.GROUPED` (:13 of the module's own
--- show gate); this plate has no unit API in it (the pure-renderer law), so
--- its GROUPED is the half it is allowed to know: the comms roster has
--- members (a scanned raid/party). No roster, no claim of a group.
function HS:SetAutoHide(on)
    self._autoHide = not not on
end

--- The colour pair of the Total bar: the original's `ColorVal` mixes
--- `HealthstoneMinColor` into `HealthstoneMaxColor` by the bar's value
--- (Forte_Healthstone.lua:104-111).
function HS:SetBarColorMin(col) self._minC = col; self:_ArmRamps() end
function HS:SetBarColorMax(col) self._maxC = col; self:_ArmRamps() end
--- The pair of the "No info" bar (HealthstoneUnknownMinColor /
--- HealthstoneUnknownMaxColor, Forte_Healthstone.lua:305-306, :330-331 --
--- the same ColorVal with `i ~= 1`).
function HS:SetUnknownColorMin(col)
    self._unkMinC = col
    self:_ArmRamps()
end
function HS:SetUnknownColorMax(col)
    self._unkMaxC = col
    self:_ArmRamps()
end

--- Both halves of a pair in hand -> the Frame's ramp is armed (and the bars
--- repaint at their current fractions). A half arriving out of a Reset
--- order arms as soon as its pair is complete.
function HS:_ArmRamps()
    if self._minC and self._maxC then
        self:SetColorRamp("main", self._minC, self._maxC)
    end
    if self._unkMinC and self._unkMaxC then
        self:SetColorRamp("unknown", self._unkMinC, self._unkMaxC)
    end
end

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
    local spy = self.Spy
    local summary
    if spy and self:Enabled() then
        -- The spy half (H6): the roster rides the Core/Group.lua model; a
        -- roster with members is a claim the plate must render even when
        -- the own bags are empty (the original's plate rides the RAID
        -- state, Forte_Healthstone.lua:13 `HealthstoneAuto`/`GROUPED`).
        summary = spy:HealthstoneSummary()
        if summary ~= nil
            and (summary.active + summary.unknown) > 0 then show = true end
    end
    self:SetShown(show and (not self._autoHide
        -- GROUPED, the plate's legal answer: the comms roster has members
        -- (the original's show gate is `not HealthstoneAuto or
        -- STATES.GROUPED`, Forte_Healthstone.lua:13).
        or (summary ~= nil and (summary.active + summary.unknown) > 0)))
    if not self._shown then
        self:SetExtraRowsShown(0)
        return false
    end
    -- `<Name>Details` + `<Name>DetailsAuto`: the bars' own show law,
    -- `Details and (not DetailsAuto or GROUPED)` (Forte_Healthstone.lua:143
    -- -- "you can hide them in case you only want to see the information on
    -- the header", FWL.SHOW_BARS_TT, Forte_Core.lua:275). The header (the
    -- icon, the count, the clock) rides the plate; the bars ride this.
    local bars = self:BarsShownFor(
        summary ~= nil and (summary.active + summary.unknown) > 0)
    self:SetIconForCount(count)
    local n = Frame.FormatAmount((type(count) == "number" and count > 0)
        and count or 0)
    if n ~= self._count then
        self._count = n
        self.amountFS:SetText(n)
    end
    -- The second line: the Total label + the count on the bar (the original's
    -- FWHSBar1, Forte_Healthstone.lua:197 + :139). With the spy live the bar
    -- is the spy's own row 1: stones over active
    -- (`hs:insert(stones, active, FWL.TOTAL, …)`, Forte_Healthstone.lua:199,
    -- the value `t1/t2` at :140).
    self:SetRowShown(bars)
    if self.nameFS:GetText() ~= self.TOTAL then
        self.nameFS:SetText(self.TOTAL)
    end
    local amount, frac
    if summary ~= nil then
        amount = tostring(summary.stones)
        frac = summary.active > 0 and (summary.stones / summary.active) or 0
    else
        amount = tostring(type(count) == "number" and count or 0)
        frac = (type(count) == "number" and count > 0) and 1 or 0
    end
    if amount ~= self._amount then
        self._amount = amount
        self.timeFS:SetText(amount)
    end
    if frac ~= self._frac then
        self._frac = frac
        self:SetFillFraction(frac)
    end
    -- The "No info" bar (`hs:insert(unknown, active+unknown, FWL.NO_INFO,
    -- …)`, Forte_Healthstone.lua:200-202), shown while showUnknown.
    local extraOn = 0
    if bars and summary ~= nil and self.state.showUnknown
        and summary.unknown > 0 then
        local e = self:ExtraRow(1)
        if e then
            self:SetExtraRowText(e, self.NO_INFO, tostring(summary.unknown))
            local den = summary.active + summary.unknown
            self:SetExtraRowFraction(e,
                den > 0 and (summary.unknown / den) or 0)
            extraOn = 1
        end
    end
    self:SetExtraRowsShown(extraOn)
    -- The right label: the creation cooldown's clock, in the plate's Info
    -- slot (Forte_Soulstone.xml:140-146 is that slot's geometry). With the
    -- spy live and no clock it is the original's Amount2, the missing count
    -- `"x"..active-stones` (Forte_Healthstone.lua:165, xml Amount2).
    local cooling = type(remaining) == "number" and remaining > 0
    -- The dim is the plate's own alpha, not the frame's (the frame's alpha
    -- stays `Warlock.Alpha`'s, so a scale/alpha setting change can not fight
    -- the cooldown law).
    self:SetBarAlpha(cooling and self.skin.CooldownAlpha or 1)
    local info = ""
    if cooling then
        info = Frame.FormatClock(remaining)
    elseif summary ~= nil then
        info = "x" .. summary.missing
    end
    if info ~= self._infoText then
        self._infoText = info
        self.infoFS:SetText(info)
    end
    local key = cooling and Frame.ClockKey(remaining) or -1
    self._timeKey = key
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
        -- ShowTime owns the right label; its content is the cooldown clock
        -- or the spy's missing count (the Update law above), so its
        -- visibility rides "it carries text".
        if self.state.showTime and self._infoText ~= nil
            and self._infoText ~= "" then
            self.infoFS:Show()
        else
            self.infoFS:Hide()
        end
    end
end

function HS:RenderIdle()
    self._count, self._timeKey, self._amount, self._frac = nil, nil, nil, nil
    self._infoText = nil
    self:SetExtraRowsShown(0)
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
