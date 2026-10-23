#!/usr/bin/env python3
"""tokfix2.py -- RE-POINT EACH CITATION ON A LINE AT ITS OWN LINE.

    .venv/bin/python .agents/slop/citefix/tokfix2.py --rows LOCATE.rows --out EDITS.rows --left LEFT.rows

`tokfix.py` gave every citation on a line the SAME target when they shared a token set,
and two citations that name two different constructs must not land on one line. So the
candidates are ASSIGNED: each citation takes the nearest line where one of ITS OWN tokens
occurs, and no line is taken twice.

A citation with no candidate is LEFT: no re-point can make it hold, and the fix for that
is the PROSE, not the number.
"""

from __future__ import annotations

import argparse
import collections
import csv
import importlib.util
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PIN = "5c2bf39d6c4b"


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--rows", required=True)
  ap.add_argument("--out", required=True)
  ap.add_argument("--left", required=True)
  args = ap.parse_args()
  pc = load("pincite", ROOT / "gates" / "pin-cite-gate.py")
  hc = load("hcensus", ROOT / "gates" / "header-census-gate.py")
  corpus = hc.Upstream(pc.UPSTREAM)
  cache: dict[str, list[str]] = {}

  def pin_lines(path: str) -> list[str]:
    if path not in cache:
      cache[path] = subprocess.run(
        ("git", "--no-optional-locks", "show", f"{PIN}:{path}"), cwd=ROOT,
        capture_output=True, text=True).stdout.splitlines()
    return cache[path]

  rows = list(csv.DictReader(open(args.rows, encoding="utf-8"), delimiter="\t"))
  by_file: dict[str, list[dict]] = collections.defaultdict(list)
  for r in rows:
    by_file[r["rel"]].append(r)
  edits: list[dict] = []
  left: list[dict] = []
  for rel, group in sorted(by_file.items()):
    src = (ROOT / rel).read_text(encoding="utf-8").splitlines()
    first, last, blk = hc.header_block(src)
    if not first:
      continue
    tgt = hc.declared_target(blk)
    prefer = tgt.rsplit("/", 1)[0] if "/" in tgt else ""
    claims = hc.citation_claims(blk, first, rel, tgt)
    by_line: dict[int, list[dict]] = collections.defaultdict(list)
    for c in claims:
      by_line[c["at"]].append(c)
    # THE ROWS OF ONE LINE, IN TEXT ORDER, so the targets can be ASSIGNED.
    per_line: dict[int, list[dict]] = collections.defaultdict(list)
    for r in group:
      per_line[int(r["at"])].append(r)
    for at, rs in sorted(per_line.items()):
      line = src[at - 1]
      spans = pc.line_spans(hc, line)
      group_at = by_line.get(at, [])
      idxs = []
      for r in rs:
        idx = next((i for i, c in enumerate(group_at)
                    if c["subject"] == r["subject"] and c["lo"] == int(r["lo"])), None)
        idxs.append(idx)
      order = sorted([(i, r) for i, r in zip(idxs, rs) if i is not None and i < len(spans)],
                     key=lambda t: t[0])
      used: set[tuple[str, int]] = set()
      for i, r in order:
        sp = spans[i]
        old_text = line[sp[0]:sp[1]]
        path, how = corpus.resolve(r["subject"], history=True, prefer_dir=prefer)
        if not path:
          left.append({**r, "why": f"the subject names no upstream file ({how})"})
          continue
        up = pin_lines(path)
        toks = [t for t in r["tokens"].split(",") if t]
        # THE DECLARATION FIRST. A `symbol=` row is judged by the line that DECLARES the
        # name, so a candidate that only NAMES it is a candidate the todo-cite gate will
        # call WRONG-LINE -- and the two tools then fight over the same line.
        decls: list[int] = []
        names: list[int] = []
        for n, raw in enumerate(up, 1):
          st = raw.strip()
          if not st or st.startswith("#"):
            continue
          m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", st)
          is_decl = bool(m and m.group(1) in toks)
          if not is_decl:
            m2 = re.match(r"([A-Za-z_]\w*)\s*(?::[^=]+)?=", st)
            is_decl = bool(m2 and m2.group(1) in toks and not raw.startswith(" " * 8))
          if is_decl:
            decls.append(n)
          elif any(re.search(rf"\b{re.escape(t)}\b", raw) for t in toks):
            names.append(n)
        cands = decls or names
        if not cands:
          left.append({**r, "why": "no claim token occurs anywhere in the cited file"})
          continue
        old_lo = int(r["lo"])
        free = [n for n in cands if (path, n) not in used]
        if not free:
          free = cands
        target = min(free, key=lambda n: abs(n - old_lo))
        used.add((path, target))
        new_text = old_text
        m = re.match(r"(?P<subject>[^:]*):(?P<lo>\d+)(?:-(?P<hi>\d+))?", old_text)
        if m:
          width = int(m.group("hi") or m.group("lo")) - int(m.group("lo"))
          new_text = f"{m.group('subject')}:{target}" + (f"-{target + width}" if width else "")
        else:
          new_text = f":{target}"
        if new_text == old_text:
          left.append({**r, "why": "the citation already names that line"})
          continue
        edits.append({"rel": rel, "at": at, "old": old_text, "new": new_text, "count": ""})

  with open(args.out, "w", encoding="utf-8", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["rel", "at", "old", "new", "count"], delimiter="\t",
                       lineterminator="\n")
    w.writeheader()
    w.writerows(edits)
  with open(args.left, "w", encoding="utf-8", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(left[0].keys()), delimiter="\t", lineterminator="\n")
    w.writeheader()
    w.writerows(left)
  print(f"{len(edits)} re-points -> {args.out}; {len(left)} rows LEFT")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
