-- Forte_Core/Core/Loader.lua
--
-- Load-on-demand loader for the per-class add-ons.
--
-- Every Forte_<Class> add-on ships `## LoadOnDemand: 1`: at login the client
-- reads its TOC metadata only and parses NONE of its Lua (docs/research/
-- secrets-unknowns.md §9 -- the same split Polestar's 13 data add-ons and
-- EllesmereUI's options/locales slots use on this exact client). That saves a
-- Hunter the ~300 KB of Mage/Priest/... spell data every character used to pay
-- for. This file decides WHEN the one add-on that matters -- the player's own
-- class -- is pulled in, and reports the failure cases.
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
FX._loadedClassAddOns = FX._loadedClassAddOns or {}

--- The add-on that carries this class token's data, or nil.
function FX.ClassAddOnFor(classToken)
    if type(classToken) ~= "string" then return nil end
    return FX.CLASS_ADDONS[classToken:upper()]
end

local function notice(text)
    FX.Print("|cffff5555" .. text .. "|r")
end

--- Bring the add-on that carries `classToken` into the running session.
--- Returns true when its files are in (already loaded, not load-on-demand,
--- or loaded by this call), false when they are not.
---
--- Every failure path prints ONE notice (name + the loader's own reason,
--- e.g. DISABLED for an add-on the player unchecked in the add-on list) and
--- continues: a missing class add-on costs that class its tools, not the
--- shared Cooldown/Timer/UI stack. `FX._loadedClassAddOns` is the once-only
--- ledger: a repeat call for a name that is already in is free, and a repeat
--- call for a name that failed stays quiet.
function FX.LoadClassAddOn(classToken)
    local name = FX.ClassAddOnFor(classToken)
    if not name then return false end -- no Forte add-on for this class: not an error
    -- The ledger settles a name after its first attempt: a name that is in
    -- returns true, a name that failed returns false, and NEITHER calls the
    -- loader (or prints) a second time.
    local seen = FX._loadedClassAddOns[name]
    if seen ~= nil then return seen == true end

    local api = _G.C_AddOns
    if type(api) ~= "table" or type(api.LoadAddOn) ~= "function" then
        -- No loader on this engine: nothing to pull in. Loud once, then silent.
        FX._loadedClassAddOns[name] = false
        notice("C_AddOns.LoadAddOn is unavailable: " .. name .. " data is not loaded")
        return false
    end

    -- Already in? Covers an always-loaded split (the `## LoadOnDemand` line
    -- removed) and an add-on someone else (a /fx probe, another addon, a
    -- test file that needs its data) loaded first. IsAddOnLoaded returns
    -- (loadedOrLoading, loaded).
    local loaded = api.IsAddOnLoaded and api.IsAddOnLoaded(name)
    if loaded then
        FX._loadedClassAddOns[name] = true
        return true
    end

    local ok, value = api.LoadAddOn(name)
    if ok then
        FX._loadedClassAddOns[name] = true
        return true
    end

    FX._loadedClassAddOns[name] = false
    notice(name .. " did not load (" .. tostring(value) .. ") -- its class tools stay off")
    return false
end

--- True when the add-on that carries `classToken` is in the running session
--- (loaded on demand by us, loaded eagerly, not load-on-demand -- the
--- question the caller asks is "is its data usable right now").
function FX.IsClassAddOnLoaded(classToken)
    local name = FX.ClassAddOnFor(classToken)
    if not name then return false end
    local api = _G.C_AddOns
    if type(api) ~= "table" or type(api.IsAddOnLoaded) ~= "function" then
        return FX._loadedClassAddOns[name] == true
    end
    return (api.IsAddOnLoaded(name)) and true or false
end
