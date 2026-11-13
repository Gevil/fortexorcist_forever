#!/usr/bin/env bash
# dev_sim.sh -- build a TEMP addons dir for wow-ui-sim that holds every addon/Forte_* plus dev/Forte_Dev
# (symlinks; nothing is copied, the repo is never written), then optionally run the simulator on it.
#
#   scripts/dev_sim.sh                              build the dir, print its path
#   scripts/dev_sim.sh run-tests Forte_Dev          build + run the Forte_Dev suites (one sim at a time)
#   scripts/dev_sim.sh --exec-lua '...' dump-tree   any wow-sim arguments after the dir is built
#
# Env: FX_DEV_ADDONS = the temp dir (default /tmp/fx-dev-addons), WOW_UI_SIM = path of wow-ui-sim's run.sh
# (default: the sibling checkout). The sim runs from /tmp under `flock` on run.sh so concurrent callers
# queue instead of storming the CPU. gate.py does not know dev/: run this for the dev addon.
set -eu -o pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
ROOT=$(cd -- "$HERE/.." && pwd -P)
DEST=${FX_DEV_ADDONS:-/tmp/fx-dev-addons}
SIM=${WOW_UI_SIM:-$(dirname "$ROOT")/wow-ui-sim/run.sh}

case "$DEST" in
  /tmp/*) ;;
  *) echo "dev_sim.sh: FX_DEV_ADDONS must live under /tmp (got $DEST)" >&2; exit 2 ;;
esac

mkdir -p "$DEST"
# Only symlinks are ever removed, and only the ones this script made (Forte_* names).
find "$DEST" -maxdepth 1 -type l -name 'Forte_*' -delete
for d in "$ROOT"/addon/Forte_* "$ROOT"/dev/Forte_Dev; do
  [ -f "$d/$(basename "$d").toc" ] && ln -sfn "$d" "$DEST/$(basename "$d")"
done

if [ "$#" -eq 0 ]; then
  echo "$DEST"
  exit 0
fi

cd /tmp
exec flock "$SIM" "$SIM" wow-sim --allow-ui-version-mismatch --no-saved-vars --addons-path "$DEST" "$@"
