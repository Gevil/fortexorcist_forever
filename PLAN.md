# ForteXorcist for WoW Forever — Plan & Handoff

Status as of 2026-11-01 (WoW Forever launches 2026-11-04). Owner: Gevil.
Read `AGENTS.md` first for working rules; this file is the *what* and *why*.

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
  (`Cooldown:SetCooldown` rejects secret values; sanctioned path is
  `C_Spell.GetSpellCooldownDuration` → `Cooldown:SetCooldownFromDurationObject`).

---

## 4. Spell / item data pipeline

No hand-typed spell IDs. Data is generated.

| Source | Path | Role |
|---|---|---|
| mythicsim-forever-engine (Rust, MIT) | `$WORK/mythicsim-forever-engine/data/*.jsonl` | **Primary.** 7,503 spells with DurationMs/CooldownMs/GCDMs/CastTimeMs/Effects; items, enchants, consumables. `manifest.json` pins `client_build` (currently **1.60.1.70425**). |
| wowsims/forever (Go) | `$WORK/wow-forever-sim/forever/` (pull only, never commit) | Cross-check class/proc/talent logic (`sim/<class>/*.go`). Pulled to `b70888a5` (2026-11-01). |
| wowsims/gamedata | github.com/wowsims/gamedata | Per-build diffs (`patches/1.60.1.70707/…`) to catch drift between the mythicsim pin and live. Not cloned yet. |
| mythicsim.com/wow-forever, wowsims.com/forever | web | Human reference only (class changes, talent rework); the websites are not data sources. |

Generator: `tools/gen_spell_data.py <class>` reads `tools/spell_lists/<class>.json` (spell
*names* grouped by purpose), picks the highest-rank row per name, writes
`addon/Forte_<Class>/Data/<Class>.lua` (`ForteXorcist.Data.<Class>` + `…ByName`), and reports any name
not found (never silently dropped).

Known data gaps to resolve (Hunter): `Rapid Fire` (row 28755 has no cooldown fields) and
`Intimidation` (no cooldown) are generated but not tracked as cooldowns; `Misdirection`,
`Snake Trap`, `Kill Command`, `Wyvern Sting`, `Readiness`, `Explosive Shot`, `Master's Call`,
`Track Humanoid` had no exact-name match — likely renamed, talent-only, pet-cast or absent in
Forever. Check via mythicsim `spell-effects.jsonl`, wowsims `sim/hunter/*.go`, and Forever's
talent data before adding.

---

## 5. Dev & test tooling

| Tool | Where | Use |
|---|---|---|
| **wow-ui-sim** v0.1.39 (Osso, GPL-3.0), Forever build | `$WORK/wow-ui-sim/` — run via `./run.sh wow-sim …` | Headless UI/API simulator with a Forever profile (incl. `spell_aura_secrecy` data). `run-tests <Addon>` runs `Interface/AddOns/<Addon>/tests/*.lua` (`test(...)`, `assertEquals`, `async_test`, `A_Admin` namespace to set combat/buffs/party). Also `lua-errors`, `dump-tree`, `screenshot`. |
| uiforever.com | browser, `/app?flavor=forever` | Visual check: drop addon folder in, any class/race, dungeon/raid scenario, Lua stack traces, missing-API list, memory. |
| luajit | `/usr/bin/luajit` | Fast syntax check + pure-logic smoke tests with stubs (no `luac` on this box). |
| Real client | `<WoW install>/_forever_/` | Final verification only. |

**wow-ui-sim gotcha:** the release binary needs ICU 78; Fedora here ships ICU 77.
`$WORK/wow-ui-sim/icu-vendor/` holds only `libicui18n/libicuuc/libicudata.so.78`
copied from the installed `org.freedesktop.Platform 26.08` flatpak runtime; `run.sh` puts that
dir (and nothing else) on `LD_LIBRARY_PATH`. Do **not** point `LD_LIBRARY_PATH` at the whole
flatpak lib dir (its glibc breaks the binary). No rpm-ostree layering.
`./run.sh wow-sim --version` → `wow-sim 0.1.39` (verified). `run-tests` not yet exercised.

---

## 6. Current state (2026-11-01)

Git repo, remote `github.com/Gevil/fortexorcist_forever` (private). Nothing deployed to the client yet.
All addon paths below are relative to `addon/`.

| File | State |
|---|---|
| `Forte_Core/Forte_Core.toc`, `_Camelot.toc` | Done |
| `Forte_Core/Core/Compat.lua` | Done — `IS_FOREVER`, `HAS_COMBAT_LOG=false`, `HAS_BLIZZ_CDM=false`, `PlainOrNil`, `GetSpellCooldown`, `IsPlayerSpell` |
| `Forte_Core/Core/Constants.lua` | Done — identity, colors, `FX.Print` |
| `Forte_Core/Core/Init.lua` | Done — module registry, bootstrap frame, `/fx`, `/fx status`, SavedVariables |
| `Forte_Hunter/` toc ×2 + `Data/Hunter.lua` | Generated — 30 spells |
| `Forte_Warlock/` toc ×2 + `Data/Warlock.lua` | Generated — 34 spells (secondary) |
| `Forte_Cooldown/Core/Engine.lua` | Done (logic only) — `Build`, `BestDuration`, `OnCast`, `OnRead`, `Sweep`, `Sorted`, `AttachStorage` |
| `tools/gen_spell_data.py`, `tools/spell_lists/{hunter,warlock}.json` | Done |
| `Forte_Cooldown` toc, event wiring, display, tests | **Not started** |
| `scripts/deploy.sh` | **Not started** |
| `README.md`, `AGENTS.md`, `PLAN.md`, `docs/` | Done (initial) |

Verified: every Lua file parses (luajit). Engine smoke test with stubs (luajit): Hunter →
16 tracked cooldowns; cast predicts 120 s Bestial Wrath; secret read leaves it; plain read
anchors and learns 110 s; recast predicts 110 s; sweep pops ready; untracked cast ignored.
**Never loaded in wow-ui-sim or the real client yet.**

---

## 7. Phased plan

### Phase 0 — housekeeping (small)
- Repo exists (`Gevil/fortexorcist_forever`). Commit/push only when the owner asks.
- `README.md`: what it is, install, data regeneration, credits (CooldownMaster MIT, mythicsim MIT,
  wowsims MIT, original FX by Xus).
- `scripts/deploy.sh`: symlink each `addon/Forte_*` folder into `<WoW>/_forever_/Interface/AddOns/`
  (symlinks, idempotent, `--copy` and `--clean` options). Edits then need only `/reload`;
  new files/TOC changes need a client restart.

### Phase 1 — Forte_Cooldown v1 (Hunter) — *next*
1. `Forte_Cooldown.toc` + `_Camelot.toc`: `## Dependencies: Forte_Core`,
   `## OptionalDeps: Forte_Hunter, Forte_Warlock` (so data loads first), files
   `Core/Engine.lua`, `UI/Display.lua`, `Module.lua`.
2. `Module.lua`: `FX.RegisterModule("Cooldown", …)`. In `OnEnable`:
   - `Engine:AttachStorage(FX.db.cooldownLearned or {})` (create the table in `FX.db`).
   - `Engine:Build(FX._playerClass, isKnown)` where `isKnown(name)` = `C_Spell.GetSpellInfo(name)`
     non-nil and `Compat.IsPlayerSpell(info.spellID)`. Rebuild on `SPELLS_CHANGED` (debounced)
     and on `PLAYER_REGEN_ENABLED`.
   - `UNIT_SPELLCAST_SUCCEEDED` (player): name via `C_Spell.GetSpellInfo(spellID)` → `PlainOrNil`
     → `Engine:OnCast(name, GetTime())`.
   - `SPELL_UPDATE_COOLDOWN` + `PLAYER_REGEN_ENABLED` + 1 Hz safety tick: for each tracked name,
     `Compat.GetSpellCooldown(name)` → `Engine:OnRead(...)`.
   - 10 Hz display tick: `Engine:Sweep(now)` → ready messages; `Engine:Sorted()` → Display.
3. `UI/Display.lua`: movable anchor frame, pooled rows (icon via `C_Spell.GetSpellTexture(name)`,
   name, remaining time), dirty-checked, position saved in `FX.db`, `/fx lock|unlock|reset`.
4. Ready alert: chat line + optional sound (`PlaySound`), later a splash frame.
5. Items/trinkets: equipped trinkets (`GetInventoryItemCooldown("player", 13|14)`), potions/
   healthstones (`C_Container.GetItemCooldown(itemID)`), bag scan via `C_Container`.
   Pattern: CooldownMaster `Engine:PollOneItem` / `ClassifyBagItem`.
6. Fix Hunter data gaps (§4) and regenerate.

**Acceptance:** in wow-ui-sim, `run-tests Forte_Cooldown` passes (tests below) and
`lua-errors` shows nothing from `Forte_*`; on uiforever.com as a Hunter the frame appears and
`/fx status` lists the modules; on the real client a Hunter casting e.g. Disengage/Concussive
Shot sees a timer that ends when the button is ready, in and out of combat, with zero Lua errors.

### Phase 2 — tests
- `addon/Forte_Cooldown/tests/test_engine.lua` (wow-ui-sim format): port the luajit smoke test above
  to `test(...)` cases; add GCD-masking case (`OnRead` "ready" within 1.6 s of a cast is ignored),
  learned-duration persistence, rebuild on class change.
- Use `A_Admin` to toggle combat and secret state for an integration test.
- Optional: GitHub Action `osso/wow-ui-sim` once the repo is on GitHub.

### Phase 3 — Hunter class tools (`Forte_Hunter` gains code)
- Aspect reminder (missing aspect out of combat), trap timers (cast-predicted, arming/duration),
  Hunter's Mark / sting timers on target (cast-predicted only, reconciled out of combat),
  auto-shot / swing timer via `PLAYER_SWING`, range / dead-zone light (8–35 yd, range APIs plain).
  Reference: charles-hood/wow-forever-addons `HunterHUD` (MIT) for measured facts.
- Pet: happiness/feed reminder, pet ability cooldowns.

### Phase 4 — Spell Timer (own buffs)
- Out of combat: `C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")` learn name→duration.
- In combat: cast-predicted entries keyed by name (CooldownMaster `_buffByName` / `RestartBuffFromCast`),
  `UNIT_SPELLCAST_SENT` target name to detect casts on others (don't claim them as yours).
- Proc buffs (no cast to predict from) can only be shown out of combat — document per proc.

### Phase 5 — all other classes
For each class: write `tools/spell_lists/<class>.json` (cooldowns, buffs, class tools), generate,
add `Forte_<Class>` tocs, add class tools. Suggested order after Hunter: Warlock (FX's heritage:
Soulstone/Healthstone/Shard/Summon), then Mage, Priest, Druid, Rogue, Warrior, Shaman, Paladin.
Use wowsims `sim/<class>/*.go` and mythicsim fixtures to find procs/talent spells per spec.

### Phase 6 — options & polish
Options panel (Settings API), profiles, sounds, splash/ready frame, Masque, raid/party messages
(`SendChatMessage` — verify which channels Forever allows from addons), localization.

---

## 8. Risks / open questions
- Launch build may differ from 70707; re-check `.build.info`, regenerate data after a
  mythicsim/wowsims pull, scan `wowsims/gamedata` diffs.
- Exactly which cooldown reads are secret in combat on live is not measured by us yet — log it
  (count `"secret"` vs `"anchored"` results from `Engine:OnRead`) in the first real session.
- Earlier beta reports: SavedVariables were not loaded back (fixed later?). The installed client's
  `WTF/Account/*/SavedVariables/` has real files with `.bak`, which suggests saving works now —
  verify `ForteXorcistDB` survives a full client restart.
- `_Camelot.toc` + plain `.toc` both present: confirm the client loads exactly one copy.
- wow-ui-sim is GPL-3.0: use it as a tool only, don't vendor its code into FX.
