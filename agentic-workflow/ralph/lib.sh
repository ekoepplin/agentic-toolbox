# shellcheck shell=bash
# Shared plumbing for the ralph loop scripts — sourced, not executed.
#
#   once.sh / pi-once.sh   one iteration on one issue (Claude Code / pi)
#   afk.sh                 loop once.sh until the issue closes
#   pi-afk.sh              loop pi-once.sh until the harness-run Verify is
#                          green, then push + open a PR (never merge)
#
# Stays bash 3.2-compatible, so the loop also runs on a bare Mac.

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_ROOT="$(cd "$RALPH_DIR/../.." && pwd)"
REPO="ekoepplin/agentic-toolbox"

# An AFK loop must never wait on a credential prompt: missing credentials fail.
export GIT_TERMINAL_PROMPT=0

# ralph_gh <args...> — gh with the bot's credentials when BOT_GIT_USER is set
# (inside a workbench plain gh is not logged in); plain gh otherwise.
ralph_gh() { "$RALPH_ROOT/.devcontainer/as-bot.sh" gh "$@"; }

# .env.ralph at the repo root sets RALPH_BACKEND / RALPH_MODEL defaults.
if [[ -f "$RALPH_ROOT/.env.ralph" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$RALPH_ROOT/.env.ralph"
  set +a
fi

# ralph_parse_once <args...> — sets ISSUE, BACKEND, MODEL (flag > .env.ralph >
# built-in default). Calls the sourcing script's usage() on bad input.
# shellcheck disable=SC2034  # ISSUE/BACKEND/MODEL are read by the caller
ralph_parse_once() {
  ISSUE="${1:-}"
  [[ -n "$ISSUE" ]] || usage
  shift
  BACKEND="${RALPH_BACKEND:-vllm}"
  MODEL="${RALPH_MODEL:-}"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --backend | --model)
        [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || { echo "error: $1 needs a value" >&2; usage; }
        if [[ "$1" == --backend ]]; then BACKEND="$2"; else MODEL="$2"; fi
        shift 2 ;;
      -h|--help) usage ;;
      *) echo "error: unknown arg: $1" >&2; usage ;;
    esac
  done
}

ralph_bad_backend() {
  echo "error: --backend must be one of: anthropic, vllm, ollama (got '$BACKEND')" >&2
  exit 1
}

# ralph_mission <issue> <prompt-file> — the full prompt for one iteration:
# mission line, issue body, recent commits, then the loop prompt.
ralph_mission() {
  local issue commits
  issue=$(ralph_gh issue view "$1" --repo "$REPO" \
    --json number,title,body,labels,state \
    --jq '"# Issue #\(.number): \(.title)\nState: \(.state)\nLabels: \(.labels | map(.name) | join(", "))\n\n\(.body)"') \
    || return 1
  commits=$(git log -n 5 --format='%h %ad %s' --date=short) || return 1
  printf 'MISSION: deliver issue #%s. Do NOT switch to other issues even if you see references to them.\n\n%s\n\nRecent commits:\n%s\n\n%s' \
    "$1" "$issue" "$commits" "$(cat "$2")"
}

# ── Execution contract (pi loop) ────────────────────────────────────────────
# An issue qwen may run carries, in its body, an `## Execution plan` section
# and a `## Verify` section whose first fenced block lists one shell command
# per line; every command must exit 0. The loop runs them itself — qwen's own
# claim of done is never trusted. See docs/harnesses/pi-agent-harness/ralph-on-pi.md.

# ralph_issue_body <issue> — the issue body, CRLF-normalised.
ralph_issue_body() {
  ralph_gh issue view "$1" --repo "$REPO" --json body --jq .body | tr -d '\r'
}

# ralph_verify_cmds <body> — the commands in the first fenced block under
# `## Verify`, one per line; blank lines and `#` comments are dropped.
ralph_verify_cmds() {
  printf '%s\n' "$1" | awk '
    /^## / { in_verify = ($0 ~ /^## Verify[[:space:]]*$/); next }
    in_verify && /^```/ { if (fence) exit; fence = 1; next }
    fence && $0 !~ /^[[:space:]]*(#|$)/ { print }
  '
}

# ralph_require_plan <issue> — exits 2 unless the issue carries the contract.
ralph_require_plan() {
  local body
  body="$(ralph_issue_body "$1")" || { echo "error: cannot read issue #$1" >&2; exit 2; }
  if ! printf '%s\n' "$body" | grep -q '^## Execution plan[[:space:]]*$' \
    || [[ -z "$(ralph_verify_cmds "$body")" ]]; then
    echo "ralph: issue #$1 has no execution plan ('## Execution plan' + a '## Verify' block) — refusing to run qwen; refine it first." >&2
    exit 2
  fi
}

# ralph_require_bot — exits 2 unless as-bot resolves to a bot identity whose
# token logs in as that same account. Without it qwen would commit, push and
# open PRs with the caller's own credentials — on the Mac that is the admin,
# who may bypass the master ruleset.
ralph_require_bot() {
  local user login
  user="$("$RALPH_ROOT/.devcontainer/as-bot.sh" sh -c 'printf %s "${GIT_AUTHOR_NAME:-}"')"
  if [[ -z "$user" ]]; then
    echo "ralph: no bot identity (BOT_GIT_USER/BOT_GH_TOKEN unset, no ~/.config/as-bot.env) — refusing to run qwen with your own credentials; run it in a workbench docked with BOT_* set." >&2
    exit 2
  fi
  login="$(ralph_gh api user --jq .login 2>/dev/null || true)"
  if [[ "$login" != "$user" ]]; then
    echo "ralph: bot token logs in as '${login:-nothing}', not '$user' — refusing to run qwen." >&2
    exit 2
  fi
}

# ralph_verify <issue> <ref> <log> — runs the issue's Verify commands in a
# clean, detached worktree at <ref>, so only committed work can turn them
# green. Appends each command and its output to <log>; returns 1 if any fails.
ralph_verify() {
  local cmds wt cmd rc=0
  cmds="$(ralph_verify_cmds "$(ralph_issue_body "$1")")"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/ralph-verify.XXXXXX")"
  git -C "$RALPH_ROOT" worktree add -q --detach "$wt" "$2" || { rm -rf "$wt"; return 2; }
  : > "$3"
  while IFS= read -r cmd; do
    printf '$ %s\n' "$cmd" >> "$3"
    if (cd "$wt" && bash -c "$cmd" < /dev/null) >> "$3" 2>&1; then
      printf '[ok]\n' >> "$3"
    else
      printf '[FAILED: exit %s]\n' "$?" >> "$3"
      rc=1
    fi
  done <<EOF
$cmds
EOF
  git -C "$RALPH_ROOT" worktree remove --force "$wt"
  return "$rc"
}

# ralph_afk <iteration-script> <issue> [max-iters] [flags...] — runs the
# iteration script until the issue is CLOSED or max-iters (default 10) is hit.
ralph_afk() {
  local once="$1"; shift
  local issue="${1:-}"
  if [[ -z "$issue" ]]; then
    cat >&2 <<EOF
Usage: $0 <issue-number> [max-iters] [--backend NAME] [--model NAME]

  max-iters  default: 10
  --backend  one of: anthropic | vllm | ollama (forwarded to $once)
  --model    model name for the chosen backend (forwarded to $once)
EOF
    exit 1
  fi
  shift
  local max=10 i state
  if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
    max="$1"
    shift
  fi
  for ((i = 1; i <= max; i++)); do
    state=$(ralph_gh issue view "$issue" --repo "$REPO" --json state --jq '.state' 2>/dev/null || echo UNKNOWN)
    if [[ "$state" == "CLOSED" ]]; then
      echo "Issue #$issue is CLOSED — done in $((i - 1)) iters."
      exit 0
    fi
    echo "=== iter $i/$max on #$issue (state=$state) ==="
    "$RALPH_DIR/$once" "$issue" "$@"
    echo "=== iter $i complete ==="
  done
  echo "Hit MAX=$max iters on #$issue without closing. Inspect and resume manually."
  exit 1
}
