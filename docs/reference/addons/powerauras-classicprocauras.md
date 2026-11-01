# Power Auras + ClassicProcAuras — how they show procs through combat secrecy

Both addons read from **real shipped code** (zips pulled from CurseForge on 2026-11-01; the
download route is `https://www.curseforge.com/api/v1/mods/<projectId>/files/<fileId>/download`,
discovered from the site's own JS bundle, redirecting to `mediafilez.forgecdn.net`).

| Addon | Version | Date | Interface | Files read |
|---|---|---|---|---|
| Power Auras (Phantomaz, MIT per `PowerAuras.toc` `X-License`) | 1.0.5 | files uploaded 2026-10-15 | **16001** (Forever) | `PowerAuras.toc`, `Core.lua` (900 l), `Buffs.lua` (491), `Overlay.lua` (836), `Options.lua` (1464), `Classes/Warrior.lua`, `Classes/Hunter.lua`, `CHANGELOG.md` |
| ClassicProcAuras (onlyzander) | 0.5.6 | 2026-10-15 | **16001** (Forever), `OptionalDeps: Blizzard_AuraContainer` | `ClassicProcAuras.toc`, `Core.lua` (517), `Core.xml` |

Line references below are from these zips (`/tmp/addons/pa/PowerAuras/...`, `/tmp/addons/cpa/ClassicProcAuras/...`).
Nothing here is inferred from marketing text; changelog quotes are labelled as author statements.

## Verdict

- **ClassicProcAuras: `uses-game-aura-container`** (plus `reads-spell-state` not at all — it never
  reads auras, never polls, uses events only for login/combat-end). It registers spell IDs into a
  Blizzard-owned `AuraContainer` and lets the container's own code show/hide the artwork.
- **Power Auras: `uses-game-aura-container` for buff-presence gates, + `reads-spell-state` as primary
  usable-proc signal, + `uses-events-only` style cast timers, + native glow events for journaling.**
  A layered fallback stack: direct aura reads out of combat → AuraContainer "gate" presence signal in
  combat → cast/cost/usable sign proxies.
- Neither uses a secure snippet, secure channel, `C_AddOnMessages`/`C_AddOnData`, `SecureHandler*`,
  `SecureCallProtectedFunction`, `RunForPlayer`/`ProcessScriptsForPlayer` — a grep over all shipped
  Lua for those names returns **zero matches** in both addons. (`C_AddOnMessages`/`C_AddOnData` and
  `RunForPlayer` do not appear anywhere in the Forever 16001 surface we have: not in the
  `wow-ui-sim` binary strings (`/tmp/simstrings.txt`, ~1e6 strings from `wow-sim` v0.1.39-forever),
  not in the extracted client API docs under `wow-forever-addon-dev/references/wow-ui-source-forever/`.)
  **There is no snippet/channel to use here; the AuraContainer *is* the sanctioned hand-off.**

## API surface used

### ClassicProcAuras 0.5.6 (all in `Core.lua` unless noted)

| API | Where | What for |
|---|---|---|
| `C_AddOns.LoadAddOn("Blizzard_AuraContainer")` (fallback `LoadAddOn`) | Core.lua:184-193 | load the native aura-container code before using it; `OptionalDeps: Blizzard_AuraContainer` in `.toc` |
| `C_Secrets.GetSpellAuraSecrecy` (existence check only) | Core.lua:180-182 | refuses to start if `C_Secrets` missing — "Required Forever aura APIs unavailable." |
| `InCombatLockdown()` | Core.lua:37, 71, 179, 383, 394, 430 | gate every structural change (init, SetEnabled, appearance, test preview) |
| `CreateFrame('AuraContainer', 'ClassicProcAurasAuraContainer', holder, 'CustomAuraContainerTemplate')` | Core.lua:204 | the whole trick: a Blizzard aura container parented to a plain addon frame |
| `container:SetUnit('player')` / `container:SetEnabled(bool)` | Core.lua:206-207, 38 | bind to player; per-class enable/disable of the proc display |
| `container:AddAuraSlot(name, 'HELPFUL', { templateNames, initializeFrame, candidateFilters = { includeSpellIDs = {...} } })` | Core.lua:212-218 (Mage), 225-244 (Druid), 252-276 (Warlock) | registers the proc aura; the spell-ID set is plain data handed to Blizzard's matcher |
| XML virtual template `CPA_FrostAuraButtonTemplate` with `visual`/`art` parentKeys | Core.xml:2-11 | CustomAuraButton-shaped slot content the addon decorates at init |
| `button.visual.art`, `art:SetTexture(<FileDataID>)`, `SetVertexColor`, `SetTexCoord` | Core.lua:114-121, 134, 236-237, 263-264 | paints Blizzard's own spell-activation art (449489 Fingers of Frost, 449492 Nightfall, 510823 Omen) onto the slot |
| `button:SetApplicationBar(gate, { minApplications = 2, maxApplications = 3 })` | Core.lua:146-161 | native 2-stack gate: Blizzard code shows the right-side art only at ≥2 stacks ("inside its own allowed execution context", comment Core.lua:143-144) |
| `CreateFrame('StatusBar', ...)` as application-bar host; no fill texture | Core.lua:149-156 | uses the bar purely as a native visibility gate for a full-size child texture |
| `art:CreateAnimationGroup`/`CreateAnimation('Scale')` pulse | Core.lua:60-68 | appearance only, never on aura-derived values |
| `CreateFrame('Frame','ClassicProcAurasAnchor', UIParent)` + `SetScale`/`SetAlpha` | Core.lua:195-200, 77-80 | the addon's own anchor frame (outside the container), for size/opacity |

Events: `PLAYER_LOGIN`, `PLAYER_REGEN_ENABLED`, `PLAYER_REGEN_DISABLED` (Core.lua:482-484) — init +
deferred-change flush; `PLAYER_REGEN_DISABLED` (combat start) stops the preview. **No aura events,
no timers.** Proc-list structure: three hardcoded constants — `SPELL_ID = 400670` (Fingers of Frost,
Core.lua:5), `NIGHTFALL_SPELL_ID = 17941` (:6), `CLEARCASTING_SPELL_ID = 16870` (:8) — as
`includeSpellIDs` sets, keyed per class.

### Power Auras 1.0.5

| API | Where (file:line) | What for |
|---|---|---|
| `GatesSupported()` → `pcall(C_AddOns.LoadAddOn,"Blizzard_AuraContainer")` + `CustomAuraContainerAuraProcessingPolicy ~= nil` | Core.lua:217-220 | detect the container system |
| `CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")` (invisible, 1×1, alpha 0) | Core.lua:240-245 | "aura gate": presence detector per proc per unit |
| `container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.None)` | Core.lua:246 | container policy (bundled enum) |
| `container:AddAuraSlot("gate", filter, { candidateFilters = { includeSpellIDs = ids }, initializeFrame = ... })` | Core.lua:247-256 | register proc aura IDs (`"HELPFUL"` / `"HARMFUL|PLAYER"`) |
| slot button `button:SetScript("OnUpdate", function() gate.seen = GetTime() end)` | Core.lua:254 | the presence signal — Blizzard shows the button while the aura is up; addon reads only the clock, never the aura |
| `container:SetUnit(unit)` / `SetEnabled` / `UpdateAllAuras()`; target-change refresh | Core.lua:256-259, 331-337 | bind/re-scan (player and target gates) |
| gate freshness + verification (`GATE_FRESH=0.3`, `GATE_PATIENCE=1.5`, `gate.verified`, auto-add unseen aura IDs) | Core.lua:213, 296-329 | treat "button ticking" as presence; cross-check vs readable auras out of combat; persist discovered IDs (`db.auraIDs`) |
| `InCombatLockdown()` guard around (re)building gates | Core.lua:279 | "A container can only be set up outside a fight" (comment Core.lua:209-210) |
| `C_Secrets.ShouldAurasBeSecret` | Core.lua:191-193; Buffs.lua:165-166 | "are aura reads going to be secret right now" gate → AuraState returns `nil` (unknown) in combat |
| `C_UnitAuras.GetAuraDataBySpellName(unit,name,filter)`; `C_UnitAuras.GetPlayerAuraBySpellID(id)` | Core.lua:195; Core.lua:426-437; Buffs.lua:173 | direct aura reads: out-of-combat truth, `nil` (not false) when secret |
| `C_Spell.IsSpellUsable` (fallback `IsUsableSpell`) | Core.lua:113-126 | "ability lit up" = the proc (usable procs "always work", per the project page) |
| `C_Spell.GetSpellCooldown` → `{startTime,duration,isOnGCD}` with `IsSecret` fields check | Core.lua:161-182 | off-cooldown condition + GCD-aware "on cooldown" suppression |
| `C_Spell.GetSpellInfo` → `castTime`, `spellID`; `C_Spell.GetSpellPowerCost` | Core.lua:357-378; 384-405 | sign proxies: proc = a listed spell "turned instant or free" (`instant`/`notInstant`/`free`/`notFree` spell-ID lists) |
| `C_Spell.GetSpellName`, `C_Spell.GetSpellTexture` | Core.lua:78-90 | names (conditions keyed by name "on purpose", Core.lua:458-460) and icons |
| `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` (pcall-registered) | Core.lua:866-867, 143-151 | the native proc-glow feed → journal evidence for `GlowText` |
| `UNIT_SPELLCAST_SUCCEEDED` via `RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED","player")` | Buffs.lua:482-486 | start cast-predicted buff timers |
| `hooksecurefunc("UseAction", OnUseAction)` + `GetActionInfo`/`GetMacroSpell` | Buffs.lua:411-429, 488-490 | remember the last pressed spell; used when the cast event's `spellID` arrives secret/nil (Buffs.lua:431-455) |
| `GetComboPoints("player","target")` polled | Buffs.lua:196-201 | finisher-length estimation (Slice and Dice) |
| learned durations `ns.db.learned[key] = scale` (real aura length corrects the estimate whenever readable) | Buffs.lua:212-226, 231-245 | in-combat timer accuracy without aura reads |
| own display: `CreateFrame("Cooldown", ..., "CooldownFrameTemplate")`+`SetCooldown(start,dur)`, textures, `PlaySoundFile`/`SOUNDKIT` | Buffs.lua:50-55, 122-127; Overlay.lua:194, 386-390, 554-556 | the arcs and timer rings are 100% the addon's own frames ("Layout, sizes and animations mirror Blizzard's SpellActivationOverlay ... which this client ships but does not load", Overlay.lua:1-3) |
| `C_Timer.NewTicker(0.1, SafeUpdate)` | Core.lua:878 | 10 Hz evaluation of every proc condition |

Events registered: `ADDON_LOADED`, `PLAYER_LOGIN` (Core.lua:839-840); then
`SPELL_UPDATE_USABLE`, `PLAYER_TARGET_CHANGED`, `SPELLS_CHANGED`, `UPDATE_SHAPESHIFT_FORM`,
`PLAYER_ENTERING_WORLD`, `PLAYER_DEAD`, `PLAYER_ALIVE`, `PLAYER_REGEN_DISABLED` (Core.lua:854-858);
`SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` (866-867, pcall); `UNIT_SPELLCAST_SUCCEEDED` unit-event
(Buffs.lua:482-486). Secret-annotated ones (client docs,
`references/wow-ui-source-forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:4827-4830`):
`UNIT_SPELLCAST_SUCCEEDED` carries `SecretWhenUnitSpellCastRestricted = true` — which is exactly why
Buffs.lua:441-447 guards `IsSecret(spellID)` and falls back to the UseAction press-memory.
`SPELL_ACTIVATION_OVERLAY_*` events are documented with **plain-number payloads**
(`SpellActivationOverlayDocumentation.lua:28-77`: `spellID number`, SHOW carries `overlayFileDataID`,
`locationType`, `scale`, `r,g,b`) — no secret annotation.
PROC-LIST STRUCTURE (answers "hardcoded spell IDs? names?"): `ns.RegisterClass(class, {...})` — one
list per class, each entry: `key`, `spellID` (client spell ID, e.g. Overpower 7384
`Classes/Warrior.lua:8`, Mongoose Bite 1495 `Classes/Hunter.lua:5`), `names={enUS=..,ruRU=..}` (aura
lookups by **name**, usability by name "on purpose", Core.lua:458-460), `auraSpell`/`auras={ids}` for
the buff aura, `kind="usable"|"ready"|"buff"|"nobuff"|"debuff"|"nodebuff"` (Options.lua:116),
`instant/notInstant/free/notFree` sign spell lists, `cast=<seconds>` estimated aura length for
buff-icons, `texture=<FileDataID>` (client `Interface\SpellActivationOverlays` art), `where`, plus
runtime-discovered aura IDs in `db.auraIDs` (Core.lua:24, 234-236). User procs: up to 20, spell chosen
from `C_SpellBook` (Options.lua:482-485), any kind (Options.lua:872-875).

## Events registered (summary, marked secret-annotated)

- ClassicProcAuras: `PLAYER_LOGIN`, `PLAYER_REGEN_ENABLED`, `PLAYER_REGEN_DISABLED` — none
  secret-annotated in the docs; deliberately **zero combat-relevant reads**.
- Power Auras: list above; secret-relevant: `UNIT_SPELLCAST_SUCCEEDED`
  (`SecretWhenUnitSpellCastRestricted`, UnitDocumentation.lua:4830) — handled;
  `UNIT_AURA*` events are **not used at all** (client docs annotate `UNIT_AURA` payloads
  `SecretWhenAurasRestricted`, `UNIT_AURA_BLOCKED` carries a secret aura ID —
  `docs/reference/wow-ui-sim-specs/secret-auras.md:23`).

## The in-combat trick, step by step

**ClassicProcAuras**
1. Out of combat (`InCombatLockdown()` gate, Core.lua:179), load `Blizzard_AuraContainer` (:184-193).
2. Create an anchor frame; `CreateFrame('AuraContainer', ..., 'CustomAuraContainerTemplate')` (:204),
   `SetUnit('player')` (:206).
3. Per proc, `AddAuraSlot(name,'HELPFUL',{ templateNames={CPA template}, initializeFrame,
   candidateFilters={includeSpellIDs={[id]=true}} })` (:212-276). The addon hands Blizzard's matcher
   a **plain table of plain spell IDs** — this is the answer to "how do they get their spell IDs
   into it": they are never secrets, and the matching/visibility logic runs in Blizzard's own
   untainted context, so no taint crosses any boundary.
4. In `initializeFrame` (runs at slot-assignment time, out of combat), the addon paints the slot:
   texture = Blizzard's own overlay art by FileDataID (:115, 237, 264). Nothing here reads an aura.
5. Right-side stack gate: an addon-made invisible `StatusBar` is passed to
   `button:SetApplicationBar(gate, {minApplications=2,maxApplications=3})` (:149-161); "Private
   Blizzard's CustomAuraButtonMixin applies the minApplications threshold and SetShown inside its
   own allowed execution context" (:143-144) — the ≥2-stack visibility decision is made on the
   secret stack count **inside Blizzard code**; the addon never sees the count.
6. In combat: addon does nothing structural. Container presence/absence animates the art. All
   appearance changes are deferred (pcall + `*Pending` flags, :29-40, :69-99) and flushed on
   `PLAYER_REGEN_ENABLED` (:485-491). Test preview is out-of-combat only (:383, 430).
7. Fallback: if `SetApplicationBar` is unavailable (:146-147), `mode='presence-fallback'` (:166) —
   both arts show on any stack count (no stack info, presence only).

**Power Auras** (defence in depth, per author changelog: 1.0.1 added instant/free sign proxies;
1.0.4 added the aura-container gates — "The game hides buffs from addons during a fight; the addon
now watches them through the game's own aura container instead")
1. 10 Hz ticker (`C_Timer.NewTicker(0.1, SafeUpdate)`, Core.lua:878) evaluates each proc's `kind`
   condition (Core.lua:454-509).
2. `usable`/`ready` procs: `C_Spell.IsSpellUsable(name)` + `not IsOnCooldown(name)` — spell state
   stays plain in combat (their page: "Procs based on an ability becoming usable always work").
3. `buff` procs: ask `PlayerBuff` (name/ID aura lookups, :190-201, :424-446). Out of combat the answer
   is final. In combat those return `nil` (guarded by `C_Secrets.ShouldAurasBeSecret`, :191-193).
4. When the read is blind, ask the **gate**: a 1×1 alpha-0 AuraContainer per proc per unit
   (:239-264, built out of combat, :279); its slot button's `OnUpdate` stamps `gate.seen` (:254);
   "a button that noted it a moment ago means the aura is up" (:206-207 comment). Presence =
   `GetTime()-gate.seen < 0.3` (:300). The addon never inspects the button/aura (only its own clock).
5. Gate trust is earned, not assumed: out of combat the gate is cross-checked against readable auras;
   an aura ID the gate missed is learned and persisted, the gate is remade, and a gate "seen to
   agree" becomes `verified` (:297-329; `db.auraIDs` :24). Only verified gates are believed when they
   say **down**; unverified gates are combined with sign proxies (`BuffSign`, :448-452: a listed
   spell turned instant (`castTime==0` after being >0) or free (`cost==0`), `usableSign`).
6. Buff icons/timers: out of combat real aura expiry (`ReadAura`, Buffs.lua:171-178); in combat the
   timer is started from the player's own `UNIT_SPELLCAST_SUCCEEDED` (+UseAction press-memory for
   secret/nil `spellID`, :411-455) with `cast=` lengths corrected by `db.learned` scales (:212-226).
7. Native `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` feed the journal (:866-867, 143-151) — recorded,
   and the author states it's not trusted for display decisions yet ("whether this client sends it
   for abilities that light up without a buff ... is not known yet", :134-136 comment).
8. Display: every arc/ring is the addon's own frames with the client's shipped art FileDataIDs
   (Overlay.lua:554-556; `Classes/*.lua` textures). The native SpellActivationOverlay system
   (`C_SpellActivationOverlay`, documented `Environment="All"`, settings row
   `displaySpellActivationOverlays:'1'`) is deliberately not used — the addon mirrors its look.

## What the simulator specs say: what tainted code may pass into aura containers, what is blocked

From `docs/reference/wow-ui-sim-specs/` (paths:line quoted):

- **The addon→container interface is plain data only.** The container option surface is
  `C_AuraContainerUtil` with `Environment = "All"` and every processor
  `SecretArguments = "AllowedWhenUntainted"` (client contract
  `references/wow-ui-source-forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/AuraContainerUtilDocumentation.lua:5-6` and per-function at :13-17 etc.).
  Sim side: "Register the nine base processors **before secure-environment copying** ...
  `src/c_api/mod.rs` — pre-secure-copy namespace registration"
  (`aura-container-options.md:7`, `:24`). Tainted code may therefore pass **plain** option
  structures, plain FileDataIDs, plain spell-ID tables — i.e. exactly what CPA/PA pass.
- **What is blocked for tainted code is everything aura-derived, both directions.**
  "direct shown/text/timing readouts derived from secret inputs **reject tainted callers**.
  Untainted native processing and Rust rendering retain access" (`aura-secret-display.md:7`);
  "Cooldown and status-bar duration consumers retain the duration's secret origin. **Tainted
  consumers reject secret duration input before mutating widgets**" (`aura-secret-display.md:13`) —
  i.e. you cannot wire a secret expiry into your own `StatusBar`/`Cooldown`.
  Tainted `IsShown`/`GetText`/cooldown/status-bar numeric readouts reject secret-origin state
  (`aura-secret-display.md:14`). Native `Blizzard_CustomAuraButton.lua` "calls
  `SetShown(secretwrap(isAuraShown))`" and the wrapped-value decoder "rejects tainted callers"
  (`aura-secret-display.md:5`) — a tainted addon can neither feed nor read the container's own
  visibility values.
- **Geometry/texture handoffs of secret values are simulator guesses and fail RED:**
  "Native `Blizzard_CustomAuraContainer.lua` wraps all anchor arguments and both dimensions ...;
  `Blizzard_AuraContainerUtil.lua:291` wraps aura icons. ... wrapped anchors fail string conversion,
  wrapped dimensions become zero, and wrapped texture assignment/clearing silently retain the old
  icon" (`aura-secret-display.md:27`, marked "explicit simulator guesses" at :25 and :34).
- **Why the container works in combat at all:** "Secrecy applies to tainted (addon) execution.
  **Untainted Blizzard code keeps working on the same data**" (`secret-auras.md:26`);
  "Shipped aura buttons can pass secret duration, text, icon, visibility and geometry to their
  widgets and render correctly" (`secret-auras.md:45`); widget sinks apply `SecretArguments` modes
  ("never allowed / not allowed / only allowed during untainted execution", `secret-auras.md:43`).
  Reads the addon would do directly: `GetAuraDataByIndex`/`ByAuraInstanceID` return secret fields
  under restriction (`secret-auras.md:32`), spell-keyed lookups are `RequiresNonSecretAura` with
  in-combat result UNKNOWN natively (`secret-auras.md:35`; client annotation
  `UnitAuraDocumentation.lua:244-247,394-397,432-435`).
- **Sim limits of these claims:** restriction trigger is test-only in the sim (`secret-auras.md:54`);
  "This implementation does not establish exact native error wording or secret-argument enforcement"
  (`aura-container-options.md:44`); "Publishing option/enumeration data does not authorize or
  establish full access-restriction or secret-value enforcement" (`aura-container-options.md:48`).
  In the sim the whole spell-activation-overlay namespace is absent
  (`C_SpellActivationOverlay` in the sim's absent-namespace bootstrap, binary strings,
  `/tmp/simstrings.txt` cols ~32618/33565) — native-client behaviour remains the reference.

## Can a tainted addon register an arbitrary item-proc spell so Blizzard's aura UI renders it in combat?

**YES — with three load-bearing caveats.** Evidence:

1. The registration call is addon-side and accepts **any plain spell-ID set**:
   `container:AddAuraSlot(name, filter, { candidateFilters = { includeSpellIDs = ids } })`
   (CPA Core.lua:212-217; PA Core.lua:247-248). There is no whitelist: PA's `ids` are built at runtime
   from name lookups plus **discovered-and-persisted aura IDs** (`db.auraIDs`, Core.lua:222-237),
   and CPA's IDs are proc aura spells (400670 / 17941 / 16870), i.e. aura spells, not castable
   ability IDs — so the container's matcher works on aura spell IDs generally.
2. The rendering itself runs in Blizzard's untainted context and keeps working while auras are
   secret (`secret-auras.md:26`, `:45`); CPA's application-bar comment (Core.lua:143-144) states the
   visibility decision executes in the native button's "own allowed execution context".
3. In-combat **registration changes are off-limits**: containers are built/rebuilt out of combat
   (CPA `InCombatLockdown()` init guard Core.lua:179; PA Core.lua:279 + "A container can only be set
   up outside a fight" :209-210; PA rebuilds gates after the fight). A proc discovered mid-fight
   rides in on the gate built before it.
   CAVEATS: (a) the container must exist and the slot be registered **before** lockdown; (b) the
   spell must exist in the 16001 spell/aura table (item-proc IDs do — the data pins them
   [INFERENCE: my reading of mythicsim data conventions, not re-verified for each ID here]);
   (c) you get **Blizzard's rendered slot + presence/stack-gated visibility**, not the numbers —
   the addon can observe "slot is live" (PA OnUpdate trick, Core.lua:254) and gate on stacks
   (CPA `minApplications`, Core.lua:158-161), but `expirationTime`/`applications` remain unreachable
   to tainted code in combat (`aura-secret-display.md:13-14`).
   NO direct evidence exists that an **item-source** aura (trinket/enchant proc) renders — both
   addons cover class/talent procs only [INFERENCE: the ID space is flat and the filter is ID-based;
   nothing in the shipped code suggests a class-spell-only match; verify with one known Forever
   item-proc ID in uiforever.com/sim before building on it].

## Applicability to a compact timeline bar (our own icons sliding on a power-scale axis)

What transfers directly:
- **Gate presence** (PA pattern): per-proc invisible AuraContainer + OnUpdate freshness → the
  on/off edge of any aura in combat, no taint, works today (PA ships it; CPA ships the registration).
- **Stack gates without stack data**: `SetApplicationBar(..., {minApplications=n})` on a hidden
  statusbar host (CPA Core.lua:149-161) — "≥2 stacks" as a native-observed boolean.
- **Cast-predict timers** (PA Buffs.lua:231-255, 431-475) — structurally identical to PLAN.md §3.2
  (own `UNIT_SPELLCAST_SUCCEEDED` + learned durations), including the secret-`spellID` press-memory
  fallback (`hooksecurefunc("UseAction")`) and the out-of-combat self-calibration
  (`db.learned`, Buffs.lua:212-226).
- **Sign proxies** (instant/free/usable zeroing, Core.lua:384-415) as last-resort evidence with
  PA's seen-normal-then-zero discipline (prevents false fire on always-instant spells).
- **`C_Spell.GetSpellCooldown` + `IsSpellUsable`** for cooldown-position ticks on the bar (plain
  in combat; every field secret-guarded, Core.lua:161-182).

The blocker for the axis itself: an icon's continuous slide position needs the **expiry timestamp**,
which is secret in combat (`secret-auras.md:32`, `aura-secret-display.md:13` — and you cannot wire a
secret duration object into your own StatusBar/Cooldown at all, the consumer rejects it tainted-side).
So the bar's in-combat geometry must be driven by addon-side predicted timers (cast + learned length),
with the gate providing the ground-truth edge (fire on, expire at gate-loss); the container hands
Blizzard-rendered icons, not our icon positions — our icons stay our own frames (PA's Overlay.lua
proves a full custom renderer is the right shape). Native glow events are a bonus corroborating
signal (plain payload per docs; PA journals them, not trusted yet).

## Secure-handoff feasibility for ForteXorcist

There is **no secure-channel step** to try on this client (no `C_AddOnMessages`/`C_AddOnData`,
no snippet APIs in any observed surface). The concrete chain to build in `Forte_Cooldown`, each step
copied from shipped working code:

```lua
-- (0) LOGIN, out of combat, once:
C_AddOns.LoadAddOn("Blizzard_AuraContainer")            -- PA Core.lua:219 / CPA Core.lua:184
assert(CustomAuraContainerAuraProcessingPolicy ~= nil) -- PA Core.lua:220 (capability probe)

-- (1) one gate per watched proc spell (IDs pre-computed from Data/<Class>.lua, incl. item-proc IDs):
local gateSeen = {}
local c = CreateFrame("AuraContainer", "FX_Gate_"..key, UIParent, "CustomAuraContainerTemplate")
c:SetSize(1,1); c:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT"); c:SetAlpha(0); c:EnableMouse(false)
c:SetEnabled(false)                                     -- PA Core.lua:241-245
c:AddAuraSlot("gate", "HELPFUL", {                      -- item procs on self; "HARMFUL|PLAYER" for target
  candidateFilters = { includeSpellIDs = { [spellID] = true } },   -- plain data: our only input
  initializeFrame = function(button)
    button:EnableMouse(false)
    button:SetScript("OnUpdate", function() gateSeen[key] = GetTime() end)  -- PA Core.lua:254
  end,
})
c:SetUnit("player"); c:SetEnabled(true); c:UpdateAllAuras()          -- PA Core.lua:256-259

-- (2) in combat, on the 10 Hz tick (PA Core.lua:878 pattern):
local up = GetTime() - (gateSeen[key] or 0) < 0.3       -- PA GATE_FRESH, Core.lua:213
```

- Gate rebuilds (new proc learned, target change, class change) only when `not InCombatLockdown()`
  (PA Core.lua:279; target-gate freshness reset + `UpdateAllAuras` on `PLAYER_TARGET_CHANGED`,
  Core.lua:331-337).
- Gate verification out of combat against `ForteXorcist.Compat.PlainOrNil(C_UnitAuras.GetAuraDataBySpellName(...))`
  before trusting a gate's *negative* (PA Core.lua:297-329) — adopt the `verified` flag verbatim;
  route through our compat layer per AGENTS.md.
- Stack tiers via hidden StatusBar host + `button:SetApplicationBar(host, {minApplications=n,
  maxApplications=n+X})` on a second container per tier (CPA Core.lua:149-161) — gives per-threshold
  presence edges; fall back to presence-only when `SetApplicationBar` is absent (CPA :146-147).
- Keep all reads of the gate out (no `GetAttribute`/text/getters on Blizzard-owned children,
  "Never inspect or mutate them in combat", CPA Core.lua:69-70) — the OnUpdate timestamp is the only
  allowed signal, and it is our own function reading our own table and `GetTime()`.
- Axis motion = predicted timers (cast event + learned scale); gate edges correct them; never pass
  anything secret-derived into our widgets (`aura-secret-display.md:13` rejection is the rule).
- Probe list for wow-ui-sim / uiforever before shipping: (a) gate built out of combat for a known
  **item-proc aura ID** fires its OnUpdate through a simulated combat lockdown; (b)
  `SetApplicationBar` availability; (c) `SPELL_ACTIVATION_OVERLAY_*` presence. Note the sim's own
  restriction trigger is test-only today (`secret-auras.md:54`), so gate the sim assertions on the
  test restriction flag; final word from the real client.

## Confidence + what we could not verify

- High: all shipped-code claims above (every call quoted with file:line from the actual zips);
  absence of secure-channel APIs in both addons (exhaustive grep); client-side annotations for
  `C_UnitAuras`/`UNIT_SPELLCAST_SUCCEEDED`/`SPELL_ACTIVATION_OVERLAY_*`/`C_Secrets`/`InCombatLockdown`
  (from the extracted 16001 API docs); sim-spec quotes (file:line above).
- Medium [INFERENCE]: the gate-out-of-combat limitation is enforced behaviourally (both addons guard
  it; PA states it in a comment) — the exact client rule (which calls are lockdown-forbidden) is not
  in any doc I have. CPA's `SetApplicationBar` stack gate is "attempted" per its own changelog with a
  presence fallback shipped — treat as best-effort, not guaranteed.
- NOT VERIFIED: an item-source (trinket/enchant) aura ID registered into a container end-to-end
  (neither addon exercises one); live in-combat gate freshness constants (0.3 s) against real
  slot-update cadence (PA ships them plus a journal, implying the author also validated in-game, not
  in docs); `SPELL_ACTIVATION_OVERLAY_*` completeness as a proc signal (PA journals, does not drive);
  CPA's Druid art FileDataID self-declares "not yet verified in-game" (Core.lua:10); the real-client
  enforcement detail of `RequiresNonSecretAura` in-combat returns (spec S8, `secret-auras.md:35`);
  native (non-sim) exactness of `C_AuraContainerUtil` secret-argument enforcement
  (`aura-container-options.md:44`); the sim has no `C_SpellActivationOverlay` namespace at all, so
  the native overlay system itself is untested terrain for us (we mirror the look, not the system —
  same choice PA made, Overlay.lua:1-3).
