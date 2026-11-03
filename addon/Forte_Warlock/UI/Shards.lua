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
-- All STATE lives in Core/Tools.lua's ShardCounter (the own count) and
-- Core/Group.lua's roster model (the raid's counts, bound through `SetSpy`,
-- Core/Comms.lua owning the live instance); this file is a pure renderer of
-- `FX.Warlock.Tools.Shards:Count()` plus `Spy:ShardRows()`/`Spy:ShardTotal()`
-- (the Forte_Hunter/UI/Swing.lua shape). The counts are DISPLAYED and never
-- gate anything (docs/warlock-tools.md: the two shard sources are trusted
-- for a count only).
--
-- THE SHARD SPY ROWS (F-A, 2026-11-02; the models and the wire went live with
-- H6 and are documented in docs/warlock-tools.md "Open"): the roster's
-- WARLOCK column (`Group:ShardRows`, the `SG1`/`SH1` pair feeding it) rides
-- the plate's extra rows, one per known warlock, sorted by name (the model
-- is deterministic); the second line, row 0, becomes the spy's TOTAL row
-- (the raid's shards over the warlocks that report, the Healthstone Spy's
-- Total-bar law, Forte_Healthstone.lua:197-199), and the right Info slot
-- carries the badge — the warlocks that report in but never answered the
-- shard query (the Healthstone Spy's Amount2, Forte_Healthstone.lua:165).
-- A warlock that never answered prints `?` in her row (the `/fx status`
-- unread law: a value never read is printed, never guessed). The Shard Spy
-- module itself is FE-35 REMOVED (`FX_Saved.Shards = nil; -- module removed`,
-- Forte_Core.lua:1531 — "the removed module has no reference law"), so the
-- geometry is the plate law (the shared ExtraRow run of UI/Frame.lua) and
-- the row cap is the Summon Assistant's `SummonMax` (Forte_Summon.lua:590):
-- five rows, the plate bounded.
--
-- Show law: the plate is on screen while a shard count is KNOWN (`Count()`
-- non-nil) OR the roster lists warlocks (a roster with warlocks is a claim
-- of its own — the Healthstone plate's H6 law; an empty roster is NO claim,
-- so a solo player's plate is bit-for-bit the pre-H6 shape). A count changes
-- on bag events and a roster on chat/roster events, never with time, so this
-- frame never asks the driver for a tick. No read, no roster, nothing to show.
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
    -- The Advanced page's strata row of this plate (the shard plates are
    -- not in the /tmp/fxref snapshot, so the key is ours, named like the
    -- source's own per-module rows: Forte_Soulstone.lua:645).
    advancedKey = "ShardStrata",
    lockKey = "Lock",
    -- CD-30: the plate's right-click opens ITS page (Pages/Warlock.lua's
    -- id, the Shard Manager cell).
    pageId = "ShardManager",
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

-- ----------------------------------------------------------------- the spy --

--- The Shard Spy's row cap: the removed module left no geometry of its own,
--- so the row run is bounded by the Summon Assistant's queue cap (`SummonMax`
--- default 5, Forte_Summon.lua:590) — the plate grows by whole row steps and
--- stops at five rows.
Shards.MAX_ROWS = 5

--- The spy's row-0 label (FWL.TOTAL, Forte_Healthstone/Localization.lua:48,
--- printed by the Healthstone Spy's Total bar, Forte_Healthstone.lua:197).
Shards.TOTAL = "Total"

--- The "this warlock never answered" marker: the `/fx status` `?` law — a
--- value that was never read is printed as unread, never guessed.
Shards.UNREAD = "?"

--- The Group model seam (a Core/Group.lua instance; Core/Comms.lua owns the
--- live one, UI/Module.lua's `_InitViews` binds it, tests inject their own —
--- the Healthstone `SetSpy` convention).
function Shards:SetSpy(group)
    self.Spy = group
    self._count, self._info, self._source = nil, nil, nil
    self._amount, self._frac = nil, nil
end

--- The Shard Spy's rows, one per known warlock (`Group:ShardRows(max)`:
--- the roster's WARLOCK column, sorted by name, so the draw order is
--- deterministic). The reported count rides the row's right label and its
--- bar is the share of the fullest reporting warlock (the row's StatusBar
--- value, HS_DrawHealthstone's `Bar:SetValue(val)`,
--- Forte_Healthstone.lua:148 — the removed Shard Spy left no scale of its
--- own, and a bar is a comparison, which is what the raid's maximum is).
--- A warlock that never answered the query prints the `?` marker at an
--- empty bar.
function Shards:RenderSpyRows(rows)
    local n = 0
    local max = 0
    for _, row in ipairs(rows or {}) do
        if type(row.shards) == "number" and row.shards > max then
            max = row.shards
        end
    end
    for i, row in ipairs(rows or {}) do
        local e = self:ExtraRow(i)
        if e then
            self:SetExtraRowText(e, row.name,
                type(row.shards) == "number" and tostring(row.shards)
                    or self.UNREAD)
            self:SetExtraRowFraction(e,
                (max > 0 and type(row.shards) == "number")
                    and (row.shards / max) or 0)
            n = i
        end
    end
    self:SetExtraRowsShown(n)
end

-- ------------------------------------------------------------- label fit --

--- The right label's VISIBLE slot (the plate's own geometry, the law the
--- engine lays the RIGHT-anchored label box with, measured in the sim
--- 2026-11-02: the box spans exactly 62 of the 106 plate at the default
--- skin): from twice the count label's AmountX offset to the InfoX inset at
--- the plate's right (Forte_Soulstone.xml:135, :144). Default:
--- 106 - 2*18 - 2*4 = 62.
function Shards:InfoSlotWidth()
    local s = self.skin
    return math.max(10, s.Width - 2 * s.AmountX - 2 * math.abs(s.InfoX))
end

--- The width the engine's NATIVE draw font gives a string: a template
--- string (GameFontHighlightSmall) is measured with the engine's built-in
--- font metrics — the exact metrics a TTF-file label is DRAWN with (the
--- sim 2026-11-02 finding: the shipped `0 total` label laid at URWGothic-Book
--- 11 measures 33.1 through GetFontStringWidth, but its draw box is 74.1 —
--- the 106 plate's slot is 62, the tail overruns the plate, and the manager's
--- screenshot rendered `0 tota`). Scaled to a size S the draw box is
--- `drawWidth(text) * S / nativeSize`.
function Shards:_InfoProbe()
    if not self._infoProbe and self.anchor then
        self._infoProbe = self.anchor:CreateFontString(nil, nil,
            "GameFontHighlightSmall")
        self._infoProbe:Hide()
    end
    return self._infoProbe
end

function Shards:InfoDrawWidth(text)
    local probe = self:_InfoProbe()
    if not probe then return nil, nil end
    probe:SetText(tostring(text))
    local dw = probe:GetStringWidth()
    local _, nsize = probe:GetFont()
    return dw, tonumber(nsize)
end

--- The label's font size: the skin's size per the original law
--- (TextSize = the {GOTHIC.TTF, 11} of Forte_Core.lua:2547) when its draw
--- box fits the slot, else the largest size (floor) whose draw box fits.
function Shards:InfoFitSize(text)
    local s = self.skin
    local dw, nsize = self:InfoDrawWidth(text)
    if not dw or not nsize or dw <= 0 then return s.TextSize end
    local fit = math.floor(nsize * self:InfoSlotWidth() / dw)
    return math.max(8, math.min(s.TextSize, fit))
end

--- The plate law's right label (RIGHT at InfoX, Forte_Soulstone.xml:140-146)
--- sized into its slot: the rect carries the slot width (so the laid box
--- ends at InfoX from the plate's right edge) and the text rides the
--- fitted size (so the NATIVE-metric draw box fits the same slot — the
--- 2026-11-02 clip fix; the law is asserted numerically in
--- tests/test_warlock_ui.lua).
function Shards:_NewInfo()
    local fs = Frame._NewInfo(self)
    fs:SetWidth(self:InfoSlotWidth())
    return fs
end

--- ShardSize (keymap SetWidth) resizes the plate: the slot and the fitted
--- size ride it.
function Shards:SizeChangedHook()
    if self.infoFS then
        self.infoFS:SetWidth(self:InfoSlotWidth())
        self:ApplyInfoFont()
    end
end

--- Re-fit the label's font to the current text (the count is the text's
--- only input, so this runs on text changes and on resizes, never per
--- frame — the plate is bag-event-driven and asks no ticks).
function Shards:ApplyInfoFont()
    local fs = self.infoFS
    if not fs then return end
    local size = self:InfoFitSize(fs:GetText())
    pcall(fs.SetFont, fs, self.state.fontFile, size, 0)
end

-- ------------------------------------------------------------------ update --

--- One render pass. Neither a shard count nor a roster is time-driven, so
--- the return is always false (the driver stops ticking on this frame's
--- account).
function Shards:Update(_now)
    local show = false
    local count, source
    local t = self.Tracker
    if t and self:Enabled() then
        -- Count is the pair (count, source): the source label is the
        -- launch-day probe reading that rides the same read.
        count, source = t:Count()
    end
    -- The spy half (F-A): the roster rides the Core/Group.lua model; the
    -- warlocks it lists are a claim the plate must render even with no own
    -- read, and an EMPTY roster is no claim at all (the H6 law of the
    -- Healthstone plate).
    local rows, total
    local spy = self.Spy
    if spy and self:Enabled() then
        rows = spy:ShardRows(self.MAX_ROWS)
        total = spy:ShardTotal()
    end
    local warlocks = (total and total.warlocks) or 0
    if (type(count) == "number")
        or (rows ~= nil and #rows > 0) then show = true end
    self:SetShown(show)
    if not show then
        self:SetExtraRowsShown(0)
        return false
    end
    local n = Frame.FormatAmount(type(count) == "number" and count
        or self.UNREAD)
    if n ~= self._count then
        self._count = n
        self.amountFS:SetText(n)
    end
    -- The right label: with a roster it is the spy's BADGE — the warlocks
    -- that report in but never answered the shard query (the Healthstone
    -- Spy's Amount2 `"x"..active-stones`, Forte_Healthstone.lua:165);
    -- without one it is the own count's `<n> total` (the plate's Info slot,
    -- Forte_Soulstone.xml:140-146).
    local info
    if warlocks > 0 then
        info = "x" .. (warlocks - total.known)
    elseif type(count) == "number" then
        info = self:FormatInfo(count)
    else
        info = ""
    end
    if info ~= self._info then
        self._info = info
        self.infoFS:SetText(info)
        -- The label's size rides its text (the fit law, label fit section).
        self:ApplyInfoFont()
    end
    -- The second line, row 0: with the spy live it is the spy's TOTAL row —
    -- the raid's shards over the warlocks that report (the Healthstone
    -- Spy's Total bar, Forte_Healthstone.lua:197-199 with the value
    -- `t1/t2` at :140); without one it is the source label line (`bag`/
    -- `power`, the ShowTime-owned text keyed by its own text).
    local rowOn, rowName, rowTime, frac
    if warlocks > 0 then
        rowOn = true
        rowName = self.TOTAL
        rowTime = tostring(total.total)
        frac = total.known / warlocks
    else
        local src = source ~= nil and tostring(source) or ""
        rowOn = self.state.showTime and src ~= ""
        rowName = src
        rowTime = ""
        frac = 0
    end
    self:SetRowShown(rowOn)
    if rowOn and rowName ~= self._source then
        self._source = rowName
        self.nameFS:SetText(rowName)
    end
    if rowTime ~= self._amount then
        self._amount = rowTime
        self.timeFS:SetText(rowTime)
    end
    if frac ~= self._frac then
        self._frac = frac
        self:SetFillFraction(frac)
    end
    self:RenderSpyRows(rows)
    self:ApplyTextVisibility()
    return false
end

--- The plate's count and the spy rows are the module's core readout; the
--- Info label and the source second line (the no-spy shape) are the
--- ShowTime-owned text. The spy's TOTAL row is the plate's own readout, so
--- its two labels ride the row, not ShowTime (the Healthstone plate's law).
function Shards:ApplyTextVisibility()
    if not self._shown then return end
    if self.amountFS then self.amountFS:Show() end
    if self.infoFS then
        if self.state.showTime then self.infoFS:Show() else self.infoFS:Hide() end
    end
    if self.nameFS then
        if self._rowShown then self.nameFS:Show() else self.nameFS:Hide() end
    end
    if self.timeFS then
        if self._rowShown and self._amount ~= nil and self._amount ~= "" then
            self.timeFS:Show()
        else
            self.timeFS:Hide()
        end
    end
end

function Shards:RenderIdle()
    self._count, self._info, self._source = nil, nil, nil
    self._amount, self._frac = nil, nil
    self:SetExtraRowsShown(0)
    self:SetRowShown(false)
    self:SetShown(false)
    self.amountFS:SetText("")
    self.infoFS:SetText("")
    self.nameFS:SetText("")
    self.timeFS:SetText("")
end

function Shards:StatusLine()
    local count, source
    if self.Tracker then count, source = self.Tracker:Count() end
    local spy = ""
    if self.Spy then
        local total = self.Spy:ShardTotal()
        spy = string.format(" | spy %d/%d warlocks, %d shards",
            total.known, total.warlocks, total.total)
    end
    return string.format("Shard Manager: %s%s | %dx%d | %s%s",
        type(count) == "number" and tostring(count) or "unread",
        source ~= nil and ("[" .. tostring(source) .. "]") or "",
        self.skin.Width, self.skin.Height,
        self:Enabled() and "on" or "off", spy)
end

--- The injected-tracker seam (tests, launch-day probes).
function Shards:SetTracker(tracker)
    self.Tracker = tracker
    self._count, self._info, self._source = nil, nil, nil
    self._amount, self._frac = nil, nil
end
