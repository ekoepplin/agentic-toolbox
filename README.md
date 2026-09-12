# agentic-toolbox

The agentic development **base**: the environment (base image + compose stack)
and the shared agentic content (skills, subagents, slash commands, hooks) that
host projects **dock** into at runtime to get agentic development across every
supported harness. The Claude Code **plugin** under `.claude-plugin/` is the
base's Claude Code harness adapter. See `CONTEXT.md` for the domain vocabulary.

Shipped components are invoked under the `/agentic-toolbox:` namespace, so
they never collide with a host project's own skills.

## How host projects use this

Host projects **dock** the base: `make dock HOST=<path-to-host-repo>`
scaffolds the workbench stack, and the dock step wires every harness adapter
on each workbench start (see `docs/harnesses/dock-e2e.md`).

## Shipped skills

The plugin ships exactly these skills (listed in `.claude-plugin/plugin.json`):

- [web-search-local](skills/web-search-local/SKILL.md) — web search and URL content
  extraction (Tavily) for unblocking a stuck local model: `/agentic-toolbox:web-search-local`
- [fetch-news-local](skills/fetch-news-local/SKILL.md) — fetch news articles via
  NewsAPI and save them as markdown files: `/agentic-toolbox:fetch-news-local`
- [fetch-free-images-local](skills/fetch-free-images-local/SKILL.md) — fetch free
  high-quality images from Pexels and Pixabay: `/agentic-toolbox:fetch-free-images-local`

Draft skills live in `skills/in-progress/` and are never listed in
`.claude-plugin/plugin.json`, so they are not installed.
