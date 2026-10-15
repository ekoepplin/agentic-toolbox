# The dock E2E — the runtime gate

The runtime counterpart of the static drift guard. `scripts/check.sh` is the
static half: it proves the adapter-manifest contract (`plugin.json` ↔ shipped
skills on disk ↔ README) holds in the working tree. The dock E2E is the runtime
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
   - Claude-adapter skill expansion — the `--plugin-dir` plugin inventory
     lists the three shipped skills under the toolbox namespace;
   - the dock alias is wired for interactive shells;
   - pi model-list probe — `pi --list-models` lists the seeded
     `vllm-hpzgx/qwen` provider (catalog only, no endpoint call);
   - pi deterministic skill expansion — the `get_commands` RPC table lists
     `skill:web-search-local` (base shipped) and `skill:code-review`
     (vendored);
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
