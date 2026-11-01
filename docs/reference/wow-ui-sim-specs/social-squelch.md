# Supplied social squelch state

`C_SocialRestrictions.IsSquelched()` projects the environment-local social restriction input for Retail, PTR and Mists. The original GroupFinder controls consume this value. See the [consumer investigation](../wiki/investigations/consumer-selection-and-red-proof.md#supplied-social-squelch).

## What it must do

- [x] Publish a non-nil boolean getter on Retail, PTR and Mists only in this change.
- [x] Read the supplied environment-local squelch flag without changing it; independent environments must not share the flag.
- [x] The original selected `LFGListCategorySelection_UpdateNavButtons` enables both find/start controls for false, disables both with the squelch tooltip for true, then enables both and clears both tooltips for false.

The pinned `Blizzard_APIDocumentationGenerated/SocialRestrictionsDocumentation.lua` declares `IsSquelched` at line 96 on Retail 12.1.5.70448 and PTR 12.1.7.70493, and line 62 on Mists 5.5.4.70268. Returns are non-nil `bool` at lines 101 and 67 respectively. The original restriction calls are in `Blizzard_GroupFinder/Mainline/LFGList.lua:189` (Retail), `Mainline/LFGList.lua:176` (PTR), and `Classic/LFGList.lua:94` (Mists).

The unrestricted initial flag is a simulator fixture input, not a native account-default claim. Hosts and tests may supply either value directly through `SimState.social_restrictions.is_squelched`.

## How it works

- [Consumer selection and RED proof](../wiki/investigations/consumer-selection-and-red-proof.md#supplied-social-squelch).

## Implementation inventory

- `src/lua_api/state_types/social.rs`: supplied social restriction record.
- `src/lua_api/state/sim_state.rs` and `src/lua_api/state.rs`: environment ownership and initial fixture.
- `src/c_api/c_social_restrictions.rs`: boolean getter and profile publication boundary.
- `src/c_api/mod.rs`: namespace registration.

## Tests asserting this spec

- `tests/social_squelch.rs`: original XML-created listing controls and independent-environment preservation across false/true/false.

## Known gaps (current cycle)

None in this lane. Paired original-consumer RED/GREEN, stock captures and all-target checks passed on all three profiles.

## Out of scope

Voice-provider queries, account-default policy, native moderation/network lifecycle, and publication on other profiles are not part of this lane.
