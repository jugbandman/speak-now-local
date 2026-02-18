# speak-now-local scripts

Scripts for processing SpeakNowLocal voice memo transcripts with Claude AI.

## process-transcripts-watcher.py

Watches the transcript output directory for new files, sends them to Claude API
for analysis, prepends structured summaries, and renames files with meaningful slugs.

### Setup

**1. Install dependencies:**

```bash
pip install anthropic watchdog
# or
pip install -r requirements.txt
```

**2. Set your API key:**

```bash
export ANTHROPIC_API_KEY=your-key-here
```

Add this to your `~/.zshrc` or `~/.bashrc` to persist it.

**3. (Optional) Create a config file:**

```bash
mkdir -p ~/.config/speak-now-watcher
cat > ~/.config/speak-now-watcher/config.json << 'EOF'
{
  "watch_dir": "~/Documents/SpeakNowLocal/Transcripts",
  "model": "claude-haiku-4-5-20251001",
  "today_file": "~/Documents/Obsidian Vault/10-Timestamped/today.md",
  "no_rename": false
}
EOF
```

### Usage

**Watch mode (runs continuously):**

```bash
python scripts/process-transcripts-watcher.py
```

**Batch mode (process all existing unprocessed transcripts):**

```bash
python scripts/process-transcripts-watcher.py --process-existing
```

**With options:**

```bash
python scripts/process-transcripts-watcher.py \
  --watch-dir ~/Documents/SpeakNowLocal/Transcripts \
  --today-file ~/Documents/ObsidianVault/10-Timestamped/today.md \
  --model claude-haiku-4-5-20251001 \
  --no-rename
```

### CLI Options

| Flag | Default | Description |
|------|---------|-------------|
| `--watch-dir` | `~/Documents/SpeakNowLocal/Transcripts` | Directory to watch |
| `--today-file` | (none) | Path to today.md for summary appends |
| `--model` | `claude-haiku-4-5-20251001` | Claude model to use |
| `--no-rename` | false | Keep original filenames |
| `--process-existing` | false | Batch process all unprocessed files and exit |

### Output Format

Each processed transcript gets an AI Summary block prepended:

```markdown
## AI Summary

**Category:** brain-dump | meeting | coding-dictation | quick-note
**Keeper:** yes / no

Two to three sentence summary of the transcript content.

**Key Insights:**
- Key idea 1
- Key idea 2

**Action Items:**
- [ ] Concrete next step 1
- [ ] Concrete next step 2

---

---
date: 2026-02-17-16-35-32
model: base.en
duration: 9.6s
---

Original transcript text...
```

### File Renaming

By default, processed files are renamed from:

```
2026-02-17-16-35-32-transcript.md
```

to:

```
2026-02-17-meaningful-slug-transcript.md
```

If `is_keeper=false` (quick tests, junk), the slug is prefixed with `trash-`:

```
2026-02-17-trash-test-dictation-transcript.md
```

### Running as a background service

To run the watcher automatically at login, create a launchd plist. See the
macOS documentation for launchd user agents.

Quick background run for a session:

```bash
nohup python scripts/process-transcripts-watcher.py > /tmp/transcript-watcher.log 2>&1 &
```
