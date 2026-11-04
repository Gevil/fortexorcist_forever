-- addon/Forte_Hunter/UI/Melee.lua
-- FX.Hunter.Melee: the opt-in main-hand companion rail (P5, the "is my
-- main-hand swing up -- the Raptor Strike reset reward" glance,
-- docs/research/wst-swing-design.md §7.5, slice §7.8 β). A PURE RENDERER
-- of FX.Hunter.MeleeCore.Tracker:Progress() (Core/Melee.lua owns every
-- event and every number); this file reads no unit API.
--
-- Skin law (the FX.Hunter.RangeLight strip this rail sits in the family
-- of, Forte_Cooldown/UI/Timeline.lua law): the Background/Border backdrop
-- pair, the Aluminium fill, URW Gothic 10 OUTLINE text; the frame is
-- created inside Init (run from the module's OnEnable / OnClassChanged /
-- SetEnabled -- never at file load); every style setter is dirty-checked;
-- the OnUpdate ticker exists ONLY while the rail is on screen (a hidden
-- frame gets no OnUpdate -- show transitions render synchronously from
-- the Core/Melee.lua event kicks). Click-through chrome (EnableMouse
-- false, SetMovable false) like the range light and the Reminder: no
-- handle of its own, it rides the bar's drag through the anchor chain.
--
-- Geometry (the §7.5 rail law): same width as the swing bar, 8 px tall,
-- anchored TOPLEFT at -4 under its stack neighbour (the UI/Range.lua
-- precedent -- with the light on: under the light, giving the vertical
-- order bar -> light -> rail, each anchored off the swing bar, so one
-- drag moves all three; with the light off: directly under the bar). The
-- fill is TOPLEFT-anchored and grows left -> right; FULL = THE SWING IS
-- READY (the one reading -- no fill_empty toggle, no spark, no off-hand
-- row: the §7.5 non-goals); a tenths text rides the right end.
--
-- THE GATE (§7.5, behaviour not option): the rail draws ONLY while in
-- combat AND (the range light is off, OR the light is on and its meter
-- reads the `melee` band). Auto Shot needs >= 8 yd, Raptor Strike and
-- Mongoose Bite <= 5 (spells.jsonl Auto Shot MinRange=8, Raptor/Mongoose
-- MaxRange=5), so the rail's information is actionably true only inside
-- the melee band; at 30 yd it is noise. Out of that and out of combat:
-- hidden, no ticker. The option is the rail itself: EnableMeleeRail
-- (default OFF): off = NO frame, NO ticker, NO event registration
-- (§7.8 β -- Core/Melee.lua's events ride SetEnabled).
--
-- The fill colour is the swing bar's own BarColor read at Init (one
-- truth, no drift -- the Pages/Hunter.lua DEFAULTS precedent): the rail
-- is the bar's companion, not a new signal family.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Hunter = FX.Hunter or {}

local D = {}
FX.Hunter.Melee = D

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"
local FONT_FILE = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"

--- The bar's current fill colour (one truth); the verbatim Spell triple
--- is the fallback when the bar's skin is not loaded (the RangeLight
--- BandColor / Pages DEFAULTS precedent).
local function barFillColor()
    local skin = FX.Hunter.SwingSkin
    local c = skin and skin.BarColor
    if type(c) == "table" and type(c[1]) == "number" then
        return { c[1], c[2], c[3], c[4] or 1 }
    end
    return { 1, 0.5, 0, 1 }
end

FX.Hunter.MeleeSkin = {
    Height = 8,                                 -- the §7.5 rail height
    BackdropBG = TEX .. "Background",
    BackdropEdge = TEX .. "Border",
    BackdropTile = false,
    BackdropTileSize = 16,
    BackdropEdgeSize = 5,
    Inset = 2,                                  -- the RangeLight strip inset
    BgColor = { 0, 0, 0, 0.50 },
    BarTexture = TEX .. "Aluminium",
    TextColor = { 1, 1, 1, 0.90 },
    FontFile = FONT_FILE,
    FontSize = 10,
    FontFlags = "OUTLINE",
}
local S = FX.Hunter.MeleeSkin

local TICK_SECONDS = 0.1                        -- the 10 Hz display law

--- The module's live state. EnableMeleeRail defaults OFF (§7.5: the
--- option is the rail; off = no frame, no ticker, no events).
D.state = { enabled = false }
local ST = D.state

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

--- Remaining seconds as tenths (a swing is always < 60 s -- the
--- Swing bar's formatRemaining law at its one relevant branch).
function D.FormatRemaining(remaining)
    return string.format("%.1f", remaining)
end

-- ------------------------------------------------------------------- init --
--- The off law: no frame is built at all while the rail is disabled
--- (§7.8 β). SetEnabled(true) runs Init -- the frame arrives with the
--- module's defaults, like every setter-before-store seam.
function D:Init()
    if self.anchor then return end
    if not ST.enabled then return end
    self.Tracker = self.Tracker
        or (FX.Hunter.MeleeCore and FX.Hunter.MeleeCore.Tracker)
    self.Meter = self.Meter or FX.Hunter.RangeMeter
    local bar = FX.Hunter.Swing
    self._w = (bar and bar.anchor and bar.anchor:GetWidth()) or 200
    self.fontFile = validateFontFile(S.FontFile)

    local f = CreateFrame("Frame", "ForteXorcistHunterMeleeAnchor", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(self._w, S.Height)
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
    -- Click-through chrome (the range light / Reminder law): no handle,
    -- it rides the swing bar's drag through the anchor chain.
    f:EnableMouse(false)
    f:SetMovable(false)

    -- The fill: TOPLEFT-anchored, grows left -> right, full = ready.
    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(S.BarTexture)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    fill:SetSize(0, S.Height)
    local c = self._color or barFillColor()
    self._color = c
    fill:SetVertexColor(c[1], c[2], c[3], c[4])

    -- The remaining-seconds text, right-aligned at the rail's right end.
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if self.fontFile then
        pcall(text.SetFont, text, self.fontFile, S.FontSize, S.FontFlags)
    end
    text:SetJustifyH("RIGHT")
    text:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    local tc = S.TextColor
    text:SetTextColor(tc[1], tc[2], tc[3], tc[4])
    text:SetText("")

    self.anchor, self.fill, self.text = f, fill, text
    self._shown, self._fillW, self._timeKey = false, nil, nil

    self:_ApplyAnchor()
    f:Hide()
end

--- The injected-tracker seam (tests, later gear models).
function D:SetTracker(tracker)
    self.Tracker = tracker
    self._fillW, self._timeKey = nil, nil
end

--- The injected-meter seam (tests; §7.8 β acceptance 5's gate rides it).
function D:SetMeter(m)
    self.Meter = m
end

-- -------------------------------------------------------------- anchoring --
--- The rail's stack neighbour: with the range light ON the rail rides
--- under the light (the vertical order bar -> light -> rail), with it
--- off directly under the bar. Both frames are themselves anchored off
--- the swing bar, so one drag moves the whole stack.
function D:_AnchorTarget()
    local light = FX.Hunter.RangeLight
    if light and light.state and light.state.enabled and light.anchor then
        return light.anchor
    end
    return FX.Hunter.Swing and FX.Hunter.Swing.anchor
end

--- (Re-)plant the rail. Chosen at every show transition, so the light's
--- live enable/disable retargets the stack with no hook on the light.
function D:_ApplyAnchor()
    local f = self.anchor
    if not f then return end
    local target = self:_AnchorTarget()
    f:ClearAllPoints()
    if target then
        f:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -4)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -171)
    end
end

-- ------------------------------------------------------------------ gate --
--- InCombatLockdown (CAT, RestrictedActionsDocumentation.lua:44) through
--- the injectable seam; a raising/absent read is "no knowledge" = closed
--- (the rail draws only on a proven combat fact).
function D:_InCombat()
    local reader = self.combatReader
    if reader == nil and type(InCombatLockdown) ~= "function" then
        return nil
    end
    local ok, v
    if reader then ok, v = pcall(reader)
    else ok, v = pcall(InCombatLockdown) end
    if not ok then return nil end
    v = FX.Compat.PlainOrNil(v)
    if v == true or v == 1 then return true end
    if v == false or v == 0 then return false end
    return nil
end

--- The §7.5 gate: draws iff in combat AND (the light is off, OR the
--- light is on and its meter reads `melee`), AND the clock is neither
--- parked nor idle. The meter's nil band (no target / dead / no
--- knowledge) is not the melee band: closed.
function D:_GateOpen()
    if self:_InCombat() ~= true then return false end
    local light = FX.Hunter.RangeLight
    if light and light.state and light.state.enabled then
        local meter = self.Meter
        if not (meter and meter.GetBand) then return false end
        local ok, band = pcall(meter.GetBand, meter)
        if not ok or band ~= "melee" then return false end
    end
    local t = self.Tracker
    return (t ~= nil) and (not t.parked)
end

-- ---------------------------------------------------------------- render --
--- One render pass. Returns true when the rail is on screen. Show
--- transitions render synchronously (the hidden-frame law), which is why
--- the anchor is re-planted right before a Show.
function D:Refresh()
    if not self.anchor then return false end
    if not ST.enabled then
        self:HideNow()
        return false
    end
    if not self:_GateOpen() then
        self:HideNow()
        return false
    end
    local tracker = self.Tracker
    local fraction, remaining = tracker:Progress()
    if fraction == nil then
        -- No clock (idle): the rail has nothing to say (the idle law).
        self:HideNow()
        return false
    end
    if not self._shown then
        self._shown = true
        self:_ApplyAnchor()
        self.anchor:Show()
    end
    local W = self._w or 200
    local w = fraction * W
    if w < 0 then
        w = 0
    elseif w > W then
        w = W
    end
    if self._fillW ~= w then
        self._fillW = w
        self.fill:SetSize(w, S.Height)
    end
    local key = math.floor(remaining * 10 + 0.5)
    if self._timeKey ~= key then
        self._timeKey = key
        self.text:SetText(D.FormatRemaining(remaining))
    end
    self:StartTicking()
    return true
end

function D:HideNow()
    if self._shown ~= false then
        self._shown = false
        if self.anchor then self.anchor:Hide() end
    end
    -- No stale number on a hidden rail (runs on the show transition too).
    if self.text and self._timeKey ~= nil then
        self._timeKey = nil
        self.text:SetText("")
    end
    self._fillW = nil
    if self.fill and self.anchor and self.fill.SetSize then
        -- Park the fill at empty, dirty-checked through _fillW.
        self.fill:SetSize(0, S.Height)
    end
    self:StopTicking()
end

-- ----------------------------------------------------------------- ticker --
--- The 10 Hz script exists ONLY while the rail is on screen.
function D:StartTicking()
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
        -- The gate rides every pass: the range band leaving `melee` and
        -- the out-of-combat edge hide the rail within a tick, no ticker
        -- surviving them (the idle law).
        if not self:Refresh() then self:StopTicking() end
    end)
    -- The hidden-frame law: a shown-during-this-pass frame renders
    -- itself (Refresh is what just showed the anchor).
    self:Refresh()
end

function D:StopTicking()
    if not self._ticking then return nil end
    self._ticking = false
    if self.anchor then self.anchor:SetScript("OnUpdate", nil) end
end

-- ----------------------------------------------------------------- seams --
--- The Core/Melee.lua event kick ("the clock / the gate may have
--- moved"). Payloads are Core's, never touched here.
function D:OnTrackerEvent()
    if ST.enabled then self:Refresh() end
end

--- Settings: EnableMeleeRail (the §7.5 opt-in) + Width (same width as
--- the swing bar; γ routes both through this seam and ApplyStoredSettings
--- re-applies them at login -- the STORED law).
function D:SetEnabled(on)
    on = not not on
    if on == ST.enabled then
        -- Idempotent re-enable (login / class entry): keep the frame,
        -- the anchor and the render consistent.
        if on then
            self:Init()
            self:_ApplyAnchor()
            self:Refresh()
        end
        return
    end
    ST.enabled = on
    local core = FX.Hunter.MeleeCore
    if core and core.RefreshEvents then core:RefreshEvents() end
    if on then
        self:Init()
        self:_ApplyAnchor()
        self:Refresh()
    else
        self:HideNow()
    end
end

function D:SetWidth(w)
    if type(w) ~= "number" or w <= 0 then return end
    self._w = w
    if self.anchor then
        self.anchor:SetSize(w, S.Height)
        -- The fill keeps its current fraction under the new numbers.
        self._fillW = nil
        self.fill:SetSize(0, S.Height)
        if self._shown then self:Refresh() end
    end
end

function D:ApplySettings(tbl)
    for key, value in pairs(tbl or {}) do
        if key == "EnableMeleeRail" then self:SetEnabled(value)
        elseif key == "Width" then self:SetWidth(value) end
    end
end

function D:ApplyStoredSettings()
    local st = FX.Settings
    if not st or not st.IsRegistered or not st:IsRegistered("Hunter") then
        return
    end
    self:ApplySettings({
        EnableMeleeRail = st:Get("Hunter", "EnableMeleeRail"),
        Width = (FX.Hunter.Swing and FX.Hunter.Swing.anchor
            and FX.Hunter.Swing.anchor:GetWidth()),
    })
end

function D:_WireSettings()
    local st = FX.Settings
    if not st or not st.OnChange or self._wired then return end
    self._wired = true
    st:OnChange("Hunter", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
end

-- ------------------------------------------------------------- lifecycle --
--- The HUNTER entry (login / class change): seed from the store, wire,
--- and build only when the rail is enabled (the off law: no frame).
function D:EnableForClass()
    self:ApplyStoredSettings()
    self:_WireSettings()
    if ST.enabled then
        self:Init()
        self:_ApplyAnchor()
        self:Refresh()
    end
end

function D:OnEnable()
    -- Hunters only (the shared /fx bootstrap runs OnEnable for every
    -- player class; the test law drives EnableForClass directly).
    if FX._playerClass ~= "HUNTER" then return end
    self:EnableForClass()
end

--- Core FX.RefreshPlayerClass notification (the uiforever T4 class
--- guard).
function D:OnClassChanged(classFile)
    if classFile == "HUNTER" then
        self:EnableForClass()
    else
        self:HideNow()
    end
end

function D:StatusLine()
    local fraction
    local t = self.Tracker
    if t and t.Progress then fraction = t:Progress() end
    return string.format("Melee rail: %s | %s | fill=%s | light=%s",
        self._shown and "shown" or "hidden",
        fraction and string.format("%.0f%%", fraction * 100) or "idle",
        tostring(self._fillW),
        (FX.Hunter.RangeLight and FX.Hunter.RangeLight.state
            and FX.Hunter.RangeLight.state.enabled) and "on" or "off")
end

--- `/fx status` integration: prints its own line (the Core status law).
function D:Status()
    FX.Print(D:StatusLine())
end

FX.RegisterModule("HunterMeleeUI", D)
