# Why ForteXorcist doesn't build on Blizzard's Cooldown Manager

Decision (2026-11-01): track cooldowns/buffs with our own engine. Keep
`ForteXorcist.Compat.HAS_BLIZZ_CDM = false` as a switch for later.

Evidence:
- **CooldownMaster** (installed, `Core/Compat.lua`, updated 2026-11-01):
  `HAS_BLIZZ_CDM = IS_RETAIL and TOC_VERSION >= 120000` — false on Forever (16001) even though
  `IS_RETAIL` is true there. `Core/Engine.lua:3450`: "Forever's cooldowns are secret in combat
  like retail's, so it falls through to the retail reader" — Forever gets its own path that
  neither uses `C_CooldownViewer` nor the Classic spellbook scan.
- **Reliability**: Thunderz96/forever-addon-kit measured every `C_CooldownViewer` category empty
  for Forever specs through build 69977; Blizzard's known-issues post called it a work in progress
  that varies by class. Later beta notes (Oct 8) claim all classes/racials/trinkets supported, but
  the maintainers above still don't trust it as a data source.
- **Model mismatch**: the CDM populates from the retail spec/talent model; Forever has no
  `GetSpecialization`, new spec IDs and Legacy trait trees.
- **Scope**: it's a fixed HUD for rotational cooldowns — no soulstones, shards, healthstones, traps,
  aspects, custom alerts. Nothing to extend for FX's class tools.
- **EllesmereUI** ships `EllesmereUICooldownManager`, described as "A CDM replacement".
