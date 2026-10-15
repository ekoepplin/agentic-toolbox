#!/bin/sh
# Matches `node` into the group owning /var/run/docker.sock (docker-outside-
# of-docker). The socket's gid varies per host Docker install, so this runs
# on every start (dock.sh), not just image build. Root-only; called via the
# NOPASSWD sudoers entry set up in the Dockerfile.
set -e

SOCK=/var/run/docker.sock
[ -S "$SOCK" ] || exit 0

GID=$(stat -c '%g' "$SOCK")
GRP=$(getent group "$GID" | cut -d: -f1)
if [ -z "$GRP" ]; then
  GRP=docker-host
  groupadd -g "$GID" "$GRP"
fi

usermod -aG "$GRP" node
