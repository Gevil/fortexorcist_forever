-- addon/Forte_Core/tests/test_database.lua
-- The SavedVariables schema of Forte_Core/Core/Database.lua: the ordered
-- migration ladder (v0 = the flat settings map -> v1 = the profiles table
-- -> v2 = the default-equal prune -> v3 = the Name-Realm -> plain-name
-- re-key), its idempotence, the never-fatal law, the shape guard and the
-- plain-name profile key (docs/research/upstream-api-2026-11-03.md §2).
-- Synthetic DB tables --
-- plus one look at the live FX.db to prove the bootstrap in Core/Init.lua ran
-- the ladder at ADDON_LOADED, before any module could read the DB.
--
-- The acceptance law this file carries (PLAN §11.1 H3 + wave 5): "migration
-- of a v0 DB snapshot", "never erroring at login", "v2 drops stored values
-- equal to their current default; a user-set value survives".

local FX = ForteXorcist
local DB = FX.DB

local function countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- Today's shape (2026-11-02): NO `version`, one flat `settings` map, the
--- frame positions and the probe log beside it.
local function v0DB()
    return {
        settings = {
            Cooldown = { Width = 311, Lock = false, BarColor = { 1, 0, 0, 1 } },
            General = { FrameScale = 1.5 },
        },
        optionsPos = { point = "CENTER", relPoint = "CENTER", x = 3, y = -4 },
        cooldownDisplay = { point = "CENTER", x = 0, y = -150, locked = true },
        probes = { { label = "ooc" } },
        probeEpoch = 2,
    }
end

test("FX.DB ships the schema surface", function()
    assertNotNil(DB, "Forte_Core/Core/Database.lua loaded")
    assertEquals(3, DB.SCHEMA_VERSION)
    assertEquals("function", type(DB.MIGRATIONS[1]))
    assertEquals("function", type(DB.MIGRATIONS[2]))
    assertEquals("function", type(DB.MIGRATIONS[3]))
    assertEquals("function", type(DB.Migrate))
    assertEquals("function", type(DB.Guard))
    assertEquals("function", type(DB.CharacterKey))
    assertEquals(DB.SHARED_NAME, "ForteXorcist")
end)

test("a v0 snapshot migrates: the flat settings map becomes this character's profile",
function()
    local db = v0DB()
    assertEquals(0, DB.Stamp(db), "an unversioned file is v0")
    local to = DB.Migrate(db)
    assertEquals(DB.SCHEMA_VERSION, to)
    assertEquals(DB.SCHEMA_VERSION, db.version)

    local key = DB.CharacterKey()
    assertNotNil(key, "the client gives a player name")
    local p = db.profiles
    assertEquals(true, p.perCharacter, "per-character is the default (the original's instances)")
    assertEquals(DB.SHARED_NAME, p.shared)
    assertEquals(key, p.active)
    assertEquals(key, p.characters[key], "this character is bound to its own profile")
    assertNotNil(p.byName[key])
    -- The VALUES ride the move, not a re-default.
    assertEquals(311, p.byName[key].settings.Cooldown.Width)
    assertEquals(false, p.byName[key].settings.Cooldown.Lock)
    assertEquals(1, p.byName[key].settings.Cooldown.BarColor[1])
    assertEquals(1.5, p.byName[key].settings.General.FrameScale)
    -- The account-wide profile starts as a COPY, never as a live alias.
    assertNotNil(p.byName[DB.SHARED_NAME])
    assertEquals(311, p.byName[DB.SHARED_NAME].settings.Cooldown.Width)
    p.byName[key].settings.Cooldown.Width = 100
    assertEquals(311, p.byName[DB.SHARED_NAME].settings.Cooldown.Width,
        "the two profiles do not share a settings table")
    -- v0's map is GONE: a second live table for the same settings is the
    -- defect the step exists to prevent.
    assertEquals(nil, db.settings)
    -- Everything that is not settings rode through untouched.
    assertEquals(3, db.optionsPos.x)
    assertEquals(-150, db.cooldownDisplay.y)
    assertEquals(1, #db.probes)
    assertEquals(2, db.probeEpoch)
    -- Step 2 ran after the move: its marker table names the modules it
    -- pruned. (Every value in this snapshot differs from its shipped
    -- default, so the prune of a migrated v0 keeps them all.)
    assertNotNil(db.defaultsPruned, "the v2 step leaves its marker")
    assertNotNil(db.defaultsPruned.Cooldown,
        "Forte_Options' chunks registered Cooldown before the ladder ran")
    assertNotNil(db.defaultsPruned.General)
    assertEquals(311, db.profiles.byName[DB.SHARED_NAME].settings.Cooldown.Width,
        "none of these values equals a shipped default: the prune keeps them")
end)

test("the ladder is idempotent: a second pass rewrites nothing", function()
    local db = v0DB()
    DB.Migrate(db)
    local active = db.profiles.active
    db.profiles.byName[active].settings.Cooldown.Width = 123
    local sharedBefore = db.profiles.byName[DB.SHARED_NAME].settings.Cooldown.Width
    local namesBefore = countKeys(db.profiles.byName)
    local boundBefore = countKeys(db.profiles.characters)

    assertEquals(DB.SCHEMA_VERSION, DB.Migrate(db))
    assertEquals(DB.SCHEMA_VERSION, db.version)
    assertEquals(123, db.profiles.byName[active].settings.Cooldown.Width)
    assertEquals(sharedBefore,
        db.profiles.byName[DB.SHARED_NAME].settings.Cooldown.Width)
    assertEquals(namesBefore, countKeys(db.profiles.byName))
    assertEquals(boundBefore, countKeys(db.profiles.characters))
    assertEquals(nil, db.settings)
end)

test("a fresh install lands on the shipped shape with empty profiles", function()
    local db = {}
    assertEquals(DB.SCHEMA_VERSION, DB.Migrate(db))
    local key = DB.CharacterKey()
    assertEquals(key, db.profiles.active)
    assertEquals(0, countKeys(db.profiles.byName[key].settings))
    assertNotNil(db.profiles.byName[DB.SHARED_NAME])
    assertEquals(0, countKeys(db.profiles.byName[DB.SHARED_NAME].settings))
    assertNotNil(db.defaultsPruned,
        "a fresh install carries the prune marker: nothing to prune, "
        .. "later registrations are marked as they arrive")
end)

test("a v0 DB whose profiles table is only the shape repair still adopts its settings",
function()
    -- The every-login Guard runs BEFORE the ladder can be retried (a failed
    -- step, a value-layer touch): it creates an empty profiles table. "The
    -- table exists" is therefore not evidence of a migration -- the step has
    -- to look at the content, or a retried login strands the flat map and
    -- the install wakes up on defaults.
    local db = v0DB()
    DB.Guard(db)
    assertNotNil(db.profiles, "the repair created the shape")
    assertEquals(0, countKeys(db.profiles.byName))
    assertEquals(DB.SCHEMA_VERSION, DB.Migrate(db))
    local key = DB.CharacterKey()
    assertNotNil(db.profiles.byName[key], "the flat map was adopted, not stranded")
    assertEquals(311, db.profiles.byName[key].settings.Cooldown.Width)
    assertEquals(key, db.profiles.active)
    assertEquals(nil, db.settings)
end)

test("v2 drops the defaults the old seeding law froze and keeps every choice",
function()
    -- A v1 install written by the OLD value layer: the profile carries
    -- every key, the untouched ones sitting AT their shipped defaults (the
    -- uiforever probe: all 8 General keys on a player who only ever set
    -- Cooldown.Width). Values equal to the CURRENT registered default are
    -- frozen defaults and go; values that differ are indistinguishable
    -- from user choices and stay (wave 5).
    local key = DB.CharacterKey()
    local db = {
        version = 1,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = key,
            characters = { [key] = key },
            byName = {
                [key] = {
                    settings = {
                        Cooldown = {
                            Width = 311,    -- a user value: kept
                            Lock = false,   -- the shipped default is true:
                                            -- a stored false is a choice,
                                            -- kept
                            Height = 24,    -- == the shipped default:
                                            -- frozen, goes
                            Spark = true,   -- == the shipped default:
                                            -- frozen, goes
                        },
                    },
                },
                [DB.SHARED_NAME] = {
                    settings = {
                        Cooldown = { Height = 24 },
                    },
                },
            },
        },
    }
    assertEquals(DB.SCHEMA_VERSION, DB.Migrate(db))
    local cd = db.profiles.byName[key].settings.Cooldown
    assertEquals(311, cd.Width, "a user-set value survives v2")
    assertEquals(false, cd.Lock,
        "a stored value that differs from the shipped default survives")
    assertEquals(nil, cd.Height,
        "the frozen default goes: the key follows the shipped value from now on")
    assertEquals(nil, cd.Spark)
    assertEquals(nil, db.profiles.byName[DB.SHARED_NAME].settings.Cooldown.Height,
        "every profile of the install is pruned, not only the active one")
    assertNotNil(db.defaultsPruned.Cooldown,
        "the modules registered at the ladder are marked done in the file")
    -- Idempotence: the marker is the step's own output; a retried ladder of
    -- an install stamped at the top runs no step at all.
    cd.Height = 24
    assertEquals(DB.SCHEMA_VERSION, DB.Migrate(db))
    assertEquals(24, cd.Height,
        "a retried login of a stamped install drops nothing new")
end)

test("a raising step stops the ladder, stamps the last good version and never propagates",
function()
    local saved1, saved2 = DB.MIGRATIONS[1], DB.MIGRATIONS[2]
    local savedVersion = DB.SCHEMA_VERSION
    local ok, stamp
    do
        DB.MIGRATIONS[1] = function() error("invented step broke") end
        DB.MIGRATIONS[2] = function(db) db.stepTwoRan = true end
        DB.SCHEMA_VERSION = 2
        local db = v0DB()
        ok, stamp = pcall(DB.Migrate, db)
        assertTrue(ok, "Migrate never propagates a step's error: a broken DB must not eat the login")
        assertEquals(0, stamp, "the version stops at the last step that completed")
        assertEquals(0, db.version)
        assertEquals(nil, db.stepTwoRan, "a step after the broken one does not run")
        -- The retried login, with the step fixed: the install is picked up.
        DB.MIGRATIONS[1] = saved1
        assertEquals(2, DB.Migrate(db))
        assertEquals(2, db.version)
        assertEquals(true, db.stepTwoRan)
        assertEquals(311, db.profiles.byName[db.profiles.active].settings.Cooldown.Width)
    end
    DB.MIGRATIONS[1], DB.MIGRATIONS[2] = saved1, saved2
    DB.SCHEMA_VERSION = savedVersion
end)

test("a DB stamped ABOVE this build keeps its stamp (a downgrade steps nothing)",
function()
    local db = { version = 99 }
    assertEquals(99, DB.Migrate(db))
    assertEquals(99, db.version, "a newer build's shape is not stepped down")
    assertNotNil(db.profiles, "the shape guard still runs, so readers never crash")
end)

test("the shape guard repairs hand-edited shape and keeps the data", function()
    local db = { version = 1, profiles = {
        byName = {
            Good = { settings = { Cooldown = { Width = 7 } } },
            Junk = "a string where a profile belongs",
            Bare = {},
        },
        characters = "not a table",
        perCharacter = "yes",
        shared = "",
        active = "Missing",
    } }
    local p = DB.Guard(db)
    assertNotNil(p.byName.Good, "a real profile survives")
    assertEquals(7, p.byName.Good.settings.Cooldown.Width, "with its values")
    assertEquals(nil, p.byName.Junk, "junk under a profile name is dropped")
    assertNotNil(p.byName.Bare.settings, "a profile without settings gets one")
    assertEquals(0, countKeys(p.characters), "a non-table binding map starts empty")
    assertEquals(true, p.perCharacter, "a string is not a mode")
    assertEquals(DB.SHARED_NAME, p.shared)
    assertEquals(nil, p.active, "an active profile that does not exist is cleared")
    -- The guard is a fix, not a type law: the values it does not understand
    -- are left for the value layer, which owns the registered defaults.
    assertEquals(7, p.byName.Good.settings.Cooldown.Width)
end)

-- The key law of docs/research/upstream-api-2026-11-03.md §2 (slice I2a):
-- the key is the FULLEST PLAIN NAME, the realm label is not identity, and
-- a failed/secret read never reaches the cache. The fakes drive the three
-- name APIs; every one of them, and the caches, is restored at the end of
-- every test.
local function clearKeyCaches()
    DB._clearKeyCache()
    FX.Identity._clearSelfName()
end
local function saveNameAPIs()
    return { UnitName = _G.UnitName, UnitNameUnmodified = _G.UnitNameUnmodified,
        UnitFullName = _G.UnitFullName, GetRealmName = _G.GetRealmName,
        issecretvalue = _G.issecretvalue, UNKNOWNOBJECT = _G.UNKNOWNOBJECT }
end
local function restoreNameAPIs(saved)
    _G.UnitName, _G.UnitNameUnmodified, _G.UnitFullName =
        saved.UnitName, saved.UnitNameUnmodified, saved.UnitFullName
    _G.GetRealmName, _G.issecretvalue = saved.GetRealmName, saved.issecretvalue
    _G.UNKNOWNOBJECT = saved.UNKNOWNOBJECT
    clearKeyCaches()
end
local function v3Profiles(active, characters, byName)
    return {
        version = 3,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = active,
            characters = characters,
            byName = byName,
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
end

test("the character key is the fullest plain name, realm-free, and a session constant",
function()
    local key = DB.CharacterKey()
    assertNotNil(key)
    local name = UnitName("player")
    assertTrue(key:find(name, 1, true) ~= nil, "the key is built on the name: " .. key)
    local realm = GetRealmName and GetRealmName()
    if type(realm) == "string" and realm ~= "" then
        assertTrue(key:find(realm, 1, true) == nil,
            "no realm label in the key (a connection label, not identity): " .. key)
        assertTrue(key:find("-", 1, true) == nil,
            "no hyphen: the old Name-Realm shape is gone: " .. key)
    end
    assertEquals(key, DB.CharacterKey(), "cached: a mid-session nil can not orphan the profile")
end)

test("a two-part name is the whole name: the key packs the parts, keeps them all",
function()
    local saved = saveNameAPIs()
    clearKeyCaches()
    _G.UnitNameUnmodified = function() return "Aria Dawnsong" end
    _G.UnitFullName = function() return "Aria Dawnsong", "Somewhere" end
    _G.UnitName = function() return "Aria Dawnsong" end
    assertEquals("AriaDawnsong", DB.CharacterKey(),
        "first+last is ONE character: the space is packed out, nothing cut")
    restoreNameAPIs(saved)
end)

test("the UNKNOWNOBJECT placeholder is a failed read: nil key, nothing cached",
function()
    local saved = saveNameAPIs()
    clearKeyCaches()
    -- Early in loading the name reads answer the localized placeholder
    -- (the live enUS string; the global for the other locales) instead of
    -- nil. A profile key built on it is an orphan factory.
    _G.UnitNameUnmodified = function() return tostring(_G.UNKNOWNOBJECT) end
    _G.UnitFullName = function() return "UNKNOWN" end
    _G.UnitName = function() return "Unknown" end
    assertEquals(nil, DB.CharacterKey(), "the placeholder is no name")
    -- The next good read wins: the placeholder read cached nothing.
    _G.UnitNameUnmodified = function() return "Aria Dawnsong" end
    _G.UnitFullName = nil
    _G.UnitName = nil
    assertEquals("AriaDawnsong", DB.CharacterKey(),
        "the good read after the placeholder is THE key")
    restoreNameAPIs(saved)
end)

test("the key rides the API with the MOST name parts, not the first answer",
function()
    local saved = saveNameAPIs()
    clearKeyCaches()
    -- The live-unknown of the research note: UnitName's surname is
    -- display-conditional. The two-part answer must win from ANY of the
    -- three APIs, and the raising ones may not spoil the good reads.
    _G.UnitNameUnmodified = function() error("locked") end
    _G.UnitFullName = function() return "Aria Dawnsong" end
    _G.UnitName = function() return "Aria" end
    assertEquals("AriaDawnsong", DB.CharacterKey(), "the fuller read wins")
    clearKeyCaches()
    _G.UnitNameUnmodified = function() return "Aria Dawnsong" end
    _G.UnitFullName = function() error("locked") end
    _G.UnitName = function() error("locked") end
    assertEquals("AriaDawnsong", DB.CharacterKey(), "the raising halves drop out")
    clearKeyCaches()
    _G.UnitNameUnmodified = nil
    _G.UnitFullName = nil
    _G.UnitName = function() return "Aria Dawnsong" end
    assertEquals("AriaDawnsong", DB.CharacterKey(),
        "a lone UnitName carries a two-part name too")
    restoreNameAPIs(saved)
end)

test("a failed or secret name read answers nil and caches NOTHING",
function()
    local saved = saveNameAPIs()
    clearKeyCaches()
    _G.UnitNameUnmodified = function() error("client raise") end
    _G.UnitFullName = function() error("client raise") end
    _G.UnitName = function() error("client raise") end
    assertEquals(nil, DB.CharacterKey(), "a raising read is a nil, not an error")
    -- The secret string (SecretWhenUnitIdentityRestricted): type() is
    -- "string", it passes every string test — only PlainOrNil may stop it,
    -- and the string op on it runs inside the pcall.
    local SECRET = "FXTEST-SECRET-NAME"
    _G.issecretvalue = function(v) return v == SECRET end
    _G.UnitNameUnmodified = function() return SECRET end
    _G.UnitFullName = function() return SECRET, SECRET end
    _G.UnitName = function() return SECRET end
    assertEquals(nil, DB.CharacterKey(), "a secret name names nobody")
    -- Not cached: the next good read is THE key.
    _G.issecretvalue = saved.issecretvalue
    _G.UnitNameUnmodified = function() return "Aria Dawnsong" end
    _G.UnitFullName = nil
    _G.UnitName = nil
    assertEquals("AriaDawnsong", DB.CharacterKey(),
        "the failed reads left the cache empty")
    -- The good read IS a session constant: every read dying afterwards
    -- changes nothing.
    _G.UnitNameUnmodified = function() error("locked") end
    _G.UnitFullName = function() error("locked") end
    _G.UnitName = function() error("locked") end
    assertEquals("AriaDawnsong", DB.CharacterKey())
    restoreNameAPIs(saved)
end)

test("a realm label change between two bootstraps keeps the same profile",
function()
    local saved = saveNameAPIs()
    clearKeyCaches()
    _G.GetRealmName = function() return "World-A" end
    local db = v0DB()
    assertEquals(DB.SCHEMA_VERSION, DB.Migrate(db))
    local key = DB.CharacterKey()
    db.profiles.byName[key].settings.Cooldown.Width = 277
    -- The next login: the connection reports another world label (Blizzard
    -- moves players between world instances) — the profile rides.
    _G.GetRealmName = function() return "World-B" end
    clearKeyCaches()
    assertEquals(key, DB.CharacterKey(), "the key is realm-free by law")
    assertEquals(DB.SCHEMA_VERSION, DB.Migrate(db))
    assertEquals(277, db.profiles.byName[db.profiles.active].settings.Cooldown.Width,
        "the same profile, settings and all")
    restoreNameAPIs(saved)
end)

test("v3 re-keys the current character's legacy Name-Realm rows, settings and all",
function()
    local key = DB.CharacterKey()
    assertNotNil(key)
    -- The legacy key of the OLD CharacterKey law: packed name, hyphen,
    -- packed realm label (the SHARED_NAME fallback on an empty label).
    local realm = (GetRealmName and GetRealmName() or "")
    realm = (tostring(realm):gsub("%s+", ""))
    if realm == "" then realm = DB.SHARED_NAME end
    local legacy = key .. "-" .. realm
    local db = {
        version = 2,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = legacy,
            characters = { [legacy] = legacy },
            byName = {
                [legacy] = { settings = { Cooldown = { Width = 277 } } },
                [DB.SHARED_NAME] = { settings = {} },
            },
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
    assertEquals(3, DB.Migrate(db))
    assertEquals(key, db.profiles.active, "the active profile rides the new key")
    assertNotNil(db.profiles.byName[key], "the profile moved")
    assertEquals(277, db.profiles.byName[key].settings.Cooldown.Width,
        "the settings moved WITH it: a re-key never drops them")
    assertEquals(key, db.profiles.characters[key], "the character binding moved")
    assertEquals(nil, db.profiles.byName[legacy], "the legacy spelling is gone")
    assertEquals(nil, db.profiles.characters[legacy])
    assertNotNil(db.profiles.byName[DB.SHARED_NAME], "the shared profile rode through")
    -- Idempotent: a second pass finds no legacy row.
    assertEquals(3, DB.Migrate(db))
    assertEquals(277, db.profiles.byName[key].settings.Cooldown.Width)
end)

test("v3 re-keys a legacy row of a MOVED realm label and never overwrites the new key",
function()
    local key = DB.CharacterKey()
    local saved = saveNameAPIs()
    local db = {
        version = 2,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = key .. "-World-Old",   -- the label of the login that wrote it
            characters = { [key .. "-World-Old"] = key .. "-World-Old" },
            byName = {
                [key .. "-World-Old"] = { settings = { Cooldown = { Width = 188 } } },
                [DB.SHARED_NAME] = { settings = {} },
            },
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
    _G.GetRealmName = function() return "World-New" end  -- the label moved
    clearKeyCaches()
    assertEquals(3, DB.Migrate(db))
    assertEquals(188, db.profiles.byName[key].settings.Cooldown.Width,
        "the recognition rides the NAME half, not the label: no orphaning")
    assertEquals(key, db.profiles.active)
    assertEquals(nil, db.profiles.byName[key .. "-World-Old"])
    -- The collision: a new-key profile already exists -> it stands, the
    -- legacy row is left visible, nothing is written over the new key.
    db = {
        version = 2,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = key,
            characters = { [key] = key },
            byName = {
                [key] = { settings = { Cooldown = { Width = 300 } } },
                [key .. "-World-Old"] = { settings = { Cooldown = { Width = 111 } } },
                [DB.SHARED_NAME] = { settings = {} },
            },
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
    assertEquals(3, DB.Migrate(db))
    assertEquals(300, db.profiles.byName[key].settings.Cooldown.Width,
        "the new-key entry was NOT overwritten")
    assertNotNil(db.profiles.byName[key .. "-World-Old"],
        "the legacy row is kept visible: a re-key never drops data")
    restoreNameAPIs(saved)
end)

test("v3 moves a BOUND legacy key, a user-named shape twin rides untouched",
function()
    local key = DB.CharacterKey()
    local legacy = key .. "-SimulatedRealm"
    local raid = key .. "-Raid"          -- a profile someone NAMED, not a key
    local db = {
        version = 2,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = legacy,
            characters = { [legacy] = legacy },   -- ONLY the legacy key binds
            byName = {
                [legacy] = { settings = { Cooldown = { Width = 233 } } },
                [raid] = { settings = { Cooldown = { Width = 150 } } },
                [DB.SHARED_NAME] = { settings = {} },
            },
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
    assertEquals(3, DB.Migrate(db))
    assertEquals(233, db.profiles.byName[key].settings.Cooldown.Width,
        "the bound legacy key moved")
    assertEquals(nil, db.profiles.byName[legacy])
    assertNotNil(db.profiles.byName[raid],
        "a user-named profile of the SHAPE is no character key: it rides")
    assertEquals(150, db.profiles.byName[raid].settings.Cooldown.Width)
    assertEquals(key, db.profiles.active)
end)

test("v3 recognises the uiforever shape: a legacy key of the FIRST name half",
function()
    -- The measured shape (PLAN §9, rows of 2026-11-04, uiforever): the name
    -- APIs answer a TWO-part identity, `UnitNameUnmodified` the bare FIRST
    -- name, `GetRealmName()` the connection label "Nethergarde". Today's key
    -- packs the whole name (`MorvessaAshveil`); the old key law packed the
    -- name read of ITS day with the label (`Morvessa-Nethergarde`), so an
    -- install written before the key law moved carries a legacy row whose
    -- name half is only the first half — and a whole-key canonical compare
    -- never folds the two. Without the first-name leg the character boots on
    -- defaults with her profile sitting under a key nothing reads.
    local saved = saveNameAPIs()
    _G.UnitName = function() return "Morvessa", "Ashveil" end
    _G.UnitFullName = function() return "Morvessa Ashveil", "Nethergarde" end
    _G.UnitNameUnmodified = function() return "Morvessa" end
    -- K9 M2: the first-name leg now requires the legacy key's realm
    -- LABEL to canonical-equal today's realm; pin the label the row
    -- carries so the leg speaks.
    _G.GetRealmName = function() return "Nethergarde" end
    clearKeyCaches()
    local key = DB.CharacterKey()
    assertEquals("MorvessaAshveil", key, "the key packs the FULL name")
    local legacy = "Morvessa-Nethergarde"
    local db = {
        version = 2,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = legacy,
            characters = { [legacy] = legacy },
            byName = {
                [legacy] = { settings = { Cooldown = { Width = 277 } } },
                [DB.SHARED_NAME] = { settings = {} },
            },
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
    assertEquals(3, DB.Migrate(db))
    assertEquals(key, db.profiles.active,
        "the active profile rides the packed key: the first-name row folds onto it")
    assertNotNil(db.profiles.byName[key], "the profile moved")
    assertEquals(277, db.profiles.byName[key].settings.Cooldown.Width,
        "the settings moved WITH it")
    assertEquals(key, db.profiles.characters[key],
        "the character binding followed the SAME key the profile moved from")
    assertEquals(nil, db.profiles.byName[legacy], "the legacy spelling is gone")
    assertEquals(nil, db.profiles.characters[legacy])
    assertNotNil(db.profiles.byName[DB.SHARED_NAME], "the shared profile rode through")
    -- Idempotent by content: a second pass finds no legacy row.
    assertEquals(3, DB.Migrate(db))
    assertEquals(277, db.profiles.byName[key].settings.Cooldown.Width)
    restoreNameAPIs(saved)
end)

test("v3 SIBLING GUARD: two characters sharing a first name keep their own rows",
function()
    -- K9 M2 (docs/reviews/code-review-9.md MAJOR 2): Forever names are
    -- first + surname and name uniqueness is a whole-name fact, so one
    -- account can carry "Anne Ashvale" AND "Anne Brightoak" -- and the
    -- OLD key law packed the first name plus the realm label, so both
    -- Annes of one realm wrote the SAME legacy key `Anne-Nethergarde`.
    -- The packed key then names NEITHER of them: the leg skips (the
    -- boot-defaults pre-leg behaviour), the shared row and the
    -- sibling's binding ride, and the ladder report names the skip.
    local saved = saveNameAPIs()
    _G.UnitName = function() return "Anne", "Ashvale" end
    _G.UnitFullName = function() return "Anne Ashvale", "Nethergarde" end
    _G.UnitNameUnmodified = function() return "Anne" end
    _G.GetRealmName = function() return "Nethergarde" end
    clearKeyCaches()
    local key = DB.CharacterKey()
    assertEquals("AnneAshvale", key, "the mover is Anne Ashvale")
    local legacy = "Anne-Nethergarde"
    local sibling = "AnneBrightoak"
    local db = {
        version = 3,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = legacy,
            characters = { [legacy] = legacy, [sibling] = sibling },
            byName = {
                [legacy] = { settings = { Cooldown = { Width = 277 } } },
                [sibling] = { settings = { Cooldown = { Width = 96 } } },
                [DB.SHARED_NAME] = { settings = {} },
            },
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
    DB.RekeyLegacy(db)
    assertNotNil(db.profiles.byName[legacy],
        "the shared first name names NEITHER Anne: the row rides")
    assertEquals(277, db.profiles.byName[legacy].settings.Cooldown.Width,
        "with its settings")
    assertEquals(nil, db.profiles.byName[key],
        "no profile moves onto this character: the boot is the pre-leg defaults")
    assertEquals(legacy, db.profiles.active, "the active key rides untouched")
    assertEquals(legacy, db.profiles.characters[legacy], "with the row's binding")
    assertEquals(sibling, db.profiles.characters[sibling],
        "the sibling's binding rides too")
    restoreNameAPIs(saved)
end)

test("v3 SIBLING GUARD: a legacy key of ANOTHER realm's label does not move",
function()
    -- The cross-realm twin of the sibling collision: `Anne-Nethergarde`
    -- and `Anne-Ashvenos`, both bound, the mover matching both through
    -- the head -- the pick among the matches used to fall to pairs()
    -- order. The label half of a first-name row now must
    -- canonical-equal today's realm; the alien label rides. The
    -- sibling-free whole-key leg one keeps its realm-label tolerance
    -- (the MOVED-label leg above pins it): this is leg two only.
    local saved = saveNameAPIs()
    _G.UnitName = function() return "Anne", "Ashvale" end
    _G.UnitFullName = function() return "Anne Ashvale", "Nethergarde" end
    _G.UnitNameUnmodified = function() return "Anne" end
    _G.GetRealmName = function() return "Nethergarde" end  -- today's label
    clearKeyCaches()
    local key = DB.CharacterKey()
    local alien = "Anne-Ashvenos"
    local db = {
        version = 3,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = alien,
            characters = { [alien] = alien },
            byName = {
                [alien] = { settings = { Cooldown = { Width = 143 } } },
                [DB.SHARED_NAME] = { settings = {} },
            },
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
    DB.RekeyLegacy(db)
    assertNotNil(db.profiles.byName[alien],
        "the label names another world's Anne: the row rides")
    assertEquals(143, db.profiles.byName[alien].settings.Cooldown.Width)
    assertEquals(nil, db.profiles.byName[key], "no move onto this character")
    assertEquals(alien, db.profiles.characters[alien], "with its binding")
    assertEquals(alien, db.profiles.active, "and the active key")
    restoreNameAPIs(saved)
end)

test("the first-name leg stays BOUND-GATED and never writes over the new key",
function()
    local saved = saveNameAPIs()
    _G.UnitName = function() return "Morvessa", "Ashveil" end
    _G.UnitFullName = function() return "Morvessa Ashveil", "Nethergarde" end
    _G.UnitNameUnmodified = function() return "Morvessa" end
    clearKeyCaches()
    local key = DB.CharacterKey()
    local twin = "Morvessa-Nethergarde"
    -- (a) THE NEW KEY ALREADY EXISTS, and the twin is BOUND: both write
    -- guards stand, so the twin rides as a named profile and nothing of the
    -- new key moves.
    local db = {
        version = 3,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = key,
            characters = { [key] = key, [twin] = twin },
            byName = {
                [key] = { settings = { Cooldown = { Width = 300 } } },
                [twin] = { settings = { Cooldown = { Width = 111 } } },
                [DB.SHARED_NAME] = { settings = {} },
            },
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
    DB.RekeyLegacy(db)
    assertEquals(300, db.profiles.byName[key].settings.Cooldown.Width,
        "the new-key entry is NOT overwritten")
    assertNotNil(db.profiles.byName[twin],
        "the legacy row is kept visible: a re-key never drops data")
    assertEquals(111, db.profiles.byName[twin].settings.Cooldown.Width)
    assertEquals(twin, db.profiles.characters[twin], "its binding rides")
    assertEquals(key, db.profiles.active)
    -- (b) THE TWIN IS NOT BOUND and is not the active profile: a profile of
    -- the SHAPE that nothing binds is a profile someone NAMED — the same
    -- bound gate the whole-key leg rides, now on the first-name leg.
    db = {
        version = 3,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = key,
            characters = { [key] = key },
            byName = {
                [key] = { settings = { Cooldown = { Width = 300 } } },
                [twin] = { settings = { Cooldown = { Width = 111 } } },
                [DB.SHARED_NAME] = { settings = {} },
            },
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
    DB.RekeyLegacy(db)
    assertNotNil(db.profiles.byName[twin], "an UNBOUND twin of the shape rides")
    assertEquals(111, db.profiles.byName[twin].settings.Cooldown.Width)
    assertEquals(300, db.profiles.byName[key].settings.Cooldown.Width)
    restoreNameAPIs(saved)
end)

test("a first-name half that is not this character's own prefix folds nothing",
function()
    -- The gate of the second leg is structural: the first name must be a
    -- STRICT PREFIX of the packed key. A name read that is not the
    -- character's own first half — a stranger's name on a shared profile
    -- file, and by the same law the client's `UNKNOWNOBJECT` placeholder —
    -- is no half of this identity, so her profile rides under her own key.
    local saved = saveNameAPIs()
    _G.UnitName = function() return "Morvessa", "Ashveil" end
    _G.UnitFullName = function() return "Morvessa Ashveil", "Nethergarde" end
    _G.UnitNameUnmodified = function() return "Zyxnia" end
    clearKeyCaches()
    local key = DB.CharacterKey()
    assertEquals("MorvessaAshveil", key)
    local stranger = "Zyxnia-Nethergarde"
    local db = {
        version = 3,
        profiles = {
            perCharacter = true,
            shared = DB.SHARED_NAME,
            active = key,
            characters = { [key] = key, [stranger] = stranger },
            byName = {
                [key] = { settings = { Cooldown = { Width = 300 } } },
                [stranger] = { settings = { Cooldown = { Width = 140 } } },
                [DB.SHARED_NAME] = { settings = {} },
            },
        },
        defaultsPruned = { Cooldown = true, General = true },
    }
    DB.RekeyLegacy(db)
    assertNotNil(db.profiles.byName[stranger],
        "a bound key whose name half is NOT this character rides")
    assertEquals(140, db.profiles.byName[stranger].settings.Cooldown.Width)
    assertEquals(stranger, db.profiles.characters[stranger], "with its binding")
    assertEquals(300, db.profiles.byName[key].settings.Cooldown.Width)
    assertEquals(2, (function()
        local n = 0
        for _ in pairs(db.profiles.characters) do n = n + 1 end
        return n
    end)(), "no third binding is invented")
    restoreNameAPIs(saved)
end)

test("a ladder with no readable name stamps v3; the first good key re-keys the live DB once",
function()
    local saved = saveNameAPIs()
    local realDB = FX.db
    local legacy = tostring(DB.CharacterKey()) .. "-LegacyRealm"
    local db = v3Profiles(legacy, { [legacy] = legacy },
        { [legacy] = { settings = { Cooldown = { Width = 311 } } },
          [DB.SHARED_NAME] = { settings = {} } })
    DB._clearKeyCache()
    DB._clearRekeyFlag()
    FX.Identity._clearSelfName()
    FX.db = db
    -- The ladder of a session whose name read is the placeholder: the
    -- stamp lands on 3, the legacy row is still in the file (the stamp is
    -- not a re-key, and the stamp is not undone by the failed read).
    _G.UnitName = function() return "Unknown" end
    _G.UnitNameUnmodified = nil
    _G.UnitFullName = nil
    assertEquals(nil, DB.CharacterKey())
    assertEquals(3, DB.Migrate(db))
    assertEquals(3, db.version)
    assertNotNil(db.profiles.byName[legacy],
        "with no name the re-key ran no move: the row is waiting")
    -- The first good read of the session: the login path re-keys the live
    -- DB before the key reaches a reader.
    restoreNameAPIs(saved)
    DB._clearKeyCache()
    FX.Identity._clearSelfName()
    local key = DB.CharacterKey()
    assertEquals(DB.CharacterKey(), key)
    assertEquals(311, db.profiles.byName[key].settings.Cooldown.Width,
        "the waiting legacy row moved to the plain key")
    assertEquals(nil, db.profiles.byName[legacy])
    assertEquals(key, db.profiles.active)
    -- EXACTLY ONCE: a forced second pass over the same file moves nothing.
    DB._clearRekeyFlag()
    DB.RekeyLegacy(db)
    DB.RekeyLegacy(db)
    assertEquals(2, (function()
        local n = 0
        for _ in pairs(db.profiles.byName) do n = n + 1 end
        return n
    end)(), "the file keeps exactly the two profiles: key + shared")
    FX.db = realDB
    DB._clearKeyCache()
    DB._clearRekeyFlag()
    FX.Identity._clearSelfName()
end)

test("the first key of a session runs the re-key exactly once, without recursing",
function()
    -- RekeyLegacy reads DB.CharacterKey() itself, so the login-path call
    -- inside CharacterKey must see the key already cached; otherwise every
    -- level calls back into the other until the C stack overflows and a
    -- pcall swallows it (manager review, wave I-2a).
    local realDB = FX.db
    local realRekey = DB.RekeyLegacy
    local calls = 0
    DB.RekeyLegacy = function(db)
        calls = calls + 1
        return realRekey(db)
    end
    FX.db = v3Profiles(DB.SHARED_NAME, {}, { [DB.SHARED_NAME] = { settings = {} } })
    DB._clearKeyCache()
    DB._clearRekeyFlag()
    FX.Identity._clearSelfName()
    local key = DB.CharacterKey()
    DB.RekeyLegacy = realRekey
    FX.db = realDB
    DB._clearKeyCache()
    DB._clearRekeyFlag()
    FX.Identity._clearSelfName()
    assertNotNil(key)
    assertEquals(1, calls, "one cold CharacterKey() runs RekeyLegacy once, not a recursion")
end)

test("the live FX.db reached the shipped (v3) shape through the bootstrap", function()
    assertNotNil(FX.db, "the bootstrap adopted the SavedVariables global")
    assertEquals(DB.SCHEMA_VERSION, FX.db.version,
        "Core/Init.lua ran the ladder at ADDON_LOADED")
    assertNotNil(FX.db.profiles)
    assertEquals(nil, FX.db.settings, "the v0 map is not left alive beside the profiles")
    local active = FX.db.profiles.active
    assertNotNil(active)
    assertNotNil(FX.db.profiles.byName[active], "the active profile exists")
    assertEquals(DB.SHARED_NAME, FX.db.profiles.shared)
    assertEquals(true, FX.db.profiles.perCharacter)
    -- The v2 step ran in the bootstrap: its marker names the modules the
    -- Forte_Options chunks had registered before ADDON_LOADED; a LoD page
    -- that registered at PLAYER_LOGIN is marked by the Register hook.
    assertNotNil(FX.db.defaultsPruned, "the v2 step marked this install")
    assertNotNil(FX.db.defaultsPruned.Cooldown)
    assertNotNil(FX.db.defaultsPruned.General)
end)
