# Lessons Learned

Append-only. Most recent at top.

---

## 2026-10-22 — bot identity lives in a dotfiles function, not env vars

### Check ~/repos/dotfiles before answering "who does the agent run as"
I answered "pi pushes as you" after checking only `PI_GIT_*`/`BOT_GIT_*` env
vars. The owner corrected: `~/repos/dotfiles/zsh/zshrc` defines a `pi()`
function that hard-codes `datadidact-bot` (token from `pass`), so the Mac's
interactive pi pushes as the bot — while workbenches and ralph scripts (no zsh
functions, no exported vars) push as the human. **Rule:** for identity/config
questions, grep the dotfiles repo (`~/.zshrc`, `~/.gitconfig` are symlinks into
it) as well as this repo and the env; answer per execution context (Mac shell,
workbench, script).

---

## 2026-10-22 — `make image` without buildx silently uses the legacy builder

### A missing buildx plugin turns a BuildKit Dockerfile into a slow late failure
On colima with only the compose CLI plugin, `docker build` fell back to the
legacy builder: it rebuilt every layer uncached for ~2 minutes, then died at the
first `COPY --chmod` ("requires BuildKit"). **Rule:** `make image` exports
`DOCKER_BUILDKIT=1` so a missing plugin fails in a second with a clear message;
fix with `brew install docker-buildx` + link into `~/.docker/cli-plugins/`.

### Hard-coded skill names in probes break on any skill change
`probe-dock.sh` asserted `Skills (3)` and three literal names, so removing or
adding a skill broke the runtime gate. **Rule:** probes derive the shipped set
from `plugin.json` (the contract `check.sh` already enforces) — never a literal
list or count.

---

## 2026-09-13 — pi + local vLLM/SGLang model routing

### pi's model `id` is the wire name — it must equal the server's `data[].id`
`pi --provider vllm-hpzgx --model qwen` returned `404: The model 'qwen' does not
exist`. Cause: in `~/.pi/agent/models.json`, a model's `id` field is sent
verbatim as the OpenAI `"model"` param. The config had `id: "qwen"`, but the
backend had been swapped (`start-local-setup --flashnext`) and now serves the
model as `qwen3.8-flash-next-a5b`. A server-side rename
(`--served-model-name qwen`) wasn't clean here because the flashnext launcher
wraps an upstream `serve.sh` that hardcodes the served name.

**Rule:** the `id` you pass to `--model` must match `curl -s
localhost:8000/v1/models | jq -r '.data[].id'`. When a host serves different
models on the same port at different times, register one model entry per served
`id` under the provider in `~/.pi/agent/models.json`, and pass whichever
`--model` matches what's currently live. Provider-level `baseUrl`/`compat`
(e.g. `thinkingFormat: "qwen"`) is shared across the entries. See
`docs/harnesses/pi-agent-harness/connecting-local-models.md`.

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

## 2026-10-17 — workbench voice: image ENV is invisible over SSH

### Test workbench behavior through SSH, not `docker exec`
`ENV PULSE_SERVER=…` in the Dockerfile made `rec` work under `docker exec`, so every probe passed — but users enter workbenches through sshd, whose sessions get a fresh environment without image `ENV`. Claude Code `/voice` then failed with `SoX could not open an audio capture device`. **Rule:** anything an SSH session needs goes into a config file (`/etc/pulse/client.conf.d/`, `/etc/profile.d/`, …), never image `ENV` alone; verify with `env -i` or a real `ssh -p <port>` session, not plain `docker exec`.

---
