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
-- Step 3 is the identity re-key: the original keyed characters
-- `Name-Realm` (`FW:FullName()`), and the v1 move kept that key — on
-- Forever the law moved (docs/research/upstream-api-2026-11-03.md §2: a
-- character is its first+last name, `GetRealmName()` is a CONNECTION label
-- that moves between logins): the key is now the plain packed player name
-- and step 3 re-keys this character's legacy `Name-Realm` rows to it. The
-- prose for the key lives at DB.CharacterKey.
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
DB.SCHEMA_VERSION = 3

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

--- v2 -> v3: the character key lost its realm half
--- (docs/research/upstream-api-2026-11-03.md §2, Atraeau b64aab0a: on
--- Forever a character is its first+last name and `GetRealmName()` is a
--- CONNECTION label that moves between logins — a key carrying it can
--- orphan this character's profile on a plain party move). The step
--- re-keys the CURRENT character's legacy `Name-Realm` rows — profile
--- `byName`, character `characters` binding, `active` — to the new
--- realm-free key.
---   * never lose settings: the move carries the profile table over as it
---     stands;
---   * never overwrite an existing new-key entry: with both spellings in
---     the file the new-key profile stands untouched and the legacy row
---     stays visible as a named profile (nothing is deleted, the
---     character keeps riding its new key);
---   * a legacy row is a key of the SHAPE the old CharacterKey wrote — the
---     packed name, a hyphen, any realm label — whose name half matches
---     this character canonically, so a realm label that moved between the
---     write and now is still picked up. The name half matches on EITHER
---     the WHOLE key (the old read answered the full name) OR this
---     character's FIRST name (the read `UnitNameUnmodified` answers on a
---     Forever client — the measured uiforever shape of PLAN §9, rows of
---     2026-11-04: `UnitNameUnmodified` = "Morvessa" while the key today is
---     "MorvessaAshveil", so the file carries "Morvessa-Nethergarde"); the
---     second leg is gated on that first name being a STRICT PREFIX of the
---     packed key, so it folds one character's own two spellings and never
---     a second player of the same first name. The match is additionally
---     BOUND-GATED (the key is a key of `characters` — every real
---     character key binds itself there — or equals `active`), so a
---     profile the USER named e.g. "Uther-Raid" is left exactly where it
---     is: the shape alone does not prove a key was written by the old
---     CharacterKey law;
---   * IDEMPOTENT by content: after the move no legacy spelling of this
---     character remains; a second pass finds nothing.
--- The step body lives in DB.RekeyLegacy: the ladder runs it once, and
--- because a nil name read here is a NO-OP the ladder still stamps (the
--- file is v3 with the legacy rows in place), the login path of
--- DB.CharacterKey runs it again on FX.db the first time a key is
--- produced — a failed read at the ladder costs the install the move
--- until the first good read of a later session, never forever.
DB.MIGRATIONS[3] = function(db)
    DB.RekeyLegacy(db)
end

--- The v3 re-key, idempotent, callable from the ladder and the login path.
--- Moves ONE best legacy row (preferring one with non-empty settings),
--- plus its `characters` binding and a matching `active`, onto the plain
--- key. Runs at most once per session (a once-flag): a second call is a
--- no-op — the ladder that ran it, and the login-path call that follows,
--- are the two mouths of the SAME law, not two passes over the file.
local rekeyed
function DB.RekeyLegacy(db)
    local key = DB.CharacterKey()
    if not isTable(db) then return end
    if not key then return end
    -- The flag marks a RAN move, not an attempted step: with no readable
    -- name the ladder stamps v3 over an unre-keyed file and the flag
    -- stays down — the login path of CharacterKey is the session's second
    -- mouth of this law, running the move the moment a key exists.
    rekeyed = true
    local p = db.profiles
    if not isTable(p) then return end
    local keyCanon = FX.Identity.Canonical(key)
    if not keyCanon then return end
    -- The character's FIRST name, canonically: what `UnitNameUnmodified`
    -- answers on a Forever client (measured on uiforever, PLAN §9 rows of
    -- 2026-11-04: `UnitNameUnmodified` = "Morvessa" beside
    -- `UnitName` = ("Morvessa", "Ashveil")). The old key law packed the
    -- name read of ITS day, so a file can carry "Morvessa-Nethergarde"
    -- while today's key is "MorvessaAshveil" — a whole-key canonical
    -- compare never folds those two. The read rides this file's name law:
    -- the call pcall'd (the identity reads are
    -- SecretWhenUnitIdentityRestricted), the value through
    -- FX.Identity.Canonical, which classifies it via PlainOrNil first (a
    -- secret name has type() == "string"), and a failed read is a nil that
    -- costs this session only the second recognition leg.
    -- The gate is structural: the first name must be a STRICT PREFIX of
    -- the packed key — one character's own first half, never the full name
    -- (that is leg one), never a placeholder read, and never a DIFFERENT
    -- character who happens to share the first name.
    local firstCanon
    local okFirst, first = pcall(function()
        if type(_G.UnitNameUnmodified) ~= "function" then return nil end
        local okRead, bare = pcall(_G.UnitNameUnmodified, "player")
        if not okRead then return nil end
        return FX.Identity.Canonical(bare)
    end)
    if okFirst and type(first) == "string"
        and #first < #keyCanon and keyCanon:sub(1, #first) == first then
        firstCanon = first
    end
    local function legacyOf(k)
        if type(k) ~= "string" or k == key then return false end
        local head = k:match("^(.-)%-")            -- the name before the label
        if not head or head == "" then return false end
        local headCanon = FX.Identity.Canonical(head)
        if headCanon == keyCanon then return true end
        return firstCanon ~= nil and headCanon == firstCanon
    end
    -- The move moves a LEGACY KEY OF THIS CHARACTER, not any key of the
    -- shape: a shape match alone would re-key a user-named profile like
    -- "Uther-Raid" onto the character key. The old law bound EVERY
    -- character key it wrote into `characters` (and Bind keeps that law),
    -- and a live install's `active` is one of them — a key of the shape
    -- that is neither is a profile someone NAMED, not a key to re-key.
    local characters, active
    if isTable(p.characters) then characters = p.characters end
    if type(p.active) == "string" then active = p.active end
    local function boundToCharacter(k)
        if characters and characters[k] ~= nil then return true end
        return active ~= nil and active == k
    end
    -- Collect first: assigning a NEW key inside pairs() is illegal. The
    -- cursor is HOISTED past the byName leg so the binding leg below moves
    -- the SAME key: pairs() has no order, and with the two first-name legs
    -- a file can carry more than one legacy spelling of this character.
    local moveKey
    if isTable(p.byName) then
        for k, profile in pairs(p.byName) do
            if legacyOf(k) and boundToCharacter(k) then
                local st = type(profile) == "table" and profile.settings
                if moveKey == nil or (type(st) == "table" and next(st) ~= nil) then
                    moveKey = k
                end
            end
        end
        if moveKey and p.byName[key] == nil then
            p.byName[key] = p.byName[moveKey]
            p.byName[moveKey] = nil
        end
    end
    if characters then
        local bind
        if moveKey ~= nil and characters[moveKey] ~= nil then
            bind = moveKey
        else
            for k in pairs(characters) do
                if legacyOf(k) then bind = k end
            end
        end
        if bind and characters[key] == nil then
            local bound = characters[bind]
            if bound == bind then
                -- Self-bound (the character rode a profile named by the
                -- old key): the byName move RENAMED that profile, the
                -- binding follows it. A binding to any other profile
                -- (the shared one, a renamed custom one) is a name the
                -- step has no claim on — it rides.
                bound = key
            end
            characters[key] = bound
            characters[bind] = nil
        end
    end
    if legacyOf(active) then p.active = key end
end

--- The test seam (and only that): let RekeyLegacy run again — the state a
--- fresh install's first login stands in.
function DB._clearRekeyFlag()
    rekeyed = nil
end

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

--- The profile key of this install's character: the FULLEST PLAIN PLAYER
--- NAME — no realm. The law moved with upstream-api-2026-11-03 §2 (Atraeau
--- b64aab0a, "a character is its first and last name"): on Forever the
--- name is first+last and `GetRealmName()` is a CONNECTION label that can
--- change between logins (Blizzard's own party moves shift players to
--- another world instance), so a key carrying it would orphan this
--- character's profile the first time the label moves. The read is
--- FX.Identity.SelfName — the fullest of `UnitNameUnmodified`/
--- `UnitFullName`/`UnitName`, every call and every string op inside a
--- pcall, every value through PlainOrNil, a failed/secret read caching
--- NOTHING — packed (the spaces out, the way the old key packed them; the
--- name half's spelling rule is unchanged, so the v3 migration recognises
--- the legacy rows). The result is cached: a session constant once a good
--- read happened, so a mid-session nil can not orphan the profile.
local cachedKey
function DB.CharacterKey()
    if cachedKey then return cachedKey end
    local ok, name = pcall(function()
        local n = FX.Identity.SelfName()
        if type(n) ~= "string" then return nil end
        return (n:gsub("%s+", ""))
    end)
    if not ok then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    -- Cache FIRST: RekeyLegacy reads DB.CharacterKey() itself, and with the
    -- key not yet cached the two would call each other until the C stack
    -- overflowed inside the pcall (198 levels measured; manager review,
    -- wave I-2a, test "...exactly once, without recursing").
    cachedKey = name
    -- The login path of the v3 step (RekeyLegacy's own header): the
    -- ladder ran its step when this character's name was not readable
    -- (a nil/placeholder read) — the file is stamped v3 with the legacy
    -- rows in place — so the first key of a session runs the re-key on
    -- the live DB, before the key reaches a reader. Once-flagged, pcall'd
    -- (the never-fatal law of this file: a half move retried next
    -- login), silent.
    if not rekeyed and isTable(FX) and isTable(FX.db) then
        pcall(DB.RekeyLegacy, FX.db)
    end
    return cachedKey
end

--- The test seam (and only that): forget the cached key — the boundary a
--- fresh bootstrap stands at (the session itself re-logs in with a fresh
--- global environment, where this cache is already empty).
function DB._clearKeyCache()
    cachedKey = nil
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
