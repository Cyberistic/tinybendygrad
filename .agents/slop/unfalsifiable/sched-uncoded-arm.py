#!/usr/bin/env python3
"""sched-uncoded-arm.py -- FIND A SLICE WHERE THE UNCODED-OP HAZARD FIRES.

SUBJECT:    the op-name sequences `sched-cmp.py` feeds to `pack`, for a spec whose
            graph contains an op `DIG` has no code for.
INSTRUMENT: `sched-cmp.py`'s own `DIG` / `dig` / `pack` / `pack16` / `store_val_op`,
            imported BY PATH so the alphabet under test is the live one and not a
            copy that could drift from it.

THE HAZARD, as stated in the audit: `dig(name)` returns 0 for a name outside DIG,
and 0 is also `pack([])`, so a sequence of uncoded ops and an EMPTY sequence pack
to the same value, on BOTH sides -- an agreement about a digit that means nothing.
`sched-cmp.py`'s docstring claims the census of uncoded ops is printed. It is a
loop that discards its result (`sched-cmp.py:135`).

THIS FILE ANSWERS ONE QUESTION, EMPIRICALLY: can a spec be constructed whose
`ksrc`, `ktop` or `kmark` slice contains an uncoded op? Every candidate below is
DRIVEN, not guessed. Nothing here is transcribed.

RUN:
  env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python \\
    .agents/slop/unfalsifiable/sched-uncoded-arm.py
"""
import importlib.util
import os
import sys

REPO = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
SLOP = os.path.join(REPO, ".agents/slop")
sys.path.insert(0, REPO)


def load(path, name):
  spec = importlib.util.spec_from_file_location(name, path)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


CMP = load(os.path.join(SLOP, "sched-cmp.py"), "cmp_arm")
SO = load(os.path.join(SLOP, "sched-oracle.py"), "so_arm")

from tinygrad import Tensor  # noqa: E402  -- after the path insert, by design


def slices_for(lin):
  """The three packed slices, each as the RAW NAME LIST `sched-cmp.py` packs --
  plus the arity list `pack16` sees, which needs no alphabet and so cannot arm."""
  ksrc = [u.op.name for k in lin.src for u in k.src]
  ktop = [k.src[0].op.name for k in lin.src]
  kmark = [CMP.store_val_op(k) for k in lin.src]
  return {"ksrc": ksrc, "ktop": ktop, "kmark": kmark}


def candidate_exp():
  a = Tensor.empty(4, 3).realize()
  return Tensor.empty(4, 3).realize().assign(a.exp())


def candidate_cmp():
  """A comparison. tinygrad lowers `a > b` to a CMPLT under a WHERE."""
  a = Tensor.empty(4, 3).realize()
  b = Tensor.empty(4, 3).realize()
  return Tensor.empty(4, 3).realize().assign((a > b).relu())


def candidate_where():
  a = Tensor.empty(4, 3).realize()
  b = Tensor.empty(4, 3).realize()
  return Tensor.empty(4, 3).realize().assign(Tensor.where(a > b, a, b))


def candidate_log():
  a = Tensor.empty(4, 3).realize()
  return Tensor.empty(4, 3).realize().assign((a + 2).log())


CANDIDATES = [
  ("exp", candidate_exp),
  ("cmp", candidate_cmp),
  ("where", candidate_where),
  ("log", candidate_log),
]


def report(label, fn):
  SO._reset()
  SO._CAPTURED.clear()
  try:
    fn()
  except Exception as e:
    print(f"  {label:10s} RAISED {type(e).__name__}: {e}")
    return None
  if not SO._CAPTURED:
    print(f"  {label:10s} NO_SCHEDULE_CALL (no schedule)")
    return None
  sink, lin = SO._CAPTURED[-1]
  sl = slices_for(lin)
  armed = {k: [n for n in v if CMP.dig(n) == 0 and n != ""]
           for k, v in sl.items()}
  armed = {k: v for k, v in armed.items() if v}
  print(f"  {label:10s} ksrc={sl['ksrc']} ktop={sl['ktop']} kmark={sl['kmark']}")
  if armed:
    print(f"             *** ARMED in {armed}")
  else:
    print("             not armed (every packed name has a code)")
  return armed


def main():
  print("=" * 78)
  print("0. THE NON-INJECTIVITY, computed by CALLING the live pack()")
  for names in (["SHR", "SHL"], ["NOPE", "WHAT"], [], ["CAST"], ["WHERE"]):
    print(f"  pack({names!r:22s}) = {CMP.pack(names)}")
  print(f"  DIG size = {len(CMP.DIG)}, entries with digit 0: "
        f"{[k for k, v in CMP.DIG.items() if v == 0] or 'none'}")

  print("=" * 78)
  print("1. THE EXISTING SIX -- does any of THEM arm it?")
  for name, fn in SO.SPECS:
    report(name, fn)

  print("=" * 78)
  print("2. CANDIDATE SPECS, each DRIVEN -- which slice arms, and on what")
  hits = {}
  for label, fn in CANDIDATES:
    a = report(label, fn)
    if a:
      hits[label] = a

  print("=" * 78)
  if not hits:
    print("NOT ARMED BY ANY CANDIDATE -- report that, do not claim a fix.")
    return 1
  print("ARMED BY:", sorted(hits))
  # For the first arming candidate, show what the comparator would PRINT for the
  # packed field, and what its own `uncoded` counter would hold.
  label = sorted(hits)[0]
  import collections
  uncoded = collections.Counter()
  SO._reset()
  SO._CAPTURED.clear()
  CANDIDATES[label == "cmp" and 1 or 0][1] if False else None
  for lbl, fn in CANDIDATES:
    if lbl != label:
      continue
    fn()
    sink, lin = SO._CAPTURED[-1]
    sl = slices_for(lin)
    for field, names in sl.items():
      for n in names:
        if n and CMP.dig(n) == 0:
          uncoded[f"{field}:{n}"] += 1
    print(f"  spec {label!r}: the census that sched-cmp.py:135 DISCARDS would be "
          f"{dict(uncoded)}")
    for field in ("ksrc", "ktop", "kmark"):
      print(f"  {field:5s} packs to {CMP.pack(sl[field])}   "
            f"(n={len(sl[field])}, and pack([])={CMP.pack([])})")
  return 0


if __name__ == "__main__":
  sys.exit(main())