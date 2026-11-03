-- addon/Forte_Core/tests/test_database.lua
-- The SavedVariables schema of Forte_Core/Core/Database.lua: the ordered
-- migration ladder (v0 = the flat settings map -> v1 = the profiles table
-- -> v2 = the default-equal prune), its idempotence, the never-fatal law,
-- the shape guard and the `Name-Realm` profile key. Synthetic DB tables --
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
    assertEquals(2, DB.SCHEMA_VERSION)
    assertEquals("function", type(DB.MIGRATIONS[1]))
    assertEquals("function", type(DB.MIGRATIONS[2]))
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

test("a fresh install lands on the v2 shape with empty profiles", function()
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
    assertEquals(2, DB.Migrate(db))
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
    -- an install stamped at 2 runs no step at all.
    cd.Height = 24
    assertEquals(2, DB.Migrate(db))
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

test("the character key is Name-Realm and a session constant", function()
    local key = DB.CharacterKey()
    assertNotNil(key)
    local name = UnitName("player")
    assertTrue(key:find(name, 1, true) ~= nil, "the key leads with the name: " .. key)
    local realm = GetRealmName and GetRealmName()
    if type(realm) == "string" and realm ~= "" then
        assertEquals(name .. "-" .. realm, key,
            "the realm comes from GetRealmName (GetServerName is not in the catalog)")
    end
    assertEquals(key, DB.CharacterKey(), "cached: a mid-session nil can not orphan the profile")
end)

test("the live FX.db reached the v2 shape through the bootstrap", function()
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
