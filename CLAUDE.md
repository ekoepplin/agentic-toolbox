# agentic-toolbox

## Purpose

This repository is the **central Claude Code plugin** shared by all of its owner's local projects.

It serves as the single place where shared AI behavior is defined — behavioral guidelines, reusable
skills, agent definitions, lifecycle hooks, and utility scripts. Individual project repositories
stay lean: they import this file and get consistent AI behavior without duplicating configuration.

This repo sits **on top of oh-my-claudecode (OMC)**, which provides the orchestration primitives
(ralph, autopilot, team, ultrawork, etc.). This toolbox holds personal defaults and workflow-specific
additions that don't belong in a framework.

## What lives here vs. in a project repo

| Here (`agentic-toolbox`) | In a project repo (`.claude/`) |
|---|---|
| Behavioral guidelines | Project-specific instructions |
| Shared, reusable skills | Skills tied to one codebase |
| Common lifecycle hooks | Project-specific hooks |
| Utility scripts | Project-specific scripts |
| Agent definitions | — |

## How other projects reference this

Host projects **dock** this base at runtime: `make dock HOST=<path>` scaffolds
the host's workbench stack, and the dock step wires every harness adapter on
each workbench start — shipped skills are then invocable as
`/agentic-toolbox:<skill-name>` inside the workbench (see
`docs/harnesses/dock-e2e.md`).

For the shared behavioral guidelines, a project's `CLAUDE.md` can import this
file:

```markdown
@~/repos/agentic-toolbox/CLAUDE.md
```

## Structure

```
agentic-toolbox/
├── .claude-plugin/  # Claude Code harness adapter manifest (plugin.json)
├── .devcontainer/   # Base image (Dockerfile), shell config, dock-step scripts, pin locks
├── skills/          # Shipped skills (one subdirectory + SKILL.md each); drafts in skills/in-progress/
├── agents/          # Custom subagent persona definitions
├── commands/        # Slash commands
├── hooks/           # Lifecycle hooks
├── scripts/         # check.sh (drift guard), dock-host.sh (scaffolder), dock-e2e.sh, setup-mac-voice.sh (docs/voice.md)
├── agentic-workflow/# Ralph AFK loop + task files
├── docs/            # ADRs, harness guides, agent docs
└── compose.yaml     # This repo's own workbench stack
```

---

# Behavioral guidelines

Guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Subagent Strategy

- Use subagents liberally to keep main context window clean.
- Offload research, exploration, and parallel analysis to subagents.
- One task per subagent for focused execution.
- Don't duplicate effort — if a subagent is researching something, don't search for the same thing yourself.

## 6. Self-Improvement Loop

- After ANY correction from the user: append to `agentic-workflow/tasks/lessons.md` with the pattern. Don't ask — just log.
- Write rules that prevent the same mistake.
- Review lessons at session start for relevant context.

## 7. Task Management

For multi-step tasks, write a plan to `agentic-workflow/tasks/todo.md` before starting:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```

Canonical task file paths:

- `agentic-workflow/tasks/todo.md` — task list and success criteria
- `agentic-workflow/tasks/plan.md` — current implementation plan. Overwrite when a new plan supersedes the previous one. Read before starting any non-trivial task.
- `agentic-workflow/tasks/lessons.md` — append-only lessons learned

---

## Agent skills

### Issue tracker

Issues are tracked in this repo's GitHub Issues via the `gh` CLI; external PRs are not a triage surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context layout — `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### AFK execution loop

`agentic-workflow/MATT-WORKFLOW.md` maps the think → plan → break down → execute → refactor pipeline onto this repo. The execute stage is the `agentic-workflow/ralph/` loop (`agentic-workflow/ralph/once.sh`, `agentic-workflow/ralph/afk.sh`) — an unattended agent that works one `ready-for-agent` issue per invocation. Read that doc before running or modifying ralph.

### Skill dependencies

External skills (mattpocock/skills) are **pinned** by ref in `.devcontainer/skills.lock`; `install-skills.sh` checks out exactly that ref, so the skill set is reproducible and doesn't drift on rebuild. Bump the pin with the `/update-project` skill — it reviews the upstream skill-set diff, updates the lock, and reconciles `agentic-workflow/*` against any renamed skills. Never bump by editing the lock blindly.

### Adapter-manifest drift guard

**Sync rule:** every shipped skill MUST be listed in `.claude-plugin/plugin.json`, and nothing listed may be missing on disk; draft skills under `skills/in-progress/` MUST NOT appear in `plugin.json`. This is the adapter-manifest contract — `plugin.json` is the Claude Code harness adapter's manifest, and only what it lists is wired into a docked workbench. `scripts/check.sh` enforces the invariant and exits non-zero on any drift. When you add, rename, or promote a skill, update `plugin.json`, then run `scripts/check.sh`.

### Verification

This repo has **no unit-test framework**. The gate is `scripts/check.sh` — the adapter-manifest drift guard, which exits non-zero on any mismatch between `plugin.json` and the skills on disk. Run it after any change that adds, renames, or promotes a skill. This overrides the unit-test framing of the §4 examples above.
