#!/usr/bin/env bash
# External skills installer — called by the dock step (dock.sh) on every
# workbench start, and by scripts/bootstrap-dev.sh after a fresh clone.
#
# Skill repos are PINNED. The pinned ref (commit SHA or tag) for each repo lives
# in .devcontainer/skills.lock, so a devcontainer rebuild always reproduces the
# same skill set. Bump pins via the /update-project skill — it also reconciles
# agentic-workflow/* against any renamed or removed skills.
#
# To add a skill:
#   1. Add a line to .devcontainer/skills.lock:  <name> = <sha-or-tag>
#   2. clone_at_ref <name> <github-url> "$(pin_for <name>)"
#   3a. Single-skill repo:  ln -sfn "$AGENTS_DIR/<name>" "$CLAUDE_SKILLS_DIR/<name>"
#   3b. Multi-skill repo:   loop over subdirs (see mattpocock example below)
set -euo pipefail

WORKSPACE="$(cd "$(dirname "$0")/../.." && pwd)"
AGENTS_DIR="$WORKSPACE/.agents/skills"
CLAUDE_SKILLS_DIR="$WORKSPACE/.claude/skills"
LOCKFILE="$WORKSPACE/.devcontainer/skills.lock"

mkdir -p "$AGENTS_DIR" "$CLAUDE_SKILLS_DIR"

# Resolve the pinned ref for a repo from the lockfile. Falls back to 'main' (with
# a warning) so a missing/incomplete lockfile degrades gracefully rather than
# hard-failing container creation.
pin_for() {
  local name="$1" ref=""
  if [ -f "$LOCKFILE" ]; then
    ref="$(sed -n "s/^[[:space:]]*${name}[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p" "$LOCKFILE" | head -n1)"
  fi
  if [ -z "$ref" ]; then
    echo "  ! no pin for '$name' in ${LOCKFILE#"$WORKSPACE"/} — falling back to 'main'" >&2
    ref="main"
  fi
  printf '%s' "$ref"
}

# Clone (if needed) and check out an exact pinned ref. Full clone (not shallow)
# so any historical SHA or tag is checkoutable, and never `git pull` — the pin,
# not upstream HEAD, decides what is installed.
#
# Pin-aware: when the clone exists and its HEAD already is the pinned ref, no
# network traffic happens at all (the ref resolves locally — pins are commit
# SHAs or tags, per the skills.lock format). Fetch + re-checkout only when the
# clone is missing or the pin changed.
# safe.directory: the repo may be owned by a different uid than the caller
# (base mounted across the container/host boundary).
git_repo() { git -c safe.directory="$AGENTS_DIR/$1" -C "$AGENTS_DIR/$1" "${@:2}"; }
clone_at_ref() {
  local name="$1" url="$2" ref="$3"
  local dir="$AGENTS_DIR/$name"
  if [ ! -d "$dir/.git" ]; then
    echo "  ↓ $name (cloning)"
    git clone --quiet "$url" "$dir"
  else
    local want have
    want="$(git_repo "$name" rev-parse -q --verify "$ref^{commit}" 2>/dev/null || true)"
    have="$(git_repo "$name" rev-parse HEAD 2>/dev/null || true)"
    if [ -n "$want" ] && [ "$want" = "$have" ]; then
      echo "  ✓ $name (pin $ref satisfied — no fetch)"
      return 0
    fi
    echo "  ↻ $name (fetching — pin $ref not satisfied)"
    git_repo "$name" fetch --quiet --tags --force origin
    if ! git_repo "$name" rev-parse -q --verify "$ref^{commit}" >/dev/null 2>&1; then
      echo "  ! pin '$ref' not resolvable in $name after fetch" >&2
    fi
  fi
  echo "  ⇲ $name → $ref"
  git_repo "$name" -c advice.detachedHead=false checkout --quiet "$ref"
}

# Remove symlinks whose target no longer exists — i.e. skills renamed or dropped
# upstream since the last run. Live symlinks are recreated by the loop below.
prune_dangling_symlinks() {
  local l
  for l in "$CLAUDE_SKILLS_DIR"/*; do
    if [ -L "$l" ] && [ ! -e "$l" ]; then
      echo "  ✗ $(basename "$l") (gone upstream)"
      rm -f "$l"
    fi
  done
}

# ── mattpocock/skills ────────────────────────────────────────────────────────
# Skills live two levels deep: skills/<category>/<skill-name>/SKILL.md
# Skip skills/deprecated/<name> — those are skills Matt no longer uses.
clone_at_ref mattpocock-skills https://github.com/mattpocock/skills "$(pin_for mattpocock-skills)"

prune_dangling_symlinks

for dir in "$AGENTS_DIR/mattpocock-skills/skills"/*/*/; do
  [ -f "${dir}SKILL.md" ] || continue
  [ "$(basename "$(dirname "$dir")")" = "deprecated" ] && continue
  skill_name="$(basename "$dir")"
  link="$CLAUDE_SKILLS_DIR/$skill_name"
  # No-op when the symlink already points at this target (second run).
  [ -L "$link" ] && [ "$(readlink "$link")" = "$dir" ] && continue
  ln -sfn "$dir" "$link"
  echo "  ✓ $skill_name"
done

echo "Skills ready → $CLAUDE_SKILLS_DIR"
