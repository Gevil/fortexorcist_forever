# IPC Exec print output

IPC Exec returns the Lua-wrapped `print` capture for that request, not a second copy from the simulator console buffer. This records commit `f96644168`; execution and capture live in `src/iced_app/update_servers.rs`. See [Lua API architecture](../wiki/systems/lua-api.md) for the execution environment.

## What it must do

- [ ] Return only the request's Lua print capture on successful Exec; never append a duplicate console-buffer copy (`collect_lua_command_output`).
- [ ] Keep capture request-local: `print('one')` returns `one`, a following request without prints returns an empty string, and a later `print('two')` returns only `two`.
- [ ] Preserve repeated identical prints: `print('same'); print('same')` returns `same\nsame`, not a deduplicated result.
- [ ] Invoke the previously installed print function to preserve its normal side effects; capturing output must not replace those calls (`install_repl_print_capture`).
- [ ] Restore the previous print function after execution, including when execution returns a Lua error; an execution error remains an IPC Error response (`exec_lua_command`, `restore_repl_print`).

Unchecked items are source-grounded contracts, not newly verified test passes. The existing socket regression asserts the first three; it does not directly assert restoration or prior-print side effects. This docs-only change runs no tests.

## How it works

- [Lua API architecture](../wiki/systems/lua-api.md).

## Implementation inventory

- `src/iced_app/update_servers.rs`: Exec execution, print wrapping/restoration, capture-only output collection and response dispatch.
- `src/lua_server.rs`: IPC Exec command, Output/Error response types and socket transport.

## Tests asserting this spec

`src/lua_server/exec_tests.rs`, `exec_print_output_is_captured_once_per_call_across_connections`: real Unix-socket requests processed by the app; asserts single execution, exact single-print output, empty next-request capture and repeated identical lines.

## Known gaps (current cycle)

- [ ] Direct behavioral assertions for prior-print side effects and print restoration on success/error are absent from the socket regression.

## Out of scope

Native-client parity, changes to general print behavior, IPC protocol redesign and capture of non-print output. Request-local capture does not imply isolated Lua globals: the socket regression explicitly preserves globals between requests.
