---
name: fetch-free-images-local
description: Fetch free high-quality images from Pexels and Pixabay. Use when the user asks to "download images", "fetch free images", "get stock photos", or replace placeholder images with real photos.
---

# fetch-free-images-local

Fetch free high-quality images from Pexels and Pixabay for a search query.

## Purpose

Downloads free, high-quality stock photos matching a search query — for
illustrating docs, replacing placeholder images, or building an image set.

## Usage

```
/agentic-toolbox:fetch-free-images-local
```

## Setup

At least one API key is required via environment variable:

```bash
export PEXELS_API_KEY=<your-key>    # https://www.pexels.com/api/new/
export PIXABAY_API_KEY=<your-key>   # https://pixabay.com/api/docs/ (optional)
```

## How It Works

1. Searches Pexels (and optionally Pixabay) for the given query
2. Downloads the top matching images, up to `--count`
3. Saves them to the output directory (default `./images`)
4. Writes a summary JSON alongside the images

## Image Sources

- **Pexels**: Free images, no attribution required (API key required)
- **Pixabay**: Free images, no attribution required (API key optional)

## Output

- Images saved as `<out>/<query-slug>[-<n>].jpg`
- Summary JSON at `<out>/download-summary.json`

## Execution

Run in background — slow (multiple HTTP downloads), log-heavy. Use `run_in_background=true` on the Bash tool call so main context isn't blocked.

```bash
python3 scripts/fetch-images.py "<search query>" [--count N] [--out DIR]
```

Examples:

```bash
python3 scripts/fetch-images.py "espresso machine"
python3 scripts/fetch-images.py "coffee beans" --count 3 --out public/images
```

## Requirements

- Python 3.6+
- `requests` library
- At least one API key set as environment variable
