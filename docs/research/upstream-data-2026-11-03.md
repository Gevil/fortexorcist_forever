# Upstream data diff — wowsims `164d1cf6..6e69a7f4`, mythicsim `f794f2b..14b1a693` (2026-11-03)

Agent `DataScout2`. PLAN §11.2 Iteration I, "Data upstreams" row.
Clones read: `/tmp/wowsims-forever` @ `6e69a7f4f239c591e9dec4124a93fca6329c240f`,
`~/Work/Personal/mythicsim-forever-engine` @ `14b1a693`. Our repo `e58ea97`.
Prior baseline note: `docs/research/data-diff-70707.md` (2026-11-02, wowsims @ `164d1cf6`) —
this note is the **increment**; it does not repeat §1/§2/§3 of that file.

## 0. Answer

1. **No new client build, and no upstream base-data change at all.** The wowsims spell store is
   stamped `1.60.1.70707` × 12 groups with hotfix push `113562` at *both* pins; the one byte change to
   `assets/db_inputs/spell_store_inputs.json` in the range (`c8d54897`, 2026-11-03, "[DB] Update items
   to 1.60.1.70707 with hotfixes as of 2026-11-03") is a **gzip re-pack**: the decompressed payload is
   byte-content-identical, and upstream documents exactly that artefact in `ee93a917` ("[Skills] Note
   the gzip-only change a clean regeneration leaves on the store inputs"). mythicsim's
   `data/manifest.json` is unchanged (`client_build: 1.60.1.70425`) and `git diff --stat
   f794f2b..14b1a693 -- data/` is **empty**. The installed client's `.build.info` is `1.60.1.70707`.
2. **The one real data delta in our pipeline is self-inflicted staleness, not upstream.** The
   checked-in `tools/overrides_70707.json` was last generated for Wave 2a (`7fa9134`); Wave 2b
   (`2e0124c`, "T1 class spell lists (+43 cast spells, 22 procs deferred to H7)") added **42 tracked
   names that the overlay has no coverage for**. A fresh extract from the *old* pin reproduces the
   fresh extract exactly, so the `+458` ids / `+42` names delta is repo drift. Regenerating the
   overlay moves **8 rows across 5 class data sets** (§2.2).
3. **Our 70707 overlay path has no cast-time column at all** (`Cooldowns` keys are only
   `CooldownMs`/`CategoryCooldownMs`/`GCDMs`, measured over 71,480,000 rows) — every `castMs` we ship
   is a 70425 base-data number, and no store refresh can move it. That is the pipeline's one blind
   spot for the 2026-11-03 dev notes (Chain Lightning's 2.5 s cast, Wild Growth's 3 s).
4. **The 2026-11-03 Blizzard notes (forum post 9) are NOT in the captured client.** Measured in the
   `6e69a7f4` store: Slam's ranks still `18000` ms, Stormstrike `17364` still `8000`, Riptide
   `1239243`/`408521` still `6000`, Lava Burst's 11 ranks are all present, `Elemental Mastery`
   `16166` still carries the 180 000 / 15 000 rows, `437009` is still named `Totemic Projection`
   (`60000`). Some of the *same* notes **are** in the capture: shared trap category `411`/`30000`,
   Ice Lance on Fire Blast's category `19`/`8000`, Arcane Blast `400573` `18000`, Ferocious Bite
   `1328618` at level 24, Primal Bite's 3-rank ladder, Righteous Fury `25780` at level 10,
   `Oath of Light 1328548` `300000`, Swift Judgement with no shared category, Lacerate's two new low
   ranks. Full per-item table: §5.
5. **wowsims now publishes a MIT name→spellId table for every talent** (`6671d332` "[SIML] Name every
   talent in the spell namespace"; `sim/siml/names.json` leaves `2348 → 2785`, +437 of which 414 carry
   `talentOnlyBy`). It resolves **10 of our 22** deferred `_deferred_H7` proc names, 8 of them new in
   this range, all with store-verified durations (§3.1).
6. **Items: nothing to regenerate.** Their item DB moved `2098` of `5226` entries, all in `sources`
   (2090) and `scalingOptions` (8), `0` in `stats`; `consumables` and `spellEffects` are identical;
   118 of our 705 item ids fall in the changed set, all metadata-only, and `tools/gen_item_data.py`
   reads mythicsim (unchanged) — §2.4.
7. **Must-regenerate list: 1 data artefact + 9 class data sets + 6 spell lists; no item regeneration**
   (§6). Ranked change list with the files each item touches: §7.

---

## 1. Build pins (verified)

| source | our pin | upstream head | client build | hotfix push |
|---|---|---|---|---|
| wowsims spell store | `164d1cf6` | `6e69a7f4` | `1.60.1.70707` (12/12 groups) | `113562` (12/12) |
| mythicsim `data/manifest.json` | `f794f2b` | `14b1a693` | `1.60.1.70425` | — (models `113531`, `113554`) |
| installed client `.build.info` | — | — | `1.60.1.70707` | — |

Evidence: `tools/overrides_70707.json` `_meta` = `{"build": "1.60.1.70707", "commit":
"164d1cf6…"}`, regenerated `_meta.commit` = `6e69a7f4…`; `Builds`/`Hotfixes` tables of
`assets/db_inputs/spell_store_inputs.json` at both pins; mythicsim manifest hashes for every
`data/*.jsonl` identical; the highest hotfix number named anywhere in mythicsim source is `113554`
(`src/prepare/hotfix_113554.rs`, tests `hotfix_113554*.rs`, `hotfix_20261103.rs`) — `113504`,
`113509`, `113531`, `113536` also appear; `113575`/`113585` are digit noise inside fixture numbers.

No build string newer than `1.60.1.70707` exists in either tree. `[INFERENCE]` The 2026-11-03 notes
(post 9) therefore live in a push the store has not captured; our pin (`113562`) is *ahead* of
mythicsim's modelled push (`113554`), so mythicsim is the more speculative of the two, not the
fresher.

## 2. Data changes touching our lists

### 2.1 The overlay's own delta (repo drift)

`python3 tools/extract_70707.py --wowsims /tmp/wowsims-forever --out /tmp/overrides_new.json` →
`spells=3870 nameIndex=583 removed=7 bookRanks=35`; checked-in = `3412 / 541 / 7 / 35`.
Added spells `458`, dropped `0`, value changes to *already-covered* ids `0`; added names `42`;
`removed` list identical (`1038, 19977, 19978, 19979, 25890, 25895, 1325499`); `bookRanks` identical.

Proof this is not upstream: extracting from a store decompressed from `164d1cf6`'s blob
(`/tmp/overrides_oldpin.json`) yields the identical result, and the value tables (`Names`,
`Cooldowns`, `Categories`, `AuraOptions`, `Misc`) are content-identical across the range.

The 42 newly covered names, by list:

| class | n | names |
|---|--:|---|
| druid | 8 | Berserk, Dash, Lifebloom, Pounce, Pounce Bleed, Skull Bash, Starfall, Thrash |
| mage | 13 | Arcane Blast, Blast Wave, Blizzard, Combustion, Cone of Cold, Deep Freeze, Fire Blast, Flamestrike, Freeze, Frost Nova, Frostfire Bolt, Living Bomb, Pyroblast |
| paladin | 5 | Aura Mastery, Beacon of Light, Holy Shield, Holy Shock, Reckoning |
| priest | 8 | Devouring Plague, Holy Fire, Mind Blast, Mind Flay, Mind Sear, Prayer of Mending, Renew, Vampiric Touch |
| rogue | 5 | Crimson Tempest, Deadly Poison, Dismantle, Envenom, Mind-numbing Poison |
| shaman | 3 | Heroism, Lava Burst, Stormstrike |

All 42 were added by `2e0124c` (Wave 2b) — e.g. its `tools/spell_lists/mage.json` hunk adds
`"Blizzard", "Living Bomb", "Pyroblast", "Flamestrike", "Frostfire Bolt", "Freeze"` and
`paladin.json` adds `"Holy Shield", "Holy Shock"` / `"Beacon of Light", "Reckoning", "Aura Mastery"`.

### 2.2 What regeneration does to generated rows (dry runs, old overlay vs fresh)

`tools/gen_spell_data.py <class> --dry-run --out /tmp/dry_{old,new}_<class>.txt`, diffed.
Unresolved counts are unchanged (`hunter 1, mage 1, paladin 1, priest 2, rogue 1, warlock 2,
druid 0, shaman 0, warrior 0` gaps). Row-level deltas, verbatim:

```
[druid]   70707: Dash:  { … noTarget = true, durationMs = 15000, cooldownMs = 30000, cooldownCategory = 44, … } -> { … (noTarget gone) … }
[druid]   70707: Pounce Bleed: { id = 9826, … tickEvery = 3, durationMs = 18000, rank = "Rank 3" } -> { … (tickEvery gone) … }
[mage]    70707: Blizzard:    { id = 10187, … } -> { … cooldownCategory = 2518 … }
[mage]    70707: Flamestrike: { id = 10216, … } -> { … cooldownCategory = 2506 … }
[paladin] 70707: Holy Shock:  { id = 1311606, … rank = "Rank 1" } -> { id = 20930, … rank = "Rank 4" }
[paladin] 70707: Reckoning:   { id = 1326084, maxStack = 4, noTarget = true, durationMs = -1 } -> { id = 1326084, durationMs = -1, icdMs = 1500 }
[rogue]   70707: Dismantle:   { id = 442206, noTarget = true } -> { id = 442206, icdMs = 12000 }
[shaman]  70707: Heroism:     { id = 23689, noTarget = true, durationMs = -1 } -> { id = 23689, durationMs = -1 }
```

`hunter`, `priest`, `warlock`, `warrior` regenerate **identically at row level** (only the
`-- Wowsims forever @ <sha>` / `-- Regenerated:` header stamp moves). Two structural readings:

- **Gain:** a picked row whose name is now store-covered takes the 70707 `Categories.Category`
  (Blizzard `2518`, Flamestrike `2506`) and the store's `AuraOptions.ICDMs` (Reckoning `20177`
  `1500`; the same mechanism gave us Feint `11303`, Dismantle `12000`, Seal of Command `1000`,
  the three shields (Lightning, Earth, Water) `3500`, Flurry `500`, Taste for Blood `5800`, Immolation Aura `1000` in the
  checked-in data). A rank move follows the store's ladder: Holy Shock `1311606` (`baseLevel 30`,
  `Rank 1`) → `20930` (`baseLevel 56`, `Rank 4`) — the first is a **displayed rank label**
  (`test_70707_overlay.lua:68` asserts rank text).
- **Loss:** a store-sourced row carries no `Effects`/`MaxStack`/`Targets`, so five rows *lose* a feed
  column (`noTarget` on Dash / Dismantle / Heroism / Reckoning, `tickEvery` on Pounce Bleed,
  `maxStack` on Reckoning) that only the 70425 base data supplies. Dismantle keeps
  `icdMs = 12000` and Reckoning keeps `durationMs = -1`, so the assertions at
  `test_tracked_set.lua:164,168,173` survive; the `noTarget` band in Forte_Timer and the
  max-stack read for Reckoning do not. Fix in §7 item 5.

### 2.3 ICD / rank / consumable changes for our tracked names

`AuraOptions` is content-identical between the pins ⇒ **zero ICD moves** for any id we already
cover; the fresh overlay's extra coverage *adds* ICDs on 73 newly-covered rows (measured census), of
which exactly two land on tracked rows (Reckoning `20177` `1500` via the name `Reckoning`; Dismantle
`442206` `12000` already shipped). Rank moves: 1 (Holy Shock). Consumables: mythicsim
`data/consumables.jsonl` = 106 rows, unchanged; wowsims `db.json.consumables` identical.
`spellEffects` identical. `bookRanks` 35, identical, and identical in content to the store-derived
`book_ranks` law (see §4.3 for the new cross-check export).

### 2.4 Item data

`assets/database/db.json` over the range: `items 5226 → 5226`, changed `2098`, added `0`,
removed `0`; changed-field census `sources: 2090`, `scalingOptions: 8`, **items with a changed
`stats` block: 0**. Scanning our shipped ids (`addon/Forte_Items/Data/Items.lua` +
`addon/Forte_ItemProcs/Data/Procs.lua`, 705 ids) into that set: `118` intersect, all `sources`-only.
`tools/gen_item_data.py` consumes mythicsim `data/{items,consumables}.jsonl` (byte-identical) ⇒
**no item regeneration**, and the `sources` field we do not ship is the whole delta.
Spot-checks against the notes: The Black Book `19337` carries `buff_id 23720`,
`effect_duration_ms 30000`, `on_use.cooldown_ms 300000`, `category_id 1141` (mythicsim head
`c8132853`) — our row matches, so the 5-minute book cooldown is already right. Oil of Immolation:
`0` rows in `data/consumables.jsonl` and absent from our item/procs data (mythicsim models it in
`src/core/fight/oil_of_immolation.rs`, `ca434dbf` PR #189) ⇒ no item row to add, and its
"stalls the running melee swings by 0.5 s" law is a Phase-2 swing-bar fact, not data.

### 2.5 The cast-time blind spot

`Cooldowns` key census = `CooldownMs`, `CategoryCooldownMs`, `GCDMs` — no cast field. Cross-checked
against our rows: `Chain Lightning 10605 castMs = 2000` and `Wild Growth 1238215 castMs = 3000` come
from mythicsim's 70425 rows, never from the store. Consequences: post 9's Chain Lightning
"cast time increased to 2.5 seconds" is invisible to the store path; Wild Growth's 3 s happens to
agree; `Stormstrike`/`Lava Burst`/`Arcane Wrath` cast times all ride the 70425 pin. This is the one
column family where a *pin bump* cannot help us — only a live-client read (§7 item 6).

## 3. New Forever rules that change what we display

### 3.1 wowsims' talent name table resolves 10 of our 22 deferred procs

Range commits: `6671d332` ("talent_is_known and talent_rank read a spell name … the generator now
collects each build's talents into spell, uncastable and with no rank"; "The table also picks up the
three Shieldsworn Holy Shield copies"), `27e9ab6f`, `3a8b2146`, `95c21176`, `24464ec2` ("[SIML] Name
Riposte, its window, Setup and Ghostly Strike's buff for the rogue"). `sim/siml/names.json` shape:
`classes.<class>.<kind>.<snake_name> = {spellId, tag, registeredBy}`.

Resolved today (id from names.json, name/duration from the store's `Names`/`Misc`):

| our deferred name | id | store duration | new in this range |
|---|--:|--:|---|
| Clearcasting (druid) | 16870 | 15 000 | no |
| Forbearance (paladin) | 25771 | 60 000 | no |
| Fingers of Frost (mage) | 400669 | 15 000 | **yes** |
| Ignite (mage) | 412538 | 4 000 | **yes** |
| Infusion of Light (paladin) | 437063 | 15 000 | **yes** |
| Vengeance (paladin) | 20050 | 30 000 | **yes** |
| Vindication (paladin) | 440667 | 30 000 | **yes** |
| Maelstrom Weapon (shaman) | 408505 | 30 000 | **yes** |
| Deep Wounds (warrior) | 12834 | 0 | **yes** |
| Enrage (warrior) | 12880 | 12 000 | **yes** |

Unresolvable (no names.json key): Living Seed, Nature's Grace, Savage Defense, Brain Freeze, Chilled,
Mana Surge, Ancient Power, Grand Crusader, The Art of War, Serendipity, Surge of Light, Vigilance.
Caveat: Deep Wounds `12834` and Maelstrom Weapon `408498` carry `DurationMs 0` (the window lives on
the sibling `408505`), so they yield an id with no bar.

### 3.2 Shaman — the 2 Nov dev notes, as mythicsim models them

`28859c08` "Take the rest of the Shaman development notes of 2 November under Forever's rules"
(Lava Burst removed, its slot giving Call of Thunder, Elemental Mastery's aura named Lightning
Mastery, Chain Lightning 2.5 s / 145 % / 225 %, shocks at Classic Era values);
`README.md:400-405` ("Lava Burst is removed: its talent slot … gives Call of Thunder … and no Lava
Burst spell is registered … Elemental Mastery's aura reads Lightning Mastery (the name only)");
`src/classes/shaman/prepare/talents.rs:31-38` (`Rules::Forever => "Lightning Mastery"`),
`:104-107`; `src/prepare/hotfix_113554.rs:391-392` (`// Shaman (notes of 2 November): Stormstrike's
cooldown 8 sec to 6.` / `patch(17364, … cooldown_ms = 6000)`), `:264`
(`CHAIN_LIGHTNING_CAST_MS_20261102 = 2500`). Store reality at `6e69a7f4`:
`17364 CooldownMs 8000`, Lava Burst present (11 ids incl. `1326047` Category `1224` /
`CategoryCooldownMs 10000`), `16166 Elemental Mastery CooldownMs 180000 / DurationMs 15000`,
`16579-16582 Lightning Mastery` present as **value-less** rows. Verdict: a **rename + hotfix-watch**
item, not a regeneration item (§7 item 4).

### 3.3 Paladin — the new proc/tag ids are in the client, not in our lists

Store rows (all `Names` hits, `Misc.DurationMs`): `Shieldsworn 1328544` (0) / `1328551` (6 000),
`Echo of Fury 1311701` (15 000, `ICDMs 0`), `Echo of Command 1311703` (15 000), `Unsealed Wrath
1310735` (`ProcFlags [4, 0]`), `Oath of Light 1328548` (**300 000**), `Boundless Light 1328550` (0).
All six are **ABSENT from `tools/spell_lists/paladin.json` and `Forte_Paladin/Data/Paladin.lua`**
(measured). Range commits that light them up: `25797d46` ("[Prot] Test which Holy Shield copy a
Shieldsworn Holy Strike casts"), `5e79880e` ("split Seal of Command's roll from its cast"),
`50effdfa` ("Report Unsealed Wrath's Echo hits apart"), `e2842f0a`, `34c557c4`; `c8d54897` added the
`holy_shield_2092{5,7,8}_tag1328544` / `seal_of_fury_*_tag1311701` / `seal_of_command_tag1311703`
SIML names. Display reading: a proc-driven Holy Shield copy arrives with the *same* spellId as the
player cast (`tag 1328544`), so Forte_Cooldown's cast-predict must not treat the copy as a second
player cast. `[INFERENCE]` The `tag` field is wowsims' SIML marker, not a client column.

### 3.4 Rogue

`143efa6a` "[Rogue] Preparation finishes Riposte's cooldown" — store `14251 Riposte`
`CooldownMs 6000`, `Category 133`, `CategoryCooldownMs 1000`; our row matches
(`Forte_Rogue/Data/Rogue.lua [14251]`) ⇒ a *reset* event our engine must absorb (the client's own
cooldown recalc does this; no data change). `6f9ef519` "Setup hears only the current target's
attacks"; `572cff35` "Lightning Reflexes, Deflection and Ghostly Strike's dodge buff".
Store: `Setup 13983` (`ICDMs 1000`, `ProcFlags [131112, 0]`, `DurationMs 0`), `Ghostly Strike 14278`
(7 000, cd 20 000 — already ours), `Riposte 14251` (ours). **`Setup` is ABSENT from our Rogue data**;
it is an ICD-gated proc with no window, so it belongs to the proc layer, not a bar.

### 3.5 Priest / Druid / Hunter additions with real client windows

`67e01d91` "Party buffs: a Shadow Priest's Dark Inspiration at its talent rank" — store
`1326159 Dark Inspiration` (0) / `1326168` (**10 000**); ABSENT from our priest data.
Druid/Hunter new tracked-name candidates from `names.json` (all store-verified): `Bloom 1328621`
(level 1, `DurationMs 0`), `Ferocious Bite 1328618` (level **24** — the notes' new Rank 1),
`Primal Bite 1238070` (level 60), `Shifting Power 1322605` (cd 8 000), `Read Leyline 1259705`,
`Touch of the Grave 1260198`, `Berserking 20554`, `Blood Fury 20572`, `Slam 11605`,
`Ice Lance 1240047`, `Arcane Blast 400573` — the racial five are **in no spell list of ours**
(measured `listed=-` for Blood Fury, Berserking, Touch of the Grave, Read Leyline).

## 4. Shaman totem facts (for `Forte_Shaman/Core/Totems.lua`)

1. **Slot model is confirmed by upstream.** `README.md:613-615`: Mana Tide Totem "stands in the
   water totem slot: its cast ends a Healing Stream Totem … and a Healing Stream Totem cast ends
   it". Our tracker is slot-keyed (`Totems.lua:50` slot→element, `:130` `ReadSlot`, `:155`
   `OnTotemUpdate`, `:217` one row per slot) ⇒ the exclusivity pair (Mana Tide / Healing Stream,
   both water) needs no change.
2. **Totem ids/durations match the live store exactly.** Store `10497 Mana Spring Totem 300 000`;
   `1325256 Mana Tide Totem 13 000` with `Category 591` / `CategoryCooldownMs 300 000`
   (ranks `16190`, `17354` identical shape; aura `1325257 Mana Tide 0`);
   `10613/10614/8512 Windfury Totem 300 000`; `10442` / `25361 Strength of Earth Totem 300 000`;
   `10627` / `25359 Grace of Air Totem 300 000`; `8177 Grounding Totem 45 000` +
   `8178 Grounding Totem −1` (`ProcFlags [131072, 0]`); `8227/8249/10526/16387 Flametongue Totem
   300 000`. `Shaman.lua [10497] durationMs = 300000` and `[1325256] durationMs = 13000,
   cooldownMs = 300000, cooldownCategory = 591` agree — no totem row moves.
3. **The new `release/book-ranks.json` export** (`f57e1efe`, 194 lines,
   `{"note": "Ahn'Qiraj 20 book ranks …", "ranks": [...]}`) is a *narrower* table than our 35-id
   `bookRanks`: it includes `Grace of Air Totem` (`10627` → book `25359`) and
   `Strength of Earth Totem` (`10442` → book `25361`), and `25346` (Arcane Missiles) which our table
   lacks; our table uniquely carries `25302, 25916, 25918, 28609, 28610, 28612, 29228, 31016, 31018`.
   Display effect today: **none** — `gen_spell_data.py` excludes book ranks, so we ship the trainer
   ranks (`10442 Rank 4`, `10627 Rank 2`), and the runtime totem row is slot/name-keyed, never
   id-keyed (`Totems.lua:50,130`), so a guild casting the book rank (`25361`) still lands on the
   slot row. Value: a **second opinion on the rank ladder** — a gate cross-check (§7 item 8).
4. **The air slot can be lit by a weapon, not a totem.** Store `Windfury Weapon 8233/8236/10484/16361`
   `1 500` (`ProcFlags [4, 0]`, one `ICDMs 1 500` at `439431`) vs `Windfury Totem 10613` `300 000`;
   mythicsim `0578ba5d`/`97ac83d8`/`9b6da03a` ("Windfury Weapon follows the weapon and outbids the
   party totem"). Our shaman list tracks `Windfury Weapon` (stamps, `16361 icdMs = 1500`) and does
   **not** track the name `Windfury Totem` (measured ABSENT) ⇒ a Windfury bar that appears with no
   totem cast is legitimate. Post 9 adds the swing animation for both.
5. Totem-adjacent talents that are all `DurationMs 0` in the store (nothing to draw):
   `Restorative Totems 16187`, `Guardian Totems 16258`, `Totemic Focus 16173`,
   `Thundering Strikes 16255`; mythicsim `talents.rs:961` "Restorative Totems … and Mana Tide Totem
   (the party buff) register nothing". Enamored Water Spirit `20503` → `buff_id 24854
   "Mana Spring Totem (24854)"`, `effect_duration_ms 24000`, `on_use.cooldown_ms 600000`
   (mythicsim `items.jsonl`; our item list carries the trinket).

## 5. Blizzard dev notes 2026-11-03 vs our data

Source: [WoW Forever Beta Development Notes – Updated November 2, **post 9**, 2026-11-03,
"changes since the October 15 beta update"](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-november-2/2360696/9).
Columns: **store** = the `6e69a7f4` (= `164d1cf6` content) capture; **head** = wowsims head
code/names.json; **msim** = mythicsim head; **ours** = the shipped row, cited.

| # | note (post 9) | store | head | msim | ours today | verdict |
|--:|---|---|---|---|---|---|
| 1 | Slam cd **15 s** (was 18) | `1464/8820/11604/11605/1310200 CategoryCooldownMs 18000`, Category `2412` | no Slam change in range | `hotfix_113554.rs:279-280` `SLAM_RANKS`, `:378-381` 18→15 | `Forte_Warrior/Data/Warrior.lua [1310200] cooldownMs = 18000, cooldownCategory = 2412` | **not carried by the client capture**; msim ahead. Override + launch probe |
| 2 | Improved Slam cut 2.5/5 s (was 3/3) | `12862` talent, `DurationMs 0`, no `Cooldowns` row | — | `hotfix_113554.rs:119-126` `[-2500,-5000]` | untracked (a talent) | no action (talent curve, not a displayed row) |
| 3 | **NEW** talent Reckless Swings, 15 s cd, 8 s window | **not in `Names`** | not in names.json | none (only Curse of Recklessness) | absent | net-new; `_deferred_H7` + probe |
| 4 | Lava Burst **removed** (→ passive Call of Thunder) | 11 ranks present; `1326047 Category 1224`, `CategoryCooldownMs 10000` | names.json `lava_burst 1326047` | `talents.rs:104-107`, `README.md:400-404` "no Lava Burst spell is registered" | `[1326047] cooldownMs = 10000, cooldownCategory = 1224, castMs = 2500`; listed `shaman.json`; asserted `test_tracked_set.lua:150` | **client keeps it** → keep the row; hotfix-watch, launch probe. Do **not** map `Call of Thunder 16120` (that is the Far Sight scry spell, `Misc` value-less) |
| 5 | Totemic Projection → **Totemic Call**, cd **30 s** | `437009` named `Totemic Projection`, `CooldownMs 60000`, `DurationMs 1000` | no `totemic_call` key | none | `[437009] durationMs = 1000, cooldownMs = 60000` | rename is **not** in the capture → alias layer + expected `30000` |
| 6 | Elemental Mastery → **Lightning Mastery** (icon) | `16166 Elemental Mastery 180000/15000`; `16579-82 Lightning Mastery` value-less | `elemental_mastery 16166`; no `lightning_mastery` key | `talents.rs:31-38` | `[16166] name = "Elemental Mastery", cooldownMs = 180000` | rename not in the capture → alias by **name and id** (`16579-82` exist client-side) |
| 7 | Stormstrike cd **6 s** (was 8), 150 % WH | `17364 CooldownMs 8000`, `DurationMs 12000` | `stormstrike 17364` | `hotfix_113554.rs:391-392` `6000` | `[17364] durationMs = 12000, cooldownMs = 8000` | not carried; probe (a 2 s over-count if it ships) |
| 8 | Riptide cd **12 s** (was 6), no initial heal | `1239243/1239242/408521 CategoryCooldownMs 6000`, Category `1228`, `DurationMs 15000` | `riptide 408521` | **not modelled** (`README.md:406-408`) | `[1239243] cooldownMs = 6000, tickEvery = 3, durationMs = 15000` | nobody carries 12 s → post 9 is the only source |
| 9 | Chain Lightning cast **2.5 s** | **no cast column in the store** | — | `hotfix_113554.rs:264` `2500`, `README.md:393-397` | `[10605] castMs = 2000` (70425) | invisible to the store path (§2.5) |
| 10 | Ice Lance **8 s shared with Fire Blast** | `400640 Category 19 / 8000` (also `1240044-47`, `1312002`); `10197 Category 19 / 8000` | `ice_lance 1240047` | `mage/prepare/spells.rs:530` "push 113531 puts Ice Lance on Fire Blast's category (19)" | `[400623] cooldownMs = 15000, cooldownCategory = 19`; **Ice Lance absent from `mage.json`** | **already carried** (category `19`) → add the Ice Lance name so the shared bar has both sides; note ranks `400616-23` say `15000` for the same category |
| 11 | Arcane Blast duration **18 s** | `400573 DurationMs 18000` (stack aura); cast `18091 CategoryCooldownMs 8000` | `arcane_blast aura 400573` | — | `[18091] cooldownMs = 8000` | **carried**; the 18 s aura shares the *name*, so a name-keyed list cannot show both → needs an explicit aura row. The Cooldown Manager's own list says "Arcane Blast cannot be tracked" |
| 12 | Frost Blast **removed** | present: `16407/18398/20869 CategoryCooldownMs 8000` | names.json `frost_blast` | `masks.rs:40` "a trained Frost spell of client 70425" | untracked | no action; do **not** add |
| 13 | Piercing Ice removed | `11151` value-less | — | `talents/frost.rs:37` "left the tree in hotfix push 112753" | untracked | no action |
| 14 | **all traps share one 30 s cd** | `14310/14311 Freezing Trap Category 411 / 30000`, `13809 Frost Trap 411/30000`, `13813/14316/14317 Explosive Trap 411/30000` | `explosive_trap 14317` | — | `[14311] cooldownMs = 30000, cooldownCategory = 411`, `[13809] … 411`, `[14317] … 411` | **fully carried** (the 70425 base rows said category `2183`; the 70707 overlay already moved them) |
| 15 | Hunter's Mark one rank per target | `1130/14323/14324/14325 DurationMs 120000`, Category `0` | — | rank-stacking laws in `talents/survival.rs` | `[14325] durationMs = 120000, rank = "Rank 4"` | no data column for the exclusivity → no change |
| 16 | Berserk talent **removed**; Primal Bite replaces it; Primal Bite ranks → **3** | `417141 Berserk CooldownMs 180000`; Primal Bite ladder `407995`(L40)/`1238069`(L50)/`1238070`(L60) `Category 971 / 6000` + value-less `1238073` | `berserk 417141`, `primal_bite 1238070` | `druid/prepare.rs:63` "Berserk (417141) … are gone", `:88`, `prepare/bear.rs:31` "rank 4 (1238073) in the frozen data, rank 3" | `[417141] cooldownMs = 180000`; `[1238073] cooldownMs = 6000, cooldownCategory = 971, rank = "Rank 4"` | client keeps Berserk's rows → keep, hotfix-watch. **Our Primal Bite pick is the value-less Rank 4**; the store's ladder stops at Rank 3 = the note's "reduced to 3" → rank-law bug (§7 item 7) |
| 17 | Lacerate is now a Feral talent, +2 low ranks | ladder `1328617`(L25,R1) `1328616`(L34,R2) `414644`(L42,R3) `1235826`(L50,R4) `1235827`(L58,R5) | `lacerate 1235827` | — | `[1235827] rank = "Rank 5", durationMs = 15000, tickEvery = 3, maxStack = 5` | the two new ranks are **already in the capture**; talent-gating is not a displayed column |
| 18 | Ferocious Bite new Rank 1 at 24 | `1328618 SpellLevel 24` (+`22568` 32, `22827` 40, `22828` 48, `22829` 56, `31018` 60) | `ferocious_bite 22829` | `export.rs:502` Predatory Discipline `1328613` (push 113531) | untracked | **carried** → add to `druid.json` |
| 19 | Shifting Power now a talent | `1322605 CooldownMs 8000` | `shifting_power 1322605` | `druid/prepare.rs:89` | `[1322605] cooldownMs = 8000` (the overlay moved it from the 70425 `16000`) | carried |
| 20 | Wild Growth cast **3 s** | no cast column | — | — | `[1238215] castMs = 3000` (base data) | agrees by luck; the field is not store-sourced |
| 21 | Bloom new (Rejuvenation/Regrowth expiry heal) | `1328621 SpellLevel 1, DurationMs 0` | `bloom 1328621` | `druid/agent.rs:142-143` "Bloom (hotfix push 113531, Forever's rules)" | untracked | id known, window 0 → proc/announce layer, not a bar |
| 22 | **NEW** spell Shank (L24, 10 s cd; R2 at L44) | `15248`, `15617` = **value-less Classic names** (no `Levels`/`Cooldowns`) | no `shank` key | `rogue/agent.rs:25` Shank implemented | untracked | the client has the *name*, not the new rows → post 9 is the source; add the name + probe for a Forever-family id |
| 23 | **NEW** talent Death Mark (active, 10 s cd, 6 s mark) | `1316709`, `1325756/7/8` value-less | no key | none | untracked | ids in the `13xxxxx` family exist; values net-new → `_deferred_H7` + probe |
| 24 | **NEW** passive Poised (rogue L18 / druid L32) | **not in `Names`** | no key | `rogue/agent.rs:35` Poised | untracked | net-new; cannot be keyed yet |
| 25 | Thousand Cuts / Cutthroat / Murder / Improved Distract removed | all present: `1310721` (`ICDMs 1900`), `1310723` (10 000), `462707` (10 000), `462708`, `14158`, `14084` | names.json has all four | — | untracked | no action; a caution for any names.json harvest: it carries removed talents |
| 26 | Blessing of Light **removed** | ranks `19979`/`25890` gone (= our `removed`); name survives value-less at `26650` | — | `prepare/buffs.rs:406` (push 113554, Salvation family) | `[26650] name = "Blessing of Light"` (value-less row); still listed in `paladin.json` | partially carried → prune the list name, drop the value-less row |
| 27 | Salvation / Mass Salvation / Revoke removed | **all three names absent from `Names`** (= our `removed` `1038`, `25895`, `1325499`) | — | `buffs.rs:406` | listed in `paladin.json`, resolved from base data, absent from `Paladin.lua` | **fully carried** → prune the three names |
| 28 | Righteous Fury trainable at level 10 | `25780 SpellLevel 10`, `DurationMs 1 800 000`; `407627 DurationMs -1` | — | — | `[25780] durationMs = 1800000` | carried; the level is not a shipped column. `[INFERENCE]` probe which id the client reports (the permanent `407627` is the Forever-shaped stance) |
| 29 | Swift Judgement: **no shared cd** with Judgement | `1310994 CooldownMs 60000 Category 0`; `20271 CooldownMs 10000 Category 0` | — | `paladin/agent.rs:62` "Swift Judgement … since push 113554: a second Judgement" | `[1310994] cooldownMs = 60000`; `[20271] cooldownMs = 10000` | **carried** (categories are `0`) |
| 30 | **NEW** Oath of Light (no cd, 5-min oath) | `1328548 DurationMs 300 000, CooldownMs 0, SpellLevel 0`; companion `1328550 Boundless Light` | `oath_of_light 1328548` (paladin/spell + aura) | `paladin/agent.rs:58` "Oath of Light's cast (push 113554, Forever's rules)" | **absent from `paladin.json`** | **the client already has it** → add the name; the generator yields a 300 000 tracked aura |
| 31 | Orc Blood Fury cd 2 min (was 3) | `20572`/`24571` have **no `Cooldowns` row** | `blood_fury 20572` | `prepare/racials.rs:149` | untracked (racials are in no list) | store cannot answer; post 9 is the source; a new feature surface |
| 32 | Troll Berserking duration 15 s (was 10) | `20554/23505/24378` value-less | `berserking 20554` | `contracts/prepared_v2.rs:1876` | untracked | store cannot answer |
| 33 | Undead Touch of the Grave ICD 15 s (was 25) | `1260189/1260198/1260201` value-less (no `AuraOptions`) | `touch_of_the_grave 1260198` | `core/fight/racial.rs:14` | untracked | store cannot answer |
| 34 | Skyborne Read Leyline 15 s | `1259705` value-less | `read_leyline 1259705` | `prepare/racials.rs:302` + `racials/tests.rs:406` | untracked | msim carries it; store cannot answer |

Reading of the table: **the store capture is the October-15-era client plus hotfix 113562**, and post
9 is a 2.5-week delta that the capture has *partly* absorbed (rows 10, 11, 14, 17, 18, 19, 27, 28, 29,
30 = 10 of 34). Shaman is the worst-covered class: 0 of 6 Shaman rows are in the capture, and
mythicsim models 4 of them (`113554`-keyed). `[INFERENCE]` The split is exactly "numbers the client
already ships" vs "numbers the notes promise for the 2026-11-04 opening", so a launch-day probe is
the only clean source for rows 1, 4, 5, 6, 7, 8, 9, 31-34.

### 5.1 Concrete spell-list / data edits, with the source of truth for each

`add` = put the name in `tools/spell_lists/<class>.json` (values then come from the store via the
overlay); `remove` = drop a dead name; `alias` = a `Forte_Core/Locale` name pairing;
`note` = a value no data source carries (a probe, never a hand-edit of a generated file).

| edit | class | name (id) | source of truth |
|---|---|---|---|
| add | paladin | `Oath of Light` (`1328548`, 300 000) | **data** (`Names`+`Misc`) ✓ post 9 |
| add | mage | `Ice Lance` (`400640`, cat `19`/8 000) | **data** ✓ post 9 |
| add | druid | `Ferocious Bite` (ladder head `1328618` L24) | **data** ✓ post 9 |
| add | druid | `Bloom` (`1328621`, 0 → announce layer) | data id, **post 9** for the law |
| add | paladin | `Shieldsworn` (`1328551` 6 000), `Echo of Fury`/`Echo of Command` (`1311701`/`1311703` 15 000), `Unsealed Wrath` (`1310735`) | **data** (`Names`+`Misc`+`AuraOptions`) |
| add | priest | `Dark Inspiration` (`1326168`, 10 000) | **data** |
| add | rogue | `Setup` (`13983`, icd 1 000, 0 window → proc layer) | **data** |
| add | shaman | `Windfury Totem` (`10613`, 300 000) | **data** (slot row) |
| add→deferred | warrior | `Reckless Swings` (15 s cd / 8 s window) | **post 9 text only** |
| add→deferred | rogue | `Shank` (L24, 10 s), `Death Mark` (10 s cd / 6 s mark), `Poised` | **post 9 text only** (ids `15248`/`1325756-8` value-less; `Poised` has no client name) |
| add→deferred | shaman | `Totemic Call` (`437009` renamed, 30 000) | **post 9 text**; client still says `437009 Totemic Projection 60000` |
| add→deferred | paladin | `Lightning Mastery` (alias of `16166`) | **post 9 text**; client keeps both names |
| add→deferred (10) | shaman/paladin/mage/druid/warrior | `Maelstrom Weapon 408505` (30 000), `Infusion of Light 437063` (15 000), `Forbearance 25771` (60 000), `Vengeance 20050` (30 000), `Vindication 440667` (30 000), `Fingers of Frost 400669` (15 000), `Ignite 412538` (4 000), `Clearcasting 16870` (15 000), `Deep Wounds 12834` (0), `Enrage 12880` (12 000) | **data** (`names.json` + store `Names`/`Misc`) |
| remove | paladin | `Salvation`, `Mass Salvation`, `Revoke`, `Blessing of Light` | **data** (names absent from `Names`; 4 ids in our `removed`) ✓ post 9 |
| remove | shaman | `Call of Thunder` mapping (keep `16120` as the scry spell only) | **data** (`16120` value-less) vs post 9's talent of the same name |
| note | warrior | Slam 18 000 → **15 000** (all 5 ranks, category `2412`) | **post 9** (msim `hotfix_113554.rs:378-381`); store says 18 000 |
| note | shaman | Stormstrike 8 000 → **6 000**; Riptide 6 000 → **12 000**; Chain Lightning cast 2 000 → **2 500** | **post 9** (msim carries the first and third; Riptide: nobody) |
| note | druid | Primal Bite pick `1238073` "Rank 4" → the store's ranked top `1238070` "Rank 3" | **data** (the store's ladder has 3 ranked rows + a value-less `1238073`) ✓ post 9 |

## 6. Must-regenerate list

| # | artefact | action | why (evidence) |
|--:|---|---|---|
| 1 | `tools/overrides_70707.json` | regenerate from `/tmp/wowsims-forever` @ `6e69a7f4` | overlay predates `2e0124c`; `3412→3870`, `541→583`, `removed 7`, `bookRanks 35`; store content unchanged so **no value deltas ride in** |
| 2 | `addon/Forte_{Druid,Mage,Paladin,Rogue,Shaman}/Data/*.lua` | `python3 tools/gen_spell_data.py <class>` | the 8 row deltas of §2.2 (rank label, shared categories, ICDs, feed losses) |
| 3 | `addon/Forte_{Hunter,Priest,Warlock,Warrior}/Data/*.lua` | same command | header/`_meta` stamp only; regeneration keeps `scripts/gate.py:180-202`'s determinism byte-compare honest |
| 4 | `tools/spell_lists/{paladin,mage,druid,shaman,rogue,priest}.json` | the §5.1 add/remove list | the client already carries `Oath of Light`, Ice Lance, the paladin proc family, `Setup`, `Dark Inspiration`; the paladin `removed` four are dead |
| 5 | `addon/Forte_Items/Data/Items.lua`, `Forte_ItemProcs/Data/Procs.lua` | **none** | mythicsim `data/*.jsonl` byte-identical; the wowsims item delta is `sources`-only (§2.4) |
| 6 | docs: `docs/research/data-diff-70707.md:76` (counts), `PLAN.md` §6 pins, `CHANGELOG.md` | update | the overlay's counts and `_meta.commit` change |
| 7 | re-run once, by the main agent: `python3 scripts/gate.py`; `test_tracked_set.lua`; `Forte_Timer/tests/test_kinds.lua:72` (Blizzard Channel), `test_module.lua:605` (Flamestrike), `Forte_Cooldown/tests/test_70707_overlay.lua:68,114` (rank text, `bookRanks`), `Forte_Paladin`/`Forte_Shaman` suites, `Forte_Core/tests/test_locale.lua:21-36` (Reckoning row `31216`) | verify | the deltas touch a rank label, two categories, one ICD and four feed columns |

## 7. What we should change (ranked)

1. **Refresh the overlay, then the class data** (items 1-3 of §6). Files:
   `tools/overrides_70707.json`, the 9 `addon/Forte_*/Data/*.lua`. Cost: one command each.
   Benefit: 458 ids of 70707 coverage for the Wave 2b names; shared categories for Blizzard
   (`2518`)/Flamestrike (`2506`); Holy Shock's rank label; Dismantle's ICD.
2. **Add the six data-carried names** (§5.1 rows `add`). Files: `tools/spell_lists/paladin.json`,
   `mage.json`, `druid.json`, `rogue.json`, `priest.json` + regenerated data. Highest display value
   per line: `Oath of Light` is a 5-minute tracked aura the client *already ships*, and Ice Lance
   completes Fire Blast's shared category `19` bar.
3. **Add the 10 resolvable deferred procs** (§3.1). Files: `tools/spell_lists/*.json`
   (`_deferred_H7` → a real group), `docs/class-port.md` §787 (the H7 gate). wowsims is MIT and
   name-verified; 8 of the 10 landed inside this range, so this is a moving target worth one
   `tools/` harvest step (a `names.json` → id resolver, with an exclusion list for the removed
   talents of row 25).
4. **Land the rename-alias layer before launch.** Files: `addon/Forte_Core/Locale.lua` (id↔name
   alias table), `addon/Forte_Shaman/Forte_Shaman.lua` + the announce tables,
   `tools/spell_lists/shaman.json`. Post 9 renames two tracked Shaman names (`Elemental Mastery` →
   `Lightning Mastery`, `Totemic Projection` → `Totemic Call`) that the client capture does **not**
   carry; our chains are name-keyed, so one alias table covers both directions and both builds.
5. **Stop 70707 picks from dropping base-data feeds.** Files: `tools/extract_70707.py` (capture
   `Effects.PeriodMs`, `Targets.Target`, `AuraOptions.MaxStack` — all present in the store, e.g.
   `9826 PeriodMs 3000`, `1326084` target row), `tools/gen_spell_data.py` (the feed law),
   `docs/class-port.md` (the feeds-are-base-data law). Removes the five feed losses measured in §2.2.
6. **A hotfix/dev-notes probe harness, not hand edits.** Files: `PLAN.md` §8 (risks),
   `docs/research/data-diff-70707.md`, a launch-day `/fx probe` list covering rows 1, 4, 5, 6, 7, 8,
   9, 16, 28 and the cast-time family (§2.5). The four Shaman/Warrior numbers with no data source
   stay out of the generated files: a generated file must stay a pure function of the pins
   (`scripts/gate.py:9` "generator determinism").
7. **Harden the rank law against value-less tops.** Files: `tools/gen_spell_data.py`
   (`pick_current_rank`), `docs/class-port.md` (the rank law), a new gate case. Primal Bite ships
   `Rank 4` (`1238073`, value-less in the store) while the store's ladder stops at `Rank 3`
   (`1238070`) — the same shape as the `Polymorph` → "Odd Melon" hazard of
   `data-diff-70707.md:169-171`. Rule: when the store covers a name, a picked id must carry store
   `subtext`/`SpellLevel`.
8. **Two cheap gate cross-checks.** Files: `scripts/gate.py`.
   (a) assert the pins: the store stamp is `1.60.1.70707`/`113562`, mythicsim's manifest is
   `1.60.1.70425`, and the overlay `_meta.commit` equals the clone HEAD we extracted from (this
   note's §2.1 drift becomes loud). (b) diff our `bookRanks` against
   mythicsim's `release/book-ranks.json` and report the symmetric difference (`25346` theirs-only;
   nine ours-only).
9. **Housekeeping in the lists.** Files: `tools/spell_lists/paladin.json` (drop the four
   `removed` names), `shaman.json` (keep `Call of Thunder 16120` as the scry spell, do not map the
   notes' talent of the same name), `rogue.json`/`warrior.json` (the net-new `_deferred_H7` names of
   §5.1).

## 8. Open questions

1. Which hotfix push carries post 9's numbers, and is it in the 2026-11-04 opening build? The
   capture says **no** for Slam / Stormstrike / Riptide / Lava Burst / Elemental Mastery /
   Totemic Projection; mythicsim keys its rows to `113554`, our store stamp is `113562`.
2. Righteous Fury: does the live client report `25780` (1 800 000 ms) or `407627` (`-1`,
   permanent-stance shaped)? Our pick is the former; the store has both.
3. Arcane Blast: is the 18-second stack aura (`400573`) reported under the *name* "Arcane Blast"
   (it is in `Names`), and if so how do we key a cast row and an aura row that share one name?
4. Do `Shank`, `Death Mark`, `Poised`, `Reckless Swings`, `Totemic Call`, `Lightning Mastery` (as
   the Elemental aura) get `13xxxxx`-family ids at opening? The store has only value-less Classic
   rows (`15248`, `16579-82`) or nothing at all.
5. Is wowsims' `sim/siml/names.json` stable enough to key a harvest on (it moved +437 leaves in 10
   days and its 414 `talentOnlyBy` entries are sim-scoped, i.e. *not* a client-completeness claim)?
