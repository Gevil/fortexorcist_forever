# Generated data crates

Generated Rust catalogs live under `crates/sim-data` and `crates/sim-data-profile`. The root library preserves existing catalog API paths. See [design](../wiki/design/generated-data-crates.md).

## What it must do

- [x] Preserve generated catalog bytes and observable lookup behavior (all 23 file hashes and bounded catalog tests pass).
- [ ] Compile common catalogs independently of client selection.
- [ ] Preserve atlas, global-string and aura attribute selection through forwarded features.
- [ ] Preserve root exactly-one-client validation.
- [ ] Generators and Docker builds use the moved files.

## How it works

- [Crate boundary](../wiki/design/generated-data-crates.md)

## Implementation inventory

- `crates/sim-data/`: common catalogs and profession item overrides.
- `crates/sim-data-profile/`: profile-selected catalogs.
- `src/lib.rs`, `src/c_api/c_secrets.rs`: compatibility re-exports.
- `Cargo.toml`, `Dockerfile`: dependency and build context wiring.
- `tools/gen*.py`, `src/bin/wow_cli/gen_*.rs`: generator paths.

## Tests asserting this spec

- `tests/c_item_probes.rs`, `tests/c_spell_probes.rs`, `tests/texture_atlas_regressions.rs`: 52 integration preservation cases pass.
- `tests/generated_data_refresh_coverage.rs`: one Lua refresh-manifest preservation case passes; this does not exercise Rust catalogs.
- `crates/sim-data/data/*.rs`: 37 existing catalog unit tests pass.
- `crates/sim-data-profile/data/global_strings_retail.rs`: four existing selected-string unit tests pass.
- Six generator Python tests pass.

Other checklist requirements have static/build proof, not dedicated new regression tests: seven-profile metadata resolution, byte-identical root profile validation, copied original cfg expressions, cross-profile Fresh common unit and Docker COPY audit. See the [proof summary](../wiki/design/generated-data-crates.md#proof-status).

## Known gaps (current cycle)

No remaining gap in the requested static audit and bounded build/test gate. Unchecked requirements above lack dedicated regression tests; their static/build evidence is linked in the test section.

## Out of scope

Other crate cuts, test-harness restructuring, data regeneration, pushes and runtime changes.
