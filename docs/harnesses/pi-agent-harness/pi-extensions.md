# Pinned pi extensions

The pi harness gets its extensions from `.devcontainer/pi-extensions.lock` — the
pi analogue of `skills.lock`. `install-pi-extensions.sh` runs `pi install` for
each pinned entry on every workbench start (called by `dock.sh`), so a rebuild
reproduces exactly this set. Bump a pin by editing its line in the lock; check
the pi.dev package page or npm first.

Some extensions need a runtime binary in the image. Those are provisioned in
`.devcontainer/Dockerfile` alongside the pin, the same way `pi-docparser` pulls
Tesseract's German traineddata. This doc records the pinned set and any
per-extension caveats.

## The pinned set

| Package | Purpose | Runtime dep |
|---|---|---|
| `pi-mcp-adapter` | MCP server bridge | — |
| `pi-web-access` | web fetch / search | — |
| `pi-subagents` | subagent orchestration | — |
| `remote-pi` | remote session bridge | — |
| `pi-docparser` | scanned-PDF/image parsing (DOCX/XLSX/PPTX needs LibreOffice, not in the image) | Tesseract + `deu` traineddata (`TESSDATA_PREFIX`) |
| `pi-voice-stt` | voice dictation into the pi TUI | `ffmpeg` |
| `pi-context` | agentic context management | — |
| `pi-powerline-footer` | powerline-style status bar | — (a Nerd Font in the client terminal for the glyphs) |

## pi-voice-stt (voice dictation)

Provider-agnostic speech-to-text for the pi TUI. In the prompt: `Ctrl+R` starts
recording, `Ctrl+R` again transcribes and inserts the text, `Enter` while
recording transcribes and sends, `Esc` cancels. There's also a `/stt` command.

**Why this one** over the other pi voice packages: it's provider-agnostic and
speaks any OpenAI-compatible transcription endpoint (plus Mistral Voxtral / Groq),
so it can point at the self-hosted stack instead of being locked to one cloud
ASR — and it's the only one that ships a host→SSH microphone bridge, which is
what makes it usable from inside a remote workbench (see the caveat below).

### Provider

STT is configured by environment before pi starts — set one of:

- an **OpenAI-compatible** base URL + key pointing at a local/self-hosted Whisper
  endpoint (fits the same self-hosted ethos as the `vllm-hpzgx` model routing), or
- a hosted key (Groq Whisper, Mistral Voxtral, or any OpenAI-compatible service).

The provider credential is **not** seeded by `dock.sh` — it's host/secret-specific.
Export it in your shell (or the workbench env) before launching pi.

### ⚠️ Microphone caveat in the devcontainer

**The workbench is a headless Linux container with no audio device.** `ffmpeg` is
installed for capture, but there is no microphone inside the container to capture
*from*. So voice input works in one of two topologies:

1. **pi in the container + host mic bridge (intended remote-workbench flow).**
   Use `pi-voice-stt`'s native macOS microphone bridge to stream your laptop's
   mic into the containerized pi session over SSH. The container-side `ffmpeg`
   handles decode/capture of the bridged stream; the mic itself lives on the host.

2. **Forward the host audio device.** On a Linux host you can pass `/dev/snd`
   (and a PulseAudio socket) into the container so `ffmpeg` captures directly.
   Not wired up by default — it's a host-specific mount.

If you instead run pi **locally** (outside the container) against the same lock,
neither applies — `ffmpeg` captures your local mic directly.
