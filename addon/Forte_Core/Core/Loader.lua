-- Forte_Core/Core/Loader.lua
--
-- Load-on-demand loader: the per-class add-ons, and the general seam any
-- Forte add-on that ships `## LoadOnDemand: 1` data uses to ask for it.
--
-- Every Forte_<Class> add-on ships `## LoadOnDemand: 1`: at login the client
-- reads its TOC metadata only and parses NONE of its Lua (docs/research/
-- secrets-unknowns.md §9 -- the same split Polestar's 13 data add-ons and
-- EllesmereUI's options/locales slots use on this exact client). That saves a
-- Hunter the ~300 KB of Mage/Priest/... spell data every character used to pay
-- for. This file decides WHEN a load-on-demand add-on is pulled in -- the
-- class loader at PLAYER_LOGIN, a feature loader (Forte_Cooldown/Core/
-- Procs.lua for Forte_ItemProcs) at the moment its own switch is switched
-- on -- and reports the failure cases. `FX.LoadAddOnOnDemand(name)` is the
-- general, idempotent seam; `FX.LoadClassAddOn(token)` is its class half.
--
-- The law: a class add-on is loaded inside the PLAYER_LOGIN handling, BEFORE
-- the module enable loop in Init.lua runs, so its `FX.RegisterModule` calls
-- land in the registry in file order and its modules enable in the same pass
-- as everyone else's. `C_AddOns.LoadAddOn` runs the add-on's files to
-- completion before it returns (measured in the sim: the data table and the
-- registered modules are visible on the next statement), and the add-on's
-- `ADDON_LOADED` fires on that load.
--
-- Init.lua's `FX.RefreshPlayerClass` (PLAYER_ENTERING_WORLD) calls this too:
-- tooling can change the player's class mid-session (PLAN §10.4 T4), and the
-- new class's add-on must come with it. A class with no add-on (Forever 1.60.1
-- has no Death Knight) loads nothing and is not an error.
--
-- No frame and no RegisterEvent lives here: the events belong to Init.lua's
-- bootstrap frame (AGENTS.md: no top-level RegisterEvent outside the
-- bootstrap).

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

--- Class token (`UnitClass("player")`'s second return, e.g. "HUNTER") -> the
--- add-on that carries that class. A static map by design: the names are
--- ours, and an unknown token must not be turned into a guessed add-on name.
FX.CLASS_ADDONS = {
    DRUID = "Forte_Druid",
    HUNTER = "Forte_Hunter",
    MAGE = "Forte_Mage",
    PALADIN = "Forte_Paladin",
    PRIEST = "Forte_Priest",
    ROGUE = "Forte_Rogue",
    SHAMAN = "Forte_Shaman",
    WARLOCK = "Forte_Warlock",
    WARRIOR = "Forte_Warrior",
}

-- Add-on names this session has already brought in (or failed to). One
-- notice per name, ever: a per-zone class re-read must not print again.
-- The ledger is keyed by ADD-ON NAME, not by class token: the class loader
-- and the general `FX.LoadAddOnOnDemand` share it, so a name a class path
-- already brought in costs the feature that asks for it next nothing.
FX._loadedAddOns = FX._loadedAddOns or {}

--- The add-on that carries this class token's data, or nil.
function FX.ClassAddOnFor(classToken)
    if type(classToken) ~= "string" then return nil end
    return FX.CLASS_ADDONS[classToken:upper()]
end

local function notice(text)
    FX.Print("|cffff5555" .. text .. "|r")
end

--- Bring the load-on-demand add-on `name` into the running session.
--- Returns true when its files are in (already loaded, not load-on-demand,
--- or loaded by this call), false when they are not. IDEMPOTENT: the ledger
--- settles a name after its first attempt -- a name that is in returns true,
--- a name that failed returns false, and NEITHER calls the loader (or prints)
--- a second time.
---
--- Every failure path prints ONE notice (name + the loader's own reason,
--- e.g. DISABLED for an add-on the player unchecked in the add-on list) and
--- continues: a missing add-on costs the feature that asked for it, not the
--- shared Cooldown/Timer/UI stack.
---
--- This is the general seam (`FX.LoadClassAddOn` is its class-token half).
--- A feature that owns a load-on-demand data add-on asks for it here at the
--- moment its own switch is switched on -- the class loader asks at
--- PLAYER_LOGIN, `Forte_Cooldown/Core/Procs.lua` asks at the first
--- `Cooldown.Procs` enable -- and treats `false` as "the feature is off",
--- never as an error. `C_AddOns.LoadAddOn` runs the add-on's files to
--- completion before it returns, so the caller's data reads on the next
--- statement are valid.
function FX.LoadAddOnOnDemand(name)
    if type(name) ~= "string" or name == "" then return false end
    local seen = FX._loadedAddOns[name]
    if seen ~= nil then return seen == true end

    local api = _G.C_AddOns
    if type(api) ~= "table" or type(api.LoadAddOn) ~= "function" then
        -- No loader on this engine: nothing to pull in. Loud once, then silent.
        FX._loadedAddOns[name] = false
        notice("C_AddOns.LoadAddOn is unavailable: " .. name .. " is not loaded")
        return false
    end

    -- Already in? Covers an always-loaded split (the `## LoadOnDemand` line
    -- removed) and an add-on someone else (a /fx probe, another addon, a
    -- test file that needs its data) loaded first. IsAddOnLoaded returns
    -- (loadedOrLoading, loaded).
    local loaded = api.IsAddOnLoaded and api.IsAddOnLoaded(name)
    if loaded then
        FX._loadedAddOns[name] = true
        return true
    end

    local ok, value = api.LoadAddOn(name)
    if ok then
        FX._loadedAddOns[name] = true
        return true
    end

    FX._loadedAddOns[name] = false
    notice(name .. " did not load (" .. tostring(value) .. ") -- its features stay off")
    return false
end

--- True when the add-on `name` is in the running session (loaded on demand by
--- us, loaded eagerly, or not load-on-demand at all -- the question the caller
--- asks is "is its data usable right now").
function FX.IsAddOnLoadedOnDemand(name)
    if type(name) ~= "string" then return false end
    local api = _G.C_AddOns
    if type(api) ~= "table" or type(api.IsAddOnLoaded) ~= "function" then
        return FX._loadedAddOns[name] == true
    end
    return (api.IsAddOnLoaded(name)) and true or false
end

--- Bring the add-on that carries `classToken` into the running session.
--- Returns true when its files are in (already loaded, not load-on-demand,
--- loaded by this call), false when they are not. A class with no Forte
--- add-on (Forever 1.60.1 has no Death Knight) loads nothing, prints nothing
--- and is NOT an error.
function FX.LoadClassAddOn(classToken)
    local name = FX.ClassAddOnFor(classToken)
    if not name then return false end -- no Forte add-on for this class: not an error
    return FX.LoadAddOnOnDemand(name)
end

--- True when the add-on that carries `classToken` is in the running session
--- (loaded on demand by us, loaded eagerly, not load-on-demand -- the
--- question the caller asks is "is its data usable right now").
function FX.IsClassAddOnLoaded(classToken)
    local name = FX.ClassAddOnFor(classToken)
    if not name then return false end
    return FX.IsAddOnLoadedOnDemand(name)
end
