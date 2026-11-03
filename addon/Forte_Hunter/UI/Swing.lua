-- addon/Forte_Hunter/UI/Swing.lua
-- FX.Hunter.Swing: the Auto Shot / ranged-swing bar (TWO-PHASE since swing
-- v2: the safe-window fill + the aim/retry/cast slices + the white
-- projectile-left state), plus the UI module ("HunterUI") that owns the
-- Hunter frames' lifecycle. The bar is a thin Classic skin strip (the
-- Forte_Cooldown/UI/Timeline.lua law: Aluminium fill on the
-- Background/Border backdrop, URW Gothic text). All swing STATE lives in
-- Core/Tools.lua's SwingTracker; this file is a pure renderer of
-- `FX.Hunter.Tools.Swing:Progress(now)` + `:CycleState(now)` +
-- `:CastRemaining(now)` (PLAN §3.4 "pure renderer, 10 Hz display",
-- §3.6 module map; the gap table of docs/research/weaponswingtimer.md).
--
-- Frame + skin law (Forte_Cooldown/UI/Timeline.lua):
--   * frames are created inside Init, which runs from the module's OnEnable
--     (PLAYER_LOGIN) or an OnClassChanged handler -- never at file load
--     (Forte_Core/Core/Init.lua's taint rule);
--   * every style setter is dirty-checked, the pass runs at 10 Hz;
--   * the lock convention (m4): SetLocked publishes the state into
--     FX.Settings (module "Hunter", key "Lock", guarded by
--     store-inequality so a listener calling back stops there) and locking
--     flips SetMovable only -- the mouse stays live, the source's law (the
--     lock gates the drag start, FW_StartMoving Forte_Core/Options.lua:651,
--     never the mouse) so the right-click options release (CD-30) works on a
--     locked bar. `/fx lock|unlock` runs
--     FX.Cooldown.Display:SetLocked, which publishes Cooldown.Lock and
--     General.GlobalLock -- that publish IS the lock-change hook, so the
--     Hunter bar follows it by mirroring those two keys through
--     FX.Settings:OnChange; no Forte_Cooldown change is needed.
--   * position lives in FX.db.hunterSwing (point/relPoint/x/y/locked).
--
-- Update law: the OnUpdate script exists ONLY while a swing runs
-- (SetScript("OnUpdate", fn) when a swing event arrives, SetScript
-- ("OnUpdate", nil) the moment the tracker reports idle) -- an idle bar
-- costs no per-frame work. The script accumulates elapsed time and renders
-- at 10 Hz, never every frame.
--
-- Settings (module "Hunter", defaults registered by
-- Forte_Hunter/Pages/Hunter.lua when Forte_Options is loaded; every setter
-- here is legal BEFORE the store exists -- the module keeps its own skin
-- defaults): Enable, Width, Height, BarColor, BgColor, ShowTime, Lock, plus
-- the General page's shared BarFont (the bar's text rides the same file the
-- Cooldown bar rides).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Hunter = FX.Hunter or {}

local D = {}
FX.Hunter.Swing = D

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"
local FONT_FILE = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"

--- The fill's design default: the Forte_Cooldown timeline's Spell category
--- colour at FULL alpha, read off the Display's skin
--- (FX.Cooldown.TimelineSkin.Colors.Spell, the vendored source default
--- :1842-1855). Forte_Cooldown is an OptionalDep, so the verbatim Spell
--- triple (1, 0.5, 0) is the fallback when its skin is not loaded -- the two
--- are the same numbers. The 1,1,1 a 0.20 this replaces (polish pass
--- 2026-11-02) was a near-invisible wash over the Aluminium texture.
local function spellBarColor()
    local skin = FX.Cooldown and FX.Cooldown.TimelineSkin
    local c = skin and skin.Colors and skin.Colors.Spell
    if type(c) == "table" and type(c[1]) == "number" then
        return { c[1], c[2], c[3], 1 }
    end
    return { 1, 0.5, 0, 1 }
end

FX.Hunter.SwingSkin = {
    Width = 200, Height = 12,                 -- the assignment's bar
    BackdropBG = TEX .. "Background",         -- the Timeline's Backdrop[1]
    BackdropEdge = TEX .. "Border",           -- the Timeline's Backdrop[2]
    BackdropTile = false,
    BackdropTileSize = 16,
    BackdropEdgeSize = 5,                     -- the Timeline's Backdrop[5]
    Inset = 3,                                -- the Timeline's Backdrop[6]
    BgColor = { 0, 0, 0, 0.50 },              -- Classic black a 0.50
    BarTexture = TEX .. "Aluminium",          -- FW.Default.Texture
    BarColor = spellBarColor(),               -- the Cooldown timeline's
                                              -- Spell category colour at
                                              -- full alpha (Init re-reads
                                              -- it, see below)
    TextColor = { 1, 1, 1, 0.90 },
    FontFile = FONT_FILE,
    FontSize = 10,                            -- the assignment: font 10
    FontFlags = "OUTLINE",
    -- The two-phase palette (docs/research/weaponswingtimer.md §5): the
    -- Forte_Cooldown Timeline category colours -- aim window = Debuff red,
    -- projectile-left = Buff white, retry = Item yellow, the flight pulse
    -- rides the Spark2 ADD-blend law (Timeline's PulseSeconds = 1.0,
    -- linear 1->0 alpha, no wave).
    AimColor = { 1, 0, 0, 1 },
    FlyingColor = { 1, 1, 1, 1 },
    RetryColor = { 1, 1, 0, 1 },
    SparkTexture = TEX .. "Spark2",
    PulseSeconds = 1.0,
    InCombatAlpha = 1.0,                      -- the WST in/ooc alpha pair
    OutOfCombatAlpha = 1.0,                   -- (parked VISIBLE: the bar
                                              --  already hides when idle
                                              --  -- the alpha pair, gap
                                              --  row 10)
}
local S = FX.Hunter.SwingSkin

local DEFAULT = { point = "CENTER", relPoint = "CENTER", x = 0, y = -175,
    locked = true }
local TICK_SECONDS = 0.1                      -- the 10 Hz render rate

-- The module's live skin state: the setters are legal before Init (the
-- options page applies stored values at PLAYER_LOGIN; the frames arrive
-- with them) -- Timeline.frameState's shape.
D.state = { enabled = true, showTime = true,
    -- swing v2 draw gates (the Hunter page keys; docs/research/
    -- weaponswingtimer.md gap row 10).
    showSafeWindow = true,   -- off = today's single-phase bar (the law)
    showAimSlice = true,
    showFlying = true,
    showRetry = true,
    showLatency = false,     -- the GetNetStats leg is a launch probe (§B12)
}
local ST = D.state

-- ------------------------------------------------------------------- font --
--- The shipped-file validator (the Timeline's / the Widgets' round trip:
--- CreateFont + SetFont on a throwaway string, accepted only when GetFont
--- returns the file back). Rejection keeps every string on the
--- GameFontHighlightSmall template it was created with.
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

local function applyFont(fs, size, flags)
    local key = (D.fontFile or "tpl") .. "|" .. tostring(size) .. "|" .. (flags or "")
    if fs._font == key then return end
    local ok = false
    if D.fontFile then
        ok = pcall(fs.SetFont, fs, D.fontFile, size, flags)
        if ok then ok = (fs:GetFont()) == D.fontFile end
    end
    if not ok then
        pcall(fs.SetFontTemplate, fs, "GameFontHighlightSmall")
        key = nil
    end
    fs._font = key
end

--- Remaining seconds as text: m:ss at >= 60, tenths below (the Timeline's
--- formatRemaining law). A swing is always < 60 s, so the bar prints
--- tenths ("1.0", "0.3").
local function formatRemaining(remaining)
    if remaining >= 60 then
        return string.format("%d:%02d", math.floor(remaining / 60),
            math.floor(remaining % 60))
    end
    return string.format("%.1f", remaining)
end
D.FormatRemaining = formatRemaining

--- The identity of the displayed text (the Timeline's timeKey): the render
--- pass compares this int, so a tick with an unchanged visible value costs
--- no string.format and no SetText.
local function timeKey(remaining)
    if remaining >= 60 then return math.floor(remaining) end
    return math.floor(remaining * 10 + 0.5)
end

-- ------------------------------------------------------------- persistence --
local fallbackCfg
local function config()
    if FX.db then
        FX.db.hunterSwing = FX.db.hunterSwing or {}
        return FX.db.hunterSwing
    end
    fallbackCfg = fallbackCfg or {}
    return fallbackCfg
end

local function cfgDefaults(cfg)
    for k, v in pairs(DEFAULT) do
        if cfg[k] == nil then cfg[k] = v end
    end
    return cfg
end

-- ------------------------------------------------------------------- init --
function D:Init()
    if self.anchor then return end
    self.cfg = cfgDefaults(config())
    self.fontFile = validateFontFile(S.FontFile)
    -- Forte_Cooldown is an OptionalDep: at file load its skin may not exist
    -- yet (the loader is free to run Forte_Hunter first), by PLAYER_LOGIN it
    -- does -- so this is where the shared Spell tint is really read. An
    -- explicit SetBarColor (the options page applying a stored value: the
    -- setters are legal before Init) wins over the skin default.
    if not self._barColorSet then S.BarColor = spellBarColor() end
    self.Tracker = self.Tracker or (FX.Hunter.Tools and FX.Hunter.Tools.Swing)

    local f = CreateFrame("Frame", "ForteXorcistHunterSwingAnchor", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(S.Width, S.Height)
    if f.SetBackdrop then
        local bd, ins = S.BackdropEdgeSize, S.Inset
        f:SetBackdrop({
            bgFile = S.BackdropBG,
            edgeFile = S.BackdropEdge,
            tile = S.BackdropTile,
            tileSize = S.BackdropTileSize,
            edgeSize = bd,
            insets = { left = ins, right = ins, top = ins, bottom = ins },
        })
        local bg = S.BgColor
        f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        f:SetBackdropBorderColor(bg[1], bg[2], bg[3], bg[4])
    end
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- CodeReview6 M2: the source stamps EVERY press (`<OnMouseDown>
    -- FW:StartMoving(self,button)`, Forte_Soulstone.xml:189-191). The
    -- engine fires OnDragStart only for the REGISTERED drag button, so a
    -- stamp riding only OnDragStart leaves the right-press unstamped:
    -- after one left-drag every later right-click compares against the
    -- stale stamp and reads as "moved" -- the seam dies. The press stamp
    -- rides OnMouseDown (any button); the OnDragStart stamp stays (the
    -- sim's rigs drive that script directly).
    f:SetScript("OnMouseDown", function() self:_StampPress() end)
    f:SetScript("OnDragStart", function(fr, button)
        -- FW:StartMoving (Forte_Core/Options.lua:649-656) stamps the cursor
        -- at press; FW:Moved() (:659-662) is the release-time compare that
        -- makes the right-click's CD-30 law skip a drag. The stamp is taken
        -- BEFORE the lock is read (the source's order at :650-651), and the
        -- lock gates the DRAG START only (:651
        -- `if not FW:IsLocked(frame) and button=="LeftButton" ...`): a
        -- locked bar keeps the mouse, so its right-button release still
        -- reaches the seam below (the Forte_Soulstone law, SSFrame_OnClick
        -- + Forte_Soulstone.xml:189-196).
        self:_StampPress()
        if self.cfg and self.cfg.locked then return end
        fr.StartMoving(fr, button)
    end)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        self:SavePosition(fr)
    end)
    -- CD-30 (the source's frame release, the Cooldown bar's law ported at
    -- Forte_Cooldown/UI/Timeline.lua's OnMouseUp): a right-button release on
    -- the bar opens the options window on this module's page, dropped by the
    -- Moved guard after a drag. "OnMouseUp" is the script this engine accepts
    -- on a plain Frame ("OnClick" is Button-only -- the sim rejects it on a
    -- Frame); its payload is (frame, mouseButtonName, upInside) -- the
    -- catalog's 3rd slot, m2 CodeReview6.
    f:SetScript("OnMouseUp",
        function(_, button, upInside) self:OnMouseUp(button, upInside) end)

    -- The Aluminium progress fill: TOPLEFT-anchored with an explicit size,
    -- so `fill:GetWidth()` IS the rendered fraction (the acceptance's
    -- geometry check) and the fill grows left -> right.
    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(S.BarTexture)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    fill:SetSize(0, S.Height)
    local bc = S.BarColor
    fill:SetVertexColor(bc[1], bc[2], bc[3], bc[4])

    -- The swing v2 slices, all RIGHT-anchored at the bar's right edge with
    -- explicit widths (the WST slice geometry, WeaponSwingTimer_Hunter.lua
    -- :688-709, in our geometry language): the aim window (Debuff red) at
    -- the right end, the retry penalty (Item yellow) immediately left of
    -- it (inset by the aim length), the interlock's full-width cast slice
    -- behind everything. Hidden by default; Update() sizes/colours them.
    local aim = f:CreateTexture(nil, "ARTWORK")
    aim:SetTexture(S.BarTexture)
    aim:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    aim:SetSize(0, S.Height)
    local ac = S.AimColor
    aim:SetVertexColor(ac[1], ac[2], ac[3], ac[4])
    aim:Hide()

    local retry = f:CreateTexture(nil, "ARTWORK")
    retry:SetTexture(S.BarTexture)
    retry:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    retry:SetSize(0, S.Height)
    local rc = S.RetryColor
    retry:SetVertexColor(rc[1], rc[2], rc[3], rc[4])
    retry:Hide()

    local cast = f:CreateTexture(nil, "ARTWORK")
    cast:SetTexture(S.BarTexture)
    cast:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    cast:SetSize(0, S.Height)
    cast:SetVertexColor(ac[1], ac[2], ac[3], ac[4])
    cast:Hide()

    -- The "projectile left" pulse: Spark2 ADD-blend at the fill head, the
    -- Timeline's pulse law (alpha 1->0 linear over PulseSeconds, no wave).
    local spark = f:CreateTexture(nil, "ARTWORK")
    spark:SetTexture(S.SparkTexture)
    spark:SetPoint("CENTER", f, "TOPLEFT", 0, S.Height * 0.5)
    spark:SetSize(math.max(6, S.Height), S.Height)
    if spark.SetBlendMode then pcall(spark.SetBlendMode, spark, "ADD") end
    spark:SetVertexColor(1, 1, 1, 0)
    self.spark = spark

    -- The remaining-seconds text, right-aligned inside the bar.
    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    applyFont(text, S.FontSize, S.FontFlags)
    text:SetJustifyH("RIGHT")
    text:SetPoint("RIGHT", f, "RIGHT", -2, 0)
    text:SetTextColor(S.TextColor[1], S.TextColor[2], S.TextColor[3],
        S.TextColor[4])
    text:SetText("")

    -- The drag-handle label (the Timeline's title law: visible only while
    -- unlocked).
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetText("Forte Swing")
    title:SetTextColor(1, 1, 1, 1)
    title:SetPoint("BOTTOM", f, "TOP", 0, 2)

    self.anchor, self.fill, self.text, self.title = f, fill, text, title
    self.aim, self.retry, self.cast = aim, retry, cast
    self._fillW, self._timeKey, self._shown = nil, nil, false
    self._phase, self._aimW, self._retryW, self._castW, self._sparkAt
        = nil, nil, nil, nil, nil
    self._fillColor, self._combatAlpha = nil, nil

    self:_WireSettings()
    self:ApplyStoredSettings()
    self:ApplyPosition()
    self:SetLocked(self.cfg.locked and true or false)
    -- An idle bar draws nothing: hidden until a swing arrives.
    f:Hide()
end

--- The injected-tracker seam (tests, later speed models).
function D:SetTracker(tracker)
    self.Tracker = tracker
    self._fillW, self._timeKey = nil, nil
end

-- -------------------------------------------------------------- position --
function D:ApplyPosition()
    if not self.anchor then return end
    local cfg = self.cfg
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
end

function D:SavePosition(f)
    f = f or self.anchor
    if not f then return end
    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint, x, y
end

function D:Reset()
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y =
        DEFAULT.point, DEFAULT.relPoint, DEFAULT.x, DEFAULT.y
    self:ApplyPosition()
end

--- Locked = NOT draggable + the title hidden; the publish to the store is
--- what makes the options checkbox and the header lock icon read the same
--- truth (the Timeline's m4 convention). The mouse stays live: the source's
--- lock (FW:IsLocked, Forte_Core/Options.lua:517-523) gates only
--- FW_StartMoving's drag start (:651), it never disables the frame's mouse --
--- that is what keeps the right-button options release alive on a locked bar
--- (the Forte_Soulstone.xml:189-196 + SSFrame_OnClick law; the port's
--- mouse-off-while-locked was silencing it, and this bar ships LOCKED by
--- default, so the mouse-off made the seam unreachable by default).
function D:SetLocked(locked)
    locked = not not locked
    if self.cfg then self.cfg.locked = locked end
    local st = FX.Settings
    if st and st.IsRegistered and st:IsRegistered("Hunter")
        and st:Get("Hunter", "Lock") ~= locked then
        st:Set("Hunter", "Lock", locked)
    end
    if not self.anchor then return end
    self.anchor:SetMovable(not locked)
    self.anchor:EnableMouse(true)
    if locked then self.title:Hide() else self.title:Show() end
end

--- FW:StartMoving's press stamp (Forte_Core/Options.lua:649-656): the cursor
--- position at the moment the bar started moving (the Cooldown bar's
--- `_StampPress`, Forte_Cooldown/UI/Timeline.lua, the same seam).
function D:_StampPress()
    if type(GetCursorPosition) ~= "function" then return end
    local x, y = GetCursorPosition()
    self._downX, self._downY = x, y
end

--- FW:Moved() (Forte_Core/Options.lua:659-662): did the cursor travel
--- between press and release? A drag must never open the options window
--- (CD-30). No cursor read (no press stamp, no cursor on this client) means
--- no travel, i.e. a click.
function D:Moved()
    if type(GetCursorPosition) ~= "function" then return false end
    local dx, dy = self._downX, self._downY
    if dx == nil or dy == nil then return false end
    local x, y = GetCursorPosition()
    if x == nil or y == nil then return false end
    return x ~= dx or y ~= dy
end

--- CD-30 on this bar (the source's frame release, the Cooldown bar's law at
--- Forte_Cooldown/UI/Timeline.lua's OnMouseUp): a right-button release opens
--- the options window on this module's page; a release that followed a drag
--- is dropped by the Moved guard.
function D:OnMouseUp(button, upInside)
    if button ~= "RightButton" then
        -- CodeReview6 M2: the stamp describes ONE press/release pair; the
        -- release consumes it, on every exit (a stale stamp is exactly
        -- M2's dead seam).
        self._downX, self._downY = nil, nil
        return
    end
    local moved = self:Moved()
    self._downX, self._downY = nil, nil
    if moved then return end
    -- m2 (CodeReview6): a release the client reports OUTSIDE the frame
    -- (the catalog's 3rd OnMouseUp slot) is not a click on it; nil (a
    -- hand-driven script) = treated as inside.
    if upInside == false then return end
    -- `RightClickOptions` (the source's row of the same name,
    -- Forte_Core/Options.lua:5545, default true at Forte_Core.lua:2495; our
    -- row rides the General page). Off = the bar is silent: the release is
    -- consumed, nothing opens.
    local st = FX.Settings
    if st and st.IsRegistered and st:IsRegistered("General")
        and st:Get("General", "RightClickOptions") == false then
        return
    end
    local O = FX.Options
    if not O or not O.Open then return end
    pcall(O.Open, O, "Hunter")
end

-- --------------------------------------------------------------- geometry --
function D:SetSize(w, h)
    if type(w) == "number" and w > 0 then S.Width = w end
    if type(h) == "number" and h > 0 then S.Height = h end
    if not self.anchor then return end
    self.anchor:SetSize(S.Width, S.Height)
    -- The fill keeps its current fraction under the new numbers.
    self.fill:SetSize(self._fillW or 0, S.Height)
end

function D:SetWidth(v) self:SetSize(v, nil) end
function D:SetHeight(v) self:SetSize(nil, v) end

function D:SetBarColor(col)
    if type(col) ~= "table" then return end
    -- An explicit choice: Init must not overwrite it with the skin default.
    self._barColorSet = true
    S.BarColor = { col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1 }
    if not self.fill then return end
    local c = S.BarColor
    self.fill:SetVertexColor(c[1], c[2], c[3], c[4])
end

function D:SetBgColor(col)
    if type(col) ~= "table" then return end
    S.BgColor = { col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 0.5 }
    local f = self.anchor
    if f and f.SetBackdropColor then
        local c = S.BgColor
        f:SetBackdropColor(c[1], c[2], c[3], c[4])
        f:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
    end
end

function D:SetEnabled(on)
    ST.enabled = not not on
    if not ST.enabled then
        if self.anchor and self._shown then
            self._shown = false
            self.anchor:Hide()
        end
        self:StopTicking()
    end
end

function D:SetShowTime(on)
    ST.showTime = not not on
    self._timeKey = nil
    if self.text then
        if ST.showTime then
            if self._shown then self.text:Show() end
        else
            self.text:Hide()
        end
    end
end

function D:SetFont(path)
    S.FontFile = tostring(path or "")
    self.fontFile = validateFontFile(S.FontFile)
    D.fontFile = self.fontFile
    if self.text then
        self.text._font = nil
        applyFont(self.text, S.FontSize, S.FontFlags)
    end
end

--- The eight FrameStrata names (`SetFrameStrata`,
--- SimpleFrameAPIDocumentation.lua:1293); the same eight the source's own
--- tip lists (Forte_Core/Localization.lua:441). Plain string literals.
local STRATA = { "background", "low", "medium", "high", "dialog",
    "fullscreen", "fullscreen_dialog", "tooltip" }
local function strataOrNil(value)
    if type(value) ~= "string" then return nil end
    local up = string.upper(value)
    local low = string.lower(up)
    for i = 1, #STRATA do
        if STRATA[i] == low then return up end
    end
    return nil
end

--- The Advanced page's strata row for this bar (`HunterStrata`). The
--- source's Hunter class module registers ZERO options
--- (`Forte_Class/Hunter/Hunter.lua`), so the row is ours; the key follows
--- the source's per-module strata naming (Forte_Cooldown.lua:1790,
--- Forte_Timer.lua:3277). A name outside the eight is ignored: the bar
--- keeps the strata it has.
function D:SetStrata(name)
    local up = strataOrNil(name)
    if not up then return end
    S.Strata = up
    if self.anchor and self.anchor.SetFrameStrata then
        self.anchor:SetFrameStrata(up)
    end
end

-- ------------------------------------------------------- swing v2 seams --
function D:SetShowSafeWindow(on)
    ST.showSafeWindow = not not on
    self._fillW, self._timeKey, self._phase = nil, nil, nil
end

function D:SetShowAimSlice(on)
    ST.showAimSlice = not not on
    self._phase = nil
end

function D:SetShowFlying(on)
    ST.showFlying = not not on
    self._fillColor = nil
    if not ST.showFlying then self._sparkAt = nil end
end

function D:SetShowRetry(on)
    ST.showRetry = not not on
end

function D:SetShowLatency(on)
    -- The GetNetStats 4th-return shape is a launch-day probe (§B12);
    -- enabling the strip before the probe measures it is a no-op by law.
    ST.showLatency = not not on
end

function D:SetInCombatAlpha(v)
    v = tonumber(v)
    if v == nil then return end
    S.InCombatAlpha = math.min(1, math.max(0, v))
    self._combatAlpha = nil
end

function D:SetOutOfCombatAlpha(v)
    v = tonumber(v)
    if v == nil then return end
    S.OutOfCombatAlpha = math.min(1, math.max(0, v))
    self._combatAlpha = nil
end

--- The aim-ratio base speed (0 = auto). Rides the tracker seam.
function D:SetBaseSpeed(v)
    local t = self.Tracker
    if t and t.SetBaseSpeed then t:SetBaseSpeed(tonumber(v)) end
end

-- ---------------------------------------------------------------- render --
--- One render pass; `now` is optional (GetTime() by default) -- the tests
--- inject a clock. Returns true when a swing is on screen.
---
--- swing v2 geometry (docs/research/weaponswingtimer.md §5, the slice
--- widths adapting WeaponSwingTimer SixxFix's shot_bar/auto_shot_cast_bar/
--- retry_bar laws, WeaponSwingTimer_Hunter.lua:688-709):
---   * safe-window mode (ShowSafeWindow on): the fill is the SAFE span
---     `(remaining - floor) / duration` shrinking toward the right-end
---     aim slice; the aim window (Debuff red), the retry penalty (Item
---     yellow) and the interlock's full-width red ride as slices;
---   * ShowSafeWindow off = the single-phase bar: fill = elapsed/duration,
---     every slice hidden (the fallback law -- the pre-v2 look);
---   * the event-proven flight paints the fill Buff white (the "projectile
---     left, safe to move/cast" state) with a Spark2 pulse on entry;
---   * the Aimed/Multi interlock freezes the fill at its clip fraction and
---     prints the cast's remaining seconds;
---   * the in/ooc alpha pair (InCombatAlpha/OutOfCombatAlpha) rides the
---     anchor.
function D:Update(now)
    if not self.anchor then return false end
    local tracker = self.Tracker
    if not tracker or not tracker.CycleState or not ST.enabled then
        self:RenderIdle()
        return false
    end
    now = now or GetTime()
    local phase, aimLen, floor, ready = tracker:CycleState(now)
    if phase == nil then
        self:RenderIdle()
        return false
    end
    local fraction, remaining = tracker:Progress(now)
    if fraction == nil then
        self:RenderIdle()
        return false
    end
    self:_ApplyCombatAlpha()
    local castLeft, castLen
    if tracker.CastRemaining then
        castLeft, castLen = tracker:CastRemaining(now)
    end
    if not self._shown then
        self._shown = true
        self.anchor:Show()
        if ST.showTime then self.text:Show() end
    end
    local W = S.Width
    local scale = (tracker.duration and tracker.duration > 0)
        and (W / tracker.duration) or 0

    -- The fill: frozen under the cast interlock, otherwise the phase's
    -- own law.
    local w
    if castLeft then
        w = (tracker.CastingCycleFraction
            and (tracker:CastingCycleFraction() * W)) or W
    elseif ST.showSafeWindow and phase == "flying" then
        -- The WST shot-bar law (WeaponSwingTimer_Hunter.lua :913-1010):
        -- the WHOLE bar rides white from SUCCEEDED to the next
        -- PLAYER_SWING re-arm -- the safe-to-move state, not a sliver.
        w = W
    elseif ST.showSafeWindow and phase ~= "flying" then
        w = math.max(0, (remaining - floor) / tracker.duration) * W
    else
        w = fraction * W
    end
    if w < 0 then
        w = 0
    elseif w > W then
        w = W
    end
    if self._fillW ~= w then
        self._fillW = w
        self.fill:SetSize(w, S.Height)
    end

    -- The fill tint: Buff white while the proven projectile is in flight,
    -- the BarColor otherwise (a two-value cache -- dirty-checked).
    local flying = ST.showFlying and phase == "flying" and not castLeft
    local fc = flying and S.FlyingColor or S.BarColor
    local fck = fc[1] .. "|" .. fc[2] .. "|" .. fc[3] .. "|" .. fc[4]
    if self._fillColor ~= fck then
        self._fillColor = fck
        self.fill:SetVertexColor(fc[1], fc[2], fc[3], fc[4])
    end
    if flying and self.spark then
        if self._phase ~= "flying" then
            self._sparkAt = now      -- the shot left: one pulse, 1.0 s
        end
    end

    -- The spark at the fill head (the Timeline's pulse: alpha 1 -> 0
    -- linear over PulseSeconds, no wave).
    if self.spark then
        local sa = 0
        local at = self._sparkAt
        if at then
            sa = 1 - (now - at) / S.PulseSeconds
            if sa <= 0 then
                sa = 0
                self._sparkAt = nil
            end
        end
        self.spark:SetPoint("CENTER", self.anchor, "TOPLEFT", w,
            S.Height * 0.5)
        self.spark:SetVertexColor(1, 1, 1, sa)
    end

    -- The slices: hidden wholesale in single-phase mode.
    local aimW, retryW, castW = 0, 0, 0
    if ST.showSafeWindow then
        if castLeft then
            -- The interlock: the full-width red slice says "this cycle
            -- gets clipped" (the WST clip-bar signal our safe window
            -- carries -- gap row 8/11).
            castW = W
        else
            if ST.showAimSlice and phase == "aim"
                and aimLen and aimLen > 0 then
                -- The window is INFORMATION (the WST shot_slice law
                -- :688-709 draws it unconditionally): the readiness gate
                -- governs the shot, never the slice.
                aimW = math.min(aimLen, aimLen + math.max(0,
                    (tracker.retryUntil or 0) - now)) * scale
            end
            if ST.showRetry and tracker.retryUntil
                and tracker.retryUntil > now then
                local left = math.min(0.5, tracker.retryUntil - now)
                retryW = left * scale
            end
        end
    end
    self:_SetSlice(self.aim, "_aimW", aimW, aimLen and aimLen * scale or 0)
    self:_SetSlice(self.retry, "_retryW", retryW, 0)
    self:_SetSlice(self.cast, "_castW", castW, 0)
    self._phase = phase

    -- The text: the cast's remaining under the interlock; during the aim
    -- window the stand-still countdown (the aim left + an open retry, the
    -- WST :651-657 fold); the cycle's remaining otherwise.
    if ST.showTime then
        local text
        local key
        if castLeft then
            text = formatRemaining(castLeft)
            key = math.floor(castLeft * 10 + 0.5)
        elseif phase == "aim" then
            local shown = math.min(remaining, aimLen)
                + math.max(0, (tracker.retryUntil or 0) - now)
            text = formatRemaining(shown)
            key = timeKey(shown)
        else
            text = formatRemaining(remaining)
            key = timeKey(remaining)
        end
        if self._timeKey ~= key then
            self._timeKey = key
            self.text:SetText(text)
        end
    elseif self._timeKey ~= nil then
        self._timeKey = nil
        self.text:SetText("")
    end
    return true
end

--- Dirty-checked slice geometry (the every-style-setter-is-checked law).
function D:_SetSlice(tex, key, w, inset)
    if not tex then return end
    if self[key] ~= w then
        self[key] = w
        tex:SetSize(w, S.Height)
        tex:SetPoint("TOPRIGHT", self.anchor, "TOPRIGHT", -(inset or 0), 0)
        if w > 0 then tex:Show() else tex:Hide() end
    end
end

--- The in/out-of-combat alpha pair (the WST in-combat-only mechanism,
--- gap row 10; the gate is InCombatLockdown, CAT-declared).
function D:_ApplyCombatAlpha()
    local inC
    if type(InCombatLockdown) == "function" then
        local ok, v = pcall(InCombatLockdown)
        inC = ok and v and true or false
    end
    local a = inC and S.InCombatAlpha or S.OutOfCombatAlpha
    if self._combatAlpha ~= a then
        self._combatAlpha = a
        self.anchor:SetAlpha(a)
    end
end

--- The idle state: bar hidden, text blank, the slices parked, the
--- per-frame script gone.
function D:RenderIdle()
    if self._shown then
        self._shown = false
        if self.anchor then self.anchor:Hide() end
    end
    -- No stale number on a hidden bar (runs on the state transition only).
    if self.text then self.text:SetText("") end
    self._fillW, self._timeKey = nil, nil
    self._phase = nil
    if self.spark then self.spark:SetVertexColor(1, 1, 1, 0) end
    self._sparkAt = nil
    for _, pair in ipairs({ { self.aim, "_aimW" }, { self.retry, "_retryW" },
        { self.cast, "_castW" } }) do
        local tex, key = pair[1], pair[2]
        if tex and self[key] ~= 0 then
            self[key] = 0
            tex:SetSize(0, S.Height)
            tex:Hide()
        end
    end
    self:StopTicking()
end

-- ----------------------------------------------------------------- ticker --
--- The 10 Hz script exists only while a swing runs.
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
        self:Update(GetTime())
    end)
    -- A hidden frame never receives OnUpdate, and the anchor is hidden while
    -- idle: render once now so the anchor is shown before its own OnUpdate is
    -- relied on (found live on uiforever 2026-11-02 -- the bar never appeared).
    self:Update(GetTime())
end

function D:StopTicking()
    if not self._ticking then return end
    self._ticking = false
    if self.anchor then self.anchor:SetScript("OnUpdate", nil) end
end

--- The event kick (the UI module calls it on PLAYER_SWING /
--- PLAYER_SWING_RANGE_UPDATE / Auto Shot cast events): a running tracker
--- starts the ticker, an idle one costs nothing.
function D:Kick()
    local tracker = self.Tracker
    if not tracker then return end
    if tracker.active then self:StartTicking() end
end

--- The event hook surface: `a1..a3` arrive and are deliberately unread --
--- the payload contracts belong to Core/Tools.lua (PLAN §8), which owns the
--- same events; the bar only needs to know "the tracker may have moved".
function D:OnSwingEvent()
    self:Kick()
end

-- ------------------------------------------------------------ live settings --
--- options key -> setter. Lock rides SetLocked (the bar publishes it back);
--- GlobalLock is the General page's shared frame lock, and BarFont is the
--- General page's shared bar font (the same seam Forte_Cooldown's Display
--- routes -- the swing text rides the identical URW Gothic law). Keys with
--- no consumer here (the reminder's) are simply absent from the map.
local KEYMAP = {
    Enable = "SetEnabled",
    Lock = "SetLocked",
    Width = "SetWidth",
    Height = "SetHeight",
    BarColor = "SetBarColor",
    BgColor = "SetBgColor",
    ShowTime = "SetShowTime",
    Font = "SetFont",
    BarFont = "SetFont",
    GlobalLock = "SetLocked",
    -- swing v2 (gap row 10): all ride the existing seam, no new plumbing.
    ShowSafeWindow = "SetShowSafeWindow",
    ShowAimSlice = "SetShowAimSlice",
    ShowFlying = "SetShowFlying",
    ShowRetry = "SetShowRetry",
    ShowLatency = "SetShowLatency",
    ShowRangeLight = "SetShowRangeLight",
    InCombatAlpha = "SetInCombatAlpha",
    OutOfCombatAlpha = "SetOutOfCombatAlpha",
    BaseSpeed = "SetBaseSpeed",
    -- The Advanced page's strata row for this bar (the source has no Hunter
    -- options at all; the key is the shared Advanced page's, named like the
    -- source's per-module rows: Forte_Cooldown.lua:1790, Forte_Timer
    -- .lua:3277).
    HunterStrata = "SetStrata",
}

--- The stored shape of the wired keys, per settings module (the pages'
--- defaults are canonical). Lock is deliberately NOT pulled: the live lock
--- state is the truth and SetLocked publishes it upward (the Timeline's m4
--- rule).
local STORED = {
    Hunter = { "Enable", "Width", "Height", "BarColor", "BgColor",
        "ShowTime", "ShowSafeWindow", "ShowAimSlice", "ShowFlying",
        "ShowRetry", "ShowLatency", "InCombatAlpha", "OutOfCombatAlpha",
        "BaseSpeed" },
    General = { "BarFont" },
    -- The Advanced page's shared keys (Forte_Options/Pages/Advanced.lua).
    Advanced = { "HunterStrata" },
}

function D:ApplySettings(tbl)
    for key, value in pairs(tbl or {}) do
        local m = KEYMAP[key]
        -- The shared page listener routes every Hunter-key change to
        -- every renderer; a key without a consumer HERE (the range
        -- light's ShowRangeLight) is inert by the map's law.
        if m and self[m] then self[m](self, value) end
    end
end

function D:ApplyStoredSettings()
    local st = FX.Settings
    if not st or not st.IsRegistered then return end
    for module, keys in pairs(STORED) do
        if st:IsRegistered(module) then
            local out = {}
            for i = 1, #keys do
                out[keys[i]] = st:Get(module, keys[i])
            end
            self:ApplySettings(out)
        end
    end
end

--- Live wiring, registered once from Init (the Timeline's _WireSettings
--- shape): our own module routes through KEYMAP, and the two shared lock
--- keys are mirrored so /fx lock|unlock (which moves the Cooldown bar's
--- lock and General's GlobalLock) also locks/unlocks the Hunter frames.
--- SetLocked's store-inequality guard stops the echo.
function D:_WireSettings()
    local st = FX.Settings
    if not st or not st.OnChange or self._wired then return end
    self._wired = true
    st:OnChange("Hunter", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
    st:OnChange("Cooldown", function(key, value)
        if key == "Lock" then self:SetLocked(not not value) end
    end)
    st:OnChange("General", function(key, value)
        -- GlobalLock rides SetLocked; every other General key rides KEYMAP
        -- (BarFont today; FrameScale/FrameAlpha/... have no consumer here
        -- and are inert by the map's law).
        if key == "GlobalLock" then self:SetLocked(not not value)
        else self:ApplySettings({ [key] = value }) end
    end)
    -- CodeReview6 M4: the Advanced page's HunterStrata row rides this
    -- module (STORED + KEYMAP), and the tip promises "Applied live" --
    -- without this listener the row moved the store and ZERO consumers
    -- on the bar, login-only, every sibling (Timeline, Splash, the Spell
    -- Timer, the Warlock plates) carrying the one-liner the Hunter
    -- lacked.
    st:OnChange("Advanced", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
end

-- -------------------------------------------------------------- lifecycle --
function D:OnClassChanged(classFile)
    if classFile == "HUNTER" then
        self:Init()
    elseif self.anchor then
        self:RenderIdle()
        self.anchor:Hide()
        self._shown = false
    end
end

function D:StatusLine()
    local fraction, remaining
    if self.Tracker then fraction, remaining = self.Tracker:Progress() end
    return string.format("Swing bar: %s | %dx%d | %s | %s",
        fraction and string.format("%.0f%% (%.1fs)", fraction * 100, remaining)
            or "idle",
        S.Width, S.Height,
        ST.showTime and "text on" or "text off",
        (self.cfg and self.cfg.locked) and "locked" or "unlocked")
end

-- ================================================================ UI module --
-- FX.Hunter.UI drives the Hunter frames (the swing bar + the aspect
-- reminder) and their events. Registered as its own Forte module: the
-- Hunter module is Core/Tools.lua's (the data/state module) and its OnEnable
-- is class-gated for the event frame -- the UI needs its own class-gated
-- OnEnable + OnClassChanged, and Forte_Core is not ours to edit. Frames and
-- RegisterEvent live inside these handlers, never at file load.

FX.Hunter.UI = {}
local U = FX.Hunter.UI

--- The events that mean "the swing / aspect state may have moved". All
--- payloads are forwarded UNREAD to the renderers (contracts: Core/Tools.lua
--- header + PLAN §8), which only use the kick.
local KICK_SWING = {
    PLAYER_SWING = true,
    PLAYER_SWING_RANGE_UPDATE = true,
}
local KICK_ALL = {
    PLAYER_ENTERING_WORLD = true,
    PLAYER_REGEN_ENABLED = true,
    PLAYER_REGEN_DISABLED = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
}
-- swing v2: the movement edges move the readiness gate, the target edge
-- moves the range light and the gate's target facts.
local KICK_MOVE = {
    PLAYER_STARTED_MOVING = true,
    PLAYER_STOPPED_MOVING = true,
}
local KICK_TARGET = {
    PLAYER_TARGET_CHANGED = true,
}

local function onUIEvent(self, event, a1, a2, a3)
    -- a1..a3 are received and deliberately unread (secret-value law: the
    -- trackers own these payloads, the UI touches none of them).
    if KICK_SWING[event] then
        self.Swing:OnSwingEvent()
    elseif KICK_ALL[event] then
        self.Swing:OnSwingEvent()
        self.Reminder:OnStateEvent()
        if self.RangeLight then self.RangeLight:OnStateEvent() end
    elseif KICK_MOVE[event] then
        self.Swing:OnSwingEvent()
    elseif KICK_TARGET[event] then
        self.Swing:OnSwingEvent()
        if self.RangeLight then self.RangeLight:OnStateEvent() end
    end
end

--- Register the UI's events (idempotent while enabled). The frame is
--- created here, inside OnEnable/OnClassChanged (the taint rule).
function U:EnableEvents()
    if self._eventsEnabled then return end
    local f = self._eventFrame
    if not f then
        f = CreateFrame("Frame")
        self._eventFrame = f
    end
    f:RegisterEvent("PLAYER_SWING")
    f:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:RegisterEvent("PLAYER_STARTED_MOVING")
    f:RegisterEvent("PLAYER_STOPPED_MOVING")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    -- OnEvent receives (frame, event, ...): swallow the frame, or `event`
    -- would be the frame and no branch would ever match.
    f:SetScript("OnEvent", function(_, event, a1, a2, a3) onUIEvent(U, event, a1, a2, a3) end)
    self._eventsEnabled = true
end

--- Tear the registrations back down when the class moves away from HUNTER
--- (Core FX.RefreshPlayerClass). Unregister* is nil-guarded exactly like
--- Core/Tools.lua's DisableEvents (the sim's frame emulation lacks them).
function U:DisableEvents()
    local f = self._eventFrame
    if f and self._eventsEnabled then
        if f.UnregisterUnitEvent then
            f:UnregisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        end
        if f.UnregisterEvent then
            f:UnregisterEvent("PLAYER_SWING")
            f:UnregisterEvent("PLAYER_SWING_RANGE_UPDATE")
            f:UnregisterEvent("PLAYER_REGEN_ENABLED")
            f:UnregisterEvent("PLAYER_REGEN_DISABLED")
            f:UnregisterEvent("PLAYER_ENTERING_WORLD")
            f:UnregisterEvent("PLAYER_STARTED_MOVING")
            f:UnregisterEvent("PLAYER_STOPPED_MOVING")
            f:UnregisterEvent("PLAYER_TARGET_CHANGED")
        end
        f:SetScript("OnEvent", nil)
    end
    self._eventsEnabled = false
end

function U:OnEnable()
    -- The page registration is NOT class-gated: this chunk runs at
    -- PLAYER_LOGIN, the first point where Forte_Options' files are
    -- guaranteed to exist (the loader may run Forte_Hunter first -- the
    -- dependency is optional and alphabetical order puts Forte_Hunter
    -- before Forte_Options), and Pages/Hunter.lua's load-time attempt was
    -- a no-op then. Idempotent.
    local pages = FX.Hunter.Pages
    if pages and pages.RegisterHunterPage then pages.RegisterHunterPage() end
    -- Hunters only (the Core bootstrap runs OnEnable for every class).
    if FX._playerClass ~= "HUNTER" then return end
    self.Swing = FX.Hunter.Swing
    self.Reminder = FX.Hunter.Reminder
    self.Swing:Init()
    self.Reminder:Init()
    self:_InitRange()
    self:EnableEvents()
    -- A swing that was already running (login mid-shot) shows immediately.
    self.Swing:Kick()
    self.Reminder:Refresh()
end

--- The range light's late registration: its file rides the same toc, so
--- it exists; the guard is load-order paranoia, not a load-on-demand seam.
function U:_InitRange()
    local RL = FX.Hunter.RangeLight
    self.RangeLight = RL
    if not RL then return end
    RL:Init()
    RL:_WireSettings()
    RL:ApplyStoredSettings()
    RL:Refresh()
end

--- Core FX.RefreshPlayerClass notification (the uiforever T4 class guard):
--- the frames and the event frame follow the class.
function U:OnClassChanged(classFile)
    self.Swing = FX.Hunter.Swing
    self.Reminder = FX.Hunter.Reminder
    if classFile == "HUNTER" then
        self.Swing:OnClassChanged(classFile)
        self.Reminder:OnClassChanged(classFile)
        self:_InitRange()
        if self.RangeLight then
            self.RangeLight:OnClassChanged(classFile)
        end
        self:EnableEvents()
        self.Swing:Kick()
        self.Reminder:Refresh()
    else
        self:DisableEvents()
        self.Swing:OnClassChanged(classFile)
        self.Reminder:OnClassChanged(classFile)
        if self.RangeLight then
            self.RangeLight:OnClassChanged(classFile)
        end
    end
end

--- `/fx status` integration (Core's status loop calls Status per module).
function U:Status()
    local lines = {}
    if self.Swing and self.Swing.anchor then
        lines[#lines + 1] = self.Swing:StatusLine()
    end
    if self.Reminder and self.Reminder.anchor then
        lines[#lines + 1] = self.Reminder:StatusLine()
    end
    if self.RangeLight and self.RangeLight.anchor then
        lines[#lines + 1] = self.RangeLight:StatusLine()
    end
    if #lines == 0 then
        lines[1] = "Hunter UI: not built (class " .. tostring(FX._playerClass) .. ")"
    end
    for _, l in ipairs(lines) do FX.Print(l) end
end

FX.RegisterModule("HunterUI", U)
