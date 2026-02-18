#!/usr/bin/env python3
"""
process-transcripts-watcher.py

Watches ~/Documents/SpeakNowLocal/Transcripts/ for new transcript files,
sends them to Claude API for analysis, prepends structured summaries,
and renames files with meaningful slugs.

Usage:
    python process-transcripts-watcher.py                 # watch mode
    python process-transcripts-watcher.py --process-existing  # batch mode
"""

import argparse
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

try:
    import anthropic
except ImportError:
    print("ERROR: anthropic package not installed. Run: pip install anthropic watchdog")
    sys.exit(1)

try:
    from watchdog.events import FileSystemEventHandler
    from watchdog.observers import Observer
except ImportError:
    print("ERROR: watchdog package not installed. Run: pip install anthropic watchdog")
    sys.exit(1)


DEFAULT_WATCH_DIR = os.path.expanduser("~/Documents/SpeakNowLocal/Transcripts")
DEFAULT_MODEL = "claude-haiku-4-5-20251001"
CONFIG_PATH = os.path.expanduser("~/.config/speak-now-watcher/config.json")

SYSTEM_PROMPT = (
    "You are a personal productivity assistant analyzing voice memo transcripts. "
    "Return only valid JSON."
)

USER_PROMPT_TEMPLATE = (
    'Analyze this transcript and return JSON with keys: '
    'summary (2-3 sentences), '
    'insights (array of strings, key ideas worth keeping), '
    'action_items (array of strings, concrete next steps), '
    'is_keeper (bool, false if this is just coding dictation or a quick test), '
    'suggested_slug (3-5 word kebab-case filename slug), '
    'category (one of: brain-dump, meeting, coding-dictation, quick-note)\n\n'
    'Transcript:\n{transcript}'
)


def load_config():
    """Load config from ~/.config/speak-now-watcher/config.json if it exists."""
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def get_anthropic_client():
    """Create and return an Anthropic client, checking for API key."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        print(
            "ERROR: ANTHROPIC_API_KEY environment variable is not set.\n"
            "Set it with: export ANTHROPIC_API_KEY=your-key-here"
        )
        sys.exit(1)
    return anthropic.Anthropic(api_key=api_key)


def parse_transcript_file(file_path: Path):
    """
    Parse a transcript file with YAML frontmatter.

    Returns (frontmatter_text, transcript_text, already_processed).
    already_processed is True if the file already has an AI Summary section.
    """
    content = file_path.read_text(encoding="utf-8")

    if "## AI Summary" in content:
        return None, None, True

    # Split on YAML frontmatter delimiters
    parts = content.split("---", 2)
    if len(parts) >= 3:
        frontmatter = parts[1].strip()
        transcript = parts[2].strip()
    else:
        frontmatter = ""
        transcript = content.strip()

    return frontmatter, transcript, False


def analyze_transcript(client: anthropic.Anthropic, transcript: str, model: str) -> dict:
    """Send transcript to Claude API and return structured analysis."""
    prompt = USER_PROMPT_TEMPLATE.format(transcript=transcript)

    message = client.messages.create(
        model=model,
        max_tokens=1024,
        messages=[{"role": "user", "content": prompt}],
        system=SYSTEM_PROMPT,
    )

    response_text = message.content[0].text.strip()

    # Strip markdown code blocks if present
    if response_text.startswith("```"):
        lines = response_text.split("\n")
        # Remove first and last lines if they are fence markers
        if lines[0].startswith("```"):
            lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        response_text = "\n".join(lines)

    return json.loads(response_text)


def build_summary_block(analysis: dict) -> str:
    """Build the formatted AI Summary markdown block to prepend."""
    is_keeper = analysis.get("is_keeper", True)
    keeper_str = "yes" if is_keeper else "no"
    category = analysis.get("category", "quick-note")
    summary = analysis.get("summary", "")

    insights = analysis.get("insights", [])
    action_items = analysis.get("action_items", [])

    lines = ["## AI Summary", ""]
    lines.append(f"**Category:** {category}")
    lines.append(f"**Keeper:** {keeper_str}")
    lines.append("")
    lines.append(summary)
    lines.append("")

    if insights:
        lines.append("**Key Insights:**")
        for insight in insights:
            lines.append(f"- {insight}")
        lines.append("")

    if action_items:
        lines.append("**Action Items:**")
        for item in action_items:
            lines.append(f"- [ ] {item}")
        lines.append("")

    lines.append("---")
    lines.append("")

    return "\n".join(lines)


def build_new_filename(original_path: Path, analysis: dict) -> Path:
    """Build a new filename with date prefix and suggested slug."""
    original_name = original_path.stem  # e.g. 2026-02-17-16-35-32-transcript
    # Extract date prefix: first 10 chars YYYY-MM-DD
    date_prefix = original_name[:10]

    slug = analysis.get("suggested_slug", "note")
    # Sanitize slug: lowercase, replace spaces with dashes, remove non-alphanumeric except dashes
    slug = slug.lower().strip()
    slug = re.sub(r"[^a-z0-9\-]", "", slug.replace(" ", "-"))
    slug = re.sub(r"-+", "-", slug).strip("-")

    is_keeper = analysis.get("is_keeper", True)
    if not is_keeper:
        slug = f"trash-{slug}"

    new_name = f"{date_prefix}-{slug}-transcript.md"
    return original_path.parent / new_name


def process_transcript_file(
    file_path: Path,
    client: anthropic.Anthropic,
    model: str,
    today_file: str | None = None,
    no_rename: bool = False,
) -> Path | None:
    """
    Process a single transcript file.

    Returns the new file path (or original if no_rename), or None on error.
    """
    print(f"Processing: {file_path.name}")

    frontmatter, transcript, already_processed = parse_transcript_file(file_path)

    if already_processed:
        print(f"  Skipping (already has AI Summary): {file_path.name}")
        return file_path

    if not transcript:
        print(f"  Skipping (no transcript text found): {file_path.name}")
        return file_path

    try:
        analysis = analyze_transcript(client, transcript, model)
    except json.JSONDecodeError as e:
        print(f"  ERROR: Claude returned invalid JSON: {e}")
        return None
    except anthropic.APIError as e:
        print(f"  ERROR: Claude API error: {e}")
        return None

    summary_block = build_summary_block(analysis)

    # Rebuild file content: AI Summary at top, then original frontmatter + transcript
    if frontmatter:
        original_section = f"---\n{frontmatter}\n---\n\n{transcript}\n"
    else:
        original_section = f"{transcript}\n"

    new_content = f"{summary_block}\n{original_section}"

    # Determine output path
    if no_rename:
        output_path = file_path
    else:
        output_path = build_new_filename(file_path, analysis)

    output_path.write_text(new_content, encoding="utf-8")

    # Remove original if renamed
    if output_path != file_path and file_path.exists():
        file_path.unlink()

    print(f"  Done: {output_path.name}")
    print(f"  Category: {analysis.get('category')} | Keeper: {analysis.get('is_keeper')}")

    # Optionally append to today.md
    if today_file:
        append_to_today(today_file, output_path, analysis)

    return output_path


def append_to_today(today_file: str, transcript_path: Path, analysis: dict):
    """Append a brief summary line to today.md."""
    today_path = Path(os.path.expanduser(today_file))
    if not today_path.exists():
        print(f"  Note: today-file not found, skipping append: {today_path}")
        return

    category = analysis.get("category", "quick-note")
    summary = analysis.get("summary", "").split(".")[0]  # First sentence only
    slug_name = transcript_path.stem

    line = f"\n- [{slug_name}]({transcript_path}) ({category}): {summary}.\n"

    with open(today_path, "a", encoding="utf-8") as f:
        f.write(line)

    print(f"  Appended summary to: {today_path}")


class TranscriptHandler(FileSystemEventHandler):
    """Watchdog event handler for new transcript files."""

    def __init__(
        self,
        client: anthropic.Anthropic,
        model: str,
        today_file: str | None,
        no_rename: bool,
    ):
        self.client = client
        self.model = model
        self.today_file = today_file
        self.no_rename = no_rename
        # Track files being processed to avoid double-processing
        self._processing = set()

    def on_created(self, event):
        if event.is_directory:
            return
        path = Path(event.src_path)
        if path.suffix != ".md" or not path.name.endswith("-transcript.md"):
            return
        if str(path) in self._processing:
            return

        self._processing.add(str(path))
        print(f"\nNew transcript detected: {path.name}")
        # Wait for the app to finish writing the file
        time.sleep(2)
        process_transcript_file(
            path, self.client, self.model, self.today_file, self.no_rename
        )
        self._processing.discard(str(path))

    def on_moved(self, event):
        """Handle file renames (some editors write via temp file + rename)."""
        if event.is_directory:
            return
        path = Path(event.dest_path)
        if path.suffix != ".md" or not path.name.endswith("-transcript.md"):
            return
        if str(path) in self._processing:
            return

        self._processing.add(str(path))
        print(f"\nNew transcript detected (via move): {path.name}")
        time.sleep(1)
        process_transcript_file(
            path, self.client, self.model, self.today_file, self.no_rename
        )
        self._processing.discard(str(path))


def run_watcher(args, client: anthropic.Anthropic):
    """Run in watch mode."""
    watch_dir = Path(os.path.expanduser(args.watch_dir))
    if not watch_dir.exists():
        print(f"ERROR: Watch directory does not exist: {watch_dir}")
        sys.exit(1)

    handler = TranscriptHandler(
        client=client,
        model=args.model,
        today_file=args.today_file,
        no_rename=args.no_rename,
    )

    observer = Observer()
    observer.schedule(handler, str(watch_dir), recursive=False)
    observer.start()

    print(f"Watching for new transcripts in: {watch_dir}")
    print(f"Model: {args.model}")
    if args.today_file:
        print(f"Appending summaries to: {args.today_file}")
    print("Press Ctrl+C to stop.\n")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping watcher...")
        observer.stop()

    observer.join()


def run_process_existing(args, client: anthropic.Anthropic):
    """Batch process all unprocessed transcripts in the watch directory."""
    watch_dir = Path(os.path.expanduser(args.watch_dir))
    if not watch_dir.exists():
        print(f"ERROR: Watch directory does not exist: {watch_dir}")
        sys.exit(1)

    files = sorted(watch_dir.glob("*-transcript.md"))
    if not files:
        print(f"No transcript files found in: {watch_dir}")
        return

    print(f"Found {len(files)} transcript file(s) in: {watch_dir}\n")

    processed = 0
    skipped = 0
    errors = 0

    for file_path in files:
        result = process_transcript_file(
            file_path, client, args.model, args.today_file, args.no_rename
        )
        if result is None:
            errors += 1
        else:
            _, _, already = parse_transcript_file(result) if result.exists() else (None, None, False)
            processed += 1

    print(f"\nDone. Processed: {processed}, Errors: {errors}")


def main():
    config = load_config()

    parser = argparse.ArgumentParser(
        description="Watch transcript directory and process with Claude API"
    )
    parser.add_argument(
        "--watch-dir",
        default=config.get("watch_dir", DEFAULT_WATCH_DIR),
        help=f"Directory to watch for transcripts (default: {DEFAULT_WATCH_DIR})",
    )
    parser.add_argument(
        "--today-file",
        default=config.get("today_file"),
        help="Path to today.md to append summaries (optional)",
    )
    parser.add_argument(
        "--model",
        default=config.get("model", DEFAULT_MODEL),
        help=f"Claude model to use (default: {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--no-rename",
        action="store_true",
        default=config.get("no_rename", False),
        help="Disable file renaming (keep original filenames)",
    )
    parser.add_argument(
        "--process-existing",
        action="store_true",
        help="Process all existing unprocessed transcripts and exit",
    )

    args = parser.parse_args()
    client = get_anthropic_client()

    if args.process_existing:
        run_process_existing(args, client)
    else:
        run_watcher(args, client)


if __name__ == "__main__":
    main()
