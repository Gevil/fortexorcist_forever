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
import filecmp, glob, hashlib, os, re, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDONS = os.path.join(ROOT, "addon")
SIM = os.path.expanduser("$WORK/wow-ui-sim/run.sh")
ANSI = re.compile(r"\x1b\[[0-9;]*m")
FORTE_ERR = re.compile(r"(Forte_\w+/[\w/\.]+:\d+)")

failures = []


def sim(*args):
    p = subprocess.run([SIM, "wow-sim", "--allow-ui-version-mismatch", "--addons-path", ADDONS, *args],
                       cwd="/tmp", capture_output=True, text=True, errors="replace")
    return p.returncode, ANSI.sub("", p.stdout + p.stderr)


def run_tests():
    for d in sorted(glob.glob(os.path.join(ADDONS, "Forte_*", "tests"))):
        addon = os.path.basename(os.path.dirname(d))
        rc, out = sim("run-tests", addon)
        counts = re.findall(r"(\d+) tests?, (\d+) passed, (\d+) failed", out)
        fails = [l.strip()[:140] for l in out.splitlines() if "\u2717" in l]
        errs = sorted(set(FORTE_ERR.findall(out)))
        ok = rc == 0 and counts and counts[-1][2] == "0" and not fails and not errs
        print(f"[tests] {addon}: {counts[-1] if counts else 'no summary'} rc={rc} {'OK' if ok else 'FAIL'}")
        for f in fails: print("        ", f)
        for e in errs: print("         error at", e)
        if not ok: failures.append(f"tests {addon}")


EXPECTED_DATA = {"Druid", "Hunter", "Items", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior"}
EXPECTED_MODULES = {"Cooldown", "Hunter", "HunterUI", "Probe", "Timer", "Warlock", "WarlockUI"}
PROBE = ('local k={} for n in pairs(ForteXorcist.Data or {}) do if not n:find("ByName") then k[#k+1]=n end end '
         'table.sort(k) local m={} for n in pairs(ForteXorcist.modules or {}) do m[#m+1]=n end table.sort(m) '
         'CreateFrame("Frame","FXPROBE__"..table.concat(k,"_").."__M__"..table.concat(m,"_")'
         '.."__O"..tostring(ForteXorcist.Options~=nil))')


def lua_errors():
    rc, out = sim("lua-errors")
    errs = sorted(set(FORTE_ERR.findall(out)))
    print(f"[load] Forte_* error sites: {errs or 'none'}")
    if errs: failures.append("lua-errors")
    # The sim's load summary only lists the slowest addons, so prove loading from live globals instead.
    rc, out = sim("--exec-lua", PROBE, "dump-tree")
    m = re.search(r"FXPROBE__(\w*?)__M__(\w*?)__O(true|false)", out)
    if not m:
        print("[load] FAIL probe frame not found"); failures.append("load probe"); return
    data, mods, opts = set(filter(None, m.group(1).split("_"))), set(filter(None, m.group(2).split("_"))), m.group(3)
    print(f"[load] data sets: {sorted(data)}; modules: {sorted(mods)}; options: {opts}")
    missing = (EXPECTED_DATA - data) | (EXPECTED_MODULES - mods) | ({"Options"} if opts != "true" else set())
    if missing:
        print(f"[load] FAIL missing: {sorted(missing)}"); failures.append("load probe")


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
    spell_files = [f for f in spell_files if not f.endswith("Items.lua")]
    item_files = glob.glob(os.path.join(ADDONS, "Forte_Items", "Data", "*.lua"))
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


if __name__ == "__main__":
    run_tests(); lua_errors(); toc_pairs(); syntax(); api_lint()
    if "--fast" not in sys.argv: generators()
    print("\nGATE:", "PASS" if not failures else "FAIL -> " + ", ".join(failures))
    sys.exit(1 if failures else 0)
