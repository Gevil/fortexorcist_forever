#!/usr/bin/env python3
"""Full verification gate for ForteXorcist (run from anywhere).

Runs, in order:
  1. wow-ui-sim run-tests for every addon that has a tests/ directory
  2. wow-ui-sim lua-errors (load check), counting only Forte_* errors
  3. X.toc == X_Camelot.toc byte-identical for every addon with a toc
  4. luajit loadfile on every addon Lua file (syntax)
  5. generator determinism: re-run spell + item generators, compare bytes

Exit code 0 only if everything passes. Usage:
  scripts/gate.py            # everything
  scripts/gate.py --fast     # skip generators
"""
import filecmp, glob, hashlib, json, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDONS = os.path.join(ROOT, "addon")
# wow-ui-sim checkout: $WOW_UI_SIM (path to run.sh) or a sibling checkout next to this repo.
SIM = os.environ.get("WOW_UI_SIM") or os.path.join(os.path.dirname(ROOT), "wow-ui-sim", "run.sh")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
FORTE_ERR = re.compile(r"(Forte_\w+/[\w/\.]+:\d+)")

failures = []


def sim(*args):
    # --no-saved-vars: every gate run starts from a fresh SavedVariables state.
    # Without it the sim reloads whatever the last run wrote (a demo capture
    # that switched the splash on made test_splash's "OFF by default" fail at
    # a clean HEAD — wave I, 2026-11-03).
    p = subprocess.run([SIM, "wow-sim", "--allow-ui-version-mismatch", "--no-saved-vars",
                        "--addons-path", ADDONS, *args],
                       cwd="/tmp", capture_output=True, text=True, errors="replace")
    return p.returncode, ANSI.sub("", p.stdout + p.stderr)


# With every class add-on `## LoadOnDemand: 1`, a session parses only the
# profile class's data + modules, so a suite that leans on one class's data has
# to run as that class -- Forte_Core excepted on purpose: its `test_loader.lua`
# asserts "only the player's class add-on is loaded", so it must run as the
# default (Paladin) class, the one with data and NO modules (PLAN §11).
#
# The suites whose fixtures are another class's spells (Forte_Cooldown,
# Forte_Timer, Forte_Options) and the class suites themselves declare that by
# loading the add-on they audit (`test_00_class_data.lua`, and the loader call
# at the top of each class suite's first file): `run-tests` does NOT run a
# load-on-demand add-on's own files, so without it the suite audits nil data.
# Every suite runs under the sim's default class exactly as before the split
# -- `--class` would move `FX._playerClass`, which the class-gate tests assert
# is NOT the class they audit.
def run_tests():
    for d in sorted(glob.glob(os.path.join(ADDONS, "Forte_*", "tests"))):
        addon = os.path.basename(os.path.dirname(d))
        rc, out = sim("run-tests", addon)
        counts = re.findall(r"(\d+) tests?, (\d+) passed, (\d+) failed", out)
        fails = [l.strip()[:140] for l in out.splitlines() if "\u2717" in l]
        errs = sorted(set(FORTE_ERR.findall(out)))
        ok = rc == 0 and counts and counts[-1][2] == "0" and not fails and not errs
        print(f"[tests] {addon}: "
              f"{counts[-1] if counts else 'no summary'} rc={rc} {'OK' if ok else 'FAIL'}")
        for f in fails: print("        ", f)
        for e in errs: print("         error at", e)
        if not ok: failures.append(f"tests {addon}")


# With `## LoadOnDemand: 1` on every class add-on, a session carries the
# always-loaded data sets + modules plus EXACTLY the profile class's. Forte_Core
# is the load probe's own target, so the runs below are plain startup probes
# (no tests). The sim's headless default class is Paladin (docs/reference/
# wow-ui-sim-specs/cli-class-spec.md), which has data and no modules -- the
# shape that proves the gate keeps the other classes out.
ALWAYS_DATA = {"Items"}
# TestMode: wave I-3c. Log: code-review-10 M3/M4 -- the /fx log module is a
# Forte_Core module (registered through the module registry, no frame and no
# event at file top, inert by default: OnEnable acts only on a stored
# FX.db.logOn, writes SavedVariables only through Log:Enable, speaks in chat
# only when a user calls FX.Log or /fx log), so it rides the always-loaded
# Core load set like Locale/Messages/Probe. Errors: PLAN §11.11 -- the error
# recorder is a Forte_Core module too (handler and event frame created in
# OnEnable, never at file top; writes SavedVariables only on the first stored
# entry), always loaded.
ALWAYS_MODULES = {"Cooldown", "Errors", "Locale", "Log", "Messages", "Probe", "Splash", "TestMode", "Timer"}
LOAD_PROBES = {
    None: {"data": {"Paladin"}, "modules": set()},
    "Hunter": {"data": {"Hunter"}, "modules": {"Hunter", "HunterUI", "HunterMelee", "HunterMeleeUI",
                                               "HunterSwingDemo"}},  # melee rail: J beta; demo: K2
    "Warlock": {"data": {"Warlock"}, "modules": {"Warlock", "WarlockUI"}},
}
PROBE = ('local k={} for n in pairs(ForteXorcist.Data or {}) do if not n:find("ByName") then k[#k+1]=n end end '
         'table.sort(k) local m={} for n in pairs(ForteXorcist.modules or {}) do m[#m+1]=n end table.sort(m) '
         'local c={} for n in pairs(ForteXorcist.CLASS_ADDONS or {}) do if C_AddOns.IsAddOnLoaded(ForteXorcist.CLASS_ADDONS[n]) '
         'then c[#c+1]=ForteXorcist.CLASS_ADDONS[n] end end '
         'CreateFrame("Frame","FXPROBE__"..table.concat(k,"_").."__M__"..table.concat(m,"_")'
         '.."__O"..tostring(ForteXorcist.Options~=nil).. "__L"..tostring(#c)'
         '.."__C"..tostring(ForteXorcist._playerClass))')


def lua_errors():
    rc, out = sim("lua-errors")
    errs = sorted(set(FORTE_ERR.findall(out)))
    print(f"[load] Forte_* error sites: {errs or 'none'}")
    if errs: failures.append("lua-errors")
    # The sim's load summary only lists the slowest addons, so prove loading from live globals
    # and -- for the LoD split -- from the live C_AddOns registry, once per profile class.
    for cls, want in LOAD_PROBES.items():
        flags = ["--class", cls] if cls else []
        rc, out = sim(*flags, "--exec-lua", PROBE, "dump-tree")
        m = re.search(r"FXPROBE__(\w*?)__M__(\w*?)__O(true|false)__L(\d+)__C(\w+)", out)
        label = cls or "default(Paladin)"
        if not m:
            print(f"[load] FAIL {label}: probe frame not found"); failures.append(f"load probe {label}"); continue
        data = set(filter(None, m.group(1).split("_")))
        mods = set(filter(None, m.group(2).split("_")))
        opts, loaded_n, token = m.group(3), int(m.group(4)), m.group(5)
        want_data = ALWAYS_DATA | want["data"]
        want_mods = ALWAYS_MODULES | want["modules"]
        print(f"[load] {label}: data={sorted(data)} modules={sorted(mods)} "
              f"class addons loaded={loaded_n} class={token} options={opts}")
        missing = (want_data - data) | (want_mods - mods) | ({"Options"} if opts != "true" else set())
        extra = (data - want_data) | (mods - want_mods)
        bad = []
        if missing: bad.append(f"missing {sorted(missing)}")
        if extra: bad.append(f"extra {sorted(extra)}")
        if "Items" not in data:
            bad.append("Forte_Items data is not always-loaded")
        if loaded_n != 1:
            bad.append(f"{loaded_n} class add-ons loaded, expected exactly 1")
        want_token = (cls or "Paladin").upper()
        if token != want_token:
            bad.append(f"profile class {token}, expected {want_token}")
        if bad:
            print(f"[load] FAIL {label}: " + "; ".join(bad)); failures.append(f"load probe {label}")


def toc_pairs():
    for toc in sorted(glob.glob(os.path.join(ADDONS, "Forte_*", "Forte_*.toc"))):
        if toc.endswith("_Camelot.toc"): continue
        twin = toc[:-4] + "_Camelot.toc"
        same = os.path.exists(twin) and filecmp.cmp(toc, twin, shallow=False)
        iface = re.search(r"^## Interface:\s*(\S+)", open(toc, errors="replace").read(), re.M)
        ok = same and iface and iface.group(1) == "16001"
        if not ok:
            print(f"[toc] FAIL {os.path.relpath(toc, ROOT)} twin={same} interface={iface and iface.group(1)}")
            failures.append(f"toc {os.path.basename(toc)}")
    print("[toc] checked all pairs")
    # An always-loaded addon that lists a LoadOnDemand addon in Dependencies/OptionalDeps makes the
    # client load it for EVERY character (uiforever showed Forte_Warlock resident on a Hunter,
    # 2026-11-02; wow-ui-sim does not reproduce this, so it is checked statically).
    meta = {}
    for toc in glob.glob(os.path.join(ADDONS, "Forte_*", "Forte_*.toc")):
        if toc.endswith("_Camelot.toc"): continue
        text = open(toc, errors="replace").read()
        name = os.path.basename(toc)[:-4]
        deps = []
        for key in ("Dependencies", "RequiredDeps", "OptionalDeps"):
            m = re.search(rf"^## {key}:\s*(.+)$", text, re.M)
            if m: deps += [d.strip() for d in m.group(1).split(",") if d.strip()]
        lod = re.search(r"^## LoadOnDemand:\s*1", text, re.M) is not None
        meta[name] = (lod, deps)
    for name, (lod, deps) in sorted(meta.items()):
        if lod: continue
        bad = [d for d in deps if d in meta and meta[d][0]]
        if bad:
            print(f"[toc] FAIL {name} (always loaded) depends on LoadOnDemand {bad}: forces them to load")
            failures.append(f"toc lod-dep {name}")


def syntax():
    bad = 0
    for f in sorted(glob.glob(os.path.join(ADDONS, "**", "*.lua"), recursive=True)):
        p = subprocess.run(["luajit", "-e", f"assert(loadfile([[{f}]]))"], capture_output=True, text=True)
        if p.returncode:
            bad += 1
            print("[syntax] FAIL", os.path.relpath(f, ROOT), p.stderr.strip()[:200])
    print(f"[syntax] {'OK' if not bad else str(bad) + ' failures'}")
    if bad: failures.append("syntax")


STAMP = re.compile(rb"^-- Regenerated: ")


def normalized(path):
    return b"".join(l for l in open(path, "rb") if not STAMP.match(l))


def digest(paths):
    h = hashlib.sha256()
    for p in sorted(paths):
        h.update(normalized(p))
    return h.hexdigest()


def generators():
    spell_files = glob.glob(os.path.join(ADDONS, "Forte_*", "Data", "*.lua"))
    # Items.lua is gen_item_data.py's, and so is Forte_ItemProcs/Data/
    # Procs.lua (the H7 proc split, a load-on-demand data add-on): both
    # belong to the ITEM digest, not the spell one.
    spell_files = [f for f in spell_files
                   if not f.endswith("Items.lua")
                   and "Forte_ItemProcs" not in f]
    item_files = (glob.glob(os.path.join(ADDONS, "Forte_Items", "Data", "*.lua"))
                  + glob.glob(os.path.join(ADDONS, "Forte_ItemProcs", "Data", "*.lua")))
    before = (digest(spell_files), digest(item_files))
    originals = {p: open(p, "rb").read() for p in spell_files + item_files}
    cmds = [["python3", "tools/gen_spell_data.py", os.path.splitext(os.path.basename(j))[0]]
            for j in sorted(glob.glob(os.path.join(ROOT, "tools", "spell_lists", "*.json")))]
    cmds.append(["python3", "tools/gen_item_data.py"])
    for cmd in cmds:
        p = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        tail = (p.stdout + p.stderr).strip().splitlines()[-2:]
        print(f"[gen] {' '.join(cmd[1:])}: rc={p.returncode} {' | '.join(tail)}")
        if p.returncode: failures.append(f"gen {cmd[1]}")
    after = (digest(spell_files), digest(item_files))
    for name, b, a in (("spell data", before[0], after[0]), ("item data", before[1], after[1])):
        print(f"[gen] {name} deterministic: {b == a}")
        if b != a: failures.append(f"determinism {name}")
    # Content identical apart from the timestamp line: put the original bytes back so a gate run leaves no git churn.
    for p, raw in originals.items():
        if os.path.exists(p) and normalized(p) == b"".join(l for l in raw.splitlines(True) if not STAMP.match(l)):
            open(p, "wb").write(raw)

def api_lint():
    p = subprocess.run(["python3", os.path.join(ROOT, "scripts", "api_lint.py")], capture_output=True, text=True)
    for line in (p.stdout + p.stderr).strip().splitlines()[-12:]:
        print("[api]", line)
    if p.returncode: failures.append("api-lint")


# Data provenance (wave M3a, docs/research/data-diff-live-2026-11-07.md §9):
# the generated spell data is only as trustworthy as its stamps. The 70790
# refresh retired the three pins this check replaces, each welded to one
# build: the hard-coded `1.60.1.70707` stamp string, the literal
# "70707 overlay changes" wording and a research citation window that read
# only the header's first 1800 characters. The law is now build-GENERAL: the
# subject build/commit/hotfix are PARSED from tools/gen_spell_data.py's
# `LIVE_OVERLAY` pointer (the file the generator's own docstring calls the
# LIVE overlay -- the check follows the pointer, so the next refresh moves
# this check by editing that one line), and the citation window spans the
# WHOLE header comment block, so a citation may move as the header grows.
OVERLAY_POINTER = re.compile(r'LIVE_OVERLAY = HERE / "([^"]+)"')
DEVNOTES_POINTER = re.compile(r'DEFAULT_DEVNOTES = HERE / "([^"]+)"')


def data_provenance():
    gen = open(os.path.join(ROOT, "tools", "gen_spell_data.py"),
               errors="replace").read()
    overlay_m = OVERLAY_POINTER.search(gen)
    devnotes_m = DEVNOTES_POINTER.search(gen)
    if not overlay_m:
        print("[provenance] FAIL tools/gen_spell_data.py carries no "
               "LIVE_OVERLAY = HERE / \"...\" pointer")
        failures.append("provenance pointer")
        return
    overlay_path = os.path.join(ROOT, "tools", overlay_m.group(1))
    if not os.path.exists(overlay_path):
        print(f"[provenance] FAIL the generator's live overlay "
               f"tools/{overlay_m.group(1)} does not exist")
        failures.append("provenance live overlay")
        return
    meta = json.load(open(overlay_path))["_meta"]
    label = str(meta["build"]).split(".")[-1]          # 1.60.1.70790 -> 70790
    files = sorted(glob.glob(os.path.join(ADDONS, "Forte_*", "Data", "*.lua")))
    checked = 0
    for path in files:
        rel = os.path.relpath(path, ROOT)
        lines = open(path, errors="replace").read().splitlines()
        head = []
        for line in lines:
            if not line.startswith("--"): break
            head.append(line)
        header = "\n".join(head)
        is_class = rel.endswith(("Druid.lua", "Hunter.lua", "Mage.lua",
                                 "Paladin.lua", "Priest.lua", "Rogue.lua",
                                 "Shaman.lua", "Warlock.lua", "Warrior.lua"))
        wants = [
            # The overlay stamp: commit and build straight from the meta.
            (re.compile(rf"-- Overlay: wowsims/forever {meta['commit']} "
                        rf"build {re.escape(meta['build'])}"),
             f"overlay stamp (commit {meta['commit'][:10]}… build "
             f"{meta['build']}", header),
            (re.compile(rf"-- .*hotfix push {meta['hotfix_push']}"),
             f"hotfix push {meta['hotfix_push']}", header),
            # The builder: the overlay is extract_store.py's capture, not a
            # hand list (the check the 70707 pin carried, worded generically).
            (re.compile(r"-- .*built by tools/extract_store\.py"),
             "built by tools/extract_store.py", header),
            (re.compile(r"-- Source: mythicsim-forever-engine"),
             "mythicsim base source", header),
        ]
        if is_class and devnotes_m:
            wants.append((
                re.compile(rf"-- Dev notes: tools/{re.escape(devnotes_m.group(1))}"),
                f"dev-notes file {devnotes_m.group(1)}", header))
        missing = [what for rx, what, _ in wants if not rx.search(_)]
        # The change list: the header's "the live build's label overlay
        # changes in this file (N):" line, when present, carries the live
        # label and its bullet count is the list's true length (a stale
        # "70707 overlay changes" header -- the exact drift of §9 -- fails
        # the label test; a lying count fails the count test).
        cl = re.search(r"-- (\S+) overlay changes in this file \((\d+)\):",
                       header)
        if cl:
            n, bullets = int(cl.group(2)), 0
            after = [l for l in header[cl.end():].splitlines() if l.strip()]
            # The list is the CONTIGUOUS run of `--   ` bullets right under
            # the header line; the run ends at the next section heading.
            for line in after:
                if line.startswith("--   "): bullets += 1
                else: break
            if cl.group(1) != label:
                missing.append(f"change-list label {cl.group(1)!r}, the live "
                               f"overlay is {label!r}")
            elif bullets != n:
                missing.append(f"change-list says {n}, the header lists {bullets}")
        # A research citation anywhere in the header block (the whole block,
        # not a fixed byte window).
        if not re.search(r"docs/research/[A-Za-z0-9_\-.]+\.md", header):
            missing.append("a docs/research/*.md citation in the header block")
        checked += 1
        if missing:
            print(f"[provenance] FAIL {rel}: " + "; ".join(missing))
            failures.append(f"provenance {rel}")
    print(f"[provenance] {checked} generated data files audited against "
          f"tools/{overlay_m.group(1)} (build {meta['build']}, "
          f"{'all stamped' if not any(f.startswith('provenance') for f in failures) else 'SEE ABOVE'})")

if __name__ == "__main__":
    run_tests(); lua_errors(); toc_pairs(); syntax(); api_lint(); data_provenance()
    if "--fast" not in sys.argv: generators()
    print("\nGATE:", "PASS" if not failures else "FAIL -> " + ", ".join(failures))
    sys.exit(1 if failures else 0)
