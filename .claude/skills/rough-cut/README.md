# rough-cut — setup

Turns raw talking-head clips into a tight rough cut. Claude transcribes every clip with WhisperX (large-v3 ASR + wav2vec2 word-level alignment), applies auto-kill rules to remove filler, dead air, stutters, and false starts, then stitches the kept segments with FFmpeg. Output is a single MP4 with audio normalized via a static chain (+10 dB amplify → −6 dBFS hard limiter — your Premiere move, NOT dynamic loudnorm, which pumps) — no captions, no B-roll, just a clean cut ready for polish.

Trigger phrases: "rough cut", "edit this reel", "cut this video", "edit the latest project", "trim this", "chop this up", "make a rough cut".

## Install

Drop this folder into a skills directory:
- `<project>/.claude/skills/rough-cut/` — for one project, or
- `~/.claude/skills/rough-cut/` — to use it everywhere.

When copying or zipping the folder for someone else, exclude `__pycache__/` and `.DS_Store`.

## Prerequisites

**1. System tools.** Install with Homebrew on macOS:

```
brew install uv ffmpeg
```

`uv` manages the Python venv. `ffmpeg` (which includes `ffprobe`) handles all media operations. Both are required.

**2. Python venv — first-run download.** On the first transcription, `transcribe.sh` builds a persistent WhisperX venv at `~/.cache/video-editor/whisperx-venv`. This pulls PyTorch and the WhisperX package — expect several GB and several minutes depending on your connection. Let it finish. If the install is interrupted, the script detects the incomplete state via a `.deps-ok` sentinel file, wipes the venv, and rebuilds cleanly on the next run. Every subsequent run reuses the built venv and starts in seconds.

**3. Model weights — first-run download.** The first transcription also downloads the `large-v3` ASR model and the wav2vec2 alignment model from Hugging Face. These are cached locally by the library after the first pull. Combined, plan for 3-5 GB of disk space.

**4. Project folder structure.** The skill expects raw clips inside a job folder under `projects/`:

```
video-editor/
└── projects/
    └── <job-name>/
        ├── raw/          ← put your clips here (.mov .mp4 .mkv .m4v)
        └── outputs/      ← final MP4 written here (created automatically)
```

Create the `projects/<job-name>/raw/` path and drop your clips in. The skill creates `outputs/` automatically.

**5. Optional: speaker diarization.** The `--diarize` flag labels each word with a speaker (useful for multi-person clips). To use it you need:
- A Hugging Face account with `HUGGINGFACE_TOKEN` set in your environment.
- The `pyannote/speaker-diarization-3.1` model accepted on your Hugging Face profile (requires agreeing to their terms at huggingface.co/pyannote/speaker-diarization-3.1).

Diarization is entirely optional. Single-speaker clips do not need it.

## Output

The transcript (`words.json`) and cut sheet (`cuts.json`) persist **durably** to `projects/<job-name>/transcript/` — that's the source of truth, reused across runs (re-running skips re-transcription). Encoded segments and other scratch land in `/tmp/video-editor/<job-name>/`, which macOS clears — never rely on anything living solely there.

The final output is written to:

```
projects/<job-name>/outputs/<job-name>.mp4
```

Claude reports back with the compression ratio (e.g., "3:47 → 0:48, 79% cut") and a cut sheet showing each kept segment with its timestamp range and transcript line.
