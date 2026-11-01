# Patch 9.0.1 publication sweep

Audit page 229972 revision 6471353 against current retail 12.1.0. Publication is not historical/native behavior parity.

## Requirements

- [x] Retain pinned source, recorded generator/extractor flags, every inventory/extract/caption occurrence.
- [x] Probe every inventory occurrence with integrated later registers and an exact reviewed gap fixture.
- [x] Retire only unused members with qualified/bare cached-Lua and whole simulator/test scans; preserve classic and deprecation wrappers.
- [x] Preserve earlier source bytes, extraction-mode outcomes and byte-identical register reproduction.
- [x] Verify all publication sweeps, one-ID negative control, affected bare/cached/Mists behavior, formatting, Mists warning boundary and startup `[]`.

## Exclusions

Historical client reconstruction, guessed constants/defaults, placeholder publication fixes, linked-page expansion, vendor/cache/Wowless edits, canonical/sibling writes, agents/models, push and merge.

## Retained boundaries

Exact gap identities and reasons live in the fixture and per-ID review; counts are derived, not a fixed compatibility contract. Substantive extract targets receive no behavior credit. At integration main thread prepends 9.0.2, then regenerates current observations, fixtures and coverage/evidence; placeholder excludes it on this branch.

## Current gap reconciliation — 2026-10-14

The saved `983f02fbf` default prefork sweep failed only on resolved/stale entries for `C_UIWidgetManager.GetDiscreteProgressStepsVisualizationInfo`; no new gap was reported. Reconcile the current known-gap fixture (262 → 261) with the already-modeled [discrete-progress contract](ui-widget-discrete-progress-steps.md). Source rows, IDs, later-register ordering and exact set equality remain unchanged. Historical reviewed captures/counts remain historical, not rewritten. This closes only obsolete missing-endpoint expectations; native/signature/payload parity is not inferred. The original default Retail prefork body passes at compiled`1b94ffff3`; [bounded repair matrix](../wiki/investigations/fullsuite-983f02-2026-10-14.md#bounded-repair-follow-up) owns the independent proof and retained diagnostics. Historical broad FAIL is unchanged.

## Sources

- `tests/patch_9_0_1_publication_sweep.rs`
- `tests/data/patch_9_0_1_sweep_known_gaps.json`
- [Audit, sweep table and proof](../wiki/investigations/patch-9-0-1-api-audit.md).

Integration (2026-10-08): 9.0.2 register prepended; 10 gaps superseded (273 → 263); `MatchesCurrentSpecSet` retained.
