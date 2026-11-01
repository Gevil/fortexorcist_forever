# Unit role assignment

`UnitSetRoleEnum` and `UnitSetRole` assign explicit display roles to represented player/party identities; `UnitGroupRolesAssignedEnum` and `UnitGroupRolesAssigned` read the same live role. Active Retail evidence inspected 2026-10-12: profile cache `Blizzard_APIDocumentationGenerated/UnitRoleDocumentation.lua:55–106` and `UnitDocumentation.lua:1290–1322`. See [Lua API](../lua-api.md) and [event dispatch](../event-system.md) for existing runtime architecture. This contract does not claim native behavioral proof for inferred policies.

## What it must do

### Declared API and coherent state

- [x] Register both setters as real globals. `UnitSetRoleEnum(unit: UnitToken, role: LFGRole?)` and `UnitSetRole(unit: UnitToken, roleStr: cstring?)` return exactly one boolean.

Both setters declare `HasRestrictions` and `SecretArguments = AllowedWhenUntainted`; metadata declarations are source evidence, not runtime assertions.
- [x] Both getters accept nullable `UnitToken`, return exactly one nonnil value (`cstring` or `number`). Preserve the existing identity-restriction policy rather than making all role reads public or always secret.

Getter declarations specify `SecretWhenUnitIdentityRestricted` plus `AllowedWhenUntainted`; metadata declarations are source evidence, not runtime assertions.
- [x] Round-trip Tank=0/`TANK`, Healer=1/`HEALER`, Damage=2/`DAMAGER` through either setter and either getter. No class/catalog/spec-derived auto-role inference.
- [x] **MODELED ASSUMPTION:** default unset and unrepresented nullable getter input return `NONE`/-1, preserving existing getter defaults. Missing/nil role arguments clear; string `NONE` and enum -1 also clear. -1 is the existing `Constants.LFG_ROLEConstants.LFG_ROLE_NO_ROLE` consumed by cached `RolePoll.lua:78–86`, not a fourth `Enum.LFGRole` entry.
- [x] **MODELED ASSUMPTION:** store explicit roles per represented identity in the environment, not selected unit-token spelling or display name. Player and two party members remain independent; target/focus aliases with the same existing GUID observe/write the same role. Losing a selection does not erase that identity's role. Changing display names or class metadata does not infer/reset roles. Separate environments do not share assignments.

### Validation and authority

- [x] **MODELED ASSUMPTION:** require a nonnil UTF-8 unit string; nullable enum role must be numeric, nullable string role must be UTF-8 string. No string/number coercion. Type validation precedes unknown-unit lookup. Invalid numeric domains (including fractional/nonfinite values) and unsupported case-sensitive role strings return false, preserving state/events.
- [x] **MODELED ASSUMPTION:** unknown units, nonrepresented selected entities, pets/vehicles/enemies, and hidden inactive roster members cannot gain a player/party role; setters return false without mutation/event. No synthesis of roster identities.
- [x] **MODELED ASSUMPTION:** self assignment, including solo self, is allowed; another represented active party member requires existing player leader/assistant authority. Cached `UnitPopupSharedButtonMixins.lua:3460–3482` supports this UI eligibility, but does not prove native setter enforcement. Reuse existing authority state; do not redesign groups or infer extra combat/network/LFG restrictions from the bare `HasRestrictions` declaration.
- [x] **MODELED ASSUMPTION:** valid identical assignment returns true without a duplicate role-change event. Ordinary addon-tainted calls with public arguments remain allowed when modeled authority permits; `HasRestrictions` alone is not a blanket addon prohibition.

### Synchronous event and actual callers

- [x] Emit the declared synchronous `ROLE_CHANGED_INFORM(changedName, fromName, oldRole, newRole)` with four nonnil strings before the setter returns. Event handlers must observe the new role through both getters.
- [x] **MODELED ASSUMPTION:** emit only an actual successful transition; names are current represented recipient/player display names, roles use `NONE`, `TANK`, `HEALER`, `DAMAGER`. Rejections and valid no-ops do not emit. Clear reports the prior role and `NONE`.
- [x] Exercise unchanged cached `UnitPopupSetRoleNoneButton.OnClick` and inherited Tank/Healer handlers at `Blizzard_UnitPopupShared/UnitPopupSharedButtonMixins.lua:3507–3513`: actual enum writes/nullable clear, return `MenuResponse.Close`, and checked Tank/Healer reads.
- [x] Exercise unchanged whole `RolePollPopupAccept_OnClick` at `Blizzard_FrameXML/Mainline/RolePoll.lua:84–88` on real test-created parent/button widgets, using the whole original file rather than a copied handler. Observe player mutation and synchronous event during that handler; preserve its void return. Test its real -1 clear sentinel. This proves the bounded handler call, not full RolePoll XML readiness, physical click, rendered menu or native client parity.

### Genuine secrets

- [x] Accept genuine VM `secretwrap` unit/role inputs from an untainted caller, separately and together, including wrapped nil clear. Keep original wrappers secret with identical payloads and preserve caller taint. Authenticated malformed payloads still undergo strict type/domain checks without mutation/event; wrapped nil unit is invalid, unlike wrapped nil role.
- [x] Deny authentic secret arguments from genuinely addon-tainted callers for both setters and getters. Authenticate original declared arguments before type validation, lookup or mutation; a malformed public unit plus secret role must yield secret-access denial, not type/lookup short-circuit. Denial preserves role, event count, wrappers and caller context.
- [x] Under `retail-12-1-0`, identity-restricted getter outputs wrap the actual assigned string/number payload for both secure and addon callers; unrelated player/member reads remain public. Retain existing predicate behavior rather than inventing a new role-only secrecy model.

## How it works

- [Lua API](../lua-api.md): global registration and state-backed Lua surface.
- [Event system](../event-system.md): synchronous dispatch and script callbacks.
- [Client profiles](../wiki/systems/client-profiles.md): selected profile cache and feature epochs.

## Implementation inventory

- `src/lua_api/globals/group_queries.rs` — current getter registration.
- `src/lua_api/globals/real/unit_roles.rs` — shared getter validation/secrecy and existing GUID comparison; profiles without assignment producers retain unset `NONE`/-1 reads.
- `src/lua_api/globals/real/unit_roles_assignment.rs` — Retail/PTR-only three-value role representation, live read projection, strict authenticated setters and changed-only synchronous event; earlier profiles do not gain setters.
- `src/lua_api/globals/group_queries_relationships.rs` — existing leader/assistant authority helpers and default eligibility; constant role getters removed.
- `src/lua_api/globals/targeting_verbs.rs` and `unit_misc.rs` — existing represented snapshot/GUID resolution.
- `src/lua_api/globals/real/unit_secret_predicates.rs` — existing getter identity-secrecy finishing.
- `src/lua_api/state/sim_state.rs` and `src/lua_api/state.rs` — Retail/PTR-only environment-owned GUID-to-optional-role map, initially empty; existing player/party/authority inputs unchanged.
- `src/lua_api/globals/enum_data/widget.rs` and `constants_values.lua` — existing LFGRole enumeration and unset constant.

## Tests asserting this spec

- `tests/unit_role_assignment.rs` — staged public round-trip/default/clear, identity aliases, environment/party isolation, domain/type/authority policies, synchronous event, authentic secrets, conditional getter secrecy and unchanged cached handlers. **13/13 GREEN**, exit0, at source `080833f1d182caaa762c734a988847edd20f633b`, including unchanged popup handlers and the whole RolePoll accept handler. GREEN3176 runtime `runtime-scoped-20261013T013111696766Z`, artifact epoch `admitted-native-20261013T011400020026Z`; recorded compile/runtime source maps equal and saved seals unchanged by stat receipt. Public packet not yet retained; no public evidence link claimed. Historical parent RED remains unchanged: all 13 failed at missing raw `UnitSetRoleEnum`, with downstream assertions unreached. Checked modeled policies remain simulator models, not native proof.
- `tests/admin_pvp_guild_api.rs::test_unit_group_roles_assigned_returns_none` — unset string/numeric reads, arity, nullable/unrepresented inputs and malformed-unit rejection; current rerun receipts remain separate from historical Retail/PTR acceptance.
- `tests/patch_12_1_0_unit_secrecy.rs` — existing getter identity-restriction rows; no new run or acceptance credit here.

## Known gaps (current cycle)

- Production registration/backing committed; bounded GREEN above verifies the reached contract assertions only. Full XML/menu/startup and native acceptance remain unproved.
- [ ] Cached popup None radio compares numeric getter with nil `GetRole()`, unlike the declared nonnil getter and existing -1 sentinel. Preserve vendor behavior and numeric contract; do not claim checked-None behavior or patch Blizzard Lua in this scope.
- [ ] Native invalid-domain/authority/no-op/name/clear policies remain assumptions, with no native capture.

## Out of scope

- Network/server/catalog role acquisition, class-role auto inference, matchmaking/available-role eligibility, role polls themselves, group redesign and earlier-profile parity: independent contracts, not needed for this assignment backing.
- Invented combat/LFG restriction enforcement: documentation supplies `HasRestrictions`, not exact native policy.
- Full menu/RolePoll startup/rendered/native acceptance and vendor changes: staged test uses bounded original whole handlers only.
