#!/usr/bin/env bash
# Plugin drift guard.
#
# Enforces the consistency invariant that keeps the plugin coherent (see
# CLAUDE.md and ADR-0002): every shipped skill appears in both
# .claude-plugin/plugin.json and the README, and nothing listed is missing on
# disk. Draft skills under skills/in-progress/ must NOT appear in plugin.json.
#
# Exits non-zero on any mismatch.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

PLUGIN_JSON=".claude-plugin/plugin.json"
README="README.md"

fail=0
err() { printf 'DRIFT: %s\n' "$1" >&2; fail=1; }

# Skills registered in plugin.json (basename of each "./skills/<name>" entry).
mapfile -t listed < <(python3 -c '
import json
d = json.load(open(".claude-plugin/plugin.json"))
for s in d.get("skills", []):
    print(s.rstrip("/").split("/")[-1])
')

# Skills shipped on disk: directories under skills/ (excluding the in-progress
# staging area) that carry a SKILL.md.
mapfile -t shipped < <(
  for d in skills/*/; do
    name="$(basename "$d")"
    [ "$name" = "in-progress" ] && continue
    [ -f "$d/SKILL.md" ] || continue
    echo "$name"
  done
)

# Draft skills staged under skills/in-progress/.
mapfile -t drafts < <(
  for d in skills/in-progress/*/; do
    [ -d "$d" ] || continue
    basename "$d"
  done
)

contains() {
  local needle="$1"; shift
  local x
  for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
  return 1
}

# 1. Every shipped skill on disk must be registered in plugin.json.
for s in ${shipped[@]+"${shipped[@]}"}; do
  contains "$s" ${listed[@]+"${listed[@]}"} \
    || err "skill 'skills/$s' ships on disk but is not listed in $PLUGIN_JSON"
done

# 2. Every plugin.json entry must have a directory on disk.
for l in ${listed[@]+"${listed[@]}"}; do
  [ -d "skills/$l" ] \
    || err "$PLUGIN_JSON lists '$l' but skills/$l does not exist on disk"
done

# 3. Every shipped skill must appear in the README.
for s in ${shipped[@]+"${shipped[@]}"}; do
  grep -q -- "$s" "$README" \
    || err "skill '$s' ships on disk but is absent from $README"
done

# 4. No skills/in-progress/ draft may be listed in plugin.json.
for d in ${drafts[@]+"${drafts[@]}"}; do
  contains "$d" ${listed[@]+"${listed[@]}"} \
    && err "draft 'skills/in-progress/$d' must not be listed in $PLUGIN_JSON"
done

if [ "$fail" -ne 0 ]; then
  echo "check.sh: plugin drift detected." >&2
  exit 1
fi
echo "check.sh: plugin.json <-> disk <-> README in sync."
