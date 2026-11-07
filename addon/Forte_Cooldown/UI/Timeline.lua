-- Forte_Cooldown/UI/Timeline.lua
-- The Classic Cooldown Timer, PLAN.md §3.5: ONE 250x24 timeline bar (not a
-- stack of rows -- the rows are the Spell Timer, §3.6; the old row renderer
-- the ClassicSkin wave built died with that wave: its dormant seed
-- UI/Rows.lua was forked into Forte_Timer/UI/Rows.lua and deleted here
-- 2026-11-02, it was never in this addon's TOC). Cooldowns ride a
-- power-scale time axis: the icon for t seconds remaining sits at
-- TimelineMath.pos(t) and slides left as it burns, parking at the right end
-- over Max = 300 s; custom time tags (0 1 10 30 60 120 ...) print under the
-- same curve; icons overlapping by more than half an icon form a group that
-- cross-fades focus between its members over exactly 1.0 s (the focus
-- visibility t14 ramps +1/s, the hand-off at t14 >= 1, the outgoing side
-- decays -1/s, :619-633). The splash AND the end-of-cooldown pulse are the
-- source's single t15==-1 expiry effect (:353-354 sets t14 = 1, :629-632
-- decays it at 1/s -> a 1.0 s window): a WHITE icon texture (vertex colour
-- never set, :1088; BLEND), size SplashFactor*ih*(1-t14) = 0 -> 4*ih linear
-- (:1381, :1812), a 2.2x Spark2 ADD glow behind it tinted
-- FixIntensity(category) (:1083-85, :1386-87, :1407, :1418), the whole bar
-- fading alpha t14 = 1 -> 0 linear (:1403). We fire that curve on a cast's
-- first sighting (name-keyed slots) at the icon centre, and the pulse at
-- the left end, over the same 1.0 s law. Source law:
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
--
-- CD-30/CD-31/CD-35 (Phase 2, 2026-11-02): the bar's own right-button release
-- opens the options window on the Cooldown page, dropped when the cursor
-- travelled between press and release (the source's `FW:Moved()` guard,
-- Forte_Core/Options.lua :659-662); a `UNIT_SPELLCAST_FAILED` of a spell that
-- already has a live entry takes attention on that icon -- the ADD-blend
-- Spark2 pulse at 2.2*ih*t20 and the group's cross-fade focus (the source's
-- CD_CastFailed + CD_FocusTimer, :933-946 / :860-877), gated by the `Warn`
-- setting; and the bar draws in three geometry modes -- Vertical (the icons
-- bottom->top up the bar's height), Flip (right->left, tags and segment
-- gradients mirrored), HideZero (the bar hides itself while the feed carries
-- nothing) -- all sharing the one TimelineMath.pos axis through the
-- axisPoint/axisOffset/segmentPoints helpers.

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
    -- The FRAME SIZING block's third row (`IconSize`, the NU2 row
    -- Forte_Cooldown.lua:1760 = a value plus its `[0]` gate; the value
    -- default 36, the gate OFF: `IconSize = {[0]=false,36}` :1805). A
    -- gate-off icon rides the bar height -- the source's
    -- `ih = s.IconSize[0] and s.IconSize[1] or s.Height` (:1151, :1364).
    -- Our NU2 gates ride their own `<Key>On` key (the Forte_Timer
    -- `Max`/`MaxOn` convention).
    IconSizeOn = false, IconSize = 36,
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
    -- TextColor (tag labels): the APPEARANCE row "Bar text"
    -- (Forte_Cooldown.lua:1765, FWL.BAR_TEXT, Localization.lua:1019),
    -- default {1,1,1,0.20} (:1838). The source's only consumer is the
    -- time-tag path (SetTimeTags :1270, :1289) -- D:SetTextColor.
    TextColor = { 1, 1, 1, 0.20 },
    TimeFormatAlt = true,                     -- General AltTimeFormat:
                                              -- m:ss for EVERY time. The
                                              -- original's default is ON
                                              -- (`TimeFormat = true`,
                                              -- Forte_Core.lua:2487), so
                                              -- a fresh install prints
                                              -- `0:45`, not `45.0`.
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
                                              -- (`Alpha`/`AlphaMax`,
                                              -- :1818/:1819; the page keys
                                              -- are BarAlpha/BarAlphaMax --
                                              -- see D:SetBarAlpha)
    -- The icon's own time text (`IconTime`, :1835 default true; the row is
    -- SPECIFICS :1718 "Show Icon text") and its colour (`IconTextColor` =
    -- {[0]=false,1,1,1,1}, :1837; the row is :1719 "Icon text color", whose
    -- [0] gate rides IconTextColorOn). Gate off -> the text rides
    -- FixIntensity(category) (:1419-1425).
    IconTime = true,
    IconTextColorOn = false,
    IconTextColor = { 1.00, 1.00, 1.00, 1.00 },
    -- The fresh-visibility ramp, 1.0 s by the source law: the focus hand-off
    -- starts a fresh member at visibility 0 (:625 `cd[n][14] = 0; -- set its
    -- visibilty to zero just to make sure`; the "correcting focus" init of a
    -- group without one is the other end, :598 `cd[n][14] = 1`), and the
    -- render loop advances the focused bar's t14 by the elapsed seconds,
    -- clamped at 1 (:611 `t14 = t14+(tim-cd[i][16]);` -> +1.0 per second,
    -- :612-614). The frame alpha rides that visibility (:1402
    -- `bar:SetAlpha(t14)`), so the icon's fade-in from S.Alpha to S.AlphaMax
    -- spans the same 1.0 s. (The 0.3 here was an invented cadence.)
    FadeSeconds = 1.0,
    CrossfadeSeconds = 1.0,                   -- group focus dwell: t14 ramps
                                              -- +1/s, hand-off at >= 1,
                                              -- outgoing -1/s (:619-633)
    SplashOn = true,                          -- the per-bar splash gate
                                              -- (`Splash`, :1811 default
                                              -- true; the row is the SPLASH
                                              -- block :1723 "Splash ready
                                              -- cooldowns"): it gates the
                                              -- t15==-1 expiry visual, both
                                              -- its casts (:1380 `if
                                              -- s.Splash and t15==-1`)
    SplashFactor = 4,                         -- splash peak = 4x the icon
                                              -- (size = SplashFactor*ih*
                                              -- (1-t14) :1381; =4 :1812)
    SplashAlpha = 1.0,                        -- frame alpha at splash start
                                              -- = t14 = 1 (:354, :1403; the
                                              -- 0.7 default is the DISABLED
                                              -- secondary splash window,
                                              -- :1872, not the bar splash)
    SplashSeconds = 1.0,                      -- t14 decays -1/s clamped (:629-632)
    SplashCrop = { 0.133, 0.867 },            -- spark-on splash texcoord crop
                                              -- (:1388; full 0,1,0,1 :1391)
    PulseSeconds = 1.0,                       -- same expiry window: t14 = 1
                                              -- decaying at -1/s (:354,
                                              -- :629-632)
    PulseCycle = 0,                           -- NO alpha wave in the source
                                              -- (:1403 is the only alpha
                                              -- law: linear 1->0); 0 = the
                                              -- spark rides a constant alpha

    -- The TIME RANGE block's four filters (`MinRange` :1826, `MaxRange`
    -- :1827, `MinRemaining` :1828, `MaxRemaining` :1829 -- every one of them
    -- `{[0]=false, N}`: the value, plus its `[0]` gate on a separate key).
    -- The rows are :1729-1732; the law is CD_TimeFilterDuration /
    -- CD_TimeFilterRemaining (:488-495), applied to the draw pass by the
    -- t17 filter flag (:547, drawn only `t17 == 0`, :1371). All four gates
    -- ship OFF: a fresh bar shows every cooldown.
    MinRangeOn = false,      MinRange = 0,
    MaxRangeOn = false,      MaxRange = 3600,
    MinRemainingOn = false,  MinRemaining = 0,
    MaxRemainingOn = false,  MaxRemaining = 3600,

    -- CD-35 frame geometry modes (CD-31's Warn rides the same option block).
    -- The axis runs left -> right by default; Vertical turns it into a
    -- bottom -> top column AND swaps the frame size (frame.Update
    -- :1476-1479: SetWidth(Height + 2*d) / SetHeight(Width + 2*d)), Flip runs
    -- it right -> left (icons :1440-1443, tags :1263, segments' TexCoord
    -- mirrored :1441). Defaults: Vertical = false (:1808), Flip = false
    -- (:1809). CD-35's third mode, HideZero (hide the bar while no cooldown
    -- is on it), is a VISIBILITY gate, so it rides D.frameState.hideZero
    -- below (the source's `Hide` row, default false :1813).
    Vertical = false,
    Flip = false,
    Warn = true,                              -- s.Warn (:1821): a failed cast
                                              -- of a cooling spell flashes
                                              -- that icon (CD-31)
    WarnSeconds = 0.5,                        -- `local focustime = 0.5` (:32):
                                              -- cd[i][20] = 1 + focustime,
                                              -- decayed -1/s (:528-530), the
                                              -- attention pulse window
    AttentionScale = 2.2,                     -- the attention spark is
                                              -- `2.2*ih*(t20)` (:1409)

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
local ICON_FONT_SIZE = FONT_SIZE - 1   -- FW IconFont = Font size - 1 (:1810)
local ICON_FONT_FLAGS = "OUTLINE"

D.fontFile = nil   -- set by validateFont() in Init; nil = template fallback

local ANCHOR_W, ANCHOR_H = S.Width, 20
local DEFAULT = { point = "CENTER", relPoint = "CENTER", x = 0, y = -150, locked = true }

--- The overlap-lane cap (m3, code-review-10): the perpendicular step of the
--- render pass is `lane * 0.75 * Height`, so the cap is the geometry budget --
--- lane 3 is the last step off the axis (a 2.25-icon-width reach at H=24), and
--- icons crowded past it fold into the last lane. 3 == four lanes.
local LANE_MAX = 3

-- Frame scale/alpha inputs (OP-06 header fields + General FrameAlpha/
-- FrameScale), module-local so the setters are safe to call before Init
-- (the values are live skin state; Init and ApplyFrameFX read them back).
D.frameState = {
    scale = 1.0, alpha = 1.0,          -- the Cooldown page's Scale / Alpha
    globalScale = 1.0, globalAlpha = 1.0,   -- General FrameScale / FrameAlpha
    enabled = true, hideCombat = false,     -- Basics: Enable / HideCombat
    hideZero = false,                       -- CD-35 `Hide` (:1813): the bar is
                                            -- auto-hidden while cd is empty
}
local FS = D.frameState

--- The DRAWN size of one icon (and of the art that rides an icon: its
--- running/attention glows, the splash, the ready pulse). The source's law
--- `ih = s.IconSize[0] and s.IconSize[1] or s.Height` (:1151, :1364): with
--- the gate off (the shipped default :1805) the icon rides the bar height.
--- The curve positions, the tags and the segments ride the bar HEIGHT in
--- every mode (the position passes compute `ih = s.Height`, :502, :1236):
--- this size moves the icon art, never its place on the axis.
local function iconSize()
    if S.IconSizeOn and type(S.IconSize) == "number" and S.IconSize > 0 then
        return S.IconSize
    end
    return S.Height
end

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
---
--- n6: the template branch stores a SENTINEL key -- the requested key with
--- "#tpl" on it -- not nil, so the dirty check holds on the rejected-font
--- path: a BarFont the client refused used to re-run `SetFontTemplate` on
--- every fontstring of every BuildTags/SetBarFont pass. The sentinel
--- carries the requested file, so it is only the accepted state for THAT
--- request: a later BarFont change (a new D.fontFile, the all-template
--- state) moves to a new key and the string re-applies.
local function applyFont(fs, size, flags)
    local key = (D.fontFile or "tpl")
        .. "|" .. tostring(size) .. "|" .. (flags or "")
    local tplKey = key .. "#tpl"
    if fs._font == key or fs._font == tplKey then return end
    local ok = false
    if D.fontFile then
        ok = pcall(fs.SetFont, fs, D.fontFile, size, flags)
        if ok then ok = (fs:GetFont()) == D.fontFile end
    end
    if not ok then
        pcall(fs.SetFontTemplate, fs, "GameFontHighlightSmall")
        key = tplKey
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

--- Are the TIME RANGE filters on at all? The render pass asks this once;
--- with every gate off (the shipped default) the pass runs its own entries
--- array and the filter machinery is not entered.
local function filtersActive()
    return S.MinRangeOn or S.MaxRangeOn or S.MinRemainingOn or S.MaxRemainingOn
end

--- CD_TimeFilterDuration + CD_TimeFilterRemaining, verbatim (:488-495):
--- `Min <= value` and `Max >= value` for every gate that is on. The duration
--- half rides the row's TOTAL duration (the source's cd[i][4], the legend at
--- :466-469), the remaining half the live remaining (cd[i][2]). A row with no
--- readable duration is a row the duration gate can not vouch for: with a
--- duration gate on, it stays off the bar.
local function passesFilter(duration, remaining)
    if S.MinRangeOn and (type(duration) ~= "number" or duration < S.MinRange) then
        return false
    end
    if S.MaxRangeOn and (type(duration) ~= "number" or duration > S.MaxRange) then
        return false
    end
    if S.MinRemainingOn and remaining < S.MinRemaining then return false end
    if S.MaxRemainingOn and remaining > S.MaxRemaining then return false end
    return true
end

--- The icon text colour: `IconTextColor[0]` picks the custom colour, off
--- picks the FixIntensity tint of the row's category (:1419-1425 -- the
--- block is inside `if s.IconTime`, and the colour is the one the spark
--- rides). `fr, fg, fb` is that FixIntensity result, computed by the caller.
local function iconTextColor(fr, fg, fb)
    if S.IconTextColorOn then
        local c = S.IconTextColor
        return c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
    end
    return fr, fg, fb
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

-- ------------------------------------------------------- geometry modes --
-- CD-35 (`Vertical`, `Flip`). The bar has ONE axis coordinate: `a`, the
-- position TimelineMath.pos produced, counted from the axis's ORIGIN end --
-- the bar's LEFT end horizontally, its BOTTOM end vertically (the source
-- branches on exactly these two flags in NewBar.Update :1176-1189, in the
-- tag path :1260-1263 / :1279-1282 / :1319-1322 and in the draw loop's
-- icon/segment block :1427-1450). Anchoring an icon to the bar's origin-end
-- point with offset `+a` is the source's
-- `bar.icon:SetPoint("CENTER", bar, "LEFT", t10, 0)` (:1449); Flip mirrors
-- the whole axis (the source moves the anchor to the far end and negates
-- the offset), which is why every one of the four modes is this one pair of
-- helpers. The axis SPAN (the inset bar layer's length along the axis) is
-- S.Width - 2*S.Inset in both orientations, because SetSize swaps the frame
-- size (the source's frame.Update :1476-1479).

--- The anchor triple for a bar-anchored object at axis position `a`: the
--- frame point, the relative (same) point and the x/y offsets.
local function axisPoint(a)
    if S.Vertical then
        if S.Flip then return "TOP", 0, -a end
        return "BOTTOM", 0, a
    end
    if S.Flip then return "RIGHT", -a, 0 end
    return "LEFT", a, 0
end

--- The anchor offsets for a CENTRE-anchored object (the time tags, the cast
--- splash, the ready pulse) whose axis offset `o` is measured from the
--- frame's centre.
local function axisOffset(o)
    if S.Vertical then
        if S.Flip then return 0, -o end
        return 0, o
    end
    if S.Flip then return -o, 0 end
    return o, 0
end

--- The segment's two anchor pairs (:1427-1450): the slice spans the axis
--- from `leftX` (its group's left border) to `rightX` (the icon's own
--- centre), so the two points are the bar's two CORNER pairs; the far one is
--- expressed from the far end, which is what the source's `s.Width - t9`
--- offsets say, in the bar layer's own span. Returns
--- p1, x1, y1, p2, x2, y2.
local function segmentPoints(leftX, rightX)
    local span = S.Width - 2 * S.Inset
    if S.Vertical then
        if S.Flip then
            return "TOPRIGHT", 0, -leftX, "BOTTOMLEFT", 0, span - rightX
        end
        return "TOPLEFT", 0, rightX - span, "BOTTOMRIGHT", 0, leftX
    end
    if S.Flip then
        return "TOPRIGHT", -leftX, 0, "BOTTOMLEFT", span - rightX, 0
    end
    return "TOPLEFT", leftX, 0, "BOTTOMRIGHT", rightX - span, 0
end

--- The segment's TexCoord slice (:1429-1450): the Aluminium gradient runs
--- along the axis, so Vertical swaps the u/v pairs and Flip swaps which of
--- the two uv values rides the left corner pair. 8-arg order:
--- (ulX,ulY, llX,llY, urX,urY, lrX,lrY).
local function setSegmentUV(seg, uvL, uvR)
    if S.Vertical then
        if S.Flip then
            seg:SetTexCoord(uvL, 0, uvR, 0, uvL, 1, uvR, 1)
        else
            seg:SetTexCoord(uvR, 0, uvL, 0, uvR, 1, uvL, 1)
        end
    elseif S.Flip then
        seg:SetTexCoord(uvR, 0, uvR, 1, uvL, 0, uvL, 1)
    else
        seg:SetTexCoord(uvL, 0, uvL, 1, uvR, 0, uvR, 1)
    end
end

--- The identity of the current geometry mode, for the dirty checks that must
--- re-run when only the MODE moved (the segment TexCoord slice).
local function geoKey()
    return (S.Vertical and "V" or "H") .. (S.Flip and "F" or "")
end

--- The frame size of the current geometry mode: the source's frame.Update
--- (:1476-1482) swaps width and height (and flips the backdrop's TexCoord)
--- for Vertical, so the 250-long axis is the frame's HEIGHT there.
function D:ApplyBarSize()
    if not self.anchor then return end
    if S.Vertical then
        self.anchor:SetSize(S.Height, S.Width)
    else
        self.anchor:SetSize(S.Width, S.Height)
    end
    if self.fill and self.fill.SetTexCoord then
        if S.Vertical then
            self.fill:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)  -- :1479
        else
            self.fill:SetTexCoord(0, 0, 0, 1, 1, 0, 1, 1)  -- :1483
        end
    end
end

-- ------------------------------------------------------------------- init --
--- One tag fontstring by index; grow-only pool. `axisOff` is the tag's
--- offset from the frame centre ALONG the axis (CD-35: axisOffset lays it
--- out on the current axis, mirroring the sign for Flip).
function D:_TagSlot(i, text, axisOff)
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
    local ox, oy = axisOffset(axisOff)
    fs:SetPoint("CENTER", self.anchor, "CENTER", ox, oy)
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
    -- note): locking flips SetMovable -- the DRAG -- and never the mouse
    -- (the lock law in SetLocked).
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    -- CodeReview6 M2: the source stamps EVERY press -- the wiring is
    -- `<OnMouseDown>FW:StartMoving(self,button)` (Forte_Soulstone.xml
    -- :189-191), and FW:StartMoving stamps before its lock check. The
    -- engine only fires OnDragStart for the REGISTERED drag button
    -- (RegisterForDrag(buttons: MouseButton)), so the right-button press
    -- stamps nothing while the stamp rides only OnDragStart -- after one
    -- left-drag every later right-click reads as "moved" against the stale
    -- stamp and the seam dies. The press stamp therefore rides OnMouseDown
    -- (any button); the OnDragStart stamp stays (the sim's rigs drive that
    -- script directly).
    f:SetScript("OnMouseDown", function() self:_StampPress() end)
    f:SetScript("OnDragStart", function(fr, button)
        -- FW:StartMoving (Forte_Core/Options.lua:649-656) stamps the cursor
        -- at press; FW:Moved() (:659-662) is the release-time compare that
        -- makes CD-30's right-click skip a drag. The stamp lands FIRST --
        -- the source's FW:StartMoving stamps, then its lock check is the
        -- one that refuses the move -- and the lock check after it is the
        -- belt to SetMovable(false): a locked bar starts no move.
        self:_StampPress()
        if self.cfg.locked then return end
        fr.StartMoving(fr, button)
    end)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        self:SavePosition(fr)
    end)
    -- CD-30: a right-button release on the bar opens the options window on
    -- this module's page. The source wires the release on the frame itself
    -- (Forte_Cooldown.lua :1226-1227: OnMouseDown = FW:StartMoving, OnMouseUp
    -- = FW:StopMoving + Frame_OnClick(button) -> FW:ScrollTo(COOLDOWN_TIMER),
    -- :901-909). "OnMouseUp" is also the script this engine accepts on a
    -- plain Frame ("OnClick" is a Button-only slot here -- the sim rejects
    -- it on a Frame), and its payload is (frame, mouseButtonName, upInside)
    -- exactly as in the Blizzard UI's own OnMouseUp handlers (m2,
    -- CodeReview6: the catalog's SCRIPT-HANDLERS.md OnMouseUp row --
    -- `upInside` is true when the cursor is still over the widget at the
    -- release).
    f:SetScript("OnMouseUp",
        function(_, button, upInside) self:OnMouseUp(button, upInside) end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetText("Forte Cooldowns")
    title:SetTextColor(1, 1, 1, 1)
    title:SetPoint("BOTTOM", f, "TOP", 0, 2)

    self.anchor, self.title, self.bar, self.fill = f, title, bar, fill
    self._geoMode = geoKey()
    -- The frame size follows the geometry mode (CD-35; the source sizes the
    -- frame in frame.Update :1476-1482, i.e. after the settings are read).
    self:ApplyBarSize()
    self.slots = {}        -- grow-only icon-slot pool
    self._byName = {}      -- name -> slot bound to it (names on the bar)
    self._free = {}        -- stack of released slots (release pops, O(1))
    self._islot = {}       -- scratch: per-pass index -> bound slot
    self._draw = {}        -- scratch: the TIME RANGE filter's compacted view
    self._seen = {}        -- scratch: names present in the current pass
    self.tagFS = {}
    self.splashPool = {}
    self.pulsePool = {}
    self._xf = {}        -- cross-fade focus state, keyed by group signature
    self._gitems = {}    -- scratch for grouping (entries are engine-owned)
    self._groupsScratch = {}   -- TM.group's caller-owned scratch (m5)
    self._ready = {}
    -- CD-31: names whose last failed cast asked for attention, pending the
    -- pass that draws them (the stamp needs the render clock, so the
    -- handler only records the intent).
    self._steal = {}

    -- CD-31 Warn: the Display's OWN event frame (created here inside Init,
    -- which runs at PLAYER_LOGIN -- never at chunk scope), registered for
    -- the player's failed casts. The source registers/unregisters the
    -- handler on the Warn checkbox itself (:953-960); SetWarn does the same
    -- through the script slot (the Forte_Hunter/Warlock UI convention).
    local ef = CreateFrame("Frame", nil, UIParent)
    ef:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
    self._eventFrame = ef
    self:_BindWarnEvents()

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
    -- The lock law (the source: the lock gates the DRAG and nothing else
    -- -- the row label is literally "Lock (disable dragging)", FWL.LOCK
    -- Forte_Cooldown.lua:2114, and the one lock check in the whole move
    -- path sits in FW:StartMoving, Forte_Core/Options.lua:649-656; a
    -- locked frame's mouse release still fires, e.g. the source's
    -- Forte_Soulstone.xml OnMouseUp). SetMovable(false) removes the drag
    -- scripts; EnableMouse stays TRUE so the CD-30 right-click seam works
    -- on a locked bar -- the bar SHIPS locked, the seam must be usable
    -- out of the box.
    self.anchor:SetMovable(not locked)
    self.anchor:EnableMouse(true)
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
    self:ApplyBarSize()
    self:_ResizeIconPools()
    self:InvalidateLayout()
    self:ReflowEffects()
    self:BuildTags()
end

--- The pool geometry at the current `iconSize()`: the slot frame, its
--- icon, the running/attention glows, the splash pool's caps and the
--- ready pulses (the size loop SetSize used to run inline; the
--- `IconSize` rows drive the very same pass, as the source recomputes
--- `ih` once per draw for all of them, :1364). A running splash's live
--- size is recomputed by `_SplashCurve` on every pass; an armed
--- attention spark re-sizes through the busted `_alertSize` cache.
function D:_ResizeIconPools()
    if not self.anchor then return end
    local ih = iconSize()
    for i = 1, #(self.slots or {}) do
        local slot = self.slots[i]
        slot.frame:SetSize(ih, ih)
        slot.tex:SetSize(ih, ih)
        slot.spark:SetSize(ih * S.SparkScale, ih * S.SparkScale)
        -- The attention spark rides 2.2 x the icon at REST (:1409); an
        -- armed one is resized by the next attention pass.
        slot.alert:SetSize(ih * S.AttentionScale, ih * S.AttentionScale)
        slot._alertSize = nil
    end
    for i = 1, #(self.splashPool or {}) do
        local sp = self.splashPool[i]
        -- The animated sizes are re-set by _SplashCurve every pass; these
        -- are the geometry caps (peak splash = SplashFactor x the icon).
        sp.tex:SetSize(ih * S.SplashFactor, ih * S.SplashFactor)
        sp.spark:SetSize(ih * S.SplashFactor * S.SparkScale,
            ih * S.SplashFactor * S.SparkScale)
    end
    for i = 1, #(self.pulsePool or {}) do
        local p = self.pulsePool[i]
        p.tex:SetSize(ih, ih)
        p.spark:SetSize(ih * S.SparkScale, ih * S.SparkScale)
    end
end

--- Re-anchor the live splash / ready-pulse frames on the axis: a Width
--- change (SetSize) or a geometry-mode change (SetVertical/SetFlip) moves
--- every centre-relative offset, and these frames animate on their own
--- clock, not on an entry, so nothing else would move them.
function D:ReflowEffects()
    if not self.anchor then return end
    for i = 1, #self.splashPool do
        local s = self.splashPool[i]
        if s._off then
            s.frame:ClearAllPoints()
            local ox, oy = axisOffset(s._off)
            s.frame:SetPoint("CENTER", self.anchor, "CENTER", ox, oy)
        end
    end
    for i = 1, #self.pulsePool do
        local p = self.pulsePool[i]
        if p._off then
            p.frame:ClearAllPoints()
            local ox, oy = axisOffset(p._off)
            p.frame:SetPoint("CENTER", self.anchor, "CENTER", ox, oy)
        end
    end
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
        slot._cp = nil          -- the geometry mode's anchor point
        slot._segSetL, slot._segSetR = nil, nil
        slot._segSetVL, slot._segSetV = nil, nil
        slot._segSetMode = nil
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
            slot.timeFS:SetTextColor(iconTextColor(fr, fg, fb))
            slot.alert:SetVertexColor(fr, fg, fb)   -- :1412 tint
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

--- `TextColor` (the APPEARANCE row "Bar text", Forte_Cooldown.lua:1765,
--- FWL.BAR_TEXT, default {1,1,1,0.20} :1838): the colour of the TIME-TAG
--- text -- the source's only consumer is the tag path
--- (`tag:SetTextColor(unpack(s.TextColor))`, SetTimeTags :1270, :1289).
--- Re-tints every live tag string (hidden pool strings ride along, so a
--- tag built later reads the same skin colour).
function D:SetTextColor(col)
    if type(col) ~= "table" then return end
    S.TextColor = { col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 0.2 }
    local c = S.TextColor
    for i = 1, #(self.tagFS or {}) do
        self.tagFS[i]:SetTextColor(c[1], c[2], c[3], c[4])
    end
end

--- `IconSize` (the FRAME SIZING row :1760, the NU2 type: a value plus its
--- `[0]` gate, default `{[0]=false,36}` :1805 -- the gate rides the
--- `IconSizeOn` key): the icon's DRAWN size independent from the bar
--- height ("Set the icon sizes independently from the bar height",
--- Localization.lua:174). `ih = s.IconSize[0] and s.IconSize[1] or
--- s.Height` (:1151, :1364) sizes the bar icon, its running/attention
--- glows, the splash and the pulse; the axis curve, the tags and the
--- segments stay on the bar HEIGHT (:502, :1236) -- the icons grow in
--- place, they do not move.
function D:SetIconSize(v)
    if type(v) ~= "number" or v <= 0 then return end
    S.IconSize = v
    self:_ResizeIconPools()
end

function D:SetIconSizeOn(on)
    S.IconSizeOn = not not on
    self:_ResizeIconPools()
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
    -- The splash spark is the gate for the icon's crop too: Spark[0] on ->
    -- the 0.133..0.867 centre crop (:1388), off -> the full texture
    -- (:1391); the original branches on exactly this flag (:1385).
    for i = 1, #(self.splashPool or {}) do
        local sp = self.splashPool[i]
        if S.SparkOn then
            sp.spark:Show()
            sp.tex:SetTexCoord(S.SplashCrop[1], S.SplashCrop[2],
                S.SplashCrop[1], S.SplashCrop[2])
        else
            sp.spark:Hide()
            sp.tex:SetTexCoord(0, 1, 0, 1)
        end
    end
end

--- Bar alpha floor (`Alpha`, the SPECIFICS row :1716 "Minimum bar alpha",
--- default 0.2 :1818). The pair is the bar's alpha RANGE: the segment fill
--- rides `AlphaMax - (AlphaMax - Alpha) * t7` (:1404, applied at :1406) and
--- the icon's alpha rides the fresh-visibility ramp from `Alpha` up to
--- `AlphaMax` (:1402 with :611-614). Our page keys are `BarAlpha` /
--- `BarAlphaMax`: this module's `Alpha` key is the HEADER frame's alpha
--- (OP-06, SetAlpha), which is a different law.
function D:SetBarAlpha(v)
    if type(v) ~= "number" then return end
    S.Alpha = v
    self:_BustAlpha()
end

--- Bar alpha ceiling (`AlphaMax`, row :1717 "Maximum bar alpha", default
--- 1.0 :1819). A settled icon sits exactly here, so this is the live witness
--- of the pair.
function D:SetBarAlphaMax(v)
    if type(v) ~= "number" then return end
    S.AlphaMax = v
    self:_BustAlpha()
end

--- The icon and segment alphas are dirty-checked against `_alpha` /
--- `_segSetA`; a change of the pair makes those caches stale, so the next
--- pass re-applies them.
function D:_BustAlpha()
    for i = 1, #(self.slots or {}) do
        local slot = self.slots[i]
        slot._alpha = nil
        slot._segSetA = nil
    end
end

--- `IconTime` (SPECIFICS row :1718 "Show Icon text", default true :1835):
--- the time text on the icons themselves. The source runs the whole icon
--- block behind `if s.IconTime` (:1419), so off takes the string off every
--- icon on the bar.
function D:SetIconTime(on)
    S.IconTime = not not on
    for i = 1, #(self.slots or {}) do
        local ts = self.slots[i].timeFS
        if S.IconTime then ts:Show() else ts:Hide() end
    end
end

--- `IconTextColor` = {[0]=false, 1,1,1,1} (:1837; the row :1719 "Icon text
--- color" -- its `[0]` gate rides the separate `IconTextColorOn` key, the
--- Forte_Timer `Max`/`MaxOn` convention).
function D:SetIconTextColor(col)
    if type(col) ~= "table" then return end
    S.IconTextColor = { col[1] or 1, col[2] or 1, col[3] or 1, col[4] or 1 }
    self:_RetintIconText()
end

function D:SetIconTextColorOn(on)
    S.IconTextColorOn = not not on
    self:_RetintIconText()
end

--- Re-run the icon text colour law (:1419-1425) over the bound slots: the
--- slot carries its category colour, so FixIntensity is recomputed and
--- `iconTextColor` picks the custom colour or that tint.
function D:_RetintIconText()
    for i = 1, #(self.slots or {}) do
        local slot = self.slots[i]
        if slot._name and slot._col then
            local fr, fg, fb = fixIntensity(slot._col[1], slot._col[2],
                slot._col[3])
            slot.timeFS:SetTextColor(iconTextColor(fr, fg, fb))
        end
    end
end

--- `Splash` (the SPLASH block's row :1723 "Splash ready cooldowns", default
--- true :1811): the gate of the source's t15==-1 expiry visual (:1380 `if
--- s.Splash and t15 == -1`). This port renders that ONE curve twice -- the
--- splash on the icon at the cast (SpawnSplash) and the pulse at the bar's
--- origin when the cooldown comes ready (SpawnPulse) -- so one gate rules
--- both. Off also clears what is on screen.
function D:SetSplashOn(on)
    S.SplashOn = not not on
    if S.SplashOn then return end
    for i = 1, #(self.splashPool or {}) do
        local s = self.splashPool[i]
        s._endAt = nil
        s.frame:Hide()
    end
    for i = 1, #(self.pulsePool or {}) do
        local p = self.pulsePool[i]
        p._endAt = nil
        p.frame:Hide()
    end
end

--- `SplashFactor` (row :1724 "Splash icon active scale", `SetRange(1)`: the
--- floor is 1, default 4 :1812): the bell's peak multiplier, the splash size
--- being `SplashFactor * ih * (1 - t14)` (:1381). The running curves re-read
--- the skin every pass; the pool's static geometry caps move here (the same
--- split SetSize makes).
function D:SetSplashFactor(v)
    if type(v) ~= "number" or v < 1 then return end
    S.SplashFactor = v
    for i = 1, #(self.splashPool or {}) do
        local sp = self.splashPool[i]
        sp.tex:SetSize(S.Height * S.SplashFactor, S.Height * S.SplashFactor)
        sp.spark:SetSize(S.Height * S.SplashFactor * S.SparkScale,
            S.Height * S.SplashFactor * S.SparkScale)
    end
end

--- The four TIME RANGE filters (rows :1729-1732): `MinRange`/`MaxRange` gate
--- a row on its TOTAL duration, `MinRemaining`/`MaxRemaining` on its live
--- remaining, and every value has its `[0]` gate on a `<Key>On` key (the
--- defaults :1826-1829 are the value 0 / 3600 / 0 / 3600 with every gate OFF).
--- The eight keys are one shape, so they are built in a loop; the render pass
--- re-decides every entry at 10 Hz, so a change needs no cache bust.
for _, key in ipairs({ "MinRange", "MaxRange", "MinRemaining",
    "MaxRemaining" }) do
    D["Set" .. key] = function(self, v)
        if type(v) == "number" then S[key] = v end
    end
    D["Set" .. key .. "On"] = function(self, on)
        S[key .. "On"] = not not on
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

--- The eight FrameStrata names (`SetFrameStrata`,
--- SimpleFrameAPIDocumentation.lua:1293) — the same eight the source's own
--- tip lists, Forte_Core/Localization.lua:441. Plain string literals.
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

--- The Advanced page's "Frame level (strata)" row for this frame (the
--- source's `CooldownStrata`, Forte_Cooldown.lua:1790, applied by its own
--- `self:SetFrameStrata(FW.Settings.CooldownStrata)` at :1490; default
--- `Strata = "MEDIUM"`, Forte_Core.lua:2531). A name outside the eight is
--- ignored: the store keeps the player's text, the bar keeps the strata it
--- has.
function D:SetStrata(name)
    local up = strataOrNil(name)
    if not up then return end
    FS.strata = up
    if self.anchor and self.anchor.SetFrameStrata then
        self.anchor:SetFrameStrata(up)
    end
end

function D:SetEnabled(on)
    FS.enabled = not not on
    self:UpdateVisibility()
end

function D:SetHideCombat(on)
    FS.hideCombat = not not on
    self:UpdateVisibility()
end

--- CD-35 `HideZero` (the source's `Hide` row of the geometry-mode block,
--- :1813 + the auto-hide term of Draw :1348): the bar hides itself while the
--- cooldown table carries nothing. The gate is the live feed size, so it
--- self-heals on the Module's 10 Hz pass with no extra event.
function D:SetHideZero(on)
    FS.hideZero = not not on
    self:UpdateVisibility()
end

--- CD-35 `Vertical`: the axis becomes the frame's HEIGHT, icons stacking
--- bottom -> top (the source's "BOTTOM" anchor branch :1446-1448 and the
--- frame-size swap :1476-1479). Everything that keys on the axis -- tags,
--- segments, the icon anchors, the live splash/pulse centres -- is rebuilt
--- from the same TimelineMath.pos numbers, mirrored onto the new axis.
function D:SetVertical(on)
    S.Vertical = not not on
    self._geoMode = geoKey()
    self:ApplyBarSize()
    self:InvalidateLayout()
    self:ReflowEffects()
    self:BuildTags()
end

--- CD-35 `Flip`: the axis runs from the far end (right -> left, or top ->
--- bottom when Vertical), with the tags and the segment gradients mirrored
--- (:1440-1443, :1263, :1441).
function D:SetFlip(on)
    S.Flip = not not on
    self._geoMode = geoKey()
    self:InvalidateLayout()
    self:ReflowEffects()
    self:BuildTags()
end

--- CD-31 `Warn` (:1821, default on): the source's CD_SpellFailed (:953-960)
--- registers / unregisters the UNIT_SPELLCAST_FAILED handler on exactly
--- this flag. Registering it in this engine means (re)installing the frame's
--- OnEvent script -- with the script off the frame is inert, which is the
--- Forte_Hunter / Forte_Warlock UI convention for a silent module.
function D:SetWarn(on)
    S.Warn = not not on
    self:_BindWarnEvents()
end

--- Install / remove the Warn handler (idempotent; safe before Init).
function D:_BindWarnEvents()
    local f = self._eventFrame
    if not f then return end
    if S.Warn then
        f:SetScript("OnEvent", function(_, event, unit, castGUID, spellID, castBarID)
            self:CastFailed(spellID)
        end)
    else
        f:SetScript("OnEvent", nil)
    end
end

--- CD-31 (Forte_Cooldown.lua :933-946 `CD_CastFailed`): a failed cast of a
--- spell that is ALREADY on the bar is the "you tried to cast something that
--- is cooling" warning -- the icon takes attention. `unit == "player"` is
--- the frame's own RegisterUnitEvent filter (the source also accepted
--- "pet", :936; Forever's payload carries the unit token, verified in the
--- pinned catalog @UnitDocumentation.lua:4713).
---
--- The spellID -> name resolve is Module:RecordCastEvent's law verbatim:
--- the pcall wraps the whole C_Spell.GetSpellInfo read, PlainOrNil classifies
--- the field (a combat-secret spellID resolves to nil, and NOTHING is ever
--- compared or counted on a raw payload field), and only a plain string
--- leaves the protected call.
function D:CastFailed(spellID)
    if not S.Warn then return end
    local name
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, resolved = pcall(function()
            local info = C_Spell.GetSpellInfo(spellID)
            return info and FX.Compat.PlainOrNil(info.name)
        end)
        if ok and type(resolved) == "string" then name = resolved end
    end
    if not name then return end
    -- "a spell that has a live entry on the bar" (:938 `for i=cd.rows,1,-1
    -- do if cd[i][1] == spell ...`): a name with no slot is not cooling, so
    -- nothing flashes. The source also excludes its BUFF/DEBUFF rows from
    -- the attention (:939); in this port that category rides the slot.
    local slot = self._byName and self._byName[name]
    if not slot then return end
    local class = slot._colorClass
    if class == "Buff" or class == "Debuff" then return end
    self._steal[name] = true
end

--- FW:StartMoving's press stamp (Forte_Core/Options.lua:649-656): the cursor
--- position at the moment the bar started moving.
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

--- CD-30 (the source's `Frame_OnClick`, Forte_Cooldown.lua :901-909, wired on
--- the frame's own mouse release at :1226-1227): a right-button release on
--- the bar opens the options window on this module's page; a release that
--- followed a drag is dropped by the Moved guard. The source's matching
--- `PlaySound("igMainMenuOptionCheckBoxOn")` (:907 -- the panel's only
--- sound, spec CD-33) is Forte_Options' own UI click and lives with its
--- widgets, not on the bar.
function D:OnMouseUp(button, upInside)
    if button ~= "RightButton" then
        -- CodeReview6 M2: the stamp describes ONE press/release pair (the
        -- source's cx,cy ride every press, and a stale stamp is exactly
        -- M2's dead seam): the release consumes it, on every exit.
        self._downX, self._downY = nil, nil
        return
    end
    local moved = self:Moved()
    self._downX, self._downY = nil, nil
    if moved then return end
    -- m2 (CodeReview6): a release the client reports OUTSIDE the frame
    -- (the catalog's 3rd OnMouseUp slot) is not a click on it. nil = the
    -- slot not delivered (a hand-driven script), treated as inside.
    if upInside == false then return end
    -- `RightClickOptions` (the source's row of the same name,
    -- Forte_Core/Options.lua:5545, default true at Forte_Core.lua:2495; our
    -- row rides the General page, where the shared frame keys live). Off =
    -- the bar is silent: the release is consumed, nothing opens.
    local st = FX.Settings
    if st and st.IsRegistered and st:IsRegistered("General")
        and st:Get("General", "RightClickOptions") == false then
        return
    end
    local O = FX.Options
    if not O or not O.Open then return end
    pcall(O.Open, O, "Cooldown")
end

function D:SetTimeFormatAlt(on)
    S.TimeFormatAlt = not not on
    -- The displayed string identity changes -> force one repaint pass.
    for i = 1, #(self.slots or {}) do
        self.slots[i]._timeKey = nil
    end
end

--- Enable gates everything; HideCombat ("Hide when not in combat") hides the
--- bar OUT of combat; HideZero (CD-35's `Hide` row, Draw :1348) hides it
--- while the feed carries no cooldown. Dirty-checked; Update refreshes it
--- every pass, which is how the combat transitions self-heal without event
--- wiring -- and how the bar shows again the moment its first entry lands.
--- `_lastCount` is the size of the last feed Update saw, so a visibility
--- refresh from a setter (Init, SetEnabled, SetHideZero) between passes reads
--- the state the bar is actually in.
function D:UpdateVisibility()
    if not self.anchor then return end
    local show = FS.enabled
    if show and FS.hideCombat then
        show = (type(InCombatLockdown) == "function")
            and InCombatLockdown() and true or false
    end
    if show and FS.hideZero and (self._lastCount or 0) <= 0 then
        show = false
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
    -- CD-35 geometry modes + CD-31 Warn
    Vertical = "SetVertical",
    Flip = "SetFlip",
    HideZero = "SetHideZero",
    Warn = "SetWarn",
    Width = "SetWidth",
    Height = "SetHeight",
    MaxTime = "SetMaxTime",
    PowerScale = "SetPowerScale",
    TimeTags = "SetTimeTags",
    IgnoreShort = "SetIgnoreShort",
    BarColor = "SetBarColor",
    BgColor = "SetBgColor",
    Spark = "SetSparkOn",
    -- The FRAME SIZING block's IconSize pair (:1760, def {[0]=false,36}
    -- :1805) and the APPEARANCE "Bar text" colour (:1765, def :1838).
    IconSize = "SetIconSize",
    IconSizeOn = "SetIconSizeOn",
    TextColor = "SetTextColor",
    -- The SPECIFICS icon block (:1716-1719) and the SPLASH block
    -- (:1723-1724), plus the TIME RANGE filters (:1729-1732) and their
    -- `[0]` gates.
    BarAlpha = "SetBarAlpha",
    BarAlphaMax = "SetBarAlphaMax",
    IconTime = "SetIconTime",
    IconTextColor = "SetIconTextColor",
    IconTextColorOn = "SetIconTextColorOn",
    Splash = "SetSplashOn",
    SplashFactor = "SetSplashFactor",
    MinRange = "SetMinRange", MinRangeOn = "SetMinRangeOn",
    MaxRange = "SetMaxRange", MaxRangeOn = "SetMaxRangeOn",
    MinRemaining = "SetMinRemaining",
    MinRemainingOn = "SetMinRemainingOn",
    MaxRemaining = "SetMaxRemaining",
    MaxRemainingOn = "SetMaxRemainingOn",
    Scale = "SetScale",
    Alpha = "SetAlpha",
    GlobalLock = "SetLocked",
    FrameAlpha = "SetGlobalAlpha",
    FrameScale = "SetGlobalScale",
    AltTimeFormat = "SetTimeFormatAlt",
    BarFont = "SetBarFont",
    BarTexture = "SetBarTexture",
    -- The Advanced page's strata row for this bar (the source's
    -- `CooldownStrata`, Forte_Cooldown.lua:1790).
    CooldownStrata = "SetStrata",
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
    Cooldown = { "Enable", "HideCombat", "HideZero", "Vertical", "Flip",
        "Warn", "Width", "Height", "MaxTime",
        "PowerScale", "TimeTags", "IgnoreShort", "BarColor", "BgColor",
        "Spark", "Scale", "Alpha",
        "BarAlpha", "BarAlphaMax", "IconTime", "IconTextColor",
        "IconTextColorOn", "Splash", "SplashFactor",
        "IconSize", "IconSizeOn", "TextColor",
        "MinRange", "MinRangeOn", "MaxRange", "MaxRangeOn",
        "MinRemaining", "MinRemainingOn", "MaxRemaining",
        "MaxRemainingOn",
        "ColorSpell", "ColorPowerup", "ColorItem", "ColorPotion",
        "ColorPet", "ColorInternal", "ColorBuff", "ColorDebuff" },
    General = { "FrameAlpha", "FrameScale", "AltTimeFormat",
        "BarFont", "BarTexture" },
    -- The Advanced page's shared keys (Forte_Options/Pages/Advanced.lua):
    -- the module-prefixed strata row of the source's Advanced category
    -- (`CooldownStrata`, Forte_Cooldown.lua:1790). Shared-module keys ride
    -- the same ApplySettings seam as this module's own.
    Advanced = { "CooldownStrata" },
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
    st:OnChange("Advanced", function(key, value)
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
    local ih = iconSize()
    frame:SetSize(ih, ih)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("CENTER", frame, "CENTER", 0, 0)
    tex:SetSize(ih, ih)

    -- Permanent running spark: NewBar.Update :1156-1160 shows it at
    -- 2.2 x icon size, alpha Spark[1] = 1, whenever Spark[0] -- and Spark
    -- defaults {[0]=true, 1} (:1820), "flags on by default" (PLAN §3.5).
    -- Tint = FixIntensity(category) (:1407 + :1417).
    local spark = frame:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(S.Spark)
    spark:SetBlendMode("ADD")
    spark:SetPoint("CENTER", frame, "CENTER", 0, 0)
    spark:SetSize(ih * S.SparkScale, ih * S.SparkScale)
    spark:SetAlpha(S.SparkAlpha)
    -- The Spark OPTION (S.SparkOn): the running glow is a flag, off hides
    -- it on the whole pool (SetSparkOn) and on freshly built slots.
    if not S.SparkOn then spark:Hide() end

    -- The ATTENTION spark (CD-21/CD-31): the source creates it per bar
    -- (:1100-1103, Spark2, ADD, centred on the icon) and shows it, sized
    -- 2.2*ih*t20, while t20 > 1 (:1408-1415). It is the "you tried to cast
    -- this while it was cooling" flash -- NOT the running spark, and the
    -- source never gates it on Spark[0], so it is built shown-off and the
    -- attention pass owns its visibility.
    local alert = frame:CreateTexture(nil, "OVERLAY")
    alert:SetTexture(S.Spark)
    alert:SetBlendMode("ADD")
    alert:SetPoint("CENTER", frame, "CENTER", 0, 0)
    alert:SetSize(ih * S.AttentionScale, ih * S.AttentionScale)
    alert:Hide()

    -- IconTime text: IconFont = font, size-1, OUTLINE (:1810), anchored
    -- BOTTOMLEFT of the icon (NewBar :1120-1122).
    local timeFS = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    applyFont(timeFS, ICON_FONT_SIZE, ICON_FONT_FLAGS)
    timeFS:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    -- The `IconTime` gate (the row :1718, default on :1835): the source runs
    -- the icon text behind it (:1419), so a slot built while it is off is
    -- born hidden (SetIconTime shows the live pool on the way back).
    if not S.IconTime then timeFS:Hide() end

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

    -- m2 (CodeReview3): the missing `local` wrote the SHARED-ENVIRONMENT
    -- global named `slot` on every pool growth (the reuse branch's local
    -- at the top of the function dies at its branch). Functional, pure
    -- hygiene: a trivially collidable name in the environment every addon
    -- shares.
    local slot = { frame = frame, tex = tex, spark = spark, alert = alert,
                   timeFS = timeFS, chargeFS = chargeFS, seg = seg }
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
    -- A released icon can not be "the spell you just tried to cast" any
    -- more: the attention window leaves with it (the pending request in
    -- self._steal is pruned by name in the same Update pass).
    slot._alertEnd, slot._alertShown = nil, false
    slot.alert:Hide()
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
    -- The icon text colour (:1419-1425): `IconTextColor[0]` on -> the custom
    -- colour, off -> the same FixIntensity tint the spark rides.
    slot.timeFS:SetTextColor(iconTextColor(fr, fg, fb))
    -- The attention spark rides the SAME FixIntensity tint as the running
    -- spark (:1407-1408: r,g,b = FixIntensity(ColorVal(...)) right before the
    -- t20 > 1 branch); it is re-armed by the Warn pass, hidden at rest.
    slot.alert:SetVertexColor(fr, fg, fb)
    slot._alertEnd, slot._alertShown, slot._alertSize = nil, false, nil
    -- The charge number is per-tick state (Update): drop the previous
    -- name's cached text/colour so the first pass always repaints it.
    slot._chargeText, slot._chargeCol = nil, nil
    slot._timeKey = nil                     -- fresh icon: paint the time
    slot._fadeStart = now
    slot._alpha = nil
    self:SpawnSplash(cx, slot._texPath, col, now)
end

--- The source's t15==-1 expiry curve (:1380-1403), shared by spawn and the
--- per-pass update. `t14` is the source's bar visibility (1 at spawn,
--- decaying -1/s to 0 over SplashSeconds, :629-632): icon size =
--- SplashFactor*ih*(1-t14) (:1381; ih = the iconSize() law -- the gate
--- ships off, so = Height, :1364, :1803), the spark rides 2.2x the splash
--- (:1386-87), and the FRAME alpha is t14 itself (:1403; SplashAlpha = 1.0).
function D:_SplashCurve(s, t14)
    local size = S.SplashFactor * iconSize() * (1 - t14)
    -- The original's splashicon is a texture ON the sized bar frame
    -- (:1088); our pool frames centre the icon, so the frame rides the same
    -- size (a 0x0 frame clips its children in some renderers).
    s.frame:SetSize(size, size)
    s.tex:SetSize(size, size)
    local g = size * S.SparkScale
    s.spark:SetSize(g, g)
    s.frame:SetAlpha(S.SplashAlpha * t14)
end

--- Cast splash: the source's t15==-1 expiry visual (:1380-1403) fired on a
--- name's first sighting: the spell icon WHITE with a BLEND draw (the
--- splashicon's vertex colour and blend mode are never set, :1088-89),
--- growing 0 -> SplashFactor x the icon LINEARLY over SplashSeconds
--- (:1381, :1812), with the 2.2x Spark2 ADD glow behind it tinted
--- FixIntensity(category) (:1083-85, :1407, :1418) and the whole frame
--- fading alpha 1 -> 0 linear (:1403). Grow-only pool.
function D:SpawnSplash(cx, texPath, col, now)
    -- The `Splash` gate (:1380 `if s.Splash and t15 == -1`, row :1723,
    -- default on :1811): off, the expiry visual is not spawned at all -- the
    -- pool stays untouched, so a later on needs no repair.
    if not S.SplashOn then return end
    local pool = self.splashPool
    local s
    for i = 1, #pool do
        if not pool[i]._endAt then
            s = pool[i]
            break
        end
    end
    if not s then
        -- Named for dump-tree checks: a visible frame named
        -- ForteXorcistCooldownSplash<n> is a splash on screen.
        local f = CreateFrame("Frame", "ForteXorcistCooldownSplash" .. (#pool + 1), UIParent)
        -- Spark first, icon on top: NewBar creates splashiconspark
        -- (:1083-85) BEFORE splashicon (:1088-89), same OVERLAY layer.
        local sparkTex = f:CreateTexture(nil, "OVERLAY")
        sparkTex:SetTexture(S.Spark)
        sparkTex:SetBlendMode("ADD")
        sparkTex:SetPoint("CENTER", f, "CENTER", 0, 0)
        sparkTex:SetAlpha(S.SparkAlpha)
        local iconTex = f:CreateTexture(nil, "OVERLAY")
        iconTex:SetPoint("CENTER", f, "CENTER", 0, 0)
        s = { frame = f, tex = iconTex, spark = sparkTex }
        pool[#pool + 1] = s
    end
    s.tex:SetTexture(texPath)
    s.tex:SetVertexColor(1, 1, 1, 1)      -- the white, untinted splash icon
    s.spark:SetVertexColor(fixIntensity(col[1], col[2], col[3]))  -- :1407, :1418
    -- The Spark[0] gate (:1385; default {[0]=true} :1820): spark + centre
    -- crop on (:1388), spark off + full texture (:1391).
    if S.SparkOn then
        s.tex:SetTexCoord(S.SplashCrop[1], S.SplashCrop[2],
            S.SplashCrop[1], S.SplashCrop[2])
        s.spark:Show()
    else
        s.tex:SetTexCoord(0, 1, 0, 1)
        s.spark:Hide()
    end
    s.frame:ClearAllPoints()
    -- cx is the icon-centre offset on the bar AXIS, relative to the
    -- bar/anchor centre (both sit on the same screen point: the bar layer is
    -- inset symmetrically); axisOffset lays it out for the geometry mode and
    -- ReflowEffects re-anchors it when the mode or the size moves.
    s._off = cx
    local ox, oy = axisOffset(cx)
    s.frame:SetPoint("CENTER", self.anchor, "CENTER", ox, oy)
    s._endAt = now + S.SplashSeconds
    self:_SplashCurve(s, 1)              -- t = 0: size 0, alpha SplashAlpha
    s.frame:Show()
end

--- End-of-cooldown pulse: the source's SAME t15==-1 expiry curve
--- (:1380-1403) riding the parked icon (CD_EndCooldown parks the bar value
--- at ih/W, :343-351 => the icon centre sits at the bar's LEFT end): the
--- icon at bar size with its 2.2x Spark2 glow tinted FixIntensity(category)
--- (:1407, :1418) at CONSTANT alpha (the source has no alpha wave -- :1403
--- is the only alpha law; PulseCycle 0 switches the wave off), the frame
--- fading alpha 1 -> 0 linear over PulseSeconds. Grow-only pool.
function D:SpawnPulse(name, texPath, col, endAt)
    -- The one source curve this renders is the gated `Splash` visual too
    -- (:1380), so the same gate keeps the ready pulse off the bar. (Both
    -- call sites already popped the _ready entry; a stale one prunes itself.)
    if not S.SplashOn then return end
    -- m8 (CodeReview3): a sealed GetSpellTexture read (the secrecy law's
    -- own case) leaves slot._texPath nil; drawing the ADD-blend spark alone
    -- would fly a lone glow along the bar. A nil-icon pulse therefore runs the
    -- fade law as a spark-less flash; an icon pulse keeps its glow.
    local pool = self.pulsePool
    local s
    -- Reuse a spent entry first, like the splash pool (CodeReview2 n2: the old
    -- `pool[#pool + 1]` was always nil, so every pulse grew the pool forever).
    for i = 1, #pool do
        if not pool[i]._endAt then s = pool[i] break end
    end
    if not s then
        local f = CreateFrame("Frame", nil, UIParent)
        local ih = iconSize()
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetSize(ih, ih)
        tex:SetPoint("CENTER", f, "CENTER", 0, 0)
        local spark = f:CreateTexture(nil, "OVERLAY")
        spark:SetTexture(S.Spark)
        spark:SetBlendMode("ADD")
        spark:SetSize(ih * S.SparkScale, ih * S.SparkScale)
        spark:SetPoint("CENTER", f, "CENTER", 0, 0)
        if not S.SparkOn then spark:Hide() end
        s = { frame = f, tex = tex, spark = spark }
        pool[#pool + 1] = s
    end
    s.tex:SetTexture(texPath)
    s.spark:SetVertexColor(fixIntensity(col[1], col[2], col[3]))  -- :1407, :1418
    if texPath and S.SparkOn then s.spark:Show() else s.spark:Hide() end
    s.frame:ClearAllPoints()
    -- The pulse rides the bar's ORIGIN end (CD_EndCooldown parks the row at
    -- t = 0, so pos(0) is that axis position) on the current geometry axis.
    local off = S.Inset
        + TM.pos(0, S.Width, S.Height, S.Max, S.Loga)
        + S.Height * 0.5 - S.Width * 0.5
    s._off = off
    local ox, oy = axisOffset(off)
    s.frame:SetPoint("CENTER", self.anchor, "CENTER", ox, oy)
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
                s.frame:SetAlpha(S.SplashAlpha * t)  -- bar:SetAlpha(t14), :1403
                if S.PulseCycle > 0 then
                    local wave = (math.sin((endAt - now) / S.PulseCycle * 2 * math.pi) + 1) * 0.5
                    s.spark:SetAlpha(0.3 + 0.7 * wave)
                else
                    -- The source law: the spark rides a constant alpha
                    -- (SetVertexColor(r,g,b) -> alpha 1, :1418); the frame
                    -- alpha t14 modulates it. PulseCycle > 0 keeps the
                    -- legacy wave available as an option.
                    s.spark:SetAlpha(S.SparkAlpha)
                end
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
            -- t14: the source's bar visibility, decaying -1/s clamped
            -- (:629-632); the bar's draw gate is t14 > 0 (:1371).
            local t14 = (endAt - now) / S.SplashSeconds
            if t14 <= 0 then
                s._endAt = nil
                s.frame:Hide()
            else
                self:_SplashCurve(s, t14)
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

--- The identity of an overlap group: its member names in order. CodeReview2
--- n6: the m5 pass left this allocating a `parts` table plus a
--- `table.concat` string per MULTI-MEMBER GROUP per 10 Hz pass. The group
--- lists live in the Display's own `_groupsScratch` pool, so the built
--- string and the names it was built from ride on the list and are reused
--- whenever the membership is unchanged -- the common case, a group sitting
--- still while its icons cross-fade. Only the rebuild (a member joining,
--- leaving, reordering) allocates a string.
local function groupSignature(g)
    local n = #g
    local parts = g._fxParts
    if not parts then
        parts = {}
        g._fxParts = parts
    end
    local same = g._fxSig ~= nil and g._fxSigN == n
    if same then
        for i = 1, n do
            if parts[i] ~= g[i].name then same = false break end
        end
        if same then return g._fxSig end
    end
    for i = 1, n do parts[i] = g[i].name end
    for i = n + 1, #parts do parts[i] = nil end
    local sig = table.concat(parts, "|")
    g._fxSig, g._fxSigN = sig, n
    return sig
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
--- :1404-1406; frame alpha rides the bar visibility, :1402). The two anchor
--- pairs and the TexCoord slice come from the CD-35 helpers, so the slice
--- runs up the bar in Vertical and mirrors in Flip exactly as the source's
--- :1427-1450 branch. The applied values are cached in _segSet*; the CURRENT
--- values are mirrored to _segL/_segR/_segVL/_segV/_segA for the tests.
function D:_SetSegment(slot, leftX, rightX, uvL, uvR, a)
    local seg = slot.seg
    if not seg:IsShown() then seg:Show() end
    if slot._segSetL ~= leftX or slot._segSetR ~= rightX then
        slot._segSetL, slot._segSetR = leftX, rightX
        seg:ClearAllPoints()
        -- Bar coords: the slice spans the axis from leftX to rightX, and the
        -- bar layer is inset (the axis span is Width - 2*Inset in BOTH
        -- orientations, because ApplyBarSize swaps the frame; the original's
        -- bar frame is s.Width wide, :1490).
        local p1, x1, y1, p2, x2, y2 = segmentPoints(leftX, rightX)
        seg:SetPoint(p1, self.bar, p1, x1, y1)
        seg:SetPoint(p2, self.bar, p2, x2, y2)
    end
    if slot._segSetVL ~= uvL or slot._segSetV ~= uvR
        or slot._segSetMode ~= self._geoMode then
        slot._segSetVL, slot._segSetV = uvL, uvR
        slot._segSetMode = self._geoMode
        setSegmentUV(seg, uvL, uvR)
    end
    local col = slot._segCol
    if col and (slot._segSetCol ~= col or slot._segSetA ~= a) then
        slot._segSetCol, slot._segSetA = col, a
        seg:SetVertexColor(col[1], col[2], col[3], a)
    end
end

--- Render one pass. `entries` is the Engine's reused scratch array, sorted
--- soonest-ready first -- the only thing we tag onto it is the transient
--- numeric `.x` the grouping consumes; keep no references to it (the filter's
--- `_draw` view is emptied the moment no gate runs, and is trimmed to the
--- pass's own rows while one does).
function D:Update(entries, now)
    if not self.anchor then return end
    local W, H, Max, Loga = S.Width, S.Height, S.Max, S.Loga
    local n = #entries
    -- The TIME RANGE filters (CD_TimeFilterDuration / CD_TimeFilterRemaining
    -- :488-495; the source marks the filtered row cd[i][21] = 1 at :547 and
    -- draws only `t17 == 0` at :1371). Our slots are name-bound and released
    -- by the "names the feed dropped" pass at the end, so the filter runs
    -- BEFORE that loop by handing the rest of the pass a COMPACTED VIEW of
    -- the feed: the Display's own grow-only scratch of references. A filtered
    -- row then costs no slot, no segment, no group member and no HideZero
    -- count, and its slot releases exactly like a row the engine dropped.
    -- With every gate off -- the shipped default -- the feed is used as it
    -- arrived and the scratch is emptied, so it holds no engine row between
    -- the passes that filter.
    if filtersActive() then
        local draw = self._draw
        local m = 0
        for i = 1, n do
            local e = entries[i]
            local finishAt = e.rechargeEnd or e.endTime
            if passesFilter(e.duration, finishAt - now) then
                m = m + 1
                draw[m] = e
            end
        end
        for i = m + 1, #draw do draw[i] = nil end
        entries, n = draw, m
    elseif self._draw[1] ~= nil then
        for i = 1, #self._draw do self._draw[i] = nil end
    end
    -- The feed size is HideZero's witness (CD-35): the number of rows the
    -- bar is DRAWING (post-filter), recorded before the visibility pass so
    -- the bar shows again on the very pass its first entry lands, with
    -- nothing but this normal feed driving it.
    self._lastCount = n
    -- Enable / Hide-when-out-of-combat / HideZero ride this 10 Hz pass (cheap
    -- and dirty-checked): the bar self-heals on combat transitions. A hidden
    -- bar spends no draw work; the transient splash/pulse timers keep
    -- running so nothing resurfaces when it returns.
    self:UpdateVisibility()
    if not self._shown then
        self:UpdatePulses(now)
        self:UpdateSplashes(now)
        return
    end
    local byName, islot, seen = self._byName, self._islot, self._seen
    wipe(seen)
    local lanes = self._lanes
    if not lanes then lanes = {}; self._lanes = lanes end
    for k in pairs(lanes) do lanes[k] = nil end

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
        -- Anchored on the bar's axis ORIGIN point at pos(t): the original's
        -- `bar.icon:SetPoint("CENTER", bar, "LEFT", t10, 0)` (:1449), whose
        -- LEFT/RIGHT/TOP/BOTTOM choice IS the CD-35 mode (:1427-1450). The
        -- number is always TimelineMath.pos(t) -- the mode only says which
        -- edge of the bar it is measured from and in which direction:
        -- icon centre = origin + pos(t) + ih/2 = t9, the very right edge of
        -- the segment span.
        local point, ox, oy = axisPoint(x)
        -- Overlap lanes: icons whose axis positions fall within one icon width
        -- of an earlier icon (same-cooldown casts, a trap family) step sideways
        -- off the axis instead of hiding each other. The AXIS position stays
        -- true; only the perpendicular offset changes.
        --
        -- m3 (code-review-10): the walk is CAPPED at LANE_MAX. An unbounded
        -- lane count is unbounded geometry -- a dense log-scale tail (a dozen
        -- near-ready icons inside one icon width: a trap burst, the shared
        -- Arcane Shot / Summon Hawk windows) chained lanes 0..11 and drew
        -- icons ~165 px off the axis at H=18, over neighbouring UI. Past the
        -- cap the icons FOLD into the last lane (they overlap each other,
        -- the honest degraded state; the axis position stays true, as it
        -- always is). Max perpendicular reach: LANE_MAX * 0.75 * H = 2.25 * H.
        local lane = 0
        while lanes[lane] and math.abs(x - lanes[lane]) < H do lane = lane + 1 end
        if lane > LANE_MAX then lane = LANE_MAX end
        lanes[lane] = x
        local step = lane * H * 0.75
        if S.Vertical then ox = ox + step else oy = oy + step end
        if slot._cx ~= x or slot._cp ~= point or slot._cl ~= lane then
            slot._cx, slot._cp, slot._cl = x, point, lane
            slot.frame:ClearAllPoints()
            slot.frame:SetPoint(point, self.bar, point, ox, oy)
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
            -- The live path: the Module pops a name in Sweep (entry removed)
            -- and calls OnReady, so a ready name is never in `entries` again.
            -- Its departing slot still knows the texture/colour: pulse here.
            -- (CodeReview2 N1, 2026-11-02 -- the pulse never fired live.)
            local endAt = self._ready[name]
            if endAt and endAt > now then
                local slot = byName[name]
                self._ready[name] = nil
                self:SpawnPulse(name, slot._texPath, slot._col, endAt)
            end
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
        -- CD-31: a failed cast of a spell that is on the bar takes
        -- attention. The stamp rides THIS pass's clock (the source stamps
        -- cd[i][20] = 1 + focustime at the event, :874, and the render pass
        -- decays it -1/s, :528-530 -- the pass clock is the only clock the
        -- draw side reads), and the attention spark is drawn by
        -- _UpdateAttention from it.
        local stealIdx
        for mi = 1, #g do
            if self._steal[g[mi].name] then
                stealIdx = mi
                self._steal[g[mi].name] = nil
                g[mi].slot._alertEnd = now + S.WarnSeconds
                break
            end
        end
        if #g > 1 then
            local sig = groupSignature(g)
            xfSeen[sig] = true
            local st = self:_RotateFocus(sig, #g, now)
            -- ... and the warned icon STEALS the group's cross-fade focus
            -- (CD_FocusTimer, :860-877: the warned bar gets cd[i][15] = 1
            -- (focused) and cd[i][14] = 1 (full visibility) while every other
            -- member of the group is set to 0). phase = CrossfadeSeconds is
            -- this port's frac = 1, so the warned member draws full and the
            -- others 0 -- the source's exact post-steal state -- and the
            -- rotation resumes its hand-off from there.
            if stealIdx then
                st.idx, st.phase = stealIdx, S.CrossfadeSeconds
            end
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
        self:_UpdateAttention(slot, now)
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
    -- The same law for Warn requests whose name left the bar between the
    -- event and this pass (`_steal` is empty in the common case).
    for name in pairs(self._steal) do
        if not byName[name] then self._steal[name] = nil end
    end

    self:UpdatePulses(now)
    self:UpdateSplashes(now)
end

--- CD-21/CD-31: the attention spark of one slot (`bar.icon.attentionspark`,
--- :1408-1415). The source's state is cd[i][20], set to 1 + focustime by
--- CD_FocusTimer (:874) and decayed by the elapsed seconds while > 1
--- (:528-530), so `t20` runs 1.5 -> 1.0 over `focustime = 0.5` s (:32) and the
--- draw pass shows the ADD-blend Spark2 at `2.2*ih*t20` -- a glow that starts
--- a third wider than the running spark and contracts onto the icon -- and
--- hides it the moment t20 reaches 1. `slot._alertEnd` is that t20 window's
--- end, stamped by the group pass from the render clock.
function D:_UpdateAttention(slot, now)
    local endAt = slot._alertEnd
    if endAt then
        -- The source decays cd[i][20] by the ELAPSED SECONDS at 1/s
        -- (:528-530 `cd[i][20] = cd[i][20] - (tim-cd[i][16])`), so `t20 - 1`
        -- IS the seconds left in the focustime window; the `> 1` gate is the
        -- source's own (:528, :1408).
        local t20 = 1 + (endAt - now)
        if t20 > 1 then
            local size = S.AttentionScale * iconSize() * t20   -- :1409
            if slot._alertSize ~= size then
                slot._alertSize = size
                slot.alert:SetSize(size, size)
            end
            if not slot._alertShown then
                slot._alertShown = true
                slot.alert:Show()
            end
            return
        end
        slot._alertEnd = nil
    end
    if slot._alertShown then
        slot._alertShown = false
        slot.alert:Hide()                                  -- :1413
    end
end
