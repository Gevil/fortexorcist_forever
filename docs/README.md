# docs/ index

Start with the repository `README.md` (players) and `PLAN.md` (what, why, dated log). Everything here is
background for decisions, written for the people who work on the addon. Many notes are dated; the
date is the day they were written, not a promise that they are current.

## Release and verification

| File | What it is |
|---|---|
| [`release/CURSEFORGE-STEPS.md`](release/CURSEFORGE-STEPS.md) | Owner checklist for the CurseForge project, API token, GitHub secret, the toc id line, the tag, and a manual first upload. Includes the paste-ready summary and description. |
| [`release/curseforge-description.md`](release/curseforge-description.md) | A parallel draft of the CurseForge summary/description and the screenshot list. |
| [`launch-day.md`](launch-day.md) | Runbook for the first live session (status: launched 2026-11-04): the `/fx probe` protocol, feature checks F1-F27, how to read each probe line. |
| [`VERIFICATION.md`](VERIFICATION.md) | Ledger of the `/fx probe` rows: what each decides, simulator status, live-client status. |
| [`COMPATIBILITY-MATRIX.md`](COMPATIBILITY-MATRIX.md) | Client chat/addon-comms rules and how the code answers each one, with what is proven in the simulator and what is pending live. |

## Design and behaviour

| File | What it is |
|---|---|
| [`design-spell-timer.md`](design-spell-timer.md) | The Spell Timer (`Forte_Timer`): per-spell and per-target rows under Forever's restrictions. |
| [`design-combat-procs.md`](design-combat-procs.md) | In-combat item, trinket and proc display: design and the list of live probes. |
| [`engine-notes.md`](engine-notes.md) | Facts about the engine the code relies on, and where each came from. |
| [`why-not-blizzard-cdm.md`](why-not-blizzard-cdm.md) | Why the addon does not build on Blizzard's Cooldown Manager. |
| [`hunter-tools.md`](hunter-tools.md) | The Hunter tools: aspect tracker, swing bar, range light, melee rail; API evidence and live probes. |
| [`warlock-tools.md`](warlock-tools.md) | The Warlock tools: shards, soulstone, healthstone, summon; evidence, predicted vs read, probes, plates. |
| [`messages-sounds.md`](messages-sounds.md) | `Forte_Messages`: self messages, sounds, party/raid announcements, the event bus they listen on. |
| [`item-procs.md`](item-procs.md) | The generated item data: on-use items, consumables, weapon enchants, procs; counts and rules. |
| [`profiles.md`](profiles.md) | Profiles, the `ForteXorcistDB` schema and migrations, `/fx reset`. |
| [`localization.md`](localization.md) | How names are resolved on non-English clients; what is fixed and what is open. |
| [`class-port.md`](class-port.md) | Survey of the 2012 class modules against Forever: what is done, what needs only a spell-list entry, what is not possible. |
| [`perf.md`](perf.md) | Performance survey measured in the simulator, and the fixes it led to. |
| [`reference-functional-spec.md`](reference-functional-spec.md) | Functional spec of the original ForteXorcist v1.980.8 (the behavioural reference). |

## Research notes (`research/`)

| File | What it is |
|---|---|
| [`secrets-unknowns.md`](research/secrets-unknowns.md) | Ten launch-critical questions about secret values and restrictions, with the probe for each. |
| [`weaponswingtimer.md`](research/weaponswingtimer.md), [`wst-swing-design.md`](research/wst-swing-design.md) | WeaponSwingTimer SixxFix behaviour survey and the swing-bar design mapped from it. |
| [`options-fidelity.md`](research/options-fidelity.md) | The options pages compared with the original's option tree. |
| [`forever-dev-notes-2026-11-03.md`](research/forever-dev-notes-2026-11-03.md) | What matters to this addon in Blizzard's Forever beta development notes. |
| [`forever-locales.md`](research/forever-locales.md) | Forever's locales, and item/spell names at login. |
| [`forever-data-gaps.md`](research/forever-data-gaps.md) | Data-gap research (online and local). |
| [`forever-postlaunch-2026-11-07.md`](research/forever-postlaunch-2026-11-07.md) | Post-launch research: hotfixes, addon-API reports, builds 70790 / 70840 / 70862. |
| [`upstream-addons-2026-11-03.md`](research/upstream-addons-2026-11-03.md), [`upstream-api-2026-11-03.md`](research/upstream-api-2026-11-03.md), [`upstream-data-2026-11-03.md`](research/upstream-data-2026-11-03.md), [`upstream-sim-2026-11-03.md`](research/upstream-sim-2026-11-03.md) | What changed in installed addons, the Forever API, the data repositories and the simulator as of 2026-11-03. |
| [`data-diff-70707.md`](research/data-diff-70707.md), [`data-diff-live-2026-11-07.md`](research/data-diff-live-2026-11-07.md) | Data diffs: the pinned 70425 data against live builds 70707, and then 70790 / 70862. |
| `live-<class>-2026-11-09.md` (`druid`, `hunter`, `mage`, `paladin`, `priest`, `rogue`, `shaman`, `warlock`, `warrior`) | Per-class check of the generated data and tracked names against the live game, with proposed spell-list changes. |
| [`live-items-procs-2026-11-09.md`](research/live-items-procs-2026-11-09.md) | The same check for items, consumables and procs. |
| [`curseforge-forever-publishing-2026-11-09.md`](research/curseforge-forever-publishing-2026-11-09.md) | How to publish to CurseForge, Wago and GitHub for Forever; the tested packager setup. |

## Code reviews

| Where | What it is |
|---|---|
| [`review/`](review/) | Code reviews 1-6 (2026-11-01 to 2026-11-03). |
| [`reviews/`](reviews/) | Code reviews 7-10 (Iteration I through the first live session). |

## References and media

| Where | What it is |
|---|---|
| [`api/`](api/README.md) | The pinned Forever API catalog (JBurlison/WoWAddonAPIAgents skills) and which local layer outranks which. |
| [`reference/`](reference/) | `owner-research-secrets-2026-11-01.md`, notes on other addons that detect procs (`addons/`), and the vendored wow-ui-sim behavioural specs (`wow-ui-sim-specs/`, one file per behaviour). |
| [`demo/`](demo/) | The screenshots, GIFs and MP4s used by the README. |
| `media/`, `refs/` | Local reference screenshots and videos (git-ignored; third-party material and simulator captures). `media/README.md` describes them. |
