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

import collections

from tinygrad import dtypes
from tinygrad.dtype import AddrSpace, ConstFloat, Invalid, InvalidType
from tinygrad.uop.ops import AxisType, Ops, ParamArg, UOp
from tinygrad.uop.symbolic import symbolic

F32 = dtypes.float32


def b(value: bool) -> str:
    """A 1-cell Bool as the row's value, so the two lanes' rows are comparable strings."""
    return "1" if value else "0"


def pa(val):
    """The port's `pa_with`: a PARAM differing in EXACTLY ONE FIELD, `val`.

    **AND THE FIXTURE SPELLS UPSTREAM's OWN FIELD ORDER AT THE PIN** -- MEASURED 2026-11-08: THE
    ORACLE CRASHED WITH "ParamArg.__init__() takes from 3 to 13 positional arguments but 14 were
    given", **AND `git show f5ac54685074:tinygrad/uop/ops.py` READS THE FIELDS AS
    `slot, dtype, vmin_vmax, name, addrspace, device, volatile, image, buffer, bind_on_realize,
    val, spec` -- TWELVE OF THEM, WITH **NO `multiple_of`**, WHILE THE OLD FIXTURE PASSED THREE
    `None`s BETWEEN `vmin_vmax` AND `addrspace`.** **SO THE FIXTURE IS RE-SPELLED AT THE PIN's
    OWN ORDER AND THE FIXTURE SETS EVERY FIELD**, because a fixture that dropped one would stop
    the row being about `val`: a comparator that dropped any other field could not satisfy this
    pair, and one that dropped `val` cannot pass it.
    """
    return UOp(Ops.PARAM, src=(), arg=ParamArg(0, dtypes.int32, None, None,
                                               AddrSpace.GLOBAL, None, False, None, None,
                                               False, val, None))


def argd(value):
    """A SINK carrying a bare Python value in the `arg` slot.

    **AND THIS IS THE **REPLACEMENT** FOR THE `tagged()` HELPER, AND THE REPLACEMENT IS A
    MEASUREMENT AND NOT A WHIM** -- MEASURED 2026-11-08: THE ORACLE CRASHED WITH "TypeError:
    UOpMetaClass.__call__() got an unexpected keyword argument 'tag'", **AND UPSTREAM DELETED
    `UOp.tag` IN `fb518b44e` ("delete UOp.tag [pr] (#18954)", 2026-10-21), AND
    `git merge-base --is-ancestor fb518b44e f5ac54685074` ANSWERS YES** -- **SO AT THE PIN
    THERE IS NO `tag` SLOT AT ALL, AND `rg '\btag\b' tinygrad/uop/ops.py` FINDS **NOTHING**.**

    **THE PIN's KEY IS `(op, src, arg, type(arg))` (`ops.py:194`), SO `type(arg)` IS THE ONLY
    THING THAT SPLITS THE KEY BY A PYTHON TYPE** -- and THAT is the question the three rows
    below ask, in upstream's own spelling.

    **AND THE PORT's `arg` CARRIES THAT TYPE IN ITSELF** -- `APy{CBool{…}}` and
    `APy{CInt{…}}` are different `Arg` values and `ANone{}` is a third -- so the port can
    answer it too, and the port's rows are `arg_bool_vs_int_splits`, `arg_none_vs_int_splits`
    and `arg_int_same_interns`.
    """
    return UOp(Ops.SINK, src=(), arg=value)


def _nd_arm(d):
    """UPSTREAM's OWN ARM, `divandmod.py:23`'s `nested_div`, EVALUATED **AS ITS OWN TEXT**.

    **AND THE ARM IS ASKED AND NOT THE MATCHER AND NOT `fold_divmod_general`** -- MEASURED
    2026-11-09: `(x%2)//4` IS **NOT** REWRITTEN BY `nested_div` (THE `k` IS `None`, BECAUSE `2`
    DOES NOT DIVIDE `4`), **AND `fold_divmod_general` ANSWERS `0` ANYWAY -- FROM THE **RANGE** ARM
    (`divandmod.py:13`) -- **AND THE MATCHER ANSWERS THE SAME `0`.** **SO BOTH OF THOSE ASK A
    DIFFERENT QUESTION, AND THE PORT's ROW ASKS **THIS** ARM.**

    **AND THE ARM'S CONDITION IS **UPSTREAM's OWN TEXT** -- `if d.op is Ops.DIV and x.op is
    Ops.MOD and (k := x.src[1].divides(c)) is not None and k.vmin > 0: return x.src[0] // y % k`
    (`divandmod.py:23`) -- **SO THE ORACLE EVALUATES **UPSTREAM's OWN LINE** AND NOT A COPY OF
    IT.**
    """
    x, y = d.src
    if not (d.op is Ops.DIV and x.op is Ops.MOD): return None
    if not (y.op is Ops.CONST and y.val > 0): return None
    k = x.src[1].divides(y.val)
    if k is None or not (k.vmin > 0): return None
    return x.src[0] // y % k


def _nd_rewrite() -> bool:
    """`(x % 8) // 4` IS `(mod (div x 4) 2)` -- THE `nested_div` REWRITE.

    **AND THE ANSWER IS READ AS A **TREE**, AND NOT AS A FLAG** -- so the row says the answer HAS
    the shape upstream's has.
    """
    x = UOp.variable("x", 0, 20, dtype=dtypes.weakint)
    d = UOp(Ops.DIV, (UOp(Ops.MOD, (x, UOp.const(8, dtypes.weakint)), dtypes.weakint),
                      UOp.const(4, dtypes.weakint)), dtypes.weakint)
    g = _nd_arm(d)
    if g is None or g.op is not Ops.MOD: return False
    inner = g.src[0]
    return (inner.op is Ops.DIV and inner.src[0] is x and inner.src[1].op is Ops.CONST
            and inner.src[1].arg == 4 and g.src[1].op is Ops.CONST and g.src[1].arg == 2)


def _nd_neg() -> bool:
    """`(x % -4) // 4` IS **NOT** REWRITTEN -- THE `k` IS **-1** AND `k.vmin > 0` FAILS."""
    x = UOp.variable("x", 0, 20, dtype=dtypes.weakint)
    d = UOp(Ops.DIV, (UOp(Ops.MOD, (x, UOp.const(-4, dtypes.weakint)), dtypes.weakint),
                      UOp.const(4, dtypes.weakint)), dtypes.weakint)
    return _nd_arm(d) is None


def _nd_nodiv() -> bool:
    """`(x % 2) // 4` IS **NOT** REWRITTEN -- `2` DOES NOT DIVIDE `4`."""
    x = UOp.variable("x", 0, 20, dtype=dtypes.weakint)
    d = UOp(Ops.DIV, (UOp(Ops.MOD, (x, UOp.const(2, dtypes.weakint)), dtypes.weakint),
                      UOp.const(4, dtypes.weakint)), dtypes.weakint)
    return _nd_arm(d) is None


def _de_same() -> bool:
    """THE `self IS v` ANSWER IS **1** -- A CONST WITH NO SRCS."""
    x = UOp.variable("x", 0, 4, dtype=dtypes.weakint)
    g = x.divide_exact(x)
    return g is not None and g.op is Ops.CONST and len(g.src) == 0


def _de_const_none() -> bool:
    """**`x` DOES NOT DIVIDE **2**, SO THE ANSWER IS **NONE**."""
    x = UOp.variable("x", 0, 4, dtype=dtypes.weakint)
    return x.divide_exact(UOp.const(2, dtypes.weakint)) is None


def _de_mul() -> bool:
    """**`x*y` DIVIDED BY `y` IS **A MUL** -- AND THE CONSTANT IS **STRIPPED** BY `pop_const`.

    **AND THE **VALUE** OF THE LEFT SRC IS READ AND NOT ONLY ITS **SHAPE** -- MEASURED
    2026-11-09: A PLANT THAT REPLACED THE PRODUCT's **START** WITH **1** DID NOT MAKE THE GATE GO
    RED, BECAUSE THE ROW ASKED "IS IT A CONST?" AND A PLANTED **1** IS ALSO A CONST. **A ROW THAT
    CANNOT GO RED IS WORSE THAN NO ROW.**
    """
    x = UOp.variable("x", 0, 4, dtype=dtypes.weakint)
    y = UOp.variable("y", 0, 4, dtype=dtypes.weakint)
    mxy = UOp(Ops.MUL, (x, y), dtypes.weakint)
    g = mxy.divide_exact(y)
    if g is None or g.op is not Ops.MUL or len(g.src) != 2: return False
    # THE LEFT SRC IS THE CONSTANT FACTOR's QUOTIENT AND THE RIGHT IS THE SURVIVING FACTOR.
    left, right = g.src
    return left.op is Ops.CONST and left.arg == 1 and right is x


def _de_const_out() -> bool:
    """**`x*2` DIVIDED BY `x` IS **THE CONSTANT** -- A CONST WITH NO SRCS.

    **AND THIS IS THE ROW THAT CATCHES A `divide_exact` THAT DOES NOT STRIP THE CONSTANT**:
    the popped numerator is `x` with the constant `2`, and the popped divisor is `x` with the
    constant `1`, so the answer is `const//div_const` = `2` and **NO** factor survives.
    """
    x = UOp.variable("x", 0, 4, dtype=dtypes.weakint)
    mx2 = UOp(Ops.MUL, (x, UOp.const(2, dtypes.weakint)), dtypes.weakint)
    g = mx2.divide_exact(x)
    # **AND THE **VALUE** IS READ**: the answer is `const//div_const` = `2//1` = **2**, and a
    # planted **1** IS A DIFFERENT CONST.
    return g is not None and g.op is Ops.CONST and len(g.src) == 0 and g.arg == 2


def _gcd_const() -> bool:
    """THE GCD OF TWO UNRELATED VARIABLES IS **1** -- A CONST WITH NO SRCS.

    CPython's OWN `UOp.gcd` is the oracle, so the port's answer and this one are two independent
    computations of the same property rather than a restatement of an expected number.
    """
    x = UOp.variable("x", 0, 4, dtype=dtypes.weakint)
    y = UOp.variable("y", 0, 4, dtype=dtypes.weakint)
    g = UOp.gcd(x, y)
    return g.op is Ops.CONST and len(g.src) == 0


def _gcd_shared() -> bool:
    """THE GCD OF `x*z` WITH ITSELF IS **THE SHARED FACTOR** -- A MUL.

    **AND THE CONSTANT IS **STRIPPED** BY `pop_const`**, which is what makes the counter `{x:1,
    z:1}` and not `{x:1, z:1, 3:1}` -- so the answer's shape carries the popping.
    """
    x = UOp.variable("x", 0, 4, dtype=dtypes.weakint)
    z = UOp.variable("z", 0, 4, dtype=dtypes.weakint)
    mxz = UOp(Ops.MUL, (x, z), dtypes.weakint)
    g = UOp.gcd(mxz, mxz)
    return g.op is Ops.MUL and len(g.src) == 2


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


def sg_ctor(a) -> str:
    """The port's `sg.ctor` arm for arm, over the four arms a WHERE's srcs can carry here."""
    if a is None:
        return "none"
    if isinstance(a, bool):
        return f"cbool:{a}"
    if isinstance(a, InvalidType):
        return "cinvalid"
    if isinstance(a, int):
        return "cint"
    if isinstance(a, float):
        return "cfloat"
    return "other"


def _ctr_bump() -> bool:
    """THE COUNT OF EACH KEY IN A LIST OF NODES -- A MULTISET AND NOT A SET."""
    c = collections.Counter([1, 2, 3, 2])
    return c[1] == 1 and c[2] == 2 and c[3] == 1


def _ctr_find() -> bool:
    """THE COUNT OF A KEY, AND **ZERO FOR A KEY THAT IS NOT THERE**."""
    c = collections.Counter([7, 7, 9])
    return c[7] == 2 and c[9] == 1 and c[4] == 0


def _ctr_inter() -> bool:
    """THE MULTISET INTERSECTION: THE KEYS IN **EVERY** COUNTER, WITH THE **MINIMUM** COUNT."""
    a, b = collections.Counter([1, 1, 2]), collections.Counter([1, 2, 2])
    keys = sorted(set(a) & set(b))
    return (keys == [1, 2] and min(a[1], b[1]) == 1 and min(a[2], b[2]) == 1
            and 3 not in keys)


def main() -> None:
    nan = ConstFloat(float("nan"))

    # The BACKEDGE reads back as itself: src[0] is the SPECIAL it was called on and src[1] the
    # RANGE whose arg names the axis it closes over. Built through the port's own shape --
    # `special` is handed the RANGE, not a bare number.
    rng = UOp.range(UOp.const(1, dtypes.weakint), 1, AxisType.DEVICE)
    backedge = UOp.special(rng, "g").backedge(rng, rng)

    rows = (
        # 1-5: CONST identity. `UOp.const` interns in `ucache`, so identity IS hash-consing.
        # THE COUNTER's THREE CLAIMS, **AND CPYTHON's OWN `collections.Counter` IS THE
        # ORACLE** -- SO THE PORT's ANSWER AND PYTHON's ARE TWO INDEPENDENT COMPUTATIONS OF
        # THE SAME PROPERTY, AND NOT A RESTATEMENT OF THE EXPECTED NUMBERS.
        ("hashcons_same_index", UOp.const(3, dtypes.int32) is UOp.const(3, dtypes.int32)),
        ("zeros_differ", UOp.const(ConstFloat(0.0), F32) is not UOp.const(ConstFloat(-0.0), F32)),
        ("nan_interns", UOp.const(nan, F32) is UOp.const(ConstFloat(float("nan")), F32)),
        ("bool_vs_int_key", UOp.const(True, dtypes.bool) is not UOp.const(3, dtypes.int32)),
        ("backedge_srcs", backedge.src[0].op is Ops.SPECIAL and backedge.src[1].op is Ops.RANGE),

        # THE TOP-LEVEL `arg` LANE -- **AND IT REPLACES THE THREE `tag_*` ROWS**, because upstream
        # DELETED `UOp.tag` BEFORE the pin (`fb518b44e`, an ancestor of the pin) and so upstream's
        # pin CANNOT answer a question about a slot it no longer has. **THE PROPERTY IS THE SAME
        # ONE** -- `type(arg)` splits the key -- and the port's `arg` carries the type in itself,
        # so BOTH lanes can answer it.
        #
        # MEASURED AT THE PIN: `arg=True` vs `arg=1` is False, `arg=None` vs `arg=0` is False,
        # `arg=1` vs `arg=1` is True.
        ("arg_bool_vs_int_splits", argd(True) is not argd(1)),
        ("arg_none_vs_int_splits", argd(None) is not argd(0)),
        ("arg_int_same_interns", argd(1) is argd(1)),

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

    # `valid` -- ops.py:664 -- is `cond.where(self, self.const_like(Invalid))`, so its whole
    # content is the SHAPE of the node it returns. The three arms are DISTINGUISHABLE BY CLASS --
    # a bool const, an int const, an Invalid -- so an order swap fails rather than passing on a
    # count, which `sg_ctor` above is written to reproduce arm for arm.
    cond = UOp.const(True, dtypes.bool)
    selff = UOp.const(7, dtypes.weakint)
    valid = cond.where(selff, selff.const_like(Invalid))
    rows.append(("valid_is_where", str(valid.op is Ops.WHERE)))
    for k, s in enumerate(valid.src, start=1):
        rows.append((f"valid_src{k-1}", sg_ctor(s.arg)))

    rows.append(last)

    # THE COUNTER's THREE CLAIMS, **AND CPYTHON's OWN `collections.Counter` IS THE ORACLE** --
    # SO THE PORT's ANSWER AND PYTHON's ARE TWO INDEPENDENT COMPUTATIONS OF THE SAME PROPERTY,
    # AND NOT A RESTATEMENT OF THE EXPECTED NUMBERS.
    rows.extend((("ctr_bump", _ctr_bump()), ("ctr_find", _ctr_find()), ("ctr_inter", _ctr_inter())))
    # `UOp.gcd` -- ops.py:1073. **AND CPYTHON's OWN `UOp.gcd` IS THE ORACLE**, so the port's
    # answer and this one are two independent computations of the same property.
    rows.extend((("gcd_const", _gcd_const()), ("gcd_shared", _gcd_shared())))
    # `nested_div` -- divandmod.py:23 -- **AND THE **ARM** IS EVALUATED, **AND NOT THE MATCHER AND
    # NOT `fold_divmod_general`** (MEASURED 2026-11-09: `(x%2)//4` IS **NOT** REWRITTEN BY
    # `nested_div` **AND THE OTHER TWO ANSWER IT VIA THE **RANGE** ARM**).
    #
    # **⇒ AND THE ROWS ARE **RIGHT AFTER** THE `gcd_*` ROWS IN **BOTH** LANES**, **BECAUSE THE
    # GATE COMPARES THEM **POSITIONALLY** (`gates/gatekit.py`: `zip(base, other)`)**.
    rows.extend((("nd_rewrite", _nd_rewrite()), ("nd_neg", _nd_neg()), ("nd_nodiv", _nd_nodiv())))
    # `UOp.divide_exact` -- ops.py:1038-1047. **AND CPYTHON's OWN `UOp.divide_exact` IS THE
    # ORACLE**, so the port's answer and this one are two independent computations of the same
    # property.
    rows.extend((("de_same", _de_same()), ("de_const_none", _de_const_none()),
                 ("de_mul", _de_mul()), ("de_const_out", _de_const_out())))




    for name, value in rows:
        print(f"{name}={value if isinstance(value, str) else b(value)}")


if __name__ == "__main__":
    main()
