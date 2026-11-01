# CF-2 social, party, and LFG consumers

CF-2 slice 1 covers unchanged profile-cache Blizzard social and scenario consumers. New C namespace queries and their backing models belong in `src/c_api/`; no Blizzard Lua changes or general factory-gap closure are authorized. Tests are authored but have not been built or executed.

## What it must do

### Club invitations preservation: Retail, PTR, Forever, Mists, Era, Anniversary

- [ ] With explicitly empty supplied club state, the original `GuildMicroButtonMixin:HasUnseenInvitations` returns `false`, and `C_Club.GetInvitationsForSelf` projects an empty table.
- [ ] Existing displayed-invitation history does not manufacture an incoming invitation when supplied club state remains empty.

### Scenario availability: Retail, PTR, Mists

- [ ] `C_PartyInfo.GetMinLevel` uses the lowest supplied party/player level: a level-60 player grouped with a level-49 member yields 49; raising that member to 50 yields 50; leaving the party yields 60.
- [ ] The unchanged `ScenarioFinderFrame_UpdateAvailability` consumes explicitly supplied scenario records through normal catalog APIs. Both specific and random catalogs must drive the original branches.
- [ ] For scenario ranges 80–90 and 50–70 supplied in that order, a level-49 party shows the cover with next level 50. An ordinary dungeon covering levels 1–100 must not make scenarios available.
- [ ] Raising the lowest party level to the inclusive lower boundary 50 hides the cover. Leaving the party restores the level-60 player's availability without recreating the consumer.
- [ ] An explicitly empty catalog shows the no-scenarios cover and generic unavailable text, not an invented next level.

The scenario fixture uses existing `LfdDungeonInfo` records (`subtype_id = 4`, the cache's `LFG_SUBTYPEID_SCENARIO`; `is_random` distinguishes the fixture catalogs). This specifies supplied simulator input, not a claim about native catalog ordering or native service defaults. Translated strings and minimal widgets are presentation fixtures; no consumer or API function is replaced.

## How it works

- [C API ownership and social inputs](../wiki/systems/lua-api.md#factory-removal-social-inputs--2026-10-21)
- [Addon loading](../addon-loading-pipeline.md)

## Implementation inventory

- `tests/cfactory_cf2_social.rs` — original scenario consumers with real roster and dungeon-state inputs.
- `tests/cfactory_cf2_social_preservation.rs` — empty club-invitation boundary preservation, not producer acceptance.
- `src/c_api/club_model.rs` — existing club/invitation state; incoming-self semantics await native evidence.
- `src/lua_api/game_data.rs` — existing party member levels.
- `src/lua_api/globals/battlefield_lfg_probes.rs` — existing dungeon projection; scenario catalog functions currently return empty placeholders. Replacement modeled behavior belongs in `src/c_api/`.
- `src/lua_api/workarounds/temporary/social_service_defaults.rs` — documents absent authoritative social/LFG capability snapshots; not evidence for new native defaults.

## Tests asserting this spec

`tests/cfactory_cf2_social_preservation.rs`:

- `original_guild_microbutton_has_no_unseen_invitations_with_empty_clubs_preserves_boundary` — preservation only; an empty producer satisfies it.

`tests/cfactory_cf2_social.rs`:
- `original_scenario_specific_catalog_uses_lowest_party_level`
- `original_scenario_random_catalog_uses_lowest_party_level`
- `original_scenario_empty_catalog_keeps_no_scenarios_cover_preserves_boundary` — preservation only; a constant empty catalog satisfies it.

File-level profile cfg registers club preservation only on its six applicable profiles and scenarios only on Retail/PTR/Mists. Other profiles register no such tests; there are no runtime N/A returns.

Club invitations have no producer acceptance until the outstanding laptop PENDING-NATIVE-ORACLE answers establish populated incoming-self inputs and transitions. No invitation producer may be written before those answers and a genuine populated RED test. Only the two populated scenario cases belong to the expected-RED matrix (six profile executions). Empty-catalog preservation adds three executions, excluded from RED along with the six club-preservation executions.

## Known gaps (current cycle)

- [ ] Runtime RED has not been observed: EDIT-ONLY phase has no build slot.
- [ ] Missing `GetInvitationsForSelf` and `GetMinLevel` producers; scenario catalog placeholders ignore supplied records.
- [ ] PENDING-NATIVE-ORACLE: populated incoming-self invitation storage, projection, and notification lifecycle.
- [ ] PENDING-NATIVE-ORACLE: `C_SocialRestrictions.IsSquelched` authoritative input/default and restriction behavior (Retail/PTR/Mists original LFGList).
- [ ] PENDING-NATIVE-ORACLE: `C_LFGInfo.IsLFREnabled` authoritative service input/default (Mists original PVEFrame).

## Out of scope

Native defaults, account penalties, LFR service policy, and populated self-invitation policy are not invented from missing-member errors. No new temporary workaround is authorized by this test-only change. Other CF-2 slices, vendor edits, builds, execution, push, merge, deployment and full-suite acceptance are excluded from this phase.
