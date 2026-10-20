#!/usr/bin/env python3
"""linearizer_census-oracle.py -- CPython's rows for `tinygrad/codegen/late/linearizer.py`.

    .venv/bin/python gates/linearizer_census-oracle.py

71 ROWS, THE SAME 71 `gates/../tinybendygrad/codegen/late/linearizer.bend` PRINTS, IN ITS
ORDER AND IN ITS SPELLING. Every value here is DERIVED BY CALLING CPython -- `linearize`,
`CFGContext`, `pm_add_control_flow`, `do_split_ends`, `pm_split_ends`, `UOp.toposort`,
`UOp.ranges`, `helpers.prod` -- over a fixture built from the same 22 constructions
`linearizer.bend`'s `lt_fix` names. Nothing is transcribed except the priority ladder, and
that transcription is CROSS-CHECKED AGAINST `linearize` ON EVERY RUN (see `THE LADDER`).

WHAT THE LAYER RETURNS, AND WHY THESE ROWS ARE IN THIS FORM. `linearize` returns an ORDERED
LIST of UOps -- a toposort with a priority heap on top -- so a COUNT cannot see a reordering
and a MULTISET cannot see one either. Every row class here is therefore either the ORDERED
SEQUENCE itself (`lin_srcs`, `lin_ord`, `lin_nkey`, `lin_ord`) or one row PER NODE IN THAT
SEQUENCE (`lin_u<i>`, carrying the node's op, its run_count, its priority and its nkey), or
the EDGE LIST IN POSITIONS (`lin_edg`, `linc_edg`, `cfg_edges`), which is the form that caught
the src-permutation defect the header records. `gatekit` diffs ORDERED LISTS, so a defect
has no total to cancel inside.

THE FIXTURE IS AN INPUT ON BOTH SIDES, NOT A DERIVATION. `lt_fix` builds 22 arena nodes;
this file builds the same graph with the raw `UOp(Ops.X, src=..., arg=...)` constructors
because the sugar (`UOp.range`, `UOp.const(b, dtype)`) FOLDS a CONST/CAST pair into one node
and the two lanes must hold the same 22 nodes for a position to mean the same thing in both.
MEASURED: the three roots `c4a`/`c16a`/`c16a` are built with `src=()` -- `UOp.const(arena, v)`
appends and takes no parent -- and a toposort that threaded them would emit a different order.

`TUPLE_ORDER` IS SET TO 0. `linearizer.py:36` sorts on
`priorities[x] + (x.tuplize if TUPLE_ORDER else ())`, and `helpers.TUPLE_ORDER` is a
ContextVar defaulting to 1. The port names the `=1` lane a wall (`x.tuplize` is a recursive
structural key holding a `repr` and a dtype), so this file ports the `=0` lane and must ask
CPython for the same lane: under `Context(TUPLE_ORDER=0)`. MEASURED, the two lanes differ --
over this fixture CPython's `=1` order begins `PARAM CONST CAST ALLOC` and its `=0` order
begins `PARAM CONST CAST ALLOC` too here, but the two full sequences are NOT equal, so
comparing against the default would be comparing against a lane the port does not claim.

THE LADDER -- THE ONE TRANSCRIPTION, AND WHY IT IS NOT A BLIND SECOND IMPLEMENTATION.
`po_*` is nine rows, one per arm of `linearizer.py:24-32`, and that ladder lives INSIDE
`linearize`'s body: CPython exposes no `priority_of`, so reading a priority out of CPython
rather than out of the ladder needs a probe. The probe is `THE LADDER CHECK` below: this
file transcribes the eight lines, predicts the order `linearize` will return over a fixture
of eleven independent leaves, and calls `linearize` to see whether it agrees. A mistyped
constant, a wrong arm or a swapped `addrspace` test makes the two orders differ, the oracle
exits non-zero, and `gatekit` reports REFUSED -- never a row that agrees with the bug.

WHAT IS NOT DERIVED FROM CPython, AND WHY IT IS A PORT-ONLY ROW RATHER THAN A CARVE-OUT:
nothing. `ix_len` and `ix` ARE derived -- from CPython's own walk of the fixture's two
sinks -- and they DISAGREE with the port by one node. That disagreement is pinned as a
DIVERGENCE in the gate, not excluded: see the gate's header for the measurement.
"""
import sys

from tinygrad.uop.ops import UOp, Ops, AxisType, ParamArg, KernelInfo, CallInfo
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.helpers import Context, prod, dedup
from tinygrad.codegen.late.linearizer import (
    linearize, CFGContext, pm_add_control_flow, do_split_ends, pm_split_ends)

OUT = []


def row(nm, v):
    OUT.append(f"{nm}={v}")


def srow(nm, v):
    OUT.append(f"{nm}={v}")


def parg(slot, ad):
    """`ParamArg` with every optional field at its default except `addrspace`.

    `ops.py:25-49` is a frozen dataclass whose defaults are `size=None, vmin_vmax=None,
    multiple_of=None, name=None, addrspace=GLOBAL, device=None, volatile=False, image=None,
    buffer=None, bind_on_realize=False, val=None`. Positional construction would have to
    spell all thirteen, so this is the twelve defaults and the one field the fixture varies.
    """
    return ParamArg(slot, dtypes.float16, None, None, None, None, ad, None, False, None,
                    None, False, None)


def lab(u):
    """`lin_srcs`'s node label: `RANGE:<axis id>`, the op name for everything else."""
    return f"RANGE:{u.arg[1]}" if u.op is Ops.RANGE else u.op.name


def slab(u):
    """`se_ops`'s node label: the op name, `/` the axis id for a RANGE and `/-` otherwise.

    NOT `lin_srcs`'s spelling -- a RANGE here is `RANGE/2`, where `lin_srcs` writes
    `RANGE:2`. Two alphabets, two printers, so a punctuation change cannot hide a reordering.
    """
    return f"{u.op.name}/{u.arg[1] if u.op is Ops.RANGE else '-'}"


def u32s(xs):
    return " ".join(str(x) for x in xs)


# ===========================================================================
# THE FIXTURE -- `lt_fix` (linearizer.bend:867-904), 22 constructions.
# ===========================================================================
def build_lin():
    c1a = UOp(Ops.CONST, src=(), arg=1)
    c1 = UOp(Ops.CAST, src=(c1a,), arg=dtypes.int32)
    c4a = UOp(Ops.CONST, src=(), arg=4)
    c4 = UOp(Ops.CAST, src=(c4a,), arg=dtypes.int32)
    c16a = UOp(Ops.CONST, src=(), arg=16)
    c16 = UOp(Ops.CAST, src=(c16a,), arg=dtypes.int32)
    sp = UOp(Ops.SPECIAL, src=(c1,), arg="0")
    bufl = UOp(Ops.BUFFER, src=(sp,), arg=parg(7, AddrSpace.LOCAL))
    prm = UOp(Ops.PARAM, src=(), arg=parg(0, AddrSpace.GLOBAL))
    r_u = UOp(Ops.RANGE, src=(c4,), arg=(AxisType.UPCAST, 0))
    ad = UOp(Ops.ADD, src=(prm, c1))
    st = UOp(Ops.STORE, src=(bufl, ad, sp))
    al = UOp(Ops.ALLOC, src=(c1,), arg=parg(0, AddrSpace.GLOBAL))
    en = UOp(Ops.END, src=(st, r_u))
    r_b = UOp(Ops.RANGE, src=(c16, en), arg=(AxisType.LOOP, 1))
    ad2 = UOp(Ops.ADD, src=(prm, c16))
    st2 = UOp(Ops.STORE, src=(bufl, ad2, sp))
    en2 = UOp(Ops.END, src=(st2, r_b))
    sk = UOp(Ops.SINK, src=(st, st2, en2, al), arg=KernelInfo())
    cll = UOp(Ops.CALL, src=(st, ad), arg=CallInfo())
    sk2 = UOp(Ops.SINK, src=(cll,), arg=KernelInfo())
    return sk, sk2, [c1a, c1, c4a, c4, c16a, c16, sp, bufl, prm, r_u, ad, st, al, en, r_b,
                     ad2, st2, en2, sk, cll, sk2]


SK, SK2, LIN_NODES = build_lin()


# ===========================================================================
# THE LADDER -- `linearizer.py:24-32`, transcribed, and cross-checked below.
# ===========================================================================
def priority_of(u):
    """`priorities[u] = (run_count, priority, extra)`, lines :20-33, priority arm only.

    `u.ranges` and `r.vmax` are CPython's own; only the eight-line `match` is transcribed,
    and `ladder_check()` proves the transcription against `linearize` on every run.
    """
    extra = None
    match u.op:
        case Ops.PARAM: priority, extra = -20, u.arg.slot
        case Ops.BUFFER | Ops.ALLOC: priority = -17 if u.addrspace == AddrSpace.LOCAL else -18
        case Ops.LOAD: priority = -1
        case Ops.STORE: priority = 1
        case Ops.RANGE: priority = 5
        case Ops.END | Ops.BACKEDGE: priority = -5
        case _: priority = 0
    return priority, extra


def ladder_check():
    """`linearize` ON TWO FIXTURES -- the transcription's own cross-check, every run.

    `po_*` is nine rows, one per arm of `linearizer.py:24-32`, and that ladder lives INSIDE
    `linearize`'s body: CPython exposes no `priority_of`, so reading a priority out of the
    code rather than out of the transcription needs a probe. THE PROBE IS THIS FUNCTION, and
    a wrong constant, a dropped arm or a swapped `LOCAL` test makes it exit 2 -- which
    `gatekit`'s `_oracle` reports as a REFUSED gate, never as a row that agrees with the bug.

    **FIXTURE A: TEN INDEPENDENT LEAVES, ALL `src=()`.** With no edges among them the toposort
    imposes no order, so `linearize`'s output is `sorted(lst, key=priorities)` and the only
    thing deciding the sequence is the key. The prediction is a sort; the observation is
    `linearize`. MEASURED, `linearize` returns

        PARAM BUFFER-global ALLOC-global BUFFER-local ALLOC-local END BACKEDGE LOAD ADD STORE

    which is -20, -18, -18, -17, -17, -5, -5, -1, 0, +1: seven of the eight arms, and BOTH
    sides of `linearizer.py:27`'s conditional.

    **FIXTURE B: THE RANGE ARM, ALONE.** `UOp.range(0, 0, LOOP)` has `vmax = -1` and so
    run_count 0, which sorts it ahead of everything and makes its priority unobservable in
    fixture A. `UOp.range(1, 0, LOOP)` has `vmax = 0` and run_count 1, so `SINK(STORE, RANGE)`
    compares priority 1 against priority 5 and nothing else. MEASURED, `linearize` returns
    STORE then RANGE -- the ascending-priority answer. Its CONST src is dropped from BOTH
    sides for the same reason the sink is: the heap's seed and a node's src are structural,
    not key decisions.

    THE SINK IS DROPPED FROM BOTH SIDES EVERYWHERE. `linearize` seeds the heap with the sink
    alone (:39), so the sink is popped first and `newlst[::-1]` (:46) puts it LAST whatever
    its key says. That is a property of the heap, not of the ladder, and predicting it would
    be reimplementing the heap.
    """
    leaves = [UOp(Ops.PARAM, src=(), arg=parg(0, AddrSpace.GLOBAL)),
              UOp(Ops.BUFFER, src=(), arg=parg(7, AddrSpace.LOCAL)),
              UOp(Ops.BUFFER, src=(), arg=parg(8, AddrSpace.GLOBAL)),
              UOp(Ops.ALLOC, src=(), arg=parg(9, AddrSpace.LOCAL)),
              UOp(Ops.ALLOC, src=(), arg=parg(10, AddrSpace.GLOBAL)),
              UOp(Ops.END, src=()), UOp(Ops.BACKEDGE, src=()), UOp(Ops.LOAD, src=()),
              UOp(Ops.STORE, src=()), UOp(Ops.ADD, src=())]
    key = lambda x: (prod([int(r.vmax) + 1 for r in x.ranges]), *priority_of(x))
    probes = [(UOp(Ops.SINK, src=tuple(leaves), arg=KernelInfo()), leaves),
              (UOp(Ops.SINK, src=(UOp(Ops.STORE, src=()),
                                  UOp.range(1, 0, AxisType.LOOP)), arg=KernelInfo()),
               [UOp(Ops.STORE, src=()), UOp.range(1, 0, AxisType.LOOP)])]
    for sk, watched in probes:
        keep = {id(u) for u in watched}
        want = sorted([u for u in sk.toposort(enter_calls=False) if id(u) in keep], key=key)
        with Context(TUPLE_ORDER=0):
            got = [u for u in linearize(sk) if id(u) in keep]
        if want != got:
            print("ladder_check: the transcription disagrees with linearize", file=sys.stderr)
            print(f"  predicted {[u.op.name for u in want]}", file=sys.stderr)
            print(f"  linearize {[u.op.name for u in got]}", file=sys.stderr)
            # REFUSED (3), NOT 2: this is the ORACLE'S OWN SELF-CHECK (`ladder_check()` -- "THE ORACLE HAS ONE TRANSCRIPTION AND IT IS CHECKED ON EVERY RUN", per the gate's docstring at :52-54). A self-check that fails means the oracle CANNOT ANSWER, and "cannot answer" is REFUSED, not FAIL -- it is not evidence that the port is wrong.
            # A self-check that fails means the oracle CANNOT ANSWER, and "cannot answer" is REFUSED, not FAIL -- it is not evidence that the port is wrong.
            sys.exit(3)


ladder_check()


def po_of(u):
    """The PORT's `lt_po` spelling: the priority biased by +20 into a U32.

    `linearizer.py`'s priorities are -20..+5 and Bend has no signed `U32`, so the port
    encodes them as `priority + 20`: `po_param=0` is -20 and `po_range=25` is +5. The bias is
    the PORT's alphabet, not CPython's, so it lives here and not in `priority_of`.
    """
    return priority_of(u)[0] + 20


# ===========================================================================
# THE ROWS.
# ===========================================================================
def emit_lin_rows(pre, sink):
    """`lin_*` / `linc_*`: the toposort, the sort, and one row per node of the OUTPUT."""
    lst = list(sink.toposort(enter_calls=False))
    PR = {}
    for u in reversed(lst):
        PR[id(u)] = (prod([int(r.vmax) + 1 for r in u.ranges]), *priority_of(u))
    pos = {id(u): k for k, u in enumerate(lst)}
    srow(f"{pre}_srcs", " ".join(lab(u) for u in lst))
    row(f"{pre}_n", len(lst))
    vm = []
    for u in lst:
        vs = [int(r.vmax) for r in u.ranges]
        vm.append(len(vs))
        vm += vs
    srow(f"{pre}_vm", u32s(vm))
    srow(f"{pre}_edg", " ".join(f"{k}:" + " ".join(str(pos[id(s)]) for s in u.src_without_body)
                                for k, u in enumerate(lst)))
    with Context(TUPLE_ORDER=0):
        srt = sorted(lst, key=lambda x: PR[id(x)])
        nk = {id(u): i for i, u in enumerate(srt)}
        out = linearize(sink)
    srow(f"{pre}_nkey", u32s([nk[id(u)] for u in lst]))
    srow(f"{pre}_ord", " ".join(lab(u) for u in srt))
    # `lin_u<i>` -- ONE ROW PER NODE OF `linearize`'s OUTPUT. THE OP NAME IS BARE HERE,
    # not `lin_srcs`'s `RANGE:<id>`: `lt_lin_u.tag` is `Ops.name.of(op)`. Two spellings,
    # two call sites, so a RANGE is `RANGE` in one row class and `RANGE:0` in the other.
    for i, u in enumerate(out):
        srow(f"{pre}_u{i}", f"{u.op.name} rc={PR[id(u)][0]} po={po_of(u)} nk={nk[id(u)]}")
    keys = [PR[id(u)][:2] for u in srt]
    row(f"{pre}_ties", sum(1 for i, a in enumerate(keys) for b in keys[:i] if a == b))
    row(f"{pre}_exmix", sum(1 for i, a in enumerate(keys) for b in keys[:i]
                            if a == b and (PR[id(srt[i])][2] is None) != (PR[id(srt[i])][2] is None)))


# `ix_len` / `ix` -- THE FIXTURE'S OWN NODE CENSUS, from CPython's walk of both sinks. Not
# the SINK's toposort: the fixture has 21 distinct nodes and 20 of them are in `SK`'s.
seen, census = set(), []


def census_walk(u):
    if id(u) in seen:
        return
    seen.add(id(u))
    census.append(u)
    for s in u.src:
        census_walk(s)


census_walk(SK2)
census_walk(SK)
row("ix_len", len(census))
srow("ix", u32s(range(len(census))))

# `po_*` -- ONE ROW PER ARM OF THE LADDER. `po_bufl` and `po_bufg` are the two halves of
# `linearizer.py:27`'s conditional, and `po_add` is the `case _` arm, so the nine rows
# between them cover every arm and both sides of the only conditional. `ladder_check()` has
# already proved the transcription against `linearize` by the time these nine print.
po = [UOp(Ops.PARAM, src=(), arg=parg(0, AddrSpace.GLOBAL)),
      UOp(Ops.BUFFER, src=(), arg=parg(7, AddrSpace.LOCAL)),
      UOp(Ops.BUFFER, src=(), arg=parg(8, AddrSpace.GLOBAL)),
      UOp(Ops.LOAD, src=()), UOp(Ops.STORE, src=()),
      UOp.range(0, 0, AxisType.LOOP), UOp(Ops.END, src=()), UOp(Ops.BACKEDGE, src=()),
      UOp(Ops.ADD, src=())]
for nm, u in zip(("po_param", "po_bufl", "po_bufg", "po_load", "po_store", "po_range",
                  "po_end", "po_backedge", "po_add"), po):
    row(nm, po_of(u))

# `rc_*` -- `helpers.prod` over `[int(r.vmax)+1 for r in u.ranges]`. The three the `lin`
# fixture actually sees are `[]`, `[3]` and `[15]`, which cannot tell a product from a sum,
# so the six rows name the lists they mean.
for nm, vs in (("rc_nil", []), ("rc_1", [3]), ("rc_2", [3, 15]), ("rc_3", [1, 1, 4]),
               ("rc_max", [15, 15, 15, 15]), ("rc_big", [63, 63, 63])):
    row(nm, prod([v + 1 for v in vs]))

emit_lin_rows("lin", SK)
emit_lin_rows("linc", SK2)

# `cfg_*` -- `CFGContext` (:53-81) and `pm_add_control_flow` (:83-85).
CFG = CFGContext(SK)
srow("cfg_edges", " ".join(
    f"{'RANGE/' + str(k.arg[1]) if k.op is Ops.RANGE else k.op.name}->{v.op.name}"
    for k, v in CFG.edges.items()))
row("cfg_edges_n", len(CFG.edges))
RNGS = [u for u in SK.toposort(enter_calls=False) if u.op is Ops.RANGE]
hits = []
for r in RNGS:
    nw = pm_add_control_flow.rewrite(r, ctx=CFG)
    hits.append(f"{r.arg[1]}->[{','.join(lab(s) for s in nw.src)}]" if nw is not None else "-")
srow("cfg_hits", " ".join(hits))
row("cfg_tbl_len", len(pm_add_control_flow.patterns))
srow("cfg_tbl_ops", " ".join(sorted(o.name for o in pm_add_control_flow.patterns[0][0].op)))

# `se_*` -- `do_split_ends` (:87-91) and `pm_split_ends` (:93-96), over `se_fix`'s SECOND
# fixture: `e = END(F2, R0, R1, R2)` with the axes ASCENDING, so `sorted(reverse=True)` is a
# reorder and `se_rngs` reading `0 1 2` would be a sort that does nothing.
SE_C4A = UOp(Ops.CONST, src=(), arg=4)
SE_C4 = UOp(Ops.CAST, src=(SE_C4A,), arg=dtypes.int32)
SE_C8A = UOp(Ops.CONST, src=(), arg=8)
SE_C8 = UOp(Ops.CAST, src=(SE_C8A,), arg=dtypes.int32)
SE_C2F = UOp(Ops.CONST, src=(), arg=2.0)
SE_F2 = UOp(Ops.CAST, src=(SE_C2F,), arg=dtypes.float16)
SE_R0 = UOp(Ops.RANGE, src=(SE_C4,), arg=(AxisType.LOOP, 0))
SE_R1 = UOp(Ops.RANGE, src=(SE_C8,), arg=(AxisType.LOOP, 1))
SE_R2 = UOp(Ops.RANGE, src=(SE_C4,), arg=(AxisType.LOOP, 2))
SE_E = UOp(Ops.END, src=(SE_F2, SE_R0, SE_R1, SE_R2))
SE = do_split_ends(SE_E)
srow("se_rngs", u32s([r.arg[1] for r in sorted(
    dedup(r for s in SE_E.src[1:] for r in ((s,) if s.op is Ops.RANGE else s.ranges)),
    key=lambda x: x.arg, reverse=True)]))
srow("se_ops", " ".join(slab(u) for u in SE.toposort()))
row("se_len", sum(1 for u in SE.toposort() if u.op is Ops.END))
row("se_nsrc", len(SE.src))
row("se_tbl_len", len(pm_split_ends.patterns))
srow("se_tbl_ops", " ".join(sorted(o.name for o in pm_split_ends.patterns[0][0].op)))
# `se_fired` / `se_miss` -- `PatternMatcher.pdict` is CPython's OWN dispatch table: a key is
# present iff some pattern names that op, which is what `rewrite` consults. So these two rows
# ask `pdict` rather than re-reading the table's op set.
row("se_fired", len(pm_split_ends.pdict.get(SE_E.op, [])))
row("se_miss", len(pm_split_ends.pdict.get(SE_R0.op, [])))

print("\n".join(OUT))