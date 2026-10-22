# MATT-WORKFLOW.md

Matt Pocock workflow mapped to this repo's `agentic-workflow/ralph/` execution loop.

> **Development aid.** `agentic-workflow/` is committed but is not part of the plugin — `plugin.json` never lists it. The scripts resolve their own paths (and read `.env.ralph` from the repo root), so `agentic-workflow/ralph/afk.sh <N>` works from anywhere in the tree. Shared plumbing — `.env.ralph` loading, flag parsing, issue fetch, the AFK loop — lives in `ralph/lib.sh`; each entry script only maps its backend and launches its harness.

The intended pipeline is **think → plan → break down → execute (loop) → refactor**. The `ralph/` folder is the execution stage. Issues with the right labels get picked up automatically.

## 1. Think — `/grill-with-docs`

Stress-test the idea against `CONTEXT.md` + `docs/adr/`. Updates terminology and ADRs inline as decisions crystallise. Output: shared understanding, no code yet.

## 2. Spec — `/to-spec`

Turn the grilled context into a spec (PRD) published as a GitHub issue on `ekoepplin/agentic-toolbox`. One spec per feature.

## 3. Break down — `/to-tickets`

Slice the spec into independently-grabbable issues using tracer-bullet vertical slices. Each issue gets a triage label:

- `ready-for-agent` → ralph picks up
- `ready-for-human` → you handle
- `needs-info` / `needs-triage` → not actionable yet

## 4. Triage — `/triage` (optional gatekeeper)

State-machine review of incoming issues. Promotes `needs-triage` → `ready-for-agent` once fully specified.

## 5. Execute — `ralph/` loop

This is where the `ralph/` folder fits. Both scripts target **one specific issue per invocation** — they do not auto-pick from the queue. `pi-once.sh` / `pi-afk.sh` are the same loop on pi (see `docs/harnesses/pi-agent-harness/ralph-on-pi.md`).

**One iteration** (interactive, one claude session against one issue):

```bash
agentic-workflow/ralph/once.sh <issue-number> [--backend NAME] [--model NAME]
```

**N iterations AFK** (loop `once.sh` until the issue is `CLOSED` on GitHub or `max-iters` is hit):

```bash
agentic-workflow/ralph/afk.sh <issue-number> [max-iters] [--backend NAME] [--model NAME]
```

`afk.sh` polls `gh issue view <n> --json state` between iterations and exits 0 when the state is `CLOSED`. Default `max-iters` is `10`.

### Backend & model selection

Both scripts route claude to one of three backends. Pick the one that matches the model you want:

| `--backend` | Endpoint                                 | Example `--model` values                                         |
|-------------|------------------------------------------|------------------------------------------------------------------|
| `vllm`      | `host.docker.internal:8000` (SSH tunnel) | whatever the backend serves: `qwen`, `qwen3.8-flash-next-a5b` (`curl -s host.docker.internal:8000/v1/models`) |
| `ollama`    | `host.docker.internal:11434` (SSH tunnel) | `qwen3.5:4b`, `qwen3.5:35b`                                      |
| `anthropic` | api.anthropic.com                         | `sonnet`, `opus`                                                 |

Resolution order for both `--backend` and `--model`:

1. **CLI flag** — `--backend vllm --model qwen`
2. **`.env.ralph`** in the repo root (git-ignored) — e.g. `RALPH_BACKEND=vllm` and `RALPH_MODEL=qwen`, one per line
3. **Built-in default** — `vllm` + `$VLLM_DEFAULT_MODEL` (which is `qwen` in this devcontainer)

The scripts set `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` themselves, so a plain shell works — no wrapper session needed.

### Examples

```bash
# Default: vllm + qwen, up to 10 iters on issue #42
agentic-workflow/ralph/afk.sh 42

# Single iteration, anthropic sonnet
agentic-workflow/ralph/once.sh 42 --backend anthropic --model sonnet

# Flash-Next backend, capped at 5 iters
agentic-workflow/ralph/afk.sh 42 5 --backend vllm --model qwen3.8-flash-next-a5b

# Anthropic opus for a hard issue
agentic-workflow/ralph/afk.sh 42 --backend anthropic --model opus

# Project-wide default via .env.ralph (no flags needed afterwards)
printf 'RALPH_BACKEND=vllm\nRALPH_MODEL=qwen\n' > .env.ralph
agentic-workflow/ralph/afk.sh 42
```

Each iteration follows `agentic-workflow/ralph/prompt.md`:

1. Reads the target issue body + last 5 commits
2. Pre-checks whether acceptance criteria are already satisfied (closes the issue if so)
3. Explores, then implements — surgical, in-scope changes only
4. Runs the plugin gates (`scripts/check.sh`, plus a `claude --plugin-dir .` load check), then `/code-review` on the diff, before commit
5. Stages only files in scope; one atomic conventional commit with `Closes #<N>`
6. Either closes the issue or comments progress

The kanban card is moved manually — this repo has no `move-issue.sh`.

## 6. Refactor — `/improve-codebase-architecture`

After the slice lands, look for tight coupling / shallow modules and consolidate. Feeds new ADRs back into step 1.

---

## Diagnostic side-loop

When ralph (or you) hits a hard bug, drop into `/diagnosing-bugs` — reproduce → minimise → hypothesise → instrument → fix → regression test. Result feeds back into the current issue, not a new one.

## What's missing / worth knowing

- `agentic-workflow/ralph/once.sh` runs `claude` with `--permission-mode acceptEdits` so the agent writes/edits without prompting, plus `--settings agentic-workflow/ralph/settings.ralph.json` (passed only if the file exists) — the allow-list of `git`/`gh`/`claude`/`scripts/check.sh` commands that keeps an AFK loop from stalling on permission prompts, with force-push denied. Make sure the issue scope is what you want before launching.
- `afk.sh` exits when `gh issue view <n>` reports `state == "CLOSED"`, or after `max-iters` (default 10). Ctrl-C otherwise.
- The script logs the resolved backend + model at start of each iteration: `ralph: backend=vllm model=qwen issue=#42`. Quick way to confirm routing.
- Local-backend (`vllm` / `ollama`) requires the HP-ZGX SSH tunnel to be up. Diagnose with `check-vllm` (defined in `.devcontainer/claude-aliases.sh`; Ollama on HP-ZGX is retired, so the `ollama` backend only works against another Ollama endpoint).
- Feedback gates are this plugin repo's own: `scripts/check.sh` (the `plugin.json` ↔ `skills/` drift guard, also `make check`) plus a `claude --plugin-dir .` load check. There is no unit-test framework; issues that touch the image or the dock step also need `make probe` / `make dock-e2e`.
- The kanban board is not wired into ralph — there is no `move-issue.sh` in this repo, so move cards by hand.
