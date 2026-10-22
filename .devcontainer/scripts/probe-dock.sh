#!/usr/bin/env bash
# Issue #10 acceptance probes, run inside the dogfooded workbench
# (make probe-dock → docker compose exec). Every probe is deterministic:
# no LLM call, no model endpoint needed. Requires the dock step to have run
# (i.e. the workbench is up — it runs on every start via the compose command).
set -euo pipefail

BASE="$(cd "$(dirname "$0")/../.." && pwd)"
echo "== dock probes: workbench (base at $BASE) =="

# Shipped skills come from the Claude Code adapter's manifest — the contract
# scripts/check.sh enforces — so no probe hard-codes skill names or counts.
mapfile -t shipped < <(python3 -c '
import json, sys
for s in json.load(open(sys.argv[1])).get("skills", []):
    print(s.rstrip("/").split("/")[-1])
' "$BASE/.claude-plugin/plugin.json")

# ── Claude Code: the plugin loads; shipped skills under its namespace ───────
# --plugin-dir loads the plugin from the mounted base; plugin details prints
# the component inventory without an LLM call.
out="$(claude --plugin-dir "$BASE" plugin details agentic-toolbox)" \
  || { echo "FATAL: claude cannot load the agentic-toolbox plugin"; exit 1; }
if [ "${#shipped[@]}" -gt 0 ]; then
  echo "$out" | grep -q "Skills (${#shipped[@]})" \
    || { echo "FATAL: plugin inventory does not list ${#shipped[@]} skill(s)"; exit 1; }
fi
for s in ${shipped[@]+"${shipped[@]}"}; do
  echo "$out" | grep -q "$s" \
    || { echo "FATAL: $s missing from the plugin inventory"; exit 1; }
done
echo "claude: plugin loads (${#shipped[@]} shipped skill(s) under /agentic-toolbox:)"

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
# the base's .agents/skills/ is a project resource). The driver stops pi as
# soon as the response arrives; `timeout` bounds a pi that never answers.
cmds="$(timeout 60 python3 -c '
import json, subprocess
pi = subprocess.Popen(["pi", "--mode", "rpc", "-a", "--no-session"],
                      stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
pi.stdin.write(json.dumps({"id": "1", "type": "get_commands"}) + "\n")
pi.stdin.flush()
for line in pi.stdout:
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") == "response" and d.get("command") == "get_commands":
        for c in d["data"]["commands"]:
            if c.get("source") == "skill":
                print(c["name"])
        break
pi.terminate()
pi.wait()
')"
for s in ${shipped[@]+"${shipped[@]}"} code-review; do
  echo "$cmds" | grep -qx "skill:$s" \
    || { echo "FATAL: pi does not expand skill:$s"; exit 1; }
done
echo "pi: deterministic skill expansion passed (${#shipped[@]} shipped + vendored code-review)"

# ── pi: the base's skill paths are seeded in the container config ───────────
python3 - "$HOME/.pi/agent/settings.json" "$BASE" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
skills = data.get("skills", [])
assert sys.argv[2] + "/skills" in skills, "base skills/ path not seeded"
assert sys.argv[2] + "/.agents/skills" in skills, "vendored path not seeded"
print("pi: base skill paths seeded in settings.json")
PY

# ── Copilot CLI: base + vendored skills discovered ──────────────────────────
# `copilot skill list` reads the skill dirs locally — no login, no LLM call.
skills="$(copilot skill list)"
for s in ${shipped[@]+"${shipped[@]}"} code-review; do
  echo "$skills" | grep -q "^  $s - " \
    || { echo "FATAL: copilot does not list skill $s"; exit 1; }
done
echo "copilot: base + vendored skills discovered (copilot skill list)"

# ── SSH keys: synced from the staged host file ───────────────────────────────
cmp -s /tmp/container_authorized_keys "$HOME/.ssh/authorized_keys" \
  || { echo "FATAL: authorized_keys not synced from the staged host file"; exit 1; }
[ "$(stat -c %a "$HOME/.ssh/authorized_keys")" = 600 ] \
  || { echo "FATAL: authorized_keys is not mode 600 (sshd would reject it)"; exit 1; }
echo "ssh: authorized_keys synced from the staged host file (mode 600)"

# ── Bot identity: persisted for SSH sessions, never world-readable ─────────
[ "$(stat -c %a "$HOME/.config/as-bot.env")" = 600 ] \
  || { echo "FATAL: ~/.config/as-bot.env missing or not mode 600"; exit 1; }
echo "bot: identity file present for SSH sessions (mode 600)"

# ── Idempotency: a second dock run is a no-op ────────────────────────────────
pin="$(sed -n 's/^mattpocock-skills[[:space:]]*=[[:space:]]*\([^[:space:]#]*\).*/\1/p' "$BASE/.devcontainer/skills.lock" | head -n1)"
second="$(bash "$BASE/.devcontainer/scripts/dock.sh")"
echo "$second" | grep -q "pin $pin satisfied" \
  || { echo "FATAL: second dock run fetched the vendored set"; exit 1; }
echo "$second" | grep -q "in sync" \
  || { echo "FATAL: second dock run rewired container state"; exit 1; }
echo "dock: second run is a no-op"

echo "== all dock probes passed =="
