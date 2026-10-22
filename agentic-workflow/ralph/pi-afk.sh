#!/bin/bash
# AFK loop (pi): runs pi-once.sh until the issue closes. See lib.sh.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
ralph_afk pi-once.sh "$@"
