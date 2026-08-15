# Audio polish in DaVinci Resolve — the default pass

**This is the standard final audio pass for any Resolve-finish job.** Validated end to end
2026-08-06 on `your-job` (9 sections, 210 timeline clips): section loudness
spread collapsed from **4.7 LU to 1.1 LU**, every true peak moved under −0.6 dBFS (two were
over full scale), and **not one clip on the timeline moved**.

Run it **after** the edit is locked, never during a rough-cut handoff — you do one audio
pass over the whole video at the end, and touching levels mid-edit is explicitly out
(`CLAUDE.md` Lab Notes).

Companion files here: [`normalize-sections.sh`](normalize-sections.sh) (measure + render the
normalized copies) and [`replace-clips.py`](replace-clips.py) (swap them in, verify, revert).

## Why not do it in Resolve

**Resolve's scripting API has no audio-gain surface at all.** Verified by direct test, not
assumption:

```python
item.GetProperty('Volume')        # -> None   (on BOTH the video and the audio item)
item.SetProperty('Volume', 3.0)   # -> False
```

`timeline_item get_audio` returns `{Volume: null, Pan: null, ...}`. There is no normalize
method at timeline or project level. So per-clip gain is a UI-only action, and on a
200-clip timeline that is not a pass anyone wants to hand-click.

Resolve's own **Normalize Audio Levels** dialog is the manual equivalent and it is fine —
if you use it, pick **ITU-R BS.1770-4** (the gated algorithm; BS.1770-1 has no relative gate
and silence between takes drags the reading down), target **−16 LUFS**, and **Relative** mode
per section (Independent flattens delivery by normalizing every clip separately). The
broadcast presets — EBU R128, ATSC A/85, OP-59, TR-B32 — are locked around −23 to −24 LUFS,
about 8 dB under what YouTube wants. **Never True Peak / Sample Peak**: those normalize to
the loudest sample, not perceived loudness, which is exactly the failure mode this pass
exists to fix.

## The method

Measure → static gain → limiter → **verify no drift** → `ReplaceClip`.

### 1. Measure each source file, not each clip

```bash
ffmpeg -nostdin -hide_banner -i <raw> -af ebur128=peak=true -f null - 2>&1 | sed -n '/Summary:/,$p'
```

Read `I:` (integrated LUFS), `LRA:` (range) and `Peak:` (true peak). `ebur128` implements the
gated BS.1770 spec, so silence and dead air between takes barely move the number — a whole
raw is a valid proxy for its kept ranges, and you do not have to concat the EDL to measure.

Per **file**, not per clip: within one recording the level is essentially constant, so nine
measurements beat two hundred, and short clips give unreliable integrated readings anyway.

**`LRA` is the tell for whether section gain is enough.** 6–10 LU is normal talking head.
A section reading 20+ genuinely varies clip to clip and will still need hand attention after
this pass — section gain matches sections to each other, it does not fix dynamics inside one.

### 2. Gain + limit, one static chain

```bash
GAIN=$(echo "-16 - $I" | bc)      # to a -16 LUFS target
ffmpeg -nostdin -v error -y -i "$SRC" -c:v copy \
  -af "volume=${GAIN}dB,alimiter=limit=0.891251:level=disabled:latency=1" \
  -c:a aac -b:a 320k "$OUT"
```

- **`-c:v copy`** — video is stream-copied, so the picture stays bit-identical and the render
  is seconds, not minutes. Only audio is rebuilt.
- **`level=disabled`** is non-negotiable: the limiter's auto-level defeats the static gain you
  just measured. **`latency=1`** compensates its own lookahead so nothing shifts in time.
  Both are the house `alimiter` locks from `splice.sh`.
- **`limit=0.891251`** = −1.0 dBFS ceiling. Delivery-safe with room for the encoder.
- **320k AAC** — the downstream-bitrate lock: any re-encode after splice must match or exceed
  256k, and a quiet bed starves below that.
- **NEVER `loudnorm`.** Dynamic normalization pumps; your call, and it is a repo lock.

### 3. Verify no timing drift BEFORE committing

**This is the step that protects the whole edit.** An AAC re-encode can shift audio by a
frame through encoder priming, which would silently break lip sync across every cut. Run one
file first and compare four things against the source:

```bash
ffprobe -v error -show_entries format=duration -of csv=p=0 <f>
ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 <f>
ffprobe -v error -select_streams a:0 -show_entries stream=nb_frames,start_time -of csv=p=0 <f>
```

Duration, video frame count, audio frame count and audio `start_time` must all match exactly.
On the reference job all nine matched to the sample. If any differ, stop — do not replace.

### 4. Swap the media, do not re-edit

```python
mediaPoolItem.ReplaceClip('/abs/path/to/normalized.mp4')
```

The timeline references **clips**, not files, so repointing the media pool item leaves every
cut, trim, slip and hand edit exactly where it is. This is the whole reason the pass is safe
to run on a locked timeline.

Snapshot every track's `(name, start, duration)` before and after and diff them — the pass is
only correct if the answer is UNCHANGED on every track. Write a `REVERT.json` mapping each
clip name back to its original path as you go, so undoing it is one scripted loop.

**Never overwrite the raws.** Normalized copies live in `projects/<job>/audio-normalized/`.

**Version the output filename, never overwrite a path Resolve already has linked.** Same
reasoning as the Premiere and CapCut lanes: an app holding a linked file can keep serving the
cached old one. `rough-cut-use-case.mp4` → `-v2.mp4` → `-v3.mp4` across the reference job.

### 4a. Two things ReplaceClip does that break other scripts

**It RENAMES the media pool item to the new filename.** Every name-keyed lookup downstream
silently stops matching — on the reference job this broke a retime audit (which reported "no
retimed clips" when all five were intact) and would have broken the section colour/marker pass,
which keys on `rough-cut-use-case.mp4` and suddenly saw `rough-cut-use-case-v3.mp4`. Strip a
trailing `-v<N>` before matching. For example:

```python
_VER = re.compile(r"-v\d+(?=\.[A-Za-z0-9]+$)")
def base(name): return _VER.sub("", name)
```

**It CLEARS the clip colour label.** Re-run the colour pass after any swap or the clip comes
back unlabelled. (Seen on a title card, not just audio — this applies to any `ReplaceClip`.)

### 5. RETIMED CLIPS: derive protected ranges from the AUDIO items, not the video

**The single most expensive mistake on the reference job — three rounds to find.**

Resolve's audio time-stretch breaks down on extreme speed changes. On a 16.95x clip it emitted
a wall of **full-scale clipped samples for the first 1.1 seconds** (RMS −2.1 dB, 61% of samples
past 0.985) before recovering. Normalized, hard-limited audio makes it dramatically worse,
because the stretch is being driven into overload. So a retimed clip wants its **original**
level, not the section gain.

Since `ReplaceClip` is per source FILE, you cannot exempt one clip — you exempt the source
RANGES that clip consumes, with a time-varying gain:

```bash
R=0.25   # ramp seconds, INSIDE the protected range
P="clip(min((t-<a>)/$R\,(<b>-t)/$R)\,0\,1)"
-af "volume=volume='pow(<G>\,1-max($P1\,$P2))':eval=frame,alimiter=..."
```

`pow(G, 1-p)` interpolates in dB; `p` ramps 0→1 over `R` seconds inside each range so the
transition happens in material only the retimed clip uses (at 17x, 0.25s is 15ms on screen).
Ramp INSIDE, never outside — outside dips material other clips may share.

**Get the ranges from the audio items.** A retimed clip's audio is a SEPARATE timeline item
with its own source range, and they do not match. On the reference job the video read
`src 3474-5983` while the audio read `src 3474-6424`, and that one audio item covered BOTH
video clips (the second had no audio item at all). Deriving from video left **14.7 seconds of
source unprotected** — still at +9.7 dB under a 17x compression. That was the whole bug.

```python
for c in tl.GetItemListInTrack('audio', 1):
    ss, se, d = c.GetSourceStartFrame(), c.GetSourceEndFrame(), c.GetDuration()
    if not d or ss is None or se is None:      # audio items return None on some clips
        continue
    if abs(float(se - ss) / d - 1.0) > 0.02:
        ...                                     # protect ss..se
```

**Then verify by rendering the timeline range and measuring it — not by measuring the file.**
The file can be perfect while Resolve still mangles it. Per-100ms RMS, peak and percent-clipped
across the retimed span is the check; a clean file plus a broken render points at the stretch,
not the gain. And measure the SPECIFIC source window the stretch consumes — a broad mean around
it averages away the loud material that is actually causing the overload.

**If it still misbehaves, the fix is level, not muting.** Lowering the clip's Inspector gain
(which the API cannot reach) fixed it where three rounds of file surgery did not.

## Targets

| use | integrated | ceiling |
|---|---|---|
| **YouTube long-form (default)** | **−16 LUFS** | −1 dBTP |
| short-form / social | −14 LUFS | −1 dBTP |
| broadcast | −23 LUFS | −2 dBTP |

Landing within about 1 LU of target across sections is the goal; the limiter pulls peaks
without moving integrated loudness much on speech, so measured output typically comes back
0.1–1.2 LU under the requested target. Re-measure the output and report the real numbers
rather than the requested ones.

## What this pass cannot fix

**Clipping already recorded into the source.** On the reference job two sections measured
`+0.1` and `+0.2` dBFS true peak *before* any gain — already over full scale in the recording.
The limiter stops it getting worse and brings the section to target, but the distortion
baked into those takes stays. If it is audible, that is a re-record, not a mix fix.

**Dynamics inside a single section** — see the `LRA` note above.

## Afterwards

One limiter on the **Master bus** at −1 dBTP is a reasonable safety net, and it should barely
engage. Do not put limiters on individual clips: that is the move this pass replaces, and it
is what fails when some clips are already hot and others are 12 dB down.
