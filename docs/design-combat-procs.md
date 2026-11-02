# In-combat item / trinket / proc display — design and live-probe list

Status: **design, not built.** Written 2026-11-01 from three source reads
(`docs/reference/addons/everauras-family.md`, `shadowflare.md`, `powerauras-classicprocauras.md`) and the
simulator specs (`docs/reference/wow-ui-sim-specs/`). Evidence quality is stated per claim.
Nothing here has run in the real client. The first live session is on/after the 2026-11-04 launch.

## 1. The problem (engine-wide, not ours)
- The combat log is closed to addons on this engine (`forever-combat-event-namespace.md`; `RETAIL-12-0-CHANGES.md:160-180`).
  No addon can parse "proc fired".
- Aura and cooldown reads are secret while restricted; our code gets opaque values it cannot compare.
- Own casts (`UNIT_SPELLCAST_SUCCEEDED`) are the one reliable in-combat signal, and even its `spellID` is
  annotated `SecretWhenUnitSpellCastRestricted` — plain-ness for own casts is *observed*, not guaranteed.
  The cast counter in `/fx status` exists to measure this on 11-04.

## 2. What the item data allows (`docs/item-procs.md`, generated)
| Kind | Count | In-combat signal | Verdict |
|---|---|---|---|
| on-use items (trinkets, engineering) | 238 | **cast event** → predict from known cooldown | **Full bar support**, same path as spells |
| consumables (potions, healthstones) | 79 | cast event, category cooldown | **Full bar support** |
| weapon-enchant procs | 5 | none | buff window only (see §3) |
| item procs (buff on a trigger) | 405 | **none** — no cast to predict from | audible/visual alert + best-effort timer (see §3) |

## 3. Proc channels, ordered by how much we trust the evidence
1. **Own-cast prediction** (certain in design, plain-id unverified): on-use effects. Entry created on cast, duration from
   generated data keyed by NAME. Already the engine's core path.
2. **Audible cue with zero reads** — `C_UnitAuras.AddAuraSound(trigger, {unit, spellID, sound...})`.
   Evidence: used by Musca/EverAuras (`BlizzardAuraDisplaySounds.lua:72-73,117-127`; authors' in-game claim 2026-09-18..24).
   Unverified by us. Lets us say "proc!" without ever reading a secret.
3. **Gate container** (the one mechanism that renders a no-cast proc): a hidden 1×1 `AuraContainer`
   (`CustomAuraContainerTemplate`), `AddAuraSlot(name, "HELPFUL", {candidateFilters={includeSpellIDs={[id]=true}}, initializeFrame=...})`,
   built **out of combat**. Blizzard's untainted code matches and shows/hides the slot button; we read only our own clock
   (`button:SetScript("OnUpdate", function() gate.seen = GetTime() end)`; present ⇔ `GetTime()-gate.seen < 0.3`).
   Evidence: Power Auras `Core.lua:247-256,279,296-329`, ClassicProcAuras `Core.lua:206-276` (RefProc), Shadowflare
   "blind" mode ×14 procs (RefShadow). **Authors' claims; item-source proc IDs never exercised by anyone we read.**
   Caveats found: register out of combat only (`InCombatLockdown()` guard; rebuild after the fight); spell-ID filters are
   documented as *dead for debuffs on yourself* (`ForeverEngineAuraOptions.lua:158`) and Musca's preview warns
   "spell ID filters hide these auras in combat" — so **buff-vs-debuff behaviour must be probed**.
4. **Timer from the gate edge**: on the gate's rising edge, start our own predicted entry with the proc's known
   `effect_duration_ms` (ItemData has it for 400/405 item procs with a duration… 205 have none → show `?`); correct on the
   falling edge. This gives a **bar position without reading a secret**. Accuracy = duration table + edge latency (≤0.3 s).
5. **Spell-state proxy** (Shadowflare 20 procs): `castTime`/`cost`/`IsSpellUsable`/`GetSpellCooldown().isActive`.
   Boolean only, no times, stacks only for linear cost slopes. Use only as a fallback, never to place a bar position.
6. **Native alert**: `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` events; only fires for spells that glow. Bonus signal.

## 4. What we will build (phased)
- P-A: **landed** — on-use trinkets + consumables on the timeline via the cast path (`Forte_Cooldown/Core/Items.lua`, wave 2a).
- P-B: **landed 2026-11-02 (H7), at its narrowest reading** — `Forte_Cooldown/Core/Procs.lua`
  behind `Cooldown.Procs` (default OFF): the watched set is the generated rows that carry a
  plain `buffId` + an `icdMs` clearing `Engine.MIN_COOLDOWN` (class-filtered: 13 for a Hunter),
  and a proc aura *seen* through one of the two trusted routes — the out-of-combat
  `C_UnitAuras.GetUnitAuras("player","HELPFUL")` sweep (the Reconcile.lua gate: sealed aura
  mode or `InCombatLockdown`) or `UNIT_AURA`'s `addedAuras` — puts the proc's **ICD** on the
  bar (`{start=now, duration=icdMs/1000, predicted=true, source="proc", category="Item"}`,
  key `<data name>#<buffId>` per the n3 law). The window's length is data and its start is
  `GetTime()`; no aura number reaches a widget (§4 hard rule). No proc-list UI: the owner's
  review of "which of the 405 to watch" is still open, and with it the checkbox — the key is
  registered in `Forte_Options/Pages/Cooldown.lua` with no page row.
- P-C: **not built** — gate containers per chosen proc. Its evidence (probe 3) is other addons'
  claims about item-source proc IDs; Q3 keeps in-combat proc work behind the launch-day probes.
  `Core/Procs.lua` counts every sealed/raised/plain read and prints it at `/fx status`, which is
  the same evidence probe 2/3 ask for, gathered by the shipped path.
- P-D: **not built** — gate-edge timers + `AddAuraSound` cues (same reason: the `source="gate"`
  display has nothing to observe until P-C exists).
- Hard rule: **nothing secret-derived is ever passed to our own widgets** (`aura-secret-display.md`: tainted code touching
  secrets errors). Gates observe only `GetTime()`.

## 5. Live probes for 2026-11-04 (cheap, in this order)
**Instrumented already (H7, 2026-11-02):** `/fx status` prints a `Procs:` pair — the watched/live
counts and `proc reads N | plain N | secret N | raised N | skipped N` plus the aura-event and
edge counters. Probes 2/3's question ("is the aura read sealed, and does a proc's appearance
arrive as a plain `spellId` out of combat / through `UNIT_AURA`?`) is answered off those columns
by the shipped path, with no hand probe. Probes 4-7 stay manual.
1. Cast counter: is own-cast `spellID` plain in combat? (`/fx status` → plain/secret/unresolved).
2. Does a gate for a **self buff by spell ID** show/hide in combat? Use a long-lived known buff first (food, a class aura),
   then a real trinket proc.
3. Same gate for an **item-source** proc (RefProc flagged this as never exercised).
4. Does `C_UnitAuras.AddAuraSound` fire on a self-buff gain in combat?
5. Does `StatusBar:SetTimerDuration` tick with a duration object **we** construct (`C_DurationUtil.CreateDuration()` + `SetTimeFromStart`)?
   (Musca does this at `SecretAuraSingleFollow.lua:186-190`; never proven by us.)
6. EllesmereUI's `SetDurationText` readback (RefShadow lead) — only route to real in-combat remaining time.
7. Does `C_Item.GetItemCooldown` / `C_Container.GetItemCooldown` return plain values for trinkets in combat?

## 6. Licence / provenance
Shadowflare has no licence (pattern reference only; no code copied). Power Auras / ClassicProcAuras / Musca / EverAuras
licences are recorded in the per-addon reports. We reimplement from the API surface, not from their source.
