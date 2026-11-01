# Temporary empty quest progress-dialogue / requirements inputs

Five missing native globals are explicitly temporary compatibility gaps, not
supplied-state implementations. Source:
`workarounds/temporary/quest_progress_requirements.rs`.
[Quest architecture](../wiki/systems/lua-api.md#quest-dialog-material) and the
[execution receipt](../baselines/quest-lifecycle.md) own context/proof.

## What it must do

- [x] Retail/Forever GetProgressText returns an empty string, and original progress
  panel text remains empty when NPC progress dialogue is unmodeled.
- [x] GetQuestMoneyToGet/GetNumQuestItems/GetNumQuestCurrencies return numeric0;
  original required-cost/item/currency displays remain hidden with no invented rows.
- [x] GetQuestPortraitTurnIn returns exactly `0, "", ""`; original reward-panel
  no-portrait logic hides and detaches the real QuestModelScene.
- [x] An unsupplied original reward panel remains empty and introduces no swallowed errors.

Existing reward_items/currency_rewards remain authoritative for rewards; no parallel
store is introduced. There is no NPC progress-dialogue, required item/currency/cost,
or turn-in portrait-input model in the inspected state. Retire these empties when
supplied quest-progress-requirements/dialogue/portrait-input state replaces them.

## How it works

- [Quest model](../wiki/systems/lua-api.md#quest-dialog-material)
- [QL-2](quest-readiness-dialog.md)

## Implementation inventory

- `src/lua_api/workarounds/temporary/quest_progress_requirements.rs`: typed empties and retirement condition.
- `src/lua_api/workarounds/{mod.rs,temporary/mod.rs}`: registration under QL-1's profile gate.

## Tests asserting this spec

`tests/quest_dialog_requirements.rs` invokes unchanged original handlers, with explicit
first-dialog mapView state. Cached Retail Mainline/QuestFrame.lua:205,218-225,129
calls text, requirements and portrait respectively. Its :129-136 tests displayID
against0; :535-540 hides/detaches. Text/name are strings consumed at :459,499-504.

Historical tests reached three actual original nil calls. Money/currency-count
calls were behind the earlier item-count failure, not separately credited as REDs.
The first no-values portrait draft reached the original nil-number comparison at
:523; revised hidden/detached-frame test reproduced it before the approved0/string
fix. Saved GREEN and latest integration status live in the execution receipt.

## Known gaps (current cycle)

- [ ] Close the latest-base integration gate in the execution receipt.

## Out of scope

Real progress dialogue/requirements/portrait-input state, reward acquisition or
native parity. GetNumRewardSpells/GetRewardSpell/GetQuestCurrencyInfo were absent but
uncalled by these Mainline consumers and are not added. The [eight-global inventory](../baselines/quest-lifecycle.md)
distinguishes the five included temporary domains from those three exclusions.
