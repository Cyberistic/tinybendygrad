#!/usr/bin/env python3
"""autofix.py -- THE MECHANICAL RE-POINT, AND THE QUEUE THAT IS LEFT.

    .venv/bin/python .agents/slop/citefix/autofix.py --rows LOCATE.rows --out EDITS.rows --left LEFT.rows

For every FALSE row, the upstream construct the port's comment names, found by NAME at the
pin: the line where the upstream file DECLARES the token. The citation is re-pointed to
that line, and the `symbol=` field is added when the name is a declared upstream symbol.

The edit is the CITATION'S OWN SPAN, taken from `gates/header-census-gate.py`'s claim
reader and `gates/pin-cite-gate.py`'s span reader, so a line with three citations edits the
right one of the three.

A row whose token has NO declaration upstream is NOT edited: it goes to `--left`, which is
the queue a human has to read.
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
  edits: list[dict] = []
  left: list[dict] = []
  # THE PORT FILE, so the header block and the ambient are the FILE's own.
  by_file: dict[str, list[dict]] = collections.defaultdict(list)
  for r in rows:
    by_file[r["rel"]].append(r)

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
      # THE ROW'S PLACE IN THE LINE'S SPAN LIST. The claim reader emits the EXPLICIT
      # citations first and the BARE ones after; the span reader does the same, so the
      # pairing is by index.
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

      def declared(name: str) -> int:
        """The line where the upstream file DECLARES `name`, or 0."""
        for i, raw in enumerate(up, 1):
          s = raw.strip()
          if not s or s.startswith("#"):
            continue
          m = re.match(r"(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", s)
          if m and m.group(1) == name:
            return i
          m = re.match(r"([A-Za-z_]\w*)\s*(?::[^=]+)?=", s)
          if m and m.group(1) == name and not raw.startswith(" " * 8):
            return i
        return 0

      # THE CONSTRUCT THE COMMENT NAMES: the backticked identifier NEAREST BEFORE the
      # citation, because the port writes `NAME (file.py:N)`. Only then the token list,
      # because a token list is ordered by the gate's proximity and not by the prose.
      target = 0
      sym = ""
      before = line[:sp[0]]
      names = [n for span in pc.BACKTICK.findall(before)
               for n in pc.IDENT.findall(span) if len(n) >= 3]
      for n in reversed(names):
        if n in toks:
          decl_at = declared(n)
          if decl_at:
            target, sym = decl_at, n
            break
      if not target:
        for t in toks:
          decl_at = declared(t)
          if decl_at:
            target, sym = decl_at, t
            break
      if target is None or target == 0:
        left.append({**r, "why": "no token of the claim is DECLARED upstream"})
        continue
      new_text = old_text
      m = re.match(r"(?P<subject>[^:]*):(?P<lo>\d+)(?:-(?P<hi>\d+))?", old_text)
      if m:
        lo = int(m.group("lo"))
        hi = int(m.group("hi") or lo)
        width = hi - lo
        new_text = f"{m.group('subject')}:{target}" + (f"-{target + width}" if width else "")
      else:
        new_text = f":{target}"
      # THE `symbol=` FIELD, when the name IS a declared upstream symbol AND the
      # todo-cite gate can RESOLVE the subject: that gate's corpus is `tinygrad/` only,
      # so a subject outside it (`examples/llama.py`) or an ambiguous basename
      # (`dtype.py`) would make the row UNRESOLVABLE, which is a RED row.
      tin = path.startswith("tinygrad/")
      unique = len(corpus.files().get(r["subject"], [])) == 1 or "/" in r["subject"]
      if sym and tin and unique and re.search(rf"\bdef\s+{re.escape(sym)}\b", "\n".join(up)):
        new_text = new_text + f" symbol={sym}"
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
  print(f"{len(edits)} mechanical edits -> {args.out}; {len(left)} rows LEFT for a human")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
