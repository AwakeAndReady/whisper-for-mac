# Whisper for Mac

Whisper for Mac is a fast, native macOS app for offline speech-to-text using OpenAI’s Whisper models.
It runs entirely on-device with no Python, no cloud, and no setup required — just download a model and start transcribing.

[Download the latest macOS release](https://github.com/AwakeAndReady/whisper-for-mac/releases/latest)

![Whisper for Mac setup wizard walkthrough](docs/wizard-walkthrough.gif)

## Features

- ⚡ Fast on-device transcription using `whisper.cpp`
- 🧠 Apple Silicon acceleration (Core ML where available)
- 🔒 100% offline & private — no data leaves your Mac
- 🎯 Multiple model support (tiny → large, multilingual + English-only)
- 🌍 Translation & language detection
- 📊 Live progress feedback & timestamps
- 🧵 Optimized multi-threaded inference
- 🖥️ Clean native macOS UI (SwiftUI)
- 🌗 Automatic Light and Dark Mode that follows your macOS appearance

## Using Whisper for Mac

1. Build the app or open a shared `.app` bundle.
2. Open Settings and install the Whisper model you want to use.
3. Drag and drop one or more audio or video files into the app, or select multiple files in Finder.
4. Review the Quick Start summary and start transcribing. Choose **Change Settings** to adjust the model, language, task, or output using the setup wizard.
5. Find the output files next to the source media or in your configured output folder.

Quick Start reuses the model, language, and task from the last transcription you started, including after restarting the app. Output formats, the output folder, and the Core ML preference keep their saved defaults. Files must be selected explicitly; transcription only begins when you click **Start Transcription** or **Start Queue**.

With multiple files, the **File** step shows a removable list in selection order. Add more files with **Add Files…** or drag them onto the list. **Quick Start** reviews the shared settings; the queue processes files sequentially and continues after individual failures. **Results** shows each file’s status and provides Open, Reveal in Finder, and Copy actions for finished files. **Stop Queue** cancels the current file and skips waiting files while keeping completed outputs. **Retry Failed** or **Retry Unfinished** processes only files that have not succeeded. The queue stays in memory for the current session; it is not restored after quitting. A background queue sends one summary notification at the end, and optional automatic Finder reveal runs once.

Choose **TXT transcript**, **VTT subtitles**, or **SRT subtitles** in the Output step or **Settings > Output**, individually or in combination. The selection is saved and appears in the Quick Start summary. SRT uses numbered subtitle cues and comma-separated millisecond timestamps.

After completion, use the copy icon next to **Output files** to copy the full transcript as plain text, even when only VTT or SRT subtitles were exported. The icon briefly shows a checkmark and **Copied** after a successful copy.

Whisper can send a local macOS notification when a transcription finishes while the app is in the background. Allow notifications when macOS asks. In **Settings > Output > When Finished**, you can disable these notifications or enable automatic Finder reveal. Automatic Finder reveal is off by default; **Reveal in Finder** remains available on the results screen.

When you cancel a transcription, the results screen first shows **Cancelling transcription** until processing stops. A neutral **Transcription cancelled** card then lets you restart with the same file and settings or choose another file. Cancelled jobs do not send completion notifications.

## Requirements

- macOS 15 or newer
- Apple Silicon or Intel Mac
- Internet connection only for downloading Whisper models

## Installation

Download the Universal app ZIP from the [latest GitHub Release](https://github.com/AwakeAndReady/whisper-for-mac/releases/latest). Unzipping creates a folder with `WhisperForMac.app` and a [README.txt](distribution/README.txt) containing installation steps. Quit any running copy, then move the app from that folder to Applications.

The app is currently distributed without Apple Developer ID signing or notarization. If macOS says it cannot verify the app for malware, click **Done**, then open **System Settings → Privacy & Security → Open Anyway** and confirm **Open**. Only do this if you trust the download from this repository. You may need to repeat the approval for each new download.

Alternatively, build the app locally from this repository:

```bash
git clone https://github.com/AwakeAndReady/whisper-for-mac.git
cd whisper-for-mac
./script/build_and_run.sh
```

The build script creates app bundles in `dist/`:

- `WhisperForMac.app` (Universal)
- `WhisperForMac-AppleSilicon.app`
- `WhisperForMac-Intel.app`

A built `.app` can also be shared directly with another user.

To publish a release, push a tag such as `v0.1.0`. The [release workflow](.github/workflows/release.yml) builds and checks a Universal app, then uploads its ZIP to GitHub Releases. GitHub Actions must be enabled for this repository.

## Development

Use the build script for local development:

```bash
./script/build_and_run.sh
```

Other useful modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

## Current Limitations

- No Whisper model is bundled with the app
- The first transcription requires downloading a model
- The app is already usable, but it is still evolving

## Notes

- The app is local-first and does not upload files for transcription
- Models are downloaded on demand and stored locally
- The default outputs are `.txt` and `.vtt`

## License

The software source code is available under the [MIT License](LICENSE.md).
The logo and app icon artwork is excluded and is covered by the separate
[Logo and App Icon License Exception](LOGO-LICENSE.md). Official unmodified
releases may retain the artwork; publicly distributed modified versions and
forks must use their own logo and app icons unless permission has been granted.

## Feedback

If the project looks useful to you, issues, ideas, and real-world testing feedback are very welcome.
