#!/usr/bin/env python3
"""cs-arms.py -- WHAT `cshape`'s `except` ACTUALLY CATCHES, ONE EXCEPTION AT A TIME.

Reads the live `.agents/slop/graphcmp.py` (never a copy: another unit is editing it, and a
copy would silently measure a stale corpus) and, for every node of every py-side graph in
the corpus PLUS the pattern-compiler IR from upstream's own `_get_clause`, asks
`node.shape` what it raises and WHERE.

It then reports, for each candidate widening of the one `except RuntimeError` arm:
  * how many nodes of how many graphs become renderable
  * which OPS that buys, against the MEASURED corpus of the day (read from this run, not
    transcribed)
  * every DISTINCT (exception type, raising file:line, message prefix) the widening admits

The last column is the whole point. Catching more is not the same as admitting more, and
the only way to know what a widening admits is to print what it swallows.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/cshape/cs-arms.py
"""
from __future__ import annotations

import collections
import os
import sys
import traceback

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, REPO)
sys.path.insert(0, os.path.join(REPO, ".agents/slop"))

os.environ["DEV"] = "CPU"

import graphcmp as G  # noqa: E402

G.load_tinygrad()
G.COMM = G.commutative()

from tinygrad.uop.ops import UOp, UPat, Ops  # noqa: E402
from tinygrad.uop.upat import _get_clause  # noqa: E402
from tinygrad.uop.ops import GroupOp  # noqa: E402
from tinygrad import dtypes  # noqa: E402


def patir() -> UOp:
  """upat.py:66 `_get_clause`, called the way upstream calls it. NOT hand-built."""
  return _get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))


def ask(n: UOp) -> tuple[str, str, str]:
  """(kind, raising file:line, message prefix) for `n.shape`.

  `kind` is `ok` when the shape answers. Otherwise the deepest frame inside tinygrad is
  the raising site, which is what makes the answer a fact about upstream rather than about
  the caller that happened to ask.
  """
  try:
    n.shape
    return ("ok", "", "")
  except BaseException as e:  # noqa: BLE001 -- this IS the census of what can be raised
    site, msg = "", " ".join(str(e).split())
    for fr in traceback.extract_tb(e.__traceback__):
      f = fr.filename
      if f.startswith(REPO + "/tinygrad/"):
        site = os.path.relpath(f, REPO) + ":" + str(fr.lineno)
    if not site:
      tb = traceback.format_tb(e.__traceback__)[-1].strip()
      site = tb.split("\n")[0].split(",")[0].lstrip("  File \"")[:40]
    return (type(e).__name__, site, msg[:70])


WIDEN: list[tuple[str, tuple[type, ...]]] = [
    ("W0  RuntimeError (LIVE)", (RuntimeError,)),
    ("W1  W0 + AssertionError", (RuntimeError, AssertionError)),
    ("W2  W1 + NotImplementedError", (RuntimeError, AssertionError, NotImplementedError)),
    ("W3  W2 + ValueError", (RuntimeError, AssertionError, NotImplementedError, ValueError)),
    ("W4  bare Exception", (Exception,)),
]


def main() -> int:
  print(f"# graphcmp md5 {G.__file__}")
  # ---- the live corpus, read from THIS run -------------------------------------------
  corpus: dict[str, list[UOp]] = {}
  for g in sorted(G.GRAPHS):
    corpus[g] = G.base(g).toposort()
  corpus["patir"] = patir().toposort()

  # ---- per-node census ---------------------------------------------------------------
  census: dict[str, dict[int, tuple[str, str, str]]] = {}
  for g, nodes in corpus.items():
    census[g] = {id(n): ask(n) for n in nodes}

  print(f"\n# ==== 1. WHAT `node.shape` DOES, PER GRAPH, GROUPED BY OUTCOME ====")
  kinds: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
  for g, nodes in corpus.items():
    for n in nodes:
      kinds[g][census[g][id(n)][0]] += 1
  print(f"  {'graph':<10} {'nodes':>5}  outcome histogram")
  for g in sorted(kinds):
    print(f"  {g:<10} {len(corpus[g]):>5}  {dict(kinds[g])}")

  print(f"\n# ==== 2. EVERY DISTINCT (type, raising site, message) OVER ALL {sum(len(v) for v in corpus.values())} NODES ====")
  sites: collections.Counter = collections.Counter()
  for g in census:
    for n in corpus[g]:
      k, site, msg = census[g][id(n)]
      sites[(k, site, msg)] += 1
  for (k, site, msg), cnt in sorted(sites.items(), key=lambda kv: -kv[1]):
    print(f"  {cnt:>4}x  {k:<20} {site:<34} {msg}")

  print(f"\n# ==== 3. EACH WIDENING: WHAT IT RENDERS, WHAT IT BUYS, WHAT IT ADMITS ====")
  base_ops = set()
  for g in sorted(G.GRAPHS):
    base_ops |= {n.op.name for n in corpus[g]}
  print(f"# LIVE corpus py-side distinct ops = {len(base_ops)} of {len(list(Ops))}")
  for label, excs in WIDEN:
    rendered_nodes, rendered_graphs, ops = 0, 0, set()
    admitted: collections.Counter = collections.Counter()
    for g, nodes in corpus.items():
      ok = 0
      for n in nodes:
        k, site, msg = census[g][id(n)]
        if k == "ok" or issubclass(_EXC[k], excs):
          ok += 1
          ops.add(n.op.name)
          if k != "ok":
            admitted[(k, site, msg)] += 1
      rendered_nodes += ok
      rendered_graphs += 1 if ok == len(nodes) else 0
    new = sorted(ops - base_ops)
    print(f"\n  {label}")
    print(f"    nodes rendered {rendered_nodes}/{sum(len(v) for v in corpus.values())}"
          f"   graphs fully rendered {rendered_graphs}/{len(corpus)}"
          f"   distinct ops {len(ops)} of {len(list(Ops))}")
    print(f"    NEW ops vs the live corpus: {new or 'none'}")
    for (k, site, msg), cnt in sorted(admitted.items(), key=lambda kv: -kv[1]):
      print(f"      admits {cnt:>4}x {k:<20} {site:<34} {msg}")
    print(f"    ops in the 4 blocked set now emittable: "
          f"{sorted(set(new) & {'CUSTOM', 'CUSTOMI', 'PYLITERAL', 'MULACC'}) or 'none'}")

  print(f"\n# ==== 4. IS `AND` IN `GroupOp.Broadcastable`, AND DOES UPSTREAM PUT IT THERE ====")
  print(f"#   Ops.AND in GroupOp.Broadcastable = {Ops.AND in GroupOp.Broadcastable}")
  print(f"#   Ops.CUSTOM in GroupOp.Broadcastable = {Ops.CUSTOM in GroupOp.Broadcastable}")
  return 0


_EXC: dict[str, type] = {
    "RuntimeError": RuntimeError, "AssertionError": AssertionError,
    "NotImplementedError": NotImplementedError, "ValueError": ValueError,
    "TypeError": TypeError, "KeyError": KeyError, "IndexError": IndexError,
    "AttributeError": AttributeError, "ZeroDivisionError": ZeroDivisionError,
    "RecursionError": RecursionError, "Exception": Exception,
}


if __name__ == "__main__":
  sys.exit(main())
