# Moving data between workbenches

Every docked workbench is its own compose project, but they all run on the
same Mac and the scaffolder (`scripts/dock-host.sh`) gives each the same shared
mounts. That decides what can reach what:

| Path | Works? | Use it for |
|---|---|---|
| `~/agent-work` (shared folder) | ✅ | **The default.** Hand files from one workbench to another. |
| `~/agent-logs` (shared folder) | ✅ | Agent logs; readable from every workbench. |
| Docker socket (`docker cp` / `docker exec`) | ✅ | Reaching *into* another workbench. Root-equivalent — deliberate, one-off use only. |
| SSH via `host.docker.internal:<SSH_PORT>` | ⚠️ port reachable | Needs a private key inside the calling container; not set up. |
| Container network (by name) | ❌ | Each compose project has its own `<project>_default` network. |
| The other host repo | ❌ | A workbench mounts only its own repo plus the base. |

Verified 2026-10-17 between the `sprungjob` and `dlt-information-retrieval-utils`
workbenches.

## Shared folders

Both are bind-mounted from the Mac into every workbench:

| Mac | Workbench |
|---|---|
| `~/agent-work` | `/home/node/agent-work` |
| `~/agent-logs` | `/home/node/agent-logs` |

A file written by one workbench is visible to all others and to the Mac at
once, and survives container rebuilds:

```bash
# in workbench A
cp result.parquet ~/agent-work/
# in workbench B (or on the Mac: ~/agent-work/)
ls ~/agent-work/
```

Use a subdirectory per hand-off (e.g. `~/agent-work/sprungjob-to-dlt/`) —
the folder is shared by every workbench, so loose files collide.

## Docker socket

The host's Docker socket is mounted in every workbench (docker-outside-of-docker),
so one workbench can operate on another:

```bash
docker cp ./file dlt-information-retrieval-utils-workbench-1:/tmp/
docker exec -u node dlt-information-retrieval-utils-workbench-1 cat /tmp/file
```

`docker cp` cannot target a bind-mounted Mac folder such as `~/agent-work` —
it fails with `failed to Lchown … permission denied`. Files already go there
without it: write them to the shared folder directly.

That is full control over every container on the Mac, not a scoped channel —
prefer the shared folder for routine hand-offs.

## Not wired up

- **Network by name.** Workbenches cannot resolve each other. Making that work
  needs a shared external Docker network added to each host's `compose.yaml`;
  no current need for it.
- **SSH between workbenches.** The published SSH ports are reachable via
  `host.docker.internal`, but no workbench holds a private key to log in with.
