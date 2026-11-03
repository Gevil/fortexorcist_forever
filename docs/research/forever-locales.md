# Slice H1r — Forever locales, and item/spell names at login

Research note for **H1 Localization** (`PLAN.md` §11.1 row "H1r Locale research"). Read-only
survey of the installed Forever client, the installed third-party addons, the pinned API catalog,
the wow-ui-sim spec set, and public launch-window sources. Date of survey: 2026-11-02.

Paths: `<install>` = the WoW Forever client's `World of Warcraft` folder (a Steam/Proton install on the author's
machine); `<_forever_>` = `<install>/_forever_`;
`<addins>` = `<_forever_>/Interface/AddOns`;
`<agents>` = `docs/api/wow-addon-api-agents`; `<specs>` = `docs/reference/wow-ui-sim-specs`
(repo-relative to `wow-fortexorcist`).

## Answers in one place

| # | Question | Answer | Confidence |
|---|---|---|---|
| 1 | Which locales does Forever ship/support? What does `GetLocale()` return here? | **Not enUS-only.** The shop lists **10 client languages** (enUS, enGB, deDE, frFR, esES, esMX, ptBR, ruRU, koKR, zhTW); no itIT, no zhCN, no ptPT. This machine's install is **enUS**, so `GetLocale()` returns **`"enUS"`** (`audioLocale` is a separate key). | **High** on the set + on this install's value. Medium on which locales are *playable* at launch (ruRU was locked out of EU rulesets in the pre-launch window). |
| 2 | Are item names synchronous at `PLAYER_LOGIN` on 12.x? | **No — not guaranteed.** `C_Item.GetItemNameByID` is declared **nullable**, and shipping Forever addons explicitly handle a **cold item cache at login** for equipped gear (`IsItemDataCachedByID` false ⇒ `RequestLoadItemDataByID` ⇒ re-run on `ITEM_DATA_LOAD_RESULT`), plus **empty `GetInventoryItemID` reads** in the login window before the inventory syncs. | **High** that the async path is real and expected; **Medium** on how often it bites at `PLAYER_LOGIN` (never observed on a real client — launch-day probe). The **simulator is not an oracle here** (§2.4). |
| 3 | Do installed Forever addons localize spell names, or key by ID? | **Key by ID; names are asked from the client.** Every installed addon keeps IDs as the identity and (a) ships `Locales/<locale>.lua` phrase files for its *own* UI text, (b) resolves game names by ID (`C_Spell.GetSpellName(id)`, `C_Item.GetItemNameByID(id)`) at render time, (c) **gates English string parsing behind `GetLocale() == "enUS"/"enGB"`**. 14 of 68 installed addons ship locale files. | **High** (file:line evidence, §3). |

---

## 1. Which client locales exist, and what `GetLocale()` returns

### 1.1 The installed client (primary, local)

| Fact | Evidence |
|---|---|
| Product = Forever (`wowf`), branch `eu`, installed version **1.60.1.70707** | `<install>/.build.info:2` (the `Product` / `Branch` / `Version` columns) |
| Product flavor `wowf` | `<_forever_>/.flavor.info:2` |
| Install tag names **one** text + speech locale: `Windows x86_64 EU? acct-NLD? geoip-NL? enUS speech?:… enUS text?` | `<install>/.build.info:2` (`Tags!STRING:0` column) |
| `SET textLocale "enUS"` | `<_forever_>/WTF/Config.wtf:33` |
| `SET audioLocale "enUS"` (a separate, independently-set key) | `<_forever_>/WTF/Config.wtf:90` |
| Client told Battle.net `locale="enUS"` | `<_forever_>/Logs/Connection.log:8`, `<_forever_>/Logs/General.log:142` |
| No per-locale content folders: `Data/` holds only `config data ecache indices wowf` (no `Data/ruRU`, `Data/koKR`, …) | `<install>/Data/` listing |
| The client's shipped *browser* locale packs cover a wider set — `DE, EN-US, ES, ES-419, FR, it, KO, PT-BR, RU, ZH-CN, ZH-TW` | `<_forever_>/UTILS/LOCALES/` listing (CEF/browser packs, **not** game text locales; read as the build's regional set, `[INFERENCE]`) |
| Hotfix validation touches `Table Locale` RecIDs 14/15/16 ⇒ the `Locale` table has ≥17 rows — the modern multi-locale table, not a 1-row enUS stub | `<_forever_>/Logs/Hotfix.log:25887-25889` |

**Therefore on this machine `GetLocale()` → `"enUS"`** — the value is the `textLocale` string verbatim;
nothing in the install overrides it.

### 1.2 What Blizzard advertises (web; shop + forums)

The Battle.net Shop product page for *World of Warcraft: Forever* (US + EU) lists **10 languages**:
English (US), English (EU), Español (AL = esMX), Español (EU = esES), Português (BR), Deutsch,
Français, Русский, 한국어, 繁體中文 — **Italian, Polish, Turkish absent**; Italian *is* listed for
retail *Midnight* on the same page, so Forever's set is deliberately narrower.
Source: [wowguide.net — WoW Forever languages](https://wowguide.net/en/guides/wow-forever-supported-languages)
(secondary guide, Sep 16–22 2026, citing `eu.shop.battle.net/en-gb/product/world-of-warcraft-forever`
and `us.shop.battle.net/en-us/product/world-of-warcraft-forever`; both shop pages failed to fetch
directly here — redirect loop). Regions: Americas & Oceania, Europe, Korea, Taiwan.

Launch-window forum evidence that these are **real client locales, not labels**:

- Non-Latin-script locales exist in the EU install picker: *"why is Russian version is even listed in
  supported localizations on the install language selection options in the EU region?"*; the **deDE
  client works and shares the same character list as the EN client**; the **ruRU client had all EU
  rulesets greyed out** (also during the Oct 21 stress test), while EN and DE connected.
  [eu.forums.blizzard.com t/638066](https://eu.forums.blizzard.com/en/wow/t/latin-script-only-client-localizations-and-names/638066) (Oct 27, 2026)
- Same complaint at scale: *"Russian: cannot connect. English: can connect. German: can connect.
  This concerns the game client language"*; the ruRU client **did** work on the **US-region beta**;
  Cyrillic character names are rejected on the EN client.
  [eu.forums.blizzard.com t/638126](https://eu.forums.blizzard.com/en/wow/t/wow-forever-ru-locale-client-has-no-ruleset-access-or-name-reservation-cyrillic-names-fail-on-en-client/638126) (Oct 27–28, 2026, 161 posts)
- Italian is *requested, not shipped*: [t/631635](https://eu.forums.blizzard.com/en/wow/t/a-sincere-plea-for-italian-language-support-in-wow-forever/631635),
  [it t/10376](https://eu.forums.blizzard.com/it/wow/t/request-for-italian-localization-in-world-of-warcraft-forever/10376).

`[INFERENCE]` **Expected `GetLocale()` return set on live clients:** `enUS`, `enGB`, `deDE`, `frFR`,
`esES`, `esMX`, `ptBR`, `ruRU`, `koKR`, `zhTW` (no `itIT`, no `zhCN`, no `ptPT`). The
`enGB` / `ptBR`-vs-`ptPT` regional split is an engine concept on this generation:
`<specs>/toc-regional-text-locale.md:20` ("English `enUS` selects `enUS` in US and `enGB` in EU;
Portuguese selects `ptBR` in US and `ptPT` in EU"), and that capability is shared by
`retail-12-1-7` **and** `client-wowforever` (`<specs>/toc-regional-text-locale.md:19`).

### 1.3 The wow-ui-sim is enUS-fixed — locale behaviour is not sim-testable

- `<specs>/xml-file-locale-annotations.md:8` — "Under the simulator's enUS text-locale policy,
  execute selected enUS script and included XML, and skip non-enUS references even when their files
  exist."
- same file `:27` (Known gaps) — "Client-selected non-enUS text locale is **not modeled**; enUS
  remains the simulator's existing fixed policy."
- `<specs>/client-profiles.md:15` — "PTR and Forever expand `[RegionalTextLocale]` in TOC file paths
  to `enUS` for the simulator's current enUS text locale / US region … Alternate locale/region
  configuration is **not modeled** by this change."
- Observed: `wow-sim … --exec-lua 'print("FXPROBE marker", GetLocale())' dump-tree` printed
  **`enUS`** (2026-11-02, this machine).
- The sim's Forever text table is the **enUS** GlobalStrings export of build 1.60.1.70532
  (`<specs>/forever-global-strings.md:5`, `:24` — 27,388 rows; `:34` "Native localization conformance
  … not established by these fixtures").

**Consequence for H1:** every localized-path assertion is a **launch-day probe on a real client**
(`GetLocale()`, a `[TextLocale]`/`[AllowLoadTextLocale]` file, `C_Spell.GetSpellName(id)` under
deDE/frFR). The sim can only prove the *enUS* path and the *code shape* (ID ⇒ name, locale gating).

---

## 2. Item names at `PLAYER_LOGIN` on the 12.x engine

**Answer: treat them as async.** Item-ID reads for equipped gear can be *empty* in the login window,
`C_Item.GetItemNameByID` is declared nullable, and the addons shipping on Forever all implement a
request-and-retry path keyed on `ITEM_DATA_LOAD_RESULT` / `GET_ITEM_INFO_RECEIVED`.

### 2.1 The pinned API catalog (Forever tree; Gethe `ca8368f2…` = 1.60.1.70532, per `<agents>/docs/audit/FOREVER-SYMBOL-GAPS.md:3`)

| Symbol | Signature as pinned | Cite |
|---|---|---|
| `C_Item.GetItemNameByID(itemInfo)` → `itemName: string` **Nilable=true** | can return nil | `<agents>/docs/audit/api-coverage.json:29764` = `ItemDocumentation.lua#L845` (same link at `<agents>/docs/audit/FOREVER-SYMBOL-GAPS.md:2916`) |
| `C_Item.IsItemDataCachedByID(itemInfo)` → `isCached: bool` | the gate | `api-coverage.json:29807` (`#L1519`) |
| `C_Item.IsItemDataCached(itemLocation)` → `isCached: bool` | location form | `api-coverage.json:29806` (`#L1504`) |
| `C_Item.RequestLoadItemDataByID(itemInfo)` | triggers the load | `api-coverage.json:29823` (`#L1709`) |
| `GET_ITEM_INFO_RECEIVED(itemID, success)` | payload `(number, bool)` | `api-coverage.json:26427` (`#L1812`; `<agents>/skills/wow-api-events/references/EVENTS-G-L.md:82` pins that line to **forever**) |
| `ITEM_DATA_LOAD_RESULT(itemID, success)` | payload `(number, bool)` | `api-coverage.json:26633` (`#L1854`; `FOREVER-SYMBOL-GAPS.md:2875`) |
| Evidence flags on all of the above | `"loadConditions":"unknown","runtime":"unknown","addonAccess":"unknown"` | `<agents>/skills/wow-api-items-inventory/references/generated/forever.json:120,125,476,535` |

`FOREVER-SYMBOL-GAPS.md:3`: the catalog is "Generated definitions only; **availability and addon
access remain unverified**" — source presence, not runtime proof.

Documented pattern in the same skill:
`<agents>/skills/wow-api-items-inventory/references/RETAIL-BASELINE.md:546` — "**Async item data** —
`C_Item.GetItemInfo()` may return nil for uncached items. Use `C_Item.RequestLoadItemDataByID()` and
listen for `GET_ITEM_INFO_RECEIVED`, or use the `Item:ContinueOnItemLoad()` mixin pattern";
`:519` — `GET_ITEM_INFO_RECEIVED | itemID, success | Async item data arrived`; `:374-387`
(`Item:CreateFromItemID` + `ContinueOnItemLoad`), `:389-397` (`ContinuableContainer` batch form).

⚠ **API-lint trap for H1:** `CreateFromItemID`, `ContinueOnItemLoad`, `ContinuableContainer` have
**0 occurrences** in the pinned catalog (checked across
`<agents>/skills/wow-api-items-inventory/references/generated/forever.json` and
`<agents>/docs/audit/api-coverage.json`). `PLAN.md` §11.1's H1 row names
`Item:CreateFromItemID` + `ContinueOnItemLoad`, so `scripts/api_lint.py` will reject them. Use
`IsItemDataCachedByID` ⇒ `RequestLoadItemDataByID` ⇒ `ITEM_DATA_LOAD_RESULT` — the shape every
installed addon uses.

### 2.2 Shipping Forever addons prove the login window is cold (primary, local)

`EllesmereUICooldownManager` (the Forever CDM fork) — `<addins>/EllesmereUICooldownManager/EUI_CDM_HookTrinkets.lua`:

```lua
123      local itemID = GetInventoryItemID("player", slotID)
126          -- An empty read is also what the login window returns before the inventory
127          -- has synced: flag it so the PLAYER_ENTERING_WORLD retry sweep re-reads the
128          -- slot (SlotScanIncomplete) …
136      -- Item data not in the client cache yet (cold cache at login): GetItemSpell
137      -- reads nil for an on-use item, which the passive test below would take as
138      -- conclusive and nothing would ever re-scan. Keep the previous state,
139      -- request the load and let ITEM_DATA_LOAD_RESULT re-run the scan.
140      if C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(itemID) then
141          f._slotScanPending = true
142          C_Item.RequestLoadItemDataByID(itemID)
143          _trinketEventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
144          return
145      end
```

…for **equipped** slots (`:123`), i.e. exactly H1's "equipped items" case. Companion lines in the
same file: `:158-172` (`C_TooltipInfo.GetInventoryItem("player", slotID)` nil ⇒
"Tooltip data not cached yet: keep the previous state and let the **login/equip retry timers**
re-run the scan", `:176-178`), `:344-352` (handler for `ITEM_DATA_LOAD_RESULT` /
`SPELL_DATA_LOAD_RESULT` / `SPELL_TEXT_UPDATE`; `success` arrives as **arg2**), `:370-372`
(unregister the load events once nothing is pending), `:387-390` (`PLAYER_ENTERING_WORLD` re-sweep),
`:393-394` ("Tooltip data may not be cached yet on login, causing on-use detection to fail. Retry only
for slots whose scan is incomplete"). Same file `:335` registers the `PLAYER_ENTERING_WORLD` sweep.
Companion addon file `<addins>/EllesmereUICooldownManager/EUI_CDM_HookPresetFrames.lua:806-811` — a
missing `C_Item.GetItemInfo` link ⇒ `RequestLoadItemDataByID` and "leave the memo unresolved so the
next pass retries **rather than baking in the miss**".

`NeedRoll` — `<addins>/NeedRoll/Core/Items.lua:9-22` is the canonical two-step:

```lua
9   function ns.Items:Load(itemID, callback)
10      if C_Item.IsItemDataCachedByID(itemID) then callback(itemID); return end
…
16      C_Item.RequestLoadItemDataByID(itemID)
19  ns:On("ITEM_DATA_LOAD_RESULT", function(itemID, success)
```

Nil-name is a **normal UI state** in NeedRoll: `UI/LootGrid.lua:522-526` (`ItemName`: nil ⇒ request,
render `L["Item %d"]`), `:350-354` ("Loading…"), `:1796-1800`, `UI/Theme.lua:1974-1977`,
`UI/WarlockPets.lua:162-166`, `UI/Poisons.lua:52-56`, `UI/ProfessionOverview.lua:152-156`,
`UI/Overview.lua:848-852`, `UI/Questlines.lua:444-446`, `UI/TierSets.lua:143-147`,
`UI/Drops.lua:978-980`, `:1953-1955`. Its own docs: NPC/quest names "arrive from the server **a moment
after the first ask**", so they are asked for in the background (a few a second, **never in combat**)
and cached in `NeedRollDB.names` for the next session
(`<addins>/NeedRoll/docs/LOCALIZATION.md`, §"Names in the data"; `<addins>/NeedRoll/Core/Names.lua:12-16`).

Spell side is symmetric: `C_Spell.GetSpellInfo` — "Returns `nil` if data is not cached. Call
`C_Spell.RequestLoadSpellData()` first for uncached spells, then wait for `SPELL_DATA_LOAD_RESULT`";
gate with `C_Spell.IsSpellDataCached(spellIdentifier)`
(`<agents>/skills/wow-api-spells-abilities/references/SPELLS-CORE.md:40-42`; both symbols present in
`<agents>/skills/wow-api-spells-abilities/references/generated/forever.json`). Live example of the
cold spell cache on Forever: `EUI_CDM_HookTrinkets.lua:194-201` — `C_Spell.GetSpellDescription`
"empty … until `SPELL_TEXT_UPDATE` fires … (nil when the spell record itself is not loaded yet)" ⇒
`RequestLoadSpellData` + `SPELL_TEXT_UPDATE`/`SPELL_DATA_LOAD_RESULT`.

### 2.3 Answer shape for H1

1. At load/login: build ID ⇒ name maps by **asking the client** (`C_Spell.GetSpellName(id)`,
   `C_Item.GetItemNameByID(id)`); never assume the read succeeded.
2. Any nil ⇒ mark pending, `RequestLoad*DataByID`, resolve on `ITEM_DATA_LOAD_RESULT` /
   `GET_ITEM_INFO_RECEIVED` / `SPELL_DATA_LOAD_RESULT` (payload `(id, success)` — respect `success`;
   Elle treats `SPELL_TEXT_UPDATE` as a success without a flag).
3. Don't bake the miss: keep the previous state and re-run (`EUI_CDM_HookPresetFrames.lua:808-810`),
   and re-sweep equipped slots on `PLAYER_ENTERING_WORLD`, not only `PLAYER_LOGIN`
   (`EUI_CDM_HookTrinkets.lua:387-390`).
4. Never persist a name-only key captured during a nil window; names become keys only **after**
   resolution — which is exactly the `*ByName` alias work the H1 row asks for.

### 2.4 Simulator probe (what the sim does **and does not** show)

```
cd /tmp && $WORK/wow-ui-sim/run.sh wow-sim --allow-ui-version-mismatch \
    --delay 2500 --exec-lua @/tmp/fx_locale_probe.lua dump-tree
```

Observed (2026-11-02, this machine): `FXPROBE start locale=enUS build=16001`; for all 14 equipped
item IDs (`GetInventoryItemID("player", 1..16)`; `Enum.InventoryType` exists)
`C_Item.IsItemDataCachedByID` ⇒ **true** and `C_Item.GetItemNameByID` ⇒ a real name
(e.g. `211993 → "Entombed Seraph's Casque"`, quality 4). Arbitrary IDs `5512 / 19071 / 2589 / 13954`
also report `cached=true` with the fabricated name **`"Unknown"`**. No
`GET_ITEM_INFO_RECEIVED`/`ITEM_DATA_LOAD_RESULT` ever fired; a `C_Timer.After(1500, …)` callback
never ran in `dump-tree` mode (that mode exits after the `--delay` window).

⇒ The simulator **pre-caches item data and fabricates names for unknown IDs**: it proves the
enUS/sync path and the API shapes, and it can **not** reproduce (or disprove) the nil-until-load path.
Frequency on the real client = launch-day probe (`/fx probe`).

---

## 3. Do installed Forever addons localize spell names, or key by ID?

**Answer: they key by ID and never ship spell-name tables.** Localisation in the installed set is
(1) the addon's *own* UI phrases, (2) game names asked from the client by ID, (3) English text parsing
behind a `GetLocale()` gate.

### 3.1 Key by ID, ask the client for the name

| Addon | Evidence (paths under `<addins>/`) |
|---|---|
| CooldownMaster | Config keyed by **spellID**: `CooldownMaster/Core/Defaults.lua:307` `spellOverrides[spellID] = { visible, lane, bar, … }`; ID keyspaces documented at `CooldownMaster/Core/Constants.lua:61-71` — `:70` "Item entries are keyed by itemID, which overlaps the real spellID range (5512 is both a spellID and an itemID)". Name/icon resolved at display time: `CooldownMaster/Core/Engine.lua:193-198` (`C_Spell.GetSpellInfo(spellID)` ⇒ `info.name, info.iconID`), `CooldownMaster/UI/SettingsFilters.lua:692-696`. Name maps are **built from client-supplied names**, never literals: `Core/Engine.lua:37-38` `_castNames [cast spellID]=name`, `_cooldownByName [spell name]=id` ("Classic and Forever"). |
| NeedRoll | Recipe/profession/talent/pet/poison names all `C_Spell.GetSpellName(spellID)`: `NeedRoll/Core/Names.lua:206-209`, `UI/ClassSpells.lua:263,634`, `UI/LootGrid.lua:1452`, `UI/TalentPlanner.lua:92,115,159`, `UI/WarlockPets.lua:403,471`, `UI/HunterPets.lua:710,734`, `UI/Questlines.lua:414`. Item names via `C_Item.GetItemNameByID` (§2.2). Design rule — `Core/Names.lua:1-16` and `docs/LOCALIZATION.md` §"Names in the data": "**The data files stay English.** On any other client `Core/Names.lua` asks the game for each name by its ID **after login** and rewrites the loaded data in place". |
| EllesmereUI (Family) | `EllesmereUI/EllesmereUI_Locale.lua:9-12` design law: "**translate the pixels, never the data**" — translation applied at the `:SetText` render boundary so "the English identity fields used for search, page dispatch, and unlock-mode routing keep byte-matching English for free"; `L()` (`:60-71`) refuses to translate non-strings, secret values, pure numbers and letterless strings; `EnKey()` (`:84-87`) reverse-maps an on-screen translation back to English for comparisons; `Lf()` (`:75-78`) uses positional `%1$s` specifiers so translators can reorder. |

### 3.2 Own-text locale files: shape, and how they are gated

- Count (computed over the installed tree, filename pattern `<locale>[_suffix].lua`):
  **14 of 68 installed addons** ship per-locale files —
  `TidyPlates_ThreatPlates 12, Auctionator 11, NeedRoll 11, EllesmereUILocales 10, OpenMap 10,
  WhisperMessenger 10, Polestar 9, Polestar_Recorder 9, NodeSight 8, PrettyTooltip 8,
  CooldownMaster 7, WarEffortScout 7, Lueur 5, QuestieDB 1`.
  Union of codes: `enUS enGB deDE esES esMX frFR itIT koKR ptBR ruRU zhCN zhTW` (community files also
  cover `itIT`/`zhCN`, which the **shop** does not list for Forever).
- Two gating styles coexist:
  1. **TOC file annotation** — `EllesmereUILocales/EllesmereUILocales.toc:22-31`:
     `deDE.lua [AllowLoadTextLocale deDE, enUS, enGB]`, `esES.lua [AllowLoadTextLocale esES, esMX,
     enUS, enGB]`, `esMX.lua [AllowLoadTextLocale esMX, enUS, enGB]`,
     `zhCN.lua [AllowLoadTextLocale zhCN, zhTW, enUS, enGB]`, … (module-scoped copies at
     `:37-45`). Header `:13-21`: each line lists "its own language, the paired language a client may
     pick in EUI Options Language (esMX clients read esES; zhCN and zhTW read each other), and
     English … So a non-English client parses its own file (and its pair) only". File `:1`:
     `## Interface: 120000, 120001, 120005, 120007, 120100, 120105, 16001` (Forever = **16001**).
  2. **Lua self-guard** — CooldownMaster `Locales/deDE.lua:11`, `frFR.lua:11`, `koKR.lua:11`,
     `ruRU.lua:11`, `zhCN.lua:11`, `zhTW.lua:11`: `if GetLocale() ~= "<locale>" then return end`;
     English-key metatable with untranslated-falls-back-to-English documented at
     `CooldownMaster/Locales/enUS.lua:4-8`. Registry/chooser form:
     `Auctionator/Source/Locales/Main.lua:25-32` (`AUCTIONATOR_LOCALES[GetLocale()]`, else `enUS`).
- Runtime locale normalisation + fonts: `EllesmereUI/EllesmereUI_Locale.lua:35-38`
  `SUPPORTED = { enUS, deDE, esES, esMX, frFR, itIT, ptBR, ruRU, koKR, zhCN, zhTW }`;
  `:144-147` and `:201-205`: `local client = GetLocale(); if client == "enGB" then client = "enUS"
  end; if not SUPPORTED[client] then client = "enUS" end`; per-locale glyph fonts `:120-131`
  (`zhCN→Fonts\ARKai_T.ttf`, `zhTW→Fonts\bLEI00D.ttf`, `koKR→Fonts\2002.TTF`,
  `ruRU→Fonts\FRIZQT___CYR.TTF`) plus the CJK/Cyrillic script class (`:135-138`); CJK line-height
  special case `EllesmereUIChat/EllesmereUIChat_Engine.lua:381-385`; locale-conditional runtime
  strings `EllesmereUI/EllesmereUI_FriendsKit.lua:1143-1145`,
  `EllesmereUIFriends/EllesmereUIFriends.lua:840-841`; locale-keyed gameplay tables
  `EllesmereUILocales/koKR.lua:72-75`, `EllesmereUILocales/ptBR.lua:8857-8860`.
- Locale data as **separate addons**: the install carries `Polestar_Names_<locale>` and
  `Polestar_Guides_<locale>` for `deDE esES esMX frFR koKR ptBR ruRU zhCN zhTW` (9 each) — the
  ecosystem treats locale data as a pluggable satellite loaded by language.

### 3.3 English text parsing is explicitly locale-gated

`EllesmereUICooldownManager/EUI_CDM_HookTrinkets.lua:187-190`:

```lua
local locale = GetLocale()
if locale == "enUS" or locale == "enGB" then
    -- The "Use: ... (X Min Cooldown)" line is the use spell's DESCRIPTION,
    -- loaded separately from the item data: on a cold spell cache the tooltip
    -- omits the line entirely and the scan would read an on-use trinket as passive.
```

with the non-English branch taking a **different, text-free** decision path
(`:246-249` `isRealOnUse = true; scanConclusive = true`), while the English branch parses
`ITEM_SPELL_TRIGGER_ONUSE` tooltip lines (`:196-245`, incl. the `|4Min:Min;` plural-token reducer at
`:220-223`). The same addon scans a **localized** "Use:" prefix from the *instance* tooltip for
enchant/tinker effects (`:152-172`, via `C_TooltipInfo.GetInventoryItem("player", slotID)` +
`ITEM_SPELL_TRIGGER_ONUSE`). ShadowFlare's documented trick is the same idea in ID form: derive the
buff name from `C_Spell.GetSpellName(enchantSpellID)` minus the `"… - "` prefix, "**so it works in
any language**" (`docs/reference/addons/shadowflare.md:125`, `:361-364`).

`NeedRoll/docs/LOCALIZATION.md` (rule for all shared data): "**Never translate strings the code
compares, stores in SavedVariables or sends to other players.**"

### 3.4 Spell-name lookups are locale-bound (for H1's `*ByName` aliases)

No primary source states "`C_Spell.GetSpellInfo(<English name>)` returns nil on a localized client"
⇒ **launch-day probe**. Supporting: the `spellIdentifier` union is "either a `spellID` (number) or
`spellName` (string)", resolved by `C_Spell.GetSpellIDForSpellIdentifier`
(`<agents>/skills/wow-api-spells-abilities/references/SPELLS-CORE.md:8`, `:80-84`) — names therefore
resolve through the client's own per-locale name table; and every installed addon above stores
**IDs** in data/SavedVariables or builds its name map from client runtime names
(`CooldownMaster/Core/Engine.lua:37-38`), never English literals.
`[INFERENCE]` English name lookups work **only** on enUS/enGB clients: keep ID keys as the source of
truth, treat `*ByName` as a derived, per-session locale-refreshed index (H1's stated design), and
never persist a localized name as a key.

---

## Launch-day probes (not answerable from disk; candidates for `/fx probe`)

1. **Real-client `GetLocale()` per install** — confirm the returned string for deDE/frFR/ruRU/koKR/zhTW
   installs (expected verbatim), and text/audio independence (two keys:
   `WTF/Config.wtf:33`, `:90`).
2. **Cold item cache at `PLAYER_LOGIN`** — log `GetInventoryItemID`, `IsItemDataCachedByID`,
   `GetItemNameByID` per equipped slot at `PLAYER_LOGIN` and at `PLAYER_ENTERING_WORLD`, then on
   `ITEM_DATA_LOAD_RESULT`; measure nil counts and arrival latency. Expectation from §2.2: some
   nil/empty; Elle's shape is the reference implementation.
3. **`C_Item.IsItemDataCachedByID` / `RequestLoadItemDataByID` / `ITEM_DATA_LOAD_RESULT` callable and
   fired** on a live client (catalog flags them `runtime: unknown`, §2.1).
4. **Name lookups on a localized client** — `C_Spell.GetSpellInfo(<English name>)` ⇒ nil?
   `C_Spell.GetSpellName(id)` ⇒ localized? Same ID's `C_Item.GetItemNameByID` differs per locale
   (names = display, never identity).
5. **`[TextLocale]` / `[AllowLoadTextLocale]` honoured by the 16001 loader** (installed addons depend
   on it, §3.2; the sim expands them to enUS only, §1.3).
6. **`enGB` reachability** — the engine's regional split exists
   (`<specs>/toc-regional-text-locale.md:20`) and Elle/CDM/TidyPlates code for it, but the shop never
   shows it; probe an EU install.
7. **ruRU playability** (§1.2 lockout) and per-locale fonts — `<_forever_>/Fonts/` holds only `.slug`
   caches, so CJK/Cyrillic glyph routing on Forever is unproven.

## Open questions

- Can one install present **two** text locales (base + override)? This machine keeps a single
  `WTF/Config.wtf` shared by `_forever_`, `_classic_beta_`, `_classic_era_`; FX is unaffected, noted
  for completeness.
- The shop list is **pre-launch marketing** — confirm against the live install picker during launch
  (the `ruRU` lockout shows advertised ≠ enabled in this window).
- Are `itIT`/`zhCN` accepted by the 16001 `AllowLoadTextLocale` matcher? At least one large addon ships
  files for them (`EllesmereUILocales.toc:26`, `:30`), so its author expects them to load.
- Does the Forever client ship `LOCALE_*` / `UI_LOCALE` globals that addons read (the retail
  `Blizzard_LoadLocale` mechanism the sim models, `<specs>/toc-regional-text-locale.md:21`)? None of
  the 68 installed addons read them — all call `GetLocale()`; not verified as *absent*.

## Method / provenance

- Installed client: the path in §Paths, incl. `.build.info`, `WTF/Config.wtf`, `Logs/{Connection,General,Hotfix}.log`,
  `UTILS/LOCALES/`, `Data/`, `Interface/AddOns` (68 addons).
- Pinned catalog + specs: `<agents>/**`, `<specs>/**` (Forever source pin
  `Gethe/wow-ui-source@ca8368f2f2380cbe696854f7f2646387c278a61b` = 1.60.1.70532,
  per `<agents>/docs/audit/FOREVER-SYMBOL-GAPS.md:3`).
- Simulator: `$WORK/wow-ui-sim/run.sh wow-sim … dump-tree --exec-lua @/tmp/fx_locale_probe.lua`
  (probe left in `/tmp`; the only file written into the repo is this note).
- Web: Blizzard EU forums (2 threads + 2 Italian threads), wowguide.net language list (shop-cited);
  Battle.net shop pages cited through that guide (direct fetch failed: redirect loop).
