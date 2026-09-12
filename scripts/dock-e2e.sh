#!/usr/bin/env bash
# The dock E2E (issue #12): the runtime gate — the runtime counterpart of the
# static drift guard (scripts/check.sh). See docs/harnesses/dock-e2e.md.
#
# From a clean state (no scratch project), one command proves the full dock
# pipeline in a single deterministic run:
#
#   1. scaffold   — the #11 scaffolder (scripts/dock-host.sh) turns a
#                   throwaway git repo into a docked host project
#                   (compose.yaml, .env, .devcontainer/devcontainer.json,
#                   free SSH port, base image built if missing)
#   2. up         — the scratch workbench comes up; the dock step (issue #10)
#                   wires every harness adapter on start
#   3. probes     — the #10 probe battery (probe-dock.sh) inside the workbench:
#                   Claude-adapter skill expansion, pi discovery + model probe,
#                   vendored set a no-op on the second dock run
#   4. pin        — the vendored set sits at the ref pinned in skills.lock
#   5. dirty-base — the dock step warns when the base mount is dirtied
#   6. teardown   — the scratch project and its container state are removed;
#                   no residue, even when a probe fails
#
# Every probe is deterministic: no LLM call, no model endpoint needed (the
# model probe checks pi's catalog, not the endpoint). Exits non-zero on any
# probe failure (usable as a gate).
#
#   usage: scripts/dock-e2e.sh        or:  make dock-e2e
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"

die() { echo "dock-e2e: FATAL: $*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker CLI not found on PATH"
docker info >/dev/null 2>&1 || die "docker daemon not reachable — start Docker/colima first"

# ── Scratch project + teardown (no residue, even on failure) ────────────────
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/dock-e2e.XXXXXX")"
MARKER="$BASE_DIR/.e2e-dirty-marker"

cleanup() {
  rm -f "$MARKER"
  if [ -f "$SCRATCH/compose.yaml" ]; then
    ( cd "$SCRATCH" && docker compose down --remove-orphans -v ) >/dev/null 2>&1 || true
  fi
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

echo "dock-e2e: scratch host project at $SCRATCH"
git -C "$SCRATCH" init -q

# ── 1. Scaffold (issue #11) ─────────────────────────────────────────────────
bash "$SCRIPTS_DIR/dock-host.sh" "$SCRATCH"
for f in compose.yaml .env .devcontainer/devcontainer.json; do
  [ -f "$SCRATCH/$f" ] || die "scaffolder did not create $SCRATCH/$f"
done
echo "dock-e2e: scratch project docked (three-file tree present)"

# ── 2. Workbench up; wait for the dock step to wire every adapter ───────────
( cd "$SCRATCH" && docker compose up -d )
echo "dock-e2e: workbench up — waiting for the dock step"
deadline=$(( $(date +%s) + 300 ))
while :; do
  cid="$( cd "$SCRATCH" && docker compose ps -q )"
  [ -n "$cid" ] || die "workbench container never appeared"
  running="$(docker inspect -f '{{.State.Running}}' "$cid")"
  [ "$running" = "true" ] || die "workbench container exited (State.Running=$running)"
  logs="$( cd "$SCRATCH" && docker compose logs --no-color workbench 2>/dev/null || true )"
  if printf '%s\n' "$logs" | grep -q "dock: step FAILED"; then
    printf '%s\n' "$logs" >&2
    die "the dock step failed — see workbench logs above"
  fi
  if printf '%s\n' "$logs" | grep -q "dock: all harnesses wired"; then
    break
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    printf '%s\n' "$logs" >&2
    die "workbench did not reach 'dock: all harnesses wired' within 300s"
  fi
  sleep 2
done
echo "dock-e2e: dock step wired every harness adapter"

# ── 3. Probe battery (issue #10) inside the scratch workbench ───────────────
# The same probes the dogfooded workbench runs (make probe-dock), here against
# a host project that was never dogfooded: Claude-adapter skill expansion,
# the dock alias, pi model-list + deterministic skill expansion, the seeded
# pi config, and the second-dock-run no-op (pin satisfied, state in sync).
( cd "$SCRATCH" && docker compose exec -T workbench \
  bash "$BASE_DIR/.devcontainer/scripts/probe-dock.sh" )

# ── 4. Pin fidelity: the vendored set sits at the pinned ref ────────────────
LOCK="$BASE_DIR/.devcontainer/skills.lock"
pin="$(sed -n 's/^mattpocock-skills[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$LOCK" | head -n1)"
[ -n "$pin" ] || die "no mattpocock-skills pin in skills.lock"
REPO="$BASE_DIR/.agents/skills/mattpocock-skills"
[ -d "$REPO/.git" ] || die "vendored set not fetched: $REPO missing"
# safe.directory: the clone may be owned by the container user (uid 1000) if
# the dock step fetched it.
git_vendored() { git -c safe.directory="$REPO" -C "$REPO" "$@"; }
want="$(git_vendored rev-parse -q --verify "$pin^{commit}")"
have="$(git_vendored rev-parse HEAD)"
[ "$want" = "$have" ] || die "vendored set at $have — pin is $pin ($want)"
echo "dock-e2e: vendored set at the pinned ref ($pin)"

# ── 5. Dirty-base warning: dirtying the base mount makes the dock warn ──────
touch "$MARKER"
out="$( ( cd "$SCRATCH" && docker compose exec -T workbench \
  bash "$BASE_DIR/.devcontainer/scripts/dock.sh" ) 2>&1 )"
rm -f "$MARKER"
printf '%s\n' "$out" | grep -q "WARNING — dirty base" \
  || { printf '%s\n' "$out" >&2; die "dirty-base warning did not fire (base mount was dirtied)"; }
echo "dock-e2e: dirty-base warning fires when the mount is dirtied"

echo "== dock E2E: all probes passed (scratch project torn down, no residue) =="
