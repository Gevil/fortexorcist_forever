# Code review 5 — changes since review 4 (`4cf0cf0..HEAD`)

Scope: `git -C wow-fortexorcist log --stat 4cf0cf0..HEAD -- addon tools scripts` —
`c02528e` Hunter swing v2, `695434c` README media, `366eee3` H7 item-proc split
(`Forte_ItemProcs`, `Cooldown.Procs`), `7eb1751` wave 2b class spells + cast
announces, `1624991` wave 2a data refresh (build 70707), `9a9bf86` `uif_battery.js`
console commands, `55c1ebc` H1 localization + H3 settings/profiles, `e3de949` H2
launch kit, `3e62477` Warlock plate icons, `9aee3b7` review-4 fixes.
129 files, `+51404 −1980`.

Read-only review: nothing was edited, no gate/sim run.

## Answer

**No blockers.** Every event-registration site added in this window reads its
payload in the catalog's slot order — including the two shapes the review class
is about (SENT carries `(unitTarget, target, castGUID, spellID)`, SUCCEEDED
carries `(unitTarget, castGUID, spellID, castBarID)`), which are handled
correctly at all four sites that consume them. The only event-name string
surgery in the window is the Hunter's `event:sub(16)`, whose offset is correct.
New aura/cooldown/unit/totem/comms reads obey the secret-value law. Chat/comms
sends all ride the legality gate; no added login-time sound; the hidden-frame
law holds in the new UI.

**5 majors, 12 minors.** The majors are all in the two families the launch is
most exposed to: four real-frame payload-test gaps on the event paths this
window added, and one announce row whose spell does not exist in the pinned
data. Nothing here blocks the 2026-11-04 launch; the four test gaps are the
law-violating class (AGENTS.md: tests ride the real frame's `OnEvent` with the
exact client payload), and the one shape-drift instance in a test
(`Forte_Timer/tests/test_module.lua:984`) is the same defect the Hunter bug
class produced.

---

## 1. Event payload audit

Catalog: `docs/api/wow-addon-api-agents/skills/*/references/generated/forever.json`
(`declaration.Payload`), plus the client docs the addon cites inline
(`UnitDocumentation.lua`, `ChatInfoDocumentation.lua`). Classic
`UniqueEvent`/`UnitEvent` names that the generated catalog does not declare
(`SPELL_UPDATE_COOLDOWN`, `BAG_UPDATE_*`, `WEAPON_ENCHANT_CHANGED`,
`PLAYER_REGEN_*`, `PLAYER_SWING*`, `UNIT_DIED`, `SPELLS_CHANGED`) are governed by
the repo's own gate, `scripts/api_lint.py`'s KNOWN-event set.

| Site | Event | Catalog payload | Handler reading | Verdict |
|---|---|---|---|---|
| `addon/Forte_Cooldown/Module.lua:561` (handler `:594`) | `UNIT_SPELLCAST_SUCCEEDED` | `(unitTarget, castGUID, spellID, castBarID)` | `function(_, event, unit, castGUID, spellID, castBarID)`; `spellID` → `M:RecordCastEvent(spellID, …)` (`:601`) | correct |
| `addon/Forte_Cooldown/Module.lua:581` | `UNIT_AURA` (`player`) | `(unitTarget, updateInfo)` | slots 1–2 handed to `Engine.Procs:OnUnitAura(unit, castGUID)` (`:624`); callee `Procs:OnUnitAura(unitTarget, updateInfo, now)` (`Core/Procs.lua:326`) | slots correct, call-site names misleading → m1 |
| `addon/Forte_Cooldown/Module.lua:562,563,564,571,572,585-588,593` | `SPELL_UPDATE_COOLDOWN`, `PLAYER_REGEN_ENABLED/DISABLED`, `SPELLS_CHANGED`, `ADDON_RESTRICTION_STATE_CHANGED`, `PLAYER_ENTERING_WORLD`, `BAG_UPDATE_COOLDOWN`, `PLAYER_EQUIPMENT_CHANGED`, `BAG_UPDATE_DELAYED`, `WEAPON_ENCHANT_CHANGED` | none / not read | branches re-read state; the carried payload is named as deliberately unused in the comments (`:655-660`) | clean |
| `addon/Forte_Cooldown/UI/Timeline.lua:580` (`_BindWarnEvents`, `:958`) | `UNIT_SPELLCAST_FAILED` (`player`) | `(unitTarget, castGUID, spellID, castBarID)` | binds slot 3 → `rows:CastFailed(spellID)` | correct |
| `addon/Forte_Core/Core/Init.lua:151` | `ADDON_LOADED` | `(addOnName, containsBindings)` | slot 1 → `addonName` | correct |
| `addon/Forte_Core/Core/Locale.lua:357-358` (handler `:351`) | `GET_ITEM_INFO_RECEIVED`, `ITEM_DATA_LOAD_RESULT` | `(itemID, success)` | slot 1 → `OnItemNameArrived(arg1)`, gate `arg2 == false` | correct; frame-level test gap → M3 |
| `addon/Forte_Hunter/Core/Tools.lua:1104-1118` (`onToolEvent`, `:1040`) | `UNIT_SPELLCAST_SENT` | `(unitTarget, target, castGUID, spellID)` | `a4` spellID, `a3` castGUID, `a2` target (`:1061-1062`) | correct; the SENT leg's target lands in the tracker's `castGuid` slot → m2 |
| same | `UNIT_SPELLCAST_START/SUCCEEDED/INTERRUPTED/FAILED/FAILED_QUIET` | `(unitTarget, castGUID, spellID[, castBarID])` | `a3` spellID, `a2` castGUID | correct |
| same | `PLAYER_SWING` | `(swingDuration, swingType)` | `OnSwingStart(a1, a2)` | correct |
| same | `PLAYER_SWING_RANGE_UPDATE` | `(swingType, isInRange, checksRange)` | `OnSwingRange(a1, a2, a3)` | correct |
| `addon/Forte_Hunter/UI/Swing.lua:906-917` | the render kicks | — | payloads unread by design | clean |
| `addon/Forte_Messages/Module.lua:591-598` (`OnCastForAnnounce`, `:502`) | `UNIT_SPELLCAST_SENT` | `(unitTarget, target, castGUID, spellID)` | `spellNameFor(c)` (slot 3), target stamp `PlainOrNil(a)` | correct |
| same | `UNIT_SPELLCAST_SUCCEEDED` | `(unitTarget, castGUID, spellID, castBarID)` | `OnCastForAnnounce(event, unit, a, b, c)` with `a`=castGUID, `b`=spellID → `spellNameFor(b)` | correct |
| `addon/Forte_Shaman/Core/Totems.lua:260-266` | `PLAYER_TOTEM_UPDATE` | `(totemSlot)` | slot 1 → `OnTotemUpdate`, `PlainOrNil(slot)` (`:96-120`) | correct, and frame-tested (`tests/test_totems.lua:199-203`) |
| `addon/Forte_Timer/Module.lua:560-577` (handler `:635`) | `UNIT_SPELLCAST_SENT` (`player`, `pet`) | `(unitTarget, target, castGUID, spellID)` | `C:OnSent(a2, a4)` / `C:OnPetSent(a2, a4)` (`:646-652`) | correct |
| same | `UNIT_SPELLCAST_START`, `SUCCEEDED` | `(unitTarget, castGUID, spellID, …)` | `OnStart(a3)`, `OnSucceeded(a3)`, `OnPetSucceeded(a3)` | correct |
| same | `UNIT_SPELLCAST_FAILED`, `INTERRUPTED` | `(unitTarget, castGUID, spellID)` | `C:OnFailed(a3, a2)` (`:639,:642`) — slot 3 spellID ✓; slot 2 is the castGUID into `Casts:OnFailed(spellID, target, now)` (`Core/Casts.lua:647`) | spellID correct; 2nd-arg naming drift → m3 |
| same (`:575-576`) | `UNIT_AURA` (`player`, `target`) | `(unitTarget, updateInfo)` | slot 1 unit token drives the liveness/live-pass branches | correct |
| same (`:577`) | `UNIT_DIED` (`target`) | `(unitToken)` | the branch at `:672` uses slot 1 as the dying unit | correct; untested → M4 |
| `addon/Forte_Warlock/Core/Comms.lua:593-600` | `CHAT_MSG_ADDON` | `(prefix, text, channel, sender, …)` | `OnAddonMessage(a1, a2, a4)` | correct, and frame-tested (`tests/test_warlock_group.lua:160-166`) |
| `addon/Forte_Warlock/Core/Tools.lua:844-858` | `UNIT_SPELLCAST_SENT` + the START/CHANNEL_START/SUCCEEDED/STOP/FAILED/INTERRUPTED/CHANNEL_STOP family | as catalog | `a4`/`a2` on SENT, `a3` on the rest | correct |
| `addon/Forte_Warlock/UI/Module.lua:226-236` | `CAST_EVENTS` | — | kick-only | clean |
| `addon/Forte_Core/Core/Probe.lua:866-874` (frame `:943`) | `UNIT_SPELLCAST_SUCCEEDED`, `PLAYER_SWING`, `PLAYER_SWING_RANGE_UPDATE`, `ADDON_RESTRICTION_STATE_CHANGED` | — | `Probe:Capture(event, a,b,c,d)` classifies every slot through the secrecy classifier; no semantic slot use | clean; dynamic registration → m6 |

No payload-order defect at any site.

## 2. String surgery on event names

Single site: `addon/Forte_Hunter/Core/Tools.lua:1059`

```lua
self.Swing:OnShotCast(event:sub(16), name, a3, a2)
```

`"UNIT_SPELLCAST_"` is 15 characters, so the 1-based `sub(16)` yields
`START` / `SENT` / `SUCCEEDED` / `FAILED` / `FAILED_QUIET` / `INTERRUPTED` —
exactly the op strings `SwingTracker:OnShotCast` compares
(`addon/Forte_Hunter/Core/Tools.lua:317-321,366-380`). The historical `sub(15)`
bug is named and pinned by the comment at `:1056-1058`. **Verdict: correct.**
No event-name `gsub`/`match`/`find`/`gmatch` appears in the window; the other
string surgery operates on settings keys, locale aliases, comms wire text and
font paths.

## 3. Secret-value handling on the new reads

Clean:
- `addon/Forte_Cooldown/Core/Procs.lua` — the bulk read counts `raise`/`secret`/
  `plain` (`:155-178`), the payload's `addedAuras` is read through a hoisted
  accessor inside `pcall`, `issecretvalue` gates the bulk list, and only a plain
  `spellId` opens a window; the gate (`Gates`, `:127-138`) treats a nil mode as
  "no answer", never as an absence.
- `addon/Forte_Timer/Core/Casts.lua` — `TokenGuid`/`PetTargetKey`/`ResolveTarget`
  (`:80-176`) pcall + `PlainOrNil`, target strings are keys, never values.
- `addon/Forte_Shaman/Core/Totems.lua:90-120,187-215` — `C_Secrets.ShouldTotemSlotBeSecret`
  sealed-slot check before the read, `PlainOrNil` on every return.
- `addon/Forte_Hunter/Core/Range.lua:21-48` — nil means "no knowledge", never false.
- `addon/Forte_Hunter/Core/Tools.lua:888-892` (`speedSampler`) +
  `Core/Tools.lua:400-411` (`SampleMovement`: `type(speed) == "number"` before any
  compare), `:1121-1137` (`NetLatency`: the 4th `GetNetStats` return gated by
  `type(v) == "number"`, no raw compare — exactly the §B12 law).
- `addon/Forte_Warlock/Core/Comms.lua:240-300` — roster reads pcall'd,
  `plainString`/plain-number gates.
- `addon/Forte_Core/Core/Locale.lua:83-107` — name reads pcall + `PlainOrNil`;
  `GET_ITEM_INFO_RECEIVED`'s `success` is a plain non-nilable `bool` in the
  catalog, so `arg2 == false` is not a secret compare.
- `addon/Forte_Cooldown/Module.lua:432-467` (`RecordCastEvent`) — no `spellID ~= nil`
  compare, the `C_Spell.GetSpellInfo` table read inside one `pcall`,
  `PlainOrNil(info.name)` the only value that leaves.
- `addon/Forte_Cooldown/Core/Enchants.lua` — `readKey(name)` + pcall'd reads
  (the H1b locale seam), and the split's proc rows moved to
  `addon/Forte_ItemProcs/Data/Procs.lua` (a plain generated table, no client reads).

Findings: m8, m9, m12.

## 4. Settings ⇄ consumers

Every key registered in the window has a runtime consumer:

| Key (registration) | Consumer |
|---|---|
| `Hunter.ShowSafeWindow/ShowAimSlice/ShowFlying/ShowRetry/ShowLatency/InCombatAlpha/OutOfCombatAlpha/ShowRangeLight/BaseSpeed` (`addon/Forte_Hunter/Pages/Hunter.lua:41-53`) | the setter map `addon/Forte_Hunter/UI/Swing.lua:752-761` + `:660` (the alpha pair); `BaseSpeed` also `Core/Tools.lua:282,317,327` |
| `Hunter.ShowRangeLight` | `UI/Swing.lua:758` → `UI/Range.lua:SetEnabled` (`:271-280`), the `C_SwingTimer.EnableRangeCheck` pair (`:188-196`) |
| `Warlock.CommsEnable` (`Forte_Warlock.toc` page) | `Core/Comms.lua:218` (`C:Enabled`), `UI/Frame.lua` |
| `Warlock.HealthstoneUnknown` | `Core/Group.lua`, `UI/Frame.lua`, `UI/Healthstone.lua` |
| `Cooldown.Procs` (`addon/Forte_Options/Pages/Cooldown.lua:55`, row `:197`) | `Core/Procs.lua:390` + the live listener `_WireSettings` (`:399`) |
| the 20 cast rows × `<prefix>CastParty/CastChannel/CastText` (`addon/Forte_Messages/Pages/RaidMsg.lua:538-543`) | `addon/Forte_Messages/Module.lua:516-522` (the per-row gate + send) |

Consumers with no setting: none found — every `cfg[...]`/`FX.Settings:Get`
read in the window maps to a registered key.

Finding M5 covers the one row whose *spell* is inert on the pinned build.

## 5. Real-client hazards

- **Chat/comms legality.** No direct `SendChatMessage` added. Warlock comms
  rides `C_ChatInfo.SendAddonMessage` through `Comms:Send` behind: the
  `CommsEnable` switch, `C:chatLocked()` (plain-`true`-only over
  `FX.SecretState.chat`, `C_ChatInfo.InChatMessagingLockdown`,
  `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted` —
  `addon/Forte_Warlock/Core/Comms.lua:196-209`), the group-channel requirement
  and the rate gate (`:239-259`). The announce casts go through
  `Announce:Group/Channel`, per-row gated, and every cast-row gate key defaults
  OFF (`Forte_Messages/Pages/RaidMsg.lua` DEFAULTS). Prefix registration is
  pcall'd once and unregistered symmetrically
  (`Forte_Warlock/Core/Comms.lua:593-600`).
- **Sounds.** The added sound rows play on the `FX_COOLDOWN_READY` /
  `FX_TIMER_EXPIRED` pumps only (`addon/Forte_Messages/Core/Sounds.lua:76-101`);
  no login-time pump. The new `CooldownReady` row defaults OFF (its PAGES
  default is `false`).
- **Frames shown while idle / hidden-frame `OnUpdate`.** No top-level
  `CreateFrame` in the window. The range light hides at `Init`
  (`addon/Forte_Hunter/UI/Range.lua:169`), installs `OnUpdate` only from a shown
  `Refresh` (`:249-266`) and nils the script in `StopTicking` (`:266-268`); the
  show transition renders synchronously (`:236`). The swing bar's ticker follows
  the same law (`addon/Forte_Hunter/UI/Swing.lua:28-32,697-716`). The one
  standing-shown frame is the documented Warlock plate driver (no textures,
  mouse-disabled).
- **Registration site law.** Every new `Register*Event` runs inside the
  `OnEnable`/login chain with the frame created there
  (`addon/Forte_Cooldown/Module.lua:558`, `Forte_Timer/Module.lua:558`,
  `Forte_Messages/Module.lua:589`, `Forte_Warlock/Core/Comms.lua:593`).

## 6. Test-shape audit

Riding the real frame with exact client payloads (good):
`addon/Forte_Hunter/tests/test_swing2.lua:619-703` (START/SUCCEEDED/
FAILED_QUIET/SENT through `Tools._eventFrame`'s script, incl. the 4-slot SENT),
`Forte_Messages/tests/test_cast_announce.lua:73-176`, `Forte_Warlock/tests/
test_warlock_group.lua:160-166` (`CHAT_MSG_ADDON` with the 4-slot shape),
`Forte_Shaman/tests/test_totems.lua:199-203`, `Forte_Timer/tests/
test_pet_rows.lua:114-118` (pet SENT/SUCCEEDED with the catalog shapes),
`Forte_Timer/tests/test_module.lua:136-251`, `Forte_Hunter/tests/
test_locale_hunter.lua:106-140`.

Direct-method-only where the frame shape is load-bearing: findings M1–M4.

---

# Findings

## Blockers
None.

## Major

**M1 — a `UNIT_SPELLCAST_SENT` dispatch rides the retired 3-slot shape
(`addon/Forte_Timer/tests/test_module.lua:984`).**
```lua
dispatch("UNIT_SPELLCAST_SENT", 425737, "Serpent Sting", "target-target")
```
The catalog's shape is `(unitTarget, target, castGUID, spellID)`, so under
`Forte_Timer/Module.lua:646` (`C:OnSent(a2, a4)`) the spellID arrives as `nil`
and the dispatch records nothing. The test's row-count assertion is satisfied
by the `/fx timer test` seed at `:982`, so the payload line is inert and the
file's comment ("the steady state is reached through the public cast path") is
false. This is the shape-drift class the review exists to catch — the same
1-slot shift that broke the Hunter. Fix:
```lua
dispatch("UNIT_SPELLCAST_SENT", "player", "target-target", "G:fill", 425737)
```
and assert the row the dispatch adds (`Rows:Count()` delta), not the seed total.

**M2 — no real-frame payload test for the new `UNIT_AURA` → proc-feed handoff
(`addon/Forte_Cooldown/Module.lua:581,624`).**
`addon/Forte_Cooldown/tests/test_procs.lua:116,296-307` call
`Procs:OnUnitAura("player", {…})` directly. The catalog hands
`(unitTarget, updateInfo)`; the handler hands `(unit, castGUID)` and the callee
is `OnUnitAura(unitTarget, updateInfo, now)` (`Core/Procs.lua:326`). The mapping
is correct today and pinned by nothing — exactly the AGENTS.md test law
("tests send exact client payloads through the real frame's `OnEvent`"). Add to
`test_procs.lua`:
```lua
local f = M._eventFrame
f:GetScript("OnEvent")(f, "UNIT_AURA", "player",
    { addedAuras = { { spellId = AD_ID, instID = 1 } } })
-- then assert the ICD window opened / IsShown()
```
plus the negative leg: a dispatch whose 2nd slot is `nil` must open nothing.

**M3 — the Locale late-name events are untested at their frame
(`addon/Forte_Core/Core/Locale.lua:345-358`).**
`Forte_Core/tests/test_locale.lua:57` and
`Forte_Cooldown/tests/test_locale_cooldown.lua:138` call
`Locale.OnItemNameArrived(itemID)` directly. The frame's `(itemID, success)`
reading and the `arg2 == false` gate are the only place the build pins the
late-arrival contract; a swapped shape passes the suite today. Add a
`Forte_Core` locale test that drives
`Locale.state.frame:GetScript("OnEvent")(f, "GET_ITEM_INFO_RECEIVED", id, true)`
(name resolves) and `(…, id, false)` (stays unresolved).

**M4 — `UNIT_DIED` has no test at any level (`addon/Forte_Timer/Module.lua:577,672`).**
The registration is new, the event is payload-bearing
(`(unitToken)`), and the branch is the target-death cleanup of the E5 liveness
law. `Forte_Timer/tests/test_expiry_identity.lua:21,410-438` proves the law at
the `Rows:TargetIsDead` seam only. Add a frame dispatch:
```lua
dispatch("UNIT_DIED", "Vile Poacher")   -- seeded castToken row
```
asserting the rows die, plus the inert leg (a GUID payload matches nothing).

**M5 — one announce row's spell is absent from the pinned build
(`addon/Forte_Messages/Pages/RaidMsg.lua:255`).**
All 20 `P.CAST_ROWS` (`RaidMsg.lua:168-300`) were checked against the pinned
data corpus (`mythicsim-forever-engine/data/{spells,items,enchants}.jsonl` +
`addon/Forte_*/Data/*.lua`): 19 of the 20 `spell` names appear in it, and the
one outlier is `"Ardent Defender"`. Its row registers three
settings keys (`ArdentDefenderCastParty/CastChannel/CastText`) and a
`ArdentDefender*` chat prefix (`:375-379,419-423,538-543`) that the consumer
(`Forte_Messages/Module.lua:502-525`) can never match. The options page shows
live-looking toggles with no effect. Fix: drop the row, or annotate it
`inertOnBuild = "70707"` and hide it from the page. (Checked and **refuted**:
the earlier suspicion about `"Salvation"` and `"Vigilance"` — both are present:
`addon/Forte_Paladin/Data/Paladin.lua`, `addon/Forte_Items/Data/Items.lua`,
`mythicsim-forever-engine/data/spells.jsonl`.)

## Minor

- **m1** `addon/Forte_Cooldown/Module.lua:624` — the UNIT_AURA slots are handed
  through locals named `unit, castGUID` (the handler's `:594` names, tuned for
  the cast events); the callee's parameter is `updateInfo`
  (`Core/Procs.lua:326`). Rename the call-site locals for the aura leg.
- **m2** `addon/Forte_Hunter/Core/Tools.lua:1061` — on the SENT leg, `a2` (the
  payload's target string) is passed into `OnShotCast`'s 4th slot, which is
  stamped as `row.castGuid` by the tracker. `Forte_Timer/Core/Rows.lua:269-273`
  treats `castGuid` as a GUID pair (and `castToken` is nil there, so the pair
  never fires). Inert today; pass `nil` on the SENT leg.
- **m3** `addon/Forte_Timer/Core/Casts.lua:647` —
  `Casts:OnFailed(spellID, target, now)` receives the **castGUID** as `target`
  from `Module.lua:639,642`; the parameter is unread in the body, so behaviour is
  right and the contract is a lie (the file's own convention names slot 2
  `sourceKey`, cf. `Casts:OnStart(spellID, sourceKey, now)`). Rename to
  `_sourceKey` and fix the header comment.
- **m4** `addon/Forte_Hunter/Pages/Hunter.lua:213-217` — the `OutOfCombatAlpha`
  tip states "default 0.0 = hidden out of combat, the WeaponSwingTimer
  in-combat-only law" while the shipped default is `1.0` (`:53`) and the module
  skin parks it visible. The options text and the shipped behaviour contradict
  each other; fix one (the tip, if `1.0` is the owner ruling).
- **m5** `addon/Forte_Hunter/Pages/Hunter.lua:158-160` — the `ShowLatency` row is
  labelled "needs launch probe … the strip is inert until the probe lands.
  Stored." while the strip **is** live: `UI/Swing.lua:1573` consumes
  `S.ShowLatency` through the `NetLatency` read (`Core/Tools.lua:1121-1137`,
  proven shape-picky by `tests/test_swing2.lua:912-964`). Relabel to "Live".
- **m6** `addon/Forte_Core/Core/Probe.lua:947` — the registrations run through
  `pcall(f.RegisterEvent, f, e)` over the `CaptureEvents` table (`:866-874`), so
  api-lint's literal-event scan cannot see them. Add the literals in a
  lint-visible position (or the table to the lint's allow-list) so a name typo
  is still caught.
- **m7** `addon/Forte_Core/Core/Locale.lua:371-375` — `LocaleModule.OnDisable`
  calls `Locale.state.frame:UnregisterEvent(...)` unguarded, against the tree's
  convention of pcall'ing it (`Forte_Timer/Module.lua:587-592`,
  `Forte_Messages/Module.lua:607-613`). Pre-existing file, touched in this
  window; guard it for symmetry.
- **m8** `addon/Forte_Cooldown/Core/Procs.lua:413` —
  `self._lastSweep = castGUID and GetTime()` stores the client's
  `UnitAuraUpdateInfo` table in a field whose name reads as a stamp. Use
  `GetTime()`.
- **m9** `addon/Forte_Cooldown/Core/Procs.lua:130-131` — `Procs:NameOf` returns
  the raw `C_Spell.GetSpellInfo(spellID).name` with no `pcall`/`PlainOrNil`
  (the file's own pattern is `:317-330`), and the header's "the ENGLISH key"
  claim (`:31-33`) is localisation-wrong. Only caller today is
  `Forte_ItemProcs/tests/test_item_procs.lua:113` — wrap it before any display
  path adopts it.
- **m10** `addon/Forte_Cooldown/Core/Procs.lua:336-339` — `Procs:ScanAll()` is a
  no-op alias, so the party/raid half of the proc feed rides the 0.5 s poll
  (`Forte_Core/Core/Init.lua` ticker) and the `UNIT_AURA` fast path is
  self-only (`Module.lua:581` registers `"player"`). Documented; keep the alias
  honest in `/fx status`'s gate row.
- **m11** `addon/Forte_Hunter/UI/Range.lua:188-196` — enabling the light turns
  the client's own ranged swing-range check on (`C_SwingTimer.EnableRangeCheck`),
  a client-wide side effect while the strip is shown. Opt-in, paired off,
  documented in the tip (`Pages/Hunter.lua:199-205`): acceptable, worth a line in
  the launch checklist.
- **m12** `addon/Forte_Cooldown/Module.lua:601` —
  `type(InCombatLockdown) == "function" and InCombatLockdown()` samples the
  read outside a `pcall` and truth-tests the raw value, against the tree's
  convention (`Core/Procs.lua:132-137`, `Forte_Timer/Core/Casts.lua:84-88`).
  Pre-existing (predates `4cf0cf0`), inside a handler this window changed.

# Clean checks (verified, no finding)

- Payload slot order at every registration site listed in §1 — no blocker, no
  major, in the whole window.
- Event-name string surgery: one site, correct offset.
- Secret-value law on every new aura/cooldown/unit/totem/comms/locale read (§3).
- Chat/comms legality gates; announce cast rows default OFF; no direct
  `SendChatMessage`; prefix register/unregister symmetric.
- No added login-time sound; the new sound row defaults OFF.
- Hidden-frame `OnUpdate` law in `Forte_Hunter/UI/Range.lua` and
  `Forte_Hunter/UI/Swing.lua`; no top-level `CreateFrame`; frames created inside
  the enable/login chain.
- `Forte_ItemProcs` (LoD) is reached only through `FX.LoadAddOnOnDemand` +
  `FX.ADDON_MARKERS.Forte_ItemProcs` (`Forte_Core/Core/Loader.lua:104`), its
  `.toc` carries `LoadOnDemand: 1` and `Dependencies: Forte_Core` — no
  always-loaded → LoD `Dependencies` edge.
- No `FX:CallSafe`, no `|` in Lua patterns, no `FX` top-level guard in the
  changed files (the tree-wide greps came back empty for the forbidden shapes).

# Open questions

1. Should the announce rows carry a data gate — resolve every `row.spell`
   through the pinned data at registration (or `C_Spell.GetSpellInfo`) so an
   inert row (M5) cannot be added silently?
2. `Forte_Cooldown.toc:7` lists `OptionalDeps: Forte_Items` only. The H7 split's
   LoD add-on is reached through the marker path — is that sufficient under
   PLAN §2.4 law 5, or does it need an `OptionalDeps` entry too?
3. `Procs:NameOf`'s English-key claim and the test-only consumer: is the proc
   display seam (the icon/CD display over the ICD windows) scheduled for Wave 4,
   i.e. is the data + ICD model's display half intentionally not wired yet?
4. `UnitData("target")` (`Forte_Timer/Core/Rows.lua:262`) is the undeclared §B7
   read the E5 liveness law leans on: is it on the launch-probe record in
   `docs/launch/04-*`?
5. Is `OutOfCombatAlpha = 1.0` the owner's ruling (fix the tip, m4) or a stale
   default (ship `0.0`, the in-combat-only law)?

# Checks for the main agent

Nothing was run here. After any of M1–M4 is implemented, run
`python3 scripts/gate.py --fast` (baseline PASS 562) — the new tests are the
only delta, and M5's row removal changes `#P.CAST_ROWS`-driven assertions in
`Forte_Messages/tests/test_cast_announce.lua` (the count assertion at `:231`,
the `:210-231` census loops).
