-- Forte_Core/Core/Database.lua
-- The `ForteXorcistDB` SavedVariables schema: its version stamp, the ordered
-- migration list and the shape guard. The global is declared by
-- `## SavedVariables: ForteXorcistDB` (Forte_Core.toc) and adopted into FX.db
-- by the bootstrap frame; Core/Init.lua calls FX.DB.Migrate(FX.db) right after
-- that adoption -- the one moment at which every Forte_* file has been parsed
-- and no module has read the DB yet. A version ladder therefore runs before
-- any reader exists, which is what keeps it non-fatal at login.
--
-- The law is the original's (docs/reference-functional-spec.md FE-22:
-- `Forte_Core.lua:1367-1583`):
--   * a `version` in the DB and one ORDERED list of steps, each step runs
--     exactly once per install;
--   * a step is a plain `function(db)` mutating in place, and is IDEMPOTENT:
--     re-run on already-migrated data it does nothing (a step that failed
--     half-way is retried on the next login);
--   * a raising step is stamped and reported, never fatal. The original
--     answered a broken DB by unregistering every event, emptying FW.Settings
--     and showing a popup (`Forte_Core.lua:1374-1384`); a build that shows
--     nothing at login is a bug report, not a fix, so we stop the ladder and
--     keep every reader on its defaults;
--   * `FX.DB.Guard` runs on EVERY login and repairs structure (a string where
--     a table belongs, a hand-edited file), so no reader can crash on shape.
--
-- Step 1 is the profiles table. v0 (the shape up to 2026-11-02) kept ONE flat
-- `db.settings[module][key]` map for the whole install; v1 moves it into
-- `db.profiles.byName[<profile>].settings` so settings can be per-character --
-- the original's per-instance profile binding (`FW:FullName()` =
-- `PLAYER.."-"..SERVER`, `Forte_Core.lua:1074-1076`; the character -> profile
-- pick at `:1078-1084`; the switch at `:2142-2162`). The value layer that reads
-- the shape is FX.Settings (Forte_Options/Core/Settings.lua), its UI is
-- Forte_Options/Pages/Profiles.lua, and docs/profiles.md is the prose.
-- Step 2 is the default prune: the old value layer seeded every registered
-- default into every profile table, so installs carried (and froze) the
-- defaults of the build that wrote them; the layer is now sparse (stores
-- only values that differ from the registered default) and step 2 drops the
-- stored values equal to their current defaults, lazily per module at
-- registration for the LoD pages the ladder cannot see (the marker table
-- `db.defaultsPruned` is the hand-off).
--
-- Version numbering is NUMERIC here (0, 1, 2 ...), not the original's
-- string-compared "v1.975.1" (`FX_Saved.VERSION < "v1.90"`, :1374): a string
-- compare of two-part names is how that ladder grew a "fix the v1.975 bug"
-- branch of its own.

ForteXorcist = ForteXorcist or {}
local FX = ForteXorcist

local DB = {}
FX.DB = DB

--- The shape this build writes. A DB stamped ABOVE it is from a newer build:
--- the ladder skips (Forward compatibility, PLAN §11.1 H3: a downgrade must
--- not invent keys) and the shape guard still repairs what it can.
DB.SCHEMA_VERSION = 2

DB.SHARED_NAME = "ForteXorcist"

--- The ordered ladder. Index = the version the step PRODUCES.
DB.MIGRATIONS = {}

--- v0 -> v1: the flat settings map becomes the character's first profile.
DB.MIGRATIONS[1] = function(db)
    -- Idempotent by CONTENT, not by the presence of the tables: FX.DB.Guard
    -- runs on every login (and after a failed step) and creates an empty
    -- `profiles.byName`, so "the table exists" is not evidence of a migration.
    -- A migrated install has a shared name and at least one profile. A fresh
    -- install lands here too and gets the empty tables.
    local p = db.profiles
    if type(p) == "table" and type(p.byName) == "table"
        and type(p.shared) == "string" and p.shared ~= ""
        and next(p.byName) ~= nil then
        return
    end
    local legacy = type(db.settings) == "table" and db.settings or nil
    local name = DB.CharacterKey() or DB.SHARED_NAME
    local profiles = {
        perCharacter = true,
        shared = DB.SHARED_NAME,
        active = name,
        characters = {},
        byName = {},
    }
    profiles.characters[name] = name
    profiles.byName[name] = { settings = legacy or {} }
    -- The account-wide profile starts as a COPY of the migrated settings, so
    -- a player who turns sharing on never lands on an empty page.
    profiles.byName[DB.SHARED_NAME] = { settings = DB.deepCopy(profiles.byName[name].settings) }
    db.profiles = profiles
    -- The moved map is REMOVED, not left as an alias: two live tables for the
    -- same settings is the defect this step exists to prevent.
    db.settings = nil
end

--- v1 -> v2: drop the defaults FROZEN into the profiles (PLAN §11.1 wave 5
--- "Settings defaults"). The live uiforever probe: a profile carried EVERY
--- key of EVERY module (all 8 General keys on a player who only ever set
--- Cooldown.Width; `AltTimeFormat = false`, the default of an older build,
--- beat the shipped true) because the old value layer SEEDED the defaults
--- into the profile tables. The layer now stores only values that differ
--- from the registered default (Forte_Options/Core/Settings.lua, the sparse
--- store); this step cleans what the old law left behind: over every
--- profile it drops every stored value equal to its CURRENT registered
--- default. A stored value that differs from the shipped default survives:
--- it is indistinguishable from a user choice, and data loss is the worse
--- failure (a v0 `Lock = false` under the shipped true stays).
---
--- LAZY BY MODULE: the ladder runs at ADDON_LOADED (Core/Init.lua), the
--- load-on-demand pages -- Hunter, Spell Timer, the Warlock plates, the
--- Messages pages -- register their defaults only at PLAYER_LOGIN, and the
--- standing law of the original's ladder ("always use real values for
--- defaults in modules, since these defaults/modules may not be loaded",
--- Forte_Core.lua:1332) forbids inventing the missing ones here. So the
--- step (a) prunes every module REGISTERED IN THIS SESSION and (b) leaves
--- the marker table `db.defaultsPruned` with the pruned module names;
--- FX.Settings:Register prunes every later registration lazily at its
--- registration (the module name is its entry in the marker). A module no
--- session ever registers (a class that is not the player's) is pruned by
--- the first session that registers it -- until then a stored value equal
--- to the current default reads identically to the default, so nothing
--- hangs on the timing. Idempotent by CONTENT: the marker table is the
--- step's own output.
DB.MIGRATIONS[2] = function(db)
    if type(db.defaultsPruned) ~= "table" then
        local mark = {}
        db.defaultsPruned = mark
        local st = FX.Settings
        if st and type(st.PruneStoredDefaults) == "function" then
            st.PruneStoredDefaults(db, mark)
        end
    end
end

local function isTable(v) return type(v) == "table" end

--- Structural repair, run on every login (idempotent, allocation-free).
--- Repairs the SHAPE of db.profiles (the shape step 1 writes) and drops
--- non-table profiles. Key-level sanity is the value layer's job
--- (FX.Settings:SanitizeProfile, Forte_Options/Core/Settings.lua): the
--- registered defaults -- the only type law a key can be checked against --
--- are registered there.
function DB.Guard(db)
    if not isTable(db) then return nil end
    if not isTable(db.profiles) then db.profiles = {} end
    local p = db.profiles
    if not isTable(p.byName) then p.byName = {} end
    if not isTable(p.characters) then p.characters = {} end
    if type(p.perCharacter) ~= "boolean" then p.perCharacter = true end
    if type(p.shared) ~= "string" or p.shared == "" then p.shared = DB.SHARED_NAME end
    if type(p.active) == "number" then p.active = tostring(p.active) end
    if type(p.active) ~= "string" then p.active = nil end
    for name, profile in pairs(p.byName) do
        if not isTable(profile) then
            p.byName[name] = nil
        elseif not isTable(profile.settings) then
            profile.settings = {}
        end
    end
    if p.active and not p.byName[p.active] then p.active = nil end
    return p
end

--- The profile this install's character is keyed by: "Name-Realm". Realm via
--- GetRealmName -- a documented global on Forever (the window title uses it
--- for the same reason; GetServerName is NOT in the pinned catalog). The
--- result is cached: the value is a constant for the session and every
--- profile name derives from it, so a mid-session nil can not orphan the
--- profile of this character.
local cachedKey
function DB.CharacterKey()
    if cachedKey then return cachedKey end
    local okN, name = pcall(function() return UnitName and UnitName("player") end)
    if not okN or type(name) ~= "string" or name == "" then return nil end
    name = name:gsub("%s+", "")
    local realm = ""
    if type(GetRealmName) == "function" then
        local okR, r = pcall(GetRealmName)
        if okR and type(r) == "string" then realm = r:gsub("%s+", "") end
    end
    if realm == "" then realm = DB.SHARED_NAME end
    cachedKey = name .. "-" .. realm
    return cachedKey
end

--- Deep copy of the plain data a SavedVariables table may hold (numbers,
--- strings, booleans, tables). The one Settings.lua shares for colour rows.
function DB.deepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = DB.deepCopy(val) end
    return out
end

--- The stamp of a DB as an integer: nil/0 for an unversioned (v0) file.
function DB.Stamp(db)
    local v = isTable(db) and tonumber(rawget(db, "version"))
    if not v then return 0 end
    return math.floor(v)
end

--- Run the ladder. Never raises: every step runs in a pcall and the version
--- stops at the last step that completed, so the next login retries the
--- broken one. Returns the stamp the DB ended on.
function DB.Migrate(db)
    if not isTable(db) then return nil end
    local from = DB.Stamp(db)
    if from >= DB.SCHEMA_VERSION then
        -- A DB from a NEWER build: repair the shape, run no step, and keep
        -- the stamp it came with -- stamping it down to this build's version
        -- would make the next build re-run steps it has already had.
        DB.Guard(db)
        return from
    end
    local at = from
    for step = from + 1, DB.SCHEMA_VERSION do
        local fn = DB.MIGRATIONS[step]
        if fn then
            -- The steps run on the RAW table: each one recognises its own
            -- input shape, which is also what makes it idempotent. Guarding
            -- first would hand step 1 a table that already looks migrated.
            local ok, err = pcall(fn, db)
            if not ok then
                DB.Guard(db)  -- repair what the half step left
                db.version = at
                FX.Print("|cffff5555saved-variable migration step " .. step
                    .. " failed; settings fall back to their defaults "
                    .. "(retried next login):|r " .. tostring(err))
                return at
            end
        end
        at = step
        db.version = step
    end
    DB.Guard(db)
    db.version = DB.SCHEMA_VERSION
    return at
end
