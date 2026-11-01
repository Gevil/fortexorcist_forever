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

-- Subcommand registry for /fx: Forte_Options registers "options"/"config"
-- (later modules may add more). Dispatch order in FX.OnSlash: the cooldown
-- Display's claims (lock/unlock/reset) first, registered subs next, the
-- status fallback last.
FX.slashSubs = FX.slashSubs or {}

--- Call from any Forte_* addon's own Lua before the first /fx is typed.
--- fn(rest) gets the remainder of the (lower-cased, trimmed) message.
function FX.RegisterSlash(sub, fn)
    FX.slashSubs[(sub or ""):lower()] = fn
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
    -- Registered subcommands (/fx options|config|opt), after the Display's
    -- claims so lock/unlock/reset keep their behaviour, before the status
    -- fallback so a module can own any sub name.
    local sub, rest = msg:match("^(%S+)%s*(.*)$")
    local fn = sub and FX.slashSubs[sub]
    if fn then
        fn(rest)
        return
    end
    if msg == "status" then
        FX.Print(string.format("%s | class=%s | Forever=%s | modules=%d",
            FX.CONST.VERSION, tostring(FX._playerClass), tostring(FX.Compat.IS_FOREVER), #FX._moduleOrder))
        for _, name in ipairs(FX._moduleOrder) do
            FX.Print("  " .. name)
        end
        -- Every registered module prints its own status lines, in
        -- registration order (the registry is the only order we own). The
        -- old code hard-wired Forte_Cooldown and let Forte_Hunter wrap it;
        -- review m6 killed both. One module's Status raising must not
        -- silence the others, so each call is protected.
        for _, name in ipairs(FX._moduleOrder) do
            local mod = FX.modules[name]
            if mod and mod.Status then
                local ok, err = pcall(mod.Status, mod)
                if not ok then
                    FX.Print("|cffff5555" .. name .. " status failed:|r " .. tostring(err))
                end
            end
        end
        return
    end
    FX.Print(FX.CONST.VERSION .. " -- /fx status")
end

--- Re-read the player's class token and, when it changed, update
--- FX._playerClass and call every module's optional OnClassChanged(new).
--- Real clients never change class mid-session; this is the cheap guard
--- for tooling that does (the uiforever T4 artifact logged in as the
--- wrong class). Runs at PLAYER_ENTERING_WORLD; PLAYER_LOGIN below keeps
--- its own one-time capture.
function FX.RefreshPlayerClass()
    local ok, _, classFile = pcall(UnitClass, "player")
    if not ok or type(classFile) ~= "string" then return end
    if classFile == FX._playerClass then return end
    FX._playerClass = classFile
    for _, name in ipairs(FX._moduleOrder) do
        local mod = FX.modules[name]
        if mod and mod.OnClassChanged then
            local okC, err = pcall(mod.OnClassChanged, mod, classFile)
            if not okC then
                FX.Print("|cffff5555" .. name .. " OnClassChanged failed:|r " .. tostring(err))
            end
        end
    end
end

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
bootstrap:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= FX.CONST.ADDON_NAME then return end
        _G[FX.CONST.SV_KEY] = _G[FX.CONST.SV_KEY] or {}
        FX.db = _G[FX.CONST.SV_KEY]
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zone-in re-read (the login capture below is the first one): the
        -- uiforever T4 artifact class guard, see FX.RefreshPlayerClass.
        FX.RefreshPlayerClass()
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
