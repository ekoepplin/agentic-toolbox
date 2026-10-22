# shellcheck shell=bash
# Shared plumbing for the ralph loop scripts — sourced, not executed.
#
#   once.sh / pi-once.sh   one iteration on one issue (Claude Code / pi)
#   afk.sh  / pi-afk.sh    loop an iteration script until the issue closes
#
# Stays bash 3.2-compatible, so the loop also runs on a bare Mac.

RALPH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_ROOT="$(cd "$RALPH_DIR/../.." && pwd)"
REPO="ekoepplin/agentic-toolbox"

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
      --backend) BACKEND="${2:?--backend needs a value}"; shift 2 ;;
      --model)   MODEL="${2:?--model needs a value}";     shift 2 ;;
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
  issue=$(gh issue view "$1" --repo "$REPO" \
    --json number,title,body,labels,state \
    --jq '"# Issue #\(.number): \(.title)\nState: \(.state)\nLabels: \(.labels | map(.name) | join(", "))\n\n\(.body)"') \
    || return 1
  commits=$(git log -n 5 --format='%h %ad %s' --date=short) || return 1
  printf 'MISSION: deliver issue #%s. Do NOT switch to other issues even if you see references to them.\n\n%s\n\nRecent commits:\n%s\n\n%s' \
    "$1" "$issue" "$commits" "$(cat "$2")"
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
    state=$(gh issue view "$issue" --repo "$REPO" --json state --jq '.state' 2>/dev/null || echo UNKNOWN)
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
