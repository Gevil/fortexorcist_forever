-- Forte_Options/Pages/Cooldown.lua
-- The Cooldown Timer page (sections Some Tips / Basics / Specifics /
-- Coloring / Frame Appearance). Defaults mirror the design law, PLAN §3.5
-- (Forte_Cooldown.lua :1801-1866): one 250x24 power-scale bar, Max 300,
-- Loga 0.33, tags "0 1 10 30 60 120 300 600", IgnoreCooldown 2.99, verbatim
-- category colours.
--
-- Wiring contract (Timeline owns Forte_Cooldown, nothing here edits it):
--   * Lock -> FX.Cooldown.Display:SetLocked  (its public lock seam; the
--     General page's Global Frame Lock drives the SAME display state).
--   * Every other key (Enable, HideCombat, Width, Height, MaxTime,
--     PowerScale, TimeTags, IgnoreShort, all colours, Spark, Scale, Alpha)
--     is stored only; the Phase-6 report lists them as unwired keys.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local O = FX.Options

local M = "Cooldown"

FX.Settings:Register(M, {
    -- Basics
    Enable = true,
    Lock = true,
    HideCombat = false,
    -- Specifics (PLAN §3.5)
    Width = 250,
    Height = 24,
    MaxTime = 300,
    PowerScale = 0.33,                 -- Loga
    TimeTags = "0 1 10 30 60 120 300 600",
    IgnoreShort = 2.99,                -- Engine.MIN_COOLDOWN
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

local function display()
    return FX.Cooldown and FX.Cooldown.Display
end
local function hasLockSeam()
    local d = display()
    return d ~= nil and d.SetLocked ~= nil
end

local wired = false
local function ensureWiring()
    if wired then return end
    wired = true
    FX.Settings:OnChange(M, function(key, value)
        if key == "Lock" and hasLockSeam() then
            display():SetLocked(not not value)
        end
    end)
    -- Push the stored lock state once, at first page build.
    if hasLockSeam() then
        display():SetLocked(not not FX.Settings:Get(M, "Lock"))
    end
end

O:RegisterPage({
    id = "Cooldown",
    module = M,
    title = "Cooldown Timer",
    colour = O.C.GREEN,
    scaleKey = "Scale",
    alphaKey = "Alpha",
    lockKey = "Lock",
    build = function(b)
        ensureWiring()
        b.Tips({
            "One power-scale timeline: fresh cooldowns ride in from the right.",
            "Drag the bar (with Lock off) to place it; the position is saved.",
            "Colour squares open the colour picker; values print as r g b a.",
            "The recycle icon on a section restores that section's defaults.",
        })
        b.Section("Basics", function(s)
            s.CHK({ module = M, key = "Enable", label = "Enable",
                tip = "Show the Cooldown Timer. Stored: enable switch not wired yet." })
            s.CHK({ module = M, key = "Lock", label = "Lock",
                tip = "Lock the bar against dragging (shared with Global Frame Lock)." })
            s.CHK({ module = M, key = "HideCombat", label = "Hide when not in combat",
                tip = "Auto-hide the bar out of combat. Stored: display policy not wired yet." })
        end, {
            module = M, keys = { "Enable", "Lock", "HideCombat" },
            tip = "Master switch, position lock and combat visibility.",
        })
        b.Section("Specifics", function(s)
            s.NUM({ module = M, key = "Width", label = "Width",
                min = 60, max = 1024, step = 1,
                tip = "Bar width in px (default 250). Stored: timeline geometry not wired yet." })
            s.NUM({ module = M, key = "Height", label = "Height",
                min = 12, max = 128, step = 1,
                tip = "Bar height in px (default 24). Stored: timeline geometry not wired yet." })
            s.NUM({ module = M, key = "MaxTime", label = "Max time",
                min = 10, max = 3600, step = 10,
                tip = "Longest cooldown drawn on the axis (default 300 s). Stored: not wired yet." })
            s.NUM({ module = M, key = "PowerScale", label = "Power scale (Loga)",
                min = 0.05, max = 2.0, step = 0.01,
                tip = "Power exponent of the time axis (default 0.33). Stored: not wired yet." })
            s.STR({ module = M, key = "TimeTags", label = "Custom time tags",
                maxLetters = 64,
                tip = "Space-separated tag seconds (default 0 1 10 30 60 120 300 600). Stored: not wired yet." })
            s.NUM({ module = M, key = "IgnoreShort", label = "Ignore shorter than",
                min = 0, max = 60, step = 0.01,
                tip = "Cooldowns shorter than this are ignored (default 2.99 s). Stored: Engine.MIN_COOLDOWN not wired." })
        end, {
            module = M,
            keys = { "Width", "Height", "MaxTime", "PowerScale", "TimeTags", "IgnoreShort" },
            tip = "The power-scale timeline geometry (PLAN §3.5).",
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
                    tip = row.label .. " category colour (Forte_Cooldown.lua :1842-1855). Stored: not wired yet." })
            end
        end, {
            module = M,
            keys = { "ColorSpell", "ColorPowerup", "ColorItem", "ColorPotion",
                "ColorPet", "ColorInternal", "ColorBuff", "ColorDebuff" },
            tip = "Per-category icon/segment colours.",
        })
        b.Section("Frame Appearance", function(s)
            s.COL({ module = M, key = "BarColor", label = "Bar colour",
                tip = "Aluminium bar fill (default white a 0.20). Stored: not wired yet." })
            s.COL({ module = M, key = "BgColor", label = "Background colour",
                tip = "Bar backdrop (default black a 0.50). Stored: not wired yet." })
            s.CHK({ module = M, key = "Spark", label = "Spark",
                tip = "Running glow on cooling icons (default on). Stored: not wired yet." })
        end, {
            module = M, keys = { "BarColor", "BgColor", "Spark" },
            tip = "Bar fill, backdrop and spark.",
        })
    end,
})
