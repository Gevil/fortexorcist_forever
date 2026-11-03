# Upstream API refresh — 2026-11-03 (ApiScout2)

Inputs diffed locally: JBurlison/WoWAddonAPIAgents `f9269081..20585807` (clone at
`/tmp/upstream-api/apiagents`; our vendored slice `docs/api/wow-addon-api-agents/` spot-checked
byte-identical to `f9269081` — 6 sampled files `cmp` SAME, incl. the unit/spells/combat catalogs),
and Atraeau/WoW-Addons `b64aab0a` (clone at `/tmp/upstream-api/wowaddons`, head = that commit).
All catalog line cites: `Gethe/wow-ui-source@ca8368f2` = build 1.60.1.70532 ("old pin"),
`@aff0d8cd5` = build **1.60.1.70707** ("new pin" — exactly our installed client build).

## Answer first

1. **The catalog refresh lands our layer-1 pin on our own client build.** Upstream re-pinned Forever
   70532 → **70707** (`skills/wow-client-targets/references/targets.json`, diff at range tip: commit
   `aff0d8cd…`, verifiedAt 2026-11-03; 39 catalogs regenerated; 10250 → 10255 Forever records
   per `skills/wow-api-index/references/generated/manifest.json`). The "two builds behind" caveat in
   `docs/api/README.md` is retired by re-vendoring. **We must re-vendor.**
2. **Zero drift across everything we use.** Of the 86 catalog entries our addons touch
   (40 `C_*` calls, 40 registered/listed events, 5 `Enum.*` + `Enum.SwingType`-as-presence-probe,
   set extracted with `scripts/api_lint.py`'s regexes over `addon/**/*.lua` minus tests/Data),
   **all 85 declared ones are declaration-identical at both pins** (symbol-set + per-record
   declaration-hash diff over all 39 `forever.json` files; the 86th, `Enum.SwingType`, is undeclared
   at both pins and already carries an `api-lint: ok` presence-probe opt-out,
   `addon/Forte_Core/Core/Probe.lua:365,406`). The headline contracts keep their exact shape at
   70707: `UNIT_SPELLCAST_SUCCEEDED/START/FAILED/INTERRUPTED` =
   `(unitTarget, castGUID, spellID, castBarID?NeverSecret)` + `SecretWhenUnitSpellCastRestricted`
   (`UnitDocumentation.lua:4844` pin; payload dump at new pin identical);
   `PLAYER_SWING = (swingDuration, swingType)` vs
   `PLAYER_SWING_RANGE_UPDATE = (swingType, isInRange, checksRange)`
   (`SwingTimerDocumentation.lua:42,53`) — our
   two-handler rule stands; `CHAT_MSG_ADDON = (prefix, text, channel, sender, target,
   zoneChannelID, localID, name, instanceID)` at `ChatInfoDocumentation.lua:800` — line **and**
   payload unchanged; all `C_Secrets.Should*` and both `C_SwingTimer` functions unchanged.
   No event we register was removed (only additions: `PET_ORDER_MOVE_TO_PENDING_CHANGED`,
   `SETTINGS_HEADER_TEXT_UPDATE` — neither ours).
3. **Changed at 70707 (8 records; none on a call site of ours):**
   `C_Spell.IsSpellCrowdControl` `SecretArguments: AllowedWhenTainted → AllowedWhenUntainted`
   (`SpellDocumentation.lua:852`); `C_LossOfControl.GetActiveLossOfControlData(+ByUnit)` gained
   `SecretWhenLossOfControlRestricted` (new predicate, `SecretPredicatesDocumentation.lua:99/100`;
   `LossOfControlDocumentation.lua:10,25→26`); `DamageMeterCombatSource.specIconID` and
   `DamageMeterCombatSpellUnitDetails.specIconID` `NeverSecret → SecretValue`;
   `ForeverExperiencePreset.Modern → Enhanced`; `NamePartType` adds `Combined = 2`
   (`LocalizationSharedDocumentation.lua:19`, +1 field, NumValues 2→3);
   enum `VasTransactionPurchaseResult` insert. Removed: `C_GameRules.SetForeverExperiencePreset`
   (split into `…PreLogin/…PostLogin`), constant `LevelConstsExposed → LevelConstsExposed_Camelot`.
   Added: pet-order pair, `SETTINGS_HEADER_TEXT_UPDATE`, the LOC secret predicate, the two preset
   setters, the Camelot level consts. **None of these symbols occurs anywhere in `addon/`**
   (regex sweep incl. `Constants.`/`LevelConsts`/`C_GameRules`/`C_PetInfo`/`LossOfControl`/
   `IsSpellCrowdControl`/`NamePartType`/`Ambiguate`). The vendor's own migration guide for the range
   is the new file `skills/wow-client-targets/references/FOREVER-70707-CHANGES.md`
   (reviewed 2026-11-03, "118 relevant files, nine generated API definition files");
   `SOURCE-EVIDENCE.md` records the key negatives: **identity, aura and spell-info sources
   unchanged 70532 → 70707** — our aura/spell read paths and the §8 `FOREVER-FINDINGS.md:41`
   caveat quote are untouched by this refresh (file cmp-identical).
4. **Identity (`b64aab0a`): on Forever a character is `First Last`, `Name-Realm` is dead.**
   The commit's design journal states the law and the exact live-unknowns; the layer-1 catalog at
   our build pins the shapes (below). This breaks the premise of `FX.DB.CharacterKey`'s
   `-Realm` half and puts raw-name equality in the Warlock comms at risk; ranked fixes at the end.
5. **Atraeau's rest (last 2 weeks)** = King's Gambit master-looter work; four transferable client
   facts (§"Other Atraeau facts"): 255-byte addon-message cap enforced client-side; the same
   chat gate pair we use (validated shape); `issecretvalue`-guard-everything on event payloads;
   self-check-to-SavedVariables probe pattern. Hosted `docs/api/` (our layer 2) is unchanged —
   still build 70170.

## 1. WoWAddonAPIAgents `f9269081..20585807`

Range = 6 commits (`27f89ea`, `e8880c0`, `0269b25`, `ac7e3c7`, `53e9ace`, `2058580`); the only
addon-relevant one is `53e9ace` "Add persistent addon planning and refresh Forever 70707 APIs"
(release `docs/RELEASE-2.3.0.md`: package 2.2.0 → 2.3.0). Rest = updater/CI/plugin packaging
(nothing we vendor). `plugins/wow-addon-dev/skills/**` mirror `skills/**` 1:1.

### Symbol-level catalog diff (all 39 `forever.json`, old tree `git archive f9269081` vs new head)

```
TOTALS added=7 removed=2 changed=8   (of 10250 → 10255 records)
ADD  [wow-api-unit-player] event PET_ORDER_MOVE_TO_PENDING_CHANGED      PetInfoDocumentation.lua:225
ADD  [wow-api-unit-player] fn   C_PetInfo.IsPetOrderMoveToPending       PetInfoDocumentation.lua:130
ADD  [wow-api-lua-environment] secret SecretWhenLossOfControlRestricted SecretPredicatesDocumentation.lua:99
ADD  [wow-api-settings-system] event SETTINGS_HEADER_TEXT_UPDATE        GameRulesDocumentation.lua:396
ADD  [wow-api-settings-system] fn   C_GameRules.SetForeverExperiencePresetPreLogin  …:312 (…PostLogin :322)
ADD  [wow-lua-api] constants LevelConstsExposed_Camelot                 LevelConstantsDocumentation.lua:5
REM  [wow-api-settings-system] fn   C_GameRules.SetForeverExperiencePreset
REM  [wow-lua-api] constants LevelConstsExposed
CHG  [wow-api-combat] C_LossOfControl.GetActiveLossOfControlData(+ByUnit)  +SecretWhenLossOfControlRestricted
CHG  [wow-api-combat] DamageMeterCombatSource / …SpellUnitDetails          specIconID NeverSecret→SecretValue
CHG  [wow-api-spells-abilities] C_Spell.IsSpellCrowdControl  SecretArguments Tainted-allowed→Untainted-only
CHG  [wow-api-settings-system] ForeverExperiencePreset  Modern→Enhanced(=1)
CHG  [wow-lua-api] NamePartType  +Combined=2  (Linked to identity — see §2)
CHG  [wow-api-currency-economy] VasTransactionPurchaseResult  +ProxyNoMixedAlliance=56
```

Guide-text changes in range: combat `CURRENT-CONTRACTS.md` gains a **"Loss of control and
crowd-control classification"** section (LOC getters secret for everyone but active PvP
spectators/commentators; "no ordinary-player or out-of-combat exception");
`FOREVER-GAME-RULES.md` documents the preset split (`Enhanced = 1`, getter nil = unselected,
setters are Glue/Preset-panel mutations, "third-party addon access … requires client validation");
all domain SKILL.md files gained the pointer "For Forever 1.60.1.70707, also consult
FOREVER-70707-CHANGES.md before applying earlier build guidance"; `CURRENT-UI-SOURCES.md` notes the
foundational sources are unchanged at 70707. The bag/item-button/gamepad/menu/PvP/housing UI-helper
churn (`ContainerFrameItemButtonMixin:Initialize` signature +`containerFrame`,
`SmartNavigation_*` helpers, `Menu.IsMenuProxy`, `SelectButton` internal+secure-only) is
Blizzard-internal Lua, **not generated API** — we hook none of it.

### Check against our used set (40 C_ symbols, 42 events, 6 Enum refs)

Method: extracted with api_lint's own regexes; every used name's full record compared
(declaration JSON) between pins → **drift set empty; missing-at-either-pin set empty** (all used
names declared at both). Spot facts:
- `C_Secrets.ShouldAurasBeSecret/ShouldCooldownsBeSecret/ShouldUnitIdentityBeSecret/
  ShouldTotemSlotBeSecret`, `C_RestrictedActions.IsAddOnRestrictionActive`,
  `C_ChatInfo.{RegisterAddonMessagePrefix,SendAddonMessage,SendChatMessage,
  AreOutgoingAddonChatMessagesRestricted,InChatMessagingLockdown}`,
  `C_UnitAuras.*`, `C_Item.*`, `C_Container.*`, `C_Spell*`, `C_DurationUtil.CreateDuration`,
  `C_Timer.*`, `C_SwingTimer.{IsTargetWithinSwingRange,EnableRangeCheck}`, `C_AddOns.LoadAddOn`:
  **identical declarations at 70532 and 70707** (the 42 events likewise; `CHAT_MSG_WHISPER` —
  not ours — also unchanged at `ChatInfoDocumentation.lua:2591`).
- `Enum.SwingType` still **undeclared** at 70707 (only `Enum.PlayerSwingType` exists) — our
  presence probe remains a probe; keep the `api-lint: ok` opt-out.
- §8 risk "payload 4-field tolerance": `castBarID` is field 4 `Nilable, NeverSecret` at both pins
  — handler tolerance (mitigation 3) stays correct; mitigation 2 (`isActive`/`isOnGCD` NeverSecret)
  untouched by the range (`SpellSharedDocumentation.lua` not in the nine regenerated files).
- Stale cite to fix while re-vendoring: `Forte_Warlock/Core/Comms.lua:338` cites
  "UnitDocumentation.lua:2399" for `UnitName`; the declaration sits at **:2488** at both pins.

### What re-vendoring adds (files, our slice's layout)

`skills/wow-client-targets/references/FOREVER-70707-CHANGES.md` (new, must-have),
`skills/wow-addon-development/references/PROJECT-PLANNING.md` + 2 templates (new, optional),
regenerated `targets.json`/manifest/forever.json/EVENTS-*.md/symbols.json. `SOURCE.md`'s provenance
table + file index (233 files) and `docs/api/README.md`'s pin table must be updated: layer-1 pin →
`20585807` / data pin `aff0d8cd… 1.60.1.70707`; the "Two builds behind" phrasing is retired.

## 2. The identity finding (Atraeau `b64aab0a`, "a character is its first and last name")

Repo `github.com/Atraeau/WoW-Addons` head `b64aab0ab698e0c907deafc1d5e8b23ba6741b0a` (2026-11-01
-0800; journal entry "Decided by the guild leader" dated 2026-11-02). 43 files, +1057/−569.

### What it says Forever's character identity is

- **No realms exist on Forever** (author's premise, stated in the commit message and
  `docs/design-journal.md` entry). The identity is **(first name, last name)**; canonical string
  `First_Last`, display `First Last` (`src/KingsGambit/src/Identity.lua` header; `M.SEP = "_"`;
  `Normalize` splits on whitespace, `-`, `_`, and any *learned* separator).
- **No hyphen in names** — hyphen is retired from the name space because it used to mark a realm
  (journal: "no hyphen, because `short()` used to cut a name at it and would have conflated two
  characters sharing a first name").
- **The APIs (pinned in our layer-1 catalog at 70707 — I verified the exact records):**
  `UnitName(unit)` → `(unitName, unitServer)` — `SecretWhenUnitNameIdentityRestricted`,
  `SecretArguments AllowedWhenTainted` (`UnitDocumentation.lua:2488`);
  `UnitNameUnmodified(unit)` → `(unitName, unitServer)` — `SecretWhenUnitIdentityRestricted`,
  `AllowedWhenUntainted` (`:2522`); `UnitFullName(unit)` → `(unitName, unitServer)` —
  `SecretWhenUnitIdentityRestricted`, `AllowedWhenUntainted` (`:1223`). Each returns a "server"
  string **that the author treats as empty ("there are no realms"); he prints it raw in-game
  to confirm** (`RealClient:nameProbe`).
  `GetRealmName()` **exists** (`ConnectionDocumentation.lua:68`, returns non-nil `realmName`) — it
  is a *connection* label, not a character component; its content on Forever is unmeasured.
  `C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator(fullName)` → string
  (`NameUtilDocumentation.lua:10`, `SecretArguments AllowedWhenUntainted`) is the only name-split
  helper in the catalog; `ShouldDisplaySurname`, `C_NameUtil.GetNamePart`, `GetRealmNameNoColor`,
  `GetUnitName` are **not declared** at the pin (the author's probes guard them all — same shape).
  `Ambiguate(fullName, context)` exists (`PlayerScriptDocumentation.lua:21`); the 70707
  `NamePartType` gained `Combined = 2` — the only hard name-API signal in the range, and it points
  the same direction (first+last as one combined unit).
- **Full names carry a "surname separator" whose bytes are not documented** (exported APIDocumentation
  has only the hint quoted above). The author therefore **learns it at runtime**: diff
  `full` vs `ReplaceSurnameSeparatorWithLinkSeparator(full)` bytes (`Identity.LearnSeparator`),
  collect learned separators, split on them + whitespace + `-` + `_`.
- **Which name API is authoritative is an explicit live-game unknown** ("FIELD: confirm in the
  game"): `ShouldDisplaySurname()` *suggests* `UnitName` may omit the surname per the viewer's
  display settings — "which would make one character look like two". Their defense: ask all three,
  take the answer with the **most parts**; print raw returns + byte hex in `/gambit check`
  (`SelfCheck.lua:48-49`, persisted to `KingsGambitDB.selfcheck` for disk readback).
- **Every inbound name is normalized through the identity layer, every outbound name is returned
  in the game's own remembered spelling** (`RealClient:fromGame/toGame`; `rawOf` per identity).
  `CHAT_MSG_ADDON(prefix, text, channel, sender)` → `sender = fromGame(sender)`;
  `CHAT_MSG_WHISPER(text, sender)` likewise; whisper/`SendAddonMessage` targets go through
  `toGame(name)`. All event-payload strings pass a `safe()` `issecretvalue` guard first
  (`RealClient.lua:29-32`). No `Name-Realm`, no realm parsing anywhere in the addon.

### What it means for `FX.DB.CharacterKey` (`addon/Forte_Core/Core/Database.lua:163-185`)

Current law: `UnitName("player")` (spaces stripped) + `"-"` + `GetRealmName()` (spaces stripped),
falling back to `"ForteXorcist"` when the realm is empty → `AldricStormwind-ForteXorcist` on a
realm-less client. Premise damage, ranked:
1. **`-Realm` half is dead weight**: the key's historical job (uniqueness across realms in an
   account-wide `ForteXorcistDB`) doesn't exist. It is *consistent* per install (the realm half is a
   constant) so it degrades gracefully, but the Profiles UI actively teaches `Name-Realm`
   (`Forte_Options/Pages/Profiles.lua:158` tip) — a law we shouldn't ship on a realm-less client.
2. **The real hazard is the *name* half**: it is keyed on `UnitName`, the one name API whose
   surname is display-conditional in the author's reading. Two alts `Aldric One` / `Aldric Two`
   on one account collapse to one profile key the moment the theory holds. The catalog's own
   answer: prefer `UnitNameUnmodified`/`UnitFullName` (identity-restricted, not name-restricted)
   over `UnitName` (`AllowedWhenTainted` + `SecretWhenUnitNameIdentityRestricted` on the
   display-side API).
3. **Secret-poisoning hole in the current code**: `pcall` covers only the `UnitName` call
   (`Database.lua:172`); `name:gsub("%s+","")` (:174) runs on the result *outside* any pcall. A
   secret name string (`SecretWhenUnitNameIdentityRestricted` — combat lockdown) has
   `type(v) == "string"`, passes the `:173` guard, and the method call on it raises uncaught —
   during `PLAYER_LOGIN` init. A secret/raising read also must not be cached: `cachedKey` is a
   session-constant by design (:167-169) and a poisoned read is sticky. `FX.Compat.PlainOrNil`
   (the `issecretvalue`-first guard, `Forte_Core/Core/Compat.lua:42-49`) is the existing tool and
   is absent here.
4. If the key shape changes, it is a **migration** (schema v2 → v3: rewrite
   `profiles.characters`/`bindings` keys, add a `MIGRATIONS[3]`); pre-launch there are no real
   user DBs, so a clean cutover is also legitimate (owner's call; `test_database.lua:267-272`
   asserts the current law and must move with it).

### Warlock comms sender handling (`Forte_Warlock/Core/Comms.lua`, `Core/Group.lua`)

Verified-good, at the pinned pin: the file's "inbound law" comments (Comms.lua:61-66,
Group.lua:40-42) — `CHAT_MSG_ADDON` payload order `(prefix, text, channel, sender, …)` and
`sender/target` being plain non-nil `cstring` with **no secrecy annotation** — hold at 70707
(`ChatInfoDocumentation.lua:800` dump above). The dispatcher's "sender is the FOURTH" trap
(Comms.lua:560-563) matches the catalog.

The fragility is not secrecy, it's **string identity across sources**. The model keys
`Group.members`/`Group.summons` on raw strings from three places: (a) `sender` from
`CHAT_MSG_ADDON` (`OnAddonMessage`, :408), (b) `UnitName("raidN"/"partyN")` from `ScanRoster`
(:359), (c) self-name via `UnitName("player")` (`SelfName`, :301-303). Three laws ride on these
being byte-identical:
- **self-echo** `who == self:SelfName()` (:413) — CA-24 law;
- **summon-claim law** `a ~= who → drop` (:438-442) where `a` is the sender's self-encoding of its
  own `SelfName` and `who` is the wire's `sender` field;
- **roster merge** — `SetRoster` drops every member key the scan didn't list (Group.lua:113-137),
  so a sender-spelling ≠ scan-spelling silently deletes an FX-pair's comms state at the next
  `GROUP_ROSTER_UPDATE` (count columns, summon queue entries).
We never measured `sender` spelling vs `UnitName` spelling on a real client (the sim stubs it).
If the client spells them identically, all is moot; the author's architecture — every inbound
name from the game goes through one normalizer (`fromGame`), nothing compares raw strings —
is the pattern that makes the question moot. [INFERENCE: divergence would need the event layer to
re-spell names; the author normalizes both, so his code survives either answer.]

### Announce whispers (`Forte_Messages/Core/Announce.lua:177-201`)

`Whisper` sends `SendChatMessage(text, "WHISPER", nil, who)` where `who` is a roster-scan
(`UnitName`) spelling, lockdown-gated (`:91-95`, same pair as Atraeau's `c:whisper`/`c:announce`).
Same-law dependence as comms (name we send must be a name the game accepts as a whisper target) —
identical in shape to the author's `toGame(name)`, whose answer for game-sourced names is "send
the spelling the game gave us", which is exactly what we do. The one delta: our names ride on
`UnitName`'s display half, so under the surname-omit theory we whisper to a truncated target.
No change is forced pre-launch; add the probe.

## 3. Other Atraeau facts (commits 2026-10-28 → 11-03)

The rest is King's Gambit (master-looter) product work — ledger/simulator/guild-rank law; no
client-API content relevant to cooldowns/auras/secrets. Transferable facts:
- **`maxMessage = 255` on `C_ChatInfo.SendAddonMessage`** payloads
  (`RealClient` caps + `SendAddonMessageResult` reason-mapping incl. `invalidprefix → noprefix`;
  protocol chunks "under 255 bytes"). Our `C:Send` (Comms.lua:255-289) has **no client-side cap**;
  FXWK payloads are `<cmd> <name…>` short commands — safe on today's grammar; pin the cap in code
  before any richer payload (summon `by`/`target` full names make the worst case `SE <by> <tgt>`).
- **Chat gate pair mirrors ours**: they gate whispers/announces on
  `C_ChatInfo.InChatMessagingLockdown()` and comms on
  `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` (Comms.lua:204-208 / Announce.lua:91-95
  use the same pair) and re-evaluate on `ADDON_RESTRICTION_STATE_CHANGED` (Comms.lua:622,641
  registered + `chatLocked` re-reads per send ✓).
- **`issecretvalue` guard on every event payload string** before touching it
  (`RealClient safe()`) — our `FX.Compat.PlainOrNil` is the same discipline (fails closed), used
  consistently in Comms/Announce; §2.3 names the one site missing it (CharacterKey).
- **Self-check-to-SavedVariables probe pattern** (`SelfCheck.lua`, `/gambit check`,
  persisted `selfcheck` readable from disk after `/reload`) — the right model for our
  launch-day `/fx probe` (`Forte_Core/Core/Probe.lua`) identity block: print
  `UnitName/UnitFullName/UnitNameUnmodified` raw pairs, `ShouldDisplaySurname` presence,
  `ReplaceSurnameSeparatorWithLinkSeparator` byte-diff, `GetRealmName()` raw, learned separator.
- **`C_EncodingUtil.SerializeCBOR` + `EncodeBase64`** is their preferred comms encoding with a
  text fallback — a fact about a declared namespace we don't use; note only.
- **Layer-2 hosted `docs/api/` unchanged** (last regeneration `c3e03f9` build 70170, before the
  window): our `docs/api/README.md` layer-2 row stays valid.
- uiforever.com changelog tab (my row's tail item): the site is a JS app, not indexed, and
  **unreachable from this scout env** (no chromium for the browser tier; all four static
  changelog URL guesses 4xx). [INFERENCE: tab content is the hosted client's API notes; manager
  check via the existing `scripts/uif_battery.js` browser path, page `/app?flavor=forever`.]

## Open questions (probe on launch day, 2026-11-04)

1. Raw values: `UnitName`/`UnitFullName`/`UnitNameUnmodified("player")` (both returns),
   `ShouldDisplaySurname` presence/value, `GetRealmName()` content, separator bytes — the §2
   FIELD items (owner's: ours are the same unknowns).
2. `CHAT_MSG_ADDON.sender` spelling vs `UnitName(raidN)` in a 2-player group (the
   self-echo/claim/merge laws).
3. Which in-combat name reads are secret: `UnitName` under lockdown (drives the §2.3 hardening).
4. uiforever.com/app changelog tab contents (browser path only).

## Ranked: what we should change

1. **Harden `DB.CharacterKey` + identity law** — `addon/Forte_Core/Core/Database.lua`:
   read through `UnitNameUnmodified`/`UnitFullName`/`UnitName` (fullest wins), all of it inside the
   pcall incl. the `gsub`, `FX.Compat.PlainOrNil` the name (never cache a secret/failed read);
   drop the `GetRealmName` half → key = `First_Last` (learned-separator join; hyphen-free);
   schema v2→v3 `MIGRATIONS[3]` re-key (or clean cutover, pre-first-launch). Touches
   `Forte_Core/tests/test_database.lua:267-272`, `Forte_Options/Pages/Profiles.lua:158` tip,
   `Forte_Options/UI/Window.lua:277-282` (title keeps `GetRealmName` as a *label*, not identity),
   `Forte_Options/Core/Settings.lua:133`, PLAN.md §3.3/§9 row.
2. **Single name-normalizer for comms** (new `Forte_Core/Core/Identity.lua` — canonicalize +
   learned separator + remembered raw) applied in `Forte_Warlock/Core/Comms.lua`
   (`SelfName`, `OnAddonMessage`, `ScanRoster`), `Forte_Warlock/Core/Group.lua` (keys),
   `Forte_Messages/Core/Announce.lua` (whisper target = remembered raw). Add the
   raw-spelling field-probe line to `Forte_Core/Core/Probe.lua` + `docs/launch-day.md` F-checks.
3. **Re-vendor layer 1 to `20585807`** — `docs/api/wow-addon-api-agents/**` (add
   `skills/wow-client-targets/references/FOREVER-70707-CHANGES.md`), rewrite
   `docs/api/wow-addon-api-agents/SOURCE.md` provenance (pin 70707, package 2.3.0) and
   `docs/api/README.md` layer-1 table ("OUTRANKS" ladder unchanged; client stays above).
   `scripts/api_lint.py` needs no change (used set declares identically; 2 new events are inert).
4. **Stale cites:** `Forte_Warlock/Core/Comms.lua:338` `UnitDocumentation.lua:2399 → :2488`;
   PLAN.md §8 "Core premise" line keeps citing `FOREVER-FINDINGS.md:41` (verified unchanged);
   add §9 entries for the 70707 re-pin and the identity law.
5. **Pin the comms cap:** length guard `≤ 255` (measured law: Atraeau `maxMessage`; our own client
   measure = launch-day probe) in `Forte_Warlock/Core/Comms.lua:Send` + count, before any payload
   grammar growth.
6. **No-action records** (documented so nobody re-opens): LOC/CC-classification tightening —
   unused (CC announces are name-driven, no `C_LossOfControl`/`IsSpellCrowdControl` call sites);
   damage-meter `specIconID` secrecy — no meter code; presets/level-consts/pet-order/settings
   header — unused surfaces; `Enum.SwingType` probe unchanged.
