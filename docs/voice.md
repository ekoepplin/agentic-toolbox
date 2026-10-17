# Voice in the workbench

Claude Code `/voice` (and `pi-voice-stt`) work inside every workbench, using
the Mac's microphone.

## How it works

Docker Desktop runs containers in a Linux VM with no sound hardware, so there
is no `/dev/snd` to pass through. Instead, the Mac runs a PulseAudio server
that owns the microphone, and the container records from it over TCP:

```
Mac microphone ─► PulseAudio (brew service, 127.0.0.1:4713)
                        ▲
                        │ host.docker.internal:4713
workbench: rec / arecord ─► PULSE_SERVER=tcp:host.docker.internal:4713
```

- **Image side** (already in the base image): `sox` gives Claude Code its `rec`
  recorder, `alsa-utils` its `arecord` fallback; `/etc/asound.conf` routes the
  ALSA default device to pulse, and `PULSE_SERVER` points at the Mac. Nothing
  changes in a host project's `compose.yaml` — `host.docker.internal` is
  already mapped there.
- **Mac side** (once per Mac): `scripts/setup-mac-voice.sh`.

## Set up a Mac

Do this once on every Mac that runs workbenches (MacBook, Mac mini, …):

```bash
cd ~/repos/agentic-toolbox
scripts/setup-mac-voice.sh   # brew install pulseaudio, config, launchd service
make image                   # only if this Mac's image predates voice support
make probe-voice             # speak while it records — must print "voice probe passed"
```

Then recreate running workbenches so they run the new image:

```bash
docker compose up -d --force-recreate   # in each host repo
```

In the workbench, `/voice` in Claude Code now records from the Mac.

**Mac mini:** it has no built-in microphone. Connect a USB or Bluetooth mic
(or headset) and select it as input in *System Settings → Sound → Input*
before running `make probe-voice` — PulseAudio records from the macOS
default input.

## What the setup script changes

| Path | Content |
|---|---|
| `~/.config/pulse/default.pa` | Homebrew defaults + `module-native-protocol-tcp listen=127.0.0.1 port=4713 auth-anonymous=1` |
| `~/.config/pulse/daemon.conf` | `exit-idle-time = -1` (stay up) |
| `brew services` | `pulseaudio` as a launchd agent, started at login |

The listener is bound to loopback only, so it is unreachable from the LAN;
anonymous auth therefore admits only processes on this Mac and its Docker
containers. Docker Desktop forwards `host.docker.internal` to the Mac's
loopback, which is why no cookie mount is needed.

## Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `Connection refused` / `pactl info` fails in the container | Server not running → `brew services restart pulseaudio`; check `lsof -nP -iTCP:4713` on the Mac |
| `make probe-voice`: `recorded silence` | Wrong or no input device → *System Settings → Sound → Input*; or microphone permission denied → *System Settings → Privacy & Security → Microphone* |
| `/voice` says SoX is missing | Workbench runs an old image → `make image`, then `docker compose up -d --force-recreate` |
| Port 4713 busy | A hand-started daemon → re-run `scripts/setup-mac-voice.sh` (it kills it first) |

Check what PulseAudio sees on the Mac: `pactl list short sources` and
`pactl get-default-source`. Service log: `$(brew --prefix)/var/log/pulseaudio.log`.

## Undo

```bash
brew services stop pulseaudio
rm ~/.config/pulse/default.pa ~/.config/pulse/daemon.conf
```
