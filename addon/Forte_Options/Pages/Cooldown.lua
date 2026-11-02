-- Forte_Options/Pages/Cooldown.lua
-- The Cooldown Timer page (sections Some Tips / Basics / Specifics /
-- Coloring / Frame Appearance). Defaults mirror the design law, PLAN §3.5
-- (Forte_Cooldown.lua :1801-1866): one 250x24 power-scale bar, Max 300,
-- Loga 0.33, tags "0 1 10 30 60 120 300 600", IgnoreCooldown 2.99, verbatim
-- category colours.
--
-- Wiring: every key on this page drives FX.Cooldown.Display live (see the
-- contract at the seam below); IgnoreShort drives Engine.MIN_COOLDOWN.
-- No key of this page is stored-only any more.
--
-- CD-35/CD-31 (2026-11-02): the three geometry rows of the original's Basics
-- block (Vertical :1705, Flip :1706, "Auto-hide when no cooldowns" :1707) and
-- its Specifics Warn row (:1714) joined the page, at the shipped defaults
-- (:1808/:1809/:1815/:1821) and with the original's own labels
-- (Localization.lua :108-111, :158-159, :510-511). All four are live through
-- Display:ApplySettings -> SetVertical / SetFlip / SetHideZero / SetWarn.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local O = FX.Options

local M = "Cooldown"

FX.Settings:Register(M, {
    -- Basics (the original's BASICS rows, Forte_Cooldown.lua :1704-1708:
    -- Enable, "Flip to vertical", "Flip bar direction", "Auto-hide when no
    -- cooldowns", "Hide when not in combat"; defaults :1808/:1809/:1815/:1816)
    Enable = true,
    Lock = true,
    Vertical = false,
    Flip = false,
    HideZero = false,
    HideCombat = false,
    -- Specifics (PLAN §3.5 + the SPECIFICS row :1714 "Spell on cooldown
    -- Warning", default Warn = true :1821)
    Warn = true,
    Width = 250,
    Height = 24,
    MaxTime = 300,
    PowerScale = 0.33,                 -- Loga
    TimeTags = "0 1 10 30 60 120 300 600",
    IgnoreShort = 2.99,                -- Engine.MIN_COOLDOWN
    -- The item/weapon proc ICD windows (Core/Procs.lua). NO PAGE ROW (the
    -- 2026-11-02 ruling: the feature ships behind the flag, not behind a
    -- checkbox): the key is registered so the store owns the default -- OFF,
    -- per docs/design-combat-procs.md P-B -- and so `/fx procs on` writes it
    -- through FX.Settings:Set like every other key. The switch is live
    -- through Procs:_WireSettings' listener; Procs:ApplyStoredSettings
    -- applies it at login. Flipping it on loads the load-on-demand
    -- Forte_ItemProcs data add-on (docs/perf.md §4 fix 1), which is the
    -- whole reason it is not on by default.
    Procs = false,
    -- Coloring (Forte_Cooldown.lua :1842-1855, verbatim)
    ColorSpell     = { 1.00, 0.50, 0.00, 1 },
    ColorPowerup   = { 0.00, 0.75, 1.00, 1 },
    ColorItem      = { 1.00, 1.00, 0.00, 1 },
    ColorPotion    = { 0.00, 1.00, 0.00, 1 },
    ColorPet       = { 1.00, 0.00, 0.95, 1 },
    ColorInternal  = { 0.00, 0.60, 0.85, 1 },
    ColorBuff      = { 1.00, 1.00, 1.00, 1 },
    ColorDebuff    = { 1.00, 0.00, 0.00, 1 },
    -- Frame Appearance (BarColor / BgColor / Spark, :1820 + §3.5)
    BarColor = { 1, 1, 1, 0.20 },
    BgColor = { 0, 0, 0, 0.50 },
    Spark = true,
    -- Header-bar frame fields (OP-06: scale 0.2..5.0, alpha 0.1..1.0)
    Scale = 1.0,
    Alpha = 1.0,
})

-- Wiring contract (T9, 2026-11-02): every key of this module has a public
-- setter seam on FX.Cooldown.Display -- the listener below routes each
-- change through Display:ApplySettings, which maps the key onto its
-- setter (size/Max/Loga/tags -> geometry rebuild of exactly what moved,
-- colours -> TimelineSkin colors + live slot re-tint, BarColor/BgColor/
-- Spark/Scale/Alpha/Enable/HideCombat/AltTimeFormat/BarFont/BarTexture ->
-- their own seams, IgnoreShort -> Engine.MIN_COOLDOWN + a tracked rebuild).
-- Saved values are applied at login by Display:Init (ApplyStoredSettings)
-- and the OnChange listeners make every edit live. Lock is the exception
-- (m4): the LIVE lock state on the bar is the truth -- SetLocked publishes
-- it into Lock/GlobalLock, and the first page build mirrors the live state
-- INTO the store (never the other way), so the checkboxes, the header icon
-- and /fx lock|unlock can never disagree.
--
-- Display:Init also self-wires these two modules (Forte_Cooldown must work
-- without Forte_Options installed); this listener is the page-side mirror
-- and is idempotent with it.

local function display()
    return FX.Cooldown and FX.Cooldown.Display
end

local function pushLiveLock()
    local d = display()
    if not d or not d.cfg or d.cfg.locked == nil then return end
    local live = d.cfg.locked and true or false
    if FX.Settings:Get(M, "Lock") ~= live then
        FX.Settings:Set(M, "Lock", live)
    end
end

local wired = false
local function ensureWiring()
    if wired then return end
    wired = true
    FX.Settings:OnChange(M, function(key, value)
        local d = display()
        if d and d.ApplySettings then
            d:ApplySettings({ [key] = value })
        end
    end)
    pushLiveLock()
end

O:RegisterPage({
    id = "Cooldown",
    module = M,
    title = "Cooldown Timer",
    colour = O.C.GREEN,
    scaleKey = "Scale",
    alphaKey = "Alpha",
    lockKey = "Lock",
    -- C4: this page drives the timeline bar; its header glyph reads the
    -- bar's LIVE cfg.locked (the m4 publish law), never the store copy.
    lockFrame = display,
    build = function(b)
        ensureWiring()
        -- m4: the checkbox (and the header icon BuildHeader builds after
        -- this) read the STORE, so mirror the live lock state into it on
        -- every page build: /fx unlock then Open("Cooldown") must show an
        -- unchecked Lock box.
        pushLiveLock()
        b.Tips({
            "One power-scale timeline: fresh cooldowns ride in from the right.",
            "Drag the bar (with Lock off) to place it; the position is saved.",
            "Colour squares open the colour picker; values print as r g b a.",
            "The recycle icon on a section restores that section's defaults.",
        })
        b.Section("Basics", function(s)
            s.CHK({ module = M, key = "Enable", label = "Enable",
                tip = "Show the Cooldown Timer. Off hides the bar live." })
            s.CHK({ module = M, key = "Lock", label = "Lock",
                tip = "Lock the bar against dragging (shared with Global Frame Lock)." })
            -- CD-35 geometry modes, the original's BASICS rows in its order
            -- (labels verbatim: Localization.lua :108-111, :510-511).
            s.CHK({ module = M, key = "Vertical", label = "Flip to vertical",
                tip = "Change the bar orientation from horizontal to vertical: the icons stack bottom -> top along the bar's height (Forte_Cooldown.lua :1446-1448, :1476-1479). Live." })
            s.CHK({ module = M, key = "Flip", label = "Flip bar direction",
                tip = "Flip the timer bar direction: the icons run right -> left (top -> bottom when vertical) with the time tags and the fills mirrored (Forte_Cooldown.lua :1440-1443). Live." })
            s.CHK({ module = M, key = "HideZero", label = "Auto-hide when no cooldowns",
                tip = "Hide the cooldown timer scale and background when you have no visible cooldowns; the bar returns with the first one (Forte_Cooldown.lua :1348). Live." })
            s.CHK({ module = M, key = "HideCombat", label = "Hide when not in combat",
                tip = "Auto-hide the bar out of combat (live with the combat state)." })
        end, {
            module = M,
            keys = { "Enable", "Lock", "Vertical", "Flip", "HideZero",
                "HideCombat" },
            tip = "Master switch, position lock, bar geometry and visibility.",
        })
        b.Section("Specifics", function(s)
            -- CD-31, the SPECIFICS row :1714 (label verbatim,
            -- Localization.lua :158-159).
            s.CHK({ module = M, key = "Warn", label = "Spell on cooldown Warning",
                tip = "When you try to use an ability that is on cooldown, the timer will focus on this ability: the icon flashes and takes the group's focus (Forte_Cooldown.lua :933-946, :860-877). Live." })
            s.NUM({ module = M, key = "Width", label = "Width",
                min = 60, max = 1024, step = 1,
                tip = "Bar width in px (default 250). Resizes the bar live." })
            s.NUM({ module = M, key = "Height", label = "Height",
                min = 12, max = 128, step = 1,
                tip = "Bar height in px (default 24). Icon size rides it; resizes live." })
            s.NUM({ module = M, key = "MaxTime", label = "Max time",
                min = 10, max = 3600, step = 10,
                tip = "Longest cooldown drawn on the axis (default 300 s). Curve updates live." })
            s.NUM({ module = M, key = "PowerScale", label = "Power scale (Loga)",
                min = 0.05, max = 2.0, step = 0.01,
                tip = "Power exponent of the time axis (default 0.33). Curve updates live." })
            s.STR({ module = M, key = "TimeTags", label = "Custom time tags",
                maxLetters = 64,
                tip = "Space-separated tag seconds (default 0 1 10 30 60 120 300 600). Tags rebuild live." })
            s.NUM({ module = M, key = "IgnoreShort", label = "Ignore shorter than",
                min = 0, max = 60, step = 0.01,
                tip = "Cooldowns shorter than this are ignored (default 2.99 s). Engine.MIN_COOLDOWN, tracked set rebuilt live." })
        end, {
            module = M,
            keys = { "Warn", "Width", "Height", "MaxTime", "PowerScale", "TimeTags", "IgnoreShort" },
            tip = "The spell-on-cooldown warning and the power-scale timeline geometry (PLAN §3.5).",
        })
        b.Section("Coloring", function(s)
            local rows = {
                { key = "ColorSpell", label = "Spell" },
                { key = "ColorPowerup", label = "Powerup" },
                { key = "ColorItem", label = "Item" },
                { key = "ColorPotion", label = "Potion" },
                { key = "ColorPet", label = "Pet" },
                { key = "ColorInternal", label = "Internal" },
                { key = "ColorBuff", label = "Buff" },
                { key = "ColorDebuff", label = "Debuff" },
            }
            for _, row in ipairs(rows) do
                s.COL({ module = M, key = row.key, label = row.label,
                    tip = row.label .. " category colour (Forte_Cooldown.lua :1842-1855). Icons, segments and text retint live." })
            end
        end, {
            module = M,
            keys = { "ColorSpell", "ColorPowerup", "ColorItem", "ColorPotion",
                "ColorPet", "ColorInternal", "ColorBuff", "ColorDebuff" },
            tip = "Per-category icon/segment colours.",
        })
        b.Section("Frame Appearance", function(s)
            s.COL({ module = M, key = "BarColor", label = "Bar colour",
                tip = "Aluminium bar fill (default white a 0.20). Applied live." })
            s.COL({ module = M, key = "BgColor", label = "Background colour",
                tip = "Bar backdrop (default black a 0.50). Applied live." })
            s.CHK({ module = M, key = "Spark", label = "Spark",
                tip = "Running glow on cooling icons (default on). Shown/hidden live." })
        end, {
            module = M, keys = { "BarColor", "BgColor", "Spark" },
            tip = "Bar fill, backdrop and spark.",
        })
    end,
})
