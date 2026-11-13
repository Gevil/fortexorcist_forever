-- addon/Forte_Hunter/UI/Reminder.lua
-- FX.Hunter.Reminder: the "you are not wearing an aspect" nudge. A 32x32
-- spell icon that pulses its alpha while `FX.Hunter.Tools.Aspects:Missing()`
-- is true, hidden at every other moment. All STATE lives in the aspect
-- tracker (Core/Tools.lua): Missing() is "no aspect known active AND not in
-- combat" (docs/hunter-tools.md), so the out-of-combat gate is the tracker's,
-- not a combat read of ours.
--
-- The icon is the LAST aspect the tracker knew (cast-predicted in combat,
-- reconciled out of combat -- PLAN §3.2), remembered across the clear, so the
-- reminder keeps showing the aspect the hunter last used; a player who never
-- cast one gets the generic first aspect (the derived list's first name,
-- alphabetical -- FX.Hunter.Tools.aspectNames).
--
-- Skin law (Forte_Cooldown/UI/Timeline.lua): the backdrop pair
-- Background/Border, Aluminium icon plate; frames are created inside Init
-- (called from the module's OnEnable / OnClassChanged), never at file load;
-- every style setter is dirty-checked.
--
-- Click-through: EnableMouse(false) -- the reminder is pure chrome, it
-- never takes input (the assignment's law), so there is nothing to lock; the
-- shared Lock state (FX.Settings Hunter.Lock) gates the swing bar only.
--
-- Update law: the OnUpdate script exists ONLY while the icon is on screen
-- (it drives the pulse); hidden = no script, no per-frame work. Transitions
-- INTO the shown state come from the UI module's event kicks (regen
-- enabled/disabled, cast, zone-in) and from the tracker's change callback
-- (R:_Watch: a reconcile that moved the aspect), never from a standing ticker.
--
-- Position lives in FX.db.hunterReminder. Settings (module "Hunter"):
-- EnableReminder gates it; the aspect icon colour rides ReminderColor.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Hunter = FX.Hunter or {}

local R = {}
FX.Hunter.Reminder = R

local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.Hunter.ReminderSkin = {
    Size = 32,                                -- the assignment's 32x32
    BackdropBG = TEX .. "Background",
    BackdropEdge = TEX .. "Border",
    BackdropTile = false,
    BackdropTileSize = 16,
    BackdropEdgeSize = 5,
    Inset = 2,
    BgColor = { 0, 0, 0, 0.50 },
    BarTexture = TEX .. "Aluminium",
    ReminderColor = { 1, 1, 1, 1 },
    PulsePeriod = 1.2,                        -- one breath of the pulse
    PulseMin = 0.35,                          -- the alpha swing
    PulseMax = 1.0,
}
local S = FX.Hunter.ReminderSkin

local DEFAULT = { point = "CENTER", relPoint = "CENTER", x = 160, y = -175 }
local TICK_SECONDS = 0.1                      -- 10 Hz pulse sampling

R.state = { enabled = true }
local ST = R.state

-- ------------------------------------------------------------- persistence --
local fallbackCfg
local function config()
    if FX.db then
        FX.db.hunterReminder = FX.db.hunterReminder or {}
        return FX.db.hunterReminder
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
function R:Init()
    if self.anchor then return end
    self.cfg = cfgDefaults(config())
    self.Aspects = self.Aspects or (FX.Hunter.Tools and FX.Hunter.Tools.Aspects)
    self:_Watch(self.Aspects)

    local f = CreateFrame("Frame", "ForteXorcistHunterReminderAnchor", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(S.Size, S.Size)
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
    -- Click-through: the reminder never takes mouse input, locked or not.
    f:EnableMouse(false)
    f:SetMovable(false)

    -- The aspect icon, inset by Backdrop[6] like the Classic bars.
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(S.BarTexture)
    local ins = S.Inset
    icon:SetPoint("TOPLEFT", f, "TOPLEFT", ins, -ins)
    icon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -ins, ins)
    local c = S.ReminderColor
    icon:SetVertexColor(c[1], c[2], c[3], c[4])

    self.anchor, self.icon = f, icon
    self._shown, self._alpha, self._tex = nil, nil, nil

    self:_WireSettings()
    self:ApplyStoredSettings()
    self:ApplyPosition()
    f:Hide()
    self._shown = false
end

--- The injected-tracker seam (tests): replaces the aspect state source.
function R:SetAspects(tracker)
    self.Aspects = tracker
    self._shown, self._alpha = nil, nil
    self:_Watch(tracker)
end

--- Subscribe to the tracker's change callback: a reconcile that moves the
--- aspect (a reload that finds one worn, one cancelled out of combat)
--- shows/hides the icon at once. A hidden frame gets no OnUpdate, so the
--- 10 Hz self-heal cannot be what brings a hidden reminder back. The
--- callback is the tracker's (pcall'd there); no chat output.
function R:_Watch(tracker)
    local old = self._watched
    if old == tracker then return end
    if old and old.onChange == self._changeCb then old:OnChange(nil) end
    self._watched = tracker
    if tracker and tracker.OnChange then
        self._changeCb = self._changeCb or function() R:Refresh() end
        tracker:OnChange(self._changeCb)
    end
end

-- -------------------------------------------------------------- position --
function R:ApplyPosition()
    if not self.anchor then return end
    local cfg = self.cfg
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
end

function R:SavePosition(f)
    f = f or self.anchor
    if not f then return end
    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint, x, y
end

function R:Reset()
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y =
        DEFAULT.point, DEFAULT.relPoint, DEFAULT.x, DEFAULT.y
    self:ApplyPosition()
end

-- ---------------------------------------------------------------- styling --
function R:SetSize(v)
    if type(v) == "number" and v > 0 then S.Size = v end
    if self.anchor then self.anchor:SetSize(S.Size, S.Size) end
end

function R:SetColor(col)
    if type(col) ~= "table" then return end
    S.ReminderColor = { col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1 }
    if not self.icon then return end
    local c = S.ReminderColor
    self.icon:SetVertexColor(c[1], c[2], c[3], c[4])
end

function R:SetEnabled(on)
    ST.enabled = not not on
    self:Refresh()
end

-- ------------------------------------------------------------- the icon art --
--- The aspect whose icon we show: the tracker's live one, else the last one
--- it ever knew, else the generic first aspect of the derived list.
function R:IconName()
    local t = self.Aspects
    local current = t and t:Current()
    if type(current) == "string" then
        self._lastAspect = current
        return current
    end
    if type(self._lastAspect) == "string" then return self._lastAspect end
    -- Nothing cast yet: the first aspect THIS character actually knows (the
    -- generic first entry, Beast, is not in every spellbook), else the first.
    local names = FX.Hunter.Tools and FX.Hunter.Tools.aspectNames
    local byName = FX.Data and FX.Data.HunterByName
    if names and byName and FX.Compat and FX.Compat.IsPlayerSpell then
        for i = 1, #names do
            local id = byName[names[i]]
            if id and FX.Compat.IsPlayerSpell(id) then return names[i] end
        end
    end
    return (names and names[1])
end

-- Never the grey bar: a question-mark is the honest "icon unknown".
local UNKNOWN_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

--- Icon for an aspect name: by spell ID first (name lookups fail for spells
--- the client does not list), then by name, then the question mark.
local function aspectTexture(name)
    local id = FX.Data and FX.Data.HunterByName and FX.Data.HunterByName[name]
    local C = _G.C_Spell
    -- m2 (code-review-10): the old `ipairs({ id, name })` stored NOTHING at
    -- index 1 when `id == nil`, so ipairs read nil at 1 and never ran -- the
    -- "then by name" leg of this function's own docstring could not execute
    -- for exactly the spells HunterByName lacks. Two fixed indices, holes
    -- classified per leg.
    local keys = { id, name }
    for i = 1, 2 do
        local key = keys[i]
        if key ~= nil and C then
            if C.GetSpellTexture then
                local ok, v = pcall(C.GetSpellTexture, key)
                if ok and v ~= nil then return v end
            end
            if C.GetSpellInfo then
                local ok, info = pcall(C.GetSpellInfo, key)
                local icon = ok and type(info) == "table" and (info.iconID or info.originalIconID)
                if icon then return icon end
            end
        end
    end
    return nil
end

function R:ApplyIcon()
    local name = self:IconName()
    if name == nil or self._tex == name then return end
    local path = aspectTexture(name)
    -- Only cache a successful lookup, so a not-yet-ready spell DB is retried.
    if path ~= nil then self._tex = name end
    self.icon:SetTexture(path or UNKNOWN_ICON)
end

-- ----------------------------------------------------------------- render --
--- Re-read the tracker and show/hide. `now` is optional (GetTime()).
--- Returns true when the reminder is on screen.
function R:Refresh(now)
    if not self.anchor then return false end
    local t = self.Aspects
    local missing = ST.enabled and t ~= nil and t:Missing() and true or false
    if not missing then
        self:HideNow()
        return false
    end
    self:ApplyIcon()
    if not self._shown then
        self._shown = true
        self.anchor:Show()
    end
    self:UpdateAlpha(now)
    self:StartTicking()
    return true
end

--- The pulse: a cosine breath between PulseMin and PulseMax.
function R:UpdateAlpha(now)
    if not self._shown then return end
    now = now or GetTime()
    local period = (S.PulsePeriod > 0) and S.PulsePeriod or 1
    local phase = (now - (self._anchor0 or now)) / period
    local wave = (1 - math.cos(phase * 2 * math.pi)) * 0.5
    local a = S.PulseMin + (S.PulseMax - S.PulseMin) * wave
    if self._alpha ~= a then
        self._alpha = a
        self.anchor:SetAlpha(a)
    end
    return a
end

function R:HideNow()
    if self._shown ~= false then
        self._shown = false
        if self.anchor then
            self.anchor:Hide()
            self.anchor:SetAlpha(1)
        end
        self._alpha = nil
    end
    self:StopTicking()
end

-- ----------------------------------------------------------------- ticker --
function R:StartTicking()
    if not self.anchor then return end
    if self._ticking then return end
    self._ticking = true
    self._anchor0 = GetTime()
    self._acc = 0
    local f = self.anchor
    f:SetScript("OnUpdate", function(_, elapsed)
        local acc = (self._acc or 0) + (tonumber(elapsed) or 0)
        if acc < TICK_SECONDS then
            self._acc = acc
            return
        end
        self._acc = 0
        -- The pulse AND a state self-heal: an aspect cast (the tracker
        -- adopts it) hides the reminder within one 10 Hz pass.
        if not self:Refresh(GetTime()) then self:StopTicking() end
    end)
end

function R:StopTicking()
    if not self._ticking then return end
    self._ticking = false
    if self.anchor then self.anchor:SetScript("OnUpdate", nil) end
end

-- ------------------------------------------------------------ live settings --
local KEYMAP = {
    EnableReminder = "SetEnabled",
    ReminderSize = "SetSize",
    ReminderColor = "SetColor",
}

local STORED = { "EnableReminder", "ReminderSize", "ReminderColor" }

function R:ApplySettings(tbl)
    for key, value in pairs(tbl or {}) do
        local m = KEYMAP[key]
        if m then self[m](self, value) end
    end
end

function R:ApplyStoredSettings()
    local st = FX.Settings
    if not st or not st.IsRegistered or not st:IsRegistered("Hunter") then return end
    local out = {}
    for i = 1, #STORED do
        out[STORED[i]] = st:Get("Hunter", STORED[i])
    end
    self:ApplySettings(out)
end

function R:_WireSettings()
    local st = FX.Settings
    if not st or not st.OnChange or self._wired then return end
    self._wired = true
    st:OnChange("Hunter", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
end

-- -------------------------------------------------------------- lifecycle --
--- The event kick surface: "the aspect state may have moved". `a1..a3` are
--- received and deliberately unread (payload contracts belong to
--- Core/Tools.lua, PLAN §8).
function R:OnStateEvent()
    self:Refresh()
end

function R:OnClassChanged(classFile)
    if classFile == "HUNTER" then
        self:Init()
    elseif self.anchor then
        self:HideNow()
        self.anchor:Hide()
        self._shown = false
    end
end

function R:StatusLine()
    local t = self.Aspects
    return string.format("Aspect reminder: %s | icon=%s | %s",
        (t and t:Missing()) and "showing" or "hidden",
        tostring(self:IconName()),
        ST.enabled and "on" or "off")
end
