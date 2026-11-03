# WeaponSwingTimer SixxFix (Forever v1.60.2) — Hunter behaviour survey → Forte_Hunter v2

Scout note for PLAN.md §11.1 row "Hunter swing v2" (`PLAN.md:679`). Reference source:
`/tmp/wst/src/WeaponSwingTimer/` (all file:line below are that tree; `toc` header:
`## Interface: 16001`, `## Version: 1.60.2`, `## Author: LeftHandGlove, WatchYourSixx`,
`WeaponSwingTimer.toc`). **Licence: GPLv3** (owner-confirmed, `PLAN.md:679`) = our licence
(`LICENSE` = GPL-3.0 full text) → their code MAY be adapted; attribution + change notices
required (authors: **WatchYourSixx** (SixxFix), **LeftHandedGlove** (original WST,
`README.md:1`)). Every "adapt" row below names the exact function worth adapting;
`addon/Forte_Core/ATTRIBUTION.md` gains a WST section (owned by `HunterSwing2`).

**Bottom line.** WST's Hunter value boils down to five mechanisms we do not have:
(1) the two-phase shot cycle — a **reload phase** and a fixed ~0.5 s **aiming window**
whose length is `0.5 × hastedSpeed / baseSpeed` (`WeaponSwingTimer_Hunter.lua:109-141`,
`:283-286`), where moving during aiming loses the shot; (2) the **white "projectile left,
safe to move/cast" state** (`README.md:22-24` — the bar is white while moving/casting cannot
clip the next shot, non-white means stand still); (3) the **GUID-keyed cast-event machine**
for the aiming phase (`UNIT_SPELLCAST_SENT → START → SUCCEEDED / INTERRUPTED /
FAILED_QUIET`, Hunter.lua:465-631) including the **0.5 s failed-start retry penalty**
(`:604-631`, drawn as `retry_bar` `:705-709`); (4) the **readiness gate** (target alive,
attackable, in range, standing → only then show "aiming", `:182-215`) and the
**Feign-Death reset path** (`:309-321`, `:410-414`, `:421-427`); (5) the **range /
dead-zone band** ladder (`WeaponSwingTimer_Range.lua:339-433`). Our tracker/bar already own
the plain cycle and the Classic skin; we port 1–5 as our own code (adapting WST formulas
where cited), and skip WST's melee bars, target bar, profile system, config framework,
tooltip base-speed scan, GCD/clip remnants, latency strip (catalog mismatch — §B12) and
nonexistent-spell paths (Readiness/traps/`Shoot` 5019 — §B15/B19).

Catalog checks below ran over the pinned catalog
`docs/api/wow-addon-api-agents/skills/*/references/generated/forever.json` (the paths
`scripts/api_lint.py:12` loads). "CAT ✓" = declaration present in the pinned catalog.
Secret-risk column = the pinned catalog's secrecy annotation + our 12.x law
(`docs/research/secrets-unknowns.md` §1 `:34-51`, §6 `:429-461`; `AGENTS.md` hard rules).

## 0. Reference architecture (verified)

- One `OnUpdate` driver on a core frame calls `player/target/hunter/castbar` `OnUpdate`
  (`Core.lua:196-201`, wired at `Core.lua:391`); events on one core frame, registered at
  `ADDON_LOADED` (`Core.lua:348-378`), dispatched by one `OnEvent` switch
  (`Core.lua:450-557`).
- CLEU is **deliberately dead** on Forever: `cleu_available = false` with a comment that
  12.x blocks `COMBAT_LOG_EVENT_UNFILTERED` (`Core.lua:353-357`); the
  `OnCombatLogUnfiltered` handlers (Hunter.lua:500-511, Castbar.lua:330-357) are unreachable
  (the event is never registered). Confirms the roster's "no CLEU" — pushback moved to
  `UNIT_SPELLCAST_DELAYED` (Castbar.lua:224-263).
- `PLAYER_SWING` registered under `pcall`; success sets `native_swing_available`
  (`Core.lua:370-378`) and then PLAYER_SWING is "the sole authority for normal ranged swing
  resets" (Hunter.lua:543-552) — cast-success legacy resets are gated off (Hunter.lua:553-584).
- In-combat state = `PLAYER_REGEN_ENABLED/DISABLED` (Core.lua:455-460) — the same law as
  our `onToolEvent` (Tools.lua:398-399).
- Every protected read goes through a local `WST_IsSecret` = `issecretvalue` guard
  (Hunter.lua:11-13, Player.lua:5-8, Target.lua:5-8) and a cache-when-secret fallback
  (e.g. Hunter.lua:131-134 "Combat may hide ranged stats. Never replace a known speed
  multiplier …" — same shape as our `PlainOrNil` law, Tools.lua header).
- Class gates: Hunter bar enabled-by-default for HUNTER/**MAGE/PRIEST/WARLOCK** (the wand
  classes share the bar, Hunter.lua:243-247); castbar HUNTER-only (Castbar.lua:276-280,
  :316-317). `UnitClass` is `SecretWhenUnitIdentityRestricted` in the catalog; WST's target
  code explicitly stops reading it ("can return secret values", Target.lua:86-90).
- **No sounds anywhere** in WST (grep `PlaySound|SoundFile|Sound` over the tree: 0 hits) —
  "sounds" in the config-options brief: not a WST feature. Audio stays Forte_Messages' job.
- Config framework: its own `Settings.RegisterAddOnCategory` panel tree + Ace3 profiles
  (Config.lua:29-30, :88-96, :335-523), global "Lock All Bars" checkbox writing
  `is_locked` into all five bar settings (Config.lua:285-297, :313-320), slash
  `/wst` (Core.lua:544-556). Saved vars: `WSTProfileDB` + per-char keys (toc:36-37).
  We keep Forte_Options; none of this framework ports.

## 1. Behaviour inventory

Legend per row: mechanism + file:line; **events/APIs** with catalog verdict; **secret risk**
on 12.x combat for our use; note. `[INFERENCE]` marks reading beyond the code.

### B1. Shot cycle anchor — PLAYER_SWING drives the cycle
`OnPlayerSwing(duration, swing_type)`: guards (secret/≤0/non-Ranged drop), clears an
inferred aiming phase, records `native_cycle_speed = duration`,
`native_cycle_cast_time = 0.5 × duration / base_speed` (this cycle's hasted aim length),
`shot_timer = duration`, `last_shot_time = now`, `auto_shot_ready = false`,
resets the feign flag (Hunter.lua:261-292). "In Forever, PLAYER_SWING is the authoritative
source for ranged swing timing. Spell-cast events do not reset the normal Auto Shot timer"
(Hunter.lua:256-259).
- Events/APIs: `PLAYER_SWING` CAT ✓ (`wow-api-combat`, `SwingTimerDocumentation.lua` —
  payload `(swingDuration, swingType)`, duration first).
- Secret risk: none annotated; high-confidence plain, live third-party consumer on the
  client (`secrets-unknowns.md:429-461`).
- Note: this is exactly our `SwingTracker:OnSwingStart` (Tools.lua:184-191) minus the
  aim-length derivation (B3) and the `native_cycle_cast_time` pinning.

### B2. Auto Shot on/off — START/STOP_AUTOREPEAT_SPELL
`OnStartAutorepeatSpell` sets `shooting = true`; on the OFF→ON edge: stamp
`autorepeat_started_at`, and if the last shot is older than a full cycle, drop the
native-cycle pin so live reads retake over (`:433-442`); toggling on with the timer already
at the floor re-arms a shot (`:443-447`). `OnStopAutorepeatSpell` clears `shooting`, the
pending attempt, the cast GUID/phase, and the retry timer (`:454-461`). Registered at
Core.lua:360-361.
- Events/APIs: `START_AUTOREPEAT_SPELL`, `STOP_AUTOREPEAT_SPELL` CAT ✓
  (`wow-api-spells-abilities`, `SpellBookDocumentation.lua`) — the pinned declarations carry
  **no Payload fields** ⇒ the event cannot distinguish Auto Shot from wand Shoot ⇒ the
  **Auto Shot / wand Shoot paths are shared** (one `shooting` flag; the bar is
  "Autoshot/Shoot bar", Hunter.lua:1029).
- Secret risk: none annotated (unit-less events; WST reads no args).
- Note: shared-path answer for the brief: yes, one path; wand caveat §B19.

### B3. The two phases + the white "projectile left, safe to move/cast" state
The core law. **Aim window length** `GetAutoCastTime() = 0.5 × speed / base` where `speed =
UnitRangedDamage("player")` (hasted; includes quiver haste — comment Hunter.lua:108),
`base =` the un-hasted weapon base speed (§B13); authoritative mid-cycle from B1's pin
(`native_cycle_cast_time`, `:111`); falls back to cached value, then
`0.5/(1+GetRangedHaste()/100)`, floor `0.5` (`:109-141`).
**Cycle model** (`UpdateAutoShotTimer`, `:353-398`): `shot_timer` counts down but is
**clamped at the aim floor** (`:359-360` `math.max(shot_timer - elapsed, cast_time)`); the
moment it reaches the floor (plus the retry, §B4), the **aiming phase** starts
(`BeginAutoCastVisual`, `:332-351`); `auto_shot_ready` = floor reached, aim not running
(`:381-382`).
**White state** (`UpdateVisualsOnUpdate`): `shot_bar` (the white/progress bar) width =
`(shot_timer − cast_time) × scale` (two-bar mode, `:688-699`); the fixed right-end slice
`auto_shot_cast_bar` = the aim window (`:701-704`, red default `auto_cast_* 0.8,0,0`
`:82-83`); `one_bar` mode: white fills left→right and follows the shrinking red edge
(`:688-694`, panel label "YaHT / One bar" `:1096-1103`).
**User law**: "The shot bar turns white when projectile leaves the player. While the bar
is white, the player can move and cast freely without clipping their next Auto Shot or
Shoot. When the white bar is depleted, the player should stand still while their Auto Shot
or Shoot is 'casting'" (`README.md:22-24`).
- Events/APIs: `UnitRangedDamage` CAT ✓ (`UnitDocumentation.lua`, first return `speed`;
  **`SecretWhenUnitStatsRestricted=true`**), `GetRangedHaste` CAT ✓
  (`PlayerScriptDocumentation.lua`, returns `(result, quiverHaste)`,
  `SecretWhenUnitStatsRestricted`).
- Secret risk: the speed/haste reads can be secret in combat (WST treats them as such —
  Hunter.lua:99-100, 126-137). Everything here is derived arithmetic + `GetTime()` after the
  first plain read ⇒ in-combat-safe once seeded; our `PlainOrNil` law covers it.
- Note: the white window = "the shot that will fire next has not begun its aim yet, so
  moving cannot cost it" — i.e. **safe-to-move window = remaining reload time**; the aim
  slice = stand-still zone. This is the headline gap: our bar has one phase
  (Swing.lua:362-400).

### B4. Aiming phase = a cast: GUID-keyed event machine + 0.5 s retry penalty
`UNIT_SPELLCAST_SENT` (Auto Shot): record a GUID-keyed `pending_auto_attempt` (tentative —
the same batch may report FAILED_QUIET, comment `:462-464`) (`:465-473`).
`UNIT_SPELLCAST_START`: authoritative begin (`inferred=false`), clear pending, zero the
retry timer, `auto_shot_ready=false`; also clears `FeignStatus`, runs `StartCastingSpell`
(§B9 gate), and stamps `spell_GCD=1.5` for Steady/Multi (`:479-498`; `spell_GCD` is computed
in `:396-401` and **never drawn** — vestigial).
`UNIT_SPELLCAST_SUCCEEDED`: on GUID match end the phase, zero `auto_cast_remaining`,
and record the facts a completed shot proves (`attackable=true, in_range=true,
dead=false` — "readable negative checks still take priority", `:514-542`).
`UNIT_SPELLCAST_INTERRUPTED`: end phase (`:587-601`).
**Retry penalty**: `UNIT_SPELLCAST_FAILED_QUIET` = "auto shot … can't [begin]; This causes
0.5 seconds of delay before it can try casting again" (`:602-631`): restart
`auto_delay_timer = auto_delay_duration (0.5, :95-97)`, raise the floor to the aim length
(`:625-627`); drawn as `retry_bar` (orange `1,0.5,0`, right-anchored at the aim slice's
start, `:705-709`); pending promotion when a SENT proves good (`:388-396`); display folds
the retry into the printed timer (`:651-657`).
Movement kills an **inferred** (not server-confirmed) aim phase — `auto_cast_inferred and
not can_begin → drop` (`:361-366`); a confirmed cast survives movement (its truth is the
events, and `UNIT_SPELLCAST_INTERRUPTED` is the mover).
- Events/APIs: `UNIT_SPELLCAST_SENT/START/SUCCEEDED/INTERRUPTED/FAILED_QUIET` all CAT ✓
  (`wow-api-unit-player`, `UnitDocumentation.lua`; payload `(unitTarget, castGUID,
  spellID[, castBarID])`, INTERRUPTED adds `interruptedBy` — WST's dispatcher passes
  `(args[1], args[3], args[2])` = (unit, spellID, castGUID), Core.lua:513-537 — matches).
- Secret risk: all five carry **`SecretWhenUnitSpellCastRestricted=true`** — spellID/GUID
  may wrap in combat (`secrets-unknowns.md:34-51`); own-casts "player exception" ⇒ always
  delivered; **never compare a raw spellID/GUID** — resolve through
  `pcall + PlainOrNil` exactly as our `resolveCastName` (Tools.lua:339-352). WST guards the
  GUIDs with `WST_IsSecret` (e.g. `:467`, `:520`). Spell-ID gates (75, 5384, …) need our
  name-keyed law (AGENTS.md "track spells by name") — WST's ID tables are the GPL-adaptable
  part; the 75/5384 IDs match our pinned data (Auto Shot 75, Feign Death 5384,
  `mythicsim-forever-engine/data/spells.jsonl`).
- Note: also `UNIT_SPELLCAST_FAILED` is wired to the same "interrupted" handler
  (Core.lua:527-529) — WST treats plain-FAILED as end-phase; keep FAILED_QUIET distinct
  (the penalty source).

### B5. Readiness gate (what "safe to begin aiming" means)
`CanBeginAutoVisual` (`:182-215`): `shooting && UnitExists("target")` (`:184`);
`UpdateAutoMovement` (`:145-156`); `UnitIsDeadOrGhost("target")` → `state.dead`
(`:186-188`); `UnitCanAttack("player","target")` (`:189-192`); range via
`pcall(C_SwingTimer.IsTargetWithinSwingRange, Enum.PlayerSwingType.Ranged)` (`:194-200`)
falling back to the range module's band (`:201-211`, §B16). Result =
`moving==false and dead~=true and attackable==true and in_range==true` (`:218-219`).
Event hygiene: a dedicated watcher frame (`:846-853`) registers `PLAYER_STARTED_MOVING`,
`PLAYER_STOPPED_MOVING`, `PLAYER_TARGET_CHANGED`, `PLAYER_ENTERING_WORLD`;
`OnReadinessEvent` (`:158-175`) clears pendings/GUID/target-facts on target-change /
world-entry and manages the move-pulse (§B6).
- Events/APIs: all CAT ✓ (`wow-api-unit-player`; `PLAYER_ENTERING_WORLD` in
  `wow-api-widget`). `C_SwingTimer.IsTargetWithinSwingRange(swingType) → bool(Nilable)`
  CAT ✓, `SecretArguments=AllowedWhenUntainted` (return not annotated secret);
  `C_SwingTimer.EnableRangeCheck(swingType, enable)` CAT ✓ (WST never calls it — our
  `docs/hunter-tools.md` probe 7 already lists it; `secrets-unknowns.md:456-458` recommends
  enabling it while the widget is shown). `UnitCanAttack`/`UnitExists`/`UnitIsDead*` CAT ✓,
  booleans not annotated secret.
- Secret risk: low (own-player/target presence APIs); runtime reachability for third-party
  addons is `declaration: source-declared, addonAccess: unknown` (catalog evidence field) —
  launch probe, same caveat our tracker already carries.

### B6. Movement detection
Dual source: continuous `GetUnitSpeed("player") > 0` sampled in `OnUpdate`
(`:403-408` sets `has_moved`; `:147-149` in `UpdateAutoMovement`) **and** the
`PLAYER_STARTED/STOPPED_MOVING` events (`:160-165`); when the speed read is secret, a
`PLAYER_STARTED_MOVING` pulse is only trusted once sustained ≥ 0.05 s
("Short event pulses are not enough … a sustained start event still cancels the
inference", `:150-154`); STOPPED clears (`:163-166`).
- Events/APIs: `PLAYER_STARTED_MOVING`/`PLAYER_STOPPED_MOVING` CAT ✓
  (`wow-api-unit-player`, no payload). `GetUnitSpeed(unit) → (currentSpeed, runSpeed,
  flightSpeed, swimSpeed)` CAT ✓, **`SecretWhenUnitStatsRestricted=true`**.
- Secret risk: speed can be secret in combat → WST's pulse-fallback is the pattern; our
  law: `PlainOrNil` the speed, event pulses as the non-secret lane.
- Note: we already register `PLAYER_REGEN_*` and own an event frame (Tools.lua:406-421);
  the two movement events are cheap additions.

### B7. Feign Death interaction
On SUCCEEDED(5384) in native mode: set `FeignStatus = true`, clear `FeignFullReset`
(`:546-552`). The **reset fires on the next movement** (`OnUpdate` `:410-414`:
"Check for feign death movement that causes swing reset") and on **jump-out** via
`hooksecurefunc("JumpOrAscendStart", …)` (`:421-427`). `FeignDeath()` (`:309-320`): stamp
`last_shot_time = now`, first pass only set `range_speed = base_speed + 0.15` (an unhasted
plus-grace cycle — `[INFERENCE]` models the first post-FD shot arriving late; WST ships the
+0.15 fudge verbatim), set `FeignFullReset`, `ResetShotTimer()` (full re-arm at current
cycle length, `:322-329`). Any new cast start clears `FeignStatus` (`:488`).
`FeignFullReset` is re-cleared by each real PLAYER_SWING (`:291`).
- Events/APIs: `UNIT_SPELLCAST_SUCCEEDED` CAT ✓ (§B4 risks; the 5384 gate needs name
  resolution "Feign Death" — in our data list, `tools/spell_lists/hunter.json`
  `pet_and_utility`). `hooksecurefunc` and `JumpOrAscendStart`: **NOT in the pinned
  catalog** (grep: 0) — the jump leg is unproven on Forever; `[INFERENCE]` a
  `PLAYER_JUMP`-style event or the movement leg covers it; probe list.
- Note: legacy-mode variants (FD/Trueshot success ⇒ immediate reset) at `:553-561` —
  §B8.

### B8. Legacy (non-PLAYER_SWING) reset table — dead on Forever
If `native_swing_available` is false, success of Feign Death/Trueshot/Aimed/Auto/
`Shoot`(5019) resets `shot_timer`/`last_shot_time` and `Shoot` refreshes `range_speed`
from `UnitRangedDamage` (`:553-584`). Native mode returns before it all (`:543-552`).
- Note: our tracker already keeps the one leg we need from this family: the
  `Auto Shot`-cast fallback start (`Tools.lua:209-215`). Port **no** other leg.

### B9. Aimed Shot / Multi-Shot (and Steady) cast tracking
A second bar ("castbar", frame name `HunterCastbarFrame`, Castbar.lua:588) is a
**cast-time bar for castable shots**: starts on `UNIT_SPELLCAST_START`
(Multi/Aimed/Steady, `:208-221`) — **and on `UNIT_SPELLCAST_SENT`** because
"Forever Multi-Shot does not emit UNIT_SPELLCAST_START, … SENT followed by SUCCEEDED"
(`:195-205`, the comment is the finding). Length: live `UnitCastingInfo("player")`
`(start_time_ms, end_time_ms)` first; fallback the static rank table
(Multi 0.5 / Aimed 2.0 / Steady 2.0, ids table `:4-23`) then
`pcall(C_Spell.GetSpellInfo(id))` `.castTime` ms (`:136-165`). The Hunter bar's phase gate
uses the same cast set: `StartCastingSpell` sets `casting=true` for Multi/Aimed/34120
behind `UnitCanAttack` (Hunter.lua:216-231) — while casting, `UpdateAutoShotTimer` keeps
running the cycle (the cycle itself is untouched: cast events "do not reset" it,
`:256-259`), and `auto_cast_active` visuals gate off; `casting` clears on SUCCEEDED/FAILED/
INTERRUPTED (`:534`, `:599`, `:411-416`).
**Pushback**: `UNIT_SPELLCAST_DELAYED` → re-read `UnitCastingInfo` start/end (+
`delay_time_ms`) → authoritative new length + `total_pushback` (`:224-263`); timeout guard:
cast over `cast_time + 0.5` self-fails (`:299-312`).
**Cast visuals**: fill = `cast_timer/cast_time` left→right, gold `(0.8,0.64,0,1)` while
casting, spark at the fill head (`Images/Spark`), right text tenths, centre text = spell
name (`:451-470`, `:608-610`); SUCCEEDED: bar flashes full-width green `(0,0.5,0,1)` +
"0.0" (`:359-384`); FAILED: full-width red `(0.7,0,0,1)` + "Failed" (`:387-416`);
INTERRUPTED: same + "Interrupted" (`:419-448`); idle: alpha fades −0.005/frame (`:471-482`).
- Events/APIs: §B4 set + `UNIT_SPELLCAST_DELAYED` CAT ✓ (same payload + `castBarID
  NeverSecret`); `UnitCastingInfo` CAT ✓ — **`SecretWhenUnitSpellCastRestricted`**, returns
  `(name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill(NeverSecret),
  castID, notInterruptible, castingSpellID, …, delayTimeMs)` with the NeverSecret field set
  recorded (`secrets-unknowns.md:48-50`). `C_Spell.GetSpellInfo` CAT ✓
  (`SecretArguments=AllowedWhenTainted`; `.name` through `PlainOrNil` — our law,
  Tools.lua:339-352).
- Secret risk: own casts are the player exception; route all fields through
  `PlainOrNil`; the Aimed cast length in our data = 2000 ms ranks 19434-20904
  (`spells.jsonl`) — matches the table (the 3.0 s figures in Hunter.lua:26-32 are a legacy
  vanilla table; the live read is the correct source).
- Note: Steady's hard-coded id 34120 (Hunter.lua:228, 494) does **not exist** in the Forever
  data set — Steady rows are 409957 / 437123 (1500 ms cast) — an anti-pattern to avoid
  (ids: name-keyed law, AGENTS.md).

### B10. Multi-Shot clip bar — vestigial in this build
Infrastructure: `multishot_clip_bar` texture (Hunter.lua:840), placement + colour
`clip_* (1,0,0,0.7)` (`:767-774`, defaults `:83`), setting `show_multishot_clip_bar`
(`:75`), toggle (`:912-915`), tooltip "shows a bar that represents when a Multi-Shot would
clip an Auto Shot" (`:1170-1176`). **Every draw path force-hides it**: update `:711`,
settings `:782`, panel checkbox hidden `:1178` ⇒ the clip indicator ships dead in v1.60.2.
Concept (what it would show): where on the cycle a 1.5 s+cast (Multi) lands — casting after
the safe window ends clips the shot. §Gap-11: skip; our safe-window state carries the same
decision-signal.

### B11. Movement during casting — the aim-cancel story
Covered by B3/B4/B6: the **movement law lives in the events** (moving during the aim
window ⇒ the server never starts the cast ⇒ FAILED_QUIET ⇒ 0.5 s penalty; moving after
`SUCCEEDED` ⇒ shot flies, the white window says so). WST's visual response: drop an
inferred aim phase on `not can_begin` (`:361-366`); confirmed phases end only on events.
`UpdateAutoShotTimer` also re-derives readiness **every tick** so a mid-cycle target loss
drops the aim slice at once (`:362`).

### B12. Latency compensation (`GetNetStats`)
`show_latency_bars` (default **false**, Castbar.lua:74): cast length gains
`latency/1000` at cast start (`:183-187`) and a red `(1,0,0,0.75)` strip of width
`width × (latency/1000)/cast_time` is overlaid at the cast bar's left (`:483-491`,
`:542-549`, `:617-618`), toggle `:676+`. Reads `_, _, _, latency = GetNetStats()` — the
**4th** return.
- Catalog: `GetNetStats` CAT ✓ (`wow-api-settings-system`,
  `ConnectionDocumentation.lua`) declaring returns `(in, out, latencyList)` — the 4th
  `latency` WST reads is **not in the pinned declaration**. `[INFERENCE]` WST targets a
  legacy 4-value shape; on Forever the 4th read is nil → `tonumber(nil) or 0` silently
  zero-extends at cast start, and the draw path divides `nil/1000` (runtime error when the
  toggle is on).
- Verdict input: latency strip = skip-until-probe (Gap-12); probe the real return shape
  launch day.
- Note: the *swing* side has no latency model at all (PLAYER_SWING timestamps are client
  clock, `GetTime()`-relative) — nothing to port, nothing at risk.

### B13. Ranged speed & haste sources (base-speed table)
`GetRangedBaseSpeed()`: `GetInventoryItemID("player", INVSLOT_RANGED)` →
`GameTooltip:SetItemByID` → scan tooltip lines for `SPEED .. " (%d%.%d%d)"` ("Speed
1.50"…) → cache per item id, default 1.0 (`ranged_base_speed.lua:1-39`). Refreshed on
`UNIT_INVENTORY_CHANGED` for the four shot classes (Core.lua:359, Hunter.lua:295-306).
Consumed by B1/B3/B7. The cycle-time authority is PLAYER_SWING's own duration
(`native_cycle_speed`, B1) and the visuals deliberately ride
`visual_range_speed`/`native_cycle_speed`, "PLAYER_SWING durations can include
resets/delays and must not move the cast boundary" (`:665-675`).
- Catalog: `GetInventoryItemID` — **NOT in the pinned catalog** (grep 0; modern is
  `C_Item.GetItemID(itemLocation)` CAT ✓ `wow-api-items-inventory`); `INVSLOT_RANGED` —
  **NOT declared** (only `C_Bank.BankBagTypeAndIDToInvSlot` /
  `C_PaperDollInfo.GetInventorySlotInfoForInvSlot` / `C_PlayerInfo.HasVisibleInvSlot`
  rows matched "INVSLOT"); `SPEED` global string — **NOT declared**; the
  `CreateFrame("GameTooltip", …,"GameTooltipTemplate")` + `SetItemByID` tooltip scan —
  `GameTooltip`/`SetItemByID` **NOT declared**; the modern declared shape is
  `C_TooltipInfo.GetInventoryItemByID(itemID) → TooltipData` CAT ✓
  (`wow-api-misc-systems`).
- Secret risk: `UnitRangedDamage`/`UnitAttackSpeed` speed rows
  `SecretWhenUnitStatsRestricted` (B3); the base-speed table (item statics) is not a unit
  read. `UNIT_ATTACK_SPEED (unitTarget)` CAT ✓ (`wow-api-unit-player`) — a declared
  refresh hook WST does not use (it polls `UNIT_INVENTORY_CHANGED`); `SPEED_UPDATE` CAT ✓.
- Risk: WST calls `GetInventoryItemID` unguarded (`ranged_base_speed.lua:15`) and
  `SPEED` in a file-scope concat (`:10`) — if absent on Forever, those throw (api_lint
  checks only `C_*`/`Enum`/events, `scripts/api_lint.py:13-16,49-66`, so plain globals pass
  it unnoticed). Launch probe; our port must not copy this leg.
- Note: our tracker's chain (event duration → `UnitRangedDamage` → `UnitAttackSpeed[3]` →
  last-observed, Tools.lua:159-181) already implements the safe subset; what B3 needs on
  top is a **base-speed** for the aim ratio (§Gap-7: the aim formula needs `base`; seed
  chain + interim `aim=0.5` floor + a settings override — shape in the gap table).

### B14. Quiver / haste buffs
No buff scanning anywhere (grep `Quiver` 0). Quiver haste is **already inside**
`UnitRangedDamage` speed and inside PLAYER_SWING durations — WST relies on that
("uses ranged weapon haste, including quiver haste", Hunter.lua:108) and the declared
`GetRangedHaste` second return `quiverHaste` exists (catalog, B3) unused.
- Verdict: no row to port — our cycle/aim derivation inherits quiver haste the same way.
  Trueshot's swing-reset is covered by B1 (server-side reset ⇒ fresh PLAYER_SWING,
  `[INFERENCE]` — WST's legacy Trueshot leg `:553-561` implies the same expectation, and
  the native-mode comment `:543-545` states cast events do not touch the cycle).

### B15. Readiness / traps interactions
**None exist in WST** (grep `Readiness|Trap|20716|…` — only the unrelated
`OnReadinessEvent` name at Hunter.lua:158, which is B5's visual-readiness watcher).
Readiness has **no row** in our pinned data set (`spells.jsonl` grep 0), traps exist
(Freezing/Frost/Immolation/Explosive, `tools/spell_lists/hunter.json` `traps`) — trap
timers are our separate PLAN item (`PLAN.md:318`, `docs/hunter-tools.md`), not a WST
behaviour.
- Verdict: nothing to port.

### B16. Range / dead-zone indicator
Full module. `GetRangeBand()` (Range.lua:339-433): gates `UnitExists/UnitIsDead/
UnitCanAttack` (`:340-347`); non-Hunter classes use a generic spell-ladder probe table
(`:61-70`, `:213-338` — out of scope). Hunter ladder:
melee ⇔ `C_SpellBook.FindSpellBookSlotForSpell("Wing Clip")` +
`C_SpellBook.IsSpellBookItemInRange(slot,bank,"target")` — **Wing Clip is the only 5-yd
breakpoint; Raptor Strike's range API is broken on Forever** ("reports true outside
actual melee range", `:152-160`);
`NativeRangedInRange` = `pcall(C_SwingTimer.IsTargetWithinSwingRange, Ranged)` →
fallback spellbook `Auto Shot` (`:162-174`);
dead-zone = ranged false && `Scatter Shot`(15-yd) true (`:372-376`, Auto Shot's 8-yd
floor); close = Scatter true (`:378-384`); max range from
`C_Spell.GetSpellInfo(75).maxRange` (fallback 35) (`:201-211`, data MaxRange=35
`spells.jsonl`); ranged false ⇒ `IsCloseFallback()`
= `pcall(CheckInteractDistance,"target",4 then 1)` (~28 yd rings; separates
too-close from too-far, `:176-199`); far/out by `Hunter's Mark`(100-yd) (`:395-401`).
Draw: 10 Hz throttle (`:625-632`), full-width bar re-coloured per band + centred text
(`:579-623`), band colours defaults `:35-42` (melee red `.85,.2,.2`, deadzone yellow
`1,.9,.1`, close amber, ranged green, far blue, out grey), band **texts are user-editable
strings** (`:21-28`), opt-in default off (`:549-552`), a hidden 1×1 always-on poller frame
drives updates (`:664-671`), `/wstrangedebug` dump (`:455-533`).
- Events/APIs: `C_SpellBook.FindSpellBookSlotForSpell` /
  `C_SpellBook.IsSpellBookItemInRange` CAT ✓ (`wow-api-spells-abilities`,
  `SpellBookDocumentation.lua`; `SecretArguments=AllowedWhenUntainted` — bool returns not
  annotated); `C_SwingTimer.IsTargetWithinSwingRange` CAT ✓ (B5); `CheckInteractDistance`
  CAT ✓ (`UnitDocumentation`, bool return not annotated);
  `C_Spell.GetSpellInfo(id).minRange/maxRange` CAT ✓; legacy `IsSpellInRange` — **NOT in
  the catalog** (the modern is `C_Spell.IsSpellInRange(spellIdentifier, targetUnit)` CAT ✓,
  `SecretArguments=AllowedWhenTainted` — WST's fallback leg `:108-122` is the legacy name);
  `PLAYER_TARGET_CHANGED` CAT ✓.
- Secret risk: PLAN §2.4:58 — range checks are **not** secret; WST pcall-wraps every call
  and normalises `true/1`/`false/0` (`:77-84`) — good hygiene to keep.
- Note: this realises the `PLAN.md:318` "range / dead-zone light (8–35 yd)" commitment.

### B17. Player melee bars & target swing bar (bar family context)
`PLAYER_SWING` also feeds MH/OH bars: duration per swing type
(`Player.lua:81-102`), fill `width × (1 − timer/speed)` (fills as the swing burns,
`Player.lua:296-301`), spark texture at the fill head (`:300-306`), `fill_empty` inverts
direction (`:306-310`, default true, `:42`); bar alpha = `in_combat/ooc_alpha`
(`:366-371`; in_combat from PLAYER_REGEN_* Core.lua:455-460).
Melee swing-reset whitelist: Raptor Strike/Maul/Cleave/Heroic Strike/Slam on
SUCCEEDED, Maul also CHANNEL_START path; an explicit note that Hunter **shots** must not
reset melee (`Core.lua:30-57`, `:70-84`). Parry haste: `UNIT_COMBAT` `action=="PARRY"` ⇒
reduce remaining swing by 40 % of weapon speed, floor 20 % (`Core.lua:410-448`,
`:466-476`; payload `(unitTarget, event, …)` CAT ✓ matches). Legacy CLEU parry/extra-attack
legs dead (`Player.lua:155-176`, `Core.lua:127-196`).
Target bar = the boss-swing estimate: CLEU gone ⇒ `OnEstimatedPlayerCombatResult`:
from `UNIT_COMBAT` results on the player, gated by target-targets-player
(`UnitIsUnit("targettarget","player")` — `SecretWhenUnitComparisonRestricted`),
WOUND/DODGE/PARRY/MISS samples, interval clamped 0.5–5.0 s, every sample restarts the
bar (`Target.lua:56-62`, `:81-104`, `:107-171`; secret-bool law comments at `:115-128`).
- **Hunter value: none** — the Hunter product does not swing a main hand in the scenario
  this bar serves, and a boss-swing bar is a tank tool. `Enum.PlayerSwingType` MH/OH filter
  knowledge we already carry (Tools.lua header).
- Verdict: skip the bars; keep one note: WST proves PLAYER_SWING fires for **all three
  swing types with the duration payload** — our Ranged filter stays required
  (Tools.lua:185; test_hunter.lua:179-186 guards exactly this).

### B18. Config options (full inventory, per bar)
Hunter (`Hunter.lua:61-84`, panel `:1010-1212`): `enabled`, `width` 300, `height` 12,
`fontsize` 12, anchor `point/rel_point/x_offset/y_offset` (drag-saved, `:800-813`),
`in_combat_alpha` 1.0 / `ooc_alpha` **0.0** (the bar is alpha-hidden out of combat by
default = the "in-combat only" mechanism; drawn `:668-673`), `backplane_alpha` 0.5,
`is_locked` (global "Lock All Bars" Config.lua:285-297, 313-320), `show_text`,
`show_multishot_clip_bar` (panel hidden), `show_autoshot_delay_timer`, `show_border`,
`classic_bars` (texture swap `Images/Bar` ⇔ `Images/Background` `:755-765`), `one_bar`,
colours `cooldown_*` (grey .95 fill), `auto_cast_*` (red aim slice), `clip_*`; font
`Fonts/FRIZQT__.ttf` (`:757`).
Castbar (`:64-76`): enable/width/height/font/anchor/alpha + per-shot enables
(`show_aimedshot_cast_bar` / `show_multishot_cast_bar` / `show_steadyshot_cast_bar`) +
`show_latency_bars` + `show_cast_text` + `show_border`.
Range (`Range.lua:8-44`): enable/size/font/anchor/alphas/`show_text`/`show_border`/
`classic_bars`/`hide_no_target`/`hide_dead_target`/per-band colour set/**per-band text
strings**.
Player/Target (`Player.lua:17-45`, `Target.lua:16-37`): size/font/anchor/alphas,
per-hand colour + text colour, `show_left_text/show_right_text/show_offhand`,
`fill_empty`, paladin seal-twist markers (Player).
No sounds; no combat-gate beyond the alpha pair; profiles = Ace3 panel (Config.lua:335-523)
— Forte_Options already owns profiles/clones for us.
- Bugs worth not-porting: `UpdateConfigPanelValues` reads
  `panel.show_gcd_spark_checkbox` (`Hunter.lua:873`) which **no factory ever creates**
  ⇒ nil-index when the Hunter panel is built; `show_gcd_spark` is in no defaults table.
- Our equivalents already: Enable/Lock/ShowTime/Width/Height/BarColor/BgColor + shared
  BarFont/GlobalLock (`Pages/Hunter.lua:38-57`, `Swing.lua:463-486`) + `/fx lock` law
  (`hunter-tools.md` "The /fx lock|unlock hook"). Missing pair: in/out-of-combat alpha
  (we hide at idle instead — swings only run while shooting; a combat-gate is a settings
  call, §Gap-10).

### B19. Wand Shoot (the shared-path question)
WST shares one Hunter bar for Auto Shot **and** wand Shoot: class default includes
MAGE/PRIEST/WARLOCK (`Hunter.lua:243-247`); START/STOP_AUTOREPEAT_SPELL carry no spell id
(B2) so the phases cannot distinguish; the Shoot-specific leg (5019: legacy reset +
`range_speed` refresh) is **legacy-mode only** (`:571-584`) — native mode = PLAYER_SWING +
autorepeat cover both (B1/B2).
- Our data pin: **no `Shoot` (5019) row exists in Forever data** (`spells.jsonl` grep:
  only "Soul of the Trick Shooter" rows) — `[INFERENCE]` wands shoot via the same Ranged
  swing subsystem so PLAYER_SWING(Ranged) fires for wands too (server-authoritative);
  wand users are a launch-day probe, no code today (our bar is Hunter-gated).

### B20. Sounds
None (see §0). Verdict row 14: nothing to compare; audio = Forte_Messages.

## 2. Catalog summary table (events/APIs WST touches)

All events WST registers are **CAT ✓** in the pinned catalog: `PLAYER_SWING`,
`PLAYER_SWING_RANGE_UPDATE` (wow-api-combat); `START_AUTOREPEAT_SPELL`,
`STOP_AUTOREPEAT_SPELL`, `C_SpellBook.*` (wow-api-spells-abilities);
`UNIT_SPELLCAST_SENT/START/CHANNEL_START/DELAYED/SUCCEEDED/FAILED/FAILED_QUIET/
INTERRUPTED`, `UNIT_COMBAT`, `UNIT_INVENTORY_CHANGED`, `UNIT_ATTACK_SPEED`,
`PLAYER_STARTED_MOVING`, `PLAYER_STOPPED_MOVING`, `PLAYER_TARGET_CHANGED`,
`PLAYER_REGEN_ENABLED/DISABLED`, `SPEED_UPDATE` (wow-api-unit-player);
`PLAYER_ENTERING_WORLD` (wow-api-widget).
Functions CAT ✓: `GetTime`, `UnitExists`, `UnitClass`, `UnitGUID`, `UnitCanAttack`,
`UnitIsDead`, `UnitIsDeadOrGhost`, `UnitIsUnit`, `UnitAttackSpeed`, `UnitRangedDamage`,
`GetUnitSpeed`, `GetRangedHaste`, `CheckInteractDistance`, `UnitCastingInfo`, `GetNetStats`,
`C_Spell.GetSpellInfo`, `C_Spell.IsSpellInRange`, `C_SwingTimer.EnableRangeCheck`,
`C_SwingTimer.IsTargetWithinSwingRange`, `C_Item.GetItemID`,
`C_TooltipInfo.GetInventoryItemByID`, `issecretvalue`.
**NOT in the pinned catalog** (WST calls them; each is a crash/nil risk — probe list §6):
`GetInventoryItemID`, `INVSLOT_RANGED`, `SPEED`, legacy `GetSpellInfo`, legacy
`IsSpellInRange`, `GameTooltip`/`SetItemByID`/`GameTooltipTemplate` (as declared symbols),
`CombatLogGetCurrentEventInfo` (CLEU, dead in their build), `hooksecurefunc`,
`JumpOrAscendStart`, `GetNetStats`'s 4th return value.
`Enum.PlayerSwingType {MainHand=0,OffHand=1,Ranged=2}` CAT ✓ (docs/hunter-tools.md table,
`SwingTimerDocumentation.lua:70`).

## 3. Mapping to Forte_Hunter (ours: `addon/Forte_Hunter/`)

| # | Behaviour | Ours | Evidence |
|---|---|---|---|
| B1 | Cycle anchor PLAYER_SWING | **done** | Tools.lua:184-191 (`OnSwingStart`, duration-first, Ranged filter, secret→speed→last chain); dispatch Tools.lua:392-394; tests test_hunter.lua:140-196 |
| B2 | Auto Shot on/off | **missing** | no `START/STOP_AUTOREPEAT_SPELL` anywhere in Forte_Hunter (grep 0) — no `shooting` state |
| B3 | Two phases + safe window | **missing** | tracker = single linear cycle (Tools.lua:219-231 `Progress` = fraction/remaining only); bar = one fill + text (Swing.lua:362-400) |
| B4 | Cast-event aim machine + retry | **partial** | we consume only `UNIT_SPELLCAST_SUCCEEDED` "Auto Shot" as a cycle **fallback** (Tools.lua:209-215, :384-391); no SENT/START/INTERRUPTED/FAILED_QUIET, no GUID keying, no 0.5 s retry |
| B5 | Readiness gate | **missing** | nothing gates the bar on target/attackable/moving (Tools.lua/Swing.lua) |
| B6 | Movement | **missing** | `PLAYER_STARTED/STOPPED_MOVING` unregistered; `GetUnitSpeed` unused (Tools.lua:406-421 registers SUCCEEDED/PLAYER_SWING/RANGE_UPDATE/REGEN only) |
| B7 | Feign Death | **missing** | no 5384/Feign path in Forte_Hunter (spell known: hunter.json pet_and_utility) |
| B8 | Legacy resets | done-minimal | the Auto Shot cast fallback is the one kept leg (Tools.lua:209-215); rest not needed |
| B9 | Aimed/Multi cast tracking | **partial, by design** | our own-cast rows are Forte_Timer's product (PLAN.md:540, iteration D `6670ce4`); the Hunter bar has no cast interlock; Multi-has-no-START law (Castbar.lua:200-205) is **not** recorded anywhere in our tree |
| B10 | Clip bar | n/a | WST ships it dead (§B10) |
| B12 | Latency strip | missing (by choice) | no GetNetStats use in our addon tree (grep 0) |
| B13 | Base speed/haste | **partial** | speed chain = event-duration→UnitRangedDamage→UnitAttackSpeed[3]→last, all `PlainOrNil`-guarded (Tools.lua:159-181); no base-speed/aim ratio, no UNIT_ATTACK_SPEED hook |
| B14 | Quiver | n/a (inherited) | B13 chain inherits quiver haste (§B14) |
| B15 | Readiness/traps | n/a | WST has none; traps = PLAN.md:318 own item |
| B16 | Range/dead-zone light | **missing** | `PLAYER_SWING_RANGE_UPDATE` consumed only as stop-gate (Tools.lua:198-204); no band indicator (PLAN.md:318 commits one) |
| B17 | Melee/target bars | n/a | out of product scope (§B17) |
| B18 | Config | **done-shape** | our option law: Pages/Hunter.lua:38-57 defaults, :96-152 sections, Swing.lua:463-486 KEYMAP/STORED, lock m4 law Swing.lua:279-293 |
| B19 | Wand path | n/a today | Hunter-gated product |
| B20 | Sounds | n/a | WST has none |

Bar skin (ours, for §5): 200×12 Aluminium fill on Background/Border backdrop, URW Gothic
10 OUTLINE, text = remaining tenths (`Swing.lua:56-88` skin, :131-143 format law,
:199-209 fill geometry); default fill = the Cooldown timeline's `Colors.Spell`
(1,.5,0) read from `FX.Cooldown.TimelineSkin` (Swing.lua:46-54); idle = hidden +
`OnUpdate(nil)` (Swing.lua:403-413); hidden-anchor `OnUpdate` trap fixed via synchronous
`StartTicking` render (Swing.lua:416-438, PLAN.md:453).

## 4. Gap table + verdicts + work order

Verdicts: **port** = new code in our tree; **adapt** = a WST implementation is worth
carrying as GPLv3-derived code (source cited; notice + change-mark + ATTRIBUTION entry);
**skip** = do not build (reason). "Shape" = our implementation sketch.

| Pri | # | Gap | Verdict | Implementation shape (ours) |
|---|---|---|---|---|
| 1 | B3 | **Aim window + safe-to-move window** — the headline | **port (adapting two formulas)** | `SwingTracker` gains `aimLen` (seeds at each `OnSwingStart`: `aimLen = 0.5 * duration / base` — **adapt** Hunter.lua:283-286 + GetAutoCastTime floor ladder :109-141 [GPLv3; WatchYourSixx]) and `base` (Pri 7); `Progress(now)` returns `fraction, remaining, phase` with `phase = "reload" | "aim"` around `remaining > aimLen`; floor-clamp law **adapt** :359-360 (the cycle never counts below the aim window). Bar (Swing.lua `Update` :362-400): fill = the **safe window** (`(remaining - aimLen)/duration` law from :688-696), a right-anchored **aim slice** (width `aimLen*scale`) shown only while `remaining <= aimLen` — colours §5. `Snapshot()`/`StatusLine` extend; tests extend test_swing.lua geometry + phase law. |
| 2 | B4 | **Auto Shot cast-event machine + 0.5 s retry penalty** | **port** | On the existing Tools event frame (`EnableEvents` :406-421) add SENT/START/FAILED_QUIET/INTERRUPTED (unit "player"); a `ShotCast` sub-state machine keyed by `castGUID` (seal via pcall+PlainOrNil string, never raw-compare — Tools.lua:339-352 law; the GUID-algorithm **pattern** is WST :465-473/:332-351, we re-express it). `shotPhase = aiming` starts on START (authoritative) / on cycle-floor arrival (inferred, dropped by B5 readiness); SUCCEEDED(guid-match) ends it **and stamps facts** (`attackable/inRange/!dead := true/true/false` — adopt :536-538, cheap and combat-safe); FAILED_QUIET ⇒ `retryUntil = now+0.5` + floor-raise (law :623-627); retry drawn §5. The "safe" white window (§5) turns on at SUCCEEDED — the event is *the* proof the projectile left. |
| 3 | B11/B4 | White-state display (projectile left) | **port** (visual of Pri 2) | Tracker reports `phase="flying"` between `SUCCEEDED` and the next cycle-floor arrival (i.e. reload time **after** a confirmed shot left; WST encodes "projectile left" as the whole non-aim span — README :22-24, so the first reload slice after SUCCEEDED is the flying/safe state; `auto_shot_ready` law :381-382); bar recolours §5; a Spark2 pulse rides the SUCCEEDED stamp (our pulse law Timeline:141,:1452-1467). |
| 4 | B5/B6 | **Readiness gate + movement** | **port (simplified)** | Register `PLAYER_STARTED_MOVING/STOPPED_MOVING/PLAYER_TARGET_CHANGED/PLAYER_ENTERING_WORLD` on the Tools frame (CAT ✓ all); `moving` flag; optional `GetUnitSpeed` cross-check **through PlainOrNil** + the ≥0.05 s sustained-pulse law **adapt** :150-154; `ready = not moving and shooting(B2) and target` + `pcall(C_SwingTimer.IsTargetWithinSwingRange, Ranged)` [probe-gated; nil = permissive]; gate only **draws**: aim slice suppressed while `not ready`, inferred aiming dropped (law :361-366), target-change clears facts (law :166-174). Full B16 range ladder is Pri 6. |
| 5 | B7 | **Feign Death reset** | **port (simplified)** | Name-keyed: our cast seam resolves "Feign Death" (hunter.json row; id 5384 = WST's, matches data) → `feignPending=true`; next `moving==true` (Pri-4 flag) → `OnSwingStart(knownDuration, Ranged)` re-arm (≡ :309-321 without the +0.15 fudge — keep a settings-free `firstShotStretch` ONLY if a launch probe shows the late first shot); clear on any other cast start (:488 law). Skip the jump hook: `hooksecurefunc`/`JumpOrAscendStart` not declared (§2) — probe `PLAYER_JUMP` presence; the movement leg covers jump-*away*. |
| 6 | B16 | **Range / dead-zone light** | **port (own, compact)** | New `UI/Range.lua` (10 Hz, own hidden driver frame — WST's hidden-anchor lesson + our Swing.lua:416-438 law): Hunter ladder = `C_SwingTimer.IsTargetWithinSwingRange(Ranged)` primary [probe]; spellbook rung `C_SpellBook.FindSpellBookSlotForSpell("Wing Clip"/"Scatter Shot"/"Hunter's Mark")+IsSpellBookItemInRange(...,"target")` (all CAT ✓, pcall+normalise true/1 law :77-84); max range `C_Spell.GetSpellInfo(75).maxRange` fallback 35 (data: 35); dead-zone = ranged-false && scatter-true; `CheckInteractDistance("target",4|1)` too-close vs too-far **after** a sim/client confirm (CAT ✓ declared, semantics WST-documented only). Bands + colours §5. Register `C_SwingTimer.EnableRangeCheck(Ranged,true)` while shown → unlocks the native `PLAYER_SWING_RANGE_UPDATE` 3-arg stop we already handle (Tools.lua:198-204; docs/hunter-tools.md probe 7, secrets-unknowns.md:456-458). |
| 7 | B13 | **Base speed for the aim ratio** | **port (minimal, no tooltip scan)** | Seed chain per cycle: (a) `base` learned from a clean pair — when `UNIT_ATTACK_SPEED`/`SPEED_UPDATE` (CAT ✓, register unit "player") mark quiet, sample `UnitRangedDamage` speed plain ⇒ `base` candidate = first plain speed where PLAYER_SWING durations show no haste delta `[INFERENCE]`; (b) `C_TooltipInfo.GetInventoryItemByID(ranged itemID).` speed field [probe — declares TooltipData, field census launch day]; (c) interim: `aimLen = 0.5` (no-haste reading, the :139 floor) until a base is known. **Do not port** the tooltip scan (undeclared `GetInventoryItemID`/`INVSLOT_RANGED`/`SPEED` — §B13 crash risk). The base-speed override rides the options page (one NUM, default 0 = auto). |
| 8 | B9 | **Cast interlock** (casting shots vs the cycle) | **port (gate only)** | On cast-SENT for names ∈ {Aimed Shot, Multi-Shot, Steady Shot} (cast-time set only) set `castingSpell` (name + live length via `UnitCastingInfo` pcall, NeverSecret anchor fields law :141-147 [adapt]); bar: freeze the fill at its frozen fraction + full-width aim colour = "this cycle is clipped", text = cast remaining (format law Swing.lua:131-143); clear on SUCCEEDED/FAILED/INTERRUPTED. **Skip** WST's own castbar frame — castable-shot rows are Forte_Timer's surface (PLAN.md:540). Carry the **finding**: Forever Multi-Shot emits SENT→SUCCEEDED, no START (Castbar.lua:200-205) → our interlock MUST open on SENT, not START. Steady ids from data (409957/437123), never 34120 (§B9). |
| 9 | B2 | **shooting flag (autorepeat)** | **port** | Tools frame registers START/STOP_AUTOREPEAT_SPELL (CAT ✓, no-payload); `shooting` gates the aim-slice draw + Pri-4 readiness; on the start edge, if `now - lastEvent` > one cycle, drop stale pins (law :433-442). Enables the honest idle law: stop firing ⇒ bar hides at cycle end even if the last cycle is mid-flight. |
| 10 | B18 | Config additions | **port (knobs only)** | New keys, Forte_Options law (Pages/Hunter.lua pattern): `ShowAimSlice` (default on), `ShowSafeWindow` (on — off = today's single-phase bar), `ShowRetry` (on), `InCombatAlpha`/`OutOfCombatAlpha` (defaults 1.0/0.0 — adopt WST's in/ooc alpha pair as the "in-combat only" mechanism, law :668-673; gate = `InCombatLockdown()` (CAT ✓, Tools.lua:50-56 uses it), not PLAYER_REGEN), `BaseSpeed` (Pri 7c). All ride the existing KEYMAP/STORED seams (Swing.lua:463-486) — no new plumbing. |
| 11 | B10 | Multi-Shot clip bar | **skip** | Dead in the reference (:711,:782,:1178); the safe-window state + Pri-8 interlock carry the signal. |
| 12 | B12 | Latency strip | **skip-until-probe** | The `GetNetStats` 4th-return read WST uses is not in the pinned declaration (§B12); probe the real return shape launch day; decide then. |
| 13 | B1/B17 | Melee MH/OH bars, target bar, parry haste | **skip** | Tank/rogue tools; no Hunter value (§B17); parry law (`UNIT_COMBAT` PARRY, -40 %/+20 % floor, Core.lua:410-448) noted for a future Warrior pass. |
| 14 | B8/B14/B15/B19/B20 | Legacy reset table, quiver rows, Readiness/traps, wand path, sounds | **skip** | Native-first (B8 note), inherited (B14), absent from WST (B15) / from our data pin (B19 `Shoot` row), not in WST (B20). |

**Order of work = Pri 1→10** (the owner's brief: safe-to-move window + clipping first).
Pri 1–3 are one cohesive tracker+bar change (phases, events, white state, retry);
Pri 4–5 the readiness/feign layer; 6 the range light; 7–9 the supporting legs; 10 exposes
it all. Every step: tests drive the **real event path** (test_swing.lua law, PLAN.md:455)
and fail on pre-change code; api_lint + gate; sim captures per state (§5).

**Attribution mechanics (per Main):** each adapted law/function carries a header note
`// derived from WeaponSwingTimer (c) WatchYourSixx — SixxFix build v1.60.2, GPLv3;
original WST by LeftHandedGlove; adapted <date>, changes: <…>` on the adapted file/section
(cited: Hunter.lua:109-141,:283-286,:353-398,:465-473,:604-631; Castbar.lua:200-205 [finding],
:136-165,:224-263; Range.lua:339-433 [reference only — we re-derive]; README.md:22-24 [law]);
`addon/Forte_Core/ATTRIBUTION.md` (exists; format precedent = its ForteXorcist/font
sections) gains a "WeaponSwingTimer SixxFix — adapted Lua law (GPLv3)" section
(owned by `HunterSwing2`). Visuals/textures stay ours (§5).

## 5. Visual spec — ForteXorcist Classic skin (no WST textures)

All parts/skins already vendored: `Aluminium.tga`, `Background.blp`+`Border.blp`
backdrop, `Spark2.blp` pulse, `Charcoal.tga`, URW Gothic (ATTRIBUTION.md:5-24;
Swing.lua:39-40,56-88). Palette = the Timeline category colours
(`Forte_Cooldown/UI/Timeline.lua:173-186`): Spell `(1,.5,0)`, Powerup `(0,.75,1)`,
Item `(1,1,0)`, Potion `(0,1,0)`, Buff/white `(1,1,1)`, Debuff/red `(1,0,0)`.
Text = `formatRemaining` tenths law (Swing.lua:131-143), right-aligned, white 0.90.

| State (tracker) | Bar look | Notes |
|---|---|---|
| idle | hidden + `OnUpdate(nil)` | existing law (Swing.lua:403-413); `shooting` off after cycle end hides at cycle end (Pri 9) |
| reload — safe window (pre-aim) | **current fill**: Aluminium, Spell tint `(1,.5,0)`; width = `(remaining − aimLen)/duration × Width` (the *safe* span shrinks toward the aim slice) | today's look minus the aim tail = WST's white-bar role, in our orange; the right aimLen-slice sits **dark** (backdrop, black 0.50) marking the stand-still zone |
| aiming window (stand still) | fixed **aim slice** at the right end, Aluminium tinted Debuff red `(1,0,0)`; safe fill at 0; text counts the aim | WST law "should stand still while … 'casting'" (README:24) — red = stop; suppressed while `not ready` (Pri 4) |
| projectile left — flying/safe | fill flips to Buff **white** `(1,1,1)` (Aluminium texture), **Spark2.blp ADD-blend pulse at the fill head**, alpha 1→0 linear over 1.0 s (our pulse law Timeline:141,:1452-1467), riding the `SUCCEEDED` stamp | this is our "turns white" moment (README:22-23) — event-proven, our skin; white text stays |
| retry (failed start) | **retry slice**: Item yellow `(1,1,0)` slice immediately left of the aim slice, width `min(0.5, retry)/scale`, counts down | = WST retry_bar role (:705-709) in our palette; `ShowRetry` gate |
| casting shot interlock | fill frozen at clip fraction, full-width aim-slice red (the cycle is clipped), text = cast remaining | Pri 8; Forte_Timer prints the cast name — the Hunter bar stays a number bar |
| out of range / dead-zone (Pri 6 light, slim strip below, same width) | band colour + band text, our palette: melee Debuff red / dead-zone Item yellow / ranged (8–max) Potion green `(0,1,0)` / far Powerup cyan `(0,.75,1)` / out-of-range Charcoal grey ~`(0.55,.55,.55,1)`; text `"8-35"`, `"5-8 DEAD"`, `"OUT"` URW Gothic 10 OUTLINE | WST's ladder (Range.lua:339-433) in ForteXorcist colours; hide per `Lock`/`hide_no_target` equivalents |
| combat alpha | `InCombatAlpha 1.0` / `OutOfCombatAlpha 0.0` on the anchor | adopt WST's pair as the in-combat-only law (§B18) |
| target-loss / stop | existing idle law; no mid-cycle vanish | swings only run while shooting (B1) |

No new texture files; no WST `Images/*`; no WST fonts (`FRIZQT__.ttf` not shipped);
colours are settings keys (`BarColor` stays the reload tint; aim/retry/safe slices ride
fixed palette defaults, `ShowAimSlice/ShowSafeWindow/ShowRetry` gate).

## 6. Open questions / launch-day probes (hunter char)

1. PLAYER_SWING reachability for third-party addons (our probe list #1 already
   — docs/hunter-tools.md; `secrets-unknowns.md:451-461`); confirm `swingType==2` cadence
   while Auto Shot fires; does **wand Shoot** swing fire Ranged swings (B19)?
2. Auto Shot cast-event ladder: does SENT/START/`FAILED_QUIET` fire on Auto Shot starts /
   move-cancels (the 0.5 s penalty is classic-law; the event pair is the proof, B4)?
   Confirm the Multi-Shot **no-START** law (Castbar.lua:200-205) in the sim too.
3. `C_SwingTimer.EnableRangeCheck(Ranged,true)` / `IsTargetWithinSwingRange` runtime
   behaviour for addons (CAT-declared; `addonAccess: unknown`); after enabling, does
   `PLAYER_SWING_RANGE_UPDATE(checksRange=true)` arrive (our stop-gate then goes live)?
4. `GetNetStats` real return shape (4th `latency`?) — gates the B12 revisit.
5. `GetInventoryItemID`/`INVSLOT_RANGED`/`SPEED` existence (does WST's base-speed scan
   survive on the client at all?); `C_TooltipInfo.GetInventoryItemByID` field census
   (weapon Speed field on `TooltipData`?) — gates Pri-7 seed (b).
6. `UNIT_ATTACK_SPEED("player")` fires on quiver/trinket haste in/out? `SPEED_UPDATE` on
   speed auras? (Pri 4/7 refresh hooks.)
7. Feign Death: first shot after the FD reset arrives +~0.15 s late (WST's fudge, B7)?
   `hooksecurefunc`/`JumpOrAscendStart`/`PLAYER_JUMP` presence (jump-out coverage)?
8. In-combat `UnitRangedDamage` speed secrecy on this client (the B3 seed floor) and
   `GetUnitSpeed` secrecy (the B6 pulse-fallback's necessity).
9. Aim-window constant: is the pre-fire windup exactly 0.5 s (× haste ratio) on
   16001 server rules, per shot class (bow vs gun vs wand)? (B3/B13 formulas.)
10. Steady Shot live cast = 1500 ms (437123) vs the 2000 ms WST-era table — Pri 8 set +
    Forte_Timer data check.
