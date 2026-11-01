# Markup stripping

The render and frame-dump paths strip WoW markup from text. Their implementations are in `crates/sim-render/src/lib.rs` and `src/dump/display.rs`; see the [rendering pipeline](../rendering-pipeline.md).

## What it must do

- [ ] Strip a named color escape through its colon without removing visible text.
- [ ] Preserve hyperlink display text after a named color escape.
- [ ] For a named color escape without a colon, stop at the next escape. This is simulator recovery behavior; native behavior is unknown.
- [ ] Continue to strip classic eight-character color escapes.

## How it works

- [Rendering pipeline](../rendering-pipeline.md)

## Implementation inventory

- `crates/sim-render/src/lib.rs` — render markup stripping.
- `src/dump/display.rs` — frame-dump markup stripping and whitespace trimming.

## Tests asserting this spec

- `src/render/text.rs` — named and classic color cases.
- `src/dump/display.rs` — named color and hyperlink cases.

## Known gaps (current cycle)

- [ ] Verify the named-color cases on both producer versions.

## Out of scope

- Native behavior for malformed named escapes is not established.
- Color rendering parity is not established by text stripping.
