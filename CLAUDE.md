# agentic-toolbox

## Purpose

This repository is the **central Claude Code plugin** for all of ekoepplin's local projects.

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

Add to the project's `CLAUDE.md`:

```markdown
@/Users/ekoepplin/repos/agentic-toolbox/CLAUDE.md
```

To also load skills and hooks, start Claude with:

```bash
claude --plugin-dir ~/repos/agentic-toolbox
```

Or permanently via shell alias in `~/.zshrc`:

```bash
alias claude='claude --plugin-dir ~/repos/agentic-toolbox'
```

Skills are then available as `/agentic-toolbox:<skill-name>`.

## Structure

```
agentic-toolbox/
├── skills/          # Reusable slash-command skills (one subdirectory + SKILL.md each)
├── agents/          # Custom subagent persona definitions
├── hooks/hooks.json # Lifecycle hooks: PreToolUse, PostToolUse, SessionStart, Stop
├── scripts/         # Shell scripts invoked by hooks or skills
├── bin/             # CLI executables (claude-toolbox wrapper, etc.)
└── settings.json    # Default Claude Code settings when plugin is active
```

---

## Behavioral Guidelines

These travel with every project that imports this file. They bias toward caution over speed —
use judgment on trivial tasks.

### 1. Think Before Coding

Before implementing: state assumptions explicitly. If uncertain, ask. If multiple interpretations
exist, present them — don't pick silently. If a simpler approach exists, say so. If something is
unclear, stop and name what's confusing.

### 2. Simplicity First

Minimum code that solves the problem. No features beyond what was asked, no abstractions for
single-use code, no unrequested "flexibility", no error handling for impossible scenarios.
If 200 lines could be 50, rewrite it.

### 3. Surgical Changes

Touch only what you must. Don't improve adjacent code, comments, or formatting. Match existing
style. If you notice unrelated dead code, mention it — don't delete it. Remove only
imports/variables/functions that your changes made unused.

Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

Transform tasks into verifiable goals before starting. For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```

Strong success criteria enable independent looping. Weak criteria require constant clarification.

---

## Plugin Drift Guard

**Sync rule:** every shipped skill MUST be listed in both `.claude-plugin/plugin.json` and the
README, and nothing listed may be missing on disk; draft skills under `skills/in-progress/` MUST
NOT appear in `plugin.json`. `plugin.json` is the only thing that reaches consumers, so this is the
plugin contract. `scripts/check.sh` enforces the invariant and exits non-zero on any drift. When you
add, rename, or promote a skill, update `plugin.json` **and** the README together, then run
`scripts/check.sh`.
