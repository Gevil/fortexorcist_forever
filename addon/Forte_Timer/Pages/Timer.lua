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
-- `Scale` / `Alpha` / `ExpandUpwards` / `ShowTooltips` are stored and labelled
-- as the project's own page law labels them ("not wired yet"): v1 growth is
-- fixed upward (design §5.4) and the tooltip is the frozen path of §5.5.

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
    Max = 32,
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
    ShowTooltips = true,
    AltTimeFormat = false,
    -- Colour law (§5.4, the Skin triples at Forte_Timer.lua:3348-3351 and the
    -- per-unit bar colours at :3387-3391). The Skin's own defaults are the
    -- single truth: the store default can not drift from the renderer.
    ColourNormal = (FX.Timer.Skin and FX.Timer.Skin.ColourNormal)
        or { 0.25, 0.55, 1 },
    ColourExpiry = (FX.Timer.Skin and FX.Timer.Skin.ColourExpiry)
        or { 0.25, 1.0, 0.25 },
    ColourFlash = (FX.Timer.Skin and FX.Timer.Skin.ColourFlash)
        or { 1.0, 0.25, 0.25 },
    ColourExpired = (FX.Timer.Skin and FX.Timer.Skin.ColourExpired)
        or { 1.0, 1.0, 1.0 },
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
    -- Position (the 14 px icon slot + the 3 px backdrop, §5.4)
    IconOffset = 18,
    OffsetSelf = 18,
    OffsetTarget = 18,
}

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
                        label = "Enable spell timers",
                        tip = "Show the stack. Off hides it live." })
                    s.CHK({ module = M, key = "Lock", label = "Lock",
                        tip = "Lock the stack against dragging (moves with /fx lock|unlock and Global Frame Lock)." })
                    s.CHK({ module = M, key = "Label",
                        label = "Show group labels",
                        tip = "The target name above each group's box. Off moves the raid mark onto the bars (Forte_Timer.lua:2351-2364). Applied live." })
                    s.CHK({ module = M, key = "ShowTargetNames",
                        label = "Show target names",
                        tip = "Label the rows with the target's name; off labels them with the spell name. Applied live." })
                    s.CHK({ module = M, key = "ShowSpellNames",
                        label = "Show spell names",
                        tip = "Label the rows with the spell name instead of the target (the source's own spell mode, :2391). Applied live." })
                    s.CHK({ module = M, key = "ShowID",
                        label = "Show the buff id",
                        tip = "Prefix the label with #<id> (the source's ShowID, :2517-2521). Applied live." })
                end, {
                    module = M,
                    keys = { "Enable", "Lock", "Label", "ShowTargetNames",
                        "ShowSpellNames", "ShowID" },
                    tip = "The master switches and the row labels.",
                })
                b.Section("Frame Sizing", function(s)
                    s.NUM({ module = M, key = "Width", label = "Width",
                        min = 120, max = 640, step = 1,
                        tip = "Row width in px (default 250). The bar is Width - Height - 1 because the icon sits OUTSIDE it. Resizes live." })
                    s.NUM({ module = M, key = "Height", label = "Height",
                        min = 8, max = 40, step = 1,
                        tip = "Row height in px (default 14) -- also the icon size, the row x-inset and the group padding. Resizes live." })
                    s.NUM({ module = M, key = "Space", label = "Space",
                        min = 0, max = 12, step = 1,
                        tip = "Space between the rows inside a group (default 2, :3364). Applied live." })
                    s.NUM({ module = M, key = "Spacing", label = "Spacing",
                        min = 0, max = 12, step = 1,
                        tip = "Space between two groups (default 2, :3345). Applied live." })
                    s.NUM({ module = M, key = "Max", label = "Max rows",
                        min = 4, max = 64, step = 1,
                        tip = "Rows drawn (default 32, :3320). Long rows are always sorted last, so the cap drops only dead ones (:3449-3452). Applied live." })
                    s.NUM({ module = M, key = "Scale", label = "Scale",
                        min = 0.5, max = 2.0, step = 0.05,
                        tip = "Frame scale (general key, applied by the window). Applied live." })
                    s.NUM({ module = M, key = "Alpha", label = "Alpha",
                        min = 0.2, max = 1.0, step = 0.05,
                        tip = "Frame alpha (general key, applied by the window). Applied live." })
                end, {
                    module = M,
                    keys = { "Width", "Height", "Space", "Spacing", "Max",
                        "Scale", "Alpha" },
                    tip = "Sizes of the stack. The recycle icon restores the Classic defaults.",
                })
                b.Section("Display Rules", function(s)
                    s.NUM({ module = M, key = "MaxDisplayTime",
                        label = "Max display time (s)",
                        min = 5, max = 120, step = 1,
                        tip = "The compressed scale: a row whose total is longer than this fills proportionally (taller rows fill slower -- the source's own MaxTime rule, :2164-2169). Default 30. Applied live." })
                    s.NUM({ module = M, key = "NormalAlpha",
                        label = "Normal alpha",
                        min = 0.1, max = 1.0, step = 0.05,
                        tip = "Alpha of the rows that are not the target's (default 0.50, :3366). Applied live." })
                    s.NUM({ module = M, key = "BarBackgroundAlpha",
                        label = "Bar background alpha",
                        min = 0.0, max = 1.0, step = 0.05,
                        tip = "Alpha of the row background behind the bar (default 0.30). Applied live." })
                    s.CHK({ module = M, key = "EnableSpark",
                        label = "Enable sparks",
                        tip = "The leading-edge spark on the bar and the icon (Forte_Timer.lua:1712). Applied live." })
                    s.CHK({ module = M, key = "EnableBackdrop",
                        label = "Enable group backdrop",
                        tip = "Draw the per-target box (Background/Border, edge 3, :3414-3417). Applied live." })
                    s.CHK({ module = M, key = "SmartSpace",
                        label = "Smart space",
                        tip = "The time column is as wide as the widest time text in the group, so the names centre (Forte_Timer.lua:2489-2510). Applied live." })
                    s.CHK({ module = M, key = "IconStacks",
                        label = "Stacks on the icon",
                        tip = "Print the stack count on the icon's corner (:1696-1698). Applied live." })
                    s.CHK({ module = M, key = "ShowStacks",
                        label = "Stacks in the label",
                        tip = "Suffix the label with (n) (:2517-2523). Applied live." })
                    s.CHK({ module = M, key = "ShowTicks",
                        label = "Show tick marks",
                        tip = "Mark the data's tick schedule on the bar (:1613-1627). DISPLAY ONLY -- real tick detection is log-only and the log is closed. Applied live." })
                    s.CHK({ module = M, key = "ShowTooltips",
                        label = "Show tooltips",
                        tip = "The hover tooltip law (:1730-1759, C_TooltipInfo + C_Tooltip on hover). Applied live." })
                    s.CHK({ module = M, key = "AltTimeFormat",
                        label = "mm:ss above a minute",
                        tip = "Print mm:ss once the remaining time passes a minute (the source's AltTimeFormat, :2476). Applied live." })
                    s.CHK({ module = M, key = "ExpandUpwards",
                        label = "Grow upwards",
                        tip = "The Classic cascade grows upward from the frame's bottom edge (:3321). v1 is always upward; the key is stored for the layout work." })
                end, {
                    module = M,
                    keys = { "MaxDisplayTime", "NormalAlpha",
                        "BarBackgroundAlpha", "EnableSpark", "EnableBackdrop",
                        "SmartSpace", "IconStacks", "ShowStacks", "ShowTicks",
                        "ShowTooltips", "AltTimeFormat", "ExpandUpwards" },
                    tip = "The display law of the stack.",
                })
                b.Section("Coloring", function(s)
                    s.COL({ module = M, key = "ColourNormal",
                        label = "Normal colour",
                        tip = "A spell burning normally (:3348). Applied live." })
                    s.COL({ module = M, key = "ColourExpiry",
                        label = "About-to-expire colour",
                        tip = "The expiry band -- the last second, 10% of the total, min 4 s / max 10 s (:3349, :2462). Applied live." })
                    s.COL({ module = M, key = "ColourFlash",
                        label = "Flash colour",
                        tip = "The flash band -- the last 2 s (:3350). Applied live." })
                    s.COL({ module = M, key = "ColourExpired",
                        label = "Expired colour",
                        tip = "A row past its end, greyed and faded over a second (:3351, :2364). Applied live." })
                    s.COL({ module = M, key = "BarColorSelf",
                        label = "Self rows",
                        tip = "The bar colour of your own buffs (:3387). Applied live." })
                    s.COL({ module = M, key = "BarColorTarget",
                        label = "Target rows",
                        tip = "The bar colour of buffs on your target (:3388). Applied live." })
                    s.COL({ module = M, key = "BarColorFocus",
                        label = "Focus rows",
                        tip = "The bar colour of buffs on your focus (:3389). Applied live." })
                    s.COL({ module = M, key = "BarColorPet",
                        label = "Pet rows",
                        tip = "The bar colour of pet rows (:3390). Applied live." })
                    s.COL({ module = M, key = "BarColorEnemy",
                        label = "Hostile rows",
                        tip = "The bar colour of buffs on a hostile unit (:3391). Applied live." })
                end, {
                    module = M,
                    keys = { "ColourNormal", "ColourExpiry", "ColourFlash",
                        "ColourExpired", "BarColorSelf", "BarColorTarget",
                        "BarColorFocus", "BarColorPet", "BarColorEnemy" },
                    tip = "The colour law (docs/design-spell-timer.md §3.6).",
                })
                b.Section("Position", function(s)
                    s.NUM({ module = M, key = "IconOffset",
                        label = "Icon offset",
                        min = 0, max = 48, step = 1,
                        tip = "The row x-inset inside the group box (default 18 = Height + 1 + 3, :2322). Applied live." })
                    s.NUM({ module = M, key = "OffsetSelf",
                        label = "Self offset",
                        min = 0, max = 48, step = 1,
                        tip = "Extra x-offset of your own rows (:3411). Applied live." })
                    s.NUM({ module = M, key = "OffsetTarget",
                        label = "Target offset",
                        min = 0, max = 48, step = 1,
                        tip = "Extra x-offset of your target's rows (:3412). Applied live." })
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
