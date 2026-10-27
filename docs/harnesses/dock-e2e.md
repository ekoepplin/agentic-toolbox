# The dock E2E — the runtime gate

The runtime counterpart of the static drift guard. `scripts/check.sh` is the
static half: it proves the adapter-manifest contract (`plugin.json` ↔ shipped
skills on disk) holds in the working tree. The dock E2E is the runtime
half: it proves the docked base actually works in a host project's workbench —
every harness adapter wired, the pinned vendored set intact, the dock step's
guardrails live — in one deterministic run against a throwaway host project.
The static guard cannot see runtime wiring; the E2E cannot see contract
drift. Both must be green.

## One command

From a clean state (no scratch project):

```bash
make dock-e2e            # or: scripts/dock-e2e.sh
```

The command:

1. **Scaffolds** a scratch host project in a temp dir — the #11 scaffolder
   (`scripts/dock-host.sh`): exactly the three-file tree
   (`compose.yaml`, `.env`, `.devcontainer/devcontainer.json`), a free SSH
   port, the base image built if missing.
2. **Brings the scratch workbench up** (`docker compose up -d`) and waits for
   the dock step (issue #10) to finish wiring every harness adapter on start.
3. **Runs the #10 probe battery** inside the workbench
   (`.devcontainer/scripts/probe-dock.sh` — the same probes the dogfooded
   workbench runs via `make probe-dock`), reusing the deterministic probe
   techniques from the earlier pi E2E:
   - Claude adapter — the plugin loads via `--plugin-dir` and its inventory
     lists every skill in `plugin.json` (the probes read the manifest; none
     hard-codes skill names or counts);
   - the dock alias is wired for interactive shells;
   - pi model-list probe — `pi --list-models` lists the seeded
     `vllm-hpzgx/qwen` provider (catalog only, no endpoint call);
   - pi deterministic skill expansion — the `get_commands` RPC table lists
     `skill:<name>` for every shipped skill plus the vendored
     `skill:code-review`;
   - the base's skill paths are seeded in pi's container config;
   - SSH keys are synced — `authorized_keys` matches the staged host file
     (`~/.ssh/container_authorized_keys`) and is mode 600, so a
     `docker compose up` workbench accepts SSH logins without VS Code's
     `post-create.sh`;
   - a second dock run is a no-op (pin satisfied, container state in sync).
4. **Verifies pin fidelity** — the vendored set's HEAD equals the ref pinned
   in `.devcontainer/skills.lock`.
5. **Verifies the dirty-base warning** — a transient marker file dirties the
   base mount; the next dock step run must warn about uncommitted content.
6. **Tears down** — `docker compose down` plus removal of the scratch project
   and the marker. No residue, even when a probe fails. The base image is
   shared canonical state, not scratch state, so it is kept.

Every probe is deterministic: no LLM call, no model endpoint needed. The test
exits non-zero on any probe failure, so it is a gate.

## When to run it

- After any change to the dock step (`dock.sh`), the scaffolder
  (`dock-host.sh`), the base image, or `skills.lock` — none of which the
  static guard can see.
- On a fresh machine / fresh clone, before running ralph unattended.

## Running the gates inside a workbench

Checked 2026-10-27 (#26) in the base's own workbench on colima (Docker
server 27.4.0), with the Docker CLI talking to the Mac's daemon through the
mounted socket. **Run `make image`, `make probe` and `make dock-e2e` on the
Mac.** Inside a workbench only the subset below works:

| Gate | Inside a workbench | Why |
|---|---|---|
| `make check` | ✅ | static, no Docker |
| `make probe` | ❌ | it depends on `make image`, which fails at once: the image has no buildx plugin and the Makefile forces BuildKit |
| `make -o image probe` | ✅ | probes the **existing** image without rebuilding — proves nothing about a Dockerfile change |
| `make probe-dock` | ❌ | `docker compose` is not installed (only `docker-ce-cli`) |
| `bash .devcontainer/scripts/probe-dock.sh` | ✅ | the same probes, run in the current workbench (run `.devcontainer/scripts/dock.sh` first so they see the change) |
| `make dock-e2e` | ❌ | needs `docker compose`; behind that, two more blockers (below) |

Don't run `make image` inside a workbench even once buildx exists: it passes
the container's `$HOME` (`/home/node`) as `HOST_HOME`, so the rebuilt shared
image would lose the Mac-path `~/.claude/hooks` mirror for every workbench.

**Bind mounts resolve on the Mac, not in the container.** The daemon reads a
mount source as a path on the Mac (through colima's home share), so from
inside a workbench:

| Mount source | Result |
|---|---|
| the mirrored base path (ADR-0004) | ✅ the real files |
| a Mac path such as `/Users/<user>/.claude` | ✅ the real files |
| the container's `/tmp/...` | ❌ an empty directory |
| the container's `$HOME/...` (`/home/node/...`) | ❌ an empty directory |

So `dock-e2e.sh` would still break with compose installed: its scratch host
lives under the container's `/tmp`, and the generated `compose.yaml`
interpolates `${HOME}` for `~/.claude`, `~/.claude.json` and the staged
`authorized_keys`, which become empty mounts (not run: Docker creates a missing
`-v` source as a directory, so the staged keys file would arrive as an empty
directory and the SSH-key probe would fail).

**Consequence for the ralph loop:** qwen's verify commands may use only the
✅ rows. Tickets that change the image, the scaffolder or the E2E itself need
their runtime gate run on the Mac, so refine routes them to the owner instead
of qwen. Making the full set work in a workbench would take: the
`docker-compose-plugin` (and `docker-buildx-plugin`) in the image, a scratch
dir under a mirrored path, and the Mac home passed explicitly instead of
`${HOME}` / `$(HOME)`.
