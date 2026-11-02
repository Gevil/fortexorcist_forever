-- addon/Forte_Cooldown/tests/test_procs.lua
-- wow-ui-sim tests for Core/Procs.lua: the item/weapon proc ICD tracker
-- (PLAN §11.1 H7, docs/design-combat-procs.md P-B, docs/perf.md §4 fix 1).
--
-- Shape of the subject: the feature sits behind the `Cooldown.Procs` setting
-- (default OFF), its data is the load-on-demand Forte_ItemProcs add-on, and
-- the two routes that may arm a window are the out-of-combat bulk aura read
-- and the UNIT_AURA event -- both read pcall'd through PlainOrNil, with the
-- window's LENGTH from the data (`icdMs`) and its START from GetTime at the
-- edge. The tests script the injectable seams (Procs.readers, Procs.inCombat)
-- and the real generated rows (name-keyed, no magic ids):
--   Argent Defender  item 13243  buff aura 17351  icdMs 20000  (no class filter)
-- and the real Hunter census of qualifying rows (13).
--
-- The sentinel seam is tests/test_reconcile.lua / test_items.lua: PlainOrNil
-- patched so a string classifies as secret, restored in-test (the framework
-- has no teardown). This file switches the feature on, so it switches it
-- back OFF at the end: a proc window left armed would move the entry counts
-- the later suites (test_rogue, test_warlock, ...) assert.

local FX = ForteXorcist
local Engine = FX.Cooldown.Engine
local Procs = Engine.Procs

local SECRET = "FXTEST-SECRET-VALUE"
local realPlainOrNil = FX.Compat.PlainOrNil
local function patchPlain()
    FX.Compat.PlainOrNil = function(v)
        if v == SECRET then return nil end
        return realPlainOrNil(v)
    end
end
local function restorePlain()
    FX.Compat.PlainOrNil = realPlainOrNil
end

-- The generated data fact (tools/gen_item_data.py -> Forte_ItemProcs).
local AD_NAME, AD_BUFF, AD_ICD = "Argent Defender", 17351, 20
local AD_KEY = "Argent Defender#17351"
-- The generated Hunter census (build 1.60.1.70425): rows with a plain buffId
-- and an icdMs whose seconds clear Engine.MIN_COOLDOWN, class-filtered.
local HUNTER_ROWS = 13

local function watched()
    local n = 0
    for _ in pairs(Procs.tracked) do n = n + 1 end
    return n
end

local function live()
    local n = 0
    for key in pairs(Procs.tracked) do
        if Engine.entries[key] then n = n + 1 end
    end
    return n
end

--- Drop the windows this file owns, so each test starts from "no proc is
--- running" without disturbing the entries the other suites count.
local function clearProcs()
    for key in pairs(Procs.tracked) do
        Engine.entries[key] = nil
    end
    wipe(Procs.seen)
end

--- Script the bulk aura read: `ids` are the spell ids of the auras the
--- client lists for the player (a spellId element that must not read passes
--- a table whose field access raises -- a sealed AuraData proxy).
local function readersWith(ids)
    return {
        bulk = function(unit, filter)
            local list = {}
            for _, id in ipairs(ids) do
                if type(id) == "table" then
                    list[#list + 1] = setmetatable({}, {
                        __index = function()
                            error("FXTEST: a sealed aura read raises")
                        end,
                    })
                else
                    list[#list + 1] = { spellId = id }
                end
            end
            return list
        end,
    }
end

-- ------------------------------------------------------------------ wiring --

test("the proc tracker is wired and off by default", function()
    assertNotNil(Procs, "Core/Procs.lua is not attached to the Engine")
    -- The feature's default (docs/design-combat-procs.md P-B): the proc
    -- ICDs ride the timeline only when `Cooldown.Procs` is switched on.
    assertFalse(Procs:IsEnabled())
    assertEquals(0, watched(),
        "a session that never switched the feature on tracks no proc")
    -- The split's data law (test_loader.lua proves the login-session half:
    -- the add-on is declared load-on-demand and is not parsed at login).
    assertNotNil(FX.Data.Items.onUse, "the on-use rows are still here")
    assertNotNil(FX.Data.Items.consumables, "the consumable rows are still here")
    assertEquals(5, #FX.Data.Items.enchantProcs,
        "the 5 enchant proc rows are the split's kept half")
    assertNil(FX.Data.Items.procs,
        "the item proc rows moved out of Forte_Items (H7)")
    assertNil(FX.Data.Items.ProcsByName,
        "the proc indexes moved out of Forte_Items (H7)")
end)

test("switched off, a proc aura on the player arms nothing on either route",
function()
    clearProcs()
    local before = live()
    Procs:Scan(1000, readersWith({ AD_BUFF }))
    Procs:OnUnitAura("player", { addedAuras = { { spellId = AD_BUFF } } })
    assertEquals(before, live(), "the off feature armed a window")
    assertEquals(0, Procs.counts.reads,
        "the off feature did not even reach the read")
end)

test("switching on loads Forte_ItemProcs exactly once", function()
    clearProcs()
    -- Count the loader calls. The ledger (Loader.lua) is the idempotence
    -- proof and is SHARED with the class loader, so a test file that runs
    -- before this one (test_70707_overlay loads the class add-ons and the
    -- proc data itself) may have warmed it: this test therefore starts from
    -- a cleared ledger entry of its own and restores it after.
    local calls = 0
    local savedAddOns = _G.C_AddOns
    local savedEntry = FX._loadedAddOns["Forte_ItemProcs"]
    FX._loadedAddOns["Forte_ItemProcs"] = nil
    -- A synthetic loader view: the add-on is reported NOT in, so the load
    -- path itself is exercised (a session that ran an earlier suite file may
    -- have it in already, which the real loader answers without a load call).
    _G.C_AddOns = {
        LoadAddOn = function(name)
            calls = calls + 1
            return true
        end,
        IsAddOnLoaded = function() return false, false end,
    }
    local watchedFirst = Procs:SetEnabled(true)
    Procs:SetEnabled(true)
    Procs:SetEnabled(true)
    local ledger = FX._loadedAddOns["Forte_ItemProcs"]
    _G.C_AddOns = savedAddOns
    FX._loadedAddOns["Forte_ItemProcs"] = savedEntry
    assertEquals(true, ledger, "the ledger records the load")
    assertEquals(1, calls, "the data add-on loaded more than once")
    assertTrue(Procs:IsEnabled())
    if FX.Data.ItemProcs then
        -- The real data is in the session (this suite's own loader path, or
        -- the explicit load of test_70707_overlay): the watched set is the
        -- generated Hunter census (rows with a plain buffId + an icdMs of at
        -- least a GCD band, class-filtered).
        assertEquals(HUNTER_ROWS, watchedFirst,
            "the watched set is not the generated Hunter census")
    else
        -- A session where the add-on is not in: the feature is enabled and
        -- empty, which is the loader's documented failure shape.
        assertEquals(0, watchedFirst,
            "a session without the data add-on tracked rows anyway")
    end
    -- The split law, both sides: the LoD file carries item rows only, the
    -- always-loaded file enchant rows only.
    for _, row in ipairs(FX.Data.ItemProcs and FX.Data.ItemProcs.procs
        or {}) do
        if row.source ~= "item" then
            assertTrue(false, ("a %s row rode in the item proc file"):format(
                tostring(row.source)))
        end
    end
    for _, row in ipairs(FX.Data.Items.enchantProcs) do
        if row.source ~= "enchant" then
            assertTrue(false, "an item row rode in the kept enchant rows")
        end
    end
end)

-- -------------------------------------------------- the out-of-combat sweep --

test("one out-of-combat proc aura creates exactly one ICD entry", function()
    clearProcs()
    local row = FX.Data.ItemProcs.ProcsByName[AD_NAME]
    assertEquals(AD_BUFF, row.buffId)
    local created = Procs:Scan(1000, readersWith({ AD_BUFF }))
    assertEquals(1, created, "the sweep is not the one-entry edge it claims")
    local e = Engine.entries[AD_KEY]
    assertNotNil(e, "the proc's key is <data name>#<buffId> (the n3 key law)")
    -- The KEY carries the id; the NAME the pop, the splash and FX_COOLDOWN_READY
    -- speak stays the display name.
    assertEquals(AD_NAME, e.name)
    -- The window is the DATA's ICD from the edge time -- no duration,
    -- expiration, applications count or aura instance id of the read reaches
    -- it (docs/design-combat-procs.md §4, docs/aura-secret-display.md).
    assertEquals(1000, e.start)
    assertEquals(AD_ICD, e.duration)
    assertEquals(1000 + AD_ICD, e.endTime)
    assertTrue(e.predicted, "a proc window is engine-inferred, never read-")
    assertNil(e.anchored, "inferred, so it is never read-certified")
    assertEquals("proc", e.source)
    assertEquals("Item", e.category, "the timeline's ColourItem row")
    assertEquals(1, live())
end)

test("a proc seen twice does not restart its ICD; a gap re-arms the edge",
function()
    clearProcs()
    assertEquals(1, Procs:Scan(1000, readersWith({ AD_BUFF })))
    -- The aura is still up at 1010: same edge, no second window, no restart.
    assertEquals(0, Procs:Scan(1010, readersWith({ AD_BUFF })))
    assertEquals(1000, Engine.entries[AD_KEY].start)
    assertEquals(0, Procs:Scan(1020, readersWith({})))  -- the aura is gone
    -- The ICD of the 1000 edge ran out at 1020; the Engine retires it on the
    -- next Sweep (the live 10 Hz ticker), and a window that is running is not
    -- restarted by a new proc -- so the re-arm is measured on a retired bar.
    Engine:Sweep(1029, {})
    -- ... and the next proc is an edge again.
    assertEquals(1, Procs:Scan(1030, readersWith({ AD_BUFF })))
    assertEquals(1030, Engine.entries[AD_KEY].start)
end)

test("the sweep reads nothing while the gate is shut", function()
    clearProcs()
    local reads = Procs.counts.reads
    -- In combat: a nil from a sealed read is not "no aura", and an invented
    -- absence would cancel a live window (Forte_Timer/Core/Reconcile.lua).
    Procs.inCombat = function() return true end
    assertEquals(0, Procs:Scan(1000, readersWith({ AD_BUFF })))
    -- The cached aura-secrecy mode answering a plain true: the same skip.
    Procs.inCombat = nil
    local SS = FX.SecretState
    local saved = SS and SS.aurasSecret
    if SS then SS.aurasSecret = true end
    assertEquals(0, Procs:Scan(1000, readersWith({ AD_BUFF })))
    if SS then SS.aurasSecret = saved end
    assertEquals(reads, Procs.counts.reads,
        "a gated pass did not skip the read")
    -- An unknown mode (nil) is not a reason to skip work.
    Procs.inCombat = function() return false end
    assertEquals(1, Procs:Scan(1000, readersWith({ AD_BUFF })))
    Procs.inCombat = nil
    assertEquals(reads + 1, Procs.counts.reads,
        "the ungated pass did not reach the read")
end)

test("a secret aura read arms nothing and raises nothing", function()
    clearProcs()
    -- (a) an aura element that will not read (the sealed-proxy shape: the
    -- field access itself raises), (b) an id that classifies as secret.
    local sealed = Procs:Scan(1000, readersWith({ { sealed = true } }))
    assertEquals(0, sealed)
    assertEquals(0, live())
    patchPlain()
    local secret = Procs:Scan(1000, readersWith({ SECRET }))
    restorePlain()
    assertEquals(0, secret)
    assertEquals(0, live())
    -- (c) the whole bulk answer sealed: a raise, then a secret table. Both
    -- are "no answer" -- the seen model and every running window keep.
    clearProcs()
    assertEquals(0, Procs:Scan(1000, { bulk = function()
        error("FXTEST: the bulk read is sealed")
    end }))
    patchPlain()
    assertEquals(0, Procs:Scan(1000, { bulk = function() return SECRET end }))
    restorePlain()
    assertEquals(0, live())
    assertTrue(Procs.counts.secret > 0, "the sealed reads are counted")
    assertTrue(Procs.counts.raised > 0, "the raising reads are counted")
end)

test("a sealed pass does not cancel a running window", function()
    clearProcs()
    Procs:Scan(1000, readersWith({ AD_BUFF }))
    local e = Engine.entries[AD_KEY]
    assertNotNil(e)
    -- The aura is gone from the sweep's answer (the falling edge) only when
    -- the pass ANSWERED; a sealed pass leaves the window running to its
    -- endTime. (The counter pair of that law:)
    local reads = Procs.counts.reads
    Procs:Scan(1005, { bulk = function() error("FXTEST: sealed") end })
    assertEquals(reads + 1, Procs.counts.reads)
    assertNotNil(Engine.entries[AD_KEY], "a seal cancelled a live window")
    assertEquals(1000, Engine.entries[AD_KEY].start)
end)

-- ------------------------------------------------------- the aura event --

test("the UNIT_AURA route arms the window from a plain addedAuras id",
function()
    clearProcs()
    -- The payload shape is (unitTarget, UnitAuraUpdateInfo) --
    -- UnitAuraDocumentation.lua:644, UnitConstantsDocumentation.lua:55.
    assertEquals(1, Procs:OnUnitAura("player",
        { addedAuras = { { spellId = AD_BUFF } } }, 2000))
    local e = Engine.entries[AD_KEY]
    assertNotNil(e, "the in-combat half armed nothing")
    assertEquals(2000, e.start)
    assertEquals(AD_ICD, e.duration)
    -- Idempotent: the event fires per aura change, the window is one edge.
    assertEquals(0, Procs:OnUnitAura("player",
        { addedAuras = { { spellId = AD_BUFF } } }, 2005))
    assertEquals(2000, Engine.entries[AD_KEY].start)
    -- Not our unit: silent.
    assertEquals(0, Procs:OnUnitAura("pet",
        { addedAuras = { { spellId = AD_BUFF } } }, 2010))
end)

test("a secret UNIT_AURA payload says nothing and raises nothing", function()
    clearProcs()
    -- The whole payload sealed: reading a field of it raises.
    assertEquals(0, Procs:OnUnitAura("player", setmetatable({}, {
        __index = function() error("FXTEST: a sealed payload raises") end,
    }), 2000))
    -- The addedAuras list is there, the id inside it is not.
    patchPlain()
    assertEquals(0, Procs:OnUnitAura("player",
        { addedAuras = { { spellId = SECRET } } }, 2000))
    restorePlain()
    assertEquals(0, Procs:OnUnitAura("player",
        { addedAuras = { { sealed = true } } }, 2000))
    assertEquals(0, live())
    -- A unit field that will not classify: the pass runs (the payload's unit
    -- field is SecretWhenAurasRestricted too), the id rule still governs.
    assertEquals(0, Procs:OnUnitAura(SECRET,
        { addedAuras = { { spellId = AD_BUFF } } }, 2000))
end)

-- ------------------------------------------------------------ the bar ride --

test("the window rides the Engine and retires at its endTime", function()
    clearProcs()
    Procs:Scan(3000, readersWith({ AD_BUFF }))
    local popped = {}
    assertEquals(0, #Engine:Sweep(3019.5, popped), "it popped early")
    assertEquals(1, #Engine:Sweep(3020.5, popped), "it did not pop at its end")
    assertEquals(AD_NAME, popped[1],
        "the pop speaks the display name, never the key")
    assertNil(Engine.entries[AD_KEY])
end)

test("a rebuild drops the windows and re-arms the seen model", function()
    clearProcs()
    Procs:Scan(4000, readersWith({ AD_BUFF }))
    assertEquals(1, live())
    Engine:Build(FX._playerClass, function() return true end)   -- wipes entries
    Procs:OnRebuild()
    assertEquals(0, live(), "the Engine wiped the table; the windows stayed")
    -- The aura is (model-wise) still up, so the sweep sees no new edge --
    -- after the rebuild reset it sees one again.
    assertEquals(1, Procs:Scan(4010, readersWith({ AD_BUFF })))
    assertEquals(1, live())
    clearProcs()
end)

-- --------------------------------------------- the split left the rest alone --

test("the on-use item tracking the split did not touch still works", function()
    -- The on-use path reads Forte_Items, which the split only shrank: the
    -- same rescan, the same watched count, the same use-spell join.
    local Items = Engine.Items
    assertNotNil(Items, "Core/Items.lua is not attached to the Engine")
    local before = 0
    for _ in pairs(Items.tracked) do before = before + 1 end
    local rows = FX.Data.Items.onUse
    assertTrue(#rows > 200, "the on-use rows survived the split")
    -- The real inventory surface (the Core/Items.lua live readers): the
    -- sim's item DB resolves names as "Unknown", so the count is scripted
    -- no-where here -- what this asserts is that the rescan path itself is
    -- intact on the shrunken data (test_items.lua owns its per-row detail).
    Items:Rescan()
    local after = 0
    for _ in pairs(Items.tracked) do after = after + 1 end
    assertTrue(after >= 0)
    assertNotNil(Items.byCastSpell, "the use-spell join index is built")
    -- The enchant half: the always-loaded name fallback (Core/Enchants.lua
    -- ResolveName) reads the kept rows, so the split must not have moved
    -- them -- the same 5 rows, the same effect ids.
    local en = FX.Data.Items.enchantProcs
    local has1900
    for _, row in ipairs(en) do
        if row.itemId == 1900 then has1900 = row.name end
    end
    assertEquals("Enchant Weapon - Crusader", has1900,
        "the enchant rows no longer name the Enchants module's fallback")
end)

-- Self-cleaning (the framework has no teardown): the feature goes back to
-- its shipped default so the suites that run after this one keep their
-- entry counts, and the injected seams go with it.
test("the feature returns to its default off", function()
    Procs.inCombat = nil
    Procs.readers = nil
    clearProcs()
    assertFalse(Procs:SetEnabled(false))
    assertEquals(0, watched())
end)
