#!/usr/bin/env python3
"""Unit tests for tools/diff_live_items.py:  python3 scripts/test_diff_live_items.py

A synthetic mini db.json plus two tiny generated-Lua files exercise every report category
(a..g), the -1 "no cooldown" normalisation, the 60 s consumable floor, the layer's known
overrides, the CLI (text and --json) and its determinism. No network, no real data files."""
import contextlib
import io
import json
import pathlib
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "tools"))
import diff_live_items as D  # noqa: E402

ITEMS_LUA = '''-- header
ForteXorcist.Data.Items = {
  onUse = {
    { name = "Kept Trinket", itemId = 1, source = "item", cooldownMs = 300000, buffId = 11, buffName = "Kept (11)", durationMs = 10000, trackable = "cooldown" },
    { name = "Slow Trinket", itemId = 2, source = "item", cooldownMs = 90000, buffId = 12, buffName = "Slow (12)", durationMs = 15000, trackable = "cooldown" },
    { name = "Stripped Trinket", itemId = 3, source = "item", cooldownMs = 60000, buffId = 13, trackable = "cooldown" },
    { name = "Vanished Trinket", itemId = 4, source = "item", cooldownMs = 60000, buffId = 14, trackable = "cooldown" },
    { name = "Override Trinket", itemId = 5, source = "item", cooldownMs = 480000, buffId = 15, durationMs = 10000, trackable = "cooldown" },
    { name = "Name \\"Quoted\\" Trinket", itemId = 6, source = "item", cooldownMs = 60000, classAllowlist = { "ClassMage", "ClassPriest" }, trackable = "cooldown" },
  },
  consumables = {
    { name = "Old Potion", itemId = 100, source = "consumable", categoryCooldownMs = 120000, categoryId = 4, trackable = "cooldown" },
    { name = "Changed Potion", itemId = 101, source = "consumable", categoryCooldownMs = 120000, categoryId = 4, trackable = "cooldown" },
    { name = "Gone Potion", itemId = 102, source = "consumable", categoryCooldownMs = 60000, categoryId = 24, trackable = "cooldown" },
  },
  enchantProcs = {
    { name = "Enchant", itemId = 900, source = "enchant", icdMs = 1000, trackable = "buff-window" },
  },
}
'''

PROCS_LUA = '''ForteXorcist.Data.ItemProcs = {
  procs = {
    { name = "Steady Proc", itemId = 20, source = "item", buffId = 21, buffName = "Steady (21)", icdMs = 30000, trackable = "buff-window" },
    { name = "Icd Drift", itemId = 21, source = "item", buffId = 22, buffName = "Drift (22)", icdMs = 15000, trackable = "buff-window" },
    { name = "Debounce Drift", itemId = 22, source = "item", buffId = 23, buffName = "Deb (23)", icdMs = 100, trackable = "buff-window" },
    { name = "Dead Proc", itemId = 23, source = "item", buffId = 24, trackable = "buff-window" },
    { name = "Shared Name", itemId = 50, source = "item", buffId = 25, trackable = "buff-window" },
  },
}
'''


def eff(buff, on_use=None, proc=None, dur=None):
    e = {"buffId": buff, "buffName": f"B ({buff})"}
    if dur is not None:
        e["effectDurationMs"] = dur
    if on_use is not None:
        e["onUse"] = on_use
    if proc is not None:
        e["proc"] = proc
    return e


DB = {
    "items": [
        {"id": 1, "name": "Kept Trinket", "type": 12, "itemEffects": [
            {"buffId": 11, "buffName": "Kept (11)", "effectDurationMs": 10000,
             "onUse": {"cooldownMs": 300000, "categoryId": 1141, "categoryCooldownMs": 20000}}]},
        {"id": 2, "name": "Slow Trinket", "type": 12, "itemEffects": [
            {"buffId": 12, "buffName": "Slow (12)", "effectDurationMs": 15000, "onUse": {"cooldownMs": 360000}}]},
        {"id": 3, "name": "Stripped Trinket", "type": 12, "itemEffects": [
            {"buffId": 13, "effectDurationMs": 8000, "onUse": {"cooldownMs": 60000, "categoryCooldownMs": -1}}]},
        {"id": 4, "name": "Vanished Trinket", "type": 12},  # item present, effect gone
        {"id": 5, "name": "Override Trinket", "type": 12, "itemEffects": [
            {"buffId": 15, "effectDurationMs": 8000, "onUse": {"cooldownMs": 480000}}]},
        {"id": 6, "name": 'Name "Quoted" Trinket', "type": 12, "itemEffects": [
            {"buffId": 16, "onUse": {"cooldownMs": 60000}}]},
        # missing on-use item: trinket, phase 1, first seen 2026-11-10 (the epoch below)
        {"id": 7, "name": "New Trinket", "type": 12, "phase": 1, "quality": 3, "itemEffects": [
            {"buffId": 17, "buffName": "New (17)", "effectDurationMs": 15000,
             "onUse": {"cooldownMs": 900000, "categoryId": 94, "categoryCooldownMs": 15000}}]},
        # a category-only on-use is out of scope (the generator emits no cooldown for it)
        {"id": 8, "name": "Lockout Only", "type": 12, "itemEffects": [
            {"buffId": 18, "onUse": {"categoryId": 1, "categoryCooldownMs": 30000}}]},
        {"id": 20, "name": "Steady Proc", "itemEffects": [
            {"buffId": 21, "buffName": "Steady (21)", "proc": {"icdMs": 30000}}]},
        {"id": 21, "name": "Icd Drift", "itemEffects": [
            {"buffId": 22, "buffName": "Drift (22)", "proc": {"icdMs": 20000}}]},
        {"id": 22, "name": "Debounce Drift", "itemEffects": [
            {"buffId": 23, "buffName": "Deb (23)", "proc": {"icdMs": 200}}]},
        {"id": 23, "name": "Dead Proc", "itemEffects": [{"buffId": 24}]},  # passive now
        {"id": 30, "name": "New Proc", "type": 13, "weaponType": 9, "handType": 4, "phase": 2,
         "sources": [{"drop": {"zoneId": 1}}], "classAllowlist": [8], "itemEffects": [
             {"buffId": 31, "buffName": "Newproc (31)", "effectDurationMs": 9000, "proc": {"ppm": 2.0}}]},
        {"id": 51, "name": "Shared Name", "itemEffects": [
            {"buffId": 25, "buffName": "Shared (25)", "proc": {}}]},
        {"id": 60, "name": "Passive Aura", "itemEffects": [{"buffId": 61}]},
    ],
    "consumables": [
        {"id": 100, "name": "Old Potion", "itemEffects": [
            {"buffId": 1, "onUse": {"categoryId": 4, "categoryCooldownMs": 120000}}]},
        {"id": 101, "name": "Changed Potion", "itemEffects": [
            {"buffId": 2, "onUse": {"categoryId": 4, "categoryCooldownMs": 300000}}]},
        {"id": 103, "name": "New Stone", "itemEffects": [
            {"buffId": 3, "onUse": {"categoryId": 1153, "categoryCooldownMs": 120000}}]},
        {"id": 104, "name": "Item Cd Only", "itemEffects": [{"buffId": 4, "onUse": {"cooldownMs": 900000}}]},
        {"id": 105, "name": "Elixir Lock", "itemEffects": [
            {"buffId": 5, "onUse": {"cooldownMs": -1, "categoryId": 2593, "categoryCooldownMs": 3000}}]},
        {"id": 106, "name": "Plain Food", "itemEffects": [
            {"buffId": 6, "onUse": {"cooldownMs": -1, "categoryId": 11, "categoryCooldownMs": -1}}]},
    ],
}
FIRST_SEEN = {7: 1794268800, 30: 1668901636}  # 2026-11-10, the 2022-11-19 placeholder


def ours_from(td):
    items, procs = pathlib.Path(td, "Items.lua"), pathlib.Path(td, "Procs.lua")
    with open(items, "w", encoding="utf-8") as f:
        f.write(ITEMS_LUA)
    with open(procs, "w", encoding="utf-8") as f:
        f.write(PROCS_LUA)
    return items, procs


class Parse(unittest.TestCase):
    def test_sections_fields_and_escapes(self):
        with tempfile.TemporaryDirectory() as td:
            items, procs = ours_from(td)
            ours = D.load_ours(items, procs)
        self.assertEqual([len(ours[k]) for k in ("onUse", "consumables", "enchantProcs", "procs")],
                         [6, 3, 1, 5])
        row = ours["onUse"][5]
        self.assertEqual(row["name"], 'Name "Quoted" Trinket')
        self.assertEqual(row["classAllowlist"], ["ClassMage", "ClassPriest"])
        self.assertEqual(ours["onUse"][0]["cooldownMs"], 300000)
        self.assertEqual(ours["procs"][0]["icdMs"], 30000)

    def test_slot_type_composition_matches_generator_order(self):
        self.assertEqual(D.slot_type({"type": 13, "handType": 4, "weaponType": 9}),
                         "ItemTypeWeapon / HandTypeTwoHand / WeaponTypeSword")
        self.assertEqual(D.slot_type({"type": 14, "rangedWeaponType": 3}),
                         "ItemTypeRanged / RangedWeaponTypeGun")
        self.assertIsNone(D.slot_type({"name": "x"}))


class Report(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as td:
            ours = D.load_ours(*ours_from(td))
        layer = {"onUseOverride": {"5": {"name": "Override Trinket", "durationMs": 10000, "was": 8000}}}
        cls.rep = D.compute(DB, ours, FIRST_SEEN, {7: True}, layer)
        cls.rows = cls.rep["rows"]

    def test_a_missing_on_use_items(self):
        ids = [r["itemId"] for r in self.rows["a"]]
        self.assertEqual(ids, [7])  # the category-only lockout (id 8) is out of scope
        r = self.rows["a"][0]
        self.assertEqual((r["cooldownMs"], r["durationMs"], r["categoryCooldownMs"]), (900000, 15000, 15000))
        self.assertEqual((r["firstSeen"], r["phase"], r["liveJsonl"]), ("2026-11-10", 1, "effects"))

    def test_b_mismatches_normalise_minus_one_and_mark_known_overrides(self):
        got = {(r["itemId"], r["field"]): r for r in self.rows["b"]}
        self.assertEqual(got[(2, "cooldownMs")]["ours"], 90000)
        self.assertEqual(got[(2, "cooldownMs")]["live"], 360000)
        self.assertEqual(got[(3, "durationMs")]["ours"], None)   # ours states none, live 8000
        self.assertEqual(got[(3, "durationMs")]["live"], 8000)
        self.assertEqual(got[(101, "categoryCooldownMs")]["live"], 300000)
        self.assertEqual(got[(5, "durationMs")]["known"], "onUseOverride")
        self.assertNotIn("known", got[(2, "cooldownMs")])
        # Kept Trinket: live category 20000 is not emitted for items, so it is not a mismatch
        self.assertFalse([k for k in got if k[0] == 1])
        # the quoted-name row: live has no buffName where ours has none either, no noise
        self.assertFalse([k for k in got if k[0] == 6 and k[1] != "buffId"])

    def test_c_missing_procs_include_effect_and_context(self):
        ids = [r["itemId"] for r in self.rows["c"]]
        self.assertEqual(ids, [30, 51])
        r = self.rows["c"][0]
        self.assertEqual((r["ppm"], r["durationMs"], r["sources"], r["classAllowlist"], r["phase"]),
                         (2.0, 9000, ["drop"], [8], 2))
        self.assertEqual(r["slotType"], "ItemTypeWeapon / HandTypeTwoHand / WeaponTypeSword")
        self.assertEqual(r["firstSeen"], "2022-11-19")
        self.assertFalse(r["partial"])

    def test_d_icd_mismatch_flags_debounces(self):
        got = {r["itemId"]: r for r in self.rows["d"]}
        self.assertEqual(sorted(got), [21, 22])
        self.assertEqual((got[21]["ours"], got[21]["live"], got[21]["debounce"]), (15000, 20000, False))
        self.assertEqual((got[22]["ours"], got[22]["live"], got[22]["debounce"]), (100, 200, True))

    def test_e_consumables_floor_and_exclusions(self):
        ids = [r["itemId"] for r in self.rows["e"]]
        # 103 (category 120 s) and 104 (item cooldown 900 s) qualify; the 3 s elixir lockout and
        # the food (-1 / -1) do not; 100/101 are already ours
        self.assertEqual(ids, [103, 104])

    def test_f_gone_rows_split_evidence_from_absence(self):
        got = {(r["itemId"], r["list"]): r for r in self.rows["f"]}
        self.assertEqual(got[(4, "onUse")]["state"], "lost its effect")
        self.assertTrue(got[(4, "onUse")]["evidence"])
        self.assertEqual(got[(23, "procs")]["state"], "changed kind: passive")
        self.assertEqual(got[(102, "consumables")]["state"], "absent from db")
        self.assertFalse(got[(102, "consumables")]["evidence"])
        self.assertNotIn((1, "onUse"), got)
        self.assertNotIn((900, "enchantProcs"), got)  # enchant rows are not item rows

    def test_g_name_collision_the_byname_index_would_hit(self):
        # "Shared Name": ours 50, the live db adds 51 -> lowest id (50) keeps the key
        g = [r for r in self.rows["g"] if r["name"] == "Shared Name"]
        self.assertEqual(len(g), 1)
        self.assertEqual((g[0]["existing"], g[0]["new"], g[0]["winner"], g[0]["flips"]),
                         ([50], [51], 50, False))

    def test_counts_match_rows(self):
        self.assertEqual(self.rep["counts"], {k: len(v) for k, v in self.rows.items()})
        self.assertEqual(self.rep["meta"]["liveOnUseEffects"], 6)  # ids 1,2,3,5,6,7 (8 is lockout-only)


class Cli(unittest.TestCase):
    def run_cli(self, *extra):
        with tempfile.TemporaryDirectory() as td:
            items, procs = ours_from(td)
            db = os.path.join(td, "db.json")
            with open(db, "w", encoding="utf-8") as f:
                json.dump(DB, f)
            with open(os.path.join(td, "item_first_seen.json"), "w", encoding="utf-8") as f:
                json.dump([{"id": k, "firstSeen": v} for k, v in FIRST_SEEN.items()], f)
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                rc = D.main(["--db", db, "--items-lua", str(items), "--procs-lua", str(procs),
                             "--live-jsonl", os.path.join(td, "none.jsonl"),
                             "--layer", os.path.join(td, "none.json"), *extra])
        return rc, buf.getvalue()

    def test_json_is_deterministic_and_complete(self):
        rc1, out1 = self.run_cli("--json")
        rc2, out2 = self.run_cli("--json")
        self.assertEqual((rc1, rc2), (0, 0))
        self.assertEqual(out1, out2)
        rep = json.loads(out1)
        self.assertEqual(sorted(rep["counts"]), list("abcdefg"))
        self.assertEqual(rep["counts"]["a"], 1)
        self.assertIsNone(rep["rows"]["a"][0].get("liveJsonl"))  # no jsonl given

    def test_text_tables_and_category_filter(self):
        rc, out = self.run_cli("--category", "a,d")
        self.assertEqual(rc, 0)
        self.assertIn("(a) live on-use items missing from our data: 1", out)
        self.assertIn("New Trinket", out)
        self.assertIn("(d) proc ICD mismatches", out)
        self.assertNotIn("(c) ", out)
        self.assertTrue(out.rstrip().endswith("counts: a=1 d=2"))

    def test_unreadable_db_exits_2(self):
        with self.assertRaises(SystemExit) as cm:
            with contextlib.redirect_stderr(io.StringIO()):
                D.main(["--db", "/nonexistent/db.json"])
        self.assertEqual(cm.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
