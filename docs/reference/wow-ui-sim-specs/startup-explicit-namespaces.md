# Explicit startup namespace empty states

## Era / Anniversary startup extension

- [x] `C_LootHistory.GetNumItems()` returns zero pending a Classic roll-history
  model; original OnLoad and full-update handlers clear/recycle stale UI rows.
- [x] `C_ProductChoice.GetChoices()` returns a fresh empty identifier array pending
  a product-entitlement catalog; original OnLoad initializes the reward panel,
  and login/update handlers complete without creating reward alerts.
- [x] Replace the former engraving false default with [supplied availability](era-engraving-availability.md); the original rune control reflects the supplied value or reports a named unset error.
- [x] Unknown members remain nil on these three Era/Anniversary namespaces, even
  after exported-constructor reuse. Existing non-strict factories remain unchanged.

Only IsEngravingEnabled has a cached generated signature (non-nil bool).
GetNumItems and GetChoices are consumer-inferred number/array queries: Classic
caches omit their generated documentation. These policies are not client defaults.

`workarounds/temporary/classic_startup_defaults.rs` owns the empty loot/product
queries. Its former engraving block was relocated from `src/era/compat_bootstrap.lua`
on 2026-10-17, then removed by the [supplied availability implementation](era-engraving-availability.md).
The [shared contract and input supply](../wiki/investigations/mists-engraving-inputs.md#shared-availability-and-input-supply)
now govern engraving; no false default remains. Strict namespace policy remains
in the runtime bootstrap. The following receipts describe the historical default, not current engraving behavior. The fresh b6c603498 Era gate
passes all five unchanged namespace tests, including original rune-control hiding
and strict/factory preservation, plus the original empty-history startup test.
No fresh Anniversary or whole-profile acceptance is inferred. Retire each default when its named system is modeled under c_api. Retail's encounter/time API and active
loot-roll state are not Classic completed-roll/player history; C_PlayerChoice is
not C_ProductChoice. Mists's pre-existing empty loot/product defaults are not a
backing model. This extension changes no Mists/Forever/Wrath/ Retail/PTR surface.

`tests/classic_startup_namespaces.rs` loads complete hash-pinned cached consumers
using `blizzard_ui_addons_dir()`. Five tests cover the four original-handler cases
plus complete-bootstrap strictness/factory preservation. Tests-only Era RED at
fbf25a24d reproduced missing C_LootHistory at LootHistory.lua:55, C_ProductChoice
at ProductChoice.lua:63 (OnLoad and dispatched events), C_Engraving at
PaperDollFrame.lua:951, and the absent raw namespace preservation control.
Producer GREEN passed all five tests on both Era and Anniversary. Sealed headless
startups on this branch each measured 87 unique records / 138 occurrences versus
the supplied 26877f296 captures' 95/150: eight records disappeared, no new records,
and the existing ScriptErrors.lua:83 reporter count fell 50→46. Removed records
are LootHistory OnLoad :55, ProductChoice OnLoad and OnEvent :63, and rune-control
OnLoad PaperDollFrame :951, each with its Lua Error mirror and count one.
These are still failing startups, not full-profile acceptance. Build/runtime
receipts and exact-message deltas live in the private classic-ns-apply handoff.
Populated loot history, product selection, engraving modes/runes, reporter repair,
and full startup acceptance are outside this bounded extension.

### Explicit consumer exclusions

`Blizzard_UIPanels_Game/Classic/ContainerFrame_Shared.lua:54,95,315-316,1078,1088-1089,1111`
bag/rune events and bag-generation paths remain unsupported on Era/Anniversary:
`C_Engraving.GetEngravingModeEnabled`, `GetCurrentRuneCast`, and `RefreshRunesList`
remain nil. The first two are called without an availability guard;
`alwaysShowRuneIcons=1` can reach RefreshRunesList even with availability false.
Mists has a separate [supplied bag/settings model](mists-engraving-inputs.md).
Forced engraving UI and PaperDoll engraving interaction paths remain excluded;
Era/Anniversary's original rune-control OnLoad is covered by the availability spec.
`Blizzard_SettingsDefinitions_Frame/Classic/InterfaceOverrides.lua:136` uses
IsEngravingEnabled and skips its setting when supplied false; that is not bag/rune coverage.
See the [later Mists constructor proof](../wiki/investigations/mists-engraving-inputs.md#merged-settings-proof-and-stock-effects)
for the resolved display-settings blocker.

### Comparison boundaries

The pre-rebase receipts above and historical 92/98 baselines are not current
integration gates. Measured post-rebase comparisons against `9c0251fca` are in
[Proof level](#proof-level); they supersede earlier conditional arithmetic.

## Forever and classic extension

Share existing combat-text active-unit selection and spell-overlay membership with
Mists, Era, Anniversary and Forever, whose cached API docs declare those methods.
Keep Wrath namespace absence. Share the existing local PlayerChoice model with
Forever; share RecentAllies storage/query code with Forever without publishing it
to additional classic profiles. Forever's disabled GetRecentAllies returns an
empty array as declared, rather than the Retail disabled no-result policy.
Share the existing SearchRecentAllies producer with Forever without changing its
Retail epoch gate or adding a second search model. No RecentAllies service,
request completion, readiness or note/pin mutation behavior is added. Forever's
IsRecentAllyByGUID and IsRecentAllyByFullName query enabled supplied rows by exact
GUID/full-name identity; disabled input returns false, including retained rows.

Forever-only temporary defaults: no flyout artwork (GetFlyoutTexture returns no
values); no mentor membership (None), no newcomer status, restricted mentoring,
no required level, fresh empty achievement arrays plus zero optional count; no
RecentAllies game-type support or supported filter categories. Social UI reuses
the existing temporary disabled-service policy with Forever admitted explicitly.
Mists/Era/Anniversary/Forever GetCurrentEventInfo has no returns pending modeled
combat-text event routing. These defaults are simulator choices, not native facts.

Retire defaults when c_api models flyout artwork, mentorship membership/eligibility,
social-UI availability, recent-allies game-type support, or combat-text event
payload routing. Do not add missing request/mutation no-ops to fill out namespaces.

Ten original-consumer tests cover three shared Mists/Era/Anniversary/Forever
cases and seven Forever-only cases. Tests load complete hash-pinned cached chunks
from blizzard_ui_addons_dir and assert alert visibility under supplied membership,
deprecated alias state effects, vehicle unit transitions, hidden choice toggle,
empty supported-filter list, false mentor/social predicates, cleared unavailable
flyout texture, disabled/supplied RecentAllies list rows, and text/status-filtered
social-view trees. Only consumer-required dependencies are loaded.

Preserve the tip's generic namespace member factory, constructor, merger and final
C_* seed. Only newly published surfaces are strict: C_CombatText and
C_SpellActivationOverlay in Mists/Era/Anniversary/Forever, plus C_PlayerChoice,
C_RecentAllies, C_PlayerMentorship, C_SocialUI and C_Flyout in Forever, plus
C_LootHistory, C_ProductChoice and C_Engraving in Era/Anniversary. Keep the
exemption inventory in one bootstrap location. Their missing members return nil
through ordinary lookup without changing membership, including after reusing the
exported constructor. Other namespaces retain synthesized cached nil-returning
functions. A complete-bootstrap test covers only these strict surfaces; a separate
C_CVar/constructor control asserts unchanged non-strict behavior. Retail/PTR/Wrath
receive no strict exemptions. Generic member-factory retirement is out of scope.

Pre-rebase execution at producer `26877f296`: Forever passes all ten original
consumer cases and both factory controls (12/12); Mists, Era and Anniversary each
pass three original consumers and two controls (5/5). Their preceding REDs failed
at the missing named namespace in each original consumer, plus strictness; the
non-strict factory control passed. Post-rebase SocialUI preservation and startup
receipts are listed in [Proof level](#proof-level).

The Mists error-reporter gap predates this stage and has its own
[modeled logging repair](mists-script-error-logging.md). The selected-character
root is owned by the master StoreUI fix. No clean startup, full-profile or native
acceptance follows from these bounded component results.


## Contract

Replace reliance on removed generic C_* namespace synthesis with explicit,
profile-scoped members. No new arbitrary namespace/member fabrication or Blizzard
source changes; existing non-strict member factories retain the policy above. These temporary defaults describe simulator empty state, not
native behavior or defaults established by API documentation.

| Namespace | Empty behavior | Profiles with cached declaration |
|---|---|---|
| C_QuestSession | Start/stop unavailable; no session, join, pending command, begin details, or supertracked session quest; command None (0); proposed level 0 | Retail, PTR, Mists, Era, Anniversary, Forever |
| C_ClientScene | No active scene | IsSceneTypeActive: Retail, PTR, Forever; namespace-only declaration in Mists/Era/Anniversary |
| C_FrameManager | Managed feature frames hidden until event says otherwise; query refresh returns empty-policy false | Retail, PTR, Forever |
| C_LobbyMatchmakerInfo | Not queued; mainline queue disabled | IsInQueue: all except Wrath; GetQueueFromMainlineEnabled: Retail, PTR, Forever |
| C_CovenantCallings | Locked; request synchronously emits COVENANT_CALLINGS_UPDATED with a fresh empty BountyInfo array | Retail, PTR, Forever |

Namespace absence in Wrath must remain absence. Declaration alone does not
permit methods absent from that profile's documentation. Preserve raw existing
members; do not install metatable catchalls. Unsupported queue/session mutation
commands remain absent rather than accepting and discarding inputs. Queued-only
playlist/state/time queries remain outside this empty startup slice.

## Consumer-inferred public namespace

Cached BoostTutorial.lua:224 in Retail/PTR/Forever calls
`C_CharacterServicesPublic.ShouldSeeControlPopup()`. No cached profile's API
documentation declares the signature. User-approved temporary policy returns
false on those observed profiles; original BoostTutorial initialization leaves
its control popup hidden. This is consumer-inferred compatibility, not an
API-doc-declared signature or native default. Existing active boost fields are
not used to invent a popup rule. Retire this default when character boost/services
popup state is modeled.

## Retirement

Replace each temporary namespace with a c_api-backed producer when the quest
session coordinator, client-scene lifecycle, frame-manager visibility policy,
lobby matchmaking service, or covenant calling snapshots are modeled. Callings
requests must retain an observable completion effect, not become no-ops.

## Proof level

### Retail 70448 input checkpoint

Rebase onto `85ad9cae6` and the verified shared-cache resync change two of eleven
Retail consumer pins: `Blizzard_GroupFinder/Shared/LFGFrame.lua` and
`Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.lua`. Only their expected
hashes are refreshed to the approved 12.1.5.70448 cache; test bodies and production
behavior are unchanged. At `fd46b7a9a` all seven profiles passed fresh focused
gates and compile checks, including Retail 13/13 and startup []. This checkpoint
also reran the other profiles because incoming SetAtlas changes were shared.
Private `wrath-fixes-redgreen/FINAL-85ad9cae6.json` records exact receipts; the
older 9c checkpoint below is historical.

### Classic B integration checkpoint

Production `5ea0336fd` integrates comparison master `37b6c07b7`. B's guarded
Rust empty loot/product producers replace the redundant Lua defaults; engraving
and strict namespace inventory remain. Shared guild/marker constructor fields
are passive on the other five profiles. Profile-gated publication, string,
loader and fixture changes were inspected: their prior observable API behavior
is unchanged, so their accepted 85ad runtime receipts are reused, not relabeled
as fresh current-source execution.

| Profile | Focused tests | Master startup → branch | Runtime proof |
|---|---:|---|---|
| Retail | 13/13 | [] → [] | 85ad checkpoint reused |
| PTR | 7/7 | [] → [] | 85ad checkpoint reused |
| Mists | 6/6 | [] → [] | 85ad checkpoint reused |
| Forever | 12/12 | [] → [] | 85ad checkpoint reused |
| Era | 33/33 | 24/56 → 24/56 | 5ea0336fd; 32 + separate empty-history case |
| Anniversary | 33/33 | 24/56 → 24/56 | 5ea0336fd; combined batch |
| Wrath | 36/36 | 44/55 → 22/30 | 85ad checkpoint reused |

Era/Anniversary combined gates cover namespace/logging, Classic A/B and marker
behavior. Their startup records and counts exactly match current master, with
no new, removed or changed records. Equal counts are accepted: B already
subsumes the earlier empty-query removals. Both startups still exit 1.
Wrath's ten unmasked classes and 22/30 inventory remain unchanged; sound v2,
loot and U1–U4/residual work are deferred to a new branch after merge.
Private `wrath-fixes-redgreen/37b6-profile-projection.md` records source
projection and its limits. Independent verification remains parent-owned;
no clean-startup, native-parity or full-suite claim follows.

### Historical 9c checkpoint

Original complete cached Lua chunks are hash-pinned by the consumer tests.
Tests assert dialog/mode/frame visibility, LFD button label and role-warning
state, calling completion payload/count/throttle, supplied rows, and the original
public-popup consumer. Namespace factory controls check observable lookup behavior.

Post-rebase implementer checkpoint: comparison master `9c0251fca`, production
`b37d2a509` except the explicitly older Forever receipt. Counts are unique error
records / occurrences, not independent root causes.

| Profile | Focused tests | Master startup → branch | Runtime source |
|---|---:|---|---|
| Retail | 13/13 | [] → [] | b37d2a509 |
| PTR | 7/7 | [] → [] | b37d2a509 |
| Mists | 6/6 | [] → [] | b37d2a509 |
| Forever | 12/12 | [] → [] | 50b975eb7 |
| Era | 11/11 | 36/38 → 28/30 | b37d2a509 |
| Anniversary | 11/11 | 36/38 → 28/30 | b37d2a509 |
| Wrath | 36/36 | 44/55 → 22/30 | b37d2a509 |

Retail/PTR include the explicit SocialUI member-factory control. Era/Anniversary
remove exactly eight records with no new records or changed common counts after
[modeled logging](mists-script-error-logging.md). Wrath's ten unmasked classes
predate v4: its normalized inventory/counts exactly equal the retained
pre-namespace `6a8607899` capture. Remaining Wrath sound/loot/unmasked-root work
continues separately; Wrath/Era/Anniversary startups remain failing.

Forever was not rerun after the later Mists/Era/Anniversary-only logging
registration change. Its raw C_Log publication matched an independently sealed
exact-master `9c0251fca` probe (both absent, both clean startup), so no Forever
logging change was authorized. This is source-bounded evidence, not a fresh
all-profile current-HEAD claim. Parent-owned independent verification and merge
remain pending. No native parity or broad-suite acceptance is asserted.
