# Shadowflare (Fistao) — how it shows procs on WoW Forever

Analysed from **real source**, version **0.23.25** (zip `Shadowflare-0.23.25.zip`, uploaded
2026-10-30, CurseForge file id 9369267). TOC declares `## Interface: 16001` → **targets Forever
specifically**, no retail/classic flavour
(`Shadowflare.toc:1-8`). Files: `Core.lua` 2483 l, `Display.lua` 2018 l, `AuraShow.lua` 1187 l,
`Settings.lua` 1802 l, `Profiles.lua` 463 l, `Locale.lua`, `Notes.lua`, `Options.lua`,
`AuraShow.xml`, `Art/*.tga`.

**How the source was obtained** (documented because CurseForge gates its pages): the addon is
not installed locally (`Interface/AddOns/` has no Shadowflare) and has **no GitHub mirror**
(GitHub user `fistao` has 6 repos, all unrelated Java/JS utilities). `api.curseforge.com/v1/...`,
`widget.forgecdn.net` → 404/dead; plain `curl` of the site gets a Cloudflare 403. The files page
was opened in the local playwright Chromium (headed → passes the challenge), which exposed the
file page `/wow/addons/shadowflare/files/9369267`; the CDN path pattern read from the local
CurseForge client logs (`~/.config/CurseForge/agent/logs/CurseClient/20261101130942-39094D.json:1936`,
`Downloading project file from https://edge.forgecdn.net/files/9358/226/CooldownMaster-v2.0.4.7z`)
is unauthenticated: `https://edge.forgecdn.net/files/<id/1000>/<id%1000>/<name>`. That served the
zip (`HTTP 200, application/zip, 759622 B`).

**Licence**: no LICENCE file in the zip; CurseForge page shows no open-source licence. Treat as
**all rights reserved — pattern reference only, copy no code**. (Contrast CooldownMaster, MIT.)

---

## Verdict

**`uses-game-aura-container` is the primary technique**, with `reads-spell-state` as the second
and `uses-native-alert` for exactly two procs. All three coexist, chosen **per proc by a single
`mode` field** in a static table (`Core.lua:63-368`). Nothing in the addon reads the combat log,
`C_ClientScene`, `DoAction`, `C_Spell.AddActiveSparkleSpell`, GCD or charges APIs (0 occurrences —
see "APIs it does *not* use").

Split of the 37 proc entries in 0.23.25 (the public page lists 35; `conflagrate` and `shieldblock`
are new and not yet in the page list):

| technique | n | modes |
|---|---|---|
| game aura container only (addon is blind) | 14 | `aura` |
| spell-state proxy (cast time / cost / usable / cooldown-active) | 20 | `faster`, `free`, `instant`, `usable`, `overlay`+fallback, `reset`, `casts` |
| game's native proc alert (event + CVar + game sound) | 2 | `trance` (Shadow Trance), `overlay` (Fingers of Frost) |
| events-only (no polling as the signal) | 0 | `overlay` is event-driven, the rest is polled |

Their own description sentence maps 1:1 onto the code: *"reads the spell instead"* = the `mode`
engine in `Core.lua`; *"uses the game's own proc alert"* = `Core.lua:1215-1247`; *"lets the game
show the alert itself from the buff, with the real time left"* = the whole of `AuraShow.lua`.

---

## API surface used

Paths are inside the zip (`Shadowflare/…`). Line numbers from 0.23.25.

### Secrecy guards (the pattern our `Compat.PlainOrNil` mirrors)

| API | where | what for |
|---|---|---|
| `issecretvalue` (global) | `Core.lua:525` (`local isSecretValue = issecretvalue`), used at `:529-548`; `AuraShow.lua:1088-1096`, report at `:1107-1163` | the single secrecy test |
| `ns.num(v)` / `ns.str(v)` / `ns.clean(v)` | `Core.lua:534-548` | plain number/string or `nil`; tries `v + 0` / `v .. ""` under `pcall` (a secret value throws on maths/concat) |
| `desc(v)` → `"secret"` | `Core.lua:1263-1267` | debug printing only |

### Spell state — the proxy (mode `faster`/`instant`/`free`/`usable`/`reset`)

| API | where | fields read | what for |
|---|---|---|---|
| `C_Spell.GetSpellInfo(id)` | `Core.lua:646-649` (`CastTimeRead`, `:641`), `:651-658` cache | **`castTime` only** (`info.castTime`) | cast-time comparison |
| `GetSpellInfo(id)` (legacy multi-return) | `Core.lua:636-639` (`GetSpellInfoOld`), `:641-645` | 5th return | preferred when the client still has it |
| `C_Spell.GetSpellPowerCost(id)` | `Core.lua:893-908`; probe `:2313-2330` | `t[i].cost`, and in debug `name`/`type`, `minCost`, `costPercent`; `secret(t)` gate at `:904` | "spell became free/cheaper" |
| `C_Spell.IsSpellUsable(id)` | `Core.lua:970-975` (`IsSpellUsableAPI`, `CheckUsable` `:975`); probe `:2226-2228` | returns **`(usable, noPower)`**; `noPower and lack==true` counts as usable for window procs | "proc opened a window" |
| `C_Spell.GetSpellCooldown(id)` | `Core.lua:1061-1069` | **`isActive` only** | `reset` mode (Improved Stormstrike). Their claim: `SpellCooldownInfo.isActive` is *NeverSecret* in Forever's own API docs (`Core.lua:307-309`) |
| `C_Spell.GetSpellCooldown` `startTime`+`duration` | `Core.lua:2240-2252` | (debug warrior probe only) | not used in shipping logic |
| `C_Spell.GetSpellName` / `GetSpellTexture` | `Core.lua:558-569` | — | labels/icons |
| `IsPlayerSpell` / `IsSpellKnown` | `Core.lua:660-668` | — | pick the highest known rank from a rank list (`Known()`), all spell IDs are rank lists |
| `IsStealthed` | `Core.lua:981-983` | — | Cutthroat: ignore the always-usable-in-stealth case |
| `GetShapeshiftForm` | `Core.lua:2265` | — | debug only (stance affects `usable`) |
| `C_Spell.GetSpellCharges`, `isOnGCD`, `IsSpellInRange`, `AddActiveSparkleSpell`, `C_ClientScene`, `DoAction` | — | — | **not used anywhere** (grep: 0 hits) |

### Aura reads (out of combat + Shadow Trance only)

| API | where | fields | what for |
|---|---|---|---|
| `C_UnitAuras.GetPlayerAuraBySpellID(id)` | `Core.lua:693-712`, `:1379-1381` | `auraInstanceID`, `expirationTime`, `duration` | Shadow Trance direct ask; returns nil in combat for some buffs (see corroboration below) |
| `C_UnitAuras.GetAuraDataByIndex("player",i,"HELPFUL")` | `Core.lua:713-733` (`ReadAura`), `:735-756` (`FullScan`), `:1294-1300`; `AuraShow.lua:270-272`, `:302-307` | `spellId`, `name`, `expirationTime`, `duration`, `auraInstanceID`, `applications`, `icon` | full buff scan; "unreadable" if `spellId` and `name` are both nil ⇒ `auraReliable=false` |
| `C_UnitAuras.GetAuraDataByAuraInstanceID("player",inst)` | `Core.lua:757-763` | `expirationTime`, `duration` | follow one known aura instance through `UNIT_AURA` deltas |
| `UnitBuff` (legacy) | `Core.lua:719-721` | — | fallback branch |

### Blizzard widget that gets the buff — **the aura container** (mode `aura`)

| API | where | what for |
|---|---|---|
| `C_AddOns.LoadAddOn("Blizzard_AuraContainer")` | `AuraShow.lua:335-336` | make the template exist |
| `CreateFrame("AuraContainer","ShadowflareAuraContainer",UIParent,"CustomAuraContainerTemplate")` | `AuraShow.lua:337-341` | one container for the whole addon |
| `container:SetUnit("player")`, `:SetEnabled(true)`, `SetAllPoints`, `SetFrameStrata` | `AuraShow.lua:343-347` | self-auras only |
| `container:AddAuraSlot(skey,"HELPFUL",{templateNames={"ShadowflareAuraTemplate"}, initializeFrame=fn, candidateFilters={includeSpellIDs=ids}})` | `AuraShow.lua:592-598` (main), `:574-578` (per-stack frames) | **the hand-off**: one slot per proc, keyed by spell ID set; the game instantiates the addon's template and shows/hides it |
| `container:SetAuraSlotEnabled(skey,on)` | `AuraShow.lua:631-633` | on/off gate (options, "only in combat", held-during-cooldown) |
| `container:SetAuraSlotCandidateFilters(skey,{includeSpellIDs})` | `AuraShow.lua:708-711` | a newly learned buff ID joins live frames without `/reload` |
| `container:IsAuraSlotEnabled` / `GetAuraSlotFrame` | `AuraShow.lua:1126-1130` | `/flare gstest` diagnostics |
| `button:SetApplicationBar(bar,{minApplications,maxApplications})` | `AuraShow.lua:378-391` | **stack filter**: game shows the frame at ≥ n stacks |
| `button:SetApplicationCount(fontstring,{formatter})` | `AuraShow.lua:394-411` | **the game writes the stack number** into the addon's FontString |
| `button:SetDurationCooldown(cooldownFrame)` | `AuraShow.lua:540`, `:883` | **the game drives the countdown** (real time left) |
| `button:SetDurationText(fontstring,{textFormatter})` | `AuraShow.lua:929-933` | the game writes the remaining-time **text** |
| `button:AddAuraShownAnimation` / `RemoveAuraShownAnimation` | `AuraShow.lua:783-788` | entry animations the game plays |
| `button:GetIcon()` (hidden) | `AuraShow.lua:421-423` | suppress the game's icon, draw our art |
| `AuraShow.xml` virtual `ShadowflareAuraTemplate` with `<StatusBar parentKey="bar">` | `AuraShow.xml:6-11` (`StatusBar` at `:8`) | the frame the game instantiates; the addon draws everything inside `bar` |
| `CreateFrame("Cooldown",nil,bar,"CooldownFrameTemplate")` + `SetCountdownFormatter` + `GetCountdownFontString` | `AuraShow.lua:525-546`, `:920-926` | numbers-only countdown, game-written text |
| `C_StringUtil.CreateNumericRuleFormatter` + `SetBreakpoints` + `Enum.NumericRuleFormatRounding` | `AuraShow.lua:178-184`, `:356-368` | round-down format (`%.0f` ≥3 s, `%.1f` below) |

### Native proc alert (mode `trance` + `overlay`)

| API | where | what for |
|---|---|---|
| `C_CVar.SetCVar("displaySpellActivationOverlays","1"/"0")` | `Core.lua:1215-1222` | turn Blizzard's own proc alert on/off; their own sound **switches it off** so the two don't double up (`Core.lua:1191-1194` comment) |
| `C_CVar.GetCVar("displaySpellActivationOverlays")` | `Core.lua:1231-1246` | keep the CVar in sync with the player's choice |
| `PlaySound(23287,"Master")` | `Core.lua:1197-1213` | sound set 23287 ("power") = the sound the game plays for its own proc alert; also IDs 8959, 8960, 12889, 3081, 3175 |
| `SPELL_ACTIVATION_OVERLAY_SHOW/HIDE`, `…_GLOW_SHOW/HIDE` | `Core.lua:2162-2200` | the alert *events* — `a1` = spell ID. `_GLOW_*` = "the game's Shadow Bolt glows on the action bar" |
| `ns.db.blizzTex` | `Core.lua:2176-2178`; `Display.lua:1219-1228` | the atlas ID the game passed (`a2`) is **saved and becomes a selectable "classic" style** — the game's own proc art |

### Gear (Weapons and Enchants sections)

| API | where | what for |
|---|---|---|
| `C_Item.GetItemNameByID(itemID)` | `Core.lua:576-578` | label only |
| `C_Item.RequestLoadItemDataByID(itemID)` | `Core.lua:581-582` | async name request, retried by `GET_ITEM_INFO_RECEIVED` (`Core.lua:1952-1960`) |
| `C_Item.GetItemIconByID(itemID)` | `Core.lua:598-601` | icon only |
| `C_Spell.GetSpellName(enchantSpellID)` | `Core.lua:585-591` | the buff's name = the enchant spell's name minus `"… - "` prefix, so it works in any language |
| `C_Item.GetWeaponEnchantInfo`, `GetInventoryItemEnchantByID`, `GetInventoryItem*`, any equipped-gear scan | — | **not used (0 hits)** — see the gear section below |

### Driving and cadence

| API | where | what for |
|---|---|---|
| `C_Timer.NewTicker(0.2, Poll)` | `Core.lua:1691`, `:1688-1700` | the light in-combat read loop; **created only while `inCombat or anyActive`**, cancelled otherwise ("nothing runs between fights") |
| `ns.RequestRefresh()` + `REFRESH_GAP = 0.1` | `Core.lua:1526-1539` | floods (`SPELL_UPDATE_USABLE`, `ACTIONBAR_UPDATE_USABLE`, `UPDATE_SHAPESHIFT_FORM`) coalesce to ≤10 Hz |
| `C_Timer.After(0.1/0.35, ns.Refresh)` | `Core.lua:2039-2041`, `2063-2067` | re-check after a cast: the state changes a moment after `UNIT_SPELLCAST_SUCCEEDED` |
| `WakeAt(t)` single scheduled wake | `Core.lua:1482-1494` | no timers: one wake at the next expiry |
| `InCombatLockdown()` | `AuraShow.lua:68-74`; `Display.lua:1877` | the client's own lock for placing/moving |

---

## Events registered

Main frame `Core.lua:1937-1950`; `items` frame `:1952-1960`; `casts` frame `:1961-1963`;
debug probe frame `:2286-2290`. Secrecy column = what the code does to the payload.

| Event | where | payload handling |
|---|---|---|
| `ADDON_LOADED`, `PLAYER_LOGIN` | `Core.lua:1946-1947` | — |
| `PLAYER_ENTERING_WORLD` | `Core.lua:1939` | — (also `Notes.lua:576`) |
| `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` | `Core.lua:1939`, `2161-2165` | **their in/combat flag** (`S.inCombat`); on *enabled* → re-apply looks + `AuraShow.QueueScan()` |
| `SPELLS_CHANGED`, `CHARACTER_POINTS_CHANGED`, `PLAYER_TALENT_UPDATE` | `Core.lua:1939-1941` | re-learn ranks; talents ⇒ `ForgetUsual()` clears all learned baselines (`Core.lua:1187-1189`) |
| `SPELL_ACTIVATION_OVERLAY_SHOW` / `_HIDE` | `Core.lua:1941`, `:2162-2185` | `a1` spell ID through `num()` (secret-safe); `a2` = texture atlas |
| `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW` / `_HIDE` | `Core.lua:1942`, `:2186-2200` | `a1` spell ID |
| `SPELL_UPDATE_USABLE`, `ACTIONBAR_UPDATE_USABLE` | `Core.lua:1943`, `:2202` | grouped (`FREQUENT`) |
| `UPDATE_SHAPESHIFT_FORM` | `Core.lua:1943` | grouped |
| `PLAYER_TARGET_CHANGED` | `Core.lua:1944` | re-check `onTarget` procs at once (0.23.16) |
| `UNIT_AURA` (unit `player` **only**) | `Core.lua:1949-1950`, handler at `:2090-2108` | **secret-annotated.** `info.isFullUpdate` may be secret ⇒ `AskGame()` only; then `addedAuras` / `updatedAuraInstanceIDs` / `removedAuraInstanceIDs` (`Core.lua:766-800`) each field through `num()`/`str()`; a `spellId`/`name`-less entry ⇒ `auraReliable=false`. Known break: reading `isFullUpdate` threw on every Rejuvenation/shapeshift until 0.13.0 (`Core.lua:2086-2088` comment) |
| `GET_ITEM_INFO_RECEIVED` | `Core.lua:1953` | name arrival for gear labels |
| `UNIT_SPELLCAST_SUCCEEDED` (unit `player`) | `Core.lua:1963`, `2013-2071` | `spellID` read through `num()`; drives the `used`/`spent`/`renew`/`stack`/`reset` role maps |
| `SPELL_UPDATE_COOLDOWN` | `Core.lua:2287` | `/flare debug` warrior probe only |

No `C_CombatLog*`, no `COMBAT_LOG_EVENT_UNFILTERED`, no nameplate/target-aura events. The comment
at `Core.lua:1949` is explicit: *"the player's buffs only (never the target's, the party's, or the
nameplates')"*.

---

## The in-combat trick, step by step

### 1. Every proc declares one detection mode

`Core.lua:63-368` is a static table; each entry carries `mode`, the rank lists it watches
(`cast`, `refs`, `watch`, `others`, `renew`), a hardcoded design duration `dur`, optional
`cd`, `stacks`, `buffIds`, and a `defaults` block. `mode` is the whole encoding of "which of the
three techniques" (dispatched at `Core.lua:1120-1132`, explained at `Core.lua:822-835` (mode table comment)):

| `mode` | signal | "proc ready" derivation |
|---|---|---|
| `faster` | ratio of two cast times | `CastTime(cast)/CastTime(ref) < base*threshold` |
| `instant` | cast time hits 0 | `ct == 0` **and** a real `ct > 0` was seen before (`g.base ~= nil`) |
| `free` | `cost` dropped | `cost(id) <= base(id)*free` for any watched spell |
| `usable` | `IsSpellUsable` | `usable == true` **or** (`noPower` accepted **and** the second return `lack == true`) |
| `reset` | cooldown ended early | `C_Spell.GetSpellCooldown().isActive == false` between 1.6 s and `cd-0.6` s after the cast |
| `casts` | our own cast events | count of casts of the spell inside a `dur` window, from `UNIT_SPELLCAST_SUCCEEDED` |
| `overlay` | the game's own alert events | on between `SPELL_ACTIVATION_OVERLAY_SHOW(id)` and `_HIDE(id)`; expires `dur+2` s if the HIDE is missed |
| `trance` | 4 independent signals, **any** one wins | aura ∥ overlay ∥ glow ∥ cast-time |
| `aura` | **none readable** | no detection, **no sound** (`Core.lua:1252`); display handed to the game |

### 2. Learn a baseline, compare against it (never read an absolute)

Every proxy is *relative*. `g.ratio[refId]`, `g.costBase[id]`, `g.maxCt` start empty and are
filled with the **largest value seen** (`Core.lua:852-858`, `869-871`, `906-911`). The comparison is
`now < base * threshold`. Consequences built into the code:

- **Haste is cancelled by a reference spell.** `refs` = a list of reference rank-lists the proc does
  *not* touch (Pyroblast vs Fireball `Core.lua:143-148`; Starfire vs Wrath; Holy Light vs Flash of
  Light). `CheckFaster` divides the two (`Core.lua:841-847`). Where no reference is readable it
  falls back to `selfCheck` — compare the spell against its own fastest-seen cast, and *keep the
  previous answer* if that is unknown too (`Core.lua:848-853`).
- The baseline is **learned only while the spell is at its usual speed** — a flat cut on both
  spells (Nature's Grace) would otherwise inflate the ratio and make haste look like a proc
  (`Core.lua:852-856`).
- `ForgetUsual()` wipes all baselines on `PLAYER_TALENT_UPDATE` (`Core.lua:1187-1189`).
- Read memoisation per pass: `readStamp` + `ctAt`/`costAt` so a spell is read once per refresh
  ("each read can make a small table", `Core.lua:634-638`, `912-918`).

### 3. Stacks are *inferred from the slope*, not read

`CountStacks` (`Core.lua:1023-1060`) has three numeric recipes, all from the same two readable
fields:
- `stackAt` (Heating Up): thresholds on the ratio — `{0.88, 0.66}` → 1/2/3 stacks;
- `perCharge` (Eclipse): `floor(cut/perCharge)`, `cut = (1 - r/base) * maxCt / 1000` — seconds
  shaved off Starfire, 0.5 s a charge;
- `perStack` (Maelstrom Weapon): **Lightning Bolt's mana cost**, 20 % per stack, falling back to
  the cast-time ratio when the cost reads 0 (i.e. when Clearcasting made it free).

`fullCut` handles Eclipse charges: only show when the cut equals the biggest cut ever seen
(`Core.lua:863-871`). The alert fires its sound only at the maximum count
(`Core.lua:1655-1660`).

### 4. Debounce the game's chattiness (the ugly half)

The state answers flicker, so most of `Refresh` is edge-condition surgery
(`Core.lua:1541-1660` (`Refresh`)): a "no" shorter than **0.3 s** is ignored; a proc that ran out may not come
back for a moment's "yes" — inside 1.5 s the "yes" must hold **0.5 s**; `holdCd` hides the alert
for a full cooldown after a cast because *"the game says usable even while the spell is on
cooldown, and hides cooldowns in combat"* (`Core.lua:88-90`); `st.spent` retires the window at its
design duration even while the game still says yes, and re-arms it if the game says yes **2 s**
later (that is a genuine refresh). `g.openAt` records when the window *opened*, so an alert shown
at the end of a cooldown counts its time from the open, not from now
(`Core.lua:988-994`).

### 5. The warm-out-of-combat mechanism (their stated workaround)

What the description calls *"they start once their buff has been on you out of combat"* is the
buff-ID learning loop in `AuraShow.lua`:

1. Triggers: `UNIT_AURA` for `player` **while out of combat** (`Core.lua:2097-2098`) and
   `PLAYER_REGEN_ENABLED` (`Core.lua:2156-2158`) → `AS.QueueScan()`, a 0.25 s debounce
   (`AuraShow.lua:321-329`).
2. `AS.Scan` (`AuraShow.lua:282-331`) **returns at once on `InCombat()`** (`:283`). It walks
   `GetAuraDataByIndex("player", i, "HELPFUL")` for i = 1..40 and matches each aura against
   `Candidates(p)` = `buffIds` ∪ the names of `buffIds` ∪ the proc's own spell name
   (`nameFromSpell`) ∪ the proc's Shadowflare label (`nameFromLabel`) ∪ literal `buffNames` ∪ the
   enchant-spell name for gear.
3. Plausibility filters so a random long buff can't be captured: `minDur ≤ duration ≤ maxDur`
   (default 0..60 s), `noEnd` for buffs with no expiry (Reckoning's stored attacks, Revelation's
   unknown length), `maxDur = 3600` for Revelation, `minDur=8, maxDur=12` for Insight (its French
   name "Clairvoyance" collides with other spells) (`AuraShow.lua:303-318` + `Core.lua:346-355`).
4. `Learn()` (`AuraShow.lua:235-264`) persists `{id, apps, flat, dur, icon}` into
   **`ShadowflareDB.buffs[key]`** — *"what is seen is kept for the whole account"*
   (`AuraShow.lua:21`). It records `apps` (a stack count ever seen) and `flat` (the buff turned
   out not to count stacks), and calls `AS.Setup` the moment `Ready()` flips true, printing a chat
   line (`GS_LEARNED`).
5. `Ready(p)` = the buff ID is known, **or** `Preset(p)` (`AuraShow.lua:129-138`, `:120-127`).
   In 0.23.20 the gate was relaxed: procs with `mode == "aura"` **and** entries marked `preset`
   get their container slots from the first login with all candidate IDs at once, because
   "having to see a buff out of combat first looked like a broken alert" (`AuraShow.lua:12-19`;
   `Notes.lua:31-35`). `AS.Setup` still refuses to run `InCombat()` (`AuraShow.lua:590`) — slots
   are only ever created out of combat.

**Why it works**: the addon only needs the **numeric aura identity**. Once the ID is in
`includeSpellIDs`, the *game* does the rest; the addon never reads the aura in combat. The same
learning also feeds `AS.Dur(key)` (`AuraShow.lua:190-194`) — a real buff length used as the display
duration for its own alerts, which is the *only* measured duration in the addon.

### 6. The container hand-off (the payoff for 14 blind procs)

`AS.Setup` → one slot per proc keyed `shadowflare_<key>`, `candidateFilters.includeSpellIDs = ids`,
`templateNames = {"ShadowflareAuraTemplate"}` — the virtual template from `AuraShow.xml` whose
only content is a `StatusBar` with `parentKey="bar"`; the game instantiates it and hands it to
`initializeFrame`, inside which the addon builds **its own** alert art (`AuraShow.lua:413-559`).
Stacking procs get **one slot per stack count** (`AddAuraSlot` for `skey.."_"..n`, n = 1..max-1,
`AuraShow.lua:561-584`) because the game's filter is "n **or more**" — read from
`Blizzard_CustomAuraButton.lua` and documented at `AuraShow.lua:30-35`. Frames are stacked so the
lowest enabled one carries the number, the time and the full look, and each frame above adds only
brightness (`LayerAlpha`, `AuraShow.lua:661-673`). Then `SetApplicationBar`,
`SetApplicationCount`, `SetDurationCooldown`/`SetDurationText` hand the number and the countdown to
the engine, so *"the addon never learns when"* (`AuraShow.lua:1-10`).

Hard constraints they hit and documented (all of them secret/taint related):
- **frames cannot be touched in combat**: `AS.Apply` defers the look and only calls
  `SyncEnabled()` while `InCombat()` (`AuraShow.lua:947-952`); "Forever doesn't let an addon touch
  them in a fight (seen with /flare gstest)" ⇒ no looping animations inside game frames at all
  since 0.23.7 (`AuraShow.lua:1065-1071`); the 30 Hz `AS.Tick` loop exists only for that and is
  stopped outside combat + 20 s (`AuraShow.lua:1033-1063`, `:1141-1163`).
- watching the frame's `OnHide` was **rejected by the client**: *"blocked by secret aspects"*, and
  the frame stopped being built at all (0.23.0 → removed 0.23.7, `AuraShow.lua:494-498` (comment), phrase at `:495`).
- "only in combat" and Victory-Rush's cooldown are enforced by **switching the slot off**, because
  the frame itself can't be touched in a fight ("forbidden object", `AuraShow.lua:703-704` (`AS.Update` gate), `:707-717`).
- `AS.Update`/`SetAuraSlotCandidateFilters` live-updates are out-of-combat only
  (`AuraShow.lua:703-706`).

### 7. The native proc alert (2 procs)

Shadow Trance (`mode = "trance"`) treats the game's alert events as **one of four equals**
(`SourceOf`, `Core.lua:1500-1516`) — aura, overlay, glow, cast-time. Fingers of Frost
(`mode = "overlay"`) is **entirely** the game's alert: *"nothing an addon can read changes (cast
time, cost, usable), but the game plays its own proc alert sound"* (`Core.lua:147-150`), so it is
`gameSoundOnly = true` — the CVar `displaySpellActivationOverlays` **must stay on**, because
"turning the game's alert off might also stop the event" (`Core.lua:153-154`). Its art is the game's
own (default style `blz449489`, atlas IDs harvested live into `ns.db.blizzTex`).

---

## Per-proc map (mode → signal → timer source)

"timer" = what the numeric countdown is anchored to. **Design** = the hardcoded `dur` in the proc
table (an assumption); **learned** = `AS.Dur()` (real, seen out of combat); **game** = written by
the engine (the addon never sees it); **none** = `noTimer`, a state, not a proc.

| proc (class) | `mode` | in-combat signal | timer | game container | native alert |
|---|---|---|---|---|---|
| Shadow Trance (WARLOCK aff) | `trance` | aura ∥ overlay ∥ glow ∥ Shadow Bolt cast→0 | learned/design, `expirationTime` when the aura is readable | — | **yes** (`gameAlert`) |
| Decimation (WARLOCK demo) | `faster` | Soul Fire ÷ Shadow Bolt/Immolate | design 10 s | yes (`preset`) | — |
| Conflagrate (WARLOCK destr) | `usable` | `IsSpellUsable` + `onTarget` | **none** (`noTimer`) | — | — |
| Overpower (WARRIOR arms) | `usable` | `IsSpellUsable(+noPower)`, `combatOnly` | design 5 s, `holdCd` 5 s | — | — |
| Revenge (WARRIOR prot) | `usable` | idem | design 5 s | — | — |
| Shield Block (WARRIOR prot) | `usable` | idem, `combatOnly` | **none** | — | — |
| Execute (WARRIOR any) | `usable` | idem + `onTarget` (a *state*, not a proc) | **none** | — | — |
| Victory Rush (WARRIOR any) | `usable` | `IsSpellUsable`; display taken over by the game from buff 402975 | **game** (`gameHold`) | yes (`preset`) | — |
| Clearcasting (MAGE arc) | `free` | cost of Frostbolt/Fireball → 0 | design 15 s | yes (`preset`) | — |
| Missile Barrage (MAGE any) | `free` | cost of Arcane Missiles → 0, `unless = clearcasting` | design 15 s | yes (`preset`) | — |
| Heating Up (MAGE fire) | `faster` | Pyroblast ÷ Fireball, `threshold 0.46`, 3 stacks via `stackAt` | design 20 s | yes (`preset`) | — |
| Fingers of Frost (MAGE frost) | `overlay` | **the game's alert events only** | **game** (2 charges) | yes (0.18.2) | **yes** (`gameSoundOnly`) |
| Arcane Blast (MAGE arc) | `casts` | count of our own casts (15 s from the 1st); its raised `cost` tells when stacks went early | from the **first stack** (`fromFirst`) | yes (takes over once the buff is learned) | — |
| Omen of Clarity (DRUID any) | `free` | cost of Wrath/Touch/Claw/Shred/Maul → 0 | design 15 s | yes (`preset`) | — |
| Eclipse (DRUID bal) | `faster` | Starfire ÷ Wrath, `selfCheck` + `fullCut 1.75`, 4 charges via `perCharge` | design 15 s | yes (`preset`) | — |
| Nature's Grace (DRUID bal) | `aura` | **none** | **game** | yes | — |
| Maelstrom Weapon (SHAMAN enh) | `instant` | Lightning Bolt cast→0; stacks from its **mana cost** (20 %/stack) | design 30 s | yes (`preset`) | — |
| Elemental Focus (SHAMAN elem) | `free` | cost → 0, `skipInstant` (Maelstrom's free+instant cast must not count) | design 15 s | yes (`preset`) | — |
| Improved Stormstrike (SHAMAN enh) | `reset` | `GetSpellCooldown().isActive == false` early after the cast | user `showFor` (2-10 s) | — | — |
| Infusion of Light (PALADIN holy) | `faster` | Holy Light ÷ Flash of Light, `selfCheck` | design 15 s | yes | — |
| Hammer of Wrath (PALADIN any) | `usable` | `IsSpellUsable` + `onTarget` | **none** | — | — |
| Redoubt (PALADIN prot) | `aura` | **none** | **game** | yes | — |
| Vengeance (PALADIN ret) | `aura` | **none** (3 stacks) | **game** | yes, one slot per stack | — |
| Reckoning (PALADIN prot) | `aura` | **none** (4 stored attacks, buff has **no expiry** ⇒ `noEnd`) | **none** | yes | — |
| Searing Light (PRIEST holy) | `free` | cost of Holy Nova → 0; `others` (Smite, Lesser Heal free ⇒ that's Inner Focus, not this) | design 15 s | yes | — |
| Martyrdom (PRIEST disc) | `aura` | **none**; the buff is "Focused Casting" 27828 | **game** | yes | — |
| Riposte (ROGUE combat) | `usable` | `IsSpellUsable`, `combatOnly` | design 5 s | — | — |
| Cutthroat (ROGUE any) | `usable` | `IsSpellUsable(Ambush)` ∧ `not IsStealthed` | design 10 s | yes (`preset`) | — |
| Remorseless Attacks (ROGUE assa) | `aura` | **none** | **game** | yes | — |
| Thousand Cuts (ROGUE sub) | `aura` | **none** (5 stacks) | **game** | yes | — |
| Mongoose Bite (HUNTER any) | `usable` | `IsSpellUsable`, `combatOnly` | design 5 s | — | — |
| Counterattack (HUNTER surv) | `usable` | idem | design 5 s | — | — |
| Rapid Killing (HUNTER mm) | `aura` | **none** | **game** | yes | — |
| Deadly Aspects (HUNTER bm) | `aura` | **none**; **two** buffs ("Quick Shots"/"Quick Strikes", `multiBuff`, name-matched, English names only) | **game** | yes, both IDs | — |
| Hand of Edward the Odd (**Weapons**) | `aura` | **none** — buff 18803 by ID/name | **game** | yes | — |
| Revelation (**Enchants**) | `aura` | **none** — buff named from the enchant spell 1248805 | **game** | yes | — |
| Insight (**Enchants**) | `aura` | **none** — buff named from enchant spell 1248757, `minDur/maxDur` 8..12 s | **game** | yes | — |

Notes: the 37 entries above include the two new ones (`conflagrate`, `shieldblock`) absent from the
public 35-proc list. `spec` in the table is a **label only** (used at `Settings.lua:294`, `:746`) —
there is no spec/talent gating. `defaults.enabled = false` for the three gear procs (off since
0.23.15, `Core.lua:421-431`) and for Conflagrate (a talent not everyone takes).

### Weapons and Enchants — answered explicitly

**No weapon/enchant-state API is used at all.** `C_Item.GetWeaponEnchantInfo`,
`GetInventoryItemEnchantByID` and every `GetInventoryItem*` global are **absent from the source**
(0 hits across all 8 lua files). The sections are labels + **aura-container procs**:
`C_Item.GetItemNameByID`/`RequestLoadItemDataByID`/`GetItemIconByID` for the name/icon
(`Core.lua:574-601`), `C_Spell.GetSpellName(enchantSpellID)` cut at `" - "` for the buff name
(`Core.lua:585-591`, `AuraShow.lua:225-227`), and the actual detection is the buff (ID ∪ name ∪
duration window) shown by the game. `p.item` is never compared against an equipped item;
`ns.Mine()` returns true for `gear = true` for **every class** (`Core.lua:2206-2208`).
[INFERENCE] So these three alerts are really "a buff named X is on me" — they can fire for a player
not wearing the weapon/enchant if any buff with that ID/name appears, which is consistent with them
being shipped **off by default** since 0.23.15.

---

## Applicability to a compact timeline bar

We draw our own bar with our own icons on a power-scale axis. Ranked by transfer value:

**Directly transferable**
1. **The secrecy gate.** `num`/`str`/`clean` + `issecretvalue` (`Core.lua:527-548`) is the same rule
   as our `Compat.PlainOrNil`, and is proven against this client across 25 releases. Copy the
   *pattern* (probe with `v + 0` / `v .. ""` under `pcall`; never `tostring` a raw read; treat
   "spellId and name both nil" as *unreadable*, not as "no buff"), not their code.
2. **Baseline-learn + reference-spell ratio.** For our own casts this is strictly better than our
   current pure cast-predict for the *on/off* question, and cheap (2 reads per spell per pass,
   memoised). It also tells us the real `duration` out of combat for free (`AS.Dur`).
3. **Cadence model.** A ticker that exists **only** while `inCombat or anyActive`, at 0.2 s;
   10 Hz coalescing of `SPELL_UPDATE_USABLE`/`ACTIONBAR_UPDATE_USABLE`; one `WakeAt` expiry
   timer; 0.1/0.35 s re-checks after `UNIT_SPELLCAST_SUCCEEDED`. That is a concrete budget for
   our 10 Hz display / 1 Hz rescan split, and the "nothing runs between fights" property.
4. **The `usable` + `noPower` idiom** for Hunter traps/Feign, Execute-style thresholds and
   item "ready" cells; and `isActive`-only as the **one** cooldown read we can trust in combat.
5. **The native-alert events as a free signal.** `SPELL_ACTIVATION_OVERLAY_SHOW/HIDE` carry a plain
   spell ID; for procs we cannot see at all they give a combat-legal onset. Cheap, and their atlas
   harvesting (`Core.lua:2176-2178`) shows how to reuse the game's own proc art for our icons.

**Transferable as display, not as data** — the aura container. It is the *only* thing on this client
that shows "buff X with its real stacks and its real time left" in combat, and two independent
installed addons use it the same way. **It is not a data source for us**:
`AuraShow.lua:1-10` states the addon never learns when the game showed it, and the value paths
(`SetApplicationBar`, `SetApplicationCount`, `SetDurationCooldown`, `SetDurationText`) are
**write-only hand-offs** into a frame subtree the addon loses access to.

The blockers for *our* bar, from their own bug trail:
- **No continuous control.** The slot frame is positioned/sized **once** (`ApplySlot`,
  `AuraShow.lua:747-753`), the game shows/hides it, and in combat the addon may not touch it at all
  (`AS.Apply` defers, `AuraShow.lua:947-952`; "forbidden object", `AuraShow.lua:703-704` (`AS.Update` gate), `:707-717`; "blocked by
  secret aspects" for `OnHide`, `AuraShow.lua:494-498` (comment), phrase at `:495`). A sliding icon on a power-scale axis needs
  per-frame anchors ⇒ impossible on a game-owned frame. Cross-check: the installed
  `EllesmereUICdmTbbDecimals.lua:13-18` records that anything bound inside the aura button "must
  inherit all forbidden parent aspects from owner" and **hard-errors inside `AddAuraSlot`**.
- **One frame per aura identity, per stack count** — N slots for a stacking proc
  (`AuraShow.lua:561-584`), laid out by the container, with "no per-slot layout override"
  (`EllesmereUIResourceBars/EUI_ResourceBars_ArcaneSoul.lua:20-22`). Not a pool of icons we can
  re-order along an axis.
- **Slots can only be created out of combat** (`AS.Setup` refuses `InCombat()`,
  `AuraShow.lua:590`) — a bar that must handle a mid-fight spec/talent/gear change cannot build on it.

**The one idea from their neighbours worth stealing.** The installed
`EllesmereUICooldownManager/EllesmereUICdmTbbDecimals.lua:8-22` does what Shadowflare only
*displays*: it registers a hidden FontString via `SetDurationText`, the **engine writes the
remaining time (against the secret duration) into that FontString**, and their tick
**copies the string** (`engineFS -> bar._timerText`) — "the text is identical in and out of
combat". Same for the count: `EllesmereUI/EllesmereUI_WarriorCharges.lua:13-18` — the engine writes
the aura's true application count into a registered StatusBar, "**identical in and out of restricted
content. No polling, no cast handlers, no prediction: the fill IS the server count**". That is a
route to *real* durations/stacks in combat for our bar: hand the engine a hidden FontString per slot
and read the plain text back. [INFERENCE] Unverified by me in the sim/client; needs a probe.

Two direct corroboration of our design ceiling, from that same installed source:
- `EllesmereUI_WarriorCharges.lua:4-7`: for some buffs **`GetPlayerAuraBySpellID` answers nil while
  the buff is visibly up**, "so no Lua path, plain or secret, can ever hold the real count". This is
  exactly why Shadowflare's `AskGame()` sets `auraReliable=false` (`Core.lua:740-754`) and why our
  "route every read through PlainOrNil" rule must treat a nil answer as *unknown*, never as *absent*.
- `EllesmereUICdmTbbDecimals.lua:9-10`: "the remaining time is a secret value in combat — Lua cannot
  format it". Confirms PLAN.md §2.3(3).

---

## Verdict on the spell-state proxy for a timer bar

**Accurate enough to drive the *gate*, not the *bar*.** Use it as the boolean "proc is up / the
window is open" and as the sound trigger (that is exactly how Shadowflare uses it: the sound always
comes from its own detection, `AuraShow.lua:8`). It cannot anchor a timeline, for eight concrete
reasons visible in the code:

1. **No start, no end.** The proxy yields "the ratio is below baseline", never a timestamp. Their
   countdown is therefore `st.startedAt + pdur` where `pdur` is the **hardcoded design duration**
   in the proc table (`Core.lua:1565`, table `dur = 4..30`), and the only real expiry
   (`S.auraExp`) exists solely for Shadow Trance, where the aura is readable. A bar fed by this
   would render *assumed* durations for ~19 of 20 proxy procs.
2. **Stacks** — only where a cost/cast-time cut is linear and the max is known (`perStack` 0.2,
   `perCharge` 0.5, `stackAt` thresholds). It breaks when the proc makes the cost exactly 0
   (⇒ `skipInstant` needed, `Core.lua:192-196`), when haste moves both spells, when a flat
   spell-speed effect (Nature's Grace) inflates the baseline (`Core.lua:852-856`), and when
   `Presence of Mind` makes the reference spell instant (`Core.lua:140`). 6 of the 14 stacking-ish
   procs in the table can *only* get stacks from the game.
3. **Duration of the *window* is not observable** for `usable` procs: the game keeps answering "yes"
   after the window closed. Their mitigations (0.3 s no-filter, 0.5 s re-arm hold, 2 s re-new
   window, 1.5 s ran-out guard, `Core.lua:1584-1611`) show the answer is ±0.3-0.5 s *fuzzy at the
   edge* — tolerable for one flashing icon, visible as jitter on a sliding bar.
4. **Threshold tuning is per-proc and per-rank**: `threshold = 0.46` exists because 3 stacks cut
   Pyroblast to 0.25-0.42 of its cast time while 2 give 0.5-0.56, at the *current* rank
   (`Core.lua:133-142`). Nothing generalises; every proc needs in-game measurement.
5. **14 procs have no signal at all** (`mode = "aura"`: Remorseless, Rapid Killing, Deadly Aspects,
   Redoubt, Vengeance, Reckoning, Martyrdom, Nature's Grace, Thousand Cuts, Edward, Revelation,
   Insight, + Victory Rush's display + Fingers' charges). For these the proxy is silent — the
   description's "shown by the game itself, **without sound**" is literal
   (`Core.lua:1252` forces `soundChoice = "none"`). A proc bar that simply omits 14 of 35 named
   procs is a product decision, not a technical one.
6. **States are not procs.** Execute, Hammer of Wrath, Shield Block, Conflagrate
   (`onTarget`/`noTimer`/`still`) are target-threshold usability — true for most of a fight. On a
   timeline they occupy a slot continuously; they need a separate "ready" lane (as Shadowflare's
   `noTimer` + `style` split does).
7. **`noPower` accepted ⇒ "ready" ≠ "castable".** For window procs they count "usable with more
   rage" as true so the icon doesn't flicker with the rage bar (`Core.lua:963-965`); for states they
   don't. A power-scale axis must pick one meaning per lane.
8. **Cooldown end times are not available.** The only field they trust in combat is `isActive`
   (claimed NeverSecret per Forever's API docs, `Core.lua:307-309`); `startTime`/`duration` appear
   **only** in the debug probe. Every cooldown number in the addon is hardcoded
   (`cd = 5/6/8/30`, measured off tooltips by hand). `GetSpellCharges` is never called: charges are
   *inferred* (`perCharge`) or delegated to the game.

**Bottom line for us.** Spell-state proxy = cheap, combat-legal, **boolean-only**. It slots into
PLAN.md §3.2 as a *reconcile source* (confirm a predicted entry, cancel it when the ratio snaps
back, learn the real duration out of combat) and as the trigger for the sound. The **bar geometry**
must stay on our cast-predict timeline; where we need real in-combat numbers, the aura-container
hand-off (Shadowflare's display path, EllesmereUI's read-the-engine-written-text path) is the only
known route, and it is a display/one-frame-per-aura architecture — it will not slide.

---

## Confidence + what I could not verify

**High confidence (read the code, quoted above):** the mode table and every per-proc mode; the exact
API calls and fields read; the three AuraContainer hand-offs (`AddAuraSlot`,
`SetApplicationBar/Count`, `SetDurationCooldown/Text`); the `displaySpellActivationOverlays` CVar +
the four `SPELL_ACTIVATION_OVERLAY_*` events as the native-alert pair; absence of
`AddActiveSparkleSpell`/`C_ClientScene`/`DoAction`/`GetSpellCharges`/GCD/gear-enchant APIs; the
out-of-combat learning loop and its 0.23.20 `preset` relaxation; all secrecy constraints they
documented in comments and in the `Notes.lua` changelog (`:230`, `:237`, `:250`, `:280`, `:285-287`,
`:121-125`).

**Cross-checked against an independent primary source** (installed Forever addons, not blogs):
`EllesmereUI/EllesmereUI_WarriorCharges.lua`, `EllesmereUICooldownManager/EllesmereUICdmTbbDecimals.lua`,
`EllesmereUI/EllesmereUI_AuraKit.lua`, `EllesmereUIResourceBars/EUI_ResourceBars_ArcaneSoul.lua`,
`EllesmereUIUnitFrames/EUI_PlayerAuraBars_Bars.lua`, `TidyPlates_ThreatPlates/Widgets/AurasWidgetMidnight.lua`
— they confirm the container template name, `AddAuraSlot` + `candidateFilters.includeSpellIDs`
(map shape, not array), `SetApplicationBar`, and the combat-legality of the engine-written
count/text.

**Not verified (state plainly):**
- **Nothing was run.** No sim, no client. All behavioural claims are *their* claims, evidenced by
  in-game notes attributed to a tester, "Ben", with dates (`Core.lua:79`, `:88-90`, `:133-142`,
  `:228-231`, `:307-309`, `:963-965`) and by `Notes.lua`. I verified the code, not the measurements.
- `SpellCooldownInfo.isActive` being **NeverSecret** in Forever's API documentation
  (`Core.lua:307-309`) — I did not find that documentation, and the local
  `$WORK/wow-forever-sim` checkout has **no implementation of `AuraContainer`,
  `AddAuraSlot`, `SetApplicationBar`, `displaySpellActivationOverlays` or
  `SPELL_ACTIVATION_OVERLAY_*`** (grep: 0 hits), so the sim cannot validate this addon's core
  surfaces. Our own tests must probe them.
- The installed client ships no loose Blizzard lua (`_forever_/Interface/` contains only
  `AddOns/`), so `CustomAuraContainerTemplate`, `Blizzard_CustomAuraButton.lua` and the CVar name
  are **not** confirmed from the client itself — only from two independent addons' code.
  `TidyPlates/…/AurasWidgetMidnight.lua:32` probes the template at runtime via
  `C_XMLUtil.GetTemplateInfo("CustomAuraContainerTemplate")` — the pattern we should copy.
- The three gear procs' buff IDs (18803 / 1248805 / 1248757) and 14 of the class buff IDs are
  self-labelled "unchecked in Forever" (`Core.lua:360-368`); they fall back to name matching.
- The proc count on the CurseForge page (35) vs the code (37) is my count of
  `Core.lua:63-368`; `conflagrate` (0.23.16) and `shieldblock` (0.23.15) are absent from the page.
- Their 20-style catalog, fonts and placement UX (`Display.lua`) I read only structurally
  (`Display.lua:987-1240`, `:1623-1660`, `:1740-1825`) — out of scope for the detection question.
