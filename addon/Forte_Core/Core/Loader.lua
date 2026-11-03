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
-- class loader in the login pass (Core/Init.lua's FX.RunLoginPass, driven by
-- PLAYER_LOGIN, or by the first PLAYER_ENTERING_WORLD when PLAYER_LOGIN was
-- missed), a feature loader (Forte_Cooldown/Core/Procs.lua for
-- Forte_ItemProcs) at the moment its own switch is switched
-- on -- and reports the failure cases. `FX.LoadAddOnOnDemand(name)` is the
-- general, idempotent seam; `FX.LoadClassAddOn(token)` is its class half.
--
-- The law: a class add-on is loaded inside the login pass, BEFORE
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
--
-- The listing law (F-B, 2026-11-02): `C_AddOns.IsAddOnLoaded` is the ADD-ON
-- LIST's answer, and a runner can list an add-on it never parsed -- under
-- `run-tests Forte_<Class>` the add-on under test is listed while its Lua has
-- not run. Every "already in?" decision therefore also asks the add-on's
-- liveness probe (`FX.ADDON_MARKERS`: the data table its own first file
-- defines), and a listed-but-not-run add-on goes through `LoadAddOn` like any
-- other. That is what lets a class suite state its subject with
-- `FX.LoadClassAddOn("<CLASS>")` and nothing else.

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

--- name -> count of times the add-on LIST said "in" while the add-on's own
--- probe said its files had not run (the `run-tests` shape; see the listing
--- law at the top). A diagnostic, never a decision.
FX._listedNotRun = FX._listedNotRun or {}

--- The add-on that carries this class token's data, or nil.
function FX.ClassAddOnFor(classToken)
    if type(classToken) ~= "string" then return nil end
    return FX.CLASS_ADDONS[classToken:upper()]
end

--- The liveness probe of every load-on-demand add-on we ask for: a function
--- answering true when the add-on's FILES have actually run. `IsAddOnLoaded`
--- reports the add-on list's state, not the Lua machine's, and the two can
--- disagree: under `run-tests Forte_<Class>` the runner puts the add-on under
--- test in its add-on list -- `C_AddOns.IsAddOnLoaded("Forte_Shaman")` answers
--- true, `C_AddOns.IsAddOnLoadOnDemand` answers true -- while NONE of its
--- files have been parsed (measured in the sim: `FX.Data.Shaman` absent, the
--- module unregistered). Trusting the listing settles the idempotence ledger
--- on `true` and the add-on's data and modules never arrive, which is why
--- Forte_Shaman's suite had to call the raw loader behind our back.
---
--- A probe is the add-on's own file-load side effect -- the data table its
--- first file defines -- so the question "is its data usable right now" is
--- answered from the Lua state, the only state that has to be right. The nine
--- class add-ons are derived from CLASS_ADDONS (their file defines
--- `FX.Data.<Class>`); a new class add-on needs no second entry. An add-on
--- with NO probe (an always-loaded split, a third-party name) answers true:
--- there is nothing to check, so the listing is all we have and is trusted.
FX.ADDON_MARKERS = {}
for token, name in pairs(FX.CLASS_ADDONS) do
    local dataKey = name:gsub("^Forte_", "")
    FX.ADDON_MARKERS[name] = function()
        return FX.Data ~= nil and FX.Data[dataKey] ~= nil
    end
end
FX.ADDON_MARKERS.Forte_ItemProcs = function()
    return FX.Data ~= nil and FX.Data.ItemProcs ~= nil
end

--- True when the add-on `name`'s files have run (no probe: the loader's
--- listing is the only evidence and is believed).
function FX.AddOnFilesRan(name)
    if type(name) ~= "string" then return false end
    local probe = FX.ADDON_MARKERS[name]
    if probe == nil then return true end
    local ok, ran = pcall(probe)
    return (ok and ran) and true or false
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
    --
    -- LISTED IS NOT RUN: the listing is the add-on list's answer, so it is
    -- accepted only when the add-on's own probe says its files ran (see
    -- FX.ADDON_MARKERS). A listed-but-never-parsed add-on -- exactly the
    -- `run-tests Forte_<Class>` shape, where the runner lists the add-on under
    -- test -- falls through to the loader below, which is idempotent and runs
    -- the files. Counted, so a test harness is visible from `/fx status`.
    local listed = api.IsAddOnLoaded and api.IsAddOnLoaded(name)
    if listed then
        if FX.AddOnFilesRan(name) then
            FX._loadedAddOns[name] = true
            return true
        end
        FX._listedNotRun = FX._listedNotRun or {}
        FX._listedNotRun[name] = (FX._listedNotRun[name] or 0) + 1
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
--- asks is "is its data usable right now"). The add-on's own probe is part of
--- the answer: a listed-but-never-parsed add-on's data is NOT usable, so this
--- says false and the caller asks `LoadAddOnOnDemand` for it (which loads it
--- for real, the listing being no obstacle).
function FX.IsAddOnLoadedOnDemand(name)
    if type(name) ~= "string" then return false end
    local api = _G.C_AddOns
    if type(api) ~= "table" or type(api.IsAddOnLoaded) ~= "function" then
        return FX._loadedAddOns[name] == true
    end
    if not api.IsAddOnLoaded(name) then return false end
    return FX.AddOnFilesRan(name)
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
