# Distribute the toolbox as a Claude Code plugin via a marketplace

**Status:** superseded by [ADR-0003](0003-distribute-the-base-by-runtime-dock.md) — the plugin survives as the base's Claude Code harness adapter, but its marketplace delivery route is retired; the base is distributed exclusively by runtime dock.

The toolbox exists to be **installed into other repositories** and invoked there (see "Consumer repo" in `CONTEXT.md`). We had to choose how a consumer gets these skills, agents, commands, and hooks. The options considered:

- **Claude Code plugin + marketplace** — ship a `.claude-plugin/plugin.json` and a `.claude-plugin/marketplace.json`; a consumer runs `claude plugin marketplace add ekoepplin/agentic-toolbox` then installs the plugin. Skills become `/agentic-toolbox:<name>`.
- **Symlink installer script** — a script symlinks skills into `~/.claude/skills`, the approach the vendored `mattpocock-skills` uses for its *maintainers*.
- **Copy/paste per consumer** — no install mechanism; each repo copies the files it wants.

We distribute as a **Claude Code plugin, published through a marketplace** whose source is the `ekoepplin/agentic-toolbox` GitHub repo.

Rationale:

- **Namespaced, collision-free invocation.** Plugin skills are called as `/agentic-toolbox:<name>`, so they never clash with Matt's skills or a consumer's own — decisive because the author runs Matt's skills alongside these in the same sessions.
- **One canonical install, upgradable in place.** `marketplace add` + `plugin install` is a documented, repeatable path; consumers pull updates without re-symlinking or re-copying. The symlink script is a maintainer convenience, not a distribution channel.
- **Carries all five primitives.** A plugin bundles skills, subagents, commands, hooks, and MCP servers together — matching decision that the toolbox holds all of them, not skills alone.

Consequences:

- **`.claude-plugin/plugin.json` is the contract.** Only what it lists reaches consumers. This is what makes the **shipped/draft split** meaningful: `skills/in-progress/*` is absent from `plugin.json` and therefore never installed. `scripts/check.sh` guards `plugin.json` ↔ disk drift so a shipped skill can't silently go unregistered.
- **The plugin namespace defines the public API.** Renaming a skill or the plugin breaks consumers' `/agentic-toolbox:<name>` calls, so names are a compatibility surface (see the naming convention in `CONTEXT.md`).
- **Marketplace source is the GitHub repo.** The repo must stay a clean, cloneable plugin — which is *why* vendored third-party skills and their symlinks are kept out of version control (ADR-0001): a consumer adding the marketplace must not pull down Matt's skills.
- **The vendored `mattpocock-skills` set is not part of the plugin.** It is a local development aid only, wired in via the bootstrap script, never listed in `plugin.json`.
