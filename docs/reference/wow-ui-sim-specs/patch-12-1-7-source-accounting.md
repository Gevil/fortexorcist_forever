# Patch 12.1.7 source accounting

Slice I0 freezes the public 12.1.7 source, its linked current 1.60.1 inventory and the TOC reference under `data/patch-api/sources/12.1.7-*`. Frozen page target: **12.1.7 build 70424, interface 120107**. The selected runtime source moved to **wowt 12.1.7.70493** on 2026-10-23; [source pin and regeneration](ptr-blizzard-ui-source.md) own that target. Frozen bodies/provenance remain historical, not 70493 evidence. Exact body SHA-256 identities replace unavailable MediaWiki revision IDs; no revision number is invented. [Investigation and reproduction](../wiki/investigations/patch-12-1-7-api-audit.md). This is source accounting, not implemented API coverage.

## What it must do

- [x] Validate frozen source bytes/hashes, source-linked P01–P12 and the supplemental patch-page-index entry offline; reject an empty API register substituted for the prose ledger.
- [x] Preserve all 1,876 inherited literal occurrences, including repeated names with distinct source-line IDs, defaults, command kinds and header disagreements; reject row identity/count corruption.
- [x] Keep inherited rows **UNKNOWN until slice I4** and return `runtime_complete: false`, even when every source row is accounted.
- [x] Retain GUID rows as a **deferred gap pending the user decision**, not as build-70424 behavior or implemented coverage.

### Direct prose and preservation rows

Source line numbers refer to the frozen wikitext files. P10–P11 incorporate the TOC reference rather than pretending the patch page contains an API table. The machine ledger retains exact source paths/lines for every row.

| ID | Requirement | Status at I0 |
|---|---|---|
| P01 | Includes API changes from 1.60.1. | Accounted; inherited applicability/publication/behavior **UNKNOWN until I4**. |
| P02 | Obfuscate Cast GUID server/spawn portions. | **DEFERRED**, pending user decision and future-build oracle. Existing `Cast-Sim-*` spelling is not native-format proof. |
| P03 | Obfuscate Creature GUID server/spawn portions. | **DEFERRED**, same decision/oracle boundary. |
| P04 | Obfuscate Vehicle GUID server/spawn portions. | **DEFERRED**; complete native GUID production is not established. |
| P05 | Obfuscate Pet GUID server/spawn portions. | **DEFERRED**; unsupported token/producer limits remain separate. |
| P06 | Obfuscate game object GUID server/spawn portions. | **DEFERRED**; supplied fixtures do not establish an identity producer. |
| P07 | Obfuscated values stable/unique in one session, incomparable across clients/restarts; GUID format otherwise unchanged. | **DEFERRED**; no algorithm, encoding, widths or secrecy changes invented. |
| P08 | Skip variable-bearing addon metadata directives entirely, rather than expanding them. | Accounted; **PENDING I2a** implementation and loader-facing proof. Not removal of file expansion. |
| P09 | Preserve conditional directives, including AllowLoadGameType. | Accounted; **PENDING I2a** preservation proof with metadata rejection. |
| P10 | Add RegionalTextLocale file variable from configured text locale and region; English/Portuguese US/EU examples. | Accounted from TOC reference; **PENDING I2b**, shared PTR/Forever capability. No blanket locale policy inferred. |
| P11 | Preserve existing Game/Family/TextLocale file variables. | Accounted from TOC reference; **PENDING I2b** ordered-loading preservation proof. |
| P12 | Interface/epoch 120107; page identifies build 70424. | Accounted; **PENDING I1/I3** selection/source-pin proof. Retail 120105 and Forever 16001 remain separate. |

The patch explicitly says GUID changes will be testable in a **future build of 12.1.7**. Documented build 70424 is not their native oracle. Deferral does not block the other slices and does not close P02–P07.

### Inherited 1.60.1 linkage

P01 links the current frozen 1.60.1 page, not the separately sealed historical audit. Its literal rows are retained without deduplication in `data/patch-api/sources/12.1.7-inherited-1.60.1.json`.

| Category | Added | Removed | Accounting boundary |
|---|---:|---:|---|
| Global API | 175 | 10 | Header says **176** additions; preserve disagreement, not a fabricated row. |
| FrameXML | 471 | 1,041 | Vendor changes, not 1,512 simulator Rust endpoints or native removals. |
| Widgets | 7 | 0 | Four ScriptRegion input methods, two Minimap methods and one 3D actor method; permanent 3D exclusion remains. |
| Events | 25 | 2 | Header says **24** additions; registerability alone is not payload/lifecycle proof. |
| CVar column | 138 | 7 | Added column contains **137 CVars plus command `dumpSmallAlloc`**. Command is not a CVar. Preserve literal defaults and absent defaults. |

No standalone enum table appears. **Every inherited row is UNKNOWN until I4** resolves row-specific PTR applicability, publication, behavior and native/original-consumer proof. Forever implementations are reuse candidates, not automatic PTR credit. Retail 12.1.5 remains unchanged without row-specific evidence. The [existing 1.60.1 spec](patch-1-60-1-source-accounting.md) and its immutable seals remain unchanged; source accounting never upgrades their behavioral gaps.

## I4a inherited applicability worklist

The companion `data/patch-api/sources/12.1.7-inherited-applicability.json` extends accounting without changing any I0 source, ledger or status bytes. Base revision: `571284aaa8bb29f17d27e90110e4f863921d9330`. Its 1,876 records retain complete literal occurrences, all six opposite-direction PvPObjectiveBanner IDs, 816 additions/1,060 removals, header disagreements, 144 CVars and the distinct `dumpSmallAlloc` command.

- [x] Validate exact IDs and literal fields against the frozen source, not counts alone; retain independent PTR/Forever/Retail applicability, publication, behavior, original-consumer and native statuses.
- [x] Retain 63 exact opposing-direction sweep intersections across 14 Retail modules, plus the register-only `GetArmorPenetration` reference. These provide no inherited-direction completion credit.
- [x] Retain 233 rows with exact-symbol lexical test candidates, separately from the 122 original source-candidate rows. Strings/comments and old assertions are discovery only; namespace suffix matches grant zero credit.
- [x] Reject disposable occurrence/default/kind corruption, direction collapse, command confusion, wrong namespace, unselected consumers, lexical upgrades, wrong-profile/build evidence and old-direction completion credit.
- [x] Preserve permanent unsupported 3D effects for the actor method; publication/factory status remains UNKNOWN.

**Accounting resolved: 1,876/1,876. Applicability resolved: 0/5,628 profile cells; unresolved: 1,876 per profile.** Selected publisher ownership, TOC chains and source binding are unresolved for every row. `literal_owner` records only a spelling prefix, not a proven selected addon. Proposed selector names are grouping work, not existing Rust selectors or applicability decisions. A fully UNKNOWN map is valid accounting, not closure of I4.

I3 has not accepted source revision `e30d17b106ce76a872c2bdfe69f95b4ec215fd06`: required PTR **wowt 12.1.7.70493**, Gethe `2cdbc7ff511ec6a8c2f4f8341accd1da44a3c9af`, 4,578 files. The base still pins **wowxptr 12.1.5.69594**, Gethe `49b69918fcdc77e109813281e4f537d45ec7dcbf`, 4,025 files. No PTR cache was read as 12.1.7. Public page build 70424 remains separate from the pending runtime pin. Forever needs its own accepted 1.60.1 source/selection receipts; Retail remains 12.1.5 preservation, never a surrogate.

`python3 -B tools/test_patch_12_1_7_inherited.py` exercises real validator CLI mutations in disposable roots. `python3 -B tools/validate_patch_12_1_7_inherited.py` validates the companion and unchanged I0 boundary. Historical joins use bounded existing registers, so unrelated later patch additions do not expand this audit. I4b owns accepted-source binding, selected Game/Glue/LoD ownership and grouped runtime observations; no producer or native-parity implementation belongs to I4a.

## I4b conditional static selection

The separate `data/patch-api/sources/12.1.7-inherited-static.json` overlays **only static PTR applicability**. It does not rewrite the I0 or I4a ledgers. Its 1,876 exact occurrence IDs each retain independent PTR/Forever/Retail dispositions. On base `7e786472d`, effective resolutions remain **zero**. The staged `CONDITIONAL_APPLICABLE` cells take effect **only after p1217-source `e30d17b106ce76a872c2bdfe69f95b4ec215fd06` merges**. They do not assert I3 runtime acceptance.

- [x] Bind to the exact I3 `wowt 12.1.7.70493` content-index SHA-256 `e84a8de626166c53d7cccbe0cba65e141488f8cf315d4b03a36c4f181585da00` and 4,578-path PTR manifest SHA-256 `ba4414999237ad7b50de73a2a61d7dd18fee31b2f2c3b70d5a21ad3cdc34d328`; authenticate every file's pinned size and content key plus cache provenance/completion before deriving any cells. Stale 69594 inputs and missing/changed files fail explicitly.
- [x] Select PTR Mainline/generic/Standard TOCs in runtime order, including underscore/hyphen and case rules, Game/Family substitutions, game-type allow/exclude, enUS, public environment, Game/Glue/Both and LoD. Follow document-level XML includes/scripts, with relative/addon-root/case path resolution. Record each witness's exact symbol, file/line/text/hash, owner, selected TOC, include chain and screen/load group.
- [x] Accept added-row static obligations from selected Lua declarations, exact native API calls, structured generated API/event documentation, and literal CVar/event consumers. Documentation establishes a source contract, **not a native factory or execution**. A selected declaration establishes an applicable publisher, not a successful addon load or global publication. No current-value/default/effect or producer proof follows.
- [x] Keep every removed occurrence UNKNOWN: 985 have selected surviving spelling witnesses, but removal/republication/alias provenance is not resolved. All six opposing-banner IDs survive: three added declarations are conditional; the three removed occurrences remain UNKNOWN. No simultaneous presence/absence requirement is invented.
- [x] Reject constant all-applicable/all-UNKNOWN/not-applicable overlays, altered dependencies/receipts/IDs, unselected files, namespace suffixes, locals/comments/strings, private environments, nonselected locales, stale pins and incomplete caches. These are static-classifier/validator controls, **not simulator producer RED**.

| Conditional PTR source obligations | Resolved on I3 merge | PTR UNKNOWN |
|---|---:|---:|
| Globals | 168 | 17 |
| FrameXML | 253 | 1,259 |
| Events | 23 | 4 |
| CVars / typed command | 16 / 0 | 128 / 1 |
| Widgets | 0 | 7 |

Conditional total: **460 resolved / 5,168 UNKNOWN** across three profiles (PTR 460/1,416; Forever 0/1,876; Retail 0/1,876). All runtime publication, behavior, original-consumer execution and native proof stages stay UNKNOWN. Witness groups overlap: 332 Game, 207 LoD and 122 Glue row memberships; these are not extra resolved cells. API documentation uses its own selected LoD publisher, not an observed factory or the documented API's native screen availability.

All 88 enumerated source-selection exclusions are non-public/non-enUS entries, including two prefix-style `[AllowLoadTextLocale: zhCN]` browser entries. No pinned cache file is missing; none of these exclusions supplies absence credit. Whole secure-addon passes are not modeled by this static tool, even when a global override might exist. Widget owner/factory construction, typed command registration, dynamic consumer arguments/aliases/assignments and all removal applicability remain open. No allocator dump, TTS/hardware change, source synchronization or runtime execution occurs.

Reproduce with `python3 -B tools/test_patch_12_1_7_static.py`. Validate the real companion with `python3 -B tools/patch_12_1_7_static.py --source-root <I3-checkout> --cache <authenticated-70493-AddOns>`; `--write` regenerates it from those read-only inputs. There is no cache fallback. Source decoding preserves every byte through a Latin-1 view of ASCII syntax, including non-UTF-8 comments; receipt hashes cover original bytes. The exact I3 pin and private cache are external inputs, not duplicated vendor source in this branch. I4a remains a sealed all-UNKNOWN accounting baseline; this conditional overlay is the later static disposition source.

## I4c: removal contradictions and excluded publishers

`data/patch-api/sources/12.1.7-inherited-i4c.json` supersedes the I4b static dispositions without changing I0/I4a/I4b bytes. It uses the same exact authenticated 70493 corpus and I3 dependency. That dependency is an ancestor of the I4c base `08b423c5c`; this is source availability, not a fresh runtime acceptance claim.

- [x] Preserve all 1,876 occurrence IDs and three independent profile cells. Resolve only conditional static applicability; publication, behavior, native retirement and successful original-consumer execution remain unproved.
- [x] Distinguish selected additions (`CONDITIONAL_APPLICABLE`), selected source contradicting a literal removal (`CONDITIONAL_REMOVAL_CONTRADICTED`), and explicitly excluded FrameXML publishers (`CONDITIONAL_UNSELECTED_PUBLISHER`). The last two are not new presence/absence assertions about the live native surface.
- [x] Record every selected declaration or direct identifier/function assignment with its source receipt and TOC/XML chain. Exclude local owners and function parameters. Trace rejected addon/file game filters, TOC flavors and actual pinned Game/Family siblings. All recognized declarations must have explicit exclusion receipts before granting excluded-publisher disposition; secure-environment uncertainty stays UNKNOWN.
- [x] Index literal spellings across all authenticated pinned text, including comments/strings. A missing spelling proves only bounded literal-source absence, never native retirement, dynamic-global absence or an alias relationship. Such cells retain UNKNOWN with the exact runtime question.
- [x] Keep native APIs, events, CVar registration/defaults, typed commands and widget factories UNKNOWN without supported selected witnesses. An unselected native consumer cannot establish native inapplicability. Retail/Forever require independent source proof, not copied PTR decisions.

| PTR disposition | I4b | I4c |
|---|---:|---:|
| Selected additions | 460 | 467 |
| Selected source contradicts literal removal | 0 | 987 |
| Explicitly excluded publisher | 0 | 208 |
| UNKNOWN | 1,416 | 214 |

I4c decides **1,202 additional cells**: **1,662 conditional static dispositions / 3,966 UNKNOWN** across profiles. The extra selected additions are seven literal `UnitFrameUtil` assignments to secure delegates. The two additional surviving removals are `LFD_CURRENT_FILTER` and `SCENARIOS_CURRENT_FILTER` assignments. Of the excluded publishers, 206 are added rows; removed `FormatProfession` is file-game-filtered and `ToyBox_UpdateProgressBar` is in the unselected Classic family branch.

For all **1,060 removed occurrences**, 987 contradict a literal-source retirement obligation, two have explicitly excluded publishers, and 71 remain UNKNOWN. Those 71 comprise 64 absent literal spellings and seven spellings without a supported selected declaration; none earns native removal credit. All six opposing banner occurrences retain separate directions and source dispositions. No replacement, alias, signature or behavior is invented.

The 214 PTR UNKNOWN cells have reason codes and exact runtime questions: five added literal-source absences, 71 unresolved removals, 121 CVar registrations, one typed command registration, nine native API/event questions and seven widget factories. Retail and Forever each retain 1,876 UNKNOWN cells requiring their own selected source first.

`python3 -B tools/test_patch_12_1_7_i4c.py` checks concrete synthetic selection boundaries and actual checked-in occurrence dispositions. `python3 -B tools/patch_12_1_7_i4c.py --source-root <70493-checkout> --cache <authenticated-70493-AddOns>` recomputes every receipt, exclusion, reason, question and occurrence from authenticated inputs; `--write` regenerates only I4c. The I4b authentication and I0/I4a validation controls remain applicable. No build, slot, cache synchronization or vendor write is required.

## How it works

- [Source import, validator and evidence limits](../wiki/investigations/patch-12-1-7-api-audit.md).
- [Historical Forever accounting](patch-1-60-1-source-accounting.md).

## Implementation inventory

- `data/patch-api/sources/12.1.7-api-changes.provenance.json`: public fetch identities, body hashes and target; three matching frozen wikitext files.
- `data/patch-api/sources/12.1.7-source-accounting.json`: direct prose, inherited linkage, source-only status and GUID hold.
- `data/patch-api/sources/12.1.7-inherited-1.60.1.json`: all literal rows, header counts and UNKNOWN triage; repository-relative lexical candidates only.
- `data/patch-api/patch-page-index.json`: supplemental 12.1.7 discovery, explicitly not a new allpages census.
- `tools/validate_patch_12_1_7_source.py`: Python-only validation using the existing literal parser; no shared generator changes or historical resealing.

## Tests asserting this spec

`tools/test_patch_12_1_7_source.py`: nine direct CLI fixtures cover empty-register substitution, accepted source-only output, omitted direct row, malformed inherited counts, repeated-name identity, missing index entry, changed source bytes, false inherited implementation credit and false direct completion credit. Run directly with `python3 -B tools/test_patch_12_1_7_source.py`; no Cargo build.

## Known gaps (current cycle)

- [ ] I1–I3: epoch selection, metadata rejection, regional file loading and exact PTR source refresh/runtime proof.
- [x] I4a: lossless inherited accounting and per-profile UNKNOWN worklist; zero Cargo.
- [x] I4b static staging: 460 conditional PTR source obligations, effective only after the exact I3 dependency merges; 5,168 conditional UNKNOWN cells. Effective resolutions on the I4b base remain zero.
- [x] I4c static classification: 1,202 additional source dispositions; 3,966 cells remain UNKNOWN with source/runtime questions. No native removal is claimed.
- [ ] I4b/I4c runtime and later: successful publisher/LoD loads, native factories, registration/defaults, all behavior and original-consumer execution remain unverified; static receipts are not implementation credit.
- [ ] I5: GUID timing decision and native oracle; P02–P07 remain deferred.
- [ ] I6: independent runtime/profile acceptance. A source-only validator success cannot satisfy it.

## Out of scope

Runtime implementation, vendor changes, new GUID policy, native parity, builds, source-cache synchronization and historical seal changes. The optional `/notes` fetch returned 404 and is excluded as non-authoritative. This ledger does not claim rendered/transcluded MediaWiki completeness.
