# Keep vendored external skill sets out of version control; re-fetch from upstream

The toolbox integrates external **vendored skill sets** (see `CONTEXT.md`) — currently `mattpocock-skills` under `.agents/skills/`. We had to decide how that upstream code lives in this repo: committed directly (as a plain copy, submodule, or subtree), or kept in the working tree but excluded from version control.

We **do not commit vendored skill sets**. `.agents/skills/` is git-ignored, and the upstream files are fetched into the working tree out-of-band (clone/download from upstream) rather than tracked here. Under the runtime-dock distribution model (ADR-0003) the vendored set *is* distributed: the dock step (`.devcontainer/scripts/install-skills.sh`) fetches the pinned set into the base's git-ignored `.agents/skills/` on every workbench start — the base's own and every host's. The invariant is therefore **never committed**, not never distributed.

Rationale:

- **Don't own code we don't develop.** As recorded in `CONTEXT.md`, a vendored skill set is consumed, not edited here. Committing hundreds of upstream files makes this repo's history and diffs about someone else's code — reviews, blame, and `grep` all get noisier for no benefit.
- **No stale fork.** A committed copy silently drifts from upstream and invites accidental local edits that never flow back. Keeping it out of the repo forces a clean re-fetch and keeps upstream as the single source of truth.
- **Smaller, clearer repo.** What this repo *owns* — local skills under `skills/`, the `.claude/` config, and `docs/` — stays front and center.

Consequences:

- **The set must be fetched**, not obtained automatically with the repo. The dock step is that script: `install-skills.sh` fetches the pinned set into `.agents/skills/` on every workbench start, only when it is missing or the pin has changed.
- **Pin the upstream version out-of-band.** Since git history won't record which upstream revision is present, the pin lives in `.devcontainer/skills.lock`, which the dock step checks out exactly — environments are reproducible without the commit being tracked.
- **The existing nested `.git/` inside `.agents/skills/mattpocock-skills/` can stay** (it's the upstream clone) or be removed; either way it is now excluded from this repo via `.gitignore`.
