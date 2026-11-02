# `Forte_Timer` — the Spell Timer (stacked per-spell / per-target rows), Forever-constrained

Design note, owner `SpellTimerDesign`, written 2026-11-02.

**Citation discipline:** every original-source line number in this note was re-checked today by an
automated anchor test (search the cited string, compare its line number with the number cited) over
`Forte_Timer.lua`, `Forte_Casting.lua` and `Forte_Core.lua`; 60 anchors, all matching. Where an earlier
project document disagrees with the source, the source wins and the delta is listed in §1.11.

**Sources read** (all paths exist as of 2026-11-02):

- Original: `/tmp/fxref/Forte_Timer/Forte_Timer.lua` (3,419 lines), `/tmp/fxref/Forte_Core/Forte_Core.lua`
  (2,546), `/tmp/fxref/Forte_Casting/Forte_Casting.lua` (880).
- `docs/reference-functional-spec.md` §2 (`CA-*`), §3 (`ST-01`…`ST-38`), §10–§12.
- `docs/research/secrets-unknowns.md` (Q1, Q4, Q5, Q10 + summary table + ranked changes).
- `docs/design-combat-procs.md` (§1 the closed log, §4 the "nothing secret-derived reaches a widget" rule).
- `PLAN.md` §2.5, §3.2, §3.4, §3.5–3.6, §7 Phase 4, §8, §10.2, §10.7 (owner ruling: **Spell Timer v1 scope =
  own-cast predictions accepted**, `PLAN.md:549`), §11 Iteration C.
- Dormant seed `addon/Forte_Cooldown/UI/Rows.lua` (473 lines; header `:1-28` stated it is the Phase-4
  Spell-Timer seed). **Spent input**: Phase 4 forked it to `addon/Forte_Timer/UI/Rows.lua` (in that TOC)
  and the seed was deleted 2026-11-02, so the `Rows.lua:NNN` cites below are the seed's historical
  line numbers, kept because the fork keeps the seed's structure.
- Catalog, pinned target `forever`, version **1.60.1.70532**, commit `ca8368f2f238`:
  `docs/api/wow-addon-api-agents/skills/<shard>/references/generated/forever.json` (record index
  `shard:N` = the N-th entry of its `declarations` array; `source.file:line` inside = the Blizzard
  `*Documentation.lua` anchor), plus `docs/audit/api-coverage.json` and
  `skills/wow-api-index/references/generated/symbols.json` (`targets.forever`, 10,250 symbols).
- Data: `mythicsim-forever-engine/data/spells.jsonl` (7,503 rows) → `addon/Forte_Hunter/Data/Hunter.lua`.
- `AGENTS.md` **does not exist in this repo** (globbed: only `PLAN.md`); the working laws applied are
  `PLAN.md` §10.2 rules 1–10 and §3.4.

**Image blindness disclosure:** this agent cannot see images. Every visual number in §5 comes from the
original's *source*, never from pixels. The reference pictures exist (`docs/refs/ref4.png`,
`docs/media/frames/walk-000315.png`, `docs/media/frames/demo3-000245.png` + `-crop`, index in
`docs/media/README.md:19-25`) and must be eyeballed by the owner (or a vision-capable worker) before
sign-off. All geometry claims are asserted numerically in tests (§6), never visually.

---

## 1. What the original did

### 1.1 The row stack: geometry

One *instance* (`FX_Timer<i>`, `Forte_Timer.lua:2631-2666`) is a stack of **groups**; a group is one
target and holds bars.

| Quantity | Value | Anchor |
|---|---|---|
| row (bar) width | `Width = 250` | `Forte_Timer.lua:3365` |
| row height | `Height = 14` | `Forte_Timer.lua:3363` |
| gap between bars inside a group | `Space = 2` | `Forte_Timer.lua:3364` |
| gap between groups | `SpacingHeight = 2` | `Forte_Timer.lua:3345` |
| group label height | `LabelHeight = 18` | `Forte_Timer.lua:3344` |
| group width | `Width + Backdrop[6]*2` = 256 (edge 3) | `Forte_Timer.lua:1938`, `:3414-3417` |
| bar width (the icon is **outside** the bar) | `s.Width - s.Height - 1` = 235 | `Forte_Timer.lua:1860-1861` (the comment reads *"icon is placed outside of the actual bar!!"*) |
| icon = a `Button`, 14×14, 1 px gap | `TOPRIGHT→bar TOPLEFT,-1,0` + `BOTTOMRIGHT→bar BOTTOMLEFT,-1,0` | `Forte_Timer.lua:1862-1870` |
| stack offset / x-inset | group offset `s.Backdrop[6]` (3); bar x-inset `s.Height+1+s.Backdrop[6]` = 18 when `Icon and not IconRight` | `Forte_Timer.lua:2320-2332`, inset literal `:2322` |
| growth direction | `Expand = true` ⇒ upward from the frame's BOTTOM | `Forte_Timer.lua:2320-2332`, default `:3321` |
| row alpha | target / failed rows full alpha, everything else `NormalAlpha = 0.50` | `Forte_Timer.lua:2340-2344`, default `:3366` |
| per-instance visible cap | `Max = {[0]=false,15}`, enforced at `:2192` | `Forte_Timer.lua:3315`, `:2192` |
| row-background alpha | `BarBackgroundAlpha = 0.3` | `Forte_Timer.lua:3367` |
| bar cascade | `baroffset += vis*Height + vis*Space` | `Forte_Timer.lua:2337-2339` |

### 1.2 Row anatomy (the bar's own children)

All children are built once per slot in `NewBar` (`Forte_Timer.lua:1679-1904`) and recycled forever.

| Part | Detail | Anchor |
|---|---|---|
| bar body | a hand-rolled StatusBar: `SetValue(v)` crops `SetTexCoord(0,v,0,1)` and slides the far anchor ⇒ a LEFT-anchored fill that **drains toward the right** | `Forte_Timer.lua:1630-1677`, law `:1656-1668` |
| icon | a `Button`, texture `Interface\AddOns\Forte_Core\Textures\ST`, cropped `0.133,0.867,0.133,0.867`; the per-spell texture is written each pass | `Forte_Timer.lua:1686`, `:1692-1694`, `:2542` |
| icon spark | `…\Textures\Spark2`, `ADD`, centred on the icon, height `vis*Height*2.2` | `Forte_Timer.lua:1688-1691`, `:2534` |
| stack tag | `GameFontHighlightSmall`, `JustifyH CENTER`, anchored `BOTTOMRIGHT` of the icon | `Forte_Timer.lua:1696-1698` |
| name text | `GameFontHighlightSmall`, centred on the bar, height = bar height | `Forte_Timer.lua:1701-1702`, `:1894-1896` |
| time + `timedummy` | `GameFontHighlightSmall`, `JustifyH LEFT`, 2 px inset at the LEFT (right when `TimeRight`) | `Forte_Timer.lua:1704-1708`, `:1878-1888` |
| bar spark | `…\Textures\Spark`, `ADD`, anchored at `barval*width` from LEFT | `Forte_Timer.lua:1711-1714`, `:2536-2540` |
| cast slice | `bar.castarea`, `ADD`, texcoords `from,to` | `Forte_Timer.lua:1716-1717`, law `:2421-2464` |
| raid mark | `Interface\TargetingFrame\UI-RaidTargetingIcons` + the 8 coord pairs | `Forte_Timer.lua:1720-1722`, coords `:385-394`, use `:2356`, `:2360` |
| row background | `Interface\PaperDollInfoFrame\UI-Character-Skills-Bar`, full-bleed, tinted by `ColorVal`'s alpha | `Forte_Timer.lua:1725-1727`, `:2366-2367` |
| tick marks | texture `…\Textures\Spark`, `ADD`, `Width = Height*0.5` (7), `Height = Height*1.5` (21) | `Forte_Timer.lua:1613-1627` (sizes `:1621-1622`) |
| interaction | left-click = print the duration, shift+click = one-shot ignore (`state = IGNORE`), right-click = jump to that spell's filter; hover = spell tooltip | `Forte_Timer.lua:1730-1759` |

Group chrome: `NewGroup` (`Forte_Timer.lua:1899-1948`) builds the group `background` (the instance
backdrop), the `label` fontstring (`LabelFont`) and the group `raidicon` (`:1909-1916`).

### 1.3 The row record (the 28-column law) + enums

The in-source schema is `Forte_Timer.lua:399-426` (column *n* = line *398+n*):
`1 expiring-at · 2 cast time · 3 duration · 4 target name · 5 show-ticks · 6 MAIN SPELL TYPE · 7 texture ·
8 name · 9 target type (0 trash/1 boss/2 player) · 10 ready-to-check-removal · 11 GUID · 12 expire-msg-at ·
13 unique id (the group key) · 14 timer state · 15 special flag · 16 stacks · 17 remove time · 18 show-tick
time · 19 raid icon · 20 the expire time actually drawn/sorted · 21 option + shared group · 22 haste factor ·
23 isfriendly · 24 isshared · 25 isunique · 26 keep_after_combat · 27 unit token · 28 aura id`.

The per-instance *link* row (visibility / filter / max-time cache per clone) is `:431-441`.
Enums: states `IGNORE -1, NORMAL 0, FADING_INSTANT 1, FADING 2, REMOVE 3, FAILED 4` (`:35-40`);
priorities `PRIOR_NONE 0, PRIOR_COOLDOWN -1, PRIOR_DEBUFF -2, PRIOR_SELF_DEBUFF -3, PRIOR_POWERUP -4`
(`:48-52`); seven main spell types `DEFAULT 1 … ENCHANT 7` (`:474-481`); bit flags
`NOTARGET / BUFF / SHARED / UNIQUE / TICKS …` (`:455-460`, composites documented by spec `ST-02`).

### 1.4 Grouping by target

- **The group key is column 13, the per-mob unique id — not the GUID.** A group opens whenever
  `lastid ~= st[i][13]` (`Forte_Timer.lua:2214-2222` pre-pass; `:2263-2311` draw pass). The id comes from
  `CA:GiveID(guid)` (monotonic, per-mob, recycled from live rows — spec `CA-20`; the live use
  `Forte_Casting.lua:680-686`); self / no-target rows carry a `PRIOR_*` sentinel instead
  (`Forte_Timer.lua:979-985`).
- Group scale = the max link visibility of its bars (`group.factor`, `:2219-2222`); border, label and
  raid-icon sizes scale with it (`:2281-2284`, label/raid-icon sizing `:2271-2274`).
- Label law — `drawLabel` (`Forte_Timer.lua:2060-2110`): text = the target name, `#<id>` prefixed when
  `ShowID` (`:2063-2064`); colour = `TargetColor` / `FocusColor` / `NormalColor` (`:2067-2073`); anchored
  top/bottom, mirrored by `LabelFlip`, full-width when `LabelLimit` (`:2075-2089`); it consumes
  `group.labelsize` and `Space` from the group's height budget (`:2104-2107`).
  Defaults: `GroupID true` (`:3319`), `Label false` (`:3341`), `LabelFlip/LabelLimit false`
  (`:3342-3343`).
- Group background identity tint: `TargetBgColor` / `FocusBgColor` / `NormalBgColor`
  (`Forte_Timer.lua:2292-2303`; defaults `:3397`, `:3400-3401`, all identity ones off by default).
- The raid mark rides the **label** when `Label and GroupID`, else the bar (`:2354-2363`).
- "Sections for self / target / others" are *not* separate frames: they fall out of the sort key — the
  `PRIOR_*` sentinels band self/no-target rows (`UpdateSortOrder` `Forte_Timer.lua:161-191`), and the
  unit gates are `Target`/`Focus`/`Other`/`NoTarget`/`UnknownTarget`/`You`/`RaidDebuffs` (`:3349-3355`).

### 1.5 Sorting

- The keys are *data*: `SORT_TIMER_ORDER = {3}` (duration) ungrouped;
  `SORT_TIMER_ORDER2 = {2,3}` (group id, then drawn-expire-time) when grouping
  (`Forte_Timer.lua:450-453`). The sort runs on the **link** table, never on the row table:
  `links[k][2],links[k][3] = st[i][13],st[i][20]` (`:2144`) then `links:sort(...)` (`:2171-2185`).
- `Outwands` flips the direction (`:2172-2175`, `:2179-2182`; default `:3333`).
- `TimerSortOrder` is a **string of category names** — default
  `"buff selfdebuff debuff cooldown notarget target"` (`Forte_Timer.lua:3306`) — parsed into the
  `PRIOR_*` values (`:193-215`), where `target` acts as a hard offset (`:206-212`); the option row is
  `:3280`.
- Time-band compression: `OneMax` (default `true`, `:3357`) takes the tallest visible duration as the
  bar's 1.0, clamped at `MaxTime` (default `{[0]=true,30}`, `:3358`), eased by
  `links[k][6] += (highestduration - links[k][6])/smooth` (`:2192-2226`); `ForceMax` pins the scale
  (`:2228-2235`); `HideLonger` + `HideTime` fade out rows longer than N (`:2151-2162`).

### 1.6 Colours

`ColorVal(frame, remaining, total, mainType, state, filterAction, spell, group)`
(`Forte_Timer.lua:1524-1573`) is the *only* colour decision:

1. failed states (`state > REMOVE`) ⇒ the `Fail` colour, mixed from `HighlightColor` while the fail flash
   runs (`:1527-1531`; `Fail = {1.00,0.00,0.30}` `:3375`);
2. the last 0.5 s of the row's own total ⇒ `MixColors((total-remaining)*2, HighlightColor, category)`
   (`:1535-1546`; `HighlightColor = {1,1,1}` `:3372`; `MixColors` = `Forte_Core.lua:2080-2084`);
3. otherwise the **per-category colour row** (`:1548-1556`), overridable globally by
   `TimerColorOverride {0.24,0.24,0.24}` (`:3309`);
4. alpha: `a = 1` by default (`:1559`), `ExpiredColor` once past zero (`:1560-1561`, default `:3371`),
   then the background blink law (`:1562-1571`; §1.8).

The palette to ship verbatim (`Forte_Timer.lua:3374-3394`):
`Channel 0.42,0,1` (`:3374`) · `Fail 1,0,0.30` (`:3375`) · `Curse 0.64,0.21,0.93` (`:3377`) ·
`Bane 0,0.54,0.42` (`:3378`) · `Crowd 0,1,0.50` (`:3380`) · `Default 1,0.50,0` (`:3381`) ·
`Pet 1,0,0.95` (`:3382`) · `Heal 0,1,0` (`:3383`) · `Buff 1,1,0` (`:3384`) · `Enchant 1,1,1` (`:3385`) ·
`SelfBuff 0,0.75,1` (`:3387`) · `SelfBuffOther 0.5,0.5,0.5` (`:3388`) ·
`TargetDebuff 0,0.36,1` (`:3389`) · `TargetDebuffOther 0,0.18,0.50` (`:3390`) ·
`Cooldown 1,0.39,0.35` (`:3391`) · `CooldownOther 0.5,0.20,0.18` (`:3392`) ·
`SelfDebuff 1,0,0` (`:3393`) · `SelfDebuffOther 0.5,0,0` (`:3394`);
text `NormalColor {1,1,1,1}` (`:3396`) / `TargetColor` (`:3398`) / `FocusColor` (`:3399`);
text over a bright fill is de-saturated by `FW:FixIntensity` (`Forte_Timer.lua:2369`,
`Forte_Core.lua:796-800`).

### 1.7 Text

| Element | Law | Anchor |
|---|---|---|
| time | `FW:SecToTimeD(t)`: `m:ss` when ≥ 60 s, else `%.1f`; the alternate mode prints `Nh/Nm/Ns` | `Forte_Timer.lua:2473-2481`; law `Forte_Core.lua:1746-1761` |
| time column width | measured by a hidden `timedummy`; `TimerSmartSpace = {true,30}` takes the **widest in the group** so the digits do not jitter | `Forte_Timer.lua:2482-2489`; default `:3308`; name width shrinks by it `:2531` |
| name | = the target name; the spell name when `Spell` (or when the row has no target); `#id` prefix (`ShowID`); `(stacks)` suffix | `Forte_Timer.lua:2491-2531` (`:2516`) |
| custom tag | `CustomTag = {false, "id target :: spell stacks"}` template with the four tokens | `Forte_Timer.lua:2492-2508`; default `:3412` |
| stacks on the icon | `IconStacks = true` + `StacksFont` (base font, size − 1, `OUTLINE`), text = col 16 | `Forte_Timer.lua:2467-2471`; defaults `:3330`, `:3347` |
| raid-mark prefix in messages | `FW.RaidIcons[mark] .. unit` | `Forte_Timer.lua:1582-1586` |
| tooltip | `title = "<time> <spell>"`, `tip = "<target>\n<remaining>/<total>"`, plus the spell / friendly / token / aura-id fields the tooltip law consumes | `Forte_Timer.lua:2394-2399` |

### 1.8 Expiry flash (three number laws, no sprites)

1. **Colour rush**: the final 0.5 s of the row's own total mixes the category colour toward
   `HighlightColor`: `MixColors((total-remaining)*2, …)` — `Forte_Timer.lua:1535-1546`. The *fail* flash
   mixes the other way over `2·|remaining|` (`:1527-1528`).
2. **Background pulse**: while `0 < remaining ≤ Blink[1]` (default `{[0]=true,3}` ⇒ 3 s, `:3335`) the
   row-background alpha oscillates around `BarBackgroundAlpha` by `0.25·(1 − cos(25·√remaining))`,
   inverted above alpha 0.5 — `Forte_Timer.lua:1562-1569`; the `cos`/`sqrt` locals at `:22-23`).
3. Past zero with `ExpiredColor` enabled ⇒ a flat grey row (`:1560-1561`, default `:3371`).
4. Spark flare around a tick: `SparkDamage = {true,1.5}` (`:3410`) scales the bar spark to
   `Height*2*(dt*(SparkDamage[1]-1)+1)` over a 0.3 s decay around col 18 (`:2376-2387`);
   `Spark = {true,0.7}` (`:3409`), `CastSpark = {true,0.3}` (`:3406`).

### 1.9 Lifetime state machine

`ST:Fade(i, mode)` is the only entry (`Forte_Timer.lua:1008-1017`: stamps col 17 = now, col 14 = mode;
an already-`IGNORE` row is zeroed instantly). `ST_UpdateSpellTimers` (`:1038-1077`, driven on
`AnimationInterval` = 0.04 s, `Forte_Core.lua:2473`):

- emits the expire message at col 12 (`:1049-1058`);
- deletes `IGNORE` rows at zero (`:1060-1066`);
- promotes `NORMAL → FADING_INSTANT` for `DRAIN/DEBUFF/POWERUP/SELF_DEBUFF`, `→ FADING` for the rest
  (`:1064-1067`);
- deletes a faded row at `removeTime + (instant ? TimerFadeSpeed : max(FailTime,FadeTime)+TimerFadeSpeed)`
  (`:1070-1076`, with `ST_CalculateMaxDelay` `:1028-1036`); the keep-alive
  comment is at `:1070`, the delete at `:1076`.

Defaults: `FadeTime 1` (`:3339`), `FailTime 2` (`:3338`), `TimerFadeSpeed 0.5` (`:3290`).

**The smoothing law** (the "TimerSmooth" behaviour the module is known for) — the drawn expire time is
interpolated, never raw:

```
1046:  st[i][20] = st[i][20] + (st[i][1]-st[i][20])/smooth;
```

`smooth = FW.Settings.TimerSmooth`, default **5** (`:3293`), option range 1…20 (`:3278`); bars draw from
col 20 (`t1 = t20 - t`, `:2243`). Display cadence = `AnimationInterval` 0.04 s
(`Forte_Timer.lua:2851`, `:2854`; `Forte_Core.lua:2473`), logic/rescan cadence = `UpdateInterval` 0.5 s
(`:2855`; `Forte_Core.lua:2475`) — exactly `PLAN.md` §3.4's ~10 Hz display / ~1 Hz rescan.

### 1.10 The reconciliation law (the quotes PLAN Phase 4 asks for)

The tolerance, `Forte_Timer.lua:33`:

```lua
33:  local maxlag = 1.00; -- lower is better, but once you get over this with your actual lag weird things may happen
```

The adopt inside the insert path, `Forte_Timer.lua:899-905` (`ST:AddNewTimer`; the same law in the
simple insert path at `:873-877`):

```lua
899:  if st[i][8] == spell and st[i][11] == guid then -- spell match on same unit
900:      if abs(st[i][1]-expire)<maxlag then -- exact match, just correct time
901:          st[i][1] = expire;
902:          if abs(st[i][20]-expire)>maxlag then
903:              st[i][3] = total;
904:              st[i][20] = expire;
905:          end
```

`ST_CorrectionScan` (`Forte_Timer.lua:1142-1223`) — the "uncertain cast" half (`:1154-1170`):

```lua
1154:  if st[i][11] == "" then -- uncertain cast, attempt to correct
1155:      local expire = UnitHasYourAura(unit,spell_name,friendly == 1 and "HELPFUL" or "HARMFUL");
1158:          if st[i][6] == DRAIN then -- drains are special cases, and never added by debuff/buff scans
1159:              if abs( expire-st[i][1] )<maxlag then
1160:                  st[i][9] = CA:Unique(unit);
1161:                  st[i][11] = guid;
1162:                  st[i][13] = CA:GiveID(guid);
1163:                  st[i][19] = GetRaidTargetIndex(unit) or 0;
1164:                  rebuildLinks(); -- IMPORTANT
1167:          if abs( expire-st[i][1] )<maxlag or Tick[spell_name] and ((expire > st[i][1] - maxlag) and (expire - Tick[spell_name]*st[i][22] - maxlag < st[i][1])) then --if it's found for correction, it will be added anyway, so can remove this now
1168:              st:remove(i);
```

…the confirmed-row half (`:1175-1211`):

```lua
1175:  elseif st[i][11] == guid then
1179:      local expire,index,stacks,total,rank = UnitHasYourAura(unit,spell_name,friendly == 1 and "HELPFUL" or "HARMFUL");
1181:      if st[i][10] == 0 then -- makes early (de)buff removing faster and hopefully bug free
1184:          if expire > st[i][1] or abs(st[i][1]-expire)<maxlag then st[i][1] = expire;st[i][16] = stacks or 0; end
1186:      elseif (st[i][3]-st[i][1]+t) >= BuffDelay then
1187:          st[i][10] = 1;-- it should have been on already at this time
1199:          st[i][1] = expire;
1200:          st[i][16] = (Stacks[spell_name] ~= 0 and stacks) or 0;
1201:          st[i][3] = total;
1207:      elseif st[i][10] == 1 and (st[i][1]==0 or st[i][1]-t>maxlag) then -- dont remove if only maxlag left
1211:          ST:Fade(i,REMOVE);
```

Read as rules — this *is* the design:

1. **A cast creates an *uncertain* row.** `guid == ""` = "from a cast event, target unconfirmed";
   `"none"` = self/no-target (`Forte_Timer.lua:979-985`; the queue schema comment
   `Forte_Casting.lua:226`).
2. **Adopt by expiry match.** A later aura observation whose `expire` lands within `maxlag` **is** the
   prediction: the row is filled in (guid, group id, raid mark) at `:1159-1164`, or *deleted as spurious*
   at `:1167-1169` when the real aura is about to be added by the scan anyway.
3. **Longer ⇒ extend; equal ⇒ leave** (`:1184`); a confirmed read rewrites `expire/stacks/total`
   (`:1199-1201`).
4. **A grace, not a poll.** A row may not be judged gone before `BuffDelay = 4.0` s after its window
   should have started (`:69`, `:1186-1187`), and removal is refused while more than `maxlag` remains
   (`:1207`).
5. **Shorter by more than `maxlag` ⇒ a refresh:** the row is removed (`:924`) and re-inserted
   (new icon, new fade) — the `:899-933` insert loop is the law; spec `ST-25`.
6. **Rows are keyed by NAME + caster identity.** `UnitHasYourAura(unit, name, filter)` walks the aura
   list matching the *name* and `isMine[m]` (`:1124-1140`; `isMine = {player,pet,vehicle}` `:1095`), and
   `ST_ScanForMissing` only adds auras of spells registered as **our own casts** (`Track[spell][1] == 0`,
   `:1103`). **The original was never a raid-debuff tracker** (spec `ST-24`).
7. **Triggers:** `UNIT_AURA` (`:2847`; `ST_AuraChanged` `:1387-1400`, with the `Settings.Delay`-deferred
   rescan at `:1391`), target change (`ST_TargetChanged` `:1402-1414`), focus (`:1416-1427`), mouseover
   (`:1429-1432`), a timed extra sweep (`ST_ExtraScan` `:1455-1479`), and the target-debuff scan
   (`ST_TargetDebuffs` `:1225-1271`) / self-buff scan (`ST_PlayerBuffs` `:1272-1351`). Registration block:
   `:2842-2865`; the cast hooks `CA:RegisterOnSelfCastFail/Tracked/End` at `:2867-2869`; leave-combat
   purge `:2880-2884`.

### 1.11 Corrections to earlier project notes (source is ground truth; log in `PLAN.md` §9)

| Claim | Truth (verified today) |
|---|---|
| `PLAN.md:331`: `maxlag` is "a user option" | It is a hard-coded file-local (`Forte_Timer.lua:33`; uses `:873-905`, `:1159-1207`). No option row exists. We keep it a constant in `FX.Timer.LAWS` so it is at least a *tested* constant. |
| Spec `ST-12`: states `IGNORE 0 … FAILED 5` | Source values are −1…4 (`Forte_Timer.lua:35-40`). The comparisons `<= NORMAL`, `> REMOVE` depend on them. |
| Spec `ST-30`: smoothing at `:1045`, and a `now2`/`minDuration` re-anchoring law | Smoothing is `:1046`. No `now2`/`minDuration` exists in this build; the time-band compression is `:2192-2235`. |
| Spec `ST-37`: "width 150, height 18, `TimerSmooth 0.5`" | `Width = 250` (`:3365`), `Height = 14` (`:3363`), `LabelHeight = 18` (`:3344`), `TimerSmooth = 5` (`:3293`). |
| Spec `ST-34`: the aura tooltip path `GameTooltip:SetUnitAura` | No successor on Forever: 0 `SetUnitAura` symbols in the pinned `targets.forever` list. The spell path is `C_TooltipInfo.GetSpellByID` / `.GetSpellBookItem` (present in the same list). |
| Our seed's backdrop edge = 5 (`addon/Forte_Cooldown/UI/Rows.lua:52-56`) | The *Spell Timer's* `Backdrop` edge is **3** (`Forte_Timer.lua:3417`): `{Background, Border, false, 16, 5, 3}`. |

---

## 2. Forever feasibility, behaviour by behaviour

Verdicts: **readable@when** = the fact can be read directly; **predicted** = inferred from our own cast
event plus generated data; **impossible** = no legal signal on this engine. Every API is cited from the
pinned Forever catalog (`skills/<shard>/references/generated/forever.json` record `shard:N`;
`api-coverage.json` line = the forever target block).

| Behaviour (original) | Verdict on Forever | Evidence |
|---|---|---|
| Geometry, fonts, textures, stack/group layout, alpha, fill direction | **feasible as-is** | `SimpleStatusBarAPI:SetStatusBarTexture` @`SimpleStatusBarAPIDocumentation.lua:317` (widget:1424), `:SetStatusBarColor` @`:281` (widget:1421), `:SetMinMaxValues` @`:228` (widget:1416), `:SetValue` @`:354` (widget:1427), `SimpleFontStringAPI:SetJustifyH` @`SimpleFontStringAPIDocumentation.lua:559` (wow-lua-api:236). Note `SetValue`/`SetStatusBarColor` carry `SecretArgumentsAddAspect` (`BarValue`, `VertexColor`, `Alpha`) ⇒ the renderer accepts **only our own scalars**. |
| Grouping by target (col 13 = per-mob id) | **feasible as-is** (our own id allocator) | `CA:GiveID` is bookkeeping (`Forte_Casting.lua:680-686`, spec `CA-20`); the identity *input* is the row below. |
| Sorting, `Outwands`, `TimerSortOrder`, `MaxTime` compression | **feasible as-is** | Reads cols 2/3/13/20 only. |
| Category colours, colour rush, `Blink` pulse, `ExpiredColor`, `FixIntensity` | **feasible as-is** | `ColorVal` + `MixColors` are arithmetic on our own numbers (`Forte_Timer.lua:1524-1573`; `Forte_Core.lua:2080-2084`, `:796-800`). |
| Text law (`SecToTimeD`, smart-space width, stacks, custom tag) | **feasible as-is** | Fontstring text + measurement. |
| 0.2 s settle + 3 s queue flush of the cast feed | **feasible as-is** | `Forte_Casting.lua:518` (`GetTime() + FW.Settings.Delay`), `:602-611` (3 s ⇒ `CA_SelfQueue:erase()`), `:344` (`CancelDelay`). |
| A row created by **our own cast** (DoT / CC / self-buff) | **predicted** | `UNIT_SPELLCAST_SUCCEEDED` payload `(unitTarget, castGUID, spellID, castBarID)`, event `SecretWhenUnitSpellCastRestricted`, `castBarID` `NeverSecret` — `UnitDocumentation.lua:4844` (unit-player:208; `docs/audit/api-coverage.json:27420`); `docs/research/secrets-unknowns.md:32-36`. Duration from data, as the original computed it (`Forte_Casting.lua:432-478` — `CA:Duration`; the travel/remap table is `CA_TrackCast` `:479-506`; spec `CA-15`). |
| **Target capture** for multi-target DoT rows | **predicted + guarded** | `UNIT_SPELLCAST_SENT` payload `(unitTarget, target:cstring` **`ConditionalSecret`**`, castGUID, spellID)` — `UnitDocumentation.lua:4802` (unit-player:205; `api-coverage.json:27417`). Original: `CA_SelfSent(spell,rank,target)` stores the name (`Forte_Casting.lua:560-577`, insert `:577`; event registration `:738-743`) and resolves it (`CA:CastTargetInfo`, spec `CA-19`). We keep the string as an opaque key and resolve only when plain. |
| Removal at the *true* expiry | **readable out of combat; predicted in combat** | `C_UnitAuras.GetAuraDataBySpellName(unit, spellName[, filter]) → AuraData` carries `SecretWhenUnitAuraRestricted` **and** `RequiresNonSecretAura` (`UnitAuraDocumentation.lua:244`, unit-player:345); the result for a secret aura is explicitly undefined (nil / error / secret: `docs/research/secrets-unknowns.md:255-260`). Out of combat = fact; in a lockdown a read must never over-rule a prediction. |
| The §1.10 adopt / extend / refresh reconciliation | **readable out of combat only** | Same annotations; the three spell-keyed lookups all carry `RequiresNonSecretAura` (`GetAuraDataBySpellName` @`:244`, `GetPlayerAuraBySpellID` @`:396` unit-player:354, `GetUnitAuraBySpellID`), `docs/research/secrets-unknowns.md:255-257`. |
| Bulk rescan (`ST_TargetDebuffs` / `ST_PlayerBuffs` / `ST_ScanForMissing`) | **readable out of combat only** | `C_UnitAuras.GetUnitAuras` @`UnitAuraDocumentation.lua:494` (unit-player:359, `RequiresUnitAuraAccess`); `C_UnitAuras.GetAuraDataByIndex` @`:207` (unit-player:343, + `SecretWhenUnitAuraRestricted`). `AuraData` fields (`name`, `icon`, `applications`, `duration`, `expirationTime`, `spellId`, `auraInstanceID`, `sourceUnit`, …) at `skills/wow-api-unit-player/references/UNIT-AURAS.md:174-199`; filter strings incl. `"HARMFUL PLAYER"` at `:146-168`. |
| **In-combat** live DoT truth on my target | **impossible in general** | The per-spell aura classifier flags exactly 76 spells (68 NeverSecret, 7 AlwaysSecret) and FX's 1,051 tracked IDs have **zero** overlap — `docs/research/secrets-unknowns.md:236-241`, `:268-291`. |
| DoT **tick marks** from real ticks | **impossible** | The original reads `SPELL_PERIODIC_*` (`Forte_Timer.lua:2750`, block per spec `ST-18` `:2745-2762`); the log is closed on Forever (`addon/Forte_Core/Core/Compat.lua:32-33`; `PLAN.md:50`). The *schedule* from data `tick` stays feasible (display only). |
| Resist / immune / reflect classification + the resist text/sound | **impossible** | Log-only (spec `CA-08`). We keep the *visual* band (col 14 > REMOVE, `Fail` colour, `FailTime`) driven by `UNIT_SPELLCAST_FAILED` `@:4713` (unit-player:198) / `UNIT_SPELLCAST_INTERRUPTED` `@:4741` — never naming a cause. |
| Other players' auras / raid-debuff tracking | **impossible, and out of scope**: the original filtered to `isMine[caster]` (`Forte_Timer.lua:1095`, `:1103`, `:1131`) | Aura annotations above; `sourceUnit` is not comparable in a lockdown. |
| Raid mark on a group (col 19) | **readable out of combat** | `GetRaidTargetIndex` @`RaidMarkersDocumentation.lua:54` carries **`SecretReturns = true`** (group-lfg:269). |
| Target/focus identity colouring | **feasible with guards** | We compare *our own* stored snapshot; the input `UnitGUID` is `SecretWhenUnitIdentityRestricted` (`UnitDocumentation.lua:1240`, unit-player:660) ⇒ `PlainOrNil` first. |
| Target-class band (trash/boss/player, `HideLongerNoBoss`, `/fx u trash\|boss`) | **feasible with guards, out of combat** | `UnitPlayerControlled @:2666` (unit-player:752), `UnitClassification @:965` (`:644`), `UnitIsDead @:1915` (`:704`), `UnitExists @:1191` (`:657`), `UnitName @:2488` (`SecretWhenUnitNameIdentityRestricted`, `:741`) — all `SecretArguments: AllowedWhenUntainted` ⇒ plain args legal; the *returns* need `PlainOrNil`. |
| Spell tooltip on hover | **feasible** | `C_TooltipInfo.GetSpellByID`, `C_TooltipInfo.GetSpellBookItem` (both present in `targets.forever`). |
| `TimerSmooth` interpolated clock, splashes, sounds | **feasible** | `GetTime` @`SystemTimeDocumentation.lua:56` (settings-system:299); `C_Sound.PlaySound` (present); `C_Timer.After` @`UITimerDocumentation.lua:10` (lua-environment:41). |
| **Pet**-cast rows (Devour Magic / Spell Lock / Seduction; `isMine.pet`) | **impossible** | `*PET_SPELLCAST*`: **0 symbols** in `targets.forever`. `isMine` (`Forte_Timer.lua:1095`) loses `pet`. |
| Death-driven cleanup (`ST_MobDies` `:1481-1487`) | **partly** | `UNIT_DIED` @`UnitDocumentation.lua:4223` (unit-player:155) exists **but** is `SecretWhenUnitIdentityRestricted` and its payload is a `unitGUID`; `UNIT_DESTROYED` **does not exist** (symbol scan: only `NAVIGATION_FRAME_DESTROYED`, `QUEST_SESSION_DESTROYED`). Cleanup rides `UNIT_DIED` (guarded) + row-expiry + `UnitExists`, never a hard purge. |
| Weapon-enchant rows (`ENCHANT` type) | **moved, do not fork** | Already owned by the Cooldown bar (`addon/Forte_Cooldown/Core/Enchants.lua`, rides `WEAPON_ENCHANT_CHANGED`, `Module.lua:392`); `GetWeaponEnchantInfo` is not on the 2012→Forever path we use (`Compat.lua:338-341` seam for the Cooldown side). |
| Totem rows, DK ghoul counts, Valkyr-summon rows, trap-trigger mutation | **impossible / not ported** | Spec `ST-17`, `ST-20`, `ST-21`, `ST-22` (all log-driven; no totem API on this client). |
| Test mode (`ST_UpdateTest` `Forte_Timer.lua:2764-2795`) | **feasible as-is — and it is our test bed** | The sim has no real combat state (`PLAN.md` §10.3 gotcha), so a synthetic feeder is the only deterministic UI test. |

**Owner ruling honoured:** v1 = *own-cast predictions only* (`PLAN.md:549`). Everything the v1 panel shows
is **predicted** by construction, and the panel says so (§5.5).

---

## 3. Data model

### 3.1 Two registries, one row table

```
FX.Timer.Register   (declared, generated)   keyed by spell NAME
FX.Timer.rows       (live rows, array+free-list) keyed by rowKey
```

`FX.Timer.Register[name] = { duration, kind, group, flags, tick, remap, maxStack, dispel }`
— the port of `Track[spell] = {notTarget, duration, ticks, type, texture, group, isBuff, isShared,
isUnique, isRefresh, keep}` (`Forte_Timer.lua:606-617`, spec `ST-01`), minus `texture` (resolved live) and
minus the 2012 glyph/talent/set modifier hooks (`C_Glyph`: **0 symbols** on Forever; talents live in
`C_Traits.*`, 53 symbols present — spec `ST-10`).

`kind` keeps the seven-way taxonomy (`Forte_Timer.lua:474-481`) so the colour + filter rows port 1:1:
`SelfBuff`, `SelfDebuff`, `TargetDebuff`, `Crowd`, `Cooldown`, `Channel`, `Enchant`.
The bit vocabulary ports verbatim (`F`, `:455-460`): `NOTARGET`, `BUFF`, `SHARED`, `UNIQUE`, `TICKS`.

### 3.2 The row

A **fixed-shape named table**, not the 28-slot positional tuple (the original repeats that literal at
every insert site — spec `ST-13`, insert literal `Forte_Timer.lua:937`):

| Field | Replaces | Law |
|---|---|---|
| `name` | col 8 | resolved **by name**; never an id (`PLAN.md` §10.2 rule 8; §8 spell-id drift) |
| `targetKey` | col 4 + 11 | `"none"` (self/no-target) · the **cast-target string** while unconfirmed · the resolved unit token + our numeric id once confirmed |
| `groupKey` | col 13 | our own monotonic per-target id (port of `CA:GiveID`), `PRIOR_*` sentinels for self/no-target (`Forte_Timer.lua:979-985`) |
| `expireAt` | col 1 | the fact/prediction expiry (authoritative) |
| `drawExpireAt` | col 20 | the smoothed value the renderer draws (`:1046`) |
| `castTime` | col 2 | from `castMs/1000`; the `castMs = -1000000` sentinel = instant (e.g. `addon/Forte_Hunter/Data/Hunter.lua:34`) |
| `total` | col 3 | the window the bar is scaled against |
| `maxTime` | link col 6 | the compression scale (`:2192-2235`) |
| `state` | col 14 | −1…4, values unchanged (`:35-40`) |
| `kind`, `colourKey` | col 6, 21 | drive `ColorVal` |
| `stacks` | col 16 | **written only by an aura read** (`aura.applications`); a predicted row shows none |
| `removeAt` | col 17 | set by `Fade()` |
| `tickEvery`, `hasteFactor` | col 5, 22 | a *display* schedule from data + the frozen haste factor |
| `raidMark` | col 19 | out-of-combat read only (§2) |
| `predicted` | new | true until an aura read adopts it; drives the UI marking (§5.5) and mirrors `source`/`anchored` in `addon/Forte_Cooldown/Core/Engine.lua:185-205` |
| `unitToken` | col 27 | kept | 
| *(dropped)* | col 28 | `auraIndex` is gone: the aura-tooltip path has no Forever successor (§1.11) |

No allocation per tick: rows live in a pooled table; the renderer takes an index array
(`PLAN.md` §3.4: pools, dirty-checked setters, staggered polling).

### 3.3 Keys

```
rowKey = name .. "\1" .. targetKey
```

Spell name **and** target ⇒ the same DoT on two dummies is two rows (exactly the
`demo3-000245.png` view), and a self-buff is exactly one row because its `targetKey == "none"`
(the original's own law, `Forte_Timer.lua:979-985`). Insert-time uniqueness =
`FindRow(name, targetKey)` first (port of `ST_FindSimilarSimple`, `Forte_Timer.lua:832-841`);
`SHARED`/`UNIQUE` group eviction ports `:926`.

### 3.4 Durations

```
duration = learned[name] (seconds, >= MIN)  else  data.durationMs / 1000
```

Identical to the cooldown engine's law (`addon/Forte_Cooldown/Core/Engine.lua:171-177`
`Engine:BestDuration`), fed by the same generated rows: `addon/Forte_Hunter/Data/Hunter.lua:11`
(Bestial Wrath `durationMs = 18000`), `:25` (Rapid Fire 15000), `:33` (Hunter's Mark 120000),
`:34` (Serpent Sting 12000), `:35` (Scorpid Sting 20000). `learned` is written **only** by a plain aura
read's `duration`/`expirationTime` pair (`UNIT-AURAS.md:182-183`) — a prediction never teaches, exactly
the rule `Engine:OnRead` enforces (`Engine.lua:210-255`).
Haste: the original multiplied the window by `CA:HasteFactor`, gated per class/spell by
`SetDefaultHasted`/`SetHasted` (spec `CA-16`, `Forte_Casting.lua:410-431`); the haste *probe* is
out-of-combat on Forever (`CA-14`), so v1 measures the factor out of combat, freezes it for the fight, and
stores it per row (`hasteFactor`, the col-22 slot).

**Generator work required.** Upstream `mythicsim-forever-engine/data/spells.jsonl` (7,503 rows) already
carries `Mechanic`, `MaxStack`, `DispelType`, `CasterAura`, `DurationMs`, `MaxTargets`, `MinRange`,
`MaxRange`, `ICDMs` (verified key census today); our generator emits only `durationMs`, `cooldownMs`,
`cooldownCategory`, `gcdMs`, `castMs`, `rank` (`tools/gen_spell_data.py:161-176`, `durationMs` at
`:163-164`). The Spell Timer needs four more: `mechanic` (→ the shared group, the modern stand-in for the
2012 "shared debuff" tables), `maxStack` (→ the `Stacks` cap), `dispel` (→ the Curse/Magic/Enrage colour
rows), `isBuff` (→ the `F.BUFF` bit). Change site: `emit_entry` (`tools/gen_spell_data.py:161-176`);
gate step 5 re-runs the generators, so bytes must stay deterministic.

### 3.5 Insert / refresh / stack rules (the ported law, verbatim numbers)

```
MAXLAG = 1.00   BUFF_DELAY = 4.0   SETTLE = 0.2   CANCEL_SETTLE = 0.5   QUEUE_FLUSH = 3.0
SMOOTH = 5      FADE = 1.0         FAIL = 2.0     BLINK = 3.0          MAXTIME = 30
```
anchors: `:33`, `:69`, `Forte_Casting.lua:518`, `:344`, `:602-611`, `:3293`, `:3339`, `:3338`, `:3335`,
`:3358`. One table, `FX.Timer.LAWS`.

```
insertFromCast(row)        -- SETTLE after a settled own cast
  row.expireAt   = now + duration*hasteFactor
  row.castTime, row.total, row.predicted = true
  row.groupKey   = idFor(targetKey)            -- PRIOR_* sentinel for self/no-target
  row.state      = NORMAL

onAuraFact(row, expire, stacks, total)         -- out of combat, plain values only
  d = expire - row.expireAt
  if abs(d) <= MAXLAG  then ADOPT:    expireAt, stacks, total; predicted = false    -- :900-905, :1159-1164
  elif d >  MAXLAG     then EXTEND:   expireAt = expire                             -- :1184
  else                      REFRESH:  Fade(row, REMOVE) then re-insert               -- :924 (ST-25)
  refuse removal while expire - now > MAXLAG                                        -- :1207
  row becomes checkable only after BUFF_DELAY                                       -- :1186-1187
```

Stacks are display-only and never invented: the tag renders from `stacks > 0`
(`Forte_Timer.lua:2467-2471`), so a predicted row shows a clean icon.

### 3.6 Renderer-only laws

`drawExpireAt += (expireAt - drawExpireAt)/SMOOTH` (`:1046`);
`barval = clamp((drawExpireAt - now)/maxTime, 0, 1)`; `maxTime` from `OneMax`/`MaxTime`/`ForceMax`
(`:2192-2235`); visibility alpha per state (`:2146-2168`: `Alpha(removeAt, t)` for
`FADING_INSTANT`, `Alpha(removeAt + FADE, t)` for `FADING`, `Alpha(removeAt + FAIL, t)` for
removed/failed); display cadence 0.04 s, logic sweep 0.5 s (§1.9).

---

## 4. Signals (the complete inbound set)

Registration law: **one** frame, created inside the module's `OnEnable`/login handler, every
`RegisterEvent`/`RegisterUnitEvent` call inside that handler — the exact pattern of
`addon/Forte_Cooldown/Module.lua:365-392` and `Forte_Core/Core/Init.lua`'s safety note
(`SimpleFrameAPI:RegisterEvent` @`SimpleFrameAPIDocumentation.lua:1018`, widget:1065;
`:RegisterUnitEvent` @`:1063`, widget:1068).

### 4.1 Own casts (the v1 spine)

| Event | Forever record | Use |
|---|---|---|
| `UNIT_SPELLCAST_SENT` | `UnitDocumentation.lua:4802`; payload `(unitTarget, target:cstring` **`ConditionalSecret`**`, castGUID, spellID)`; event `SecretWhenUnitSpellCastRestricted` (unit-player:205; `api-coverage.json:27417`) | **the target capture.** Open a cast record `{name, targetKey, openedAt}`; a fresh SENT evicts unstarted "garbage sent" records (`Forte_Casting.lua:565-575`). The name stays an opaque string; it is resolved only after `FX.Compat.PlainOrNil` (`addon/Forte_Core/Core/Compat.lua:45-48`) |
| `UNIT_SPELLCAST_START` | `@:4816` (unit-player:206) | stamp the cast-bar end ⇒ the cast-slice law (`Forte_Timer.lua:2421-2464`) |
| `UNIT_SPELLCAST_SUCCEEDED` | `@:4844`; payload `(unitTarget, castGUID, spellID, castBarID` **`NeverSecret`**`)` (unit-player:208; `api-coverage.json:27420`) | settle for `SETTLE` (0.2 s) then insert — **never on the event itself** (the original defers, `Forte_Casting.lua:514-518`; spec `CA-04`) |
| `UNIT_SPELLCAST_FAILED` / `_INTERRUPTED` | `@:4713` (unit-player:198), `@:4741` | settle for 0.5 s (`Forte_Casting.lua:344`) then move the row into the `FAILED` band (`Fail` colour, `FailTime`), **without** naming a cause (`CA-08`) |
| name resolution | `C_Spell.GetSpellName` @`SpellDocumentation.lua:517` (spells-abilities:194), `C_Spell.GetSpellTexture` @`:594` (`:199`), `C_Spell.GetSpellInfo` @`:415` (`:188`) | resolve the payload id to a **name first** (the `isKnown` precedent, `Module.lua:65-69`), then the name is the key. A secret `spellID` ⇒ no row is created, and it is counted (probe P1) |

Target resolution = the port of `CA_CastOn` (spec `CA-19`): match the string against `target`, `focus`,
party/raid, then the token list `"target targettarget focus focustarget pet pettarget"`; keep only
`UnitExists` + not `UnitIsDead`; **ambiguity ⇒ stay unconfirmed** (the original returns `""`).
Every returned name/guid passes `PlainOrNil`.
Queue hygiene: flush after `QUEUE_FLUSH` (`Forte_Casting.lua:602-611`), erase on
`PLAYER_LEAVING_WORLD`/`PLAYER_DEAD` (`:776-777`).

### 4.2 Aura reconciliation — gated, out of combat only

`FX.SecretState` is the single gate (live today: `Module.lua:291-306` `RefreshSecretState`; events
`ADDON_RESTRICTION_STATE_CHANGED` / `PLAYER_REGEN_ENABLED` / `PLAYER_REGEN_DISABLED` registered at
`Module.lua:380-381`), backed by `C_RestrictedActions.IsAddOnRestrictionActive`
(`addon/Forte_Core/Core/Compat.lua:126-130`) and `C_Secrets.ShouldAurasBeSecret` (`:148-152`);
semantics + NATIVE verification: `docs/research/secrets-unknowns.md:362-427`.

| Trigger | Record | Sweep |
|---|---|---|
| `UNIT_AURA` (throttled) | `UnitAuraDocumentation.lua:644`, payload `(unitTarget, updateInfo)`, `SecretWhenAurasRestricted` (unit-player:145) | `"player"`: `C_UnitAuras.GetUnitAuras("player","HELPFUL")` + `"HARMFUL"` (`@:494`, unit-player:359) → refresh/fade `SelfBuff`/`SelfDebuff` rows (port of `ST_PlayerBuffs`, `Forte_Timer.lua:1272-1351`) |
| target change / `UNIT_AURA("target")` | `PLAYER_TARGET_CHANGED` `@:3973`, **no secrecy annotation** (unit-player:115) | `GetUnitAuras("target","HARMFUL PLAYER")` + per-name `GetAuraDataBySpellName("target", name, "HARMFUL")` (`@:244`, unit-player:345) → ports of `ST_TargetDebuffs` + `ST_CorrectionScan` (`:1225-1271`, `:1142-1223`) |
| combat end | `PLAYER_REGEN_ENABLED` | the full sweep: adopt / extend / refresh / fade, **and learn** `duration` — the only teacher in the system |
| fallback enumeration | `GetAuraDataByIndex` `@:207` (unit-player:343) | used only when the bulk call is absent; pcall'd |

Every read is `pcall`'d (a restricted read **raises**), every returned field passes `PlainOrNil`, and a
nil/secret result changes **nothing** — the contract `Engine:OnRead` already enforces
(`addon/Forte_Cooldown/Core/Engine.lua:210-213`). `sourceUnit` is compared only as a *plain* string
against `"player"`/`"pet"` for the `isMine` filter (`Forte_Timer.lua:1095`), never as a token identity.

### 4.3 Explicitly not wired (do not "helpfully" add)

- `COMBAT_LOG_EVENT_UNFILTERED` — forbidden on Forever; that is why
  `Compat.HAS_COMBAT_LOG = not IS_FOREVER` exists (`addon/Forte_Core/Core/Compat.lua:32-33`,
  `PLAN.md:50`). This is what kills tick detection, resists, ghoul/Valkyr rows and trap triggers
  (`ST-16/17/21/22`).
- Any aura/cooldown read while `FX.SecretState` reports restricted (§2 rows).
- `*PET_SPELLCAST*`, `UNIT_DESTROYED`, `GameTooltip:SetUnitAura`, `C_Glyph.*` — verified **absent** from the
  pinned Forever symbol surface (§2).
- Nothing secret-derived may reach a widget: the widget methods add a secret aspect on value/colour
  (`SimpleStatusBarAPI:SetValue` @`:354`, `:SetStatusBarColor` @`:281`), so the renderer accepts only plain
  scalars (`docs/design-combat-procs.md` §4 hard rule).

---

## 5. UI spec (1:1 with the original), reusing `UI/Rows.lua`

### 5.1 Reuse map and the exact deltas

`addon/Forte_Cooldown/UI/Rows.lua` is the seed (header `:1-28`; forked into `addon/Forte_Timer/UI/Rows.lua`
and the seed deleted 2026-11-02), structurally right: the row IS the
`StatusBar` (`:301-333`), pools grow and never shrink (`:300-302`), every style setter is dirty-checked
(`:355-408`), splashes recycle (`:340-378`), position + lock persist (`:108-176`). Its
`FX.Cooldown.Display` alias stays inert (`:24-27`): if Phase 4 loads the file, it registers as
`FX.Cooldown.Timer` — do not resurrect the alias.

| # | Seed today | Spell-Timer value | Source of the number |
|---|---|---|---|
| D1 | row `Height 24`, `IconSize 36` overhanging | bar `Height 14`; icon **outside** the bar, 14×14; bar width `235`; x-inset `18` | `Forte_Timer.lua:3363`, `:3365`, `:1860-1870`, `:2322` |
| D2 | one flat stack | **groups** per `groupKey`: frame + backdrop + optional label (`LabelHeight 18`, `SpacingHeight 2`) | `Forte_Timer.lua:1899-1948`, `:2263-2311`, `:2060-2110` |
| D3 | time text centred in the bar | time at the bar's LEFT with a 2 px inset; name centred; both the `GameFontHighlightSmall` class | `Forte_Timer.lua:1878-1896`, `:1701-1708` |
| D4 | `formatRemaining` (`Rows.lua:112-121`) | `SecToTimeD`: `m:ss` ≥ 60, else `%.1f`, plus the `timedummy` smart-space width | `Forte_Core.lua:1746-1761`; `Forte_Timer.lua:2473-2489`, `:3308` |
| D5 | no bar spark | bar spark (`Spark`, α `Spark[1] = 0.7`) at `barval*width`, height `Height*2.2` | `Forte_Timer.lua:1711-1714`, `:2534`, `:2536-2540`, `:3409` |
| D6 | no ticks | tick marks: `Spark`, 7×21, spaced `tickEvery*haste / maxTime * width` | `Forte_Timer.lua:1613-1627`, `:2408` |
| D7 | no cast slice | `castarea` (`ADD`) over the cast/GCD slice + the icon cast spark (α 0.3) | `Forte_Timer.lua:1716-1717`, `:2421-2464`, `:3406` |
| D8 | no stacks | stack tag at the icon's BOTTOMRIGHT, `StacksFont` = base font, size − 1, `OUTLINE` | `Forte_Timer.lua:1696-1698`, `:2467-2471`, `:3347` |
| D9 | `BgColor` α 0.50 | `BarBackgroundAlpha = 0.30` + the blink law (§5.4) | `Forte_Timer.lua:3367`, `:1562-1569` |
| D10 | no raid mark | `UI-RaidTargetingIcons` + the 8 coord pairs; size = `Height` on the bar, `LabelHeight` on the label; α `RaidTargets[1] = 0.7` | `Forte_Timer.lua:1720-1722`, `:385-394`, `:2356`, `:2360`, `:3348` |
| D11 | no group identity colour | group backdrop `NormalBgColor {0,0,0,0.5}` / `TargetBgColor` / `FocusBgColor` (identity ones off by default) | `Forte_Timer.lua:2292-2303`, `:3397`, `:3400-3401` |
| D12 | α from fade-in only | non-target rows at `NormalAlpha 0.50`; target/failed rows at 1.0 | `Forte_Timer.lua:2340-2344` |
| D13 | `BarColor` white α 0.20 | per-category colour (the 18 rows of §1.6), text de-saturated by `FixIntensity` | `Forte_Timer.lua:1524-1573`, `:2369`; `Forte_Core.lua:796-800` |
| D14 | hard 12-row cap | per-instance `Max` (default off, 15) + `OneMax`/`MaxTime`/`HideLonger` gates | `Forte_Timer.lua:3315`, `:3357-3360`, `:2151-2162` |
| D15 | `ForteXorcistCooldownAnchor` + `/fx lock` | its own frame name (`ForteXorcistTimerAnchor`) and its own saved table — the Cooldown Timer owns its anchor | `Rows.lua:108-176` (pattern) |

Keep verbatim: the `Aluminium` fill; the `Background`/`Border` backdrop with tile 16 / edge 5 / inset 5
(`Rows.lua:51-57`) **except** the Spell Timer's edge value, which is **3** (`Forte_Timer.lua:3414-3417`);
fonts `FX.CLASSIC_FONT = Interface\AddOns\Forte_Core\Fonts\URWGothic-Book.ttf` size 11
(`Rows.lua:44-45`) replacing the original's bundled `GOTHIC.TTF` 11 (`Forte_Core.lua:2509`,
`Forte_Core.lua:584-586`) per the owner's font ruling (`PLAN.md:399-402`); the row background
`Interface\PaperDollInfoFrame\UI-Character-Skills-Bar` (`Forte_Timer.lua:1727`); the icon base
`Interface\AddOns\Forte_Core\Textures\ST` with the `0.133…0.867` crop (`Forte_Timer.lua:1692-1694`);
sparks `Spark`/`Spark2` (`Forte_Timer.lua:1617-1618`, `:1690`, `:1712`); the bar fill
`Interface\AddOns\Forte_Core\Textures\Aluminium` (`Forte_Core.lua:2488`).

### 5.2 Draw pass (0.04 s cadence)

For each visible link in sorted order: group open/close on `groupKey` change → label + geometry →
`barval = clamp((drawExpireAt − now)/maxTime)` → `SetValue` → `ColorVal` (§1.6) for fill + background +
spark → `FixIntensity` for the name colour → text (`SecToTimeD`, name/target, stacks) → tick marks →
cast slice → spark position/alpha → raid mark. Every setter dirty-checked; pools never shrink
(`PLAN.md` §3.4).

### 5.3 Bar fill direction (do not "fix")

`SetValue(v)` crops `0..v` and slides the far anchor ⇒ the fill is anchored at the LEFT and **shrinks from
the right**; `Flip` mirrors it (`Forte_Timer.lua:1656-1668`). The time text sits at that same left edge, so
the countdown reads at the shrinking edge — that is the FX look.

### 5.4 The expiry flash, as code-able numbers

```
if total - remaining < 0.5   then fill = mix(fill, highlight, (total-remaining)*2)        -- :1535-1546
if 0 < remaining <= BLINK(3) then bgAlpha = barBg ± 0.25*(1 - cos(25*sqrt(remaining)))     -- :1562-1569
if remaining <= 0 and expiredColor then fill, bg = expiredColor                           -- :1560-1561
```
Keep `cos`/`sqrt` and the constants (25, √t, 0.25) so the pulse *frequency and shape* match, and assert
them numerically (§6, T7).

### 5.5 UI honesty (`PLAN.md` §7 Phase 4: "state the ceiling in the UI")

- The anchor title (visible only while unlocked, `Rows.lua:157-171`) reads
  **`Forte Spell Timers (predicted)`**.
- `FX.Timer.options.markPredicted = true` by default: a predicted row's bar carries a 1 px dark notch at
  its right end and its time text at α 0.85 (the seed's existing α law, `Rows.lua:405-412`); adopted /
  anchored rows render solid. "Predicted" is legible without a legend.
- One tooltip line states the ceiling: *your own casts only; times are predictions; no tick, raid-aura or
  in-combat expiry truth exists on Forever.*
- Gate flags port 1:1: `Enable` (`Forte_Timer.lua:3313-3314`, option `:3146`), `Hide` (`:3331`),
  `Flip` (`:3332`), `Expand` (`:3321`), `Outwands` (`:3333`), `Time`/`TimeRight`/`Icon`/`IconRight`/
  `Name` (`:3324-3328`), `Label` (`:3341`), `Spell` (`:3340`), `ShowID` (`:3318`), `IconStacks` (`:3330`),
  `MaxTime`/`ForceMax`/`HideLonger`/`HideTime` (`:3357-3360`, `:3337`), `Blink`/`FadeTime`/`FailTime`
  (`:3335`, `:3339`, `:3338`), `Target`/`Focus`/`You`/`Other`/`RaidDebuffs` (`:3349-3355`), `Max`
  (`:3315`). The combat/party gate block is `:882-940` (spec `ST-35`).

---

## 6. Module / file plan (owners, then the test plan)

Slice: `PLAN.md` §11 Iteration C — "Spell Timer (`Forte_Timer`) design + seed from `UI/Rows.lua`
(own-cast predicted rows)". **One owner per file** (§10.2 rule 4). `Forte_Timer/**` is new and unlisted in
§10.1's lock table; `UI/Rows.lua` is dormant and unlisted too — **confirm with `Main` before touching
`Rows.lua`** (`TimelineFidelity` owns `UI/Timeline.lua` and both read the same style constants).

| File | Contents | Owner |
|---|---|---|
| `addon/Forte_Timer/Forte_Timer.toc` + `Forte_Timer_Camelot.toc` | `## Interface: 16001`, `## Dependencies: Forte_Core`; the pair **byte-identical** (gate step 3, `scripts/gate.py`; the convention: `Forte_Cooldown/Forte_Cooldown.toc`) | fx-worker A |
| `addon/Forte_Timer/Core/Rows.lua` | the row table: `New/Fade/FindRow/Insert/OnAuraFact/Sweep/Sorted`, §3.5's rules, §3.6's smoothing. **Zero API reads** (pure, testable) | fx-worker A |
| `addon/Forte_Timer/Core/Casts.lua` | the cast queue (port of `CA_SelfQueue`, `Forte_Casting.lua:40`, schema `:225-240`): SENT/START/SUCCEEDED/FAILED/INTERRUPTED, settle + flush, the target resolver, the plain/secret counters | fx-worker A |
| `addon/Forte_Timer/Core/Reconcile.lua` | the gated sweep: `Gates()` via `FX.SecretState`, `SweepUnit(token, kind)` (bulk `GetUnitAuras`, `GetAuraDataByIndex` fallback, per-name `GetAuraDataBySpellName`), all pcall + `PlainOrNil`, feeding `Rows` | fx-worker A |
| `addon/Forte_Timer/UI/RowsRenderer.lua` | §5: groups + labels + bars + texts + ticks + sparks + marks + flash; deltas D1–D15 | fx-worker B |
| `addon/Forte_Timer/Module.lua` | `FX.RegisterModule("Timer", M)` (`addon/Forte_Core/Core/Init.lua:19`), the single event frame, `/fx timer` (`FX.RegisterSlash`, `Init.lua:36`), the `/fx status` timer block, `FX.db.timer` | fx-worker A |
| `addon/Forte_Timer/Data/Registry.lua` (generated) | `FX.Timer.Register` from the class data (rows carrying `durationMs` + `mechanic`/`maxStack`/`dispel`), keyed by name (the name→id map shape: `addon/Forte_Hunter/Data/Hunter.lua:118-163`) | fx-worker C |
| `tools/gen_spell_data.py` (edit) | emit `mechanic`, `maxStack`, `dispel`, `isBuff` — `emit_entry` `:161-176` | fx-worker C |
| `addon/Forte_Options/Pages/Timer.lua` | the options page in the original's section order (spec `ST-36`), via `FX.Options:RegisterPage` | fx-worker D |
| `addon/Forte_Cooldown/UI/Rows.lua` (edit) | D1/D3/D5/D6/D9/D13 by **extraction**, not copy: `FX.Cooldown.ClassicSkin` gains a shape struct the row factory consumes | fx-worker B, after `Main` clears it |

**Not built** (decided; no scope creep): multi-instance cloning (`Forte_Timer.lua:2631-2710`),
profiles/clones, the filter editor, sounds, the per-spell registration DSL, tick *measurement*, pet rows,
the `CustomTag` editor. v1 = one instance, the fixed category palette, predicted rows, out-of-combat
reconciliation.

### Test plan (the sim is the only API proof, `PLAN.md` §10.2 rule 2)

Gate: `python3 scripts/gate.py --fast`. Per addon:
`cd /tmp && $WORK/wow-ui-sim/run.sh wow-ui-sim --allow-ui-version-mismatch --addons-path
$REPO/addon run-tests Forte_Timer`.
Style: `test()` + `assertTrue/Equals/NotNil/Nil`, seams restored inside the test, floats compared with a
tolerance — the conventions of `addon/Forte_Cooldown/tests/test_reconcile.lua:1-46`. Files under
`addon/Forte_Timer/tests/`. **Every behaviour change ships with a test that fails on the old code** (the
"fails-on" column states how that was checked).

| # | Case (deterministic; no real combat) | Asserts | Fails on the old code because |
|---|---|---|---|
| T1 | registry load for `HUNTER`: `Serpent Sting` → 12 s, `Hunter's Mark` → 120 s | exact seconds | new file + new fields (a registry test run before the generator change fails) |
| T2 | SENT(`Serpent Sting`, target `"Dummy-1"`) at `t0`, SUCCEEDED at `t0`; sweep at `t0+0.19` ⇒ **no row**; at `t0+0.21` ⇒ one row, `predicted`, `expireAt == t0+12`, `targetKey == "Dummy-1"` | the settle law with the ±0.02 bracket | the settle is new (an immediate insert fails at `t0+0.19`) |
| T3 | SENT of an **untracked** name ⇒ no row; SENT carrying a *secret* `spellID` (the sentinel-seam trick of `test_reconcile.lua:22,43-44`) ⇒ no row, `status.secret > 0` | name-keying + secret tolerance | new |
| T4 | same DoT on two dummies ⇒ **2 rows, 2 `groupKey`s**; recast on dummy 1 with `expire` inside `MAXLAG` ⇒ adopt ⇒ `predicted == false`, still exactly one row for that pair, `stacks` from the read | §3.3 keying + the adopt | keying by name alone merges the pair ⇒ the 2-row assert fails |
| T5 | `extend`: fact `expire = row.expireAt + 3` ⇒ survives, `expireAt` extended, `total` untouched. `refresh`: fact `expire = row.expireAt − 6` ⇒ old row `state == REMOVE` **and** a new row with the new window | §3.5 longer/shorter | a naive "always take the fact" pass leaves one row ⇒ the new-row assert fails |
| T6 | grace: an adoptable row 0.5 s from expiry is **not** removed; an unconfirmed row is checkable only after `BUFF_DELAY` | `:1207`, `:1186-1187` | a plain expiry cleanup passes ⇒ asserts fail |
| T7 | flash numbers: at `total-remaining == 0.25` the fill is the 0.5 mix of category and white; at `remaining == 1.5` the bg α equals `barBg ± 0.25*(1-cos(25*sqrt(1.5))))`; **no** flash at `remaining == 4` | §5.4, verbatim constants | new |
| T8 | sort/group: self-buff + 2 dummies ⇒ self band first (the `PRIOR_*` sentinels); `Outwands` reverses; `MaxTime = 30` clamps `maxTime`; `OneMax` picks the tallest visible | §1.4–§1.5 | new |
| T9 | gate: a row with `remaining == 45` is invisible under `HideLonger 30`, and its α ramps back over `HideTime` | `:2151-2162` | new |
| T10 | `Reconcile` refusals: `FX.SecretState.aurasSecret == true` ⇒ **zero** aura calls (the readers are counted seams); a reader that **raises** ⇒ no error escapes, no row mutates; a secret field ⇒ no mutation | §4.2, the safety story | new (and it is the launch-day safety net) |
| T11 | `RowsRenderer:Update` dump-tree numbers at a fixed fake clock: row height 14, bar width 235, group width 256, x-inset 18, label height 18, `SetValue` == expected `barval` (1e-6), `Max` cap honoured, pool size == rows shown, rows past *n* hidden | geometry numerically (no vision) | new |
| T12 | state machine: `NORMAL → FADING_INSTANT` for a `TargetDebuff`, `→ FADING` for a `SelfBuff`, deletion at `removeAt + FadeTime (+ TimerFadeSpeed)`, the expire message fires exactly once | §1.9 numbers | new |
| T13 | forbidden-surface scan of `Forte_Timer/**/*.lua`: no `COMBAT_LOG`, `SetUnitAura`, `UNIT_DESTROYED`, `PET_SPELLCAST`, `C_Glyph` | §4.3 stays closed | new |
| T14 | `api_lint` clean (gate step 4) with the event set asserted explicitly: `UNIT_SPELLCAST_SENT/START/SUCCEEDED/FAILED/INTERRUPTED`, `UNIT_AURA`, `PLAYER_TARGET_CHANGED`, `PLAYER_REGEN_ENABLED/DISABLED`, `ADDON_RESTRICTION_STATE_CHANGED`, `UNIT_DIED` | every cited name exists in the pinned catalog | new |

Screenshot scenarios for the owner's eye (`docs/media/sim/fx_timer_*.png`, the recipe from the brief):
(a) 6 rows on 3 dummies + 1 self-buff, clock advanced 4 s **before** capture, all predicted;
(b) the same at `remaining = 2.5` to catch the blink band; (c) `Label = true` with a target + focus group.
Report the dump-tree numbers; no visual claim (this agent has no vision).

---

## 7. Launch-day probes specific to the Spell Timer

Run through `/fx probe` (`addon/Forte_Core/Core/Probe.lua`, `PLAN.md` §11 B1) on the launch build
(`.build.info` re-check, `PLAN.md:361`). Record outcomes in `PLAN.md` §9 + §8.

| # | Probe | Pass shape | If it fails |
|---|---|---|---|
| P1 | **cast counter per spell, three states** (out of combat, in combat, in a dungeon/PvP, printing `IsAddOnRestrictionActive(0..5)`): for `Serpent Sting`, `Hunter's Mark`, `Scorpid Sting`, `Bestial Wrath` — one instant + one casted; is `spellID` plain and name-resolvable? (`docs/research/secrets-unknowns.md:32-36`, the ready probe block `:88-110`) | plain + resolvable in all three | the panel is blind in the restricted state ⇒ the "predicted, out of combat only" banner becomes permanent; escalate to `PLAN.md` §8 mitigation 2 (`Engine:OnActiveEdge`, `Engine.lua:316-334`) |
| P2 | **`UNIT_SPELLCAST_SENT.target`**: print the `PlainOrNil` class of the target string for a cast on `target`, on a named raid member, with no target, and inside a raid lockdown. This is the only field in the whole cast family flagged `ConditionalSecret` (`UnitDocumentation.lua:4802`) | plain, non-empty, resolvable out of combat; degrades only in a restricted state | **no per-target rows at all** ⇒ v1 collapses to self-buffs + a single current-target band; record as a scope decision (§8.1) |
| P3 | **`GetAuraDataBySpellName("target", name, "HARMFUL")`** for our own DoTs, out of combat on a dummy; then the identical call *in combat*; then in a dungeon. Print `expirationTime - GetTime()`, `duration`, `applications` and the `type()` of each | plain out of combat; a *defined* (nil / secret / raise) answer in combat | if it answers plain for **our own** DoTs in combat, in-combat reconciliation becomes legal for those rows ⇒ the single biggest v1 upgrade (run the sweep in combat behind `FX.SecretState`) |
| P4 | **`RequiresNonSecretAura` behaviour** on a tracked (ContextuallySecret) DoT: nil, error, or secret? — explicitly unknown in the docs (`docs/research/secrets-unknowns.md:255-260`) | any defined answer (the code must already tolerate all three, T10) | tolerance test only; P3 is the design gate |
| P5 | **`GetUnitAuras("target","HARMFUL PLAYER")`** vs `GetAuraDataByIndex` iteration on a dummies pile: does the bulk call exist, are the rows plain, does `PLAYER` really filter to *my* auras (print `sourceUnit`) | bulk works, filter clean | fall back to per-name `GetAuraDataBySpellName` sweeps (bounded by the ~30 tracked names ⇒ fine) |
| P6 | **`UNIT_AURA` delivery**: fires for `player` and `target` in plain combat? is `unitTarget` plain? (`UnitAuraDocumentation.lua:644`) | fires, token plain | the sweep becomes purely timed (1 Hz) — no correctness loss |
| P7 | **`GetRaidTargetIndex("target")`**, `UnitClassification("target")`, `UnitName("target")` in the three states (`RaidMarkersDocumentation.lua:54` `SecretReturns`; `UnitDocumentation.lua:965`, `:2488`) | plain out of combat, wrapped in combat | drop raid marks + the boss band from v1 (cosmetic only) |
| P8 | **`UNIT_DIED`**: does it fire, and is `unitGUID` plain, in plain combat (`UnitDocumentation.lua:4223`, `SecretWhenUnitIdentityRestricted`); `UNIT_DESTROYED` is known-absent | guid plain + matching ⇒ dead-mob cleanup | cleanup rides row-expiry + `UnitExists` polling only (rows die late — acceptable, note it) |
| P9 | **learned-duration survival**: write one `FX.db.timer.learned` row, full client restart, print it (the save order is best-guess, `docs/research/secrets-unknowns.md:677-710`) | survives | `learned` is session-only ⇒ every duration falls back to generated data |
| P10 | **asset reality check**: `C_Spell.GetSpellTexture(name)` renders; `Textures\ST` + the `0.133…0.867` crop renders; `URWGothic-Book.ttf` loads (the real-client font check is still open, `PLAN.md:399-402`) | icon + font render | icon falls back to `AuraData.icon` (a fileID); font to the `GameFontHighlightSmall` class (the original's own default, `Forte_Timer.lua:1701`) |

---

## 8. Open questions for the owner

1. **v1 population.** With own-cast predictions as the only source, the panel shows self-buffs, CC, DoTs
   and every spell carrying `durationMs` — for Hunter ~20 data rows
   (`addon/Forte_Hunter/Data/Hunter.lua:11-45`). That is a thin panel against `demo3-000245.png`. Ship
   them all, or a curated default (DoTs + CC + major windows)?
2. **Is reconciliation visible at all?** P3/P4 decide it. If in-combat reads are dead (the expected
   answer), a real fight shows **pure prediction, never corrected**: refresh/clip is invisible and the bar
   position is data arithmetic. Accept that as the Forever ceiling (with §5.5's marking), or add the
   Cooldown-style boolean tier for auras — note the boolean tier (`Engine.lua:336-390`) has **no aura-side
   equivalent** today, so it would be new design, not a port.
3. **Group labels by default.** The original ships `GroupID true / Label false`
   (`Forte_Timer.lua:3319`, `:3341`), yet the label is what makes a multi-target stack legible
   (`demo3-000245.png`). Keep the original's default, or flip `Label` on for v1?
4. **`Rows.lua` sharing.** D1–D15 need the row factory parameterised (a shared shape struct) so the
   Cooldown Timer's Classic skin and the Spell Timer do not fork. That touches a file the Cooldown wave
   authored (currently dormant, unlisted in §10.1). Approve the extraction, or fork a `Forte_Timer/UI/`
   copy (cheaper, uglier)?
5. **Data pipeline change now?** `mechanic` / `maxStack` / `dispel` / `isBuff` are all present upstream
   (key census over 7,503 rows today) and are what make the Curse/Magic/Enrage colours and the
   shared-group eviction real. Add them to `tools/gen_spell_data.py:161-176` (byte-regen of 10 data sets
   + the determinism gate), or keep v1 colour-by-category only?
6. **Corrections to log in `PLAN.md` §9** — the six rows of §1.11, all verified against the source today.
7. **The ceiling wording.** The §5.5 title/tooltip text is user-facing and permanent on Forever. Owner's
   preferred phrasing?
8. **Pet windows.** With zero `*PET_SPELLCAST*` symbols on the client, Hunter pet DoTs and Warlock
   Devour Magic / Spell Lock / Seduction (spec `CA-28`) are unrepresentable. Confirm they are struck from
   Phase 3/5 expectations so the plan text stays honest.
