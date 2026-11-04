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
-- Fill law (Wave I-3, upstream-addons-2026-11-03 §3 / ranked 2 -- the
-- shipped swing-timer family's own capability gate, re-derived from the
-- declared APIs; numbers and shape only): where `StatusBar
-- :SetTimerDuration` + `C_DurationUtil.CreateDuration` + the
-- Status-bar Interpolation/TimerDirection enums exist, the reload/aim fill
-- can be ARMED, not animated -- one call per state edge (a cycle re-arm, the
-- aim-floor move, the flight, the cast interlock, the idle transition) and
-- the client interpolates the bar in between, with no Lua fill maths
-- running per frame.
--
-- DEFAULT POSTURE: the v2 Lua path ("lua"). The engine path is built,
-- feature-detected, tested and selectable (`SetFillEngineMode`), and it is
-- NOT the default, measured 2026-11-03 on wow-ui-sim v0.1.39: the call, the
-- enums and the duration object (its own GetRemainingDuration counts down)
-- all exist, and the widget's `SetValue` arms DO render (the white
-- projectile-left bar and the interlock's frozen fraction draw exactly the
-- v2 pixels, and so does a degraded bar) -- but the widget never CONSUMES
-- an armed duration: its value sits at its min after `SetTimerDuration`, so
-- the two arms that need the client's animation (the safe-window span, the
-- single-phase elapsed fill) render EMPTY in the harness the v2 bar was
-- frame-by-frame verified in (test_swing3.lua pins that reading). On the
-- client the same call is docs/launch-day.md probe 5 /
-- docs/design-combat-procs.md item 5 -- "does a duration object WE built
-- animate our own widgets", i.e. not yet a proven fact. A live-verified bar
-- does not go dark behind an unproven capability the night before launch:
-- the flip of this file's default from "lua" to "auto" is that probe's
-- result, and it is one word. Everything the v2 cycle needs -- phases,
-- slices, spark, text, alpha -- runs identically on both paths, the gate
-- runs once, in Init, and the OnUpdate script (never on a hidden frame) is
-- the shared edge pass that carries them.
--
-- ITERATION J SLICE A (docs/research/wst-swing-design.md §7.1-§7.4, the
-- ForteXorcist-style reading of WeaponSwingTimer SixxFix's Hunter bar):
--   * ONE MODE PICKER (`SetBarMode`, the `BarMode` key; §7.1) selects a
--     single expression in Update's fill chain and nothing else --
--       "safe"     the shipped pixels, byte for byte (today's default,
--                   and the reading of an unset mode);
--       "one"      the fill runs TOWARD the aim end (the WST `one_bar`
--                   idiom): W x progress, capped by the standing aim
--                   region, the cap opening with the region's drain so the
--                   edge reaches full width as the shot leaves (§7.2);
--       "elapsed"  the plain cycle clock = today's ShowSafeWindow=false
--                   law (the slices hide wholesale, as today).
--     `ShowSafeWindow` is now that picker's servant (its `false` reads
--     back as `elapsed`), which is §7.1's migration as running code.
--   * THREE POSITION MARKERS on the same 200x12 Aluminium bar, pure
--     geometry off numbers the pass already reads -- no new event, no new
--     frame, no tracker change (each behind its own key, defaults of §7.8
--     γ.1: region ON, stripe ON, line OFF):
--       the STANDING AIM REGION (P2, §7.3): aimLen x scale at the right
--       end ALL cycle at AimRegionAlpha, the full-alpha live slice drawing
--       over it; the WST aim block's *drain* is deliberately NOT copied
--       (one number per fact: the region is positional, the text numeric);
--       under a live retry its alpha dims so the yellow stays loudest;
--       the CLIP STRIPE (P1, §7.4): (castLen + aimLen) x scale, clamped to
--       the bar, the aim hue at ClipRegionAlpha under the region, so the
--       right end is a two-tone zone -- bright = stand still, dim = a
--       cast started from here out clips the shot. castLen is the LIVE
--       cast's length under the interlock (the frozen red bar shows the
--       reason it is red) and the shipped data's Aimed Shot otherwise;
--       the WEAVE LINE (P4, §7.4): 1 px at (aimLen + gcd) x scale from the
--       right, Height + MarkerOvershoot tall so it reads as a line, hidden
--       when the budget runs off the bar's left edge -- at/past it there is
--       no room for the GCD at all, which is the "do not step in" message.
--     The markers read by ALPHA STEP (0.22 / 0.45 / 1.0 of the same red)
--     plus one off-family hue for the line; the Aluminium art, the
--     Aluminium fill and the live red slice are all untouched.
--   * `gcdSeconds()` is a DATA read (the shipped Hunter rows' gcdMs, §7.9
--     law 3), not WST's paladin constant; `ClipCastSeconds()` is the data's
--     cast time for the interlock's shot set (§7.9 law 2: no clip bar from
--     the reference -- its width law does not exist in this build).
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
    -- Iteration J slice A (docs/research/wst-swing-design.md §7.3/§7.4): the
    -- three position markers on the Aluminium bar. They read by ALPHA STEP,
    -- not by a new art file, so the right end is one legible family:
    --   * the CLIP STRIPE (P1) -- the aim hue at 0.22: a dim red wash over
    --     the bar's right end, wider than the aim region; under a live cast
    --     interlock it rides the FlyingColor triple so the frozen RED bar
    --     shows a lighter band = the reason it is red (§7.4);
    --   * the STANDING AIM REGION (P2) -- the same red at 0.45: clearly the
    --     brighter knob inside the stripe, and always dimmer than the
    --     full-alpha live aim slice that draws over it; under a live retry
    --     it dims to AIM_REGION_RETRY_ALPHA so the yellow stays loudest;
    --   * the WEAVE LINE (P4) -- the Timeline's Powerup cyan at 0.95 on the
    --     Border edge art, 1 px wide and Height + 6 tall, so it pokes out of
    --     the bar's top/bottom edges and cannot be mistaken for the
    --     orange/red/yellow cycle family.
    AimRegionAlpha = 0.45,
    AimRegionRetryAlpha = 0.25,
    ClipRegionAlpha = 0.22,
    ClipInterlockColor = { 1, 1, 1, 1 },
    WeaveColor = { 0, 0.75, 1, 0.95 },
    WeaveTexture = TEX .. "Border",
    WeaveWidth = 1,
    MarkerOvershoot = 6,                      -- WST's taller-than-the-bar law
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

--- The GCD the melee-weave line budgets for (docs/research/
--- wst-swing-design.md §7.4 P4, §7.9 law 3): a DATA row, not WST's
--- hard-coded paladin `GetSpellInfo(19217)` constant. The GCD does not
--- haste, so the shipped Hunter rows' `gcdMs` is the number, and the
--- smallest positive row is the one a Hunter pays. Memoised (the generated
--- data is static for the session); 1.5 s is the data's value and the
--- no-data fallback.
local gcdSecCache
local function gcdSeconds()
    if gcdSecCache ~= nil then return gcdSecCache end
    local data = FX.Data and FX.Data.Hunter
    local best
    if type(data) == "table" then
        for _, sp in pairs(data) do
            local ms = (type(sp) == "table") and sp.gcdMs or nil
            if type(ms) == "number" and ms > 0
                and (best == nil or ms < best) then
                best = ms
            end
        end
    end
    gcdSecCache = (best and best / 1000) or 1.5
    return gcdSecCache
end
D.GcdSeconds = gcdSeconds

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
    -- Iteration J slice A (docs/research/wst-swing-design.md §7.1 + §7.8 γ.1
    -- defaults; the page (γ) wires the keys, the module keeps these as its
    -- own skin defaults so the setters are legal before the store exists):
    --   barMode        "safe" (unset = today's pixels exactly) | "one" |
    --                  "elapsed" -- §7.1's one mode picker;
    --   showAimWindow  the standing aim region (P2), default ON;
    --   showClipRegion the clip stripe (P1), default ON;
    --   showWeaveLine  the melee-weave line (P4), default OFF (§7.4: a
    --                  signal a player without the weave build must learn
    --                  to ignore costs more than it pays).
    barMode = "safe",
    showAimWindow = true,
    showClipRegion = true,
    showWeaveLine = false,
}
local ST = D.state

--- The default fill path (the header's DEFAULT POSTURE): the v2 Lua law.
--- "auto" = the capability gate, "engine" = force the armed widget; both
--- are live seams (`SetFillEngineMode`), and the launch-day duration-object
--- probe is what flips this line.
D._fillMode = "lua"

-- ---------------------------------------------------------- fill engines --
--- The capability gate of the header's Fill law: the engine path needs the
--- duration factory (C_DurationUtil.CreateDuration
--- @DurationUtilDocumentation.lua:10), the widget timer
--- (SimpleStatusBarAPI:SetTimerDuration
--- @SimpleStatusBarAPIDocumentation.lua:333 -- checked on the fill object
--- itself, in _BuildFill) and both enums (StatusBarInterpolation
--- @SimpleStatusBarConstantsDocumentation.lua:19, StatusBarTimerDirection
--- @:43). Runs ONCE, in Init. The shipped family's own gate also demands
--- C_SwingTimer + Enum.PlayerSwingType: those are the swing-RANGE surface
--- (Core/Tools.lua's second range signal), not the fill's, and the fill
--- arms without them.
local function engineFillCapable()
    local CDU = _G.C_DurationUtil
    local E = _G.Enum
    return type(CDU) == "table"
        and type(CDU.CreateDuration) == "function"
        and type(E) == "table"
        and E.StatusBarTimerDirection ~= nil
        and E.StatusBarInterpolation ~= nil
end

--- An Enum member as a plain number, the declared value as the fallback
--- (Core/Tools.lua's pcall-guarded Enum idiom: a secret table can never
--- raise here). Declared: StatusBarTimerDirection.ElapsedTime = 0,
--- .RemainingTime = 1, StatusBarInterpolation.Immediate = 0 (measured
--- identical in the simulator 2026-11-03).
local function enumNum(ns, name, fallback)
    local ok, v = pcall(function()
        return FX.Compat.PlainOrNil(ns and ns[name])
    end)
    if ok and type(v) == "number" then return v end
    return fallback
end

local function timerDirections()
    local E = _G.Enum
    return {
        elapsed = enumNum(E and E.StatusBarTimerDirection, "ElapsedTime", 0),
        remaining = enumNum(E and E.StatusBarTimerDirection, "RemainingTime", 1),
        immediate = enumNum(E and E.StatusBarInterpolation, "Immediate", 0),
    }
end

--- Two decimals are enough to name an arm: the widths and windows of the
--- v2 cycle are tenths-of-a-pixel / tenths-of-a-second affairs.
local function armNum(v)
    if type(v) ~= "number" then return "-" end
    return string.format("%.2f", v)
end

-- ---------------------------------------------------------------- font --
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

    -- The fill (the engine/lua choice of the header's Fill law, decided
    -- once here): TOPLEFT-anchored with an explicit size on the lua path,
    -- so `fill:GetWidth()` IS the rendered fraction (the acceptance's
    -- geometry check) and the fill grows left -> right.
    self._fillEngine = engineFillCapable()
    self._dirs = timerDirections()
    self:_BuildFill(f)
    -- The standing aim region (slice A, §7.3) must sit UNDER the live aim
    -- slice, so it is built before the slices; the clip stripe and the
    -- weave line are built after them (below), so the frozen interlock bar
    -- shows the stripe's lighter band = the reason it is red (§7.4).
    self:_BuildAimRegion(f)

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

    -- The clip stripe + the weave line: the topmost bar art (the z law of
    -- `_BuildAimRegion`).
    self:_BuildTopMarkers(f)

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

    self.anchor, self.text, self.title = f, text, title
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
    self._fillW, self._timeKey, self._armKey = nil, nil, nil
end

--- The standing aim region (slice A, docs/research/wst-swing-design.md
--- §7.3, signal P2) and the two position markers of §7.4. Built in two
--- steps because the z-order is load-bearing on the Aluminium art:
---   * the AIM REGION is built here, AFTER the fill (so its red tint reads
---     over the Aluminium) and BEFORE the live aim slice (so the full-alpha
---     live slice draws over it, §7.3);
---   * the CLIP STRIPE and the WEAVE LINE are built by `_BuildTopMarkers`
---     after the slices: the stripe must stay legible over the interlock's
---     full-width red slice (§7.4: "the frozen red bar also shows the
---     *reason* it is red"), and the weave line is a 1-px ruler over
---     everything.
--- All three are plain textures on the anchor: no new frame, no new event.
function D:_BuildAimRegion(parent)
    local reg = parent:CreateTexture(nil, "ARTWORK")
    reg:SetTexture(S.BarTexture)
    reg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    reg:SetSize(0, S.Height)
    local ac = S.AimColor
    reg:SetVertexColor(ac[1], ac[2], ac[3], S.AimRegionAlpha)
    reg:Hide()
    self.aimRegion = reg
    self._aimRegionW, self._aimRegionA = nil, nil
end

--- The clip stripe (P1) and the weave line (P4); see `_BuildAimRegion` for
--- why they are the topmost bar art.
function D:_BuildTopMarkers(parent)
    local clip = parent:CreateTexture(nil, "ARTWORK")
    clip:SetTexture(S.BarTexture)
    clip:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    clip:SetSize(0, S.Height)
    local ac = S.AimColor
    clip:SetVertexColor(ac[1], ac[2], ac[3], S.ClipRegionAlpha)
    clip:Hide()

    local weave = parent:CreateTexture(nil, "ARTWORK")
    weave:SetTexture(S.WeaveTexture)
    weave:SetSize(S.WeaveWidth, S.Height + S.MarkerOvershoot)
    weave:SetPoint("TOPLEFT", parent, "TOPLEFT", 0,
        S.MarkerOvershoot * 0.5)
    local wc = S.WeaveColor
    weave:SetVertexColor(wc[1], wc[2], wc[3], wc[4])
    weave:Hide()

    self.clip, self.weave = clip, weave
    self._clipW, self._clipA, self._weaveX = nil, nil, nil
end

-- ---------------------------------------------------------------- the fill --
--- Which path draws: the file's default is "lua" (the header's DEFAULT
--- POSTURE); "auto" runs the capability gate and "engine" asks for the
--- armed widget -- both of them degrade to the v2 path on a client without
--- the API, never to a blank bar.
function D:_FillEngineWanted()
    if self._fillMode == "lua" then return false end
    if self._fillEngine == nil then self._fillEngine = engineFillCapable() end
    return self._fillEngine and true or false
end

--- True while the engine path owns the fill's animation.
function D:UsesEngineFill()
    return self._engineFill and true or false
end

--- Build the fill for the mode the gate decided (Init) or a seam forced.
--- The engine path needs a StatusBar -- SetTimerDuration is a widget
--- method -- whose value range (min..max = 0..1) IS the bar's width
--- fraction, so both paths agree on geometry: the engine fill spans a
--- width set at its edge and the value animates inside it, the lua fill is
--- sized every pass. No StatusBar (or no timer method) = the v2 texture
--- path, gate off: the pre-I-3 bar, unchanged.
function D:_BuildFill(parent)
    local engine = self:_FillEngineWanted()
    local fill
    if engine then
        local ok, sb = pcall(CreateFrame, "StatusBar",
            "ForteXorcistHunterSwingFill", parent)
        if ok and sb and type(sb.SetTimerDuration) == "function" then
            fill = sb
            pcall(fill.SetStatusBarTexture, fill, S.BarTexture)
            pcall(fill.SetMinMaxValues, fill, 0, 1)
            fill:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
            fill:SetSize(0, S.Height)
        else
            engine = false
        end
    end
    if fill == nil then
        fill = parent:CreateTexture(nil, "ARTWORK")
        fill:SetTexture(S.BarTexture)
        fill:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
        fill:SetSize(0, S.Height)
    end
    self.fill, self._engineFill = fill, engine
    self._fillW, self._armKey, self._fillSpanW = nil, nil, nil
    self:_SetFillColor(fill, S.BarColor)
    return fill
end

--- The fill tint, per path (the widget has its own colour setter; the
--- texture's is SetVertexColor).
function D:_SetFillColor(fill, c)
    if self._engineFill and fill.SetStatusBarColor then
        pcall(fill.SetStatusBarColor, fill, c[1], c[2], c[3], c[4])
    else
        fill:SetVertexColor(c[1], c[2], c[3], c[4])
    end
end

--- The tests'/demo's seam over the two fill paths. Rebuilds the fill; the
--- state edges, the slices, the spark and the text are shared code, so one
--- cycle draws the same sequence on both (the parity test proves it).
function D:SetFillEngineMode(mode)
    if mode ~= "engine" and mode ~= "lua" then mode = "auto" end
    if self._fillMode == mode then return end
    self._fillMode = mode
    if not self.anchor then return end
    local old = self.fill
    self.fill = nil
    if old ~= nil then
        if old.Hide then pcall(old.Hide, old) end
        if old.SetParent then pcall(old.SetParent, old, nil) end
    end
    self:_BuildFill(self.anchor)
    self:RenderIdle()
    local t = self.Tracker
    if t and t.active then self:StartTicking() end
end

--- The one duration object of this bar -- the shipped law re-SETS the
--- row's object at every edge instead of building one per frame.
function D:_DurationObject()
    local d = self._dur
    if d ~= nil then return d end
    local CDU = _G.C_DurationUtil
    if not (CDU and CDU.CreateDuration) then return nil end
    local ok, created = pcall(CDU.CreateDuration)
    if not ok or created == nil then return nil end
    if type(created.SetTimeFromStart) ~= "function" then return nil end
    self._dur = created
    return created
end

--- Arm the engine fill for the current state. The three arms and why each
--- is algebraically the v2 law (W = the bar's width):
---   * span (the safe window): the frame is sized to the law's CURRENT
---     width w = (remaining - floor)/duration x W and the timer drains it
---     to empty over exactly the span that is left (remaining - floor
---     seconds, RemainingTime). Both curves are linear and agree at the
---     arm instant and at the floor instant, so they agree everywhere --
---     the fill reaches 0 at the aim window's first instant;
---   * elapsed (the single-phase law): the full width, ElapsedTime from the
---     cycle's own start, so a bar that starts mid-shot picks the cycle up
---     at its true fraction;
---   * value: a static fraction -- the whole-width white flight, the
---     interlock's frozen clip fraction -- an expired duration plus an
---     explicit value, the static state the engine paints for a finished
---     timer.
--- Immediate on every arm: the shipped "a restart mid-swing must not ease
--- back from the old fill". One pcall over the widget touches: a raise
--- degrades THIS bar to the v2 SetSize law (one way, never back).
function D:_EngineFillPass(now, tracker, phase, castLeft, w, floor, remaining)
    local W = S.Width
    local kind, key, dir, start, dur, target
    if castLeft or (ST.showSafeWindow and phase == "flying") then
        kind = "value"
        target = (W > 0) and (w / W) or 0
        dir, start, dur = self._dirs.remaining, now, 0
        key = "v|" .. armNum(target)
    elseif ST.barMode == "one" then
        -- The `one` mode's arm (slice A, §7.2): the law is the cycle's own
        -- progress, W x progress, capped by the standing region's drain --
        -- and the cap IS W x progress (progress = 1 - remaining/duration,
        -- the region's width is aimLen x scale), so the cycle's elapsed
        -- arm over the full width is algebraically the whole curve, cap
        -- included. The fill runs toward the aim end and reaches full
        -- width exactly as the shot leaves.
        kind = "elapsed"
        dir = self._dirs.elapsed
        start, dur = tracker.start, tracker.duration
        key = "n|" .. armNum(tracker.start) .. "|" .. armNum(tracker.duration)
    elseif ST.showSafeWindow then
        kind = "span"
        dir = self._dirs.remaining
        start = now
        dur = math.max(0, remaining - floor)
        key = "s|" .. armNum(tracker.start) .. "|" .. armNum(tracker.duration)
            .. "|" .. armNum(floor)
    else
        kind = "elapsed"
        dir = self._dirs.elapsed
        start, dur = tracker.start, tracker.duration
        key = "e|" .. armNum(tracker.start) .. "|" .. armNum(tracker.duration)
    end
    if key == self._armKey then return end
    local d = self:_DurationObject()
    if d == nil then
        self:_DegradeEngineFill()
        return
    end
    local spanW = (kind == "span") and w or W
    local dirs = self._dirs
    local ok = pcall(function()
        d:SetTimeFromStart(start, dur, 1)
        self.fill:SetSize(spanW, S.Height)
        self.fill:SetTimerDuration(d, dirs.immediate, dir)
        if target ~= nil then self.fill:SetValue(target) end
    end)
    if not ok then
        self:_DegradeEngineFill()
        return
    end
    self._armKey = key
    self._fillSpanW = spanW
    local log = self._engineLog
    if log ~= nil then
        log[#log + 1] = { kind = kind, key = key, span = spanW, dur = dur,
            dir = dir, target = target, at = now }
        if #log > 64 then table.remove(log, 1) end
    end
end

--- The idle state of an engine fill: an expired duration parked at empty,
--- so a hidden bar costs the client nothing (the shipped "an idle row
--- costs nothing" law).
function D:_EnginePark(now)
    self._armKey, self._fillSpanW = nil, 0
    local d = self:_DurationObject()
    if d == nil then return end
    local dirs = self._dirs
    pcall(function()
        d:SetTimeFromStart(now, 0, 1)
        self.fill:SetSize(0, S.Height)
        self.fill:SetTimerDuration(d, dirs.immediate, dirs.remaining)
        self.fill:SetValue(0)
    end)
end

--- The one-way degrade: the widget path raised, so this bar's fill is
--- driven by the v2 SetSize law from here on. A StatusBar whose value sits
--- at its max fills its own frame, which is exactly what that law expects.
function D:_DegradeEngineFill()
    self._engineFill = false
    self._fillW, self._armKey, self._fillSpanW = nil, nil, nil
    local fill = self.fill
    if fill == nil then return end
    pcall(function()
        fill:SetMinMaxValues(0, 1)
        fill:SetValue(1)
    end)
end

--- The tests' view of the engine arms (bounded): entries are
--- {kind, key, span, dur, dir, target, at}. nil = logging off.
function D:FillLog(on)
    self._engineLog = on and {} or nil
    return self._engineLog
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
    -- The fill keeps its current fraction under the new numbers: the v2
    -- path's own width, the engine path's current span (the arm key is
    -- dropped, so the next pass re-arms the span and the timer on the new
    -- geometry).
    if self._engineFill then
        self._armKey = nil
        self.fill:SetSize(self._fillSpanW or 0, S.Height)
    else
        self.fill:SetSize(self._fillW or 0, S.Height)
    end
    -- The slice A markers are pure functions of (W, Height), so the resize
    -- drops their caches: the next pass re-sizes/re-anchors them on the new
    -- numbers (the slice widths ride the same law, the v2 behaviour).
    self._aimRegionW, self._aimRegionA = nil, nil
    self._clipW, self._clipA = nil, nil
    self._weaveX = false                        -- the force sentinel, not nil
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
    self:_SetFillColor(self.fill, c)
    self._fillColor = nil
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
--- Today's shipped key, now the mode picker's servant (§7.1: `BarMode`
--- REPLACES `ShowSafeWindow`, the key retires in the same cutover and slice
--- γ drops it from the page/STORED lists). Routing it through
--- `SetBarMode` is what makes the migration a fact and not a comment: a
--- stored `ShowSafeWindow = false` reads back as the `elapsed` mode -- the
--- same pixels it draws today -- and `true`/unset as `safe`. It is also why
--- the mode and the key can never disagree on the live object.
function D:SetShowSafeWindow(on)
    self:SetBarMode(on and "safe" or "elapsed")
end

--- The §7.1 mode picker: "safe" (today's shipped pixels, the default),
--- "one" (the fill runs toward the aim end, §7.2) or "elapsed" (the plain
--- cycle clock, today's `ShowSafeWindow = false` law, slices hidden). An
--- unset/unknown mode reads as "safe"; `SetShowSafeWindow` is the runtime
--- migration seam.
function D:SetBarMode(mode)
    if mode ~= "one" and mode ~= "elapsed" then mode = "safe" end
    ST.barMode = mode
    ST.showSafeWindow = (mode ~= "elapsed")   -- the mode subsumes the key
    self._fillW, self._timeKey, self._phase, self._fillColor = nil, nil, nil,
        nil
    self._aimRegionW, self._aimRegionA, self._clipW, self._clipA =
        nil, nil, nil, nil
    self._weaveX = false                       -- the force sentinel, not nil
end

--- P2: the standing aim region at the bar's right end (§7.3). Hiding it
--- touches NOTHING else: the live aim slice, the cap's geometry in the
--- `one` mode and every v2 signal are independent of it.
function D:SetShowAimWindow(on)
    ST.showAimWindow = not not on
    self._aimRegionW, self._aimRegionA = nil, nil
end

--- P1: the clip stripe (§7.4). Off = width 0, the stripe never drawn.
function D:SetShowClipRegion(on)
    ST.showClipRegion = not not on
    self._clipW, self._clipA = nil, nil
end

--- P4: the melee-weave line (§7.4). Default OFF: it is a weave-build tool.
function D:SetShowWeaveLine(on)
    ST.showWeaveLine = not not on
    self._weaveX = false             -- force the next pass (the sentinel law)
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
    elseif ST.barMode == "one" then
        -- The `one` mode (slice A, §7.2): the fill is the cycle's progress
        -- running INTO the aim end, capped so its right edge never enters
        -- the standing aim region; the cap opens with the region's drain
        -- through the aim phase, so the edge reaches the full width exactly
        -- as the shot leaves. `drain` is the aim length the bar must still
        -- keep clear: the full aim window while the cycle reloads, the
        -- aim phase's own remaining inside it.
        local aim = aimLen or 0
        local drain = (phase == "aim") and math.min(aim, remaining) or aim
        w = math.min(W - drain * scale, W * fraction)
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
    -- The fill intent: this pass' width from the law above, recorded on
    -- both paths (the v2 path's `_fillW` caches its last SetSize; the
    -- engine path sizes its span from this number at the arm edge). The
    -- seam the fill-parity test compares; the spark head rides it too.
    self._fillIntent = w
    -- The engine path arms the widget at the state edge and lets the
    -- client animate it (the header's Fill law); the v2 path sizes it from
    -- the law above. The engine test is re-read, so a mid-pass degrade is
    -- drawn the same pass it happens.
    if self._engineFill then
        self:_EngineFillPass(now, tracker, phase, castLeft, w, floor, remaining)
    end
    if not self._engineFill and self._fillW ~= w then
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
        self:_SetFillColor(self.fill, fc)
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

    -- The slice A markers (docs/research/wst-swing-design.md §7.3/§7.4):
    -- the standing aim region, the clip stripe, the weave line. Pure
    -- geometry off the numbers this pass already read -- no new event, no
    -- new frame, no tracker change.
    local aimSec = (aimLen and aimLen > 0) and aimLen or 0
    -- P2: the standing aim region -- `aimLen x scale` at the bar's right
    -- end for the WHOLE cycle, in every mode. It is a region, not the live
    -- window, so the full-alpha live slice above it stays the loudest red
    -- (and under a live retry this one dims further, §7.3).
    local regionW = 0
    if ST.showAimWindow and aimSec > 0 and scale > 0 then
        regionW = math.min(W, aimSec * scale)
    end
    self:_SetSlice(self.aimRegion, "_aimRegionW", regionW, 0)
    self:_SetMarkerColor(self.aimRegion, "_aimRegionA", S.AimColor,
        (retryW > 0) and S.AimRegionRetryAlpha or S.AimRegionAlpha)

    -- P1: the clip stripe -- (castLen + aimLen) x scale, clamped to the
    -- bar. `castLen` is the LIVE cast's length while a cast runs, the
    -- shipped data's longest cast-time shot otherwise, so an un-hasted
    -- 2.0 s bow draws a full-width stripe: the honest "Aimed Shot always
    -- clips on this bow", available before the press (§7.4).
    local clipW = 0
    if ST.showClipRegion and scale > 0 then
        local castSec = castLen or self:ClipCastSeconds()
        local span = castSec and (castSec + aimSec)
        if span and span > 0 then
            clipW = math.min(W, span * scale)
        end
    end
    self:_SetSlice(self.clip, "_clipW", clipW, 0)
    -- Under the interlock the stripe rides the light interlock tint, so the
    -- frozen red bar shows the *reason* it is red (§7.4's last law).
    self:_SetMarkerColor(self.clip, "_clipA",
        castLeft and S.ClipInterlockColor or S.AimColor, S.ClipRegionAlpha)

    -- P4: the melee-weave line, 1 px at (aimLen + GCD) x scale from the
    -- right. At/past the bar's left edge there is no room for the 1.5 s GCD
    -- at all -- a hasted cycle parks the line OFF the bar, which IS the
    -- "do not step in" message, so the line hides (§7.4's no-room law).
    local weaveX
    if ST.showWeaveLine and scale > 0 then
        local x = W - (aimSec + gcdSeconds()) * scale
        if x > 0 then weaveX = x end
    end
    self:_SetWeaveLine(weaveX)
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

--- Dirty-checked marker tint: a colour triple plus the alpha it rides at.
--- The slice A markers read by ALPHA STEP over the Aluminium fill (see the
--- SwingSkin comment), so the alpha is part of their identity, not a style.
function D:_SetMarkerColor(tex, key, col, a)
    if not tex or not col then return end
    local k = col[1] .. "|" .. col[2] .. "|" .. col[3] .. "|" .. tostring(a)
    if self[key] == k then return end
    self[key] = k
    tex:SetVertexColor(col[1], col[2], col[3], a)
end

--- The weave line's geometry: a 1-px line at `x` px from the bar's left
--- edge, drawn `MarkerOvershoot` px TALLER than the bar so it reads as a
--- line across the bar's edges (the WST marker law,
--- WeaponSwingTimer_Player.lua:399, :406). `nil` = off-bar ⇒ hidden.
---
--- The dirty key rides `_weaveX`; the setters and `RenderIdle` force the
--- next pass by storing `false`, NEVER nil -- nil IS the hidden state, so a
--- nil force makes a following hidden pass dirty-return and leave a shown
--- line on the bar (the law the first run's facts proved: x=nil, node shown,
--- strata untouched).
function D:_SetWeaveLine(x)
    local tex = self.weave
    if not tex then return end
    if self._weaveX == x then return end
    self._weaveX = x
    if x == nil then
        -- The park, in the `_SetSlice` idiom: zero the size and drop the
        -- strata out of the bar's drawing order before hiding, so a stale
        -- 1-px ruler can never ride a bar that has nothing to say.
        tex:SetSize(0, 0)
        tex:SetFrameStrata("BACKGROUND")
        tex:Hide()
        return
    end
    local h = S.Height + S.MarkerOvershoot
    tex:SetFrameStrata("ARTWORK")               -- the build-time strata
    tex:SetTexture(S.WeaveTexture)
    tex:SetSize(S.WeaveWidth, h)
    -- WoW's y runs upward: +overshoot/2 puts the line's TOP that far ABOVE
    -- the bar's top, so the taller line straddles the bar's edges evenly.
    tex:SetPoint("TOPLEFT", self.anchor, "TOPLEFT",
        x - S.WeaveWidth * 0.5, S.MarkerOvershoot * 0.5)
    tex:Show()
end

--- The names the swing interlock treats as cast-time shots
--- (Core/Tools.lua's SHOT_CAST_SET, :184-186 — the SAME English key space,
--- name-keyed per AGENTS.md; the set is that module's local, so the clip
--- stripe's data fallback mirrors it here and rides the DATA for the
--- number. Multi-Shot / Steady Shot ship no castMs on Forever, so this
--- resolves to Aimed Shot's 2000 ms -- §7.4's worked number).
local CLIP_SHOT_NAMES = {
    ["Aimed Shot"] = true, ["Multi-Shot"] = true, ["Steady Shot"] = true,
}

--- The clip stripe's cast length with NO live cast (seconds): the longest
--- cast time the shipped data gives the interlock's shot set. nil = no
--- knowledge ⇒ no stripe. Memoised per bar; `InvalidateClipCastLength`
--- re-reads (the data-refresh seam; the tests inject their own table
--- through Tools.DataCastMsByName).
function D:ClipCastSeconds()
    if self._clipCastSec ~= nil then return self._clipCastSec end
    local T = FX.Hunter.Tools
    local idx = (T and T.DataCastMsByName) and T.DataCastMsByName()
    local best
    if type(idx) == "table" then
        for name, ms in pairs(idx) do
            if CLIP_SHOT_NAMES[name] and type(ms) == "number" and ms > 0
                and (best == nil or ms > best) then
                best = ms
            end
        end
    end
    self._clipCastSec = (best and best / 1000) or nil
    return self._clipCastSec
end

function D:InvalidateClipCastLength()
    self._clipCastSec = nil
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
    self._fillIntent = nil
    self._phase = nil
    if self._engineFill then
        -- The engine fill costs the client nothing while the bar is
        -- hidden: its timer is expired and parked at empty.
        self:_EnginePark(GetTime())
    end
    if self.spark then self.spark:SetVertexColor(1, 1, 1, 0) end
    self._sparkAt = nil
    -- The slice A markers park with the slices: a hidden bar carries no
    -- stripe, no region and no line.
    if self.weave then
        self._weaveX = nil
        self.weave:Hide()
    end
    for _, pair in ipairs({ { self.aim, "_aimW" }, { self.retry, "_retryW" },
        { self.cast, "_castW" }, { self.aimRegion, "_aimRegionW" },
        { self.clip, "_clipW" } }) do
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
    -- Iteration J slice A (§7.1/§7.3/§7.4): the seams slice γ's options page
    -- wires. A key the store does not have yet is inert by the map's law,
    -- so the module defaults above are the shipped behaviour today.
    BarMode = "SetBarMode",
    ShowAimWindow = "SetShowAimWindow",
    ShowClipRegion = "SetShowClipRegion",
    ShowWeaveLine = "SetShowWeaveLine",
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
        "BaseSpeed",
        -- Iteration J slice A: the mode picker and the three markers. A key
        -- the store does not have (slice γ registers them) reads nil and is
        -- skipped, so the module defaults stand -- the login law.
        "BarMode", "ShowAimWindow", "ShowClipRegion", "ShowWeaveLine" },
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
    -- §7.8 slice A item 8: the line names the mode and every marker the bar
    -- is drawing right now, so `/fx status` on the live client says what the
    -- eye is looking at (the mode, the aim region + its alpha, the clip
    -- stripe's width, the weave line's x).
    local markers
    if not self.anchor then
        markers = "markers=not built"
    else
        local function num(v)
            return (type(v) == "number") and string.format("%.1f", v)
                or "off"
        end
        markers = string.format(
            "aimRegion=%s@%.2f clip=%s weave=%s",
            num(self._aimRegionW or 0),
            self._aimRegionA and (tonumber(
                (self._aimRegionA:match("|([%d%.]+)$"))) or 0) or 0,
            num(self._clipW or 0), num(self._weaveX))
    end
    return string.format(
        "Swing bar: %s | %dx%d | %s | %s | fill=%s | mode=%s | %s",
        fraction and string.format("%.0f%% (%.1fs)", fraction * 100, remaining)
            or "idle",
        S.Width, S.Height,
        ST.showTime and "text on" or "text off",
        (self.cfg and self.cfg.locked) and "locked" or "unlocked",
        self._engineFill and "engine" or "lua",
        tostring(ST.barMode or "safe"),
        markers)
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
