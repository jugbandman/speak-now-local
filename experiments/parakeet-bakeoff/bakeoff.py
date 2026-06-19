#!/usr/bin/env python3
"""Parakeet (MLX) vs whisper-cpp bake-off for speak-now-local.

Runs both engines on the same clips, times wall-clock inference, and computes
word error rate against known reference text. First Parakeet run downloads the
model; we warm it up before timing so download time is excluded.
"""
import os, re, sys, time, subprocess, shutil
from pathlib import Path

HERE = Path(__file__).parent
CLIPS = HERE / "clips"
REFS = HERE / "references.txt"
WHISPER = "/opt/homebrew/bin/whisper-cli"
WHISPER_MODELS = {
    "whisper-small.en": str(Path.home() / ".cache/whisper/ggml-small.en.bin"),
    "whisper-medium":   str(Path.home() / ".cache/whisper/ggml-medium.bin"),
}
PARAKEET = str(Path.home() / ".local/bin/parakeet-mlx")

def norm(t):
    """Lowercase, strip punctuation, collapse whitespace — fair WER comparison."""
    t = t.lower()
    t = re.sub(r"[^a-z0-9\s]", " ", t)
    return re.sub(r"\s+", " ", t).strip()

def wer(ref, hyp):
    r, h = norm(ref).split(), norm(hyp).split()
    # Levenshtein on words
    d = [[0]*(len(h)+1) for _ in range(len(r)+1)]
    for i in range(len(r)+1): d[i][0] = i
    for j in range(len(h)+1): d[0][j] = j
    for i in range(1, len(r)+1):
        for j in range(1, len(h)+1):
            cost = 0 if r[i-1]==h[j-1] else 1
            d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+cost)
    return d[len(r)][len(h)] / max(1, len(r))

def run_whisper(model_path, wav):
    t0 = time.time()
    out = subprocess.run([WHISPER, "-m", model_path, "-f", str(wav), "-nt", "--no-prints"],
                         capture_output=True, text=True)
    dt = time.time() - t0
    return out.stdout.strip(), dt

def run_parakeet(wav, outdir):
    t0 = time.time()
    subprocess.run([PARAKEET, str(wav), "--output-format", "txt", "--output-dir", str(outdir)],
                   capture_output=True, text=True,
                   env={**os.environ, "PATH": f"{Path.home()}/.local/bin:" + os.environ.get("PATH","")})
    dt = time.time() - t0
    txt = outdir / (wav.stem + ".txt")
    return (txt.read_text().strip() if txt.exists() else "<NO OUTPUT>"), dt

def main():
    refs = {}
    for line in REFS.read_text().splitlines():
        if "|" in line:
            k, v = line.split("|", 1); refs[k] = v
    clips = sorted(CLIPS.glob("*.wav"))
    pk_out = HERE / "parakeet_out"; pk_out.mkdir(exist_ok=True)

    print("Warming up Parakeet (downloads model on first run, excluded from timing)...")
    run_parakeet(clips[0], pk_out)
    print("Warm.\n")

    engines = list(WHISPER_MODELS.keys()) + ["parakeet-tdt-0.6b"]
    agg = {e: {"wer": [], "time": []} for e in engines}

    for wav in clips:
        ref = refs.get(wav.stem, "")
        print(f"━━━ {wav.name} ━━━")
        print(f"REF: {ref}")
        for name, mp in WHISPER_MODELS.items():
            txt, dt = run_whisper(mp, wav)
            w = wer(ref, txt)
            agg[name]["wer"].append(w); agg[name]["time"].append(dt)
            print(f"  {name:18s} {dt:5.2f}s  WER {w*100:5.1f}%  | {txt}")
        txt, dt = run_parakeet(wav, pk_out)
        w = wer(ref, txt)
        agg["parakeet-tdt-0.6b"]["wer"].append(w); agg["parakeet-tdt-0.6b"]["time"].append(dt)
        print(f"  {'parakeet-tdt-0.6b':18s} {dt:5.2f}s  WER {w*100:5.1f}%  | {txt}")
        print()

    print("════════ SUMMARY (avg across clips) ════════")
    print(f"{'engine':20s} {'avg time':>9s} {'avg WER':>9s}")
    for e in engines:
        at = sum(agg[e]['time'])/len(agg[e]['time'])
        aw = sum(agg[e]['wer'])/len(agg[e]['wer'])*100
        print(f"{e:20s} {at:8.2f}s {aw:8.1f}%")

if __name__ == "__main__":
    main()
