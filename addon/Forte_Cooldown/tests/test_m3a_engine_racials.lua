-- addon/Forte_Cooldown/tests/test_m3a_engine_racials.lua
-- Wave M3a (review-10 M2/m4 + MT-7/MT-8): the racials ride the GENERATED
-- data (`racial = true` rows of the class files, the data-diff-live
-- 2026-11-07 pinning), Engine:Build SKIPS them (Build's contract: class kit
-- only, its count tests unchanged) and Engine:AddExtras enlists them from
-- the same rows -- the data's NAME, the data's cooldown, the data's
-- `shares` link. The hand-kept Engine.RACIALS table (English keys, ids that
-- bypassed every data refresh) is deleted, and the Arcane Blast pin (the
-- 18091 weapon proc out, the 400573 self-buff without a cooldown in) is what
-- keeps the fake 8 s bar off the Mage's timeline.
--
-- Sharing law: FX.Cooldown.Engine is the session's one instance; like
-- test_engine.lua, every test attaches a private storage, rebuilds its own
-- tracked set, and the last registered test hands the module storage back
-- (the framework has no teardown).

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine

FX.LoadClassAddOn("HUNTER")
FX.LoadClassAddOn("MAGE")

local originalStorage = Engine.learned
local function freshStorage()
    Engine:AttachStorage({})
end

local function allKnown() return true end
-- ms -> s divisions are floats: compare with tolerance (test_engine.lua's
-- measured law), never exact equality.
local function near(actual, expected)
    return assertTrue(math.abs(actual - expected) < 1e-6)
end
local function trackedCount()
    local n = 0
    for _ in pairs(Engine.tracked) do n = n + 1 end
    return n
end
--- Mirror of the M3a Engine:Build predicate: floor + name, NOT a racial row.
local function expectedBuildCount(data)
    local n = 0
    for _, spell in pairs(data) do
        local cd = spell.cooldownMs and spell.cooldownMs / 1000
        if cd and cd >= Engine.MIN_COOLDOWN and spell.name and not spell.racial then
            n = n + 1
        end
    end
    return n
end

test("Build skips the racials rows; AddExtras enlists them from the data",
function()
    freshStorage()
    local data = FX.Data and FX.Data.Hunter
    assertNotNil(data, "Forte_Hunter's data did not load")
    local kit = expectedBuildCount(data)
    local n = Engine:Build("HUNTER", allKnown)
    assertEquals(kit, n)
    -- The rows ARE in the data; they are deliberately not in the Build.
    local berserking
    for _, spell in pairs(data) do
        if spell.name == "Berserking" then berserking = spell end
    end
    assertNotNil(berserking, "the Hunter data carries no Berserking row")
    assertEquals(20554, berserking.id)
    assertNil(Engine.tracked["Berserking"],
        "Build tracked a racial row -- its contract is the class kit")
    assertNil(Engine.tracked["Summon Hawk"])
    assertNil(Engine.tracked["Rapid Regeneration"])

    local added = Engine:AddExtras(allKnown)
    assertEquals(3, added, "the Hunter roster is Summon Hawk + both racials")
    assertEquals(kit + 3, trackedCount())
    local hawk = Engine.tracked["Summon Hawk"]
    assertNotNil(hawk)
    assertEquals(1293527, hawk.dataId, "the store's Rank 4, not the 70425-era id-slot")
    near(6, hawk.baseDuration)
    assertEquals("Arcane Shot", hawk.shares)
    local b = Engine.tracked["Berserking"]
    assertEquals(20554, b.dataId)
    near(180, b.baseDuration)
    -- Berserking Spell Timer fix 2026-11-14: the row now ALSO carries
    -- durationMs = 15000 (the buff, for Forte_Timer). The Engine reads
    -- `cooldownMs` only (Build/AddExtras never touch `durationMs`), so the
    -- bar a cast draws is still the 180 s cooldown, not the 15 s buff.
    assertEquals(15000, berserking.durationMs)
    local e = Engine:OnCast("Berserking", 1000)
    assertNotNil(e, "the Berserking cast drew no bar")
    near(180, e.endTime - e.start)
    Engine.entries["Berserking"] = nil
    -- The name key is the DATA's English canonical name (the Locale alias
    -- walk canonicalizes the client's names onto it -- the deDE pin rides
    -- test_locale_cooldown.lua); AddExtras never asks the client for a name
    -- (the retired `liveSpellName` path).
end)

test("the known-gate keeps un-rolled racials out of tracked", function()
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    -- A character that knows no racial (the isKnown chain answers for the
    -- class kit, the id probe is off): the gate is `isKnown(name) or
    -- IsPlayerSpell(id)`, so with both closed nothing rides in.
    local savedIPS = FX.Compat.IsPlayerSpell
    FX.Compat.IsPlayerSpell = nil
    local only = function(name)
        return name ~= "Berserking" and name ~= "Rapid Regeneration"
            and name ~= "Summon Hawk"
    end
    local added = Engine:AddExtras(only)
    assertEquals(0, added)
    assertNil(Engine.tracked["Berserking"])
    -- The id half of the gate: the NAME unknown, the spellbook known.
    FX.Compat.IsPlayerSpell = function(id) return id == 20554 end
    added = Engine:AddExtras(only)
    assertEquals(1, added, "only the id-probed Berserking rides in")
    assertNotNil(Engine.tracked["Berserking"])
    FX.Compat.IsPlayerSpell = savedIPS
end)

test("the shared 6 s pair: a cast of either starts both bars", function()
    -- MT-8: the store's fact -- Summon Hawk and Arcane Shot share category
    -- 1173 with a 6 s CategoryCooldownMs -- rides the row's `shares` link
    -- and the Engine's partner walk. On the pre-M3a sim tree the Hawk half
    -- never rides in at all (the hand table's 1293241 name read
    -- `liveSpellName` off the sim DB = nil), so the forward direction here
    -- is the fails-on-old-code half.
    freshStorage()
    Engine:Build("HUNTER", allKnown)
    Engine:AddExtras(allKnown)
    wipe(Engine.entries)
    local e = Engine:OnCast("Arcane Shot", 1000)
    assertNotNil(e, "Arcane Shot is not tracked")
    local hawk = Engine.entries["Summon Hawk"]
    assertNotNil(hawk, "the Arcane Shot cast did not start the Hawk's bar")
    near(6, hawk.duration)
    assertEquals(1006, hawk.endTime)
    -- The reverse direction: the Hawk cast starts Arcane Shot's bar.
    Engine:OnCast("Summon Hawk", 3000)
    local shot = Engine.entries["Arcane Shot"]
    assertNotNil(shot)
    near(6, shot.duration)
    -- The partner walk stops at the pair: Berserking shares nothing and
    -- rides untouched.
    assertNil(Engine.entries["Berserking"])
end)

test("Arcane Blast rides the Spell Timer, never the cooldown bar", function()
    -- §5.2: the 400573 pin row carries no cooldownMs, so Build's floor gate
    -- never enlists it and a cast of it draws no bar; the fake 8 s window
    -- was mythicsim's 18091 proc row, and the proc has its own layer. Fails
    -- on the pre-M3a data, where the Mage's class row WAS 18091/cd 8000.
    freshStorage()
    local n = Engine:Build("MAGE", allKnown)
    assertNotNil(n)
    assertNil(Engine.tracked["Arcane Blast"],
        "Arcane Blast rode the cooldown bar -- the pin is out of the data")
    assertNil(Engine:OnCast("Arcane Blast", 1000),
        "a cast of the self-buff created a bar entry")
    assertNil(Engine.entries["Arcane Blast"])
    -- The positive control: the harness is live -- a real Mage cooldown of
    -- the same data rides the bar normally.
    assertNotNil(Engine.tracked["Evocation"],
        "the Mage kit must still ride the bar (harness control)")
    local e = Engine:OnCast("Evocation", 1000)
    assertNotNil(e)
    assertTrue(e.duration >= Engine.MIN_COOLDOWN)
    wipe(Engine.entries)
    Engine:AttachStorage(originalStorage)
end)
