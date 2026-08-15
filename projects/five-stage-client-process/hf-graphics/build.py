#!/usr/bin/env python3
"""Build the 4 default-overlay cards for five-stage-client-process.

Basic tier, presets/default-overlay-style.md. Each card is an independent
transparent-overlay comp (no shared timeline), rendered to alpha ProRes .mov
at 4K via --resolution landscape-4k (comp space stays 1920x1080), 59.94 fps.
"""
import json, os, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
FPS = 60000 / 1001
F = 1001 / 60000          # one frame at 59.94
STEP = f"steps(2)"         # 12-frame move quantized on the 6-frame grid (~10fps look)

# id, window start, window end (base-timeline seconds)
PARTS = [
    ("g1", 0.8,  9.0),
    ("g2", 9.8,  15.4),
    ("g3", 17.6, 24.4),
    ("g4", 26.8, 33.4),
]

CSS = """
  body{margin:0;background:transparent;font-family:'Inter',sans-serif;}
  @font-face{font-family:'Inter';src:url('assets/fonts/Inter-Black.otf');font-weight:900;}
  @font-face{font-family:'Inter';src:url('assets/fonts/Inter-Bold.otf');font-weight:700;}
  @font-face{font-family:'Inter';src:url('assets/fonts/Inter-Regular.otf');font-weight:400;}
  #root{position:relative;width:3840px;height:2160px;overflow:hidden;}
  .clip{position:absolute;inset:0;}
  /* static 2x stage: card coordinates stay 1920x1080, output is native 4K.
     Never GSAP-tween this element (CSS transform is its own). */
  .stage{position:absolute;left:0;top:0;width:1920px;height:1080px;
    transform:scale(2);transform-origin:0 0;}
  :root{--royal:#1e48ff;--sky:#57c9f0;--txt:#e8f0ff;--muted:#8fa6d4;}
  .panel{position:absolute;left:1180px;width:620px;box-sizing:border-box;
    background:linear-gradient(160deg,#12224e 0%,#0a1435 100%);
    border:2px solid rgba(96,146,255,0.42);border-radius:22px;
    box-shadow:0 26px 60px rgba(2,7,24,0.72), 0 0 0 1px rgba(6,13,36,0.85),
               inset 0 2px 0 rgba(140,180,255,0.22);
    padding:34px 40px 38px;}
  .topline{display:flex;align-items:center;gap:14px;}
  .dot{width:12px;height:12px;border-radius:50%;background:var(--sky);
    box-shadow:0 0 12px rgba(87,201,240,0.85);}
  .eyebrow{font-weight:700;font-size:23px;letter-spacing:3.4px;text-transform:uppercase;color:var(--muted);}
  .rule{height:1px;background:rgba(96,146,255,0.30);margin:20px 0 22px;}
  .head{font-weight:900;color:var(--txt);line-height:1.04;letter-spacing:-1.6px;}
  .royal{color:var(--royal);}
  .body{font-weight:400;font-size:26px;color:var(--muted);line-height:1.35;margin-top:18px;}
  .mrow{display:flex;align-items:center;gap:16px;margin-top:26px;}
  .mlabel{font-weight:700;font-size:24px;letter-spacing:1.5px;color:var(--txt);width:96px;}
  .mpct{font-weight:900;font-size:44px;letter-spacing:-1px;color:var(--txt);width:110px;text-align:right;}
  .meter{display:flex;gap:6px;flex:1;}
  .cell{height:16px;flex:1;border-radius:4px;background:rgba(96,146,255,0.16);}
  .cell.on{background:var(--royal);box-shadow:0 0 10px rgba(30,72,255,0.5);}
"""

def card_html(pid, dur, top, inner, anim):
    return f"""<!doctype html>
<html lang="en"><head><meta charset="UTF-8"/>
<meta name="viewport" content="width=3840, height=2160"/>
<title>{pid}</title>
<script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
<style>{CSS}</style></head>
<body>
<div id="root" data-composition-id="main" data-start="0" data-width="3840" data-height="2160" data-duration="{dur:.4f}">
  <section id="{pid}-clip" class="clip" data-start="0" data-duration="{dur:.4f}" data-track-index="1">
    <div class="stage">
      <div class="panel" id="{pid}p" style="top:{top}px;">
{inner}
      </div>
    </div>
  </section>
</div>
<script>
window.__timelines = window.__timelines || {{}};
const F = {F:.10f}, DUR = {dur:.4f};
const tl = gsap.timeline({{ paused: true }});
tl.fromTo("#{pid}p", {{opacity:0, y:26}}, {{opacity:1, y:0, duration:12*F, ease:"{STEP}"}}, 0);
{anim}
tl.to("#{pid}p", {{opacity:0, y:-14, duration:14*F, ease:"{STEP}"}}, DUR-16*F);
tl.set("#{pid}p", {{opacity:0}}, DUR-0.0005);
window.__timelines["main"] = tl;
</script>
</body></html>
"""

def stamp(sel, t, frm='{opacity:0, y:10}', to='{opacity:1, y:0}'):
    # immediateRender (default true) applies the from-pose at build time,
    # so stamped children stay hidden until their entrance.
    return (f'tl.fromTo("{sel}", {frm}, {{...{to}, duration:8*F, ease:"{STEP}"}}, {t}*F);\n')

parts_meta = []
comps = {}

# ---- g1 · hook label card -------------------------------------------------
d1 = PARTS[0][2] - PARTS[0][1]
inner = """      <div class="topline" id="g1a"><span class="dot"></span><span class="eyebrow">My Sales Process</span></div>
      <div class="rule" id="g1r"></div>
      <div class="head" id="g1h" style="font-size:62px;">5 Stages &rarr; More <span class="royal">Clients</span></div>"""
anim = (stamp("#g1a", 10) + stamp("#g1r", 16, '{opacity:0}', '{opacity:1}') + stamp("#g1h", 20))
comps["g1"] = card_html("g1", d1, 150, inner, anim)

# ---- g2 · stage 01 label card --------------------------------------------
d2 = PARTS[1][2] - PARTS[1][1]
inner = """      <div class="topline" id="g2a"><span class="dot"></span><span class="eyebrow">Stage 01</span></div>
      <div class="rule" id="g2r"></div>
      <div class="head royal" id="g2h" style="font-size:76px;">Decipher</div>
      <div class="body" id="g2b">make them say the problem out loud</div>"""
anim = (stamp("#g2a", 10) + stamp("#g2r", 14, '{opacity:0}', '{opacity:1}') +
        stamp("#g2h", 18) + stamp("#g2b", 26))
comps["g2"] = card_html("g2", d2, 150, inner, anim)

# ---- g3 · 20/80 meter card ------------------------------------------------
d3 = PARTS[2][2] - PARTS[2][1]
cells_you  = ''.join(f'<div class="cell" id="g3y{i}"></div>' for i in range(10))
cells_them = ''.join(f'<div class="cell" id="g3t{i}"></div>' for i in range(10))
inner = f"""      <div class="topline" id="g3a"><span class="dot"></span><span class="eyebrow">On the Call</span></div>
      <div class="rule" id="g3r"></div>
      <div class="mrow" id="g3row1"><span class="mlabel">YOU</span><span class="meter">{cells_you}</span><span class="mpct">20%</span></div>
      <div class="mrow" id="g3row2"><span class="mlabel">THEM</span><span class="meter">{cells_them}</span><span class="mpct">80%</span></div>"""
anim = stamp("#g3a", 10) + stamp("#g3r", 14, '{opacity:0}', '{opacity:1}')
anim += stamp("#g3row1", 18)
ON = '{backgroundColor:"#1e48ff", boxShadow:"0 0 10px rgba(30,72,255,0.5)"}'
for i in range(2):   # YOU fills 2 cells, discrete sets on the 6-frame grid
    anim += f'tl.set("#g3y{i}", {ON}, {30+i*6}*F);\n'
anim += stamp("#g3row2", 44)
for i in range(8):   # THEM fills 8 cells
    anim += f'tl.set("#g3t{i}", {ON}, {56+i*6}*F);\n'
comps["g3"] = card_html("g3", d3, 150, inner, anim)

# ---- g4 · stage 02 label card --------------------------------------------
d4 = PARTS[3][2] - PARTS[3][1]
inner = """      <div class="topline" id="g4a"><span class="dot"></span><span class="eyebrow">Stage 02</span></div>
      <div class="rule" id="g4r"></div>
      <div class="head royal" id="g4h" style="font-size:76px;">The Offer</div>
      <div class="body" id="g4b">their words &rarr; something they&rsquo;d buy</div>"""
anim = (stamp("#g4a", 10) + stamp("#g4r", 14, '{opacity:0}', '{opacity:1}') +
        stamp("#g4h", 18) + stamp("#g4b", 26))
comps["g4"] = card_html("g4", d4, 150, inner, anim)

# ---- write ---------------------------------------------------------------
os.makedirs(os.path.join(HERE, "compositions"), exist_ok=True)
for pid, start, end in PARTS:
    path = os.path.join(HERE, "compositions", f"{pid}.html")
    with open(path, "w") as f:
        f.write(comps[pid])
    parts_meta.append({"id": pid, "window": [start, end], "kind": "overlay",
                       "comp": f"compositions/{pid}.html",
                       "clip": f"renders/parts/{pid}.mov",
                       "sha": hashlib.sha256(comps[pid].encode()).hexdigest()[:12]})
with open(os.path.join(HERE, "parts.json"), "w") as f:
    json.dump({"job": "five-stage-client-process", "fps": "60000/1001",
               "base": "../outputs/five-stage-client-process.mp4",
               "parts": parts_meta}, f, indent=1)
print(f"[build] wrote {len(PARTS)} comps + parts.json")
