#!/usr/bin/env python3
"""
process-transcripts-watcher.py

Watches ~/Documents/SpeakNowLocal/Transcripts/ for new transcript files,
sends them to a local LLM via LM Studio (or any OpenAI-compatible server)
for analysis, prepends structured summaries, and renames files with
meaningful slugs. Free, local, no API key required.

Usage:
    python process-transcripts-watcher.py                  # watch mode
    python process-transcripts-watcher.py --process-existing  # batch mode

Requirements:
    pip install openai watchdog
"""

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

try:
    from openai import OpenAI
except ImportError:
    print("ERROR: openai package not installed. Run: pip install openai watchdog")
    sys.exit(1)

try:
    from watchdog.events import FileSystemEventHandler
    from watchdog.observers import Observer
except ImportError:
    print("ERROR: watchdog package not installed. Run: pip install openai watchdog")
    sys.exit(1)


DEFAULT_WATCH_DIR = os.path.expanduser("~/Documents/SpeakNowLocal/Transcripts")
DEFAULT_BASE_URL = "http://127.0.0.1:1234/v1"
# LM Studio routes to whatever model is loaded - this name is informational only
DEFAULT_MODEL = "llama-3.2-3b-instruct"
CONFIG_PATH = os.path.expanduser("~/.config/speak-now-watcher/config.json")

SYSTEM_PROMPT = (
    "You are a personal productivity assistant analyzing voice memo transcripts. "
    "Return only valid JSON, no markdown, no explanation."
)

USER_PROMPT_TEMPLATE = (
    'Analyze this transcript and return a single JSON object with these exact keys:\n'
    '- summary: string, 2-3 sentences describing what was discussed\n'
    '- insights: array of strings, key ideas worth keeping\n'
    '- action_items: array of strings, concrete next steps (empty array if none)\n'
    '- is_keeper: boolean, false if this is just coding dictation or a quick test\n'
    '- suggested_slug: string, 3-5 word kebab-case filename slug\n'
    '- category: string, one of: brain-dump, meeting, coding-dictation, quick-note\n\n'
    'Return ONLY the JSON object. No markdown code blocks.\n\n'
    'Transcript:\n{transcript}'
)


def load_config():
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH) as f:
                return json.load(f)
        except (json.JSONDecodeError, OSError):
            pass
    return {}


def get_lm_studio_client(base_url: str) -> OpenAI:
    """Create OpenAI client pointed at LM Studio (or any OpenAI-compatible server)."""
    return OpenAI(base_url=base_url, api_key="lm-studio")


def parse_transcript_file(file_path: Path):
    """
    Parse a transcript file with YAML frontmatter.
    Returns (frontmatter_text, transcript_text, already_processed).
    """
    content = file_path.read_text(encoding="utf-8")

    if "## AI Summary" in content:
        return None, None, True

    parts = content.split("---", 2)
    if len(parts) >= 3:
        frontmatter = parts[1].strip()
        transcript = parts[2].strip()
    else:
        frontmatter = ""
        transcript = content.strip()

    return frontmatter, transcript, False


def analyze_transcript(client: OpenAI, transcript: str, model: str) -> dict:
    """Send transcript to LM Studio and return structured analysis."""
    prompt = USER_PROMPT_TEMPLATE.format(transcript=transcript)

    completion = client.chat.completions.create(
        model=model,
        max_tokens=1024,
        temperature=0.3,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
    )

    response_text = completion.choices[0].message.content.strip()

    # Strip markdown code blocks if the model wraps its response
    if response_text.startswith("```"):
        lines = response_text.split("\n")
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
    original_name = original_path.stem
    date_prefix = original_name[:10]  # YYYY-MM-DD

    slug = analysis.get("suggested_slug", "note")
    slug = slug.lower().strip()
    slug = re.sub(r"[^a-z0-9\-]", "", slug.replace(" ", "-"))
    slug = re.sub(r"-+", "-", slug).strip("-")

    if not analysis.get("is_keeper", True):
        slug = f"trash-{slug}"

    return original_path.parent / f"{date_prefix}-{slug}-transcript.md"


def process_transcript_file(
    file_path: Path,
    client: OpenAI,
    model: str,
    today_file: str | None = None,
    no_rename: bool = False,
) -> Path | None:
    """Process a single transcript file. Returns new path or None on error."""
    print(f"Processing: {file_path.name}")

    frontmatter, transcript, already_processed = parse_transcript_file(file_path)

    if already_processed:
        print(f"  Skipping (already processed): {file_path.name}")
        return file_path

    if not transcript:
        print(f"  Skipping (empty): {file_path.name}")
        return file_path

    try:
        analysis = analyze_transcript(client, transcript, model)
    except json.JSONDecodeError as e:
        print(f"  ERROR: Model returned invalid JSON: {e}")
        return None
    except Exception as e:
        print(f"  ERROR: {e}")
        return None

    summary_block = build_summary_block(analysis)

    if frontmatter:
        original_section = f"---\n{frontmatter}\n---\n\n{transcript}\n"
    else:
        original_section = f"{transcript}\n"

    new_content = f"{summary_block}\n{original_section}"

    output_path = file_path if no_rename else build_new_filename(file_path, analysis)
    output_path.write_text(new_content, encoding="utf-8")

    if output_path != file_path and file_path.exists():
        file_path.unlink()

    print(f"  -> {output_path.name}")
    print(f"     Category: {analysis.get('category')} | Keeper: {analysis.get('is_keeper')}")

    if today_file:
        append_to_today(today_file, output_path, analysis)

    return output_path


def append_to_today(today_file: str, transcript_path: Path, analysis: dict):
    """Append a brief summary line to today.md."""
    today_path = Path(os.path.expanduser(today_file))
    if not today_path.exists():
        print(f"  Note: today-file not found: {today_path}")
        return

    category = analysis.get("category", "quick-note")
    summary = analysis.get("summary", "").split(".")[0]
    slug_name = transcript_path.stem
    line = f"\n- [{slug_name}]({transcript_path}) ({category}): {summary}.\n"

    with open(today_path, "a", encoding="utf-8") as f:
        f.write(line)
    print(f"  Appended to: {today_path}")


class TranscriptHandler(FileSystemEventHandler):
    def __init__(self, client: OpenAI, model: str, today_file: str | None, no_rename: bool):
        self.client = client
        self.model = model
        self.today_file = today_file
        self.no_rename = no_rename
        self._processing = set()

    def _handle(self, path: Path):
        if not path.name.endswith("-transcript.md"):
            return
        if str(path) in self._processing:
            return
        self._processing.add(str(path))
        print(f"\nNew transcript: {path.name}")
        time.sleep(2)
        process_transcript_file(path, self.client, self.model, self.today_file, self.no_rename)
        self._processing.discard(str(path))

    def on_created(self, event):
        if not event.is_directory:
            self._handle(Path(event.src_path))

    def on_moved(self, event):
        if not event.is_directory:
            self._handle(Path(event.dest_path))


def run_watcher(args, client: OpenAI):
    watch_dir = Path(os.path.expanduser(args.watch_dir))
    if not watch_dir.exists():
        print(f"ERROR: Directory not found: {watch_dir}")
        sys.exit(1)

    handler = TranscriptHandler(client, args.model, args.today_file, args.no_rename)
    observer = Observer()
    observer.schedule(handler, str(watch_dir), recursive=False)
    observer.start()

    print(f"Watching: {watch_dir}")
    print(f"Model:    {args.model} via {args.base_url}")
    if args.today_file:
        print(f"Today:    {args.today_file}")
    print("Ctrl+C to stop.\n")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nStopping...")
        observer.stop()
    observer.join()


def run_process_existing(args, client: OpenAI):
    watch_dir = Path(os.path.expanduser(args.watch_dir))
    if not watch_dir.exists():
        print(f"ERROR: Directory not found: {watch_dir}")
        sys.exit(1)

    files = sorted(watch_dir.glob("*-transcript.md"))
    if not files:
        print(f"No transcripts found in: {watch_dir}")
        return

    print(f"Found {len(files)} transcript(s)\n")
    errors = 0
    for f in files:
        if process_transcript_file(f, client, args.model, args.today_file, args.no_rename) is None:
            errors += 1
    print(f"\nDone. Errors: {errors}")


def main():
    config = load_config()

    parser = argparse.ArgumentParser(description="Transcript watcher - local LLM via LM Studio")
    parser.add_argument("--watch-dir", default=config.get("watch_dir", DEFAULT_WATCH_DIR))
    parser.add_argument("--base-url", default=config.get("base_url", DEFAULT_BASE_URL),
                        help=f"LM Studio server URL (default: {DEFAULT_BASE_URL})")
    parser.add_argument("--model", default=config.get("model", DEFAULT_MODEL),
                        help="Model name (LM Studio routes to loaded model, name is flexible)")
    parser.add_argument("--today-file", default=config.get("today_file"),
                        help="Path to today.md to append summaries (optional)")
    parser.add_argument("--no-rename", action="store_true", default=config.get("no_rename", False))
    parser.add_argument("--process-existing", action="store_true",
                        help="Batch process all unprocessed transcripts and exit")

    args = parser.parse_args()
    client = get_lm_studio_client(args.base_url)

    if args.process_existing:
        run_process_existing(args, client)
    else:
        run_watcher(args, client)


if __name__ == "__main__":
    main()
