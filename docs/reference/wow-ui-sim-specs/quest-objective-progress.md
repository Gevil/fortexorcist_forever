# Supplied mutable quest objectives (QL-1)

Approved bounded per-environment objective progress for represented quests in Retail and
Forever. [Execution receipt](../baselines/quest-lifecycle.md) owns historical RED,
saved GREEN and the current integration gate; native/full-parent acceptance is separate.
Current backing model: `src/lua_api/sim_substates/quest_log.rs`; current projections:
`src/lua_api/globals/quest_surface/` and `globals/missing_surface/quest_log.rs`.
See [quest state architecture](../wiki/systems/lua-api.md#public-offer-rich-log-state-split).

## What it must do

- [x] Supply and replace ordered objective text/type/finished/counts for an existing
  rich active quest independently per environment, including IDs absent from the
  static catalog. Queries expose supplied values, not inferred gameplay progress.
- [x] `C_QuestLog.GetQuestObjectives(questID)` returns ordered records with `text`,
  `type`, `finished`, `numFulfilled`, `numRequired`; `GetNumQuestObjectives` and
  legacy leaderboard count/rows agree through the current rich log index, including
  after rich rows reorder. Preserve active membership and permanent history.
- [x] Supplied quest percentage is visible through `GetQuestProgressBarPercent`;
  original cached tracker writes 50 into its actual StatusBar and displays `50%`.
- [x] Commit all affected query projections before synchronous progress notification;
  callbacks can query them and invoke the unmodified original tracker without stale
  values or a held mutable state borrow. Existing tracker lines change text and enter
  the original finished-objective completion branch while another objective remains
  incomplete. An unchanged snapshot emits no duplicate notification (authored policy).
- [x] Changed objective snapshots notify `QUEST_LOG_UPDATE()` and
  `QUEST_WATCH_UPDATE(questID)`, not log index. Only represented changed criteria
  notify `QUEST_LOG_CRITERIA_UPDATE(questID, criteriaID, description, fulfilled,
  required)`; the supplied tree 71 advances 1/3 to 2/3 with five fields. Ordinary
  monster/item progress does not synthesize criteria IDs. No event-order relationship
  beyond committed-before-each-callback is prescribed here.

### Authored simulator boundary

`A_Admin.SetQuestObjectives(questID, rows, percentage?)` replaces the supplied
objective snapshot for an existing active rich quest. Row fields are the public
query fields above plus optional `criteriaID` for an explicitly represented tree.
Percentage is explicit quest-level 0–100 input for the progressbar fixture, not
inferred from objective counts. Repeating identical supplied state is inert.
This is a simulator-only producer, not a Blizzard API. Registration, snapshots and
notifications landed after both-profile behavioral RED. Tests tolerate absent
registration only when attempting input so baseline reaches real count/percentage
assertions, not a nil-call.

### Unsupplied cardinality preservation

Bootstrap world snapshots retain only declared counts when objective rows are unknown;
no rows are invented. Until supplied, count APIs/map records preserve each catalog's
nonzero declaration. First supplied snapshot clears declared cardinality and all
counts become the actual supplied row count. This is the explicit preservation rule,
not a runtime catalog fallback or evidence that unknown objective rows are modeled.
Ordinary seed texts/type/finished and authored numeric counts bootstrap into snapshots.

## How it works

- [Existing rich/light membership contract](quest-offer-rich-log-coherence.md)
- [Separate turn-in contract](quest-turn-in-model.md)
- [Lua API state architecture](../wiki/systems/lua-api.md)

## Implementation inventory

- `src/lua_api/sim_substates/quest_log.rs`: per-environment objective snapshot map and removal cleanup.
- `src/lua_api/globals/quest_surface/{data,legacy_globals,task_quest}.rs`: explicit
  bootstrap counts and shared objective text/rows/percentage/task projections.
- `src/lua_api/globals/missing_surface/quest_log.rs`: C objective/world/map counts read the same snapshot.
- `src/c_api/quest_objectives.rs` and `quest_objectives/queries.rs`: typed snapshots,
  bootstrap declared cardinality, shared counts and C/legacy projections.
- `src/lua_api/globals/admin_quest_objectives.rs`: atomic input/commit then notifications;
  `admin_quests.rs` publishes the simulator-only producer for Retail/Forever.

## Tests asserting this spec

`tests/quest_objective_progress.rs` and `tests/quest_objective_progress.lua`: six
shared Retail/Forever cases, with concrete custom quest 990001 and original tracker
closure loading through the existing addon harness. Tests inspect real FontStrings,
StatusBar and animation state; no fake block methods, query replacements, vendor
source slicing or synthetic events. Test-owned event receiver explicitly invokes
original `DoQuestObjectives`; full tracker automatic scheduling is not claimed.
Five producer-dependent cases reached behavioral RED in both profiles before the
producer; the bootstrap control passed. All six passed both latest-base matrices;
[receipt](../baselines/quest-lifecycle.md#latest-base-integration-proof--2026-10-17)
binds exact source revisions and distinguishes historical checkpoints.

## Known gaps (current cycle)

- [ ] Full tracker scheduling, map-handler integration and actual rendering remain
  unproven; the tracker body/real widget path is the bounded original-consumer test.

## Out of scope

QL-2 readiness/completion/history lifecycle, reward grants, failure/deadline modeling,
auto-complete popups, unconditional automatic watch membership, native validation or
native event-order parity, catalog acquisition, persistence, and other client profiles.
The fixture deliberately never finishes its last objective. Existing turn-in and
acceptance contracts are unchanged. Forever legacy QuestLogFrame loading is not
claimed; acceptance uses the shared original tracker instead.
