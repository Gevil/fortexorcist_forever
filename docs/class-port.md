# H4s — Class port survey (Druid, Mage, Paladin, Priest, Rogue, Shaman, Warrior)

Slice **H4s** of `PLAN.md` §11.1. Read-only survey of the original 2012 class modules
(`/tmp/fxref/Forte_Class/<Class>/<Class>.lua` + `Localization.lua`) against the WoW Forever
12.x engine (interface 16001, client 1.60.1) and the current ForteXorcist tree.

Everything below is **verified on disk** with a `file:line`; the two places where a claim is a
reasoned reading are marked `[INFERENCE]`.

## 0. Answer first

The seven modules are **registrations, not code**. Each dir holds exactly two files
(`<Class>.lua`, `Localization.lua` — `ls /tmp/fxref/Forte_Class/<Class>`); there is **no custom
frame, no custom widget and no custom renderer** in any of the seven. The only executable
machinery outside the registration chain is the Shaman's four-slot totem tracker
(`Shaman.lua:72-101`) and the Priest's Rapture combat-log hook (`Priest.lua:95-100`).

Every spell registration lands in one of three buckets:

| bucket | count (all seven; 339 registration rows in total) | what it means |
|---|---|---|
| **already done** | 117 of 339 rows | the spell is in `tools/spell_lists/<class>.json`, has a generated `Data/<Class>.lua` row, and the shared `Forte_Cooldown` / `Forte_Timer` / `Forte_Messages` engine already draws it |
| **port = add the name to the spell list** | 67 rows = **64 unique spell names** | the spell exists in `spells.jsonl`; `tools/gen_spell_data.py` + the shared engines do the rest. No new Lua |
| **not feasible on Forever** | 144 rows | the 2012 MoP spell simply **has no Forever spell row** (see §2 A1), plus the 2012 glyph / tier-set / PvP-length / combat-log mechanisms |
| commented out in the reference | 11 rows | dead in the original source; nothing to port |

Per-class verdict and size (`add-to-list` counts registration rows; the
parenthesised count is the number of unique spell names — the Mage's 21 add-rows list three
spells twice, once as an `AddSpell` and once as an `AddDebuff` row):

| class | registrations | already done | add-to-list | no Forever spell / mechanism | the one real item | size |
|---|---|---|---|---|---|---|
| **Druid** | 70 | 24 | 12 (12 names) | 33 | `SetCustomName` form labels (`Druid.lua:22-33`) | **medium** |
| **Mage** | 51 | 14 | 21 (18 names) | 16 | Polymorph fade/break — **already in** `RaidMsg.lua:107` | **small** |
| **Paladin** | 58 | 10 | 12 (12 names) | 34 | the 8 raid DR-warning announce rows (`Paladin.lua:134-143`), one spec-gated | **medium** |
| **Priest** | 48 | 13 | 10 (10 names) | 18 (+7 commented) | Rapture = combat log → **not feasible** | **small** |
| **Rogue** | 43 | 17 | 5 (5 names) | 21 | Sap fade/break **already in** (`RaidMsg.lua:111`); poisons → `Enchants.lua` | **small** |
| **Shaman** | 28 | 13 | 4 (4 names) | 11 | the totem slot tracker + 4 element groups/filters/colours (`Shaman.lua:72-113`) | **medium** |
| **Warrior** | 41 | 26 | 3 (3 names) | 12 | the 6 raid DR-warning announce rows (`Warrior.lua:88-102`) | **small** |

Suggested split: **3 workers** (§7).

---

## 1. What the current build already provides (the target of every row)

| seam | file:line | what it covers |
|---|---|---|
| spell-list → data pipeline | `tools/spell_lists/<class>.json` → `tools/gen_spell_data.py` → `addon/Forte_<Class>/Data/<Class>.lua` | every cooldown, GCD, cast time, duration and icon; generated rows per class: Druid 52, Mage 52, Paladin 56, Priest 47, Rogue 50, Shaman 61, Warrior 64 |
| cooldown engine | `addon/Forte_Cooldown/Core/Engine.lua:132` (`Build`), `:185` (`OnCast`), `:210/:264/:325/:364/:414` (the read ladder) | every `ST:AddCooldown` / `AddSpell`-with-cooldown row, charges, the GCD band (`MIN_COOLDOWN = 2.99`, `Engine.lua:98-100`, `isOnGCD` law `:364-388`) |
| item + enchant windows | `Forte_Cooldown/Core/Items.lua:1-32`, `Core/Enchants.lua:1-42` (+ `Module.lua:475-482` `WEAPON_ENCHANT_CHANGED`) | the original's `CD:AddCooldownPowerup` / `AddMeleePowerupCooldowns` / `AddCasterPowerupCooldowns` (item windows) and the Rogue's poison applications (weapon-slot enchant windows) |
| timer registry | `Forte_Timer/Core/Registry.lua:305-368` (`Build`, the `durationMs > 0` gate `:339`), the `KIND_RULES` bands `:78-268` | every `ST:AddSpell/AddBuff/AddDebuff/AddChannel` row; the colour bands. Measured band census of the generated rows (the `Registry._kindFor` decision): Druid 33 rows / 6 bands, Mage 37 / 6, Paladin 33 / 7, Priest 37 / 7, Rogue 39 / 4, Shaman 42 / 4, Warrior 46 / 5 — **zero `Default` rows**, i.e. the colour law is already fed for all nine classes |
| cast spine | `Forte_Timer/Core/Casts.lua` (`UNIT_SPELLCAST_SENT/SUCCEEDED`, the settle deferral), `Core/Rows.lua:240-290` (`InsertFromCast`) | the in-combat prediction every registration depends on |
| fade / break / expiry | `Forte_Messages/Module.lua:294` (`RefreshFadeWarnings`), `:316` (`OnTimerFading`), `:334` (`OnTimerBroken`), `:246` (`OnTimerExpired`); rows table `Forte_Messages/Pages/RaidMsg.lua:79-115` (`P.FADE_ROWS`, keys `:116-119`) | `ST:RegisterOnTimerFade` / `RegisterOnTimerBreak`: Fear, Banish, Subjugate Demon, Seduction, **Polymorph**, **Sap** are already rows of the extensible table |
| announces | `Forte_Messages/Core/Announce.lua:122` (`Group`), `:150` (`Channel`); the cast-triggered precedent `Forte_Messages/Module.lua:385-410` (`OnCastForSoulstone`, a SENT→SUCCEEDED pair with the plain target stamp) | the `CA:CastShow` raid-warning rows (`CA` = `Forte_Casting.lua:702-712`) — the machinery exists; **there is no per-spell cast-announce table yet** (the pages carry Ready / Expiry / Soulstone / fade-break rows only: `Pages/SelfMsg.lua:33-69`, `Pages/RaidMsg.lua:231-310`) |
| sounds | `Forte_Messages/Pages/Sound.lua:27-48` (fade / break / expire / cooldown-ready triples) | the original's `TimerFadeSound` / `TimerBreakSound` / `TimerResistSound` / `Clearcasting` defaults |
| class-module precedents | `Forte_Hunter/Core/Tools.lua:1-70` (cast-predict + out-of-combat aura reconcile), `Forte_Warlock/Core/Tools.lua`, `Forte_Hunter/Pages/Hunter.lua`, `Forte_Warlock/Pages/Warlock.lua` | what a real class module looks like on this engine (derived lists, `PlainOrNil` on every read, a class Options page) |

## 2. The legality frame (applied to every row below)

**A1 — the 2012 spell-id space does not exist on Forever (the dominant blocker).**
`mythicsim-forever-engine/data/spells.jsonl` (7,503 rows) carries ids only in the bands
0–29,999 (4,513 rows), 300k, 400k, 1.2M and 1.3M; **zero rows in 100,000–119,999**. Probed
absent: `113746`, `115804`, `115768`, `114030`, `102351`, `108210-108215`, `113953`, `114039`,
`114153`, `114163`, `114250`, `114637`, `114954`, `115610`, `105068`, `105593`, `105785`,
`105809`, `102051`, `102342`, `102351`, `102543-102560`, `102795`, `106830/106839/106922/106996`,
`108210-108215`, `112048`, `112965`, `113092`, `113724`, `118038`, `121411`, `86346`, `86273`,
`86659`, `64382`, `64843`, `59889`, `77487`, `81662`, `81700`, `87153`, `47755`, `47788`, `47515`,
`77613`, `70772`, `77485`, `88625`, `88684`, `88686`, `48517`, `48518`, `102342`, `102543`,
`102547`, `102558`, `102560`, `102795`, `90164`, `90166`, `69369`, `77495`, `77761`, `5217`.
The generator's family law is what makes this safe: rank resolution is
**family-scoped with an uncoded-family fallback**, and a foreign-family row is never taken
(`tools/gen_spell_data.py:11-30`) — so a 2012 name that only survives as another class's row
surfaces as an explicit gap line, not a silent wrong row. Measured on the §6 add-list:
`Mana Surge` resolves only to family 11 (Shaman) and `Grand Crusader` only to family 7
(Druid) → those two are generator gaps; the other 62 names resolve in-family
(including the uncoded-fallback rows `Pounce Bleed`, `Thrash`, `Dash`, `Savage Defense`,
`Freeze`, `Reckoning`, `Vindication`, `Ancient Power`, `Dismantle`, `Deep Wounds`, `Enrage`,
`Vigilance` — all present as `Family = None` rows).

Consequence: the port **never copies a 2012 id**; the unit of porting is the spell **name**,
which is exactly the law `tools/gen_spell_data.py` and `Registry.lua:5-9` already run.
Renaming is expected: the reference's `Weakened Armor` / `Mortal Wounds` are Forever's
`Sunder Armor` (7386, 30 s) and `Mortal Strike` (12294, 10 s), `Disorienting Roar` is
`Demoralizing Roar` (99), `Hand of Salvation` is `Salvation` (1038, paladin),
`Enslave Demon` is `Subjugate Demon` (`RaidMsg.lua:52-56`), `Mangle` is `Lacerate`,
`Berserk` exists as its own name, `Bash` 5211 / `Skull Bash` 410176 carry the bear stun,
`Heroism`/`Bloodlust`/`Time Warp` are Forever's `Rage of the Farseer` (425336, shaman, 25 s /
180 s cd) and `Bloodrage` (warrior).

**A2 — the combat log is closed. Not negotiable.**
`COMBAT_LOG_EVENT_UNFILTERED` is forbidden project law (`AGENTS.md`, `PLAN.md` §2.3;
`docs/design-combat-procs.md:9` "The combat log is closed to addons on this engine … No addon
can parse 'proc fired'"). It kills exactly **one** class feature in this slice: the Priest's
Rapture hidden cooldown (`Priest.lua:95-100`).

**A3 — aura / cooldown reads are secret while restricted; own-cast events are the spine.**
`docs/research/secrets-unknowns.md` §2/§8; `C_Secrets.GetSpellAuraSecrecy` classifies the FX
spell set as ContextuallySecret and no FX spell sits in the 76-row NeverSecret aura set.
Every row in the tables below is therefore legal *as a cast-predicted row* (the
`Forte_Timer/Core/Casts.lua` + `Forte_Cooldown/Module.lua:483-490` path) with the plain-read
reconcile running out of combat (`Forte_Timer/Core/Reconcile.lua`, gated on
`FX.SecretState.aurasSecret`). Every value crosses `FX.Compat.PlainOrNil` first
(`Forte_Hunter/Core/Tools.lua:22-26`). **No row in this survey needs a secret value.**

**A4 — the 2012 glyph / talent / tier-set columns do not exist on this client.**
The pinned catalog (`docs/api/wow-addon-api-agents/skills/*/references/generated/forever.json`)
has `C_Glyph` = **0** symbols, `GetGlyphInfo` absent, `C_EnchantIncants` = 0,
`GetShapeshiftForm` absent, `GetActiveSpecGroup` / bare `GetSpecialization` absent,
while `C_Traits` has 53 symbols and `C_SpecializationInfo.GetSpecialization` +
`C_SpecializationInfo.GetActiveSpecGroup` exist. Every `SetSpellModGlph` / `SetSpellModSetB` /
`RegisterSet` row is therefore dropped — and `Registry.lua:19-27` already records that
decision ("the 2012 glyph/talent/set modifiers (`C_Glyph`: ZERO symbols on this client;
talents are C_Traits)").

**A5 — the shared `SetDefaultHasted` haste model has a seam, not a feed.**
`Forte_Casting.lua:56-84` holds the shared haste-buff table (Heroism/Bloodlust/Time Warp 1.30,
Power Infusion 1.20, Priest `Borrowed Time` 1.15, Druid `Nature's Grace` 1.15, Shaman
`Elemental Mastery` 1.20, Troll Berserking 1.20). The port freezes an out-of-combat factor per
row and the seam is explicitly un-wired: `Forte_Timer/Core/Casts.lua:275-292` — *"the
original's `SetHasted`/`SetDefaultHasted` gate is a per-spell table we do not have"*. So the
per-class `SetDefaultHasted(0|1)` + `SetTickSpeed` + `SetSpellMod*` stack is one **shared**
work item, not seven: `SetDefaultHasted(1)` = Mage `Mage.lua:15`, Paladin `Paladin.lua:19`,
Priest `Priest.lua:24`, Shaman `Shaman.lua:17`; `SetDefaultHasted(0)` = Druid
`Druid.lua:69` (feral block, `1` at `:49`), Rogue `Rogue.lua:16`, Warrior `Warrior.lua:14`;
the one row-level override is `Paladin.lua:28` `SetHasted(0)` (Exorcism).

**A6 — the tick / stack / no-target columns are rendered and gated, never fed.**
`Forte_Timer/UI/Rows.lua:734-757` draws the tick marks from `row.tickEvery` and
`Core/Rows.lua:119` declares the field, but **no code assigns it** (a whole-tree search for
`tickEvery =` matches the declaration only) and `Registry:Build` writes only
`name/dataId/duration/kind/noTarget` (`Registry.lua:336-346`) — with
`noTarget = false` hard-set (`:345`) and `Registry.IsNoTarget` reading it (`:319-322`).
Measured: **no generated class row carries `tickEvery`/`maxStack`/`noTarget`, and no class has
a `kind = "channel"` row** (all nine classes report `chan=0`, `tick=0` in the generated data).
Every `SetTickSpeed` / `SetStacks` / `F.NOTARGET` / `F.UNIQUE` / `AddChannel` row in the
seven tables below is therefore "data + registry, tick marks off" until that feed lands.

**A7 — the options tree has no per-band filter, so "filter pre-seeds" have no landing.**
The reference pre-seeds per-class filter rows bound to `ST.FilterChange` / `CD.FilterChange`
(Shaman `Shaman.lua:105-108` `TotemFire/Earth/Water/Air`, Warlock `Warlock.lua:342-343`
Curse/Bane, DeathKnight `DeathKnight.lua:208-210` runes) plus per-group colour defaults
(`Shaman.lua:110-113` `FW.InstanceDefault.Timer.TotemFire = {[0]=true,1.00,0.37,0.00}` …).
`addon/Forte_Timer/Pages/Timer.lua:42-96` has layout/colour keys only (its `BarColor*` five
are documented "Not wired yet (stored)", `:181-195`) — **no band/group visibility rows**. So
the Shaman's four filter rows are a feature request against the Timer page, not a data edit.

**A8 — per-proc audio/visual windows (`CD:AddHiddenCooldown`) need the unbuilt gate path.**
`Forte_Cooldown.lua:149-152`: `AddHiddenCooldown(item, buff, seconds)` stores
`hiddencooldown[buffName] = seconds` — i.e. *"when this buff appears, start a fake cooldown of
N seconds"*. The appearance of a proc buff is exactly the signal the closed log removes;
`docs/design-combat-procs.md` §3.3/§4 (P-C/P-D gate containers + `C_UnitAuras.AddAuraSound`)
is **design, not built** ("Status: design, not built", `:3`). `Forte_Cooldown` has no
hidden-cooldown concept (its tracked set is built from data `cooldownMs`,
`Engine:Build:132-155`). Rows affected: Eclipse (`Druid.lua:166-167`), Cauterize
(`Mage.lua:103`), Rapture (`Priest.lua:97`), Taste for Blood (`Warrior.lua:74`, commented),
Nature's Grace (`Druid.lua:169`, commented).

**A9 — PvP-length rows have no data basis.** `spells.jsonl` has no PvP duration column
(spell-level: `DurationMs`, `AreaDurationMultiplier`; effect-level: `PvpMult` = a damage
multiplier). The reference's `SetDurationPVP` rows (Druid `:51,:52`; Mage `:18,:35`) have
nothing to fill a table from.

**A10 — legality of the two remaining event families used by these classes.**
* `PLAYER_TOTEM_UPDATE`, `GetTotemInfo`, `GetTotemTimeLeft`, `GetNumTotemSlots`,
  `C_TooltipInfo.GetTotem`, `C_Secrets.ShouldTotemSlotBeSecret`,
  `C_Secrets.ShouldTotemSpellBeSecret`: all **in** the pinned catalog → the Shaman totem
  tracker is feasible, with the two `Should…BeSecret` gates and `PlainOrNil` (`[INFERENCE]`:
  the payload shape `(index)` is taken from the reference call site `Shaman.lua:77-79`, not
  from a live probe).
* form state: `UPDATE_SHAPESHIFT_FORM` / `_FORMS` / `_USABLE` / `_COOLDOWN` **are** in the
  catalog, and the catalog has **no** form getter (`GetShapeshiftForm`, `GetFormSpellID`,
  `ActiveForm` all absent; the only `Shapeshift` symbols are `C_TooltipInfo.GetShapeshift` and
  `C_ActionBar.HasTempShapeshiftActionBar`). So Druid form state is **event-edge only** —
  exactly the `Forte_Hunter/Core/Tools.lua:39-73` AspectTracker shape (predict on our own
  cast, reconcile out of combat, a secret read never overwrites).

## 3. Shared feature families (one row each; the per-class tables reference them)

| # | 2012 call (the seven's call sites) | behaviour | legality on Forever | current coverage | verdict |
|---|---|---|---|---|---|
| S1 | `ST:SetDefaultHasted(0\|1)` — `Druid.lua:49,69`, `Mage.lua:15`, `Paladin.lua:19`, `Priest.lua:24`, `Rogue.lua:16`, `Shaman.lua:17`, `Warrior.lua:14` | the following rows' drawn length scales with haste | feasible (the frozen out-of-combat factor already exists) | `Casts.lua:275-292` seam, defaults to 1, **no gate table** | **port-adapted once, shared (A5)**: a `{[name]=hasted}` table fed from the data, read at `HasteFactor` |
| S2 | `SetHasted(0)` — `Paladin.lua:28` | one-spell override | as S1 | none | **port-adapted (S1 row)** |
| S3 | `ST:AddChannel(id, durSec, tickSec)` — `Druid.lua:43-46`, `Mage.lua:16`, `Priest.lua:26,63,64`, `Shaman.lua:19` | a channelling window with a tick period | feasible: the cast spine knows the channel; the duration is data | `Registry` `Channel` band exists (`Registry.lua:146-153`) and the renderer draws ticks, **no generated row is a channel and none has a tick** (A6) | **port-adapted**: a generator `kind`/`tickEvery` field; then free |
| S4 | `SetTickSpeed(sec[, spellId])` — Druid `:56-66,79-91`, Mage `:20-24,39,51`, Paladin `:23,28,63`, Priest `:36,38,48,75`, Rogue `:32,35,58`, Shaman `:35,37,43`, Warrior `:50` | tick marks inside the bar (display) | feasible (display-only; the log is not needed) | renderer `UI/Rows.lua:734-757`; row field `Core/Rows.lua:119`; **never assigned** | **port-adapted (shared, A6)** |
| S5 | `SetStacks(n)` — Druid `:62,83,122`, Priest `:45`, Paladin `:62,87`, Warrior `:18`, Rogue `—` | the icon stack badge | feasible: the data has `MaxStack` | page switches `Timer.lua:66-69` (`IconStacks`, `ShowStacks`); `Registry` does not read `MaxStack` (A6) | **port-adapted (shared, A6)** |
| S6 | `F.NOTARGET` / `F.UNIQUE` / `F.SHARED` flags — all seven | self-row keying, shared-debuff eviction | feasible (a row-key law, not a read) | `Registry.IsNoTarget` + the `noTarget` field exist, hard-set to `false` (`Registry.lua:319-322,345`); the `group`/`isShared`/`isUnique` columns are documented as not in the data (`Registry.lua:22-27`) | **port-adapted (shared, A6)** |
| S7 | `SetDurationPVP(sec)` — Druid `:51,52`, Mage `:18,35` | the PvP length | feasible in principle | **no data source** (A9) | **not feasible (no data)**; owner decision |
| S8 | `SetSpellModGlph` / `SetSpellModSetB` + `FW:RegisterSet` — Paladin `:22,23`, Priest `:28,29,31`, Shaman `:22,23`, Druid `:35,36,57,63` | glyph / tier-set length+tick modifiers | **not portable** (A4) | deliberately dropped, `Registry.lua:19-27` | **not feasible** |
| S9 | `AddCasterBuffs()` / `AddMeleeBuffs()` — Druid `:174-175`, Mage `:83`, Paladin `:102-103`, Priest `:88`, Rogue `:71`, Shaman `:69-70`, Warrior `:70` | the shared raid-buff / trinket-proc aura list (`Forte_Timer.lua` shared module; its class keys: Priest `Borrowed Time`, Druid `Nature's Grace`, Shaman `Elemental Mastery`) | own-cast half feasible; **someone else's** raid buff is unseeable (no cast event for another player, aura secret) → only the `AddAuraSound` / gate-container path (A8) | own casts are covered by the class data rows; `Forte_Items` covers the item-proc windows for the Cooldown bar | **port-adapted**: the shared list is a data input to `Registry:Build`; the raid-wide half = A8 gate work |
| S10 | `CD:AddCasterPowerupCooldowns()` / `AddMeleePowerupCooldowns()` — Druid `:172-173`, Mage `:104`, Paladin `:119-120`, Priest `:103`, Rogue `:91`, Shaman `:117-118`, Warrior `:75` | ~30 hard-coded trinket→proc pairs (`Forte_Cooldown.lua:1581-1660`) | feasible: an on-use item's cast event is a cast | `Forte_Cooldown/Core/Items.lua:1-32` + `Forte_Items/Data/Items.lua` (generated, name-matched) | **already done, generically** — the 2012 trinket list itself is void (those items are not on this client) |
| S11 | `CD:AddHiddenCooldown(item, buff, sec)` — Druid `:166,167,(169)`, Mage `:103`, Priest `:97`, Warrior `:74` | start a fake N-second bar when a **proc buff appears** | proc signal unobtainable in combat (A2/A8) | no hidden-cooldown concept in `Forte_Cooldown` | **not feasible** until `design-combat-procs.md` P-C/P-D ships |
| S12 | `CD:AddCooldownBuff(spellId)` — Druid `:163,164`, Paladin `:107,110-117`, Rogue `:84-89`, Warrior `:73` | "the appearance of this buff is a bar" (`Forte_Cooldown.lua:167-169`) | feasible for our own casts; the poisons ride `C_Item.GetWeaponEnchantInfo` | self-buff windows: `Forte_Timer` data rows; poisons: `Forte_Cooldown/Core/Enchants.lua:1-42` + `WEAPON_ENCHANT_CHANGED` | **already done** (as a Timer row / an Enchant window) |
| S13 | `CD:AddCooldownPowerup` — none of the seven directly (inside S10) | item → proc pair | feasible | `Items.lua` | **already done** |
| S14 | `ST:AddSpellRemap(oldId, newId)` — Warrior `:17` (Sunder Armor→Weakened Armor), `:24` (Mortal Strike→Mortal Wounds), Druid `:40` (commented) | display the modern form of a spell | n/a on Forever: the registry is **name-keyed** (`Registry.lua:5-9`) | the Forever name (`Sunder Armor`, `Mortal Strike`) is already the key | **already done by construction** — no remap layer to port |
| S15 | `ST:AddExtraSpell(id)` — Druid `:76` (Pounce→bleed), Warrior `:25` (Mortal Strike→Deep Wounds) | one cast lights a second row | feasible (a cast is the trigger) | the cast spine is single-name (`Casts.lua`); no extra-spell map | **port-adapted**: a `{[castName]=extraName}` table the class module feeds at the cast hook |
| S16 | `FW:SetCustomName(id, name)` + the `Localization.lua` suffixed labels — Druid `:22-33` + `Localization.lua:80-88` (`_BEAR/_CAT/_FERAL` `:73-78`) | rename a spell id (the form-paired pairs) | label-only | the one name-rewrite seam is the locale alias path (`Registry.lua:357-368`, `Forte_Core/Core/Locale.lua`), which maps the **client's** localized names, not invented labels; the form-paired 2012 ids do not exist (A1) | **not feasible as written; port-adapted** as a label layer (a `labelFor` seam over the row name) |
| S17 | `CA:RegisterOnSelfCastSuccess(fn)` + `CA:CastShow(key, target)` — Druid `:190-205` (6 rows), Paladin `:134-143` (8), Warrior `:88-102` (6), `Forte_Casting.lua:622-632,702-712` | "X casts Y on Z" to party/raid/whisper at the cast | feasible — the Soulstone hook is this shape already (`Forte_Messages/Module.lua:385-410`) | `Announce:Group/Channel` + the per-row text/opt-in triple; **no per-spell cast-announce table exists** (`Pages/SelfMsg.lua:33-69`, `Pages/RaidMsg.lua:231-310`) | **port-adapted**: one `P.CAST_ROWS` table mirroring `P.FADE_ROWS` (`RaidMsg.lua:79-115`) + the cast hook; per-class rows = data |
| S18 | `ST:RegisterOnTimerFade(spell,key)` / `RegisterOnTimerBreak(fn)` — Mage `:86-92`, Rogue `:74-80` | the CC fade + early-break announces | feasible | **done**: `P.FADE_ROWS` + `OnTimerFading`/`OnTimerBroken` | **already done**; the Polymorph and Sap rows ship (`RaidMsg.lua:107-114`) |
| S19 | `ST:RegisterOnBuffGain(fn)` → `FW:PlaySound("TimerClearcastingSound")` — Druid `:144-149` (commented), Mage `:95-100` (commented) | a proc-triggered sound | combat-side = A8; out-of-combat readable | `Core/Sounds.lua` + the four Sound rows (`Pages/Sound.lua:27-48`); no per-proc row | **not feasible** in combat (A8); the Clearcasting rows are commented in the reference too |
| S20 | `FW:RegisterToEvent(name, fn)` — Shaman `:95` `PLAYER_TOTEM_UPDATE`, Priest `:100` `COMBAT_LOG_EVENT_UNFILTERED` | a raw event handler | event must be in the pinned catalog (`scripts/api_lint.py:17,21-31`); the log is banned (A2) | `PLAYER_TOTEM_UPDATE` is in the catalog | **feasible for totems; not feasible for Rapture** |
| S21 | `FW:RegisterDelayedLoadEvent(fn)` — Shaman `:97-101` | a one-shot post-login pass (seed the live totems) | feasible | the login/entering-world handler pattern (`Forte_Cooldown/Module.lua:455-478`) | **already done pattern** |
| S22 | `FW:SetMainCategory`/`SetSubCategory`/`AddOption("MS2"\|"SND"\|"CO2"\|"INF", …):SetFunc(…FilterChange)` — every module's tail block | the per-class options tree + the **filter pre-seeds** + the per-group colour defaults | UI-only | `Forte_Options` pages exist; **no per-band filter rows** in `Forte_Timer/Pages/Timer.lua:42-96`; the five `BarColor*` are "Not wired yet (stored)" (`:181-195`) | **port-adapted** (message rows = S17 table; **filter pre-seeds = a Timer-page feature**, A7) |
| S23 | `CA:SetGCDStance(stance, gcd)` / `FW:RegisterSpecialCastTime(...)` | per-stance GCD (DeathKnight `:14` only) / a cast-time override (Hunter `:113` only) | — | the GCD band is modelled (`Engine.lua:98-100,364-388`) | **n/a for these seven** — neither call appears in Druid/Mage/Paladin/Priest/Rogue/Shaman/Warrior |
| S24 | custom frames / custom tracking | — | — | the seven dirs contain `<Class>.lua` + `Localization.lua` only | **none exists in the seven** |

## 4. Per-class registration tables

How to read them: **registration** = the 2012 call, the spell label as the reference's own
trailing comment, its `ST.F` flags and its chained modifiers. **Forever** = the
`spells.jsonl` join on that **name**: `ids · dur · cd · row count`, or `absent`.
**current coverage** = `list` (in `tools/spell_lists/<class>.json`) · `data` (a generated
`Data/<Class>.lua` row with a duration, or with a cooldown). Legality is §2's frame applied:
every row that exists on Forever is legal as a cast-predicted row (A3); the columns
`SetStacks`/`SetTickSpeed`/`F.NOTARGET`/`F.UNIQUE`/`AddChannel` additionally need the shared
feed of A6, `SetSpellMod*`/`RegisterSet` is A4, `SetDurationPVP` is A9.
`list – · data –` on a row that exists on Forever means the **port is a spell-list entry**, not code.

How they were produced (reproducible): every `ST:Add*` / `CD:Add*` / `CA:CastShow` call line of
the module was read out with its trailing label comment; the label was looked up as a
lower-cased **name** in `spells.jsonl` (the engine's name-keyed law, A1) reporting the id band,
the duration/cooldown set and the row count; the same label was then checked against
`tools/spell_lists/<class>.json` (list ✓) and the generated `Data/<Class>.lua`
(data dur ✓ / data cd ✓). Verdict = the join plus §2's frame.


### 4.1 Druid

Registration chain: `/tmp/fxref/Forte_Class/Druid/Druid.lua` (`SetDefaultHasted` + the fluent `:AddSpell`/`:AddBuff`/`:AddDebuff`/`:AddChannel`/`:AddCooldown` block) and the `CD:` block. The port's landing is
`addon/Forte_Druid/Data/Druid.lua` generated from `tools/spell_lists/druid.json`.

| ref | registration | Forever `spells.jsonl` | current coverage | verdict |
|---|---|---|---|---|
| `Druid.lua:40` | `AddSpellRemap` **Faerie Fire (Feral) → Faerie Fire** | absent | list – · data – | n/a — commented out in the reference |
| `Druid.lua:43` | `AddChannel` **Hurricane**  | [16914, 17401, 17402, 1278759] · dur [10000] · cd [] · 7 rows | list ✓ · data dur ✓ | already done (data row) + channel row (ticks unwired) |
| `Druid.lua:44` | `AddChannel` **Astral Communion**  | absent | list – · data – | not feasible (no Forever spell) + channel row (ticks unwired) |
| `Druid.lua:45` | `AddChannel` **Astral Storm**  | absent | list – · data – | not feasible (no Forever spell) + channel row (ticks unwired) |
| `Druid.lua:46` | `AddChannel` **Astral Storm**  | absent | list – · data – | not feasible (no Forever spell) + channel row (ticks unwired) |
| `Druid.lua:50` | `AddSpell` **Cyclone** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:51` | `AddSpell` **Entangling Roots** `UNIQUE` `SetDurationPVP(12)` | [339, 1062, 5195, 5196] · dur [12000, 15000] · cd [] · 12 rows | list ✓ · data dur ✓ | already done (data row) + PvP length deferred |
| `Druid.lua:52` | `AddSpell` **Hibernate** `UNIQUE` `SetDurationPVP(12)` | [2637, 18657, 18658] · dur [20000, 30000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) + PvP length deferred |
| `Druid.lua:53` | `AddSpell` **Faerie Fire**  | [770, 778, 9749, 9907] · dur [30000, 40000] · cd [] · 5 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:54` | `AddSpell` **Faerie Swarm**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:55` | `AddSpell` **Force of Nature** `SUMMON` | [467079] · dur [15000] · cd [] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:56` | `AddSpell` **Insect Swarm** `TICKS` `SetTickSpeed(2)` | [5570, 24974, 24975, 24976] · dur [12000] · cd [] · 5 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Druid.lua:57` | `AddSpell` **Moonfire** `TICKS` `SetTickSpeed(2);SetSpellModSetB("Thunderheart Regalia",2,3)` | [8921, 8924, 8925, 8926] · dur [9000, 12000] · cd [] · 10 rows | list ✓ · data dur ✓ | already done (data row) + glyph/talent mod dropped + tick feed unwired |
| `Druid.lua:58` | `AddSpell` **Sunfire** `TICKS` `SetTickSpeed(2)` | [414684] · dur [12000] · cd [] · 1 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Druid.lua:61` | `AddSpell` **Innervate** `BUFF` | [29166] · dur [20000] · cd [360000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:62` | `AddSpell` **Lifebloom** `HOT` `SetTickSpeed(1);SetStacks(3)` | [408124, 408245, 409824] · dur [7000] · cd [] · 3 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Druid.lua:63` | `AddSpell` **Regrowth** `HOT` `SetTickSpeed(2);SetSpellModSetB("Nordrassil Raiment",2,6)` | [8936, 8938, 8939, 8940] · dur [21000] · cd [] · 10 rows | list ✓ · data dur ✓ | already done (data row) + glyph/talent mod dropped + tick feed unwired |
| `Druid.lua:64` | `AddSpell` **Rejuvenation** `HOT` | [774, 1058, 1430, 2090] · dur [12000] · cd [] · 15 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Druid.lua:65` | `AddSpell` **Living Seed** `BUFF` | [414677, 414680] · dur [15000] · cd [] · 2 rows | list – · data – | port (add to spell list) |
| `Druid.lua:66` | `AddSpell` **Wild Growth** `HOT` `SetTickSpeed(1)` | [408120, 409810, 1238214, 1238215] · dur [7000] · cd [6000] · 4 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Druid.lua:70` | `AddSpell` **Mighty Bash** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:71` | `AddSpell` **Skull Bash** `UNIQUE` | [410176, 414621] · dur [2000] · cd [10000] · 2 rows | list – · data – | port (add to spell list) |
| `Druid.lua:72` | `AddSpell` **Disorienting Roar** `AOE` | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:73` | `AddSpell` **Growl** `UNIQUE` | [1853, 6795, 14922, 14923] · dur [3000] · cd [8000] · 8 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:74` | `AddSpell` **Mangle Bear**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:75` | `AddSpell` **Mangle Cat**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:76` | `AddSpell` **Pounce** `AddExtraSpell(9007)` | [9005, 9823, 9827] · dur [2000] · cd [] · 3 rows | list – · data – | port (add to spell list) |
| `Druid.lua:77` | `AddSpell` **Pounce Bleed** `TICKS` | [9007, 9824, 9826] · dur [18000] · cd [] · 3 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Druid.lua:79` | `AddSpell` **Rake** `TICKS` | [1822, 1823, 1824, 9904] · dur [9000] · cd [] · 4 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Druid.lua:80` | `AddSpell` **Rip** `TICKS` `SetTickSpeed(2)` | [1079, 9492, 9493, 9752] · dur [12000] · cd [] · 6 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Druid.lua:81` | `AddSpell` **Maim** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:82` | `AddSpell` **Infected Wounds (Movement speed slowed by 50%.)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:83` | `AddSpell` **Lacerate** `TICKS` `SetStacks(3)` | [414644, 1235826, 1235827] · dur [15000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Druid.lua:85` | `AddSpell` **Thrash** `TICKS` | [21919] · dur [] · cd [] · 1 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Druid.lua:87` | `AddSpell` **Solar Beam** `AOE` | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:89` | `AddSpell` **Cenarion Ward** `BUFF` | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:91` | `AddSpell` **Bear Hug** `TICKS` `SetTickSpeed(1)` | absent | list – · data – | not feasible (no Forever spell) + tick feed unwired |
| `Druid.lua:95` | `AddBuff` **eclipse (solar)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:96` | `AddBuff` **eclipse (lunar)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:97` | `AddBuff` **savage roar**  | [407988] · dur [9000] · cd [] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:98` | `AddBuff` **Nature's Swiftness**  | [17116] · dur [] · cd [180000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:99` | `AddBuff` **Ironbark**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:101` | `AddBuff` **Incarnation: Son of Ursoc**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:102` | `AddBuff` **Incarnation: King of the Jungle**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:103` | `AddBuff` **Incarnation: Chosen of Elune**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:106` | `AddBuff` **Barkskin**  | [22812, 428713] · dur [15000] · cd [60000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:107` | `AddBuff` **Nature's Grasp**  | [16689, 16810, 16811, 16812] · dur [45000] · cd [60000] · 6 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:108` | `AddBuff` **Nature's Grace**  | [16880, 16886] · dur [3000] · cd [] · 2 rows | list – · data – | port (add to spell list) |
| `Druid.lua:109` | `AddBuff` **Starfall**  | [439748, 439753, 439755, 439756] · dur [10000] · cd [90000] · 5 rows | list – · data – | port (add to spell list) |
| `Druid.lua:110` | `AddBuff` **Harmony**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:113` | `AddBuff` **Dash**  | [1850, 9821, 23099, 23100] · dur [15000] · cd [30000, 300000] · 8 rows | list – · data – | port (add to spell list) |
| `Druid.lua:114` | `AddBuff` **Enrage**  | [5229, 12317, 12686, 425415] · dur [10000, 12000] · cd [60000] · 5 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:115` | `AddBuff` **Frenzied Regeneration**  | [22842, 22845, 428708] · dur [10000] · cd [180000] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:116` | `AddBuff` **Tiger's Fury**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:117` | `AddBuff` **Nurture 2 piece Feral T5**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:118` | `AddBuff` **Berserk**  | [417141, 424759] · dur [15000] · cd [180000] · 2 rows | list – · data – | port (add to spell list) |
| `Druid.lua:119` | `AddBuff` **Survival Instincts**  | [408024, 408025, 409809] · dur [20000] · cd [180000] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:120` | `AddBuff` **Might of Ursoc**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:121` | `AddBuff` **Stampeding Roar**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:122` | `AddBuff` **Prowl** `SetStacks(0)` | [5215, 6783, 9913, 24450] · dur [] · cd [10000] · 9 rows | list ✓ · data dur ✓ | already done (data row) |
| `Druid.lua:123` | `AddBuff` **Savage Defense**  | [410144] · dur [10000] · cd [] · 1 rows | list – · data – | port (add to spell list) |
| `Druid.lua:126` | `AddBuff` **Clearcasting**  | [16870] · dur [15000] · cd [] · 1 rows | list – · data – | port (add to spell list) |
| `Druid.lua:129` | `AddBuff` **Primal Instinct, Idol of Terror**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:131` | `AddBuff` **Predator's Swiftness** `SetStacks(0)` | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:132` | `AddBuff` **Astral Alignment Balance 4P T11 bonus**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:133` | `AddBuff` **Strength of the Panther Feral 4P T11 bonus**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:135` | `AddCooldown` **id 5217 (no name comment)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:137` | `AddDebuff` **Disorienting Roar**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:138` | `AddDebuff` **Solar Beam**  | absent | list – · data – | not feasible (no Forever spell) |
| `Druid.lua:139` | `AddDebuff` **Astral Storm**  | absent | list – · data – | not feasible (no Forever spell) |

**Druid tally:** 33 × `not feasible (no Forever spell)`, 24 × `already done (data row)`, 12 × `port (add to spell list)`, 1 × `n/a — commented out in the reference`.


### 4.2 Mage

Registration chain: `/tmp/fxref/Forte_Class/Mage/Mage.lua` (`SetDefaultHasted` + the fluent `:AddSpell`/`:AddBuff`/`:AddDebuff`/`:AddChannel`/`:AddCooldown` block) and the `CD:` block. The port's landing is
`addon/Forte_Mage/Data/Mage.lua` generated from `tools/spell_lists/mage.json`.

| ref | registration | Forever `spells.jsonl` | current coverage | verdict |
|---|---|---|---|---|
| `Mage.lua:16` | `AddChannel` **Blizzard**  | [10, 6141, 8427, 10185] · dur [8000] · cd [] · 12 rows | list – · data – | port (add to spell list) + channel row (ticks unwired) |
| `Mage.lua:18` | `AddSpell` **Polymorph** `UNIQUE` `SetDurationPVP(10)` | [118, 12824, 12825, 12826] · dur [20000, 30000] · cd [] · 4 rows | list ✓ · data dur ✓ | already done (data row) + PvP length deferred |
| `Mage.lua:19` | `AddSpell` **Living Bomb** `TICKS` | [400613, 400614, 401731] · dur [12000] · cd [] · 3 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Mage.lua:20` | `AddSpell` **Ignite** `TICKS` `SetTickSpeed(2)` | [11119, 412538] · dur [4000] · cd [] · 2 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Mage.lua:21` | `AddSpell` **Pyroblast** `TICKS` | [11366, 12505, 12522, 12523] · dur [12000] · cd [] · 8 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Mage.lua:22` | `AddSpell` **Flamestrike** `AOE_DMG` `SetTickSpeed(2)` | [2120, 2121, 8422, 8423] · dur [8000] · cd [] · 14 rows | list – · data – | port (add to spell list) |
| `Mage.lua:23` | `AddSpell` **Nether Tempest** `TICKS` `SetTickSpeed(1)` | absent | list – · data – | not feasible (no Forever spell) + tick feed unwired |
| `Mage.lua:24` | `AddSpell` **Combustion** `TICKS` `SetTickSpeed(1)` | [11129, 28682] · dur [] · cd [180000] · 2 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Mage.lua:26` | `AddSpell` **Frost Bomb**  | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:28` | `AddSpell` **Slow** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:29` | `AddSpell` **Counterspell** `UNIQUE` | [2139] · dur [10000] · cd [30000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:30` | `AddSpell` **Cone of Cold** `AOE` | [120, 8492, 10159, 10160] · dur [6000] · cd [10000] · 5 rows | list – · data – | port (add to spell list) |
| `Mage.lua:31` | `AddSpell` **Frost Nova** `AOE` | [122, 865, 6131, 10230] · dur [8000] · cd [25000] · 4 rows | list – · data – | port (add to spell list) |
| `Mage.lua:32` | `AddSpell` **Ring of Frost** `AOE` | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:33` | `AddSpell` **Deep Freeze** `UNIQUE` | [428739, 428917, 428920, 429303] · dur [5000] · cd [30000] · 4 rows | list – · data – | port (add to spell list) |
| `Mage.lua:34` | `AddSpell` **Dragon's Breath** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:35` | `AddSpell` **Frostjaw** `UNIQUE` `SetDurationPVP(4)` | absent | list – · data – | not feasible (no Forever spell) + PvP length deferred |
| `Mage.lua:37` | `AddSpell` **Frostfire Bolt**  | [401502, 401735, 1237312, 1237313] · dur [9000] · cd [] · 4 rows | list – · data – | port (add to spell list) |
| `Mage.lua:38` | `AddSpell` **Mirror Image** `SUMMON` | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:39` | `AddSpell` **Frozen Orb** `SUMMON` `SetTickSpeed(1)` | [440802, 440804, 440809, 440859] · dur [5000, 16000] · cd [60000] · 4 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:41` | `AddBuff` **Pyroblast Clearcasting ??**  | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:42` | `AddBuff` **Mana Surge**  | [23572] · dur [] · cd [] · 1 rows | list – · data – | port (add to spell list) |
| `Mage.lua:44` | `AddBuff` **Arcane Power**  | [12042] · dur [15000] · cd [180000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:45` | `AddBuff` **Mana Shield**  | [1463, 8494, 8495, 10191] · dur [60000] · cd [] · 12 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:46` | `AddBuff` **Icy Veins**  | [425121, 425169] · dur [20000] · cd [180000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:47` | `AddBuff` **Brain Freeze**  | [400731, 401725] · dur [] · cd [] · 2 rows | list – · data – | port (add to spell list) |
| `Mage.lua:48` | `AddBuff` **Pushing the Limit**  | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:50` | `AddBuff` **Invisibility**  | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:51` | `AddBuff` **Evocation** `SetTickSpeed(2)` | [12051, 28763] · dur [8000] · cd [480000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:52` | `AddBuff` **Ice Block**  | [11958] · dur [10000] · cd [300000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:54` | `AddBuff` **Mage Armor**  | [6117, 22782, 22783] · dur [1800000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:55` | `AddBuff` **Molten Armor**  | [428741, 428743, 429307] · dur [1800000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:56` | `AddBuff` **Frost Armor**  | [168, 7300, 7301] · dur [1800000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:58` | `AddBuff` **Fingers of Frost**  | [400647, 400669, 401741] · dur [15000] · cd [] · 3 rows | list – · data – | port (add to spell list) |
| `Mage.lua:59` | `AddBuff` **Ice Barrier**  | [11426, 13031, 13032, 13033] · dur [60000] · cd [30000] · 4 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:60` | `AddBuff` **Arcane Missile Barrage**  | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:62` | `AddBuff` **Stolen Time**  | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:63` | `AddBuff` **Temporal Shield**  | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:64` | `AddBuff` **Ice Floes**  | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:67` | `AddSelfDebuff` **Arcane Blast**  | [18091, 20883, 400573, 400574] · dur [15000] · cd [8000] · 9 rows | list – · data – | port (add to spell list) |
| `Mage.lua:70` | `AddDebuff` **Cone of Cold**  | [120, 8492, 10159, 10160] · dur [6000] · cd [10000] · 5 rows | list – · data – | port (add to spell list) |
| `Mage.lua:71` | `AddDebuff` **frost nova**  | [122, 865, 6131, 10230] · dur [8000] · cd [25000] · 4 rows | list – · data – | port (add to spell list) |
| `Mage.lua:72` | `AddDebuff` **Blast Wave**  | [11113, 13018, 13019, 13020] · dur [6000] · cd [45000] · 5 rows | list – · data – | port (add to spell list) |
| `Mage.lua:73` | `AddDebuff` **Ring of Frost**  | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:74` | `AddDebuff` **Freeze**  | [18798, 18799, 27867, 27868] · dur [3000, 5000] · cd [] · 4 rows | list – · data – | port (add to spell list) |
| `Mage.lua:75` | `AddDebuff` **Chilled**  | [6136, 7321, 12484, 16927] · dur [1500, 3000] · cd [] · 6 rows | list – · data – | port (add to spell list) |
| `Mage.lua:76` | `AddDebuff` **Frostfire Bolt**  | [401502, 401735, 1237312, 1237313] · dur [9000] · cd [] · 4 rows | list – · data – | port (add to spell list) |
| `Mage.lua:77` | `AddDebuff` **Frostjaw**  | absent | list – · data – | not feasible (no Forever spell) |
| `Mage.lua:78` | `AddDebuff` **Frozen orb**  | [440802, 440804, 440809, 440859] · dur [5000, 16000] · cd [60000] · 4 rows | list ✓ · data dur ✓ | already done (data row) |
| `Mage.lua:80` | `AddCooldown` **Fire Blast**  | [2136, 2137, 2138, 8412] · dur [10000] · cd [8000, 15000] · 17 rows | list – · data – | port (add to spell list) |
| `Mage.lua:81` | `AddCooldown` **Arcane Barrage**  | [400610, 401719] · dur [] · cd [3000] · 2 rows | list ✓ · data cd ✓ | already done (data row) |

**Mage tally:** 21 × `port (add to spell list)`, 16 × `not feasible (no Forever spell)`, 14 × `already done (data row)`.


### 4.3 Paladin (`Paladin.lua` in the reference tree; the addon is `Forte_Paladin`)

Registration chain: `/tmp/fxref/Forte_Class/Paladin/Paladin.lua` (`SetDefaultHasted` + the fluent `:AddSpell`/`:AddBuff`/`:AddDebuff`/`:AddChannel`/`:AddCooldown` block) and the `CD:` block. The port's landing is
`addon/Forte_Paladin/Data/Paladin.lua` generated from `tools/spell_lists/paladin.json`.

| ref | registration | Forever `spells.jsonl` | current coverage | verdict |
|---|---|---|---|---|
| `Paladin.lua:22` | `AddSpell` **Beacon of Light** `BUFF` `SetSpellModGlph(63865,30)` | [409906] · dur [] · cd [] · 1 rows | list – · data – | port (add to spell list) + glyph/talent mod dropped |
| `Paladin.lua:23` | `AddSpell` **Consecration** `AOE_DMG` `SetTickSpeed(1);SetSpellModGlph(54928,2)` | [20116, 20922, 20923, 20924] · dur [8000] · cd [8000] · 10 rows | list ✓ · data dur ✓ | already done (data row) + glyph/talent mod dropped |
| `Paladin.lua:24` | `AddSpell` **:AddSpell(31842,15, "Default",F.NOTARGET) -- Divine Illumination** `NOTARGET` | absent | list – · data – | n/a — commented out in the reference |
| `Paladin.lua:25` | `AddSpell` **Denounce** `BUFF` | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:26` | `AddSpell` **Improved Lay on Hands**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:27` | `AddSpell` **Turn Evil**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:28` | `AddSpell` **Exorcism** `TICKS` `SetTickSpeed(2);SetHasted(0)` | [879, 5614, 5615, 10312] · dur [] · cd [15000] · 12 rows | list ✓ · data cd ✓ | already done (data row) + tick feed unwired |
| `Paladin.lua:29` | `AddSpell` **Eternal Flame** `HOT` | absent | list – · data – | not feasible (no Forever spell) + tick feed unwired |
| `Paladin.lua:30` | `AddSpell` **Illuminated Healing (Shield)** `BUFF` | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:34` | `AddSpell` **Avenger's Shield (silence)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:35` | `AddSpell` **Divine Intervention	MOP**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:36` | `AddSpell` **Hammer of Justice (stun)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:37` | `AddSpell` **Reckoning**  | [20177, 1326084] · dur [] · cd [] · 2 rows | list – · data – | port (add to spell list) |
| `Paladin.lua:39` | `AddSpell` **Hand of Freedom** `BUFF+F` | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:40` | `AddSpell` **Hand of Protection** `BUFF+F` | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:41` | `AddSpell` **Hand of Sacrifice** `BUFF+F` | [409935, 462853] · dur [12000] · cd [120000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Paladin.lua:42` | `AddSpell` **Hand of Salvation** `BUFF+F` | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:43` | `AddSpell` **Hand of Purity** `BUFF+F` | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:45` | `AddSpell` **Vindication**  | [9452, 440667] · dur [30000] · cd [] · 2 rows | list – · data – | port (add to spell list) |
| `Paladin.lua:46` | `AddSpell` **Censure** `TICKS` | absent | list – · data – | not feasible (no Forever spell) + tick feed unwired |
| `Paladin.lua:47` | `AddSpell` **:AddSpell(88063,   6, "Buff",	F.BUFF) -- Guarded by the Light (Shield)** `BUFF` | absent | list – · data – | n/a — commented out in the reference |
| `Paladin.lua:50` | `AddSpell` **Repentance (stun)** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:54` | `AddSpell` **Illuminated Healing** `BUFF` | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:55` | `AddSpell` **Fist of Justice** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:58` | `AddBuff` **Aura Mastery**  | [409932] · dur [] · cd [] · 1 rows | list – · data – | port (add to spell list) |
| `Paladin.lua:59` | `AddBuff` **Divine Favor**  | [20216] · dur [] · cd [120000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Paladin.lua:60` | `AddBuff` **Enlightenment (T5 4-Set)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:61` | `AddBuff` **Holy Mending (T8 2-Set)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:62` | `AddBuff` **Infusion of Light** `SetStacks(0)` | [426065, 426179, 437063] · dur [15000] · cd [] · 3 rows | list – · data – | port (add to spell list) |
| `Paladin.lua:63` | `AddBuff` **Divine Plea** `SetTickSpeed(3)` | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:64` | `AddBuff` **Speed of Light**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:65` | `AddBuff` **Radiant (T11 4-Set)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:66` | `AddBuff` **Daybreak**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:67` | `AddBuff` **Holy Avenger**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:71` | `AddBuff` **Aegis (T8 4-Set)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:72` | `AddBuff` **Infused Shield (T5 4-Set)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:73` | `AddBuff` **Divine Shield**  | [642, 1020] · dur [10000, 12000] · cd [300000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Paladin.lua:74` | `AddBuff` **Holy Shield**  | [9800, 20925, 20927, 20928] · dur [10000, 60000] · cd [10000] · 4 rows | list – · data – | port (add to spell list) |
| `Paladin.lua:75` | `AddBuff` **Guardian of Ancient Kings**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:77` | `AddBuff` **Ardent Defender**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:78` | `AddBuff` **Divine Protection**  | [498, 5573, 27778, 458312] · dur [6000, 8000] · cd [300000] · 5 rows | list ✓ · data dur ✓ | already done (data row) |
| `Paladin.lua:80` | `AddBuff` **Grand Crusader**  | [1231126] · dur [] · cd [] · 1 rows | list – · data – | port (add to spell list) |
| `Paladin.lua:81` | `AddBuff` **Righteous Fury**  | [25780, 407627] · dur [1800000] · cd [] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Paladin.lua:82` | `AddBuff` **Vengeance**  | [20049, 20050] · dur [30000] · cd [] · 2 rows | list – · data – | port (add to spell list) |
| `Paladin.lua:83` | `AddBuff` **Bastion of Glory**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:84` | `AddBuff` **Shield of the Righteous**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:87` | `AddBuff` **The Art of War** `SetStacks(0)` | [415706, 426157] · dur [] · cd [] · 2 rows | list – · data – | port (add to spell list) |
| `Paladin.lua:88` | `AddBuff` **Replenishment**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:89` | `AddBuff` **Hand of Light**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:90` | `AddBuff` **Avenging Wrath**  | [407788, 409934] · dur [20000] · cd [180000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Paladin.lua:91` | `AddBuff` **Inquisition**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:92` | `AddBuff` **Selfless Healer**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:93` | `AddBuff` **Long Arm of the Law**  | absent | list – · data – | not feasible (no Forever spell) |
| `Paladin.lua:94` | `AddBuff` **Ancient Power**  | [1265634, 1318159] · dur [] · cd [] · 2 rows | list – · data – | port (add to spell list) |
| `Paladin.lua:96` | `AddCooldown` **Crusader Strike**  | [409914] · dur [] · cd [] · 1 rows | list ✓ · data – | already done (data row) |
| `Paladin.lua:97` | `AddCooldown` **Rebuke**  | [425616, 1302716] · dur [] · cd [] · 2 rows | list ✓ · data – | already done (data row) |
| `Paladin.lua:98` | `AddCooldown` **Holy Shock**  | [1311604, 1311605, 1311606] · dur [] · cd [10000] · 3 rows | list – · data – | port (add to spell list) |
| `Paladin.lua:100` | `AddDebuff` **Forbearance**  | [25771] · dur [60000] · cd [] · 1 rows | list – · data – | port (add to spell list) |

**Paladin tally:** 34 × `not feasible (no Forever spell)`, 12 × `port (add to spell list)`, 10 × `already done (data row)`, 2 × `n/a — commented out in the reference`.


### 4.4 Priest

Registration chain: `/tmp/fxref/Forte_Class/Priest/Priest.lua` (`SetDefaultHasted` + the fluent `:AddSpell`/`:AddBuff`/`:AddDebuff`/`:AddChannel`/`:AddCooldown` block) and the `CD:` block. The port's landing is
`addon/Forte_Priest/Data/Priest.lua` generated from `tools/spell_lists/priest.json`.

| ref | registration | Forever `spells.jsonl` | current coverage | verdict |
|---|---|---|---|---|
| `Priest.lua:26` | `AddChannel` **Divine Hymn**  | absent | list – · data – | not feasible (no Forever spell) + channel row (ticks unwired) |
| `Priest.lua:28` | `AddSpell` **Shadow Word: Pain** `TICKS+F` `SetSpellModSetB("Absolution Regalia",2,3)` | [589, 594, 970, 992] · dur [18000] · cd [] · 8 rows | list ✓ · data dur ✓ | already done (data row) + glyph/talent mod dropped + tick feed unwired |
| `Priest.lua:29` | `AddSpell` **Vampiric Touch** `TICKS` `SetSpellModSetB("Velen's/Zabra's Regalia",2,6)` | [402668] · dur [15000] · cd [] · 1 rows | list – · data – | port (add to spell list) + glyph/talent mod dropped + tick feed unwired |
| `Priest.lua:30` | `AddSpell` **Shadowfiend** `SUMMON` | [401977, 402843] · dur [15000] · cd [300000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Priest.lua:31` | `AddSpell` **Psychic Scream** `AOE` `SetSpellModGlph(56177,2)` | [8122, 8124, 10888, 10890] · dur [8000] · cd [30000] · 4 rows | list ✓ · data dur ✓ | already done (data row) + glyph/talent mod dropped |
| `Priest.lua:32` | `AddSpell` **Shackle Undead** `UNIQUE` | [9484, 9485, 10955] · dur [30000, 40000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Priest.lua:33` | `AddSpell` **:AddSpell(  453,  15,"Crowd",	F.UNIQUE) -- Mind Soothe** `UNIQUE` | absent | list – · data – | n/a — commented out in the reference |
| `Priest.lua:34` | `AddSpell` **Power Word: Shield** `BUFF` | [17, 592, 600, 3747] · dur [30000] · cd [4000] · 10 rows | list ✓ · data dur ✓ | already done (data row) |
| `Priest.lua:35` | `AddSpell` **Renew** `HOT` | [139, 6074, 6075, 6076] · dur [15000] · cd [] · 21 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Priest.lua:36` | `AddSpell` **Devouring Plague** `UNIQUE+F` `SetTickSpeed(1)` | [2944, 19276, 19277, 19278] · dur [24000] · cd [24000] · 6 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Priest.lua:37` | `AddSpell` **Silence** `UNIQUE` | [15487, 27559, 1293654] · dur [3000, 5000] · cd [45000] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Priest.lua:38` | `AddSpell` **holy fire** `TICKS` `SetTickSpeed(1)` | [14914, 15261, 15262, 15263] · dur [10000] · cd [] · 8 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Priest.lua:39` | `AddSpell` **Prayer of Mending** `BUFF` | [401859, 401877, 401880, 1240826] · dur [30000] · cd [10000] · 5 rows | list – · data – | port (add to spell list) |
| `Priest.lua:40` | `AddSpell` **:AddSpell(14893,  15,"Buff",	F.BUFF) -- Inspiration** `BUFF` | absent | list – · data – | n/a — commented out in the reference |
| `Priest.lua:41` | `AddSpell` **Pain Suppression** `BUFF` | [402004, 402839] · dur [8000] · cd [180000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Priest.lua:42` | `AddSpell` **Power Infusion** `BUFF` | [10060] · dur [15000] · cd [180000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Priest.lua:43` | `AddSpell` **Guardian Spirit** `BUFF` | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:44` | `AddSpell` **Divine Aegis (PASSIVE)** `BUFF` | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:45` | `AddSpell` **Grace (PASSIVE)** `BUFF` `SetStacks(3)` | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:46` | `AddSpell` **Blessed Healing (2 set T10)** `HOT` | absent | list – · data – | not feasible (no Forever spell) + tick feed unwired |
| `Priest.lua:48` | `AddSpell` **Echo of Light** `HOT` `SetTickSpeed(1)` | absent | list – · data – | not feasible (no Forever spell) + tick feed unwired |
| `Priest.lua:50` | `AddSpell` **Dominate Mind** `CHARM` | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:52` | `AddSpell` **Holy Word: Chastise** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:54` | `AddCooldown` **Mind Blast**  | [8092, 8102, 8103, 8104] · dur [] · cd [8000] · 9 rows | list – · data – | port (add to spell list) |
| `Priest.lua:55` | `AddCooldown` **Shadow Word: Death**  | [401955, 1309595, 1309633, 1309635] · dur [] · cd [12000, 18000] · 5 rows | list ✓ · data cd ✓ | already done (data row) |
| `Priest.lua:57` | `AddCooldown` **Holy Word: Chastise**  | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:58` | `AddCooldown` **Holy Word: Serenity**  | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:59` | `AddCooldown` **Holy Word: Sanctuary**  | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:63` | `AddChannel` **Mind Flay**  | [15407, 17311, 17312, 17313] · dur [3000] · cd [] · 6 rows | list – · data – | port (add to spell list) + channel row (ticks unwired) |
| `Priest.lua:64` | `AddChannel` **Mind Sear**  | [413259, 413260] · dur [6000] · cd [] · 2 rows | list – · data – | port (add to spell list) + channel row (ticks unwired) |
| `Priest.lua:67` | `AddBuff` **Serendipity**  | [413247, 413248] · dur [20000] · cd [] · 2 rows | list – · data – | port (add to spell list) |
| `Priest.lua:68` | `AddBuff` **Surge of Light**  | [431664, 431666, 431668] · dur [15000] · cd [] · 3 rows | list – · data – | port (add to spell list) |
| `Priest.lua:69` | `AddBuff` **Borrowed Time**  | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:70` | `AddBuff` **:AddBuff(34754) -- Holy Concentration**  | absent | list – · data – | n/a — commented out in the reference |
| `Priest.lua:71` | `AddBuff` **Fade**  | [586, 9578, 9579, 9592] · dur [10000] · cd [30000] · 8 rows | list ✓ · data dur ✓ | already done (data row) |
| `Priest.lua:72` | `AddBuff` **Inner fire**  | [588, 602, 1006, 7128] · dur [600000] · cd [] · 6 rows | list ✓ · data dur ✓ | already done (data row) |
| `Priest.lua:73` | `AddBuff` **Inner Will**  | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:74` | `AddBuff` **:AddBuff(15257) -- Shadow Weaving**  | absent | list – · data – | n/a — commented out in the reference |
| `Priest.lua:75` | `AddBuff` **Dispersion** `SetTickSpeed(1)` | [425294, 425307] · dur [6000] · cd [120000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Priest.lua:76` | `AddBuff` **Vampiric Embrace**  | [15286] · dur [30000] · cd [30000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Priest.lua:77` | `AddBuff` **:AddBuff(45237) -- Focused Will**  | absent | list – · data – | n/a — commented out in the reference |
| `Priest.lua:78` | `AddBuff` **Shadow Orb**  | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:79` | `AddBuff` **:AddBuff(95799) -- Empowered Shadow**  | absent | list – · data – | n/a — commented out in the reference |
| `Priest.lua:81` | `AddBuff` **Evangelism**  | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:82` | `AddBuff` **:AddBuff(87118) -- Dark Evangelism**  | absent | list – · data – | n/a — commented out in the reference |
| `Priest.lua:83` | `AddBuff` **Archangel**  | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:84` | `AddBuff` **Dark Archangel**  | absent | list – · data – | not feasible (no Forever spell) |
| `Priest.lua:87` | `AddDebuff` **id 6788 (no name comment)**  | absent | list – · data – | not feasible (no Forever spell) |

**Priest tally:** 18 × `not feasible (no Forever spell)`, 13 × `already done (data row)`, 10 × `port (add to spell list)`, 7 × `n/a — commented out in the reference`.


### 4.5 Rogue

Registration chain: `/tmp/fxref/Forte_Class/Rogue/Rogue.lua` (`SetDefaultHasted` + the fluent `:AddSpell`/`:AddBuff`/`:AddDebuff`/`:AddChannel`/`:AddCooldown` block) and the `CD:` block. The port's landing is
`addon/Forte_Rogue/Data/Rogue.lua` generated from `tools/spell_lists/rogue.json`.

| ref | registration | Forever `spells.jsonl` | current coverage | verdict |
|---|---|---|---|---|
| `Rogue.lua:19` | `AddSpell` **Kidney Shot** `UNIQUE` | [408, 8643] · dur [1000] · cd [20000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:20` | `AddSpell` **Nerve Strike** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:21` | `AddSpell` **Blind** `UNIQUE` | [2094] · dur [10000] · cd [300000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:22` | `AddSpell` **Sap** `UNIQUE` | [2070, 6770, 11297] · dur [25000, 35000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:23` | `AddSpell` **Deadly Throw interrupt** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:24` | `AddSpell` **Garrote silence** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:25` | `AddSpell` **Cheap Shot** `UNIQUE` | [1833] · dur [4000] · cd [] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:26` | `AddSpell` **Gouge** `UNIQUE` | [1776, 1777, 8629, 11285] · dur [4000] · cd [10000] · 5 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:27` | `AddSpell` **Dismantle** `UNIQUE` | [435467, 439164, 442206] · dur [] · cd [] · 3 rows | list – · data – | port (add to spell list) |
| `Rogue.lua:28` | `AddSpell` **Vendetta** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:30` | `AddSpell` **Revealing Strike** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:31` | `AddSpell` **Garrote** `TICKS` | [703, 8631, 8632, 8633] · dur [18000] · cd [] · 6 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Rogue.lua:32` | `AddSpell` **Rupture** `TICKS` `SetTickSpeed(2)` | [1943, 8639, 8640, 11273] · dur [6000] · cd [] · 6 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Rogue.lua:33` | `AddSpell` **Hemorrhage** `TICKS` | [16511] · dur [15000] · cd [] · 1 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Rogue.lua:35` | `AddSpell` **Crimson Tempest** `TICKS` `SetTickSpeed(2)` | [412096, 436611] · dur [2000] · cd [] · 2 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Rogue.lua:38` | `AddSpell` **Crippling Poison**  | [3409, 11201] · dur [12000] · cd [] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:39` | `AddSpell` **Mind-numbing Poison**  | [5760] · dur [10000] · cd [] · 1 rows | list – · data – | port (add to spell list) |
| `Rogue.lua:40` | `AddSpell` **Wound Poison**  | [13218, 13222, 13223, 13224] · dur [15000] · cd [] · 4 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:41` | `AddSpell` **Paralytic Poison**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:42` | `AddSpell` **Paralysis**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:43` | `AddSpell` **Leeching Poison**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:44` | `AddSpell` **Deadly Poison** `TICKS` | [2818] · dur [12000] · cd [] · 1 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Rogue.lua:47` | `AddBuff` **Adrenaline Rush**  | [13750, 28753] · dur [15000] · cd [300000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:48` | `AddBuff` **Blade Flurry**  | [13877] · dur [15000] · cd [120000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:49` | `AddBuff` **Evasion**  | [5277] · dur [15000] · cd [300000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:50` | `AddBuff` **Sprint**  | [2983, 8696, 11305] · dur [15000] · cd [300000] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:51` | `AddBuff` **Cloak of Shadows**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:52` | `AddBuff` **Vanish**  | [1856, 1857, 11327, 11329] · dur [10000] · cd [300000] · 5 rows | list ✓ · data cd ✓ | already done (data row) |
| `Rogue.lua:53` | `AddBuff` **Feint**  | [1966, 6768, 8637, 11303] · dur [] · cd [10000] · 5 rows | list ✓ · data cd ✓ | already done (data row) |
| `Rogue.lua:54` | `AddBuff` **Hunger for Blood**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:55` | `AddBuff` **Tricks of the Trade**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:56` | `AddBuff` **Slice and Dice**  | [5171, 6774] · dur [6000] · cd [] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Rogue.lua:57` | `AddBuff` **Envenom**  | [399968] · dur [] · cd [] · 1 rows | list – · data – | port (add to spell list) |
| `Rogue.lua:58` | `AddBuff` **Recuperate** `SetTickSpeed(3)` | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:60` | `AddBuff` **Shallow Insight**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:61` | `AddBuff` **Moderate Insight**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:62` | `AddBuff` **Deep Insight**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:63` | `AddBuff` **Killing Spree**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:64` | `AddBuff` **Combat Readiness**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:65` | `AddBuff` **Burst of Speed**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:66` | `AddBuff` **Shadow Dance**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:68` | `AddDebuff` **Paralysis**  | absent | list – · data – | not feasible (no Forever spell) |
| `Rogue.lua:69` | `AddDebuff` **Nerve Strike**  | absent | list – · data – | not feasible (no Forever spell) |

**Rogue tally:** 21 × `not feasible (no Forever spell)`, 17 × `already done (data row)`, 5 × `port (add to spell list)`.


### 4.6 Shaman

Registration chain: `/tmp/fxref/Forte_Class/Shaman/Shaman.lua` (`SetDefaultHasted` + the fluent `:AddSpell`/`:AddBuff`/`:AddDebuff`/`:AddChannel`/`:AddCooldown` block) and the `CD:` block. The port's landing is
`addon/Forte_Shaman/Data/Shaman.lua` generated from `tools/spell_lists/shaman.json`.

| ref | registration | Forever `spells.jsonl` | current coverage | verdict |
|---|---|---|---|---|
| `Shaman.lua:19` | `AddChannel` **Earthquake**  | absent | list – · data – | not feasible (no Forever spell) + channel row (ticks unwired) |
| `Shaman.lua:22` | `AddSpell` **Flame Shock** `TICKS` `SetSpellModGlph(55447,9)` | [8050, 8052, 8053, 10447] · dur [12000] · cd [6000] · 6 rows | list ✓ · data dur ✓ | already done (data row) + glyph/talent mod dropped + tick feed unwired |
| `Shaman.lua:23` | `AddSpell` **Frost Shock** `SetSpellModGlph(55443,2)` | [8056, 8058, 10472, 10473] · dur [8000] · cd [6000] · 4 rows | list ✓ · data dur ✓ | already done (data row) + glyph/talent mod dropped |
| `Shaman.lua:26` | `AddSpell` **Feral Spirit** `SUMMON` | [440580] · dur [45000] · cd [180000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Shaman.lua:27` | `AddSpell` **Stormstrike**  | [17364] · dur [12000] · cd [8000] · 1 rows | list – · data – | port (add to spell list) |
| `Shaman.lua:29` | `AddSpell` **:AddSpell(85838,  15,"Buff",	F.BUFF) -- Ancestral Fortitude** `BUFF` | absent | list – · data – | n/a — commented out in the reference |
| `Shaman.lua:30` | `AddSpell` **Earth Shield** `BUFF+F` | [408514, 408519, 409947] · dur [600000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Shaman.lua:31` | `AddSpell` **Bind Elemental** `UNIQUE` | absent | list – · data – | not feasible (no Forever spell) |
| `Shaman.lua:32` | `AddSpell` **Earthliving** `HOT` | absent | list – · data – | not feasible (no Forever spell) + tick feed unwired |
| `Shaman.lua:33` | `AddSpell` **Riptide** `HOT` | [408521, 409954, 1239242, 1239243] · dur [15000] · cd [6000] · 4 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Shaman.lua:35` | `AddSpell` **Earthquake** `AOE_DMG` `SetTickSpeed(1)` | absent | list – · data – | not feasible (no Forever spell) |
| `Shaman.lua:37` | `AddSpell` **Healing Rain** `AOE_HOT` `SetTickSpeed(2)` | [415236, 415242] · dur [10000] · cd [10000] · 2 rows | list ✓ · data dur ✓ | already done (data row) + tick feed unwired |
| `Shaman.lua:39` | `AddCooldown` **Lava Burst**  | [408490, 409952, 1238299, 1238300] · dur [] · cd [10000] · 5 rows | list – · data – | port (add to spell list) |
| `Shaman.lua:40` | `AddCooldown` **Thunderstorm**  | absent | list – · data – | not feasible (no Forever spell) |
| `Shaman.lua:41` | `AddCooldown` **Chain Lightning**  | [421, 930, 2860, 10605] · dur [] · cd [6000] · 10 rows | list ✓ · data cd ✓ | already done (data row) |
| `Shaman.lua:48` | `AddBuff` **Astral Shift**  | absent | list – · data – | not feasible (no Forever spell) |
| `Shaman.lua:49` | `AddBuff` **Ancestral Guidance**  | [409333, 409337, 409944] · dur [] · cd [] · 3 rows | list – · data – | port (add to spell list) |
| `Shaman.lua:50` | `AddBuff` **Ancestral Swiftness**  | absent | list – · data – | not feasible (no Forever spell) |
| `Shaman.lua:51` | `AddBuff` **Spiritwalker's Grace**  | absent | list – · data – | not feasible (no Forever spell) |
| `Shaman.lua:52` | `AddBuff` **Spirit Walk**  | absent | list – · data – | not feasible (no Forever spell) |
| `Shaman.lua:53` | `AddBuff` **Flurry**  | [12319, 12966, 16256, 16257] · dur [15000] · cd [] · 4 rows | list ✓ · data dur ✓ | already done (data row) |
| `Shaman.lua:56` | `AddBuff` **Lightning Shield**  | [324, 325, 905, 945] · dur [3000, 600000] · cd [] · 20 rows | list ✓ · data dur ✓ | already done (data row) |
| `Shaman.lua:57` | `AddBuff` **Elemental Mastery**  | [16166] · dur [15000] · cd [180000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Shaman.lua:58` | `AddBuff` **Clearcasting**  | [16246] · dur [15000] · cd [] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Shaman.lua:61` | `AddBuff` **Maelstrom Weapon**  | [408498, 408505, 409946] · dur [30000] · cd [] · 3 rows | list – · data – | port (add to spell list) |
| `Shaman.lua:62` | `AddBuff` **Shamanistic Rage**  | absent | list – · data – | not feasible (no Forever spell) |
| `Shaman.lua:66` | `AddBuff` **Tidal Waves**  | [432041, 432042] · dur [20000] · cd [] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Shaman.lua:67` | `AddBuff` **Water Shield**  | [408510, 408511, 409941] · dur [600000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) |

**Shaman tally:** 13 × `already done (data row)`, 10 × `not feasible (no Forever spell)`, 4 × `port (add to spell list)`, 1 × `n/a — commented out in the reference`.


### 4.7 Warrior

Registration chain: `/tmp/fxref/Forte_Class/Warrior/Warrior.lua` (`SetDefaultHasted` + the fluent `:AddSpell`/`:AddBuff`/`:AddDebuff`/`:AddChannel`/`:AddCooldown` block) and the `CD:` block. The port's landing is
`addon/Forte_Warrior/Data/Warrior.lua` generated from `tools/spell_lists/warrior.json`.

| ref | registration | Forever `spells.jsonl` | current coverage | verdict |
|---|---|---|---|---|
| `Warrior.lua:17` | `AddSpellRemap` **Sunder Armor (remap of 7386)**  | [7386, 7405, 8380, 11596] · dur [30000] · cd [] · 5 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:18` | `AddSpell` **Weakened Armor** `SetStacks(3)` | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:19` | `AddSpell` **Taunt**  | [355] · dur [3000] · cd [8000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:20` | `AddSpell` **Mocking Blow**  | [694, 7400, 7402, 20559] · dur [6000] · cd [120000] · 5 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:21` | `AddSpell` **Disarm**  | [676, 11879, 13534, 15752] · dur [5000, 10000] · cd [60000] · 4 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:24` | `AddSpellRemap` **Mortal Strike (remap of 12294)**  | [12294, 21551, 21552, 21553] · dur [10000] · cd [6000] · 4 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:25` | `AddSpell` **Mortal Wounds** `AddExtraSpell(115768)` | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:26` | `AddSpell` **Deep Wounds** `TICKS` | [12162, 12834] · dur [] · cd [] · 2 rows | list – · data – | port (add to spell list) + tick feed unwired |
| `Warrior.lua:28` | `AddSpell` **Hamstring**  | [1715, 7372, 7373] · dur [15000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:29` | `AddSpell` **Demoralizing Shout** `AOE` | [1160, 6190, 11554, 11555] · dur [45000] · cd [] · 5 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:30` | `AddSpell` **Intimidating Shout** `AOE` | [5246, 20511] · dur [8000] · cd [180000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:31` | `AddSpell` **Thunder Clap (Weakened Blows)** `AOE` | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:32` | `AddSpell` **Piercing Howl** `AOE` | [12323] · dur [6000] · cd [] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:33` | `AddSpell` **Shockwave** `AOE` | [440488, 440497] · dur [4000] · cd [20000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:34` | `AddSpell` **Vigilance** `BUFF` | [426972, 427068] · dur [1800000] · cd [] · 2 rows | list – · data – | port (add to spell list) |
| `Warrior.lua:35` | `AddSpell` **Colossus Smash**  | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:38` | `AddBuff` **Commanding Shout**  | [403215, 403435] · dur [300000] · cd [] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:39` | `AddBuff` **Enrage**  | [12317, 12686, 12880, 425415] · dur [12000, 15000] · cd [] · 7 rows | list – · data – | port (add to spell list) |
| `Warrior.lua:40` | `AddBuff` **Sweeping Strikes**  | [12292] · dur [20000] · cd [30000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:41` | `AddBuff` **Death Wish**  | [12328] · dur [30000] · cd [180000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:43` | `AddBuff` **Battle Shout**  | [5242, 6192, 6673, 11549] · dur [180000] · cd [] · 7 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:44` | `AddBuff` **Berserker Rage**  | [18499] · dur [10000] · cd [30000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:45` | `AddBuff` **Recklessness**  | [1719] · dur [15000] · cd [1800000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:47` | `AddBuff` **Die by the Sword**  | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:48` | `AddBuff` **Slam!**  | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:49` | `AddBuff` **Deadly Calm**  | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:50` | `AddBuff` **Enraged Regeneration** `SetTickSpeed(1)` | [402913, 403359] · dur [10000] · cd [180000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:51` | `AddBuff` **Rallying Cry**  | [426490, 426492] · dur [10000] · cd [180000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:52` | `AddBuff` **Spell Reflection**  | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:53` | `AddBuff` **Shield Wall**  | [871] · dur [12000] · cd [900000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:54` | `AddBuff` **Last Stand**  | [12975, 12976] · dur [20000] · cd [180000] · 2 rows | list ✓ · data cd ✓ | already done (data row) |
| `Warrior.lua:55` | `AddBuff` **Shield Barrier**  | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:56` | `AddBuff` **Shield Block**  | [2565] · dur [7000] · cd [5000] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:59` | `AddDebuff` **Mortal Strike**  | [12294, 21551, 21552, 21553] · dur [10000] · cd [6000] · 4 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:60` | `AddDebuff` **Hamstring**  | [1715, 7372, 7373] · dur [15000] · cd [] · 3 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:61` | `AddDebuff` **Demoralizing Shout (only target damage reduction to you)**  | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:62` | `AddDebuff` **Intimidating Shout**  | [5246, 20511] · dur [8000] · cd [180000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:63` | `AddDebuff` **Piercing Howl**  | [12323] · dur [6000] · cd [] · 1 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:64` | `AddDebuff` **Shockwave**  | [440488, 440497] · dur [4000] · cd [20000] · 2 rows | list ✓ · data dur ✓ | already done (data row) |
| `Warrior.lua:66` | `AddDebuff` **Shattering Throw**  | absent | list – · data – | not feasible (no Forever spell) |
| `Warrior.lua:67` | `AddDebuff` **Colossus Smash**  | absent | list – · data – | not feasible (no Forever spell) |

**Warrior tally:** 26 × `already done (data row)`, 12 × `not feasible (no Forever spell)`, 3 × `port (add to spell list)`.

## 5. Non-registration features, per class

Everything the module does **outside** the `ST:`/`CD:` registration chain: custom code, the
options/message tree, the sound rows, the labels and the filter pre-seeds.


### 5.1 Druid

| ref | feature | behaviour | legality | Forever | current coverage | verdict |
|---|---|---|---|---|---|---|
| `Druid.lua:22-33` | `FW:SetCustomName` ×9 — Berserk **(Feral)**, Feral Charge **(Bear)/(Cat)**, Mangle **(Bear)/(Cat)**, Skull Bash **(Bear)/(Cat)**, Swipe **(Bear)/(Cat)** | the row/bar/icon label of a spell id gains a form suffix | label-only (a read of nothing) | the paired 2012 ids are all absent (A1); Forever carries **one** name per pair (`Bash` 5211, `Skull Bash` 410176, `Lacerate`, `Faerie Fire` 770) | `Registry.lua:357-368` alias rows (locale names only) | **not feasible as written; port-adapted** — a `labelFor` seam (S16) |
| `Druid.lua:35-36` | `FW:RegisterSet` "Thunderheart Regalia", "Nordrassil Raiment" (+ the users `:57,:63`) | tier-set tick/duration modifiers | A4 | no set/bonus API in the catalog | dropped by `Registry.lua:19-27` | **not feasible** |
| `Druid.lua:43-46` | `AddChannel` Hurricane `16914`, Astral Communion `127663`, Astral Storm `106996`/`740` | the channelling bars | A3 | **Hurricane exists** (fam=Druid, 10 s) — already our row `1278759 durationMs=10000`; the other three absent | the Hurricane row lands in the `Channel` band | **already done** (Hurricane) / **not feasible** (the two MoP channels) |
| `Druid.lua:144-149` | `RegisterOnBuffGain` → `PlaySound("TimerClearcastingSound")` *(commented upstream)* | a proc-triggered sound | A8 | `12536` (the glyph's trigger) absent; `Clearcasting` fam=Druid exists | `Pages/Sound.lua:27-48` has no proc row | **not feasible** |
| `Druid.lua:159-164` | `CD:AddCooldownBuff` Mark of the Wild `1126`, Omen of Clarity `16864` (Barkskin/Thorns commented at `:159-160`) | "this buff appearing is a bar" | own cast → feasible | Mark of the Wild is in `[buffs]` | the data rows + the cast spine | **already done** (S12) |
| `Druid.lua:166-167` | `CD:AddHiddenCooldown(nil,48517,30)` + `(nil,48518,30)` — Eclipse (Solar/Lunar) | a 30 s eclipse window with no cast | A8 | `48517/48518` absent; Forever's Eclipse rows are `408248/408255` (fam=Druid) | no hidden-cooldown concept | **not feasible** in combat (S11) |
| `Druid.lua:169` | `AddHiddenCooldown(nil,16886,60)` — Nature's Grace *(commented)* | proc-cooldown | A8 | `16886` exists (3 s) | — | **not feasible** in combat |
| `Druid.lua:172-173` | `CD:AddCasterPowerupCooldowns()` / `AddMeleePowerupCooldowns()` | the trinket-proc lists | feasible | the generated item data | `Core/Items.lua` | **already done** (S10) |
| `Druid.lua:176-178` | `SetMainCategory(SOUND)` + `AddOption("SND", CLEARCASTING, …)` *(commented)* | the sound option row | legal | — | `Pages/Sound.lua` | **not feasible** (its trigger is the proc) |
| `Druid.lua:182-206` | `CA:RegisterOnSelfCastSuccess` + 6 × `CA:CastShow`: Barkskin, Survival Instincts, Frenzied Regeneration, Rebirth `+target`, Innervate `+target`, Tranquility | the self-cast raid warnings | **feasible** — the cast spine | all six exist (22812, 61336, 22842, 20484, 29166, 740) and 5 are in our lists (`Rebirth` in `[utility]`) | `Announce:Group/Channel` (`Announce.lua:122,150`) + the cast hook shape (`Module.lua:385-410`) | **port-adapted**: the S17 table + 6 rows |
| `Druid.lua:208-227` | `SetMainCategory(RAID_MESSAGES)` + 2 × `SetSubCategory` ("Self Damage Reduction", "Other") + 6 `MS2` rows | the options tree for those six | legal | — | `P.FADE_ROWS`-shaped table is the landing | **port-adapted** (S17/S22) |
| `Localization.lua:24-28,73-88` | the 5 spell-name labels, `_FERAL/_BEAR/_CAT` ×7 locales, the 9 composed labels | the labels S16 renames with | legal | — | `Forte_Core/Core/Locale.lua` (client-name aliases) | **label seam only** (S16) |


### 5.2 Mage

| ref | feature | behaviour | legality | Forever | current coverage | verdict |
|---|---|---|---|---|---|---|
| `Mage.lua:85-92` | `ST:RegisterOnTimerBreak(function(unit,mark,spell) … CA:CastShow("PolymorphBreak",unit))` + `ST:RegisterOnTimerFade(poly,"PolymorphFade")` | the Polymorph break (with the raid-mark prefix) and the fade warning | feasible | `Polymorph` 118/12824 (fam=Mage, 20–40 s) | **`RaidMsg.lua:107-110`** + `Module.lua:316,334` | **already done** (S18) |
| `Mage.lua:94-100` | `RegisterOnBuffGain` → Clearcasting sound *(commented)* | proc sound | A8 | — | — | **not feasible** |
| `Mage.lua:103` | `CD:AddHiddenCooldown(nil,86949,60)` — Cauterize | a 60 s fake cooldown | A8 | `86949` absent, no `Cauterize` row in 7,503 | — | **not feasible** |
| `Mage.lua:104` | `AddCasterPowerupCooldowns()` | trinkets | feasible | generated | `Core/Items.lua` | **already done** |
| `Mage.lua:111-114` | `SetSubCategory(BREAK_FADE)` + `AddOption("INF", BREAK_FADE_HINT1)` + `MS2` PolymorphBreak/PolymorphFade | the options rows | legal | — | the two fade rows ship (default-off, `RaidMsg.lua:152-163`) | **already done** |
| `Mage.lua:116-118` | the SOUND category + the Clearcasting row *(commented)* | as above | A8 | — | — | **not feasible** |
| `Localization.lua:29-60` | `POLYMORPH_BREAK` / `POLYMORPH_FADE` strings ×7 locales | the announce texts | legal | — | verbatim in `RaidMsg.lua:108-109` | **already done** |


### 5.3 Paladin

| ref | feature | behaviour | legality | Forever | current coverage | verdict |
|---|---|---|---|---|---|---|
| `Paladin.lua:15` | `FW:RegisterSet("Redemption Plate", …)` *(commented)* | tier set | A4 | no API | — | **n/a** |
| `Paladin.lua:107-117` | `CD:AddCooldownBuff` ×7 — Seal of Insight `20165`, Blessing of Kings `20217`, Righteous Fury `25780`, Seal of Justice `20164`, Seal of Righteousness `20154`, Blessing of Might `19740`, Seal of Truth `31801` | "the seal/blessing landing is a bar" | own cast → feasible | the 2012 seals (`Seal of Insight/Truth/Righteousness`) are absent; Forever's set is `Seal of Fury/Righteousness/Command/Wisdom/Light/Justice/the Crusader` (in `[auras]`) and the blessings are `Blessing of Kings/Light/Might/Wisdom` (in `[buffs]`) | the data rows + the cast spine | **already done (name-swapped)** — the port's data carries the Forever seal set |
| `Paladin.lua:119-120` | the two powerup lists | trinkets | feasible | generated | `Core/Items.lua` | **already done** |
| `Paladin.lua:125-143` | `CA:RegisterOnSelfCastSuccess` + 8 × `CA:CastShow`: Aura Mastery, **Salvation `+t`**, Hand of Sacrifice `+t`, Hand of Freedom `+t`, Hand of Protection `+t`, Divine Protection, **Guardian of Ancient Kings gated on `GetSpecialization(nil,nil,GetActiveSpecGroup()) == 2`**, Ardent Defender | the hand-of / DR raid warnings | feasible; **the gate is not** — the bare 2012 globals `GetSpecialization`/`GetActiveSpecGroup` are ABSENT from the pinned catalog; `C_SpecializationInfo.GetSpecialization` + `C_SpecializationInfo.GetActiveSpecGroup` are IN (A4) | Aura Mastery `31821` absent; `Salvation` 1038 (fam=Paladin), `Hand of Sacrifice` 409935/462853, `Blessing of Freedom` 1044 / `Blessing of Protection` 1022 / `Blessing of Sacrifice` 6940, `Divine Protection` (498/5573/27778), `Avenging Wrath` (407788/409934) exist | `Announce:Group/Channel` + the cast hook | **port-adapted**: the S17 table + 8 rows, the spec gate re-expressed on the pinned `C_SpecializationInfo` pair |
| `Paladin.lua:147-168` | `RAID_MESSAGES` + "Raid Damage Reduction" / "Hands" / "Self Damage Reduction" + 8 `MS2` rows | the options tree | legal | — | the S17 table | **port-adapted** |
| `Localization.lua:18-48` | `GOAK` (`86669`) + `_HOLY/_PROT/_RETR` labels *(the whole block is commented out in the source)* | labels | legal | — | the label seam | **n/a (commented)** |


### 5.4 Priest

| ref | feature | behaviour | legality | Forever | current coverage | verdict |
|---|---|---|---|---|---|---|
| `Priest.lua:12-16` | `FW:RegisterSet` "Absolution Regalia", "Velen's/Zabra's Regalia" (+ the users `:28,:29`) | tier-set tick modifiers | A4 | no API | dropped | **not feasible** |
| `Priest.lua:90-101` | `local rapture = FW:SpellName(47755)` → `PR_CombatLogEvent(event,…)` testing `select(5,…)==PLAYER and select(13,…)==rapture` → `CD:HiddenCooldown(rapture, 12, texture)`, registered on **`COMBAT_LOG_EVENT_UNFILTERED`** (`:100`) | a 12 s Rapture window per proc | **banned** (A2) — the only combat-log consumer in the seven | `47755` absent; the whole Rapture family is absent from `spells.jsonl` | no hidden-cooldown concept | **not feasible** (A2 + A8 + A1 — three independent reasons) |
| `Priest.lua:103` | `CD:AddCasterPowerupCooldowns()` | trinkets | feasible | generated | `Core/Items.lua` | **already done** |
| — | the module has **no** `RAID_MESSAGES` / `SOUND` / `SELF_MESSAGES` block (it ends at `:106`) | nothing to port | — | — | — | **n/a** |
| `Localization.lua:1-35` | a locale stub (no active label) | — | — | — | — | **n/a** |


### 5.5 Rogue

| ref | feature | behaviour | legality | Forever | current coverage | verdict |
|---|---|---|---|---|---|---|
| `Rogue.lua:12` | `FW:SetCustomName(89775, HEMORRHAGE_GLYPH)` *(commented)* | a glyph label | A4 | no glyph API | — | **not feasible** |
| `Rogue.lua:73-80` | `ST:RegisterOnTimerBreak(… CA:CastShow("SapBreak",unit))` + `ST:RegisterOnTimerFade(sap,"SapFade")` | the Sap break/fade | feasible | `Sap` 6770 (25–45 s) | **`RaidMsg.lua:111-114`** | **already done** (S18) |
| `Rogue.lua:84-89` | `CD:AddCooldownBuff` ×6 — Crippling `30981`, Mind-numbing `5761`, Wound `8679`, Deadly `2818`, Paralytic `108215`, Leeching `108211` | the poison-application windows | feasible — poisons are **temporary weapon enchants** on this engine | Deadly/Mind-numbing/Wound/Crippling exist; Paralytic/Leeching absent | **`Forte_Cooldown/Core/Enchants.lua`** (`C_Item.GetWeaponEnchantInfo().timeLeft`, ms → `:16-24`, `WEAPON_ENCHANT_CHANGED` at `Module.lua:482`) | **already done — superseded by a better mechanism** |
| `Rogue.lua:91` | `AddMeleePowerupCooldowns()` | trinkets | feasible | generated | `Core/Items.lua` | **already done** |
| `Rogue.lua:95-98` | `SetSubCategory(BREAK_FADE)` + `INF` hint + `MS2` SapBreak/SapFade | the options rows | legal | — | shipped rows | **already done** |
| `Localization.lua:27-58` | `SAP_BREAK` / `SAP_FADE` ×7 locales | the texts | legal | — | verbatim in `RaidMsg.lua:112-113` | **already done** |


### 5.6 Shaman — the only class with real custom code

| ref | feature | behaviour | legality | Forever | current coverage | verdict |
|---|---|---|---|---|---|---|
| `Shaman.lua:43` | `SetTickSpeed(2, 8190)` — the 2-argument form: a global tick period for Magma Totem | tick marks on the totem row | A6 | Magma Totem `8190`/`10587` (20 s) — our row `10587 durationMs=20000` | the renderer draws ticks; nothing feeds them | **port-adapted** (the A6 feed; the row exists) |
| `Shaman.lua:76` | `index_to_group = {"TotemFire","TotemEarth","TotemWater","TotemAir"}` | the four elemental **slots** as timer groups | — | the four element groups have no spell rows (`Fire/Earth/Water/Air Totem` absent) | no group concept (`Registry.lua:22-27`) | **port-adapted — needs a new Timer capability** |
| `Shaman.lua:77-93` | `SH_TOTEM_UPDATE(event,index)`: `GetTotemInfo(index)` → `_, name, startTime, duration, icon`; `ST.ST:find(group,21)`; `ST.ST:remove(i)` when the slot is retaken; `ST:Fade(i, (<0.75) and 2 or 3)` when the read names no totem; `ST:AddManualSpellOfType(name, ST.DEFAULT)` + the raw `ST.ST:insert(…)` | **one row per totem slot**, replaced in place, with the fade lead shortened in the last 0.75 s | `GetTotemInfo`, `GetTotemTimeLeft`, `GetNumTotemSlots`, `C_Secrets.ShouldTotemSlotBeSecret`, `ShouldTotemSpellBeSecret`, `PLAYER_TOTEM_UPDATE` are all in the pinned catalog → **feasible** with the two secrecy gates + `PlainOrNil` (`[INFERENCE]` payload shape from `:77-79`) | the 15 totems are in `[totems]` and generated with durations (`Decoy 425874 10000`, `Grounding 8177 45000`, `Stoneskin 10408 300000`, `Magma 10587 20000`, `Searing 10438 55000`, `Mana Tide 1325256 13000` …) | the **bars already exist** through the cast spine (a totem drop is a cast); the **slot-replacement rule and the element grouping do not** | **port-adapted** — a `totemSlot` group + evictions in the Timer (T3); the data side is done |
| `Shaman.lua:95` | `FW:RegisterToEvent("PLAYER_TOTEM_UPDATE", SH_TotemUpdate)` | the feed | feasible (catalog event, `api_lint`-legal) | — | the event is pinned | **port-adapted** (the reader body = T3) |
| `Shaman.lua:97-101` | `FW:RegisterDelayedLoadEvent(function(self) for i=1,4 do SH_TotemUpdate(self,i) end end)` | seed the live totems after login | feasible | — | the login/entering-world handler pattern (`Forte_Cooldown/Module.lua:455-478`) | **already-done pattern** |
| `Shaman.lua:104-108` | `SetSubCategory(MY_SPELLS)` + 4 × `AddOption("CO2", TOTEM_FIRE…, "TotemFire", 99):SetFunc(ST.FilterChange)` | **the filter pre-seeds**: four group show/hide rows | UI-only | — | `Forte_Timer/Pages/Timer.lua:42-96` has **no** band/group filter rows | **not feasible as written** — a Timer-page feature (A7), Shaman-only demand |
| `Shaman.lua:110-113` | `FW.InstanceDefault.Timer.TotemFire/Earth/Water/Air = {[0]=true, r,g,b}` | the per-group bar colours | UI-only | — | the port colours per category, and the five `BarColor*` are "Not wired yet (stored)" (`Timer.lua:181-195`) | **port-adapted with the A7/T3 feature** |
| `Shaman.lua:117-118` | the two powerup lists | trinkets | feasible | generated | `Core/Items.lua` | **already done** |
| `Localization.lua:25-77` | `TOTEM_FIRE/EARTH/WATER/AIR` labels ×7 locales | the four filter labels | legal | — | — | **needed only with the filter feature** |


### 5.7 Warrior

| ref | feature | behaviour | legality | Forever | current coverage | verdict |
|---|---|---|---|---|---|---|
| `Warrior.lua:17,24` | `AddSpellRemap(7386,113746)` Sunder Armor→Weakened Armor; `AddSpellRemap(12294,115804)` Mortal Strike→Mortal Wounds | display the MoP rename under the classic cast | n/a on this engine (A1; the registry is name-keyed, `Registry.lua:5-9`) | `Sunder Armor` 7386 (30 s, in `[buffs]`), `Mortal Strike` 12294 (10 s, in `[cooldowns]`) | the Forever names are already the keys | **already done by construction** |
| `Warrior.lua:70` | `AddMeleeBuffs()` | the shared melee raid-buff list | A3/S9 | the Forever pair is `Rage of the Farseer` (Shaman), `Bloodrage`/`Heroism` 23682/`Commanding Shout` 469 | the class data rows | **already done** |
| `Warrior.lua:73` | `CD:AddCooldownBuff(6673)` — Battle Shout | the shout window | own cast | `Battle Shout` (183 s, in `[stances]`) | the data row | **already done** |
| `Warrior.lua:74` | `AddHiddenCooldown(nil,60503,6)` — Taste for Blood *(commented)* | a 6 s proc window | A8 | `60503` absent; Forever's `Taste for Blood` is in `[buffs]` | — | **not feasible** in combat (S11) |
| `Warrior.lua:75` | `AddMeleePowerupCooldowns()` | trinkets | feasible | generated | `Core/Items.lua` | **already done** |
| `Warrior.lua:79-102` | `CA:RegisterOnSelfCastSuccess` + 6 × `CA:CastShow`: Shield Wall, Last Stand, Rallying Cry, Enraged Regeneration, Intervene `+t`, Vigilance `+t` | the DR raid warnings | feasible | all six exist (`Intervene` in `[utility]`, `Vigilance` fam=Warrior dur 1 800 000) | `Announce:Group/Channel` + the cast hook | **port-adapted**: the S17 table + 6 rows |
| `Warrior.lua:108-119` | `RAID_MESSAGES` + "Raid Damage Reduction" / "Self Damage Reduction" / "Other" + 6 `MS2` rows | the options tree | legal | — | the S17 table | **port-adapted** |
| `Localization.lua:1-38` | a locale stub | — | — | — | — | **n/a** |
| — | **GCD / stance table**: the Warrior module calls **no** `CA:SetGCDStance` (the only call site in the whole reference is `DeathKnight.lua:14`), and **no** `FW:RegisterSpecialCastTime` (only `Hunter.lua:113`) | the stance-keyed GCD / cast-time table | — | the stances are plain rows (`Battle/Berserker/Defensive/Gladiator Stance` in `[stances]`) | the GCD band is modelled (`Engine.lua:98-100,364-388`) | **n/a for these seven** (S23) |

---

## 6. Work estimate

| class | spell-list entries | shared-feed dependencies | new class code | new shared feature | size |
|---|---|---|---|---|---|
| **Druid** | **12** (`Lifebloom`, `Pounce`, `Pounce Bleed`, `Skull Bash`, `Starfall`, `Nature's Grace`, `Berserk`, `Clearcasting`, `Dash`, `Living Seed`, `Savage Defense`, `Thrash`) | A5 hasted rows, A6 ticks (9 DoT/HoT rows) | none | the S16 label seam + the S17 announce table (6 rows) | **medium** |
| **Mage** | **18** (`Pyroblast`, `Ignite`, `Living Bomb`, `Flamestrike`, `Blizzard`, `Combustion`, `Cone of Cold`, `Frost Nova`, `Deep Freeze`, `Frostfire Bolt`, `Fire Blast`, `Blast Wave`, `Arcane Blast`, `Chilled`, `Freeze`, `Brain Freeze`, `Fingers of Frost`, `Mana Surge` (the rest of the reference's Mage rows — `Counterspell`, `Frozen Orb`, `Arcane Barrage`, `Evocation`, `Ice Block`, `Mana Shield`, `Arcane Power`, `Icy Veins`, the three armours, `Ice Barrier` — are already in `[cooldowns]/[buffs]/[utility]`) | A5 (`SetDefaultHasted(1)` for all), A6 (8 ticked rows) | **none** | none (Polymorph is in) | **small** |
| **Paladin** | **12** (`Holy Shock`, `Holy Shield`, `Beacon of Light`, `Forbearance`, `Vindication`, `Vengeance`, `The Art of War`, `Aura Mastery`, `Infusion of Light`, `Reckoning`, `Ancient Power`, `Grand Crusader`) | A5, A6 | none | the S17 announce table (8 rows) + the `C_SpecializationInfo` gate | **medium** |
| **Priest** | **10** (`Renew`, `Devouring Plague`, `Holy Fire`, `Mind Blast`, `Mind Flay`, `Mind Sear`, `Vampiric Touch`, `Serendipity`, `Surge of Light`, `Prayer of Mending`) | A5, A6 (7 ticked rows) | **none** (Rapture is dead) | none | **small** |
| **Rogue** | **5** (`Deadly Poison`, `Mind-numbing Poison`, `Crimson Tempest`, `Envenom`, `Dismantle`) | A5 (`SetDefaultHasted(0)` = unhasted), A6 | none | none (Sap + poisons done) | **small** |
| **Shaman** | **4** (`Stormstrike`, `Lava Burst`, `Maelstrom Weapon`, `Ancestral Guidance`) | A5, A6 (`Magma Totem` ticks) | a `PLAYER_TOTEM_UPDATE` reader (the `Forte_Hunter/Core/Tools.lua` shape) | **the totem slot/element grouping + the four filter pre-seeds + the four colours** | **medium** |
| **Warrior** | **3** (`Deep Wounds`, `Enrage`, `Vigilance`) | A5 (`SetDefaultHasted(0)`), A6 | none | the S17 announce table (6 rows) | **small** |

Totals: **64 spell-list names** (62 addable today; `Mana Surge` resolves only to family 11 = Shaman and `Grand Crusader` only to family 7 = Druid, so the generator's documented foreign-family rule (`tools/gen_spell_data.py` docstring) prints them as gaps), 20 announce rows across 3 classes, 1 label seam, 1 totem
feature, 0 new class modules beyond the Shaman's.


### 6.1 The add-list, class by class (T1's exact work)

`tools/spell_lists/<class>.json` — a name per line, in the existing group whose intent
matches (the groups are the file's own: `[cooldowns]`, `[buffs]`, `[auras]/[forms]/[stances]`,
`[utility]`, `[totems]`, `[stealth_utilities]`).

| class | names to add |
|---|---|
| druid | `Lifebloom`, `Living Seed`, `Skull Bash`, `Pounce`, `Pounce Bleed`, `Thrash`, `Nature's Grace`, `Starfall`, `Dash`, `Berserk`, `Savage Defense`, `Clearcasting` |
| mage | `Blizzard`, `Living Bomb`, `Ignite`, `Pyroblast`, `Flamestrike`, `Combustion`, `Cone of Cold`, `Frost Nova`, `Deep Freeze`, `Frostfire Bolt`, `Mana Surge`*, `Brain Freeze`, `Fingers of Frost`, `Arcane Blast`, `Blast Wave`, `Freeze`, `Chilled`, `Fire Blast` |
| paladin | `Beacon of Light`, `Reckoning`, `Vindication`, `Aura Mastery`, `Infusion of Light`, `Holy Shield`, `Grand Crusader`*, `Vengeance`, `The Art of War`, `Ancient Power`, `Holy Shock`, `Forbearance` |
| priest | `Vampiric Touch`, `Renew`, `Devouring Plague`, `Holy Fire`, `Prayer of Mending`, `Mind Blast`, `Mind Flay`, `Mind Sear`, `Serendipity`, `Surge of Light` |
| rogue | `Dismantle`, `Crimson Tempest`, `Mind-numbing Poison`, `Deadly Poison`, `Envenom` |
| shaman | `Stormstrike`, `Lava Burst`, `Ancestral Guidance`, `Maelstrom Weapon` |
| warrior | `Deep Wounds`, `Vigilance`, `Enrage` |

`*` = a generator gap on today's data (the family rule, A1); the rest resolve in-family.

**Executed 2026-11-02 (T1, `fx-worker SpellLists`).** The Q1 split: **43 cast spells added**
(druid 8: Lifebloom, Skull Bash, Pounce, Pounce Bleed, Starfall, Berserk, Dash, Thrash ·
mage 13: Blizzard, Living Bomb, Pyroblast, Flamestrike, Combustion, Cone of Cold, Frost Nova,
Deep Freeze, Frostfire Bolt, Arcane Blast, Blast Wave, Fire Blast, Freeze ·
paladin 5: Beacon of Light, Reckoning, Aura Mastery, Holy Shield, Holy Shock ·
priest 8: Vampiric Touch, Renew, Devouring Plague, Holy Fire, Prayer of Mending, Mind Blast,
Mind Flay, Mind Sear · rogue 5: Dismantle, Crimson Tempest, Mind-numbing Poison, Deadly Poison,
Envenom · shaman 4: Stormstrike, Lava Burst, Ancestral Guidance, Heroism · warrior 0 — its three
§6.1 names are all Q1 deferrals), **22 proc/passive names deferred** into a `_deferred_H7` note in
each spell-list file (druid 4, mage 5, paladin 7, priest 2, shaman 1, warrior 3) for H7. All five
§8.6 `fam=None` rows are in (Dash, Thrash, Freeze, Heroism, Dismantle). Counts after the cut:
druid 60, mage 65, paladin 57, priest 55, rogue 55, shaman 65, warrior 64 — **0 gaps** every class.
Eight added names ride data rows with NO window (Thrash 21919, Beacon of Light 409906,
Aura Mastery 409932, Reckoning 1326084 `durationMs -1`, Dismantle 442206, Envenom 399968,
Ancestral Guidance 409944, Heroism 23689 `durationMs -1`): they are in the lists and on the data,
tracked by neither engine, pinned as a named list in `Forte_Cooldown/tests/test_tracked_set.lua`.
Their colour bands went into `Forte_Timer/Core/Registry.lua`'s `KIND_RULES` band tables (the
band-term lists only, per the manager's ruling; `Registry:Build`, the feed and the band order
untouched). Each band is the **original's own registration kind** for that name, read out of
`/tmp/fxref/Forte_Class/<Class>/<Class>.lua` — `Crowd` → Crowds (Skull Bash `:71`, Cone of Cold
`Mage.lua:30`, Reckoning `Paladin.lua:37`, Dismantle `Rogue.lua:27`, Frostfire Bolt `Mage.lua:37`),
`Heal`/`F.HOT` → Heal (Lifebloom `Druid.lua:62`, Renew `Priest.lua:35`), `AddChannel` → Channel
(Mind Flay/Mind Sear `Priest.lua:63,64`), `AddCooldown` → Cooldown (Fire Blast `Mage.lua:80`, Mind
Blast `Priest.lua:54`, Lava Burst `Shaman.lua:39`, Holy Shock `Paladin.lua:98`), `AddSelfDebuff` →
SelfDebuff (Arcane Blast `Mage.lua:67`), `F.BUFF` → Buff (Beacon of Light `Paladin.lua:22`),
`AddBuff` → SelfBuff (Starfall `Druid.lua:109`, Holy Shield `Paladin.lua:74`, Envenom
`Rogue.lua:57`, Heroism `Hunter.lua:45`), and the `Default` + `F.TICKS` DoT family → TargetDebuff
(the druid bleeds, the mage bomb/fire line, Combustion, Vampiric Touch, Holy Fire, Crimson Tempest)
plus its `AddDebuff` lines (Blast Wave `Mage.lua:72`, Freeze `:74`). Patterns stay `^Name`
front-anchored with no `|` alternation. The nine-class census
(`Forte_Timer/tests/test_kinds.lua`, all nine class add-ons loaded by `test_00_class_data.lua`)
prints `Default=0` over the 590 tracked names.

Two spell-list rows the reference also names are **already present under the Forever
name** and need no add: `Counterspell`/`Frozen Orb`/`Arcane Barrage`/`Evocation`/
`Ice Block`/`Mana Shield`/`Arcane Power`/`Icy Veins`/the three armours/`Ice Barrier` (mage),
`Bash`/`Enrage`/`Prowl`/`Savage Roar`/`Rake`/`Rip`/`Lacerate`/`Faerie Fire`/`Moonfire`/
`Sunfire`/`Insect Swarm`/`Entangling Roots`/`Hibernate`/`Force of Nature`/`Regrowth`/`Rejuvenation`/`Wild Growth`/`Thorns`/`Mark of the Wild`/`Gift of the Wild`/
`Barkskin`/`Innervate`/`Swiftmend`/`Wild Rejuvenation`/`Tranquility`/`Nature's Swiftness`/
`Nature's Grasp`/`Survival Instincts`/`Frenzied Regeneration`/`Astral Power`/`Prowl`/`Shifting Power`/`Feral Charge`/`Survival Instincts` (druid), `Gouge`/`Cheap Shot`/
`Kidney Shot`/`Blind`/`Sap`/`Garrote`/`Rupture`/`Hemorrhage`/`Expose Armor`/
`Crippling Poison`/`Wound Poison`/`Slice and Dice`/`Evasion`/`Sprint`/`Vanish`/`Feint`/
`Adrenaline Rush`/`Blade Flurry`/`Shadowstep`/`Preparation`/`Vigor`/`Cold Blood` (rogue),
`Taunt`/`Mocking Blow`/`Disarm`/`Hamstring`/`Demoralizing Shout`/`Intimidating Shout`/
`Piercing Howl`/`Shockwave`/`Thunder Clap`/`Mortal Strike`/`Sunder Armor`/`Hamstring`/
`Battle Shout`/`Commanding Shout`/`Berserker Rage`/`Recklessness`/`Shield Wall`/
`Shield Block`/`Last Stand`/`Death Wish`/`Sweeping Strikes`/`Rallying Cry`/
`Enraged Regeneration`/`Taste for Blood`/`Sudden Death`/`Victorious` (warrior),
`Power Word: Shield`/`Shadow Word: Pain`/`Shadow Word: Death`/`Shadowfiend`/
`Psychic Scream`/`Shackle Undead`/`Silence`/`Pain Suppression`/`Power Infusion`/`Fade`/
`Inner Fire`/`Dispersion`/`Vampiric Embrace`/`Shadowform`/`Chastise`/`Circle of Healing`/
`Fear Ward` (priest), `Consecration`/`Exorcism`/`Rebuke`/`Judgement`/`Righteous Judgement`/
`Crusader Strike`/`Divine Shield`/`Divine Protection`/`Divine Favor`/`Righteous Fury`/
`Avenging Wrath`/`Repentance`/`Hand of Sacrifice`/`Salvation`/`Mass Salvation`/the six seals/
the six auras/`Blessing of Freedom`/`Blessing of Protection`/`Blessing of Sacrifice`/
`Blessings of Kings/Might/Light/Wisdom` (paladin), `Flame Shock`/`Frost Shock`/
`Earth Shock`/`Stormstrike`→add/`Earth Shield`/`Lightning Shield`/`Water Shield`/
`Riptide`/`Healing Rain`/`Chain Lightning`/`Flurry`/`Clearcasting`/`Elemental Devastation`/
`Power Surge`/`Tidal Waves`/`Way of Earth`/`Shield Mastery`/`Energized Shield`/
`Windfury Weapon`/`Flametongue Weapon`/`Rockbiter Weapon`/`Frostbrand Attack`/all 15
`[totems]`/`Feral Spirit`/`Elemental Mastery`/`Nature's Swiftness`/`Rage of the Farseer`/
`Far Sight`/`Reincarnation` (shaman).

### 6.2 Wave I-2 data laws (2026-11-03, `fx-worker I2b Data`)

Four laws now bind the generator chain (`tools/extract_70707.py` →
`tools/overrides_70707.json` → `tools/overrides_devnotes_2026-11-03.json` →
`tools/gen_spell_data.py`); sources: `docs/research/upstream-data-2026-11-03.md`,
`docs/research/forever-dev-notes-2026-11-03.md`.

1. **Rank law (store coverage).** When the 70707 store covers a tracked name — one of
   its ids carries a real value field (Names/Misc/Cooldowns/Categories/AuraOptions row) —
   the picked row is the store row carrying that name's `Rank N` subtext / SpellLevel /
   MaxLevel; a bare book twin (no subtext, `spellLevel >= 70`) is excluded from the pick.
   Implemented as the `store_covered` leg of `pick_current_rank` (between the cast leg
   and the id tiebreak, so it never outranks carry/has-cd/level/has-cast). Landing:
   `Primal Bite` 1238073 → **1238070 (Rank 3)**; `Holy Shock` 1311606 Rank 1 → **20930
   Rank 4** (the store's highest-ranked Holy Shock row, MaxLevel 62, subtext Rank 4).
   Store-uncovered names keep the book ranks (Ferocious Bite's 31018 pair is NOT store-
   covered — the store only ranks 22829 — so the coverage leg, not the book cut, is the
   tool; the book cut stays the documented fallback).
2. **Dev-notes layer.** `tools/overrides_devnotes_2026-11-03.json` carries cited post-9
   lines as `{id: {fields, cite, …}}`; the generator applies them AFTER the 70707 layer
   and BEFORE row assembly, keyed by the PICKED row's id — a row for a name no spell
   list tracks is inert by design (the file's `_meta` pins the store build the values
   were probed against) — and echoes every applied row into the
   generated file header (`-- Post-9 dev-notes values applied (N):` sections). It is the
   ONLY authority for values the store does not carry — the values never enter the
   extractor, so re-running the extractor cannot wash them out. Applied: Slam
   1310200 cd 18000→15000 (the row fires via the picked row's captured
   Category 2412 pair; all five ranks carry the line), Stormstrike 17364
   cd 8000→6000, Riptide 1239243 categoryCd 6000→12000. Blood Fury 20572
   cd 120000 is a cited row that is INERT by design (no spell list tracks the
   racials; the row is the launch-day racial probe's pin). Berserk: the post-9
   notes REMOVED the talent (Primal Bite replaces it) — the name is pruned from
   the druid list, the store's 417141 value rows ride on unused; the 300/360
   `spellLevel` lines need no row (no captured level exists for them).
3. **§3.5 feed capture.** The extractor captures `Effects[].PeriodMs` → `periodMs`,
   `Targets.Target` → `targetCode` (scalar category rows only; the per-effect list form
   is left to the base rows), `AuraOptions.MaxStack` → `maxStack`. The generator feeds
   them ONLY where the row's own `Effects` and base twin stay silent — same shape as the
   `procFlag`/`icdMs` laws — with the base row of the same id as the effects source when
   the pick rides a store-synthesised row; `maxStack` feeds only at >= 2 (a 0/1 row says
   "no stacking"; 2012 `maxStack=1` is a real cap, 0 is "not stacking"). Landings:
   Reckoning/Lifebloom/Echo of Fury/Echo of Command keep their stacks; Oath of Light
   `tickEvery 1.5` + `noTarget` (Target 1 + a 1500 period); Black Arrow `tickEvery 2`;
   Wild Growth `tickEvery 1`; Vigor/Rebuke/Shield Mastery/Soul Harvest `noTarget`;
   Blizzard/Flamestrike ride the captured category.
4. **Rename alias law.** A build rename (dev notes "X -> Y") lands as a static alias
   PAIR, never a name edit: `addon/Forte_Core/Core/Locale.lua` `Locale.RenameAliases`
   makes `Locale.CanonicalName` fold the new client spelling onto the captured data key
   (locale-independent, folds on enUS; id-keyed lookups are untouched), and the spell
   list's `_renames` block puts the alias into the generated `ByName` table. Both
   spellings then resolve on every client. When a future data pull carries the NEW
   spelling, the pair FLIPS (the alias becomes the data key). Live pair: Totemic
   Projection ↔ Totemic Call (437009), Elemental Mastery ↔ Lightning Mastery (16166;
   the captured client spells the data side "Elemental Mastery" —
   upstream-data §5 rows 5-6).
5. **Post-9 pruning (2026-11-03).** Removed from the lists (the spells are gone from the
   live client — dev notes post-9): druid `Berserk` (the store still carries it as
   417141; removal is list-level), shaman `Lava Burst`, paladin `Blessing of Light`,
   `Salvation`, `Mass Salvation`, `Revoke`. `Call of Thunder 16120` STAYS (a totem,
   scry §2.1.2). §5.1 adds landed: druid `Ferocious Bite` + `Bloom` (1328621 is a bare
   store shell — the row is the name + id, the layer's first day-1 probe row), mage
   `Ice Lance` (1240047, cd 8000 — the 8 s the notes cite), paladin `Oath of Light`
   (1328548) + `Shieldsworn` (1328551) + `Echo of Fury`/`Echo of Command` (1311701/3,
   scry §2.1.10 — distinct from the paladin's own Echo of the Chosen), priest `Dark
   Inspiration` (1326168), rogue `Setup` (13983 — the store-covering row wins the pick;
   15250 stays untracked), shaman `Windfury Totem` — item 6.
6. **Totem-window law (wave I-2b follow-up).** For a `... Totem` CAST name (the
   name shape `Forte_Shaman/Core/Totems.lua:SlotSpellNames` uses), the rank pick
   drops carriers whose `DurationMs` sits below the largest captured window:
   the short rows sharing a totem's name are its proc/trigger auras (Windfury
   Totem's 1000 ms Rank-3 twin 10610, `procFlag 4`), and the row that stands is
   the summon window the element slot draws. `Windfury Totem` rides **10614
   (Rank 3, 300 000)** — the shape of its sibling `Windwall Totem` 15112 — so the
   cast spine's prediction (in sealed combat the ONLY signal until the slot
   event lands) is the five minutes, not a one-second blip; the F-B dedupe
   (`Forte_Shaman/tests/test_totem_dedupe.lua`) keeps it one row. Pinned in the
   real paths by `Forte_Timer/tests/test_timer_display_rows.lua`: the cast
   spine's `OnSent`/`OnSucceeded`/`Pump`, the slot's `OnTotemUpdate`, the
   module's `Draw` — exactly ONE row with a 300 s window in the Air element
   group. No other tracked totem moved (all already rode window rows).

### 6.3 Wave I-3 H7: the proc names land (2026-11-03, `fx-worker I3e Procs`)

The `H7` proc pass (`docs/design-combat-procs.md`) shipped its data half. A
deferred proc name moves out of a spell list's `_deferred_H7` note into the
group its intent matches when — and only when — the client data resolves it:
an id the wowsims MIT capture (`/tmp/wowsims-forever` @ `6e69a7f4`, the
`names.json` keys + `spell_store_inputs.json` rows) and the mythicsim base
spells both carry, resolved by the §6.1 family-scoped rank law. Nothing
hand-typed; the 2026-11-03 dev-notes removals (Thousand Cuts, Cutthroat,
Murder, Improved Distract) are excluded by law — none of these names is one.
The generator chain ran all nine classes; every name below resolves with 0
gaps. The 12 moves:

| class | name → id | window | carrier note |
|---|---|---|---|
| Druid | Clearcasting → 16870 | 15 000 ms | family 7, the §3.1 store row |
| Mage | Fingers of Frost → 400669 | 15 000 ms | carrier over the bare 401741/400647 twins |
| Mage | Ignite → 412538 | 4 000 ms | carrier over the bare 11119 |
| Paladin | Forbearance → 25771 | 60 000 ms | the heal-reduce debuff, target-side |
| Paladin | Infusion of Light → 437063 | 15 000 ms | carrier over the bare 426065/426179 |
| Paladin | Vengeance → 20050 | 30 000 ms | `maxStack = 3` (the store row); uncoded-family fallback |
| Paladin | Vindication → 440667 | 30 000 ms | carrier over the bare 440668 |
| Shaman | Maelstrom Weapon → 408505 | 30 000 ms | the only carrier of the family-11 trio (§3.1 caveat: the window rides the picked sibling); `maxStack = 5` |
| Warrior | Enrage → 440483 | 12 000 ms | category 21; the store-coverage rank law (§6.2 law 1) lifts 440483 over the 12880/427066 rank pair — same 12 s window, the §3.1 row-10 value |
| Warrior | Deep Wounds → 12834 | **none** | the store's value row carries `DurationMs 0`: a name + id row, pinned "tracked by neither" — the bleed window rides the Mortal Strike line, arriving with the S15 extra-spell feed |
| Rogue | Shank → 15617 | **none** | 70707-sourced `{id, name}` shell (the index-shell law, the `Mesmerize` 24594 shape): the store's 15248/15617 rows are value-less Classic names; post-9's 10 s cd is text-only — the launch-day probe row |
| Rogue | Death Mark → 1325758 | **none** | as Shank: the 1316709/1325756-8 rows are value-less name shells; post-9's 10 s cd / 6 s mark text-only |

The 14 kept deferred, with the reason class (§3.1/§5.1): **no names.json key**
— Living Seed, Nature's Grace, Savage Defense, Brain Freeze, Chilled, Ancient
Power, The Art of War, Serendipity, Surge of Light, Vigilance; **family-law
gap** (the only id is foreign-family, §6.1 never takes a foreign row) — Mana
Surge (shaman 11's 23572), Grand Crusader (druid 7's 1231126); **no client
Names row at all** (the post-9 net-news, ids at opening are the launch probe)
— Poised, Reckless Swings.

**Follow-up (2026-11-04, the uiforever Mage-scenario probe):** the Mage's
**Clearcasting → 12536** joins the landed set (census 12 → 13). The scenario
measured the Arcane Concentration proc live — player aura spellId 12536,
duration 15 s applied and readable — and the Spell Timer drew no row because
`tools/spell_lists/mage.json` did not name the spell. The name is a
**five-row family spread** in this build (mage 12536 fam 3, druid 16870 fam 7,
shaman 16246 fam 11, rogue 457342/467735 fam 8; every row DurationMs 15 000,
store procFlag 87376, caster-side effect `[1, 0]` → `noTarget`), and the
§6.1/§6.2 family-scoped law resolves each class's list to its own row —
**no per-class id pin needed**; the census test `test_tracked_set.lua` pins
mage 12536 / druid 16870 / shaman 16246, all 15 000 ms + noTarget, so a family
slide trips at once. **Priest: no row** — the classic Holy-Concentration
Clearcasting has no family-6 row in the base pull or the 70707 store, so
`priest.json` does not name it (the pin asserts the absence; the day a
family-6 row lands is a decision). The name rides the shipped `^Clearcasting`
SelfBuff term (`Registry.lua`), `test_kinds.lua` stays `Default = 0`.

**The eight T1 no-window pins, re-read against the `6e69a7f4` store:** none
gained a positive window — Thrash 21919 (0), Beacon of Light 409906 (0), Aura
Mastery 409932 (0), Reckoning 1326084 (−1, +1500 icd), Envenom 399968 (0),
Dismantle 442206 (0, +12 000 icd), Heroism 23689 (−1), Ancestral Guidance (the
family-11 rows value-less; the 60 s is family-10 409324). All pins stand
unchanged.

**The in-combat safety law (the gate this wave required, read off the shipped
code):** a proc row can never render a *wrong* row from a sealed read —
`Forte_Timer/Core/Reconcile.lua:80-91` `Gates()` returns true for
`SecretState.aurasSecret` and for in-combat, so every aura sweep runs ZERO
reads; a sealed read that does happen returns `nil, "secret"`
(`Reconcile.lua:158-161`); `SweepBulk` inserts a row only for a plain
`expire ~= nil` on a tracked name (`:308-311`); `Registry:Build` registers
only `dur > 0` rows (`Registry.lua:451`); the Cooldown engine ignores
nil/secret reads outright (`Forte_Cooldown/Core/Engine.lua:210-213`). A sealed
read yields **no row, not a wrong row** — the proc adds are safe on this
build.

Colour bands: six new `Registry.lua` `KIND_RULES` terms in `I-3e H7` comment
blocks (Fingers of Frost / Infusion of Light / Maelstrom Weapon → SelfBuff;
Ignite / Forbearance → TargetDebuff; Shank → Cooldown); Clearcasting,
Vengeance, Vindication, Enrage, Deep Wounds (`Wound`), Death Mark (`Mark$`)
ride shipped terms. `test_kinds.lua` keeps `Default = 0` over every landed
name. The census mirror: `Forte_Cooldown/tests/test_tracked_set.lua` keeps
the T1 side (41 / pinned 8) intact, shrinks `T1_DEFERRED` 22 → 14 and adds the
I-3e landed census (12 landed, 3 pinned no-window).

## 7. Suggested worker split (3 tickets)

| ticket | owner | scope | touches |
|---|---|---|---|
| **T1 — seven-class spell-list cutover** | `fx-worker` | add the 64 names (§6.1) (one `//`-style intent note per add inside the JSON `_notes`), regenerate, keep the per-class data tests green, record the 144 dropped 2012 spells in the note field so the cut is auditable | `tools/spell_lists/{druid,mage,paladin,priest,rogue,shaman,warrior}.json`, the generated `addon/Forte_*/Data/*.lua`, `addon/Forte_*/tests/test_00_class_data.lua` |
| **T2 — cast-announce + label framework, then the Druid/Paladin/Warrior rows** | `fx-worker` | a `P.CAST_ROWS` table in `RaidMsg.lua` mirroring `P.FADE_ROWS` (`:79-115`), the generalized cast hook in `Forte_Messages/Module.lua` (the `OnCastForSoulstone` shape at `:385-410`), the 20 announce rows with their verbatim texts, the Paladin's `C_SpecializationInfo` gate, and a `labelFor` seam over `Registry.entries[].name` for the Druid's form suffixes | `addon/Forte_Messages/Pages/RaidMsg.lua`, `addon/Forte_Messages/Module.lua`, `addon/Forte_Messages/tests/*`, `addon/Forte_Timer/Core/Registry.lua`, `addon/Forte_Druid/**` (label rows only) |
| **T3 — Shaman totem slots + the shared `tickEvery`/`noTarget`/`MaxStack` feeds** | `fx-worker` | the A6 feeds in `Registry:Build` + the generator columns, the totem slot/element grouping with in-place replacement (the `Shaman.lua:77-93` semantics), the `PLAYER_TOTEM_UPDATE`/`GetTotemInfo` reader behind `C_Secrets.Should…` + `PlainOrNil`, and only then the four filter/colour rows on the Timer page | `addon/Forte_Timer/Core/Registry.lua`, `addon/Forte_Timer/Pages/Timer.lua`, `addon/Forte_Shaman/**`, `tools/gen_spell_data.py` |

Deliberately **not** ticketed: the 2012 glyph/talent/tier-set columns (A4), the PvP length table
(A9), and every `AddHiddenCooldown` proc window (A8) — each needs an engine feature or a data
source that does not exist yet, and §2 names the missing prerequisite for each.

## 8. Open questions

1. **Owner scope**: the 64 names in §6.1 are the reference's spells that survive on Forever, not a
   judgement that ForteXorcist should track them (the lists are owner-curated). Which of the
   per-class blocks does the owner want — the whole cut, or the CC/DoT/HoT cores only?
2. **Shaman filter layer (A7)**: the four totem filter rows and their colours need a
   per-group show/hide layer the Timer page does not have, and the Shaman is its only
   2012-era customer. Build the layer, or drop the pre-seeds and keep the totem bars?
3. **Gate-container timeline (A8)**: Eclipse, Cauterize, Rapture, Taste for Blood and the
   Clearcasting sounds all land on `design-combat-procs.md` §4 P-C/P-D. Is that on the
   launch-day plan, and does Rapture stay dead even after it (its 2012 spell row is absent)?
4. **PvP (A9)**: is rated PvP in scope for this build at all? `SetDurationPVP` has no data
   source on Forever (only `Effects[].PvpMult` damage multipliers).
5. **Form labelling (S16)**: the Druid's ten `SetCustomName` pairs have no Forever counterparts
   (the pair ids are all absent). Accept the plain name, add a `labelFor` seam (T2), or key the
   label off the data's `StanceMask`?
6. **`fam=None` rows**: several Forever-only names carry no family (`Dash` 1850, `Thrash` 21919,
   `Dismantle` 435467, `Freeze` 18798, `Heroism` 23682). The generator's `isKnown` gate
   (`Engine:Build(classFile, isKnown)`, `Engine.lua:132`) accepts them, so they are addable —
   confirm the owner wants class-agnostic rows in a class list.
   **RESOLVED 2026-11-02 (manager ruling, PLAN §11.1 wave 2b T1): add them.** All five are in the
   class lists now (`Dash`/`Thrash` druid, `Freeze` mage, `Dismantle` rogue, `Heroism` shaman;
   the generator resolves them through its documented uncoded-family tier, so 0 gaps). Four of
   the five ride a real window (`Dash` 23110 30 s cd + 15 s, `Freeze` 27868 3 s, `Heroism` 23689
   `durationMs -1` is a permanent aura, `Dismantle` 442206 name-only with `icdMs 12000`,
   `Thrash` 21919 name-only) — the last two are the tracked-by-neither entries pinned in
   `Forte_Cooldown/tests/test_tracked_set.lua`.
