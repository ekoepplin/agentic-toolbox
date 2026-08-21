"""
web-search-local: Search the web or extract URL content via Tavily.

Usage:
    python3 __main__.py "search query"
    python3 __main__.py "https://example.com"
"""

import os
import sys


def get_client():
    api_key = os.getenv("TAVILY_API_KEY")
    if not api_key:
        print(
            "Error: TAVILY_API_KEY environment variable is not set.\n"
            "\n"
            "Setup:\n"
            "  export TAVILY_API_KEY=<your key>\n"
            "\n"
            "Get an API key at: https://tavily.com\n"
            "Install the client: pip install tavily-python"
        )
        sys.exit(1)

    from tavily import TavilyClient
    return TavilyClient(api_key=api_key)


def is_url(arg: str) -> bool:
    return arg.startswith("http://") or arg.startswith("https://")


def search(client, query: str) -> str:
    response = client.search(query)
    results = response.get("results", [])
    if not results:
        return "No results found."

    parts = []
    for result in results:
        title = result.get("title", "Untitled")
        url = result.get("url", "")
        content = result.get("content", "").strip()
        parts.append(f"[{title}]({url})\n{content}")

    return "\n\n---\n\n".join(parts)


def extract(client, url: str) -> str:
    response = client.extract(urls=[url])
    results = response.get("results", [])
    if not results:
        return f"No content extracted from {url}"

    parts = []
    for result in results:
        raw_url = result.get("url", url)
        content = result.get("raw_content", "").strip()[:4000]
        parts.append(f"URL: {raw_url}\n{content}")

    return "\n\n---\n\n".join(parts)


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 __main__.py \"<search query or URL>\"")
        sys.exit(1)

    arg = sys.argv[1].strip()
    client = get_client()

    try:
        if is_url(arg):
            print(extract(client, arg))
        else:
            print(search(client, arg))
    except Exception as e:
        error = str(e).lower()
        if "rate limit" in error or "429" in error:
            print(f"Rate limit reached. Please retry later.\n({e})")
        elif "invalid api key" in error or "401" in error or "403" in error:
            print(f"Invalid TAVILY_API_KEY. Check your key at https://tavily.com\n({e})")
        else:
            print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
