#!/usr/bin/env python3
"""cs-opshape.py -- WHAT `except Exception` WOULD ADMIT, over all 77 ops.

`cshape`'s live arm is `except RuntimeError`. W1 (`+ AssertionError`) is the widening this
unit proposes. W2/W3/W4 add `NotImplementedError` and `ValueError` and then everything.

The question W4 has to answer is not "does it render more rows" -- measured, it renders
none that W1 does not -- but "what does it SWALLOW". So this asks every one of the 77 ops,
with zero srcs and then with one scalar CONST src, what `.shape` raises, and it separates
two facts that render as the same letter `R`:

  * ops.py:455  `shape requested, but X doesn't have a shape`  -- the op is in upstream's
    NO-SHAPE LIST (ops.py:331-338) and `_shape` is None. This is a fact about the op, and
    `R` is its faithful spelling.
  * ops.py:444  `None input shape not supported for X`          -- upstream ASSERTS. The op
    HAS a shape rule; the graph is malformed for shape purposes. `R` is a much weaker claim.
  * ops.py:451  `no shape handling for X with Y`                -- upstream has NO RULE for
    this (op, dtype) AT ALL. `R` would be a lie: there is nothing to be absent.

The third is what a bare `except Exception` buys, and it is why W4 is refused rather than
merely unused.

    env -u PYTHONPATH LC_ALL=C DEV=CPU .venv/bin/python .agents/slop/cshape/cs-opshape.py
"""
from __future__ import annotations

import collections
import os
import sys
import traceback

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
sys.path.insert(0, REPO)
os.environ["DEV"] = "CPU"

from tinygrad.uop.ops import UOp, Ops  # noqa: E402
from tinygrad import dtypes  # noqa: E402

NO_SHAPE_LIST = ("IF BARRIER SINK REWRITE_ERROR ENDIF BACKEDGE GROUP LINEAR PROGRAM "
                 "SOURCE").split()  # ops.py:331-338, transcribed FROM THE COMMENT and
# re-measured below by the `ops.py:455` rows, so a drift is visible rather than trusted.


def ask(u: UOp) -> tuple[str, str]:
  try:
    u.shape
    return ("ok", "")
  except BaseException as e:  # noqa: BLE001
    site = ""
    for fr in traceback.extract_tb(e.__traceback__):
      if fr.filename.startswith(REPO + "/tinygrad/"):
        site = os.path.relpath(fr.filename, REPO) + ":" + str(fr.lineno)
    return (type(e).__name__, site)


def main() -> int:
  print(f"# denominator = {len(list(Ops))} (measured len(list(Ops)))")
  zero: collections.Counter = collections.Counter()
  one: collections.Counter = collections.Counter()
  zero_where: dict[str, str] = {}
  one_where: dict[str, str] = {}
  for op in Ops:
    try:
      k, site = ask(UOp(op, src=()))
    except BaseException as e:  # noqa: BLE001 -- the CONSTRUCTION may refuse too
      k, site = "CTOR:" + type(e).__name__, ""
    zero[site.split(":")[-1] if site else "no-tinygrad-frame"] += 1
    zero_where[op.name] = f"{k}@{site}"
    try:
      c = UOp.const(UOp(op, src=()), 4)
      k, site = ask(c)
    except BaseException as e:  # noqa: BLE001
      k, site = "CTOR:" + type(e).__name__, ""
    one[site.split(":")[-1] if site else "no-tinygrad-frame"] += 0
    one[site.split(":")[-1] if site else "no-tinygrad-frame"] += 1
    one_where[op.name] = f"{k}@{site}"

  for label, where, d in (("ZERO srcs", zero_where, zero), ("ONE scalar CONST src", one_where, one)):
    print(f"\n# ==== {label}: raising line histogram ====")
    for ln, cnt in sorted(d.items(), key=lambda kv: -kv[1]):
      print(f"  {cnt:>3} ops  ops.py:{ln}")
    print(f"#   NO-SHAPE-LIST ops (ops.py:455): "
          f"{sorted(n for n, v in where.items() if ':455' in v)}")
    print(f"#   ASSERTED (ops.py:444):          "
          f"{sorted(n for n, v in where.items() if ':444' in v)}")
    print(f"#   NO RULE AT ALL (ops.py:451):   "
          f"{sorted(n for n, v in where.items() if ':451' in v)}")
    print(f"#   other:                          "
          f"{sorted((n, v) for n, v in where.items() if not any(s in v for s in (':455', ':444', ':451', 'ok@')))}")
    print(f"#   ok:                             {sorted(n for n, v in where.items() if v.startswith('ok'))}")

  print(f"\n# ==== THE THREE FACTS W1 AND W4 DIFFER ON, over {len(list(Ops))} ops x 2 arities ====")
  tally: collections.Counter = collections.Counter()
  for label, where in (("zero", zero_where), ("one", one_where)):
    for n, v in where.items():
      key = ("ok" if v.startswith("ok") else
             "ops.py:455 no-shape list (R is faithful)" if ":455" in v else
             "ops.py:444 upstream ASSERTS (R is a weaker claim)" if ":444" in v else
             "ops.py:451 NO RULE AT ALL (R would be a lie)" if ":451" in v else
             "other: " + v)
      tally[(label, key)] += 1
  for (label, key), cnt in sorted(tally.items()):
    print(f"  {label:<5} {cnt:>3}  {key}")
  print(f"\n# NOTE `NO-SHAPE LIST` is transcribed from ops.py:331-338 and is CHECKED by the")
  print(f"# 455 rows above, not trusted: it is the same class of stale list as `flip`'s 7/7.")
  listed = sorted(n for n, v in zero_where.items() if ":455" in v)
  print(f"#   transcribed {sorted(NO_SHAPE_LIST)}")
  print(f"#   MEASURED at zero srcs {listed}")
  print(f"#   in the transcription and not measured: {sorted(set(NO_SHAPE_LIST) - set(listed))}")
  print(f"#   measured and not in the transcription: {sorted(set(listed) - set(NO_SHAPE_LIST))}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
