#!/usr/bin/env bash
# The dock step (issue #10) — runs on every workbench start (compose service
# command, not just first creation) and wires the docked base into every
# supported harness. Idempotent: a second run is a no-op.
#
#   1. Dirty-base warning — uncommitted changes on the base mount are visible
#      at boot; a clean base stays quiet.
#   2. Vendored skill set — the pinned external set is fetched into the
#      base's git-ignored .agents/skills/ only if missing or the pin changed,
#      and wired into every harness (install-skills.sh; Copilot in step 5).
#   3. Claude Code — an alias makes `claude` load the base plugin from the
#      mounted base (--plugin-dir), so shipped skills are invocable as
#      /agentic-toolbox:<name>.
#   4. pi — container-local ~/.pi/agent/ config: the container-specific model
#      provider (host.docker.internal, seeded, never bind-mounted) and the
#      base's skill paths.
#   5. GitHub Copilot CLI — container-local ~/.copilot/skills/ links to every
#      shipped and vendored skill.
#   6. Bot identity — compose's BOT_*/PI_* persisted to ~/.config/as-bot.env
#      (mode 600) for as-bot, because sshd sessions never see container env.
#
# Before step 1 it syncs the staged SSH authorized_keys and seeds claude.json —
# post-create.sh only runs under VS Code, so a `docker compose up` workbench
# would otherwise come up with no SSH keys.
#
# Runs as the container user (node). Everything it writes is container-local
# or inside the base's git-ignored paths — it never touches host state.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
BASE_DIR="$(cd "$SCRIPTS_DIR/../.." && pwd)"

# safe.directory: the base mount is owned by the host's user uid; the
# container runs this step as node (uid 1000), so git would otherwise
# refuse the repo as "dubious ownership".
git_base() { git -c safe.directory="$BASE_DIR" -C "$BASE_DIR" "$@"; }

echo "dock: base at $BASE_DIR"

sudo /usr/local/bin/fix-docker-socket.sh || echo "dock: WARNING — fix-docker-socket.sh failed; docker CLI may lack socket access" >&2

# ── Staged host files ────────────────────────────────────────────────────────
# authorized_keys: synced every start — the host file is the source of truth,
# and the bind mount has the wrong ownership for sshd, so copy, don't link.
# claude.json: seeded only if missing — afterwards it holds container-side
# state (trusted projects, sessions) that a re-copy would clobber.
if [ -f /tmp/container_authorized_keys ]; then
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  cp /tmp/container_authorized_keys "$HOME/.ssh/authorized_keys"
  chmod 600 "$HOME/.ssh/authorized_keys"
  echo "dock: SSH authorized_keys synced"
else
  echo "dock: WARNING — no staged /tmp/container_authorized_keys; SSH login will fail" >&2
fi
if [ -f /tmp/claude.json.host ] && [ ! -f "$HOME/.claude.json" ]; then
  cp /tmp/claude.json.host "$HOME/.claude.json"
  echo "dock: claude.json seeded"
fi

# ── 1. Dirty-base warning ────────────────────────────────────────────────────
if git_base rev-parse --git-dir >/dev/null 2>&1; then
  dirty="$(git_base status --porcelain)"
  if [ -n "$dirty" ]; then
    n="$(printf '%s\n' "$dirty" | grep -c .)"
    {
      echo "dock: WARNING — dirty base at $BASE_DIR: $n uncommitted change(s)."
      echo "dock: WARNING — every harness sees uncommitted content; commit or clean the base first."
    } >&2
  fi
fi

# ── 2. Vendored skill set (pinned in .devcontainer/skills.lock) ─────────────
# Fetches only when the clone is missing or the pin changed; symlinks the
# skills into .claude/skills/ for Claude Code. pi discovers .agents/skills/
# on its own (also wired via the seeded settings.json below).
bash "$SCRIPTS_DIR/install-skills.sh"

# ── 3. Claude Code harness adapter ───────────────────────────────────────────
# The base plugin loads from the mounted base. --plugin-dir is session-scoped
# in Claude Code, so the alias is the wiring: interactive shells in the
# workbench get it for free. The rc files are container-local (image state),
# so this never writes through to the host.
alias_line="alias claude='claude --plugin-dir $BASE_DIR'"
for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
  [ -f "$rc" ] || continue
  if grep -qxF "$alias_line" "$rc"; then
    echo "dock: claude alias in sync ($rc)"
    continue
  fi
  # Drop any stale dock alias (e.g. from a previous base path), then append.
  sed -i "/^alias claude='claude --plugin-dir /d" "$rc"
  echo "$alias_line" >> "$rc"
  echo "dock: claude alias updated ($rc)"
done

# ── 4. pi harness adapter ────────────────────────────────────────────────────
# Container-specific config, seeded (never bind-mounted from the host — the
# host's models.json points at localhost; inside the container the tunnel is
# only reachable via host.docker.internal). Both files are upserted in place:
# user-added providers / settings keys are preserved, and nothing is rewritten
# when the content already matches (idempotent no-op).
PI_AGENT_DIR="$HOME/.pi/agent"
mkdir -p "$PI_AGENT_DIR"
python3 - "$PI_AGENT_DIR" "$BASE_DIR" <<'PY'
import json, os, sys

agent_dir, base_dir = sys.argv[1], sys.argv[2]

def upsert(path, mutate):
    try:
        with open(path) as f:
            data = json.load(f)
        existed = True
    except FileNotFoundError:
        data, existed = {}, False
    if not isinstance(data, dict):
        data, existed = {}, False
    mutate(data)
    desired = json.dumps(data, indent=2) + "\n"
    current = open(path).read() if existed else None
    if current != desired:
        with open(path, "w") as f:
            f.write(desired)
        return "updated"
    return "in sync"

def seed_models(d):
    providers = d.get("providers")
    if not isinstance(providers, dict):
        providers = {}
    # The container provider is seeded (host.docker.internal baseUrl); any
    # other providers the user added are kept as-is.
    providers["vllm-hpzgx"] = {
        "baseUrl": "http://host.docker.internal:8000/v1",
        "api": "openai-completions",
        "apiKey": "vllm",
        "compat": {
            "thinkingFormat": "qwen",
            "supportsDeveloperRole": False,
            "supportsReasoningEffort": False,
        },
        "models": [
            {
                "id": "qwen",
                "name": "HP-ZGX qwen (local — qwen38 or nvfp4 backend)",
                "reasoning": True,
                "contextWindow": 262144,
                "maxTokens": 32000,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            },
            {
                "id": "qwen3.8-flash-next-a5b",
                "name": "HP-ZGX Qwen3.8-Flash-Next 125B-A5B (local)",
                "reasoning": True,
                "contextWindow": 262144,
                "maxTokens": 32000,
                "cost": {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0},
            },
        ],
    }
    d["providers"] = providers

def seed_settings(d):
    d.setdefault("defaultProvider", "vllm-hpzgx")
    d.setdefault("defaultModel", "qwen")
    skills = d.get("skills")
    if not isinstance(skills, list):
        skills = []
    # Point pi at the base's skill paths (shipped skills + vendored set),
    # regardless of the session's working directory.
    for p in (os.path.join(base_dir, "skills"), os.path.join(base_dir, ".agents", "skills")):
        if p not in skills:
            skills.append(p)
    d["skills"] = skills

models_status = upsert(os.path.join(agent_dir, "models.json"), seed_models)
settings_status = upsert(os.path.join(agent_dir, "settings.json"), seed_settings)
print(f"pi: models.json {models_status} ({agent_dir})")
print(f"pi: settings.json {settings_status} ({agent_dir})")
PY

# Pinned pi extensions (.devcontainer/pi-extensions.lock) — installed after the
# config is seeded so pi writes packages[] into the freshly-seeded settings.json.
bash "$SCRIPTS_DIR/install-pi-extensions.sh"

# ── 5. GitHub Copilot CLI harness adapter ────────────────────────────────────
# Copilot discovers personal skills in ~/.copilot/skills/<name>/SKILL.md and
# follows symlinks there. Link every shipped skill (skills/*, not in-progress/)
# and every vendored skill (the flat links install-skills.sh made in
# .claude/skills/, resolved) — the list is derived from disk, so there is no
# Copilot manifest to drift. ~/.copilot is container-local; login state lives
# there too (`copilot login`, once per container). Shipped skills win on a
# name clash because they are linked last.
COPILOT_SKILLS="$HOME/.copilot/skills"
mkdir -p "$COPILOT_SKILLS"
changed=0
for d in "$BASE_DIR"/.claude/skills/* "$BASE_DIR"/skills/*/; do
  d="${d%/}"
  [ "$(basename "$d")" = in-progress ] && continue
  [ -f "$d/SKILL.md" ] || continue
  target="$(readlink -f "$d")"
  link="$COPILOT_SKILLS/$(basename "$d")"
  [ "$(readlink "$link" 2>/dev/null)" = "$target" ] && continue
  ln -sfn "$target" "$link"
  changed=$((changed + 1))
done
# Drop links whose skill was removed or renamed in the base.
while IFS= read -r stale; do
  rm "$stale"
  changed=$((changed + 1))
done < <(find "$COPILOT_SKILLS" -maxdepth 1 -xtype l)
if [ "$changed" -eq 0 ]; then
  echo "copilot: skills in sync ($COPILOT_SKILLS)"
else
  echo "copilot: $changed skill link(s) updated ($COPILOT_SKILLS)"
fi

# ── 6. Bot identity for SSH sessions ─────────────────────────────────────────
# compose passes BOT_*/PI_* into the container's environment, but sshd
# sessions start fresh (lessons 2026-10-17), so as-bot would never see them
# there. Persist whatever is set — an empty file when nothing is, so a removed
# bot doesn't linger. Container-local, mode 600: it holds the bot's token.
BOT_ENV="$HOME/.config/as-bot.env"
mkdir -p "$(dirname "$BOT_ENV")"
(
  umask 077
  for v in BOT_GIT_USER BOT_GIT_EMAIL BOT_GH_TOKEN PI_GIT_USER PI_GIT_EMAIL PI_GH_TOKEN; do
    if [ -n "${!v:-}" ]; then printf '%s=%q\n' "$v" "${!v}"; fi
  done > "$BOT_ENV.new"
)
if cmp -s "$BOT_ENV.new" "$BOT_ENV"; then
  rm "$BOT_ENV.new"
  echo "bot: identity in sync ($BOT_ENV)"
else
  mv "$BOT_ENV.new" "$BOT_ENV"
  echo "bot: identity updated ($BOT_ENV)"
fi

echo "dock: all harnesses wired"
