#!/usr/bin/env python3
"""Build a self-contained lesson player: one lesson, its timeline, its audio.

    python3 tools/player/build.py 02.4

Writes content/player/<id>/{index.html, app.js, data.json, *.m4a}. The page
imports the real track.ts through a bun bundle, so the timing logic in the
player is the same code the tests cover — not a second implementation that can
drift.

The source pane is cut from the vendored tree at build time, which is why a
lesson cannot show a line that is not there.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent          # .agents/slop/30klines
CONTENT = ROOT / "content"
LESSONS = CONTENT / "lessons"
VOICE = CONTENT / "voice"
OUT = CONTENT / "player"
CANDIDATES = [("draft-timeline.json", "draft"), ("timeline.json", "")]


def timeline_for(lid: str) -> tuple[dict, pathlib.Path]:
  for name, audio in CANDIDATES:
    p = VOICE / lid / name
    if p.exists():
      return json.loads(p.read_text()), (p.parent / audio if audio else p.parent)
  raise SystemExit(f"no timeline for {lid}: run draft.py or sync.py first")


def source_lines(tree: pathlib.Path, ref: dict) -> list[str]:
  path = tree / ref["file"]
  raw = path.read_text().splitlines()
  return raw[ref["start"] - 1:ref["end"]]


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("lesson", nargs="?", default="02.4")
  ap.add_argument("--tree", default=str(ROOT.parent.parent.parent / "references" / "tinygrad-latest"))
  args = ap.parse_args()

  lesson = json.loads((LESSONS / f"{args.lesson}.json").read_text())
  timeline, audio_dir = timeline_for(args.lesson)
  tree = pathlib.Path(args.tree).resolve()
  out = OUT / args.lesson
  out.mkdir(parents=True, exist_ok=True)

  refs = [{**r, "lines": source_lines(tree, r)} for r in lesson["refs"]]

  clips = []
  for beat in lesson["beats"]:
    src = next((p for p in audio_dir.glob(f"{beat['id']}.*")
                if p.suffix in {".m4a", ".wav", ".webm", ".mp3", ".aac"}), None)
    if src:
      shutil.copy2(src, out / src.name)
      clips.append({"id": beat["id"], "src": src.name})

  (out / "data.json").write_text(json.dumps({
    "lesson": {**lesson, "refs": refs},
    "timeline": timeline,
    "clips": clips,
  }, indent=2) + "\n")

  shutil.copy2(HERE / "app.ts", out / "app.ts")
  build = subprocess.run(["bun", "build", "app.ts", "--outfile", "app.js", "--target", "browser"],
                         cwd=out, capture_output=True, text=True)
  if build.returncode != 0:
    print(build.stderr, file=sys.stderr)
    return build.returncode

  (out / "index.html").write_text(HTML.replace("__TITLE__", f"{lesson['id']} — {lesson['title']}"))
  print(f"{out}/index.html  ({len(clips)} clips, {len(refs)} refs, "
        f"{sum(len(r['lines']) for r in refs)} source lines)")
  return 0


HTML = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>__TITLE__</title>
<style>
:root{--paper:#F4F2ED;--paper2:#EDEAE2;--ink:#16161A;--ink2:#3C3C42;--muted:#6E6A63;--faint:#9A958C;
--rule:#D6D1C7;--rule2:#BDB7A9;--accent:#3DA639;--wash:#E4EFD9}
*{box-sizing:border-box;margin:0}
body{background:var(--paper);color:var(--ink);font:12px/1.5 ui-monospace,"SF Mono",Menlo,monospace;
-webkit-font-smoothing:antialiased;font-variant-numeric:tabular-nums;height:100vh;display:flex;flex-direction:column}
.top{display:flex;justify-content:space-between;align-items:center;height:44px;padding:0 24px;border-bottom:1px solid var(--rule);flex:0 0 auto}
.brand{font-size:13px}.brand span{color:var(--faint);font-size:11px}
.top .r{display:flex;gap:16px;align-items:center;font-size:10.5px;color:var(--muted)}
.sig{width:7px;height:7px;background:var(--accent);display:inline-block;margin-right:6px}
.body{display:grid;grid-template-columns:1fr 380px;flex:1;min-height:0}
.left{overflow:auto;padding:0}
.ref{border-bottom:1px solid var(--rule)}
.refhead{display:flex;justify-content:space-between;padding:8px 16px;border-bottom:1px solid var(--rule);
font-size:10px;color:var(--muted);position:sticky;top:0;background:var(--paper);z-index:2}
.range{color:var(--faint)}
.code{padding:8px 0 12px;font-size:11.5px;line-height:1.75}
.row{display:grid;grid-template-columns:46px 1fr;align-items:start;padding-right:16px;white-space:pre-wrap;overflow-wrap:anywhere}
.row .ln{color:var(--faint);text-align:right;padding-right:14px;font-size:10px;user-select:none}
.row .ct{color:#2A2A30}
.row.on{background:var(--wash);box-shadow:inset 2px 0 0 var(--accent)}
.row.on .ct{color:var(--ink)}.row.on .ln{color:#1F6B22}
.right{border-left:1px solid var(--rule);display:flex;flex-direction:column;min-height:0}
.claimbox{padding:16px 20px;border-bottom:1px solid var(--rule);min-height:150px}
.sum{font:11px/1.55 -apple-system,sans-serif;color:var(--faint);margin-bottom:12px}
.k{font-size:9.5px;letter-spacing:.14em;text-transform:uppercase;color:var(--faint)}
#claim p{font:13.5px/1.6 -apple-system,sans-serif;color:var(--ink2);margin-top:8px}
#claim b{font:9px ui-monospace,monospace;text-transform:uppercase;letter-spacing:.1em;color:var(--accent);margin-right:6px}
.said{padding:14px 20px;border-bottom:1px solid var(--rule)}
#said{font:13px/1.65 -apple-system,sans-serif;color:var(--muted);margin-top:6px;font-style:italic}
.beats{flex:1;overflow:auto}
.beat{display:grid;grid-template-columns:34px 1fr;gap:10px;width:100%;text-align:left;background:none;border:0;
border-bottom:1px solid var(--rule);padding:9px 16px;font:10.5px ui-monospace,monospace;color:var(--muted);cursor:pointer}
.beat .bi{color:var(--faint)}
.beat.cur{background:var(--paper2);color:var(--ink);box-shadow:inset 2px 0 0 var(--accent)}
.bar{display:flex;align-items:center;gap:12px;padding:10px 20px;border-top:1px solid var(--rule);flex:0 0 auto}
button.ctl{background:none;border:1px solid var(--rule2);color:var(--ink);font:11px ui-monospace,monospace;padding:4px 10px;cursor:pointer}
button.ctl:hover{border-color:var(--ink)}
#progress{flex:1;accent-color:#3DA639}
#beatno{color:var(--faint);font-size:10px}
</style></head>
<body>
<div class="top">
  <div class="brand">30klinesofcode <span>· lesson player</span></div>
  <div class="r"><span><span class="sig"></span>draft voice</span><span id="title"></span><span id="id"></span></div>
</div>
<div class="body">
  <div class="left" id="sources"></div>
  <div class="right">
    <div class="claimbox"><div class="sum" id="summary"></div><div class="k">what this line does</div><div id="claim"></div></div>
    <div class="said"><div class="k">narration · <span id="tracklabel"></span></div><div id="said"></div></div>
    <div class="beats" id="beats"></div>
    <div class="bar">
      <button class="ctl" id="prev">←</button>
      <button class="ctl" id="play">▶</button>
      <button class="ctl" id="next">→</button>
      <input id="progress" type="range" min="0" max="1" step="0.001" value="0">
      <span id="beatno"></span>
    </div>
  </div>
</div>
<script src="app.js"></script>
</body></html>
"""

if __name__ == "__main__":
  sys.exit(main())
