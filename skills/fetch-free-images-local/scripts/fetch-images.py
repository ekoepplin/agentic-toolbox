#!/usr/bin/env python3
"""
Fetch free high-quality coffee equipment images from Pexels and Pixabay.
"""

import os
import sys
import json
import re
import requests
from pathlib import Path
from typing import Dict, List, Tuple
import logging

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)


def read_products(project_root: Path) -> List[Tuple[str, str]]:
    """Read product image IDs and names from products.ts.

    Returns list of (image_id, product_name) tuples.
    image_id is the filename stem from imageUrl, product_name is used as the search query.
    """
    products_file = project_root / "src" / "data" / "products.ts"
    if not products_file.exists():
        logger.error(f"Products file not found: {products_file}")
        return []

    text = products_file.read_text()

    # Extract imageUrl and name pairs from each product block
    products = []
    for block in re.split(r"\{", text):
        name_match = re.search(r'name:\s*"([^"]+)"', block)
        image_match = re.search(r'imageUrl:\s*"/images/products/([^"]+)\.jpg"', block)
        if name_match and image_match:
            products.append((image_match.group(1), name_match.group(1)))

    return products


def fetch_from_pexels(query: str, api_key: str) -> List[Dict]:
    """Fetch images from Pexels API."""
    try:
        response = requests.get(
            "https://api.pexels.com/v1/search",
            headers={"Authorization": api_key},
            params={"query": query, "per_page": 5, "orientation": "square"},
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


def fetch_from_pixabay(query: str, api_key: str) -> List[Dict]:
    """Fetch images from Pixabay API."""
    try:
        response = requests.get(
            "https://pixabay.com/api/",
            params={
                "key": api_key,
                "q": query,
                "image_type": "photo",
                "per_page": 5,
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


def main() -> int:
    pexels_key = os.environ.get("PEXELS_API_KEY", "")
    pixabay_key = os.environ.get("PIXABAY_API_KEY", "")

    if not pexels_key and not pixabay_key:
        logger.error(
            "No API keys found. Set PEXELS_API_KEY and/or PIXABAY_API_KEY environment variables.\n"
            "  Pexels: https://www.pexels.com/api/new/\n"
            "  Pixabay: https://pixabay.com/api/docs/"
        )
        return 1

    # Auto-detect project root (walk up from script dir looking for package.json)
    script_dir = Path(__file__).resolve().parent
    project_root = script_dir
    for _ in range(10):
        if (project_root / "package.json").exists():
            break
        project_root = project_root.parent
    else:
        logger.error("Could not find project root (no package.json found)")
        return 1

    products = read_products(project_root)
    if not products:
        logger.error("No products found in src/data/products.ts")
        return 1

    output_dir = project_root / "public" / "images" / "products"
    output_dir.mkdir(parents=True, exist_ok=True)

    downloaded = {}
    failed = []

    for image_id, product_name in products:
        image_path = output_dir / f"{image_id}.jpg"

        if image_path.exists():
            logger.info(f"[skip] {image_id} — already exists")
            downloaded[image_id] = str(image_path)
            continue

        logger.info(f'[search] {image_id}: "{product_name}"')

        images: List[Dict] = []
        if pexels_key:
            images.extend(fetch_from_pexels(product_name, pexels_key))
        if pixabay_key and not images:
            images.extend(fetch_from_pixabay(product_name, pixabay_key))

        if not images:
            logger.warning(f"[miss] {image_id} — no results")
            failed.append(image_id)
            continue

        if download_image(images[0]["url"], image_path):
            logger.info(f"[ok] {image_id} ({images[0]['source']})")
            downloaded[image_id] = str(image_path)
        else:
            failed.append(image_id)

    # Summary
    total = len(products)
    print(f"\nDownloaded {len(downloaded)}/{total} images")
    for pid, path in downloaded.items():
        print(f"  + {pid}: {path}")
    if failed:
        print(f"\nMissing ({len(failed)}):")
        for pid in failed:
            print(f"  - {pid}")

    summary = {
        "downloaded": len(downloaded),
        "total": total,
        "images": downloaded,
        "missing": failed,
    }
    summary_path = output_dir / "download-summary.json"
    summary_path.write_text(json.dumps(summary, indent=2))
    print(f"\nSummary: {summary_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
