# Supplied party AI membership

`UnitInPartyIsAI(unit)` must expose explicit GUID classification intersected with the live active-party representation. `SimState.party_ai_guids` is an independent empty GUID set; the modeled producer uses the shared `retail-12-0-0` feature floor. Tests target `client-retail`/`client-ptr`. Producer implementation follows main's reported genuine 9/9 behavioral RED (including argument failures and the actual cached name consumer); Bounded Retail GREEN passes. This is current modeled behavior, not a historical 10.2.5 emulator.

## What it must do

### Supplied membership

- [x] Initialize an independent empty GUID set per environment; supplying a GUID creates no unit, roster member, target, dungeon or follower.
- [x] Resolve existing modeled identity and return true only if its GUID is both supplied and currently part of the active party representation. Unknown/absent/nonparty identities are false even when supplied; ordinary unsupplied members are false.
- [x] Same-GUID aliases agree; matching display names do not create equality. Retargeting does not transfer classification; retained focus remains classified only while its GUID belongs to the live roster.
- [x] Query live activity/roster each time; inactivation/removal clears effective membership immediately even with retained snapshots/metadata. Explicit set removal is reversible; environments remain independent.
- [x] Follower-dungeon state alone neither supplies nor spawns AI; supplied active-party AI does not require an instance. Classification does not remodel human/player identity.

### Accepted inferred policies

- [x] Include an explicitly supplied existing player GUID while the party is active, following current UnitInParty's player inclusion. Unsupplied/solo/inactive player is false. This is an inferred simulator policy, not native AI-player proof.
- [x] Use the existing active-party representation, without a new roster-size exclusion or party/raid taxonomy. Tests use two roster entries; raid-token/conversion behavior is not claimed.
- [x] Preserve nil/missing -> one false, strict string-or-nil inputs, ignored extra arguments and one plain nonnil boolean. No number coercion/token normalization or new result-secret policy.
- [x] Authenticate genuine VM secret inputs for untainted callers before state lookup, then enforce string/nil validation; reject tainted secret callers while preserving wrappers and caller taint. Ordinary tainted queries remain usable; authentic wrong-type secret numbers error.
- [x] Actual cached CompactUnitFrame name consumer, with a real FontString and real query, adds follower prefix only for supplied live AI in follower-dungeon context; ordinary members/context and removed retained aliases lose the prefix.

## How it works

- [Unit GUID presence](unit-guid-presence.md).
- [Unit identity and retained snapshots](unit-identity-equality.md).
- [Lua API overview](../lua-api.md).

The modern producer authenticates the original first argument through the VM, then validates nullable UTF-8 string input. It borrows live state with propagated errors, gates on `party_group_active`, and reuses `unit_roles::represented_identity` (existing GUID resolution plus active roster GUID comparison) before looking up supplied classification. Retained target/focus snapshots do not bypass live roster membership. Result is a plain boolean; no state, wrappers, or taint are changed.

Earlier profiles retain the original `Option<String>` extraction and false result in a separate temporary workaround. Its crate-visible re-export is exposed through the `workarounds` module, not the private `temporary` module. A Mists no-run compile at `be2fa83fb` reproduced `E0603` on that private-module import before any test ran; the import-boundary repair changes no query semantics. Post-repair compilation and runtime proof remain pending. No modern secret policy or AI backport is added.

## Implementation inventory

- `src/lua_api/state/sim_state.rs`: public `party_ai_guids: HashSet<String>` fixture field.
- `src/lua_api/state.rs`: independent empty initialization.
- `src/lua_api/globals/real/party_ai.rs`: modern non-C modeled producer.
- `src/lua_api/globals/group_queries_relationships.rs`: feature-selected re-export consumed by the unchanged group-query registration helper.
- `src/lua_api/workarounds/temporary/party_ai_legacy.rs`: unmodeled earlier-profile false query; retire when those profiles have an explicit model and policy.

## Tests asserting this spec

Current bounded proof: **9/9 PASS**, zero selected failures, fixture failures, skips or timeouts. Corrected active-cache AI name consumer reaches actual assertions. [Integrated current proof](../wiki/investigations/integrated-source-and-factory-proof-2026-10-09.md#five-producer-and-receiver-source-checkpoint--2026-10-12) owns aggregate gates and retention status.

[tests/party_ai_membership.rs](../../tests/party_ai_membership.rs): nine cases with main-reported behavioral RED; current bounded Retail GREEN passes for supplied/ordinary/player classification, aliases and equal-name controls, absent/nonparty identities, live inactivation/removal, reversible independent state, dungeon independence, nullable/plain type policy, authentic host-secret security, and cached real name consumer.

Consumer fixture loads unchanged contiguous CompactUnitFrame_UpdateName/IsTapDenied definitions from the active profile cache. Only visibility fixture input and localization sentinel are supplied; AI getter, walk-in/spectating predicates and actual FontString remain real. Walk-in TRUE is unmodeled and excluded. No vendor/cache changes or query overrides.

## Known gaps (current cycle)

- [x] Main reports genuine compiled behavioral RED, 9/9, including source-false/argument failures and the reached cached consumer; field/import/cache/fixture failures do not count.
- [x] Implement modern membership/authentication after genuine RED. No builds or runtime tests ran during this implementation slice.
- [x] Current bounded Retail GREEN: 9/9 tests, exit0.
- [x] Replace modern raw extraction with original-value VM authentication before nullable strict UTF-8 string validation. Cached current Retail UnitDocumentation.lua:1579–1592 declares AllowedWhenUntainted, nullable UnitToken, nonnil bool; this is not historical 10.2.5 secret-policy evidence.
- [ ] Native/PTR parity and slot lifetimes remain unverified. PartyMember has no GUID; current identity is slot-derived, so regrowth can reuse a GUID. No epoch/generation or slot-reuse contract is introduced.

Source limits: draft inspected cached Retail API/CompactUnitFrame sources and repository identity/group helpers, not native execution. [10.2.5 publication source](../../data/patch-api/sources/10.2.5-api-changes.wikitext) row 108 establishes publication only. Current UnitInParty is token-spelling based and cannot directly satisfy GUID-alias requirements; pet/vehicle lack represented GUIDs. Supplied AI is distinct from npc_follower_guids.

## Out of scope

New Admin commands, AI entity generation, party/human remodeling, raid identity expansion, metadata pruning, lifetime redesign, walk-in behavior, UI event wiring, nameplate lifecycle, other profiles, native probes, vendor/config/WTF changes. No central C API or other group-model changes.
