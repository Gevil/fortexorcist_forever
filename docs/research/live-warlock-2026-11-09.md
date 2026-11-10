# Warlock live data, 2026-11-09 (the day before the Nov 10 tuning hotfix)

Researcher: RsrchWarlock (read-only). Written 2026-11-09. Only this file was written.

**Labels.** `[V]` = verified in a page I fetched today (URL + date given). `[D]` = derived from local data or code
(file, row id or function given). `[I]` = my inference. `[UNVERIFIED]` = could not be checked.

**What the "live numbers" are.** They are the live client's spell tables as captured by the wowsims/forever store, not an
in-game measurement. Clone `/tmp/wowsims-forever` @ `9ca4d977` (2026-11-09), `assets/db_inputs/spell_store_inputs.json`
(gzip JSON). `[D]` The `warlock` group is stamped `1.60.1.70790`, hotfix push `113715`. The `paladin` and `items` groups
are already at `1.60.1.70862` / push `113823`, so the warlock group has not been re-captured since the Nov 7 pull. Values
below come from tables `Misc`, `Levels`, `Cooldowns`, `Effects`, `Powers`, `ClassOptions`, `Descriptions`. The base pull is
`mythicsim-forever-engine` `data/spells.jsonl` (build 70425, repo @ `ff6a43cf`). Where I quote both they agree unless I say so.

---

## 0. Answer first

1. **Blizzard has published no numbers for the Nov 10 warlock changes.** `[V]` The only announcement is Kaivax's post of
   2026-11-06 (quoted in §1). It names Siphon Life, Corruption, Bane of Agony, Wrack and Voidwalker, and gives no value,
   percentage, duration or tick interval. I scanned all 534 posts in that thread and the only staff post is #1. It has
   never been edited (version 1). Secondary sites say the same: wowguide.net writes "Exact numbers aren't out yet."
   There is nothing to quote. The numbers will exist only after the hotfix, so the re-pull in §8 is the only source.
2. **Corruption ticks every 3 s today.** `[D]` Every castable Corruption rank (ids 172, 6222, 6223, 7648, 11671, 11672,
   25311) has `PeriodMs = 3000` in both the 70425 pull and the 70790 store. The test assumption
   (`Forte_Timer/tests/test_data_feeds.lua:140`) is true today. `[I]` Blizzard says it will keep "total damage output"
   unchanged, so shifting damage between Wrack and the DoTs is a coefficient change and does not have to touch the tick
   period. Nothing published rules a period or duration change out, so re-check after Tuesday.
3. **Bigger problem found: our `Corruption` row is the wrong spell.** `[D]` `Data/Warlock.lua` maps `Corruption` to
   **1223963** (12 s, no cast time). That row has no mana cost, no GCD, no cooldown row and no learn level. It is
   referenced only by the set-bonus spell "S03 - Item - Scarlet Enclave - Warlock - Tank 2P Bonus" (`RefIDs: [1223963]`,
   `sim/core/spelldata/spells_auto_gen.go:32519`). The spell a warlock actually casts is **25311** (Rank 7) or **11672**
   (Rank 6): 18 s, 2 s cast, 340 / 290 mana. So the Corruption bar is 12 s where the aura lasts 18 s. The same shape hits
   **Unstable Affliction** (§4). Fix in §10. It also changes `test_pet_rows.lua:315` (`near(row.total, 12)`).
4. **Corruption's duration depends on rank**, and most players are still levelling. `[D]` Rank 1 = 12 s, Rank 2 = 15 s,
   Ranks 3–7 = 18 s. Siphon Life (30 s), Bane of Agony (24 s) and Immolate (15 s) are the same in every rank. The generated
   data keeps one row per name, so a low-level Corruption bar will be too long even after the pin. See §3.
5. **"Summon Voidwalker hotfix":** `[V]` the only Voidwalker hotfix is the Nov 6 line "Voidwalker base health increased
   by about 40 at all levels." It is a creature stat. `[D]` The spell is unchanged in the store (697: 10 s cast, 1 Soul
   Shard, 100 % mana). The Nov 10 durability change is also unquantified. The only "Summon Voidwalker" data event on our
   side was our own overlay swapping 25112 → 697 (`Warlock.lua` header, 70790 overlay changes).
6. **New Forever-only rule that matters for bars:** `[D]` Unstable Affliction's description says "Only one Unstable
   Affliction or Immolate per Warlock can be active on any one target." Banes are exclusive per target too (Agony, Doom,
   Havoc). Our timer rows do not model either exclusion (PLAN §S6).

---

## 1. What Blizzard announced for Nov 10 (verbatim)

`[V]` Kaivax (Community Manager), "Class Tuning Incoming - November 10", 2026-11-06T21:11:39Z, version 1, never edited.
https://us.forums.blizzard.com/en/wow/t/2404092/1 (fetched 2026-11-09 17:2x UTC via the thread JSON):

> "Now that players around the world are leveling up in WoW: Forever, we've identified a few class issues that we feel
> need some immediate changes. Today, we're still investigating these issues and working through them with a plan to
> release hotfixes on Tuesday, November 10 to address:
> - We've seen that Hunter pets and Warlock Voidwalkers are not as durable as tanks as we would like them to be. Our
>   intent is for their effectiveness to be relatively the same as in Classic Era. We will adjust their stats as
>   necessary to accomplish this.
> - Affliction Warlock reports indicate that always channeling Wrack is superior to also casting damage-over-time
>   abilities like Siphon Life, Corruption, and Bane of Agony. We will make adjustments to make sure those are always
>   worthwhile to cast combined with Wrack, without affecting Affliction Warlocks' total damage output.
> - Enhancement Shamans … [Strength change, not warlock]
> Our plan is to make class balance changes on Tuesday, and then on future Tuesdays if necessary."

What the post fixes, and what it leaves open:

| Item | Stated | Not stated |
|---|---|---|
| Voidwalker | "relatively the same as in Classic Era" effectiveness as a tank; "adjust their stats as necessary" | which stats, how much; Hunter pets and Voidwalker are one bullet |
| Siphon Life, Corruption, Bane of Agony | "always worthwhile to cast combined with Wrack" | what changes (damage, duration, tick, cost, cast time) |
| Wrack | the premise: always channelling it beats DoTs | whether Wrack is nerfed, or the DoTs buffed, or both |
| Total damage | "without affecting Affliction Warlocks' total damage output" | measured against what rotation |

Checks that found nothing more:
- All 534 posts of the thread: only #1 is staff. Post #64 is a Community Council member's opinion on Wrack in PvP, not
  Blizzard `[V]`.
- Blizzard hotfix thread `2403040`, posts 1 and 4: warlock lines are only the three Nov 6 ones (§2). No Nov 8 or Nov 9
  hotfix post with warlock content was found. `[UNVERIFIED]` I could not reach the Blizzard blue tracker or the news feed
  for 2026-11-08/09 beyond the forum "latest" list.
- Secondary: https://wowguide.net/en/guides/wow-forever-class-tuning-november-10 (2026-11-08) "Exact numbers aren't out
  yet." Others (icy-veins, gladiatorboost, foreverdb) are the same post re-worded; I did not rely on them.

### 1.1 Earlier Blizzard numbers about the same spells (the only numeric announcements that exist)

- `[V]` Dev notes post 9, Kaivax 2026-11-03T03:20:33Z
  https://us.forums.blizzard.com/en/wow/t/2360696/9 (fetched 2026-11-09):
  - "Wrack: Spell damage coefficient doubled, to match the expected coefficient per cast time of 0.286 per second. Base
    damage per second now increases with each level by 2.5. Base damage per second at level 60 effectively increased from
    36 to 86."
  - "Bane of Agony now correctly dynamically updates its damage."
  - "Amplify Curse now correctly affects Curse of Exhaustion and Bane of Agony."
  - "Improved Drains: Now increases Drain Mana's amount of Mana drained but no longer increases Wrack damage."
  - "Pets now gain 2 Health per point of Master's Stamina (was 7.5 Health per point of Master's Stamina)."
  - "Drain Soul: This chance for this spell to grant a Soul Shard on dealing damage (not a kill) has been reduced
    significantly."
- `[V]` Class deep dive, Blizzard news "Rogue and Warlock", 2026-10-07, https://worldofwarcraft.blizzard.com/en-us/news/24310968
  (fetched 2026-11-09):
  - "Curse of Agony and Curse of Doom are now Banes. Only one Bane can be active per Warlock on a single target. All
    effects that interact with Curses now also interact with Banes."
  - "Curse of the Elements now applies to all magic damage." "Curse of Shadows removed."
  - "Wrack: (New 31-point gold medal talent.) Tears the target apart from within, inflicting Shadow damage every second
    and increasing the damage they take from your other Shadow damage-over-time (DoT) effects by 10% for 6 seconds. This
    spell grants the Affliction Warlock a powerful drain-style spell to use as their primary spell when not re-casting
    damage-over-time spells or instant Shadow Bolts from Nightfall."
  - "Soul Siphon: (New row 5 talent) Increases the damage done or Health drained by your Drain Life, Drain Soul, and
    Wrack spells by up to 12% for each of your other Affliction spells on the target, up to a maximum increase of 36%."
  - "Improved Corruption: Now also increases Corruption's damage to a maximum of 10%." "Improved Bane of Agony:
    (Previously Improved Curse of Agony) Damage increased and now is 2 points instead of 3."
  - "Drain Soul now has a progressive chance per tick to grant a Soul Shard (chance increases each time it doesn't
    happen, until guaranteed)."
- `[V]` Nov 6 hotfixes https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-6-2026/2403040 (post 4,
  2026-11-07T01:07:59Z): "Voidwalker base health increased by about 40 at all levels." / "The Soul Siphon talent no
  longer incorrectly causes Wrack to increase its own damage." / "Fixes an issue where some Warlock pet abilities were
  benefitting too much from the Orc Command racial ability."

---

## 2. Current live numbers for the five spells named in the announcement (the re-pull baseline)

All rows `[D]` from the store (`Misc`, `Effects`, `Powers`, `Cooldowns`) at 70790 / push 113715. `BP` = `BasePoints`
as stored, `Coef` = `SPCoef`; I did not convert them to per-tick damage (the unit convention of `BasePoints` is not
stated in the store, so a damage figure would be `[UNVERIFIED]`).

| Spell | Row id (rank) | Duration | Tick | Cast | GCD | Mana | BP / Coef per tick | Notes |
|---|---|---|---|---|---|---|---|---|
| Corruption | **25311** (R7, Grimoire book), 11672 (R6, trainer) | 18 000 ms | **3000 ms** | 2000 ms | 1500 | 340 / 290 | 73 / 0.200 ; 57 / 0.200 | R1 172: 12 s (learn level 4); R2 6222: 15 s; R3-R6 18 s |
| Corruption (wrong row we use) | 1223963 | 12 000 ms | 3000 ms | 0 | none | none | 137 / 0.167 | no Powers/Cooldowns row, BaseLevel 0 |
| Bane of Agony | **11713** (R6) | 24 000 ms | **2000 ms** | 0 (instant) | 1500 | 215 | 46 / 0.133 | ranks 980/1014/6217/11711/11712 also 24 s / 2 s; extra effects: aura 271 (class mask 0x400, the self/Amplify hook) and aura 4 (dummy). Ramp: sim assumes 0.5× / 1× / 1.5× per third (`sim/warlock/agony.go`, from the Nov 3 notes) `[D]`, I did not verify it in game |
| Siphon Life | **18881** (R4) | 30 000 ms | **3000 ms** | 0 | 1500 | 365 | 41 / 0.050 | aura 53 (periodic leech); ranks 18265/18879/18880 also 30 s / 3 s |
| Wrack | **1316697** (R1, level 40) | 6 000 ms (channel) | **1000 ms** | 0 | 1500 | 200 | 36 + 2.5/level / 0.286 | effect 2 = aura 271, **BP 10** (+10 %), class mask `0x402` = Corruption (0x2) + Bane of Agony (0x400). Siphon Life's family flag sits in mask word 1 and is not named `[D]`, matching `sim/warlock/wrack.go` comment. Matches Nov 3 notes: coef 0.286, 36 → 86 at level 60 |
| Summon Voidwalker | **697** (Summon) | none (-1) | – | 10 000 ms | 1500 | CostPct 100 | – | reagent: 1× item 6265 (Soul Shard); 25112 is the older row, no reagent |

`[D]` Test impact today: Corruption 3 s ✓ (`test_data_feeds.lua:140`, `:320`), Agony 2 s ✓, Siphon 3 s ✓, Wrack 1 s ✓
(all `tickEvery` in `Data/Warlock.lua` match the store). Durations in our data: Corruption 12 000 ✗ (store 18 000 on the
castable ranks), Agony 24 000 ✓, Siphon 30 000 ✓, Wrack 6 000 ✓.

`[I]` Likely knobs for Tuesday, from the post and the data (no source states them): the Wrack channel's per-second BP,
its aura-271 percentage and its class mask (adding Siphon Life's mask word would make "always worthwhile" true for it
without touching Siphon's own row); the DoTs' BP / Coef; durations and ticks are less likely because "total damage
output" is to stay fixed, but not excluded.

---

## 3. The Corruption test assumption, in detail

- 3 s tick: `[D]` all seven castable ranks `PeriodMs 3000`. The NPC-style shells 13530, 17510, 18088 carry `PeriodMs 1000`
  / `DurationMs 3000` with no family. They sit in the overlay (`tools/overrides_70790.json`, the "Corruption 13530/17510"
  lines of `docs/research/data-diff-live-2026-11-07.md` §2.1) and must never win the pick; today they do not.
- Secondary measurement `[UNVERIFIED]`: `docs/research/upstream-addons-2026-11-03.md:172` quotes an addon comment that
  Corruption's first and second ticks land at 3.00 / 6.00 s within ±0.03 s. I did not re-open the addon source.
- The data model keeps one duration per name. `[D]` Corruption: R1 12 s (lvl 4), R2 15 s (lvl 14), R3–R7 18 s. Fear: R1
  10 s, R2 15 s, R3 20 s. Howl of Terror: R1 10 s, R2 15 s (store rows Fear 5782 / 6213 / 6215, Howl of Terror 5484 / 17928). The generator takes the top rank, so a level-20 warlock's Corruption (R2) or Fear (R2) bar is wrong even
  with correct pins. `[I]` Own casts expose a readable spell id (`docs/research/forever-postlaunch-2026-11-07.md` §2.2),
  so a `{[spellId] = durationMs}` rank table would fix this without secret reads. This is an open design question
  (§11), not part of the patch.

---

## 4. Immolate, Unstable Affliction, Curse and Bane family

| Spell | Row | Duration | Tick / cast / cd | Notes `[D]` |
|---|---|---|---|---|
| Immolate | **11668** (R7 trainer), 25309 (R8 book) | 15 000 | tick 3000; cast 2000; GCD 1500; 370 mana | tick BP 52 / coef 0.13; direct BP 146 + 2.3/level / coef 0.20; ranks 348…11667 all 15 s / 3 s. Identical values on R7 and R8, so our pick (11668) is fine |
| Unstable Affliction | **427717** (R1, level 40) | **18 000** | tick 3000; cast 1500; GCD 1500; 200 mana | BP 86 / coef 0.20. Description: "Only one Unstable Affliction or Immolate per Warlock can be active on any one target." |
| UA silence effect | 427719 (what our data uses) | 5 000 | none | `Aura 27` (silence) on the dispeller; no Powers, no level. **Wrong row for a cast-predicted bar** (the bar would run 5 s, the DoT 18 s) |
| Curse of Weakness | 11708 (R6) | 120 000 | cast 0, GCD 1500 | ranks R1 702 … R6 11708 all 120 s |
| Curse of Recklessness | 11717 (R4) | 120 000 | same | Nov 3 notes: stacking of duplicates fixed `[V]` (post 6, 2026-10-16) |
| Curse of the Elements | 1311680 (R4), 440892 / 1311676 / 1311677 | 300 000 | same | Forever-only id band; now "all magic damage" `[V]` deep dive |
| Curse of Tongues | 11719 (R2) | 30 000 | same | |
| Curse of Exhaustion | 18223 | 12 000 | same | |
| Curse of Idiocy | 1010 (R1) | 120 000 | tick 3000 | stack cap 15 in our data |
| Bane of Agony | 11713 | 24 000 | tick 2000 | see §2 |
| Bane of Doom | 603 | 60 000 | cd 60 000, GCD 1500 | was Curse of Doom; "Cannot be cast on players" |
| Bane of Havoc | 1225228 | 300 000 | no cd/GCD row in the store | Forever talent; "limited to 1 target" `[V]` deep dive |
| Amplify Curse | 18288 | 30 000 window | cd 180 000 | now also affects Exhaustion and Agony `[V]` |

`[D]` "Curse of Agony" and "Curse of Doom" no longer exist by those names; "Curse of Shadows" is removed. Our list
already uses the Bane names and has no Shadows entry.

---

## 5. Fear / Howl / CC, and the shard-spending cooldowns

| Spell | Row | Duration | Cast | Cooldown | Notes `[D]` |
|---|---|---|---|---|---|
| Fear | 6215 (R3) | 20 000 | 1500 | none | R1 5782 10 s, R2 6213 15 s; description "Only 1 target can be feared at a time" |
| Howl of Terror | 17928 (R2) | 15 000 | 2000 | 40 000 (cat 634) | R1 5484 10 s |
| Death Coil | 17926 (R3) | 3 000 | 0 | 120 000 (cat 633) | |
| Banish | 18647 (R2) | 30 000 | 1500 | none | |
| Subjugate Demon | 11726 (R3) | 300 000 | 3000 | none | |
| Shadowburn | 18871 (R6) | 8 000 (shard window) | 0 | **15 000** (cat 651) | "If the target dies within 8 s … the caster gains a Soul Shard"; ranks 17877…18870 all 15 s |
| Conflagrate | 18932 (R6) | – | 0 | **10 000** (cat 672) | requires Immolate on the target; consumes it; R1–R6 all 10 s |
| Chaos Bolt | 403629 | – | 2500 | **12 000** | no rank; Forever id band |
| Haunt | 403501 (R1) | 12 000 | 1500 | 15 000 | |
| Soul Fire | 17924 (R2) | – | 6000 | 60 000 (cat 631) | |
| Shadow Cleave | 403852 (R10) | – | 0 | 6 000 (cat 2129) | |

`[UNVERIFIED]` PvP durations (Fear, Howl, Death Coil): the store has no PvP duration column.
`[I]` The Nov 6 and Nov 10 posts mention none of these, so I expect no change on Tuesday.

---

## 6. Metamorphosis, Demon Charge, Fel Domination and the other Forever kit `[D]`

| Spell | Row | Duration | Cooldown | Notes |
|---|---|---|---|---|
| Metamorphosis | 403789 (+ aura 403816, 403873) | -1 (toggle) | **none** in the store (`Cooldowns` row is 0 / 0) | GCD 1500; `Powers`: mana, CostPct 100 `[UNVERIFIED]` whether that is charged in game; transforms Searing Pain, Shadow Bolt and others |
| Demon Charge | 412788 | stun | **15 000** (category, GCD 0) | "Cannot be used in combat." |
| Fel Domination | 18708 | 15 000 window | **300 000** | next summon: cast time and mana reduced |
| Demonic Howl | 412789 | 6 000 | **600 000** | GCD 1500 taunt-style |
| Demonic Grace | 425463 | 6 000 | 20 000 | |
| Menace | 442233 | 3 000 | 10 000 (cat 82) | taunt |
| Infernal Armor | 440882 | 10 000 | 60 000 | |
| Vengeance | 426195 | 20 000 | 180 000 | |

`[I]` Metamorphosis having no cooldown row means our cooldown list entry gives no bar. This was already the case in
`Data/Warlock.lua` (no `cooldownMs`). It is a toggle (`durationMs = -1`).

### Forever-specific warlock spells (not in the 2005 Classic set) `[D]` ids from `Data/Warlock.lua` and the store

Wrack 1316697 (level 40), Incinerate 412758 / 1293812 / 1293813 (2.5 s cast, levels 40/50/60, not tracked: no duration
or cooldown), Haunt 403501, Chaos Bolt 403629, Shadow Cleave 403852, Unstable Affliction 427717, Bane of Havoc 1225228,
Shadowflame 426320, Metamorphosis 403789, Demon Charge 412788, Demonic Howl 412789, Demonic Grace 425463, Menace 442233,
Infernal Armor 440882, Vengeance 426195, Immolation Aura 427726, Summon Felguard 427733, Portal of Summoning 437169,
Dance of the Wicked 412800, Backdraft 427714, Soul Harvest 1242853. `[I]` Most look like Season-of-Discovery rune
spells; that origin is my guess from names and id bands, not a verified source.

---

## 7. Pet kit and the warlock tools' data dependencies

### 7.1 Pets (generated rows from the 70790 overlay; `[D]` `Data/Warlock.lua`, matches the store)

| Pet | Summon | Abilities in our data |
|---|---|---|
| Imp | 688, cast 10 s, 80 % mana, **no shard** | Fire Shield 11771 (R5, 180 s window) |
| Voidwalker | **697**, 10 s, 1 shard | Torment 11775 (R6, cd 5 s), Suffering 17752 (R4, cd 120 s), Consume Shadows 17854 (R6, 10 s, tick 2 s), Sacrifice 19443 (R6, 30 s window) |
| Succubus | 712, 10 s, 1 shard | Seduction 6358 (15 s, cast 1.5 s), Soothing Kiss 11785 (R4, cd 4 s), Lash of Pain 11780 (R6, cd 12 s), Lesser Invisibility 7870 (300 s) |
| Incubus | 713, 10 s, 1 shard | Mesmerize 24594 (name-only shell, no values; owner pet is my guess `[I]`) |
| Felhunter | 691, 10 s, 1 shard | Spell Lock 19647 (R2, 8 s lockout, **cd 30 s**), Devour Magic 19736 (R4, cd 8 s), Paranoia 19480, Tainted Blood 19660 (R4, 60 s) |
| Felguard | 427733, 10 s, 80 % mana, 1 shard | – |
| Infernal | Inferno 1122, cd 3 600 000, cast 2 s | reagent item 5565 |

- `[V]` Pet tuning facts: "A Warlock's current pet will now be stunned while summoning a new pet" (dev notes post 5);
  "Improved Felhunter … reduce the cooldown of its Spell Lock by 2 seconds" (deep dive), so the 30 s cooldown above can
  shorten with the talent; our data row cannot show that.
- `[D]` `sim/warlock/pets.go` models pet health as `1.400 × CreatureHealthMaxLevel` for the Voidwalker (0.699 for the
  Succubus), read at level 30 only (its own TODO). The Nov 6 "+40 health" and the Nov 10 durability change are creature
  stats; no spell-store row carries them. The store cannot confirm either change. `[UNVERIFIED]` creature health after
  Nov 10.
- `[D]` The Nov 3 notes put pet health at 2 per point of the warlock's Stamina; the sim marks this "Ingame test needed".

### 7.2 Shards, healthstones, soulstones, summons (what `Forte_Warlock` reads)

- **Soul Shard (6265)** `[D]`: reagent of Create Healthstone / Soulstone / Firestone / Spellstone (6366, 11730, 17728,
  17953, 20757), Ritual of Summoning 698, and the Summon Voidwalker / Succubus / Incubus / Felhunter / Felguard rows
  (count 1 each). The sim's 32-shard cap is a sim constant, not a game fact `[UNVERIFIED]`.
  Shard income is not cast-driven: Drain Soul has a progressive per-tick chance (deep dive) and Shadowburn grants one
  if the target dies within 8 s. `[I]` The shard counter must come from bag counts (`C_Item.GetItemCount`), as
  `Forte_Warlock/Core/Tools.lua` already does by name; no cast event predicts it.
- **Healthstone** `[D]`: the spell rows (Minor 23469, Lesser 23471, Healthstone 23473, Greater 23475, Major 23477) have
  no spell cooldown, spell category 30. The cooldown is on the item: Major Healthstone item 9421 has
  `categoryCooldownMs = 120000`, item category 1153 (`Forte_Items/Data/Items.lua`, row for 9421).
  `[I]` Our own-bag cooldown read therefore needs the item API, as `Core/Tools.lua` does.
- **Soulstone** `[D]`: Create Soulstone 20757 (R5): cast 3000, 1 shard. Soulstone Resurrection 20765 / 20762:
  `DurationMs 1 800 000`. Our data's `Use Soulstone` 20761 has no duration, and `Core/Tools.lua` predicts 1800 s
  (`WK.SOULSTONE_SECONDS`). The store agrees with 1800 s.
- **Summons**: Ritual of Summoning 698: cast 5000, duration 600 000, 1 shard. Ritual of Doom 18540 cd 3 600 000, 10 s
  cast, reagent 16583. Portal of Summoning 437169 cd 3 600 000.

---

## 8. Re-pull procedure for after Tuesday (what to diff)

Order: (1) wait for the wowsims clone to move the `warlock` group stamp past `1.60.1.70790` / push `113715`
(`d['Builds']['warlock']`, `d['Hotfixes']['warlock']` in the gzip JSON; paladin and items already moved to 70862 /
113823 on Nov 9); (2) regenerate; (3) compare against §2.

Read command (read-only, from the clone directory):
`python3 -c "import gzip,json;d=json.load(gzip.open('assets/db_inputs/spell_store_inputs.json'));i='25311';print(d['Misc'][i],d['Effects'][i],d['Powers'][i])"`

Re-pull these ids and fields:

| Ids | Fields | Fails if |
|---|---|---|
| 25311, 11672 (Corruption) | `Misc.DurationMs`, `Misc.CastTimeMs`, `Effects[0].PeriodMs`, `BasePoints`, `SPCoef`, `Powers.Cost` | period ≠ 3000 → `test_data_feeds.lua:140,320`; duration ≠ 18 000 → bar length |
| 11713 (Agony) | same, plus the aura-271 and aura-4 effects | period ≠ 2000 → `tickEvery`; duration ≠ 24 000 |
| 18881 (Siphon Life) | same | period ≠ 3000; duration ≠ 30 000 |
| 1316697 (Wrack) | `DurationMs`, `PeriodMs`, `Effects[0].BasePoints/PPL/SPCoef`, `Effects[1].BasePoints` and `ClassFlags.Mask` | period ≠ 1000 or duration ≠ 6000 |
| 697 | `Misc`, `Powers`, `Reagents` | shard or cast change |
| 11668, 25309, 427717 | duration, period, cast | Immolate / UA window |
| New ids | `Names` rows whose name is one of our tracked names and whose `ClassOptions.Family == 5` | a new "Corruption", "Wrack" or "Siphon Life" row would change the pick (compare `docs/research/forever-postlaunch-2026-11-07.md` §0 item 8 for the Frost Armor precedent) |

`[I]` Creature health (Voidwalker, Hunter pets) is not in this table, so Tuesday's pet change will not show in the store
at all. The only check is in game: summon a Voidwalker, read its health with `UnitHealthMax("pet")` before and after
(it may be secret in combat, so read out of combat).

After regenerating, run the in-game check the launch-day doc already prescribes (`docs/launch-day.md:228-232`): put each
DoT on a target and compare the row with the tooltip.

---

## 9. Evidence quality

- Announced numbers: none exist. The Blizzard post is a plan; no hotfix after it has been published as of 2026-11-09.
- Live numbers: one capture, the store at build 70790 / push 113715 (2026-11-07 pull, clone commit 2026-11-09), plus the
  70425 base pull. Both are table extracts, not measurements in game. Independent replication: the two extracts agree on
  every period and duration quoted in §2 and §4; one secondhand in-game timing for Corruption and Agony ticks exists in
  our docs and is unverified (§3).
- Out-of-sample / leakage / costs: not applicable (no performance claim). Replication status for the Corruption-row
  finding: two sources (`mythicsim` row and store row for 1223963; the sim's own use of 11672 / 25311 in
  `sim/warlock/corruption.go`) agree.
- `[UNVERIFIED]` whether push 113715 already contains the Nov 6 server-side warlock changes. I did not diff the Soul
  Siphon talent aura. `[UNVERIFIED]` the Nov 8 and Nov 9 hotfix lists for warlock lines (no page found).

---

## 10. Implications for our setup

1. **Fix the Corruption and Unstable Affliction rows now**, before the Tuesday re-pull, so the re-pull diffs a correct
   baseline. Otherwise Tuesday's diff will compare a changed 25311 against our 1223963 and show nothing.
2. **Keep the `tickEvery = 3` assert**, but expect a rewrite if the post-Tuesday period differs. Re-run §8 first.
3. **Tests that follow the pin:** `test_pet_rows.lua:53` (id 1223963 → name "Corruption", "12 s") and `:315`
   (`near(row.total, 12)`); both assume the wrong row. They should use 25311 and 18. `test_data_feeds.lua:317`
   passes explicit 5000 values to `InsertFromCast`, so it is probably unaffected `[I]` (not run).
4. **Exclusion rows:** UA ↔ Immolate on the same target, and Agony / Doom / Havoc on the same target, are real rules.
   `[I]` Casting one should evict the other's row for that target; this needs the S6 eviction feed
   (`docs/class-port.md` S6).

## 11. Open questions

1. What exactly changes on Tuesday for the three DoTs and for Wrack (the post names none)? Answer only after §8.
2. Do we want a per-rank duration table (§3) now that most players are below level 60, or do we accept the top-rank bar
   with the in-combat reconcile correcting it?
3. Does the live client report 25311 or 11672 as the cast spell id for a player who has learnt the Grimoire rank? The
   name-keyed runtime resolves both, so only the bar duration is at stake (both 18 s).
4. Which of 1223963's triggers is real? `[UNVERIFIED]` I found only the Scarlet Enclave set-bonus reference; I did not
   see the row fired in game.
5. Pet durability: how will we know the Tuesday value, given it is outside the spell store?

---

## Proposed patch

Edit `tools/spell_lists/warlock.json` `_pins` only, then regenerate with `python3 tools/gen_spell_data.py warlock`.

```json
"Corruption": {
  "id": 25311,
  "reason": "the rank law picks 1223963 (Rank 7, 12 s, cast 0, no Powers/Cooldowns/BaseLevel row; referenced only by the S03 Scarlet Enclave Warlock Tank 2P set bonus, spells_auto_gen.go:32519). The castable Corruption is 25311 (R7) / 11672 (R6): 18 s, 3 s tick, 2 s cast, 340/290 mana. Store 70790/113715, mythicsim 70425 agree."
},
"Unstable Affliction": {
  "id": 427717,
  "reason": "the rank law picks 427719, the 5 s dispel-silence trigger (Aura 27, no Powers). The cast spell 427717 (Rank 1) is the 18 s DoT with 3 s tick and 1.5 s cast."
}
```

| Line | Confidence | One-line reason a builder can apply mechanically |
|---|---|---|
| Pin `Corruption` → 25311 | **high** | the generated row's id has no mana cost, GCD or learn level, so it is not a player cast; 25311 has all three and the sim casts it |
| Pin `Unstable Affliction` → 427717 | **high** | 427719's description is empty and its only effect is silence; 427717 is the named, castable, 18 s DoT |
| No change to Bane of Agony, Siphon Life, Wrack, Immolate, Summon Voidwalker rows | high | picked ids 11713, 18881, 1316697, 11668, 697 match the store values in §2 |
| Do **not** add a Voidwalker or Hunter-pet row for Nov 10 | med | the change is a creature stat; no spell-store field carries it |
| After Tuesday: re-run the §8 table, then review `tickEvery` / `durationMs` for the four DoTs | – | nothing to patch until the new values exist |

Expected generated effect of the two pins: `Corruption` `durationMs 12000 → 18000`, `castMs` becomes 2000 and gains
`gcdMs = 1500`; `Unstable Affliction` `durationMs 5000 → 18000`, `tickEvery = 3`, `castMs = 1500`, `gcdMs = 1500`. `[I]` I
did not run the generator (read-only task); check the diff before accepting.
