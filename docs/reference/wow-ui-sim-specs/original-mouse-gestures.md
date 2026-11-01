# Original consumer mouse gestures

Bounded input contract for original Retail DamageMeter sizing and Wrath floating-chat movement. See [layout](../layout-system.md) and [events](../event-system.md).

## What it must do

### Retail DamageMeter

- [x] Original InitializeResizeButton mouse-down starts sizing; subsequent physical motion changes geometry without synthetic drag registration or replacement callbacks.
- [x] Bottom-right sizing preserves top-left; bottom-left preserves top-right. Outward movement increases dimensions; minimum/maximum bounds constrain them.
- [x] Stationary release and moved release while still on the handle clear native motion flags, capture, original isResizing and original userPlaced.

### Wrath floating chat

- [x] Original XML tab OnDragStart moves the owning chat frame by the cursor delta without resizing it.
- [x] After release, original FCFTab_OnUpdate reaches FCF_StopDragging and clears native motion, MOVING_CHATFRAME and tab dragButton.

## Implementation inventory

- `src/iced_app/mouse.rs`: physical down/move/up, registered script-drag threshold and release routing.
- `src/iced_app/mouse_drag.rs`: geometry and opposite-corner anchoring.
- `src/lua_api/frame/methods/misc/drag_input.rs`: StartSizing capture and StopMovingOrSizing cleanup.
- `src/iced_app/mouse_sequence_probe.rs`: shared Rust adapter that drives real App handlers and hit-grid construction; no Lua shim.

## Tests and proof

`tests/f2_original_mouse_consumers.rs` is shared between profiles. At source `5f5aa4563`, all six Retail cases pass: right/left geometry, maximum/minimum, stationary release and moved in-handle release. Five cases first reproduced geometry or cleanup RED; stationary release was already GREEN. Omitting physical mouse-up rejects the stationary stop assertion. Five unchanged native sizing-state tests pass. Geometry cases deliberately stop before release, so clamped motion does not assert outside-handle behavior.

The original callbacks were unchanged. [Capture/routing diagnosis](../wiki/investigations/mouse-sizing-capture.md#root-cause) owns the root cause and simulator repair; this spec owns acceptance and proof boundaries.

Wrath full original FrameXML loading reached original OnDragStart but reproduced no horizontal movement. The [Wrath sibling-capture diagnosis](../wiki/investigations/mouse-sizing-capture.md#proof-boundary) owns the capture repair. At `a23d6741d`, the original loaded XML gesture and original OnUpdate cleanup pass. Setting only the supplied frame's movable flag false preserves original OnDragStart dispatch but fails the horizontal-delta assertion, establishing non-vacuity. Cache/loader failures are setup failures, not behavioral RED; no shims may hide them.

## Exclusions and fact gaps

Native outside-handle release ordering and scaled native resize policy remain fact gaps; neither is asserted. No vendor edits, callback replacement, synthetic resize OnDragStart, docking/persistence redesign, complete startup or other-profile acceptance. Retail fixtures call the original initializer but not full DamageMeter OnLoad/OnShow.
