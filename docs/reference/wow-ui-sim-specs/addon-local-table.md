# Addon local-table access

`C_AddOns.GetAddOnLocalTable` returns the actual second Lua-chunk argument of a loaded addon opting in with `AllowAddOnTableAccess: 1`. [Patch 11.1.7 source](../../data/patch-api/sources/11.1.7-api-changes.txt) and cached `AddOnsDocumentation.lua:149–162` establish opt-in and denial of Blizzard addon tables to insecure callers. Native absent-target/error shape is unknown; policies below are explicit simulator choices.

## What it must do

- [x] Return the same nonnil namespace table used by all files of the opted-in addon; preserve identity across repeated calls and later addon loads. Caller mutation is visible to original target closures.
- [x] Retain that namespace through garbage collection after chunks return, including when only a weak test witness remains.
- [x] Resolve canonical loaded addon names, not display titles; never implicitly load a target or return a fabricated/copied table.
- [x] **Modeled policy:** unknown, registered-but-unloaded, title-only and unopted targets raise errors. Missing or zero opt-in does not expose the table.
- [x] Enforce documented `AllowedWhenUntainted` arguments using genuine VM secret authentication; preserve wrappers and caller taint.
- [x] Deny an insecure caller access to a Blizzard-classified target even with a plain name. Secure access to a loaded opted-in Blizzard target remains possible. Error shape is modeled; denial itself is sourced.

## How it works

- [Addon loading](../addon-loading-pipeline.md).
- [Lua API system](../wiki/systems/lua-api.md).

## Implementation inventory

- `src/loader/addon.rs`, `src/loader/lua_file.rs`: actual shared namespace creation/chunk arguments.
- `src/toc/mod.rs`: metadata and Blizzard classification.
- `src/c_api/c_addons_local_table.rs`: VM-registry-rooted records retain the original namespace, TOC opt-in and actual `loads_as_blizzard_code()` classification. Namespace and record are stack-rooted during construction; no Lua GC handles live in `SimState`.
- `src/loader/addon.rs`: retain the namespace before compiling/executing files; existing `AddonInfo.loaded` marks gate publication. No `SimState` borrow crosses registry allocation.
- `src/c_api/c_addons.rs`, `c_addons_registration.rs`: direct registration and existing name/index parser. VM `unwrap_secret` authenticates the original selector before parsing, including revoked-secret-context denial; `state_is_secure` independently rejects tainted plain-name Blizzard queries. Neither changes caller taint.

## Tests asserting this spec

`tests/addon_local_table.rs`: six behavioral tests with real temporary two-addon loading, original namespace identity/mutation, GC lifetime, opt-in/absence and genuine security boundaries. The parent runtime report at `080833f1d` records six genuine RED failures at the initial raw-registration assertion; namespace/security/GC assertions were not reached. Sealed Retail integration at `e3978fd48196` passes all six tests, exit0; identity, mutation, GC retention and access/security boundaries are now reached. Numeric selectors, unload and native behavior remain unverified.

## Known gaps (current cycle)

- [x] Verify retained rooted namespaces and opt-in access: six tests PASS at sealed `e3978fd48196`. [Bounded second-pass evidence](../wiki/investigations/integrated-source-and-factory-proof-2026-10-09.md) retains the pre-fix RED; the six-case GREEN above is bounded production proof.
- [ ] Native absent-target behavior and error text remain unverified.

## Out of scope

Reload/unload, failed-load/bootstrap-only publication, aliases/case normalization and native/earlier-profile parity are separate contracts. Numeric selectors reuse the existing addon parser but lie outside the six-test proof. No vendor edits or copied/empty namespace compatibility paths.
