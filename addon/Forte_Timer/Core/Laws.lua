-- addon/Forte_Timer/Core/Laws.lua
-- FX.Timer.Laws: the numbers, the enums and the frame-free laws of the Spell
-- Timer. Every constant here is the ORIGINAL's, with its `Forte_Timer.lua` /
-- `Forte_Core.lua` anchor (docs/design-spell-timer.md §1, §3.5); the numbers
-- are the design, so they are tested (tests/test_laws.lua) and every consumer
-- reads them off this one table. Zero game API, zero frames: this file is pure
-- data + pure functions, runnable under luajit as well as in the sim.
--
-- v1 scope (owner ruling, PLAN.md:549 / §7 Phase 4): the panel shows
-- **own-cast predictions** only. Nothing here is a live read: Rows holds our
-- own numbers; `Core/Reconcile.lua` is the only file that touches an aura API,
-- and it runs out of combat only.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
FX.Timer = FX.Timer or {}

local Laws = {}
FX.Timer.Laws = Laws

-- =========================================================== the laws table --
-- The §3.5 table, verbatim. MAXLAG / BUFF_DELAY are the reconciliation law
-- (the quotes PLAN Phase 4 asks for); SMOOTH / FADE / FAIL / BLINK / MAXTIME
-- are the display law.
Laws.MAXLAG        = 1.00   -- :33  "lower is better, over this and weird things happen"
Laws.BUFF_DELAY    = 4.0    -- :69  "absolute maximum time before checking if a (de)buff is gone"
Laws.SETTLE        = 0.2    -- Forte_Casting.lua:518  a cast's effect is deferred, never inserted on the event
Laws.CANCEL_SETTLE = 0.5     -- Forte_Casting.lua:344  a fail/interrupt settles for this long first
Laws.QUEUE_FLUSH   = 3.0    -- Forte_Casting.lua:602-611 an unfired cast record is garbage after this
Laws.SMOOTH        = 5      -- :3293 FW.Default.TimerSmooth (option range 1..20, :3278)
Laws.FADE          = 1.0     -- :3339 FadeTime
Laws.FAIL          = 2.0     -- :3338 FailTime
Laws.FADE_SPEED    = 0.5     -- :3290 TimerFadeSpeed, the instant-fade addend
Laws.BLINK         = 3.0     -- :3335 Blink = {[0]=true, 3}
Laws.MAXTIME       = 30      -- :3358 MaxTime = {[0]=true, 30}
Laws.HIDE_TIME     = 2       -- :3337 HideTime (the HideLonger fade-in back)
Laws.TICK_LIFE     = 0.3     -- :2376-2387 the spark flare's decay window; :3340 Ticks = {true,0.3}
Laws.SPARK_DAMAGE  = 1.5     -- :3410 SparkDamage = {true,1.5}

-- The lifetime enums, VALUES VERBATIM (:35-40). The comparisons in the state
-- machine (`state <= NORMAL`, `state > REMOVE`) depend on these exact numbers;
-- spec ST-12's 0..5 was refuted by the source (design §1.11).
Laws.IGNORE         = -1
Laws.NORMAL         = 0
Laws.FADING_INSTANT = 1
Laws.FADING         = 2
Laws.REMOVE         = 3
Laws.FAILED         = 4

-- The self / no-target group sentinels (:49-53, the PRIOR_* band the sort keys
-- on so "sections for self / target / others" fall out of the sort, §1.4).
Laws.PRIOR_NONE        = 0
Laws.PRIOR_COOLDOWN    = -1
Laws.PRIOR_DEBUFF      = -2
Laws.PRIOR_SELF_DEBUFF = -3
Laws.PRIOR_POWERUP     = -4

-- The seven main spell types (:474-481), the colour + filter rows key on them.
Laws.TYPE = {
    DEFAULT = 1, CHANNEL = 2, CROWD = 3, COOLDOWN = 4,
    SELF_BUFF = 5, SELF_DEBUFF = 6, ENCHANT = 7,
}

--- The colour row a spell type draws with (the `t21` group key of the
--- original's ColorVal call, :2366 / :3374-3394).
Laws.COLOR_KEY = {
    SelfBuff     = "SelfBuff",
    SelfDebuff   = "SelfDebuff",
    TargetDebuff = "TargetDebuff",
    Crowds       = "Crowd",
    Cooldown     = "Cooldown",
    Channel      = "Channel",
    Enchant      = "Enchant",
    Default      = "Default",
    Heal         = "Heal",
    Buff         = "Buff",
    Curse        = "Curse",
    Bane         = "Bane",
    Pet          = "Pet",
}

--- Types that fade INSTANTLY at expiry (the original's DRAIN / DEBUFF /
--- POWERUP / SELF_DEBUFF set, :1067 / :1071). v1's type names map onto it.
Laws.INSTANT_FADE = { SelfDebuff = true, TargetDebuff = true, Cooldown = true,
    Channel = true }

-- ================================================================ geometry --
-- The original's `FW.InstanceDefault.Timer` (:3312-3418) in the shape
-- Forte_Cooldown/UI/Rows.lua's ClassicSkin uses, with the deltas D1-D15 of
-- docs/design-spell-timer.md §5.1 applied. `Textures`/`Font` ride Forte_Core.
local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"
FX.CLASSIC_FONT = FX.CLASSIC_FONT
    or "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"
local FONT_SIZE = 11                     -- FW.Default.Font[2] (GOTHIC 11, Forte_Core.lua:2509)

FX.Timer.Skin = {
    -- ---- the row + stack numbers (§1.1) --------------------------------
    Width       = 250,   -- :3365  row (bar) width
    Height      = 14,    -- :3363  row height
    Space       = 2,     -- :3364  gap between bars inside a group
    SpacingHeight = 2,   -- :3345  gap between groups
    LabelHeight = 18,    -- :3344  group label height
    -- Backdrop = { Background, Border, tile=false, 16, 5, 3 } (:3414-3417).
    -- Edge value 3 is the Spell Timer's own (the Cooldown seed's is 5 --
    -- design §1.11; group width = Width + Backdrop[6]*2 = 256).
    BackdropBG = TEX .. "Background",
    BackdropEdge = TEX .. "Border",
    BackdropTile = false,
    BackdropTileSize = 16,
    BackdropEdgeSize = 5,
    Inset = 3,                              -- Backdrop[6]
    BarWidth = 235,                         -- Width - Height - 1, :1860-1861
    IconSize = 14,                          -- the icon is a 14x14 Button OUTSIDE the bar
    IconGap = 1,                            -- the -1/+1 anchor gap, :1862-1870
    BarInset = 18,                          -- Height+1+Backop[6], :2322
    GroupWidth = 256,                       -- Width + Backop[6]*2, :1938
    -- ---- the text law (§1.7) ---------------------------------------------
    Font = { FX.CLASSIC_FONT, FONT_SIZE },
    LabelFont = { FX.CLASSIC_FONT, FONT_SIZE },
    StacksFont = { FX.CLASSIC_FONT, FONT_SIZE - 1, "OUTLINE" },  -- :3347
    SmartSpace = true,                      -- :3308 TimerSmartSpace
    -- ---- alphas (§1.1 / §1.2) -------------------------------------------
    NormalAlpha = 0.50,        -- :3366
    BarBackgroundAlpha = 0.30, -- :3367
    RaidTargetsAlpha = 0.7,    -- :3348 RaidTargets[1]
    SparkAlpha = 0.7,          -- :3409 Spark[1]
    CastSparkAlpha = 0.3,      -- :3406 CastSpark[1]
    TimeAlpha = 0.85,          -- the predicted marking's time alpha (§5.5)
    -- ---- textures (§5.1 "keep verbatim") --------------------------------
    BarTexture = TEX .. "Aluminium",
    IconBase = TEX .. "ST",        -- :1692, cropped 0.133..0.867 (:1694)
    IconCrop = { 0.133, 0.867, 0.133, 0.867 },
    Spark = TEX .. "Spark",        -- :1712 bar spark, :1618 tick marks
    IconSpark = TEX .. "Spark2",   -- :1690 icon spark
    RowBack = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", -- :1727
    RaidMark = "Interface\\TargetingFrame\\UI-RaidTargetingIcons",      -- :1721
    TickWidthFactor = 0.5,  -- :1621 Width = Height*0.5
    TickHeightFactor = 1.5, -- :1622 Height = Height*1.5
    SparkHeightFactor = 2,  -- :2384 spark height = Height*2
    SparkFlareFactor = 2.2, -- :2534 icon spark height = vis*Height*2.2
    -- ---- the row gate (§1.1 / §5.5) -------------------------------------
    Max = 15,               -- :3315 Max = {[0]=false, 15} (the ON value)
    MaxOn = false,          -- the flag default
    -- ---- the colours, verbatim :3371-3401 -------------------------------
    ExpiredColor  = { 0.50, 0.50, 0.50, 1.00 },  -- :3371
    HighlightColor = { 1.00, 1.00, 1.00 },        -- :3372
    Fail          = { 1.00, 0.00, 0.30 },        -- :3375
    Channel       = { 0.42, 0.00, 1.00 },        -- :3374
    Curse         = { 0.64, 0.21, 0.93 },        -- :3377
    Bane          = { 0.00, 0.54, 0.42 },        -- :3378
    Crowds        = { 0.00, 1.00, 0.50 },        -- :3380
    Default       = { 1.00, 0.50, 0.00 },        -- :3381
    Pet           = { 1.00, 0.00, 0.95 },        -- :3382
    Heal          = { 0.00, 1.00, 0.00 },        -- :3383
    Buff          = { 1.00, 1.00, 0.00 },        -- :3384
    Enchant       = { 1.00, 1.00, 1.00 },        -- :3385
    SelfBuff      = { 0.00, 0.75, 1.00 },        -- :3387
    SelfDebuff    = { 1.00, 0.00, 0.00 },        -- :3393
    TargetDebuff  = { 0.00, 0.36, 1.00 },        -- :3389
    Cooldown      = { 1.00, 0.39, 0.35 },        -- :3391
    NormalColor   = { 1.00, 1.00, 1.00, 1.00 },  -- :3396
    NormalBgColor = { 0.00, 0.00, 0.00, 0.50 },  -- :3397
    TargetBgColor = { 0.00, 0.00, 0.00, 1.00 },  -- :3400
    FocusBgColor  = { 1.00, 1.00, 0.50, 1.00 },  -- :3401
    ColorOverride = { 0.24, 0.24, 0.24 },        -- :3309 TimerColorOverride
    -- ---- the raid-mark coord pairs (:385-394) ---------------------------
    RaidMarkCoords = {
        { 0.387, 0.549, 0.016, 0.180 },  -- 1 star
        { 0.723, 0.885, 0.016, 0.180 },  -- 2 circle
        { 0.051, 0.212, 0.207, 0.371 },  -- 3 diamond
        { 0.387, 0.549, 0.207, 0.371 },  -- 4 triangle
        { 0.723, 0.885, 0.207, 0.371 },  -- 5 moon
        { 0.051, 0.212, 0.398, 0.562 },  -- 6 square
        { 0.387, 0.549, 0.398, 0.562 },  -- 7 skull
        { 0.723, 0.885, 0.398, 0.562 },  -- 8 palm
    },
}
local S = FX.Timer.Skin

-- ============================================================ pure helpers --
--- FW:MixColors (Forte_Core.lua:2080-2084), verbatim: v==0 => c1, v==1 => c2.
function Laws.Mix(v, c1, c2)
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    return c1[1] * (1 - v) + c2[1] * v,
        c1[2] * (1 - v) + c2[2] * v,
        c1[3] * (1 - v) + c2[3] * v
end

--- FW:FixIntensity (Forte_Core.lua:796-805), verbatim: the text de-saturation
--- that keeps a name legible over a bright fill.
function Laws.FixIntensity(r, g, b)
    local largest = math.max(math.max(r, g), b)
    if largest == 1 then
        return 0.7 * r + 0.3, 0.7 * g + 0.3, 0.7 * b + 0.3
    elseif largest > 0 and largest < 1 then
        return 0.7 * r / largest + 0.3, 0.7 * g / largest + 0.3,
            0.7 * b / largest + 0.3
    end
    return 1, 1, 1
end

--- FW:SecToTimeD (Forte_Core.lua:1746-1761), the `TimeFormat` branch:
--- `m:ss` at >= 60, `%.1f` below. The alternate (Nh/Nm/Ns) branch is the same
--- function's second arm; `alt` selects it.
function Laws.SecToTimeD(t, alt)
    if not alt then
        if t >= 60 then
            return string.format("%d:%02d", math.floor(t / 60), t % 60)
        end
        return string.format("%.1f", t)
    end
    if t >= 3600 then
        return string.format("%dh", math.ceil(t / 3600))
    elseif t >= 60 then
        return string.format("%dm", math.ceil(t / 60))
    end
    return string.format("%ds", math.floor(t))
end

--- The original's visibility ramp (`Alpha(trigger, t)`, the instance-local
--- helper the fade law :2146-2168 calls): full while `t <= trigger`, then a
--- CUBIC fall to 0 across TimerFadeSpeed.
function Laws.Alpha(endAt, t, speed)
    if t <= endAt then return 1 end
    speed = speed or Laws.FADE_SPEED
    if t < endAt + speed then
        return 1 - math.pow((t - endAt) / speed, 3)
    end
    return 0
end

--- The colour law (`ColorVal`, Forte_Timer.lua:1524-1573) as a pure function,
--- the ONE colour decision (:2366-2368 fills the bar from the triple and the
--- row background from the alpha). `remaining`/`total` are OUR OWN computed
--- numbers (v1 rows are predictions; nothing secret-derived reaches here),
--- `state` the row's lifecycle enum, `kind` the spell type whose palette row
--- it draws with. `skin` is FX.Timer.Skin (or a live copy the options page
--- mutates); `opts` carries the flag-shaped settings:
---   highlight=false        the HighlightColor[0] switch off
---   colorOverride={r,g,b}  TimerColorOverride (:3309, off by default)
---   expiredColor=true      ExpiredColor[0]   (:3371, off by default)
---   blink=false            Blink[0] off      (:3335, on by default)
---   blinkAt=3              Blink[1]
function Laws.ColorVal(remaining, total, state, kind, skin, opts)
    skin = skin or S
    opts = opts or {}
    local key = Laws.COLOR_KEY[kind] or "Default"
    local category = skin[key] or skin.Default
    local highlightOn = opts.highlight ~= false
    local r, g, b, a
    if state > Laws.REMOVE then
        -- the fail band (:1526-1533): Fail, mixed from HighlightColor while
        -- the fail flash runs over 2*|remaining|
        if highlightOn and remaining > -0.5 then
            r, g, b = Laws.Mix(-2 * remaining, skin.HighlightColor, skin.Fail)
        else
            r, g, b = skin.Fail[1], skin.Fail[2], skin.Fail[3]
        end
    elseif state == Laws.REMOVE then
        r, g, b = skin.Fail[1], skin.Fail[2], skin.Fail[3]
    else
        local base = opts.colorOverride or category
        if highlightOn and (total - remaining) < 0.5 then
            -- the last half second of the row's OWN total (:1535-1546)
            r, g, b = Laws.Mix((total - remaining) * 2, skin.HighlightColor, base)
        else
            r, g, b = base[1], base[2], base[3]
        end
    end
    -- the alpha law (:1557-1572)
    if total == 0 then
        a = 1
    elseif remaining <= 0 and opts.expiredColor then
        local e = skin.ExpiredColor
        return e[1], e[2], e[3], e[4]
    elseif opts.blink ~= false
        and remaining <= (opts.blinkAt or Laws.BLINK) and remaining > 0 then
        -- the background pulse (:1562-1569): 0.25*(1 - cos(25*sqrt(t))),
        -- inverted above alpha 0.5. Keep 25, the sqrt and the 0.25: they are
        -- the pulse's shape and frequency (asserted numerically, T7).
        local pulse = 0.25 * (1 - math.cos(25 * math.sqrt(remaining)))
        if skin.BarBackgroundAlpha >= 0.5 then
            a = skin.BarBackgroundAlpha - pulse
        else
            a = skin.BarBackgroundAlpha + pulse
        end
    else
        a = skin.BarBackgroundAlpha
    end
    return r, g, b, a
end

--- The bar's fill fraction (§3.6): `barval = clamp((drawExpireAt - now) /
--- maxTime, 0, 1)` -- drawn from the SMOOTHED expire time (:2243 `t1 = t20 - t`).
function Laws.BarVal(drawExpireAt, now, maxTime)
    if not maxTime or maxTime <= 0 then return 0 end
    local v = (drawExpireAt - now) / maxTime
    if v < 0 then return 0 elseif v > 1 then return 1 end
    return v
end

--- The smoothing law, verbatim (:1046):
--- `st[i][20] = st[i][20] + (st[i][1]-st[i][20])/smooth;`
function Laws.Smooth(drawExpireAt, expireAt, smooth)
    return drawExpireAt + (expireAt - drawExpireAt) / (smooth or Laws.SMOOTH)
end

--- The text the time column prints for a row (§1.7, :2473-2481): the fail
--- band's word, the empty string for a zero-total row, else SecToTimeD.
function Laws.TimeText(remaining, total, state, altFormat, failText)
    if state > Laws.REMOVE then
        return failText or "gone"
    elseif total == 0 then
        return ""
    end
    return Laws.SecToTimeD(remaining < 0 and 0 or remaining, altFormat)
end

--- The name column's text (§1.7, :2491-2531): the target name, the spell name
--- when `spell` (or the row has no target), the `#id` prefix and the
--- `(stacks)` suffix.
function Laws.NameText(targetName, spellName, opts)
    opts = opts or {}
    local text = targetName
    if opts.spell or text == nil or text == "" then text = spellName end
    if opts.showID and opts.id and opts.id > Laws.PRIOR_NONE
        and opts.id < (opts.maxId or 1e9) then
        text = "#" .. opts.id .. " " .. tostring(text)
    end
    if opts.stacks and opts.stacks ~= 0 then
        text = tostring(text) .. " (" .. opts.stacks .. ")"
    end
    return text
end

--- The row key (§3.3): spell NAME plus the target key. The same DoT on two
--- dummies is two rows; a self / no-target row is exactly one because its
--- targetKey is the `"none"` sentinel (the original's own law, :979-985).
function Laws.RowKey(name, targetKey)
    return tostring(name) .. "\1" .. tostring(targetKey)
end

--- The group id a self / no-target row carries (:979-985): a PRIOR_* sentinel
--- bands it in the sort instead of a per-mob id.
function Laws.SentinelGroupKey(kind)
    if kind == "Cooldown" then return Laws.PRIOR_COOLDOWN end
    if kind == "SelfDebuff" then return Laws.PRIOR_SELF_DEBUFF end
    if kind == "Channel" then return Laws.PRIOR_POWERUP end
    return Laws.PRIOR_NONE
end

--- The link-table comparator (§1.5). A link is `{ rowIdx, groupKey,
--- drawExpireAt, alpha, hiddenSince, maxTime }` (the port of the original's
--- link row :431-441); the sort keys are `SORT_TIMER_ORDER2 = {2,3}` (group
--- id, then drawn-expire-time) when grouping and `SORT_TIMER_ORDER = {3}`
--- when not (:450-453). `outwands` is the direction flip (:2172-2182, default
--- true :3333); rowIdx breaks ties so the order is total and deterministic.
function Laws.CompareLinks(a, b, grouping, outwands)
    if grouping and a[2] ~= b[2] then
        if outwands then return a[2] > b[2] end
        return a[2] < b[2]
    end
    if a[3] ~= b[3] then
        if outwands then return a[3] < b[3] end
        return a[3] > b[3]
    end
    return a[1] < b[1]
end

--- The grace law (:1186-1187). The source test is
--- `(st[i][3] - st[i][1] + t) >= BuffDelay` -- total minus expire is MINUS the
--- cast time (expire = cast + total), so the predicate is
--- `t >= castTime + BuffDelay`: a row becomes checkable (judgeable as gone)
--- BUFF_DELAY seconds after the window it predicts started.
function Laws.CheckableAt(castTime, total)
    return (castTime or 0) + Laws.BUFF_DELAY
end

--- The time-band compression law (:2192-2235): the scale a bar is drawn
--- against. `oneMax` takes the tallest visible duration as the shared 1.0
--- (clamped at MaxTime); `forceMax` pins it to MaxTime; the ease to the target
--- is the link's own relaxation (:2236-2240), applied by Rows.
function Laws.MaxTime(total, highestduration, opts)
    opts = opts or {}
    local cap = opts.maxTimeCap
    if opts.forceMax then return cap or total end
    local h = highestduration
    if cap and h > cap then h = cap end
    if opts.oneMax == false then
        local t = total
        if cap and t > cap then t = cap end
        return t
    end
    return h
end

--- The per-row visibility law (:2146-2168) + the HideLonger gate
--- (:2151-2162). `hiddenSince` is the moment the gate tripped (0 = not
--- gated); a gated row fades out over `Alpha(hiddenSince + HideTime, t)`, and
--- ramps back in the same ramp from `now` when the gate lets go.
function Laws.GateAlpha(state, expireAt, removeAt, now, opts)
    if state == Laws.IGNORE then
        return 0
    elseif state == Laws.NORMAL then
        if opts.hideLonger and (expireAt - now) >= opts.hideLongerAt then
            local since = opts.hiddenSince
            if not since or since == 0 then
                since = now
                opts.hiddenSince = since
            end
            return Laws.Alpha(since + (opts.hideTime or Laws.HIDE_TIME), now)
        end
        opts.hiddenSince = 0
        return 1
    elseif state == Laws.FADING_INSTANT then
        return Laws.Alpha(removeAt, now)
    elseif state == Laws.FADING then
        return Laws.Alpha(removeAt + Laws.FADE, now)
    end
    return Laws.Alpha(removeAt + Laws.FAIL, now)
end

--- The lifetime law's delete test (:1070-1076 with ST_CalculateMaxDelay
--- :1028-1036): a faded row dies at `removeAt + (instant and TimerFadeSpeed
--- or max(FailTime, FadeTime) + TimerFadeSpeed)`.
function Laws.DeathAt(removeAt, kind)
    if Laws.INSTANT_FADE[kind] then
        return removeAt + Laws.FADE_SPEED
    end
    return removeAt + math.max(Laws.FAIL, Laws.FADE) + Laws.FADE_SPEED
end

--- The adopted-window law (§3.5, the :1184 comparison as a predicate):
--- ADOPT when |fact - prediction| <= MAXLAG, EXTEND when the fact is longer,
--- REFRESH when it is shorter by more than MAXLAG.
function Laws.ReconcileVerdict(factExpire, predictedExpire)
    local d = factExpire - predictedExpire
    if math.abs(d) <= Laws.MAXLAG then return "adopt", d end
    if d > 0 then return "extend", d end
    return "refresh", d
end

--- The removal-refusal law (:1207): a row may not be judged gone while more
--- than MAXLAG of its own window is left.
function Laws.RemovalRefused(expireAt, now)
    return (expireAt - now) > Laws.MAXLAG
end

--- The grace law (:1186-1187): a row becomes checkable (removable on a
--- "no such aura" read) only BUFF_DELAY seconds after the window it predicts
--- should have started.
function Laws.CheckableAt(castTime, total)
    return (castTime or 0) + (total or 0) - Laws.BUFF_DELAY
end

FX.Timer.Laws = Laws
FX.Timer.Skin = S
