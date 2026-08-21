#!/usr/bin/env python3
"""
Agent-facing interface for fetch-news-local.
Produces markdown files for each fetch call.

Usage:
    python fetch_news.py <topic> [--days N]
    python fetch_news.py fetch <topic> [--days N]
    python fetch_news.py recent [--limit N]

Examples:
    python fetch_news.py "coffee trends" --days 7
    python fetch_news.py "espresso brewing" --days 3
    python fetch_news.py recent --limit 10
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path

import duckdb
from loguru import logger
from newsapi.newsapi_client import NewsApiClient


def get_newsapi_client():
    """Get NewsAPI client from secrets."""
    api_key = os.getenv("NEWS_API_KEY") or os.getenv("NEWSAPI_ORG_API_KEY")
    if not api_key:
        logger.error("NEWS_API_KEY or NEWSAPI_ORG_API_KEY environment variable is not set.")
        logger.info("Get a free API key at: https://newsapi.org")
        raise RuntimeError("Missing NEWS_API_KEY")
    return NewsApiClient(api_key=api_key)


def get_db_path():
    """Get the DuckDB file path."""
    return Path(__file__).parent / "coffee_news.duckdb"


def get_output_dir():
    """Get the output directory for markdown files."""
    return Path(__file__).parent / "output"


def init_database(db_path: Path):
    """Initialize DuckDB schema."""
    conn = duckdb.connect(str(db_path))
    try:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS articles (
                url TEXT PRIMARY KEY,
                title TEXT,
                description TEXT,
                author TEXT,
                source_name TEXT,
                source_url TEXT,
                published_at TIMESTAMP,
                url_to_image TEXT,
                category TEXT,
                custom_query TEXT,
                fetched_at TIMESTAMP
            )
        """)
        conn.commit()
    finally:
        conn.close()


def fetch_articles(topic: str, days: int = 7, language: str = "en", source_filter: str = "") -> dict:
    """
    Fetch news articles for a given topic.

    Args:
        topic: Search topic (e.g., 'coffee trends', 'espresso brewing')
        days: Number of days of history
        language: Language code
        source_filter: Optional source name to filter by (e.g., 'perfect-daily-grind')

    Returns:
        Dict with articles and metadata
    """
    client = get_newsapi_client()
    today = datetime.utcnow().date()
    from_date = today - timedelta(days=days)

    logger.info(f"Fetching articles about '{topic}' for the last {days} days")

    # Build API params
    params = {
        "q": topic,
        "language": language,
        "from_param": from_date.isoformat(),
        "to": today.isoformat(),
        "sort_by": "publishedAt",
        "page_size": 50,
    }
    if source_filter:
        params["sources"] = source_filter
        logger.info(f"Filtering by source: {source_filter}")

    articles = client.get_everything(**params)

    article_list = articles.get("articles", [])
    logger.info(f"Fetched {len(article_list)} articles")

    return {
        "query": topic,
        "days": days,
        "language": language,
        "fetched_at": datetime.utcnow().isoformat(),
        "articles": article_list,
    }


def generate_markdown(data: dict) -> str:
    """Generate markdown content from fetched articles."""
    lines = [
        f"# Coffee News: {data['query']}",
        "",
        f"**Fetched:** {data['fetched_at']}",
        f"**Query:** {data['query']}",
        f"**Period:** Last {data['days']} days",
        f"**Total Articles:** {len(data['articles'])}",
        "",
        "---",
        "",
    ]

    for i, article in enumerate(data["articles"], 1):
        lines.extend([
            f"## {i}. {article.get('title', 'No title')}",
            "",
            f"**Source:** {article.get('source', {}).get('name', 'Unknown')}",
            f"**Published:** {article.get('publishedAt', 'Unknown')}",
            f"**Author:** {article.get('author', 'Unknown')}",
            "",
        ])

        if article.get("urlToImage"):
            lines.extend([
                f"**Image:** {article['urlToImage']}",
                "",
            ])

        if article.get("description"):
            lines.extend([
                article["description"],
                "",
            ])

        if article.get("url"):
            lines.extend([
                f"> [{article['url']}]({article['url']})",
                "",
            ])

        if i < len(data["articles"]):
            lines.append("---")
            lines.append("")

    return "\n".join(lines)


def save_to_db(data: dict, db_path: Path):
    """Save articles to DuckDB database."""
    init_database(db_path)

    conn = duckdb.connect(str(db_path))
    try:
        # Insert articles
        for article in data["articles"]:
            conn.execute("""
                INSERT OR REPLACE INTO articles (
                    url, title, description, author, source_name, source_url,
                    published_at, url_to_image, category, custom_query, fetched_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                article.get("url", ""),
                article.get("title", ""),
                article.get("description", ""),
                article.get("author", ""),
                article.get("source", {}).get("name", ""),
                article.get("source", {}).get("url", ""),
                article.get("publishedAt", ""),
                article.get("urlToImage", ""),
                data.get("category", "general"),
                data.get("query", ""),
                datetime.utcnow(),
            ])
        conn.commit()
        logger.success(f"Saved {len(data['articles'])} articles to database")
    finally:
        conn.close()


def save_to_markdown(data: dict):
    """Save articles to a timestamped markdown file."""
    output_dir = get_output_dir()
    output_dir.mkdir(parents=True, exist_ok=True)

    # Sanitize filename from query
    safe_query = "".join(c if c.isalnum() or c in " _-" else "_" for c in data["query"])
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"news_{safe_query}_{timestamp}.md"
    filepath = output_dir / filename

    markdown_content = generate_markdown(data)
    filepath.write_text(markdown_content)

    logger.success(f"Saved to: {filepath}")
    return filepath


def save_to_json(data: dict):
    """Save articles to a JSON file for programmatic access."""
    output_dir = get_output_dir()
    output_dir.mkdir(parents=True, exist_ok=True)

    safe_query = "".join(c if c.isalnum() or c in " _-" else "_" for c in data["query"])
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"news_{safe_query}_{timestamp}.json"
    filepath = output_dir / filename

    filepath.write_text(json.dumps(data, indent=2, default=str))
    logger.success(f"Saved JSON to: {filepath}")
    return filepath


def display_recent(limit: int = 10):
    """Display the most recent fetched articles."""
    output_dir = get_output_dir()
    if not output_dir.exists():
        logger.info("No fetched articles found. Run a fetch first.")
        return

    files = sorted(output_dir.glob("news_*.md"), key=lambda x: x.stat().st_mtime, reverse=True)

    if not files:
        logger.info("No fetched articles found.")
        return

    logger.info(f"Showing {min(limit, len(files))} most recent fetches:")
    logger.info()

    for filepath in files[:limit]:
        content = filepath.read_text()
        # Extract title and first few lines
        lines = content.split("\n")
        title = lines[0].replace("# ", "") if lines else "No title"
        logger.info(f"**{filepath.name}**")
        logger.info(f"  {title}")
        logger.info()


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Fetch coffee news articles and save as markdown files."
    )

    subparsers = parser.add_subparsers(dest="mode", help="Available modes")

    # Default mode: fetch + save
    default_parser = subparsers.add_parser("default", help="Fetch and save (default mode)", add_help=False)
    default_parser.add_argument("topic", type=str, help="Topic to search for")
    default_parser.add_argument("--days", type=int, default=7, help="Days of history")
    default_parser.add_argument("--language", type=str, default="en", help="Language code")
    default_parser.add_argument("--json", action="store_true", help="Also save JSON")

    # Fetch mode
    fetch_parser = subparsers.add_parser("fetch", help="Fetch and save articles", add_help=False)
    fetch_parser.add_argument("topic", type=str, help="Topic to search for")
    fetch_parser.add_argument("--days", type=int, default=7, help="Days of history")
    fetch_parser.add_argument("--language", type=str, default="en", help="Language code")
    fetch_parser.add_argument("--json", action="store_true", help="Also save JSON")

    # Recent mode
    recent_parser = subparsers.add_parser("recent", help="Show recent fetches", add_help=False)
    recent_parser.add_argument("--limit", type=int, default=10, help="Number of recent fetches to show")

    # Database mode
    db_parser = subparsers.add_parser("database", help="Query stored articles in DuckDB", add_help=False)
    db_parser.add_argument("--query", type=str, dest="database_query", help="Custom SQL query")

    args = parser.parse_args()

    # Default to "fetch" mode if no subcommand
    if not args.mode:
        args.mode = "fetch"
        if len(sys.argv) > 1 and not sys.argv[1].startswith("--"):
            topic = sys.argv[1]
            days = 7
            language = "en"
            save_json = False

            for i, arg in enumerate(sys.argv[1:], 1):
                if arg == "--days" and i + 1 < len(sys.argv):
                    days = int(sys.argv[i + 1])
                elif arg == "--language" and i + 1 < len(sys.argv):
                    language = sys.argv[i + 1]
                elif arg == "--json":
                    save_json = True

            args = argparse.Namespace(
                mode="fetch",
                topic=topic,
                days=days,
                language=language,
                json=save_json,
            )

    # Execute mode
    if args.mode in ("fetch", "default"):
        data = fetch_articles(args.topic, args.days, args.language, source_filter="")
        save_to_db(data, get_db_path())
        save_to_markdown(data)

        if args.json:
            save_to_json(data)

        logger.success(f"\nSuccessfully fetched {len(data['articles'])} articles about '{args.topic}'")
        logger.info(f"Markdown saved to: {get_output_dir()}/news_{args.topic}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.md")

    elif args.mode == "recent":
        display_recent(args.limit)

    elif args.mode == "database":
        """Query the database."""
        db_path = get_db_path()
        if not db_path.exists():
            logger.error(f"Database not found: {db_path}")
            logger.info("Run a fetch command first to create the database.")
            return

        conn = duckdb.connect(str(db_path))
        try:
            # Default query: show recent articles
            if args.database_query is None:
                results = conn.execute("""
                    SELECT title, source_name, published_at, url
                    FROM articles
                    ORDER BY fetched_at DESC
                    LIMIT 10
                """).fetchall()

                logger.info("Recent articles in database:")
                for row in results:
                    logger.info(f"  [{row[2]}] {row[0][:60]}... ({row[1]})")
            else:
                results = conn.execute(args.database_query).fetchall()
                for row in results:
                    logger.info(str(row))
        finally:
            conn.close()


if __name__ == "__main__":
    main()
