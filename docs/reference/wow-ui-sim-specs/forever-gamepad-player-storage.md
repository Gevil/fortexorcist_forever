# Forever gamepad player storage

The original Forever gamepad consumers require a non-nil player-action storage base from `C_GamepadUI.GetFirstGamepadActionStorageSlotIndex()`. This is distinct from the [pet storage contract](forever-gamepad-pet-storage.md). The user selected simulator-owned disjoint allocation on 2026-10-16. This contract does not claim native numbering or native parity.

## What it must do

- [x] Original cached `ActionBindingUtil.lua` maps standard pages relative to a positive integral player base: `(1,1)` to base, `(1,9)` to base+4, `(1,32)` to base+27, `(2,1)` to base+28, `(3,32)` to base+83; reserved slots5–8 and special page4 return nil.
- [x] Normal XML-created main and edit PageUnits complete initial OnLoad without replay or preseeded maps; real possess/stance bars resolve default4/default3 to bottom/right anchors and page1.
- [x] Under no-bonus-action state, original registered stance handlers for `UPDATE_BONUS_ACTIONBAR` and `PLAYER_ENTERING_WORLD` preserve linked parents and inactive hidden stance bars without the recorded storage/map errors.

## Simulator allocation contract

Player gamepad storage occupies **4096–4179 inclusive**, 84 slots in the existing player action storage: three standard pages times (32 positions minus four reserved positions). The getter returns **4096**. Ordinary and special bars retain their existing low slot IDs (default special indices through 14, with 12 buttons per bar); pet APIs retain their separate ten-slot, one-based storage. The new range shares no IDs with those existing allocations. The gap below 4096 avoids remapping ordinary/special bars. This is a simulator reservation, not a measured native base; explicit writes to these IDs intentionally address gamepad storage.

`GetActionInfo`, `PlaceAction` and `PickupAction` use the same existing player action maps at these IDs, with no copied state or alias translation. Original main/edit buttons reference the same gamepad slots. Pet storage is neither moved nor mirrored.

- [x] Prove all 84 mapped slots support known-spell placement, lookup and pickup/replacement, original main/edit buttons see the spell, and every lower player slot plus a distinct pet action remain unchanged.

## How it works

- [Addon loading and XML lifecycle](../addon-loading-pipeline.md).
- [Override defaults](forever-gamepad-cvars.md).

## Implementation inventory

- `src/c_api/c_gamepad_ui.rs`: Forever-only namespace publishes the reserved player base and unchanged pet base. Existing player action maps supply storage; no legacy API changes.
- `tests/wowforever_batch5_surface.rs`: original cache binding consumer and dependency-closure XML lifecycle regressions; no vendor changes.

## Tests asserting this spec

- `forever_player_storage_original_binding_consumer_uses_relative_offsets`.
- `forever_player_storage_normal_xml_initializes_both_page_units`.
- `forever_player_storage_disjoint_actions_preserve_player_and_pet_slots`.

## Known gaps (current cycle)

- [x] Behavioral RED at test revision `7cdd8e705`: original consumer nil arithmetic, normal XML mapping errors and selected-base assertion fail; existing pet control passes. Normal Forever library/binary build succeeded. Private proof: `forever-gamepad-producer/red-component-20261016T211328411373Z` under the handoff directory.
- [x] Select simulator-owned disjoint allocation and execute the action/pet acceptance fixture.
- [x] Re-capture normal startup and compare all10 historical records/14 occurrences. Historical JSON remains intact; this receipt supersedes its counts for the bounded configuration below.
- [ ] Parent integration verification, whole integration target, native/hardware and GUI evidence remain separate.

## Bounded execution — 2026-10-16

Normal `sound,gui,casc,client-wowforever` library/binary at producer `0177adc75443fa2b6506c0e2ac32c44395dc384c`: **three player tests and one existing pet control PASS** using copied real test modules and the unchanged dependency-closure loader. Tests/library revisions and seals live in private handoff `forever-gamepad-producer/`; `proof-ledger.json` owns exact commands/revisions. No full integration-target claim.

Separate sealed normal startup (`--no-addons --no-saved-vars lua-errors`, CASC/sound disabled) returns **exit0, `[]`, 0 records/0 occurrences**. Own sealed preproducer revision `7cdd8e705` returns exit1,10 records/14 occurrences. It matches the historical baseline apart from the generated handler hash in four event rows; counts, consumers and failure sites match. `startup-comparison.json` records that qualification. All six runtime invocations copied current persisted CVars into fresh child-only data homes and preserved original stat/hash.

The normal build retains the pre-existing unused `UnitRole` variants warning. The component compiler reports one unused closure-helper warning. The narrow lifecycle fixture records an unrelated `MainActionBar.lua:45` missing `BagsBar` diagnostic after events; target-family assertions and state assertions pass. The separate normal startup has no Lua errors. These are not zero-warning, whole-fixture-clean or native-parity claims.

## Out of scope

Hardware input, active-stance storage, unrelated validators, vendor changes, native numbering claims and clean-startup acceptance without replay evidence.

## Producer staging — 2026-10-16

The generated API declares a non-nil luaIndex but no numeric base. Pet slot1 does not establish player numbering. The selected simulator allocation above supersedes the earlier unresolved staging decision. Implementation belongs in `src/c_api/c_gamepad_ui.rs`; downstream maps and Blizzard Lua remain unchanged.
