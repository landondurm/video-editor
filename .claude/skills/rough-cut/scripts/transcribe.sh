#!/usr/bin/env bash
# transcribe.sh — runs WhisperX (large-v3 + wav2vec2 forced alignment) on every clip in a job folder
# usage: transcribe.sh <job_dir> [--diarize]
# output: <job_dir>/transcript/words.json  (durable canonical — transcribe ONCE, reuse forever;
#         /tmp/video-editor/<job-name>/ is just render scratch)
#
# --diarize adds speaker labels per word (requires HUGGINGFACE_TOKEN in env;
# pyannote/speaker-diarization-3.1 must be accepted on Hugging Face).

set -euo pipefail

# Windows pipes default python stdio to cp1252, which can't encode the ⚠/→ glyphs in the
# long-span warnings (or huggingface's progress output), so force UTF-8 everywhere.
# Windows without Developer Mode also denies os.symlink (WinError 1314): a real first-run
# large-v3 download crashed on that (2026-08-13). HF_HUB_DISABLE_SYMLINKS makes
# huggingface_hub copy instead of symlink, but treat it as belt-and-suspenders, NOT the
# proven fix: whisperx pins huggingface-hub <1.0, which never reads this var (only hub
# >=1.0 does) and whose cache already copy-degrades on denied symlinks. The likelier root
# cure for that crash is the uv interpreter pre-install below (junction race). If 1314
# recurs on a fresh no-Developer-Mode box, capture the traceback to find the real symlink
# site. Windows-only; costs disk, never correctness. No-ops on macOS/Linux.
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) export HF_HUB_DISABLE_SYMLINKS=1 ;; esac

# ─ Hardware auto-detect: an NVIDIA GPU (Windows/Linux) runs WhisperX on CUDA,
# several times faster than CPU. Apple Silicon stays CPU int8 (the lock: MPS
# torch is still flaky for some ops; CPU is slower but never silently wrong).
# WHISPERX_DEVICE=cpu|cuda overrides the auto-pick. The python side runs a full
# fallback ladder (cuda float16 → cuda int8_float16 → cpu int8), so a broken
# CUDA stack degrades to CPU with a warning; it can never block an edit.
GPU=0
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then GPU=1; fi
DEVICE="${WHISPERX_DEVICE:-}"
if [ -z "$DEVICE" ]; then
  if [ "$GPU" -eq 1 ]; then DEVICE=cuda; else DEVICE=cpu; fi
fi

JOB_DIR="${1:?usage: transcribe.sh <job_dir> [--diarize]}"
JOB_DIR="$(cd "$JOB_DIR" && pwd)"
JOB_NAME="$(basename "$JOB_DIR")"
MEDIA_DIR="$JOB_DIR"
[ -d "$JOB_DIR/raw" ] && MEDIA_DIR="$JOB_DIR/raw"
WORK="/tmp/video-editor/$JOB_NAME"
CANON="$JOB_DIR/transcript/words.json"   # persisted canonical transcript — transcribe ONCE, reuse forever
mkdir -p "$WORK" "$JOB_DIR/transcript"

DIARIZE=0
FORCE=0
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --diarize) DIARIZE=1 ;;
    --force)   FORCE=1 ;;
    *) echo "unknown flag: $1" >&2; exit 1 ;;
  esac
  shift
done

# Transcribe ONCE. WhisperX large-v3 is slow + deterministic, so a persisted canonical
# transcript wins unless --force. This is the single source of truth for the whole
# pipeline (rough cut AND finishing captions) — nothing else transcribes this footage.
if [ "$FORCE" -eq 0 ] && [ -f "$CANON" ]; then
  echo "[transcribe] reusing canonical transcript $CANON (pass --force to re-transcribe)" >&2
  cp "$CANON" "$WORK/words.json"
  echo "$WORK/words.json"
  exit 0
fi

shopt -s nullglob nocaseglob
CLIPS=("$MEDIA_DIR"/*.mov "$MEDIA_DIR"/*.mp4 "$MEDIA_DIR"/*.mkv "$MEDIA_DIR"/*.m4v)
shopt -u nocaseglob
if [ ${#CLIPS[@]} -eq 0 ]; then
  echo "no clips found in $MEDIA_DIR" >&2
  exit 1
fi

if [ -d /opt/homebrew/opt/ffmpeg@7 ]; then
  export DYLD_LIBRARY_PATH="/opt/homebrew/opt/ffmpeg@7/lib:${DYLD_LIBRARY_PATH:-}"
  export PATH="/opt/homebrew/opt/ffmpeg@7/bin:$PATH"
fi

# Persistent venv: built once, reused every run. whisperx pulls torch, so it
# gets its own box — it can't share the faster-whisper venv (different deps).
VENV="${VIDEO_EDITOR_WHISPERX_VENV:-$HOME/.cache/video-editor/whisperx-venv}"
# venv layout differs by OS: bin/python (macOS/Linux) vs Scripts/python.exe (Windows)
venv_py() { if [ -e "$VENV/Scripts/python.exe" ]; then echo "$VENV/Scripts/python.exe"; else echo "$VENV/bin/python"; fi; }
# sentinel written only after a successful install — a half-built venv (install
# interrupted once) self-heals on the next run instead of wedging forever
if [ ! -e "$VENV/.deps-ok" ]; then
  echo "[transcribe] first-run: building whisperx venv at $VENV (pulls torch, ~minutes)" >&2
  rm -rf "$VENV"
  # Windows: materialize the managed interpreter BEFORE creating the venv. `uv venv
  # --python 3.11` can trigger a just-in-time CPython download whose junction/trampoline
  # finalization races the venv creation and yields a broken venv (hit on a real machine,
  # 2026-08-13). A separate install step is idempotent and instant when already present.
  case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) uv python install 3.11 >&2 || true ;; esac
  if ! uv venv "$VENV" --python 3.11 >&2; then
    echo "[transcribe] venv creation failed; retrying once from clean" >&2
    rm -rf "$VENV"
    uv venv "$VENV" --python 3.11 >&2
  fi
  uv pip install --python "$(venv_py)" whisperx >&2
  if [ "$DEVICE" = cuda ]; then
    case "$(uname -s)" in
      MINGW*|MSYS*|CYGWIN*)
        # PyPI torch on Windows is CPU-only; swap in the CUDA build (Linux PyPI
        # wheels already ship CUDA, so only Windows needs this). cu128 wheels
        # want a current NVIDIA driver; if this install or the runtime probe
        # fails, everything falls back to CPU and the edit still runs.
        echo "[transcribe] NVIDIA GPU detected: installing CUDA torch (~3 GB, once)" >&2
        uv pip install --python "$(venv_py)" torch torchaudio \
            --index-url https://download.pytorch.org/whl/cu128 >&2 \
          || { echo "[transcribe] ⚠ CUDA torch install failed; this venv stays CPU-only" >&2; DEVICE=cpu; }
        ;;
    esac
  fi
  # record what this venv was built for, so later runs don't request CUDA
  # against a CPU-only torch (see the mismatch hint below)
  echo "$DEVICE" > "$VENV/.mode"
  touch "$VENV/.deps-ok"
fi
# A venv built before GPU support (or while no GPU was visible) is CPU-only;
# requesting CUDA against it would just fail the runtime probe. Downgrade with
# a hint so the rebuild is a deliberate choice, not a surprise 3 GB download.
if [ "$DEVICE" = cuda ] && [ "$(cat "$VENV/.mode" 2>/dev/null || echo cpu)" != "cuda" ]; then
  echo "[transcribe] · CUDA requested, but this WhisperX venv was built CPU-only." >&2
  echo "[transcribe]   For CUDA speed: rm -rf \"$VENV\" and re-run; the rebuild installs the CUDA stack." >&2
  DEVICE=cpu
fi
PYBIN="$(venv_py)"

"$PYBIN" - "$WORK/words.json" "$DIARIZE" "$DEVICE" "${CLIPS[@]}" <<'PY'
import json, os, sys
import whisperx

out_path = sys.argv[1]
diarize_flag = sys.argv[2] == "1"
want_device = sys.argv[3]      # "cuda" or "cpu", decided by transcribe.sh
clip_paths = sys.argv[4:]

# Device ladder. CPU int8 is the always-works floor (and the Apple Silicon
# lock: MPS torch is still spotty for some ops; CPU is slower but never
# silently wrong). With an NVIDIA GPU the ladder tries float16 first, then
# int8_float16 (fits ~4 GB cards), then drops to CPU: a broken CUDA stack
# (old driver, missing cuDNN, OOM) must never block an edit.
tiers = [("cpu", "int8", 8)]
if want_device == "cuda":
    tiers = [("cuda", "float16", 16), ("cuda", "int8_float16", 16)] + tiers
    try:
        import torch
        if not torch.cuda.is_available():
            raise RuntimeError(
                "torch.cuda.is_available() is False (CPU-only torch build, or the "
                "NVIDIA driver is too old for this CUDA runtime; a driver update "
                "usually fixes it)")
        # Windows: ctranslate2 resolves cublas/cudnn DLLs by name from the DLL
        # search path, and the CUDA torch wheel bundles them in torch/lib.
        if os.name == "nt":
            _lib = os.path.join(os.path.dirname(torch.__file__), "lib")
            if os.path.isdir(_lib):
                os.add_dll_directory(_lib)
                os.environ["PATH"] = _lib + os.pathsep + os.environ.get("PATH", "")
        print(f"[transcribe] NVIDIA GPU: {torch.cuda.get_device_name(0)}", file=sys.stderr)
    except Exception as e:
        print(f"[transcribe] ⚠ CUDA unavailable ({e}); using CPU int8", file=sys.stderr)
        tiers = [("cpu", "int8", 8)]

def load_stack(device, compute_type):
    print(f"[transcribe] loading whisperx large-v3 ({device}, {compute_type})", file=sys.stderr)
    asr = whisperx.load_model("large-v3", device, compute_type=compute_type, language="en")
    print("[transcribe] loading wav2vec2 alignment model", file=sys.stderr)
    align, meta = whisperx.load_align_model(language_code="en", device=device)
    return asr, align, meta

for i, (device, compute_type, batch_size) in enumerate(tiers):
    try:
        asr_model, align_model, align_metadata = load_stack(device, compute_type)
        break
    except Exception as e:
        if i == len(tiers) - 1:
            raise
        nd, nc, _ = tiers[i + 1]
        print(f"[transcribe] ⚠ {device}/{compute_type} failed to load "
              f"({type(e).__name__}: {e}); trying {nd}/{nc}", file=sys.stderr)

def load_diarize(device):
    hf_token = os.environ.get("HUGGINGFACE_TOKEN", "").strip()
    if not hf_token:
        print("[transcribe] --diarize requires HUGGINGFACE_TOKEN in env", file=sys.stderr)
        sys.exit(1)
    print("[transcribe] loading pyannote diarization pipeline", file=sys.stderr)
    return whisperx.DiarizationPipeline(use_auth_token=hf_token, device=device)

diarize_model = load_diarize(device) if diarize_flag else None

def process(path):
    audio = whisperx.load_audio(path)
    tr = asr_model.transcribe(audio, batch_size=batch_size, language="en")
    al = whisperx.align(
        tr["segments"], align_model, align_metadata, audio, device,
        return_char_alignments=False)
    if diarize_model is not None:
        al = whisperx.assign_word_speakers(diarize_model(audio), al)
    return audio, al

result = {"clips": []}
for path in clip_paths:
    name = os.path.basename(path)
    print(f"[transcribe] {name}", file=sys.stderr)
    try:
        audio, aligned = process(path)
    except Exception as e:
        # CUDA can also die mid-run (OOM on a long clip, a cuDNN kernel error):
        # rebuild the whole stack on CPU once and redo this clip. CPU errors
        # are real errors and still raise.
        if device == "cpu":
            raise
        print(f"[transcribe] ⚠ CUDA failed mid-run on {name} "
              f"({type(e).__name__}: {e}); falling back to CPU int8", file=sys.stderr)
        device, compute_type, batch_size = "cpu", "int8", 8
        asr_model, align_model, align_metadata = load_stack(device, compute_type)
        if diarize_flag:
            diarize_model = load_diarize(device)
        audio, aligned = process(path)
    duration = len(audio) / 16000.0

    words = []
    for seg in aligned.get("segments", []):
        for w in seg.get("words", []):
            # wav2vec2 sometimes can't align unspeakable tokens (numerals, punctuation).
            # Skip words missing timestamps so cuts.json builders don't crash.
            if "start" not in w or "end" not in w:
                continue
            entry = {
                "w": str(w.get("word", "")).strip(),
                "start": round(float(w["start"]), 3),
                "end": round(float(w["end"]), 3),
                "prob": round(float(w.get("score", 1.0)), 3),
            }
            if "speaker" in w:
                entry["speaker"] = w["speaker"]
            words.append(entry)

    result["clips"].append({
        "clip": name,
        "path": path,
        "duration": round(duration, 3),
        "words": words,
    })

with open(out_path, "w") as f:
    json.dump(result, f, indent=2)
print(f"[transcribe] wrote {out_path}", file=sys.stderr)

# WhisperX collapses an immediately repeated word into ONE long-span entry —
# the transcript shows a single word but the audio has every utterance. Flag
# them so cut authoring doesn't trust the span (splice's refiner auto-snaps
# these at segment boundaries; MID-segment ones need an authored split).
for c in result["clips"]:
    for w in c["words"]:
        if w["end"] - w["start"] > 1.0:
            print(f"[transcribe] ⚠ long-span word {w['w']!r} "
                  f"{w['start']:.2f}-{w['end']:.2f} ({w['end']-w['start']:.2f}s) "
                  f"— possible merged repeat, check the audio before keeping",
                  file=sys.stderr)
PY

# Persist the canonical copy so we never transcribe this footage again.
cp "$WORK/words.json" "$CANON"
echo "[transcribe] persisted canonical transcript → $CANON" >&2
echo "$WORK/words.json"
