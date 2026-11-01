# Secrets & unknowns — ten launch-critical questions (2026-11-01)

Research note for ForteXorcist for WoW Forever (interface **16001**, engine 12.x, `WOW_PROJECT_CAMELOT`).
All local paths relative to the repo unless noted. Client root `…/_forever_/` =
`<WoW install>/_forever_/`
(`.flavor.info` = `wowf`, installed 2026-11-01).

**Evidence labels** (per the spec-corpus convention, `wow-ui-sim-specs/secret-auras.md:12-19`):

- **DOCS** — pinned Forever API surface: `docs/api/wow-addon-api-agents/skills/*/references/generated/forever.json`
  (record `id` carries the Blizzard source `File.lua:line`; target `forever`, version `1.60.1.70532`) and
  spec paragraphs quoting the shipped `Blizzard_APIDocumentationGenerated` annotations / patch-API change text.
- **STRING** — strings extracted from the installed client `Wow.exe` (85,829,840 B, `strings -a -n 8`,
  97,685 strings, extract dated 2026-11-01; line numbers = offsets in that extract), plus client strings
  quoted inside specs.
- **NATIVE** — clean-room client behaviour traces recorded in specs (`native-evidence-70688`, builds
  12.1.5.70688, **Forever 70707**, 12.1.7 PTR; `secret-auras.md:96-103`).
- **UI** — shipped third-party Lua in the installed client (`…/_forever_/Interface/AddOns/…`,
  EllesmereUI suite v9.7.2 with `## Interface: …, 16001`) and addon code analysed in
  `docs/reference/addons/*.md` (cited as `powerauras-classicprocauras.md:N` etc.).
- **SIM** — wow-ui-sim v0.1.39-forever (`wow-ui-sim-v0.1.39-forever-linux-x86_64`) facts and my own headless
  runs today via `run.sh … --exec-lua @file lua-errors` (`FX*` markers). **Not evidence of real-client
  behaviour** — used for surface shape and for reading the simulator's client-derived data tables
  (labelled explicitly). `--exec-lua @file` **does** work (PLAN §10.6's "ignored" applies to `run-tests`).

Simulator runs used: corpus probes over FX's own tracked spells (`/tmp/fxprobe/out_FXAURA.json`),
a full-ID scan `1..2,500,000` of `C_Secrets.GetSpellAuraSecrecy` (`/tmp/fxprobe/scan_*.raw`),
name-resolution and surface probes (`/tmp/fxprobe/probe_*.lua`).

---

## 1. Own-cast `UNIT_SPELLCAST_SUCCEEDED` payload: which fields are secret, when; is *player* ever restricted?

**Answer:** The event is annotated `SecretWhenUnitSpellCastRestricted`; payload `(unitTarget, castGUID, spellID, castBarID)`
with `castBarID` explicitly `NeverSecret` — so the other three wrap *iff the casting-restriction guard applies to that unit's
casts*; the player's own casts are always *delivered* (the "player exception") and every shipped/analysed addon treats the
own-cast payload as usable — whether the fields wrap in combat is the launch-day cast-counter probe, not a doc fact.

**Evidence:**

- DOCS: all 16 `UNIT_SPELLCAST_*` events + `GetUnitEmpower*` + `UnitCastingInfo`/`UnitChannelInfo` carry
  `SecretWhenUnitSpellCastRestricted: true` (pinned records: `forever.json` `event:UNIT_SPELLCAST_SUCCEEDED@UnitDocumentation.lua:4844`,
  `…START@:4816`, `…STOP@:4830`, `…INTERRUPTED@:4741`, `…SENT@:4802`, `…FAILED@:4713`, `UnitCastingInfo@:827`, `UnitChannelInfo@:869`).
  SUCCEEDED payload: `unitTarget:UnitTokenVariant`, `castGUID:WOWGUID`, `spellID:number` (no `NeverSecret`),
  `castBarID:UnitCastBarID Nilable` **`NeverSecret:true`** — same file:line (full record dumped today).
- DOCS: payload shape `(unitTarget, castGUID, spellID, castBarID)` pinned in
  `wow-ui-sim-specs/spellcast-event-payloads.md:3` (`data/patch-api/sources/12.1.5-register.json`).
- DOCS: in `UnitCastingInfo`/`UnitChannelInfo`, `castBarID`, `isTradeskill`, `delayTimeMs`, `isEmpowered`,
  `numEmpowerStages` are also `NeverSecret`; "These annotations do not establish simulator enforcement"
  (`cast-bar-id-returns.md:31`).
- DOCS (patch-API prose, 12.0.5 change line 193): suppression of SUCCEEDED applies only when the completion
  **is instant, the spell is secret, and the caster is not the player**; the deliver-list is "the player
  exception, public instant casts, and noninstant casts" (`secret-instant-cast-events.md:7-8`). Out of scope
  there: "SecretWhenUnitSpellCastRestricted payload wrapping/taint. Delivery eligibility does not prove the
  cached declaration's payload secrecy contract" (`:43`).
- UNKNOWN: "Native GUID formatting, allocator lifetime/wrap semantics, and secret/restricted-value behavior
  remain unverified" (`spellcast-event-payloads.md:71`); "Casting and threat restriction triggers: **best-guess,
  native UNKNOWN**" (`secret-auras.md:105`); `ShouldUnitSpellCastingBeSecret(unit)` exists per-unit
  (DOCS `event … @SecretPredicateAPIDocumentation.lua:371` — dumped today).
- STRING: the guard states are named by cvar help: `addonCombatRestrictionsForced` "If set, APIs guarded in
  combat will be restricted, or may return secrets"; same pattern for `addonEncounterRestrictionsForced`,
  `addonChallengeModeRestrictionsForced` ("challenge mode and mythic plus status"), `addonPvPMatchRestrictionsForced`
  ("PvP match state"), `addonMapRestrictionsForced` ("current map type"), `addonChatRestrictionsForced`
  ("in lockdown") — Wow.exe strings @68660–68677. The restriction machinery is generic (state machine pair
  `AddOnRestrictionType→AddOnRestrictionState` in the RTTI string @68677); which categories gate *cast* events
  is not in the strings.
- STRING: the per-spell classifier ships: "Usage: local secrecy = C_Secrets.GetSpellCastSecrecy(spellIdentifier)"
  — Wow.exe strings @53358-59.
- UI: CooldownMaster / PowerAuras / Shadowflare all anchor own-cast predictions on
  `UNIT_SPELLCAST_SUCCEEDED:player` in combat (`docs/reference/addons/powerauras-classicprocauras.md:239-242`
  "structurally identical to PLAN.md §3.2 … including the secret-`spellID` press-memory"; Shadowflare ships
  cast-predict on it). These addons work on the live client — implying own-cast events arrive usable in practice.
- SIM (surface only): the sim registers the events + payloads (`spellcast-event-payloads.md:14-20` SOURCE) and has
  **no** `C_Secrets.GetSpellCastSecrecy` (my run `probe_surfa`: `CS:GetSpellCastSecrecy=false`) — absence is a sim gap,
  the STRING above proves client presence.

**Confidence:** payload shape and annotations **high** (DOCS); "player casts are delivered and usable" **high**
(DOCS prose + UI practice); "which of the three fields wrap in which states, for `player` specifically" —
**unknown**, by design; per-spell `GetSpellCastSecrecy` exists on the client **high** (STRING), its data **unseen** locally.

**Design implication:** the cast-predict + reconcile core (PLAN §3.2) is the right architecture *because* the answer
is unknown; keep the planned "cast counter" so day-1 data classifies plain/secret per spell immediately; do not let
`spellID`-keyed state be required (keep last-known-name press-memory, per PA's secret-`spellID` memory pattern).
Use `castBarID` freely — it is DOCS-`NeverSecret`.

**Remaining live probe (day-1, out of combat, then in combat, then in a dungeon/PvP):**

```lua
/run 1 local f = CreateFrame("Frame") f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:SetScript("OnEvent", function(_,e,u,g,s,b)
  local t = {}
  for i,v in ipairs({u,g,s,b}) do t[i] = (issecretvalue and issecretvalue(v)) and "SECRET"
    or (type(v)=="number" and "plain#"..tostring(v)) or (type(v)) end
  DEFAULT_CHAT_FRAME:AddMessage(("CASTPAY u=%s g=%s s=%s b=%s secret=%s restrict=%s castRestr=%s")
    :format(t[1],t[2],t[3],t[4],
      tostring(C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions()),
      tostring(C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive
        and (C_RestrictedActions.IsAddOnRestrictionActive(0) or C_RestrictedActions.IsAddOnRestrictionActive(1)
          or C_RestrictedActions.IsAddOnRestrictionActive(2) or C_RestrictedActions.IsAddOnRestrictionActive(3)
          or C_RestrictedActions.IsAddOnRestrictionActive(4))),
      tostring(C_Secrets and C_Secrets.ShouldUnitSpellCastingBeSecret
        and C_Secrets.ShouldUnitSpellCastingBeSecret("player"))))
  if C_Secrets and C_Secrets.GetSpellCastSecrecy and type(s)=="number" then
    DEFAULT_CHAT_FRAME:AddMessage(("CASTSEC spell=%s level=%s"):format(tostring(s),tostring(C_Secrets.GetSpellCastSecrecy(s))))
  end
end)
```
(Fire a few instant casts + one long cast in each state; the line `CASTPAY` classifies each field; absence of
`issecretvalue` on the client is itself a data point.)

---

## 2. `C_Spell.GetSpellCooldown` / `GetSpellCooldownDuration` / `GetSpellCharges` secrecy

**Answer:** `GetSpellCooldown` and `GetSpellCharges` carry `SecretWhenCooldownsRestricted: true` (arguments
`AllowedWhenTainted`); `GetSpellCooldownDuration` has **no** output-restriction annotation (returns a
`LuaDurationObject`); under restriction only the *numeric* fields wrap — `isEnabled`, `isActive`, `isOnGCD`
(cooldown) and `maxCharges`, `isActive` (charges) are DOCS `NeverSecret`; the restriction is driven by
combat/encounter/challenge/PvP contexts **plus individual spell exceptions** per the shipped annotation prose.

**Evidence:**

- DOCS (pinned catalog, dumped today): `C_Spell.GetSpellCharges @SpellDocumentation.lua:290`
  `SecretWhenCooldownsRestricted=true, SecretArguments=AllowedWhenTainted → SpellChargeInfo`;
  `C_Spell.GetSpellCooldown @SpellDocumentation.lua:308` (same pair) `→ SpellCooldownInfo`;
  `C_Spell.GetSpellCooldownDuration @SpellDocumentation.lua:326` — `SecretArguments=AllowedWhenTainted` only,
  returns `LuaDurationObject`.
- DOCS `SpellChargeInfo @SpellSharedDocumentation.lua:5`: `maxCharges` **NeverSecret**, `isActive` **NeverSecret**;
  `currentCharges`, `cooldownStartTime`, `cooldownDuration`, `chargeModRate` unannotated.
  `SpellCooldownInfo @SpellSharedDocumentation.lua:18`: `isEnabled`, `isActive`, `isOnGCD` **NeverSecret**;
  `startTime`, `duration`, `modRate`, `activeCategory`, `timeUntilEndOfStartRecovery` unannotated.
- DOCS-via-spec: "restriction annotation includes combat/encounter/challenge/PvP contexts **and individual spell
  exceptions**" (`cooldown-restriction.md:32`, citing shipped `SecretPredicatesDocumentation.lua:89–92`);
  register IDs `api-C_Spell-GetSpellCharges-303` / `api-C_Spell-GetSpellCooldown…` changed to
  `SecretWhenCooldownsRestricted` at 12.0.5 (`cooldown-restriction.md:28-30`);
  "`maxCharges` and the newer `isActive` are `NeverSecret`" (`:33`); "`isEnabled` and `isActive` are `NeverSecret`"
  (`action-cooldown-output-restriction.md:95`, quoting `SpellSharedDocumentation.lua:19–31`).
- DOCS: duration objects excluded from wrapping: "Leave charge duration objects and timing unchanged and
  **nonsecret** under either restriction input" (`cooldown-restriction.md:17`; the SS-P1 list —
  `GetSpellCooldown`, `GetSpellChargeDuration`, `GetSpellCooldownDuration`, LoC pair — "duration objects …
  remain nonsecret", `:69-71`).
- UI: Shadowflare ships `C_Spell.GetSpellCooldown(id)` reading **`isActive` only** in combat — "claimed
  NeverSecret in Forever's API docs" (`shadowflare.md:70,513`); M33kAuras/EverAuras use
  `C_Spell.GetSpellCooldownDuration(id, true)` as a readable object (`everauras-family.md:94`).
- STRING: "Usage: local secrecy = C_Secrets.GetSpellCooldownSecrecy(spellIdentifier)" class — token
  `GetSpellCastSecrecy`/`GetSpellCooldownSecrecy` family present in the binary (`GetSpellCastSecrecy` @53358;
  `ShouldCooldownsBeSecret` @53361 region: count=1) — per-spell cooldown classifier is in the binary.
- SIM (not client): the sim gates charge/cooldown wrapping on the explicit test input `SimState.cooldowns_restricted`
  with **no production combat trigger** (`cooldown-restriction.md:7-8`; `secret-auras.md:54` analogue) — SOURCE,
  not evidence of native triggers.

**Confidence:** annotations + NeverSecret field sets **high** (DOCS + UI agreement); "booleans survive, numbers
wrap in combat" as runtime behaviour **medium** (native per-field probe is listed open, `cooldown-restriction.md:116-118`);
`GetSpellCooldownDuration` returning a *plain* object in combat **medium** (DOCS absence-of-annotation + UI use;
Musca gates with `HasSecretValues()` exactly in case a server hands a secret-origin object).

**Design implication:** in-combat "is X ready" is DOCS-legal via `isEnabled`/`isActive` (+ `isOnGCD`, `maxCharges`) —
add that boolean tier to the engine (ready-dot on icons) while keeping cast-predict for numbers; route all numeric
reads through `Compat.PlainOrNil`; keep `GetSpellCooldownDuration` objects only as widget fuel, never in arithmetic.

**Remaining live probe (in combat, on a known-cooldown spell):**

```lua
/run 1 local id = 3045  -- Rapid Fire (replace per class)
local ci = C_Spell.GetSpellCooldown(id)
local ch = C_Spell.GetSpellCharges(id)
local okD,dur = pcall(C_Spell.GetSpellCooldownDuration, id, true)
local function K(v) return (issecretvalue and issecretvalue(v)) and "SECRET" or tostring(v) end
DEFAULT_CHAT_FRAME:AddMessage(("CDR: en=%s act=%s gcd=%s st=%s dur=%s rate=%s | CHG: mx=%s act=%s cur=%s | DURobj=%s secret=%s | CDsec=%s")
  :format(K(ci and ci.isEnabled),K(ci and ci.isActive),K(ci and ci.isOnGCD),K(ci and ci.startTime),K(ci and ci.duration),K(ci and ci.modRate),
    K(ch and ch.maxCharges),K(ch and ch.isActive),K(ch and ch.currentCharges),
    tostring(okD and dur and dur.GetRemainingDuration and dur:GetRemainingDuration()),
    tostring(okD and dur and dur.HasSecretValues and dur:HasSecretValues()),
    tostring(C_Secrets and C_Secrets.GetSpellCooldownSecrecy and C_Secrets.GetSpellCooldownSecrecy(id))))
```

---

## 3. Item cooldown reads in combat (`C_Item`, `C_Container`, `GetInventoryItemCooldown`)

**Answer:** In the pinned 16001 declarations the three container/item queries carry **no** output-secrecy annotation
at all (only `SecretArguments=AllowedWhenUntainted`) — unlike the `C_Spell` pair — and `GetInventoryItemCooldown(unit,
slot)` is a legacy global present in the binary but absent from the generated docs; runtime plainness of item cooldowns
in combat is therefore *plausible per docs* but unverified → keep the item-cooldown probe.

**Evidence:**

- DOCS (pinned catalog, dumped today): `C_Item.GetItemCooldown @ItemDocumentation.lua:433`
  (`ItemInfo → startTimeSeconds,durationSeconds,enableCooldownTimer`, `SecretArguments=AllowedWhenUntainted`,
  no `SecretWhen*`); `C_Container.GetItemCooldown @ContainerDocumentation.lua:336`
  (`itemID → startTime,duration,enable`, same shape); `C_Container.GetContainerItemCooldown @ContainerDocumentation.lua:121`
  (`bag,slot → startTime,duration,enable`). No `SecretWhenCooldownsRestricted` on any of the three, while
  `C_Spell.GetSpellCooldown` in the same catalog **has** it → the difference is in the shipped data, not sampling.
- `GetInventoryItemCooldown`: **not** in the pinned API catalog (raw scan of all `forever.json`: zero records);
  present in the binary string table (Wow.exe strings — token count 1, usage-string neighbourhood of the item
  globals) and consumed live: UI `local start, dur, enable = GetInventoryItemCooldown("player", slotID)`
  (`…/_forever_/Interface/AddOns/EllesmereUICooldownManager/EUI_CDM_HookTrinkets.lua:307`,
  `EllesmereUICdmFakeActive.lua:48,1202` — trinket slots, in-combat CDM context). SIM registers it as the
  "Legacy … getter" with equipment-slot semantics (`item-cooldowns.md:14,26` SOURCE).
- SIM: item-cooldown return-shape proof incl. `(0,0,true)`/`(0,0,1)` ready values (`item-cooldowns.md:11-15`,
  bounded Retail/Mists GREEN `:38-48`) — SOURCE, shape only; "secret validation … remain pending"
  (`item-cooldowns.md:51`).
- The `ShouldSpellBookItemCooldownBeSecret` / action-level predicates exist (DOCS
  `@SecretPredicateAPIDocumentation.lua:154,:102`), i.e. the book/action *slots* have their own spell-level
  secrecy query; nothing analogous is annotated for the item path.

**Confidence:** annotations **high** (DOCS, dumped today); "plain numbers in combat" **low-medium** (no
counter-evidence, no confirmation; the design doc keeps it as probe #7 for exactly this reason).

**Design implication:** P-A (trinket consumables on the timeline) can prefer the direct read path *conditionally*:
probe first, fall back to cast-predict; do not build the P-A spine on the unproven plainness.

**Remaining live probe:** = design doc probe #7, concretely (combat, trinket on cooldown):

```lua
/run 1 local function K(v) return (issecretvalue and issecretvalue(v)) and "SECRET" or tostring(v) end
for slot=1,16 do
  local s,d,e = GetInventoryItemCooldown("player", slot)
  if (type(s)=="number" and s>0) or (type(d)=="number" and d>0) then
    DEFAULT_CHAT_FRAME:AddMessage(("LEG slot=%d %s/%s/%s"):format(slot,K(s),K(d),K(e)))
  end
end
-- trinkets:
for i=1,2 do local sp,tr,sl = GetInventoryItemCooldown("player", (i==1) and 13 or 14)
  DEFAULT_CHAT_FRAME:AddMessage(("TRINK%d %s / %s / %s"):format(i,K(sp),K(tr),K(sl))) end
local it = C_Item and C_Item.GetItemCooldown
local link = GetInventoryItemLink and GetInventoryItemLink("player",13)
if it and link then local s,d,e = it(link) DEFAULT_CHAT_FRAME:AddMessage(("CITEM %s/%s/%s"):format(K(s),K(d),K(e))) end
```
(Adjust slots to equipped trinkets; compare `K()` outputs: `SECRET` vs `plain`.)

---

## 4. `C_Secrets.GetSpellAuraSecrecy(spellID)` + the NeverSecret aura set — cross-checked against FX data

**Answer:** It classifies a spell from shipped `SpellMisc.Attributes_15` bits → `Enum.SecrecyLevel`
(`NeverSecret=0`/`AlwaysSecret=1`/`ContextuallySecret=2`), callable from tainted code with plain arguments
(`SecretArguments=AllowedWhenUntainted`), reporting **base** secrecy only; exactly 76 spells carry the bits
(68 `AURA_NEVER_SECRET`, 7 `AURA_ALWAYS_SECRET`, 1 dual-flag 1317008 that errors); **the FX corpus (530 class spells +
335 item-proc buff spells + 196 on-use buff spells) has ZERO ID-overlap with the 76** — the only intersections are
name-family (the 76 hold the low-rank row of e.g. Mark of the Wild; FX tracks the top rank, unflagged).

**Evidence (mechanics):**

- DOCS: `C_Secrets.GetSpellAuraSecrecy @SecretPredicateAPIDocumentation.lua:44`, arg `spellIdentifier:SpellIdentifier`,
  returns `SecrethyLevel`, `SecretArguments=AllowedWhenUntainted`; `Enum.SecrethyLevel` =
  `NeverSecret=0, AlwaysSecret=1, ContextuallySecret=2` (`@SecretWrapperConstantsDocumentation.lua:5`, dumped today).
- STRING: "Usage: local secrecy = C_Secrets.GetSpellAuraSecrecy(spellIdentifier)" — Wow.exe strings @53358-59.
- Spec: bits from `SpellMisc.Attributes_15`; "reports **base** secrecy, not whether auras are currently secret in
  combat"; absent entry = "no aura secrecy override, not never-secret"; 76 spells; identity-filter exemption
  (`spell-aura-secrecy.md:3,7,11,15`); dual-flag spell `1317008` (base row 863018) raises an explicit ambiguity
  error (`:34`); provenance json `data/spell_aura_secrecy.provenance.json` referenced at `:17` — **not shipped in
  this repo copy** (checked: absent from the local spec corpus); regeneration pinned to
  `pi-SpellMisc-12.1.0.69497.csv` + `pi-SpellAttributes15.dbdf` (`:19-23`).
- Consumers: "The 22 Retail functions annotated `SecretWhenUnitAuraRestricted`" (`secret-auras.md:33`; I counted
  exactly 22 in the pinned catalog — C_UnitAuras/C_TooltipInfo/C_Spell pairs, incl.
  `C_UnitAuras.GetPlayerAuraBySpellID @UnitAuraDocumentation.lua:396`, `GetAuraDataBySpellName @:244`,
  `GetUnitAuraBySpellID @:455`); the three spell-keyed lookups additionally carry **`RequiresNonSecretAura: true`**
  (pinned records, dumped today) — "define their result for a secret aura. Whether that is nil, an error or a
  secret is UNKNOWN (S8)" (`secret-auras.md:35`); sim policy: "Never-secret spells stay plain; others nil for
  tainted callers (**inferred**)" (`secret-auras.md:56`, SOURCE).
- UI: Musca gates its spell-ID filters on `C_Secrets.GetSpellAuraSecrecy(id) == Enum.SecrecyLevel.NeverSecret`
  (`everauras-family.md:73` — `SecretAuraSingleLearning.lua:20,44` "AllNeverSecret"), because spell-ID aura
  filters "hide these auras in combat" for non-never-secret spells (`:121-125`).

**The 76 (SIM data extraction, `scan_*.raw` — sim table generated from client `SpellMisc` per the spec's own
regeneration pin; treat as client-derived, re-enumerate on day-1):**

`GetSpellAuraSecrecy` scanned over IDs `1..2,500,000`: flagged = **75** (`68 → 0`, `7 → 1`) + the dual-flag
`1317008` (raises; = the 76th, consistent with `spell-aura-secrecy.md:15,34`).

- **NeverSecret (68)** — names via sim `C_Spell.GetSpellName` (nil = not in the sim's name table; day-1 probe
  fills them): 1126 Mark of the Wild, 1459 Arcane Intellect, 2823 Deadly Poison, 3408 ?, 5761 Numbing Poison,
  6673 Battle Shout, 8679 ?, 21562 Prayer of Fortitude, 26013 ?, 57723 ?, 57724 ?, 71041 ?, 80354 ?, 95809 ?,
  124255 ?, 160455 ?, 205473 ?, 206151 ?, 260286 ?, 264689 ?, 308312 ?, 315584 ?, 319773 ?, 319778 ?, 344179 ?,
  369459 Source of Magic, 369968 ?, 377234 ?, 381637 Atrophic Poison, 381664 Amplifying Poison, 381732 ?, 381741 ?,
  381746 ?, 381748 ?, 381749 ?, 381750 ?, 381751 ?, 381752 ?, 381753 ?, 381754 ?, 381756 ?, 381757 ?, 381758 ?,
  382021 Earthliving Weapon, 382022 ?, 388367 ?, 390435 ?, 404464 ?, 404468 ?, 405189 ?, 418590 ?, 427490 ?,
  433568 Rite of Sanctification, 433583 Rite of Adjuration, 447959 Ride Along – Enabled, 447960 Ride Along – Inactive,
  457481 ?, 457496 ?, 462742 ?, 462757 Thunderstrike Ward, 462854 ?, 474754 ?,
  1217607 Void Metamorphosis, 1225789 Dark Heart, 1227702 Silence the Whispers (names for the last three from DOCS
  `constants:UnitPowerSpellIDs@SpellIDDocumentation.lua:13-17`), 1254550 ?, 1283888 ?, 1313593 ?.
- **AlwaysSecret (7)**: 343960 Sin-Stone Bond, 343963 Val'kyr Bond, 440836 Essence of Yu'lon, 440837 Fury of Xuen,
  440838 Fortitude of Niuzao, 440839 Kindness of Chi-Ji (the last four = Bestial-Wrath pet-power auras — relevant to
  Hunter pet UI: never readable, never show them in read-driven logic), 1283894 ?.
- [INFERENCE] The 3817xx/3820xx/38xxxx clusters are talent/reworked-form rows of the named families (classic
  self-buff/poison/shout + new-engine forms).

**Can tainted code call it in combat?** DOCS/STRING say the function is a plain query with public args
(`AllowedWhenUntainted` restricts *passing secrets*, not plain args); the NATIVE-verified helper-surface census
(25 restricted helpers) does **not** include the `C_Secrets` family (`secret-auras.md:96-100`); Musca calls it from
tainted combat code paths (`everauras-family.md:73`). No annotation blocks a tainted plain-arg call in combat.
**Confidence: high.**

**FX cross-check (the highest-value part):**

- Corpus = every spell FX can act on: 530 class rows (all `[id]`/`id=` in
  `addon/Forte_{Deathknight,Druid,Hunter,Mage,Paladin,Priest,Rogue,Shaman,Warlock,Warrior}/Data/*.lua`),
  335 distinct proc-buff IDs + 196 on-use buff IDs (`addon/Forte_Items/Data/Items.lua`, `buffId` fields;
  `ProcsByBuffName` built from the same rows at `Items.lua:1348`). 1,051 distinct IDs.
- `probe_FXAURA` (sim): **all 1,051 → `2` (ContextuallySecret)**; zero `0`, zero `1`, zero `nil`.
  **ID-level overlap with the NeverSecret set = NONE.**
- Name-level scan of all `Forte_*/**/*.lua` against the 76 resolved names: the only hits are
  the *same spell family, different rank row*: Mage `"Arcane Intellect"` id **10157** (Rank 5) vs flagged 1459;
  Priest `"Prayer of Fortitude"` **21564** (Rank 2) vs 21562; Druid `"Mark of the Wild"` **9885** (Rank 7) vs 1126;
  Rogue `"Deadly Poison V"` **25349** vs 2823, `"Numbing Poison"` **439472** (Forever rework row) vs 5761,
  `"Atrophic Poison"` **439473** vs 381637; Warrior `"Battle Shout"` **25289** (Rank 7) vs 6673;
  Warlock `"Metamorphosis"` 403789 / item `"Rune of Metamorphosis"` — no flag on those rows.
  (`Forte_Mage/Data/Mage.lua`, `Forte_Priest/Data/Priest.lua`, `Forte_Druid/Data/Druid.lua`,
  `Forte_Rogue/Data/Rogue.lua`, `Forte_Warrior/Data/Warrior.lua`, rows quoted today.)
- Name-keyed query in the sim: `GetSpellAuraSecrecy("Mark of the Wild") → 0` while
  `GetSpellAuraSecrecy(9885) → 2`; `("Battle Shout") → 2` (resolves to an unflagged rank row);
  `("Deadly Poison V") → nil` (not in the sim name table); nonsense `999999999 → 2`, `("Zzz Not A Spell") → nil`
  (`probe_q4`, SIM). So **the flag is per spell row**; name resolution lands on some modelled row of the family —
  the rank a flag sits on is *not* the rank FX tracks.
- Item procs specifically: all 335 proc buff rows (incl. the 405-proc list head 18833 "Firebolt", 1300783
  "Slaughter", 16928 "Armor Shatter" …) → 2: **none of the 405 item/enchant procs is aura-readable in combat**.
  Corollary (consistent with design-combat-procs §2): proc windows = out-of-combat read + in-combat
  container-gate / AddAuraSound channels only.

**Confidence:** function semantics + 76 mechanism **high**; the concrete 76 list **medium** (client-derived data
pinned at `12.1.0.69497`; shipped client is `1.60.1.704xx` — re-enumerate day-1); "no FX overlap" **high for today's
data pins** (IDs are the authoritative key; re-check after every data regen); "a NeverSecret spell's aura is
readable via `GetPlayerAuraBySpellID` in combat" — **the** open one (S8 + RequiresNonSecretAura enforcement
"unknown" `powerauras-classicprocauras.md:330`), medium.

**Design implication:** day-1, classify every tracked aura ID with one `GetSpellAuraSecrecy` sweep (out of
combat, cache in SavedVariables keyed by data build-pin) — any hit becomes a **priority in-combat read channel**
(plain `GetPlayerAuraBySpellID`, no container needed). For FX's current data: no hits ⇒ the container-gate +
AddAuraSound plan stays primary. Also: the 76 list contains a **pet-power AlwaysSecret core** — never build pet-buff
logic on reads; and a pool of NeverSecret classic self-buffs (Mark of the Wild, Arcane Intellect, Battle Shout,
Prayer of Fortitude, Earthliving Weapon, poisons) — if FX ever tracks *rank-1* forms (or if day-1 shows the flag
follows the applied rank), those become the first free in-combat aura reads (buff-uptime gates, out-of-combat
aspect reminders validated in combat).

**Remaining live probe (the day-1 aura sweep):**

```lua
/run 1 local lvl,never,always,names = {},{},0,{}
local function probeOne(id,name)
  local ok,sec = pcall(C_Secrets.GetSpellAuraSecrecy, id)
  local nm = (C_Spell and C_Spell.GetSpellName) and C_Spell.GetSpellName(id) or "?"
  if ok and sec==Enum.SecrecyLevel.NeverSecret then
    never[#never+1]=("%d=%s"):format(id,tostring(nm)); names[id]=nm
  elseif ok and sec==Enum.SecrecyLevel.AlwaysSecret then always=always+1 end
end
for _,id in ipairs({1126,1459,2823,5761,6673,21562,369459,381637,381664,382021,433568,433583,447959,447960,462757,1217607,1225789,1227702,1317008}) do probeOne(id) end
DEFAULT_CHAT_FRAME:AddMessage(("AURASEC never=[%s] alwaysCount=%d"):format(table.concat(never,","),always))
-- functional half: out of combat apply the RANK-1 buff, then IN COMBAT:
local a = C_UnitAuras.GetPlayerAuraBySpellID(1126)  -- MotW R1 id (swap per family)
DEFAULT_CHAT_FRAME:AddMessage(("AURA1126=%s exp=%s"):format(tostring(a),
  tostring(a and a.expirationTime and ((issecretvalue and issecretvalue(a.expirationTime)) and "SECRET" or a.expirationTime))))
-- also probe the rank actually cast (e.g. 9885) and the spell-name lookup:
DEFAULT_CHAT_FRAME:AddMessage(("AURA9885=%s BYNAME=%s"):format(tostring(C_UnitAuras.GetPlayerAuraBySpellID(9885)),
  tostring(C_UnitAuras.GetAuraDataBySpellName("player","Mark of the Wild","HELPFUL"))))
```
Repeat the functional half in a rated BG / M+ to cover all restriction states. Day-1 full sweep: feed every
`Forte_*/Data/*.lua` + `Items.lua` ID (list is in `ForteXorcist.Data`) through `probeOne` and print hits.

---

## 5. "Are reads secret right now?" — cheap mode queries

**Answer:** Yes: `C_RestrictedActions.GetAddOnRestrictionState(type)`/`IsAddOnRestrictionActive(type)` over the
six `AddOnRestrictionType` {Combat=0, Encounter=1, ChallengeMode=2, PvPMatch=3, Map=4, Chat=5} states
(`Inactive/Activating/Active`), plus the zero-arg `C_Secrets.Should{Auras,Cooldowns}BeSecret()` /
`HasSecretRestrictions()` predicates, plus the `ADDON_RESTRICTION_STATE_CHANGED(type, state)` event — so the
engine can switch modes on one query/one event, not per-value probing.

**Evidence:**

- DOCS (pinned catalog): whole `C_Secrets` surface exists on Forever (`@SecretPredicateAPIDocumentation.lua:11-414`,
  27 functions (29 records incl. the two enums) incl. `HasSecretRestrictions :92`, `ShouldAurasBeSecret :118`, `ShouldCooldownsBeSecret :128`,
  `ShouldActionCooldownBeSecret :102`, `ShouldSpellCooldownBeSecret :171`, `ShouldSpellBookItemCooldownBeSecret :154`);
  `C_RestrictedActions.GetAddOnRestrictionState @RestrictedActionsDocumentation.lua:28`,
  `IsAddOnRestrictionActive @:54` (both `SecretArguments=AllowedWhenUntainted`, env `All`);
  `AddOnRestrictionState {Inactive,Activating,Active} @RestrictedActionsConstantsDocumentation.lua:5`,
  `AddOnRestrictionType {Combat,Encounter,ChallengeMode,PvPMatch,Map,Chat} @:18`.
- **NATIVE** (clean-room, builds incl. **Forever 70707**): "`GetAddOnRestrictionState(type)` returns one byte of a
  per-type state array, and `IsAddOnRestrictionActive(type)` is `state[type]==2`" — **VERIFIED**
  (`secret-auras.md:96-102` → `native-evidence-70688/secrets/S13-restriction-surface-summary.md`;
  `restricted-actions-state.md:17` records the same as verified structure).
- STRING: usage strings "local state = C_RestrictedActions.GetAddOnRestrictionState(type)" (Wow.exe @53107-08);
  the six `addon*RestrictionsForced` cvar help lines @68660-68677 (names the guard states verbatim:
  "combat", "active encounters", "challenge mode and mythic plus status", "PvP match state", "current map type",
  "in lockdown"); RTTI for a `function(AddOnRestrictionType, AddOnRestrictionState)` callback @68677.
- STRING/spec: "the client's help text names its guard states as combat, lockdown, active encounter,
  challenge mode / Mythic+, current map type and PvP match state, and frames the outcome as
  '**restricted, or may return secrets**'" (`secret-auras.md:22`); "The exact inputs, and whether the state is
  per unit, per aura or global, are UNKNOWN (S1)" (`:22`).
- Event: `ADDON_RESTRICTION_STATE_CHANGED(type, state)` declared synchronous, "predicate false inside the event"
  ordering is sim-side best-guess (`restricted-actions-state.md:8,17`); Musca/EverAuras watch the event live
  (`everauras-family.md:145`).
- UI: PowerAuras gates aura reads on `C_Secrets.ShouldAurasBeSecret` ("are aura reads going to be secret right
  now" gate → `nil`/unknown in combat) (`powerauras-classicprocauras.md:69,146`).
- STRING: restriction message "Auras cannot be accessed when secret while tainted by '%s'" sits beside
  `UIUtil\SecretPredicates.cpp` (Wow.exe @73398) — the guard is the SecretPredicates module.
- SIM (not client): `C_RestrictedActions`/most predicates unregistered in sim v0.1.39 (`probe_surfa`:
  `CR:*=false`; only `GetSpellAuraSecrecy` present) → sim cannot host this probe; STRING/NATIVE above are the evidence.

**Confidence:** presence + per-type byte semantics **high** (NATIVE on 70707 + DOCS + STRING); "these six states
are what the SecretWhen* families consult" **medium** (help-text framing + one family per cvar name; spec marks the
predicate→category wiring unverified, `secret-auras.md:104-106`, `restricted-actions-state.md:26`); per-unit
granularity of cast events **unknown**.

**Design implication:** implement a `ForteXorcist.SecretState` mode switch: on `ADDON_RESTRICTION_STATE_CHANGED`
(plus `PLAYER_REGEN_ENABLED/DISABLED` as belt) recompute `restricted = any(IsAddOnRestrictionActive(0..5))` +
`ShouldAurasBeSecret()`/`ShouldCooldownsBeSecret()` (all zero-arg/cheap) and flip the read tier
(plain-reads vs predict-only) in one place; gate all *registrations* (AddAuraSound, container slots) on the same
state. This replaces per-value `PlainOrNil` probing with one cached mode (PlainOrNil stays as the field-level guard).

**Remaining live probe:** day-1 `/fx status` extension (design doc probe #1) prints, in each state,
`IsAddOnRestrictionActive(0..5)`, `ShouldAurasBeSecret()`, `ShouldCooldownsBeSecret()`, `HasSecretRestrictions()`
and logs every `ADDON_RESTRICTION_STATE_CHANGED` payload — confirming the event fires live and the modes track
combat entry/encounter start.

```lua
/run 1 local f=CreateFrame("Frame") f:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
f:SetScript("OnEvent",function(_,e,t,s) DEFAULT_CHAT_FRAME:AddMessage(("ARSC type=%s state=%s"):format(tostring(t),tostring(s))) end)
DEFAULT_CHAT_FRAME:AddMessage(("SECQ ars=%s/%s/%s/%s/%s/%s abs=%s cbs=%s hsr=%s")
 :format(tostring(C_RestrictedActions.IsAddOnRestrictionActive(0)),tostring(C_RestrictedActions.IsAddOnRestrictionActive(1)),
  tostring(C_RestrictedActions.IsAddOnRestrictionActive(2)),tostring(C_RestrictedActions.IsAddOnRestrictionActive(3)),
  tostring(C_RestrictedActions.IsAddOnRestrictionActive(4)),tostring(C_RestrictedActions.IsAddOnRestrictionActive(5)),
  tostring(C_Secrets.ShouldAurasBeSecret()),tostring(C_Secrets.ShouldCooldownsBeSecret()),tostring(C_Secrets.HasSecretRestrictions())))
```

---

## 6. `PLAYER_SWING` / `PLAYER_SWING_RANGE_UPDATE`

**Answer:** Present on the 16001 surface as the `C_SwingTimer` system: `PLAYER_SWING(swingDuration, swingType)` and
`PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange)` (DOCS, env `All`, **no secrecy annotations**);
`C_SwingTimer.EnableRangeCheck(swingType, enable)` / `IsTargetWithinSwingRange(swingType)`; `swingType` =
`PlayerSwingType` (melee/ranged); a shipped addon consumes exactly these payloads on this client.

**Evidence:**

- DOCS (pinned catalog): `event PLAYER_SWING @SwingTimerDocumentation.lua:42` payload
  `(swingDuration:number, swingType:PlayerSwingType)`, `SynchronousEvent`; `event PLAYER_SWING_RANGE_UPDATE
  @SwingTimerDocumentation.lua:53` payload `(swingType, isInRange:bool, checksRange:bool)`;
  `C_SwingTimer.EnableRangeCheck @:10`, `C_SwingTimer.IsTargetWithinSwingRange @:22 → bool`.
- STRING: `PLAYER_SWING_RANGE_UPDATE` and `PLAYER_SWING` adjacent in the binary event-name table (Wow.exe
  @37513-14, between `TALKINGHEAD_CLOSE` and `SPELL_UPDATE_USES`); `C_SwingTimer` + usage strings for
  `IsTargetWithinSwingRange`/`EnableRangeCheck` + `PlayerSwingType`/`PlayerSwingTypeMeta` (@54546-49).
- UI (installed client, `## Interface: …, 16001`): `EllesmereUIResourceBars/EUI_ResourceBars_SwingTimer.lua`
  registers both events (`:1467-68`), dispatches on them (`:1376,1433`) and documents the payload verbatim:
  "PLAYER_SWING(swingDuration, swingType) -- one per player swing",
  "PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange)" (`:8,:10`), then drives its swing bar with
  `C_DurationUtil` durations + `SetTimerDuration` (`:25-26,:689`).
- Secrecy: no `SecretWhen*` on any swing record; swing data is own-player data; no counter-evidence anywhere.
- SIM (not client): no `C_SwingTimer` namespace in v0.1.39 (`probe_surfa: SITWSR=nil`); `RegisterEvent("PLAYER_SWING")`
  accepted (unknown events register silently) — sim presence ≠ evidence.

**Confidence:** **high** (three independent labels; live consumer on the target client).

**Design implication:** Phase 3 auto-shot/swing timer uses `PLAYER_SWING` as the tick source (payload carries the
*next* swing duration → drive a self-built duration object); dead-zone light via `PLAYER_SWING_RANGE_UPDATE` +
`C_SwingTimer.IsTargetWithinSwingRange`; register `EnableRangeCheck` for the swing type while the widget is shown.

**Remaining live probe:** confirm `swingType` enumeration values + payload signs on the client (and ranged swing
presence for Hunter):

```lua
/run 1 local f=CreateFrame("Frame") f:RegisterEvent("PLAYER_SWING") f:RegisterEvent("PLAYER_SWING_RANGE_UPDATE")
f:SetScript("OnEvent",function(_,e,a,b,c) DEFAULT_CHAT_FRAME:AddMessage(("SWING %s a=%s b=%s c=%s enum=%s")
  :format(e,tostring(a),tostring(b),tostring(c),tostring(Enum and Enum.PlayerSwingType))) end)
if C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange then
  DEFAULT_CHAT_FRAME:AddMessage("SITWS="..tostring(C_SwingTimer.IsTargetWithinSwingRange(0)))
end
```

---

## 7. Duration objects from own plain numbers → own widgets

**Answer:** Tainted code may construct a duration object (`C_DurationUtil.CreateDuration()`), fill it from plain
numbers (`SetTimeFromStart(start, duration, [rate])`), and feed it to its own `StatusBar:SetTimerDuration(d,
interpolation, direction)` / `Cooldown:SetCooldownFromDurationObject(d, [clearIfZero])` — every one of those is
annotated `SecretArguments = "AllowedWhenUntainted"` (restricts *secret* arguments only; plain args are legal
from tainted callers), the two widget methods have no `SecretWhen*` on their *outputs*, and the design-combat-procs
probe list (#5) keeps live confirmation open because the widgets' tick behaviour with addon-made objects has
never been seen on a live client.

**Evidence:**

- DOCS (pinned catalog): `C_DurationUtil.CreateDuration @DurationUtilDocumentation.lua:10`,
  `CreateManualClock @:30`, `CreateDurationTextBinding @:20`;
  `FrameAPICooldown:SetCooldownFromDurationObject(duration:LuaDurationObject, clearIfZero:bool)
  @FrameAPICooldownDocumentation.lua:307` (`SecretArguments=AllowedWhenUntainted`);
  `SimpleStatusBarAPI:SetTimerDuration(duration, interpolation:StatusBarInterpolation,
  direction:StatusBarTimerDirection) @SimpleStatusBarAPIDocumentation.lua:333` (same mode).
- DOCS-via-spec: "Forever's cached `LuaDurationObjectAPIDocumentation.lua` declares the **three timing setters** as
  `SecretArguments = "AllowedWhenUntainted"`" and `HasSecretValues` is non-secret metadata, `SetToDefaults` clears
  secret state (`duration-core.md:27`); shipped `Blizzard_AuraButton.lua:167-169` passes `secretwrap(...)` into those
  setters (UI, quoted `:27`; also `aura-secret-display.md:5` — "Retail 12.1+ **and Forever** native
  Blizzard_AuraButton.lua feed wrapped timing values into duration objects"); duration objects are the one value
  type the restriction machinery deliberately leaves non-secret (`cooldown-restriction.md:17`).
- Guard direction: widgets *reject* secret-origin inputs from tainted code "before mutating widgets"
  (`aura-secret-display.md:13`) — i.e. the rejection is about *secret* provenance, not addon-made plain objects.
- UI: Musca ships the self-built path today: `C_DurationUtil.CreateDuration()` + `SetTimeFromStart(start,dur)`
  feeding its follow-frame (`everauras-family.md:279-281`, `SecretAuraSingleFollow.lua:186-190`); the same report
  flags the complement: "a bar driven by numbers **we computed ourselves** will freeze in combat — only
  engine-sourced objects tick" (`:283-285`) — i.e. *plain numbers* (no duration object) are the dead path,
  `CreateDuration` is the sanctioned one; EllesmereUI drives `SetTimerDuration` with its own
  `C_DurationUtil` durations on the client (`EUI_ResourceBars_SwingTimer.lua:689,843,866,892`).
- SIM (my run today): from a tainted `--exec-lua` context, `CreateDuration()` → `SetTimeFromStart(GetTime(),30000,1)`
  → `StatusBar:SetTimerDuration(d,0,0)` ok, `Cooldown:SetCooldownFromDurationObject(d)` ok,
  `d:GetRemainingDuration()` counted down (29999.99) — `probe_surfa: durfeed=true/nil,true..nil`
  (SOURCE: proves the call-path is unrestricted in the sim's model, not on the client).
- Gate idiom from the field: Musca gates with `Painter.CanDrawDurationObject` +
  `durationObject:HasSecretValues()` before feeding (`everauras-family.md:282-284`).

**Confidence:** permissibility of construction/feed **high** (DOCS + UI shipping it); that a self-built object
*animates* (not just "is accepted") in combat on the live client **medium** (Musca ships it ⇒ de-facto yes for
out-of-combat; the combat-tick claim is design-doc probe #5, "never proven by us").

**Design implication:** the timeline can migrate from manual SetValue loops to engine-ticked duration objects
(`SetTimerDuration`/`SetCooldownFromDurationObject`) fed by cast-predict start/durations — engine keeps animating
while FX is blind; keep the `HasSecretValues()` gate on every object entering a widget (never FX-built objects
carry secrets, but defensive parity with Musca's idiom); no plain-number-only bar in combat.

**Remaining live probe:** = design doc probe #5 verbatim, in combat:

```lua
/run 1 local d = C_DurationUtil.CreateDuration() d:SetTimeFromStart(GetTime(), 10000, 1)
local sb = CreateFrame("StatusBar", "FXProbeBar", UIParent)
sb:SetSize(200,12); sb:SetPoint("CENTER"); sb:SetStatusBarColor(0,1,0,1); sb:Show()
sb:SetTimerDuration(d, 0, 0)
local cd = CreateFrame("Cooldown", "FXProbeCd", UIParent) cd:SetSize(40,40) cd:SetPoint("CENTER",sb,"RIGHT",8) cd:Show()
cd:SetCooldownFromDurationObject(d)
DEFAULT_CHAT_FRAME:AddMessage(("FXDUR rem=%s secret=%s"):format(tostring(d:GetRemainingDuration()),
  tostring(d:HasSecretValues())))
-- then: does the green bar shrink and the cooldown swipe spin while IN COMBAT? (visual)
```

---

## 8. `C_UnitAuras.AddAuraSound` + `CustomAuraContainerTemplate`/`AuraContainer` on Forever

**Answer:** Both present on the shipped 16001 surface and shipped-in-use on this exact client (installed EllesmereUI
creates `CreateFrame("AuraContainer", …, "CustomAuraContainerTemplate")` after `C_AddOns.LoadAddOn("Blizzard_AuraContainer")`;
Musca/EverAuras/PowerAuras/CPA ship gate containers and sound registrations). `AddAuraSound` carries
`HasRestrictions: true` (+ `SecretArguments=AllowedWhenUntainted`); the patch-API prose limits its restriction to
encounter/M+/PvP — i.e. **registration in ordinary combat is allowed, in locked-down contexts it is not**; container
*slot* registration is the same class of call and all shipping addons do it out of combat (practice rule,
PA: "A container can only be set up outside a fight").

**Evidence:**

- DOCS (pinned catalog): `C_UnitAuras.AddAuraSound(trigger:UnitAuraSoundTrigger, sound:UnitAuraSoundInfo)
  → auraSoundID @UnitAuraDocumentation.lua:10`, annotations `HasRestrictions=true, SecretArguments=AllowedWhenUntainted`.
- DOCS-via-spec: patch-API `12.0.5-api-changes.txt:168` — "The source limits restrictions to **encounters/M+/PvP
  matches**"; model line: "Public arguments under actual addon taint register outside encounter/M+/PvP,
  **including ordinary combat**"; "Any active context denies an insecure caller … consume no ID"
  (`private-aura-sound-add-context.md:3,19,21` — the model is INFERRED from that prose; PvP flag has no runtime
  writer in the sim, `:66`).
- STRING: `AddAuraSound` in the binary (token count 2, usage-string region of `C_UnitAuras`).
- UI (installed client): `EllesmereUI/EllesmereUI_AuraKit.lua:1608-1622`:
  `C_AddOns.LoadAddOn("Blizzard_AuraContainer")` → `CreateFrame("AuraContainer", nil, parent,
  "CustomAuraContainerTemplate")` → `SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.ProcessAura, …)`;
  also `EUI_UnitFrames_AuraContainers.lua:2157`, `EUI_RaidFrames_Layout.lua:85,124` (raids' own aura
  containers). DOCS: `C_AuraContainerUtil` "publishes … to Retail 12.1+ **and Forever**"
  (`aura-container-options.md:3-5`; "Pinned Forever documentation also declares
  `ProcessCustomAuraButtonCasterNameOptions`", `:75`).
- UI (analysed addons): CPA: registration accepts **any plain spell-ID set** —
  `container:AddAuraSlot(name, filter, {candidateFilters={includeSpellIDs=ids}}})` (CPA Core.lua:212-217), rendering
  runs untainted and "keeps working while auras are secret"; **in-combat registration changes are off-limits** —
  containers built/rebuilt out of combat (`powerauras-classicprocauras.md:216-235`; "A container can only be set up
  outside a fight" PA :209-210; `InCombatLockdown()` init guard Core.lua:179); "NO direct evidence exists that an
  **item-source** aura renders" (`:236-239` [INFERENCE-flagged there too]).
- `AddAuraSound` live in combat: Musca/EverAuras ship it as the zero-read proc alert,
  `AddAuraSound(Enum.UnitAuraSoundTrigger.Added/.Removed/.ApplicationsIncreased, {unitToken, spellID,
  soundFileName/soundFileID, outputChannel, throttleSeconds}) → soundID` (`everauras-family.md:100-101,309-310`
  "works in combat"); EverAuras PoC-verified `UpdateAllAuras` inbound delegates in combat (`:396`).
- SIM (v0.1.39): `C_UnitAuras.AddAuraSound` **unregistered** (`probe_surfa: CUA.AAS=false`);
  `CreateFrame(…,"CustomAuraContainerTemplate")` **crashes the sim** (probe_cap: hard exit, no lua-errors JSON) —
  the sim cannot host Q8 at all; all presence evidence above is DOCS/STRING/UI.

**Confidence:** presence **high**; ordinary-combat registration permissibility **medium** (DOCS prose scope +
INFERRED model; the shipping addons' own policy is out-of-combat-only registration, which is compatible with
*either* answer — it is a safety convention, not proof of enforcement); encounter/M+/PvP blackout windows
**medium**; item-source container rendering **low-medium** (explicitly unverified in the report).

**Design implication:** (a) FX registers all proc gates (containers, sounds) out of combat and rebuilds on
`PLAYER_REGEN_ENABLED` (matches design doc P-C); (b) in encounter/M+/PvP, treat AddAuraSound/AddAuraSlot
registration calls as forbidden (queue to next out-of-combat rebuild) — the annotation `HasRestrictions` makes a
runtime "denied" plausible; (c) keep `AddAuraSound` as the zero-read proc-alert channel for chosen procs;
(d) the item-proc container render is *the* gate experiment on day-1 (probe #3 of the design doc).

**Remaining live probe:** = design doc probes #3/#4:

```lua
/run 1 local out = {}
out[1] = "load="..tostring(C_AddOns.LoadAddOn("Blizzard_AuraContainer"))
local ok, c = pcall(CreateFrame, "AuraContainer", "FXGateProbe", UIParent, "CustomAuraContainerTemplate")
out[2] = "frame="..tostring(ok and c)
if ok and c then
  local okP = pcall(c.SetAuraProcessingPolicy, c, CustomAuraContainerAuraProcessingPolicy.None)
  local okS = pcall(c.AddAuraSlot, c, "FXSlot", "HELPFUL;player", { candidateFilters = { includeSpellIDs = { 16928 } } }) -- Armor Shatter proc (item-sourced)
  pcall(c.SetUnit, c, "player"); c:Show()
  out[3] = "policy="..tostring(okP).." slot="..tostring(okS)
end
DEFAULT_CHAT_FRAME:AddMessage("FXGATE "..table.concat(out," | "))
-- then: does the (hidden) gate show/expire when the proc is up IN COMBAT? Poll presence via
-- c:GetFrameRegion() / a shown CustomAuraButton child, never via aura reads.
-- Sound half (OUT of combat first, then try in combat to test the blackout):
local okSnd, sndID = pcall(C_UnitAuras.AddAuraSound, Enum.UnitAuraSoundTrigger.Added,
  {unitToken="player", spellID=16928, soundFileID=8129, outputChannel=2})
DEFAULT_CHAT_FRAME:AddMessage("FXSND ok=%s id=%s"):format(tostring(okSnd), tostring(sndID))
```

---

## 9. Load-on-demand on Forever (`C_AddOns.LoadAddOn`, `IsAddOnLoadOnDemand`, `## LoadOnDemand`)

**Answer:** The full LoD system ships on 16001 (TOC directive + `C_AddOns.LoadAddOn/IsAddOnLoadOnDemand/IsAddOnLoaded`
+ binary loader strings), LoD addons are metadata-only at login and *nothing of them is parsed* until an explicit
load — shipped addons use exactly FX's planned pattern (`## LoadOnDemand: 1` per-class data slots loaded at
login by a core addon, e.g. Polestar's 13 data addons, EllesmereUI's options/locales slots); so `Forte_Core` can
ship each class data addon LoD and load only the player's class at `PLAYER_LOGIN` — with the caveats that its
`ADDON_LOADED` fires on the load (payload `(addOnName, containsBindings)`), its SavedVariables arrive *with the
load* in the real client (a documented SIM-only gap), and module-registry/options re-registration must be re-run
after the load (FX design already requires this).

**Evidence:**

- STRING: TOC directive table includes `LoadOnDemand:` (with `UseSecureEnvironment:`, `LoadFirst:`, `AllowLoad:`,
  `SavedVariables:`, `SavedVariablesPerCharacter:`, `RequiredDep`, `LoadManagers:`, `LoadWith:`) — Wow.exe
  @73055-67; loader error strings "AddOn %s has cyclic dependency involving %s",
  "**] uses [Bootstrap] files but is not LoadOnDemand; [Bootstrap] will be ignored.**" @73050;
  "Usage: local loadOnDemand = C_AddOns.IsAddOnLoadOnDemand(name)", `IsAddOnLoadable(name [, character,
  demandLoaded])`, `IsAddOnLoaded(name) → loadedOrLoading, loaded` @39648-63.
- DOCS: `C_AddOns.LoadAddOn(name) → loaded, value @AddOnsDocumentation.lua:346`,
  `IsAddOnLoadOnDemand(name) → bool @:288`, `IsAddOnLoaded @:321`, `IsAddOnLoadable @:303`,
  event `ADDON_LOADED(addOnName:cstring, containsBindings:bool) @:388` (all env `All`).
- UI (installed client): `## LoadOnDemand: 1` in 24 shipped TOCs (`Polestar_*` guides/itemdb/names,
  `EllesmereUIOptions/EllesmereUIOptions.toc:9`, `EllesmereUILocales/EllesmereUILocales.toc:9`;
  `SilverDragon.toc:18` shows `: 0`); runtime loads: `C_AddOns.LoadAddOn("EllesmereUILocales")`
  (`EllesmereUI/EllesmereUI_Locale.lua:210`), `"Blizzard_AuraContainer"` (`AuraKit.lua:1608`),
  `"Blizzard_AuctionHouseUI"` (`EllesmereUIQoL.lua:1019`); design intent verbatim: "LoadOnDemand
  EllesmereUIOptions addon: **nothing of it is even PARSED** until" (`EllesmereUI.lua:3128`),
  "the LoadOnDemand split's **login win** evaporates" (`:3154`), and `ADDON_LOADED`-driven re-registration
  (`EllesmereUI_Locale.lua:188`, `EllesmereUI.lua:3166-3170`).
- SIM: LoD metadata registered at startup, files unexecuted, `IsAddOnLoaded=false` until explicit load, one-time
  execution, bootstrap file rules, `ADDON_LOADED` delivery only for full loads
  (`addon-lod-metadata.md:8,36`; `addon-bootstrap-loading.md:10,23`); sim's LoD load path lacks the SavedVariables
  persistence manager (`saved-variables.md:50` — **sim limitation**, not a client fact).
- `## Bootstrap` interplay exists on the client (`[Bootstrap]` loader string above + TOC annotation parser,
  `addon-bootstrap-loading.md:8-9` quotes the real Forever line `TargetFrameAuraContainer.lua … [AllowLoadGameType
  mainline] [LoadIntoEnvironment secure]` — the directive set is live in Forever's own shipped TOCs).

**Confidence:** surface + semantics **high** (STRING+DOCS+UI; three LoD users on the box); "FX's split works
end-to-end (class module re-registers cleanly mid-session)" **medium** (FX-specific; sim can prove the load, the
client can prove the login win; §10.4 battery).

**Design implication:** split each `Forte_<Class>` data addon into `## LoadOnDemand: 1` (+
`## RequiredDep: Forte_Core`), Forte_Core loads `C_AddOns.LoadAddOn("Forte_"..class)` on `PLAYER_LOGIN`
(`GetNumSaveableClasses/UnitClass("player")` pattern; the class→addon name map is static), gates module
registration on that addon's `ADDON_LOADED`; `/fx class <name>` loads others on demand; measure login-time win
(Ellesmere's "login win" comment is the yardstick).

**Remaining live probe (client, day-1):**

```lua
/run 1 local f=CreateFrame("Frame") f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent",function(_,e,n,b) DEFAULT_CHAT_FRAME:AddMessage(("ADDONLOADED %s bindings=%s"):format(tostring(n),tostring(b))) end)
DEFAULT_CHAT_FRAME:AddMessage(("FXLOD lod=%s loaded=%s load=%s,%s"):format(
  tostring(C_AddOns.IsAddOnLoadOnDemand("Forte_Hunter")), tostring((C_AddOns.IsAddOnLoaded("Forte_Hunter"))),
  tostring(C_AddOns.LoadAddOn("Forte_Hunter")):match("^(%a+)"), tostring((select(2,C_AddOns.LoadAddOn("Forte_Hunter"))))))
DEFAULT_CHAT_FRAME:AddMessage(("FXDATA=%s"):format(tostring(rawget(_G,"ForteXorcist") and ForteXorcist.Data and ForteXorcist.Data.Hunter ~= nil)))
```
(Expected: `lod=true`, `loaded=false`, second `load=true`, `ADDON_LOADED Forte_Hunter`, `FXDATA=true`
after the load — plus in WTF: that ForteXorcist's SavedVariables are complete for the late-loaded addon.)

---

## 10. SavedVariables write timing + `## SavedVariablesPerCharacter`

**Answer:** The directive is shipped (binary TOC-directive table; live consumer on the box: EllesmereUIChat
declares `## SavedVariablesPerCharacter: EllesmereUIChatScrollDB`); write timing on Forever is *inferred, not
measured*: the research best guess is `PLAYER_LEAVING_WORLD → PLAYER_LOGOUT → ADDONS_UNLOADING(closingClient)`
then serialization, per-addon files (account `<addon>.lua`, character `<realm>/<character>/<addon>.lua`) — so FX
must own its writes (save on `PLAYER_LOGOUT`/`ADDONS_UNLOADING`) and never rely on a hidden engine flush for the
learned-durations DB.

**Evidence:**

- STRING: TOC directive list contains `SavedVariablesMachine:`, `SavedVariables:`, `SavedVariablesPerCharacter:`
  (Wow.exe @73061-67).
- UI: `EllesmereUIChat/EllesmereUIChat.toc:9-10` — `## SavedVariables: EllesmereUIChatDB` +
  `## SavedVariablesPerCharacter: EllesmereUIChatScrollDB` (installed, `## Interface: …,16001`);
  `EllesmereUIResourceBars.toc:9` (`SavedVariables:`); session-history note "SavedVariablesPerCharacter"
  (`EllesmereUIChat.lua:161`).
- Spec (Forever-specific inference, explicitly "not measured"): "For Forever, the researched best guess is
  conditional argless `PLAYER_LEAVING_WORLD`, argless `PLAYER_LOGOUT`, then `ADDONS_UNLOADING(closingClient)`
  before serialization; proposed `closingClient` is true for normal close/Quit and false for ReloadUI. **This is
  not implemented general shutdown behavior or measured native order**"
  (`saved-variables-native-evidence.md:17-20`; consumer-stakes paragraph `:27-30` — saving earlier changes
  persisted data (AceDB); `:32-38` data-shape facts: explicit nils are meaningful, shared tables reload as copies,
  cycles may not survive).
- Spec (sim persistence model, SOURCE): per-scope file layout and serializer limits
  (`saved-variables.md:16-24,40-52`); ReloadUI saves before retiring the VM (`saved-variables.md:6-8`).
- No NATIVE trace for Forever shutdown order exists (recorded as such — `saved-variables-native-evidence.md:3-6`
  "no new native-client execution"; the aso clean-room route unavailable).

**Confidence:** directive presence **high**; per-character file layout **high** (UI + documented account/character
scopes, `saved-variables.md:18-21`); event order / "engine flushes at logout" on Forever **low-medium** (labelled
best guess) → day-1 probe.

**Design implication:** declare the character-split in the TOCs now (learned-durations DB is per-character by
nature: `## SavedVariables: ForteXorcistDB`, `## SavedVariablesPerCharacter: ForteXorcistLearnedDB`); add FX's
own save on `ADDONS_UNLOADING` + `PLAYER_LOGOUT` (cheap `C_AddOns`-independent table write via assignment — the
engine serializes the global), and a `/fx save` escape; keep the learned DB acyclic, metatable-free, depth<128
(`saved-variables.md:46-52`); do not store functions/userdata in SavedVariables globals.

**Remaining live probe (day-1):** stamp on logout, verify on next login:

TOC (declare in `Forte_Probe.toc`): `## SavedVariablesPerCharacter: ForteXorcistProbeDB`

```lua
/run 1 local f=CreateFrame("Frame")
for _,e in {"PLAYER_LEAVING_WORLD","PLAYER_LOGOUT","ADDONS_UNLOADING"} do f:RegisterEvent(e) end
f:SetScript("OnEvent",function(_,e,closing) ForteXorcistProbe = ForteXorcistProbe or {}
  ForteXorcistProbe.fired = (ForteXorcistProbe.fired or "") .. e .. "(" .. tostring(closing) .. "),";
  ForteXorcistProbe.seen = (ForteXorcistProbe.seen or 0) + 1 end)
-- normal Quit to desktop → relogin: print ForteXorcistProbe.fired ; then ReloadUI: compare the
-- closingClient arg (nil/true/false) and that a ReloadUI-saved file carries the pre-reload state.
```

---

## Summary table

| # | Question (short) | Answer (short) | Confidence | Live probe needed |
|---|---|---|---|---|
| 1 | Own-cast SUCCEEDED payload secrecy | Annotated event-wide; `castBarID` NeverSecret; player casts always delivered; field-wrap in combat = field probe | high (shape) / — (runtime) | **y** |
| 2 | Spell cooldown/charge secrecy | `SecretWhenCooldownsRestricted` on Get{Spell,Charges}; booleans `isEnabled/isActive/isOnGCD/maxCharges` stay plain; duration objects non-secret | high (docs) / med (runtime) | **y** |
| 3 | Item cooldown reads in combat | No output-secrecy annotations on `C_Item/C_Container` pair; `GetInventoryItemCooldown` legacy-present; runtime unknown | high (docs) / low-med (runtime) | **y** |
| 4 | `GetSpellAuraSecrecy` + 76 set; FX overlap | Base classifier, tainted-callable, 76 spells (68 NS/7 AS/1 dual); **FX overlap: none** (ID-level), name-family only | high (mechanics) / med (list) | **y** (sweep + functional) |
| 5 | Cheap "are reads secret now?" | `C_RestrictedActions.Get/IsAddOnRestrictionActive(0..5)` + `C_Secrets.Should{Auras,Cooldowns}BeSecret` + `ADDON_RESTRICTION_STATE_CHANGED`; NATIVE-verified on 70707 | high | **y** (event fires; trivial) |
| 6 | `PLAYER_SWING(_RANGE_UPDATE)` | Present; documented payloads; no secrecy; live consumer on client | high | n (enum check y, cheap) |
| 7 | Own duration objects → own widgets | Legal by annotations; Musca ships CreateDuration+SetTimeFromStart; in-combat tick to be seen | high (legal) / med (tick) | **y** (= probe #5) |
| 8 | AddAuraSound / CustomAuraContainerTemplate | Present + in use on client; sound registration scoped to outside encounter/M+/PvP (ordinary combat allowed); container registration out-of-combat practice; item-source render unproven | high (presence) / med (enforcement) / low-med (item render) | **y** (= probes #3/#4) |
| 9 | Load-on-demand split | Full LoD ships; LoD files unparsed until load; load fires ADDON_LOADED; login win real (Ellesmere/Polestar precedent) | high (surface) / med (FX end-to-end) | **y** (day-1) |
| 10 | SavedVariables timing + PerCharacter | Directives shipped + live-used; Forever write order = best-guess (LEAVING→LOGOUT→UNLOADING→save); FX must self-save | high (presence) / low-med (order) | **y** (day-1) |

## Ranked design changes this research justifies

1. **`ForteXorcist.SecretState` mode-switch** (Q5): one cached `restricted`/`aurasSecret`/`cooldownsSecret` set
   updated on `ADDON_RESTRICTION_STATE_CHANGED` + `PLAYER_REGEN_ENABLED/DISABLED`; every read tier reads it.
   Replaces scattered `PlainOrNil` probing with one mode (keep `PlainOrNil` as field guard).
2. **Boolean cooldown tier** (Q2): render readiness from `isEnabled`/`isActive` (+ `isOnGCD`, `maxCharges` — all
   DOCS-plain-in-combat) on icons; numbers stay cast-predict. Free, legal, high-value in-combat signal.
3. **Day-1 aura-secrecy sweep baked into data pipeline** (Q4): stamp every tracked aura ID with
   `GetSpellAuraSecrecy` (client, out of combat) into a `secrecy` field in generated data (re-stamp per build pin);
   hits (today: zero) upgrade straight to in-combat `GetPlayerAuraBySpellID` reads; zero ⇒ container/sound stays
   primary. Also encodes the AlwaysSecret pet set as a never-read blacklist.
4. **Registration blackout windows** (Q8): gate `AddAuraSound`/`AddAuraSlot`/gate-container construction on
   `IsAddOnRestrictionActive(1|2|3)` — queue to the out-of-combat rebuild; formalises PA/CPA practice.
5. **Duration-object rendering spine** (Q7, after probe #5): timeline/cooldown widgets fed by
   `C_DurationUtil.CreateDuration()`+`SetTimeFromStart` from cast-predict, with `HasSecretValues()` gate on every
   object entering a widget; kills the "frozen bar" class of bugs.
6. **LoD class-data split** (Q9): `## LoadOnDemand: 1` per class addon + `C_AddOns.LoadAddOn` from Forte_Core at
   `PLAYER_LOGIN`, `ADDON_LOADED`-driven registration; measurable login win, Polestar/Ellesmere precedent.
7. **SavedVariables contract** (Q10): per-character learned DB in TOCs, self-save on `PLAYER_LOGOUT`/
   `ADDONS_UNLOADING`, acyclic/depth-bounded shape, `/fx save`.
8. **Swing subsystem plan confirmed** (Q6): implement Phase 3 swing timer on `PLAYER_SWING` payload +
   `C_SwingTimer`; no secrecy risk; no design change beyond adopting the documented payloads.
9. **Item-cooldown read = opportunistic, not spine** (Q3): P-A uses direct item-cooldown reads only behind the
   probe result + cast-predict fallback.
10. **Cast-counter instrumentation** (Q1): ship the plain/secret/unresolved cast tally in `/fx status` now
    (design doc probe #1) — it is the collection instrument for the one genuinely unknown field-level question.

## Method notes / gaps

- Sim harness: `$WORK/wow-ui-sim/run.sh wow-sim --allow-ui-version-mismatch --no-addons
  --exec-lua @/tmp/fxprobe/probe_*.lua lua-errors`; results encoded via `error("FX…")`; `--exec-lua @file` works
  (inline `-e` style too); `print` is swallowed. Simulator runs are **not** client evidence; the client's own
  binary strings (installed 2026-11-01, `.flavor.info=wowf`) were extracted to close presence gaps the sim leaves open.
- `data/spell_aura_secrecy.provenance.json` (referenced at `spell-aura-secrecy.md:17`) is not in the local
  corpus; the 76 list therefore carries the `12.1.0.69497` data pin of the regeneration command
  (`spell-aura-secrecy.md:19-23`) and must be re-enumerated on the launch build (probe in Q4).
- The sim's spell name table is partial (nils in the 76 name list); names marked `?` resolve only on the client.
