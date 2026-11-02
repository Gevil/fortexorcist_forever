# Forte_Messages — Self Messages, Sound, Party/Raid Messages

> Home note (2026-11-02): this note documents `addon/Forte_Messages/` and
> lives in the repository's `docs/` — nothing under `addon/` is a place for
> notes, because the whole of `addon/` is what the game loads. The paths it
> cites (`Core/Sounds.lua`, `Pages/RaidMsg.lua`, …) are relative to
> `addon/Forte_Messages/`; `Forte_*` paths outside that prefix are relative
> to `addon/`.

The add-on that listens. It owns **no game events of the tracked kind**: the
Forte_Core event bus (`addon/Forte_Core/Core/Events.lua`) is the seam, and
this add-on subscribes:

| Event (wire string)      | Payload                     | Fired by |
|--------------------------|-----------------------------|----------|
| `FX_COOLDOWN_READY`      | `(name, now, texPath, category)` | Forte_Cooldown's ready-pop pass (`Forte_Cooldown/Module.lua`'s `ProcessReadyPops`, driven by its 10 Hz ticker — the hook point the plan named, nil-guarded `if FX.Fire then FX.Fire(...) end`) |
| `FX_TIMER_EXPIRED`       | `(spell, target, kind)`     | **Forte_Timer fires it** — `Forte_Timer/Core/Rows.lua`'s Sweep, at the row's true expiry (the moment `remaining <= 0` on a `NORMAL` row, the promote of the `:1064-1068` law), once per row (`row.expiredFired`), `FX.Fire` nil-guarded, the payload the row's plain fields. Review 4 **E3**: this add-on used to *wrap* the Timer's `options.onExpire` at its own enable, a seam the real enable order never reached — the fire now lives where the expiry happens, so no enable order can lose it. It is INDEPENDENT of the Timer's `AnnounceExpiry` chat gate (that gate is the source's chat channel, `m7`); this module's own rows decide whether anything is heard, and every one of them is opt-in, so the shipped defaults are silent (the original has no per-expiry message/sound) |
| `FX_TIMER_FADING`        | `(spell, target, kind, secondsLeft)` | **Forte_Timer fires it** — `Core/Rows.lua`'s Sweep fade block, the verbatim port of `ST_UpdateSpellTimers` (`Forte_Timer.lua:1049-1056`): once per row, when `fadeWarn > 0` and remaining crosses it; the stamp (`row.fadeWarn`, the original's column 12) is `FX.Timer.FadeWarnings[spell]` at insert (`ST_GetFadeTime`, `:1590-1603`) |
| `FX_TIMER_BROKEN`        | `(spell, target, kind)`     | **Forte_Timer fires it** — `Core/Rows.lua:OnAuraAbsent`'s removal, the `:1207-1211` law site (aura confirmed gone past the BUFF_DELAY grace with more than MAXLAG of window left — the CC broke early). The original's `if not UnitIsDead(unit)` gate (`:1208`) is ported as `Rows:TargetIsDead`, and it answers on the row's **identity PAIR** — the token plus the plain guid that token had at the stamp, which must PLAIN-equal the row's own guid, with the token's PLAIN `UnitIsDead`/`UnitIsDeadOrGhost` saying dead. Two laws stamp a pair (review 4 **E5**): the aura law's `unitToken`/`guid` (the original's col 11, `:1161`, set only by the confirming read), and — for a row nothing has confirmed — the **cast** pair `castToken`/`castGuid`, stamped by `Forte_Timer/Core/Casts.lua`'s Pump at the insert of one of my own casts, which is the shape the common kill arrives in (my banish on my current target, and the target dies inside the window). `guid` is the aura law's ADOPTION key and the cast path does not touch it: stamping it there would make a prediction adoptable by identity and move `row.predicted` with it, so the cast stamp is a separate pair that the liveness gate alone consumes. The gate FAILS OPEN on every gap — no identity stamped, no liveness reader, a token outside `Rows.LIVENESS_TOKENS` (`player`/`target`/`focus`/`mouseover`; a cast-target string and a `partyN`/`raidN` target are out of scope), a sealed identity (`C_Secrets.ShouldUnitIdentityBeSecret`), a secret/absent guid on either side, a guid of a different unit, a raising read — so a CC-dropping kill of a sealed-identity unit still fires. Pinned by `Forte_Timer/tests/test_rows.lua` and `Forte_Timer/tests/test_expiry_identity.lua` |

There is **no `FX_SPLASH`** on this bus (review 4 **E6**): the event, the
Self Messages `SplashKick` row and the fire that fed it are all deleted. The
row was a control with no consumer — the splash's pops come straight from
`Forte_Cooldown/Module.lua`'s pop loop into `disp/splash:OnReady`, and
`UI/Splash.lua` never listened on the bus — so the only thing a tick could
have produced later is a double pop. The splash has its own page and its own
`Enable`.

The fade registry `FX.Timer.FadeWarnings` is populated by **this** add-on
(`Pages/RaidMsg.lua`'s `P.FADE_ROWS`/`P.FADE_SPELL_KEYS` — the original's
`ST:RegisterOnTimerFade` registrations: Fear, Banish, Enslave Demon,
Seduction, Mesmerize (Warlock.lua:246-250), Polymorph (Mage.lua:92), Sap
(Rogue.lua:80) — the shared Seduction rows for Mesmerize included), keyed
by SPELL NAME so no class add-on is required. The threshold is parsed from
the fade **text** by the `ST_GetFadeTime` law (first `[%.%d]+` run, fallback
0.1, re-published when a `*FadeText` key changes; rows keep their
insert-time stamp).

**The keys are the FOREVER names, and that is a live gate, not cosmetics**
(review 4 **E4**). A registry entry only bites when Forte_Timer has a row of
that exact name, and rows come from `FX.Timer.Registry:Build(FX._playerClass)`
over the **generated** data (`addon/Forte_<Class>/Data/<Class>.lua`, with the
`durationMs > 0` gate) — a name the data does not carry has no row, so its
fade threshold is never read and its page section can not fire. Under that
gate, as of this build:

| Row | Key the registry sees | Status |
|---|---|---|
| Fear | `Fear` (Warlock data, 6215) | live |
| Banish | `Banish` (Warlock data) | live |
| Sap | `Sap` (Rogue data) | live |
| Polymorph | `Polymorph` (12826, added to `tools/spell_lists/mage.json` for this) | live |
| Enslave | **`Subjugate Demon`** (11726) — Forever renamed the source's `Enslave Demon` (1098/11725/11726, `ClassFlags.Family` 5); the row keys on the Forever name and the TEXTS stay the original's (`">> Enslave on %s …"`) | live |
| Seduction (+ the `Mesmerize` alias) | `Seduction` | **can not fire on this build: the spell does not exist in the Forever data.** Searched all **7503** rows of `mythicsim-forever-engine/data/spells.jsonl` (client_build `1.60.1.70425`) for the names `Seduction`, `Seduction`, `Mesmerize` (plus the Succubus' other tools `Devour Magic`, `Spell Lock`, `Clamp`, `Grip of the Dead` and the source's `Enslave Demon`): **no row of any of them** — the file's families are `3,4,5,6,7,8,9,10,11,13` plus 3525 uncoded rows, the Warlock family (5) has no Charm-mechanic spell at all, and the source's ids `6358`/`6359` (Seduction), `115268`/`115269` (Mesmerize), `19505` (Devour Magic), `19647` (Spell Lock), `20707`/`21017` (Enslave Demon) are all absent; the file's only Succubus row is the form `Perm. Illusion Succubus` (8315). The client's live table agrees: `C_Spell.GetSpellInfo(6358)`/`(6359)`/`(115268)` answer **nil**, and a scan of ids `1..1500000` finds no name containing `Seduction`, `Seduction` or `Mesmeriz` (the scan is proven live: `Charm` 8 hits, `elguard` 2, `oomguard` 2). With no data row the registry's `durationMs > 0` gate never sees the name, so no Timer row of it can exist, its fade threshold is never read, and the section can not fire. The texts ship so the pair is visible on the page (the census, review 4 **E2**). Behind that gate sits the second one: these are the Succubus **pet's** casts, and Forte_Timer registers its cast spine for `player` only (`Core/Module.lua`) — the day the client's data carries the spell, pet-cast tracking is what lights it |

`Corruption` is deliberately absent (the source registered no fade for it), and
that absence is a test (`test_announce.lua`: a bare expiry of an unregistered
spell fires no `FX_TIMER_FADING` and rings no bell).

Bus semantics (tested in `Forte_Core/tests/test_events.lua`): registration
order dispatch, every listener in its own `pcall` (a raising listener is
reported through `FX.Print` and the **firing code path never breaks**),
`FX.Off` removes exactly the handle it is given, and `FX.Fire` iterates a
snapshot — a `FX.Off` from inside a listener completes the running fire.

## The Timer seam (where FX_TIMER_EXPIRED fires, and who listens)

**Forte_Timer fires the event itself, at the fact.** The fire sits in
`Forte_Timer/Core/Rows.lua`'s Sweep, in the block that promotes a row at its
true expiry (the `:1064-1068` law), behind a `row.expiredFired` once-flag and
a nil-guarded `FX.Fire`, with the payload the row's plain fields
`(name, targetKey, kind)`. This add-on is a **pure subscriber**
(`Module.lua`'s `_SubscribeToBus`, four `FX.On` handles, each Off'd before it
is re-`On`'d so a re-enable can not double a listener).

Review 4 **E3** is why the shape moved. The earlier build had this add-on
replacing `FX.Timer.Module.options.onExpire` with a wrapper at ITS enable
(`WrapTimerExpire`, with a `wrappedFns` weak-keyed idempotency registry and a
`timerHook = "absent"` branch). The real load order never ran it:
`Forte_Messages.toc` lists `Forte_Timer` as an OptionalDep, the modules enable
in registration order, and `Forte_Timer/Module.lua`'s `OnEnable` is where
`self.options` is first built (and every re-enable rebuilds it) — so on the
client the wrapper saw `opts == nil` and gave up, `FX_TIMER_EXPIRED` had zero
producers, and the whole "Timer Expiry" group (the SelfMsg chat/banner rows,
the RaidMsg expire rows, the `TimerExpire` bell) was inert while the suite,
firing the event by hand, stayed green. Firing at the fact makes the enable
order irrelevant; `Forte_Timer/tests/test_expiry_identity.lua` pins the fire
(one per expiry, not the fade, not the break, the Sweep its only producer) and
`Forte_Messages/tests/test_messages.lua` pins the listener side.

The bus event is INDEPENDENT of the Timer's own `AnnounceExpiry` chat gate
(`m7`, the source's expire-message channel, shipped off because the source
ships its announce pages dimmed): that gate stamps the row's chat column at
the insert and prints `Forte: <spell> expired on <target>`, and it is the
Timer's own feature, not this add-on's. The bus rides every true expiry; this
module's `ExpireEnable`/`TimerExpire*`/`ExpireAnnounce*`/`ExpireChannel` rows —
all opt-in, all shipped off — are the gates that decide whether anything is
heard.

The soulstone announce needs no hook at all: there is no `FX_SOULSTONE`
event and Forte_Warlock is a load-on-demand class add-on (an always-loaded
add-on never lists one — the dependency law), so the module watches the
**player's own** `UNIT_SPELLCAST_SENT` / `UNIT_SPELLCAST_SUCCEEDED`
(`Forte_Messages/Module.lua`, one frame created inside `OnEnable`), resolves
the spellID through `C_Spell.GetSpellInfo` in a pcall with `PlainOrNil` on
every field (the `Forte_Cooldown/Module.lua:329-334` cast-event pattern —
the spellID is never compared, only looked up), and family-matches the
**name** against the soulstone family patterns `{ "^Create Soulstone",
"^Soulstone" }`. **The family has one home** (review 4 **m7**):
`FX.SoulstonePatterns`, declared in `Forte_Core/Core/Constants.lua` — the one
add-on both consumers hard-depend on. `Forte_Warlock/Core/Tools.lua` reads it
as `WK.SoulstonePatterns` and this module reads it directly, so the two lists
can not drift; the two WATCHERS stay separate on purpose (Tools tracks the
buff, this announces the cast) and `Forte_Warlock` is still not required (the
dependency law). `Use Soulstone` is not in the family, per
`Forte_Warlock/tests/test_tools.lua`, which is the pattern's law. A mage hears
"Soulstone Resurrection" named the same way, which is exactly what the
name-pattern form is for. The target is the SENT payload's plain target name,
stamped and used as a string only.

## Self Messages — what the original is, and the one new thing

The source search, with its answer: the original has **no raid-warning-style
frame and no custom message window at all**. A Self Message is a coloured
line in the DEFAULT chat frame —

* `FW:Show(msg, r, g, b, a)` = `DEFAULT_CHAT_FRAME:AddMessage(tostring(msg),
  r, g, b, a)` (`/tmp/fxref/Forte_Core/Forte_Core.lua:559`);
* "This allows you to display useful messages to yourself. They are shown in
  your 'default' chat frame." (`/tmp/fxref/Forte_Core/Localization.lua:279`,
  `:2271`);
* the message rows and their colours: `TimeLeft = ">> %s on %s is fading in
  %s <<"`, `TimeLeftNoTarg`, `CooldownLeft = ">> %s is ready in %s <<"`
  (`Forte_Core.lua:2525-2527`), `SoulstoneMsgColor {1,0,1}`
  (`Forte_Soulstone.lua:672`), ReadColor `{1,1,0}` (`Forte_Soulstone.lua:651`).

`DEFAULT_CHAT_FRAME:AddMessage` is live on Forever (the shipped Blizzard UI
calls it on this interface — `Blizzard_ChatBase/FloatingChatFrame.lua:354`,
`ChatFrameUtilOverrides.lua:8`). The call is pcall'd and degrades to
`FX.Print`, so a chat-less boot costs the colour, not the message.

**NEW (labelled in the pages): the on-screen banner** (`UI/Banner.lua`). The
original ships no on-screen self-message; the banner is the configurable
on-screen message (per-event colour + duration, opt-in) the task asks for,
built under the owner ruling "build what we actually need, label what is
new". It obeys the hidden-frame law: it is SHOWN synchronously by the event
itself, and the banner frame owns no OnUpdate at all. Its clock is a
**self-rescheduling `C_Timer.After` chain** (review 4 **m5**), not a session
ticker: `Banner:Show` calls `onActive`, which arms one 50 ms step, and each
step re-arms the next only while `Banner:Update()` reports a live window, so
the chain ENDS the pass the banner lapses and an idle session runs no closure
(`Module:BannerPumpActive()` reports the state, `/fx messages` prints it).
`C_Timer.DeleteTicker` is not in the pinned catalog, so the chain is the
cancellable form — the same idiom `Forte_Cooldown/Module.lua` ships for its
debounces.

**The colour rows are the source's three-slot `{r, g, b}`** (review 4 **m6**).
The source's rows are `{[0]=true, r, g, b}` (`Forte_Soulstone.lua:651`, `:672`)
and its `FW:Show(msg, r, g, b, a)` hands the alpha to `AddMessage`
(`Forte_Core.lua:559`) — but on this interface the Camelot override of that
call is `AddMessage(text, r, g, b, id)` (`Core/Channel.lua:18-23`), whose 5th
slot is a chat-line **id**, not an alpha. So `Core/Channel.lua:Show` passes
three numbers and no alpha is invented for chat; a colour picker that wrote a
4th slot gets it as the TEXT's own alpha in the banner (`UI/Banner.lua`, which
is the half that owns a real alpha — the frame's alpha is the banner's fade
and is never the row's).

**The ready chat line — one voice, opt-in.** Review 4 **E1** (owner ruling
2026-11-02): `Forte_Cooldown`'s ready-pop loop prints **nothing**. The source's
pop loop prints nothing either (zero "ready" prints across
`/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua`), and its `">> %s is ready in
%s <<"` trio is the bar-icon **click** readout family (`FW:ShowTimeFor`,
`Forte_Core.lua:2188`, reached from `CD_ShowTimeFor`, `Forte_Cooldown.lua:911`,
`:1128`, and from the Spell Timer's `ST_ShowTimeFor`, `Forte_Timer.lua:1582`) —
not a pop message. The port's ungated `FX.Print(name .. " ready")` at the pop
was chat spam with no switch: one line per ready cooldown per pull, every
pull, un-offable, and it justified four shipped defaults (the SelfMsg row's
note and tip, the RaidMsg tip, and this file's own note) on a source claim the
source does not support. It is deleted. **The ready chat line is this
add-on's `SelfMsg` `ReadyChat` row** — the templated (`ReadyText`, the
original's `CooldownLeft` shape), coloured (`ReadColor`), original-shaped one
— and it is **opt-in: `ReadyChat` ships OFF**, so the shipped build is silent
at a pop until the owner ticks it. That row is the ONLY chat voice for a pop:
no second line of the same news exists anywhere.

## Sound — the original's law, the one addition

The sound law is `{[0]=on, [1]=path, [2]=times}` played through
`PlaySoundFile` repeated `[2]` times (`Forte_Core.lua:2062-2068`; the `[2]`
slot is a **repeat count**, spec ST-38:3297). `PlaySoundFile(path)` is the
original's call and the call a working Forever addon makes on the live
client (CooldownMaster `UI/ReadyFrames.lua:37`, in a pcall exactly like
ours; it is not in the pinned catalog slice — the live client + working-addon
usage is the source of this API, per the verification law).

* **Timer fade bell** (`TimerFade*`, default ON) — the original's
  `TimerFadeSound` `{[0]=true, "Sound\\Spells\\ShaysBell.wav", 2}`
  (`Forte_Timer.lua:3297`), played at the fade block
  (`Forte_Timer.lua:1049-1056` — `PlaySound("TimerFadeSound")` rides the
  fade row's fire, independent of the message's bits). Reached through
  `FX_TIMER_FADING`. Ported verbatim.
* **Timer break sound** (`TimerBreak*`, default ON) — the original's
  `TimerBreakSound` `{[0]=true,
  "Sound\\Spells\\SimonGame_Visual_LevelStart.wav", 4}`
  (`Forte_Timer.lua:3298`), played where the aura sweep judges the CC broke
  early (the `:1207` site, the original's `ST_BreakMessages` call). Reached
  through `FX_TIMER_BROKEN`. Ported verbatim.
* **True-expiry bell** (`TimerExpire*`, **default OFF**) — NEW: the original
  has no per-expiry sound (its warning is the fade bell); the
  `FX_TIMER_EXPIRED` seam is kept wired and silent by default. The same
  ruling keeps the Self Messages `Expire*` rows and the RaidMsg
  `ExpireAnnounce*` rows as opt-in (the Core-level `TimeLeft` template
  they ride is `Forte_Core.lua:2525-2527`, the original's announce-row
  half — not a per-row expiry behaviour).
* **NO resist row** (review 4 **m4**) — the original's `TimerResistSound`
  (`Forte_Timer.lua:3299`, `Sound\\Spells\\SimonGame_Visual_BadPress.wav`, 1,
  shipped ON there) has **no row on the Sound page and no key in the
  defaults**: the page's row table, its defaults and its tips dropped it. The
  reason is a missing signal, not a missed row: its site is a resisted *aura
  application*, and the nearest Forever event, `UNIT_SPELLCAST_FAILED`, names
  a **cast** failure — conflating them rings a resist bell on every interrupted
  cast (the review law: do not conflate). A checkbox with no consumer is a
  control that changes nothing, which is the ticket's "settings without a
  consumer" hazard, so the decision lives here in the note, with the original's
  path recorded, until a legal resist signal exists. `Core/Sounds.lua`'s row
  table has never had a resist entry, and `/fx messages` reports no such row.
* **Cooldown ready** — **NEW.** Spec CD-33 is the finding: the original's
  Cooldown module has **no ready sound of its own** (verified absence,
  `Forte_Cooldown.lua:400-1000` — the panel's only sound is the options
  click). This add-on ships one as an explicit **opt-in** (default off),
  labelled new on the page. Its default path
  `Sound\\Spells\\SimonGame_Visual_GameStart.wav` is a path the original
  itself ships a default for (`Forte_Timer.lua:3301`) — no invented asset.

There is no `SND` widget in Forte_Options, so the path is a STR row;
`SOUNDKIT_*` constants are absent from the pinned catalog and the cached
Blizzard UI (`SOUNDKIT_OPEN_ALL_SUMMONER_SPELLS` & co. live in the
FrameXML/SoundConstants family — not on the searchable surface here), and
the original's own law is file paths, so **no soundkit ids are used and no
`C_Sound` call is made**. `PlaySoundFile` is the whole surface, exactly the
original's.

## Party/Raid Messages — the legality record

The routing is the original's: bit1 → `FW:ToGroup` (RAID in a raid, PARTY in
a party, a local echo with no group, behind the `OutputRaid` master,
`Forte_Core.lua:2046-2056`, default true `:2518`); bit2 → `FW:ToChannel`
(SAY/YELL/channel, behind the `Output` master, `:2058-2070`, default on
`:2519`). The announce texts are the original's rows verbatim, including
`SoulstoneSuccess = "Soulstoned >> %s << Use it well!"`
(`Forte_Class/Warlock/Warlock.lua:365`).

**Every group and channel send ships OFF** (review 4 **E2**, owner ruling
2026-11-02). That is a deliberate departure from the source's data, and it is
the ONLY half that departs:

* **Verbatim**: every fade/break TEXT (and the threshold the fade text's first
  number carries, `ST_GetFadeTime`), the routing, the master switches, and the
  row's `{[0]=bits}` value — which rides `P.FADE_ROWS` as the row's `bits`
  field (0 silent, 1 group) so the source's value is on the record.
* **Opted-in**: the SEND. Every `*FadeParty`, `*BreakParty`, `*FadeChannel`,
  `*BreakChannel`, `ReadyAnnounce`, `ReadyChannel`, `ExpireAnnounce`,
  `ExpireChannel`, `SoulstoneAnnounce`, `SoulstoneChannel` checkbox defaults
  `false`, so a default install — one that has never run on a real client —
  sends nothing to anyone. The three rows the source ships with party bits 1
  (`Banish`, `Enslave Demon`→`Subjugate Demon`, `Seduction`;
  `Warlock.lua:372-373`, `:382-391`) say so in their own section note: *"the
  source ships this ON — tick to restore"*.

The reason is the one the file's own legality half is about: the group half of
a Banish fade is a 3-second heads-up on a crowd control, and the common real
shape of a CC window is the victim **dying inside it** — a default install
with these rows on talks to a party that never asked, in the content (the
lockdown, `InChatMessagingLockdown`) where a tainted send is silently
swallowed. The verbatim law and the "a NEW feature ships off / a default
install must be legal on a real client" law collide here; the owner ruling is
that the send is the half that moves. `Pages/RaidMsg.lua`'s header and its
section tips carry the same sentence, and
`Forte_Messages/tests/test_announce.lua` pins both halves: the shipped default
is silent on the chat wire while the `FX_TIMER_BROKEN` event and the original's
four break sounds still ring, and the ticked row sends the verbatim line to
`PARTY`.

The legal surface (all of it catalog-pinned or live-client-observed):

* `C_ChatInfo.SendChatMessage(message, chatType, languageID, target)` —
  the pinned catalog `@ChatInfoDocumentation.lua:563`, annotated
  **`HasRestrictions = true`**; `chatType` is the `ChatTypeInfo` string
  (`SAY`/`YELL`/`RAID`/`PARTY`/`CHANNEL1..10`). Every send is pcall'd.
  EllesmereUI's live code calls it exactly so:
  `C_ChatInfo.SendChatMessage(AnnounceLine(marker), "PARTY")`.
* The restriction regime: instances/encounters put addons into a **chat
  messaging lockdown**. Evidence chain —
  `docs/reference/wow-ui-sim-specs/chat-messaging-lockdown.md` (the
  `C_ChatInfo.InChatMessagingLockdown()` predicate; the harness gates
  `SendChatMessage` on it: row 388 "shared producers reject under
  chat-messaging lockdown", rows 568-569 "in-chat messaging is blocked" for
  the `RAID`/`PARTY` verbs);
  `docs/reference/wow-ui-sim-specs/chat-lockdown-ready-checks.md` row 169 —
  the 12.0.x `HasRestrictions` restrictions "apply when in chat messaging
  lockdown"; the live code names the bite: inside a lockdown a tainted send
  is **silently swallowed** (EllesmereUI `EUI_Chat_EditBox.lua:64-68`).
* The gates `Announce:chatLocked()` reads, in order, refreshed at every
  send: `FX.SecretState.chat` (the Forte_Core/Compat.lua snapshot of
  `C_RestrictedActions.IsAddOnRestrictionActive` for
  `AddOnRestrictionType.Chat = 5` — `RESTRICTION_TYPES` at
  `Forte_Core/Core/Compat.lua`, the type pinned at
  `@RestrictedActionsConstantsDocumentation.lua:18`), then
  `C_ChatInfo.InChatMessagingLockdown()`, then
  `C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()` — the exact pair
  NeedRoll (installed, live) gates its outbox on
  (`Core/Drops.lua:616`, `Core/Init.lua:453-455`), and the pair + the
  `IsAddOnRestrictionActive`-derived snapshot EllesmereUI gates on
  (`EllesmereUIQoL_RaidTools.lua:837-840 ChatLocked()`,
  `EllesmereUIQuestTracker_Forever.lua:710`: check first, then send).
  The gate law is the SecretState consumer law
  (`Forte_Core/Core/Compat.lua:394-448`): **only a plain `true` skips** —
  an absent/raising/nil answer is unknown and does not suppress.
* On a lock: the send is **silently skipped and counted**
  (`counts.lockedSkipped`, printed by `/fx messages`). No send is attempted
  blind: the client swallows it, and a module that pretends a swallowed
  line went is lying in its own status.
* No raid-target data is read (the announce targets are the player's own
  cast event's names, the spell names from the player's own engine/events —
  `UnitAurasUnitIsNotUnit`-class surfaces are untouched).

## Files

* `Core/Sounds.lua` — the FE-18 play law; `Sounds.playFn` is the test seam.
  Three rows: the fade bell, the break sound, the opt-in expiry bell, the
  opt-in ready sound. **No resist row** (`m4`, reason in the note above).
* `Core/Channel.lua` — the FW:Show chat line (the source's three-slot colour,
  no invented alpha) + the safe `%s` template formatter (a broken template
  degrades to the raw text, never a loss).
* `Core/Announce.lua` — the gate above; `Announce.readers` is the test seam.
* `UI/Banner.lua` — the NEW on-screen banner: shown synchronously, no
  OnUpdate on the frame, faded by a self-rescheduling `C_Timer.After` chain
  that the first `Show` arms and that stops the pass the banner lapses (`m5`).
* `Pages/SelfMsg.lua`, `Pages/Sound.lua`, `Pages/RaidMsg.lua` — the pages
  on the `SelfMsg` / `Sound` / `RaidMsg` index cells; the pages are the
  defaults home (every group/channel send ships OFF — `E2`) and every tip
  says "Applied live" — the keys ride `FX.Settings:OnChange` (the Forte_Timer
  live law).
* `Module.lua` — the four bus subscriptions (`_SubscribeToBus`:
  `FX_COOLDOWN_READY` / `FX_TIMER_FADING` / `FX_TIMER_BROKEN` /
  `FX_TIMER_EXPIRED`, each Off-before-On so a re-enable cannot double it), the
  soulstone cast watch (reading `FX.SoulstonePatterns`), the banner pump,
  `/fx messages`. There is no Timer wrap any more (`E3`): the
  `FX_TIMER_EXPIRED` fire lives in `Forte_Timer/Core/Rows.lua`'s Sweep.
* The soulstone family's one home is `Forte_Core/Core/Constants.lua`'s
  `FX.SoulstonePatterns` (`m7`); the two watchers — Forte_Warlock's buff scan
  and this module's cast watch — read it, and neither hard-requires the other.
