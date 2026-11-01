# Patch 9.1.0 publication sweep

Account for page 17181 revision 167980 against current retail 12.1.0, not historical reconstruction.

## Required behavior

- [x] Retain pinned source, provenance flags, extract and all 179 inventory occurrences.
- [x] Parse the plain widget Scripts label only with an opt-in flag; preserve earlier registers.
- [x] Review exact cached publication gaps and later-register supersession.
- [x] Account for every extract/context ID without granting publication-only behavior credit.
- [x] Prove all publication sweeps, negative control, parser fixtures, formatting, Mists tests check and retail startup [].

## Current gap reconciliation — 2026-10-14

The saved `983f02fbf` default prefork sweep failed only on resolved/stale entries for `C_Item.IsDressableItemByID`; no new gap was reported. Reconcile the current known-gap fixture (51 → 50) with the already-modeled [dressability contract](item-dressability.md). Source rows, IDs, later-register ordering and exact set equality remain unchanged. Historical reviewed captures/counts remain historical, not rewritten. This closes only obsolete missing-endpoint expectations; native/signature/payload parity is not inferred. The original default Retail prefork body passes at compiled`1b94ffff3`; [bounded repair matrix](../wiki/investigations/fullsuite-983f02-2026-10-14.md#bounded-repair-follow-up) owns the independent proof and retained diagnostics. Historical broad FAIL is unchanged.

## Current widget-query reconciliation — 2026-10-15

Saved `39d38` prefork execution reports no new gap and only two resolved/stale expectations: `C_UIWidgetManager.GetSpacerVisualizationInfo` and `GetTextColumnRowVisualizationInfo`. `593e543f5` removes only those two missing-endpoint IDs (50 → 48), matching the implemented [Spacer](ui-widget-spacer.md) and [text-column row](ui-widget-text-column-row.md) queries. Preserve exact remaining set equality and historical captures. Independently accepted saved source `655f0698b` corrected prefork execution passes one case, exit0, reaching unchanged exact remaining 48-gap equality. Raw custom-harness output proves one pass despite empty parsed summaries; three empty harness groups add no cases. Two non-fatal CVar default mismatches remain: graphicsComputeEffects 4 versus 1 and RAIDVolumeFog 1 versus 0. This does not resolve the 48 gaps or prove payload/native behavior. See [saved bounded receipt](../wiki/investigations/test-suite-performance.md#saved-fullsuite39-bounded-runtime). Fullsuite39 remains historical FAIL.

## Proof boundary

192 IDs: 61 current absences, 65 publication/registration-only rows, 56 pending rows (51 exact gaps after 9.1.5 integration plus three summary contracts; two former gaps are now bounded 9.1.5 supersessions), ten metadata rows. Twenty-one unused namespace retirements closed; post-load tooltip placeholder remains classic-only. Two historical CVar defaults differ without current-state rewrites. Thirty sweeps have combined current-scope proof; first aggregate run's own 9.1.0 failure was resolved by the subsequent focused run, not hidden as an aggregate pass. See [audit](../wiki/investigations/patch-9-1-0-api-audit.md).

## Exclusions

No vendor/cache edits, placeholders, historical reconstruction, broad suites, agents/models, push or merge. Retail retirements preserve classic profiles and deprecation wrappers. Concurrent 9.1.5 register remains read-only and is inserted by integration.
