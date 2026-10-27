# Task: split ralph loop — Opus plans and reviews, pi/qwen executes (#25)

Design and decisions: `agentic-workflow/tasks/plan.md`. GitHub issues are the
source of truth; this list mirrors them (state as of 2026-10-27). Tag = the
issue's triage label (`docs/agents/triage-labels.md`).

## Ready now (no open blockers)

1. [ ] #31 `ready-for-agent` — Opus refine writes a stamped plan that passes the plan gates
   → verify: a real ticket gets plan + files + Verify + marker; criterion without red-on-base check rejected; oversized plan split; Mac-only gates routed to ready-for-human
2. [ ] #35 `ready-for-agent` — escalate stuck tickets (needs-opus after 3 red) and refuse stale plans
   → verify: forced-red scratch issue ends labelled needs-opus; editing a planned file after stamping makes the loop refuse
3. [ ] #52 `ready-for-agent` — guardrail for every pi session in every workbench
   → verify: host workbench pi blocks push to default branch + gh pr merge; base loads it once; probe-dock asserts it
4. [ ] #53 `ready-for-agent` — generic pi prompt for host projects
   → verify: prompt-pi.md names no repo or base-only facts; base run keeps the same contract
5. [ ] #54 `ready-for-agent` — `ralph-onboard.sh <host>`: ruleset, labels, bot access, BOT_* in compose
   → verify: second run changes nothing; bot push/self-merge refused on the host afterwards
6. [ ] #41 `ready-for-human` — reviewer bot account (needed from #32 on)
   → verify: second account with write + PAT in pass; can approve and merge a datadidact-bot PR
7. [ ] #55 `ready-for-human` — bot identity survives workbench recreates
   → verify: recreating any workbench keeps as-bot = datadidact-bot; token in no repo file

## Blocked

8. [ ] #32 `ready-for-agent` — Opus review: hard gates + bounded redo loop · blocked by #41
9. [ ] #33 `ready-for-agent` — Opus review: evidence-backed rubric score · blocked by #32
10. [ ] #34 `ready-for-agent` — golden set of known-bad PRs + replay runner · blocked by #33
11. [ ] #37 `ready-for-agent` — metrics collector + autonomy ladder state · blocked by #33
12. [ ] #36 `ready-for-human` — L0 shadow run: five real tickets, owner merges · blocked by #31 #33 #34
13. [ ] #38 `ready-for-agent` — meta loop: retro → one improvement → keep or revert · blocked by #34 #36 #37
14. [ ] #56 `ready-for-human` — first host run: CONTEXT.md → GLOSSARY.md in sprungjob via the loop · blocked by #52 #53 #54 #55

## Done

- [x] #26 `ready-for-human` — which gates run inside a workbench (document-only)
- [x] #27 `ready-for-human` — master ruleset + datadidact-bot executor identity
- [x] #28 `ready-for-agent` — no upstream draft skills in Claude Code / Copilot
- [x] #39 `ready-for-agent` — no upstream draft skills in pi
- [x] #29 `ready-for-agent` — qwen ticket ends in a PR gated by harness-run Verify (experiment #42 → PR #48, 10/10)
- [x] #30 `ready-for-agent` — stamped plans, snapshot, scope gate
- [x] #51 `ready-for-agent` — loop targets the repo it runs in (host e2e on haus-daten-am-rankrain)
