# Simulator selected quest turn-in

Explicitly simulator-authored `A_Admin.TurnInSelectedQuest()` commits a selected completed quest using the existing rich quest-log/history model in `src/lua_api/sim_substates/quest_log.rs` and administrative producer in `src/lua_api/globals/admin_quests.rs`. This is not a native API or native-parity claim. [Implementation notes](../wiki/systems/lua-api.md#simulator-selected-quest-turn-in) describe projections.

Wrath 3.3.5a build 12340 native/dialog behavior is governed separately by [Wrath turn-in](wrath-quest-turn-in.md). The selected-log admin validation and modern `QUEST_TURNED_IN` rules below record the existing Retail/Forever simulator policy, not Wrath native semantics; a future Wrath pending-claim response adapter must not inherit them.

## What it must do

- [x] Consume only the selected positive, i32-representable quest ID whose existing rich row is complete and not failed. Return `true` only for a committed turn-in; no selection, invalid/out-of-range ID, missing row, incomplete or failed row returns `false` without mutation/event. Selection, not a supplied argument or another completed quest, determines the target.
- [x] Remove target rich/light active membership and, where modeled (Forever), ordinary watch membership/metadata. Preserve unrelated membership and completion history; insert the target into the existing completion set exactly once. A complete represented seed already in history remains eligible; history alone is not an active quest. Repeated calls/reselection of a removed row cannot turn it in again.
- [x] Clear the consumed selection and matching pending offer, remove matching current gossip rows and refresh counts; preserve unrelated pending offers/rows. A callback retry sees no eligible consumed target.
- [x] Publish `QUEST_TURNED_IN(questID, 0, 0)` once through existing synchronous dispatch after the full mutation and after releasing the mutable state borrow. Original listeners observe removed active/watch membership and recorded completion, not a staged or manually replayed event. The payload field order is sourced from cached official Lua documentation; zero rewards and this mutation order are explicit simulator policies.
- [x] Suppress completed IDs in existing task catalog active/map/time projections, including `GetQuestLogTimeLeft`, `GetQuestsOnMap`, the available map alias and `DoesMapShowTaskQuestObjectives`. Rich log/world/map queries reflect removed rows. Preserve unrelated task catalog availability and environment isolation; catalog metadata lookups remain catalog-backed. No second active/completed domain is introduced.

Checked requirements record the supplied fixtures in the [saved bounded acceptance](#bounded-retailforever-acceptance--2026-10-16), not native parity or exhaustive input/profile acceptance.

## How it works

- [Quest state and projection implementation](../wiki/systems/lua-api.md#simulator-selected-quest-turn-in)
- [Existing offer/accept/watch/abandon contract](quest-offer-rich-log-coherence.md)
- [Simulator admin API](../admin-api/quests.md)

## Implementation inventory

- `src/lua_api/sim_substates/quest_log.rs`: eligibility, rich-row removal and existing completion-set insertion.
- `src/lua_api/globals/admin_quests.rs`: simulator-only endpoint, shared membership/dialog cleanup and original synchronous event dispatch.
- `src/lua_api/globals/quest_surface/task_quest.rs`: static task availability filtered by existing per-environment completion history; metadata stays catalog-backed.

## Tests asserting this spec

`tests/quest_turn_in_model.rs` contains four authored behavioral cases: selected ordinary completion/watch/event-boundary/reentrant and repeat controls (Forever), rich-only world task/map/time/history/environment projections (shared), invalid/incomplete/failed controls (shared), and represented completed-seed/dialog/pending preservation (shared). Existing completion is supplied by setting the existing rich row's `is_complete` fixture field; no gameplay objective-completion producer is claimed.

Historical RED: producer committed as `b5dd5947a` after actual shared Retail behavioral RED; GREEN had not been run at that checkpoint. [Saved bounded acceptance](#bounded-retailforever-acceptance--2026-10-16) now supersedes the pending producer gate. Three shared cases executed: zero PASS/three FAIL, exit 101. The world-task and represented-seed/dialog cases stopped at unchanged rich active membership; the invalid-selection case stopped at selection `None` because the missing endpoint yielded nil instead of false. All later assertions in those cases remain unreached. The fourth authored case is Forever-only and was not executed in that RED epoch: ordinary watch cleanup, original synchronous listener visibility, reentry and repeat-event controls had no runtime proof there. Committed tests are `96ba1ba4d`; saved receipt metadata labels the test/source snapshot `b7e380f2fe56ceb820cbbe355c6a6c94aac8d339`, not the test-authoring commit or runtime source. The executed copied fixture used retained normal Retail library source `bbeac62133cfbf678faf3eca07eab27f6b9bcec8` (getter `64a5576b1`), not the subsequently committed producer or unrelated EditBox source. Receipt: `/home/osso/.local/state/wow-ui-sim/verification/wrath-source-current/quest-turnin-retail-red-20261016T172145753836Z`. Independent RED audit accepted this evidence in `/home/osso/.local/state/wow-ui-sim/verification/quest-turnin-next/red-report.md`; no GREEN, Forever-event ordering, native or full-parent claim. Missing endpoint is tolerated only by the test invocation helper, not production fallback.

## Bounded Retail/Forever acceptance — 2026-10-16

Saved source `70ebaee0e70997b691edeaf894156ca376c2ad1f` contains producer `b5dd5947a`. All copied real `tests/quest_turn_in_model.rs` bytes match that source. **Retail shared 3/3; Forever 4/4**, zero failed/ignored/measured, both bounded processes exit0. The Forever-only case reaches original synchronous `QUEST_TURNED_IN(80002,0,0)` after rich/light/watch removal, completion insertion and selection cleanup; original listener reentry returns false, reselection cannot repeat, event count remains one and unrelated membership/history/money/XP are preserved. Shared cases reach world/task/map/time/history/environment isolation, invalid/incomplete/failed inertness and represented-completed-seed/dialog/pending preservation. No manually replayed replacement event or native reward producer is involved.

Component epochs: `/home/osso/.local/state/wow-ui-sim/verification/green-batch/green-retail-20261016T205154411414Z` and `green-wowforever-20261016T204221233563Z`. Retail runs these three alongside 25 [charge-policy controls](cooldown-restriction.md#bounded-retailptr-selector-acceptance--2026-10-16), yielding 28/28; PTR's separate 25/25 charge process does not test turn-in. Overall 57 executions/29 logical tests are counted once. Shared recipe, successful retry/original ledger reconciliation, source ancestry, nine artifact seals, exact feature bundles and six CVar guards are independently recorded in `/home/osso/.local/state/wow-ui-sim/verification/green-batch-20261016/report.md`; handoff ledger paths are linked in the [charge receipt](cooldown-restriction.md#bounded-retailptr-selector-acceptance--2026-10-16).

Separate normal cached-UI startups are not component cases: Retail/PTR exit0 with `[]`; **Forever exit 1, 10 unique/14 GamepadActionBars errors**. Forever's complete message/count multiset matches saved source `docs/baselines/wowforever-lua-errors.json` after normalizing only generated template-handler hex hashes. The reported nil general action-storage start at `ActionBindingUtil.lua:101` and downstream override-map errors are a separate root investigation, not repaired or retested here. Baseline equality does not make startup GREEN. Forever's unused `UnitRole::{Tank,Healer,Damage}` compiler warning remains. All normal libraries are non-test, one-client sound/gui/casc builds; runtime startup explicitly disables CASC/sound and third-party addons/saved variables. Persisted original CVars retain their batch-before hash/stat; private startup-copy initialization is receipt-proven, and private post-run files may change.

Only these saved bounded component behaviors are accepted. No full integration-target compilation/execution, native parity, GUI/assets, broad suite, current-HEAD proof or new format/check gates. Existing RED receipts remain historical, not erased by GREEN.

## Known gaps (current cycle)

- [x] Saved focused GREEN and independent artifact verification: Retail shared 3/3, Forever 4/4 including original watch/event/reentry/repeat boundary.
- [ ] Separate formatting/readability/profile checks and broader startup acceptance remain unproven by this receipt.
- [ ] Native behavior, reward acquisition, objective progression and broad UI acceptance remain unproven and are not asserted by supplied fixtures.

## Out of scope

Native `GetQuestReward`/`CompleteQuest` publication or parity, native validation/event sequencing beyond the documented payload shape, quest objective progression, automatic watches, inventory/currency/XP/money rewards, transport, native catalogs, persistence, new repeatable/reacceptance/reset policy and whole-parent acceptance. `is_replayable` is not changed or promoted into a repeat-turn-in lifecycle. The existing seed catalog stays intact; only active/map/time projections exclude completion-history IDs under this authored scenario.
