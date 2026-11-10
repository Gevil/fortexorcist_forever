#!/usr/bin/env python3
"""Build the ForteXorcist release zip (PLAN §11.1 slice H2).

    scripts/release.py [--dry-run] [--version X] [--out DIR] [--name NAME]
                     [--suffix SUFFIX] [--ref GIT-REF]

One source of truth for the version: the repo-root `VERSION` file. The
version is stamped into every shipped addon's toc twins as `## Version:`
(both twins get the identical bytes, so `gate.py`'s byte-identical toc-pair
check and its `## Interface: 16001` check keep passing on a stamped tree).

Output, in `dist/`:
  ForteXorcist-<version>-forever.zip         the GitHub release asset. WowUp
                                             offers a GitHub zip to a Forever
                                             install only when its name ends
                                             in `-forever.zip` (an unsuffixed
                                             zip is treated as Retail).
  ForteXorcist-<version>-forever.zip.sha256  `sha256sum` format, so
                                             `sha256sum -c` works next to it.
`--suffix ""` produces the old unsuffixed name (`ForteXorcist-<version>.zip`).

The payload is `git archive HEAD addon` -- the COMMITTED tree, so the zip can
never be built from half-finished working-copy files. The release set is what
the game loads, minus what the game must not load:
  * `*/tests/*`   the sim's test suites (not in any .toc; the client would
                  load them if they shipped -- never ship a test)
  * `*.otf`       the OpenType build of the vendored font (the client loads
                  the .ttf build only -- deploy.sh excludes it the same way)
  * `*/docs/*`    prose that lives inside an addon folder

Every addon's two tocs are stamped identically and asserted byte-equal, and
the addon's `## Interface:` line is asserted to stay `16001`.

Nothing in the repo working tree is written: the staging tree lives in a temp
dir, the output goes to `dist/` (created on demand). `--dry-run` builds the
whole staging tree, prints the plan (file list + sizes + stamp table) and
writes nothing.

The CurseForge / Wago / GitHub-release pipeline is the tag-triggered
workflow in `.github/workflows/release.yml` (BigWigs packager, `.pkgmeta`).
This script is the local, offline builder of the same payload.
"""
import argparse, hashlib, os, re, shutil, subprocess, sys, tempfile, zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VERSION_FILE = os.path.join(ROOT, "VERSION")
EXCLUDE_DIR_PARTS = ("tests", "docs")
EXCLUDE_SUFFIXES = (".otf",)
INTERFACE = "16001"
# Fixed epoch for deterministic archives (zip: 1980-01-01 is the format floor).
ZIP_DATE = (1980, 1, 1, 0, 0, 0)
TOC_STAMP = re.compile(r"^##[ \t]*Version:[ \t]*(.*)$", re.M)
TOC_IFACE = re.compile(r"^##[ \t]*Interface:[ \t]*(\S+)", re.M)


def die(msg, code=2):
    sys.exit(f"release.py: {msg}")


def read_version(override=None):
    """(version, source_label)"""
    if override:
        raw, src = override.strip(), "--version"
    else:
        if not os.path.isfile(VERSION_FILE):
            die(f"no version source: {os.path.relpath(VERSION_FILE, ROOT)} is missing "
                "(create it: one line, e.g. 1.0.0)")
        with open(VERSION_FILE, errors="replace") as fh:
            raw, src = fh.read().strip(), os.path.relpath(VERSION_FILE, ROOT)
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?", raw):
        die(f"version {raw!r} is not a release version (want e.g. 1.0.0 or 1.0.1-rc1)")
    return raw, src


def git_archive_addon(staging, ref="HEAD"):
    """Extract `git archive <ref> addon` into staging; return the addon root."""
    head = run_git(["rev-parse", "--short", ref])
    src = os.path.join(staging, "src")
    os.makedirs(src)
    proc = subprocess.run(["git", "-C", ROOT, "archive", "--format=tar", ref, "addon"],
                          capture_output=True)
    if proc.returncode:
        die(f"git archive {ref} addon failed: {proc.stderr.decode(errors='replace').strip()}")
    tar = os.path.join(staging, "head.tar")
    with open(tar, "wb") as fh:
        fh.write(proc.stdout)
    proc = subprocess.run(["tar", "-xf", tar, "-C", src], capture_output=True)
    if proc.returncode:
        die(f"unpacking the archive failed: {proc.stderr.decode(errors='replace').strip()}")
    return os.path.join(src, "addon"), head


def run_git(args):
    proc = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True)
    if proc.returncode:
        die(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout.strip()


def is_shipped(rel):
    parts = rel.split(os.sep)
    if any(p in EXCLUDE_DIR_PARTS for p in parts[:-1]):
        return False
    return not rel.lower().endswith(EXCLUDE_SUFFIXES)


def collect(addon_root):
    """(kept, dropped) lists of repo-relative-to-addon-root paths."""
    kept, dropped = [], []
    for base, dirs, files in os.walk(addon_root):
        dirs.sort()
        for name in sorted(files):
            full = os.path.join(base, name)
            rel = os.path.relpath(full, addon_root)
            (kept if is_shipped(rel) else dropped).append((rel, os.path.getsize(full)))
    kept.sort()
    dropped.sort()
    return kept, dropped


def stamp_toc(text, version):
    """`## Version: <version>` set, in place, or added below ## Title:/## Interface:.

    Returns (new_text, action) with action in {unchanged, stamped, added}.
    """
    if TOC_STAMP.search(text):
        new = TOC_STAMP.sub(lambda m: f"## Version: {version}", text, count=1)
        return new, ("unchanged" if new == text else "stamped")
    lines = text.splitlines(True)
    for key in ("## Title:", "## Interface:"):
        for i, line in enumerate(lines):
            if line.lstrip().startswith(key):
                pad = "\n" if not lines[i].endswith("\n") else ""
                lines.insert(i + 1, f"{pad}## Version: {version}\n")
                return "".join(lines), "added"
    return f"## Version: {version}\n" + text, "added"


def toc_pairs(addon_root):
    """[(base_toc, twin_toc)] relative to addon_root, for the gate's twin law."""
    out = []
    for base, _dirs, files in os.walk(addon_root):
        for name in sorted(files):
            if not name.endswith(".toc") or name.endswith("_Camelot.toc"):
                continue
            rel = os.path.relpath(os.path.join(base, name), addon_root)
            twin = os.path.join(base, name[:-4] + "_Camelot.toc")
            out.append((rel, os.path.relpath(twin, addon_root)
                        if os.path.isfile(twin) else None))
    out.sort()
    return out


def build(version, version_source, out_dir, name, suffix, dry_run, ref="HEAD"):
    staging = tempfile.mkdtemp(prefix="fxrelease-")
    try:
        addon_root, head = git_archive_addon(staging, ref)
        kept, dropped = collect(addon_root)
        kept_names = {rel for rel, _ in kept}

        # --- the two laws the release must never break -------------------
        problems = []
        for rel, twin in toc_pairs(addon_root):
            if os.path.relpath(os.path.join(addon_root, rel), addon_root) not in kept_names:
                continue                      # a toc the release does not ship
            if twin is None:
                problems.append(f"{rel}: no _Camelot.toc twin in the release set")
                continue
            a = open(os.path.join(addon_root, rel), "rb").read()
            b = open(os.path.join(addon_root, twin), "rb").read()
            if a != b:
                problems.append(f"{rel}: toc twin {twin} is not byte-identical")
            iface = TOC_IFACE.search(a.decode(errors="replace"))
            if not iface or iface.group(1) != INTERFACE:
                problems.append(f"{rel}: ## Interface is "
                                f"{iface.group(1) if iface else 'absent'}, want {INTERFACE}")
        if problems:
            die("refusing to release:\n  " + "\n  ".join(problems), 1)

        # --- stamp the version into every shipped toc -------------------
        stamps = []
        for rel, _size in [p for p in kept if p[0].endswith(".toc")]:
            full = os.path.join(addon_root, rel)
            text = open(full, errors="replace").read()
            new, action = stamp_toc(text, version)
            if new != text:
                with open(full, "w") as fh:
                    fh.write(new)
            stamps.append((rel, action))
        for rel, twin in toc_pairs(addon_root):
            if twin is None:
                continue
            full, twin_full = (os.path.join(addon_root, p) for p in (rel, twin))
            if not (os.path.isfile(full) and os.path.isfile(twin_full)):
                continue
            if open(full, "rb").read() != open(twin_full, "rb").read():
                die(f"stamping broke the twin law: {rel} != {twin}", 1)

        # --- the archive ------------------------------------------------
        stem = f"{name}-{version}" + (f"-{suffix}" if suffix else "")
        zip_path = os.path.join(out_dir, stem + ".zip")
        sha_path = zip_path + ".sha256"
        entries = []
        total = 0
        for rel, _size in kept:
            full = os.path.join(addon_root, rel)
            size = os.path.getsize(full)
            total += size
            entries.append((rel.replace(os.sep, "/"), size))

        digest = None
        if not dry_run:
            os.makedirs(out_dir, exist_ok=True)
            with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
                for rel, _size in entries:
                    zi = zipfile.ZipInfo(rel, date_time=ZIP_DATE)
                    zi.compress_type = zipfile.ZIP_DEFLATED
                    zf.writestr(zi, open(os.path.join(addon_root, rel), "rb").read())
            with open(zip_path, "rb") as fh:
                digest = hashlib.sha256(fh.read()).hexdigest()
            with open(sha_path, "w", newline="\n") as fh:
                fh.write(f"{digest}  {os.path.basename(zip_path)}\n")

        # --- the report --------------------------------------------------
        print(f"release.py  version {version}  (source: {version_source}; "
               f"archive: git archive {ref} = {head})")
        print(f"  addons:   {len({p[0].split('/')[0] for p in entries})}")
        print(f"  files:    {len(entries)}  raw {total / 1024:.1f} KiB")
        for rel, size in entries:
            print(f"    {size:>9,}  {rel}")
        print(f"  excluded: {len(dropped)} file(s)")
        for rel, size in dropped:
            print(f"    {size:>9,}  {rel}")
        print("  toc version stamps:")
        for rel, action in stamps:
            print(f"    {action:<10} {rel}  ## Version: {version}")
        if dry_run:
            print(f"  DRY RUN: nothing written; the build would be "
                  f"{zip_path} + {sha_path} "
                  f"({len(entries)} files, {total / 1024:.1f} KiB raw)")
        else:
            size = os.path.getsize(zip_path)
            print(f"  wrote:    {os.path.relpath(zip_path, ROOT)} "
                  f"{size:,} bytes ({size / 1024:.1f} KiB), "
                  f"{len(entries)} entries")
            print(f"  wrote:    {os.path.relpath(sha_path, ROOT)}  sha256 {digest}")
        return 0
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="release.py", add_help=True,
                                 description=__doc__.splitlines()[0])
    ap.add_argument("--dry-run", action="store_true",
                    help="build and report; write no zip")
    ap.add_argument("--version", help="override the VERSION file (a release "
                                       "version, e.g. 1.0.0-rc1)")
    ap.add_argument("--out", default=os.path.join(ROOT, "dist"),
                    help="output dir (default: <repo>/dist)")
    ap.add_argument("--name", default="ForteXorcist",
                    help="archive base name (default: ForteXorcist)")
    ap.add_argument("--suffix", default="forever",
                    help="archive name suffix: <name>-<version>-<suffix>.zip "
                         "(default: forever, which WowUp needs for a Forever "
                         "install; '' = unsuffixed <name>-<version>.zip)")
    ap.add_argument("--ref", default="HEAD",
                    help="git ref to release (default: HEAD -- the committed "
                         "tree; a tag or commit id for a re-release)")
    a = ap.parse_args(argv)
    version, source = read_version(a.version)
    return build(version, source, a.out, a.name, a.suffix, a.dry_run, a.ref)


if __name__ == "__main__":
    sys.exit(main())
