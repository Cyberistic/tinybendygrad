#!/usr/bin/env python
"""corpus_fresh.py -- RE-TAKE THE 34-GRAPH BYTE-IDENTICAL COUNT, IN THIS UNIT'S OWN DIRECTORY.

WHY NOT READ THE PUBLISHED ARTIFACTS. Two of them, both measured today:
  * `checks/rows/` held 68 files at 2026-10-09T16:11Z, 58 at ~16:14, 46, then 40 -- another
    unit is DELETING it while this one reads it. A count over a directory someone else is
    emptying is a count with a moving denominator.
  * `checks/rows-<graph>-<side>.rows` (69 files, stable) is `checks/census.py:64`'s OWN cache
    and it is STALE: its `rows-flip-bend.rows` carries the FLIP arg as `n(i1,i0)`, the
    PRE-`ABoolList` rendering, and its `rows-allred-bend.rows` holds a 13-node graph where
    the py side holds a 4-node one. Byte-diffing that set gives 10 of 34 identical, which
    describes a generation from before commit 73644b9c1 and not this tree.
So the number is re-taken here, from the harness itself, and written nowhere but here.

THE POPULATION is `graphcmp.GRAPHS` -- the generator's OWN declaration, loaded by path
(driving `graphcmp.py`'s `--graph` choices off the same dict), not a hand list.

MEMORY. Every `emit_bend` is a separate `bend` process, so the runs are SEQUENTIAL and the
sum precondition is never in question: one child at a time, ceiling 2048 MB, measured peaks
~650-680 MB against a 16 GB machine.
"""
import os, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[2]
OUT = HERE / "rows"
OUT.mkdir(exist_ok=True)
sys.path.insert(0, str(REPO / ".agents" / "slop"))

os.environ["DEV"] = "CPU"
import graphcmp as G  # noqa: E402

G.load_tinygrad()
GRAPHS = sorted(G.GRAPHS)  # the population, from the generator that owns it
LAUNCH = [".venv/bin/python", ".agents/slop/graphcmp.py", "emit"]


def emit(graph: str, side: str) -> tuple[str, str]:
  """Runs through `checks/bounded.py` so the verdict TOKEN is on stderr and the CHILD's
  bytes are the only thing in stdout -- a census must not count its own verdict."""
  p = subprocess.run(
    [".venv/bin/python", "checks/bounded.py", "--seconds", "300", "--mb", "2048", "--",
     *LAUNCH, "--graph", graph, "--side", side],
    cwd=REPO, capture_output=True, text=True, env={**os.environ, "PYTHONPATH": ""})
  token = next((w for w in ("WITHIN-LIMITS", "KILLED-ON-MEMORY", "TIMED-OUT")
                if w in p.stderr), "NO-TOKEN")
  return p.stdout, token


print(f"# population: len(graphcmp.GRAPHS) = {len(GRAPHS)}   repo: {REPO}", flush=True)
agree, differ, walls = [], [], []
for n in GRAPHS:
  py, tok_py = emit(n, "py")
  bd, tok_bd = emit(n, "bend")
  if tok_bd != "WITHIN-LIMITS" or tok_py != "WITHIN-LIMITS" or not py.strip() or not bd.strip():
    walls.append(f"{n}({tok_py}/{tok_bd},{len(py.splitlines())}/{len(bd.splitlines())})")
    print(f"  {n:<14} WALL", flush=True)
    continue
  (OUT / f"rows-{n}-py.rows").write_text(py)
  (OUT / f"rows-{n}-bend.rows").write_text(bd)
  same = py == bd
  (agree if same else differ).append(n)
  print(f"  {n:<14} py={len(py.splitlines()):<3} bend={len(bd.splitlines()):<3} "
        f"{'AGREE' if same else 'DIFFER'}", flush=True)

print()
print(f"graphs with both lanes : {len(agree) + len(differ)} of {len(GRAPHS)}")
print(f"BYTE-IDENTICAL         : {len(agree)}")
print(f"differ                 : {len(differ)}  -> {sorted(differ)}")
print(f"WALLS (not a verdict)  : {walls}")