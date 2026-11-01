# Supplied quest background material

Retail/Forever legacy `GetQuestBackgroundMaterial()` projects explicitly supplied
materials from existing quest state. Source: `quest_surface/legacy_globals.rs` and
`sim_substates/quest_log.rs`. [Quest architecture](../wiki/systems/lua-api.md#quest-dialog-material)
owns implementation details.

[API documentation](https://warcraft.wiki.gg/wiki/API:GetQuestBackgroundMaterial)
(inspected 2026-10-16) declares no arguments and one `string?` result. The inspected
cached generated Retail docs have no entry for this legacy global.

## What it must do

- [x] Return one nil when selected/supplied material is absent; let original
  `QuestFrame_GetMaterial` choose Parchment, without inventing a material name.
- [x] Return supplied Stone verbatim and preserve live selection/environment isolation.
- [x] Remove supplied material on existing abandonment.
- [ ] Preserve the same cleanup through existing completed turn-in (new test assertion pending).

The rich-state-owned `background_materials` map is explicit ingress, not a second
quest-membership store. No admin mutation endpoint is added.

## How it works

- [Quest architecture](../wiki/systems/lua-api.md#quest-dialog-material)

## Implementation inventory

- `src/lua_api/sim_substates/quest_log.rs`: passive supplied map and turn-in cleanup.
- `src/lua_api/globals/quest_surface/legacy_globals.rs`: selected material getter.
- `src/lua_api/globals/quest_surface/register.rs`: Retail/Forever-only publication.
- `src/lua_api/globals/quest_verbs.rs`: abandonment cleanup.

## Tests asserting this spec

`tests/quest_background_material.rs` loads original cached QuestFrame;
`Mainline/QuestFrame.lua:602-610` contains the nil-to-Parchment branch.
Passive ingress `4e5e1efd0` needed seeded initializer `fe529b241`; the initial E0063
build failure is not RED. Repaired source then produced two real assertion REDs:
None versus Parchment and None versus Stone. Saved `9d1430bf3` passed both cases
(4.72s), including selection/isolation/abandonment and nil arity; separate Retail
startup returned `[]`. Test `1a7bea08d` additionally asserts completed turn-in cleanup.
Receipts: private `quest-lifecycle-build/material-red-repaired-retail-*` and
`root-green-retail-*`. Full dialog progress is a [separate contract](quest-readiness-dialog.md).

## Known gaps (current cycle)

- [ ] Execute the added turn-in assertion in the final Retail/Forever quest matrix.

## Out of scope

Material acquisition/catalogs, native context parity, full reward metadata and vendor edits.
