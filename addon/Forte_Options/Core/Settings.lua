-- Forte_Options/Core/Settings.lua
-- The value layer of the options window. Every page registers a module's
-- defaults table once; live values live in FX.db.settings[module]
-- (SavedVariables, ForteXorcistDB). Defaults NEVER overwrite a saved value:
-- seeding copies a default only where the saved table has nil.
--
-- Contract (docs/reference-functional-spec.md §8.1 OP-03/OP-04, PLAN §3.6):
--   * values are flat scalars, strings, arrays (time-tag string is one string)
--     or nested tables for colours: { r, g, b, a } (the original's positional
--     colour shape).
--   * Reset(module) restores every key of the module; Reset(module, key)
--     restores one key. Both write the *deep copy* of the registered default,
--     so callers can mutate the table they get back from Get() without
--     corrupting the default.
--   * Set fires every callback registered through OnChange(module, fn) as
--     fn(key, value) -- this is the wiring seam pages use to push a value
--     into a live consumer (e.g. FX.Cooldown.Display:SetLocked).
--
-- Load-time safety: Forte_Options' chunks run before Forte_Core's bootstrap
-- sees ADDON_LOADED, so FX.db is not set yet when Register() executes. The
-- defaults are plain data at that point; the storage table is resolved
-- lazily on first Get/Set/Reset (by then OnEnable-time at the earliest),
-- with a session-local fallback table when SavedVariables never arrived.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

local S = {}
FX.Settings = S

-- Registered defaults: [module] = { key = default }. Read-only after
-- registration; handed out only through GetDefault's deep copy.
local defaults = {}
-- Callbacks: [module] = { fn, ... }
local listeners = {}
-- Session fallback when FX.db is absent (mirrors Timeline's fallbackCfg).
local sessionFallback

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = deepCopy(val) end
    return out
end
S._deepCopy = deepCopy   -- shared with the widget layer (colour rows)

--- The live storage table for a module, seeded from the registered defaults
--- without overwriting any saved value.
local function store(module)
    local base
    if FX.db then
        FX.db.settings = FX.db.settings or {}
        base = FX.db.settings
    else
        sessionFallback = sessionFallback or {}
        base = sessionFallback
    end
    local t = base[module]
    if not t then
        t = {}
        base[module] = t
    end
    local def = defaults[module]
    if def then
        for key, value in pairs(def) do
            if t[key] == nil then
                t[key] = deepCopy(value)
            end
        end
    end
    return t
end
S._store = store

--- Register a module's defaults table (data only -- safe at load time).
--- Re-registering the same module replaces the default set (idempotent for
--- the page files, which register from their own chunk).
function S:Register(moduleName, def)
    defaults[moduleName] = def
end

function S:IsRegistered(moduleName)
    return defaults[moduleName] ~= nil
end

function S:GetModuleNames()
    local names = {}
    for name in pairs(defaults) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function S:Get(moduleName, key)
    return store(moduleName)[key]
end

--- Write a value and notify this module's change listeners.
function S:Set(moduleName, key, value)
    local t = store(moduleName)
    t[key] = value
    local fns = listeners[moduleName]
    if fns then
        for i = 1, #fns do
            local ok, err = pcall(fns[i], key, value)
            if not ok then
                FX.Print("|cffff5555settings listener failed for "
                    .. moduleName .. "." .. tostring(key) .. ":|r " .. tostring(err))
            end
        end
    end
    return value
end

--- How many change listeners a module carries (read-only test seam,
--- CodeReview3 m1: the single-registration convention -- Init/hook paths
--- must not multiply their listeners across class round trips; the count
--- is the observable of that law).
function S:CountListeners(moduleName)
    local fns = listeners[moduleName]
    return fns and #fns or 0
end

--- fn(key, value) fires after every Set on this module.
function S:OnChange(moduleName, fn)
    local fns = listeners[moduleName]
    if not fns then
        fns = {}
        listeners[moduleName] = fns
    end
    fns[#fns + 1] = fn
end

--- A deep copy of the registered default for one key (nil when unregistered
--- key). Used by Reset and by every per-option recycle icon.
function S:GetDefault(moduleName, key)
    local def = defaults[moduleName]
    return def and deepCopy(def[key])
end

--- key form: restore one key. module form: restore every key of the module.
--- Writes flow through Set, so live consumers get notified.
function S:Reset(moduleName, key)
    if key ~= nil then
        return S:Set(moduleName, key, S:GetDefault(moduleName, key))
    end
    local def = defaults[moduleName]
    if not def then return end
    for k in pairs(def) do
        S:Set(moduleName, k, deepCopy(def[k]))
    end
end
