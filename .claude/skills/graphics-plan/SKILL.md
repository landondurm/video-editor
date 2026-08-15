---
name: graphics-plan
description: "Plans the graphics for a video BEFORE any are built — the creative-direction step (3a) between rough-cut and HyperFrames. Reads the finished-script transcript and decides, beat by beat: does this line need a graphic at all, what kind, and where. Outputs a graphics plan the creation step builds from and the second pass edits. Does NOT create graphics. Triggers: plan the graphics, graphics plan, where should graphics go, ideate graphics, what graphics for this, graphic direction, plan visuals for this reel."
---

# Graphics Plan — decide what gets a graphic, what kind, where

**Step 3a of the pipeline.** Rough-cut already produced the finished script (the cut-aligned transcript). This skill reads that script and produces a **graphics plan** — a beat-by-beat decision of graphic-or-not, what kind, where on frame, and the actual creative idea — *before anything is built*. The HyperFrames creation skills (step 3b) build from this plan; the **second pass** edits it.

**This skill decides graphics. It does not create them.** No rendering, no HyperFrames, no HTML. The output is a plan, not a video.

The whole job is judgment: **a graphic on every line is wrong** — plain beats give rhythm and let your face carry the moment. The skill's value is picking the *right* lines and a *genuinely good* idea for each, not blanketing the script.

---

## 🔒 STEP 0 — the scope tier (do this before any planning)

> **"Do a graphics pass" = the BASIC tier. Always. Assume nothing bigger.**
> Default look + scope: [`presets/default-overlay-style.md`](../../../presets/default-overlay-style.md) — modern
> blue UI cards **over** the footage, **4–7 graphics**, no full-frame, no bespoke illustration, ~30 min.

| Tier | Trigger | What it is |
|---|---|---|
| **Basic** ← DEFAULT | "do the graphics", "graphics pass", "add some overlays" | `default-overlay-style.md`. 4–7 cards from the 6 templates. Face never covered. |
| **Full** | you ask for it **by name** — "go all out", "full graphics pass", "make it crazy", names a look | takeovers, bespoke art, 15+ graphics, whatever it takes |

**A tier is never inferred from how good the footage is or how much the beat could carry.** An
exciting script is not permission to escalate. When a beat genuinely wants more than a card, note it
in the plan in one line and plan the card anyway — you upgrades it if you want it.

**Two things require an explicit ask before they go in a plan, every time:**
1. **Anything full-frame** or that covers your face — state the total second-count in the plan summary and get a yes.
2. **A non-default look** (Vox collage, liquid-glass takeover, anything with its own preset doc).

Ask both in ONE line at plan time, not mid-build.

> **Craft principle — plan against `presets/motion-craft.md`.** Read it before writing ideas. Every `content` idea should already think in materials and imperfection (what's the texture, where does the eye go, does this beat's motion want twos, is a screenshot getting a screen treatment + camera drift), so the build step inherits taste instead of defaulting to clean digital slop.

> **Core principle — visuals over text.** Graphics are **usually visual- and animation-heavy, not text-heavy.** The motion / footage / data should carry the point; words are a label, a number, or a hook line — used sparingly. Reserve text-forward cards for the hook + punchlines only. **And remember captions are added later** (step 5: centered for explainer, low for TikTok/raw) — so don't fill the frame with on-screen text a caption will then collide with. When in doubt, cut the words and let the visual do the work.

---

## Inputs

1. **The job** — reads `projects/<job>/outputs/<job>.transcript.json` (the finished script from rough-cut). If that doesn't exist, rough-cut hasn't run — stop and say so.
2. **The format** — `short-explainer`, `short-tiktok`, or `long-form`. It sets density, regions, and style (below). If unknown, ask the one-liner: *"explainer, TikTok/raw, or long-form?"*

---

## Step 1 — Segment the script into beats

```bash
python3 .claude/skills/graphics-plan/scripts/segment-script.py projects/<job> /tmp/video-editor/<job>/graphics-plan.scaffold.json
```

Groups the words into sentence beats (`id`, `start`, `end`, `line`) with empty decision fields. It prints a readable beat sheet. The segmentation is mechanical — **merge or split beats freely** when planning if a graphic idea spans two short beats or a long beat needs two visuals. The beats are a starting grid, not a contract.

## Step 2 — Decide each beat (the actual work)

For every beat, answer in order:

**a. Does this line even need a graphic?** Default to **plain** unless a graphic earns its place. A beat earns a graphic when it:
- is the **hook** (beat 1 always gets a graphic),
- names something **concrete and showable** — a number/stat, a screenshot, a product/dashboard, a name, a before/after, a list,
- is a **payoff/punchline** worth emphasizing,
- describes a **process or structure** a visual would make instantly clearer.

Leave it **plain** when the line is connective tissue ("and yeah, it works"), a transition, a personal aside, emotional delivery, or rhetorical setup. Those land harder on your face alone. Don't let two graphics collide on adjacent short beats — merge them or let one breathe.

**b. What kind? Default to SHOWING, not telling.** Keep graphics **visual- and animation-heavy, not text-heavy** — most of the time the *motion is the message*. Reach first for kinds that show the thing moving — real screen recordings, B-roll, animated diagrams/data, visual metaphors. **Reserve pure text / kinetic-type cards for the hook and punchlines** where the words themselves are the payoff — and even then give them a visual element + motion, never a static wall of type. If a beat could be a text card OR a visual, pick the visual.

| Kind | Use it for |
|------|-----------|
| `screen-rec` | the thing actually working — a demo, the agent running, the report building live |
| `b-roll` | illustrative motion footage over a claim |
| `screenshot` | the real artifact — a post, a report, the tool's output, a DM (zoom/pan/annotate it, don't just park it) |
| `diagram` / `flow` | how it works — steps / pipeline / architecture, drawn ON as you talk |
| `data-viz` | numbers in motion — a chart drawing in, a count-up, a ranking, an outlier spiking |
| `motion-graphic` | a visual metaphor that animates the idea — scan, lock-on, fan-out, build-up |
| `stat-callout` | a single number as a beat — but count it up / pop it, never static-place it |
| `icon-row` / `list` | a set of things — features, what-you-get, steps (reveal in sequence) |
| `quote` / `comment` | a comment, tweet, DM, testimonial |
| `lower-third` | a name / title / label (long-form especially) |
| `kinetic-title` / text card | **reserve for** the hook + punchlines — words ARE the payoff. Give them motion + a visual element, not a wall of type |
| `annotation` | arrow / highlight / circle pointing at part of another visual |

**c. Where (region)?** Set by format:
- **short-explainer** → graphics live in the **top half** (`top-half`, y 200→960); your face is the bottom half. Captions come later, centered on the seam.
- **short-tiktok** → only one graphic, a **hook card** pinned `top` inside the safe zone; it disappears after ~2–4s. Everything else plain.
- **long-form** → `full` cutaways (B-roll/screen-rec), `lower-third` for names/labels, intro hook up top. Mind the 16:9 safe zones + end-screen region.

> **Short-form safe zones — never break this.** Keep every key visual out of the **top 200 px and bottom 300 px** (those bands are background/filler only — platform UI + device chrome land there). Key graphics, hero text, numbers, the face, and captions all sit inside y `200 → 1620`. Place each `top-half`/`top`/`full` graphic so its readable content stays in the safe box. See `workflows/short-form.md`.

**d. The idea (`content`).** Write the actual creative direction, not a category — what's on screen, the hierarchy, the hero element. **Describe the motion** — what animates and in what order. Concrete enough that the creation step can build it without guessing.

On the **basic tier** the idea names one of the six templates in `presets/default-overlay-style.md` plus its copy and which side it sits on — that's a complete spec, and "which template + what words" is the whole design decision. On the **full tier**, short-explainer graphics obey `presets/signature-style.md` and long-form `presets/liquid-glass-style.md` (locked colors/fonts/backgrounds) — reference the preset; design each fresh, don't stamp.

### Density by format

**On the BASIC tier (the default), density is capped at 4–7 graphics** for an intro or section
regardless of format — pick the strongest beats and leave the rest plain. The numbers below are the
**full**-tier densities; only use them when the user asked for a full pass by name.

- **short-explainer** — visuals carry half the story, so **most teaching beats get a graphic** (~roughly half to two-thirds of beats), but quality over coverage. Hook, every concrete claim, every stat, the payoff. Plain on the connective beats.
- **short-tiktok** — **exactly one graphic**: the front hook card. Default everything else plain. A second graphic only if a single stat is too big to skip. (Same on both tiers.)
- **long-form** — **sparser, more varied.** Intro hook + B-roll/screen-rec over claims + lower-thirds on names/stats + the occasional diagram. No percentage target — cover what genuinely needs showing.

## Step 3 — Write the plan

Write two files to the job folder (they're reviewed artifacts, not scratch):

- **`projects/<job>/graphics-plan.json`** — the machine-readable plan the creation step consumes (schema below).
- **`projects/<job>/graphics-plan.md`** — a human cut-sheet for you to review: a table of `# · time · line · graphic? · kind · idea`, with the graphic'd beats marked. This is what the **second pass** edits against.

Report back tight: **the tier**, total beats, how many got graphics, **how many seconds (if any) cover your face**, and the 2–3 strongest ideas. Flag any beat you're unsure on with `⚠️` so the user can call it. If the plan wants anything on the "requires an explicit ask" list from Step 0, that ask goes here — in one line, before building.

### `graphics-plan.json` schema

```json
{
  "job": "your-job",
  "format": "short-explainer",
  "tier": "basic",
  "duration": 136.56,
  "preset": "presets/default-overlay-style.md",
  "face_covered_seconds": 0,
  "beats": [
    {
      "id": 1, "start": 0.05, "end": 5.03,
      "line": "I just built this Claude skill that can predict exactly what you need to post to go viral.",
      "graphic": true,
      "kind": "kinetic-title",
      "region": "top-half",
      "content": "Two-tone hook title — 'predict what goes VIRAL', hero word 'viral' in a royal boxed chip, signature spotlight bg.",
      "reason": "the hook — must open on a strong visual"
    },
    {
      "id": 2, "start": 5.17, "end": 6.49,
      "line": "And yeah, it works.",
      "graphic": false,
      "reason": "connective beat — let your delivery carry it, no graphic"
    }
  ]
}
```

Keep `graphic:false` beats in the array (with a `reason`) so the plan is a complete map of the script, not just a graphics list — the second pass needs to see the plain beats too.

---

## Handoff

The plan feeds **step 3b (creation)** — the HyperFrames skills (`general-video`/`hyperframes`, `motion-graphics`, `talking-head-recut`) build each `graphic:true` beat at its `start`/`end` in its `region`, per the `content` idea. **On an app finish** the same plan drives that lane instead — set `"compositor"` in the plan JSON so the creation step knows the target: `"premiere"` (the `premiere-pro` skill's "Graphics in Premiere" recipe: alpha overlays on V2 + baked footage moves on V1), `"capcut"` (`workflows/capcut-bridge.py` consumes the plan; see the `capcut` skill's graphics step), or `"resolve"` (the `davinci-resolve` skill's "Graphics on the timeline" section, `place.py` pattern). For short-explainer, build to `presets/signature-style.md`. `b-roll` / `motion-graphic` beats with no real footage to pull from can be **generated** as AI clips with your AI-video tool of choice, then composited like any part. Then the **second pass** adjusts, and **captions** (short-form) come after.

This skill does ONE thing: decide the graphics. It never renders.
