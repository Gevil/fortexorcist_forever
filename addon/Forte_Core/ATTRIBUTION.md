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

The ForteXorcist-for-WoW-Forever Lua code is an independent reimplementation, not a port of the
2012 sources; only the textures above (all unmodified) are shared with it.

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
