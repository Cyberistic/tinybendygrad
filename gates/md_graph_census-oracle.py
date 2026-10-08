#!/usr/bin/env python3
"""md_graph_census-oracle.py -- CPython's OP SEQUENCE for the graph-building dtype methods.

    .venv/bin/python gates/md_graph_census-oracle.py

THE SAME 22 ROWS `gates/md_graph_census.bend` PRINTS, FROM CPYTHON. The bend lane drives the
port's `cast_at` / `bitcast_at` / the eight named casts; this lane drives the `DTypeMixin`
METHOD each one mirrors, so a divergence is a SHAPE divergence and not a prose claim.

THE POPULATION IS DISCOVERED, NOT LISTED. A port def is a row iff `tinygrad/mixin/dtype.py`
defines the method it mirrors. `DTypeMixin`'s sixteen names less the three abstract
declarations (`dtype`, `_uop`, `_wrap_uop`, all `raise NotImplementedError`) leaves THIRTEEN
methods; three are READERS (`commit_dtype`, `element_size`, `is_floating_point`) and build no
graph, so ten build graphs:

    cast, bitcast, float, half, int, bool, bfloat16, double, long, short.

THE FIXTURE IS A BARE CONST, MATCHING THE PORT'S ARENA. `Tensor(UOp(Ops.CONST, src=(), arg=v))`
is the node the port's `O.UOp.const` builds; `T(3)` is weakint, `T(1.0)` is weakfloat, `T(True)`
is bool, and `T(3).cast(dtypes.int32)` is the concrete int32 source -- the same chain the port's
`world()` builds. The concrete source exists because `UOp.const` of an int is ALWAYS weakint.

THE SIGNATURE IS `Rng.sig` PLUS THE ROOT ARG. `Rng.sig` prints the toposort length, the root op
and its src count and the src op sequence; a CAST's whole point is its arg, so the arg's dtype
NAME is appended. CPython's `DType.name` and the port's `S.Dt` `nm` are the same table -- `f16`,
`f32`, `i32`, ... -- measured; a root with no `DType` arg prints `-`.

THE TWO REFUSAL ROWS. `bitcast` RAISES on a weak dtype where `cast` does not. The port models
the raise as `None` (no Bend spelling for a `RuntimeError`), so the port prints `None` and this
lane prints the exception's NAME. That is a declared carve-out, pinned in the gate.
"""

from tinygrad.dtype import DType, dtypes
from tinygrad.uop.ops import Ops, UOp
from tinygrad.tensor import Tensor


def seq(u, seen=None, out=None):
    if seen is None:
        seen, out = set(), []
    if id(u) in seen:
        return out
    seen.add(id(u))
    for s in u.src:
        seq(s, seen, out)
    out.append(u.op.name)
    return out


def sig(r) -> str:
    s = seq(r.uop)
    srcs = " ".join("Ops." + u.op.name for u in r.uop.src)
    arg = r.uop.arg.name if isinstance(r.uop.arg, DType) else "-"
    return f"{len(s)} Ops.{r.uop.op.name}/{len(r.uop.src)} {srcs} arg={arg}"


def T(arg):
    return Tensor(UOp(Ops.CONST, src=(), arg=arg), device="PYTHON")


def wi():
    return T(3)


def wf():
    return T(1.0)


def bl():
    return T(True)


def i32():
    return T(3).cast(dtypes.int32)


def half():
    return T(1.0).cast(dtypes.float16)


def raised(fn) -> str:
    """The NAME of the exception a refused bitcast raises -- CPython's answer to `None`."""
    try:
        fn()
        return "NONE-RAISED"
    except Exception as e:
        return type(e).__name__


# --- `cast` (dtype.py:19) -------------------------------------------------
print(f"cast_weak_to_f32={sig(wi().cast(dtypes.float32))}")
print(f"cast_same_weakint={sig(wi().cast(dtypes.weakint))}")
print(f"cast_weakfloat_to_i32={sig(wf().cast(dtypes.int32))}")
print(f"cast_wf_same={sig(wf().cast(dtypes.weakfloat))}")
print(f"cast_bool_to_i32={sig(bl().cast(dtypes.int32))}")
print(f"cast_concrete_to_f32={sig(i32().cast(dtypes.float32))}")
print(f"cast_concrete_same={sig(i32().cast(dtypes.int32))}")
print(f"cast_weak_to_weakfloat={sig(wi().cast(dtypes.weakfloat))}")

# --- `bitcast` (dtype.py:38) ---------------------------------------------
print(f"bitcast_concrete_to_u32={sig(i32().bitcast(dtypes.uint32))}")
print(f"bitcast_concrete_same={sig(i32().bitcast(dtypes.int32))}")
print(f"bitcast_weak_src={raised(lambda: wi().bitcast(dtypes.int32))}")
print(f"bitcast_weak_dst={raised(lambda: i32().bitcast(dtypes.weakfloat))}")

# --- the eight named casts (dtype.py:79-142) -----------------------------
print(f"cast_float={sig(wi().float())}")
print(f"cast_half={sig(wi().half())}")
print(f"cast_int={sig(wi().int())}")
print(f"cast_bool={sig(wi().bool())}")
print(f"cast_bfloat16={sig(wi().bfloat16())}")
print(f"cast_double={sig(wi().double())}")
print(f"cast_long={sig(wi().long())}")
print(f"cast_short={sig(wi().short())}")

# --- the two identity rows -----------------------------------------------
print(f"cast_half_same={sig(half().half())}")
print(f"cast_bool_same={sig(bl().bool())}")
