# Running the ralph loop on pi

[pi](https://pi.dev/) as the execution engine for `agentic-workflow/` — the same
**think → spec → break down → triage → execute → refactor** pipeline from
`agentic-workflow/MATT-WORKFLOW.md`, with the `ralph/` execution stage driving
`pi -p` instead of `claude`.

Prerequisite: the local endpoint is up and a provider is registered in
`~/.pi/agent/models.json` — see [connecting-local-models.md](./connecting-local-models.md).

The good news: the ralph loop is already 90% harness-agnostic. `afk.sh` only polls
`gh issue view` and shells out to `once.sh`; `prompt.md` is plain git/gh
instructions. The port is **the launch line in `once.sh` plus two lines of
`prompt.md`**.

## What stays, what changes

| ralph piece | on pi |
|---|---|
| `afk.sh` (issue-state polling, iter cap) | **Unchanged** (one-line swap to call `pi-once.sh`) |
| `once.sh` issue fetch + recent-commits + mission assembly | **Unchanged** |
| `once.sh` launch line (`claude … --permission-mode acceptEdits`) | **Replaced** with `pi -a -p …` (below) |
| Backend routing via `ANTHROPIC_BASE_URL`/`AUTH_TOKEN` env vars | **Replaced** with `--model <provider>/<id>`; providers live in `models.json`, not env vars |
| `settings.ralph.json` (permission allow-list) + `acceptEdits` | **Gone** — pi has no permission prompts, so an AFK loop can never stall on approval. Optional `--tools` restriction and/or a guardrail extension instead |
| `claude --plugin-dir .` plugin-load smoke check (gate) | **Gone** — pi's skill discovery is path-based and deterministic; `scripts/check.sh` remains the gate |
| `/code-review` in the prompt | The `code-review` skill is listed in pi's system prompt with its file path; the model reads it and follows it |

## One-time setup

### 1. Provider entries — baseUrl depends on where pi runs

The tunnel hostname differs per environment, so each environment carries its
own `models.json`:

- **Mac host** — the tested config from
  [connecting-local-models.md](./connecting-local-models.md) (`vllm-hpzgx`,
  baseUrl `http://localhost:8000/v1`) works as-is.
- **Devcontainer** — the container's `~/.pi/agent/` is seeded by
  `.devcontainer/scripts/setup-pi.sh`, and its `vllm-hpzgx` provider already
  points at `http://host.docker.internal:8000/v1` (see
  [devcontainer-pi-support-plan.md](./devcontainer-pi-support-plan.md)).
  Same provider name, different baseUrl, so `pi-once.sh`'s default
  (`vllm-hpzgx`) works in both environments — no env override needed.
- **Ollama** (optional) — add an `ollama-local` provider to whichever
  `models.json` you run from:

```json
{
  "providers": {
    "ollama-local": {
      "baseUrl": "http://localhost:11434/v1",
      "api": "openai-completions",
      "apiKey": "ollama",
      "models": [{ "id": "qwen3.5:4b", "name": "Ollama qwen3.5 4B", "contextWindow": 32768, "maxTokens": 8192, "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 } }]
    }
  }
}
```

(use `host.docker.internal:11434/v1` instead from the devcontainer).

Verify: `pi --list-models` must list the model before ralph will resolve it.

**Colon model ids are safe**: pi resolves `provider/id` by exact match *before*
treating a trailing `:<thinking>` as a thinking level, so `qwen3.5:4b` works —
as long as the model is registered in `models.json` (an unregistered id with an
unknown colon-suffix fails instead of guessing a different model).

### 2. (Optional) Expose the toolbox's own skills to pi

The vendored mattpocock-skills under `.agents/skills/` are **auto-discovered**
by pi from the project root (after project trust — the `-a` in the launch line
handles that). The repo's own `skills/` directory (`web-search-local`,
`fetch-news-local`, `fetch-free-images-local`) is **not** a pi discovery
location. To make those available, add a project settings file (`.pi/settings.json`):

```json
{ "skills": ["./skills"] }
```

or pass `--skill skills/web-search-local` (repeatable) on the launch line.

### 3. (Optional) Guardrail extension

pi runs with your user's full permissions and no per-command prompts
(pi's `security.md` docs: "Pi does not include a built-in sandbox"). For AFK runs
that is a feature — nothing stalls — but it also means `settings.ralph.json`'s
deny-force-push rule has no direct equivalent. Two levers:

- **Tool restriction** — `--tools read,edit,write,bash,grep,find,ls` (or
  `--exclude-tools`) narrows what the agent can do at all.
- **Command blocking** — a `tool_call` extension can block specific commands:

```typescript
// .pi/extensions/ralph-guardrail.ts  (auto-discovered once the project is trusted;
// or load explicitly with -e .pi/extensions/ralph-guardrail.ts)
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", (event) => {
    // Deliberately over-matching, like settings.ralph.json's prefix-denies:
    // also catches `git push --force-with-lease`.
    if (event.toolName === "bash" && /git push (\s--force|-f)/.test(event.input.command ?? "")) {
      return { block: true, reason: "force-push is not allowed in ralph runs" };
    }
  });
}
```

The return shape is `{ block: true, reason?: string, terminate?: boolean }`
(`terminate` additionally ends the agent run).

## The launch line — drop-in `pi-once.sh`

Same CLI as `once.sh` (`<issue-number> [--backend NAME] [--model NAME]`, same
`.env.ralph` support). The only structural difference: backends map to
`provider/model` patterns instead of env vars.

```bash
#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source environment
if [[ -f .env.ralph ]]; then
  set -a
  source .env.ralph
  set +a
fi

usage() {
  cat >&2 <<EOF
Usage: $0 <issue-number> [--backend NAME] [--model NAME]

  --backend  one of: anthropic | vllm | ollama
             default: \$RALPH_BACKEND, else 'vllm'
  --model    model id for the chosen backend
             default: \$RALPH_MODEL, else backend default

Backend -> pi provider (see ~/.pi/agent/models.json):
  vllm      -> vllm-hpzgx
  ollama    -> ollama-local
  anthropic -> built-in anthropic provider (model required)
EOF
  exit 1
}

ISSUE="${1:-}"
[[ -z "$ISSUE" ]] && usage
shift

BACKEND="${RALPH_BACKEND:-vllm}"
MODEL="${RALPH_MODEL:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --backend) BACKEND="${2:?--backend needs a value}"; shift 2 ;;
    --model)   MODEL="${2:?--model needs a value}";     shift 2 ;;
    -h|--help) usage ;;
    *) echo "error: unknown arg: $1" >&2; usage ;;
  esac
done

# Map backend -> pi model pattern (provider/id)
case "$BACKEND" in
  vllm)
    : "${MODEL:=${VLLM_DEFAULT_MODEL:-qwen}}"
    MODEL_PATTERN="vllm-hpzgx/$MODEL"
    ;;
  ollama)
    : "${MODEL:=${OLLAMA_DEFAULT_MODEL:-qwen3.5:4b}}"
    MODEL_PATTERN="ollama-local/$MODEL"
    ;;
  anthropic)
    # pi's catalog ids are not Claude Code's sonnet/opus shorthands — check `pi --list-models`
    [[ -n "$MODEL" ]] || { echo "error: anthropic backend needs --model (see 'pi --list-models')" >&2; exit 1; }
    MODEL_PATTERN="anthropic/$MODEL"
    ;;
  *)
    echo "error: --backend must be one of: anthropic, vllm, ollama (got '$BACKEND')" >&2
    exit 1
    ;;
esac

REPO="ekoepplin/agentic-toolbox"

echo "ralph-pi: backend=$BACKEND model=$MODEL_PATTERN issue=#$ISSUE" >&2

issue=$(gh issue view "$ISSUE" --repo "$REPO" \
  --json number,title,body,labels,state \
  --jq '"# Issue #\(.number): \(.title)\nState: \(.state)\nLabels: \(.labels | map(.name) | join(", "))\n\n\(.body)"')
commits=$(git log -n 5 --format='%h %ad %s' --date=short)
prompt=$(cat "$SCRIPT_DIR/prompt.md")

pi -a -p --model "$MODEL_PATTERN" --name "ralph #$ISSUE" \
  "MISSION: deliver issue #$ISSUE. Do NOT switch to other issues even if you see references to them.

$issue

Recent commits:
$commits

$prompt"
```

`afk.sh` needs exactly one change — the inner call:

```diff
-  "$SCRIPT_DIR/once.sh" "$ISSUE" "$@"
+  "$SCRIPT_DIR/pi-once.sh" "$ISSUE" "$@"
```

(or keep a `pi-afk.sh` copy and leave the Claude Code loop intact — the two
harnesses are then selectable per issue, which is sometimes useful: local
qwen for routine slices, Anthropic for the hard one).

### Launch flags, decoded

- **`-a` / `--approve`** — trust project-local resources for this run. Without a
  saved trust decision, non-interactive pi *ignores* `.agents/skills/` and
  `.pi/` resources, so this flag is what makes the vendored skills load.
  (Project trust ≠ permissions; it only gates resource loading.)
- **`-p`** — print mode: process the prompt, exit. `--mode json` / `--mode rpc`
  are the structured variants if you ever want machine-parseable progress.
- **`--model provider/id`** — full routing; the optional `:<thinking>` suffix
  (`vllm-hpzgx/qwen:high`) sets the thinking level on the fly.
- **`--name "ralph #N"`** — labels the session file in
  `~/.pi/agent/sessions/` for post-mortems; `--no-session` to skip saving.

## Adapting `prompt.md`

Two lines change; everything else (PRE-CHECK, EXPLORATION, STAGING DISCIPLINE,
COMMIT, KANBAN) is plain git/gh and carries over verbatim.

1. **CODE REVIEW** — replace `run /code-review on your diff` with:

   > Load and follow the `code-review` skill: its SKILL.md path is listed in the
   > available-skills block of your system prompt — read that file and follow it
   > on your diff (two-axis: Standards + Spec against this issue).

   This works headless because pi puts every visible skill in the system prompt
   with its absolute path and instructs the model to `read` it when the task
   matches. (Alternative: pass `/skill:code-review` as the prompt text — pi
   expands skill commands in print mode too, including for skills marked
   `disable-model-invocation`, which are otherwise hidden from the model.)

2. **FEEDBACK LOOPS** — drop the `claude --plugin-dir .` smoke check. On pi the
   skill tree is scanned from `.agents/skills/` at startup (deterministic, once
   trusted); `scripts/check.sh` is the gate. If you want a one-time visual
   confirmation, start interactive `pi -a` and check that `/skill:` autocomplete
   lists the vendored skills.

## The rest of the pipeline on pi

Stages 1–4 and 6 are just skills, so they run on pi as-is:

| Stage | Claude Code | pi |
|---|---|---|
| Think | `/grill-with-docs` | `/skill:grill-with-docs` |
| Spec | `/to-spec` | `/skill:to-spec` |
| Break down | `/to-tickets` | `/skill:to-tickets` |
| Triage | `/triage` | `/skill:triage` |
| Refactor | `/improve-codebase-architecture` | `/skill:improve-codebase-architecture` |

Run interactive pi in the repo (trusted, `-a` or a saved trust decision) and use
the `skill:`-prefixed commands. `enableSkillCommands` is on by default.
`/code-review` and `/diagnosing-bugs` are additionally model-invocable in either
harness; the others are `disable-model-invocation` in the vendored set, and pi
honors that flag exactly like Claude Code.

## Differences to know

- **No permission prompts, ever** — pi's built-in tools run with your user's
  permissions. `acceptEdits` has no counterpart because there is nothing to
  accept. That is what makes the AFK loop simpler; use `--tools` and/or the
  guardrail extension for the guardrails you had in `settings.ralph.json`.
- **Session files** — every `pi -p` run saves a session under
  `~/.pi/agent/sessions/` by default (one file per ralph iteration).
  `--session-dir` keeps them out of the way; `--no-session` throws them away.
- **Auto-compaction is on by default** — long AFK iterations won't overflow the
  context window; the footer shows live usage (e.g. `7.3%/262k (auto)`).
- **Thinking** — `qwen` is registered as a reasoning model; tune with
  `--thinking low|medium|high` or the `:<level>` model suffix.
- **Anthropic ids** — pi's catalog ids are not Claude Code's `sonnet` / `opus`
  shorthands. Get the exact ids from `pi --list-models`.
- **`models.json` is per-environment** — the Mac's file points at
  `localhost`; the devcontainer is seeded with its own copy pointing at
  `host.docker.internal` (see
  [devcontainer-pi-support-plan.md](./devcontainer-pi-support-plan.md)). The
  provider name is the same in both, so no flag differs.

## Smoke test

```bash
# 1. Provider registered
pi --list-models                                  # -> vllm-hpzgx qwen (262.1K context)

# 2. Endpoint + print mode (provider name is vllm-hpzgx in both environments)
pi -a -p --model vllm-hpzgx/qwen --no-tools --no-session "Say the word: ready"
# -> ready

# 3. Skills discovered (model-dependent sanity check — optional)
pi -a -p --model vllm-hpzgx/qwen --no-tools --no-session \
  "List the names of the skills available to you."

# 4. Dry iteration on a throwaway GitHub issue
agentic-workflow/ralph/pi-once.sh <scratch-issue>
# expect: one conventional commit, Closes #N trailer, issue auto-closed on push
```

## Validation

2026-09-11 — smoke-tested on this issue (#7): the pi loop delivered it itself
via `agentic-workflow/ralph/pi-once.sh` — provider `vllm-hpzgx`, model `qwen`,
local HP-ZGX endpoint (`http://localhost:8000/v1`). A single pi run did the
whole issue end to end: issue fetch, this single-file edit, the
`scripts/check.sh` gate, and a commit whose `Closes #7` trailer auto-closes
the issue on push.

## References

- [connecting-local-models.md](./connecting-local-models.md) — endpoint + provider registration (this doc's prerequisite)
- [configuration.md](./configuration.md) — pi's config files (`models.json`, `settings.json`), host vs docked-container seeding, adding config that survives a dock
- [devcontainer-pi-support-plan.md](./devcontainer-pi-support-plan.md) — pi in the devcontainer (seeded `models.json`, pinned extensions)
- [pi-extensions.md](./pi-extensions.md) — the pinned extension set + per-extension caveats (e.g. voice mic bridge)
- `agentic-workflow/MATT-WORKFLOW.md` — the pipeline this executes
- `agentic-workflow/ralph/{once.sh,afk.sh,prompt.md}` — the Claude Code loop this ports
- pi docs: <https://pi.dev/docs/latest/usage> (modes & flags), <https://pi.dev/docs/latest/skills>, <https://pi.dev/docs/latest/extensions> (`tool_call`), <https://pi.dev/docs/latest/security>
