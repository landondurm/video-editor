# 🛠️ Setup — read this first

This is a **video editing system you run with [Claude Code](https://claude.com/claude-code).** You
drop in raw footage, and Claude takes it from **raw → fully edited → exported.** It does short-form
explainers, TikTok/raw-style verticals, and long-form YouTube intros, with locked, on-brand captions,
graphics, and thumbnails.

**Runs natively on macOS, Windows, and Linux.** On a Mac it uses Apple's hardware video encoder; on
Windows/Linux it uses software encoding — same output, just a bit slower.

The fastest path: unzip, open this folder in Claude Code, and say **"run the setup"** (or "set me
up"). Claude detects your OS, runs the one-command auto-installer (**`./setup.sh`**: installs every
tool via Homebrew on macOS / winget on Windows, bootstraps the render engine, verifies itself,
**auto-detects your editing app** (Premiere Pro / DaVinci Resolve / CapCut) and wires its lane, and
is safe to re-run), and walks you through the one or two restarts along the way. If you have several
editing apps installed it asks one question: which one you edit in. That's the whole setup.
Personalizing the look/voice (your brand kit) is **optional** and can happen any time later, or
never. Everything below is the same setup by hand, if you prefer to see each step.

### 🪟 On Windows — one install first

No WSL, no virtual machine — the system runs natively. Its scripts run through **Git Bash**, the
Unix shell that ships with **Git for Windows** (it's also the shell Claude Code itself uses on
Windows), so that's the one thing to install first:

1. Install **Git for Windows**: `winget install Git.Git` (in PowerShell), then restart Claude Code
   so it finds Git Bash.
2. Unzip the project anywhere normal (e.g. `C:\Users\<you>\video-editor` — Windows Explorer's
   Extract All is fine) and open that folder in Claude Code.
3. That's it. Everything below runs unchanged; wherever a command says `brew`, use the
   **Windows (winget)** version below. After any `winget install`, open a **new** terminal
   (and restart Claude Code once) so PATH picks the tool up.

---

## 1. Install the prerequisites

**The automatic way** (recommended; auto-installs on macOS + Windows, prints the exact apt
commands on Linux and finishes the rest there too):

```bash
./setup.sh
```

It detects your OS, installs everything missing, bootstraps the render engine, verifies, then
auto-detects your editing app and wires its lane (one app: wired automatically; several: it asks
which you edit in). Re-run it after any restart: it skips what's done and finishes the rest. (The
one manual step it can ask of you: installing Homebrew itself on a fresh Mac, which needs your
password.) It tells you exactly when a Claude Code restart is needed; there are at most two (once
after Windows tool installs, once after an editing-app MCP is wired).

**The manual way** — run the report-only checker and follow what it prints:

```bash
./check-setup.sh
```

### Core (required — the raw → exported pipeline)

`./check-setup.sh` prints the right command for whichever OS you're on — run it and follow what it shows.

**macOS:**

```bash
# Homebrew (skip if you already have it)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install ffmpeg          # every audio/video pass (cut, captions, music, render)
brew install uv              # builds the WhisperX transcription engine on first run
brew install node            # the graphics render engine (npx hyperframes)
brew install python          # caption + thumbnail text overlays
brew install pillow          # PIL — text overlays (this ffmpeg has no built-in text)
```

**Windows (winget — built into Windows 11 / App Installer):**

```bash
winget install Gyan.FFmpeg           # every audio/video pass (cut, captions, music, render)
winget install OpenJS.NodeJS.LTS     # the graphics render engine (npx hyperframes)
winget install Python.Python.3.12    # caption + thumbnail text overlays
winget install astral-sh.uv          # builds the WhisperX transcription engine on first run
python -m pip install pillow         # PIL — text overlays (run AFTER the Python install, new terminal)
```

> Open a **new terminal** after the winget installs (and restart Claude Code once) so PATH updates.
> Note: on Windows, Python is `python`, not `python3` — the `python3` name there is a fake
> Microsoft Store stub. The pipeline scripts handle this automatically.

**Linux (Ubuntu / Debian):**

```bash
sudo apt update
sudo apt install -y ffmpeg python3 python3-pip python3-pil   # video passes + caption/thumbnail text (PIL)

# Node ≥22 (the render engine) — Ubuntu's apt node is too old, so use NodeSource:
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs

# uv (builds the WhisperX transcription engine on first run):
curl -LsSf https://astral.sh/uv/install.sh | sh

sudo apt install -y wamerican   # optional: enables the transcript-QA word scan
```

Then bootstrap the render engine **once**:

```bash
npx hyperframes@0.7.92 doctor   # downloads the headless browser the graphics renderer uses
```

> Pinned to `@0.7.92` — the version the locked caption/graphics presets were validated against.
> Using the same version for the one-time bootstrap means it's cached once and every render uses it.
>
> **On Linux,** if `doctor` (or a render) reports a missing shared library, install the headless-Chrome
> deps it names, e.g. `sudo apt install -y libnss3 libatk-bridge2.0-0 libgtk-3-0 libgbm1 libasound2t64`.

**First edit is slow, once.** The first time you run a job, the rough-cut step downloads the WhisperX
`large-v3` speech model (~3–5 GB) and builds its environment. That takes several minutes and needs
internet — but only the first time. Every job after is fast. **Your hardware is auto-detected:** an
NVIDIA GPU (Windows/Linux) transcribes on CUDA, several times faster than CPU (the first build adds
the ~3 GB CUDA stack), and if the GPU path ever fails it falls back to CPU automatically, so
transcription always works. Macs and GPU-less machines run the reliable CPU path. (Same idea, much smaller: the face-framing
tool `workflows/face-frame.py` auto-installs its OpenCV dependency via `uv` on first use, ~50 MB.)

### Fonts — all bundled, nothing to install

- **Inter** — bundled in `assets/fonts/` (free, Open Font License). The display font for signature-style
  and long-form graphics. Nothing to install — and it's the cross-platform default. *(macOS only:
  prefer Apple's SF Pro?* Install the free "San Francisco Pro" pack from <https://developer.apple.com/fonts>
  and set it in `brand-kit.md`. On Windows/Linux, stay on the bundled Inter.)
- **Coolvetica** — bundled in `assets/fonts/` (the locked explainer caption look). Nothing to do.
- **SF Pro (system)** — *optional.* The TikTok/raw overlays render from bundled **Inter** by default; SF Pro is not required.

### Optional (only if you use the feature)

- **Thumbnails (long-form):** the Higgsfield CLI + a paid Higgsfield account —
  `curl -fsSL https://raw.githubusercontent.com/higgsfield-ai/cli/main/install.sh | sh` then
  `higgsfield auth login`.
- **Premiere lane** (the recommended finish if you edit in Premiere — the rough cut
  lands on your timeline as **separate, trimmable clips**, and Claude can build graphics, apply
  effects, recolor sections, and run the final export in there too): one command,
  ```bash
  ./setup-premiere.sh
  ```
  It installs the pinned Premiere MCP engine (`vendor/premiere-mcp`, built from source at a verified
  commit), installs the **MCP Bridge (CEP)** panel into Premiere, and writes `.mcp.json`. Safe to
  re-run; it skips what's already done. Requires **Adobe Premiere Pro** (validated on Premiere Pro 2026, 26.x) on
  **macOS or Windows** — plain Linux has no Premiere, use the default chat-only pipeline.
  Afterward: restart Premiere → **Window → Extensions → MCP Bridge (CEP) → Start Bridge** →
  restart Claude Code once → verify with `node workflows/premiere-bridge.mjs ping`.
- **DaVinci Resolve lane** (the same finish, in Resolve on macOS, Windows, or Linux; **Studio**
  recommended, since external scripting is a Studio feature): one command,
  ```bash
  ./setup-resolve.sh
  ```
  It installs the pinned Resolve MCP server (`vendor/davinci-resolve-mcp`, built from source at a
  verified commit) and writes the `davinci-resolve` entry into `.mcp.json` (other servers are left
  untouched). Safe to re-run. Afterward: restart Claude Code once → verify by asking Claude to get
  the Resolve version. No bridge panel needed; Resolve just has to be running (Claude can launch
  it), and there's nothing to change inside Resolve: **External scripting = Local is its default.**
  Only if the connection fails after the restart, check **Preferences → System → General → External
  scripting = Local** (Studio feature; the free edition uses the MCP's in-app bridge script instead).
  The `davinci-resolve` skill documents everything the lane can do, plus the API calls to avoid.
- **CapCut lane** (the same, in the CapCut desktop app — macOS only): nothing to
  install beyond CapCut itself. `uv run workflows/capcut-bridge.py replay <job>` writes the rough cut
  as a native CapCut draft, one trimmable clip per cut. **Quit CapCut fully before running it** (it
  clobbers new drafts on exit otherwise). Full lane rules + live-editing commands: the CapCut section
  in `CLAUDE.md`.
- **Speaker labels** (`rough-cut --diarize`): set `HUGGINGFACE_TOKEN` (see `.env.example`). The normal
  single-speaker flow does **not** need this.

---

## 2. Make it yours (optional: any time, or never)

The editor works out of the box with a neutral bundled look (Inter fonts, a generic starter
palette). Personalization only makes captions, graphics, and thumbnails sound and look like *you*.
Whenever you want that:

1. **Fill in `brand-kit.md`** — your name, niche, handles, voice/tone, brand colors, fonts, hook style,
   and brand wordlist. This is the one file that drives how every caption and thumbnail sounds and looks.
   (Part A is the fill-in form; **Part B** spells out exactly which file and token each value changes, if
   you want to do it by hand or verify Claude's work.)
2. **Drop your face photos** into `assets/face-refs/` — 4–8 photos of *your* face (varied angles /
   expressions / lighting). Only needed if you want generated thumbnails. See that folder's README.
3. *(Optional)* **Add your logos** to `assets/logos/` — any brand marks you want available for thumbnails.

Then tell Claude **"apply my brand kit"** and it writes those values into the presets and `CLAUDE.md`
for you (the exact map is Part B of `brand-kit.md`), and renders a quick test so you can see the look
took.

---

## 3. Edit your first video

1. Put a raw clip somewhere handy (e.g. `~/Downloads`).
2. In Claude Code, say: **"edit this video: ~/Downloads/yourclip.mp4"**.
3. Claude copies it into `projects/<job>/raw/`, runs the rough cut, plans graphics, and walks the rest
   of the pipeline with you. It auto-detects the format from the footage (vertical = short-form,
   horizontal = long-form YouTube) and states the hook + takeaway it read from your transcript;
   correct it in a word if it read wrong.
4. The finished deliverable is `projects/<job>/outputs/<job>.final.mp4` (promoted by `./finalize.sh
   <job> --apply`, which also drops an export copy in `~/Downloads/`, ready to upload).

That's it. The whole pipeline and how each step works is documented in `CLAUDE.md`.

---

## What's in the box

| Path | What it is |
|------|-----------|
| `CLAUDE.md` | The editor's brain — the pipeline, the rules, the format variants. |
| `brand-kit.md` | Optional personalization: fill it in whenever you want the output to carry your brand. |
| `setup.sh` | One-command auto-setup: detects macOS/Windows, installs everything, bootstraps the renderer, wires your editing app's lane. |
| `check-setup.sh` | Prerequisite checker (report-only). |
| `.claude/skills/` | The editing skills + the HyperFrames render toolkit. |
| `presets/` | The locked looks — signature style, captions, TikTok/raw, liquid-glass, the vox print-collage long-form look, plus `motion-craft.md` (the graphics craft rules). |
| `workflows/` | Per-format layout + safe-zone references, the Premiere and CapCut bridge scripts, and the Resolve lane docs: `resolve-templates/` (fps-matched project templates), `resolve-grading/` (the color playbook), `resolve-export.md` (delivery-render settings), `resolve-audio-polish/` (the final audio pass). |
| `assets/` | Fonts (bundled) + the face-detection model + an `sfx/` folder for your sound-effects library (ships empty — see its README) + your face refs / logos / thumbnail templates (you supply). |
| `projects/` | Your job folders land here (one per video). |
| `finalize.sh` | The export step — promotes the final render to `outputs/<job>.final.mp4` and copies it to `~/Downloads/` (dry-run by default). |
| `prune.sh` | Reclaims disk space from old render scratch (dry-run by default). |
