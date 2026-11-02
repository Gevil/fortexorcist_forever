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
| Seduction (+ the `Mesmerize` alias) | `Seduction` | **LIVE through the pet-cast feed** (wave 2b "PetRows v2", 2026-11-02). The pair is the Succubus' own casts (`AddSpell(6358, 30, "Pet")` / `AddSpell(115268, 30, "Pet") -- Mesmerize`, Warlock.lua:73-74), so the window opens on a **pet** cast: `Forte_Timer` now registers its cast spine for the `pet` unit too (`Forte_Timer/Module.lua`'s `f:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "pet")` pair plus the pet half of its `Core/Casts.lua` feed), a pet Seduction inserts the row off the generated Warlock data (`6358`, `durationMs` 15000 — the D3 70707 refresh put the kit in `addon/Forte_Warlock/Data/Warlock.lua`: the client's own spell store names Seduction 6358/6359 and Mesmerize 24594), and the row's FADING/BROKEN ride the SAME shared sites as every other row, so the pair's two announces light when the boxes are ticked. `Forte_Timer/tests/test_pet_rows.lua` pins the whole spine (a pet SUCCEEDED → one 15 s `Crowds` row, the pet's target as the row key, the fade firing ONCE at 3 s of window left, the Mesmerize name row NOT tracked — it carries no `durationMs`, so it has no row of its own and shares the Seduction keys through `P.FADE_SPELL_KEYS`). The Iteration G verdict printed below measured the **70425** data pull plus the simulator, and is SUPERSEDED — kept as the record of what was searched and why the pair looked dead. The texts ship so the pair is visible on the page (the census, review 4 **E2**). The remaining half of the old note stands as history: the 70425 search found no `Seduction`/`Mesmerize` row in `mythicsim-forever-engine/data/spells.jsonl` (all **7503** rows; families `3,4,5,6,7,8,9,10,11,13` plus 3525 uncoded; ids `6358`/`6359`, `115268`/`115269`, `19505`, `19647`, `20707`/`21017` all absent; the file's only Succubus row the form `Perm. Illusion Succubus` 8315), and `C_Spell.GetSpellInfo(6358)`/`(6359)`/`(115268)` answered nil on that build |

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

## The 20 cast announce rows (wave 2b T2)

The third family of opt-in sends on `Pages/RaidMsg.lua`: the source's
`CA:RegisterOnSelfCastSuccess` + `CA:CastShow` **raid warnings of the
player's own casts** — the 20 rows of `Forte_Class/Druid/Druid.lua:190-227`,
`Forte_Class/Paladin/Paladin.lua:125-168` and
`Forte_Class/Warrior/Warrior.lua:79-104` (`docs/class-port.md` S17). They ride
`P.CAST_ROWS`, the `P.FADE_ROWS` shape, and the **same** cast frame and
legality gate as the soulstone row above: `Module.lua`'s
`M:OnCastForAnnounce` on the player's own `UNIT_SPELLCAST_SENT` /
`UNIT_SPELLCAST_SUCCEEDED` pair (SENT carries `(unit, targetName, castGUID,
spellID)` and stamps the target; SUCCEEDED carries `(unit, castGUID,
spellID)` and is where the announce goes — the payload order is the catalog's,
the Hunter swing bug's class of error), the spellID resolved to a **name** by
`spellNameFor` (a `C_Spell` read, pcall'd, `PlainOrNil` on every field, never
compared), the name canonicalized through `FX.Locale.CanonicalName` so a
German `Schildwall` meets the Shield Wall row, then sent through
`Announce:Group` / `Announce:Channel` on the row's own
`<Prefix>CastParty` / `<Prefix>CastChannel` gate keys. `counts.cast` counts
the fires for `/fx messages`; `M:CastRowArmed` is the cheap pre-gate (40
reads of the live config per cast event, before any spell resolve).

**All 20 rows ship OFF** — every one of the 40 boxes (20 group + 20 channel)
defaults `false`, so a fresh install is mute in the raid (review 4 **E2**,
the owner ruling of 2026-11-02; the page's own tip says it: *"the 40
cast-announce boxes"*). **All 20 texts are the source's verbatim**, in the
`<Prefix>CastText` string keys (row defaults from `row.text`, so the recycle
icon restores the original's line). The source's own party bits ride each
row's `bits` field (19 rows party-ON, `Warrior Vigilance` the one row the
source ships silent at `Warrior.lua:104`) and each row's section tip names
them — *"the source ships this ON — tick to restore"*.

| # | Prefix (the key root) | Class | Key the hook matches (the Forever name) | Source | Group | Text (verbatim) | Targ. | bits |
|---|---|---|---|---|---|---|---|---|
| 1 | `Barkskin` | Druid | `Barkskin` | Druid.lua:213 | Self Damage Reduction | `+++ Barkskin (10 sec) +++` | | 1 |
| 2 | `SurvivalInstincts` | Druid | `Survival Instincts` | Druid.lua:216 | Self Damage Reduction | `+++ Survival Instincts (12 sec) +++` | | 1 |
| 3 | `FrenziedRegeneration` | Druid | `Frenzied Regeneration` | Druid.lua:219 | Self Damage Reduction | `+++ Frenzied Regeneration (20 sec) +++` | | 1 |
| 4 | `Rebirth` | Druid | `Rebirth` | Druid.lua:223 | Other | `>>> Rebirth on %s <<<` | ✔ | 1 |
| 5 | `Innervate` | Druid | `Innervate` | Druid.lua:226 | Other | `>>> Innervate on %s <<<` | ✔ | 1 |
| 6 | `Tranquility` | Druid | `Tranquility` | Druid.lua:229 | Other | `>>> Tranquility up <<<` | | 1 |
| 7 | `AuraMastery` | Paladin | `Aura Mastery` (the 2012 id 31821 has no row; the **name** does — 409932 in the 70707 store's Names) | Paladin.lua:151 | Raid Damage Reduction | `+++ Aura Mastery (6sec) +++` | | 1 |
| 8 | `Salvation` | Paladin | `Salvation` — **INERT ON THIS BUILD**: 1038 is a 70425 row, REMOVED on 70707 (the generated Paladin data's header records the drop), so no cast of the name can reach the hook | Paladin.lua:154 | Hands | `+++ Salvation on %s (10sec) +++` | ✔ | 1 |
| 9 | `Sacrifice` | Paladin | `Hand of Sacrifice` (462853), with the 2012 id 6940's Forever name `Blessing of Sacrifice` (20729) aliasing onto the same row in `P.CAST_SPELL_KEYS` | Paladin.lua:156 | Hands | `+++ Sacrifice on %s (12sec) +++` | ✔ | 1 |
| 10 | `Freedom` | Paladin | `Blessing of Freedom` (1044) — the 2012 Hand of Freedom | Paladin.lua:158 | Hands | `+++ Freedom on %s (6sec) +++` | ✔ | 1 |
| 11 | `HandOfProtection` | Paladin | `Blessing of Protection` (10278) — the 2012 Hand of Protection | Paladin.lua:160 | Hands | `+++ Hand of Protection on %s (12sec) +++` | ✔ | 1 |
| 12 | `DivineProtection` | Paladin | `Divine Protection` | Paladin.lua:162 | Self Damage Reduction | `+++ Divine Protection (10sec) +++` | | 1 |
| 13 | `GuardianOfAncientKings` | Paladin | `Avenging Wrath` (407788/409934) — the Paladin's own DR of the 2012 Guardian of Ancient Kings family (86659/86669, no row on either build); the **spec-gated** row, see the note below | Paladin.lua:164 | Self Damage Reduction | `+++ Guardian of Ancient Kings (12sec) +++` | | 1 |
| 14 | `ArdentDefender` | Paladin | `Ardent Defender` — **INERT ON THIS BUILD**: the 2012 31850 has no row in the 70425 pull and no name in the 70707 store's Names table | Paladin.lua:166 | Self Damage Reduction | `+++ Ardent Defender (10sec) +++` | | 1 |
| 15 | `ShieldWall` | Warrior | `Shield Wall` | Warrior.lua:100 | Self Damage Reduction | `+++ Shield Wall (12 sec) +++` | | 1 |
| 16 | `LastStand` | Warrior | `Last Stand` | Warrior.lua:101 | Self Damage Reduction | `+++ Last Stand (20 sec) +++` | | 1 |
| 17 | `RallyingCry` | Warrior | `Rallying Cry` | Warrior.lua:98 | Raid Damage Reduction | `+++ Rallying Cry (10 sec) +++` | | 1 |
| 18 | `EnragedRegeneration` | Warrior | `Enraged Regeneration` (the 2012 55694's Forever row is 402913 of the same name) | Warrior.lua:102 | Self Damage Reduction | `+++ Enraged Regeneration (10 sec) +++` | | 1 |
| 19 | `Intervene` | Warrior | `Intervene` | Warrior.lua:99 | Raid Damage Reduction | `+++ Intervene on %s (10 sec) +++` | ✔ | 1 |
| 20 | `Vigilance` | Warrior | `Vigilance` | Warrior.lua:104 | Other | `>>> Vigilance on %s (12 sec) <<<` | ✔ | **0** |

Targ. = the row's text carries `%s` and the hook hands it the target stamped
from the SENT payload's plain target name (`"?"` when no stamp is in hand,
the soulstone law); the rows without a tick never see a target word. The
**Source** column is each row's own recorded `src` citation, a line of the
`FW:AddOption` / `FW.Default.<Key>Start = {[0]=bits,"<text>"}` pair in
`/tmp/fxref/Forte_Class/<Class>/<Class>.lua` — the `{[0]=bits}` literal is
the **bits** column and the string is the **Text** column. The 20 texts and
the 20 bits values were re-checked against those files on 2026-11-03 and all
20 match verbatim (the Druid six and `Warrior`'s set are defined in the
`FW.Default` block a little above the cited lines — the citations are the
rows', warts and all).
`P.CAST_ROW_CLASS` is the split of the census — **6 Druid, 8 Paladin, 6
Warrior** — and `Forte_Messages/tests/test_cast_announce.lua` fails the suite
if the table drifts (a row dropped, a class left short, a text not the
source's, a box not OFF, an `.text` carrying a `%s` on a non-target row, a
Druid name wearing a form suffix).

**The Paladin spec note (row 13, the one gated row).** The source gated
Guardian of Ancient Kings on the specialization
(`Paladin.lua:139`, `GetSpecialization(...) == 2`). The 2012 globals
`GetSpecialization` / `GetActiveSpecGroup` are absent from the pinned
catalog, so the gate is re-expressed on its pinned pair,
`C_SpecializationInfo.GetSpecialization` +
`C_SpecializationInfo.GetActiveSpecGroup`
(`@SpecializationInfoDocumentation.lua:236` / `:40`), and it rides the row's
`spec = 2` field as the **recorded** gate. **No gate is enforced on this
build**, for one named reason: the row's Forever key spell — `Avenging Wrath`
— is itself spec-specific (the Retribution paladin's own DR), so a cast of
that name already *means* the specialization and a gate would filter nothing.
It is an OPEN item for a build whose name is shared: the day a name of the
family is castable out of the spec, the `spec` field is the gate to enforce,
and the field plus the pinned pair are why no research is needed to do it.

The announce itself is **name-keyed and class-blind** (the soulstone family
pattern's law): a Warrior who somehow casts a `Blessing of Freedom` meets the
Paladin row. The key table is `P.CAST_SPELL_KEYS` (the Forever name → the
prefix, built off `P.CAST_ROWS` plus the one alias), and the two rows whose
key the client's spell set does not carry — `Salvation` and `Ardent Defender`
— are **inert by that gate**, each naming its own reason in its own note (the
review 4 **E4** gate in its cast form). Q5 (the owner ruling of 2026-11-02):
the six Druid rows carry **plain spell names** — the source's
`FWL._FERAL/_BEAR/_CAT` suffixes (`Druid/Localization.lua:73-88`) label the
form-paired BAR rows (the S16 `SetCustomName` seam), are not announce labels,
and none of the six is form-paired.

`Forte_Messages/tests/test_cast_announce.lua` drives all of this through the
real cast frame's `OnEvent` with client payloads (the test law), over the
injected `Announce.readers` seam (its `send` collecting the chat wire, its
lockdown readers flipping on demand) and a stubbed `C_Spell.GetSpellInfo`
supplying the cast names: the 20-row table
SHAPE (the 6 Druid / 8 Paladin / 6 Warrior census, unique prefixes), the
verbatim texts of all 20, the OFF shipped defaults (20 casts, nothing on the
chat wire), the one send per SUCCEEDED with the SENT stamp in the line, the
channel half behind `OutputChannel`, a cast of no row (Fireball) and a
foreign unit's cast both silent, the source's `bits` recorded with the ONE
bits-0 row named, the two rows that can not fire on this build naming their
reason, the Q5 plain Druid names, the soulstone watch untouched by the general
hook, and the page's 20 sections × 3 controls. The localized-name half of the
hook is pinned in `test_locale_messages.lua` (a German `Schildwall` cast
meeting the Shield Wall row, and the German name of `Blessing of Freedom`
reaching the FOREVER key).

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
  soulstone cast watch (reading `FX.SoulstonePatterns`), the **own-cast
  announce hook** over the same frame (`M:OnCastForAnnounce` + the
  `M:CastRowArmed` pre-gate + `counts.cast`, the 20 rows above), the banner
  pump, `/fx messages`. There is no Timer wrap any more (`E3`): the
  `FX_TIMER_EXPIRED` fire lives in `Forte_Timer/Core/Rows.lua`'s Sweep.
* The soulstone family's one home is `Forte_Core/Core/Constants.lua`'s
  `FX.SoulstonePatterns` (`m7`); the two watchers — Forte_Warlock's buff scan
  and this module's cast watch — read it, and neither hard-requires the other.
