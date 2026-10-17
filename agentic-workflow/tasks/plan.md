# Plan: GitHub Copilot CLI as the third harness

Supersedes the base/dock refactor plan (issues #8–#14, done — see git history
of this file). Status: **planned, not started**.

## Goal

A docked workbench runs `copilot` (GitHub Copilot CLI) with the base's skills
available, wired by the dock step on every start — the same contract Claude
Code and pi already have (`CONTEXT.md`: one harness adapter per harness).

## Research (2026-10-17)

| Fact | Source | Verified here |
|---|---|---|
| Install: `npm install -g @github/copilot`, Node ≥ 22 | [install docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli) | ✅ v1.0.98 installs and runs in `agentic-toolbox-base` |
| Personal skills: `~/.copilot/skills/` or `~/.agents/skills/`; project: `.github/skills`, `.claude/skills`, `.agents/skills` | [skills docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-skills) | ✅ `copilot skill --help` lists the same |
| Symlinked skill dirs are followed | not documented | ✅ 37 symlinks → `copilot skill list` lists all 37, no warnings |
| `copilot skill list` works without login and without an LLM call | — | ✅ — usable as a deterministic dock probe |
| Instructions: `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md` in repo root / cwd; user-level `~/.copilot/copilot-instructions.md`; extra dirs via `COPILOT_CUSTOM_INSTRUCTIONS_DIRS` | [instructions docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-custom-instructions) | ❌ not tested |
| Custom agents: `~/.copilot/agents/*.agent.md` | [GitHub blog](https://github.blog/ai-and-ml/github-copilot/from-one-off-prompts-to-workflows-how-to-use-custom-agents-in-github-copilot-cli/) | n/a — base `agents/` is empty |
| Auth: `COPILOT_GITHUB_TOKEN` > `GH_TOKEN` > `GITHUB_TOKEN`; fine-grained PAT with "Copilot Requests" | install docs | ❌ not tested (would spend a Copilot request) |

What the base ships today: 3 skills (`skills/`), 34 vendored skills (flattened
as symlinks in the base's git-ignored `.claude/skills/` by `install-skills.sh`);
`agents/`, `commands/`, `hooks/` are empty. So the adapter is **skills + auth**.

## Steps

1. **Image** — add `ARG COPILOT_VERSION=1.0.98` and `@github/copilot@${COPILOT_VERSION}`
   to the agent-CLI npm layer in `.devcontainer/Dockerfile`.
   → verify: `make probe` asserts `copilot --version`.
2. **Dock step §5, Copilot adapter** (`.devcontainer/scripts/dock.sh`) — symlink
   every shipped skill (`$BASE/skills/*/`, not `in-progress/`) and every vendored
   skill (`$BASE/.claude/skills/*`, resolved) into `~/.copilot/skills/<name>`;
   remove stale links that point into the base but no longer resolve.
   Container-local, never writes to the host; idempotent.
   → verify: second run prints "in sync"; `copilot skill list` lists 37.
3. **Auth passthrough** — add `COPILOT_GITHUB_TOKEN` to `environment:` in
   `compose.yaml` and in the `scripts/dock-host.sh` template (beside
   `PI_GH_TOKEN`). Existing hosts (`sprungjob`, `dlt-information-retrieval-utils`,
   `haus-daten-am-rankrain`) need the one line by hand — re-docking refuses to
   overwrite. `~/.copilot` is container-local, so an interactive `copilot login`
   would not survive a recreate; the token is the durable path.
   → verify: `copilot -p "reply OK"` in a workbench with the token set (one request).
4. **Probes** — `probe-dock.sh`: `copilot skill list` contains the 3 shipped
   skills. `scripts/dock-e2e.sh` inherits it.
   → verify: `make probe-dock`, `make dock-e2e` green.
5. **Docs** — `docs/harnesses/copilot.md` (wiring, auth, limits); harness list
   in `CONTEXT.md`, `README.md`, `CLAUDE.md` (`dock.sh` comment header too).
   → verify: grep for "Claude Code and pi" finds no stale two-harness claim.

`scripts/check.sh` is unaffected: `plugin.json` stays the Claude Code adapter's
manifest; the Copilot adapter derives its list from disk.

## Open decisions (for the owner)

1. **Base behavioral guidelines for Copilot.** A host's own `CLAUDE.md` is read
   natively, but the base's guidelines reach Claude via `@~/repos/agentic-toolbox/CLAUDE.md`
   imports — whether Copilot resolves `@` imports is untested. Options: skip in
   v1 (recommended), or link `~/.copilot/copilot-instructions.md` to a
   guidelines-only file split out of the base `CLAUDE.md`.
2. **Token.** Use a dedicated fine-grained PAT with "Copilot Requests", or reuse
   `GH_TOKEN` if one is already forwarded. Needs an active Copilot plan.

## Out of scope

- Local models (`vllm-hpzgx`) for Copilot — Copilot CLI talks to GitHub-hosted
  models; bring-your-own-endpoint support was not researched.
- Voice — no Copilot CLI voice input known; the PulseAudio bridge stays
  available to any tool that uses it.
