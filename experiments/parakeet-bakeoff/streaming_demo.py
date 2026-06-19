#!/usr/bin/env python3
"""Parakeet real-time streaming prototype for speak-now-local.

Proves the live loop the Granola-replacement needs:
  audio chunks -> Parakeet streaming decode -> live partial captions
  -> silence-based end-of-utterance detection -> committed turn

Two modes:
  --file CLIP.wav   stream a WAV through the pipeline (verifiable headless)
  --mic             live microphone (talk into it; Ctrl-C to stop)

Run via uv so deps resolve without polluting anything:
  uv run --with parakeet-mlx --with sounddevice --with numpy --with soundfile \
      python streaming_demo.py --file clips/clip3.wav
  uv run --with parakeet-mlx --with sounddevice --with numpy --with soundfile \
      python streaming_demo.py --mic
"""
import argparse, sys, time
import numpy as np
import mlx.core as mx
from parakeet_mlx import from_pretrained

MODEL = "mlx-community/parakeet-tdt-0.6b-v3"
SR = 16000                 # Parakeet expects 16kHz mono
CHUNK_S = 1.5              # seconds per decode step; 1.5s = ~1.5x real-time on M1 (override: --chunk)
CONTEXT = 256              # attention right/left context frames (override: --context)
SILENCE_RMS = 0.012        # below this = silence
SILENCE_HANG_S = 0.8       # silence this long after speech = end of utterance

GREEN, GREY, BOLD, RESET = "\033[32m", "\033[90m", "\033[1m", "\033[0m"


def load_model():
    sys.stderr.write(f"Loading {MODEL} (cached) ...\n"); sys.stderr.flush()
    t0 = time.time()
    m = from_pretrained(MODEL)
    sys.stderr.write(f"Loaded in {time.time()-t0:.1f}s. Speak naturally; pauses end a turn.\n\n")
    return m


class Turns:
    """Tracks committed-vs-live text and prints turn boundaries on EOU."""
    def __init__(self):
        self.committed_chars = 0
        self.spoke = False
        self.last_voice = time.time()
        self.turn = 1

    def feed(self, stream, rms, now):
        text = stream.result.text
        live_tail = text[self.committed_chars:].strip()
        # live partial caption (overwrites in place)
        sys.stdout.write(f"\r{GREY}… {live_tail[-110:]}{RESET}" + " " * 8)
        sys.stdout.flush()
        if rms > SILENCE_RMS:
            self.spoke = True
            self.last_voice = now
        elif self.spoke and (now - self.last_voice) > SILENCE_HANG_S:
            committed = stream.result.text[self.committed_chars:].strip()
            if committed:
                sys.stdout.write(f"\r{GREEN}✅ turn {self.turn}:{RESET} {BOLD}{committed}{RESET}" + " " * 12 + "\n")
                sys.stdout.flush()
                self.committed_chars = len(stream.result.text)
                self.turn += 1
            self.spoke = False

    def flush_final(self, stream):
        committed = stream.result.text[self.committed_chars:].strip()
        if committed:
            sys.stdout.write(f"\r{GREEN}✅ turn {self.turn}:{RESET} {BOLD}{committed}{RESET}" + " " * 12 + "\n")
            sys.stdout.flush()


def run_file(model, path):
    import soundfile as sf
    audio, sr = sf.read(path, dtype="float32")
    if audio.ndim > 1:
        audio = audio.mean(axis=1)
    if sr != SR:  # naive resample
        idx = (np.arange(int(len(audio) * SR / sr)) * sr / SR).astype(int)
        audio = audio[idx]
    # pad 1s trailing silence so the EOU detector fires on the last turn
    audio = np.concatenate([audio, np.zeros(SR, dtype="float32")])
    step = int(SR * CHUNK_S)
    t0 = time.time()
    with model.transcribe_stream(context_size=(CONTEXT, CONTEXT)) as stream:
        turns = Turns()
        for i in range(0, len(audio), step):
            chunk = audio[i:i + step]
            rms = float(np.sqrt(np.mean(chunk ** 2))) if len(chunk) else 0.0
            stream.add_audio(mx.array(chunk))
            turns.feed(stream, rms, time.time())
        turns.flush_final(stream)
    audio_s = (len(audio) - SR) / SR
    proc_s = time.time() - t0
    print(f"\n{GREY}[{audio_s:.1f}s audio decoded in {proc_s:.1f}s "
          f"= {audio_s/proc_s:.1f}x real-time]{RESET}")


def run_mic(model):
    import sounddevice as sd
    import queue
    q = queue.Queue()

    def cb(indata, frames, t, status):
        q.put(indata[:, 0].copy())

    blocksize = int(SR * CHUNK_S)
    with model.transcribe_stream(context_size=(CONTEXT, CONTEXT)) as stream:
        turns = Turns()
        with sd.InputStream(samplerate=SR, channels=1, dtype="float32",
                            blocksize=blocksize, callback=cb):
            print(f"{BOLD}🎤 Listening…{RESET} (Ctrl-C to stop)\n")
            try:
                while True:
                    chunk = q.get()
                    rms = float(np.sqrt(np.mean(chunk ** 2)))
                    stream.add_audio(mx.array(chunk))
                    turns.feed(stream, rms, time.time())
            except KeyboardInterrupt:
                turns.flush_final(stream)
                print(f"\n{GREY}stopped.{RESET}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--file", help="WAV file to stream through the pipeline")
    g.add_argument("--mic", action="store_true", help="live microphone")
    ap.add_argument("--chunk", type=float, help="seconds of audio per decode step")
    ap.add_argument("--context", type=int, help="attention context frames (lower = faster)")
    args = ap.parse_args()
    if args.chunk:   CHUNK_S = args.chunk
    if args.context: CONTEXT = args.context

    model = load_model()
    if args.file:
        run_file(model, args.file)
    else:
        run_mic(model)
