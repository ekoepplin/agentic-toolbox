---
name: fetch-news-local
description: Fetch news articles via NewsAPI and save as markdown files. Use when the user asks for "latest news", "tech news", "business news", "coffee news", "news about espresso", or wants to stay updated on industry trends.
---

# fetch-news-local

Fetch news articles via NewsAPI, store them in a local DuckDB database, and save as markdown files.

## Agent Usage

Agents can invoke this skill to fetch coffee-related news autonomously:

```bash
# Fetch latest coffee trends (last 7 days)
python scripts/fetch-news.py "coffee trends" --days 7

# Research espresso brewing techniques
python scripts/fetch-news.py "espresso brewing" --days 3

# Get JSON output for programmatic processing
python scripts/fetch-news.py "coffee industry" --days 14 --json

# List recent fetches
python scripts/fetch-news.py recent
```

### Example Agent Prompts

- "Fetch the latest news about coffee brewing innovations"
- "Research current trends in specialty coffee"
- "Find articles about espresso machine technology from the past week"
- "What are the top coffee industry stories this month?"

### Output Files

Each fetch creates:
- `output/news_<topic>_<timestamp>.md` - Human-readable markdown
- `output/news_<topic>_<timestamp>.json` - Machine-readable JSON (with `--json`)

## Setup

### 1. Install dependencies

```bash
pip install -r requirements-fetch-news.txt
```

### 2. Set NewsAPI key

```bash
export NEWS_API_KEY=<your-key>
```

Get a free API key at [newsapi.org](https://newsapi.org)

## CLI Usage

### Fetch Articles

```bash
python scripts/fetch-news.py <topic> [options]

# Examples:
python scripts/fetch-news.py "coffee trends" --days 7
python scripts/fetch-news.py "espresso" --days 3 --json
python scripts/fetch-news.py "coffee OR brewing" --days 14
```

**Options:**

| Flag | Default | Description |
|------|---------|-------------|
| `--days` | `7` | Number of days of history |
| `--language` | `en` | Language code |
| `--json` | `False` | Also save JSON output |

### Show Recent Fetches

```bash
# List recent fetches
python scripts/fetch-news.py recent

# Show only last 3
python scripts/fetch-news.py recent --limit 3
```

## Files

```
requirements-fetch-news.txt        # Python dependencies
scripts/
├── fetch-news.py                  # Agent-facing CLI
└── output/                        # Generated markdown/JSON files
    ├── news_coffee_trends_20260330_143022.md
    └── news_coffee_trends_20260330_143022.json
```

## Troubleshooting

**"Missing NEWS_API_KEY"**
```bash
export NEWS_API_KEY=your-key-here
```

**"Rate limit reached"**
NewsAPI free tier allows 50 requests/day. Wait 24h or upgrade.

**No output files found**
Run `python scripts/fetch-news.py <topic>` first to create files.
