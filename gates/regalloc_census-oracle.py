#!/usr/bin/env python3
"""regalloc_census-oracle.py -- CPython's rows for `tinygrad/codegen/late/regalloc.py`.

    .venv/bin/python gates/regalloc_census-oracle.py

48 ROWS, THE SAME 48 `gates/../tinybendygrad/codegen/late/regalloc.bend` PRINTS, IN ITS ORDER
AND IN ITS SPELLING. Every value is DERIVED BY CALLING CPython -- `LinearScanRegallocContext`
and `regalloc_rewrite` from `regalloc.py`, `rdef` from `renderer/isa/__init__.py`,
`PatternMatcher.rewrite` for the table -- over a fixture built from the same register universe
and the same twelve `RaUop`s `regalloc.bend`'s `ra_un0`/`ra_ops0` name.

WHAT THIS LAYER RETURNS, AND WHY THE ROWS HAVE THIS FORM. `LinearScanRegallocContext` returns
five DICTS (`live_range`, `locals`, `spills`, `reals`, `insert_before`) and `regalloc_rewrite`
returns `(nx, before + [nx] + after)`. So the answer is a MAP keyed by PROGRAM POINT, not a
toposort -- which is the case the census brief flags. A count cannot see it and a multiset
cannot see it: `ra0_a7` and `ra1_a7` carry the same number of pairs and the same pairs' KEYS
and differ only in where `v4` landed. So every row is either the map at ONE program point
(`ra<t>_a<i>`, one row per `i` in `reals`, carrying every virtual live there and the REAL
register each took) or a per-key LIST (`ra<t>_lr`, the live range as the ordered index list it
is -- `vdef` reads `live_range[v][0]`, so the order IS the value), and the printed pairs are
SORTED AS TEXT because the port sorts the same strings and the two orders differ on `ra2_a4`
(`v0>3 v2>5 v5>4` against `v0 v5 v2` by intern position).

THE FIXTURE IS AN INPUT ON BOTH SIDES. A `Register` is `@dataclass(frozen=True)` with
`(name, index, _cons, size)` (`renderer/isa/__init__.py:8-17`), and the port INTERNs them
because `O.Tag`'s tuple arm carries UOP INDICES. The oracle builds real `Register`s in the
same order, so intern index `k` is `regs[k]` on both sides and `name>k` is one name per lane.

THE THREE RENDERER HOOKS ARE THE ORACLE'S, MEASURED, NOT THE PORT'S. `LinearContext.assign_
spill_slot`, `ISARenderer.fill` and `ISARenderer.spill` all `raise NotImplementedError("arch
specific")` in tinygrad's own base class (`renderer/isa/__init__.py:37,47,48`), and
`is_two_address` is `return False` (:46). So the oracle subclasses both, and `ra0`/`ra1` are
the SAME uop list with `is_two_address` False and True -- which is the whole reason the pair
exists, because that hook only REORDERS `cons` (`regalloc.py:72-74`) and a reorder is
invisible without a tie. The slot spelling `slot:<name>` is the PORT's alphabet (the port
derives it from the register's name), so it lives here and not in `regalloc.py`.

`regalloc_rewrite`'s RETURN is `(nx, list)`, and this oracle prints the LIST -- the port's
`rw_none` prints `r[1]`. So the row is `before ++ [nx] ++ after` and the SRC REWRITE (the
`:105-107` fill-per-spilled-src half) IS INVISIBLE, because `nx`'s srcs live in `r[0]`. That is
a wall, not an omission, and the port's header says so; three of the rewrite's four halves
have no row.
"""
import sys

from tinygrad.uop.ops import UOp, Ops
from tinygrad.renderer.isa import Register, LinearContext, ISARenderer
from tinygrad.codegen.late.regalloc import (LinearScanRegallocContext, regalloc_rewrite,
                                            pm_regalloc_rewrite, PSEUDO_OPS)

OUT = []


def row(nm, v):
    OUT.append(f"{nm}={v}")


def srow(nm, v):
    OUT.append(f"{nm}={v}")


# ===========================================================================
# THE REGISTER UNIVERSE -- `ra_un0` / `ra_un2` (regalloc.bend:1105-1119).
# `(name, index, cons)` where `cons` are INTERN INDICES, so the port's `Ru{name, index,
# cons}` is CPython's `Register(name, index, tuple(regs[j] for j in cons))`.
# ===========================================================================
UN0 = [("rax", 0, (0,)), ("rcx", 1, (1,)), ("rdx", 2, (2,)), ("rsi", 3, (3,)),
       ("rbx", 4, (4,)), ("rbp", 5, (5,)), ("v0", 6, (0, 4)), ("v1", 7, (1, 5)),
       ("v2", 8, (2, 3)), ("v3", 9, (4, 0)), ("v4", 10, (1, 2))]
UN2 = [("rax", 0, (0,)), ("rcx", 1, (1,)), ("rbx", 3, (2,)),
       ("v0", 3, (0,)), ("v5", 4, (1,)), ("v2", 5, (0,))]

# `ra_ops0` / `ra_ops2`: `(op, srcs, tag)`, srcs and tag as intern indices.
OPS0 = [("CONST", (), ()), ("INS", (0,), (6,)), ("INS", (0,), (7,)), ("INS", (0,), (8,)),
        ("INS", (0,), (9,)), ("INS", (1,), ()), ("INS", (2,), ()), ("INS", (3, 4), (10,)),
        ("CONST", (), ()), ("INS", (1,), ()), ("INS", (2, 3), ()), ("INS", (4,), ())]
# `RaUop.ss` IS A LIST OF **NODE** INDICES, NOT REGISTER INDICES, and getting that wrong is
# the trap this fixture exists to avoid. `ra_rdef` (regalloc.bend:369-372) is `ds`'s HEAD --
# the DEF of a node -- and `ra_rdefs` (regalloc.bend:570) applies it to `ss`, so `ss` indexes
# `ops`. MEASURED, it has to: with `ss` read as registers, `ra0` would give `rax` a live range
# and five spill slots, and the port's own `ra0_lr` carries only `v0..v4`. So `("INS", (0,),
# (6,))` is "this uop's src is NODE 0, and it DEFINES register 6 (v0)", and node 0 is a
# CONST with no tag -- which is why no real register appears in `ra<t>_lr`.
#
# `regalloc.py:29`'s `loops[idx] = max(j for j,x in enumerate(uops) if u in x.src)` is
# therefore ported CORRECTLY as `ra_lastuse` (regalloc.bend:576-583), and `ra2`'s END srcs
# `[4, 3]` are nodes 4 and 3 -- node 3 IS the RANGE, which is the structural relation CPython
# asks for. MEASURED: rewriting those to `[4, 5]` -- replacing the RANGE with the END itself,
# so the loop has no user -- moves `ra2_lr`, `ra2_spills` and `ra2_before`, which is the
# right answer and not a defect.
OPS2 = [("CONST", (), ()), ("INS", (0,), (3,)), ("INS", (0,), (4,)), ("RANGE", (0,), ()),
        ("INS", (1, 2), (5,)), ("END", (4, 3), ())]


def mkregs(names):
    """Real `Register`s in intern order.

    A SELF-REFERENCE IS WRITTEN AS AN EMPTY `_cons`, AND THAT IS NOT A SPELLING CHOICE.
    `UN0`'s rax is `Ru{"rax", 0, [0]}` -- cons is intern index 0, which is rax ITSELF -- and
    a frozen dataclass cannot hold a reference to the value being constructed. CPython spells
    that case natively: `Register.cons` is a property, `_cons or (self,)` (`isa:16`), so an
    EMPTY `_cons` means "my own only candidate". So `c == (i,)` at position `i` becomes `()`,
    and the two lanes' `v.cons` are the same tuple of Registers. This is the shape that would
    otherwise have been a silent divergence, and it is called out because a reader checking
    `cons == (rax,)` on both sides will not see how the self case got there.
    """
    regs = []
    for i, (n, ix, c) in enumerate(names):
        regs.append(Register(n, ix, () if c == (i,) else tuple(regs[j] for j in c)))
    return regs


def mkops(regs, ops):
    """A src IS THE NODE THAT DEFINES ITS REGISTER -- `ss` holds node indices, so the src is
    `nodes[k]` itself and `rdef` reads that node's own `tag`. That is `isa/__init__.py:29-31`'s
    `rdef` and `regalloc.py:25`'s `rdef(s) for s in dedup(u.src)` in one move.

    A def is a `tag` TUPLE, because `regalloc.py:66` reads `isinstance(u.tag, tuple)`. A node
    with no def has `tag=None` and `rdef` answers `None`, which `regalloc.py:26`'s
    `isinstance(v, Register)` discards -- so the CONST at position 0 defines nothing.

    ONE FORWARD PASS, because `UOp` is hash-consed: a node referenced before it is built is a
    DIFFERENT object (a different src tuple is a different interning key), and
    `regalloc.py:29`'s `u in x.src` is an identity test over exactly those objects. Both
    fixtures only ever reference EARLIER nodes."""
    nodes = []
    for op, srcs, tg in ops:
        nodes.append(UOp(getattr(Ops, op), src=tuple(nodes[s] for s in srcs),
                         tag=(tuple(regs[t] for t in tg) if tg else None)))
    return nodes


# ===========================================================================
# THE RENDERER AND CONTEXT. Both hooks the port cannot ask tinygrad for.
# ===========================================================================
class TwoAddress(ISARenderer):
    """`regalloc.py:72` reads `ren.is_two_address(u)`; the base class answers `False`
    (`isa/__init__.py:46`) and `ra1` is the fixture that makes it True."""
    two = False

    def is_two_address(self, x):
        return self.two

    def fill(self, spill_slot, x, reg):
        return UOp(Ops.CUSTOM, arg=('fill', spill_slot, reg.name))

    def spill(self, spill_slot, x):
        return UOp(Ops.CUSTOM, arg=('spill', spill_slot))


class Slots(LinearContext):
    """`assign_spill_slot` is `NotImplementedError("arch specific")` in tinygrad's own base
    (`isa/__init__.py:37`). The port derives the slot from the register's NAME (`ra_slot`,
    regalloc.bend:737), so the oracle does too -- which makes `slot:v1` a spelling both lanes
    agree on rather than one lane's private invention."""

    def assign_spill_slot(self, r, u):
        return "slot:" + r.name


def ren_of(two):
    r = TwoAddress("NONE")
    r.two = two
    return r


# ===========================================================================
# THE ROWS.
# ===========================================================================
def pair(v, real, regs):
    """`v>intern->r>intern`. `intern` is the REGISTER'S POSITION in the universe, which is
    what the port's interner assigns and what `Register.index` is NOT (`ra_un2`'s rbx has
    index 3 and sits at position 2)."""
    return f"{v.name}>{regs.index(v)}->{real.name}>{regs.index(real)}"


def emit(pre, names, ops, two=False):
    regs = mkregs(names)
    uops = mkops(regs, ops)
    ren = ren_of(two)
    ctx = LinearScanRegallocContext(Slots(ren), uops, ren)
    row(f"{pre}_n", len(uops))
    srow(f"{pre}_uops", " ".join(u.op.name for u in uops))
    srow(f"{pre}_vregs", " ".join(f"{r.name}>{i}" for i, r in enumerate(regs)))
    srow(f"{pre}_lr", " ".join(
        f"{v.name}>{regs.index(v)}:{','.join(str(x) for x in ctx.live_range[v])}"
        for v in regs if v in ctx.live_range))
    for i in sorted(ctx.reals):
        srow(f"{pre}_a{i}", " ".join(sorted(
            pair(v, r, regs) for v, r in ctx.reals[i].items())))
    srow(f"{pre}_spills", " ".join(sorted(
        f"{v.name}>{regs.index(v)}:{ctx.spills[v]}" for v in regs if v in ctx.spills)))
    srow(f"{pre}_before", " ".join(
        f"{i}:" + " ".join(sorted(pair(v, r, regs) for v, r in ctx.insert_before[i]))
        for i in sorted(ctx.insert_before)))
    row(f"{pre}_loop", sum(1 for u in uops if u.op is Ops.RANGE))


def rw_none():
    """`regalloc_rewrite`'s SECOND return element, `before + [nx] + after` (`regalloc.py:114`),
    for every uop in order, with `-` where the rule returns None (`regalloc.py:101`).

    THE INDEX IS THE UOP INDEX, NOT A PSEUDO-FILTERED ONE. `regalloc_rewrite` reads
    `i = next(ctx.idx)` at :100 BEFORE the `PSEUDO_OPS` test at :101, and the UPat at :117
    MATCHES the pseudo ops too, so every uop consumes one counter value. A renumbered
    pseudo-filtered index is the off-by-k that makes an `insert_before[i]` row land on the
    wrong program point -- and `ra0_before` is exactly one such row.
    """
    regs = mkregs(UN0)
    uops = mkops(regs, OPS0)
    ren = ren_of(False)
    c = LinearScanRegallocContext(Slots(ren), uops, ren)
    items = []
    for x in uops:
        r = regalloc_rewrite(c, x)
        if r is None:
            items.append("-")
        else:
            items.append(f"{x.op.name}->" + ",".join(
                f"{u.op.name}/{u.arg!r}" if u.op is Ops.CUSTOM else u.op.name for u in r[1]))
    srow("rw_none", " ".join(items))


emit("ra0", UN0, OPS0, two=False)
emit("ra1", UN0, OPS0, two=True)
emit("ra2", UN2, OPS2, two=False)
rw_none()
row("rw_tbl_len", len(pm_regalloc_rewrite.patterns))
srow("rw_tbl_ops", " ".join(sorted(o.name for o in pm_regalloc_rewrite.patterns[0][0].op)))
row("rw_pseudo_n", len(PSEUDO_OPS))

print("\n".join(OUT))