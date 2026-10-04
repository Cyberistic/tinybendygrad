#!/usr/bin/env python3
"""ADEV's re-measure: every graph's VERDICT, and the 13 blocked candidates.

Run from `.agents/slop` with the venv interpreter (`sys.path[0]` is this file's dir, so a
bare `python3` cannot import `graphcmp`):

    ../../.venv/bin/python adev/recheck.py verdicts
    ../../.venv/bin/python adev/recheck.py blocked

NOTHING HERE IS TRANSCRIBED. Two rules from `agent-core.md` and `DENOMINATOR.md` govern it:

  * The candidate RECIPES are imported from `.agents/slop/denom/emittable.py`'s `CANDS`,
    never retyped. `agent-core.md`'s table of hand-typed oracles is five rows long and the
    last one had BOTH the port and the oracle wrong, "so the differ reported 0
    disagreements over an error made twice".
  * `emittable` and `reached` are asked SEPARATELY. `DENOM-4`: the census and the emitter
    are different instruments and they disagree.

WHAT `blocked` ACTUALLY ANSWERS, because the brief's framing needs one correction.
DENOMINATOR.md §8 says "Did not add the other 13 candidate graphs ... each measured
emittable". So they were NOT blocked on emittability -- `cshape` could already render them.
What they were blocked on was the NORMAL FORM: a fixture whose arg is a device pair had no
settled spelling to be written down in, so it could not be added without guessing. So the
question this unit must measure is not "how many can `cshape` render" but

    HOW MANY OF THE 13 DID THE ADEV-1 DECISION ACTUALLY CHANGE?

and the column that answers it is `moved`: for every node of the candidate, render the arg
with the PRE-FIX flattening renderer and with the POST-FIX one and ask whether the two
disagree. `moved=NO` means the decision was a no-op for that candidate and its only real
blocker was something else.
"""
import contextlib
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SLOP = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(SLOP))


def run(args):
  env = dict(os.environ, DEV="CPU", LC_ALL="C")
  env.pop("PYTHONPATH", None)
  return subprocess.run([sys.executable, "graphcmp.py", *args], cwd=SLOP, env=env,
                        capture_output=True, text=True, timeout=1800)


def verdicts():
  sys.path.insert(0, SLOP)
  import graphcmp
  from collections import Counter
  rows = []
  for g in sorted(graphcmp.GRAPHS):
    p = run(["diff", "--graph", g])
    m = re.search(r"^# VERDICT: (\w+)", p.stdout, re.M)
    d = re.search(r"^# DENOMINATOR: .*?nodes=(\d+)/(\d+).*?field-records=(\d+)", p.stdout, re.M)
    rows.append((g, m.group(1) if m else "NO-VERDICT",
                 f"nodes={d.group(1)}/{d.group(2)} field-records={d.group(3)}" if d else "?", p.returncode))
  print(f"{'graph':<10} {'VERDICT':<10} denominator")
  for g, v, d, _ in rows:
    print(f"{g:<10} {v:<10} {d}")
  print("\nTALLY", dict(Counter(v for _, v, _, _ in rows)))
  print("REACHED (ops seen on either side) and the denominator are re-measured by `denom/census.py`;"
        "\nthis table is the VERDICT per graph, which is the headline.")
  return 0 if all(v != "NO-VERDICT" for _, v, _, _ in rows) else 1


def _pre_fix_dev(x):
  """The pre-ADEV-1 device renderer, re-evaluated rather than remembered.
  `graphcmp.py`'s `dev` was `ATOMS['str'] + ','.join(x)` for a tuple; it is gone, so the
  arithmetic is inlined here. Keeping the PRE-fix spelling in one place is what lets the
  `moved` column be a measurement instead of a claim."""
  import graphcmp as G
  if x is None:
    return G.ATOMS["none"]
  return G.ATOMS["str"] + ",".join(x) if isinstance(x, tuple) else G.bstr(str(x))


def blocked():
  sys.path.insert(0, SLOP)
  os.chdir(ROOT)
  sys.path.insert(0, os.path.join(ROOT, ".agents", "slop", "denom"))
  os.environ["DEV"] = "CPU"
  import graphcmp as G
  G.load_tinygrad()
  with contextlib.redirect_stdout(io.StringIO()):     # emittable.py prints at import
    import emittable

  cands = [(n, c) for n, c, _ in emittable.CANDS]
  done = {"allred"}                                      # already in the corpus (DENOM §4)
  print(f"# CANDS measured by denom/emittable.py = {len(cands)}; already in the corpus: {sorted(done)}")
  print(f"# DENOMINATOR.md §8 says 'the other 13' and NAMES 12. The 13th is `mulacc`")
  print(f"# (§3: 'needs an NVIDIA device, not a different graph'; §8: 'Did not touch MULACC's")
  print(f"# PTX gate'). `patir` is the 15th of CANDS and is blocked by the INSTRUMENT (DENOM-3).")

  print(f"\n{'cand':<9} {'nodes':<6} {'emittable':<10} {'moved':<7} what the ADEV-1 decision did")
  tally = {"emittable": 0, "moved": 0, "total": 0}
  for name, cite in cands:
    if name in done:
      print(f"{name:<9} {'-':<6} {'IN CORPUS':<10} {'-':<7} {cite}")
      continue
    tally["total"] += 1
    try:
      root = emittable.CANDS[[c[0] for c in emittable.CANDS].index(name)][2]()
      nodes = list(root.toposort())
    except Exception as e:                                     # noqa: BLE001
      print(f"{name:<9} {'ERR':<6} {'NO':<10} {'-':<7} BUILD {type(e).__name__}: "
            f"{' '.join(str(e).split())[:60]}")
      continue
    # (a) EMITTABLE -- can cshape render EVERY node?  DENOM-4.
    ix = {id(s): i + 1 for i, s in enumerate(nodes)}
    try:
      for i, n in enumerate(nodes):
        G.row_of(n, i + 1, ix)
      emit, why = "YES", ""
      tally["emittable"] += 1
    except Exception as e:                                     # noqa: BLE001
      emit, why = "NO", f"{type(e).__name__}: {' '.join(str(e).split())[:44]}"
    # (b) MOVED -- did the ADEV-1 decision change this candidate's arg text at all?
    moved, sample = "NO", ""
    for n in nodes:
      if n.op not in (G.Ops.COPY, G.Ops.ALLREDUCE) and not (
          n.arg is not None and isinstance(n.arg, tuple) and any(
              isinstance(d, tuple) for d in n.arg if isinstance(d, (tuple, str)))):
        continue
      pre = _pre_fix_dev(n.arg if n.op is G.Ops.COPY else n.arg[1]) if n.op in (
          G.Ops.COPY, G.Ops.ALLREDUCE) else None
      post = G._carg(n.arg) if n.op is G.Ops.COPY else G._carg(n.arg[1])
      if pre is not None and pre != post:
        moved = "YES"
        sample = f"{n.op.name}: {pre} -> {post}"
        tally["moved"] += 1
        break
    print(f"{name:<9} {len(nodes):<6} {emit:<10} {moved:<7} {sample or cite}{' ' + why if why else ''}")

  print(f"\nemittable:   {tally['emittable']} of {tally['total']} candidates")
  print(f"moved by ADEV-1: {tally['moved']} of {tally['total']} candidates")
  return 0


if __name__ == "__main__":
  sys.exit({"verdicts": verdicts, "blocked": blocked}[sys.argv[1]]())
