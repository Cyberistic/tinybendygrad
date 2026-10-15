#!/usr/bin/env python3
"""label.py -- the residual NEW FAIL population, with each row's class.

39 of the rows carry the `failaudit` unit's hand label, matched by anchor.  The 12
`.agents/TODO.md` rows are the ones `failaudit` labelled at TODO line numbers that a
live rewrite has since moved; they are re-labelled here from the ROW's own evidence.

classes: FALSE-SHAPE (the needle is not a literal of the subject, so the question was
wrong), FALSE-SUBJECT (the prose names a symbol that lives in another file), FALSE-CONVENTION
(the number matches `wc -l` and not `splitlines()` on a file with no trailing newline),
TRUE (the prose claim is false), TRUE-STALE (it was true when written; the file moved).

usage: .venv/bin/python .agents/slop/residual/label.py
"""
import ast
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LAB = ROOT / ".agents/slop/failaudit/handlabels.rows"


def norm(a: str) -> str:
  return a[1:] if a.startswith(".") else a


old = {}
for line in LAB.read_text().splitlines():
  f = line.split("\t")
  old[norm(f[2])] = f[1]

MINE = {
  ("codegen/decomp/dtype.bend", "BASE_ORACLES"): "FALSE-SHAPE",
  ("runtime/webgpu_call.js", ""): "TRUE",
  ("uop/ops.bend", "cfunc_buf"): "FALSE-SHAPE",
  ("engine/realize.bend", "array"): "FALSE-SHAPE",
  ("codegen/decomp/dtype.bend", "native"): "FALSE-SHAPE",
  ("uop/render.bend", "LANE-DEATH"): "FALSE-SHAPE",
  ("viz/serve.bend", "LANE-DEATH"): "FALSE-SHAPE",
  ("runtime/ops_python.bend", ""): "TRUE-STALE",
  ("mixin/gradient.bend", ""): "TRUE-STALE",
  ("renderer/cstyle.bend", ""): "TRUE-STALE",
  ("viz/serve.bend", "pad_name"): "TRUE",
}

rows = (ROOT / ".agents/slop/residual/fails-now.rows").read_text().splitlines()
out, counts = [], {}
for line in rows:
  f = line.split("\t")
  if len(f) < 6 or f[4] != "suffix-index":
    continue
  anchor, subj, needle = f[1], f[2], ast.literal_eval(f[3])
  lab = old.get(norm(anchor)) or MINE.get((subj, needle))
  if lab is None:
    lab = MINE.get((subj, ""), "UNLABELLED")
    print(f"UNMATCHED {anchor} {subj} {needle!r}", file=sys.stderr)
  counts[lab] = counts.get(lab, 0) + 1
  out.append((anchor, subj, needle, lab, f[5]))
with (ROOT / ".agents/slop/residual/classified.rows").open("w") as fh:
  for a, s, n, l, e in out:
    fh.write(f"{l:16s}\t{a}\t{s}\t{n}\t{e}\n")
print(f"NEW FAILs classified = {len(out)}")
for k in ("FALSE-SHAPE", "FALSE-SUBJECT", "FALSE-CONVENTION", "TRUE", "TRUE-STALE", "UNLABELLED"):
  if counts.get(k):
    print(f"  {k:16s} {counts[k]}")
print("-> .agents/slop/residual/classified.rows")
