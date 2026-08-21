# fetch-news-local

Fetch news articles via NewsAPI, store in DuckDB, and save as markdown files.

## Setup

### 1. Install dependencies

```bash
pip install -r requirements.txt
```

### 2. Set NewsAPI key

```bash
export NEWS_API_KEY=<your-key>
```

Get a free API key at [newsapi.org](https://newsapi.org)

## Usage

### Quick Start

```bash
# Fetch coffee trends (last 7 days)
python fetch_news.py "coffee trends" --days 7

# Fetch espresso brewing news
python fetch_news.py "espresso brewing" --days 3

# Show recent fetches
python fetch_news.py recent
```

### Output

Each fetch creates:
- **DuckDB database:** `coffee_news.duckdb` (persistent storage)
- **Markdown file:** `output/news_<topic>_<timestamp>.md` (human-readable)
- **JSON file:** `output/news_<topic>_<timestamp>.json` (machine-readable, with `--json`)

### CLI Options

```bash
python fetch_news.py <topic> [options]

# Options:
#   --days N       Days of history (default: 7)
#   --language lang  Language code (default: en)
#   --json         Also save JSON output
#   recent         Show list of recent fetches
```

**Examples:**

```bash
# Fetch with 14 days history (auto-saves to DB + markdown)
python fetch_news.py "coffee industry" --days 14

# Fetch and get JSON output for programmatic use
python fetch_news.py "espresso" --days 3 --json

# List recent fetches
python fetch_news.py recent --limit 5

# Query database (default: show recent 10 articles)
python fetch_news.py database

# Custom SQL query
python fetch_news.py database --query "SELECT source_name, COUNT(*) FROM articles GROUP BY source_name"
```

### Python API

```python
from fetch_news import fetch_articles, save_to_markdown, save_to_json

# Fetch articles
data = fetch_articles("coffee trends", days=7)

# Save to markdown
save_to_markdown(data)

# Save to JSON
save_to_json(data)
```

## Data Schema

### DuckDB Table: `articles`

| Column | Type | Description |
|--------|------|-------------|
| `url` | TEXT | Article URL (primary key) |
| `title` | TEXT | Article title |
| `description` | TEXT | Article summary |
| `author` | TEXT | Author name |
| `source_name` | TEXT | News source name |
| `source_url` | TEXT | News source website |
| `published_at` | TIMESTAMP | Publication timestamp |
| `url_to_image` | TEXT | Featured image URL |
| `category` | TEXT | News category |
| `custom_query` | TEXT | Custom query used |
| `fetched_at` | TIMESTAMP | When fetched into DB |

### JSON Output Schema

```json
{
  "query": "coffee trends",
  "days": 7,
  "language": "en",
  "fetched_at": "2026-03-30T14:30:22.123456",
  "articles": [
    {
      "title": "Article title",
      "description": "Article summary",
      "url": "https://example.com/article",
      "author": "Author Name",
      "source": {"name": "Source Name", "url": "https://source.com"},
      "publishedAt": "2026-03-30T10:00:00Z",
      "urlToImage": "https://example.com/image.jpg"
    }
  ]
}
```

## Troubleshooting

**"Missing NEWS_API_KEY"**
```bash
export NEWS_API_KEY=your-key-here
```

**"Rate limit reached"**
NewsAPI free tier allows 50 requests/day. Wait 24h or upgrade.

**"Database not found"**
Run `python fetch_news.py <topic>` first to create the database.

**"No files in output/**
Run `python fetch_news.py <topic>` first to create files.
