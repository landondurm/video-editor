# Short-Form — format detail (Reels / TikTok / Shorts)

Format detail sheet for the **Graphics (step 3)** and **Captions (step 5)** steps when the job is short-form. The overall flow is the linear pipeline in [CLAUDE.md](../CLAUDE.md) — intake → rough cut → graphics → second pass → captions → background music (optional) → export. This file only covers what's short-form-specific.

**Format:** 9:16 vertical · **1080 × 1920** · tightest cut that delivers (target ~1–2 min — never pad to hit a length).
**Ships to:** Instagram Reels, TikTok, YouTube Shorts — one edit, all three.

Two presets — decide when you reach Graphics, and decide it YOURSELF from the content: teaching/system-walkthrough material cuts as a **talking-head explainer**, casual talk-to-camera stays **TikTok/raw**. State the pick in one line (the creator overrides with a word); ask only if the footage genuinely supports both reads. Both ran the same rough cut; they only differ here.

**Default tier first:** a plain "graphics pass" on an explainer = [`../presets/default-overlay-style.md`](../presets/default-overlay-style.md) cards in the top half, per the safe zones below (TikTok/raw is unchanged at any tier: hook card only). The full looks below — the `signature-style.md` split-frame plan — are the **FULL** tier, opt-in by name only.

---

## Preset A — Talking-Head Explainer

Split frame: **graphics top half, face bottom half.** Use when on-screen visuals (screenshots, B-roll, report screens, motion graphics) carry half the story. This is the **built-out** preset — apply `presets/signature-style.md` verbatim for the hooks.

- **Face framing (LOCKED — measure, never guess):** at the top of Graphics run `uv run workflows/face-frame.py projects/<job>/outputs/<job>.mp4`. It detects the face + true hair top across sampled frames and prints the exact `#head` `object-position` that puts the **median hair top 50px below the y960 seam** — the locked framing standard. Use the printed value in the build verbatim (also written to `projects/<job>/face-frame.json`). After the draft render, `uv run workflows/face-frame.py --verify <render>` must print ✓ PASS before review.
- **Reframe → 9:16:** crop to 1080×1920 if the footage isn't already — `face-frame.py` prints the face-centered ffmpeg crop when the source is 16:9. Keep the face in the **bottom** box.
- **Graphics (step 3):** fill the **top half** — region y `200 → 960`, but **key graphic content tops out ~y880** so it stays clear of the centered-caption band (~y900–1080). Screenshots / B-roll / motion graphics synced to the VO. Plan first with `graphics-plan` (which lines get a graphic, which stay plain), then build in HyperFrames per `presets/signature-style.md`. Beats that want generated motion (no real footage, filmic or abstract texture): generate the clips with your AI-video tool first, then composite them like any part.
- **Captions (step 5):** **centered** — sit them on the graphics/face seam (around the vertical middle, ~y 900–1080), inside the safe box. Feed the derived transcript, never re-transcribe.

**Split layout (1080 × 1920):** graphics ≈ y `200 → 960` (top half, below the platform header) · face ≈ y `960 → 1620` (bottom half, above the UI band) · captions centered on the seam. Key visuals stay inside the safe box (below).

---

## Preset B — TikTok / Raw

Full-frame raw talking head. **Graphics = one front hook card, nothing else.** Lightest finish. **Locked** — look + builder live in [`presets/tiktok-raw-style.md`](../presets/tiktok-raw-style.md).

- **Reframe → 9:16:** crop to 1080×1920 if not already.
- **Graphics (step 3):** a single **hook card** (locked look: `presets/tiktok-raw-style.md`) pinned to the **top** safe zone. Appears at the start, **disappears once the hook lands** (~first 2–4 s). After it, the footage plays raw. No top-half graphics, no B-roll, no lower-thirds.
- **Captions (step 5):** **low — under the face**, inside the caption-safe band (locked look: `presets/tiktok-raw-style.md`). Feed the derived transcript, never re-transcribe.

---

## Safe Zones (9:16, always 1080 × 1920) — THE rule, never break it

**The top 200 px and bottom 300 px hold NO key visuals — background / filler only.** His face, the captions, and every key visual (graphics, hero text, numbers, logos, hook cards) must sit **inside the safe box**. The two bands can carry background, grid, glow, or B-roll bleed — nothing the viewer actually needs to see, because the platform UI and the device chrome land there.

| Band | No key visuals — background/filler only |
|------|------------------------------------------|
| **Top** | **200 px** — status bar / platform header |
| **Bottom** | **300 px** — caption UI, username, audio tag, CTA, progress bar |

→ **Safe box:** full width, y `200 → 1620`. Sides are fine to use.
→ Explainer captions sit centered inside the box · the TikTok/raw hook card sits inside the top of it · the face is framed inside it.

---

## Length philosophy

The rough cut already aims for the tightest version that still delivers (~1–2 min target — the `rough-cut` "max value per second" filter governs). If the value fits in 40 s, ship 40 s. Don't pad graphics or captions to stretch it.

## CTA

CTA decisions live in your content system (the script carries any ask). This edit adds no sales asks — captions and end screens stay clean (see CLAUDE.md Rules).
