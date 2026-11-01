-- Forte_Options/Pages/General.lua
-- The General Options page (docs/refs/options-panel.png: sections Some Tips
-- / General Module Options / General Module Appearance). The only live
-- wiring on this page is Global Frame Lock -> FX.Cooldown.Display:SetLocked
-- (Timeline owns Forte_Cooldown; SetLocked is its public lock seam, so the
-- lock checkbox, the header lock icon and /fx lock|unlock drive the very
-- same state). FrameAlpha/FrameScale/FrameSnap/AltTimeFormat are stored
-- only -- they are listed as unwired in the Phase-6 report.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist
local O = FX.Options

local M = "General"
local TEX = "Interface\\AddOns\\Forte_Core\\Textures\\"
local FONT = "Interface\\AddOns\\Forte_Core\\Fonts\\URWGothic-Book.ttf"

FX.Settings:Register(M, {
    GlobalLock = true,                 -- the cooldown bar starts locked (Timeline DEFAULT)
    FrameAlpha = 1.0,
    FrameScale = 1.0,
    FrameSnap = false,
    AltTimeFormat = false,
    ShowTooltips = true,
    BarFont = FONT,
    BarTexture = TEX .. "Aluminium",
})

--- Push the stored lock state into the live cooldown display (nil-safe:
--- Forte_Cooldown is an optional dependency).
local function applyLock()
    local d = FX.Cooldown and FX.Cooldown.Display
    if d and d.SetLocked then
        d:SetLocked(not not FX.Settings:Get(M, "GlobalLock"))
    end
end

local wired = false
local function ensureWiring()
    if wired then return end
    wired = true
    FX.Settings:OnChange(M, function(key, value)
        if key == "GlobalLock" then
            local d = FX.Cooldown and FX.Cooldown.Display
            if d and d.SetLocked then d:SetLocked(not not value) end
        end
    end)
    applyLock()
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
                tip = "Overall frame alpha (0..1). Stored: the timeline bar keeps its own alpha law.",
            })
            s.CHK({
                module = M, key = "FrameSnap",
                label = "Enable frame snapping",
                tip = "Snap module frames to the screen edge while dragging. Stored: snap grid not built yet.",
            })
            s.CHK({
                module = M, key = "AltTimeFormat",
                label = "Alternate time format",
                tip = "Show cooldown times as m:ss everywhere. Stored: display switch not wired yet.",
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
                tip = "Show game tooltips when the mouse rests on module frames.",
            })
            s.INFO({
                module = M, key = "BarFont",
                label = "Bar Font",
                value = function() return FX.Settings:Get(M, "BarFont") end,
                tip = "Font used by module bars (URW Gothic Book 11, PLAN §3.5).",
            })
            s.INFO({
                module = M, key = "BarTexture",
                label = "Bar Texture",
                value = function() return FX.Settings:Get(M, "BarTexture") end,
                tip = "Fill texture used by module bars (vendored Aluminium).",
            })
        end, {
            module = M,
            keys = { "ShowTooltips", "BarFont", "BarTexture" },
            tip = "Shared appearance of the module bars.",
        })
    end,
})
