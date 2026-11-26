#!/bin/bash
# Check that a local model server is usable for Claude Code and Pi.
# Works for any server on the URL (llama-server, vLLM, SGLang), local or through a tunnel.
#   1. model list          GET  /v1/models
#   2. OpenAI chat         POST /v1/chat/completions   (what Pi's `local` provider sends)
#   3. Anthropic + tool    POST /v1/messages            (what Claude Code sends; must call the tool)
#
# Usage: ./check.sh [base-url]   (default http://localhost:8000)
# Env:   MODEL  model name to request (default: first id the server lists)
set -uo pipefail
BASE="${1:-http://localhost:8000}"
fails=0
step() { printf '%-28s %s\n' "$1" "$2"; [[ "$2" == ok* ]] || fails=$((fails + 1)); }

models=$(curl -s -m 5 "$BASE/v1/models") || { step "1 model list" "FAIL: no answer from $BASE"; exit 1; }
MODEL="${MODEL:-$(jq -r '.data[0].id // empty' <<<"$models")}"
[[ -n "$MODEL" ]] && step "1 model list" "ok ($MODEL)" || { step "1 model list" "FAIL: $models"; exit 1; }

chat=$(curl -s -m 300 "$BASE/v1/chat/completions" -H 'Content-Type: application/json' -d "$(jq -n --arg m "$MODEL" \
  '{model: $m, max_tokens: 2048, messages: [{role: "user", content: "Reply with the single word: pong"}]}')")
text=$(jq -r '.choices[0].message.content // empty' <<<"$chat")
grep -qi pong <<<"$text" && step "2 OpenAI chat" "ok" || step "2 OpenAI chat" "FAIL: ${chat:0:300}"

msg=$(curl -s -m 300 "$BASE/v1/messages" -H 'Content-Type: application/json' -H 'x-api-key: local' \
  -H 'anthropic-version: 2023-06-01' -d "$(jq -n --arg m "$MODEL" '{model: $m, max_tokens: 2048,
  tools: [{name: "get_weather", description: "Current weather for a city",
           input_schema: {type: "object", properties: {city: {type: "string"}}, required: ["city"]}}],
  messages: [{role: "user", content: "What is the weather in Berlin? Use the tool."}]}')")
call=$(jq -c '[.content[]? | select(.type == "tool_use")][0].input // empty' <<<"$msg")
[[ "$(jq -r .stop_reason <<<"$msg")" == tool_use && -n "$call" ]] \
  && step "3 Anthropic + tool call" "ok ($call)" || step "3 Anthropic + tool call" "FAIL: ${msg:0:300}"

[[ $fails -eq 0 ]] && echo "check: ok" || { echo "check: $fails failed"; exit 1; }
