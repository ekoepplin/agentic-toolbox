#!/bin/bash
# Stamp an issue's plan with the ralph:plan marker (base sha + plan hash) —
# the step refine (#31) ends with, and how a hand-written plan becomes
# runnable. Replaces any earlier marker; the format is documented in lib.sh.
#
#   usage: plan-stamp.sh <issue-number>
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ISSUE="${1:-}"
[[ -n "$ISSUE" ]] || { echo "usage: $0 <issue-number>" >&2; exit 2; }

body="$(ralph_issue_body "$ISSUE")"
# Command substitution also drops trailing blank lines, so re-stamping never
# grows the body.
clean="$(printf '%s\n' "$body" | grep -v '^<!-- ralph:plan ' || true)"
if ! problem="$(ralph_plan_problem "$clean" unstamped)"; then
  echo "plan-stamp: issue #$ISSUE: $problem — nothing stamped." >&2
  exit 2
fi

"$RALPH_ROOT/.devcontainer/as-bot.sh" git -C "$RALPH_ROOT" fetch -q origin master
base="$(git -C "$RALPH_ROOT" rev-parse origin/master)"
hash="$(ralph_plan_hash "$clean")"
printf '%s\n\n<!-- ralph:plan base=%s hash=%s -->\n' "$clean" "$base" "$hash" \
  | ralph_gh issue edit "$ISSUE" --repo "$REPO" --body-file - >/dev/null

if ! problem="$(ralph_plan_problem "$(ralph_issue_body "$ISSUE")")"; then
  echo "plan-stamp: issue #$ISSUE: stamped, but the re-read plan fails: $problem" >&2
  exit 1
fi
echo "plan-stamp: #$ISSUE stamped (base ${base:0:7}, hash ${hash:0:12})"
