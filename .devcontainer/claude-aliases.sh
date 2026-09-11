# ----------------------------------------------------------------------------
# Git Aliases
# ----------------------------------------------------------------------------
alias gs='git status'
alias gst='git status -sb'
alias ga='git add'
alias gaa='git add .'
alias gau='git add -u'
alias gp='git pull'
alias gf='git fetch'
alias gpu='git push'
alias gcm='git commit -m'
alias gco='git checkout'
alias gcob='git checkout -b'
alias gl='git log --oneline'
alias gb='git branch'
alias gbd='git branch -d'
alias gruf='git clean -f'
alias gss='git stash'
alias gssl='git stash list'
alias gssp='git stash pop'
alias grm='git rebase master'
alias grc='git rebase --continue'
alias gpf='git push --force'

# check-ollama: diagnose connectivity to Ollama via SSH tunnel
check-ollama() {
  local host="host.docker.internal"
  local port="11434"
  local url="http://${host}:${port}"

  echo "=== Ollama connectivity check ==="
  echo ""

  # 1. DNS resolution
  echo -n "[1] Resolving ${host}... "
  if getent hosts "$host" > /dev/null 2>&1; then
    echo "OK ($(getent hosts "$host" | awk '{print $1}'))"
  else
    echo "FAIL — host.docker.internal not resolvable (not in /etc/hosts?)"
    return 1
  fi

  # 2. TCP reachability
  echo -n "[2] TCP ${host}:${port}... "
  if curl -sf --max-time 3 "${url}/api/tags" > /dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL — HP-ZGX Ollama not reachable from Docker."
    echo ""
    echo "  Checklist:"
    echo "  1. SSH tunnel must be open: ssh HP-ZGX"
    echo "  2. ~/.ssh/config must bind to all interfaces (not just localhost):"
    echo "       LocalForward *:${port} localhost:${port}"
    echo "  3. Ollama must be running on HP-ZGX: systemctl status ollama"
    echo "  Then reconnect: ssh HP-ZGX"
    return 1
  fi

  # 3. Model list
  echo ""
  echo "[3] Available models:"
  curl -sf --max-time 5 "${url}/api/tags" \
    | grep -o '"name":"[^"]*"' \
    | sed 's/"name":"//;s/"//'

  # 4. Env summary
  echo ""
  echo "[4] Env:"
  echo "    ANTHROPIC_BASE_URL  = ${ANTHROPIC_BASE_URL:-(not set)}"
  echo "    ANTHROPIC_AUTH_TOKEN= ${ANTHROPIC_AUTH_TOKEN:-(not set)}"
  echo "    OLLAMA_DEFAULT_MODEL= ${OLLAMA_DEFAULT_MODEL:-(not set)}"
  echo ""
  echo "=== All checks passed — run: claude-zgx ==="
}

# claude-zgx: routes to Ollama on HP-ZGX via SSH LocalForward tunnel
# host.docker.internal:11434 → Mac host → SSH tunnel → HP-ZGX Ollama
#
# Usage:
#   claude-zgx                        interactive, default model
#   claude-zgx qwen3.5:35b            interactive, specific model
#   claude-zgx -r "do the TODO"       non-interactive, default model
#   claude-zgx qwen3.5:35b -r "task"  non-interactive, specific model
claude-zgx() {
  local model="$OLLAMA_DEFAULT_MODEL"
  if [[ -n "$1" && "$1" != -* ]]; then
    model="$1"; shift
  fi

  if [[ "$1" == "-r" ]]; then
    shift
    ANTHROPIC_AUTH_TOKEN=ollama \
    ANTHROPIC_BASE_URL=http://host.docker.internal:11434 \
      claude --model "$model" --dangerously-skip-permissions --print -p "$@"
  else
    ANTHROPIC_AUTH_TOKEN=ollama \
    ANTHROPIC_BASE_URL=http://host.docker.internal:11434 \
      claude --model "$model" --dangerously-skip-permissions "$@"
  fi
}

# claude-vllm: routes to vLLM on HP-ZGX via SSH LocalForward tunnel
# host.docker.internal:8000 → Mac host → SSH tunnel → HP-ZGX vLLM
#
# Usage:
#   claude-vllm                         interactive, default model
#   claude-vllm llama3.1:8b             interactive, specific model
#   claude-vllm -r "do the TODO"        non-interactive, default model
#   claude-vllm llama3.1:8b -r "task"   non-interactive, specific model
claude-vllm() {
  local model="$VLLM_DEFAULT_MODEL"
  if [[ -n "$1" && "$1" != -* ]]; then
    model="$1"; shift
  fi

  if [[ "$1" == "-r" ]]; then
    shift
    ANTHROPIC_AUTH_TOKEN=vllm \
    ANTHROPIC_BASE_URL=http://host.docker.internal:8000 \
      claude --model "$model" --dangerously-skip-permissions --print -p "$@"
  else
    ANTHROPIC_AUTH_TOKEN=vllm \
    ANTHROPIC_BASE_URL=http://host.docker.internal:8000 \
      claude --model "$model" --dangerously-skip-permissions "$@"
  fi
}

# check-vllm: diagnose connectivity to vLLM via SSH tunnel
check-vllm() {
  local host="host.docker.internal"
  local port="8000"
  local url="http://${host}:${port}"

  echo "=== vLLM connectivity check ==="
  echo ""

  # 1. DNS resolution
  echo -n "[1] Resolving ${host}... "
  if getent hosts "$host" > /dev/null 2>&1; then
    echo "OK ($(getent hosts "$host" | awk '{print $1}'))"
  else
    echo "FAIL — host.docker.internal not resolvable (not in /etc/hosts?)"
    return 1
  fi

  # 2. TCP reachability
  echo -n "[2] TCP ${host}:${port}... "
  if curl -sf --max-time 3 "${url}/models" > /dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL — HP-ZGX vLLM not reachable from Docker."
    echo ""
    echo "  Checklist:"
    echo "  1. SSH tunnel must be open: ssh HP-ZGX"
    echo "  2. ~/.ssh/config must have: LocalForward *:8000 localhost:8000"
    echo "  3. vLLM must be running on HP-ZGX: bash service/utils/start-vllm.sh"
    echo "  Then reconnect: ssh HP-ZGX"
    return 1
  fi

  # 3. Model list
  echo ""
  echo "[3] Available models:"
  curl -sf --max-time 5 "${url}/models" \
    | grep -o '"id":"[^"]*"' \
    | sed 's/"id":"//;s/"//'

  # 4. Env summary
  echo ""
  echo "[4] Env:"
  echo "    VLLM_DEFAULT_MODEL= ${VLLM_DEFAULT_MODEL:-(not set)}"
  echo ""
  echo "=== All checks passed — run: claude-vllm ==="
}

# claude-anthropic: routes to real Anthropic API with caveman always-on
# caveman keeps responses terse and token-efficient by default
claude-qwen38() {
  ANTHROPIC_AUTH_TOKEN=sglang \
  ANTHROPIC_BASE_URL=http://host.docker.internal:8000 \
  ANTHROPIC_DEFAULT_OPUS_MODEL=qwen \
  ANTHROPIC_DEFAULT_SONNET_MODEL=qwen \
  ANTHROPIC_DEFAULT_HAIKU_MODEL=qwen \
  CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000 \
  MAX_THINKING_TOKENS=2048 \
  API_TIMEOUT_MS=3600000 \
   claude --model qwen --dangerously-skip-permissions "$@"
}