#!/usr/bin/env python3
"""
Fetch free high-quality images from Pexels and Pixabay for a search query.
"""

import os
import sys
import json
import re
import argparse
import requests
from pathlib import Path
from typing import Dict, List
import logging

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


def fetch_from_pexels(query: str, api_key: str, count: int) -> List[Dict]:
    """Fetch images from Pexels API."""
    try:
        response = requests.get(
            "https://api.pexels.com/v1/search",
            headers={"Authorization": api_key},
            params={"query": query, "per_page": count},
            timeout=15,
        )
        response.raise_for_status()
        data = response.json()
        return [
            {
                "url": photo["src"]["large"],
                "width": photo["width"],
                "height": photo["height"],
                "source": "pexels",
                "alt": photo.get("alt", ""),
            }
            for photo in data.get("photos", [])
        ]
    except Exception as e:
        logger.warning(f"Pexels error: {e}")
        return []


def fetch_from_pixabay(query: str, api_key: str, count: int) -> List[Dict]:
    """Fetch images from Pixabay API."""
    try:
        response = requests.get(
            "https://pixabay.com/api/",
            params={
                "key": api_key,
                "q": query,
                "image_type": "photo",
                "per_page": max(count, 3),
                "min_width": 600,
            },
            timeout=15,
        )
        response.raise_for_status()
        data = response.json()
        return [
            {
                "url": hit["webformatURL"],
                "width": hit["webformatWidth"],
                "height": hit["webformatHeight"],
                "source": "pixabay",
                "alt": hit.get("tags", ""),
            }
            for hit in data.get("hits", [])
        ]
    except Exception as e:
        logger.warning(f"Pixabay error: {e}")
        return []


def download_image(url: str, dest: Path) -> bool:
    """Download an image to disk."""
    try:
        response = requests.get(url, timeout=30)
        response.raise_for_status()
        content_type = response.headers.get("content-type", "")
        if "image" not in content_type:
            logger.warning(f"Not an image ({content_type}): {url}")
            return False
        dest.write_bytes(response.content)
        return True
    except Exception as e:
        logger.error(f"Download failed: {e}")
        return False


def slugify(text: str) -> str:
    """Turn a search query into a filename-safe stem."""
    slug = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return slug or "image"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fetch free high-quality images from Pexels and Pixabay."
    )
    parser.add_argument("query", help="Search query, e.g. 'espresso machine'")
    parser.add_argument(
        "--count", type=int, default=1, help="Number of images to download (default: 1)"
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=Path("images"),
        help="Output directory (default: ./images)",
    )
    args = parser.parse_args()

    pexels_key = os.environ.get("PEXELS_API_KEY", "")
    pixabay_key = os.environ.get("PIXABAY_API_KEY", "")

    if not pexels_key and not pixabay_key:
        logger.error(
            "No API keys found. Set PEXELS_API_KEY and/or PIXABAY_API_KEY environment variables.\n"
            "  Pexels: https://www.pexels.com/api/new/\n"
            "  Pixabay: https://pixabay.com/api/docs/"
        )
        return 1

    images: List[Dict] = []
    if pexels_key:
        images.extend(fetch_from_pexels(args.query, pexels_key, args.count))
    if pixabay_key and len(images) < args.count:
        images.extend(fetch_from_pixabay(args.query, pixabay_key, args.count))

    if not images:
        logger.error(f"No results for query: {args.query!r}")
        return 1

    output_dir = args.out
    output_dir.mkdir(parents=True, exist_ok=True)

    stem = slugify(args.query)
    downloaded: Dict[str, str] = {}
    failed: List[str] = []

    for i, image in enumerate(images[: args.count], 1):
        name = f"{stem}-{i}.jpg" if args.count > 1 else f"{stem}.jpg"
        dest = output_dir / name

        logger.info(f'[download] {name} <- {image["source"]}')
        if download_image(image["url"], dest):
            logger.info(f"[ok] {name}")
            downloaded[name] = str(dest)
        else:
            failed.append(name)

    requested = min(args.count, len(images))
    print(f"\nDownloaded {len(downloaded)}/{requested} images")
    for name, path in downloaded.items():
        print(f"  + {name}: {path}")
    if failed:
        print(f"\nFailed ({len(failed)}):")
        for name in failed:
            print(f"  - {name}")

    summary = {
        "query": args.query,
        "downloaded": len(downloaded),
        "requested": requested,
        "images": downloaded,
        "failed": failed,
    }
    summary_path = output_dir / "download-summary.json"
    summary_path.write_text(json.dumps(summary, indent=2))
    print(f"\nSummary: {summary_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
