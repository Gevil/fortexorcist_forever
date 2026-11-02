-- addon/Forte_Cooldown/tests/test_70707_overlay.lua
-- DataRefresh (wave 2a, D3): the 70707 spell-store overlay is the pinning law
-- for every generated data file. The store (wowsims/forever, MIT, commit
-- stamped in each generated header) is the live build's capture of name,
-- family, rank, cooldown, category and ICD; the generators
-- (tools/gen_spell_data.py --overrides tools/overrides_70707.json,
-- tools/gen_item_data.py) read mythicsim 70425 and override with it, drop
-- rows the live build removed, exclude class-book ranks from the rank
-- ladder, and source rows for the names the 70425 pull lacks (the Warlock
-- pet kit).
--
-- Every pin here is a row whose value the overlay CHANGED (docs/research/
-- data-diff-70707.md §2) -- each one fails on the pre-overlay data. This
-- suite lives in Forte_Cooldown because the audited artefact is the
-- repo-level generated data set (the test_tracked_set.lua law), not one
-- class's module.

local FX = ForteXorcist

FX.LoadClassAddOn("DRUID")
FX.LoadClassAddOn("HUNTER")
FX.LoadClassAddOn("MAGE")
FX.LoadClassAddOn("WARRIOR")
FX.LoadClassAddOn("PALADIN")
FX.LoadClassAddOn("PRIEST")
FX.LoadClassAddOn("ROGUE")
FX.LoadClassAddOn("SHAMAN")
FX.LoadClassAddOn("WARLOCK")

local Registry = FX.Timer and FX.Timer.Registry

test("the overlaid classes' data is in the session", function()
    for _, name in ipairs({ "Druid", "Warrior", "Paladin", "Warlock" }) do
        assertNotNil(FX.Data and FX.Data[name], ("Forte_%s's data did not load"):format(name))
        assertNotNil(FX.Data and FX.Data[name .. "ByName"],
            ("Forte_%s's name index did not load"):format(name))
    end
    assertNotNil(FX.Data and FX.Data.Items, "Forte_Items's data did not load")
    assertNotNil(FX.Data.Items.ProcsByName, "Forte_Items's proc index did not load")
    assertNotNil(Registry, "Forte_Timer's registry is not in the session")
end)

test("the store's corrected cooldowns land: Shifting Power 8 s, Charge Rank VI",
function()
    -- data-diff §2: Shifting Power 1322605 Cooldowns 16000 -> 8000 (the store
    -- row rides family 3). Pre-overlay the data said 16000.
    local druid, druidByName = FX.Data.Druid, FX.Data.DruidByName
    local shifting = druid[druidByName["Shifting Power"]]
    assertNotNil(shifting)
    assertEquals(1322605, shifting.id)
    assertEquals(8000, shifting.cooldownMs)
    -- Charge: the pick moved off the book-rank ladder to Rank VI 27685
    -- (data-diff §2.4 "Charge 1240289 -> 27685"), carrying the store's 25 s
    -- charge-stun cooldown + shared category 44. Pre-overlay: 1240289,
    -- Rank III, no cooldown at all.
    local warrior, warriorByName = FX.Data.Warrior, FX.Data.WarriorByName
    local charge = warrior[warriorByName["Charge"]]
    assertNotNil(charge)
    assertEquals(27685, charge.id)
    assertEquals("Rank 6", charge.rank)
    assertEquals(25000, charge.cooldownMs)
    assertEquals(44, charge.cooldownCategory)
    -- Cower: Rank VI 16697 (data-diff §2.4), 5 s + category 82.
    local cower = druid[druidByName["Cower"]]
    assertNotNil(cower)
    assertEquals(16697, cower.id)
    assertEquals(5000, cower.cooldownMs)
    assertEquals(82, cower.cooldownCategory)
    -- Wild Growth: the store's Levels capture adds the 3 s cast (pre-overlay
    -- the row carried no cast at all).
    local wild = druid[druidByName["Wild Growth"]]
    assertNotNil(wild)
    assertEquals(3000, wild.castMs)
end)

test("rows the live build removed are gone, Blessing of Light re-lands bare",
function()
    -- data-diff §2.2: Salvation 1038, Mass Salvation 25895, Greater Blessing
    -- of Light 25890 and Revoke 1325499 have no Names row on 70707. Pre-
    -- overlay all four carried full values.
    local paladin, paladinByName = FX.Data.Paladin, FX.Data.PaladinByName
    for _, name in ipairs({ "Salvation", "Mass Salvation", "Greater Blessing of Light",
                            "Revoke" }) do
        assertNil(paladinByName[name], name .. " survived into the 70707 data")
    end
    -- Blessing of Light: the ranked trio 19977/19978/19979 is gone; 26650
    -- exists in Names with no value row, so the row is name-only (a live
    -- probe is the launch task; docs/research/forever-data-gaps.md G5).
    local bol = paladin[paladinByName["Blessing of Light"]]
    assertNotNil(bol)
    assertEquals(26650, bol.id)
    assertNil(bol.durationMs)
    -- Swift Judgement: the store's Misc row carries DurationMs 0; the
    -- mythicsim row's -1 (a sentinel the generators never emit) is gone.
    local swift = paladin[paladinByName["Swift Judgement"]]
    assertNotNil(swift)
    assertNil(swift.durationMs)
    assertEquals(60000, swift.cooldownMs)
end)

test("the rank ladder lands on trainer ranks, never class-book ranks", function()
    -- wowsims/forever sim/core/spelldata/book_ranks.go: these ids are taught
    -- ONLY by the class books; on the live ranks the trainer line is what a
    -- max-level character casts. data-diff §2.4 lists each pick moving off
    -- the book id. The exclusion lives in gen_spell_data.py + the overrides
    -- file's bookRanks list.
    local paladinByName = FX.Data.PaladinByName
    assertEquals(19838, paladinByName["Blessing of Might"])   -- not 25291 (Rank VII book)
    assertEquals(19854, paladinByName["Blessing of Wisdom"])  -- not 25290 (Rank VI book)
    assertEquals(25782, paladinByName["Greater Blessing of Might"])   -- not 25916
    assertEquals(25894, paladinByName["Greater Blessing of Wisdom"])  -- not 25918
    assertEquals(9841, FX.Data.DruidByName["Rejuvenation"])   -- not 25299 (Rank XI book)
    assertEquals(14322, FX.Data.HunterByName["Aspect of the Hawk"]) -- not 25296 (VII book)
    assertEquals(11668, FX.Data.WarlockByName["Immolate"])     -- not 25309 (Rank VIII book)
    assertEquals(10448, FX.Data.ShamanByName["Flame Shock"])    -- not 29228 (Rank VI book)
    assertEquals(11303, FX.Data.RogueByName["Feint"])           -- not 25302 (Rank IX book)
    assertEquals(11601, FX.Data.WarriorByName["Revenge"])       -- not 25288 (Rank VI book)
    assertEquals(11551, FX.Data.WarriorByName["Battle Shout"])  -- not 25289 (Rank VII book)
end)

test("the Warlock pet kit is live data sourced from the store", function()
    -- docs/research/forever-data-gaps.md G6: the 70425 pull names none of
    -- the Succubus/Felhunter/Voidwalker kit; the 70707 store does (family 5).
    -- Pre-overlay the generated file had no pet rows at all.
    local warlock, warlockByName = FX.Data.Warlock, FX.Data.WarlockByName
    local seduction = warlock[warlockByName["Seduction"]]
    assertNotNil(seduction, "Seduction is not in the Warlock data")
    assertEquals(6358, seduction.id)
    assertEquals(15000, seduction.durationMs)
    assertEquals("Crowds", Registry._kindFor("Seduction"))
    -- Spell Lock 19647: 8 s silence on a 30 s cd (the store's Cooldowns row).
    local lock = warlock[warlockByName["Spell Lock"]]
    assertNotNil(lock)
    assertEquals(8000, lock.durationMs)
    assertEquals(30000, lock.cooldownMs)
    -- Mesmerize (the Succubus CC alias) exists by name only: the store's
    -- Names table has the id, the value tables do not. The row is inert
    -- (no duration), the Forte_Messages fade rows stay dark (LocaleB's call).
    local mesmerize = warlock[warlockByName["Mesmerize"]]
    assertNotNil(mesmerize)
    assertEquals(24594, mesmerize.id)
    assertNil(mesmerize.durationMs)
    -- Enslave Demon (2012) is not on the live build (the client's 1098 name
    -- is Subjugate Demon): the pet kit must not smuggle it in.
    assertNil(warlockByName["Enslave Demon"])
    -- Seduction rides the Crowds tracked set now (15 s CC): the registry
    -- Build is the game seam (the test_tracked_set law).
    if Registry:Build("WARLOCK") then
        local entry = Registry.entries["Seduction"]
        assertNotNil(entry, "Seduction is not in the Warlock tracked set")
        assertEquals(15, entry.duration)
        Registry:AttachStorage(FX.db and FX.db.timer and FX.db.timer.learned or {})
        Registry:Build(FX._playerClass)
    end
end)

test("spell ICDs ride their own capture, never a borrowed cast row", function()
    -- The strict ICD join (Main's 2026-11-02 D3 review, gen_spell_data.py):
    -- icdMs rides (a) the row's own captured AuraOptions ICDMs, or (b) a
    -- same-family sibling rank / an uncoded PROC pair -- and never onto a
    -- row that is an active cast with a cooldown of its own.
    local paladin, paladinByName = FX.Data.Paladin, FX.Data.PaladinByName
    -- (a) Divine Protection 5573 is the paladin's 300 s active cast: the
    -- 60 s ICD rides uncoded 27778 (a separate proc-carrying aura,
    -- ProcFlags 139944) -- a cross-family borrow onto an active cast was
    -- exactly the pre-review bug.
    local dp = paladin[paladinByName["Divine Protection"]]
    assertNotNil(dp)
    assertEquals(5573, dp.id)
    assertNil(dp.icdMs)
    -- (a) Rogue Rebuke 425609 is the family-8 15 s active interrupt; the
    -- 60 s ICD is paladin family-10 proc row 1302716's own capture -- the
    -- cross-family borrow is law, not data.
    local rb = FX.Data.Rogue[FX.Data.RogueByName["Rebuke"]]
    assertNotNil(rb)
    assertEquals(425609, rb.id)
    assertNil(rb.icdMs)
    -- Paladin Rebuke rides 1302716: the uncoded proc row, ICD from ITS OWN
    -- id (ProcChance 7, ProcFlags 131072, ICDMs 60000 in the store) -- the
    -- pick's own capture, kept on review.
    local pr = paladin[paladinByName["Rebuke"]]
    assertNotNil(pr)
    assertEquals(1302716, pr.id)
    assertEquals(60000, pr.icdMs)
    -- Own-capture keep-pins (branch (a)):
    local soc = paladin[paladinByName["Seal of Command"]]
    assertNotNil(soc)
    assertEquals(1000, soc.icdMs)
    local sg = FX.Data.Priest[FX.Data.PriestByName["Shadowguard"]]
    assertNotNil(sg)
    assertEquals(3500, sg.icdMs)
    -- Same-family sibling keep-pins (branch (b)): Windfury Weapon's pick
    -- 16361 (family 11) rides Rank 1 439431's ICDMs; Taste for Blood 426969
    -- (family 4) rides 426953's 5800.
    local wf = FX.Data.Shaman[FX.Data.ShamanByName["Windfury Weapon"]]
    assertNotNil(wf)
    assertEquals(1500, wf.icdMs)
    local tfb = FX.Data.Warrior[FX.Data.WarriorByName["Taste for Blood"]]
    assertNotNil(tfb)
    assertEquals(5800, tfb.icdMs)
end)

test("the D3 watch-list picks ride family-correct rows", function()
    -- Main's review census (store families as of commit 164d1cf6):
    -- Dispel Magic: the 16908 pick was an index shell (family-less, no cast
    -- data, name + level only) over-shadowing the family-6 cast line; the
    -- index-shell law re-lands 988 (Rank 2, the priest cast row).
    assertEquals(988, FX.Data.PriestByName["Dispel Magic"])
    -- Summon Felhunter: 8176 is family-less with no cast time and a 10 min
    -- duration; 691 is the family-5 cast (10 s, permanent) -- the cast-time
    -- tiebreak re-lands 691.
    assertEquals(691, FX.Data.WarlockByName["Summon Felhunter"])
    -- Cripple 89: family-less in the store (no ClassOptions row) but the
    -- line's ONLY castable capture (Rank 1, 30 s cd, range 30); 18381 is a
    -- name-only row on 70707. Kept.
    assertEquals(89, FX.Data.WarriorByName["Cripple"])
    -- Shield Mastery: 426981 (family-less, 3 s block-proc effect) over the
    -- old 408525 (family 11 passive proc aura, MaxStack 7): a passive line
    -- both ways, no castable row was lost. Kept.
    assertEquals(426981, FX.Data.ShamanByName["Shield Mastery"])
    -- Flametongue Weapon: 16342 (family-less Rank 6 cast, gcd) over the old
    -- 436519 (family-11 proc aura): the move is TOWARDS the castable row.
    -- Kept.
    assertEquals(16342, FX.Data.ShamanByName["Flametongue Weapon"])
    -- Paladin Rebuke: both rows passive on 70707 (425616 name-level,
    -- 1302716 the proc capture) -- review ruling: keep 1302716 with its
    -- own ICD (pinned in the ICD test above).
    assertEquals(1302716, FX.Data.PaladinByName["Rebuke"])
end)

test("item proc rows carry their ICDs", function()
    -- docs/research/forever-data-gaps.md G2: 51 proc rows ride
    -- proc.icd_ms; the store confirms 9 through the proc aura's
    -- AuraOptions.ICDMs. Argent Defender is one of the confirmed (20 s).
    local items = FX.Data.Items
    local ad = items.ProcsByName["Argent Defender"]
    assertNotNil(ad, "Argent Defender lost its proc row")
    assertEquals(20000, ad.icdMs)
    local withIcd = 0
    for _, row in ipairs(items.procs) do
        if row.icdMs then withIcd = withIcd + 1 end
    end
    assertTrue(withIcd >= 51,
        ("expected the 51 icdMs proc rows, found %d"):format(withIcd))
end)
