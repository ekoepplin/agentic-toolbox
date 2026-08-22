# Agentic Toolbox

A Claude Code **plugin** that packages the author's own skills, subagents, commands, hooks, and MCP servers, and is installed into other repositories via a marketplace (see `docs/adr/0002`). Locally it also wires in a vendored external skill set as a development aid, which is never distributed.

## Language

**Plugin**:
The distribution unit and the identity of this repo as a whole. Defined by `.claude-plugin/plugin.json` and published through `.claude-plugin/marketplace.json`. A **Consumer repo** installs the plugin and invokes its skills as `/agentic-toolbox:<name>`. The plugin bundles the five Claude Code **component** types below.
_Avoid_: package, extension

**Component**:
Any of the five things a plugin can contain: a **skill**, a **subagent** (`agents/`), a **slash command** (`commands/`), a **hook** (`hooks/`), or an **MCP server** (`.mcp.json`). "Tool" is not a component type — what one might loosely call a tool is really a script owned by a skill, a slash command, or an MCP server. Use the precise component name.
_Avoid_: tool (too vague — name the actual component)

**Skill**:
A packaged unit of agent instructions defined by a `SKILL.md` file with YAML frontmatter (`name`, `description`). Claude Code loads it and follows its instructions in place of the default approach. A skill may ship a supporting script (e.g. Python under its `scripts/`); that script is a private detail of the skill, not a separately-installable thing. The shipped skills keep the `-local` suffix (`web-search-local`, `fetch-news-local`, `fetch-free-images-local`): it names their purpose — giving a **local model** web/news/image access to unblock itself — so it stays part of the name even once distributed. The `agentic-toolbox:` namespace scopes them; the suffix describes what they are for.
_Avoid_: command (a distinct component)

**Shipped skill** / **Draft skill**:
A **shipped skill** lives at `skills/<name>/` and is listed in `plugin.json`, so consumers receive it. A **draft skill** lives at `skills/in-progress/<name>/` and is absent from `plugin.json`, so it is never installed. `scripts/check.sh` enforces that every shipped component appears in both `plugin.json` and the README.
_Avoid_: promoted/unpromoted (Matt's bucket vocabulary; we use shipped/draft), WIP

**Consumer repo**:
A separate repository that installs this plugin from the marketplace and calls its components. The consumer is *not* this repo and its domain concepts (e.g. the "docoffeeright" coffee project) are not part of the toolbox's domain.
_Avoid_: downstream repo, client

**Vendored skill set**:
An external collection of skills (currently `mattpocock-skills`) fetched into the working tree under `.agents/skills/` as a **local development aid** — used to help build this repo, never shipped in the plugin. Kept out of version control and re-fetched from upstream rather than committed (see `docs/adr/0001`).
_Avoid_: third-party plugin, dependency (it is not installed as one)

**Local-dev bootstrap**:
The `scripts/` step a developer runs after cloning: it fetches the **vendored skill set** into `.agents/skills/` and symlinks its skills into `.claude/skills/` for use in this repo's own Claude sessions. Both `.agents/skills/` and `.claude/skills/` are git-ignored; only `.claude/settings.json` is committed.
_Avoid_: installer (that word is reserved for how a Consumer repo installs the plugin)

## Relationships

- The **plugin** contains many **components** (skills, subagents, commands, hooks, MCP servers)
- A **skill** is **shipped** or a **draft**; only shipped skills are listed in `plugin.json`
- A **Consumer repo** installs the **plugin** and invokes its components under the `agentic-toolbox:` namespace
- The **vendored skill set** is wired in by the **local-dev bootstrap** and is never part of the **plugin**

## Flagged ambiguities

- "tool" — the author's original phrase "tools, skills, and other things" collapsed to the five **component** types. There is no separate "tool" primitive; retired as a domain term.
- "-local" suffix — the skills are named `*-local`, meaning "gives a local model web/news/image access to unblock itself." A rename to drop the suffix was considered and reversed: the suffix names the skill's purpose, not merely a deployment context that goes away once distributed, so it is kept. The shipped skills are `web-search-local`, `fetch-news-local`, and `fetch-free-images-local`; the `agentic-toolbox:` namespace handles scoping.
- "skill" vs "plugin" — a **skill** is one `SKILL.md`-defined component; the **plugin** is the whole distributable repo that contains it. Keep them distinct.
- "installer" vs "bootstrap" — installing the **plugin** into a **Consumer repo** (marketplace) is distinct from the **local-dev bootstrap** that wires Matt's skills in for development. Don't conflate them.
