#!/bin/bash
# Minimal split loop: Opus judges, local Qwen executes.
#   1. (interactive, before this script) grill with Opus -> plan.md
#   2. Qwen implements plan.md in $WORK
#   3. the script runs the Verify commands (not the model)
#   4. Opus reviews the diff against plan.md -> JSON score
#   red or failed review -> feedback into the next Qwen run, max $MAX rounds
#
# Usage: EXEC=<provider>/<id> ./loop.sh <plan.md> <empty-git-dir>
# Env:   EXEC  local model as Pi knows it, e.g. from ~/.pi/agent/models.json (required)
#        JUDGE (default anthropic/claude-opus-5-5), MAX rounds (default 3)
#        HIDDEN_VERIFY  optional file, one command per line, run by the harness after the
#                       plan's Verify block. The executor never sees it up front (held-out
#                       checks); a failure reaches it only as feedback for the next round.
set -euo pipefail
PLAN="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; WORK="$2"; MAX="${MAX:-3}"
EXEC="${EXEC:?set EXEC=<provider>/<id>, your local model in Pi}"
JUDGE="${JUDGE:-anthropic/claude-opus-5-5}"
HIDDEN=""; [[ -n "${HIDDEN_VERIFY:-}" ]] && HIDDEN="$(cd "$(dirname "$HIDDEN_VERIFY")" && pwd)/$(basename "$HIDDEN_VERIFY")"
cd "$WORK"; feedback=""

verify_cmds() {
  sed -n '/^## Verify/,$p' "$PLAN" | sed -n '/^```$/,/^```$/p' | sed '1d;$d'
  [[ -n "$HIDDEN" ]] && grep -v '^\s*\(#\|$\)' "$HIDDEN"
  return 0
}

for ((i = 1; i <= MAX; i++)); do
  echo "=== round $i: execute ($EXEC)" >&2
  pi -p --no-session --model "$EXEC" --tools read,write,edit,bash \
    "Implement this plan in the current directory. Touch only the files it lists.
Run the Verify commands yourself before you finish. Do not install anything.
$(cat "$PLAN")
${feedback:+# FEEDBACK FROM LAST ROUND
$feedback}" >&2 || true

  echo "=== round $i: verify (harness)" >&2
  log=$(verify_cmds |
    while read -r cmd; do
      echo "\$ $cmd"; bash -c "$cmd" </dev/null 2>&1 | tail -5 && echo "[ok]" || echo "[FAIL]"
    done)
  echo "$log" >&2
  if grep -q '\[FAIL\]' <<<"$log"; then feedback="Verify failed:
$log"; continue; fi

  echo "=== round $i: judge ($JUDGE)" >&2
  verdict=$(pi -p --no-session --model "$JUDGE" --tools read,grep,find,ls \
    "You review work done by another model. Read plan.md below and the files it lists in the
current directory. Score each acceptance criterion 0 (missing), 1 (partial) or 2 (met), and quote
the line that proves it. Answer with JSON only:
{\"pass\": bool, \"scores\": [{\"criterion\": n, \"score\": 0-2, \"evidence\": \"...\"}], \"feedback\": \"...\"}
pass is true only if every score is 2.
$(cat "$PLAN")" | python3 -c 'import sys; t = sys.stdin.read(); print(t[t.find("{"):t.rfind("}") + 1])')
  echo "$verdict" >&2
  if [[ "$(jq -r .pass <<<"$verdict" 2>/dev/null)" == true ]]; then echo "PASS after $i round(s)"; exit 0; fi
  feedback="Review failed: $(jq -r .feedback <<<"$verdict" 2>/dev/null || echo "$verdict")"
done
echo "FAIL after $MAX rounds -> escalate to Opus or a human"; exit 1
