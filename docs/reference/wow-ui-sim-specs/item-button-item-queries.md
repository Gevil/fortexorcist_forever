# Item button item queries

The Retail and PTR ItemButton consumer uses supplied item observations for Azerite classification and reagent quality. See [Lua API architecture](../lua-api.md).

## What it must do

- [x] `C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItemByID` reads the existing supplied empowered-item ID set and returns a boolean.
- [x] `C_TradeSkillUI.GetItemReagentQualityInfo` reads item-keyed supplied reagent quality or returns nil when no record is supplied.
- [ ] Reagent quality snapshots remain detached from supplied state.
- [ ] Both APIs authenticate secret selectors before parsing, and accept the existing item-ID and link parser forms.
- [ ] Publish these queries on Retail and PTR only in this lane. Pinned declarations are `AzeriteEmpoweredItemDocumentation.lua:172` in both profiles and `TradeSkillUIDocumentation.lua:364` (Retail) / `:379` (PTR).

## How it works

- [Lua API architecture](../lua-api.md)

## Implementation inventory

- `src/c_api/c_azerite_empowered_item.rs`: supplied Azerite classification.
- `src/c_api/c_trade_skill_quality.rs`: supplied reagent records and quality snapshots.

## Tests asserting this spec

- `tests/test_keybindings.rs`: original ItemButton overlay consumers with distinct supplied items.

## Known gaps (current cycle)

- [ ] PTR secret-input and excluded-profile runtime coverage remain unverified.
- Retail character-toggle next fails at `AzeritePaperDollItemOverlay.lua:13` (`C_AzeriteItem.IsAzeriteItem`), not `GetMinItemLevel`; the latter is not implemented in this lane.

## Out of scope

- Native item classification and catalog inference; other profile publication; modifier-click dispatch and spell-target APIs.
