"""THE CPYTHON ORACLE for tinybendygrad/schedule/__init__.bend.

It mirrors the port's fixtures ONE FOR ONE (same construction order, same ops,
same srcs) and answers the SAME rows the port's gate prints, so the two lanes
are comparable line by line.  CPython is the reference: `tinygrad.schedule` is
the upstream file at the pin, unmodified.

The port's arena indices are NOT reproducible here (CPython has no arena), so
every row below is one the port can answer by GRAPH IDENTITY rather than by
index: the fixture is built here and the SAME nodes are looked up by name.

usage: .venv/bin/python oracles/schedule-bodies/sb-oracle.py [rows...]
"""
import sys

from tinygrad.dtype import AddrSpace, dtypes
from tinygrad.uop.ops import KernelInfo, Ops, ParamArg, UOp
from tinygrad.schedule import create_schedule

CODE = {
    Ops.BUFFER: 1, Ops.AFTER: 2, Ops.PARAM: 3, Ops.CALL: 4, Ops.END: 5,
    Ops.STORE: 6, Ops.SINK: 7, Ops.SPECIAL: 8, Ops.CONST: 9, Ops.LINEAR: 10,
    Ops.MSTACK: 11, Ops.STAGE: 12, Ops.ALLOC: 13, Ops.PROGRAM: 14,
}


def code(u: UOp) -> int:
    return CODE.get(u.op, 0)


# --------------------------------------------------------------------------
# THE FIXTURES -- the port's `g_buf`, `g_body`, `g_pv` and the five `fx*`.
# --------------------------------------------------------------------------
def g_pb(slot: int, nm: str) -> ParamArg:
    return ParamArg(slot, dtypes.int32, name=nm, device="CPU")


def g_pv(nm: str, val) -> ParamArg:
    return ParamArg(0, dtypes.int32, vmin_vmax=(0, 10), multiple_of=1, name=nm,
                    addrspace=AddrSpace.ALU, val=val)


def g_buf(slot: int, nm: str) -> UOp:
    # the port's `g_buf` interns the SPECIAL and never links it to the BUFFER;
    # CPython interns it too (the ucache), so the two graphs agree node for node.
    z = UOp.const(1, dtypes.int32)
    UOp(Ops.SPECIAL, src=(z,), arg=nm)
    return UOp(Ops.BUFFER, src=(UOp.const(4, dtypes.int32),), arg=g_pb(slot, nm))


def g_body(n: int) -> UOp:
    c0 = UOp.const(0, dtypes.int32)
    cn = UOp.const(n, dtypes.int32)
    st = UOp(Ops.STORE, src=(c0, cn))
    return UOp(Ops.SINK, src=(st,))


def fx1() -> dict:
    a = g_buf(0, "a")
    b = g_buf(1, "b")
    d1 = g_body(1)
    d2 = g_body(2)
    vb = UOp(Ops.PARAM, src=(UOp(Ops.STACK),), arg=g_pv("v", 3))
    vu = UOp(Ops.PARAM, src=(UOp(Ops.STACK),), arg=g_pv("v", None))
    k1 = UOp(Ops.CALL, src=(d1, a))
    k2 = UOp(Ops.CALL, src=(d2, b, vb))
    e2 = UOp(Ops.END, src=(k2,))
    f1 = UOp(Ops.AFTER, src=(a, k1))
    f2 = UOp(Ops.AFTER, src=(f1, e2))
    sa = UOp(Ops.SINK, src=(a,))
    top = UOp(Ops.SINK, src=(f2, sa))
    bad = UOp(Ops.AFTER, src=(a, k1, top))
    return dict(a=a, b=b, vb=vb, vu=vu, k1=k1, k2=k2, e2=e2, af1=f1, af2=f2, top=top, bad=bad)


def fx2() -> dict:
    a = g_buf(0, "a2")
    x = g_buf(1, "x2")
    d1, d2, d3 = g_body(1), g_body(2), g_body(3)
    ka = UOp(Ops.CALL, src=(d1, a))
    kb = UOp(Ops.CALL, src=(d2, a))
    kc = UOp(Ops.CALL, src=(d3, x))
    fa = UOp(Ops.AFTER, src=(a, ka))
    fb = UOp(Ops.AFTER, src=(fa, kb))
    fc = UOp(Ops.AFTER, src=(x, kc))
    sa = UOp(Ops.SINK, src=(a,))
    top = UOp(Ops.SINK, src=(fb, fc, sa))
    return dict(a=a, x=x, ka=ka, kb=kb, kc=kc, afa=fa, afb=fb, afc=fc, top=top)


def fx3() -> dict:
    a = g_buf(0, "a3")
    d3 = g_body(3)
    k3 = UOp(Ops.CALL, src=(d3, a))
    g1 = UOp(Ops.AFTER, src=(a, k3))
    g2 = UOp(Ops.AFTER, src=(g1, k3))
    sa = UOp(Ops.SINK, src=(a,))
    top = UOp(Ops.SINK, src=(g2, sa))
    ag3 = UOp(Ops.AFTER, src=(g2, g1))
    return dict(a=a, k3=k3, ag1=g1, ag2=g2, top=top, ag3=ag3)


def fx5() -> dict:
    a = g_buf(0, "a5")
    d1, d2 = g_body(1), g_body(2)
    ka = UOp(Ops.CALL, src=(d1, a))
    fa = UOp(Ops.AFTER, src=(a, ka))
    kb = UOp(Ops.CALL, src=(d2, a, fa))
    fb = UOp(Ops.AFTER, src=(fa, kb))
    sa = UOp(Ops.SINK, src=(a,))
    top = UOp(Ops.SINK, src=(fb, sa))
    return dict(a=a, ka=ka, kb=kb, afa=fa, afb=fb, top=top)


# --------------------------------------------------------------------------
# UPSTREAM'S OWN FUNCTIONS, verbatim from tinygrad/schedule/__init__.py.
# --------------------------------------------------------------------------
def _unwrap_src(s: UOp) -> UOp:
    while len(s.src) and s.op not in {Ops.AFTER, Ops.BUFFER, Ops.ALLOC, Ops.PARAM, Ops.MSELECT, Ops.MSTACK}:
        s = s.src[0]
    return s


def _states(s: UOp) -> list[UOp]:
    s = _unwrap_src(s)
    if s.op in {Ops.MSELECT, Ops.MSTACK}: return [st for ss in s.src for st in _states(ss)]
    assert s.op in {Ops.AFTER, Ops.BUFFER, Ops.ALLOC, Ops.PARAM}, f"input to kernel must resolve to a buffer state, not {s.op}"
    return [s]


def _split_after(after: UOp) -> tuple[tuple[UOp, ...], tuple[UOp, ...]]:
    kernels, remaining = [s for s in after.src[1:] if s.op in {Ops.CALL, Ops.END}], [s for s in after.src[1:] if s.op not in {Ops.CALL, Ops.END}]
    deps, remaining = [s for s in remaining if s.op is Ops.AFTER], [s for s in remaining if s.op is not Ops.AFTER]
    if invalid := [s for s in remaining if s.op is not Ops.STORE]:
        raise AssertionError(f"AFTER source should be CALL, END, STORE, or AFTER, not {invalid[0].op}")
    return tuple(kernels), tuple(deps)


def _split_after_port(after: UOp) -> tuple[list[UOp], list[UOp]]:
    """THE PORT'S `_split_after`: the invalid src is DROPPED where Python RAISES."""
    kernels = [s for s in after.src[1:] if s.op in {Ops.CALL, Ops.END}]
    rest = [s for s in after.src[1:] if s.op not in {Ops.CALL, Ops.END}]
    deps = [s for s in rest if s.op is Ops.AFTER]
    return kernels, deps




# --------------------------------------------------------------------------
# THE EDGE FIXTURES.  EMPTY, SINGLE, MANY, COLLAPSE, and the two WITNESSES.
# --------------------------------------------------------------------------
def fx0() -> dict:
    """EMPTY: a sink with no AFTERs at all.  CPython answers a LINEAR with no srcs."""
    top = UOp(Ops.SINK, src=())
    return dict(top=top)


def fx7() -> dict:
    """THE `src_without_body` WITNESS: an AFTER that lives ONLY inside a CALL's body.

    CPython's toposort does NOT descend into a CALL's src[0], so the inner AFTER
    is never seen and the inner kernel is NEVER SCHEDULED.  A port that walks
    all srcs schedules it -- an EXTRA kernel, which is a REORDER.

    MIRRORS the port's `fx7` ONE FOR ONE: same construction order, same ops,
    same srcs.  `top = SINK(f1, k2, sa)`, `k2 = CALL(body2, a2)`,
    `body2 = SINK(g)`, `g = AFTER(a2, k3)`, `k3 = CALL(d3, a2)`.
    """
    a = g_buf(0, "a7")
    a2 = g_buf(1, "a7b")
    d1 = g_body(1)
    d3 = g_body(3)
    k1 = UOp(Ops.CALL, src=(d1, a))
    f1 = UOp(Ops.AFTER, src=(a, k1))
    k3 = UOp(Ops.CALL, src=(d3, a2))
    g = UOp(Ops.AFTER, src=(a2, k3))
    body2 = UOp(Ops.SINK, src=(g,))
    k2 = UOp(Ops.CALL, src=(body2, a2))
    sa = UOp(Ops.SINK, src=(a,))
    top = UOp(Ops.SINK, src=(f1, k2, sa))
    return dict(a=a, a2=a2, k1=k1, k2=k2, k3=k3, g=g, body2=body2, f1=f1, top=top)


def fx8() -> dict:
    """THE `gate_kernel_sink` WITNESS: a SINK whose arg is a KernelInfo.

    CPython's gate REJECTS it, so the subtree under it is never visited and the
    kernel under it is never scheduled.  A port whose gate says True for every
    SINK schedules it -- again an EXTRA kernel, again a REORDER.

    MIRRORS the port's `fx8`: `top = SINK(kin, sa)`, `kin = SINK(f1)` with a
    KernelInfo arg, `f1 = AFTER(a, k1)`, `k1 = CALL(d1, a)`.
    """
    a = g_buf(0, "a8")
    d1 = g_body(1)
    k1 = UOp(Ops.CALL, src=(d1, a))
    f1 = UOp(Ops.AFTER, src=(a, k1))
    kin = UOp(Ops.SINK, src=(f1,), arg=KernelInfo())
    sa = UOp(Ops.SINK, src=(a,))
    top = UOp(Ops.SINK, src=(kin, sa))
    return dict(a=a, k1=k1, kin=kin, f1=f1, sa=sa, top=top)


# --------------------------------------------------------------------------
# THE ROWS.
# --------------------------------------------------------------------------
def marks(lin: UOp) -> int:
    out = 0
    for k in lin.src:
        out = out * 10 + k.src[0].src[0].src[1].val
    return out


def nsrcs(lin: UOp) -> int:
    out = 0
    for k in lin.src:
        out = out * 10 + len(k.src)
    return out


from tinygrad.uop.ops import gate_kernel_sink


def topo_kernels(top: UOp) -> list[UOp]:
    """CPython's OWN toposort order, with the gate upstream's `create_schedule` uses."""
    out = []
    for u in top.toposort(gate_kernel_sink):
        if u.op is Ops.CALL: out.append(u)
        elif u.op is Ops.END: out.append(u.src[0])
    return out


def topo_nodes(top: UOp) -> int:
    """CPython's toposort SIZE, in the PORT's shape.

    CPython's `UOp.const(x, dtypes.int32)` is TWO nodes -- a CAST over a CONST
    -- and the port's is ONE (ops.bend:2990-2996 says so: "a CONST of int32 is
    one node here and two there").  So the CASTs are dropped from the count and
    the two sides become comparable.
    """
    return len([u for u in top.toposort(gate_kernel_sink) if u.op is not Ops.CAST])


def topo_marks(top: UOp) -> int:
    out = 0
    for k in topo_kernels(top):
        # a kernel whose body is not a body (fx7's k2) has NO readable mark, and
        # CPython's `UOp.val` ASSERTS on it -- so the row is not producible here.
        m = k.src[0].src[0].src[1]
        if m.op not in (Ops.CONST, Ops.CAST): continue
        out = out * 10 + m.val
    return out


def ops_of(lin: UOp) -> int:
    out = 0
    for k in lin.src:
        for s in k.src:
            out = out * 10 + code(s)
    return out


def rows() -> list[tuple[str, int]]:
    r: list[tuple[str, int]] = []
    f1, f2_, f3, f5 = fx1(), fx2(), fx3(), fx5()

    r += [("unwrap_A1", code(_unwrap_src(f1["a"])))]
    r += [("unwrap_B1", code(_unwrap_src(f1["b"])))]
    r += [("unwrap_Vb", code(_unwrap_src(f1["vb"])))]
    r += [("unwrap_AF1", code(_unwrap_src(f1["af1"])))]
    r += [("unwrap_AF2", code(_unwrap_src(f1["af2"])))]
    r += [("unwrap_bad", code(_unwrap_src(f1["bad"])))]

    r += [("split_A1_ks", len(_split_after_port(f1["a"])[0]))]
    r += [("split_AF1_ks", len(_split_after_port(f1["af1"])[0]))]
    r += [("split_AF2_ks", len(_split_after_port(f1["af2"])[0]))]
    r += [("split_AG1_ks", len(_split_after_port(f3["ag1"])[0]))]
    r += [("split_AG2_ks", len(_split_after_port(f3["ag2"])[0]))]
    r += [("split_AF2_ds", len(_split_after_port(f1["af2"])[1]))]
    r += [("split_bad_ks", len(_split_after_port(f1["bad"])[0]))]
    r += [("split_AG3_ks", len(_split_after_port(f3["ag3"])[0]))]
    r += [("split_AG3_ds", len(_split_after_port(f3["ag3"])[1]))]

    r += [("states_A1", len(_states(f1["a"])))]
    r += [("states_AF2", len(_states(f1["af2"])))]
    r += [("states_AG2", len(_states(f3["ag2"])))]

    r += [("bufuop_A1", code(_unwrap_src(f1["a"]).buf_uop))]
    r += [("bufuop_AF1", code(_unwrap_src(f1["af1"]).buf_uop))]
    r += [("bufuop_AF2", code(_unwrap_src(f1["af2"]).buf_uop))]
    r += [("bufuop_Vb", code(_unwrap_src(f1["vb"]).buf_uop))]
    r += [("bufuop_AG1", code(_unwrap_src(f3["ag1"]).buf_uop))]
    r += [("bufuop_AG2", code(_unwrap_src(f3["ag2"]).buf_uop))]

    r += [("bv_Vb", int(f1["vb"].is_bound_var))]
    r += [("bv_Vu", int(f1["vu"].is_bound_var))]
    r += [("bv_A1", int(f1["a"].is_bound_var))]
    r += [("bv_K2src2", int(f1["k2"].src[2].is_bound_var))]

    r += [("bs_K2_K1", int(f1["k1"] in f1["k2"].backward_slice))]
    r += [("bs_E2_K2", int(f1["k2"] in f1["e2"].backward_slice))]
    r += [("bs_K1_K2", int(f1["k2"] in f1["k1"].backward_slice))]
    r += [("bs_Kb_Ka", int(f2_["ka"] in f2_["kb"].backward_slice))]
    r += [("bs_Ka_Kb", int(f5["ka"] in f5["kb"].backward_slice))]

    for nm, f in (("fx1", f1), ("fx2", f2_), ("fx3", f3), ("fx5", f5)):
        lin = create_schedule(f["top"])
        r += [(f"{nm}_lin_n", len(lin.src))]
        r += [(f"{nm}_lin_op", code(lin))]
        r += [(f"{nm}_marks", marks(lin))]
        r += [(f"{nm}_nsrcs", nsrcs(lin))]
        r += [(f"{nm}_ops", ops_of(lin))]
        r += [(f"{nm}_topo_marks", topo_marks(f["top"]))]
        r += [(f"{nm}_topo", topo_nodes(f["top"]))]
    # THE EDGES.
    f0 = fx0()
    lin0 = create_schedule(f0["top"])
    # THE TOPOSORT's NODE COUNT IS NAMED `fxN_topo`, AND THIS ROW IS THE PROOF: this
    # oracle ALREADY called fx0's `topo_nodes` `fx0_topo` while it called the other
    # fixtures' `fxN_topo_nodes` -- so the oracle was INTERNALLY INCONSISTENT about its own
    # row names and the port was consistent. MEASURED 2026-10-22: the two sides agreed on
    # every VALUE and disagreed on six NAMES, which is a comparison that cannot report
    # agreement. The gate compares whole `name=value` LINES, so the two sides must share a
    # key -- and this file's own fx0 row says which key.
    r += [("fx0_topo", topo_nodes(f0["top"]))]
    r += [("fx0_lin_n", len(lin0.src))]
    r += [("fx0_lin_op", code(lin0))]
    r += [("fx0_marks", marks(lin0))]
    r += [("fx0_nsrcs", nsrcs(lin0))]
    r += [("fx0_ops", ops_of(lin0))]
    for nm, f in (("fx7", fx7()), ("fx8", fx8())):
        lin = create_schedule(f["top"])
        r += [(f"{nm}_lin_n", len(lin.src))]
        r += [(f"{nm}_lin_op", code(lin))]
        r += [(f"{nm}_marks", marks(lin))]
        r += [(f"{nm}_nsrcs", nsrcs(lin))]
        r += [(f"{nm}_ops", ops_of(lin))]
        r += [(f"{nm}_topo_marks", topo_marks(f["top"]))]
        r += [(f"{nm}_topo", topo_nodes(f["top"]))]
    return r


def main():
    want = sys.argv[1:]
    for nm, v in rows():
        if not want or nm in want:
            print(f"{nm}={v}")


if __name__ == "__main__":
    main()
