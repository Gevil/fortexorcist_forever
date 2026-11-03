# Third-party assets in Forte_Core

## Textures — from ForteXorcist (GPL-3.0)
ForteXorcist © Xus (Xussie of Kazzak EU), v1.980.8 (2012), licensed under **GPL-3.0**
(full text: `gpl-3.0.txt` next to this file). Vendored unmodified from the owner's release zip:

- `Textures/Aluminium.tga` — timeline bar fill
- `Textures/Background.blp` — bar backdrop center
- `Textures/Border.blp` — bar backdrop border
- `Textures/Spark2.blp` — spark / glow / pulse
- `Textures/Spark.blp`, `Textures/CastSpark.blp` — Spell Timer bar spark, tick marks, cast slice
- `Textures/ST.blp` — Spell Timer icon base
- `Textures/SS1-3.blp`, `HS1-3.blp`, `SH1-2.blp`, `SU1-2.blp`, `SW1-2.blp` — Warlock module art
  (Soulstone, Healthstone, Shard, Summon, Shard Warn)
- `Textures/ForteXorcist.blp`, `XusLogo.blp`, `CheckButton.blp` — branding / option widgets
- Bar textures offered by the original's Bar Texture option: `Bantobar.tga`, `Charcoal.tga`,
  `Flat.tga`, `Frost.tga`, `Glaze.tga`, `Healbot.tga`, `LiteStep.tga`, `Minimalist.tga`,
  `Otravi.tga`, `Perl.tga`, `Rocks.tga`, `Runes.tga`, `SWSDefault.tga`, `Smooth.tga`,
  `Smudge.tga`, `Striped.tga`, `Xeon.tga`, `Xus.tga`

## Sound — from ForteXorcist (GPL-3.0)

Vendored unmodified from the same owner's release (same licence, full text above):

- `Sounds/SoulstoneExpire.mp3` — the original's `SoulstoneFadeSound`
  (Forte_Soulstone.lua:677 default path `Interface\\AddOns\\Forte_Core\\Sounds\\SoulstoneExpire.mp3`),
  the soulstone-window-expiry bell played by `Forte_Messages/Core/Sounds.lua`. Vendored 2026-11-03.

The ForteXorcist-for-WoW-Forever Lua code is an independent reimplementation, not a port of the
2012 sources; only the textures and the sound above (all unmodified) are shared with it.

## Font — URW Gothic Book (AGPL-3.0 with font exception)
(URW)++ Design & Development, from the `urw-base35-fonts` set as packaged by Fedora
(`urw-base35-gothic-fonts`). License: GNU AGPL v3 (`Fonts/URW-COPYING.txt`) with the font
exception in `Fonts/URW-LICENSE.txt`.

- `Fonts/URWGothic-Book.otf` — **unmodified original** (the corresponding source)
- `Fonts/URWGothic-Book.ttf` — **modified version**: converted 2026-11-01 from the `.otf` above,
  CFF cubic outlines → TrueType quadratic outlines (fontTools `cu2qu`, max error 1.0 unit). No glyph,
  metric, naming or coverage changes. Distributed under the same license.

The original ForteXorcist bundled Monotype's Century Gothic (`GOTHIC.TTF`). That font is proprietary
("All Rights Reserved") and is **not** redistributed here; URW Gothic is the libre lookalike.

## Hunter swing v2 laws — adapted from WeaponSwingTimer SixxFix (GPL-3.0)

The Forte_Hunter swing v2 cycle (two-phase reload/aim model with aim length
`0.5 x speed / baseSpeed` and the floor clamp, the `UNIT_SPELLCAST_*` shot machine
with the `FAILED_QUIET` 0.5 s retry window and GUID-seal matching, the event-proven
white "projectile left" phase stamped by `UNIT_SPELLCAST_SUCCEEDED`, the
movement-cancel law with the sustained-speed pulse, the Feign Death
movement-rearm, the Aimed/Multi-Shot cast interlock, the base-speed learning from
a clean no-haste pair, and the readiness-gate shape) adapts the behaviour of
**WeaponSwingTimer SixxFix** © WatchYourSixx (original WST by LeftHandedGlove),
Forever v1.60.2, licensed **GPL-3.0** — the same licence as this project.
Adapted 2026-11-02 from `/tmp/wst/src/WeaponSwingTimer/`
(`WeaponSwingTimer_Hunter.lua:352-660, 913-1075`, `WeaponSwingTimer_Castbar.lua:210-330`);
the adapted blocks in `Forte_Hunter/Core/Tools.lua` and `Forte_Hunter/UI/Swing.lua`
carry per-block source comments. No WST artwork, textures, fonts, skin XML,
configuration system, profile system, melee code, target code or frame scripts are
used: all UI here is the ForteXorcist skin, all code is rewritten against the
Forever 12.x catalog APIs (`C_Spell`, `C_SpellBook`, the modern event set); the
classic-API symbols WST calls (`GetInventoryItemID`, `SPEED`,
`hooksecurefunc`, `COMBAT_LOG_EVENT_UNFILTERED`) are not used anywhere.
