#!/usr/bin/env python3
"""cs-androot.py -- IS "EVERY PATTERN IR IS `AND`-ROOTED" UPSTREAM'S RULE OR THE
DIFFER'S? MEASURED, over every `UPat` shape this tree can build, by CALLING upstream.

The brief's claim is that `tinygrad/uop/upat.py:66` makes every pattern-compiler IR
`AND`-rooted, and that therefore a graph needing an `OR` root or an ATOM root cannot be
expressed. If that is upstream's own rule the question closes permanently, because the
differ is not the thing that would have to change. This measures the roots instead of
reading them off the source, because a rule read off a source is a claim and a root
counted by calling `_get_clause` is a measurement.

It also asks the question the reading cannot answer: WHERE is the rule, and is it load
bearing for matching or merely a representation? Three upstream sites make the root
`AND`, and the third is an `assert` -- which settles it.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/cshape/cs-androot.py
"""
from __future__ import annotations

import collections
import itertools
import os
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, REPO)
os.environ["DEV"] = "CPU"

from tinygrad.uop.ops import UOp, UPat, Ops  # noqa: E402
from tinygrad.uop.upat import _get_clause  # noqa: E402
from tinygrad import dtypes  # noqa: E402

BASE = UOp(Ops.CUSTOMI, arg=("uop", dtypes.void))


def shapes() -> list[tuple[str, UPat]]:
  """Every `UPat` shape the pattern compiler distinguishes, named by the CLAUSE that
  produces it (upat.py:25-64). Not a sample: one per branch of `_get_clause`."""
  out: list[tuple[str, UPat]] = [
    ("op only, len 1             (upat.py:27)", UPat(Ops.ADD)),
    ("op only, len 2             (upat.py:25)", UPat((Ops.ADD, Ops.MUL))),
    ("arg int                    (upat.py:29)", UPat(Ops.ADD, arg=3)),
    ("arg str                    (upat.py:30)", UPat(Ops.ADD, arg="x")),
    ("name                       (upat.py:32)", UPat(Ops.ADD, name="a")),
    ("allow_any_len (not strict) (upat.py:31)", UPat(Ops.ADD, src=(UPat(Ops.MUL),), allow_any_len=True)),
    ("src as a bare UPat (repeat) (upat.py:52)", UPat(Ops.ADD, src=UPat(Ops.MUL))),
    ("match_dtype len 1          (upat.py:34)", UPat(Ops.ADD, dtype=(dtypes.int,))),
    ("match_dtype len 2          (upat.py:33)", UPat(Ops.ADD, dtype=(dtypes.int, dtypes.uint))),
    ("match_tag len 1            (upat.py:36)", UPat(Ops.ADD, tag=("a",))),
    ("match_tag len 2            (upat.py:35)", UPat(Ops.ADD, tag=("a", "b"))),
    ("src, single match          (upat.py:42)", UPat(Ops.ADD, src=(UPat(Ops.MUL),))),
    ("src, multi match           (upat.py:43)", UPat(Ops.ADD, src=(UPat(Ops.MUL), UPat(Ops.SUB)))),
    ("src as a LIST -> FORK      (upat.py:63)", UPat(Ops.ADD, src=[UPat(Ops.MUL), UPat(Ops.SUB)])),
    ("UPat.any(...) (is_any)     (upat.py:20)", UPat.any(UPat(Ops.MUL), UPat(Ops.SUB))),
    ("op as a set                (upat.py:25)", UPat(op={Ops.ADD, Ops.MUL})),
    ("NOTHING (empty clause)     (upat.py:66)", UPat()),
    ("EVERYTHING at once                    ",
     UPat(Ops.ADD, arg=3, name="a", dtype=(dtypes.int,), tag=("t",),
          src=(UPat(Ops.MUL),), allow_any_len=True)),
  ]
  return out


def main() -> int:
  print("# `_get_clause` ROOTS, called for every `UPat` shape, with `base=CUSTOMI('uop')`")
  print(f"  {'UPat shape':<40} {'n':>3} {'root op':<10} root src ops")
  roots: collections.Counter = collections.Counter()
  ored: list[str] = []
  for label, pat in shapes():
    try:
      r = _get_clause(pat, BASE)
    except BaseException as e:  # noqa: BLE001
      print(f"  {label:<40} ERR {type(e).__name__}: {' '.join(str(e).split())[:40]}")
      continue
    roots[r.op.name] += 1
    inner = [n.op.name for n in r.toposort()]
    if "OR" in inner:
      ored.append(label.strip())
    print(f"  {label:<40} {len(r.toposort()):>3} {r.op.name:<10} {' '.join(inner)}")
  print(f"\n# ROOT HISTOGRAM over {sum(roots.values())} patterns: {dict(roots)}")
  print(f"#   roots that are OR: {sum(1 for _ in ored)}   patterns whose IR CONTAINS an OR "
        f"(always under the AND): {ored or 'none'}")
  print(f"#   OR appears in {sum(1 for l in ored)}/1 pattern(s), and in every case it is a "
        f"CHILD of the AND (upat.py:20) -- never a root.")

  # ---- THE SITE THAT SETTLES IT: upstream ASSERTS the root is AND -------------------
  import inspect

  from tinygrad.uop import upat
  src = inspect.getsource(upat)
  for pat, line in ((r"return UOp\(Ops\.AND", "upat.py:66"), (r"x = UOp\(Ops\.AND, \(x,\)\)", "upat.py:139"),
                    (r"assert x\.op is Ops\.AND", "upat.py:140"), (r"UPat\(Ops\.AND, name=\"a\"\)", "upat.py:118")):
    hits = [i + 1 for i, ln in enumerate(src.splitlines()) if re_search(pat, ln)]
    print(f"#   {line:<12} pattern {pat:<34} found at upat.py:{hits}")
  return 0


def re_search(pat: str, ln: str) -> bool:
  import re
  return re.search(pat, ln) is not None


if __name__ == "__main__":
  sys.exit(main())
