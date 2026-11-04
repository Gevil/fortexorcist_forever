# Launch day runbook — 2026-11-04 (WoW Forever launch)

One addon session that answers every open live question from
`docs/research/secrets-unknowns.md` (Q1–Q10) and `docs/design-combat-procs.md` §5.
The collector is `/fx probe` (`addon/Forte_Core/Core/Probe.lua`): every probe
group runs in its own `pcall`, every API value passes the `Probe.K` classifier
(`SECRET` / `type:rendering`), runs are stored in `ForteXorcistDB` →
`FX.db.probes` (last 20), so the artefacts survive the session.

**Do not rush.** The value is the two runs *out of combat* vs *in combat* and
the relog persistence proof — same probe code, different restriction state.

## Step list (exact order)

1. **Deploy (copy mode) and verify the install.** `scripts/deploy.sh --copy
   --verify` from the repo root. `--copy` (not symlink) because third-party
   tools below edit `.toc` files in place and symlinks would write into the
   git tree. `--verify` then compares every installed `Forte_*` file against
   the repo's shipped set and reports `MISSING`/`EXTRA`/`DIFFERENT` per path
   (plus an `SVFIX` line for a file the SavedVariables fixup has patched,
   which is expected, not an error) — the deployer exits 1 on a real diff.
   Re-run `--verify` (read-only, `scripts/deploy.sh --verify`) after any
   third-party tool touches the tree, and rehearse the whole install in a
   scratch directory first with `--target /tmp/fxdeploytest` (never against
   the live client) if the step is unfamiliar.
2. **ForeverSVFix: uninstall if installed.** (If it edits our `.toc` in place,
   the SavedVariables evidence below is contaminated.) Launch, log in on the
   **Hunter**.
3. `/fx status` — every Forte module listed, `Probe: epoch=1 runs=0` line
   present, class=HUNTER, build line sane.
4. `/fx probe` — the **out-of-combat baseline run** (label `ooc` auto).
   Read the printed lines (guide below); all 20+ lines also print, the run
   itself is stored. The run **also opens in a copy window**: click in its
   text (the click selects the whole run), `Ctrl-C`, and paste it into your
   launch-day notes; the `X` button closes it, and so does `Esc`. Do this for
   every run in this list — the pasted blocks are the launch-day artefacts,
   chat scrollback is not. (`/fx probe show` reprints the last run and
   reopens the window.)
5. **In combat:** attack a training dummy and keep it attacking you (real
   combat lockdown, not stealthed, not solo-cast-only). Cast **3 tracked
   cooldowns** (e.g. Rapid Fire, Disengage, One Beast's Charge — the cast
   counter needs the events). While still in combat: `/fx probe` (label
   `combat` auto). This run is *the* launch-day artefact.
6. **Bar probe, in combat:** `/fx probe bar` — a green StatusBar + Cooldown
   frame appear, driven by a duration object WE built
   (`SetTimeFromStart(GetTime(), 10, 1)` — 10 **seconds**). **Watch for 10 s:**
   does the bar animate (fill/decline) and the cooldown swipe rotate while in
   combat? `/fx probe bar off` when done.
7. **Leave combat, run dry:** `/fx probe` (label `ooc` again — the
   restriction-state pair to step 5).
8. `/reload` then `/fx status` — position/`/fx` window placement and the
   learned-durations store must persist across a reload; probeEpoch must be
   **unchanged** by `/reload` (it is a PLAYER_LOGIN counter).
9. **Full log out** (quit to desktop, not /reload), **log back in**,
   `/fx probe` — the EPOCH line must show probeEpoch **+1** vs step 7's run
   (the runs stored at steps 4–7 must still be in `FX.db.probes`: the
   SavedVariables round-trip proof).
10. Exit the game. Send the SavedVariables file:
    `WTF/Account/<ACCOUNT>/SavedVariables/Forte_Core.lua` — the toc's
    `## SavedVariables: ForteXorcistDB` writes the per-addon file
    `Forte_Core.lua` (research Q10 file layout). It carries every probe run
    (`probes`), the event-capture rings (`probesEvents`) and `probeEpoch`.
    (If the folder shows a differently-named file containing
    `ForteXorcistDB`, send that one — note which.)

## Pre-flight, browser only: the uiforever battery (~5 min)

`scripts/uif_battery.js` is one async function for the browser kernel that
already has an open uiforever.com tab — it needs the kernel's `uifTab`,
`clickText(text)` and `lua(cmd, waitMs)`. Call
`await uifBattery({ zip: 'dist/ForteXorcist-<version>.zip', fresh: true })`
and it clears the previous import, uploads the zip, waits (polling up to
15 s) for the `Import addons?` dialog and clicks **that dialog's** Import
button, waits for the dialog to close, then presses `/reload` and returns
a pass/fail table. The dialog gate matters: on a larger zip it lands
seconds after the upload, and the 2026-11-02 battery raced it — every
check then passed against the PREVIOUS import's code (false PASS). No
dialog within 15 s = the IMPORT rows FAIL. The CODE row proves the site
runs the bytes just imported: it evaluates a Lua marker expression and
passes only when it prints true (by default the `ForteXorcist.CONST.VERSION`
build constant; pass `expectMarker` to assert a newer build's symbol, e.g.
`ForteXorcist.Hunter and ForteXorcist.Hunter.Tools and
ForteXorcist.Hunter.Tools.Swing.CycleState ~= nil`). A `fresh` clear that
removed 0 rows while Forte rows stood in the add-on list FAILS instead of
passing. The rest: only the player's own class add-on resident (a resident
Mage add-on from the site's own log-in is tolerated), the module list
printed, Splash + Messages present, a ready pop sending **0** party/raid
chat lines on the shipped defaults, and the site's Errors tab free of Lua
errors (it prints the table too). These are the
chat-defaults and F12 checks in browser form; the client session below stays
the real gate. Build the zip with `python3 scripts/release.py` first, so the
imported bytes are the release bytes.

## Feature smoke checks (same session, after step 9; ~10 minutes)

Each line is something only the real client can prove. Note PASS/FAIL and anything odd;
a screenshot of anything that looks wrong is worth more than a description.

| # | Do | Expect |
|---|---|---|
| F1 | `/fx options` | window opens; the **close X** and the profile tab glyphs render (the sim draws them at 0×0, unverified); ESC closes it |
| F2 | Cast Rapid Fire (or any long cooldown) | its icon appears on the right of the cooldown bar with a white 4× splash that fades over ~1 s, then slides left along the bar |
| F3 | Wait for a short cooldown (Arcane Shot / Multi-Shot) to finish | the icon reaches the left end and **pulses** once (this pulse never fired live before the 11-02 fix); **no chat line** — the pop prints nothing by design (E1, 11-02), the ready chat line only appears if the Self Messages page's "Chat line" (`ReadyChat`) is ticked, and it is off by default |
| F4 | Start Auto Shot on a hostile target, stand still, then move during a shot | the swing bar appears: **orange** fill drains while reloading, a **red** slice at the end is the stand-still aim window, after each shot the whole bar turns **white** (safe to move/cast) until the next reload; cast Aimed Shot mid-cycle → a cast slice + countdown; moving during the red slice delays the shot (watch the bar); `/fx status` shows the Hunter line. Report any state that never appears — the aim/cast states depend on `UNIT_SPELLCAST_SENT/START` reaching addons, which only the live client can prove |
| F5 | Drop your aspect, out of combat | the aspect reminder icon pulses; cast an aspect → it hides |
| F6 | Cast Serpent Sting / Hunter's Mark on a target, then on a second target | Spell Timer rows appear grouped under each target's name, coloured by kind, timer text counting down; out of combat the rows correct themselves to the real aura times |
| F7 | Use an on-use trinket and drink a potion | both appear on the cooldown bar (item = yellow, potion = green) |
| F8 | Apply a weapon oil/poison (if your class has one) | it appears as a Buff-coloured entry parked at the right end until under 5 min |
| F9 | `/fx unlock`, drag the cooldown bar, the timer panel and the swing bar; `/fx lock`; `/reload` | all three stay where you put them |
| F10 | (Warlock alt, if you have one) log in | four purple plates: shards `x<n>  <n> total`, soulstone `x0  no ss up`, healthstone, summon; cast Create Soulstone/Soulstone on someone → the soulstone plate shows the target and a timer |
| F11 | Any Lua error popup at all | screenshot it; `/fx status` output too |
| F12 | `/run local L={} for _,c in ipairs({"Druid","Hunter","Mage","Paladin","Priest","Rogue","Shaman","Warlock","Warrior"}) do if C_AddOns.IsAddOnLoaded("Forte_"..c) then L[#L+1]=c end end print(table.concat(L,","))` | prints **only your class** (load-on-demand class data; every other class's data must not be loaded) |
| F13 | `/fx options` → Secondary Splash → tick Enable; let a cooldown finish | a large copy of its icon pops near screen centre, grows to ~2× and fades out within 1 s (`/fx unlock` shows a draggable placeholder) |
| F14 | Try to cast a spell that is on cooldown (with Cooldown → Warn on) | that icon on the bar flashes and comes to the front |
| F15 | Right-click the cooldown bar (don't drag) | the options window opens on the Cooldown page; a drag-and-release does **not** open it |
| F16 | (Warlock) Banish a demon/elemental; (Mage) Polymorph; (Rogue) Sap | ~3 s before it ends you hear the bell twice (ShaysBell); if it breaks early you hear the break sound. **No party chat** unless you ticked it on the Party/Raid Messages page |
| F17 | (Hunter) `/fx options` → Hunter Tools → tick **Enable range / dead-zone light**, stand at ~20 yd on the dummy and start Auto Shot; walk past 35 yd; then untick it | the strip shows MELEE/DEAD/8-35/35+/OUT as you move. **This option switches a CLIENT-wide feature on: `C_SwingTimer.EnableRangeCheck(Ranged, true)`** (`addon/Forte_Hunter/UI/Range.lua`), so while the light is on the game itself starts range-checking the ranged swing. Expected: Auto Shot keeps cycling inside 35 yd, the strip reads OUT beyond it, and the client's own swing behaviour is unchanged from what you see with the light off (no new "out of range" ability flashes, no swing stall). Untick → the strip hides and the check is switched back off: the swing cycle goes back to the plain behaviour and nothing else in the UI keeps range-checking. Report any swing-range change that OUTLIVES the untick — that would mean the pair is not closed |
| F18 | `/fx options` → Advanced → set one frame's **"Frame level (strata)"** row to `HIGH` (open a character panel/dialog to overlay it), then set `BACKGROUND`; the Hunter bar rides `HunterStrata` live (CodeReview6 M4 — the frame carries the `OnChange("Advanced")` listener since the fix; if typing the row moves nothing, say so) | the frame moves OVER the dialog at HIGH and UNDER it at BACKGROUND, immediately at the row, no `/reload` (the tip promises "Applied live"); the eight names are the client's FrameStrata set, a name outside them is ignored (the tip's words). The suite pins `SetFrameStrata`'s PRESENCE on the sim frame (m5) — this row is the ride on the REAL frames (review-6 open question 3) |
| F19 | Read the `NAME:` line of the step-4 (out-of-combat) and step-5 (in-combat) runs | Out of combat: `n1 n2 f1 f2 u1 u2` all `string:` values matching your character's real first/last name (`f1` should carry the FULL "First Last" form — the identity finding expects it) and `realm=` your realm label. In combat: **which of the seven went `SECRET`** is the answer to the in-combat identity question (docs/research/upstream-api-2026-11-03.md Open question 3) — a `SECRET` here is expected data, not a bug; a `raise=` is news |
| F20 | Read the `EVENTS:` line of any run | `n=42 ok=42 bad=- raise=-` — every event the addons register exists on the shipped client. Any name appearing in `bad=`/`raise=` is an event whose `RegisterEvent` raises on this build: note the module that registers it (the registration is pcall'd, so the module runs blind, it does not die). `ievT1/ievT2/ievT3` (the classic `UNIT_THREAT` + the catalog's two `UNIT_THREAT_*_UPDATE` events) + the `threatFn=` field of `SEC:` answer the threat-surface question (docs/research/upstream-addons-2026-11-03.md §10.3; `ievT1=false` is the catalog-expected answer for the classic name) |
| F21 | Read the `SV:` line at step 8 (post-`/reload` run) and step 9 (post-relog run) | `login=` equals the `wrote=` of the LAST run before the reload / logout — the value-level SavedVariables round-trip (EPOCH proves the counter, this proves the content). `login=nil` after a relog ⇒ the store does not round-trip — the step-9 escalation applies to the stamp too |
| F22 | (Warlock alt, in the F10 session; on the Hunter the line reads `hs=no-warlock-data`, expected) Conjure a healthstone, use it, run `/fx probe` out of combat, then in combat | `HS:` shows `cnt<id>` counts ≥ 1 for the created stone and `cd<id>=start/duration/enable` — after USING the stone, a real countdown (plain numbers, `duration` ≈ the stone's cd) means the item cooldown is READABLE, the read Blizzard's own Cooldown Manager is documented as not getting (dev-notes §2). Any `SECRET` in the combat pair = the in-combat half of the answer |
| F23 | Hunter (pet always out): run `/fx probe` out of combat and in combat on the dummy | `PET:`: `pet=true`, `slots=`>0, `slot=` the first pet-bar-1 action id, `has=true`, `spell=` a spellID, `cd=` the cooldown record (`en/st/dur/rate`). Numbers plain in the combat run ⇒ pet cooldowns readable on this client — the gate for ever showing pet timers (Blizzard's CDM "cannot track pet cooldowns") |
| F24 | Put a temporary weapon enchant on (a sharpening stone / weightstone works on any weapon; F8's oil if you have one): `/fx probe` out of combat, then in combat | `ENCH:` `mh=n1` with `mhe=true mh t=<ms-number> i=<enchantID>` (timeLeft is **milliseconds**), the un-enchant slots `n0`/`nil`. The number plain in the combat pair ⇒ enchant timers are readable in combat (Blizzard's CDM "cannot track item enhancements") |
| F25 | Interface → Combat → enable **Show swing timer** (the `showSwingTimer` CVar), start Auto Shot on the dummy with the Hunter swing bar on: run `/fx probe` | `BSW:` `mgr/mh/oh/rng` — `shown`/`hidden`/`absent` tells whether Blizzard's own SwingTimer frames are live on the client (dev-notes §2: they exist; post-9 fixed a dual-wield login case). With Auto Shot cycling: do Blizzard's bars appear, and do they OVERLAP the Hunter swing bar (F4) — the launch-day overlap decision |
| F26 | Hunter, Auto Shot cycling on the dummy: type `/run ForteXorcist.Hunter.Swing:SetFillEngineMode("engine")`, watch several shot cycles, then `/run ForteXorcist.Hunter.Swing:SetFillEngineMode("lua")` to go back | With `engine` the orange reload bar and the white safe-to-move bar must **fill smoothly exactly as with `lua`** (the client animates `StatusBar:SetTimerDuration`). Same look ⇒ flip the shipped default in `addon/Forte_Hunter/UI/Swing.lua` (`D._fillMode = "lua"` → `"auto"`, one word, wave I-3a). An empty or frozen bar with `engine` ⇒ keep `lua` (the simulator renders nothing from an armed duration — that is why the default is `lua` today) |
| F27 | Hunter on the dummy with Aimed Shot known, the swing bar in the default **Safe window** mode; options → Hunter Tools: tick **Weave line** and **Melee rail**. (a) Watch a few cycles: the dim red band at the LEFT is the Aimed Shot length — start Aimed Shot only while the orange reaches past it, and check the shot really goes out without delaying the next Auto Shot; (b) the thin cyan weave line — is it visible? orange past it ⇒ one 1.5 s GCD still fits; (c) walk into melee range and auto-attack: does the melee rail appear under the bar and fill once per main-hand swing, and does Raptor Strike refill it? (d) switch Bar mode to **One bar** and **Single fill** and repeat (a) — there the stripe is at the RIGHT and the fill must stay LEFT of it | (a)/(b) the markers match what the shot actually does (no clipped Auto Shot when started on the right side of the mark); (c) the rail only shows in melee range and in combat — if it never fills, main-hand `PLAYER_SWING` does not reach a Hunter on this client (the rail stays opt-in, docs/research/wst-swing-design.md §8 probe 4); (d) same reading in each mode. Untick both rows again afterwards |


## Reading the output (one line per probe group)

Header: `PROBE <label> epoch=<n> build=[<GetBuildInfo>] date=<...>`.

| Line | Question | What to look for |
|---|---|---|
| `SEC:` | Q5 | out of combat `act0..act5=false abs=false cbs=false`; in combat the same flags — **which flip true** names the restriction categories the live engine uses; `rsSeen`>0 means `ADDON_RESTRICTION_STATE_CHANGED` fired |
| `CD <spell>:` (3 spells) | Q2 | the boolean trio `en act gcd` plain in BOTH runs? `st dur rate` = `SECRET` in the combat run = the expected shape; `durObj=table secret=false rem=<number>` = the duration-object escape hatch works; `cdSec/castSec` = per-spell SecrecyLevel (0/1/2) |
| `ITEM trinket13/14, pot <name>:` | Q3, design §5.7 | any combat-run item value = `SECRET` ⇒ item reads are NOT the P-A spine (cast-predict only); all plain numbers in the combat run ⇒ P-A direct reads green-light |
| `AURA <name>:` | Q4 | `sec=` (0 NeverSecret = free in-combat aura read — today's data predicts `2` everywhere); `aura=table exp=SECRET/nil` in combat = the S8 answer (Readable? nil? raises?) |
| `CAST:` | Q1, design §5.1 | `seen plain secret unres` + `inSeen/inPlain/inSecret` — `inPlain>0` proves own-cast `spellID` is plain in combat (cast-predict spine confirmed); `inSecret>0` ⇒ the active-edge fallback is load-bearing, keep press-memory |
| `SWING:` | Q6 | `pst=table` = `Enum.PlayerSwingType` present; a captured swing (`cap`>0, `sA/sB/sC` plain numbers) = payload shape `(swingDuration, swingType)` for Phase 3 |
| `GATE:` | Q8 | `load/loaded` outcome of `C_AddOns.LoadAddOn("Blizzard_AuraContainer")` out of combat (the visual half — does a gate show a self-buff/item proc in combat — is a manual look: `CreateFrame("AuraContainer",…,"CustomAuraContainerTemplate")` is not probe-automatable since the SIM crashes on it, on the client eyeball per research §8 snippet after this run) |
| `PRES:` | Q6/Q9/surface | presence census: `isPlayerSpell=absent` on the live client would break `Compat.IsPlayerSpell` chains (the `knownInSpellBook` fallback must be a `function`); `swingType` = the `Enum.SwingType` alias question; `getInvItemID/getInvItemCD` = the legacy item globals |
| `EPOCH:` | Q10 | `epoch=` +1 after the relog; `saved=true` |
| `NAME:` | api-note Open q 1/3 | out of combat the seven fields plain strings (`f1` = the FULL name, `realm=` the connection label); in combat **which went `SECRET`** = the in-combat identity answer (`n1..u2` are the `DB.CharacterKey`/comms name surfaces) |
| `EVENTS:` | capability | `n=42 ok=42 bad=- raise=-` = every registered event exists on this client; a name in `bad`/`raise` = that module's registration raises (F20); `ievT1/2/3` (classic `UNIT_THREAT` + the two catalog `UNIT_THREAT_*_UPDATE`) + `SEC threatFn` = the threat-surface legs |
| `SV:` | Q10 (value-level) | after the relog run: `login=` == the last pre-logout run's `wrote=` (the stamp round-trips; `login=nil` ⇒ the store does not — escalate with EPOCH) |
| `HS:` | dev-notes §2 | warlock runs: per generated stone `cnt<id>`/`cd<id>=st/dur/en`; a real `dur` after using a stone = the healthstone cooldown is readable (Blizzard's CDM cannot); Hunter runs: `hs=no-warlock-data` (expected) |
| `PET:` | dev-notes §2 | `pet=true slots>0 slot=<id> spell=<id> cd=table en/st/dur/rate` — plain numbers in the combat run ⇒ pet cooldowns readable on this client |
| `ENCH:` | dev-notes §2 | `mh/oh/rng = n<k>` + per-slot `e/t/i/c` (`t`=timeLeft ms); `SECRET` in the combat pair = the in-combat answer for the Enchants bar |
| `BSW:` | dev-notes §2 | Blizzard's own swing-timer frames: `shown/hidden/absent` per frame — the input to the Hunter-bar overlap look (F25) |

## What each answer decides (map to `docs/research/secrets-unknowns.md` §
"Ranked design changes this research justifies")

| Probe result | Decision |
|---|---|
| `SEC` flags track combat/lockdown, `rsSeen`>0 | **design change 1** — ship `FX.SecretState` mode-switch on `ADDON_RESTRICTION_STATE_CHANGED` (one cached mode, PlainOrNil demotes to field guard) |
| `CD` booleans plain + numbers `SECRET` in combat | **design change 2** — boolean ready tier on icons (B2 ReadTiers): render readiness from `en/act/gcd/mx`, numbers stay cast-predict |
| `CD durObj=table secret=false rem=number` | B2's opportunistic exact-anchor reads (duration objects as widget fuel, never arithmetic) |
| `ITEM` combat run all plain | **design change 9** — P-A may use direct item-cooldown reads as the spine; any `SECRET` ⇒ stays cast-predict + out-of-combat anchoring only |
| `AURA sec=0` hits in the class sweep | **design change 3** — promote those IDs to in-combat `GetPlayerAuraBySpellID` reads (day-1 full data sweep = the same probe over all data; run `/fx probe aura-sweep` follow-up if hits appear) |
| `CAST inPlain>0` | cast-predict spine confirmed (Q1 closes; B2's SecretState ships as designed) — `inSecret>0` ⇒ active-edge + press-memory stay mandatory, spellID-keyed state banned |
| `SWING cap>0` with plain numbers | **design change 8** — Phase 3 swing timer on `PLAYER_SWING` as specced (no secrecy work needed) |
| `GATE` loads + manual gate test shows in combat | **design change 4** — registration blackout windows gated on `IsAddOnRestrictionActive(1|2|3)`; P-C/P-D container gates start (design doc D-wave) |
| `/fx probe bar` ticks in combat | **design change 5** — duration-object rendering spine: timeline/cooldown widgets fed by self-built `C_DurationUtil` objects (kills the "frozen bar" bug class); frozen ⇒ keep manual SetValue loops out of combat only |
| `EPOCH` +1 after relog, runs persisted | **design change 7** — SavedVariables contract (self-save on `PLAYER_LOGOUT`/`ADDONS_UNLOADING`, per-character learned DB in the TOCs) is on a working base; `probeEpoch` NOT incrementing ⇒ SavedVariables do not round-trip ⇒ NOTHING persisted is trustworthy — escalate first thing |
| `PRES getInvItemID=function` | keeps the Items.lua slot-based equipped path (CooldownMaster parity); `absent` ⇒ `C_Item.GetItemID(ItemLocation…)` fallback only |

After the session: file the SavedVariables file + the bar-observation into the
PLAN §9 log, then fix whatever the probes report (PLAN §11 Iteration D) and
re-stamp §8 risks with the measured facts.
