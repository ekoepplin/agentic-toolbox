#!/usr/bin/env bash
# Runs once after the container is created (postCreateCommand in devcontainer.json).
# SSH keys are synced by the dock step (dock.sh), which runs on every start —
# this hook only covers create-time extras.
set -euo pipefail

# ── Persistent directories ───────────────────────────────────────────────────
mkdir -p /home/node/agent-logs /home/node/agent-work

# ── claude.json ──────────────────────────────────────────────────────────────
# Seed from the read-only host copy before headroom writes to it; may race
# with dock.sh, which seeds the same way (only if missing).
if [ -f /tmp/claude.json.host ] && [ ! -f "$HOME/.claude.json" ]; then
  cp /tmp/claude.json.host "$HOME/.claude.json"
fi

# ── Headroom MCP server ──────────────────────────────────────────────────────
# Registers headroom as an MCP server in ~/.claude/settings.json so Claude Code
# can call headroom_compress / headroom_retrieve / headroom_stats automatically.
headroom mcp install || true
