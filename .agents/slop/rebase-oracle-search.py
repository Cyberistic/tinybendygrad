#!/usr/bin/env python3
"""rebase-oracle-search.py -- the CPython oracle for `tinybendygrad/codegen/opt/search.bend`,
AND THE ROW THAT SAYS WHY IT RUNS AGAINST THE UPSTREAM TREE.

THE FINDING THIS ORACLE EXISTS TO SURFACE, and it is the reason the file is worth having:

    tinygrad/codegen/opt/search.py IN THE VENDORED TREE DOES NOT IMPORT.

Line 15 reads `AxisType.UNROLL`, and upstream DELETED `AxisType.UNROLL` and
`AxisType.REDUCE` (`ops.py`'s `AxisType` has eight members now). Upstream's own
`search.py` was updated in the same commit -- `for at in (AxisType.UPCAST, AxisType.UNROLL)`
became `AxisType.UPCAST` -- and the vendored copy was not, so the re-vendor is half done
and `import tinygrad.codegen.opt.search` raises. `rebase-plan.py` recorded `actions` as
CHANGED for this file, so the drift was known to the plan and invisible to every gate.

THE MEASURED CONSEQUENCE, which is the whole value of this oracle:

    row        port     upstream CPython
    acts_n      269          209        60 entries fewer: the UNROLL group's 6 amts x 10 axes
    acts_zero    28           18        10 fewer: UNROLL's 10 amt-0 entries
    zero_un9      1        ABSENT      AxisType.UNROLL does not exist at HEAD
    zero_red0     0        ABSENT      AxisType.REDUCE does not exist at HEAD

So FOUR rows of this port gate a table upstream has deleted a third of, and two of them
gate an enum member that no longer exists. Reported, NOT FIXED: `tinygrad/` belongs to the
re-vendor and `codegen/opt/*` to a live agent.

WHICH TREE. `TG_TREE` picks it, exactly as `ops-gate.sh` does, and it defaults to the
upstream archive snapshot `.agents/slop/opstree` because that is the tree the rebase is
heading for and it is the only one of the two that can be asked. The vendored tree's failure
is not swallowed: it is printed as the `#repro_vendored_import` row, so the tree's own
importability is a row and not a footnote.

WHAT IS NOT HERE, and why. Six rows -- `dropped`, `drop_ok`, `drop_seen`, `keep_ok`,
`least_lo`, `least_hi` -- are rows over the PORT'S OWN `SCORE` fixture table and its own
two-argument `drop`/`min2` predicates. `least_lo=5` from `least_of(True{}, 5, 9)` restates
the def under test; CPython's `min()` is a different function and agreeing with it would be
the `nv/ip` mistake. They are unrefutable here and are not claimed.

    DEV=NULL .venv/bin/python .agents/slop/rebase-oracle-search.py
"""
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
TREE = pathlib.Path(os.environ.get("TG_TREE") or (HERE / "opstree")).resolve()
PY = REPO / ".venv" / "bin" / "python"

# The rows are computed by CPython in a CHILD whose sys.path is the chosen tree. In-process
# would be one import fewer, but then the oracle could only ever describe whichever tree
# happened to be on `sys.path` -- and which tree it described is the whole question here.
CHILD = r'''
import sys
sys.path.insert(0, sys.argv[1])
from tinygrad.codegen.opt.search import actions
from tinygrad.uop.ops import AxisType
from tinygrad.codegen.opt import OptOps
def emit(n, v): print(f"{n}={v}")
def zero_variant(at_name, top, axis):
  at = getattr(AxisType, at_name, None)
  if at is None: return "ABSENT"
  for a in actions:
    if a.op is not OptOps.SPLIT or a.axis != axis or not isinstance(a.arg, tuple): continue
    if a.arg[0] != 0 or a.arg[1] is not at: continue
    if (bool(a.arg[2]) if len(a.arg) > 2 else False) == top: return 1
  return 0
emit("acts_n", len(actions))
emit("acts_zero", sum(1 for a in actions if a.op is OptOps.SPLIT and isinstance(a.arg, tuple) and a.arg[0] == 0))
for nm, at, top, ax in (("zero_up0","UPCAST",False,0), ("zero_up9","UPCAST",False,9),
                        ("zero_un9","UNROLL",False,9),
                        ("zero_lcl7","LOCAL",False,7), ("zero_lcl9","LOCAL",False,9),
                        ("zero_top0","LOCAL",True,0), ("zero_top9","LOCAL",True,9),
                        ("zero_up10","UPCAST",False,10), ("zero_red0","REDUCE",False,0)):
  emit(nm, zero_variant(at, top, ax))
for at in ("UPCAST","UNROLL","LOCAL"):
  for top in (False, True):
    a = getattr(AxisType, at, None)
    if a is None: emit(f"#repro_split_{at}_top{int(top)}", "AxisType.ABSENT"); continue
    axes = sorted({x.axis for x in actions if x.op is OptOps.SPLIT and x.arg[1] is a
                   and (bool(x.arg[2]) if len(x.arg) > 2 else False) == top})
    amt0 = sum(1 for x in actions if x.op is OptOps.SPLIT and x.arg[1] is a and x.arg[0] == 0
               and (bool(x.arg[2]) if len(x.arg) > 2 else False) == top)
    emit(f"#repro_split_{at}_top{int(top)}",
         f"group={len(axes)} amt0={amt0} axes={'|'.join(map(str, axes)) or '-'}")
'''

LEN_SRC = ("import sys; sys.path.insert(0, sys.argv[1])\n"
           "from tinygrad.codegen.opt.search import actions\nprint(len(actions))\n")


def child(src, extra_env=None, label=""):
  e = dict(os.environ, DEV="NULL", **(extra_env or {}))
  c = subprocess.run([str(PY), "-c", src, str(TREE)], cwd=REPO, capture_output=True,
                     text=True, env=e)
  if c.returncode != 0:
    tail = (c.stderr.strip().splitlines() or ["?"])[-1]
    raise SystemExit(f"rebase-oracle-search: the {label} child DIED rc={c.returncode}\n"
                     f"  tree: {TREE}\n  {tail}")
  return c.stdout


def main():
  print(f"#repro_tree={TREE.relative_to(REPO) if TREE.is_relative_to(REPO) else TREE}")
  print("#repro_vendored_import=" + vendored_import_state())
  out = child(CHILD, label="rows")
  rows = dict(line.split("=", 1) for line in out.splitlines() if "=" in line)
  for k, v in rows.items():
    print(f"{k}={v}")
  # LAST, because it is the row whose value costs a second import and no other row needs it.
  print(f"acts_n_padto={len_actions_with_padto()}")
  return 0


def vendored_import_state():
  """Whether the VENDORED `tinygrad/codegen/opt/search.py` imports, and if not, the line.

  This is a ROW and not a comment because it is the defect: the tree claims a file CPython
  cannot execute, and every gate that imports it answers nothing while exiting 0."""
  e = dict(os.environ, DEV="NULL")
  c = subprocess.run(
    [str(PY), "-c", "from tinygrad.codegen.opt.search import actions; print(len(actions))"],
    cwd=REPO, capture_output=True, text=True, env=e)
  if c.returncode == 0:
    return f"OK:{c.stdout.strip()}"
  last = (c.stderr.strip().splitlines() or ["?"])[-1]
  return last.replace("|", "/").replace("=", "~")[:200]


def len_actions_with_padto():
  return int(child(LEN_SRC, {"BEAM_PADTO": "1"}, label="BEAM_PADTO=1").strip().splitlines()[-1])


if __name__ == "__main__":
  sys.exit(main())