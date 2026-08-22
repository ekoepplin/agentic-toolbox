# Keep vendored external skill sets out of version control; re-fetch from upstream

The toolbox integrates external **vendored skill sets** (see `CONTEXT.md`) — currently `mattpocock-skills` under `.agents/skills/`. We had to decide how that upstream code lives in this repo: committed directly (as a plain copy, submodule, or subtree), or kept in the working tree but excluded from version control.

We **do not commit vendored skill sets**. `.agents/skills/` is git-ignored, and the upstream files are fetched into the working tree out-of-band (clone/download from upstream) rather than tracked here.

Rationale:

- **Don't own code we don't develop.** As recorded in `CONTEXT.md`, a vendored skill set is consumed, not edited here. Committing hundreds of upstream files makes this repo's history and diffs about someone else's code — reviews, blame, and `grep` all get noisier for no benefit.
- **No stale fork.** A committed copy silently drifts from upstream and invites accidental local edits that never flow back. Keeping it out of the repo forces a clean re-fetch and keeps upstream as the single source of truth.
- **Smaller, clearer repo.** What this repo *owns* — local skills under `skills/`, the `.claude/` config, and `docs/` — stays front and center.

Consequences:

- **The set must be fetched after clone**, not obtained automatically with the repo. This needs to be documented (README / setup) and, ideally, scripted so a fresh clone is one command away from working.
- **Pin the upstream version out-of-band.** Since git history won't record which upstream revision is present, capture the expected version/commit in setup docs or a fetch script so environments are reproducible.
- **The existing nested `.git/` inside `.agents/skills/mattpocock-skills/` can stay** (it's the upstream clone) or be removed; either way it is now excluded from this repo via `.gitignore`.
