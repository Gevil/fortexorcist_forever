# Texture metatable access

## Contract

- Retail 12.1.5+ and Forever expose `GetTextureMetatable()` before addon loading.
- It returns the actual per-type metatable obtained from a Texture created through the existing frame factory, not a fabricated method table.
- Like the existing FontString helper, an optional Texture argument selects that object's metatable.
- Repeated calls and calls with different ordinary textures return the same per-type metatable. Its `__index` methods operate on real Texture objects.
- Earlier Retail epochs and other profiles retain their prior global surface.

## Consumer and proof

Forever 1.60.1.69913 `Blizzard_UnitFrame/Mainline/UnitFrameUtil.lua:67` copies `GetTextureMetatable().__index` and uses its `IsObjectType` method. `tests/wowforever_texture_metatable.rs` loads that unmodified source and exercises metatable identity, type queries, and texture mutation through the real methods.

Retail 12.1.5.70448 moves this consumer to `Blizzard_UnitFrame/Shared/UnitFrameUtil.lua:119`. Its missing producer aborts the original file before role/PvP helpers are defined. `tests/retail_70448_startup_roots.rs` loads that complete original file and checks copied real-method dispatch; the initial test fails at line 119.

This preserves simulator metatable-helper behavior; optional-argument validation and native metatable mutation/security semantics are not established by this test.
