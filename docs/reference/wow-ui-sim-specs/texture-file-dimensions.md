# Texture actual-file dimensions

`Texture:GetFileWidth()` and `Texture:GetFileHeight()` report dimensions of the actual source image, not the Texture widget. The frozen [3.3.0 source](../../data/patch-api/sources/3.3.0-api-changes.wikitext), Texture section, lines 27–28, literally introduces both methods and describes “width/height of the actual file in use by the texture” and “0 if we can't access the texture for some reason”. It also warns that some Blizzard UI images returned incorrect values; this spec does not reproduce undocumented historical bugs. See [texture loading](../texture-atlas-system.md) for existing resolution behavior.

## What it must do

### Literal source contract

- [x] Publish callable `GetFileWidth()` and `GetFileHeight()` on Texture objects; each returns the corresponding actual source-image dimension.
- [x] Return zero when the source image cannot be accessed. Widget dimensions are not a substitute for file metadata.

### Inferred simulator integration contract

These requirements apply the literal contract to existing simulator state; they are not independent native-client observations.

- [x] Resolve local addon files through the configured `addon_base_paths`, including later roots, without requiring GPU initialization or CASC for those fixtures.
- [x] Return `(7, 5)` for the concrete wide WebP fixture and `(3, 11)` for the tall fixture, while independent widget dimensions remain `(101, 103)`; changing widget width/height does not change file dimensions.
- [x] Follow `SetTexture` source changes; absent, cleared, missing, undecodable, and color-only sources return zero rather than retaining previous dimensions.
- [x] UV cropping and tiling do not change actual-file dimensions.
- [ ] For an accessible atlas backing image, use full backing-file dimensions, not atlas-slot dimensions.
- [ ] Numeric fileDataID assignments use the existing manifest path resolution and actual accessible source metadata; unresolved/inaccessible files return zero. Merely preserving the ID does not prove dimensions.
- [x] Apply the existing secret-texture read policy before metadata lookup: an untainted caller may read; a tainted caller receives the same secret-origin denial as existing texture getters. A subsequent plain `SetTexture` assignment restores plain reads under existing policy.
- [x] Receiver scope: expose both getters in Texture's actual index, not ordinary widgets, WorldFrame, FontString or animations. Current bounded receiver/runtime proof passes 7/7, including WorldFrame scroll controls.
- [ ] Preserve all earlier WorldFrame lookups. Bounded scroll controls pass; exhaustive lookup preservation and opposite fresh-cache order remain unproved.
- [ ] Historical Texture placement is not seven-profile native availability. Retained native discovery omits both names without establishing removal; it remains unchanged.

## How it works

- [Texture loading and atlas resolution](../texture-atlas-system.md)
- [Lua API architecture](../lua-api.md)

## Implementation inventory

- `src/lua_api/frame/methods/widgets/texture/atlas.rs` — `GetFileWidth`/`GetFileHeight` adapters beside `SetTexture` and existing readable getters; implemented; six local-file tests GREEN at sealed `e3978fd48196`.
- `src/lua_api/frame/methods/widgets/texture/mod.rs` — both modeled getters remain registered.
- `src/lua_api/methods/frame_metatable.rs` — excludes the two names from non-Texture indexes. WorldFrame preserves all other base entries and has a separate key in the same cache because its object-type name is Frame.
- `docs/wow-client-diff/diff_methods_extra.txt` — exactly two expected Texture rows added to the default comparison fixture; no native capture or unrelated row changes.
- `src/lua_api/frame/methods/secret_origin.rs` — existing `require_texture_readable` policy and denial message.
- `src/texture.rs` — `TextureManager::new` initializes empty CPU maps; `with_addons_paths` stores configured roots without GPU initialization.
- `src/texture/resolve.rs` — existing `get_or_load_texture_size` resolves source metadata without populating the RGBA cache.
- `data/manifest_interface_data.rs` — existing fileDataID-to-path mapping.
- `tests/texture_file_dimensions.rs` — seven current bounded PASS tests: six local-file controls and one receiver-scope test.

The adapter checks readability, snapshots the frame's actual texture path/fileDataID and addon roots, releases the simulator borrow, resolves numeric sources through SetTexture's existing manifest route, and queries source metadata with a temporary TextureManager. An actual nonnumeric path takes precedence over a retained fileDataID, including atlas assignments. Color-only sources are excluded. Each getter returns only the requested component, or zero for unknown metadata. No new state, subsystem, or headless exclusion is added. A temporary manager discards its metadata cache between calls, so separate width/height calls can repeat path resolution and file-header I/O; this is an explicit cost of this simple choice, not a user-mandated no-cache policy.

## Tests asserting this spec

Parent reports six genuine RED results at revision `080`: fixture images and Texture construction reached, then missing `GetFileWidth`/`GetFileHeight` failures. Downstream geometry and secret cases were not reached. Sealed Retail integration at `e3978fd48196` passes all six local-file cases, exit0, reaching geometry/source/clearing and existing secret-read-policy assertions. Numeric-ID and atlas actual metadata remain untested; atlas10 + empty-clear1 regression passes do not establish them.

- `tests/texture_file_dimensions.rs::texture_get_file_width_reads_actual_source_not_widget_width` and `texture_get_file_height_reads_actual_source_not_widget_height` — independently call each missing public method against two exact WebP files and separate widget-size controls.
- `tests/texture_file_dimensions.rs::texture_file_dimensions_follow_source_changes_and_clearing` — source replacement, missing path, recovery, nil/empty/no-argument clearing.
- `tests/texture_file_dimensions.rs::texture_file_dimensions_are_zero_without_accessible_image_metadata` — unset, missing, invalid-image, and color-only sources.
- `tests/texture_file_dimensions.rs::texture_file_dimensions_ignore_uv_crop_and_tiling` — real file dimensions remain unchanged after verified UV, tiling, and widget-size changes.
- `tests/texture_file_dimensions.rs::texture_file_dimensions_obey_existing_secret_texture_read_policy` — sets only the existing `secret_texture` backing flag as a fixture, checks secure reads and exact tainted denial with an existing getter control, then restores plain reads through public `SetTexture`. No wrapper mutation or new secret state; secret ingestion is not tested.

### Receiver repair — bounded runtime proof

Separate e397 comparison: missing snapshot PASS; extra snapshot FAIL with 96 rows (64 VertexColor, 30 non-Texture file-getter leaks, two intended Texture additions). VertexColor repair is separate. `texture_file_dimension_lookup_is_texture_only_and_preserves_world_frame_scroll` checks actual lookup, public index enumeration, usable metadata getters and preserved WorldFrame scroll behavior. WorldFrame is engine-created; lookup sequences do not force fresh cache construction. Current bounded tests pass 7/7, exit0; both method comparisons pass 2/2. Native capture remains unchanged with exactly two legitimate modeled Texture extras. Graph PASS is not native parity; opposite fresh WorldFrame cache order remains untested.

## Known gaps (current cycle)

- [x] Targeted local-file GREEN: six PASS / zero FAIL at sealed `e3978fd48196`, exit0.
- [ ] Numeric fileDataID actual-file coverage has no established CASC-independent accessible fixture in this stage. Existing ID/path round-trip tests do not cover metadata dimensions; no synthetic manifest/state mutation or conditional skip substitutes for that proof.
- [ ] Atlas full-file versus slot dimensions remain untested: the existing `checkbox-minimal` mapping uses a Blizzard Interface path, which is not resolved from the temporary addon roots. No vendor/cache writes or manufactured atlas mapping are used to claim this boundary.
- [ ] Native-client parity and cross-profile runtime proof remain unestablished.

## Out of scope

New caches or texture subsystems, renderer/GPU changes, new secret policy or ingestion, historical Blizzard-image bugs, vendor/cache/Wowless writes, compilation/tests/checks/deployment in this adapter stage, and final integration acceptance.
