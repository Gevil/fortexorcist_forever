# Zone ability spell icon

`C_ZoneAbility.GetZoneAbilityIcon(zoneAbilitySpellID)` must query the existing spell catalog. Cached Retail `ZoneAbilityDocumentation.lua` declares a required number argument, nilable numeric result and `SecretArguments = "AllowedWhenUntainted"`. C API-owned producer returns a catalog file ID or modeled nil miss; old placeholder-string path is removed. See [C API architecture](../lua-api.md).

## What it must do

- [x] Known Fireball spell 133 returns exactly one ordinary numeric value matching catalog `icon_file_data_id`, not a texture path.
- [x] A valid u32 absent from the catalog returns exactly one nil. Fixture 4,000,000,000 has absence asserted. This is explicit simulator policy consistent with nilable output, not native-observed miss behavior.
- [x] Preserve existing ordinary input rejection: missing/nil, non-numbers including numeric strings, non-integral/non-finite numbers and numbers outside u32 range fail explicitly. This preserves current extraction, not native parity.
- [x] Authenticate original secret arguments before numeric extraction/lookup: authentic VM host-secret known and absent IDs work untainted and fail tainted; plain known numeric IDs remain permitted tainted. Preserve wrapper identity/secrecy and caller taint across success, rejection and subsequent untainted reuse. Input secrecy does not imply secret output propagation.

## How it works

- [Existing spell API](../lua-api.md).
- [Cache provenance](../updating-blizzard-ui-to-a-new-patch.md).

## Implementation inventory

- `src/c_api/c_zone_ability_icon.rs`: catalog query, secret authentication and exact u32 validation.
- `src/lua_api/globals/missing_surface/zone_ability.rs`: existing namespace/state setup calls the modeled registrar; placeholder query removed.
- `data/spells.rs`: generated catalog, including required Skyward Ascent372610 sourced through `SpellMisc.SpellID`, not the unrelated row-ID372610.
- `src/bin/wow_cli/gen_spells.rs`: baseline required-ID selection retains372610 for normal regeneration; no new runtime fallback or CLI flag.

## Tests asserting this spec

`tests/zone_ability_icon.rs`: four behavioral cases for positive lookup, modeled miss, ordinary rejection and actual host-secret caller policy. Secret case uses existing `retail-12-0-5` VM-secret fixture gate. At `ff72f3c3b`, ordinary rejection passes; positive numeric result, modeled nil miss and untainted host-secret input fail at their real query boundaries. No observed fixture failures; later secret/taint assertions remain unreached in that RED. Executed scoped Retail producer GREEN: 4/4 PASS at `6b522c595`, including host-secret caller policy; [investigation SSOT](../wiki/investigations/integrated-source-and-factory-proof-2026-10-09.md#executed-staged-queries-and-new-producers).

## Original consumer catalog repair — 2026-10-14

The saved `983f02fbf` original zone-ability fixture retains spell372610 and requires a visible icon. Its catalog miss produced modeled nil. Installed-build CSV TEXT for12.1.5.70391 matches the earlier applied export manifest; header-aware joins establish name `Skyward Ascent`, subtext `Skyriding`, SpellMisc row631333/difficulty0, icon4640498/school1, and SpellEffect row997338/index0/target18. This recorded source-build relationship is not native profile/epoch equality.

Scoped generation reuses the existing PHF writer with a typed snapshot of the original catalog and precisely this sourced record; no fabricated CSVs, hand-editing of generated entries, broad data swap, vendor override or replacement test spell. A separate compiled typed comparison passes:5505 existing records retain all five semantic fields; only372610 is added. Physical PHF ordering/displacements may change. Descriptions/power catalogs are untouched. Independent default Retail proof at compiled`1b94ffff3` passes the unchanged original zone consumer and4 existing positive/miss/input/secret policy cases, plus typed canonical comparison. [Repair matrix](../wiki/investigations/fullsuite-983f02-2026-10-14.md#bounded-repair-follow-up) owns the current49-case gate and diagnostics. Original zone startup/load errors remain recorded; the icon PASS is not globally clean startup.

## Known gaps (current cycle)

- [x] Compile/execute genuine RED and distinguish behavioral failures from fixture barriers.
- [x] Replace the string placeholder with one C_API-owned producer.
- [ ] Saved PTR4 zone-policy cases pass within the separate38-case [repair matrix](../wiki/investigations/fullsuite-983f02-2026-10-14.md#bounded-repair-follow-up); broader startup/native acceptance remains open; historical12 SMOOTH setup errors remain history. Current default733-record library/six-bin check and full format pass, with six manifest warnings and the format soft-high crossing retained; no clean-startup implication.

## Out of scope

Native miss/malformed-input behavior and native parity remain unknown. Active-ability membership, zone lifecycle, external addon caller acceptance and broader catalog/generated-data changes are not covered; the single sourced spell372610 repair above is included. Secret tests assert observable authentication failures, not internal lookup calls.
