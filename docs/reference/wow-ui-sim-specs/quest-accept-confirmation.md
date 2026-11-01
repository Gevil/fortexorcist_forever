# Quest accept confirmation

Bounded Retail 12.0.5 `QUEST_ACCEPT_CONFIRM` input tied to the existing pending quest offer. Producer lives beside `A_Admin.OpenQuestNpc` in `src/lua_api/globals/admin_quests.rs`; bounded independent acceptance is recorded below. See [event dispatch](../event-system.md) and [Lua API](../wiki/systems/lua-api.md).

## What it must do

- [x] Under `profile-retail` + `retail-12-0-5`, expose `A_Admin.RequestQuestAcceptConfirmation(name, questTitle)`, with two explicit string inputs. Derive event `questID` exclusively from current `pending_quest_offer`; do not invent a sharer name or substitute the gossip title.
- [x] With a pending offer, synchronously publish exactly `(name:string, questTitle:string, questID:number)` to real frame listeners before returning. Preserve pending offer, selected quest and quest log until an acceptance/close action occurs. Existing selected quest must be queryable during the callback; acceptance inside that callback must consume the matching pending offer.
- [x] Selecting an available quest alone still sets the offer and emits `QUEST_DETAIL`, not `QUEST_ACCEPT_CONFIRM` or an acceptance transition.
- [x] `ConfirmAcceptQuest()` consumes the offer, adds that ID once to the existing log, and queues existing `QUEST_ACCEPTED` without re-prompting. Calling it again with no offer remains inert.
- [x] Preserve established simulator `CloseQuestFrame()` semantics: clear pending offer, queue `QUEST_FINISHED`, leave log unchanged and emit no acceptance or new prompt. **Chosen simulator policy:** confirmation input with no pending offer is a silent no-op, both initially and after close; no event or state mutation. This is not native-verified default behavior.

### Grounding and policy limits

Inspected profile cache on 2026-10-01 under `~/.cache/wow-ui-sim/blizzard-ui/retail/AddOns/`:

- `Blizzard_APIDocumentationGenerated/QuestOfferDocumentation.lua:64-74` declares `SynchronousEvent = true`; payload names/types are `name:cstring`, `questTitle:cstring`, `questID:number`, all nonnil. This is cached source evidence for the added third argument, not a live native probe.
- `Blizzard_Game/Mainline/EventRouting.lua:83` forwards the event to `GameEvent.HandleQuestAcceptConfirm`. `Mainline/EventImplementation.lua:331-338` consumes only the first two arguments, queries `C_QuestLog.GetNumQuestLogEntries()`, then shows `QUEST_ACCEPT` or `QUEST_ACCEPT_LOG_FULL`. No third-argument query/validation behavior is established by this consumer.
- `Blizzard_StaticPopup_Game/GameDialogDefs.lua:1582-1605` defines YES callbacks invoking `ConfirmAcceptQuest()`. Neither confirmation popup defines `OnCancel`; a native decline transition or pending-state effect cannot be inferred from the NO button alone. Fixtures cover the separate established simulator close action, not popup cancellation.
- `src/lua_api/globals/missing_surface/gossip_info.rs:101-121` selects an existing available row, sets `pending_quest_offer` and `selected_quest_log_id`, and dispatches `QUEST_DETAIL`. `src/lua_api/globals/quest_verbs.rs:67-97` establishes acceptance, deduplication, absent-offer no-op and close behavior in the current simulator.

The new admin name/signature and absent-offer policy are explicit simulator design choices. Two string inputs avoid a redundant caller-supplied quest ID and any invented mismatch-validation contract. Existing pending ID is the only association; this scope does not introduce a second confirmation record, acceptance gating, or payload defaults. Malformed-input/native validation semantics remain unspecified.

## How it works

- [Existing event queue and synchronous dispatch](../event-system.md)
- [Existing Lua API subsystem](../wiki/systems/lua-api.md)

## Implementation inventory

- `tests/quest_accept_confirmation.rs`: five grouped fixtures, gated by Retail profile and 12.0.5 epoch; no separate Cargo target.
- `src/lua_api/globals/admin_quests.rs`: gated explicit confirmation input; decodes two strings through `FromStack`, reads only the pending offer ID, releases the state borrow, and roots event strings across synchronous listeners. No offer is a no-op; no new storage or transition.
- `src/lua_api/globals/missing_surface/gossip_info.rs`: available-quest selection now retains a full selected snapshot under the [rich-log coherence contract](quest-offer-rich-log-coherence.md).
- `src/lua_api/globals/quest_verbs.rs`: acceptance now publishes absent rich membership in addition to the existing lightweight ID/event; confirmation and close semantics remain as specified here.

Shared payload change `ccd9e2d01` replaces the pending numeric ID with an existing `QuestLogEntry`; the prompt extracts its ID before synchronous dispatch. Historical October1 proof below predates this change. Current source `a56e11267` Retail pending-payload preservation is independently accepted at the bounded fixtures below; separate Forever43/43 evidence at source53cf is not Retail prompt proof.

## Tests asserting this spec

`tests/quest_accept_confirmation.rs` exercises actual `A_Admin.OpenQuestNpc` → `C_GossipInfo.SelectAvailableQuest` ordering, then the explicit admin input. Listeners assert exactly three arguments, concrete values/types and selected-quest visibility. Explicit confirmation title differs from seeded gossip title. Rust observes actual `pending_quest_offer`, `quest_log` and queued lifecycle events; no query globals, handlers or event dispatchers are replaced. Acceptance inside the prompt callback checks pending-state availability at the real dispatch boundary.

### Current Retail preservation — 2026-10-15

[Central Retail receipt](../baselines/README.md#retail-quest-preservation--2026-10-15) owns sourcea56 retry1 evidence, actual default-Retail emitted features/guard, successful12m13s integration no-run build and SHA256 `fcf228806a0203e11a18eea699f7245e88890f2652f5d133f511ffd6ccc5fbdf`. Independent `quest-enrich-next/retail-green-build-report.md` and `retail-green-runtime-report.md` under host-private verification state both PASS. Runtime executes **31 unique PASS / 0 FAIL, exit0**: these confirmation5 + Retail verbs13 + gossip13, harness16.50s; stdout2596/stderr19858 bytes. All five current prompt fixtures pass through actual modeled selection and real synchronous frame listeners. Exact payload/type assertions, immediate callback sentinels and Rust state/event postconditions establish bounded current preservation; exec success alone would not, because callback errors can be routed to an error handler. Complete saved stderr has no such diagnostic.

First204301Z host-PSI guard SIGTERM abort remains separate, with no compiler/test verdict. Original Forever43 at source53cf is not pooled with Retail31. Existing a56 fmt PASS and bounded quest-source default check/startup gates are accepted via the [central gate receipt](../baselines/README.md#quest-source-check-and-startup-gates--2026-10-15). Later4cb/52b DoubleIcon passive/test code is not covered by those check/startup/fmt proofs and awaits a new RED build. Loaded-popup/native/full-parent acceptance remains open; no whole-current-HEAD startup pass or C_UIWidgetManager closure follows.

### Historical proof — 2026-10-01

**Proof ledger (2026-10-01):** independent `/tmp/patch-12.0.5-quest-confirmation-independent-proof.md` inspected saved RED/GREEN and executed existing lifecycle controls. Producer `e5ab15302` follows actual RED at `81421d0574b6af3c3fc289216a6e910e4ee3806e`: 1 PASS (selection), 4 FAIL at missing `A_Admin.RequestQuestAcceptConfirmation`. Saved `/tmp/patch-12.0.5-batch16-red-run.{log,json}` identifies the artifact. Unrelated RED bin-test compilation failure at `enable_state.rs:225` (missing `AddonMetadata.addon_dir`) remains historical evidence; this producer is not claimed to fix it.

- GREEN combined build at `3f6d9d89e985165f51b34a2ee15df873d9d16105`: exit 0, 510.99s, no compiler diagnostics. Saved `/tmp/patch-12.0.5-batch16-green-build*` and `-green-runs.json` record 5 quest + 6 spell-prompt PASS. Integration SHA256 `cc23d4732ef54160c5a8ed2f7ec7691523314593a9001192bc9c3dec3d92c671` matches independent hashes before/after controls. Run2 selected zero tests and earns no control credit.
- Fresh independent `quest_verbs::` controls: 13 PASS, 0 FAIL, 9188 filtered, exit 0, 12.41s; `/tmp/patch-12.0.5-quest-confirmation-controls.{log,json}`. Saved quest/prompt cases were inspected, not rerun.
- Default `cargo fmt --check` and `cargo check`: exit 0, 37.90s/77.05s, no warnings/errors, at snapshot `36a7fb573e41f23173cef3de581e1bd67fc2bf34`. Producer/tests/manifest and relevant dispatch/quest/String conversion unchanged. Scope hashes before/after match (`c8284e433149c0068cea976bf4f90eea4ad6a47f1073f5b169649c10180f5e12`); `/tmp/patch-12.0.5-quest-confirmation-gates-{results,scope-before,scope-after}.json`. Not perpetual HEAD or all-profile proof.
- Separate **parent** normal `wow-sim` startup: `/tmp/patch-12.0.5-batch16-green-startup-run.json`, `-startup.json`, `-startup.log`; exit 0, `[]`, zero Lua errors, 12.70s. SHA256 `caa62e8aef0a770f60767faf2fa6f142c514789ec221ee9087ca7f72088620aa`, emitted by GREEN combined build. Hash-bound saved run, not verifier-run startup or current-binary proof.

**Security/rooting: source-only.** Strict `FromStack<String>` rejects nonstrings and wrapped secret userdata before pending lookup; no coercion/default/secret unwrap or secure-only authorization claim. Owned strings are pushed/rooted across synchronous dispatch; stack top restored before result propagation and model borrow released before callbacks. No malformed/secret input, forced-GC, multiple-listener or callback-error runtime probe. Independent wiring/readability PASS is bounded to inspected producer/tests. No broad-suite GREEN claim.

## Known gaps (current cycle)

- [x] Parent compiled integration artifact and ran actual targeted RED: selection passed; four confirmation fixtures stopped at missing producer.
- [x] Implement bounded producer after valid RED.
- [x] Saved targeted GREEN and independent bounded acceptance/default snapshot gates recorded.
- [x] Independently reconcile current a56 Retail pending-snapshot preservation: confirmation5 plus verbs13/gossip13 PASS, separate from historical proof and Forever execution.
- [x] Close bounded quest-source default check/startup gates from [independent saved receipts](../baselines/README.md#quest-source-check-and-startup-gates--2026-10-15), without extending proof to later4cb/52b code.
- [ ] Native, loaded-popup integration, all-profile and full-parent acceptance remain open.

## Out of scope

Native payload validation/defaults, popup cancellation/decline behavior, quest-sharing transport, full-log rejection policy, rich quest-log projection, generic event injection, source-row completion/accounting and changes to other supported profiles. Producer must be gated to the Retail profile/12.0.5 epoch; existing historical/non-Retail prompt behavior must remain unchanged. The separately specified [shared rich-log enrichment](quest-offer-rich-log-coherence.md) adds accepted membership without redefining this prompt contract. Fixtures assert simulator model transitions, not loaded Blizzard popup integration or native parity.
