#!/usr/bin/env bash
# Mac side of workbench voice (docs/voice.md): a PulseAudio server that owns
# the Mac microphone and listens on loopback TCP 4713, which containers reach
# as host.docker.internal:4713 (the image's pulse client config names exactly
# that).
#
# Idempotent — safe to re-run; it rewrites its two config files and restarts
# the launchd service so they take effect.
set -euo pipefail

command -v brew >/dev/null || { echo "FATAL: Homebrew not found" >&2; exit 1; }
brew list pulseaudio >/dev/null 2>&1 || brew install pulseaudio

conf="$HOME/.config/pulse"
mkdir -p "$conf"

# Homebrew defaults, plus the TCP listener. Loopback bind keeps it off the LAN,
# so anonymous auth only admits local processes and Docker containers.
cat > "$conf/default.pa" <<EOF
.include $(brew --prefix)/etc/pulse/default.pa
load-module module-native-protocol-tcp listen=127.0.0.1 port=4713 auth-anonymous=1
EOF

# Stay up; containers connect on demand.
echo 'exit-idle-time = -1' > "$conf/daemon.conf"

# A hand-started daemon would hold the port and block the service.
pulseaudio --kill 2>/dev/null || true
brew services restart pulseaudio

for _ in $(seq 10); do
    lsof -nP -iTCP:4713 -sTCP:LISTEN >/dev/null 2>&1 && break
    sleep 1
done
lsof -nP -iTCP:4713 -sTCP:LISTEN >/dev/null 2>&1 \
    || { echo "FATAL: nothing listening on 127.0.0.1:4713" >&2; exit 1; }

echo "ok PulseAudio on 127.0.0.1:4713, default source: $(pactl get-default-source)"
echo "next: make probe-voice   (records 2 s inside the image)"
