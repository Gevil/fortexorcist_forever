# Profiles, the SavedVariables schema and `/fx reset`

Written 2026-11-02 (iteration H, slice H3). Code: `Forte_Core/Core/Database.lua`
(the `ForteXorcistDB` schema), `Forte_Options/Core/Settings.lua` (the value
layer + `FX.Profiles`), `Forte_Options/Pages/Profiles.lua` (the page),
`Forte_Options/UI/Window.lua` (the profile tab row). Original = the law:
`/tmp/fxref/Forte_Core/Forte_Core.lua`, `Forte_Core/Options.lua`,
`Forte_Core/Localization.lua`. Spec rows: FE-21, FE-22, FE-23, OP-02, OP-04.

## 1. What the original did

| Law | Anchor |
|---|---|
| The saved table carries `Profiles = { Active, Characters[name]=index, Instances[settings], Data[{name}], Links[] }`: profiles are one "instance tree", the same primitive as a per-module frame clone | `Forte_Core.lua:1331`, `:2129-2160` |
| A version stamp `VERSION` + an ordered ladder of `if FX_Saved.VERSION < "v1.9xx" then ... end` blocks that rewrite the saved structures, run once per install in `FW_Variables`, with the standing instruction *"always use real values for defaults in modules, since these defaults/modules may not be loaded"* | `Forte_Core.lua:1332`, `:1367-1583` |
| A too-old install gets a popup offering a full wipe, and the addon then unregisters every event, empties `FW.Settings` and returns (`FW:UnregisterAllEvents(); FW.Settings = {}; return`) | `Forte_Core.lua:1374-1384` |
| Which profile a session rides: `if FW.Saved.Profiles.Characters[FW:FullName()] then UseProfile(that) else UseProfile(Profiles.Active) end` — i.e. **per character by default**, keyed `Name-Realm` (`FW.PLAYER.."-"..FW.SERVER`) | `Forte_Core.lua:1078-1084`, `:1074-1076` |
| `FW:UseProfile(index)`: validate the index (fall back to `Active`, then 1), store `Profiles.Active` + the character binding, swap `FW.Settings` to the profile's table, re-copy the defaults over it (`FW_CopyNew(FW.Default, FW.Settings)`), then `FW_InitClones(); FW:RefreshFrames(); FW:BuildOptions(); FW:RefreshOptions()` — the switch is applied to the live frames and the panel at once | `Forte_Core.lua:2142-2162` |
| Profiles are created as copies of the current settings, deleted through a confirmation popup (the delete fixes the `Characters` bindings), renamed in place; the tab row is the switcher, drawn from `Profiles.Data` with `root.Active` highlighted; delete is gated on `#root.Data > 1` (the last profile can not go) | `Options.lua:5454-5469`, `:5471-5500`, `:4849-4901`, `:5535`; `Forte_Core.lua:2100-2127` |
| The strings: `PROFILES` / `PROFILES_CURRENT` / `PROFILES_CURRENT_TT` ("[delete current] deletes the profile you are currently using… [create new] copies your current settings to a new profile") | `Localization.lua:339-341` |
| Per-frame geometry (`lock/alpha/scale/x/y`) is stored **inside** the profile's settings under the frame's name (`FW.Settings[frame.name]`) | `Forte_Core.lua:2013-2039` |
| Slash surface is one `Commands[word]` table: `reset`, `resetall` (which wipes by writing `FX_Saved = {RESETTING=true}` and reloading), `profile <name>` | `Forte_Core.lua:2344-2346`, `:2384-2399` |
| The option tree's `BTN` widget type (one of the 17 shipped types) is a labelled action row | spec OP-02 (`Options.lua:4099-4116`) |

**Not ported** (and why): the `Links` layer of FE-21/OP-05 (profile↔clone option
linking, `Options.lua:96-260`, `:484-492`) is a second settings system of its
own, ~10× the size of the profile model, and it has no live UI in this build
(no per-module frame clones yet). The frame-clone half of the original's
"instance tree" is a Wave-2/3 item; `db.profiles.byName[name] = { settings = … }`
is deliberately a *wrapper row*, so a later `clones` key can join it without a
new schema step.

## 2. The `ForteXorcistDB` schema (`Forte_Core/Core/Database.lua`)

```
ForteXorcistDB = {
  version  = 2,                          -- numeric schema stamp
  defaultsPruned = { Cooldown = true, General = true, ... },  -- v2 marker (below)
  profiles = {
    perCharacter = true,                 -- false => the whole account rides `shared`
    shared  = "ForteXorcist",            -- the account-wide profile's name
    active  = "Name-Realm",              -- the profile this session rides
    characters = { ["Name-Realm"] = "Name-Realm" },   -- who rides what
    byName  = { ["Name-Realm"]  = { settings = { [module] = { [key] = value } } } },
                ["ForteXorcist"] = { settings = … } },
  },
  probes = {…}, probesEvents = {…}, diag = {…}, probeEpoch = n,   -- Forte_Core/Probe.lua
  cooldownDisplay = {…}, cooldownSplash = {…},                   -- Forte_Cooldown
  hunterSwing = {…}, hunterReminder = {…},                       -- Forte_Hunter
  timer = {…},                                                   -- Forte_Timer
  optionsPos = {…},                                              -- Forte_Options
}
```

* **Numeric** versions, not the original's string compare (`FX_Saved.VERSION <
  "v1.90"`, `Forte_Core.lua:1374`): that ladder is on record growing a branch to
  fix itself. A DB stamped *above* this build is from a newer build: the ladder
  skips, the shape guard repairs, the stamp is kept (a downgrade re-runs
  nothing).
* **The ladder runs in the bootstrap's `ADDON_LOADED` handler**
  (`Forte_Core/Core/Init.lua`), i.e. after every `Forte_*` file has been parsed
  and before any module reads `FX.db`. A migration therefore never races a
  reader, and a broken step can not take the login down:
* **A step never propagates.** Each step runs in a pcall; the version stops at
  the last step that completed, the failure prints once, and every reader falls
  back to its registered defaults. The original's answer (unregister all
  events, empty the settings, show a popup) is a build that shows nothing — a
  bug report, not a fix.
* **Steps are idempotent**: each recognises its own input shape, so a retried
  login picks the install up where it stopped.
* **`FX.DB.Guard`** runs on every login (from `Migrate`, and from the value
  layer) and repairs *shape*: a string where a profile belongs is dropped, a
  profile without a `settings` table gets one, a non-table `characters` map
  starts empty, a `perCharacter` that is not a boolean becomes the default, an
  `active` naming a profile that is not there is cleared. It is a shape fix, not
  a type law: values it does not understand are left for the value layer, which
  is the only place the registered defaults exist.
* **v1**: today's flat `db.settings[module][key]` map becomes
  the profile named `Name-Realm`, plus a copy under `ForteXorcist`; the v0 map
  is *removed* (no second live table for the same settings). A fresh install
  gets the same shape with empty settings.
* **v2 (the default prune, wave 5 2026-11-03)**: the old value layer *seeded*
  every registered default into every profile table, so a profile carried
  every key — the untouched ones frozen at the defaults of the build that
  wrote the file (the uiforever probe: all 8 General keys on a player who
  only ever set `Cooldown.Width`; a shipped `AltTimeFormat = true` that never
  reached a profile carrying the old `false`). The layer is now sparse (see
  §3); this step drops, over every profile, every stored value **equal to its
  current registered default**. A stored value that *differs* from the
  shipped default survives: it is indistinguishable from a user choice
  (data loss is the worse failure). The step is LAZY BY MODULE: the ladder
  runs at `ADDON_LOADED`, the load-on-demand pages register at
  `PLAYER_LOGIN`, so the step prunes the modules registered by then, writes
  their names into the marker table `defaultsPruned`, and
  `FX.Settings:Register` prunes every later registration at its
  registration. A module no session registers (a class that is not the
  player's) is pruned in the first session that registers it — until then
  its stored default reads identically to the default, so nothing hangs on
  the timing.
* **Frame geometry** (`cooldownDisplay`, `hunterSwing`, `timer.display`,
  `optionsPos`, …) is **not** profile data: a dragged bar stays where it is
  across a profile switch. The original stored it *inside* the profile
  (`Forte_Core.lua:2013-2039`), which is what made its profile copies carry
  frame positions. Moving geometry into the profile is a separate schema
  step (v3) and needs a decision per module — it is not part of H3.

## 3. The value layer (`Forte_Options/Core/Settings.lua`)

`FX.Profiles` is the profile API on top of the store; `FX.Settings` is
unchanged in its public contract (Register/Get/Set/OnChange/Reset/GetDefault)
— the store it reads is now the active profile's table.

* **The store is SPARSE** (wave 5, 2026-11-03): a profile's module table
  carries **only the values that differ from the registered defaults**.
  Reading an unset key fills the default in (`Get` returns a deep copy of
  the registered value and writes nothing); `Set` of a value **equal to the
  registered default (deep equality — the colour rows) deletes the stored
  key** and notifies the listeners exactly as a write does. `Reset` is
  therefore the *removal* of the module's stored keys plus the notify, and
  the effective value is the shipped one. The whole window built and a
  `/reload` pass over such a store leaves no default-valued key anywhere
  (the law `test_profiles.lua` scans); a shipped default the build moves
  reaches every profile that never set the key — the frozen
  `AltTimeFormat = false` a live profile carried under the shipped `true`
  is the defect this law ends. `P.ApplyLive` pushes, per module, every
  *registered* key's effective value (stored, else default), so a key the new
  profile does not store moves its consumers back to the default, and the
  switch self-cleans the profile it switches into. A profile copy (`Create`,
  the sharing copy) copies **explicit values only**: the new profile shares
  every unchanged key with the registration.
* **Key sanity.** The first time this session reads a `(profile, module)` pair,
  its keys are type-checked against that module's **registered defaults**: a
  value whose type does not match the default's, a key the module does not
  register, and a non-table module block are dropped, and the unseeded store
  serves the default from the registration. A repaired module prints one chat
  line ("repaired N saved value(s) of Cooldown in the profile X; they are
  back on their defaults",
  once per pair per session) — a silent repair reads as "my settings vanished
  at the update". `FX.Settings.DroppedKeys()` counts them for the tests. A module that is not registered *in this session* is left
  completely alone — with `## LoadOnDemand: 1` a Hunter page registers its
  module only on a Hunter, so "unknown" there is another class's data, not
  corruption (dropping it would be data loss). A **rename** is a migration step
  (copy `old → new` before the defaults reseed), never this pass: the pass is
  what makes a hand-edited file readable again, which is exactly the original's
  `FX_Saved.X = nil -- no longer used` idiom (`Forte_Core.lua:1400-1427`) moved
  from per-version code into one general pass.
* **Live switching.** `P.Select(name)` writes the new active profile and pushes
  the new profile's every key through `Settings:Set` — the same notification a
  checkbox click produces. There is no second apply path to keep in sync, which
  is `FW:UseProfile`'s `FW_CopyNew` + `RefreshFrames` + `RefreshOptions`
  sequence (`Forte_Core.lua:2155-2161`) in this build's idiom.
* **Bindings.** `characters[key]` is written only while per-character mode is on,
  so turning sharing on (which moves the session to the shared profile) leaves
  every character's binding intact and turning it off returns each character to
  the profile it rode. Deleting a profile rebinds every character that pointed
  at it, as the original's delete popup does (`Options.lua:5476-5489`).
* **The last profile can not be deleted** (`Forte_Core.lua:2100`), and names are
  trimmed, capped at 32, case-insensitively unique, and rejected for `|` and
  control characters (a profile name is printed into tooltips and chat).

## 4. Where the UI sits

The original had **no Profiles cell in its module grid**: `SetMainCategory`
carries the profile tabs for the General category
(`Forte_Core/Options.lua:5535`, drawn at `:4849-4901`), and the module grid is
the module list. So:

* the **tab row under the title bar** of the options window is the switcher
  (`Window.lua:RefreshProfileTabs`): a `Profiles` opener + one tab per profile,
  the active one gold, a click switches live, past `MAX_TABS` the row folds
  into a `...` tab onto the page;
* the **Profiles page** (`Pages/Profiles.lua`) is the editor: the sharing row,
  the active profile and its `Name-Realm` key, Use/Delete rows per profile, the
  typed name + Create (a copy of the profile in use), and the reset rows;
* `O.INDEX` (the module grid) gets **no** new cell — the original has none.

`BTN` is the original's own widget type (spec OP-02), added to
`Core/Widgets.lua` for these rows.

## 5. `/fx reset`

| Command | Behaviour |
|---|---|
| `/fx reset <module>` | arm a reset of that module's settings, ask, apply on confirm |
| `/fx reset all` | the same for every registered module (the original's `resetall`, `Forte_Core.lua:2387`) |
| `/fx reset list` | name the modules the build registered in this session |
| `/fx reset confirm` / `cancel` | the chat gate of the ask |
| `/fx reset` (bare) | **unchanged**: the cooldown bar's position reset (Forte_Cooldown's `Display:Slash` claims the bare word ahead of every registered sub — `Core/Init.lua` dispatch order, asserted by `test_timeline.lua:482-490`) |

Every reset is **per module** (`FX.Settings:Reset(module)`, which pushes the
deep copy of each default through `Set` — the stored key is *deleted*, a
default is not stored, and every consumer is notified, so the effective
value and the live frames move to the shipped state while the file keeps no
frozen copy of it) and **behind a confirmation**:
`StaticPopup_ShowGenericConfirmation(text, callback)` — Blizzard's generic
yes/no (`Blizzard_StaticPopup/StaticPopup.lua:225`, called the same way by
`Blizzard_AccountStoreCardTemplates.lua:183`), the live equivalent of the
original's `StaticPopupDialogs` rows. Where that add-on is not loaded (a
headless run, a minimal UI) the printed line names `/fx reset confirm`, the
same gate. A reset touches the **active profile only**: it is not a profile
operation and it is not a sharing operation.

## 6. Persistence: the launch-day caveat (say it, do not imply it)

Everything above rides the `## SavedVariables: ForteXorcistDB` global of
`Forte_Core.toc`. WoW Forever has launched to nobody: the profiles, the
migrations and the resets are verified in the simulator, where a session's
`ForteXorcistDB` is a fresh table (the migration is therefore driven over
*synthetic* v0 snapshots in `Forte_Core/tests/test_database.lua`). **Real
SavedVariables round-tripping — the file being written on logout, re-read on
the next login, surviving a relog and a `/reload` — is a launch-day probe**,
the `probeEpoch` Q10 row of `/fx probe` (`Forte_Core/Core/Probe.lua`,
`docs/launch-day.md`): a full relog that shows the epoch +1 in the stored file
proves the round trip; a `/reload` must not bump it. If that probe fails, the
profiles do not persist either — they are the same file. The Profiles page
tips state this to the player in one line.
