# Patch 12.1.7 TOC metadata and regional text locale

The TOC parser in `src/toc/` selects addon metadata and ordered file entries. Patch 12.1.7 separates metadata-variable rejection from the regional file-locale capability shared with Forever. See [addon loading](../wiki/systems/addon-loading.md) for the loader boundary.

## What it must do

### Epoch selection

- [ ] `retail-12-1-7` cumulatively includes `retail-12-1-5` and `regional-text-locale`. `client-ptr` selects interface `120107`; default Retail stays `120105`, Forever `16001`, and older explicit epochs retain their interfaces.

### Metadata

- [ ] Only `retail-12-1-7` skips an entire `## Key: value` line when the value contains `[Game]`, `[Family]`, `[TextLocale]` or `[RegionalTextLocale]`, before stripping annotations or inserting metadata.
- [ ] Skipped lines create no metadata or dependency effects and preserve previous accepted values. Supported conditional-only annotations and subsequent ordinary overrides keep their existing order and behavior.
- [ ] Older epochs and Forever retain their existing metadata parsing; this feature does not repair historical metadata expansion.

### File selection

- [ ] `regional-text-locale` is shared by `retail-12-1-7` and `client-wowforever`, without enabling a Retail epoch on Forever.
- [ ] Parser locale/region input is explicit and defaults to `enUS`/`US`. `[RegionalTextLocale]` differs from configured `[TextLocale]`: English `enUS` selects `enUS` in US and `enGB` in EU; Portuguese selects `ptBR` in US and `ptPT` in EU. Locales without a regional variant retain their configured spelling.
- [ ] The original 70424 `Blizzard_LoadLocale.toc` and unmodified locale Lua files load through the normal ordered loader, publish the selected `UI_LOCALE` and `LOCALE_*`, leave other locale flags absent, and produce no missing-file warnings.
- [ ] Existing `[Game]`, `[Family]`, `[TextLocale]`, conditional, bootstrap and environment file annotations remain operational. Builds without the capability do not expand `[RegionalTextLocale]`.

## How it works

- [Addon loading and TOC parsing](../wiki/systems/addon-loading.md#addon-discovery-and-toc-parsing)
- [Client profiles and cumulative epochs](../wiki/systems/client-profiles.md#retail-api-epochs)

## Implementation inventory

- `Cargo.toml` — cumulative epoch and shared capability selection.
- `src/client_profile.rs` — highest active epoch and interface identity.
- `src/toc/mod.rs` — metadata acceptance and ordered file-variable selection.

## Tests asserting this spec

- `tests/patch_12_1_7_toc.rs` — public interface, addon admission, normal metadata loader/API path and original LoadLocale consumer.
- `tests/fixtures/p1217-loadlocale/PROVENANCE.json` — exact Gethe revision, source-relative paths, lengths and SHA-256 hashes; fixture files are copied unchanged.
- `src/client_profile.rs` tests — historical/current interface selection.

## Known gaps (current cycle)

- [ ] Targeted executable RED/GREEN receipts await granted build capacity. Unchecked bullets are requirements, not passing claims.

## Out of scope

- PTR CDN pin/cache refresh and exact version/build acceptance: separate source-refresh slice; changing interface does not authenticate a new runtime cache.
- GUID obfuscation and inherited 1.60.1 APIs: independent patch slices, not TOC semantics.
- Other region mappings, locale aliases, malformed/unknown variables and native case-normalization behavior: no source oracle supplied.
- New locale settings UI, global environment mutation or coupling to `C_Intl` context objects: unnecessary for explicit parser input.

## Sources

- Warcraft Wiki `Patch 12.1.7/API changes`, build 70424, TOC 120107: variable-bearing addon directives are skipped; conditional directives continue.
- Warcraft Wiki `TOC_format`, Variables and Patch changes: regional English/Portuguese US/EU examples and Forever support; file variables remain supported.
- Gethe `wow-ui-source` revision `b87363e0770c2f15b1e2f154de8ad3b0cf3ea90a`, version `12.1.7.70424`: original `Blizzard_LoadLocale` consumer bytes, hashes in fixture provenance.
