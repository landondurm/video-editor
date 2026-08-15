# hf-graphics — five-stage-client-process

**Status:** first draft assembled → `renders/final.mp4` (awaiting creator second pass)
**Tier:** basic, `presets/default-overlay-style.md` · light pass per creator ask (4 cards)
**Base:** `../outputs/five-stage-client-process.mp4` (3840×2160 @ 60000/1001, 49.47s) — never re-rendered here

## Parts (all transparent overlays, Callout R, no face coverage)

| id | window | card |
|----|--------|------|
| g1 | 0.8–9.0 | label: MY SALES PROCESS · "5 Stages → More Clients" |
| g2 | 9.8–15.4 | label: STAGE 01 · "Decipher" + body |
| g3 | 17.6–24.4 | meters: ON THE CALL · YOU 20% / THEM 80% |
| g4 | 26.8–33.4 | label: STAGE 02 · "The Offer" + body |

## Mechanics
- `python3 build.py` regenerates `compositions/*.html` + `parts.json` (source of truth).
- Comps author in 1920×1080 coords inside a static 2× `.stage` wrapper → native 4K alpha
  (alpha + `--resolution` is rejected by the CLI, hence the wrapper).
- `./render-part.sh <id>` renders one part (~30–70s) → `renders/parts/<id>.mov` (ProRes alpha, 59.94).
- `./assemble.sh` composites base + 4 overlays (~15s) → `renders/final.mp4`, runs the YDIF
  dup-frame guardrail (fails ≥8%; measured 0%).
- Font paths must stay root-relative (`assets/fonts/...`) — `../` fails lint/preview.
- Tweak loop: edit build.py → `python3 build.py` → render only the changed part → assemble.
