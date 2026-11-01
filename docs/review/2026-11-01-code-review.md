# ForteXorcist code review — 2026-11-01 (agent `CodeReview`)

Scope: all of `addon/Forte_Core/**`, `addon/Forte_Cooldown/**` (Engine, Items, Module, Timeline,
TimelineMath), `addon/Forte_Options/**`, `addon/Forte_Hunter/Core/**`, all `.toc` pairs,
`scripts/deploy.sh`. Read-only review; nothing edited.
Excluded per assignment: the `UI/Timeline.lua` slot-index rebind (known, being fixed by `TimelineFix`).

**Verdict: 2 blockers, 4 majors, 8 minors.** The two headline items:

1. **VERIFIED-SEVERITY BLOCKER (trigger suspected, mechanism verified): the whole
   multi-addon architecture shares a `ForteXorcist` global across five separate addons.**
   The Forever client is the Retail 12.x engine; Retail has separated per-addon Lua states
   since 10.2 — each addon's chunk writes into its own global store. The wow-ui-sim and
   uiforever.com simulators run all addons in ONE shared state (proof: PLAN §10.4 T1
   `modules=1` — Forte_Cooldown's `FX.RegisterModule` at `Module.lua:10` reached Forte_Core's
   `FX.modules`, and PLAN §10.2 T1 `Cooldown: 18 tracked` printed through `Init.lua:72`'s
   `cdMod:Status()` — this is only possible with shared state). The installed client's own
   multi-addon families do NOT rely on shared globals: `SilverDragon_History/SilverDragon_History.toc:11`
   uses `## LoadManagers: AddOnLoader` so the parent loads the satellite's files into the
   PARENT's state. If Forever keeps Retail separation, on the first real login: `/fx` does
   nothing per-module (Core's registry empty → `modules=0`), `/fx options`/`lock`/`unlock`
   dead (slash registrations of siblings invisible to Core's `SlashCmdList` handler),
   `FX.Cooldown` nil in Forte_Options' pages (nil-safe → silent), `FX.Data.Items` invisible
   to Forte_Cooldown (`Items.lua:131` → 0 items), every satellite's `FX.db` nil (all settings/
   learned/positions session-local). **Every cross-addon seam is a no-op and nothing prints an
   error.** This cannot be caught in any simulator. First real-client session MUST read
   `/fx status`'s modules count as gate #0; plan the fallback now (embed the satellites'
   files into Forte_Core's load list, or the AddOnLoader pattern, or C_AddOnMessages).
2. **VERIFIED BLOCKER: `Forte_Options/UI/Window.lua:143`** — `GetPoint` destructuring stores
   the *relativeTo frame* as `relPoint`; the options window raises a Lua error on every
   reopen after the first close. Same pattern in `Forte_Cooldown/UI/Timeline.lua:342` (major).

Details, severities, and all citations below. "verified" = traced in code + catalog-verified
contract; "suspected" = code site verified, runtime trigger depends on an unmeasured Forever
behaviour.

Concurrent-edit note: `Timeline.lua`, `Module.lua`, `Window.lua`, `Items.lua` changed during the
review (peers `TimelineFix`, `ItemsCD`, …). Every citation below was re-checked against the file
state at the end of this session (mtimes 1793565566–1793568788). One issue seen mid-review
(`GetServerName` at `Window.lua` — Classic-era global) was already fixed to `GetRealmName`
(present in the catalog) by a concurrent worker and is NOT reported.

---

## Blockers

### B1 — Cross-addon `ForteXorcist` global sharing; unproven on the real client [SUSPECTED trigger]
- Sites: `Forte_Cooldown/Module.lua:6-10` (`FX.RegisterModule("Cooldown", M)`),
  `Forte_Hunter/Core/Tools.lua:374` (`FX.RegisterModule("Hunter", M)`),
  `Forte_Options/UI/Window.lua:725-727` (`FX.RegisterSlash("options"…)`),
  `Forte_Cooldown/Core/Items.lua:131` (`FX.Data and FX.Data.Items`),
  `Forte_Options/Pages/General.lua:30` (`FX.Settings` writes to `FX.db`),
  `Forte_Core/Core/Init.lua:18-25,43-45,70-73`, `Forte_Cooldown/Module.lua:118-127` (`FX.db`).
- Failure scenario: first real-client login as Hunter. Forte_Core's state has no modules, no
  slash subs, no `FX.db` writes from siblings → `/fx status` = `modules=0`; `/fx options` falls
  through to the usage line; Forte_Cooldown registers a `SlashCmdList["FORTEXORCIST"]`? — no,
  only Core registers the slash, and its registry is empty → the entire product is inert with
  zero Lua errors (worst kind: silent).
- Proposed fix (one step at a time): (1) gate #0 of the first client session = read
  `/fx status`'s `modules=`; (2) if 0, fold the satellites into Forte_Core's load list (one
  addon, per-module folders) or adopt the installed-client pattern (`## LoadManagers:
  AddOnLoader`, SilverDragon_History.toc:11). The sim gates keep working unchanged.

### B2 — `Window.lua:143` `GetPoint` destructuring stores a Frame; reopen of the options window errors [VERIFIED]
- Code (`Forte_Options/UI/Window.lua:141-147`):
  ```lua
  local point, _, relPoint, x, y = f:GetPoint()
  …
  p.point, p.relPoint, p.x, p.y = point, relPoint, x, y
  ```
  `Frame:GetPoint()` returns `point, relativePoint, relativeTo, x, y` — the third value is the
  *relativeTo frame* (UIParent). So `p.relPoint` = a live Frame (and gets written into the
  SavedVariables table `FX.db.optionsPos`, where it is dropped at save → saved position's
  relPoint silently lost).
- Consumed at `Window.lua:155-157`:
  ```lua
  w:SetPoint(p.point or d.point, UIParent, p.relPoint or d.relPoint, p.x or d.x, p.y or d.y)
  ```
  `relativePoint` gets a Frame where a point string is required → `bad argument #3` Lua error.
- Failure scenario (no drag needed): `/fx options` (open, fine — defaults), `ESC`/X to close
  (`Close()` → `SavePosition()`), `/fx options` again → Lua error every reopen, position restore
  broken. Gate tests miss it because they never close+reopen (test suite drives widgets directly).
- Fix: `local point, relPoint, _, x, y = f:GetPoint()` (swap slots 2/3).

## Majors

### M1 — `Timeline.lua:342` identical `GetPoint` destructuring; `/fx reset` after a drag errors [VERIFIED]
- Code: `Forte_Cooldown/UI/Timeline.lua:339-346` (same `point, _, relPoint` pattern;
  `cfg.relPoint` = a Frame written into `FX.db.cooldownDisplay`).
- Consumed at `Timeline.lua:333-337` `ApplyPosition` → `SetPoint(cfg.point, UIParent, cfg.relPoint, …)`
  (frame in the point slot → `bad argument #3`).
- Failure scenario: `/fx unlock`, drag the bar (OnDragStop → SavePosition), `/fx reset` →
  Lua error, position not reset. A `/reload` heals it only because the serializer drops the
  Frame and the DEFAULT seed fills back in (so the dragged position's relPoint is lost, x/y kept).
- Fix: swap slots 2/3: `local point, relPoint, _, x, y = f:GetPoint()`.

### M2 — `Items.lua:120-128` the rescan sweep runs on the just-wiped `tracked` → every item entry dies on every rescan [VERIFIED]
- Code:
  ```lua
  wipe(self.tracked)
  wipe(self.byCastSpell)
  -- Invariant FIRST, before the data gate: an item-category entry with no
  for name, e in pairs(Engine.entries) do
      if (e.category == "Item" or e.category == "Potion")
          and not self.tracked[name] then
          …
          Engine.entries[name] = nil
  ```
  `self.tracked` was just wiped, so `not self.tracked[name]` is true for **every** entry —
  the sweep deletes ALL Item/Potion entries on every rescan, not only the untracked ones
  (the header and the comment at `:275-276` "Entries of items that left the inventory … died
  with the untracked sweep at the top" describe the intended behaviour; the implemented
  behaviour is "all of them").
- Failure scenario: trinket fired (120 s CD, entry live). Any bag event (`BAG_UPDATE_COOLDOWN`,
  `BAG_UPDATE_DELAYED`, `PLAYER_EQUIPMENT_CHANGED`, looting a grey, `PLAYER_ENTERING_WORLD`,
  `Module.lua:31-40` → `requestRescan`) → 0.5 s later the debounced `Rescan` kills the entry;
  in combat the follow-up reads are secret and `Items:OnRead` only *anchors* on plain reads →
  the trinket vanishes from the bar for the rest of the fight and never pops ready.
- Fix: move the sweep to the end of `Rescan` (after the tracked set is rebuilt, the "step 3"
  slot), keeping a copy of the old set for the data-absent path — i.e. prune against the NEW
  `self.tracked`, not the wiped one. (Owner: `ItemsCD` is live on this file.)

### M3 — `Tools.lua:302` bare `spellID == nil` on the raw cast-event payload — the exact pattern `Module.lua:167-168` forbids [site VERIFIED, trigger SUSPECTED]
- Code (`Forte_Hunter/Core/Tools.lua:301-303`):
  ```lua
  local function resolveCastName(spellID)
      if spellID == nil then return nil end
  ```
  The event field is the `UNIT_SPELLCAST_SUCCEEDED` `spellID`, catalog-annotated
  `SecretWhenUnitSpellCastRestricted` (`wow-api-unit-player/…/forever.json`,
  UnitDocumentation.lua:4844). Forte_Cooldown learned this: `Module.lua:167-168` — "No
  `spellID ~= nil` here: that is a comparison on a possibly-secret payload field" — and the
  hardened `Compat.PlainOrNil` (`Compat.lua:42-48`) documents that even `== nil` is a
  comparison. The Hunter comment at `:304-305` claims "same pattern as Forte_Cooldown/Module.lua";
  that pattern has since been fixed; the pcall at `:306` is reached only after the raise site.
- Failure scenario: §8 premise (own cast id can be secret in combat) + any Hunter cast in
  combat → the OnEvent handler raises at `Tools.lua:302` → one Lua error per cast (and the
  client stops reporting after 100, PLAN §2.3-8).
- Fix: drop line 302 (the pcall absorbs a nil/secret id) or route `local id =
  FX.Compat.PlainOrNil(spellID); if id == nil then return nil end` first.

### M4 — `Compat.IsPlayerSpell` gates every tracked spell; `IsPlayerSpell` is not in the pinned Forever catalog → silent zero tracking [SUSPECTED]
- Sites: `Forte_Core/Core/Compat.lua:92-97` (returns `false` when the global is absent),
  `Forte_Cooldown/Module.lua:45-49` (`isKnown` returns false →), `Module.lua:99-108`
  (`n = 0` passes `if not n` (0 is truthy in Lua) → the "no data for your class" notice is
  NOT printed).
- Catalog evidence: `IsPlayerSpell` has zero declarations in any pinned
  `docs/api/…/references/generated/forever.json` (grep across all 30 catalogs; the spell
  catalog's neighbours `C_Spell.GetSpellInfo/GetSpellCooldown/GetSpellCharges/GetSpellTexture`
  are all present). The code's "stays a plain global on every flavor so far" claim is unproven
  for Forever.
- Failure scenario: live client lacks the global → every `isKnown` false → `Engine:Build`
  tracks 0 spells → timeline bar permanently empty, `/fx status` shows `Cooldown: 0 tracked`,
  no error, no warning — indistinguishable from "this class has nothing to show".
- Fix: in `Rebuild`, when `n == 0 and data present`, print once "0 tracked — isKnown resolves
  nothing? (IsPlayerSpell missing?)"; probe the global at login and count in `/fx status`.

## Minors

### m1 — `Items.lua:326` raw `start ~= nil` on an unprobed item-cooldown read, outside the pcall [site VERIFIED, trigger SUSPECTED]
- `if ok and start ~= nil then self:OnRead(...) end` — the file's own contract
  (`Items.lua:35-41`) says the item-read secrecy is "an open live probe … consumers MUST route
  every number through PlainOrNil", and `PlainOrNil` documents `== nil` as a comparison
  (`Compat.lua:42-44`). The catalog annotates the item reads with no `SecretWhen…`
  (`C_Container.GetItemCooldown`, items-inventory catalog) so expected-plain, unmeasured.
  If a read returns secret in combat the comparison raises inside the `pairs` loop → aborts the
  whole 1 Hz read pass (every item AND the trailing pass) with a Lua error each second of combat.
- Fix: `if ok then self:OnRead(name, start, duration, now) end` — `OnRead` already guards
  (`Items.lua:285-288`), returning "secret" for nil.

### m2 — `Compat.lua:115-119,177-180` `GetInventoryItemID` / `GetInventoryItemCooldown` are not in any pinned catalog; the "verified twice" comment is unsupported [SUSPECTED]
- The header at `Forte_Cooldown/Core/Items.lua:43-48` and `Compat.lua:110-114` claim presence
  "verified twice: pinned Forever catalog … and the wow-ui-sim probe". Grep across all pinned
  catalogs: zero declarations (closest: `C_TooltipInfo.GetInventoryItemByID`). CooldownMaster
  uses `GetInventoryItemCooldown` (docs/engine-notes.md:16), so the sim+CMC evidence is real;
  the *catalog* leg of the claim is false. If the globals are absent live,
  `Compat.GetEquippedItemID` → nil and the equipped branch of `GetItemCooldownInfo` → nil →
  equipped trinkets untracked, silently (the gate `Items.lua:141-143` returns 0 when
  `getEquippedItemID` is nil — note this also disables the BAG items, gate conjunct includes
  `getEquippedItemID`).
- Fix: correct the comments (sim + CooldownMaster evidence only) and probe both globals in the
  first live session (they are already nil-guarded — no crash risk).

### m3 — `Engine.lua:229-252` charge entries with a secret charge-pair and no previous clock never sweep out [VERIFIED site, trigger SUSPECTED]
- `OnReadCharges` accepts a plain `currentCharges < max` and then, secret pair + `prev == nil`,
  builds `c = { max, current }` with **`nextAt = nil`** (`:245-252`). The charge Sweep branch
  (`Engine.lua:300-317`) advances only via `nextAt` and clears only on `current >= max` →
  `done` can never become true → the entry lives in `Engine.entries` for the rest of the
  encounter (excluded from `Sorted` while `current > 0`, shown stale when drained).
  Recovery needs a later plain pair (out of combat) — acceptable for a display that hides it,
  not for the engine's bookkeeping (it also re-survives `Sweep` silently).
- Fix: when a charges read produces `nextAt == nil`, stamp a prediction:
  `c.nextAt = now + (self:BestDuration(name) or 0)` (mirrors `OnCast`'s arming rule), or let the
  plain-window `endTime` clear charge entries in Sweep as a backstop.

### m4 — Options lock state can diverge from the real lock [VERIFIED]
- `Forte_Options/Pages/General.lua:55` (`lockKey = "GlobalLock"`), `Pages/Cooldown.lua:72`
  (`lockKey = "Lock"`) and `UI/Window.lua:610-617` (header icon reads the *setting*),
  while `/fx lock|unlock` (`Forte_Cooldown/UI/Timeline.lua` `SetLocked`, `D:Slash`) writes only
  `self.cfg.locked` in `FX.db.cooldownDisplay` and never writes back the two settings keys.
  `ensureWiring`'s `applyLock` runs only at first page build.
- Failure scenario: `/fx unlock` (bar movable, settings still `true/true`); open options →
  Cooldown page header icon renders *locked* (reads setting), checkbox checked, bar is
  draggable; clicking the (visually matching) checkbox toggles the "off" value → SetLocked(false)
  — a no-op the user reads as a broken checkbox.
- Fix: have `Timeline:SetLocked` publish through `FX.Settings:Set("Cooldown","Lock",locked)`
  (nil-guarded), the General page listen/mirror `GlobalLock`, and read the live
  `FX.Cooldown.Display.cfg.locked` when building the header.

### m5 — `Timeline.lua:742` per-tick string build + unconditional SetText in the 10 Hz pass; `Timeline.lua:791` `TM.group` allocates its groups table + one sub-table per pass [VERIFIED]
- `slot.timeFS:SetText(formatRemaining(math.max(0, remaining)))` runs every tick per icon
  (string.format allocation, texture-text invalidation), while the sibling charge text IS
  dirty-checked (`:751-755`). `TM.group` (`UI/TimelineMath.lua:86-109`) allocates `groups` +
  one `cur` per group on every call; `groupSignature` (`:610-614`) concats a string per group
  per tick (only for groups > 1).
- Impact: bounded (≤ ~10 icons, 10 Hz) — GC churn, not a stall. PLAN §3.4 says "Staggered
  polling … never allocate per tick".
- Fix: cache the last time string per slot (set only on change); reuse a scratch group table in
  `TM.group` (pass an out table like `Sorted(out)` does).

### m6 — `/fx status` hard-codes one module; the Hunter status is a monkey-patch on a sibling's method [VERIFIED; assessment as requested]
- `Forte_Core/Core/Init.lua:70-73` calls exactly `FX.Cooldown.Module:Status()`;
  `Forte_Hunter/Core/Tools.lua:347-359` wraps `cd.Status` (`_fxHunterStatusHooked`) to append its
  line — a class module patching a method object of another addon. It works today (guarded,
  one-shot, OnEnable-time so file load order is irrelevant), but: a second class module
  registers a *second* wrapper (chain grows per module, printing order = hook order, invisible
  in Forte_Cooldown's tests), Forte_Cooldown cannot test for it, and it silently vanishes when
  Forte_Cooldown is absent (`:358` comment admits).
- Clean Forte_Core change (the registry already exists, order-stable):
  ```lua
  -- Init.lua: replace the cdMod block with
  for _, name in ipairs(FX._moduleOrder) do
      local mod = FX.modules[name]
      if mod and mod.Status then mod:Status() end
  end
  ```
  Then `Cooldown.Module:Status` and `Hunter.Tools:Status` print their own lines
  (`Tools:Status` currently returns a string for the wrapper — print inside it) and the
  `Tools.lua:347-359` block is deleted.

### m7 — Legacy globals `SlashCmdList` (Forte_Core) and `UISpecialFrames` (Forte_Options) are not in the pinned catalog [SUSPECTED, guarded]
- `Forte_Core/Core/Init.lua:43` `SlashCmdList["FORTEXORCIST"] = function…` — a top-level write;
  if the table is nil on the live client Forte_Core's chunk dies at load (every addon inert).
  Documented only in the *historical* baseline (`wow-api-misc-systems/references/RETAIL-BASELINE.md:164`
  incl. the uppercase-key rule the code obeys). `Forte_Options/UI/Window.lua:310-317` appends the
  window name to `UISpecialFrames` (ESC-close); absent from the catalog, `type(…)=="table"`
  guarded → degrades to "ESC does not close the window".
- Fix: live-probe both at first login; keep a one-line fallback
  (`SlashCmdRegistry.AddSlashCommandList("SLASH_FORTEXORCIST1", …)` on retail-style surfaces).

### m8 — `scripts/deploy.sh`: symlinks into a **Wine prefix** path are unproven for the game's addon scan [SUSPECTED]
- `ln -sfn -- "$src" "$target"` into `…/pfx/drive_c/Program Files (x86)/…` (deploy.sh:9,
  deploy mode). The client runs under Wine inside that prefix; directory scans go through
  wineserver over the host FS — symlinks usually resolve, but PLAN §6 only records
  "smoke-verified on a temp dir" (host-FS, not Wine, and the client has never been run with
  them). Script hygiene itself is good (`set -euo pipefail`, refuses non-symlink entries,
  `--remove` limited to repo targets, `-n`-safe replaces).
- Fix: first client session check = `deploy.sh --list` + the addon list in-game; if symlinks do
  not appear, switch to `cp -a` staging (a `--copy` mode, ~5 lines).

---

## Verified-clean (checked, no defect to report)

**Secret-value law** (class 1, the highest-value one): every live spell/charge/cooldown read is
routed — `Module.lua:60-63` (pcall reads, fields handed raw **into guarding** `Engine:OnRead`
/`OnReadCharges`), `Engine.lua:190-192` and `:227-229` (guard before any compare; the GCD-window
compare at `Engine.lua:216` runs only on engine-owned plain numbers), `Items.lua:285-288`,
`Module.lua:160-163` (`PlainOrNil` before the counters), `Module.lua:47` (`isKnown` routes
`info.spellID`), `Tools.lua` swing-speed reads route `UnitRangedDamage`/`UnitAttackSpeed`
(both catalog-`SecretWhenUnitStatsRestricted`; return orders match the catalog exactly:
`(speed,min,max,…)`, `(attackSpeed,offhand,ranged)`). Charge booleans: the code relies on
`maxCharges`/`isActive`/`isOnGCD` NeverSecret — consistent with the catalog
(`SecretWhenCooldownsRestricted` on the function, `C_Spell.GetSpellCharges`). The two
remaining raw nil-tests are m1 (Items.lua:326) and M3 (Tools.lua:302).

**Event contracts** (class 3): every registered event exists in the pinned catalog —
`ADDON_LOADED`, `PLAYER_LOGIN`, `UNIT_SPELLCAST_SUCCEEDED`, `SPELL_UPDATE_COOLDOWN`,
`PLAYER_REGEN_ENABLED`, `SPELLS_CHANGED`, `PLAYER_ENTERING_WORLD`, `BAG_UPDATE_COOLDOWN`,
`BAG_UPDATE_DELAYED`, `PLAYER_EQUIPMENT_CHANGED` (`EVENTS-A-F/M-R/S-Z.md`), `PLAYER_SWING`,
`PLAYER_SWING_RANGE_UPDATE` (forever-only, `SwingTimerDocumentation.lua:42/53`). Payload orders
match: `UNIT_SPELLCAST_SUCCEEDED(unitTarget, castGUID, spellID, castBarID[Nilable])` —
`Module.lua`'s `(self,event, unit, castGUID, spellID, castBarID)` and `Tools.lua:323-326`'s
`a3` = spellID both correct; `PLAYER_SWING(swingDuration, swingType)` vs
`PLAYER_SWING_RANGE_UPDATE(swingType, isInRange, checksRange)` — `Tools.lua:333-339` uses two
handlers with the right orders (the PLAN §8 trap avoided). `C_Timer.After/NewTicker` argument
orders match. `C_UnitAuras.GetAuraDataBySpellName(unit, spellName, filter)` matches the
catalog record (the audit note about the non-existent `GetPlayerAuraBySpellName` is correct).
Old-Classic globals: `GetSpellInfo`, `UnitAura`, `UnitBuff`, global `GetSpellCooldown`/
`GetItemCooldown`, `GetContainerItemInfo`, `GetSpecialization` — all absent from the catalog
(= correctly removed from the code); `NUM_BAG_SLOTS`/`INVSLOT_TRINKET1/2` are Classic-only
(absent from catalog) and used only with `or 4`/`or 13/14` fallbacks (`Items.lua:242`) — safe
fallbacks, values match the InventoryType layout.

**Taint / combat lockdown** (class 2): all `CreateFrame`/`RegisterEvent` happen at load-time data
setup, in the Forte_Core bootstrap, inside `OnEnable` (PLAYER_LOGIN), and lazily in the frame
pools. Combat-time pool growth (`Timeline.lua:545` splash, pulse, `AcquireSlot`) creates plain
non-secure frames — legal per the pinned lockdown contract: "Cannot: create/destroy **secure**
frames … Can: modify non-secure frames"
(`wow-api-lua-environment/references/RETAIL-BASELINE.md:166-170`). No `SetPropagateKeyboardInput`
use, no writes to Blizzard secure frames; the only Blizzard-global writes are UISpecialFrames
(m7). No top-level `RegisterEvent` outside the Core bootstrap frame.

**SavedVariables** (class 5): `## SavedVariables: ForteXorcistDB` declared in both Core tocs;
satellites write only into `FX.db.*` (owned by Core) after ADDON_LOADED (`Init.lua:83-86`) and
`Engine:AttachStorage` runs in OnEnable with a session fallback (`Module.lua:196-205`);
`Forte_Options/Core/Settings.lua:49-71` resolves storage lazily — no nil-db path at load. The
two Frame-into-SavedVariables sites are B2/M1. Under B1-separation the satellites' `FX.db`
is nil (folded into B1).

**Toc hygiene** (class 9): all five pairs `X.toc`/`X_Camelot.toc` byte-identical (filecmp
verified), `## Interface: 16001` everywhere, Dependencies/OptionalDeps present and load-order
consistent (Items/Hunter files load before Forte_Cooldown via its OptionalDeps; Hunter's
Data-before-Tools order makes `DeriveAspectNames` at `Tools.lua:271-283` safe; ByName maps are
sibling tables, so the `pairs(data)` walks never index a number). Every listed file exists,
every shipped lua is listed (`UI/Rows.lua` deliberately dormant per PLAN §6), `tests/` not in
tocs, `Forte_Deathknight` toc-less by design.

**Engine logic** (class 7, beyond M2/m3): `Sweep` charge clock math and full-bar pop,
`Sorted` (charge-drained filter, endTime + name tiebreak = stable), `rowFor` row cache
(reclaimed by Build's wipe), `OnRead`'s 1.6 s GCD-mask window, `OnActiveEdge` idempotency,
`Build`/`Sweep` wipe discipline, Sweep's safe pairs-removal: all trace clean.
`OnReadCharges` re-allocs the charges table at 1 Hz (negligible). Items family law
(`LearnFamily`, shared `categoryId` sibling cast at `Items.lua:255-263`) traces clean — the
consumables gate `MIN_CATEGORY_CD = 60` correctly drops the elixir-band rows (verified against
the data: e.g. Arcane Elixir 3 s).

---

## Open questions
1. **B1 is THE gate-0 probe of the first real-client session** (owner runs the client after
   11-04): `/fx status` must show `modules=2` (Cooldown + Hunter) and
   `Cooldown: N tracked`. If not, which fallback is owner-preferred — single FatAddon,
   AddOnLoader (installed-client pattern), or C_AddOnMessages event bus?
2. Live probe list for that session (all already nil-guarded): `IsPlayerSpell` (M4),
   `GetInventoryItemID`/`GetInventoryItemCooldown` (m2), `SlashCmdList`/`UISpecialFrames`
   (m7), symlink deploy (m8), item-read secrecy (m1), mixed charge-read secrecy (m3).
3. Should `/fx lock` publish into `FX.Settings` (m4 fix) — small cross-module write into the
   Options-owned store; needs an owner nod on the direction (Timeline → Settings).
4. m3: is an engine entry that cannot expire ever (charge entry, `nextAt = nil`) acceptable
   during a fight if the display hides it (charge display not built), or must the engine
   guarantee expiry? Proposed stamping fix above.
