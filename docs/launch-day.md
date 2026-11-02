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

1. **Deploy (copy mode).** `scripts/deploy.sh --copy` from the repo root.
   `--copy` (not symlink) because third-party tools below edit `.toc` files in
   place and symlinks would write into the git tree.
2. **ForeverSVFix: uninstall if installed.** (If it edits our `.toc` in place,
   the SavedVariables evidence below is contaminated.) Launch, log in on the
   **Hunter**.
3. `/fx status` — every Forte module listed, `Probe: epoch=1 runs=0` line
   present, class=HUNTER, build line sane.
4. `/fx probe` — the **out-of-combat baseline run** (label `ooc` auto).
   Read the printed lines (guide below); all 20+ lines also print, the run
   itself is stored.
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

## Feature smoke checks (same session, after step 9; ~10 minutes)

Each line is something only the real client can prove. Note PASS/FAIL and anything odd;
a screenshot of anything that looks wrong is worth more than a description.

| # | Do | Expect |
|---|---|---|
| F1 | `/fx options` | window opens; the **close X** and the profile tab glyphs render (the sim draws them at 0×0, unverified); ESC closes it |
| F2 | Cast Rapid Fire (or any long cooldown) | its icon appears on the right of the cooldown bar with a white 4× splash that fades over ~1 s, then slides left along the bar |
| F3 | Wait for a short cooldown (Arcane Shot / Multi-Shot) to finish | the icon reaches the left end and **pulses** once (this pulse never fired live before the 11-02 fix); **no chat line** — the pop prints nothing by design (E1, 11-02), the ready chat line only appears if the Self Messages page's "Chat line" (`ReadyChat`) is ticked, and it is off by default |
| F4 | Start auto-attacking with a ranged weapon | the Auto Shot **swing bar** appears under the cooldown bar, fills left→right each shot, hides when you stop (it never appeared in a client before the 11-02 fix) |
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
