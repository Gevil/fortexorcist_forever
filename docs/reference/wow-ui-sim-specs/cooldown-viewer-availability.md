# Cooldown viewer availability

`C_CooldownViewer.IsCooldownViewerAvailable()` exposes explicit environment-local availability and reason. Cached API metadata and 11.1.7 notes specify the bool/string returns, not a native eligibility algorithm. [C API architecture](../lua-api.md) describes the runtime boundary.

## What it must do

- [ ] Return exactly two non-nil values: boolean `isAvailable`, string `failureReason`.
- [ ] Model unsupplied state as `(false, "Availability not supplied")`; this default is simulator policy, not a native failure string.
- [ ] Preserve supplied boolean and exact reason, including empty strings, Unicode and whitespace; infer nothing from class/spec, cooldown catalog, settings or UI presence.
- [ ] Read live environment state on every query, including retained function references; isolate environments.
- [ ] Allow ordinary tainted zero-argument queries; native secret-return classification remains unknown.
- [ ] Project both values through the actual cached settings predicate; gate the unchanged bounded visibility consumer with supplied availability.

## How it works

- [Lua API and simulator state](../lua-api.md).
- [Client profiles](../wiki/systems/client-profiles.md).

## Implementation inventory

- `src/c_api/c_cooldown_viewer.rs`: owned availability input, default and live two-value query provider.
- `src/lua_api/state/sim_state.rs`: environment-local input field.
- `src/lua_api/state.rs`: default initialization.

## Tests asserting this spec

- `tests/cooldown_viewer_availability.rs`: eight public-query, isolation, taint and cached-consumer cases.

## Known gaps (current cycle)

- [x] Execute genuine query-boundary RED: all eight cases fail at `ff72f3c3b` on missing bool/string projection, including failure converting the actual cached settings predicate result; downstream visibility assertions remain unreached. No observed fixture failures.
- [x] Executed scoped Retail producer GREEN: 8/8 PASS at `6b522c595`; [investigation SSOT](../wiki/investigations/integrated-source-and-factory-proof-2026-10-09.md#executed-staged-queries-and-new-producers).
- [ ] Broader Retail/PTR runtime and default-check acceptance remain open; startup still fails with 12 SMOOTH setup errors, not clean.

## Out of scope

Native eligibility/reason vocabulary, automatic gameplay feed, Lua/Admin setters, new events, tooltip rendering, full addon visibility and other-profile native behavior are not modeled by this supplied-state query.
