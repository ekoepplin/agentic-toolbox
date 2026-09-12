#!/usr/bin/env bash
# Runs once after the container is created (postCreateCommand in devcontainer.json).
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Persistent directories ───────────────────────────────────────────────────
mkdir -p /home/node/agent-logs /home/node/agent-work

# ── SSH authorized_keys ──────────────────────────────────────────────────────
# Bind-mount has wrong ownership for sshd — must copy, not use directly.
cp /tmp/container_authorized_keys /home/node/.ssh/authorized_keys
chmod 600 /home/node/.ssh/authorized_keys

# ── claude.json ──────────────────────────────────────────────────────────────
# Staged read-only at /tmp to avoid race conditions with Mac's Claude Code.
cp /tmp/claude.json.host /home/node/.claude.json

# ── Project dependencies ─────────────────────────────────────────────────────
cd /workspace && uv sync || true

# ── External skills ──────────────────────────────────────────────────────────
# The pinned external skill set is wired by the dock step (dock.sh), which
# runs on every container start — not just this create-time hook.

# ── Headroom MCP server ──────────────────────────────────────────────────────
# Registers headroom as an MCP server in ~/.claude/settings.json so Claude Code
# can call headroom_compress / headroom_retrieve / headroom_stats automatically.
headroom mcp install || true
