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

test("the store's corrected cooldowns land: Shifting Power 8 s, Charge Rank 3",
function()
    -- data-diff §2: Shifting Power 1322605 Cooldowns 16000 -> 8000 (the store
    -- row rides family 3). Pre-overlay the data said 16000.
    local druid, druidByName = FX.Data.Druid, FX.Data.DruidByName
    local shifting = druid[druidByName["Shifting Power"]]
    assertNotNil(shifting)
    assertEquals(1322605, shifting.id)
    assertEquals(8000, shifting.cooldownMs)
    -- Charge: Rank 3 11578 (live 70862 store / review 2026-11-10). History:
    -- 1240289 (Rank III, no cooldown) -> 27685 (Rank VI, data-diff §2.4,
    -- 25 s charge-stun cooldown) -> 11578 on the final 70862 overlay: the 15 s
    -- Warrior charge, shared category 44, off the GCD. Re-pinned from 27685.
    local warrior, warriorByName = FX.Data.Warrior, FX.Data.WarriorByName
    local charge = warrior[warriorByName["Charge"]]
    assertNotNil(charge)
    assertEquals(11578, charge.id)
    assertEquals("Rank 3", charge.rank)
    assertEquals(15000, charge.cooldownMs)
    assertEquals(44, charge.cooldownCategory)
    assertNil(charge.gcdMs, "Charge is off the GCD")
    -- (Cower moved out: its own test below, so a Warrior pin never masks it)
    -- Wild Growth: the store's Levels capture adds the 3 s cast (pre-overlay
    -- the row carried no cast at all).
    local wild = druid[druidByName["Wild Growth"]]
    assertNotNil(wild)
    assertEquals(3000, wild.castMs)
end)

-- Live 70862 store / review 2026-11-10: the druid Cower is 9892 (Rank 3, cat
-- 84, 10 s, GCD 1 s). Re-pinned from the Hunter pet's Cower Rank VI 16697
-- (5 s, category 82, which the engine refuses as the pet/threat label).
test("the druid Cower is the druid's own row, not the Hunter pet's", function()
    local druid, druidByName = FX.Data.Druid, FX.Data.DruidByName
    local cower = druid[druidByName["Cower"]]
    assertNotNil(cower)
    assertEquals(9892, cower.id)
    assertEquals("Rank 3", cower.rank)
    assertEquals(10000, cower.cooldownMs)
    assertEquals(84, cower.cooldownCategory)
    assertEquals(1000, cower.gcdMs)
    assertNil(druid[16697], "the Hunter pet's Cower Rank VI is not a druid row")
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
    -- Cripple: the 70862 store dropped the family-less 89 capture (it was the
    -- line's only castable row; 18381 stayed a name-only row) and the Warrior
    -- spell list no longer carries the name -- live 70862 store / review
    -- 2026-11-10. Re-pinned from `assertEquals(89, ...)`: absence is the pin.
    assertNil(FX.Data.WarriorByName["Cripple"],
        "Cripple returned to the Warrior data (it was removed on 70862)")
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

-- Live 70862 store / review 2026-11-10 -- the CENSUS of corrected picks. The
-- stage-A diff report let Thorns (the item-proc aura 15438 out-ranked the real
-- Rank 6 9910 on level) and Summon Voidwalker (the Abyss Shard no-reagent
-- summon 25112 tied 697 on level and won on id) slip through because no test
-- pinned the id: a future refresh that silently re-picks a decoy must go RED
-- here. One row per corrected pick, id + the values that distinguish it from
-- the decoy. The picks are the spell lists' `_pins` / the rank law's results
-- (tools/spell_lists/<class>.json, docs/research/data-diff-live-2026-11-10.md).
local function pin(className, name, id, fields)
    local byName = FX.Data[className .. "ByName"]
    assertNotNil(byName, className .. "ByName did not load")
    assertEquals(id, byName[name],
        className .. ": " .. name .. " re-picked off " .. tostring(id)
        .. " -- a decoy row won the rank law")
    local row = FX.Data[className][id]
    assertNotNil(row, className .. ": " .. name .. " has no row at " .. id)
    assertEquals(name, row.name)
    for field, want in pairs(fields or {}) do
        assertEquals(want, row[field],
            className .. ": " .. name .. " (" .. id .. ") field " .. field)
    end
    return row
end

test("census 70862: the Druid picks (Thorns, Dash, Cower, Abolish Poison)", function()
    -- Thorns 9910 (Rank 6, 600 s) -- NOT the item-proc aura 15438.
    local thorns = pin("Druid", "Thorns", 9910,
        { durationMs = 600000, gcdMs = 1500, rank = "Rank 6" })
    assertNil(FX.Data.Druid[15438], "the Thorns item-proc decoy is in the druid data")
    assertNil(thorns.cooldownMs)
    -- Dash 9821 (Rank 2, 300 s, off the GCD) -- NOT the Hunter pet's 23110.
    local dash = pin("Druid", "Dash", 9821,
        { durationMs = 15000, cooldownMs = 300000, cooldownCategory = 44,
          rank = "Rank 2", noTarget = true })
    assertNil(dash.gcdMs, "the druid Dash is off the GCD")
    assertNil(FX.Data.Druid[23110], "the Hunter pet's Dash is in the druid data")
    -- Cower 9892 (Rank 3, cat 84, 10 s, GCD 1 s) -- NOT the pet's 16697.
    pin("Druid", "Cower", 9892,
        { cooldownMs = 10000, cooldownCategory = 84, gcdMs = 1000, rank = "Rank 3" })
    assertNil(FX.Data.Druid[16697], "the Hunter pet's Cower is in the druid data")
    -- Abolish Poison 2893 -- NOT Black Husk Shield's on-use spell 14253.
    pin("Druid", "Abolish Poison", 2893,
        { durationMs = 8000, tickEvery = 2, gcdMs = 1500 })
    assertNil(FX.Data.Druid[14253], "the Black Husk Shield spell is in the druid data")
    -- The rows the store removed stay gone; the deferred note is the new one.
    for _, gone in ipairs({ "Astral Power", "Force of Nature", "Wild Rejuvenation",
                            "Fury of Stormrage", "Thrash", "Eclipse" }) do
        assertNil(FX.Data.DruidByName[gone], gone .. " returned to the Druid data")
    end
end)

test("census 70862: the Mage picks (Fire Blast, Frost Armor)", function()
    -- Fire Blast 10199 (Rank 7, 8 s, cat 19, GCD 1.5 s) -- NOT 400623.
    pin("Mage", "Fire Blast", 10199,
        { cooldownMs = 8000, cooldownCategory = 19, gcdMs = 1500, rank = "Rank 7" })
    assertNil(FX.Data.Mage[400623], "the Season-of-Discovery Fire Blast is in the mage data")
    pin("Mage", "Frost Armor", 7301,
        { noTarget = true, durationMs = 1800000, rank = "Rank 3" })
end)

test("census 70862: the Warlock picks (Corruption, Unstable Affliction, Summon Voidwalker)",
function()
    -- Corruption 11672 (Rank 6, 18 s, 2 s cast, 3 s tick) -- NOT 1223963 (12 s).
    pin("Warlock", "Corruption", 11672,
        { durationMs = 18000, castMs = 2000, gcdMs = 1500, tickEvery = 3,
          rank = "Rank 6" })
    assertNil(FX.Data.Warlock[1223963], "the Scarlet Enclave Corruption is in the warlock data")
    -- Unstable Affliction 427717 (18 s DoT, 1.5 s cast) -- NOT 427719 (5 s).
    pin("Warlock", "Unstable Affliction", 427717,
        { durationMs = 18000, castMs = 1500, tickEvery = 3, rank = "Rank 1" })
    assertNil(FX.Data.Warlock[427719], "the 5 s dispel trigger is in the warlock data")
    -- Summon Voidwalker 697 (values identical) -- NOT the Abyss Shard 25112.
    pin("Warlock", "Summon Voidwalker", 697,
        { durationMs = -1, castMs = 10000, gcdMs = 1500, rank = "Summon" })
    assertNil(FX.Data.Warlock[25112], "the Abyss Shard summon is in the warlock data")
end)

test("census 70862: the Shaman picks (Earth Shock, Lightning Shield)", function()
    -- Earth Shock 10414 (Rank 7, cat 19, 6 s) -- NOT 408690 (cat 2171).
    pin("Shaman", "Earth Shock", 10414,
        { cooldownMs = 6000, cooldownCategory = 19, durationMs = 2000, rank = "Rank 7" })
    assertNil(FX.Data.Shaman[408690], "the cat-2171 Earth Shock is in the shaman data")
    -- Flame Shock 10448 and Frost Shock 10473 share the category: the 3-group.
    pin("Shaman", "Flame Shock", 10448, { cooldownCategory = 19 })
    pin("Shaman", "Frost Shock", 10473, { cooldownCategory = 19 })
    -- Lightning Shield 10432 (Rank 7, 600 s, 3.5 s ICD, caster-side) -- NOT
    -- 28821 (the permanent -1 set-bonus passive, which drew no Timer row).
    pin("Shaman", "Lightning Shield", 10432,
        { durationMs = 600000, gcdMs = 1500, icdMs = 3500, noTarget = true,
          rank = "Rank 7" })
    assertNil(FX.Data.Shaman[28821], "the set-bonus Lightning Shield is in the shaman data")
end)

test("census 70862: the Rogue poison ranks and Venom", function()
    for _, p in ipairs({ { "Deadly Poison II", 2819, "Rank 2" },
                         { "Deadly Poison III", 11353, "Rank 3" },
                         { "Deadly Poison IV", 11354, "Rank 4" } }) do
        pin("Rogue", p[1], p[2], { durationMs = 12000, tickEvery = 3, maxStack = 5,
                                   rank = p[3] })
    end
    pin("Rogue", "Mind-numbing Poison II", 8692, { durationMs = 12000, rank = "Rank 2" })
    -- Venom 1310703 (the 6 s Shank aura) -- NOT the level-30 passive 1329328.
    pin("Rogue", "Venom", 1310703, { durationMs = 6000, gcdMs = 1000 })
    assertNil(FX.Data.Rogue[1329328], "the Venom talent passive is in the rogue data")
end)

test("census 70862: the Warrior picks (Charge, Rend, Reckless Swings, Gore Drinker)",
function()
    pin("Warrior", "Charge", 11578,
        { cooldownMs = 15000, cooldownCategory = 44, rank = "Rank 3" })
    pin("Warrior", "Rend", 11574,
        { durationMs = 21000, tickEvery = 3, gcdMs = 1500, rank = "Rank 7" })
    pin("Warrior", "Reckless Swings", 1329555,
        { cooldownMs = 15000, durationMs = 8000, gcdMs = 1000 })
    pin("Warrior", "Gore Drinker", 1323969, { durationMs = 8000, noTarget = true })
    for _, gone in ipairs({ "Cripple", "Cheat Death", "Howling Blade",
                            "Spell Vulnerability", "Retaliate", "Deep Wounds",
                            "Intervene" }) do
        assertNil(FX.Data.WarriorByName[gone], gone .. " returned to the Warrior data")
    end
end)

test("census 70862: the Paladin picks (Cleanse, Exorcism, Judgement of Light, the new casts)",
function()
    -- Cleanse 4987 (the level-42 spell) -- NOT the passive 28787.
    pin("Paladin", "Cleanse", 4987, { gcdMs = 1500 })
    assertNil(FX.Data.Paladin[28787], "the Cleanse passive is in the paladin data")
    -- Exorcism 10314 (Rank 6, 15 s, cat 19) -- NOT the rune ladder 415073.
    pin("Paladin", "Exorcism", 10314,
        { cooldownMs = 15000, cooldownCategory = 19, gcdMs = 1500, rank = "Rank 6" })
    assertNil(FX.Data.Paladin[415073], "the rune Exorcism is in the paladin data")
    pin("Paladin", "Judgement of Light", 20346, { durationMs = 40000, rank = "Rank 4" })
    pin("Paladin", "Holy Strike", 10333,
        { cooldownMs = 10000, cooldownCategory = 2404, gcdMs = 1500, rank = "Rank 8" })
    pin("Paladin", "Holy Wrath", 10318,
        { cooldownMs = 60000, castMs = 2000, gcdMs = 1500, rank = "Rank 2" })
    pin("Paladin", "Light's Vigil", 1311595,
        { cooldownMs = 6000, castMs = 1500, gcdMs = 1500, rank = "Rank 3" })
    for _, e in ipairs({ { "Echo of Righteousness", 1311704 },
                         { "Echo of Justice", 1311705 },
                         { "Echo of Light", 1328198 },
                         { "Echo of Wisdom", 1328206 } }) do
        pin("Paladin", e[1], e[2], { durationMs = 15000, maxStack = 3, noTarget = true })
    end
end)

test("census 70862: the Hunter picks (Serpent Sting, Raptor Strike)", function()
    -- Serpent Sting 13555 (Rank 8, 15 s) -- NOT the 12 s 425737 row.
    pin("Hunter", "Serpent Sting", 13555,
        { durationMs = 15000, tickEvery = 3, gcdMs = 1500, rank = "Rank 8" })
    assertNil(FX.Data.Hunter[425737], "the 12 s Serpent Sting is in the hunter data")
    -- Raptor Strike 14266 (Rank 8, 6 s, cat 40, off the GCD) -- NOT 415343.
    local raptor = pin("Hunter", "Raptor Strike", 14266,
        { cooldownMs = 6000, cooldownCategory = 40, rank = "Rank 8" })
    assertNil(raptor.gcdMs, "Raptor Strike is off the GCD")
    assertNil(FX.Data.Hunter[415343], "the 415343 Raptor Strike is in the hunter data")
end)
