# Current LFG follower dungeon

`C_LFGInfo.IsInLFGFollowerDungeon()` reports current instance membership from existing world LFG ID and dungeon classification. [Patch 10.2.5 source](../../data/patch-api/sources/10.2.5-api-changes.wikitext) publishes the function; cached `LFGInfoDocumentation.lua` declares zero arguments and one nonnil boolean. The modeled query replaces the former constant-false compatibility path.

## What it must do

- [x] Return one boolean: true when `world.in_instance` and its `instance_lfg_dungeon_id` identifies an existing follower-classified dungeon.
- [x] **Modeled policy:** known non-follower, unknown/missing ID and outside-instance states return false, including stale follower IDs outside an instance.
- [x] Observe live ID/classification updates and removal; isolate environments. Never infer ID from name, map, difficulty or party makeup.
- [x] Extend existing host `A_Admin.SetInstanceInfo(name, type, difficulty, maxPlayers, lfgDungeonID?)` with optional fifth input, preserving earlier outputs and existing instance flag behavior.
- [x] **Host replacement policy:** omitted/nil ID clears prior current LFG ID; an unknown numeric ID may be stored but does not become a follower. `SetInInstance` remains a flag-only toggle.
- [x] Keep existing `GetInstanceInfo` tenth result and generic LFG membership consistent with supplied state.
- [x] Exercise unchanged cached compact-frame name logic with controlled AI/walk-in/spectator inputs. This is a bounded caller fixture, not AI modeling or rendered/native acceptance.

## How it works

- [Host zone API](../admin-api/zone.md).
- [Lua API](../wiki/systems/lua-api.md).

## Implementation inventory

- `src/c_api/c_lfg_info.rs`: live query over existing world ID and dungeon classification, retaining the former stub's registration/profile applicability.
- `src/lua_api/workarounds/temporary/lfg_legacy_defaults.rs`: constant-false path removed; fallback-shape test no longer clears or asserts the modeled method.
- `src/lua_api/globals/admin_zone_economy.rs`: optional fifth `Option<i32>` host input replaces the current LFG ID; omitted/nil clears it.
- Existing world `instance_lfg_dungeon_id` and `lfd_dungeons` classification: no new catalog needed.

## Tests asserting this spec

`tests/lfg_follower_instance.rs`: eight cases for positive/false matrices, live mutation/isolation, optional host input/clearing, existing projections and exact cached caller logic. Historical genuine RED at `080833f1d`: one false-control PASS / seven FAIL; downstream transitions were not reached. Sealed Retail integration at `e3978fd48196`: eight PASS / zero FAIL, exit0, including the cached caller fixture. Existing instance-output regressions pass 3+1 cases, exit0 each.

The cached caller fixture executes unchanged contiguous `CompactUnitFrame.lua` function definitions. Fixture-only probes control AI membership, walk-in and spectator inputs, with a formatting sentinel; this does not model AI state or establish native/localized wording.

## Known gaps (current cycle)

- [x] Targeted eight-case GREEN at sealed `e3978fd48196`; historical RED retained above.
- [x] Execute narrow cached-caller fixture; no full UnitFrame claim.
- [ ] Actual AI membership query remains a stub; fixture-controlled AI inputs do not prove it.

## Out of scope

AI party systems, native catalogs, localization, physical input/rendering, unrelated classifier validation/security changes and earlier-profile parity are independent contracts. Optional host ID uses existing bridge extraction conventions; no new coercion/domain policy is claimed. No vendor patches.
