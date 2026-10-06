#!/usr/bin/env python3
"""MEASURE injectivity of `_carg` on the 25 graphs' rows. Read-only; runs no `bend`.

`graphcmp.py:672` renders a dataclass as `Type(f1=v1f2=v2...)` -- fields joined by `""`, not
by `,`. Two distinct dataclass instances would then print the same string and the differ
would call that AGREE. This measures whether the collision is REACHABLE on the corpus's own
rows, not whether the grammar merely permits it.

THE MEASUREMENT IS OVER THE ROWS. For every dataclass value the 25 graph definitions reach,
both spellings are recorded: `_carg`'s (`""`-joined, the one the differ compares) and a
`,`-joined structure (the same reading with the field boundary made visible). Injectivity is
then: does any one `""`-joined string stand for two different `,`-joined structures?

TWO THINGS THIS FILE MUST NOT REPEAT, both measured on its first run:
  * the module is loaded as `gcmp`, NOT as `gc`. `gc` is the stdlib garbage collector, and
    naming it `gc` gave `AttributeError: module 'gc' has no attribute 'isenabled'` on 4 of
    25 graphs -- a failure that looks like a port defect and is entirely the probe's.
  * `structure` mirrors `_carg`'s OWN ARM ORDER (`graphcmp.py:599-681`), including the enum
    arm before the `__dict__` arm. A `structure` that walked `__dict__` freely followed
    `__objclass__` out of the value into its class and recursed forever on all 25 graphs --
    which is precisely the defect `graphcmp.py:578-590` documents and the enum arm exists
    to stop. The lesson is the file's own: a fallback that does not stop at the value.
"""
from __future__ import annotations

import collections
import importlib.util
import json
import os
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
os.environ["DEV"] = "CPU"

spec = importlib.util.spec_from_file_location("gcmp", ROOT / ".agents/slop/graphcmp.py")
gcmp = importlib.util.module_from_spec(spec)
sys.modules["gcmp"] = gcmp
spec.loader.exec_module(gcmp)
gcmp.load_tinygrad()


def structure(x, depth: int = 0) -> str:
    """`_carg` with the dataclass join changed from `""` to `,`. EVERY OTHER ARM IS COPIED,
    including its ORDER, so the two readings differ ONLY at the field boundary -- which is
    the whole claim. `depth` is a refusal, not a cap: an object reached this deep is reported
    as `deep(...)` rather than silently truncated, because a silent truncation would make two
    different objects agree."""
    if depth > 12:
        return "deep(" + type(x).__name__ + ")"
    if x is None:
        return "N"
    if isinstance(x, gcmp.DType):
        return "D" + x.name
    if isinstance(x, gcmp.Ops):
        return "O" + x.name
    if isinstance(x, gcmp.AxisType):
        return "X" + x.name
    if isinstance(x, gcmp.AddrSpace):
        return "A" + x.name
    if isinstance(x, __import__("enum").Enum):
        return f"E{type(x).__name__}.{x.name}"
    if isinstance(x, bool):
        return "b1" if x else "b0"
    if isinstance(x, int):
        return "i" + str(x)
    if isinstance(x, float):
        return "f" + repr(x)
    if isinstance(x, str):
        return "s" + x
    if isinstance(x, bytes):
        return "y n(" + ",".join("i" + str(b) for b in x) + ")"
    if isinstance(x, (tuple, list)):
        return "n(" + ",".join(structure(e, depth + 1) for e in x) + ")"
    if isinstance(x, gcmp.UOp):
        return "u"
    if isinstance(x, gcmp.ParamArg):
        return structure(x.__dict__, depth + 1) if False else "P(...)"   # its own arm; see paramarg
    if hasattr(x, "__dataclass_fields__"):
        return type(x).__name__ + "(" + ",".join(
            f"{n}={structure(getattr(x, n), depth + 1)}" for n in x.__dataclass_fields__) + ")"
    d = getattr(x, "__dict__", None)
    if d is None:
        return f"raw({type(x).__name__})"
    return type(x).__name__ + "(" + ",".join(
        f"{k}={structure(v, depth + 1)}" for k, v in d.items() if k != "grad_fxn") + ")"


# Every dataclass value reached, rendered BOTH ways.
PAIRS: list[tuple[str, str, str, str]] = []      # (_carg, structure, typename, graph)
ORIG = gcmp._carg
CUR = ["?"]


def spy(x) -> str:
    s = ORIG(x)
    if (hasattr(x, "__dataclass_fields__")
            and not isinstance(x, gcmp.ParamArg) and not isinstance(x, gcmp.UOp)):
        PAIRS.append((s, structure(x), type(x).__name__, CUR[0]))
    return s


gcmp._carg = spy

rows_total = 0
graphs_ok: list[str] = []
graphs_failed: dict[str, str] = {}
for g in sorted(gcmp.GRAPHS):
    CUR[0] = g
    try:
        rows = gcmp.emit_py(g, None)
    except Exception as exc:
        graphs_failed[g] = f"{type(exc).__name__}: {exc}"
        continue
    rows_total += len(rows)
    graphs_ok.append(g)

by_string: dict[str, set[str]] = collections.defaultdict(set)
seen_at: dict[str, set[str]] = collections.defaultdict(set)
for s, st, tn, g in PAIRS:
    by_string[s].add(st)
    seen_at[s].add(f"{tn}@{g}")

collisions = {s: v for s, v in by_string.items() if len(v) > 1}

print(f"graphs emitted          : {len(graphs_ok)} of {len(gcmp.GRAPHS)}")
for g, why in graphs_failed.items():
    print(f"    FAILED {g}: {why}")
print(f"rows                    : {rows_total}")
print(f"dataclass renderings    : {len(PAIRS)}")
print(f"distinct ''-joined strs : {len(by_string)}")
print(f"distinct ','-structures : {len({st for _, st, _, _ in PAIRS})}")
print(f"COLLISIONS              : {len(collisions)}")
for s, v in sorted(collisions.items()):
    print(f"  {s}")
    for st in sorted(v):
        print(f"      <= {st}")

# THE GRAMMAR PROBE: two different field MAPS, one `""`-joined spelling. This is not a
# corpus finding; it is the demonstration that the join is the defect, shown on the corpus's
# own `Opt` spelling so no reader has to take the claim on faith.
print("\nGRAMMAR PROBE -- one `''`-joined spelling, two field maps:")
for fields in ({"op": "EOptOps.SPLIT", "axis": "i2", "arg": "n(i0,XUPCAST)"},
               {"op": "EOptOps.SPLITax", "is": "i2", "arg": "n(i0,XUPCAST)"}):
    joined = "".join(f"{k}={v}" for k, v in fields.items())
    print(f"  Opt({joined})   <- {fields}")

out = {
    "graphs_emitted": len(graphs_ok),
    "graphs_failed": graphs_failed,
    "rows": rows_total,
    "renderings": len(PAIRS),
    "distinct_strings": len(by_string),
    "distinct_structures": len({st for _, st, _, _ in PAIRS}),
    "collisions": {s: sorted(v) for s, v in collisions.items()},
    "collision_at": {s: sorted(v) for s, v in seen_at.items() if len(v) > 1},
}
dest = pathlib.Path(__file__).with_name("injectivity.json")
dest.write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")
print(f"\nwrote {dest}")
sys.exit(1 if collisions else 0)