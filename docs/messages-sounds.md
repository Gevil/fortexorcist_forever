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
| `FX_TIMER_EXPIRED`       | `(spell, target, kind)`     | **This add-on wraps Forte_Timer's own expire seam** — see “The Timer hook” below. Kept as the bus seam; the shipped defaults are silent (the original has no per-expiry message/sound) |
| `FX_TIMER_FADING`        | `(spell, target, kind, secondsLeft)` | **Forte_Timer fires it** — `Core/Rows.lua`'s Sweep fade block, the verbatim port of `ST_UpdateSpellTimers` (`Forte_Timer.lua:1049-1056`): once per row, when `fadeWarn > 0` and remaining crosses it; the stamp (`row.fadeWarn`, the original's column 12) is `FX.Timer.FadeWarnings[spell]` at insert (`ST_GetFadeTime`, `:1590-1603`) |
| `FX_TIMER_BROKEN`        | `(spell, target, kind)`     | **Forte_Timer fires it** — `Core/Rows.lua:OnAuraAbsent`'s removal, the `:1207-1211` law site (aura confirmed gone past the BUFF_DELAY grace with more than MAXLAG of window left — the CC broke early). The original's `if not UnitIsDead(unit)` gate (`:1208`) is ported (2026-11-02) as `Rows:TargetIsDead`: the row's unit token must PLAIN-match the row's stamped `guid` (the original's col 11, `:1161`) and its PLAIN `UnitIsDead`/`UnitIsDeadOrGhost` must say dead, and then the row is retired **without** the fire. The gate FAILS OPEN on every gap — no liveness reader, a token outside `Rows.LIVENESS_TOKENS` (`player`/`target`/`focus`/`mouseover`; a cast-target string and a `partyN`/`raidN` target are out of scope), a sealed identity (`C_Secrets.ShouldUnitIdentityBeSecret`), a secret/absent guid on either side, a raising read — so a CC-dropping kill of a sealed-identity unit still fires. Pinned by `Forte_Timer/tests/test_rows.lua` |
| `FX_SPLASH`              | `(name, texPath)`           | This add-on, when the Self Messages page's `SplashKick` row is on (opt-in, default off) |

The fade registry `FX.Timer.FadeWarnings` is populated by **this** add-on
(`Pages/RaidMsg.lua`'s `P.FADE_ROWS`/`P.FADE_SPELL_KEYS` — the original's
`ST:RegisterOnTimerFade` registrations: Fear/Banish/Enslave Demon/
Seduction/Mesmerize (Warlock.lua:246-250), Polymorph (Mage.lua:92), Sap
(Rogue.lua:80) — the shared Seduction rows for Mesmerize included), keyed
by SPELL NAME so no class add-on is required. The threshold is parsed from
the fade **text** by the `ST_GetFadeTime` law (first `[%.%d]+` run, fallback
0.1, re-published when a `*FadeText` key changes; rows keep their
insert-time stamp).

Bus semantics (tested in `Forte_Core/tests/test_events.lua`): registration
order dispatch, every listener in its own `pcall` (a raising listener is
reported through `FX.Print` and the **firing code path never breaks**),
`FX.Off` removes exactly the handle it is given, and `FX.Fire` iterates a
snapshot — a `FX.Off` from inside a listener completes the running fire.

## The Timer hook (where FX_TIMER_EXPIRED actually fires)

`Forte_Timer` ships no bus fire and the task fences us out of editing it. Its
expire seam is `options.onExpire` — set in `Forte_Timer/Module.lua:540`
(`self.options.onExpire = announceExpiry`) and invoked as `opts.onExpire(row)`
from `Core/Rows.lua`'s sweep. `Forte_Messages/Module.lua`'s
`WrapTimerExpire()` replaces that field at enable time with a closure that
chain-calls the previous handler first (the Timer's own behaviour is
untouched by our presence) and then fires
`FX.Fire("FX_TIMER_EXPIRED", row.name, row.targetKey, row.kind)`. The
registry of wraps is `M.wrappedFns` (a weak-keyed table — a Lua function
carries no fields, so the "is this our wrap?" marker cannot ride the
closure), which makes the wrap idempotent across re-enables. When
`Forte_Timer` is not loaded the wrap is skipped (`timerHook = "absent"`) and
the bus seam stays open for a Timer-side fire later.

The soulstone announce needs no hook at all: there is no `FX_SOULSTONE`
event and Forte_Warlock is a load-on-demand class add-on (an always-loaded
add-on never lists one — the dependency law), so the module watches the
**player's own** `UNIT_SPELLCAST_SENT` / `UNIT_SPELLCAST_SUCCEEDED`
(`Forte_Messages/Module.lua`, one frame created inside `OnEnable`), resolves
the spellID through `C_Spell.GetSpellInfo` in a pcall with `PlainOrNil` on
every field (the `Forte_Cooldown/Module.lua:329-334` cast-event pattern —
the spellID is never compared, only looked up), and family-matches the
**name** against the Warlock tools' shipped patterns
(`^Create Soulstone`, `^Soulstone` — `Forte_Warlock/Core/Tools.lua:142`
copied as law; `Use Soulstone` is not in the family, per that file's own
tests). The target is the SENT payload's plain target name, stamped and
used as a string only.

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
itself, and the clock is the module's `C_Timer` ticker — the banner frame
owns no OnUpdate.

Defaults note: `ReadyChat` ships OFF because Forte_Cooldown's own pop
already prints "<name> ready" (`Forte_Cooldown/Module.lua`'s
`ProcessReadyPops`); the templated chat line here is the richer opt-in
replacement, not a second line of the same news.

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
* **Resist sound** (`TimerResist*`) — the original's `TimerResistSound`
  (`Forte_Timer.lua:3299`, shipped ON there) is kept **OFF and unwired**:
  its site is a resisted *aura application*; the nearest Forever signal,
  `UNIT_SPELLCAST_FAILED`, names a cast failure, not a resist, and
  conflating them fires a resist bell for every failed cast (the review
  law: do not conflate). The row is the visible seam until a legal resist
  signal exists.
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
(SAY/YELL/channel, behind the `Output` master, `:2059-2071`, default on
`:2519`). The announce texts are the original's rows verbatim, including
`SoulstoneSuccess = "Soulstoned >> %s << Use it well!"`
(`Forte_Class/Warlock/Warlock.lua:365`) — its shipped default is bits 0
(OFF), which is why every announce row here is opt-in.

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
* `Core/Channel.lua` — the FW:Show chat line + the safe `%s` template
  formatter (a broken template degrades to the raw text, never a loss).
* `Core/Announce.lua` — the gate above; `Announce.readers` is the test seam.
* `UI/Banner.lua` — the NEW on-screen banner (law notes in its header).
* `Pages/SelfMsg.lua`, `Pages/Sound.lua`, `Pages/RaidMsg.lua` — the pages
  on the `SelfMsg` / `Sound` / `RaidMsg` index cells; the pages are the
  defaults home and every tip says "Applied live" — the keys ride
  `FX.Settings:OnChange` (the Forte_Timer live law).
* `Module.lua` — the subscriptions, the Timer wrap, the soulstone watch,
  `/fx messages`.
