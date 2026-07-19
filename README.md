# Meeting Transcriber (Native)

A native **macOS** app that transcribes meeting recordings and produces
formatted, summarized notes. Transcription runs entirely **on-device** using
[WhisperKit](https://github.com/argmaxinc/WhisperKit) (Apple Silicon), so your
audio never leaves your Mac. Summaries are generated on-device with
Apple Intelligence.

## Features

- Transcribe audio (and the audio track of video) meetings to text — Whisper, fully on-device
- Summarize transcripts into structured meeting notes (Executive Summary, Key Discussion Points, Decisions Made, Action Items, Next Steps)
- Pick a summary style: **Brief**, **Balanced**, or **Full**
- Manage and download Whisper models from within the app
- Export summaries as Markdown, HTML, or Word (.docx)
- Native SwiftUI interface — fast and private

## Requirements

- macOS 26 (Tahoe) or later — **required** (the summarizer uses Apple Intelligence / FoundationModels, and the UI uses Liquid Glass)
- Apple Silicon Mac with **Apple Intelligence enabled** (needed for the Summarize feature; transcription alone also benefits from Apple Silicon)
- Xcode command-line tools (`xcode-select --install`)

## Download

Grab the latest **`Meeting Transcriber.dmg`** from the
[Releases](https://github.com/harmlessparasite/Meeting-Transcriber/releases) page,
open it, and drag **Meeting Transcriber** to your `Applications` folder.

The first time you click **Transcribe**, the app downloads the Whisper model you
select (≈1 GB) into the app — no other setup required.

## Build from source

The app is a normal native macOS `.app`. To build it yourself:

```bash
bash build_app.sh
open "Meeting Transcriber.app"
```

`build_app.sh` compiles the app and assembles a self-contained
`Meeting Transcriber.app`. The first launch downloads the Whisper model you
select inside the app.

## Project layout

- `Package.swift` — Swift Package Manager manifest (depends on WhisperKit)
- `Sources/MeetingTranscriber/` — app source (SwiftUI views + engines)
- `build_app.sh` — builds the self-contained `.app`

## License

See `LICENSE` for details.
