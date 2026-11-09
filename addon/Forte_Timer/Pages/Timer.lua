-- addon/Forte_Timer/Pages/Timer.lua
-- The Spell Timer page: the settings of docs/design-spell-timer.md §5.4
-- (Forte_Timer.lua:3310-3427), registered under the index id `SpellTimer`
-- (Forte_Options/UI/Window.lua:46-54 -- the ids are exact and `SpellTimer` is
-- already in the list, so the cell lights up when the page is on) through
-- `FX.Options:RegisterPage`. The layout follows the page law of
-- Forte_Options/Pages/Cooldown.lua and Forte_Hunter/Pages/Hunter.lua verbatim:
-- `b.Tips`, `b.Section(title, fn, { module, keys, tip })` (the per-section
-- recycle icon), `s.CHK/NUM/COL` bound to `{ module, key }`.
--
-- Load-order law (Forte_Hunter/Pages/Hunter.lua:20-27): this chunk is
-- FORTE_TIMER's, and the loader is free to run it before Forte_Options' files
-- -- so NOTHING on FX.Settings / FX.Options is touched at file load. The whole
-- registration is one idempotent function: run at load when those exist, and
-- from `FX.Timer:OnEnable` (PLAYER_LOGIN, after every addon chunk has run)
-- when they do not.
--
-- Lock is the m4 rule (Forte_Cooldown/Module.lua:307-313, Hunter UI/Swing.lua,
-- PLAN §8 Phase 2): the display PUBLISHES its live lock state into
-- SpellTimer.Lock, never the other way, so the checkbox, the header lock icon
-- and `/fx lock|unlock` all agree.
--
-- `Scale` / `Alpha` are wired live (Module.lua's SetScale/SetAlphaValue drive
-- the anchor frame). `ExpandUpwards` is wired too (PLAN §11.8): ticked = the
-- stack grows upward from the first bar's bottom edge, unticked = downward
-- from the first bar's top; the first bar stays where the panel was placed.
-- `ShowTooltips` is stored and labelled as the project's own page law labels
-- it ("not wired yet"): the tooltip is the frozen path of §5.5. Every widget
-- tip lives in `P.WIDGET_TIPS` (one table, the page and
-- the settings-consumer census in tests/test_module.lua read the same text:
-- a tip may claim "Applied live" only where a consumer reads the key).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

local M = "SpellTimer"

FX.Timer = FX.Timer or {}
FX.Timer.Pages = FX.Timer.Pages or {}
local P = FX.Timer.Pages

local DEFAULTS = {
    Enable = true,
    Lock = true,
    -- Frame Sizing. `Scale`/`Alpha` are the Cooldown page's general keys,
    -- resolved on the FX.Options:Options() side (Forte_Options
    -- Pages/Cooldown.lua:169-175), so the page exposes them and the display
    -- reads them; geometry keys are live.
    Scale = 1.0,
    Alpha = 1.0,
    Width = 250,
    Height = 14,
    Space = 2,
    Spacing = 2,
    -- `Max = {[0]=false,15}` (Forte_Timer.lua:3315): the row cap rides its OWN
    -- gate, and the shipped gate is OFF with the value 15. The gate is our
    -- `MaxOn`, the value our `Max` -- both rows are on the page, so the pair
    -- can not drift from the source's one row (the options survey's
    -- "Max shown" default drift, docs/research/options-fidelity.md).
    MaxOn = false,
    Max = 15,
    -- `LabelHeight = 18` (:3344, the "Unit label height" row :3242): the strip
    -- the group's unit header rides inside.
    LabelHeight = 18,
    -- The layout direction pair, Basics :3148-3149: `Outwands = true`
    -- (:3333, "Highest timers outwards" -- the sort runs the longest times
    -- furthest from the anchor) and `Flip = false` (:3332, "Flip bar
    -- direction" -- the fill's direction).
    Outwands = true,
    Flip = false,
    -- Display rules
    ShowTargetNames = true,
    ShowID = false,
    ShowSpellNames = false,
    MaxDisplayTime = 30,
    ExpandUpwards = true,
    NormalAlpha = 0.5,
    BarBackgroundAlpha = 0.3,
    Label = true,
    EnableSpark = true,
    EnableBackdrop = true,
    SmartSpace = true,
    IconStacks = true,
    ShowStacks = true,
    ShowTicks = true,
    -- `TicksNext = true` (:3404, the "Next Tick only" row :3182): one mark,
    -- the next tick of the schedule, not the whole schedule.
    TicksNext = true,
    -- The Fading section (:3192-3199): `FadeTime = 1` (:3339, "Standard fade
    -- delay" -- the ghost time a row rides past its window) and
    -- `Blink = {[0]=true,3}` (:3335, "Blink expiring bars" -- the source's
    -- expiry cue is the alpha pulse, :1562-1569, not a colour change).
    FadeTime = 1,
    Blink = true,
    BlinkTime = 3,
    ShowTooltips = true,
    AltTimeFormat = false,
    -- The colour law (§5.4): the text/flash/expired entries ride the Skin's
    -- source rows (NormalColor :3396, Fail :3375, ExpiredColor :3371); the
    -- five BarColor* are stored for the per-caster question -- the source
    -- colours bars PER CATEGORY (ColorVal :1524-1573). The Skin's own
    -- defaults are the single truth: the store default can not drift from
    -- the renderer.
    ColourNormal = (FX.Timer.Skin and FX.Timer.Skin.NormalColor)
        or { 1.0, 1.0, 1.0 },
    ColourExpiry = (FX.Timer.Skin and FX.Timer.Skin.ColourExpiry)
        or { 0.25, 1.0, 0.25 },
    ColourFlash = (FX.Timer.Skin and FX.Timer.Skin.ColourFlash)
        or { 1.0, 0.25, 0.25 },
    -- `ExpiredColor = {[0]=false,0.50,0.50,0.50,1.00}` (:3371): a row past its
    -- end rides the CATEGORY colour by default; the grey is behind the gate,
    -- and the gate ships OFF. The triple is the Skin's own `ExpiredColor`, the
    -- value ColorVal reads (:1560-1561) -- the store default can not drift.
    ExpiredColor = false,
    ColourExpired = (FX.Timer.Skin and FX.Timer.Skin.ExpiredColor)
        or { 0.50, 0.50, 0.50, 1.00 },
    BarColorSelf = (FX.Timer.Skin and FX.Timer.Skin.BarColorSelf)
        or { 0.99, 0.82, 0.34 },
    BarColorTarget = (FX.Timer.Skin and FX.Timer.Skin.BarColorTarget)
        or { 0.25, 0.55, 1.0 },
    BarColorFocus = (FX.Timer.Skin and FX.Timer.Skin.BarColorFocus)
        or { 1.0, 0.25, 0.25 },
    BarColorPet = (FX.Timer.Skin and FX.Timer.Skin.BarColorPet)
        or { 0.25, 1.0, 0.25 },
    BarColorEnemy = (FX.Timer.Skin and FX.Timer.Skin.BarColorEnemy)
        or { 1.0, 0.25, 0.25 },
    -- Position (the 14 px icon slot + the 3 px backdrop, §5.4). The offsets
    -- are EXTRA x on top of the shared inset law (:2322), so the Classic
    -- defaults are zero: every row rides IconOffset.
    IconOffset = 18,
    OffsetSelf = 0,
    OffsetTarget = 0,
    -- The expire-message channel (:1049-1056): the source ships its announce
    -- pages dimmed, so the gate defaults off (m7).
    AnnounceExpiry = false,
}

-- The widget tips, one table, keyed by settings key: the widgets below and
-- the settings-consumer census (tests/test_module.lua) read the SAME text.
-- A tip that says "Applied live" claims a consumer; the census fails the
-- build when a live-claiming key has none. Keys whose law is not wired say
-- "Not wired yet (stored)" (the General page's FrameSnap/ShowTooltips
-- honesty, Pages/General.lua:10-12).
FX.Timer.Pages.WIDGET_TIPS = {
    Enable = "Show the stack. Off hides it live.",
    Lock = "Lock the stack against dragging (moves with /fx lock|unlock and "
        .. "Global Frame Lock).",
    Label = "The target name above each group's box. Off moves the raid mark "
        .. "onto the bars (Forte_Timer.lua:2351-2364). Applied live.",
    ShowTargetNames = "Label the rows with the target's name; off labels "
        .. "them with the spell name. Applied live.",
    ShowSpellNames = "Label the rows with the spell name instead of the "
        .. "target (the source's own spell mode, :2391). Applied live.",
    ShowID = "Prefix the label with #<id> (the source's ShowID, "
        .. ":2517-2521). Applied live.",
    Width = "Row width in px (default 250). The bar is Width - Height - 1 "
        .. "because the icon sits OUTSIDE it. Resizes live.",
    Height = "Row height in px (default 14) -- also the icon size, the row "
        .. "x-inset and the group padding. Resizes live.",
    Space = "Space between the rows inside a group (default 2, :3364). "
        .. "Applied live.",
    Spacing = "Space between two groups (default 2, :3345). Applied live.",
    Max = "Rows drawn while the row cap is on (the Classic default 15, "
        .. ":3315 -- the value half of the source's one `Max = {[0]=false,15}` "
        .. "row). Long rows are always sorted last, so the cap drops only "
        .. "dead ones (:3449-3452). Applied live.",
    MaxOn = "The `[0]` gate of the source's `Max = {[0]=false,15}` row "
        .. "(:3315): with it off every row of the stack is drawn. The Classic "
        .. "build ships it OFF. Applied live.",
    LabelHeight = "The height of the unit labels between the bars (the "
        .. "'Unit label height' row :3242, default 18 :3344): the strip the "
        .. "group header rides inside, so it reserves the room above the "
        .. "group's topmost bar. Resizes live.",
    Outwands = "Highest timers outwards (:3148, default true :3333): the "
        .. "longest remaining times ride furthest from the anchor, so the "
        .. "rows that expire soonest sit nearest it. Applied live.",
    Flip = "Flip bar direction (:3149, default false :3332): the fill grows "
        .. "from the RIGHT and shrinks from the LEFT, and the spark (:2536-"
        .. "2540) and the tick marks (:1797/:1806) mirror with it. Applied "
        .. "live.",
    Scale = "Frame scale of this panel (drives the anchor live, "
        .. "Module:SetScale). Applied live.",
    Alpha = "Frame alpha of this panel (drives the anchor live, "
        .. "Module:SetAlphaValue). Applied live.",
    MaxDisplayTime = "The compressed scale: a row whose total is longer than "
        .. "this fills proportionally (taller rows fill slower -- the source's "
        .. "own MaxTime rule, :2164-2169). Default 30. Applied live.",
    NormalAlpha = "Alpha of the rows that are not the target's (default "
        .. "0.50, :3366). Applied live.",
    BarBackgroundAlpha = "Alpha of the row background behind the bar "
        .. "(default 0.30). Applied live.",
    EnableSpark = "The leading-edge spark on the bar and the icon "
        .. "(Forte_Timer.lua:1712). Applied live.",
    EnableBackdrop = "The per-target box (Background/Border, edge 3, "
        .. ":3414-3417) is the Classic law and always drawn in v1. Not wired "
        .. "yet (stored).",
    SmartSpace = "The time column is as wide as the widest time text in the "
        .. "group, so the names centre (Forte_Timer.lua:2489-2510). Applied "
        .. "live.",
    IconStacks = "Print the stack count on the icon's corner (:1696-1698, "
        .. "the IconStacks gate :2467). Applied live.",
    ShowStacks = "Suffix the label with (n) (:2517-2523); off drops the "
        .. "suffix. Applied live.",
    ShowTicks = "Mark the data's tick schedule on the bar (:1613-1627). "
        .. "DISPLAY ONLY -- real tick detection is log-only and the log is "
        .. "closed. Applied live.",
    TicksNext = "Next Tick only (:3182, default true :3404): of the schedule "
        .. "ShowTicks marks, draw the ONE that fires next -- the step at the "
        .. "fill's live edge (the source's `TicksNext` branch, :1775-1791) -- "
        .. "instead of every remaining step. Applied live.",
    FadeTime = "Standard fade delay (:3193, default 1 :3339), the source's "
        .. "'ghost time': a row rides its full visibility this long past the "
        .. "end of its window, then the fade-out ramp runs (the "
        .. "`Alpha(removeAt + FadeTime, t)` law, :2166). Applied live.",
    Blink = "Blink expiring bars (:3195, the `[0]` of `Blink = {[0]=true,3}` "
        .. ":3335 -- the Classic build ships it ON): the rows' backgrounds "
        .. "pulse as their window runs out (:1562-1569). The source has no "
        .. "about-to-expire COLOUR -- the pulse is its expiry cue. Applied "
        .. "live.",
    BlinkTime = "Blink expiring bars, the seconds half of the same row "
        .. "(:3335, 3): a row starts its pulse with this much of its window "
        .. "left. Applied live.",
    ShowTooltips = "The hover tooltip law (:1730-1759, C_TooltipInfo + "
        .. "C_Tooltip on hover) has no panel tooltip yet -- the frozen path "
        .. "of design §5.5. Not wired yet (stored).",
    AltTimeFormat = "Print mm:ss once the remaining time passes a minute "
        .. "(the source's AltTimeFormat, :2476). Applied live.",
    AnnounceExpiry = "The source's expire-message channel (:1049-1056): "
        .. "print a chat line when a row's window ends; rows born while off "
        .. "stay silent. The source ships its announce pages dimmed, so this "
        .. "defaults off. Applied live.",
    ExpandUpwards = "Ticked (the default) the stack grows upward from the "
        .. "first bar's position; unticked it grows downward from it, the "
        .. "first bar staying exactly where you placed the panel and later "
        .. "bars appearing below it (:3321). Applied live.",
    ColourNormal = "The row TEXT colour -- the source's NormalColor (:3396: "
        .. "the time text :1856, the group label :2073, the names :2528), "
        .. "de-saturated over a bright fill. Applied live.",
    ColourExpiry = "The source has no colour band for the last seconds -- "
        .. "the expiry cue is the Blink alpha pulse (:1562-1569) and the "
        .. "past-the-end colour is the Expired colour below. Not wired yet "
        .. "(stored).",
    ColourFlash = "The flash band -- a failed row, the `Fail` colour "
        .. "(:3375) over the FailTime seconds (:3338, 2). Applied live.",
    ColourExpired = "A row past its end, the grey of `ExpiredColor` (:3371) "
        .. "-- the source's Expired row (:1560-1561), off by default behind "
        .. "the gate below. Applied live.",
    ExpiredColor = "Expired (:3197, the `[0]` gate of `ExpiredColor = "
        .. "{[0]=false,0.5,0.5,0.5,1}` :3371): OFF by the Classic default, a "
        .. "row past its end keeps its category colour; ON, it takes the "
        .. "expired colour above. Applied live.",
    BarColorSelf = "The source colours bars PER CATEGORY (ColorVal "
        .. ":1524-1573); a per-caster bar law is the open phase question "
        .. "(design §3.6). Not wired yet (stored).",
    BarColorTarget = "The source colours bars PER CATEGORY (ColorVal "
        .. ":1524-1573); a per-caster bar law is the open phase question "
        .. "(design §3.6). Not wired yet (stored).",
    BarColorFocus = "The source colours bars PER CATEGORY (ColorVal "
        .. ":1524-1573); a per-caster bar law is the open phase question "
        .. "(design §3.6). Not wired yet (stored).",
    BarColorPet = "The source colours bars PER CATEGORY (ColorVal "
        .. ":1524-1573); a per-caster bar law is the open phase question "
        .. "(design §3.6). Not wired yet (stored).",
    BarColorEnemy = "The source colours bars PER CATEGORY (ColorVal "
        .. ":1524-1573); a per-caster bar law is the open phase question "
        .. "(design §3.6). Not wired yet (stored).",
    IconOffset = "The row x-inset inside the group box (default 18 = Height "
        .. "+ 1 + 3, :2322). Applied live.",
    OffsetSelf = "Extra x-offset of your own rows, added to the row x-inset "
        .. "(the port's own knob; the source has the one shared inset law "
        .. ":2322). Applied live.",
    OffsetTarget = "Extra x-offset of your target's rows, added to the row "
        .. "x-inset (the port's own knob; the source has the one shared inset "
        .. "law :2322). Applied live.",
}
local TIPS = FX.Timer.Pages.WIDGET_TIPS

local function display()
    return FX.Timer and FX.Timer.Display
end

local wired = false
--- The page-side mirror of FX.Timer:ApplySettings (Module.lua): every key of
--- this module reaches the display through that one seam, so the page is not a
--- second law. Idempotent with the module's own self-wiring.
local function ensureWiring()
    if wired then return end
    wired = true
    FX.Settings:OnChange(M, function(key, value)
        local d = FX.Timer
        if d and d.ApplySettings then d:ApplySettings({ [key] = value }) end
    end)
    -- The m4 rule: publish the live lock state before the checkbox reads it.
    local disp = display()
    if disp and disp.cfg and disp.cfg.locked ~= nil then
        local live = disp.cfg.locked and true or false
        if FX.Settings:Get(M, "Lock") ~= live then
            FX.Settings:Set(M, "Lock", live)
        end
    end
end

--- Register the defaults + the page. Idempotent; needs FX.Settings +
--- FX.Options. Returns true when the page is registered.
function P.RegisterTimerPage()
    local O = FX.Options
    if not O or not O.pages or not FX.Settings then return false end
    if not O.pages[M] then
        FX.Settings:Register(M, DEFAULTS)
        O:RegisterPage({
            id = M,
            module = M,
            title = "Spell Timer",
            colour = O.C.BROWN,
            lockKey = "Lock",
            -- C4: the page hands its live lock frame to the header glyph
            -- (Forte_Options/UI/Window.lua's def.lockFrame resolver) -- the
            -- icon reads the frame THIS module owns, not the Cooldown bar's.
            lockFrame = display,
            build = function(b)
                ensureWiring()
                b.Tips({
                    "Each bar predicts one of YOUR spells on one unit, from the cast; a confirmed cast refreshes it.",
                    "The bar ends at the spell's natural end -- a buff reapplied early just restarts the countdown (v1 is one row per spell+unit).",
                    "Out of combat the real aura data fixes any bar that drifted; in combat the data is sealed and every bar is a prediction.",
                    "The rows are labelled PREDICTED: a bar whose buff the addon has not seen land carries a notch at its right end.",
                    "Drag a bar with Lock off; the position is saved per character.",
                    "/fx lock and /fx unlock move this stack with the Cooldown and Hunter bars.",
                })
                b.Section("Basics", function(s)
                    s.CHK({ module = M, key = "Enable",
                        label = "Enable spell timers", tip = TIPS.Enable })
                    s.CHK({ module = M, key = "Lock", label = "Lock",
                        tip = TIPS.Lock })
                    s.CHK({ module = M, key = "Label",
                        label = "Show name tags/headers", tip = TIPS.Label })
                    s.CHK({ module = M, key = "ShowTargetNames",
                        label = "Show target names",
                        tip = TIPS.ShowTargetNames })
                    s.CHK({ module = M, key = "ShowSpellNames",
                        label = "Show spell names",
                        tip = TIPS.ShowSpellNames })
                    s.CHK({ module = M, key = "ShowID",
                        label = "Show unit #", tip = TIPS.ShowID })
                    -- The two layout-direction rows of the source's Basics
                    -- (:3148-3149), in its order.
                    s.CHK({ module = M, key = "Outwands",
                        label = "Highest timers outwards",
                        tip = TIPS.Outwands })
                    s.CHK({ module = M, key = "Flip",
                        label = "Flip bar direction", tip = TIPS.Flip })
                end, {
                    module = M,
                    keys = { "Enable", "Lock", "Label", "ShowTargetNames",
                        "ShowSpellNames", "ShowID", "Outwands", "Flip" },
                    tip = "The master switches and the row labels.",
                })
                b.Section("Frame Sizing", function(s)
                    s.NUM({ module = M, key = "Width", label = "Width",
                        min = 120, max = 640, step = 1, tip = TIPS.Width })
                    s.NUM({ module = M, key = "Height", label = "Height",
                        min = 8, max = 40, step = 1, tip = TIPS.Height })
                    s.NUM({ module = M, key = "Space", label = "Space",
                        min = 0, max = 12, step = 1, tip = TIPS.Space })
                    s.NUM({ module = M, key = "Spacing", label = "Spacing",
                        min = 0, max = 12, step = 1, tip = TIPS.Spacing })
                    -- The source's SIZING rows (:3241-3244): the unit label
                    -- height, then the `NU2` row "Maximum shown" -- its gate
                    -- and its value as our two keys.
                    s.NUM({ module = M, key = "LabelHeight",
                        label = "Unit label height",
                        min = 0, max = 48, step = 1,
                        tip = TIPS.LabelHeight })
                    s.CHK({ module = M, key = "MaxOn",
                        label = "Limit rows shown", tip = TIPS.MaxOn })
                    s.NUM({ module = M, key = "Max", label = "Maximum shown",
                        min = 4, max = 64, step = 1, tip = TIPS.Max })
                    s.NUM({ module = M, key = "Scale", label = "Scale",
                        min = 0.5, max = 2.0, step = 0.05,
                        tip = TIPS.Scale })
                    s.NUM({ module = M, key = "Alpha", label = "Alpha",
                        min = 0.2, max = 1.0, step = 0.05,
                        tip = TIPS.Alpha })
                end, {
                    module = M,
                    keys = { "Width", "Height", "Space", "Spacing",
                        "LabelHeight", "MaxOn", "Max", "Scale", "Alpha" },
                    tip = "Sizes of the stack. The recycle icon restores the Classic defaults.",
                })
                b.Section("Display Rules", function(s)
                    s.NUM({ module = M, key = "MaxDisplayTime",
                        label = "Max display time (s)",
                        min = 5, max = 120, step = 1,
                        tip = TIPS.MaxDisplayTime })
                    s.NUM({ module = M, key = "NormalAlpha",
                        label = "Normal alpha",
                        min = 0.1, max = 1.0, step = 0.05,
                        tip = TIPS.NormalAlpha })
                    s.NUM({ module = M, key = "BarBackgroundAlpha",
                        label = "Bar background alpha",
                        min = 0.0, max = 1.0, step = 0.05,
                        tip = TIPS.BarBackgroundAlpha })
                    s.CHK({ module = M, key = "EnableSpark",
                        label = "Enable sparks", tip = TIPS.EnableSpark })
                    s.CHK({ module = M, key = "EnableBackdrop",
                        label = "Enable group backdrop",
                        tip = TIPS.EnableBackdrop })
                    s.CHK({ module = M, key = "SmartSpace",
                        label = "Smart space", tip = TIPS.SmartSpace })
                    s.CHK({ module = M, key = "IconStacks",
                        label = "Stacks on the icon",
                        tip = TIPS.IconStacks })
                    s.CHK({ module = M, key = "ShowStacks",
                        label = "Stacks in the label",
                        tip = TIPS.ShowStacks })
                    s.CHK({ module = M, key = "ShowTicks",
                        label = "Show tick marks", tip = TIPS.ShowTicks })
                    s.CHK({ module = M, key = "TicksNext",
                        label = "Next Tick only", tip = TIPS.TicksNext })
                    s.CHK({ module = M, key = "ShowTooltips",
                        label = "Show tooltips", tip = TIPS.ShowTooltips })
                    s.CHK({ module = M, key = "AltTimeFormat",
                        label = "mm:ss above a minute",
                        tip = TIPS.AltTimeFormat })
                    s.CHK({ module = M, key = "AnnounceExpiry",
                        label = "Announce expiries (chat)",
                        tip = TIPS.AnnounceExpiry })
                    s.CHK({ module = M, key = "ExpandUpwards",
                        label = "Expand up", tip = TIPS.ExpandUpwards })
                end, {
                    module = M,
                    keys = { "MaxDisplayTime", "NormalAlpha",
                        "BarBackgroundAlpha", "EnableSpark", "EnableBackdrop",
                        "SmartSpace", "IconStacks", "ShowStacks", "ShowTicks",
                        "TicksNext",
                        "ShowTooltips", "AltTimeFormat", "AnnounceExpiry",
                        "ExpandUpwards" },
                    tip = "The display law of the stack.",
                })
                -- The source's FADING subcategory (:3192-3199), in its order
                -- and with its labels: the fade delay, then the Blink pair.
                b.Section("Fading", function(s)
                    s.NUM({ module = M, key = "FadeTime",
                        label = "Standard fade delay (s)",
                        min = 0, max = 120, step = 1, tip = TIPS.FadeTime })
                    s.CHK({ module = M, key = "Blink",
                        label = "Blink expiring bars", tip = TIPS.Blink })
                    s.NUM({ module = M, key = "BlinkTime",
                        label = "Blink when under (s)",
                        min = 0, max = 30, step = 1, tip = TIPS.BlinkTime })
                end, {
                    module = M,
                    keys = { "FadeTime", "Blink", "BlinkTime" },
                    tip = "How a row leaves: the ghost time, the fade ramp and the Blink pulse (:1557-1569).",
                })
                b.Section("Coloring", function(s)
                    s.COL({ module = M, key = "ColourNormal",
                        label = "Normal colour", tip = TIPS.ColourNormal })
                    s.COL({ module = M, key = "ColourExpiry",
                        label = "About-to-expire colour",
                        tip = TIPS.ColourExpiry })
                    s.COL({ module = M, key = "ColourFlash",
                        label = "Flash colour", tip = TIPS.ColourFlash })
                    s.COL({ module = M, key = "ColourExpired",
                        label = "Expired colour", tip = TIPS.ColourExpired })
                    -- The CO2 row's own gate (:3197, `[0]` of :3371): the
                    -- Classic build ships the grey EXPIRED colour OFF.
                    s.CHK({ module = M, key = "ExpiredColor",
                        label = "Tint expired rows",
                        tip = TIPS.ExpiredColor })
                    s.COL({ module = M, key = "BarColorSelf",
                        label = "Self rows", tip = TIPS.BarColorSelf })
                    s.COL({ module = M, key = "BarColorTarget",
                        label = "Target rows", tip = TIPS.BarColorTarget })
                    s.COL({ module = M, key = "BarColorFocus",
                        label = "Focus rows", tip = TIPS.BarColorFocus })
                    s.COL({ module = M, key = "BarColorPet",
                        label = "Pet rows", tip = TIPS.BarColorPet })
                    s.COL({ module = M, key = "BarColorEnemy",
                        label = "Hostile rows", tip = TIPS.BarColorEnemy })
                end, {
                    module = M,
                    keys = { "ColourNormal", "ColourExpiry", "ColourFlash",
                        "ColourExpired", "ExpiredColor",
                        "BarColorSelf", "BarColorTarget",
                        "BarColorFocus", "BarColorPet", "BarColorEnemy" },
                    tip = "The colour law (docs/design-spell-timer.md §3.6).",
                })
                b.Section("Position", function(s)
                    s.NUM({ module = M, key = "IconOffset",
                        label = "Icon offset",
                        min = 0, max = 48, step = 1,
                        tip = TIPS.IconOffset })
                    s.NUM({ module = M, key = "OffsetSelf",
                        label = "Self offset",
                        min = 0, max = 48, step = 1,
                        tip = TIPS.OffsetSelf })
                    s.NUM({ module = M, key = "OffsetTarget",
                        label = "Target offset",
                        min = 0, max = 48, step = 1,
                        tip = TIPS.OffsetTarget })
                end, {
                    module = M,
                    keys = { "IconOffset", "OffsetSelf", "OffsetTarget" },
                    tip = "The offsets inside the group box.",
                })
            end,
        })
    end
    return FX.Options.pages[M] ~= nil
end

-- The load-time fast path: Forte_Options ran first (the loader honoured the
-- OptionalDeps), so register right now. Otherwise FX.Timer:OnEnable
-- (PLAYER_LOGIN) calls the same function once every addon chunk has run.
P.RegisterTimerPage()
