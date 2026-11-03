-- addon/Forte_Timer/UI/Rows.lua
-- FX.Timer.Display: the Spell Timer's row stack, the Classic look. This file
-- is FORKED FROM the dormant seed `addon/Forte_Cooldown/UI/Rows.lua` (the
-- Phase-4 Spell-Timer seed, its own header said so; PLAN §3.6,
-- docs/refs/ref4.png) with the deltas D1-D15 of docs/design-spell-timer.md
-- §5.1 applied. The seed was a copy source only: it never entered the
-- Cooldown TOC, and it is DELETED (2026-11-02) -- this file is the one live
-- row renderer. The seed's structure is
-- kept because it is right for this engine: the row IS its bar, the pools grow
-- and never shrink, every style setter is dirty-checked (the pass runs at
-- 25 Hz), position + lock persist, and its `FX.Cooldown.Display` alias is NOT
-- resurrected -- this file registers `FX.Timer.Display` and nothing else.
--
-- The geometry, with its `Forte_Timer.lua` anchors (design §1.1/§1.2/§5.1):
--   bar 250x14, the icon OUTSIDE the bar (the source's own comment at :1860),
--   bar width = Width - Height - 1 = 235, the icon a 14x14 Button with a 1 px
--   gap, TOPRIGHT->bar TOPLEFT,-1,0 + BOTTOMRIGHT->bar BOTTOMLEFT,-1,0
--   (:1862-1870); x-inset Height+1+Backdrop[6] = 18 (:2322); group width =
--   Width + Backdrop[6]*2 = 256 (:1938); backdrop edge = 3 (:3417, the value
--   that differs from the Cooldown seed's 5); LabelHeight 18 (:3344),
--   SpacingHeight 2 (:3345), Space 2 (:3364); growth UPWARD from the frame's
--   BOTTOM (Expand, :2320-2332, default :3321); row alpha: target/failed rows
--   full, everything else NormalAlpha 0.50 (:2340-2344, :3366); the row
--   background `Interface\PaperDollInfoFrame\UI-Character-Skills-Bar`
--   (:1727) tinted by ColorVal's alpha (:2368); the bar fill Aluminium
--   (Forte_Core.lua:2488); the icon base `Textures\ST` cropped
--   0.133/0.867 (:1692-1694); sparks `Spark`/`Spark2` (:1712, :1690); URW Gothic
--   11 (FX.CLASSIC_FONT, the owner's font ruling PLAN:399-402) replacing the
--   original's bundled GOTHIC 11 (Forte_Core.lua:2509).
--
-- The fill direction is NOT "fixed" (§5.3): the fill is LEFT-anchored and
-- shrinks from the RIGHT -- `SetValue(v)` maps to the bar's 0..1 value, and a
-- StatusBar crops exactly that way; the time text rides the same left edge, so
-- the countdown reads at the shrinking edge. That is the FX look.
--
-- It is a PURE RENDERER: it never reads a unit/aura/cooldown API. It draws the
-- link array `FX.Timer.Rows:Sorted` produced (which points into
-- `FX.Timer.Rows.rows`), plus the numbers in `options`/`skin`. Every setter is
-- dirty-checked; the pools only grow (acquire/hide, never destroy); the
-- per-tick path allocates nothing (PLAN §3.4).
--
-- THE KEY LAW (docs/perf.md §4 fix 2 + 3, the Timeline's own discipline). Every
-- dirty key is a NUMBER: the colour triples compare component-wise, the size
-- and anchor keys compare the layout numbers, and a text is rebuilt only when
-- the identity of its SHOWN value changes (`timeKey` for the time column, the
-- row's own name inputs for the name column). Geometry is touched on a layout
-- change only -- a group box, a bar, a header and the static tick marks keep
-- their anchoring across ticks; the bar spark is the one element that must
-- move every tick and it does.
--
-- Lock/position: its OWN anchor frame (`ForteXorcistTimerAnchor`) and its OWN
-- saved table (FX.db.timer.display) -- the Cooldown Timer owns its anchor
-- (delta D15). `/fx lock|unlock` reaches it through the FX.Settings mirroring
-- in Module.lua; the title is the "you can drag this" affordance and shows only
-- while unlocked.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Timer = FX.Timer or {}

local D = {}
FX.Timer.Display = D

--- The COUNTED SEAMS: how many times per pass the layout and the texts were
--- actually APPLIED. They are the proof of the key law above, asserted by
--- Forte_Timer/tests/test_perf_gates.lua (a steady pass must apply zero
--- anchoring, zero geometry, zero texts; a layout change must move them; the
--- spark must move every pass), in the same pattern
--- `Forte_Timer/Core/Reconcile.lua`'s `counts.reads` is for the aura law.
--- Incremented at the apply sites only, so they cost an add per applied
--- setter, never per inspected row.
D.counts = { anchorGroup = 0, anchorRow = 0, anchorLabel = 0,
    anchorTicks = 0, sizeGroup = 0, geometry = 0, timeText = 0,
    nameText = 0, spark = 0 }

local Laws = FX.Timer.Laws
local Rows = FX.Timer.Rows
local counts = D.counts

-- ------------------------------------------------------- the display keys --
--- The identity of the DISPLAYED time string for `Laws.TimeText` -- the
--- Timeline's law (`Forte_Cooldown/UI/Timeline.lua:312-320`): one whole second
--- for the `m:ss` / `Nh/Nm/Ns` branches, one rounded tenth for the `%.1f`
--- branch. The render pass compares THIS, so `string.format` + `SetText` run
--- only when the shown number changes (docs/perf.md §4 fix 2), not every tick.
--- A key may therefore change more often than the text (a tenth step in the
--- m:ss band never happens; the alt band keys per second, which is finer than
--- its `h`/`m`/`s` steps) -- never less often, which is the only direction a
--- stale label can come from. The `+ 2` keeps every numeric key clear of the
--- two constant-text sentinels, so a row whose `total` arrives later, or whose
--- state crosses REMOVE, repaints.
local TIMEKEY_GONE = -2      -- state > REMOVE: the constant "gone"
local TIMEKEY_EMPTY = -1     -- total == 0: the constant ""
local function timeKey(remaining, total, state, alt)
    if state > Laws.REMOVE then return TIMEKEY_GONE end
    if total == 0 then return TIMEKEY_EMPTY end
    local shown = remaining > 0 and remaining or 0
    if alt or shown >= 60 then return math.floor(shown) + 2 end
    return math.floor(shown * 10 + 0.5) + 2
end

--- The `Laws.NameText` options carrier. One table for the whole module,
--- refilled in full by `NameFor` before every call: the name text is built at
--- most once per row per layout change, so the literal this replaces (one
--- table per row per tick, docs/perf.md §2) is the only thing lost.
local nameOpts = {}

-- ------------------------------------------------------------------- font --
--- The shipped-file validator, the Forte_Hunter/UI/Swing.lua law (CreateFont +
--- SetFont on a throwaway string, accepted only when GetFont returns the file
--- back). Rejection leaves every string on its GameFontHighlightSmall template.
local function validateFontFile(path, size)
    if type(path) ~= "string" or path == "" then return nil end
    local okCreate, fontObj = pcall(CreateFont, path, size)
    if not okCreate or not fontObj then return nil end
    local probe = UIParent:CreateFontString(nil, "OVERLAY")
    if not probe then return nil end
    local okSet = pcall(probe.SetFont, probe, path, size)
    local got = okSet and probe:GetFont()
    probe:Hide()
    if type(got) == "string" and got:lower() == path:lower() then
        return path
    end
    return nil
end

-- ------------------------------------------------------------------- init --
--- Position + lock live in the caller's table (FX.db.timer.display).
function D:Init(options, skin, cfg)
    if self.anchor then
        self.options, self.skin = options, skin
        return
    end
    self.options, self.skin, self.cfg = options, skin, cfg
    self.fontFile = validateFontFile(skin.Font[1], skin.Font[2])
    self.stacksFontFile = validateFontFile(skin.Font[1], skin.Font[2] - 1)

    local f = CreateFrame("Frame", "ForteXorcistTimerAnchor", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(options.groupWidth, options.height)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(fr)
        fr:StopMovingOrSizing()
        self:SavePosition(fr)
    end)

    -- The drag affordance, visible only while unlocked. The title states the
    -- ceiling (design §5.5 / PLAN §7 Phase 4 "state the ceiling in the UI").
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetText("Forte Spell Timers (predicted)")
    title:SetTextColor(1, 1, 1, 1)
    title:SetPoint("BOTTOM", f, "TOP", 0, 2)

    self.anchor, self.title = f, title
    self.groups = {}      -- the group pool (frame + backdrop + label + mark)
    self.rows = {}        -- the bar pool, flat; index -> row table
    self._shown = false
    self:ApplyPosition()
    self:ApplySize()
    f:Hide()
end

--- The stack's own size: the anchor is the group frame's box; its width is the
--- group width so the rows line up with it (D15).
function D:ApplySize()
    if not self.anchor then return end
    local o = self.options
    self.anchor:SetSize(o.groupWidth, o.height)
end

function D:SetSize(w, h)
    -- Before Init there is no geometry to resize: the caller's options table
    -- (which Init adopts verbatim) already carries the numbers, so a no-op is
    -- the complete answer -- the module's stored settings are applied before
    -- the display is built.
    if not self.anchor then return end
    if type(w) == "number" and w > 0 then self.options.width = w end
    if type(h) == "number" and h > 0 then self.options.height = h end
    local o = self.options
    o.barWidth = o.width - o.height - 1
    o.iconSize = o.height
    o.barInset = o.height + 1 + (o.inset or 3)
    o.groupWidth = o.width + (o.inset or 3) * 2
    self:ApplySize()
    -- The geometry caches are numeric now (fix 3): drop them so the next
    -- ApplyRowGeometry re-sizes and re-anchors from the new numbers.
    for i = 1, #self.rows do
        local row = self.rows[i]
        if row then
            row._gBarW, row._gHeight, row._gIcon, row._gIconRight =
                nil, nil, nil, nil
        end
    end
end

function D:SetEnabled(on)
    self._enabled = not not on
    if not self._enabled then self:RenderIdle() end
end

-- ------------------------------------------------------------- position --
function D:ApplyPosition()
    if not self.anchor then return end
    local cfg = self.cfg
    self.anchor:ClearAllPoints()
    self.anchor:SetPoint(cfg.point, UIParent, cfg.relPoint, cfg.x, cfg.y)
end

--- Snapshot the anchor's current anchoring after a native drag.
function D:SavePosition(f)
    f = f or self.anchor
    if not f then return end
    local point, _, relPoint, x, y = f:GetPoint()
    if not point then return end
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y = point, relPoint, x, y
end

function D:Reset()
    -- One source for the first-run placement (Module.DEFAULT_POSITION); the
    -- literal copy is only what a headless unit run, where the module file is
    -- not loaded, falls back to.
    local d = (FX.Timer.Module and FX.Timer.Module.DEFAULT_POSITION)
        or { point = "CENTER", relPoint = "CENTER", x = 261, y = -150 }
    local cfg = self.cfg
    cfg.point, cfg.relPoint, cfg.x, cfg.y = d.point, d.relPoint, d.x, d.y
    self:ApplyPosition()
end

--- Locked = mouse-off (no drag possible) + the title hidden.
function D:SetLocked(locked)
    locked = not not locked
    if self.cfg then self.cfg.locked = locked end
    if not self.anchor then return end
    self.anchor:SetMovable(not locked)
    self.anchor:EnableMouse(not locked)
    if locked then self.title:Hide() else self.title:Show() end
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
--- `TimerStrata`, Forte_Timer.lua:3277, applied by its own
--- `self:SetFrameStrata(FW.Settings.TimerStrata)` at :2619; default
--- `Strata = "MEDIUM"`, Forte_Core.lua:2531). A name outside the eight is
--- ignored: the panel keeps the strata it has.
function D:SetStrata(name)
    local up = strataOrNil(name)
    if not up then return end
    if self.options then self.options.strata = up end
    if self.anchor and self.anchor.SetFrameStrata then
        self.anchor:SetFrameStrata(up)
    end
end

-- ------------------------------------------------------------- the pools --
--- Group i: the per-target box. The backdrop is the instance's Backdrop
--- (Background/Border, tile 16, EDGE 3 -- the Spell Timer's own value, :3414-3417)
--- tinted by NormalBgColor (:2292-2303, :3397), and it carries the label
--- (:2060-2110) and the group's raid mark (:1909-1916).
function D:AcquireGroup(i)
    local g = self.groups[i]
    if g then return g end
    local f = CreateFrame("Frame", nil, self.anchor,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    local o, skin = self.options, self.skin
    f:SetSize(o.groupWidth, o.height)
    if f.SetBackdrop then
        local bd = skin.BackdropEdgeSize
        local ins = o.inset or 3
        f:SetBackdrop({
            bgFile = skin.BackdropBG,
            edgeFile = skin.BackdropEdge,
            tile = skin.BackdropTile,
            tileSize = skin.BackdropTileSize,
            edgeSize = bd,
            insets = { left = ins, right = ins, top = ins, bottom = ins },
        })
    end
    local bg = skin.NormalBgColor
    if f.SetBackdropColor then
        f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4])
        f:SetBackdropBorderColor(bg[1], bg[2], bg[3], bg[4])
    end
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if self.fontFile then
        pcall(label.SetFont, label, skin.LabelFont[1], skin.LabelFont[2])
    end
    label:SetTextColor(1, 1, 1, 1)
    label:SetJustifyH("CENTER")
    local mark = f:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(skin.RaidMark)
    mark:SetAlpha(skin.RaidTargetsAlpha)
    mark:Hide()
    -- `_ax`/`_ay`/`_hy` are the anchoring the box was LAST anchored with, and
    -- `_sizeW`/`_sizeH` the box size, so the pass touches geometry on a layout
    -- change only (docs/perf.md §4 fix 3).
    g = { frame = f, label = label, mark = mark, _key = nil, _bg = nil,
        _labelText = nil, _labelSize = nil, _factor = nil, _ncol = nil,
        _ax = nil, _ay = nil, _hy = nil, _sizeW = nil, _sizeH = nil }
    self.groups[i] = g
    return g
end

--- Bar i: the row. The row IS the progress bar (the seed's law), so the icon,
--- the texts and the spark created on it sit on top, and one row costs one
--- frame. The icon is a 14x14 Button OUTSIDE the bar (the source's comment at
--- :1860), the time text rides the bar's LEFT edge with a 2 px inset and the
--- name is centred (:1878-1896, :1701-1708 -- deltas D1, D3).
function D:AcquireRow(i)
    local row = self.rows[i]
    if row then return row end
    local o, skin = self.options, self.skin
    local bar = CreateFrame("StatusBar", nil, self.anchor,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    bar:SetSize(o.barWidth, o.height)
    bar:SetStatusBarTexture(skin.BarTexture)
    bar:SetMinMaxValues(0, 1)
    -- The row background (:1725-1727): the full-bleed Skills-Bar texture,
    -- tinted by ColorVal's alpha (:2368). Delta D9: BarBackgroundAlpha 0.30
    -- (the seed's BgColor alpha was 0.50) plus the blink law.
    local back = bar:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(bar)
    back:SetTexture(skin.RowBack)
    -- The icon: a Button, 14x14, the ST base cropped 0.133..0.867 (:1686,
    -- :1692-1694). The per-spell texture is written each bind (:2542).
    local icon = CreateFrame("Button", nil, bar)
    icon:SetSize(o.height, o.height)
    if icon.SetNormalTexture then
        icon:SetNormalTexture(skin.IconBase)
        local nt = icon.GetNormalTexture and icon:GetNormalTexture()
        if nt then
            nt:SetTexCoord(skin.IconCrop[1], skin.IconCrop[2],
                skin.IconCrop[3], skin.IconCrop[4])
            icon._tex = nt
        end
    end
    -- The icon spark: Spark2, ADD, centred on the icon, height
    -- vis*Height*2.2 (:1688-1691, :2534).
    local iconSpark = icon:CreateTexture(nil, "OVERLAY")
    iconSpark:SetTexture(skin.IconSpark)
    iconSpark:SetBlendMode("ADD")
    iconSpark:SetPoint("CENTER", icon, "CENTER", 0, 0)
    iconSpark:SetSize(o.height, o.height * skin.SparkFlareFactor)
    -- The stack tag: the icon's BOTTOMRIGHT, the base font at size - 1 with
    -- OUTLINE (:1696-1698, :2467-2471, :3347 -- delta D8).
    local tag = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if self.stacksFontFile then
        pcall(tag.SetFont, tag, skin.Font[1], skin.Font[2] - 1, "OUTLINE")
    end
    tag:SetJustifyH("CENTER")
    tag:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
    tag:SetTextColor(1, 1, 1, 1)
    -- The name, centred on the bar; the time, at the LEFT with a 2 px inset;
    -- the hidden timedummy that measures the time column (D3, D4).
    local nameFS = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local timeFS = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    local dummy = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    for _, fs in ipairs({ nameFS, timeFS, dummy }) do
        if self.fontFile then
            pcall(fs.SetFont, fs, skin.Font[1], skin.Font[2])
        end
    end
    nameFS:SetTextColor(1, 1, 1, 1)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetPoint("CENTER", bar, "CENTER", 0, 0)
    timeFS:SetTextColor(1, 1, 1, skin.TimeAlpha)
    timeFS:SetJustifyH("LEFT")
    timeFS:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, 0)
    timeFS:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 2, 0)
    dummy:SetJustifyH("LEFT")
    dummy:SetPoint("TOPLEFT", bar, "TOPLEFT", 2, 0)
    dummy:Hide()
    -- The mirrored fill (the `Flip` row, :3149/def :3332). The source's bar IS
    -- a frame plus one ARTWORK texture: `SetFlipped` (:1647-1655) anchors that
    -- texture on the RIGHT edge and `SetValue` (:1656-1668) crops it with
    -- `SetTexCoord(1-value, 1, 0, 1)` — the fill grows leftwards from the right
    -- edge. Forever's StatusBar fills in the source's DEFAULT direction only
    -- (no fill-direction API in the pinned catalog), so the flipped law rides
    -- this texture and the default path keeps drawing on the engine bar (the
    -- texture stays hidden). Same mechanism as Forte_Hunter/UI/Swing.lua's fill.
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(skin.BarTexture)
    fill:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    fill:SetSize(0, o.height)
    fill:Hide()
    -- The bar spark (:1711-1714, :2536-2540 -- delta D5, the seed has none).
    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(skin.Spark)
    spark:SetBlendMode("ADD")
    spark:SetSize(o.height, o.height * skin.SparkHeightFactor)
    spark:SetAlpha(skin.SparkAlpha)
    -- The cast slice (:1716-1717, :2421-2464 -- delta D7) and the bar's raid
    -- mark (:1720-1722, :2356/:2360 -- delta D10).
    local castarea = bar:CreateTexture(nil, "OVERLAY")
    castarea:SetBlendMode("ADD")
    castarea:SetAlpha(skin.CastSparkAlpha)
    castarea:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    castarea:Hide()
    local mark = bar:CreateTexture(nil, "OVERLAY")
    mark:SetTexture(skin.RaidMark)
    mark:SetSize(o.height, o.height)
    mark:SetAlpha(skin.RaidTargetsAlpha)
    mark:SetPoint("CENTER", bar, "CENTER", 0, 0)
    mark:Hide()
    -- The predicted marking (§5.5): a 1 px dark notch at the bar's right end.
    local notch = bar:CreateTexture(nil, "OVERLAY")
    notch:SetSize(1, o.height)
    notch:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    notch:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    notch:SetVertexColor(0, 0, 0, 0.65)
    notch:Hide()
    -- The interaction (:1730-1759): left-click prints the duration, shift-click
    -- one-shot ignores the row (state = IGNORE). The right-click filter jump
    -- has no Forever successor (the filter editor is not built, §6 "Not
    -- built"), so it is deliberately unwired.
    local tick = { bar = bar, back = back, icon = icon, iconSpark = iconSpark,
        tag = tag, nameFS = nameFS, timeFS = timeFS, dummy = dummy,
        fill = fill,
        spark = spark, castarea = castarea, mark = mark, notch = notch,
        ticks = {}, _name = nil, _tex = nil, _alpha = nil, _timeKey = nil,
        _text = nil, _tag = nil, _notch = nil, _sparkOn = nil,
        _height = nil, _width = nil,
        -- Numeric dirty keys (docs/perf.md §4 fix 2): the colour triples are
        -- compared component-wise, so no per-tick string key is built.
        _fillR = nil, _fillG = nil, _fillB = nil, _bgA = nil,
        -- The bar direction (`Flip`, :3332) and the width the mirrored fill
        -- carries: a direction change forces the colour re-write (the fill
        -- moves between the engine bar and the ARTWORK texture).
        _flip = nil, _fillW = nil,
        _ncR = nil, _ncG = nil, _ncB = nil, _timeAlt = nil,
        _twWidth = nil, _nwWidth = nil, _tagStacks = nil, _tagOn = nil,
        -- The name text's own inputs (fix 2): the text is rebuilt only when
        -- one of them changes.
        _nName = nil, _nTarget = nil, _nStacks = nil, _nId = nil,
        _nSpell = nil, _nShowID = nil, _nShowStacks = nil,
        -- Geometry: the sizes the row was sized with (`_g*`) and the anchoring
        -- it carries (`_ap` the group frame, `_ax`/`_ay` the offset) -- fix 3.
        _gBarW = nil, _gHeight = nil, _gIcon = nil, _gIconRight = nil,
        _ap = nil, _ax = nil, _ay = nil,
        -- The tick-mark layout the marks are anchored for (fix 3), plus the
        -- bar direction the layout was mirrored for (the Flip row, :3332).
        _tkEvery = nil, _tkMax = nil, _tkBarW = nil, _tkHeight = nil,
        _tkCount = nil, _tkFlip = nil }
    icon:SetScript("OnClick", function(_, button)
        local r = tick._row
        if not r then return end
        if button == "RightButton" then return end
        if IsShiftKeyDown and IsShiftKeyDown() then
            r.state = Laws.IGNORE
            return
        end
        FX.Print(string.format("%s: %.1fs", tostring(r.name),
            math.max(0, r.expireAt - GetTime())))
    end)
    self.rows[i] = tick
    return tick
end

--- Tick marks: `Spark` textures 7x21 (Height*0.5, Height*1.5, :1613-1627 with
--- the sizes at :1621-1622 -- delta D6, the seed has none), spaced
--- `tickEvery*haste / maxTime * width` from the data's `tick` schedule
--- (DISPLAY ONLY: real tick detection is log-only and the log is closed, §2).
function D:AcquireTick(row, i)
    local t = row.ticks[i]
    if t then return t end
    local skin = self.skin
    t = row.bar:CreateTexture(nil, "OVERLAY")
    t:SetTexture(skin.Spark)
    t:SetBlendMode("ADD")
    t:SetAlpha(0.5)
    row.ticks[i] = t
    return t
end

-- ------------------------------------------------------------------ render --
local function nearEq(a, b)
    return a ~= nil and b ~= nil and math.abs(a - b) < 0.01
end

--- Size/anchor one row to the live geometry, dirty-checked (the `_g*` fields
--- cache the numbers it was last built with — compared numerically, never
--- stringified: docs/perf.md §4 fix 2).
function D:ApplyRowGeometry(row, o, skin, vis)
    if row._gBarW ~= o.barWidth or row._gHeight ~= o.height
        or row._gIcon ~= o.iconSize or row._gIconRight ~= o.iconRight then
        row._gBarW, row._gHeight = o.barWidth, o.height
        row._gIcon, row._gIconRight = o.iconSize, o.iconRight
        counts.geometry = counts.geometry + 1
        row.bar:SetSize(o.barWidth, o.height)
        row.icon:SetSize(o.iconSize, o.iconSize)
        row.icon:ClearAllPoints()
        -- The icon is placed OUTSIDE the bar (:1862-1870): TOPRIGHT -> bar
        -- TOPLEFT,-1,0 and BOTTOMRIGHT -> bar BOTTOMLEFT,-1,0 (the icon's
        -- height is the bar's, so the pair squares it up), the bar x-inset
        -- Height+1+Backdrop[6] = 18 (:2322).
        if o.iconRight then
            row.icon:SetPoint("TOPLEFT", row.bar, "TOPRIGHT", 1, 0)
            row.icon:SetPoint("BOTTOMLEFT", row.bar, "BOTTOMRIGHT", 1, 0)
        else
            row.icon:SetPoint("TOPRIGHT", row.bar, "TOPLEFT", -1, 0)
            row.icon:SetPoint("BOTTOMRIGHT", row.bar, "BOTTOMLEFT", -1, 0)
        end
        row.iconSpark:SetSize(o.iconSize, o.height * skin.SparkFlareFactor)
        row.spark:SetSize(o.height, o.height * skin.SparkHeightFactor)
        row.mark:SetSize(o.height, o.height)
        -- The mirrored fill rides the bar's height (its width is the fill
        -- law in BindRow); a geometry change drops its cached width.
        row.fill:SetHeight(o.height)
        row._fillW = nil
        row.nameFS:SetHeight(o.height)
        for i = 1, #row.ticks do
            row.ticks[i]:SetSize(o.height * skin.TickWidthFactor,
                o.height * skin.TickHeightFactor)
        end
    end
    if not nearEq(row._height, o.height * vis) then
        row._height = o.height * vis
        row.bar:SetHeight(o.height * vis)
        row.fill:SetHeight(o.height * vis)
        row._fillW = nil
    end
    if row._width ~= o.barWidth then
        row._width = o.barWidth
        row.bar:SetWidth(o.barWidth)
    end
end

--- One render pass. `links` is `FX.Timer.Rows:Sorted`'s reused array (entries
--- { rowIndex, groupKey, drawExpireAt, alpha, hiddenSince, maxTime }); `now` is
--- GetTime(), read here once. The pass allocates nothing per row: groups and
--- rows are acquired from the pools, everything past the live count is hidden.
function D:Update(links, n, options, skin)
    if not self.anchor then return 0 end
    local o = options or self.options
    local s = skin or self.skin
    local S = FX.Timer.Skin
    n = n or 0
    local now = GetTime()
    if not o.enable or o.hide then
        self:RenderIdle()
        return 0
    end
    if not self._shown then
        self._shown = true
        self.anchor:Show()
    end

    -- Pass A: collapse the sorted array into group runs, applying the alpha
    -- law (:2340-2344): target/failed rows full, the rest NormalAlpha.
    local runs = self._runs
    if not runs then runs = {} self._runs = runs end
    local ng, lastKey = 0, nil
    for k = 1, n do
        local link = links[k]
        local vis = link[4]
        local row = vis > 0 and Rows.rows[link[1]]
        if row then
            local key = link[2]
            if key ~= lastKey then
                ng = ng + 1
                local g = runs[ng]
                if not g then g = { links = {}, slot = {} } runs[ng] = g end
                g.key, g.count, g.alpha, g.raidMark = key, 0, 0, 0
                lastKey = key
            end
            local g = runs[ng]
            g.count = g.count + 1
            g.links[g.count] = link
            local alpha = vis * ((row.state > Laws.REMOVE)
                and 1 or (o.normalAlpha or S.NormalAlpha))
            if alpha > g.alpha then g.alpha = alpha end
            if (row.raidMark or 0) > g.raidMark then g.raidMark = row.raidMark end
        end
    end

    -- Pass B: draw the runs, cascading UPWARD from the frame's BOTTOM
    -- (`Expand`, :2320-2332). A group's box is `height*count +
    -- space*(count-1)` plus `LabelHeight` 18 (:3344); groups are separated by
    -- `SpacingHeight` 2 (:3345); the bars sit inside the box at the x-inset
    -- `Height + 1 + Backdrop[6]` = 18 (:2322).
    local y, ri = 0, 0
    for gi = 1, ng do
        local run = runs[gi]
        local g = self:AcquireGroup(gi)
        local labelled = o.label ~= false and o.showTarget ~= false
            and run.key > Laws.PRIOR_NONE
        local h = run.count * o.height
            + math.max(0, run.count - 1) * o.space
            + (labelled and o.labelHeight or 0)
        ri = ri + run.count - run.count
        for j = 1, run.count do
            ri = ri + 1
            run.slot[j] = self:AcquireRow(ri)
        end

        if g._sizeW ~= o.groupWidth or g._sizeH ~= h then
            g._sizeW, g._sizeH = o.groupWidth, h
            counts.sizeGroup = counts.sizeGroup + 1
            g.frame:SetSize(o.groupWidth, h)
        end
        -- The box rides the anchor's BOTTOMLEFT at a y that ONLY a layout
        -- change moves (the cascade height, the group width): re-anchor on
        -- change, not per tick (docs/perf.md §4 fix 3). The anchor frame's own
        -- move/resize needs no re-anchoring here -- an anchored child tracks
        -- its parent.
        if g._ax ~= 0 or g._ay ~= y then
            g._ax, g._ay = 0, y
            counts.anchorGroup = counts.anchorGroup + 1
            g.frame:ClearAllPoints()
            g.frame:SetPoint("BOTTOMLEFT", self.anchor, "BOTTOMLEFT", 0, y)
        end
        if not g.frame:IsShown() then g.frame:Show() end
        if g._alpha ~= run.alpha then
            g._alpha = run.alpha
            g.frame:SetAlpha(run.alpha)
        end

        -- the group label = the target name, above the box (:2060-2110); the
        -- sentinel groups (`self`, `server`) have none (:2058, :2214-2222).
        local label = g.label
        if labelled then
            -- The label is the TARGET NAME (the run's key is the group id, the
            -- name is what a player reads).
            local first = Rows.rows[run.links[1][1]]
            local text = (first and first.targetKey) or run.key
            if g._labelText ~= text then
                g._labelText = text
                label:SetText(tostring(text))
            end
            if not label:IsShown() then label:Show() end
            -- The header rides INSIDE the box's reserved LabelHeight strip
            -- (the cascade law, :2086-2099: the label is drawn at the
            -- baroffset the bars then stack away from, so it never leaves
            -- the box). Its BOTTOM rides the bars' stack top `h -
            -- LabelHeight`, so the header sits in the gap directly above
            -- the group's own topmost bar and the spacingHeight gap of the
            -- next box stays clear — an OUTSIDE anchoring (BOTTOM->TOP)
            -- lifted the header LabelHeight above its reserved strip and
            -- overprinted the neighbouring group's first bar (measured in
            -- docs/media/sim/fx_timer_rows.png 2026-11-02).
            -- `headerY` is the whole layout input, so the pair is rebuilt on
            -- a layout change only (docs/perf.md §4 fix 3).
            local headerY = h - o.labelHeight
            if g._hy ~= headerY then
                g._hy = headerY
                counts.anchorLabel = counts.anchorLabel + 1
                label:ClearAllPoints()
                label:SetPoint("BOTTOMLEFT", g.frame, "BOTTOMLEFT", 0, headerY)
                label:SetPoint("BOTTOMRIGHT", g.frame, "BOTTOMRIGHT", 0,
                    headerY)
            end
        elseif label:IsShown() then
            label:Hide()
        end

        -- the group's raid mark: the highest among its rows (:1909-1916,
        -- :2351-2364).
        local coords = s.RaidMarkCoords[run.raidMark]
        if g._mark ~= run.raidMark then
            g._mark = run.raidMark
            if coords then
                g.mark:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
            end
        end
        if coords then
            if not g.mark:IsShown() then g.mark:Show() end
        elseif g.mark:IsShown() then
            g.mark:Hide()
        end

        -- the smart space (:2489-2495, :2510, D4): the time column is as wide
        -- as the widest time string in the group, so the names centre on the
        -- remaining bar. Texts first (dirty-checked), measured, then widths.
        -- Both texts ride a NUMERIC key (docs/perf.md §4 fix 2): the
        -- `string.format` inside `Laws.TimeText` and the `NameText` concats
        -- run only when the SHOWN value changes, not every 25 Hz tick.
        local usewidth = 0
        for j = 1, run.count do
            local r = run.slot[j]
            local row = Rows.rows[run.links[j][1]]
            local remaining = (row.drawExpireAt or row.expireAt) - now
            local tKey = timeKey(remaining, row.total, row.state,
                o.altTimeFormat)
            if r._timeKey ~= tKey or r._timeAlt ~= o.altTimeFormat then
                r._timeKey, r._timeAlt = tKey, o.altTimeFormat
                counts.timeText = counts.timeText + 1
                local text = Laws.TimeText(remaining, row.total, row.state,
                    o.altTimeFormat)
                r.timeFS:SetText(text)
                r.dummy:SetText(text)
            end
            if r._nName ~= row.name or r._nTarget ~= row.targetKey
                or r._nStacks ~= row.stacks or r._nId ~= row.groupKey
                or r._nSpell ~= o.spell or r._nShowID ~= o.showID
                or r._nShowStacks ~= o.showStacks then
                r._nName, r._nTarget = row.name, row.targetKey
                r._nStacks, r._nId = row.stacks, row.groupKey
                r._nSpell, r._nShowID, r._nShowStacks = o.spell, o.showID,
                    o.showStacks
                local nameText = self:NameFor(row, o)
                r._text = nameText
                counts.nameText = counts.nameText + 1
                r.nameFS:SetText(nameText)
            end
            local w = r.dummy:GetWidth()
            if w and w > usewidth then usewidth = w end
        end
        if o.smartSpace == false then usewidth = 0 end

        local barOffset = 0
        for j = 1, run.count do
            self:BindRow(run.links[j], run.slot[j], g, o, s, now, barOffset,
                usewidth)
            barOffset = barOffset + o.height + o.space
        end
        y = y + h + o.spacingHeight
    end

    -- rows/groups past what is live: hidden, and only when actually shown
    for i = ri + 1, #self.rows do
        local row = self.rows[i]
        if row.bar:IsShown() then row.bar:Hide() end
    end
    for i = ng + 1, #self.groups do
        local g = self.groups[i]
        if g.frame:IsShown() then g.frame:Hide() end
        if g.label:IsShown() then g.label:Hide() end
    end
    self.anchor:SetSize(o.groupWidth,
        math.max(o.height, y - o.spacingHeight))
    return ri
end

--- The name a row carries (:1878-1884, :2391-2395): the target name, the spell
--- name with ShowSpellNames, with the #id prefix and the (stacks) suffix
--- (:2517-2523). The suffix rides ShowStacks: the source draws it off the
--- row's stacks unconditionally (the option did not exist there); the port's
--- page ships the switch, and off means NO suffix.
function D:NameFor(row, o)
    local base = row.name
    if not o.spell and row.targetKey ~= "none"
        and row.targetKey ~= "server" and row.targetKey ~= "self" then
        base = row.targetKey
    end
    -- The shared carrier, refilled in FULL (every field the law reads) before
    -- the call, so no per-call table literal rides the render pass.
    local opts = nameOpts
    opts.spell = o.spell
    opts.showID = o.showID
    opts.id = row.groupKey
    opts.maxId = nil
    opts.stacks = (o.showStacks ~= false) and row.stacks
    return Laws.NameText(base, row.name, opts)
end

--- One live row: geometry, colours, fill, texts, icon, spark, slice, mark,
--- ticks. Every setter dirty-checked.
function D:BindRow(link, r, g, o, s, now, barOffset, usewidth)
    local row = Rows.rows[link[1]]
    if not r.bar:IsShown() then r.bar:Show() end
    self:ApplyRowGeometry(r, o, s, link[4])
    -- The row x-inset: Height+1+Backdrop[6] (:2322), plus the page's extra
    -- x-offset of your own rows (the `none` key, the self/no-target law
    -- §3.3) and of the rows riding on your CURRENT target. The source has
    -- one shared inset law; the per-unit extra is the port's own, applied
    -- here and nowhere else. BOTH halves are layout numbers, never time, so
    -- the bar keeps its anchoring across ticks and is re-anchored only when
    -- the inset, the cascade slot or the owning group box changes (fix 3).
    local extra = (row.targetKey == "none") and (o.offsetSelf or 0)
        or ((row.targetKey == "target") and (o.offsetTarget or 0) or 0)
    local ax = o.barInset + extra
    if r._ap ~= g.frame or r._ax ~= ax or r._ay ~= barOffset then
        r._ap, r._ax, r._ay = g.frame, ax, barOffset
        counts.anchorRow = counts.anchorRow + 1
        r.bar:ClearAllPoints()
        r.bar:SetPoint("BOTTOMLEFT", g.frame, "BOTTOMLEFT", ax, barOffset)
    end

    -- the colours (:2366-2369): ColorVal decides once, the fill takes the
    -- triple, the row background takes the alpha. The TEXT is NormalColor
    -- (:3396; the time :1856, the name :2528), de-saturated by FixIntensity
    -- (:2369, Forte_Core.lua:796-800) so a picked colour stays legible.
    -- Every comparison is component-wise NUMERIC (docs/perf.md §4 fix 2): the
    -- stringified triples this replaces were the panel's largest allocator.
    local total = row.total
    local remaining = (row.drawExpireAt or row.expireAt) - now
    local fillR, fillG, fillB, bgA = Laws.ColorVal(remaining, total,
        row.state, row.kind, s, o)
    -- The bar direction (`Flip`, :3149/def :3332): a direction change IS a
    -- colour change, because the fill moves between the engine StatusBar and
    -- the mirrored ARTWORK texture.
    local flipOn = o.flip and true or false
    local fillChanged = r._fillR ~= fillR or r._fillG ~= fillG
        or r._fillB ~= fillB or r._flip ~= flipOn
    if fillChanged then
        r._fillR, r._fillG, r._fillB = fillR, fillG, fillB
        r._flip = flipOn
        r._fillW = nil
        if flipOn then
            r.bar:SetStatusBarColor(0, 0, 0, 0)
            r.fill:SetVertexColor(fillR, fillG, fillB, 1)
        else
            r.bar:SetStatusBarColor(fillR, fillG, fillB, 1)
        end
    end
    if fillChanged or r._bgA ~= bgA then
        r._bgA = bgA
        r.back:SetVertexColor(fillR, fillG, fillB, bgA)
    end
    local nc = s.NormalColor
    if r._ncR ~= nc[1] or r._ncG ~= nc[2] or r._ncB ~= nc[3] then
        r._ncR, r._ncG, r._ncB = nc[1], nc[2], nc[3]
        local nr, ng, nb = Laws.FixIntensity(nc[1], nc[2], nc[3])
        r.nameFS:SetTextColor(nr, ng, nb, 1)
        r.timeFS:SetTextColor(nc[1], nc[2], nc[3], s.TimeAlpha)
    end

    -- the fill: the smoothed drawn-expire time over the compressed scale.
    -- SetValue(v) on the bar crops its LEFT-anchored fill to v, so the fill
    -- shrinks from the RIGHT: the direction law of §5.3, not a fix.
    local barval = Laws.BarVal(row.drawExpireAt, now, row.maxTime)
    if flipOn then
        -- Flipped (the source's flipped SetValue, :1656-1668): the fill rides
        -- the bar's RIGHT edge and crops its own left, `TexCoord(1-v,1,0,1)`.
        local fw = barval * o.barWidth
        if not r.fill:IsShown() then r.fill:Show() end
        if r._fillW ~= fw then
            r._fillW = fw
            r.fill:SetSize(fw, r._height or o.height)
            r.fill:SetTexCoord(1 - barval, 1, 0, 1)
        end
    else
        if r.fill:IsShown() then r.fill:Hide() end
        r.bar:SetValue(barval)
    end

    -- widths from the smart space (:2391, :2510).
    if r._twWidth ~= usewidth then
        r._twWidth = usewidth
        r.timeFS:SetWidth(usewidth)
    end
    local nameWidth = math.max(1, o.barWidth - 2 * usewidth - 4)
    if r._nwWidth ~= nameWidth then
        r._nwWidth = nameWidth
        r.nameFS:SetWidth(nameWidth)
    end

    -- the stacks tag on the icon's BOTTOMRIGHT (:2467-2471, D8). The number
    -- is the key; `tostring` runs on a change (fix 2).
    if r._tagStacks ~= row.stacks or r._tagOn ~= o.iconStacks then
        r._tagStacks, r._tagOn = row.stacks, o.iconStacks
        local tag = (o.iconStacks and row.stacks and row.stacks ~= 0)
            and tostring(row.stacks) or ""
        if r._tag ~= tag then
            r._tag = tag
            r.tag:SetText(tag)
        end
    end

    -- the icon texture, written each bind (:2542).
    local tex = row._iconTex
    if tex == nil then
        local texture
        local ok = pcall(function()
            texture = C_Spell and C_Spell.GetSpellTexture
                and C_Spell.GetSpellTexture(row.name)
        end)
        tex = (ok and FX.Compat.PlainOrNil(texture)) or false
        row._iconTex = tex
    end
    if r._tex ~= tex then
        r._tex = tex
        if r.icon._tex and tex then r.icon._tex:SetTexture(tex) end
    end

    -- the spark at barval*width from the bar's left edge (:2536-2540, D5).
    local sparkOn = o.spark ~= false and barval > 0
    if r._sparkOn ~= sparkOn then
        r._sparkOn = sparkOn
        if sparkOn then r.spark:Show() else r.spark:Hide() end
    end
    if sparkOn then
        counts.spark = counts.spark + 1
        r.spark:ClearAllPoints()
        -- The spark rides the fill's live edge; a flipped bar's edge is the
        -- mirrored one (:2536-2540: `(1-barval)*width` when `bar.flipped`).
        r.spark:SetPoint("CENTER", r.bar, "LEFT",
            (flipOn and (1 - barval) or barval) * o.barWidth, 0)
    end

    -- the predicted marking (§5.5): a 1 px dark notch at the bar's RIGHT end
    -- (the far end of the left-anchored fill) marks a row the addon has not
    -- seen land; an anchored row draws without it.
    local notchOn = (o.markPredicted ~= false)
        and (row.predicted and true or false)
    if r._notch ~= notchOn then
        r._notch = notchOn
        if notchOn then r.notch:Show() else r.notch:Hide() end
    end

    -- the cast slice (:1716-1717, :2421-2464, D7): the ADD overlay over the
    -- bar's first `castMs / (maxTime*1000)` of width -- the window the design
    -- leaves to the GCD, since the cast event has already ended by SENT.
    local castFrac = (row.castMs and row.castMs > 0 and row.maxTime > 0)
        and math.min(1, (row.castMs / 1000) / row.maxTime)
    if castFrac and castFrac > 0 and barval > 0 then
        r.castarea:SetTexture(s.Spark)
        r.castarea:SetWidth(math.max(1, castFrac * o.barWidth))
        r.castarea:SetHeight(o.height)
        if not r.castarea:IsShown() then r.castarea:Show() end
    elseif r.castarea:IsShown() then
        r.castarea:Hide()
    end

    -- the per-bar raid mark, drawn only when the group label is off
    -- (:2351-2364).
    local markCoords = s.RaidMarkCoords[row.raidMark or 0]
    if markCoords and (o.label == false or o.showTarget == false) then
        if r._barMark ~= row.raidMark then
            r._barMark = row.raidMark
            r.mark:SetTexCoord(markCoords[1], markCoords[2], markCoords[3],
                markCoords[4])
        end
        if not r.mark:IsShown() then r.mark:Show() end
    elseif r.mark:IsShown() then
        r.mark:Hide()
    end

    -- the tick marks (:1613-1627, D6): `Spark` textures 7x21 (Height*0.5,
    -- Height*1.5, :1621-1622) spaced `tickEvery / maxTime * width` apart,
    -- DISPLAY ONLY from the data's `tick` schedule -- real tick detection is
    -- log-only and the log is closed (§2).
    local every = row.tickEvery
    if o.ticks and every and every > 0 and row.maxTime > 0 then
        local count = math.min(12, math.floor(row.maxTime / every))
        -- The marks are STATIC for a row: their spacing is the data's
        -- schedule over the row's scale, the size is the row's geometry. The
        -- layout is rebuilt when one of those changes, not every tick; the
        -- show/hide pass below is what keeps them visible (fix 3). The bar
        -- direction joins the layout key: a flipped bar mirrors every mark
        -- (`w - dist`, the source's :1797/:1806).
        if r._tkEvery ~= every or r._tkMax ~= row.maxTime
            or r._tkBarW ~= o.barWidth or r._tkHeight ~= o.height
            or r._tkCount ~= count or r._tkFlip ~= flipOn then
            r._tkEvery, r._tkMax = every, row.maxTime
            r._tkBarW, r._tkHeight, r._tkCount = o.barWidth, o.height, count
            r._tkFlip = flipOn
            counts.anchorTicks = counts.anchorTicks + count
            for t = 1, count do
                local tk = self:AcquireTick(r, t)
                tk:SetSize(o.height * s.TickWidthFactor,
                    o.height * s.TickHeightFactor)
                tk:ClearAllPoints()
                local frac = t * every / row.maxTime
                tk:SetPoint("CENTER", r.bar, "LEFT",
                    (flipOn and (1 - frac) or frac) * o.barWidth, 0)
            end
        end
        -- `TicksNext` (:3182, def true :3404) shows ONE mark: the next tick
        -- of the schedule that is still inside the remaining fill -- the
        -- source's `dist = (ceil(barval/interval) - 1) * interval` (:1775-1791),
        -- i.e. the schedule step closest to the fill's live edge. Off, every
        -- mark of the row's schedule rides the bar (the port's D6 law).
        local first, last = 1, count
        if o.ticksNext then
            local nextT = (barval > 0) and math.floor(barval * row.maxTime
                / every) or 0
            if nextT > count then nextT = count end
            first, last = nextT, nextT
        end
        for t = first, last do
            local tk = r.ticks[t]
            if tk and not tk:IsShown() then tk:Show() end
        end
        for t = 1, #r.ticks do
            if (t < first or t > last) and r.ticks[t]:IsShown() then
                r.ticks[t]:Hide()
            end
        end
    else
        for t = 1, #r.ticks do
            if r.ticks[t]:IsShown() then r.ticks[t]:Hide() end
        end
    end

    r._row = row
end

--- The idle state: everything hidden, no per-frame work.
function D:RenderIdle()
    if self._shown then
        self._shown = false
        if self.anchor then self.anchor:Hide() end
    end
    if self.rows then
        for i = 1, #self.rows do
            local row = self.rows[i]
            if row.bar:IsShown() then row.bar:Hide() end
        end
    end
    if self.groups then
        for i = 1, #self.groups do
            local g = self.groups[i]
            if g.frame:IsShown() then g.frame:Hide() end
            if g.label:IsShown() then g.label:Hide() end
        end
    end
end

function D:StatusLine()
    if not self.anchor then
        return "Spell Timers: not built"
    end
    local o = self.options
    return string.format(
        "Spell Timers: %dx%d bar %d icon %d inset %d | %s | %s | %s",
        o.groupWidth, o.height, o.barWidth, o.iconSize, o.barInset,
        o.label and "labels on" or "labels off",
        o.flip and "flipped" or "left-to-right",
        (self.cfg and self.cfg.locked) and "locked" or "unlocked")
end
