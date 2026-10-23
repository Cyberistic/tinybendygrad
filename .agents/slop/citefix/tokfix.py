#!/usr/bin/env python3
"""tokfix.py -- RE-POINT A CITATION AT A LINE WHERE THE ROW'S OWN CLAIM HOLDS.

    .venv/bin/python .agents/slop/citefix/tokfix.py --rows LOCATE.rows --out EDITS.rows --left LEFT.rows

The pin-cite gate judges a citation by the CLAIM TOKENS it attributes to it: the
backticked names within `_NEAREST` (40) characters of the citation. So the line a citation
must name is a line where one of THOSE tokens occurs -- not a line where some other name
occurs.

The candidates are, in order: the DECLARATION of a token (`def X` / `class X` / `X =`),
then the first line that NAMES a token. The one closest to the line the citation names NOW
wins, because the port's comment was written against a revision where it was near.

A row whose tokens occur NOWHERE in the cited file is LEFT: no re-point can make it hold,
and the fix for that is the PROSE, not the number.
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
    for r in group:
      at = int(r["at"])
      line = src[at - 1]
      spans = pc.line_spans(hc, line)
      group_at = by_line.get(at, [])
      idx = next((i for i, c in enumerate(group_at)
                  if c["subject"] == r["subject"] and c["lo"] == int(r["lo"])), None)
      if idx is None or idx >= len(spans):
        left.append({**r, "why": "the row's citation is not on the line's span list"})
        continue
      sp = spans[idx]
      old_text = line[sp[0]:sp[1]]
      path, how = corpus.resolve(r["subject"], history=True, prefer_dir=prefer)
      if not path:
        left.append({**r, "why": f"the subject names no upstream file ({how})"})
        continue
      up = pin_lines(path)
      toks = [t for t in r["tokens"].split(",") if t]
      decls: list[int] = []
      names: list[int] = []
      for i, raw in enumerate(up, 1):
        s = raw.strip()
        if not s or s.startswith("#"):
          continue
        m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", s)
        is_decl = bool(m and m.group(1) in toks)
        if not is_decl:
          m2 = re.match(r"([A-Za-z_]\w*)\s*(?::[^=]+)?=", s)
          is_decl = bool(m2 and m2.group(1) in toks and not raw.startswith(" " * 8))
        if is_decl:
          decls.append(i)
          continue
        if any(re.search(rf"\b{re.escape(t)}\b", raw) for t in toks):
          names.append(i)
      cands = decls or names
      if not cands:
        left.append({**r, "why": "no claim token occurs anywhere in the cited file"})
        continue
      old_lo = int(r["lo"])
      target = min(cands, key=lambda n: abs(n - old_lo))
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
      edits.append({"rel": rel, "at": at, "old": old_text, "new": new_text})

  with open(args.out, "w", encoding="utf-8", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=["rel", "at", "old", "new"], delimiter="\t",
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
