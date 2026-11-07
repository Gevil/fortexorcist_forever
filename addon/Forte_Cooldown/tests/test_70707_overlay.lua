-- addon/Forte_Cooldown/tests/test_70707_overlay.lua
-- The live spell-store overlay is the pinning law for every generated data
-- file. The store (wowsims/forever, MIT, commit + build stamped in each
-- generated header and POLICED generically by scripts/gate.py's
-- data_provenance, wave M3a) is the live build's capture of name, family,
-- rank, cooldown, category, ICD and the feed shapes; the generators
-- (tools/gen_spell_data.py, live overlay = its `LIVE_OVERLAY` pointer --
-- tools/overrides_70790.json since the wave M5 refresh,
-- docs/research/data-diff-live-2026-11-07.md) read mythicsim 70425 and
-- override with it, drop rows the live build removed, exclude class-book
-- ranks from the rank ladder, and source rows for the names the 70425 pull
-- lacks (the Warlock pet kit, the racials shells).
--
-- The FILE NAME carries the 70707 origin; the pins are the standing law of
-- the data set. Every pin here is a row whose value an overlay CHANGED
-- (docs/research/data-diff-70707.md §2, and the wave M3a block at the end for
-- the 1.60.1.70790 moves) -- each one fails on the pre-overlay data. This
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
-- The proc data split (H7): the proc rows + ProcsByName live in the
-- load-on-demand Forte_ItemProcs add-on, so the suite that audits them has to
-- ask for them through the real loader -- `run-tests` does not run a
-- load-on-demand add-on's files.
FX.LoadAddOnOnDemand("Forte_ItemProcs")

local Registry = FX.Timer and FX.Timer.Registry

test("the overlaid classes' data is in the session", function()
    for _, name in ipairs({ "Druid", "Warrior", "Paladin", "Warlock" }) do
        assertNotNil(FX.Data and FX.Data[name], ("Forte_%s's data did not load"):format(name))
        assertNotNil(FX.Data and FX.Data[name .. "ByName"],
            ("Forte_%s's name index did not load"):format(name))
    end
    assertNotNil(FX.Data and FX.Data.Items, "Forte_Items's data did not load")
    assertNotNil(FX.Data and FX.Data.ItemProcs,
        "Forte_ItemProcs's proc data did not load")
    assertNotNil(FX.Data.ItemProcs.ProcsByName, "the proc name index did not load")
    assertNotNil(FX.Data.Items.enchantProcs, "the enchant proc rows did not load")
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

test("rows the live build removed are gone, bare and value-less alike",
function()
    -- data-diff §2.2: Salvation 1038, Mass Salvation 25895, Greater Blessing
    -- of Light 25890 and Revoke 1325499 have no Names row on 70707. Pre-
    -- overlay all four carried full values.
    local paladin, paladinByName = FX.Data.Paladin, FX.Data.PaladinByName
    for _, name in ipairs({ "Salvation", "Mass Salvation", "Greater Blessing of Light",
                            "Revoke" }) do
        assertNil(paladinByName[name], name .. " survived into the 70707 data")
    end
    -- Blessing of Light: wave I-2b pruned it from the spell lists -- the
    -- post-9 dev notes REMOVE the blessing (docs/research/
    -- forever-dev-notes-2026-11-03.md §1 Paladin row; docs/class-port.md
    -- 6.2 item 5). Its 70707 carrier 26650 was a name-only shell (data-gaps
    -- G5), so nothing of value leaves the data; the name must not return.
    assertNil(paladinByName["Blessing of Light"],
        "Blessing of Light was removed on the post-9 notes -- it is out of "
        .. "the spell lists")
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
    -- The split: 49 ride in Forte_ItemProcs, 2 in Forte_Items.enchantProcs.
    local procs = FX.Data.ItemProcs
    assertNotNil(procs, "Forte_ItemProcs's data is not in the session")
    local ad = procs.ProcsByName["Argent Defender"]
    assertNotNil(ad, "Argent Defender lost its proc row")
    assertEquals(20000, ad.icdMs)
    local withIcd = 0
    for _, row in ipairs(procs.procs) do
        if row.icdMs then withIcd = withIcd + 1 end
    end
    for _, row in ipairs(FX.Data.Items.enchantProcs or {}) do
        if row.icdMs then withIcd = withIcd + 1 end
    end
    assertTrue(withIcd >= 51,
        ("expected the 51 icdMs proc rows, found %d"):format(withIcd))
end)

-- Wave M3a (2026-11-07) -- the 1.60.1.70790 moves this census newly pins.
-- Every assertion here fails on the pre-M3a generated data (the data as of
-- commit d490e2e), docs/research/data-diff-live-2026-11-07.md §3-§5.
test("wave M3a: the 70790 rank re-picks land with their values", function()
    -- §4 the rogue pair, pinned no-window rows since I-3e, are value rows
    -- now: Shank 1329549 (Rank 2) 10 s cooldown / 1 s GCD, Death Mark
    -- 1325758 (Rank 4) the 10 s cooldown, the 6 s mark window, the 6 s tick
    -- capture. On the pre-M3a data the picks were the value-less shells
    -- 15248/1316709 and BOTH names sat in H7_UNTRACKED.
    local rogue, rogueByName = FX.Data.Rogue, FX.Data.RogueByName
    local shank = rogue[rogueByName["Shank"]]
    assertNotNil(shank)
    assertEquals(1329549, shank.id)
    assertEquals("Rank 2", shank.rank)
    assertEquals(10000, shank.cooldownMs)
    assertEquals(1000, shank.gcdMs)
    local mark = rogue[rogueByName["Death Mark"]]
    assertNotNil(mark)
    assertEquals(1325758, mark.id)
    assertEquals("Rank 4", mark.rank)
    assertEquals(10000, mark.cooldownMs)
    assertEquals(6000, mark.durationMs)
    assertEquals(6, mark.tickEvery)
    -- §3 Holy Shield 20928 -> 1239570 (Rank 4). THE flag test: the store's
    -- 1239570 capture carries no Target, so the `noTarget` flag (the base
    -- 20928 row's caster `[1, 0]` shape) rides the generator's rank-sibling
    -- feed inheritance -- on the data before the sibling law the re-pick
    -- DROPPED the flag (the §3 "loses noTarget -- check" hazard), and the
    -- Timer's one-row-per-caster law broke with it.
    local paladin, paladinByName = FX.Data.Paladin, FX.Data.PaladinByName
    local hs = paladin[paladinByName["Holy Shield"]]
    assertNotNil(hs)
    assertEquals(1239570, hs.id)
    assertEquals("Rank 4", hs.rank)
    assertEquals(true, hs.noTarget)
    assertEquals(10000, hs.durationMs)
    assertEquals(10000, hs.cooldownMs)
end)

test("wave M3a: Arcane Blast is the 18 s self-buff, the proc rides the proc layer",
function()
    -- §5.2: the pin moves the Mage row from mythicsim's weapon-proc row
    -- 18091 (an 8 s cooldown -- the fake cooldown bar) to the player's own
    -- 400573 self-buff: 18 s window, 4 stacks, caster-targeted, NO cooldown
    -- at all. On the pre-M3a data the name keyed 18091 with cooldownMs
    -- 8000 and no window.
    local mage, mageByName = FX.Data.Mage, FX.Data.MageByName
    assertEquals(400573, mageByName["Arcane Blast"])
    local ab = mage[400573]
    assertNotNil(ab)
    assertEquals(18000, ab.durationMs)
    assertEquals(4, ab.maxStack)
    assertEquals(true, ab.noTarget)
    assertNil(ab.cooldownMs)
    assertNil(mage[18091], "the 18091 proc row has no business in the class data")
    -- The proc has NOT vanished -- it rides the layer that names proc auras
    -- by `<name> (<id>)`: the Archeus row (Forte_ItemProcs/Data/Procs.lua).
    assertNotNil(FX.Data.ItemProcs.ProcsByBuffName["Arcane Blast (18091)"],
        "the Arcane Blast weapon proc left the proc layer with the pin")
end)

test("wave M3a: the racials are generated rows (racial = true) on the right rosters",
function()
    -- review-10 M2/m4: the hand-kept Engine.RACIALS ids are data rows now.
    -- Berserking (Orc/Troll) rides eight class files, Rapid Regeneration
    -- (Dwarf) rides seven; the druid carries no Dwarf racial and the
    -- paladin no Orc/Troll one -- the rosters are the game's, the rows are
    -- the store's shells + the owner's measured 180 s (the dev-notes file).
    -- On the pre-M3a data NO class file carried these rows at all.
    local ALL = { "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue",
                  "Shaman", "Warlock", "Warrior" }
    local berserking = { Druid = true, Hunter = true, Mage = true, Priest = true,
                         Rogue = true, Shaman = true, Warlock = true,
                         Warrior = true }
    local rapid = { Hunter = true, Mage = true, Paladin = true, Priest = true,
                    Rogue = true, Shaman = true, Warlock = true, Warrior = true }
    for _, cls in ipairs(ALL) do
        local data, byName = FX.Data[cls], FX.Data[cls .. "ByName"]
        local b = byName["Berserking"]
        if berserking[cls] then
            assertNotNil(b, cls .. " carries no Berserking row")
            assertEquals(20554, b)
            local row = data[b]
            assertEquals(true, row.racial)
            assertEquals(180000, row.cooldownMs)
            assertNil(row.durationMs)
        else
            assertNil(b, cls .. " cannot roll Berserking (Orc/Troll racial)")
        end
        local r = byName["Rapid Regeneration"]
        if rapid[cls] then
            assertNotNil(r, cls .. " carries no Rapid Regeneration row")
            assertEquals(1260270, r)
            local row = data[r]
            assertEquals(true, row.racial)
            assertEquals(180000, row.cooldownMs)
        else
            assertNil(r, cls .. " cannot roll Rapid Regeneration (Dwarf racial)")
        end
    end
    -- Summon Hawk (the Hunter family-9 pet-control line): the store's Rank 4
    -- 1293527, the shared 6 s cooldown with Arcane Shot (category 1173).
    -- Pre-M3a the id was hand-typed in Engine.lua as the 70425-era 1293241
    -- with no data row at all.
    local hunter, hunterByName = FX.Data.Hunter, FX.Data.HunterByName
    assertEquals(1293527, hunterByName["Summon Hawk"])
    local hawk = hunter[1293527]
    assertEquals(true, hawk.racial)
    assertEquals(6000, hawk.cooldownMs)
    assertEquals(1173, hawk.cooldownCategory)
    assertEquals("Rank 4", hawk.rank)
    assertEquals("Arcane Shot", hawk.shares)
    -- The hand table is gone: the data is the one source.
    assertNil(FX.Cooldown.Engine.RACIALS,
        "Engine.RACIALS survived the M3a migration; the racials ride the data")
end)
