# klaudimero-stt

Standalone speech-to-text server for macOS using Apple's SpeechAnalyzer framework. Accepts audio files over HTTP and returns transcriptions. Designed to serve Klaudimero Telegram voice messages but works as a general-purpose transcription API.

Requires **macOS 26 (Tahoe)** on Apple Silicon.

## Quick Start

```bash
# Prerequisites
brew install ffmpeg
xcode-select --install  # if needed

# Build and run
swift build -c release
.build/release/KlaudimeroSTT
```

The server starts on port **8586** by default. Override with `STT_PORT`:

```bash
STT_PORT=9000 .build/release/KlaudimeroSTT
```

## Install as a Service

```bash
./install.sh
```

This builds the binary, copies it to `~/.klaudimero-stt/`, and installs a launchd agent that starts automatically on login.

### Start / Stop / Monitor

```bash
# Stop the service
launchctl unload ~/Library/LaunchAgents/com.klaudimero.stt.plist

# Start the service
launchctl load ~/Library/LaunchAgents/com.klaudimero.stt.plist

# Check if running
launchctl list | grep klaudimero.stt

# View logs
tail -f ~/.klaudimero-stt/stderr.log

# Health check
curl http://localhost:8586/health
```

### Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.klaudimero.stt.plist
rm ~/Library/LaunchAgents/com.klaudimero.stt.plist
rm -rf ~/.klaudimero-stt
```

## API

### `GET /health`

```bash
curl http://localhost:8586/health
```

```json
{
  "status": "ok",
  "version": "1.0.0",
  "supportedLocales": ["de_DE", "en_US", "fr_FR", "..."],
  "installedLocales": ["de_DE", "en_US"]
}
```

### `GET /languages`

```bash
curl http://localhost:8586/languages
```

```json
{
  "supported": ["de_DE", "en_US", "fr_FR", "..."],
  "installed": ["de_DE", "en_US"]
}
```

### `POST /languages/download`

Download a language model to the device. Required before transcribing in that language.

```bash
curl -X POST http://localhost:8586/languages/download \
  -H "Content-Type: application/json" \
  -d '{"locale": "fr_FR"}'
```

```json
{ "locale": "fr_FR", "status": "installed" }
```

### `POST /transcribe`

Transcribe an audio file. Accepts multipart/form-data.

```bash
curl -X POST http://localhost:8586/transcribe \
  -F "file=@voice.oga" \
  -F "language=de_DE"
```

```json
{
  "text": "Hallo, kannst du die Logs checken?",
  "language": "de_DE",
  "durationSeconds": null,
  "processingTimeMs": 310
}
```

| Field      | Type   | Required | Description                              |
|------------|--------|----------|------------------------------------------|
| `file`     | binary | yes      | Audio file (OGA, MP3, WAV, M4A, CAF)    |
| `language` | string | no       | Locale hint (e.g. `de_DE`). Auto-detected if omitted. |

**Error codes:**

| Status | Meaning                                    |
|--------|--------------------------------------------|
| 400    | No file / unsupported format / bad locale  |
| 422    | No speech detected in audio                |
| 503    | Language model not installed                |

## How Language Models Work

SpeechAnalyzer models are **not bundled with the OS** — they must be downloaded per-locale before use:

1. Check available languages: `GET /languages`
2. Download what you need: `POST /languages/download {"locale": "de_DE"}`
3. Transcribe: `POST /transcribe`

If you try to transcribe in a locale that isn't installed, you get a **503** with instructions to download it.
