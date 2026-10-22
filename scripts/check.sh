#!/usr/bin/env bash
# Adapter-manifest drift guard.
#
# Enforces the adapter-manifest contract (see CLAUDE.md): every shipped skill
# appears in the Claude Code harness adapter's manifest
# (.claude-plugin/plugin.json), and nothing listed is missing on disk. Draft
# skills under skills/in-progress/ must NOT appear in the manifest.
#
# Portable to macOS's stock bash 3.2 (no mapfile), so it runs on a bare Mac
# as well as in the workbench. Exits non-zero on any mismatch.
set -euo pipefail

cd "$(dirname "$0")/.."

PLUGIN_JSON=".claude-plugin/plugin.json"

fail=0
err() { printf 'DRIFT: %s\n' "$1" >&2; fail=1; }

# Newline-separated name lists; `has <list> <name>` tests membership.
has() { printf '%s\n' "$1" | grep -qxF -- "$2"; }

# Skills registered in plugin.json (basename of each "./skills/<name>" entry).
listed="$(python3 -c '
import json, sys
for s in json.load(open(sys.argv[1])).get("skills", []):
    print(s.rstrip("/").split("/")[-1])
' "$PLUGIN_JSON")" || { echo "check.sh: cannot read $PLUGIN_JSON" >&2; exit 1; }

# Skills shipped on disk: directories under skills/ (excluding the in-progress
# staging area) that carry a SKILL.md.
shipped=""
for d in skills/*/; do
  name="$(basename "$d")"
  [ "$name" != "in-progress" ] && [ -f "$d/SKILL.md" ] && shipped="$shipped$name"$'\n'
done

# Draft skills staged under skills/in-progress/.
drafts=""
for d in skills/in-progress/*/; do
  [ -d "$d" ] && drafts="$drafts$(basename "$d")"$'\n'
done

# 1. Every shipped skill on disk must be registered in plugin.json.
while IFS= read -r s; do
  [ -n "$s" ] || continue
  has "$listed" "$s" \
    || err "skill 'skills/$s' ships on disk but is not listed in $PLUGIN_JSON"
done <<< "$shipped"

# 2. Every plugin.json entry must have a directory on disk.
while IFS= read -r l; do
  [ -n "$l" ] || continue
  [ -d "skills/$l" ] \
    || err "$PLUGIN_JSON lists '$l' but skills/$l does not exist on disk"
done <<< "$listed"

# 3. No skills/in-progress/ draft may be listed in plugin.json.
while IFS= read -r d; do
  [ -n "$d" ] || continue
  ! has "$listed" "$d" \
    || err "draft 'skills/in-progress/$d' must not be listed in $PLUGIN_JSON"
done <<< "$drafts"

if [ "$fail" -ne 0 ]; then
  echo "check.sh: adapter-manifest drift detected." >&2
  exit 1
fi
echo "check.sh: adapter manifest <-> disk in sync."
