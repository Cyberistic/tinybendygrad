#!/usr/bin/env python3
"""schedsched-oracle.py -- CPython's answer for the rows `tinybendygrad/schedule/__init__.bend`
prints about `create_schedule` (`tinygrad/schedule/__init__.py:32-80`).

WHY THIS FILE EXISTS. `schedule/__init__.bend` emits 111 rows from its own `main()` and NOT ONE
of them was compared against CPython: `gates/schedstore-oracle.py` covers the twelve rule bodies
and never calls `create_schedule`. Every expectation in that file's comments was a reading of
`.agents/slop/notes/sched-truth.py`, and that script is GONE (`find .agents -name 'sched-truth*'`
-> nothing), so today the rows are a memory of a deleted script. A row only the port prints
cannot go red. This file re-derives them by CALLING CPython.

WHAT IS MIRRORED, AND THE ONE RULE. Every fixture is the port's fixture with the SAME SOURCE
ARGUMENT ORDER, because `UOp.toposort` order -- and therefore the linearization -- is decided by
src order. Construction ORDER is NOT mirrored and must not be: it decides arena indices, and the
port names a node by its place in the graph precisely so indices cannot leak into a row.

THE READERS ARE THE PORT'S `gate.*`, string for string, not idea for idea: `code()` is one digit
per op, `marks` folds each kernel's STORE value base 10, `nsrcs` folds each kernel's arity base
10, `ops` folds every kernel src's op code base 10, `topo_marks` folds each readable CALL/END in
GATED TOPOSORT ORDER. Boolean rows print 0/1, exactly as the port's `b2u`.

WHAT IS NOT HERE, AND IT IS NAMED RATHER THAN DROPPED: `fx*_nodes` (an arena slot count -- the
port's own bookkeeping, no CPython analogue), every `COUNT_*` row (the four dicts are LOCALS in
`create_schedule`, so computing their sizes here would be re-implementing the algorithm instead
of asking it), and `split_bad_ks` (CPython RAISES on that fixture where the port deliberately
drops the SINK, so the two lanes do not answer the same question).
"""
import sys

from tinygrad.dtype import AddrSpace, dtypes
from tinygrad.schedule import _split_after, _states, _unwrap_src, create_schedule
from tinygrad.uop.ops import KernelInfo, Ops, ParamArg, UOp, gate_kernel_sink

CODE = {Ops.BUFFER: 1, Ops.AFTER: 2, Ops.PARAM: 3, Ops.CALL: 4, Ops.END: 5, Ops.STORE: 6,
        Ops.SINK: 7, Ops.SPECIAL: 8, Ops.CONST: 9, Ops.LINEAR: 10, Ops.MSTACK: 11, Ops.STAGE: 12}


def code(u: UOp) -> int:
    return CODE.get(u.op, 99 if u.op is Ops.NOOP else 0)


def b2u(b) -> int:
    return int(bool(b))


def kernel(rk: UOp) -> UOp:
    return rk.src[0] if rk.op is Ops.END else rk


def readable(rk: UOp) -> bool:
    k = kernel(rk)
    return rk.op in (Ops.CALL, Ops.END) and k.body.op is Ops.SINK and k.body.src[0].op is Ops.STORE


def mark(rk: UOp) -> int:
    return kernel(rk).body.src[0].src[1].val


def marks(lin_: UOp) -> int:
    acc = 0
    for k in lin_.src:
        acc = acc * 10 + mark(k)
    return acc


def nsrcs(lin_: UOp) -> int:
    acc = 0
    for k in lin_.src:
        acc = acc * 10 + len(k.src)
    return acc


def ops(lin_: UOp) -> int:
    acc = 0
    for k in lin_.src:
        for s in k.src:
            acc = acc * 10 + code(s)
    return acc


def topo_marks(sink: UOp) -> int:
    acc = 0
    for u in sink.toposort(gate_kernel_sink):
        if readable(u):
            acc = acc * 10 + mark(u)
    return acc


def lin_n(lin_: UOp) -> int:
    return len(lin_.src)


def lin_op(lin_: UOp) -> int:
    return code(lin_)


# ---- fixtures: src ORDER identical to the port's, indices irrelevant ----
def g_buf(slot: int, nm: str) -> UOp:
    # `UOp._buffer` (ops.py:831) is `src=(shape_to_shape_arg((size,)),)+device_range_src(device)`,
    # and `device_range_src` is `()` for a SINGLE STRING device (:829). So a BUFFER's src is
    # ONE CONST and there is NO SPECIAL -- MEASURED: building the SPECIAL form gave a toposort
    # of `CONST SPECIAL BUFFER ...` where CPython's own `_buffer` gives `CONST BUFFER ...`,
    # which moved every `fx*_topo` row by one. The port was right here and this oracle was not.
    return UOp(Ops.BUFFER, src=(UOp.const(1),),
               arg=ParamArg(slot, dtypes.int32, name=nm, addrspace=AddrSpace.GLOBAL, device="CPU"))


def g_body(n: int) -> UOp:
    return UOp(Ops.SINK, src=(UOp(Ops.STORE, src=(UOp.const(0), UOp.const(n))),))


def fx0() -> UOp:
    return UOp(Ops.SINK, src=())


def fx1():
    a, b = g_buf(0, "a"), g_buf(1, "b")
    d1, d2 = g_body(1), g_body(2)
    vb = UOp.variable("v", 0, 10, dtype=dtypes.int32).bind(3)
    k1 = UOp(Ops.CALL, src=(d1, a))
    k2 = UOp(Ops.CALL, src=(d2, b, vb))
    e2 = UOp(Ops.END, src=(k2,))
    f1 = UOp(Ops.AFTER, src=(a, k1))
    f2 = UOp(Ops.AFTER, src=(f1, e2))
    sa = UOp.sink(a)
    top = UOp(Ops.SINK, src=(f2, sa))
    return dict(top=top, af2=f2, sa=sa, af1=f1, e2=e2, a=a, k1=k1, k2=k2, b=b, vb=vb,
                vu=UOp.variable("u", 0, 10, dtype=dtypes.int32))


def fx2():
    a, x = g_buf(0, "a2"), g_buf(1, "x2")
    d1, d2, d3 = g_body(1), g_body(2), g_body(3)
    ka = UOp(Ops.CALL, src=(d1, a))
    kb = UOp(Ops.CALL, src=(d2, a))
    kc = UOp(Ops.CALL, src=(d3, x))
    fa = UOp(Ops.AFTER, src=(a, ka))
    fb = UOp(Ops.AFTER, src=(fa, kb))
    fc = UOp(Ops.AFTER, src=(x, kc))
    top = UOp(Ops.SINK, src=(fb, fc, UOp.sink(a)))
    return dict(top=top, afb=fb, afc=fc, fa=fa, ka=ka, kb=kb, kc=kc, a=a, x=x)


def fx3():
    a = g_buf(0, "a3")
    d3 = g_body(3)
    k3 = UOp(Ops.CALL, src=(d3, a))
    g1 = UOp(Ops.AFTER, src=(a, k3))
    g2 = UOp(Ops.AFTER, src=(g1, k3))
    top = UOp(Ops.SINK, src=(g2, UOp.sink(a)))
    return dict(top=top, ag2=g2, ag1=g1, k3=k3, a=a,
                ag3=UOp(Ops.AFTER, src=(g2, g1)))


def fx4():
    a = g_buf(0, "a4")
    st = UOp(Ops.STAGE, src=(UOp.const(0), UOp.const(1)))
    return dict(ms=UOp(Ops.MSTACK, src=(a, a)), st=st, a=a)


def fx5():
    a = g_buf(0, "a5")
    d1, d2 = g_body(1), g_body(2)
    ka = UOp(Ops.CALL, src=(d1, a))
    fa = UOp(Ops.AFTER, src=(a, ka))
    kb = UOp(Ops.CALL, src=(d2, a, fa))
    fb = UOp(Ops.AFTER, src=(fa, kb))
    top = UOp(Ops.SINK, src=(fb, UOp.sink(a)))
    return dict(top=top, afb=fb, afa=fa, ka=ka, kb=kb, a=a)


def fx7():
    a, a2 = g_buf(0, "a7"), g_buf(1, "a7b")
    d1, d3 = g_body(1), g_body(3)
    k1 = UOp(Ops.CALL, src=(d1, a))
    f1 = UOp(Ops.AFTER, src=(a, k1))
    k3 = UOp(Ops.CALL, src=(d3, a2))
    g = UOp(Ops.AFTER, src=(a2, k3))
    body2 = UOp.sink(g)
    k2 = UOp(Ops.CALL, src=(body2, a2))
    top = UOp(Ops.SINK, src=(f1, k2, UOp.sink(a)))
    return dict(top=top, k1=k1, k2=k2, k3=k3, f1=f1, a=a, a2=a2)


def fx8():
    a = g_buf(0, "a8")
    d1 = g_body(1)
    k1 = UOp(Ops.CALL, src=(d1, a))
    f1 = UOp(Ops.AFTER, src=(a, k1))
    kin = UOp(Ops.SINK, src=(f1,), arg=KernelInfo())
    sa = UOp.sink(a)
    return dict(top=UOp(Ops.SINK, src=(kin, sa)), kin=kin, sa=sa, k1=k1, f1=f1, a=a)


def fx1_bad():
    a, k1 = g_buf(0, "a"), UOp(Ops.CALL, src=(g_body(1), g_buf(0, "a")))
    return UOp(Ops.AFTER, src=(k1, UOp.sink(a)))


def rows() -> dict:
    r = {}
    F1, F2, F3, F4, F5, F7, F8 = fx1(), fx2(), fx3(), fx4(), fx5(), fx7(), fx8()

    # ---- _unwrap_src / _states / _split_after / buf_uop / is_bound_var ----
    for nm, u in (("A1", F1["a"]), ("B1", F1["b"]), ("Vb", F1["vb"]),
                  ("AF1", F1["af1"]), ("AF2", F1["af2"])):
        r[f"unwrap_{nm}"] = code(_unwrap_src(u))
    r["unwrap_bad"] = code(_unwrap_src(fx1_bad()))
    for nm, u in (("A1", F1["a"]), ("AF2", F1["af2"]), ("AG2", F3["ag2"])):
        r[f"states_{nm}"] = len(_states(u))
    for nm, u in (("A1", F1["a"]), ("AF1", F1["af1"]), ("AF2", F1["af2"]),
                  ("AG1", F3["ag1"]), ("AG2", F3["ag2"])):
        r[f"split_{nm}_ks"] = len(_split_after(u)[0])
    r["split_AF2_ds"] = len(_split_after(F1["af2"])[1])
    r["split_AG3_ks"], r["split_AG3_ds"] = (len(x) for x in _split_after(F3["ag3"]))
    for nm, u in (("A1", F1["a"]), ("AF1", F1["af1"]), ("AF2", F1["af2"]), ("Vb", F1["vb"]),
                  ("AG1", F3["ag1"]), ("AG2", F3["ag2"]), ("STAGE", F4["st"]),
                  ("MSTACK", F4["ms"])):
        r[f"bufuop_{nm}"] = code(u.buf_uop)
    for nm, u in (("Vb", F1["vb"]), ("Vu", F1["vu"]), ("A1", F1["a"]), ("K2src2", F1["k2"].src[2])):
        r[f"bv_{nm}"] = b2u(u.is_bound_var)
    for nm, k, t in (("K2_K1", F1["k2"], F1["k1"]), ("E2_K2", F1["e2"], F1["k2"]),
                     ("K1_K2", F1["k1"], F1["k2"]), ("Kb_Ka", F2["kb"], F2["ka"]),
                     ("Ka_Kb", F5["kb"], F5["ka"])):
        r[f"bs_{nm}"] = b2u(t in k.backward_slice)

    # ---- the linearization: create_schedule ITSELF ----
    for nm, F in (("fx0", None), ("fx1", F1), ("fx2", F2), ("fx3", F3),
                  ("fx5", F5), ("fx7", F7), ("fx8", F8)):
        top = fx0() if F is None else F["top"]
        lin_ = create_schedule(top)
        r[f"{nm}_topo"] = len(top.toposort(gate_kernel_sink))
        r[f"{nm}_lin_n"] = lin_n(lin_)
        r[f"{nm}_lin_op"] = lin_op(lin_)
        r[f"{nm}_marks"] = marks(lin_)
        r[f"{nm}_nsrcs"] = nsrcs(lin_)
        r[f"{nm}_ops"] = ops(lin_)
        if F is not None:
            r[f"{nm}_topo_marks"] = topo_marks(top)

    r["gate_ki"] = b2u(gate_kernel_sink(F8["kin"]))
    r["gate_plain"] = b2u(gate_kernel_sink(F8["sa"]))
    return r


# THE ORDER IS THE PORT'S `main()`, TRANSCRIBED. `gates/gatekit.py` diffs the two lanes
# POSITIONALLY (`zip`), so the two lanes must enumerate the same rows in the same sequence.
# Derived from the port's own `row("...")` calls with the 27 port-only names removed, so this
# list and the port cannot drift without the gate failing on a count or a pin.
ORDER = (
    "unwrap_A1", "unwrap_B1", "unwrap_Vb", "unwrap_AF1",
    "unwrap_AF2", "unwrap_bad", "split_A1_ks", "split_AF1_ks",
    "split_AF2_ks", "split_AG1_ks", "split_AG2_ks", "split_AF2_ds",
    "states_A1", "states_AF2", "states_AG2", "bufuop_A1",
    "bufuop_AF1", "bufuop_AF2", "bufuop_Vb", "bufuop_AG1",
    "bufuop_AG2", "bv_Vb", "bv_Vu", "bv_A1",
    "bv_K2src2", "bs_K2_K1", "bs_E2_K2", "bs_K1_K2",
    "bs_Kb_Ka", "fx1_topo", "fx1_lin_n", "fx1_lin_op",
    "fx1_marks", "fx1_nsrcs", "fx1_ops", "fx2_topo",
    "fx2_lin_n", "fx2_lin_op", "fx2_marks", "fx2_nsrcs",
    "fx2_ops", "split_AG3_ks", "split_AG3_ds", "bufuop_STAGE",
    "bufuop_MSTACK", "fx3_lin_n", "fx3_marks", "fx3_topo",
    "fx3_lin_op", "fx3_nsrcs", "fx3_ops", "fx1_topo_marks",
    "fx2_topo_marks", "fx3_topo_marks", "fx5_topo_marks", "fx0_topo",
    "fx0_lin_n", "fx0_lin_op", "fx0_marks", "fx0_nsrcs",
    "fx0_ops", "fx7_topo_marks", "fx7_topo", "fx7_lin_n",
    "fx7_lin_op", "fx7_marks", "fx7_nsrcs", "fx7_ops",
    "fx8_topo_marks", "fx8_topo", "fx8_lin_n", "fx8_lin_op",
    "fx8_marks", "fx8_nsrcs", "fx8_ops", "gate_ki",
    "gate_plain", "fx5_topo", "fx5_lin_n", "fx5_lin_op",
    "fx5_marks", "fx5_nsrcs", "fx5_ops", "bs_Ka_Kb",
)


def main() -> None:
    out = rows()
    if "--rows" in sys.argv:
        print("\n".join(sorted(out)))
        return
    # A NAME IN `ORDER` THAT THIS FILE NO LONGER PRODUCES IS A CRASH, not a short lane: a
    # missing row must never read as agreement by omission.
    missing = [n for n in ORDER if n not in out]
    if missing:
        raise SystemExit(f"schedsched-oracle: no answer for {missing}")
    extra = sorted(set(out) - set(ORDER))
    if extra:
        raise SystemExit(f"schedsched-oracle: rows not in the port's order: {extra}")
    print("\n".join(f"{n}={out[n]}" for n in ORDER))


if __name__ == "__main__":
    main()
