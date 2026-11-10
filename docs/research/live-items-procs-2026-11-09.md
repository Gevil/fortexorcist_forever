# Live items, consumables and procs on 70790 / 70862 (push 113823): what `gen_item_data.py` gets wrong or never sees

Researched and written 2026-11-09 by RsrchItems (read-only research subagent). All web pages and local clones were read on 2026-11-09. Only this file was written.

**Claim labels**

- **[V]** verified: a verbatim value from a page I fetched. The URL is given, and every fetch was on 2026-11-09.
- **[D]** derived: computed from local data or code (`file:line`, jsonl row, git commit) or by a script over fetched data. The method is stated.
- **[I]** inference: my reading. Nobody has tested it.
- **[UNVERIFIED]** could not be checked.

Pinned inputs:

| input | pin |
| --- | --- |
| wowsims/forever clone `/tmp/wowsims-forever` | `9ca4d977` (2026-11-09). `db.json` carries the items leg 1.60.1.70862 at hotfix push **113823** (`assets/db_inputs/spell_store_inputs.json` → `Builds.items` / `Hotfixes.items`). |
| `mythicsim-forever-engine` | `ff6a43cf` (2026-11-10). `data/manifest.json` `client_build` is still **1.60.1.70425**. `items.jsonl` (12,042 rows), `consumables.jsonl` (106) and `enchants.jsonl` (260) are the files `gen_item_data.py` reads. |
| our overlay `tools/overrides_70790.json` | items leg 70862 @ push **113763**, which is 60 pushes behind the clone. |

---

## 0. Bottom line (ranked)

1. **[D] Exactly three tracked on-use rows are wrong today: Adaptive Combat Assistant 272437, Weakness Analyzer 272438 and Serenity Field 272439.**
   - Our `Items.lua` has `cooldownMs = 90000` on all three (`Items.lua:46`, `:275`, `:233`).
   - The live rows are **300000 / 360000 / 360000**.
   - Blizzard's Forever tooltips agree [V] (§1.1).
   - The change entered wowsims `db.json` in commit `28a13349` (2026-11-08 02:33 UTC, "items … hotfixes as of 2026-11-08"). It is not in Blizzard's Nov 5 or Nov 6 hotfix notes.
   - It is an ItemEffect row hotfix. It never appears in the spell store, which is why wave M5's "707 of 707 equal, 0 deltas" (`data-diff-live-2026-11-07.md` §4) was true for the spell store but missed it.
   - It also post-dates push 113763, the last push our overlay stamps.
2. **[D] The ICD audit in `gen_item_data.py:50-52` and `:497-499` ("7 of the 51 rows have a store row, all 0, so the store confirms NONE") is wrong. It joined on the wrong id.**
   - With the join on the aura id named in `buffName` (`"Sear (1291568)"`), the store's `AuraOptions.ICDMs` equals our `icdMs` on **22 of the 51** emitted rows.
   - It contradicts none outright. One row, Orb of Fire (our 8000), reads `ICDMs 0` on both of its aura ids, but the Firebolt spell it triggers carries `CategoryCooldownMs 8000`.
   - The 22 rows are Searing Dagger, Firebelcher, Force of Will, Hand of Justice, Argent Defender, Mark of the Chosen, Darkspear, Guardian's Dualblade, both Grand-* enchants, and others (§1.2).
   - Counting the live tooltips too, **44 of the 51 rows are confirmed**, 6 rows are on items Wowhead 404s, and 1 (Orb of Fire) is ambiguous.
   - The generator's `buff_id` is often the *damage spell* the aura triggers, and that spell has no `AuraOptions` row.
3. **[D] 33 of the 51 ICD rows are sub-second debounces (10 ms, 100 ms or 200 ms), not cooldowns.**
   - Searing Dagger's tooltip reads "(10ms cooldown)" [V].
   - A proc-window bar sized from `icdMs = 10` is meaningless (§1.3).
   - 205 of the 400 item proc rows also have no `durationMs`. They are instant-effect procs with nothing to see on a buff bar.
4. **[D] The generator's consumable leg is mythicsim's 106-row sim list, not the live game.**
   - It omits **104 live consumables** (§3.2). 101 show a cooldown line in their Forever tooltip; the other 3 (Mark of the Dawn) have a 1.5 s item cooldown.
   - The omitted rows include every Healthstone except Major (`5509-5512`, `19004-19013`), 23 healing/mana/protection potions, 4 Draughts, and 43 engineering explosives plus Goblin Sapper Charge.
   - Hearthstone is in no dataset at all.
5. **[D][V] 11 on-use items are live and invisible to us** (§2), plus Forever-only potion and elixir reissues (§3.2). Six are in wowsims `db.json` (Serpentbane Crown, Theka's Last Breath, Emblem of Slamming, Behemoth Bones, Flamebreak Talisman, Scalding Flamehoof). The other five trinkets/belts (Shen'dralar Relic, Lucky Shovelnose Tuft, Sand-Covered Silk Sash, Escape Plan, Benediction/Anathema) are only in Wowhead tooltips.
6. **[D] Decoys that the lowest-id `ByName` rule picks wrongly** (§4): `Insignia of the Horde/Alliance` (16 rows each, 5 different buffs, picks the Warrior row), `Fist of Stone` (picks a row with no drop source [I]), `ProcsByBuffName["Lightning Bolt (13959)"]` (4 items), and the Druid `Abolish Poison 14253` ↔ Black Husk Shield `buffId 14253` id clash.
7. **[D] Not found / not applicable:**
   - **"Boot Knife" is a Rogue talent.** It is not an item row in any source.
   - **No item named "Warband…" exists** in `items.jsonl`, `forever-live-items.jsonl`, wowsims `db.json` or `leftover_db.json`. Zero hits.
   - The **Alterac Valley off-hands and shields** carry stats only. Their 7 rows (`19308-19312`, `19315`, `19321`) have no `item_effects`, so there is nothing to patch.

---

## 1. Changed rows: cooldown, duration, ICD, proc rate

### 1.1 Method, and the three cooldown deltas

What the generator reads **[D]** (`gen_item_data.py:189-300`): only `mythicsim/data/{items,enchants,consumables}.jsonl` pinned at 70425, plus the overlay's `_meta` for the header. The overlay applies **no item values**. Selection is "every item effect with `on_use` or `proc`", with no list. So "what is tracked" is not a config file: it is whatever mythicsim's 70425 rows contain. That is why the only fix points are constants in `gen_item_data.py` or a new list (see "Proposed patch").

Cross-source comparison **[D]**. I joined mythicsim `items.jsonl` (the generator input) to wowsims `db.json` (`itemEffects`, snake-cased) on item id. The consumed fields were effect kind, `buff_id`, `effect_duration_ms`, `max_cumulative_stacks`, on-use `cooldown_ms` / `category_id` / `category_cooldown_ms`, and proc `icd_ms`. I made no filters beyond the join:

| result | count |
| --- | --- |
| item ids in both sources | 6,443 (db rows 6,727, of which 284 are not in `items.jsonl`) |
| effect-bearing rows identical in every field, proc rate included | 615 |
| rows differing anywhere | 102: **8** in a field the generator consumes, 94 in proc-rate representation only (§1.4) |
| base effect-bearing items absent from `db.json` | 391 (nothing to say about them; absence is not evidence they are dead, because wowsims drops items below its item-effect floor and phase-filters) |

The 8 differences:

| id | name | base (70425) | live (113823) | on `Items.lua` / `Procs.lua`? |
| --- | --- | --- | --- | --- |
| 272437 | Adaptive Combat Assistant | cd 90000 | **cd 300000** (cat 1141, category cd 15000 ms unchanged) | wrong, `Items.lua:46` |
| 272438 | Weakness Analyzer | cd 90000 | **cd 360000** (cat 1141, 20000) | wrong, `Items.lua:275` |
| 272439 | Serenity Field | cd 90000 | **cd 360000** (cat 1141, 15000) | wrong, `Items.lua:233` |
| 7726 | Aegis of the Scarlet Commander | passive (no `on_use`/`proc`) | `proc` | dropped, see §4 |
| 17943 | Fist of Stone (the second row) | passive | `proc` | dropped, see §4 |
| 23004 | Idol of Longevity | passive | `proc` | dropped |
| 23005 | Totem of Flowing Water | passive | `proc` | dropped |
| 273293 | Bandsaw Wristbands | passive | `proc` | dropped |

(That makes 3 cooldown deltas plus 5 "passive → proc" kind changes. The 5 rows are on-block damage or mana-refund procs with no player-side aura.)

**When the three cooldowns moved [D].** I loaded `db.json` at four commits (`git show <c>:assets/database/db.json`):

| commit | date (UTC) | 272437 / 272438 / 272439 |
| --- | --- | --- |
| `aba7dff3` | 2026-11-07 18:52 | 90000 / 90000 / 90000 |
| **`28a13349`** | **2026-11-08 02:33** | **300000 / 360000 / 360000** |
| `340078e3` | 2026-11-08 10:47 (push 113791) | same |
| `57131830` | 2026-11-08 17:10 | same |

**Live confirmation [V].** Wowhead Forever tooltips (`https://nether.wowhead.com/forever/tooltip/item/<id>`, fetched 2026-11-09):

- 272437: "Use: Absorbs 450 damage for 15 sec. … (5 Min Cooldown)"
- 272438: "Use: Increases your critical strike chance with all spells and attacks by 5% for 20 sec or until you deal a non-periodic critical effect. (6 Min Cooldown)"
- 272439: "Use: Increases Spirit by 72 for 15 sec. (6 Min Cooldown)"

The fourth member of the family, Defender's Grip Stabilizer 272440, is already `cooldownMs = 360000` in `Items.lua:78`. The three outliers match their sibling.

**Whole-list check [V][D].** I fetched the tooltip for all 238 emitted on-use items and parsed the `(… Cooldown)` text against `cooldownMs`:

| outcome | count |
| --- | --- |
| equal | 224 (218 parsed automatically, 6 more read by hand where the tooltip says "1 Hour" or "1 Min, 30 Sec") |
| differ | **3** (the three above) |
| cannot verify | 11: 8 not on Wowhead Forever (12532 Spire of the Stoneshaper, 13143 Mark of the Dragon Lord, 13353 Book of the Dead, 17067 Ancient Cornerstone Grimoire, 18047 Flame Walkers, 18340 Eidolon Talisman, 18370 Vigilance Charm, 18438 Sergeant's Mark); 2 with an unread format (7133 Brutal Hauberk, 10721 Gnomish Harm Prevention Belt, both 3600000); 1 charge item (5387 Enchanted Moonstalker Cloak, "1 Charge", data 1000) |

Single-source caveat **[I]**: Wowhead's tooltip is a third-party render of the client's data, and wowsims is derived from raidbots' `DBCache.bin`. They agree with each other on all three rows, but neither is Blizzard's own page.

**Other cooldown, duration and category values [D].**

- Stores across the week: I diffed `spell_store_inputs.json` at `a67d2e58` (11-04), `84c7e1d4` (11-05), `4b71eb02` (11-06), `90d7ff43` (11-07), `57131830` (11-08) and `16deb502` (11-09). In every step `Cooldowns`, `Categories`, `AuraOptions` and `Misc.DurationMs` had **0 changed rows and only additions**. That finishes the "spell store carries no item deltas" half of M5.
- Consumables: 96 ids are in both `consumables.jsonl` and `db.json`. **0** differ in cooldown, category cooldown or category id.
- Consumable tooltips: all **73** emitted consumables whose tooltip I could fetch match `max(cooldownMs, categoryCooldownMs)` [V].
- Consumable durations: the generator emits only `buff_duration`. I did not diff it against the live store (wave M5 found no deltas, `data-diff-live-2026-11-07.md` §4).

### 1.2 Proc ICDs: the audit's join key was wrong

Method **[D]**. Of the 405 proc rows (400 item + 5 enchant), 51 carry `icd_ms` (49 + 2). I joined each to the current store's `AuraOptions` two ways:

| join key | rows with an `AuraOptions` row | non-zero `ICDMs` | rows equal to our `icdMs` |
| --- | --- | --- | --- |
| `buff_id` (what the header describes) | 9 of the 51 | **0** | 0 |
| the id in `buffName` parentheses | 187 of 405 | **22** | **22 of 51** |

The first line reproduces the shipped claim (all zeros). The second line is the correct join: **Searing Dagger** has `buffId 1291570` (the 7-damage "Sear" spell, no aura row) and `buffName "Sear (1291568)"`. The aura `1291568` carries `{ProcChance: 100, ICDMs: 10, ProcFlags [65536,0]}`, and `1291570` is a spell with `Misc.DurationMs 0`.

Of the 22 agreeing rows, 20 sit on items whose tooltip states the same number [V]. The two exceptions are the Unbalanced Idol rows (210195): the store says 1000, the tooltip shows no cooldown line.

The 51 ICD rows sit on 37 items (the ten Signet Rings account for 20 rows). I fetched all 37 tooltips: **29 state exactly our `icdMs`** (including the Signet Rings, Blade of Eternal Darkness and Mana Channeling Wand, which the store has no row for), 2 show no cooldown, and 6 return 404 [V]. Examples of the live text:

- Searing Dagger: "Equip: Harmful spell casts sear the target for 7 Fire damage. (10ms cooldown)"
- Zealot Plate (274651, not in our data): "(15s cooldown)"
- Hand of Justice: "Proc chance: 3%, 2s cooldown"
- Signet Ring of the Bronze Dragonflight: "Proc chance: 8%, 200ms cooldown"

The remaining 22 rows break down as:

- **Unverified by tooltip: 6 items return 404** on Wowhead Forever: 9483 Flaming Incinerator, 11684 Ironfoe, 14557 The Lion Horn of Stormwind, 17064 Shard of the Scale, 17104 Spinal Reaper, 22332 Blade of Necromancy.
- **Orb of Fire 12805 is the one ambiguous row** (our `icdMs 8000`). Its tooltip reads "Grants a chance on striking the enemy for 50 to 70 Fire damage. (Proc chance: 1%)" with no cooldown, and `AuraOptions.ICDMs` is 0 on both ids. The 8000 comes from the Firebolt spell `13441`'s `CategoryCooldownMs 8000` in the store [D]. Mark it medium confidence.
- **Unbalanced Idol 210195** (`icdMs 1000`) is confirmed by the store (`AuraOptions.ICDMs 1000` on 424339 and 424336) but its tooltip shows no cooldown line. Keep it.

Rows by status: 22 confirmed by the store; 22 more confirmed by tooltip alone (Signet Rings 20, Blade of Eternal Darkness 1, Mana Channeling Wand 1); 6 unverifiable (404); 1 ambiguous (Orb of Fire).

[D] consequence for the files: the ICD header block in `Procs.lua` (from line 50) should read "22 of 51 rows confirmed by `AuraOptions.ICDMs` (joined on the aura id in `buffName`), 29 of 37 items confirmed by their live tooltip, 0 contradicted, 1 ambiguous (Orb of Fire)".

### 1.3 Searing Dagger and the Nov 6 hotfix

**[V]** Blizzard, `https://worldofwarcraft.blizzard.com/en-us/news/24315281/wow-forever-hotfixes-november-6-2026`, Items: "Searing Dagger is now only activated by spells that have a damaging component." That is the only item line in that hotfix list. The Nov 5 list's only item lines concern vendors and Mild Spices.

**[D]** No data row moved. Sear `1291568` / `1291570` is in the store with no changes across the six snapshots of §1.1. Mythicsim records the same: "the client rows are unchanged, so Forever's rules now leave out the casts with no damaging component" (commit `4808857e`, 2026-11-08; `tests/hotfix_20261106.rs`). The change is server-side.

**[I]** For FX this means a bar can no longer assume "any harmful cast procs it". There is nothing to retune in `Procs.lua`. The real problem is that the row is a window-less, 10 ms-ICD damage proc (`Procs.lua:372`), which no buff bar can show. See Proposed patch P5.

**Boot Knife [D].** A Rogue talent, not an item: the Nov 6 note reads "While Boot Knife is talented, Shank will now correctly display the number of Combo Points it grants." I found no item of that name in any source.

**Shank suppresses weapon procs [D].** Mythicsim commit `420dfe31` (Nov 6): "Shank's rows carry Suppress Weapon Procs (attributes 4, 0x800000; Wowhead Forever lists it on 1329549), so poisons, weapon enchants and chance on hit weapon effects no longer hear it." That changes how often weapon procs fire, not any value we store.

**Warband's Pendant-style weapon procs [D].** No item named Warband exists (see §0). The relevant "weapon proc" change this week is wowsims' **weapon proc-rate table** (below).

### 1.4 Proc rates (not emitted by the generator)

`gen_item_data.py` emits no proc chance or procs-per-minute, only `icdMs`. For completeness, the rate side moved like this **[D]**:

- wowsims `db.json` carries `proc.ppm` on **58** rows. mythicsim's 70425 rows carry no rate on 54 of those weapons (`proc: {}`) and `proc_chance: 1` on 4 (Hand of Edward the Odd 2243, Julie's Dagger 6660, Sword of Corruption 13032, Darkmoon Card: Heroism 19287; live ppm 1 / 1 / 1 / 2).
- 36 rows have `proc_chance: 1` in base and no rate in the live rows. That is a representation difference.
- Between Nov 5 and Nov 6: Killmaim 13016 gained `ppm 0.85`.
- At 70862 (2026-11-07): "Restore the proc rates of six weapons live at 70862" (`59a0409a`): Fiery War Axe 870, Nightblade 1982, Bow of Searing Arrows 2825, Ravager 7717, Serpent Slicer 13035 and Thrash Blade 17705.
- 2026-11-08: Flurry Axe 871 got its 1.9 ppm row back (`340078e3`).
- 2026-11-09 (push 113823): Gut Ripper 2164, Hand of Edward the Odd 2243, Sword of Zeal 6622, Cobalt Crusher 7730, Linken's Sword of Mastery 11902, Doombringer 13053 and The Needler 13060 came back "verbatim from before 0cfbbf7fe9" (`16deb502`).

**[I]** These are wowsims-side tables. The commits say they are restored to what the tables held before, and the game's own tooltips state no rate for these weapons. They are not game changes and cannot be read off a Forever page. Mythicsim's own rule for items with no stated rate is **1.8% × weapon speed** (`6469b36a`, an assumption documented in its README). If the owner wants a rate column later, emit `ppm` from `db.json` (P6), but today nothing consumes it.

**Alterac Valley off-hands and shields [D].** Mythicsim `7663ed97` (2026-11-06) updated their live stats: item level 65 → 60 and lower stat values (Tome of Arcane Domination, Tome of Shadow Force, Tome of the Ice Lord, Tome of Fiery Arcana, Lei of the Lifegiver, Therazane's Touch, The Immovable Object; Thanthaldis Snowgleam 13217 and Jekyll Flandring 13219 sell them). The 7 item rows have `item_effects: []` in both `items.jsonl` and `forever-live-items.jsonl`. No change for us.

**`forever-live-items.jsonl` (1,431 rows) and `forever-client-items.jsonl` (648 rows) [D].**

- All 1,431 live ids are also in `items.jsonl`. Of those 1,431 rows, 177 carry `item_effects`, and **0** of the 177 differ from `items.jsonl` in any effect field. The live file changes stats and set data only.
- The 648 client rows are not in `items.jsonl` and carry **no** `item_effects` field at all. The builder skips any item whose tooltip has an effect line (`tools/README.md`, `341ec298`: "any other effect … still leaves the item out"). So the on-use and proc items that Forever added are invisible to both files.

---

## 2. New on-use trinkets and items (live, not tracked)

Source: wowsims `db.json` at push 113823 (`itemEffects`) **[D]**. Wowhead tooltips (fetched 2026-11-09) confirm each cooldown **[V]**.

### 2.1 In wowsims `db.json`, not in `items.jsonl`

| id | name | slot | on-use cd | shared cat | cat cd | buff (aura id) | window | tooltip [V] |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 274609 | Serpentbane Crown | head, mail | 300000 | 1141 | 10000 | 1295039 | 10000 | "(5 Min Cooldown)" fire damage plus DoT |
| 274641 | Theka's Last Breath | trinket | 420000 | none | -1 | 1294617 | 10000 | "(7 Min Cooldown)" turns enemies into scarabs |
| 275009 | Emblem of Slamming | trinket | 900000 | **2585** | 900000 | 1315972 | 3000 | "(15 Min Cooldown)" stuns target and you |
| 280065 | Behemoth Bones | trinket | 300000 | **2554** | 20000 | 1315849 | none | "(5 Min Cooldown)" heals you and ally |
| 280071 | Flamebreak Talisman | trinket | 300000 | 1141 | 30000 | 1315878 | 30000 | "(5 Min Cooldown)" +33 agility |
| 280074 | Scalding Flamehoof | trinket | 300000 | **44** | 20000 | 1309551 | 20000 | "(5 Min Cooldown)" +14% fire damage taken, +14% speed |

First seen (wowsims `item_first_seen.json`): 275009 on 2026-11-06, 274609/274641 on 11-07, 280065/280071/280074 on 11-09. Behemoth Bones has no `durationMs` in the row, so its buff window is unknown (the tooltip is a heal, so there is nothing to show).

### 2.2 In Wowhead tooltips only (not in `db.json`; no buff id known)

Found by scanning wago.tools `Item` (`https://wago.tools/db2/Item/csv?product=wowf`, 32,007 rows; 4,631 with id ≥ 270000) for ids ≥ 260000 that are in none of `items.jsonl`, the client rows or `db.json`, then fetching their Wowhead Forever tooltips. Of 833 weapon/armor candidates 109 resolved; the rest return 404 and are **[UNVERIFIED]** (Wowhead has not decoded them yet).

| id | name | slot | on-use | tooltip [V] |
| --- | --- | --- | --- | --- |
| 277559 | Shen'dralar Relic | trinket | 420000 | "Dispel 1 beneficial magic effect from the target enemy and 1 additional magic effect every 4 sec for 8 sec. (7 Min Cooldown)" |
| 280060 | Lucky Shovelnose Tuft | trinket | 300000 | "Increases your chance to Dodge by 5% for 15 sec. (5 Min Cooldown)" |
| 286612 | Sand-Covered Silk Sash | belt | 1800000 | "Removes existing Immobilizing effects and makes you immune … for 5 sec. (30 Min Cooldown)" |
| 287026 | Escape Plan | ranged | 900000 | "Disarm target's weapon for 10 sec. (15 Min Cooldown)" |
| 289296 / 289297 | Benediction / Anathema | staff | 60000 | "Calls forth Anathema / Benediction. (1 Min Cooldown)" (the staff swap) |

Chance-on-hit weapons that are new and not in the base rows: Lightcrest Hammer 276419, Claymore of Two Moons 280080 ("Your attacks have a chance to Wax, dealing 189 Arcane damage or Wane, granting 40 Strength for 10 sec."), Ankle Slicers 284587, and the Forever copies of Thunderfury 289294 and Sulfuras 289295. The buff ids are unknown **[UNVERIFIED]**, and `db.json` has no ICD for them.

New procs that are in `db.json` (38 new rows with effects in all; the ones that matter): Maw of Min'loth 274608 (off-hand, "10% chance, 3s cooldown", Fatal Bite; **[V]** tooltip: "When struck in melee combat, has a 10% chance of stealing 40 life … (Proc chance: 10%, 3s cooldown)"), Zealot Plate 274651 (energize, ICD 15000, **[V]**), Farraki Kris 274647 (ICD 100 ms, **[V]**), and Girdle of Extracted Answers 276742 (on-block damage).

### 2.3 Shared-category lockouts (what the bar does not show)

`gen_item_data.py` emits `categoryId` / `categoryCooldownMs` for consumables but **not for item on-use rows** (`gen_item_data.py:235-250`; the docstring line 30 says "NOT emitted"). The source has the fields on **181 of 238** on-use rows **[D]**. Using one item locks every item in its category for that many ms, so a trinket B bar would not show the 10-30 s lock that trinket A started. Live categories among the 207 on-use item rows in `db.json` **[D]**:

| category | items | lockout (ms) | what it is |
| --- | --- | --- | --- |
| 1141 | 47 | 10000 / 15000 / 20000 / 30000 | general "use trinket" family |
| 2554 | 13 | 10000 / 15000 / 20000 / 30000 / 60000 | second trinket family |
| 1155 | 8 | 180000 | PvP trinkets (Talisman of Arathor, Defiler's Talisman) |
| 1153 | 4 | 60000 / 120000 | Ankh of Life, Major Recombobulator, Diamond Flask, Mark of the Red Flight |
| 94 | 4 | 20000 / 60000 | Barov Peasant Caller, Arcanite Dragonling, Defender of the Timbermaw/Barkskin |
| 44 | 3 | 10000 / 20000 | Nifty Stopwatch, Mirage Mirror, Scalding Flamehoof |
| 2466 / 2467 | 3 + 3 | 900000-1800000 / 14400000 | Olaf's Shield, Parachute Cloak, Rusty Propeller Blade / Dimensional Ripper-style transporters |
| 2585 | 1 | 900000 | Emblem of Slamming |

Only 114 of 207 rows have no category at all.

---

## 3. Consumables, flasks/elixirs, enchants and engineering

### 3.1 What the generator emits

79 consumable rows (`Items.lua`, `consumables`), 5 enchant proc rows (`enchantProcs`: 1900 Crusader, 7940 Grand Crusader, 7941 Grand Arcanist, 7942 Grand Sorcerer, 7943 Grand Inquisitor). The source is mythicsim `consumables.jsonl` (106 rows; the 27 with no cooldown are skipped) and `enchants.jsonl` (260 rows; only 5 carry `enchant_effects`).

### 3.2 Omitted live consumables with a cooldown (the "players track these" set)

I fetched the Wowhead tooltip of every `db.json` consumable that is not in `Items.lua` and whose `onUse` has category 4, 24, 1153, 28 or 133, or a cooldown above 1 s. I fetched the tooltip of each of the **104** resulting ids: all 104 resolve on Wowhead Forever, and **101** show a cooldown line [V]. The other 3 are Mark of the Dawn (item cooldown 1.5 s, no line). Grouped by category (ids from `db.json`):

| category / cd | count | what | ids |
| --- | --- | --- | --- |
| 4 / 120000 | 23 | healing, mana, protection, rejuvenation potions | 118, 858, 929, 2455, 2456, 3384, 3385, 6048-6052, 9144, 14894, 18839, 18841, 255663, 268881-268883, 274935, 282011, 282013 |
| 4 / 120000 (item cd -1) | 2 | Full Moonshine, Mug of Shimmer Stout | 1072, 3087 |
| 4 / 300000 | 4 | Major/Superior Healing and Mana Draughts | 17348, 17349, 17351, 17352 |
| 1153 / 120000 | 22 | **Healthstones (all ranks, both id families), Mana Jade/Citrine/Ruby, Tea with Sugar** | 1703, 5509-5513, 8007, 8008, 11951, 11952, 15723, 17747, 19004-19013 |
| 1153 / 120000 (item cd -1) | 1 | Fishliver Oil | 1322 |
| 24 / 60000 | 43 | **engineering explosives** (Iron Grenade 4390, Thorium Grenade 15993, Dark Iron Bomb 16005, Dense Dynamite 18641, The Big One 10586, Hi-Explosive Bomb 10562 …) | 1178, 1399, 1402, 4358, 4360, 4365, 4370, 4374, 4378, 4380, 4390, 4394, 4403, 4598, 5013, 6714, 10507, 10514, 10562, 10586, 10830, 11566, 13180, 15993, 16005, 18588, 18641, 22151, 215168, 260792, 260793, 260795, 260797, 260798, 260803, 260805, 260809, 260814, 260816, 260817, 276145, 277499, 284868 |
| 24 / 60000 + item cd 300000 | 1 | Goblin Sapper Charge | 10646 |
| 24 / 120000 | 1 | Flash Bundle | 1127 |
| 28 / 300000 | 1 | Swiftfeather Token | 1400 |
| none / 900000 | 2 | Flame Deflector, Ice Deflector | 4376, 4386 |
| none / 60000 + item cd 60000 | 1 | Distilled Firewater | 246948 |
| item cd 1500 | 3 | Mark of the Dawn (3 ranks) | 23194, 23195, 23196 |

(Row sizes are `db.json` rows I grouped by `(categoryId, categoryCooldownMs, cooldownMs)`; the totals are 43 + 23 + 22 + 4 + 3 + 2 + 2 + 1 + 1 + 1 + 1 + 1 = 104. The 43-id explosives list printed by the script has 43 entries.)

Tooltip spot-checks [V]: Healthstone 5509 "Use: Instantly restores 600 life. (2 Min Cooldown)"; Minor Healthstone 19004 "(2 Min Cooldown)". All 73 *emitted* consumables whose tooltip I fetched agree with `Items.lua` (§1.1).

**Forever-only reissues [V].** These are in no dataset. Each carries a 2-minute potion cooldown on its tooltip, with a Classic name that already exists under another id (decoys, §4):

- 287966 Minor Healing Potion, 287967 Lesser Healing Potion, 287977 Greater Healing Potion, 288896 Superior Healing Potion
- 287968 Minor Mana Potion, 287969 Lesser Mana Potion, 288897 Superior Mana Potion
- 287975 / 288898 Swiftness Potion, 287976 Free Action Potion
- The "Endless" elixirs, 3 s shared potion lockout, 1 h duration, "This effect stacks up to 5 times": 289082 Intellect, 289083 Power, 289084 Healing, 289086 Rapidity, 289087 Opportunity, 289321 Mana, 289329 Growth, 289334 Experience; scrolls 289088 Fortitude, 289330 Speed; 289081 Noggenfogger Elixir
- Engineering: 260818 EZ-Thro Mana Bomb (1 Min), 260827 Stealthman 52 (5 Min), 260800 Shafety Sheep (1 Min), 260822 Ultrasafe Rechargeable Battery (1 Min), 260825 Ultralight Goblin Glider (5 Min), 260823 Dimensional Transporter - Mt. Hyjal (4 Hrs), 260819 / 260820 / 260821 field transporters (cat 2467, 4 Hrs)
- Camping system: 1 hour shared cooldown on all camp features (e.g. 279943-279990)

Categories for the reissues are **[UNVERIFIED]**: they are not in `db.json`, and a tooltip does not show a category id.

### 3.3 Weapon enchants

`enchants.jsonl` has `enchant_effects` on 5 rows. In `db.json` and the shipped Forever tooltips these enchants exist too, but mythicsim carries no effect rows for them, so the generator drops them **[D]**:

| effect id | name | what [D] |
| --- | --- | --- |
| 803 | Fiery Weapon | damage proc (spell 13897), no aura |
| 912 | Demonslaying | damage + stun (13907), demons only |
| 1894 | Icy Chill | debuff on the target (20005, 5 s) |
| 1898 | Lifestealing | life steal (20004), no aura |
| 1899 | Unholy Weapon | spell 20006 "Unholy Curse", store `Misc.DurationMs 12000` |

Wowsims comments say these "state no rate" (`sim/common/forever/enchants_auto_gen.go:12-63`), which is why neither side models them. Only Unholy Weapon has a duration that could be a self-buff window **[I]**; that is unconfirmed (the store row's school is Shadow with a range, which looks like a debuff on the target). Treat as open (Q4).

The Forever scroll `273564 Enchant Weapon - Lifestealing` (tooltip "to often steal life from the enemy") confirms Lifestealing exists live [V].

### 3.4 Hearthstone

No row anywhere carries a cooldown **[D][V]**: item 6948 has no `item_effects` in `items.jsonl` or `db.json`; the store has two name-only `Hearthstone` spells (1303762, 1315212) with no `Cooldowns` row; the Wowhead tooltip (`https://nether.wowhead.com/forever/tooltip/item/6948`) reads "Use: Returns you to Hearthstone Location. Speak to an Innkeeper in a different place to change your home location." with no cooldown line. A bar for it needs an in-client probe (`C_Container.GetItemCooldown`), not data. The Hearthstone-like items we do have are Dimensional Ripper - Everlook 18984 and SAF-T Emergency Ripper: Everlook 260820 (cat 2467, 14400000, same buff 23442; the SAF-T copy has "3 Charges").

---

## 4. Same-name decoys the generator can pick wrongly

`by_name_keyed` (`gen_item_data.py:171`) keeps the **lowest item id** per name. The header lists 15 name collisions in `Items.lua:19-34`. The ones that matter, with the rows **[D]**:

| name | rows | what goes wrong |
| --- | --- | --- |
| **Insignia of the Horde / Alliance** | 16 rows each (18834-18853 + 209619-209626; 18854-18864 + 209611-209618), one per class | The effect differs per class: buff 5579 (Root/Snare/Stun, Warrior/Hunter/Shaman), 23273 (Charm/Fear/Polymorph, Rogue/Warlock), 23274 (Mage), 23276 (Priest/Paladin), 23277 (Druid). `OnUseByName` resolves to the **Warrior** row (18834 / 18854) with buff 5579 for every class. All rows share `cooldownMs 300000` and carry a `classAllowlist`. |
| **Fist of Stone** | 17733 (emitted, buff 21951) vs 17943 (droppable mace, buff 1294794, passive in base, so **dropped**) | `ProcsByName["Fist of Stone"]` is 17733 (`Procs.lua:221`), a row whose tooltip lists no drop source. The live droppable item is 17943 ("Chance on hit to restore 32 mana", dropped by Landslide, 37.06%) [V]. The tooltip of 17733 reads the same but has no "Dropped by" line; I could not find 17733 in `db.json` or `leftover_db.json`, so I treat it as an orphan row **[I]**. |
| **Earthshaker** | 17073 (ilvl 66, Magmadar) vs 288900 (new, BoE ilvl 30) | Both carry buff 21152 / 3 s knockdown [V]. `ByName` takes 17073 and the other is never seen. Harmless for the bar but the slot/ilvl text differs. |
| **Grand Marshal's Aegis / High Warlord's Shield Wall** | 18825 / 18826 (5% proc) vs 234588 / 234562 (20% proc, plus passive "Unflinching Morale") | The 234xxx rows say "Added in Season of Discovery. May not be in WoW: Forever." [V]. `ByName` takes the 5% rows, which is the Forever-plausible pick (**[I]**, tooltip text only). |
| **`ProcsByBuffName["Lightning Bolt (13959)"]`** | Grand Marshal's Aegis, High Warlord's Shield Wall, Premier Grand Marshal's Aegis 272838, Premier High Warlord's Shield Wall 272591 | `ProcsByBuffName` keeps the first. The generator prints these in its report but not in the file header. **22 buff names collide across different item names**: `Shadow Bolt (18211)` (Doombringer, Ebon Hand, Nightblade), `Frostbolt (13439)` (3 items), `Building Inspiration (413338)` (5 Icons), `Rend (13318)`, `Poison (17511)` and others. |
| **Signet Ring of the Bronze Dragonflight** | 10 effect rows (234017 …) vs 15 Classic rings (21196-21210) and other passive Forever siblings with no effect | Only the 10 effect rows are emitted; the lookup returns 234017. |
| **Minor/Lesser/Healing/Mana potions** (§3.2) | Classic 118, 858, 929, 2455, 3385 vs Forever reissue 287966-287977, 288896-288898 | If these are ever added, `ByName` picks the Classic id. Same cooldown, so only the id differs. |
| **Healthstones** | Minor ×3 (5512, 19004, 19005), Lesser ×3, Healthstone ×3, Greater ×3, Major ×3 | Only Major 9421 is emitted. The two id families (5509-5513 vs 19004-19013) share cooldown 120000 and category 1153; why there are two families is **[UNVERIFIED]**. |
| **Barov Peasant Caller** | 14022 (buff 18307), 14023 (buff 18308) | Faction variants. Lowest-id pick is arbitrary. |
| **Defiler's Talisman / Talisman of Arathor** | 4 ranks each, buffs 23991 / 25746 / 25747 / 25750 | Same cooldown (180000), different absorb ids. |

**Id clashes with the spell side [D].** I checked every item `buffId` and parenthesised aura id against the class files in `addon/Forte_*/Data/`:

| item | buff id | clashes with |
| --- | --- | --- |
| Black Husk Shield 4444 (on-use) | 14253 "Abolish Poison" | Druid `Abolish Poison` (the 70790 refresh moved the Druid row 2893 → 14253, `data-diff-live-2026-11-07.md` "Answer first", item 1) |
| Archeus 2000 | 18091 "Arcane Blast" | Mage `Arcane Blast` pick 18091 (the postlaunch doc's §0 item 2) |
| Cursed Felblade 14145 | 18381 "Cripple" | Warrior `Cripple` |
| Howling Blade 6331 | 13490 | Warrior |
| Nightfall 19169 | 23605 "Spell Vulnerability" | Warrior |
| Searing Needle 12531 | 16454 "Searing Blast" | Mage |
| Thrash Blade 17705 | 21919 "Thrash" | Druid |
| Dark Edge of Insanity 21134 | 26108 | Rogue |
| Abyss Shard 20534 (on-use) | 25112 "Summon Voidwalker" | Warlock |
| Arcane Infused Gem 19336, Hazza'rah's Charm of Destruction 19957, Wushoolay's Charm of Spirits 19956 | 23721, 24543, 24499 | Hunter / Warlock / Shaman |
| Darkmoon Card: Heroism 19287 | aura 23689 "Heroism" | Shaman `Heroism` |

**[I]** Any code that maps an incoming spell id or aura to "item vs class spell" by id or name alone can mis-attribute these. This matters for the Arcane Blast pick and the Druid `Abolish Poison` row.

---

## 5. Item rows the generator drops that matter

| # | what | why dropped | matters? |
| --- | --- | --- | --- |
| 1 | the 104 live consumables with cooldowns (§3.2) | the consumable leg reads mythicsim's sim list (106 rows) | **yes**: Healthstones, potions, explosives are the most-used cooldown-bar items |
| 2 | 6 + 5 new on-use items (§2) | not in 70425 base; client rows carry no effects | **yes** (trinkets) |
| 3 | the 3 stale cooldowns (§1.1) | not dropped, wrong value | **yes** |
| 4 | Fist of Stone 17943 | base row has no `proc` key | yes for mana-proc melee; medium |
| 5 | Aegis of the Scarlet Commander 7726, Idol of Longevity 23004, Totem of Flowing Water 23005, Bandsaw Wristbands 273293 | passive in base, `proc` live | low: block-damage / mana-refund procs with no aura |
| 6 | weapon enchants 803, 912, 1894, 1898, 1899 | `enchants.jsonl` has no effects | low-medium; 1899 Unholy Weapon only if it has a self buff |
| 7 | shared lockout categories on item on-use rows (181 of 238 carry them) | `entry_fields` skips them for items | **yes** for trinket/PvP-trinket bars |
| 8 | Hearthstone | no item effect, no store cooldown | needs an in-client probe |
| 9 | procs with no `durationMs` (205 of 400) | emitted as `buff-window` with no window | design call, see P5 |

---

## 6. Evidence quality

- **Sample / out-of-sample:** not applicable. These are point-in-time game data, not backtests.
- **Single points of failure:**
  - Everything about the live game rests on three third-party renderings: wowsims `db.json` (raidbots `DBCache.bin` at push 113823), wago.tools `Item`, and Wowhead Forever tooltips. They agree on all three cooldown deltas and on all 29 checkable ICDs. I did not reach Blizzard's own client.
  - The 404 sets (8 on-use items, 6 ICD items) are **not evidence of absence**. Wowhead "Entity not found" means Wowhead has not decoded the id.
- **Replication:** mythicsim's live-audit commits (`4808857e`, `7663ed97`, `75d543f3`, `3a1bb052`) and wowsims' hotfix commits independently track the same Nov 6-9 changes. Neither source lists the three cooldown changes. They are visible only in wowsims `db.json` history.
- **Costs / data cost:** none. All fetches were free public endpoints.
- **"Reported" vs "independently replicated":** the three cooldowns are *reported* by wowsims (derived from raidbots) and *independently replicated* by Wowhead's tooltips.

---

## Implications for our setup

1. **`gen_item_data.py` is pinned to a 70425 dataset that mythicsim has not refreshed.** `manifest.json client_build` is 70425. Mythicsim's data `items.jsonl` has not moved since the base pull. The three wrong cooldowns will persist until either mythicsim re-extracts, or we overlay from wowsims `db.json`.
2. **The right source for the item leg is wowsims `db.json`, not the spell store.** The spell store never changed an item value this week (0 changed rows across 6 snapshots). Item rows change via hotfixed ItemEffect rows, which only show up in `db.json`. `extract_store.py` has no item section.
3. **Wave M5's "item leg unchanged" finding needs a footnote.** It was true of the spell store and wrong for ItemEffect cooldowns.
4. **The ICD "launch-day probe" framing can retire for 22 of 51 rows.** The store and the tooltips agree. Tooltips confirm 22 more rows (29 of 37 items overall); 6 rows are unverifiable and only Orb of Fire is ambiguous.
5. **A proc bar should not light for sub-second ICDs.** 33 of 51 rows are debounces. For those, `icdMs` is a duplicate-suppression number, not a window length.
6. **The consumable list is the largest data gap for "cooldown bar" users.** 104 live consumables with tooltips are absent, and Forever's reissued potions (287966 onward) use new ids under old names.
7. **ByName needs class awareness for the PvP Insignia rows.** Otherwise a Hunter gets the Warrior row (same buff 5579 only by coincidence).

## Open questions

- **Q1.** Does `Forte_Cooldown/Core/Procs.lua` read `icdMs` for window sizing, as `Procs.lua`'s header says? I did not read that file. If it clamps or ignores sub-second values already, P5 is moot.
- **Q2.** What categories do the Forever potion reissues (287966-288898) and the "Endless" elixirs use? Not in `db.json`; tooltips do not show category ids. Needs an in-client `GetItemSpell` / `GetItemCooldown` probe.
- **Q3.** Is the 5/6/6 min change on the three Undermine trinkets deliberate? Blizzard's Nov 5/6 notes do not mention it. The tooltip is the only live evidence.
- **Q4.** Is Unholy Weapon's `20006` a self buff or a target debuff on Forever? The store row (shadow school, range 30, cast time 1000) reads like a debuff. Probe with `C_UnitAuras` out of combat.
- **Q5.** Orb of Fire's 8000 ms ICD is not in its tooltip and `AuraOptions.ICDMs` is 0. Keep (it matches the spell's category cooldown) or drop to 0?
- **Q6.** Do mythicsim's Healthstone/mana-gem rules (category 1153 shared with Demonic Rune, commit `7c710305`) match what we want on a bar? A Healthstone bar would also show the mana-gem lockout.
- **Q7.** Is `Forte_Items` expected to resolve an item by name or by id at runtime? If by name, P4 matters; if by id, only the data needs fixing.

---

## Proposed patch

Selection is not driven by a list today. The generator takes every `on_use`/`proc` row in mythicsim's 70425 files (`gen_item_data.py:189-300`), and the consumable leg takes every row of `consumables.jsonl` that has a cooldown (`:300-325`). The smallest mechanical change is one new config file and one load step:

- Add **`tools/item_lists/live_items.json`** (new), read by `gen_item_data.py` next to `LIVE_OVERLAY`. Keys below.
- In `gen_item_data.py`: after the on-use loop apply `onUseOverride`, append `onUseAdd` rows, apply `consumablesAdd` rows, and emit the extra `ByName` rows. Names come from the row; the ids are listed here because they are the datum.
- Header: replace the ICD claim at `gen_item_data.py:50-52` and `:497-499` (P1).

Confidence: **high** = db.json and tooltip agree; **med** = one source or inferred; **low** = guess.

### P1. Fix the ICD audit text (docs only; high)

`gen_item_data.py:50-52` and `:497-499`: "AuraOptions.ICDMs, joined on the aura id in `buffName`'s parentheses, equals `icdMs` on 22 of the 51 rows and contradicts none; 29 of 37 ICD items match their live tooltip; ambiguous: Orb of Fire 12805; 6 items not on Wowhead." The old join (`buff_id`) found 9 rows, all 0.

### P2. Cooldown overrides (new `onUseOverride`; high)

```json
"onUseOverride": {
  "272437": { "cooldownMs": 300000, "_conf": "high", "_why": "db.json 28a13349 + Wowhead tooltip '(5 Min Cooldown)'" },
  "272438": { "cooldownMs": 360000, "_conf": "high", "_why": "db.json 28a13349 + Wowhead tooltip '(6 Min Cooldown)'" },
  "272439": { "cooldownMs": 360000, "_conf": "high", "_why": "db.json 28a13349 + Wowhead tooltip '(6 Min Cooldown)'; sibling 272440 already 360000" }
}
```

### P3. New on-use rows (new `onUseAdd`; high for the first six, medium for the rest)

Field names follow `entry_fields`. `source` is `"item"`, `trackable` is `"cooldown"`.

```json
"onUseAdd": [
  { "itemId": 274609, "name": "Serpentbane Crown", "cooldownMs": 300000, "categoryId": 1141, "categoryCooldownMs": 10000, "buffId": 1295039, "buffName": "Serpentbane (1295039)", "durationMs": 10000, "slotType": "ItemTypeHead / ArmorTypeMail", "_conf": "high", "_why": "db.json 113823 + tooltip '5 Min'" },
  { "itemId": 274641, "name": "Theka's Last Breath", "cooldownMs": 420000, "buffId": 1294617, "buffName": "Theka's Last Breath (1294617)", "durationMs": 10000, "slotType": "ItemTypeTrinket", "_conf": "high", "_why": "db.json + tooltip '7 Min'; categoryCooldownMs -1 omitted" },
  { "itemId": 275009, "name": "Emblem of Slamming", "cooldownMs": 900000, "categoryId": 2585, "categoryCooldownMs": 900000, "buffId": 1315972, "buffName": "Slammed (1315972)", "durationMs": 3000, "slotType": "ItemTypeTrinket", "_conf": "high", "_why": "db.json + tooltip '15 Min'" },
  { "itemId": 280065, "name": "Behemoth Bones", "cooldownMs": 300000, "categoryId": 2554, "categoryCooldownMs": 20000, "buffId": 1315849, "buffName": "Behemoth Bone (1315849)", "slotType": "ItemTypeTrinket", "_conf": "high", "_why": "db.json + tooltip '5 Min'; no duration in row" },
  { "itemId": 280071, "name": "Flamebreak Talisman", "cooldownMs": 300000, "categoryId": 1141, "categoryCooldownMs": 30000, "buffId": 1315878, "buffName": "Flamebreak Talisman (1315878)", "durationMs": 30000, "slotType": "ItemTypeTrinket", "_conf": "high", "_why": "db.json + tooltip '5 Min'" },
  { "itemId": 280074, "name": "Scalding Flamehoof", "cooldownMs": 300000, "categoryId": 44, "categoryCooldownMs": 20000, "buffId": 1309551, "buffName": "Scalding Flamehoof (1309551)", "durationMs": 20000, "slotType": "ItemTypeTrinket", "_conf": "high", "_why": "db.json + tooltip '5 Min'" },
  { "itemId": 277559, "name": "Shen'dralar Relic", "cooldownMs": 420000, "durationMs": 8000, "slotType": "ItemTypeTrinket", "_conf": "med", "_why": "tooltip only, no buff id" },
  { "itemId": 280060, "name": "Lucky Shovelnose Tuft", "cooldownMs": 300000, "durationMs": 15000, "slotType": "ItemTypeTrinket", "_conf": "med", "_why": "tooltip only, no buff id" },
  { "itemId": 286612, "name": "Sand-Covered Silk Sash", "cooldownMs": 1800000, "durationMs": 5000, "slotType": "ItemTypeWaist", "_conf": "med", "_why": "tooltip only" },
  { "itemId": 287026, "name": "Escape Plan", "cooldownMs": 900000, "durationMs": 10000, "slotType": "ItemTypeRanged", "_conf": "med", "_why": "tooltip only; slot from wago InventoryType 26" },
  { "itemId": 289296, "name": "Benediction", "cooldownMs": 60000, "slotType": "ItemTypeWeapon / HandTypeTwoHand / WeaponTypeStaff", "_conf": "med", "_why": "tooltip '(1 Min Cooldown)'; swap with Anathema 289297" }
]
```

### P4. Consumables (new `consumablesAdd`; high)

Rule: add every `db.json` consumable whose `onUse` has category 4, 24, 1153 or 28 or an item/category cooldown above 1 s and that is not already emitted. Names come from `db.json`. Group ids as in §3.2:

```json
"consumablesAdd": [
  { "categoryId": 4,    "categoryCooldownMs": 120000, "consumableType": "ConsumableTypePotion", "ids": [118,858,929,2455,2456,3384,3385,6048,6049,6050,6051,6052,9144,14894,18839,18841,255663,268881,268882,268883,274935,282011,282013], "_conf": "high", "_why": "db.json onUse cat 4 + tooltips '(2 Min Cooldown)'" },
  { "categoryId": 4,    "categoryCooldownMs": 300000, "ids": [17348,17349,17351,17352], "_conf": "high", "_why": "Draughts, tooltips 5 Min" },
  { "categoryId": 1153, "categoryCooldownMs": 120000, "ids": [1703,5509,5510,5511,5512,5513,8007,8008,11951,11952,15723,17747,19004,19005,19006,19007,19008,19009,19010,19011,19012,19013], "_conf": "high", "_why": "Healthstones + gems; db.json cat 1153; tooltip 2 Min on 5509/19004" },
  { "categoryId": 24,   "categoryCooldownMs": 60000,  "ids": [1178,1399,1402,4358,4360,4365,4370,4374,4378,4380,4390,4394,4403,4598,5013,6714,10507,10514,10562,10586,10830,11566,13180,15993,16005,18588,18641,22151,215168,260792,260793,260795,260797,260798,260803,260805,260809,260814,260816,260817,276145,277499,284868], "_conf": "high", "_why": "explosives, shared engineering lockout; tooltips 1 Min" },
  { "categoryId": 24,   "categoryCooldownMs": 60000, "cooldownMs": 300000, "ids": [10646], "_conf": "high", "_why": "Goblin Sapper Charge" },
  { "categoryId": 24,   "categoryCooldownMs": 120000, "ids": [1127], "_conf": "med", "_why": "Flash Bundle" },
  { "categoryId": 28,   "categoryCooldownMs": 300000, "ids": [1400], "_conf": "med", "_why": "Swiftfeather Token" },
  { "categoryCooldownMs": 900000, "ids": [4376,4386], "_conf": "med", "_why": "Flame/Ice Deflector" },
  { "categoryCooldownMs": 60000, "cooldownMs": 60000, "ids": [246948], "_conf": "med", "_why": "Distilled Firewater (matches Winterfall Firewater's shape)" }
]
```

Skip for now: the 6 of the 104 ids that P4 leaves out (Full Moonshine 1072 and Mug of Shimmer Stout 3087 and Fishliver Oil 1322, whose item cooldown is -1, and the three Mark of the Dawn rows, 1.5 s item cooldown), the 3 s elixir/flask lockout (category 2593) and the 1 hour camping features. They are not bar-worthy. Forever potion reissues (287966-288898) are **low** confidence until Q2 is answered, so they are not in the fragment.

### P5. Debounce ICDs and window-less procs (`gen_item_data.py` constants; medium)

```python
# gen_item_data.py, near SLOT_FIELDS
DEBOUNCE_ICD_MS = 1000   # [D] 33 of 51 icd rows are 10/100/200 ms debounces (Searing Dagger tooltip "10ms cooldown")
```

- In the proc and enchant branches (`:260-262`, `:293-295`) emit `icdMs` only when `>= DEBOUNCE_ICD_MS`, else emit `icdDebounceMs = <n>`. The Searing Dagger row then reads `icdDebounceMs = 10`.
- Rows with `buffName` but neither `durationMs` nor `maxStacks` (205 of 400): add `window = "none"` so Forte_Cooldown/Core/Procs.lua can skip them (Q1).

```json
"_notes_procs": {
  "273003": { "_conf": "med", "_why": "Searing Dagger: buffId 1291570 is the damage spell, aura 1291568 has ICDMs 10; no player buff to show" }
}
```

### P6. Optional: emit the proc rate (low)

`proc.ppm` from `db.json` (58 rows) and `procChance` for the rest (28). The generator never emits a rate today and no consumer reads one, so skip unless asked.

### P7. Resolve name collisions deterministically (`gen_item_data.py:171`; medium)

```json
"preferId": {
  "Fist of Stone":                { "itemId": 17943, "_conf": "med", "_why": "droppable live mace (Landslide 37.06%); 17733 has no drop source" },
  "Earthshaker":                  { "itemId": 17073, "_conf": "low", "_why": "ilvl 66 Magmadar drop is the raid item; 288900 is a BoE clone, same buff 21152" }
},
"byNameClassRows": ["Insignia of the Horde", "Insignia of the Alliance"]
```

Change `by_name_keyed` so a name with several `classAllowlist` variants emits a table `OnUseByName[name] = { ClassWarrior = row, ClassHunter = row, ... }` (or a list), not the lowest id. Also add the 22 `ProcsByBuffName` collisions to the generated header (they are printed to stdout but not recorded in the file).

### P8. Header provenance (low)

Add the items-leg push (113823, wowsims `9ca4d977`) and a line "values taken from mythicsim 70425 plus `live_items.json`" to `common_header()`. A re-run of `extract_store.py` is not needed for this patch because the overlay holds no item values.

### P9. Re-baseline (high)

After P2-P4: re-run `python3 tools/gen_item_data.py`. The expected counts become `onUse = 238 + 11 = 249`, `consumables = 79 + 98 = 177` (P4 lists 98 ids). Check that the three cooldowns and the eleven new `ByName` keys appear, and that `gate.py`'s item checks still pass.

---

## Sources

Fetched 2026-11-09:

- `https://worldofwarcraft.blizzard.com/en-us/news/24315281/wow-forever-hotfixes-november-6-2026` (Items line)
- `https://us.forums.blizzard.com/en/wow/t/wow-forever-hotfixes-november-6-2026/2403040.json` (same text, posts 1 and 4)
- `https://nether.wowhead.com/forever/tooltip/item/<id>`: 238 on-use rows, 37 ICD items, 207 consumables, ~60 decoy/new items, 1,804 unknown ids scanned (998 class-0 resolved, 109 of 833 weapon/armor)
- `https://wago.tools/db2/Item/csv?product=wowf` (item table)

Local:

- wowsims `9ca4d977`: `assets/database/db.json` and its history, `assets/db_inputs/spell_store_inputs.json`, `sim/common/forever/enchants_auto_gen.go`
- mythicsim `ff6a43cf`: `data/*.jsonl`, `src/prepare/forever_items_generated.rs`, commits `4808857e`, `420dfe31`, `7663ed97`, `75d543f3`, `3a1bb052`, `341ec298`, `6469b36a`
- this repo: `tools/gen_item_data.py`, `addon/Forte_Items/Data/Items.lua`, `addon/Forte_ItemProcs/Data/Procs.lua`
