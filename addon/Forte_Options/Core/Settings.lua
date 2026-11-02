-- Forte_Options/Core/Settings.lua
-- The value layer of the options window, and the home of the profile model.
-- Every page registers a module's defaults table once; live values live in
-- the ACTIVE PROFILE's table, `db.profiles.byName[<profile>].settings[module]`
-- (SavedVariables, ForteXorcistDB, shape owned by Forte_Core/Core/Database.lua).
-- Defaults NEVER overwrite a saved value: seeding copies a default only where
-- the profile table has nil.
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
--     into a live consumer (e.g. FX.Cooldown.Display:SetLocked). It is also
--     the ONLY apply path of a profile switch (FX.Profiles.ApplyLive).
--
-- PROFILES (PLAN §11.1 H3; the original's FE-21 profile/instance model --
-- `Forte_Core.lua:2142-2162` FW:UseProfile, `:1078-1084` FW_InitConfig, the
-- tab row `Forte_Core/Options.lua:5454-5489`, and the strings at
-- `Forte_Core/Localization.lua:339-341`):
--   * a profile is one profile-name -> { settings = { [module] = {...} } }
--     row of `db.profiles.byName`;
--   * BY DEFAULT a character rides its own profile, keyed `Name-Realm`
--     (FX.DB.CharacterKey, the original's FW:FullName), recorded in
--     `db.profiles.characters[key] = <profile name>`;
--   * `db.profiles.perCharacter = false` makes the whole account ride the one
--     shared profile (`db.profiles.shared`); the character bindings survive
--     the toggle, so switching back restores them;
--   * switching writes the new active profile and pushes every key through
--     Set, so a switch is applied by exactly the notifications a checkbox
--     click produces -- no second apply path to keep in sync.
--   * the UI sits in the window's PROFILE TAB ROW (Forte_Options/UI/Window.lua
--     RefreshProfileTabs), which is where the original's tabs were
--     (`Options.lua:4849-4901` main_data.tabs), and on the Profiles page. It is
--     NOT a cell of the module index: the original never had one.
--
-- KEY SANITY (the "corrupt saved vars" defence): a profile's module table is
-- type-checked against that module's registered defaults the first time this
-- session touches the module, and a key whose value does not match the
-- default's type -- or that the module does not know at all -- is dropped, so
-- seeding puts the default back. A module that is NOT registered in this
-- session is left completely alone: with `## LoadOnDemand: 1` a Hunter page
-- registers its module only on a Hunter, and "unknown" there is another
-- class's data, not corruption. Junk under a module NAME (a string where the
-- table belongs) is dropped with it.
--
-- Load-time safety: Forte_Options' chunks run before Forte_Core's bootstrap
-- sees ADDON_LOADED, so FX.db is not set yet when Register() executes. The
-- defaults are plain data at that point; the storage table is resolved
-- lazily on first Get/Set/Reset (by then OnEnable-time at the earliest),
-- with a session-local fallback table when SavedVariables never arrived.
-- The schema ladder runs in the bootstrap's ADDON_LOADED handler
-- (Forte_Core/Core/Init.lua), i.e. before the first Get of any module.

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
-- Key sanity passes already run: checked[<profile>][<module>] = true.
local checked = {}
-- Keys dropped by that pass (launch-day evidence, printed once).
local droppedKeys = 0

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = deepCopy(val) end
    return out
end
S._deepCopy = deepCopy   -- shared with the widget layer (colour rows)

-- =============================================================== profiles ==
local P = {}
FX.Profiles = P
S.Profiles = P

--- The name of the account-wide profile (FX.DB.SHARED_NAME's twin; the
--- migration writes the same constant).
P.SHARED_NAME = "ForteXorcist"
P.MAX_NAME = 32

local root            -- the live db.profiles table (or the session fallback)
local bound = false   -- the active profile of THIS session is resolved
local selfKey         -- cached `Name-Realm` (a session constant)

local function selfName()
    if not selfKey then
        selfKey = (FX.DB and FX.DB.CharacterKey())
            or ((UnitName and UnitName("player")) or "Player")
    end
    return selfKey
end

local function profilesRoot()
    if root then return root end
    if FX.db then
        -- Forte_Core's shape guard (Core/Database.lua) owns the repair; the
        -- inline branch is the same repair for a DB that predates it.
        if FX.DB and FX.DB.Guard then
            root = FX.DB.Guard(FX.db)
        end
        if not root then
            if type(FX.db.profiles) ~= "table" then FX.db.profiles = {} end
            root = FX.db.profiles
        end
    else
        sessionFallback = sessionFallback
            or { perCharacter = true, shared = P.SHARED_NAME,
                 active = nil, characters = {}, byName = {} }
        root = sessionFallback
    end
    if type(root.byName) ~= "table" then root.byName = {} end
    if type(root.characters) ~= "table" then root.characters = {} end
    if type(root.perCharacter) ~= "boolean" then root.perCharacter = true end
    if type(root.shared) ~= "string" or root.shared == "" then
        root.shared = P.SHARED_NAME
    end
    return root
end
S._profilesRoot = profilesRoot   -- read-only test seam

--- The settings table of one profile (created on demand).
local function profileSettings(name)
    local r = profilesRoot()
    local p = r.byName[name]
    if type(p) ~= "table" then
        p = { settings = {} }
        r.byName[name] = p
    end
    if type(p.settings) ~= "table" then p.settings = {} end
    return p.settings
end

--- Resolve which profile this session rides, once. FW_InitConfig's pick
--- (Forte_Core.lua:1078-1084): the profile bound to this character, else the
--- profile this install last used, else a fresh per-character profile
--- (perCharacter) / the shared one.
function P.Bind(force)
    local r = profilesRoot()
    local me = selfName()
    if bound and not force and type(r.active) == "string"
        and r.byName[r.active] then
        return r.active
    end
    local mine = r.perCharacter and r.characters[me]
    if type(mine) ~= "string" or not r.byName[mine] then mine = nil end
    local last = (type(r.active) == "string" and r.byName[r.active])
        and r.active or nil
    local want = mine or last
        or (r.perCharacter and me)
        or r.shared
    profileSettings(want)
    r.active = want
    if r.perCharacter then r.characters[me] = want end
    bound = true
    return want
end

function P.Active() return P.Bind() end
function P.IsShared(name) return name == profilesRoot().shared end
function P.IsPerCharacter() return profilesRoot().perCharacter and true or false end
function P.Self() return selfName() end

function P.List()
    P.Bind()
    local names = {}
    for name in pairs(profilesRoot().byName) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function P.Exists(raw)
    local name = P.SanitizeName(raw)
    return name ~= nil and profilesRoot().byName[name] ~= nil
end

--- Trim + reject: empty, over P.MAX_NAME, colour codes (`|`) or control
--- characters would poison every string the name is printed into.
function P.SanitizeName(raw)
    if type(raw) ~= "string" then return nil end
    local s = raw:match("^%s*(.-)%s*$")
    if s == nil or s == "" or #s > P.MAX_NAME then return nil end
    if s:find("[%|%c]") then return nil end
    return s
end

--- Case-insensitive lookup of an existing profile -> the stored name.
function P.Find(raw)
    local name = P.SanitizeName(raw)
    if not name then return nil end
    local r = profilesRoot()
    if r.byName[name] then return name end
    local low = name:lower()
    for stored in pairs(r.byName) do
        if stored:lower() == low then return stored end
    end
    return nil
end

-- ------------------------------------------------------- key sanity pass --
--- Drop the keys of one module table that the registered defaults do not
--- license. Legal during pairs(): assigning nil to an EXISTING key is the
--- one mutation Lua allows while traversing.
local function sanitizeTable(def, t)
    local n = 0
    for key, value in pairs(t) do
        local d = def[key]
        if d == nil then
            t[key] = nil
            n = n + 1
        elseif type(value) ~= type(d) then
            t[key] = nil
            n = n + 1
        end
    end
    return n
end

--- Type-check one profile over every module registered in THIS session.
--- Returns the number of dropped keys.
function S:SanitizeProfile(name)
    local base = profileSettings(name)
    local n = 0
    for _, module in ipairs(S:GetModuleNames()) do
        local v = base[module]
        if v ~= nil and type(v) ~= "table" then
            base[module] = nil
            n = n + 1
        elseif type(v) == "table" then
            n = n + sanitizeTable(defaults[module], v)
        end
    end
    return n
end

--- Every profile of the install (the switch-time pass for profiles that
--- were never touched this session).
function S:SanitizeAllProfiles()
    local n = 0
    for _, name in ipairs(P.List()) do
        n = n + S:SanitizeProfile(name)
    end
    droppedKeys = droppedKeys + n
    return n
end

function S.DroppedKeys() return droppedKeys end

-- ------------------------------------------------------------------ store --
--- The live storage table for a module, in the ACTIVE PROFILE, seeded from
--- the registered defaults without overwriting any saved value. The
--- type-check pass is keyed by (profile, module): a profile the player
--- switches to is checked when this session first reads it, and a profile
--- it returns to is not re-checked.
local function store(module)
    local profileName = P.Bind()
    local base = profileSettings(profileName)
    local t = base[module]
    if type(t) ~= "table" then
        t = {}
        base[module] = t
    end
    local def = defaults[module]
    if def then
        local seen = checked[profileName]
        if not seen then seen = {}; checked[profileName] = seen end
        if not seen[module] then
            seen[module] = true
            local n = sanitizeTable(def, t)
            if n > 0 then
                droppedKeys = droppedKeys + n
                -- The player has to see that the file was repaired, once per
                -- (profile, module): a silent repair reads as "my settings
                -- vanished at the update".
                FX.Print(string.format(
                    "repaired %d saved value(s) of %s in the profile %s;"
                    .. " they are back on their defaults",
                    n, module, tostring(profileName)))
            end
        end
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

-- ------------------------------------------------------ profile operations --
--- Push the active profile's values through the live seam: every registered
--- module's every key goes back out through Set, so every OnChange consumer
--- (the pages' wiring, the modules' ApplySettings) re-reads the new profile.
--- This is FW:UseProfile's `FW_CopyNew(FW.Default, FW.Settings)` +
--- `FW:RefreshFrames()` pass (Forte_Core.lua:2155-2158) in our idiom.
function P.ApplyLive()
    for _, module in ipairs(S:GetModuleNames()) do
        local t = store(module)          -- seeds + type-checks the new profile
        for key, value in pairs(t) do
            S:Set(module, key, value)
        end
    end
end

--- Copy the ACTIVE profile into a new one (the original's `[create new]
--- copies your current settings to a new profile`, Localization.lua:341).
--- @return name | nil, reason
function P.Create(raw)
    local r = profilesRoot()
    P.Bind()
    local name = P.SanitizeName(raw)
    if not name then
        return nil, "a profile name must be 1.." .. P.MAX_NAME
            .. " characters without spaces at the edges, | or control characters"
    end
    if P.Find(name) then return nil, "a profile of that name exists already" end
    r.byName[name] = { settings = deepCopy(profileSettings(r.active)) }
    return name
end

--- Delete a profile. The last one can not go (FW:InstanceDelete refuses to
--- empty the list, Forte_Core.lua:2100-2115); the characters bound to it move
--- to a survivor (the `root.Characters` fix, Options.lua:5476-5489), and so
--- does this session when it rode it.
function P.Delete(raw)
    local r = profilesRoot()
    local name = P.Find(raw)
    if not name then return nil, "no profile of that name" end
    local names = P.List()
    if #names <= 1 then return nil, "the last profile can not be deleted" end
    local fallback
    for _, other in ipairs(names) do
        if other ~= name then fallback = other break end
    end
    r.byName[name] = nil
    for who, target in pairs(r.characters) do
        if target == name then r.characters[who] = fallback end
    end
    if r.active == name then
        r.active = fallback
        if r.perCharacter then r.characters[selfName()] = fallback end
        P.ApplyLive()
    end
    return true
end

--- Switch profiles, live.
function P.Select(raw)
    local r = profilesRoot()
    P.Bind()
    local name = P.Find(raw)
    if not name then return nil, "no profile of that name" end
    if r.active == name then return true end
    r.active = name
    if r.perCharacter then r.characters[selfName()] = name end
    P.ApplyLive()
    return true
end

--- Per-character (true, the default) or one account-wide profile (false).
--- The character bindings are KEPT across the toggle, so switching back
--- restores exactly what each character rode: Select and Bind only write
--- `characters[me]` while per-character mode is ON, so sharing never
--- overwrites a binding. Turning sharing off moves this session back to the
--- profile its own key is bound to.
function P.SetPerCharacter(on)
    local r = profilesRoot()
    P.Bind()
    on = not not on
    if r.perCharacter == on then return true end
    r.perCharacter = on
    local target
    if on then
        local mine = r.characters[selfName()]
        target = (type(mine) == "string" and r.byName[mine]) and mine
            or selfName()
    else
        target = r.shared
        -- Sharing starts as a copy of what the player already had, never as
        -- an empty page.
        if not r.byName[target] then
            r.byName[target] = { settings = deepCopy(profileSettings(r.active)) }
        end
    end
    profileSettings(target)
    r.active = target
    if on then r.characters[selfName()] = target end
    P.ApplyLive()
    return true
end

-- ================================================================== reset ==
-- `/fx reset <module> | all | list | confirm | cancel` (FE-23: the original's
-- `reset` / `resetall`, Forte_Core.lua:2384-2399). Bare `/fx reset` stays the
-- Cooldown bar's position reset: Forte_Cooldown's Display claims the exact
-- word ahead of every registered sub (Core/Init.lua's dispatch order,
-- test_timeline.lua:482-490 asserts it), so this command always carries an
-- argument.
--
-- EVERY reset asks first. The confirmation is Blizzard's own generic yes/no
-- (`StaticPopup_ShowGenericConfirmation(text, callback)`,
-- Blizzard_StaticPopup/StaticPopup.lua:225, called the same way by
-- Blizzard_AccountStoreCardTemplates.lua:183 -- the live Forever equivalent
-- of the original's StaticPopupDialogs rows, Forte_Core.lua:1374-1379 and
-- Options.lua:5471-5489). Where that add-on is not loaded (a headless run, a
-- minimal UI) the chat line names the second command, `/fx reset confirm`,
-- which is the same gate.
local pending              -- { module = <name> } | { module = nil } = everything

local function moduleOf(word)
    if type(word) ~= "string" or word == "" then return nil, "which module?" end
    local low = word:lower()
    for _, name in ipairs(S:GetModuleNames()) do
        if name:lower() == low then return name end
    end
    return nil, "no module '" .. word .. "'"
        .. " (its page is not registered in this session)"
end

local function ask(mode)
    return mode == "chat"
        and " Confirm with |cff" .. FX.CONST.HEX.ACCENT .. "/fx reset confirm|r."
        or ""
end

--- Arm a reset and ask. `target` = a module name, or nil/"all" for every
--- registered module. Shared by the slash and the Profiles page's buttons.
function S.RequestReset(target)
    local name, err
    if target ~= nil and target ~= "all" then
        name, err = moduleOf(tostring(target))
        if not name then
            FX.Print("|cffff5555" .. tostring(err) .. "|r")
            return false
        end
    end
    local label = name and ("the " .. name .. " module") or "every module"
    pending = { module = name }
    local shown = false
    local show = _G.StaticPopup_ShowGenericConfirmation
    if type(show) == "function" then
        local ok = pcall(show,
            "ForteXorcist: reset " .. label .. " to the shipped defaults?",
            function() S.ConfirmReset() end)
        shown = ok and true or false
    end
    FX.Print(string.format("reset %s -- your settings for %s are thrown away.%s",
        label, name and "it" or "every module",
        ask(shown and "popup" or "chat")))
    return true
end

function S.ConfirmReset()
    if not pending then
        FX.Print("nothing to confirm: /fx reset <module|all> asks first")
        return false
    end
    local name = pending.module
    pending = nil
    if name then
        S:Reset(name)
        FX.Print("reset " .. name .. " to the shipped defaults")
    else
        local names = S:GetModuleNames()
        for _, mod in ipairs(names) do S:Reset(mod) end
        FX.Print(string.format("reset %d modules to the shipped defaults", #names))
    end
    return true
end

function S.CancelReset()
    if not pending then return false end
    local name = pending.module
    pending = nil
    FX.Print("cancelled: nothing was reset" .. (name and (" (" .. name .. ")") or ""))
    return true
end

function S.PendingReset()
    return pending and (pending.module or "all") or nil
end

FX.RegisterSlash("reset", function(rest)
    rest = (rest or ""):match("^%s*(.-)%s*$")
    local word = rest:match("^(%S+)")
    if word == "confirm" then
        S.ConfirmReset()
    elseif word == "cancel" then
        S.CancelReset()
    elseif word == "list" then
        local names = S:GetModuleNames()
        FX.Print(string.format("modules (%d): %s", #names,
            table.concat(names, ", ")))
    elseif rest == "" then
        FX.Print("use |cff" .. FX.CONST.HEX.ACCENT .. "/fx reset <module>|r,"
            .. " |cff" .. FX.CONST.HEX.ACCENT .. "/fx reset all|r"
            .. " (|cff" .. FX.CONST.HEX.ACCENT .. "/fx reset list|r names them;"
            .. " bare /fx reset resets the cooldown bar's position)")
    else
        S.RequestReset(rest)
    end
end)
