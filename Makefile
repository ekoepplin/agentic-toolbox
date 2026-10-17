# Top-level build target for the base image (issue #8).
#
# The base image is the single development image every workbench runs: all
# supported harnesses (Claude Code, pi, Copilot CLI) alongside the shared
# environment — key-only sshd on the internal SSH port (2222), tmux, gh,
# duckdb, the skill-dependency venv, zsh setup, and the mobile-SSH plumbing.
#
# The build context is .devcontainer/ — base files only. A clean clone of the
# base (or the base docked inside a host project) produces the same image, and
# no host-project file can ever enter the context.
#
# The image is tagged locally and built for the host architecture (the base
# runs on the machine that built it; there is no registry). HOST_HOME mirrors
# the host's ~/.claude/hooks at its host path inside the image.

# Canonical image tag. The workbench compose stack (#9) and the scaffolder
# (#11) reference exactly this name — do not rename without updating them.
BASE_IMAGE := agentic-toolbox-base:latest
DOCKERFILE := .devcontainer/Dockerfile
CONTEXT    := .devcontainer

.PHONY: image probe probe-voice probe-dock dock dock-e2e

# Build the base image from the base's own files only.
image:
	docker build -f $(DOCKERFILE) --build-arg HOST_HOME=$(HOME) -t $(BASE_IMAGE) $(CONTEXT)

# Dock a host project in one command (issue #11): generates the host's
# three-file tree (compose.yaml, .env, .devcontainer/devcontainer.json),
# picks a free SSH port, and builds the base image if missing.
dock:
	@test -n "$(HOST)" || { echo "usage: make dock HOST=<path-to-host-repo>"; exit 1; }
	@scripts/dock-host.sh "$(HOST)"

# Issue #8 acceptance probes against $(BASE_IMAGE):
#   in-image:  all three harness CLIs report a version (plus Node >= 22 for pi)
#   regression: sshd config (internal port, key-only, single user), tmux, gh,
#               duckdb, and the skill-dependency venv are all still present;
#               Ghostty-over-SSH shell: xterm-ghostty terminfo, zsh login
#               shell, Powerlevel10k theme; torch is the CPU-only build.
probe: image
	docker run --rm $(BASE_IMAGE) /bin/sh -c ' \
		set -e; \
		echo "== base image probes: $(BASE_IMAGE) =="; \
		echo "-- harnesses --"; \
		node --version; \
		[ "$$(node -p "process.versions.node" | cut -d. -f1)" -ge 22 ] \
			|| { echo "FATAL: Node major < 22 (pi needs >= 22.19)"; exit 1; }; \
		claude --version; \
		pi --version; \
		copilot --version; \
		echo "-- sshd config: internal port, key-only, single user --"; \
		grep -qx "Port 2222" /etc/ssh/sshd_config \
			|| { echo "FATAL: sshd Port 2222 not set"; exit 1; }; \
		grep -qx "PasswordAuthentication no" /etc/ssh/sshd_config \
			|| { echo "FATAL: sshd is not key-only"; exit 1; }; \
		grep -qx "AllowUsers node" /etc/ssh/sshd_config \
			|| { echo "FATAL: sshd AllowUsers node missing"; exit 1; }; \
		echo "sshd: Port 2222, key-only, AllowUsers node"; \
		echo "-- tmux --"; \
		tmux -V; \
		echo "-- terminal + shell (Ghostty over SSH) --"; \
		infocmp xterm-ghostty >/dev/null \
			|| { echo "FATAL: no xterm-ghostty terminfo"; exit 1; }; \
		[ "$$(getent passwd node | cut -d: -f7)" = /bin/zsh ] \
			|| { echo "FATAL: node login shell is not zsh"; exit 1; }; \
		grep -qx "ZSH_THEME=.powerlevel10k/powerlevel10k." /home/node/.zshrc \
			|| { echo "FATAL: Powerlevel10k is not the zsh theme"; exit 1; }; \
		echo "terminal: xterm-ghostty terminfo, zsh login shell, Powerlevel10k"; \
		echo "-- gh --"; \
		gh --version | head -n1; \
		echo "-- duckdb --"; \
		duckdb_bin=$$(ls /usr/local/bin/duckdb* | head -n1) \
			|| { echo "FATAL: no duckdb binary in /usr/local/bin"; exit 1; }; \
		$$duckdb_bin --version; \
		echo "-- skill-dependency venv --"; \
		/opt/venv/bin/python -c "import newsapi, loguru, duckdb, tavily, requests; print(\"venv: skill deps importable\")"; \
		command -v headroom; \
		/opt/venv/bin/python -c "import torch, sys; sys.exit(\"FATAL: torch is a CUDA build\") if torch.version.cuda else print(\"venv: torch is CPU-only\")"; \
		echo "-- voice capture tools (docs/voice.md) --"; \
		command -v rec arecord pactl; \
		grep -qx "default-server = tcp:host.docker.internal:4713" /etc/pulse/client.conf.d/workbench.conf \
			|| { echo "FATAL: pulse default-server not set"; exit 1; }; \
		grep -q "type pulse" /etc/asound.conf \
			|| { echo "FATAL: ALSA default not routed to pulse"; exit 1; }; \
		echo "voice: rec + arecord routed to tcp:host.docker.internal:4713"; \
		echo "== all probes passed =="; \
	'

# Voice end to end (docs/voice.md): records 2 s from the Mac microphone through
# the Mac's PulseAudio server, once via `rec` and once via `arecord` — the two
# recorders Claude Code /voice falls back to. Fails on silence, which is what
# a missing server or a denied macOS microphone permission looks like.
# Requires scripts/setup-mac-voice.sh on the Mac. Speak while it records.
probe-voice:
	docker run --rm --add-host host.docker.internal:host-gateway $(BASE_IMAGE) /bin/bash -c ' \
		set -e; \
		pactl info | grep -E "Server Name|Default Source"; \
		check() { \
			peak=$$(sox "$$1" -n stat 2>&1 | awk "/Maximum amplitude/ {print \$$3}"); \
			echo "$$2: peak $$peak"; \
			awk -v p="$$peak" "BEGIN { exit !(p > 0.001) }" \
				|| { echo "FATAL: $$2 recorded silence"; exit 1; }; \
		}; \
		rec -q -c1 -r16000 /tmp/rec.wav trim 0 2; check /tmp/rec.wav rec; \
		arecord -q -f S16_LE -r16000 -c1 -d2 /tmp/arecord.wav; check /tmp/arecord.wav arecord; \
		echo "== voice probe passed =="; \
	'

# Issue #10 acceptance probes against the dogfooded workbench (issue #9): the
# dock step must have wired every harness adapter. Requires a running
# workbench (docker compose up -d) and the base image (make image).
probe-dock:
	docker compose exec -T workbench bash .devcontainer/scripts/probe-dock.sh

# Issue #12 acceptance: the dock E2E on a scratch host project — the runtime
# gate, counterpart of the static drift guard (scripts/check.sh). One command
# scaffolds a throwaway host, brings its workbench up, runs every probe
# (every harness adapter, pin fidelity, dirty-base warning), and tears down
# with no residue. Exits non-zero on any probe failure.
# See docs/harnesses/dock-e2e.md.
dock-e2e:
	scripts/dock-e2e.sh
