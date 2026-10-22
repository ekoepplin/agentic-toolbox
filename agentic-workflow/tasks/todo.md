# Task: remove the `-local` skills, refactor, speed up, refresh docs (2026-10-22)

Owner request: remove all local skills; refactor; make it faster; apply best
practice; update docs; validate carefully.

## Steps

1. [x] Remove `skills/{web-search,fetch-news,fetch-free-images}-local` and every
   reference (plugin.json, Dockerfile, devcontainer.json API keys, Makefile
   probe, probes, docs, CONTEXT.md glossary)
   → verify: `grep -rn -- '-local\b'` finds only unrelated hits (`ollama-local`,
   `connecting-local-models`, `start-local-setup`)
2. [x] Faster image: drop the skill-only venv deps (newsapi-python, loguru, duckdb,
   tavily-python, requests) and the unused `ccstatusline` (status line is
   claude-powerline via managed settings)
   → verify: `make probe` green
3. [x] Probes derive the shipped-skill list from `plugin.json` instead of
   hard-coding names/counts; the pi `get_commands` probe stops at the response
   instead of a fixed `sleep 8`
   → verify: `make probe-dock` / `make dock-e2e` green
4. [x] `scripts/check.sh` portable to macOS bash 3.2 (no `mapfile`), fails on an
   unparsable `plugin.json`; `make check` target
   → verify: green on the tree under `/bin/bash` 3.2 and bash 5; each drift case
   exits 1 in a scratch copy
5. [x] Ralph: one shared `lib.sh` for env/arg parsing/issue context/AFK loop
   (removes four-way duplication); fix the force-push guardrail regex
   (`git push --force` was not blocked); delete the finished one-off `chain.sh`
   (#8–#14 all closed)
   → verify: `bash -n`; usage/arg errors; regex table test
6. [x] Docs: README, CLAUDE.md, CONTEXT.md, MATT-WORKFLOW.md, ralph-on-pi.md,
   copilot.md, dock-e2e.md, configuration.md, prompts — drop removed skills and
   stale claims (git-ignored `agentic-workflow/`, `.env.ralph.example`,
   `setup-pi.sh`, "once check.sh exists", inlined script copies)
   → verify: stale-term greps clean; links resolve
