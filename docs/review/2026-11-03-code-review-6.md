# Code review 6 — waves 4–6 (`6092e17..HEAD`)

Scope: `git -C wow-fortexorcist log --stat a2fdaf5..HEAD -- addon tools scripts` —
`ccc349a` wave 6 (right-click-to-options on every module frame, bar font/texture
pickers, Cooldown IconSize + TextColor rows), `b87bd58` `uif_battery` DB row
follows `DB.SCHEMA_VERSION`, `0a711da` wave 5 (sparse settings store + schema v2
prune, Advanced Options page, review-5 minors). Gate at HEAD: PASS 707 (as
recorded in PLAN §11.1; not re-run here — read-only review, no sim/gate run).

Every finding below quotes a line from a file this reviewer opened. The
right-click law's source law was re-read in the original (`/tmp/fxref/Forte_Core/Options.lua:649-662`,
`/tmp/fxref/Forte_Soulstone/Forte_Soulstone.xml:189-196`), the mouse/strata
payloads in the pinned catalog (`docs/api/wow-addon-api-agents/skills/wow-api-widget/references/SCRIPT-HANDLERS.md:162-164,224-225`,
`docs/api/audit/api-coverage.json:24838`), and the reference implementation's
drag convention in the installed CooldownMaster (MIT).

## Answer

**No blockers.** Every event touch in this window is payload-clean: the window
adds **zero** new client-event registrations (the Probe change is a lint-visible
re-spelling of the existing capture set), the `UNIT_AURA` handoff is now slot-named
before the call, the `InCombatLockdown` sample rides pcall + `PlainOrNil` through
the real frame with the catalog's 4-slot `UNIT_SPELLCAST_SUCCEEDED`, and the new
frame scripts (`OnMouseUp`, `OnDragStart`, `OnDragStop`, `OnMouseWheel`) read the
catalog's slots. The settings store's five laws all hold in isolation (Set-to-default
deletes, Get never writes, v2 idempotent + LoD-lazy, copy/reset/delete, colour
deep-equality) and the page-build census test enforces them.

**4 majors, 5 minors.** All four majors are real-client-only — exactly the class
the sim cannot see: (M1) `P.ApplyLive`'s `v ~= nil and v or deepCopy(d)` idiom
loses a stored `false` whenever the default is `true`, so the first profile switch
re-locks every bar a player unlocked **and deletes the stored `false`**; (M2) the
press stamp rides only the LeftButton drag-start, so on the live client the
right-click seam is dead on every frame from the first left-press on — the suites
mask it by stamping manually; (M3) the Splash got no seam at all while the wave-6
commit message claims it; (M4) the Advanced page's Hunter strata row has no live
listener and its test short-circuits on a non-Hunter gate profile. None of the
four is reachable by the shipped defaults on day one; all four should land before
launch — M1 is the one that eats user data.

---

# Findings

## Blockers

None.

## Major

**M1 — `P.ApplyLive` erases every stored `false` whose default is `true`
(`addon/Forte_Options/Core/Settings.lua:522-525`).**

```lua
        for key, d in pairs(defaults[module]) do
            local v = t[key]
            S:Set(module, key, v ~= nil and v or deepCopy(d))
        end
```

For `v = false`, `v ~= nil and v` evaluates to `false`, and `false or deepCopy(d)`
yields the **default** — the stored value is never reached. Every `Lock` key ships
`true` (`GlobalLock = true` at `addon/Forte_Options/Pages/General.lua:70`; the bar,
the splash, the swing and the Warlock plates all ship locked), so a player who
unlocks a frame stores `Lock = false` — the single non-default the sparse store is
built to carry. The next `P.Select`/`SetPerCharacter`/active-profile `P.Delete`
(every caller of `ApplyLive`, `Settings.lua:519`, :570, :587, :614) pushes
`true` through `Set`: every frame re-locks live, and because `true` equals the
default the `Set` **deletes the stored `false`** (`:447-448`) — the choice is gone
from SavedVariables. Same for a stored `RightClickOptions = false`,
`ShowStartupText = false`, every boolean default-true key.
The suites cannot catch this: every switch test moves the *numeric* `Width`
(`addon/Forte_Options/tests/test_profiles.lua:301-402` — 340/180/396, all truthy).
**Fix:**

```lua
            local v = t[key]
            S:Set(module, key, v ~= nil and v ~= false and v or (v == false and false or deepCopy(d)))
```

— clearer as an explicit branch: `if v == nil then v = deepCopy(d) end; S:Set(module, key, v)`.
Then a test that stores `Settings:Set("General", "GlobalLock", false)`, switches
`P.Select(shared)` → `P.Select(base)`, and asserts `S:Get("General","GlobalLock") == false`,
the stored key survives in `settingsOf(base)`, and the bar frames follow `false`.
Grep the file's other `and … or` trios for the same shape (none of the reviewed
`Lock` publishes take a raw stored `false` through the idiom — `ApplyLive` is the
site).

**M2 — the press stamp rides only the LeftButton drag start; the right-button
press stamps nothing, so after the first left-press the right-click seam is dead
(`Timeline.lua:625-637`, `Forte_Hunter/UI/Swing.lua:229-243`,
`Forte_Timer/UI/Rows.lua:143-157`, `Forte_Warlock/UI/Frame.lua:561-567`).**

The shipped seam:

```lua
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(fr, button)
        …
        self:_StampPress()
        if self.cfg.locked then return end
        fr.StartMoving(fr, button)
    end)
```

`_StampPress` exists **only** inside `OnDragStart` (grep of the five seam files:
`Timeline.lua:634`, `Swing.lua:240`, `Rows.lua:154`, `Frame.lua:565`, `Splash.lua`
has none; no `SetScript("OnMouseUp"`-file installs an `OnMouseDown`). The catalog
registers drags per button (`RegisterForDrag(buttons: MouseButton)`,
`docs/api/audit/api-coverage.json:24838`; `OnDragStart(self, button)` requires the
registration, `SCRIPT-HANDLERS.md:224`), so a **right-button press fires no
`OnDragStart`** and the stamp is never refreshed for it. Sequence on the live
client: unlock the bar → left-press (stamp lands at cursor A) → drag → release at
B; later right-click the bar at C: `Moved()` (`Timeline.lua:1331-1338`) compares C
to the **stale stamp A** → true → the release is dropped. Every later right-click
is swallowed unless the cursor happens to sit on the old stamp pixel. The
shipped-locked bar is clean only because nothing stamps while locked (nil stamp →
`Moved()` false — `test_timeline.lua:1894` even pins `assertNotNil(Display._downX,
"the press stamps, lock or not")`, i.e. the stamp becomes live the moment the
player touches the drag path).

The source stamps **every press**: `FW:StartMoving` (the original,
`/tmp/fxref/Forte_Core/Options.lua:649-656`) begins `cx,cy = GetCursorPosition();`
before the lock check, and is wired as `<OnMouseDown>FW:StartMoving(self,button)`
(`/tmp/fxref/Forte_Soulstone/Forte_Soulstone.xml:189-191`); the installed reference
addon does the same (`CooldownMaster/UI/Bars.lua:368-375` stamps in
`OnMouseDown`). The suites mask the gap by stamping by hand before every release
(`test_timeline.lua:1827,1837,1882`; `test_swing_rightclick.lua:46,55`;
`test_rows_rightclick.lua:50,60`; `test_warlock_rightclick.lua:95`) — the tests
prove the `Moved()` function, not the stamp's wiring, and every suite ends by
nil-ing `_downX/_downY` (e.g. `test_timeline.lua:1852`), which is the author
knowing the stamp lingers.
**Fix:** install the stamp on every press on each seam frame (and on the Warlock
anchor + tip + drag frame), CooldownMaster's shape:

```lua
    f:SetScript("OnMouseDown", function() self:_StampPress() end)
```

keep the `OnDragStart` stamp (the sim rigs call that script, not the press
script), and add one test per frame that never touches `_StampPress` directly:
fire the press script, move the fake cursor, release (left, inert), move, fire the
press script again, release `RightButton` → opens. Also read the catalog's third
`OnMouseUp` slot while in there (m2).

**M3 — the Secondary Splash has no right-click seam, contradicting the wave-6
commit message** (`ccc349a`: “right-click-to-options on every module frame
(Spell Timer, Hunter swing, each Warlock plate, cooldown bar **+ splash**)”).
`addon/Forte_Cooldown/UI/Splash.lua` carries no `OnMouseUp`, `_StampPress`,
`Moved` or `RightClickOptions` (grep: no match in the file), while its `SetLocked`
adopted the new law — `Splash.lua:258 self.anchor:EnableMouse(true)` — so the
window's right release now fires into no handler. The frame is a module frame with
its own page (`pagesBuilt` id `Splash`) and is mouse-live by the new law, so the
gap is user-visible. The PLAN wave-6 contract (`PLAN.md` §11.1 wave 6, RightClick
row) owns `Forte_Timer/UI/Rows.lua`, `Forte_Hunter/UI/Swing.lua`,
`Forte_Warlock/UI/Frame.lua` — the Splash file is the Cosmetics slice's, so the
slice boundary explains the miss; the message overclaims.
**Fix:** port the `Timeline` trio to `Splash.lua` (`OnMouseUp` →
`pcall(O.Open, O, "Splash")`), stamped per M2's shape, with the three tests
(`test_splash.lua` rides the same rig as `test_timeline.lua:1820-1909`), or
strike the splash claim from the record and open it in a follow-up wave.

**M4 — the Advanced page's Hunter strata row has no live consumer: the swing bar
registers no `OnChange("Advanced")` listener, and the row's test short-circuits
on a non-Hunter gate run (`Forte_Hunter/UI/Swing.lua:915-932`;
`Forte_Options/tests/test_advanced.lua:194-202`).**

`Swing.lua` wires three modules:

```lua
    st:OnChange("Hunter", function(key, value)
    st:OnChange("Cooldown", function(key, value)
    st:OnChange("General", function(key, value)
```

Every other strata frame wires the shared module — `Timeline.lua:1532`,
`Splash.lua:673`, `Forte_Timer/Module.lua:303`, `Forte_Warlock/UI/Frame.lua:1340` —
the Hunter is the one that does not. `KEYMAP.HunterStrata = "SetStrata"`
(`Swing.lua:868`) rides login (`STORED.Advanced`, `:882`, via
`ApplyStoredSettings:895`), so typing `HIGH` into the row moves the store, fires
zero listeners on the bar, and the tip promises “Applied live”
(`Pages/Advanced.lua` `STRATA_TIP`). The test
(`test_advanced.lua:194-197`):

```lua
test("HunterStrata drives the swing bar's SetFrameStrata", function()
    local SW = FX.Hunter and FX.Hunter.Swing
    assertNotNil(SW and SW.SetStrata, "the bar has the seam")
    if not SW.anchor then
```

returns on the gate's (non-Hunter) profile before ever running
`strataDrives("HunterStrata", …)` — the gate passed at 707 with the leg dark.
**Fix:** add to `_WireSettings` the one-liner the siblings carry,

```lua
    st:OnChange("Advanced", function(key, value)
        self:ApplySettings({ [key] = value })
    end)
```

and make the test build the frame before driving
(`ensureBuilt()`/`Swing:Init()` as `test_swing_rightclick.lua:29-34` does) so the
Hunter leg runs on every profile where the frame is buildable.

## Minor

- **m1 — `FX.db.optionsExpanded` is the window's one unvalidated DB row: a scalar
  at the per-page slot raises inside the page build (`Forte_Options/UI/Window.lua:102-105,116-119,125-126`).**
  `StartCollapsed` does `local per = expandMemory()[pageId]; local v = per and per[title]`
  and `RememberCollapse` does `per[title] = …` — with `db.optionsExpanded =
  { Cooldown = 5 }` (hand-edited/legacy file) indexing the number raises and the
  page build dies. The tree's own law for every other DB row is shape-before-read
  (`Core/Database.lua` `Guard` header: “no reader can crash on shape”). Fix:
  `if type(per) ~= "table" then per = nil end` in `StartCollapsed` and a
  type-gated recreate in `RememberCollapse`.
- **m2 — `OnMouseUp` ignores the catalog's third slot `upInside`**
  (`SCRIPT-HANDLERS.md:163`: “`OnMouseUp(self, button, upInside)` … `upInside` is
  true if the cursor is still over the widget”). The seam handlers read slots 1–2
  only (`Timeline.lua:1347-1349`, `Swing.lua:415-417`, `Rows.lua:295-297`,
  `Frame.lua:625-627`), so on a never-stamped (locked) frame a press inside + a
  release far outside opens the window. Fold into M2's fix:
  `function(_, button, upInside) self:OnMouseUp(button, upInside) end`, drop a
  release whose `upInside == false`.
- **m3 — `O:Close()` does not stop the wheel animation
  (`Forte_Options/UI/Window.lua:990-993`).** `StopScrollAnim` is called from
  `SetPage` (`:757`) but not from `Close`; closing mid-ride leaves the driver
  script ticking on the hidden window until the target is reached (bounded,
  self-retiring per `StepScrollAnim:924`, so minor) — the hidden-frame-carries-no-ticker
  law this tree tests for the splash (`test_splash.lua:110-111`). One line:
  `self:StopScrollAnim()` in `Close`.
- **m4 — `P.Delete` leaves the deleted profile's key in `checked`
  (`Forte_Options/Core/Settings.lua:552-571`, the map declared at `:88`).** Re-create
  a same-named profile (`Create:544` copies the sanitized active profile, so the
  content is clean) and the new profile is never key-sanity-checked this session.
  Add `checked[name] = nil` beside `r.byName[name] = nil`.
- **m5 — the strata tests prove the seam against a stub, not the client method
  (`Forte_Options/tests/test_advanced.lua:160-161`).**
  `frame.SetFrameStrata = function(_, name) rec[#rec + 1] = name end` replaces the
  catalog method; every production call is presence-guarded (`if self.anchor.SetFrameStrata`,
  e.g. `Timeline.lua:1213`), so if the sim's frame lacks the method the suite is
  silent on the real leg. Add a presence assertion (`assertNotNil(D.anchor.SetFrameStrata,
  "the client frame carries SetFrameStrata")`, the `IsMouseEnabled`-probe
  convention at `test_splash.lua:356`) and a launch-day strata row in
  `docs/launch-day.md`.

---

## What was checked and found clean

**1. Event payloads (every registration/handler touch in the window).** Zero new
client-event registrations: the whole-range diff's only new `Register*Event`
literals are the re-spelled `CAPTURE_EVENTS` table (`Core/Probe.lua` diff hunk,
`CAPTURE_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_SWING",
"PLAYER_SWING_RANGE_UPDATE", "ADDON_RESTRICTION_STATE_CHANGED" }`), whose lines
match `scripts/api_lint.py:18`'s `EVENT_LIST` list-shape scan (verified against the
regex at `api_lint.py:69`) — the review-5 m6 fix works. The capture handler
classifies slots (unchanged). The `UNIT_AURA` handoff now aliases the cast-family
slot names before the call (`Forte_Cooldown/Module.lua` diff: `local unitTarget,
updateInfo = unit, castGUID` → `Engine.Procs:OnUnitAura(unitTarget, updateInfo)`)
— slots 1–2 per the catalog. The `InCombatLockdown` sample is pcall'd,
`PlainOrNil`-gated, no-answer=out-of-combat, and the new `test_reconcile.lua`
test drives it through the real frame with the catalog's 4-slot
`(unitTarget, castGUID, spellID, castBarID)` (`"player", "G:fxtest-raise", BOGUS, 1`).
`Locale.OnDisable` guards both unregistrations (`if frame and frame.UnregisterEvent
then pcall(...)` — the m7 fix). New scripts: `OnMouseUp(self, button, upInside)`
slots read correctly (m2 for the ignored 3rd), `OnDragStart(self, button)`
(`SCRIPT-HANDLERS.md:224`), `OnDragStop(self)`, `OnMouseWheel(self, delta)`. No
event-name string surgery in the window.

**2. The sparse store.** `Set`-to-default deletes via `deepEqual`
(`Settings.lua:447-448`); the key-set-count walk of `deepEqual` (`:103-114`) was
worked by hand for subset/superset/equal colour tables (±counts reject, equal
accepts) — colour rows ride it correctly. `Get` fills from `deepCopy(d)` and
stores nothing (`:429-436`); `store()` never seeds (`:353-360`); the sole
Get-hands-the-live-table case (a stored value) has no mutating consumer (every
reader indexes `c[1..4]`). `Reset` is delete-through-`Set` with the listeners
firing (the notify-then-delete contract tested at `test_profiles.lua` and
`test_options.lua`'s sparse test). v2 (`Core/Database.lua` `MIGRATIONS[2]`) is
idempotent by marker and by content — the `test_database.lua` v2 leg proves
user-values survive, frozen defaults go over every profile, and a retried login
of a stamped install drops nothing; the LoD hand-off (`S:Register`'s
`FX.db.defaultsPruned` hook, `Settings.lua:400-406`) is tested by the `LateProbe`
profile. Copy is the sparse copy (`:544`, “not a live alias” +
`countKeys == 1` assertions); delete refuses the last profile, re-binds every
character and moves the session with `ApplyLive`; select/share/bind round-trip
through `ApplyLive` alone (the M1 idiom excepted). The page-build census
(“building every options page + a /reload-equivalent pass leaves no
default-valued keys”) enforces the whole law on the real store. No path in the
window writes defaults: the m4 lock publishes push the live bool through `Set`
(default-equal → delete), the widget/recycle/section-reset paths all ride
`GetDefault → Set`.

**3. Every wave 4–6 option's consumer (key → consumer:line).**
`Advanced.ShowStartupText` → `Core/Init.lua:154-163` (`FX.PrintStartupLine`, called
from the `PLAYER_LOGIN` branch); `Advanced.AnimateScroll` →
`UI/Window.lua:892-941` (`AnimateScrollOn`/`Scroll`/`StepScrollAnim`, driver retires);
`Advanced.ExpandSubcats`/`LoadExpandSubcats` → `Window.lua:114-131`
(`RememberCollapse`/`StartCollapsed`, fold-on-build disclosed in the tip);
`Advanced.CooldownStrata` → `Timeline.lua:1457 → SetStrata :1209`;
`SplashStrata` → `Splash.lua` `KEYMAP` `SplashStrata = "SetStrata"`;
`TimerStrata` → `Forte_Timer/Module.lua` `ADVANCED_KEYMAP = { TimerStrata =
"SetStrata" }` → `UI/Rows.lua SetStrata`; `HunterStrata` → **login-only, M4**;
`Shard/Soulstone/Healthstone/SummonStrata` → `Forte_Warlock/UI/Frame.lua:1339-1346`
(one listener per plate, `advancedKey` in the four plate tables);
`General.RightClickOptions` → the four `OnMouseUp` gates (M2/M3/M4 scope);
`Cooldown.IconSize`/`IconSizeOn` → `Timeline.lua:1428-1429 → SetIconSize :973 /
SetIconSizeOn :979 → _ResizeIconPools` (icons grow in place; tags/curve ride
Height, source `ih` law); `Cooldown.TextColor` → `:1430 → SetTextColor :955` (the
tag strings); the SEL pickers write `General.BarFont`/`BarTexture` consumed at
`Timeline.lua:1453-1454` (`SetBarFont :1148`, `SetBarTexture :1137`),
`Swing.lua:852`, `Forte_Warlock/UI/Frame.lua:167`; `General.FrameSnap`/`ShowTooltips`
stay stored-only with honest tips and the inertness pin
(`test_timeline.lua:1243-1254`). The dropped Advanced rows (FrameSnap distances,
Core intervals, columns, global frame names, linking, `REMOVE_BACKUP`) are listed
with the reason in `Pages/Advanced.lua`'s header.

**4. The right-click/lock law.** Lock = `SetMovable(not locked)` + the mouse kept:
`Timeline.lua:750-751`, `Swing.lua:384-385` (`self.anchor:EnableMouse(true)`),
`Rows.lua:263-264`, `Splash.lua:257-258`; the Warlock anchor is gated by the
user's `enableMouse` only (`Frame.lua ApplyMouse:1191`) and the lock gates the
drag *registration* (`:1196-1197`, `EnableMove:578`). The right-click gate is
`== false` on all four seams (default-true honoured), the `Moved` guard drops
drag-releases, the lock leg asserts “a locked bar never starts moving” + “the
press stamp is taken before the lock is read” (`test_swing_rightclick.lua:76-110`,
`test_rows_rightclick.lua:81-112`, `test_timeline.lua:1855-1909`), the locked
seam opens through the real `OnMouseUp` script, and drags are pinned: the locked
frame's geometry does not move, the unlocked `OnDragStart` reaches `StartMoving`
exactly once. (The stamp's live-client reachability is M2.)

**5. Real-client hazards.** No `SendChatMessage`/`SendAddonMessage`/
`RegisterAddonMessagePrefix`/`PlaySound` line was added anywhere in the window
(diff grep: the only `PlaySound` touch is the Timeline comment routing the
source's panel-click sound to Forte_Options' widgets). Login noise: the startup
line is a chat print, gated, default-visible, returns its gate for the test. The
scroll driver installs `OnUpdate` only from a user wheel on the shown window and
nils the slot at the target (`Window.lua:902-928`, `test_advanced.lua` asserts
the retirement); no chunk-scope `CreateFrame`/`RegisterEvent` in the window. The
SEL picker: popup at `TOOLTIP` strata (the original's `NewDropdown` law), parented
under the window root (`popupRoot` walks to the UIParent child) so a window hide
hides it; one popup open at a time; item click is the single `FX.Settings:Set`
write; off-list values print the basename; the popup tests drive the real
widget's scripts (`test_options.lua` picker legs). Strata values: validated at
every consumer (`strataOrNil` type-gated, outside-the-eight kept-as-typed-and-ignored
per the tip). The eight names match the catalog (`XML-FRAME-TYPES.md:44`).
`test_warlock_ui.lua` flips the click-through expectations to the new law and adds
the drag-frame-is-the-locked-one assertion. `scripts/uif_battery.js` DB row now
compares `version == DB.SCHEMA_VERSION` (no stale pinned `1`).

**6. Test shapes.** The strata tests drive the **real store** (`S:Set("Advanced",
key, …)` + recycle) with a recorder on the frame method (m5 for the method-presence
leg); the right-click tests drive the real `OnMouseUp`/`OnDragStart` scripts with
the catalog's `(frame, button)` payloads (M2 for the stamp wiring); the picker
tests drive the real popup rows' `OnClick` and assert the live frame moved;
`test_reconcile` is a real-frame payload test; `test_profiles`/`test_database`
drive the real store/DB with a raw-table census. Remaining direct-method-only
spots are the seam's own stamps (`_StampPress` calls, M2) — the class the suite
must close before launch.

---

## Open questions (launch-day, not code)

1. Does the live client fire `OnDragStart` for a `SetMovable(false)` frame's
   registered button (M2's locked-bar sub-case: stamp set → later right-click
   swallowed, vs. no stamp → the release-outside hole of m2)? Probe on one frame.
2. `RegisterForDrag(true)` (the Warlock drag frame, `Frame.lua:560,578`) passes a
   boolean where the catalog types `MouseButton` strings — pre-existing, untouched
   here, and the right-click law now rides it. Verify a right-press on the plate
   delivers `OnMouseUp` to the frame the engine picks on the real client.
3. M5-class strata presence on real frames (m5) — one `/fx probe` row: set
   `SoulstoneStrata = "HIGH"` live, watch the plate ride it over a Blizzard dialog.
