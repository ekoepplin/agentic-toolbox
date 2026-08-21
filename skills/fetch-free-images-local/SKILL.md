---
name: fetch-free-images-local
description: Fetch free high-quality images from Pexels and Pixabay. Use when the user asks to "download images", "fetch free images", "get stock photos", or replace placeholder images with real photos.
---

# fetch-free-images-local

Fetch free high-quality coffee equipment images from Pexels and Pixabay.

## Purpose

Downloads free, high-quality images of coffee equipment and beans for the docoffeeright project. Replaces placeholder images with real photos.

## Usage

```
/fetch-free-images-local
```

## Setup

At least one API key is required via environment variable:

```bash
export PEXELS_API_KEY=<your-key>    # https://www.pexels.com/api/new/
export PIXABAY_API_KEY=<your-key>   # https://pixabay.com/api/docs/ (optional)
```

## How It Works

1. Reads product list dynamically from `src/data/products.ts`
2. Searches Pexels (and optionally Pixabay) for each product by name
3. Downloads the best matching image
4. Saves to `public/images/products/` with filenames matching `imageUrl`
5. Skips products that already have an image on disk

## Image Sources

- **Pexels**: Free images, no attribution required (API key required)
- **Pixabay**: Free images, no attribution required (API key optional)

## Output

- Images saved in `public/images/products/<product-id>.jpg`
- Summary JSON at `public/images/products/download-summary.json`

## Execution

Run in background — slow (multiple HTTP downloads), log-heavy. Use `run_in_background=true` on the Bash tool call so main context isn't blocked.

```bash
python3 scripts/fetch-images.py
```

## Requirements

- Python 3.6+
- `requests` library
- At least one API key set as environment variable
