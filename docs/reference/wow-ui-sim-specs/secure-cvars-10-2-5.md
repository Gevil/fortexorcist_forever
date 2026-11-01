# 10.2.5 secure-CVar combat policy

Seven secure-CVar names must extend the existing Retail combat-protected-name policy in `src/c_api/cvar_combat_policy.rs`. Genuine Retail RED at `76cf33ef3` reached the first insecure-combat `autoStand` write; it succeeded instead of being denied. The predicate now includes the seven names; defaults and registrations remain unchanged. Bounded Retail GREEN passes. Tests are Retail-only, matching current policy.

Accepted draft grounding: [local 10.2.5 publication source](../../data/patch-api/sources/10.2.5-api-changes.wikitext):67–76 attributes the hotfix to build 53441, February 23, 2024. Names: `autoStand`, `autoUnshift`, `SoftTargetEnemy`, `SoftTargetEnemyRange`, `SoftTargetForce`, `SoftTargetInteract`, `SoftTargetInteractRange`. Interpreting “secure” as denial of insecure writes only during player combat is an explicitly accepted simulator policy, not native security/error/timing or all-write-surface proof.

## What it must do

- [x] Both SetCVar and C_CVar.SetCVar reject genuinely tainted combat writes through the existing Lua error path, preserve previous global/namespace/case-normalized reads, and emit no CVAR_UPDATE.
- [x] Secure combat and tainted out-of-combat writes remain accepted, return true, update reads, and emit exactly one existing notification after storage changes.
- [x] Canonical/uppercase spellings share policy and stored value, preserving existing caller-spelling event payloads.
- [ ] Add seven names without removing the historical protected list; preserve nameplateShowEnemies combat-denial regression and existing 5.4.8 coverage. Four historical denial controls pass; whole-list and 5.4.8 runtime coverage remain unproved.
- [x] Refuse non-deps executable contexts before constructing WowLuaEnv; every matrix case uses existing per-process/per-instance temporary CVar storage, never user config/WTF.

## How it works

- [CVar registration contract](cvar-registration.md).
- [Lua API overview](../lua-api.md).

## Implementation inventory

- `tests/patch_10_2_5_secure_cvars.rs`: four tests, 88 matrix cases, preserved pre-construction executable-location storage guard.
- `src/c_api/cvar_combat_policy.rs`: Retail-only case-insensitive membership in the complete historical list plus the seven hotfix names.
- `src/lua_api/globals/set_cvar_verb.rs`: existing permission/storage/event path; unchanged.
- `src/cvars.rs`: existing temporary-store selection and persistence; unchanged.

## Tests asserting this spec

Current bounded proof: **4/4 PASS**, zero selected failures, fixture failures, skips or timeouts. [Integrated current proof](../wiki/investigations/integrated-source-and-factory-proof-2026-10-09.md#five-producer-and-receiver-source-checkpoint--2026-10-12) owns aggregate gates and retention status.

[tests/patch_10_2_5_secure_cvars.rs](../../tests/patch_10_2_5_secure_cvars.rs): three matrices of 7 names × 2 public setters × 2 spellings (28 each), plus 4 historical nameplate denial cases = 88 intended cases. At `76cf33ef3`, three tests passed and one failed: 60 matrix cases completed, one failed and 27 were unreached. Later test correction classifies the modeled permission error and uses named contexts; its current four-test proof passes all 88 cases. Each gets a bare environment and concrete secure out-of-combat old value 0 before listener installation, then attempts 1. Genuine stamped closure execution/stack taint is asserted independently of pcall outcome so taint setup failure cannot masquerade as denial. Accepted events must observe committed storage.

The executable-parent deps guard stays before environment creation. No HOME/XDG mutation, real configuration writes or standalone execution permitted. Temporary-file cleanup is not claimed; store path is not publicly exposed. No matrix name is skipped as unreadable; seeding does not prove native defaults/value domains.

## Known gaps (current cycle)

- [x] Genuine permission-assertion RED at `76cf33ef3`; not fixture/import/compile failure.
- [x] Current bounded Retail GREEN: 4/4 tests, exit0; all 88 matrix cases reached.
- [ ] Any unreadable seeded fixture is a separate blocker, not permission evidence or authorization to alter defaults/removal semantics.
- [ ] Native parity, exact errors/hotfix timing, whole historical list and other write surfaces remain unverified.

## Out of scope

synchronizeMacros/synchronizeSettings removal rows, defaults/publication, profile/epoch changes, bitfield writes, historical list replacement, UI/vendor/config/WTF changes, native probes, runtime infrastructure. No new state, defaults or registration change.
