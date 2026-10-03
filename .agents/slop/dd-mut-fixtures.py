#!/usr/bin/env python3
"""dd-mut-fixtures.py -- the CPython expectations for the TWO fixture rows this
unit added to `dtype.bend`, plus the order proof that makes their `n=` rows mean
anything.

  `hi42`  closes M09.  See "THE ROW IT PRODUCES" below.
  `lgy`   closes M05, which the REQUEST sweep turned from a 0 into a 0-WITH-A-
          REASON: `dd-mut-proof.py` REFUSED to rename `l2i_cast3.bitc`, so the
          site is LIVE, so the 0 is INVISIBILITY and wants a fixture.

`dd-oracle.py` is another unit's, so this file answers by CALLING CPython.  It
LOADS that oracle for the print helpers (`tree`, `cone`, `esig`, `ck`, `kept`,
`ORDER`) rather than restating them: the gate compares whole `name=value` LINES,
so a second transcription of the printers could disagree with the first for a
reason that has nothing to do with the port, and "the port and my copy of the
oracle disagree" would be unreadable.  One printer, two lanes.

---------------------------------------------------------------------------
hi42 -- dtype.py:42's `hi`, as a fixture's ANSWER

    tinygrad/codegen/decomp/dtype.py:41-44
      case Ops.SHL:
        a0u, a1u, n = a0.bitcast(uint), a1.bitcast(uint), (b0 & 31).cast(uint)
        lo, hi = (a0u << n).bitcast(dt), ((a1u << n) | ((a0u >> 1) >> (31 - n))).bitcast(dt)
        return (b0 >= 32).where(zero, lo), (b0 >= 32).where(lo, hi)

`l2i` returns `(r0, r1)` and `r1 = (b0 >= 32).where(lo, hi)`, so `hi` is
`r1.src[2]` -- the `y` of `where(cond, x, y)`.  The Bend gate reaches the same
node at the same address: `dd_where = T.tx_alu3(ar, WHERE, [cond, x, y])`, so
`hi` is `O.Arena.src(ar, r1, 2)`.

`dt` is `uint32` and NOT `int32`, and that is load-bearing rather than
incidental: `dtype.py:42`'s `hi` is `(... | ...).bitcast(dt)`, so at an `int32`
`dt` CPython puts a `BITCAST` OUTSIDE the `|` and the node at `r1.src[2]` is the
BITCAST.  At `uint32` the bitcast FOLDS (`mixin/dtype.py:53`), `hi` IS the `|`,
and BOTH lanes reach it in ONE hop with no dtype-dependent second address.

`lg9` ALREADY CONTAINS THAT `OR`.  `dd_tree` prints TWO levels (`dd_sfx2.put`
calls `dd_sh1` on each src; `dd_sfx1.put` calls `dd_lab`, which is a bare
label), and `hi` sits under a `WHERE` and a `BITCAST`, so `lg9p` reads
`BITCAST(OR)` -- the operand ORDER is in no `lg9` row except `lg9sig`, and only
because the cone toposort happens to walk src[0] before src[1`.  Printing `hi`
as a fixture's ANSWER puts the `|` at the ROOT, where `OR(SHL,SHR)` and
`OR(SHR,SHL)` are different strings.

`xdt` is `int32` (pool offset 4) and not its `uint32` neighbour: with a `u32`
source `a0u`/`a1u` FOLD (`mixin/dtype.py:53`) and both halves of the `|` are
bare PARAMs; with an `i32` source each half carries its own `BITCAST`, so the
row also reaches `dd_bcast`'s False arm and `dd_cast_fold`'s False arm INSIDE
the SHL arm -- neither of which `lg9` reaches.

---------------------------------------------------------------------------
lgy -- dtype.py:39's `else` arm, on a source whose bitcast does NOT fold

    tinygrad/codegen/decomp/dtype.py:39
      case Ops.CAST: return a0.bitcast(dtypes.uint).cast(dt)

`lg7` is already this arm (`dt=int32`, `xdt=uint32`), and its answer is
`CAST(Pu320)`: no BITCAST, because `bitcast` FOLDS when the dtypes already
agree (`mixin/dtype.py:53`).  So the ONLY fixture on this arm is one on which
the fold fires, and the BITCAST of dtype.py:39 -- the node the arm exists to
build -- is in no row.  `l2i_cast3.bitc`'s `False` arm is live code with zero
coverage: `dd-mut-proof.py` REFUSES to rename it, so the site is reachable, and
M05 ("never bitcast the source to uint32") moves nothing because every reaching
fixture folds.  `xdt = int32` is the fix and the smallest possible one: same
`dt`, same arm, one dtype over on the source.

usage: dd-mut-fixtures.py [hi42|lgy]
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, ROOT)
os.chdir(ROOT)


def load(name, path):
    """`dd-oracle.py` has a dash in its name, so import it by path.  It guards
    its own `main()` with `if __name__ == "__main__"`, so importing RUNS NOTHING."""
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


O_ = load("dd_oracle", os.path.join(HERE, "dd-oracle.py"))


def call(fn, *a):
    """`l2i` raises on FLOORDIV (dtype.py:81) and the gate prints `refused:` for
    it, so the replay must let the raise happen and keep going: the nodes it
    interned before firing still count, exactly as they do in the port."""
    try:
        return fn(*a)
    except Exception:
        return None


def replay_gate_prefix(skip=None):
    """The gate's OWN fixture order, so a row's `n=` counts the same window on
    both lanes.  `ORDER` counts a node only the FIRST time it is interned, so a
    row's `n=` is a function of SESSION order and not of `l2i`: measured
    `hi42` FIRST it read 22, LAST it reads 14, and only the second is comparable
    with the port.

    `dtype.bend`'s `gate()` is  `fixtures()` -> `l2i.rows(N)` -> `up` -> `hi42`
    -> `c0..c7`, and `l2i.rows(N)` is `l2i.pick`'s cases 0..N-1 = the oracle's 28
    `L2I()` rows, then `lgv`/`lgw`/`lgx` (the const-source CASTs, dtype.py:28-32),
    then `lgu` (dtype.py:35-38), then `lgy` (dtype.py:39).  VERIFIED below against
    the stored oracle's own `upn`, which is the one row whose window is zero on
    both lanes.

    `skip` DROPS the fixture being measured from its own prefix.  It has to: the
    first version of this file replayed `lgy` and then measured `lgy`, so the
    measurement ran in a session that had already interned its two nodes and read
    `lgyn=0` against the port's `2`.  A replay that includes the row under
    measurement is the same defect as a baseline taken from a mirror still holding
    a mutant -- the row under test is measured after it already happened.
    """
    for nm, op, dt, xdt, n in O_.L2I():
        call(O_.DD.l2i, op, dt, *O_.ws(xdt, n))
    for dt, src in ((O_.dtypes.long, O_.UOp.const(0, O_.dtypes.uint32)),
                    (O_.dtypes.ulong, O_.UOp.const(0, O_.dtypes.uint32)),
                    (O_.dtypes.ulong, O_.UOp.const(1, O_.dtypes.uint32))):
        call(O_.DD.l2i, O_.Ops.CAST, dt, src)
    call(O_.DD.l2i, O_.Ops.CAST, O_.dtypes.float32, *O_.WPOOL[O_.dtypes.f32][:2])
    if skip != "lgy":
        call(O_.DD.l2i, O_.Ops.CAST, O_.dtypes.int32, *O_.ws(O_.dtypes.int32, 2))
    return len(O_.ORDER)


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "hi42"
    replay_gate_prefix(skip=which)
    ub = len(O_.ORDER)
    O_.DD.unpack32(O_.WPOOL[O_.dtypes.u32][0])
    upn = len(O_.kept(O_.ORDER[ub:]))
    assert upn == 0, f"replay is not the gate's order: upn={upn}, the stored oracle says 0"

    if which == "hi42":
        w = O_.ws(O_.dtypes.int32, 3)
        b = len(O_.ORDER)
        r0, r1 = O_.DD.l2i(O_.Ops.SHL, O_.dtypes.uint32, *w)
        hi = r1.src[2]
        assert hi.op is O_.Ops.OR, f"dtype.py:42's hi is not an OR: {hi.op}"
        c = O_.cone([hi])
        print(f"hi42={O_.tree(hi)}")
        print(f"hi42n={len(O_.kept(O_.ORDER[b:]))}")
        print(f"hi42sig={O_.esig(c)}")
        print(f"hi42k={O_.ck(c)}")
        # THE ORDER, READ BACK OUT OF CPython'S OWN GRAPH.  If `hi.src[0]` were
        # the carried half, this row would encode M09.
        print(f"# hi.src[0] = {O_.tree(hi.src[0])}   <- a1u << n, dtype.py:42's LEFT")
        print(f"# hi.src[1] = {O_.tree(hi.src[1])}   <- (a0u>>1)>>(31-n), the RIGHT")
        print(f"# r1 = {r1.op.name}/{len(r1.src)}  ->  hi is r1.src[2]")
        return

    assert which == "lgy", which
    # dtype.py:39 reads `a0`, which `l2i` only binds at `len(uops) >= 2` (line 23),
    # so TWO pool words: measured, one word is `UnboundLocalError` on the arm.
    w = O_.ws(O_.dtypes.int32, 2)
    b = len(O_.ORDER)
    # dtype.py:39 returns a BARE UOp, not a tuple -- one of the four arms that
    # answer a single node -- so there is no `p` row and `hi == 0` in the port.
    r = O_.DD.l2i(O_.Ops.CAST, O_.dtypes.int32, *w)
    assert r.op is O_.Ops.CAST and r.src[0].op is O_.Ops.BITCAST, \
        f"dtype.py:39's BITCAST is missing: {O_.tree(r)}"
    c = O_.cone([r])
    print(f"lgy={O_.tree(r)}")
    print(f"lgyn={len(O_.kept(O_.ORDER[b:]))}")
    print(f"lgysig={O_.esig(c)}")
    print(f"lgyk={O_.ck(c)}")
    print("# dtype.py:39 `case Ops.CAST: return a0.bitcast(dtypes.uint).cast(dt)`,")
    print("# one node, so the gate prints no `p` row and `hi == 0`.")


if __name__ == "__main__":
    main()