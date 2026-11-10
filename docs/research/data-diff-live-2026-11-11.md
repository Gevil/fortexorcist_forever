# Data refresh: 70862 -> 70888 / push 113904 (2026-11-11)

Follows `docs/research/data-diff-live-2026-11-10.md`. Working tree, uncommitted; no git command that changes anything was run.

## Answer first

1. **Tuesday's (2026-11-10) class changes are NOT in the tracked data.** Between the 70862 and 70888 stores, 2 of 4053 spell ids changed any field. Only one is tracked: Warlock `Bane of Havoc` 1225228 gained `gcdMs = 1500`. Every other tracked row, in all nine classes plus Items and Procs, is identical field for field.
2. **Warlock rows equal the pre-change baseline** (`live-warlock-2026-11-09.md`): Corruption 18 s / 3 s tick, Bane of Agony 24 s / 2 s, Siphon Life 30 s / 3 s, Wrack 6 s channel / 1 s tick, Immolate 15 s / 3 s. No tick period moved.
3. **Why Wrack shows nothing:** "Wrack speeds up the warlock's dots" is not a period or duration in the store. wowsims models it at run time from Wrack's dummy effect (`sim/warlock/wrack.go`, `wrackSpeedup`: `1 + Wrack.EffectN(2).Percent()`). The overlay does not capture that effect. This is a mechanic the Forte_Timer data feed does not model; I did not add one (needs a design decision, no data column).
4. Voidwalker and Hunter pet changes are creature stats, with no spell-store field (as predicted in the Warlock report). Enhancement: no tracked row moved.
5. **No new decoy re-picks.** Every tracked name resolves to the same id as before (0 id changes, 0 rows added or removed). Pins from 2026-11-10 (Thorns 9910, Summon Voidwalker 697) still hold. **No pins added.**
6. **Tests: all 8 suites green, 0 re-pinned.**

## Inputs

| input | value |
| --- | --- |
| `/tmp/wowsims-forever` | `c1c29def` (store `1.60.1.70888`, hotfix push 113904; was `5f766b07` / 70862 / 113890) |
| mythicsim | `c29fefcf` (not pulled) |
| stamps | all spell groups and items on one build/push, `mixed: false`, `--allow-mixed` not needed |
| overlay | `tools/overrides_70888.json` (new, 668201 bytes); 70862/70790/70707 kept as history |
| pointer | `LIVE_OVERLAY` at `tools/gen_spell_data.py:264`, the only place; `scripts/gate.py` parses it, so no gate edit (it hard-codes no 70862) |

## Store census 70862 -> 70888

ids 4053 -> 4053 (+0 / -0), `nameIndex` 608 -> 608 (identical mapping; the checked-in 70862 overlay also holds 608, the 601 quoted in the 2026-11-10 report was that run's count), `removed` and `bookRanks` identical. Two ids with a changed field:

| id | name | tracked | changes |
| --- | --- | --- | --- |
| 1225228 | Bane of Havoc | yes (Warlock) | `gcdMs` None -> 1500; `cooldownMs` None -> 0; `categoryCooldownMs` None -> 0 |
| 439440 | Windfury Weapon | no | `category`, `durationMs`, `castMs` None -> 0; `family` None -> 11; `subtext` None -> Rank 1; `v` None -> 1 |

Both are coverage gains (a field the previous capture had no row for), not value changes.

## Table of every changed field in generated data

| class | row | file | old | new |
| --- | --- | --- | --- | --- |
| Warlock | Bane of Havoc 1225228 | `Warlock.lua:23` | `{ durationMs = 300000 }` | `{ durationMs = 300000, gcdMs = 1500 }` |

That is the complete list: durationMs, tickEvery, cooldownMs, castMs, gcdMs, maxStack, noTarget, rank, icdMs and ids were compared by body diff (comment lines excluded) of all 11 generated files old vs new. Everything else differs only in header lines (overlay name, hotfix push, "70888 overlay changes" counts, Regenerated stamp). Items.lua and Procs.lua bodies are byte-identical.

## Warlock rows vs the pre-change baseline

| spell | id | baseline | 70888 | same |
| --- | --- | --- | --- | --- |
| Corruption | 11672 (pinned over 1223963) | 18 s, tick 3 s | durationMs 18000, tickEvery 3, castMs 2000 | yes |
| Bane of Agony | 11713 | 24 s, tick 2 s | 24000, tickEvery 2 | yes |
| Siphon Life | 18881 | 30 s, tick 3 s | 30000, tickEvery 3 | yes |
| Wrack | 1316697 | 6 s channel, tick 1 s | 6000, tickEvery 1 | yes |
| Immolate | 11668 | 15 s, tick 3 s | 15000, tickEvery 3 | yes |
| Summon Voidwalker | 697 | pinned | 697 | yes |

The store's raw rows for those ids (`periodMs` 3000 / 2000 / 3000 / 1000 / 3000) are unchanged from 70862 too. If Blizzard's Tuesday numbers differ from these, the store has not captured them at push 113904; re-run after the next push.

## Decoy re-picks and pins

None found: 0 picked ids changed, so no new pins. Existing pins checked still in `tools/spell_lists/druid.json` (Thorns 9910) and `warlock.json` (Summon Voidwalker 697).

## Tests (run locked, `run-tests`, current addon tree)

| suite | result |
| --- | --- |
| Forte_Cooldown | 268 / 268 |
| Forte_Timer | 193 / 193 |
| Forte_Warlock | 103 / 103 |
| Forte_Hunter | 175 / 175 |
| Forte_Shaman | 23 / 23 |
| Forte_Core | 144 / 144 |
| Forte_Options | 109 / 109 |
| Forte_Messages | 85 / 85 |

Re-pinned: none. The Corruption 3 s tick assumption in `Forte_Timer/tests/test_data_feeds.lua` and `test_pet_rows.lua` still holds because the data still says 3 s. No behaviour break, no code fix.

## Verification

- `python3 tools/extract_store.py --dry` and real run: `extract 1.60.1.70888 hotfix 113904 commit c1c29def: spells=4053 nameIndex=608 removed=1 bookRanks=35`.
- Regenerated nine classes plus `gen_item_data.py` twice: identical except the `-- Regenerated:` line (2 differing lines per file).
- Re-extract after regenerating is byte-identical to the checked-in overlay (fixpoint).
- `luajit loadfile` on all 11 Data/*.lua: ok. `python3 scripts/api_lint.py`: OK (64 files).
- `scripts/gate.py` not run (manager's job).

## Files changed

`tools/overrides_70888.json` (new), `tools/gen_spell_data.py` (one line), 11 generated `Data/*.lua`, this report, an appended section in `live-warlock-2026-11-09.md`.
