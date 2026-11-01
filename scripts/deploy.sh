#!/usr/bin/env bash
# deploy.sh — deploy ForteXorcist addons into a WoW Forever Interface/AddOns dir.
#
# Symlinks every addon/Forte_* directory that contains a .toc into the target
# AddOns dir as <AddOns>/<Name> -> <abs source dir> (ln -sfn, so re-running
# replaces existing symlinks idempotently). Never copies, never deletes
# anything that is not a repo-owned symlink.
set -eu -o pipefail

DEFAULT_DEST='<WoW install>/_forever_/Interface/AddOns'

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)
ADDON_ROOT=$REPO_ROOT/addon

usage() {
  cat <<-EOF
	Usage: ${0##*/} [options]

	Deploys the game-loadable addons (addon/Forte_* dirs containing a .toc) into
	a WoW Forever Interface/AddOns directory as symlinks to the source dirs.
	Re-running replaces the symlinks (idempotent); edits then need only /reload.

	Modes (pick at most one; default is deploy):
	  (no mode)     Deploy: (re)create symlinks for all Forte_* addons.
	  --remove      Remove only symlinks in the destination that point into this
	                repo's addon/ dir. Leaves everything else untouched.
	  --list        Per addon, print: source path, linked/unlinked, and whether
	                the destination entry is a foreign dir/file/symlink.

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
	    left alone. Other addons are still processed.
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
        state=foreign-dir
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
  deploy)
    rc=0
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
