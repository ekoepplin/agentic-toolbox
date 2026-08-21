# agentic-toolbox

A Claude Code **plugin** that packages skills, subagents, slash commands, and hooks,
installed into other repositories through the Claude Code marketplace
(see `docs/adr/0002`). Shipped components are invoked under the
`/agentic-toolbox:` namespace, so they never collide with a consumer repo's own
skills.

## Install

From a consumer repo, add this repository as a marketplace and install the plugin:

```bash
claude plugin marketplace add ekoepplin/agentic-toolbox
claude plugin install agentic-toolbox@agentic-toolbox
```

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
