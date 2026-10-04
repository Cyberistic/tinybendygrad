#!/usr/bin/env python3
"""arena-jit-rows.py -- the CPython comparison for `engine/jit.bend`'s two `prune_sig_*` rows.

`rebase-gate.py`'s `rows()` IS the reader -- agent-core is explicit that a harness must not
write a second one, because a name-comparing reader reported 0 for all 30 mutations in one
unit. So this file imports it and adds only the ORACLE, which is the part that was missing:
`jit-oracle.py` skips four rows and these two were PORT-ONLY, so the defect they encoded was
invisible to every gate in the tree.

Three states, because "the rows moved" and "the rows are RIGHT" are different claims:

  DISAGREE  a row's port value differs from CPython's.
  AGREE     both lanes compared the row and matched.
  NO-LANE   CPython printed no such row, so nothing was compared and nothing is claimed.

usage: arena-jit-rows.py [--fixed path]
"""
import importlib.util, os, subprocess, sys, collections

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASE = os.path.join(ROOT, ".agents/slop/arena-jit-baseline.txt")
ORACLE = os.path.join(ROOT, ".agents/slop/jit-prune-truth.py")
PY = os.path.join(ROOT, ".venv/bin/python")

def load_rows_reader():
  spec = importlib.util.spec_from_file_location("rebase_gate",
                                                 os.path.join(ROOT, ".agents/slop/rebase-gate.py"))
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m.rows

def cpython():
  """run the oracle TWICE and refuse to claim anything unless both runs agree.

  agent-core: run anything twice. A one-shot oracle is a coin flip, and `nv_query_litter`
  was wrong in the PORT *and* in the ORACLE, so the differ reported zero disagreements over
  an error made twice."""
  outs = []
  for _ in range(2):
    r = subprocess.run([PY, ORACLE], capture_output=True, text=True, cwd=ROOT)
    if r.returncode != 0:
      print(f"ORACLE DIED rc={r.returncode}\n{r.stderr[-600:]}")
      return None
    outs.append(r.stdout)
  if outs[0] != outs[1]:
    print("ORACLE IS NOT DETERMINISTIC -- refusing to compare")
    print("run 1:", outs[0][:400])
    print("run 2:", outs[1][:400])
    return None
  return outs[0]

def main():
  rows = load_rows_reader()
  fixed = sys.argv[sys.argv.index("--fixed") + 1] if "--fixed" in sys.argv \
          else os.path.join(ROOT, ".agents/slop/arena-jit-fixed.txt")
  cp = cpython()
  if cp is None: return 1
  c = rows(cp)
  print(f"CPython rows: {len(c)}   (ran twice, identical)")
  for lane, path in (("BASELINE", BASE), ("FIXED", fixed)):
    p = rows(open(path, encoding="utf-8").read())
    verdict = collections.Counter()
    detail = []
    for k in sorted(c):
      if k not in p:
        verdict["NO-LANE"] += 1
        detail.append(f"  NO-LANE  {k}: port printed nothing")
      elif p[k] != c[k]:
        verdict["DISAGREE"] += 1
        detail.append(f"  DISAGREE {k}\n      port    {p[k]}\n      cpython {c[k]}")
      else:
        verdict["AGREE"] += 1
    for k in sorted(p):
      if k not in c and "prune_sig" in k:
        verdict["NO-CPYTHON"] += 1
    print(f"\n{lane}: {len(p)} rows -- AGREE {verdict['AGREE']}  "
          f"DISAGREE {verdict['DISAGREE']}  NO-LANE {verdict['NO-LANE']}")
    for d in detail: print(d)
    if verdict["DISAGREE"] == 0 and verdict["AGREE"] > 0:
      print(f"  -> {lane} AGREES with CPython on every row CPython printed")
  return 0

if __name__ == "__main__":
  sys.exit(main())