# Item procs / on-use / consumables (`ForteXorcist.Data.Items`)

Human summary of the data emitted by `tools/gen_item_data.py`. Nothing here is hand-typed:
re-run `python3 tools/gen_item_data.py` after pulling `mythicsim-forever-engine` and the files
regenerate byte-deterministic (order = name, itemId, buffId).

**The generator writes two files (H7, 2026-11-02; `docs/perf.md` §4 fix 1).**
`addon/Forte_Items/Data/Items.lua` (always loaded) carries `onUse`, `consumables` and the 5
`enchantProcs` rows + `OnUseByName`; `addon/Forte_ItemProcs/Data/Procs.lua` (a
`## LoadOnDemand: 1` add-on, `ForteXorcist.Data.ItemProcs`) carries the 400 item `procs` rows +
`ProcsByName` + `ProcsByBuffName`. The enchant rows are the exception that stays: the
always-loaded `Forte_Cooldown/Core/Enchants.lua` names an enchant from them. A default session
parses 89.5 KB, not 227.5 KB; the proc file is parsed when the `Cooldown.Procs` switch is
switched on (`Forte_Cooldown/Core/Procs.lua` -> `FX.LoadAddOnOnDemand`). All numbers below are for the pin
**client_build 1.60.1.70425** (manifest `engine_revision a667dce8`,
`items.jsonl` sha256 prefix `79e1e471a9bc`).

## Lists and counts

| list | file | entries | trackable | source |
|---|---|---|---|---|
| `onUse` | Forte_Items | **238** | `cooldown` | 238 items with `on_use` effects |
| `consumables` | Forte_Items | **79** | `cooldown` | 79 of 106 consumables carry a cooldown |
| `enchantProcs` | Forte_Items | **5** | `buff-window` | 5 weapon-enchants |
| `procs` | Forte_ItemProcs (LoD) | **400** | `buff-window` | 400 item `proc` effects |

Lookup maps: `OnUseByName` (201 keys, by item name) in Forte_Items; `ProcsByName` (371 keys, by
item name) and `ProcsByBuffName` (351 keys, by the effect's `buffName`) in Forte_ItemProcs. Keys are ITEM/buff **names**; ids are
informational (PLAN.md §8 — ids drift between builds). Where a name carries several ids (PvP rank
variants), the key resolves to the lowest id and every collision is listed in the generated file
header (15 name collisions, largest: "Insignia of the Horde" ×16, "Signet Ring of the Bronze
Dragonflight" ×10).

Fields per entry: `name`, `itemId`, `source` (`item`/`enchant`/`consumable`), `cooldownMs` (onUse),
`buffId`/`buffName`, `durationMs`, `maxStacks`, `slotType`, `classAllowlist`, `trackable`.
`classAllowlist` is emitted only where the source row has one (70 onUse + 36 proc entries, 12
distinct single-class combos); everything else is class-agnostic and unfiltered. `slotType` is
composed verbatim from the fields the data states (`type`, `hand_type`, `weapon_type`,
`ranged_weapon_type`, `armor_type`, joined with ` / `), `icdMs` (51 rows: 49 in `procs`, 2 in
`enchantProcs` — `proc.icd_ms`, `docs/research/forever-data-gaps.md` G2, consumed by
`Forte_Cooldown/Core/Procs.lua` as the length of a proc's ICD window) and the consumable
`categoryId`/`categoryCooldownMs`. Deliberately **not** emitted: `proc.proc_chance` (119 procs),
`on_use.category_id`/`category_cooldown_ms` (181 onUse).

### slotType distribution — `onUse` (238)

| slotType | n |
|---|---|
| ItemTypeTrinket | 171 |
| ItemTypeWeapon / HandTypeOffHand / WeaponTypeOffHand | 19 |
| ItemTypeHead / ArmorTypeCloth | 6 |
| ItemTypeBack / ArmorTypeCloth | 4 |
| ItemTypeWeapon / HandTypeTwoHand / WeaponTypeStaff | 4 |
| ItemTypeChest / ArmorTypeCloth | 3 |
| ItemTypeChest / ArmorTypeMail | 3 |
| ItemTypeWaist / ArmorTypeLeather | 3 |
| (no type fields — Orb of Deception, Traveler's Symbols) | 2 |
| ItemTypeFeet / ArmorTypeCloth | 2 |
| ItemTypeFinger | 2 |
| ItemTypeNeck | 2 |
| ItemTypeWaist / ArmorTypeCloth | 2 |
| ItemTypeWeapon / HandTypeOffHand / WeaponTypeShield | 2 |
| ItemTypeWeapon / HandTypeTwoHand / WeaponTypeMace | 2 |
| one each: Feet/Leather, Feet/Mail, Feet/Plate, Hands/Leather, Head/Leather, Head/Plate, Legs/Plate, Trinket/ArmorTypeMail, Weapon/MainHand/Axe, Weapon/OneHand/Dagger, Weapon/TwoHand/Sword | 11 |

Trinkets dominate (171/238) — the on-use tracking payoff is the trinket bar.

### slotType distribution — `procs` (405)

Item procs (400): weapons carry most.

| slotType | n |
|---|---|
| Weapon/OneHand/Dagger | 39 |
| Weapon/TwoHand/Sword | 32 |
| Weapon/OneHand/Sword | 24 |
| Weapon/TwoHand/Axe | 24 |
| Weapon/MainHand/Sword | 23 |
| Finger | 22 |
| Weapon/TwoHand/Mace | 22 |
| Weapon/OffHand/Shield | 20 |
| Weapon/OneHand/Mace | 18 |
| Weapon/TwoHand/Polearm | 18 |
| Trinket | 16 |
| Weapon/OneHand/Axe | 14 |
| Ranged/Totem | 13 |
| Ranged/Idol | 12 |
| Weapon/MainHand/Mace | 12 |
| Weapon/MainHand/Axe | 10 |
| Ranged/Libram | 9 |
| Ranged/Bow | 8 |
| Weapon/TwoHand/Staff | 8 |
| Ranged/Gun | 6 |
| Ranged/Thrown | 6 |
| Hands/Leather | 4 |
| Ranged/Crossbow | 4 |
| Ranged/Wand | 4 |
| Weapon/MainHand/Dagger | 4 |
| Weapon/OneHand/Fist | 4 |
| Weapon/MainHand/Fist | 3 |
| Weapon/OffHand/Fist | 3 |
| Weapon/OffHand/OffHand | 3 |
| Chest/Mail 2, Chest/Plate 2, Hands/Mail 2, Hands/Plate 2 | 8 |
| one each: Back/Cloth, Chest/Cloth, Chest/Leather, Neck, Shoulder/Plate, Waist/Mail, Weapon/OffHand/Axe | 7 |

Enchant procs (5): 3 `ItemTypeWeapon` (Crusader, Grand Crusader, Grand Sorcerer) +
2 `ItemTypeWeapon / EnchantTypeTwoHand` (Grand Arcanist, Grand Inquisitor). Their `itemId` is the
enchant `effect_id`, **not** an inventory item id.

### `consumables` (79)

What `consumables.jsonl` records hold: `id`, `name`, `type` (`ConsumableTypePotion` 29,
`ConsumableTypeFood` 18, `ConsumableTypeGuardianElixir` 10, `ConsumableTypeFlask` 8,
Battle/Defense/School/SpellPower elixirs, Zanza, Alcohol, …), a 41-slot `stats` vector,
`category_id` + `category_cooldown_duration` (seconds; 77 records — 120 s potion category 4,
3 s elixir category 2593, 1 s food category 59, 3600 s Zanza category 103, 120 s Healthstone-like
category 1153 incl. **Major Healthstone**), `cooldown_duration` (seconds; 4 records: Thistle Tea
300 s, Juju Power/Might 60 s, Winterfall Firewater 60 s) and `buff_duration` (seconds; 89 records,
30 s food up to 2 h flasks). Values are **seconds** — converted to ms on emit
(`cooldownMs`/`categoryCooldownMs`/`durationMs`). 27 records (stat food, Alcohol, quest items like
Potion of Demon Slaying) carry **no cooldown** and are skipped by design.

## 15 longest on-use cooldowns

| item | id | cooldownMs | ≈ | applied buff | durationMs | slotType |
|---|---|---|---|---|---|---|
| Dimensional Ripper - Everlook | 18984 | 14400000 | 240 min | Everlook Transporter (23442) | — | Trinket |
| EZ and SAF Field Transporter: Mt. Hyjal | 260821 | 14400000 | 240 min | Mount Hyjal Transporter (1269339) | — | Trinket |
| EZ-Thro Field Transporter: Gadgetzan | 260819 | 14400000 | 240 min | Gnomish Transporter (23453) | — | Trinket |
| SAF-T Emergency Ripper: Everlook | 260820 | 14400000 | 240 min | Everlook Transporter (23442) | — | Trinket |
| Ultrasafe Transporter: Gadgetzan | 18986 | 14400000 | 240 min | Gnomish Transporter (23453) | — | Trinket |
| Signet of Expertise | 8703 | 10800000 | 180 min | Summon Smithing Hammer (11209) | — | Trinket |
| Arcanite Dragonling | 16022 | 3600000 | 60 min | Arcanite Dragonling (19804) | 60000 | Trinket |
| Brutal Hauberk | 7133 | 3600000 | 60 min | Rage (9174) | — | Chest/Mail |
| Fire Hardened Hauberk | 6972 | 3600000 | 60 min | Rage (9174) | — | Chest/Mail |
| Gnomish Harm Prevention Belt | 10721 | 3600000 | 60 min | Harm Prevention Belt (13234) | 600000 | Waist/Leather |
| Goblin Construction Helmet | 10543 | 3600000 | 60 min | Fire Protection (12561) | 60000 | Head/Cloth |
| Arcane Orb | 7507 | 1800000 | 30 min | Replenish Mana I (9252) | — | OffHand orb |
| Celestial Orb | 7515 | 1800000 | 30 min | Replenish Mana II (9253) | — | OffHand orb |
| Everglow Lantern | 5323 | 1800000 | 30 min | Heal (14053) | — | OffHand orb |
| Gauntlets of the Sea | 8346 | 1800000 | 30 min | Heal (10577) | — | Hands/Leather |

(Trinket rank variants share these windows; e.g. the three Gadgetzan/Everlook transporters all
carry the 240 min engineering travel cooldown.)

## 15 most-frequent proc buff names (with carrying items)

| buffName | proc entries | distinct items | items |
|---|---|---|---|
| Timeworn Shot (1213395) | 10 | 10 | Signet Ring of the Bronze Dragonflight (10 id variants) |
| Timeworn Strike (1213390) | 10 | 10 | Signet Ring of the Bronze Dragonflight (10 id variants) |
| Building Inspiration (413338) | 5 | 5 | Astral/Bulwark/Brimstone/Ichthyan/Syzygic Icon |
| Lightning Bolt (13959) | 4 | 4 | Grand Marshal's Aegis, High Warlord's Shield Wall, Premier variants |
| Frostbolt (13439) | 3 | 3 | Frost Tiger Blade, Hammer of the Northern Wind, Winter's Bite |
| Shadow Bolt (18211) | 3 | 3 | Doombringer, Ebon Hand, Nightblade |
| Frost Blast (18276) | 2 | 2 | Bonechill Hammer, Darrowspike |
| Jang'thraze (11657) | 2 | 2 | Jang'thraze the Protector (2 id variants) |
| Libram of Divinity (28853) | 2 | 2 | Libram of Divinity (2 id variants) |
| Lightning Bolt (1216968) | 2 | 2 | Grand Marshal's Aegis, High Warlord's Shield Wall |
| Poison (16400) | 2 | 2 | Naraxis' Fang, Wyvern Tailspike |
| Poison (17511) | 2 | 2 | Ichor Spitter, Serpent Slicer |
| Puncture Armor (1293005) | 2 | 2 | Digmaster 5000, Vibroblade |
| Puncture Armor (17315) | 2 | 2 | Bashguuder, Rivenspike |
| Rend (13318) | 2 | 2 | Blood Talon, Killmaim |

The buff name strings embed the spell id in parentheses — they are catalog display names; the
numeric id is duplicated in `buffId` (informational, §8).

## Caveats

- **Procs have no cast to predict from.** A proccing aura arrives off a swing/hit; there is no
  `UNIT_SPELLCAST_SUCCEEDED` anchor to start a predicted window (the core §3.2 cast-predict trick
  does not apply). The only full-window source is the aura itself.
- **Forever aura reads are secret in combat** (PLAN.md §8, `SecretWhenCombatRestricted`):
  `C_UnitAuras` durations may come back as secret values during a fight, so proc windows are
  tagged `trackable = "buff-window"` = **read out of combat** (via `ForteXorcist.Compat.PlainOrNil`);
  in combat the addon may only watch the aura appear/disappear, never read the timer. A secret
  read must never overwrite a known window.
- **`onUse` uses the item-cooldown API path** (`C_Item`/`C_Container` `GetItemCooldown`): unannotated
  for secrecy at this pin — PLAN.md §8 says probe before relying.
- **Entries with a buff but no duration**: `onUse` **54**, `procs` **205**. The data genuinely lacks
  `effect_duration_ms` there; show `?` and learn the duration at runtime, never guess.
- **Name collisions** (15, listed in the file header): mostly PvP rank variants (Insignia/Talisman
  families, Premier Aegis/Shield Wall) and multi-effect items (Signet Ring of the Bronze Dragonflight
  carries both Timeworn Shot and Timeworn Strike across 10 ids). ByName keys resolve to the lowest
  id; all variants stay in the lists.
- **Enchant entries** carry `itemId = effect_id` (1900, 7940-7943) — never match them against bag
  item ids; match enchant procs through the weapon-enchant aura by `buffName`.
- The 517 remaining `item_effects` with a `buff_id` (passive/equip auras, no `on_use`/`proc`) are
  out of scope and not emitted.
- `durationMs = -1` in a few on-use rows means "permanent duration" in the catalog (summons); treat
  as no-window.
