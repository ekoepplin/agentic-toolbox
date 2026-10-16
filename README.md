# agentic-toolbox

The agentic development **base**: the environment (base image + compose stack)
and the shared agentic content (skills, subagents, slash commands, hooks) that
host projects **dock** into at runtime to get agentic development across every
supported harness. The Claude Code **plugin** under `.claude-plugin/` is the
base's Claude Code harness adapter. See `CONTEXT.md` for the domain vocabulary.

Shipped components are invoked under the `/agentic-toolbox:` namespace, so
they never collide with a host project's own skills.

## How host projects use this

Host projects **dock** the base: `make dock HOST=<path-to-host-repo>`
scaffolds the workbench stack, and the dock step wires every harness adapter
on each workbench start (see `docs/harnesses/dock-e2e.md`).

## Connect to a workbench

Each workbench runs sshd; its published port is `SSH_PORT` in the host's `.env`
(the base's own workbench uses `2224`).

```bash
docker compose up -d                 # in the host repo (or this repo)
ssh -p <SSH_PORT> node@localhost
```

- **Keys** — put your public key(s) in `~/.ssh/container_authorized_keys` on
  the Mac. The dock step syncs that file into the container on every start;
  password and root login are disabled.
- **After an image rebuild** the container has new SSH host keys — clear the
  old one first: `ssh-keygen -R "[localhost]:<SSH_PORT>"`.
- **Ghostty** works out of the box: the image (Debian 13 trixie) ships its
  terminfo, aliased as `xterm-ghostty`, so `less`, `tmux` and other TUIs
  behave without overriding `TERM`.
- **Shell** — zsh with Oh My Zsh and Powerlevel10k; on SSH login a tmux session
  picker opens. The prompt config `.devcontainer/p10k.zsh` is a copy of the
  Mac's `~/.p10k.zsh` — re-copy it after `p10k configure` on the Mac, then
  `make image`.
- The SSH port is published on all interfaces (for Tailscale/mobile access);
  key-only auth is what protects it.

