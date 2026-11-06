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

# Small - very good quality, the default (466 MB)
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

### Prompt mode

Talk a messy brain dump, get back a prompt tuned for the model you are about to use. Open it from **Open Prompt** in the menu bar, a hotkey you set in Settings, the wand button on any transcript, or start a take with the word "prompt". While the window is open every take is added to the draft. Your local model (Ollama) checks the dump against the chosen model profile's checklist and asks about anything missing. Answer by typing or by voice and it reshapes. Copy, paste back into the app you were in, save, or send it to Claude Code in a project folder. Nothing leaves your Mac.

Model profiles and kinds of ask are plain Markdown in `~/.speaknow/targets/` and `~/.speaknow/asks/`. Add a model by adding a file.

### Spelling fixes

`~/.speaknow/corrections.md` holds one line per term, `Right: wrong, wrong`. The right spellings are given to whisper as hints and anything still misheard is replaced. Use the Fix a word button on a transcript or `speaknow fix HEARD RIGHT`.

### Idea board

Each dump is split into ideas by your local model and sorted into Product, Client and Personal cards. Repeated ideas stack on one card, and the menu bar tells you when a take repeats an earlier idea. Drag a card to fix its column. Words in `~/.speaknow/buckets.md` always mean a bucket.

## Configuration

Every setting lives in `~/.speaknow/config.json`. The app reloads it within two seconds of a change, and Settings writes to the same file. `~/.speaknow/AGENTS.md` explains the folder to any AI assistant.

The `speaknow` command (linked by `install.sh`) works on the same files:

```bash
speaknow config set model medium        # change a setting
speaknow fix Belair Velare              # teach a spelling
speaknow last --prompt                  # print the last shaped prompt
speaknow last --prompt | claude -p      # hand it to Claude Code
speaknow dumps --since 7d               # list recent transcripts
speaknow ideas --week                   # this week's Idea board as Markdown
speaknow doctor                         # check whisper, models and Ollama
speaknow install-claude-commands        # add /dump and /ideas to Claude Code
```

With `whisper-server` installed next to `whisper-cli` (Homebrew's whisper-cpp ships both), the app keeps the model loaded between takes so text comes back faster.

Set `vaultInbox` to a notes folder (an Obsidian vault inbox works) and every transcript and saved prompt is also written there as a note.

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
