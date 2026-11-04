# CodeReview8 — Iteration J (`git diff d4f64fb..9a1db90 -- addon scripts`)

Reviewer: CodeReview8 (fresh). Date: 2026-11-04 (launch day). Scope: the swing bar's three
bar modes, the clip/weave markers, the melee rail, the `ShowSafeWindow` → `BarMode` cutover —
commits `d05bcea` (β rail), `98f0b52` (γ picker), `f6eeb19` (live-check notes), `8215483`
(the α/γ marker law), `a20f182`, `9a1db90`; 15 files, ~+2 050. Every `file:line` below was read
from the working tree; the tree's `addon/` and `scripts/` are byte-identical to `9a1db90`
(`HEAD` = `686479c`, whose only delta is `PLAN.md`), so tree line numbers are the diff's.

**Headline: 3 major, 5 minor, 4 nit. No blocker.**

1. **The interlock's frozen fill is drawn in one mode's units in all three modes**
   (`UI/Swing.lua:1201-1203`). `CastingCycleFraction()` is the *remaining* fraction
   (`Core/Tools.lua:555-561`, `:687-691`) — the shrinking bar's measure. Under a live cast the
   J4 marker law is therefore **inverted** in `one`/`elapsed` (a cast that fits reads "clips"),
   over-reports "fits" by `floor × scale` in `safe`, and in `elapsed` (where the red slice is
   off) the mode's headline number — the plain cycle clock — jumps *backwards* at the press and
   freezes. The J4 suite **exempts** the interlock from the fill-edge property
   (`tests/test_swing_modes.lua:907-912`, `:948-957`), and the one pixel pin of the freeze sits
   at exactly half a cycle (`tests/test_swing2.lua:535-536`), where the two measures coincide —
   which is why the suite cannot see it.
2. **The mode migration's outcome is decided by `pairs` order** (`UI/Swing.lua:1660-1672`,
   `:1684-1696`, `:1674-1682`): the retired `ShowSafeWindow` is still pulled from the store
   while `BarMode` has a registered default, so both land in the same table and the applied
   order is the hash's, not the code's. Measured on this box's LuaJIT the legacy key is applied
   **last** (`ShowSafeWindow@11`, `BarMode@1`) — so a player's stored `BarMode` is silently
   overwritten by a pre-J legacy value at every login, the options panel keeps showing the
   stored mode, and the legacy key is never pruned (`Forte_Options/Core/Settings.lua:312-329`
   compares only *registered* keys). Adding one key to the list (K4's palette) reshuffles the
   order and can flip which key wins.
3. **A raw compare on the secret-annotated spellID** (`Core/Melee.lua:280`:
   `if a3 ~= nil …`) against the law quoted in the same file's header (`:50-52`;
   `Core/Tools.lua:993-996`: "NO raw comparison on it is legal (not even `== nil`…)", inside an
   `OnEvent` script with no pcall (`Core/Melee.lua:318-320`).

§1 findings, §2 the priority-1 deliverable (the per-mode fill/marker laws with worked
numbers), §3 the audits that came out clean, §4 counts, §5 the decisions the manager owns.

---

## 1. Findings

### F1 — MAJOR — `addon/Forte_Hunter/UI/Swing.lua:1201-1203` — the interlock freeze is mode-blind: the clip marker's reading inverts in the growing fills

```lua
    local shrinking = ST.showSafeWindow and ST.barMode ~= "one"   -- :1196
    local w
    if castLeft then
        w = (tracker.CastingCycleFraction
            and (tracker:CastingCycleFraction() * W)) or W
```

`CastingCycleFraction()` returns `c.freeze`, and `freeze = 1 - (now - self.start) /
self.duration` (`Core/Tools.lua:555-561`, surfaced by `:687-691`): the **remaining** fraction at
the press. The three fill laws it overrides read the other way, two of them with the floor
spent (`UI/Swing.lua:1209-1224`):

| mode | fill law (no cast) | the mode's own frozen value at the press | what the code freezes |
|---|---|---|---|
| `safe` | `(remaining - floor) / duration × W` (`:1220-1221`) | `(remaining₀ - floor) × scale` | `remaining₀ × scale` — **floor × scale too far right** |
| `one` | `min(W - drain × scale, W × fraction)` (`:1209-1219`) | `(1 - f) × W` | `f × W` — **the complement: inverted** |
| `elapsed` | `fraction × W` (`:1222-1223`) | `(1 - f) × W` | `f × W` — **the complement: inverted** |

The markers the fill edge is read against (`UI/Swing.lua:1337-1346`, `:1373-1379`): the
shrinking bar's marker is the length from the bar's left end, the growing bars' marker is
`(length + floor) × scale` from the right end, read "fill's edge LEFT of the marker ⇒ it fits".
The header's own words for the freeze are "freezes the fill at its **clip fraction**"
(`:1156-1157`) — the code freezes the cycle fraction, not the clip fraction.

**Scenario A — inversion (`one`/`elapsed`).** `W = 200`, cycle `4.0 s`, `aimLen = 0.5`
(`scale = 50`); the shipped data's Aimed Shot `castMs = 2000` (`Data/Hunter.lua:46`) ⇒ the
stripe is `(2.0 + 0.5) × 50 = 125` px ⇒ its left edge at `x = 75`.
* Press at `remaining = 3.9`: truth `3.9 - 0.5 = 3.4 ≥ 2.0` ⇒ **fits**. Fill freezes at
  `(3.9 / 4.0) × 200 = 195` ⇒ `195 > 75` ⇒ the marker reads **clips**.
* Press at `remaining = 0.9`: truth `0.9 - 0.5 = 0.4 < 2.0` ⇒ **clips**. Fill freezes at `45` ⇒
  `45 < 75` ⇒ the marker reads **fits**.
Exactly the inverse, for the cast's whole length (`Core/Tools.lua:548-562`, `:687-691`).

**Scenario B — the `elapsed` clock runs backwards.** `W = 200`, cycle `2.0 s`, `aimLen = 0.5`.
Press at `+1.6 s` (`remaining = 0.4`): the fill is at `160`; at the press it jumps to
`(0.4 / 2.0) × 200 = 40`, freezes for the cast, then resumes near `165`. In this mode
`showSafeWindow` is false, so the full-width red slice (`:1281-1287`) is **off**: the frozen
fill is the only cast signal, and the mode's tip sells it as "the plain cycle clock"
(`Pages/Hunter.lua:171`). On the J3 live-check that is a 120 px backward jump in a 10 Hz clock.

**Scenario C (`safe`, the shipped default).** `W = 200`, cycle `3.0 s` (`scale = 66.7`),
`aimLen = 0.5`, Aimed Shot `2.0 s` ⇒ the band is `133 px`, the true boundary `remaining = 2.5`.
Press at `remaining = 2.2`: truth `1.7 < 2.0` ⇒ clips; frozen fill `(2.2 / 3.0) × 200 = 147` ⇒
right of `133` ⇒ reads "it fit". On the J3 bow (un-hasted `2.0 s`, Aimed `2.0 s`) the band is
the full bar and a press at the cycle's first instant freezes the fill at `200` — "fits" —
where the truth is `2.0 - 0.5 = 1.5 < 2.0` ⇒ clips. The bias is exactly `floor × scale`
(`0.5 s`).

**Why the suite misses it.** `tests/test_swing_modes.lua:907-912` states the exemption ("Under
the cast interlock the FILL is FROZEN by the shipped v2 law … the fill-edge property does not
read there"), and `:948-957` pins only the marker's width/slice on those passes. The only
frozen-fill pins are `tests/test_swing2.lua:535-536` (`nearpx(w0, 100)` on a 200 px bar at
exactly half a cycle, where `f = 0.5` makes `f × W == W - f × W`) and
`tests/test_swing_modes.lua:553-556` (a press that ate the whole cycle, `f = 1`, where the band
is full-width so the reading is right by saturation). The regime the J3 live-check signed off
("cast a cast-time shot mid-cycle") is the one the acceptance does not sample.

**Fix (and its blast radius).** Carry the freeze into the mode's own measure — the same
algebra the markers ride at `:1342`:

```lua
    if castLeft then
        local f = (tracker.CastingCycleFraction and tracker:CastingCycleFraction())
        if f == nil then
            w = W
        elseif shrinking then
            -- the freeze is the REMAINING fraction; the safe fill spends the floor
            w = math.max(0, f * W - (floor or 0) * scale)
        else
            -- the growing fills draw raw progress
            w = W - f * W
        end
```

(The `floor` above is the render pass's; the press-instant floor is what the freeze wants, and
`SwingTracker:FloorAt` — `Core/Tools.lua:399-401` — is that function.) This moves pinned
pixels: `tests/test_swing2.lua:536` (`100 → 50`), `tests/test_swing_modes.lua:556` (`W → 150`
in `safe`, `→ 0` growing), and the cast-phase `FillLog` entries in `tests/test_swing3.lua`.
It changes the shipped `safe`-mode pixels the J3 live-check signed off, so **the manager owns
that call**. The zero-pixel alternative: park the clip marker under the interlock
(`clipW = 0` while `castLeft`, `:1337`) — it removes the inverted reading in the growing fills
and keeps every frozen pixel, at the cost of §7.4's "the frozen bar shows the reason it is
red" and of the interlock tint leg (`:1359-1363`). Either way, retire the exemption at
`:907-912` in favour of the law that ships.

### F2 — MAJOR — `addon/Forte_Hunter/UI/Swing.lua:1660-1672` + `:1684-1696` — the `ShowSafeWindow` → `BarMode` migration rides `pairs` order

```lua
local STORED = {
    Hunter = { "Enable", "Width", "Height", "BarColor", "BgColor",
        "ShowTime", "ShowSafeWindow", "ShowAimSlice", "ShowFlying",
        ...
        "BarMode", "ShowAimWindow", "ShowClipRegion", "ShowWeaveLine" },
```
```lua
        local out = {}
        for i = 1, #keys do
            out[keys[i]] = st:Get(module, keys[i])      -- :1690-1692
        end
        self:ApplySettings(out)                        -- :1693
...
function D:ApplySettings(tbl)
    for key, value in pairs(tbl or {}) do              -- :1674-1675
        local m = KEYMAP[key]
        if m and self[m] then self[m](self, value) end
```

`st:Get` returns the **registered default** when the store has no value
(`Forte_Options/Core/Settings.lua:439-446`), and `Pages/Hunter.lua:52` registers
`BarMode = "safe"`, so at login `out` always carries *both* mode keys: `BarMode = "safe"` (the
default) and `ShowSafeWindow = <the legacy stored value>`. `ApplySettings` iterates
`pairs(out)` — an order the language leaves unspecified — and the two keys drive the same
state through two setters (`KEYMAP:1633` → `SetShowSafeWindow:1060-1062` →
`SetBarMode:1069-1075`). The winner is the key set's hash layout.

Measured on this box's LuaJIT with the shipped key list: `BarMode` is applied at position **1**,
`ShowSafeWindow` at position **11** ⇒ **the legacy key is applied last and wins**; adding a
19th key moves them to `12` / `1` (the layout moves with the key set).

**Concrete failing scenario.** A player who ran Iteration I has `ShowSafeWindow = false` in
the profile. Iteration J: the panel's SEL row reads `Get("Hunter","BarMode")` = the registered
default `"safe"`, so the picker shows "Safe window" while the bar has been drawing the
single-phase clock all session; they pick **"One bar"** ⇒ the store gains `BarMode = "one"`.
From then on every login applies `BarMode("one")` *then* the legacy `SetShowSafeWindow(false)`
⇒ `SetBarMode("elapsed")`: the drawn mode is not the mode the picker shows, and the choice is
lost at each login. The legacy key is never cleaned — the v2 prune walks the stored keys
against the **registered** defaults and only compares a key the defaults still carry
(`Forte_Options/Core/Settings.lua:312-329`, the `def[key]` test at `:321-322`), and
`Pages/Hunter.lua:44-51` removed that default ⇒ the key lives in the profile permanently.
Flip the pair (`ShowSafeWindow = true` + `BarMode = "elapsed"`) and the same mechanism snaps
the bar back to `safe`. When K4 adds its palette key to this same list the hash layout moves —
which of the two keys wins stops being a fact of the code.

**Fix (a fold, not a shim — the clean-cutover law).** Retire the key at the login seam so the
mode has exactly one word in the pairs pass:

```lua
function D:ApplyStoredSettings()
    local st = FX.Settings
    if not st or not st.IsRegistered then return end
    -- §7.1's migration: the legacy key is a mode word, and in a pre-J profile
    -- it is the ONLY mode word. Fold it into BarMode BEFORE the pairs pass and
    -- clear it from the store, so the two keys never coexist.
    if st.IsRegistered("Hunter") then
        local raw = st._store and st._store("Hunter")
        local legacy = raw and FX.Compat.PlainOrNil(raw.ShowSafeWindow)
        if legacy ~= nil then
            raw.ShowSafeWindow = nil                        -- the key retires
            if raw.BarMode == nil then
                st:Set("Hunter", "BarMode", legacy and "safe" or "elapsed")
            end
        end
    end
```

…and drop `"ShowSafeWindow"` from `STORED` (`:1662`). `KEYMAP`'s seam (`:1633`) stays for the
live path, and `SetShowSafeWindow`'s header (`:1053-1058`) gains the line saying the login seam
is the fold. (Minimum-edit alternative: apply `STORED` in an ordered pair list and skip
`BarMode` when the raw store carries a legacy value — a presence test on `st._store`, not
`Get`, because `Get` answers with the default. Both fix the order; only the fold ends the
coexistence.)

### F3 — MAJOR — `addon/Forte_Hunter/Core/Melee.lua:280` — a raw `~= nil` on the secret-annotated `UNIT_SPELLCAST_SUCCEEDED` spellID, inside an un-guarded OnEvent

```lua
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- (unitTarget, castGUID, spellID): a1 unit, a2 guid rides UNREAD
        -- (the Tools M3 law), a3 id through the shared resolver.
        if a3 ~= nil and FX.Hunter.Tools and FX.Hunter.Tools.ResolveCastName then
            local raw = FX.Hunter.Tools.ResolveCastName(a3)
```

The file's header adopts the law (`:50-52`), and the law forbids this exact shape: the payload
spellID "is SecretWhenUnitSpellCastRestricted, so NO raw comparison on it is legal (not even
`== nil`, not even outside arithmetic — PlainOrNil's header)" (`Core/Tools.lua:993-996`).
`resolveCastName` was built for precisely this payload — lookup, truth test and field read
inside one pcall, only a plain string leaving it (`Core/Tools.lua:1003-1011`) — so it needs no
nil gate in front of it, and Tools' own dispatcher runs it bare:
`local name = canonicalName(resolveCastName(a3))` (`Core/Tools.lua:1087-1091`). The rail's
dispatcher is installed as a bare script body (`Core/Melee.lua:318-320`; no pcall — and AGENTS
forbids `FX:CallSafe`).

**Failing scenario.** On a client in the `RestrictedActions` regime every player
`UNIT_SPELLCAST_SUCCEEDED` carries a wrapped (secret) spellID ⇒ the raw `a3 ~= nil` raises
from inside the frame script ⇒ a Lua error per cast and the Raptor Strike re-arm — the rail's
whole reward — never runs. The sim's payloads are plain numbers
(`tests/test_melee.lua:339-341` drives `script(f, "UNIT_SPELLCAST_SUCCEEDED", "player", "G2",
raptorID)`) ⇒ green suite, red client, and it spends the 100-error budget (AGENTS §2.3).

**Fix** — mirror Tools' dispatcher:

```lua
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local T = FX.Hunter.Tools
        if T and T.ResolveCastName then
            local raw = T.ResolveCastName(a3)      -- nil for nil / secret / raise
            if raw then
                local canon = T.CanonicalCastName
                local name = (canon and canon(raw)) or raw
                t:OnCastSucceeded(a1, name)
            end
        end
```

(`a1`, the unit token, is plain per the catalog's unit-only payloads: the file's `~= "player"`
gates at `:182`, `:192` are legal, and `OnSwingStart`'s duration already rides `PlainOrNil` at
`:169`.)

### F4 — MINOR — `addon/Forte_Hunter/UI/Swing.lua:1204-1208` — the proven-flight phase reads "a cast-time shot fits" against the J4 oracle's truth, and the J4 property never drives a flight

```lua
    elseif ST.showSafeWindow and phase == "flying" then
        -- … the WHOLE bar rides white from SUCCEEDED to the next
        -- PLAYER_SWING re-arm -- the safe-to-move state, not a sliver.
        w = W
```

The J4 oracle is `fillEdgeOnFittingSide(marker) == remaining - floor >= K`
(`tests/test_swing_modes.lua:896-905`). In flight `remaining = 0` ⇒ both truths are false,
while `w = W` puts the edge on the fitting side in the shrinking direction (`safe`:
`fillW >= clipRight` ⇒ true; the growing bars read false, so they stay consistent). In the
shipped default mode the full-width white bar plus the standing band therefore read "press
Aimed Shot" through every proven flight, where the law's truth is "there is no cycle left to
fit it in".

The pixels are defensible (the shot has left the gun; the mode's tip says "move/cast freely",
`Pages/Hunter.lua:187-189`) — **the finding is the acceptance's hole**:
`tests/test_swing_modes.lua:936-941` drives only `SENT` and `FAILED_QUIET`, and
`Core/Tools.lua:654` is the only writer of `self.flying` (Auto Shot's `SUCCEEDED`, read at
`:702-706`/`:735`), so `phase == "flying"` is never sampled by the property — while the parity
cycle does drive it (`tests/test_swing_modes.lua:694-699`). "Sampled across a whole cycle" is
met only for cycles with no proven flight.

**Fix.** Write the phase as the documented exception of the law (`UI/Swing.lua:1152-1159` and
the test's law block) and add a `{ mode = …, flight = true }` scenario to `propertyCycle`
driving Auto Shot's `SENT`/`SUCCEEDED`, asserting the white full bar and the markers'
documented reading. (Removing the exception — a `phase ~= "flying"` guard on `w = W` — changes
the shipped "cast freely" signal: a manager decision, not a drive-by.)

### F5 — MINOR — `addon/Forte_Hunter/UI/Swing.lua:748-759` — engine-fill parity for mode `one` is claimed and unproven; the arm ignores the standing region's cap in the gate-shut tail

```lua
    elseif ST.barMode == "one" then
        -- … the cap IS W x progress (progress = 1 - remaining/duration,
        -- the region's width is aimLen x scale), so the cycle's elapsed
        -- arm over the full width is algebraically the whole curve, cap
        -- included.
        kind = "elapsed"
        start, dur = tracker.start, tracker.duration
```

The v2 law caps: `w = math.min(W - drain * scale, W * fraction)` (`:1209-1219`), `drain = aim`
whenever the phase is not `"aim"`. The cap binds ⇔ `remaining < drain`, which is reachable
*with* phase `"reload"`: `CycleState` takes the `"aim"` branch only on an open readiness gate
(`Core/Tools.lua:724-740`), so a gate that shuts near the cycle's end leaves phase `"reload"`
with `remaining ≤ floor`. Concretely — mode `one`, cycle `2.0 s`, `W = 200`, `aimLen = 0.5`
(`scale = 100`), the player starts moving inside the wind-up, sample at `remaining = 0.3`: the
v2 fill is `min(200 - 50, 170) = 150`, parked at the standing region's left edge; the engine's
elapsed arm is at `170` and runs to `200` — inside the region, the one thing §7.2's cap exists
to prevent. The paths differ by up to `aimLen × scale` in that window.

The parity leg cannot see it: its fill column is `Swing._fillIntent`
(`tests/test_swing_modes.lua:705-710`), and `_fillIntent` is the v2 law's own number, recorded
on both paths *before* `_EngineFillPass` runs (`UI/Swing.lua:1230-1241`) ⇒ the column is equal
by construction. The engine's real geometry (`_fillSpanW`, the armed kind/target) is pinned only
by `tests/test_swing3.lua`'s `FillLog` legs, which predate the modes (untouched in this range),
so the `one` arm has no arm-level pin. Minor today because `_fillMode` is `"lua"`
(`UI/Swing.lua:276`); it becomes F1-class the day the launch probe flips the default.

**Fix.** In the `one` arm, use a static arm exactly where the cap binds:

```lua
    elseif ST.barMode == "one" then
        local aim = tracker.aimLen or 0
        if phase ~= "aim" and remaining <= aim and tracker.duration > 0 then
            kind = "value"
            target = (W > 0)
                and ((W - aim * (W / tracker.duration)) / W) or 0
            dir, start, dur = self._dirs.remaining, now, 0
            key = "v1|" .. armNum(target) .. "|" .. armNum(aim)
        else
            kind = "elapsed"
            dir = self._dirs.elapsed
            start, dur = tracker.start, tracker.duration
            key = "n|" .. armNum(tracker.start) .. "|" .. armNum(tracker.duration)
        end
```

and add `Swing._fillSpanW` (with the armed kind) to the parity observation so a future arm
divergence is visible.

### F6 — MINOR — `addon/Forte_Hunter/tests/test_swing_modes.lua:1025-1055` — the floor's *retry* term is never probed: no scenario has a live cast and an open retry together

The marker laws carry the floor only in the growing modes (`UI/Swing.lua:1342`
`span = shrinking and castSec or (castSec + (floor or 0))`, `:1375`
`budget = gcdSeconds() + (shrinking and 0 or (floor or 0))`), and the floor is
`aimLen + max(0, retryUntil - now)` (`Core/Tools.lua:399-401`). No scenario in the property
table sets `castAt` and `retryAt` together (the legs at `:1025-1035` set one or the other), and
inside the oracle the floor cancels — the truth subtracts it (`(remaining - floor) >=
clipSec`, `:961`) and the marker adds it — so with a constant floor the pair is self-proving.
Consequence: a regression that drops `+ (floor or 0)` (and with it the J4 fix that made the
stripe ride the *decaying* floor instead of the constant `aimSec`) passes every scenario in
the file, and in the growing modes the "no room" clamp (`x > 0 and x < W`, `:1377`) moves to
the `+ aimLen` boundary — the difference between "line just off the bar" and "line on the bar"
on the same cycle.

**Fix.** One scenario with both events in one cycle, e.g.
`{ mode = "one", dur = 2.6, base = 2.0, castLen = 0.8, castAt = 1.2, retryAt = 1.0 }` and
`{ mode = "elapsed", dur = 2.6, base = 2.0, castLen = 0.8, castAt = 1.3, retryAt = 1.2 }`: the
frozen passes then assert the decaying stripe span `(castLen + floor) × scale` with
`floor > aimLen`, and the non-frozen passes cross `remaining - floor == gcd` twice while the
floor decays.

### F7 — MINOR — locale coverage: no test drives a localized Raptor Strike through the rail, and the alias map covers only the data's single rank

`Core/Melee.lua:191-193` gates on the canonical name (`if name ~= RAPTOR_STRIKE then return`,
the key declared at `:78`), fed by `ResolveCastName` + `CanonicalCastName` (`:280-287`). The
mechanism is right: `Locale.BuildSpellAliases` walks the shipped rows and aliases
`Locale.SpellNameForID(row.id) → row.name` (`Core/Locale.lua:221-260`) and runs at the Locale
module's `OnEnable` (`Core/Locale.lua:400-404`), before any Hunter LoD page. The coverage is
the gap: `tests/test_melee.lua:316-341` drives the English key and the data's own id, and
`test_locale_hunter.lua` has no Melee row at all — the AGENTS locale law's test leg ("the
localized Raptor Strike name resolves; test on a localized build") is unowned for the rail
added in this range.

**Concrete failing scenario (a test gap; a live gap only on localized sub-ranks).** A French
Hunter casts Raptor Strike **Rank 5** (`415338`): the shipped data carries only Rank 8
(`Data/Hunter.lua:63`, `:143`), so the alias map holds only Rank 8's localized name ⇒
`CanonicalName` passes the Rank-5 string through ⇒ `name ~= RAPTOR_STRIKE` ⇒ no re-arm. On an
English client the ranks share the bare name ⇒ fires. A localized sub-rank cast silently loses
the rail's reward.

**Fix.** (a) A `test_locale_hunter.lua` case: `Locale.stubLocale = "deDE"`, the spell map for
the Raptor rows, `Tools.CanonicalCastName(<localized>) == "Raptor Strike"`, and the
real-script leg (`tests/test_melee.lua:339`'s shape) with the localized name re-arming the
clock. (b) For the rank family, the sanctioned id-first leg in the dispatcher —
`Locale.RankIDsForName("Raptor Strike")` (`Core/Locale.lua:171-174`) — reading the payload id
*inside* the resolver's pcall, never as a raw compare (F3's law).

### F8 — MINOR — `addon/Forte_Hunter/UI/Swing.lua:1489-1513` — the standing clip marker's cast length is the data's only cast-time row in the set

```lua
local CLIP_SHOT_NAMES = {
    ["Aimed Shot"] = true, ["Multi-Shot"] = true, ["Steady Shot"] = true,
}
...
        local castSec = castLen or self:ClipCastSeconds()
```

`ClipCastSeconds` (`:1498-1513`) takes the longest `castMs` in that set; the shipped data has
`castMs = 2000` for Aimed Shot (`Data/Hunter.lua:46`) and **no `castMs`** for Multi-Shot
(`Data/Hunter.lua:61`), and the file's own note says so (`:1486-1488`). So with nothing casting
the standing marker is the Aimed Shot length for every build. The J4 tests pin this as the
intended law (`tests/test_swing_modes.lua:479-499`, `:501-527`) and §7.4 names the same source,
so this is a scope gap, not a law break: a Steady / Kill / Explosive Shot player reads a marker
that is not their shot's length, while the row's tip promises "The mark is **that shot's** cast
time" (`Pages/Hunter.lua:175-177`). Launch probe: which cast-time shots a Forever Hunter
actually learns; if Steady is one of them the *set* is the thing to widen, not the marker.

### F9 — NIT — `addon/Forte_Hunter/UI/Swing.lua:226-241` — `gcdSeconds`'s no-data fallback is the magic number the law says is data-owned

```lua
    gcdSecCache = (best and best / 1000) or 1.5
    return gcdSecCache
```

Everything else in the file reads the data (`D.GcdSeconds = gcdSeconds` at `:242` exists so the
tests read the same number, `tests/test_swing_modes.lua:583-584`). The fallback fires only when
the data table is absent — and then the weave line keeps drawing at a hard-coded 1.5 s law,
including its `x > 0 and x < W` clamp (`:1377`). The file's own convention for "no number" is
*no signal* (`scale > 0`, `aimSec > 0` gates). **Fix:** return `nil` and gate the line (the
`:1373-1379` block already tolerates a nil `budget` behind one `if gcd then`). The J4 "no magic
numbers" law.

### F10 — NIT — `Core/Melee.lua` + `Pages/Hunter.lua:181-183` — the rail's tip promises more than the gate

`_GateOpen` asks the range meter only while the light is enabled (`UI/Melee.lua:234-245`), and
`ShowRangeLight` ships off (`Pages/Hunter.lua:63`), so with the rail on and the light off — the
shipped pair — the gate is in-combat-only, while the row's tip reads "your main-hand swing,
shown only in melee range". The rail's clock is the de-facto band gate (a main-hand swing and a
Raptor Strike both need melee), so the exposure is the ≤ one-swing tail after leaving the
band. §7.5's gate is implemented exactly as specified ⇒ the tip's wording is the thing to fix
("in melee combat"), not the gate.

### F11 — NIT — `Core/Melee.lua:78` — an exact canonical compare for the reset gate

`if name ~= RAPTOR_STRIKE then return end` (`:193`) is correct on English clients (the ranks
share the bare name, verified against the data's Raptor family, `Data/Hunter.lua:63`, `:143`).
The localized sub-rank gap is F7(b); the id-first fix rides the same seam.

### F12 — NIT — `UI/Swing.lua:1060-1075` — the subsumed twin state

`SetBarMode` writes `ST.showSafeWindow = (mode ~= "elapsed")` and `SetShowSafeWindow`
delegates to it, so the pair can not disagree on the live object (`:1069-1075`, and the
`ShowSafeWindow` header `:1053-1058` states the retirement). The residual is that the *live*
key is still a reachable input (`KEYMAP:1633` plus the store's `OnChange` fan-out,
`Forte_Options/Core/Settings.lua:485`), so two fields keep carrying one fact. F2's fold retires
the last real use of the seam; after that the pair can go.

### F13 — NIT — doc drift: `docs/research/wst-swing-design.md:670-671` states the clip reading backwards

"Reading: fill's right edge **right of** the stripe's left edge ⇒ press it; inside the stripe
⇒ you clip" — the inverse of the shipped law (`UI/Swing.lua:1324-1336`,
`Pages/Hunter.lua:175-177`, `tests/test_swing_modes.lua:969-974`). J4's code and tips are right;
the scout note is the stale one, and K1 owns the docs row ⇒ a one-line fix there.

---

## 2. Priority 1: the marker meanings per mode, derived and checked

Laws as shipped — `W` the bar's width, `scale = W / tracker.duration`,
`floor = aimLen + max(0, retryUntil - now)` (`Core/Tools.lua:399-401`),
`aimLen = 0.5 × duration / baseSpeed` (`Core/Tools.lua:313-317`), `gcd = 1500 ms`
(`Data/Hunter.lua:60`, `:63`):

| signal | `safe` (shrinking) | `one` / `elapsed` (growing) |
|---|---|---|
| fill | `(remaining - floor) / duration × W`, left-anchored, `W` in flight | `min(W - drain × scale, W × fraction)` / `fraction × W` |
| clip marker | left-anchored band `castLen × scale` (`:1342`, `:1352-1354`) | right-anchored stripe `(castLen + floor) × scale` (`:1342`, `:1355-1357`) |
| weave line | centre at `gcd × scale` from the left (`:1375-1376`) | centre at `W - (gcd + floor) × scale` |
| "fits" reading | fill's right edge **right of** the marker | fill's right edge **left of** the marker |

**Derivation (non-interlock, unclamped).** `safe`:
`fill = (remaining - floor) × scale ≥ castLen × scale ⇔ remaining - floor ≥ castLen` ✔ exact.
Growing: `fill = (1 - remaining/duration) × W ≤ W - (castLen + floor) × scale ⇔
remaining ≥ castLen + floor` ✔ exact. The weave line is the same algebra with `gcd`, so the J4
claim "one marker answers one question the same way in every mode" **holds exactly** for every
non-interlock pass in all three modes ✔ — including the open-retry case, where the floor is
time-varying and rides both sides identically (the property's retry legs,
`tests/test_swing_modes.lua:1025-1035`).

**Clamped cases.** `castLen ≥ duration` saturates both markers to `W`: the growing stripe's
left edge is the bar's left edge ⇒ "clips" everywhere, and the truth is
`remaining - floor ≤ duration - floor < castLen` ⇒ never fits ✔. The `safe` band is full-width
while the fill tops out at `(duration - floor) × scale < castLen × scale` ⇒ never outgrown ✔
(the shipped-data case, `tests/test_swing_modes.lua:501-527`).

**Haste.** `duration` and `aimLen` are fixed at the cycle's `PLAYER_SWING`
(`Core/Tools.lua:313-317`) and `scale` rides the same `duration`: a mid-cycle haste change
moves nothing until the next swing, and the fill, the region, the stripe and the line all move
together ✔ (`gcd` and `castLen` are un-hasted constants by §7.9's law ✔).

**0 / absent cast lengths.** `castSec = castLen or ClipCastSeconds()`; both nil ⇒ `span` nil ⇒
`clipW = 0` ⇒ both textures parked (`:1337-1346`) ✔; instant rows carrying `castMs = -1000000`
(`Data/Hunter.lua:64`) are filtered by the `ms > 0` test (`UI/Swing.lua:1505`) ✔; a missing
`gcdMs` is F9's fallback. Under a live cast `castLen` is never nil (`CastRemaining` returns the
length with the seconds, `Core/Tools.lua:673-685`) ✔.

**Bar resize.** `SetSize` drops `_aimRegionW/_aimRegionA/_clipW/_clipBandW/_clipA` and forces
the weave with the `false` sentinel, never `nil` (`:955-961`) ⇒ the next pass re-sizes and
re-pins every marker ✔; the band's build-time `TOPLEFT` pin (`:609`) and the stripe's
build-time `TOPRIGHT` pin (`:601`) each have exactly one `_SetSlice` call site (`:1352-1357`)
⇒ the sim's "one SetPoint per texture per frame" law holds ✔. The rail follows the bar's
`Width` key (`UI/Melee.lua:386-390`) ✔, the weave line's overshoot height re-sizes ✔.

**Interlock.** The freeze breaks the reading in all three modes ⇒ **F1**.

---

## 3. Audits that came out clean

**Secret-value sweep (priority 2).** Every client read in the new files passes pcall +
`FX.Compat.PlainOrNil` before any compare/arithmetic: `Core/Melee.lua:105-144`
(`UnitAttackSpeed`'s returns, the `issecretvalue` probe itself inside a pcall at `:136-139`),
`:167-176` (`PLAYER_SWING`'s duration via `PlainOrNil`, `> 0` on the plain copy), `:82-89`
(`Enum.PlayerSwingType.MainHand` through the pcall+plain idiom, the catalog `0` as fallback),
`:182`/`:192` (unit tokens: plain per the catalog's unit-only payloads),
`UI/Melee.lua:215-228` (`InCombatLockdown` — the same call Tools makes plainly at
`Core/Tools.lua:71-77`; the rail's leg is the stricter pcall+`PlainOrNil` shape),
`UI/Melee.lua:238-241` (the meter's band behind a pcall), `:251-291` (the text/throttle on the
tracker's own numbers). `UI/Swing.lua`: the alpha pair, `gcdSeconds` (data),
`ClipCastSeconds` (data, `:1498-1513`), and all marker arithmetic (tracker/data numbers). The
one violation in the range is F3.

**Priority 3 (hidden frames, tickers, event registration).** `UI/Melee.lua:113-116` — `Init`
returns before any `CreateFrame` while the rail is off; `Core/Melee.lua:302-323` — the event
frame is created inside `EnableEvents`, which `RefreshEvents` (`:350-364`) gates on class +
`rail.state.enabled`, so off ⇒ no registrations (`tests/test_melee.lua:61-62` pins the off law,
`:385-396` the out-of-combat/no-ticker law); the rail's ticker exists only between `Show` and
`HideNow`/`SetEnabled(false)`/`StopTicking` (`UI/Melee.lua:293-309`, `:313-336`, `:350`) — no
OnUpdate on a hidden frame ✔. `UI/Swing.lua` adds no event frame; its ticker is
`Kick`/`RenderIdle`-paired (`:1574-1600`); the three new textures are parented to the bar's
anchor (`:595-625`), so the bar's `Enable` gate is their gate ✔.

**Priority 4 (defaults, the sparse-store law).** `BarMode`, `ShowAimWindow`, `ShowClipRegion`,
`ShowWeaveLine`, `EnableMeleeRail` are registered in exactly one table, inside the
`if not O.pages["Hunter"]` guard (`Pages/Hunter.lua:36-80`, `:118-122`) ⇒ no second `Register`
replacing a default set; the section's `keys` list carries the new rows (`:200-206`) and the
row-count pins move with them (`tests/test_swing.lua:551-557`); the module's own defaults
(`UI/Swing.lua:255-268`, `UI/Melee.lua:85`) equal the pages' defaults, so the store's
default-equal pruning (`Forte_Options/Core/Settings.lua:454-461`) keeps profiles sparse ✔.

**Priority 5 (the melee gate, the Raptor name).** The gate is in-combat AND (the light off OR
the band `== "melee"`) AND not parked, with a nil band = closed (`UI/Melee.lua:230-245`) —
implemented as `docs/research/wst-swing-design.md` §7.5 specifies; `EnableMeleeRail` defaults
off (`Pages/Hunter.lua:56`) ✔. Name resolution rides `ResolveCastName` → `CanonicalCastName` →
the data key ✔ (the rank/coverage caveats: F7, F11). FULL = ready, no `fill_empty` toggle, per
§7.5's non-goals ✔.

**Priority 6 (the engine path).** `castLeft` and the flight arm are `value` arms on `w / W`,
carrying the v2 law's number ⇒ parity is structural there ✔; `safe`'s span arm and `elapsed`'s
elapsed arm are the v2 curves ✔; mode `one`'s arm is F5.

**J3/J4 live-check claims.** The J3 note's three readings are consistent with the laws at its
own numbers (3.0 s cycle, Aimed 2.0 s, `aim = 0.5` ⇒ a `1.67 s` stripe; `2.0 s` of `2.2 s`
remaining ⇒ fits ✔). The J4 note's "the stripe retargets to the live cast's length" matches
`:1339` ✔. Both notes sample pre-press only — the regime F1 lives in.

---

## 4. Counts

| Severity | Count | Findings |
|---|---|---|
| Blocker | 0 | — |
| Major | 3 | F1, F2, F3 |
| Minor | 5 | F4, F5, F6, F7, F8 |
| Nit | 4 | F9, F10, F11, F12 (F13 = docs row) |

Test-coverage holes: F4 (no flight sample), F6 (cast + retry never co-occur), F7 (no localized
Raptor leg), F5 (the parity column is path-independent by construction; no arm-level pin for
the `one` arm).

---

## 5. Decisions for the manager (Iteration K sequencing)

1. **F1**: convert the freeze into the mode's measure (a `safe`-mode pixel change under a live
   cast: `tests/test_swing2.lua:536`, `tests/test_swing_modes.lua:556`,
   `tests/test_swing3.lua`'s cast-phase `FillLog`) **or** park the clip marker under the
   interlock (zero pixels, §7.4's interlock sentence retires). Whichever ships, the property
   test's interlock exemption (`tests/test_swing_modes.lua:907-912`) is replaced by the law.
2. **F4**: is "full-width white ⇒ a cast-time shot fits" the shipped meaning of the flight
   phase? If yes, write the exception into the law + a test leg; if no, gate the `w = W` branch.
3. **F2**: fold the legacy key at the login seam (preferred, one place) vs an ordered
   `ApplySettings` — decide before K4 adds its key to the same `STORED` list.
4. **F8/F10**: launch-day probes only (which cast-time shots a Forever Hunter learns; the
   rail's tip wording).

Every quoted line was read from the working tree on 2026-11-04; the tree's `addon/` and
`scripts/` are byte-identical to `9a1db90`.
