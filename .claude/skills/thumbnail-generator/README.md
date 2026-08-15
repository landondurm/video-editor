# thumbnail-generator — setup

Generates YouTube thumbnails via Higgsfield Nano Banana Pro. Claude reads your video's hook or title, proposes thumbnail concepts with cinematic prompts, and you approve a JSON manifest before anything is submitted. `generate.py` renders 16:9 PNGs in parallel and downloads them locally. `add_title.py` then burns bold block-style title text on top using PIL — no Canva or Photoshop needed. Trigger phrases: "make a thumbnail", "yt thumbnail", "generate thumbnail", "youtube thumbnail", "design a thumbnail", "style-match this thumbnail", "add title to thumbnail".

## Install

Drop this folder into a skills directory:
- `<project>/.claude/skills/thumbnail-generator/` — for one project, or
- `~/.claude/skills/thumbnail-generator/` — to use it everywhere.

The scripts resolve the project root automatically from their own location (`parents[4]` from `scripts/`), so the folder must sit at exactly `.claude/skills/thumbnail-generator/` inside your project root — not deeper or shallower.

When copying/zipping the folder for someone else, exclude `scripts/__pycache__/` and `.DS_Store`. If your project has a `.env` file at the project root, exclude that too — it contains live secrets and must never be distributed.

## Prerequisites

**1. Higgsfield account + CLI (required, paid).** The scripts call the `higgsfield` CLI directly — no API key env var, no config file. Auth is a login session stored by the CLI itself.

- Install the CLI:
  ```
  curl -fsSL https://raw.githubusercontent.com/higgsfield-ai/cli/main/install.sh | sh
  ```
- Log in:
  ```
  higgsfield auth login
  ```
- Verify: `higgsfield account status` — must exit 0 before the script will run.

The script will error immediately with "higgsfield CLI not authenticated" if the session is missing or expired. Re-run `higgsfield auth login` to fix it. A Higgsfield Plus plan ($49/mo, 1000 credits) is enough for normal use; `nano_banana_2` costs 2 credits per image (~$0.10 at Plus rates). The script prints an estimated cost and prompts for confirmation before submitting anything.

**2. System tools.** Python 3.10+ and the `Pillow` library are required. On macOS:

```
brew install python
pip3 install Pillow
```

`add_title.py` also uses Helvetica Bold, which is included with macOS at `/System/Library/Fonts/Helvetica.ttc`. On Linux you will need to substitute a different `.ttc` path by editing the `HELVETICA` constant at the top of `add_title.py`.

**3. Face-ref photo library (required for identity-anchored generations).** `generate.py` loads every `.png`, `.jpg`, `.jpeg`, or `.webp` file from `assets/face-refs/` at your project root and passes them all as `--image` flags to every generation. This is how the model locks the subject's identity. You must supply your own photos — this folder is not included in the distributed skill.

- Location: `<project-root>/assets/face-refs/`
- Recommended: 4–8 photos. Varied angles, expressions, and lighting improve fidelity. More than 8 may exceed the model's per-run image cap.
- Acceptable formats: PNG, JPG, JPEG, WEBP.
- The CLI uploads each file automatically on every run — no manual upload step.

If the folder is empty or missing and `face_refs` is `true` in the manifest, the script exits with an error before submitting anything.

**Style-match mode (no face refs needed).** When the manifest sets `"face_refs": false` at the top level, `generate.py` skips the face-refs folder entirely. Use this when mimicking a flat-illustration or no-humans thumbnail style — pass the reference image via a concept's `extra_refs` instead.

## Output

Generated images land at:

```
projects/<slug>/thumbnails/generated/<concept_id>_v<n>.png
```

where `<slug>` comes from the `slug` field in the manifest. A `thumb_resolved.json` summary is also written to `/tmp/thumbnails/<slug>/` alongside the original manifest.

After picking a winner, `add_title.py` writes the titled version to whatever output path you pass as the second argument — typically `/tmp/thumbnails/<slug>/titled_<winner>.png`.
