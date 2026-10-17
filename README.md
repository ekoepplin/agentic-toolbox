# agentic-toolbox

The agentic development **base**: the environment (base image + compose stack)
and the shared agentic content (skills, subagents, slash commands, hooks) that
host projects **dock** into at runtime to get agentic development across every
supported harness (Claude Code, [pi](https://pi.dev/) and the
[GitHub Copilot CLI](docs/harnesses/copilot.md)). The Claude Code
**plugin** under `.claude-plugin/` is the base's Claude Code harness adapter.
See `CONTEXT.md` for the domain vocabulary and `docs/adr/` for the decisions.

In Claude Code, shipped components are invoked under the `/agentic-toolbox:`
namespace, so they never collide with a host project's own skills; pi uses
`skill:<name>`, Copilot `/<name>`.

## Quick start

Requires Docker (Docker Desktop or colima) and `make`.

```bash
git clone https://github.com/ekoepplin/agentic-toolbox.git ~/repos/agentic-toolbox
cd ~/repos/agentic-toolbox
make image                 # build the base image (agentic-toolbox-base:latest)
make probe                 # optional: verify the image
docker compose up -d       # start this repo's own workbench
ssh -p 2224 node@localhost
```

The repo is mounted into the container at its own host path (ADR-0004). If you
clone somewhere other than `~/repos/agentic-toolbox`, export `BASE_PATH` with
the absolute path before `docker compose up`.

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
  the host. The dock step syncs that file into the container on every start;
  password and root login are disabled.
- **After an image rebuild** the container has new SSH host keys — clear the
  old one first: `ssh-keygen -R "[localhost]:<SSH_PORT>"`.
- **Ghostty** works out of the box: the image (Debian 13 trixie) ships its
  terminfo, aliased as `xterm-ghostty`, so `less`, `tmux` and other TUIs
  behave without overriding `TERM`.
- **Shell** — zsh with Oh My Zsh and Powerlevel10k; on SSH login a tmux session
  picker opens. Prompt config lives in `.devcontainer/p10k.zsh` — replace it
  with your own `~/.p10k.zsh` and `make image` to change it.
- **Claude Code status line** —
  [claude-powerline](https://github.com/Owloops/claude-powerline) (repo, git
  branch, model, tokens, cost), set in the image's
  `/etc/claude-code/managed-settings.json`. Managed settings outrank the
  `~/.claude/settings.json` mounted from the Mac, so only workbenches get it;
  the Mac's own status line is untouched. The glyphs need a Nerd Font in the
  terminal (Ghostty has them built in).
- **git** works on the mounted repos: the image sets `safe.directory '*'`,
  because they are owned by the Mac's uid, not by `node`.

## Voice

Claude Code `/voice` works inside every workbench, recording from the Mac's
microphone through a PulseAudio server on the Mac. One-time setup per Mac:

```bash
scripts/setup-mac-voice.sh   # PulseAudio as a brew service on 127.0.0.1:4713
make probe-voice             # speak while it records
```

Details, Mac mini notes and troubleshooting: `docs/voice.md`.

## Moving data between workbenches

Workbenches don't share a network, but every one mounts `~/agent-work` and
`~/agent-logs` from the Mac — drop a file in `~/agent-work` in one workbench,
read it in another. What else can and can't reach across: `docs/cross-workbench.md`.

## Optional: a bot identity for pi

Set these on the host to make pi commit and push as a dedicated GitHub
account (e.g. a bot); unset, pi uses your normal git identity:

```bash
export PI_GIT_USER=my-bot
export PI_GIT_EMAIL=12345+my-bot@users.noreply.github.com   # optional
export PI_GH_TOKEN=<the bot's PAT, scopes repo + workflow>
```

## Security notes

The workbench is a trusted, single-user dev environment — read before running:

- The SSH port is published on **all interfaces** (for Tailscale/mobile
  access); key-only auth is what protects it. Change `0.0.0.0` to `127.0.0.1`
  in `compose.yaml` to keep it local.
- The host's **Docker socket** is mounted (docker-outside-of-docker), which is
  root-equivalent on the host.
- `~/.claude`, `~/.claude.json` and API keys from the host environment are
  mounted/forwarded into the container.

## License

[MIT](LICENSE)
