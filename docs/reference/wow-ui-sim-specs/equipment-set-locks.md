# Supplied equipment-set item locks

`C_EquipmentSet.EquipmentSetContainsLockedItems` projects supplied observations onto the existing saved equipment sets on Retail, PTR, Forever and Mists. Native acquisition and lock policy are not inferred. See the [model and proof](../wiki/systems/equipment-set-locks.md).

## What it must do

- [x] Publish the numeric saved-set-ID query on Retail/PTR/Forever/Mists. Preserve excluded Wrath/Era/Anniversary behavior.
- [x] `A_Admin.SetEquipmentItemLock(itemID, locked)` supplies or replaces one explicit boolean observation; missing/nil/non-boolean inputs error without mutation. `A_Admin.ClearEquipmentItemLock(itemID)` removes only that observation; neither operation equips gear or infers native event timing.
- [x] Join observations to the current saved set's slot-to-item-ID contents. With an observation for every referenced item, return exactly one boolean: whether any referenced item is locked. A lock outside the saved set does not affect the result; resaving changes membership immediately.
- [x] Unknown sets and missing observations raise explicit simulator errors prefixed `native-unknown: C_EquipmentSet.EquipmentSetContainsLockedItems`. Clearing an observation restores the missing-observation error. This wording is simulator policy, not a native error contract.
- [x] The original runtime-selected `EquipmentManager_EquipSet` rejects locked saved sets without changing equipment or starting a swap, equips unlocked sets, and follows replacements/relocking without leaking observations between environments.

The saved-set representation is slot→item ID, not item-instance identity. Observations therefore use item IDs; two copies of the same item ID share one observation. This is a model limit, not a native claim. No lock flag is seeded implicitly. The query requires complete observations rather than treating unknown items as unlocked. Empty known contents have no referenced locked item under this supplied-state projection; this does not establish native empty-set policy.

Declarations: pinned `Blizzard_APIDocumentationGenerated/EquipmentManagerDocumentation.lua:56–69` on Retail/PTR/Forever and `:53–65` on Mists. All require numeric `equipmentSetID` and return non-null boolean `hasLockedItems`. PTR line numbers were re-authenticated. Selected original consumers are Mainline `EquipmentManager.lua:259–266` on R/P/F and Wrath `EquipmentManager.lua:307–314` on Mists. FrameXML TOC selects `[Family]` at Retail `:99`, PTR/Forever `:105`; Mists selects `Wrath` at `:70`.

## How it works

- [Equipment-set state and original-consumer proof](../wiki/systems/equipment-set-locks.md).

## Implementation inventory

- `src/c_api/equipment_set_locks.rs` — supplied observations, profile gate and locked-item query.
- `src/lua_api/state_types/character_world.rs` — observation map beside existing saved sets.
- `src/c_api/item_spell/c_equipment_set.rs` — namespace publication.
- `src/lua_api/globals/admin.rs` — host input publication.
- `src/lua_api/workarounds/temporary/equipment_set_lock_defaults.rs` — excluded-profile legacy workaround only.

## Tests asserting this spec

- `tests/api_shape_equipment_set.rs` — restored coverage uses real original-consumer equipment/swap transitions, saved-set changes, explicit errors and independent environments, not boolean shape alone.

- `tests/c_item_api.rs` — the previous implicit-unlocked test now requires explicit missing-observation errors on supported profiles and retains the old assertion on excluded profiles.

## Known gaps (current cycle)

The supplied-observation slice is verified below. Native-policy limits remain out of scope.

## Out of scope

Wrath/Era/Anniversary contracts, item upgrades and `C_ItemUpgrade`, item-instance identity, native lock acquisition/defaults/criteria, ignored-slot lock policy, missing-item policy, combat/casting restrictions beyond the unchanged original consumer, native unknown-set/invalid-input wording, native secrecy and event-timing parity. Existing saved-set equip transitions are reused, not redesigned.

## Bounded proof — 2026-10-26

Runtime code/tests: GREEN `33b1723a0`, producer-only RED `7fea6a69f`, exact master baseline `503c63d27`. The sibling trees have byte-identical tests and differ only in `src/c_api/equipment_set_locks.rs`; RED returns constant false from the projection helper while preserving observation inputs.

| Profile | Exact GREEN cases | Original-consumer REDs | All-target compiler warnings | Raw stock before → after (unique/occurrences) |
|---|---|---|---|---|
| Retail | 6/6 | 3/3 intended failures | 0 | 8/10 → 8/10 |
| PTR | 6/6 | 3/3 intended failures | 0 | 214/280 → 214/280 |
| Forever | 6/6 | 3/3 intended failures | 0 | 26/26 → 26/26 |
| Mists | 6/6 | 3/3 intended failures | 0 | 6/12 → 6/12 |

Every case listed exactly one test before its isolated run. The original consumer is authenticated through the selected Game TOC and Lua source provenance. All four stock comparisons have zero added, removed or changed-count raw keys. Stock commands exit1 because unrelated residual Lua errors remain; this is not clean-startup or whole-client acceptance. Tests do not erase existing loader errors or patch vendor consumers.

Checks use `cargo check --all-targets --no-default-features --features sound,gui,casc,tools,client-<profile> --message-format=json-render-diagnostics -j1` through the canonical slot launcher; Cargo JSON and plain stderr both have zero compiler warnings. Formatting and manual Rust readability pass. Fresh child-only copies of current CVar bytes protect the original for every list/test/stock process. These are bounded simulator proofs, not native lock/default/secrecy parity.
