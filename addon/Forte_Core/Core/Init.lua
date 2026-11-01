-- Forte_Core/Core/Init.lua
-- Bootstrap. Other Forte_* addons (Forte_Cooldown, Forte_Hunter, Forte_Warlock, ...)
-- call FX.RegisterModule(name, mod) from their own files; mod.OnEnable(mod) runs
-- once at PLAYER_LOGIN, in registration order.
--
-- Safety note (see docs/engine-notes.md): never RegisterEvent/RegisterUnitEvent at
-- a file's top level except the single bootstrap frame below. If another addon's
-- main chunk taints the Lua state before ours runs, a top-level RegisterEvent can
-- throw ADDON_ACTION_FORBIDDEN. Everything else happens inside the ADDON_LOADED/
-- PLAYER_LOGIN handler instead.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

FX.modules = FX.modules or {}      -- [name] = { OnEnable = function(self) ... end }
FX._moduleOrder = FX._moduleOrder or {}

--- Call from any Forte_* addon's own Lua, any time before PLAYER_LOGIN.
function FX.RegisterModule(name, mod)
    if FX.modules[name] then
        FX.Print("|cffff5555module '" .. name .. "' registered twice|r")
        return
    end
    FX.modules[name] = mod
    FX._moduleOrder[#FX._moduleOrder + 1] = name
end

-- Slash command registration is not protected and is safe at file-load time.
SLASH_FORTEXORCIST1 = "/fx"
SLASH_FORTEXORCIST2 = "/fortexorcist"
SlashCmdList["FORTEXORCIST"] = function(msg)
    FX.OnSlash((msg or ""):lower():match("^%s*(.-)%s*$"))
end

function FX.OnSlash(msg)
    -- Let the cooldown module claim its subcommands (/fx lock|unlock|reset). It returns
    -- true only for commands it owns; nil for everything else. Checked before our own
    -- commands so the core never shadows a module command by accident.
    local cd = FX.Cooldown and FX.Cooldown.Display
    if cd and cd.Slash and cd:Slash(msg) then
        return
    end
    if msg == "status" then
        FX.Print(string.format("%s | class=%s | Forever=%s | modules=%d",
            FX.CONST.VERSION, tostring(FX._playerClass), tostring(FX.Compat.IS_FOREVER), #FX._moduleOrder))
        for _, name in ipairs(FX._moduleOrder) do
            FX.Print("  " .. name)
        end
        local cdMod = FX.Cooldown and FX.Cooldown.Module
        if cdMod and cdMod.Status then
            cdMod:Status()
        end
        return
    end
    FX.Print(FX.CONST.VERSION .. " -- /fx status")
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= FX.CONST.ADDON_NAME then return end
        _G[FX.CONST.SV_KEY] = _G[FX.CONST.SV_KEY] or {}
        FX.db = _G[FX.CONST.SV_KEY]
    elseif event == "PLAYER_LOGIN" then
        local _, classFile = UnitClass("player")
        FX._playerClass = classFile -- e.g. "HUNTER", "WARLOCK" -- matches ForteXorcist.Data keys title-cased below
        for _, name in ipairs(FX._moduleOrder) do
            local mod = FX.modules[name]
            if mod and mod.OnEnable then
                local ok, err = pcall(mod.OnEnable, mod)
                if not ok then
                    FX.Print("|cffff5555" .. name .. " failed to enable:|r " .. tostring(err))
                end
            end
        end
        FX.Print(FX.CONST.VERSION .. " loaded. /fx status")
    end
end)
