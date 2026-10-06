#!/usr/bin/env python3
"""mints.py -- THE PORT GAP TEST: can the port BUILD a node carrying this op?

`classify.py` tested for a `def UOp.<snake>` minting METHOD and found two PORT GAPs (`ins`,
`unshard`). **That test is wrong, and measuring it wrong is what produced them.** A missing
convenience method is not a missing op: `schedule/multi.bend:2316` and `engine/jit.bend:1244`
call `UOp.new(..., OpsUNSHARD{}, ...)` directly, so the port BUILDS UNSHARD nodes inside its
own scheduling rules while `uop/ops.bend:4718` still carries `# TODO(p3) ops.py:689 def
unshard`. `ops.bend:4658` (`def ins`) and `:4669` (`def wmma`) are worse -- those TODO markers
are STALE, because `ops.bend:6865` and `:6873` implement both, documented against the same
`ops.py:622` / `ops.py:649` lines. **The port's own not-ported inventory is a measurement
too, and it has aged.**

So the honest test is the WIDEST one: a non-comment site that constructs `Ops<NAME>{}`. Zero
such sites means the port cannot put the op in a graph at all, and that -- not the absence
of a method -- is what a corpus graph could never compare.

  vault.  `tinybendygrad/uop/ops.staged-blob-*` are four STALE COPIES of `ops.bend` sitting
          in the port tree. They are EXCLUDED here and the exclusion is counted, because
          `port-presence.py` (which did not exclude them) inflated several ops' match counts
          by roughly 4x.

    env -u PYTHONPATH .venv/bin/python .agents/slop/corpus24/mints.py
"""
from __future__ import annotations

import collections
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"
BLOB = re.compile(r"\.staged-blob-\d+$")


def missing_ops() -> list[str]:
    ms = importlib.util.spec_from_file_location("cf", ROOT / "checks/corpus-figure.py")
    cf = importlib.util.module_from_spec(ms)
    ms.loader.exec_module(cf)
    gc = cf.load_graphcmp()
    from tinygrad.uop.ops import Ops
    union: set[str] = set()
    for g in sorted(gc.GRAPHS):
        try:
            union |= {n.op for n in gc.build(gc.emit_py(g, None), "py")[0].values()}
        except Exception:
            continue
    return [o.name for o in Ops if o.name not in union]


def main() -> int:
    ops = missing_ops()
    allf = sorted(p for p in PORT.rglob("*.bend") if p.is_file())
    blobs = [p for p in allf if BLOB.search(p.name)]
    files = [p for p in allf if not BLOB.search(p.name)]
    print(f"# .bend files: {len(allf)}   EXCLUDED stale staged-blob copies: {len(blobs)}")
    for b in blobs:
        print(f"#   excluded: {b.relative_to(ROOT)}")

    # A MINT is a non-comment line that CONSTRUCTS a node: the `Ops<NAME>{}` case must sit
    # on a line that also opens a node/arg constructor. Requiring `UOp.new(` / `Node{` /
    # `Found{` is what separates a CONSTRUCTION from a MEMBERSHIP TABLE, and the
    # difference is large: `schedule/prepare.bend:369` names all 77 ops on one line and
    # constructs none of them. The loose count ("the op appears in non-comment code") called
    # CUSTOM a mint on the strength of `codegen/decomp/dtype.bend:1987`, which is a table.
    CTOR = re.compile(r"UOp\.new\(|Node\{|Found\{")
    mints: dict[str, list[str]] = collections.defaultdict(list)
    tables: dict[str, list[str]] = collections.defaultdict(list)
    for p in files:
        for i, ln in enumerate(p.read_text(errors="replace").splitlines(), 1):
            if ln.lstrip().startswith("#"):
                continue
            for op in ops:
                if f"Ops{op}{{}}" not in ln:
                    continue
                (mints if CTOR.search(ln) else tables)[op].append(
                    f"{p.relative_to(ROOT)}:{i}")

    print()
    print(f"{'OP':<16} {'CONSTRUCT':<10} {'MATCH/TABLE-ONLY':<17} WHERE IT IS BUILT")
    n_nomint = 0
    for op in ops:
        s = mints[op]
        if not s:
            n_nomint += 1
        shown = " ".join(x.replace("tinybendygrad/", "") for x in s[:3])
        print(f"{op:<16} {len(s):<10} {len(tables[op]):<17} "
              f"{shown}{' ...' if len(s) > 3 else ''}")
    print()
    print(f"# ops with NO construction site (PORT GAP): {n_nomint} of {len(ops)}")
    for op in ops:
        if not mints[op]:
            print(f"#   {op}  (referenced in {len(tables[op])} table/match lines only)")
    return 0


if __name__ == "__main__":
    sys.exit(main())