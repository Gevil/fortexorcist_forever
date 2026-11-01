-- Forte_Cooldown/UI/Timeline.lua
-- The Classic Cooldown Timer, PLAN.md §3.5: ONE 250x24 timeline bar (not a
-- stack of rows -- the rows are the Spell Timer, §3.6; the old row renderer
-- lives on as UI/Rows.lua, dormant, the Phase-4 seed). Cooldowns ride a
-- power-scale time axis: the icon for t seconds remaining sits at
-- TimelineMath.pos(t) and slides left as it burns, parking at the right end
-- over Max = 300 s; custom time tags (0 1 10 30 60 120 ...) print under the
-- same curve; icons overlapping by more than half an icon form a group that
-- cross-fades focus between its members (~1 s each); at the end of a
-- cooldown the icon lands at the left end and pulses a Spark2 glow before
-- vanishing; a fresh cast flashes a 4x splash. Source law:
-- /tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua (render loop :499-642, tags
-- :1233-1330, defaults :1801-1874).
--
-- Registers as FX.Cooldown.Display: the public API of the old row Display
-- (Init, Update, SetLocked, Reset, Slash, SavePosition, ApplyPosition,
-- OnReady) is kept exactly, so Forte_Core/Core/Init.lua's `/fx
-- lock|unlock|reset` hook and Module.lua's ticker need no change.
--
-- It is a pure renderer: it NEVER reads unit/aura/cooldown APIs. The Module
-- feeds the Engine's plain, sorted scratch array ({ name, start, duration,
-- endTime, predicted, charges, maxCharges, rechargeEnd, category, icon })
-- at 10 Hz plus ready names through OnReady(); we keep no references to it
-- (only the transient e.x position tag for grouping).
-- `charges`/`maxCharges` (the current count) drive the icon's charge number
-- and `rechargeEnd` the icon's position for a multi-charge bar; `category`
-- picks the colour out of TimelineSkin.Colors (default "Spell") and `icon`
-- overrides the spell-icon lookup (items/potions). Every one of those is
-- optional: a row without them renders exactly as before.
--
-- PLAN.md §3.4 rules: frames are created inside Init/Acquire* only; the slot,
-- splash and pulse pools only grow (acquire/hide, never destroy); every style
-- setter is dirty-checked because the whole pass runs at 10 Hz. Positions,
-- tag placement and grouping are frame-free in UI/TimelineMath.lua.
--
-- Slots bind by entry NAME, never by index: a slot keeps its name for its
-- whole life on the bar, so a name is seen (splash + fade-in) exactly once;
-- when a cooldown ends and the entries shift up, the shift is purely
-- positional. Index order drives position, segment and alpha; texture,
-- colour, fade start and splash are per-name. A name that leaves the feed
-- releases its slot (hidden, back on the free list, identity dropped) and a
-- later cast of the same name is a fresh first sighting.
--
-- Font: the owner font decision (2026-11-01) is the libre Century-Gothic
-- lookalike URWGothic-Book.ttf at size 11 (the .otf twin next to it is license
-- source only). The file is validated once (CreateFont + SetFont/GetFont
-- round-trip on a throwaway string): any fontstring that did not take it
-- keeps its GameFontHighlightSmall template. FX.Cooldown.Display.fontFile is
-- the accepted path, nil = every string on the template fallback.
--
-- Position + lock state live in FX.db.cooldownDisplay.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.Cooldown = FX.Cooldown or {}
local TM = FX.Cooldown.TimelineMath

local D = {}
FX.Cooldown.Display = D

-- ------------------------------------------------------------ timeline skin --
-- Vendored values from ForteXorcist v1.980.8 FW.InstanceDefault.Cooldown
-- (:1801-1874, GPL-3.0, see addon/Forte_Core/ATTRIBUTION.md).
local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"

FX.Cooldown.TimelineSkin = {
    Width = 250, Height = 24,                 -- FW Width/Height
    Max = 300, Loga = 0.33,                   -- the power axis (:1816, :1836)
    CustomTags = "0 1 10 30 60 120 300 600",  -- CustomTags[1] (:1840)
    BackdropBG = TEX .. "Background",         -- Backdrop[1]
    BackdropEdge = TEX .. "Border",           -- Backdrop[2]
    BackdropTile = false,                     -- Backdrop[3]
    BackdropTileSize = 16,                    -- Backdrop[4]
    BackdropEdgeSize = 5,                     -- Backdrop[5]
    Inset = 3,                                -- Backdrop[6]
    BgColor = { 0, 0, 0, 0.50 },              -- BgColor: black a 0.50
    BarTexture = TEX .. "Aluminium",          -- FW.Default.Texture
    BarColor = { 1, 1, 1, 0.20 },             -- BarColor: white a 0.20
    TextColor = { 1, 1, 1, 0.20 },            -- TextColor (tag labels)
    TimeFormatAlt = false,                    -- General AltTimeFormat:
                                              -- m:ss for EVERY time
    -- Charge-count text (the icon's BOTTOMRIGHT number): white while the
    -- bar has charges, Blizzard gold when the bar is drained (`charges 0`,
    -- the one state the engine keeps on the bar -- see Engine:Sorted).
    ChargeColor = { 1, 1, 1, 1 },
    ChargeZeroColor = { 1.00, 0.82, 0.00, 1 },
    Spark = TEX .. "Spark2",
    SparkOn = true,                           -- the Spark OPTION (on/off);
                                              -- Spark above is the texture
    SparkScale = 2.2,                         -- glow size / icon size (:1157)
    SparkAlpha = 1.0,                         -- Spark = {[0]=true, 1}
    Alpha = 0.2, AlphaMax = 1.0,              -- icon fade-in endpoints
    FadeSeconds = 0.3,                        -- ... over this many seconds
    CrossfadeSeconds = 1.0,                   -- group focus dwell per member
    SplashFactor = 4,                         -- cast splash = 4x the icon
    SplashAlpha = 0.7,
    SplashSeconds = 0.35,
    PulseSeconds = 1.2,                       -- end-of-cooldown pulse life
    PulseCycle = 0.4,                         -- spark alpha pulse cycle

    -- Category colours, verbatim :1842-1855 (BuffOther/DebuffOther default
    -- off in the original). Default class is Spell (orange); per-spell
    -- override via FX.Cooldown.Engine.tracked[name].fxClass = "<key>".
    Colors = {
        Spell       = { 1.00, 0.50, 0.00 },
        Powerup     = { 0.00, 0.75, 1.00 },
        Item        = { 1.00, 1.00, 0.00 },
        Potion      = { 0.00, 1.00, 0.00 },
        Healthstone = { 0.00, 1.00, 0.50 },
        Pet         = { 1.00, 0.00, 0.95 },
        Internal    = { 0.00, 0.60, 0.85 },
        ResTimer    = { 1.00, 0.00, 0.00 },
        Buff        = { 1.00, 1.00, 1.00 },
        Debuff      = { 1.00, 0.00, 0.00 },
        Enchant     = { 1.00, 1.00, 1.00 },
        Soulstone   = { 0.64, 0.21, 0.93 },
    },
}
local S = FX.Cooldown.TimelineSkin

-- Owner font decision 2026-11-01: URW Gothic Book (libre Century-Gothic
-- clone, converted to TrueType; the .otf twin next to it is the license
-- source and must NOT be loaded). GameFontHighlightSmall is the clean
-- fallback; GOTHIC.TTF is Monotype-proprietary and gone.
local FONT_FILE = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
local FONT_SIZE = 11
local ICON_FONT_SIZE = FONT_SIZE - 1   -- FW IconFont = Font size - 1 (:1806)
local ICON_FONT_FLAGS = "OUTLINE"

D.fontFile = nil   -- set by validateFont() in Init; nil = template fallback

local ANCHOR_W, ANCHOR_H = S.Width, 20
local DEFAULT = { point = "CENTER", relPoint = "CENTER", x = 0, y = -150, locked = true }

-- Frame scale/alpha inputs (OP-06 header fields + General FrameAlpha/
-- FrameScale), module-local so the setters are safe to call before Init
-- (the values are live skin state; Init and ApplyFrameFX read them back).
D.frameState = {
    scale = 1.0, alpha = 1.0,          -- the Cooldown page's Scale / Alpha
    globalScale = 1.0, globalAlpha = 1.0,   -- General FrameScale / FrameAlpha
    enabled = true, hideCombat = false,     -- Basics: Enable / HideCombat
}
local FS = D.frameState

--- The validated, lower-compare round-trip of validateFont for ANY file
--- path (the General BarFont option feeds arbitrary strings).
local function validateFontFile(path)
    if type(path) ~= "string" or path == "" then return nil end
    local okCreate, fontObj = pcall(CreateFont, path, FONT_SIZE)
    if not okCreate or not fontObj then return nil end
    local probe = UIParent:CreateFontString(nil, "OVERLAY")
    if not probe then return nil end
    local okSet = pcall(probe.SetFont, probe, path, FONT_SIZE)
    local got = okSet and probe:GetFont()
    probe:Hide()
    if type(got) == "string" and got:lower() == path:lower() then
        return path
    end
    return nil
end

local fallbackCfg
local function config()
    local cfg
    if FX.db then
        FX.db.cooldownDisplay = FX.db.cooldownDisplay or {}
        cfg = FX.db.cooldownDisplay
    else
        fallbackCfg = fallbackCfg or {}
        cfg = fallbackCfg
    end
    for k, v in pairs(DEFAULT) do
        if cfg[k] == nil then cfg[k] = v end
    end
    return cfg
end

--- Validate the shipped font ONCE (the shipped path through the generic
--- round-trip above). Rejected files leave fontFile nil and every
--- fontstring keeps its GameFontHighlightSmall template.
local function validateFont()
    return validateFontFile(FONT_FILE)
end

--- Apply the validated font, dirty-checked, falling back to the string's
--- GameFontHighlightSmall template (set at creation) when the file was not
--- accepted. The cache key carries the accepted FILE, so a BarFont change
--- re-applies every live string. SetFont returns the object (truthy) on
--- success in 12.x; treat any false/nil return or raise as a rejection and
--- restore the template.
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

--- FW:FixIntensity, verbatim (Forte_Core.lua :796-805): lift a colour for
--- text/glow use -- a full-saturation colour softens toward white, a dim one
--- is normalised then softened, black becomes white.
local function fixIntensity(r, g, b)
    local largest = math.max(math.max(r, g), b)
    if largest == 1 then
        return 0.7 * r + 0.3, 0.7 * g + 0.3, 0.7 * b + 0.3
    elseif largest > 0 and largest < 1 then
        return 0.7 * r / largest + 0.3, 0.7 * g / largest + 0.3, 0.7 * b / largest + 0.3
    end
    return 1, 1, 1
end

--- FW:SecToTimeD, TimeFormat branch (Forte_Core.lua :1746-1761; TimeFormat
--- defaults true, :2487): m:ss at >= 60, tenths below. (The original feeds
--- the raw float to "%02d", Lua 5.1 truncates; math.floor is explicit here.)
--- S.TimeFormatAlt (the General AltTimeFormat option) prints m:ss for
--- EVERY remaining time, tenths never.
local function formatRemaining(remaining)
    if remaining >= 60 or S.TimeFormatAlt then
        return string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
    end
    return string.format("%.1f", remaining)
end

--- The identity of the DISPLAYED string for `formatRemaining`: one whole
--- second for the m:ss branches, one rounded tenth for the %0.1f branch.
--- m5: the render pass compares this int, so a per-tick call with the same
--- visible value formats (and SetTexts) nothing.
local function timeKey(remaining)
    if remaining >= 60 or S.TimeFormatAlt then
        return math.floor(remaining)
    end
    return math.floor(remaining * 10 + 0.5)
end

--- The category KEY of a row (its colour identity, the TimelineSkin.Colors
--- key). Read once per (slot, name) bind and cached on the slot so a
--- SetCategoryColor can recolor exactly the slots that ride that category.
local function rowClass(row)
    local cls = row.category
    if not cls then
        local tracked = FX.Cooldown.Engine and FX.Cooldown.Engine.tracked
        local t = tracked and tracked[row.name]
        cls = (t and t.fxClass) or "Spell"
    end
    return cls
end

--- The row's category colour: S.Colors[rowClass(row)], unknown categories
--- falling back to Spell so a row without one renders exactly as before.
local function rowColor(row)
    return S.Colors[rowClass(row)] or S.Colors.Spell
end

-- ------------------------------------------------------------------- init --
--- One tag fontstring by index; grow-only pool.
function D:_TagSlot(i, text, xoff)
    local fs = self.tagFS[i]
    if not fs then
        fs = self.anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("CENTER")
        self.tagFS[i] = fs
    end
    applyFont(fs, FONT_SIZE)
    fs:SetText(text)
    local c = S.TextColor
    fs:SetTextColor(c[1], c[2], c[3], c[4])
    fs:ClearAllPoints()
    fs:SetPoint("CENTER", self.anchor, "CENTER", xoff, 0)
    fs:Show()
    return fs
end

--- The custom tags on the power curve + the original's trailing Max tag
--- (SetTimeTags :1279-1293 draws s.Max itself at the right end after the
--- >= Max tags break out of the loop).
function D:BuildTags()
    local n = 0
    for _, tag in ipairs(TM.tags(S.CustomTags, S.Width, S.Height, S.Max, S.Loga)) do
        n = n + 1
        self:_TagSlot(n, tag.label, S.Inset + tag.x - S.Width * 0.5)
    end
    n = n + 1
    self:_TagSlot(n, TM.tagLabel(S.Max),
        S.Inset + TM.pos(S.Max, S.Width, S.Height, S.Max, S.Loga) - S.Width * 0.5)
    for i = n + 1, #self.tagFS do
        if self.tagFS[i]:IsShown() then self.tagFS[i]:Hide() end
    end
end

function D:Init()
    if self.anchor then return end
    self.cfg = config()
    self.fontFile = validateFont()

    local f = CreateFrame("Frame", "ForteXorcistCooldownAnchor", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(S.Width, S.Height)
    if f.SetBackdrop then
        -- FW Backdrop = { Background, Border, tile=false, 16, 5, 3 } (:1857).
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

    -- The Aluminium fill, white a 0.20, over the inset bar area (:1856).
    local fill = f:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(S.BarTexture)
    fill:SetPoint("TOPLEFT", f, "TOPLEFT", S.Inset, -S.Inset)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -S.Inset, S.Inset)
    local bc = S.BarColor
    fill:SetVertexColor(bc[1], bc[2], bc[3], bc[4])

    -- The icon layer: inset by Backdrop[6] like the original's bars
    -- (NewBar.Update :1176: TOPLEFT +3 / BOTTOMRIGHT -3), so slot x offsets
    -- are TimelineMath.pos values in the same coordinate system as the tags
    -- (which carry the +3 inset explicitly).
    local bar = CreateFrame("Frame", nil, f)
    bar:SetPoint("TOPLEFT", f, "TOPLEFT", S.Inset, -S.Inset)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -S.Inset, S.Inset)

    -- Drag plumbing registered exactly once, here (see the old Display's
    -- note): locking only flips SetMovable/EnableMouse.
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        self:SavePosition(fr)
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetText("Forte Cooldowns")
    title:SetTextColor(1, 1, 1, 1)
    title:SetPoint("BOTTOM", f, "TOP", 0, 2)

    self.anchor, self.title, self.bar, self.fill = f, title, bar, fill
    self.slots = {}        -- grow-only icon-slot pool
    self._byName = {}      -- name -> slot bound to it (names on the bar)
    self._free = {}        -- stack of released slots (release pops, O(1))
    self._islot = {}       -- scratch: per-pass index -> bound slot
    self._seen = {}        -- scratch: names present in the current pass
    self.tagFS = {}
    self.splashPool = {}
    self.pulsePool = {}
    self._xf = {}        -- cross-fade focus state, keyed by group signature
    self._gitems = {}    -- scratch for grouping (entries are engine-owned)
    self._groupsScratch = {}   -- TM.group's caller-owned scratch (m5)
    self._ready = {}

    -- Login apply FIRST (Init runs at PLAYER_LOGIN): saved settings resize
    -- the skin, then BuildTags/Build draw in the saved geometry. Live
    -- changes arrive through the OnChange listeners from here on.
    self:_WireSettings()
    self:ApplyStoredSettings()
    self:BuildTags()
    self:ApplyPosition()
    self:SetLocked(self.cfg.locked and true or false)
    -- The scale/alpha/enabled/hide-combat state may have been set before
    -- the frames existed (options apply runs at PLAYER_LOGIN, and the
    -- setters are safe pre-Init); make the live frames agree with it.
    self:ApplyFrameFX()
    self:UpdateVisibility()
end

-- -------------------------------------------------------------- position --
function D:ApplyPosition()
    local cfg = self.cfg
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
end

--- Snapshot the anchor's current anchoring after a native drag.
function D:SavePosition(f)
    f = f or self.anchor
    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint, x, y
end

--- Locked = mouse-off (no drag possible) and the title hidden.
function D:SetLocked(locked)
    locked = not not locked
    self.cfg.locked = locked
    -- m4: the lock has ONE truth (the bar) -- publish it to the options
    -- store so the checkboxes and the header icon read live state. Guarded
    -- by store-inequality: a settings listener that calls back into
    -- SetLocked finds the store already agrees and the loop dies there.
    local st = FX.Settings
    if st and st.IsRegistered then
        if st:IsRegistered("Cooldown")
            and st:Get("Cooldown", "Lock") ~= locked then
            st:Set("Cooldown", "Lock", locked)
        end
        if st:IsRegistered("General")
            and st:Get("General", "GlobalLock") ~= locked then
            st:Set("General", "GlobalLock", locked)
        end
    end
    if not self.anchor then return end
    self.anchor:SetMovable(not locked)
    self.anchor:EnableMouse(not locked)
    if not locked then
        self.title:Show()
    else
        self.title:Hide()
    end
end

--- Default position, keeping the current lock state.
function D:Reset()
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y = DEFAULT.point, DEFAULT.relPoint, DEFAULT.x, DEFAULT.y
    self:ApplyPosition()
end

--- `/fx lock|unlock|reset`. Returns true when handled (Init.lua wires this).
function D:Slash(cmd)
    cmd = (cmd or ""):lower()
    if cmd == "lock" then
        self:SetLocked(true)
        FX.Print("cooldown display locked")
        return true
    elseif cmd == "unlock" then
        self:SetLocked(false)
        FX.Print("cooldown display unlocked -- drag the |cff" .. FX.CONST.HEX.ACCENT
            .. "Forte Cooldowns|r bar, then /fx lock")
        return true
    elseif cmd == "reset" then
        self:Reset()
        FX.Print("cooldown display position reset")
        return true
    end
    return false
end

-- ----------------------------------------------------------- live settings --
-- T9: the public seam the options window drives. Every setter is safe to
-- call at ANY time: pre-Init it records intent (skin `S` + `D.frameState`),
-- post-Init it also rebuilds exactly the pieces that key owns (tags,
-- segment caches, slot geometry, fonts, colours). In combat the bar is a
-- plain non-secure frame, so geometry/texture/colour edits are legal there.
-- `ApplySettings(tbl)` maps the options keys (the names as Forte_Options
-- registers them) onto these setters; `ApplyStoredSettings()` pulls every
-- saved value from FX.Settings (login apply), and `_WireSettings()` (run
-- from Init, i.e. PLAYER_LOGIN) subscribes to FX.Settings:OnChange so a
-- change applies live. Keys with no consumer YET (FrameSnap, ShowTooltips)
-- are deliberately NOT in the map; the pages mark them "not used yet".

local CATEGORY_OF = {
    ColorSpell = "Spell", ColorPowerup = "Powerup", ColorItem = "Item",
    ColorPotion = "Potion", ColorPet = "Pet", ColorInternal = "Internal",
    ColorBuff = "Buff", ColorDebuff = "Debuff",
}

function D:SetSize(w, h)
    if type(w) == "number" and w > 0 then S.Width = w end
    if type(h) == "number" and h > 0 then S.Height = h end
    if not self.anchor then return end
    self.anchor:SetSize(S.Width, S.Height)
    for i = 1, #self.slots do
        local slot = self.slots[i]
        slot.frame:SetSize(S.Height, S.Height)
        slot.tex:SetSize(S.Height, S.Height)
        slot.spark:SetSize(S.Height * S.SparkScale, S.Height * S.SparkScale)
    end
    for i = 1, #self.splashPool do
        local sp = self.splashPool[i]
        sp.tex:SetSize(S.Height * S.SplashFactor, S.Height * S.SplashFactor)
    end
    for i = 1, #self.pulsePool do
        local p = self.pulsePool[i]
        p.tex:SetSize(S.Height, S.Height)
        p.spark:SetSize(S.Height * S.SparkScale, S.Height * S.SparkScale)
    end
    self:InvalidateLayout()
    self:BuildTags()
end

--- Max time / power scale move every icon and tag on the curve.
function D:SetMaxTime(v)
    if type(v) ~= "number" or v <= 0 then return end
    S.Max = v
    if not self.anchor then return end
    self:InvalidateLayout()
    self:BuildTags()
end

function D:SetPowerScale(v)
    if type(v) ~= "number" or v <= 0 then return end
    S.Loga = v
    if not self.anchor then return end
    self:InvalidateLayout()
    self:BuildTags()
end

function D:SetTimeTags(text)
    S.CustomTags = tostring(text or "")
    if self.anchor then self:BuildTags() end
end

--- Drop the caches that key on the timeline geometry so the next Update
--- re-anchors icons, segments and TexCoords from the new skin numbers.
function D:InvalidateLayout()
    for i = 1, #(self.slots or {}) do
        local slot = self.slots[i]
        slot._cx = nil
        slot._segSetL, slot._segSetR = nil, nil
        slot._segSetVL, slot._segSetV = nil, nil
    end
end

--- One category colour (ColorSpell .. ColorDebuff). Assigning a FRESH
--- table to S.Colors[key] busts every cached identity (_segCol/_segSetCol
--- compare by table), so segments repaint themselves on the next pass; the
--- spark and the time text need the explicit re-tint of the bound slots.
function D:SetCategoryColor(key, col)
    if type(col) ~= "table" then return end
    S.Colors[key] = { col[1] or 1, col[2] or 1, col[3] or 1 }
    local c = S.Colors[key]
    local fr, fg, fb = fixIntensity(c[1], c[2], c[3])
    for i = 1, #(self.slots or {}) do
        local slot = self.slots[i]
        if slot._name and slot._colorClass == key then
            slot._col = c
            slot._segCol = c
            slot.spark:SetVertexColor(fr, fg, fb)
            slot.timeFS:SetTextColor(fr, fg, fb)
        end
    end
end

function D:SetBarColor(col)
    if type(col) ~= "table" then return end
    S.BarColor = { col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 0.2 }
    local c = S.BarColor
    if self.fill then self.fill:SetVertexColor(c[1], c[2], c[3], c[4]) end
end

function D:SetBgColor(col)
    if type(col) ~= "table" then return end
    S.BgColor = { col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 0.5 }
    local c = S.BgColor
    local f = self.anchor
    if f and f.SetBackdropColor then
        f:SetBackdropColor(c[1], c[2], c[3], c[4])
        f:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
    end
end

function D:SetSparkOn(on)
    S.SparkOn = not not on
    for i = 1, #(self.slots or {}) do
        if S.SparkOn then self.slots[i].spark:Show()
        else self.slots[i].spark:Hide() end
    end
    for i = 1, #(self.pulsePool or {}) do
        if S.SparkOn then self.pulsePool[i].spark:Show()
        else self.pulsePool[i].spark:Hide() end
    end
end

--- Bar fill texture (General BarTexture): the fill and every segment.
function D:SetBarTexture(path)
    if type(path) ~= "string" or path == "" then return end
    S.BarTexture = path
    if self.fill then self.fill:SetTexture(path) end
    for i = 1, #(self.slots or {}) do
        self.slots[i].seg:SetTexture(path)
    end
end

--- Bar font (General BarFont): re-validate the file and re-apply it to
--- every live fontstring (applyFont's key carries the file).
function D:SetBarFont(path)
    self.fontFile = validateFontFile(path)
    D.fontFile = self.fontFile
    for i = 1, #(self.tagFS or {}) do
        applyFont(self.tagFS[i], FONT_SIZE)
    end
    for i = 1, #(self.slots or {}) do
        local slot = self.slots[i]
        applyFont(slot.timeFS, ICON_FONT_SIZE, ICON_FONT_FLAGS)
        applyFont(slot.chargeFS, ICON_FONT_SIZE, ICON_FONT_FLAGS)
    end
end

function D:SetScale(v)
    FS.scale = (type(v) == "number" and v > 0) and v or 1.0
    self:ApplyFrameFX()
end

function D:SetAlpha(v)
    FS.alpha = (type(v) == "number" and v > 0) and v or 1.0
    self:ApplyFrameFX()
end

function D:SetGlobalScale(v)
    FS.globalScale = (type(v) == "number" and v > 0) and v or 1.0
    self:ApplyFrameFX()
end

function D:SetGlobalAlpha(v)
    FS.globalAlpha = (type(v) == "number" and v > 0) and v or 1.0
    self:ApplyFrameFX()
end

--- Frame scale/alpha = the module's own value x the Global one (OP-06).
function D:ApplyFrameFX()
    if not self.anchor then return end
    self.anchor:SetScale(FS.scale * FS.globalScale)
    self.anchor:SetAlpha(FS.alpha * FS.globalAlpha)
end

function D:SetEnabled(on)
    FS.enabled = not not on
    self:UpdateVisibility()
end

function D:SetHideCombat(on)
    FS.hideCombat = not not on
    self:UpdateVisibility()
end

function D:SetTimeFormatAlt(on)
    S.TimeFormatAlt = not not on
    -- The displayed string identity changes -> force one repaint pass.
    for i = 1, #(self.slots or {}) do
        self.slots[i]._timeKey = nil
    end
end

--- Enable gates everything; HideCombat ("Hide when not in combat") hides
--- the bar OUT of combat. Dirty-checked; Update refreshes it every pass,
--- which is how the combat transitions self-heal without event wiring.
function D:UpdateVisibility()
    if not self.anchor then return end
    local show = FS.enabled
    if show and FS.hideCombat then
        show = (type(InCombatLockdown) == "function")
            and InCombatLockdown() and true or false
    end
    if self._shown == show then return end
    self._shown = show
    if show then self.anchor:Show() else self.anchor:Hide() end
end

--- IgnoreShort = the Engine's public floor. Engine.lua is not touched
--- here; MIN_COOLDOWN is its public field, and the tracked set is rebuilt
--- so a lowered floor takes effect immediately.
function D:IgnoreShortChanged(value)
    local E = FX.Cooldown.Engine
    if not E then return end
    E.MIN_COOLDOWN = (type(value) == "number") and value or 2.99
    local m = FX.Cooldown.Module
    if m and m.Rebuild then pcall(m.Rebuild, m) end
end

--- options key -> Display method. Keys absent from this map (FrameSnap,
--- ShowTooltips) have no consumer yet and stay stored-only.
local KEYMAP = {
    Enable = "SetEnabled",
    HideCombat = "SetHideCombat",
    Lock = "SetLocked",
    Width = "SetWidth",
    Height = "SetHeight",
    MaxTime = "SetMaxTime",
    PowerScale = "SetPowerScale",
    TimeTags = "SetTimeTags",
    IgnoreShort = "SetIgnoreShort",
    BarColor = "SetBarColor",
    BgColor = "SetBgColor",
    Spark = "SetSparkOn",
    Scale = "SetScale",
    Alpha = "SetAlpha",
    GlobalLock = "SetLocked",
    FrameAlpha = "SetGlobalAlpha",
    FrameScale = "SetGlobalScale",
    AltTimeFormat = "SetTimeFormatAlt",
    BarFont = "SetBarFont",
    BarTexture = "SetBarTexture",
}

function D:SetWidth(v) self:SetSize(v, nil) end
function D:SetHeight(v) self:SetSize(nil, v) end

--- Public bulk seam: { [options key] = value }. Unknown keys (the
--- not-used-yet ones) are ignored by design.
function D:ApplySettings(tbl)
    for key, value in pairs(tbl or {}) do
        local m = KEYMAP[key]
        if m then
            self[m](self, value)
        elseif CATEGORY_OF[key] then
            self:SetCategoryColor(CATEGORY_OF[key], value)
        end
    end
end

function D:SetIgnoreShort(v) self:IgnoreShortChanged(v) end

--- The stored shape of every wired key (the pages' defaults are the
--- canonical source; Get returns them unmodified when the store is empty).
local STORED = {
    Cooldown = { "Enable", "HideCombat", "Width", "Height", "MaxTime",
        "PowerScale", "TimeTags", "IgnoreShort", "BarColor", "BgColor",
        "Spark", "Scale", "Alpha",
        "ColorSpell", "ColorPowerup", "ColorItem", "ColorPotion",
        "ColorPet", "ColorInternal", "ColorBuff", "ColorDebuff" },
    General = { "FrameAlpha", "FrameScale", "AltTimeFormat",
        "BarFont", "BarTexture" },
}

--- Apply every saved value (login: Init runs at PLAYER_LOGIN). Lock and
--- GlobalLock are NOT pulled -- the live lock state is the truth and
--- SetLocked publishes it upward (m4).
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

--- Live wiring: one listener per settings module, registered once from
--- Init. The Lock/GlobalLock listeners keep the m4 mirror warm for pages
--- opened later; every other key routes through KEYMAP.
function D:_WireSettings()
    local st = FX.Settings
    if not st or not st.OnChange or self._wired then return end
    self._wired = true
    st:OnChange("Cooldown", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
    st:OnChange("General", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
end

-- ----------------------------------------------------------------- pools --
--- An icon slot from the grow-only pool: released slots (their name left
--- the bar) come off the free list first, else the pool grows by one. A
--- bar-height frame carrying the spell icon, its Spark2 running glow (ADD
--- blend, category-tinted), the on-icon time text (IconTime, :1837) and the
--- charge-count number. Created on first demand, never destroyed; the
--- caller binds the name (BindSlot), Update releases what the feed dropped.
function D:AcquireSlot()
    local free = self._free
    local top = #free
    if top > 0 then
        local slot = free[top]
        free[top] = nil
        return slot
    end
    local i = #self.slots + 1

    -- The segment fill (Aluminium, drawn on the bar layer, NOT inside the
    -- slot frame: it spans between icons, original bar.texture, :1441-1450).
    local seg = self.bar:CreateTexture(nil, "ARTWORK")
    seg:SetTexture(S.BarTexture)

    local frame = CreateFrame("Frame", nil, self.bar)
    frame:SetSize(S.Height, S.Height)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("CENTER", frame, "CENTER", 0, 0)
    tex:SetSize(S.Height, S.Height)

    -- Permanent running spark: NewBar.Update :1156-1160 shows it at
    -- 2.2 x icon size, alpha Spark[1] = 1, whenever Spark[0] -- and Spark
    -- defaults {[0]=true, 1} (:1820), "flags on by default" (PLAN §3.5).
    -- Tint = FixIntensity(category) (:1407 + :1417).
    local spark = frame:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(S.Spark)
    spark:SetBlendMode("ADD")
    spark:SetPoint("CENTER", frame, "CENTER", 0, 0)
    spark:SetSize(S.Height * S.SparkScale, S.Height * S.SparkScale)
    spark:SetAlpha(S.SparkAlpha)
    -- The Spark OPTION (S.SparkOn): the running glow is a flag, off hides
    -- it on the whole pool (SetSparkOn) and on freshly built slots.
    if not S.SparkOn then spark:Hide() end

    -- IconTime text: IconFont = font, size-1, OUTLINE (:1806), anchored
    -- BOTTOMLEFT of the icon (NewBar :1120-1122).
    local timeFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    applyFont(timeFS, ICON_FONT_SIZE, ICON_FONT_FLAGS)
    timeFS:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

    -- Charge count: the current castable number. v1 sat at the Blizzard
    -- CooldownViewer.xml count corner (BOTTOMRIGHT -2, 2), but the 3-4
    -- character IconTime string at the icon's BOTTOMLEFT overprints it at
    -- 24 px icon width ("40." over "0"). v4 rides the icon's TOPRIGHT
    -- instead, same font/colours, clear of the time text. Hidden until a
    -- row with a `charges` count binds here (Update owns the visibility).
    local chargeFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    applyFont(chargeFS, ICON_FONT_SIZE, "OUTLINE")
    chargeFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    chargeFS:Hide()

    slot = { frame = frame, tex = tex, spark = spark, timeFS = timeFS,
             chargeFS = chargeFS, seg = seg }
    self.slots[i] = slot
    return slot
end

--- Give a slot back: its name left the feed. Hide everything the slot
--- draws (frame, segment, charge text), drop the identity so a later cast
--- of the same name is a fresh first sighting (splash + fade-in), push the
--- slot on the free list. The frame/texture survive for the next bind.
function D:ReleaseSlot(slot)
    local name = slot._name
    if name then
        self._byName[name] = nil
        slot._name = nil
    end
    if slot._shown then
        slot._shown = false
        slot.frame:Hide()
        slot.seg:Hide()
    end
    if slot._chargeShown then
        slot._chargeShown = false
        slot.chargeFS:Hide()
    end
    local free = self._free
    free[#free + 1] = slot
end

--- Bind a slot to a row for its first sighting: textures, colours, splash,
--- fade start. Only called for a name that is NOT on the bar (Update takes
--- the byName branch), so the slot arrives fresh off the free list / a new
--- pool entry and this whole body runs once per cast, never per tick; the
--- per-tick path in Update stays allocation-free. `cx` = icon centre x
--- relative to the bar.
function D:BindSlot(slot, e, cx, now)
    slot._name = e.name
    -- A row-carried icon (an item / potion texture: a fileID or a path)
    -- overrides the spell-icon lookup; nil rows keep the lookup.
    slot._texPath = e.icon
        or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.name))
    if slot._texPath then
        -- The icon texture stays UNTINTED (bar.icon:SetNormalTexture(t5),
        -- :1400); the category colour rides the segment, spark and text.
        slot.tex:SetTexture(slot._texPath)
    end
    local col = rowColor(e)
    slot._colorClass = rowClass(e)         -- the SetCategoryColor target
    slot._col = col
    slot._segCol = col                      -- segment: raw category (:1403)
    local fr, fg, fb = fixIntensity(col[1], col[2], col[3])
    slot.spark:SetVertexColor(fr, fg, fb)   -- FixIntensity (:1407, :1417)
    slot.timeFS:SetTextColor(fr, fg, fb)    -- IconTextColor off -> FixIntensity
    -- The charge number is per-tick state (Update): drop the previous
    -- name's cached text/colour so the first pass always repaints it.
    slot._chargeText, slot._chargeCol = nil, nil
    slot._timeKey = nil                     -- fresh icon: paint the time
    slot._fadeStart = now
    slot._alpha = nil
    self:SpawnSplash(cx, slot._texPath, col, now)
end

--- Cast splash: the spell icon at 4x the bar height, alpha 0.7 -> 0 over
--- 0.35 s, centred where the icon sits. Grow-only pool.
function D:SpawnSplash(cx, texPath, col, now)
    local pool = self.splashPool
    local s
    for i = 1, #pool do
        if not pool[i]._endAt then
            s = pool[i]
            break
        end
    end
    if not s then
        local splashSize = S.Height * S.SplashFactor
        -- Named for dump-tree checks: a visible frame named
        -- ForteXorcistCooldownSplash<n> is a splash on screen.
        local f = CreateFrame("Frame", "ForteXorcistCooldownSplash" .. (#pool + 1), UIParent)
        local iconTex = f:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(splashSize, splashSize)
        iconTex:SetPoint("CENTER", f, "CENTER", 0, 0)
        s = { frame = f, tex = iconTex }
        pool[#pool + 1] = s
    end
    s.tex:SetTexture(texPath)
    s.frame:ClearAllPoints()
    -- cx is icon-centre x relative to the bar/anchor centre (both are at the
    -- same screen point: the bar layer is inset symmetrically).
    s.frame:SetPoint("CENTER", self.anchor, "CENTER", cx, 0)
    s.frame:SetAlpha(S.SplashAlpha)
    s._endAt = now + S.SplashSeconds
    s.frame:Show()
end

--- End-of-cooldown pulse: the icon parked at the LEFT end (CD_EndCooldown
--- :346-351 parks it at f2*W) with its Spark2 glow flared to 2.2x and its
--- alpha pulsing, fading out over PulseSeconds. Grow-only pool.
function D:SpawnPulse(name, texPath, col, endAt)
    local pool = self.pulsePool
    local s = pool[#pool + 1]
    if not s then
        local f = CreateFrame("Frame", nil, UIParent)
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetSize(S.Height, S.Height)
        tex:SetPoint("CENTER", f, "CENTER", 0, 0)
        local spark = f:CreateTexture(nil, "OVERLAY")
        spark:SetTexture(S.Spark)
        spark:SetBlendMode("ADD")
        spark:SetSize(S.Height * S.SparkScale, S.Height * S.SparkScale)
        spark:SetPoint("CENTER", f, "CENTER", 0, 0)
        s = { frame = f, tex = tex, spark = spark }
        pool[#pool + 1] = s
    end
    s.tex:SetTexture(texPath)
    s.spark:SetVertexColor(col[1], col[2], col[3])
    s.frame:ClearAllPoints()
    s.frame:SetPoint("CENTER", self.anchor, "CENTER",
        S.Inset + TM.pos(0, S.Width, S.Height, S.Max, S.Loga) + S.Height * 0.5 - S.Width * 0.5, 0)
    s._name = name
    s._endAt = endAt
    s.frame:Show()
end

function D:UpdatePulses(now)
    local pool = self.pulsePool
    for i = 1, #pool do
        local s = pool[i]
        local endAt = s._endAt
        if endAt then
            local t = (endAt - now) / S.PulseSeconds
            if t <= 0 then
                s._endAt = nil
                s.frame:Hide()
            else
                s.frame:SetAlpha(t)
                local wave = (math.sin((endAt - now) / S.PulseCycle * 2 * math.pi) + 1) * 0.5
                s.spark:SetAlpha(0.3 + 0.7 * wave)
            end
        end
    end
end

function D:UpdateSplashes(now)
    local pool = self.splashPool
    for i = 1, #pool do
        local s = pool[i]
        local endAt = s._endAt
        if endAt then
            local t = (endAt - now) / S.SplashSeconds
            if t <= 0 then
                s._endAt = nil
                s.frame:Hide()
            else
                s.frame:SetAlpha(S.SplashAlpha * t)
            end
        end
    end
end

-- ---------------------------------------------------------------- render --
--- Module touchpoint: the Engine's Sweep just named `name` as ready. The
--- end-of-cooldown pulse spawns from the next Update, off the slot that
--- still shows the name (texture + colour copied), at the left end.
function D:OnReady(name, now)
    if not name then return end
    now = now or GetTime()
    local q = self._ready
    q[name] = now + S.PulseSeconds
end

--- Rebuild the grouping scratch from the engine array (never mutated) and
--- the positions Update just tagged on it.
function D:_GroupItems(entries, n)
    local items = self._gitems
    for i = 1, n do
        local it = items[i]
        if not it then
            it = {}
            items[i] = it
        end
        it.name = entries[i].name
        it.x = entries[i].x
        it.v = entries[i].v
        it.slot = self._islot[i]   -- the slot bound to this entry THIS pass
        it.alpha = 1
    end
    for i = n + 1, #items do
        wipe(items[i])
    end
    return items
end

local function groupSignature(g)
    local parts = {}
    for i = 1, #g do parts[i] = g[i].name end
    return table.concat(parts, "|")
end

--- Focus rotation over an overlap group (render loop :608-637): the focused
--- member's visibility ramps 0 -> 1 over ~1 s; at the boundary the focus
--- passes to the next member and the ramp restarts. `phase/CrossfadeSeconds`
--- is exactly the original's cd[i][14] visibility.
function D:_RotateFocus(sig, count, now)
    local st = self._xf[sig]
    if not st then
        st = { idx = 1, phase = S.CrossfadeSeconds, t = now }
        self._xf[sig] = st
    end
    st.n = count
    local dt = now - st.t
    if dt < 0 then dt = 0 end
    st.t = now
    st.phase = st.phase + dt
    if st.phase >= S.CrossfadeSeconds then
        st.phase = st.phase - S.CrossfadeSeconds
        st.idx = (st.idx % st.n) + 1
    end
    return st
end

--- Segment fill for one slot: the Aluminium slice from the group's left
--- border to the icon's own centre (original bar.texture, :1441-1450:
--- TOPLEFT +t12 / BOTTOMRIGHT t9-Width, TexCoord (t8,0, t8,1, t7,0, t7,1),
--- VertexColor = raw category rgb, alpha AlphaMax-(AlphaMax-Alpha)*t7
--- :1404-1406; frame alpha rides the bar visibility, :1402). The applied
--- values are cached in _segSet*; the CURRENT values are mirrored to
--- _segL/_segR/_segVL/_segV/_segA for the tests.
function D:_SetSegment(slot, leftX, rightX, uvL, uvR, a)
    local seg = slot.seg
    if not seg:IsShown() then seg:Show() end
    if slot._segSetL ~= leftX or slot._segSetR ~= rightX then
        slot._segSetL, slot._segSetR = leftX, rightX
        seg:ClearAllPoints()
        -- Bar coords: left x from the bar's LEFT edge; right x from its
        -- RIGHT edge, and the bar layer is INSET wide (Width - 2*Inset),
        -- the original's bar frame is s.Width wide (:1490).
        seg:SetPoint("TOPLEFT", self.bar, "TOPLEFT", leftX, 0)
        seg:SetPoint("BOTTOMRIGHT", self.bar, "BOTTOMRIGHT",
            rightX - (S.Width - 2 * S.Inset), 0)
    end
    if slot._segSetVL ~= uvL or slot._segSetV ~= uvR then
        slot._segSetVL, slot._segSetV = uvL, uvR
        seg:SetTexCoord(uvL, 0, uvL, 1, uvR, 0, uvR, 1)
    end
    local col = slot._segCol
    if col and (slot._segSetCol ~= col or slot._segSetA ~= a) then
        slot._segSetCol, slot._segSetA = col, a
        seg:SetVertexColor(col[1], col[2], col[3], a)
    end
end

--- Render one pass. `entries` is the Engine's reused scratch array, sorted
--- soonest-ready first -- the only thing we tag onto it is the transient
--- numeric `.x` the grouping consumes; keep no references to it.
function D:Update(entries, now)
    if not self.anchor then return end
    -- Enable / Hide-when-out-of-combat ride this 10 Hz pass (cheap and
    -- dirty-checked): the bar self-heals on combat transitions. A hidden
    -- bar spends no draw work; the transient splash/pulse timers keep
    -- running so nothing resurfaces when it returns.
    self:UpdateVisibility()
    if not self._shown then
        self:UpdatePulses(now)
        self:UpdateSplashes(now)
        return
    end
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local n = #entries
    local byName, islot, seen = self._byName, self._islot, self._seen
    wipe(seen)

    for i = 1, n do
        local e = entries[i]
        -- A multi-charge bar rides its NEXT charge landing: the engine keeps
        -- `rechargeEnd` in `endTime` for the rows it ships, and the explicit
        -- field wins when the two ever diverge. Plain cooldowns carry no
        -- rechargeEnd, so they read exactly as before.
        local finishAt = e.rechargeEnd or e.endTime
        local remaining = finishAt - now
        local x = TM.pos(remaining, W, H, Max, Loga)
        e.x = x                                   -- transient tag (see above)
        e.v = (x + H * 0.5) / W                   -- the position factor t7
        local cx = x + H * 0.5 - (W - 2 * S.Inset) * 0.5  -- centre for the splash
        local slot = byName[e.name]
        if not slot then
            -- A name not on the bar in the previous pass: first sighting.
            -- Fresh slot from the pool + BindSlot (textures, colours,
            -- fade-in, splash). A name already on the bar keeps its slot
            -- untouched -- entries shifting down as a cooldown finishes is
            -- a POSITIONAL event, never a re-sighting.
            slot = self:AcquireSlot()
            byName[e.name] = slot
            self:BindSlot(slot, e, cx, now)
        end
        islot[i] = slot
        seen[e.name] = true
        -- LEFT-anchored at pos(t), the original's bar.icon CENTER->LEFT at
        -- t10 (:1450): icon centre = bar-left + pos(t) + ih/2 = t9, the very
        -- right edge of the segment span.
        if slot._cx ~= x then
            slot._cx = x
            slot.frame:ClearAllPoints()
            slot.frame:SetPoint("LEFT", self.bar, "LEFT", x, 0)
        end
        if not slot._shown then
            slot._shown = true
            slot.frame:Show()
        end
        -- m5: the icon time text repaints only when the DISPLAYED value
        -- moves (whole second on the m:ss branches, tenth below a minute):
        -- the key int decides, so an unchanged tenth costs no string.format
        -- and no SetText (the sibling charge text is cached the same way).
        local remainingShown = remaining > 0 and remaining or 0
        local tKey = timeKey(remainingShown)
        if slot._timeKey ~= tKey then
            slot._timeKey = tKey
            slot.timeFS:SetText(formatRemaining(remainingShown))
        end

        -- Charge count: the row's current castable number at the icon's
        -- BOTTOMRIGHT. Engine:Sorted only ships a charge row while the bar
        -- is drained (`charges` = 0) -- while charges > 0 the spell is
        -- castable and stays off the bar -- so on the live feed this is the
        -- number riding the recharge; a charges-less row (every plain
        -- cooldown, every test entry) keeps it hidden.
        local count = e.charges
        if count ~= nil and e.maxCharges ~= nil then
            local text = tostring(count)
            if slot._chargeText ~= text then
                slot._chargeText = text
                slot.chargeFS:SetText(text)
            end
            local cc = (count > 0) and S.ChargeColor or S.ChargeZeroColor
            if slot._chargeCol ~= cc then
                slot._chargeCol = cc
                slot.chargeFS:SetTextColor(cc[1], cc[2], cc[3], cc[4])
            end
            if not slot._chargeShown then
                slot._chargeShown = true
                slot.chargeFS:Show()
            end
        elseif slot._chargeShown then
            slot._chargeShown = false
            slot.chargeFS:Hide()
        end

        -- Attach a queued ready pulse (OnReady is fed by the Module).
        local endAt = self._ready[e.name]
        if endAt then
            self._ready[e.name] = nil
            self:SpawnPulse(e.name, slot._texPath, slot._col, endAt)
        end
    end

    -- Names the feed dropped release their slots (hide + free-list; a nil
    -- assignment during pairs is legal). Identity goes with them, so the
    -- next cast of the name splashes and fades in again.
    for name in pairs(byName) do
        if not seen[name] then
            self:ReleaseSlot(byName[name])
        end
    end

    -- Overlap groups + cross-fade focus (TimelineMath.group, original
    -- :554-637). Singletons keep alpha 1. m5: the groups list and its
    -- sub-lists are the Display's own scratch, reused every pass.
    local items = self:_GroupItems(entries, n)
    local groups = TM.group(items, H, self._groupsScratch)
    local xfSeen = self._seenScratch or {}
    self._seenScratch = xfSeen
    wipe(xfSeen)
    for gi = 1, #groups do
        local g = groups[gi]
        if #g > 1 then
            local sig = groupSignature(g)
            xfSeen[sig] = true
            local st = self:_RotateFocus(sig, #g, now)
            local frac = st.phase / S.CrossfadeSeconds
            local prev = ((st.idx - 2) % st.n) + 1
            for mi = 1, #g do
                if mi == st.idx then
                    g[mi].alpha = frac
                elseif mi == prev then
                    g[mi].alpha = 1 - frac
                else
                    g[mi].alpha = 0
                end
            end
        end
    end

    -- Segment fills (:1441-1450): every visible cooldown owns one Aluminium
    -- slice from its group's left border (previous visible icon's centre,
    -- shared across an overlap group by the t8/t12 propagation, :560-570) to
    -- the icon's own centre; bright left, faint right.
    for gi = 1, #groups do
        local g = groups[gi]
        local leftX, leftV
        if gi == 1 then
            leftX, leftV = 0, 0
        else
            local anchor = groups[gi - 1][1]
            leftX, leftV = anchor.x + H * 0.5, anchor.v
        end
        for mi = 1, #g do
            local it = g[mi]
            local slot = it.slot
            local rightX = it.x + H * 0.5
            local a = S.AlphaMax - (S.AlphaMax - S.Alpha) * it.v
            slot._segL, slot._segR = leftX, rightX
            slot._segVL, slot._segV, slot._segA = leftV, it.v, a
            self:_SetSegment(slot, leftX, rightX, leftV, it.v, a)
        end
    end

    -- Icon alpha = fade-in ramp * group visibility (dirty-checked).
    for i = 1, n do
        local slot = islot[i]
        local it = items[i]
        local p = (now - slot._fadeStart) / S.FadeSeconds
        local a = (p >= 1) and S.AlphaMax or (S.Alpha + (S.AlphaMax - S.Alpha) * p)
        a = a * it.alpha
        if slot._alpha ~= a then
            slot._alpha = a
            slot.frame:SetAlpha(a)
            slot.seg:SetAlpha(a)           -- bar:SetAlpha(t14), :1402
        end
    end

    -- Slots are name-bound: the release pass above already hid and freed
    -- every slot whose name left the feed -- there is no index tail to
    -- sweep any more.

    -- Prune cross-fade states whose group died (not seen, stale).
    for sig, st in pairs(self._xf) do
        if not xfSeen[sig] and now - st.t > 10 then
            self._xf[sig] = nil
        end
    end
    -- Prune pulses that never found a live slot (spell cleared in the same
    -- window): keeps _ready bounded, no per-tick table churn.
    for name, endAt in pairs(self._ready) do
        if endAt + 2 < now then self._ready[name] = nil end
    end

    self:UpdatePulses(now)
    self:UpdateSplashes(now)
end
