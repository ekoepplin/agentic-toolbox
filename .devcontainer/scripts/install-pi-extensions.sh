#!/usr/bin/env bash
# pi extension installer — called by the dock step (dock.sh) on every workbench
# start, after the pi provider/settings config is seeded.
#
# pi packages are PINNED in .devcontainer/pi-extensions.lock (npm:name@version
# or git:host/user/repo@ref), so a rebuild reproduces the same extension set —
# the pi analogue of skills.lock / install-skills.sh. To add or bump a package,
# edit the lock and restart the workbench (or re-run this script).
set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/../.." && pwd)"
LOCKFILE="$WORKSPACE/.devcontainer/pi-extensions.lock"
SETTINGS="$HOME/.pi/agent/settings.json"

# pi install shells out to npm. The image's global /home/node/.npm cache can end
# up root-owned (a root-level npm step re-populates it after the Dockerfile's
# chown), which makes `npm install` fail with EACCES. Route npm at a cache dir we
# own so the install never depends on the global cache's ownership.
export npm_config_cache="$HOME/.pi/npm-cache"
mkdir -p "$npm_config_cache"

if [ ! -f "$LOCKFILE" ]; then
  echo "pi: no ${LOCKFILE#"$WORKSPACE"/} — no extensions to install"
  exit 0
fi

# Best-effort skip: if the exact pinned source is already recorded in
# settings.json packages[], pi has it — no network. On any mismatch (first run
# or a version bump) we fall through to `pi install`, which is the source of
# truth and rewrites packages[].
already_installed() {
  python3 - "$SETTINGS" "$1" <<'PY'
import json, sys
path, src = sys.argv[1], sys.argv[2]
try:
    pkgs = json.load(open(path)).get("packages", [])
except (FileNotFoundError, ValueError):
    pkgs = []
sys.exit(0 if src in json.dumps(pkgs) else 1)
PY
}

count=0
while IFS= read -r line; do
  src="${line%%#*}"                          # strip trailing/inline comments
  src="$(printf '%s' "$src" | tr -d '[:space:]')"
  [ -n "$src" ] || continue
  count=$((count + 1))
  if already_installed "$src"; then
    echo "  ✓ $src (pin satisfied — no install)"
    continue
  fi
  echo "  ↓ pi install $src"
  pi install "$src"
done < "$LOCKFILE"

if [ "$count" -eq 0 ]; then
  echo "pi: ${LOCKFILE#"$WORKSPACE"/} has no entries — nothing to install"
else
  echo "pi extensions ready ($count pinned)"
fi
