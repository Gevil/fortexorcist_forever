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

## H1b sweep (wave 2a, 2026-11-02): the reads, the families, the kind terms
`Forte_Hunter/tests/test_locale_hunter.lua`,
`Forte_Warlock/tests/test_locale_warlock.lua`,
`Forte_Messages/tests/test_locale_messages.lua` are the new German-stub suites;
the three H1 suites gained the read-pass, kind-band and family-gate cases. Each
suite stubs a client that resolves its OWN names and the generated row ids and
answers nothing for an English data name, so it passes only through the joins:
- the 1 Hz read pass, the charges sweep and the ready-pop icon ride the row id
  on a German client, and keep asking the English name on enUS;
- a German `Aspekt des Falken` cast is adopted under `Aspect of the Falcon`,
  and the out-of-combat aura reconcile reaches the aspect (id-first
  `C_UnitAuras.GetPlayerAuraBySpellID`);
- a German `Seelenstein erstellen` cast opens the soulstone window and
  announces it, a German `Ritual der Beschwörung` predicts the channel, and the
  shard/healthstone bag counts ask the client's item names;
- a German `Verwandlung` Spell Timer row meets the Polymorph fade threshold and
  the fade/break rows, and reaches the `^Poly` kind band (Crowds);
- `FX.MatchesFamily` canonicalizes before the English patterns run, the
  raw-name leg carries the family members no data row names, and the family's
  exclusions (`Use Soulstone`) hold.
Every one of those cases was re-run with the fix reverted and FAILS on the
pre-H1b code; enUS is bit-identical (the English leg of every seam is asserted
in the same suites).

## Audit: hard-coded English names in lookup tables/patterns
### Lookup-critical (breaks tracking/decisions on a localized client)
**Fixed by H1b (wave 2a, 2026-11-02)** -- the shared seam is
`FX.MatchesFamily(name, patterns)` (`Forte_Core/Core/Constants.lua`: canonicalize
the CLIENT's name onto the data key, run the English patterns on that key, keep
the raw name as the leg for a family member no data row carries), plus
`Locale.CanonicalName` at every cast seam and the data row's id at every
name-keyed `C_*` read. Every row below names the German-stub suite that proves
it, and every fix was re-run off to prove the test fails on the pre-H1b code.
- addon/Forte_Cooldown/Module.lua -- FIXED, the name-keyed live reads
  (`GetSpellCooldownDurationObject`, `GetSpellCooldownInfo`,
  `GetSpellCharges`, the legacy `GetSpellCooldown`, `GetSpellTexture`): a
  `SpellIdentifier` is a name OR an id (the pinned catalog, SpellDocumentation),
  so the reads now go through the module's memoized `readKey(name)` -- the data
  row's id on a localized client, the English data name on an English one (bit
  identical), `FX.L(name)` for a name no row carries. The memo is stamped with
  the client locale and cleared by `Rebuild`. `Engine:DetectCharges` gets
  `M.ReadChargesFor` (the charges sweep measures by id).
  Tests: `Forte_Cooldown/tests/test_locale_cooldown.lua` (the read pass, the
  charges sweep, the pop icon, and the enUS pass that keeps asking names).
- addon/Forte_Hunter/Core/Tools.lua:271 -- FIXED. The `^Aspect of` detector
  walks the GENERATED table, so it was already the data key space; the two
  client-facing joins were not: the cast seam now canonicalizes
  (`M.CanonicalCastName`, so the aspect tracker and the `Auto Shot` gate see
  data keys) and the out-of-combat aura read goes through `auraLookup` (the
  row's id via `C_UnitAuras.GetPlayerAuraBySpellID`, `FX.L(name)` for a row
  without one, the English name on enUS).
  Tests: `Forte_Hunter/tests/test_locale_hunter.lua`.
- addon/Forte_Timer/Core/Registry.lua:88-210 -- FIXED. `kindFor` runs the
  `KIND_RULES` English term bands on `kindKey(name)` =
  `Locale.CanonicalName(name)`, so `Verwandlung` reaches `^Poly` (Crowds) and
  the `^Soulstone`/`^Healthstone`/`^Teleport`/DoT-tail/CC bands answer for a
  localized name before any registry entry exists (the alias rows `Build` adds
  keep sharing the English entry). The bands also carry the 70707 Warlock pet
  kit D3's data lands: Crowds `^Mesmerize`/`^Soothing Kiss`/`^Spell Lock`,
  TargetDebuff `^Lash of Pain`/`^Devour Magic`, SelfDebuff `^Suffering`,
  SelfBuff `^Fire Shield`/`^Tainted Blood`/`^Consume Shadows`/
  `^Lesser Invisibility`/`^Paranoia`.
  Tests: `Forte_Timer/tests/test_locale_timer.lua` (the German band census +
  the pet-kit floor).
- addon/Forte_Messages/Pages/RaidMsg.lua:80-119 -- FIXED (keys): the FADE_ROWS
  `spell=` keys and `FADE_SPELL_KEYS` stay the data's English keys, and every
  arrival is canonicalized at the lookup (`fadeKey` in the Module);
  `RefreshFadeWarnings` publishes the localized alias of each fade threshold
  alongside the English key (identity on enUS), so a localized row name meets
  the same number. CORRECTION (wave 1): the `Seduction`/`Mesmerize` note no
  longer claims the spells are missing -- the Iteration G verdict measured the
  **70425** data set and the simulator; the live 70707 store carries the kit
  (`wowsims/forever` `164d1cf6`, `sim/core/spelldata/spells_auto_gen.go`:
  `6358`/`6359 Seduction`, `24594 Mesmerize`, plus Devour Magic/Spell Lock/
  Soothing Kiss/Lash of Pain/Suffering, D3's Warlock rows). The pair is silent
  for the ONE structural reason the row's note now says: they are the Succubus
  PET's casts and Forte_Timer registers the cast spine for `player` only; the
  PetRows v2 row (PLAN §11.1 wave 2b) lights them.
  Tests: `Forte_Messages/tests/test_locale_messages.lua` (fade/break + the
  Seduction note's census floor).
- addon/Forte_Messages/Module.lua:357-407,444,514-515 -- FIXED: the soulstone
  announce gate is `FX.MatchesFamily`, and the fade/break key lookups
  canonicalize. Tests: as above (the German `Seelenstein erstellen` cast
  announces; the `Verwandlung` row reaches the Polymorph prefix).
- addon/Forte_Core/Core/Constants.lua:29 -- FIXED: the pattern list stays the
  one home and stays English; the consumers match through `FX.MatchesFamily`.
  Tests: `Forte_Core/tests/test_locale.lua`.
- addon/Forte_Warlock/Core/Tools.lua:147-157 -- FIXED: `WK.MatchesAny` is the
  family gate of the client's name (`FX.MatchesFamily`), the cast seam is
  `M.CastKey` (resolve + canonicalize, so the `^Create ` bag re-read fires),
  and the two bag counts ask `FX.L(name)` (the client's item name). The stone
  COOLDOWN read was already locale-free (it rides the generated `itemID`).
  Tests: `Forte_Warlock/tests/test_locale_warlock.lua`.
- addon/Forte_Timer/Core/Laws.lua:73 -- OPEN (wave 2b): the weapon-enchant name
  gate. Not a lookup of a tracked row (the enchant state rides
  `C_Item.GetWeaponEnchantInfo`), and the row's own seam is the item name, so
  it needs the `FX.L` leg plus the item-alias shape the live client shows --
  launch-day probe material, listed under Open below.
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
  `RankIDsForName` join rides it). The H1b read keys ride it too: on a client
  whose ids differ from the generated data's, the read asks an id the client
  does not know (the read answers nothing, the entry keeps counting down -- the
  same degradation shape as a secret read, never a wrong number).
- NAMES WITH NO GENERATED DATA ROW have no alias to canonicalize through, so
  the English compare behind them stays English on a localized client:
  `Auto Shot` (the Forte_Hunter swing fallback -- no row in
  `Forte_Hunter/Data/Hunter.lua`), the shard (`SHARD_ITEM_NAMES = { "Soul
  Shard" }` -- no row, so its `FX.L` leg is the identity until the item alias
  map carries the id) and the spec-only family members (`Soulstone
  Resurrection`: `FX.MatchesFamily`'s RAW leg is what matches them, and that
  leg is English by nature). The fix is a data row (an id), not a translation:
  a hand-typed locale string is the original's shape, which H1 rejects.
- Pre-existing, observed in the sim (NOT touched): `Module.lua:1019`
  `FX:CallSafe(C_Spell.GetSpellInfo, spellID)` passes the FUNCTION as the
  `name` slot -> the sim prints `attempt to call a number value` for every
  non-event cast path (the login-time probes show it on the paladin profile).
