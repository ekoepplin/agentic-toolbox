# Local model + Claude

Run a coding model on your own GPU machine, use it from your laptop, and pair it with Claude:
Claude plans and judges, the local model does the work. Companion to two posts on
datadidact.com (links follow on publication); the posts explain the *why* in detail.

Not a turnkey installer. Your hardware, model and server will differ from mine. These files
show the shape of the setup; adapt names, ports and context sizes to yours.

## The big picture

```
 laptop                                    GPU machine
┌──────────────────────┐   SSH tunnel    ┌───────────────────────────┐
│ Claude Code  /  Pi   │ ──────────────> │ model server              │
│                      │  localhost:8000 │ (vLLM, llama.cpp, Ollama) │
└──────────┬───────────┘                 └───────────────────────────┘
           │ internet
           v
     Claude (cloud): refine the request, plan, judge
```

1. **Serve a model on the GPU machine.** Pi needs the OpenAI API; Claude Code needs the
   Anthropic API (`/v1/messages`). Recent vLLM and llama.cpp offer both. Bind to `127.0.0.1`.
2. **Reach it from the laptop** through an SSH tunnel (`ssh -L 8000:localhost:8000 gpu-box`),
   optionally over Tailscale. Nothing is open to the network.
3. **Point your agent at it.**
   - Claude Code: `source clients.sh`, then `claude-local`.
   - Pi: add the server as a provider in `~/.pi/agent/models.json`:
     ```json
     { "providers": { "gpu": {
         "baseUrl": "http://localhost:8000/v1", "api": "openai-completions", "apiKey": "local",
         "models": [{ "id": "<id from /v1/models>", "contextWindow": 131072, "maxTokens": 32000 }]
     } } }
     ```
     Then `pi --model gpu/<id>`.

Check the server: `./check.sh` (model list, plain chat, a tool call over the Anthropic API).

## Three things that trip people up

- **Tell the agent the context window.** Claude Code does not know your model and assumes 200k
  tokens, so it compacts too late. `claude-local` sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS`.
- **Map Claude Code's model tiers.** It sends background requests to haiku/sonnet/opus by name.
  `claude-local` points all three at your local model.
- **There is no sandbox.** The agent runs `bash` as you. In one of my runs the local model ran
  `pip install` without being asked; in another it wrote a file into a different repo on my
  laptop before it noticed and deleted it again. Use a throwaway directory, container or VM.

## Claude + local: three ways

| | Orchestrator (`hybrid-orchestrator.ts`) | Split loop (`loop.sh`) | Router (`hybrid-router.ts`) |
|---|---|---|---|
| Idea | One interactive Pi session; a [virtual model](https://docs.pi.dev/latest/virtual-models) runs plan → build → review | Separate Pi runs per phase, driven by a script | One Pi session; the virtual model switches to local after Claude's first edit |
| Roles | Enforced: Claude cannot edit, write or run bash | Enforced: the executor sees only the plan, the judge only reads | Fuzzy: Claude often finished the work before the switch |
| Who says "done" | A script runs the plan's checks, then Claude scores | A script runs the plan's checks, then Claude scores | The model |
| You talk to Claude | yes, it can ask you before planning | only before: you write the plan with Claude | yes |

**Orchestrator**, the one I use day to day. Select one model, `hybrid/orchestrate`, and every
prompt runs through three phases:

```
 you ──prompt──> plan    (Claude)  reads the code, asks you if unclear, calls `handoff`:
                                   steps, acceptance criteria, files, Verify commands
                 build   (local)   implements the plan, stops
                 verify  (script)  runs the Verify commands ── red ──> back to build
                 review  (Claude)  reads the result, scores each criterion 0–2, calls
                                   `verdict` ── fail ──> back to build, with feedback
                                             ── pass ──> done
```

- **Roles are enforced, not suggested.** In plan and review, the extension blocks `edit`,
  `write` and `bash`, so Claude cannot quietly do the work itself. That was the weak spot of the
  router. `handoff` only works in plan, `verdict` only in review.
- **The script decides "green", not a model.** The extension runs the Verify commands itself.
  Claude's score is the second opinion on top.
- **At most three build rounds per prompt** (`HYBRID_MAX_ROUNDS`). Then it stops and shows what
  is still red.
- **Fallbacks:** local server down at the start of a round → Claude builds that round. A failed
  local request retries on Claude. Compaction summaries go to the local model when it is up.
- The footer shows the phase, the round and who is working, e.g. `build · round 1/3 · local`.

```bash
HYBRID_WORKER=gpu/<id> pi -e ./hybrid-orchestrator.ts --model hybrid/orchestrate
```

To load it in every session, copy the file to `~/.pi/agent/extensions/` and set
`HYBRID_WORKER` in your shell. Want to watch round 2 fix what round 1 missed? Add checks neither
model sees up front: `HYBRID_HIDDEN_VERIFY=hidden-verify.txt` (with a slugify task). Keep them
consistent with the plan, or no round can pass.

**Split loop**, the same idea without a session, for planned work you start and walk away from:

1. Talk the task through with Claude until it writes a plan: task, acceptance criteria, files,
   and a `## Verify` block with shell commands. Example: [`plan.md`](plan.md).
2. The local model implements the plan.
3. The script runs the Verify commands. A failure goes back to the local model as feedback.
4. Claude reads the result with read-only tools and scores each criterion; its feedback goes
   into the next round.

```bash
w=$(mktemp -d) && git -C "$w" init -q
EXEC=gpu/<id> ./loop.sh plan.md "$w"
# plus checks the executor does not see up front, to watch round 2 fix round 1:
EXEC=gpu/<id> HIDDEN_VERIFY=hidden-verify.txt ./loop.sh plan.md "$w"
```

**Router**, for comparison:

```bash
HYBRID_WORKER=gpu/<id> pi -e ./hybrid-router.ts --model hybrid/auto
```

All three use `anthropic/claude-opus-5-5` for Claude (`JUDGE` / `HYBRID_PLANNER` to change).

## Claude access

- **API key** (`ANTHROPIC_API_KEY`): billed per token, clearly within Anthropic's terms.
- **Pro/Max subscription in Pi** (`/login anthropic` plus
  [`@gotgenes/pi-anthropic-auth`](https://www.npmjs.com/package/@gotgenes/pi-anthropic-auth)):
  what I use. Anthropic intends subscription OAuth for "the unmodified Claude Code binary"
  ([legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)). Decide for yourself.

## The full version

[`agentic-workflow/ralph/`](../../agentic-workflow/ralph/) runs the same idea on GitHub issues:
stamped plans, a worktree per ticket, scope gate, PR as a bot account, never a merge.

Written against Pi 1.5.2 and Claude Code 2.1.311 (2026-11). APIs move; expect to adapt.
