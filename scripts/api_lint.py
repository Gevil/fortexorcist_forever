#!/usr/bin/env python3
"""Flag every `C_Namespace.Function` / `Enum.Name` referenced in addon Lua that the pinned
WoW Forever API catalog does not declare. Catches invented API names, which would otherwise
fail silently inside pcall and record misleading "absent" results.

Usage: scripts/api_lint.py [paths...]   (default: addon/, tests excluded)
Exit 1 when unknown names are found. Lines may opt out with a trailing `-- api-lint: ok <reason>`.
"""
import glob, json, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGS = glob.glob(os.path.join(ROOT, "docs/api/wow-addon-api-agents/skills/*/references/generated/forever.json"))
REF = re.compile(r"\b(C_[A-Za-z0-9]+)\.([A-Za-z_][A-Za-z0-9_]*)\b")
ENUM = re.compile(r"\bEnum\.([A-Za-z0-9_]+)\b")
# Registering an unknown event raises on the live client, so every literal that reaches
# RegisterEvent/RegisterUnitEvent (directly, or listed in a table of event names) is checked.
EVENT_CALL = re.compile(r"Register(?:Unit)?Event\(\s*\"([A-Z][A-Z0-9_]+)\"")
EVENT_LIST = re.compile(r"\"([A-Z][A-Z0-9_]{4,})\"")


def load_catalog():
    """Each catalog is one JSON document: {..., "declarations": [ {symbol, kind, name, ...}, ... ]}."""
    symbols, namespaces, enums, events = set(), set(), set(), set()
    for path in CATALOGS:
        with open(path, errors="replace") as fh:
            doc = json.load(fh)
        for rec in doc.get("declarations", []):
            sym = rec.get("symbol") or ""
            kind = rec.get("kind")
            if kind in ("enumeration", "constants"):
                enums.add(rec.get("name") or sym)
            if kind == "event":
                events.add(sym)
            if "." in sym and sym.startswith("C_"):
                symbols.add(sym)
                namespaces.add(sym.split(".")[0])
            elif kind == "namespace" and sym.startswith("C_"):
                namespaces.add(sym)
    return symbols, namespaces, enums, events


def main(argv):
    symbols, namespaces, enums, events = load_catalog()
    paths = argv or [os.path.join(ROOT, "addon")]
    files = []
    for p in paths:
        files += [p] if p.endswith(".lua") else glob.glob(os.path.join(p, "**", "*.lua"), recursive=True)
    files = [f for f in files if "/tests/" not in f and "/Data/" not in f]
    bad = []
    for f in sorted(files):
        for n, line in enumerate(open(f, errors="replace"), 1):
            code = line.split("--", 1)[0] if "api-lint: ok" not in line else ""
            for ns, fn in REF.findall(code):
                sym = f"{ns}.{fn}"
                if sym not in symbols:
                    why = "unknown namespace" if ns not in namespaces else "not in namespace"
                    bad.append((os.path.relpath(f, ROOT), n, sym, why))
            for en in ENUM.findall(code):
                if en not in enums:
                    bad.append((os.path.relpath(f, ROOT), n, f"Enum.{en}", "unknown enum"))
            for ev in EVENT_CALL.findall(code):
                if ev not in events:
                    bad.append((os.path.relpath(f, ROOT), n, ev, "unknown event registered"))
            # Event-name tables (e.g. `local EVENTS = { "PLAYER_SWING", ... }`): any all-caps
            # literal on a line that looks like an event list entry and ends in a known suffix shape.
            if "Register" not in code and re.match(r"\s*(\"[A-Z][A-Z0-9_]+\"\s*,?\s*)+(\}|,)?\s*$", code):
                for ev in EVENT_LIST.findall(code):
                    if ev not in events:
                        bad.append((os.path.relpath(f, ROOT), n, ev, "unknown event in event list"))
    for f, n, sym, why in bad:
        print(f"{f}:{n}: {sym} ({why})")
    print(f"[api-lint] {len(files)} files, catalog {len(symbols)} C_ symbols / {len(enums)} enums / "
          f"{len(events)} events: {'OK' if not bad else str(len(bad)) + ' unknown references'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
