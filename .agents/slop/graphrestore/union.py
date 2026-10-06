#!/usr/bin/env python3
"""THE CURRENT UNION AND THE PROPOSED ONE, SIDE BY SIDE. `.agents/slop/graphrestore/union.py`

    usage: .venv/bin/python .agents/slop/graphrestore/union.py [--dev CPU] [--sources]

WHAT THIS MEASURES, AND IT IS NOT EVERYTHING THE NAME SUGGESTS.  Both columns are built by
`gc.build(gc.emit_py(g, None), "py")` -- **CPYTHON'S** own op inventory. **THE PORT IS NEVER
INVOKED** on this path.  So:

    CURRENT  = set union over the 22 graphs `graphcmp.GRAPHS` declares today
    PROPOSED = the same union with `allred`, `cdiv`, `late` added back

Restoring three graphs therefore proves **CPYTHON-SIDE REACHABILITY**, which is a real claim
and NOT the port-coverage claim the 61/53 history conflated with it.  `--sources` prints the
`tinygrad/` `file:line` that constructs each newly-reached op, so the reader can see the
reachability is upstream's and not a fixture inventing a node.

WHY THE THREE FUNCTIONS ARE NOT IN `graphcmp.py` YET.  They were measured once, in commit
`db95da7bf` (2026-10-04), which is **NOT an ancestor of HEAD** -- a rebase line dropped them.
Their source is recovered from that commit into `restored.py` and exec'd into the differ's own
module namespace here, so the measurement runs the real `emit_py`/`build`/`ops_census` and not
a second implementation of them.
"""
from __future__ import annotations

import argparse
import importlib.util
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
RESTORED = ("allred", "cdiv", "late")


def load_graphcmp(dev: str | None = None):
    """Import the differ BY PATH and force its DEFERRED tinygrad imports.

    `graphcmp.py` defers every tinygrad import into `load_tinygrad()`. **Importing the module is
    not enough**: without the call every generator raises `NameError` and a union over zero
    built graphs prints `0 of 77` beside a healthy denominator -- the shape
    `checks/corpus-figure.py:44` documents.

    `dev` pins `DEV` BEFORE the deferred imports run, because **the union is a function of the
    host device** and the instrument `checks/corpus-figure.py` uses does not pin it.  MEASURED:
    with `DEV` unset this host resolves to `MetalDevice`/`MetalRenderer`, whose
    `code_for_op` has 21 keys and no `FDIV`, and `g_late` then emits `MUL(a, RECIPROCAL(b))`;
    with `DEV=CPU` -- the device `graphcmp.py` pins for the differ -- it emits `FDIV`.  One graph,
    one op, two answers, from an environment variable.
    """
    if dev:
        os.environ["DEV"] = dev
    spec = importlib.util.spec_from_file_location("gc", ROOT / ".agents/slop/graphcmp.py")
    gc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gc)
    gc.load_tinygrad()
    return gc


def install_restored(gc) -> list[str]:
    """Exec `restored.py`'s three generators into the differ's namespace, so they bind the SAME
    `Tensor`/`dtypes`/`UOp`/`Ops` the real graphs bind, and register them in `GRAPHS`.

    The registration is not optional: `emit_py` resolves the name through `GRAPHS`
    (`graphcmp.py:1405`), so a generator that exists but is not a `GRAPHS` entry raises
    `KeyError` -- which is how the first run of this script reported itself instead of
    printing a union over zero graphs.
    """
    ns = gc.__dict__
    code = (HERE / "restored.py").read_text()
    try:
        exec(compile(code, str(HERE / "restored.py"), "exec"), ns)
    except Exception as exc:                                   # a fixture that cannot load is a finding
        return [f"{type(exc).__name__}: {exc}"]
    for n in RESTORED:
        gc.GRAPHS[n] = ns[f"g_{n}"]
    return [n for n in RESTORED if n not in gc.GRAPHS]


def census(gc, name: str) -> tuple[dict[str, int] | None, str]:
    """`{op: node count}` for one graph's CPYTHON side, or `None` and a loud reason."""
    try:
        nodes = gc.build(gc.emit_py(name, None), "py")[0]
    except BaseException as exc:                               # SystemExit included: emit_py raises it
        tb = exc.__traceback__
        while tb is not None and tb.tb_next is not None:
            tb = tb.tb_next
        where = f"{tb.tb_frame.f_code.co_filename.split('/')[-1]}:{tb.tb_lineno}" if tb else "?"
        return None, f"{type(exc).__name__}: {exc} at {where}"
    return gc.ops_census(nodes), ""


def op_sites(op: str) -> tuple[list[str], list[str]]:
    """The `tinygrad/` sites that CONSTRUCT `op`, split from the sites that only NAME it.

    A coverage census that cannot tell a construction from a membership table is a census of
    names: `prepare.bend:369` names all 77 ops on one line and constructs none, and in `tinygrad`
    `ops.py:150` (`Ops.MSTACK | Ops.MSELECT | Ops.ALLREDUCE | ...`) is a guard arm, not a mint.
    So a line counts as a construction only when it CALLS a constructor with the op -- `UOp(Ops.X`,
    `.alu(Ops.X)` -- which is the form `UOp.alu` (`ops.py:627`) and `UOp(...)` both take.

    `tinygrad/renderer/**` AND `tinygrad/uop/render.py` are EXCLUDED, for the same reason: a
    backend maps an op to machine text and the pretty-printer maps it to source text, so
    `cstyle.py:149`'s `Ops.CDIV` and `render.py:107`'s `f"...alu(Ops.CDV...)"` are consumers of
    the op, not minters.  `render.py` needs the extra care that its `Ops.CDIV` sits INSIDE an
    f-string, so string literals are blanked before the line is matched -- otherwise a printer
    that prints `a.alu(Ops.CDIV, b)` reads as the call `a.alu(Ops.CDIV, b)`.
    """
    mint = re.compile(rf"(?:UOp|\.alu)\(\s*(?:Ops\.{op})\b")
    guard = re.compile(rf"^\s*(?:if|elif)\b.*\bOps\.{op}\b|\bOps\.{op}\b\s+in\s|\bis\s+Ops\.{op}\b")
    blanked = re.compile(r"""(".*?"|'.*?'|f".*?"|f'.*?')""")
    mints, guards = [], []
    for p in sorted((ROOT / "tinygrad").rglob("*.py")):
        rel = p.relative_to(ROOT)
        for i, ln in enumerate(p.read_text(errors="replace").splitlines(), 1):
            if ln.lstrip().startswith("#"):
                continue
            site = f"{rel}:{i}"
            code = blanked.sub(lambda m: " " * len(m.group(0)), ln)
            if mint.search(code):
                mints.append(site)
            elif guard.search(code):
                guards.append(site)
    codegen = [s for s in mints if s.startswith(("tinygrad/renderer/", "tinygrad/uop/render.py"))]
    return [s for s in mints if s not in codegen], guards


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sources", action="store_true", help="cite tinygrad/ construction sites")
    ap.add_argument("--dev", default=os.environ.get("DEV"),
                    help="pin DEV before the deferred tinygrad imports; unset = the host's device")
    args = ap.parse_args()

    gc = load_graphcmp(args.dev)
    if args.dev is None:
        from tinygrad.device import Device
        print(f"!! DEV IS UNSET -- this host resolves to "
              f"{type(Device.default.renderer).__name__}, and the union below is A FUNCTION OF "
              f"THE HOST DEVICE.  Pass --dev CPU for the device the differ pins.")
    bad = install_restored(gc)
    if bad:
        print(f"RESTORE FAILED: {bad}")
        return 2
    from tinygrad.uop.ops import Ops
    names = [o.name for o in Ops]

    # THE LEFT COLUMN IS THE 22-GRAPH CORPUS **EXCLUDING** THE THREE UNDER TEST, not whatever
    # `GRAPHS` happens to hold.  `graphcmp.py` now carries all 25, so `sorted(GRAPHS)` would make
    # the two columns IDENTICAL and print 61 beside 61: it measures nothing and it looks exactly
    # like a result -- the `0 of 77` shape `checks/corpus-figure.py:44` documents, one level up.
    # `install_restored` is still what puts the three on the SAME `emit_py` code path `graphcmp.py`
    # runs, so the right column is not measured by a second implementation.
    before = sorted(set(gc.GRAPHS) - set(RESTORED))
    cur: dict[str, int] = {}
    new: dict[str, int] = {}
    per: list[tuple[str, str, int, str, set[str]]] = []
    for kind, names_ in (("WITHOUT", before), ("RESTORED", RESTORED)):
        for g in names_:
            c, why = census(gc, g)
            seen = set(c) if c else set()
            per.append((g, kind, sum(c.values()) if c else 0, why, seen))
            if c is None:
                continue
            into = cur if kind == "WITHOUT" else new
            for op, k in c.items():
                into[op] = into.get(op, 0) + k

    proposed = set(cur) | set(new)
    gained = sorted(set(new) - set(cur))

    w = max(len(n) for n in names) + 2
    print(f"denominator len(Ops) = {len(names)}      "
          f"(measured live off tinygrad.uop.ops.Ops)")
    print(f"graphs WITHOUT the three : {len(before)}   "
          f"the three under test: {len(RESTORED)}   PROPOSED TOTAL: {len(before) + len(RESTORED)}")
    print()
    print(f"{'OP':<{w}}{'WITHOUT':>10}{'PROPOSED':>10}   {'VERDICT':<14}{'carried by'}")
    print("-" * (w + 46))
    for op in names:
        a, b = op in cur, op in proposed
        verdict = "reached" if (a and b) else ("GAINED" if b else "not reached")
        by = ",".join(g for g, kind, _, why, seen in per
                      if not why and op in seen and kind == ("RESTORED" if not a else "WITHOUT"))
        print(f"{op:<{w}}{str(a):>10}{str(b):>10}   {verdict:<14}{by}")
    print()
    print(f"CPYTHON-SIDE UNION over {len(before)} graphs          : {len(cur)} of {len(names)}")
    print(f"CPYTHON-SIDE UNION over {len(before) + len(RESTORED)} graphs PROPOSED: "
          f"{len(proposed)} of {len(names)}")
    print(f"GAINED by the three restored graphs ({len(gained)}): {' '.join(gained) or '(none)'}")
    print()
    print("PER-GRAPH, so the three fixtures are visible rather than asserted:")
    for g, kind, n, why, _ in per:
        print(f"  {kind:<9} {g:<10} nodes={n if not why else '-':<6} {why}")

    if args.sources:
        print("\nCONSTRUCTION SITES in tinygrad/ for each GAINED op -- a MINT is `UOp(Ops.X)` or "
              "`.alu(Ops.X)`, a NAME is a guard arm or a table:")
        for op in gained:
            mints, guards = op_sites(op)
            print(f"  {op}")
            for s in mints:
                print(f"      MINT  {s}")
            for s in guards:
                print(f"      name  {s}   (references it; constructs nothing)")
            if not mints:
                print("      MINT  **NONE -- no `UOp(Ops.X)` or `.alu(Ops.X)` site in tinygrad/**")
    return 0


if __name__ == "__main__":
    sys.exit(main())