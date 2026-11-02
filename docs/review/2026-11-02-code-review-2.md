# ForteXorcist code review #2 — 2026-11-02 (agent `CodeReview2`)

Scope (assignment): code written since review #1 — `Forte_Core/Core/{Probe,Compat,Init}.lua`,
`Forte_Cooldown/Core/{Engine,Items,Enchants}.lua`, `Forte_Cooldown/Module.lua`,
`Forte_Cooldown/UI/{Timeline,TimelineMath}.lua`, `Forte_Hunter/**` (Tools/Swing/Reminder/Pages),
`Forte_Warlock/Core/Tools.lua`, `Forte_Options/**`, `scripts/deploy.sh`, all `tests/`.
Read-only; nothing edited. `Forte_Warlock/UI/Module.lua` (WarlockUI) is a live peer's in-flight
work (not in the .toc load list at this snapshot) — reviewed not, flagged as such.

Not re-raised (refuted by the manager, PLAN §9): B1 (globals ARE shared — EllesmereUIForeverFix
proof), B2/M1 (`GetPoint()` = `point, relativeTo, relativePoint, x, y` — the code's destructuring
is correct; verified the code uses `point, _, relPoint` everywhere). Review #1's confirmed
fixes were verified landed: M2 (`Items.lua:120-134` sweep now runs at the END of Rescan,
`test_items.lua:484` regression), M3 (`Tools.lua:311-318` pcall'd resolve), m1
(`Items.lua:360-367` guard-only OnRead), m3 (`Engine.lua:304-313` clock stamping +
`test_engine.lua:267`), m4 (SetLocked publishes, `Module`/`Timeline:466-485`, `test_options.lua:462`),
m6 (Init.lua:70-80 registry loop, `test_reconcile.lua:224,248`), m7 (live-probed in Probe PRES),
m8 (`deploy.sh --copy` mode present).

**Verdict: 0 blockers, 1 major, 6 minors.**

The overall picture: the codebase has internalized the secret-value law and the event-plumbing
law deeply (all four OnEvent-binding families carry `function(_, event, ...)`; every payload
index in every handler matches the pinned catalog; every registered event is handled; the
Hunter frame-vararg regression has real driving tests). The one major is the newest feature's
live-path gap the sim tests structurally cannot see.

---

## Major

### N1 — The end-of-cooldown PULSE can never spawn from the live feed: the `_ready` pop lives
in the per-entry loop, and the popped name is off the feed by definition [VERIFIED]
- Sites (`Forte_Cooldown/UI/Timeline.lua`):
  - `:1090-1097` — `OnReady` queues `q[name] = now + S.PulseSeconds`.
  - `:1275-1280` — the ONLY `SpawnPulse` call site, inside the per-entry loop:
    ```lua
    -- Attach a queued ready pulse (OnReady is fed by the Module).
    local endAt = self._ready[e.name]
    if endAt then
        self._ready[e.name] = nil
        self:SpawnPulse(e.name, slot._texPath, slot._col, endAt)
    end
    ```
  - `:1368-1372` — the queue prune: `if endAt + 2 < now then self._ready[name] = nil end`.
- Why it never fires live: the Module ticker (`Module.lua:466-477`) runs
  `Engine:Sweep(now, readyScratch)` — Sweep **removes** the popped entry from
  `Engine.entries` (`Engine.lua:481`) — then `OnReady(name, now)` queues it, then
  `Display:Update(Engine:Sorted(sortedScratch), now)` renders. `Sorted` reads `entries`, so the
  just-popped name is **not in the array on that pass nor on any later pass** (its entry is gone;
  the release loop `:1286-1290` releases its slot, identity dropped). The pop at `:1276` runs
  only for names present in `entries` — a popped name is never present → `SpawnPulse` is never
  reached → the queue entry silently evaporates at the 2 s prune. The whole pulse law (the
  source's `t15==-1` expiry effect at the LEFT end, PLAN §9 iteration B "splash/pulse law from
  source") is a no-op in game; the splash half works (first sighting), so the symptom is subtle:
  cooldowns ready (the "X ready" chat line prints) but the bar never pulses.
- Why the tests pass: `test_timeline.lua:327-361` ("OnReady pulses the left end…") calls
  `Display:OnReady("Disengage", 101)` and then feeds `Update` a hand-built array **containing
  "Disengage"** (`endTime = 101`, entry present). Production never feeds the popped name —
  the test bypasses exactly the Sweep→Sorted sequence that drops it. Class-5 pattern (mock
  bypasses the code under test).
- Failure scenario (live, every class): Bestial Wrath finishes → Module prints
  "Bestial Wrath ready" → the queued left-end pulse never draws → 2 s later it is pruned.
  uiforever T13 checked splash expiry only — pulse presence was not asserted there.
- Fix: pop the queue where the name LEAVES the feed, in the release loop
  (`:1286-1290`), before the slot identity is dropped:
  ```lua
  for name in pairs(byName) do
      if not seen[name] then
          local slot = byName[name]
          local endAt = self._ready[name]
          if endAt and endAt > now then
              self._ready[name] = nil
              self:SpawnPulse(name, slot._texPath, slot._col, endAt)
          end
          self:ReleaseSlot(slot)
      end
  end
  ```
  (keep the `:1275-1280` in-feed pop for entries that stay live; the `endAt > now` guard stops
  an old queued pop from painting a fresh icon). Add a regression test that drives the REAL
  sequence — `Engine:Sweep` pops → `Display:OnReady` → `Display:Update(Engine:Sorted(...))` —
  and asserts a `pulsePool` entry is live (`_endAt ~= nil`, frame shown) after the pass.

---

## Minors

### n2 — `SpawnPulse` never reuses a spent pool entry: every ready-pulse allocates a frame +
2 textures for the session's lifetime [VERIFIED]
- `Timeline.lua:1014-1017`:
  ```lua
  function D:SpawnPulse(name, texPath, col, endAt)
      local pool = self.pulsePool
      local s = pool[#pool + 1]
      if not s then
  ```
  `pool[#pool + 1]` indexes past the end — always nil — so the create+append branch always runs.
  Expired pulses (`s._endAt = nil`, hidden, `UpdatePulses :1062-1065`) are never scanned. The
  splash pool has the reuse scan (`:963-969`); the pulse pool's twin is missing. Violates the
  file's own header law ("the slot, splash and pulse pools only grow (acquire/hide, never
  destroy)" — grows without bound) and PLAN §3.4 frame-pool law.
- Scenario: a raid session with ~50 ready-pops/min (the live feed today — see N1 — spawns
  none, so this is latent behind N1; once N1 is fixed this bounds nothing: hundreds-to-thousands
  of named frames per session, each frame+2 textures, all hidden, all in the pool scan of
  `UpdatePulses`).
- Fix: mirror the splash scan: `for i = 1, #pool do if not pool[i]._endAt then s = pool[i] break
  end end` before the grow branch.

### n3 — `Enchants` keys entries by the resolved display NAME: the same enchant on two weapon
slots shares ONE entry, and the earlier-expiring slot kills the later one's icon [VERIFIED code,
scenario inferred]
- `Forte_Cooldown/Core/Enchants.lua:214` `local e = Engine.entries[name] or { name = name }`,
  `:226` `self.bySlot[spec.key] = { name = name, enchantID = id }`.
  `bySlot.MainHand` and `bySlot.OffHand` then name the SAME `Engine.entries[name]`.
  The `hasEnchant == false` / sub-floor branch resolves the entry via
  `entryName = state.name` (`:181,205`) — a slot-local operation on shared state.
- Scenario (plausible: Classic dual-wield with one temporary enchant on both weapons, e.g.
  the same poisons/oils on MH+OH — the test suite's `"off hand is independent of main hand"`
  (`test_enchants.lua:255`) covers only MH-enchanted/OH-plain): MH has 2 min of the enchant
  left, OH has 30 min. At MH's expiry its read hits the sub-floor branch → `landEntry(e, now)`
  lands the SHARED window → the next Sweep retires it → the 28-minute OH enchant disappears
  from the bar (and `Count()` counted 2 for one entry).
- Fix: key slot-scoped: `local key = name .. "#" .. spec.key` for the entry key (the Timeline
  prints `e.name`, so keep `e.name = name` for display while the table key carries the slot),
  and carry `bySlot[*].entryKey`. One test: both slots report the same `enchantID` with
  different `timeLeft`; expire MH; assert the OH entry is alive with its own `endTime`.

### n4 — `Window:BuildHeader` reads the *Cooldown bar's* live lock for EVERY page's lock icon,
including the Hunter page whose lockKey is `Hunter.Lock` [VERIFIED site, divergence traced]
- `Forte_Options/UI/Window.lua:675-680`:
  ```lua
  local d = FX.Cooldown and FX.Cooldown.Display
  if def.lockKey and d and d.cfg and d.cfg.locked ~= nil then
      locked = d.cfg.locked
  elseif def.lockKey then
      locked = FX.Settings:Get(def.module, def.lockKey)
  end
  ```
  The "single truth /fx lock|unlock moves" is the Cooldown bar — true for the Cooldown and
  General pages. The Hunter page's key is NOT in that publish chain: `Swing:SetLocked`
  publishes only `Hunter.Lock` (`Swing.lua:285-293`) and the Hunter page checkbox flips
  `Hunter.Lock` only (`Pages/Hunter.lua` `ensureWiring` routes module `Hunter` to Swing/Reminder
  only; Timeline's `_WireSettings` listens to Cooldown/General modules only, `Timeline.lua:772-781`).
  So `Hunter.Lock` can legitimately differ from `Display.cfg.locked`.
- Failure scenario: open `/fx options` → Hunter Tools → untick Lock (bar becomes movable,
  `Hunter.Lock = false`; the header icon follows via the store listener `:686-695` — fine).
  Close the window, `/fx lock` (Cooldown publishes its own + `GlobalLock`; Swing mirrors
  them → relocks; consistent). Now the divergence case: while the Hunter window page is open,
  the Hunter checkbox off, reopen via `SetPage("Hunter")` → `BuildHeader` re-runs → icon shows
  `Display.cfg.locked` = TRUE (locked glyph) while the checkbox reads `Hunter.Lock` = FALSE and
  the Hunter bar is movable. Header icon contradicts checkbox+bar — exactly the m4 shape the
  manager fixed for the Cooldown page (icon read the setting, bar the truth), re-imported here
  with the wrong module's truth.
- Fix: resolve the live frame per module — `local frame = def.module == "Hunter"
  and FX.Hunter and FX.Hunter.Swing or (FX.Cooldown and FX.Cooldown.Display)`; keep the
  store fallback.

### n5 — `Compat.PlainOrNil` calls `issecretvalue` RAW; `Probe.K` documents (and pcalls) the
raise this leaves open [VERIFIED site, trigger SUSPECTED]
- `Forte_Core/Core/Compat.lua:46-47`:
  ```lua
  local iss = _G.issecretvalue
  if iss and iss(v) then return nil end
  ```
  vs `Probe.lua:52-58` (same predicate, same session): *"a `issecretvalue` that itself raises is
  treated as 'not detected secret' (best-effort)"* and pcalls it. PlainOrNil is the file every
  law cites, called from the un-pcall'd guards (`Engine:OnRead:196-197`, `Items:OnRead:308-310`,
  `Enchants:OnReadSlot`, `Module:isKnown:65`, `RecordCastEvent:318`) — those guards run
  OUTSIDE a pcall (the read pcalls end before OnRead). An `issecretvalue` that raises (the
  condition Probe.K defends against, "the real secret-restriction behaviour,
  docs/research/secrets-unknowns.md") therefore raises out of the 1 Hz pass / 10 Hz ticker —
  the exact per-tick Lua-error shape m1 was graded for a weaker cause.
- Fix (one line, match Probe.K):
  ```lua
  local ok, secret = iss and pcall(iss, v)
  if ok and secret then return nil end
  ```
  (`pcall(iss, v)` → ok=true, secret=value — treat any truthy second return; Probe.K's exact
  shape at `:55-57`.)

### n6 — Frame pools/allocs: the m5 pass left two per-tick allocations standing [VERIFIED]
1. `Timeline.lua:1121-1126` `groupSignature` allocates a `parts` table + `table.concat` string
   **per multi-member group per pass** (10 Hz) — the m5 fix covered `TM.group` (scratch,
   `:1152-1155`) and the time text, not the signature. Bounded GC churn, groups>1 only.
2. `Timeline.lua:222-233` `applyFont` — the template-fallback branch sets `fs._font = nil`, so
   the dirty-check can never cache and `pcall(fs.SetFontTemplate, …)` re-runs on every fontstring
   every pass (only on the rejected-font path: `fontFile = nil`, e.g. BarFont set to a rejected
   path).
- Fix: cache the last signature string + member-count on the display scratch and reuse when the
  group's names are unchanged (the groups array is recomputed per pass anyway); store a
  sentinel `_font = "tpl"` for the template branch and compare.

### n7 — `/fx status` prints the Warlock line for every class [VERIFIED]
- `Forte_Warlock/Core/Tools.lua:858-861` — `M:Status` prints unconditionally; module Status is
  driven registry-wide (`Init.lua:70-80`). On a Hunter login `/fx status` gains
  `Warlock: shards ? | soulstone none | healthstone ? | ritual idle` — counters of trackers
  that are structurally unable to fill (`OnEnable` class-gates the event frame, `:836-840`), so
  the line is permanent noise. (Hunter solved this by printing only built frames,
  `Swing.lua:673-682` prints "not built" lines — the same shape; at least Warlock's is honest.)
- Fix: gate the print on `FX._playerClass == "WARLOCK"` (or print `warlock tools idle (class
  <X>)` as one short line).

---

## Verified-clean (traced; the class list from the assignment)

1. **Event plumbing** — every `SetScript("OnEvent", …)` in the shipped code
   (`Module.lua:393`, `Init.lua:115`, `Probe.lua:717`, `Tools.lua:363` + `Swing.lua:602` +
   `Reminder` (no events) + `Warlock Tools.lua:803`) is the `function(_, event, …)` shape; the
   vararg regression is covered by tests that drive the frame's real script with the frame as
   arg 1 (`test_hunter.lua` 'kicks the swing bar', `test_tiers.lua:618`, `test_warlock.lua`,
   `test_probe.lua:247`). Payload indices verified field-by-field against the pinned catalog
   records (`docs/api/wow-addon-api-agents/skills/*/references/generated/forever.json`):
   PLAYER_SWING `(swingDuration:number, swingType:PlayerSwingType)` — duration leads, matches
   `Tools.lua` two-handler split; PLAYER_SWING_RANGE_UPDATE `(swingType, isInRange, checksRange)`
   — type leads ✓; UNIT_SPELLCAST_SENT `(unitTarget, target, castGUID, spellID)` — Warlock reads
   `a4`/`a2` ✓; SUCCEEDED/START/STOP/FAILED/INTERRUPTED/CHANNEL_START/CHANNEL_STOP spellID = `a3`
   (and INTERRUPTED/CHANNEL_STOP's `interruptedBy` sits AFTER spellID, unread ✓); ADDON_LOADED
   `(addOnName, containsBindings)` ✓; PLAYER_ENTERING_WORLD `(isInitialLogin, isReloadingUi)`
   ignored ✓; WEAPON_ENCHANT_CHANGED payload-less UniqueEvent ✓; UNIT_POWER_UPDATE payload
   ignored ✓. All registered events handled (Module 12/12, Warlock 12/12, Hunter 4/4 + UI 6/6,
   Probe 4/4, Init 3/3); api-lint (gate) covers event existence; Unregister paths in
   Hunter/Warlock are complete incl. `UnregisterUnitEvent(…, "player")`
   (`Tools.lua:373-386`, Warlock `:821-837`); `SetScript(nil)` is the silencer, nil-guarded for
   the sim.
2. **Secret-value law** — the `ok and PlainOrNil(x)` false-on-raise trap is named and avoided
   with comments at every seam (`SecretState.Refresh:424-431`, `ShardCounter:Read:239-245`,
   `DefaultShardCountReader:206-212`, `test_tiers` sentinel design). Charge/enchant/aura/cast
   reads: guards at `Engine:OnRead:196-201` (type-gated, the string-compare incident comment),
   `OnReadCharges`, `OnReadActive`/`OnReadDuration` (defensive PlainOrNil even on NeverSecret
   claims), `Enchants:OnReadSlot` (every field), `Items:OnRead`, Warlock `plainNumber`.
   The remaining raw comparisons on live reads are catalog-anchored: `PLAYER_SWING` payload has
   NO secrecy annotation (record verified — the `swingType ~= rangedType` compare is plain-legal),
   `C_Spell.GetSpellInfo` has NO output annotation (isKnown's `info and info.spellID` legal),
   `C_Item.GetWeaponEnchantInfo` output plain-annotated (Enchants `:183` legal). The one law
   inconsistency left is n5.
3. **Lifecycle** — no `CreateFrame`/`RegisterEvent` at file load outside the Core bootstrap
   (Hunter/Warlock/Probe frames are all OnEnable/OnClassChanged-created); OnUpdate scripts
   exist ONLY during activity in Swing (`:404-433`, tick-gated) and Reminder (`:252-277`), with
   the hidden-frame law honoured: Swing `StartTicking` renders synchronously before relying on
   its own OnUpdate (`:426-431`, the 11-02 uiforever fix) with the exact regression test
   (`test_swing.lua:165-183` 'a kick on a live swing shows the bar immediately'); Reminder
   `Refresh` Shown synchronously from event kicks; Timeline is driven by the Module's C_Timer,
   not a hidden frame. Settings listeners are all single-registration (`_wired`, `wired`,
   `_lockWired[module]` guards). Modules do not double-enable (PLAYER_LOGIN once; Init prints
   'registered twice' on collision). No SavedVariables write before ADDON_LOADED (Settings store
   is lazy; pages register data-only at load; Probe epoch bumps at PLAYER_LOGIN).
4. **Cross-module contracts** — settings key sets: Cooldown module registers 20 keys ==
   `Timeline.STORED.Cooldown` 20 + KEYMAP covers all + `CATEGORY_OF` the 8 Color*; General's 5
   wired keys covered (FrameSnap/ShowTooltips documented not-used-yet); Hunter's 10 keys all
   consumed by Swing/Reminder maps. Lock mirroring: every SetLocked publish edge terminates at
   the store-inequality guard (traced all four cycles: Cooldown⇄General, Cooldown⇄Hunter
   (Swing's Cooldown/General listeners), page checkbox→publish→self-listener). `RegisterPage`
   ids ⊆ `O.INDEX` ids (General/Cooldown/About/Hunter present in the 16-entry grid;
   RefreshIndexCells liveness tested by drop/re-add, `test_options.lua:277-360`).
   `/fx status` = version line + registry loop with per-module pcall (`Init.lua:63-84`).
5. **Tests** — the suites are unusually adversarial: sentinel-secret end-to-end through real
   `M:ReadAll` (`test_tiers.lua:256`), real frame OnEvent driving, real slash-path tests, counter
   DELTAs against the shared-session tables, SECONDS-unit measured against the sim's real
   duration object (`test_tiers.lua:512`), every M2/m3/m4/m6 fix has a named regression test.
   The single class-5 instance found is the N1 mask (`test_timeline.lua:327` feeding the popped
   name by hand). The "heuristic-weak" sweep over all 10 suites was spot-checked (status-line
   shape tests, the `ignores non-ranged` contract test, the kick-regression) — all real.
6. **Read tiers / charge / enchant / splash math** — `Engine:OnReadActive`'s early-end landing
   keeps `start + duration == endTime`; the charge Sweep loop's step is bounded (e.duration is
   > 0 on every charge-entry creation path: OnCast BestDuration, the pair branch's `duration > 0`
   gate, the m3 stamping's `bd`); `OnReadDuration`'s no-total path preserves the invariant
   (`:449-456`); Enchants `endTime = now + timeLeft/1000` matches BuffFrame.lua:774-777's ms law
   (catalog record fetched: return table plain-annotated, `SecretArguments=AllowedWhenUntainted`);
   splash/pulse/fade constants match the source law quoted in the header (:1381/:1403/1.0 s);
   `TM.pos`/`tags`/`group` re-derived from the original's formulas clean; `TM.group`'s
   caller-scratch pool is wiped at reuse (its "cleared by the tail pass" header sentence is
   stale — functionally the clear is at reuse; comment-only nit, not counted).
   `formatRemaining`/`timeKey` pair: the displayed-string identity is exact for both branches.
   `deploy.sh`: runs clean (`--help` rc=0; the `BASH_SOURCE[0]` / redirect shapes in tool
   output are display sanitisation, byte-checked), modes/refusals/marker logic clean.
   Toc orders verified (Data→Core→UI→Pages in Forte_Hunter.toc makes the `BarColor` skin default
   and `DeriveAspectNames` load-time calls legal; Forte_Warlock.toc Data→Core).

## Open questions
1. **N1**: after the fix, assert the pulse on the live feed in the sim (Sweep-pop → Sorted feed)
   and on uiforever; consider whether the pulse should also fire when the bar is HIDDEN
   (current code: hidden bar's Update early-returns, `:1178-1182` — pulses animate, spawns
   happen at re-show as first sightings — decide the HideCombat intent explicitly).
2. **n3**: confirm with the owner that dual-slot same-enchant is a real Forever case before
   paying the key rename (the generated data has per-enchant rows; a same-id dual-wield is
   build-material, unproven).
3. **n7**: decide the class-gating convention for satellite status lines (Hunter prints
   "not built (class X)"; Warlock prints full state always; pick one).
4. The `Forte_Warlock.toc` load list at this snapshot lacks `UI/Module.lua` (WarlockUI peer
   running) — the receiving manager must gate it with its toc-twin update, and the gate's
   module/data-set probe needs WarlockUI added (a new module registers via
   `FX.RegisterModule("WarlockUI")`, `UI/Module.lua:311`).
