# GUI startup yielding

GUI startup settling yields between app updates without changing timer callback identity or invocation. Source: `src/iced_app/app.rs` and `src/iced_app/update_runtime.rs`; [mechanics](../event-system.md#startup-event-sequence).

## What it must do

- [ ] Draw records the first real canvas size without executing startup or resize Lua; startup waits until that size is available and runs its event sequence once.
- [ ] Service queued IPC before advancing startup on a timer update. A zero-delay callback that schedules another callback yields to the next app update; queued Exec can run between those generations and executes once.
- [x] Carry the initial ten-pass timer budget and sixteen settling OnUpdates, each followed by up to ten timer passes, across turns. A turn performs at most one timer processing pass and one settling OnUpdate; an empty pass ends its timer group.
- [x] Keep frame-rate startup ticks active after the first canvas is known until startup finishes, even with no timers pending. Complete cleanup, hidden-frame policy, layout/render initialization and initial texture warmup before drawing UI quads.
- [ ] After startup, dispatch resize Lua from timer updates rather than draw. Preserve ordinary timer behavior and headless settling.

## How it works

- [Event-system startup mechanics](../event-system.md#startup-event-sequence).
- [Wiki event system](../wiki/systems/event-system.md#startup-event-sequence).

## Implementation inventory

- `src/iced_app/app.rs` — first-canvas capture, settling progress, completion and tick subscription.
- `src/iced_app/update.rs` — IPC processing before message dispatch.
- `src/iced_app/update_runtime.rs` — startup advancement and subsequent resize dispatch.
- `src/iced_app/render_draw_frame.rs` — records bounds and returns empty startup batches.

## Tests asserting this spec

`src/iced_app/app_tests.rs`: `gui_startup_zero_delay_chain_yields_to_queued_exec`, `gui_startup_uses_first_real_canvas_size_for_display_size_changed`, `gui_startup_draw_defers_lua_and_keeps_event_order_once`, `gui_startup_branching_zero_delay_chain_spans_turns`, `gui_startup_waits_for_canvas_before_running_lua`, `gui_startup_settles_ready_timers_at_completion`, `gui_startup_settles_bounded_on_update_work_at_completion` and `gui_startup_closes_windows_created_by_startup_timers`. Existing timer/container regressions own ordinary invocation preservation.

`src/iced_app/app_startup_proof_tests.rs` adds App-level budget and completion-order oracles:

- `saturated_startup_carries_ten_pass_groups_and_sixteen_ticks_across_updates`: 170 recursive generations, exact timer/OnUpdate trace per update, completion only after the last ten-pass group.
- `empty_startup_groups_short_circuit_and_keep_fast_subscription_without_timers`: chat-free fixture, 17 updates, 16 OnUpdates, no pending timers and frame-rate startup subscription throughout.
- `startup_cleanup_layout_and_texture_warmup_precede_first_nonempty_quad`: timer-created filesystem texture and three hidden windows, decoded pixels before draw, then one correctly positioned textured quad and its upload bytes.

Startup completion now warms visible CPU texture sources before setting the completion flag; the previous request-only preload had no render requests before the first draw. These tests construct the actual App and invoke its shader draw without a GPU adapter; they do not prove GPU upload or presentation. See the [source-cache contract](texture-source-resolution-cache.md) for queued preload and reload coverage.

## Bounded App proof — 2026-10-18

Retail source `a4f2f2978f53960113efc88caf4fb5865b48cb4f`, based on `29fac7076965dd53973168c47d972e4090f27b98`: four new App proof tests and eight existing startup controls each selected exactly once, **12 PASS / 0 FAIL / 0 ignored**. Build: `--no-default-features --features sound,gui,casc,client-retail --lib --locked -j1`. Lib-test artifact SHA256: `a7d08e75b97acd1da26d093c5c785814e4156dd012c9c6688ace773622c56c75`.

- Saturation: 170 generations over 170 updates; initial ten passes, then sixteen OnUpdates with ten passes each. Full per-update trace asserts ordering and bounds.
- Empty groups: 17 updates, sixteen OnUpdates, no pending timers and seventeen frame-rate interval checks; idle interval resumes after completion.
- Completion order: three startup windows hidden, settled rectangle `(30, 50, 40, 20)` and decoded PNG pixels before the first nonempty draw; exactly four fixture vertices and matching 2×1 upload bytes in that primitive. App backdrop geometry is excluded by its separate texture request.

The unchanged warmup assertion failed before the separate visible-texture warmup fix: request-only preload had nothing to load before the first draw. Test commits and the product fix remain separate. The [source-cache proof](texture-source-resolution-cache.md#bounded-app-proof--2026-10-18) owns filesystem reuse/reload counts. Fixture runtimes disable CASC and preserve original persisted CVars; this is App construction/update/draw proof, not full addon loading, GPU prepare/upload/presentation or native-client acceptance.

## Known gaps (current cycle)

- [x] Attach bounded final-source Retail App receipts for B1/B2 (above); no broader profile or live-addon acceptance is inferred.
- [ ] Real Ellesmere GUI first-draw and IPC acceptance remains separate from the bounded App fixtures.

## Out of scope

Preempting a synchronous Lua callback, changing timer identity/arguments/taint/cancellation, headless startup policy, or claiming native scheduling parity.
