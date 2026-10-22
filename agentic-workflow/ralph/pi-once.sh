#!/bin/bash
# One ralph iteration on one issue, driven by pi. See lib.sh and
# docs/harnesses/pi-agent-harness/ralph-on-pi.md.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat >&2 <<EOF2
Usage: $0 <issue-number> [--backend NAME] [--model NAME]

  --backend  one of: anthropic | vllm | ollama
             default: \$RALPH_BACKEND, else 'vllm'
  --model    model id for the chosen backend
             default: \$RALPH_MODEL, else backend default

Backend -> pi provider (see ~/.pi/agent/models.json):
  vllm      -> vllm-hpzgx
  ollama    -> ollama-local
  anthropic -> built-in anthropic provider (model required)
EOF2
  exit 1
}

ralph_parse_once "$@"

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
  *) ralph_bad_backend ;;
esac

echo "ralph-pi: backend=$BACKEND model=$MODEL_PATTERN issue=#$ISSUE" >&2

mission=$(ralph_mission "$ISSUE" "$RALPH_DIR/prompt-pi.md")

# as-bot: commit/push/gh as the bot account when BOT_GIT_USER is set.
"$RALPH_ROOT/.devcontainer/as-bot.sh" pi -a -p --model "$MODEL_PATTERN" --name "ralph #$ISSUE" "$mission"
