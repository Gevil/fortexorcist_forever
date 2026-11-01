# Addon module imports

World of Warcraft: Forever 1.60.1 Beta exposes `require(moduleName)` as an import of an already-finished addon Lua file, not a filesystem or package loader. The `require` source contract is Warcraft Wiki revision 6879760. The PTR and Forever `import` callable reuses simulator compatibility policy, not an established native `import=require` contract; implementation notes live in [addon module imports](../wiki/systems/addon-module-imports.md).

## What it must do

### Completed module values

- [x] Publish values only after successful execution at the actual TOC/XML Lua-file loading boundary; imports do not execute files.
- [x] Return one original completed file value, including `nil`, `false`, tables and functions, preserving identity through garbage collection.
- [x] Reject imports of missing, self, or unfinished files with `Invalid import: No module with that name exists`.

### Module paths and addon boundaries

- [ ] Load TOC files from the selected addon directory without an implicit repository-local replacement; physical source paths must remain consistent with the root used for module provenance.
- [x] Resolve absolute logical paths as `Addon.Module` components without filesystem lookup; preserve requested addon and module spelling in the resolved identity.
- [x] Resolve a leading-dot path from the caller file directory; each additional leading dot ascends one directory.
- [x] Reject a relative path that has no caller-file origin or would escape its caller addon with `Invalid import: Relative imports may only be used within the same addon`.
- [x] Reject empty logical components, path separators, and control characters with `Invalid import: No module with that name exists`.

### Dependencies and dynamic callers

- [x] Permit a disk-file caller to import another addon only when its direct required or optional dependency matches the target addon case-insensitively; same-addon imports do not need a dependency.
- [x] Reject an undeclared cross-addon disk-file import with `Invalid import: Modules from other addons may only be imported if the calling addon has a direct dependency on the addon being imported`.
- [x] Exempt a dynamic caller from the cross-addon direct-dependency check for absolute paths.
- [x] Preserve registered file provenance for delayed nested closures; dynamically compiled chunks remain dynamic even with a spoofed addon filename.
- [x] Reject a dynamic relative request because it has no file origin. This is an explicit simulator policy; the source contract does not specify it.

### Forever import binding (simulator compatibility policy)

- [x] Expose global `import` on Forever before secure-environment copying, through the same direct Rust completed-module backend as `require`; preserve the existing `require` contract. Other-profile absence remains a separate gate below.
- [x] Return the same completed table to insecure and secure addon consumers, preserving callable members and single file execution; reject unfinished/failed/missing/non-TOC modules and undeclared dependencies without autoload or host-package fallback.

These executed Forever requirements reuse simulator policy justified by vendor `import('.Utility')` after the TOC-loaded `Utility.lua` returns a table. Native import/require semantics, identity, grammar and error parity remain UNKNOWN.

### PTR original module consumers

- [x] Expose `import` on PTR before secure-environment copying and track completed TOC/XML modules through the same `ModuleRegistry` used by Forever.
- [x] Resolve both original `Blizzard_GamepadSmartNavigation/SmartNavigation.lua:1` and `Debug.lua:1` imports to the original Utility table, preserving identity and callable behavior through garbage collection.
- [x] Reject an unresolved Utility dependency even when its file exists on disk; imports do not execute it.

PTR's pinned 12.1.7.70493 `Blizzard_GamepadSmartNavigation.toc:6` loads `Utility.lua` before both consumers (:8, :11). `Utility.lua:1` constructs a local table and :551 returns it. Both consumers begin with `local Utility = import(".Utility");`. `SmartNavigationMixin:RefreshButtonGroups` uses its captured table at `SmartNavigation.lua:1642`; `SmartNavigationDebug:OnUpdate` uses its captured iterators at `Debug.lua:88,92`. No generated APIDocumentation declaration or Lua definition for `import` was found in this pinned cache. These original statements justify extending the existing loader contract, not publishing a C_* API or claiming undocumented native parity.

### Profile isolation

- [x] Publish `import` in both PTR and Forever environments; preserve their existing `require` surfaces (completed-module lookup on Forever, restricted insecure lookup on PTR).
- [ ] Keep `import` absent and preserve `require` on the five unsupported profiles. The gate and tests exist, but their runtime absence selectors were not executed in this cycle.

Path/dependency requirements have sixteen pure resolver tests; registry/value/provenance requirements have fourteen actual-rilua unit tests. Fourteen current grouped integration tests exercise the real TOC/XML loader, delayed/coroutine imports, dynamic chunks, secure environments, addon varargs and existing peer-file taint behavior. Current original-consumer execution and seven-profile compilation are recorded in the [PTR checkpoint](../wiki/systems/addon-module-imports.md#ptr-original-consumers--2026-10-25); unsupported-profile runtime isolation remains unverified.

## How it works

- [Addon module imports](../wiki/systems/addon-module-imports.md)
- [Addon loading pipeline](../addon-loading-pipeline.md)
- [Client profiles](../wiki/systems/client-profiles.md)

## Implementation inventory

- `src/loader/module_import.rs` — pure logical path and direct-dependency resolver.
- `src/loader/addon_modules.rs` — completed-value registry, prototype-identity caller provenance, and direct Rust Forever `require` and PTR/Forever `import` installation seam.
- `src/lua_api/env.rs` — per-VM module metadata; module values and source closures are rooted in the Lua registry.
- `src/lua_api/mod.rs` — internal VM context re-export used by the shared registry on every profile; it does not publish Lua globals.
- `src/loader/mod.rs` — declares the shared resolver and runtime modules; ACTIVE gates publication and completion tracking.
- `src/loader/lua_file.rs` — registers compiled-file provenance and publishes the existing execution helper's first return only after success.
- `src/loader/addon.rs` — loads files from the selected TOC source rather than substituting a same-named repository-local file.
- `src/lua_api/env_init/mod.rs` — installs PTR/Forever imports before secure-environment copying and preserves non-Forever `require` sandbox behavior.
- `src/client_profile.rs` — selects the distinct Forever profile and interface version.

## Tests asserting this spec

- `src/loader/module_import.rs` — sixteen unit tests for absolute/relative resolution, addon boundary rejection, direct dependency authorization, dynamic absolute exemption, malformed requests, and exact errors.
- `src/loader/addon_modules.rs` — fourteen actual-rilua tests for completed values/GC identity and stack restoration, load boundaries, delayed/escaped closures, direct dependencies, spoofed dynamic sources, nearest dynamic origins, failed loads/replacement, non-reexecution and VM isolation.

- `tests/ptr_module_import.rs` — original selected SmartNavigation/Debug closure, original Utility identity/GC and real button-group changes, missing absolute lookup, and on-disk non-TOC rejection followed by completed-file success in a fresh environment. Each selector rejects constant/no-op import producers independently.
- `tests/addon_require.rs` — fourteen current Forever loader-boundary tests, including TOC dependencies, XML files, values, failed/self/forward imports and caller provenance.
- `tests/forever_bug_capture.rs` — absolute local TOC loading followed by real error-capture consumers; requires the local BugGrabber/BugSack sources.
- `tests/sandbox_dangerous_globals.rs` — profile-specific global/secure-environment exposure and absence of host package loading.
- `tests/wowforever_profile.rs` — distinct profile identity, client paths, TOC routing and build information.

## Binding checkpoint — 2026-10-15

Source integrated at `012df1e45`: the binding adds only `import` registration to the existing backend, not a stub or new loader. Current runtime-code `c2bf42c4f`, built at `57f8e0b10`, has saved bounded import/control execution and a completed-table/vendor-method probe; independent bounded reconciliation PASS. [Central receipt](../baselines/README.md#current-importevents-execution--2026-10-15) owns counts, artifacts, failing startup and limits. [Owning wiki checkpoint](../wiki/systems/addon-module-imports.md#forever-import-binding--2026-10-15) separates historical RED from current execution; native parity remains unknown.

## Known gaps (current cycle)

- [x] Independent bounded import/control verification and normal vendor-method probe passed at the recorded source.
- [ ] Unsupported-profile runtime isolation and clean startup remain open. Seven-profile compilation passes, but it is not whole-client runtime acceptance.
- [ ] Native Forever execution is not part of this task; the Wiki contract and local behavioral fixtures do not establish undocumented native edge cases.

## Out of scope

No generic Lua package loader, filesystem lookup at import time, native-client conformance claim, or inferred behavior for multiple returns, module-name case normalization, duplicate module names, failed reload replacement, separate module environments, or TOC module-registration annotations. Those source semantics are unspecified and are not simulator guarantees.
