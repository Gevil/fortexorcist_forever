# CodeReview7 — Iteration I (`git diff e58ea97..HEAD -- addon scripts tools`)

Reviewer: CodeReview7 (fresh). Date: 2026-11-04 (launch day). Scope: the ten Iteration I
commits (48bc949 probes, 047ebc6 data, 15fc9bc identity, 032bdf4 procs, d2e67f6 gate, b50e604
comms, e390b32 login order, 863b910 Hunter swing/range, 36894e6 test mode) — 68 files,
+12 320 −417. Every line:code quoted below was read from the file at HEAD; every catalog
claim was checked against `docs/api/wow-addon-api-agents/skills/*/references/generated/forever.json`
(1.60.1.70707 / interface 16001). `python3 scripts/api_lint.py` at HEAD:
`[api-lint] 60 files, catalog 4378 C_ symbols / 966 enums / 1816 events: OK`.

**Headline: 2 major, 6 minor. No blockers found.** The two majors are both real-client
behaviour defects in the comms path: (1) the PARTY half of the Warlock comms (and of the
Announce group route) can never send on the real client, because `plainCall` collapses
`GetNumGroupMembers()`' number into the boolean `true` and the count test then reads
`tonumber(true) = nil`; (2) a line the client refused with `AddOnMessageLockdown` is
re-queued with a **fresh `queuedAt`** on every pump cycle, so the 300 s TTL and the whole
"stale restatements die" law are disabled for exactly the lockdown-hold lines the outbox
exists to hold, and the pump runs as a 1 Hz chain for the whole lockdown. Both are verbatim
in the code quoted at the lines; both suites miss them because the tests inject numeric
`readers.groupCount` and drive `PumpOutbox` with a clock the lockdown leg never re-stamps.

Verifications of the priority areas are at §2–§7; dead code at §8; counts at §9.

---

## 1. Findings

### F1 — MAJOR — `addon/Forte_Warlock/Core/Comms.lua:368-377` — party channel is nil on the real client; every party send is counted `noGroup`

```lua
function C:Channel()
    local r = self.readers
    if plainCall(r.isRaid or _G.IsInRaid) then return "RAID" end
    local members = r.groupCount
        and r.groupCount()
        or (type(_G.GetNumGroupMembers) == "function"
            and plainCall(_G.GetNumGroupMembers))
    if (tonumber(members) or 0) > 0 then return "PARTY" end
    return nil
end
```

and the classifier that eats the number, Comms.lua:326-333:

```lua
local function plainCall(fn, arg)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, arg)
    if not ok then return nil end
    local plain = FX.Compat.PlainOrNil(value)
    if plain == nil then return nil end
    return plain and true or false
end
```

**Why it is wrong on the real client.** In production `C.readers` leaves every slot nil
("Production leaves every slot nil and reads the real surface", Comms.lua:234-235), so the
party leg runs `plainCall(_G.GetNumGroupMembers)`. `GetNumGroupMembers` returns the member
COUNT (a number ≥ 1 in a party); `plain and true or false` converts every plain truthy
value — 1, 4, 25 — to the **boolean `true`**; `tonumber(true)` is `nil`; `(nil or 0) > 0`
is false; `Channel()` returns nil. `Send` (Comms.lua:560-564) then takes

```lua
    if channel == nil then channel = self:Channel() end
    if channel == nil then
        self.counts.noGroupSkipped = self.counts.noGroupSkipped + 1
        return "noGroup"
    end
```

The raid leg survives only because `IsInRaid()` is genuinely boolean. The same file's
`ScanRoster` (Comms.lua:688-691) shows the correct shape — raw `pcall` + `tonumber(PlainOrNil(n))`
— so this is a one-leg slip, not the file's law. **Pre-existing in this file** (the pattern
is identical at e58ea97, from 2e0124c wave 2b), not introduced by b50e604 — but b50e604
rebuilt the send/outbox half around it, I3b owns the file, and launch day is today.

**Failing scenario (real client).** Warlock logs into a 5-man party, default install
(`CommsEnable = true`, Pages/Warlock.lua:103, UI/Frame.lua:206), chat unrestricted.
`GROUP_JOINED` → `OnRosterChanged` (Comms.lua:798-812) → `SendCmd("HG")`/`SendCmd("SG")` →
`Send` gates pass (`Enabled` ✓, `chatLocked` ✗) → `Channel()` → `IsInRaid()`=false,
`plainCall(GetNumGroupMembers)`= `true` → nil → `noGroupSkipped++`. Every shard/stone
count announce, every `SU1`/`SE1` summon phase: zero bytes on the wire, forever; `/fx
status` grows "solo" while the roster panel lists 5 members (the roster's own scan uses the
correct numeric read, so the panel fills and the comms stays mute — the split is the
symptom). The suite passes because `C.readers.groupCount = function() return 5 end`
(test_warlock_group.lua) exercises the injected half only.

**Fix.** Classify the count as a number, keeping the secret law:

```lua
    local members
    if type(r.groupCount) == "function" then members = r.groupCount()
    elseif type(_G.GetNumGroupMembers) == "function" then
        local ok, v = pcall(_G.GetNumGroupMembers)
        v = ok and FX.Compat.PlainOrNil(v)
        members = (type(v) == "number") and v or nil
    end
    if (tonumber(members) or 0) > 0 then return "PARTY" end
```

**Same shape, same file-family (adjacent, pre-existing, defaults OFF so opt-in-only):**
`addon/Forte_Messages/Core/Announce.lua:188-192` (`Announce:Group`) —
`and plainCall(_G.GetNumGroupMembers))` then `if (tonumber(members) or 0) > 0 then
return self:send(text, "PARTY") end`. On the real client the PARTY announce leg of every
RaidMsg row is dead by the same mechanism; invisible by default (owner 2b048c5 ships
announcements OFF, test_warlock_announce.lua:151-174 pins "ships OFF"), so it bites only
the user who checks "party". Fix identically.

---

### F2 — MAJOR — `addon/Forte_Warlock/Core/Comms.lua:419-436` + `:513-518` — the lockdown-hold re-stamps `queuedAt`, disabling the TTL; the pump becomes a 1 Hz chain for the whole lockdown

`Enqueue` stamps arrival unconditionally (Comms.lua:419-427):

```lua
function C:Enqueue(text, channel, kind, mode, tries)
    local q = self.outbox
    local now = self:Clock()
    tries = math.floor(tonumber(tries) or 0)
    placeOutbox(q, {
        text = text, channel = channel, kind = kind, tries = tries,
        queuedAt = now,
```

and `PumpOutbox`'s lockdown leg (Comms.lua:513-518) sends every held line back through it:

```lua
    if status == "locked" then
        -- ... the line goes back at
        -- the head with its tries UNSPENT (the client never saw it) and
        -- waits for the lift — ...
        self:Enqueue(item.text, item.channel, "gate", "front", item.tries)
```

The staleness bound the header law promises (Comms.lua:493) reads the field Enqueue
just re-stamped:

```lua
    if now - (item.queuedAt or now) > self.OUTBOX_TTL then
```

**Why it is wrong on the real client.** `Enqueue(mode = "front")` resets `queuedAt = now`
on every gate-cycle, so `now - item.queuedAt` never exceeds ~1 s: the `OUTBOX_TTL = 300`
law of the header ("A line ... older than OUTBOX_TTL = 300 s is dropped and counted",
Comms.lua:67-68) can never fire for a lockdown-held line. The retry budget cannot retire it
either — `tries` is passed through unspent **by design** ("the client never saw it"), so
`item.tries >= self.RETRY_MAX` (Comms.lua:503) never trips while the gate keeps answering
`locked`. Each cycle ends in `Enqueue`'s `self:_SchedulePump(self:PumpDelay())`
(Comms.lua:434) with the re-queued head's `nextAt = nil` (`mode ~= "tail"`), so
`PumpDelay()` returns `PUMP_STEP` = 1 s and a fresh `C_Timer.After` arms the next pass:
a one-second pump chain, one event + `chatLocked()` (which runs `SS.Refresh` + two pcall'd
client predicates, Comms.lua:337-351) every second, for the whole duration of the lockdown.

**Failing scenario (real client).** Warlock joins a raid on a build whose raid chat
restricts addon messaging (the shipped raid posture the I3b gate set exists for —
`addonChatRestrictionsForced` / `InChatMessagingLockdown`, Announce.lua:100-107 citing
secrets-unknowns.md:62-63). First `HG1` passes the pre-gates (not yet locked), the client
answers **11 = `AddOnMessageLockdown`** (verified member @ChatConstantsDocumentation.lua:146,
`CODE_CLASS[11] = "lockdown"`, Comms.lua:256) → head-enqueue. The lockdown lifts nothing
and locks: next pump at t+1 → `Send` hits its own pre-gate `self:chatLocked()` → true →
`"locked"` (Comms.lua:556-559) → `Enqueue("front")` → `queuedAt = now`. The 1 Hz chain
runs the whole raid (hours). On `ADDON_RESTRICTION_STATE_CHANGED` (registered,
Comms.lua:901-909) at hour 0:42 the lift pump flushes the **head**: a 42-minute-old
`HS1 3` count, older than every fresh restatement queued behind it — the exact outcome the
header law forbids ("a stale line is worth less than the fresh one already queued behind
it"). The suite drives `PumpOutbox` with its own clock and never asserts TTL expiry
through the locked leg, so it passes.

**Fix.** Carry the arrival stamp on the gate re-queue — one parameter:

```lua
function C:Enqueue(text, channel, kind, mode, tries, at)
    ...
        queuedAt = at or now,
```

and in the locked leg pass the original:
`self:Enqueue(item.text, item.channel, "gate", "front", item.tries, item.queuedAt)`.
(TTL expiry then drops the line at the first pump ≥ 300 s in, counted, and the 1 Hz chain
dies with the queue.)

---

### F3 — MINOR — `addon/Forte_Core/Core/TestMode.lua:309-315` — the re-fill ticker runs the whole session and its cancel seam is not in the pinned catalog

```lua
    if C_Timer and C_Timer.NewTicker then
        local ok, ticker = pcall(C_Timer.NewTicker, self.pumpSeconds, function()
            T:Pump()
        end)
        if ok then self._ticker = ticker end
    end
```

Created in `OnEnable` — which the module framework runs **exactly once** (`FX._enabledModules`
ledger, Init.lua:23; no DisableModule exists in the tree) — so from PLAYER_LOGIN to
logout a 1 Hz closure fires forever, doing `if not self.active then return 0 end`
(TestMode.lua:252) for every second the demo is off, including in combat and at the
logout screen. The cancellation half (`self._ticker.Cancel`, TestMode.lua:320-321,
feature-detected) guards a method **the pinned catalog does not declare**: the catalog's
`C_Timer.NewTicker` (@UITimerDocumentation.lua:21) declares the return only as
`cbObject: TickerCallback`; no `TickerProxy`/`Cancel` record exists in any
`forever.json`. The feature-detect is the right call (catalog rule: "a source miss is
unknown, not proof of removal"), so on the real client the ticker most likely *is*
cancellable — on a client where it is not, `OnDisable` (the only stop) never runs in
production and the pump is permanent. Bounded cost (one no-op closure/second), so minor;
the honest options: bound it (`C_Timer.NewTicker(seconds, fn, iterations)`, the declared
nilable 3rd arg) so an idle session's pump self-terminates and re-arms at `Start`, or
start/stop the ticker in `Start`/`Stop` instead of `OnEnable`/`OnDisable`.

---

### F4 — MINOR — `addon/Forte_Timer/Module.lua:810` vs `:833` — `DEMO_PARKED` is defined twice; the first block is dead

Module.lua:810 (after the `OnEnable` feeder hunk) and :833 (immediately before `OnEvent`)
both open with `local DEMO_PARKED = { UNIT_SPELLCAST_SENT = true, ... }` — byte-identical
11-line tables. The second shadows the first; the single reader is the `OnEvent` gate
(:855) `... and DEMO_PARKED[event]`, bound to the :833 copy. The :810 copy is dead code
committed in 36894e6: a maintainer who parks one more event edits the first copy and the
gate silently does not change. **Fix:** delete Module.lua:809-820 (the comment + table +
blank line of the first copy), keep the :830-841 copy that `OnEvent` closes over.

---

### F5 — MINOR — `addon/Forte_Core/Core/Locale.lua:72,76-78` — `Locale.canonicalByAliasID` is built and never read

```lua
Locale.renamedToCanonical = {}
Locale.canonicalByAliasID = {}
for i = 1, #Locale.RenameAliases do
    local pair = Locale.RenameAliases[i]
    Locale.renamedToCanonical[pair.alias] = pair.name
    for j = 1, #(pair.aliasIDs or {}) do
        Locale.canonicalByAliasID[pair.aliasIDs[j]] = pair.name
    end
end
```

Repo-wide search finds no consumer of `canonicalByAliasID` beyond these build lines
(`Locale.lua:72` and `:77` only). The id-fold the map advertises is unnecessary: the
id-first lookups resolve through the generated data (the alias rides the ByName table —
`Forte_Shaman/Data/Shaman.lua:194-195` `["Lightning Mastery"] = 16166`) and the name fold
rides `renamedToCanonical` in `CanonicalName` (Locale.lua:160-165). Dead data introduced
by 047ebc6. **Fix:** delete lines 72 and 76-78 (keep the `renamedToCanonical` leg).

---

### F6 — MINOR (dead code, confirmed) — `addon/Forte_Core/Core/Locale.lua:425` — `LocaleModule.OnEvents` has no dispatcher

```lua
function LocaleModule.OnEvents(event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        Locale.state.spellsBuilt = false
        Locale.BuildSpellAliases()
```

**CONFIRMED, not refuted.** No dispatcher exists: the only `OnEvents` references in
`addon/` are this definition (Locale.lua:425) and `test_login_order.lua:211`'s census
(`countMethod({ "Locale" }, "OnEvents")`) — which exists precisely to prove the count is
zero, and whose header states it ("`Forte_Core/Core/Locale.lua`'s `LocaleModule.OnEvents`
PLAYER_LOGIN leg is never dispatched by anyone (no OnEvents dispatcher exists in the
tree)", test_login_order.lua:42-46). The bootstrap frame (Init.lua:228-235) registers
`ADDON_LOADED`/`PLAYER_LOGIN`/`PLAYER_ENTERING_WORLD` and dispatches only
Migrate/RefreshPlayerClass/RunLoginPass; the module loop calls `OnEnable` (Init.lua:34-48),
and Locale's login/class rebuilds ride its `OnEnable` and `OnClassChanged`. The hook
body can never run on any client. **Fix:** delete `LocaleModule.OnEvents` (Locale.lua:425-…),
keep the `OnEnable`/`OnClassChanged` legs; the census test can then count the hook absent.

---

### F7 — MINOR — `addon/Forte_Warlock/Core/Comms.lua:220` + `:1066` — `counts.rateSkipped` is declared, printed, and never incremented

Comms.lua:220 `rateSkipped = 0,      -- the rate law of the header stopped the send`,
printed by `StatusLine` (:1066, `" | rate %d |"` with `c.rateSkipped`) — and no line in
the file writes it. The rate law itself is silent: `RateGate` (:380-386) returns `false`
without counting, and the three gated call sites (:806 query burst, the `HG`/`SG` answer
leg in `OnAddonMessage`, `AnnounceState`) drop the send with no counter. `/fx status`
prints `rate 0` for a session whose comms is rate-shaving constantly — a misleading
launch-day instrument (the header leans on "a skipped send is SILENT and COUNTED
(`/fx status` prints the ate-list)"). **Fix:** count at the three call sites
(`if not self:RateGate(...) then self.counts.rateSkipped = self.counts.rateSkipped + 1 ... end`),
or pass `self` into the gate.

---

### F8 — MINOR — `addon/Forte_Hunter/Core/Tools.lua:345,348` (+ field doc `:822-823`) — `rangeEdges` is write-only

`OnSwingRange` writes it on both branches:

```lua
    if not checked then
        self.rangeEdges = false
        return
    end
    self.rangeEdges = true
```

The `NewSwingTracker` state block declares it (`rangeEdges = nil, -- the last edge's
checksRange state:`). No reader exists: searches across `Forte_Hunter/` find the two
writes and the declaration only. Introduced by 863b910 as telemetry of "did the range
check ever speak" — a launch-probe fact (F17-style) that nothing reports. Minor dead
state. **Fix:** delete the field + both writes, or surface it (the tracker's
`StatusLine`) where the launch-day probe can read it — the second option is the
probe the `EnableRangeCheck` opt-in needs evidence for.

---

## 2. Priority area (1) — `Forte_Core/Core/Database.lua` + `Identity.lua`: no finding

Question asked: can any path lose a user's settings, or pick a wrong profile key
(placeholder names, secret reads, the migration re-key, the lazy `RekeyLegacy`)?

- **Placeholder names.** An early `UnitName("player")` answering `UNKNOWNOBJECT` is a
  failed read: `isPlaceholderName` (Identity.lua:61-70) matches the localized global
  *and* the enUS literal, `SelfName`'s `consider` drops it (Identity.lua:173) and
  caches nothing, `Remember` refuses to store it (Identity.lua:139), `Same` refuses to
  fold it (Identity.lua:122). A key built on a placeholder is unreachable by construction.
  The fresh-install fallback profile `DB.CharacterKey() or DB.SHARED_NAME`
  (Database.lua:83) is the documented shared-profile landing, not a key error.
- **Secret reads.** Every value crosses `PlainOrNil` **before** any string op
  (`plainName`, Identity.lua:45-50; the three API calls each in their own pcall,
  :181-186; `stripRealm`/`gsub`/`lower` inside the outer pcall, :91-98). Secret strings
  classify to nil and key nothing. Catalog confirms the shape: `UnitNameUnmodified` /
  `UnitFullName` / `UnitName` carry `SecretWhenUnitIdentityRestricted` and return
  `(unitName, unitServer)` (@UnitDocumentation.lua:2522/:1223/:2488) — the "ask all
  three, keep the fullest" defence is against the display half, sound as documented.
- **The v3 re-key.** `RekeyLegacy` (Database.lua:185-253) is bound-gated
  (`boundToCharacter`: a key of `characters` — the old law bound every key it wrote —
  or `active`), so a user-named profile `"Uther-Raid"` that shape-matches is left in
  place; it never overwrites (`if moveKey and p.byName[key] == nil`, :218-221); it moves
  the best row preferring non-empty settings (:211-216); a self-binding follows the
  rename, a binding to any other profile rides (:228-243). Idempotent by content
  (post-move, `legacyOf` finds no key with a hyphen).
- **The lazy RekeyLegacy.** The ladder's `MIGRATIONS[3]` runs at ADDON_LOADED, where the
  name APIs are not ready — the step stamps v3 over un-re-keyed rows and raises the
  once-flag only on a RAN pass (`rekeyed = true` sits **after** the key-nil returns,
  Database.lua:186-193), so the first readable key of the session runs the same law
  through `CharacterKey` (:324-326, `pcall`, flag-guarded). The recursion the flag
  guards (key→rekey→key) is closed by caching the key **before** the call (:316
  comment, "198 levels measured"). Logout→login reloads the Lua state, so the
  session-scoped `cachedKey`/`selfCache`/`rekeyed` cannot cross characters.
  `RekeyLegacy` also raises `rekeyed` before the `isTable(p)` bail (:193-195) —
  harmless (the file it would move is the file the guard owns), noted for the manager.
- **`Settings.selfName`** (Settings.lua:129-146) delegates to the DB key law, packs the
  raw fallback identically, and "Player" only when the read itself failed — consistent.
- **`Announce:Whisper`** (Announce.lua:251-254) `Remember(who)` → `Raw(canon)` keeps the
  GAME's spelling as the whisper target (the toGame law of upstream-api §2); the
  callers pass unit-API names (Forte_Messages/Module.lua:486, :521), so the remembered
  spelling is the game's. Correct.

No setting-loss path found. [INFERENCE] The one live assumption is the research note's
"no hyphen in names" (upstream-api-2026-11-03.md:143, Atraeau b64aab0a) — the key law is
as cited.

## 3. Priority area (2) — Comms outbox

- **Unbounded growth:** none. The cap trim (`while #q > self.OUTBOX_MAX do table.remove(q, 1)`,
  Comms.lua:430-433) runs on every `Enqueue`; TTL, `RETRY_MAX`, `ClearOutbox` on
  `GROUP_LEFT` (:529-537, and `OnGroupLeft` :817-824) and `_stopped` on `DisableEvents`
  (:1013-1041) all bound it. The `_lastAt`/`_lastSent` key sets are fixed strings.
- **Timer chains that never stop:** the pump is one `C_Timer.After` armed at a time
  (`_SchedulePump` guards `_stopped`/`_pumpArmed`/empty queue, :457-477); every
  re-arm path is bounded **except** the lockdown-hold chain of F2, which is bounded only
  by the lift/group-leave/disable.
- **Sends in lockdown:** none. `chatLocked()` gates pre-send (:556-559), pumped lines
  re-gate every pass; the four legs (`SecretState.chat`, `InChatMessagingLockdown`,
  `AreOutgoingAddonChatMessagesRestricted`, the `addonChatRestrictionsForced` CVar via
  `C_CVar.GetCVarBool` @CVarDocumentation.lua:50, all declared) are consumer-law-safe
  (only a plain true locks).
- **Sends on a default install:** solo is silent by the channel law (F1's mechanism makes
  the party leg silent too — the wrong way). `CommsEnable` defaults **ON**
  (Pages/Warlock.lua:103, UI/Frame.lua:206, `Enabled()` default-on :356-363) — the
  documented H6 posture "ON in a group, OFF solo"; the owner's OFF-by-default ruling
  (2b048c5) covers the Announcer, whose rows ship OFF and are pinned by
  test_warlock_announce.lua:151-174 ("a default install stands mute"). Report as design,
  flagged for the owner's launch-day re-confirm given F1.
- **Event payloads:** `CHAT_MSG_ADDON` is `(prefix, text, channel, sender, target,
  zoneChannelID, localID, name, instanceID)` (@ChatInfoDocumentation.lua:800) — the
  dispatcher reads positions 1, 2, **4** (`onCommsEvent`, Comms.lua:904-906:
  `self:OnAddonMessage(a1, a2, a4)`) — correct, the 3rd-field trap handled as documented.
  `SendAddonMessage(prefix, message, chatType)` call shape and the `SendAddonMessageResult`
  0..12 `CODE_CLASS` map verified member-for-member (@ChatConstantsDocumentation.lua:146);
  the `RegisterAddonMessagePrefixResult` 0/1/2/3 = Success/Duplicate/Invalid/MaxPrefixes
  map verified for `prefixState` (@:132).
- **The 255-byte law:** `MAX_WIRE_BYTES = 255` enforced pre-send (:545-550) ✓.

## 4. Priority area (3) — TestMode: leak / post-exit block / announce / settings

- **Synthetic leak into real play:** the tag is the scrub key; `Stop` scrubs **before**
  dropping the flag (TestMode.lua:236-250); `OnEnable`-time feeders are replaced by name
  (`RegisterFeeder` idempotency, :124-134); the mode stops on `PLAYER_REGEN_DISABLED`
  (combat start — `Start` additionally refuses in combat, `InCombatLockdown`
  @RestrictedActionsDocumentation.lua:44, declared ✓) and on `PLAYER_LOGOUT` /
  `PLAYER_LEAVING_WORLD` (@PlayerDocumentation… declared ✓). Every entry **writer** is
  gated and all were read on disk: `M:ReadAll` (Cooldown/Module.lua:230),
  `M:RecordCastEvent` (:547), `Procs:OnProcSeen` (Procs.lua:263), `Enchants:ReadAll`
  (Enchants.lua:274), `M:Logic`'s `Casts:Pump` + `Reconcile:SweepAll`
  (Timer/Module.lua:613-622), the event spine's `DEMO_PARKED` set (:855 — every name a
  declared event incl. `UNIT_SPELLCAST_SENT` @UnitDocumentation), the combat-end sweep
  gate (:912-916). The row/entry lifecycles (`Rows:Sweep`, the 10 Hz draw) run ungated
  over tagged rows by law (the panel animates) and cannot write: `Rows:InsertFromCast`
  is reachable only from the gated `Casts:Pump`/gated `Reconcile`/the tagged `demoFill`.
- **Blocks real reads after exit:** every gate re-reads `IsActive()` per call; `Stop`
  clears it; `demoFill`/`demoScrub` are feeder-private. No read/draw path is gated
  (verified: the Display path and `Count`/`Status` read unconditionally).
- **Fires an announce:** the four world-facing legs and the chat leg are all
  tag-gated — `FX_COOLDOWN_READY` (Cooldown/Module.lua:660, the tag rides the pop
  snapshot `info._source = e._source`, Engine.lua:490), `FX_TIMER_FADING`
  (Rows.lua:632), `FX_TIMER_EXPIRED` (:671), `FX_TIMER_BROKEN` (:576-577), the
  `opts.onExpire` announce leg (:644). The module's own prints are `FX.Print` local
  echoes; no send API is named in TestMode.lua (grep-clean).
- **Writes settings:** none (no `FX.Settings` touch in TestMode.lua, the feeder pairs,
  the `demoFill`/`demoScrub` bodies). The options row is an action button
  (`s.BTN`, Pages/Cooldown.lua:244-252; `W.BTN` @Widgets.lua:800 — no `key`, `spec.onPress`
  on click @:833) → `FX.TestMode:Toggle()`; the sparse store is untouched.
- Residuals = F3 (ticker) only.

## 5. Priority area (4) — Init.lua RunLoginPass on PLAYER_ENTERING_WORLD

Read on disk (Init.lua:201-228; the PEW leg at :246-253). One-shot by `FX._loginDone` checked before
anything; the PEW leg is a no-op on the normal order (`return false`), and carries the
full pass when PLAYER_LOGIN was missed — the CDM-published §7.3 law, the enable loop
`pcall`-guarded per module via `EnableModule` (Init.lua:34-48, raising OnEnable prints
and the loop continues, so the pass cannot abort mid-loop). `pcall(UnitClass, "player")`
reads the 2nd return = `classFilename` (@UnitDocumentation.lua:910 `(className,
classFilename, ...)` — `className` is the ConditionalSecret one, `classFilename` the
plain token, matching the pre-change `UnitClass("player")` usage the commit moved).
`LoadClassAddOn` runs before the enable loop, `_loginDone` is set after it, so LoD class
modules register into the loop (and the late seam, :61-63). The bootstrap frame remains
the tree's only top-level `RegisterEvent` (AGENTS.md carve-out). No finding.

## 6. Priority area (5) — Hunter range/swing: secret compares, plain-boolean changes

- `OnSwingRange` (Tools.lua:339-356): both payload fields pass `PlainOrNil` **before**
  the `== true / == 1 / == nil` compares — secret values become nil, no compare ever
  sees a secret. The 3-return payload `(swingType, isInRange, checksRange)` is verified
  (@SwingTimerDocumentation.lua:53, isInRange/checksRange declared non-nilable — the nil
  leg is defensive, not a fabricated shape). `nil = no check possible` returns before
  any stamp ✓.
- Plain-boolean behaviour changes: (a) `unitBool` (Range.lua:141-150) — pre-change the
  `(b == nil) and pcall(...) or pcall(...)` ternary truncated the pcall to its ok-flag
  (multi-assign), so **every** leg returned nil for true and false alike and the meter
  never rendered a band; post-change a plain `false` is the negative the ladder needs.
  The fix, not a regression. (b) `nativeRangedInRange`/`SW.rangeReader`/`closeReader`
  split the ok-test from the `PlainOrNil` pass so a plain `false` speaks "out" — each
  value classified first, secret-safe. (c) the `factsInRange = true/false` stamping on
  plain edges (Tools.lua:351) rides the readiness gate (:441) and is new only in the
  sense that the edges themselves are new (`EnableRangeCheck` opt-in, `C_SwingTimer
  .EnableRangeCheck` declared @SwingTimerDocumentation; the single-owner request table
  :1178-1192 + UI/Range.lua:188-196 routing is sound, feature-detected, no-op in the sim).
- Engine-driven Swing fill: default OFF (`D._fillMode = "lua"`, UI/Swing.lua:159), the
  gate result computed in `Init` (:359), `_EngineFillPass` reachable only when
  `_engineFill` is true (:969-972); `_DegradeEngineFill` is one-way; `C_DurationUtil
  .CreateDuration` + `SimpleStatusBarAPI:SetTimerDuration` declared; the fill's
  OnUpdate law unchanged (the script exists only on a shown anchor, Swing.lua:1135-1153).
  No finding.
- Residual: F8 (write-only `rangeEdges`).

## 7. Priority area (6) — sweeps

- `FX:CallSafe`: **zero uses** (only the Locale.lua:341 comment naming the law).
- Top-level `RegisterEvent`: only the Init.lua bootstrap (grep at column 0). New frames
  are created inside `OnEnable`/`OnEvent`-time code paths (Comms `EnableEvents` :983-1010,
  TestMode `OnEnable`, Swing `_BuildFill`) — the taint rule holds.
- `OnUpdate` added anywhere: none (diff-wide scan; every hit is a comment/test asserting
  the law; TestMode's pump is a `C_Timer` ticker, tested as such).
- `python3 scripts/api_lint.py` → OK (C_/Enum/event registry). Catalog spot-checks beyond
  the lint: `GetRealmName` @ConnectionDocumentation.lua:68, `CheckInteractDistance`
  @PlayerScriptDocumentation, `UnitCanAttack`/`UnitExists`/`UnitIsDead`/`UnitAttackSpeed`
  (returns `(attackSpeed, offhandAttackSpeed, rangedAttackSpeed)` @UnitDocumentation
  :681 — the `ATTACK_SPEED_LEG` mapping @Tools.lua:250 is right), `InCombatLockdown`,
  `C_Timer.After`/`NewTicker`, `C_CVar.GetCVarBool`, `C_EventUtils.IsEventValid`,
  `PLAYER_REGEN_DISABLED` @UnitDocumentation:3884, `PLAYER_LOGOUT` @SystemDocumentation
  :156, `PLAYER_ENTERING_WORLD`/`PLAYER_LOGIN`, `GROUP_FORMED/JOINED/LEFT/ROSTER_UPDATE`
  @PartyInfoDocumentation, `ADDON_RESTRICTION_STATE_CHANGED` @RestrictedActions
  Documentation — all declared. The legacy `wipe`/`table.concat` idioms are not in the
  catalog (source miss ≠ removal; both are tree-wide convention since wave 1 — [INFERENCE]
  FrameXMLUtil core) — not flagged.
- I3e/I2b data: `Data/*.lua` changes ride the generator (headers + `tools/spell_lists
  /*.json` + `overrides_70707.json` touched in the same commits, AGENTS.md law kept);
  the Registry kind-band additions are plain Lua-pattern terms (no `|` alternation —
  the lint's own guard), anchored (`^Ignite`, `^Bloom`, …) and covered by test_kinds.
  No hand-typed ids in Lua.
- gate.py `--no-saved-vars` (d2e67f6): simulation-harness flag, gate-only, fine.
  deploy.sh SVFix-guard prose change: script-only, fine.

## 8. Dead code — verdicts

| Site | Verdict |
|---|---|
| `Locale.lua:425 LocaleModule.OnEvents` | **CONFIRMED dead** — no dispatcher exists in the tree (F6; test_login_order.lua:42-46 states it; census test proves zero delivery) |
| `Forte_Timer/Module.lua:810 DEMO_PARKED` (1st copy) | dead — shadowed by :833 (F4) |
| `Locale.canonicalByAliasID` (Locale.lua:72,76-78) | dead — zero consumers (F5) |
| `Comms.counts.rateSkipped` (:220,:1066) | never incremented (F7) |
| `Tools.lua rangeEdges` (:345,:348,:822) | write-only (F8) |
| `DB._clearRekeyFlag` / `I._clearSelfName` / `DB._clearKeyCache` / `DB.Stamp` | **alive** — test seams by their own labels, `Stamp` used by `Migrate` |
| `Rows:Compact` | **alive** — `demoScrub` is the documented out-of-sweep caller (Rows.lua:722 + Module.lua demoScrub) |

## 9. Counts

| Severity | Count |
|---|---|
| blocker | 0 |
| major | 2 (F1 party-channel nil; F2 lockdown TTL reset) |
| minor | 6 (F3 ticker, F4 DEMO_PARKED dup, F5 canonicalByAliasID, F6 LocaleModule.OnEvents, F7 rateSkipped, F8 rangeEdges) |

Manager re-check notes: F1/F2 live in lines b50e604 touched around, and F1's shape is
pre-existing at e58ea97 in both files (2e0124c) — labelled as such above. Everything else
is Iteration I code. Every quoted line was read from the file at HEAD on 2026-11-04.
