# wow-ui-sim: combat simulation, post-v0.1.39 changes, recording — 2026-11-03

Agent `SimScout2` (Iteration I row, PLAN.md §11.2). Sources: installed binary
`$WORK/wow-ui-sim/wow-ui-sim-v0.1.39-forever-linux-x86_64/` (probed live 2026-11-03), fresh clone
`https://github.com/Osso/wow-ui-sim` at `/tmp/wow-ui-sim-src`, master head `06b67d9a`
("Respect secure ping publication in startup test", 2026-11-03 09:30 -0600), tag `v0.1.39` =
`389ca8a` (2026-10-31, released 2026-11-01T00:34Z). **380 commits** on master between the two
(`git log --oneline v0.1.39..HEAD | wc -l`).

## 1. Answers first

1. **v0.1.39 already supports scripted combat simulation end-to-end** — enter/leave combat with
   the lockdown events, GCD + per-spell cooldowns, cast bars with real `UNIT_SPELLCAST_*` payloads,
   player aura injection, `PLAYER_SWING` injection, a **deterministic manual clock**
   (`SetManualClock`/`AdvanceTime`), class/spec/race selection, and a running-GUI socket that
   `wow-cli` drives (`lua -e`, `screenshot`, `mouse-*`). All measured in the installed binary
   (probes §2.2). What it does **not** support: secret-value production in the Forever profile
   (no `SecretValue`, no `C_Secrets.ShouldAurasBeSecret`/`ShouldCooldownsBeSecret`), `C_RestrictedActions`
   (Retail/PTR-gated), custom **target** auras (fixture-only), and cast *completion* in headless mode
   (GUI loop only).
2. **After the tag, the big items for us are the Forever profile pin moving to client build
   1.60.1.70707** (exact match to our live client; removes the spellID-drift problem of PLAN §8),
   the **WM61 secret-auras package** (adds `C_Secrets.ShouldAurasBeSecret` + publication predicates
   for the Forever profile — the API our launch-day secrecy probes talk to), a `SetRestrictionContext`
   admin (Retail/PTR only), `PET_ORDER_MOVE_TO_PENDING_CHANGED` registerable, PR #34 Forever
   `spell_id_by_name` subtext alignment, and GUI-session/reload hardening (PR #26). **No newer
   release binary is published** (v0.1.39 is the latest release and the latest tag); building HEAD
   needs Rust 1.99.1 + system packages this machine does not have (no `cargo`/`rustc` in PATH) —
   report only, not built (§3.3).
3. **Recording**: there is no video/GIF command, no transparent background (the headless canvas is
   cleared opaque `[0.05,0.05,0.08,1.0]`, `src/render/headless.rs:349-353`), and WebP defaults to
   quality 15 (use `--png`). The smooth-recording recipe is: one GUI session + manual clock +
   `wow-cli lua -e A_Admin.AdvanceTime(dt)` + `wow-cli screenshot --png --crop` per frame, then
   ffmpeg — deterministic time per frame, real animation stepping (OnUpdate receives the exact
   delta), one startup for the whole GIF, exact crops from `dump-tree -v` rects. Full command
   lines in §4.4.

## 2. (1) v0.1.39 inventory for combat simulation

### 2.1 Command/API surface (all in the installed binary; `run.sh wow-sim help <cmd>`)

- Subcommands: `dump-tree`, `screenshot`, `lua-errors`, `self-test [--max-ticks N]`,
  `run-tests <Addon>`, `dump-texture`, `cache-texture`. Top-level options include
  `--addons-path`, `--class/--spec/--race`, `--delay <MS>`, `--exec-lua <CODE|@file>`,
  `--exec-lua-secure`, `--screen game|login|…`, `--no-addons`, `--no-saved-vars`,
  `--debug-borders/-anchors/-elements` (v0.1.39 `--help` output).
- `wow-cli` (talks to a **running GUI** over `/tmp/wow-lua-<pid>.sock`,
  `src/lua_server.rs:126-129`): `lua -e CODE|-f FILE|-l` (non-interactive injection!),
  `screenshot -o --png --width --height -f <frame-subtree> --crop WxH+X+Y`, `dump-tree`,
  `dump-quads`, `mouse-move --x --y`, `mouse-click --x --y` (`src/bin/wow_cli/main.rs:75-158`).
- `wow-sim screenshot` (headless, one frame): `--width/--height` (default 1600x1200), `--png`
  (lossless; WebP default quality 15!), `--quality 1-100`, `--crop WxH+X+Y`, `-f <frame>` render
  ONLY that frame subtree, `--dump-tree [FILTER]` tree alongside, `--ui-scale S` — "the client
  renders 1 UI unit as height/768 * uiScale pixels; 1440p at uiScale 0.9 is 1.6875. Above 1.0 the
  2x atlas art is used" (binary `screenshot --help`; `WOW_SIM_HIRES_ATLASES=0/1` override).
- `wow-cli screenshot` in v0.1.39 has **no** `--ui-scale` (HEAD neither; `src/bin/wow_cli/main.rs`
  grep). Headless `--ui-scale` is the sharp path.

### 2.2 Measured with `A_Admin` (probes run against the installed v0.1.39 binary;
full outputs in artifacts `5045` and the P1/P2/P3 runs of 2026-11-03)

The binary's `A_Admin` table (dumped in full) includes, verbatim:
`SetInCombat, SetGCD, SetSpellCooldown, SetSpellBookItemLowRank, SetCasting, StopCasting,
DelayCasting, FailCasting, StartChannel/UpdateChannel/StopChannel, StartEmpower/UpdateEmpower,
AddBuff, AddDebuff, RemoveBuff, ClearBuffs, AddLossOfControl/ClearLossOfControl, SetTarget,
SetTargetHealth, ClearTarget, SetFocus, SetEnemyPool, SetPartySize/SetPartyMember/SetRotDamage,
SetPlayerHealth/Power, SetFrameProtected, SetMoving/Mounted/Flying/Swimming, SetManualClock,
AdvanceTime, SetWorldElapsedTime/AdvanceWorldElapsedTime/StartWorldElapsedTimer, SetGameTime,
SetGameRule/SetActiveGameMode, FireEvent, SimulateBossKill, RegisterTestAddon,
IsSimulatorExitRequested, ToggleDebugBorders/Anchors` (+ bag/mail/auction/quest/collection families).

Probe facts (Forever profile, `--allow-ui-version-mismatch`):

| Probe | Result |
|---|---|
| `SetInCombat(true/false)` | fires **`PLAYER_REGEN_DISABLED`** on entry, **`PLAYER_REGEN_ENABLED`** on exit; `InCombatLockdown()`/`UnitAffectingCombat("player")` flip (also `Interface/TestAddOns/Wowless/tests/admin_api.lua:42-50`). No `PLAYER_ENTERING_COMBAT`/`LEAVING_COMBAT` fired. |
| `SetManualClock(10)` + `AdvanceTime(2.5)` | `GetTime()` → **12.5** — a deterministic clock; `GetTime` returns **elapsed seconds** in the sim (`src/lua_api/register.rs:400-403 clock_elapsed().as_secs_f64()`), NOT retail ms. |
| `SetSpellCooldown(276105,36)` then advance 5 s | `GetSpellCooldown(276105)` → `(12.5, 36, 1)` = `(start, duration, modRate)`. GCD sentinel = spell **61304** (`docs/admin-api/combat.md`, SetGCD section). |
| `FireEvent("PLAYER_SWING", 1.6, 0)` | delivered synchronously as `(1.6, 0)`; `PLAYER_SWING` + `PLAYER_SWING_RANGE_UPDATE` registerable, `Enum.PlayerSwingType = {MainHand=0,OffHand=1,Ranged=2}`; unknown event names rejected (`SPELLSUPDATED` register → false). Contract: `crates/sim-event/src/valid_events.rs:59-60` (FOREVER_REGISTERABLE_EVENTS, present at the tag), `tests/wowforever_finite_constants.rs:177-234` (payload order `(swingDuration, swingType)` — duration FIRST; range event leads with `swingType`), spec `docs/specs/forever-finite-constants.md:114-126`. Matches our PLAN §8 swing-law note. |
| Casts | `SetCasting(spellId, name, icon, duration)` = state-only initializer (fires **no** start event, `docs/admin-api/combat.md`); `FailCasting()` → `UNIT_SPELLCAST_FAILED` then `UNIT_SPELLCAST_STOP` with 4-arg payload `(unit, castGUID, spellID, castBarID)` measured `(player, Cast-Sim-2, 276105, 2)`; `StopCasting()` silent. Completion (`UNIT_SPELLCAST_STOP`+`UNIT_SPELLCAST_SUCCEEDED`, `src/lua_api/cast_completion.rs:34-50`) is driven by the **GUI app loop** (`src/iced_app/casting/`): in headless `--exec-lua`, an elapsed `SetCasting` never completes (P3 observed zero SUCCEEDED). The completion check reads `clock_elapsed()` (`cast_completion.rs:24`) → with the manual clock, GUI-mode casts complete deterministically on `AdvanceTime`. |
| Cast-event injection | `UNIT_SPELLCAST_SUCCEEDED` is registerable AND `A_Admin.FireEvent` accepts it → headless scenario drivers can inject the 4-field payload directly (incl. for `target`/`pet` unit tokens). |
| Auras | `AddBuff(spellID,name,icon,durationSec,stacks[,caster])` / `AddDebuff(...[,dispelType])` — **player-only**, fire `UNIT_AURA` (`docs/admin-api/buffs.md`). Target auras are a fixed fixture (`src/lua_api/globals/auras.rs:323-333`, `sim_state.rs:545 "seeded with the legacy target fixture"`) — no setter. |
| Secrecy | `C_Secrets = {GetSpellAuraSecrecy, ShouldUnitIdentityBeSecret}` — exactly the tag's Forever surface (`src/c_api/c_secrets.rs` at tag, lines 36/43). `SecretValue`/`SecretValues`/`IsSecretValue` globals = nil. No runtime secret-value production in the Forever profile (§3.2). |
| Restrictions | No `SetAddOnRestrictionActive`/`SetRestrictionContext` in the binary: `C_RestrictedActions` + those admins are **Retail/PTR-only** (`src/c_api/restricted_actions.rs:23-27 supported() = matches!(ACTIVE, Retail | Ptr)`). |

### 2.3 Time advance (answers "does time advance between frames?")

- Headless runs use the **real wall clock** by default: `clock_elapsed = start_time.elapsed()`
  (`src/lua_api/manual_clock.rs:16-21`). Our "~0.02 s per capture" note = wall-clock time across
  the fixed headless phase set: `--delay MS` is a real-time loop firing OnUpdate with real deltas
  and draining `C_Timer` (`src/startup.rs:130-147 apply_delay_with_tick`, 16 ms slices), then
  exactly **3 extra ticks at 0.016 s** (`run_screenshot` → `run_extra_update_ticks(env, 3)`,
  `src/bin/wow_sim/gui_commands.rs:313`; `fire_one_on_update_tick(0.016)`, `startup.rs:180-186`),
  plus startup animation groups force-advanced **2.0 s** (`settle_startup_animation_groups`,
  `startup.rs:167-176`). That is why loops must backdate stamps (our `scripts/demo_media.sh`).
- **Yes, there is a tick/advance API**: `A_Admin.SetManualClock(seconds)` (enable-once) +
  `A_Admin.AdvanceTime(delta)` — advances both clock coordinates, fires **one OnUpdate with the
  exact delta**, drains due `C_Timer` callbacks in deadline order; animation groups and
  EncounterTimeline advance off that OnUpdate delta (binary A_Admin list;
  `src/lua_api/manual_clock.rs:33-89`; spec `docs/specs/manual-simulation-clock.md:5-9`;
  usage example `docs/admin-api/challenge-mode.md:66-70`). Post-tag `AdvanceTime` gained only a
  retail-12-0-5 frame-budget reset (`git diff v0.1.39..HEAD -- src/lua_api/manual_clock.rs` = +5
  lines) — the binary we run is functionally current.
- `GetTime` = seconds (sim) vs ms (retail client): scenario drivers and any FX math on `GetTime`
  must tolerate the unit shift. [measured]

### 2.4 Scripted scenarios

- Headless: `--exec-lua @/tmp/x.lua` + a subcommand; our ~1.2 KB chunk cap applies (PLAN §10.6).
  **Correction:** PLAN.md:562 says "`--exec-lua @file` is ignored" — **false for v0.1.39**: three
  `@file` chunks (929–998 B) executed and were visible via `lua-errors` on 2026-11-03.
- GUI: run `wow-sim` with no subcommand (`WOW_SIM_GUI=1` + DISPLAY) and drive it with
  `wow-cli lua -e/-f`; `A_Admin.IsSimulatorExitRequested` exists for scripted shutdown.
- `run-tests <Addon>` runs `Interface/AddOns/<Addon>/tests/*.lua` (the gate path) — the A_Admin
  surface above is fully available there (`A_Admin.FireEvent` is `async_test`-friendly;
  `admin_api.lua:326-343`). Canonical scenario cookbook: `docs/admin-api/examples.md`
  ("Simulating Combat for UI Testing", raid-healing party), `docs/admin-api/combat.md`,
  `targeting.md`, `party.md`, `events.md`.

### 2.5 What v0.1.39 CANNOT do for combat sim (boundary list)

1. No SecretValue production for Forever: `C_Secrets` lacks `ShouldAurasBeSecret` in the binary;
   `ShouldCooldownsBeSecret`/`ShouldUnitStatsBeSecret`/`ShouldSpellsBeSecret` are
   `retail-12-0-5 + profile-retail|client-ptr`-gated (`src/c_api/c_secrets.rs:52-68, 79-82`).
   The runtime `SimState.auras_secret_in_context` (Forever script-object access, `feature =
   "client-wowforever"`) is settable **only from Rust integration tests** (`tests/script_object_context_access.rs:105`,
   `tests/forever_aura_secrecy_predicate.rs:33`) — no Lua hook, "No simulator producer can
   determine the live aura-secret context" (`docs/specs/script-object-context-access.md:12`).
   → Our in-combat secrecy behaviour can only be exercised in-sim by **simulating the reads at
   the addon level** (feed plain/secret results into the module seam) — the sim will not mint a
   SecretValue for us.
2. `InCombatLockdown` is a pure read of `SetInCombat`; no protected-action enforcement, no
   chat/protected-frame lockdown emulation, no `C_RestrictedActions` in the Forever build.
3. Cast completion is GUI-loop-driven; headless runs must inject `UNIT_SPELLCAST_SUCCEEDED`
   via `FireEvent` (payload shape above) — our tests already do this.
4. Target/focus aura pools are fixtures; no setters. Player-target DoT display scenarios must
   drive the cast-event path, not the aura path.
5. No combat-log events (`forever-combat-event-namespace` law stands), no damage engine, no
   boss/AI: `SimulateBossKill`/`SetRotDamage`/`SetEnemyPool` are the extent.

## 3. (2) What changed after v0.1.39 (380 commits → head `06b67d9a`)

### 3.1 Combat/secret/time-relevant changes (all post-tag dates)

| Commit | Date | Relevance |
|---|---|---|
| `116f2dff` **Update Forever profile to build 70707** | 11-02 | `data/blizzard-ui-builds/wowforever.json`: tag `1.60.1.70532` → HEAD **`1.60.1.70707` + Gethe rev `aff0d8cd…`** = **our live client build**. The sim's spell DB (70532) that PLAN §8 refuses as an ID oracle would become the same build as the client; `--allow-ui-version-mismatch` becomes unnecessary (profile pin, not flag). |
| `7209a0ef` + `762d8dfd` **WM61 secret-auras S1…S8** (restriction-state model, secret aura models, persisted forced CVars) | 11-02/03 | Forever gains `C_Secrets.ShouldAurasBeSecret` (`src/c_api/c_secrets.rs:30-43 client-wowforever`; spec `docs/specs/spell-aura-secrecy.md:46-54`: Forever gate returns false even with `unit_auras_restricted`; the *context* input is Rust-only). Retail-side forced-`addonCombatRestrictionsForced`-CVar model (`restricted_actions.rs:16-32`) is Retail/PTR-gated. `A_Admin.SetRestrictionContext(encounterStatus, count, pvpState, …)` new (`HEAD admin.rs:126-130`; Retail-only). |
| `860bf27b`,`5600a20d`,`a8587a8b`,`871f45a2`,`488fe45a` (WM61 publication slice) | 11-02/03 | Restricted AuraData fields published individually; spell-name→aura-id rejection; AuraData predicate fixes — closer Forever aura-secrecy publication semantics. |
| `093a723b` Gate aura duration queries on aura enumeration | 11-03 | `C_UnitAuras` duration queries gated (WM61 S6 family). |
| `9e533745` **PR #34: forever `spell_id_by_name` subtext + WM71 alignment** | 11-03 | The sim profile's name→ID resolution for Forever changed — directly relevant to our name-resolution runtime and to any data regeneration. |
| `f8ea0fc8` retail-aura-identity WM73 GetParent receiver view | 11-03 | Aura-identity/`GetParent` receiver views (TargetFrame managed auras). |
| `4697cf40`/valid_events | 11-03 | `PET_ORDER_MOVE_TO_PENDING_CHANGED` added to FOREVER_REGISTERABLE_EVENTS (Warlock pet queues). |
| `c8c022ee`,`cfffb1995` scoped combat-text event payloads | 11-02 | `A_Admin.FireEvent('COMBAT_TEXT_UPDATE', payload)` special-case refined (`src/lua_api/globals/admin_events.rs:28-30`; spec `combat-text-current-event.md`). CombatText was already tag-present. |
| `91859af0` PR #26 "Finalize GUI sessions and recover failed reloads" (`ffd59693`) | 11-02 | GUI session/reload hardening — stabilises the §4.4 recording loop. |
| `80da1b5c` PR #33 BLP partial DXT decode, texture path/listfile override | 11-02 | Fewer atlas/texture decode artefacts in captures. |
| `d1196bd7` CombatAudioAlert known targets (WM52) | 11-02 | Combat audio targeting; not FX-facing. |
| `0e47a188` PR #30 `C_ChatInfo` addon-message prefixes | 11-02 | Our Warlock comms use addon messages; prefixes now modelled. |
| `b5c5e9d9` toolchain pin 1.99.1 + rustfmt 2024 | 11-02 | Build-side (§3.3). |

Unchanged since the tag (verified by diffstat `git diff --stat v0.1.39..HEAD -- …`): the whole
combat admin surface (`admin.rs` +13 = only `SetRestrictionContext`; `combat_verbs.rs` +13 =
`SpellStopTargeting` Forever pet-cancel), the manual clock core, cast events,
`PLAYER_SWING*`/`SHARD_TRANSFER*` Forever event lists, `auras_secret_in_context` (Rust-test-only
in every version). The **`v0.1.39` binary is functionally current for everything in §2.**

### 3.2 Secrecy data file (what the Forever profile ships)

`crates/sim-data-profile/data/spell_aura_secrecy.rs` (generated; header lines 1-3): "Client
export: **12.1.0.69497**; SpellMisc SHA-256 3ef1…; both native flags retained; no precedence
inferred". i.e. the aura-secrecy attribute table is generated from a **retail PTR export** and
shared to Forever via the `aura-containers` feature ("published for Retail 12.1+ and Forever",
`docs/specs/spell-aura-secrecy.md:3`; "Known gaps: Shared Forever publication GREEN is pending").
Treat per-spell `GetSpellAuraSecrecy` values in the sim as retail-flavoured hints, not Forever
ground truth — the live client remains the oracle (PLAN §8 law unchanged).

### 3.3 Newer binary? / how to build

- **No newer release:** GitHub releases atom lists v0.1.39 (2026-11-01T00:34:38Z) as latest
  (https://github.com/Osso/wow-ui-sim/releases — "Latest"; release page notes **898 commits to
  master since this release**). `git ls-remote --tags`: newest tag = v0.1.39. Release cadence is
  ~daily-to-weekly, so v0.1.40 is plausible within days, not weeks.
- **Release assets:** the v0.1.39 tag page carries 14 assets; our installed dir name
  `wow-ui-sim-v0.1.39-forever-linux-x86_64` matches the published per-profile naming — a new
  release with the 70707 profile would give the same drop-in swap (`run.sh` ICU shim + install
  shim unchanged).
- **Building HEAD locally — not done (report only, per task bounds):**
  `rust-toolchain.toml` pins channel **1.99.1** (profile minimal + rustfmt); this box has
  **no `cargo`/`rustc` in PATH** (probed 2026-11-03), so a build needs a toolchain install
  (rustup) plus the Dockerfile's system deps: clang, mold, git, pkg-config, cmake,
  libicu-dev, libudev-dev, fonts-dejavu-core (Debian names; `Dockerfile:23-30`).
  Release command for our profile (`Dockerfile:62`):
  `cargo build --release --bin wow-sim --bin wow-cli --no-default-features --features client-wowforever,gui,tools --locked`
  (plus `wow-cli casc sync-forever-spells --source cdn` for the spell bundle, `Dockerfile:63`),
  on rust:1.92+ bookworm; the workspace is huge (iced+wgpu+phf data, CI builds in Docker),
  first build ≫ 10 min on this 2-core-limited box → **out of scope today**. A container build
  (`podman build --build-arg WOW_UI_SIM_PROFILE=wowforever`) is the clean route with owner
  approval. A community action also exists (`action.yml`: `ghcr.io/osso/wow-ui-sim:<tag>` runs
  `run-tests`, retail-flavoured).
- After a profile bump, refresh the local Blizzard UI cache:
  `run.sh wow-cli casc sync-blizzard-ui --allow-ui-version-mismatch` (PLAN §5 recipe).

## 4. (3) Recording: making demo GIFs smoother

### 4.1 Existing capabilities (v0.1.39 binary, all verified via `--help`/source)

| Need | Tool | Evidence |
|---|---|---|
| Frame sequence / "video" | none built in; sequence = loop `screenshot` (headless) or `wow-cli screenshot` (live GUI) | `src/bin/wow_cli/main.rs:105-141`, `src/lua_server.rs:483+` |
| Higher resolution | `--width/--height` (any), plus **`--ui-scale 1.6875`** (1440p@0.9: lays out at client scale, uses 2x atlas art) — sharper glyphs than raster upscale | `wow-sim screenshot --help`; `src/bin/wow_sim/main.rs:923-943` tests |
| PNG (lossless) | `--png`; WebP default quality is **15** — never use WebP for GIF sources | `screenshot --help`, `gui_commands.rs:455-462` |
| Crop to a frame | `--crop WxH+X+Y` (both CLI paths), or `-f <FrameName>` **renders only that frame subtree** (subtree-only render = auto-framing, no other UI) | `gui_commands.rs:353,437-453`; `build_screenshot_batch ... root_name(filter)` |
| Crop geometry | `dump-tree -v` prints per-frame rect + UV; `wow-sim screenshot --dump-tree [FILTER]` renders + dumps in one run | `dump-tree --help`; our `demo_media.sh dtbox` already consumes this |
| Transparent background | **Not supported**: canvas clear is opaque dark-navy `[0.05,0.05,0.08,1.0]`; alpha=1 everywhere | `src/render/headless.rs:333-353` |
| Smooth animation timing | manual clock: `SetManualClock(t0)` + `AdvanceTime(dt)` → one OnUpdate with **exact dt** (animation groups, C_Timer, spark/statusbar updates), `GetTime` advances exactly dt | §2.3; `manual_clock.rs:33-89` |
| Deterministic renders | GUI server renders are "pixel-identical" to the live pipeline; headless = same wgpu pipeline (`render_to_image`), so headless/GUI frames mix | `headless.rs:1`, `:356-360` |
| Interaction | `wow-cli mouse-move/mouse-click` (canvas coords), `SetMousePosition/SetMouseOverFrame` | `wow-cli --help` |
| Debug overlays | `--debug-borders/-anchors`, `A_Admin.ToggleDebugBorders/Anchors` | `--help` |

### 4.2 Why the current trick costs what it costs

`scripts/demo_media.sh` runs the full sim once per frame (startup + ReloadUI ×4 phases +
`--delay` real-time loop + 3 settle ticks, `gui_commands.rs:296-316`), backdating stamps by
`@K@` because each fresh process sees wall-clock time only. That is inherent to
**headless-one-frame-per-process**; the GUI-server path removes it.

### 4.3 Exact command line — combat scenario (headless, one state, v0.1.39)

```bash
WOW=/var/home/gevil/Work/Personal
cat >/tmp/fx_scene_combat.lua <<'LUA'   -- keep <= ~1.1 KB (PLAN chunk cap; @file works)
A_Admin.SetManualClock(0)
A_Admin.SetPlayerClass(3); A_Admin.SetSpec(3)         -- Hunter, Marksmanship
A_Admin.SetInCombat(true)
A_Admin.SetTarget("Ragnaros", 85, 1, true)
A_Admin.SetPlayerHealth(68000, 100000)
A_Admin.AddBuff(34004, "Battlelust", 132328, 26, 1)
A_Admin.AddDebuff(5760, "Fear", 136247, 12, 1, "Magic")
A_Admin.SetGCD(1.5)
A_Admin.SetSpellCooldown(193442, 25)                   -- Wildward Shot  [demo ids]
A_Admin.SetSpellCooldown(198547, 44)                   -- [demo ids]
A_Admin.FireEvent("PLAYER_SWING", 1.6, 0)
A_Admin.FireEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Scn-1", 276105, 7)
A_Admin.AdvanceTime(6.4)                              -- cooldowns/sparks advance 6.4 s exactly
LUA
cd /tmp && $WOW/wow-ui-sim/run.sh wow-sim --allow-ui-version-mismatch \
  --addons-path $WOW/wow-fortexorcist/addon \
  --exec-lua @/tmp/fx_scene_combat.lua \
  screenshot --png --width 1600 --height 1200 --ui-scale 1.6875 \
  -o /tmp/fx_combat.png            # add: -f ForteXorcistCooldownTimeline  (subtree-only)
                                    # add: --crop 900x180+350+600           (from dump-tree -v rect)
```
Frame geometry first: same command line with `dump-tree -v --visible-only -f ForteXorcist`
in place of `screenshot …` (parse rects as `demo_media.sh dtbox` already does).

### 4.4 Exact command line — smooth recording (one session, deterministic frames)

```bash
# 0) one-time: capture the crop box from dump-tree (as 4.3)
# 1) start the GUI session (owner-visible window; DISPLAY needed, WOW_SIM_GUI=1)
WOW=/var/home/gevil/Work/Personal
cd /tmp && WOW_SIM_GUI=1 $WOW/wow-ui-sim/run.sh wow-sim --allow-ui-version-mismatch \
  --addons-path $WOW/wow-fortexorcist/addon --exec-lua @/tmp/fx_scene_setup.lua &
sleep 20                       # first-frame + ADDON_LOADED settle
# 2) deterministic frame loop (20 min budget): 30 fps for 6 s = 180 frames
for i in $(seq 0 179); do
  $WOW/wow-ui-sim/run.sh wow-cli lua -e "
    A_Admin.SetManualClock(0)            -- enable-once; later calls error, guard in setup
    A_Admin.AdvanceTime(1/30)
    if $i % 37 == 5 then A_Admin.FireEvent('PLAYER_SWING', 1.6, 0) end
    if $i % 61 == 9 then A_Admin.SetGCD(1.5); A_Admin.SetSpellCooldown(193442, 25) end
    if $i == 30 then A_Admin.FireEvent('UNIT_SPELLCAST_SUCCEEDED','player','Cast-Scn-2',276105,8) end
    if $i == 90 then A_Admin.SetInCombat(false) end"
  $WOW/wow-ui-sim/run.sh wow-cli screenshot -o $(printf /tmp/fx_frames/f%03d.png $i) \
    --png --width 1600 --height 1200 --crop WxH+X+Y   # box from dump-tree
done
# 3) encode (same pipeline as demo_media.sh)
ffmpeg -y -framerate 30 -i /tmp/fx_frames/f%03d.png -vf "scale=iw*2:ih*2:flags=lanczos" \
  -c:v libx264 -pix_fmt yuv420p /tmp/fx_scene.mp4
```
Notes: `SetManualClock` is enable-once → call it once inside `fx_scene_setup.lua`, then the loop
only `AdvanceTime`s. The GUI render happens on the sim's own frame cadence; the recorded
*timeline* is the manual clock (deterministic), wall-clock only sets capture pacing — jitter
freezes a frame one slot, never skips simulation time [inference from `manual_clock.rs`
+ loop structure]. For subtree-only frames pass `-f ForteXorcist…` to `wow-cli screenshot`
(instead of `--crop`). The 70707-profile HEAD build is not required for any of this.

## 4.5 Quality deltas vs `scripts/demo_media.sh`

- One startup per GIF (≈ 8–16 s saved per 60-frame loop at measured ~4–6 s/run) → also removes
  per-run `--delay` real-time cost.
- Frames step by exact `dt`: sparks/animation groups/splash bells evolve continuously; the
  backdating shim (`@K@`) disappears; scene scripts become the single source of truth.
- `--ui-scale` at 2x atlas = crisp text at 2880x2160 (ffmpeg-downscale to 1440p) — current
  captures render at scale 1.0 and upscale 3x with lanczos.
- PNG everywhere (WebP q15 is a loss trap).

## 5. Open questions / risks

1. Release cadence: no `v0.1.40` yet; the 70707-profile binary (with Forever aura-secrecy
   predicates) lands with the next release — watch
   `https://github.com/Osso/wow-ui-sim/releases.atom`; asset naming per profile
   (`…-forever-linux-x86_64`) matches our layout.
2. GUI-server determinism under load: wall-clock render jitter (§4.4 note) — verify on the
   owner box before converting all loops.
3. `C_Secrets.GetSpellAuraSecrecy` values in the shipped table come from a retail PTR export
   (12.1.0.69497) — do not treat as a Forever secrecy oracle.
4. Whether Osso will publish a Docker tag built `--features client-wowforever`
   (`Dockerfile` supports the profile; `action.yml` images are retail-flavoured).
5. `--exec-lua` chunk cap (~1.2 KB) confirmed on files ≤998 B; cap for `@files` >1.2 KB
   untested this session.

## 6. What we should change (ranked; files in our repo)

1. **Rework `scripts/demo_media.sh` to the GUI-server frame loop** (§4.4): per-GIF single
   session, manual clock, `--png --ui-scale 1.6875`, crop box from `dump-tree -v`. Removes the
   `@K@` backdating scaffolding and the per-frame startup cost.
2. **Add a combat-scenario harness for the Wave I-2 round** — new `scripts/scenario.sh` +
   `scripts/scenarios/*.lua` (≤1.1 KB drivers; the §4.3 line), with a `run-tests`-compatible
   variant so each module gets an in-combat test (SetInCombat + injected
   `UNIT_SPELLCAST_*`/`PLAYER_SWING` + SetGCD/SetSpellCooldown + AddBuff/AddDebuff +
   `AdvanceTime`), feeding `scripts/gate.py` unchanged.
3. **Record the clock facts in our sim docs** — `docs/reference/wow-ui-sim-specs/`:
   `GetTime` = elapsed **seconds** (client = ms), `SetManualClock`/`AdvanceTime` contract,
   `--delay` = real-time loop + 3×0.016 settle, WebP default quality 15, opaque canvas clear.
   Files: new `docs/reference/wow-ui-sim-specs/time-and-capture.md`; check
   `addon/Forte_Core/Compat/Compat.lua` + engine stamp paths for `GetTime` unit assumptions.
4. **PLAN.md corrections** (lines 562–565 area + §8): `--exec-lua @file` **works** (3 measured
   runs, v0.1.39); add "no SecretValue production in Forever sim profile — in-combat secrecy is
   addon-side + launch probes only" (reinforces §8 mitigation (2)); note the sim-profile
   `spell_aura_secrecy` table's retail-PTR provenance (§3.2).
5. **Binary strategy**: pin the installed v0.1.39 (functionally current for §2); subscribe to
   the releases atom; adopt the next release when it carries the 70707 profile — it retires
   `--allow-ui-version-mismatch` in `AGENTS.md` verification commands, `scripts/gate.py`,
   `scripts/demo_media.sh` (all keep the flag harmlessly until then).
6. **Data regeneration plan update**: when the 70707-pinned sim lands, re-run
   `tools/gen_spell_data.py` against its profile + re-check the §8 name/ID collision list
   (sim DB == client build makes ID assertions meaningful again); PR #34's
   `spell_id_by_name` subtext change is the upstream signal that name→ID resolution is active.
7. **Target-aura demos**: use injected `UNIT_SPELLCAST_SUCCEEDED("target", …)` (works today)
   for Spell Timer target rows; document that `A_Admin` cannot plant custom target auras
   (`auras.rs:323-333`) so the timeline DoT rows are event-predicted in media.

## 7. Evidence index

- Live probes 2026-11-03 against the installed binary: A_Admin key dump (artifact `5045`),
  P1 (events/enums/secrecy globals), P2 (manual clock + combat events + GetSpellCooldown),
  P3 (cast lifecycle, headless completion absent, FailCasting payload `(player,
  Cast-Sim-2, 276105, 2)`).
- Clone `/tmp/wow-ui-sim-src` @ `06b67d9a`; tag compare `v0.1.39(389ca8a)`:
  `git log --oneline v0.1.39..HEAD` (380), diffstats cited inline.
- Binary `--help` transcripts: `wow-sim`, `wow-cli`, `help dump-tree/screenshot/run-tests/
  lua-errors/dump-texture/self-test`, `wow-cli help lua/dump-quads/screenshot` (2026-11-03).
- Releases: https://github.com/Osso/wow-ui-sim/releases (+ `.atom`: v0.1.39 latest,
  2026-11-01T00:34:38Z; tag page "898 commits to master since this release").
- Build: `Dockerfile:23-30, 62-63, 68-100`; `rust-toolchain.toml`; PATH probe (no cargo/rustc).
- Profile pins: `data/blizzard-ui-builds/wowforever.json` tag `1.60.1.70532` vs HEAD
  `1.60.1.70707` (`116f2dff`, 2026-11-02).
