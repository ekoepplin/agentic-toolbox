#!/usr/bin/env bash
# Local-dev bootstrap: reconstruct a working dev environment after a fresh clone.
#
# Fetches the vendored skill set (mattpocock/skills, pinned in
# .devcontainer/skills.lock) into .agents/skills/ and symlinks each skill into
# this repo's .claude/skills/ so they're invocable in this repo's Claude
# sessions. Both directories are git-ignored (see docs/adr/0001).
#
# This is a development aid only — the vendored skills are never part of the
# shipped plugin. Run it once after cloning; re-run to pick up pin bumps.
#
# Idempotent: safe to run repeatedly.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# The pinned fetch + symlink logic already lives in the devcontainer installer;
# reuse it rather than duplicate the traversal so there's a single source of truth.
bash "$REPO/.devcontainer/scripts/install-skills.sh"
