# Screenshot output format

`wow-sim screenshot` and live `wow-cli screenshot` select screenshot encoding explicitly. Source lives in `src/screenshot_output.rs` and the CLI/live capture paths below; see the [CLI reference](../wiki/reference/cli-commands.md#screenshot).

## What it must do

- [x] Default to lossy WebP, quality 15 for standalone capture and 65 for live IPC; force `.webp` regardless of the requested extension, including `-o frame.png`.
- [x] Accept `--png` in both CLIs, propagate the choice through live IPC, write lossless PNG preserving supplied RGBA bytes, and force `.png` regardless of the requested extension.
- [x] Preserve the default 1600×1200 viewport and existing source pixels, crop, color handling, and layout; format selection changes encoding only.
- [x] Report write failures rather than success; success messages identify the actual output path.
- [x] Leave Windows screenshot IPC unsupported.

## How it works

- [Screenshot commands](../wiki/reference/cli-commands.md#screenshot)
- [Rendering pipeline](../rendering-pipeline.md)

## Implementation inventory

- `src/screenshot_output.rs` — shared encoder and forced extension.
- `src/bin/wow_sim/{main.rs,gui_commands.rs}` — standalone option, capture, crop, and quality 15 save.
- `src/bin/wow_cli/main.rs` — live option and request.
- `src/lua_server.rs`, `src/lua_server_windows.rs` — IPC request transport and unsupported Windows client.
- `src/iced_app/{update_servers.rs,screenshot.rs}` — live dispatch, capture, crop, and quality 65 save.

## Tests asserting this spec

At Rust revision `8feefbdbd`, the targeted screenshot selection passed 12 tests (8 library, 3 wow-cli, 1 wow-sim). This proves the encoder/socket/App fixtures below; separate standalone runtime evidence is recorded afterward. Neither establishes native render parity:

- `src/screenshot_output.rs`: `png_preserves_every_rgba_byte_and_forces_extension`, `webp_has_riff_webp_signature_and_forces_extension`, `missing_parent_returns_write_error_for_both_formats`, `directory_destination_returns_write_error_for_both_formats` — encoder fixtures, extensions, and write errors only; not rendered output.
- `src/bin/wow_sim/main.rs`: `screenshot_png_selection_preserves_defaults` — standalone parsing/defaults only.
- `src/lua_server/screenshot_tests.rs`: actual Unix socket framing, public client forwarding, mpsc selection, omitted-field default, and response roundtrip.
- `src/iced_app/update_servers.rs`: `screenshot_commands_save_selected_format_after_crop` — live App command dispatch, GPU capture, crop, output signatures/dimensions, and success paths.
- `src/bin/wow_cli/main.rs`: `screenshot_png_flag_parses`, `screenshot_png_choice_survives_wire_roundtrip`, `screenshot_defaults_are_unchanged` — live parsing, serialization, and default control only; not a running-server capture.

## Verification status (2026-10-15)

- [x] Targeted screenshot tests GREEN at `8feefbdbd`: 12 passed, zero failed, independently reconciled in `verification/png-terminal-next/report.md` under `~/.local/state/wow-ui-sim/`. Pre-implementation corrected-argv RED at `76cb61c40`: two PNG failures and one passing default control. Source/focused formatting and workspace formatting checks passed.
- [x] Default `cargo check` and normal `wow-sim`/`wow-cli` build completed with exit 0. Saved runs under `~/.local/state/wow-ui-sim/verification/widget-discrete-progress-current/`: `screenshot-png-default-check-20261015T081147056455Z` and `screenshot-png-native-bins-20261015T081338925572Z`. Docs revision `12e9c46a9` retains Rust revision `8feefbdbd`.
- [x] Corrected standalone runtime captures both exited 0: `--png -o capture.webp` produced `capture.png`; no flag with `-o capture.png` produced `capture.webp`. Signatures and 16×12 dimensions match the requested crop of a 32×24 viewport. Actual `wow-cli` help includes `--png` and the 1600×1200 default. The initial PNG setup failure launched no process; it is distinct from these successful corrected runs.
- [x] Live App GPU capture/crop and actual Unix socket/public-client forwarding passed separate tests. These are not a full external GUI-process end-to-end capture.

### Evidence limits

Independent `verification/png-final-next/report.md` under `~/.local/state/wow-ui-sim/` confirms the default check, normal builds, sealed binary hashes, and corrected standalone captures. Decoded standalone PNG pixels are uniformly RGBA `(158, 195, 219, 255)`; this does not establish expected native pixel parity. Exact supplied-RGBA preservation is proven by encoder fixtures; quality 15/65 and unchanged crop/viewport/color/layout algorithms are source-audit evidence, not exhaustive rendered equivalence. Full external GUI-process end-to-end capture remains unverified. These limits do not add renderer-parity requirements to this encoding-only contract.

## Out of scope

Windows IPC support, renderer/color/layout changes, viewport or crop changes, and WebP quality changes: this contract selects encoding only.
