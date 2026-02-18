# Speak Now Local 🫶

Native macOS menubar app for voice transcription. Press a hotkey, speak, get text in your clipboard. Fully local via whisper-cpp, no cloud, no subscription.

## Requirements

- macOS 13.0+ (Apple Silicon recommended)
- [Xcode](https://apps.apple.com/us/app/xcode/id497799835) (for building)
- [whisper-cpp](https://github.com/ggerganov/whisper.cpp) via Homebrew

## Install

### 1. Install whisper-cpp

```bash
brew install whisper-cpp
```

### 2. Download a whisper model

Pick one (or grab several, you can switch in Settings):

```bash
mkdir -p ~/.cache/whisper
cd ~/.cache/whisper

# Tiny - fastest, good for quick notes (75 MB)
curl -L -o ggml-tiny.en.bin "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"

# Base - balanced speed/quality (142 MB)
curl -L -o ggml-base.en.bin "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

# Small - very good quality (466 MB)
curl -L -o ggml-small.en.bin "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"

# Medium - best quality, slower (1.5 GB)
curl -L -o ggml-medium.bin "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"
```

### 3. Build the app

```bash
git clone https://github.com/jugbandman/speak-now-local.git
cd speak-now-local
open SpeakNowLocal.xcodeproj
```

In Xcode:
1. Wait for Swift Package Manager to resolve dependencies (bottom status bar)
2. Select **My Mac** as the run destination
3. Press **Cmd+R** to build and run

### 4. Install as standalone app (no Xcode needed to run)

After building once, export a standalone .app:

```bash
xcodebuild -project SpeakNowLocal.xcodeproj \
  -scheme SpeakNowLocal \
  -configuration Release \
  -derivedDataPath build \
  build

# Copy to Applications
cp -r build/Build/Products/Release/SpeakNowLocal.app /Applications/
```

Then just launch from `/Applications/SpeakNowLocal.app`. No Xcode required.

To start automatically at login: **System Settings > General > Login Items > add SpeakNowLocal**.

## Usage

1. A sparkles icon appears in your menubar
2. First run walks you through permissions and model selection
3. Press **Cmd+Shift+R** (customizable) to start recording
4. Speak, then press the hotkey again to stop
5. Transcription runs locally, then text lands in your clipboard
6. **Cmd+V** to paste anywhere

### Auto-paste

Toggle auto-paste from the menubar dropdown or Settings. When enabled, the transcript automatically pastes into whatever text field is active (requires Accessibility permission).

### Transcript files

Transcripts save as markdown to `~/Documents/SpeakNowLocal/Transcripts/` (configurable in Settings). Each file has YAML frontmatter with date, model, and duration.

## Configuration

Click the menubar icon, then **Settings**:

- **General** - Hotkey, whisper-cli path, output directory, auto-paste, sound effects
- **Models** - Download, select, and manage whisper models

## Architecture

```
SpeakNowLocal/
├── App/           # @main entry, MenuBarExtra scene
├── Models/        # AppState, RecordingState, TranscriptEntry, WhisperModel
├── Services/      # AudioRecorder, WhisperTranscriber, ClipboardManager, etc.
├── Views/         # MenuBarView, SettingsView, OnboardingView, etc.
└── Utilities/     # Constants, SoundEffects
```

Built with Swift/SwiftUI. Uses `Process` to invoke `whisper-cli` (no embedded C++ library). Audio recorded as 16kHz mono 16-bit PCM WAV (exactly what whisper-cpp expects).

## License

MIT
