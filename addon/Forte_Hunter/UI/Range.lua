-- addon/Forte_Hunter/UI/Range.lua
-- FX.Hunter.RangeLight: the slim range / dead-zone strip under the swing
-- bar (docs/research/weaponswingtimer.md §5, the "range / dead-zone light"
-- of PLAN Phase 3; the band law is Core/Range.lua's RangeMeter -- this
-- file is a PURE RENDERER, no frame reads a unit API; every band value
-- arrives through the meter).
--
-- Skin law (the Forte_Cooldown/UI/Timeline.lua law this bar family
-- follows): the Background/Border backdrop pair, URW Gothic 10 OUTLINE,
-- the Timeline category colours; frames are created inside Init (from the
-- UI module's OnEnable / OnClassChanged), never at file load; every style
-- setter is dirty-checked; the OnUpdate ticker exists ONLY while the
-- strip is on screen (a hidden frame gets no OnUpdate -- show transitions
-- render synchronously from the event kicks, Swing.lua's hidden-anchor
-- law).
--
-- The band colours ride the Forte_Cooldown Timeline category colours
-- (FX.Cooldown.TimelineSkin.Colors -- Spell/Powerup/Item/Potion/Buff/
-- Debuff), the verbatim triples are the fallback when that OptionalDep is
-- not loaded (the SwingSkin.BarColor precedent -- one truth, no drift).
--
-- Opt-in: ShowRangeLight defaults OFF (the WST opt-in law,
-- WeaponSwingTimer_Range.lua:549-552). Showing it enables the native
-- swing range check (C_SwingTimer.EnableRangeCheck(Ranged, true), CAT-
-- declared, pcall-guarded -- docs/hunter-tools.md probe 7) so
-- PLAYER_SWING_RANGE_UPDATE starts carrying checksRange=true; hiding it
-- disables the check again.
--
-- Position: anchored to the swing bar (BOTTOMLEFT under TOPLEFT, -4 px),
-- same width as the bar -- it moves with the bar; no own drag handle
-- (click-through chrome like the Reminder).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Hunter = FX.Hunter or {}

local R = {}
FX.Hunter.RangeLight = R

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"
local FONT_FILE = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"

local function skinColors()
    local skin = FX.Cooldown and FX.Cooldown.TimelineSkin
    return skin and skin.Colors
end
local function category(name, fallback)
    local c = skinColors()
    c = c and c[name]
    if type(c) == "table" and type(c[1]) == "number" then
        return { c[1], c[2], c[3], c[4] or 1 }
    end
    return fallback
end

FX.Hunter.RangeSkin = {
    Height = 8,
    BackdropBG = TEX .. "Background",
    BackdropEdge = TEX .. "Border",
    BackdropTile = false,
    BackdropTileSize = 16,
    BackdropEdgeSize = 5,
    Inset = 2,
    BgColor = { 0, 0, 0, 0.50 },
    FontFile = FONT_FILE,
    FontSize = 10,
    FontFlags = "OUTLINE",
    TextColor = { 1, 1, 1, 0.90 },
    OffAlpha = 1.0,
    Bands = {
        melee    = { r = "Debuff",  d = { 1, 0, 0, 1 } },       -- red
        deadzone = { r = "Item",    d = { 1, 1, 0, 1 } },       -- yellow
        close    = { r = "Spell",   d = { 1, 0.5, 0, 1 } },     -- orange
        ranged   = { r = "Potion",  d = { 0, 1, 0, 1 } },       -- green
        far      = { r = "Powerup", d = { 0, 0.75, 1, 1 } },    -- cyan
        out      = { r = nil,       d = { 0.55, 0.55, 0.55, 1 } }, -- grey
    },
}
local S = FX.Hunter.RangeSkin

local TICK_SECONDS = 0.1                      -- the 10 Hz display law

R.state = { enabled = false }
local ST = R.state

--- The band's colour table (Timeline category, fallback default). Cache
--- keyed by the band name so a category colour change follows the skin.
local colorCache
local function bandColor(band)
    local spec = S.Bands[band]
    if not spec then return S.Bands.out.d end
    colorCache = colorCache or {}
    local c = colorCache[band]
    if c and c.resolved == skinColors() then return c.color end
    local col = spec.r and category(spec.r, spec.d) or spec.d
    colorCache[band] = { resolved = skinColors(), color = col }
    return col
end
R.BandColor = bandColor

local function validateFontFile(path)
    if type(path) ~= "string" or path == "" then return nil end
    local okCreate, fontObj = pcall(CreateFont, path, S.FontSize)
    if not okCreate or not fontObj then return nil end
    local probe = UIParent:CreateFontString(nil, "OVERLAY")
    if not probe then return nil end
    local okSet = pcall(probe.SetFont, probe, path, S.FontSize)
    local got = okSet and probe:GetFont()
    probe:Hide()
    if type(got) == "string" and got:lower() == path:lower() then
        return path
    end
    return nil
end

-- ------------------------------------------------------------------- init --
function R:Init()
    if self.anchor then return end
    self.Meter = self.Meter or FX.Hunter.RangeMeter
    local bar = FX.Hunter.Swing
    local parent = (bar and bar.anchor) or UIParent

    local f = CreateFrame("Frame", "ForteXorcistHunterRangeAnchor", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    local w = (bar and bar.anchor and bar.anchor:GetWidth()) or 200
    f:SetSize(w, S.Height)
    if f.SetBackdrop then
        local ins = S.Inset
        f:SetBackdrop({
            bgFile = S.BackdropBG,
            edgeFile = S.BackdropEdge,
            tile = S.BackdropTile,
            tileSize = S.BackdropTileSize,
            edgeSize = S.BackdropEdgeSize,
            insets = { left = ins, right = ins, top = ins, bottom = ins },
        })
        local bg = S.BgColor
        f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        f:SetBackdropBorderColor(bg[1], bg[2], bg[3], bg[4])
    end
    f:SetClampedToScreen(true)
    f:EnableMouse(false)
    f:SetMovable(false)
    -- Under the swing bar, same width; follows the bar's drag (the anchor
    -- is the bar frame itself -- the bar re-anchors via SetPoint, which
    -- moves anchored children).
    if parent ~= UIParent then
        f:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -4)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -159)
    end

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.fontFile = validateFontFile(S.FontFile)
    if self.fontFile then
        pcall(text.SetFont, text, self.fontFile, S.FontSize, S.FontFlags)
    end
    text:SetJustifyH("CENTER")
    text:SetPoint("CENTER", f, "CENTER", 0, 0)
    local tc = S.TextColor
    text:SetTextColor(tc[1], tc[2], tc[3], tc[4])
    text:SetText("")

    self.anchor, self.text = f, text
    self._band, self._text, self._shown = nil, nil, false

    f:Hide()
end

--- The injected-meter seam (tests).
function R:SetMeter(m)
    self.Meter = m
    self._band, self._text = nil, nil
end

--- EnableRangeCheck around the light's lifetime (CAT-declared,
--- pcall-guarded; the probe-gated launch behaviour rides it, hunter-tools
--- probe 7).
---
--- THE ONE CLIENT-WIDE SIDE EFFECT IN THE HUNTER'S UI (code-review-5 m11):
--- the call is the game's own switch for ranged swing-range checking, so
--- while the light is enabled the CLIENT range-checks the swing, not just
--- our meter. Accepted because the option is opt-in (default OFF), the pair
--- closes on the same seam (`SetEnabled`), and the tip says it; the live
--- proof is launch-day check F17 in docs/launch-day.md, which measures the
--- effect on the client's own Auto Shot cycle in both directions.
local function enableRangeCheck(on)
    -- One owner of the client switch (Core/Tools.lua's request table): the
    -- swing tracker holds the "swing" request from EnableEvents, the light
    -- holds this one, and the check rides the union -- the light's law
    -- (shown = checked, hidden = unchecked) is unchanged by the routing.
    local T = FX.Hunter.Tools
    if T and T.RequestRangeCheck then
        T.RequestRangeCheck("light", on)
        return
    end
    local ok, t = pcall(function()
        local e = _G.Enum and _G.Enum.PlayerSwingType
        return FX.Compat.PlainOrNil(e and e.Ranged)
    end)
    if not ok or type(t) ~= "number" then return end
    if _G.C_SwingTimer and _G.C_SwingTimer.EnableRangeCheck then
        pcall(_G.C_SwingTimer.EnableRangeCheck, t, on and true or false)
    end
end

-- ---------------------------------------------------------------- render --
--- Re-read the meter and show/hide. Returns true when the strip is on
--- screen. Show transitions render synchronously (the hidden-frame law).
function R:Refresh()
    if not self.anchor then return false end
    if not ST.enabled then
        self:HideNow()
        return false
    end
    local meter = self.Meter
    local band, text
    if meter and meter.GetBand then
        local ok, b, t = pcall(meter.GetBand, meter)
        if ok then band, text = b, t end
    end
    if band == nil then
        self:HideNow()
        return false
    end
    if not self._shown then
        self._shown = true
        self.anchor:Show()
    end
    if self._band ~= band then
        self._band = band
        local c = bandColor(band)
        if self.anchor.SetBackdropColor then
            self.anchor:SetBackdropColor(c[1], c[2], c[3], c[4] * 0.75)
            self.anchor:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
        end
    end
    local shown = tostring(text or "")
    if self._text ~= shown then
        self._text = shown
        self.text:SetText(shown)
    end
    self:StartTicking()
    return true
end

function R:HideNow()
    if self._shown ~= false then
        self._shown = false
        if self.anchor then self.anchor:Hide() end
        self._band, self._text = nil, nil
    end
    self:StopTicking()
end

function R:SetWidth(w)
    if not self.anchor then return end
    if type(w) == "number" and w > 0 then
        self.anchor:SetSize(w, S.Height)
    end
end

-- ----------------------------------------------------------------- ticker --
function R:StartTicking()
    if not self.anchor or self._ticking then return end
    self._ticking = true
    self._acc = 0
    self.anchor:SetScript("OnUpdate", function(_, elapsed)
        local acc = (self._acc or 0) + (tonumber(elapsed) or 0)
        if acc < TICK_SECONDS then
            self._acc = acc
            return
        end
        self._acc = 0
        if not self:Refresh() then self:StopTicking() end
    end)
    -- The hidden-frame law: a shown-during-this-pass frame renders itself.
    self:Refresh()
end

function R:StopTicking()
    if not self._ticking then return end
    self._ticking = false
    if self.anchor then self.anchor:SetScript("OnUpdate", nil) end
end

-- ------------------------------------------------------------ live settings --
function R:SetEnabled(on)
    on = not not on
    if on == ST.enabled then return end
    ST.enabled = on
    enableRangeCheck(on)
    self:Refresh()
end

function R:ApplySettings(tbl)
    for key, value in pairs(tbl or {}) do
        if key == "ShowRangeLight" then self:SetEnabled(value)
        elseif key == "Width" then self:SetWidth(value) end
    end
end

function R:ApplyStoredSettings()
    local st = FX.Settings
    if not st or not st.IsRegistered or not st:IsRegistered("Hunter") then
        return
    end
    self:ApplySettings({
        ShowRangeLight = st:Get("Hunter", "ShowRangeLight"),
        Width = (FX.Hunter.Swing and FX.Hunter.Swing.anchor
            and FX.Hunter.Swing.anchor:GetWidth()),
    })
end

function R:_WireSettings()
    local st = FX.Settings
    if not st or not st.OnChange or self._wired then return end
    self._wired = true
    st:OnChange("Hunter", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
end

--- The event kick surface: "the range state may have moved" (target
--- change, combat edges, zone-in, casts). Payloads arrive UNREAD.
function R:OnStateEvent()
    self:Refresh()
end

function R:OnClassChanged(classFile)
    if classFile == "HUNTER" then
        self:Init()
        self:Refresh()
    elseif self.anchor then
        self:HideNow()
        self.anchor:Hide()
        self._shown = false
    end
end

function R:StatusLine()
    return string.format("Range light: %s | band=%s | %s",
        self._shown and "shown" or "hidden",
        tostring(self._band), ST.enabled and "on" or "off")
end
