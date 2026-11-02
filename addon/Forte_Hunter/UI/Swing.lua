-- addon/Forte_Hunter/UI/Swing.lua
-- FX.Hunter.Swing: the Auto Shot / ranged-swing bar, plus the UI module
-- ("HunterUI") that owns the Hunter frames' lifecycle. The bar is a thin
-- Classic skin strip (the Forte_Cooldown/UI/Timeline.lua law: Aluminium fill
-- on the Background/Border backdrop, URW Gothic text) that fills left ->
-- right while the current ranged swing burns, with the remaining seconds
-- right-aligned. All swing STATE lives in Core/Tools.lua's SwingTracker;
-- this file is a pure renderer of `FX.Hunter.Tools.Swing:Progress(now)`
-- (PLAN §3.4 "pure renderer, 10 Hz display", §3.6 module map).
--
-- Frame + skin law (Forte_Cooldown/UI/Timeline.lua):
--   * frames are created inside Init, which runs from the module's OnEnable
--     (PLAYER_LOGIN) or an OnClassChanged handler -- never at file load
--     (Forte_Core/Core/Init.lua's taint rule);
--   * every style setter is dirty-checked, the pass runs at 10 Hz;
--   * the lock convention (m4): SetLocked publishes the state into
--     FX.Settings (module "Hunter", key "Lock", guarded by
--     store-inequality so a listener calling back stops there) and locking
--     flips only SetMovable/EnableMouse. `/fx lock|unlock` runs
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
}
local S = FX.Hunter.SwingSkin

local DEFAULT = { point = "CENTER", relPoint = "CENTER", x = 0, y = -175,
    locked = true }
local TICK_SECONDS = 0.1                      -- the 10 Hz render rate

-- The module's live skin state: the setters are legal before Init (the
-- options page applies stored values at PLAYER_LOGIN; the frames arrive
-- with them) -- Timeline.frameState's shape.
D.state = { enabled = true, showTime = true }
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
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        self:SavePosition(fr)
    end)

    -- The Aluminium progress fill: TOPLEFT-anchored with an explicit size,
    -- so `fill:GetWidth()` IS the rendered fraction (the acceptance's
    -- geometry check) and the fill grows left -> right.
    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(S.BarTexture)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    fill:SetSize(0, S.Height)
    local bc = S.BarColor
    fill:SetVertexColor(bc[1], bc[2], bc[3], bc[4])

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
    self._fillW, self._timeKey, self._shown = nil, nil, false

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

--- Locked = mouse-off (no drag possible) + the title hidden; the publish to
--- the store is what makes the options checkbox and the header lock icon
--- read the same truth (the Timeline's m4 convention).
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
    self.anchor:EnableMouse(not locked)
    if locked then self.title:Hide() else self.title:Show() end
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

-- ---------------------------------------------------------------- render --
--- One render pass; `now` is optional (GetTime() by default) -- the tests
--- inject a clock. Returns true when a swing is on screen.
function D:Update(now)
    if not self.anchor then return false end
    local tracker = self.Tracker
    if not tracker or not ST.enabled then
        self:RenderIdle()
        return false
    end
    local fraction, remaining = tracker:Progress(now)
    if fraction == nil then
        self:RenderIdle()
        return false
    end
    if not self._shown then
        self._shown = true
        self.anchor:Show()
        if ST.showTime then self.text:Show() end
    end
    local w = fraction * S.Width
    if w < 0 then
        w = 0
    elseif w > S.Width then
        w = S.Width
    end
    if self._fillW ~= w then
        self._fillW = w
        self.fill:SetSize(w, S.Height)
    end
    if ST.showTime then
        local key = timeKey(remaining)
        if self._timeKey ~= key then
            self._timeKey = key
            self.text:SetText(formatRemaining(remaining))
        end
    elseif self._timeKey ~= nil then
        self._timeKey = nil
        self.text:SetText("")
    end
    return true
end

--- The idle state: bar hidden, text blank, the per-frame script gone.
function D:RenderIdle()
    if self._shown then
        self._shown = false
        if self.anchor then self.anchor:Hide() end
    end
    -- No stale number on a hidden bar (runs on the state transition only).
    if self.text then self.text:SetText("") end
    self._fillW, self._timeKey = nil, nil
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
}

--- The stored shape of the wired keys, per settings module (the pages'
--- defaults are canonical). Lock is deliberately NOT pulled: the live lock
--- state is the truth and SetLocked publishes it upward (the Timeline's m4
--- rule).
local STORED = {
    Hunter = { "Enable", "Width", "Height", "BarColor", "BgColor",
        "ShowTime" },
    General = { "BarFont" },
}

function D:ApplySettings(tbl)
    for key, value in pairs(tbl or {}) do
        local m = KEYMAP[key]
        if m then self[m](self, value) end
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

local function onUIEvent(self, event, a1, a2, a3)
    -- a1..a3 are received and deliberately unread (secret-value law: the
    -- trackers own these payloads, the UI touches none of them).
    if KICK_SWING[event] then
        self.Swing:OnSwingEvent()
    elseif KICK_ALL[event] then
        self.Swing:OnSwingEvent()
        self.Reminder:OnStateEvent()
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
    self:EnableEvents()
    -- A swing that was already running (login mid-shot) shows immediately.
    self.Swing:Kick()
    self.Reminder:Refresh()
end

--- Core FX.RefreshPlayerClass notification (the uiforever T4 class guard):
--- the frames and the event frame follow the class.
function U:OnClassChanged(classFile)
    self.Swing = FX.Hunter.Swing
    self.Reminder = FX.Hunter.Reminder
    if classFile == "HUNTER" then
        self.Swing:OnClassChanged(classFile)
        self.Reminder:OnClassChanged(classFile)
        self:EnableEvents()
        self.Swing:Kick()
        self.Reminder:Refresh()
    else
        self:DisableEvents()
        self.Swing:OnClassChanged(classFile)
        self.Reminder:OnClassChanged(classFile)
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
    if #lines == 0 then
        lines[1] = "Hunter UI: not built (class " .. tostring(FX._playerClass) .. ")"
    end
    for _, l in ipairs(lines) do FX.Print(l) end
end

FX.RegisterModule("HunterUI", U)
