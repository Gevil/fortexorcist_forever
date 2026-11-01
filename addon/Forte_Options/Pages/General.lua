-- Forte_Options/Pages/General.lua
-- The General Options page (docs/refs/options-panel.png: sections Some Tips
-- / General Module Options / General Module Appearance). Wiring (T9):
-- Global Frame Lock shares the ONE live lock state of the cooldown bar
-- (the bar publishes it; the first page build mirrors it into the store,
-- m4), Global Frame Alpha/Scale multiply into the module frames' own
-- alpha/scale, AltTimeFormat switches the bar's time text to m:ss
-- everywhere, and Bar Font / Bar Texture drive the bar's fontstring file
-- and its fill texture -- all live through FX.Cooldown.Display's public
-- setters (see Forte_Cooldown/UI/Timeline.lua, "live settings").
-- FrameSnap (snap grid) and ShowTooltips (module-frame tooltips) have no
-- consumer YET -- they stay stored-only and their tips say 'not used yet'.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local O = FX.Options

local M = "General"
local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"
local FONT = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"

FX.Settings:Register(M, {
    GlobalLock = true,                 -- mirrors the bar's live lock (m4)
    FrameAlpha = 1.0,
    FrameScale = 1.0,
    FrameSnap = false,
    AltTimeFormat = false,
    ShowTooltips = true,
    BarFont = FONT,
    BarTexture = TEX .. "Aluminium",
})

local function display()
    return FX.Cooldown and FX.Cooldown.Display
end

--- m4: the live lock state of the bar is the truth; mirror it into the
--- store right before the checkbox (and the header icon) read it.
local function pushLiveLock()
    local d = display()
    if not d or not d.cfg or d.cfg.locked == nil then return end
    local live = d.cfg.locked and true or false
    if FX.Settings:Get(M, "GlobalLock") ~= live then
        FX.Settings:Set(M, "GlobalLock", live)
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
    id = "General",
    module = M,
    title = "General Options",
    colour = O.C.SLATE,
    scaleKey = "FrameScale",
    alphaKey = "FrameAlpha",
    lockKey = "GlobalLock",
    build = function(b)
        ensureWiring()
        -- m4: mirror the bar's live lock into GlobalLock right before the
        -- checkbox and the header icon read the store.
        pushLiveLock()
        b.Tips({
            "Drag the title bar to move this window; ESC closes it.",
            "/fx options opens and closes this window.",
            "Global Frame Lock protects every Forte module frame from dragging.",
            "The recycle icon left of every row restores just that option.",
        })
        b.Section("General Module Options", function(s)
            s.CHK({
                module = M, key = "GlobalLock",
                label = "Global Frame Lock",
                tip = "Lock all Forte module frames (same state as /fx lock).",
            })
            s.NUM({
                module = M, key = "FrameAlpha",
                label = "Global Frame Alpha",
                min = 0, max = 1, step = 0.05,
                tip = "Overall frame alpha (0..1). Multiplies with the module's own alpha, live.",
            })
            s.CHK({
                module = M, key = "FrameSnap",
                label = "Enable frame snapping",
                tip = "Snap module frames to the screen edge while dragging. Not used yet (no snap grid exists).",
            })
            s.CHK({
                module = M, key = "AltTimeFormat",
                label = "Alternate time format",
                tip = "Show cooldown times as m:ss everywhere (not the tenths). Applied live.",
            })
        end, {
            module = M,
            keys = { "GlobalLock", "FrameAlpha", "FrameSnap", "AltTimeFormat" },
            tip = "Global behaviour of every Forte module.",
        })
        b.Section("General Module Appearance", function(s)
            s.CHK({
                module = M, key = "ShowTooltips",
                label = "Show module frame tooltips",
                tip = "Show game tooltips when the mouse rests on module frames. Not used yet (module frames have no tooltips to gate).",
            })
            s.INFO({
                module = M, key = "BarFont",
                label = "Bar Font",
                value = function() return FX.Settings:Get(M, "BarFont") end,
                tip = "Font used by module bars (URW Gothic Book 11, PLAN §3.5). Re-validates and applies live.",
            })
            s.INFO({
                module = M, key = "BarTexture",
                label = "Bar Texture",
                value = function() return FX.Settings:Get(M, "BarTexture") end,
                tip = "Fill texture used by module bars (vendored Aluminium). Applied live.",
            })
        end, {
            module = M,
            keys = { "ShowTooltips", "BarFont", "BarTexture" },
            tip = "Shared appearance of the module bars.",
        })
    end,
})
