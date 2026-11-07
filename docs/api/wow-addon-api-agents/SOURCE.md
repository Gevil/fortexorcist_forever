# Vendored reference layer: JBurlison/WoWAddonAPIAgents

**Answer first:** this is the Forever-targeted reference layer of an MIT-licensed,
version-aware WoW addon agent suite, vendored as ForteXorcist's API ground-truth layer #1
(see `docs/api/README.md`). It is a **pinned source-declaration snapshot of the Blizzard UI
source for WoW Forever 1.60.1.70790 (interface 16001)** - signatures, event payloads and
security annotations - plus the curated contract guides and the evidence discipline that goes
with them. It is **not** runtime-verified addon availability: every guide repeats that
source-declared, loaded, permitted and runtime-tested are four separate evidence states.

## Provenance

| Field | Value |
|---|---|
| Upstream repository | https://github.com/JBurlison/WoWAddonAPIAgents |
| License | MIT (text vendored at `LICENSE.md`, upstream filename `LICENSE`) |
| Clone commit (this copy) | `1957c44fa7e25adfcae4e3c9aade2b21c3576b6a` |
| Upstream commit date | 2026-11-05T11:23:52Z |
| Package version | 2.4.1 (`package.json`) |
| Vendored | 2026-11-07 by the manager (Iteration M4): the 78 files upstream changed inside the existing vendored scope copied byte-for-byte from the pinned tarball; no file removed upstream; the 13 new upstream files are in the omitted categories below. Previous copy: `20585807…` (2026-11-03, agent `I2eDocs`) |
| Data pinned by the catalogs | `Gethe/wow-ui-source` @ `eac30af597e5aaa43a60f6675ef5fdcea100375f`, version `1.60.1.70790` (the launch build), interface `16001`, verified 2026-11-07. Known later delta to 70862 (`9dc84f0d3b`, 2026-11-07), read from the Gethe compare: additive (`C_ActionBar.IsHighestSpellRank`, `BattleNet.GetDefaultTitleWhisperTarget`, `subIcon` fields, enum `SubscriptionInterstitialType.SubscriptionPeriod`) plus `UNIT_COMBAT.amount` now `SecretValue` (ForteXorcist does not use UNIT_COMBAT) and `RolesetSystem.ApplyRolesetFilters` HasRestrictions |

ForteXorcist's own client facts: interface **16001**, installed build **1.60.1.70707**
(`.build.info`), `WOW_PROJECT_CAMELOT`. The catalogs are now pinned to that **same 70707**
UI build, so the old "two builds behind the client" caveat is retired; the installed
`wow-ui-sim` v0.1.39 binary still pins **70532** (the 70707 profile ships with the next
release), so the sim layer keeps `--allow-ui-version-mismatch` (see `docs/api/README.md`).
Declaration-identity over our used symbol set at both pins was verified by
`docs/research/upstream-api-2026-11-03.md` §1; `scripts/api_lint.py` passes on the new
catalogs unchanged (4376 → 4378 declared `C_*` symbols, 1814 → 1816 events).

## Scope: what was taken and what was not

Taken: all 39 skill directories (portable markdown), the client-aware instruction file, the
shared agent definition, the curated per-target contract guides, the generated **Forever**
declaration catalogs + snapshot manifests, the Forever-relevant audit reports, and - new in
the 2026-11-03 re-vendor - `skills/wow-client-targets/references/FOREVER-70707-CHANGES.md`, the
vendor's own migration guide for the 70532 → 70707 range. File set = the previous copy's 233
files, byte-for-byte from the new commit where upstream changed them (86 files), plus that one
addition (234 files).

Deliberately **not** copied:

| Omitted | Why |
|---|---|
| `plugins/`, `.github/agents`, `.github/instructions`, `.github/plugin`, `.github/prompts`, `.github/workflows`, `.agents/`, `.claude-plugin/`, `.vscode/`, `config/` | Codex / Claude Code / GitHub Copilot plugin packaging. We are omp, not those hosts. |
| `skills/*/references/generated/retail.json`, `.../classic.json` (18.6 MB) | Not the Forever flavor; kept the tree under budget. `docs/audit/api-coverage.json` still carries all three targets' record sets. |
| `skills/wow-api-index/scripts/query.mjs`, `skills/wow-client-targets/scripts/targets.mjs`, `scripts/`, `test/` | Node tooling; the acceptance for this tree is markdown/JSON only. Their documented usage is reproduced below. |
| `agents/ai-builder.md`, `skills/agent-file-specs`-adjacent maintainer flows, `docs/RELEASING.md`, `docs/AUTOMATION.md` | Upstream repo maintenance, not addon engineering. |
| `skills/wow-addon-development/references/PROJECT-PLANNING.md` + its two templates, `docs/RELEASE-2.3.0.md` | New in 2.3.0: the upstream planning workflow (the "requirements document + implementation matrix" flow PLAN.md already runs our own way) and the release note. The release note's Forever row is the provenance fact quoted above. |
| `.git/` | No upstream git metadata; the commit sha is recorded above. |

Known side effect: relative links inside the vendored markdown point at the omitted
`query.mjs` / `retail.json` / `classic.json` / `PROJECT-PLANNING.md` files (109 links; 107 in
the 2026-11-01 copy). They are intentional, and the query recipe below replaces the script.

## How to use the catalogs (the script is not vendored)

Each `skills/<skill>/references/generated/forever.json` is one JSON object per line:

```json
{"id":"event:UNIT_SPELLCAST_SUCCEEDED@UnitDocumentation.lua","kind":"event",
 "symbol":"UNIT_SPELLCAST_SUCCEEDED","group":"Global:Unit","environment":"All",
 "source":{"file":"UnitDocumentation.lua","line":4844},
 "declaration":{ ... full Arguments/Returns/Payload with Type, Nilable, defaults,
                  SecretWhen... / NeverSecret / SecretArguments annotations ... },
 "owner":"wow-api-unit-player","classification":"client-system",
 "evidence":{"declaration":"source-declared","loadConditions":"unknown",
             "runtime":"unknown","addonAccess":"unknown"}}
```

Lookup recipe (pure shell, no Node):

```sh
cd docs/api/wow-addon-api-agents/skills
grep -l '"symbol":"C_Spell.GetSpellInfo"' */references/generated/forever.json   # which domain
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); \
  [print(json.dumps(r['declaration'])) for r in d['declarations'] if r['symbol']==sys.argv[2]]" \
  wow-api-spells-abilities/references/generated/forever.json C_Spell.GetSpellInfo
```

Upstream's own rule, from `skills/wow-api-index/references/CURRENT-REFERENCES.md`: *"Search by
exact quoted `symbol`, then inspect `declaration` and any named argument/return structures.
Do not read every large file for a narrow addon task."*

## Evidence vocabulary (upstream, verbatim)

`skills/wow-api-index/references/CURRENT-REFERENCES.md`:

> - `evidence.declaration` is `source-declared`; `loadConditions`, `runtime` and `addonAccess` are `unknown`. A curated guide may add separately cited evidence, but must not silently upgrade this inventory into tested compatibility.
> - `classification` distinguishes client systems, front-end/Glue, mixed context, internal/restricted, platform-specific and SecureOnly definitions. `Environment = All` is not an addon permission flag. `CallbackEvent = true` is not a frame-event subscription.
> - A source miss is unknown, not proof of removal.

`skills/wow-api-index/references/generated/README.md` (per-domain header):

> These are complete extracted source schemas for this domain at the pinned commits. They establish declarations, not addon-facing availability. Load conditions, runtime behavior and addon access are explicitly unknown.

## File index (234 vendored files + this index)

| Path | Covers |
|---|---|
| `LICENSE.md` | LICENSE |
| `agents/wow-addon.md` | WoW addon development |
| `docs/BEHAVIOR-SCENARIOS.md` | Behavioral acceptance |
| `docs/RELEASE-2.0.0.md` | Marketplace 2.0.0 implementation and validation |
| `docs/VALIDATION.md` | Validation record |
| `docs/audit/API-COVERAGE.md` | Generated API coverage audit |
| `docs/audit/FOREVER-FINDINGS.md` | WoW Forever evidence and documentation gaps |
| `docs/audit/FOREVER-SYMBOL-GAPS.md` | Forever generated symbols needing documentation review |
| `docs/audit/GAP-MATRIX.md` | Marketplace API documentation gap matrix |
| `docs/audit/SKILL-QUALITY-FINDINGS.md` | Local skill quality audit — 2026-10-31 |
| `docs/audit/SOURCES.md` | Audit evidence and scope — 2026-10-31 |
| `docs/audit/api-coverage.json` | Machine-readable coverage audit: per-target commit/version plus all 8,431 Forever records as [kind, symbol, group, sourceSystem, environment, sourceFile, line, mentioned, ...] with arguments, returns and scalar security annotat... |
| `docs/audit/forever-runtime-comparison.json` | Set reconciliation of the 69893 runtime capture (forever-addon-kit) against 70532 generated declarations: namespace/function additions, removals and common sets, with explicit unknown-status caveats. |
| `instructions/wow-api.instructions.md` | WoW target selection |
| `references/FRAMEXML-FUNCTIONS.md` | FrameXML Functions Reference |
| `skills/agent-file-specs/SKILL.md` | Contains the complete specifications for AI coding assistant customization files including agents, skills, prompts, and instructions. Works with GitHub Copilot, Claude Code, Codex, OpenCode, and other providers. Use this skill ... |
| `skills/agent-file-specs/references/AGENTS.md` | Custom Agent Files (`.agent.md`) |
| `skills/agent-file-specs/references/FILE-LOCATIONS.md` | Source and installed file locations |
| `skills/agent-file-specs/references/INSTRUCTIONS.md` | Instruction Files (`.instructions.md`) |
| `skills/agent-file-specs/references/PROMPTS.md` | Prompt Files (`.prompt.md`) |
| `skills/agent-file-specs/references/SETTINGS.md` | VS Code Settings Reference |
| `skills/agent-file-specs/references/SKILLS.md` | Agent Skill Files (`SKILL.md`) |
| `skills/analyze-agent-overlap/SKILL.md` | Analyzes existing agents, skills, prompts, and instructions to identify overlaps, redundancies, and conflicts. Works with GitHub Copilot, Claude Code, Codex, OpenCode, and other providers. Use before creating new customization ... |
| `skills/generate-agent-docs/SKILL.md` | Generates documentation and usage guides for agents, skills, prompts, and instructions. Works with GitHub Copilot, Claude Code, Codex, OpenCode, and other providers. Use when onboarding team members, creating README files for y... |
| `skills/validate-agent-files/SKILL.md` | Validates AI coding assistant customization files (agents, skills, prompts, instructions) for correct format and structure. Works with GitHub Copilot, Claude Code, Codex, OpenCode, and other providers. Use when checking if agen... |
| `skills/wow-addon-development/SKILL.md` | Design, build, debug, port, and package World of Warcraft addons for Retail, Forever, Classic progression, or any combination of these clients. Use for addon architecture, UI mock-ups and visual fidelity, UIForever testing, opt... |
| `skills/wow-addon-development/references/CLIENT-VALIDATION.md` | Per-client acceptance |
| `skills/wow-addon-development/references/CONNECTED-CLIENT-TESTING.md` | Connected game-client UI testing |
| `skills/wow-addon-development/references/MULTI-VERSION-ADDONS.md` | Shared source, separate client artifacts |
| `skills/wow-addon-development/references/RUNTIME-VALIDATION.md` | Runtime capture and capability validation |
| `skills/wow-addon-development/references/UI-DESIGN-AND-TESTING.md` | UI mock-ups and UIForever testing |
| `skills/wow-addon-development/references/VISUAL-FIDELITY.md` | Implement the accepted UI, then compare the render |
| `skills/wow-addon-structure/SKILL.md` | Verbose guide for WoW AddOn structure, .toc metadata, loading |
| `skills/wow-addon-structure/references/ADDON_STRUCTURE.md` | Historical Retail reference (labelled). AddOn Folder Structure and Naming |
| `skills/wow-addon-structure/references/C_ADDONS_API.md` | Historical Retail reference (labelled). C_AddOns API (Retail) |
| `skills/wow-addon-structure/references/LOADING_LIFECYCLE.md` | Historical Retail reference (labelled). AddOn Loading Lifecycle (Retail) |
| `skills/wow-addon-structure/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). WoW AddOn Structure (Retail) |
| `skills/wow-addon-structure/references/SAVED_VARIABLES.md` | Historical Retail reference (labelled). SavedVariables (Retail) |
| `skills/wow-addon-structure/references/TOC_FORMAT.md` | Historical Retail reference (labelled). TOC Format (Retail) |
| `skills/wow-addon-structure/references/VIEWING_BLIZZARD_UI.md` | Historical Retail reference (labelled). Viewing Blizzard UI Source (Retail) |
| `skills/wow-addon-structure/references/generated/README.md` | wow-addon-structure: generated declaration ledger |
| `skills/wow-addon-structure/references/generated/forever.json` | FOREVER declaration ledger: 53 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-achievements/SKILL.md` | Look up WoW Achievement, Statistics, and Achievement Criteria APIs. |
| `skills/wow-api-achievements/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Achievements API (Retail — Patch 12.0.0) |
| `skills/wow-api-achievements/references/generated/README.md` | wow-api-achievements: generated declaration ledger |
| `skills/wow-api-achievements/references/generated/forever.json` | FOREVER declaration ledger: 20 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-calendar-events/SKILL.md` | Look up WoW Calendar and Event Scheduler APIs. Covers C_Calendar |
| `skills/wow-api-calendar-events/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Calendar & Events API (Retail — Patch 12.0.0) |
| `skills/wow-api-calendar-events/references/generated/README.md` | wow-api-calendar-events: generated declaration ledger |
| `skills/wow-api-calendar-events/references/generated/forever.json` | FOREVER declaration ledger: 150 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-collections/SKILL.md` | Look up WoW Mount, Pet, Pet Battle, Toy, Stable, and Heirloom |
| `skills/wow-api-collections/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Collections API (Retail — Patch 12.0.0) |
| `skills/wow-api-collections/references/generated/README.md` | wow-api-collections: generated declaration ledger |
| `skills/wow-api-collections/references/generated/forever.json` | FOREVER declaration ledger: 220 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-combat/SKILL.md` | Look up WoW Combat, Damage Meter, Threat, Loss of Control, Combat |
| `skills/wow-api-combat/references/CURRENT-CONTRACTS.md` | Combat contracts reviewed 2026-10-31 |
| `skills/wow-api-combat/references/RETAIL-12-0-CHANGES.md` | Patch 12.0.0 (Midnight) — Critical API Changes |
| `skills/wow-api-combat/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Combat API (Retail — Patch 12.0.0) |
| `skills/wow-api-combat/references/generated/README.md` | wow-api-combat: generated declaration ledger |
| `skills/wow-api-combat/references/generated/forever.json` | FOREVER declaration ledger: 322 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-currency-economy/SKILL.md` | Look up WoW Currency, Auction House, Token, Store, Trading Post, |
| `skills/wow-api-currency-economy/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Currency & Economy API (Retail — Patch 12.0.0) |
| `skills/wow-api-currency-economy/references/generated/README.md` | wow-api-currency-economy: generated declaration ledger |
| `skills/wow-api-currency-economy/references/generated/forever.json` | FOREVER declaration ledger: 452 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-encounters/SKILL.md` | Look up WoW Encounter Journal, Mythic+/Challenge Mode, Instance, |
| `skills/wow-api-encounters/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Encounters API (Retail — Patch 12.0.0) |
| `skills/wow-api-encounters/references/generated/README.md` | wow-api-encounters: generated declaration ledger |
| `skills/wow-api-encounters/references/generated/forever.json` | FOREVER declaration ledger: 350 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-escape-sequences/SKILL.md` | Look up World of Warcraft UI escape sequences — pipe-character |
| `skills/wow-api-escape-sequences/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). WoW UI Escape Sequences |
| `skills/wow-api-events/SKILL.md` | Look up complete source-pinned WoW event declarations, ordered typed payloads, nilability, secrecy and callback-versus-frame dispatch across Retail, Forever and Classic progression. Verify addon-facing registration and runtime ... |
| `skills/wow-api-events/references/EVENTS-A-F.md` | Current event catalogue: A-F |
| `skills/wow-api-events/references/EVENTS-G-L.md` | Current event catalogue: G-L |
| `skills/wow-api-events/references/EVENTS-M-R.md` | Current event catalogue: M-R |
| `skills/wow-api-events/references/EVENTS-S-Z.md` | Current event catalogue: S-Z |
| `skills/wow-api-events/references/EVENTS-UNDOCUMENTED.md` | Non-generated events and internal callbacks |
| `skills/wow-api-events/references/RETAIL-BASELINE.md` | Current event contracts and registration |
| `skills/wow-api-events/references/generated/README.md` | wow-api-events: generated declaration ledger |
| `skills/wow-api-events/references/generated/forever.json` | FOREVER declaration ledger: 2 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-framexml/SKILL.md` | Look up World of Warcraft FrameXML functions — global Lua |
| `skills/wow-api-framexml/references/CHATFRAME-CONTAINERS.md` | Historical Retail reference (labelled). ChatFrame, Containers & Dressing Room |
| `skills/wow-api-framexml/references/CURRENT-UI-SOURCES.md` | Loaded UI helpers, callbacks and secure templates |
| `skills/wow-api-framexml/references/FRAMEXML-GAME-UTILS.md` | Historical Retail reference (labelled). FrameXML — Game Utility Modules |
| `skills/wow-api-framexml/references/MIXINS-AND-POOLS.md` | Historical Retail reference (labelled). Mixins & Object Pools |
| `skills/wow-api-framexml/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). FrameXML Functions API |
| `skills/wow-api-framexml/references/SHAREDXML-DATA-UTILS.md` | Historical Retail reference (labelled). SharedXML — Data & Logic Utilities |
| `skills/wow-api-framexml/references/SHAREDXML-UI-UTILS.md` | Historical Retail reference (labelled). SharedXML — UI & Frame Utilities |
| `skills/wow-api-framexml/references/UIPARENT.md` | Historical Retail reference (labelled). UIParent Functions |
| `skills/wow-api-group-lfg/SKILL.md` | Look up WoW Party, Raid, Dungeon Finder, Premade Groups (LFG List), |
| `skills/wow-api-group-lfg/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Group & LFG API (Retail — Patch 12.0.0) |
| `skills/wow-api-group-lfg/references/generated/README.md` | wow-api-group-lfg: generated declaration ledger |
| `skills/wow-api-group-lfg/references/generated/forever.json` | FOREVER declaration ledger: 324 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-guild/SKILL.md` | Look up WoW Guild Management, Guild Bank, Guild Info, and Guild |
| `skills/wow-api-guild/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Guild API (Retail — Patch 12.0.0) |
| `skills/wow-api-guild/references/generated/README.md` | wow-api-guild: generated declaration ledger |
| `skills/wow-api-guild/references/generated/forever.json` | FOREVER declaration ledger: 87 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-housing/SKILL.md` | Look up WoW Player Housing APIs (new in Patch 12.0.0). Covers |
| `skills/wow-api-housing/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Housing API (Retail — Patch 12.0.0) |
| `skills/wow-api-housing/references/generated/README.md` | wow-api-housing: generated declaration ledger |
| `skills/wow-api-housing/references/generated/forever.json` | FOREVER declaration ledger: 701 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-index/SKILL.md` | Find source-pinned WoW functions, events, object methods, structures, enums and domain guidance across Retail, Forever and Classic progression. Use the packaged narrow-query tool and complete ownership routing before implementa... |
| `skills/wow-api-index/references/CATEGORY-LOOKUP.md` | Category → skill lookup |
| `skills/wow-api-index/references/CURRENT-REFERENCES.md` | Current source schemas and narrow lookup |
| `skills/wow-api-index/references/DOMAIN-SKILLS.md` | Domain routing and evidence status |
| `skills/wow-api-index/references/MAINTENANCE.md` | Maintaining the source ledger and routing |
| `skills/wow-api-index/references/NAMESPACE-LOOKUP.md` | Namespace → skill lookup |
| `skills/wow-api-index/references/generated/manifest.json` | Catalog manifest: pins all three target snapshots (Forever forever/aff0d8cd5/1.60.1.70707, 10255 records; retail and classic unchanged at their pins), per-file counts and hashes. |
| `skills/wow-api-index/references/generated/symbols.json` | Global symbol -> owner-skill routing index for all three targets. |
| `skills/wow-api-items-inventory/SKILL.md` | Look up WoW Item, Container (Bag), Bank, Loot, Equipment, Socket, |
| `skills/wow-api-items-inventory/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Item & Inventory API (Retail — Patch 12.0.0) |
| `skills/wow-api-items-inventory/references/generated/README.md` | wow-api-items-inventory: generated declaration ledger |
| `skills/wow-api-items-inventory/references/generated/forever.json` | FOREVER declaration ledger: 688 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-lua-environment/SKILL.md` | Look up the WoW Lua 5.1 runtime environment, restrictions, secure |
| `skills/wow-api-lua-environment/references/CURRENT-CONTRACTS.md` | Taint and restricted-value contracts reviewed 2026-10-31 |
| `skills/wow-api-lua-environment/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Lua Environment & Security (Retail — Patch 12.0.0) |
| `skills/wow-api-lua-environment/references/generated/README.md` | wow-api-lua-environment: generated declaration ledger |
| `skills/wow-api-lua-environment/references/generated/forever.json` | FOREVER declaration ledger: 90 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-map-navigation/SKILL.md` | Look up WoW Map, Navigation, Area POI, Taxi, Vignette, Minimap, |
| `skills/wow-api-map-navigation/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Map & Navigation API (Retail — Patch 12.0.0) |
| `skills/wow-api-map-navigation/references/generated/README.md` | wow-api-map-navigation: generated declaration ledger |
| `skills/wow-api-map-navigation/references/generated/forever.json` | FOREVER declaration ledger: 260 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-misc-systems/SKILL.md` | Catch-all reference for smaller WoW API systems that don't warrant |
| `skills/wow-api-misc-systems/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Miscellaneous Systems API (Retail — Patch 12.0.0) |
| `skills/wow-api-misc-systems/references/generated/README.md` | wow-api-misc-systems: generated declaration ledger |
| `skills/wow-api-misc-systems/references/generated/forever.json` | FOREVER declaration ledger: 643 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-professions/SKILL.md` | Look up WoW Professions, Tradeskill, Crafting Orders, Recipe, and |
| `skills/wow-api-professions/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Professions API (Retail — Patch 12.0.0) |
| `skills/wow-api-professions/references/generated/README.md` | wow-api-professions: generated declaration ledger |
| `skills/wow-api-professions/references/generated/forever.json` | FOREVER declaration ledger: 328 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-pvp/SKILL.md` | Look up WoW PvP, Battlegrounds, Arenas, Rated PvP, War Mode, Duels, |
| `skills/wow-api-pvp/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). PvP API (Retail — Patch 12.0.0) |
| `skills/wow-api-pvp/references/generated/README.md` | wow-api-pvp: generated declaration ledger |
| `skills/wow-api-pvp/references/generated/forever.json` | FOREVER declaration ledger: 200 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-quests/SKILL.md` | Look up WoW Quest, Quest Log, Quest Info, Quest Offer, Quest |
| `skills/wow-api-quests/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Quest API (Retail — Patch 12.0.0) |
| `skills/wow-api-quests/references/generated/README.md` | wow-api-quests: generated declaration ledger |
| `skills/wow-api-quests/references/generated/forever.json` | FOREVER declaration ledger: 325 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-reputation/SKILL.md` | Look up WoW Reputation, Faction, Major Factions, Paragon, and |
| `skills/wow-api-reputation/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Reputation API (Retail — Patch 12.0.0) |
| `skills/wow-api-reputation/references/generated/README.md` | wow-api-reputation: generated declaration ledger |
| `skills/wow-api-reputation/references/generated/forever.json` | FOREVER declaration ledger: 84 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-settings-system/SKILL.md` | Look up WoW Settings registration, CVars, input/keybindings, |
| `skills/wow-api-settings-system/references/CURRENT-SETTINGS.md` | Settings registration, CVars, input and media |
| `skills/wow-api-settings-system/references/CVARS-OVERVIEW.md` | Historical Retail reference (labelled). CVar Overview Notes |
| `skills/wow-api-settings-system/references/FOREVER-GAME-RULES.md` | Forever game rules and experience presets |
| `skills/wow-api-settings-system/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). WoW Settings System (CVars and Console) |
| `skills/wow-api-settings-system/references/generated/README.md` | wow-api-settings-system: generated declaration ledger |
| `skills/wow-api-settings-system/references/generated/forever.json` | FOREVER declaration ledger: 384 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-social-chat/SKILL.md` | Look up WoW Chat, Social, Club/Community, Friend List, Voice Chat, |
| `skills/wow-api-social-chat/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Social & Chat API (Retail — Patch 12.0.0) |
| `skills/wow-api-social-chat/references/generated/README.md` | wow-api-social-chat: generated declaration ledger |
| `skills/wow-api-social-chat/references/generated/forever.json` | FOREVER declaration ledger: 833 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-spells-abilities/SKILL.md` | Look up WoW Spell, SpellBook, ActionBar, Cooldown, Totem, and |
| `skills/wow-api-spells-abilities/references/ACTIONBAR.md` | Historical Retail reference (labelled). C_ActionBar — Action Bar & Button Reference |
| `skills/wow-api-spells-abilities/references/COOLDOWNS-CASTING.md` | Historical Retail reference (labelled). Cooldowns, Casting & Auxiliary Spell Systems Reference |
| `skills/wow-api-spells-abilities/references/CURRENT-CONTRACTS.md` | Cooldown contracts reviewed 2026-10-31 |
| `skills/wow-api-spells-abilities/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Spell & Ability API (Retail — Patch 12.0.0) |
| `skills/wow-api-spells-abilities/references/SPELLBOOK.md` | Historical Retail reference (labelled). C_SpellBook — Spellbook Navigation Reference |
| `skills/wow-api-spells-abilities/references/SPELLS-CORE.md` | Historical Retail reference (labelled). C_Spell — Core Spell API Reference |
| `skills/wow-api-spells-abilities/references/TOTEM-SHAPESHIFT.md` | Historical Retail reference (labelled). Totems, Shapeshifting, Flyouts & Pet Actions Reference |
| `skills/wow-api-spells-abilities/references/generated/README.md` | wow-api-spells-abilities: generated declaration ledger |
| `skills/wow-api-spells-abilities/references/generated/forever.json` | FOREVER declaration ledger: 363 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-talents/SKILL.md` | Look up WoW Class Talents, Hero Talents, Traits system, |
| `skills/wow-api-talents/references/FOREVER-LEGACY.md` | Forever Legacy integration |
| `skills/wow-api-talents/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Talents & Specialization API (Retail — Patch 12.0.0) |
| `skills/wow-api-talents/references/generated/README.md` | wow-api-talents: generated declaration ledger |
| `skills/wow-api-talents/references/generated/forever.json` | FOREVER declaration ledger: 278 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-transmog/SKILL.md` | Look up WoW Transmogrification, Appearance Collection, Transmog |
| `skills/wow-api-transmog/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Transmog API (Retail — Patch 12.0.0) |
| `skills/wow-api-transmog/references/generated/README.md` | wow-api-transmog: generated declaration ledger |
| `skills/wow-api-transmog/references/generated/forever.json` | FOREVER declaration ledger: 336 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-unit-player/SKILL.md` | Look up WoW Unit and Player APIs — UnitId tokens, GUIDs, |
| `skills/wow-api-unit-player/references/PLAYER-FUNCTIONS.md` | Historical Retail reference (labelled). Player-Specific Functions Reference |
| `skills/wow-api-unit-player/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Unit & Player API (Retail — Patch 12.0.0) |
| `skills/wow-api-unit-player/references/UNIT-AURAS.md` | Historical Retail reference (labelled). Unit Auras Reference |
| `skills/wow-api-unit-player/references/UNIT-HEALTH-POWER.md` | Historical Retail reference (labelled). Unit Health, Power & Stats Reference |
| `skills/wow-api-unit-player/references/UNIT-IDENTITY.md` | Historical Retail reference (labelled). Unit Identity Reference |
| `skills/wow-api-unit-player/references/UNIT-STATE.md` | Historical Retail reference (labelled). Unit State Reference |
| `skills/wow-api-unit-player/references/UNIT-THREAT-COMBAT.md` | Historical Retail reference (labelled). Unit Threat & Combat Reference |
| `skills/wow-api-unit-player/references/generated/README.md` | wow-api-unit-player: generated declaration ledger |
| `skills/wow-api-unit-player/references/generated/forever.json` | FOREVER declaration ledger: 886 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-weekly-rewards/SKILL.md` | Look up WoW Weekly Rewards (Great Vault) API. Covers |
| `skills/wow-api-weekly-rewards/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). Weekly Rewards API (Retail — Patch 12.0.0) |
| `skills/wow-api-weekly-rewards/references/generated/README.md` | wow-api-weekly-rewards: generated declaration ledger |
| `skills/wow-api-weekly-rewards/references/generated/forever.json` | FOREVER declaration ledger: 29 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-widget/SKILL.md` | Curated guide to the WoW Widget API (Retail). Focuses on core |
| `skills/wow-api-widget/references/ADVANCED-WIDGETS.md` | Historical Retail reference (labelled). Advanced Widgets (Curated) |
| `skills/wow-api-widget/references/ANIMATION-WIDGETS.md` | Historical Retail reference (labelled). Animation Widget Types (Curated) |
| `skills/wow-api-widget/references/BASE-WIDGETS.md` | Historical Retail reference (labelled). Base Widget Types (Curated) |
| `skills/wow-api-widget/references/FONT-WIDGETS.md` | Historical Retail reference (labelled). Font Widget Types (Curated) |
| `skills/wow-api-widget/references/FRAME-CONTROLS.md` | Historical Retail reference (labelled). Frame Controls (Curated) |
| `skills/wow-api-widget/references/FRAME-MODELS.md` | Historical Retail reference (labelled). Frame Models — 3D Model Widget Types |
| `skills/wow-api-widget/references/FRAME-SPECIALIZED.md` | Historical Retail reference (labelled). Frame Specialized — Tooltips, Minimap, Movies, Map Overlays & Intrinsics |
| `skills/wow-api-widget/references/FRAME-WIDGETS.md` | Historical Retail reference (labelled). Frame Widget Type (Curated) |
| `skills/wow-api-widget/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). WoW Widget API (Curated) |
| `skills/wow-api-widget/references/SCRIPT-HANDLERS.md` | Historical Retail reference (labelled). Widget Script Handlers |
| `skills/wow-api-widget/references/TEXTURE-WIDGETS.md` | Historical Retail reference (labelled). Texture Widget Types (Curated) |
| `skills/wow-api-widget/references/generated/README.md` | wow-api-widget: generated declaration ledger |
| `skills/wow-api-widget/references/generated/forever.json` | FOREVER declaration ledger: 1574 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-api-xml-schema/SKILL.md` | Look up the World of Warcraft XML schema — all XML elements, |
| `skills/wow-api-xml-schema/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). WoW XML Schema |
| `skills/wow-api-xml-schema/references/XML-ANIMATIONS.md` | Historical Retail reference (labelled). XML Animations — `<AnimationGroup>`, `<Animation>`, and All Subtypes |
| `skills/wow-api-xml-schema/references/XML-FONTS.md` | Historical Retail reference (labelled). XML Fonts — `<Font>`, `<FontFamily>`, and Related Elements |
| `skills/wow-api-xml-schema/references/XML-FOUNDATION.md` | Historical Retail reference (labelled). XML Foundation — Root Elements, LayoutFrame, and Common Child Elements |
| `skills/wow-api-xml-schema/references/XML-FRAME-TYPES.md` | Historical Retail reference (labelled). XML Frame Types — `<Frame>` and All Subtypes |
| `skills/wow-api-xml-schema/references/XML-REGIONS.md` | Historical Retail reference (labelled). XML Regions — Texture, MaskTexture, Line, FontString, and Shared Elements |
| `skills/wow-client-targets/SKILL.md` | Resolve Retail, Forever, and Classic progression targets and verify version-specific WoW API evidence. Use before addon API lookup, client detection, compatibility decisions, TOC generation, or porting between WoW versions. |
| `skills/wow-client-targets/references/COMPATIBILITY.md` | Compatibility decisions |
| `skills/wow-client-targets/references/EVIDENCE-RECORDS.md` | Capability evidence records |
| `skills/wow-client-targets/references/FOREVER-70707-CHANGES.md` | Forever 1.60.1.70707 source changes (new in 2.3.0): the 70532 → 70707 migration guide - preset split, `SETTINGS_HEADER_TEXT_UPDATE`, damage-meter `specIconID` secrecy, loss-of-control/crowd-control secret tightening, `NamePartType.Combined`, pet move-to pair, level-constant rename, bag/item-button and gamepad helper churn; 118 relevant files, nine generated API definition files. |
| `skills/wow-client-targets/references/FOREVER.md` | Forever build evidence |
| `skills/wow-client-targets/references/SOURCE-EVIDENCE.md` | Verified source observations |
| `skills/wow-client-targets/references/targets.json` | SNAPSHOT MANIFEST: per-target source commit, version, derived interface value, verified date, fingerprint and source URLs (Forever: commit aff0d8cd5..., 1.60.1.70707, interface 16001, verified 2026-11-03). |
| `skills/wow-lua-api/SKILL.md` | Verbose guide to Lua 5.1 functions available in WoW, including |
| `skills/wow-lua-api/references/BASIC_FUNCTIONS.md` | Historical Retail reference (labelled). Basic Functions |
| `skills/wow-lua-api/references/BIT_LIBRARY.md` | Historical Retail reference (labelled). Bit Library |
| `skills/wow-lua-api/references/COROUTINE_LIBRARY.md` | Historical Retail reference (labelled). Coroutine Library |
| `skills/wow-lua-api/references/DEPRECATED_FUNCTIONS.md` | Historical Retail reference (labelled). Deprecated Functions |
| `skills/wow-lua-api/references/MATH_LIBRARY.md` | Historical Retail reference (labelled). Math Library |
| `skills/wow-lua-api/references/OVERVIEW.md` | Historical Retail reference (labelled). Overview |
| `skills/wow-lua-api/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). WoW Lua API (Lua 5.1) |
| `skills/wow-lua-api/references/STRING_DETAILS.md` | Historical Retail reference (labelled). String Details |
| `skills/wow-lua-api/references/STRING_LIBRARY.md` | Historical Retail reference (labelled). String Library |
| `skills/wow-lua-api/references/TABLE_DETAILS.md` | Historical Retail reference (labelled). Table Details |
| `skills/wow-lua-api/references/TABLE_LIBRARY.md` | Historical Retail reference (labelled). Table Library |
| `skills/wow-lua-api/references/generated/README.md` | wow-lua-api: generated declaration ledger |
| `skills/wow-lua-api/references/generated/forever.json` | FOREVER declaration ledger: 264 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `skills/wow-macro-commands/SKILL.md` | "Look up WoW macro commands (slash commands), macro conditionals, |
| `skills/wow-macro-commands/references/CONDITIONALS.md` | Historical Retail reference (labelled). Macro Conditionals Reference |
| `skills/wow-macro-commands/references/RETAIL-BASELINE.md` | Historical Retail baseline (labelled; subordinate to pinned contracts). WoW Macro Commands |
| `skills/wow-macro-commands/references/SLASH-COMMANDS.md` | Historical Retail reference (labelled). Slash Commands Reference |
| `skills/wow-macro-commands/references/SYNTAX.md` | Historical Retail reference (labelled). Macro Syntax Reference |
| `skills/wow-macro-commands/references/generated/README.md` | wow-macro-commands: generated declaration ledger |
| `skills/wow-macro-commands/references/generated/forever.json` | FOREVER declaration ledger: 9 records from Gethe/wow-ui-source@aff0d8cd5 (build 1.60.1.70707); one JSON line per declaration with full arguments, returns, payload, structures, enums and security annotations. |
| `SOURCE.md` | This provenance note: upstream repo/license/commit, vendoring scope, catalog usage recipe, evidence vocabulary, and this per-file index. |
