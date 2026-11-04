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
    -- Shot Cycle (swing v2, docs/research/weaponswingtimer.md gap row 10;
    -- Iteration J slice γ, docs/research/wst-swing-design.md §7): BarMode
    -- REPLACES ShowSafeWindow (§7.1) — this ONE registration. A stored
    -- ShowSafeWindow = false reaches the bar through UI/Swing.lua's
    -- SetShowSafeWindow migration seam and reads back as BarMode =
    -- "elapsed" (true/unset as "safe"); the key has no row and no default
    -- here any more. ShowAimWindow / ShowClipRegion / ShowWeaveLine are the
    -- §7.3 / §7.4 markers (UI/Swing.lua's KEYMAP); EnableMeleeRail is the
    -- §7.5 opt-in rail, riding FX.Hunter.Melee's own ApplySettings
    -- self-wiring (slice β) — no new plumbing in either case.
    BarMode = "safe",
    ShowAimWindow = true,
    ShowClipRegion = true,
    ShowWeaveLine = false,
    EnableMeleeRail = false,
    ShowAimSlice = true,
    ShowFlying = true,
    ShowRetry = true,
    ShowLatency = false,
    BaseSpeed = 0,
    -- Range light (gap row 6): opt-in, the WST default-off law.
    ShowRangeLight = false,
    -- Combat Alpha (the WST in/ooc pair, gap row 10).
    InCombatAlpha = 1.0,
    OutOfCombatAlpha = 1.0,
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
local function rangelight()
    return FX.Hunter and FX.Hunter.RangeLight
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
        local l = rangelight()
        if l and l.ApplySettings then l:ApplySettings({ [key] = value }) end
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
            -- C4: the n4 law as data -- the page hands its live frame (the
            -- swing bar, whose publish is Hunter.Lock) to BuildHeader; the
            -- window no longer branches on the module name.
            lockFrame = swing,
            build = function(b)
                ensureWiring()
                b.Tips({
                    "The swing bar fills while the ranged swing (Auto Shot) burns.",
                    "Safe window first, then the red aim slice: stand still while it runs.",
                    "The bar turns WHITE when the projectile left: move and cast freely.",
                    "Yellow = a rejected Auto Shot start (0.5 s retry); red cast slice = a shot will clip.",
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
                b.Section("Shot Cycle", function(s)
                    s.SEL({ module = M, key = "BarMode",
                        label = "Bar mode",
                        items = {
                            { value = "safe",
                                label =
                                    "Safe window (shrinks toward the aim end)" },
                            { value = "one",
                                label =
                                    "One bar (fills toward the aim end)" },
                            { value = "elapsed",
                                label = "Single fill (cycle elapsed)" },
                        },
                        tip = "How close is the next Auto Shot, and how much room do I have to move? Safe window: the fill is the safe-to-move span shrinking toward the aim end - an empty left field IS the warning. One bar: the same cycle read as progress, the fill growing toward the aim end. Single fill: the plain cycle clock for a player who does not weave. Live." })
                    s.CHK({ module = M, key = "ShowAimWindow",
                        label = "Aim window (right end, standing)",
                        tip = "When must I stop moving? The right-end band that stands all cycle: the aiming window (0.5 s scaled by haste). The fill runs into it; the red slice inside it is the live windup - stand still while it drains. Live." })
                    s.CHK({ module = M, key = "ShowClipRegion",
                        label = "Clip region (a cast started here clips the shot)",
                        tip = "Can I cast without clipping? Start Aimed Shot / Multi-Shot while the bar says it fits: with the shrinking bar, while the orange reaches PAST the dim mark; with the filling bars, while the fill is LEFT of the stripe at the right end. On the wrong side the cast delays your next Auto Shot. The mark is that shot's cast time, so a bar-spanning mark means this bow never fits a cast-time shot. Live." })
                    s.CHK({ module = M, key = "ShowWeaveLine",
                        label = "Melee-weave line (room for a 1.5 s GCD before the shot)",
                        tip = "Is there room to weave? Shrinking bar (Safe window): step in while the orange still reaches PAST the line. Filling bars (One bar / Single fill): while the fill is LEFT of the line. The line is the room for one 1.5 s global cooldown (Raptor Strike, Mongoose Bite, an instant shot) before the shot; the line off the bar means a hasted cycle has no room at all. Off by default: it is a melee-weave build tool. Live." })
                    s.CHK({ module = M, key = "EnableMeleeRail",
                        label = "Enable melee swing rail",
                        tip = "Is my main-hand swing up? Your main-hand swing, shown only in melee range - Raptor Strike resets it. A slim rail under the bar (under the range light when it is on): full = the swing is ready. Off by default. Live." })
                    s.CHK({ module = M, key = "ShowAimSlice",
                        label = "Aim window (red slice)",
                        tip = "The red right-end slice: the stand-still aiming window (0.5 s scaled by haste). Moving during it loses the shot. Live." })
                    s.CHK({ module = M, key = "ShowFlying",
                        label = "Projectile left (white)",
                        tip = "The bar turns white while the proven projectile is in flight: move/cast freely (spark pulse). Live." })
                    s.CHK({ module = M, key = "ShowRetry",
                        label = "Auto Shot retry penalty (yellow)",
                        tip = "A rejected Auto Shot start costs 0.5 s (yellow slice + floor raise). Live." })
                    s.CHK({ module = M, key = "ShowLatency",
                        label = "Latency strip (needs launch probe)",
                        tip = "The GetNetStats latency shape is a launch-day probe (survey Gap-12); the strip is inert until the probe lands. Stored." })
                    s.NUM({ module = M, key = "BaseSpeed",
                        label = "Weapon base speed (0 = auto)", min = 0,
                        max = 8, step = 0.05,
                        tip = "The un-hasted ranged weapon speed for the aim-window ratio (aim = 0.5 x speed / base). 0 = auto. Live." })
                end, {
                    module = M,
                    keys = { "BarMode", "ShowAimWindow", "ShowClipRegion",
                        "ShowWeaveLine", "EnableMeleeRail", "ShowAimSlice",
                        "ShowFlying", "ShowRetry", "ShowLatency",
                        "BaseSpeed" },
                    tip = "The Auto Shot cycle and its reading: the bar mode, the aim window, the clip / weave markers, the melee rail, flight, retry.",
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
                b.Section("Range Light", function(s)
                    s.CHK({ module = M, key = "ShowRangeLight",
                        label = "Enable range / dead-zone light",
                        tip = "The slim strip under the bar: MELEE (red), DEAD 5-8 (yellow), 8-35 (green), 35+ (cyan), OUT (grey). Enables the native swing range check while shown. Live." })
                end, {
                    module = M,
                    keys = { "ShowRangeLight" },
                    tip = "The 8-35 yd range / dead-zone indicator (off by default).",
                })
                b.Section("Combat Alpha", function(s)
                    s.NUM({ module = M, key = "InCombatAlpha",
                        label = "In-combat alpha", min = 0, max = 1,
                        step = 0.05,
                        tip = "Bar alpha while in combat (default 1.0). Live." })
                    s.NUM({ module = M, key = "OutOfCombatAlpha",
                        label = "Out-of-combat alpha", min = 0, max = 1,
                        step = 0.05,
                        tip = "Bar alpha out of combat (default 1.0 = VISIBLE "
                            .. "out of combat, the shipped shape: the WeaponSwingTimer "
                            .. "in-combat-only law is NOT copied -- the bar hides "
                            .. "itself while the swing cycle is idle, so an alpha of "
                            .. "0.0 is the way to park it out of combat by hand). Live." })
                end, {
                    module = M,
                    keys = { "InCombatAlpha", "OutOfCombatAlpha" },
                    tip = "The in/out-of-combat alpha pair (the combat gate is InCombatLockdown).",
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
