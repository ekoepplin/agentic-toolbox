# Agentic Toolbox

An agentic development **base**: an environment (docker image + compose) plus shared agentic content (skills, subagents, commands, hooks, workflows, docs) that other projects **dock** into at runtime to get agentic development across one or more **harnesses**. The Claude Code **plugin** is one of the base's **harness adapters**, not the repo's identity (supersedes `docs/adr/0002`). Locally it also wires in a vendored external skill set as a development aid, which is never distributed.

## Language

**Base**:
The identity of this repo: a self-contained agentic development environment (docker image + compose stack) together with the shared agentic content — skills, subagents, commands, hooks, workflows, docs — that projects mount in at runtime to get working agent sessions across all supported **harnesses**.
_Avoid_: foundation, platform, toolbox (the repo's name, not a domain term)

**Harness**:
An agent runtime that executes sessions and discovers the base's content through its own conventions. Today: Claude Code and pi. The base ships one **harness adapter** per harness.
_Avoid_: agent (conflicts with Claude's subagent concept), engine

**Harness adapter**:
The per-harness packaging that delivers the base's content to one specific harness: for Claude Code, the **plugin** (`.claude-plugin/`); for pi, the `.pi/` configuration and extensions. An adapter is a delivery mechanism, not a component.
_Avoid_: integration, "plugin" (that word belongs to the Claude Code adapter only)

**Plugin**:
The Claude Code **harness adapter**. Defined by `.claude-plugin/plugin.json`; inside a docked **workbench** Claude Code loads it from the mounted base. Its former marketplace delivery route is retired (supersedes `docs/adr/0002`). The plugin bundles the five Claude Code **component** types below. It is not the repo's identity — that is the **Base**.
_Avoid_: package, extension

**Workbench**:
The host project's compose service: a container built from the base image in which the docked base, the host project's code, and every supported **harness** coexist. One per host project; it is the only service in the stack.
_Avoid_: devcontainer (that is the thin IDE wrapper around the workbench), container (too generic)

**Component**:
Any of the five things a plugin can contain: a **skill**, a **subagent** (`agents/`), a **slash command** (`commands/`), a **hook** (`hooks/`), or an **MCP server** (`.mcp.json`). "Tool" is not a component type — what one might loosely call a tool is really a script owned by a skill, a slash command, or an MCP server. Use the precise component name.
_Avoid_: tool (too vague — name the actual component)

**Skill**:
A packaged unit of agent instructions defined by a `SKILL.md` file with YAML frontmatter (`name`, `description`). Claude Code loads it and follows its instructions in place of the default approach. A skill may ship a supporting script (e.g. Python under its `scripts/`); that script is a private detail of the skill, not a separately-installable thing. The shipped skills keep the `-local` suffix (`web-search-local`, `fetch-news-local`, `fetch-free-images-local`): it names their purpose — giving a **local model** web/news/image access to unblock itself — so it stays part of the name even once distributed. The `agentic-toolbox:` namespace scopes them; the suffix describes what they are for.
_Avoid_: command (a distinct component)

**Shipped skill** / **Draft skill**:
A **shipped skill** lives at `skills/<name>/` and is listed in `plugin.json`, so consumers receive it. A **draft skill** lives at `skills/in-progress/<name>/` and is absent from `plugin.json`, so it is never installed. `scripts/check.sh` enforces that every shipped component appears in both `plugin.json` and the README.
_Avoid_: promoted/unpromoted (Matt's bucket vocabulary; we use shipped/draft), WIP

**Host project**:
A separate repository that **docks** the **Base**: its container bind-mounts the base repo at a fixed path, and the base's content is wired into each supported **harness**'s discovery paths inside that container. The host project's own code lives in the container's working directory; the base is an add-on, never merged into the host's tree. The host project's domain concepts are not part of the base's domain.
_Avoid_: consumer repo (legacy, ADR-0002-era), downstream repo, client, "engineering project" (a host project can be any kind of project)

**Dock**:
The runtime mechanism by which a **Host project** consumes the **Base**: the base repo is bind-mounted into the host's container, and a start-up step wires the base's content into each **harness**'s discovery paths. Docking is a locative, reversible relationship — unlike installing a product.
_Avoid_: install, embed, vendor

**Consumer repo**:
*Retired.* A repository that installed the **Plugin** from the marketplace. Marketplace delivery is retired; the **Host project** supersedes this pattern entirely.
_Avoid_: downstream repo, client

**Vendored skill set**:
An external collection of skills (currently `mattpocock-skills`) fetched into the working tree under `.agents/skills/` as a **local development aid** — used to help build this repo, never shipped in the plugin. Kept out of version control and re-fetched from upstream rather than committed (see `docs/adr/0001`).
_Avoid_: third-party plugin, dependency (it is not installed as one)

**Local-dev bootstrap**:
*Retired.* The former `scripts/` step a developer ran after cloning: it fetched the **vendored skill set** into `.agents/skills/` and symlinked its skills into `.claude/skills/` for use in this repo's own Claude sessions. The Mac-side route is gone; its external-skill fetch discipline lives on inside the **dock** step (`.devcontainer/scripts/install-skills.sh`, run on every workbench start). Both `.agents/skills/` and `.claude/skills/` are git-ignored; only `.claude/settings.json` is committed.
_Avoid_: installer (that word is reserved for how a Consumer repo installs the plugin)

## Relationships

- The **base** contains many **components** (skills, subagents, commands, hooks, MCP servers)
- The **base** ships one **harness adapter** per supported **harness** (the Claude Code **plugin**, the pi configuration under `.pi/`)
- A **Host project** **docks** the **base**: the base repo is mounted into the host's **workbench** and wired into every supported harness
- A **skill** is **shipped** or a **draft**; only shipped skills are listed in `plugin.json`
- The marketplace delivery route for the **plugin** is retired; the adapter is delivered exclusively by docking
- The **vendored skill set** is wired in by the **dock** step (`install-skills.sh`) and is never part of the **base**

## Flagged ambiguities

- "tool" — the author's original phrase "tools, skills, and other things" collapsed to the five **component** types. There is no separate "tool" primitive; retired as a domain term.
- "-local" suffix — the skills are named `*-local`, meaning "gives a local model web/news/image access to unblock itself." A rename to drop the suffix was considered and reversed: the suffix names the skill's purpose, not merely a deployment context that goes away once distributed, so it is kept. The shipped skills are `web-search-local`, `fetch-news-local`, and `fetch-free-images-local`; the `agentic-toolbox:` namespace handles scoping.
- "skill" vs "plugin" — a **skill** is one `SKILL.md`-defined component; the **plugin** is the whole distributable repo that contains it. Keep them distinct.
- "installer" vs "bootstrap" — installing the **plugin** into a **Consumer repo** (marketplace) is distinct from the **local-dev bootstrap** that wires Matt's skills in for development. Don't conflate them.
