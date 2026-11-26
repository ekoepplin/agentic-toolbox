# Claude Code against a local model server. Source it: `source clients.sh`
# (or copy the functions into ~/.zshrc). Env vars are scoped to the one command.
#
# Env: LOCAL_URL    server without /v1 (default http://localhost:8000)
#      LOCAL_MODEL  served model name, see `curl -s $LOCAL_URL/v1/models` (default qwen)
#      LOCAL_CTX    the context window your server actually serves (default 65536)
#
# Pi needs no wrapper: register the server once in ~/.pi/agent/models.json (see README.md).

# Claude Code against the local server, no Anthropic account involved.
# Claude Code also sends background requests (titles, summaries) to its haiku/sonnet/opus tiers
# by name; the three DEFAULT_*_MODEL vars map them onto the local model, or those requests fail.
# CLAUDE_CODE_MAX_CONTEXT_TOKENS: Claude Code does not know the model and would assume 200k,
# so it would compact too late. MAX_THINKING_TOKENS caps reasoning; API_TIMEOUT_MS gives
# slow local decoding time.
claude-local() {
  local url="${LOCAL_URL:-http://localhost:8000}" model="${LOCAL_MODEL:-qwen}"
  ANTHROPIC_BASE_URL="$url" ANTHROPIC_AUTH_TOKEN=local \
  CLAUDE_CODE_MAX_CONTEXT_TOKENS="${LOCAL_CTX:-65536}" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="$model" ANTHROPIC_DEFAULT_SONNET_MODEL="$model" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL="$model" \
  MAX_THINKING_TOKENS=2048 API_TIMEOUT_MS=3600000 \
    claude --model "$model" "$@"
}

