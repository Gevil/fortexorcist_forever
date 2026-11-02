# ForteXorcist for WoW Forever — Plan & Handoff

Status as of 2026-11-01 (WoW Forever launches 2026-11-04). Owner: Gevil.
Read `AGENTS.md` first for working rules; this file is the *what* and *why*.
**Continuing as the manager? Start at §10 (stage runbook): current state, standing rules, test recipes, the work queue and what to verify for each worker report.**

---

## 1. Goal

Rebuild the spirit of **ForteXorcist** (Xus's BC/Wrath-era addon: Spell Timer, Cooldown Timer,
raid/self messages + sounds, warlock Soulstone/Healthstone/Shard/Summon tools) as a **new addon
for WoW Forever**, for **all classes and specs** — spells, procs, items/trinkets.

**Priority order: Hunter first**, then the remaining classes. Warlock data is already generated
as a secondary reference.

This is *not* a port of the 2012 code. The old code, old spell tables and Gevil's
`fortexorcist_tbc_classic` fork are reference only (they target an API and ruleset Forever
does not have).

---

## 2. Background research (what we know, with sources)

### 2.1 ForteXorcist history
- Author Xus (Kazzak-EU). Last real release **v1.980.8, 2012-09-27** (MoP 5.0.4). A v1.99/v2.00
  rewrite existed only as changelog notes; never shipped. CurseForge marks it *Abandoned*.
  (wowinterface.com/downloads/info7532-ForteXorcist.html, curseforge.com/wow/addons/fortexorcist)
- `fstubner/ForteXorcist` (GPLv3) made it *load* on Dragonflight 10.1 in 2023; 9 open Lua errors,
  spell data untouched, dead since. `Gevil/fortexorcist_tbc_classic` targeted TBC Classic (old API).
- Community still asks for an FX replacement (r/WowUI "[HELP] Replacement addon for ForteXorcist").

### 2.2 What WoW Forever actually is (verified on the installed client)
- Blizzard's permanent Classic+ (level 60, original Azeroth + new zones/raids, reworked talents:
  ~467 talents, 111 new / 274 reworked per wowforeverguides.com).
- **Runs the modern Retail 12.x engine**, not the 1.13 Classic codebase. Interface **16001**,
  product `wowf`, installed build **1.60.1.70707** (`.build.info`), folder `_forever_`.
  `WOW_PROJECT_ID` reports `WOW_PROJECT_CAMELOT` since build 70170.
- Old Classic globals are gone: `GetSpellInfo`, `UnitAura`, `UnitBuff`, `GetContainerItemInfo`,
  `CombatLogGetCurrentEventInfo`, `GetSpecialization`… Use `C_Spell`, `C_UnitAuras`, `C_Container`,
  `C_Item`. `C_Spell.GetSpellCooldown` returns a **table**, not multiple values.
- Soul Shards are still classic **inventory items** on Forever (Soul Bags exist, "Soul Shards
  Forever" addon manages them).
- Curse of Agony / Curse of Doom are renamed **Bane of Agony / Bane of Doom** (confirmed in data).

### 2.3 Hard restrictions (the design ceiling)
Confirmed by two independent, currently-maintained addons on this exact client
(CooldownMaster `Core/Compat.lua` + changelog 2026-10-20..28; Thunderz96/forever-addon-kit):
1. **`COMBAT_LOG_EVENT_UNFILTERED` is forbidden** on Forever — registering it fires
   `ADDON_ACTION_FORBIDDEN`. No combat log at all.
2. **Addons cannot read buffs/debuffs in combat** (yours included). Reads throw or return secret
   values; `UNIT_AURA` payloads arrive as secret tables.
3. **Cooldown numbers can be secret in combat** too. Never compare/arithmetic on a raw read.
4. **Your own `UNIT_SPELLCAST_SUCCEEDED` stays readable** in combat (spellID plain). This is the
   one reliable in-combat signal.
5. Out of combat, everything reads plain again.
6. Range checks (`C_Spell.IsSpellInRange`, item range checks) are **not** secret.
   `PLAYER_SWING` fires for auto attacks (useful for a Hunter swing/auto-shot timer).
7. Never `RegisterEvent` at file top level except one bootstrap frame — a tainted main chunk
   can throw `ADDON_ACTION_FORBIDDEN` (kimgod1142/wow-tww-api-notes).
8. Client stops delivering Lua errors after 100 per session — kill error floods first.

### 2.4 Consequence for FX features
| FX feature | Verdict |
|---|---|
| Cooldown Timer (own spells, items, trinkets) | **Feasible** — cast-predict + reconcile (below) |
| Spell Timer — own buffs | **Feasible** — cast-predict in combat, real read out of combat |
| Spell Timer — debuffs on target / raid debuffs ticking live | **Not feasible** in combat. At most: cast-predicted timers for *your own* DoTs/stings (no confirmation until combat ends) |
| DoT tick detection | **Not feasible** (no combat log) |
| Soulstone / Healthstone / Shard spy | Feasible (bag scan via `C_Container`, buff presence out of combat) |
| Summon assistant, chat messages, sounds | Feasible |
| Hunter: aspect reminder, trap timers, auto-shot/swing timer, range/dead-zone | Feasible (cast events, `PLAYER_SWING`, range APIs) |

### 2.5 Blizzard Cooldown Manager — decided: do not build on it
`C_CooldownViewer` exists on Forever, but CooldownMaster deliberately disables it there
(`HAS_BLIZZ_CDM = IS_RETAIL and TOC >= 120000` → false on 16001), it was empty for most classes
for most of beta, it is driven by the retail spec model Forever doesn't have, and it knows
nothing about FX's class tools. EllesmereUI ships a "CDM replacement" for the same reasons.
Keep `Compat.HAS_BLIZZ_CDM` as a future switch only. Details: `docs/why-not-blizzard-cdm.md`.

---

## 3. Architecture

### 3.1 Reference implementation
**CooldownMaster** (wheelbarrel00/CooldownMaster, **MIT**) — installed at
`<WoW>/_forever_/Interface/AddOns/CooldownMaster/`. Studied in depth; adapt patterns, credit in
README if code is reused. Key files: `Core/Compat.lua`, `Core/Engine.lua` (5,198 lines),
`UI/Bars.lua`, `UI/ReadyFrames.lua`. Secondary cross-check: Thunderz96/forever-addon-kit
`ForeverCDM` (MIT).

### 3.2 Core pattern: cast-predict + reconcile
- In combat: a successful own cast starts a *predicted* entry (`start = GetTime()`, duration =
  learned value, else generated base).
- Any *plain* read (always out of combat, sometimes in combat) re-anchors the entry and **learns**
  the real duration (persisted) — talents/gear get picked up automatically.
- A secret read never overwrites known state. Everything risky goes through `Compat.PlainOrNil`.
- Track by **spell name**, not ID (data holds the highest-rank ID; lower-level chars know lower ranks).
- Entries that were only predicted (never confirmed) must not claim certainty — e.g. buffs cast
  on someone else (CooldownMaster `_inferred` rule: inferred entries never fire a "ready" pop).

### 3.3 Addon layout (one shared global namespace `ForteXorcist`)
Mirrors original FX's multi-addon split:
```
addon/Forte_Core/       bootstrap, Compat, Constants, module registry, /fx, SavedVariables ForteXorcistDB
addon/Forte_Cooldown/   class-agnostic cooldown engine + display (in progress)
addon/Forte_<Class>/    generated data per class (Data/<Class>.lua) + later class-specific tools
```
Everything the game loads lives under `addon/`; `tools/`, `scripts/`, `docs/` never ship.
Every addon ships `X.toc` **and** `X_Camelot.toc` (interface 16001) — the Forever client prefers
the `_Camelot` suffix (Atraeau/WoW-Addons; CooldownMaster does the same).
Modules call `ForteXorcist.RegisterModule(name, mod)`; `mod:OnEnable()` runs at `PLAYER_LOGIN`.

### 3.4 UI rules (from CooldownMaster)
- Frame pools: never create/destroy per update; acquire/hide.
- Dirty-check every style setter (texture/font/color) — they run every tick.
- Staggered polling (~10 Hz display, ~1 Hz full rescan), not one heavy per-event handler.
- Countdown text from our own plain computed numbers; never feed a secret number to a widget
  `Cooldown:SetCooldown` rejects secret values; sanctioned path is
  `C_Spell.GetSpellCooldownDuration` → `Cooldown:SetCooldownFromDurationObject`.

### 3.5 Design law — the Classic Cooldown Timer (owner-approved 2026-11-01; corrected same day)
Source law: `/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua` — defaults `FW.InstanceDefault.Cooldown`
(:1801-1866), render loop (:499-642), time tags (:1233-1330). Visual truth: `docs/refs/ref2,3,4,6.png`,
walkthrough frame `docs/media/frames/walk-000315.png`. **Correction:** the first extraction misread these
numbers as a list of 250×24 rows; the original Cooldown Timer is **one timeline bar** (rows are the
Spell Timer, §3.6). Rows-based `Display.lua` work was stopped 2026-11-01 (§9).
- **One horizontal bar** 250×24: `Aluminium` fill, white α 0.20 (`BarColor`); black α 0.50 backdrop
  `Background` + `Border` (`Backdrop = {bg, border, false, 16, 5, 3}`).
- **Power-scale time axis:** icon at `x = W·(f1·(t/Max)^Loga + f2)`, `f1 = (W−ih)/W`, `f2 = 1−f1`
  (:517-526); `Max = 300`, `Loga = 0.33`; `t > Max` parks at the right end. Icon size = bar height
  (24) — `IconSize = {[0]=false, 36}` is an opt-in (:1805, :502).
- **Time tags** `0 1 10 30 60 120 300 600` on the same curve; tags ≥ `Max` not drawn; ≥ 60 s print as
  minutes (`2`, `5`); tag text α 0.20 (`TextColor` :1838).
- **Overlap groups:** icons overlapping by > ½ icon merge into a group that cross-fades focus between
  members; the group string lists `time name` per member (:556-638).
- **End of cooldown:** at `t ≤ 0` the end effect fires; removed at `t ≤ −1` (:509-512).
- **Category colors** (verbatim :1842-1855): Spell `1,.5,0` · Powerup `0,.75,1` · Item `1,1,0` ·
  Potion `0,1,0` · Healthstone `0,1,.5` · Pet `1,0,.95` · Internal `0,.6,.85` · ResTimer `1,0,0` ·
  Buff `1,1,1` · Debuff `1,0,0` · Enchant `1,1,1` · Soulstone `.64,.21,.93` (BuffOther/DebuffOther off).
- **Flags on by default:** Splash (factor 4), Spark, Warn, IconTime, Detail, Ignore; `Alpha 0.2` /
  `AlphaMax 1.0`; `IgnoreCooldown = 2.99` (:1796) ⇒ `Engine.MIN_COOLDOWN = 2.99` (done).
  Exact semantics of Alpha/Warn/Spark/segment coloring: `docs/reference-functional-spec.md` §1.
- **Font:** URW Gothic Book 11 (`Forte_Core/Fonts/URWGothic-Book.ttf`) — the libre lookalike of the
  original's Monotype Century Gothic (owner decision 2026-11-01; comparison `docs/media/sim/font-compare.png`).
- **Fidelity rule:** no "matches the original" claim without a side-by-side wow-ui-sim screenshot
  (`docs/media/sim/`) against `docs/refs/`.
- Assets vendored from the GPL-3.0 zip (textures only) with `ATTRIBUTION.md` + `gpl-3.0.txt`.

### 3.6 Original module map → FX (from the options index, `docs/refs/options-panel.png`)
The original is ~14 modules in one options window. Every row gets a Forever verdict; anything marked
*pending* is settled by `docs/reference-functional-spec.md` (agent `FuncSpec`).

| Original module | What it did | Forever ceiling | FX home · phase |
|---|---|---|---|
| Cooldown Timer | power-scale timeline: own spells, items, potions, pet, internal CDs | feasible: cast-predict + plain reconcile | `Forte_Cooldown` · P1 |
| Secondary Splash | big fading icon (+glow) when a cooldown is ready | feasible (own state) | `Forte_Cooldown` · P2 |
| Spell Timer | stacked rows: self buffs, own DoTs per target (multi-target), others' buffs/debuffs | own buffs/own casts: predicted in combat, real out of combat. Multi-target **others'** auras / tick detection: **not feasible** (combat log) | `Forte_Timer` · P4 |
| Soulstone Tracker · Healthstone Spy · Shard Manager · Shard Spy | warlock stone/shard tools; "spy" = other players' stones | own: feasible (bags, own casts); spying on others: *pending* | `Forte_Warlock` · P5 |
| Summon Assistant | ritual-of-summoning helper | feasible (casts, chat) — *pending* channel rules | `Forte_Warlock` · P5 |
| Party/Raid Messages · Self Messages · Sound | announcements, local messages, sounds | feasible; which chat channels addons may use on Forever: *verify* | `Forte_Core` · P6 |
| Talent Spy | others' talents | inspect APIs: *pending* | optional · P7 |
| General / Advanced Options | one window, color-coded module sections, tips, per-option reset, profiles/clones | feasible (own frame, own SavedVariables) | `Forte_Core` · P6 |

---

## 4. Spell / item data pipeline

No hand-typed spell IDs. Data is generated.

| Source | Path | Role |
|---|---|---|
| mythicsim-forever-engine (Rust, MIT) | `$WORK/mythicsim-forever-engine/data/*.jsonl` | **Primary.** 7,503 spells with DurationMs/CooldownMs/GCDMs/CastTimeMs/Effects; items, enchants, consumables. `manifest.json` pins `client_build` (currently **1.60.1.70425**). |
| wowsims/forever (Go) | `$WORK/wow-forever-sim/forever/` (pull only, never commit) | Cross-check class/proc/talent logic (`sim/<class>/*.go`). Pulled to `b70888a5` (2026-11-01). |
| wowsims/gamedata | github.com/wowsims/gamedata | Per-build diffs (`patches/1.60.1.70707/…`) to catch drift between the mythicsim pin and live. Not cloned yet. |
| mythicsim.com/wow-forever, wowsims.com/forever | web | Human reference only (class changes, talent rework); the websites are not data sources. |

Generator: `tools/gen_spell_data.py [--dry] <class>` reads `tools/spell_lists/<class>.json` (spell
*names* grouped by purpose) and writes `addon/Forte_<Class>/Data/<Class>.lua` (`ForteXorcist.Data.<Class>`
+ `…ByName`); unmatched names are reported, never dropped. Since 2026-11-01 (agent `GenFix`):
candidate rows are **scoped to the class's `ClassFlags.Family`** (Mage 3, Warrior 4, Warlock 5,
Priest 6, Druid 7, Rogue 8, Hunter 9, Paladin 10, Shaman 11; 13 = consumables; **no Death Knight in
this build**), and the rank pick prefers **the row that carries the cooldown**, then level, then ID.
This fixed cross-class collisions (Circle of Healing → a Mage copy, Divine Protection → Priest) and
recovered cooldowns (Rapid Fire 3045 = 300 s, Evocation 480 s).

Current lists (all 0 gaps, verified by independent `--dry` runs 2026-11-01): Hunter 73 · Warlock 76 ·
Mage 51 · Paladin 56 · Priest 47 · Shaman 61 · Druid 52 · Rogue 50 · Warrior 64. Total 530 spells
across the 9 Forever classes (no Death Knight in WoW Forever; the DK placeholder was removed 2026-11-02).

Rank-pick order now (agent `DataWave`): in-family row carrying a cooldown/duration > uncoded
(Family 0) carrier > in-family bare > uncoded bare; never a foreign family. Bare *companion rows*
(sole effect Type 6 / Aura 332 pointing at the real spell) lose to the row that carries the window.
Uncoded picks are printed as `info:` lines — e.g. Black Arrow 14296, Eagle Eye 6197, Feed Pet 6991,
Use Soulstone 20761, Firestone 17949. Mangle stays out of Druid (its only row is filed under Mage).

Remaining data work: (1) re-measure spell IDs on the live client before trusting them (§8);
(2) trinket/item/proc harvest (Phase 3+); (3) per-class tool lists beyond cooldowns/buffs.

---

## 5. Dev & test tooling

| Tool | Where | Use |
|---|---|---|
| **wow-ui-sim** v0.1.39 (Osso, GPL-3.0), Forever build | `$WORK/wow-ui-sim/` — run via `./run.sh wow-sim …` | Headless UI/API simulator with a Forever profile (incl. `spell_aura_secrecy` data). `run-tests <Addon>` runs `Interface/AddOns/<Addon>/tests/*.lua` (`test(...)`, `assertEquals`, `async_test`, `A_Admin` namespace to set combat/buffs/party). Also `lua-errors`, `dump-tree`, `screenshot`. |
| uiforever.com | browser, `/app?flavor=forever` | Owner-interactive gate. **Tested 2026-11-01:** upload `/tmp/fx_uif.zip` (addons without `tests/`) via the page's `input[type=file]` (index 4, `.zip`), click Import, `/reload`. All 11 `Forte_*` addons load; Errors tab "No Lua errors"; Missing-APIs list empty for our calls; console runs `/fx status` and Lua one-liners (`=expr` prints). Class picker → Hunter → bar renders on the real Blizzard UI. Gotcha: the simulated player has no real cooldown state, so our own reconcile (plain read says ready) clears predicted timers — to inspect the display set `Engine.OnRead = function() end` in the console first. Captures: `docs/media/sim/uif_hunter_*.png`. |
| luajit | `/usr/bin/luajit` | Fast syntax check + pure-logic smoke tests with stubs (no `luac` on this box). |
| Real client | `<WoW install>/_forever_/` | Final verification only. |

### 5.1 External references & MCP candidates (owner-flagged 2026-11-01, evaluation pending)
| Ref | What | Fit for FX |
|---|---|---|
| **Atraeau/WoW-Addons** `docs/api/` (generated API ref, also hosted at atraeau.github.io — from client APIDocumentation build 70170, interface 16001, ~6,598 funcs) | The authoritative Forever API surface. `github.com/Atraeau/WoW-Addons` — no local clone yet; clone into `$WORK/` on first heavy use. | **Use now** for API signature lookups (worker rule already: no invented APIs). |
| **RdyGaming/hated-wow-mcp** (`npx` MCP server, 20 tools) | In-game Lua API + Blizzard shipped UI source + CVars/FileDataIDs/texture atlases + Lua lint + TOC/XML validation + scaffolding; flavors incl. **WoW Forever**. | Strong candidate: lint/TOC-validate/API-lookup for workers. Register in `~/.config/opencode/opencode.json` after owner OK. |
| **Geraldlol/witchcraft** (`docs/MCP.md`) | Claude Code / Codex **inside** WoW Forever: terminal tabs + WoW MCP server for character data. | Candidate for the real-client phase: live `/fx status`, Lua error capture, event probing in the running game. |
| **uiforever.com** (Osso; browser UI simulator) | **WoW Forever flavor live**: the real Blizzard interface in-browser; drag-drop AddOns/WTF; combat scenarios (combat state, target/focus, auras, party/raid); Lua console + full stack traces; **per-addon missing-API list**; resolutions/UI-scales; Edit Mode; `/reload`; nightly compat list (~200 Forever addons). Same engine family as our headless wow-ui-sim. | Adopt as the owner-interactive pre-client gate (fight-state look, API-surface audit). Same policy as here: simulator pass ≠ compatibility; real client final. Owner-facing, no headless CLI — our `wow-ui-sim` stays the automation lane. |
| **JBurlison/WoWAddonAPIAgents** (MIT) | Version-aware agent suite with a **Forever target**: generated API declaration catalogs from pinned client snapshots (signatures, event payloads, access annotations, snapshot manifest) + curated guides (restricted values, cooldown/damage-meter contracts, Forever identity, swing timers, aura APIs, settings registration) + UIForever/Witchcraft integration + visual-fidelity guardrails (v2.2.0: compare rendered screenshots before declaring a match). | **Importing now** (agent `ApiPack`) → `docs/api/wow-addon-api-agents/` (skills/guides/catalogs only, no plugin packaging). API ground-truth layer #1; see `docs/api/README.md` for the 3-layer trust order. |

**wow-ui-sim gotcha:** the release binary needs ICU 78; Fedora here ships ICU 77.
`$WORK/wow-ui-sim/icu-vendor/` holds only `libicui18n/libicuuc/libicudata.so.78`
copied from the installed `org.freedesktop.Platform 26.08` flatpak runtime; `run.sh` puts that
dir (and nothing else) on `LD_LIBRARY_PATH`. Do **not** point `LD_LIBRARY_PATH` at the whole
flatpak lib dir (its glibc breaks the binary). No rpm-ostree layering.
`./run.sh wow-sim --version` → `wow-sim 0.1.39` (verified).

**wow-ui-sim setup (all handled by `run.sh`, verified 2026-11-01):**
- Headless by default (`unset DISPLAY WAYLAND_DISPLAY`); otherwise startup errors pop zenity
  dialogs on the owner's desktop. `WOW_SIM_GUI=1` to opt back in.
- This Battle.net launcher writes `.product.db` as a bare `ProductInstall` protobuf; the sim wants
  a `Database{ repeated ProductInstall = 1 }` wrapper ("invalid wire type value: 7").
  `run.sh` keeps `$WORK/wow-ui-sim/install-shim/` (symlinks to the real `Data/`,
  `.build.info`, `_forever_/` + a wrapped `.product.db`, re-wrapped when the real file changes)
  and sets `WOW_INSTALL_PATH` to it. The real install is never modified.
- The sim release pins UI build 70532; our client is 70707 → always pass
  `--allow-ui-version-mismatch`. Blizzard UI cache: `~/.cache/wow-ui-sim/blizzard-ui/wowforever/`
  (4,486 files from the live client; refresh with `run.sh wow-cli casc sync-blizzard-ui
  --allow-ui-version-mismatch` after a client patch).
- Baseline noise: Blizzard-side Lua errors (`Blizzard_Transmog` SMART_NAV_INPUT_DIRECTION,
  `Blizzard_GamepadSmartNavigation` invalid import) appear in every run — sim gaps, not ours.
  Only errors from `Forte_*` paths count.
- Test command: `run.sh wow-sim --allow-ui-version-mismatch --addons-path
  $REPO/addon run-tests Forte_Cooldown`.

**Lesson:** luajit stub tests accept any API name. A worker shipped invented APIs
(`CreateStatusBar`, `OnDragStopped`, wrong `CreateTexture`/`CreateFontString` signatures) that
passed stubs. UI/API code is only accepted after a wow-ui-sim run.

---

## 6. Current state (2026-11-02, commit `4b16d27`+)

Repo `github.com/Gevil/fortexorcist_forever` (private), pushed after every verified step. **Never loaded in the real
client yet** (first session = launch day, `docs/launch-day.md`). All addon paths relative to `addon/`.
Verification: `python3 scripts/gate.py` = **PASS, 293 sim tests** (Cooldown 113, Core 16, Hunter 37, Options 45,
Timer 45, Warlock 37), live load probe (10 data sets, 7 modules), toc twins, syntax, API/enum/event lint, data
determinism. Behaviour battery on uiforever.com: §10.4 T1–T15 + live Timer/Hunter checks (§9).

| Addon | What it contains | State |
|---|---|---|
| `Forte_Core` | registry, `/fx` slash + per-module status loop, SavedVariables `ForteXorcistDB`, `Compat` (PlainOrNil fail-closed, item/spell seams, `IsPlayerSpell` fallbacks, `FX.SecretState`), `Probe` (`/fx probe` launch-day kit), URW Gothic font, the original's full texture set | done |
| `Forte_Cooldown` | Engine (cast predict, read tiers: numeric / NeverSecret booleans / duration objects, charges, edge fallback), Items (trinkets, potions, shared categories), Enchants (weapon enchants, per slot), Timeline (Classic power-scale bar, segment fills, splash + ready pulse to the original's law, charge counts, name-keyed slots, all settings live) | done |
| `Forte_Timer` | Spell Timer v1: own-cast predicted rows by spell+target, the original's reconcile law, out-of-combat aura correction, groups by target, kind colours (0/530 Default), original geometry | done (v1 scope = own casts, owner-approved) |
| `Forte_Hunter` | data + aspect tracker + Auto Shot swing tracker + swing bar + aspect reminder + page | done |
| `Forte_Warlock` | data + shard/soulstone/healthstone/ritual trackers + the original's four purple plates + pages | done |
| `Forte_Options` | the original-style window, 16-cell module index lighting registered pages, settings registry, every key wired live | done |
| `Forte_Items` | generated on-use / proc / consumable data (238 / 405 / 79) | done |
| other `Forte_<Class>` | generated cooldown data (530 spells total) — no class tools yet | data only |

Open before/at launch: load-on-demand class data (in progress), review 3 (in progress), launch-day probes and
feature smoke checks (`docs/launch-day.md`), proc gate containers (after probes), per-class tools beyond Hunter/Warlock.

---

## 7. Phased plan

### Phase 0 — housekeeping (small)
- Repo exists (`Gevil/fortexorcist_forever`). Commit/push only when the owner asks.
- `README.md`: what it is, install, data regeneration, credits (CooldownMaster MIT, mythicsim MIT,
  wowsims MIT, original FX by Xus).
- `scripts/deploy.sh`: symlinks each `addon/Forte_*` (toc-bearing) into
  `<WoW>/_forever_/Interface/AddOns/` (`ln -sfn`, idempotent; `--dest`, `--remove`,
  `--list`; refuses hand-made entries). Edits then need only `/reload`;
  new files/TOC changes need a client restart.

### Phase 1 — Classic Cooldown Timer (Hunter) — *display landed; items + sign-off remain*
Engine + event wiring are done (§6). What remains is the display, now specified by §3.5.
1. **Get green first:** fix `test_engine.lua:77` to the new data facts (Rapid Fire tracked, 300 s;
   pick a genuinely cooldown-less row for the negative check); drop the exact float compare.
2. **Timeline display** (`UI/Timeline.lua`, replaces `Display.lua` as the Cooldown view): one 250×24
   bar, power-scale positions, custom tags, overlap groups with cross-fade, category colors,
   end-of-cooldown effect, cast splash, drag/lock/reset + saved position (keep the `Display`
   public API so `Init.lua`/`Module.lua` don't change). Pure math (position, tag placement,
   grouping) in a frame-free helper so it is unit-testable in luajit *and* the sim.
3. Keep the current row renderer as `UI/Rows.lua` (unused by Cooldown; Phase 4 seed).
4. Items/trinkets/potions/healthstones (`GetInventoryItemCooldown`, `C_Container.GetItemCooldown`,
   bag scan; CooldownMaster `PollOneItem`/`ClassifyBagItem` pattern) — category colors Item/Potion/
   Healthstone.

**Acceptance:** sim `run-tests Forte_Cooldown` green incl. new timeline tests (positions at
t = 0/1/10/30/60/120/300/600 match the formula; groups form at > ½ icon overlap); `lua-errors`
clean for `Forte_*`; side-by-side `docs/media/sim/fx_timeline_*.png` vs `docs/refs/ref2,3,6`
reviewed by the owner; uiforever.com Hunter shows the bar; real client: Disengage/Concussive Shot
slide to 0 and end, in and out of combat, zero Lua errors.

### Phase 2 — Cooldown polish
Secondary Splash (big fading icon + glow, `SecondSplashMax 4`), Warn (failed cast on a cooling
spell → attention on its icon), Spark, Alpha/AlphaMax idle-vs-active, Min/Max range and remaining
filters, Hide/HideCombat, vertical/flip — each against `reference-functional-spec.md` §1.
Combat/secret integration test via `A_Admin`.

### Phase 3 — Hunter class tools (`Forte_Hunter` gains code)
- Aspect reminder (missing aspect out of combat), trap timers (cast-predicted, arming/duration),
  Hunter's Mark / sting timers on target (cast-predicted only, reconciled out of combat),
  auto-shot / swing timer via `PLAYER_SWING`, range / dead-zone light (8–35 yd, range APIs plain).
  Reference: charles-hood/wow-forever-addons `HunterHUD` (MIT) for measured facts.
- Pet: feed reminder, pet ability cooldowns (needs the uncoded-family data fallback, §4).

### Phase 4 — Spell Timer (`Forte_Timer`, rows — `docs/refs/ref4.png`, demo3 2:45)
- Row look from the original: icon, time left, target name or spell name, category color, grouped
  per target with a header row; sections for self / target / others.
- **Reconciliation law already exists in the original** (spec §3.4, `Forte_Timer.lua:33`, `:1147-1204`):
  a cast creates an *uncertain* prediction (`guid == ""`); a later real observation within a tolerance
  window (`maxlag = 1.00`, a hard-coded constant — not a user option; corrected 11-02 per `docs/design-spell-timer.md` citing `Forte_Timer.lua:33`) is **adopted** into it; longer remaining → extend, shorter →
  refresh. Port this as the Spell Timer's reconcile rule instead of inventing one. The original also
  defers a cast's effect by 0.2 s and flushes its queue after 3 s (spec §2.1).
- **Hidden cooldowns** (spec §1.2, `Forte_Cooldown.lua:149-154`): a proc *buff* synthesises a cooldown
  starting at `expire − duration` (e.g. internal cooldowns of trinkets/procs) — Phase 2, out-of-combat
  reads only on Forever.
- **Does not carry over:** resist classification, DoT tick detection, summon/death combat-log rows, Talent
  Spy, weapon-enchant timers, world-map sampling by the Summon Assistant (spec §10). Swing mode and
  multi-charge display are **absent** from the original source despite the changelog — treat as new work.
- Out of combat: `C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")` learn name→duration.
- In combat: cast-predicted entries keyed by name (CooldownMaster `_buffByName` /
  `RestartBuffFromCast`); own DoTs per target from `UNIT_SPELLCAST_SENT` target name + cast success.
- **Ceiling (state it in the UI):** no tick detection, no others' auras, no refresh/clip truth in
  combat; predicted rows are marked as predicted. Procs without a cast: out of combat only.

### Phase 5 — Warlock tools + remaining classes
Soulstone Tracker, Healthstone, Shard Manager, Summon Assistant (own state; "spy" features per
`FuncSpec` verdicts). Then per-class tools in the order Mage, Priest, Druid, Rogue, Warrior,
Shaman, Paladin, using wowsims `sim/<class>/*.go` for procs/talent spells.

### Phase 6 — Options window, messages, sound
One options window in the original's shape (`docs/refs/options-panel.png`): title bar with version,
module index buttons color-coded per module, collapsible sections (Some Tips / Basics / Specifics /
Frame Sizing / Coloring / Appearance), per-option reset, profiles/clones. Party/Raid + Self Messages
(`SendChatMessage` — verify which channels Forever allows from addons), sounds, localization.

---

## 8. Risks / open questions
- Launch build may differ from 70707; re-check `.build.info`, regenerate data after a
  mythicsim/wowsims pull, scan `wowsims/gamedata` diffs.
- **Spell IDs are build-sensitive** (measured 2026-11-01 in `test_engine.lua`): the sim's profile
  spell DB (70532) resolves every name-resolvable data row to a *different* spellID than our
  70425-pinned data, incl. collisions (data id 603 "Bane of Doom" = "Doom" in the sim DB;
  1223963 "Corruption" → 172). The sim profile DB is not a Forever ID oracle. Consequences:
  (a) our runtime resolves spells **by name** (`Module.isKnown`, `GetSpellInfo(name)`) — keep it;
  (b) never trust hard-coded IDs across client patches — regenerate data per build;
  (c) `test_engine.lua` asserts name-equality hard, ID-equality as warnings only.
  Coverage: the sim profile DB sees only 12/30 Hunter + 13/34 Warlock rows (incl. "Deterrence")
  — sim profile gaps, not data defects; the live client is the ID ground truth.
- Exactly which cooldown reads are secret in combat on live is not measured by us yet — log it
  (count `"secret"` vs `"anchored"` results from `Engine:OnRead`) in the first real session.
- **Core premise, unproven at source level (found by `ApiPack`, 2026-11-01):** the pinned Forever
  catalog annotates `UNIT_SPELLCAST_SUCCEEDED` (and every sibling cast event) with
  `SecretWhenUnitSpellCastRestricted`; only `castBarID` is `NeverSecret`, and the vendor's own audit
  says "no blanket promise that a self-cast event is always plain"
  (`docs/api/wow-addon-api-agents/docs/audit/FOREVER-FINDINGS.md:41`). "Our own spellID is plain in
  combat" is an observation from CooldownMaster, not a guarantee. Today's handler is safe either way
  (`Module.lua:87-95` does no arithmetic on the id and acts only on a plain name) but a secret id
  would **silently disable in-combat prediction**. Mitigations, in order:
  (1) instrument — `/fx status` reports casts seen / plain / secret, so the first real session
  answers it; (2) fallback — `SpellCooldownInfo.isActive` and `isOnGCD` are `NeverSecret`
  (`SpellSharedDocumentation.lua:18`), so a tracked spell's cooldown *starting* can be detected by
  polling the boolean even when the numbers are secret, then anchored with the learned duration;
  (3) the handler must tolerate the 4-field payload (`unit, castGUID, spellID, castBarID`).
- Item/trinket cooldown APIs (`C_Item.GetItemCooldown`, `C_Container.GetItemCooldown`) carry no
  `SecretWhen…` annotation at the 70532 pin — probe before Phase 1 relies on them. Pin drift
  70532 → 70707 is not covered by any local evidence.
- Swing timer contract: `PLAYER_SWING` is `(swingDuration, swingType)` — duration first — while
  `PLAYER_SWING_RANGE_UPDATE` leads with `swingType`; two handlers, never one unpack order.
- Earlier beta reports: SavedVariables were not loaded back (fixed later?). The installed client's
  `WTF/Account/*/SavedVariables/` has real files with `.bak`, which suggests saving works now —
  verify `ForteXorcistDB` survives a full client restart.
- `_Camelot.toc` + plain `.toc` both present: confirm the client loads exactly one copy.
- wow-ui-sim is GPL-3.0: use it as a tool only, don't vendor its code into FX.
- **Font licensing — resolved 2026-11-01:** `GOTHIC.TTF` is Monotype Century Gothic ("All Rights
  Reserved"); bundling it in 2012 did not make it GPL. Owner chose URW Gothic (AGPL-3.0 with a
  PostScript/PDF font exception, per `/usr/share/licenses/urw-base35-fonts/LICENSE`). Still to verify:
  the **real client** accepts the converted TTF (the sim result comes from agent `Timeline`).
- **Repo license — resolved 2026-11-01:** `LICENSE` at the repo root is GPL-3.0 (byte-identical to
  `addon/Forte_Core/gpl-3.0.txt`). It covers our code and is compatible with the vendored GPL-3.0
  textures and the AGPL-3.0 font (GPL-3.0 §13). Per-asset terms: `addon/Forte_Core/ATTRIBUTION.md`.
- **Original vintage:** every reference video is Cata/MoP-era (v1.959–1.980.8); the Forever client is
  Retail 12.x. Faithful means *look and interaction*, not the 2012 data model.
- **Load-on-demand SavedVariables (launch-day probe, not a sim fact):** every `Forte_<Class>` add-on is
  `## LoadOnDemand: 1` and `Forte_Core` loads only the player's at `PLAYER_LOGIN`
  (`addon/Forte_Core/Core/Loader.lua`). In the real client a load-on-demand add-on's SavedVariables arrive
  *with the load*; the sim only ever restores the always-loaded set
  (`docs/reference/wow-ui-sim-specs/addon-lod-metadata.md`, `saved-variables.md:50`), so "a Hunter's saved
  Hunter Tools settings survive a relog" is unproven here -- day-1 check, `docs/research/secrets-unknowns.md` §9.
- **Spell Timer expectations:** the multi-target DoT view in the media (demo3 2:45) was combat-log
  driven; on Forever it can only show our own casts, predicted. Say so in the UI and docs.

---

## 9. Decision & correction log
Append-only; newest last. Every owner decision and every correction of an earlier claim lands here.

| Date | Entry |
|---|---|
| 2026-11-01 | Owner: 1:1 Classic skin; vendor the identity subset of the GPL-3.0 zip with attribution. |
| 2026-11-01 | Owner: research all classes' spells/cooldowns/procs/items → agents `DataA/B/C` (8 classes done; Warrior was never assigned — gap found in manager review). |
| 2026-11-01 | Data: Forever 1.60.1.70425 has 9 class families, **no Death Knight**; cross-class shared cooldown categories exist (Stealth↔Prowl 38, Kidney Shot↔Between the Eyes 270, shocks 19). |
| 2026-11-01 | Generator hardened (`GenFix`): family scoping + cooldown-carrier rank pick; uncoded-family fallback still to do. |
| 2026-11-01 | Owner: keep all media and sim screenshots in the repo folder → `docs/refs/`, `docs/media/` (git-ignored for weight). |
| 2026-11-01 | Owner: adopt uiforever.com as the interactive pre-client gate; import JBurlison/WoWAddonAPIAgents Forever catalogs (agent `ApiPack`). |
| 2026-11-01 | Owner: main session on Opus 5.5; subagents stay on basalt (`fx-worker`/`fx-scout` pin `basalt/qwen3.8-flash-next-nvfp4-basalt` in their own frontmatter, independent of the session model). |
| 2026-11-01 | **Correction:** the Cooldown Timer is one power-scale timeline bar, not a list of rows (§3.5). Found once the session could see the reference images; `ClassicSkin` agent stopped, its rows work reclassified as the Spell Timer seed. |
| 2026-11-01 | **Correction:** the default icon size is the bar height (24), not 36 (36 is an opt-in). |
| 2026-11-01 | **Correction:** `GOTHIC.TTF` is not GPL (Monotype). Owner chose **URW Gothic** (AGPL-3.0 + font exception) as the libre lookalike; vendored as unmodified `.otf` + converted `.ttf`; `ATTRIBUTION.md` rewritten with per-asset licenses; Century Gothic removed from the addon, `**/GOTHIC*.TTF` git-ignored. |
| 2026-11-01 | **Correction (process):** a `.gitignore` overwrite dropped 4 rules (restored); the first walkthrough "contact sheets" were single frames (rebuilt with timestamps); the 720p cap on the first video was not a verified geo-block (yt-dlp lacked a JS runtime). |
| 2026-11-01 | Owner: add the license file → GPL-3.0 `LICENSE` at the repo root (see §8). Owner switched the main session to Sonnet 5.5; subagents stay on basalt. |
| 2026-11-01 | **Correction:** the state table said every class had tocs; six did not, so their data never loaded. Found by `DataWave`, fixed by the manager (toc pairs for Mage/Paladin/Priest/Shaman/Druid/Rogue; Warrior's title color fixed from the Death Knight color to its own). |
| 2026-11-01 | `Timeline` agent found two source details that refine §3.5: minute labels apply only above 60 s (`v > 60`, so 60 prints "60", 120 prints "2"), and the original always draws a trailing tag at `Max`. Both implemented per source. |
| 2026-11-01 | **Correction:** the timeline agent reported 20/20 tests, but the manager's re-run found 19/20 — my own toc addition made Paladin a class *with* data, breaking the "missing class data" test. Fixed (negative case → DEATHKNIGHT), re-run green. Rule kept: manager re-runs every gate, never relays a worker's number. |
| 2026-11-01 | `ApiPack` landed `docs/api/` (235 files, 20 MB, MIT, upstream commit `f9269081`; three-layer trust order in `docs/api/README.md`). Finding logged in §8: the cast-event premise is observed, not source-guaranteed; instrumentation + an `isActive` fallback are Phase 1 work. |
| 2026-11-01 | `FuncSpec` landed the functional spec. **Owner rulings needed** (spec §14): (1) `Register.lua` is missing from the zip — accept our generated data as its replacement, or supply the original zip's file; (2) multi-charge: changelog says shipped, source says absent — build it new?; (3) weapon-enchant timers need a replacement for `GetWeaponEnchantInfo`; (4) five dead or buggy paths in the original (e.g. Warlock `spell`/`s` at `Forte_Class/Warlock/Warlock.lua:191`): replicate shipped behaviour, advertised behaviour, or fix. |
| 2026-11-01 | **Owner rulings on the spec's open questions:** (1) our generated data replaces the original's missing `Register.lua` (original zip targets an older WoW); (2) multi-charge: verified absent from the original source → **build it new** (done as engine work, then display); (3) weapon-enchant timers: replacement exists — `C_Item.GetWeaponEnchantInfo` + `WEAPON_ENCHANT_CHANGED` (Forever catalog) — use it; (4) **do not fix or replicate the original's broken paths; build what we actually need.** Owner also asked: do a second UI pass on the timeline (found missing: per-cooldown colored segment fills, `Forte_Cooldown.lua:1403-1448`), test in uiforever (done), and work out the remaining findings. |
| 2026-11-01 | Owner asked about item proc lists per class: none existed. `items.jsonl` holds 1,155 item effects (238 on-use with cooldowns, 400 procs with buff + duration); procs are mostly class-agnostic and have no cast to predict from. Harvest dispatched (agent `ItemData`). |
| 2026-11-01 | **Owner decisions:** commit+push authorized (done, `7028927`, 1,063 files, pushed to `origin/main`); first real-client session cannot happen before the 11-04 launch; Spell Timer v1 = own-cast predictions accepted; in-client MCP tools adopted **after** launch; **item/trinket procs are required in Forever and in combat** — owner asked whether this is a generic problem for all addons. |
| 2026-11-01 | **Answer: yes, engine-wide.** The combat log is closed to addons: `docs/reference/wow-ui-sim-specs/forever-combat-event-namespace.md` requires that a fresh Forever environment expose **neither** `C_CombatLog.GetCurrentEventInfo` **nor** `CombatLogGetCurrentEventInfo`; `C_CombatLogSecure.*` is `Environment=SecureOnly`; `C_CombatLogInternal` is `internal-or-restricted`; `docs/api/.../wow-api-combat/references/RETAIL-12-0-CHANGES.md:160-180` says CLEU is unavailable to addons. No addon can parse "proc fired". Anything that works in combat uses **(a)** the game draws it (Blizzard aura containers accept secret values — `aura-container-options.md`, `aura-secret-display.md`), **(b)** the *spell* as a proxy for the buff (Shadowflare's stated method, from its CurseForge page — code not yet read), or **(c)** the game's own proc alert. Owner research (`researchwow.md`, an AI-chat summary — treat as leads, not evidence) names EverAuras, Musca-Auras, ForeverAuras, Power Auras, ClassicProcAuras. Vendored the simulator's behavioural specs (753 of 831 files, `docs/reference/wow-ui-sim-specs/`; other-client eras skipped). Dispatched `RefAuras`, `RefShadow`, `RefProc` to read the real addon code. **Open until they report: can tainted addon code hand an arbitrary proc to Blizzard's aura UI?** |
| 2026-11-01 | **Accepted `ItemData`** (re-run by manager): generator deterministic (`errors: 0`, regenerated file identical), 238 on-use / 405 procs (400 item + 5 enchant) / 79 consumables, tocs identical, loads in sim with 0 `Forte_*` errors. 517 passive buff-only effects deliberately not emitted. **Timeline pass 2 delivered** (segment fills, icon time text, spark tint); manager viewed `compare_timeline_v2.png`: gold segment fill reaches the first icon and fades after it. Gate re-run showed 30/31 with the failure in `Reconcile`'s unfinished `test_reconcile.lua` and a syntax error in `Options`' unfinished `Widgets.lua:224` — both workers still running. |
| 2026-11-01 | **Accepted `Reconcile`** (manager re-run: `31 tests, 31 passed`; engine 10 / reconcile 9 / timeline 12; 0 `Forte_*` errors): cast counters in `FX.db.diag.casts` + `/fx status` lines, `Engine:OnActiveEdge`, charge model (`DetectCharges`, `OnReadCharges`, `entry.charges`). Charge spells: a plain "ready" read never clears them (charge read owns the lifecycle) — the one behaviour change beyond additive fields. New seams `Compat.GetSpellCooldownInfo/GetSpellCharges`. **Display of charges is not built yet.** |
| 2026-11-01 | **`Options` NOT accepted as delivered.** Tests pass (22/22, tocs identical, 0 `Forte_*` errors) but the manager viewed `fx_options_general.png` / `fx_options_cooldown.png`: rows do not stack (labels overprint), tips text renders above the window, header bar detached, title not in a title strip, controls invisible; only the module-index grid is right. **Lesson: green tests ≠ looks right; a worker that cannot see images must assert geometry numerically.** Fix dispatched as `OptionsFix` with measured defects. Unwired settings (persist only): General `FrameAlpha/FrameScale/FrameSnap/AltTimeFormat/ShowTooltips/BarFont/BarTexture`; Cooldown `Enable/HideCombat/Width/Height/MaxTime/PowerScale/TimeTags/IgnoreShort/Color*/BarColor/BgColor/Spark/Scale/Alpha` — need public setters on `FX.Cooldown.Display` (Timeline-owned). |
| 2026-11-01 | **`RefAuras` result** (`docs/reference/addons/everauras-family.md`, 473 lines, read by manager; source not re-opened; "works in combat" = the addon authors' in-game claims dated 2026-09-18..24, not reproduced by us). **No addon can inject an arbitrary spell into a Blizzard aura container** — containers are unit-bound (`SetUnit`), the only `Add*` APIs are `AddAuraGroup/AddAuraSlot` (filters) and `C_UnitAuras.AddAuraSound`; spell-ID filters are dead in combat, so Musca/EverAuras fall back to category/property filtering ("Game Categories", `IsAuraFilteredOutByInstanceID`, `nameless` mode). Musca-Auras (5.22.0) and EverAuras (0.9.9-beta) use game aura containers; ForeverAuras has no in-combat support (its README says so). **Transferable to our own bar:** (1) `StatusBar:SetTimerDuration(durationObject)` ticks on addon-owned frames while only an opaque duration object is held; (2) anchoring our icon to the status-bar fill edge = our power-axis slide; (3) `C_UnitAuras.AddAuraSound(trigger,{unit,spellID,sound...})` = a zero-read audible proc alert; (4) `C_Spell.GetSpellCooldown*` `isActive/isEnabled` as a proxy. **Therefore for item procs with no cast (internal-cooldown procs) a timeline bar position cannot be driven by us in combat; on-use trinkets/potions CAN (cast event → predict). Procs get: audible cue via `AddAuraSound` + optional game-drawn icon, not a bar position.** Unproven (needs the live client 11-04): whether `SetTimerDuration` accepts a duration object *we* construct (`C_DurationUtil.CreateDuration`). |
| 2026-11-01 | **`RefShadow` result** (`docs/reference/addons/shadowflare.md`, 529 lines, 133 `file:line` citations from the real 0.23.25 zip, interface 16001; **no licence → pattern reference only, never copy code**; manager read the summary, not the source). Shadowflare is composite, chosen per proc by one `mode` field (`Core.lua:63-368`): **14 procs "blind"** → Blizzard aura container (`AuraContainer` + `CustomAuraContainerTemplate`, `AddAuraSlot`, `SetApplicationBar/Count`, `SetDurationCooldown/Text`); **20 spell-proxy** (`castTime`, `cost`, `IsSpellUsable`, `GetSpellCooldown().isActive`); **2 native alert** (CVar `displaySpellActivationOverlays`, `SPELL_ACTIVATION_OVERLAY_*`). Proxy verdict: **boolean only** — no start/end time, stacks only where cost/cast-time slope is linear, bar durations hardcoded. Lead: EllesmereUI reads the engine-written `SetDurationText` string back as the only route to real in-combat times — **probe on the live client 11-04** (the sim has none of these APIs). |
| 2026-11-01 | **`RefProc` result** (`docs/reference/addons/powerauras-classicprocauras.md`, from real zips; source not re-read by manager). Neither addon uses a secure snippet/channel (no `C_AddOnMessages`/`SecureHandler`/`RunForPlayer` anywhere, none in the 16001 surface). Spell IDs enter as **plain data** via `AddAuraSlot(name,"HELPFUL",{candidateFilters={includeSpellIDs={[id]=true}}})`, built **out of combat** (`InCombatLockdown()` guards); Blizzard's untainted code matches/renders. Power Auras reads only its own clock from a hidden 1×1 "gate" slot's `OnUpdate` (present ⇔ stamped <0.3 s ago). **Scouts' verdicts conflict on the surface:** RefAuras: spell-ID filters are dead in combat (Musca preview text; "Blizzard does not let addons pick *debuffs on yourself* by spell"); RefProc: buff procs work via `includeSpellIDs`. Reconciled as: **debuffs refused, beneficial self-buffs claimed to work, item-source IDs never exercised by anyone → UNPROVEN until the 11-04 live probe.** Design + probe list: `docs/design-combat-procs.md`. |
| 2026-11-01 | **`OptionsFix` reviewed:** both gates re-run (`29/29`, `31/31`, 0 `Forte_*` errors); manager viewed the new screenshots: layout now correct (rows stack, title strip, header bar, controls, grid) but **not pristine**: labels/tips centred (original left-aligns), STR rows overprint label with value, section titles lack navy bars, recycle icons not visible, unchecked boxes indistinct. `OptionsPolish` dispatched with numeric acceptance. Commit `860bf39` pushed (state before polish). |
| 2026-11-01 | **Options window accepted** after three review/fix rounds (`OptionsFix`, `OptionsPolish`, `OptionsHeader`); manager re-ran both gates each time and viewed every screenshot. Final: `Forte_Options 37/37`, `Forte_Cooldown 31/31`, 0 `Forte_*` errors, tocs identical; General + Cooldown pages match the original's structure (left-aligned gold labels, navy section bars, reset icons, header alpha/scale, scroll thumb, module index). Root causes worth remembering: y-sign convention (anchors are y-up), nil `C.CTRL_H`/`spec.width` (zero-size controls), per-column cursor reset, a nil-global anchor target (`recycle` vs `recycleBtn`). **Still to do on this window:** (1) wire the unwired settings through public setters on `FX.Cooldown.Display` (Timeline-owned); (2) remaining module pages (disabled with tooltip until built); (3) real-client check — close-X/tab atlas glyphs measure 0×0 in the sim and are unverified. **Next build queue (unchanged order, §10.4 C):** item/potion/trinket cooldowns on the timeline; charge display on icons; weapon-enchant timers; Hunter tools; Spell Timer; options wiring. **Launch-day probes: `docs/design-combat-procs.md` §5.** |
| 2026-11-01 | **Full review round (owner left the session unattended: "review everything, verify, research, plan, iterate").** Gate script `scripts/gate.py` added (all sim tests + live-globals load probe + toc pairs + syntax + generator determinism; ignores the `Regenerated:` stamp and leaves no churn): PASS. uiforever battery T2–T13 run and recorded in §10.4 (all pass or explained). Found + fixed by manager: timeline index-binding re-splash (via `TimelineFix`, 5 regression tests proven to fail on old code), `PlainOrNil` comparing `v == nil` before `issecretvalue`, raw `spellID ~= nil` + info-table truth test outside the pcall in `RecordCastEvent`, `GetServerName` (absent on Forever) → `GetRealmName`. |
| 2026-11-01 | **Code review (`CodeReview`, `docs/review/2026-11-01-code-review.md`) verified by manager before acting.** REFUTED: **B1** "separate per-addon Lua states" — the installed real Forever addon `EllesmereUIForeverFix` (Interface 16001) writes another addon's global at file load (`EllesmereUI.FOREVER_SV_BUG = false`, relying on `## Dependencies` order): globals are shared, our multi-addon layout is sound; **B2/M1** `GetPoint` destructuring — `Region:GetPoint()` returns `point, relativeTo, relativePoint, x, y`, our `point, _, relPoint` is correct, and uiforever ran drag→reload→reset and options close→reopen error-free. CONFIRMED: **M2** item rescan deleted every live item entry on any bag event (real, major), **M3** raw `spellID == nil` in Hunter tools, **M4** `IsPlayerSpell` absent from the catalog (silent 0 tracked risk; fallbacks `C_SpellBook.IsSpellKnownOrInSpellBook/IsSpellKnown` are documented), m1–m6, m8. Fixes dispatched to `FixCore`, `FixItems`, `FixUI` (FixUI also wires the options to the bar = T9). |
| 2026-11-01 | **SavedVariables on Forever:** the beta had a broken SavedVariables *loader* (files written, not restored) — worked around by the third-party ForeverSVFix, whose README now says *"Blizzard have fixed the issue"*. Our code already degrades to session-local storage if `FX.db` is absent; persistence across relog is now a launch-day probe. **Deploy hazard found:** ForeverSVFix edits addon `.toc` files and links data dirs into addon folders, and the installed client already carries its patches (`EllesmereUIForeverFix.toc:11-15`). With `deploy.sh`'s symlinks it would write into this git working tree and break toc twin identity → `deploy.sh --copy` mode + warning (FixCore). Owner: uninstall ForeverSVFix if no longer needed. |
| 2026-11-02 | **Polish pass (agent `Polish`), four owner-listed items.** (1) The options module index carries a 16th cell, **Hunter Tools** (`id="Hunter"`, the page header's `C.BROWN`), and the enable rule is generalised into `FX.Options:RefreshIndexCells()`: a cell is enabled exactly while a page of its id is registered, refreshed from `RegisterPage` — the old build-time snapshot could never light a page that registers at `PLAYER_LOGIN`, which is exactly how `Forte_Hunter` registers. 16 cells fill the 4x4 grid. (2) **Icon fade-in law corrected:** `TimelineSkin.FadeSeconds` 0.3 → **1.0** — the source starts a fresh bar's visibility at 0 (`Forte_Cooldown.lua:625`; the no-focus init at `:598` starts at 1) and advances it by the elapsed seconds (`:611`, clamped `:612-614`) = a 1.0 s ramp the frame alpha rides (`:1402`). The cross-fade midpoint test now asserts the alphas sum to the shared fade factor (it read 1.0 only because the invented 0.3 fade had finished). (3) **Hunter swing fill default** = the Cooldown timeline's `Colors.Spell` at full alpha (read from `FX.Cooldown.TimelineSkin` at `Init`, the verbatim triple as the `OptionalDeps` fallback) — the 1,1,1 a 0.20 wash was invisible; the store default reads `FX.Hunter.SwingSkin.BarColor`, so page and skin cannot drift; the background default is untouched. (4) `General.BarFont` now drives the swing text (`KEYMAP.BarFont -> SetFont`, pulled at login, mirroring the Display's seam). Each of the four got a test proven to fail on the pre-change code (temporary reverts: 2 + 2 + 2 failures, restored green). Gate: see the run below. |
| 2026-11-02 | **Iteration B accepted** (`4997ecf`): `/fx probe` kit + `docs/launch-day.md`; in-combat read tiers (NeverSecret `isActive/isOnGCD` early-ready, plain duration-object exact anchor, `FX.SecretState`); Hunter swing bar + aspect reminder + Hunter page; splash/pulse law from source (linear 0→4×, alpha 1→0, 1.0 s). Manager added `scripts/api_lint.py` (every `C_*`, `Enum.*`, registered event must exist in the pinned catalog; in the gate) after a worker summary named APIs that turned out not to be in its code — the lint found the code clean. Verified on uiforever: T9 settings drive the bar live, `/fx probe` runs all groups, Hunter UI frames behave (§10.4 T9/T14/T15). |
| 2026-11-02 | **Iteration C accepted** (`0d7c2d5`). `Enchants` (weapon-enchant timers, `C_Item.GetWeaponEnchantInfo` `timeLeft` in ms per `BuffFrame.lua:774-777`, category Buff), `WarlockTools` (shards bag-first/power-second with source label, soulstone/healthstone/ritual trackers, `docs/warlock-tools.md`), `Polish` (Hunter Tools index cell, fade-in 1.0 s from source, visible swing default colour, BarFont reaches the swing text), `SpellTimerDesign` (`docs/design-spell-timer.md`: v1 rows all predicted — `UNIT_SPELLCAST_SENT` target is ConditionalSecret; geometry 250×14 with icon outside; reconcile law ported). **Severe bug found by `WarlockTools` in Hunter code and fixed by manager:** both Hunter `OnEvent` bindings were `function(...) handler(obj, ...)`, forwarding the frame as `event` — no Hunter event (aspect casts, `PLAYER_SWING`) would ever have been handled in game while every test passed (tests only checked the script existed). Fixed to `function(_, event, ...)`; 2 regression tests drive the real frame scripts and were proven to fail on the old binding (34/36); api-lint now rejects vararg `OnEvent` bindings. Gate PASS: 222 tests (Cooldown 108, Core 13, Hunter 36, Options 44, Warlock 21). |
| 2026-11-02 | **Timer polish pass (agent `TimerPolish`).** (1) The white rows were a two-part defect: `Laws.COLOR_KEY.Crowds` pointed at `"Crowd"`, a key the skin does not have (the skin spells the band `Crowds`), so every crowd-control row fell back to the orange `Default`; and the `/fx timer test` feed stamped its seeds in the FUTURE (`now + (i-1)*0.05`), which makes the arrival-highlight law's `(total - remaining) < 0.5` true with a negative mix factor — clamped, that pinned every seeded row to pure `HighlightColor`. The key now reads `"Crowds"`, the feed stamps the PAST (`now - (0.75 + (i-1))`, one row per distinct kind so the debug view is a palette check), and the flash law is bounded to `elapsed >= 0 and elapsed < 0.5`. (2) The panel's first-run placement moved into `Module.DEFAULT_POSITION` (CENTER/CENTER **261,-150**, the same height as the Cooldown bar, a column beside it: the bar spans x[-125,125], the panel is 256 wide, so the rectangles can not meet at any stack height; `/tmp/fxref` centres both panels, so the reference gives no separation to copy). (3) `Core/Registry.lua`'s `KIND_RULES` were regex strings — `Stun$|^Charm`, `Sting$|Mark$|^Wound` — and `|` is literal in a Lua pattern while an interior `$` is literal too, so **no rule with an alternation ever matched**: the measured coverage of the generated data was 366 of 366 spells on `Default`. The table is now ordered term bands (Curse, Bane, Pet, Crowds, Heal, Channel, Cooldown, SelfDebuff, Buff, TargetDebuff, SelfBuff) with a term grammar of plain substring / `^prefix` / `suffix$` / exact, and the coverage measured in the simulator is **530 tracked, 0 Default** (Hunter 0/73, Warlock 0/76, Mage 0/51, Priest 0/47, Druid 0/52, Rogue 0/50, Warrior 0/64, Shaman 0/61, Paladin 0/56). Spell ids are still never read. (4) Tests: 34 → **44**; new `tests/test_kinds.lua` censuses the generated data through the registry's own `DataFor` seam and asserts zero `Default`, the drawn-fill test seeds through the public `/fx timer test` feed and asserts each shown bar's `GetStatusBarColor` and its texture's vertex colour equal the skin colour of the row's kind, and the geometry test fails if the panel and the Cooldown bar's rectangles intersect. Full gate PASS. |
| 2026-11-02 | **Live finding on uiforever after Iteration C:** the Hunter swing bar never appeared in a client even with the event fix — its 10 Hz `OnUpdate` lived on its own *hidden* anchor, and hidden frames get no `OnUpdate`; sim tests passed because they called `Update(now)` directly. Fixed (`36899c6`): `StartTicking` renders once synchronously; regression test drives the kick path and asserts `IsShown()` without calling `Update` (proven to fail with the render removed). Re-verified live: mid-swing bar shown, fill 70.75 px at progress 0.379, no Lua errors. Rule broadcast to `SpellTimer`/`WarlockUI` (both adopted an always-shown driver frame). **Lesson: UI tests must start activity through the public event/kick path and assert visibility, never call the render function themselves.** |
| 2026-11-02 | **Iteration D accepted** (`a6c3d34`…`4b16d27`): Forte_Timer v1 (Spell Timer, own-cast predicted rows, the original's reconcile law) + `TimerPolish` (root causes of white rows: **every kind rule was dead because Lua patterns have no `|` alternation**, a `Crowd`/`Crowds` key typo, and the test feed stamping future casts = permanent arrival flash; now 0/530 spells fall to Default) + `TimerLayout` (group headers in their own gap); Warlock UI v1 + `WarlockPolish` (the original's purple labelled plates, constants traced to the original XML/Lua); review 2 fixes (end-of-cooldown pulse never fired live — fixed in the release path; pulse pool reuse; `PlainOrNil` fails closed; per-slot enchant entries; Hunter page header lock; no per-tick group-signature churn). Remaining original textures vendored. api_lint now also rejects `|` alternation in pattern literals. Gate PASS: 293 tests (Cooldown 113, Core 16, Hunter 37, Options 45, Timer 45, Warlock 37). Live on uiforever: 14/14 active, `/fx timer test` renders coloured rows in two target groups beside the cooldown bar, no Lua errors (`docs/media/sim/uif_timer_live_2026-11-02.png`). Worker-made captures were wrong twice (an empty scene; a capture whose recipe "didn't run") — the manager's own standard-recipe captures are the reference. |
| 2026-11-02 | **Load-on-demand class data (agent `LoadOnDemand`); Iteration C item shipped.** The nine `Forte_<Class>` add-ons carry `## LoadOnDemand: 1` in both toc twins (verified: the client metadata gate accepts the header; a LoD add-on reports `C_AddOns.IsAddOnLoadOnDemand`=true, `IsAddOnLoaded`=false, `IsAddOnLoadable`=true in the sim, and its Lua is NOT parsed at startup). `Forte_Core/Core/Loader.lua` (new, in both Core tocs) maps a `UnitClass` token to `Forte_<TitleCase(Token)>` -- `DEATHKNIGHT` maps to no add-on, which is not an error -- and loads the player's at `PLAYER_LOGIN` **before** the module enable loop, so a class module registers inside the loop and is enabled in registration order by the loop it already joined. `FX.RegisterModule` gained the other half: after the login loop a late registration is enabled at once, exactly once, in registration order (`FX._enabledModules` ledger; a module that raises is counted enabled and reported, the login order does not shift). `FX.RefreshPlayerClass` loads the new class's add-on from the `PLAYER_ENTERING_WORLD` / `GROUP_ROSTER_UPDATED` path; `C_AddOns.LoadAddOn` is idempotent, so a mid-session class change costs nothing to re-request. `Forte_Items` stays always-loaded (every class's item/enchant tables read it); `Forte_Core`/`Forte_Cooldown`/`Forte_Timer`/`Forte_Options` are the shared spine. A failed/disabled load prints ONE notice (`name did not load (<reason>) -- its class tools stay off`) and the session continues: the login loop has no dependency on the load. Measured in the sim: a Paladin session carries 7.9 KB of the 385 KB of class Lua (97% not parsed); the gate's load probe now runs per profile class (default/Hunter/Warlock) and asserts `Forte_Items` present, exactly that profile's data, exactly ONE class add-on loaded, and the profile's modules present (`Paladin` -- data, no modules). **Two things the split made visible:** (1) `run-tests <addon>` does NOT run a load-on-demand add-on's own files, so a suite that audits a class's data now declares it: `test_00_class_data.lua` (Forte_Cooldown / Forte_Timer / Forte_Options / Forte_Hunter / Forte_Warlock) calls `FX.LoadClassAddOn`, the product's own entry point, not a fake. Passing `--class` to the suites was tried and rejected: it moves `FX._playerClass`, which the class-gate tests assert is NOT the class they audit. (2) `Forte_Hunter/tests/test_swing.lua` and `Forte_Warlock/tests/test_warlock.lua`/`test_warlock_ui.lua` hard-assumed "the sim profile is not my class"; as `--class Hunter`/`--class Warlock` runs those assumptions invert (events live at login), and the assertions now read `FX._playerClass` -- the same law, from the side the always-loaded world could not reach. Baselines: Forte_Core 16 -> 28, Forte_Hunter 37 -> 38, Forte_Warlock 37 -> 38, Forte_Options 45 -> 46, Forte_Timer 45 -> 46, Forte_Cooldown 113 -> 114. **Open, not mine to call:** `docs/reference/wow-ui-sim-specs/addon-lod-metadata.md` -- a LoD add-on's SavedVariables arrive WITH the load in the real client; the sim only ever restores the always-loaded set, so a class's saved settings under LoD is a launch-day probe (`--savedvariables`), not a sim fact. |
| 2026-11-02 | **LoD + review 3 accepted** (`9220b85`, `8da8874`). **Live finding (uiforever): `Forte_Cooldown` still listed `Forte_Hunter, Forte_Warlock` as OptionalDeps, which made the client load both for every character** (Warlock frames' code resident on a Hunter); wow-ui-sim does not load LoD optional deps, so its probe said "1 class addon". Fixed, and `gate.py` statically rejects an always-loaded addon depending on a LoD one (proven: fires on the old toc, passes on the fix). Re-verified live: Hunter → only `Forte_Hunter` resident (+ `Forte_Mage` from the site's log-in-as-Mage artifact); class switch to Rogue → only `Forte_Rogue`, 10 tracked, no Lua errors. Review 3 (5 majors, verified against the original source): Spell Timer removal polarity was inverted (`Forte_Timer.lua:1207` — consumed auras rode as phantom rows), a shadowing `CheckableAt` overrode the `:1186` law, the reconcile combat gate called a nonexistent global, 11 settings had no consumer (now wired or honestly labelled, census-tested), per-page header lock. A worker's "byte-identical restore" reinstated a discarded early return that dropped every nil-icon pulse; the integrated gate caught it and the manager fixed it. Gate PASS: 321 tests. Iteration E dispatched: Secondary Splash, Cooldown extras (Warn, right-click, Vertical/Flip/HideZero), Messages + Sound + Party/Raid (legality-gated) on a Core event bus. |
| 2026-11-02 | **Owner: remove the Death Knight module** (no DK class in WoW Forever) — done `0f126e9`: `Forte_Deathknight` placeholder, its spell list and the generator's family entry deleted; the loader still treats an unknown class token as "no add-on" (tests keep `DEATHKNIGHT` as that negative case). |
| 2026-11-02 | **Iteration E accepted** (`a156812`). Three original modules that were still missing. **Secondary Splash** (CD-27/28): the functional-spec row CD-27 was WRONG (it described a linear shrink scaled by cooldown length); the source `Draw` (`Forte_Cooldown.lua:1017-1050`) is a bell over the shared 1.0 s end window — `s1 = 1-4(0.5-t14)^2`, size `32*(scale+(SSM-scale)*s1)` (64→128→64), alpha `s1*alpha` on the icon inside an `alpha` frame (peak 0.49), unlocked-idle placeholder. The manager caught the divergence in the worker's own note and had it rebuilt to the source (`SplashLaw`). **Cooldown extras** (CD-30/31/35): Warn on own `UNIT_SPELLCAST_FAILED` (flash + focus steal), right-click opens the Cooldown page (drag-guarded; a plain Frame rejects `OnClick` in this build — `OnMouseUp`), Vertical/Flip/HideZero. **Forte_Messages** (new, always-loaded): Core event bus (`FX.On/Off/Fire`, pcall-isolated); self messages to the default chat frame (the original's `FW:Show`); sounds; party/raid announce gated on `FX.SecretState.chat` / `C_ChatInfo.InChatMessagingLockdown` / `AreOutgoingAddonChatMessagesRestricted`, locked sends skipped and counted. **Manager correction:** the first cut played a bell + chat line on EVERY Spell Timer row expiry; the original (`Forte_Timer.lua:1049-1056`, `:1590-1603`) warns only for `RegisterOnTimerFade` spells (Polymorph, Sap, Fear, Banish, Enslave Demon, Seduction/Mesmerize), N seconds before the end (N parsed from the message text, 3 s), once per row, plus `*Break` rows on early removal — rebuilt with verbatim texts and the source's bits (Banish/Enslave/Seduce fade+break to party ON, the rest off); bare expiry now has no default sound/message. Known delta: the source skips Break when the target is dead (`:1208 UnitIsDead`); our rows have no liveness reader yet (agent `Cleanup` adding a fail-open target check). Gate PASS **380 tests** (Cooldown 136, Core 37, Hunter 38, Messages 28, Options 49, Timer 53, Warlock 39). Live on uiforever: 15/15 active, no Lua errors, Rogue session loads only Forte_Rogue (+ the site's Mage artifact), modules `Probe,Splash,Cooldown,Timer,Messages`, splash shown and bus delivered once through the public path. Iteration F dispatched: review 4 of this code + cleanup backlog. |



---

## 10. Stage runbook — manager handoff (written 2026-11-01 ~19:00, for a cheaper model to continue)

You are the **manager** of this project: you plan, delegate to basalt workers, verify, integrate, and report to the
owner (Gevil). You do not need to be clever; you need to be **rigorous**. Read §10.2 before doing anything.

### 10.1 Where we are
- **Done and verified** (see §6): spell data for 9 classes (530 spells, 0 gaps), generator hardened, Classic timeline bar
  v1 (`UI/Timeline.lua`, 20/20 sim tests), functional spec of the original (`docs/reference-functional-spec.md`),
  API references (`docs/api/`), media corpus (`docs/media/`), GPL-3.0 `LICENSE`, URW Gothic font, deploy script.
- **Tested on uiforever.com** (§5 table): addons load, no Lua errors, no missing APIs, `/fx status` works, bar renders.
- **Nothing is committed** since `cd06b3b`; **nothing has run in the real client**. Do not commit/push until the owner says so.
- **Four workers are running on basalt right now** (read `proc://` for live state; results arrive as notices):

| Agent | Owns (files) | Doing | Done when |
|---|---|---|---|
| `Timeline` | `Forte_Cooldown/UI/*`, `tests/test_timeline.lua`, `tests/test_engine.lua`, `docs/media/sim/fx_timeline_v2_*`, `compare_timeline_v2.png` | UI pass 2: **per-cooldown coloured segment fills** (`Forte_Cooldown.lua:1403-1448` of the original), thin icon border (no permanent glow), icon time text, chrome | gate green + side-by-side image + dump-tree segment extents reported |
| `Reconcile` | `Forte_Cooldown/Core/Engine.lua`, `Module.lua`, NEW `tests/test_reconcile.lua` | (A) cast-secrecy counter in `/fx status`; (B) `isActive`-edge fallback (`Engine:OnActiveEdge`, entry `source='edge'`); (C) multi-charge engine model (`entry.charges`, `rechargeEnd`) — data only | gate green incl. its new tests; API list reported |
| `ItemData` | NEW `tools/gen_item_data.py`, NEW `addon/Forte_Items/` (+ both tocs), `docs/item-procs.md` | on-use / proc / consumable lists from `items.jsonl` keyed by NAME | counts + loads in sim with 0 `Forte_*` errors |
| `Options` | NEW `addon/Forte_Options/` (+ both tocs), one additive edit to `Forte_Core/Core/Init.lua` (`FX.RegisterSlash`) | the original-style options window: framework + General / Cooldown / About pages | `run-tests Forte_Options` green + `fx_options_*.png` |

### 10.2 Standing rules (non-negotiable)
1. **Re-run every gate yourself.** Never relay a worker's test numbers. (Learned 2026-11-01: a worker said 20/20, the re-run was 19/20.)
2. **Gate command** (sim = the only API proof; luajit stubs prove syntax only):
   `cd /tmp && $WORK/wow-ui-sim/run.sh wow-sim --allow-ui-version-mismatch --addons-path $REPO/addon run-tests Forte_Cooldown` (swap the addon name for `Forte_Options`, etc.).
   The shell blocks `grep`/redirection, and the output is huge Blizzard noise. Read the result with Python: `subprocess.run([...], capture_output=True, errors="replace")`, strip ANSI (`re.sub(r"\x1b\[[0-9;]*m","",out)`), then regex `\d+ tests?, \d+ passed, \d+ failed`, list lines containing `✗`, and `Forte_\w+/[^ ]*:\d+:` for our errors. **Exit code 0 and no `✗` = green.**
   Only `Forte_*` errors count; Blizzard-side noise (Transmog `SMART_NAV_INPUT_DIRECTION`, Gamepad*, `PromptedBinding`, `LootHistory`, `GroupLootFrame`, `IsPetOrderMoveToPending`) is baseline.
3. **Look at every screenshot a worker produces** with `read <png>` if your model can see images. **If it cannot, say so to the owner** and rely on `dump-tree` numbers — never claim a visual match you did not see. Visual acceptance = side-by-side image vs `docs/refs/` (original) — see `compare_timeline_v2.png`.
4. **One owner per file.** The table in §10.1 is the lock list. Before dispatching anything new, check it; if a task needs a file another agent owns, wait or `write agent://<name>`.
5. **Basalt agents only** for workers (`fx-worker` implement, `fx-scout` read-only research; both pinned to `basalt/qwen3.8-flash-next-nvfp4-basalt` in their own frontmatter). The owner may change the main model; workers stay on basalt.
6. **No git writes** until the owner authorizes. No deploy to the real client until the owner asks (`scripts/deploy.sh` is ready).
7. **Do not fix or replicate the original ForteXorcist's broken code** (owner ruling §9). Build what we actually need, driven by `reference-functional-spec.md` verdicts.
8. **Never use hard-coded spell IDs at runtime** — resolve by NAME (IDs drift per build, §8).
9. **Log every owner decision and every correction** in §9 the moment it happens; update §6 state rows after each accepted worker. Keep the todo list current (one `in_progress`).
10. **Edit-tool discipline:** after every `edit`, use the returned tag; to touch lines you never displayed, `read` them first. Never overwrite a whole config file with `write` without reading it (a `.gitignore` overwrite already cost 4 rules).

### 10.3 Recipes
**uiforever.com test loop** (managed Chromium, never the owner's Chrome):
1. Zip the addons without tests/otf: `cd addon && zip -r -q /tmp/fx_uif.zip Forte_* -x '*/tests/*' '*.otf'` (re-zip after every code change).
2. `browser.open({name:"uif", url:"https://uiforever.com/app?flavor=forever", app:{relay:false,tern:false}, viewport:{width:1600,height:900}})`; wait ~8 s for the 3D scene.
3. Upload: the ZIP input is the 5th file input (`accept=".zip"`, inside "Drop addons here"): tag it with `data-fxzip` via `tab.evaluate`, then `tab.uploadFile('input[data-fxzip="1"]','/tmp/fx_uif.zip')`. A dialog lists the addons: click the button whose text is `Import`. Replacing already-imported addons: remove the old ones (✕ per addon) or reset first.
4. `Later` closes the rename prompt; `Let's go` closes the tips; then click `/reload` (the header button) and wait ~15 s.
5. Bottom tabs: `Errors` (must say "No Lua errors."), `Missing APIs`, `Lua Console`. Console input = `input[placeholder="print(UnitName('player'))"]`; `tab.fill(sel, cmd)` then `tab.press("Enter",{selector: sel})`. Slash commands work (`/fx status`); `=expr` prints a value. Read chat back with `ChatFrame1:GetNumMessages()` / `ChatFrame1:GetMessageInfo(i)` and `print`. Console output is DOM text (`document.body.innerText`).
6. Class picker: header button "<race> · <class>" opens a popover; set the `<select>` whose options include `Hunter` (Warrior, Hunter, Rogue, Mage, Druid are the only classes offered), dispatch `change`, click `Apply`, wait ~15 s. Scenarios: `Solo`/`Dungeon`/`Raid` buttons; `No combat` toggles combat state; `Target`/`ToT`/`Focus`. Resolution select: 1920×1080 … 5120×1440; `Fit`, `100 %`, UI-scale field.
7. The game canvas is a `<canvas>` (about 1300×577 CSS px at x=300,y=79); `tab.screenshot({format:"png"})` saves at 1.25× scale — crop the bar with ffmpeg (`crop=700:240:837:470,scale=2100:-1:flags=lanczos` found it at default scale). Save captures into `docs/media/sim/uif_*.png`.
8. **Gotcha:** the simulated player has no real cooldown state, so our own reconcile (plain read says "ready") clears predicted timers within ~2 s. To inspect the display, first run in the console `ForteXorcist.Cooldown.Engine.OnRead=function() end`, then start entries: `local E=ForteXorcist.Cooldown.Engine; E:AttachStorage({}); E:Build("HUNTER",function() return true end); ... E:OnCast(name, GetTime()-offset)` choosing names whose `E.tracked[name].baseDuration >= offset+15`.

**Sim screenshot** (headless, for worker comparisons): `... run.sh wow-sim --allow-ui-version-mismatch --addons-path <addon dir> --class Hunter --delay 3500 --exec-lua '<inline lua only>' screenshot --png -o <out.png> --width 1280 --height 1024`. `--exec-lua @file` is silently ignored; `print`/`io` are swallowed — create named frames and read them with `dump-tree`. The sim world is black; add a warm backdrop frame in the scenario only when comparing against the originals.

### 10.4 Work queue (in order; each item = dispatch → verify → record)
**A. Receive and verify the four running workers** (per-item checks in §10.5). Then update §6, §9.
**B. uiforever test battery** (owner request: "test all functionality, UI pristine, options screens, behaviour"). Run after A so it tests the new build. Record pass/fail per row in a table in this section.
| # | Test | Expect | Status |
|---|---|---|---|
| T1 | `/fx`, `/fx status` | version line + `Cooldown: N tracked` (+ casts counter line after `Reconcile`) | **PASS** 2026-11-01 (`class=HUNTER | Forever=true | modules=1`, `Cooldown: 18 tracked, 0 active`) |
| T2 | `/fx unlock` → drag bar → `/fx lock` → `/reload` | bar moves, position persists | **PASS** 11-01 (real canvas mouse drag: centre y 570→839.5; lock disables mouse; position + lock survive `/reload`) |
| T3 | `/fx reset` | bar returns to default anchor | **PASS** 11-01 (`CENTER 0,-150`) |
| T4 | each class (Warrior, Hunter, Rogue, Mage, Druid): tracked count in `/fx status` | matches data counts for names the sim player "knows" (isKnown) | **PASS** 11-01 (tracked 21/18/10/6/11, items 4-5, captured class = UnitClass). Artifact seen once: after an addon re-import + reload the site reported `class=MAGE` at PLAYER_LOGIN while UnitClass later said HUNTER — class captured once at login (`Init.lua:88`); harmless on a real client, hardening queued |
| T5 | resolutions 1920×1080, 2560×1440, 3440×1440, 4K and UI scales 0.64 / 1.0 | bar legible, not clipped, position sane | **PASS** 11-01 (centre x = UI width/2 at every resolution; eff. scale 0.71/0.64/0.64/0.53; visible) |
| T6 | Solo / Dungeon / Raid scenarios + `No combat` toggle | no Lua errors; bar survives scenario reload | **PASS** 11-01 (group/raid flags correct, bar visible, `InCombatLockdown()` true when toggled; in-combat cast counted in the in-combat split) |
| T7 | in-combat behaviour: patch the cast/read seams (`PlainOrNil`→secret) and watch counter + `isActive` fallback | counter shows secret>0; edge entries appear | **PASS (counter)** 11-01 (`secretId` 0→1). Edge fallback not observable on the site (its cooldown reads are always "ready"); covered by sim tests. Found + fixed: `PlainOrNil` compared `v == nil` before `issecretvalue`; `RecordCastEvent` compared the raw payload `spellID ~= nil` and truth-tested/indexed the info table outside the pcall |
| T8 | options window: open via `/fx options`; every widget (CHK/NUM/SLD/COL/STR), reset icons, section collapse, module index (dimmed unbuilt pages), ESC close, drag, position memory | all behave; matches `docs/refs/options-panel.png` | **PASS (core)** 11-01: opens/toggles via `/fx options` and `/fx config`, ESC closes it (game menu not opened), Global Frame Lock checkbox toggles the bar's mouse + saved lock both ways, works **in combat**. Found + fixed: title used `GetServerName` (not in the Forever catalog; site flagged it Missing) → `GetRealmName`. Not yet exercised on the site: NUM/SLD/COL edits, section collapse, window drag memory |
| T9 | options → Cooldown page changes (width/height/Max/Loga/colours) apply live | bar updates; list unwired keys | **PASS** 11-02 on uiforever (build `4997ecf`): `FX.Settings:Set` Width/Height/Scale/Alpha → anchor 250×24@1/1 → 320×30@1.2/0.8; IgnoreShort 10 → `Engine.MIN_COOLDOWN` 10; Enable false/true hides/shows; per-key Reset restores 250×24@1/1 and 2.99. Unwired by design: FrameSnap, ShowTooltips ("not used yet") |
| T10 | Edit Mode + Game Menu + other Blizzard windows with FX loaded | no taint/Lua errors | **PASS (Edit Mode)** 11-01 (ShowUIPanel/HideUIPanel EditModeManagerFrame clean, bar still visible); game-menu ESC inconclusive on the site |
| T11 | memory/time: Developer tab | FX load time and memory reasonable (report numbers) | **PASS** 11-01: all addons 1.5 MB sim (≈1.6 MB game est.). Items 687 KB, Options 269 KB, Cooldown 186 KB, Hunter 82 KB, each class 30-43 KB (all 9 load for every class — LoadOnDemand candidate), load ≤5 ms each, 0 errors |
| T12 | items/trinkets row on the bar (after item polling is built) | on-use trinket cooldown appears | **PARTIAL** 11-01: 4 items tracked live (Talisman of Ephemeral Power + 3 mana potions), `C_Item.GetItemSpell` present on the site and cast-spell map built (`ephemeral power`, `restore mana`); visual row on the bar not yet captured on the site |
| T13 | real cast payloads end to end (site does not simulate casting; drive the module's own OnEvent frame found via EnumerateFrames with a real `UNIT_SPELLCAST_SUCCEEDED` payload) | counters, name resolution, predicted entries, bar render | **PASS** 11-01: 4/4 plain, 4/4 resolved, entries Rapid Fire 300 s, Feign Death 30 s, Aimed/Multi 6 s; bar renders on the site's live clock (`docs/media/sim/uif_live_bar_2026-11-01.png`). Splash frames expire (alpha→0, hidden) — the stuck splashes in `fx_timeline_v3_*.png` came from the worker's frozen-clock scenario; the index-binding rebind is still real (slot 1 rebinds to whichever entry sorts first) and is being fixed by `TimelineFix` |
| T14 | `/fx probe` on uiforever (build `4997ecf`) | every group produces plain classified values, no Lua errors | **PASS** 11-02: SEC (restriction states 0–5), CD ×3 Hunter spells (duration object `secret=false`), ITEM (trinkets/potion), AURA ×8 aspects, CAST census (14 seen/1 secret, persisted), SWING, GATE (AuraContainer loads), PRES (AddAuraSound, CreateDuration, item globals present), EPOCH; "No Lua errors." — site values are simulator values, NOT client evidence |
| T15 | Hunter UI on uiforever | swing bar idle-hidden, aspect reminder pulses out of combat, Hunter page opens | **PASS** 11-02 (`ForteXorcistHunterSwingAnchor` hidden at idle, 200 wide; reminder shown, alpha pulsing; `Options:Open("Hunter")` shown) |
**C. Follow-up builds, in this order** (each needs a worker task with the standard gate + screenshots):
1. **Segments + icon polish accepted** (from `Timeline`) → then **item/potion/trinket cooldowns on the timeline**: Module polls equipped trinkets (slots 13/14) and bag consumables using `Forte_Items` data by NAME; category colours Item/Potion/Healthstone; item cooldown reads are not marked secret at the 70532 pin (§8) — probe first. Owners: `Timeline` (UI) + `Reconcile` (Module) → run sequentially, not in parallel.
2. **Multi-charge display**: show `current/max` on the icon (data from `Reconcile`'s `entry.charges`); charge spells stay on the bar while recharging.
3. **Weapon-enchant timers**: `C_Item.GetWeaponEnchantInfo` + `WEAPON_ENCHANT_CHANGED` (Forever catalog) → Enchant category colour.
4. **Hunter class tools** (`Forte_Hunter` gains code): aspect reminder (out of combat), trap timers (cast-predicted), auto-shot/swing timer — `PLAYER_SWING` payload is `(swingDuration, swingType)` with **duration first**; `PLAYER_SWING_RANGE_UPDATE` leads with `swingType`; two separate handlers (§8).
5. **Spell Timer** (`Forte_Timer`): revive `UI/Rows.lua` (dormant seed); port the original's reconcile rule (spec §3.4: uncertain prediction adopted by a later observation within `maxlag = 1.0 s`; longer → extend, shorter → refresh); own casts only, predicted rows marked as predicted.
6. **Warlock tools** (Soulstone/Healthstone/Shard/Summon) and per-class tools in the order Mage, Priest, Druid, Rogue, Warrior, Shaman, Paladin.
7. **Options expansion**: remaining module pages as their modules exist; profiles/clones last.
**D. First real-client session** (owner must run WoW; do not start until the owner asks): `scripts/deploy.sh`, log in as Hunter, `/fx status`, `/fx unlock`, drag, `/fx lock`, cast cooldowns in and out of combat, read the counter line (`casts seen | plain | secret | unresolved`) — this answers the biggest open risk (§8: is our own cast `spellID` plain in combat?). Also confirm the client loads exactly one of `X.toc`/`X_Camelot.toc` and that `ForteXorcistDB` survives a full restart.

### 10.5 What to verify when each worker reports
- **Timeline (pass 2):** gate green + count; `compare_timeline_v2.png` exists and, if you can see it, shows coloured segments left of/between icons like `docs/refs/ref6.png` and the enlarged original (`docs/media/frames/walk-000315-timeline-zoom.png`); no permanent glow ring; icon time text readable; report lists deltas fixed / not fixed. Ask the owner to eyeball it.
- **Reconcile:** gate green with its new `test_reconcile.lua`; `/fx status` prints the casts line; API names/signatures recorded in §6; confirm no existing behaviour changed except `source` field; **re-run T1 + T7 on uiforever.**
- **ItemData:** counts reported (onUse / procs / consumables / enchants); `lua-errors` shows `Forte_Items` loaded, 0 `Forte_*` errors; skim `docs/item-procs.md`; remember procs are **out-of-combat only** on Forever (no cast to predict, aura reads secret).
- **Options:** `run-tests Forte_Options` + `Forte_Cooldown` green; the two screenshots viewed (or flagged unseen); the report's **unwired keys** list → turn each into a `Timeline` task; ColorPicker API that worked recorded in §8.
- After accepting any worker: update §6 row, §9 log row, todo list; re-zip and re-test on uiforever if the addon changed.

### 10.6 Known pitfalls
- The shell blocks `grep`, `cat`, redirection (`>`), `head/tail`; use the `grep`/`read`/`write` tools, or Python via `eval`.
- `edit` needs the file's current tag; `PUT >$` appends; lines you did not read are rejected.
- `wow-ui-sim --exec-lua @file` is ignored; `print` is swallowed; `--class` takes `Hunter` etc.
- **`--exec-lua` chunks over ~1.2 KB are silently ignored** (measured 2026-11-02: a 2.2 KB
  chunk never ran, a 1.27 KB one did; the sim's arg parser has a ~4 KB per-arg limit). Capture
  drivers must be compact.
- **The Forte stack loads LATE in a headless boot**: `Forte_Cooldown` is LoadOnDemand, forced
  by `Forte_Options`, whose page `FX.Settings:Register("Cooldown", ...)` runs on
  `FORTEXORCIST_ADDONS_LOADED` with retry timers - all of it AFTER a `--delay 3500`
  `--exec-lua`. A one-shot exec-lua at 3500 ms runs before `Display:Init()`, and the late
  `InitSkin` reads the store's defaults back, so its `Settings:Set` is wiped. Drive captures
  from a frame's `OnUpdate` (`docs/media/sim/fx_timeline_modes_*.png` use exactly that).
- A plain `Frame` rejects `SetScript("OnClick", ...)` in this build (`invalid script handler
  'OnClick'`; it is a Button-only slot) - use `OnMouseDown`/`OnMouseUp`, as the source's own
  `Frame_OnMouseDown`/`Frame_OnMouseUp` pair does (`Forte_Cooldown.lua:1226-1227`).
- Class data resolves by NAME; the sim profile's spell IDs differ from our pinned data — never assert ID equality.
- `Engine.MIN_COOLDOWN = 2.99` hides short cooldowns (matches the original).
- WoW Forever has no Death Knight: there is no `Forte_Deathknight` addon and no DK spell list. The `DEATHKNIGHT` token is only used in tests as "a class token with no add-on" (loads nothing, no error).
- A basalt worker cannot view images; you (or the owner) must judge visuals and send **numeric** deltas back.
- Basalt workers can run long; check `proc://` stage lines rather than waiting blindly; if one is at ~80% context without writing its deliverable, message it to write to disk now (worked for `FuncSpec`).

### 10.7 Owner decisions (resolved 2026-11-01)
- Commit + push: **authorized** (pushing after every verified step).
- First real-client session: **only after the 11-04 launch**.
- Spell Timer v1 scope: **own-cast predictions** accepted.
- In-client MCP tools (`hated-wow-mcp`, `witchcraft`): **adopt after launch**.
- Item/trinket procs: **required, in combat too** — engine-wide problem; plan in `docs/design-combat-procs.md`, evidence in `docs/research/secrets-unknowns.md`. Ask the owner which procs to watch once the gate-container probe passes on launch day.

---

## 11. Iteration plan (written 2026-11-01 late, unattended run)

Status at `156392e`: `scripts/gate.py` PASS — Forte_Cooldown 75, Forte_Hunter 15, Forte_Options 42 tests; 0 `Forte_*` errors; 10 data sets + 2 modules + options load; data deterministic. uiforever battery T1–T13 recorded in §10.4.

**Iteration B (now, parallel, disjoint file ownership; basalt workers):**
| Slice | Owner files | What | Why |
|---|---|---|---|
| B1 ProbeKit | `Forte_Core/Core/Probe.lua` (+toc twins, `Forte_Core/tests/`), `docs/launch-day.md` | `/fx probe [label]` runs every day-1 probe from `docs/research/secrets-unknowns.md` + `docs/design-combat-procs.md` §5 inside pcalls, records into `FX.db.probes`, prints a summary; owner checklist for launch day | turns launch day into one command; answers the 7 open live questions in one session |
| B2 ReadTiers | `Forte_Cooldown/Core/Engine.lua`, `Module.lua`, `Forte_Core/Core/Compat.lua`, tests | (a) boolean ready tier from NeverSecret `isActive/isOnGCD` (early-ready in combat, resets); (b) opportunistic exact anchor from `C_Spell.GetSpellCooldownDuration` objects when not `HasSecretValues()` and the remaining time reads plain; (c) `FX.SecretState` from `C_RestrictedActions` + `C_Secrets.Should*BeSecret`, updated on `ADDON_RESTRICTION_STATE_CHANGED`, shown in `/fx status` | in-combat correctness beyond prediction (research Q2/Q5) |
| B3 HunterUI | `Forte_Hunter/UI/*`, `Forte_Hunter/Pages/*` (+toc twins), tests | Auto Shot swing bar (Classic skin: Aluminium, URW Gothic) from `PLAYER_SWING` (documented, no secrecy), aspect-missing reminder out of combat, Hunter options page registered through `FX.Options:RegisterPage` | first visible class tool; Hunter first |
| B4 TimelineFidelity | `Forte_Cooldown/UI/Timeline.lua`, `test_timeline.lua`, screenshots | splash to the original's law (`Forte_Cooldown.lua:1391-1403`: ~2.5×, white, ~1 s), re-check pulse/cross-fade against source; screenshot scenarios must advance the clock before capture | the remaining known fidelity delta |
| CD-30/31/35 | `Forte_Cooldown/UI/Timeline.lua`, `test_timeline.lua`, `Forte_Options/Pages/Cooldown.lua`, `test_options.lua`, `docs/media/sim/fx_timeline_modes_*.png` | **Warn (CD-31)**: the Display owns an event frame registered to `UNIT_SPELLCAST_FAILED` for `player` while `Cooldown.Warn` is on (the source's `CD_RegisterCallbacks` :953-960 branch), resolving the spellID to a NAME (`C_Spell.GetSpellInfo` + `PlainOrNil` + `pcall`, never an ID compare) and warning only a live non-Buff/Debuff entry (:938-941): the attention Spark2 rides `2.2 x ih x t20` (:1412-1416, tinted `FixIntensity(category)`), `t20 = 1 + (the seconds left of focustime = 0.5 s)` (:32, :540-542, :874), and the warned row takes the cross-fade focus to full alpha while every other member of its group is driven to zero (:860-877). **CD-30**: a right-button release (`OnMouseUp`, the source's pair :1226-1227 - a plain Frame rejects `OnClick` in this build) opens `FX.Options:Open("Cooldown")`, refused by the press-stamp `Moved()` compare (:902, `Options.lua:649-662`). **CD-35**: `Vertical` / `Flip` / `HideZero` join the skin at the shipped defaults (:1808, :1809, :1815, :1821) - the frame swaps to `Height x Width` (the source's `frame.Update` :1476-1479), the icons/tags/splashes/pulses/segments pick their anchor POINTS from the two flags (:1427-1450, :1260-1263, :1176-1189) with `TimelineMath.pos` as the coordinate in all four modes, segment UVs mirror (the source's own `Flip` branch :1403-1408), and the auto-hide gate is the Draw test `s.Hide and not cd:find(0,17)` (:1348) over the Module feed. All four keys drive the bar live through `Display:ApplySettings` | gate green (Cooldown 135, Options 49); the 9 new timeline tests fail on the pre-change file; the mode shots carry the live numbers: VERTICAL 24x250 with the tags at y -110/+116 and the icons at a constant x, FLIP 250x24 with the tags mirrored to x +110/-116 |

**Iteration C (before launch if time allows):**
- Weapon-enchant timers (`C_Item.GetWeaponEnchantInfo` + `WEAPON_ENCHANT_CHANGED`) as an `Enchant` category on the bar.
- Load-on-demand class data (**done, 2026-11-02**, agent `LoadOnDemand`, §9):
  `## LoadOnDemand: 1` on the nine `Forte_<Class>` toc twins, and
  `Forte_Core/Core/Loader.lua` loads the *player's* class add-on at
  `PLAYER_LOGIN` via `C_AddOns.LoadAddOn`. Measured in the sim: a session parses
  7.9 KB of the 385 KB of class Lua at a Paladin profile (97% not parsed);
  Forte_Items stays always-loaded.
- Warlock tools groundwork (Soulstone/Healthstone/Shard tracking — out of combat reads + cast prediction).
- Spell Timer (`Forte_Timer`) design + seed from `UI/Rows.lua` (own-cast predicted rows).
- **Spell Timer polish (done, 2026-11-02):** the Crowds palette key, the debug feed's
  future-dated stamps and the bounded arrival flash; one `Module.DEFAULT_POSITION`
  (CENTER/CENTER 261,-150) so the panel is a column beside the Cooldown bar at its own
  height instead of overprinting it; `KIND_RULES` rewritten from regex-shaped strings
  (which can not match in Lua, so all 366 generated spells sat on `Default`) into ordered
  term bands -- the measured coverage is now 530 tracked / 0 Default. §9 carries the
  details. Forte_Timer 34 -> 44 tests.

**Iteration D (after launch-day probes):**
- Proc gate containers + `C_UnitAuras.AddAuraSound` (design P-C/P-D) — only after probe 2/3 shows self-buff gates fire in combat.
- Duration-object rendering spine (research design change 5) if probe 5 shows self-built objects tick in combat.
- Fix whatever `/fx probe` reports; update §8 risks with measured facts.

Every slice: worker owns its files only; manager re-runs `scripts/gate.py`, views every screenshot, re-tests on uiforever when behaviour changed, commits + pushes.

