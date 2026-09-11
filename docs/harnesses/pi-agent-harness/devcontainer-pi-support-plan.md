# Plan: add pi agent support to the devcontainer

Add the [pi coding agent](https://pi.dev/) and a pinned-extension mechanism to the
`.devcontainer/`, mirroring how Claude Code + skills are already wired in. Status:
**planned, not yet implemented.**

## Decisions (agreed)

- **pi config is container-specific and seeded**, not bind-mounted from the host.
  The host's `~/.pi/agent/models.json` points at `localhost:8000`; inside Docker
  the tunnel is only reachable via `host.docker.internal`, so the container needs
  its own `models.json`. Isolated → never clobbers the Mac config. No shared
  sessions/auth.
- **Extensions: mechanism only, empty list.** Wire up a pinned-install lock file
  (the pi equivalent of `skills.lock`) with zero entries, ready to add later.

## Validated facts

_(checked against https://github.com/earendil-works/pi @ main)_

- pi installs as a global npm package **`@earendil-works/pi-coding-agent`** (v0.85.1)
  — same pattern as `@anthropic-ai/claude-code`. `bin` = `pi`. Depends on
  `@earendil-works/{chord,pi-agent-core,pi-ai,pi-tui}` (resolved by npm).
- Upstream confirms `--ignore-scripts` usage: *"Local release installs, documented
  npm installs, and `pi update --self` use `--ignore-scripts` where supported."*
- **⚠️ Requires Node `>=22.19.0`** (`engines` in `packages/coding-agent/package.json`).
  The devcontainer base image is **`node:20-slim`** → must bump to `node:22-slim`
  (or newer) or the install hits `EBADENGINE` and pi won't run. See change 0.
- pi config lives in `~/.pi/agent/` (`models.json`, `settings.json`, `extensions/`).
- pi has **no `--base-url` flag** (only Azure-specific ones) → the endpoint must
  come from `models.json`. Confirms the container needs its own file.
- `pi install <source>` writes to `settings.json` `packages[]` and installs;
  sources: `npm:@scope/name@version`, `git:github.com/user/repo@ref`, `https`/`ssh`,
  or a local path. Pinned refs = reproducible installs.
- Auto-discovery also loads any `.ts` under `~/.pi/agent/extensions/`.
- The `qwen` (SGLang Qwen3.8) endpoint is a reasoning model needing
  `compat: { thinkingFormat: "qwen", supportsDeveloperRole: false, supportsReasoningEffort: false }`
  — already verified against the live endpoint.

## How Claude Code is wired today (the pattern to mirror)

| Concern | Claude Code | pi (this plan) |
|---|---|---|
| Install | `npm i -g @anthropic-ai/claude-code` in Dockerfile | `npm i -g --ignore-scripts @earendil-works/pi-coding-agent` in Dockerfile |
| Config | host `~/.claude` bind-mounted | seeded `~/.pi/agent/` (container-only) |
| Local routing | `claude-vllm` alias sets `ANTHROPIC_BASE_URL=host.docker.internal:8000` | baked into `models.json` `baseUrl` (no env needed) |
| Extensibility | `install-skills.sh` + `skills.lock` (pinned) | `setup-pi.sh` + `pi-extensions.lock` (pinned) |

## Changes

0. **`.devcontainer/Dockerfile` — bump base image** `node:20-slim` → `node:22-slim`
   (pi requires Node ≥22.19.0). Prerequisite for the pi install below. Nothing else
   in the image pins Node 20 — Claude Code, ccstatusline, and Playwright 1.58.2 all
   support Node 22; the Python venv/uv path is unaffected.
   → verify: image builds; `node --version` ≥ v22.19; `claude --version` still runs.

1. **`.devcontainer/Dockerfile`** — add a global npm install of
   `@earendil-works/pi-coding-agent` (with `--ignore-scripts`, `chown ~/.npm`),
   beside the Claude Code / ccstatusline installs.
   → verify: `pi --version` runs in the built image.

2. **`.devcontainer/scripts/setup-pi.sh`** (new) — on container create:
   - `mkdir -p ~/.pi/agent/extensions`
   - write `~/.pi/agent/models.json` with provider `vllm-hpzgx`,
     `baseUrl: http://host.docker.internal:8000/v1`, the `qwen` model, and the
     verified `compat` block.
   - write `~/.pi/agent/settings.json` (only if absent) with
     `defaultProvider/defaultModel = vllm-hpzgx/qwen` and `packages: []`.
   - read `pi-extensions.lock` and run `pi install <source>` per non-comment line.
   → verify: `bash -n setup-pi.sh`; embedded JSON parses; with an empty lock,
     nothing installs and the script exits 0.

3. **`.devcontainer/pi-extensions.lock`** (new) — commented, empty pinned list.
   Documents the `npm:`/`git:` format. Analogue of `skills.lock`.

4. **`.devcontainer/scripts/post-create.sh`** — add one line: `bash "$SCRIPTS_DIR/setup-pi.sh"`
   after the skills install.
   → verify: `bash -n post-create.sh`.

5. **`.devcontainer/claude-aliases.sh`** — add a thin `pi-qwen` helper
   (`pi --provider vllm-hpzgx --model qwen "$@"`). No env overrides needed since
   `models.json` already carries the base URL.
   → verify: `bash -n` the sourced file.

6. **`.devcontainer/devcontainer.json`** — extend the AGENTS/SKILLS comment blocks
   to document pi routing and the `pi-extensions.lock` mechanism. Comments only;
   no behavioural change (config is seeded, not mounted, so no new mount).
   → verify: JSON still parses.

7. **`docs/harnesses/pi-agent-harness/connecting-local-models.md`** — add a short
   "In the devcontainer" note: config is auto-seeded, endpoint is
   `host.docker.internal:8000`, run with `pi-qwen` or `pi`.

## Out of scope

- Cloud pi providers / `pi auth` inside the container (local vLLM only, per the
  seed decision).
- Actually rebuilding the devcontainer here — validation is limited to shell
  `bash -n` and JSON parse checks; the image build is verified when the user
  rebuilds.

## Verification gate

- `bash -n` on every new/edited shell script.
- `python3 -c 'json.load(...)'` on the embedded `models.json`/`settings.json` and
  on `devcontainer.json` (after stripping `//` comments, or a jsonc-aware check).
- Empty `pi-extensions.lock` ⇒ `setup-pi.sh` install loop is a no-op.
