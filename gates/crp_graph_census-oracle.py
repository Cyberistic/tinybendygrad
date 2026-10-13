#!/usr/bin/env python3
"""crp_graph_census-oracle.py -- CPython's DEEP CONE for every row of
`gates/crp_graph_census.bend`, taken from the REAL `tinygrad/mixin/creation.py`.

    .venv/bin/python gates/crp_graph_census-oracle.py

THIS LANE CALLS THE REAL THING. Every row is a call into `creation.py` itself --
`Tensor.empty`, `Tensor.invalids`, `Tensor.full`, `Tensor.zeros`, `Tensor.ones`, and the
instance methods `empty_like`, `full_like`, `zeros_like`, `ones_like`, `const_like` -- on a
receiver and a dtype the fixture ARGUMENTS for and states here. Nothing here reimplements a
cast, a promotion, a fold or a reshape.

THE `tn_bitwise_not` POST-MORTEL APPLIES, TWICE, AND BOTH TIMES TO THE RECEIVER.

  * `gates/tn_bitwise_not-oracle.py` hand-built `cast.ne(True)` instead of calling
    `Tensor.bitwise_not()`, so driver and oracle both minted the CAST CPython folds.
  * `gates/decomp_graph_census-oracle.py` built `f2f`'s fixture at `float32` instead of
    `fr`, and a defect that was really the ORACLE's lived as a FINDING for a session.
  * HERE: `Tensor.zeros(shape, dtype=dt)` is NOT a receiver of dtype `dt`. `full` builds
    its buffer with `commit_dtype()` (creation.py:86), so a buffered `zeros(dtype=weakint)`
    is an **i32** tensor, and `rx(weakint).const_like(1)` came out carrying a `CAST/1`
    where a real weakint receiver has none. MEASURED, both ways:
        Tensor.zeros((2,3), dtype=dt)                 -> .dtype == commit_dtype(dt)
        Tensor.zeros((2,3), dtype=dt, buffer=False)    -> .dtype == dt   [ALL 20]
    So `rx(dt)` is `buffer=False`, and `receiver_hold()` in the gate re-measures it on every
    run -- a fixture that quietly loses the property it exists for is a fixture that agrees
    for the wrong reason.

THE CONSTANTS ARE CPYTHON'S OWN `DType.const`, NOT TRANSCRIBED. `creation.bend`'s fact 3
is that `cr_full`'s `fill_value` arrives ALREADY TRUNCATED, because `DType.const`'s
`truncate` (dtype.py:79-84, fp16 rounding included) is a P3 wall. Transcribing that
truncation into the FIXTURE would be the `tn_bitwise_not` failure with a different
spelling: the oracle would assert its own reading of dtype.py and agree with it. So the
value here is `dt.const(1)` -- the real method -- and the port's is `cr_cval1`, its own
`DType.const` arms, called.

THE SIGNATURE IS THE WHOLE CONE, in `UOp.toposort`'s OWN ORDER, with the CONST's VALUE and
the ALLOC's `ParamArg`. `rng_graph_census-gate.py` and `realize_graph_census-oracle.py` both
name that instrument's own failure -- `Rng.sig` is a 3-op PREFIX with no ARG, and `gr_10`
printed identically on both sides until a deep printer was used -- and `creation.bend`'s
header says the same of ITS gate: "THE FLOAT ARM IS THE SILENT ONE: there both consts cast,
so the COUNT agrees and only the CONST's ARG differs, which `Rng.sig` did not print before
this session." Three facts are only in the deep form: the FOLD (`CONST/0` versus
`CONST/0,CAST/1`), the ALLOC's DTYPE (`full`'s `dt if dt not in weaks else commit_dtype()`)
and the CONST's own VALUE (`ConstFloat(truncate[dt](v))` / `bool(v)` / `int(v)`).

NOTHING IS EXECUTED AND NO REAL GRAPH IS NEEDED: every row is the SIGNATURE of the lazy
graph, which is why a 207-row census runs with no device work.
"""

import re
import struct
from pathlib import Path

from tinygrad import dtypes
from tinygrad.dtype import DType, Invalid
from tinygrad.tensor import Tensor
from tinygrad.uop.ops import Ops

ROOT = Path(__file__).resolve().parent.parent
DEV = "PYTHON"
SHAPE = (2, 3)

# ============================================================================ THE AXES
# THE DTYPE AXIS IS DISCOVERED, NOT LISTED, AND IT IS DISCOVERED IN THE PORT'S OWN FILE
# ORDER -- `LAWS/spec.bend`'s twenty `def <n>() -> Dt: Dt{<pri>, <bits>, ...}` constructors,
# in the order they are written. That is `realize_graph_census-oracle.py`'s fixture-mirror
# shape, and the mirror is what makes the ORDER a contract rather than a second choice:
# `gatekit` diffs the lanes LINE BY LINE, and `DType.priority` cannot supply the order
# because `void`, `bool` and `weakint` all share one (MEASURED: -1, 0, 0).
#
# `dtypes_hold()` IN THE GATE closes the mirror: it compares this set against
# `dir(dtypes)`'s `DType`s, against the ROW NAMES this lane printed, and field by field
# against `spec.bend`'s `<pri>` and `<bits>` -- so a renamed dtype, a renumbered priority or
# a dropped constructor is a red run rather than a shorter lane.
SPEC = ROOT / "tinybendygrad" / "LAWS" / "spec.bend"
SPEC_DT = re.compile(r"^def ([a-z_0-9]+)\(\) -> Dt: Dt\{([0-9]+), ([0-9]+),", re.M)
# `void`'s priority is the ONE FIELD THE TWO FILES DISAGREE ON: CPython's is -1 and
# `spec.bend`'s is 0. MEASURED, and `dtypes_hold()` asserts that the set of disagreeing
# fields is exactly {void.priority}, so a SECOND disagreement is a red run.
PRI_OFF = {"void"}
# `spec.bend`'s CONSTRUCTOR NAME IS NOT `DType.name` AND NOT A SUFFIX RULE. Fourteen of the
# twenty differ: `boolean single double half bfloat16 int8 uint8 int16 uint16 int32 uint32
# int64 uint64` against `bool float32 float64 f16 bf16 i8 u8 i16 u16 i32 u32 i64 u64`. The
# first version of this map carried THREE of them and the `--refresh` failed with
# `KeyError: 'zl_int8'` -- which is `names_hold`'s whole argument: a mirror that is nearly
# right is a mirror that silently covers the wrong names. ALL TWENTY ARE NAMED HERE, and
# `dtypes_hold()` checks the set against `dir(dtypes)` on every run.
ALIAS = {"void": "void", "weakint": "weakint", "boolean": "bool", "int8": "i8", "uint8": "u8",
         "int16": "i16", "uint16": "u16", "int32": "i32", "uint32": "u32", "int64": "i64",
         "uint64": "u64", "weakfloat": "weakfloat", "fp8e4m3": "fp8e4m3",
         "fp8e4m3fnuz": "fp8e4m3fnuz", "fp8e5m2": "fp8e5m2", "fp8e5m2fnuz": "fp8e5m2fnuz",
         "half": "f16", "bfloat16": "bf16", "single": "f32", "double": "f64"}


def dtypes_():
    """`spec.bend`'s dtype constructors, in FILE order, resolved to CPython's `DType`s.

    THE EMPTY POPULATION IS REFUSED, NOT RETURNED. MEASURED, and it is worth writing
    down: the first draft of this regex had no `re.MULTILINE`, so `^` matched once in a
    5000-line file, `findall` returned `[]`, and this lane printed TWENTY-SEVEN of its 207
    rows and **exited 0**. A population that discovers as empty and says nothing is a lane
    that measured nothing and reported success -- the shape
    `rebase-gate-selftest.py:1168` documents as "compared nothing". Two things catch it and
    both are here: `SystemExit` below names it at the point it happens, and `gatekit`'s row
    COUNT refuses the short lane whatever this file does. The first is the diagnosis and the
    second is the backstop, and neither replaces the other."""
    hits = SPEC_DT.findall(SPEC.read_text())
    if not hits:
        raise SystemExit(f"{SPEC} has no `def <n>() -> Dt: Dt{{` constructor -- the dtype "
                         f"population discovered EMPTY, which is not a measurement")
    out = []
    for nm, _pri, _bits in hits:
        d = getattr(dtypes, ALIAS.get(nm, nm), None)
        if not isinstance(d, DType):
            raise SystemExit(f"spec.bend's {nm!r} is not a dtypes attribute -- the mirror is stale")
        out.append(d)
    return out


DTNAMES = tuple(d.name for d in dtypes_())
SHAPES = ((), (4,), (2, 3), (2, 3, 4))


def rx(dt):
    """THE RECEIVER, and `buffer=False` IS THE WHO OF IT. MEASURED: `.dtype == dt` for all
    twenty dtypes this way, and `commit_dtype()`'s answer -- not `dt` -- the other way. This
    is `realize_graph_census-oracle.py`'s rule that a fixture dtype is a named, argued
    field of the oracle rather than a convenience."""
    return Tensor.zeros(SHAPE, dtype=dt, buffer=False, device=DEV)


# ========================================================================= THE PRINTER
def cval(u) -> str:
    """`CONST/0[<value>:<derived dtype>]`. The DERIVED dtype is `UOp.dtype`, i.e.
    `dtype_from_uop` (ops.py:183-189) -- bool for `InvalidType` and for bool, weakint for
    int, weakfloat for float -- and the port prints `cr_from_py`, i.e.
    `dtypes.from_py` (dtype.py:100-106), which answers the same three. So the lane diff is
    a real check that the two tables agree and not a restatement of one of them."""
    a = u.arg
    if isinstance(a, type(Invalid)):
        v = "Invalid"
    elif isinstance(a, bool):
        v = repr(a)
    elif isinstance(a, float):
        # THE IEEE-754 PATTERN, NOT A DECIMAL. `H.f32_show(0.0)` is `"0"` and `repr(0.0)`
        # is `"0.0"` -- MEASURED, and it moved thirty of this census's rows before the arm
        # was changed. Thirty rows of "the port spells zero without a decimal point" would
        # be thirty rows of pins-file noise about `helpers.bend` and not one row about
        # `creation.bend`, which is the weakening `ops_python_census-gate.py`'s
        # `literal_rows_hold` exists to prevent. `struct.pack` is exact and total,
        # `F32.bits` is a law (base.bend:31), and this also makes 0.0, -0.0 and a NaN
        # payload three different tokens rather than one.
        v = f"bits={struct.unpack('<I', struct.pack('<f', a))[0]}"
    else:
        v = repr(int(a))
    return f"CONST/0[{v}:{u.dtype.name}]"


def pval(a) -> str:
    """`ALLOC/0[<dtype> sz=<size> <addrspace> bind=<bool>]`. `bind_on_realize` is `True` for
    an ALLOC and is the ALLOC's one difference from a BUFFER (creation.py:41 vs ops.py:852);
    `addrspace` is GLOBAL because `CreationMixin.empty` passes none."""
    return f"ALLOC/0[{a.dtype.name} sz={a.size} {a.addrspace.name} bind={a.bind_on_realize}]"


def tok(u) -> str:
    if u.op is Ops.CONST:
        return cval(u)
    if u.op is Ops.ALLOC:
        return pval(u.arg)
    return f"{u.op.name}/{len(u.src)}"


def sig(r) -> str:
    """THE WHOLE CONE, in `UOp.toposort`'s OWN ORDER -- which is the order the port's
    `UOp.toposort` (ops.bend:3213) builds, both POST-ORDER with each node once."""
    return ",".join(tok(u) for u in r.uop.toposort())


def row(nm, fn) -> str:
    """ONE ROW, AND A RAISE IS A ROW. `Tensor.empty(..., dtype=weakint)` is
    `RuntimeError: cannot create storage for weak dtype` (creation.py:37), and a pure Bend
    def cannot raise; printing `raise=<Name>` makes the two answers legible instead of
    absent, which is `rng_graph_census`'s "a refusal is a byte-identical row"."""
    try:
        return f"{nm}={sig(fn())}"
    except Exception as e:                                           # noqa: BLE001
        return f"{nm}=raise={type(e).__name__}"


# ================================================================ THE NINE DTYPE FAMILIES
# `f` is the family id and it IS the row prefix, so the row NAME and the dispatch arm cannot
# drift apart -- `crp_graph_census.bend`'s `fam.of` is the same `Nat` match.
FAMS = ("zl", "ol", "fl", "el", "cl", "f", "iv", "z", "eb")


def fam(f: int, dt: DType):
    """The ported defs of `creation.py` that take a dtype. The fill VALUE is `dt.const(1)`
    for the five that use one, because `creation.py:83` resolves `dt` from the value and
    `DType.const` is what narrows it."""
    if f == 0:
        return rx(dt).zeros_like()                      # creation.py:124
    if f == 1:
        return rx(dt).ones_like()                       # creation.py:154
    if f == 2:
        return rx(dt).full_like(dt.const(1))            # creation.py:89
    if f == 3:
        return rx(dt).empty_like()                      # creation.py:45, dtype=None
    if f == 4:
        return rx(dt).const_like(dt.const(1))           # creation.py:14
    if f == 5:
        return Tensor.full(SHAPE, dt.const(1), dtype=dt, device=DEV)          # creation.py:64
    if f == 6:
        return Tensor.invalids(SHAPE, dtype=dt, device=DEV)                    # creation.py:53
    if f == 7:
        return Tensor.zeros(SHAPE, dtype=dt, device=DEV)                       # creation.py:108
    # `eb` IS `el` -- the SAME CPython call, twice. The port's two rows differ only in
    # whether it was handed `vmin`/`vmax`, which Python reads off the receiver
    # (`commit_dtype` -> `self._uop.vmin`, dtype.py:16) and this port cannot
    # (creation.bend's W3). One CPython row and two port rows, on purpose: a PAIR, because
    # either row alone cannot say whether `commit_dtype` or the missing bounds are at fault.
    return rx(dt).empty_like()


# =============================================================== THE FIVE SHAPE FAMILIES
# `dtype` is `float32` because `empty` REFUSES a weak dtype (creation.py:37) and a weak axis
# would make every `ne` row a raise rather than a graph -- and the port's `sh.one` passes
# `S.single()` for the same reason, so both sides refuse or answer together.
SHFAMS = ("ne", "fs", "nb", "z", "o")


def shf(f: int, shape):
    kw = dict(dtype=dtypes.float32, device=DEV)
    if f == 0:
        return Tensor.empty(shape, **kw)                       # creation.py:23
    if f == 1:
        return Tensor.full(shape, 1, **kw)                     # creation.py:64, buffer=True
    if f == 2:
        return Tensor.full(shape, 1, buffer=False, **kw)       # creation.py:64, buffer=False
    if f == 3:
        return Tensor.zeros(shape, **kw)                       # creation.py:108
    return Tensor.ones(shape, **kw)                            # creation.py:138


# ============================================================== THE INTERNING AND CONTROL
# `in_*` ARE THE `ucache` ROWS. Python interns on `(op, src, arg, tag, type(arg))` against a
# PROCESS-WIDE dict, so a second equal call re-uses the CONST, the STACK, the EXPAND and the
# RESHAPE and mints only what `next(UOp.unique_num)` moved -- creation.py's rule 1 and
# ops.py:1208.
def new_nodes(b, a) -> int:
    return sum(1 for u in b.uop.toposort() if u not in a.uop.toposort())


def store_val(r):
    """`AFTER(ret, STORE(ret, val))` -- creation.py:87 -- so the STORED value is
    `AFTER.src[1].src[1]`, and THAT is the node two equal `full`s must share."""
    return r.uop.src[1].src[1]


def selfref(r) -> bool:
    """THE STALE-ARENA SELF-LOOP DETECTOR, defect class (a): `r.uop in r.uop.src`."""
    return r.uop in r.uop.src


if __name__ == "__main__":
    # EVERY ROW, REFUSALS INCLUDED, so the two lanes carry the same row count BY
    # CONSTRUCTION and an exclusion list is never what makes the counts meet.
    for f, pfx in enumerate(FAMS):
        for dt in dtypes_():
            print(row(f"{pfx}_{dt.name}", lambda f=f, dt=dt: fam(f, dt)))
    for f, pfx in enumerate(SHFAMS):
        for i, s in enumerate(SHAPES):
            print(row(f"{pfx}_{i}", lambda f=f, s=s: shf(f, s)))

    a = Tensor.full(SHAPE, 1, dtype=dtypes.float32, device=DEV)
    b = Tensor.full(SHAPE, 1, dtype=dtypes.float32, device=DEV)
    e = Tensor.empty(SHAPE, dtype=dtypes.float32, device=DEV)
    g = Tensor.empty(SHAPE, dtype=dtypes.float32, device=DEV)
    o = Tensor.ones(SHAPE, dtype=dtypes.float32, device=DEV)
    # `sorted` ORDER, and it IS PART OF THE CONTRACT: `expected_rows()` in the gate names
    # the tail with `sorted(...)` so it needs no source-order reasoning, and the lanes are
    # diffed LINE BY LINE. MEASURED, the first draft emitted them in the order that reads
    # well (`in_full` first, `in_diff` last) and the discovery answered a different order,
    # so `names_hold` reported three lanes of equal length and unequal content.
    print(f"in_diff={new_nodes(o, e)}")
    print(f"in_empty={new_nodes(g, e)}")
    print(f"in_expand={store_val(b) is store_val(a)}")
    print(f"in_full={new_nodes(b, a)}")
    print(f"in_selfref={selfref(b)}")
    print(f"in_selfref_a={selfref(a)}")
    # THE CONTROL: THE SAME FIXTURE BUILT AGAIN, which must be byte-identical to `ne_2`.
    print(row("ctl_2", lambda: Tensor.empty((2, 3), dtype=dtypes.float32, device=DEV)))