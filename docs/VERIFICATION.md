# VERIFICATION — launch-day probe rows

Row ledger for the `/fx probe` battery (`addon/Forte_Core/Core/Probe.lua`):
one row per probe line, what it decides, where the question comes from, and
the two status columns — `sim` = exercised by the wow-ui-sim suite
(`run-tests Forte_Core`, `addon/Forte_Core/tests/test_probe.lua`; the sim
cannot produce secrets, so SECRET-shape answers are client-only) and
`client` = the launch-day 2026-11-04 answer, read per
`docs/launch-day.md` F-check.

**Status at 1.0.0 (2026-11-10).** The game launched on 2026-11-04. The only live client session
recorded in this repository is the Hunter session of 2026-11-06 (build 1.60.1.70790), whose fixes are in
`CHANGELOG.md`. The probe *answers* (the `client` column below) were not recorded here, so every
`PENDING` row stays `PENDING`: nothing in this ledger claims a live answer that is not written down.
To close a row, run the `/fx probe` step it names in `docs/launch-day.md`, paste the block, and
change the cell to the measured result with the date and build.

> Scope note: wave I-2 slice I2c (2026-11-03) created this file —
> `docs/VERIFICATION.md` is cited from `PLAN.md` §9/§11.2 rows but had no
> file in the public repo (public-scrub casualty at most, pre-launch rows
> were kept in `docs/launch-day.md`). The wave I-1 pre-launch probes (the
> `#`-suffix rank probe, the SVFix write→reload→read, Gap-11/12) live in
> `docs/launch-day.md` and `docs/research/`; the manager consolidates them
> into this ledger.

## Probe rows

| Row | Decides | Source question | sim | client (2026-11-04) |
|---|---|---|---|---|
| `SEC:` (+ `sabs`, `uibsP`, `uibsT`, `utbs`, `threatFn`) | the secret-mode surface; the widened gate set = per-spell aura / per-unit identity / threat values, the set addons shipping for this product gate on | upstream-addons-2026-11-03 §1, §9.4; catalog `@SecretPredicateAPIDocumentation.lua:138/:304/:414` | VERIFIED 2026-11-03 (`test_probe.lua`; fields present, no raise in the sim; the sim ships no `C_Secrets` so values are the `absent` shape) | PENDING (launch run: F19/F20 pair) |
| `NAME:` | raw `UnitName`/`UnitFullName`/`UnitNameUnmodified("player")` both returns + `GetRealmName()`; in-combat secrecy of the identity reads feeding `CharacterKey`/comms | upstream-api-2026-11-03 Open questions 1 + 3, §2 identity law; catalog `@UnitDocumentation.lua:2488/:1223/:2522` (`SecretWhenUnit[Name]IdentityRestricted`) | VERIFIED 2026-11-03 (shape + the sentinel seam stores `SECRET`, never the value; `raise=` recording) | PENDING — F19 |
| `EVENTS:` | `C_EventUtils.IsEventValid` over all 42 event literals the addons register + the threat-event trio `UNIT_THREAT` (classic, catalog-absent) / `UNIT_THREAT_LIST_UPDATE` / `UNIT_THREAT_SITUATION_UPDATE` (the shipped capability probe; registration of an unknown event raises on the live client) | upstream-addons-2026-11-03 §2, ranked 5; catalog `@EventUtilsDocumentation.lua:25`, `@UnitDocumentation.lua:4888/:4899`; §10.3 (threat surface) | VERIFIED 2026-11-03 (`n=42 ok=42 bad=- raise=-` on the sim; api_lint PASS = the static half) | PENDING — F20 |
| `SV:` | SavedVariables round-trip at value level: every run writes a stamp, the next login latches what the store held — the 70707 restore answer the epoch counter only implies | upstream-addons-2026-11-03 §5, §9.1, §10.1 (SVFix's claim is 2026-09-25) | VERIFIED 2026-11-03 (write→next-run `db=` echo→`login=` latch through `OnEnable`, in-suite) | PENDING — F21 (+ launch-day steps 8/9) |
| `HS:` | healthstone counts + the stones' item-cooldown readability — the read Blizzard's own Cooldown Manager is documented as NOT getting | forever-dev-notes-2026-11-03 §2 (Cooldown-Manager known issues) | VERIFIED 2026-11-03 (generated-warlock-data shape: every stone reports `cnt`/`cd`, no raise; `no-warlock-data` off-class) | PENDING — F22 (warlock alt, F10 session) |
| `PET:` | pet spell-cooldown readability via the `C_ActionBar` pet-bar lookups (pet bar 1, first slot; ids resolved, not typed) | forever-dev-notes-2026-11-03 §2 ("cannot track ... pet cooldowns") | VERIFIED 2026-11-03 (gate shape: `pet=boolean:false` on the sim, no raise) | PENDING — F23 (Hunter, pet out, ooc+combat pair) |
| `ENCH:` | `C_Item.GetWeaponEnchantInfo` records (hasEnchant/timeLeft-ms/enchantID/charges) readable ooc; the combat pair decides the Enchants bar | forever-dev-notes-2026-11-03 §2 ("item enhancements (Windfury, rogue poisons)"); catalog `@ItemDocumentation.lua:1140` | VERIFIED 2026-11-03 (three slots report, no raise, un-enchant slots `n0`/nil on the sim) | PENDING — F24 (temp enchant + ooc/combat pair) |
| `BSW:` | presence + shown-state of Blizzard's OWN swing-timer frames (`SwingTimerManagerFrame`, Main/Off/Ranged) — the overlap input for the Hunter swing bar | forever-dev-notes-2026-11-03 §2 ("the Off-Hand Swing Timer" fix) | VERIFIED 2026-11-03 (all four report presence, no raise) | PENDING — F25 (`showSwingTimer` on, Auto Shot) |

Reading guide: `docs/launch-day.md` "Reading the output" rows (`NAME`,
`EVENTS`, `SV`, `HS`, `PET`, `ENCH`, `BSW`) and F-checks F19–F25.
