-- Forte_Options/Pages/Splash.lua
-- The Secondary Splash page -- the id ("Splash") the window index grid
-- lights for the "Secondary Splash" cell (O.INDEX, UI/Window.lua). The
-- module it drives is Forte_Cooldown/UI/Splash.lua (FX.Cooldown.Splash),
-- the original's own instance + option tree
-- (/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua :1770-1780,
-- FW.InstanceDefault.Splash :1868-1874; the SplashMax cap is spec CD-28).
--
-- Wiring contract (the Pages/Cooldown.lua shape): every key of this
-- module has a public setter seam on FX.Cooldown.Splash; the listener
-- below routes each change through its ApplySettings. Splash.lua also
-- self-wires from its Init (Forte_Cooldown works with Forte_Options not
-- installed); this listener is the page-side mirror and idempotent with
-- it. Saved values are applied at login by the module's
-- ApplyStoredSettings.
--
-- Lock follows the Forte_Cooldown m4 rule: the LIVE lock state of the
-- splash frame publishes into Splash.Lock (never the other way), and
-- /fx lock|unlock moves the frame through the Cooldown.Lock /
-- GlobalLock mirror built into UI/Splash.lua -- so the checkbox, the
-- header lock icon and the slash all agree.
--
-- OptionsCD (2026-11-03, wave 4 item 2): the three rows the source's SPLASH2
-- block (:1776-1780) carries are now the source's own strings -- "Enable
-- Secondary Splash icon" (FWL.CD_SPLASH3, Localization.lua:126), "Splash icon
-- active scale" (FWL.CD_SPLASH2, :124), "Show icon Glow" (FWL.SHOW_GLOW,
-- :145). "Lock" (the m4 header law) and "Max simultaneous" (spec CD-28) are
-- the project's own rows; the source has no key of the SPLASH2 block this
-- page does not already carry.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local O = FX.Options

local M = "Splash"

FX.Settings:Register(M, {
    -- Basics. Off by default: the original's InstanceDefault.Splash
    -- Enable = false (Forte_Cooldown.lua :1869).
    Enable = false,
    Lock = true,
    -- The bell + the cap (Forte_Cooldown.lua :1870 SecondSplashMax, the
    -- bell's peak multiplier; SplashMax cap CD-28).
    SecondSplashMax = 4,
    SplashMax = 8,
    SplashGlow = true,            -- :1871
    -- Frame Appearance (the :1872 alpha / :1873 scale pair).
    Alpha = 0.7,
    Scale = 2,
})

local function splash()
    return FX.Cooldown and FX.Cooldown.Splash
end

local function pushLiveLock()
    local d = splash()
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
        local d = splash()
        if d and d.ApplySettings then
            d:ApplySettings({ [key] = value })
        end
    end)
    pushLiveLock()
end

O:RegisterPage({
    id = "Splash",
    module = M,
    title = "Secondary Splash",
    colour = O.C.GREEN,
    lockKey = "Lock",
    -- C4: the page drives the splash window; its header glyph reads the
    -- frame's LIVE cfg.locked (the m4 publish law), never the store copy.
    lockFrame = splash,
    build = function(b)
        ensureWiring()
        -- m4: mirror the live lock state into the store right before the
        -- checkbox and the header icon read it.
        pushLiveLock()
        b.Tips({
            "Off by default, exactly like the original. A ready cooldown",
            "runs its icon through the source's bell here: the icon fades",
            "in while it grows to the peak half-way through a fixed 1.0 s",
            "window, then rides back down. Unlocking the window shows a",
            "placeholder icon while it idles.",
            "Drag the window (with Lock off) to place it; /fx lock|unlock",
            "moves it together with the Cooldown bar and Global Frame Lock.",
            "The recycle icon on a section restores that section's defaults.",
        })
        b.Section("Basics", function(s)
            s.CHK({ module = M, key = "Enable", label = "Enable Secondary Splash icon",
                tip = "This splash icon can be moved to anywhere in your interface. Unlock it to position it (FWL.CD_SPLASH3, Forte_Cooldown/Localization.lua:126; the SPLASH2 row :1776). Off hides the window and drops live pops (the original's default is off, Forte_Cooldown.lua :1869). Live." })
            s.CHK({ module = M, key = "Lock", label = "Lock",
                tip = "Lock the splash window against dragging (moves with /fx lock|unlock and Global Frame Lock)." })
        end, {
            module = M, keys = { "Enable", "Lock" },
            tip = "Master switch and position lock.",
        })
        b.Section("Splash Curve", function(s)
            s.NUM({ module = M, key = "SecondSplashMax", label = "Splash icon active scale",
                min = 0.1, max = 20, step = 0.1,
                tip = "Set what scale factor to use for the icon splash at the middle of the splash animation (FWL.CD_SPLASH2, Forte_Cooldown/Localization.lua:124; the SPLASH2 row :1779, SetRange(0.1) so the floor is 0.1): the bell peaks mid-window at an icon of 32 x this px, then rides back down (default 4, Forte_Cooldown.lua :1870, :1027). Live." })
            s.NUM({ module = M, key = "SplashMax", label = "Max simultaneous",
                min = 1, max = 16, step = 1,
                tip = "At most this many splashes at once; a pop over the cap is dropped (default 8, spec CD-28). Live." })
            s.CHK({ module = M, key = "SplashGlow", label = "Show icon Glow",
                tip = "Show a glow around the icons that matches the bar color (FWL.SHOW_GLOW, Forte_Cooldown/Localization.lua:145; the SPLASH2 row :1780): crop the icon to 0.133..0.867 and add the Spark2 glow at 2.2x (Forte_Cooldown.lua :978-988, :1031-1034). Live." })
        end, {
            module = M,
            keys = { "SecondSplashMax", "SplashMax", "SplashGlow" },
            tip = "The bell peak, the simultaneous cap and the glow. Every splash runs the fixed 1.0 s window.",
        })
        b.Section("Frame Appearance", function(s)
            s.NUM({ module = M, key = "Alpha", label = "Alpha",
                min = 0.05, max = 1, step = 0.05,
                tip = "Window alpha (default 0.7, Forte_Cooldown.lua :1872). Live." })
            s.NUM({ module = M, key = "Scale", label = "Scale",
                min = 0.5, max = 8, step = 0.1,
                tip = "Normal icon size = 32 x this (default 2, Forte_Cooldown.lua :1873). Live." })
        end, {
            module = M, keys = { "Alpha", "Scale" },
            tip = "Window alpha and the base icon scale.",
        })
    end,
})
