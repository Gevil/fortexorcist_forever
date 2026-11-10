# Contributing

Bug reports are the most useful contribution: see "Reporting issues" in `README.md` for what to include.

Code changes: open an issue first for anything bigger than a fix. Read `AGENTS.md` (hard technical rules)
and `PLAN.md` (what and why) before you start. The rules that most often matter:

- Forever is a Retail 12.x engine (interface 16001). `COMBAT_LOG_EVENT_UNFILTERED` is forbidden.
- Every value read from a unit, aura, cooldown, item or power API goes through
  `ForteXorcist.Compat.PlainOrNil` before it is compared or stored; a secret read never overwrites known state.
- Every addon has `X.toc` and a byte-identical `X_Camelot.toc`, `## Interface: 16001`.
- Spell and item data are generated: edit `tools/spell_lists/<class>.json` and run
  `python3 tools/gen_spell_data.py <class>`; never hand-edit `addon/*/Data/*.lua`.
- Chat to other players is opt-in and goes through `Forte_Messages`' legality gate.

Checks before a pull request: `python3 scripts/gate.py` (all simulator suites, toc twins, syntax, API lint,
data determinism). It needs the sibling `wow-ui-sim` checkout described in `AGENTS.md`; without it, run
`python3 scripts/api_lint.py` and `python3 scripts/test_release_notes.py` and say so in the pull request.

Changes by contributors are licensed under GPL-3.0, like the rest of the project.
