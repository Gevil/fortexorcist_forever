# Club self invitations

`C_Club.GetInvitationsForSelf` reads supplied active-player invitation snapshots under `src/c_api/`. This is the bounded C_Club split from CF-2 social/party, not an LFG/default-policy change. [Implementation](../wiki/systems/club-membership.md#incoming-self-invitations-cf-2).

## What it must do

- [ ] Under the documented initialized-clubs precondition, return one non-nil array of `ClubSelfInvitationInfo`; the user-authorized default is an empty supplied list, never fabricated rows.
- [ ] Return current supplied rows in supplied order, independent of subscribed clubs and outgoing invitations. Each row has invitationId, club, inviter and leaders; club/member records include all non-null documented fields. Nilable ClubInfo metadata is absent in this bounded model; members use the existing supplied Member projection.
- [ ] The runtime-selected Retail GuildMicroButton original `HasUnseenInvitations` must observe empty → unseen → displayed → second unseen → all displayed → replacement unseen → empty → unseen transitions.

## How it works

- [Club model and self-invitation projection](../wiki/systems/club-membership.md#incoming-self-invitations-cf-2).
- [Consumer-selection proof policy](../wiki/investigations/consumer-selection-and-red-proof.md).

## Implementation inventory

- `src/c_api/club_model.rs`: `ClubState.self_invitations`, empty by default.
- `src/c_api/club_self_invitations.rs`: supplied snapshot types and fresh Lua record projection.
- `src/c_api/club_members.rs`: namespace registration; existing Member projection reused.
- `src/c_api/mod.rs`: C API module publication.

## Tests asserting this spec

`tests/cf2_club_invites.rs::original_guild_micro_button_tracks_supplied_self_invitations` is the single producer RED selector. Registered only for client-retail; test harness discovers tests/*.rs via `crates/test-harness`. Data-only schema is included in RED commit `9564b1c38` so RED is not a missing-type compiler failure. No build or test executed during staging; no runtime PASS/RED claimed.

### Selection proof (static; executable checks deferred)

Retail resolver `src/loader/mod.rs::active_profile_toc_suffixes` chooses `_Mainline` before generic/Standard. Cached `Blizzard_MicroMenu/Blizzard_MicroMenu_Mainline.toc` permits mainline + Game, requires Blizzard_Communities, and directly selects Mainline/MainMenuBarMicroButtons.lua and .xml: no [Game]/[Family] substitution or per-file exclusion intervenes. XML :183 declares GuildMicroButton with GuildMicroButtonMixin and NotificationOverlay. The closure harness discovers/loads dependencies using the Game screen and selected TOCs, without overrides or extracted Lua. The selector checks actual selected TOC/parsed entries, loaded addon, XML child, and debug.getinfo source provenance before calling the actual button's original method (:1229–1238; producer call :1230).

An earlier setup/load/provenance failure is a fixture blocker, not producer RED. The staged SuperTrack fix is not copied into this lane. If the closure itself needs it, report the exact blocker and use the already-staged dependency only on a separately recorded integration base.

### Standalone static contradiction table

All observations below are within the one exact selector above; empty-only checks are preservation, not counted as a second RED selector.

| Callable producer mutation | Contradiction in this selector |
|---|---|
| Constant empty table / fixed initial snapshot / outgoing-or-membership-only rows | Supplied invite-a for club-a must make original consumer true |
| Any constant nonempty valid invitation table | Initial supplied empty state must make consumer false |
| Nil / no return / no-op | Original ipairs requires the documented non-nil list; consumer cannot finish |
| Only first supplied row | After displaying club-a, adding unseen club-b must make consumer true |
| Club key replaced by invitationId | Displaying club-a must make invite-a seen (false) |
| Cached last nonempty list / no-op clear | Clearing after unseen club-c must make consumer false |
| Drops invitation/club/inviter/leaders fields | Original clubId access and explicit concrete required-field assertions fail |

These are source-level contradictions, not executed mutant results. Future proof must keep the endpoint callable and fail at the stated behavioral observation, not compilation/setup.

## Known gaps (current cycle)

- [ ] Run exact RED/GREEN and callable producer mutants after explicit slot admission; static staging provides no runtime acceptance.
- [ ] Reprove stock full-string/count map and prefork setup on the integrating parent's exact dependency stack.

## Out of scope

- All other CF-2 members, including Mists IsLFREnabled; no native-unknown default is chosen.
- Uninitialized-club failure behavior, opaque native token encoding, optional absent metadata, invitation acceptance/decline, service transport, events, persistence, security and other-profile consumer acceptance. Generated docs mark RequiresClubsInitialized but do not specify failure semantics; this lane does not invent them.
