# Premiere Graphics Playbook — motion graphics, b-roll & graphics on the timeline

How Claude edits graphics INSIDE Premiere, distilled from the shipped `your-job` YouTube intro (2026-07-22). This is the architecture + workflow layer; engine mechanics and API gotchas live in the `premiere-pro` skill Notes, the part-split render SOP in [incremental-graphics.md](incremental-graphics.md). Read all three before a graphics session. Everything runs headless through `node workflows/premiere-bridge.mjs <tool> '<json>'` **from repo root**.

## The track stack (standard architecture)

4K 3840×2160 @ 23.976 sequence over 1080p raw footage — the timeline is 4K so 1080p-rendered graphics can be scaled crisp, and the raw rides at Motion Scale 200 (punch-ins = nudge scale, e.g. 210).

| Track | Role | Notes |
|---|---|---|
| V1 | Footage: EDL-replayed cuts (skill Procedure) | every cut a real edit point; scale 200 base, per-section punch-ins allowed; special composites get NESTED down to one V1 clip (see sandwich) |
| V2 | Graphics clips | ProRes 4444 alpha `.mov` from `hf-graphics`, butt-joined at EDL cut times, scale 200 |
| V3 | Composite helpers (talent cutouts etc.) | empty once a section is nested |
| V4 | Adjustment layers | film-feel treatment + per-section Lumetri grades (separate layers per section) |
| V5 | Grain overlay | real grain footage (`heavygrain`) spanning everything, split at section bounds |
| A1 | Voice (rides with the EDL replay) | untouchable — the splice chain already polished it |
| A2 | Music bed (+ occasional head SFX) | bed starts where graphics take over |
| A3–A5 | SFX rails, hand-designed by you | every graphic beat gets sound: stamps→pops, slides→whooshes, paint X's→scissors/markers, land moments→impacts/dings/bells. Library: `assets/sfx/` (Master SFX Pack, repo copy) |

**When re-timing or swapping a graphic, check A3–A5 in that window** — SFX are aligned to graphic beats and re-cut graphics orphan them silently. Surface affected SFX clips to you rather than moving your sound design unasked.

## The behind-talent sandwich → nest

Text/graphics BEHIND you (e.g. the cold-open "WHAT YOU'RE WATCHING / RIGHT NOW"):
1. V1 = the raw clip (background), V2 = alpha text comp timed to measured word onsets, V3 = the same raw clip again with the subject cut out — the mask trick: **Crop effect at Left=100 (wipes the frame) restricted by a mask over the talent** (the editor draws/tracks it, often with the new AI masking — not visible to scripting).
2. the editor then **nests** the three tracks into one V1 clip so adjustment layers + grain still stack above and the whole section can take a single Transform (zoom keys on the nest).
3. Known Premiere bug (26.x): rendered **preview files drop AI-masked layers** — green bar playback lies, yellow is truth. Delete render files (`qe.project.deletePreviewFiles("228CDA18-3625-4d2d-951E-348879E4ED93")`), never check "Use Previews" on export. Real renders (bridge `frame` grabs, direct exports) composite correctly.

## Graphics clip lifecycle

1. **Build** — per-job `build.py` emits comps → `./render.sh <id>` (pinned hyperframes) → ProRes 4444 → `projects/<job>/assets/<id>.mov`. Long graphics as seamless parts ([incremental-graphics.md](incremental-graphics.md)).
2. **Place** — `import_media`, then ES `videoTracks[n].overwriteClip(item, edlTime)`; trim the renderer's +1 pad frame via `c.end = t`. Graphics land ON the EDL cut times (frame-snapped splice ⇒ EDL == timeline).
3. **Iterate** — edit build.py → re-render the ONE affected part → `refresh_media` (same duration = in-place, keys/effects survive; duration changed = refresh twice in separate calls, then re-place). Never re-render the whole family for one tweak. **If the re-render changed CONTENT/duration, version the FILENAME (`<id>-b.mov`) and import fresh instead of overwriting the placed path (2026-08-01, your-job intro):** refreshMedia over a same-path rewrite left Premiere's frame index half-stale — *specific frames* of the clip rendered as nothing (program monitor AND `frame` exports; e.g. frame 126 perfect, frame 135 fully transparent) while the mov itself scanned clean. The Premiere sibling of the CapCut Resources same-filename trap.
4. **Anchor beats to MEASURED audio, not WhisperX** — word starts run ~50-100 ms late; scan a 5 ms RMS envelope of the base cut (ffmpeg f32le → stdlib) around the WhisperX time and pop on the acoustic attack, snapped to the frame grid `k·1001/24000`.
5. **The editor trims independently** — read the LIVE timeline (never trust docs/memory for clip spans) before computing anything against it.

## Keyframe & effect laws (hard-won, do not relearn)

- Clip keyframes live in **source time**: `inPoint + offset`. Synthetic media (adjustment layers) has inPoint ≈ 3600 s, and it RISES when the head is trimmed.
- **Baked keys are the standard** for any scripted motion: one key per frame (or per 2 frames) sampled off the curve, all linear. Eases via scripting are broken/limited; bake the shape.
- Point params (Position/Anchor) are **normalized** (0.5,0.5 = center — for offsets divide px by frame dims); scalars read/write in display units. Always read back after writing.
- Effects apply via QE: `qe.project.getVideoEffectByName` + `qclip.addVideoEffect`; **walk `getItemAt(i)` for `type === "Clip"`** — gaps are items, a clip that doesn't start at 0 is not item 0.
- **Adjustment layers: intrinsic Motion is inert on the image** (moves only the layer's bounds). Image moves = **Transform effect**; set Scale Height AND Width explicitly (uniform toggle untrusted). Prove any new transform assumption with an exaggerated offset + frame grab BEFORE baking hundreds of keys.
- Creating an adjustment layer = template mint, no UI: `importSequences(workflows/premiere-templates/adjustment-layer.prproj, ["b2440d0d-b8dc-4899-adf9-40cf306269a6"])`, keep the item, delete the junk `adj-template` sequence (full story: skill Notes).

## The finishing stack (what ships on top of the graphics)

- **Film-feel adjustment layer** over the graphics span. Shipped your-job values (read live 2026-07-22), effect order: **Transform** (wiggle = Position random-walk baked keys on twos, ±5px x / ±4px y @4K, LCG-seeded so re-bakes are deterministic; Uniform Scale OFF, Scale H/W 101 hides shifted edges) → **VR Glow** (Luma Threshold 0.5, Radius 200, Brightness 0.2, Saturation 1) → **Lens Distortion** (Curvature −7, Fill Alpha on) → **VR Chromatic Aberrations** (R −5 / G 0 / B +5, Falloff 25; defaults ±10 are glitch-loud) → **Lumetri** (your grade, hands off). the editor dials CA/glow/lens taste by hand: leave those dials alone, and never re-add effects they removed (Wave Warp was tried and cut).
- **Per-section Lumetri** on separate adjustment layers (one per section, split at section bounds) — your grade, don't touch.
- **Grain overlay on V5** across everything — motion-craft principle 3/8 done with real grain footage instead of per-clip ffmpeg.

## Generated b-roll on the timeline

AI-generated clips: `videoTracks[n].overwriteClip` + `audioTracks[n].overwriteClip` at the same time (V2/A2 pattern) so voice on A1 stays untouched; 1080p clip on the 4K timeline = scale 200. Beat-sync retiming (event frames → trim head → micro-slow spans): CLAUDE.md lab note "Generated-clip beat sync". Homogenize per motion-craft principle 8.

## QA loop

- `node workflows/premiere-bridge.mjs frame '{"time":<sec>,"out":"/abs/no-ext"}'` — frame-accurate program render incl. unsaved state, verified export-equivalent. This is THE verification tool.
- AME is BANNED (exports and bounces). Watchable renders: `sequence.exportAsMediaDirect` via ES, or let you play the timeline.
- Second-pass graphic tweaks: no self-QA frame-grabbing — edit, render, refresh, let you watch (your memory rule).
- `save_project` after every landed change.
