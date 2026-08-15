# Long-Form — format detail (YouTube)

Format detail sheet for the **Graphics (step 3)** step when the job is long-form. The overall flow is the linear pipeline in [CLAUDE.md](../CLAUDE.md) — intake → rough cut → graphics → second pass → captions → background music (optional) → export. Long-form's defining trait: **Captions (step 5) is skipped** — YouTube serves its own CC track, and burn-ins clutter a 16:9 frame (decided 2026-06-23).

**Format:** 16:9 horizontal · **1920 × 1080** · as long as the content earns it (no 1–2 min target).
**Ships to:** YouTube (`your channel`).

---

## Graphics (step 3) — full treatment, no reframe

**Default tier first:** a plain "graphics pass" uses [`../presets/default-overlay-style.md`](../presets/default-overlay-style.md) (4–7 overlay cards in the callout zones, ~30 min); everything below is the **FULL** tier, opt-in by name only.

Source is already 16:9 — **do not reframe to 9:16.** The long-form look is the **liquid-glass system** — locked in
[`../presets/liquid-glass-style.md`](../presets/liquid-glass-style.md): bright frosted-glass panels that **pop in
from the side the speaker points to**, the **takeover** (face resizes to a side card while the spotlight-grid background
takes over full-frame for full-screen graphics), and **push-in zooms** for emphasis. Same brand constants as
short-form; horizontal frame.

Build it the **generated-composition** way, not by hand: a `build.py` is the source of truth (CSS + per-graphic
markup/anim from ~10 templates) that emits the comps + render/assemble scripts. Footage moves are **ffmpeg-native
(`ffseg`)** so they don't shift color; only the complex takeover is a browser `segment`. The render/lock/composite
mechanics + every gotcha (glass must read on its own fill, luma at the seam, slice alignment) live in
[`incremental-graphics.md`](incremental-graphics.md).

Plan first with `graphics-plan` (which lines get what), then run `build.py`. The **second pass** edits one part →
re-renders only it → `./assemble.sh` (seconds), never a full re-render.

Full cutaways that need generated motion (filmic b-roll or abstract texture with no real footage): generate 16:9
clips with your AI-video tool, then composite them like any other part.

## Captions (step 5) — skipped

No burned-in captions. YouTube CC only.

## Thumbnail + chapters — always

Long-form needs a thumbnail **every time** — `thumbnail-generator`, 16:9, built alongside the final render. Then timestamp the sections as **chapters** in the YouTube description.

---

## Safe Zones (16:9, 1920 × 1080)

No platform UI rail like short-form — these are broadcast title/action-safe margins plus YouTube's own overlays (hover scrubber, end-screen cards).

| Zone | Margin | Keep out |
|------|--------|----------|
| **Action-safe** | 5% → 96 px H / 54 px V | Anything you don't want clipped on odd displays |
| **Title-safe** | 10% → 192 px H / 108 px V | Essential text, logos, lower-third copy |
| **Bottom strip** | lower ~10% (~110 px) | Critical text — YouTube's scrubber + controls appear here on hover |
| **End-screen zone** (last 5–20s) | right ~40% + bottom band | YouTube end-screen cards (video/subscribe/link elements) snap here — keep anything important out of this region during the outro |

→ **Lower-thirds** sit just inside the title-safe bottom, above the hover-scrubber strip.
→ During the **outro**, design the right side + bottom to *hold* end-screen elements, not fight them.

## CTA

CTA decisions live in your content system (the script carries any ask) — this edit adds no sales asks (see CLAUDE.md Rules). Keep the **end-screen zone** clear so YouTube's cards don't cover content.
