# Configuring pi

pi keeps its configuration in `~/.pi/agent/`. Two files matter for this repo:

| File | Holds | Seeded by dock? |
|---|---|---|
| `models.json` | Providers + models (endpoints, wire API, reasoning flags, cost) | Yes — `vllm-hpzgx`/`qwen` block |
| `settings.json` | `defaultProvider`, `defaultModel`, `skills[]`, extension `packages[]` | Yes — defaults + skill paths |

Both are plain JSON and re-read on demand (`models.json` reloads every time you
open `/model` — no restart needed).

## Two places config lives

pi runs in two environments, and each has its **own** `~/.pi/agent/` (they are
not shared — the container has its own home):

1. **Host (your Mac).** You hand-edit `~/.pi/agent/models.json` yourself. The
   endpoint is reached over the SSH tunnel at `localhost:8000`. This is the path
   in [connecting-local-models.md](./connecting-local-models.md) — the qwen
   providers currently registered on the host live here.
2. **Docked workbench (container).** `.devcontainer/scripts/dock.sh` **seeds**
   the container's `models.json` and `settings.json` on every workbench start.
   The endpoint is reached via `host.docker.internal:8000` (the tunnel is on the
   host's loopback, unreachable as `localhost` from inside the container).

**Key consequence:** editing the host's `models.json` does *not* propagate a new
provider into the workbench. The container is seeded from `dock.sh`, not from
your host file. To make config available in **both** places you edit both — see
below.

## Adding config on the host

Add or extend `~/.pi/agent/models.json` directly, then verify with `/model`.
The full walkthrough (bringing the endpoint up, reading the served model id,
the `compat` flags a Qwen3 reasoning model needs, making it the default) is in
[connecting-local-models.md](./connecting-local-models.md). That doc is the
reference for the shape of a provider/model entry.

## Adding config that survives a dock

The dock seed is an **idempotent upsert** (`dock.sh`, `seed_models` /
`seed_settings`): it sets the keys it owns and leaves every other key the user
added untouched. It rewrites the file only when the content actually changes, so
re-docking is a no-op when already in sync.

Because the seed *always* re-asserts the block it owns, a provider you want in
the workbench must be added to the seed function — otherwise a fresh container
simply won't have it. To add a new provider or model to the workbench:

1. Edit `seed_models` (or `seed_settings`) in
   `.devcontainer/scripts/dock.sh`. Add your provider to the `providers` dict
   using **`host.docker.internal`** in the `baseUrl`, not `localhost`.
2. Mirror the same entry into the host's `~/.pi/agent/models.json` (with
   `localhost`) if you also want it when running pi outside the container.
3. Re-dock (`make dock HOST=<path>`, or restart the workbench) — the upsert
   writes the new block and reports `models.json updated`.

Keep the two in sync deliberately: the only intended difference between the host
entry and the seeded entry is the `baseUrl` host (`localhost` vs
`host.docker.internal`).

## Related config

- **Extensions** are pinned separately in `.devcontainer/pi-extensions.lock` and
  installed after the config is seeded — see [pi-extensions.md](./pi-extensions.md).
- **Skills** are exposed to pi via the `skills[]` array in `settings.json`,
  which `dock.sh` points at the base's shipped + vendored skill directories.

## Validate

After changing either file:

```bash
# 1. The file is still valid JSON (a truncated/comma-broken file makes pi ignore it)
python3 -m json.tool ~/.pi/agent/models.json > /dev/null && echo "models.json OK"

# 2. pi actually lists the provider/model (host)
pi -p --provider <provider> --model <model> --no-tools --no-session "Say: ready"
# -> ready

# 3. The dock seed is well-formed and idempotent (safe to re-run; reports
#    "in sync" or "updated", never errors)
bash .devcontainer/scripts/dock.sh
```

Inside the workbench, repeat step 2 against the seeded provider to confirm the
`host.docker.internal` endpoint resolves.

## References

- [connecting-local-models.md](./connecting-local-models.md) — provider/model entry shape, endpoint bring-up, `compat` flags
- [devcontainer-pi-support-plan.md](./devcontainer-pi-support-plan.md) — the devcontainer pi plan (seeded `models.json`, pinned extensions)
- [pi-extensions.md](./pi-extensions.md) — pinned extension set + runtime deps
- pi docs — models & providers: <https://pi.dev/docs/latest/models>
