# CLAUDE.md — Video Editor

Your **video production & editing department** — and **only** that. Raw filmed footage comes in,
a finished exported cut goes out. This system is self-contained: you point it at a raw clip and it
takes that clip from **raw → fully edited → exported.** What happens to the export afterward
(posting, scheduling) is out of scope — this repo's job ends at the rendered file.

Not a traditional code repo — a content system where **Claude IS the editor.** Each stage runs
through a skill in `.claude/skills/`.

---

## 🪟 On Windows? One check first

This system runs natively on **macOS, Windows, and Linux** — no WSL, no virtual machine. On Windows
the `.sh` scripts run through **Git Bash** (installed with **Git for Windows**), which is the same
shell Claude Code itself uses on Windows.

**Figure out where you are** — run `uname -s` in the shell:
- `Darwin` (macOS) or `Linux` → you're set, skip to **FIRST RUN** below.
- `MINGW…` / `MSYS…` → **Windows with Git Bash working** — also set, skip to **FIRST RUN**.
- Command-not-found / PowerShell-looking output (`C:\…` paths) → **Git for Windows is missing.**
  Have the user run `winget install Git.Git` in PowerShell, restart Claude Code, and re-check
  before continuing.

> Windows notes: installs go through **winget** (`./check-setup.sh` prints the exact command per
> tool); after each install, open a new terminal and restart Claude Code once so PATH updates.
> Python on Windows is `python`, never `python3` (that name is a fake Microsoft Store stub — the
> pipeline scripts already handle it). Apple's hardware video encoder is a Mac-only speed perk;
> Windows/Linux render with software encoding (same result, a bit slower). An NVIDIA GPU is
> auto-detected and transcription runs on CUDA there (several times faster, automatic CPU fallback
> if the GPU path fails). Nothing else differs.

---

## 🚦 FIRST RUN — onboarding gate (read this before doing anything else)

**This is the first thing to handle when the project opens.** A SessionStart hook
(`.claude/hooks/setup-check.sh`) injects a reminder for as long as setup is incomplete. Trigger this
flow whenever the user says **"run the setup"** / **"set me up"** / **"continue setup"**, **or** asks
to edit/cut/process any video while the tools are not installed yet (an edit cannot run without
ffmpeg).

**Is setup done?** One deterministic check: the marker file **`.setup-complete`** exists ⇒ the tools
are done (`./setup.sh` writes it once every core tool verifies). Marker present + the user is just
opening the project or asking for an edit ⇒ skip this gate and work normally. Marker present + the
user said **"continue setup"** (they're mid-flow, back from a restart) ⇒ don't redo step 1: re-run
`./setup.sh` once (instant, it reports lane state), then jump to step 2's verification and step 3's
one-line brand-kit offer. Marker missing ⇒ run the full flow below.

**The goal: core editing working, fast, with near-zero effort from the user.** Personalization
(brand kit) is OPTIONAL and comes last. Never block editing on it: the presets ship with a neutral
bundled look (Inter fonts, a generic starter palette, no handles), so nothing of anyone else's brand
can leak into a video.

1. **Tools: run `./setup.sh` yourself.** Don't ask first (installing the tools is the whole point of
   this gate) and don't hand the user a command list; announce what it's doing as it goes. It
   auto-detects the OS (macOS → Homebrew, Windows → winget), installs every missing core tool,
   bootstraps the render engine (`npx hyperframes@0.7.92 doctor`), verifies with `./check-setup.sh`,
   then probes for installed editing apps (step 2). It is **idempotent: re-run it after any
   interruption** and it picks up where it left off. Handle its exits:
   - **exit 0** with an `ACTION FOR CLAUDE` line in the output: several editing apps were found.
     Go to step 2 (ask which one).
   - **exit 2 (Windows):** freshly installed tools need a fresh environment. Walk the user through a
     Claude Code restart (see the restart walkthrough below), then re-run `./setup.sh`.
   - **exit 3:** it wired an editing-app lane into `.mcp.json`. Walk the user through a Claude Code
     restart, then verify the lane (step 2).
   - **exit 1:** something needs fixing first; read the output. Homebrew missing (macOS) → the user
     runs the printed one-liner themselves (it needs their password), then you re-run `./setup.sh`.
     Missing Linux tools → the user runs the printed apt commands. A lane installer failed → read its
     error, fix it, re-run `./setup.sh`.
   Loop until `./check-setup.sh` shows every core item ✓. (Manual per-OS command list: `SETUP.md`.
   On Linux tools install via the printed apt commands, but `setup.sh` still verifies, wires a
   detected Resolve, and writes the marker.)
2. **Editing app lane: auto-detected, at most one question.** `setup.sh` probes for Premiere Pro,
   DaVinci Resolve, and CapCut:
   - **One app found** → it already ran the matching installer (`./setup-premiere.sh` /
     `./setup-resolve.sh`) and exited 3. After the Claude Code restart, verify the lane:
     **Premiere** → have the user restart Premiere, open **Window → Extensions → MCP Bridge (CEP) →
     Start Bridge**, then run `node workflows/premiere-bridge.mjs ping`. **Resolve** → ask the
     `davinci-resolve` MCP for the Resolve version (Resolve must be running; you can launch it).
     **Do NOT send Resolve users into Preferences up front**: External scripting = Local is Resolve's
     shipped default. Check that setting only as troubleshooting, if the connection fails after the
     restart.
   - **Several apps found** → ask ONE line (e.g. "You've got Premiere and Resolve: which one do you
     edit in?"), run the matching installer yourself, then do the restart walkthrough + verify above.
     (CapCut needs no install; its lane works out of the box, macOS only.) The pick is final: on a
     several-app machine, later `setup.sh` runs just note the other installed app as available; never
     wire it unless the user asks for it.
   - **No app found** → the chat-only pipeline is the finish. Say so in one line and move on; don't
     ask about apps.
3. **Brand kit: OPTIONAL. Offer once, never block.** Tell the user the editor already works with the
   neutral bundled look, and that whenever they want captions/graphics/thumbnails to sound and look
   like them, they can fill in `brand-kit.md` and say **"apply my brand kit"** (you then follow the
   exact file-by-file map in `brand-kit.md` Part B and render one quick test). Don't walk them
   through it during setup unless they ask for it.

**Restart walkthrough (both restart points; be exact and friendly):** tell the user: *"Quit Claude
Code completely (Cmd+Q on Mac / close the app on Windows), reopen it, open this same folder, and say
**continue setup**."* When the session resumes, pick up where the flow stopped: re-run `./setup.sh`
(it skips what's done) and continue. Never assume a restart loaded anything; verify
(`./check-setup.sh` for tools, a ping/version call for an MCP lane).

> **Face refs are optional** — they're only used for long-form YouTube *thumbnails*. When the user first
> asks for a thumbnail, have them drop 4–8 photos of their own face into `assets/face-refs/` (see that
> folder's README). Short-form-only creators never need them, so don't block onboarding on this.

---

## Brand Kit

The editor's voice and look come **entirely from [`brand-kit.md`](brand-kit.md)** and the presets it
feeds. Captions and on-thumbnail copy should sound like the creator described there; the signature
look is locked in [`presets/signature-style.md`](presets/signature-style.md). Apply those verbatim.

> Filling it in is OPTIONAL: the presets ship with a neutral bundled look (Inter fonts, a generic
> starter palette, no handles, no hook text), so editing works before any personalization and nothing
> of anyone else's brand can end up in a video. Offer the brand kit once after setup; apply it
> whenever the user asks.

---

## The Pipeline — one linear flow, every time

Every job runs the **same seven steps, in order**, raw → done. Format (short vs long, explainer vs
TikTok/raw) does **not** change the flow — it only changes how **Graphics (step 3)** and
**Captions (step 5)** behave. So don't "pick a workflow" up front. Run the line; branch only inside
those two steps.

| # | Step | Skill | What happens |
|---|------|-------|--------------|
| 1 | **Intake** | _(copy)_ | Point to a raw file (often in `~/Downloads`). **Copy** it into `projects/<job>/raw/` — never move, never touch the original, so the source clip is safe if a render goes sideways. Name `<job>` after the content (see Job naming). |
| 2 | **Rough cut** | `rough-cut` | Always, every format. WhisperX large-v3 transcribe + word-align → kill filler/dead air → stitch (**frame-snapped cuts + J-cut audio crossfades** — see the splice quality note below) → **normalize audio with a STATIC chain (+10 dB amplify → −6 dBFS hard limiter — NOT dynamic loudnorm, which pumps)** → **`audio-qa.py` self-check** (read its ⚠ lines). Produces the cut **and the finished script** (the kept-words transcript) — the source of truth for everything downstream. |
| 3 | **Graphics** | `graphics-plan` → HyperFrames | **Default = the BASIC tier: [`presets/default-overlay-style.md`](presets/default-overlay-style.md)** — clean UI cards **over** the footage, 4–7 of them, the speaker's face never covered, ~30 min. Anything bigger (full-frame takeovers, bespoke art, another look) is opt-in **by name** — a request for "a graphics pass" never means the big version. Two sub-steps. **(a) Plan** (`graphics-plan`) — reads the rough-cut transcript and decides, beat by beat: graphic or not? what kind? where exactly? Writes `graphics-plan.{json,md}`. **(b) Create** — build the planned graphics in HyperFrames. For the split-frame explainer preset, **measure the face crop first** — `uv run workflows/face-frame.py projects/<job>/outputs/<job>.mp4` prints the exact `#head` `object-position` (locked standard: median hair top 50 px below the y960 seam — measured, never guessed). The *content* diverges by format (below); the step doesn't. |
| 4 | **Second pass** | _(manual)_ | The first graphics pass is a draft. Review and call adjustments — cut this graphic, swap that one, move it, redo. **Iterate incrementally:** render/lock graphics part-by-part and recomposite with ffmpeg (~5s) instead of re-rendering the whole video each tweak — see [`workflows/incremental-graphics.md`](workflows/incremental-graphics.md). |
| 5 | **Captions** | `presets/captions-style.md` (explainer) · `presets/tiktok-raw-style.md` (TikTok/raw) | **Short-form only.** Explainer → use the **LOCKED caption preset** ([`presets/captions-style.md`](presets/captions-style.md): Coolvetica white-on-black box, dead-centered on the seam, full-phrase box, words pop in on-beat). TikTok/raw → captions **low, under the face** ([`presets/tiktok-raw-style.md`](presets/tiktok-raw-style.md)). Both build from the canonical `outputs/<job>.transcript.json` — never re-transcribe. **Long-form → skip** (YouTube serves its own CC). |
| 6 | **Background music** | `background-music` | **Optional, format-agnostic.** Lays a music bed under the voice — a **flat constant bed** by default (no ducking, no fade-in, −18 dB, short tail fade-out only). Ducking (sidechain + re-normalize to −14 LUFS) and fade-in are **opt-in**. Pure audio pass (video copied, no re-encode). Most useful on short-form explainers; skip unless asked. Track lives in `projects/<job>/audio/`. |
| 7 | **Export** | _(render → `finalize.sh`)_ | Render the final, then **finalize** so the folder is unambiguous: `./finalize.sh <job>` (dry-run; `--apply` to act) promotes the latest render to the **one** canonical deliverable **`projects/<job>/outputs/<job>.final.mp4`**, retires dead drafts, and **drops an export copy in `~/Downloads/`** (ready to grab/upload — `VE_EXPORT_DIR` overrides the target), while **keeping** the base cut (`<job>.mp4`), transcript, and `hf-graphics/` source so the job can be reopened. That's the finish line. Then `./prune.sh --apply` reclaims the regenerable cache. |

**If you use a video editing app, that's the recommended finish (steps 3–7 below are the chat-only
path for when you don't).** After step 2, hand the rough cut to **Adobe Premiere Pro** via the
`premiere-pro` skill — or **CapCut** via `capcut` — and do the editing there. It does
**not** import a flattened export — it **rebuilds the rough cut as separate, trimmable clips on the
timeline** by replaying the EDL (`transcript/cuts.json`) against the raw footage, so every cut is a
real edit point you can ripple/slip/slide. **On this path, run the splice as `RENDER=0 splice.sh
<job>`** — it refines + frame-snaps the cuts, persists the EDL and corrected transcript in seconds,
and never renders the flat MP4 (nothing on the Premiere path consumes it; transcription is the only
slow step allowed before the timeline). Then replay immediately:
`node workflows/premiere-bridge.mjs replay <cuts.json> <clipName>` (the headless bridge driver — no
MCP session needed). Claude can also work ON the timeline from there: graphics as alpha-ProRes
overlays and baked footage moves (see `workflows/premiere-graphics.md`), per-clip audio chains,
per-section label colors (set the project item's label BEFORE the replay — clips stamp it at insert),
and the final export via `exportAsMediaDirect` (renders inside Premiere — never queue Adobe Media
Encoder). One-time setup: `./setup-premiere.sh` — see SETUP.md (optional feature).

**The same, in CapCut** (macOS, needs the CapCut desktop app — no other install). CapCut has
no API, so `workflows/capcut-bridge.py` works two lanes. **File lane (build):** CapCut drafts are plain
JSON under `~/Movies/CapCut/User Data/Projects/com.lveditor.draft/`, and
`uv run workflows/capcut-bridge.py replay <job>` writes a whole draft straight from
`transcript/cuts.json` — one trimmable timeline clip per cut, butt-joined to the EDL (run the splice
`RENDER=0`, same as the Premiere path). The rules that keep it working: **CapCut must be fully quit
while the bridge writes** (on exit it rewrites the shared draft registry and clobbers new entries);
raw footage is **hardlinked into the draft's `Resources/`** automatically, because CapCut's sandbox can
only read `~/Movies` (outside paths open as red "File not accessible" clips); to file-edit a draft
CapCut has already opened once, the bridge deletes the draft's `Timelines/` native cache so the JSON is
re-imported (otherwise edits are silently ignored); and once the user has **hand-edited a draft in the
app, only add to it** (`add-overlay` / `add-text` / `graphics <draft> <job>` / `transform`) — never
re-run `replay` over it, which would wipe those hand edits. Alpha ProRes graphics composite with true
transparency on overlay tracks; text tracks are native. **Live lane (interactive):** with the editor
open, the bridge drives the real UI through the macOS accessibility tree — `open`, `seek`, `select`,
`split`, `delete`, `undo`, markers, `save`, plus `shot` for QA screenshots — so small edits need no
quit/relaunch. **`export` finishes the job inside CapCut**: it drives CapCut's own export dialog and
verifies the file that lands (1080p mp4 into `~/Downloads` by default). Two export rules: CapCut's
post-export "share to TikTok/YouTube" screen is modal and blocks the next export (the bridge clears
it, and you should never click through it — it publishes), and a segment carrying a null
`source_timerange` wedges the encoder mid-render, so the bridge repairs those before every write.
Run `uv run workflows/capcut-bridge.py` with no args for the full command list.

**The same, in DaVinci Resolve** (macOS, Windows, or Linux; Studio recommended). One-time install:
`./setup-resolve.sh` wires the `davinci-resolve` MCP, which drives Resolve's **official scripting
API** (no bridge panel; Resolve just has to be running). The
`davinci-resolve` skill carries the whole lane: the EDL replay is **one call**
(`media_pool create_timeline_from_clips` rebuilds `transcript/cuts.json` as separate trimmable
clips, linked audio included; run the splice `RENDER=0`, same as the other app lanes), and from
there Claude can work the timeline through the API: silence-ripple auto cuts (`edit_engine`), AI
subtitles + transcript-based cut proposals, Fusion node graphs, custom DCTL color shaders, in-app
Python, vision-based clip metadata, and native in-Resolve renders. The skill also carries the
hard-won traps: never `timeline apply_cuts` (it deletes whole clips while reporting success);
match the project frame rate to the SOURCE footage by importing a template `.drp` from
`workflows/resolve-templates/` rather than `create_project` + `set_setting` (the Playback frame
rate is a separate setting the API cannot write, and a mismatch plays chopped audio — mint new
rates with `mint-template.py`, then read both fps keys back before building); and vertical 9:16
fill is one property write (`Scaling = 3`), not zoom math. Two later stages have their own
measured playbooks: delivery renders follow
[`workflows/resolve-export.md`](workflows/resolve-export.md) (`VideoQuality` is a dropdown index,
not a bitrate; `MultiPassEncode` is the only real quality lever; verify with ffprobe on the
finished file), and the final audio pass follows
[`workflows/resolve-audio-polish/`](workflows/resolve-audio-polish/README.md) (measure each source
file with `ebur128`, static gain to −16 LUFS, −1 dBFS limiter, then `ReplaceClip` the normalized
copies under the locked timeline; run it only after the edit is locked).

**Second entry path: long-form → clips (`clipper`).** The pipeline above runs raw → one video; the
`clipper` skill runs the reverse: a FINISHED long-form in, a batch of 9:16 captioned clips out.
Transcribe the published file once, select self-contained hook-and-payoff moments into a reviewed
`clips-plan.json`, then `python3 .claude/skills/clipper/scripts/make-clips.py projects/<parent>
--build` runs each approved clip through the locked engine (rough-cut splice → face-centered 9:16
reframe → TikTok/raw captions → `.final.mp4` + a `~/Downloads/` export copy). Each clip is a
standard job folder under `projects/<parent>/clips/<name>/`, so every skill here works on it.

### Format variants — only steps 3 & 5 change

**Format is AUTO-DETECTED from the raw footage, never asked.** Probe the clips: **vertical**
(height > width) → short-form; **horizontal** → long-form YouTube. Mixed folder → the clips carrying
the substance decide (the main dialogue/talking takes; b-roll and inserts don't vote). Explainer vs
TikTok/raw is inferred from content (teaching/system walkthroughs cut like explainers; casual
talk-to-camera stays raw). State the detected format in the report so the creator can override with
a word; ask only if the footage is genuinely undecidable. Same rule for intent: the hook + takeaway
are read out of the transcript (or sampled frames on a visual-only edit), stated for correction,
never requested up front.

| | **Short · Explainer** | **Short · TikTok/raw** | **Long-form** |
|---|---|---|---|
| **Where** | Reels · TikTok · Shorts | Reels · TikTok · Shorts | YouTube |
| **Aspect** | 9:16 · 1080×1920 | 9:16 · 1080×1920 | 16:9 · 1920×1080 (no reframe) |
| **Graphics (3)** — *full tier* | top-half graphics, face bottom — full plan | **front hook card only** (`presets/tiktok-raw-style.md`), then raw | liquid-glass panels + takeover/zoom (`presets/liquid-glass-style.md`), or the print-collage look (`presets/vox-collage-style.md`) |
| **Graphics (3)** — *default* | *overlay cards, top half* | *unchanged — hook card only* | *overlay cards, callout zone* → all formats use [`presets/default-overlay-style.md`](presets/default-overlay-style.md) unless a bigger pass is asked for by name |
| **Captions (5)** | centered — **locked** (`presets/captions-style.md`) | low, under face — **locked** (`presets/tiktok-raw-style.md`) | none |
| **Thumbnail** | usually skip | usually skip | **always** (`thumbnail-generator`, alongside render) |

The 9:16 reframe (short-form) happens at the top of Graphics. Exact safe-zone pixel margins +
per-format layout live in [`workflows/short-form.md`](workflows/short-form.md) and
[`workflows/long-form.md`](workflows/long-form.md) — read the matching one before building graphics.

**Short-form safe zones (always, never break):** no key visuals in the **top 200 px** or **bottom
300 px** — the face, captions, and every key graphic stay inside y `200 → 1620`. Those two bands are
background/filler only (platform UI + device chrome sit there).

## Skills

- **Core editing:** `rough-cut`, `graphics-plan`, the locked caption presets (`presets/captions-style.md`,
  `presets/tiktok-raw-style.md` + their `build.py`), `background-music`, `thumbnail-generator`
- **`graphics-plan`** — the step-3a creative-direction skill: reads the rough-cut transcript and
  decides, beat by beat, where graphics go, what kind, and whether a line needs one at all. Outputs
  `projects/<job>/graphics-plan.{json,md}`. It never renders.
- **`premiere-pro`** — the recommended finish if you edit in Premiere: rebuilds the cut as **individual
  trimmable timeline clips** by replaying the EDL against the raw footage, then lets Claude keep
  working on the timeline (graphics overlays, audio effect chains, section label colors, frame-grab
  QA, direct in-Premiere export). Drives the MCP Bridge panel headlessly via
  `workflows/premiere-bridge.mjs`. One-time install: `./setup-premiere.sh` — see SETUP.md.
- **`davinci-resolve`**: the same finish in DaVinci Resolve, through Resolve's official scripting
  API (no bridge panel needed): one-call EDL replay into separate trimmable clips, then
  silence-ripple cuts, Fusion graphs, DCTL shaders, in-app Python, vision metadata, and native
  renders. The skill lists what's verified AND which API calls are broken or destructive. One-time
  install: `./setup-resolve.sh` (see SETUP.md).
- **`clipper`**: the reverse entry path, a finished long-form in, short-form clips out.
  Selection-first (a reviewed `clips-plan.json` + cut sheet before anything renders), then
  `make-clips.py --build` reuses the locked engine per clip: rough-cut splice, face-centered 9:16
  reframe, TikTok/raw captions, deliverable + Downloads export copy.
- **HyperFrames suite (engine):** `hyperframes` (+ `-core`, `-cli`, `-animation`, `-creative`,
  `-registry`, `-keyframes`) and `media-use` — the HTML-based video toolkit that renders graphics & captions.
- **HyperFrames task workflows (advanced/optional):** `faceless-explainer`, `general-video`,
  `talking-head-recut`, `motion-graphics`, `pr-to-video`, `product-launch-video`,
  `remotion-to-hyperframes`, `slideshow`. These are vendored extras for one-off
  builds; the everyday pipeline above doesn't need them. (For short-form captions always use the
  locked presets in step 5.)

### HyperFrames video-authoring toolkit (vendored)

A general HTML-based video toolkit from `heygen-com/hyperframes`, pinned in `skills-lock.json`. It's
the creation engine for **Graphics (step 3b)** and **Captions (step 5)**. The render CLI runs via
**`npx hyperframes`** (auto-downloads on a machine with `node`) — run `npx hyperframes doctor` once to
bootstrap (pin it: `npx hyperframes@0.7.92 doctor`). **Update via the skills registry, not by
hand-editing** — `skills-lock.json` tracks hashes.

## Folder Structure

The project root **is** the editing workspace — job folders live directly in `projects/`.

| Path | What's In It |
|------|--------------|
| `.claude/skills/` | The editing skills + the vendored HyperFrames toolkit |
| `projects/<job>/` | One folder per content piece: raw clips in `raw/`, audio/music in `audio/`, source assets in `assets/`, B-roll in `broll/`, thumbnails in `thumbnails/`, finals in `outputs/`. The HyperFrames graphics build lives **durably** in `hf-graphics/` (its `build.py` + `compositions/` + `parts.json` + a `PROJECT.md` resume doc — never delete this; it's the real progress). Only the **regenerable** cache (`renders/`, base slices, font copies) is disposable. **Nothing lives solely in `/tmp`** — it's volatile on every platform (macOS clears it; Windows/Linux temp dirs get cleared too) and it wiped a whole build once. `prune.sh` reclaims the cache when a job ships. |
| `finalize.sh` | The **export** step (step 7). `./finalize.sh <job>` promotes the latest render to the one canonical `outputs/<job>.final.mp4`, retires drafts, and **copies the deliverable to `~/Downloads/`** (the "export"), keeping the base cut + transcript + `hf-graphics/` source for re-editing. Dry-run by default; `--apply` to act. |
| `prune.sh` | Reclaims space in `projects/` (dry-run by default; `--apply` to delete). |
| `assets/` | Shared generation assets — `face-refs/` (your face, for thumbnails), `fonts/`, `logos/`, YT thumbnail templates, `sfx/` (your SFX library for timeline sound design — ships empty, fill it from the separate SFX-pack download or your own clips, see its README), `models/` (the face-detection model). **Personalize:** drop your own face refs + logos here (see each folder's README). |
| `brand-kit.md` | The one file you fill in — your identity, voice, colors, fonts, hook style. |
| `skills-lock.json` | Pins the vendored HyperFrames skills (source + hash). |
| `check-setup.sh` | Report-only check of the system tools the editing skills need (ffmpeg, etc.). |

**Job naming:** name `<job>` after the video's content — a short kebab-case title (e.g.
`my-first-video`, `cold-dm-teardown`), **never** the camera file (`C1840.MP4`), a date, or a stage suffix.

## Rules

- **One job: edit the best video possible.** Raw → fully edited → exported. No business/CTA logic
  lives here — captions and end screens carry no sales asks.
- **Surgical changes only.** Touch what's asked. Don't "improve" adjacent renders or refactor
  working skills.
- **Update HyperFrames via the registry,** not by hand — `skills-lock.json` tracks hashes.
- **Document, don't manufacture.** Authenticity outperforms.
- **Motion craft = [`presets/motion-craft.md`](presets/motion-craft.md).** Required reading before any
  graphics plan or graphics build: materials + texture, no pure white, restraint on effects, screens
  treated as objects, mixed footage homogenized. It's what separates the work from generic AI slop.
- **Repeated line across takes → use the LAST take.** Don't ask.
- **Captions run the whole video by default** — never suppress them under a hook or graphic unless told.

## Lab Notes — how the locked presets work

These are engineering notes from the original build of this system — the *why* behind the locked
presets, so you can extend them without re-discovering the gotchas. Any job names that appear are
worked examples from that build.

- **Transcribe ONCE per video.** WhisperX large-v3 is the single transcription for the whole pipeline
  (most accurate, so it's the source of truth). `rough-cut` persists it to
  `projects/<job>/transcript/words.json` and reuses forever (`--force` to redo). Finishing/captions do
  NOT re-transcribe: `splice.sh` derives `outputs/<job>.transcript.json` by remapping kept words
  through `cuts.json` (pure arithmetic). **Spelling/brand fixes are applied right there** — as it
  writes the canonical transcript, `export-transcript.py` runs `presets/caption-corrections.json` over
  it, so the fix reaches graphics-plan AND both caption formats AND long-form (the raw `words.json`
  stays untouched). The locked caption builders (step 5) read that already-corrected canonical
  `outputs/<job>.transcript.json` directly. The WhisperX venv builds once and is reused across jobs.
- **Splice quality = frame-snapped cuts + J-cut crossfades + a self-check (do not simplify these away).**
  Three audio-artifact mechanisms were found the hard way and are fixed at root in `splice.sh`:
  (1) every cut boundary **snaps to the video frame grid** — un-snapped fractional cuts give each
  segment a video duration up to ±1 frame different from its audio, and ffmpeg's `concat` pads the
  difference with digital-silence gaps at joints (audible room-tone dropouts + a progressive timeline
  stretch that desyncs captions/graphics). Snapped, the rendered timeline equals `transcript/cuts.json`
  exactly, so everything downstream anchors to EDL times directly. (2) joints are **equal-power
  crossfades over real continuing room tone** (each segment's audio runs 15 ms past its video cut),
  never butt-splices (they click on any non-zero crossing) and never fades-to-zero (those punch audible
  ambience holes). Timing stays exact by construction. A per-joint `"xfade": <seconds>` override in
  `cuts.json` widens the ramp into a segment whose cut-in clips an in-progress word attack (acoustic
  onsets often start tens of ms before the word timestamp). (3) the limiter runs with `latency=1`
  (its lookahead otherwise delays audio ~5 ms vs video). After every splice, **`audio-qa.py`** verifies
  joints, ambience continuity, timeline integrity, and limiter pressure — if it warns about limiter
  pressure, the footage is peakier than the default gain assumes: re-run with `AMPLIFY_DB=8` and
  compare by ear. Two more mechanisms are fixed at cut time: (4) **cut boundaries are MEASURED, not
  trusted** — WhisperX word starts run ~50–100 ms late vs the real acoustic attack (and ends run
  early), so `refine-cuts.py` runs inside `splice.sh` before every cut: it measures each chosen word's
  acoustic edge on a 5 ms RMS envelope of the raw and moves the cut just outside it (onset − 40 ms /
  offset + 50 ms, clamped to never cross an adjacent word). Cut CHOICE stays Claude's; `REFINE=0` or
  `"no_refine": true` skips it. (5) **merged repeats** — WhisperX collapses an immediately repeated
  word ("However… However") into ONE entry spanning every utterance, hiding the stutter from the
  transcript. `transcribe.sh` flags long-span words (>1.0 s); the refiner burst-scans them — a segment
  STARTING on one snaps to the last utterance (prefer-last-take), one ENDING on one trims to the first,
  and a mid-segment one gets a ⚠ (author a split around it). (6) **joints are resolved PAIRWISE:
  segments may never overlap in the source.** A continuous split (one unbroken take carved into
  separate timeline clips) must share ONE boundary time; padded outward on both sides, the same
  source frames get laid down twice and play as a 1–15 frame stutter, invisible to every
  per-segment check (each segment is individually perfect, only the pair is wrong).
  `refine-cuts.py` detects continuous splits from transcript adjacency and merges each overlap to
  a single shared boundary (a `no_refine`-pinned side is never moved; the unpinned side joins it),
  and `splice.sh` hard-aborts post-snap on any overlap that survives, naming the segment numbers.
  Refinement is NOT idempotent (it measures from the authored cut), so repair an EDL that was
  already refined or shipped with `refine-cuts.py --repair-only` (joint resolution only, zero
  re-measurement), never a second full pass.
- **Premiere-path jobs never render the flat cut.** When the finish surface is Premiere, run
  `RENDER=0 splice.sh <job>` — refine + frame-snap + persist the EDL + corrected canonical transcript
  in seconds, no ffmpeg encode. `audio-qa.py` is render-dependent and skipped; level-check in Premiere
  instead (measure the raw's mean volume with ffmpeg `volumedetect` and scale the clip Amplify dB to
  taste — quieter footage needs more gain). The metric is time-to-timeline: transcription is the only
  slow step allowed.
- **Explainer captions = LOCKED preset.** Standard burn-in for talking-head explainers lives in
  [`presets/captions-style.md`](presets/captions-style.md) + builder
  [`presets/captions/build.py`](presets/captions/build.py). Coolvetica Regular 49px, white on a
  solid-black box, dead-centered on the frame seam (y960), box pre-sized to the full phrase, words pop
  in per-word on their own WhisperX timestamp (on-beat karaoke). **The timing lock:** build captions
  ONLY from the canonical `outputs/<job>.transcript.json` and overlay onto the render that ships —
  same timeline → on-beat with zero manual nudging. Brand mishears are already fixed upstream by
  [`presets/caption-corrections.json`](presets/caption-corrections.json) (applied to the canonical
  transcript at splice time — see the transcribe-once note above), so captions inherit them.
- **TikTok/raw = LOCKED preset.** Hook card + line captions live in
  [`presets/tiktok-raw-style.md`](presets/tiktok-raw-style.md) + builder
  [`presets/tiktok-raw/build.py`](presets/tiktok-raw/build.py). Hook card = Inter Bold 64px
  black-on-white-box, sized to the ink extents (not font metrics), pinned top (y250), shown only over
  the spoken hook (auto-ends on a configured trigger word or `--hook-end`); captions = Inter Bold
  42px white + 4px black stroke, no box, no animation, line-by-line, low under the face (y1500).
  **Captions are ALWAYS ON** the whole video — the hook card overlays on top, never replaces them.
  Engine = PIL PNG overlays + ffmpeg `overlay` enable-timing (this ffmpeg has no freetype/libass, so
  PIL is the house pattern). Deliverable = `outputs/<job>.final.mp4` (keep `outputs/<job>.mp4` as the
  clean base the builder reads from — don't overwrite, or you'll caption an already-captioned video).
  **Gotcha:** the `-loop 1` PNG overlay inputs never EOF, so the output MUST be bounded with `-t`
  (source duration) — the builder always passes it.
- **Explainer face framing = LOCKED: hair top 50 px below the seam, measured not guessed.** Before
  building split-frame explainer graphics, run
  `uv run workflows/face-frame.py projects/<job>/outputs/<job>.mp4`. It samples ~12 frames of the base
  cut, detects the face (OpenCV YuNet — model bundled at `assets/models/`), finds the true hair top via
  median-background subtraction (works even with dark hair on a dark room), and prints the exact
  `object-position` for the `#head` cover-crop → also written to `projects/<job>/face-frame.json`. If
  the source is still 16:9 it prints the face-centered ffmpeg crop for the 9:16 reframe too. Fallback
  when hair can't be measured (hat/hood): face-box center → y1385. After the draft render,
  `uv run workflows/face-frame.py --verify <render>` must print ✓ PASS before review. First run
  auto-installs the OpenCV dependency via `uv` (one time, needs internet).
- **Full-video explainer graphics = GENERATE the composition, don't hand-author it.** A ~2-minute
  explainer is ~20+ graphics — too many clips to hand-write reliably. Pattern: a `build.py` reads the
  `graphics-plan` and emits `index.html` from ~10 templates (title-card / stat / checklist / ranked /
  iconrow / screenshot-card / diagram / engine). Bottom-half talking head = the full rough cut
  cover-cropped into y960–1920 (track 0); top half = a persistent background clip + each graphic a
  windowed clip on alternating `data-track-index`; one master paused GSAP timeline with absolute
  times. Gotchas: (1) every exit fade that ends on the next clip's start boundary needs a
  `tl.set("#id",{opacity:0}, end)` hard-kill or HyperFrames pops the transition; (2) keep the graphic
  stage at y200–880 so it stays inside the safe box AND clear of the centered-caption seam (~900–1080).
- **Incremental graphics = render PART-BY-PART, composite with ffmpeg.** The second-pass tweak loop
  doesn't re-render the whole video per change. Full doc:
  [`workflows/incremental-graphics.md`](workflows/incremental-graphics.md). A parts-oriented `build.py`
  emits one composition PER graphic + `render-part.sh <id>` + `assemble.sh`. Two part kinds: **overlay**
  (floats over footage → render standalone as a transparent `.mov` via `--format mov`) and **segment**
  (modifies the footage itself → render opaque `.mp4` carrying its own base slice). `assemble.sh` is
  ONE ffmpeg pass chaining base + each part with `-itsoffset` + `overlay=enable='between(...)'`. Loop =
  edit `build.py` → render only the changed part (~30–50s) → assemble (~5s) → review. The base rough cut
  is NEVER re-rendered. Render every part at the base fps (e.g. `--fps 24000/1001` for 23.976) or frames
  drift through ffmpeg. The win is modest on a short reel but compounds hard on long-form.
- **Render cut drift — SOLVED by the frame-snapped splice.** With snapping on, the rendered timeline
  equals `transcript/cuts.json` to the millisecond, so graphics/zooms anchor to EDL times directly.
  Only for a base rendered by an OLD un-snapped splice do you still verify cut times with ffmpeg
  `scdet` before anchoring to them.
- **`prune.sh`** reclaims space in `projects/` — deletes only regenerable dead weight (HyperFrames
  `work-*` render scratch, stray `node_modules`, intermediate renders; keeps `*final*`/`*graphics*` +
  highest `-vN`). Never touches source `raw/*.mp4` or `outputs/`. Dry-run by default; `--apply` to
  delete. The space hog is raw footage + leftover render scratch.
