#!/usr/bin/env python3
"""Extract one version's release notes from CHANGELOG.md into RELEASE_NOTES.md.

    scripts/release_notes.py [--version X] [--changelog FILE] [--out FILE]

The packager (`.pkgmeta` `manual-changelog`) sends RELEASE_NOTES.md as the
CurseForge "What's new" text and the GitHub release body, so it must hold one
release, not the whole CHANGELOG.md.

A section is a `## ` heading plus everything up to the next `## ` heading. The
heading of the wanted version must carry that version as a whole token:
`## [1.0.0] - 2026-11-10`, `## 1.0.0 (2026-11-10)`, `## v1.0.0 -- title`.
If several sections match (e.g. a re-release), the topmost one wins. A version
with no matching heading is an error (exit 1): a release must not ship with
another release's notes. The version defaults to the repo-root `VERSION` file.

Output = that section, heading included, trailing blank lines and `---` rules
dropped, ending in one newline.
"""
import argparse, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_version_file():
    with open(os.path.join(ROOT, "VERSION")) as fh:
        return fh.read().strip()


def heading_has_version(heading, version):
    """True when `version` occurs in `heading` as a whole token (not 1.0.0 in 11.0.05 / 1.0.0.1)."""
    return re.search(r"(?<![0-9A-Za-z.\-])v?" + re.escape(version) + r"(?![0-9A-Za-z]|\.[0-9]|-[0-9A-Za-z])",
                     heading) is not None


def extract(text, version):
    """The topmost `## ` section of `text` whose heading names `version`, or None."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if not line.startswith("## "):
            continue
        if start is not None:
            end = i
            break
        if heading_has_version(line[3:], version):
            start = i
    else:
        end = len(lines)
    if start is None:
        return None
    body = lines[start:end]
    while body and (not body[-1].strip() or re.fullmatch(r"-{3,}\s*", body[-1])):
        body.pop()
    return "\n".join(body) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(prog="release_notes.py", description=__doc__.splitlines()[0])
    ap.add_argument("--version", help="version to extract (default: the VERSION file; a leading v is ignored)")
    ap.add_argument("--changelog", default=os.path.join(ROOT, "CHANGELOG.md"))
    ap.add_argument("--out", default=os.path.join(ROOT, "RELEASE_NOTES.md"))
    a = ap.parse_args(argv)
    version = (a.version or read_version_file()).strip()
    if version.startswith("v"):
        version = version[1:]
    with open(a.changelog, encoding="utf-8") as fh:
        notes = extract(fh.read(), version)
    if notes is None:
        sys.exit(f"release_notes.py: no `## ` section for version {version} in "
                 f"{os.path.basename(a.changelog)} (heading must contain {version}, "
                 f"e.g. `## [{version}] - YYYY-MM-DD`)")
    with open(a.out, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(notes)
    print(f"release_notes.py: {version} -> {a.out} ({len(notes.splitlines())} lines)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
