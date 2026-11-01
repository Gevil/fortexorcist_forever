# Slider value callbacks

`Slider:SetValue(value, treatAsMouseEvent)` synchronously delivers `OnValueChanged` after changing the stored value. Source: `src/lua_api/frame/methods/widgets/slider.rs`. See [event dispatch](../event-system.md) for script infrastructure.

## What it must do

- [ ] Deliver `(self, effectiveValue, treatAsMouseEvent)` before returning, with the updated value readable inside the callback; omitted mouse flag is `false`, explicit `true` is forwarded.
- [ ] Clamp and quantize Slider assignments as described below; suppress calls whose effective value is unchanged, including same-value reentry from a callback.
- [x] Dispatch pre/normal/post bindings in order, including intrinsic bindings when no normal script exists.
- [x] Report each handler error through the existing error handler and continue later bindings.
- [x] Permit callbacks to update other widgets and CVars without a held simulator-state borrow; hidden sliders still dispatch.

The cached Forever `SimpleSliderAPIDocumentation.lua` documents `SetValue(value, treatAsMouseEvent=false)`. Dispatch/order/error behavior follows the simulator's existing script model and unchanged addon usage, not a new native-client probe claim.

## Clean-room step assignment follow-up

C1 defines a shared clean-room simulator policy, not a recovered native algorithm or verified all-profile completion. Current positive default step remains unchanged. For finite ordered bounds and positive finite step, choose the nearest minimum-relative lattice value or the maximum endpoint; ties choose the greater numeric value. Step zero is continuous. Thus `[0,10]`, step2, value3 becomes4; step4, value9 becomes10 rather than8.

- [ ] Quantize only Slider programmatic value assignment; preserve StatusBar clamping and callback shape.
- [ ] Reapply the current stored Slider value through the same assignment when `SetValueStep` is called. Dispatch synchronously only if the effective value changes, with a false mouse flag after releasing the simulator-state borrow.
- [ ] Preserve offset/negative minima, exact endpoints, same-effective-value suppression and existing dispatch/reentry/error behavior. Keep existing clamp semantics for unsupported nonfinite values/bounds, invalid steps and unrepresentable spans without attempting lattice arithmetic. This does not establish their native argument policy.

Producer authored in `src/lua_api/frame/methods/widgets/slider.rs`: pure quantization used by `apply_slider_value`, plus step-triggered reapplication using the existing dispatcher. No default initialization, C8 range-callback/lifecycle, mouse-drag producer or StatusBar changes.

Actual Retail baseline: source `3fa90ab7b6f8cf836e09c19ed34115eba9f245c1`, epoch `cleanroom-controls-retail-baseline-20261015T223734529083Z/slider-step-first-red`, executed the five existing `tests/slider_step_assignment.rs` cases: **0 passed, 5 unique failures, exit 101**. Full stdout/stderr and `result.json` remain in the private verification archive under that epoch; no published receipt is claimed. Four failures report incorrect stored effective values; the duplicate-suppression case reports unwanted dispatch. These receipts establish reached RED against the clamp-only/stores-only producer, not GREEN for this edit.

Saved Retail source `05f1b4a62`: **five unique PASS, exit0**, independently reconciled against saved build/seal and full runtime streams; all test assertions reached. Coverage includes nearest lattice/max and upward ties, offset/negative minima, endpoints/duplicate suppression, step reapplication, and continuous Slider versus unsnapped StatusBar. The C1 quantizer/assignment path remains unchanged at `670e3d255`, but this is saved-source proof, not current-HEAD GREEN. Wrath/all-profile acceptance remains open; requirement checkboxes stay open. The fractional scale/CVar consumer explicitly chooses step0.01.

Saved Wrath `39d38`: C1 step assignment **5 PASS**; [shared Wrath receipt](editbox-text-position-selection.md#saved-bounded-wrath-checkpoint) owns build/hash qualifications and pending runtime audit5795. Current relevant-fix/profile proof remains open; no checkbox closure.

## Exact signed decimal lattice point — 2026-10-17

- [ ] With range `[-0.5,0.5]`, step `0.1`, prior value `0.5`, assigning `0` stores exactly zero and reports exactly zero synchronously; repeating zero remains silent.

The original Wrath Gamma consumer exposed remainder-subtraction drift: `(0-(-0.5)) % 0.1` becomes `0.09999999999999998`; subtracting that remainder then adding step yields `2.7755575615628914e-17`. Reconstruct adjacent candidates from integral step indices relative to the minimum instead: `-0.5 + 5*0.1` is exactly zero. Keep nearest-candidate/max-endpoint/upward-tie policy; no decimal rounding, Gamma special case or display correction. `tests/slider_step_assignment.rs::slider_step_assignment_preserves_exact_zero_on_signed_decimal_lattice` and the unchanged exact-zero assertion in `tests/wrath_gamma_basemip.rs` are RED before the arithmetic correction. Bounded normal-Cargo Wrath GREEN at `89a915a0c`: 34/34 PASS, including this strict zero case, all six step-assignment/five range-lifecycle/eighteen widget-slider cases and four Gamma/BaseMip plus one original Effects control. Exact argv, streams and exit0 live in private handoff `wrath-gamma-basemip-fix/wrath-slider-green.*`. This headless subset is not full-feature startup, current-master integration, Retail/other-profile preservation or native acceptance; those remain separate receipts.

## C8 changed-range callback/lifecycle candidate

Explicit shared simulator policy only, not a native-client claim. Saved Retail producer execution passes five cases; current-source/all-profile acceptance remains open. Existing validation remains owned by [widget range validation](widget-range-validation.md); C8 does not change it or StatusBar behavior.

- [ ] Make Slider-only `OnMinMaxChanged` publicly discoverable through `HasScript`, bindable/readable through `SetScript`/`GetScript`, and clearable without removing type capability or dispatching on binding alone; StatusBar does not support it.
- [ ] After successful validation of changed bounds, commit both bounds, synchronously notify `OnMinMaxChanged(self,min,max)` while the old stored value remains readable, then reapply that value through ordinary Slider assignment. Hidden sliders follow the same lifecycle; equal bounds are included.
- [ ] Reapply the value even without a range binding. Deliver `OnValueChanged(self,effectiveValue,false)` synchronously only when the effective value changes, with committed bounds/value readable in that callback.
- [ ] Notify range once when changed bounds retain the effective value, without a value notification; identical bounds are silent.
- [ ] Reuse C1's minimum-relative step/max-endpoint policy through the same `apply_slider_value` for range-triggered assignment, not a second quantizer. The step-interaction test depends on C1 and cannot independently establish C8.

Actual sealed Retail baseline source `05f1b4a62`, epoch `controls-producers-retail-green-20261015T235844431000Z/slider-range-first-red`: the five unchanged `tests/slider_range_lifecycle.rs` cases executed, **0 passed, 5 unique failures, exit 101**. Three capability failures (two invalid-handler errors and one `HasScript` false) prevent the range-order assertions from being reached. Two separate value-reapplication failures are reached: unbound range silently clamps to5 without a value callback; explicit-step range retains8 instead of9 after minimum changes to1. These are not five demonstrated ordering failures. Independent saved-runtime verification reconciles these boundaries; C1 assignment GREEN does not establish C8 range reuse.

Authored producer adds Slider-only script capability in `events.rs`, commits changed validated bounds without clamping the stored value, dispatches range bindings through the existing protected pre/normal/post dispatcher, then reapplies the captured stored value through `apply_slider_value`. Both range and value delivery occur outside simulator-state borrows, including hidden sliders. Identical bounds return silently after validation; StatusBar range application is unchanged. Existing error reporting and effective-value reentry suppression are reused.

Producer `bddb5eb11` plus `b4d806ec7` executes at saved Retail source `d16876fcc`: **five unique PASS, exit0**, with all assertions reached and independent full-stream/build/seal verification. The retained selection is `c8-producer-c7-c9-retail-baseline-20261016T003140348455Z/slider-range-producer-first-green`. Public Lua traces cover new-bounds/old-value range observation followed by effective-value observation, public binding capability, retained-value silence and C1 quantizer reuse. This is bounded saved-Retail proof, not current-HEAD, other-profile or native acceptance. Historical `05f1b4a62` RED and existing callback/C1 scopes above remain separate.

Saved Wrath `39d38`: C8 range lifecycle **5 PASS**; [shared Wrath receipt](editbox-text-position-selection.md#saved-bounded-wrath-checkpoint) owns pending independent-runtime and current-source qualifications. Shared criteria remain unchecked.

Defaults, range initialization, pre-initialization and first-value policy remain untouched and **UNRESOLVED**, outside C8. StatusBar, duplicate validation/quantizer tests, and speculative callback mutations of range/value are excluded. Existing dispatch/error/reentry guarantees are not weakened; this bounded set adds no separate proof for them.

## How it works

- [Event system](../event-system.md)
- [Widget system](../widget-system.md)

## Implementation inventory

- `src/lua_api/frame/methods/widgets/slider.rs`: changed-value application and synchronous slider script delivery.

[Bounded PTR C1/C8 execution](../baselines/README.md#ptr-shared-controls--2026-10-16) supplements saved Retail/Wrath evidence; its receipt owns source and acceptance limits.

## Tests asserting this spec

`tests/widget_slider.rs` in the grouped integration target:

- `set_value_dispatches_synchronously_with_mouse_payload`
- `set_value_clamps_suppresses_unchanged_and_allows_reentry`
- `set_value_dispatches_intrinsic_bindings_after_reported_errors`
- `set_value_updates_castbar_style_scale_and_cvar_consumer`

Frozen `d1e2487f` executes identical test bodies and XML intrinsic templates: four expected missing-dispatch failures. Committed producer `3d6017fe3` passes all nine grouped slider tests, including the four new callbacks and five existing slider regressions. Independent verification reuses that 9/9 proof, passes `cargo fmt --check` and default `cargo check --offline`, and runs a direct StatusBar regression: `/tmp/forever-addon-audit/verify-slider-value-ledger.json`.

Frozen `3d6017fe` runs unchanged ClassicCastBar `8909724` through scale `1 → 1.35 → 1`, icon toggles, reset and `DONE` with no Lua errors; the no-addons control returns `[]`: `/tmp/forever-addon-runtime/classic-slider-workflow-q675457h/ledger.json` and `/tmp/forever-addon-runtime/slider-control-0uwemvbq/ledger.json`.

## Known gaps (current cycle)

- [ ] Mouse dragging, settings navigation, casting behavior, rendered pixels and restart persistence remain unverified.

## Bounded Mists execution — 2026-10-16

[Shared Mists owner matrix](../baselines/README.md#mists-shared-controls--2026-10-16) owns independently accepted saved results, provenance, diagnostics and remaining profile limits. This supplements historical evidence, not native or broader contract acceptance.

[Bounded Era execution](../baselines/README.md#era-shared-controls--2026-10-16) separately accepts the corresponding matrix cases from saved artifacts only; current source and broader criteria remain unaccepted.

[Bounded Anniversary execution](../baselines/README.md#anniversary-shared-controls--2026-10-16) separately accepts the same corresponding matrix cases from saved Anniversary artifacts only; current source and broader criteria remain unaccepted.

## Out of scope

StatusBar behavior, other slider methods outside the step follow-up and bounded C8 candidate, mouse-drag producers, new secret handling, argument-validation fidelity and native timing conformance remain unchanged or unverified. No addon/vendor changes or manual callback invocation.
