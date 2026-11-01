# Retail watched currency mutation — optional B5 sub-slice

Integration checkpoint (2026-10-16): independently selected watched slice reached original-consumer RED → GREEN; [bounded proof](../baselines/approved-batch-2026-10-16.md). No native-parity claim.

Status: implemented by explicit follow-up selection; unused grouping remains deferred. Simulator contract only.

## What it must do

- [ ] SetCurrencyBackpack resolves current displayed index; SetCurrencyBackpackByID resolves an existing catalog currency independent of visibility. Headers, unknown IDs and invalid indices do nothing.
- [ ] Record environment-local watch overrides, initially matching static membership. Update both list status and the corresponding supplied CurrencyInfo flag; backpack enumeration uses catalog order, independent of collapse/unused placement. Repeated operations are idempotent. No persistence, new events, cap enforcement or capacity policy in C API; original TokenFrame enforces its own capacity.
- [ ] Missing supplied currency records cannot be mutated. Existing watched slots with removed records preserve the shared no-values behavior; unrelated direct supplied display edits do not change watch membership.
- [ ] Quantities and non-Retail behavior remain unchanged.

## How it works

- [C API and Lua boundary](../lua-api.md)

## Implementation inventory

- `src/c_api/currency_list.rs` — watch membership overrides.
- `src/c_api/item_spell/c_currency.rs` — public mutations and list/backpack projections.

## Tests asserting this spec

`tests/currency_watched_mutations.rs` reuses original cached TokenUI loading. Original TokenFrame:SetTokenWatched (Lua:441-456) drives removal and addition after index shifting; direct ByID removal exercises the API form consumed by original BackpackTokenMixin:OnClick (Lua:728-735). Original list refresh and backpack rendering run for the TokenFrame calls; the modified-click branch itself is not exercised.

## Known gaps (current cycle)

- [x] Retail original watch mutation RED/GREEN, currency preservation and startup observation executed.
- [ ] Modified-click branch, removed-record mutation and other-profile/native acceptance are not established by the selected watch case.

Observed RED after instantiating the original BackpackTokenFrameTemplate: supplied removals did not empty backpack membership. Earlier missing watcher setup was not counted as RED. The same original TokenFrame mutation path became GREEN after producer.

## Out of scope

No transfer, filtering, persistence or new catalog. This intentionally supersedes static watch status/membership clauses of [field projection](currency-list-field-projection.md) for Retail public watch mutators only; non-Retail/static and missing-row preservation tests remain applicable. Independent of the unused sub-slice; unused classification does not implicitly watch/unwatch.
