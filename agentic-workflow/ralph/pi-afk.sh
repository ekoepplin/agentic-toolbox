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

usage() {
  echo "Usage: $0 <issue-number> [max-iters] [--backend NAME] [--model NAME]" >&2
  exit 2
}

ISSUE="${1:-}"
[[ -n "$ISSUE" ]] || usage
shift
MAX=10
if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
  MAX="$1"
  shift
fi
# Validate the flags forwarded to pi-once.sh once, before any iteration: a
# bad flag must stop the loop, not burn every iteration on a usage error.
ralph_parse_once "$ISSUE" "$@"
case "$BACKEND" in
  anthropic | vllm | ollama) ;;
  *) echo "error: --backend must be one of: anthropic, vllm, ollama (got '$BACKEND')" >&2; usage ;;
esac

ralph_require_plan "$ISSUE"
ralph_require_bot

BRANCH="ralph/issue-$ISSUE"
WT="${RALPH_WORKTREES:-$HOME/.cache/ralph}/issue-$ISSUE"
STATE="$WT.state"
mkdir -p "$STATE"
# Snapshot of the stamped plan: Verify and the scope gate run from it, and the
# run stops if the live plan changes underneath it (even when re-stamped).
PLAN_HASH="$(ralph_plan_hash "$PLAN_BODY")"
printf '%s\n' "$PLAN_BODY" > "$STATE/plan.md"
AS_BOT="$RALPH_ROOT/.devcontainer/as-bot.sh"

# Through as-bot: inside a workbench plain git has no GitHub credentials.
"$AS_BOT" git -C "$RALPH_ROOT" fetch -q origin master
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
  rc=0
  (cd "$WT" && RALPH_FEEDBACK="$STATE/feedback.md" "$RALPH_DIR/pi-once.sh" "$ISSUE" "$@") || rc=$?
  # 2 = pi-once refused (plan, bot identity): nothing ran, so stop here.
  [[ $rc -ne 2 ]] || exit 2
  [[ $rc -eq 0 ]] || echo "ralph-pi: pi exited $rc; verifying anyway" >&2

  if [[ "$(ralph_plan_hash "$(ralph_issue_body "$ISSUE")")" != "$PLAN_HASH" ]]; then
    echo "ralph-pi: the plan in #$ISSUE changed during the run — stopping; re-refine and restart" >&2
    exit 2
  fi
  green=1
  ralph_verify "$PLAN_BODY" "$BRANCH" "$STATE/verify.log" || green=0
  ralph_scope_gate "$PLAN_BODY" "$BRANCH" "$STATE/verify.log" || green=0
  if [[ $green -eq 1 ]]; then
    echo "ralph-pi: Verify + scope gate green after iter $i" >&2
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

  echo "ralph-pi: Verify or scope gate red after iter $i" >&2
  {
    printf 'The loop ran the Verify commands and the scope gate on your last commit (%s); they failed.\n' \
      "$(git -C "$RALPH_ROOT" rev-parse --short "$BRANCH")"
    printf 'Fix the cause, commit again, touch only the planned files, and do not change the Verify commands.\n\n```\n%s\n```\n' \
      "$(tail -c 6000 "$STATE/verify.log")"
  } > "$STATE/feedback.md"
done

echo "ralph-pi: hit MAX=$MAX iters on #$ISSUE with Verify or scope red — see $STATE/verify.log" >&2
exit 1
