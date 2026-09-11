# node:22-slim — pi requires Node >= 22.19.0; nothing else in the image pins Node 20.
# No --platform pin: the base image is a local artifact, built for the host
# architecture it will run on (make image).
FROM node:22-slim

# Install system packages — openssh-server + tmux + fzf enable mobile SSH access
RUN apt-get update && apt-get install -y python3 python3-pip python3-venv wget unzip curl git zsh \
    openssh-server tmux fzf sudo && \
    mkdir -p /etc/apt/keyrings && \
    wget -nv -O /etc/apt/keyrings/githubcli-archive-keyring.gpg https://cli.github.com/packages/githubcli-archive-keyring.gpg && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && apt-get install -y gh && \
    ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then DUCKDB_ARCH="linux-aarch64"; else DUCKDB_ARCH="linux-amd64"; fi && \
    wget https://github.com/duckdb/duckdb/releases/download/v1.2.1/duckdb_cli-${DUCKDB_ARCH}.zip && \
    unzip duckdb_cli-${DUCKDB_ARCH}.zip -d /usr/local/bin && \
    rm duckdb_cli-${DUCKDB_ARCH}.zip && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    # Configure sshd: port 2222, key-only auth, node user only
    mkdir -p /run/sshd && \
    sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    echo "AllowUsers node" >> /etc/ssh/sshd_config && \
    # Allow node to restart sshd without password (needed by postStartCommand)
    echo "node ALL=(ALL) NOPASSWD: /usr/sbin/sshd" >> /etc/sudoers

# Google Cloud CLI
RUN curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    apt-get update && apt-get install -y google-cloud-cli && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# uv — fast Python package manager
# installed as root, so copy out of /root (mode 700 — unreachable by the node
# user at runtime) into a world-executable path
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    cp /root/.local/bin/uv /root/.local/bin/uvx /usr/local/bin/

# Python venv for skill dependencies → /opt/venv  (on PATH for all users)
# Used by: fetch-news-local, fetch-free-images-local, web-search-local, headroom
RUN uv venv /opt/venv && \
    uv pip install --python /opt/venv/bin/python \
        newsapi-python \
        loguru \
        duckdb \
        tavily-python \
        requests \
        "headroom-ai[all]"
ENV PATH="/opt/venv/bin:$PATH"

# Oh My Zsh + plugins → /home/node/.oh-my-zsh/custom/plugins/<name>
USER node
ENV HOME=/home/node

RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

RUN git clone https://github.com/zsh-users/zsh-autosuggestions \
        ${ZSH_CUSTOM:-/home/node/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git -C ${ZSH_CUSTOM:-/home/node/.oh-my-zsh/custom}/plugins/zsh-autosuggestions checkout 85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5 && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting \
        ${ZSH_CUSTOM:-/home/node/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting && \
    git -C ${ZSH_CUSTOM:-/home/node/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting checkout 1d85c692615a25fe2293bdd44b34c217d5d2bf04 && \
    sed -i 's/^plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' /home/node/.zshrc

SHELL ["/bin/zsh", "-c"]

# Claude Code CLI → /usr/local/lib/node_modules/@anthropic-ai/claude-code  (global npm)
USER root
RUN npm install -g @anthropic-ai/claude-code && \
    chown -R 1000:1000 /home/node/.npm

# pi coding agent CLI → /usr/local/lib/node_modules/@earendil-works/pi-coding-agent (global npm)
# --ignore-scripts: pi's documented npm install path (no lifecycle scripts needed)
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent && \
    chown -R 1000:1000 /home/node/.npm

# ccstatusline — Claude Code status line (sirmalloc/ccstatusline)
RUN npm install -g ccstatusline

# Playwright Chromium + system deps — pinned to match @playwright/test in package.json
RUN npx -y playwright@1.58.2 install --with-deps chromium && \
    chown -R 1000:1000 /home/node/.cache

# Symlink macOS-style path so settings.json hook resolves inside container
# Override MAC_USER at build time for a different host username:
#   devcontainer.json → "build": { "args": { "MAC_USER": "${localEnv:USER}" } }
ARG MAC_USER=ekoepplin
RUN mkdir -p /Users/${MAC_USER}/.claude && \
    ln -sf /home/node/.claude/hooks /Users/${MAC_USER}/.claude/hooks

# Shell aliases → /etc/claude-aliases.sh  (sourced in .bashrc + .zshrc)
COPY claude-aliases.sh /etc/claude-aliases.sh
RUN echo '. /etc/claude-aliases.sh' >> /home/node/.bashrc && \
    echo '. /etc/claude-aliases.sh' >> /home/node/.zshrc

# Mobile SSH: tmux config + session picker
# tmux.conf  → mobile-friendly prefix (Ctrl+a), status bar on top, mouse on
# tmux.zsh   → fzf session picker on SSH login, auto-create on local login
COPY --chown=node:node tmux.conf /home/node/.tmux.conf
COPY --chown=node:node tmux.zsh /etc/tmux.zsh
RUN echo '. /etc/tmux.zsh' >> /home/node/.zshrc && \
    mkdir -p /home/node/.ssh && chmod 700 /home/node/.ssh && chown node:node /home/node/.ssh

USER node
WORKDIR /workspace
