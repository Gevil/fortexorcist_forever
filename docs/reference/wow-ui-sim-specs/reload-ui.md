# ReloadUI

`C_UI.Reload` and legacy `ReloadUI` request a fresh Lua/UI environment after the invoking Lua call returns. The modeled request lives in `src/c_api/c_ui.rs`; environment retirement lives in `src/lua_api/` and is serviced by the environment owner. GUI and Lua IPC use the same operation. See [lifecycle mechanics](../wiki/systems/reload-ui.md).

## What it must do

- [x] Coalesce Lua reload requests without dispatching reload events or destroying Lua inside the invoking call.
- [x] Save declared account and character SavedVariables before retiring the old VM; read back table and scalar values during fresh addon loading. Do not apply the external import-size cap to just-written reload data or re-import stale WTF values over it. Keep `--no-saved-vars` disabled across reload and never write imported WTF files.
- [x] Discard old globals, frames, scripts, timers, animation state, templates and addon-loading state. Release the old Lua VM; rerun the real startup/addon-loading path with the original launch settings.
- [x] Preserve modeled server/session/player/world/party state and process IPC/texture/font resources. Clear GUI frame-ID, input and render caches before drawing the new UI.
- [x] Service reloads requested by Lua IPC, GUI shortcut, slash commands, events and timers only after the active Lua call unwinds; subsequent IPC commands use the new environment and retain print-output isolation.

### Dispatch factory isolation

- [x] Reuse constant simulator factories only for identical source and chunk names within the active VM. Each use must receive a fresh closure, current-global environment binding and independent top-level upvalues; no old-VM prototype or object may survive reload through this cache.
- [x] Preserve HookScript order, self/arguments, solo-hook result passthrough, chained-result discard and error boundaries; preserve direct/indirect attribute callbacks, per-frame state and observable taint before and after reload.
- [x] Preserve real XML method-handler inheritance/chaining order, result passthrough, per-frame method/upvalue isolation and fresh frame/script state after ReloadUI when reusing its constant factory prototype.

### Generated XML layer reconstruction

- [x] Reuse identical generated layer operations across instance identities and fresh ReloadUI VMs. Sixteen identical texture operations may compile at most one source chunk per reload, measured after warm initial loading over two real reconstructions.
- [x] Pass instance names, parent references and substituted relativeTo targets as invocation data; preserve creation order, named/anonymous identity, parentKeys/arrays, region properties, anchors, scripts, scoped environments and fresh objects. Never rewrite authored Lua or retain old-VM handles to obtain reuse.

Forever prerequisite RED at `0d1e54849`: both real reload behaviors complete, then the first budget assertion reports16 source compiles against1. Seven factory and15 reload/XML preservation controls pass. Retail RED was not measured.

At `23f1f629a`, the producer supplies fresh invocation argument tables through the existing bytecode path. Exact selector: `loader::tests::reload_xml_cost::reload_xml_layer_reconstruction_bounds_source_compiles`.

| Bounded capability | Forever | Default Retail |
| --- | --- | --- |
| Sixteen identical layer instances, two real ReloadUI reconstructions | Source compiles0,0; budget1 | Source compiles0,0; budget1 |
| Hook/attribute/XML-method factories: order, arguments, returns, private state, taint, errors and VM retirement | 7/7 PASS | 7/7 PASS |
| Existing IPC/app reload and XML property/anchor/name controls | 15/15 PASS | 15/15 PASS |
| Mixed Texture/MaskTexture/Line/FontString order, arrays, names and anchors; standalone FontString name/text/mixin controls | 4/4 PASS | 4/4 PASS |
| Library build, cargo check and shared cargo fmt --check | PASS; zero compiler warnings | PASS; zero compiler warnings |

Each profile executes27 exact cases, zero ignored, with fresh child-only XDG data copied from current CVars; original CVar stat/hash stay unchanged. This proves bounded compile reuse and preservation, not stock-startup cleanliness, native chronology, paired wall-time savings or unchanged full Ellesmere acceptance.

The budget parent must always execute its assertion, even when `WOW_SIM_RELOAD_XML_COST_CHILD` is inherited. Reconstruction runs through a distinct exact-test selector in a fresh process with parent-controlled profiling/cache settings, not an environment-selected parent branch. The marker regression requires both budget observations with source compiles0 and budget1. Re-proof after the verifier fix is pending; the table above remains historical evidence at `23f1f629a`.

### File-backed client state

- [x] Restore the file-backed EditMode cache using the initial layout name and config, without re-importing ServerSnapshot. The original EditMode consumer must select the same active layout after ReloadUI. Native reread timing/ordering is INFERRED and unasserted.

Wrath build 12340 chronology is authenticated by clean-room laptop reconstruction `0e4e9fe0`, independently checked at `228` (relayed 2026-10-19); this is static source evidence, not native execution. Retail engine chronology remains UNKNOWN. Existing simulator policy is documented in [event system](../event-system.md#startup-event-sequence); it is not proof of native Retail order.

### Wrath 12340 requirements

Verified 2026-10-19: among all seven active profile caches, only Wrath's shipped Lua calls bare `DisableAddOn` (`FrameXML/StaticPopup.lua:466`); Mists, Era, Anniversary, Forever, Retail and PTR call `C_AddOns.DisableAddOn`. Existing `register_legacy_addon_fns` is shared by every non-Retail/non-PTR profile. The added legacy registration is therefore Wrath-only and uses the exact `c_addons_disable_addon` backing function, not an alias table or workaround.

| Slice | Required boundary | Current proof |
| --- | --- | --- |
| A prerequisite | Original StaticPopup acceptance disables its selected addon, then requests reload | Exact fixture RED `1a20ccf65`; producer `2711a473e` GREEN through original popup and C_AddOns enable-state query |
| A | Deferred request waits outside cinematic playback; zero results, coalescing, no explicit combat rejection | Original-popup cinematic RED at `2711a473e`; GREEN 2/2 at `121e4fe47` |
| B | Temporary protected-action allowance and argless REGEN_ENABLED precede conditional LEAVING, then LOGOUT; handlers finish before addon SV serialization | Exact fixture `fa73666b1`: three feature-absence REDs, noncombat control passes; producer `439b8e806`, GREEN 4/4 compiled `51bd62586` |
| C | Per-addon code/bindings, account SV, character SV, then ADDON_LOADED(name), one argument | Wrath behavioral RED `06d7cbcee`, Retail payload RED `0a2e2fb3d`, and exact `f1f445ce5` scalar-clobber RED. Producer `437bca644`: Wrath 4/4 and Retail payload 1/1 GREEN at `35851e23f`; guarded-default nested/large/WTF control passes both before (`840385e82`, f1 production) and after the producer |
| D | Both account chunks ready: VARIABLES_LOADED inline before LOGIN/argless PEW; pending chunks may defer it past entry; no synthetic WoWUISim addon event | Exact `f1f445ce5` feature REDs; producer `24ba76443`, GREEN 4/4 at `159f9f36f`. Original ticked Stopwatch OnShow/OnHide outputs pass before (sealed `35851e23f` production with `159f9f36f` fixtures) and after D. GameMenu is blocked by early-bound missing-global fast handlers and the separate cursor gap; spellbook remains an uncounted diagnostic |
| E | Restore eligible named user-placed movable/resizable frames on new objects, excluding DontSavePosition; cancel mirror timers on LeaveWorld, retain totems/player context | Exact `f1f445ce5`: six feature REDs, disabled-persistence control PASS. Producer `f0937f6ac` plus readability `10023c3d9`: GREEN 8/8,20.84s, including inherited-scale roundtrip; disabled-persistence control passes both sides. Added scale fixture also fails missing-file on sealed pre-E `159f9f36f` production; numeric native parity is not asserted |

Managed Wrath loading executes addon code before each declared saved scope, once per file rather than once per variable. Account precedes character; persisted scalars and nonempty tables overwrite code defaults. Initial WTF import retains its size limit and priority; trusted reload reads simulator storage without reimporting WTF or applying that external limit. Other profiles retain their existing SV policy. Real-addon Retail startup and LoD notifications append a boolean derived from parsed named XML bindings, including conventional `Bindings.xml`; that value derivation is INFERRED, not native evidence.

Scope approval limits C to managed startup/direct-load SV ordering. C_AddOns runtime LoD persistence remains UNMODELED: `src/c_api/c_addons_runtime.rs:131,135` calls `load_addon_from_toc`, which passes no manager at `src/loader/mod.rs:492`; a new ownership seam is a separate follow-up. Slice E uses the independently verified 12340 placed-frame and file-format facts relayed 2026-10-19 from reconstruction `0e4e9fe0a4a9fa08027c5eed4b2c5e873739cfd3`. Original anchors and relative targets are NOT serialized. Save selects one corresponding frame/root point pair by minimum squared distance, with strict-first ties in TOPLEFT, TOP, TOPRIGHT, LEFT, CENTER, RIGHT, BOTTOMLEFT, BOTTOM, BOTTOMRIGHT order. Eligibility requires a named, user-placed, movable OR resizable frame, not DontSavePosition, with a queryable rect; visibility and relative-target name do not exclude it.

Load resolves the new frame by name. CURRENT movable frames replace points with the stored point against the SAME root point; CURRENT resizable frames receive stored size. Each applicable operation marks user-placed. Nonnegative levels are assigned subject to the native upward-delta cap of 128, followed by layout resolution. Load does not recheck DontSavePosition. Missing frames are skipped.

Native storage is character-local `layout-local.txt`, not Lua SV. The simulator uses the persistence manager's `storage_dir/<realm>/<character>/layout-local.txt`, creating directories normally only when a manager is present; disabled persistence writes nothing. Tests use temporary roots only. No test or producer may create/modify the real `~/.local/share/wow-sim` tree.

The exact writer grammar is `Version: 1\n`, then per frame `Frame`, `FrameLevel`, `Anchor`, `X`, `Y`, `W`, `H` lines, each `Key: value\n`, one space, signed decimal integers and uppercase point names; no separators and final LF. Ordinary writer-generated records are the scope, not oversized-name/truncation quirks. Reader keys are case-insensitive; CR/LF/CRLF delimit lines. Unknown keys and Version values are ignored. New Frame/EOF applies records; per-frame defaults are TOPLEFT, X/Y/W/H=0, level=-1. Invalid anchors retain the current point; signed numeric prefixes stop at the first non-digit. H deliberately resets with other fields instead of reproducing an unverified reconstruction carry-over quirk.

Documented simulator deviation: store its own unscaled layout units and round to nearest/ties-even. Divide displacement and resolved width/height by the frame's effective scale, including inherited parent scale; treat both axes identically. Scale itself is never saved or restored. Native uses width conversion for BOTH axes with lrintf; the DDCToNDCWidth/aspect factor A (F=1024*A) is unauthenticated and must not be guessed. Native rounding-mode parity is unmeasured. Files are round-trip equivalent in simulator units, with NO native numeric or byte parity for X/Y/W/H.

Wrath startup registers a pending account-variables callback. Ready chunks dispatch VARIABLES_LOADED inline; otherwise `set_account_cvar_chunk_ready` dispatches once when both chunks are ready, including after LOGIN/PEW. Reload retires the pending callback, not account readiness. This supplied completion seam does not model account networking. Wrath omits synthetic ADDON_LOADED("WoWUISim") and PEW has no arguments; other profiles retain their startup policy.

The request's unnamed taint gate/default/producer and feedback contract remain evidence-blocked. Do not invent them. SPELLS_CHANGED reload occurrence/order is UNKNOWN. General engine timer policy and full native shutdown persistence are not implemented by this bounded goal. Combat reentry notification is combat-bit conditional; its finer position among startup events is not asserted. The simulator ends the Wrath permission window in its world-entry helper after PEW; this placement is INFERRED simulator policy, not a new authenticated partial order. Combat state is never cleared to simulate this window. `InCombatLockdown` and the existing protected-frame state-change probe share the same permission predicate.

Pinned Retail API docs at `b9be9379719047977fca4dba1bb1d9988e8840b3` declare ADDON_LOADED(name STRING, containsBindings BOOL) and PEW(initialLogin BOOL, reloadingUi BOOL). Reload values and containsBindings value semantics beyond type are INFERRED. These declarations do not authenticate Retail chronology or other-profile payloads. The payload slice covers only real-addon startup and C_AddOns LoD emissions. Synthetic Retail ADDON_LOADED("WoWUISim") is deliberately unchanged and remains a separate non-native simulator-policy gap.

## How it works

- [Reload lifecycle](../wiki/systems/reload-ui.md)
- [Startup and dispatch](../wiki/systems/event-system.md#startup-event-sequence)
- [Addon loading](../addon-loading-pipeline.md)

## Implementation inventory

- `src/c_api/c_ui.rs` — modeled `C_UI.Reload`, also called by Blizzard’s public `ReloadUI` wrapper.
- `src/lua_api/globals/state_backed_queries.rs` — legacy Lua `ReloadUI` registration sharing the request producer.
- `src/lua_api/env.rs` — Lua VM construction and handle retirement.
- `src/lua_api/script_helpers.rs` — VM-local factory prototype anchors and fresh closure construction for HookScript and attribute dispatch.
- `src/loader/chunk_cache.rs` and `src/lua_api/globals/create_frame/template_chain/` — exact-name constant XML method factory loading with dynamic global slots disabled, as before.
- `src/bin/wow_sim/startup.rs` — real startup/addon-loading pipeline.
- `src/startup.rs` — startup event dispatch.
- `src/saved_variables.rs` — declared-variable persistence.
- `src/iced_app/update.rs` — GUI lifecycle owner and shortcut.
- `src/iced_app/update_servers.rs` — IPC execution boundary.
- `src/lua_server.rs` — persistent socket transport.
- `src/bin/wow_sim/main.rs`, `src/bin/wow_sim/gui_commands.rs`, `src/lua_errors.rs` — one-shot owner service before output.

## Tests asserting this spec

- `src/lua_api/reload_factory_tests.rs` — callback arguments/results/errors, hook/frame/upvalue isolation, environment rebinding, closure taint and real deferred VM retirement. Pre-change and post-change characterization pass.
- `src/loader/tests/reload_factory_xml.rs` — real XML templates and method handlers, inherited/chained order, independent frame state/method replacement, returns and fresh VM retirement. Pre-change and post-change characterization pass.
- `src/iced_app/app_tests.rs` — shortcut sentinel/frame/VM retirement and Lua-requested SavedVariables persistence.
- `src/lua_server/exec_tests.rs` — public Unix Exec request, reload, subsequent fresh environment and print output.
- `src/bin/wow_sim/main.rs`, `src/bin/wow_sim/gui_commands.rs` — dump/screenshot reload observation boundaries.
- `src/bin/wow_sim/startup.rs` — real `--no-addons` startup with declared Blizzard SavedVariables rebuilt through App.

## Final implementer gate — 2026-10-19

Production Rust is `10023c3d9`; final normal-code receipts compile `ce2a122ba` (docs-only delta). Test-only `3446189b6` isolates the Retail Settings payload fixture in a child process: real startup installs a process-global tracing subscriber once. The combined six-case batch reproduced a second-initialization panic before reload, then passed unchanged consumer assertions after isolation. Production logging was not altered. This module is gated by `test` and `profile-retail`, so the other proof scopes remain valid.

| Gate | Executed result |
| --- | --- |
| Wrath 12340 lifecycle | 23/23, no exclusions, full sound/gui/casc profile; C/D/E controls pass on both sides of their producers |
| Wrath shared owners/startup | Library 21/21; binary 3/5, with two unchanged, out-of-profile Console/EditMode fixtures failing before ReloadUI and explicitly classified non-blocking by the integrator |
| Retail preservation and payload | Library 21/21; binary 6/6 at `3446189b6`, including original Settings and non-default EditMode consumers |
| Compilation and format | Wrath/Retail GUI and headless checks: 4/4, zero warnings. Full format check passes at `3446189b6` |
| Stock startup | Wrath and Retail `--no-addons --no-saved-vars lua-errors` each emit exactly `[]` |

Receipts: `final-wrath-{check,headless-check,lib,runtime-abc2,runtime-de,bin-tests,startup}-receipt.json`, `final-retail-{check,headless-check,lib-reload,lib-startup,bin-tests2,startup}-receipt.json`, `final-fmt2-receipt.json`. Original persisted CVar hash/stat and directory listing remain unchanged; each runtime uses a copied current CVar file under child-only XDG storage. All builds/runs used capacity admission, the retained shared slot, 9-GiB single-job builds and 4-GiB/90-second runtimes.

The Wrath test build has one pre-existing `simple_html_tests.rs:2` unused import, byte-identical to the lane base and fixed separately by `65afa9064`; normal checks have none. No warning suppression or ignored tests were added. Full suites and native execution were not run. Independent integrated verification remains the next owner gate.

## Known gaps (current cycle)

- [ ] Independent integrated verification of these bounded Wrath/retail gates remains pending. Retail/other-profile native teardown ordering and target/focus preservation remain unconfirmed.
- [ ] Keyboard/mouse model-state preservation is INFERRED and unasserted pending native lifecycle evidence. Keep `mouse_position`, `mouse_buttons` and `pressed_keys`; discard frame-ID input caches, not these model values.
- [ ] Full Ellesmere acceptance and standalone `wow-cli` executable reruns remain separate from the bounded Unix-socket client proof.

### Bounded retail proof — 2026-10-19

69 logical cases pass, zero ignored: 64 library/App/socket/persistence cases at `e23196863` and five binary owner/startup cases at `79f52bb3f`. Only binary startup code and docs changed between these source points; the library proof remains valid. The EditMode case's isolated child is the same logical case, not an additional one.

Historical RED: four original freshness assertions on `f254e22ee`; dump/screenshot owner assertions on `6987f6145`; scalar/import-cap assertion on `5703ecc56`; original EditMode consumer assertion on `00f8dc298`. Private RED receipts: `red-{lib,startup}-receipt.json`, `owner-red-{lib,startup}-receipt.json`, `persistence-red2-lib-receipt.json`, `editmode-red-startup-receipt.json`. Current GREEN receipts: `input-green-lib-receipt.json` and `editmode-green-startup-receipt.json`.

| Capability | Behavioral evidence | Limit |
| --- | --- | --- |
| Deferred request and IPC isolation | Invoking chunk returns; already-queued Exec and real subsequent socket connection see fresh globals; print capture stays isolated | Acknowledgement is not startup-completion notification |
| VM/UI retirement | Old VM weak handle expires; old globals/frames/timer callbacks disappear; timer-originated request rebuilds | Native teardown sequence unconfirmed |
| Persistence | Declared Blizzard table survives real addon re-registration; account/character scalars and larger local tables survive; stale WTF does not win or change | External import cap remains intact |
| Startup/output owners | Real cached Blizzard startup loads twice; original EditMode consumer retains the non-default file-backed layout; dump, screenshot preparation and lua-errors observe fresh environment | Native cache-reread timing/order inferred; no full-addon acceptance claim |
| Preservation | Existing yielded startup/texture tests pass; modeled level, zone, party count and font/texture allocations survive | No native session-parity claim |

Both GREEN runtimes use child-only XDG directories with copied current CVars; original CVar hash/stat remain unchanged. `cargo fmt --check` passes. Full-default retail `cargo check -j1` passes with zero warnings at `f5f124f93` (same Rust as `79f52bb3f`), including `wow-sim`, `wow-cli`, library and auxiliary binaries. Default features: `sound`, `gui`, `casc`, `client-retail`. Private proof: `final-check-proof.json`.

### Bounded Forever factory proof — 2026-10-19

Seven characterization cases pass before the cache at `534888bc0` and after it at `c4dfdea66`, zero ignored. They exercise real Lua calls and XML templates, not compile counts: hook order/self/arguments/results, per-frame captures, error boundaries, direct/indirect attribute dispatch, caller-environment isolation, observable callback taint and fresh-VM retirement through ReloadUI. Cached prototype ownership is additionally source-inspected: anchors exist only in the active VM registry; no process-global Lua/prototype handle is introduced.

The four factory Lua source byte strings match `84dac6715` exactly; native chunk names and invocation policies are unchanged. `cargo fmt --check` and zero-warning Forever (`--no-default-features --features sound,gui,casc,client-wowforever`) and default Retail `cargo check -j1` pass on `c4dfdea66`. Current CVars are copied only into child XDG directories; original metadata/hash remain unchanged. Evidence: private `handoff/reload-perf/{final-pipeline-proof.json,factory-lua-integrity.json}`. Retail has compilation proof here, not a new Retail behavioral run.

Quiet-window paired untraced timing and the unchanged full Ellesmere acceptance remain separate pending proof; the existing a14 failure must not be relabeled PASS. Startup profiling lacks0–8.8s, including the initial Blizzard/XML load0.283–5.628s.

## Out of scope

- Ellesmere runner or addon changes: the observed failure is simulator lifecycle state.
- Restarting the process, IPC server or modeled game session: only the UI/Lua environment reloads.
- Unconfirmed target/focus/native session-preservation claims: retain current model state without asserting native equivalence.
