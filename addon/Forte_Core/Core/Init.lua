-- Forte_Core/Core/Init.lua
-- Bootstrap. Other Forte_* addons (Forte_Cooldown, Forte_Hunter, Forte_Warlock, ...)
-- call FX.RegisterModule(name, mod) from their own files; mod.OnEnable(mod) runs
-- exactly once in the login pass (FX.RunLoginPass: PLAYER_LOGIN, or the first
-- PLAYER_ENTERING_WORLD when PLAYER_LOGIN was missed), in registration order.
-- Login-time work belongs in OnEnable, which the pass calls DIRECTLY: a module
-- that registers PLAYER_LOGIN in its own OnEnable can wait for the session
-- (docs/research/upstream-addons-2026-11-03.md §7.3; proven by
-- addon/Forte_Core/tests/test_login_order.lua).
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
-- [name] = true once OnEnable has run: the exactly-once ledger.
FX._enabledModules = FX._enabledModules or {}
-- True from the moment the PLAYER_LOGIN enable loop finished. Class add-ons
-- are load-on-demand (Core/Loader.lua), so their files -- and therefore their
-- FX.RegisterModule calls -- can land after that loop; those modules are
-- enabled at once, in registration order, by the tail of FX.RegisterModule.
FX._loginDone = false

--- Run one module's OnEnable exactly once, in a pcall. The single enable
--- path: the PLAYER_LOGIN loop and the late-registration path below both
--- go through it, so no module can be enabled twice by the two paths racing
--- inside one PLAYER_LOGIN.
function FX.EnableModule(name)
    if FX._enabledModules[name] then return end
    local mod = FX.modules[name]
    if not mod then return end
    FX._enabledModules[name] = true
    if mod.OnEnable then
        local ok, err = pcall(mod.OnEnable, mod)
        if not ok then
            FX.Print("|cffff5555" .. name .. " failed to enable:|r " .. tostring(err))
        end
    end
end

--- Call from any Forte_* addon's own Lua: at file load, and -- for the
--- load-on-demand class add-ons -- from inside the login pass
--- (FX.RunLoginPass) while it loads the class add-on.
function FX.RegisterModule(name, mod)
    if FX.modules[name] then
        FX.Print("|cffff5555module '" .. name .. "' registered twice|r")
        return
    end
    FX.modules[name] = mod
    FX._moduleOrder[#FX._moduleOrder + 1] = name
    -- Late registration (a load-on-demand class add-on whose files ran after
    -- the login loop): enable it now. Registration order is preserved by the
    -- loop the class loader drives, and by the order of the add-on's own
    -- files (Data, Core, UI, Pages) when a LoadAddOn loads several modules.
    if FX._loginDone then
        FX.EnableModule(name)
    end
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
---
--- The new class's add-on is load-on-demand, so it is pulled in here FIRST:
--- its files register their modules, and FX.RegisterModule enables each one
--- as it registers (FX._loginDone is true by now), in the add-on's own file
--- order -- so the new class's modules take part in the OnClassChanged wave
--- that follows, exactly like the modules that were present at login.
function FX.RefreshPlayerClass()
    local ok, _, classFile = pcall(UnitClass, "player")
    if not ok or type(classFile) ~= "string" then return end
    if classFile == FX._playerClass then return end
    FX._playerClass = classFile
    FX.LoadClassAddOn(classFile)
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

--- The login line (the version + the `/fx status` pointer), gated by the
--- Advanced page's `ShowStartupText` (the source's row of the same name,
--- Forte_Core/Options.lua:5577, default true at :2529: "Show the
--- ForteXorcist startup lines in your chat window", Localization.lua:497).
--- Off = a silent login. Returns whether the line went out, which is what
--- the gate's test drives.
function FX.PrintStartupLine()
    local st = FX.Settings
    if st and st.IsRegistered and st:IsRegistered("Advanced")
        and st:Get("Advanced", "ShowStartupText") == false then
        return false
    end
    FX.Print(FX.CONST.VERSION .. " loaded. /fx status")
    return true
end

--- THE LOGIN PASS: capture the class token, pull in the player's
--- load-on-demand class add-on (Core/Loader.lua), enable every registered
--- module in registration order, then open the late-registration seam.
---
--- ONE-SHOT: `FX._loginDone` is the guard, checked before anything else, so
--- the PLAYER_LOGIN dispatch and the PLAYER_ENTERING_WORLD fallback below can
--- not run the enable loop twice; the `FX._enabledModules` ledger is the
--- second, per-module half of that law (Core/Init.lua's EnableModule).
--- Returns true when THIS call was the pass, false when the pass had already
--- run -- which is exactly the shape the PLAYER_ENTERING_WORLD handler wants.
---
--- Why PLAYER_ENTERING_WORLD is a legal second driver (the shipped law,
--- docs/research/upstream-addons-2026-11-03.md §7.3, from
--- `CDM@e5811752 Core/Init.lua:153-157, 214-218`): "the login handler is driven
--- from whichever of PLAYER_LOGIN / first PLAYER_ENTERING_WORLD reaches us
--- first (`PLAYER_LOGIN` can be missed)". The client fires PLAYER_LOGIN
--- *before* PLAYER_ENTERING_WORLD, and a frame that registers during the
--- PLAYER_LOGIN dispatch (an add-on loaded on demand by us, a late-loaded
--- split) is not yet listening for its own login event. A missed PLAYER_LOGIN
--- with no fallback is the whole add-on never enabling, so the zone-in event
--- -- which every class module's own event set includes, i.e. provably
--- arrives -- carries the pass when PLAYER_LOGIN did not reach us.
---
--- The consequence for every module (the same §7.3 law, and the reason this
--- file registers PLAYER_LOGIN on no frame but this one): login-time work
--- belongs in `OnEnable`, which this function calls DIRECTLY. A module that
--- registers `PLAYER_LOGIN` inside its own OnEnable and waits for the event
--- can wait for the whole session; addon/Forte_Core/tests/test_login_order.lua
--- proves the tree keeps to that shape.
function FX.RunLoginPass()
    if FX._loginDone then return false end
    -- pcall: on the fallback leg this runs from a zone-in handler, where a
    -- failing class read must cost the token, never the enable loop.
    local ok, _, classFile = pcall(UnitClass, "player")
    FX._playerClass = (ok and type(classFile) == "string") and classFile or nil
        -- e.g. "HUNTER", "WARLOCK" -- matches ForteXorcist.Data keys title-cased below
    -- Load-on-demand: every Forte_<Class> add-on is metadata-only until
    -- this call (Core/Loader.lua). Its files run to completion before
    -- LoadClassAddOn returns, so its data table and its modules are in the
    -- registry before the enable loop below -- the class's modules enable in
    -- the same pass, in registration order, as everyone else's. A failure
    -- prints one notice there and costs this class its tools, nothing else.
    FX.LoadClassAddOn(FX._playerClass)
    for _, name in ipairs(FX._moduleOrder) do
        FX.EnableModule(name)
    end
    -- From here on, a module that registers is enabled at once (see
    -- FX.RegisterModule); the login loop above must never run twice.
    FX._loginDone = true
    FX.PrintStartupLine()
    return true
end

local bootstrap = CreateFrame("Frame")
-- The tests' handle: they dispatch events on it, so the login and zone-in
-- paths are driven through the real script (the Forte_Cooldown module's
-- `M._eventFrame` convention).
FX._bootstrapFrame = bootstrap
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("PLAYER_LOGIN")
bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
bootstrap:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" then
        if addonName ~= FX.CONST.ADDON_NAME then return end
        _G[FX.CONST.SV_KEY] = _G[FX.CONST.SV_KEY] or {}
        FX.db = _G[FX.CONST.SV_KEY]
        -- The schema ladder (Core/Database.lua, FE-22): runs on the raw
        -- SavedVariables table here -- after every Forte_* file has been
        -- parsed (ADDON_LOADED) and before any module reads FX.db -- so a
        -- migration never races a reader and a broken step can not take the
        -- login down. Never raises; it prints and stops.
        FX.DB.Migrate(FX.db)
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- The login fallback: a no-op when PLAYER_LOGIN reached us (the
        -- normal order), the whole login pass when it did not. See
        -- FX.RunLoginPass.
        FX.RunLoginPass()
        -- Zone-in re-read (the login capture inside FX.RunLoginPass is the
        -- first one): the uiforever T4 artifact class guard, see
        -- FX.RefreshPlayerClass.
        FX.RefreshPlayerClass()
    elseif event == "PLAYER_LOGIN" then
        -- The normal login driver; FX.RunLoginPass is one-shot, so the
        -- PLAYER_ENTERING_WORLD leg above can never repeat this work.
        FX.RunLoginPass()
    end
end)
