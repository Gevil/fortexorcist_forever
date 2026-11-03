#!/usr/bin/env bash
# deploy.sh — deploy ForteXorcist addons into a WoW Forever Interface/AddOns dir.
#
# Default (symlink) mode links every addon/Forte_* directory that contains a
# .toc into the target AddOns dir as <AddOns>/<Name> -> <abs source dir>
# (ln -sfn, so re-running replaces existing symlinks idempotently). --copy
# mode installs real directory copies instead (see usage). --verify diffs the
# installed Forte_* trees against this repo's shipped file set (read-only).
# Nothing outside this script's own symlinks/marked copies is ever deleted.
#
# FOREVERSVFIX GUARD. Added under PLAN §9 (2026-11-01) on the premise "the
# installed client carries ForeverSVFix's SavedVariables workaround"; that
# premise is RETIRED by docs/research/upstream-addons-2026-11-03.md §5
# (2026-11-03): SVFix's own README (@c1591b1 README.md:1-5, head 2026-09-25)
# declares the loader bug fixed by Blizzard, and in the live _forever_ install
# exactly 1 of 33 add-on folders carries a stamp — and that one's
# ForeverSVFixData link is a dangling symlink into the retired _classic_beta_
# compatdata path. The reference set (CooldownMaster 2.0.4, EllesmereUI 9.7.2,
# TidyPlates, Auctionator, NeedRoll, WarEffortScout, WhisperMessenger) ships
# plain, unpatched `## SavedVariables:` headers.
# The guard stays: it is shape handling, not a premise. It costs nothing when
# the tool is absent (the normal case), and the hazard it guards is live —
# upstream-addons §10.6: a fresh SVFix run can re-stamp our TOCs through this
# script's symlinks. When such a tool IS installed it (a) edits addon .toc files
# IN PLACE — it stamps a `## X-ForeverSVFix: <n>` header and appends a
# `ForeverSVFixData\<Name>.lua` load line — and (b) links a `ForeverSVFixData`
# symlink from inside the addon folder into the WTF SavedVariables store.
# This script therefore: deploys with real copies, never symlinks, when asked
# (--copy), so an in-place .toc edit cannot reach the git working tree;
# rsync-excludes /ForeverSVFixData so --delete can not drop the link; re-creates
# the link when it replaces one of its own copies; and --verify classifies
# those three shapes as expected SVFix patches instead of deploy diffs.
# It NEVER writes to, deletes or "restores" a .toc SVFix has patched, and it
# never reads, links, copies over, replaces, verifies or deletes anything
# outside its own Forte_* entries.
set -eu -o pipefail

# The Forever client's AddOns folder: $FX_WOW_ADDONS, else the Steam (Proton) default.
DEFAULT_DEST=${FX_WOW_ADDONS:-"$HOME/.steam/steam/steamapps/compatdata/2691180173/pfx/drive_c/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"}

# Marker file this script stamps into every --copy deployment, so a later
# run recognises its OWN copies and replaces only those.
COPY_MARKER='.fx-deploy-copy'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)
ADDON_ROOT=$REPO_ROOT/addon

usage() {
  cat <<-EOF
	Usage: ${0##*/} [options]

	Deploys the game-loadable addons (addon/Forte_* dirs containing a .toc) into
	a WoW Forever Interface/AddOns directory. Re-running is idempotent; edits
	then need only /reload (symlink mode).

	Modes (pick at most one; default is deploy):
	  (no mode)     Deploy: (re)create symlinks for all Forte_* addons.
	  --copy        Copy mode: rsync/cp the addon dirs (minus tests/) into the
	                destination as real directories, replacing only this
	                script's own previous copies (marked with .fx-deploy-copy)
	                and its own previous symlinks. Use this when third-party
	                tools (e.g. ForeverSVFix) edit addon .toc files IN PLACE:
	                through a symlink such an edit writes into the git
	                working tree. Copies need this script re-run to update.
	                A ForeverSVFix Data link inside one of our own copies is
	                re-created after the copy, so the install keeps the
	                SavedVariables patch it was given.
	  --remove      Remove only symlinks in the destination that point into this
	                repo's addon/ dir. Leaves everything else untouched
	                (including --copy deployments: remove those by hand).
	  --list        Per addon, print: source path, linked/linked-copy/unlinked,
	                and whether the destination entry is a foreign dir/file/symlink.
	  --verify      Verify mode (read-only; combines with --copy, then runs
	                after the copies): for every Forte_* addon, compare the
	                installed tree against this repo's SHIPPED file set and
	                report per file: missing (repo has it, install has not),
	                extra (install has it, the shipped set has not), different
	                (bytes differ) and svfix (a .toc whose only difference is
	                ForeverSVFix's own in-place patch lines: a
	                '## X-ForeverSVFix' header and/or a 'ForeverSVFixData\\'
	                load line — a third-party patch, NOT counted as a diff and
	                the file is left exactly as the patch made it; the guard
	                does not assume any install carries such a patch). Files
	                the release does not ship are excluded from BOTH sides: any
	                tests/ dir, any docs/ dir and *.otf. Exit 0 only when every
	                installed addon matches the shipped set.

	Options:
	  --dest <dir>  Destination AddOns dir (overrides \$DEPLOY_DEST).
	  --target <dir>
	              Synonym for --dest: the directory to deploy into / verify.
	              Use it to point a test run at a scratch dir, e.g.
	                scripts/deploy.sh --target /tmp/fxdeploytest --copy --verify
	              so no real client install is ever touched.
	  -h, --help    Show this help and exit.

	Environment:
	  DEPLOY_DEST   Destination AddOns dir. Default:
	                  $DEFAULT_DEST

	Safety:
	  - Refuses to run (exit 2) if the destination directory does not exist.
	    It is NEVER created: this script does not build WoW install trees.
	  - Only entries named Forte_* (this repo's addons) are ever created,
	    replaced, compared or removed. Every scan is anchored at
	    <dest>/Forte_<Name>; no other addon in the destination — EllesmereUI,
	    CooldownMaster, ForeverSVFix itself, anything else — is ever read,
	    compared, linked, copied over, replaced, verified or deleted.
	  - Files the ForeverSVFix SavedVariables workaround owns are never
	    touched: an installed .toc it patched in place is only classified
	    (see --verify), never rewritten, and its ForeverSVFixData symlink is
	    excluded from rsync --delete and re-created when one of our own copies
	    is replaced.
	  - If <dest>/<Name> exists and is NOT a symlink (a real dir or file the
	    owner made by hand), that addon is refused with an error on stderr and
	    left alone. In --copy mode a real dir is accepted ONLY when it carries
	    the .fx-deploy-copy marker this script stamps; foreign dirs/files and
	    symlinks not pointing into this repo are refused the same way. Other
	    addons are still processed.
	  - Exit codes: 0 = all requested work done (with --verify: every installed
	                addon matches the shipped set);
	                1 = deploy finished but >=1 addon was refused (see above),
	                    a --verify diff was found, or a hard filesystem error
	                    occurred;
	                2 = usage error, or destination does not exist.
	EOF
}

die() { # <exit-code> <message...>
  local code=$1; shift
  printf 'deploy.sh: %s\n' "$*" >&2
  exit "$code"
}

has_toc() { # <dir>
  local f
  for f in "$1"/*.toc; do
    [ -e "$f" ] && return 0
  done
  return 1
}

# ------------------------------------------------------------------- verify
# The shipped/installed file sets are compared over the SAME exclusions the
# release uses (PLAN §11.1 H2): everything under a tests/ dir, everything
# under a docs/ dir, and *.otf (the font the client cannot load) is not part
# of what an install must carry. Relative paths, LC_ALL=C sorted.
shipped_files() { # <addon-src-dir>
  ( cd -- "$1" && find . -type f \
      ! -path '*/tests/*' ! -path '*/docs/*' ! -name '*.otf' \
      ! -name "$COPY_MARKER" ! -name '.gitignore' \
      -print | sed -e 's|^\./||' | LC_ALL=C sort )
}

installed_files() { # <installed-addon-dir>
  local t=$1
  ( cd -- "$t" && find . -type f \
      ! -path '*/tests/*' ! -path '*/docs/*' ! -name '*.otf' \
      ! -name "$COPY_MARKER" ! -name '.gitignore' \
      ! -path './ForeverSVFixData*' \
      -print | sed -e 's|^\./||' | LC_ALL=C sort )
}

# A .toc as written by this repo, normalised the way ForeverSVFix edits
# happen: its `## X-ForeverSVFix: <n>` marker, the `ForeverSVFixData\<Name>.lua`
# load line it appends and the blank line that separates them are dropped.
# Pure text filter: it NEVER writes the file it reads.
toc_norm() { # <toc-file>
  sed -e '/^##[[:space:]]*X-ForeverSVFix/d' \
      -e '/^ForeverSVFixData[\\/]/d' \
      -e '/^[[:space:]]*$/d' "$1"
}

# One addon: installed tree vs this repo's shipped set. Prints every
# difference; returns 0 when the install matches (a .toc that differs only by
# ForeverSVFix's own patch lines is printed as expected and is NOT a diff).
verify_addon() { # <src-dir>
  local src=$1 name=${1##*/}
  local target=$DEST/$name rc=0 f
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    printf 'MISSING %s/ (not installed in %s)\n' "$name" "$DEST"
    return 1
  fi
  if [ -L "$target" ]; then
    local tgt
    tgt=$(readlink -f -- "$target" 2>/dev/null) || tgt=
    if [ "$tgt" = "$src" ]; then
      printf 'OK %s/ (symlink install: the destination IS this repo tree)\n' "$name"
      return 0
    fi
    printf 'DIFFERENT %s/ (symlink to %s does not point into this repo)\n' "$name" "$tgt"
    return 1
  fi
  if [ ! -d "$target" ]; then
    printf 'DIFFERENT %s/ (destination entry is not a directory)\n' "$name"
    return 1
  fi
  local lists tmpx
  tmpx=$(mktemp -d) || die 1 "verify: mktemp failed"
  lists="$tmpx"
  shipped_files "$src" > "$lists/repo"
  installed_files "$target" > "$lists/inst"
  local extra
  extra=$(comm -13 "$lists/repo" "$lists/inst")
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf 'EXTRA %s/%s (installed, not shipped by this repo)\n' "$name" "$f"
    rc=1
  done <<< "$extra"
  local missing
  missing=$(comm -23 "$lists/repo" "$lists/inst")
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf 'MISSING %s/%s (shipped by this repo, not installed)\n' "$name" "$f"
    rc=1
  done <<< "$missing"
  local common
  common=$(comm -12 "$lists/repo" "$lists/inst")
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case $f in
      *.toc)
        if cmp -s -- "$src/$f" "$target/$f"; then
          continue
        fi
        if diff -q <(toc_norm "$src/$f") <(toc_norm "$target/$f") >/dev/null 2>&1; then
          printf 'SVFIX %s/%s (carries ForeverSVFix'\''s in-place .toc patch: a third-party patch, NOT a deploy diff, left untouched)\n' "$name" "$f"
        else
          printf 'DIFFERENT %s/%s\n' "$name" "$f"
          rc=1
        fi
        ;;
      *)
        if ! cmp -s -- "$src/$f" "$target/$f"; then
          printf 'DIFFERENT %s/%s\n' "$name" "$f"
          rc=1
        fi
        ;;
    esac
  done <<< "$common"
  local nfiles
  nfiles=$(wc -l < "$lists/repo")
  nfiles=${nfiles//[[:space:]]/}
  rm -r -- "$lists"
  if [ "$rc" = 0 ]; then
    printf 'OK %s/ (%s shipped file(s) match)\n' "$name" "$nfiles"
  fi
  return "$rc"
}

verify_all() {
  local rc=0 src n_ok=0 n_bad=0
  for src in "${ADDON_DIRS[@]}"; do
    if verify_addon "$src"; then
      n_ok=$((n_ok + 1))
    else
      n_bad=$((n_bad + 1))
      rc=1
    fi
  done
  printf 'verify: %d addon(s) match the shipped set, %d with differences (target %s)\n' \
    "$n_ok" "$n_bad" "$DEST"
  return "$rc"
}

# ---------------------------------------------------------------- arg parsing
MODE=deploy
VERIFY=0
DEST=${DEPLOY_DEST:-$DEFAULT_DEST}
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)
      usage
      exit 0
      ;;
    --dest|--target)
      [ $# -ge 2 ] || die 2 "$1 requires a directory argument"
      DEST=$2
      shift 2
      ;;
    --dest=*|--target=*)
      DEST=${1#*=}
      shift
      ;;
    --remove)
      [ "$MODE" = deploy ] || die 2 "only one mode allowed (--remove already set)"
      MODE=remove
      shift
      ;;
    --copy)
      [ "$MODE" = deploy ] || die 2 "only one mode allowed (--copy already set)"
      MODE=copy
      shift
      ;;
    --list)
      [ "$MODE" = deploy ] || die 2 "only one mode allowed (--list already set)"
      MODE=list
      shift
      ;;
    --verify)
      case $MODE in
        deploy|copy) VERIFY=1 ;;
        *) die 2 "--verify combines only with --copy (mode $MODE already set)" ;;
      esac
      shift
      ;;
    *)
      die 2 "unknown option: $1 (try --help)"
      ;;
  esac
done
# --verify alone is the read-only verify mode; with --copy it runs after the
# copies, which is the launch-day sequence (deploy, then prove the install).
if [ "$VERIFY" = 1 ] && [ "$MODE" = deploy ]; then
  MODE=verify
elif [ "$VERIFY" = 1 ] && [ "$MODE" != copy ]; then
  die 2 "--verify combines only with --copy (mode $MODE given)"
fi

# ---------------------------------------------------------------- preflights
[ -d "$ADDON_ROOT" ] || die 2 "addon source dir not found: $ADDON_ROOT"
[ -d "$DEST" ] || die 2 "destination does not exist: $DEST
Refusing to run: I will not mkdir a WoW install tree.
Point me at the real Interface/AddOns dir (--dest <dir> or \$DEPLOY_DEST)."

declare -a ADDON_DIRS=()
for d in "$ADDON_ROOT"/Forte_*; do
  [ -d "$d" ] || continue
  if has_toc "$d"; then
    ADDON_DIRS+=("$d")
  else
    printf 'deploy.sh: note: %s has no .toc; skipping\n' "$d" >&2
  fi
done
[ "${#ADDON_DIRS[@]}" -gt 0 ] || die 2 "no Forte_* dirs with a .toc under $ADDON_ROOT"

# ------------------------------------------------------------------- commands
case $MODE in
  list)
    for src in "${ADDON_DIRS[@]}"; do
      name=${src##*/}
      target=$DEST/$name
      state=unlinked
      if [ -L "$target" ]; then
        tgt=$(readlink -f -- "$target" 2>/dev/null) || tgt=
        if [ "$tgt" = "$src" ]; then
          state=linked
        else
          state="symlink-foreign(-> $tgt)"
        fi
      elif [ -d "$target" ]; then
        if [ -f "$target/$COPY_MARKER" ]; then
          state=linked-copy
        else
          state=foreign-dir
        fi
      elif [ -e "$target" ]; then
        state=foreign-file
      fi
      printf '%s\tsrc=%s\tstate=%s\n' "$name" "$src" "$state"
    done
    ;;
  remove)
    removed=0
    for link in "$DEST"/*; do
      [ -L "$link" ] || continue
      tgt=$(readlink -f -- "$link") || continue
      case $tgt in
        "$ADDON_ROOT"/*)
          rm -- "$link"
          printf 'removed %s\n' "$link"
          removed=$((removed + 1))
          ;;
      esac
    done
    printf '%d repo symlink(s) removed from %s\n' "$removed" "$DEST"
    ;;
  copy)
    # Real-directory deployments. Replaces ONLY this script's own prior
    # entries: its symlinks (pointing into this repo's addon/ dir) and its
    # copies (stamped with $COPY_MARKER). Everything foreign is refused and
    # left alone, exactly like the symlink mode's non-symlink rule.
    rc=0
    if command -v rsync >/dev/null 2>&1; then
      COPY_TOOL=rsync
    else
      COPY_TOOL=cp
    fi
    for src in "${ADDON_DIRS[@]}"; do
      name=${src##*/}
      target=$DEST/$name
      SVFIX_LINK_TARGET=
      if [ -e "$target" ] || [ -L "$target" ]; then
        if [ -L "$target" ]; then
          tgt=$(readlink -f -- "$target" 2>/dev/null) || tgt=
          case $tgt in
            "$ADDON_ROOT"/*) rm -- "$target" ;;
            *)
              printf 'deploy.sh: %s: REFUSED: %s is a symlink not pointing into this repo (-> %s); leaving it alone.\n' "$name" "$target" "$tgt" >&2
              rc=1
              continue
              ;;
          esac
        elif [ -d "$target" ]; then
          if [ -f "$target/$COPY_MARKER" ]; then
            # One of ours: remember a ForeverSVFix data link it carries
            # (recorded verbatim, re-created after the copy below) before
            # the replace.
            SVFIX_LINK_TARGET=
            if [ -L "$target/ForeverSVFixData" ]; then
              SVFIX_LINK_TARGET=$(readlink -- "$target/ForeverSVFixData")
            fi
            rm -r -- "$target"
          else
            printf 'deploy.sh: %s: REFUSED: %s is a directory this script did not create (no %s marker); refusing to delete a hand-made entry. Move/remove it manually, then re-run.\n' "$name" "$target" "$COPY_MARKER" >&2
            rc=1
            continue
          fi
        else
          printf 'deploy.sh: %s: REFUSED: %s exists and is not a directory or symlink.\n' "$name" "$target" >&2
          rc=1
          continue
        fi
      fi
      mkdir -- "$target"
      if [ "$COPY_TOOL" = rsync ]; then
        # -a preserves, --delete drops files removed upstream, the
        # anchored exclude keeps tests/ out of the game's face.
        # /ForeverSVFixData is excluded so --delete can never drop a
        # ForeverSVFix SavedVariables link that lives inside our own copy.
        rsync -a --delete --exclude=/tests/ --exclude=/ForeverSVFixData -- "$src/" "$target/"
      else
        # cp -a has no exclude: copy the content, then drop tests/.
        cp -a -- "$src/." "$target/"
        if [ -e "$target/tests" ]; then rm -r -- "$target/tests"; fi
      fi
      # ForeverSVFix keeps an addon's SavedVariables alive through a
      # ForeverSVFixData symlink inside the addon folder. We just replaced
      # that folder, so re-create the link (its own target, verbatim) and
      # never touch the file it points at.
      if [ -n "$SVFIX_LINK_TARGET" ] && [ ! -e "$target/ForeverSVFixData" ]; then
        ln -s -- "$SVFIX_LINK_TARGET" "$target/ForeverSVFixData"
        printf 'kept ForeverSVFix data link in %s (-> %s)\n' "$name" "$SVFIX_LINK_TARGET"
      fi
      SVFIX_LINK_TARGET=
      printf 'ForteXorcist deploy.sh --copy from %s\n' "$src" > "$target/$COPY_MARKER"
      printf 'copied %s -> %s\n' "$name" "$target"
    done
    if [ "$VERIFY" = 1 ]; then
      verify_all || rc=1
    fi
    exit "$rc"
    ;;
  verify)
    # Read-only: never writes, never creates, never deletes.
    verify_all
    exit $?
    ;;
  deploy)
    rc=0
    printf 'deploy.sh: note: symlinks make the git working tree the live addon files. Third-party tools that edit addon .toc files IN PLACE (e.g. ForeverSVFix) write through the symlink into this repo. If such tools are installed, deploy with --copy instead.\n' >&2
    for src in "${ADDON_DIRS[@]}"; do
      name=${src##*/}
      target=$DEST/$name
      if [ -e "$target" ] || [ -L "$target" ]; then
        if [ ! -L "$target" ]; then
          printf 'deploy.sh: %s: REFUSED: %s exists and is not a symlink; refusing to delete a hand-made entry. Move/remove it manually, then re-run.\n' "$name" "$target" >&2
          rc=1
          continue
        fi
      fi
      ln -sfn -- "$src" "$target"
      printf 'deployed %s -> %s\n' "$name" "$target"
    done
    exit "$rc"
    ;;
esac
