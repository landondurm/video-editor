# Exporting from DaVinci Resolve — what the API can and cannot set

Measured 2026-08-06 on `your-job` (19 min, 3840x2160/30, Resolve Studio 21.0.3.7).
Read this before scripting a delivery render; most of it is the API lying about settings it
accepted and then ignored.

## The short version

```python
proj.SetCurrentRenderFormatAndCodec('mp4', 'H264')
proj.SetRenderSettings({
    'TargetDir': OUT, 'CustomName': '<job>.final',
    'SelectAllFrames': True,                    # whole timeline, overrides any in/out
    'FormatWidth': 3840, 'FormatHeight': 2160, 'FrameRate': '30',
    'VideoQuality': 0,            # 0 = Automatic (highest). NOT a bitrate. See below.
    'MultiPassEncode': True,      # THE bitrate lever: 18.8 -> 36.8 Mbps measured
    'EncodingProfile': 'High',
    'AudioCodec': 'aac', 'AudioBitDepth': 24, 'AudioSampleRate': 48000,
    'ExportVideo': True, 'ExportAudio': True,
})
proj.StartRendering([proj.AddRenderJob()])
```

Result on the reference job: **36.8 Mbps, H.264 High, yuv420p, 4.89 GB for 19 min** — inside
YouTube's recommended 35–45 Mbps band for 4K30.

## `VideoQuality` is a dropdown INDEX, not kb/s

This is the trap. `SetRenderSettings` returns `True` for a bitrate-looking integer and then
ignores it. Measured on identical 30 s slices of a 4K screen recording:

| setting | result |
|---|---|
| `VideoQuality: 50000` | **18.8 Mbps** — the 50000 did nothing |
| `VideoQuality: 100` | **1.1 Mbps** — worse, it is an index |
| `VideoQuality: '50000'` (string) | `SetRenderSettings` returns **False**, whole dict rejected |
| `VideoQuality: 0` + `MultiPassEncode: True` | **35.0 Mbps** |

`0` means Automatic (highest). **`MultiPassEncode` is the only real quality lever.**

There is no bitrate key at all. `validate_render_settings` confirms the namespace: `VideoQuality`,
`EncodingProfile`, `MultiPassEncode`, `NetworkOptimization` are real; `VideoBitRate`, `BitRate`,
`MaxBitrate`, `TargetBitrate`, `RestrictToBitrate`, `VideoQualityType`, `QualityMode` are all
**unknown keys**. The UI's "Restrict to N Kb/s" is not exposed to scripting — if an exact
bitrate is genuinely required, set it by hand in the Deliver page.

**`GetRenderSettings` is not callable on this build** (returns `None`, like several other
proxy methods — see the `hasattr` note below). You cannot read settings back. Verify against
the finished file with `ffprobe`, always.

## Do not carry the Premiere bitrate lock across

`CLAUDE.md` records that **CBR 50 Mbps is the measured quality ceiling** for 4K H.264 — that was
measured on **Premiere's VideoToolbox** encoder via an `.epr`, and it does not port. Resolve's
API cannot express CBR or a bitrate target at all. Chasing that number here cost a wasted
render; `MultiPassEncode` was the whole answer.

## Codec choice

| codec | measured | note |
|---|---|---|
| **H.264** + multi-pass | **35.0 Mbps** | default; safest YouTube ingest, in their recommended band |
| H.265 + multi-pass | 28.1 Mbps | more efficient per bit, so roughly comparable quality at a smaller file; availability is license/plugin dependent |

The stock **`YouTube - 2160p` preset works fine** and produces a valid file — it is just tuned
conservatively and landed at **19.4 Mbps**, below YouTube's own 4K guidance. It leaves
multi-pass off. On text-heavy screen recordings that gap is visible; on ordinary talking-head
footage it is not worth a re-render.

## Multi-pass renders look FROZEN — do not judge progress by file size

The analysis pass writes almost nothing. On the reference job the output sat at **44 MB for
four minutes** while the job was actually at **60%**, and a render was cancelled on that
misreading. File size is a valid *completion* signal (grew, then stable, then `lsof` released)
but a useless *progress* signal.

Poll the job instead:

```python
st = proj.GetRenderJobStatus(job_id)      # {'JobStatus': 'Rendering', 'CompletionPercentage': 60}
```

Note `CompletionPercentage` is laggy and `TimeTakenToRenderInMs` reads `0` mid-render — poll it
several times over a minute before concluding anything is wedged. Multi-pass roughly doubles
render time: ~20 min for 19 min of 4K on this machine.

## `hasattr` is meaningless on Resolve objects

They are dynamic proxies that answer `hasattr` for **any** name. `GetTrackVolume`,
`GetTrackFader` and `GetTrackGain` all returned `True` — three different naming conventions
that cannot all be real — and all three resolve to `None` and are not callable. Same for
`GetRenderSettings` and `TimelineItem.GetRetime`.

**Always `getattr(obj, name, None)` and check `callable()`, or just call it and catch.**

## Confirm the file, never the settings

```bash
ffprobe -v error -show_entries stream=codec_name,profile,width,height,r_frame_rate,pix_fmt \
        -show_entries format=duration,size -of default=noprint_wrappers=1 <out>
ffmpeg -nostdin -hide_banner -i <out> -af ebur128=peak=true -f null - 2>&1 | sed -n '/Summary:/,$p'
```

Check resolution, frame rate, pix_fmt, duration (against the timeline frame count), average
bitrate (size×8÷duration — the container's `bit_rate` field can disagree) and programme
loudness. On the reference job the delivered programme read **−16.3 LUFS / 5.7 LU / −2.2 dBFS**.

**Predicting programme loudness from the source files does not work.** Averaging the section
files' integrated loudness and applying the fader offset was off by 3.5 LU, because the cut
weights sections differently than their raw durations do. Measure the actual export.
