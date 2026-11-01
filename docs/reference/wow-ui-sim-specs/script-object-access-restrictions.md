# Script-object access restrictions

Retail-family 12.1+ and Forever script objects store conditional access-restriction flags separately from their forbidden flag, published through the shared `forbidden-aspects` capability. The contract comes from cached `Blizzard_APIDocumentationGenerated/SimpleFrameScriptObjectAPIDocumentation.lua`; `Blizzard_AuraContainerUtil.lua` applies the flags while creating aura buttons.

## What it must do

- [x] `AddAccessRestrictions(mask)` accumulates the supplied mask with bitwise OR; zero and repeated additions do not remove existing flags.
- [x] `GetAccessRestrictions()` returns the object's stored mask, initially zero.
- [x] `HasAnyAccessRestrictions()` and an explicit nil argument test for any stored restriction; a supplied mask tests for any intersecting bit, with zero matching none.
- [x] `HasAccessConstraints()` reports true for either the existing forbidden flag or a nonzero conditional-restriction mask.
- [x] Restrictions remain per-object and do not change the forbidden flag or another object's mask.
- [x] Unchanged cached Blizzard `AuraContainerUtil.ApplyAccessRestrictions` defers pre-login requests until `PLAYER_ENTERING_WORLD`, not `PLAYER_LOGIN`; calls after login apply immediately. Sharing mask methods must preserve both cached branches without changing Blizzard Lua.

Checkboxes record bounded accepted Retail/PTR/Forever mask and cached-application execution, not native-client, GUI or all-method enforcement. Capability scope and separate live-enforcement proof follow below.

## How it works

- [Frame data flow](../frame-data-flow.md)
- [Protected frame enforcement](../protected-frame-enforcement.md)

## Implementation inventory

- `src/widget/frame.rs`, `frame_defaults.rs` — zero-default `access_restrictions` mask.
- `src/lua_api/frame/methods/text_attribute_event/access_restrictions.rs` — mask mutation and queries.
- `src/lua_api/frame/methods/text_attribute_event/mod.rs` — registration under `forbidden-aspects`; `ClearScripts` remains Retail-12.1-only and `GetObjectTable` has one shared registration.
- `src/lua_api/frame/methods/text_attribute_event/attributes.rs` — combined `HasAccessConstraints` query.

## Tests asserting this spec

- `tests/forbidden_frames.rs` — shared-capability mask accumulation/filtering, object isolation, combination with forbidden state, and actual cached Blizzard AuraContainer pre-login/world-entry/post-login application.
- `tests/patch_12_1_0_aura_access_restrictions.rs` — Retail aura-secret method access, initialization before restriction, and pre-login accessibility through `PLAYER_LOGIN`.

### Bounded profile proof — 2026-10-16

The three mask/cached-application cases are the same logical cases executed separately for each supported `forbidden-aspects` profile; they are not nine distinct behaviors. They cover OR/zero/repeated additions and optional filtering, per-object isolation and forbidden-state union, and actual cached `AuraContainerUtil.ApplyAccessRestrictions` before login, through `PLAYER_LOGIN`, at `PLAYER_ENTERING_WORLD`, and immediately after login. Cached Blizzard Lua runs inside the simulator; this is not native-client conformance.

| Profile | Mask/cached application | Separate live aura-secret consumer | Proof level |
| --- | --- | --- | --- |
| Retail | 3/3 PASS, exit0 | 3/3 PASS, exit0 | Independently accepted bounded saved execution |
| Forever | 3/3 PASS, exit0 | Not credited; no Forever live-enforcement claim | Independently accepted bounded saved execution |
| PTR | 3/3 PASS, exit0 | 3/3 PASS, exit0 | Independently accepted bounded saved execution |

Retail test checkout `4b0ebcde3` links separately sealed normal library `a2d2d2792`; component compilation exits0 with 29 inherited common-fixture warnings. Independent full-stream/source/library/seal acceptance: `/home/osso/.local/state/wow-ui-sim/verification/access-restrictions-next/retail-report.md`.

Forever test source `9792c06d2` links separately sealed normal library basis `58bccba22`; component compile PASS with 26 inherited common-helper warnings. Independent acceptance: `/home/osso/.local/state/wow-ui-sim/verification/access-restrictions-next/forever-report.md`. Earlier precompiler metadata error and runtime capacity HOLD are not failed execution and remain in that report.

Profile runtime receipts resolve through `/home/osso/.local/state/wow-ui-sim/handoff/access-restrictions-forever-epoch.txt` and `access-restrictions-ptr-epoch.txt` in the same directory. Forever and PTR successful launchers use fresh child-only `XDG_DATA_HOME` copies of the current persisted CVar bytes; paired original stat/hash records stay unchanged. This does not mean retained child files remain immutable. PTR test source `f136f7ec9` links separately sealed normal library `0eba46a74`; compile0/29 inherited warnings, both commands exit0. Independent full-stream/source/profile/seal/CVar acceptance: `/home/osso/.local/state/wow-ui-sim/verification/access-restrictions-next/ptr-report.md`.

### Capability scope (source inspection, not absence execution)

`Cargo.toml` publishes `forbidden-aspects` in the ordinary client bundles only for Retail (`client-retail` → `retail-12-1-0`), PTR (`client-ptr` → `retail-12-1-5` → `retail-12-1-0`), and Forever (`client-wowforever` → `forbidden-animation-aspects` → `forbidden-aspects`). Wrath, Mists, Era and Anniversary bundles do not select it. This is source-level bundle scope, not an executed Classic absence assertion or a prohibition on explicit extra feature selection.

`src/lua_api/frame/methods/text_attribute_event/mod.rs` registers mask methods under `forbidden-aspects`. Live aura-secret denial in `src/c_api/unit_aura_access.rs` separately requires `retail-12-1-0`; shared mask publication does not establish Forever enforcement. Existing other APIs and their gates are unchanged.

## Known gaps (current cycle)

- [x] Independently accept bounded normal-profile mask/cached-application execution for Retail, PTR and Forever; separate live aura-secret enforcement cases accepted only for Retail/PTR.
- [ ] Historical Forever GUI missing-method failure at `/tmp/ellesmere-forever/secure-chain-gui.stderr` (`Blizzard_AuraContainerUtil.lua:421`, `AddAccessRestrictions` after login) now has accepted bounded cached-consumer coverage for that method/application boundary. The original GUI scenario was not replayed here; whole shared-profile GUI acceptance remains open.
- The separate [Forever context-access query](script-object-context-access.md) uses an explicit per-environment aura-secret scenario on that query only. It does not derive live aura secrecy or enforce restrictions on other frame methods. No native, GUI, whole-integration, all-method security or parent-goal acceptance is claimed.

## Out of scope

Inventing aura-secrecy policy, context-dependent access checks, new restrictions, or changing addon/vendor Lua. Only `DenyTaintedAccessWhenAurasAreSecret = 1` currently has a named enum value; generic mask algebra does not establish live-client validation rules for unnamed bits.
