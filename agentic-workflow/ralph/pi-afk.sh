#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source environment
if [[ -f .env.ralph ]]; then
  set -a
  source .env.ralph
  set +a
fi

usage() {
  cat >&2 <<EOF
Usage: $0 <issue-number> [max-iters] [--backend NAME] [--model NAME]

  max-iters  default: 10
  --backend  one of: anthropic | vllm | ollama (forwarded to pi-once.sh)
  --model    model name for the chosen backend (forwarded to pi-once.sh)
EOF
  exit 1
}

ISSUE="${1:-}"
[[ -z "$ISSUE" ]] && usage
shift

MAX=10
if [[ $# -gt 0 && "$1" =~ ^[0-9]+$ ]]; then
  MAX="$1"
  shift
fi

REPO="ekoepplin/agentic-toolbox"

for ((i=1; i<=MAX; i++)); do
  state=$(gh issue view "$ISSUE" --repo "$REPO" --json state --jq '.state' 2>/dev/null || echo UNKNOWN)
  if [[ "$state" == "CLOSED" ]]; then
    echo "Issue #$ISSUE is CLOSED — done in $((i-1)) iters."
    exit 0
  fi
  echo "=== iter $i/$MAX on #$ISSUE (state=$state) ==="
  "$SCRIPT_DIR/pi-once.sh" "$ISSUE" "$@"
  echo "=== iter $i complete ==="
done

echo "Hit MAX=$MAX iters on #$ISSUE without closing. Inspect and resume manually."
exit 1
