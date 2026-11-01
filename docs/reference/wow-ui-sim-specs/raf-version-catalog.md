# Supplied RAF version catalog

`C_RecruitAFriend.GetRAFInfo` must not manufacture a version-1 record. Its version rows come from environment-local supplied state in `src/c_api/c_recruit_a_friend.rs`. The existing disabled enable probes and absence defaults for recruitment/recruits remain unchanged. See [consumer evidence](../wiki/investigations/invented-query-defaults.md).

## What it must do

- [x] A fresh environment returns an empty `versions` array, with the existing empty recruits, nil recruitment info, and false claim flag.
- [x] Explicitly supplied versions project their version identifier, lifetime/spent/available month counts, recruit count and affordable-reward count without choosing native values.
- [x] Every version has a `monthCount` record, empty `rewards` array and absent `nextReward`, preserving the declared shape for this bounded no-reward input.
- [x] The selected original RecruitAFriend frame's system-enable event reads the API and distinguishes empty from supplied version state.
- [x] The prior one-row API assertions use an explicit fixture instead of a seeded default; the fresh-environment assertion expects zero versions.

## How it works

- [Pinned declarations and original-consumer evidence](../wiki/investigations/invented-query-defaults.md)

## Implementation inventory

- `src/c_api/c_recruit_a_friend.rs` — version input model and query projection.
- `src/lua_api/state/sim_state.rs` — environment-local version catalog.
- `src/lua_api/globals/missing_surface/recruit_a_friend.rs` — existing registration, without invented rows.
- `src/lua_api/globals/admin.rs` — explicit fixture inputs.

## Tests asserting this spec

- `tests/blizzard_recruit_a_friend_loads.rs::original_raf_enable_event_distinguishes_empty_and_supplied_versions`
- `tests/startup_api_glue.rs::recruit_a_friend_surface_returns_disabled_empty_defaults`
- `tests/startup_api_glue.rs::recruit_a_friend_surface_preserves_explicitly_supplied_version_fields`

## Known gaps (current cycle)

None in this bounded version-presence contract. Retail/PTR/Forever original-consumer RED/GREEN, four consumed-profile stock comparisons and all seven zero-warning all-target checks pass; this is not full RAF service coverage.

## Out of scope

Native RAF enablement, reward eligibility and ordering policy, nonempty reward/recruit catalogs, reward claiming, recruitment links, and cooldown changes. Month/count values are supplied facts, not inferred server policy.
