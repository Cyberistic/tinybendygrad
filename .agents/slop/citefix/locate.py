#!/usr/bin/env python3
"""locate.py -- WHERE DOES THE CLAIM HOLD AT THE PIN?

    .venv/bin/python .agents/slop/citefix/locate.py --rows ROWS --out ROWS

For every FALSE row of the census, the upstream file the subject resolves to (BY THE
GATE'S OWN AMBIENT), the lines at the PIN that carry the claim's tokens, and the
declaration each of those lines sits in.

THE INSTRUMENTS ARE IMPORTED, NOT COPIED. `gates/header-census-gate.py` resolves a
subject and `gates/pin-cite-gate.py` holds a claim, and this file asks both the same
questions the gate asks, so a suggestion here is a suggestion the gate can confirm.

THE PIN IS READ FROM GIT, at the vendored tree's commit, so a hand edit to the vendored
copy cannot make a false citation look true.
"""

from __future__ import annotations

import argparse
import collections
import csv
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
GATES = ROOT / "gates"
PIN = "5c2bf39d6c4b"


def load(name: str, path: Path):
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def git(*args: str) -> str:
  p = subprocess.run(("git", "--no-optional-locks",) + args, cwd=ROOT,
                     capture_output=True, text=True)
  return p.stdout


def main() -> int:
  ap = argparse.ArgumentParser()
  ap.add_argument("--rows", required=True)
  ap.add_argument("--out", required=True)
  ap.add_argument("--only", default="", help="substring of the port file to restrict to")
  ap.add_argument("--rel", default="", help="exact port file to restrict to")
  args = ap.parse_args()

  census = load("hcensus", GATES / "header-census-gate.py")
  pincite = load("pincite", GATES / "pin-cite-gate.py")

  rows = list(csv.DictReader(open(args.rows, encoding="utf-8"), delimiter="\t"))
  corpus = census.Upstream(pincite.UPSTREAM)

  # THE PORT FILE'S DECLARED TARGET, which is the ambient the gate uses.
  prefer: dict[str, str] = {}
  for rel in {r["rel"] for r in rows}:
    body = (ROOT / rel).read_text(encoding="utf-8", errors="replace").splitlines()
    _f, _l, blk = census.header_block(body)
    tgt = census.declared_target(blk)
    # THE GATE'S OWN AMBIENT: `collect()` sets `prefer_dir` to the declared target's
    # directory, with the FULL `tinygrad/` prefix, and `Upstream.resolve()` compares it
    # to the upstream path's own directory. Anything else is a different ambient.
    prefer[rel] = tgt.rsplit("/", 1)[0] if "/" in tgt else ""

  cache: dict[str, list[str]] = {}

  def pin_lines(path: str) -> list[str]:
    if path not in cache:
      txt = git("show", f"{PIN}:{path}")
      cache[path] = txt.splitlines()
    return cache[path]

  out: list[dict] = []
  for r in rows:
    if r["false_at_pin"] != "yes":
      continue
    if r["mine"] != "1":
      continue
    if args.rel and r["rel"] != args.rel:
      continue
    if args.only and args.only not in r["rel"]:
      continue
    subject = r["subject"]
    path, how = corpus.resolve(subject, history=True, prefer_dir=prefer.get(r["rel"], ""))
    toks = [t for t in r["claim"].split(",") if t]
    rec = {"rel": r["rel"], "at": r["at"], "subject": subject, "lo": r["lo"], "hi": r["hi"],
           "class": r["class"], "tokens": ",".join(toks), "up": path or "", "how": how,
           "up_len": 0, "hits": "", "decls": "", "note": ""}
    if not path:
      rec["note"] = "the subject names NO upstream file"
      out.append(rec)
      continue
    lines = pin_lines(path)
    rec["up_len"] = len(lines)
    # THE LINES THAT CARRY THE TOKENS, and the DECLARATION each sits in.
    hits: list[int] = []
    for i, ln in enumerate(lines, 1):
      if any(re.search(rf"\b{re.escape(t)}\b", ln) for t in toks):
        hits.append(i)
    rec["hits"] = ",".join(str(h) for h in hits[:40])
    # THE DECLARATIONS OF THE FILE, so a name can be found by NAME.
    decls: list[str] = []
    for i, raw in enumerate(lines, 1):
      m = re.match(r"^(\s*)(?:async\s+)?(?:def|class)\s+([A-Za-z_]\w*)", raw)
      if m:
        decls.append(f"{m.group(2)}@{i}")
    rec["decls"] = " ".join(decls)
    out.append(rec)

  with open(args.out, "w", encoding="utf-8", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=list(out[0].keys()), delimiter="\t", lineterminator="\n")
    w.writeheader()
    w.writerows(out)
  print(f"{len(out)} false rows located -> {args.out}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
