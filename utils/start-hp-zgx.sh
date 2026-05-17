#!/usr/bin/env bash
# Start HP-ZGX remote vLLM service and establish local port forwards.
#
# Steps:
#   1. Wait until HP-ZGX is reachable via SSH.
#   2. Run service/utils/start-vllm-dflash.sh on the remote host.
#   3. Establish a backgrounded SSH port-forward (ssh -fN HP-ZGX).
#
# Assumes ~/.ssh/config already Includes the colima ssh_config and defines HP-ZGX.

set -euo pipefail

HOST="HP-ZGX"
REMOTE_DIR="/home/ekoepplin/repos/hp-zgx-workflow"
REMOTE_SCRIPT="service/utils/start-vllm-dflash.sh"
TMUX_SESSION="dflash"
MAX_WAIT_SECS=120
RETRY_INTERVAL=3
# vLLM readiness probe.
VLLM_HEALTH_URL="http://localhost:8000/health"
MAX_VLLM_WAIT_SECS=600
VLLM_PROBE_INTERVAL=5

log() {
    printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

# Sanity: ssh client present.
command -v ssh >/dev/null 2>&1 || die "ssh not found in PATH"

# Sanity: host defined in ssh config.
if ! ssh -G "$HOST" >/dev/null 2>&1; then
    die "Host '$HOST' not resolvable via ssh config"
fi

# Step 1: wait for SSH to come up.
log "Waiting for $HOST SSH to become reachable (max ${MAX_WAIT_SECS}s)..."
deadline=$(( $(date +%s) + MAX_WAIT_SECS ))
while true; do
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
           "$HOST" true 2>/dev/null; then
        log "$HOST is reachable."
        break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
        die "Timed out waiting for $HOST after ${MAX_WAIT_SECS}s"
    fi
    sleep "$RETRY_INTERVAL"
done

# Step 2: ensure remote tmux session, then run start script inside it.
# ClearAllForwardings disables LocalForward from ssh config for this exec session,
# so we don't double-bind ports already forwarded by an existing ssh -fN session.
log "Ensuring remote tmux session '$TMUX_SESSION' on $HOST..."
if ssh -o ClearAllForwardings=yes "$HOST" "tmux has-session -t '$TMUX_SESSION' 2>/dev/null"; then
    die "tmux session '$TMUX_SESSION' already exists on $HOST. Attach with: ssh $HOST -t tmux attach -t $TMUX_SESSION  (or kill it: ssh $HOST tmux kill-session -t $TMUX_SESSION)"
fi

log "Creating tmux session '$TMUX_SESSION' and running: cd $REMOTE_DIR && bash $REMOTE_SCRIPT"
if ! ssh -o ClearAllForwardings=yes "$HOST" \
        "tmux new-session -d -s '$TMUX_SESSION' \"cd '$REMOTE_DIR' && bash '$REMOTE_SCRIPT'; exec bash\""; then
    die "Failed to launch tmux session '$TMUX_SESSION' on $HOST"
fi
log "tmux session '$TMUX_SESSION' started. Attach with: ssh $HOST -t tmux attach -t $TMUX_SESSION"

# Step 2b: poll remote vLLM health endpoint until ready.
log "Waiting for vLLM readiness at remote $VLLM_HEALTH_URL (max ${MAX_VLLM_WAIT_SECS}s)..."
vllm_deadline=$(( $(date +%s) + MAX_VLLM_WAIT_SECS ))
while true; do
    if ssh -o ClearAllForwardings=yes "$HOST" \
           "curl -sf --max-time 3 '$VLLM_HEALTH_URL' >/dev/null" 2>/dev/null; then
        log "vLLM is ready."
        break
    fi
    # Bail early if tmux session died (script crashed).
    if ! ssh -o ClearAllForwardings=yes "$HOST" \
            "tmux has-session -t '$TMUX_SESSION' 2>/dev/null"; then
        die "tmux session '$TMUX_SESSION' died before vLLM became ready. Check remote logs."
    fi
    if [ "$(date +%s)" -ge "$vllm_deadline" ]; then
        die "vLLM did not become ready within ${MAX_VLLM_WAIT_SECS}s. Attach: ssh $HOST -t tmux attach -t $TMUX_SESSION"
    fi
    sleep "$VLLM_PROBE_INTERVAL"
done

# Step 3: start (or reuse) backgrounded port forward.
# Substring match — full argv may include absolute ssh path.
FORWARD_PATTERN="ssh -fN $HOST"
if pgrep -f "$FORWARD_PATTERN" >/dev/null 2>&1; then
    log "Port forward already running (matched: '$FORWARD_PATTERN'). Skipping."
else
    # Check ports aren't held by another process before launching.
    FORWARD_PORTS=(11434 8000 3000)
    occupied=()
    for port in "${FORWARD_PORTS[@]}"; do
        if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
            occupied+=("$port")
        fi
    done
    if [ "${#occupied[@]}" -gt 0 ]; then
        die "Local ports already in use: ${occupied[*]}. Inspect: lsof -nP $(printf -- '-iTCP:%s ' "${occupied[@]}")| grep LISTEN"
    fi
    log "Starting port forward: $FORWARD_PATTERN"
    # ExitOnForwardFailure=yes makes ssh return non-zero if any LocalForward bind fails.
    if ! ssh -o ExitOnForwardFailure=yes -fN "$HOST"; then
        die "ssh port forward failed. Check for stale forwards: pgrep -fa 'ssh -fN $HOST'"
    fi
    log "Port forward started."
fi

log "Done."
