# Code review 9 — Iteration K/L (`fd7b3f3..HEAD`, `addon scripts tools`)

Scope reviewed: K2 (swing demo, fuller fill, Target pump), K3 (RekeyLegacy first-name leg,
ReadFact past-expiry, offSkipped, Locale dead code, rateSkipped, rangeEdges), K4 (F1 frozenFillW,
F2 ShowSafeWindow fold, F3 melee secret spellID, F5 cap, F9 gcd), K4B (palette + weave-line
Frame-only-method fix), K7 (client cast time, SetFillEngineMode guard), K8 (Mage Clearcasting).
Findings first, then the per-priority evidence, then open questions.

Verdict: **2 MAJOR, 3 MINOR, 2 INFO.** The MAJORs are (1) the F2 fold flipping every fresh
Hunter profile off the shipped Safe-window default, and (2) the RekeyLegacy first-name leg able
to move a first-name sibling's profile. Nothing found in priorities (1), (4), (5), (6): the
weave-line fix is complete (full census below), the demo's swap/ticker scrub is airtight on
every exit, the palette keeps `default` byte-identical and the pick in `BASE`, the tree lints
clean.

---

## MAJOR 1 — the F2 fold stamps `BarMode = "elapsed"` on profiles that never had the legacy key

`addon/Forte_Hunter/UI/Swing.lua:2142-2154` (`storedModeWords`), used at `:2207-2222`
(`ApplyStoredSettings`):

```lua
    local mode = FX.Compat.PlainOrNil(raw.BarMode)
    local legacy = FX.Compat.PlainOrNil(raw.ShowSafeWindow)
    return raw,
        (type(mode) == "string") and mode or nil,
        ((legacy == true or legacy == false) and legacy)
```

and:

```lua
                    if legacy ~= nil then
                        raw.ShowSafeWindow = nil
                        if chosen == nil then
                            chosen = (legacy == true) and "safe" or "elapsed"
                            raw.BarMode = chosen
                            out.BarMode = chosen
                        end
                    end
```

When `ShowSafeWindow` is **absent** (`legacy` nil), the third return expression evaluates
`(false) and nil` = **`false`** — the "no word" case collapses into the "the word is `false`"
case. The consumer's gate is `legacy ~= nil`, and `false ~= nil`, so for any raw profile with no
`ShowSafeWindow` key and no `BarMode` key the fold fires: `chosen = (false) and "safe" or
"elapsed"` → `"elapsed"`, **persisted** (`raw.BarMode = chosen`, :2219) and applied (:2220).

Failing scenario on the real client, tonight: a fresh install (fresh character — the raw
`_store("Hunter")` table carries only keys the player actually set) logs in; the login pass runs
`ApplyStoredSettings`; the bar boots in the **Elapsed fill** mode instead of the shipped
registered default `BarMode = "safe"` (`addon/Forte_Hunter/Pages/Hunter.lua:53` — "BarMode
REPLACES ShowSafeWindow ... this ONE registration"; the K5 clip and `scripts/scenarios/
hunter-swing-signals.lua` header both ride "`barMode "safe"` IS the Safe window mode"). The
Options picker then reads `Elapsed fill`, the stamp makes it permanent (the registered default is
shadowed behind the stored word), and a legacy profile whose key was retired by an earlier fold
takes the same hit on its next login (retirement leaves the key absent → `false` → stamp).

Why the suite is green: every leg of `tests/test_swing.lua:381-426` writes
`raw.ShowSafeWindow = false` before `ApplyStoredSettings` (the spoke case, folded correctly);
the leg ends with `wipe()` (`:424`), leaving `raw = {}`, and the later file that runs the login
seam (`test_swing_palette.lua` "the palette applies from the store through the login seam")
asserts only colours — so the stamp of `raw.BarMode = "elapsed"` into the shared store is never
seen.

Fix (Swing.lua, `storedModeWords`): return a real nil for "no word spoke":

```lua
    local legacyWord = (legacy == true) and true
        or ((legacy == false) and false or nil)
    return raw, (type(mode) == "string") and mode or nil, legacyWord
```

Fail-first leg to add: `wipe()` (no keys at all) → `Swing:ApplyStoredSettings()` →
`assertEquals("safe", Swing.state.barMode)` and `assertNil(raw.BarMode)` (no stamp).

## MAJOR 2 — RekeyLegacy's first-name leg can move a first-name sibling's profile

`addon/Forte_Core/Core/Database.lua:233-240`:

```lua
    local function legacyOf(k)
        ...
        local headCanon = FX.Identity.Canonical(head)
        if headCanon == keyCanon then return true end
        return firstCanon ~= nil and headCanon == firstCanon
    end
```

The gate at `:228-231` proves the first name is a strict prefix of **this** character's packed
key; it says nothing about the legacy **row** belonging to this character. Forever names are
first + surname (`UnitName` = (first, SURNAME) — the measured shape this leg rides), and name
uniqueness is a whole-name fact, so one account can carry **"Anne Ashvale" and "Anne
Brightoak"**. The old key law packed the name read of its day — the first name — plus the realm
label, so on one realm both Annes wrote the same legacy key `Anne-Nethergarde`, bound into
`characters` (`:249-253` `boundToCharacter` passes it).

Failing scenario: account with the two Annes, WTF file carrying the bound legacy row. The Anne
who logs in first on the new build: `headCanon "anne" == firstCanon "anne"`, `boundToCharacter`
true, `characters["AnneBrightoak"] == nil` → the legacy profile **and its binding** are re-keyed
onto `AnneBrightoak` (`:264-267`, `:276-291`). The second Anne then logs in, finds no legacy row,
boots defaults — her settings ride under the sister's key. Cross-realm variant
(`Anne-Nethergarde` + `Anne-Ashvenos`, both bound, the mover matching both via the head):
`moveKey` is chosen by the `pairs()` walk (`:256-263` — the non-empty-settings preference at
`:258-260` breaks pairs-order ties, so the pick among equal matches is the hash layout) — the
fold can adopt the **other realm's** Anne profile over her own.

The three new tests (`tests/test_database.lua`, the uiforever-shape / bound-gate / stranger
legs) each carry exactly **one** legacy row, so none can see the sibling collision. The
user-named-profile question the leg must protect against is answered correctly: a named profile
is inert behind the bound gate (`:241-253`), the `active == k` half only rides words the addon
itself wrote.

Fix (conservative, in `RekeyLegacy` before `firstCanon` is trusted): scan `characters` — if any
bound key `K` with `FX.Identity.Canonical(K) ~= keyCanon` has `firstCanon` as a strict prefix of
its canonical, a first-name sibling shares the account: skip leg two (boot defaults — the
pre-leg behaviour) and say so in the ladder report. Cheap hardening: require the legacy key's
label half (`k:match("^[^%-]+%-(.+)$")`) to canonical-equal today's realm (pcall'd
`GetRealmName` through `FX.Identity.Canonical`), which kills the cross-realm variant outright.

## MINOR 3 — raw, un-pcalled lockdown/identity reads (pre-existing, named-API sweep)

Not introduced in this range, listed because the sweep names these APIs:

- `addon/Forte_Hunter/Core/Tools.lua:71-77` (`AspectTracker:IsCombat`):
  `return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false` — no
  pcall. Reached from `:131` (the reminder's `not self:IsCombat()` gate), which the UI event
  kicks (PLAYER_REGEN_ENABLED/DISABLED, PLAYER_ENTERING_WORLD) drive **inside OnEvent bodies** —
  the raise-prone half per this class's own law (`Forte_Hunter/Core/Melee.lua:277-287` K4 note,
  `Forte_Cooldown/Module.lua:804-816`: "a restricted client may raise on InCombatLockdown ... a
  raise inside an OnEvent is a Lua error popup"). Failing scenario: a client under
  RestrictedActions, an aspect refresh kick, the OnEvent raises — the popup the K4 F3 fix
  removed from Melee. Fix: the same shape as `Melee.lua:219-229` (pcall + `PlainOrNil`, nil = no
  knowledge).
- `addon/Forte_Cooldown/UI/Timeline.lua:1410-1413` (`UpdateVisibility`): the same raw truth
  chain. Runs on the sealed OnUpdate path with the sanctioned no-answer→out-of-combat reading
  (`test_zz_combat_bar.lua:589-593`) — shape accepted, listed for completeness.
- `addon/Forte_Options/UI/Window.lua:284-285`: `local selfName = ... (UnitName and
  UnitName("player"))` — the read is `SecretWhenUnitIdentityRestricted` (raise-prone),
  un-pcalled; the value does pass `PlainOrNil` before the `..` concat (`:286`, `:289`), so only
  the raise half is exposed, on the player-initiated Open path. Fix: wrap in pcall like
  `Database.lua:223-231`.

No diff-added site feeds any of the four named APIs raw into `tostring`, arithmetic or
comparison — see the Priority-2 table below.

## MINOR 4 — `SetFillEngineMode`'s raise path leaves the `_fillMode` memo claiming a mode the bar does not run

`addon/Forte_Hunter/UI/Swing.lua:837-859`:

```lua
    if self._fillMode == mode then return end
    self._fillMode = mode
    ...
    local ok, built = pcall(self._BuildFill, self, self.anchor)
    if (not ok) or built == nil then
        ...
        self.fill, self._engineFill = old, oldEngine
        self._fillW, self._armKey, self._fillSpanW, self._fillColor
            = nil, nil, nil, nil
        return
```

The guard restores the fill, the widget, the caches — not the memo (set at `:840`). After a
raised rebuild the bar draws on the old fill path while `_fillMode` says the new one, and a
repeat call to the requested mode is a memo no-op (`:839`) — no retry. Scenario: the K7 fossil
itself — a mode switch against a torn-down bar (`OnClassChanged` down) whose `CreateTexture`
answers nil/raises; the `test_swing_casttime.lua` "a raising rebuild ... keep the drawing fill"
leg drives exactly this and asserts the fill object, not the memo. The split self-heals at the
next `Init` (`_BuildFill` reads `_fillMode`), so the window is bounded; fix = capture
`local prevMode = self._fillMode` before `:840` and restore it on the fail arm.

## MINOR 5 — the melee rail follows the palette, not a live `BarColor` change (push asymmetry)

K4B pushes the bar colour to the rail only from the palette setter: `UI/Swing.lua`
`SetSwingPalette` → `rail:SetBarColor(S.BarColor)`, while the bar's own `SetBarColor`
(`:1165-1176`) — the live Colour-picker seam — pushes to nobody. `UI/Melee.lua` reads the colour
once at `Init` (`:150-157`, `_color = self._color or barFillColor()`, reading the live
`S.BarColor`). Scenario: a player moves the picker → the bar repaints, the rail keeps the old
fill until it is re-enabled. Login order adds the twin: with the default palette
`SetSwingPalette("default")` early-returns (no push), so a rail that Inits before the bar's
login pass reads the skin default, not the stored pick. The rail-vs-picker half predates this
range; K4B made the asymmetry explicit by pushing from one setter and not the other. Fix: the
same two guarded lines at the tail of `SetBarColor` (`local rail = FX.Hunter.Melee; if rail and
rail.SetBarColor then rail:SetBarColor(S.BarColor) end` — `SetBarColor` is legal before the
rail's Init and remembers, per its own header).

## INFO 6 — stale pinned field in the demo's tracker-face list

`addon/Forte_Hunter/tests/test_swing_demo.lua:55-57` strings `rangeEdges` into `realFace()`;
K3 removed the field (`Forte_Hunter/Core/Tools.lua` constructor, `OnSwingRange`), so the face
now carries a constant `rangeEdges=nil` half-fact. Harmless (both faces string the same nil),
but the list should drop the key with the field.

## INFO 7 — F5's value arm divides by the skin `S.Width`, not the drawn width

`_EngineFillPass`'s F5 tail (`UI/Swing.lua`, `kind = "value"` arm): `target = (W > 0) and (w /
W) or 0` with `W = S.Width`. The parity test passes because `_fillIntent` rides the same
constant (`test_swing3.lua` F5 leg: `nearpx(Swing._fillIntent, 150)`), so today it is exact;
recorded so the arm's units are unambiguous for a future per-instance-width bar.

---

# Priority evidence

## (1) Frame-only methods called on a Texture/FontString — CLEAN (the K4B fix is complete)

Census of `SetFrameStrata / SetFrameLevel / SetToplevel / EnableMouse / SetMovable /
SetClampedToScreen / RegisterForDrag / StartMoving / StopMovingOrSizing / SetBackdrop* /
SetScript / RegisterEvent` over all non-test `addon/**` (17 files; the tool census is the
record). Every receiver is a Frame, created by `CreateFrame`:
`Forte_Cooldown/UI/Splash.lua:179/273-274/672-673` (`f`, `self.anchor`),
`UI/Timeline.lua:625/765-766/1228-1229`, `Forte_Core/Core/Probe.lua:979` (`pcall(f.SetToplevel,
f, ...)`, frame), `Forte_Hunter/UI/{Melee:145-146,Range:142-143,Reminder:107-108,Swing:570/1084-1085/1332-1333}`,
`Forte_Options/Core/Widgets.lua:676-678` (`popup = CreateFrame("Frame", ...)`, and the call is
`pcall`-wrapped), `Forte_Options/UI/Window.lua:300-307/340-341` (`titleBar`, `viewport`, `content`
— all `CreateFrame`), `Forte_Timer/UI/Rows.lua:142/274-275/359-360`, `Forte_Timer/Module.lua`
(`SetStrata` on the panel anchor), `Forte_Warlock/UI/Frame.lua:478-483/498-499/530/578-579`
(`row`/`a`/`body`/`drag`/`tip` — verified `CreateFrame` at `:475`, `:471-477`, `:496`, `:529`,
`:586`). FontStrings take FontString methods only (`Window.lua:292-294` `title:SetJustifyH/
SetPoint`; `Widgets.lua:670-671` `row.label:SetTextColor`, `row.art:SetVertexColor`).
`OnUpdate` is set only on anchors under the shown-only law (`Swing.lua:2030/2048`,
`Melee.lua:321/341`, `Range.lua:268/284`, `Reminder.lua:265/281` — all with the pinned tests).

The diff's one violation — the weave line's `tex:SetFrameStrata(...)` on `self.weave` (a
`CreateTexture` texture, `Swing.lua:752`) — is removed by K4B
(`git show 825d753`, `_SetWeaveLine` now parks with `SetSize(0,0)` + `Hide`, the ARTWORK layer
being the build-time one). The guard is real: `test_swing_palette.lua` poisons the 15 Frame-only
names on all nine marker textures (+ the rail fill) and drives `Update`/`RenderIdle`/
`_RepaintPalette`/the sentinel park across 3 modes × weave on/off × both palettes — the exact
shape the K4B header says the client threw on.

## (2) API results reaching tostring/arithmetic/comparison raw — CLEAN inside the diff

| API | diff site | verdict |
|---|---|---|
| `InCombatLockdown` | `Forte_Cooldown/Module.lua:814-816`, `Procs.lua:141-145`, `TestMode.lua:187-191`, `Swing.lua:1975-1977`, `Melee.lua:219-229` | pcall + `PlainOrNil` at every site (the `_ApplyCombatAlpha` truth reading of a secret = in-combat is the conservative half) |
| `UnitName(Unmodified)` | `Database.lua:223-231` (first-name leg) | pcall → `FX.Identity.Canonical` → `type(first) == "string"` gate before the `#first`/`:sub` arithmetic; a secret/raise = nil = the leg folds nothing |
| `C_Spell.GetSpellInfo` fields | `Tools.lua:1020-1031` (`ResolveCastLength`: one pcall over lookup+field, `PlainOrNil(info.castTime)`, `type == number and > 0`), consumed at `Swing.lua:1886-1897` through a second pcall + type gate | clean; the F3 `Core/Melee.lua` fix hands the payload slot to `resolveCastName` (`Tools.lua:1003-1012`) untouched — no raw compare survives (`tests/test_melee.lua` F3 legs (a)-(c)) |
| `GetNumGroupMembers` | `Announce.lua:132-137` (`plainCount`: pcall, `tonumber(PlainOrNil(v))`), used at `:215-217` | clean — the FX7b numeric/boolean split intact |

`GetTime`/`GetRealmName`/`GetSpellInfo` results in SwingDemo/beatPlan/beat machinery are all
internal clock values. Pre-existing raw shapes: MINOR 3.

## (3) RekeyLegacy — see MAJOR 2

User-named profiles: **protected** (bound gate `Database.lua:241-253` — a key not in
`characters` and not `active` rides; the leg-2 gate at `:228-231` additionally refuses a first
name that is not this character's own strict prefix, pinned by the "Zyxnia" leg). The exposure is
exclusively the **first-name-sharing characters** case, where the legacy head uniquely names
neither: `:239` then folds a row whose ownership the packed key cannot resolve.

## (4) K2 swing demo — CLEAN (swap, ticker, synthetic rows, chat)

- Swap/restore: `Fill` captures `self._real` before `UI:SetTracker(tracker)`; `Scrub` restores
  it (`Core/SwingDemo.lua` Scrub) and re-kicks a live real cycle or returns the bar to
  `RenderIdle`. TestMode's exit contract calls every feeder's `Scrub` at each exit — hand stop,
  `PLAYER_REGEN_DISABLED` (combat), `PLAYER_LOGOUT`/`PLAYER_LEAVING_WORLD` (`TestMode.lua:225-241`
  scrubs **before** dropping the flag; `:339-344`), disable (`:364-366` + `StopPump` belt), and
  `M:OnDisable` scrubs as the module belt. A reload takes the C_Timer ticker down with the Lua
  state.
- Ticker: armed only in `Fill` (never from the enable), cancelled in `Scrub`
  (`pcall(self._ticker.Cancel, ...)`), the `Beat` callback self-scrubs when `FX.TestMode:IsActive()`
  is false — a missed Scrub leaves no beat. A raising `C_Timer.NewTicker` leaves no handle
  (p-called construction; the mode then runs on the 1 Hz pump alone — degraded, not leaked).
  `test_swing_demo.lua` pins `assertNil(Demo._ticker)` after stop and at the suite tail.
- Synthetic entries: the demo owns no row in the Cooldown engine or the Timer panel; its Live is
  the one bar. The real tracker's face is asserted bit-identical across the whole ride
  (`realFace()`; the K2 `SetTracker` seam never writes `FX.Hunter.Tools.Swing`).
- Chat: `FX.Print` appears in `SwingDemo.lua` only inside the header comment (grep) — the demo
  prints nothing; the mode's own start/stop lines are TestMode's, by design; no
  `SetMessage`/editbox writes in the file.
- Class gate: non-Hunter `Fill` returns 0 before any swap (`test_swing_demo.lua` gate leg;
  `T:Pump()` cannot arm one). The `Swing` module (and its event frame) stays the real machine —
  the demo registers no events, no OnUpdate (the hidden-frame law).

## (5) K4B palette — CLEAN (`default` byte-identical; the pick survives)

- `default = {}` names nothing (`test_swing_palette.lua` byte-identity leg enforces it);
  `applyPalette` paints the live skin as "palette value if named, else `BASE`" over the
  `PALETTE_KEYS` list, so a default pass re-copies BASE — today's values.
- The three new skin keys are **derived** (`Swing.lua:214-222`: `AimRegionColor = AimColor`,
  `ClipColor = AimColor`, `ClipInterlockAlpha = ClipRegionAlpha`), and every consumer that grew
  a key (region build/`_SetMarkerColor` `:1655`, clip/band build/`_clipA` pair `:1695-1699`)
  evaluates to the same numbers on the shipped skin — the render-pass interlock pair now reads
  `ClipInterlockColor/ClipInterlockAlpha` where it read `ClipInterlockColor/ClipRegionAlpha`,
  the same `{1,1,1,1}`/`0.22`.
- A saved/picked `BarColor` lives in `BASE.BarColor` (`SetBarColor` writes BASE, then
  `applyPalette(ST.swingPalette)`): under `colourblind` the palette's olive paints over it,
  back on `default` the pick is restored; `Init`'s spell-tint leg writes BASE+skin too
  (`:542-549`). Store round trip and the login seam both pin the pixels. `S.BgColor`/
  `ReminderColor` are outside `PALETTE_KEYS`, so the palette cannot eat them, and the two
  palettes' names for every drawn signal are covered by the every-signal leg. `Melee:SetBarColor`
  validates (`type` checks), copies (fresh table), key-caches — the shared `S.BarColor` table
  reference is never aliased into the rail. Rail/picker push asymmetry: MINOR 5.

## (6) OnUpdate / top-level RegisterEvent / FX:CallSafe / pinned API — CLEAN

- `python3 scripts/api_lint.py` → `[api-lint] 63 files, catalog 4378 C_ symbols / 966 enums /
  1816 events: OK` (run on HEAD, 2026-11-04).
- No `FX:CallSafe` anywhere (the pattern appears only as the Locale.lua:342 comment of its
  absence; every new callback — ticker `Beat`, `ResolveCast*` closures, the demo's feeder pair,
  the palette repaints — rides an explicit `pcall`).
- No top-level `RegisterEvent`: the full census (31 files) shows every call inside a function —
  `Init.lua:230-232` is the sanctioned bootstrap frame; `TestMode.lua:354-358` (OnEnable),
  `Locale.lua:394-395` (inside `WatchItemLoads`), all module `EnableEvents`/`OnEnable` bodies.
  K3's removal of the dispatcher-less `LocaleModule.OnEvents` is verified dead (no dispatcher
  exists; `test_login_order.lua` census now pins zero hooks tree-wide).
- No new OnUpdate: the demo drives a `C_Timer.NewTicker(0.2)`; the bar's OnUpdate keeps the
  shown-only law. The K2 Target pump: `TestMode.lua` `targetOf` falls back to the classic 1 for
  feeders without a Target (the swing feeder declares none), and both Target feeders' Fills are
  idempotent per live row (`Forte_Cooldown/Module.lua` `demoFill`: `Engine.entries[name] == nil`
  gate; `Forte_Timer/Module.lua` `demoFill`: `live[name]`/`Rows:Find(name, "none")` gate) —
  verified against the running rows not being re-anchored (the K2 legs).

## (7) English-name assumptions vs a localized client — CLEAN in the diff

- `CLIP_SHOT_NAMES` (`Aimed/Multi/Steady Shot`) compares against the **generated data** key
  space (English by the AGENTS.md law), and the K7 leg resolves to ids through
  `Locale.RankIDsForName` (`Locale.lua:171-174`, `idsByEnglish` built from the data rows at
  `:248-251` — English-keyed on every client) plus `FX.Data.HunterByName` (`Swing.lua`
  `clipShotIDs`), then reads the client by **id** — locale-safe; the demo/test seam names ride
  the same key space.
- K8 Clearcasting: the row rides the data name; on a localized client the Registry's H1 alias
  rows (`Registry.lua:496-502`, keyed by the client's localized spell names, the alias entry
  table shared with the canonical row) make `IsTracked(aura.name)`/`InsertFromAura` hit for
  `Geistige Klarheit`-shape names — the same path the 12 signed-off H7 rows ride; the family-law
  census keys on ids (12536/16870/16246, Priest pinned absent), locale-independent.
- SwingDemo's synthetic `"Auto Shot"`/`"Aimed Shot"` strings drive only its own tracker
  (self-consistent seals); the F2 fold words (`safe/one/elapsed`) and palette words
  (`default/colourblind`) are internal store tokens; the F3 fix routes payload cast names
  through `resolveCastName` → `canonicalCastName` (`Tools.lua:1076-1080`), the Locale seam.
  No English spell-name literal is compared against a client-returned name anywhere the diff
  touches.

---

## Open questions

1. **MAJOR 1 lands on the launch build** (fresh-profile default). Fix + fail-first leg before
   tonight, or register `BarMode` default as `"elapsed"` deliberately (not intended per §7.1
   and the K5 clip).
2. MAJOR 2: does the pre-release install base plausibly contain first-name-sibling accounts
   (realm transfers)? The conservative sibling-scan gate costs one `pairs` walk and makes the
   leg strictly safer than not having it.
3. MINOR 5: is the rail intended to follow the live picker (one push site) — the K4B tip text
   ("Every signal ... moves together") argues yes.

## Counts

MAJOR: 2 · MINOR: 3 · INFO: 2 · **total: 7**. Priorities (1), (4), (5), (6), (7): clean (the
(5) push asymmetry and the (1) census record live as MINOR 5 and the INFO note); priority (2):
clean inside the diff, three pre-existing raw shapes at MINOR 3; priority (3): MAJOR 2.
