# REFINE

You refine ONE ticket (above) into an execution plan that a weaker local model (qwen, via the pi loop) will follow literally. You do not implement anything and you do not commit. Work in the target repo named in the MISSION line; read the code as of the base sha it gives (`git show <sha>:<path>` when your checkout differs).

Read the ticket body, every comment (an agent brief or owner comment there is part of the contract — fold it into the plan) and the code the ticket touches. Read `GLOSSARY.md` and `docs/adr/` when they exist.

# THE PLAN

Write the plan into the issue body with `gh issue edit <N> --repo <owner/name> --body-file - <<'EOF' … EOF`. Keep the ticket's own sections (What to build, Acceptance criteria, …) unchanged and put these two sections **last**, in this order. If the body already has them, **replace** them — there must be exactly one of each. Do not write a `<!-- ralph:plan … -->` marker; the harness stamps the plan after its gates pass.

````markdown
## Execution plan

Ordered steps, concrete enough to follow without exploring: which function, which line, what to add.

**Out of scope:** what qwen must not touch or "improve".

```files
path/to/existing-file
path/to/new-file (new)
```

## Verify

```
<command>  # AC1
<command>  # AC2 AC3
make check  # guard
```
````

Rules the harness checks (it rejects the plan otherwise):

- The files block lists every file the change touches, one per line; each exists at the base sha or is marked ` (new)`. qwen may change nothing else.
- Every Verify line is one shell command run from the repo root, ending in a tag: `# AC<n>` for the acceptance criteria it proves (numbered in their order in the ticket), or `# guard` for a check that must stay green (e.g. `make check`).
- Every acceptance criterion has at least one `# AC<n>` command that **fails on the base sha** and passes once the plan is done. Guards may pass on base.
- The plan states what is out of scope.
- Size limit (in the MISSION line): over it, do not write a plan — split the ticket (below).
- Verify uses only gates that run inside a workbench: `make check`, `make -o image probe`, `bash .devcontainer/scripts/probe-dock.sh`, plain shell checks. Never `make image`, `make probe`, `make probe-dock`, `make dock-e2e` or `docker compose`.

# VERDICT

End your reply with exactly one of these lines:

- `RALPH-REFINE: plan` — you wrote the plan into the body.
- `RALPH-REFINE: split #<a> #<b> …` — the ticket is over the size limit. Create the child tickets with `gh issue create` (each: `## Parent` with `#<N>`, What to build, Acceptance criteria, label `ready-for-agent`), remove any `## Execution plan` / `## Verify` from this ticket's body, and name the children here.
- `RALPH-REFINE: human <reason>` — qwen cannot do it: its runtime gate is `make image`, `make probe` or `make dock-e2e` (Mac only), a criterion cannot be checked by a command, or the ticket is unclear. Change nothing.

If a `# PREVIOUS ATTEMPT` section follows, the gates rejected your last plan: fix every finding it lists.
