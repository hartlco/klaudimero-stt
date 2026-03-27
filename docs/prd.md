# PRD: Standalone Speech-to-Text Server (macOS)

## Problem

Klaudimero's Telegram bridge supports text and image messages but not voice messages. Telegram voice messages arrive as `.oga` (Opus) audio files and need to be transcribed to text before they can be forwarded to Claude. Since Apple's on-device SpeechAnalyzer API is macOS-only, and Klaudimero instances may run on Linux, the transcription service must be a standalone, network-accessible server.

## Solution

A lightweight macOS-native HTTP server that accepts audio files and returns transcriptions using Apple's SpeechAnalyzer framework (macOS 26+). It runs independently from Klaudimero and exposes a simple REST API that any client can call.

## Goals

- Transcribe Telegram voice messages with high accuracy, on-device, at no API cost
- Run as a standalone service, decoupled from Klaudimero
- Support multiple concurrent Klaudimero installations as clients
- Minimize operational complexity (single binary, no external dependencies)

## Non-Goals

- Real-time/streaming transcription (voice messages are pre-recorded files)
- Text-to-speech (already handled by Klaudimero's TTS router)
- Speaker diarization or speaker identification
- Running on Linux or Windows (Apple API is macOS-only by design)

## Architecture

```
┌──────────────┐       POST /transcribe        ┌─────────────────────┐
│  Klaudimero  │  ──────────────────────────▶   │  Speech-to-Text     │
│  (Linux/Mac) │  ◀──────────────────────────   │  Server (macOS)     │
│              │       { "text": "..." }        │                     │
│  Telegram    │                                │  SpeechAnalyzer     │
│  Bridge      │                                │  (on-device model)  │
└──────────────┘                                └─────────────────────┘
```

The server is a Swift executable using a lightweight HTTP framework (e.g., Vapor or Hummingbird). It receives audio via multipart upload, feeds it to SpeechAnalyzer's `analyzeSequence(from:)` batch API, and returns the transcription as JSON.

## API

### `POST /transcribe`

Accepts an audio file and returns the transcription.

**Request:** `multipart/form-data`

| Field      | Type   | Required | Description                                      |
|------------|--------|----------|--------------------------------------------------|
| `file`     | binary | yes      | Audio file (OGA/Opus, MP3, WAV, M4A, CAF)        |
| `language` | string | no       | BCP-47 locale hint (e.g. `de_DE`). If omitted, auto-detected. |

**Response:** `200 OK`

```json
{
  "text": "Hey, can you check the deployment logs?",
  "language": "en_US",
  "duration_seconds": 4.2,
  "processing_time_ms": 310
}
```

**Errors:**

| Status | Meaning                                    |
|--------|--------------------------------------------|
| 400    | No file provided or unsupported format     |
| 422    | Transcription failed (no speech detected)  |
| 503    | Language model not yet downloaded on device |

### `GET /health`

Returns server status and available languages.

```json
{
  "status": "ok",
  "supported_locales": ["en_US", "de_DE", "..."],
  "version": "1.0.0"
}
```

### `GET /languages`

Returns the full list of available locales from `SpeechTranscriber.supportedLocales`, so clients can check language support before sending audio.

## Audio Format Handling

Telegram voice messages are encoded as Opus in an OGG container (`.oga`). SpeechAnalyzer works with Core Audio-compatible formats. The server must handle conversion:

1. Receive the uploaded audio file, write to a temp directory
2. If the format is not natively supported by Core Audio (e.g., OGG/Opus), convert to WAV or CAF using `ffmpeg` (shelled out) or an in-process Opus decoder
3. Pass the compatible file URL to `SpeechAnalyzer.analyzeSequence(from:)`
4. Return transcription, clean up temp files

`ffmpeg` is the pragmatic choice for format conversion — it's widely available on macOS via Homebrew and handles every codec Telegram might use.

## SpeechAnalyzer Integration

The server uses the batch transcription API since voice messages are complete audio files:

```swift
let analyzer = SpeechAnalyzer(modules: [SpeechTranscriber()])
let sequence = analyzer.analyzeSequence(from: audioFileURL)

var fullText = ""
for try await event in sequence {
    if let transcription = event as? SpeechTranscriber.Result {
        if !transcription.isVolatile {
            fullText += transcription.text + " "
        }
    }
}
```

Key considerations:
- Use `SpeechTranscriber` module (long-form), not `DictationTranscriber` — voice messages can be lengthy and conversational
- Language detection is automatic; the optional `language` hint from the API can be used to configure locale preference

## Language Model Management

SpeechAnalyzer language models are **not bundled with the OS** and do **not auto-download**. They must be explicitly downloaded via Apple's `AssetInventory` framework before transcription can work.

The server exposes language management through the API:

### `GET /languages`

Returns supported vs installed locales so clients can see what's available:

```json
{
  "supported": ["de_DE", "en_US", "fr_FR", "..."],
  "installed": ["de_DE", "en_US"]
}
```

- `supported` — all locales SpeechTranscriber can handle (requires download)
- `installed` — locales whose models are currently on-device and ready

### `POST /languages/download`

Triggers download of a language model:

```json
{ "locale": "fr_FR" }
```

Returns `{ "locale": "fr_FR", "status": "installed" }` on success.

Under the hood this uses:
1. `SpeechTranscriber.supportedLocales` / `installedLocales` to check state
2. `AssetInventory.assetInstallationRequest(supporting:)` to get a downloader
3. `downloader.downloadAndInstall()` to fetch and install the model

If a client POSTs to `/transcribe` for a locale that isn't installed, the server returns **503** with a message directing them to download the language first.

## Authentication

No authentication. The server is designed to run on a trusted local network.

## Deployment

- **Binary:** Single Swift executable, built with `swift build -c release`
- **Process management:** launchd plist for macOS (consistent with Klaudimero's existing launchd setup)
- **Port:** Default `8586` (next to Klaudimero's `8585`), configurable via `STT_PORT` env var
- **Dependency:** `ffmpeg` must be installed (`brew install ffmpeg`)
- **System requirement:** macOS 26 (Tahoe) on Apple Silicon

## Integration with Klaudimero Telegram Bridge

On the Klaudimero side, the integration requires:

1. **New config field** on `TelegramConfig`: `stt_server_url` (e.g., `http://mac-mini.local:8586`)
2. **New message handler** in `telegram_bridge.py` for `filters.VOICE` and `filters.VOICE_NOTE`:
   - Download the voice file from Telegram (`.oga`)
   - POST it to the STT server's `/transcribe` endpoint
   - Prepend the transcription to the Claude prompt: `[Voice message transcription]: {text}`
   - Process through Claude as a normal text message
3. Follow the existing pattern from image handling (`_handle_photo`)

This integration is a separate piece of work from the STT server itself.

## Project Structure

```
klaudimero-stt/
├── Package.swift
├── Sources/
│   └── KlaudimeroSTT/
│       ├── main.swift           — Entry point, HTTP server setup
│       ├── TranscriptionService.swift  — SpeechAnalyzer wrapper
│       ├── AudioConverter.swift  — ffmpeg-based format conversion
│       ├── Routes.swift          — /transcribe, /health, /languages
│       └── Config.swift          — Env var configuration
├── install.sh                   — Build + install launchd plist
└── README.md
```

## Success Criteria

- Voice messages from Telegram are transcribed and processed by Claude within 3 seconds (for messages under 60 seconds)
- Transcription quality is comparable to or better than Whisper large-v3 for supported languages
- Server runs unattended on a Mac Mini with zero maintenance
- Multiple Klaudimero instances can use the same STT server concurrently

## Decisions

- **No rate limiting** — trusted network, no auth, not needed
- **No caching** — not worth the complexity for the expected usage
- **Fallback** — Telegram bridge replies "voice messages are currently unavailable" when the STT server is unreachable
- **Video messages** — out of scope, audio files only
