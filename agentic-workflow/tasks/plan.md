# Plan: Opus thinks, pi/qwen executes — the split ralph loop

Supersedes the Copilot-harness plan (implemented 2026-10-17 — see git history
of this file and `docs/harnesses/copilot.md`). Status: **proposed 2026-10-27**,
not started. Prerequisite done the same day: mattpocock/skills pinned to
`59db609` (main, 49 fixes past v1.3.1), `CONTEXT.md` → `GLOSSARY.md`
(upstream rename in v1.3.0), `docs/agents/` refreshed from the upstream templates.

## Goal

Claude Opus (with the owner) grills, specs, slices and **refines** every ticket;
pi + local qwen **executes** it; Opus **reviews and merges**. Expensive tokens
go to judgement, free local tokens go to typing — and qwen's work is gated by
checks the harness runs, never by qwen's own claim that it is done.

## Evaluation of the vendored skills for this split (pin 59db609)

| Skill | Invocation | Role in the split | Fit / caveat |
|---|---|---|---|
| `grill-with-docs` (→ `grilling` + `domain-modeling`) | user | Think: owner + Opus | ✅ Interactive by design — it questions the human, so this stage cannot be AFK. Now reads `GLOSSARY.md`. |
| `to-spec` | user | Spec: Opus | ✅ But it labels the spec issue `ready-for-agent` itself — the spec must never be dispatched to qwen (see contract rule 1). |
| `to-tickets` | user | Break down: Opus + owner | ✅ Native blocking edges + sub-issues (gh 2.92 here → the `gh api` fallbacks in `docs/agents/issue-tracker.md`). ⚠️ Deliberately **no file paths**, slices sized "for a fresh context window" — sized for a strong agent, not qwen. |
| `triage` + `AGENT-BRIEF.md` | user | Optional gate | ⚠️ The brief — "the contract" — is posted as a **comment**; `ralph_mission` reads only the issue body, so qwen never sees it today. Also behavioural, no paths. |
| `implement` | user | — | ❌ Not for qwen: assumes typecheck + test suite + `tdd` (none here) and has no staging/scope discipline. The ralph prompt stays the executor contract. |
| `implement-spec` | user | — | ❌ Claude Code subagents + worktrees with a strong orchestrator; future option for Opus-only runs, not this loop. |
| `code-review` | model | Review: Opus | ✅ Strong fit for the Opus gate (Standards + Spec, spec found via `Closes #N`). ❌ Drop it from the qwen prompt: it spawns two sub-agents (pi needs `pi-subagents`, again qwen) — qwen grading qwen adds tokens, not signal. |
| `tdd`, `diagnosing-bugs` | model | — | Mostly N/A: no test framework. `diagnosing-bugs` stays the human/Opus side-loop. |
| `retro` | user | After a batch: Opus | ✅ Turns repeated qwen failures into checks/standards (fits CLAUDE.md §6). |
| `pr` | model | PR body | Optional for qwen's PR; low value. |
| `wayfinder` | user | — | Skip: for foggy multi-session efforts; overlaps grill → spec. |

**Central tension.** Matt's skills keep tickets behavioural and path-free
because "paths go stale" and the executor is assumed to explore well. qwen
needs the opposite: files, steps, explicit out-of-scope, executable checks.
Resolution: keep upstream tickets as they are, and add a **just-in-time refine**
step that Opus runs *immediately before dispatch*, pinned to the commit it was
written against. Staleness is then detectable instead of a reason to omit detail.

## The execution contract (what makes the split safe)

1. **qwen runs only refined tickets.** The issue body must carry an
   `## Execution plan` block written by Opus (marker line
   `<!-- ralph:plan base=<sha> -->`). No block → `pi-once.sh` refuses. This also
   keeps spec issues (labelled `ready-for-agent` by `to-spec`) out of qwen's hands.
2. **Plan lives in the body**, not a comment: `ralph_mission` already injects the
   body. Refine folds any agent brief / comments into it.
3. **Plan shape:** files to touch, ordered steps, out of scope, and a
   `## Verify` fenced block — one shell command per line, each must exit 0.
4. **The harness verifies, not the model.** After each qwen iteration `lib.sh`
   runs the `## Verify` commands itself. Red → next iteration with the failure
   output appended to the mission. Green → done for qwen.
5. **qwen never merges.** It pushes a branch and opens a PR. Enforced in the
   harness, not just the prompt: `.pi/extensions/ralph-guardrail.ts` also blocks
   `gh pr merge` and `git push` to `master` (the bot token can merge, so prompt
   wording alone is not a control).
6. **Opus reviews and merges.** `code-review` against the issue + plan, re-run
   `## Verify`, then merge, or comment "changes requested" and re-queue.
7. **Escalation, not looping.** After N red iterations (default 3, not 10) the
   loop labels the issue `needs-opus`, comments the last verify output, stops.
8. **Staleness.** If any file listed in the plan changed between `base=<sha>`
   and `HEAD`, refuse and ask for a re-refine.

```
owner+Opus: grill-with-docs → to-spec → to-tickets        (interactive)
Opus:       refine.sh <N>   → ## Execution plan + ## Verify in body
qwen (pi):  pi-afk.sh <N>   → iterate until harness-run Verify is green → PR
Opus:       review.sh <N>   → code-review + Verify → merge | changes requested
            red ×3          → needs-opus → once.sh <N> --backend anthropic --model opus
Opus:       retro            (after a batch)
```

## Tickets (tracer-bullet order; each lists its own verify)

0. **Spike: can the gates run inside a workbench?** `make probe` /
   `make dock-e2e` from inside a workbench over the mounted Docker socket.
   Suspected break: `dock-e2e.sh` creates its scratch host under the
   container's `/tmp`, a path the Mac's daemon cannot bind-mount (and colima
   shares only `~`). Outcome decides which verify commands qwen may use.
   *ready-for-human.* → verify: both targets attempted in a workbench, result
   recorded in `docs/harnesses/dock-e2e.md`.
1. **Stop wiring upstream drafts.** `install-skills.sh` links upstream
   `skills/in-progress/*` (7 today, incl. new `chief-of-staff`) into every
   harness; skip `in-progress` like `deprecated`.
   → verify: `! readlink .claude/skills/* | grep -q /in-progress/`; `make probe-dock` green.
2. **Harness-run verify + PR-only qwen** (first end-to-end slice, plan written
   by hand). `lib.sh`: parse `## Verify` from the body and run it after each
   iteration; `pi-afk.sh` ends on green verify + open PR instead of
   `CLOSED`; `pi-once.sh` refuses without a plan block. `prompt-pi.md`: drop
   UNATTENDED MERGE (also removes the broken `gh pr create --squash`), drop
   qwen's `code-review` step, fix the `tasks/drafts` path. Guardrail blocks
   `gh pr merge` / push to `master`.
   → verify: scratch issue with a hand-written plan → PR opened, issue still
   open; `bash -n` on ralph scripts; guardrail regex table test; a planless
   issue is refused.
3. **`refine.sh` + `prompt-refine.md`** (Opus, via the `once.sh` launch path):
   reads body + comments + code, writes the plan block with `base=<sha>`.
   → verify: on a real `to-tickets` ticket the body gains both sections and
   `lib.sh`'s parser extracts ≥1 verify command; re-run replaces, not appends.
4. **`review.sh` + `prompt-review.md`** (Opus): `code-review` on the PR vs the
   issue, re-run verify, merge or comment + re-queue.
   → verify: one green PR merged and issue auto-closed; one deliberately bad PR
   gets "changes requested" and stays open.
5. **Escalation + staleness.** 3 red iterations → `needs-opus` label + comment;
   plan-file drift since `base` → refuse with a re-refine message.
   → verify: forced-red scratch issue ends labelled `needs-opus` after 3 iters;
   touching a planned file after refine makes `pi-once.sh` refuse.
6. **Docs.** `MATT-WORKFLOW.md`, `ralph-on-pi.md`, `docs/agents/triage-labels.md`
   (`needs-opus`), lessons.
   → verify: stale-term grep (`UNATTENDED MERGE`, `--squash --merge`) clean.

Then: run a batch of 3–5 real tickets, `retro`, tune N and the plan template.

## Revision 2026-10-27 (b): evaluated loop, earned autonomy, self-improvement

Validation of the earlier assumptions (checked against GitHub and the code):

| Earlier claim | Verdict | Correction |
|---|---|---|
| The pi guardrail is the real merge separation | ❌ overclaimed | A regex on bash commands is bypassable (`gh api …/merge`, `git push origin HEAD:master`, a script that runs `gh pr merge`). `master` has **no branch protection** today. The control is identity + protection: ruleset on `master` (PR required, 1 approval, no bypass) and a reviewer identity ≠ the qwen bot. Guardrail stays as defence in depth. |
| Verify commands in the issue body are the contract | ❌ tamperable | The bot token can `gh issue edit --body`. Refine stores the plan hash in its marker; the harness verifies the hash and runs verify from that snapshot. |
| "Verify passes" means done | ⚠️ partial | qwen can edit the scripts a verify command calls (e.g. make `check.sh` exit 0). The scope gate fails any diff that touches a file a verify command depends on unless the plan lists it. Verify runs in a clean `git worktree` at the PR head. |
| Every verify command must be red on base | ⚠️ too strict | Guard checks (`make check`) are legitimately green on base. Rule: every acceptance criterion needs ≥1 red-on-base check; guards may be green. |
| 0–2 anchored scales beat 1–10 | ⚠️ literature, not measured here | LLM-as-judge work reports poor calibration on wide scales; treat as a hypothesis, calibrate against the owner (L0 below). |
| The triage labels exist | ❌ | Only `ready-for-agent` exists. Create `needs-triage`, `needs-info`, `ready-for-human`, `needs-opus`. |
| qwen can carry real tickets | ❓ unknown | Evidence: one +9-line doc edit (#7). Autonomy must be earned by measured pass rate, not assumed. |
| Opus can run `/to-tickets` AFK | ❓ untested | It is user-invoked and ends in "iterate until the user approves". Whether `claude -p` expands it is untested; by design, think → spec → breakdown stay owner touchpoints. |

### Pipeline

```
owner+Opus  grill → spec → tickets (owner approves)        human anchor = the goals
Opus        refine   → plan + verify; plan gates (script) → redo ≤2 → else needs-opus
qwen (pi)   execute  → harness-run verify in clean worktree → PR
Opus        review   → hard gates (script) → rubric score + evidence → pass | redo ≤2 | needs-opus
Opus        meta     → every K merged tickets: retro on metrics → ≤1 improvement PR → evaluated → kept or reverted
```

### Autonomy ladder (promotion by evidence, demotion on failure)

| Level | Loop may | Promote when | Demote when |
|---|---|---|---|
| L0 shadow | refine, execute, score; **owner merges** | owner/Opus pass-fail agree on ≥4 of 5; golden set 100 % caught | — |
| L1 auto-merge | Opus merges passing PRs; owner audits 1 in 3 | 10 merges, 0 reverts, escalation < 30 % | any revert or owner-overruled pass |
| L2 frontier | picks the next unblocked refined ticket itself | 20 merges at L1 within the thresholds | same |
| L3 follow-ups | files out-of-scope review findings as `needs-triage` issues (never `ready-for-agent`) | owner opt-in | junk-issue complaints |

Kill switches at every level: a `ralph:stop` label/file checked before each step, a
max-tickets-per-run cap and a daily Opus budget.

### Metrics (the goals, measured per ticket in a JSON review comment)

- **Correctness:** review pass, post-merge revert or fix-up within 14 days (lagging truth).
- **Autonomy:** owner touches per ticket, escalation rate.
- **Efficiency:** qwen iterations, review rounds, Opus tokens per merged ticket.
- **Evaluator health:** owner/judge agreement, golden-set catch rate.

A collector script aggregates them from issue comments, so there is no extra store
and no bot commits.

### Self-improvement (what may change itself, and how)

| Layer | Changed by | Gate |
|---|---|---|
| Executor lessons (capped list injected into `prompt-pi.md`) | meta loop | normal review loop |
| Executor prompt, plan template, ticket size limit | meta loop, ≤1 change per cycle | golden set + replay of the cycle's failed tickets; kept only if the next 2 batches do not regress, else auto-revert |
| Rubric, thresholds, hard gates, golden set, ladder rules | **owner only** | the loop may propose; it may never merge evaluator changes (no grading its own exam) |

Every caught escape (a revert, an owner-overruled pass) becomes a new golden-set
case, so the evaluator gets stricter wherever it was fooled.

Caveat: batches of 5 are noisy. Read direction over two batches, never one, and
expect the first improvements to come from lessons and checks, not prompt tuning.

### Ticket delta

- **New 0b:** a ruleset on `master` + a reviewer identity separate from the qwen bot; create the missing labels.
- **3** gains the plan gates and the plan hash.
- **4** gains the hard gates, the rubric with evidence, the redo loop and the JSON score.
- **New 4b:** golden set (out-of-scope, missing criterion, fake green, tampered verify script) plus a replay runner.
- **New 7:** metrics collector and ladder state.
- **New 8:** meta loop (`retro` → ≤1 improvement PR → evaluate → keep/revert).
- Order: 0 → 0b → 1 → 2 → 3 → 4 → 4b → run at L0 → 5 → 7 → 8.

## Decisions (owner, 2026-10-27)

1. **Pin:** keep `59db609` (main, unreleased fixes to `code-review`,
   `to-tickets` sub-issues, `implement`, tracker template); move to the next
   upstream tag when one is cut.
2. **Who merges:** Opus via `review.sh`, as a **second bot account** dedicated
   to review — never the qwen bot. The `master` ruleset requires its approval,
   so the qwen bot cannot merge on its own (supersedes the "guardrail is the
   real separation" note; see the validation table above).
3. **Ticket size:** refine splits oversized tickets (over the plan size limit)
   into child tickets; `to-tickets` keeps its upstream sizing.
4. **Scope:** this repo only (`REPO` stays hard-coded in `lib.sh`);
   host-project support is a later plan.
5. **Gates inside a workbench (#26): document only.** qwen's verify commands
   use only the gates that work in a workbench (`make check`,
   `bash .devcontainer/scripts/probe-dock.sh`, `make -o image probe`, plain
   shell checks); refine routes tickets whose runtime gate is `make image`,
   `make probe` or `make dock-e2e` to `ready-for-human` (Mac-side). See
   `docs/harnesses/dock-e2e.md` → *Running the gates inside a workbench*.

## Out of scope

- Auto-picking the frontier (explicit issue numbers stay; the tracker doc's
  "Count open blockers" command makes it a later, small addition).
- Running Opus through pi (`--backend anthropic` on pi) — Claude Code stays the
  Opus harness.
- The brain/hands sandbox idea (`Pi Brain Hands-Setup.md`) — separate ADR.
