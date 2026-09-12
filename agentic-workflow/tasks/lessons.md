# Lessons Learned

Append-only. Most recent at top.

---

## 2026-09-12 — editing a live agent's runtime config races the agent

Hand-edited `.pi/remote-pi/config.json` (`auto_start_relay` toggle) while pi
sessions were running. remote-pi rewrote the file from its own in-memory state,
colliding with the edit and leaving a corrupted duplicate-key JSON.

**Rule:** don't hand-edit a process's runtime config file while that process is
live — it will rewrite it and the edit races. Change such settings from within
the app (its own command), or only when no owning process is running.

---

## 2026-09-12 — ralph-pi on issue #10 (dock step)

### `gh pr create` does not accept `--squash`

The UNATTENDED MERGE step suggests `gh pr create --fill --base master --squash --merge`,
but the installed `gh` rejects `--squash` on create (prints the flag help, no PR).

**Rule:** create then merge in two steps:
`gh pr create --fill --base master` && `gh pr merge --squash`.

### `git rev-parse -q --verify -- "<ref>^{commit}"` fails

Putting `--` before the rev makes `rev-parse --verify` fail (rev treated
post-options). Drop the `--`: `git rev-parse -q --verify "<ref>^{commit}"`.

### Colima only shares the home dir

Bind-mounting `/tmp/...` into a container yields an empty mount without error
(colima shares `~`, not `/`). Use `$HOME/tmp/...` for throwaway mount fixtures.

---

## 2026-09-11 — tracing file deletions via pi session logs

### An unexplained `D` in git status during ralph-pi validation

After the issue #7 smoke run, `git status` showed a staged deletion of
`docs/harnesses/pi-agent-harness/devcontainer-pi-support-plan.md`. Full audit
of the ralph pi session log (`~/.pi/agent/sessions/<project>/…jsonl`) proved it
innocent: 20 bash + 1 edit + 3 read calls, zero deletion strings. No command in
this session or the ralph session removed it; the remote branch commits were
unaffected (index state is local-only). Most likely cause: parallel manual git
activity in the repo that evening (the `pi-loop` branch and the harness docs
were being worked on concurrently). File restored via `git restore -- <path>`.

**Rule:** when a tracked file vanishes mid-workflow, audit the pi session jsonl
(tool-call inputs: `name` + `arguments.command/path`) before blaming the agent;
cross-check `git reflog` and remote branch contents.

---

## 2026-09-11 — macOS system bash 3.2 lacks mapfile

### `scripts/check.sh` fails on a bare Mac (stock bash 3.2)

`check.sh` uses `mapfile` (bash 4+). macOS ships bash 3.2, so running the gate
from stock `/bin/bash` aborts with `mapfile: command not found`. The ralph-pi
smoke run (issue #7) hit this on the Mac and installed Homebrew bash 5.3
(`/opt/homebrew/bin/bash`) to pass the gate — a system side-effect, no repo
files touched.

**Rule:** on a bare Mac, ensure a modern bash is first on PATH
(`brew install bash`; `check.sh` uses `#!/usr/bin/env bash` so it picks it up)
or run the gate inside the devcontainer (bash 5.x). Candidate for a follow-up:
make `check.sh` bash 3.2-compatible so the gate is portable.

---

## 2026-06-28 — dlt dependency gaps

### dlt GCS + parquet requires three extras, not one
`dlt[filesystem]` alone is insufficient for GCS parquet writes. Required extras:
- `dlt[gs]` → installs `gcsfs` (GCS fsspec driver)
- `dlt[parquet]` → installs `pyarrow` (parquet serialization)
- `dlt[duckdb]` → installs `duckdb` (local test destination)

**Rule:** always use `dlt[filesystem,duckdb,gs,parquet]` for GCS filesystem pipelines with parquet output.

### `loader_file_format` in `[normalize]` config.toml is ignored by filesystem destination
Setting `loader_file_format = "parquet"` under `[normalize]` in `config.toml` has no effect on the filesystem destination — it defaults to `jsonl`. **Rule:** pass `loader_file_format="parquet"` explicitly in every `pipeline.run()` call.

### DuckDB pipeline_name and dataset_name must differ
When `PIPELINE_NAME == SCHEMA_NAME`, DuckDB raises `Binder Error: Ambiguous reference to catalog or schema`. The DuckDB file is named after the pipeline, making catalog = schema. **Rule:** always use distinct names, e.g. `PIPELINE_NAME = "newsapi"`, `SCHEMA_NAME = "newsapi_raw"`.

---

## 2026-06-28 — dlt multiple pipes bug

### dlt rejects multiple resource instances with the same name
Returning `[get_articles(lang, query) for lang, query in QUERIES]` from a `@dlt.source` creates multiple pipes all named `get_articles` — dlt raises `InvalidResourceDataTypeMultiplePipes`. **Rule:** a `@dlt.resource` must be a single pipe. If you need to iterate over parameters (languages, geos, etc.), loop *inside* the resource function and `yield` all rows from one function. Never return a list of calls to the same resource from `@dlt.source`.

---
