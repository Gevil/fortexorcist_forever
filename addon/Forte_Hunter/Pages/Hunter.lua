-- Forte_Hunter/Pages/Hunter.lua
-- The Hunter Tools page (the auto-shot swing bar + the aspect reminder).
-- Registered through the Forte_Options page framework (see
-- Forte_Options/UI/Window.lua + Pages/Cooldown.lua for the page/section/
-- widget law this file follows verbatim).
--
-- Wiring contract: every key of this module has a public setter seam on
-- FX.Hunter.Swing / FX.Hunter.Reminder; the OnChange listener below routes
-- each change through their ApplySettings, and both modules ALSO self-wire
-- from their own Init (Forte_Hunter works with Forte_Options not installed;
-- the listener here is the page-side mirror and is idempotent with it).
-- Saved values are applied at login by the modules' ApplyStoredSettings.
-- Lock follows the Forte_Cooldown m4 rule: the modules publish the LIVE
-- lock state of their frames into Hunter.Lock (never the other way), so the
-- checkbox, the header lock icon and /fx lock|unlock agree.
--
-- Load-order law: this chunk is FORTE_HUNTER's, and the addon loader is
-- free to run it before Forte_Options' files (the dependency graph is
-- optional, and Forte_Cooldown's OptionalDeps already names Forte_Hunter) --
-- so nothing on FX.Settings / FX.Options may be touched at file load. The
-- whole registration is one idempotent function, run at load when
-- FX.Settings/FX.Options exist and, when they do not, from
-- FX.Hunter.UI:OnEnable at PLAYER_LOGIN (after every addon chunk has run).
-- FX.Settings:Register is safe at that late point -- the store seeds
-- lazily on the first Get/Set and defaults never overwrite a saved value.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

local M = "Hunter"

FX.Hunter = FX.Hunter or {}
FX.Hunter.Pages = FX.Hunter.Pages or {}
local P = FX.Hunter.Pages

local DEFAULTS = {
    -- Basics
    Enable = true,
    Lock = true,
    ShowTime = true,
    EnableReminder = true,
    -- Frame Sizing (the assignment's 200x12 bar, the reminder's 32px icon)
    Width = 200,
    Height = 12,
    ReminderSize = 32,
    -- Coloring (the Classic Aluminium-on-black law, PLAN §3.5). BarColor is
    -- the SwingSkin's own default (the Forte_Cooldown timeline's Spell
    -- category colour at full alpha -- the 1,1,1 a 0.20 wash was all but
    -- invisible): ONE truth, the store default and the module skin can not
    -- drift apart (UI/Swing.lua loads before this file, see the .toc).
    BarColor = (FX.Hunter.SwingSkin and FX.Hunter.SwingSkin.BarColor)
        or { 1, 0.5, 0, 1 },
    BgColor = { 0, 0, 0, 0.50 },
    ReminderColor = { 1, 1, 1, 1 },
}

local function swing()
    return FX.Hunter and FX.Hunter.Swing
end
local function reminder()
    return FX.Hunter and FX.Hunter.Reminder
end

local wired = false
local function ensureWiring()
    if wired then return end
    wired = true
    FX.Settings:OnChange(M, function(key, value)
        local d = swing()
        if d and d.ApplySettings then d:ApplySettings({ [key] = value }) end
        local r = reminder()
        if r and r.ApplySettings then r:ApplySettings({ [key] = value }) end
    end)
    -- m4: mirror the LIVE lock state of the swing bar into the store right
    -- before the checkbox and the header icon read it.
    local d = swing()
    if d and d.cfg and d.cfg.locked ~= nil then
        local live = d.cfg.locked and true or false
        if FX.Settings:Get(M, "Lock") ~= live then
            FX.Settings:Set(M, "Lock", live)
        end
    end
end

--- Register the settings defaults + the page. Idempotent; needs
--- FX.Settings + FX.Options (both Forte_Options files). Returns true when
--- the page is registered (also true for a repeat call).
function P.RegisterHunterPage()
    local O = FX.Options
    if not O or not O.pages or not FX.Settings then return false end
    if not O.pages["Hunter"] then
        FX.Settings:Register(M, DEFAULTS)
        O:RegisterPage({
            id = "Hunter",
            module = M,
            title = "Hunter Tools",
            colour = O.C.BROWN,
            lockKey = "Lock",
            build = function(b)
                ensureWiring()
                b.Tips({
                    "The swing bar fills while the ranged swing (Auto Shot) burns.",
                    "Drag the bar with Lock off; the position is saved per character.",
                    "/fx lock and /fx unlock move this bar with the Cooldown bar.",
                    "The recycle icon on a section restores that section's defaults.",
                })
                b.Section("Basics", function(s)
                    s.CHK({ module = M, key = "Enable", label = "Enable swing bar",
                        tip = "Show the Auto Shot swing bar. Off hides the bar live." })
                    s.CHK({ module = M, key = "Lock", label = "Lock",
                        tip = "Lock the bar against dragging (moves with /fx lock|unlock and Global Frame Lock)." })
                    s.CHK({ module = M, key = "ShowTime", label = "Show remaining text",
                        tip = "Print the remaining seconds (one decimal) right-aligned in the bar. Applied live." })
                    s.CHK({ module = M, key = "EnableReminder", label = "Enable aspect reminder",
                        tip = "Pulse the aspect icon while no aspect is active (out of combat only). Live." })
                end, {
                    module = M,
                    keys = { "Enable", "Lock", "ShowTime", "EnableReminder" },
                    tip = "Master switches of the Hunter tools.",
                })
                b.Section("Frame Sizing", function(s)
                    s.NUM({ module = M, key = "Width", label = "Width",
                        min = 60, max = 1024, step = 1,
                        tip = "Swing bar width in px (default 200). Resizes the bar live." })
                    s.NUM({ module = M, key = "Height", label = "Height",
                        min = 4, max = 64, step = 1,
                        tip = "Swing bar height in px (default 12). Resizes the bar live." })
                    s.NUM({ module = M, key = "ReminderSize", label = "Reminder size",
                        min = 16, max = 96, step = 1,
                        tip = "Aspect reminder icon size in px (default 32). Resizes live." })
                end, {
                    module = M,
                    keys = { "Width", "Height", "ReminderSize" },
                    tip = "Sizes of the two Hunter frames.",
                })
                b.Section("Coloring", function(s)
                    s.COL({ module = M, key = "BarColor", label = "Colour",
                        tip = "Aluminium bar fill (default the Cooldown Spell tint at full alpha). Applied live." })
                    s.COL({ module = M, key = "BgColor", label = "Background colour",
                        tip = "Bar backdrop (default black a 0.50). Applied live." })
                    s.COL({ module = M, key = "ReminderColor", label = "Reminder colour",
                        tip = "Aspect icon tint (default white). Applied live." })
                end, {
                    module = M,
                    keys = { "BarColor", "BgColor", "ReminderColor" },
                    tip = "Fill, backdrop and icon colours.",
                })
            end,
        })
    end
    return FX.Options.pages["Hunter"] ~= nil
end

-- Load-time fast path: Forte_Options ran first (the loader honoured the
-- OptionalDeps), so register right now. Otherwise FX.Hunter.UI:OnEnable
-- (PLAYER_LOGIN) calls the same function once every chunk has run.
P.RegisterHunterPage()
