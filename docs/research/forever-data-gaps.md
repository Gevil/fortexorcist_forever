# D2 — Forever data-gap research (online + local)

Researched 2026-11-02 by agent `DataGaps`. Contract: PLAN.md §11.1 row **H10 Data refresh**
("which generator gaps closed? which proc ICDs / item durations resolved?").

Pins used throughout:

| Source | Pin | Cite |
| --- | --- | --- |
| Our generated data | client build **1.60.1.70425** | `mythicsim-forever-engine/data/manifest.json:2` |
| Upstream sim checkout | **1.60.1.70707**, hotfix push **113562** | `/tmp/wowsims-forever/assets/db_inputs/spell_store_inputs.json` keys `Builds`, `Hotfixes` |
| Installed client product | live 1.60.1.70707 (launch 2026-11-04) | PLAN.md §1 |

Method notes: the 70707 spell store is GZIP-compressed JSON; it was decompressed once to
`/tmp/datagaps/store.json` and every cross-check below is a join against it. "store" always means
that file's tables (`Names`, `Misc`, `Cooldowns`, `Levels`, `AuraOptions`, `ClassOptions`,
`Descriptions`). Counts marked *measured* are reproducible with the one-liners in
`/tmp/datagaps/{final,icdmatrix,itemdur,gen}.py`; anything not measured here is tagged
`[INFERENCE]`.

## Answer

Seven gaps. Two are **not** gaps (closed by data), five are real; one of the five is purely a
plumbing change in our own generators, one needs a live-client probe, and three are consequences of
the 70425 → 70707 drift that H10 exists to absorb.

| # | Gap | Status |
| --- | --- | --- |
| G1 | Generator reports **zero hard gaps**; the residual is 13 `uncoded fallback` + 21 `companion-row shadow` info lines — all 34 individually cross-checked against 70707 | **resolved** (2 accepted zero-window rows) |
| G2 | Proc **internal cooldowns exist in the source data and are dropped by both generators** (spell `ICDMs`, item `proc.icd_ms`) — the shipped addon carries no ICD at all | **open** (generator change; no data gap) |
| G3 | The original hard-coded hidden-ICD table (49 pairs) is **out of Forever scope** — 2 of 49 item IDs exist in Forever | **resolved** (drop it, rebuild from G2 data) |
| G4 | **Items with a buff and no duration: 259 entries** (onUse 54, procs 205). No local source carries a duration — the client's own 70707 spell rows all say `DurationMs 0` | **open → launch-day probe** |
| G5 | 70425→70707 drift in our own data: **5 paladin IDs removed**, 9 tracked names gone, **3 real value changes** (Shifting Power cd halved, Wild Growth gains a 3 s cast, Swift Judgement loses its window), **5 emitted rows are 70707 coverage holes** (no Misc/Cooldowns/ClassOptions row — zero names, zero values), 0 name drift, 6 family-code drifts | **open** (H10 refresh absorbs it) |
| G6 | **44 class-coded spell names exist in 70707 that our 70425 source has never seen** (104 family/name pairs) — the whole warlock pet kit + the new paladin/mage/druid lines | **open** (source-swap decision) |
| G7 | Patch/hotfix feed: Blizzard publishes **no per-spell hotfix list for Forever**; official deltas are the Beta Development Notes, and the machine-readable per-build deltas are community file diffs | **partially resolved** |
| G8 | Public DBs: four cover Forever well (one build-current at 70707), **none publishes ICDs**, and only one offers a licence for reuse | **resolved** (use as lookup, not as a pipeline) |

Nothing in this note is a *missing dataset*: for every gap the numbers that FX needs are either in
the 70425 pull (G2: 135 spell rows + 49 item procs), in the 70707 store, or genuinely absent from the
client tables (G4).

## G1 — Generator gap scan: 0 hard gaps, 34 audited resolutions

**What was checked.** `python3 tools/gen_spell_data.py <class> --dry` for all nine classes
(log: `/tmp/datagaps/gen.txt`):

```
dry druid:    52 spells, 0 gaps (build 1.60.1.70425)
dry hunter:   73 spells, 0 gaps
dry mage:     52 spells, 0 gaps
dry paladin:  56 spells, 0 gaps
dry priest:   47 spells, 0 gaps
dry rogue:    50 spells, 0 gaps
dry shaman:   61 spells, 0 gaps
dry warlock:  76 spells, 0 gaps
dry warrior:  64 spells, 0 gaps
```

531 emitted rows (`addon/Forte_*/Data/*.lua`), 0 gap lines, 13 `uncoded fallback` lines, 21
`companion-row shadow` lines. Mechanism docs: `tools/gen_spell_data.py:22-30` (uncoded-family
fallback), `:32-48` (companion-row shadows), rank rule `pick_current_rank` at `:133`.

**The 13 uncoded fallbacks — every one is a real spell with a real window in 70707** (measured,
store `Misc`/`Cooldowns` rows for the emitted IDs):

| class | name → emitted id | 70707 window |
| --- | --- | --- |
| hunter | Black Arrow → 14296 | fam 0, lvl 60, dur 30000, gcd 1500 |
| hunter | Eagle Eye → 6197 | lvl 14, dur 60000, gcd 1500 |
| hunter | Scare Beast → 14327 | lvl 46, cast 1500, dur 20000, cat 30000 |
| hunter | Tame Beast → 1515 | lvl 10, dur 20000 |
| hunter | Call Pet → 883 | lvl 10, dur −1 (permanent) |
| hunter | Dismiss Pet → 2641 | lvl 10, cast 5000 |
| hunter | **Feed Pet → 6991** | lvl 10, dur 0, cast 0, **no CD/GCD → zero window** |
| rogue | Vigor → 21975 | dur −1 |
| shaman | Far Sight → 6196 | lvl 26, cast 2000, dur 60000 |
| warlock | Soul Harvest → 1242853 | dur 10000 |
| warlock | Use Soulstone → 20761 | lvl 1, dur 0 (the 30 min buff is 20707/20762…, `Soulstone Resurrection`) |
| warlock | Firestone → 17949 | lvl 56, cast 3000, dur 0 |
| warlock | Spellstone → 1237159 | lvl 28, cast 3000, dur 0 |

The fallback is *load-bearing, not a workaround*: the same rows are `Family` 0/absent in 70707, so a
family-code-only resolver (the wowsims shape, `sim/core/spelldata/spelldatabase.go:346-348` notes
"Family 0 … shared racials") would drop all 13. The hunter list documents this at
`tools/spell_lists/hunter.json:2`.

Two accepted zero-window rows: `Feed Pet` (`Feed Pet` 6991 emits only `{ id, name }`) and
`Use Soulstone` 20761 (emits only `{ id, name }`). They cost nothing and keep the lists honest.

**The 21 companion-row shadows — resolved by the 70707 store.** Every shadowing bare row
(`20340`, `31025`, `415102`, `440672`, `440680`, `90092`, `90093`) and every picked row
(`20349`, `401417`, `428741`, `436516`, `440675`, `19312`, `19266`, `408514`, `408510`, `408525`,
`432041`, `408680`, `16387`, `403789`, `427714`, `426325`, `412800`, `426301`, `427726`, `426969`,
`403215`) exists in 70707 **under the tracked name** (`measured`, store `Names`), and the picked row
carries the window the class list wants (e.g. `20349 Seal of Light` dur 30000/gcd 1500,
`440675 Righteous Judgement` dur 8000, `19312 Shadowguard` dur 600000, `408514 Earth Shield` dur
600000, `403789 Metamorphosis` dur −1).

Why the picked id is not a tracking risk: the runtime never keys on the emitted `id`. Cast events
resolve `spellID → name` and key by name ("ids drift per build, names do not",
`addon/Forte_Timer/Core/Casts.lua:40-42`; `addon/Forte_Core/Core/Probe.lua:158-167` "the resolved
id, never the build-sensitive data id"; PLAN.md §8 "Spell IDs are build-sensitive (measured
2026-11-01 in `test_engine.lua`)").

**Fix:** none required. Keep the two info channels (they are what made this audit possible); pin
explicit `ids` in the spell lists only if a future build's family codes move.

## G2 — Proc internal cooldowns are in the data and dropped by the generators

**What is missing.** FX ships **no** ICD data. `measured`: 0 lines containing `icd` in
`addon/Forte_Items/Data/Items.lua` (277 KB generated file) and no `AddHiddenCooldown`-equivalent
registry in `addon/Forte_Cooldown/`. Both generators read files that carry the value and drop it:

- spells: `tools/gen_spell_data.py:159-173` emits `id, name, durationMs, cooldownMs,
  cooldownCategory, gcdMs, castMs, rank` — no ICD.
- items: `tools/gen_item_data.py:14` documents the source field
  "`proc` … `proc.proc_chance` / `proc.icd_ms`" and never emits it.
  **The item/enchant half has since landed (D2/M, 2026-11-02): 51 rows carry `icdMs` (49 item
  proc rows — now in the load-on-demand `Forte_ItemProcs` after H7 — + 2 enchant rows in
  `Forte_Items.enchantProcs`), and `Forte_Cooldown/Core/Procs.lua` consumes it as the length of
  a proc's ICD window on the bar (H7, `Cooldown.Procs`, default off). The SPELL half of this
  row (the 11 class-list `ICDMs`) is still not emitted.**

**What the sources hold** (all measured):

| source | ICD-carrying rows |
| --- | --- |
| `mythicsim-forever-engine/data/spells.jsonl` (`ICDMs`) | 135 rows, 114 distinct names |
| 70707 store `AuraOptions[*].ICDMs` | 115 of 3,112 rows, 94 distinct names |
| `/tmp/wowsims-forever/sim/core/spelldata/spells_auto_gen.go` | 116 rows with `ICDMs:` |
| `mythicsim …/items.jsonl` (`proc.icd_ms`) | 49 rows |
| `/tmp/wowsims-forever/assets/database/db.json` (5,226 items / 247 enchants / 430 consumables) | 9 rows |
| `enchants.jsonl`, `consumables.jsonl` | 0 rows |

Cross-source agreement is clean: the 94 store ICD names are a subset of the 114 mythicsim ICD names,
**0 value disagreements**, and for the 11 class-list spells below the emitted-ID lookup agrees to
the millisecond. So the value is not in dispute — only the plumbing.

**The 11 class-list spells that need an ICD** (name → the row carrying it, ms; store value in
parentheses where the emitted ID carries it):

| class | spell | ICD |
| --- | --- | --- |
| paladin | Divine Protection (27778) | 60000 |
| paladin | Seal of Command (20375…20920, all ranks) | 1000 ✓ on emitted 20920 |
| paladin / rogue | Rebuke (1302716) | 60000 |
| priest | Shadowguard (18137…19312) | 3500 ✓ on emitted 19312 |
| shaman | Lightning Shield (324…23552) | 3500 |
| shaman | Earth Shield (408514) | 3500 ✓ emitted |
| shaman | Water Shield (408510) | 3500 ✓ emitted |
| shaman | Flurry (16257) | 500 ✓ emitted |
| shaman | Windfury Weapon (439431) | 1500 |
| warrior | Taste for Blood (426953) | 5800 |
| warlock | Immolation Aura (427726) | 1000 ✓ emitted |

Note the trap: the ICD often rides a *different rank row* than the one the rank rule emits
(Divine Protection ICD on 27778, paladin emits 5573; Lightning Shield ICD on 324…, shaman emits
28821; Windfury Weapon on 439431, we emit 16361). An ICD lookup must be name+family-scoped, not
"the emitted row's field", or 5 of these 11 read as "no ICD".

**Item/enchant procs with a `proc.icd_ms`** — 49 rows; 9 are cross-confirmed by the 70707 store's
`AuraOptions.ICDMs` for the proc's aura spell, the other 40 have **no store ICD** and need a probe.
The 9 confirmed: Hand of Justice 11815 (aura 15600/15601) 2 s; Invulnerable Mail 12641 (16620/16621)
10 s; Darkspear 12802 (16939 → store 1314143) 60 s; Force Reactive Disk 18168 (22618, 22620) 1 s;
Jagged Obsidian Shield 22198 (27561) 20 s; Unbalanced Idol 210195 (424339, 424336) 1 s; Cleansed
Ritual Kris 275647 (1297370) 0.1 s. The 40 unconfirmed include the long ones FX's F15
(trinket-ICD-aware windows) cares about: Force of Will 11810 30 s, Orb of Fire 12805 8 s, Argent
Defender 13243 20 s, The Lion Horn of Stormwind 14557 60 s, Shard of the Scale 17064 10 s, Spinal
Reaper 17104 10 s, Mark of the Chosen 17774 120 s, Zum'rah's Vexing Cane 18082 60 s, Blade of
Necromancy 22332 120 s, Guardian's Dualblade 273046 60 s, and the Timeworn signet family
(234017/234021/234026/234030/234034/234198…234202) at 200 ms on `Timeworn Strike 1213390` /
`Timeworn Shot 1213395`.

**Why it matters.** F15/F16 (PLAN.md §3.2) size trinket windows from the ICD; without it FX shows a
proc window that re-lights early on the second proc, and the 60 s/120 s cases (Mark of the Chosen,
Blade of Necromancy, Lion Horn, Zum'rah's, Guardian's Dualblade) are exactly the "hidden cooldown"
class the original hard-coded.

**Fix (all local, no data gap):**
1. `gen_spell_data.py`: add `icdMs` to `emit_entry` (`:159-173`), value = max non-zero `ICDMs` over
   the name's family-scoped rows (the rank-trap above), `0`/absent when none.
2. `gen_item_data.py`: emit `procIcdMs` for `procs` rows from `proc.icd_ms`.
3. `Forte_Cooldown`: read a generated `FX.Data.<Class>` / `FX.Data.Items.icds` map — the shape the
   original used at `/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua:1636-1693` — and keep a small
   hand list for probe-measured values (the 40 unconfirmed item ICDs, Touch of the Grave 15 s).
4. `Forte_Items/Data/Items.lua` regeneration is deterministic + `scripts/gate.py` determinism check,
   so the added fields are gated.

## G3 — The original hard-coded hidden-ICD table is out of scope

`/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua:1636-1693` is 49 `AddHiddenCooldown(item, buff,
seconds)` pairs (Darkmoon Card Set 11815/15600/15601 2 s, Invulnerable Mail 12641/16620 10 s, The
Restrained Essence of Sapphiron 23046/28779, Zandalarian Hero Charm 19950/24659, …).

Measured: **2 of the 49 item IDs exist in Forever's `items.jsonl`** (23046, 19950) and **2 of the 49
buff spell IDs exist in the 70707 store** (28779, 24659). The rest are Classic-era Vanilla
trinkets/sets Forever never shipped.

**Status: resolved.** Do not port the table; port the *mechanism* and feed it G2's generated data
(3 of its surviving entries — 11815, 12641 — are already in G2's confirmed list, so they cost
nothing).

## G4 — Items with a buff and no duration (259) — launch-day probe

**What is missing.** `python3 tools/gen_item_data.py --dry` reports
`report: entries with a buff but no duration: onUse=54 procs=205`
(`tools/gen_item_data.py:296`; the same fact is written as a comment into the generated file at
`:322`). Reproducing the generator's own selection over `items.jsonl` gives 259 rows: 54 on-use, 205
proc.

**Every local and public source checked, and none has the duration** (measured):

| source checked | result |
| --- | --- |
| 70707 store `Misc[buff_id].DurationMs` | all **259 rows have a spell row**, and every one is `DurationMs 0` (0 positive) |
| 70707 store `Descriptions[buff_id]` | 3 of 259 carry an explicit duration in text: `Reckless Charge 22641` "for 30 seconds" (Horned Viking Helmet 9394, Goblin Rocket Helmet 10588), `Gift of Life 23725` "for 20 sec" (Lifegiving Gem 19341) |
| `mythicsim …/spells.jsonl` join on the parenthesised aura id | 112 rows have a spell row, all `DurationMs` 0/−1; 147 have no spell row at all |
| `/tmp/wowsims-forever/assets/database/db.json` (5,226 items, 247 enchants, 430 consumables) | resolves **0 of 259** |
| `/tmp/wowsims-forever` docs (`docs/spell_data/{procs,store,overrides}.md`) | documents the proc shape (`procs.md:122-140`: the buff's row supplies the duration) — no table of them |
| Zephras item page for item 234017 (build 1.60.1.70685) + spell page 1298413/15600 | publishes the effect text with **no** duration |
| bindonforever item 18168 / spell 1298413 pages (build 1.60.1.70707) | same: text only, no duration field |

The split matters more than the missing numbers (measured over the 259 rows' buff names; 133
distinct names):

- **113 of 259 are proc-cast damage/utility spells, not self-buffs** — `Shadow Bolt` 23,
  `Building Inspiration` 25, `Wound` 12, `Lightning Bolt` 12, `Firebolt` 10, `Timeworn Strike` 10,
  `Timeworn Shot` 10, `Frost Blast` 9, `Fatal Wound` 5, `Drain Life` 4, `Heal` 3, `Rage` 3 …
  These have no self-buff window at all; the proc *casts* a spell at the target. FX's F14/F15
  (item proc windows) must not size a window for them.
- **146 remain** as proc-on-hit / on-use self-effects with a real, unrecorded duration (Gloves of
  Holy Might 867 → 1325229, Flurry Axe 871 → 18797, Hand of Justice 11815 → 15600/15601, Blade of
  Hanna 2801 → 1325535, Stoneslayer 9418 → 12731, Crest of Retribution 13375 → 17495, …).

**Why it matters.** F14's proc windows and F15's ICD-aware windows are sized from
`effect_duration_ms`; a nil duration means the window is invisible, i.e. a silent coverage hole for
259 of the ~650 tracked item effects.

**Status: open → launch-day probe** (with the 3 text-carried durations harvested now). Proposed:

1. Data-side split, doable in D3: tag the 113 proc-cast rows (`procCast = true`, no window) from
   the buff name's spell-row shape, so F14 stops looking for a duration that does not exist.
2. Harvest the 3 description-carried durations by an explicit generated list (not a text regex over
   the whole file — `$d`/`for N sec` is only 3 hits of 259, so a regex pipeline buys nothing).
3. Live probe (F1/F14 kit, first client session, PLAN §8 item D): for the 146 buff IDs, log
   `SPELL_AURA_CREATED`'s duration for the player (one proc per item, stationary target) into a
   probe file, and land the measured values in a hand-maintained `tools/item_proc_durations.json`
   that `gen_item_data.py` merges. 146 items × one proc each is a short session; the Timeworn
   signet family and the `Building Inspiration` set cover many rows each.

## G5 — 70425 → 70707 identity drift inside our own shipped data

Measured by joining every emitted row's `id` against the 70707 store (`531` rows; 526 IDs present):

**Removed IDs (5, all paladin)** — `addon/Forte_Paladin/Data/Paladin.lua` tracks spells that are
gone from the client files:

| emitted | name | 70707 |
| --- | --- | --- |
| 19979 | Blessing of Light | no row |
| 25890 | Greater Blessing of Light | no row |
| 1038 | Salvation | no row |
| 25895 | Mass Salvation | no row |
| 1325499 | Revoke | no row |

The paladin list asks for them: `tools/spell_lists/paladin.json:24` (`"Purify", "Revoke",
"Redemption"`) and `:35` (`"Greater Blessing of Light", "Blessing of Light", "Salvation",
"Mass Salvation"`). They are documented removals in the community build diffs (build 70009 already
shows `Greater Blessing of Light 25890 — rank: Rank 1 → none`), i.e. exactly what the launch build
ships.

**Names in our source with no 70707 row (9):** `Elemental Precision`, `Improved Fireball`,
`Explosive Trap Effect`, `Greater Blessing of Light`, `Instrument of Law`, `Mass Salvation`,
`Revoke`, `Salvation`, `Twist of Light`. Six are explained by published renames/removals in build
70707 (bindonforever's 70707 page: `name: Improved Fireball → Accelerant`, `name: Elemental
Precision → Precision`, `name: Explosive Trap Effect → Explosive Trap` ×3 ids) plus the paladin
removals above.

**Three genuine same-ID value changes** (our 70425 → the 70707 store's `Misc`/`Cooldowns`):

| spell (id) | field | 70425 | 70707 |
| --- | --- | --- | --- |
| Shifting Power (1322605) | `CooldownMs` | 16000 | **8000** (halved) |
| Wild Growth (1238215) | `CastTimeMs` | 0 (instant) | **3000** (hard 3 s cast) |
| Swift Judgement (1310994) | `DurationMs` | −1 | **0** (row stops carrying a window) |

`Shifting Power` halving is tracking-critical (a 16 s assumption under-flags nothing, an 8 s one over-
flags); `Wild Growth` acquiring a hard cast changes cast-finished handling (§4 cast-finished rule);
`Swift Judgement`'s window going 0 means the emitted row stops tracking a window.

**Five emitted IDs are coverage holes in 70707, not zeroed values.** `Primal Bite` (1238073),
`Searing Blast` (16454), `Cripple` (18381), `Howling Blade` (13490), `Summon Voidwalker` (25112) exist
in 70707 `Names` but carry **no `Misc` row, no `Cooldowns` row, and no `ClassOptions` row** (measured).
The store has 32,052 `Names` against only 8,001 `Misc` and 2,348 `Cooldowns` rows, so an absent row
means *"not in this export"*, **not** *"the value is 0"*. The earlier reading of these five as
"cooldownMs 6000 → 0" / "durationMs 30000 → 0" is therefore **not supported by the data**: they are
coverage holes, and no local source states their live values. Consequences:
- the §4/§11 note "`Primal Bite` is a real 0 CD in the live client (probe on 11-04)" (recorded
  2026-11-02) is a **70425 fact, unresolved for the launch build** — the 70425 row does show
  `cooldownMs = 6000`, so even for 70425 the "0 CD" claim needs its source named;
- these five + the five removed paladin IDs = **10 of the 531 emitted rows that cannot be confirmed
  against the launch build from any local source** — the strongest argument here for a launch-build
  re-pull via `wago.tools`' build+hotfix DB2 route (G7).

**Family-code drift (measured, 6 of 531):** the same five spells are exactly the ones that lose their
`ClassOptions` row (`Family` 7/3/4/4/5 → no row); the sixth, `Black Arrow` (14296), gains an explicit
`Family = 0`. So family-coded lookups (the fallback in `gen_spell_data.py`) silently stop resolving
these five between the two builds.

**No drift found in:** same-ID name equality (0 of 526, measured). The paladin `Seal of *` /
`Judgement of *` lines and the mage `Frost Strike` name-collision row (D1) confirm IDs are stable;
the movement is in *rank sets* and *row coverage*, not identities.

**Status: open.** It is H10's own subject: pin the pull to the launch build (≥70707), re-run the
nine `--dry`, and drop the 5 paladin names from `paladin.json` in the same commit, then regenerate
and re-run `test_data.py` (which asserts name-equality, PLAN §8(b)).

## G6 — 44 class-coded spells exist in 70707 that our 70425 source has never seen

Measured: store `ClassOptions` gives 4,024 rows in families 3…11 (1,854 distinct names); of those,
**44 distinct names (104 family/name pairs) have no row at all in `spells.jsonl` (70425)**. This is a *source-coverage* gap, not a
generator bug: no name-list change can reach them.

The load-bearing 22 are the **warlock pet kit** — Family-5-coded rows in 70707 whose names do not
exist in our 70425 pull at all: Consume Shadows, Devour Magic, Devour Magic Effect, Eureka! (the
gnome racial, family-coded per race), Fire Shield, Inferno, Lash of Pain, Lesser Invisibility,
Paranoia, Sacrifice, Seduction, Soothing Kiss, Soulstone Resurrection, Spell Lock, Suffering,
Summon Felhunter, Summon Imp, Summon Incubus, Summon Succubus, Tainted Blood, Tainted Blood Effect,
Torment. Our list has only the two Family-5 summons the 70425 pull does carry
(`tools/spell_lists/warlock.json:26` — `Summon Voidwalker`, `Summon Felguard`); the other four
summons and every pet ability are absent. Measured windows (store `Misc`/`Cooldowns`/`Levels`):

| spell (id) | 70707 window |
| --- | --- |
| Summon Imp (688, lvl 1) | cast 10000, dur −1, gcd 1500 |
| Summon Succubus (712, lvl 20) / Summon Incubus (713) | cast 10000, dur −1, gcd 1500 |
| Summon Felhunter (691, lvl 30) | cast 10000, dur −1, gcd 1500 |
| Torment (3716/7809…11775) | cat 5000 (5 s taunt) |
| Soothing Kiss (6360…11785) | cat 4000 |
| Devour Magic (19505…19736) | cat 8000 |
| Spell Lock (19244 lvl 36 dur 6000; 19647 lvl 52 dur 8000) | cat 30000 (the pet's kick) |
| Lash of Pain (7814…11780) | cat 12000 |
| Suffering (17735…17752) | cat 120000 (2 min) |
| Seduction (6358, lvl 26) | cast 1500, dur 15000 |
| Sacrifice (7812…19443) | dur 30000 |
| Consume Shadows (17767…17854) | dur 10000 |
| Tainted Blood (19478…19660) | dur 60000 |
| Fire Shield (2947…11771) | dur 180000 (3 min) |
| Lesser Invisibility (7870) | dur 300000 (5 min) |
| Inferno (1122, lvl 50) | cast 2000, dur 15000, cat 3600000 (1 h) |
| Paranoia (19480) | dur −1 |
| Soulstone Resurrection (20707…20765) | cast 3000, dur 1800000 (30 min) |

`Subjugate Demon` (1098, 11725-8 in 70425; 20882 added in 70707) *is* in the list, so the rename
question is closed — `Enslave Demon` has no row in either build, the rename being a Blizzard-wide
2026 terminology change
(`us.forums.blizzard.com/en/wow/t/enslave-demon-is-now-subjugate-demon…/2313764`).

One cross-project correction: PLAN.md §11 (Iteration G, 2026-11-02) records "Forever 1.60.1 has no
Seduction, Mesmerize, Devour Magic or Spell Lock" — measured against **70425** (`spells.jsonl` plus
the sim client's ID range). In 70707 all three named spells are Family-5 rows with windows (table
above), so the dropped pet-cast rows should be re-tested against the launch build before FX-10
ships.

The remaining 22 names are the new class/racial lines: `Accelerant`, `Lunar Invititation`,
`Predatory Discipline`, `Holy Binding`, `Alterac Spring Water`, `Bloom`,
`Feral Charge (Bear)`, `Feral Charge (Cat)`, `Engrave Pants - Cutty's Rune`, `Adder Pheromone`,
`Battle Standard`, `Deer Musk`, `Prairie Dog Musk`, `Rabbit Musk`, `Boundless Light`,
`Oath of Light`, `Shieldsworn`, `Stoicism`, `Turn Evil`, `Unsealed Wrath`, `Rockbiter Weapon Proc`,
`Warlock Pet Scaling`. The paladin six (`Unsealed Wrath`, `Oath of Light`, `Boundless Light`,
`Shieldsworn`, `Stoicism`, `Turn Evil`) are the renamed/added Retribution line the paladin notes
describe (`Twist of Light → Unsealed Wrath`, `Voice of Truth → Oath of Light`).

**Status: open.** Options: (a) H10 re-pins to ≥70707 and these arrive free; (b) interim: add an
optional second `--spells-jsonl` from the 70707 store (the generator already takes the flag,
`tools/gen_spell_data.py:52`) with the store's `Family`/`SpellLevel`/window columns mapped to the
mythicsim field names, used *only* for names the 70425 file lacks, and stamped into the generated
header's source note. Recommended: (a), with (b) as the warlock pet-kit unblocker for FX-10.

## G7 — Patch/hotfix notes since the 70425 beta build

**Official (primary) sources checked:**

- `worldofwarcraft.blizzard.com/en-us/news` — launch/pre-purchase/news only; the 2026-10-30
  "Hotfixes" article covers Midnight, Mists of Pandaria Classic, Season of Discovery, Burning
  Crusade Classic, Classic Era, Hardcore — **no WoW: Forever section**
  (`wowhead.com/blue-tracker/news/us/hotfixes-october-30-2026-world-of-warcraft-blizzard-news-24307310`).
  ⇒ There is **no official per-spell hotfix changelog for Forever.**
- Official Beta Development Notes (the authoritative post-70425 deltas, via the
  `patchbot.io/games/world-of-warcraft-forever` mirrors of the `us.forums.blizzard.com` posts):
  - **Oct 26 + Oct 27 addendum** (`articles/1965-…`, `articles/1966-…`): Orc **Blood Fury cooldown
    3 min → 2 min**; Undead **Touch of the Grave internal cooldown 25 s → 15 s**; Troll
    **Berserking duration 10 s → 15 s**; Human Ruthless 2 %→1 %, Human Spirit 5 %→10 %; Dwarf Earth
    Fury removed → Artisan's Precision; Tauren Plainsrunning 1 %→2 %/stack, Endurance to +5 %
    Health only; Orc Savage removed, Command re-added; Skyborne Wind-Blessed 3 %→2 %, Read Leyline
    100 %→50 % regen (15 s), Skysight 10 %→15 % (15 s), Attuned/Charged 1 h buffs.
    None of the four racials (`Blood Fury 20572/24571`, `Touch of the Grave 1260189/1260198/1260201`,
    `Berserking 20554/23505/24378`) carries a usable cooldown/duration/ICD in the 70707 store's
    `Misc`/`Cooldowns`/`AuraOptions` — every value there is absent or 0 (measured) ⇒ the racials live in tables the spell store does
    not carry; FX's racials must come from the notes + a probe, not from this data.
  - Oct 15 / Oct 8 / Oct 1 notes (`articles/1810-…`, `1725-…`, `1658-…`): the pre-pin wave (the 24 s
    Devouring Plague, Arcane Wrath's 6 s CD, the paladin `Frost Strike` name collision) — all already
    inside our 70425 pin.
- Blizzard's own hotfix signal available to tools: the 70707 store's `Hotfixes` group, pinned to push
  **113562** (`/tmp/wowsims-forever/assets/db_inputs/spell_store_inputs.json`). That is the only
  machine-readable post-build change set we have locally.

**Machine-readable per-build deltas (community, file-derived) — the best "what changed after
70425" list found:** bindonforever.com `/changes` (23 builds archived, latest 70707, field-by-field,
"5,724 spell and item changes across beta builds"):

| build | date | class abilities | other spells | items |
| --- | --- | --- | --- | --- |
| 70425 (our pin) | Oct 16 | 451 | 1,110 | 276 |
| 70450 | Oct 16 | 0 | 22 | 23 |
| 70630 | Oct 27 | 60 | 72 | 15 |
| 70658 / 70634 | Oct 27–28 | no spell/item changes | | |
| 70685 | Oct 28 | 0 | 1 | 0 |
| **70707** | Oct 30 | 65 | 132 | 35 |

Post-70425 deltas that touch FX's tracked windows (from `/changes/1.60.1.70630` and
`/changes/1.60.1.70707`):

- **Ice Lance (mage, 1312002) `shared cooldown: none → 8 sec`** (category 19). Our 70425 row for
  1312002 has no cooldown; the 70707 store shows `cat 8000` (measured). A tracked mage cooldown
  appears in the launch build that our data does not show. (`Ice Lance` is not in
  `tools/spell_lists/mage.json`, so nothing breaks today — it is a list gap, D1/D3.)
- **Arcane Wrath (mage, 1326079) `shared cooldown: none → 6 sec`** in 70630 — already 6000 in our
  data (the 70425 build carried it), so no drift for us.
- **Explosive Trap Effect → Explosive Trap** renames (13812, 14314, 14315) in 70707 — closes the
  `Explosive Trap Effect` name gap in G5.
- **Righteous Fury (paladin, 25780) level learned 16 → 10**; **Aspect of the Hawk** ranks 1–5
  (13165/14318-14321) values cut ~50 %; **Bane of Agony (980)** gains a dummy effect;
  **Sap (2070)** mechanic `knockout → sap`; **Bloodthrill (1289681)** duration 6 s → 5 s;
  **Lesser Intellect (3166)** 60 min → 30 min; **Quitter (1299099)** 5 min → 40 s;
  one removal (camping spell 1328862); 35 items added/renamed (the Warden's/Initiate's/Tracker's
  Signet family, Superior Healing/Mana Potions, Swiftness Potion).
- Third-party aggregators carrying the same hotfix deltas (checked, secondary):
  `wowforevertalents.com/patch-notes` (hotfix over 70685, 216 changes; the Oct 26 racials verbatim),
  `foreverchanges.pro/patch-notes`, `wowfdb.com/classes/<class>/changes/`.

**Status: partially resolved.** Official deltas exist only as dev notes; the per-build file deltas
exist (bindonforever) and are consistent with every local measurement made here.
**Fix:** make H10's diff step run against a 70707+ pull and cite the bindonforever build page for
each accepted delta; keep a `docs/research/patches/` note per launch-week hotfix; treat
`Hotfixes=113562` as the pin to compare against, not a source.

## G8 — Public databases covering Forever: coverage, build, licence

| site | coverage | build it claims | licence / terms (as published) |
| --- | --- | --- | --- |
| **bindonforever.com** | items, item sets, spells, recipes, quests, talents, per-record **History** (build-by-build field changes), `/changes` build diffs, `/notes` (each Blizzard notes line checked against the files: 1,057 lines from 13 posts) | pages stamp **1.60.1.70707** | Terms of use (updated 2026-11-01) §3: linking fine, short quotes with a link fine, **bulk copying/scraping/mirroring of the database not allowed**; §2 fan project, game data belongs to Blizzard; §4 self-described accuracy limits |
| **zephras.com/forever/enUS** | 24,005 items, 31,935 spells, 475 quests, 1,960 NPCs, 112 Legacy challenges, talent/legacy calculators, `/forever/enUS/numbers/{items,spells,builds}.csv` (new/changed-vs-Classic + **per-build added/changed/removed** tables), `/data/forever/enUS/talents/<build>.json` | shows **1.60.1.70685**, banner: 70707 seen on Blizzard's version list 30 Oct 18:47 +04:00 | **CC BY 4.0** for Zephras' own selection/arrangement/derived values (talent JSON, tooltips embed), attribution required; spell/item names, texts, icons remain Blizzard's |
| **wow-forever.gg** | 29,507 spells with IDs, class/school browse, "New in Forever" 3,216 / "Changed in Forever" 4,197 tags, `/unreleased` (841), items/sets/quests/auction | page stamp **1.60.1.70532** (2 builds stale) | privacy page (PostHog optional); no data licence published |
| **wago.tools** | `/builds`, `/hotfixes`, `/db2` raw table browser — the same client-table route wowsims' exporter (`tools/database/exporters`) consumes | build selector (the browser's default showed a Midnight build, 12.1.7.70424; Forever builds are listed per build) | no data licence published; PLAN.md §4:281 records our 70425 pull as "72 of wago's exports" |
| **wowhead.com/forever/** (`/forever/items`, `/forever/spells/…`) | full DB sections exist (search-index titles "Forever Items"/"Forever Spells") | not observable from our fetcher: every `/forever/*` page returned **HTTP 403** (bot-blocked) | forum: "we don't allow outright scraping, especially of content that is unique to Wowhead" (`wowhead.com/classic/it/forums/topic/scraping-specific-items-data-from-wowhead-337684`) |
| thewowdb.com/wow-forever, metaforge.app/wow-forever/database/spells, warcraftforever.games, talentsforever.com, wowforevertalent.com, talents.page, wowforeverbuilds.com | general DBs / talent tools / news; the last publishes a free MIT character-export addon | not checked per-page | not checked |

Two findings that matter for D3's "public-DB cross-check" line:

1. **No public DB publishes internal cooldowns.** Spot checks: Zephras spell 15600 (Hand of
   Justice, 1 % chance on melee hit) shows text only, no ICD; Zephras spell 1298413 and
   bindonforever spell 1298413 (Iceblade Hacker) show text only; bindonforever's build diffs report
   "shared cooldown" categories, not ICDs. ⇒ ICDs come from the client tables (`AuraOptions.ICDMs`,
   `proc.icd_ms`) or from in-game measurement — never from a website.
2. **Only Zephras licenses reuse** (CC BY 4.0, and only for its derived files). Everything else is
   "link, don't mirror", and all of it says the names/text/icons are Blizzard's. ⇒ Use these sites
   for **spot-verification and change-lead hunting** (bindonforever's build pages are the best
   lead source, Zephras' CSVs the cleanest per-build counts), and keep the pipeline on the client
   files (wago exports / the installed client). Never bulk-mirror a site.

## Launch-day probe list (for D4's probe kit)

1. **The 21 companion-shadow spells** — for each, cast it and log the `SPELL_CAST_START` and
   `SPELL_AURA_CREATED` spellIDs: confirms the emitted id is the id on the wire.
   (Low severity: FX keys by name, `Casts.lua:40-42`.)
2. **146 item self-buff durations** (G4 list) — log `SPELL_AURA_CREATED` duration per item proc;
   land in `tools/item_proc_durations.json`.
3. **40 item/enchant ICDs** (G2 list, `proc.icd_ms` with no store confirmation) — 60 s of logged procs
   per item, compare the observed proc gaps to `icd_ms`.
4. **Racial windows** (Blood Fury 20572, Touch of the Grave 1260189…, Berserking 24378) — the 70707
   spell store carries no cooldown/duration/ICD for them; read the live spell tooltip/CD, matching
   the Oct 26/27 notes (2 min / 15 s / 15 s).
5. **Warlock pet kit** (G6: 26 spells incl. `Spell Lock 19244/19647` kick, `Suffering 17735+` 2 min,
   `Inferno 1122` 1 h) — confirm the 20882 `Subjugate Demon` addition and the pet-ability windows
   before FX-10 is built on them.
6. **The 5 paladin removed IDs** — cast-attempt each in the live client to confirm they are gone
   before deleting the paladin list entries (G5).

## Open questions

1. **D3 source-of-record** (the decision this note exists for): re-pin `gen_spell_data.py` /
   `gen_item_data.py` to a 70707+ pull of mythicsim, to the wowsims 70707 store (+ `db.json`) as a
   second source, or to a wago export of the launch build? Evidence: (a) the store adds the 44
   class-coded spells (G6) and every 13+21 G1 resolution; (b) the store has **no** item
   `internal_cooldowns`-style table and 0 of the 259 durations (G4) — the item tables of
   `mythicsim …/items.jsonl` are the only source for `proc_chance`/`icd_ms`/proc shape; (c) the
   70707 store's zeroed hero-row windows (G5) argue for name+family-scoped reads, not raw row picks.
   Recommended: 70707+ store for spells, mythicsim items for item effects, both stamped with build +
   hotfix push.
2. **Hotfix authority**: nothing local maps hotfix push 113562 to individual field values; the
   community per-build pages do not expose hotfixes separately from builds. Do we need a hotfix
   pin in `manifest.json`, or is "build ≥ launch build" enough?
3. **G4 shape question**: is the 113-row proc-cast family's true "window" the *target-side debuff*
   (which FX does not track today)? F14's spec says item procs light FX windows; if the debuff is
   the answer, that is a new feature, not a data gap.
4. **Racial data**: the 70707 spell store carries no racials table. Does the launch pull (mythicsim
   or a wago `SpellNames`/`PlayerClass`-adjacent export) cover racials at all, or do the four
   tracked racials stay hand-maintained from the dev notes?
5. Do we accept Zephras' CC BY 4.0 per-build CSVs into `docs/research/patches/` (attribution line
   required), or cite-only?
