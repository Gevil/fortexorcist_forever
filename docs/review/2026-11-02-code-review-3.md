# Code Review 3 — 2026-11-02 (CodeReview3, read-only)

Scope: code written since review 2 — `addon/Forte_Timer/**`,
`addon/Forte_Warlock/UI/**`, `addon/Forte_Warlock/Pages/Warlock.lua`,
`addon/Forte_Cooldown/Core/Enchants.lua`, `Forte_Cooldown/Engine.lua`,
`Forte_Cooldown/UI/Timeline.lua`, `addon/Forte_Options/UI/Window.lua`.
Review 2's fixed/refuted items (n1, n2–n7) are NOT re-raised; where a fix
extends into the new code, the gap is named as its own finding (C4).

All cited lines re-opened today. Source quotes re-verified against
`/tmp/fxref/Forte_Timer/Forte_Timer.lua` (maxlag `:33`, BuffDelay `:69`,
grace marking `:1186`, removal `:1207-1211`, alpha/HideLonger `:2146-2168`).

## Counts

- **Major: 5** (C1–C5)
- **Minor: 9** (m1–m9)
- Verified clean (selected): all event-payload indices vs `api-coverage.json`
  (SPELLCAST SENT/START/SUCCEEDED/FAILED/INTERRUPTED, UNIT_AURA, UNIT_DIED,
  WEAPON_ENCHANT_CHANGED, BAG/ITEM events); all OnEvent bindings
  `function(_, event, ...)`; `HARMFUL PLAYER` / `HARMFUL` filter strings are
  documented shapes (`UNIT-AURAS.md:164`, `:92`); review-2 fixes n1/n2/n3/n6
  verified in place (Sweep name-pop, pulse/splash pool scan, release
  endAt-guard, header m4); toc twins byte-identical (Timer, Warlock);
  SavedVariables seeds (`FX.db.timer.*`, `FX.db.warlockUI`,
  `FX.db.settings` deep-copy) sound; secret law (`PlainOrNil` gates)
  respected everywhere, incl. `Reconcile:ReadFact` pcall+issecretvalue.
- Two suspicions raised during this review and REFUTED, recorded in
  "Refuted" below so they are not re-hunted.

## Top 10

1. **C1** — `RemovalRefused` polarity is inverted vs the quoted source law;
   the aura-absent sweep can never retire a consumed aura before its last
   second (design T6 asserts the opposite; the test pins the inversion).
2. **C2** — `Laws.CheckableAt` defined twice; the second (non-source)
   definition wins; short-window rows become checkable at
   `expireAt − 4`, i.e. *before* the source's `castTime + 4` grace.
3. **C3** — `Reconcile:Gates()` combat probe falls back to global `InCombat`,
   which exists nowhere; the production gate is inert (tests inject the
   seam and cannot see it).
4. **C4** — the n4 header-lock fix hard-branches `Hunter / everything-else →
   FX.Cooldown.Display`; all five new pages (SpellTimer + four Warlock)
   read the *Cooldown bar's* lock, re-opening the exact n4 divergence.
5. **C5** — the Spell Timer page ships 11 widgets whose tips say
   "Applied live" with **no consumer at all** (7 colour pickers,
   ShowStacks, ShowTooltips, OffsetSelf, OffsetTarget).
6. **m1** — `Frame:_HookSettings` has no `_wired` guard; every
   `OnClassChanged("WARLOCK")` re-registers 4 listeners per plate
   (unbounded growth; the project's single-registration convention).
7. **m2** — `Timeline:AcquireSlot` writes global `slot` (missing `local`,
   `Timeline.lua:884`) — shared-environment global named `slot`.
8. **m3** — `HealthstoneColor` (page DEFAULTS + colour widget "Applied
   live") has zero consumers; the only plate colour without a keymap pair.
9. **m6** — `SetShowTarget` silently overwrites `options.label`; the Label
   checkbox/store desync from the screen.
10. **m7** — `expireMessage` / `onExpire` / `NotifyExpiry` is a fully dead
    production path (no defaults write it; only a test sets it).

---

## Majors

### C1 — `Laws.RemovalRefused` inverts the source's removal condition
**Class:** law divergence vs `/tmp/fxref` source (late-effect-never-fires).

`addon/Forte_Timer/Core/Laws.lua:453-455`:
```lua
function Laws.RemovalRefused(expireAt, now)
    return (expireAt - now) > Laws.MAXLAG
end
```
Source, `/tmp/fxref/Forte_Timer/Forte_Timer.lua:1207` (verified in tree):
```lua
elseif st[i][10] == 1 and (st[i][1]==0 or st[i][1]-t>maxlag) then -- dont remove if only maxlag left
```
The source *permits* removal exactly while `expire − t > maxlag` (it refuses
only in the last `maxlag` seconds, where natural expiry owns the row). The
port refuses exactly while `expire − now > MAXLAG` — the inverse inequality
of the line it cites. The design doc quotes the source verbatim
(`docs/design-spell-timer.md:265`) and paraphrases the inverse at `:280`,
`:454`; the doc's own acceptance row T6 (`:653`) — "an adoptable row 0.5 s
from expiry is **not** removed" — is the SOURCE polarity, which the code
violates: `addon/Forte_Timer/tests/test_rows.lua:401-403` asserts
`Reconcile:SweepUnit(…, 14011.5)` ⇒ `Laws.REMOVE` (source: 0.5 s left ⇒
condition false ⇒ never removed), and `:400-401`/`:402` assert NORMAL at
3 s left (source: 3 > maxlag ⇒ REMOVED). The suite therefore pins the
inversion, and no test can fail on the fix.

**Failure scenario (verified composition, `Rows:OnAuraAbsent`
Core/Rows.lua:346-356):** out of combat, a 12 s DoT is consumed/removed early
by a game effect at cast+2. The gated sweep reads "aura absent" at
cast+2.1 (past the C2 grace for short windows): `RemovalRefused(12012, 12002.1)`
⇒ 9.9 > 1 ⇒ refuse. The row keeps counting down on screen for **~11 more
seconds** as a phantom window, and can only die in its final second. The
source removes at once (grace `st[10]==1` is set from castTime+4, `:1186`).
The out-of-combat reconcile — phase 4's "the real aura data repairs the
drifted row" feature — can retire rows in a ≤5 s window only; every row
≥5 s is retirement-immune.

**Fix:** `return (expireAt - now) <= Laws.MAXLAG` for the refusal predicate
(and keep the grace as the lower gate), then fix the three asserts at
`test_rows.lua:400-404` to the source table (removed at 3 s left, kept at
0.5 s left) — the current asserts pass on both polarities for the grace
half and on the wrong polarity for the removal half.

### C2 — `Laws.CheckableAt` is defined twice; the winner is not the source law
**Class:** law divergence + dead-code shadowing.

`addon/Forte_Timer/Core/Laws.lua:383-385`:
```lua
function Laws.CheckableAt(castTime, total)
    return (castTime or 0) + Laws.BUFF_DELAY
end
```
`addon/Forte_Timer/Core/Laws.lua:460-462` (later, overwrites):
```lua
function Laws.CheckableAt(castTime, total)
    return (castTime or 0) + (total or 0) - Laws.BUFF_DELAY
end
```
Lua file order ⇒ the second body is the one `Rows:OnAuraAbsent`
(Core/Rows.lua:349) calls. The first is the source law:
`/tmp/fxref/Forte_Timer/Forte_Timer.lua:1186` marks the row checkable when
`(st[i][3] − st[i][1] + t) >= BuffDelay` with `st[3]=total`,
`st[1]=expireAt` (`:1201`), i.e. `t ≥ expire − total + BuffDelay =
castTime + BuffDelay` — exactly the dead first definition. The winner is
`expireAt − BUFF_DELAY`: "four seconds before the window ends", measured
from the *end*. Consequences, by window length:
- window ≥ 9 s: checkable window starts after the source's — the grace is
  later than the law (masked in practice by C1, whose refusal dominates);
- window < 5 s (short procs, Spellstones): checkable at `expire − 4 ≤
  castTime + (total−4) < castTime + 4`, i.e. **before the source's grace
  ends** — for windows ≤ 4 s, from the cast instant itself. A short aura
  whose server-side `expirationTime` runs ahead of the predicted window
  (lag, haste — the exact case BUFF_DELAY was measured for, `:69`) is
  judged "gone" within the settle window and deleted early, up to the
  whole BUFF_DELAY.

**Fix:** delete the second definition (its docstring at `:457-459` restates
the first law verbatim — the body contradicts its own comment), add a test
pinning `CheckableAt(c, t) == c + BUFF_DELAY` for short windows so the
shadowing can not return. The grace test at `test_rows.lua:386-427` is blind
to the difference (seeded 12 s window; both variants answer identically at
every probed instant) — it passes before and after.

### C3 — `Reconcile:Gates()` falls back to a global that does not exist
**Class:** late-effect-never-fires (production gate inert, tests inject the seam).

`addon/Forte_Timer/Core/Reconcile.lua:67-72`:
```lua
local probe = self.inCombat
if probe == nil then probe = InCombat end
if type(probe) == "function" then
    local ok, combat = pcall(probe)
```
`InCombat` is not a global on this client (the whole project's probe is
`InCombatLockdown` — `Forte_Timer/Core/Casts.lua:78`, `Forte_Hunter/Core/Tools.lua:50`,
`Forte_Cooldown/UI/Timeline.lua:718`, `Forte_Core/Core/Probe.lua:80`; grep of
`addon/` finds no `InCombat(` anywhere else). No production path assigns
`Reconcile.inCombat` (only `test_rows.lua:399`/`:468` set and clear it), so
in play `probe` is nil ⇒ `type(nil) ~= "function"` ⇒ the gate answers
`false` in combat. The comment at `:65-66` ("in combat the read is sealed …
the sweep does not run") is the design's precondition (§3.5 "Out-of-combat
aura reconcile"), and it is precisely the case the fallback was there for:
on a client whose `FX.SecretState.aurasSecret` is nil — the file's own
"this client gives me no answer" branch (`:62-63`) — the combat flag is the
*only* gate, and it is dead. Effect: mid-combat full sweeps issue
`GetUnitAuras` reads every throttle window; they come back sealed
(`counts.secret` climbs, no data damage — reads are legal), which is exactly
the wasted-read class the gate exists to stop.

**Fix:** `if probe == nil then probe = InCombatLockdown end` (type-guard
already `nil`-safe). No existing test distinguishes the globals — add the
assert `Reconcile:Gates() == true` under `_G.InCombatLockdown =
function() return true end` with `inCombat` cleared and
`SecretState.aurasSecret = nil`.

### C4 — header lock icon: the n4 fix hard-branches two modules; the five new pages read the Cooldown bar
**Class:** divergence re-opened by scope extension (review-2 n4 family).

`addon/Forte_Options/UI/Window.lua:679-690`:
```lua
local frame = (def.module == "Hunter"
    and FX.Hunter and FX.Hunter.Swing
    or (FX.Cooldown and FX.Cooldown.Display))
if frame and frame.cfg and frame.cfg.locked ~= nil then
    locked = frame.cfg.locked
```
The n4 ruling: the header glyph reads **the frame the page's module owns**.
The fix encodes the 2026-11-01 module world; the pages added since declare
`def.module = "SpellTimer"` (Pages/Timer.lua) and `def.module = "Warlock"`
(Pages/Warlock.lua, four pages) with `def.lockKey = "Lock"`, and fall into
the `or` branch ⇒ their icon reads `FX.Cooldown.Display.cfg.locked`.
`FX.db.settings`-store is not consulted (`:687` only as fallback).

**Failure scenario (Warlock plates; verified reachable):** GlobalLock=false,
Cooldown.Lock=true (bar locked). A Warlock drags the Shards plate unlocked:
`Frame:OnMoveStop → SetLocked(false)` publishes `Warlock.Lock=false`
(Frame.lua:575-588; the frame publishes its own key, not GlobalLock).
The live listener updates the open header, but on **page re-open**
`BuildHeader` re-reads the Cooldown bar ⇒ glyph says locked while the
Shards-plate checkbox (store `Warlock.Lock=false`) says unlocked and the
plate is draggable — n4's exact repro, new pages. (The SpellTimer page is
conservative only by coupling: `Module:SetLocked` cascades into
`Display:SetLocked`, so the two bars agree, `Forte_Timer/Module.lua:436-446`.)
The shared relay (`Module.lua:252-257`, Swing `:519-528`) keeps
GlobalLock/Cooldown.Lock/Hunter.Lock synchronized; `SpellTimer.Lock` and
`Warlock.Lock` join that family, which is precisely why a
*per-module-frame* lookup — not a module equality test — is the law.

**Fix:** replace the branch with a module→frame table fed at page
registration (`def.frameExpr`-style: the page hands `function() return
FX.Timer.Display end` / `function() return FX.Warlock.Shards end`), falling
back to the store read the comment already prescribes. Extend
`test_options.lua`'s n4 scenario to one of the five new pages.

### C5 — Spell Timer page: 11 widgets labelled "Applied live" have no consumer
**Class:** settings keys without consumers (options over-claim).

Every key below is registered in `ST:Register("SpellTimer", M.DEFAULTS)`
with a widget whose tip ends "Applied live", has a KEYMAP entry
(`Forte_Timer/Module.lua:166-199`) and a setter writing `self.options.*` /
`self.skin.*` — and **no read anywhere** (grep of `Core/Rows.lua`,
`UI/Rows.lua`, `Core/Laws.lua` for each field; the renderer's read-set is
`groupWidth,height,barWidth,iconSize,barInset,inset,enable,hide,normalAlpha,
label,showTarget,space,labelHeight,spacingHeight,altTimeFormat,smartSpace,
spell,showID,iconStacks,spark,markPredicted,ticks,barOffset via barInset`):

| key | widget | writes | read count |
|---|---|---|---|
| `ColourNormal` | Pages/Timer.lua:243-245 | `skin.ColourNormal` (Module:372) | 0 — `ColorVal` reads `skin[COLOR_KEY[kind]]` bands (Laws:247-248), never `ColourNormal` |
| `ColourExpiry` | :246-248 | `skin.ColourExpiry` (:373) | 0 |
| `BarColorSelf` | :255-257 | `skin.BarColorSelf` (:382) | 0 (no per-unit colour law exists in the port) |
| `BarColorTarget` | :258 | :383 | 0 |
| `BarColorFocus` | :261 | :384 | 0 |
| `BarColorPet` | :264 | :385 | 0 |
| `BarColorEnemy` | :267 | :386 | 0 |
| `ShowStacks` | :219-221 | `options.showStacks` (:417) | 0 — `NameText` appends the `(n)` suffix on `opts.stacks` unconditionally (`Laws.lua:338-340`, fed at UI/Rows.lua:596-598); unchecking shows stacks on |
| `ShowTooltips` | :225-227 | `options.tooltips` (:418) | 0 — no tooltip exists on the panel; the page's own header comment (Pages/Timer.lua:23-25) says "not wired", the widget tip says "Applied live" — the same file contradicts itself |
| `OffsetSelf` | :282-285 | `options.offsetSelf` (:424-427) | 0 — the row inset is `o.barInset` (UI/Rows.lua:609), fed only by `SetIconOffset`/`SetSize` |
| `OffsetTarget` | :286 | :428-431 | 0 |

User-visible effect: changing any of the seven colour pickers repaints
nothing (the pickers write skin rows no drawing path reads); the two stack/
tooltip checkboxes and the two offset numbers are inert. Contrast the
neighbours that DO work (`ColourFlash→skin.Fail` Laws:255,
`ColourExpired→skin.ExpiredColor` :281-283, `ColourOverride→opts.colorOverride`
:262, `IconOffset→barInset` :421-423, `MaxOn/OneMax/GroupID/Smooth/Blink/
HideLonger` all read in `Core/Rows.lua`/`Laws:413`) — the seam itself is fine,
the map over-claims. `Time`, `Icon`, `Flip` (keymap `:176-181`) are equally
unconsumed but ship no widget — dead map rows only.
The page's own header (Timer.lua:23-25) marks `Scale`/`Alpha`
"not wired" while they ARE wired (`Module.lua:390-401`) — stale label in the
other direction.

**Fix:** per key, either wire the consumer (the five BarColor* need the
per-caster law the design cites at §3.6 — `row.raidMark` exists) or retitle
the tip "not wired yet (stored)" like General's `ShowTooltips` already
honestly does (Pages/General.lua:11-12, tested inert at
test_timeline.lua:1074-1085). The page-law test (test_module.lua's
settings-seam) asserts only wired keys — add a census: every `KEYMAP`
module key of the page's module is asserted to have a consumer
(grep-shaped: the setter's written field appears in a reader), so the next
page addition can not silently over-claim.

---

## Minors

### m1 — `Frame:_HookSettings` registers listeners with no `_wired` guard
`Forte_Warlock/UI/Frame.lua:839-901` registers FOUR `OnChange` listeners
(module, shared, General, Cooldown); `Frame:Init` (`:276-281`) calls it,
and `U:OnClassChanged("WARLOCK")` (`UI/Module.lua:274-279`) re-runs
`_InitViews → Init` on every class return (the T4/T15 class-picker
scenario the suite itself drives). `FX.Settings` appends listeners with no
dedup (`Forte_Options/Core/Settings.lua:115-121`), so each round trip adds
4×4 listener copies per session; every `Set` fires all copies (idempotent
work, O(N) per click, unbounded list). Every sibling honours the convention
(`_wired` Module:244, `_lockWired` Window, `wired` Hunter page). Add the
guard.

### m2 — `Timeline:AcquireSlot` leaks the global `slot`
`Forte_Cooldown/UI/Timeline.lua:884`: `slot = { frame = frame, … }` — no
`local` in the grow branch (the reuse branch's `local slot` at `:835` dies
at the branch). Every pool growth writes the shared-environment global
`slot` (visible to every addon in the environment; a trivially collidable
name). Functional here (the table is stored at `:886` in the same write
window), pure hygiene — one word.

### m3 — `HealthstoneColor` is an orphan key
`Forte_Warlock/Pages/Warlock.lua:88` (DEFAULTS), `:263-266` (colour widget,
tip "Applied live"). Grep of the addon: the key occurs ONLY in
Pages/Warlock.lua. The other three plates pair their `<Name>Color` into a
keymap (Shards.lua:52-family, Healthstone's keymap covers
Size/Strikethrough only, Healthstone.lua:50-55). `_HookSettings` routes the
key to nothing; the count colour follows the shared `TextColor` only.
Wire it (Healthstone keymap `HealthstoneColor = "SetCountColor"`-pair) or
drop the widget.

### m4 — `Pages/Warlock.lua` routes through a method that does not exist
`Forte_Warlock/Pages/Warlock.lua:111-114`:
`if v and v.ApplySettings then v:ApplySettings({ [key] = value }) end`.
No method `ApplySettings` exists on `Frame`/views (grep: hits only in
Forte_Cooldown/Forte_Hunter/Forte_Timer). The listener is dead code; the
frames' self-wiring (`Frame:_HookSettings`) is the live path — behaviour
correct, law-text false (the comment claims a "page-side mirror, idempotent
with it"; there is no mirror to be idempotent with). The Hunter page's
identical-shape listener targets a real method (Swing:486). Delete the
block (the self-wiring is complete) — do NOT add a Frame:ApplySettings, the
`_HookSettings` keymap is the Warlock idiom.

### m5 — `Frame:_AttachTip` passes the parent in the name slot (latent)
`Forte_Warlock/UI/Frame.lua:480`: `self.tip = CreateFrame("Frame",
self.anchor)` — the 2nd CreateFrame argument is the NAME; the parent is the
3rd (see the correct shape 24 lines below at `:504`: `CreateFrame("Frame",
nil, self.anchor)`). Latent today: no view sets `opts.tip`, so the guard at
`:479` returns first (Shards builds its tip correctly with its own frames).
When the next view opts in: a tip frame with no parent (does not inherit
plate scale/strata, survives plate hide) and a frame-named-by-a-frame.
One-word fix now: `(nil, self.anchor)`.

### m6 — `SetShowTarget` entangles the Label key
`Forte_Timer/Module.lua:295-298`:
```lua
function M:SetShowTarget(on)
    self.options.showTarget = not not on
    self.options.label = self.options.showTarget
end
```
Unchecking "Show target names" also writes `options.label = false`, while
the separate `Label` key (checkbox + store) keeps its old value — the
Label checkbox then displays ON while labels are off, until a reload
re-applies `Label=true` (which re-shows labels the user just killed via the
other checkbox, because the ShowTarget store row says false…). The two
keys have one shared effect and two independent stores. Decouple (the
renderer already ANDs both: `UI/Rows.lua:469`).

### m7 — `expireMessage` / `onExpire` / `NotifyExpiry`: no production writer
`Forte_Timer/Core/Rows.lua:217` gates the row's expiry-message stamp on
`self.options.expireMessage`; `:394-395` counts `FX.Timer.NotifyExpiry` and
calls `opts.onExpire`. Grep of the addon: no default, no setter, no page
key, no Status reader — only `tests/test_rows.lua:264/268` fabricate the
field. The announce half of the §3.5 law is thus untested-in-production
(the test passes while the feature can never fire in the game). Decide: a
`SpellTimer` keymap row + page checkbox (the source had announce
channels), or delete the branch; today it is an untested law half.

### m8 — pulse/splash icon: `SetTexture(nil)` reachable
`Forte_Cooldown/UI/Timeline.lua:1047` `s.tex:SetTexture(texPath)` with the
`texPath` from `slot._texPath` (`:1334`); an entry whose icon resolved nil
(a sealed `GetSpellTexture` — the law's own case, Enchant entries whose
`enchantIconID` read sealed, Enchants.lua secrecy model) binds the slot
with a nil path, so the ready-pulse renders as a lone ADD-blend spark
flying the bar. No crash; a visual ghost. Guard: skip the pulse (or fall
back to `S.Spark`-less flash) when `texPath == nil`.

### m9 — `Module:SetLocked`'s asymmetric persistence branch is dead (cosmetic)
`Forte_Timer/Module.lua:439-440`:
```lua
if d and d.cfg then d.cfg.locked = locked end
if not locked and self.cfg then self.cfg.locked = locked end
```
`Display.cfg` IS `self.cfg` (both `FX.db.timer.display`, `Init(opts, skin,
self.cfg)` at Module.lua OnEnable), so `:439` persists BOTH directions and
`:440` is unreachable-effect-only code. Verified benign (the feared
"`/fx lock` does not persist" reading is refuted — see Refuted), flagged so
the reader stops reading an asymmetry into it: delete line 440.

---

## Refuted during this review (do not re-hunt)

- **`Reconcile` bulk read of `aura.name` outside pcall** (Reconcile.lua:258
  `aura and plain(aura.name)`): safe — field reads on the AuraData shape
  return secret values, `plain = FX.Compat.PlainOrNil` (`:76`) converts to
  nil, and `ReadFact` (`:83-86`) adds the `issecretvalue(aura)` guard.
- **`Module:SetLocked` lock-direction does not persist**: refuted, m9
  (shared cfg table).
- **`InCombat` fallback in Reconcile is "just a name"**: it IS the bug
  (C3), listed Major, not refuted.
- **`FX.Timer.Registry` `HARMFUL PLAYER`-style filter strings**: documented
  composition, `UNIT-AURAS.md:161-167`.
- **`FX.db.timer` / `FX.db.warlockUI` SavedVariables shapes**: fresh keys,
  deep-copy seeding, nil-SV fallbacks present (Module.lua OnEnable,
  Frame.lua:520-536) — no legacy shape to migrate, no shape bug.

## Open questions

1. C1/C2: is the removal/green-window pair a deliberate Forever-law ruling
   (a 2026-11-02 "server clock" concern)? The design doc contains BOTH
   readings (§3.5 table quotes the source lines; the paraphrase inverts
   them). Owner ruling needed before the tests are flipped — the fix
   changes asserted behaviour at `test_rows.lua:400-404`.
2. C5: are the five per-unit `BarColor*` bands part of the phase-4
   renderer (design §3.6 cites the source's per-caster colours) — if yes
   the page widgets are early and the law is missing; if no, they are dead
   picks. Only the owner knows the roadmap intent.
3. The Warlock-plate header lock has no per-module *frame* for
   `FX.Warlock.<View>` (frames self-publish `Warlock.Lock` only); the C4
   fix should pick `FX.Warlock.Shards` (all four plates share the one key)
   — confirm the plates must move as one lock unit (they do today).
4. `Forte_Timer` announce channels (m7) need the owner ruling: ship
   (source `RaidMsg`/`SelfMsg` pages exist in `O.INDEX` dimmed) or strike.
