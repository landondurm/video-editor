#!/usr/bin/env python3
"""
generate.py — submit thumb.json concepts to Higgsfield via the `higgsfield` CLI, wait, download images.

Reads:    /tmp/thumbnails/<slug>/thumb.json
Writes:   projects/<slug>/thumbnails/generated/<concept_id>_v<n>.png
          /tmp/thumbnails/<slug>/thumb_resolved.json

Anchor model: every file in assets/face-refs/ is passed as `--image <path>` on every
generation. Per-concept extra_refs (logos, scene refs) are appended via additional
`--image <path>` flags. The CLI auto-uploads local paths — no manual upload step
required.

Default model: nano_banana_2 (Nano Banana Pro). Per-concept model override supported
(e.g. seedream_v4_5).

Usage:
    generate.py <thumb.json> [--only <id>[,<id>...]] [--dry-run] [--yes]
"""
import argparse
import json
import re
import shutil
import subprocess
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[4]  # .../video-editor (project root)
FACE_REFS_DIR = PROJECT_ROOT / "assets" / "face-refs"
PROJECTS_ROOT = PROJECT_ROOT / "projects"

DEFAULT_MODEL = "nano_banana_2"
DEFAULT_ASPECT = "16:9"
DEFAULT_VARIANTS = 3
WAIT_TIMEOUT = "10m"
# Higgsfield Plus plan: $49/mo for 1000 credits → $0.049/credit
USD_PER_CREDIT = 0.049

# Per-model quality flag + default. Only models that accept multiple `--image` refs
# as the canonical face-anchor mechanism are listed.
MODEL_CONFIG = {
    "nano_banana_2": {"quality_flag": "--resolution", "quality_default": "2k",   "credits": 2.0},
    "seedream_v4_5": {"quality_flag": "--quality",    "quality_default": "high", "credits": 1.0},
}

IMG_EXT_RE = re.compile(r"\.(png|jpe?g|webp)(\?|$)", re.I)


def ensure_cli() -> None:
    if shutil.which("higgsfield") is None:
        sys.stderr.write("higgsfield CLI not found. Install: curl -fsSL https://raw.githubusercontent.com/higgsfield-ai/cli/main/install.sh | sh\n")
        sys.exit(1)
    r = subprocess.run(["higgsfield", "account", "status"], capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write("higgsfield CLI not authenticated. Run: higgsfield auth login\n")
        sys.exit(1)


def list_face_refs() -> list[Path]:
    if not FACE_REFS_DIR.exists():
        return []
    return sorted(p for p in FACE_REFS_DIR.iterdir()
                  if p.is_file() and p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"})


def resolve_ref(p: str) -> Path:
    pp = Path(p)
    return pp if pp.is_absolute() else (PROJECT_ROOT / p)


def collect_concept_refs(concept: dict, face_paths: list[Path]) -> list[Path]:
    paths = list(face_paths)
    for ep in concept.get("extra_refs") or []:
        p = resolve_ref(ep)
        if not p.exists():
            sys.stderr.write(f"[thumb] WARN missing extra_ref: {p}\n")
            continue
        paths.append(p)
    return paths


def extract_result_url(stdout: str) -> str | None:
    """Find the result_url on a completed job node. Strict — no regex fallback to
    avoid grabbing echoed --image upload URLs."""
    try:
        data = json.loads(stdout)
    except (json.JSONDecodeError, ValueError):
        return None
    found = []
    def walk(n):
        if isinstance(n, dict):
            if n.get("status") == "completed" and isinstance(n.get("result_url"), str):
                found.append(n["result_url"])
            for v in n.values():
                walk(v)
        elif isinstance(n, list):
            for v in n:
                walk(v)
    walk(data)
    return found[0] if found else None


def ext_from_url(url: str) -> str:
    m = IMG_EXT_RE.search(url)
    if m:
        e = m.group(1).lower()
        return ".jpg" if e == "jpeg" else f".{e}"
    return ".png"


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(url, timeout=180) as r, open(dest, "wb") as f:
        while True:
            chunk = r.read(1 << 16)
            if not chunk:
                break
            f.write(chunk)


def generate_one(concept: dict, variant_idx: int, defaults: dict,
                 ref_paths: list[Path], out_dir: Path) -> dict:
    cid = concept["id"]
    vid = f"{cid}_v{variant_idx}"
    model = concept.get("model", defaults["model"])
    if model not in MODEL_CONFIG:
        return {"id": vid, "concept_id": cid, "status": "error",
                "error": f"unsupported model: {model}. Supported: {', '.join(MODEL_CONFIG)}"}
    cfg = MODEL_CONFIG[model]
    aspect = concept.get("aspect_ratio", defaults["aspect_ratio"])
    quality = concept.get("quality", defaults.get("quality") or cfg["quality_default"])

    cmd = [
        "higgsfield", "--json", "generate", "create", model,
        "--prompt", concept["prompt"],
        "--aspect_ratio", aspect,
        cfg["quality_flag"], quality,
        "--wait", "--wait-timeout", WAIT_TIMEOUT,
    ]
    for p in ref_paths:
        cmd += ["--image", str(p)]

    sys.stderr.write(f"[thumb] {vid} submitting ({model}, {aspect}, {quality}, {len(ref_paths)} refs)\n")
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        err = (r.stderr or r.stdout or "").strip().splitlines()
        return {"id": vid, "concept_id": cid, "status": "error",
                "error": " | ".join(err[-3:])[:500]}
    url = extract_result_url(r.stdout)
    if not url:
        return {"id": vid, "concept_id": cid, "status": "error",
                "error": f"no completed result_url in output: {r.stdout.strip()[:300]}"}
    dest = out_dir / f"{vid}{ext_from_url(url)}"
    try:
        download(url, dest)
    except Exception as e:
        return {"id": vid, "concept_id": cid, "status": "error", "error": f"download {url}: {e}"}
    return {"id": vid, "concept_id": cid, "status": "ok", "path": str(dest), "source_url": url}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("manifest")
    p.add_argument("--only", help="comma-separated concept ids to (re)generate")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--yes", action="store_true", help="skip confirmation")
    args = p.parse_args()

    manifest_path = Path(args.manifest)
    manifest = json.loads(manifest_path.read_text())
    concepts = manifest.get("concepts") or []
    if args.only:
        wanted = set(args.only.split(","))
        concepts = [c for c in concepts if c["id"] in wanted]
    if not concepts:
        sys.stderr.write("[thumb] no concepts to generate\n")
        sys.exit(1)

    model_default = manifest.get("model", DEFAULT_MODEL)
    if model_default not in MODEL_CONFIG:
        sys.stderr.write(f"[thumb] unsupported default model: {model_default}\n")
        sys.exit(1)
    cfg = MODEL_CONFIG[model_default]
    defaults = {
        "model": model_default,
        "aspect_ratio": manifest.get("aspect_ratio", DEFAULT_ASPECT),
        "quality": manifest.get("quality", cfg["quality_default"]),
    }
    variants = int(manifest.get("variants_per_concept", DEFAULT_VARIANTS))

    total = len(concepts) * variants
    credits_total = sum(MODEL_CONFIG.get(c.get("model", model_default), cfg)["credits"] for c in concepts) * variants
    est = credits_total * USD_PER_CREDIT
    sys.stderr.write(f"[thumb] {len(concepts)} concept(s) × {variants} variant(s) = {total} images ≈ {credits_total:.0f} credits ≈ ${est:.2f} total\n")

    use_face_refs = manifest.get("face_refs", True)
    face_paths = list_face_refs() if use_face_refs else []
    if use_face_refs and not face_paths:
        sys.stderr.write(f"[thumb] ERROR: no face-refs in {FACE_REFS_DIR}\n")
        sys.exit(1)

    # Resolve per-concept ref paths upfront (fail fast on missing extras)
    concept_refs: dict[str, list[Path]] = {c["id"]: collect_concept_refs(c, face_paths) for c in concepts}
    sys.stderr.write(f"[thumb] {len(face_paths)} face-ref(s) + extras per concept\n")

    if args.dry_run:
        for c in concepts:
            sys.stderr.write(f"[thumb] DRY: {c['id']} ({c.get('name','')}, {len(concept_refs[c['id']])} refs) — {c['prompt'][:80]}\n")
        sys.exit(0)

    if not args.yes:
        ans = input("[thumb] Continue and submit paid generations? [y/N] ").strip().lower()
        if ans not in {"y", "yes"}:
            sys.stderr.write("[thumb] cancelled\n")
            sys.exit(0)

    ensure_cli()

    slug = manifest.get("slug") or manifest_path.parent.name
    out_dir = PROJECTS_ROOT / slug / "thumbnails" / "generated"
    out_dir.mkdir(parents=True, exist_ok=True)

    jobs = [(c, v) for c in concepts for v in range(1, variants + 1)]
    results = {}
    with ThreadPoolExecutor(max_workers=min(6, len(jobs))) as ex:
        futs = {ex.submit(generate_one, c, v, defaults, concept_refs[c["id"]], out_dir): (c["id"], v)
                for c, v in jobs}
        for fut in as_completed(futs):
            r = fut.result()
            results[r["id"]] = r
            tag = "OK " if r["status"] == "ok" else "ERR"
            sys.stderr.write(f"[thumb] {tag} {r['id']}: {r.get('path') or r.get('error')}\n")

    resolved = dict(manifest)
    resolved["output_dir"] = str(out_dir)
    resolved["results"] = list(results.values())
    (manifest_path.parent / "thumb_resolved.json").write_text(json.dumps(resolved, indent=2))
    sys.stderr.write(f"[thumb] output: {out_dir}\n")

    failed = [r for r in results.values() if r["status"] != "ok"]
    if failed:
        cs = sorted({r["concept_id"] for r in failed})
        sys.stderr.write(f"[thumb] {len(failed)} failed — re-run with --only={','.join(cs)}\n")
        sys.exit(2)


if __name__ == "__main__":
    main()
