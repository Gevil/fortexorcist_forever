# Warlock tools (`Forte_Warlock/Core/Tools.lua`) — contracts, evidence, probes

Groundwork slice (Iteration C "Warlock tools groundwork", PLAN §11): the original's four warlock
modules reduced to their **Forever-legal core** — headless state trackers, one `/fx status` line,
no frames and no options page. Module table `FX.Warlock.Tools`, registered as module `Warlock`;
the trackers are constructed as `FX.Warlock.NewShardCounter` / `NewSoulstoneTracker` /
`NewHealthstoneTracker` / `NewSummonTracker` with injected clocks and readers, exactly the
`Forte_Hunter/Core/Tools.lua` shape this file mirrors.

Original law: `docs/reference-functional-spec.md` §4 (Soulstone Tracker `SS-01…13`), §5
(Healthstone Spy `HS-01…07`), §6 (Summon Assistant `SU-01…09`), §8 (`FE-35` Shard Manager/
Shard Spy = **removed module**, "no reference law"), §3.6 module map (`PLAN.md`): *own: feasible
(bags, own casts); spying on others: pending*. Look references: `docs/refs/options-panel.png`,
`docs/media/frames/walk-000130.png` (options: Summon Assistant section), the soulstone bar panel
law of `SS-04` (`docs/refs/`).

**What is deliberately not here** (each row is a spec verdict, not an omission): raid-wide
soulstone/healthstone "spy" state (the original's data was `SendAddonMessage` comms, `SS-08`/
`HS-02` — the comms layer is Phase 6, `PLAN §3.6` P6 channel legality), the per-member aura scan
(`SS-05` = `feasible-out-of-combat-only`), the Summon Assistant's roster/distance/map sampling
(`SU-02` = `NOT-feasible-on-Forever`), whisper queueing (`SU-06`, Phase 6 with the chat layer),
pet-cast announcements (`CA-28`), and every frame (Phase 5).

## Public API

| Name | Contract |
|---|---|
| `FX.Warlock.DeriveNames(patterns)` → sorted names | generated-data spell names matching a Lua name pattern |
| `FX.Warlock.DeriveItemNames(patterns)` | the same, minus the `Create *` **spell** rows (item-name lists) |
| `FX.Warlock.soulstoneNames` / `.healthstoneNames` / `.summonNames` | the derived families (`WK.SoulstonePatterns`/`HealthstonePatterns`/`SummonPatterns`) |
| `FX.Warlock.SHARD_ITEM_NAMES` | `{ "Soul Shard" }` — the shard is a **name**, the data has no shard row |
| `FX.Warlock.SOULSTONE_SECONDS` = 1800, `WK.DeriveSoulstoneSeconds()` | the predicted stone window: data `durationMs` if the row carries one, else the 30-minute constant |
| `WK.DeriveSummonChannelSeconds()` | the ritual's channel length = the data `castMs` of the summon family |
| `WK.DataItemID(name)` | the generated data's id for a NAME (handed to an item seam, never compared) |
| `FX.Warlock.NewShardCounter({countReader, powerReader})` | shard tracker (`countReader` = bag source, `powerReader` = power-bar source) |
| `:Read(readers[, onlySource])` → `count\|nil, source` | sample the sources, first plain non-negative answer wins and is recorded as `source`; nil = nothing answered, last known count stands |
| `:Count()` → `count, source`, `:Snapshot()` | tracked state |
| `FX.Warlock.NewSoulstoneTracker({now, duration, patterns})` | stone tracker |
| `:OnCastSent(name, targetName)` → bool | claim the target of a family cast in flight (`UNIT_SPELLCAST_SENT`) |
| `:OnCast(name[, targetName])` → bool | our own successful family cast → the stone is live, predicted window |
| `:Active([now])` → bool, `:Remaining([now])`, `:Target()`, `:Snapshot()` | live-now, seconds left, bearer (`nil` = not readable), plain copy |
| `FX.Warlock.NewHealthstoneTracker({now, countReader, cooldownReader})` | stone-in-bags tracker |
| `:ReadCounts([countReader])` → `count\|nil` | bag presence; nil = no reliable read |
| `:Present()` → `true\|false\|nil` | nil = never read (never "empty") |
| `:OnReadCooldown(start, duration, enable[, now])` → `"anchored"\|"cleared"\|"secret"\|"ignored"` | the raw `FX.Compat.GetItemCooldownInfo` triple, guarded here |
| `:ReadCooldown([reader][, now])`, `:CooldownRemaining([now])`, `:Snapshot()` | the live pass, seconds of item cooldown left, plain copy |
| `FX.Warlock.NewSummonTracker({now, channelSeconds, patterns})` | Ritual-of-Summoning channel tracker |
| `:OnCastSent(name, targetName)` / `:OnCastStart(name)` → bool | the channel **starts** (predicted) and the target is claimed |
| `:End(name, outcome)` → bool | the channel ends; `outcome` is recorded (`succeeded`/`failed`/`cancelled`/`expired`) |
| `:Channeling([now])`, `:Progress([now])`, `:Snapshot()` | live-now (self-expiring prediction), `fraction, remaining`, plain copy |
| `FX.Warlock.Tools:ReadItems()` | one bag-driven read pass (shard bag source + healthstone count + item cooldown) |
| `FX.Warlock.Tools.ResolveCastName(spellID)` → `string\|nil` | the pcall-guarded id→name seam the event frame calls |
| `FX.Warlock.Tools.ResolveTargetName(target)` → `string\|nil` | the `PLAINOrNil`-guarded target seam (the SENT `target` field is ConditionalSecret) |
| `FX.Warlock.Tools:StatusLine()` / `:Status()` | the one `/fx status` line (the module prints it, `Init.lua`'s loop only loops) |

Secret-value law (AGENTS.md): every bag/item/power/cooldown read passes
`FX.Compat.PlainOrNil` (`Forte_Core/Core/Compat.lua:45`) before any compare or arithmetic and the
guards test `type(x) == "number"`, never `~= nil`; a secret/raising read never overwrites known
state. The cast-event spellID and the SENT target are guarded the same way. One house trap this
file documents in its own comments: `local plain = ok and PlainOrNil(v)` is a **trap** — a raise
makes it `false`, `false ~= nil` is true and the following numeric compare then raises ("attempt to
compare number with boolean", measured in the sim 2026-11-02); the readers therefore use
`local plain; if ok then plain = … end`.

## How this build models Soul Shards

Measured in the pinned catalog, the generated data, the engine research and the simulator
(`--class Warlock`, 2026-11-02):

| Signal | Value / evidence | Reading |
|---|---|---|
| `Enum.PowerType` includes `SoulShards = 7` | `PowerTypeConstantsDocumentation.lua:17` | the enum slot exists on the engine |
| `UnitPower(unitToken, powerType[, unmodified])`, `SecretWhenUnitPowerRestricted=true` | `UnitDocumentation.lua:2731` | a power-bar read is legal, secret-able in combat |
| `C_Item.GetItemCount(itemInfo, includeBank, includeUses, includeReagentBank, includeAccountBank) → count` | `ItemDocumentation.lua:450` | an item-count read; the `includeReagentBank` flag is the **reagent** system |
| the generated `shards-and-stones` data family: `Create Firestone` / `Create Healthstone` / `Create Soulstone` / `Create Spellstone`, `castMs` 3000–5000, **no shard row at all** | `addon/Forte_Warlock/Data/Warlock.lua` | the shard is a cost, not a spell — a **reagent item** |
| sim research: "Resources: mana bar (`warlock.go:188` EnableManaBar) + **Soul Shards** as an aura with stacks (`soul_shards.go:16-33`); carried count from `WarlockOptions.SoulShards` (all five builds ship 32, "full Felcloth Bag 21341") … spent through `useReagents`" | `../wow-forever-sim/research/R17/r17-warlock.md:17-21`, `:365` (`resources: [mana, soul_shards]`) | bag-carried count, bag-spent; the aura-stack note is the *engine's* internal model, not an addon-visible surface |
| engine aura vocabulary has `A_MOD_SPELL_CURRENCY_REAGENTS_COUNT_PCT`, `A_NO_REAGENT_USE` | `../mythicsim-forever-engine/src/prepare/dbcenums.rs:555`, `:629` | shard costs ride the modern **spell-reagent** machinery |
| sim probe, `--class Warlock`: `UnitPowerType("player")` → **0** (`Mana`), `UnitPower("player", 7)` → **0**, `C_Item.GetItemCount("Soul Shard")` → **0**, `C_Item.GetItemCount("Healthstone")` → **0**, `Enum.PowerType.SoulShards` → 7 | probe log, this file's Verification section | both seams are *callable* and answer plainly on this build; `UnitHasPowerType("player", 7)` **raises** in the sim (never call it unguarded) |

**Decision (both implemented, source-labelled):** the weight of evidence is the bag item, so
`ShardCounter` probes **bag first, power bar second** and records which one answered
(`shards 12[bag]` on `/fx status`). The two sources cost one reader each, the source label answers
the launch-day question in one login, and neither is trusted for more than a *count* — the count is
displayed, never used to gate anything. `UnitHasPowerType` is not used at all (it raises on the
sim's build, `UnitDocumentation.lua:1410` is therefore only an existence citation).

## Catalog evidence

Evidence files: `docs/api/wow-addon-api-agents/skills/<skill>/references/generated/forever.json`
(pin `ca8368f2…`, target `forever`, version `1.60.1.70532`; declarations from `wow-ui-source`
`Blizzard_APIDocumentationGenerated/*`). "Secret annotation" lists what the declaration attaches;
`—` = none on the rows we consume.

| Name | Exists? | Secret annotation | File |
|---|---|---|---|
| `C_Item.GetItemCount(itemInfo, …)` → `count` | **yes** — `itemInfo` is the ItemInfo argument; Blizzard callers pass an **itemID** (`ItemUtil.lua:320`, `Blizzard_Contribution.lua:201` with `INCLUDE_REAGENT_BANK`) or an **item link string** (`Blizzard_UIPanels_Game/MerchantFrame.lua:729`) — our name string is that same argument | `SecretArguments=AllowedWhenUntainted`, no `SecretWhen…` on the return | `ItemDocumentation.lua:450` |
| `C_Item.GetItemCooldown(itemInfo)` → `startTimeSeconds, durationSeconds, enableCooldownTimer` | **yes** | none on the returns | `ItemDocumentation.lua:433` |
| `C_Container.GetItemCooldown(itemID)` → `startTime, duration, enable` | **yes**, `MayReturnNothing` | none | `ContainerDocumentation.lua:336` |
| `FX.Compat.GetItemCooldownInfo(itemID, slot)` | the project's own seam over the two rows above (`slot=nil` → bag item by itemID) | probe note in its header | `addon/Forte_Core/Core/Compat.lua:310` |
| `UnitPower(unitToken, powerType, unmodified)` | **yes** | **`SecretWhenUnitPowerRestricted=true`** → every return through `PlainOrNil` | `UnitDocumentation.lua:2731` |
| `Enum.PowerType` (`SoulShards=7`) | **yes**, 30 values | — | `PowerTypeConstantsDocumentation.lua:17` |
| `UnitHasPowerType(unitToken, powerType)` | **yes** (not used) | `SecretArguments=AllowedWhenUntainted`; **raises** in the wow-ui-sim build | `UnitDocumentation.lua:1410` |
| `BAG_UPDATE_DELAYED` | **yes** — `UniqueEvent`, no payload | — | `ContainerDocumentation.lua:674` |
| `BAG_UPDATE(bagID)` / `BAG_UPDATE_COOLDOWN` | **yes** (`BAG_UPDATE_COOLDOWN` is what `Forte_Cooldown/Module.lua:386` registers, `BAG_UPDATE_DELAYED` what `:388` registers; we register only the DELAYED one) | — | `ContainerDocumentation.lua:658`, `:668` |
| `ITEM_COUNT_CHANGED(itemID)` | **yes** — `UniqueEvent` | — | `ItemDocumentation.lua:1844` |
| `UNIT_POWER_UPDATE(unitTarget, powerType)` | **yes** — `SynchronousEvent`, payload `powerType` is a **cstring**, not the enum (we register it unit-filtered on `"player"` and never read the payload) | — on the event; the read it triggers is the annotated `UnitPower` | `UnitDocumentation.lua:4551` |
| `UNIT_SPELLCAST_SENT(unitTarget, target, castGUID, spellID)` | **yes** — the target **name** is the 2nd field, the spellID the **4th** | **`SecretWhenUnitSpellCastRestricted=true`**; `target` additionally `ConditionalSecret=true` | `UnitDocumentation.lua:4802` |
| `UNIT_SPELLCAST_SUCCEEDED(unitTarget, castGUID, spellID, castBarID)` | **yes** (the 4th field is `Nilable`, `NeverSecret`, tolerated) | **`SecretWhenUnitSpellCastRestricted=true`** → id→name inside one pcall | `UnitDocumentation.lua:4844` |
| `UNIT_SPELLCAST_START` / `UNIT_SPELLCAST_STOP` | **yes** — `(unit, castGUID, spellID, castBarID)` | **`SecretWhenUnitSpellCastRestricted`** | `UnitDocumentation.lua:4816`, `:4830` |
| `UNIT_SPELLCAST_CHANNEL_START` | **yes** — `(unit, castGUID, spellID, castBarID)` | **`SecretWhenUnitSpellCastRestricted`** | `UnitDocumentation.lua:4612` |
| `UNIT_SPELLCAST_CHANNEL_STOP` | **yes** — `(unit, castGUID, spellID, interruptedBy, castBarID)`: an extra field **before** `castBarID`, so the spellID is the 3rd and `interruptedBy` is never touched | **`SecretWhenUnitSpellCastRestricted`** | `UnitDocumentation.lua:4626` |
| `UNIT_SPELLCAST_FAILED` / `UNIT_SPELLCAST_INTERRUPTED` | **yes** — `INTERRUPTED` = `(unit, castGUID, spellID, interruptedBy, castBarID)` | **`SecretWhenUnitSpellCastRestricted`** | `UnitDocumentation.lua:4713`, `:4741` |
| `C_Spell.GetSpellInfo(spellIdentifier)` → `SpellInfo` | **yes** — id→name resolution | `SecretArguments=AllowedWhenTainted`; `.name` through `PlainOrNil` | `SpellDocumentation.lua:415` |
| `PLAYER_REGEN_ENABLED` | **yes** — out-of-combat marker: the legal plain-read moment | — | `UnitDocumentation.lua:3890` |
| `GetTime()` | **yes** — default clock | — | `SystemTimeDocumentation.lua:56` |
| `C_UnitAuras.GetAuraDataBySpellName(unit, spellName, filter)` | **yes** — the seam that will reconcile a soulstone window out of combat (not wired in this slice, see Probes) | **`SecretWhenUnitAuraRestricted=true`**, `RequiresNonSecretAura`; `unit` is `NeverSecret`, `filter` Nilable | `UnitAuraDocumentation.lua:244` |
| `CreateFrame`, `RegisterEvent`, `RegisterUnitEvent`, `SetScript` | not rows of the generated catalogs (the frame system); the OnEnable-frame pattern is `Forte_Core/Core/Init.lua:82-86`, sim-proven by every gate run | — | pattern |

`COMBAT_LOG_EVENT_UNFILTERED` is not registered anywhere here (AGENTS.md, PLAN §2.3); every
warlock state signal above is a bag/power/cast event.

## Predicted vs read

| State | Signal | Kind |
|---|---|---|
| Shard count | `C_Item.GetItemCount` (bag/reagent count) — plain, no secrecy annotation | **read** (event-driven: `BAG_UPDATE_DELAYED`, `ITEM_COUNT_CHANGED`, `PLAYER_REGEN_ENABLED`) |
| Shard count (fallback) | `UnitPower("player", Enum.PowerType.SoulShards)` | **read**, secret-able in combat → `PlainOrNil`, and a source label, never a gate |
| Soulstone live on a target | our own `UNIT_SPELLCAST_SUCCEEDED` (name ∈ family) + the `UNIT_SPELLCAST_SENT` target name | **predicted** window (`SS-05`'s aura read is out-of-combat-only; a data `durationMs` would re-point the length, never the mechanism) |
| Soulstone bearer name | `UNIT_SPELLCAST_SENT` 2nd payload field | **read** when plain; `nil` (secret) costs the name, not the timer |
| Healthstone in bags | `C_Item.GetItemCount` over the generated `*Healthstone` names | **read** (bag reads are plain on this pin) |
| Healthstone item cooldown | `FX.Compat.GetItemCooldownInfo(itemID)` (bag item by itemID) | **read** (no `SecretWhen…` on the declared returns; the secrecy expectation is an open live probe, `docs/design-combat-procs.md §5` probe 7) |
| Ritual channel active | own `UNIT_SPELLCAST_SENT` / `START` / `CHANNEL_START` → `SUCCEEDED` / `STOP` / `FAILED` / `INTERRUPTED` / `CHANNEL_STOP` | **predicted** from cast events, self-expiring at the data's `castMs` |
| Ritual target | `UNIT_SPELLCAST_SENT` target field | **read** when plain |
| Anything about **other** players (stones, shards, who needs a summon) | — | **not modelled**: the original's data was comms (`SS-08`, `HS-02`) and per-member aura scans (`SS-05`); the comms + roster layer is Phase 6 |

`/fx status` (one line per module, `Forte_Core/Core/Init.lua`'s status loop):

```
Warlock: shards 12[bag] | soulstone Gevil 1743s | healthstone 2 cd 188.0s | ritual channeling on Alice 3.2s
```

`?` marks "never read reliably"; `(target unread)` marks a secret SENT target; `[bag]`/`[power]` is
which shard source answered.

## Live-client probe list (launch day, warlock character)

1. **P1 — shard shape (the open question).** Log the `/fx status` source label across: picking up a
   shard, spending one on `Soul Fire`/`Shadowburn`, and bagging/shuffling. Expect `[bag]` with the
   count moving 1-for-1. `UnitHasPowerType("player", SoulShards)` (raises on the sim) and
   `UnitPower("player", SoulShards)` on a shard change answer the mirror question; `[power]` in the
   status line means the bag read is the wrong half and the sources swap priority.
2. **P2 — the item-name ItemInfo.** Confirm `C_Item.GetItemCount("Soul Shard")` and
   `C_Item.GetItemCount("Healthstone")` count real items on the live client (the sim answers a flat
   `0`). A permanent `0` for an item we can see in the bags means the name form is not accepted →
   resolve the id from the hyperlink/`C_Item` family (a data row, §8) and re-probe.
3. **P3 — the soulstone window.** Cast `Create Soulstone` on a target out of combat, then
   `C_UnitAuras.GetAuraDataBySpellName("player", "Soulstone"/…, nil)` and read `(remaining, total)`
   to time the real window (and the exact aura/spell name in this build — the family is a name
   pattern precisely so a rename lands here). Our number is the **1800 s constant**, the data
   row carries no `durationMs`; the original's was `SS_TIME = 900` (`SS-01`) — record the measured
   value and wire a data/generator row (never a hand-typed id).
4. **P4 — the stone item cooldown.** Use a healthstone in and out of combat: does
   `FX.Compat.GetItemCooldownInfo(itemID)` return `(start>0, duration>0)` with the stone's real
   cooldown, and is it plain in combat? (No `SecretWhen…` on the catalog row, so "plain" is the
   expectation, not a guarantee — `docs/design-combat-procs.md §5` probe 7.)
5. **P5 — the ritual channel.** Channel `Ritual of Summoning` (5 000 ms in the data): confirm the
   event order `SENT → START/CHANNEL_START → CHANNEL_STOP/SUCCEEDED`, the SENT target *is* the
   summoning player's name, the `INTERRUPTED`/`CHANNEL_STOP` payloads carry `interruptedBy` at
   position 4 (we read only the 3rd field — a 5th-field-tolerant handler is proven in the tests),
   and that the channel prediction self-expires at the right moment.
6. **P6 — cast-event secrecy of *our own* casts** (the §8 headline risk): the
   `casts seen | plain | secret | unresolved` counters in Forte_Cooldown's `/fx status` already
   answer it for the same events; a secret spellID silently disables soulstone/ritual prediction,
   so read it in the first combat session.
7. **P7 — the soulstone aura reconcile** (the seam this slice does not wire): out of combat, does
   `GetAuraDataBySpellName` see a stone on a *group member* at all (`unitToken` is
   `UnitTokenRestrictedForAddOns`)? `true` ⇒ Phase 5 can grow the tracker to the `SS-04` bar panel;
   `nil`/secret in combat ⇒ the panel stays self-cast predicted (say so in the UI).
8. **P8 — `ITEM_COUNT_CHANGED` payload:** `itemID` of the changed item (`:1844`); if it names the
   shard item we can scope the read pass to one event per shard spent.

## Verification (2026-11-02)

- `luajit -e "assert(loadfile(...))"` — `Core/Tools.lua`, `tests/test_warlock.lua`: clean. Plus a
  luajit derivation/behaviour smoke (families, all four trackers, the secret shapes) outside the
  repo: every assertion passed.
- `run-tests Forte_Warlock` → **21 tests, 21 passed, 0 failed**, rc 0, 0 `Forte_*` error sites. The
  suite: data-derived families (`Create *` spells excluded from item lists, sorted, generation-safe
  count equality), the data-driven channel length + the soulstone fallback rule, both shard sources
  with source labels and single-source probes, secret/raising sources never overwriting, SENT
  target → SUCCEEDED window → self-expiry, stone replacement, the unread-target law, healthstone
  presence + the `anchored/cleared/secret/ignored` cooldown law, the ritual channel start/end/
  outcome/self-expiry, the `/fx status` line (one printed line, every field, and the fresh-session
  `?` shapes), the **non-warlock class gate** (no frame, no registrations) with the
  `OnClassChanged` on/off pair, the payload orders driven through the module's own event frame
  (target 2nd + spellID 4th on `SENT`, spellID 3rd on the rest, `interruptedBy` provably unread),
  `BAG_UPDATE_DELAYED`/`ITEM_COUNT_CHANGED`/`UNIT_POWER_UPDATE`/`PLAYER_REGEN_ENABLED` read-pass
  fan-out (asserted as deltas, the frame rides real events too), and the sentinel/nil/junk/raising
  id + target seams.
- Live sim probe (`--class Warlock`, dump-tree frame, 2026-11-02): `Enum.PowerType.SoulShards=7`,
  `C_Item.GetItemCount` present (name and id forms answer `0`), `UnitPower("player", 7)=0`,
  `UnitPowerType("player")=0` (Mana), `UnitHasPowerType` raises; the module's four live readers
  answer without raising and `StatusLine` renders
  `Warlock: shards 0[bag] | soulstone none | healthstone 0 | ritual idle`; 0 `Forte_*` errors.
- `scripts/gate.py --fast` → **PASS**: Forte_Cooldown 108, Forte_Core 13, Forte_Hunter 34,
  Forte_Options 44, **Forte_Warlock 21**; `lua-errors` + load probe list the `Warlock` module and
  the `Warlock` data set, 0 `Forte_*` error sites; toc pairs byte-identical, interface 16001; syntax
  OK; `[api-lint] … 4376 C_ symbols / 966 enums / 1814 events: OK`.
- `Forte_Warlock.toc` == `Forte_Warlock_Camelot.toc` (`cmp`, byte-identical, `## Interface:
  16001`), `## Dependencies: Forte_Core` (the module/clock/event helpers) and
  `## OptionalDeps: Forte_Cooldown` (its `/fx status` cast counters are probe P6's data source and
  it owns the item-cooldown read convention; `Forte_Cooldown.toc` lists `Forte_Warlock` in *its*
  OptionalDeps, so the load order between them is unordered by design). `Forte_Items` is
  deliberately **not** a dep: nothing in this addon touches `FX.Items` in this slice.

## Open items reported, not fixed

- The module prints its status line for **every** class (`Init.lua`'s loop is class-blind); the
  line is inert (`?`/`none`/`idle`) on a non-warlock, matching `Forte_Hunter`'s behaviour.
- `Core/Tools.lua` (Hunter) binds its dispatcher as `f:SetScript("OnEvent", function(...)
  onToolEvent(M, ...) end)` (`addon/Forte_Hunter/Core/Tools.lua:361`), which puts the **frame** in
  the `event` parameter — the Hunter tools' event wiring can never match an event name (its own
  tests only assert the script exists). Not this slice's file; reported to `Main`.

## UI layer (`Forte_Warlock/UI/*`, `Pages/Warlock.lua` — added 2026-11-02, agent `WarlockUI`)

Four Classic-skin frames on one shared base plus four options pages. They are **pure
renderers** of the trackers above: no frame reads a unit/aura/cooldown/bag API, and every
combat/bag payload the module's event frame receives is forwarded *unread* — an event is
only "state may have moved".

|Name|Contract|
|---|---|
|`FX.Warlock.Frame`|the shared base: the skin tables, `FormatClock`/`ClockKey` (`mm:ss`, the originals' compact clock), the `FX.db.warlockUI` position row, the lock law, the settings seam|
|`FX.Warlock.Shards`|the Shard Manager plate (34x34, the vendored `SH1` art): the shard **count**, the source label in the tooltip; shown while `Shards:Count()` is known; never time-driven|
|`FX.Warlock.Soulstone`|the Soulstone bar (140x12): `Soulstone: <target> mm:ss`, the fill draining with the window; shown while `Soulstone:Active()`|
|`FX.Warlock.Healthstone`|the Healthstone plate (34x34, the vendored `HS1` art): the count, the plate dimmed to `CooldownAlpha` with `mm:ss` under it while the creation cooldown runs|
|`FX.Warlock.Summon`|the Summon channel bar (140x12): `Summoning <target> mm:ss`, the fill running forward with the channel; lives only while the channel does|
|`:Init()` / `:Update(now)` → bool|build (idempotent) / render one pass; the return is the **10 Hz ask** (a live countdown/channel) and is the driver's only input|
|`:SetTracker(t)`|the injected state source (tests, probes); defaults to `FX.Warlock.Tools.<name>`|
|`:SetShown/RenderIdle`, `SetSize/Width/Height/Scale/Alpha/BarColor/BgColor/TextColor/ShowTime/Font/EnableMouse/SetLocked`|the live seams the pages drive|
|`FX.Warlock.UI`|module `WarlockUI`: the class gate, the event routing, `Kick`, the single driver frame, `/fx status` lines|
|`FX.Warlock.Pages.RegisterWarlockPages()`|idempotent registration of the four index cells|

**The driver law** (found live on uiforever 2026-11-02, the Hunter swing bar's bug): a hidden
frame never receives `OnUpdate`, so the frames own **no** tick script at all. `Kick` renders
each active view synchronously and the 10 Hz loop runs on `ForteXorcistWarlockUIDriver`, a
1x1, mouse-off, **always-shown** frame; `OnUpdate` is installed only while a view reports a
live countdown/channel plus a 0.5 s settle window, and cleared the moment none does.

**Settings** (module `Warlock`, defaults in `UI/Frame.lua`'s `DEFAULTS`): the shared row
(`Enable`, `Scale`, `Alpha`, `EnableMouse`, `Lock`, `ShowTime`), each frame's own switch
(`ShardEnable`, `SoulstoneEnable`, `HealthstoneEnable`, `SummonEnable`), the sizes
(`ShardSize`, `SoulstoneWidth/Height`, `HealthstoneSize`, `SummonWidth/Height`) and the
colours (`ShardColor`, `SoulstoneColor`, `SummonColor`, the plate wash `BarColor`). The
Soulstone/Summon fills ride the class's summoning purple `{.64,.21,.93}` (the 2012 mod's own
`SoulstoneColor`/`SummoningColor`), and the page defaults *read* the frames' skin tables so
the store and the frames cannot drift. The label font is not a Warlock key: it rides the
**General** page's shared `BarFont`, as `Forte_Cooldown` and the Hunter bar do. A frame's
own colour key beats the General page's shared `TextColor`/`BarColor`.

**The `/fx lock|unlock` hook**: each frame publishes its own state into `Warlock.Lock`
(store-inequality-guarded, the echo stops) and mirrors `General.GlobalLock` and
`Cooldown.Lock` — the same m4 seam the Hunter frames ride, so one `/fx lock` moves the
Warlock frames with the cooldown bar's. Locked frames are click-through. Positions:
`FX.db.warlockUI.{shards,soulstone,healthstone,summon}`.

**Verification (2026-11-02, agent `WarlockUI`)**: `run-tests Forte_Warlock` 36/36 (the 21
tool tests plus 15 UI tests: geometry, the show law on injected trackers, the label texts,
the 10 Hz ask, the kick law, real `OnEvent` dispatch, the live settings seam, the lock
mirror, the class gate, the four pages, the clock format); the gate is green (Cooldown 110,
Core 16, Hunter 37, Options 44, Timer 34, Warlock 36, api-lint OK, tocs byte-identical).
Screenshots: `docs/media/sim/fx_warlock_ui.png`, `docs/media/sim/fx_warlock_options.png`.
