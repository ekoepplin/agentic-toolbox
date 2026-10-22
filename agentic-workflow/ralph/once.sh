#!/bin/bash
# One ralph iteration on one issue, driven by Claude Code. See lib.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat >&2 <<EOF2
Usage: $0 <issue-number> [--backend NAME] [--model NAME]

  --backend  one of: anthropic | vllm | ollama
             default: \$RALPH_BACKEND, else 'vllm'
  --model    model name for the chosen backend
             default: \$RALPH_MODEL, else backend default
               anthropic -> sonnet
               vllm      -> \$VLLM_DEFAULT_MODEL
               ollama    -> \$OLLAMA_DEFAULT_MODEL
EOF2
  exit 1
}

ralph_parse_once "$@"

case "$BACKEND" in
  anthropic)
    unset ANTHROPIC_AUTH_TOKEN ANTHROPIC_BASE_URL
    : "${MODEL:=sonnet}"
    ;;
  vllm)
    export ANTHROPIC_AUTH_TOKEN=vllm
    export ANTHROPIC_BASE_URL=http://host.docker.internal:8000
    : "${MODEL:=${VLLM_DEFAULT_MODEL:-qwen}}"
    ;;
  ollama)
    export ANTHROPIC_AUTH_TOKEN=ollama
    export ANTHROPIC_BASE_URL=http://host.docker.internal:11434
    : "${MODEL:=${OLLAMA_DEFAULT_MODEL:-qwen3.5:4b}}"
    ;;
  *) ralph_bad_backend ;;
esac

echo "ralph: backend=$BACKEND model=$MODEL issue=#$ISSUE" >&2

mission=$(ralph_mission "$ISSUE" "$RALPH_DIR/prompt.md")

# settings.ralph.json is the permission allow-list that keeps an AFK loop from
# stalling on prompts; passed only if present.
settings_flag=()
[[ -f "$RALPH_DIR/settings.ralph.json" ]] && settings_flag=(--settings "$RALPH_DIR/settings.ralph.json")

# as-bot: commit/push/gh as the bot account when BOT_GIT_USER is set.
"$RALPH_ROOT/.devcontainer/as-bot.sh" claude ${settings_flag[@]+"${settings_flag[@]}"} \
  --permission-mode acceptEdits --model "$MODEL" "$mission"
