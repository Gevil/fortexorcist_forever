# Localization (H1)

Key space: every runtime table keys on the GENERATED DATA's English names
(`Data/*.lua` from `mythicsim-forever-engine/data/spells.jsonl`). The client's
LOCALIZED names are lookup inputs only. On an enUS client the alias tables are
EMPTY, so the English path is bit-identical to before.

## Original law
- `/tmp/fxref/Forte_Core/Forte_Core.lua:462-476` `FW:SpellName(spell)` --
  `GetSpellInfo(name)` -> the client's localized name via the
  `GetLocale()`-keyed tables.
- `/tmp/fxref/Forte_Core/Forte_Core.lua:808-814` `FW:ItemName(item)` -- the
  item shape of the same law.
- `/tmp/fxref/Forte_Class/Mage/Localization.lua` (and the sibling per-class
  `Localization.lua`) -- the translations keyed by `GetLocale()`; every
  registration wraps the constant in `FW:SpellName(...)`, so the source's
  runtime tables were keyed by the CLIENT's name.
- H1 inverts the direction: the data name is canonical, the localized name is
  resolved through aliases built FROM THE DATA IDS
  (`C_Spell.GetSpellInfo(id).name`, `C_Item.GetItemNameByID(id)`). No
  hand-typed translations; zero aliases on enUS.

## Shipped seams
- `addon/Forte_Core/Core/Locale.lua` (module `Locale`, toc-listed after
  `Core/Loader.lua` in both Core tocs):
  - `FX.L(english)` -> the client's display name (identity on enUS).
  - `Locale.CanonicalName(name)` -> the English data key, pass-through
    (never nil) for unknown names.
  - `Locale.RankIDsForName(english)` -> the data row ids (locale-free).
  - `Locale.BuildSpellAliases()` -- the class data walk: ids + aliases;
    adds localized keys (id-valued) to `FX.Data.<Class>ByName`; tracks
    `writtenKeys` so `Locale.Reset()` (tests) undoes the shared-table keys.
  - `Locale.BuildItemAliases(data)` -- `FX.Data.Items.onUse/consumables` ->
    `englishByItemID`; on a non-enUS client resolves the localized item name
    per id and REQUESTS the uncached ids (`Locale.RequestItemName` ->
    `C_Item.RequestLoadItemDataByID`), the `GET_ITEM_INFO_RECEIVED` /
    `ITEM_DATA_LOAD_RESULT` reply (frame registered in `OnEnable`, the law:
    no top-level `RegisterEvent`) records the alias and wakes
    `Locale.SubscribeLateNames` subscribers.
  - English-key collision guard: a localized name equal to any English data
    key is never aliased.
- `addon/Forte_Cooldown/Module.lua`: `isKnown` tries
  `Locale.RankIDsForName(name)` + `FX.Compat.IsPlayerSpell(id)` FIRST (the
  `C_Spell.GetSpellInfo(<English name>)` path resolves against the client's
  localized name table and dies on a localized client), name path as the
  fallback; the cast-name resolve canonicalizes at `Engine:OnCast`
  (`Module.lua:1290` area); `M.IsKnown` exposed as the test seam.
- `addon/Forte_Cooldown/Core/Items.lua`: the scan resolves every inventory
  name through `lookup()` (alias-aware), records each `(data name, client
  name)` pair proven by the id join (`Locale.RecordItemAlias`), adds localized
  keys to the local consumable index, requests uncached ids, and
  re-runs (debounced `C_Timer.After`) when a late item name arrives.
  `tracked`/`byCastSpell` stay English-keyed; `byCastSpell` is keyed by the
  lowercased CLIENT name (locale-safe by construction).
- `addon/Forte_Timer/Core/Casts.lua`: `Casts:NameOf` canonicalizes the
  resolved cast name -- the row key space is the data key.
- `addon/Forte_Timer/Core/Registry.lua`: `Build` adds alias rows -- the
  localized name maps to the SAME entry table as the English key (kind,
  duration, maxRows cannot drift); `Counts`/`n` keep counting English rows.
  `RestorePlayerClass`'s rebuild re-adds them (it re-runs `Build`).

## Acceptance (the sim is enUS-FIXED; the German client is stubbed)
`Forte_Core/tests/test_locale.lua`, `Forte_Cooldown/tests/test_locale_cooldown.lua`,
`Forte_Timer/tests/test_locale_timer.lua`:
- German client: the set builds from the DATA IDS with every English name
  lookup stub-dead (Rapid Fire data row 3045 -> `Schnellfeuer`).
- A cast of id 3045 named `Schnellfeuer` canonicalizes onto the
  `Rapid Fire` cooldown row (the `FX.Locale.CanonicalName` leg at the
  `Engine:OnCast` call).
- An on-use trinket (19336 `Arcane Infused Gem`) resolves through the localized
  bag-reader name (`Arkane Verstaerkte Essenz`) to the English row key.
- A `Verwandlung` (Polymorph, 12826) Spell Timer registry row: the alias entry
  shares the `Polymorph` entry (`KindFor` reaches Crowds).
- enUS: zero aliases, FX.L identity, English tests green; Gate PASS.

## Audit: hard-coded English names in lookup tables/patterns (not edited here)
### Lookup-critical (breaks tracking/decisions on a localized client)
- addon/Forte_Cooldown/Module.lua:119,154,379 -- the name-keyed live reads
  (`GetSpellCooldownDurationObject(name)`, `GetSpellCooldownInfo(name)`,
  `GetSpellCharges`, `GetSpellTexture(name)`): on a localized client the
  predictions/learning/icon reads go blind (the rows survive: the cast events
  + data durations). WAVE 2: route the reads through `FX.L(name)`.
- addon/Forte_Hunter/Core/Tools.lua:271 -- `name:find("^Aspect of")`
  (aspect-family detector; the aspects ARE data rows, so the Locale alias
  map + a data-id join is the fix).
- addon/Forte_Timer/Core/Registry.lua:88-210 -- the `KIND_RULES` English term
  bands (e.g. "^Curse", "Amplify Curse", "Touch of Weakness" (89), pet terms
  (93-99), "^Healthstone","^Soulstone","Spellstone","Firestone","^Teleport"
  (151-152), "Corruption$","Agony$","Immolate" (171), "Expose Armor","Sunder
  Armor" (172), "Judgement" (195), the taunts/interrupts/CC bands (109-149)) --
  the kind/colour of localized-name rows falls to Default.
- addon/Forte_Messages/Pages/RaidMsg.lua:80,84,89,95,107,111 -- the FADE_ROWS
  `spell=`/`prefix=` keys (Fear, Banish, Subjugate Demon, Seduction,
  Polymorph, Sap); :117-119 -- `FADE_SPELL_KEYS` (aura-suffix -> prefix).
- addon/Forte_Messages/Module.lua:357-407,444,514-515 -- the `FX.SoulstonePatterns`
  announce gates (the soulstone family).
- addon/Forte_Core/Core/Constants.lua:29 -- `FX.SoulstonePatterns =
  { "^Create Soulstone", "^Soulstone" }` (shared by Messages + Warlock).
- addon/Forte_Warlock/Core/Tools.lua:147-151 -- the soulstone/healthstone/
  summon pattern families (`^Create Soulstone`, `Healthstone$`,
  `^Ritual of Summoning`); :157 -- `SHARD_ITEM_NAMES = { "Soul Shard" }`.
- addon/Forte_Timer/Core/Laws.lua:73 -- the weapon-enchant name gate.
### UI text (labels/tips -- cosmetic, NOT lookup keys; translating them is
### outside H1 and outside the original's scope -- it localized game names,
### not its own English panel text):
- addon/Forte_Warlock/Pages/Warlock.lua:103,238-268;
  addon/Forte_Warlock/UI/Healthstone.lua:44-79;
  addon/Forte_Warlock/UI/Soulstone.lua:51-78;
  addon/Forte_Warlock/UI/Frame.lua:182-202;
  addon/Forte_Warlock/UI/Module.lua:48,98-99;
  addon/Forte_Options/UI/Window.lua:87-89 ("Healthstone Spy", "Soulstone
  Tracker"); addon/Forte_Cooldown/UI/Timeline.lua:176-190 (the COLour-category
  keys `Healthstone`/`Soulstone` -- internal keys, not game names);
  addon/Forte_Messages/Core/Sounds.lua:41-101 + Pages/Sound.lua (the settings
  keys `TimerFade*`/`Soulstone*` -- internal keys); the
  `Fade`/`Break`-family hits in Forte_Messages/Forte_Timer are settings keys
  and log strings, not game-name lookups.
### Open (launch-day, not sim-testable -- wow-ui-sim is enUS-fixed)
- The live localized `C_Item` name shape (the `GetItemInfo` tuple's name
  element) and the real `GET_ITEM_INFO_RECEIVED` arrival flow (the sim
  pre-caches every id and never fires the event -- observed in probes).
- The live localized-name data ids matching the client spell DB (the
  `RankIDsForName` join rides it).
- Pre-existing, observed in the sim (NOT touched): `Module.lua:1019`
  `FX:CallSafe(C_Spell.GetSpellInfo, spellID)` passes the FUNCTION as the
  `name` slot -> the sim prints `attempt to call a number value` for every
  non-event cast path (the login-time probes show it on the paladin profile).
