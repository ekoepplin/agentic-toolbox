#!/bin/bash
# AFK loop (Claude Code): runs once.sh until the issue closes. See lib.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ralph_afk once.sh "$@"
