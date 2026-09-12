#!/usr/bin/env bash
# Issue #10 acceptance probes, run inside the dogfooded workbench
# (make probe-dock → docker compose exec). Every probe is deterministic:
# no LLM call, no model endpoint needed. Requires the dock step to have run
# (i.e. the workbench is up — it runs on every start via the compose command).
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
echo "== dock probes: workbench (base at $BASE) =="

# ── Claude Code: shipped skills under the toolbox namespace ─────────────────
# --plugin-dir loads the plugin from the mounted base; plugin details prints
# the component inventory without an LLM call.
out="$(claude --plugin-dir "$BASE" plugin details agentic-toolbox)"
echo "$out" | grep -q "Skills (3)" \
  || { echo "FATAL: plugin inventory does not list 3 skills"; exit 1; }
for s in web-search-local fetch-news-local fetch-free-images-local; do
  echo "$out" | grep -q "$s" \
    || { echo "FATAL: $s missing from the plugin inventory"; exit 1; }
done
echo "claude: /agentic-toolbox:* invocable (3 shipped skills)"

# ── Claude Code: the dock alias is wired for interactive shells ─────────────
grep -qxF "alias claude='claude --plugin-dir $BASE'" "$HOME/.zshrc" \
  || { echo "FATAL: claude alias not wired in $HOME/.zshrc"; exit 1; }
echo "claude: dock alias present in \$HOME/.zshrc"

# ── pi: the seeded container model config is discovered ─────────────────────
pi --list-models | grep -q vllm-hpzgx \
  || { echo "FATAL: pi does not list the seeded vllm-hpzgx provider"; exit 1; }
pi --list-models | grep -qE '^vllm-hpzgx\s+qwen\s' \
  || { echo "FATAL: pi does not list the qwen model"; exit 1; }
echo "pi: model-list probe passed (vllm-hpzgx/qwen)"

# ── pi: deterministic skill expansion ───────────────────────────────────────
# get_commands lists every /skill:name command pi would expand — the expansion
# table itself, no LLM involved. -a trusts the project (the vendored set in
# the base's .agents/skills/ is a project resource).
cmds="$(
  { echo '{"id":"1","type":"get_commands"}'; sleep 8; } \
    | pi --mode rpc -a --no-session \
    | python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    if d.get("type") == "response" and d.get("command") == "get_commands":
        for c in d["data"]["commands"]:
            if c.get("source") == "skill":
                print(c["name"])
'
)"
echo "$cmds" | grep -q "^skill:web-search-local$" \
  || { echo "FATAL: pi does not expand skill:web-search-local (base shipped skill)"; exit 1; }
echo "$cmds" | grep -q "^skill:code-review$" \
  || { echo "FATAL: pi does not expand skill:code-review (vendored skill)"; exit 1; }
echo "pi: deterministic skill expansion passed (base + vendored)"

# ── pi: the base's skill paths are seeded in the container config ───────────
python3 - "$HOME/.pi/agent/settings.json" "$BASE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
skills = data.get("skills", [])
assert sys.argv[2] + "/skills" in skills, "base skills/ path not seeded"
assert sys.argv[2] + "/.agents/skills" in skills, "vendored path not seeded"
print("pi: base skill paths seeded in settings.json")
PY

# ── Idempotency: a second dock run is a no-op ────────────────────────────────
pin="$(sed -n 's/^mattpocock-skills[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$BASE/.devcontainer/skills.lock" | head -n1)"
second="$(bash "$BASE/.devcontainer/scripts/dock.sh")"
echo "$second" | grep -q "pin $pin satisfied" \
  || { echo "FATAL: second dock run fetched the vendored set"; exit 1; }
echo "$second" | grep -q "in sync" \
  || { echo "FATAL: second dock run rewired container state"; exit 1; }
echo "dock: second run is a no-op"

echo "== all dock probes passed =="
