#!/bin/bash
# Unattended ralph chain for the base/dock refactor (issues #8-#14).
#
# One ticket per invocation: fresh branch from master, pi-afk until the
# issue auto-closes on the agent's self-merge (see the UNATTENDED MERGE
# section in prompt-pi.md). Halts with a non-zero exit and a resume
# command on the first ticket that does not close within its budget.
#
# Usage:  ./chain.sh            (MAX_ITERS defaults to 10)
#         MAX_ITERS=15 ./chain.sh
set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../.."

TICKETS=(8 9 10 11 12 13 14)
MAX_ITERS="${MAX_ITERS:-10}"

state_of() { gh issue view "$1" --json state --jq .state; }

for N in "${TICKETS[@]}"; do
  state=$(state_of "$N")
  if [[ "$state" == "CLOSED" ]]; then
    echo "chain: #$N already closed - skipping"
    continue
  fi

  echo "chain: starting #$N (branch ralph/t$N, max $MAX_ITERS iters)"
  git fetch origin
  git checkout -B "ralph/t$N" origin/master

  ./agentic-workflow/ralph/pi-afk.sh "$N" "$MAX_ITERS"
  rc=$?

  git checkout master
  git pull --ff-only

  state=$(state_of "$N")
  if [[ "$state" == "CLOSED" ]]; then
    echo "chain: #$N closed - moving on"
  else
    echo "chain: HALT - #$N not closed after $MAX_ITERS iters (pi-afk rc=$rc)."
    echo "chain: resume manually:"
    echo "  git checkout ralph/t$N && ./agentic-workflow/ralph/pi-afk.sh $N $MAX_ITERS"
    exit 1
  fi
done

echo "chain: ALL TICKETS CLOSED"
