#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source environment
if [[ -f .env.ralph ]]; then
  set -a
  source .env.ralph
  set +a
fi

usage() {
  cat >&2 <<EOF
Usage: $0 <issue-number> [--backend NAME] [--model NAME]

  --backend  one of: anthropic | vllm | ollama
             default: \$RALPH_BACKEND, else 'vllm'
  --model    model id for the chosen backend
             default: \$RALPH_MODEL, else backend default

Backend -> pi provider (see ~/.pi/agent/models.json):
  vllm      -> vllm-hpzgx
  ollama    -> ollama-local
  anthropic -> built-in anthropic provider (model required)
EOF
  exit 1
}

ISSUE="${1:-}"
[[ -z "$ISSUE" ]] && usage
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

# Map backend -> pi model pattern (provider/id)
case "$BACKEND" in
  vllm)
    : "${MODEL:=${VLLM_DEFAULT_MODEL:-qwen}}"
    MODEL_PATTERN="vllm-hpzgx/$MODEL"
    ;;
  ollama)
    : "${MODEL:=${OLLAMA_DEFAULT_MODEL:-qwen3.5:4b}}"
    MODEL_PATTERN="ollama-local/$MODEL"
    ;;
  anthropic)
    # pi's catalog ids are not Claude Code's sonnet/opus shorthands — check `pi --list-models`
    [[ -n "$MODEL" ]] || { echo "error: anthropic backend needs --model (see 'pi --list-models')" >&2; exit 1; }
    MODEL_PATTERN="anthropic/$MODEL"
    ;;
  *)
    echo "error: --backend must be one of: anthropic, vllm, ollama (got '$BACKEND')" >&2
    exit 1
    ;;
esac

REPO="ekoepplin/agentic-toolbox"

echo "ralph-pi: backend=$BACKEND model=$MODEL_PATTERN issue=#$ISSUE" >&2

issue=$(gh issue view "$ISSUE" --repo "$REPO" \
  --json number,title,body,labels,state \
  --jq '"# Issue #\(.number): \(.title)\nState: \(.state)\nLabels: \(.labels | map(.name) | join(", "))\n\n\(.body)"')
commits=$(git log -n 5 --format='%h %ad %s' --date=short)
prompt=$(cat "$SCRIPT_DIR/prompt-pi.md")

pi -a -p --model "$MODEL_PATTERN" --name "ralph #$ISSUE" \
  "MISSION: deliver issue #$ISSUE. Do NOT switch to other issues even if you see references to them.

$issue

Recent commits:
$commits

$prompt"
