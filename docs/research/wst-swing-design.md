# WeaponSwingTimer SixxFix — swing/cast/melee design map vs ForteXorcist (Iteration J, row J1)

Reference tree: `/tmp/wst/src/WeaponSwingTimer/` (Forever build v1.60.2, GPL-3.0; © WatchYourSixx,
original WST by LeftHandedGlove — credited `Forte_Core/ATTRIBUTION.md:38-49`). Ours:
`addon/Forte_Hunter/` @ this repo. Every WST line reference below was opened and read in this
session; every catalog verdict was produced by loading the pinned
`docs/api/wow-addon-api-agents/skills/*/references/generated/forever.json` (the same loader
`scripts/api_lint.py` uses).

## Bottom line (answer first)

1. **WST's Hunter bar is one frame with 4 overlapping segments** (shot / cast / retry /
   clip) whose *widths* are pure functions of one `scale = width / max(weapon_speed,
   cast_time + 0.5)` (`WeaponSwingTimer_Hunter.lua:684`). `one_bar` changes **exactly one
   expression** — the shot (white/safe) segment's width formula (`:691-696`) — and one
   anchor for the dead clip bar (`:768-772`). Everything else (the red right-end cast block,
   the orange retry block, the text, the alpha pair, the frame's geometry) is
   **identical in both modes**. So "one-bar vs split-bar" is a *fill-direction* choice on one
   segment, not two layouts.
2. **`classic_bars` is a texture swap and nothing else** — `Images/Bar` vs `Images/Background`
   on the shot + cast segments (`:760-766`); the melee panel does the same swap
   (`WeaponSwingTimer_Player.lua:388-394`, `:420-426`). Colour, geometry, behaviour: unchanged.
3. **Two of the advertised weaving aids are dead code in this build**: the Multi-Shot clip bar
   is `Hide()`-n on every update (`:711`) and on every settings change (`:754`, `:782`), its
   checkbox is hidden at creation (`:1178`) and its colour picker hidden (`:1197`); the
   GCD-spark option names a widget the file never creates (`:873` — the one occurrence of
   `show_gcd_spark` in the tree, and it is not in the defaults `:61-83`). The in-panel
   "Bar Explanation" legend is created, given no texture, and hidden (`:1200-1207`,
   `:897-898`); the explanation PNGs in `Images/` are **referenced by no code** in this
   build.
4. **The live weaving surface is three bars + one number**: the ranged bar's white span
   (= safe to move/cast), the ranged bar's red right-end block (= stand still, the shot is
   being aimed), a *separate* cast bar for Aimed/Multi/Steady (`WeaponSwingTimer_Castbar.lua`),
   and the main/off-hand swing bars (`WeaponSwingTimer_Player.lua`) which Raptor Strike
   resets on success (`WeaponSwingTimer_Core.lua:35-39`, `:70-82`). The Hunter's real
   weaving arithmetic is `cycle − aim` vs the 1.5 s GCD (data: `Data/Hunter.lua:63` Raptor
   Strike `gcdMs=1500`, `:60` Mongoose Bite `gcdMs=1500`).
5. **Our bar is already WST's split mode in spirit** (the safe span shrinking toward a red
   aim region: `UI/Swing.lua:958-962`, `:1031-1040`) **plus** two states WST has no visual for
   (the event-proven white "projectile left" fill `:955-957` and the cast-interlock
   full-width red `:1027-1029`). Missing: the fills-left-to-right mode, the *standing*
   right-end aim region (our bar leaves it as bare backdrop), the clip / GCD "act-by-this-line"
   markers, melee swing rails, and the latency strip (probe-gated by design).
6. **Proposed shape** (§7): one `s.SEL` mode picker (`BarMode`, default
   `"safe"` = today's pixels, the current geometry untouched) + a standing
   `ShowAimWindow` + a `ShowClipRegion` + a `ShowWeaveLine` (the 1.5 s-GCD act line, WST's
   paladin-marker law applied to the Hunter's GCD) + an opt-in, range-gated melee swing rail
   (new `Core/Melee.lua` + `UI/Melee.lua`) + the probe-gated latency strip. **Four new rows,
   one replacement** — ranked by the rotation decision each one answers (§7.0). Three
   file-disjoint slices (§7.8), each with an exact acceptance; every Forever API in the design
   is catalog-checked in §7.7. No WST style, texture or skin is proposed anywhere.
7. **Do not copy**: WST's `COMBAT_LOG_EVENT_UNFILTERED` dispatch (`Core.lua:486-490`,
   `Hunter.lua:500-501`, `Castbar.lua:326-349` — blocked on this client per `Core.lua:355-357`
   and forbidden by our AGENTS law), `GetInventoryItemID`/`INVSLOT_*` base-speed scan
   (`Player.lua:50`, `:57`), `hooksecurefunc`/`JumpOrAscendStart` (the jump-out leg, prior
   survey §B7), hard-coded spell-ID sets (`Castbar.lua:14-52` — Steady 34120 has no Forever
   row; `Steady Shot` = 437123/409957 in the pinned data), the profile system, and the skin.
8. **Everything needed exists on Forever**: `PLAYER_SWING (swingDuration, swingType)`
   (`SwingTimerDocumentation.lua:42`), `Enum.PlayerSwingType` MainHand=0/OffHand=1/Ranged=2
   (`:70`), `UnitAttackSpeed → (attackSpeed, offhandAttackSpeed, rangedAttackSpeed)`
   (`UnitDocumentation.lua:681`), the `UNIT_SPELLCAST_*` family (`:4727`-`:4802`),
   `C_SwingTimer.EnableRangeCheck/IsTargetWithinSwingRange` (`SwingTimerDocumentation.lua:10`,`:22`),
   `GetNetStats (in, out, latencyList)` (`ConnectionDocumentation.lua:39`) — with one
   declared-shape caveat: WST reads a **4th** `GetNetStats` return (`Castbar.lua:184`,
   `:486`) that the catalog does not declare.

---

## 0. Method and evidence law

* **Facts** carry a `file:line` inside `/tmp/wst/src/WeaponSwingTimer/` (WST) or
  `addon/Forte_Hunter/…` (ours), or a catalog `Source.lua:line`. §7 is the only proposal.
* **Geometry is code-derived.** Image/vision reads were attempted on
  `Images/HunterBarExplainedFullAlpha.png` (1024×256) and `Images/HunterOneBarExplainedAlpha.png`
  (512×256) and are not available in this session — and both art files turned out to be
  unreferenced by any code in this build (§2.7), so no claim here rests on them.
* `[INFERENCE]` marks a reading beyond the code.
* The prior scout note `docs/research/weaponswingtimer.md` owns the *behaviour* survey
  (rows B1–B20, gap table Pri 1–14, §5 palette, §6 probes). This note does not repeat it: it
  covers (a) the **geometry** of every bar per mode, (b) the **full option inventory**,
  (c) the **weaving** reading model, (d) the current-state mapping and (e) the design. A
  `B-rows`/`Pri n` citation means that note's rows.

---

## 1. The bar family (what frames exist, who feeds them)

Five independent top-level frames under `UIParent`, each movable/lockable, each with its own
backplane, its own settings table and its own `UpdateVisualsOnUpdate` +
`UpdateVisualsOnSettingsChange` pair:

| Frame | Created | Fed by | Driver |
|---|---|---|---|
| `WeaponSwingTimerHunterAutoshotFrame` (ranged shot bar) | `Hunter.lua:815-846` | `shot_timer`, `auto_cast_*`, `auto_delay_timer` | one core `OnUpdate` (`Core.lua:196-201`) |
| `WeaponSwingTimerHunterCastbarFrame` (shot cast bar) | `Castbar.lua:581-620` | `cast_time` / `cast_timer` | `Castbar.lua:315-325` |
| melee player frame (main + off bar) | `Player.lua:503-545` | `main_swing_timer`, `off_swing_timer` | `Player.lua:105-142` |
| target swing frame | `Target.lua` (out of Hunter scope) | target timers | — |
| `WeaponSwingTimerRangeFrame` (range band light) | `Range.lua:622-690` | `GetRangeBand()` | a hidden 10 Hz driver (`Range.lua:651-656`, `:623-632`) |

Settings are per-profile (`Config.lua:88-95`) with a `RestoreAllDefaults`
(`Core.lua:92-96`); every widget writes the settings table then calls
`UpdateVisualsOnSettingsChange()` — the two-function law our `KEYMAP`/`ApplySettings` seam
mirrors (`UI/Swing.lua:1219-1228`).

The panels register under the client Settings canvas as `WeaponSwingTimer` →
{`Melee Settings`, `Ranged Settings`, `Range Check Settings`, `Profiles`}
(`Config.lua:30-95`); `Ranged Settings` stacks the Hunter panel (`Hunter.lua:1010`) above the
cast-bar panel (`Castbar.lua:726`, registered at `Config.lua:46-63`).

---

## 2. Deliverable 1 — one Auto Shot cycle, segment by segment, in both modes

### 2.1 The state that feeds the pixels

All four segments are drawn from five numbers, all maintained in seconds:

| Number | Meaning | Maintained at |
|---|---|---|
| `range_speed` | this cycle's length (the `PLAYER_SWING` duration) | `Hunter.lua:287` (re-pinned every Ranged swing) |
| `shot_timer` | seconds left in the cycle, clamped to never go below the windup | `Hunter.lua:358` (`math.max(shot_timer - elapsed, cast_time)`) |
| `cast_time` | the windup/aim window for **this** cycle: `0.5 × speed / base` | `Hunter.lua:127` (live), `:284` (the per-cycle pin) |
| `cast_remaining` | while the shot's aim is live: `min(shot_timer, cast_time)`; else the static `cast_time` | `Hunter.lua:657` |
| `delay_timer` | the retry countdown (0.5 s), shown only when `show_autoshot_delay_timer` | `Hunter.lua:655-656`; armed 0.5 s at `:628`, drains at `:379-382` |

The cycle model (`PLAYER_SWING` → `shot_timer = duration`, the Ranged-only filter, the
aim-length pin `0.5 × duration / base`) is `Hunter.lua:261-293`; the 0.5 s constant is
`Hunter.lua:95`, with the comment that it is deliberately *not* the swing timer. The windup
length ladder (live read → cache → `0.5 / (1 + haste/100)` → `0.5`) is
`Hunter.lua:109-141`; quiver haste rides the speed read (comment `:108`).

### 2.2 The one scale every width rides

```
weapon_speed = UnitRangedDamage("player")            -- secret/falsy → last good, then range_speed
if native_cycle_speed      then weapon_speed = native_cycle_speed end      -- PLAYER_SWING duration
if auto_cast_visual_speed  then weapon_speed = that end                    -- while aiming
scale          = width / max(weapon_speed, cast_time + auto_delay_duration)  -- 0.5 (Hunter.lua:95)
cast_width     = cast_time   * scale
retry_width    = delay_timer * scale
cooldown_width = max(0, width - cast_width)
progress       = clamp((range_speed - shot_timer) / range_speed, 0, 1)
```
`Hunter.lua:671-690` (verbatim block read at `:676-690`). Two properties matter:

* The scale is **weapon-speed based, not `PLAYER_SWING`-duration based** — the comment at
  `:673-676` says PLAYER_SWING durations "can include resets/delays and must not move the
  cast boundary". In a clean cycle the two are the same number; under a Raptor Strike /
  Feign reset they are not.
* `max(…, cast_time + 0.5)` in the denominator guarantees a hasted cycle never scales the
  windup + retry past the bar.

### 2.3 Split mode (`one_bar = false`, the shipped default `:79`) — the cycle walked

Bar = one frame `width × height` (defaults 300 × 12, `:62-63`), black backdrop
(`backplane_alpha 0.5`, `:72`, `:725-738`), `frame:SetSize(width, height)` each update (`:713`).

| Segment | Layer | Anchor | Width | Colour (default) |
|---|---|---|---|---|
| `shot_bar` (reload / "white") | `ARTWORK` | `BOTTOMLEFT` (`:741`) | `min(cooldown_width, max(0, shot_timer − cast_time) × scale)` (`:695`) | `cooldown_*` = .95,.95,.95,1 (near-white, `:80`) |
| `auto_shot_cast_bar` (aim / windup) | `OVERLAY` | `BOTTOMRIGHT` 0 (`:701`, `:748-752`) | `cast_remaining × scale` (`:703`) | `auto_cast_*` = .8,0,0,1 (red, `:81`) |
| `retry_bar` (delay) | `OVERLAY` | `BOTTOMRIGHT` at `−cast_width` (`:705-707`) | `delay_timer × scale` (`:708`) | fixed `(1,.5,0,1)` orange (`:843-844`) |
| `multishot_clip_bar` | `OVERLAY` | `BOTTOM` centred in split mode (`:769`) | — never computed (dead, §2.7) | `clip_*` = 1,0,0,.7 (`:82`) |

Over one cycle (worked numbers: `width=300`, `weapon_speed=2.0`, `cast_time=0.5`
⇒ `scale=150`, `cast_width=75`, `cooldown_width=225`):

1. **Reload** (`shot_timer` 2.0 → 0.5). `shot_bar` is the whole left field: 225 px at the cycle
   start, its **right edge receding leftward** as the cycle burns, hitting 0 exactly when
   `shot_timer == cast_time`. It is `SetShown(white_width > 0)` (`:697`) so it disappears
   rather than reaching 0. The red block sits **static** at the right end
   (`cast_remaining = cast_time` while not aiming, `:657`) — a standing "the shot is coming"
   block. The text reads `shot_timer` (`:659-663`).
2. **The aim / windup** (the last 0.5 s). The countdown is clamped at the floor (`:358`) and
   the visual `shot_timer` is *replaced* by `auto_cast_remaining` while the aim is live
   (`:650-652`), so the red block, still anchored at the right, **drains into the right
   edge** (`:703`). The white bar is already gone. The text reads the aim countdown.
3. **The shot leaves** (`UNIT_SPELLCAST_SUCCEEDED`, `:514-…`); the next `PLAYER_SWING`
   re-pins (`:261-293`) and step 1 restarts. There is **no distinct "in flight" visual** in
   WST: the flight *is* the white/reload span (§2.6).
4. **A rejected start** (`UNIT_SPELLCAST_FAILED_QUIET`, `:604-637`): the 0.5 s
   `auto_delay_timer` arms (`:628`), the floor is raised (`:629-631`), and the orange
   `retry_bar` appears **immediately left of the standing red block**
   (`BOTTOMRIGHT −cast_width`, `:707`) shrinking rightward — the comment at `:706` is
   literal: "Retry always ends at the fixed START of the full cast segment."
   `show_autoshot_delay_timer = false` suppresses only the *display* (`:655-656`), not the
   floor raise.

Reading the split bar: **the left white field is the room you have; the red right block is
the wall.**

### 2.4 `one_bar` mode (the "YaHT / One bar" option) — the cycle walked

Same frame, same segments, same red block, same retry block, same text. One formula differs:

```
white_width = min( width − cast_remaining × scale ,  width × progress )     -- :691-694
```

* `shot_bar` anchor: `BOTTOMLEFT` (`:743` — the split and one-bar branches set the same
  anchor; the mode difference is purely the width law, `:739-745`).
* **Reload**: the fill **grows from the left** as `progress` runs 0 → 1, capped by
  `width − cast_remaining·scale`, i.e. it stops at the standing red block's left edge
  (300 − 75 = 225 px at the worked numbers, reached at `progress = 0.75`).
* **The aim / windup**: `cast_remaining` starts shrinking, the cap opens 225 → 300 and
  `width × progress` follows it — the code comment's "Once the cast begins, white follows
  the shrinking red edge" (`:692`). The fill reaches full width exactly as the shot leaves,
  and the two never overlap.
* **The retry**: same anchor, same width as split mode (`:705-709`) — in `one_bar` it lands
  inside the growing field, immediately left of the standing red block.
* **Text**: identical fold (§2.6). The checkbox's own tip is the only prose the build has on
  the mode: "Changes the Autoshot timer to a bar that fills from left to right"
  (`:1051-1058`).

### 2.5 The two modes side by side

| Question | split (`one_bar=false`, default) | `one_bar=true` |
|---|---|---|
| Which side does the safe/reload fill grow from? | none: it **shrinks**, its right edge receding leftward from a full left field | grows left→right from an empty bar |
| Which part is static all cycle? | the red aim block, right end (width = the full windup) | the red aim block, right end (identical) |
| At the moment the player must stand still | the fill has just vanished (width 0) | the fill is at `width − cast_width` and starts chasing the red edge |
| Overlaps | red ⊂ [W−cast_width, W]; retry ⊂ [W−cast_width−retry_width, W−cast_width] — disjoint | fill ⊂ [0, W−cast_remaining·scale] — disjoint from the red block by construction |
| What the eye tracks | a *disappearing* left field (a countdown) | a *growing* left field (a fill) |
| Extra clip / ready markers | none | none |

### 2.6 The text, the alpha pair, the "white" law

* Text = `string.format("%.1f", displayed_timer)` on `shot_bar_text` (`:663`), anchored
  `BOTTOMRIGHT −5` inside the bar (`:755`), white, gated by `show_text` (`:784-788`),
  `fontsize` 12 (`:64`). `displayed_timer` folds the retry in: `cast_remaining + delay_timer`
  when a retry is open, else `shot_timer`; and with Auto Shot off and the timer spent it
  prints the windup (`:659-662`). That fold is the same number our aim-phase text prints
  (`UI/Swing.lua:1046-1056`).
* Frame alpha: `in_combat_alpha` (1.0) while `core.in_combat or shooting or casting_shot`,
  else `ooc_alpha` (**default 0.0** ⇒ the bar is invisible out of combat, `:670-674`,
  defaults `:70-71`). `core.in_combat` is fed by `PLAYER_REGEN_DISABLED/ENABLED`
  (`Core.lua:456-459`) — which is why we gate on the declared `InCombatLockdown()`
  (`UI/Swing.lua:1085-1095`).
* The README law (`README.md:21-24`): "the shot bar turns white when the projectile leaves
  the player. While the bar is white, the player can move and cast freely without
  clipping… When the white bar is depleted, the player should stand still." In this build the
  white bar's colour is *constant* (`:671-672` repaints `cooldown_*` every update), so the law
  is implemented as **the white bar's presence/width = the projectile is out** (split mode: it
  exists only during the reload; `one_bar`: from the first elapsed second). `[INFERENCE]` on
  the classic-WST origin; the code facts are the constant colour and the width laws above.

### 2.7 What is dead / vestigial in this build (verified)

| Thing | Evidence | State |
|---|---|---|
| Multi-Shot clip bar | `Hide()` every update `:711`; in the settings path the `show_multishot_clip_bar` branch can `Show()` it (`:776-780`) and `:782` hides it again; checkbox created then hidden `:1170-1178`; colour picker hidden `:1191-1197`; **no width is ever computed for it** (no `SetWidth`/`SetSize` in the file) | **dead** |
| GCD spark | `spell_GCD`/`spell_GCD_Time` computed (`:392-397`, armed `:494-497`), never drawn; `panel.show_gcd_spark_checkbox:SetChecked(settings.show_gcd_spark)` at `:873` — the widget is never created and the key is absent from the defaults (`:61-83`), so `UpdateConfigPanelValues` indexes a nil field (latent nil-index on the panel-open path) | **vestigial + latent defect** |
| Panel legend ("Bar Explanation") | created `:1199-1206`, `Hide()`d at `:897-898` and `:1206-1207`, never given a texture; the explanation art (`HunterBarExplainedFullAlpha`, `HunterOneBarExplainedAlpha`, `OneBarShotBar`, `YaHTShotBar`, `MeleeBars`) has **zero** code references (scan of every `.lua`/`.toc`/`.xml` for `Images/`: only `Background`, `Bar`, `Border`, `Spark`, `LandingPage` appear) | **dead** |
| Wand `Shoot` shared path | 5019 handled (`:56-59`, `:575-581`) on the same bar; the class gate includes MAGE/PRIEST/WARLOCK | shared path (prior note B19) |

---

## 3. Deliverable 2 — every WST option (key, default, label, what it changes)

Labels/tips verbatim from the panel factories; defaults from each module's
`default_settings`.

### 3.1 Ranged / Hunter bar (`Hunter.lua:61-83`, panel `:1010-1211`)

| Key | Default | Panel label | What it changes |
|---|---|---|---|
| `enabled` | `true` | "Enable" — "Enables the Autoshot/Shoot bars." (`:1024-1031`) | the whole Hunter frame; off ⇒ `frame:Hide()` (`:792`) |
| `show_border` | `false` | "Show border" (`:1033-1040`) | backdrop `edgeFile = Images/Border` vs `nil` (`:725-737`) |
| `classic_bars` | `true` | "Classic bars" — "…classic texture for the shot bars." (`:1042-1049`) | texture swap `Images/Bar` vs `Images/Background` on `shot_bar` + `auto_shot_cast_bar` (`:760-766`); nothing else |
| `one_bar` | `false` | "YaHT / One bar" — "…a bar that fills from left to right" (`:1051-1058`) | the shot-segment width law (§2.4) + the dead clip bar's anchor (`:768-772`) |
| `show_text` | `true` | "Show Text" (`:1060-1067`) | `shot_bar_text:Show/Hide` (`:784-788`) |
| `width` | 300 | "Bar Width" (`:1069-1076`) | frame width ⇒ the scale |
| `height` | 12 | "Bar Height" (`:1078-1085`) | frame / segment height |
| `fontsize` | 12 | "Font Size" (`:1087-1094`) | text font |
| `x_offset` / `y_offset` | 0 / −260 | "X/Y Offset" (`:1096-1113`) | frame anchor (`:722`); drag-saved, snapped to 0 within ±20 (`:800-813`) |
| `in_combat_alpha` | 1.0 | "In Combat Alpha" (slider 0..1 step .05, `:1134-1143`) | frame alpha in combat (`:670-674`) |
| `ooc_alpha` | **0.0** | "Out of Combat Alpha" (`:1145-1152`) | frame alpha out of combat |
| `backplane_alpha` | 0.5 | "Backplane Alpha" (`:1155-1162`) | backdrop alpha (`:738`) |
| `cooldown_*` | .95,.95,.95,1 | "Auto Shot Cooldown Color" (`:1115-1123`) | the safe/reload segment colour (`:671-672`) |
| `auto_cast_*` | .8,0,0,1 | "Auto Shot Cast Color" (`:1125-1132`) | the aim/windup block colour |
| `clip_*` | 1,0,0,.7 | "Multi-Shot Clip Color" (hidden `:1191-1197`) | the dead clip bar |
| `show_multishot_clip_bar` | `true` | "Multi-Shot clip bar" (hidden `:1170-1178`) | the dead clip bar |
| `show_autoshot_delay_timer` | `true` | "Auto Shot delay timer" (`:1180-1187`) | gates the retry segment's *display* only (`:655-656`) |
| `is_locked` | `false` | (no checkbox; the drag law) | `EnableMouse` + `StartMoving` gate (`:822-826`) |
| `point` / `rel_point` | CENTER / CENTER | — | drag-saved anchor (`:807-812`) |
| — (no key) | — | `show_gcd_spark` (referenced at `:873` only) | nothing — the widget was never created (§2.7) |

### 3.2 Shot cast bar (`Castbar.lua:56-76`, panel `:726-830`)

Defaults: `enabled=true`, 300×12, font 12, CENTER/CENTER 0/0, `in_combat_alpha=1.0`,
`backplane_alpha=0.5`, `show_cast_text=true`, `show_aimedshot_cast_bar=true`,
`show_multishot_cast_bar=true`, `show_steadyshot_cast_bar=true`,
`show_latency_bars=false`, `show_border=false`. No `ooc_alpha` (commented out at `:64`).

| Key | Panel label | What it changes |
|---|---|---|
| `show_aimedshot_cast_bar` | "Aimed Shot cast bar" (`:754-761`) | gates Aimed Shot on this bar (`:130-131`, `:373-381`, `:402-410`, `:432-440`) |
| `show_multishot_cast_bar` | "Multi-Shot cast bar" (`:745-752`) | same, Multi-Shot |
| `show_steadyshot_cast_bar` | "Steady Shot cast bar" (`:763-770`) | same, Steady 34120 (no Forever row — §7.9) |
| `show_latency_bars` | "Latency bar" — "…latency on cast bar." (`:772-779`) | inflates `cast_time` by `latency/1000` at cast start (`:183-187`) **and** shows the red left strip (§4.2) |
| `show_cast_text` | "Show Cast Text" (`:736-743`) | the right countdown + the centre "Failed"/"Interrupted" word (§4.2) |
| width / height / fontsize / offsets / border / alpha | as the Hunter panel | frame geometry (`:774-830`) |

Panel title "Player Spell Bar Settings" (`:731-734`); the frame's own visibility gate is
"any of the three cast-bar keys on **and** class == HUNTER" (`:509`).

### 3.3 Melee player bars (`Player.lua:16-42`, panel `:731-929`) — the weaving half

Defaults: `enabled=true`, 300×12, font 10, CENTER/CENTER, `is_locked=false`,
`show_left_text=true`, `show_right_text=true`, `show_offhand=true`, `show_border=false`,
`classic_bars=true`, `fill_empty=true`, main `0.1,0.1,0.9,1` (blue), off `0.1,0.1,0.9,1`,
white text colours, `pala_show_blood=false`, `pala_show_command=false`, `pala_offset=6`.

| Key | Panel label (verbatim tip where distinctive) | What it changes |
|---|---|---|
| `enabled` | "Enable" — "Enables the player's swing bars." (`:736-742`) | both bars |
| `show_offhand` | "Show Off-Hand" (`:744-750`) | the off bar + its texts; also the frame-height rule (`:352-356`) |
| `show_border` | "Show border" (`:752-758`) | backdrop edge file |
| `classic_bars` | "Classic bars" (`:760-766`) | `Images/Bar` vs `Images/Background` on both bars (`:388-394`, `:420-426`) — **and** it gates the spark (`:302-306`) |
| `fill_empty` | "Fill / Empty" — "Determines if the bar is full or empty when a swing is ready." (`:768-774`) | inverts both widths (`:295-299`, `:333-335`) |
| `show_left_text` | "Show Left Text" (`:776-782`) | "Main-Hand"/"Off-Hand" labels (`:432-443`) |
| `show_right_text` | "Show Right Text" (`:784-790`) | the tenths counters (`:445-456`) |
| `pala_show_blood` | "Show Paladin Twist" — "Show 0.4s marker before swing to help with seal twisting. Apply seal after this." (`:792-798`) | the pale 1-px vertical line at `width − width·(0.4/speed)` (`:285`, `:307`, `:398-400`) |
| `pala_show_command` | (the paladin GCD marker row) | the red 1-px line at `width − width·(gcd/speed)`, `gcd = GetSpellInfo(19750)` clamped ≤ 1500 ms (`:286-290`, `:308`, `:405-407`) |
| `pala_offset` | "Paladin Marker offset" slider (`:918-926`) | the markers' overshoot: height `height + 2·offset` (`:399`, `:406`) |
| width / height / font / offsets / alphas / colours | as the Hunter panel | geometry + the two bar colours (`:678-681` for the text colours) |

### 3.4 Range check light (`Range.lua:14-41`, panel `:933-1141`)

Defaults: `enabled=false` (opt-in — the law our `ShowRangeLight` copies), 300×12, font 10,
`text_melee "0-5 yd  •  MELEE"`, `text_deadzone "5-8 yd  •  DEAD ZONE"`, `text_close "8-15 yd"`,
`text_ranged "8-35 yd"`, `text_far "35-100 yd"`, plus the out/unknown rows,
`show_border=false`, `classic_bars=true`, per-band colour triples (melee .85,.2,.2 ·
deadzone 1,.9,.1 · close .95,.75,.1 · ranged .2,.75,.2 · far .35,.55,.9 · out .55,.55,.55 ·
unknown .65,.65,.65; `:32-40`), `hide_no_target` / `hide_dead_target` (`:1108-1116`), six
editable band texts (`:1118-1140`). Drawing: one full-width bar re-tinted per band + a centred
string (`:673-685`, `:579-623`), 10 Hz (`:625-632`).

---

## 4. Deliverable 3 — the weaving aids and how a player reads them

The Hunter's weaving problem in one sentence: the ranged swing runs on its own; an *instant*
shot (Raptor Strike, Mongoose Bite) fits between Auto Shots if the cycle minus the
stand-still window is ≥ the 1.5 s GCD; a *cast-time* shot (Aimed, Steady) fits only if the
whole cast lands before the windup begins; Raptor Strike additionally **resets the main-hand
swing** (§4.3), which is the reward for standing in melee range.

### 4.1 The ranged safe window (the primary aid)

`shot_bar` (§2.3/§2.4). Split mode: the left field burning down **is** the safe window — start
a cast while it exists and the shot is already out; when it is gone you are inside the
stand-still window. `one_bar`: the growing field is the same quantity, read as progress.
Nothing gates it on target/movement: the readiness gate (`CanBeginAutoVisual`, `:182-215`)
governs the *aim inference* (`:361-366`), never the drawing (the shot bar's width rides
`shot_timer` unconditionally, `:695`).

### 4.2 The shot cast bar (`Castbar.lua`)

A separate frame ("Player Spell Bar Settings") tracking **Aimed / Multi / Steady** casts:

* Arming: `UNIT_SPELLCAST_START` for the gated names, and **also** on
  `UNIT_SPELLCAST_SENT` (the Multi-Shot START-never-arrives law; prior note B9,
  `Castbar.lua:200-221`). The length is adopted from `UnitCastingInfo("player")`'s live
  `start_time_ms`/`end_time_ms` (`:142-146`), with the hard-coded per-rank `cast_time` table as
  the fallback (`:14-52`).
* Drawing: `spell_bar` anchored `TOPLEFT` (`:531`) with width
  `width × (cast_timer / cast_time)` ⇒ **fills left→right** as the cast burns
  (`:456-461`); gold `(0.8,0.64,0)` while casting (`:458`); a 16×h `Images/Spark` rides the
  fill head (`:462-467`, `:605-609`).
* Outcomes: success ⇒ full-width **green** `(0,0.5,0)` + text `0.0` (`:372-381`); failure ⇒
  full-width **red** `(0.7,0,0)` + the centre word "Failed" (`:395-411`); interrupt ⇒ the same
  with "Interrupted" (`:424-444`). A cast with no completion event within
  `cast_time + 0.5` self-fails (`:302-309`).
* Pushback: `UNIT_SPELLCAST_DELAYED` adopts the live `start`/`end` and `delay_time_ms`
  (`:220-263`) — the modern replacement of the combat-log path.
* Reading it against the ranged bar: the cast bar's remaining is what must fit inside the
  ranged bar's safe window. WST gives **no combined view** — the two frames are placed by
  hand, which is exactly the placement problem our interlock removes (§7.3, §7.4).

### 4.3 The melee swing bars (main / off)

* Per-slot cycle: `PLAYER_SWING(duration, swingType)` arms `main_swing_timer` /
  `off_swing_timer` from the event duration (`Player.lua:81-102`), drained every frame
  (`:202-222`); `UnitAttackSpeed("player")` is read **per slot** — 1st return = main
  (`:215-224`), 2nd return = off (`:244-264`); an off-hand speed of 0/nil ⇒
  `has_offhand = false` (`:255-259`).
* Geometry: `main_bar` `TOPLEFT`, `off_bar` `BOTTOMLEFT` (`:385`, `:419`) inside a frame of
  height `height` (one bar) or `height × 2 + 2` (both, `:352-356`) — a 2-px stack.
* Width law: `w = min(width − width·(timer/speed), width)` ⇒ **fills left→right, full = the
  swing is ready** under the default `fill_empty=true` (`:16`, `:280`);
  `fill_empty=false` inverts it (`:295-299`, `:333-335`) = "empties toward ready".
* Spark: a 16-px `Images/Spark` riding the fill head (`:301`, `:337`), **shown only while
  `classic_bars` is on and the bar is mid-swing** (`:302-306`, `:338-342`).
* Texts: left "Main-Hand"/"Off-Hand"; right = the remaining tenths
  (`:310-311`, `:343-344`, `:456-460`).
* **The "act by this line" law**: the paladin pair are exactly that — 1-px lines (taller than
  the bar by `pala_offset`) planted at the moment-by-which-an-action-is-due:
  `width − width·(0.4/speed)` and `width − width·(gcd/speed)` (`:285-290`, `:307-308`,
  `:398-407`), gated by two checkboxes + an offset slider (`:792-800`, `:918-926`). This is the
  shape our §7.4 weave line copies, with the Hunter's GCD in place of the paladin's.
* **Raptor Strike resets the melee swing** — the weave reward, encoded as a spell set applied
  on `UNIT_SPELLCAST_SUCCEEDED`: `Core.lua:30-39` (`[2973]`, `[14260..14266]`, `[27014]`),
  dispatched `Core.lua:70-82` ⇒ `ResetMainSwingTimer()` (`Player.lua:187-189`). Mongoose Bite
  is *not* in the table ⇒ no reset. The set is the classic rank family; the pinned data's
  Forever ranks are 415335–415343 (`Data/Hunter.lua:63`, `:143`) — a port must key by **name**
  (our locale law), not by these ids.
* Parry haste shortens a swing: `WST_ApplyParryHaste` cuts the remaining time by
  `speed × 0.40` with a floor at `speed × 0.20` (`Core.lua:410-448`), armed from `UNIT_COMBAT`
  with `action == "PARRY"` (`:466-473`).

### 4.4 The clip region (what the dead bar was for, and the real arithmetic)

WST's dead clip bar was a red 0.7-alpha band anchored at the bar's centre (split) / right
(`one_bar`) (`:767-774`) — "start this cast inside this band and the Auto Shot fires
mid-cast". In this build it has no width law at all (§2.7). The live signal of clipping is
the ranged bar's safe window reaching 0 before the cast can finish. Our live signal is the
interlock's full-width red (`UI/Swing.lua:1025-1029`; tracker
`CastingCycleFraction` `Core/Tools.lua:691-695`) — after the fact.

The arithmetic a design needs (from the pinned data, not from WST):

| Shot | Cast | GCD | Category / cd | Range |
|---|---|---|---|---|
| Auto Shot (75) | — (it *is* the swing) | — | — | min 8 / max 35 (`spells.jsonl` ID 75 `MinRange=8 MaxRange=35`) |
| Aimed Shot (20904) | 2000 ms (`Data/Hunter.lua:46`; data `CastMs=2000`) | 1500 | cat 2 / 6000 | 8–35 |
| Multi-Shot (2643) | **none** in the pinned data (no `CastTimeMs`; WST's table still lists 0.5 s for the classic ranks, `Castbar.lua:14-16`) | 1500 | cat 2 / 6000 | 8–35 |
| Steady Shot (437123) | 1500 ms | 1500 | — | 8–35 |
| Raptor Strike (415343) | instant | 1500 | cat 40 / 6000 | max 5 |
| Mongoose Bite (14271) | instant | 1500 | cat 65 / 5000 | max 5 |

Consequence (the law behind §7.4): the "can I weave" budget is `safeSpan = cycle − aim` vs
`GCD = 1.5 s`; the "can I cast" budget is `safeSpan ≥ cast + GCD`. Un-hasted 2.0 s bow:
`aim = 0.5`, `safeSpan = 1.5` ⇒ **exactly one** instant shot per Auto Shot, and **no**
cast-time shot fits (1.5 < 2.0 + 1.5). Hasted 1.5 s cycle (`aim = 0.5 × 1.5/2.0 = 0.375`):
`safeSpan = 1.125` ⇒ not even a GCD fits, so the weave *must* clip. `[INFERENCE]`
(arithmetic on the rows above).

### 4.5 Latency compensation

`show_latency_bars` (default **false**, `Castbar.lua:74`): at cast start the cast length gains
`latency/1000` (`:183-187`, reading the **4th** `GetNetStats` return, which the pinned
catalog does not declare — `ConnectionDocumentation.lua:39` gives `(in, out, latencyList)`),
and a red `(1,0,0,0.75)` strip is laid at the cast bar's **left** end (`TOPLEFT`, `:542-549`,
created `:617-618`) with width `width × ((latency/1000) / cast_time)` (`:483-491`) —
"the first sliver of the cast is round-trip, not your cast". Nothing on the ranged bar uses
latency in WST at all.

### 4.6 The range light and the range tension

The band ladder (`Range.lua:339-433`) gates on `UnitExists`/`UnitIsDead`/`UnitCanAttack`
(`:340-347`), uses Wing Clip as the only reliable 5-yd breakpoint (`:352-356`), defines the
dead zone as *native-ranged-false + Scatter-true* (`:358-368`), splits too-close from too-far
with `CheckInteractDistance(guid, 3)` (`:388-397`) and uses the Scatter / Hunter's Mark ladder
for 15/35/100. The data tells the same story (Auto Shot min 8; Raptor Strike, Mongoose Bite,
Wing Clip max 5): **a Hunter weaving Raptor Strike is inside 5 yd, where Auto Shot cannot fire
at all** — the ranged bar and the melee bars are never simultaneously actionable in one
stance. That is the product fact behind §7.5's gate, and the reason our light reports the dead
zone as its own band (`Core/Range.lua:81-98`, `UI/Range.lua:144-151`).

### 4.7 How a player reads the bars together (the loop)

1. Ranged bar's left field present ⇒ you have room: cast/move; the number is the seconds to
   the shot.
2. Left field gone (split) / fill at the red edge (`one_bar`) ⇒ stand still; the red block
   drains into the right edge; the shot leaves when it empties.
3. After the shot leaves the left field comes back ⇒ the flight + reload span; weave one
   instant shot (GCD 1.5 s) inside it; a cast-time shot needs the field ≥ cast + GCD.
4. Orange sliver left of the red block ⇒ the last start was rejected; the shot is 0.5 s
   further out; the printed number already folds it.
5. Cast bar (its own frame) burning ⇒ read its remaining against the ranged bar's field; a red
   sliver at its left (latency on) is round-trip, not casting.
6. Melee main bar filling ⇒ the swing clock; Raptor Strike landing refills it (the reset),
   Mongoose Bite does not.
7. Range light: MELEE (red) = the melee-weave band, DEAD 5-8 (yellow) = Auto Shot impossible,
   8-35 (green) = the shot band.

There is **no** single-bar weave aid in WST: no GCD tick, no cast-time marker on the ranged
bar, no combined frame, no ready-glow. That is precisely the gap §7.3/§7.4/§7.5 fill.

---

## 5. Deliverable 4 — our current behaviour, item by item

All lines in `addon/Forte_Hunter/`. Today's shipped look (the baseline every new signal must
sit on; live-verified in the PLAN §9 2026-11-02 "Hunter swing v2 accepted" row,
`README.md:25-27`): **orange** = the safe/reload fill, **red** = the stand-still aim slice,
**white** = the shot has left, **yellow** = the 0.5 s retry, full-width red = a cast will
clip, plus the tenths text and the range light.

### 5.1 The cycle machine (`Core/Tools.lua`)

| Item | Ours today |
|---|---|
| Cycle anchor | `OnSwingStart(duration, swingType)`: Ranged-only filter, duration-first, secret → speed → last chain (`:296-338`); the Ranged enum read is `pcall`+`PlainOrNil` (`:204-210`) |
| Aim / stand-still length | `aimLen = AIM_SECONDS × duration / base`, `AIM_SECONDS = 0.5` (`:174`; computed `:311-318`, re-pinned `:368-370`); base = override → learned clean pair → nil floor (`:376-396`) |
| Floor clamp | `FloorAt = aimLen + max(0, retryUntil − now)` (`:398-405`); the cycle never counts below it (`:726-745`) |
| Phases | `CycleState` → `"reload" | "aim" | "flying"` + `aimLen` + `floor` + readiness (`:704-746`) |
| Shot cast machine | `UNIT_SPELLCAST_{SENT,START,SUCCEEDED,INTERRUPTED,FAILED,FAILED_QUIET}` with GUID-seal matching (`:600-675`); `SHOT_CAST_SET = {Aimed Shot, Multi-Shot, Steady Shot}` (`:184-186`); lengths `UnitCastingInfo → C_Spell → data` (`:548-580`, `:1026-1050`) |
| Retry penalty | `RETRY_SECONDS = 0.5` → `retryUntil` (`:180`, `:663-672`) — the same 0.5 s law as WST's `auto_delay_duration` |
| Flight proof | stamped on `SUCCEEDED` (`:647-…`), phase `"flying"` (`:739`), stale grace (`:187`, `:707-710`) |
| Readiness gate | `CanAim` — shooting / target / moving / range (`:407-…`); the gate governs the shot, never the slice (the draw law `UI/Swing.lua:1031-1035`) |
| Movement | 0.05 s sustained-pulse law + the `GetUnitSpeed` leg (`:192-195`) |
| Feign | movement-rearm law (pinned by `tests/test_swing2.lua`) |
| Latency | `NetLatency()` guarded, never feeds timing (`:1059-1070`) — deliberate (prior note Gap-12) |
| **Melee swing** | **none** — `OnSwingStart` drops every non-Ranged type at its first line (`:297`); no MH/OH state anywhere in the module |
| **Raptor Strike swing reset** | **not modelled** (the spell is in our data: `Data/Hunter.lua:63`, `:143`) |
| Shots' GCD | present in the data (`gcdMs=1500`, `Data/Hunter.lua:60`, `:63`), unread by the bar |
| Parry haste | not modelled (no `UNIT_COMBAT` consumer) |

### 5.2 The drawing (`UI/Swing.lua`)

| Item | Ours today |
|---|---|
| Frame | `FX.Hunter.SwingSkin` 200×12, Aluminium fill on the Background/Border backdrop, URW Gothic 10 OUTLINE (`:104-137`); built in `Init` (`:286-433`) |
| Fill | one law, two paths: the lua `SetSize` path and the engine `StatusBar`+`SetTimerDuration` path, with the capability gate and the parity test (`:164-205`, `:455-518`, `:552-618`; `tests/test_swing3.lua` "fill I3a" rows) — anchored `TOPLEFT`, grows left→right |
| Safe-window width | `max(0, (remaining − floor) / duration) × W` (`:958-961`) — it **shrinks** toward the aim end; WST's split law in our geometry |
| Single-phase width | `fraction × W` when `ShowSafeWindow` is off (`:962`) |
| Flight width | the whole bar white from `SUCCEEDED` to the next re-arm (`:955-957`) + a 1.0 s Spark2 pulse at the fill head (`:993-1013`) |
| Cast interlock | frozen fraction + **full-width** red slice + the cast's remaining as the text (`:946-951`, `:1025-1030`, `:1046-1052`) |
| Aim slice | red, shown **only during** `phase == "aim"`, width `min(aimLen, aimLen+retry) × scale`, right-anchored with an inset of `aimLen × scale` ⇒ it sits immediately **left** of the final aim region, which stays bare backdrop (`:1031-1038`; `_SetSlice` `:1073-1082`) |
| Retry slice | yellow, right-anchored at inset 0, width `min(0.5, retryUntil − now) × scale` ⇒ it rides the right-most region (WST anchors its mirror left of the aim block) (`:1036-1039`) |
| Text | right-aligned `formatRemaining` tenths; the aim phase prints `min(remaining, aimLen) + open retry` — the same fold WST prints at `Hunter.lua:659-663` (`:1043-1063`, `:250-265`) |
| Standing aim region | **absent** — outside the aim phase the right-most aim region is never tinted |
| Clip / GCD markers | **absent** — no vertical-marker concept in this module |
| Combat alpha pair | `_ApplyCombatAlpha` via `InCombatLockdown` (`:1083-1098`) |
| Idle law | hidden + the script nil'd; the 10 Hz script exists only mid-swing (`:1100-1157`) |
| Range light | its own strip anchored `BOTTOMLEFT` −4 under the bar, same width, follows the bar's drag; band colour + centred text; opt-in (`UI/Range.lua:117-168`, `:210-254`) |
| Status seam | `StatusLine` (`:1288-1300`) |

### 5.3 The options (`Pages/Hunter.lua`)

`DEFAULTS` (`:38-66`): `Enable`, `Lock`, `ShowTime`, `EnableReminder`, `ShowSafeWindow`,
`ShowAimSlice`, `ShowFlying`, `ShowRetry`, `ShowLatency(false)`, `BaseSpeed(0)`,
`ShowRangeLight(false)`, `InCombatAlpha(1.0)`, `OutOfCombatAlpha(1.0)`, `Width(200)`,
`Height(12)`, `ReminderSize(32)`, `BarColor`, `BgColor`, `ReminderColor`. Sections: Basics
(`:137-150`), Shot Cycle (`:151-171`), Frame Sizing (`:172-186`), Coloring (`:187-198`),
Range Light (`:199-207`), Combat Alpha (`:208-224`); the frame strata row lives on the Advanced
page (`Forte_Options/Pages/Advanced.lua:196-202`). Key → seam routing:
`UI/Swing.lua:1186-1216` (`KEYMAP`/`STORED`). Store law: sparse store, and the defaults table
is registered **once** per module (`Forte_Options/Core/Settings.lua:396-399` — a second
`Register` *replaces* the set), so all Hunter keys' defaults must stay in
`Pages/Hunter.lua:38-66`.

### 5.4 Gap table

| # | Item | Verdict | Note |
|---|---|---|---|
| 1 | Cycle anchor `PLAYER_SWING` (Ranged) | **have** | §5.1 |
| 2 | Aim / stand-still window (the `0.5 × speed/base` law + floor) | **have** | same law, same constants |
| 3 | Safe-to-move span (the split-mode law) | **have** | `Swing.lua:958-961` |
| 4 | **One-bar mode** (the fill that grows left→right and chases the aim edge) | **missing** | our single-phase mode (`fraction × W`) is a plain elapsed fill: no aim cap, no standing aim region, no chasing edge |
| 5 | **Standing** right-end aim region (visible all cycle) | **missing** | ours is in-phase only (§5.2) |
| 6 | Retry / delay segment + the folded text | **have** | same law, same colour family; anchored right-most vs WST's left-of-aim (§7.8 open item 6) |
| 7 | Event-proven "projectile left" state | **have** (ours only) | WST has no such visual; our white fill + pulse is the stronger signal |
| 8 | "Can I cast now without clipping" legibility | **partial** | the interlock answers it *after* the fact; no *pre-cast* region answers it (WST's is dead) |
| 9 | Shot cast bar (Aimed/Multi/Steady cast visuals) | **have, elsewhere** | Forte_Timer's cast rows + our interlock; no separate Hunter cast frame (deliberate) |
| 10 | **Clip region** (where a cast-time shot starts clipping) | **missing** | WST ships it dead; our interlock is post-hoc |
| 11 | **GCD / melee-weave act line** (is there time for a 1.5 s GCD) | **missing** | WST's shape exists only as the paladin marker law (`Player.lua:285-290`) |
| 12 | **Melee main-hand swing bar** (+ the Raptor Strike reset) | **missing** | nothing consumes MainHand/OffHand `PLAYER_SWING` (§5.1) |
| 13 | Off-hand swing bar | **missing** (no Hunter need) | `UnitAttackSpeed`'s 2nd return exists (`UnitDocumentation.lua:681`); a Hunter swings the ranged weapon + the main hand |
| 14 | Parry haste shortening a swing | **missing** (no Hunter value) | `Core.lua:410-448` needs `UNIT_COMBAT`'s action field; not a Hunter rotation input |
| 15 | Latency compensation strip | **missing, by design** | the 4th `GetNetStats` return is undeclared; our row ships inert until the launch probe (`Pages/Hunter.lua:158-160`; `tests/test_swing.lua:601-611` asserts the tip does not claim live) |
| 16 | Range / dead-zone light | **have** | compact bands, own ladder; the per-band user texts and the non-Hunter ladder were deliberate non-ports (`Core/Range.lua:3-26`) |
| 17 | In/out-of-combat alpha pair | **have**, defaults differ | we park by hiding when idle; documented on the row's tip (`Pages/Hunter.lua:208-224`) |
| 18 | `classic_bars` texture toggle | **n/a — not wanted** | a WST-skin switch (`Hunter.lua:760-766`); ForteXorcist ships one Classic skin; owner guidance 2026-11-04: no WST style toggle |
| 19 | Profiles / per-character presets | **have, elsewhere** | Forte_Options' profile system covers it |
| 20 | Panel legend art ("Bar Explanation") | **n/a** | dead in WST (§2.7) |
| 21 | Wand `Shoot` shared path | **n/a today** | Hunter-gated product (no 5019 row in `Data/Hunter.lua`) |

---

## 6. Framing of the proposal

Everything in §7 is a **proposal**; facts inside it carry citations. Two facts carry the
design: (a) the aim law `0.5 × speed / base` (`Tools.lua:311-318`, mirroring
`Hunter.lua:127`) and (b) the 1.5 s GCD plus the 8-yd Auto Shot floor
(`Data/Hunter.lua:46`, `:60`, `:63`; `spells.jsonl` Auto Shot `MinRange=8`,
Raptor/Mongoose `MaxRange=5`).

Owner guidance 2026-11-04: **ForteXorcist style only** — no WST visuals, no `classic_bars`
equivalent (§3.1 documents it as a fact and proposes no row for it); take the functionality;
every signal must pay for itself in how fast a Hunter reads it mid-rotation; the
live-verified orange → red → white cycle is the baseline the new signals sit on, not a
candidate for replacement.

## 7. The ForteXorcist design

### 7.0 Ranked by rotation value: the decision each signal answers

The four questions a Hunter is actually asking, and how each answer arrives in one glance on
the existing 200×12 Aluminium bar (no new frames except the opt-in melee rail):

| Rank | The decision mid-rotation | Signal in one glance | What WST contributed |
|---|---|---|---|
| **P1** | *Can I start a cast-time shot now without clipping?* | a **dim clip stripe** at the bar's right end: a cast started while the fill's edge is inside it will not finish before the windup — its length is that shot's cast time + the aim window | the *idea* of the Multi-Shot clip bar (`Hunter.lua:767-774`); the *shape* from WST's "act-by-this-line" markers (`Player.lua:285-290`, `:307-308`); the *number* from our data, not WST's dead bar |
| **P2** | *When does the next Auto Shot fire / how long before I must stand still?* | the **standing aim region** (the right end, tinted all cycle) that the shrinking fill runs into, + the tenths number (shipped) | `auto_shot_cast_bar`'s static right-end block (`Hunter.lua:657`, `:701-704`); the split fill law (`:695`) |
| **P3** | *May I move / cast freely?* | the **white fill** (shipped, event-proven); the fill *is* the safe span | the README law (`README.md:22-24`) implemented as the safe span's width |
| **P4** | *Is there time to step in and melee-weave (GCD 1.5 s) and be back?* | a 1-px **weave line** at `aim + 1.5 s` from the right: fill edge right of it ⇒ no room | the paladin GCD marker law (`Player.lua:286-290`, `:308`, `:405-407`) applied to the Hunter's GCD |
| **P5** | *Is my main-hand swing up (the Raptor Strike reset reward)?* | an opt-in **melee rail** under the bar, filling left→right, full = ready, refilled by Raptor Strike's reset | `Player.lua:81-102`, `:280`, `:300-306`; `Core.lua:30-39`, `:70-82` |
| P6 | *How much of this cast is round-trip?* | the latency row stays inert | `Castbar.lua:483-491` + the undeclared 4th return (§7.6) |
| — | *which texture style do I like* | **no row** — ForteXorcist has one skin | `Hunter.lua:760-766` (documented §3.1, not proposed) |

The ranking sets the budget: **four new rows** (two default on, two opt-in) and **one
replacement** (the mode picker subsumes `ShowSafeWindow`). Nothing is proposed for P3 — it is
already the strongest thing we ship, and a second signal for a question we already answer
clearly is noise.

### 7.1 One mode picker, not a pile of toggles

`BarMode` (`s.SEL`, values `"safe" | "one" | "elapsed"`), replacing `ShowSafeWindow`:

| Value | Label (page voice) | Drawing | Why a Hunter picks it |
|---|---|---|---|
| `safe` (default) | "Safe window (shrinks toward the aim end)" | **today's pixels, untouched** (`Swing.lua:958-961`) | the fastest read of P2/P3: an empty left field *is* the warning |
| `one` | "One bar (fills toward the aim end)" | the WST `one_bar` law, §7.2 | the fill reads as progress — the idiom WST/YaHT players already have in their eyes |
| `elapsed` | "Single fill (cycle elapsed)" | today's `ShowSafeWindow=false` law (`:962`) | the plain swing clock for a player who does not weave |

Migration: a stored `ShowSafeWindow == false` maps to `elapsed`; `true`/unset maps to `safe`.
The key retires in the same cutover (no alias, no shim — the clean-cutover law) and the Shot
Cycle section's `keys` list moves in the same edit (`Pages/Hunter.lua:166-170`). The `s.SEL`
row shape is the General page's (`Pages/General.lua:195-208`: `module`, `key`, `label`,
`items = { {value=…, label=…} }`, `tip`), and the SEL row's full-row-span law
(`UI/Window.lua:683-689`) is already honoured by the page's section shape.

### 7.2 The one-bar geometry, in our geometry language

With `W = S.Width`, `scale = W / tracker.duration` (as today, `:944-945`),
`aimW = aimLen × scale` (the standing aim region, §7.3), `progress = 1 − remaining/duration`:

```
w = min(W − castWidth, W × progress)        -- castWidth = aimW, or the live cast's own width
```

clamped to `[0, W]` by the existing clamp (`:963-967`). The cap is the whole point: the fill
never enters the aim region, and while the region drains (§7.3) the cap opens and the fill
follows the red edge to full width exactly as the shot leaves — the choreography of
`Hunter.lua:691-694` with none of WST's art. The interlock, the flight, the retry, the text,
the alpha pair, the spark, the slices and both fill paths are untouched: the mode selects one
expression in `Update`, so the fill-parity tests (`test_swing3.lua` "fill I3a") stay valid per
mode.

### 7.3 The standing aim region (P2) — and what we deliberately do not copy

* A right-anchored slice, width `aimLen × scale`, drawn **all cycle** in `AimColor` at reduced
  alpha (≈0.45 of the shipped `{1,0,0,1}`): it is a *region*, not the live window, so it stays
  quieter than the live slice. During `phase == "aim"` the existing **live** slice
  (full-alpha red, `:1031-1038`) draws over it, inset law unchanged.
* The `retry` slice keeps its right-most anchor; under a live retry the aim region's alpha
  dims further so yellow stays the loudest thing on the bar.
* Option `ShowAimWindow` (CHK, default **on**, label "Aim window (right end, standing)"):
  it is P2's clock face, and without it the `one` mode's cap is invisible — §7.2's law needs
  it to be legible at all.
* **Do not copy**: WST's aim block *drains* as the shot fires (`:703`) so its width doubles as
  an aim countdown — the same fact our text already prints. One number per fact: the region is
  positional, the text is numeric, and the full-alpha red slice stays the live-phase marker.

### 7.4 The clip stripe (P1) and the weave line (P4)

Both are position markers on the existing bar; both are pure geometry off numbers we already
own, so neither needs a new event.

**Clip stripe (P1).** Right-anchored, width `(castLen + aimLen) × scale`, drawn **under** the
aim region in the aim hue at ≈0.22 alpha, so the bar's right end reads as a two-tone zone:
bright = stand still, dim = a cast-time shot started from here out will clip. `castLen` is the
length of the shot the player is about to press: the live cast's length while a cast runs
(`Tools.lua:677-695`), else the data length of the longest cast-time shot in `SHOT_CAST_SET`
(`Tools.DataCastMsByName()`, `:1038-1050` ⇒ Aimed Shot 2000 ms, `Data/Hunter.lua:46`). Option
`ShowClipRegion` (CHK, default **on**, label "Clip region (a cast started here clips the
shot)"). Reading — the stripe is drawn where a press CLIPS, and the fill says which side of it
the cycle's room is on, in the mode's own direction (`UI/Swing.lua`'s marker law, pinned by the
J4 property leg in `tests/test_swing_modes.lua`; the pre-F1 text of this sentence had the
growing bars on the wrong side):
in a **growing** bar (`one`, `elapsed`) the fill is the cycle's progress and the stripe hangs
off the right end, so the press fits while the fill's right edge is **left of the stripe's
left edge**, and a fill that has reached into the stripe means the press clips;
in the **shrinking** bar (`safe`) the fill *is* the safe-to-move span and the stripe starts at
the bar's left, so the press fits while that span reaches **past the stripe's right edge**,
and a span that stops short of it means the press clips.
Worked number: an un-hasted 2.0 s cycle with `aim = 0.5` gives
`(2.0+0.5)/2.0` ⇒ a full-bar stripe, i.e. the honest answer "Aimed Shot always clips on this
bow" — the stripe's *fullness* is the message, and it is the same truth our interlock prints
after the fact, now available before the press. Under the interlock the stripe retargets to
the live cast's length, so the frozen red bar also shows the *reason* it is red.

**Weave line (P4).** A 1-px vertical line (our `Spark`/`Border` art, no WST file) at
`(aimLen + GCD) × scale` from the right, `GCD = 1500 ms` read from the data
(`Data/Hunter.lua:60`, `:63`; the constant lives in `Tools` beside `AIM_SECONDS`). Option
`ShowWeaveLine` (CHK, default **off** — it is a melee-weave-build tool, and a signal a player
without that build must learn to ignore costs more than it pays). Label
"Melee-weave line (room for a 1.5 s GCD before the shot)". Reading: fill edge **left** of the
line ⇒ there is room for one instant shot before the stand-still window; the line at/past the
bar's left edge ⇒ the cycle has no room at all (a hasted 1.5 s cycle with `aim = 0.375`:
`aim + GCD = 1.875 > 1.5` ⇒ the line is off-bar, which is the correct "do not step in"
message, §4.4).
The markers' overshoot law (WST draws them taller than the bar so they read as lines,
`Player.lua:399`, `:406`) is adopted as height `S.Height + 6`; the offset slider is a
WST-skin artefact and is not proposed.

### 7.5 The melee rail (P5): opt-in, and gated by the one fact that makes it honest

A companion rail for the main-hand swing: new files (`Core/Melee.lua` tracker, `UI/Melee.lua`
renderer) on the range light's skin law — same width as the bar, anchored `BOTTOMLEFT` at −4
under it (the `UI/Range.lua:144-151` precedent), 8 px tall, `TOPLEFT`-anchored fill growing
left→right, **full = the swing is ready** (WST's law `Player.lua:280` under its
`fill_empty=true` default, `:34`), a tenths text at the right, and the idle law (hidden while
out of melee combat, no ticker).

* Feed: `PLAYER_SWING` with `Enum.PlayerSwingType.MainHand` (0). `Tools.OnSwingStart`'s
  Ranged filter stays; the melee clock is a **separate** tracker
  (`Core/Melee.lua`'s `OnSwingStart(duration, swingType)` accepting MainHand; OffHand (1) only
  if a probe ever shows a Hunter off-hand swing).
* Speed per slot from `UnitAttackSpeed("player")`'s **1st** return (main), every return
  through `PlainOrNil`, re-read on `UNIT_ATTACK_SPEED` (`UnitDocumentation.lua:4142`,
  unit-only payload) — the same per-slot leg pattern `Tools.lua:252-266` already uses.
* The reward: on `UNIT_SPELLCAST_SUCCEEDED` with the resolved name == "Raptor Strike"
  (name-keyed per our locale law — **not** WST's `[2973]/[14260..14266]/[27014]` ids,
  `Core.lua:30-39`, whose rank family is not the Forever one, `Data/Hunter.lua:63`, `:143`)
  re-arm the main-hand clock from the last known MH speed (the effect of
  `Player.lua:187-189`). Mongoose Bite does not reset (its absence from WST's table,
  `Core.lua:35-39`, is the fact).
* **The gate** (the one piece of real design here): the rail draws only while the range light
  reads `melee` **or** the light is off. Auto Shot needs ≥ 8 yd, Raptor Strike and Mongoose
  Bite need ≤ 5 (`spells.jsonl`: Auto Shot `MinRange=8`; Raptor/Mongoose `MaxRange=5`), so the
  rail's information is actionably true only inside the melee band; drawn at 30 yd it is noise.
  This is behaviour, not an option; the option is the rail itself: `EnableMeleeRail` (CHK,
  default **off**).
* Non-goals, each with its reason: no off-hand rail (a Hunter does not off-hand swing — the row
  could never be used), no paladin marker rows, no parry-haste shortening (needs
  `UNIT_COMBAT`'s action field; not a Hunter rotation input), no `fill_empty` toggle (one
  reading, ours), no spark (our fill rides the Aluminium texture; WST's spark is a skin
  artefact gated on `classic_bars`, `Player.lua:302-306`).

### 7.6 Latency stays a probe, not a pixel

`ShowLatency` and `Tools.NetLatency()` stay exactly as they are (inert, honest tip,
`Pages/Hunter.lua:158-160`; guarded `Tools.lua:1059-1070`): WST's strip rides a **4th**
`GetNetStats` return (`Castbar.lua:184`, `:486`) the pinned catalog does not declare
(`ConnectionDocumentation.lua:39` → `(in, out, latencyList)`). Launch-day probe: print the
return count on a hunter. If a latency number is there, its shape on our bar is a left-end
sliver of `W × (latency/1000) / duration` in the aim hue at 0.75 alpha (the WST geometry,
`Castbar.lua:487`) folded into the **clip stripe's** right end — because the fact latency buys
on our bar is "the stand-still line is effectively this much earlier", which is P1/P2
territory, not a new fact.

### 7.7 API check against the pinned catalog (every symbol this design touches)

| Symbol | Verdict | Pinned source | Notes / secret profile |
|---|---|---|---|
| `PLAYER_SWING (swingDuration, swingType)` | CAT ✓ | `wow-api-combat` ← `SwingTimerDocumentation.lua:42` | `SynchronousEvent`; payload order verified (duration first); feeds the bar and the rail |
| `Enum.PlayerSwingType` MainHand=0 / OffHand=1 / Ranged=2 | CAT ✓ | `SwingTimerDocumentation.lua:70` | read through `pcall`+`PlainOrNil` (`Tools.lua:204-210`) |
| `UnitAttackSpeed → (attackSpeed, offhandAttackSpeed, rangedAttackSpeed)` | CAT ✓ | `UnitDocumentation.lua:681` | `SecretWhenUnitStatsRestricted`; the per-slot leg pattern is already ours (`Tools.lua:252-266`) |
| `UNIT_ATTACK_SPEED (unitTarget)` | CAT ✓ | `UnitDocumentation.lua:4142` | unit-only payload; the rail's speed re-read trigger |
| `UNIT_SPELLCAST_{SENT,START,SUCCEEDED,INTERRUPTED,FAILED,FAILED_QUIET}` | CAT ✓ | `UnitDocumentation.lua:4727`, `:4802` (family) | `SecretWhenUnitSpellCastRestricted`; the GUID-seal law is in place |
| `C_SwingTimer.IsTargetWithinSwingRange(Ranged)` / `EnableRangeCheck(Ranged, on)` | CAT ✓ | `SwingTimerDocumentation.lua:22`, `:10` | the rail's gate rides the existing light, which owns the single `EnableRangeCheck` caller (`UI/Range.lua:176-…`; `test_swing3.lua` "range I3a" rows) |
| `UnitCastingInfo` | CAT ✓ | `UnitDocumentation.lua:827` | `startTimeMs`/`endTimeMs` (`NeverSecret` per field) — already the interlock's length source; feeds the clip stripe's live length |
| `C_Spell.GetSpellInfo` | CAT ✓ | `SpellDocumentation.lua:415` (row in `docs/hunter-tools.md` §Catalog) | cast time / ranges; the interlock's 2nd length source |
| `InCombatLockdown` | CAT ✓ | `RestrictedActionsDocumentation.lua:44` | the rail's idle gate, same as the bar's alpha pair |
| `GetNetStats (in, out, latencyList)` | CAT ✓ **shape mismatch** | `ConnectionDocumentation.lua:39` | WST's 4th read is undeclared → §7.6 |
| `GetRangedHaste (result, quiverHaste)` | CAT ✓ | `PlayerScriptDocumentation.lua:934` | **not needed**: quiver haste is already inside `UnitRangedDamage` / `PLAYER_SWING` (`Hunter.lua:108`) — listed to close WST's haste-source question |
| `GetUnitSpeed`, `UnitCanAttack`, `UnitIsDeadOrGhost`, `CheckInteractDistance`, `C_SpellBook.IsSpellBookItemInRange`, `C_Spell.IsSpellInRange` | CAT ✓ | verified present in the pinned sets | already used by the movement/light legs; no new use |
| `SetTimerDuration` | a widget method, not a global row | `SimpleStatusBarAPI` — our gate reads it off the widget (`Swing.lua:468`) | engine-fill path only |
| **Not used, by law** | — | — | `COMBAT_LOG_EVENT_UNFILTERED` (blocked `Core.lua:355-357`; forbidden by AGENTS), `CombatLogGetCurrentEventInfo` (`Hunter.lua:501`), `GetInventoryItemID`/`INVSLOT_*` (`Player.lua:50`, `:57` — no catalog row), `hooksecurefunc`, legacy `GetSpellInfo` tuple reads (`Player.lua:286`), hard-coded spell-ID sets |

### 7.8 Build slices (file-disjoint, ordered α → β → γ)

Defaults are registered in exactly one place (`Settings.lua:396-399`: a second `Register`
*replaces* the set), so `Pages/Hunter.lua` is the single options surface and it belongs to γ;
α and β therefore ship behind today's defaults, changing nothing for a player who does not
opt in. Every slice's tests are new files, so no slice's edits appear mid-run in a sibling's.

**Slice α — modes + the standing aim region + the clip stripe + the weave line (render-only).**
Files: `addon/Forte_Hunter/UI/Swing.lua`, `addon/Forte_Hunter/tests/test_swing_modes.lua`
(new). No `.toc`, no tracker, no page change.
Acceptance (`test_swing_modes.lua`, mirroring `test_swing.lua`'s injected-tracker /
`now`-box + `nearpx` 0.5-px law and `test_swing2.lua`'s per-phase geometry law):
1. `SetBarMode("safe")` — and an unset mode — reproduces today's numbers exactly: the v2
   sequence of `test_swing2.lua` run verbatim (fill `= max(0,(remaining−floor)/duration)·W`,
   aim slice `= 0.5·(W/duration)` in phase `aim` only, interlock `= W`, flight `= W`), i.e. the
   existing tests pass **unedited** — the baseline is a law, not a proposal.
2. `SetBarMode("one")`: fill `= min(W − aimW, W·progress)` at the cycle's start/mid/floor; the
   cap bites exactly at `progress = 1 − aimLen/duration`; full width at the aim's end; the
   fill's right edge ≤ `W − aimW` while no cast is live; the cap opens with the drained region
   during the aim phase.
3. `SetBarMode("elapsed")`: `= fraction·W`, no slice drawn (today's off-mode law).
4. The aim region's width is `aimLen × scale` for the **whole** cycle in every mode; its alpha
   < the live slice's; `ShowAimWindow=false` hides it without touching the live slice.
5. Clip stripe: width `(castLen + aimLen) × scale` clamped to `W`; `castLen` from the injected
   data table; retargeted to the live cast's length under the interlock; 0 when
   `ShowClipRegion=false`.
6. Weave line: x `= W − (aimLen + gcd)·scale`; hidden when that ≤ 0 (the no-room law); hidden
   by `ShowWeaveLine=false`; default off.
7. Parity: one cycle through `SetFillEngineMode("lua")` and `("engine")` yields the same
   `_fillIntent` sequence in each mode (the `test_swing3.lua` parity law).
8. `StatusLine()` names the mode, the aim-region alpha and the stripe's width (the
   `/fx status` seam, `Swing.lua:1288-1300`).

**Slice β — the melee companion (new tracker + new frame).**
Files: `addon/Forte_Hunter/Core/Melee.lua` (new), `addon/Forte_Hunter/UI/Melee.lua` (new),
`addon/Forte_Hunter/tests/test_melee.lua` (new), `addon/Forte_Hunter/Forte_Hunter.toc`,
`addon/Forte_Hunter/Forte_Hunter_Camelot.toc` (two added lines; the tocs stay byte-identical —
`gate.py` check 3).
Acceptance (`test_melee.lua`, the injected-clock/reader law):
1. `OnSwingStart(d, MainHand)` arms; `(d, Ranged)` is dropped **and the ranged tracker's state
   is unchanged**; a secret/≤0 duration is dropped.
2. Full = ready: at the arm the fill is 0, at arm + d it is `W`; the tenths text is
   `d − elapsed` to one decimal.
3. `UnitAttackSpeed`'s **1st** return is the speed leg; a secret read leaves the last known
   speed; a 0/nil main speed parks the rail (hidden, no division by zero).
4. "Raptor Strike" by **name** (the injected cast seam) re-arms the clock to the last known MH
   speed; "Mongoose Bite" does not; a Raptor Strike cast by a non-player does not.
5. The gate: the rail draws iff (light off) or (light on and band == `melee`), with an injected
   meter; `EnableMeleeRail=false` ⇒ the frame is never shown and no ticker runs (the idle law).
6. The stack: with the light on, the vertical order is swing bar → (light) → rail, each
   anchored off the swing bar, so one drag moves all three.

**Slice γ — the options surface + the docs.**
Files: `addon/Forte_Hunter/Pages/Hunter.lua`, `addon/Forte_Hunter/tests/test_swing.lua`
(extend its page-row law), `docs/hunter-tools.md`, `README.md` (the Hunter row, `:48`).
Acceptance:
1. `DEFAULTS` gains `BarMode="safe"`, `ShowAimWindow=true`, `ShowClipRegion=true`,
   `ShowWeaveLine=false`, `EnableMeleeRail=false` in the one registration; `ShowSafeWindow` is
   **gone**; a stored `false` reads back as `BarMode="elapsed"` (the migration assertion lives
   in this test).
2. The Shot Cycle section's `keys` list matches its rows exactly (the section-recycle law);
   the new rows ride `s.SEL`/`s.CHK` in the page's module/key/tip shape; the
   `test_swing.lua:601-611` honesty law is extended — **no** new row's label or tip claims a
   live effect it does not have, and every new row's tip names the rotation question it answers
   ("can I cast without clipping", "room for a 1.5 s GCD", …) in the page's voice.
3. `ApplySettings` routes every new key (the `KEYMAP` seam, `Swing.lua:1186-1216`; the melee key
   through `FX.Hunter.Melee:ApplySettings`) and `ApplyStoredSettings` re-applies them at login
   (the existing `STORED` law) — asserted by a set → `:Get` → state round-trip on the live
   objects, the way `test_swing2.lua:602-606` asserts today.
4. `gate.py --fast` PASS (the Hunter suite, the toc-identity and api-lint legs), then J3 on
   uiforever (`PLAN.md:875`): one-bar and split cycles frame-by-frame, the four rows toggled
   live, the rail observed only in the MELEE band, no Lua errors.

### 7.9 Spell identity and the three traps this design must not step in

1. **Name, never id.** Our cast seam resolves names (`Tools.lua:184-186` `SHOT_CAST_SET`)
   because the event seam is name-keyed and our data is the English key space
   (`Tools.lua:1038-1050`). WST's Hunter/melee spell sets are hard-coded classic rank ids
   (`Core.lua:30-39`, `Castbar.lua:14-52`); its Steady row **34120 has no Forever row** (the
   pinned data has Steady Shot 437123 / 409957), and its Raptor family
   (2973 / 14260–14266 / 27014) is not our data's (415335–415343, `Data/Hunter.lua:63`, `:143`).
2. **No clip bar from the reference.** Its width law does not exist in this build (§2.7); the
   clip stripe's length is our data's cast time (§7.4).
3. **The GCD is a data row, not WST's paladin constant** (`Player.lua:286-290` reads
   `GetSpellInfo(19750)` — a paladin id — and clamps it to 1500 ms). We read `gcdMs=1500` off
   the Hunter rows we ship.

---

## 8. Open questions / probes (hunter character, launch day)

1. **The `one` mode's value is a player's-eye question, not a code question.** Its geometry is
   fully specified (§7.2) and test-pinned, and the split mode answers P2/P3 at least as fast.
   J3 should record both in one session on one bow and report which one the eye goes to; if
   `one` never wins it stays a preference mode, not the default, and no further work rides on
   it.
2. **`castLen` source for the clip stripe when nothing is casting**: the shipped data table
   (`Tools.DataCastMsByName`, Aimed 2000 ms) is the proposal's answer. Probe: confirm
   `C_Spell.GetSpellInfo(...).castTime` for the *learned* Aimed Shot rank matches the data on
   the live client; a mismatch means the stripe rides the live read (the priority order
   `UnitCastingInfo → C_Spell → data`, `Tools.lua:548-580`, already encodes it).
3. **`gcdMs` and the 6 s shot category**: the GCD does not haste, so a data constant is right;
   the probe is a real Aimed-Shot-category cycle (`Data/Hunter.lua:46` cat 2 / 6000) to confirm
   the category cooldown is not what a Hunter reads as "can I weave" (it is not — the weave
   budget is GCD + aim, §4.4), so the stripe/line pair stays unconfused.
4. **Does a Hunter receive MainHand `PLAYER_SWING` while Auto Shot is on**, and at what cadence
   under pet / Raptor resets. The rail's premise is yes; probe the event stream with the rail's
   debug print. If MainHand swings are not delivered to third-party addons (the same
   reachability question as `PLAYER_SWING` Ranged, `docs/launch-day.md` probe 1), slice β's
   tracker parks (hidden rail, no ticker) and §7.5's gate makes that a silent, honest
   degradation.
5. **`GetNetStats`'s return count** (§7.6) — the only open API fact in the design.
6. **The retry's anchor.** WST anchors the retry block left of the aim block (`Hunter.lua:707`);
   ours rides the right-most region (`Swing.lua:1036-1039`). Each is consistent with its own
   aim-region law. This note takes no side: decide on the J3 recording (the yellow segment's
   legibility beside a *standing* aim region is a combination neither build has been seen in)
   and land it in §7.3's slice.
