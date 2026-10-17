# syntax=docker/dockerfile:1
#
# agentic-toolbox base image — the single development image every workbench
# runs: Claude Code + pi + Copilot CLI, key-only sshd, tmux, gh, docker CLI, duckdb, the
# skill-dependency venv and a zsh/Powerlevel10k shell.
#
# Build with `make image` (the canonical builder). No --platform pin: the image
# is a local artifact built for the host architecture it runs on.
#
# node:22-trixie-slim — Debian 13 (ncurses 6.5 ships the Ghostty terminfo);
# pi requires Node >= 22.19.
FROM node:22-trixie-slim

LABEL org.opencontainers.image.title="agentic-toolbox-base" \
      org.opencontainers.image.description="Agentic development workbench: Claude Code + pi + Copilot CLI, sshd, tmux, gh, docker CLI" \
      org.opencontainers.image.source="https://github.com/ekoepplin/agentic-toolbox" \
      org.opencontainers.image.licenses="MIT"

# Pinned tool versions — bump here, then `make probe`.
ARG CLAUDE_CODE_VERSION=2.1.296
ARG PI_VERSION=1.2.0
ARG COPILOT_VERSION=1.0.98
ARG CCSTATUSLINE_VERSION=2.2.32
ARG DUCKDB_VERSION=1.2.1

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# ── System packages (one layer) ──────────────────────────────────────────────
# - gh + docker-ce-cli from their upstream apt repos. Docker CLI only
#   (docker-outside-of-docker): it talks to the host daemon through the
#   mounted /var/run/docker.sock; no nested dockerd.
# - openssh-server + tmux + fzf: mobile SSH access.
# - tesseract-ocr(-deu): offline OCR for pi-docparser (German scans).
#   LiteParse bundles its own engine and only reads the traineddata via
#   document_parse({ ocrLanguage: "deu", tessdataPath: $TESSDATA_PREFIX }).
#   No LibreOffice: add libreoffice-writer/-calc/-impress if a host needs
#   DOCX/XLSX/PPTX conversion.
# - ffmpeg: microphone capture/decode for pi-voice-stt. The workbench is
#   headless, so capture needs a forwarded /dev/snd or the host→SSH mic bridge.
# - sox + libsox-fmt-pulse, alsa-utils + libasound2-plugins, pulseaudio-utils:
#   Claude Code /voice records with `rec` or `arecord`. Both reach the Mac
#   microphone through the Mac's PulseAudio server, named in the pulse client
#   config rather than PULSE_SERVER — sshd sessions never see image ENV. The
#   ALSA default device is routed to pulse in /etc/asound.conf. docs/voice.md.
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl gpg && \
    install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/*.gpg && \
    arch="$(dpkg --print-architecture)" && \
    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")" && \
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    echo "deb [arch=$arch signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $codename stable" \
        > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential git less make procps unzip wget zsh \
        python3 python3-dev python3-pip python3-venv \
        openssh-client openssh-server sudo tmux fzf ncurses-term \
        gh docker-ce-cli \
        tesseract-ocr tesseract-ocr-deu ffmpeg \
        sox libsox-fmt-pulse alsa-utils libasound2-plugins pulseaudio-utils && \
    rm -rf /var/lib/apt/lists/* && \
    printf 'pcm.!default { type pulse }\nctl.!default { type pulse }\n' > /etc/asound.conf && \
    echo 'default-server = tcp:host.docker.internal:4713' > /etc/pulse/client.conf.d/workbench.conf
ENV TESSDATA_PREFIX=/usr/share/tesseract-ocr/5/tessdata

# ── duckdb CLI ───────────────────────────────────────────────────────────────
RUN case "$(dpkg --print-architecture)" in \
        arm64) duckdb_arch=linux-aarch64 ;; \
        amd64) duckdb_arch=linux-amd64 ;; \
        *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac && \
    curl -fsSL -o /tmp/duckdb.zip \
        "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-${duckdb_arch}.zip" && \
    unzip -q /tmp/duckdb.zip -d /usr/local/bin && \
    rm /tmp/duckdb.zip

# ── sshd: port 2222, key-only auth, node user only ───────────────────────────
# node may start sshd (compose command) and fix the docker socket group
# (dock.sh) via sudo — nothing else.
COPY --chmod=0755 fix-docker-socket.sh /usr/local/bin/fix-docker-socket.sh
RUN mkdir -p /run/sshd && \
    sed -i -e 's/^#Port 22$/Port 2222/' \
           -e 's/^#PasswordAuthentication yes$/PasswordAuthentication no/' \
           -e 's/^#PermitRootLogin prohibit-password$/PermitRootLogin no/' \
           /etc/ssh/sshd_config && \
    echo "AllowUsers node" >> /etc/ssh/sshd_config && \
    echo "node ALL=(root) NOPASSWD: /usr/sbin/sshd, /usr/local/bin/fix-docker-socket.sh" \
        > /etc/sudoers.d/node && \
    chmod 0440 /etc/sudoers.d/node

# ── Python: uv + skill-dependency venv at /opt/venv (on PATH for all users) ──
# Used by: fetch-news-local, fetch-free-images-local, web-search-local, headroom.
# --torch-backend cpu: the default linux/arm64 torch wheel drags in ~19
# CUDA/NVIDIA packages (several GB) that can never run here — no NVIDIA GPU.
# Longer timeout + fewer parallel downloads keep multi-GB wheels from starving
# smaller requests on slow links. The uv cache is a build-time mount, so it
# never lands in the image.
COPY --from=ghcr.io/astral-sh/uv:0.13.1 /uv /uvx /usr/local/bin/
RUN --mount=type=cache,target=/root/.cache/uv \
    export UV_LINK_MODE=copy UV_HTTP_TIMEOUT=300 UV_CONCURRENT_DOWNLOADS=4 && \
    uv venv /opt/venv && \
    uv pip install --python /opt/venv/bin/python --torch-backend cpu \
        newsapi-python \
        loguru \
        duckdb \
        tavily-python \
        requests \
        "headroom-ai[all]"
ENV PATH="/opt/venv/bin:$PATH"

# ── Agent CLIs (global npm) ──────────────────────────────────────────────────
# One layer, npm cache as a build-time mount. pi uses --ignore-scripts (its
# documented install path; no lifecycle scripts needed).
RUN --mount=type=cache,target=/root/.npm \
    npm install -g \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@github/copilot@${COPILOT_VERSION}" \
        "ccstatusline@${CCSTATUSLINE_VERSION}" && \
    npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}"

# ── Shell + terminal plumbing ────────────────────────────────────────────────
# - Ghostty terminfo: Debian ships the entry as `ghostty` only, but Ghostty
#   sets TERM=xterm-ghostty — alias it so vim/htop/less work over SSH.
# - Login shell → zsh (the node image defaults to bash, so SSH sessions would
#   skip the whole zsh setup below).
COPY claude-aliases.sh /etc/claude-aliases.sh
COPY tmux.zsh /etc/tmux.zsh
RUN ln -s ../g/ghostty /usr/share/terminfo/x/xterm-ghostty && \
    usermod -s /bin/zsh node && \
    install -d -m 700 -o node -g node /home/node/.ssh

# Mirror the host's ~/.claude/hooks at its host path, so hook commands with
# absolute host paths in settings.json resolve inside the container.
# `make image` passes the host's $HOME; skipped when unset.
ARG HOST_HOME=
RUN if [ -n "$HOST_HOME" ]; then \
        mkdir -p "$HOST_HOME/.claude" && \
        ln -sfn /home/node/.claude/hooks "$HOST_HOME/.claude/hooks"; \
    fi

# ── node user: Oh My Zsh, plugins, Powerlevel10k (all pinned) ────────────────
# Instant prompt stays off: it can't coexist with the tmux picker's console
# output during zsh init. Oh My Zsh auto-update is off — the image is pinned.
USER node
ENV HOME=/home/node
ARG OMZ_REF=964ddf789b022b6958b27d02d7fa54f552de21e9
ARG ZSH_AUTOSUGGESTIONS_REF=85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5
ARG ZSH_SYNTAX_HIGHLIGHTING_REF=1d85c692615a25fe2293bdd44b34c217d5d2bf04
ARG P10K_REF=v1.20.0
RUN clone() { \
        git init -q "$3" && \
        git -C "$3" fetch -q --depth 1 "$1" "$2" && \
        git -C "$3" -c advice.detachedHead=false checkout -q FETCH_HEAD; \
    } && \
    omz=/home/node/.oh-my-zsh && \
    clone https://github.com/ohmyzsh/ohmyzsh.git "$OMZ_REF" "$omz" && \
    clone https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_AUTOSUGGESTIONS_REF" \
        "$omz/custom/plugins/zsh-autosuggestions" && \
    clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_SYNTAX_HIGHLIGHTING_REF" \
        "$omz/custom/plugins/zsh-syntax-highlighting" && \
    clone https://github.com/romkatv/powerlevel10k.git "$P10K_REF" \
        "$omz/custom/themes/powerlevel10k" && \
    "$omz/custom/themes/powerlevel10k/gitstatus/install" && \
    sed -e 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' \
        -e 's|^plugins=(git)|plugins=(git zsh-autosuggestions zsh-syntax-highlighting)|' \
        -e "s|^# zstyle ':omz:update' mode disabled|zstyle ':omz:update' mode disabled|" \
        "$omz/templates/zshrc.zsh-template" > /home/node/.zshrc && \
    printf '%s\n' \
        '. /etc/claude-aliases.sh' \
        '. /etc/tmux.zsh' \
        '[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh' \
        'typeset -g POWERLEVEL9K_INSTANT_PROMPT=off' >> /home/node/.zshrc && \
    echo '. /etc/claude-aliases.sh' >> /home/node/.bashrc

# tmux.conf → mobile-friendly prefix (Ctrl+a), status bar on top, mouse on.
# p10k.zsh  → lean Powerlevel10k prompt config.
COPY --chown=node:node tmux.conf /home/node/.tmux.conf
COPY --chown=node:node p10k.zsh /home/node/.p10k.zsh

WORKDIR /home/node
