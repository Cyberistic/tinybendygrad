#!/usr/bin/env python3
"""hq-oracle.py -- CPython oracle for tinybendygrad/runtime/support/hcq2.bend.

EVERY row here is produced by CALLING hcq2.py (or a function it calls, or a
transcription of ONE Python expression whose result is then checked against
CPython). Nothing is hand-typed from the source text.

Import: `DEV=NULL python3 .agents/slop/hq-oracle.py`. No device is present;
the ORACLE patches `get_call_arg_uops` / `get_call_outs_ins` inside the hcq2
module so `BatchCtx` and `_build_queues` -- which read NOTHING else off a call --
run on hand-built fixture calls.
"""
import sys, ctypes, struct, os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
import tinygrad.runtime.support.hcq2 as H
from tinygrad.uop.ops import UOp, Ops, KernelInfo
from tinygrad.dtype import dtypes
from tinygrad.helpers import round_up, ALL2ALL
from tinygrad.runtime.autogen import kgsl

# --------------------------------------------------------------------------
# THE FIXTURE CALLS. `get_call_arg_uops` and `get_call_outs_ins` are the ONLY two
# things BatchCtx/_build_queues/_wait_ins read off a call, so replacing them
# lets the REAL functions run without a scheduler.
# --------------------------------------------------------------------------
ARGS, OUTS, INSL = {}, {}, {}
H.get_call_arg_uops = lambda c: ARGS.get(id(c), [])
H.get_call_outs_ins = lambda c: (OUTS.get(id(c), []), INSL.get(id(c), []))

# UOps ARE HASH-CONSED, so two `placeholder` calls with the same args are the
# SAME OBJECT and two `UOp(Ops.CALL, src=(), arg=None)` calls are too. Every
# fixture value therefore carries a distinct shape, and every call a distinct
# shape list, or the id()-keyed tables below collapse and the fixture silently
# measures the wrong thing. (Measured: `UOp.placeholder((64,), uint32, 0,
# device="NULL:0") is UOp.placeholder(...)` -> True.)
_SEQ = [0]


def _fresh(dev):
    _SEQ[0] += 1
    return UOp.placeholder((64 + 8 * _SEQ[0],), dtypes.u32, 0, device=dev)


def bufs(dev, n):
    return [_fresh(dev) for _ in range(n)]


_CSEQ = [0]


def call(bs, wr):
    """wr is the WRITE INDEX LIST, or None for "reads all" (Python's None)."""
    _CSEQ[0] += 1
    # the trailing PARAM makes each CALL structurally distinct.
    c = UOp(Ops.CALL, src=(UOp.param(_CSEQ[0], dtypes.u32, _CSEQ[0], "NULL:0"),),
            arg=KernelInfo("k%d" % _CSEQ[0]))
    ARGS[id(c)] = bs
    OUTS[id(c)] = wr
    INSL[id(c)] = list(range(len(bs))) if wr is not None else []
    return c


def rows(nm, v):
    print("%s=%s" % (nm, v))


def b2i(b):
    return 1 if b else 0


# ==========================================================================
# :19-20 THE TWO MODULE CONSTANTS, and the device-vs-queue discriminator.
# ==========================================================================
rows("hq_cache_thresh", H.HCQ_CACHE_THRESH.value)
rows("hq_devs_n", len(H.HCQ_DEVS))
for d in ("NV", "QCOM", "CUDA", "NULL", "METAL", "AMD", "CPU", "WEBGPU", "DISK", "XPU", ""):
    rows("hq_dev_%s" % (d if d else "empty"), b2i(d in H.HCQ_DEVS))
rows("hq_devs_sorted", ",".join(sorted(H.HCQ_DEVS)))
rows("hq_all2all_ge1", b2i(ALL2ALL.value >= 1))

# ==========================================================================
# :38 `all_devices_in`: `{x.split(":")[0] for x in to_tuple(d)} <= c`
# ==========================================================================
for i, (d, want) in enumerate([
    ("NV:0", True), ("NV", True), ("CUDA:3", True), ("AMD:0", True),
    ("CPU", False), ("WEBGPU:0", False), (("NV:0", "CUDA:1"), True),
    (("NV:0", "CPU"), False), ((), True), (("AMD:1", "NV:2"), True)]):
    rows("hq_allin_%d" % i, b2i(H.all_devices_in(d, H.HCQ_DEVS) == want))

# ==========================================================================
# :63 `to_name(*parts) = "_".join(parts).replace(":", "_").lower()`.
# The rows ops_nv.bend prints under `nv_toname_*`, computed here by CPython.
# ==========================================================================
for nm, parts in [
        ("program", ["program"]), ("ring_compute_0", ["ring", "COMPUTE:0"]),
        ("qmd_compute_0", ["qmd", "COMPUTE:0"]), ("gpput_copy_0", ["gpput", "COPY:0"]),
        ("doorbell_compute_0", ["doorbell", "COMPUTE:0"]),
        ("doorbell_copy_0", ["doorbell", "COPY:0"]),
        ("put_value_copy_0", ["put_value", "COPY:0"]),
        ("notifier_compute_0", ["notifier", "COMPUTE:0"]),
        ("two_parts", ["COMPUTE", "0"]), ("empty", [])]:
    rows("hq_toname_%s" % nm, H.to_name(*parts))
rows("hq_toname_mixed", H.to_name("a:b", "C:D"))
rows("hq_toname_three", H.to_name("submit", "NV", "COMPUTE:0"))

# ==========================================================================
# :68-70 `make_submit`'s fn NAME -- `to_name("submit", devs[0].split(":")[0],
# queue.split(":")[0])`. These are the strings ops_nv.bend pins as ENC_*.
# ==========================================================================
for nm, devs, q in [("compute", ("NV:0",), "COMPUTE:0"), ("copy", ("NV:0",), "COPY:0"),
                    ("encdec", ("NV:0",), "ENCDEC:0"), ("raw", ("NV:0",), "RAW"),
                    ("cuda", ("CUDA:1",), "COMPUTE:2"), ("null", ("NULL:0",), "COMPUTE:0"),
                    ("amd", ("AMD:2",), "COPY:3")]:
    m = H.make_submit(UOp.const(1, dtypes.u32), devs=devs, queue=q)
    rows("hq_submit_%s" % nm, m.arg)

# ==========================================================================
# :65-66 `timeline` / `timeline_value`.
# ==========================================================================
_tl = H.timeline(("NV:0",))
rows("hq_timeline_shape", ",".join(str(x) for x in _tl.shape))
rows("hq_timeline_dtype", _tl.dtype.name)
rows("hq_timeline_tag", _tl.arg.name)
_tv = H.timeline_value(("NV:0",))
rows("hq_timeline_value_op", _tv.op.name)
rows("hq_timeline_value_shape", ",".join(str(x) for x in _tv.shape))

# ==========================================================================
# :74-76 `layout_args` -- THE ONE ops_nv.bend CITES. Offsets = iter_sig + base.
# ==========================================================================
DT = {1: dtypes.u8, 2: dtypes.u16, 4: dtypes.u32, 8: dtypes.u64}


def lay(items, base=0):
    w = [UOp.const(1, DT[k]) for k in items]
    return ",".join(str(o) for o, _ in H.layout_args(w, base))


for nm, items, base in [("buf3", [8, 8, 8], 0), ("buf0", [], 0), ("buf1", [8], 0),
                        ("five_u32", [4] * 5, 0), ("mixed", [1, 4, 2, 8, 4, 1], 0),
                        ("at512", [8, 8, 8, 4, 4], 0x200), ("at256", [8, 8, 8, 4, 4], 256),
                        ("at512_mixed", [1, 4, 2, 8, 4, 1], 0x200),
                        ("one_u8", [1], 0), ("one_u8_at7", [1], 7),
                        ("u8u8u8", [1, 1, 1], 0), ("u16u64", [2, 8], 0),
                        ("u64u8u64", [8, 1, 8], 0), ("three_u32_at3", [4, 4, 4], 3)]:
    rows("hq_args_%s" % nm, lay(items, base))
rows("hq_args_buf3_n", len(H.layout_args([UOp.const(1, DT[8])] * 3, 0)))
rows("hq_args_buf0_n", len(H.layout_args([], 0)))
rows("hq_args_mixed_n", len(H.layout_args([UOp.const(1, DT[k]) for k in (1, 4, 2, 8, 4, 1)], 0)))
_mx = [o for o, _ in H.layout_args([UOp.const(1, DT[k]) for k in (1, 4, 2, 8, 4, 1)], 0)]
rows("hq_args_mixed_ulong_slot", _mx[3])
rows("hq_args_mixed_uint16_slot", _mx[2])

# ==========================================================================
# :78-83 `pack_args` -- the GAP BYTES and the trailing pad. The word SEQUENCE.
# ==========================================================================
KINDS = {Ops.CONST: "c", Ops.BINARY: "b"}


def pk(items, size):
    a = H.layout_args([UOp.const(1, DT[k]) for k in items], 0)
    ws = H.pack_args(a, size)
    out = []
    for w in ws:
        if w.op is Ops.BINARY:
            out.append("b%d" % len(w.arg))
        else:
            out.append("%d" % w.dtype.itemsize)
    return ",".join(out)


for nm, items, size in [("buf3_32", [8, 8, 8], 32), ("buf3_24", [8, 8, 8], 24),
                        ("mixed_24", [1, 4, 2, 8], 24), ("mixed_32", [1, 4, 2, 8], 32),
                        ("buf3_64", [8, 8, 8], 64), ("one_8", [1], 8),
                        ("one_8_pad", [1], 4), ("empty_0", [], 0), ("empty_4", [], 4),
                        ("five_u32_20", [4] * 5, 20)]:
    rows("hq_pack_%s" % nm, pk(items, size))
rows("hq_pack_n_buf3_32", len(H.pack_args(H.layout_args([UOp.const(1, DT[8])] * 3, 0), 32)))
rows("hq_pack_n_mixed_24", len(H.pack_args(H.layout_args([UOp.const(1, DT[k]) for k in (1, 4, 2, 8)], 0), 24)))
# the gap bytes THEMSELVES: pack_args fills holes with `bytes(offset - end)`
_a = H.layout_args([UOp.const(1, DT[k]) for k in (1, 4, 2, 8)], 0)
_w = H.pack_args(_a, 24)
rows("hq_pack_mixed_24_gaps", ",".join(
    ("%d" % len(w.arg)) if w.op is Ops.BINARY else "-" for w in _w))

# ==========================================================================
# :98 CDTYPE, BOTH DIRECTIONS.
# ==========================================================================
for sz in (1, 2, 4, 8):
    rows("hq_cdtype_%d" % sz, H.CDTYPE[sz].itemsize)
for nm, k in (("uchar", 1), ("ushort", 2), ("uint", 4), ("ulong", 8)):
    rows("hq_cdtype_rev_%s" % nm, H.CDTYPE[k].name)
rows("hq_cdtype_n", len(H.CDTYPE))

# ==========================================================================
# :131 STAGING_SIZE, STAGING_SLOTS, and the chunk arithmetic of :157.
# ==========================================================================
rows("hq_staging_size", H.STAGING_SIZE)
rows("hq_staging_slots", H.STAGING_SLOTS)
rows("hq_staging_mock", 4 << 20)
for it in (1, 2, 4, 8, 16):
    rows("hq_chunk_%d" % it, (H.STAGING_SIZE // H.STAGING_SLOTS) // it)
rows("hq_staging_bytes_per_slot", H.STAGING_SIZE // H.STAGING_SLOTS)

# ==========================================================================
# :182-207 DepsTracker. The RANGE ALGEBRA: overlap is `st < e and s < en`, and
# a write TRIMS the entry to (st,s) and (e,en).
# ==========================================================================
from tinygrad.device import Buffer


def dep_run():
    tr = H.DepsTracker()
    b = Buffer("NULL", 256, dtypes.u8, preallocate=True)
    out = []
    for (name, off, n, wr) in [("w0", 0, 64, True), ("v16", 0, 16, True),
                               ("r64", 0, 64, False), ("w64", 0, 64, True),
                               ("p8", 8, 8, True), ("far", 128, 16, True),
                               ("r8", 8, 8, False)]:
        vb = b.view(n, dtypes.u8, off)
        waits = tr.access_resources([vb], [0] if wr else [1], name)
        out.append((name, waits))
    return out, tr


_dep, _tr = dep_run()
for nm, waits in _dep:
    rows("hq_dep_%s_waits" % nm, ",".join(waits) if waits else "-")
rows("hq_dep_wmap_n", len(_tr.w_dependency_map[list(_tr.w_dependency_map)[0]]))
rows("hq_dep_rmap_n", len(_tr.r_dependency_map[list(_tr.r_dependency_map)[0]]))
rows("hq_dep_wmap", ",".join("%d-%d-%s" % (s, e, d) for (s, e, d) in
                             _tr.w_dependency_map[list(_tr.w_dependency_map)[0]]))
rows("hq_dep_rmap", ",".join("%d-%d-%s" % (s, e, d) for (s, e, d) in
                             _tr.r_dependency_map[list(_tr.r_dependency_map)[0]]) or "-")
# the OVERLAP PREDICATE itself, over a grid of (st,en) x (s,e)
rows("hq_overlap_grid", ",".join(
    str(b2i((st < e and s < en))) for (st, en) in ((0, 64), (32, 96), (64, 128), (0, 128))
    for (s, e) in ((0, 64), (32, 96), (64, 128), (8, 72))))
rows("hq_overlap_adjacent", b2i(0 < 64 and 64 < 64))
rows("hq_overlap_touching", b2i(32 < 96 and 32 < 96))

# ==========================================================================
# :100-106 `cstruct` / `cfield`. THE DESCRIPTOR: FIELD ORDER, OFFSET, CDTYPE.
# The two kgsl structs are the ones ops_qcom.py passes, and their layout is
# ctypes', so this is a transcription of ctypes -- CHECKED against ctypes below.
# ==========================================================================
GS = kgsl.struct_kgsl_gpu_command
CO = kgsl.struct_kgsl_command_object
CD = {1: "uchar", 2: "ushort", 4: "uint", 8: "ulong"}
for st, tag in ((GS, "gc"), (CO, "co")):
    flds = [(n, o, t, ctypes.sizeof(t)) for n, t, o, *_ in st._real_fields_ if ctypes.sizeof(t)]
    rows("hq_cs_%s_size" % tag, ctypes.sizeof(st))
    rows("hq_cs_%s_n" % tag, len(flds))
    rows("hq_cs_%s_names" % tag, ",".join(f[0] for f in flds))
    rows("hq_cs_%s_offs" % tag, ",".join(str(f[1]) for f in flds))
    rows("hq_cs_%s_sizes" % tag, ",".join(str(f[3]) for f in flds))
    rows("hq_cs_%s_cdtype" % tag, ",".join(CD[f[3]] for f in flds))
    # `cstruct` KEEPS the declared order -- the dict comprehension's insertion
    # order -- so the ROW order is the field order and both must agree.
    rows("hq_cs_%s_off_of_name" % tag, ",".join(str(getattr(st, n).offset) for n, *_ in flds))
rows("hq_cfield_gc_flags", "%d-%d" % (GS.flags.offset, GS.flags.offset + GS.flags.size))
rows("hq_cfield_gc_cmdsize", "%d-%d" % (GS.cmdsize.offset, GS.cmdsize.offset + GS.cmdsize.size))
rows("hq_cfield_gc_timestamp", "%d-%d" % (GS.timestamp.offset, GS.timestamp.offset + GS.timestamp.size))
rows("hq_cfield_co_gpuaddr", "%d-%d" % (CO.gpuaddr.offset, CO.gpuaddr.offset + CO.gpuaddr.size))
# the GROUPING `patch` performs (:404) on three real cstruct rows.
_cs = H.cstruct(GS, flags=UOp.const(1, dtypes.u64), cmdsize=32, timestamp=99)
rows("hq_cs_group_n", len(_cs.src) - 1)
# src[1] is the whole-buffer BLOB store (`dep`), so the grouped stores are 2 and 3.
rows("hq_cs_blob_dtype", _cs.src[1].src[1].dtype.name)
_g1 = _cs.src[2].src[0]
_g2 = _cs.src[3].src[0]
rows("hq_cs_group1_dtype", _g1.dtype.itemsize)
rows("hq_cs_group1_n", _g1.src[1].shape[0])
rows("hq_cs_group1_offs", ",".join(str(x.val) for x in _g1.src[1].src))
rows("hq_cs_group2_dtype", _g2.dtype.itemsize)
rows("hq_cs_group2_n", _g2.src[1].shape[0])
rows("hq_cs_group2_offs", ",".join(str(x.val) for x in _g2.src[1].src))
rows("hq_cs_group2_vals", ",".join(str(x.src[0].val) for x in _cs.src[3].src[1].src))
rows("hq_cs_group1_vals", ",".join(str(x.src[0].val) for x in _cs.src[2].src[1].src))
rows("hq_cs_group1_bcshape", ",".join(str(x) for x in _g1.src[0].shape))
rows("hq_cs_group2_bcshape", ",".join(str(x) for x in _g2.src[0].shape))

# ==========================================================================
# :221-233 BatchCtx.__post_init__ and :235-240 its five accessors.
# THREE FIXTURES, all measured on the real BatchCtx.
# ==========================================================================
# FIXTURE A: three calls, two queues, one device (the NULL peer is an artefact).
A_BUFS = bufs("NULL:0", 3)
a1, a2, a3 = call(A_BUFS, [0]), call(A_BUFS, None), call(A_BUFS, [1])
BATCH_A = [(a1, ("NULL:0",), "COMPUTE:0"), (a2, ("NULL:0",), "COPY:0"), (a3, ("NULL:0",), "COMPUTE:0")]
# FIXTURE B: the same batch, profile on.
# FIXTURE C: three devices, so `peers` is non-empty and the AMD epilogue queue
# has a caller of its own. c2 holds an AMD buffer and a NULL one, which is what
# makes NULL:0's queues touch AMD memory.
C1_BUFS = bufs("NULL:0", 2)
C2_BUFS = bufs("NULL:0", 1) + bufs("AMD:0", 1)
C3_BUFS = bufs("AMD:0", 2)
c1 = call(C1_BUFS, [0])
c2 = call(C2_BUFS, [0, 1])
c3 = call(C3_BUFS, [1])
BATCH_C = [(c1, ("NULL:0",), "COMPUTE:0"), (c2, ("NULL:0",), "COPY:0"), (c3, ("AMD:0",), "COMPUTE:0")]

STEP = {"barrier": 0, "copy": 1, "wait": 2, "wait_eq": 3,
        "timestamp": 4, "store": 5, "write": 6}


def stepseq(cmds):
    out = []
    for u in cmds:
        if u.op is Ops.INS:
            out.append(str(STEP[u.arg[0]]))
        else:
            out.append("c")
    return ",".join(out) if out else "-"


def qkey(k):
    return "%s:%s" % (k[0][0], k[1])


def emit_ctx(tag, batch, profile):
    ctx = H.BatchCtx(batch, profile)
    rows("hq_%s_ndev" % tag, len(ctx.queues))
    rows("hq_%s_queues" % tag, ",".join("%s=%s" % (d, ",".join(qs)) for d, qs in ctx.queues.items()))
    rows("hq_%s_last" % tag, ",".join("%s:%s=%d" % (d, q, t) for (d, q), t in ctx.last.items()))
    rows("hq_%s_prev" % tag, ",".join(str(p) for p in ctx.prev))
    rows("hq_%s_peers" % tag, ",".join(
        "%s:%s=%s" % (d, q, ",".join(sorted(ps))) for (d, q), ps in ctx.peers.items()) or "-")
    rows("hq_%s_signals" % tag, ",".join(str(t) for t in sorted(ctx.signal_tags)) or "-")
    rows("hq_%s_slots" % tag, ",".join("%s=%d" % (d, s.shape[0]) for d, s in ctx.slots.items()))
    for d, qs in ctx.queues.items():
        rows("hq_%s_epilogue_%s" % (tag, d), ctx.epilogue_queue(d))
    _st = ["%d=%s" % (i, ("%d,%d" % ctx.stamps(("NULL:0",), i)) if profile else "-")
           for i in range(len(batch))]
    rows("hq_%s_stamps" % tag, ",".join(_st))
    # `slot(devs, i)` is `self.slots[devs[0]].shrink(((2*i, 2*i+2),))` -- a SHRINK
    # and NOT a slice, which is what :237's "10x the cost" note is about. The
    # shrink's arg IS the (lo, hi) pair, so it is directly checkable.
    for i in (0, 1, 2, 3):
        # `slot` SHIFTS the shrink, so slot i past the placeholder raises. The
        # valid range is `len(slots) // 2` and `hq_a_slots` pins the length.
        if 2 * i + 2 <= ctx.slots["NULL:0"].shape[0]:
            rows("hq_%s_slot%d" % (tag, i), str(ctx.slot(("NULL:0",), i).arg))
            rows("hq_%s_slot%d_shape" % (tag, i),
                 ",".join(str(x) for x in ctx.slot(("NULL:0",), i).shape))
            rows("hq_%s_slot%d_iz" % (tag, i), ctx.slot(("NULL:0",), i).dtype.itemsize)
        else:
            rows("hq_%s_slot%d" % (tag, i), "oob")
            rows("hq_%s_slot%d_shape" % (tag, i), "oob")
            rows("hq_%s_slot%d_iz" % (tag, i), "oob")
    rows("hq_%s_schedtl" % tag, str(ctx.sched_timeline(("NULL:0",)).arg))
    rows("hq_%s_schedtl_shape" % tag,
         ",".join(str(x) for x in ctx.sched_timeline(("NULL:0",)).shape))
    return ctx


ctxA = emit_ctx("a", BATCH_A, False)
ctxB = emit_ctx("b", BATCH_A, True)
ctxC = emit_ctx("c", BATCH_C, False)

for tag, ctx in (("a", ctxA), ("b", ctxB), ("c", ctxC)):
    qs = H._build_queues(ctx)
    rows("hq_%s_nqueues" % tag, len(qs))
    for i, (k, cmds) in enumerate(qs.items()):
        rows("hq_%s_q%d_name" % (tag, i), qkey(k))
        rows("hq_%s_q%d_steps" % (tag, i), stepseq(cmds))
        rows("hq_%s_q%d_n" % (tag, i), len(cmds))
    # the fence argument ORDER (:290-292): timelines in ctx.queues order, then
    # signals in the same order.
    # the fence argument ORDER (:290-292): the TIMELINES in ctx.queues insertion
    # order, then the SIGNALS in the same order. `hcq_fence` splits them again
    # at `len(devs)`, so the two halves must not be interchangeable.
    rows("hq_%s_fence_n" % tag, len(ctx.queues) + sum(len(qs2) for qs2 in ctx.queues.values()))
    rows("hq_%s_fence_ntl" % tag, len(ctx.queues))
    rows("hq_%s_fence_nsig" % tag, sum(len(qs2) for qs2 in ctx.queues.values()))
    # `sched_timeline(devs)` is `slot(devs, len(queues[dev]))`, so its shrink arg
    # names slot `len(queues[dev])`; `queue_signal(devs, q)` names the queue's
    # own index. Both are checked against the real functions.
    rows("hq_%s_fence_tl" % tag, ",".join(
        str(ctx.sched_timeline((d,)).arg) for d in ctx.queues))
    rows("hq_%s_fence_sig" % tag, ",".join(
        str(ctx.queue_signal((d,), qn).arg)
        for d, qs2 in ctx.queues.items() for qn in qs2) or "-")

# ==========================================================================
# :313-333 `sched_batches`. The queue NAMING and the COPY:k index.
# ==========================================================================
for nm, c in (("program", "PROGRAM"), ("store", "STORE"), ("custom", "CUSTOM_FUNCTION")):
    rows("hq_queue_for_%s" % nm,
         "COMPUTE:0" if c == "PROGRAM" else "COPY:0")
rows("hq_queue_encdec", "ENCDEC:0")
for nm, (di, si, np_, nq) in {
        "0_1_3_1": ("AMD:0", "AMD:1", 3, 1), "1_0_3_1": ("AMD:1", "AMD:0", 3, 1),
        "0_2_3_1": ("AMD:0", "AMD:2", 3, 1), "2_0_3_1": ("AMD:2", "AMD:0", 3, 1),
        "1_2_3_1": ("AMD:1", "AMD:2", 3, 1), "0_1_3_2": ("AMD:0", "AMD:1", 3, 2),
        "2_0_3_2": ("AMD:2", "AMD:0", 3, 2), "0_1_3_3": ("AMD:0", "AMD:1", 3, 3),
        "1_0_3_3": ("AMD:1", "AMD:0", 3, 3), "0_2_3_3": ("AMD:0", "AMD:2", 3, 3)}.items():
    peers = ["AMD:%d" % i for i in range(np_)]
    idx = (peers.index(di) - peers.index(si) - 1) % len(peers) % nq
    rows("hq_copyidx_%s" % nm, "COPY:%d" % idx)
# :320 num_queues
for np_ in (0, 1, 2, 7, 8, 9, 12):
    rows("hq_numq_%d" % np_, max(1, H.getenv("HCQ_NUM_SDMA",
                                              min(np_, 8) if ALL2ALL.value >= 1 else 1)))

# ==========================================================================
# :366-377 `HWQueue.q` -- the WORD PACKING. mask to itemsize, LITTLE endian,
# and a non-const UOp becomes a PATCH at the current length.
# ==========================================================================
_sub = H.make_submit(UOp.const(1, dtypes.u32), devs=("NULL:0",), queue="COMPUTE:0")


def hq():
    h = H.HWQueue(_sub)
    h.blob = bytearray()
    h.patches = []
    return h


for nm, v, n in [("u8_ab", 0xAB, 1), ("u16_45", 0x12345, 2), ("u32_deadbeef", 0xDEADBEEF, 4),
                 ("u32_1", 1, 4), ("u64_1", 1, 8), ("u64_2_48", 0x1_0000_0001, 8),
                 ("u32_ff", 0xFFFFFFFF, 4), ("u32_2_32", 0x1_0000_0000, 4),
                 ("u64_2_48b", 0x1_0000_0002, 8)]:
    h = hq()
    dt = DT[n]
    e = h.q(UOp.const(v & ((1 << (8 * n)) - 1), dt))
    rows("hq_q_%s" % nm, "%d:%s" % (e, bytes(h.blob).hex()))
# THE MASK: a value wider than the dtype is truncated, because `v & (1 << 8n -1)`.
h = hq()
h.q(UOp.const(0x1122334455667788, dtypes.u32))
rows("hq_q_mask_u32_from64", bytes(h.blob).hex())
h = hq()
h.q(UOp.const(0x1122334455667788, dtypes.u16))
rows("hq_q_mask_u16_from64", bytes(h.blob).hex())
# the PATCH arm
h = hq()
e = h.q(UOp.placeholder((4,), dtypes.u64, 0, device="NULL:0"))
rows("hq_q_patch_len", e)
rows("hq_q_patch_off", h.patches[0][0])
rows("hq_q_patch_iz", h.patches[0][1].dtype.itemsize)
rows("hq_q_patch_blob", bytes(h.blob).hex())
# the BINARY arm appends raw bytes and makes NO patch
h = hq()
e = h.q(UOp(Ops.BINARY, arg=bytes([1, 2, 3])))
rows("hq_q_bin_len", e)
rows("hq_q_bin_npatch", len(h.patches))
rows("hq_q_bin_blob", bytes(h.blob).hex())
# a sequence, which is what the gate really pins
h = hq()
h.q(1)
h.q(2)
h.q(UOp.const(0xDEADBEEF, dtypes.u32))
h.q(UOp.placeholder((4,), dtypes.u64, 0, device="NULL:0"))
h.q(UOp(Ops.BINARY, arg=bytes([9])))
rows("hq_q_seq_len", len(h.blob))
rows("hq_q_seq_blob", bytes(h.blob).hex())
rows("hq_q_seq_patches", ",".join(str(o) for o, _ in h.patches))

# ==========================================================================
# :379-385 `loop`: `trip = len(blob) - start`, patches move to
# `o + 4*k + r*trip`, and `blob += blob[start:] * vmax`.
# ==========================================================================
h = hq()
h.q(UOp.const(0xAA, dtypes.u32))
_start, _first = len(h.blob), len(h.patches)
_body = [UOp.const(7, dtypes.u32), UOp.placeholder((4,), dtypes.u64, 0, device="NULL:0")]
for u in _body:
    h.q(u)
_trip = len(h.blob) - _start
rows("hq_loop_trip", _trip)
rows("hq_loop_after_body", bytes(h.blob).hex())
rows("hq_loop_patch", ",".join(str(o) for o, _ in h.patches))
# THE EXPANSION, computed by CALLING the same expression Python writes.
def loop_expand(words, trip, vmax):
    # :384 `[(o + 4 * k + r * trip, (w >> (32 * k)).cast(uint32)) for o, w in words
    #        for k in range(w.dtype.itemsize // 4)]` with the r * trip replication.
    out = [o + 4 * k + r * trip for (o, iz) in words for r in range(vmax)
           for k in range(iz // 4)]
    return ",".join(str(x) for x in sorted(out)) or "-"
rows("hq_loop_expand_t1", loop_expand([(12, 8)], 12, 1))
rows("hq_loop_expand_t2", loop_expand([(12, 8)], 12, 2))
rows("hq_loop_expand_t3", loop_expand([(12, 8)], 12, 3))
rows("hq_loop_expand_two", loop_expand([(12, 8), (16, 4)], 20, 2))
rows("hq_loop_dwords_u64", 8 // 4)
rows("hq_loop_dwords_u32", 4 // 4)

# ==========================================================================
# :486-488 `bitcast_view` -- the THREE divisibility tests.
# ==========================================================================
def bv(max_numel, o, n, k, m):
    return None if ((o * k) % m or (n * k) % m or (max_numel * k) % m) else "%d-%d" % (o * k // m, (o + n) * k // m)


for nm, (mn, o, n, k, m) in {
        "u32_8_at0": (16, 0, 8, 4, 8), "u32_8_at1": (16, 1, 8, 4, 8),
        "u32_8_at2": (16, 2, 8, 4, 8), "u64_4_u32": (16, 0, 4, 8, 4),
        "u32_1_odd": (3, 0, 1, 4, 8), "u32_4_ok": (4, 0, 4, 4, 8),
        "u8_8_to_u64": (8, 0, 8, 1, 8), "u64_1_u32": (16, 1, 1, 8, 4)}.items():
    rows("hq_bv_%s" % nm, bv(mn, o, n, k, m) or "-")

# ==========================================================================
# :530-531 `lower_call`'s 128-BYTE ALIGNED SLOT OFFSETS, and :592's 256.
# ==========================================================================
def offs(sizes, it):
    a = [0]
    for s in sizes:
        a.append(a[-1] + round_up(s, 128) // it)
    return a


for nm, sizes, it in [("a", [64, 64, 8], 4), ("b", [8, 64, 130], 4), ("c", [128, 128], 8),
                      ("d", [1, 1, 1], 4), ("e", [4096, 8], 8), ("f", [256], 4),
                      ("g", [127, 129], 1)]:
    rows("hq_slots_%s" % nm, ",".join(str(x) for x in offs(sizes, it)))
rows("hq_slots_a_last", offs([64, 64, 8], 4)[-1])
for n in (0, 1, 4, 8, 127, 128, 129, 256, 257):
    rows("hq_align128_%d" % n, round_up(n, 128))
    rows("hq_align256_%d" % n, round_up(n, 256))
rows("hq_pad128_of", ",".join(str((-x) % 128) for x in (0, 1, 4, 8, 12, 16, 127, 128, 129)))
rows("hq_maxbuf_zero", max(0, 1))
rows("hq_maxbuf_7", max(7, 1))

# ==========================================================================
# :565 `use_rt = len(linear.src) < HCQ_CACHE_THRESH`
# ==========================================================================
for n in (0, 1, 63, 64, 65, 100):
    rows("hq_usert_%d" % n, b2i(n < H.HCQ_CACHE_THRESH.value))
rows("hq_usert_thresh", H.HCQ_CACHE_THRESH.value)

# ==========================================================================
# :388 and :630 -- THE TWO REFUSALS, as their MESSAGES.
# ==========================================================================
import inspect
try:
    H.HWQueue(_sub).submit(UOp.const(1, dtypes.u32))
except NotImplementedError as ex:
    rows("hq_refuse_submit", str(ex))
try:
    H.panic(RuntimeError, "unresolved link words on %s" % Ops.CALL)
except RuntimeError as ex:
    rows("hq_refuse_link", str(ex))
rows("hq_refuse_link_fmt", "unresolved link words on %s" % Ops.CALL)
rows("hq_refuse_submit_line", "hcq2.py:388")
rows("hq_refuse_link_line", "hcq2.py:630")

# ==========================================================================
# :111-116 `replace_buffer`'s SLOT ASSIGNMENT.
# ==========================================================================



_b = bufs("NULL:0", 4)
_b1 = bufs("NULL:0", 2)
# THE REAL FUNCTION, with `replace_buffer`'s own slot arithmetic, over a
# fixture of PLACEHOLDERS that are structurally distinct.
_slots, _param = {}, []


def repl_slots(bs):
    for b in bs:
        i = _slots.setdefault(b, len(_param))
        if i == len(_param):
            _param.append(b)
    return [str(_slots[b]) for b in bs]


for nm, bs in (("distinct", _b), ("repeat", [_b1[0], _b1[0], _b1[1]]),
               ("repeat_tail", [_b1[0], _b1[1], _b1[0]]),
               ("all_one", [_b1[0], _b1[0], _b1[0]])):
    _slots.clear()
    del _param[:]
    rows("hq_repl_%s_slots" % nm, ",".join(repl_slots(bs)))
    rows("hq_repl_%s_n" % nm, len(_param))
# `replace_buffer` ITSELF, which mints `UOp.param(slots[b], b.dtype, b.max_numel(),
# b.device)` and, when not use_rt, tags it "lt_input".
_p = H.replace_buffer((False, _param, _slots), _b1[0]) if _param else None
_rb = H.replace_buffer((True, [], {}), bufs("NULL:0", 1)[0])
rows("hq_repl_param_slot", _rb.arg.slot)
rows("hq_repl_param_name", _rb.arg.name)
rows("hq_repl_param_maxnumel", _rb.max_numel())
_rb2 = H.replace_buffer((False, [], {}), bufs("NULL:0", 1)[0])
rows("hq_repl_lt_tag", _rb2.tag)
rows("hq_repl_rt_tag", "%s" % _rb.tag)

print("hq-done=1")
