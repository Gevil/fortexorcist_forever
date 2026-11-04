-- addon/Forte_Timer/Module.lua
-- FX.Timer.Module: the module Forte_Core enables at PLAYER_LOGIN, and the
-- addon's ONLY event frame. It decides *when* the laws are fed and owns the
-- two cadences the design prescribes (§1.9, PLAN §3.4): the display pass at
-- 0.04 s (the original's AnimationInterval, Forte_Core.lua:2473) and the
-- logic/rescan sweep at 0.5 s (UpdateInterval, Forte_Core.lua:2475). It also
-- owns the live options table the laws read and the SavedVariables namespace.
--
-- Event law (the project's, enforced by scripts/api_lint.py): one frame,
-- created INSIDE OnEnable (a top-level RegisterEvent can throw
-- ADDON_RESTRICTION/ACTION_FORBIDDEN off a tainted chunk, Forte_Core/Core/
-- Init.lua's safety note); every handler binds `function(_, event, ...)`
-- because the frame is the first argument (the Forte_Hunter bug of
-- 2026-11-02: a `function(...) handler(obj, ...)` binding silently broke every
-- Hunter event); payload fields arrive UNREAD and are classified through
-- FX.Compat.PlainOrNil at the callee. COMBAT_LOG_EVENT_UNFILTERED is forbidden
-- on Forever and is not registered here (Compat.HAS_COMBAT_LOG == false): that
-- is what closes tick detection, resists, pet rows and trap triggers
-- (docs/design-spell-timer.md §4.3).
--
-- The registered set (design §4.1/§4.2, every name in the pinned Forever
-- catalog, asserted by tests/test_events.lua):
--   UNIT_SPELLCAST_SENT / START / SUCCEEDED / FAILED / INTERRUPTED  (unit events
--                                                                  for "player")
--   UNIT_SPELLCAST_SENT / SUCCEEDED                                (unit events
--                                                                  for "pet" --
--                                                                  the pet rows,
--                                                                  wave 2b
--                                                                  PetRows v2)
--   UNIT_AURA (player/target), PLAYER_TARGET_CHANGED, PLAYER_REGEN_ENABLED,
--   PLAYER_REGEN_DISABLED, ADDON_RESTRICTION_STATE_CHANGED, UNIT_DIED,
--   PLAYER_LEAVING_WORLD, PLAYER_DEAD.
--
-- The hidden-frame law (live finding of 2026-11-02, uiforever): a HIDDEN frame
-- never receives OnUpdate. The 0.04 s tick is a `C_Timer.NewTicker` (an
-- always-live driver, the Forte_Cooldown/Module.lua:458 pattern) so it runs
-- whatever the panel's visibility; and when activity starts the row's own
-- arrival calls `Display:Update` synchronously through Casts.onRow, so the
-- anchor is shown BEFORE its own OnUpdate is relied on.
--
-- Lock: `/fx lock|unlock` moves this panel with the Cooldown bar by MIRRORING
-- the two keys the Cooldown Display publishes (Cooldown.Lock and
-- General.GlobalLock) through FX.Settings:OnChange -- the law Forte_Hunter's
-- swing bar uses. SetLocked publishes this panel's own state back
-- (SpellTimer.Lock) under the store-inequality guard that stops the echo.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Timer = FX.Timer or {}

local M = {}
FX.Timer.Module = M
FX.RegisterModule("Timer", M)

local Rows = FX.Timer.Rows
local Laws = FX.Timer.Laws
local Skin = FX.Timer.Skin

local DRAW_SECONDS = 0.04   -- the display cadence (:2851/:2854, Forte_Core.lua:2473)
local LOGIC_SECONDS = 0.5   -- the logic/rescan cadence (:2855, Forte_Core.lua:2475)

-- The panel's first-run placement, in one place: OnEnable seeds the saved
-- config from it and `/fx timer reset` restores it.
--
-- The Cooldown bar defaults to CENTER/CENTER at (0, -150) with a 250x24 strip
-- (`Forte_Cooldown/Core/Pages/PanelHost.lua` DEFAULT_POSITION, the bar size
-- `UI/Timeline.lua` Width/Height). This panel is 256 px wide (Skin.Width +
-- GrowPad) and its stack grows DOWNWARD from its centre, so any centre placed
-- on the bar's vertical band ends up overprinting the bar as soon as two rows
-- show. The reference addon gives no help: `/tmp/fxref` centres both panels on
-- UIParent (Forte_Timer.lua's `frame:SetPoint("CENTER", UIParent, "CENTER")`
-- and the same in Forte_Cooldown.lua), i.e. the original overlapped them too.
--
-- So the two panels become a PAIR side by side at the same height: the bar at
-- x=0, this stack centred at x=261 -- (250 + 256)/2 = 253 needed, 261 with an
-- 8 px gutter. The rectangles can not intersect at any stack height.
M.DEFAULT_POSITION = { point = "CENTER", relPoint = "CENTER", x = 261,
    y = -150, locked = true }

-- --------------------------------------------------------- the live options --
--- The laws' option view: one table, the defaults from Core/Laws.lua + the
--- Skin, the options page writing the same keys live. Field names are the
--- law functions' (`opts.oneMax`, `opts.hideLonger`, ...), so the page and the
--- laws can not drift.
M.options = nil

local function defaultOptions()
    return {
        enable = true,
        -- the geometry the renderer draws
        width = Skin.Width, height = Skin.Height, space = Skin.Space,
        spacingHeight = Skin.SpacingHeight, labelHeight = Skin.LabelHeight,
        inset = Skin.Inset, barWidth = Skin.BarWidth, iconSize = Skin.IconSize,
        barInset = Skin.BarInset, groupWidth = Skin.GroupWidth,
        -- the gates (design §5.5's "gate flags port 1:1")
        groupID = true,            -- :3319
        label = true,              -- :3341 (v1 default ON: the label is what
                                    -- makes a multi-target stack legible --
                                    -- design §8.3, and the assignment's
                                    -- "Show target names")
        showTarget = true,         -- the assignment's "Show target names"
        showID = false,            -- :3318
        spell = false,             -- :3340
        icon = true, iconRight = false,     -- :3326-3327
        time = true, timeRight = false,     -- :3324-3325
        name = true,               -- :3328
        expand = true,             -- :3321 (upward from the frame's BOTTOM)
        flip = false,              -- :3332
        outwands = true,           -- :3333
        iconStacks = true,         -- :3330
        hide = false,              -- :3331
        maxOn = Skin.MaxOn, maxRows = Skin.Max,        -- :3315
        oneMax = true,             -- :3357
        maxTimeOn = true, maxTime = Laws.MAXTIME,      -- :3358
        forceMax = false,          -- :3359
        -- the source's `HideLonger = {[0]=false, 30}` (:3360): the flag AND
        -- its 30 s threshold ride together; Skin.HideTime never existed
        -- (nil until the census ran this gate for the first time).
        hideLonger = false, hideLongerAt = 30,
        hideTime = Laws.HIDE_TIME,                      -- :3337
        hideLongerNoBoss = false,  -- :3361
        blink = true, blinkAt = Laws.BLINK,            -- :3335
        highlight = true,                              -- :3372
        expiredColor = false,                          -- :3371
        colorOverride = nil,                           -- :3309 (off by default)
        spark = true, sparkAlpha = Skin.SparkAlpha,    -- :3409
        ticks = true,                                   -- :3403
        ticksNext = true,      -- :3404 TicksNext (the :3182 row's "Next Tick
                                -- only": one mark, the next one to fire)
        smooth = Laws.SMOOTH,                           -- :3293
        fadeTime = Laws.FADE, failTime = Laws.FAIL,     -- :3339/:3338
        normalAlpha = Skin.NormalAlpha,                 -- :3366
        barBgAlpha = Skin.BarBackgroundAlpha,           -- :3367
        markPredicted = true,                           -- §5.5's UI honesty
        -- the expire-message law (:1049-1056): rows inserted while the gate
        -- is on announce once at expiry (m7 -- the gate, the stamp and the
        -- channel all live; the tests drive them through this key)
        expireMessage = false,
        -- the unit gates (:3349-3355)
        you = true, target = true, focus = true, other = true,
        noTarget = true,
    }
end

--- The live copy the renderer mutates on a colour change.
local function skinCopy()
    local s = {}
    for k, v in pairs(Skin) do s[k] = v end
    s.BarBackgroundAlpha = Skin.BarBackgroundAlpha
    return s
end
M.skin = nil

-- ------------------------------------------------------------- settings map --
--- options key -> setter on this module. The lock rides SetLocked (which
--- publishes the state back); GlobalLock is the General page's shared frame
--- lock; the colours ride SetColor.
local KEYMAP = {
    Enable = "SetEnabled",
    Lock = "SetLocked",
    Scale = "SetScale",
    Alpha = "SetAlphaValue",
    Width = "SetWidth",
    Height = "SetHeight",
    Space = "SetSpace",
    Spacing = "SetSpacing",
    Max = "SetMaxRows",
    ShowTargetNames = "SetShowTarget",
    Label = "SetLabel",
    ShowID = "SetShowID",
    ShowSpellNames = "SetSpellName",
    MaxDisplayTime = "SetMaxTimeValue",
    ExpandUpwards = "SetExpand",
    NormalAlpha = "SetNormalAlpha",
    BarBackgroundAlpha = "SetBarBgAlpha",
    EnableSpark = "SetShowSpark",
    EnableBackdrop = "SetBackdropOn",
    SmartSpace = "SetSmartSpace",
    IconStacks = "SetIconStacks",
    ShowStacks = "SetShowStacks",
    ShowTicks = "SetShowTicks",
    ShowTooltips = "SetShowTooltips",
    AltTimeFormat = "SetAltTimeFormat",
    IconOffset = "SetIconOffset",
    OffsetSelf = "SetOffsetSelf",
    OffsetTarget = "SetOffsetTarget",
    MarkPredicted = "SetMarkPredicted",
    Smooth = "SetSmooth",
    OneMax = "SetOneMax",
    Blink = "SetBlink",
    ExpiredColor = "SetExpiredColor",
    HideLonger = "SetHideLonger",
    HideTime = "SetHideTime",
    MaxOn = "SetMaxOn",
    Outwands = "SetOutwands",
    Flip = "SetFlip",
    LabelHeight = "SetLabelHeight",
    BlinkTime = "SetBlinkTime",
    FadeTime = "SetFadeTime",
    TicksNext = "SetTicksNext",
    GroupID = "SetGroupID",
    AnnounceExpiry = "SetAnnounceExpiry",
    -- The colour law (§5.4). The four `Colour*` keys land on the skin entries
    -- ColorVal reads; Fail (:3375) = ColourFlash[0] and ExpiredColor (:3371) =
    -- ColourExpired[0] per design §1.4; the five `BarColor*` keys land on the
    -- per-unit bar colours (:3387-3391).
    ColourNormal = "SetColour_Normal",
    ColourExpiry = "SetColour_Expiry",
    ColourFlash = "SetColour_Flash",
    ColourExpired = "SetColour_Expired",
    BarColorSelf = "SetColour_BarColorSelf",
    BarColorTarget = "SetColour_BarColorTarget",
    BarColorFocus = "SetColour_BarColorFocus",
    BarColorPet = "SetColour_BarColorPet",
    BarColorEnemy = "SetColour_BarColorEnemy",
    BarColorHostile = "SetColour_BarColorEnemy",
    GlobalLock = "SetLocked",
}
-- The map is the page's census surface (tests/test_module.lua): every key
-- here must be consumed, declared stored, or structural -- the C5 guard that
-- stops a widget shipping with an "Applied live" tip and no consumer. The
-- Advanced page's `TimerStrata` rides NO row here on purpose: the map is
-- THIS page's widget map, and that row is Forte_Options/Pages/Advanced.lua's;
-- the module listens to the shared `Advanced` module in `_WireSettings`.
M.KEYMAP = KEYMAP

--- The stored shape of the wired keys, per settings module (the page's
--- defaults are canonical). Lock is deliberately NOT pulled: the live lock
--- state is the truth and SetLocked publishes it upward (the Timeline's m4
--- law).
local STORED = {
    SpellTimer = { "Enable", "Scale", "Alpha", "Width", "Height", "Space",
        "Spacing", "Max", "ShowTargetNames", "Label", "ShowID",
        "ShowSpellNames", "MaxDisplayTime", "ExpandUpwards", "NormalAlpha",
        "BarBackgroundAlpha", "EnableSpark", "EnableBackdrop", "SmartSpace",
        "IconStacks", "ShowStacks", "ShowTicks", "ShowTooltips",
        "AltTimeFormat", "IconOffset", "OffsetSelf", "OffsetTarget",
        "MarkPredicted", "Smooth", "OneMax", "Blink", "ExpiredColor",
        "HideLonger", "HideTime", "MaxOn", "Outwands", "GroupID",
        "Flip", "LabelHeight", "BlinkTime", "FadeTime", "TicksNext",
        "AnnounceExpiry", "ColourNormal", "ColourExpiry", "ColourFlash",
        "ColourExpired", "BarColorSelf", "BarColorTarget", "BarColorFocus",
        "BarColorPet", "BarColorEnemy" },
    General = {},
    -- The Advanced page's shared keys (Forte_Options/Pages/Advanced.lua):
    -- the module-prefixed strata row of the source's Advanced category.
    Advanced = { "TimerStrata" },
}

function M:ApplySettings(tbl)
    for key, value in pairs(tbl or {}) do
        local m = KEYMAP[key]
        if m and self[m] then self[m](self, value) end
    end
end

--- The Advanced page's keys of this module (the source's own per-module
--- Advanced rows: `TimerStrata`, Forte_Timer.lua:3277). The
--- page-census KEYMAP is deliberately NOT their route -- the page that
--- carries them is Forte_Options/Pages/Advanced.lua's, and its rows name the
--- setter directly (the source's `STR` row type, `Options.lua:5574-5592`).
local ADVANCED_KEYMAP = { TimerStrata = "SetStrata" }

function M:ApplyAdvancedSettings(tbl)
    for key, value in pairs(tbl or {}) do
        local m = ADVANCED_KEYMAP[key]
        if m and self[m] then self[m](self, value) end
    end
end

function M:ApplyStoredSettings()
    local st = FX.Settings
    if not st or not st.IsRegistered then return end
    for module, keys in pairs(STORED) do
        if st:IsRegistered(module) then
            local out = {}
            for i = 1, #keys do out[keys[i]] = st:Get(module, keys[i]) end
            if module == "Advanced" then
                self:ApplyAdvancedSettings(out)
            else
                self:ApplySettings(out)
            end
        end
    end
end

function M:_WireSettings()
    local st = FX.Settings
    if not st or not st.OnChange or self._wired then return end
    self._wired = true
    st:OnChange("SpellTimer", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
    -- The two shared lock keys: /fx lock|unlock moves the Cooldown bar's lock
    -- and General's GlobalLock; this panel follows (the Hunter swing bar's
    -- mirroring law -- no Forte_Cooldown change is needed).
    st:OnChange("Cooldown", function(key, value)
        if key == "Lock" then self:SetLocked(not not value) end
    end)
    st:OnChange("General", function(key, value)
        if key == "GlobalLock" then self:SetLocked(not not value) end
    end)
    st:OnChange("Advanced", function(key, value)
        self:ApplyAdvancedSettings({ [key] = value })
    end)
end

-- ----------------------------------------------------------------- setters --
function M:SetEnabled(on)
    self.options.enable = not not on
    local d = FX.Timer.Display
    if d and d.SetEnabled then d:SetEnabled(self.options.enable) end
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

--- The Advanced page's strata row for this panel (the source's
--- `TimerStrata`, Forte_Timer.lua:3277; default `Strata = "MEDIUM"`,
--- :2531). The frame call is the display's.
function M:SetStrata(name)
    local up = strataOrNil(name)
    if not up then return end
    self.options.strata = up
    local d = FX.Timer.Display
    if d and d.SetStrata then d:SetStrata(up) end
end

function M:SetWidth(v)
    if type(v) ~= "number" or v <= 0 then return end
    local o = self.options
    o.width = v
    o.barWidth = v - o.height - 1
    o.groupWidth = v + Skin.Inset * 2
    o.barInset = o.height + 1 + Skin.Inset
    local d = FX.Timer.Display
    if d and d.SetSize then d:SetSize(o.width, o.height) end
end

function M:SetHeight(v)
    if type(v) ~= "number" or v <= 0 then return end
    local o = self.options
    o.height = v
    o.iconSize = v
    o.barWidth = o.width - v - 1
    o.barInset = v + 1 + Skin.Inset
    local d = FX.Timer.Display
    if d and d.SetSize then d:SetSize(o.width, o.height) end
end

function M:SetMaxRows(v)
    if type(v) ~= "number" or v <= 0 then return end
    self.options.maxRows = math.floor(v)
end

function M:SetMaxOn(on) self.options.maxOn = not not on end
--- m6: the two label keys have ONE shared effect (the renderer ANDs them:
--- UI/Rows.lua's `labelled`) and two independent stores -- this setter used
--- to write `label` too, so unchecking ShowTarget silently desynced the
--- Label checkbox/store from the screen. It writes its own key only.
function M:SetShowTarget(on)
    self.options.showTarget = not not on
end
function M:SetLabel(on) self.options.label = not not on end
function M:SetShowID(on) self.options.showID = not not on end
function M:SetSpellName(on) self.options.spell = not not on end
function M:SetExpand(on) self.options.expand = not not on end
function M:SetOutwands(on) self.options.outwands = not not on end
--- The bar direction (`Flip`, :3332, the "Flip bar direction" row :3149): the
--- source mirrors its bar's fill (NewStatusBar's `SetFlipped` :1647-1655 —
--- the fill texture rides the RIGHT edge and crops `TexCoord(1-v,1,0,1)`,
--- :1660-1662), and with it the spark (:2536-2540) and the tick marks
--- (:1797/:1806). The renderer carries all three; the engine StatusBar can
--- only fill in the source's default direction, so the mirrored fill rides
--- UI/Rows.lua's own fill texture.
function M:SetFlip(on) self.options.flip = not not on end
function M:SetGroupID(on) self.options.groupID = not not on end
function M:SetIconStacks(on) self.options.iconStacks = not not on end
function M:SetMarkPredicted(on) self.options.markPredicted = not not on end
function M:SetShowTicks(on) self.options.ticks = not not on end
function M:SetShowSpark(on) self.options.spark = not not on end

function M:SetSmooth(v)
    if type(v) ~= "number" or v <= 0 then return end
    self.options.smooth = v
end

function M:SetMaxTimeValue(v)
    if type(v) ~= "number" or v <= 0 then return end
    self.options.maxTime = v
end

function M:SetMaxTimeOn(on) self.options.maxTimeOn = not not on end
function M:SetOneMax(on) self.options.oneMax = not not on end
function M:SetForceMax(on) self.options.forceMax = not not on end
function M:SetBlink(on) self.options.blink = not not on end
function M:SetExpiredColor(on) self.options.expiredColor = not not on end
function M:SetHideLonger(on) self.options.hideLonger = not not on end

function M:SetHideTime(v)
    if type(v) ~= "number" or v <= 0 then return end
    self.options.hideTime = v
end

function M:SetNormalAlpha(v)
    if type(v) ~= "number" then return end
    self.options.normalAlpha = math.max(0, math.min(1, v))
    self.skin.NormalAlpha = self.options.normalAlpha
end

function M:SetBarBgAlpha(v)
    if type(v) ~= "number" then return end
    self.options.barBgAlpha = math.max(0, math.min(1, v))
    self.skin.BarBackgroundAlpha = self.options.barBgAlpha
end

--- A colour row of the shipped palette (the page's COL widgets hand over the
--- positional { r, g, b, a } shape).
function M:SetColorRow(key, col)
    if type(col) ~= "table" then return end
    self.skin[key] = { col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1 }
end

for _, key in ipairs({ "SelfBuff", "TargetDebuff", "Crowds", "Cooldown",
    "SelfDebuff", "Channel", "Fail", "Highlight", "Expired" }) do
    local names = { SelfBuff = "SelfBuff", TargetDebuff = "TargetDebuff",
        Crowds = "Crowds", Cooldown = "Cooldown", SelfDebuff = "SelfDebuff",
        Channel = "Channel", Fail = "Fail", Highlight = "HighlightColor",
        Expired = "ExpiredColor" }
    M["SetColor_" .. key] = function(self, col)
        self:SetColorRow(names[key], col)
    end
end

function M:SetBarColor(col) self:SetColorRow("BarColor", col) end
function M:SetBgColor(col) self:SetColorRow("NormalBgColor", col) end

-- The §5.4 colour keys. ColourNormal is the SOURCE's text colour (Skin's
-- NormalColor, :3396 -- the time text :1856, the group label :2073, the bar
-- name :2528; the renderer reads it in UI/Rows.lua's BindRow), ColourFlash
-- the flash entry (`Fail`, :3350), ColourExpired the expired entry
-- (`ExpiredColor`, :3351); the five BarColor* keys are stored for the
-- per-caster colour work (§5.4, design §3.6) -- the source colours bars
-- PER CATEGORY (ColorVal), not per unit, so their tips say stored.
function M:SetColour_Normal(v) self:SetColorRow("NormalColor", v) end
function M:SetColour_Expiry(v) self:SetColorRow("ColourExpiry", v) end
function M:SetColour_Flash(v)
    self:SetColorRow("ColourFlash", v)
    self:SetColorRow("Fail", v)
end
function M:SetColour_Expired(v)
    self:SetColorRow("ColourExpired", v)
    self:SetColorRow("ExpiredColor", v)
end
function M:SetColour_BarColorSelf(v) self:SetColorRow("BarColorSelf", v) end
function M:SetColour_BarColorTarget(v) self:SetColorRow("BarColorTarget", v) end
function M:SetColour_BarColorFocus(v) self:SetColorRow("BarColorFocus", v) end
function M:SetColour_BarColorPet(v) self:SetColorRow("BarColorPet", v) end
function M:SetColour_BarColorEnemy(v) self:SetColorRow("BarColorEnemy", v) end

-- The rest of the §5.4 keys, all applied live.
function M:SetScale(v)
    if type(v) ~= "number" or v <= 0 then return end
    self.options.scale = v
    local d = FX.Timer.Display
    if d and d.anchor and d.anchor.SetScale then d.anchor:SetScale(v) end
end
function M:SetAlphaValue(v)
    if type(v) ~= "number" then return end
    self.options.alpha = math.max(0, math.min(1, v))
    local d = FX.Timer.Display
    if d and d.anchor and d.anchor.SetAlpha then
        d.anchor:SetAlpha(self.options.alpha)
    end
end
function M:SetSpace(v)
    if type(v) ~= "number" or v < 0 then return end
    self.options.space = v
end
function M:SetSpacing(v)
    if type(v) ~= "number" or v < 0 then return end
    self.options.spacingHeight = v
end
--- The unit label height (:3242 row, def 18 `:3344`): the strip the group's
--- header rides inside. The renderer's group box height and the header's
--- `headerY` both derive from it, so a change is a layout change (UI/Rows.lua
--- `o.labelHeight`).
function M:SetLabelHeight(v)
    if type(v) ~= "number" or v < 0 then return end
    self.options.labelHeight = v
end
--- `Ticks = {[0]=true,0.3}` + `TicksNext` (:3403/:3404): the "Next Tick only"
--- half of the :3182 row. The renderer's tick pass draws the one mark of the
--- schedule that fires next (the source's :1775-1791 branch).
function M:SetTicksNext(on) self.options.ticksNext = not not on end
--- `Blink = {[0]=true,3}` (:3335, the :3195 row): the seconds under which the
--- row's background starts its pulse. `Laws.ColorVal` reads `blink`/`blinkAt`
--- (:1562-1569) — the source's expiry cue, no colour change.
function M:SetBlinkTime(v)
    if type(v) ~= "number" or v < 0 then return end
    self.options.blinkAt = v
end
--- `FadeTime` (:3339, the "Standard fade delay" row :3193, def 1): the ghost
--- time a row rides past its window before the fade-out ramp has run. It is
--- the `Alpha(removeAt + s.FadeTime, t)` of the source's visibility law
--- (:2166) — `Laws.GateAlpha` reads it.
function M:SetFadeTime(v)
    if type(v) ~= "number" or v < 0 then return end
    self.options.fadeTime = v
end
function M:SetBackdropOn(on)
    self.options.backdrop = not not on
    self.skin.EnableBackdrop = self.options.backdrop
end
function M:SetSmartSpace(on) self.options.smartSpace = not not on end
function M:SetShowStacks(on) self.options.showStacks = not not on end
function M:SetShowTooltips(on) self.options.tooltips = not not on end
--- m7: the production gate of the expire-message law (:1049-1056, col-12
--- stamp). A row inserted while the gate is on is stamped and announces at
--- expiry through `announceExpiry` (the source's fade-message channel; the
--- announce pages are the source's RaidMsg/SelfMsg, dimmed there, off here).
function M:SetAnnounceExpiry(on) self.options.expireMessage = not not on end
function M:SetAltTimeFormat(on) self.options.altTimeFormat = not not on end
function M:SetIconOffset(v)
    if type(v) ~= "number" or v < 0 then return end
    self.options.barInset = v
end
function M:SetOffsetSelf(v)
    if type(v) ~= "number" then return end
    self.options.offsetSelf = v
end
function M:SetOffsetTarget(v)
    if type(v) ~= "number" then return end
    self.options.offsetTarget = v
end

--- The panel's own lock: mouse-off, the title hidden, and the state published
--- into SpellTimer.Lock (store-inequality guarded, so the options checkbox and
--- /fx lock|unlock can not disagree).
function M:SetLocked(locked)
    locked = not not locked
    local d = FX.Timer.Display
    -- m9: Display.cfg IS self.cfg (both are FX.db.timer.display, see
    -- OnEnable), so the one write persists both directions; the old
    -- "only while unlocking" twin branch was unreachable-effect code.
    if d and d.cfg then d.cfg.locked = locked end
    local st = FX.Settings
    if st and st.IsRegistered and st:IsRegistered("SpellTimer")
        and st:Get("SpellTimer", "Lock") ~= locked then
        st:Set("SpellTimer", "Lock", locked)
    end
    if d and d.SetLocked then d:SetLocked(locked) end
end

-- ------------------------------------------------------------------ enable --
--- The announce channel of the expire-message law (:1049-1056, the source's
--- `CA:CastShow(ST_OnTimerFade[...])` + sound): the chat line. Called as
--- `opts.onExpire(row)` from Core/Rows.lua's Sweep, which fires it only for
--- rows stamped at insert -- and rows are stamped only while the
--- AnnounceExpiry gate is on, so rows born under "off" stay silent.
local function announceExpiry(row)
    if not FX.Print then return end
    FX.Print(string.format("Forte: %s expired on %s", tostring(row.name),
        (row.targetKey == "none") and "you" or tostring(row.targetKey)))
end

--- The module's clock: the Casts' injectable clock so a test can freeze time
--- across the whole spine (the rows, the queue, the sweep and the draw), and
--- the engine clock in play.
function M:Clock()
    local C = FX.Timer.Casts
    if C and C.Clock then return C:Clock() end
    return GetTime()
end

--- The 0.04 s display pass. Ticker-driven (an always-live driver: a hidden
--- anchor's OnUpdate never runs -- the 2026-11-02 uiforever finding), and
--- callable by hand from the row-arrival hook so the panel is SHOWN before any
--- OnUpdate is relied on.
function M:Draw()
    local d = FX.Timer.Display
    if not d or not self.options.enable or self.options.hide then return end
    local now = self:Clock()
    local links, n = Rows:Sorted(self._links, now)
    d:Update(links, n, self.options, self.skin)
end

function M:Logic()
    local now = self:Clock()
    -- TEST MODE GATES (`/fx test`, Forte_Core/Core/TestMode.lua). The two
    -- writers of this pass are parked for the demo -- `Casts:Pump` is the cast
    -- queue's insert path (a real insert is a real row, and the pump is fed by
    -- the event spine parked below) and `Reconcile:SweepAll` is the aura pass
    -- that ADOPTS, EXTENDS, REFRESHES and fades rows it finds, which over rows
    -- the demo invented would be a real read annotating a fiction. `Rows:Sweep`
    -- is NOT gated: it is the row lifecycle machine (the expiry, the fade, the
    -- compaction) that the synthetic rows must ride exactly as a real one does
    -- so the panel animates. CooldownMaster's rule for the same feature:
    -- "all feeds are skipped while Test Mode is active" (Core/Cooldown.lua
    -- :233-255).
    local demo = FX.TestMode and FX.TestMode:IsActive()
    if not demo then
        FX.Timer.Casts:Pump(now)
    end
    Rows:Sweep(now)
    -- the 0.5 s safety sweep of the aura law: gated, so it costs nothing while
    -- the client says aura reads are secret
    if not demo then
        FX.Timer.Reconcile:SweepAll(now)
    end
end

--- The synchronous kick every signal rides: the panel must be up before its
--- own OnUpdate is relied on, and the draw is idempotent + allocation-free.
function M:Kick()
    if not self.options or not self.options.enable then return end
    self:Draw()
end

-- ======================================================== Test Mode (I-3c) ==
--- The `/fx test` donor law (docs/research/upstream-addons-2026-11-03.md §6
--- "Test Mode"): the rows are drawn from THIS panel's own registered pool --
--- `FX.Timer.Registry.entries`, this class's registered spells, the names of
--- the generated data -- inserted through the panel's own insert path
--- (`Rows:InsertFromCast`, the same one `/fx timer test` rides), and tagged. No
--- spell id is typed, no name is compared against a client name
--- (docs/localization.md), and no unit is invented: every row rides
--- `targetKey = "none"`, the panel's own self/no-target key, so the group key
--- is a PRIOR_* sentinel and no consumer resolves the row against a live unit
--- (the CDM demo law: synthetic entries carry no `dObj`).
--- The two public legs are disarmed at the seam -- `expireMsgAt` is the
--- announce stamp (`opts.onExpire` = the module's printed expiry line) and
--- `fadeWarn` is the FX_TIMER_FADING threshold -- so a demo row can not reach
--- a chat line even if `AnnounceExpiry` is on; the fire-side gates in
--- Core/Rows.lua carry the same law for the expiry and break events.
--- K2 (PLAN §11.4): the feed carries `Target = DEMO_ROWS`, so the 1 Hz pump
--- tops the panel UP as rows run out (the idempotent fill below -- a donor
--- with a live tagged row is left alone, so a top-up never stacks a second
--- row of the same name and never touches a real row); the live check of
--- 2026-11-04 watched the panel run down between the all-rows-gone refills.
local DEMO_ROWS = 4
local demoScratch = {}

--- The names that are the demo's RIGHT NOW: the idempotence key of the fill.
--- A panel row is keyed (name, "none"), so one live tagged row per donor
--- name is one live row.
local demoSeen = {}
local function taggedNames()
    wipe(demoSeen)
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and FX.TestMode.IsSynthetic(row) then
            demoSeen[row.name] = true
        end
    end
    return demoSeen
end

local function demoFill(now)
    now = now or M:Clock()
    local pool, n = demoScratch, 0
    for name in pairs(FX.Timer.Registry.entries) do
        n = n + 1
        pool[n] = name
    end
    if n == 0 then return 0 end
    table.sort(pool)
    local take = math.min(DEMO_ROWS, n)
    local live = taggedNames()
    local created = 0
    for i = 1, take do
        local name = pool[math.floor((i - 1) * n / take) + 1]
        -- The K2 idempotence: a donor whose window is still running (the
        -- demo's own tagged row, or a real row the demo has no claim on --
        -- `Rows:Find` is the panel's own key lookup) is LEFT ALONE, so the
        -- pump's top-up pass adds only the donors that ran out.
        if not live[name] and not Rows:Find(name, "none") then
            local dur = FX.Timer.Registry.BestDuration(name)
            if type(dur) == "number" and dur > 0 then
                -- The stamp rides the PAST, spread across the row's own
                -- window, so the panel opens on rows that are running (a
                -- stamp in the future is a negative elapsed, which the
                -- arrival-highlight law reads as "arrived": the finding
                -- `/fx timer test` documents).
                local started = now - (dur * (i - 1) / take)
                local row = Rows:InsertFromCast(name, "none", dur, started,
                    started, 1)
                if row then
                    row.expireMsgAt = 0
                    row.fadeWarn = 0
                    FX.TestMode.Tag(row)
                    created = created + 1
                end
            end
        end
    end
    -- The synchronous-show law of this panel (the hidden anchor gets no
    -- OnUpdate): a row arrives with the panel shown, in the same pass.
    M:Kick()
    return created
end

--- Scrub: drop every tagged row, then close the holes at once (the compaction
--- `Sweep` would run at its tail cannot be deferred behind a `Sorted` pass).
local function demoScrub()
    local n = 0
    for i = Rows.rows_n, 1, -1 do
        local row = Rows.rows[i]
        if row and FX.TestMode.IsSynthetic(row) then
            Rows:removeAt(i)
            n = n + 1
        end
    end
    Rows:Compact()
    M:Kick()
    return n
end

local function demoCount()
    local n = 0
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and FX.TestMode.IsSynthetic(row) then n = n + 1 end
    end
    return n
end

function M:OnEnable()
    self.options = defaultOptions()
    self.skin = skinCopy()
    self._links = {}
    -- SavedVariables (design §3.4's `learned`, plus the panel's own position).
    if FX.db then
        FX.db.timer = FX.db.timer or {}
        FX.db.timer.learned = FX.db.timer.learned or {}
        FX.db.timer.display = FX.db.timer.display or {}
        FX.Timer.Registry:AttachStorage(FX.db.timer.learned)
        self.cfg = FX.db.timer.display
    else
        -- SavedVariables never arrived (the beta bug class): the panel keeps
        -- its locks and learned durations for the session.
        self.cfg = {}
        FX.Timer.Registry:AttachStorage({})
    end
    for k, v in pairs(M.DEFAULT_POSITION) do
        if self.cfg[k] == nil then self.cfg[k] = v end
    end

    FX.Timer.Registry:Build(FX._playerClass)
    FX.Timer.Casts:Init(Rows, self.options)
    FX.Timer.Reconcile:Init(Rows, self.options)
    Rows.options = self.options
    self.options.onExpire = announceExpiry          -- m7's announce channel
    FX.Timer.Casts.onRow = function() self:Kick() end
    self:_WireSettings()
    self:ApplyStoredSettings()

    local d = FX.Timer.Display
    if d then
        d:Init(self.options, self.skin, self.cfg)
        d:SetLocked(self.cfg.locked and true or false)
        self:SetLocked(self.cfg.locked and true or false)
    end

    -- One frame, created inside the PLAYER_LOGIN handler (see the header).
    local f = CreateFrame("Frame")
    self._eventFrame = f
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_START", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    f:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    -- The pet feed (wave 2b "PetRows v2", PLAN §11.1): the same family,
    -- registered for the pet unit. SENT + SUCCEEDED only -- the pet has no
    -- START/FAIL/INTERRUPT row law here (the original's pet half had no
    -- fail band either: Forte_Casting.lua:653-664 ships Success/Failed/Start
    -- to the CLASS add-on, never to the timer queue), and a pet event with
    -- no pet to produce it is simply no event. The payload's leading unit
    -- token is ours to read (a unit token is plain text), classified at the
    -- callee -- that token is what routes the two feeds.
    f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "pet")
    f:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "pet")
    f:RegisterUnitEvent("UNIT_AURA", "player")
    f:RegisterUnitEvent("UNIT_AURA", "target")
    f:RegisterUnitEvent("UNIT_DIED", "target")
    f:RegisterEvent("PLAYER_TARGET_CHANGED")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:RegisterEvent("PLAYER_REGEN_DISABLED")
    f:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    f:RegisterEvent("PLAYER_LEAVING_WORLD")
    f:RegisterEvent("PLAYER_DEAD")
    -- The bindings are explicit (`function(_, event, ...)`) -- the frame is
    -- argument 1, and a vararg binding forwards it as `event` (api_lint
    -- rejects that shape; the Forte_Hunter bug of 2026-11-02).
    f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
        M:OnEvent(event, a1, a2, a3, a4)
    end)

    -- The two cadences, both ticker-driven so they run while the panel is
    -- hidden (PLAN §3.4's ~10 Hz display / ~1 Hz rescan).
    local ticks = 0
    C_Timer.NewTicker(DRAW_SECONDS, function()
        ticks = ticks + 1
        M:Draw()
        if ticks % 12 == 0 then M:Logic() end
    end)

    -- `/fx test` (Forte_Core/Core/TestMode.lua): this panel owns these rows.
    -- Registered in the enable, idempotent by name (a re-enable replaces the
    -- pair, so the fill can not double).
    if FX.TestMode then
        FX.TestMode.RegisterFeeder({ Name = "SpellTimer", Fill = demoFill,
            Scrub = demoScrub, Live = demoCount, Target = DEMO_ROWS })
    end

    -- The pages are Forte_Options' framework; registering from here is the
    -- point where every addon chunk has run (the Hunter page's law).
    local pages = FX.Timer.Pages
    if pages and pages.RegisterTimerPage then pages.RegisterTimerPage() end
end

--- The event spine. The payload fields arrive as `a1..a4` and are classified
--- at the callee (PlainOrNil), never compared here. The ONE exception is the
--- leading unit token `a1`: a unit token is OURS to read (plain text, the
--- UNIT_AURA law below), and for the SPELLCAST family it is what tells the
--- player's casts from the pet's (the registration set: the family rides for
--- "player" AND for "pet"). The token is classified through PlainOrNil
--- before the compare, and the pet branch hands the payload to the pet half
--- of the feed; every non-pet token -- "player", a sealed read, the tests'
--- token-free shape -- rides the v1 player path untouched.
--- The `/fx test` parked set: the events of the feed spine whose whole job is
--- a row WRITE (a cast fact into the queue, an aura fact into a sweep, a target
--- change into a sweep). The cleanups and the read-only secret-state
--- snapshots are deliberately absent: they must keep running during a demo.
local DEMO_PARKED = {
    UNIT_SPELLCAST_SENT = true,
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_SUCCEEDED = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_AURA = true,
    PLAYER_TARGET_CHANGED = true,
}

function M:OnEvent(event, a1, a2, a3, a4)
    -- TEST MODE GATE (`/fx test`, Forte_Core/Core/TestMode.lua): the feed spine
    -- is parked while the demo owns the panel -- every event below is a cast,
    -- a hit or an aura fact that ends in a row insert, an adopt or a fade, and
    -- a real row landing on a demo panel is the mixed frame the upstream law
    -- exists to prevent ("all feeds are skipped while Test Mode is active",
    -- CooldownMaster Core/Cooldown.lua:233-255). What is deliberately NOT
    -- parked: the two secret-state snapshots (they read, they never write),
    -- PLAYER_LEAVING_WORLD / PLAYER_DEAD (the erase-everything cleanup, which
    -- is also the mode's own scrub path -- FX.TestMode stops on the same
    -- events) and UNIT_DIED's row fade, which retires a row of a dead unit and
    -- must never be skipped.
    if FX.TestMode and FX.TestMode:IsActive() and DEMO_PARKED[event] then
        return
    end
    local C = FX.Timer.Casts
    local caster = FX.Compat.PlainOrNil(a1)
    local isPet = type(caster) == "string" and caster == "pet"
    if event == "UNIT_SPELLCAST_SENT" then
        -- (unitTarget, target, castGUID, spellID)
        if isPet then
            C:OnPetSent(a2, a4)
        else
            C:OnSent(a2, a4)
        end
    elseif event == "UNIT_SPELLCAST_START" then
        -- (unitTarget, castGUID, spellID, castID)
        C:OnStart(a3)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unitTarget, castGUID, spellID, castBarID) -- the 4th field is
        -- tolerated (PLAN §8 mitigation 3)
        if isPet then
            C:OnPetSucceeded(a3)
        else
            C:OnSucceeded(a3)
        end
    elseif event == "UNIT_SPELLCAST_FAILED" then
        -- (unitTarget, castGUID, spellID, reason, ...)
        C:OnFailed(a3, a2)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        -- (unitTarget, castGUID, spellID)
        C:OnFailed(a3, a2)
    elseif event == "UNIT_AURA" then
        -- (unitTarget, updateInfo): the token is OURS to read (a unit token
        -- is plain text); the throttled per-row sweep is the timed one, so the
        -- event only nudges it forward.
        local token = FX.Compat.PlainOrNil(a1)
        local now = GetTime()
        local last = FX.Timer.Reconcile.lastSweep[token]
        if type(token) == "string"
            and (not last or now - last > FX.Timer.Reconcile.throttle) then
            FX.Timer.Reconcile:SweepUnit(token,
                token == "player" and "HELPFUL" or "HARMFUL", now)
            M:Kick()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        FX.Timer.Reconcile.lastSweep["target"] = nil
        FX.Timer.Reconcile:SweepUnit("target", "HARMFUL")
        M:Kick()
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- combat started: re-snapshot the secrecy mode
        FX.Timer:RefreshSecretState()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- out of combat: every read is plain again. Refresh FIRST so the sweep
        -- runs in the mode it is about to see, then the full sweep (the design's
        -- "combat end" trigger: adopt / extend / refresh / fade AND learn).
        FX.Timer:RefreshSecretState()
        -- TEST MODE GATE (`/fx test`): the sweep is the aura writer; the
        -- snapshot above is a read and keeps running.
        if not (FX.TestMode and FX.TestMode:IsActive()) then
            FX.Timer.Reconcile:SweepAll()
            M:Kick()
        end
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        FX.Timer:RefreshSecretState()
    elseif event == "UNIT_DIED" then
        -- the guid is SecretWhenUnitIdentityRestricted: it is classified and
        -- never compared (design §2's death-cleanup verdict: cleanup rides
        -- row-expiry, this is the opportunistic half).
        local guid = FX.Compat.PlainOrNil(a1)
        if type(guid) == "string" then
            for i = 1, Rows.rows_n do
                local row = Rows.rows[i]
                if row and row.state <= Laws.NORMAL
                    and row.unitToken == "target" then
                    local ok, exists = pcall(UnitExists, "target")
                    if ok and FX.Compat.PlainOrNil(exists) == false then
                        Rows:Fade(row, Laws.REMOVE, GetTime())
                    end
                end
            end
        end
    elseif event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_DEAD" then
        C:Erase()
        Rows:Clear()
        local d = FX.Timer.Display
        if d and d.RenderIdle then d:RenderIdle() end
    end
end

--- The secrecy-mode snapshot lives in Forte_Core (FX.SecretState); this is the
--- call site, pcall-protected the way Forte_Cooldown/Module.lua:291 does it.
function FX.Timer.RefreshSecretState()
    if FX.SecretState and FX.SecretState.Refresh then
        local ok, err = pcall(FX.SecretState.Refresh)
        if not ok and FX.Print then
            FX.Print("|cffff5555secret-state refresh failed:|r " .. tostring(err))
        end
    end
end

--- The `/fx status` block (Forte_Core's status loop calls Status per module).
function M:Status()
    local opts = self.options
    if not opts then
        FX.Print("Timer: not enabled")
        return
    end
    local n = Rows:Count()
    local predicted = 0
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and row.predicted and row.state <= Laws.REMOVE then
            predicted = predicted + 1
        end
    end
    local tracked, learned = FX.Timer.Registry:Counts()
    FX.Print(string.format(
        "Timer: %d tracked, %d learned | %d rows (%d predicted) | %dx%d | %s",
        tracked, learned, n, predicted, opts.width, opts.height,
        (self.cfg and self.cfg.locked) and "locked" or "unlocked"))
    FX.Print(string.format(
        "  laws: maxlag %.2f | buffdelay %.1f | settle %.2f | smooth %g | maxtime %g | blink %g",
        Laws.MAXLAG, Laws.BUFF_DELAY, Laws.SETTLE, opts.smooth, opts.maxTime,
        opts.blinkAt))
    FX.Print(string.format(
        "  expire messages announced: %d (gate %s)",
        FX.Timer.NotifyExpiry or 0,
        tostring(not not opts.expireMessage)))
    FX.Print(FX.Timer.Casts:StatusLine())
    FX.Print(FX.Timer.Reconcile:StatusLine())
    if FX.SecretState and FX.SecretState.StatusLine then
        FX.Print(FX.SecretState.StatusLine())
    end
    for i = 1, Rows.rows_n do
        local row = Rows.rows[i]
        if row and row.state <= Laws.REMOVE then
            FX.Print(string.format("  %s%s: %.1fs%s", row.name,
                row.targetKey ~= "none" and (" on " .. row.targetKey) or "",
                math.max(0, row.expireAt - GetTime()),
                row.predicted and " (predicted)" or " (anchored)"))
        end
    end
end

--- `/fx timer status|clear|test` -- the debug seam (the sim has no real
--- combat state, PLAN §10.3, so a synthetic feeder is the only deterministic
--- way to see the panel on a live client).
FX.RegisterSlash("timer", function(rest)
    local sub = (rest or ""):match("^(%S+)")
    if sub == "clear" then
        Rows:Clear()
        FX.Timer.Casts:Erase()
        local d = FX.Timer.Display
        if d and d.RenderIdle then d:RenderIdle() end
        FX.Print("timer rows cleared")
    elseif sub == "test" then
        local names = {}
        for name in pairs(FX.Timer.Registry.entries) do
            names[#names + 1] = name
        end
        table.sort(names)
        -- One row per distinct KIND, first name wins: this feed is the
        -- palette check, so it has to show rows that say what they ARE --
        -- five same-coloured rows prove nothing. Name-shape through
        -- Registry.KindFor; no spell id is read or written here.
        local picked, seenKind, isPicked = {}, {}, {}
        for _, name in ipairs(names) do
            if #picked < 5 then
                local kind = FX.Timer.Registry.KindFor(name)
                if not seenKind[kind] then
                    seenKind[kind] = true
                    isPicked[name] = true
                    picked[#picked + 1] = name
                end
            end
        end
        for _, name in ipairs(names) do
            if #picked >= 5 then break end
            if not isPicked[name] then
                isPicked[name] = true
                picked[#picked + 1] = name
            end
        end
        local now = GetTime()
        local targets = { "Dummy-1", "Dummy-2" }
        -- The stamps go into the PAST, settled: a second apart and the
        -- newest row already past the arrival flash, so the debug view
        -- shows each row's KIND colour -- which is what the feed exists to
        -- be looked at. A stamp dated in the FUTURE has a negative elapsed,
        -- and the arrival-highlight law ((total - remaining) < 0.5,
        -- Core/Laws.lua) reads that as "arrived" and mixes with a clamped
        -- factor -- which is why every row the old feed seeded read pure
        -- white. A real cast still gets its arrival flash.
        for i = 1, #picked do
            local name = picked[i]
            local dur = FX.Timer.Registry.BestDuration(name)
            local started = now - (0.75 + (i - 1))
            Rows:InsertFromCast(name, targets[((i - 1) % 2) + 1], dur,
                started, started, 1)
        end
        FX.Print(string.format("timer: seeded %d predicted rows",
            #picked))
        M:Kick()
    else
        FX.Print("timer: /fx timer status | clear | test")
        M:Status()
    end
end)
