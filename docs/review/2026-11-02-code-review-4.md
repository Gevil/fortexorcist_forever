# Code Review 4 — 2026-11-02 (CodeReview4, read-only)

Scope: Iteration E (`a156812`, 33 files, +3523/−41) — `Forte_Cooldown/UI/Splash.lua`,
the Iteration-E parts of `Forte_Cooldown/UI/Timeline.lua` (`Warn`, `CastFailed`,
right-click, `Vertical`/`Flip`/`HideZero`), `Forte_Cooldown/Module.lua`
(`ProcessReadyPops`), `Forte_Core/Core/Events.lua`, all of `Forte_Messages/`,
and the fade/break additions in `Forte_Timer/Core/Rows.lua`.
Source law: `/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua` (md5
`bb8e7243b4ef649ca914a6c9b6e78037`, byte-identical to the authoritative zip),
`/tmp/fxref/Forte_Timer/Forte_Timer.lua`, `/tmp/fxref/Forte_Core/Forte_Core.lua`,
`/tmp/fxref/Forte_Class/{Warlock,Mage,Rogue}/*.lua`. Review 3's items (C1–C5,
m1–m9) are NOT re-raised.

Tree basis: the review ran against the **working tree at HEAD `851817f`**, which
carries a concurrent cleanup agent's uncommitted edits (`Rows.lua`,
`UI/Timeline.lua`, `Reconcile.lua`, the `messages-sounds.md` move), so every
cite below is a working-tree line verified against the file as it sits on
disk today, not against the commit; where the tree has moved past the commit
the finding says so (E5). `python3 scripts/gate.py --fast` was not run here —
out of scope for a read-only review; the manager runs it.

Every cited line below was re-opened today. Every cross-file key name was
compared on **raw bytes**, not on rendered text: the tool render of this repo's
Lua intermittently splits words inside string/identifier tokens (`ReadyColor`
renders as `Read yColor`, `default` as `def ault`), so an identically-rendered
key set across two files proves nothing and a mismatched one proves nothing.
Each key-name claim in this report is a byte comparison.

## Counts

- **Major: 6** (E1–E6)
- **Minor: 8** (m1–m8)
- **Blockers: 0.** No crash, no law break in the six project laws (names-not-IDs,
  the secret-value law, `OnEvent` shape, no hidden-frame `OnUpdate`, no
  `|`-alternation in Lua patterns, toc twins), no gate failure.
- Law scan clean (details in "Verified clean"): no top-level `CreateFrame` /
  `RegisterEvent` in the new files, no vararg-less `OnEvent`, all 380 tests
  public-path, `Forte_Messages` is LoadOnDemand-clean (deps `Forte_Core` only).
- Verbatim fidelity: all 6 checked CC fade/break texts + all 6 `{[0]=bits}`
  party bits, all 4 sound rows, `OutputRaid`/`Output` — byte-identical to the
  source defaults. 4 of the 6 CC groups, however, **cannot fire** on the shipped
  data (E4).

---

## Major

### E1 — Every ready pop prints a chat line, ungated, and the pages justify the *real* ready message off a source claim the source does not support

`addon/Forte_Cooldown/Module.lua:385` — inside the pop loop of
`ProcessReadyPops`:

```lua
for _, name in ipairs(Engine:Sweep(now, readyScratch)) do
    FX.Print(name .. " ready")
```

`FX.Print` is a chat-frame write (`Forte_Core/Core/Constants.lua:28-32` →
`DEFAULT_CHAT_FRAME:AddMessage`). Nothing on this path is gated: the pop loop's
only other feeds are `disp:OnReady` (`:389-391`), the splash (`:403-405`) and
`FX.Fire(FX_COOLDOWN_READY, ...)` (`:410`).

The source prints **nothing** at a ready pop. Scanned every
`Show(`/`ShowText`/`AddMessage` line in `/tmp/fxref/Forte_Cooldown/Forte_Cooldown.lua`
carrying "ready": zero. The original's `">> %s is ready in %s <<"`
(`Forte_Core.lua:2527`, `CooldownLeft`) is not a pop message at all: its only
send path is `FW:ShowTimeFor` (`Forte_Core.lua:2188`, the `CooldownLeft` branch
at `:2198-2202`), reached from `CD_ShowTimeFor`
(`Forte_Cooldown.lua:911-912`) wired to the bar icon's **left-click**
("show duration", `Forte_Cooldown.lua:1128`), and from the Spell Timer's
`ST_ShowTimeFor` (`Forte_Timer.lua:1582-1587`, called at `:1742`). It is the
click-to-readout family, whose shipped bits are `{[0]=1}` — a *group* announce.
The original's only "X ready" chat messages are the Warlock pet-cooldown
messages (`Forte_Class/Warlock/Warlock.lua:269,271`, via `CA:CastShow`).

The docs assert the opposite, and four shipped defaults rest on it:
`Forte_Messages/Pages/SelfMsg.lua:34-38` ("`ReadyChat` off: Forte_Cooldown
prints its own plain '<spell> ready' line to chat, the original's line, and
two lines per pop is noise"), the tip at `SelfMsg.lua:76-80`,
`Forte_Messages/Pages/RaidMsg.lua:75-79`, and
`docs/messages-sounds.md:95-99` (the file moved out of the addon in the tree). So the shipped chat voice is
the untemplated, uncoloured, **un-offable** one, and the rich row
(`Read yText`/`Read yColor`/`ReadyBanner`, opt-in) is shipped off with a
false warranty.

Real-client effect: one chat line per ready cooldown per pop, every pull,
with no way to silence it — chat spam on defaults (the ticket's hazard list),
and a documented premise the next change will inherit.

Fix (one of, plus the docs):
1. delete `Module.lua:385` and let `SelfMsg`'s `ReadyChat` be the single ready
   chat line (it is the original-shaped, templated, coloured one — flip that
   row's default to `true` if the owner wants a default voice); or
2. gate it behind a new opt-in key (`Cooldown.PrintReady`, default `false`) on
   the Cooldown page.

Cite in the fix: the trio's true site (`Forte_Core.lua:2188` +
`Forte_Cooldown.lua:911,1128`) so the readout family is not mistaken for the
pop family again.

### E2 — Six party/raid announce groups ship ON, against the page's own opt-in law

`Forte_Messages/Pages/RaidMsg.lua:41-52` — `P.FADE_ROWS` carry `party = true`
on the Banish, Enslave Demon and Seduction rows (`:45`, `:48`, `:51`; the
six-spell name map is `:61-65`); the expansion at `:93-101` fans that one flag into *two* announce defaults:

```lua
P.DEFAULTS[M][row.prefix .. "FadeParty"]   = row.party    -- true for 6 rows
P.DEFAULTS[M][row.prefix .. "BreakParty"]  = row.party
P.DEFAULTS[M][row.prefix .. "FadeChannel"] = false
P.DEFAULTS[M][row.prefix .. "BreakChannel"] = false
```

under the master `OutputRaid = true` (`:68`, verbatim from
`Forte_Core.lua:2518`). The module's own header (`RaidMsg.lua:16-18`) claims
"Every announce row is opt-in … the shipped-default-OFF pattern is the
original's own (SoulstoneSuccess bits 0, `Warlock.lua:365`)". True for the
three new announce rows (`ReadyAnnounce`/`ExpireAnnounce`/`SoulstoneAnnounce`),
false for these twelve: faithful to `Forte_Class/Warlock/Warlock.lua:382-391`
+ `:372-373` (bits 1), which the file says at `:30-36` — and that is the
conflict: the verbatim law and the "a NEW feature on by default" /
real-client-legality law.

A default install — one that has never run on a real client — sends
`C_ChatInfo.SendChatMessage(text, "RAID"|"PARTY")`
(`Forte_Messages/Core/Announce.lua:128-149`) on a Banish fade (3 s before the
sheep drops) and on a Banish/Enslave break, with no user action beyond
installing. The legality gate (`Announce.lua:79-95`) skips only inside a
lockdown, so this is the normal-combat path.

Fix: keep the texts and the structure verbatim, ship the group half off:
default the three `party = true` entries to `false` (`:45`, `:48`, `:51`) and record the original's
bits-1 in the section tip ("the source ships these party-ON: tick to restore").
The row-level "the bits ride the row verbatim" comment (`:20-22`) should then
say what is verbatim (the text) and what is opted-in (the send).

### E3 — `FX_TIMER_EXPIRED` cannot fire in a real session; the "Timer Expiry" group is dead code on the client

`Forte_Messages/Module.lua:191` records the outcome the load order forces.
The expire seam is installed by `M:WrapTimerExpire()` (`:187-211`), which
replaces `FX.Timer.Module.options.onExpire` with a chain-calling wrapper.
On the real client it sees `opts == nil` and gives up:

- `Forte_Messages/Forte_Messages.toc:7` — `OptionalDeps: Forte_Options,
  Forte_Cooldown, Forte_Timer`;
- `Forte_Core/Core/Init.lua:21-22` — modules are enabled **in registration
  order**, i.e. the addon load order;
- `Forte_Timer/Module.lua:515-516` — `function M:OnEnable()` **rebuilds**
  `self.options = defaultOptions()` and at `:540` installs
  `self.options.onExpire = announceExpiry`.

`Forte_Timer` is an OptionalDep of `Forte_Messages`, so the Loader loads the
Timer first, but the *enable* pass runs in registration order and the Timer's
`OnEnable` is where `options` first exists. Two orders, one outcome: (a) the
Messages enable runs first → `WrapTimerExpire` takes the `absent` branch
(`:191`) and nothing ever calls it again → `FX_TIMER_EXPIRED` has zero
producers → the SelfMsg "Timer Expiry" chat/banner rows
(`Pages/SelfMsg.lua:52-64`), the RaidMsg expire group (`:80-85`) and
`Sounds:TimerExpire` (the row at `Core/Sounds.lua:52-56`) is inert; (b) a later
`Forte_Timer` re-enable replaces `self.options` (`:516`) and the installed
wrapper is dropped with no signal. The headless gate cannot see this: the
tests fire the event directly (`Forte_Messages/tests/test_messages.lua`).

Fix (smallest lawful, inside `Forte_Timer/Module.lua` — both addons are
always-loaded, and the seam is the Timer's):

```lua
self.options.onExpire = announceExpiry            -- :540 as today
local MSG = FX.Messages and FX.Messages.Module
if MSG and MSG.WrapTimerExpire and MSG.enabled then MSG:WrapTimerExpire() end
```

run after the `onExpire` install in `OnEnable` (the module list is populated
by file load, so the reference is safe; `MSG.enabled` guards the not-yet-enabled
case). Keep `WrapTimerExpire`'s `wrappedFns` idempotency guard
(`Module.lua:185`, the guard at `:194-197`) — it makes the re-wrap free.

### E4 — Four of the six CC fade/break groups can never fire: the spells are not in the tracked set

`Forte_Messages/Pages/RaidMsg.lua:61-65` registers six spells
(Fear, Banish, `Enslave Demon`, Seduction, Polymorph, Sap) plus the
`Mesmerize` alias at `:66-69`, and the header claims "the original's
registrations verbatim … all six … verbatim" (`:30-36`). Only three exist on
this build: the tracked set is `FX.Timer.Registry:Build(FX._playerClass)`
(`Forte_Timer/Module.lua:536`) over `FX.Data[Class]` with a `durationMs > 0`
gate (`Registry.lua:330-341`), and the generated data is
`Forte_Warlock/Data/Warlock.lua` (76 names — has `Fear`, `Banish`; no
`Enslave Demon`, no `Seduction`), `Forte_Rogue/Data/Rogue.lua` (50 — has
`Sap`), `Forte_Mage/Data/Mage.lua` (51 — **no** `Polymorph`);
the `Mesmerize` alias names a pet ability (`Forte_Class/Warlock/Warlock.lua:74`, `AddSpell(115268, 30,"Pet") -- Mesmerize`).

Consequence: `FX.Timer.FadeWarnings` entries for the four (`Module.lua:264-290` (`RefreshFadeWarnings` at `:264`)) are never read — `Rows:FadeWarnFor`
(`Forte_Timer/Core/Rows.lua:112-118`) stamps a `fadeWarn` only for rows that
exist (`Rows:InsertFromCast` / `InsertFromAura`), and no row exists for an
untracked spell. 8 of the 12 fade/break rows are inert, and the two
FadeWarnings rows the owner can see are for spells the client does not name.

Fix: add `Polymorph` to `tools/spell_lists/mage.json` and
`Enslave Demon`, `Seduction` (drop the `Mesmerize` alias) to
`warlock.json`, regenerate (`python3 tools/gen_spell_data.py mage warlock`);
until then, state it in the section tip (`RaidMsg.lua:229-240`) next to the
threshold law, so the owner is not hunting a bell that has no row.

### E5 — The break site lost the source's liveness gate: a kill announces "Broke Early!" and plays the break sound

Source: `Forte_Timer.lua:1207-1211`

```lua
elseif st[i][1] ~= -1 and st[i][1] < (GetTime()-st[i][16]) then
    if not UnitIsDead(unit) then ST_BreakMessages(st[i][2],st[i][1]-GetTime(),st[i]) end
    ST:Fade(i,REMOVE);
```

Port: `Forte_Timer/Core/Rows.lua:479-499` — the same early-end branch fires
`FX.EVENTS.TIMER_BROKEN` with **no liveness test**, and the delta is
self-documented in the commit at `a156812`'s `:384-392` ("the original's
`if not UnitIsDead(unit)` gate is **not ported** … a kill that dropped the aura
fires BROKEN, exactly the behaviour this file had before"); the working tree
documents the same asymmetry at `:488-496` — see the note at the end of this
finding. Downstream defaults
make that loud: `FX_TIMER_BROKEN` → `Forte_Messages/Module.lua:304-316` plays
`TimerBreak` (default ON, 4 repeats, `Pages/Sound.lua:37-40`) and calls
`Announce:Group` (`:313-315`), whose gate for Banish/Enslave/Seduction is ON by
default (E2). The common real-client shape of a banish/enSlave window is the
victim **dying inside it** — so the default install reports a false "Broke
Early!" (a raid line + 4 sounds) on kills, and reports the *true* breaks
(immunity, a cleanse) identically.

In the commit there is no liveness read at the site at all. `InsertFromAura`
rows carry a unit token (`row.unitToken`), and the file already has the
liveness idiom to copy (`Reconcile:Alive`, `Forte_Timer/Core/Reconcile.lua` —
the `type(UnitIsDead) == "function"` + pcall shape). Fix as of the commit:

```lua
local function aliveEnough(row)
    if type(UnitIsDead) ~= "function" then return true end
    if type(row.unitToken) ~= "string" then return true end   -- unknown = keep
    local ok, dead = pcall(UnitIsDead, row.unitToken)
    return (not ok) or not dead
end
```

and gate the BROKEN fire on it (`FX_TIMER_FADING` needs no gate: the source's
fade bell at `Forte_Timer.lua:1049-1056` is liveness-blind by design — verified).

*Working-tree note (the concurrent cleanup pass):* a liveness gate now exists —
`Rows:TargetIsDead` (`Rows.lua:458-477`), wired at the fire site
(`:497 if not self:TargetIsDead(row) and FX.Fire then`). It is a
**token-gated** probe: it reads `row.unitToken` and refuses to answer for any
token outside `Rows.LIVENESS_TOKENS` (`:82` — `player`, `target`, `focus`, …).
A banish/enslave victim is a **mob** with a name key (`Mob-1-3`), and
cast-created rows (v1's population: my own cast) carry **no** `unitToken` at
all, so the gate returns "not dead" and the fire proceeds. Its fail-open is
documented as deliberate at `:450-457`, `:490-496`. The finding therefore
stands with the remedy narrowed: bind the name-keyed identity that
`Reconcile:Scan` already resolves (`name-npc-N` → guid, the
`Reconcile:Alive` map) into `TargetIsDead`'s reach for name-keyed rows.

### E6 — `SplashKick` fires an event with no listener: a page row that changes nothing

`Forte_Messages/Module.lua:164-166`:

```lua
if cfg.SplashKick and FX.Fire then
    FX.Fire(FX.EVENTS.SPLASH, plain, FX.Compat.PlainOrNil(texPath))
end
```

Census over `addon/**` (raw bytes): `FX.EVENTS.SPLASH` / `FX_SPLASH` appears
in `Forte_Core/Core/Events.lua:35-37` (declared, "optional: the SelfMsg page's
`SplashKick` row fires this"), the fire above, and **one test listener**
(`Forte_Messages/tests/test_messages.lua:131`). No production `FX.On`. The
splash's pops come from the Cooldown module directly
(`Forte_Cooldown/Module.lua:403-405`, `disp/splash:OnReady`), and
`Forte_Cooldown/UI/Splash.lua` never touches the bus. So the row
`Pages/SelfMsg.lua:68` (the key) + `:173-177` (the control) ("The ready-icon request to the Secondary Splash
(FX_SPLASH)… the opt-in bus kick") is a control with no consumer
("settings without a consumer", the ticket's hazard list). If a listener is
added later, every pop double-pops (the direct call is already there).

Fix, pick one: (a) delete `SplashKick` (the key, the fire, the page row) — the
splash has its own page and its own `Enable`; (b) move the pop onto the bus:
`UI/Splash.lua` subscribes to `FX_EVENT.SPLASH` in its `Init`, and
`Module.lua:403-405` drops the direct call. (b) makes the bus load-order-free
for the pair; (a) is smaller.

---

## Minor

**m1 — 11 citation line numbers in the new code sit 1–11 lines off the pinned
source.** Every one below was located by its own content in the pinned file.

| claim site | cites | true |
|---|---|---|
| `Forte_Cooldown/UI/Timeline.lua:165,1757,1864,1873,1875` (the t20 decay) | `:540-542` | `:528-530` (`:529` is the decay) |
| `Forte_Cooldown/UI/Timeline.lua:168,700,798,1216,1308,1862,1878,1893` (the attention spark block) | `:1412-1416`, size `:1412`, `Hide` `:1415` | `:1408-1415`; size `:1409` (`local size = 2.2*ih*(t20);`), `Hide` `:1413` |
| `Forte_Cooldown/UI/Timeline.lua:438` (the horizontal fill `TexCoord`) | `:1481` | `:1483` (the vertical cite `:1479` is exact) |
| `Forte_Cooldown/UI/Timeline.lua:350,1663` (the icon `SetPoint … "LEFT", t10`) | `:1450` | `:1449` |
| `Forte_Cooldown/UI/Timeline.lua:157,211,910` (the `Hide` default) | `:1815` | `:1813` (`Hide = false,`) |
| `Forte_Cooldown/UI/Timeline.lua:196,1227` (the `IconFont`) | `:1806` | `:1810` |
| `Forte_Cooldown/UI/Timeline.lua:1374` (the `Spark` default) | `:1822` | `:1820` |
| `Forte_Cooldown/UI/Splash.lua:15` (the icon pool centre) | `:968` | `:967` |
| `Forte_Cooldown/UI/Splash.lua:33,81,271` (NewIcon's standing texture) | `:965` | `:970` |
| `Forte_Cooldown/UI/Splash.lua:31,79,277` (the spark's `ADD` blend) | `:973` | `:975` |
| `Forte_Messages/Pages/Sound.lua:5` (`FW:PlaySound`) | `Forte_Core.lua:2062-2068` | `:2072-2077` (`:24`'s "the `PlaySoundFile` call `:2067`" → `:2076`) |

The `Forte_Timer.lua`, `Forte_Class/*`, `Forte_Soulstone.lua`,
`Forte_Core.lua` defaults and the `Forte_Options`/`api-coverage` cites are all
exact (checked: `Forte_Timer.lua:1049,1054,1055,1207,1213,1590,1726,3297,3298,
3299,3301`; `Warlock.lua:121,254,263,269,271,287,365,372,373,382-391`;
`Mage.lua:121`; `Rogue.lua:101`; `Forte_Soulstone.lua:369,405,651,672`;
`Forte_Core.lua:559,2046,2058,2518,2519,2525-2527`). `Forte_Core/Core/Events.
lua:44` cites `Forte_Core.lua:278-306` for "the one-dispatcher rule"; the
dispatcher is `FC_OnEvent` at `:306-322` (`:278-306` is `UnregisterToEvent` +
`RegisterUpdatedEvent` + `DelayedExec`), and note the source's dispatcher is
**raw** (`v(event,...)` at `:319`, no pcall) — the bus's per-listener isolation
is this port's own improvement, so cite it as such.

**m2 — `self:RegisterPages()` is called twice in one `OnEnable`**
(`Forte_Messages/Module.lua:399` — the law's site, before the stored-settings
apply — and again at `:464`, immediately before `return true`). The page
registration is guarded (`Pages/RaidMsg.lua:141`,
`Pages/SelfMsg.lua:110`, and the selftest at `tests/test_messages.lua:84`), so
the second call is dead work that also re-walks `FX.Options.pages`. Delete
`:464`.

**m3 — The ready-pop snapshot walks every live entry on every 10 Hz tick**
(`Forte_Cooldown/Module.lua:374-381`): three field writes per live entry into
`popInfoScratch`, per tick, to cover the rare pop. The project law is "NEVER
avoidable computation". `Engine:Sweep` already touches each popping entry
before deleting it — have it fill a parallel `popInfoScratch[name]` there (or
return `entry` refs in `into`) and drop the pre-pass. (The module's own
no-per-tick-allocation comment is at `:25-29`.)

**m4 — The `TimerResist*` rows are settings with no consumer.**
`Pages/Sound.lua:56-58` (defaults) + the section at `:162-177`; no reference in
`Core/Sounds.lua`'s row table (`:38-57`) and none in `Module.lua`. The tip at
`:84-90` labels it "the reserved unwired seam", and the default is
deliberately flipped off against the source's `{[0]=true,…,1}`
(`Forte_Timer.lua:3299`). A reserved seam belongs in
`docs/messages-sounds.md:129-133` (it is already there), not in the shipped
option tree: delete the three rows and the defaults, keep the docs paragraph.

**m5 — The banner pump is a permanent 20 Hz `C_Timer` for the session life**
(`Forte_Messages/Module.lua:444-449` creates it; `UI/Banner.lua:103-118` is the
pump, whose first line is the cheap `if not self.active then return false end`
at `:104`). The hidden-frame law is respected (no hidden-frame `OnUpdate`) and
the test drives the public pump path (`Forte_Messages/tests/test_messages.lua:160-163`).
The cost is one no-op closure per 50 ms for the session; if a profile shows
it, create the ticker on the first `Show` and delete it when the banner
lapses — `C_Timer.DeleteTicker` has no call site in `Forte_Messages` today
(grep), and the ticker-pair idiom this repo already ships is
`Forte_Cooldown/Module.lua:525`.

**m6 — `Banner:Show`/`Channel:Show` drop the colour row's 4th slot.** The pages
ship 4-slot colour rows (`Pages/SelfMsg.lua:41,56`; the source's
`Forte_Soulstone.lua:651,672` are 3-slot `{[0]=true,r,g,b}` shape and the
original's `FW:Show` consumed the row whole, `Forte_Core.lua:559`), while
`UI/Banner.lua:83-95` (the read at `:91`) and `Core/Channel.lua:45-47` passes
three numbers to `AddMessage`. A user-set alpha is inert. Either accept and
drop the 4th slot from the page defaults (the honest shape), or pass it (the
source's 4-arg `AddMessage(text,r,g,b[,id])` shape is what the Camelot
overrides take, per `Core/Channel.lua:18-23`).

**m7 — The soulstone family patterns are copied, not shared.**
`Forte_Messages/Module.lua:323` `local SOULSTONE_PATTERNS = { "^Create
Soulstone", "^Soulstone" }` vs `Forte_Warlock/Core/Tools.lua:142`
`WK.SoulstonePatterns = { "^Create Soulstone", "^Soulstone" }`. The
LoadOnDemand law forbids the reference (the copy's comment says exactly that)
and the two watchers are legitimately separate (Tools tracks the *buff*,
Messages announces the *cast*), so the finding is the drift risk with no
shared home. Move the list to `Forte_Core` (both addons depend on it) and
point both sites at it.

**m8 — Two real-client facts this review could not close.** (i) The right-click
is a raw `OnMouseUp` on a plain `Frame` (`Forte_Cooldown/UI/Timeline.lua:545`,
the press stamp at `:1002-1006` mirrors `FW:StartMoving`'s press stamp
`Forte_Core/Options.lua:649-656`, and `Moved()` is the release compare at
`:659-662`): the simulator accepts the script
(`wow-ui-sim/internal/lua2lua/widgets/widgets.go:716-726`, `"MouseUp" →
OnMouseUp`), the real client is unverified here. (ii) `Core/Sounds.lua:73-83`
calls `pcall(play, path)` at `:80`; the installed live addon's call is
`pcall(PlaySoundFile, path, "SFX")` (`CooldownMaster/UI/ReadyFrames.lua:37`),
and `PlaySoundFile` is **not** in the pinned catalog (verified absence) — the
channel arg may be load-bearing. Both are launch-day preview items; the gates
that hide them are `Warn` (E-series, default on) and `Sound` rows (default on
for fade/break), so preview them on the first client run.

---

## Verified clean

Law scan (all re-opened, no findings):

- No top-level `CreateFrame`/`RegisterEvent` in the reviewed new files: the
  Warn event frame is created inside `Init`
  (`Forte_Cooldown/UI/Timeline.lua:579-582`), the splash window in
  `Init` (`UI/Splash.lua:170-215`), the Banner frame in
  `Banner:Init` (`UI/Banner.lua:53-79`), the soulstone watcher in `OnEnable`
  (`Forte_Messages/Module.lua:455-462`), and the `WEAPON_ENCHANT_CHANGED` /
  bag frame registrations in the Cooldown `OnEnable`
  (`Forte_Cooldown/Module.lua:437-459`). No vararg-less `OnEvent`.
- Hidden-frame pump law: the splash window installs `OnUpdate` only while
  shown (`_StartTicking`, `UI/Splash.lua:493-506`, the script at `:497`) and
  removes it on every end path (`_StopTicking`, `:508-512`, the `nil` at
  `:511`; `Update`'s own gate at `:487`), asserted headlessly
  (`tests/test_splash.lua:110,206,297`); the Banner has no `OnUpdate` at all;
  `HideZero` is pumped by the module's 10 Hz ticker
  (`Forte_Cooldown/Module.lua:525-536`), not by a hidden frame, and the
  `UpdateVisibility` gate (`Timeline.lua:1045`) keeps feeding.
- Secret law: every new API read is `pcall` + `FX.Compat.PlainOrNil` before
  use — `resolveReadyIcon` (`Forte_Cooldown/Module.lua:357-373`),
  `CastFailed`'s `C_Spell.GetSpellInfo` (`Timeline.lua:978-988`), the
  right-click's `GetCursorPosiion` (`Timeline.lua:1021-1040`, pcall'd because
  the Camelot override taints it), `spellNameFor`
  (`Forte_Messages/Module.lua:337-345`), `Announce:chatLocked`
  (`Core/Announce.lua:79-84`), `Channel:Show`'s `AddMessage`
  (`Core/Channel.lua:43-49`), `Sounds`' `_G.PlaySoundFile`
  (`Core/Sounds.lua:64-84`), the Banner's `SetFont`/`GetFont` round trip
  (`UI/Banner.lua:63-74`). A raw-byte scan of the new files found no arithmetic
  or comparison on a secret-capable value.
- Event payloads match the pinned catalog exactly: `UNIT_SPELLCAST_SENT`
  `(unitTarget, target, castGUID, spellID)` — `@UnitDocumentation.lua:4802`;
  `UNIT_SPELLCAST_SUCCEEDED` `(unitTarget, castGUID, spellID, castBarID)` —
  `:4844`; `UNIT_SPELLCAST_FAILED` `(unitTarget, castGUID, spellID,
  castBarID)` — `:4713`. The handlers' slot picks are right
  (`Forte_Messages/Module.lua:357-372`'s `c`/`b`; `Timeline.lua:958-959`'s
  `spellID`), and the SENT `target` slot is a `ConditionalSecret` in the
  catalog, here PlainOrNil'd and used only as a string.
- The bus (`Forte_Core/Core/Events.lua:47-127`): validated `On`, a handle-based
  `Off`, a snapshot-then-dispatch `Fire` (an `On`/`Off` from a listener cannot
  mutate the running dispatch), per-listener `pcall` with the failure named,
  `ListenerCount` for the tests. `FX.Fire`'s payload is plain strings by
  construction on every fire site checked.
- The tocs and the index: `UI/Splash.lua` is in `Forte_Cooldown.toc`; all 15
  Camelot twins are byte-identical; `Forte_Messages.toc` lists all 8 files with
  `Dependencies: Forte_Core` and no class addon (the LoadOnDemand law,
  `Forte_Warlock/Core/Tools.lua:14-19`) and its soulstone feature is
  name-based, so that is lawful; `O.INDEX` (`Forte_Options/UI/Window.lua`)
  carries cells for `Splash`, `SelfMsg`, `Sound`, `RaidMsg`; the raw-byte key
  census across `Forte_Messages` shows `used-not-defined: []`, no key
  collisions between the three pages, and `Read y*`/`Expire*`/`Soulstone*` key
  sets identical between `Module.lua` and the pages.
- Tests: 380 registrations counted across the suites (Cooldown 136, Core 37,
  Hunter 38, Messages 28, Options 49, Timer 53, Warlock 39). The new suites use
  public paths only: the event scripts through `GetScript("OnEvent")`, the
  right-click through `GetScript("OnMouseUp")`, the banner/fade/sound rows
  through `FX.Fire`/`ST:Set`, the splash through `Init`/`OnReady`/`Update`, and
  every visibility assertion is `IsShown()` (`tests/test_timeline.lua`,
  `tests/test_splash.lua`, `Forte_Messages/tests/*`).

Fidelity checks that passed (the source sites, all re-read):

- **The fade/break law.** `FadeWarnFor` (`Forte_Timer/Core/Rows.lua:112-118`)
  reads `FX.Timer.FadeWarnings[spell]`, and the registry parses the digits out
  of the *stored text* (`Forte_Messages/Module.lua:264-290`), which is the
  source's `ST_GetFadeTime` mechanism verbatim
  (`Forte_Timer.lua:1590-1603`, the `tonumber(strfind(...,"(%d+)%s*seconds!"))`
  at `:1595`). The stamp happens at insert (`Rows.lua:269`, `:316`), not at sweep —
  the source stamps per insert too (`Forte_Timer.lua:1214`). The fire gate
  (`Rows.lua:536-548`) is the source's `st[i][1] - (GetTime()-st[i][16]) <=
  ST_GetFadeTime(...)` (`Forte_Timer.lua:1049`) with the same `kind == CROWDS`
  precondition (the sweep's kind gate), played once (`:545` zeroes).
- **The six CC rows are verbatim.** `Fear`/`Banish`/`Enslave`/`Seduce` fade +
  break texts and all six `{[0]=bits}` party bits byte-match
  `Forte_Class/Warlock/Warlock.lua:372-373,382-391`,
  `Mage/Mage.lua:121-122`, `Rogue/Rogue.lua:101-102`. The four sound rows byte-
  match `Forte_Timer.lua:3297,3298,3299` + the `TimerClearcastingSound` path,
  `OutputRaid`/`Output` match `Forte_Core.lua:2518-2519` (with `MyProChannel`
  correctly treated as a sample value, not a default).
- **The splash bell.** `s1 = 1 - 4*(0.5 - t14)²` (`UI/Splash.lua:147-152`) is
  `Forte_Cooldown.lua:1025`; the size `32*(scale+(SSM-scale)*s1)`
  (`Splash.lua:157-165`) is `:1028`; the alpha law (icon `s1*s.alpha` inside the
  frame's own `s.alpha`, `Splash.lua:445-449`) is `:1027` × `:1060`, and the
  documented product `s1*s.alpha²` = 0.49 peak matches. The base-32 geometry is
  `:1028/:1043-44/:1061-62`; the placeholder law (`Splash.lua:332-371`, alpha
  `s.alpha`, spark `2.2*32*scale`, no `t14` term, the `i == 1` gate) is
  `:1041-1050`; the `SplashGlow` crop/spark (`Splash.lua:304-330`) is
  `:978-988` + `:1031-1034`; the defaults (`Enable = false`, `SSM = 4`,
  `Glow = true`, `alpha = 0.7`, `scale = 2`) are `:1869-1873`; the plate
  (`+6` inset ×2, `BgColor[4] × PlateAlpha`) is `:1843/:1865/:1860`;
  `SplashStrata` is inherited from the existing window code as the source's
  `:1067` is from the source's.
- **The Warn law.** The `S.Warn` gate (`Timeline.lua:979`) is the source's
  handler on/off on the checkbox (`:953-960`); "a spell already on the bar"
  (`:993-996`) is `:938`; the BUFF/DEBUFF exclusion (`:995-996`) is `:939`'s
  category test, carried by the row's colour class (documented in-place);
  the attention spark's `2.2*Height*t20` (`_UpdateAttention`,
  `:1869-1900`, the size at `:1878`) with `t20` running 1.5 → 1.0 over
  `focustime = 0.5` is `:1409` + `:529` + `:32`; the focus
  ownership rules (`:1793-1860`, called from `_UpdateAttention` at `:1833`) are
  `CD_FocusTimer`'s
  `:860-878` — a `group > 0` gate (`:1819`), a single member keeping its own
  focus (`:1835-1838`), the shared t14 ride (`:1575-1584`), the stolen focus
  riding the focused bar's alpha (`:1581`). One documented shape choice: the
  source's singleton flashers get `cd[i][8] = 0, cd[i][12] = i`
  (`:557-571`), so a *single* warned bar does flash, and the port matches that
  (`:1836-1838`'s own-group id).
- **The geometry modes.** `axisPoint`/`axisOffset`/`segmentPoints`
  (`:1600-1700`) reproduce `:1427-1450` — the monotonic power axis, the
  per-side `s1/s2` clamps (`:1462-1470`) that make an out-of-window cooldown
  saturate to the near end, the Flip mirror (`:1441-1445`), and the
  vertical-bottom branch (`:1444-1449`); `ApplyBarSize` (`:425-441`) is the
  `frame.Update` size swap `:1477-1483` including the backdrop's `TexCoord`
  pair; `HideZero` is the `Draw` gate's `s.Hide` term (`:1348`), the frame
  default at `:1813`. `SetVertical`/`SetFlip` invalidate the segment cache and
  rebuild tags/effects (`:926-941`), and the rescale path keeps the splash
  centres on the icons through `ReflowEffects` (`:651-664`) and
  `ApplyFrameFX`'s re-anchor (`:1912-1917`).
- **The announce routing.** `Announce:Group` (`Core/Announce.lua:128-149`) is
  `FW:ToGroup`'s shape verbatim (`Forte_Core.lua:2046-2056`: a raid gets
  `"RAID"`, a party `"PARTY"`, neither = silence); `Announce:Channel`
  (`:157-195`) is `FW:ToChannel`'s (`:2058-2070`) with the `SAY`/`YELL`/
  `CHANNEL1-10` spellings verified against the installed live addon
  (`WhisperMessenger/Core/ChatGateway.lua:81` sends `sender(text, "RAID")`)
  and the legality trio (`SendChatMessage`,
  `AreOutgoingAddonChatMessagesRestricted`, `InChatMessagingLockdown`) is in
  the pinned catalog (`@ChatInfoDocumentation.lua:13,61,105`);
  `DEFAULT_CHAT_FRAME:AddMessage` is used by nine installed live addons
  (grep over `Interface/AddOns`).
- The soulstone watcher's pairing is name-verified on both events
  (`Module.lua:346-374`) with a single `_ssPending` slot, which is right for a
  self-cast spell; the `?` placeholder for a SENT that never arrives is
  documented at `:364-367`.

Gate/tests state at review time: the tree's 380 test registrations, all new
files represented (`Splash.lua`, `Events.lua`, all 7 `Forte_Messages` code
files, `Core/Rows.lua`, `UI/Timeline.lua`, `Module.lua`). `python3
scripts/gate.py --fast` was not run (out of scope for this review — the manager
runs it).

## Open questions (owner/launch-day)

1. **E2 is a law collision, not a bug.** The verbatim law says party-ON
   (`Forte_Class/Warlock/Warlock.lua:382-391`); the legality/opt-in law says OFF. My fix ships OFF
   with the source's bits recorded in the tip. Confirm the direction before the
   first raid.
2. Do `Enslave Demon` / `Seduction` / `Polymorph` belong in the spell lists
   (E4)? They are real BC spells (`Enslave Demon` 1098, `Seduction` 20707,
   `Polymorph` 118); the generator's family files simply omit them.
3. `PlaySoundFile(path)` — one arg (ours, `Core/Sounds.lua:93`) or
   `path, "SFX"` (`CooldownMaster/UI/ReadyFrames.lua:37`)? Not in the catalog;
   needs the first client run. Same run: do `Sound\Spells\ShaysBell.wav` and
   `Sound\Spells\SimonGame_Visual_LevelStart.wav` exist on the Forever client
   (a missing file is a silent no-op here, `Core/Sounds.lua:66-69, 80`). There is no
   preview button on the Sound page (the original had `TestSounds`,
   `Forte_Timer.lua:2885`) — worth one row.
4. Does the right-button `OnMouseUp` fire on a plain `Frame` on the real
   client (m8(i))?
5. E3's re-wrap is the smallest lawful fix, but the seam design itself
   (a module replacing a public field at `OnEnable`) will bite any future
   subscriber: should `FX.Timer` publish an `FX_TIMER_EXPIRED` fire of its own
   (the bus already exists) and retire the `onExpire` wrap?
6. E1: is a default chat line wanted at all for the launch build?
