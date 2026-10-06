#!/usr/bin/env python3
"""ops-core-oracle.py -- CPython's answers to `gates/ops-core.bend`'s fourteen rows.

Built from `tinygrad` directly, so the two lanes share no code: the Bend lane calls the `t_*`
claims `uop/ops.bend` already contains, this lane builds the same graphs out of real tinygrad UOps
and asks the same questions. A row agrees only if two implementations of the property say so.

Run with the repo's venv so the import is the working tree's tinygrad:

    .venv/bin/python gates/ops-core-oracle.py

ROWS 1-5, THE CONST-IDENTITY CLUSTER. tinygrad's `UOp.key` is a hash over the packed arg, so a
CONST's identity is its BIT PATTERN, and IEEE equality disagrees with that in exactly two
directions -- which is the whole reason the port compares `F32.bits` rather than `F32.is_eq`:

    Tensor(0.0)._uop is Tensor(-0.0)._uop   -> False   0x00000000 vs 0x80000000
    Tensor(nan)._uop is Tensor(nan)._uop   -> True    0x7fc00000 both

A port that keyed on `is_eq` would collapse two distinct nodes in the first cell and re-mint an
identical node in the second: two different wrong answers from one comparison.

ROWS 6-14, THE ARG-TYPE LANE, and these are the rows worth the gate. tinygrad's key is

    (op, src, arg, tag, type(arg))                      -- ops.py:201

which carries an ASYMMETRY: `type(arg)` is in the key and `type(tag)` is NOT. So `True` and `1`
SPLIT as a top-level arg and MERGE in the tag, and a `ParamArg` -- whose own type is `ParamArg` on
both sides -- MERGES them again in the nested `val`. Three positions, two different answers, and
a comparator that treated them alike would pass any single one of these rows.

`pynest_cfloat_vs_int_interns` is the subtlest and is here because it was WRONG here first: my
first version of this oracle passed a bare Python `1.0` and reported that tinygrad MERGES
`1.0` with `1`, which contradicted the port. The port was right. `PyConst` floats are
`ConstFloat`, whose `__hash__` is `hash(self.bits)` (`dtype.py:21`) and whose `__eq__` is
`float.__eq__` -- so `ConstFloat(1.0) == 1` is True while `hash(ConstFloat(1.0)) != hash(1)`.
Equal values in DIFFERENT dict buckets are never compared, so they are two keys. Same fact from
the other side in `pynest_signed_zero_interns`, where the two floats differ in bits. The fixture
was the error, not the port: an oracle that asks a different question than the port is worse than
no oracle, because it produces a confident wrong answer.

A `0` here is a correct answer and not a failure: these rows are CLAIMS, and three of them are
`0` precisely because a comparator that answered True for every pair would be wrong.
"""

from tinygrad import dtypes
from tinygrad.dtype import AddrSpace, ConstFloat
from tinygrad.uop.ops import AxisType, Ops, ParamArg, UOp

F32 = dtypes.float32


def b(value: bool) -> str:
    """A 1-cell Bool as the row's value, so the two lanes' rows are comparable strings."""
    return "1" if value else "0"


def pa(val):
    """The port's `pa_with`: a PARAM differing in EXACTLY ONE FIELD, `val`.

    Thirteen fields in `ops.py:26-38`, and the fixture has to set all of them or the row stops
    being about `val`: a comparator that dropped any other field could not satisfy this pair, and
    one that dropped `val` cannot pass it.
    """
    return UOp(Ops.PARAM, src=(), arg=ParamArg(0, dtypes.int32, None, None, None, None,
                                               AddrSpace.GLOBAL, None, False, None, None,
                                               False, val))


def tagged(tag):
    """A SINK carrying a bare Python value in the TAG slot, where `type(tag)` is absent."""
    return UOp(Ops.SINK, src=(), arg=None, tag=tag)


def i64_text(v: int) -> str:
    """An I64 as its two words, because `H.i64_text` is -- `7` is `0:7`."""
    return f"{v >> 32}:{v & 0xFFFFFFFF}"


def show_const(v) -> str:
    """A popped CONST, in the SAME three renderings the Bend lane uses.

    `ConstFloat` takes the six-decimal form and an integer takes `hi:lo`, because `H.f32_show`
    and `H.i64_text` do. That is the same choice made twice rather than one choice shared -- the
    two lanes share no code by construction, and a third formatter here would be a third thing to
    keep in step.
    """
    if v is None:
        return "none"
    if isinstance(v, bool):
        return "True" if v else "False"
    if isinstance(v, ConstFloat):
        return f"{float(v):f}"
    return i64_text(int(v))


def main() -> None:
    nan = ConstFloat(float("nan"))

    # The BACKEDGE reads back as itself: src[0] is the SPECIAL it was called on and src[1] the
    # RANGE whose arg names the axis it closes over. Built through the port's own shape --
    # `special` is handed the RANGE, not a bare number.
    rng = UOp.range(UOp.const(1, dtypes.weakint), 1, AxisType.DEVICE)
    backedge = UOp.special(rng, "g").backedge(rng, rng)

    rows = (
        # 1-5: CONST identity. `UOp.const` interns in `ucache`, so identity IS hash-consing.
        ("hashcons_same_index", UOp.const(3, dtypes.int32) is UOp.const(3, dtypes.int32)),
        ("zeros_differ", UOp.const(ConstFloat(0.0), F32) is not UOp.const(ConstFloat(-0.0), F32)),
        ("nan_interns", UOp.const(nan, F32) is UOp.const(ConstFloat(float("nan")), F32)),
        ("bool_vs_int_key", UOp.const(True, dtypes.bool) is not UOp.const(3, dtypes.int32)),
        ("backedge_srcs", backedge.src[0].op is Ops.SPECIAL and backedge.src[1].op is Ops.RANGE),

        # 6-14: the arg-type lane. `type(arg)` is in the key; `type(tag)` is not.
        ("tag_bool_vs_int_interns", tagged(True) is tagged(1)),
        ("tag_true_vs_false_splits", not (tagged(True) is tagged(False))),
        ("tag_none_vs_zero_interns", tagged(None) is tagged(0)),
        ("const_bool_vs_int_splits", not (UOp(Ops.CONST, src=(), arg=True) is UOp(Ops.CONST, src=(), arg=1))),
        ("pynest_bool_vs_int_interns", pa(True) is pa(1)),
        ("pynest_int_distinct_interns", pa(1) is pa(2)),
        ("pynest_none_vs_zero_interns", pa(None) is pa(0)),
        ("pynest_cfloat_vs_int_interns", pa(ConstFloat(1.0)) is pa(1)),
        ("pynest_signed_zero_interns", pa(ConstFloat(-0.0)) is pa(ConstFloat(0.0))),
    )
    rows = list(rows)
    last = rows.pop()                       # pynest_signed_zero_interns, which the driver prints LAST
    # `pop_const` -- ops.py:1082. `(src[0], src[1].val) if op is self.op and src[1].op is
    # CONST else (self, None)`. TWO rows per fixture, and the fixtures are chosen so the two
    # conditions fail SEPARATELY: a wrong second src, and a wrong op. The fourth is the row that
    # caught the port answering an I64-only reader -- the value here is a FLOAT.
    def pop(nm, u, op=Ops.ADD):
        hit = u.op is op and u.src[1].op is Ops.CONST
        return ((f"{nm}_hits", str(hit)),
                (f"{nm}_val", show_const(u.pop_const(op)[1] if hit else None)))

    c7 = UOp.const(7, dtypes.weakint)
    r2 = UOp.const(2, dtypes.weakint)
    add_const = UOp(Ops.ADD, src=(c7, c7))
    add_noconst = UOp(Ops.ADD, src=(UOp.range(r2, 0, AxisType.LOOP),
                                    UOp.range(r2, 0, AxisType.LOOP)))
    mul_const = UOp(Ops.MUL, src=(c7, c7))
    add_cfloat = UOp(Ops.ADD, src=(c7, UOp.const(ConstFloat(2.5), dtypes.weakfloat)))
    rows.extend(pop("pop_add_const", add_const))
    rows.extend(pop("pop_add_noconst", add_noconst))
    rows.extend(pop("pop_mul_const", mul_const))
    rows.extend(pop("pop_add_cfloat", add_cfloat))
    # `ssimplify` -- ops.py:92. `if (ret := self.simplify()).op is CAST and ret.src[0].op is
    # CONST: return ret.dtype.const(ret.src[0].val); return ret.val if ret.op is CONST else ret`.
    # THREE shapes, and the third is the one that matters: a CAST of a PARAM satisfies neither
    # condition, so CPython hands the NODE back -- a different answer, not an absent one. Two rows
    # per fixture, because "is a value" and "what value" fail independently.
    def ss(nm, u):
        val = u.ssimplify()
        return ((f"{nm}_is_val", str(not isinstance(val, UOp))),
                (f"{nm}_val", show_const(None if isinstance(val, UOp) else val)))

    rows.extend(ss("ss_const", UOp.const(7, dtypes.weakint)))
    # A CAST OF A CONST. `UOp.const(2.5, dtypes.float32)` is exactly that -- the cast folds nowhere
    # but bool/weakint/weakfloat -- so this is CPython's own way of writing the arm.
    rows.extend(ss("ss_cast_const", UOp.const(ConstFloat(2.5), F32)))
    rows.extend(ss("ss_cast_param", UOp(Ops.PARAM, src=(), arg=ParamArg(0, dtypes.int32)).cast(dtypes.int32)))

    rows.append(last)



    for name, value in rows:
        print(f"{name}={value if isinstance(value, str) else b(value)}")


if __name__ == "__main__":
    main()
