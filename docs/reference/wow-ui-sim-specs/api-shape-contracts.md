# API shape-only contracts

Documented shapes, not invented native behavior, are the acceptance contract for these native-unknown surfaces (decision 2026-10-23). Tests live in `tests/api_shape_*.rs`; original consumer selection follows [consumer selection and proof](../wiki/investigations/consumer-selection-and-red-proof.md). The equipment-set row is superseded by the [supplied lock-state contract](equipment-set-locks.md). Other rows retain their deferred proof status.

## What it must do

### Stable active list

- [ ] Retail/PTR `C_StableInfo.GetActivePetList()` returns exactly one non-nil `table<PetInfo>`; validate every present record and nested numeric ability table without requiring any entry count, order or slot membership.
- [ ] Original `StableActivePetListMixin:Refresh` accepts actual results without Lua error. An empty table is shape-compatible, not native-confirmed. `uiModelSceneID` documents Default=718, not a required value for every record.

Sources: Retail/PTR `Blizzard_APIDocumentationGenerated/StableInfoDocumentation.lua:15-22,193-214`; selected `Blizzard_StableUI/Blizzard_StableUI.lua:447` via `Blizzard_StableUI/Blizzard_StableUI.toc:4`. Forever excluded: selected Camelot StableUI never calls this API despite cached Standard source and documentation.

### Item upgrade

- [ ] Retail/PTR/Forever/Mists/Era/Anniversary `C_ItemUpgrade.CanUpgradeItem` takes a required non-nil `ItemLocation` and returns exactly one non-nil boolean; no eligible/ineligible value is mandated.
- [ ] Original generic ItemUtil consumes supplied eligibility through a shown-frame fixture context on all six declaring profiles. See the [supplied eligibility contract](item-upgrade-eligibility.md) for authenticated declaration/consumer lines and lifecycle requirements. This explicitly supplied fixture context does not claim original upgrade-window acceptance; Era/Anniversary's window remains unselected.

### Store

- [ ] Retail/PTR/Forever/Mists/Era/Anniversary `C_StorePublic.DoesGroupHavePurchaseableProducts` accepts a required non-nil numeric group ID and returns exactly one non-nil boolean.
- [ ] Original `StoreInterfaceUtil.OpenToSubscriptionProduct` accepts the actual group-query result without Lua error on its normal legacy-shop path. Shop2 bypass is a blocked prerequisite, not a passing group-query test. Direct shape checks cover both original category IDs; the second original call remains conditional on the first actual result.

Sources: `Blizzard_APIDocumentationGenerated/StorePublicUIDocumentation.lua:11-24` (Retail/PTR/Forever), `:11-23` (Mists/Era/Anniversary); selected `Blizzard_SharedXML/InterfaceUtil.lua:44,48` (Retail/PTR/Forever), `:32,36` (Mists/Era/Anniversary), selected by SharedXML TOCs. Secure StoreUI is not the selected consumer on five of these profiles and is not forced into coverage.

### Equipment set

The restored `tests/api_shape_equipment_set.rs` now asserts the [supplied lock-state contract](equipment-set-locks.md), including original equip/no-equip transitions and explicit unknown-input errors. Its old boolean-only acceptance is not producer proof. The linked contract owns declarations, current PTR TOC lines, behavior and exclusions.

## How it works

- [Runtime-selected consumers and proof classes](../wiki/investigations/consumer-selection-and-red-proof.md).

## Implementation inventory

- `tests/api_shape_stable_active_list.rs`: Retail/PTR list/record shape and original refresh acceptance; missing member is a shape blocker, not semantic RED.

- `tests/api_shape_item_upgrade.rs`: six-profile supplied eligibility, real inventory lifecycle, argument/boolean shape and original generic consumer.

- `tests/api_shape_store.rs`: six-profile numeric-group/boolean shape and original InterfaceUtil acceptance.

- `tests/api_shape_equipment_set.rs`: four-profile supplied lock-state behavior through the original equip-set consumer.

## Tests asserting this spec

- `api_shape_stable_active_list::stable_active_list_shape_blocker_contract` — source-predicted FAIL for missing member; not executed.

- Item-upgrade coverage is restored and strengthened under [the supplied eligibility contract](item-upgrade-eligibility.md); the historical boolean-only pass is preservation, not producer acceptance. Execution of the restored selectors is pending.

- `api_shape_store::store_original_interface_util_contract` — expected preservation PASS on six profiles with legacy shop prerequisites, unexecuted.

- `api_shape_equipment_set::equipment_set_original_equip_set_contract` — locked/unlocked/relocked original-consumer transitions; see the supplied-state contract for proof status.

## Known gaps (current cycle)

- [ ] Deferred execution must distinguish setup failures from shape blockers and preservation passes. No producer or vendor changes are authorized here.
- [ ] `GetInventoryItemsForSlot` (#7 q1, Retail/PTR/Forever consumer) and `IsInventoryItemProfessionBag` (#7 q3, Mists/Era/Anniversary consumer): native-unknown with **no generated documentation schema** in the six scoped profiles. No shape test, return type, mutation rule or semantics is inferred from call sites.

## Out of scope

Native behavior remains unknown: defaults, membership, ordering, eligibility/lock/purchase policy, invalid-input behavior, event timing and persistence. A constant shape-compatible implementation can satisfy these contracts; passing never proves a native producer. No Wrath coverage, forced unselected consumers, runtime N/A returns, ignored tests, API replacements or vendor edits.
