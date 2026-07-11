# Meeting Transcriber (Native)

A native **macOS** app that transcribes meeting recordings and produces
formatted, summarized notes. Transcription runs entirely **on-device** using
[WhisperKit](https://github.com/argmaxinc/WhisperKit) (Apple Silicon), so your
audio never leaves your Mac.

## Features

- Transcribe audio/video meetings to text (Whisper, on-device)
- Summarize transcripts into structured meeting notes
- Manage and download Whisper models from within the app
- Native SwiftUI interface — fast and private

## Requirements

- macOS 15 (Sequoia) or later
- Apple Silicon Mac recommended
- Xcode command-line tools (`xcode-select --install`)

## Build & Run

Double-click **`Build and Launch.command`** in Finder. It will build the app (if
needed) and open it. Alternatively, from the terminal:

```bash
bash build_app.sh
open "Meeting Transcriber.app"
```

The first launch downloads the Whisper model you select inside the app.

## Project layout

- `Package.swift` — Swift Package Manager manifest (depends on WhisperKit)
- `Sources/MeetingTranscriber/` — app source (SwiftUI views + engines)
- `build_app.sh` — build script
- `Build and Launch.command` — Finder launcher

## License

See `LICENSE` for details.
