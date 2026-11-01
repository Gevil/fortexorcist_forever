# Missing C namespace members

The October 20, 2026 removal decision makes unmodeled `C_*` members nil, rather than manufacturing callable functions. Runtime namespace attachment lives in `src/lua_api/env_init/runtime_surface_bootstrap.lua`; explicit registrations remain authoritative.

## What it must do

- [x] Unknown members remain nil under raw lookup, ordinary lookup, repeated lookup and `type`, without appearing in enumeration, across seven client profiles.
- [x] Explicit seeded defaults, state and actions remain unchanged.
- [x] Missing-member diagnostics remain available without publishing a value; strict and retired members remain nil.

## How it works

- [Namespace lookup and diagnostics](../wiki/systems/addon-loading.md#missing-c-members-f0-2026-10-20)

## Implementation inventory

- `src/lua_api/env_init/runtime_surface_bootstrap.lua` — shared nil diagnostic lookup.
- `src/lua_api/workarounds/temporary/housing_catalog_state.lua` — explicit housing defaults only.
- `src/lua_api/workarounds/temporary/{game_rules_namespace_fallback,guild_info_namespace_fallback,secure_transfer_state}.rs` — explicit surfaces and nil diagnostics, never arbitrary member fabrication.

## Tests asserting this spec

- `tests/c_namespace_nil_contract.rs` — lookup/enumeration and explicit registration contract, profile independent.
- `tests/nil_symbol_access.rs` — attributed, deduplicated nil observations.
- `tests/namespace_member_absence.rs` and `tests/classic_startup_namespaces.rs` — strict, ordinary and constructed namespace absence.
- `tests/guild_info_probes.rs` and `tests/housing.rs` — unknown-member nil expectations alongside unchanged explicit-state checks.
- Embedded tests in the three Rust modules above — preserved state/actions and nil expectations.

## Known gaps (current cycle)

- [x] Capture stock startup errors on all seven profiles and Retail startup tests without relaxing assertions.
- [x] Identify Forever's original T6 opaque timer pair: `C_UnitAuras.AuraIsBigDefensive`, called by the original private-aura watcher. [Attribution and closure](#forever-original-opaque-timer-pair--2026-10-22).

### Frozen F0 proof

Source anchor `0953c9b58`; `8c60cf5bb` changes documentation only. All seven builds use `sound,gui,casc,client-<profile>`; non-Retail disables default features. Each integration ELF binds this worktree's test source, and each stock executable's Cargo artifact binds its client profile. Surface, diagnostic, strict/constructor and embedded explicit-state subsets pass. Retail `startup_namespaces` passes 4/4; `startup_warnings` passes 24/26, with `test_no_warnings_on_startup` and `test_secure_env_annotated_files_load_cleanly` still failing.

| Profile | Stock unique errors | Occurrences |
|---|---:|---:|
| Retail | 108 | 185 |
| PTR | 108 | 188 |
| Wrath | 0 | 0 |
| Mists | 66 | 90 |
| Era | 52 | 70 |
| Anniversary | 52 | 70 |
| Forever | 208 | 224 |

The private F0 handoff's `gap-list.json` preserves every stock error, original consumer location and M1–M5/T6 routing, plus Retail assertion diagnostics. Alias/cascade attributions include original-source evidence and explicitly label inference. The two anonymous normal/wrapped timer rows retain a null member rather than an invented root. Committed baselines remain unchanged; comparisons use those empty baselines, not a fresh pre-removal run. Original persisted CVars retain their initial stat and hash.

**F0 alone is not mergeable.** Follow-up batches must restore clean stock startup and the two failing Retail tests without reinstating arbitrary member fabrication.

## Forever original opaque timer pair — 2026-10-22

Fresh integrated stock at `05dcf006b` reproduces 80 unique errors / 90 occurrences, including both byte-exact F0 opaque rows at four occurrences each. Timing-enabled callback-registry inspection identifies the original `FunctionUtil.lua:87` closure's `f` as `PrivateAuraUnitWatcher:Clean` (`Blizzard_PrivateAurasUI/Blizzard_PrivateAurasUI.lua:1256`). `MarkDirty` constructs that closure at line1280 and schedules it at line1283.

Replaying those unchanged callbacks with `xpcall` traceback and read-only line-hook capture identifies `player`, `party1`, `party2` and `party3` failures; `party4` succeeds. Each failing path reaches `Clean:1264` → anchor `ProcessAura:463` → `Blizzard_FrameXMLUtil/AuraUtil.lua:467`: `securecallfunction(C_UnitAuras.AuraIsBigDefensive, spellID)`. The nil function argument erases the member name in the ordinary error. The normal and ScriptErrors-wrapped rows describe the same four failures, not eight callbacks.

This is the original T6 missing-member gap, **not a newly exposed CF-2 cascade**. Forever's shipped `UnitAuraDocumentation.lua:55–67` declares a required `SpellIdentifier` and nonnil boolean. The existing [explicit classification model](aura-spell-classification-identifiers.md) now publishes its defensive query on Forever through `aura-spell-classifications`; supplied flags and empty-catalog false semantics are reused unchanged. Retail retains both getters; Forever's unrelated `AuraIsPrivate` remains nil. No vendor, VM, catalog, secret policy or factory changes.

`tests/cfactory_t6_opaque.rs::original_aura_util_classifies_an_unlisted_spell` executes the unmodified cached AuraUtil consumer: test-only `66336ee32` builds successfully and selects one genuine failing Forever test (`attempt to call a nil value`) before producer changes. Producer `6d396d23f` passes both new exact cases on Forever and Retail: each command selects one, passes one and ignores zero. The supplied-true case also preserves Forever's nil private query; Retail's existing 16 classification controls pass. Full-feature Forever stock changes **80/90 → 78/82** unique/occurrence counts: only the original two rows disappear (four occurrences each), with no added rows or changed remaining counts. Both stock commands still exit1; the unchanged non-opaque CF-2 frontier is not clean startup. Forever Cargo check and fmt pass with zero compiler warnings. Child-only current-CVar copies preserve content and per-run stat/hash; no reset or restore. This closes the original pair, not the deferred CF-2 gaps.

## Out of scope

- Implementing the missing backing models or introducing workarounds. Follow-up batches own those gaps.
