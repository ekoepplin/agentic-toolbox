# MATT-WORKFLOW.md

Matt Pocock workflow mapped to this repo's `agentic-workflow/ralph/` execution loop.

> **Local-only.** This whole `agentic-workflow/` directory is a development aid and is git-ignored — it never ships in the plugin or reaches GitHub (same rationale as the vendored skill set, `docs/adr/0001`). Run the scripts from the repo root; they resolve their own paths, so `agentic-workflow/ralph/afk.sh 2` works from anywhere in the tree.

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

This is where the `ralph/` folder fits. Both scripts target **one specific issue per invocation** — they do not auto-pick from the queue.

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
| `vllm`      | `host.docker.internal:8000` (SSH tunnel) | `qwen`, `aeon-ultimate`, `qwen36-ultimate`, `aeon-fast`, `aeon-deep`, `qwen36-ultimate-xs` |
| `ollama`    | `host.docker.internal:11434` (SSH tunnel) | `qwen3.5:4b`, `qwen3.5:35b`                                      |
| `anthropic` | api.anthropic.com                         | `sonnet`, `opus`                                                 |

Resolution order for both `--backend` and `--model`:

1. **CLI flag** — `--backend vllm --model qwen`
2. **`.env.ralph`** in the repo root — `RALPH_BACKEND=vllm`, `RALPH_MODEL=qwen` (see `.env.ralph.example`)
3. **Built-in default** — `vllm` + `$VLLM_DEFAULT_MODEL` (which is `qwen` in this devcontainer)

The scripts set `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` themselves, so you don't need to be inside a `claude-vllm` / `claude-zgx` wrapper session — a plain shell works.

### Examples

```bash
# Default: vllm + qwen, up to 10 iters on issue #2 (rename the skills)
agentic-workflow/ralph/afk.sh 2

# Single iteration, anthropic sonnet
agentic-workflow/ralph/once.sh 2 --backend anthropic --model sonnet

# Stronger local model, capped at 5 iters
agentic-workflow/ralph/afk.sh 2 5 --backend vllm --model aeon-ultimate

# Anthropic opus for a hard issue
agentic-workflow/ralph/afk.sh 4 --backend anthropic --model opus

# Project-wide default via .env.ralph (no flags needed afterwards)
cp .env.ralph.example .env.ralph
# edit RALPH_BACKEND / RALPH_MODEL
agentic-workflow/ralph/afk.sh 2
```

Each iteration follows `agentic-workflow/ralph/prompt.md`:

1. Reads the target issue body + last 5 commits
2. Pre-checks whether acceptance criteria are already satisfied (closes the issue if so)
3. Explores, then implements — surgical, in-scope changes only
4. Runs the plugin gates (`scripts/check.sh` once it exists, plus a `claude --plugin-dir .` load check), then `/code-review` on the diff, before commit
5. Stages only files in scope; one atomic conventional commit with `Closes #<N>`
6. Either closes the issue or comments progress

The kanban card is moved manually — this repo has no `move-issue.sh`.

## 6. Refactor — `/improve-codebase-architecture`

After the slice lands, look for tight coupling / shallow modules and consolidate. Feeds new ADRs back into step 1.

---

## Diagnostic side-loop

When ralph (or you) hits a hard bug, drop into `/diagnosing-bugs` — reproduce → minimise → hypothesise → instrument → fix → regression test. Result feeds back into the current issue, not a new one.

## What's missing / worth knowing

- `agentic-workflow/ralph/once.sh` runs `claude` with `--permission-mode acceptEdits` so the agent writes/edits without prompting. It also passes `--settings agentic-workflow/ralph/settings.ralph.json` **only if that file exists** — create one to allow-list the `git`/`gh`/`claude` commands ralph needs so an AFK loop doesn't stall on permission prompts. Make sure the issue scope is what you want before launching.
- `afk.sh` exits when `gh issue view <n>` reports `state == "CLOSED"`, or after `max-iters` (default 10). Ctrl-C otherwise.
- The script logs the resolved backend + model at start of each iteration: `ralph: backend=vllm model=qwen issue=#2`. Quick way to confirm routing.
- Local-backend (`vllm` / `ollama`) requires the HP-ZGX SSH tunnel to be up. Diagnose with `check-vllm` / `check-ollama` (defined in `.devcontainer/claude-aliases.sh`).
- Feedback gates are this plugin repo's own: `scripts/check.sh` (the `plugin.json`/README drift guard, once issue #5 lands) plus a `claude --plugin-dir .` load check. There is no build step, no `make`, and no unit-test framework — the plugin-load smoke-check is the behavioural check.
- The kanban board is not wired into ralph — there is no `move-issue.sh` in this repo, so move cards by hand.
