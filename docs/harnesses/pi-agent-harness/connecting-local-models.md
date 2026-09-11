# Connecting local models to pi

[pi](https://pi.dev/) is a minimal agent harness ("adapt pi to your workflows, not
the other way around"). It ships with 15+ providers, but any OpenAI-compatible
endpoint — including a **local/self-hosted vLLM or SGLang server** — can be added
through `~/.pi/agent/models.json`. This doc covers the HP-ZGX setup used here.

## How pi discovers models

- Custom providers/models live in `~/.pi/agent/models.json`.
- The file is re-read every time you open `/model` — no restart needed.
- A provider is any endpoint; `api` selects the wire protocol:
  - `openai-completions` — OpenAI Chat Completions (**use this for vLLM/SGLang**)
  - `openai-responses`, `anthropic-messages`, `google-generative-ai`
  - SGLang qwen38 also serves the **Anthropic** API on the same port
    (`/v1/messages`), so `anthropic-messages` with `baseUrl: http://localhost:8000`
    works too — but the `openai-completions` config below is the tested path.
- Defaults are set in `~/.pi/agent/settings.json` (`defaultProvider`, `defaultModel`).

## vLLM/SGLang on HP-ZGX

**All inference runs on the HP-ZGX host** (a GB10 box, 192.168.178.103). The Mac
only holds the SSH tunnel and runs the client. The models run in Docker containers
on ZGX (`sglang-qwen38`, `vllm-dflash`, …), started by `service/utils/start-*.sh`
scripts that Ansible deploys to `/usr/local/bin` there. The GB10 has one shared GPU
memory pool and one port 8000, so **only one backend serves at a time** — switching
auto-evicts the previous one (`stop-inference`).

### 1. Bring the endpoint up

Drive it from the Mac with `start-local-setup` (from the `hp-zgx-workflow` repo,
`service/mac/start-local-setup.sh`, symlinked onto `PATH`). It opens/repairs the SSH
tunnel that forwards `11434/8000/8004/3000`, starts the chosen backend on ZGX over
SSH, and blocks until a real generation succeeds:

```bash
start-local-setup            # default --qwen38: SGLang Qwen3.8-27B NVFP4 on :8000
# other backends: --dflash (vLLM AEON DFlash), --vllm, --fp8 (:8004), --ollama (:11434)
start-local-setup --status   # report only, start nothing
```

The tunnel relies on this `~/.ssh/config` entry:

```
Host HP-ZGX
    HostName 192.168.178.103
    LocalForward *:11434 localhost:11434
    LocalForward *:8000  localhost:8000
```

Verify the endpoint is live and read the exact model id:

```bash
curl -sf http://localhost:8000/v1/models | python3 -m json.tool
```

The `data[].id` value is what you pass to pi as the model `id`. (As currently
served: `id` = `qwen`, `max_model_len` = 262144. Note the endpoint reports
`owned_by: sglang` — it's SGLang, not vLLM proper, but it's OpenAI-compatible all
the same, so `openai-completions` is still correct. `qwen` is also a **reasoning
model**: it returns a separate `reasoning_content` field, so mark it
`"reasoning": true` and set `"compat": { "thinkingFormat": "qwen" }` on the
provider — see the config below.)

### 2. Register the provider

Add to `~/.pi/agent/models.json`:

```json
{
  "providers": {
    "vllm-hpzgx": {
      "baseUrl": "http://localhost:8000/v1",
      "api": "openai-completions",
      "apiKey": "vllm",
      "compat": {
        "thinkingFormat": "qwen",
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false
      },
      "models": [
        {
          "id": "qwen",
          "name": "HP-ZGX qwen (local)",
          "reasoning": true,
          "contextWindow": 262144,
          "maxTokens": 32000,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
```

For a non-reasoning model, drop `"reasoning": true` and the whole `compat` block.
For the Qwen3 thinking model served here, all three `compat` flags are needed:
`thinkingFormat: "qwen"` parses the separate `reasoning_content` field, and
`supportsDeveloperRole: false` + `supportsReasoningEffort: false` stop pi sending
the `developer` role / `reasoning_effort` param that this SGLang server rejects
with a bare `400` (verified — without them, print mode silently returns nothing).

- `apiKey` is a **placeholder**. vLLM ignores it unless launched with `--api-key`,
  but pi treats every model as auth-gated and won't list it in `/model` without a
  non-empty value. If vLLM *does* enforce a key, use `"$VLLM_API_KEY"` and export
  the real one (pi resolves `$VAR`, `!shell-command`, or a literal string).
- `cost` is set to all-zeros so pi's budgeting stays quiet on a free local model.

### 3. Make it the default

`~/.pi/agent/settings.json`:

```json
{
  "defaultProvider": "vllm-hpzgx",
  "defaultModel": "<served-model-name>"
}
```

Or pick it per session inside pi with `/model`.

### 4. Run it

Launch the interactive TUI against the local model (leaves your global default
untouched):

```bash
pi --provider vllm-hpzgx --model qwen
```

Or, once the endpoint is up (`start-local-setup --status`), a quick non-interactive
check — this is the exact command used to verify the setup:

```bash
pi -p --provider vllm-hpzgx --model qwen --no-tools --no-session "Say the word: ready"
# -> ready
```

Add `--thinking low|medium|high` to tune reasoning depth.

## Troubleshooting

- **Model missing from `/model`** — `apiKey` is empty. Set the placeholder, or run
  `/login` for the provider, or pass `--api-key` when selecting the model.
- **400s on a reasoning model** — vLLM's OpenAI server often rejects the `developer`
  role and `reasoning_effort`. Add to the provider (or a single model) block:

  ```json
  "compat": { "supportsDeveloperRole": false, "supportsReasoningEffort": false }
  ```

- **Connection refused at `localhost:8000`** — the forward is up but vLLM isn't
  serving yet. Confirm the remote `dflash` session is running and healthy:
  `ssh HP-ZGX 'curl -sf http://localhost:8000/health'`.
- **Sampling params** — for OpenAI-compatible providers you can set
  `"samplingParams": { "temperature": 0.2 }` on a model entry.

## References

- pi docs — models & providers: <https://pi.dev/docs/latest/models>
- Source: `earendil-works/pi` → `packages/coding-agent/docs/models.md`, `providers.md`
