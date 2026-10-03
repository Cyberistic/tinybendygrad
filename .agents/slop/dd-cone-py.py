#!/usr/bin/env python3
"""dd-cone-py.py -- CPython's CONE for one named `l2i` row, with LABELS and srcs.

dd-gap.py diffs two `sig` strings as `op/nsrc` MULTISETS, which names a missing node's
OP but not WHICH node it is: a `CMPLT` in a 2431-node cone is 2431 candidates. This
prints `position  op/nsrc  label  <- srcs` for the cone of the row you name.

IT RE-RUNS dd-oracle.py's `L2I()` TABLE IN ORDER, not just the row you name, because
the table's rows share one interning session and `UOp.const(i, dtypes.uint)` is interned
by the first row that needs it. Running `lgq` alone would report a cone CPython's own
gate never sees.

dd-oracle.py's `main()` INLINES its `l2i` loop rather than calling `run()`, so patching
`run` does not reach it; this file walks `L2I()` itself.

  dd-cone-py.py lgq [LO HI]
"""
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))
spec = importlib.util.spec_from_file_location("dd_oracle_calls", HERE / "dd-oracle.py")
M = importlib.util.module_from_spec(spec)
sys.modules["dd_oracle_calls"] = M
spec.loader.exec_module(M)

WANT = sys.argv[1] if len(sys.argv) > 1 else "lgq"
LO = int(sys.argv[2]) if len(sys.argv) > 2 else 0
HI = int(sys.argv[3]) if len(sys.argv) > 3 else 10 ** 9

for nm, op, dt, xdt, n in M.L2I():
    w = M.ws(xdt, n)
    b = len(M.ORDER)
    try:
        r = M.DD.l2i(op, dt, *w)
    except Exception:
        continue
    r = r if isinstance(r, tuple) else (r,)
    if nm != WANT:
        continue
    c = M.cone(list(r))
    print(f"# {nm} cone {len(c)} nodes  window {b}..{len(M.ORDER)}")
    for i, u in enumerate(c):
        if not (LO <= i < HI):
            continue
        srcs = ",".join(f"{s.op.name}:{M.lab(s)}" for s in u.src)
        print(f"{i}\t{u.op.name}/{len(u.src)}\t{M.lab(u)}\t<- {srcs}")