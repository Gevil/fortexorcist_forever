# Wrath XML/Lua file-load diagnostics

Wrath 12340 file-open/XML-parse diagnostics belong to the loader, not Lua's error handler. Source: laptop native answer `xml-load-diagnostics-12340.md` (2026-10-20), refining batch3 Q-X2 (2026-10-18). [Loader mechanics](../wiki/systems/addon-loading.md#wrath-file-load-diagnostics) describe the implementation. Native modern Retail behavior is UNKNOWN; other profiles preserve current simulator behavior.

## What it must do

- [x] Wrath missing/unreadable XML records `Couldn't open <path>`; malformed XML records `Couldn't parse XML in <path>` before processing that document's children. Missing Lua Include/external Script records `Error loading <path>`. Native severity is STATUS_ERROR; simulator retains exact texts in the existing failure-warning collection without a new severity field or emission path.
- [x] Record each failed attempt synchronously at discovery in loader warnings, without Lua handler calls or entries in any canonical Lua-error collection. Propagated child errors must not add duplicate parent records.
- [x] Use backslash client virtual paths, collapse `..`, and preserve the failed child's identity. Derivation from addon-root-relative host paths is INFERRED simulator mapping, not native path tracking.
- [x] Parent XML siblings, external Script inline body and TOC tail continue. Malformed XML executes no document children. Runtime LoadAddOn succeeds, marks loaded and publishes ADDON_LOADED; runtime loader diagnostics remain retained.
- [x] Genuine Lua compilation, execution and OnLoad failures still reach the handler and canonical Lua collectors, including the unchanged original Wrath ScriptErrorsFrame consumer. Retail XML/Script loading preserves its current routing.

## How it works

- [Addon loader](../wiki/systems/addon-loading.md#wrath-file-load-diagnostics)
- [Earlier continuation contract](wrath-minimap-xml-labels.md)

## Implementation inventory

- `src/loader/xml_file.rs` — file-boundary classification and recursive XML execution.
- `src/loader/addon.rs` — addon warning ownership and TOC continuation.
- `src/loader/mod.rs` — finalized diagnostics.
- `src/loader/file_diagnostics.rs` — Wrath policy and inferred virtual-path formatting.

## Tests asserting this spec

- `tests/xml_load_diagnostics.rs` — diagnostic text, repeated failed attempts, original DebugTools consumer, continuation, runtime LoadAddOn and genuine-error/Retail controls.
- `tests/batch3_wrath_include.rs` — existing nested XML/Lua continuation.
- `src/loader/tests/xml_basics_extra.rs` — preserved non-Wrath handler/path policy from `03786f864`.
- `src/loader/addon.rs` missing-TOC test — profile-specific XML text with unchanged missing-Lua and no-handler contracts.

### Bounded proof — 2026-10-20

Source-bound RED `d3dc2100b` reaches unchanged original DebugTools (`file diagnostic polluted original ScriptErrorsFrame`); earlier grouped RED also proves canonical sink pollution and missing retained texts. FrameXML alone does not load DebugTools: its original TOC is explicitly loaded.

Producer `c7436722a`: Wrath diagnostics5/5 plus preservation62/62. Later Rust changes only adjust existing/new test expectations: missing-TOC native XML text and Retail's current pathless parse-error policy. Retail preservation61/61 passes through `637851d2a`. Integration ELFs contain only this worktree's test paths (Wrath1,026; Retail1,963; no foreign paths); every selection runs nonzero tests. Direct vector pushes establish synchronous recording by source inspection; tests observe retained records and callback effects, not an intermediate native logger.

Both separately built stock binaries return `[]`, exit0, for `--no-addons --no-saved-vars lua-errors`. Child-only XDG data directories copy current persisted CVars byte-for-byte; original stat/hash remain unchanged. Formatter checks pass; builds emit no warnings. Proof reference: commit `c36561423`, `tests/xml_load_diagnostics.rs`, filters `wrath_xml_diagnostics_` and `retail_xml_diagnostics_`. No broad suite, independent gate or non-Retail/non-Wrath execution is claimed.

## Known gaps (current cycle)

None within the bounded file-diagnostic contract. Other-profile runtime matrices and native Retail channel authentication remain outside this change.

## Out of scope

Optional context headings, FrameXML.log writing, native printf quirks/255-byte truncation, unknown-element/schema diagnostics and modern Retail native parity. Existing `report_xml_error` must remain active for genuine inline Lua compile failures. No vendor or rilua changes.
