# ForteXorcist for WoW Forever

A rebuild of the classic **ForteXorcist** addon (cooldown & spell timers, alerts, class tools) for
**World of Warcraft: Forever**, written for the Forever client's modern API and its combat
restrictions. All classes and specs are the goal; Hunter comes first.

> Status: early development — not playable yet. See [PLAN.md](PLAN.md).

## Layout
```
addon/      the addons the game loads (Forte_Core, Forte_Cooldown, Forte_<Class>)
tools/      spell-data generator + per-class spell lists
docs/       research notes behind design decisions
```

## Spell data
Generated, never hand-typed, from [mythicsim-forever-engine](https://github.com/sage3648/mythicsim-forever-engine)
data (checked out next to this repo):
```sh
python3 tools/gen_spell_data.py hunter
```

## Install (once it's usable)
Copy or symlink each folder in `addon/` into `World of Warcraft/_forever_/Interface/AddOns/`.

## Credits
- ForteXorcist — original addon by Xus.
- [CooldownMaster](https://github.com/wheelbarrel00/CooldownMaster) (MIT) — reference for the
  Forever-safe cooldown engine design.
- [mythicsim-forever-engine](https://github.com/sage3648/mythicsim-forever-engine) (MIT) and
  [wowsims/forever](https://github.com/wowsims/forever) (MIT) — spell data.
- [Thunderz96/forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) — measured client findings.
