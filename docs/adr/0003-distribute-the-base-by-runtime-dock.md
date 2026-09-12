# Distribute the base by runtime dock, not by installing a plugin

**Status:** accepted — supersedes [ADR-0002](0002-distribute-as-a-claude-code-plugin-via-marketplace.md)

The **base** (see `CONTEXT.md`) is consumed by **host projects**: they need the base's content — skills, subagents, commands, hooks, docs — inside working agent sessions for every supported **harness** (today, Claude Code and pi), inside the base's docker image and compose environment. ADR-0002 answered that question back when the answer was a Claude Code plugin installed from a marketplace: one harness, one install step, and no environment at all. The decision had to be reopened. The options considered:

- **Keep the marketplace plugin** — consumers `claude plugin install` the Claude Code **harness adapter**; pi and the workbench environment would need separate, per-consumer wiring.
- **Runtime dock** — a host project's compose **workbench** bind-mounts the base repo at a fixed path, and the **dock step** (`.devcontainer/scripts/dock.sh`) wires every harness adapter into its discovery paths on every workbench start. No packaging, no publishing, no install.

We distribute the base **exclusively by runtime dock**. The marketplace delivery route is **retired**: there is no `marketplace.json`, no `claude plugin marketplace add`, no install step. The Claude Code **plugin** survives as the base's Claude Code harness adapter — `.claude-plugin/plugin.json` remains the adapter-manifest contract for what counts as shipped — but inside a docked workbench Claude Code loads it from the mounted base (`--plugin-dir`), not from a marketplace install.

Rationale:

- **One delivery mechanism for every harness.** The dock step is the single place where content reaches a harness, so adding a harness is a change to one script, not a new distribution channel per harness.
- **No publish step between base and host.** A host gets whatever is in the base's working tree: upgrades are a `git pull` in the base, and the dock step's dirty-base warning makes uncommitted content visible at boot instead of silently shipped.
- **The base dogfoods its own dock.** The root `compose.yaml` is the base's own workbench, docked at the base's own Mac path; host workbenches are structurally identical. That is what lets the dock E2E (`scripts/dock-e2e.sh`, `docs/harnesses/dock-e2e.md`) prove the full pipeline on a scratch host project with the same probes the dogfooded workbench runs.
- **Model inference is deliberately out of compose scope.** The workbench runs no inference service: the local model endpoint lives on a separate machine (the HP-ZGX box — one shared GPU, one backend serving at a time; see `docs/harnesses/pi-agent-harness/connecting-local-models.md`), is tunneled to the Mac's loopback, and is reached from inside the workbench via `host.docker.internal`. Keeping inference out of the stack keeps the workbench to a single service and keeps model lifecycle (start, evict, switch backends) on the machine that owns the GPU.

Consequences:

- **The base is personal, not public.** A host docks a local clone of the base at a fixed path (`BASE_PATH` in the host's committed `.env`); anyone without that clone cannot consume the base. Deliberate — this is a personal base, not a public package.
- **The dock step is load-bearing runtime.** It runs on every workbench start, must stay idempotent (a second run is a no-op), and must never take the workbench down when it fails. The dock E2E is the runtime gate; `scripts/check.sh` is the static gate on the adapter-manifest contract.
- **Upgrades are unversioned.** A host sees the base's working tree, not a released revision; reproducibility rests on the base's git state (hence the dirty-base warning), not on a marketplace version.
- **ADR-0002's marketplace consequences are void.** `marketplace.json` is gone and "consumer repo" is retired vocabulary (see `CONTEXT.md`). What survives of ADR-0002 is namespaced `/agentic-toolbox:<name>` invocation and `plugin.json` as the shipped/draft contract — both now delivered by docking.
