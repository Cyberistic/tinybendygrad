#!/usr/bin/env python3
"""Render the coverage browser: every line of tinygrad, green where explained.

    python3 tools/coverage/build.py

One self-contained page under content/coverage/. The source text and the
attribution are inlined, so it opens from disk with no server and no build step.
A green line is a line a claim names; clicking it shows the claim, and links to
the lesson if that lesson has been built.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CONTENT = ROOT / "content"
SKIP = ("autogen", "viz/assets", "/assets/", "__pycache__")


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--tree", default=str(HERE.parents[4] / "references" / "tinygrad-latest"))
  ap.add_argument("--out", default=str(CONTENT / "coverage"))
  args = ap.parse_args()

  coverage = json.loads((CONTENT / "coverage.json").read_text())
  tree = pathlib.Path(args.tree).resolve()
  players = {p.name for p in (CONTENT / "player").iterdir()} if (CONTENT / "player").exists() else set()

  files = {}
  for path in sorted((tree / "tinygrad").rglob("*.py")):
    rel = path.relative_to(tree).as_posix()
    if any(s in rel for s in SKIP):
      continue
    text = path.read_text().splitlines()
    files[rel] = {"lines": text, "covered": coverage["files"].get(rel, {})}

  payload = {"files": files, "lessons": coverage["lessons"], "totals": coverage["totals"],
             "players": sorted(players), "commit": coverage.get("commit")}

  out = pathlib.Path(args.out)
  out.mkdir(parents=True, exist_ok=True)
  (out / "index.html").write_text(HTML.replace("__DATA__", json.dumps(payload)))
  covered = coverage["totals"]["covered"]
  print(f"{covered} covered lines · {len(files)} files · {len(coverage['lessons'])} lessons")
  print(f"wrote {(out / 'index.html').relative_to(ROOT)}")
  return 0


HTML = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>30klinesofcode — coverage</title>
<style>
:root{--paper:#F4F2ED;--paper2:#EDEAE2;--ink:#16161A;--ink2:#2A2A30;--muted:#6E6A63;--faint:#9A958C;
--rule:#D6D1C7;--rule2:#BDB7A9;--accent:#3DA639;--accentInk:#1F6B22;--wash:#E4EFD9}
*{box-sizing:border-box;margin:0}
body{background:var(--paper);color:var(--ink);font:12px/1.5 ui-monospace,"SF Mono",Menlo,monospace;
-webkit-font-smoothing:antialiased;height:100vh;display:flex;flex-direction:column;overflow:hidden}
.top{display:flex;justify-content:space-between;align-items:center;height:44px;padding:0 22px;border-bottom:1px solid var(--rule);flex:0 0 auto}
.brand{font-size:13px}.brand span{color:var(--faint);font-size:11px}
.top .r{display:flex;gap:18px;font-size:10.5px;color:var(--muted)}
.top b{color:var(--ink);font-weight:500}
.sig{width:7px;height:7px;background:var(--accent);display:inline-block;margin-right:6px}
main{display:grid;grid-template-columns:330px 1fr;grid-template-rows:1fr;flex:1;min-height:0}
aside{border-right:1px solid var(--rule);overflow:auto;padding:8px 0}
.f{padding:5px 14px;cursor:pointer;display:grid;grid-template-columns:1fr auto;gap:6px;font-size:10.5px;color:var(--muted)}
.f:hover{background:var(--paper2)}
.f.on{background:var(--paper2);color:var(--ink);box-shadow:inset 2px 0 0 var(--accent)}
.f .p{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.f .c{color:var(--faint);font-variant-numeric:tabular-nums}
.f.has .p{color:var(--ink)}
.f.has .c{color:var(--accentInk)}
.bar{grid-column:1/-1;height:2px;background:var(--rule);position:relative}
.bar i{position:absolute;left:0;top:0;bottom:0;background:var(--accent)}
section{display:flex;flex-direction:column;min-width:0;min-height:0}
.fh{display:flex;justify-content:space-between;padding:8px 16px;border-bottom:1px solid var(--rule);
font-size:10px;color:var(--muted);flex:0 0 auto}
.code{overflow:auto;flex:1;min-height:0;font-size:11.5px;line-height:1.72;padding-bottom:40px}
.row{display:grid;grid-template-columns:52px 1fr;align-items:start;padding-right:16px;white-space:pre-wrap;overflow-wrap:anywhere}
.row .ln{color:var(--faint);text-align:right;padding-right:14px;font-size:10px;user-select:none}
.row .ct{color:var(--ink2)}
.row.cov{background:var(--wash);box-shadow:inset 2px 0 0 var(--accent);cursor:pointer}
.row.cov .ln{color:var(--accentInk)}
.row.cov:hover{background:#D8EAC8}
.row.sel{outline:1px solid var(--accent);outline-offset:-1px;background:#D8EAC8}
#panel{position:fixed;right:0;bottom:0;width:430px;max-height:60vh;overflow:auto;background:var(--paper);
border:1px solid var(--rule2);border-right:0;border-bottom:0;padding:14px 16px;display:none}
#panel.on{display:block}
#panel h3{font-size:10px;letter-spacing:.14em;text-transform:uppercase;color:var(--faint);font-weight:400;margin-bottom:8px}
#panel .c{border-top:1px solid var(--rule);padding:8px 0}
#panel .c:first-of-type{border-top:0}
#panel .k{font-size:9px;text-transform:uppercase;letter-spacing:.1em;color:var(--accent);margin-right:6px}
#panel .t{font:13px/1.55 -apple-system,sans-serif;color:var(--ink2)}
#panel a{display:inline-block;margin-top:10px;color:var(--accentInk);font-size:10.5px;border-bottom:1px solid var(--accent)}
#panel .x{position:absolute;right:12px;top:10px;cursor:pointer;color:var(--faint)}
</style></head><body>
<div class="top">
  <div class="brand">30klinesofcode <span>· coverage</span></div>
  <div class="r"><span><span class="sig"></span><b id="cov"></b> covered</span><span id="files"></span><span id="pin"></span></div>
</div>
<main>
  <aside id="list"></aside>
  <section>
    <div class="fh"><span id="path"></span><span id="count"></span></div>
    <div class="code" id="code"></div>
  </section>
</main>
<div id="panel"><span class="x" onclick="closePanel()">×</span><div class="body"></div></div>
<script>
const D = __DATA__;
const el = (t,c,x)=>{const n=document.createElement(t); if(c)n.className=c; if(x!==undefined)n.textContent=x; return n};
const order = Object.keys(D.files).sort((a,b)=>{
  const ca=Object.keys(D.files[a].covered).length, cb=Object.keys(D.files[b].covered).length;
  return cb-ca || a.localeCompare(b);
});
document.getElementById('cov').textContent = D.totals.covered.toLocaleString();
document.getElementById('files').textContent = D.totals.files_touched + ' / ' + Object.keys(D.files).length + ' files';
document.getElementById('pin').textContent = (D.commit||'').slice(0,8);

let current = order[0];
const list = document.getElementById('list');
for (const path of order) {
  const cov = Object.keys(D.files[path].covered).length;
  const n = D.files[path].lines.length;
  const row = el('div', 'f' + (cov ? ' has' : ''));
  row.dataset.path = path;
  row.append(el('span','p',path.replace('tinygrad/','')), el('span','c', cov ? `${cov}` : ''));
  const bar = el('div','bar'); const fill = el('i'); fill.style.width = (100*cov/n).toFixed(1)+'%';
  bar.append(fill); row.append(bar);
  row.onclick = () => show(path);
  list.append(row);
}

function show(path) {
  current = path;
  for (const r of list.children) r.classList.toggle('on', r.dataset.path === path);
  const f = D.files[path];
  document.getElementById('path').textContent = path;
  document.getElementById('count').textContent = Object.keys(f.covered).length + ' covered of ' + f.lines.length;
  const code = document.getElementById('code');
  code.innerHTML = '';
  const frag = document.createDocumentFragment();
  f.lines.forEach((text, i) => {
    const n = i + 1;
    const users = f.covered[n];
    const row = el('div', 'row' + (users ? ' cov' : ''));
    row.append(el('span','ln',String(n)), el('span','ct', text || ' '));
    if (users) { row.dataset.line = n; row.onclick = () => openClaim(n, users); }
    frag.append(row);
  });
  code.append(frag);
  code.scrollTop = 0;
}

function openClaim(line, ids) {
  const panel = document.getElementById('panel');
  const body = panel.querySelector('.body');
  body.innerHTML = '';
  body.append(el('h3', null, `${current}:${line} — ${ids.length} claim${ids.length>1?'s':''}`));
  for (const lid of ids) {
    const L = D.lessons[lid];
    for (const c of L.claims.filter(c => c.file === current && c.lines.includes(line))) {
      const box = el('div','c');
      const head = el('div');
      head.append(el('span','k', c.kind), el('span', null, `${lid} · ${L.title}`));
      box.append(head, el('div','t', c.text));
      if (D.players.includes(lid)) {
        const a = el('a', null, 'open lesson →'); a.href = `../player/${lid}/index.html`;
        box.append(a);
      }
      body.append(box);
    }
  }
  panel.classList.add('on');
  const row = document.querySelector(`.row[data-line="${line}"]`);
  if (row) {
    document.querySelectorAll('.row.sel').forEach(r => r.classList.remove('sel'));
    row.classList.add('sel');
    // scroll the code pane only: scrollIntoView moves the whole body, which is
    // not scrollable by design and lands on blank paper
    // after the next frame: at call time the freshly appended rows have no
    // scrollable height yet, and the assignment is silently clamped to 0
    requestAnimationFrame(() => {
      const pane = document.getElementById('code');
      const r = row.getBoundingClientRect(), pr = pane.getBoundingClientRect();
      pane.scrollTop += (r.top - pr.top) - pane.clientHeight / 2 + r.height / 2;
    });
  }
}
function closePanel(){ document.getElementById('panel').classList.remove('on') }

addEventListener('keydown', (e) => {
  if (e.key === 'Escape') return closePanel();
  if (e.key !== 'j' && e.key !== 'k') return;
  const i = order.indexOf(current) + (e.key === 'j' ? 1 : -1);
  if (i >= 0 && i < order.length) show(order[i]);
});

// #tinygrad/uop/ops.py:184 opens a file at a line, so a claim can be linked to
const hash = decodeURIComponent(location.hash.slice(1));
if (hash.includes(':')) {
  const [p, line] = hash.split(':');
  if (D.files[p]) { show(p); const n = Number(line); const users = D.files[p].covered[n]; if (users) openClaim(n, users); }
} else if (D.files[hash]) show(hash);
else show(current);
</script></body></html>
"""

if __name__ == "__main__":
  sys.exit(main())
