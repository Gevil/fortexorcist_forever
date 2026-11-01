#!/usr/bin/env bash
# deploy.sh — deploy ForteXorcist addons into a WoW Forever Interface/AddOns dir.
#
# Default (symlink) mode links every addon/Forte_* directory that contains a
# .toc into the target AddOns dir as <AddOns>/<Name> -> <abs source dir>
# (ln -sfn, so re-running replaces existing symlinks idempotently). --copy
# mode installs real directory copies instead (see usage). Nothing outside
# this script's own symlinks/marked copies is ever deleted.
set -eu -o pipefail

DEFAULT_DEST='<WoW install>/_forever_/Interface/AddOns'

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
	  --remove      Remove only symlinks in the destination that point into this
	                repo's addon/ dir. Leaves everything else untouched
	                (including --copy deployments: remove those by hand).
	  --list        Per addon, print: source path, linked/linked-copy/unlinked,
	                and whether the destination entry is a foreign dir/file/symlink.

	Options:
	  --dest <dir>  Destination AddOns dir (overrides \$DEPLOY_DEST).
	  -h, --help    Show this help and exit.

	Environment:
	  DEPLOY_DEST   Destination AddOns dir. Default:
	                  $DEFAULT_DEST

	Safety:
	  - Refuses to run (exit 2) if the destination directory does not exist.
	    It is NEVER created: this script does not build WoW install trees.
	  - If <dest>/<Name> exists and is NOT a symlink (a real dir or file the
	    owner made by hand), that addon is refused with an error on stderr and
	    left alone. In --copy mode a real dir is accepted ONLY when it carries
	    the .fx-deploy-copy marker this script stamps; foreign dirs/files and
	    symlinks not pointing into this repo are refused the same way. Other
	    addons are still processed.
	  - Exit codes: 0 = all requested work done;
	                1 = deploy finished but >=1 addon was refused (see above),
	                    or a hard filesystem error occurred;
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

# ---------------------------------------------------------------- arg parsing
MODE=deploy
DEST=${DEPLOY_DEST:-$DEFAULT_DEST}
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)
      usage
      exit 0
      ;;
    --dest)
      [ $# -ge 2 ] || die 2 "--dest requires a directory argument"
      DEST=$2
      shift 2
      ;;
    --dest=*)
      DEST=${1#--dest=}
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
    *)
      die 2 "unknown option: $1 (try --help)"
      ;;
  esac
done

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
        rsync -a --delete --exclude=/tests/ -- "$src/" "$target/"
      else
        # cp -a has no exclude: copy the content, then drop tests/.
        cp -a -- "$src/." "$target/"
        if [ -e "$target/tests" ]; then rm -r -- "$target/tests"; fi
      fi
      printf 'ForteXorcist deploy.sh --copy from %s\n' "$src" > "$target/$COPY_MARKER"
      printf 'copied %s -> %s\n' "$name" "$target"
    done
    exit "$rc"
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
