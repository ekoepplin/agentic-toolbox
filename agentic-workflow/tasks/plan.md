# Plan: ralph the base/dock refactor unattended (issues #8–#14)

Supersedes the plugin-plan (issues #1–#5, done). This is the current
implementation plan.

## What this is

Seven tracer-bullet tickets, #8–#14, that convert this repo into a dockable
agentic development **base** (the domain decisions were locked in the
grill session 2026-09-11; `CONTEXT.md` on master already carries the
vocabulary — commit 46626c8). This plan defines how to work them with
ralph on pi, with zero human intervention until they are all closed.

## Dependency graph

```
#8 image ──┬── #9 dogfooded workbench ── #10 dock step ──┬── #12 dock E2E ── #13 retire routes ── #14 record decisions
           └── #11 scaffolder ───────────────────────────┘
```

Chain order: **8 → 9 → 10 → 11 → 12 → 13 → 14**. One ticket per ralph
invocation, fresh context each time (frontier discipline).

## Where ralph runs

Mac host, pi backend (`pi-afk.sh`), provider `vllm-hpzgx/qwen` — the
proven E2E path (scratch issue #7, commit 0fdf742). **Not inside a
container:** ticket #9 rebuilds the base's own devcontainer, and we do
not run the platform-under-construction inside itself. Docker on the Mac
is the daemon the tickets orchestrate (`make image`, `compose up`).

## The unattended loop (`agentic-workflow/ralph/chain.sh`)

For each ticket N in order:

1. `git checkout -B ralph/tN origin/master` — fresh branch, fresh context.
2. `pi-afk.sh N 10` — polls the issue state; each iteration is a fresh pi
   session with the mission (issue body + last 5 commits + `prompt-pi.md`).
3. The agent: implements → runs gates (`check.sh`, ticket-specific
   acceptance probes) → two-axis self code-review → one atomic commit with
   a `Closes #N` trailer → **pushes the branch and squash-merges its own
   PR to master** (the UNATTENDED MERGE section in `prompt-pi.md`, added
   2026-09-11). The merge to master fires the trailer → issue auto-closes.
4. `pi-afk.sh` sees CLOSED → exits → the driver verifies, pulls master,
   moves to the next ticket.

**Halt condition:** a ticket that is not CLOSED after its iteration
budget (default 10) stops the whole chain with a resume command printed.
The chain never auto-skips and never works two tickets in one context.

## Safety valves standing between agent and master

- Gates must pass before commit (prompt: "Do not commit on red").
- Two-axis self code-review before commit (prompt).
- Force-push blocked (`.pi/extensions/ralph-guardrail.ts`).
- One ticket = one branch = one squash-merged PR: full post-hoc audit trail.
- The chain halts on the first non-closed ticket; it cannot drift ahead.

## Pre-flight (one-time, human, ~5 min)

- [x] master clean; new-vocabulary `CONTEXT.md` committed (46626c8)
- [ ] Docker running (`docker ps` healthy)
- [ ] Local model reachable: `pi --list-models` shows `vllm-hpzgx qwen`
      (Mac Mini tunnel up)
- [x] `prompt-pi.md` carries the UNATTENDED MERGE section
- [ ] Nothing else mutating this repo (no other ralph/agent session)

## How to run

```
tmux new -s ralph
cd ~/repos/agentic-toolbox
./agentic-workflow/ralph/chain.sh 2>&1 | tee /tmp/ralph-chain-$(date +%F).log
```

Monitor: `tmux attach -t ralph` locally, or from the phone
`ssh -p 2224 <mac-mini>` → `tmux attach -t ralph`.
Each ticket prints a status line; per-iteration detail goes to the log.

## Remaining human intervention points (the honest list)

1. **Launch** — the one command above.
2. **Ticket #9 VS Code smoke** — the agent verifies every probe it can run;
   the "open the base in VS Code" acceptance line is a ~30-second human
   click after #9's PR lands. If it fails, the old devcontainer definition
   is still there (expand-contract is written into #9's acceptance).
3. **Halt triage** — only if a ticket burns its iteration budget.
4. **Post-hoc PR review** — optional, non-blocking, all seven PRs.

## Cost note

Each iteration = one full pi session on qwen via the Mac Mini endpoint.
7 tickets × default max 10 iterations = up to ~70 sessions; with the spec
at this precision expect 1–3 iterations per ticket. Wall time is
dominated by the model, not the gates.

## Known risks

- #9 is the only ticket that touches the daily-driver devcontainer;
  expand-contract is in its acceptance criteria.
- #12 orchestrates Docker from the Mac on a scratch project; a port
  collision with a manually running devcontainer is the agent's to route
  around (port assignment is #11's job).
- The in-progress `.gitignore` change on `docker-compose-poc` (committing
  `agentic-workflow/`, with a mangled `.pi/` line) is a separate VCS-boundary
  decision — under the dock model ralph's loop probably becomes committed
  base content, but that decision belongs to its own ticket, not to pre-flight.
