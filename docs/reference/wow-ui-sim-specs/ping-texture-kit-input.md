# Host-supplied ping texture kits

`C_Ping.GetTextureKitForType(type)` must project a whole host-supplied type-to-string mapping, not an invented native catalog. Input/export/default and getter/registrar are implemented; six pre-producer tests failed at observed query boundaries; bounded Retail execution is recorded below. Architecture: [Lua API](../lua-api.md).

## What it must do

- [ ] Return exactly one string equal to the host entry, with no normalization, inference or substitute kit.
- [ ] Each environment starts with empty input; whole-map replacement changes future queries without affecting another environment.
- [ ] **Simulator miss policy, not native unknown-type behavior:** unmapped types error explicitly, identifying `unmapped ping type <type>` and `host-supplied mapping required`; no nil/empty/guessed-kit fallback or cached stale entry.
- [ ] **Simulator key policy:** accept finite integral numbers representable as the supplied map's `i32` keys; reject missing/nil, strings, booleans, tables, fractional/non-finite and out-of-range values before lookup. No native coercion, enum membership or native-range claim.
- [ ] Authenticate secret inputs before ordinary validation/lookup using `AllowedWhenUntainted`: an untainted secret numeric key may select a mapped entry; tainted secrets (including unmapped and malformed payloads) are denied without leaking/declassifying input. Public keys remain usable by tainted callers. Returned mapped strings are public by simulator policy; caller taint is preserved.
- [ ] Actual cached `PingManager:ShowPingSpot(type,posX,posY)` consumes the real query and passes exact `Ping_SpotGlw_<kit>_In`/`_Out` atlas names with use-size true to both sinks.

Cached `PingManagerDocumentation.lua` declares required PingSubjectType, non-nil textureKit and AllowedWhenUntainted secret arguments. It does not provide mappings or miss behavior. Arbitrary synthetic keys/kits in tests are host fixtures, not native pairs. Pre-producer secret-input tests failed at initial query assertions; bounded current GREEN reaches authentication and recovery/ordering assertions, without native security parity.

## How it works

- [Lua API architecture](../lua-api.md)
- [Addon loading](../addon-loading-pipeline.md)

## Implementation inventory

| Path | Role |
|---|---|
| `src/c_api/c_ping_texture_kits.rs`, `src/c_api/mod.rs` | Input map/export and exact lookup provider; registrar wired under `retail-12-0-0`. |
| `src/lua_api/state/sim_state.rs`, `src/lua_api/state.rs` | Environment input/default under retail-12-0-0. |
| `tests/ping_texture_kits.rs` | Six query/argument tests selected on Retail/PTR, generated integration module. |

## Tests asserting this spec

Generated `--test integration` filter `ping_texture_kits::` (expected six): configured exact strings/live replacement/isolation; empty/absent/cleared input error policy; invalid public key matrix; untainted actual VM secret numeric input; tainted actual VM secret numeric/unmapped/fractional/string denial plus public-input recovery; actual cached ShowPingSpot atlas arguments through controlled pool/frame/animation sinks. Secret fixtures assert query publication before setup. Consumer asserts real query before cache discovery or vendor loading. Sink spies prove call arguments only, not rendering/assets/lifecycle. At `ff72f3c3b`, all six fail real output, miss/invalid-input error or secret-policy assertions; no observed fixture/setup failures. Cached consumer loading and later authentication/recovery assertions remain unreached in that RED where prior assertions fail. Executed scoped Retail producer GREEN: 6/6 PASS at `6b522c595`, including VM-secret rejection/recovery and both exact cached-consumer atlas names; [investigation SSOT](../wiki/investigations/integrated-source-and-factory-proof-2026-10-09.md#executed-staged-queries-and-new-producers). Cache/setup failures are not query RED.

## Known gaps (current cycle)

- [x] Compile and obtain executed behavioral RED before implementing getter.
- [x] Execute source-backed ordinary/secret argument policy tests; retain pre-producer failures and bounded current downstream assertion reach.
- [x] Implement minimal getter after genuine RED.
- [ ] Mixed GREEN/startup/profile gate remains open: startup still fails with 12 SMOOTH setup errors, not clean; default-check/PTR acceptance remains pending.
- [x] Verify cached consumer prerequisite sufficiency in bounded execution, not full startup.

## Out of scope

Native/default/enum-complete mappings, GetDefaultPingOptions DTOs, auto-discovery, atlas existence/rendering, send/wheel/animation lifecycle, native coercion/ranges/secrecy and full-profile/native acceptance. Existing cooldown/default-options providers remain unchanged.
