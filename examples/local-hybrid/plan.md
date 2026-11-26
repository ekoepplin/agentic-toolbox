# Plan: slugify

Written by Opus after the grilling session. The executor gets only this file.

## Task
Create `slugify.py` with `slugify(text: str) -> str` and `test_slugify.py` (pytest).

## Acceptance criteria
1. Lowercase; German umlauts become ae/oe/ue, ß becomes ss.
2. Every run of non `[a-z0-9]` characters becomes one `-`; no leading/trailing `-`.
3. Empty or symbol-only input returns `""`.
4. Tests cover criteria 1–3.

## Files
```files
slugify.py
test_slugify.py
```

## Out of scope
Other files, packages, installing anything.

## Verify
```
python3 -m pytest -q
python3 -c "from slugify import slugify as s; assert s('Grüße aus Köln!') == 'gruesse-aus-koeln'"
python3 -c "from slugify import slugify as s; assert s('  --Hallo,   Welt--  ') == 'hallo-welt'"
python3 -c "from slugify import slugify as s; assert s('!!!') == ''"
```
