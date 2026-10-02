#!/usr/bin/env python3
"""The CPython row driver for tinybendygrad/renderer/wgsl.bend.

Prints the SAME lines the Bend gate prints, in the same order, so

    T=$(mktemp -d)
    ./bin/bend tinybendygrad/renderer/wgsl.bend | grep -v '^$' > $T/bd.txt
    PYTHONPATH=. python3 .agents/slop/wgsl-rows.py > $T/py.txt
    diff $T/bd.txt $T/py.txt

is empty iff every claim holds. Each line is `nm = [<value>]   py=[<value>]`,
so the `py=` half is the expectation AND the diff. A row is a STRING: no row is a
boolean about a string, because `String.concat` hides a dropped literal and a
boolean about the result would go green with the semicolon missing.

TWO KINDS OF ROW.

  PURE ROWS call the renderer method directly. `render_cast` takes a UOp in
  wgsl.py:95, so its fixture is `UOp(Ops.CAST, (UOp.const(0),), dt)` -- a real
  UOp, not a dtype, because the row must exercise the method CPython has.

  MODULE ROWS call `render_kernel` on real inputs and escape the newlines, so
  one module is one diffable line. The `alu` body's twelve lines are the ones
  `to_program` produced for `Tensor([1,2,3,4]) + Tensor([5,6,7,8])` on this
  `tinygrad/`, measured off a Spy that recorded `render_kernel`'s arguments.
  The `mixed` case is the one no single real kernel gives: a packed GLOBAL uchar,
  a workgroup line to hoist, a LOCAL f32, two local axes and a half uop, so
  every branch of the method fires at once.
"""
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))

from tinygrad import dtypes  # noqa: E402
from tinygrad.dtype import AddrSpace  # noqa: E402
from tinygrad.helpers import Target  # noqa: E402
from tinygrad.uop.ops import Ops, ParamArg, UOp  # noqa: E402
from tinygrad.renderer import wgsl as W  # noqa: E402

from tinygrad.renderer.wgsl import WGSLRenderer  # noqa: E402

R = WGSLRenderer(Target(device="", renderer="wgpu", arch=""))
R16 = WGSLRenderer(Target(device="", renderer="wgpu", arch="shader-f16"))


def dt_of(n):
    return getattr(dtypes, n)


def r(nm, got):
    print("%s = [%s]   py=[%s]" % (nm, got, got))


def rm(nm, got):
    """A MODULE row. No `py=` half: the expectation is the driver's own call to
    the real `render_kernel`, and a 700-character escaped module pasted into the
    Bend file would be a second copy of the truth that has to be re-escaped by
    hand every time the renderer changes."""
    print("%s = [%s]" % (nm, got))


def esc(s):
    """One line, newlines spelled. A dropped separator must be visible."""
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def buf(dt, addr, size, name):
    """A PARAM UOp paired with its writability -- the shape `bufs` has."""
    return name, (UOp(Ops.PARAM, (), ParamArg(0, dt, size, device="CPU", addrspace=addr)), True)


def work_buf(dt, size):
    """A LOCAL BUFFER, which is what wgsl.py:74's BUFFER rule renders."""
    return UOp(Ops.BUFFER, (UOp.range(size, 0),), ParamArg(0, dt, size, device="CPU",
                                                          addrspace=AddrSpace.LOCAL))


# ---------------------------------------------------------------- pure rows
def rows_pure():
    for n in ["float", "uchar", "ushort", "short", "char", "int32", "uint32", "bool", "half"]:
        r("type_map " + n, R.type_map.get(dt_of(n), ""))
    r("type_map double", R.type_map.get(dtypes.f64, ""))

    for n in ["uchar", "ushort", "char", "short", "int32", "uint32", "float", "half"]:
        r("render_cast " + n, R.render_cast(UOp(Ops.CAST, (UOp.const(0),), dt_of(n)), "V"))

    r("barrier", R.barrier)
    r("nan", R.nan)
    r("supports_float4", str(R.supports_float4))
    r("global_max", ",".join(str(x) for x in R.global_max))
    r("local_max", ",".join(str(x) for x in R.local_max))

    for n in ["uchar", "char", "ushort", "short", "half", "int32"]:
        dt = dt_of(n)
        w = 8 * dt.itemsize
        r("pf_elems " + n, str(4 // dt.itemsize))
        r("pf_width " + n, str(w))
        r("pf_mask " + n, str((1 << w) - 1))

    for mask, shift in [(255, 0), (255, 8), (255, 16), (255, 24), (65535, 0), (65535, 16)]:
        r("wmask %d_%d" % (mask, shift), str(((mask << shift) ^ 0xFFFFFFFF)))

    for n in ["float", "half", "bfloat16", "double"]:
        dt = dt_of(n)
        bs, (e, m) = dt.bitsize, dtypes.finfo(dt)
        r("nan_bs " + n, str(bs))
        r("nan_e " + n, str(e))
        r("nan_m " + n, str(m))
        # THE U32 LIMIT, and the two rows the two lanes DISAGREE on. A U32 holds
        # 2^32-1, so double's 2^63-1 mask and its 2047<<52 threshold have no
        # image; the Bend lane answers 4294967295 and 0. Unreachable from a
        # WGSLRenderer (no double in `type_map`, none in `supported_dtypes`), and
        # printed rather than hidden.
        r("nan_mask " + n, str((1 << (bs - 1)) - 1))
        r("nan_thr " + n, str(((1 << e) - 1) << m))

    for n in ["float", "half", "double"]:
        r("nan_uint " + n, getattr(dtypes, "uint%d" % dt_of(n).bitsize).name)

    for op in ["SQRT", "RECIPROCAL", "NEG", "EXP2", "LOG2", "SIN", "TRUNC", "AND", "XOR", "OR",
               "ADD", "SUB", "MUL", "CMOD", "CDIV", "CMPNE", "SHR", "SHL", "CMPLT", "CMPEQ", "WHERE"]:
        f = R.code_for_op[getattr(Ops, op)]
        r("code_for_op " + op, f("A", "B", "C", dtypes.f32) if op == "WHERE" else (
            f("A", dtypes.f32) if op in ("SQRT", "RECIPROCAL", "NEG", "EXP2", "LOG2", "SIN", "TRUNC")
            else f("A", "B", dtypes.f32)))

    for k in ["g", "l"]:
        for x in range(3):
            r("workitem %s%d" % (k, x), R.code_for_workitem[k](x))
    r("workitem l3", "")

    for arch, rr in [("", R), ("shader-f16", R16)]:
        r("supported_dtypes " + arch, ",".join(sorted(d.name for d in rr.supported_dtypes())))

    r("render_dtype float", R.render_dtype(dtypes.f32, True))
    r("_render_dtype uchar global", R._render_dtype(dtypes.u8, 1, addrspace=AddrSpace.GLOBAL,
                                                    mutable=True, override_ptr=True))


    # is_packed / buf_map / packed_size, over every dtype and addrspace. These
    # rows exist because the gate caught `is_packed`'s third clause INVERTED with
    # every other row green: a predicate no row calls is a predicate no mutation
    # finds, and this one decides whether a buffer is `atomic<u32>` at all.
    for n in ["uchar", "char", "ushort", "short", "bool", "half", "float", "int32"]:
        for a in ["GLOBAL", "LOCAL", "REG"]:
            u = UOp(Ops.PARAM, (), ParamArg(0, dt_of(n), 16, device="CPU", addrspace=getattr(AddrSpace, a)))
            r("is_packed %s %s" % (n, a), str(W.is_packed(u)))
            r("buf_map %s %s" % (n, a), R.buf_map(u))
    for n, sz in [("uchar", 16), ("uchar", 17), ("ushort", 16), ("ushort", 17), ("half", 16),
                  ("half", 17), ("float", 16), ("int32", 16)]:
        u = UOp(Ops.PARAM, (), ParamArg(0, dt_of(n), sz, device="CPU", addrspace=AddrSpace.GLOBAL))
        r("packed_size %s %d" % (n, sz), str(W._packed_size(u)))
    u = UOp(Ops.PARAM, (), ParamArg(0, dtypes.u8, 16, device="CPU", addrspace=AddrSpace.REG))
    r("packed_size uchar 16 REG", str(W._packed_size(u)))


# ------------------------------------------------------------- module rows
KERN_ALU = ["  var val0 = data1_4[0];", "  var val1 = data1_4[1];", "  var val2 = data1_4[2];",
            "  var val3 = data1_4[3];", "  var val4 = data2_4[0];", "  var val5 = data2_4[1];",
            "  var val6 = data2_4[2];", "  var val7 = data2_4[3];", "  data0_4[0] = (val0+val4);",
            "  data0_4[1] = (val1+val5);", "  data0_4[2] = (val2+val6);", "  data0_4[3] = (val3+val7);"]


def decl(nm, i, u):
    space = "storage,read_write" if u.addrspace == AddrSpace.GLOBAL else "uniform"
    ty = ("array<%s>" % R.buf_map(u)) if u.addrspace == AddrSpace.GLOBAL else R.buf_map(u)
    return "@group(0) @binding(%d)var<%s>%s:%s;" % (i + 1, space, nm, ty)


def rows_kernel():

    # R2's uops, named here because `rk_sz` and `rk_half` are rows of their own.
    uops2 = [UOp.special(UOp.const(8).cast(dtypes.i32), "l0"),
             UOp.special(UOp.const(2).cast(dtypes.i32), "l1"),
             UOp(Ops.CAST, (UOp.const(0),), dtypes.f16)]
    r("rk_sz none", "1")
    r("rk_sz mixed", ",".join(str(u.src[0].ssimplify()) for u in
                              sorted([u for u in uops2 if u.op is Ops.SPECIAL and u.arg[0] == "l"],
                                     key=lambda u: u.arg)))
    r("rk_half mixed", str(any(u.dtype == dtypes.f16 for u in uops2)))
    r("rk_half none", str(any(u.dtype == dtypes.f16 for u in [])))

    # THE TWO FOLDS, as rows. `;` cannot appear in a WGSL binding declaration, so
    # the row is one line, and these two rows are the only reason the Bend file's
    # other folds are written the way they are: `String.join` is head-first, so a
    # fold whose result reaches it must APPEND and a fold whose result is WALKED
    # must PREPEND. Getting it backwards emits a shader with its bindings and its
    # body in reverse order, and that typechecks.
    r("rk_bindings", ";".join(decl(n, i, u) for i, (n, (u, _)) in enumerate(
        [buf(dtypes.f32, AddrSpace.GLOBAL, 4, x) for x in ["data0_4", "data1_4", "data2_4"]])))
    r("rk_body", ";".join(KERN_ALU))

    # R1: the real float32 add. Three GLOBAL f32 PARAMs, no local axis, no half:
    # the prologue, the storage layout and the `[1]` fallback of an empty
    # local_size.
    b = [buf(dtypes.f32, AddrSpace.GLOBAL, 4, n) for n in ["data0_4", "data1_4", "data2_4"]]
    rm("rk alu", esc(R.render_kernel("E_4", KERN_ALU, b, [], prefix=None)))

    # R2: every branch at once. A packed GLOBAL uchar for `array<atomic<u32>>`, a
    # workgroup line to hoist out of the body, a LOCAL f32 for `var<uniform>`, TWO
    # local axes so the `,` join is not a one-element list, and a half uop for
    # `enable f16;`. The workgroup line is wgsl.py:74's OWN rule spelled from the
    # three functions this file ports, so the row cross-checks `is_packed`,
    # `_packed_size` and `buf_map` as well as `render_kernel`.
    wbu = work_buf(dtypes.u8, 16)
    kern2 = ["  var val0 = atomicLoad(&data0_16[0]);",
             "  var<workgroup> buf0:array<%s,%d>;" % (R.buf_map(wbu), W._packed_size(wbu)),
             "  data0_16[0] = (val0+1);"]
    b2 = [buf(dtypes.u8, AddrSpace.GLOBAL, 16, "data0_16"), buf(dtypes.f32, AddrSpace.LOCAL, 1, "t0")]
    uops2 = [UOp.special(UOp.const(8).cast(dtypes.i32), "l0"),
             UOp.special(UOp.const(2).cast(dtypes.i32), "l1"),
             UOp(Ops.CAST, (UOp.const(0),), dtypes.f16)]
    rm("rk mixed", esc(R.render_kernel("K_mixed", kern2, b2, uops2, prefix=None)))

    # R3: the two short-circuits -- `"\\n".join([])` and `range(0)`.
    rm("rk empty", esc(R.render_kernel("K_empty", [], [], [], prefix=None)))


if __name__ == "__main__":
    which = sys.argv[1] if len(sys.argv) > 1 else "all"
    if which in ("all", "pure"):
        rows_pure()
    if which in ("all", "kernel"):
        rows_kernel()
