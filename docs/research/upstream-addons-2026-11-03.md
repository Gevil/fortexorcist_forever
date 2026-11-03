# Upstream addons + the installed client: what is new for us (2026-11-03)

Row: `PLAN.md` §11.2 Iteration I, "Reference" (`RefScout2`). Scope: CooldownMaster
`e5811752` (v2.0.4), WeaponSwingTimer SixxFix (Forever files), Thunderz96/forever-addon-kit,
and the live `_forever_` install read read-only. No other repo file touched.

Citation keys:

- `CDM@e5811752 <path>:<line>` — clone `/tmp/cdm2` (head `e5811752`, 2026-10-28,
  "v2.0.4 - Test Mode fixes").
- `SVFix@c1591b1 <file>:<line>` — clone `/tmp/svfix` (head 2026-09-25).
- `kit@8dc2976` — clone `/tmp/fak` (head 2026-09-25, unchanged since our studies).
- `install: <AddOn>/<path>:<line>` — `_forever_/Interface/AddOns/` as pinned by
  `scripts/deploy.sh` (the path in `PLAN.md` §6). **Re-verified in a final pass at
  2026-11-03 19:2x.** The tree is *live*: between my 19:14 and 19:25 passes the generated
  files under `Interface/` vanished, and `EllesmereUI_Flyouts.lua`,
  `EllesmereUI_ChatBar.lua`, `Questie_CVarWatchdog.lua`, `WhisperMessenger/Sources/Meta.lua`,
  `TidyPlates_ThreatPlates/CVarsManager.lua` were removed/renamed and line numbers shifted
  inside `EUI_ResourceBars_SwingTimer.lua` / `Mine.lua`. Citations that existed only in the
  19:14 pass are marked `(observed; rotated)`. Treat every `install:` line number as a
  *fingerprint of a moving target*: the law it carries is corroborated by a second source
  wherever one exists, and §9's change items name the law, not the line.

## Answer first

| Asked | The new answer (2026-11-03 evidence) | Adopt? |
|---|---|---|
| Secret values in combat | The shipped set gates **per-domain *and* per-spell**: `C_Secrets.ShouldAurasBeSecret()`, `ShouldCooldownsBeSecret()`, `ShouldSpellAuraBeSecret(spellID)`, `ShouldUnitIdentityBeSecret(unit)`, `ShouldUnitThreatValuesBeSecret()` are all live in addons shipping for this product. CooldownMaster encodes the throw-laws we only had as prose: a secret as a **table key poisons the table**, a secret in a **`table.sort` comparator throws**, a **boolean test on a secret boolean throws** (`UnitIsDeadOrGhost("player")` can be secret). | yes (§9.4) |
| Cooldown/aura APIs readable | `C_Spell.GetSpellInfo(id) -> {name, iconID}` is readable in combat (the community's name+icon path, fallback icon `134400`). `C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL"/"HARMFUL\|PLAYER")` is the record form and its **first return means "an aura exists at this index", not "it read plain"**. `C_Item.GetItemInfo` / `GetItemIconByID` are **async** ("nil until the item is cached"). `C_Spell.GetSpellCooldown` table carries `modRate`. `C_EventUtils.IsEventValid(event)` is the shipped capability probe. | yes (§9.4, §9.5) |
| PLAYER_SWING | A shipped-for-Forever swing timer (EllesmereUIResourceBars) gives the full client law: rows exist **while `UnitAttackSpeed` reports a speed for that slot**; the fill is **engine-driven** (`C_DurationUtil` + `SetTimerDuration`, no Lua per frame); `PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange)` is 3 returns and `IsTargetWithinSwingRange` **nil = "no check possible", not out-of-range**; the client's own Auto Shot/wand aim window is `AIM_TIME = 0.5` with the GO edge at `end - 0.5 - latency`; `GetNetStats()` **3rd = home latency, 4th = world latency (ms)** — the Gap-12 shape, from two shipped readers. MikScrollingBattleText publishes **measured windows on `1.60.1.70450`/`70374`**: melee swing→hit ≈0.45 s, shot→hit 0.58–0.66 s (1.50 s long range), a hit can be held a whole extra animation, **pet swings and extra attacks send no `PLAYER_SWING`**, DoT ticks land within ±0.03 s. | yes (§9.2) |
| Addon comms restrictions | `RegisterAddonMessagePrefix` results are `0=success, 1=duplicate, 2=invalid, 3=toomany` — a real **prefix budget**. `SendAddonMessage` results `3=AddonMessageThrottle`, `8=ChannelThrottle` are **retryable**, and the shipped law is: classify by enum *name*, throttle → back off (NeedRoll: 600 s quiet, 3 strikes stop the session), Lockdown/Restriction → re-queue at the head, anything else → drop; the outbox lives in SavedVariables "so nothing is lost to a boss fight's addon message lockdown or a /reload". Prefix registers at `PLAYER_LOGIN`, the channel join runs **15 s after `PLAYER_ENTERING_WORLD`** so a realm channel does not take a game channel number (ten-channel cap), 600 s keep-joined ticker. `addonChatRestrictionsForced` is checked by shipped code — our gate misses it. | yes (§9.3) |
| SavedVariables | The SVFix author declares the loader bug **fixed by Blizzard** (`SVFix@c1591b1 README.md:1-5`), and the live `_forever_` install agrees: **1 of 33** TOCs carries the stamp and its `ForeverSVFixData` link is **dangling** (points at the retired `_classic_beta_` compatdata path). The reference set (CooldownMaster 2.0.4, EllesmereUI 9.7.2, TidyPlates, Auctionator, NeedRoll, WarEffortScout, WhisperMessenger) ships **plain** `## SavedVariables:` / `## SavedVariablesPerCharacter:`. Load order: the client restores SavedVariables **before** the addon's files; `## LoadSavedVariablesFirst: 1` is the declared request for that ordering, and an addon that defaults its DB at file-load overwrites the restore. `C_AddOns.GetAddOnMetadata(folder, key)` is the sanctioned marker read (32 installed files). | yes (§9.1) |
| Test Mode | CooldownMaster v2.0.4's demo is a **synthetic entry set**: ids in a private range (`TEST_ID_BASE = 95000000`) so the spellID-keyed map cannot collide, names/icons **donated from the player's own tracked pool** by category, durations spread evenly across `[5, 120]` s, `_source = "test"`, `_testDur` for the loop; **entries carry no `dObj` and no `itemID` — "keeps test entries off the secret-value path, so the demo renders the same on every flavor"** (`CDM@e5811752 Core/Engine.lua:3973-3974`); the tick re-arms expired entries and **auto-turns Test Mode off when the pool drains** ("leaving testActive set would suspend every real data path"); the v2.0.4 delta is exactly the missing gates (`testActive` in `ScanBuffs`/`SyncOffensiveEntry`) so live auras cannot bleed into a demo. | yes (§9.6) |

Source deltas: **CooldownMaster v2.0.4 adds no new client law** (our notes already studied
v2.0.4 — §8.1) — its delta is Test-Mode hygiene only. **No WeaponSwingTimer Forever file is
newer than v1.60.2**, and the public source repo is *behind* the shipped build (§8.2).
**forever-addon-kit is unchanged** at `8dc2976` (§8.3).

## 1. Secret values in combat

Laws, all from code shipping for this product:

- **Per-spell and per-unit secrecy predicates are the shipped gate set.**
  `install: EllesmereUIAuraBuffReminders/EUI_AuraBuffReminders_Auras.lua:30`,
  `EllesmereUICooldownManager/EUI_CDM_HookIconWatch.lua:845`,
  `EllesmereUIQoL/EllesmereUIQoL_RaidBuffCheck.lua:138` (`ShouldAurasBeSecret()` **and**
  `ShouldSpellAuraBeSecret(spellID)` in one gate);
  `EllesmereUIActionBars/EUI_ActionBars_Disposal.lua:191` (`ShouldCooldownsBeSecret()`);
  `MikScrollingBattleText/Combat/Reader.lua:855`;
  `Lueur/Lueur.lua:1386-1387` (`ShouldUnitIdentityBeSecret(unit)`);
  `EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_ThreatData.lua:9`
  (`ShouldUnitThreatValuesBeSecret()`).
  We use exactly two (`Forte_Cooldown/Module.lua`'s `ShouldCooldownsBeSecret` /
  `ShouldAurasBeSecret` snapshot). The per-*spell* form matters for our aura-rider path:
  a specific cast's aura can be readable while the domain is secret (or the reverse).
- **Threat has a secrecy predicate on this client.** Our survey conclusion "no threat API on
  70707" is a *declared-name* result; an addon family built for this product ships a threat
  feed file and calls `ShouldUnitThreatValuesBeSecret()`. `[INFERENCE]` the predicate exists
  because a threat surface exists (server-pushed). Launch probe:
  `C_EventUtils.IsEventValid("UNIT_THREAT")` + `type(UnitThreat) == "function"` +
  `C_Secrets.ShouldUnitThreatValuesBeSecret()`.
- **Throw shapes** (`CDM@e5811752`): `Core/Engine.lua:202` "A secret value used as a table key
  poisons the table, so nothing read off an aura record is trusted"; `:224` "a secret name
  throws in the Filters page's `table.sort`"; `:4211-4212` "Dead-ness may read secret on this
  engine, and a boolean test on a secret boolean throws" — and they use it as a *guard value*
  (`... and not dead and ...`, `:4213`), so `UnitIsDeadOrGhost("player")` is on the
  secret-prone list.
- **Aura records**: `CDM@e5811752 Core/Engine.lua:208-217` — the first return of
  `GetAuraDataByIndex` means *an aura exists at this index*; "Treating an unreadable buff as
  the end of the list stops the sweep early". `:224-225` — "HARMFUL|PLAYER is what makes an
  aura 'ours' here (`sourceUnit` reads secret)"; name and icon are re-resolved from the
  `spellID` instead. These two are the same walls our `Forte_Cooldown` sweep works around:
  our "in-combat a sweep cannot prove removal" law is the community's, reached independently.
- `CDM@e5811752 Core/Engine.lua:3450`: "Forever's cooldowns are secret in combat like
  retail's, so it falls through to the retail reader" — the exact shape of our read-tier
  ladder (`Forte_Cooldown` tiers), independently reached. `InCombatLockdown()` gates the tick
  (`:4215`) = our `FX.SecretState`.
- `CDM@e5811752 Core/Compat.lua:56-60`: `GetSpellName`/`GetSpellIcon` "are not gated here (they
  take a spell name, not an id)" — the **name-keyed** form is the readable form; the law
  behind our `ByClass`/name-keyed tables.

## 2. Cooldown / aura APIs that are readable

- `CDM@e5811752 Core/Engine.lua:193-198` — `C_Spell.GetSpellInfo(spellID)` → `info.name`,
  `info.iconID`; the `UNKNOWN_ICON = 134400` fallback (`:3879`, returned at `:197`). This is
  the **in-combat-readable name+icon channel**; `GetSpellInfo` is absent from our API-LINT
  allow-list and from our icon code path.
- `CDM@e5811752 Core/Engine.lua:248-256` — item name/icon:
  "Instant path: nil until the item is cached; `addItem`'s ItemMixin fills it in async"
  (`C_Item.GetItemInfo(itemID)`, `C_Item.GetItemIconByID(itemID)`), plus the method form
  `item:GetItemIcon()` (`:2940`). **Item metadata is async on this client** — a law for
  `Forte_Items`, `Forte_ItemProcs` and `Forte_Timer/UI/Trinkets.lua`, whose icon paths assume
  a synchronous read. `ItemUtil.GetIconByItemID` (our allow-list name) has **0 uses** in the
  installed set; `GetItemIconTexture(itemID, size)` is the community's 12.x name, kept behind a
  shim (`install: TidyPlates_ThreatPlates/ItemUtilShim.lua:5-19` (observed; rotated)).
- `CDM@e5811752 Core/Compat.lua:25-33` — the `C_Spell.GetSpellCooldown` table:
  `startTime, duration, isEnabled, modRate` (they forward `modRate`). Our
  `Forte_Core/Core/Probe.lua:241` already records `g.rate = K(ci.modRate)`; the law to make
  explicit is that **`modRate` is the haste/haste-scale multiplier riding the cooldown record**
  (companion read: `IsHasteEffectApplied` / `IsHasteEffectKnown`, 16 installed files, e.g.
  `TidyPlates_ThreatPlates/HasteReader.lua:12` (observed; rotated)) — it belongs in the
  Forte_Timer GCD/swing math.
- `CDM@e5811752 Core/Engine.lua:257-262` — "SPELL_UPDATE_COOLDOWN fires 20-50 times/sec", so
  handlers are hoisted to module scope to avoid a closure per fire. Rate budget for our
  hot-path law (§3.7 cost law).
- `install: MikScrollingBattleText/Combat/Context.lua:60-61` — `C_EventUtils.IsEventValid(event)`
  is the **shipped capability probe** (13 installed files, incl.
  `EllesmereUIActionBars/EUI_ActionBars_Setup.lua:1026`): an addon asks *the client* whether an
  event exists before registering it, instead of catching the raise. `scripts/api_lint.py`
  enforces the static half (literals ⊆ catalog); this is the dynamic half for
  cross-build-safe probes (`PLAYER_SWING`, `COMBAT_LOG_MESSAGE` probes at the same file).

## 3. PLAYER_SWING and the swing timer

The reference: `install: EllesmereUIResourceBars/EUI_ResourceBars_SwingTimer.lua` (1787 lines,
Forever-only, header at `:2-46`; the same file's line numbers moved +/− 53 between 19:14 and
19:25 — the 19:2x set is what the numbers below are).

- `:5-6` "Addons lost the combat log in 12.0 (no SWING_DAMAGE / SWING_MISSED), so the classic
  swing-timer recipe is dead. Forever instead ships a native timer (`Blizzard_SwingTimer`,
  `AllowLoadGameType camelot`) and the API under it".
- `:8-12` the API surface: `PLAYER_SWING(swingDuration, swingType)` — one per player swing;
  `C_SwingTimer.EnableRangeCheck(swingType, bool)` — **opt in** to range edges;
  `PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange)` — **three** returns
  (our survey records two); `C_SwingTimer.IsTargetWithinSwingRange(swingType)` —
  **`nil` = "no check possible" (no target / untargetable / no weapon), NOT out of range**
  (the file's law text: "so it is not a reason to stop the bar");
  `Enum.PlayerSwingType.MainHand | OffHand | Ranged` (`:51` cites
  `SwingTimerDocumentation.lua: 0/1/2`).
- `:16-23` **row law**: "A row exists while `UnitAttackSpeed` reports a speed for its slot
  (Main Hand always does); the frame shrinks to the rows shown"; Combine Hands overlays the
  Off Hand row on the Main Hand bar with its own spark riding its own engine-timed fill.
- `:25-31` **the fill is engine-driven**: `PLAYER_SWING` re-sets the row's `C_DurationUtil`
  duration object and arms `SetTimerDuration` so **the engine animates the fill with no Lua per
  frame**, the remaining-time text is an engine duration-text binding through a tenths
  formatter, and Lua runs only at a swing's edges (start, deadlines, Stop by, the last
  latency). `:53-60` the capability gate:
  `C_SwingTimer and Enum.PlayerSwingType and C_DurationUtil and C_DurationUtil.CreateDuration
  and Enum.StatusBarTimerDirection and Enum.StatusBarInterpolation`; a re-arm uses
  `Enum.StatusBarInterpolation.Immediate` because "a restart mid-swing must not ease back from
  the old fill". `:36-42` an idle row costs nothing (a finished duration paints a static state).
- `:123-125` **`AIM_TIME = 0.5`; `AIM_CLASS = { PRIEST, MAGE, WARLOCK, HUNTER }`** — the
  client-family's own aim/wand window, and exactly the class set that needs the wand/Auto Shot
  aim phase. `:828-830` `row._rtt = NetLatency() or 0`, `row._aimAt = row._end - AIM_TIME -
  row._rtt`; `:1416` `local shot = now + AIM_TIME + (NetLatency() or 0)`.
- `:575-579` **`NetLatency()` = `local _, _, home, world = GetNetStats()`** — the 3rd return is
  home latency, the 4th is world latency, in ms, world preferred;
  `install: EllesmereUIResourceBars/EUI_ResourceBars_CastBar.lua:1221-1224` the same pair with
  the comment "home/realm value only while world latency hasn't been measured yet". This
  settles the *shape* of survey Gap-12 / `PLAN.md` §B12: our
  `Forte_Hunter/Core/Tools.lua:996-1003` reads only the 4th and must fall back to the 3rd.
  `[INFERENCE]` the units (ms) and the home/world pairing; the names are the shipped readers'.
- `:33-36, :1481-1507` the state machine is event-driven:
  `ACTIONBAR_UPDATE_STATE` + the auto-attack/auto-repeat edges carry "queued, on, waiting", and
  `PLAYER_STARTED/STOPPED_MOVING` are **registered only while** a wand or Auto Shot is on with
  the movement mode. A row whose attack is on with no swing running parks full.
- Measured windows, `install: MikScrollingBattleText/Combat/Mine.lua:65-108` (pinned to builds
  in the comments — the most transferable numbers found today):
  - melee swing → its hit report ≈**0.45 s** (a hunter's 21 swings: **0.446–0.453 s**,
    `1.60.1.70450`, 19 Oct 2026); the swing line and its hit can arrive in one frame;
    `SWING_WINDOW = 0.5`, learned per-hand spreads 0.417–0.473 / 0.661–0.741;
  - wand/bow **shot → hit 0.58–0.66 s** (battleground, `1.60.1.70374`), 1.50 s at long range →
    `RANGED_WINDOW, RANGED_UNSURE = 2.0, 1.5`;
  - a hit can be held a whole extra animation: a rogue's at **0.98–1.01 s** 27/180 times, 22 with
    an ability between (`DELAYED_FROM, DELAYED_TO = 0.25, 0.9`; "Hits in that window do not
    teach the delay");
  - **`LATE_SWING = 0.35` — "a swing may follow its hit by this much"**: the event/report order
    is not fixed, so our hit-pairing must accept both orders (our swing bar pairs only one);
  - **`PET_GAP = 1.0` and "pet swings and extra attacks send no `PLAYER_SWING`"** (`:110`) —
    the pet's swing cadence is *inferred* (≤1/s), never event-driven;
  - DoT tick cadence is server-exact: Corruption's 1st/2nd ticks at 3.00/6.00 s within ±0.03,
    Agony's at 2.00/4.00 within ±0.02 (`TICK_SLACK = 0.15`) → the law behind our DoT bars;
  - `install: MikScrollingBattleText/Combat/Mine.lua:12-13` states the secrecy posture
    independently: "the combat log is closed (no SPELL_DAMAGE, SWING_*, UNIT_COMBAT);
    UNIT_COMBAT amounts are public", and `PLAYER_SWING` "has **no secrecy rule**
    (SwingTimerDocumentation)".
- Pet/range extras: `install: EllesmereUIForeverEssentials/EllesmereUIForeverEssentials_PetSummon.lua:88`
  uses `UnitInVehicle("pet")` for the stable/kennel law (the same wall our §3.2 note records);
  `GetRangeIndicator()` is readable and reports `0 short / 1 medium / 2 long / 3 out of range`
  (`install: TidyPlates_ThreatPlates/Ranges.lua:11-19` (observed; rotated)) — a second,
  built-in range signal for the Hunter range light; `IsRangedUnitWithinSwingRange` is used once
  in the installed set (declare it for `api_lint.py`).

## 4. Addon comms restrictions

- **Prefix budget**: `install: EllesmereUI/Libs/LibKeystone/LibKeystone.lua:14-17` —
  `local result = C_ChatInfo.RegisterAddonMessagePrefix("LibKS")` with the comment
  `0=success, 1=duplicate, 2=invalid, 3=toomany`, and `result > 1` treated as a hard failure.
  Our `Forte_Warlock/Core/Comms.lua:580-606` maps `0/1 → ok`, non-numeric → `okUnlabelled`,
  `1 → duplicate`, else `refused:<n>` — right shape; `2 = invalid`, `3 = toomany` are now
  *named* failures (a shared per-session registry, so a busy install can deny us), and the
  `/fx status` label plus a degrade row should name them.
- **Send results**: `install: Questie/Libs/AceComm-3.0/ChatThrottleLib.lua:349-355`
  (identical copies under `TidyPlates_ThreatPlates/`, `SilverDragon/`) declare the client's
  `Enum.SendAddonMessageResult` fallback set `Success = 0, AddonMessageThrottle = 3,
  NotInGroup = 5, ChannelThrottle = 8, GeneralError = 9`;
  `install: TrueshotLodge/src/share.lua:56` — `THROTTLED = { [3] = true, [8] = true } --
  SendAddonMessage results: addon / channel message throttle`. Our
  `Comms.lua:276-282` folds every `result > 0` into `sendFailed + 1`: throttles are
  **retryable**, and counting them as failures feeds the `commsFail` degrade thresholds with
  noise.
- **The shipped throttle discipline** (`install: NeedRoll/Core/Drops.lua`):
  `:628-630` `DAILY_MAX = 100`, `THROTTLE_PAUSE = 600` (seconds of quiet after the game says
  throttled), `THROTTLE_STOP = 3` (throttled answers after which sharing stops **for the
  session**); `:638-654` `SendResultName`/`Refusal` classify the numeric code by enum **name**
  (`Throttle` → "throttled", `Lockdown`/`Restrict` → "later"), everything else is dropped "like
  a sent one"; `:736-765` the outbox pump re-queues at the head with `RETRY` and counts a daily
  budget; `:13-15` the outbox lives in `NeedRollDB.dropOutbox` "so nothing is lost to a boss
  fight's addon message lockdown or a /reload"; `:14-15` "at most one a minute and at most
  DAILY_MAX a day, to stay well clear of the game's throttling".
- **Join timing and the channel budget**: `install: NeedRoll/Core/Drops.lua:1673-1679` —
  `C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)` on `PLAYER_LOGIN`, then
  `C_Timer.After(15, JoinChannel)` with "After the game's own channels (General, Trade, ...)
  have been joined, so the realm channel doesn't take one of their numbers", plus a
  `C_Timer.NewTicker(600, KeepJoined)` and `:565-566` a re-join guard; `:1768` "The game allows
  ten chat channels; /chatlist shows yours"; `:543-545` `GetChannelName(old)` probes an old
  channel name before `LeaveChannelByName`. `install: TrueshotLodge/src/share.lua:6-11` the
  same law in prose: two hidden channels (a global one plus a per-zone one joined *as a
  temporary channel*), "Both are kept after every other channel you are in, so they never take
  the numbers of the game's own channels".
- **Rate budget** `install: TrueshotLodge/src/share.lua:47-56`: 255-byte packed lines,
  `SEND_EVERY = 0.5` after a `BURST = 4`, `QUEUE_LIMIT = 400`, `WHISPERS_PER_MINUTE = 30`,
  `CHANNEL_REACH = 600`, `OFFLINE_SKIP = 600`, and `:56`'s throttle set. Transport law (the
  one-hop, no-relay, `shared_by`-credit, never-replace-own-records set) at `:12-15`, the
  whisper-as-reachability-fallback law at `:16-20` (a channel's reach is not global; the
  offline probe is the client's own `"No player named 'X' is currently playing."` line).
  `install: WarEffortScout/WarEffortScout.lua:206-219` the same 250 ms cadence with the
  stated budget "the server's rate limiter punishes bursts: ten messages in one second is the
  ceiling. A raid's roster goes out over ten seconds, not in one frame".
- `install: WarEffortScout/WarEffortScout.lua:193-195` — "the server will not deliver raid
  broadcasts to a party-only player: the send answers `Success` and nothing comes back", so a
  zero-delivery success is legal: our `Forte_Messages` group-target path needs a
  "who-can-reach-me" gate, not a send-result check. `:226-227` "the addon channel prefix is a
  registered constant: an unknown prefix is dropped silently, so the channel carries only our
  traffic" = the kit's law, independently.
- `install: EllesmereUIChat/EUI_Chat_EditBox.lua:308`, `EllesmereUI/EllesmereUI.lua:3648`,
  `EllesmereUIChat/EllesmereUIChat_SessionHistory.lua:70` — shipped code gates on
  `addonChatRestrictionsForced`; `InChatMessagingLockdown` appears in 12 installed files.
  **Our `Forte_Messages/Core/Announce.lua:196-206` gates the two `C_ChatInfo` predicates and
  not the CVar.**
- Identity (feeds `ApiScout2`'s row): `SVFix@c1591b1 CHANGELOG.md` 1.0.3 — "Fix per-character
  [SavedVariables] for WoW Forever's **required first-and-last-name character identities**",
  "Match the runtime full name first, with safe unique fallbacks", "Tolerate character names
  represented by **multiple path components** under the WTF realm folder";
  `install: WarEffortScout/WarEffortScout.lua:136-137,167-169` — the identity split law, the
  realm-suffix law and the "the game's own roster names carry the realm suffix and will not
  read" wall; the whisper-address law `C_PartyInfo.GetLocalPlayerName()` + "the game's
  `Full Name` whisper form needs the realm-less name as the player has it; the realm-suffixed
  form is answered 'No player named X is currently playing.'"
  (`install: EllesmereUINameplates/EllesmereUINameplates_ChatLink.lua:451-469`
  (observed; rotated)).
- No installed addon queries a prefix registry (`C_ChatInfo.GetRegisteredAddonMessagePrefixes`
  → 0 hits), so the kit's "unknown prefix = silent drop" stays the only published rule.

## 5. SavedVariables behaviour

- **The workaround's author retired the problem.** `SVFix@c1591b1 README.md:1-5`: "It seems
  that Blizzard have fixed the issue. You should be able to safely uninstall now." (with the
  IMPORTANT block below it still warning "while the WoW Forever SavedVariables loader bug
  exists"). Head date 2026-09-25.
- **The live install agrees.** Of 33 installed add-on folders, exactly **one** TOC carries a
  stamp — `install: EllesmereUIForeverFix/EllesmereUIForeverFix.toc:8,11,15`
  (`## X-ForeverSVFix-URL: https://github.com/nobewayo/ForeverSVFix`, `## X-ForeverSVFix: 5`,
  and the injected `ForeverSVFixData\EllesmereUIForeverFix.lua` load line) — and its
  `ForeverSVFixData` directory is a **dangling symlink into the retired `_classic_beta_`
  compatdata path** (the pre-launch product folder; `WTF/Account` under it no longer exists).
  `CooldownMaster.toc:6` (`## SavedVariables: CooldownMasterDB`),
  `EllesmereUI.toc:6`, `TidyPlates_ThreatPlates.toc:12` (three names on one line),
  `Auctionator.toc:24` (`SavedVariablesPerCharacter`), `WarEffortScout.toc:15`,
  `NeedRoll.toc`, `WhisperMessenger.toc` all ship plain, unpatched headers. The newest
  reference addon in the set is CooldownMaster 2.0.4 (2026-10-28).
- **Load order and `LoadSavedVariablesFirst`.** `SVFix@c1591b1 RELEASE_NOTES_v1.0.1.md`:
  "Some addons initialize their SavedVariables globals to defaults while their normal Lua/XML
  files load. ForeverSVFix v1.0.0 restored data **before** those files, which allowed those
  addons to overwrite the restored values again. v1.0.1 restores … **after** the addon's
  normal files by default, matching WoW's normal SavedVariables timing more closely. Addons
  that explicitly declare `## LoadSavedVariablesFirst: 1` keep their requested pre-script
  behavior." The client's own ordering is therefore *data first, then files*; the header is
  the declared opt-in for the pre-script order, and
  `install: Questie/Questie_Vanilla.toc:29` (+ `_Vanillplus`/`_Wrath`/`_Mists`/`_TBC`/`_Camelot`,
  8 files total, used at `Questie.lua:354`) is the shipped use. Our TOCs declare neither form.
- **Per-character is a client feature, not our scheme**: `SavedVariablesPerCharacter:` in 31
  installed TOCs (e.g. `Auctionator.toc:24`, `TidyPlates_ThreatPlates.toc:26`
  (`ThreatPlatesPerCharacterDB`), `WarEffortScout.toc:19`, `WarEffortScout.lua:234`
  "it rides the add-on's own SavedVariables (`SavedVariablesPerCharacter: WarEffortScoutLog`),
  and keys every entry by character so a shared account cannot leak"). Our
  `FX.DB.CharacterKey` prefixing (`Forte_Core/Core/Util.lua`) is portable and redundant with
  the client's own mechanism; the **SVFix identity law above is the constraint**: the
  per-character key is the *full* "First Last" name and the WTF path splits it across
  components, so our key must not assume a single token, a space-free name, or a stable order.
  `[INFERENCE]` for our key's shape; the SVFix changelog wording is primary.
- `C_AddOns.GetAddOnMetadata` is live and heavily used (32 installed files:
  `Auctionator/Source/Variables/Main.lua:13`, `TidyPlates_ThreatPlates/Init.lua:462`,
  `MikScrollingBattleText/MikSBT.lua:45`, `EllesmereUIForeverFix.lua:37`); the SVFix stamp's
  whole purpose is to be readable through it (`CDM@e5811752 Core/Compat.lua:64-72` states
  exactly that, alongside `IsAddOnsLoaded()` / `IsAddOnsForcedDisabled()` as camelot-only
  globals). `C_AddOns.GetAddOnList()` is in the declared catalog
  (`tools/api-survey/api.json:14725`) and is the declared enabled-set enumeration
  (`install: EllesmereUI/EllesmereUI_ChatBar.lua:202,264` (observed; rotated)) — so
  `Forte_ChatBar/Module.lua`'s `siblingTidyPlates()` returning `"unknown"` is a *choice*, and
  the launch probe can settle it.
- Live WTF state (read-only, 19:1x): `WTF/Account/GREATESTEVIL/SavedVariables/` holds
  `.lua` + `.bak` pairs (`CooldownMaster.lua` + `.bak`, `EllesmereUI.lua` + `.bak`, …, the
  pair timestamps 17:52 → 18:25 = a tool pass then a client run, 2026-10-23), and
  `WTF/Account/SavedVariables/` holds the account-wide copies. The `.bak` convention is the
  SVFix tool's "accumulated safety backups" (`SVFix@c1591b1 CHANGELOG.md`, 2026-09-22 entry),
  not the client's.

## 6. Test Mode (CooldownMaster v2.0.4) for demo media

The v2.0.3 → v2.0.4 delta is **only** Test-Mode hygiene: changed files
`CHANGELOG.md`, `CooldownMaster.toc`, `_Camelot/_Mists/_TBC/_Vanilla.toc`,
`Core/Changelog.lua`, `Core/Constants.lua`, `Core/Engine.lua`; functional delta = the
`Engine.testActive` gates (`CDM@e5811752 Core/Engine.lua:3456` in `ScanBuffs`, `:3486` in
`SyncOffensiveEntry`, `:4061` set true, `:4080` set false, `:4222` the tick loop;
`Core/Changelog.lua:27-31` — "Test Mode no longer shows buffs you do not have, and stops
showing them as the real ones expire" / "no longer shows debuffs you put on your target").
The law we should copy: **a demo mode must gate every path that writes entries, not just the
scans** — our future demo shims must gate the event feeds too.

The mechanism, all in `CDM@e5811752 Core/Engine.lua` + `Core/Constants.lua` +
`Core/Defaults.lua`:

- Private id space: `TEST_ID_BASE = 95000000` — "Entries are keyed by spellID, so test entries
  need their own id range or duplicates would collapse into one" (`Constants.lua:64-65`);
  entries are keyed `TEST_ID_BASE + i` (`Engine.lua:3966-3974`).
- Donor pool: `CollectTestDonors(category)` (`:3891-3939`) harvests **the player's own tracked
  items/spells** (name + icon only) and, for "mixed", interleaves categories through
  `MIXED_ORDER = { 0, 2, 1, 3 }` (`:3878`), with a curated `testSpellIDs` fallback when the pool
  is empty (`:3932-3937`) — so a demo shows the localiser's real names/icons, never invented
  ones. `TEST_TYPES` omits the categories with no donor pool: "no donor pool to demo from, and
  a fake Custom would look like a live timer" (`Constants.lua:76-81`).
- Spread: `count = clamp(testCount 1..20, default 6)`, `first = 5`, `last = 120`
  (`:3944-3946`, `Defaults.lua:253-257`), `span = (last - first) / (count - 1)`,
  `dur = first + span * (i - 1)` (`:3964-3970`) → a lane that fills evenly and never all-pops
  at once.
- **Secrecy-proof entries**: "No dObj and no itemID keeps test entries off the secret-value
  path, so the demo renders the same on every flavor" (`:3973`). This is the demo-media law
  for us: our media must run on entry shapes that never touch the secret-gated reads, so one
  capture is valid for the whole flavour matrix.
- Loop and drain: the tick (`:4222-4252`) fires the ready transition, re-arms with
  `entry._testDur` when `testLoop` is on, drops entries when it is off, and when
  `remaining == 0` calls `ToggleTestMode()` — "With looping off the demo drains, and leaving
  testActive set would suspend every real data path (they all early-out on it). Toggle outside
  the loop - StopTestMode rescans."
- Gating the real feed: `DeferredCooldownPoll` skips `ScanSpells` when `testActive` (`:256-261`).

**Our adoption shape** (demo media per `PLAN.md` §6's demo-media gate): a
`Forte_Core/Core/TestMode.lua` that (a) owns a reserved synthetic id range, (b) draws
names/icons from the *generated* spell/item data for the current class (our equivalent of the
donor pool — deterministic, so media is reproducible without a live client), (c) spreads
durations over a configurable window with a re-arm loop and an auto-off, (d) tags every synthetic
record `_source = "test"` and scrubs on exit, and (e) **gates every writer**: the
`Forte_Cooldown` read tiers + event feeds, `Forte_ItemProcs` proc detector, `Forte_Timer` trinket
windows, `Forte_Messages` announce queue. Files: `addon/Forte_Core/Core/TestMode.lua` (new) +
`addon/Forte_Core/Forte_Core.toc`, `addon/Forte_Cooldown/Module.lua`,
`addon/Forte_ItemProcs/Module.lua`, `addon/Forte_Timer/Core/Timer.lua`,
`addon/Forte_Messages/Core/Announce.lua`, `scripts/demo/*`, `docs/VERIFICATION.md` §Demo media.

## 7. Additive law pack (other new client facts from the install)

1. **Rank law corroboration.** `CDM@e5811752 Core/Changelog.lua:41-46` (v2.0.3): "On Forever,
   `UNIT_SPELLCAST_SUCCEEDED` reports **the rank you cast**, while Cooldown Master had the
   spell listed under a different rank, so the event never matched and the spell never showed";
   fix = a shared `ResolveSpellRank` + a canonicalised `Name<TAB>baseName` index (v2.0.1).
   Their lookup ladder: `GetSpellInfo(baseName).name` → a rank-suffix probe table via
   `GetSpellTooltipInfo(0, 0, "spell", name .. " " .. rank)` → a base-name tooltip
   (`Core/Init.lua:160-180`), and the note that "the base name carries a `#` suffix; the rank
   probes run against it" (`:165`) — the `#` suffix on base names is **new for us** (a locale
   shape our `Locale.CanonicalName` does not model). Launch probe (already in
   `docs/VERIFICATION.md`): `assertnumber(string.find(FX.Locale.CanonicalName(172), "Holy Strike"), 1))`,
   plus `#`-suffix forms on our four tracked base spells.
2. **The 100-error cap is a law the community codes to.** `CDM@e5811752 Core/Init.lua:381-384`
   "Blizzard's UI engine cuts a feature off at 100 Lua errors, and a 20/s storm of raises on a
   name that cannot resolve is how a working feature dies mid-raid" + the raise/never-pcall
   posture at `:374-380` — the same law our `Forte_Timer` storm-stop and
   `Forte_Core/Core/Init.lua:61` carry.
3. **`PLAYER_LOGIN` can be missed.** `CDM@e5811752 Core/Init.lua:153-157, 214-218`: the login
   handler is "driven from whichever of `PLAYER_LOGIN` / first `PLAYER_ENTERING_WORLD` reaches
   us first (`PLAYER_LOGIN` can be missed)"; "AceAddon enables us mid-`PLAYER_LOGIN` dispatch
   on a fresh login, so the `PLAYER_LOGIN` handler registered in OnEnable can miss its own
   event". This is *our* shape: `Forte_Core/Core/Loader.lua` + `Init.lua:436-462` enable
   `Forte_<Class>` **during** the `PLAYER_LOGIN` dispatch, so any class module registering
   `PLAYER_LOGIN` in `OnEnable` will not see it. Audit the six class modules; the selftest's
   direct `OnPlayerLogin()` call sites need the one-shot guard they use.
4. **Add-on state gates.** `CDM@e5811752 Core/Compat.lua:64-72`: the SVFix stamp +
   `C_AddOns.GetAddOnMetadata` as the Forever gate, plus **`IsAddOnsForcedDisabled()` /
   `IsAddOnsLoaded()` as camelot-only globals** ("absent on every retail flavour, so call them
   gated, never bare") — the "our add-ons are on?" health read for `Forte_Options`; our
   extractor learns them at launch (they are camelot-declared).
5. **Nameplate cooperation protocol.** `install: EllesmereUINameplates/EllesmereUINameplates_Init.lua:422-431,1226-1230,1627`
   (observed; rotated) — `C_NamePlates.ForbidNamePlates()`,
   `C_NamePlates.ReleaseNamePlatesForAddon(<ownerId>, { <ownerSet> })`, the
   `OnNamePlatesForbidden` script, and `C_NamePlatesAreForbidden()` read in 21 installed
   files; the "addon owns plate" precedent is a **numeric owner id** and the shipped set names
   the other owners (`18379`, `17422`, `4509`). For `Forte_ChatBar`'s glow-under-plates plan the
   cooperative path (`Forbid`/`Release` + the `Forbidden` callback) is cleaner than our
   `GetFramesRegion()` geometry. `[INFERENCE]` the ids are CurseForge project ids.
6. **The CVar law.** `install: TidyPlates_ThreatPlates/CVarsManager.lua:11-40` (observed;
   rotated): the restore path is `GetCVarDefault(name)` → `RestoreCVarToDefault(name)` per
   name (the whole CVar is the unit, no index math), `CVarIsHardSet` is the truth for a hard
   set (a realm can hard-set `addonChatRestrictionsForced` / `nameplatesDisableForcedAddOns`),
   a plain `GetCVar` "can read secret inside a restricted add-on", `GetCVarDefault` is the
   readable default, forced CVars are *skipped* by the cleanup, and the user override is
   `SetOverrideCVar`/`SetOverrideCVarValue`. 6 installed files use `GetCVarDefault`. Law for our
   `Forte_Options` CVar writes (the ChatBar's two CVars) and the restore path.
7. **Container law.** The 12.x `GetContainerNumSlots`/`GetContainerNumItems` pair needs the
   `_G.` underscore form on this client (`install: EllesmereUINameplates/EllesmereUINameplates_EIVContainer.lua:7,35-38`
   (observed; rotated) — the shipped shim names the bare camelot spellings as the trap), and
   the **`GetContainerItemLink` six→seven-return law with the `Item` object as the 7th**
   (`:110-114`, `:343-346`), 14 installed uses (`EllesmereUIQoL/EllesmereUIQoL.lua:1580`,
   `EllesmereUIBlizzardSkin/EllesmereUIBlizzardSkin_CharacterSheet.lua:1355`, …). Our
   `Forte_ItemProcs` law is right and the `Item` tail is a free enrichment.
8. **Spec-count gate.** `CDM@e5811752 Core/Compat.lua:40-45` + `Core/Init.lua:145-148`:
   `GetNumSpecs()` returns **nil (not a truthy 0)** on spec-less flavours "so bare
   `if GetNumSpecs()` gates skip them", and `PLAYER_SPECIALIZATION_CHANGED` registration is
   gated "so spec-less flavors (Era/TBC) don't register an unknown event" — our §3.2 law
   (`GetNumSpecializations() == 1`), in the wild. 18 installed files use
   `GetNumSpecializations`.
9. **Frame persistence / display law.** `CDM@e5811752 Core/Init.lua:119-124`:
   `SetPropagateKeyboardFocusChanges(false)` + `SetClipsChildren(true)` for the zoomed panel,
   and `ActionBarUsage.GetActionBarsForUsage(ENUM)` for the bar set.
   `install: Lueur/Lueur.lua:1332-1335,1560-1567` (observed; rotated) —
   `C_UnitPersistentData.SetPersistedSettings({ frame, "UnitFrameModels", "UnitFrameModelScene" },
   { modelIndex, cameraID })` + `GetPersistentValue` is the product's *sanctioned* frame-model
   persistence, and the re-assert-after-spawn law ("spawns clear custom settings: re-assert
   them once the model is there", a 0.1 s re-assert).

## 8. Source deltas since our studies

### 8.1 CooldownMaster — our notes studied **v2.0.4** (no new client law)

Pin proof: `docs/engine-notes.md:9` cites `Core/Engine.lua:3450`; at `e5811752` line 3450 is
"Forever's cooldowns are secret in combat like retail's…", at `22fc78f` (v2.0.3) that comment
is at **3448**; the 16 `docs/engine-notes.md` CooldownMaster cites (the
`ClassifyBagItem` `:74-84`, `RestartBuffFromCast` `:1188-1250`, `PollOneItem` `:3712-3736`,
`Compat.lua:20-21,26-37` pins) all land on the named symbols at `e5811752`. The installed copy
is v2.0.4 (`install: CooldownMaster/Core/Constants.lua` `VERSION = "2.0.4"`) and its `Core/`
tree is byte-identical to `e5811752` (`diff -rq` rc=0). **v2.0.3 → v2.0.4 delta = §6's Test
Mode gates; TOCs 2.0.3 → 2.0.4.** The rank/`ResolveSpellRank` law we cite as "2.0.1/2.0.3" is
v2.0.3-era and unchanged.

### 8.2 WeaponSwingTimer SixxFix — nothing newer than v1.60.2, and the public repo lags

- CurseForge files snapshot (`.../weaponswingtimer-sixxfix/files/all`, project "Last Update
  Oct 31, 2026"): Main File `1.60.1` → `WeaponSwingTimer-SixxFix_Forever_v1.60.2 — Latest
  release · R · Forever · Oct 31, 2026` (file id `9384757`). No Forever file newer than
  v1.60.2 exists as of 2026-11-03. The page's own snapshot is `read`-reachable; the direct
  project/CDN HTML is Cloudflare-gated (403) and the `api.curseforge.com` probes are 404, so
  this is a search-index snapshot, not an API pull.
- The CDN pull `edge.forgecdn.net/files/9384/757/WeaponSwingTimer-SixxFix_Forever_v1.60.2.7z`
  extracts **byte-identical** to the tree `docs/research/weaponswingtimer.md` studies
  (`/tmp/wst/src/WeaponSwingTimer/`, `## Version: 1.60.2`, `## Interface: 16001`) — so our
  survey's pin is current.
- **New**: the "Source" link, `github.com/watchyoursixx/WeaponSwingTimer-SixxFix`, head
  `3f48ab3` (2026-09-25) — its TOC has no `Version:` line and its newest functional commit is
  the June steady-shot work. **The public repo predates the shipped v1.60.2 build**: cite the
  shipped package, not the repo. `PLAN.md` §11.1's Hunter row pin stays right, for a new
  reason.

### 8.3 forever-addon-kit — unchanged

`/tmp/fak` head `8dc2976` (2026-09-25), the same head our studies cite ⇒ no new client facts
from it. Its SV law ("SavedVariables are never loaded back") is the *pre-fix* statement;
§5 supersedes it.

### 8.4 The installed set as studied (2026-11-03, all `## Interface: 16001`)

Auctionator, CooldownMaster 2.0.4, EllesmereUI 9.7.2 + 24 `EllesmereUI*` modules (ActionBars,
AuraBuffReminders, Bags, BlizzardSkin, Chat, CooldownManager, DamageMeters, DataBars,
**ForeverEssentials**, ForeverFix 1.0.0, Friends, GroupFinder, Locales, Minimap, MythicTimer,
Nameplates, Options, QoL, QuestTracker, Quickdraw, RaidFrames, ResourceBars, UnitFrames),
Lueur, MikScrollingBattleText 0.6.5 (Forever-only), NeedRoll, NodeSight, OpenMap, Polestar,
PrettyTooltip, Questie (6 flavour TOCs), SilverDragon, **TidyPlates_ThreatPlates**,
TrueshotLodge, WarEffortScout, WhisperMessenger (1.60.2), WowSavedVariables.
Read-only; nothing written outside `/tmp`.

## 9. Ranked: what we should change

1. **Retire the SVFix premise; make SavedVariables a measured launch probe.** Evidence §5.
   Touch: `scripts/deploy.sh` (the FOREVERSVFIX LAW block + the `SVFIX_PATTERNS` "never patch"
   rationale → keep the guard, drop the "every install carries the stamp" claim),
   `addon/Forte_Core/Forte_Core.toc` + `_Camelot.toc` (decide `SavedVariablesPerCharacter:`
   and the `LoadSavedVariablesFirst:` posture), `addon/Forte_Core/Core/Util.lua`
   (`CharacterKey`: document the full-name/multi-component identity law; probe the client's
   per-character store next to ours), `PLAN.md` §2.3 + §8 + §9's 2026-11-01 SVFix rows
   (supersede, don't delete), `docs/VERIFICATION.md` (a write → `/reload` → read probe over
   `ForteXorcistDB`, + assert the *order* a file-load default needs),
   `docs/research/forever-dev-notes-2026-11-03.md` (the API row on
   `C_AddOns.GetAddOnMetadata`/`GetAddOnList`).
2. **Adopt the shipped swing-timer law for Hunter swing v2.** Evidence §3.
   Touch: `addon/Forte_Hunter/UI/Swing.lua` (engine-driven fill: `C_DurationUtil` +
   `SetTimerDuration` + `Enum.StatusBarTimerDirection/StatusBarInterpolation`, the
   `UnitAttackSpeed`-per-slot row model, the 0.5 s aim window, `Immediate`-on-rearm),
   `addon/Forte_Hunter/Core/Tools.lua` (the 3-return `PLAYER_SWING_RANGE_UPDATE`,
   nil-is-not-out-of-range, `EnableRangeCheck` opt-in, `GetNetStats` home/world pair + the
   3rd-return fallback, the 0.45 s / 0.58–0.66 s / 2.0 s windows, the no-`PLAYER_SWING`-for-pets
   law, `GetRangeIndicator` as a second range signal),
   `addon/Forte_Hunter/Pages/Hunter.lua` + `UI/Range.lua` (the range light),
   `scripts/api_lint.py` (names: `C_DurationUtil`, `SetTimerDuration`, `EnableRangeCheck`,
   `GetRangeIndicator`, `IsRangedUnitWithinSwingRange`, `UnitInVehicle`, `GetSpellInfo`),
   `docs/VERIFICATION.md` (Gap-11/Gap-12 rows now have a shipped-shape answer),
   `addon/Forte_Core/ATTRIBUTION.md` if the fill law is taken from the EllesmereUI tree
   (closed-source: re-derive from the declared APIs, take the numbers only).
3. **Throttle-aware comms.** Evidence §4.
   Touch: `addon/Forte_Warlock/Core/Comms.lua` (classify the result codes: 3/8 → re-queue with
   back off, Lockdown/Restrict → re-queue at the head, else drop; a persisted outbox;
   name `2 = invalid`/`3 = toomany` in `prefixState`), `addon/Forte_Messages/Core/Announce.lua`
   (+ `addonChatRestrictionsForced` in the gate at `:196-206`),
   `addon/Forte_Messages/Core/Snapshot.lua`/`Reconcile.lua` (the budget),
   `tools/selfcheck.lua` (result-class asserts), `docs/COMPATIBILITY-MATRIX.md`.
4. **Secrets: widen the gate set and harden the laws.** Evidence §1–§2.
   Touch: `addon/Forte_Core/Core/Compat.lua` (add `ShouldSpellAuraBeSecret`/
   `ShouldUnitIdentityBeSecret`/`ShouldUnitThreatValuesBeSecret` to the gated set; `GetSpellInfo`
   in the name/icon path with the `134400` fallback; the async item path),
   `addon/Forte_Cooldown/Module.lua` (the per-spell aura gate on the buff-rider path; the
   "exists ≠ read plain" iteration rule), `scripts/api_lint.py` (the secret-prone list +
   `UnitIsDeadOrGhost`; a law rule "a value from a gated read passes `PlainOrNil` before any
   `not`/`and`/`or`/`table.sort` key/table key"), `addon/Forte_Options/Pages/*` (the sort-key
   law), `docs/VERIFICATION.md` §2, `addon/Forte_Core/Core/Probe.lua` (+ `UNIT_THREAT` /
   `ShouldUnitThreatValuesBeSecret` rows).
5. **Capability probes over try-and-catch.** Evidence §2, §5.
   Touch: `addon/Forte_Core/Core/Probe.lua` (`C_EventUtils.IsEventValid` over every event
   literal our modules register; `C_AddOns.GetAddOnList`; `IsAddOnsLoaded`/
   `IsAddOnsForcedDisabled`), `addon/Forte_Options/Pages/Status.lua` (the add-on-state row),
   `addon/Forte_ChatBar/Module.lua` (settle `siblingTidyPlates()`'s `"unknown"` at launch),
   `docs/VERIFICATION.md`, `scripts/api_lint.py` (a static↔dynamic pair note).
6. **`FX.TestMode` for demo media.** Evidence §6.
   Touch: `addon/Forte_Core/Core/TestMode.lua` (new) + `addon/Forte_Core/Forte_Core.toc`,
   `addon/Forte_Cooldown/Module.lua`, `addon/Forte_ItemProcs/Module.lua`,
   `addon/Forte_Timer/Core/Timer.lua`, `addon/Forte_Messages/Core/Announce.lua`,
   `scripts/demo/*` + `scripts/demo_media.sh` + `scripts/gate.py` (the demo-media gate),
   `docs/VERIFICATION.md` §Demo media, `tools/selfcheck.lua` (the `_source = "test"` scrub
   assert: no synthetic entry survives an exit).
7. **Login-order audit for LoD class add-ons.** Evidence §7.3.
   Touch: `addon/Forte_Core/Core/Loader.lua`, `addon/Forte_Core/Core/Init.lua:436-462`,
   `addon/Forte_Hunter/Core/Tools.lua:1108-1156` (the event registration set), the class
   modules' `OnEnable`/`OnLogin` split, `tools/selfcheck.lua`,
   `docs/engine-notes.md` (the law row).
8. **ChatBar/nameplates + CVar law.** Evidence §7.5–§7.6.
   Touch: `addon/Forte_ChatBar/Module.lua` (prefer the `ForbidNamePlates`/
   `ReleaseNamePlatesForAddon` + `OnNamePlatesForbidden` protocol over geometry; the
   `CVarIsHardSet`/`GetCVarDefault`/`RestoreCVarToDefault` shape for its two CVars),
   `addon/Forte_ChatBar/Forte_ChatBar_TidyPlates.toc` (the pair law note),
   `docs/COMPATIBILITY-MATRIX.md`, `scripts/api_lint.py`.
9. **Item/icon + container enrichment.** Evidence §2, §7.7.
   Touch: `addon/Forte_Items/*`, `addon/Forte_ItemProcs/Module.lua`,
   `addon/Forte_Timer/UI/Trinkets.lua` (async icon path + the `GetContainerItemLink` 7th
   `Item`), `docs/engine-notes.md` (the `ItemUtil.GetIconByItemID` claim: unconfirmed in the
   wild), `docs/research/forever-data-gaps.md` (icon fields).
10. **Locale/rank probe additions.** Evidence §7.1.
    Touch: `addon/Forte_Core/Core/Locale.lua` (the `#`-suffixed base-name shape),
    `docs/VERIFICATION.md` (probe rows: the `#` suffix, the `GetSpellInfo().name` rank leg,
    `IsAddOnsForcedDisabled`), `tools/overrides_70707.json` if a rank is unresolvable.

## 10. Open questions

1. Does the client's SavedVariables restore work on `1.60.1.70707`, and in which order relative
   to file load? (§5; SVFix's claim is 2026-09-25 and the install evidence is 2026-10-23.)
   Decides change-list item 1.
2. Is `GetNetStats()`'s 3rd/4th pair (home/world, ms) as the two shipped readers use it? If yes,
   Gap-12 shrinks to a units check. Decides §9.2.
3. Threat: is there any threat surface on the client (`IsEventValid("UNIT_THREAT")`,
   `type(UnitThreat)`, `C_Secrets.ShouldUnitThreatValuesBeSecret()`) — the predicate's existence
   in a shipped-for-Forever addon contradicts a pure "no threat API" reading.
4. Prefix budget: what is the `3 = toomany` ceiling, and does a busy install (25 add-ons) hit it?
5. `GetAddOnList()`/`GetAddOnMetadata` on 70707 for a *LoadOnDemand sibling* (`TidyPlates`):
   enabled-set truth available? (ChatBar §9.8.)
6. Is the `_forever_` install's dangling SVFix symlink a migration bug in the tool (product
   folder `_classic_beta_` → `_forever_`) — i.e. will a fresh SVFix run re-stamp our add-ons and
   rewrite our TOCs under the `scripts/deploy.sh` symlinks? (The law says never patch; this is
   the concrete hazard.)
7. `C_NamePlates` owner-id protocol: are the numeric ids CurseForge project ids, and is
   `ReleaseNamePlatesForAddon` ref-counted across owners? Decides §9.8's glow plan.
8. Does `IsRangedUnitWithinSwingRange` answer for `Ranged` (one installed use; our Hunter range
   light wants the ranged form)?
9. `_testDur`-style re-arm: does a looping demo need to be gated in *our* `Forte_Cooldown` tiers
   as tightly as CDM's `testActive` gates (the v2.0.4 lesson) — answer at implementation.
