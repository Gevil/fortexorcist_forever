# Options fidelity — our pages vs the original's option tree

Agent `OptionsScout`, 2026-11-02 (Wave 3, H8s). Read-only survey.

## Answer (headline)

The **shape** of our options system is faithful: one window, module index, collapsable
sections, per-option + per-section + per-module resets, profile tabs in the original's
own position. The **content** is a deliberate, mostly-labeled subset. Measured against
the original's registrations, our module pages carry roughly:

| Page | Original rows (AddOption, excl. INF) | Ours | Most-missed |
|---|---|---|---|
| General | 9 (+5 INF) `Forte_Core/Options.lua:5537-5556` | 7 | RightClick rows, GlobalSpark |
| Cooldown | 34 (+9 INF) `Forte_Cooldown/Forte_Cooldown.lua:1696-1768` | 20 | Alpha/AlphaMax, IconTime trio, 4 range filters, per-bar Splash, category enable gates |
| Splash | 3 `Forte_Cooldown.lua:1775-1780` | 7 (4 = ours) | — (superset) |
| Spell Timer | 57 (+9 INF) `Forte_Timer/Forte_Timer.lua:3138-3257` | 36 | Blink, FadeTime/FailTime/HideTime, Outwands/Flip, TicksNext, unit-scope gates, category color rows |
| Soulstone | 21 `Forte_Soulstone.lua:595-645` | 8 | ShowReady/ShowAll, Details, Expand, Space, Max, 9 colour rows — mostly raid-panel features (SS-05) |
| Healthstone | 15 `Forte_Healthstone.lua:282-317` | 8 | 4 spy-bar colour rows, Space, Details/Auto, Interval |
| Summon | 13 `Forte_Summon.lua:538-574` | 7 | Details/Expand/Closer/Keyword — mostly roster features (SU-02) |
| Party/Raid Msg | 2 Core + ~40 module rows (`Forte_Core/Options.lua:5558-5564` + module files) | 107 (structure rows; ~90 generated) | Soulstone Start/Cancel + whispers, Seduce/SpellLock/DevourMagic pet rows, DK rows |
| Self Messages | 4 (+1 INF) | 13 (10 = ours) | Blood Pact trio (parked) |
| Sound | 6 SND rows +1 INF | 12 (3 rows = ours; 12 keys/4 files) | **Soulstone Fade/Ready sounds** (verbatim pair missing) |
| Advanced | ~35 | built 2026-11-03, 12 rows | startup text, scroll/expand prefs, per-module strata (shipped); Core intervals, snap, columns dropped (see "Advanced cell") |
| Hunter Tools | **0** (`Forte_Class/Hunter/Hunter.lua` has zero AddOption) | 21 | no original baseline (all ours, WST law) |
| Profiles | no cell in the original grid | full page + tab row | documented match, `Pages/Profiles.lua:4-14` |
| About | 4 IMG/URL + 20 INF | 7 INFO | fine (2012 URLs are dead) |

Biggest genuine fidelity gaps (details per page below): the **Soulstone sound pair**,
the Cooldown **Alpha/AlphaMax pair + IconTime trio + the four range filters + the
per-bar Splash**, the Timer **Blink/FadeTime/FailTime** set, the original's **label text**
on a handful of rows (Time scale max, Use power of, Show icon Glow, Hide when out of
combat, Expand up, Show unit #, Show name tags/headers, Show in party/raid), and three
**default drifts** (AltTimeFormat, FrameSnap, Timer Max / ExpiredColor).

## Method

- Original tree = every `SetMainCategory`/`SetSubCategory`/`AddOption` in `/tmp/fxref/`
  (API at `Forte_Core/Options.lua:4264-4289`); defaults from `FW.Default`
  (`Forte_Core/Forte_Core.lua:2469-2545`) and the `FW.InstanceDefault.*` blocks
  (`Forte_Cooldown.lua:1801-1874`, `Forte_Timer.lua:3310-3419`) plus module
  `FW.Default.*` rows. Labels from the English blocks of the `Localization.lua` files.
- Ours = the 10 page files + `Forte_Options/UI/Window.lua`.
- Verdicts: **add** / **keep ours** (why) / **not feasible** (why) / **parked** (needs a
  feature that is not ported).
- Not verifiable on disk: the original's Shard Spy / Shard Manager / Casting option rows
  (modules not in `/tmp/fxref/` — the snapshot lacks them; Casting is present), the
  module-grid cell labels for indices 2/6/9 (the panel PNG vision pass failed;
  marked `[INFERENCE]`), the original window's title bar text (XML, not in the
  snapshot). The original's index indices, in code order: General 1
  (`Options.lua:5535`), Spell Timer 3 (`Forte_Timer.lua:3138`), Cooldown 4 and
  Secondary Splash 4 (`Forte_Cooldown.lua:1696,1770`), Soulstone 5
  (`Forte_Soulstone.lua:595`), Healthstone 7 (`Forte_Healthstone.lua:282`), Summon 8
  (`Forte_Summon.lua:538`), Party/Raid 10 / Self 11 / Sound 12
  (`Options.lua:5558,5566,5570`), Talent Spy 13 (`Forte_Talent.lua:366`),
  Advanced 99, About 100 (`Options.lua:5574,5630`).

## Window / index (`UI/Window.lua` vs `Forte_Core/Options.lua`)

| Aspect | Original | Ours | Verdict |
|---|---|---|---|
| Index cells | code-ordered set above; Shard cells at 2/6/9 `[INFERENCE]` | `Window.lua:78-103` adds **Hunter Tools** (no original class cell) and keeps ShardSpy/ShardManager/TalentSpy/Advanced dim | keep ours (extra cell = our class-tool law; dimmed cell = the original's own Talent Spy shipped disabled, `Forte_Talent.lua:366-371`) |
| Tab row | tabs are **clones** per category (multiple bar instances; `Options.lua:4847-4901`), profiles live as the General category's tabs only (`tab_actions` :5454-5469) | one global profile tab row on every page (`Window.lua:459-498`) | keep ours (`Pages/Profiles.lua:4-14` states it). **Clones/multi-instance: not implemented at all** — every `tab_data`/`InstanceDefault` in the original (`Forte_Cooldown.lua:1696` "Cooldown", `Forte_Timer.lua:3138` "Timer") means N bars of one module; our engine is one instance per module. This is the largest structural gap of the whole system |
| Clone/profile linking | Options Linking section, 8 colour rows + 2 buttons + 2 CHKs (`Options.lua:5595-5614`, defaults `Forte_Core.lua:2497-2510`) | none | not feasible (needs clones) |
| Per-module header scale/alpha/lock | strings exist (`Localization.lua:242` "Lock (disable dragging)", `:261` Scale, `:417` "[restore alpha]"); header controls `[INFERENCE]` | `Window.lua:764-805` scale 0.2..5.0 / alpha 0.1..1.0 / lock | keep ours |
| Section tips line | "Some Tips" `FWL.GENERAL_TIPS` (`Localization.lua:307`), 5 lines on General | `b.Tips` 3-6 per page | keep ours |
| Frame strata per module | 7 STR rows "Frame level (strata)" (`Options.lua` Advanced: `Forte_Cooldown.lua:1790,1793`, `Forte_Timer.lua:3266` region, `Forte_Soulstone.lua:645`, `Forte_Healthstone.lua:316`, `Forte_Summon.lua:573`); label `Localization.lua:440` | none | **feasible** — `SimpleFrameAPI:SetFrameStrata` is in the pinned catalog (`docs/api/wow-addon-api-agents` api-coverage: SimpleFrameAPIDocumentation.lua:1292, frameStrata enum BACKGROUND..TOOLTIP per XML-FRAME-WIDGETS.md:44). Goes with the Advanced page |

## General page (`Pages/General.lua`)

Original: `Options.lua:5535-5556`. Tips ×5 (`:5537-5543`) · **General Module Options**
`:5544-5549`: RightClickOptions, RightClickIconOptions, TimeFormat, GlobalLock,
GlobalAlpha · **General Module Appearance** `:5551-5556`: Tips, GlobalSpark, Font, Texture.

| Row | Original (file:line, default) | Ours (file:line, default) | Verdict |
|---|---|---|---|
| Global Frame Lock | `Options.lua:5548`, def `false` (`Forte_Core.lua:2508`); label `Localization.lua:361` | `General.lua:82-86`, def **true** (`:28`) | keep ours (ship-locked law) — record the default drift |
| Global Frame Alpha | `Options.lua:5549` "Global Frame Alpha" (`Localization.lua:415`), def 1.0 (`:2509`) | `General.lua:87-91` "Global Frame Alpha" (label match), def 1.0 | keep ours (row parity) |
| Alternate time format | `Options.lua:5547` "Alternate time format" (`Localization.lua:316`), def **true** (`Forte_Core.lua:2493`) | `General.lua:97-101`, def **false** (`:32`) | **default drift — add the flip** (original defaults to m:ss) |
| Enable frame snapping | ADVANCED `Options.lua:5581-5583` (with FrameSnapDistance=5, FrameDistance=0, `Forte_Core.lua:2481-2483`), def **true** | on General `General.lua:92-96`, def false (`:31`), stored-only | keep placement (ours is one-settings-page); **add the 2 distance rows** with the snap grid; record default drift |
| Show module frame Tooltips | `Options.lua:5552` (`Localization.lua:423`), def true (`:2514`) | `General.lua:112-116`, def true | keep ours (label + default match; tip honest "not used yet") |
| Right-click headers for options | `Options.lua:5545`, def true (`:2495`) | missing | **add** (feasible: bar OnMouseUp → `Open(pageId)`) |
| Right-click icons to customize | `Options.lua:5546`, def true | missing | parked (needs the per-spell filter editor) |
| Show Sparks (global) | `Options.lua:5554`, def {on,0.7} (`:2511`) | per-page spark keys (`Cooldown.Spark`, `SpellTimer.EnableSpark`) | keep ours (no second global multiplier) |
| Bar Font / Bar Texture | `Options.lua:5555-5556` FNT/TXT pickers, def GOTHIC.TTF 11 (`:2506` — ours URW by PLAN §3.5) | `General.lua:117-128` INFO (read-only) | **add the picker** later (INFO is a labelled placeholder; the vendored-font law stands) |
| Order | Tips, Module Options, Module Appearance | same order | parity |

## Cooldown page (`Pages/Cooldown.lua` vs `Forte_Cooldown.lua:1696-1794`)

Original sections: Tips(3) · Basics `:1702-1707` Enable, Vertical, Flip, Hide, HideCombat ·
Specifics `:1710-1720` GroupOverride, Spark(glow α), Warn, Alpha, AlphaMax, IconTime,
IconTextColor, IconFont · Splash Icons `:1722-1724` Splash, SplashFactor ·
Time Range `:1726-1734` Max, Loga, MinRange, MaxRange, MinRemaining, MaxRemaining,
Tags, CustomTags · Coloring/Filtering `:1736-1737` FIL · My Cooldowns `:1739-1748`
9 × CO2 (enable+colour) · Buffs/Debuffs(on me) `:1750-1755` 5 × CO2 ·
Frame Sizing `:1757-1760` Width, Height, IconSize · Frame Appearance `:1762-1768`
BarColor, BgColor, TextColor, Font, Texture, Backdrop.

| Row | Original (file:line, default) | Ours (file:line) | Verdict |
|---|---|---|---|
| Enable | `:1703`, def true `:1802` | `Cooldown.lua:156` | parity |
| Vertical / Flip | `:1705-1706`, def false `:1808-1809` | `:160-166` verbatim labels + defaults | parity (CD-35 pass) |
| Auto-hide when no cooldowns (Hide) | `:1707` (label `Forte_Cooldown/Localization.lua:110`), def false `:1813` | `:167-169` "Auto-hide when no cooldowns" | parity |
| Hide when **out of** combat | `:1707` TIMER_HIDE (label `Forte_Core/Localization.lua:526` "Hide when out of combat"), def false `:1814` | `:170-172` "Hide when **not in** combat" | **renamed — fix label** to the original's |
| Lock | not a Basics row (header law) | `:157-159` | keep ours |
| Group Master Icons | `:1712` (label `Forte_Cooldown/Localization.lua:150`), def true `:1822` | missing | parked (engine has no master-icon grouping yet) |
| Show icon Glow (Spark) | `:1713` NU2 alpha 0..1, def {on,1} `:1820` (label `:145` "Show icon Glow") | `:214-215` CHK "Spark" in Frame Appearance, def true | keep bool; **relabel "Show icon Glow"** (α-slider upgrade = Phase 2) |
| Spell on cooldown Warning | `:1714`, def true `:1821` | `:180-182` verbatim | parity |
| Minimum/Maximum bar alpha (Alpha/AlphaMax) | `:1717-1718` (labels `Localization.lua:118` / `:161`), defs 0.2 / 1.0 (`:1818-1819`) | missing | **add** (PLAN Phase 2 "Alpha/AlphaMax") |
| Show Icon text + Icon text color + Icon Font | `:1719-1720`+`:1720` (label `Localization.lua:140`), def IconTime=true `:1846` | missing (icon time always drawn) | **add** gate + colour (+ font low) |
| Splash / SplashFactor (per-bar ready splash) | `:1722-1724` (labels `:122,124`), def Splash=true, SplashFactor=4 (`:1811-1812`) | missing (we only have the SEPARATE Secondary Splash page) | **add** — distinct effect (icon flashes at the bar origin), PLAN Phase 2 |
| Time scale max (Max) | `:1727` label "Time scale max (sec)" (`Localization.lua:114`), def 300 `:1815` | `:187-189` "Max time", 300 | value parity; **relabel** |
| Use power of (Loga) | `:1728` label `:163` "Use power of", def 0.33 `:1832` | `:190-193` "Power scale (Loga)" | value parity; **relabel** |
| Min/Max duration + Min/Max remaining | `:1729-1732` (labels `:175,177,180,182`), all gates off `:1826-1829` | missing | **add** (PLAN Phase 2 "Min/Max range and remaining filters") |
| Amount of time tags + Custom tags | `:1733-1734`, Tags=6 + CustomTags {on,"0 1 10 30 60 120 300 600"} (`:1833-1834`) | `:194-196` single STR "Custom time tags" with the verbatim list | keep ours (§3.5 pins the tag list; the count row is inert under custom tags) |
| Ignore shorter than | ADVANCED `:1791`, def 2.99 (`:1796`) | Specifics `:197-200`, 2.99 | keep ours (relocated, same default) |
| Category rows CO2 (Spell, Pet, Item, Powerup, Internal/Hidden, Potion, Healthstone, **Soulstone**, **ResTimer**) | `:1740-1748`, defs `:1842-1855` (Soulstone {.64,.21,.93}, ResTimer {1,0,0}, Healthstone {0,1,.5}) | `:202-215` colour rows for Spell/Powerup/Item/Potion/Pet/Internal/Buff/Debuff (no enable gates) | **add** the Soulstone/ResTimer/Healthstone/Enchant colour rows if those categories draw on our bar; enable-gates parked behind the filter editor (FIL `:1737`) |
| Buff/BuffOther/Debuff/DebuffOther/Enchant | `:1751-1755`; the *Other rows ship gate-off (`:1852,1854`) | Buff/Debuff colour present; *Other/Enchant missing | keep (no catch-all filter in v1); Enchant = add with item procs |
| Icon size (independent of bar height) | `:1760` NU2, def gate-off 36 `:1805` | missing (icon rides Height) | **add** (low) |
| Bar text colour | `:1765` def {1,1,1,0.20} `:1841` | missing (Timeline text fixed) | **add** |
| Font / Texture / Backdrop | `:1766-1768` | none (pinned URW + Aluminium, PLAN §3.5) | keep ours (the 2012 texture-picker law is superseded by the vendored-asset law) |
| Section order | Basics, Specifics, Splash, Time Range, Coloring/Filtering, My Cooldowns, Buffs/Debuffs, Frame Sizing, Frame Appearance | Basics, Specifics (geometry+range+advanced merged), Coloring, Frame Appearance | keep ours (documented); note for a future layout pass |

## Splash page (`Pages/Splash.lua` vs `Forte_Cooldown.lua:1770-1780`, `:1868-1874`)

| Row | Original (line, default) | Ours | Verdict |
|---|---|---|---|
| Enable | `:1776` "Enable Secondary Splash icon" (`Forte_Cooldown/Localization.lua:126`), def **false** `:1869` | `Splash.lua:92-93`, def false (`:34`) | parity (label text is ours — original label = add) |
| SecondSplashMax | `:1779` "Splash icon active scale" (`:124`), def 4 `:1870` | `:100-103` "**Peak size**", 4 | value parity; **relabel** |
| Glow | `:1780` "Show icon Glow", def true `:1871` | `:108-110` "Glow", true | value parity; **relabel** |
| Lock, SplashMax, Alpha, Scale | no rows (alpha 0.7 / scale 2 are defaults `:1872-1873`; cap fixed at 4) | `:94,104,96` present (SplashMax documented CD-28; Alpha/Scale exposed defaults) | keep ours (labelled additions) |

## Spell Timer page (`Forte_Timer/Pages/Timer.lua` vs `Forte_Timer.lua:3138-3310`)

Original sections (counts): Tips(3) · Basics `:3145-3151`: Enable, Expand, Outwands, Flip,
Test, Hide · Additional layout `:3153-3162`: RaidTargets, Time, TimeRight, Icon, IconRight,
IconStacks, StacksFont · Naming and Grouping `:3164-3172`: GroupID, Label, LabelFlip,
LabelLimit, Name, Spell, CustomTag, ShowID · Visual Casting Aid `:3174-3182`: Spark,
SparkDamage, CastSpark, CastSparkTickOverlap, CastSparkGCD, Ticks, TicksNext ·
Maximum Time and Hiding `:3184-3190`: OneMax, MaxTime, ForceMax, HideLonger,
HideLongerNoBoss, HideTime · Fading `:3192-3199`: FadeTime, FailTime, Blink,
BarBackgroundAlpha, ExpiredColor, HighlightColor · Units `:3200-3208`: RaidDebuffs,
Target, Focus, Other, UnknownTarget, NoTarget, You, NormalAlpha · Coloring/Filtering
`:3210-3211` FIL · My Spells `:3213-3220`: Default, Crowd, Heal, Buff, Channel, Pet, Fail ·
My Cooldowns `:3222-3224` · Buffs/Debuffs `:3226-3231` · Raid Debuffs `:3233-3235` ·
Frame Sizing `:3237-3244`: Width, Height, Space, SpacingHeight, LabelHeight, Max ·
Frame Appearance `:3246-3256`: 10 rows.

Key comparisons (defaults block `Forte_Timer.lua:3310-3419`):

| Row | Original (line, default) | Ours (`Timer.lua`) | Verdict |
|---|---|---|---|
| Expand up | `:3146` "Expand up" (`Forte_Core/Localization.lua:243`) def true `:3327` | `:349-350` "**Grow upwards**", stored-only | **relabel** (the original's words exist; our tip says so) |
| Highest timers outwards / Flip bar direction / Enable Test Bars | `:3148-3150`, defs Outwands=true, Flip=false, Test=false (`:3330-3331,3311`) | missing | **add** Outwands+Flip (feasible sort/geometry); Test bars: our tests inject payloads (test law) — parked |
| Show Count down text / on right | `:3155-3156`, defs Time=true, TimeRight=false | time always shown; no side choice | keep v1 (design §5.4 law); add TimeRight later |
| Show icons / Icons on right | `:3158-3159`, defs Icon=true, IconRight=false | icons always on | keep v1 |
| Show unit # | `:3172` label `Forte_Timer/Localization.lua:73` "Show unit #" | `:228-229` "Show the buff id" | **relabel** |
| Show name tags/headers | `:3165-3166` (label `:77`); GroupID=true, Label=false (`:3323,3335`) | `:222-223` "Show group labels" (one merged row, def true) | **relabel**; merged gate = keep (our grouping is always on) |
| Show Ticks + Next Tick only | `:3181-3182`, defs Ticks={on,0.3}, TicksNext=true (`:3400-3401`) | `:341-342` ShowTicks only | **add** TicksNext |
| Adapt to one maximum / Force max | `:3185-3187`, defs OneMax=true, MaxTime={on,30}, ForceMax=false | `:312-315` one MaxDisplayTime=30 | keep ours (one-scale model; OneMax = our always behaviour) |
| Hide timers if remaining over / No hiding on bosses / Pre-hide display time | `:3189-3191`, defs off/off/2 | missing | parked (hide-longer needs boss metadata; feasibles later) |
| Standard fade delay / Failed display time / Blink expiring bars | `:3193-3195`, defs FadeTime=1, FailTime=2, Blink={on,3} (`:3348-3349,3343`) | missing (Blink/flash is Skin-fixed: ColourFlash law) | **add** Blink + FadeTime (the original's expiry cue IS the blink — design §5.4 cites `:1562-1569`) |
| Show target/focus/other/unknown/no-target/you/raid-debuffs | `:3201-3207`, all true (`:3352-3358`) | fixed v1 scope | parked (v1 = own casts; the gates are a Phase-4 surface) |
| Category colour CO2 rows (Default, Crowd, Heal, Buff, Channel, Pet, Fail, Cooldown, SelfBuff, SelfDebuff, Enchant, TargetDebuff) | `:3214-3235`, defs `:3376-3392` | per-CASTER BarColor* ×5 (page says stored) | the original colours **per category**; ours is the open design question (page tips cite ColorVal `:1524-1573`); keep + record |
| Max shown | `:3244` NU2 def **{off,15}** | `:250-252` def **32**, gate min 4 | **default drift — manager call** (align to 15-gate-off, or keep the wider cap by law) |
| Bar bg alpha / Normal alpha | `:3197`+`:3207`, defs 0.3 / 0.50 (`:3367-3368`) | `:316-320` 0.3 / 0.5 | parity |
| Expired colour gate | `:3198` def {**off**,.5,.5,.5} `:3371` | ColourExpired {1,1,1} live | **default drift** (original defaults grey-expired OFF) |
| Frame Sizing Width/Height/Space/SpacingHeight | `:3238-3241` defs 250/14/2/2 (`:3363-3365,3345`) | 250/14/2/2 | parity |
| Unit label height | `:3243` def 18 `:3340` | missing | **add** (low) |
| Normal text/bg, target/focus colours, fonts, texture, backdrop | `:3247-3256` | ColourNormal ✓; target/focus pair absent; Font/Texture/Backdrop none (backdrop via EnableBackdrop) | keep v1 pair |
| Position (IconOffset, OffsetSelf, OffsetTarget) | none (one shared inset law `:2322`) | `:386-399` | keep ours (labelled port knob) |
| AnnounceExpiry | the module's own fade channel `:1049-1056` is the fade/break announce | `:351-352` opt-in | keep ours (m7 law) |

## Soulstone page (`Pages/Warlock.lua` "Soulstone" vs `Forte_Soulstone.lua:595-678`)

Original: Tips(1) `:596-598` · Basics `:599-604`: Enable, Auto-hide (SoulstoneAuto),
Auto-minimize (DetailsAuto), Show bars (Details), Expand up · Specifics `:606-608`:
ShowAll, ShowReady · Sizing `:610-615`: Width 100 (`:670`), Height 12 (`:671`), Space 1
(`:675`), Max 10 (`:669`) · Bar Coloring `:616-626`: Max {.64,.21,.93} `:652`,
Min {1,0,.6} `:653`, Ready {1,1,0} `:651`, Dead `:655`, Offline `:654`, Mix .5 `:649`,
Warlock/Druid/Paladin/Shaman class colours `:650,656-658` · Appearance `:628-631`.

Ours: Basics(Enable, master, Lock, ShowTime), Sizing(width 106, bar height 12),
Coloring(SoulstoneColor = the Max colour ✓, shared plate pair = BgColor `:659` ✓).
Verdicts: the Auto/minimize/show-all/Max/dead/offline/class rows are the **raid-wide
panel** features the SS-05 ruling froze — **not feasible** (auras sealed; page Tips say
so). Feasible, worth adding: **Expand up** (single plate grows up/down; def false `:674`),
**ReadyColour** gate for the "ready to RES" state (the plate's ready state exists —
`ShowReady` def false `:667`), Space (needs the bar list; parked). Width 100→106 is the
border math, documented in `Pages/Warlock.lua:56-60` — keep.

## Healthstone page (vs `Forte_Healthstone.lua:282-341`)

Same structure. Present in ours: Enable, Unknown ("Show players with no info" verbatim,
def true `:341`) ✓. The spy bars (Total / No-info) ride our group comms (page Tips
`:206-208`), so the spy-half rows are feasible: **add** the 4 bar colours (Min {.93,1,0}
`:334`, Max {.53,1,0} `:335`, UnknownMin `:336`, UnknownMax `:337`), Details/Auto/
DetailsAuto (`:288-292`), Space (bar row spacing `:300`), and the Advanced
`HealthstoneInterval`=2 (`:318,:321`) when the sweep is exposed. Expand-up as above.

## Summon page (vs `Forte_Summon.lua:538-609`)

Present: Enable, Width/Height, SummoningColor ✓. Missing: Details (`:545`, def true
`:602`) — our bar IS the channel bar, add; Expand (`:546`, def false `:609`) — add;
Closer (`:549`, def false `:604`) = the summoner closes portal windows — parked
(no portal-window feature); Keyword (`:550`, def "summon" `:607`) + Max (`:557`, def 5
`:606`) + Far/Close/Whisper colours (`:560-563`) = the roster/distance list — **not
feasible** (SU-02, Tips `:306` say it); SummonInterval/SummonOldMode (`:574-575`) N/A
without the roster.

## Party/Raid Messages page (`Forte_Messages/Pages/RaidMsg.lua`)

Core rows parity: the two master switches (`Options.lua:5563-5564`, def OutputRaid=true,
Output={on,"MyProChannel"} `Forte_Core.lua:2513-2514`) vs `RaidMsg.lua:148-150,431-441`
(OutputRaid true, OutputEnable true, channel "SAY") — shape parity. Labels: the
original's = "Show in party/raid (1st checkboxes)" / channel twin
(`Forte_Core/Localization.lua:283`); ours "Allow party/raid announcements" / "Allow
say/yell/channel announcements" — **renamed**, keep ours (clearer, `(1st checkboxes)`
refers to the 2012 row layout).

Defaults: the original's announce trio CooldownLeft/TimeLeft/TimeLeftNoTarg ship
**party-ON** (`Forte_Core.lua:2524-2526`, bits `{[0]=1}`); ours ship OFF under the E2
ruling (page header `:26-33`) — **keep** (recorded ruling).

Missing registrations (all `MS2` party+channel pairs, all shippable behind the E2 law):

| Missing row | Original | Verdict |
|---|---|---|
| SoulstoneStart / SoulstoneCancel (+Start/Cancel whispers; Success whisper) | `Forte_Class/Warlock/Warlock.lua:294-295`+`:297-299`; whisper defaults `Warlock.lua:357-359` (Success ON, Start/Cancel OFF) | **add** — our Soulstone cast events exist; the whispers are the original's half the page header (`:25-33`) does not mention |
| SummonFinish ("Portal summoned") | `Warlock.lua:291` | parked (no port feature) |
| SoulwellStart | `Warlock.lua:302` | parked (2012 Ritual-of-Souls; not in the 7-class data law) |
| SeduceStart / Success / Failed | `Warlock.lua:307-309` | **add** (Seduction pair is live 70707 — page header `:83-105` proves the data; PetRows v2 feeds it) |
| SpellLockSuccess/Failed/Ready, DevourMagicSuccess/Failed/Ready | `Warlock.lua:310-327` | **add** (both spells are in the live client store per the page's own `:88-92` evidence) |
| Raise Ally (RAStart), Icebound Fortitude (IBFStart) | `Forte_Class/DeathKnight/DeathKnight.lua:247,264` | **add** the pair after the DK cutover (T1); the T2 scope was Druid/Paladin/Warrior only |
| BloodPact self-announce trio | on SelfMsg, `Warlock.lua:349-352` | see SelfMsg |
| "Fading" sub-category label | the original groups its announce rows under "Fading" (`Forte_Cooldown.lua:1783`, `Forte_Timer.lua:3260`) | our sections are per-spell — order/grouping difference, keep |

20 cast rows + 6 CC pairs: our texts and the recorded `bits` are verbatim (rows carry
their `src` file:line, e.g. `RaidMsg.lua:135-300`) — the strongest page.

## Self Messages page (`Pages/SelfMsg.lua`)

Original: Tips(1) `Options.lua:5567-5568` + 4 module rows:
TimerResistsColor (`Forte_Timer.lua:3267`, def {on,1,0,.54} `:3292`), SoulstoneMsgColor
(`Forte_Soulstone.lua:636`, def {on,1,0,1} `:672`), BloodPact trio
(`Forte_Class/Warlock/Warlock.lua:349-352`).
Ours: Ready(6) + Expire(7) event pairs. The colours are the original's verbatim
(Ready {1,1,0} = `Forte_Soulstone.lua:651` (the original itself writes that default as
`Read yColor` at `:651` — a real 2012 key typo: row key "ReadyColor" `:619`); Expire
{1,0,1} = `:672`). Verdicts: **keep ours** (the original's SelfMsg rows are per-event
colour gates for a fixed set; our events are the ones the Forever engine emits);
TimerResistsColor **not feasible** (no legal resist signal — the Sound page's m4 ruling
`Pages/Sound.lua:50-56` covers the family); BloodPact **parked** (MoP talent; probe at
launch). The banner rows are labelled NEW in-file. ✓

## Sound page (`Pages/Sound.lua`)

Original SND rows: Timer Fade/Break/Resist (`Forte_Timer.lua:3270-3272`, defs
`{on,"ShaysBell.wav",2}` / `{on,"…LevelStart.wav",4}` / `{on,"…BadPress.wav",1}`
`:3297-3299`), **Soulstone Expired/Ready** (`Forte_Soulstone.lua:640-641`, defs
`{on,"…SoulstoneExpire.mp3",1}` / `{on,"…GameTick.wav",1}` `:677-678`), Warlock Instant
(`Forte_Class/Warlock/Warlock.lua:346`, def {false,…} `Forte_Timer.lua:3300`).
Ours: Fade ✓ verbatim, Break ✓ verbatim, Expire(new), CooldownReady(new), Resist absent
by the recorded m4 ruling ✓. **GAP: the Soulstone Fade/Ready sound pair is missing and
unlabelled** — our Soulstone plate knows the predicted window end (its whole purpose),
so both signals exist. **add** (verbatim defaults). TimerInstantSound: parked
(instant-proc display not ported). The `[0]/[1]/[2]` law renders as enable/path/times ✓
(the `[2]`-is-repeat-count reading per `Forte_Timer.lua:3297`).

## Hunter Tools page

The original Hunter class module (`Forte_Class/Hunter/Hunter.lua`, 197 lines) registers
**zero** options — pure spell data (and a forbidden COMBAT_LOG_EVENT_UNFILTERED handler
`:120-160`). Our 21 rows descend from WeaponSwingTimer (research
`docs/research/weaponswingtimer.md`), not from the original. Verdict: **keep ours**
(no baseline to be unfaithful to); the grid cell "Hunter Tools" is our addition.

## Shard Manager / Shard Spy cells

The shard modules are not in `/tmp/fxref/` — no original tree on disk to diff. Shard
Manager page = our design; ShardSpy stays dim per the warlock-tools law
(`Pages/Warlock.lua:6-10`). Verdict: no claim made.

## Advanced cell (v1 built 2026-11-03: `Pages/Advanced.lua`, 12 rows)

SHIPPED, every row with a live consumer: `ShowStartupText` (the login print,
`Forte_Core/Core/Init.lua` `PrintStartupLine`); `AnimateScroll`,
`ExpandSubcats`, `LoadExpandSubcats` (the window's wheel and section-fold law,
`UI/Window.lua` `Scroll`/`StartCollapsed`/`RememberCollapse` — `ExpandSubcats`
ships TRUE, the recorded panel-look drift, the fold law is live); eight
`<Module>Strata` rows (`Cooldown`, `Splash`, `Timer`, `Hunter`, `Shard`,
`Soulstone`, `Healthstone`, `Summon`) landing on each frame's `SetStrata` →
`SetFrameStrata` (the catalog's eight names validated at the consumer).
`RightClickOptions` is a row of the **General** page (`Options.lua:5550` sits
in that category; consumer: the Cooldown bar's `OnMouseUp` gate).

DROPPED, no consumer: `FrameSnap`/`FrameSnapDistance`/`FrameDistance` (every
frame drags via the engine's native `StartMoving`; no snap grid exists — the
registered `General.FrameSnap` key stays stored-only and says so); Core
`LoadDelay`/`UpdateInterval`/`AnimationInterval`/`Chill` (fixed per-module
cadences, none reads a setting); `OptionsColums`/`OptionsHeight` (fixed grid,
fixed 780x650 window); `GlobalFrameNames` (compiled in); `TimerSpellsTooltip`,
the Options Linking block (no spell-group tooltips, no clones), the options
appearance rows (no themable window); `REMOVE_BACKUP`.

The survey this came from (the original's ADVANCED, `Options.lua:5574-5629`
plus module rows: 7 strata rows, Casting `Forte_Casting.lua:868-874`,
module intervals, IgnoreCooldown, per-module strata) and Core
(`Options.lua:5626-5630`: LoadDelay 1, UpdateInterval 0.5, AnimationInterval 0.04,
Chill 0.05, defaults `Forte_Core.lua:2472-2475`). Feasibility notes kept for the
dropped set: strata + startup text
(`ShowStartupText` def true `:2529`) + AnimateScroll (`:2477`) + ExpandSubcats/
LoadExpandSubcats (`:2530-2531`) + Core intervals = **feasible** (all our own
mechanics); OptionsColums = inert (our builder is fixed 2-col, `Window.lua:565-585`);
Options Linking / clone rows = not feasible; Casting rows = parked (module not ported);
REMOVE_BACKUP = N/A (no backup cache).

## Defaults audit (all, with source)

Parity (verbatim defaults): Cooldown Width/Height/Max/Loga/Tags/Ignore/colours/Bar·Bg
(`Forte_Cooldown.lua:1801-1866` ↔ `Cooldown.lua:28-81`); Splash trio (`:1868-1874`);
Timer geometry/alphas (`Forte_Timer.lua:3363-3368` ↔ `Timer.lua:41-49`); Soulstone
Bg/Max-colour/Height, Healthstone Unknown, Summon SummoningColor, SelfMsg colours,
Sound Fade/Break paths+counts, General Alpha/Tips/label set.

Drifts: **General.AltTimeFormat** false vs original TimeFormat **true**
(`Forte_Core.lua:2493`); **General.FrameSnap** false vs true (`:2483`);
**General.GlobalLock** true vs false (`:2508`, ship-lock law — keep);
**Timer.Max** 32-on vs 15-off (`Forte_Timer.lua:3320`); **Timer.ColourExpired**
white-on vs grey-off (`:3371`); **RaidMsg announce** off vs party-on (`:2524-2526`,
E2 ruling — keep).

## Open questions

1. Max rows: align SpellTimer `Max` to the original's 15-gate-off, or keep the wider
   cap as a recorded design law?
2. Does the Timeline draw the Healthstone/Soulstone/ResTimer/Enchant categories at all?
   (Decides whether the 4 extra colour rows go on the Cooldown Coloring section.)
3. Shard Manager/Shard Spy: the full 2012 tree exists in the complete addon outside
   `/tmp/fxref/` — a re-scout needs a fuller snapshot before any parity claim.
4. The panel PNG (grid labels for cells 2/6/9, original title-bar text) — vision pass
   failed today; re-check when a vision lane is up.

## Prioritized fix list

1. **Sound page: Soulstone Fade + Ready rows** — the only unlabelled verbatim-row gap
   (`Forte_Soulstone.lua:640-641`, defaults `:677-678`).
2. **Label fidelity pass**: "Hide when out of combat", "Time scale max (sec)",
   "Use power of", "Show icon Glow" (Cooldown+Splash), "Expand up", "Show unit #",
   "Show name tags/headers", "Enable Secondary Splash icon", "Splash icon active scale"
   (all file:lines in the tables).
3. **Default flips**: General.AltTimeFormat→true (`Forte_Core.lua:2493`); decide
   Timer Max + ColourExpired defaults.
4. **Cooldown feature rows**: Alpha/AlphaMax pair, IconTime(+IconTextColor), the four
   range filters, per-bar Splash+SplashFactor (all Phase-2-planned; original lines
   `Forte_Cooldown.lua:1717-1732`, `:1722-1724`).
5. **Timer rows**: Blink + FadeTime, TicksNext, Outwands + Flip, Unit label height
   (`Forte_Timer.lua:3148-3149,3182,3193-3195,3243`).
6. **RaidMsg pet/warlock rows**: Seduce trio, SpellLock trio, DevourMagic trio,
   Soulstone Start/Cancel + whispers, DK pair (`Warlock.lua:294-327`,
   `DeathKnight.lua:247,264`) — behind the E2 opt-in law, keys from the live data.
7. **Warlock page rows**: Healthstone 4 spy-bar colours + Details/Auto/Space/Interval;
   Soulstone Expand + Ready-look gate; Summon Details/Expand (`Forte_Healthstone.lua:287-300,318`,
   `Forte_Soulstone.lua:604,619`, `Forte_Summon.lua:545-546`).
8. **Advanced page v1** (feasible subset: startup text, AnimateScroll, ExpandSubcats pair,
   Core intervals, per-module strata via `SetFrameStrata`, FrameSnap + distances,
   RightClickOptions onto General).
9. Cosmetic backlog: Bar Font/Texture pickers, Cooldown IconSize/TextColor,
   Timer TimeRight/HighlightColor, Global RightClickIconOptions (needs the filter
   editor), Blood Pact row after the launch probes.
