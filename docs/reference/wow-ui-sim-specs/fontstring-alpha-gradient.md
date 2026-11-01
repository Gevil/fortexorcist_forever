# FontString alpha gradient (T4, approved simulator policy)

Integration checkpoint (2026-10-16): user approved the scalar/taper/completion policy; Retail/Wrath API and renderer RED → GREEN recorded in [bounded proof](../baselines/approved-batch-2026-10-16.md). No native-parity claim.

FontString text reveal and its completion boolean. Producer: `src/lua_api/frame/methods/misc/alpha_gradient.rs`; rendering: `src/render/glyph.rs`. The contract was approved and its tested API/render boundaries reached behavioral RED before producer integration; it does not establish native parity. See [rendering](../rendering-pipeline.md).

## What it must do

- [ ] Interpret start/length in Unicode scalar positions after stripping WoW markup. Spaces and explicit line breaks count; automatic wrapping adds no positions. A shaped cluster uses its first scalar's alpha.
- [ ] Multiply ordinary text, shadow and outline alpha by `clamp((start + length - position) / length, 0, 1)`. For zero length use a hard boundary: positions strictly below start visible, others hidden. Preserve geometry, RGB and layout/cache behavior; colored segments continue the same position sequence.
- [ ] Replace slot-zero gradient on each setter call, retaining current storage/getter/clear behavior. Completion retains the gradient; clearing restores ordinary text rendering.
- [ ] Return true while start is less than stripped scalar count, false at/after that count (including empty text). Length controls the taper, not the completion threshold. Completion ignores viewport clipping, font size and wrapping.
- [x] Drive the original cached Wrath callback through gradual progress and the consumer's 1024 instant-progress convention; clear fading, reveal its dependent frame and enable accept on false. Characterize the cached Mists Classic callback explicitly, without claiming automatic profile selection. Immediate dependent reveal branch only; scheduled dependent-frame fade is separate.

## How it works

- [Rendering pipeline](../rendering-pipeline.md)
- [Widget system](../widget-system.md)

## Implementation inventory

- `src/widget/frame_types.rs`: stored gradient and scalar alpha calculation.
- `src/lua_api/frame/methods/misc/alpha_gradient.rs`: setter state and completion result.
- `src/render/glyph.rs`, `src/render/glyph/text_emit.rs`: shaped cluster positions and alpha paint.
- `src/iced_app/quad_builders.rs`: FontString paint and colored-segment offsets.

## Tests asserting this spec

- `tests/fontstring_alpha_gradient.rs`: scalar/markup completion, replacement, clearing and empty text.
- `src/iced_app/quad_builders_alpha_gradient_tests.rs`: concrete emitted glyph alpha and unchanged geometry.
- `tests/wrath_quest_alpha_gradient.rs`: two original cached Wrath initializer/callback paths; pending progress, exact scalar completion, dependent alpha, Accept state, retained gradient, idle completed callback and original `WriteQuest` request/kit 3093.
- `tests/mists_quest_alpha_gradient_characterization.rs`: two explicitly selected cached Mists callback paths with original hide/show helpers and two dependent frames. Loads the complete hash-pinned Wrath `SoundKitConstants.lua` from the Mists cache; no sound stub.
- `tests/common/quest_alpha_gradient.rs` and `tests/fixtures/quest_alpha_gradient/{wrath,mists}.lua`: shared hash-checked complete-source loader, real widgets and explicit error capture.

Public consumer citations (cache root `~/.cache/wow-ui-sim/blizzard-ui`): Wrath `FrameXML/QuestInfo.lua:3-16,479-492`, constants `FrameXML/QuestFrame.lua:4-6`; Mists `AddOns/Blizzard_UIPanels_Game/Classic/QuestFrame.lua:4-6,799-814`, dependent helpers `AddOns/Blizzard_UIPanels_Game/Wrath/QuestInfo.lua:919-945`. Wrath's cache places the consumer beside AddOns, not inside it; tests use that literal location, without an alternate-source fallback.

## Known gaps (current cycle)

- [x] User separately approved units/taper/completion; API and three renderer cases per Retail/Wrath profile reached RED then GREEN.
- [x] Original Wrath callbacks: 2/2 passed with `--no-default-features --features sound,gui,casc,client-wrath`, integration selector `wrath_quest_alpha_gradient::`. Legacy `PlaySound("WriteQuest")` no longer blocks this proof.
- [x] Separate Mists characterization: 2/2 passed with `--no-default-features --features sound,gui,casc,client-mists`, integration selector `mists_quest_alpha_gradient_characterization::`. Initial run failed setup because the harness omitted vendor sound constants; loading that original file fixed setup. Neither run establishes gradient RED → GREEN: the producer was already merged; these are missing-proof coverage.
- [ ] Fixed-setting gradual scheduled dependent fades, automatic Mists profile selection, native and broader acceptance remain unexecuted. Startup observations are separate and Wrath remains a failing compatibility inventory.

Both gradual cases use 35 markup-stripped scalars, including Unicode, spaces and newlines. They change the fading setting from `"0"` to `"1"` only before the completing tick, selecting immediate dependent reveal without replacing callbacks or scheduling helpers. Wrath executes the original initializer's 1024 branch; Mists supplies post-OnShow progress 1024 and does not execute OnShow. Completion clears `fading`, not the stored gradient, and reveals already-shown alpha-zero dependents without claiming `Show()` behavior.

Proof receipts: `/home/osso/.local/state/wow-ui-sim/handoff/t4-wrath-callback-tests/` (`wrath-tests.log`, `mists-tests-corrected.log`, `proof-ledger.json`). Wrath passed at `5671220c1`; Mists passed at `f7674e2e0` after the harness-only prerequisite correction. No simulator or vendor behavior changes.

## Combined-tree callback proof

After rebasing onto master `f452d5a4b`, all five bounded gates passed on revision `8debcce7c375ea24deaf795bbafe4d5506b54b4b`, tree `fadd70738ec003f5ba3b092149101ee6d99b7eb5`. Wrath selected both named callback cases: **2 passed, 0 failed, 8241 filtered**; Mists selected both named characterization cases: **2 passed, 0 failed, 8354 filtered**. No zero-selection run or harness invalidation occurred.

Both `cargo check --locked -j1 --no-default-features --features sound,gui,casc,client-<profile>` gates (Wrath and Mists, default check targets) and workspace `cargo fmt --all -- --check` exited 0. The existing `UnitRole::{Tank,Healer,Damage}` dead-code warning appeared in both tests and checks, without suppression. This proves the rebased callback initialization/compilation boundary, not the excluded native, scheduler, startup or broader acceptance boundaries.

Complete commands, output, toolchain and receipts: `/home/osso/.local/state/wow-ui-sim/handoff/t4-combined-rerun/`; appended records: `/home/osso/.local/state/wow-ui-sim/handoff/t4-wrath-callback-tests/proof-ledger.json`. Each Cargo gate ran asynchronously in a user systemd unit with `MemoryMax=9G`, slot-0 and admission `ADD`. Tests used byte-exact isolated copies of current persisted CVars; original stat/hash stayed unchanged before/after every gate. This documentation-only follow-up does not invalidate that proof.

## Out of scope

Native thresholds, malformed/nonfinite input redesign, ScrollBox edge fades, vendor edits, quest acceptance effects, automatic Mists branch-selection proof and other-profile acceptance.
