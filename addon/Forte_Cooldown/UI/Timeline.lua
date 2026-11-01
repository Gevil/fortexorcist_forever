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
-- endTime, predicted }) at 10 Hz plus ready names through OnReady(); we keep
-- no references to it (only the transient e.x position tag for grouping).
--
-- PLAN.md §3.4 rules: frames are created inside Init/Acquire* only; the slot,
-- splash and pulse pools only grow (acquire/hide, never destroy); every style
-- setter is dirty-checked because the whole pass runs at 10 Hz. Positions,
-- tag placement and grouping are frame-free in UI/TimelineMath.lua.
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
    Spark = TEX .. "Spark2",
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

D.fontFile = nil   -- set by validateFont() in Init; nil = template fallback

local ANCHOR_W, ANCHOR_H = S.Width, 20
local DEFAULT = { point = "CENTER", relPoint = "CENTER", x = 0, y = -150, locked = true }

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

--- Validate the shipped font ONCE: CreateFont the file, SetFont it on a
--- throwaway fontstring and read GetFont back. Accepted only when the round
--- trip returns the same file; everything else leaves fontFile nil and every
--- fontstring keeps its GameFontHighlightSmall template.
local function validateFont()
    local okCreate, fontObj = pcall(CreateFont, FONT_FILE, FONT_SIZE)
    if not okCreate or not fontObj then return nil end
    local probe = UIParent:CreateFontString(nil, "OVERLAY")
    if not probe then return nil end
    local okSet = pcall(probe.SetFont, probe, FONT_FILE, FONT_SIZE)
    local got = okSet and probe:GetFont()
    probe:Hide()
    if type(got) == "string" and got:lower() == FONT_FILE:lower() then
        return FONT_FILE
    end
    return nil
end

--- Apply the validated font, dirty-checked, falling back to the string's
--- GameFontHighlightSmall template (set at creation) when the file was not
--- accepted. SetFont returns the object (truthy) on success in 12.x; treat
--- any false/nil return or raise as a rejection and restore the template.
local function applyFont(fs, size, flags)
    local key = tostring(size) .. "|" .. (flags or "")
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
local function formatRemaining(remaining)
    if remaining >= 60 then
        return string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
    end
    return string.format("%.1f", remaining)
end

--- The entry's category color: the Engine's per-spell `fxClass` override,
--- else the default Spell orange. Read once per (slot, name) bind.
local function classColor(name)
    local tracked = FX.Cooldown.Engine and FX.Cooldown.Engine.tracked
    local t = tracked and tracked[name]
    local cls = (t and t.fxClass) or "Spell"
    return S.Colors[cls] or S.Colors.Spell
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
    self.slots = {}
    self.tagFS = {}
    self.splashPool = {}
    self.pulsePool = {}
    self._xf = {}        -- cross-fade focus state, keyed by group signature
    self._gitems = {}    -- scratch for grouping (entries are engine-owned)
    self._ready = {}

    self:BuildTags()
    self:ApplyPosition()
    self:SetLocked(self.cfg.locked and true or false)
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

-- ----------------------------------------------------------------- pools --
--- Icon slot i from the grow-only pool: a bar-height frame carrying the
--- spell icon, its Spark2 running glow (ADD blend, category-tinted) and the
--- on-icon time text (IconTime, :1837). Created on first demand, never
--- destroyed; Update hides what it does not need.
function D:AcquireSlot(i)
    local slot = self.slots[i]
    if slot then return slot end

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

    -- IconTime text: IconFont = font, size-1, OUTLINE (:1806), anchored
    -- BOTTOMLEFT of the icon (NewBar :1120-1122).
    local timeFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    applyFont(timeFS, ICON_FONT_SIZE, "OUTLINE")
    timeFS:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)

    slot = { frame = frame, tex = tex, spark = spark, timeFS = timeFS, seg = seg }
    self.slots[i] = slot
    return slot
end

--- Bind a slot to an entry: textures, colours, splash, fade start.
--- Everything heavy lives in the first-sighting branch; the per-tick path in
--- Update stays allocation-free. `cx` = icon centre x relative to the bar.
function D:BindSlot(slot, e, cx, now)
    if slot._name == e.name then return end
    slot._name = e.name
    slot._texPath = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(e.name)
    if slot._texPath then
        -- The icon texture stays UNTINTED (bar.icon:SetNormalTexture(t5),
        -- :1400); the category colour rides the segment, spark and text.
        slot.tex:SetTexture(slot._texPath)
    end
    local col = classColor(e.name)
    slot._col = col
    slot._segCol = col                      -- segment: raw category (:1403)
    local fr, fg, fb = fixIntensity(col[1], col[2], col[3])
    slot.spark:SetVertexColor(fr, fg, fb)   -- FixIntensity (:1407, :1417)
    slot.timeFS:SetTextColor(fr, fg, fb)    -- IconTextColor off -> FixIntensity
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
        local f = CreateFrame("Frame", nil, UIParent)
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
        it.slot = self.slots[i]
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
    if col and slot._segSetA ~= a then
        slot._segSetA = a
        seg:SetVertexColor(col[1], col[2], col[3], a)
    end
end

--- Render one pass. `entries` is the Engine's reused scratch array, sorted
--- soonest-ready first -- the only thing we tag onto it is the transient
--- numeric `.x` the grouping consumes; keep no references to it.
function D:Update(entries, now)
    if not self.anchor then return end
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local n = #entries

    for i = 1, n do
        local e = entries[i]
        local remaining = e.endTime - now
        local x = TM.pos(remaining, W, H, Max, Loga)
        e.x = x                                   -- transient tag (see above)
        e.v = (x + H * 0.5) / W                   -- the position factor t7
        local slot = self:AcquireSlot(i)
        local cx = x + H * 0.5 - (W - 2 * S.Inset) * 0.5  -- centre for the splash
        self:BindSlot(slot, e, cx, now)
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
        slot.timeFS:SetText(formatRemaining(math.max(0, remaining)))

        -- Attach a queued ready pulse (OnReady is fed by the Module).
        local endAt = self._ready[e.name]
        if endAt then
            self._ready[e.name] = nil
            self:SpawnPulse(e.name, slot._texPath, slot._col, endAt)
        end
    end

    -- Overlap groups + cross-fade focus (TimelineMath.group, original
    -- :554-637). Singletons keep alpha 1.
    local items = self:_GroupItems(entries, n)
    local groups = TM.group(items, H)
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
        local slot = self.slots[i]
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

    -- Slots past the entry count: hide (frame + segment), and only if
    -- actually shown.
    for i = n + 1, #self.slots do
        local slot = self.slots[i]
        if slot._shown and slot.frame:IsShown() then
            slot._shown = false
            slot.frame:Hide()
            slot.seg:Hide()
        end
    end

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
