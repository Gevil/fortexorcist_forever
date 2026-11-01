# Hook callback origin

Simulator-owned `HookScript` and `hooksecurefunc` adapters must not acquire the installing addon's taint. They invoke original and hook functions without changing those functions' own origin or the invocation caller's taint.

## What it must do

- [ ] A hook installed by addon code must leave a trusted original secure when invoked from a clean engine context; the addon hook remains insecure.
- [ ] A hooked function called from addon code remains subject to that caller's taint; constructing the adapter must not clear the addon caller.
- [ ] Preserve original-before-hook ordering, original multi-return values including nil gaps, and existing error behavior.
- [ ] Generate only the fixed engine adapter, not arbitrary caller-supplied source. Do not taint an originally clean global slot merely by installing its secure hook.
- [x] Hooks belong to the exact target object and method key. Hooking an inherited or copied wrapper must not append that callback to the source target's hook list. Preserve inherited hooks and repeated-hook ordering on the actual target.
- [x] A texture-metatable pixel-snap hook followed by instance-local arrow and action-border hooks must not repaint the arrow when another texture's border is repainted.

## How it works

- [Event system](../event-system.md)
- [Closure taint lifetime](closure-taint-lifetime.md)

## Implementation inventory

- `src/lua_api/frame/methods/text_attribute_event/events/script_binding_args.rs` — protected creation of the fixed HookScript adapter.
- `src/lua_api/env_init/shared_bootstrap.lua` — bootstrap-owned secure-hook factory, without runtime loadstring generation.

## Tests asserting this spec

- `tests/hook_script.rs` — original/hook/caller taint, result preservation and existing chaining behavior.
- `tests/security_api.rs` — existing global/table hook consumers.
- `tests/secure_hook_target.rs` and `tests/fixtures/ellesmere_hook_consumers.lua` — inherited/copied target isolation, ordering/nil returns, and real extracted Ellesmere consumers driven by a timer.

## Bounded proof — 2026-10-18

Forever build `cc8c334820279e87a2360e8c606395ae72bf3dee`, features `sound,gui,casc,client-wowforever`, default features disabled:

| Boundary | Proof |
|---|---|
| Extracted real consumer, original seal `70a334c0f` | RED: three button repaints invoke an unrelated arrow's paint hook 24 times; twelve buttons produce 312. |
| Rebuilt timer consumer and target/key isolation | GREEN: `secure_hook_target::` 3/3. |
| Existing hook controls | `hook_script::` 16/16, including taint and nil-return preservation; `hooksecurefunc` filter 3/3. |
| Real archived addons, uninstrumented callback | Timer125 returns `outcome=ok` in 591.188 ms; public AF_UNIX Exec sent after callback entry returns in 2.551545 s. Subsequent populated draws and normal ticks complete. |
| Static gates | `cargo fmt --all -- --check` and locked single-job Forever `cargo check` exit 0. Build/check each retain the unchanged `unit_roles.rs:17-19` dead-code warning for Tank/Healer/Damage. |

Proof: `tests/secure_hook_target.rs` with the extracted consumer fixture `tests/fixtures/ellesmere_hook_consumers.lua`; real-addon GUI receipts are retained in the private handoff, not in the repository.

## Known gaps (current cycle)

- [ ] Native conformance, other-profile execution and full Ellesmere interaction acceptance remain outside this bounded proof. Other GUI Lua errors and the unchanged UnitRole compiler warning are not repaired by this fix. Historical taint RED is superseded only by the selected passing Forever controls above.

## Out of scope

Clearing callback taint, changing addon code, general-purpose trusted compilation, or full native hooking conformance.
