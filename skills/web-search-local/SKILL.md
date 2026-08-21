---
name: web-search-local
description: Use this skill when the local model is stuck and needs internet access to unblock itself, when the user asks to "search the web", "look up", "fetch a URL", "extract from a URL", or when fresh online information is needed to answer a question.
---

# Web Search / URL Extract via Tavily

Use this skill to fetch live web content when you cannot answer from context alone.

## When to Use

- You need current information not in your training data
- The user provides a URL and wants its content extracted
- You are stuck and need external documentation, a spec, or a data source

## How to Execute

### Extract content from a URL

Provide a full URL as the argument:

```
web-search-local "https://example.com"
```

### Search the web for a query

Provide your search query:

```
web-search-local "latest Python release date"
web-search-local "react vs vue comparison"
```

## Expected Output Format

**Search results:**
```
[Title of Result](http://example.com)
Relevant content snippet from the page...

---

[Another Result](http://another-site.com)
More search result content...

---
```

**Extracted content:**
```
URL: https://example.com
Full extracted content from the webpage, truncated to 4000 characters...

---
```

## Configuration

Requires `TAVILY_API_KEY` environment variable:

```bash
export TAVILY_API_KEY=<your key>
```

Get an API key at: https://tavily.com

Install the client with: `pip install tavily-python`

## Error Handling

- Missing API key: Shows setup instructions
- Rate limit: Suggests retrying later
- Network errors: Indicates connectivity issues

## Execution

Run via Bash tool:

```bash
python3 scripts/web-search.py "$ARGUMENTS"
```

Print the output to the user verbatim.
