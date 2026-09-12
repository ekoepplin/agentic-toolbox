# Task: deliver issue #13 — retire the old delivery routes

Spec: GitHub issue #13. Plan-of-record for the chain: `plan.md` (#8–#14).
#14 owns the full rewrite (new ADRs, glossary, "around docking") — #13 is the
surgical retirement: delete the routes, narrow the guard, strip retired-route
descriptions from docs.

## Success criteria (from the issue)

1. [x] `.claude-plugin/marketplace.json` deleted; no doc instructs a
      marketplace install → verify: `git ls-files | grep marketplace` empty;
      grep for `marketplace add`/`plugin install` across tracked docs
2. [x] `scripts/bootstrap-dev.sh` deleted; fetch logic reachable only through
      the dock step → verify: `install-skills.sh` still called by `dock.sh`,
      header no longer references the bootstrap
3. [x] Drift guard fails on each drift case: shipped component missing from
      the manifest, missing on disk, listed but absent, draft leaked into the
      manifest → verify: four negative cases in a scratch copy, each exits 1
4. [x] Drift guard passes on the correct tree → verify: `bash scripts/check.sh`
      green in the live tree
5. [x] README + top-level docs no longer describe the retired routes →
      verify: README/CLAUDE.md/CONTEXT.md greps clean (dock pointer instead)

## In-scope files

- delete: `.claude-plugin/marketplace.json`, `scripts/bootstrap-dev.sh`
- edit: `scripts/check.sh` (guard narrows to the adapter-manifest contract),
  `.claude-plugin/plugin.json` (description no longer claims marketplace
  distribution), `.devcontainer/scripts/install-skills.sh` (header),
  `README.md`, `CLAUDE.md`, `CONTEXT.md` (bootstrap marked *Retired.*, dock
  bullet, Dock _Avoid_ line), `docs/harnesses/dock-e2e.md` ("plugin contract"
  → "adapter-manifest contract")

## Out of scope (issue #14)

- New ADRs; superseded pointer on ADR-0002; ADR-0001 wording
- Full rewrite of README / CLAUDE.md "how other projects reference this"
  around docking; glossary vocabulary pass

## Working-tree hazards (do NOT stage)

- `.gitignore` has an in-progress WIP edit (mangled `.pi/` line) — unrelated
- untracked: `.pi/`, `agentic-workflow/`, `agentic-workflow-notes/`
