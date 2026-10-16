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

# Local models on HP-ZGX, reached through the Mac's SSH tunnel:
# host.docker.internal:8000 → Mac host → SSH tunnel → HP-ZGX :8000
# Start a backend on the Mac first: start-local-setup [--nvfp4|--flashnext]
# (see ~/repos/hp-zgx-workflow). Used via pi only (pi-zgx, pi-flashnext below).

# check-vllm: diagnose connectivity to the HP-ZGX backend via SSH tunnel
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
  if curl -sf --max-time 3 "${url}/v1/models" > /dev/null 2>&1; then
    echo "OK"
  else
    echo "FAIL — HP-ZGX backend not reachable from Docker."
    echo ""
    echo "  Checklist (on the Mac):"
    echo "  1. Backend running + tunnel open: start-local-setup --status"
    echo "  2. Else start it: start-local-setup [--nvfp4|--flashnext]"
    echo "  3. ~/.ssh/config Host HP-ZGX must forward 8000 (LocalForward)"
    return 1
  fi

  # 3. Model list
  echo ""
  echo "[3] Served models:"
  curl -sf --max-time 5 "${url}/v1/models" \
    | grep -o '"id":"[^"]*"' \
    | sed 's/"id":"//;s/"//'

  echo ""
  echo "=== All checks passed — run: pi-zgx | pi-flashnext ==="
}

# Optional bot identity for pi. When PI_GIT_USER is set, pi commits and pushes
# as that GitHub user (e.g. a dedicated bot account); otherwise pi runs as-is.
# Scoped to the pi process only, so git commits made from the shell itself keep
# the personal identity.
#   PI_GIT_USER   GitHub login of the bot
#   PI_GIT_EMAIL  commit email (default: <PI_GIT_USER>@users.noreply.github.com)
#   PI_GH_TOKEN   the bot's PAT (scopes repo + workflow)
# Without a token pushes fail instead of falling back to another login: the
# credential helpers are replaced, gh gets its own empty config dir, and no
# other GitHub token is passed through.
pi() {
  if [[ -z ${PI_GIT_USER:-} ]]; then
    command pi "$@"
    return
  fi
  local user=$PI_GIT_USER
  local email="${PI_GIT_EMAIL:-$user@users.noreply.github.com}"
  local token="${PI_GH_TOKEN:-}"
  [[ -n $token ]] || echo "pi: PI_GH_TOKEN not set; commits stay $user, pushes will fail" >&2
  GIT_AUTHOR_NAME=$user GIT_AUTHOR_EMAIL=$email \
  GIT_COMMITTER_NAME=$user GIT_COMMITTER_EMAIL=$email \
  GH_TOKEN=$token GITHUB_TOKEN=$token GH_CONFIG_DIR=$HOME/.config/gh-$user \
  GIT_CONFIG_COUNT=2 \
  GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0= \
  GIT_CONFIG_KEY_1=credential.https://github.com.helper \
  GIT_CONFIG_VALUE_1="!f() { test \"\$1\" = get && test -n \"\$GH_TOKEN\" && echo username=$user && echo \"password=\$GH_TOKEN\"; }; f" \
    command pi "$@"
}

# pi against the HP-ZGX backend (goes through the pi() bot wrapper)
# pi-zgx: qwen38 or nvfp4 backend; pi-flashnext: Flash-Next backend
pi-zgx()       { pi --model vllm-hpzgx/qwen "$@"; }
pi-flashnext() { pi --model vllm-hpzgx/qwen3.8-flash-next-a5b "$@"; }
