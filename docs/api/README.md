# API ground truth — the three local layers, and who outranks whom

**Answer first:** ForteXorcist has three API reference layers. They agree more than they
disagree, and they fail differently, so use them in a fixed order:

| # | Layer | Where | What it is pinned to | Fails by |
|---|---|---|---|---|
| **1** | **WoWAddonAPIAgents catalogs** | `docs/api/wow-addon-api-agents/` | `Gethe/wow-ui-source` @ `ca8368f2…`, **1.60.1.70532**, interface **16001** | Silent on load conditions + addon permission (it says so: `evidence.loadConditions = "unknown"`, `addonAccess = "unknown"`). Two builds behind our client. |
| **2** | **Atraeau generated reference** | `github.com/Atraeau/WoW-Addons` `docs/api/` (also hosted at `atraeau.github.io`) — not cloned locally yet | Client `APIDocumentation`, build **70170**, interface **16001**, ~6,598 funcs | Older build than layer 1; generated from the shipped API docs, so it carries less annotation detail (no per-field secret annotations). |
| **3** | **wow-ui-sim built-in API surface** | `$WORK/wow-ui-sim/` (`./run.sh wow-cli … audit-api`), binary **v0.1.39** | Sim's own extracted Blizzard UI tree (`~/.cache/wow-ui-sim/blizzard-ui/wowforever/`, 4,488 files) + the sim's **implemented** API surface | It is *the simulator*: an API can exist in the catalog and be absent/stubbed here (that is the point of `--gaps`). Never a compatibility certificate. |

```
real client  ~/.steam/…/_forever_/  interface 16001, build 1.60.1.70707
   └─ OUTRANKS ALL THREE. A feature is not done until it ran there (AGENTS.md §Verification).
      layer 1  pinned source declarations  → signature, payload order, security annotations
      layer 2  generated API reference     → fast signature/surface lookups
      layer 3  live simulator              → does it LOAD, does it CALL, does it ERROR
```

## When to trust which

- **Signature, argument order, nilability, event payload order, security annotation**
  → **layer 1**. It is the only layer that records the annotations we design around
  (`SecretWhenAurasRestricted`, `SecretWhenCooldownsRestricted`, `SecretWhenUnitSpellCastRestricted`,
  `ConditionalSecretContents`, `NeverSecret`, `IsProtectedFunction`, `SecretArguments`).
  Start at `wow-addon-api-agents/skills/wow-api-index/references/CURRENT-REFERENCES.md`,
  then the domain file `skills/<domain>/references/generated/forever.json`.
- **The written rule behind a design decision** (why we never branch on a cooldown read, why
  the cooldown display path is a duration object, why `PLAYER_SWING` payloads cannot share an
  unpack order with the range event) → **layer 1's curated guides**, the `CURRENT-CONTRACTS.md`
  and `CURRENT-*.md` files. They are commit-pinned prose, and they name the source file+line.
- **"Does this name exist at all / what else is in this namespace / quick signature"** →
  **layer 2** is the fastest; then confirm anything load-bearing against layer 1.
- **"Did our code break?"** → **layer 3**, and only layer 3:
  `./run.sh wow-sim --allow-ui-version-mismatch --addons-path <abs>/addon run-tests Forte_Cooldown`,
  plus `lua-errors`. For an API-surface sweep:
  `./run.sh wow-cli --allow-ui-version-mismatch audit-api --namespace C_Spell`
  (verified: reports the Blizzard UI tree's 252 `C_Spell` call sites with per-method counts),
  `--gaps` to list where the sim itself is thin, and
  `audit-api --index-lua-tree <abs>/addon` to index our own global publications.
  **A sim pass ≠ compatibility** — same policy as uiforever.com.
- **Anything about taint, protected operations, secret-value mechanics, settings registration,
  widget/FrameXML boundaries** → layer 1 curated guides **plus** a sim run, never prose alone.
  Our own hard rule: `luajit` stub tests accept invented APIs; they are not an API check
  (`PLAN.md` §5 lesson).
- **Version skew is the trap.** Layer 1 = 70532, layer 2 = 70170, layer 3 = the sim's pinned UI
  build (70532, run with `--allow-ui-version-mismatch` against our 70707), our client = 70707.
  When layers 1 and 2 disagree, neither is authoritative over the client — record the
  disagreement in a note under `docs/research/` and probe it in-game.

## Two rules that outrank every lookup

1. **`Environment = All` is not an addon permission flag, and a source declaration is not a
   runtime pass.** Layer 1 states it verbatim
   (`wow-addon-api-agents/skills/wow-api-index/references/CURRENT-REFERENCES.md`):
   *"`evidence.declaration` is `source-declared`; `loadConditions`, `runtime` and `addonAccess`
   are `unknown`."* A catalog hit answers "is it declared", never "may our addon call it".
2. **All three layers are subordinate to the installed client**
   (`<WoW install>/_forever_/`).
   Deploy only via `scripts/deploy.sh`.

## Layer 1 in one paragraph

`docs/api/wow-addon-api-agents/` is the Forever-targeted slice of
`github.com/JBurlison/WoWAddonAPIAgents` (MIT, cloned at `f9269081…`, 2026-11-01): 39 portable
skills, the client-aware instruction file, the pinned **Forever** declaration catalogs
(`forever.json`, one JSON line per declaration, full signatures/payloads/security annotations),
the snapshot manifest (`skills/wow-client-targets/references/targets.json`: commit, version,
derived interface value, verification date), the curated contracts (restricted values,
damage-meter/cooldown contracts, Forever identity, swing timers, aura APIs, settings
registration, UI loading/callback boundaries, visual fidelity) and the audit reports.
Provenance, scope decisions, the no-Node query recipe and a per-file index:
`wow-addon-api-agents/SOURCE.md`.

## Do not

- Do not treat a layer-2/3 absence as removal. Layer 1's standing rule:
  *"A source miss is unknown, not proof of removal."*
- Do not copy a `RETAIL-BASELINE.md` / `*_BASELINE.md` example into `addon/`. Those files are
  the vendor's own historical Retail 12.0.0 material, labelled as such
  (*"Historical Retail baseline: … Claims and examples require re-verification for every
  selected client"*) and explicitly subordinate to the pinned contracts. Concretely:
  - The damage-meter guide's `GetCurrentSessionID`, `GetSessions`, `GetSessionInfo`,
    `GetPlayerData`, `GetPartyData`, `ResetSessions` names are rejected by the vendor's own
    contract review — *"not supported by these reviewed declarations. Their runnable example
    has been withdrawn"*
    (`wow-addon-api-agents/skills/wow-api-combat/references/CURRENT-CONTRACTS.md`).
  - `UNIT-AURAS.md`'s `AuraData` field list (`isMeOrMyPet`, `isBossAura`, `nameplateShowAll`,
    `points`, `timeMod`, …) is a Retail 12.0.0 wiki dump: none of those names occurs anywhere in
    the vendored Forever catalogs, while `auraInstanceID` does. Treat the field list as a
    naming lead, not a Forever structure.
  - The same file's "Duration Calculations" snippet (`aura.expirationTime - GetTime()`) is
    arithmetic on aura fields — exactly the shape the Forever annotations forbid without a
    plain-value check (see `skills/wow-api-lua-environment/references/CURRENT-CONTRACTS.md`).
- Do not use the upstream `query.mjs` (Node) — it is not vendored; the shell recipe in
  `wow-addon-api-agents/SOURCE.md` replaces it.
