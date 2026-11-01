# Club unread notifications (CF-2)

The C_Club unread surface projects supplied streams within the existing `ClubState.clubs` model. [Model notes](../wiki/systems/club-membership.md#unread-streams-cf-2) describe ownership. This is edit-only staging, not executed RED/GREEN or native parity.

## What it must do

- [ ] Under the documented initialized-clubs precondition, return a non-nil boolean from `DoesAnyCommunityHaveUnreadMessages`, derived from current clubs/streams rather than a parallel flag/store.
- [ ] Project supplied stream descriptors through `GetStreams`, `GetStreamInfo`, and `IsSubscribedToStream`; preserve existing guild/officer descriptors and supplied stream state across legacy roster synchronization.
- [ ] Return only supplied `ClubStreamNotificationSetting` rows from `GetClubStreamNotificationSettings`; absent preference is not an invented All/None preference. Return the supplied numeric last-read time from `GetStreamViewMarker`, or nil when current.
- [ ] `AdvanceStreamViewMarker` makes a supplied unread stream current. Local modeled transition publishes the documented synchronous `STREAM_VIEW_MARKER_UPDATED(clubId, streamId, nil)` after changing state. Exact native event generation/idempotence policy remains UNKNOWN.
- [ ] Original selected MicroMenu and CommunitiesUtil consumers observe read/unread, club replacement/removal, multiple streams, filter changes, ignored club/stream IDs and marker clearing. Preserve PTR and Forever through separately selected original consumers and shared guild probes.

### Evidence and bounded interpretation

Cached generated `ClubDocumentation.lua`: DoesAnyCommunityHaveUnreadMessages :241–249 (bool); GetClubStreamNotificationSettings :468–482 (array); GetStreamViewMarker :745–759 (nil if current); AdvanceStreamViewMarker :35–45 (void); StreamViewMarkerUpdated :1540–1551 (synchronous, unique event with optional lastReadTime). StreamInfo :1949–1959 and notification filter :1718–1729 describe projections. Retail, PTR and Forever caches contain these four endpoints.

Original `Blizzard_FrameXMLUtil/CommunitiesUtil.lua` :185–242 supplies the per-community unread predicate: preference **All** AND non-nil marker. Aggregating that predicate across subscribed clubs is the staged, consumer-derived **INFERRED** interpretation of the native aggregate; native aggregate treatment of guilds, mentions, exclusions and transport state is **UNKNOWN**. No mention detection, notification preference defaults, timestamp generation or automatic message-arrival behavior is invented. New local clubs have no supplied streams. Initial guild descriptors retain the existing simulator data, without supplied preferences or unread markers.

## How it works

- [Existing club model and unread stream projection](../wiki/systems/club-membership.md#unread-streams-cf-2).
- [Consumer selection / RED proof policy](../wiki/investigations/consumer-selection-and-red-proof.md).

## Implementation inventory

- `src/c_api/club_model.rs`: data-only Stream snapshots owned by Club; legacy guild snapshot retention.
- `src/c_api/club_members.rs`: existing club creation and shared initialized club lookup.
- `src/c_api/club_unread.rs`: unread/settings/marker/advance Lua boundary and stream projection.
- `src/c_api/c_club.rs`: publication and shared stream queries; no second guild stream producer.
- `src/lua_api/workarounds/`: superseded empty notification-settings shim removed with producer.

## Tests asserting this spec

`tests/cf2_club_unread.rs` is discovered by the existing integration test harness. All three selectors are enabled for Retail, PTR and Forever; compilation is unverified. Schema/test commit `02ea638a0` precedes producer publication, so the original-consumer RED is not intended to depend on missing Rust types. No test was run during staging.

### Selection evidence (static only)

Retail MicroMenu `_Mainline.toc` permits mainline + Game, depends on Communities, and directly lists Mainline/MainMenuBarMicroButtons.lua/.xml. FrameXMLUtil generic TOC permits Game and directly lists CommunitiesUtil.lua; the file is not a [Game]/[Family] substitution or excluded entry. The tests use the original dependency-closure loader without overrides, assert the profile-selected TOC and loaded addons, verify original Lua source provenance, and call the XML-created GuildMicroButton. PTR has the same notification call (:1242). Forever selects its generic `Blizzard_MicroMenu.toc` (no Camelot-suffixed TOC exists in the inspected cache); its `[Family]` entries resolve to Mainline via the existing parser. Mainline UpdateNotificationIcon :1398 uses original SetHasNotification, which sets the same NotificationOverlay. The generic TOC also selects Camelot game overrides; actual original method provenance must still pass rather than assuming those overrides leave the method unchanged. Actual selection/provenance still must pass at execution time. Fixture/load failures are blockers, not producer RED.

MicroMenu :1240–1246 calls GetInvitationsForSelf then the single-line CommunitiesUtil aggregate wrapper (:186), then SetShown (Forever: SetHasNotification). There is **no further C_Club nil call downstream** on this direct path. Related helpers (:189–242) additionally reach existing GetSubscribedClubs/GetStreams, the empty-settings shim, missing GetStreamViewMarker and missing AdvanceStreamViewMarker. Only these documented siblings are staged; unrelated C_Club calls elsewhere are not widened into this lane.

### Current-master integration source binding (2026-10-24)

PTR master `08b423c5c` pins wowt 12.1.7.70493. Its supported private-cache sync contains 4,578 files and selects generic `Blizzard_MicroMenu.toc`, whose `[Family]` entries resolve to Mainline. `GuildMicroButtonMixin:UpdateNotificationIcon` at :1483–1489 calls the same CommunitiesUtil aggregate wrapper (:185–187); sibling settings/marker/clear helpers remain :205–242. The paired integrated RED/GREEN tests expect this generic PTR TOC and retain every behavior assertion and original Lua provenance check. The historical 12.1.5 `_Mainline.toc` evidence above is not current PTR runtime proof. Integrated runtime acceptance is recorded separately in the bounded handoff report.

### Standalone static contradiction table

Every row names the exact selector that alone rejects the callable mutant. These are static contradictions, not executed mutation proof.

| Selector | Callable constant/no-op mutation | Concrete contradiction |
|---|---|---|
| `original_micro_menu_tracks_club_unread_state` | aggregate constant true / truthy table | Initial current state must hide overlay |
| same | aggregate constant false / nil / no return / no-op | Supplied club-a stream11 All + marker101 must show overlay |
| same | fixed initial snapshot / cached last result / first club or first stream only | Read replacement hides; club-b second stream22 shows; club removal hides; replacement stream12 shows |
| same | ignores preference / treats missing or Mention as All | Unread marker with missing/None/Mention preference must hide |
| `original_community_unread_helpers_clear_supplied_markers` | settings constant empty / no-op | Original per-community helper must report club-a unread |
| same | settings fixed nonempty / always All / ignores supplied changes | Replacing preference through missing/None/Mention/All produces false/false/false/true; row counts change 1/2; ignored stream11 excludes muted stream12 |
| same | marker constant nil / no-op | Original stream12 helper must be true; exact 101/102 times required |
| same | marker constant non-nil / ignores club ID / cached snapshot | club-b stream11 is current, club-a stream11 unread; clear must make both club-a markers nil |
| same | advance no-op / clears wrong stream or club / clears all clubs | Two supplied markers must clear with post-state synchronous payloads; club-b remains independently writable; unrelated stream descriptors retained |
| same | GetStreams constant guild/empty / GetStreamInfo nil / subscription always true/false | Concrete community11/12 descriptors, positive and negative subscription, original ignored-stream path fail |

`guild_stream_projection_preserves_supplied_unread_across_roster_sync` is a shared-model preservation selector, not a standalone original-consumer RED claim. It protects existing two-stream guild descriptors and retention through GetClubInfo/GetSubscribedClubs synchronization.

## Known gaps (current cycle)

- [ ] Execute original-consumer RED on the schema/test commit and GREEN on the producer commit; verify callable mutants at each stated observation. No build or slot was used during staging.
- [ ] Capture exact full-string/count stock maps for Retail/PTR/Forever on an admitted integration stack. Retail expectation starts from the previous club invitation lane's measured GREEN map, not its baseline.

## Out of scope

- Native opaque-ID/BigUInteger encoding and numeric precision above Lua's exact integer range, malformed or unknown IDs, uninitialized failure semantics, secret/lockdown policy, native event deduplication/idempotence and native aggregate policy: **UNKNOWN** beyond cited docs/consumer evidence; no native-parity claim.
- Persistence, live service transport, message-time ordering, mention detection, preference mutation UI, auto-advance and additional C_Club methods: no documented behavior established by this bounded path.
