# Profiler clock frequency

Standalone `C_AddOnProfiler.GetTicksPerSecond()` reports an explicitly modeled nanosecond-unit frequency. Producer is registered in `src/c_api/c_addon_profiler.rs`; three pre-producer cases executed RED, bounded Retail execution is recorded below. Architecture: [Lua API](../lua-api.md).

## What it must do

- [ ] Zero-argument query returns exactly one finite positive Lua number.
- [ ] **Simulator policy, not native frequency parity:** return exactly `1_000_000_000` ticks per second, deterministically across repeated calls and fresh environments.
- [ ] Fixed elapsed nanoseconds convert consistently: seconds = ticks / frequency; milliseconds = ticks × 1000 / frequency. Conversion fixtures are not production elapsed-field proof.

Cached `Blizzard_APIDocumentationGenerated/AddOnProfilerDocumentation.lua` declares non-nil `frequency: BigInteger` and profiling ticks per real-time second, but supplies no numeric frequency. Nanosecond units are a labeled compatibility model, not hardware clock resolution or native CPU ticks.

## How it works

- [Lua API architecture](../lua-api.md)

## Implementation inventory

| Path | Role |
|---|---|
| `src/c_api/c_addon_profiler.rs` | Existing profiler namespace; nanosecond-policy frequency getter registered. |
| `tests/get_ticks_per_second.rs` | Three frequency tests, shared `retail-12-0-0` gate. |

## Tests asserting this spec

Generated `--test integration` filter `get_ticks_per_second::`: exact return count/type/finite positivity; repeated exact frequency across environments; fixed zero, 1ns, fractional-, whole- and multi-second conversions. All three fail at the real query at `ff72f3c3b` (nil instead of a finite positive number), with no observed fixture failures. Fixed-duration conversion assertions remain unreached in RED; executed scoped Retail producer GREEN is 3/3 PASS at `6b522c595`, covering fixed conversions, not production elapsed timing ([investigation SSOT](../wiki/investigations/integrated-source-and-factory-proof-2026-10-09.md#executed-staged-queries-and-new-producers)).

## Known gaps (current cycle)

- [x] Compile and execute behavioral RED against unchanged namespace.
- [x] Register standalone frequency getter after genuine RED.
- [ ] Mixed GREEN/startup/check gate remains open: startup still fails with 12 SMOOTH setup errors, not clean; default-check/PTR acceptance remains pending.

## Out of scope

`MeasureCall` and `AddMeasuredCallEvent` need truthful cumulative allocation/deallocation counters. Current heap size or heap deltas, zero counters and incomplete DTOs are not substitutes. Conversion tests do not verify callback execution, elapsed DTO fields, memory accounting or native clock behavior. Argument rejection, security and native integer-range parity are not inferred here.
