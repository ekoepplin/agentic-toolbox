#!/bin/bash
# AFK loop (pi): qwen implements one refined issue in its own worktree on
# branch ralph/issue-<N>, cut from origin/master. After every iteration the
# loop itself runs the issue's Verify commands in a clean worktree at the
# branch head; red feeds the output into the next iteration, green makes the
# loop push the branch and open a PR as the bot. It never merges: the master
# ruleset requires an approval from someone other than the pusher.
#
# Exit: 0 green + PR open · 1 max iterations · 2 refused (no plan, bad args)
#       3 green without any commit (the plan's checks don't fail on base)
#
# See lib.sh and docs/harnesses/pi-agent-harness/ralph-on-pi.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ISSUE="${1:-}"
if [[ -z "$ISSUE" ]]; then
  echo "Usage: $0 <issue-number> [max-iters] [--backend NAME] [--model NAME]" >&2
  exit 2
fi
shift
MAX=10
if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
  MAX="$1"
  shift
fi

ralph_require_plan "$ISSUE"
ralph_require_bot

BRANCH="ralph/issue-$ISSUE"
WT="${RALPH_WORKTREES:-$HOME/.cache/ralph}/issue-$ISSUE"
STATE="$WT.state"
mkdir -p "$STATE"
AS_BOT="$RALPH_ROOT/.devcontainer/as-bot.sh"

git -C "$RALPH_ROOT" fetch -q origin master
if [[ ! -d "$WT" ]]; then
  if git -C "$RALPH_ROOT" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null; then
    git -C "$RALPH_ROOT" worktree add -q "$WT" "$BRANCH"
  else
    git -C "$RALPH_ROOT" worktree add -q -b "$BRANCH" "$WT" origin/master
  fi
fi
echo "ralph-pi: issue #$ISSUE on $BRANCH in $WT (max $MAX iters)" >&2

rm -f "$STATE/feedback.md"
for ((i = 1; i <= MAX; i++)); do
  echo "=== iter $i/$MAX on #$ISSUE ===" >&2
  (cd "$WT" && RALPH_FEEDBACK="$STATE/feedback.md" "$RALPH_DIR/pi-once.sh" "$ISSUE" "$@") \
    || echo "ralph-pi: pi exited non-zero; verifying anyway" >&2

  if ralph_verify "$ISSUE" "$BRANCH" "$STATE/verify.log"; then
    echo "ralph-pi: Verify green after iter $i" >&2
    if [[ "$(git -C "$RALPH_ROOT" rev-list --count "origin/master..$BRANCH")" -eq 0 ]]; then
      echo "ralph-pi: green without any commit — the plan's Verify does not fail on base; re-refine #$ISSUE" >&2
      exit 3
    fi
    "$AS_BOT" git -C "$WT" push -q -u origin "$BRANCH"
    pr="$(ralph_gh pr list --repo "$REPO" --head "$BRANCH" --state open --json url --jq '.[0].url // empty')"
    if [[ -z "$pr" ]]; then
      title="$(ralph_gh issue view "$ISSUE" --repo "$REPO" --json title --jq .title)"
      body="$(printf 'Closes #%s\n\nImplemented by the pi loop (qwen). Verify run by the harness on %s:\n\n```\n%s\n```\n' \
        "$ISSUE" "$(git -C "$RALPH_ROOT" rev-parse --short "$BRANCH")" "$(tail -c 6000 "$STATE/verify.log")")"
      pr="$(ralph_gh pr create --repo "$REPO" --base master --head "$BRANCH" --title "$title" --body "$body")"
    fi
    echo "ralph-pi: PR $pr — awaiting review (the loop never merges)" >&2
    echo "$pr"
    exit 0
  fi

  echo "ralph-pi: Verify red after iter $i" >&2
  {
    printf 'The loop ran the Verify commands on your last commit (%s); they failed.\n' \
      "$(git -C "$RALPH_ROOT" rev-parse --short "$BRANCH")"
    printf 'Fix the cause, commit again, and do not change the Verify commands.\n\n```\n%s\n```\n' \
      "$(tail -c 6000 "$STATE/verify.log")"
  } > "$STATE/feedback.md"
done

echo "ralph-pi: hit MAX=$MAX iters on #$ISSUE with Verify red — see $STATE/verify.log" >&2
exit 1
