# GitHub Copilot CLI harness

The third harness next to Claude Code and pi. Every docked workbench ships the
[GitHub Copilot CLI](https://docs.github.com/en/copilot/how-tos/copilot-cli)
(`copilot`, pinned as `COPILOT_VERSION` in `.devcontainer/Dockerfile`), and
the dock step wires the base's skills into it on every start.

## Use it

Requires an active GitHub Copilot plan.

```bash
ssh -p <SSH_PORT> node@localhost
copilot login     # once per container — prints a device code to enter on github.com
copilot           # interactive session in the host repo
```

Skills are invoked as `/<skill-name>` (e.g. `/code-review`) or picked by
Copilot on its own when relevant; `/skills list` shows what is loaded.

## What the adapter wires

| Base content | Copilot | How |
|---|---|---|
| Shipped skills (`skills/*`, not `in-progress/`) | ✅ personal skills | dock step §5 links each into `~/.copilot/skills/<name>` |
| Vendored skill set (`.agents/skills/`) | ✅ personal skills | same, via the flat links `install-skills.sh` keeps in `.claude/skills/` |
| Host repo `CLAUDE.md` / `AGENTS.md` | ✅ read natively | Copilot's own discovery (repo root, cwd) |
| Base behavioral guidelines (`@~/repos/agentic-toolbox/CLAUDE.md` imports) | ❌ not wired | whether Copilot resolves `@` imports is untested; left out by decision |
| Agents, commands, hooks | — | the base ships none today |

There is no Copilot manifest: the adapter derives its skill list from disk, so
`scripts/check.sh` (the `plugin.json` contract) does not cover it. The dock
probe does — `make probe-dock` asserts `copilot skill list` contains every
skill in `plugin.json` and a vendored one, without login or an LLM call.

## Login and container lifetime

`~/.copilot/` is container-local, like `~/.pi/`. Login state and the skill
links live there:

- skill links are recreated by the dock step on every start;
- **login is not** — after `docker compose up -d --force-recreate` (e.g. an
  image rebuild), run `copilot login` again.

Over SSH, `copilot login` uses the OAuth device-code flow (it detects the
headless session). The container has no credential store, so the token is kept
in a plain-text file under `~/.copilot/` — readable by anything running as
`node` in that workbench, and gone with the container.

No token is forwarded into the workbench. `COPILOT_GITHUB_TOKEN` / `GH_TOKEN`
would work as an alternative to `copilot login`, but none is wired up.

## Limits

- **Models** — Copilot uses GitHub-hosted models; the local `vllm-hpzgx`
  endpoint (pi's default) is not wired for Copilot.
- **Voice** — the PulseAudio bridge (`docs/voice.md`) is available in the
  container, but no Copilot CLI voice input is known.

## Bump the version

Change `COPILOT_VERSION` in `.devcontainer/Dockerfile`, then `make probe` and
`make probe-dock` (after recreating the workbench).
