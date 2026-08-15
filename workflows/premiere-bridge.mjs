// Headless CLI driver for the Premiere MCP bridge — calls tool handlers directly,
// no MCP session needed. Works from any session as long as the MCP Bridge (CEP)
// panel is running in Premiere (Window > Extensions > MCP Bridge (CEP), temp dir
// /tmp/premiere-mcp-bridge on macOS, %TEMP%\premiere-mcp-bridge on Windows).
//
// Engine: vendor/premiere-mcp — our pinned local clone of
// github.com/hetpatel-11/Adobe_Premiere_Pro_MCP (the original project; the old
// premiere-pro-mcp npm package was a knockoff republish with a broken CEP shim).
// Pinned by clone: update ONLY via deliberate `git pull` + re-test, record the
// new commit hash in the premiere-pro skill.
//
// Usage:
//   node workflows/premiere-bridge.mjs --list [filter]        # list tools
//   node workflows/premiere-bridge.mjs --desc <tool>          # show a tool's params
//   node workflows/premiere-bridge.mjs <tool> ['<json-args>'] # call one tool
//   node workflows/premiere-bridge.mjs replay <cuts.json> <clipName>
//     # premiere-pro step 7: replay the EDL onto V1 of the ACTIVE sequence as
//     # individual overwrite edits via one batched ExtendScript (per-segment
//     # in/out + overwriteClip with position read-back — the your-job
//     # pattern; append position is read back after every overwrite because
//     # Premiere quantizes boundaries to the frame grid).
//   node workflows/premiere-bridge.mjs frame '{"time":17.0,"out":"/abs/path-no-ext"}'
//     # Program-monitor-accurate frame grab from the ACTIVE sequence at `time` seconds —
//     # full render: keyframed effects + all video tracks/alpha overlays composited.
//     # Calls QE exportFramePNG with a proper NON-DROP TIMECODE STRING built from the
//     # sequence fps. That arg form is the ONLY correct one: numeric seconds THROW
//     # ("Illegal Parameter type") and the vendored export_frame tool's fallback passes
//     # String(seconds), which QE parses as a FRAMES timecode — it silently exports the
//     # frame at ~t/fps seconds (measured 2026-07-18: "18" → frame 18 ≈ 0.75s). A ticks
//     # string is equally wrong. Writes <out>.png and prints the timecode used.
//   node workflows/premiere-bridge.mjs diff-edl <cuts.json> [more cuts.json...]
//     # The rough-cut learning loop (skill Step 5): diff the ACTIVE sequence's
//     # V1 against the authored EDL(s) after the creator hand-edits. Matches
//     # timeline clips to EDL segments by source-range overlap (clips matched to
//     # EDLs by clip filename), then prints: deleted segments (with their
//     # transcript), boundary moves > 1 frame with the WORDS around each moved
//     # boundary (needs <job>/transcript/words.json next to each cuts.json),
//     # graft pairs (OUT-extension + IN-trim at one joint), new material, and
//     # timeline gaps. Read-only; never writes. The hand-edited timeline is the
//     # source of truth — this command exists to LEARN from it, not to sync it.
//   node workflows/premiere-bridge.mjs zoom ['<json-opts>']
//     # Opening zoom preset (locked 2026-07-17): applies Transform (with
//     # Shutter Angle 360 motion blur) to a clip on V1 of the active sequence and
//     # bakes a per-frame scale ramp — the only way to script ease shapes, since
//     # Premiere's ease presets aren't reachable via the API. Defaults reproduce
//     # the approved look; all keys land at the clip's in point (source-time domain).
//     # Opts: {"clip":0,"from":130,"to":100,"frames":8,"ease":"cubic"}
//     #   clip: 0-based clip index on V1 · ease: cubic | overshoot | linear
import { readFileSync } from "node:fs";

// Bridge dir must match the CEP panel's default: /tmp on macOS, %TEMP% on Windows.
// (URL.href, not .pathname, for the imports — pathname yields /C:/... on Windows.)
const { tmpdir } = await import("node:os");
process.env.PREMIERE_TEMP_DIR = process.env.PREMIERE_TEMP_DIR ||
  (process.platform === "win32" ? `${tmpdir()}\\premiere-mcp-bridge` : "/tmp/premiere-mcp-bridge");
const V = new URL("../vendor/premiere-mcp/", import.meta.url);
const { PremiereProBridge } = await import(new URL("dist/bridge/index.js", V).href);
const { PremiereProTools } = await import(new URL("dist/tools/index.js", V).href);

const bridge = new PremiereProBridge();
await bridge.initialize();
const tools = new PremiereProTools(bridge);

const call = async (name, args = {}) => {
  const r = await tools.executeTool(name, args);
  if (r && r.success === false) throw new Error(`${name} failed: ${r.error}`);
  return r && r.data !== undefined ? r.data : r;
};
const es = async (code) => call("execute_extendscript", { script: code });

const [cmd, a1, a2] = process.argv.slice(2);

if (!cmd || cmd === "--list") {
  const filter = a1?.toLowerCase();
  console.log(tools.getAvailableTools().map(t => t.name)
    .filter(n => !filter || n.includes(filter)).join("\n"));
} else if (cmd === "--desc") {
  const t = tools.getAvailableTools().find(x => x.name === a1);
  console.log(JSON.stringify({ description: t?.description, parameters: t?.inputSchema }, null, 2));
} else if (cmd === "replay") {
  const segs = JSON.parse(readFileSync(a1, "utf-8")).segments;
  // +1e-4s on every boundary: frame-grid times are repeating decimals, and a double
  // that lands a hair BELOW the exact tick value gets FLOORED by Premiere into the
  // previous frame (measured: one out-point a full frame short). The nudge is 0.24%
  // of a frame — floor now always resolves to the intended frame, and off-grid EDLs
  // are unaffected.
  const segJson = JSON.stringify(segs.map(s => [s.start + 1e-4, s.end + 1e-4]));
  const r = await es(`
(function(){
var SEGS = ${segJson};
var NAME = ${JSON.stringify(a2)};
var item = null;
function find(bin){
  for (var i = 0; i < bin.children.numItems; i++) {
    var c = bin.children[i];
    if (c.name === NAME) return c;
    if (c.type === ProjectItemType.BIN) { var f = find(c); if (f) return f; }
  }
  return null;
}
item = find(app.project.rootItem);
if (!item) return "ERROR: project item not found: " + NAME;
var seq = app.project.activeSequence;
if (!seq) return "ERROR: no active sequence";
var vt = seq.videoTracks[0];
var pos = vt.clips.numItems ? vt.clips[vt.clips.numItems - 1].end.seconds : 0;
for (var s = 0; s < SEGS.length; s++) {
  item.setInPoint(SEGS[s][0], 4);
  item.setOutPoint(SEGS[s][1], 4);
  vt.overwriteClip(item, pos);
  pos = vt.clips[vt.clips.numItems - 1].end.seconds;
}
item.clearInPoint(4);
item.clearOutPoint(4);
return "laid " + SEGS.length + " segments, timeline ends " + pos.toFixed(3) + "s";
})()
`);
  console.log(JSON.stringify(r));
  console.log(JSON.stringify(await call("save_project")));
} else if (cmd === "diff-edl") {
  const { dirname, basename, join } = await import("node:path");
  const edlPaths = process.argv.slice(3);
  if (!edlPaths.length) throw new Error("diff-edl needs at least one cuts.json path");

  // segments from every EDL, keyed by clip basename; word lists for boundary context
  const segs = [];
  const wordsByClip = {};
  for (const p of edlPaths) {
    for (const [i, s] of JSON.parse(readFileSync(p, "utf-8")).segments.entries())
      segs.push({ edl: basename(dirname(dirname(p))) || p, i, clip: basename(s.clip), ...s, used: false });
    // transcript/words.json sits next to transcript/cuts.json
    try {
      const w = JSON.parse(readFileSync(join(dirname(p), "words.json"), "utf-8"));
      for (const c of w.clips || []) wordsByClip[basename(c.clip)] = c.words || [];
    } catch { /* words optional — boundary context just goes quiet */ }
  }
  const wordsAt = (clip, t) => {
    const ws = wordsByClip[clip];
    if (!ws) return "";
    const near = ws.filter(w => w.end > t - 0.8 && w.start < t + 0.8).map(w => w.w).join(" ");
    return near ? `  [“${near}”]` : "";
  };

  const dump = await es(`
(function(){
var s = app.project.activeSequence;
if (!s) return "ERROR: no active sequence";
var fps = 1 / s.getSettings().videoFrameRate.seconds;
var v = [];
for (var t = 0; t < s.videoTracks.numTracks; t++) {
  var vt = s.videoTracks[t];
  for (var i = 0; i < vt.clips.numItems; i++) {
    var c = vt.clips[i];
    v.push({ trk: t, name: c.name,
      tlIn: c.start.seconds, tlOut: c.end.seconds,
      srcIn: c.inPoint.seconds, srcOut: c.outPoint.seconds });
  }
}
return JSON.stringify({ fps: fps, clips: v });
})()`);
  const tl = JSON.parse(typeof dump === "string" ? dump : dump.result || JSON.stringify(dump));
  if (tl.ERROR) throw new Error(tl.ERROR);
  const FRAME = 1 / (tl.fps || 30);
  const fmt = (x) => x.toFixed(2);

  const lines = [];
  let grafts = 0, moves = 0;
  const clipRows = [];
  for (const c of tl.clips) {
    let best = null, bo = 0;
    for (const s of segs) {
      if (c.name !== s.clip) continue;
      const o = Math.min(c.srcOut, s.end) - Math.max(c.srcIn, s.start);
      if (o > bo) { bo = o; best = s; }
    }
    if (!best) { lines.push(`NEW      ${c.name} src ${fmt(c.srcIn)}-${fmt(c.srcOut)} — not from any EDL segment`); continue; }
    best.used = true;
    clipRows.push({ c, s: best, dIn: c.srcIn - best.start, dOut: c.srcOut - best.end });
  }
  for (let k = 0; k < clipRows.length; k++) {
    const { c, s, dIn, dOut } = clipRows[k];
    if (Math.abs(dIn) > FRAME) {
      moves++;
      lines.push(`IN  ${dIn > 0 ? "trimmed " : "extended"} ${Math.abs(dIn).toFixed(2)}s  ${s.edl}#${s.i} @src ${fmt(s.start)}→${fmt(c.srcIn)}${wordsAt(c.name, c.srcIn)}`);
    }
    if (Math.abs(dOut) > FRAME) {
      moves++;
      lines.push(`OUT ${dOut > 0 ? "extended" : "trimmed "} ${Math.abs(dOut).toFixed(2)}s  ${s.edl}#${s.i} @src ${fmt(s.end)}→${fmt(c.srcOut)}${wordsAt(c.name, c.srcOut)}`);
    }
    // graft signature: this clip's OUT extended into words + next clip's IN trimmed past its start
    const nxt = clipRows[k + 1];
    if (nxt && dOut > FRAME && nxt.dIn > FRAME) {
      grafts++;
      lines.push(`  ↳ GRAFT at joint: kept take-1 through ${fmt(c.srcOut)}, re-entered take 2 at ${fmt(nxt.c.srcIn)} — mid-sentence splice around a restart`);
    }
  }
  for (const s of segs.filter(x => !x.used))
    lines.push(`DELETED  ${s.edl}#${s.i} ${fmt(s.start)}-${fmt(s.end)}  “${(s.transcript || "").slice(0, 90)}”`);
  const v1 = tl.clips.filter(c => c.trk === 0);
  for (let k = 1; k < v1.length; k++) {
    const g = v1[k].tlIn - v1[k - 1].tlOut;
    if (Math.abs(g) > 0.001) lines.push(`GAP      ${g > 0 ? "+" : ""}${g.toFixed(3)}s on the timeline at ${fmt(v1[k - 1].tlOut)}`);
  }
  console.log(lines.length ? lines.join("\n") : "timeline matches the EDL(s) exactly — no hand edits detected");
  console.log(`— ${tl.clips.length} timeline clips vs ${segs.length} EDL segments · ${segs.filter(x => !x.used).length} deleted · ${moves} boundary moves · ${grafts} graft(s) · end ${fmt(v1.length ? v1[v1.length - 1].tlOut : 0)}s`);
} else if (cmd === "frame") {
  const opts = JSON.parse(a1);
  if (!(opts.time >= 0) || !opts.out) throw new Error('frame needs {"time":<seconds>,"out":"/abs/path-no-ext"}');
  const r = await es(`
(function(){
var seq = app.project.activeSequence;
if (!seq) return "ERROR: no active sequence";
var frameDur = seq.getSettings().videoFrameRate.seconds;
var nominal = Math.round(1 / frameDur);
var f = Math.round(${opts.time} / frameDur);
var ff = f % nominal, s = (f - ff) / nominal;
var ss = s % 60, mm = ((s - ss) / 60) % 60, hh = Math.floor(s / 3600);
function p(n){ return (n < 10 ? "0" : "") + n; }
var tc = p(hh) + ":" + p(mm) + ":" + p(ss) + ":" + p(ff);
app.enableQE();
var qs = qe.project.getActiveSequence();
if (!qs) return "ERROR: no QE sequence";
qs.exportFramePNG(tc, ${JSON.stringify(opts.out)});
return "exported " + seq.name + " @ " + tc + " (frame " + f + ") -> " + ${JSON.stringify(opts.out)} + ".png";
})()
`);
  console.log(JSON.stringify(r));
} else if (cmd === "zoom") {
  const opts = { clip: 0, from: 130, to: 100, frames: 8, ease: "cubic", ...(a1 ? JSON.parse(a1) : {}) };
  const EASE = {
    linear: t => t,
    cubic: t => 1 - Math.pow(1 - t, 3),
    overshoot: t => { const s = 1.70158; return 1 + (s + 1) * Math.pow(t - 1, 3) + s * Math.pow(t - 1, 2); },
  };
  const fn = EASE[opts.ease];
  if (!fn) throw new Error(`unknown ease: ${opts.ease} (use ${Object.keys(EASE).join("/")})`);
  const vals = [];
  for (let f = 0; f <= opts.frames; f++) vals.push(opts.from + (opts.to - opts.from) * fn(f / opts.frames));
  const r = await es(`
(function(){
var TRACK = 0, CLIP = ${opts.clip}, VALS = ${JSON.stringify(vals)};
var frameDur = 1001 / 24000;
var seq = app.project.activeSequence;
if (!seq) return "ERROR: no active sequence";
var clip = seq.videoTracks[TRACK].clips[CLIP];
if (!clip) return "ERROR: no clip " + CLIP + " on V" + (TRACK + 1);
var hasTransform = false;
for (var i = 0; i < clip.components.numItems; i++) {
  if (clip.components[i].displayName === "Transform") hasTransform = true;
}
if (!hasTransform) {
  app.enableQE();
  var qtrack = qe.project.getActiveSequence().getVideoTrackAt(TRACK);
  var nth = -1;
  for (var q = 0; q < qtrack.numItems; q++) {
    var it = qtrack.getItemAt(q);
    if (it && it.type === "Clip") {
      nth++;
      if (nth === CLIP) { it.addVideoEffect(qe.project.getVideoEffectByName("Transform")); break; }
    }
  }
  clip = seq.videoTracks[TRACK].clips[CLIP];
}
var inPt = clip.inPoint.seconds;
var baked = 0;
for (var i = 0; i < clip.components.numItems; i++) {
  var comp = clip.components[i];
  if (comp.displayName !== "Transform") continue;
  for (var p = 0; p < comp.properties.numItems; p++) {
    var prop = comp.properties[p];
    var dn = prop.displayName;
    if (dn === "Scale Height" || dn === "Scale Width") {
      var keys = prop.getKeys();
      if (keys) { for (var k = keys.length - 1; k >= 0; k--) prop.removeKey(keys[k], 1); }
      if (!prop.isTimeVarying()) prop.setTimeVarying(true);
      for (var f = 0; f < VALS.length; f++) {
        var kt = inPt + f * frameDur;
        prop.addKey(kt);
        prop.setValueAtKey(kt, VALS[f], 1);
      }
      var check = prop.getKeys();
      for (var c = 0; c < check.length; c++) { try { prop.setInterpolationTypeAtKey(check[c], 0, 1); } catch (e) {} }
      baked++;
    } else if (dn === "Shutter Angle") {
      prop.setValue(360, 1);
    }
  }
}
if (baked !== 2) return "ERROR: baked " + baked + " scale props, expected 2";
return "zoom baked: clip " + CLIP + ", " + VALS.length + " keys/prop, first key " + inPt.toFixed(4) + "s";
})()
`);
  console.log(JSON.stringify(r));
  console.log(JSON.stringify(await call("save_project")));
} else {
  const t = tools.getAvailableTools().find(x => x.name === cmd);
  if (!t) { console.error(`Unknown tool: ${cmd}`); process.exit(1); }
  console.log(JSON.stringify(await tools.executeTool(cmd, a1 ? JSON.parse(a1) : {}), null, 2));
}
process.exit(0);
