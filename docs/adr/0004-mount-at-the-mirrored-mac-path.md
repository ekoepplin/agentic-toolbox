# Mount the host repo and the docked base at their mirrored Mac paths

**Status:** accepted

When a **host project** docks the **base**, the host's compose **workbench** has to get two trees into the container: the host repo (the workspace) and the docked base. The obvious convention is a fixed, distinct mount point (`/workspace`, `/opt/base`), regardless of where the repos live on the Mac. The alternative: bind each repo at the exact absolute path it already has on the Mac (`/Users/ekoepplin/repos/<repo>:/Users/ekoepplin/repos/<repo>`), so the container's filesystem mirrors the Mac's.

We mount at the **mirrored Mac path**: the host repo is the workbench's `working_dir` at its Mac path, and the base is docked at its own Mac path — the same path in every host's workbench (the scaffolder's `BASE_PATH`).

Rationale — content arrives unmodified:

- **Shared content is full of absolute paths.** `CLAUDE.md` files import this repo by absolute path (`@/Users/ekoepplin/repos/agentic-toolbox/CLAUDE.md`); hooks, skill scripts, the ralph loop, agent logs, and devcontainer settings all do the same. With a mirrored mount the same file resolves the same inside the workbench as on the Mac — no per-host path-rewriting layer, no indirection, nothing to drift.
- **One path, every workbench.** Because the base's mirrored path is identical in the base's own workbench and in every host's, the base can reference its own scripts by absolute path from anywhere (the compose `command` runs `${BASE_PATH}/.devcontainer/scripts/dock.sh`), and the scaffolder (`scripts/dock-host.sh`) emits one canonical `BASE_PATH` instead of discovering each host's layout.
- **Mac and container share one address space for content.** A session on the Mac and a session in the workbench read and write the same files at the same paths, so state (git working tree, agent logs, scratch space) is continuous rather than translated.

Consequences:

- **The container layout is coupled to one Mac user's layout.** The username and repo paths are baked into the host's committed files and into the base image (the macOS-style `/Users/<user>/.claude` symlink, overridable via the `MAC_USER` build arg). Moving the base on the Mac, or docking from a different machine or user, is a re-dock — an explicit act the scaffolder refuses to perform silently.
- **The mount looks like a no-op in compose files** (source and target path identical). It is not: collapsing it to a distinct mount point would break every absolute path above. Do not "simplify" it.
