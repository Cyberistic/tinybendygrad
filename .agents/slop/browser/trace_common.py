#!/usr/bin/env python3
"""trace_common.py -- THE TRACER, RE-POINTED AT THE CURRENT SUBSTRATE.

    .agents/slop/browser/trace_common.py        # self-check: one forward, count launches

WHY THIS FILE EXISTS AND NOT AN EDIT TO `.agents/slop/xd2/trace_forward.py`.
`AGENTS.md` records the rule and the cost: *"a SCRIPT that others are EXECUTING
is SHARED STATE TOO, and EDITING IT IN PLACE IS THE HAZARD ... THE SAFE FORM IS
TO WRITE A NEW PATH AND LEAVE THE OLD ONE ALONE."* **⇒ SO THIS IS A NEW PATH.**
`xd2/trace_forward.py` is STALE and now raises `AttributeError: 'Buffer' object
has no attribute 'size'`; it is REPORTED here rather than patched.

THE ONE SUBSTRATE FACT THAT MOVED, MEASURED:

    $ .venv/bin/python -c "from tinygrad.device import Buffer; print([a for a in dir(Buffer) if not a.startswith('_')])"
    ['allocate', 'allocator', 'as_memoryview', 'base', 'copy_from', 'deallocate',
     'ensure_allocated', 'get_buf', 'get_storage', 'host', 'is_allocated', 'meta',
     'profile_events', 'trace_num', 'view']

**⇒ `size` IS GONE AND `nbytes` IS WHAT IT BECAME** (`tinygrad/device.py:116`
sets `self.device, self.nbytes, self.offset, self._base`). **⇒ AND THE TRACER
WENT STALE SILENTLY**: nothing read the tracer, so nothing noticed -- which is
the same class the tree names for a gate that is never run.

EVERYTHING ELSE IS `xd2/trace_forward.py`'s, AND IT WAS GOOD: the
`exec_kernel` hook, the two measured WGSL shims, the buffer naming with its
strong-ref list, and the per-launch `after` snapshot. **⇒ THE HOOK IS THE PART
THAT MATTERS: it wraps `tinygrad/engine/realize.py`'s ONE place that knows every
launch's binding order, dispatch geometry and buffer contents, so nothing about
the schedule is re-derived here.**
"""
import base64
import json
import os
import pathlib
import re
import sys

# **⇒ `DEV=CPU` MUST BE SET BEFORE TINYGRAD IMPORTS, AND ITS ABSENCE IS WHAT
# MADE THE FIRST THREE ATTEMPTS AT THIS TRACER FAIL.** MEASURED: with no `DEV`
# the default device on darwin is `METAL`, so the traced AST was a METAL kernel
# and `to_program(..., WGSLRenderer)` died with
# `RuntimeError: long decomposition of variable None unsupported`. **⇒ AND THE
# CAUSE WAS TWO U64 `PARAM`s NAMED `mtl_cb` AND `mtl_enc`** --
# `tinygrad/runtime/ops_metal.py:104` mints exactly those for a Metal command
# buffer and encoder -- so the "u64 problem" was never WGSL's: it was a METAL
# kernel handed to a WGSL renderer. **⇒ A DECOMPOSITION ERROR IS A SYMPTOM AND
# THE PARAM NAMES WERE THE EVIDENCE.**
os.environ.setdefault("DEV", "CPU")

# **⇒ AND `DMC=1` IS REQUIRED FOR THE BACKWARD PASS, AND IT IS MEASURED.**
# ONE of the training step's 90 launches failed to render with
# `AssertionError: memory coalescing does not support gated loads/stores`
# (`tinygrad/codegen/late/coalesce.py`), and it is the cross-entropy kernel:
# a `WHERE`-guarded LOAD is exactly what the coalescer cannot vectorise.
# **⇒ AND `DMC` IS TINYGRAD's OWN SWITCH FOR IT** -- "1=skip memory coalescing
# pass" -- so this is the compiler's own flag and not a patch. **MEASURED:
# `DMC=0` renders 89 of 90; `DMC=1` renders 90 of 90.** **⇒ AND IT IS HONEST
# RATHER THAN CONVENIENT: the traced AST is the CPU's, and the CPU does not
# coalesce either, so the un-coalesced WGSL is the same arithmetic the CPU ran.**
os.environ.setdefault("DMC", "1")

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "examples"))

from tinygrad import dtypes  # noqa: E402
from tinygrad.dtype import AddrSpace  # noqa: E402
from tinygrad.device import Device  # noqa: E402
from tinygrad.engine.realize import exec_kernel as _orig_exec_kernel  # noqa: E402
from tinygrad.uop.ops import Ops, PatternMatcher, UPat  # noqa: E402
from tinygrad.renderer.wgsl import WGSLRenderer  # noqa: E402
import tinygrad.engine.realize as RZ  # noqa: E402

launches: list = []
buffers: dict = {}
_seen: dict = {}
_keep: list = []
_order = [0]
ENTRY_RE = re.compile(r"@compute[^\n]*\bfn\s+(\w+)\s*\(", re.M)


def raw_of(buf) -> bytes:
    """The buffer's bytes as the page will upload them.

    **⇒ AND `as_memoryview` READS THE **BASE ALLOCATION**, NOT THE VIEW.** A
    `Buffer` can be a view with `nbytes` smaller than its `base`'s, so a `size`
    taken from `buf.nbytes` and a payload taken from `as_memoryview(buf)` are TWO
    DIFFERENT LENGTHS. **⇒ MEASURED: EfficientNet's replay died with `Write range
    (size: 4816896) does not fit in [Buffer] size (1605632)`**, which is exactly
    that mismatch. **⇒ SO THE SIZE IS DERIVED FROM THE BYTES AND NOT READ FROM A
    FIELD**, and the two cannot disagree by construction.
    """
    return bytes(buf.as_memoryview(allow_zero_copy=True))


def bits_of(buf) -> str:
    """The buffer's bytes, base64'd -- exactly the u32 words the gate is about.

    **⇒ AND `buf.dtype` IS READ OFF `buf.base`, NOT `buf`**: a `Buffer` here has
    no `dtype` of its own (`tinygrad/device.py:116`), the ALLOCATION does.
    """
    raw = bytes(buf.as_memoryview(allow_zero_copy=True))
    # **⇒ AND `buf.dtype` DOES NOT EXIST ANY MORE**, AND NEITHER DOES
    # `buf.base.dtype`: MEASURED, `AttributeError: 'Buffer' object has no
    # attribute 'dtype'` (`tinygrad/device.py:116` sets only
    # `device, nbytes, offset, base`). **⇒ THE DTYPE LIVES ON THE UOP THAT OWNS
    # THE BUFFER**, so this function reads BYTES and the caller names the dtype
    # from the CALL. **⇒ AND THE 4-BYTE TEST WENT WITH IT**: `len(raw) %
    # itemsize` cannot be asked of a Buffer that does not carry one, so the
    # caller asks the UOP instead.
    return base64.b64encode(raw).decode("ascii")


def dt_of(u) -> object:
    """The dtype of the UOp a buffer slot binds, or `None`."""
    try:
        return u.dtype
    except Exception:
        return None


def name_of(buf) -> str:
    """`base` owns the storage, so a view names as its allocation.

    The strong ref is LOAD-BEARING: nothing else holds these Buffers, so CPython
    frees them and hands the SAME id to the next allocation. Measured by the
    forward unit: without it a recycled id made launch 11 report BatchNorm's
    running stats as wildly wrong."""
    key = id(buf.base)
    if key not in _seen:
        _seen[key] = f"b{_order[0]}"
        _order[0] += 1
        _keep.append(buf.base)
    return _seen[key]


class BrowserWGSL(WGSLRenderer):
    """WGSLRenderer plus EXACTLY TWO string-level shims, each a MEASURED gap in
    `tinygrad/renderer/wgsl.py`. Neither touches the uop graph, the rewrites or
    the arithmetic: both only spell a uop tinygrad itself built.

    GAP 1 -- `code_for_op` has no `Ops.FDIV` (cstyle.py:311 defines it,
    wgsl.py:60 does not). BatchNorm's `rsqrt(running_var + eps)` is one FDIV per
    element, so without this `render_alu` raises `KeyError: Ops.FDIV`.

    GAP 2 -- `float4` is None (`supports_float4 = False`, wgsl.py:58), and that
    flag is read in exactly ONE place (`coalesce.py:143`), which gates only
    vectorised LOAD/STORE; a STACK built elsewhere still reaches
    `string_rewrite` and raises `AttributeError: 'NoneType' ...`. **⇒ AND THE
    ARITY COMES FROM THE STACK's OWN SRC COUNT** -- the max-pool kernel stacks
    two f32 and `vec4<f32>(a, b)` is rejected by WGSL.

    **⇒ AND NO THIRD SHIM IS ADDED HERE, ON PURPOSE.** A shim covers a MEASURED
    gap; guessing at `Ops.CMOD`/`Ops.THREEFRY` before a trace asks for one would
    be inventing arithmetic, and my first draft invented `Ops.FMOD`, **WHICH IS
    NOT IN THIS ENUM AT ALL** (`AttributeError: type object 'Ops' has no
    attribute 'FMOD'`). **⇒ THE TRACE PRINTS EVERY LAUNCH IT COULD NOT RENDER**,
    so the gaps the backward pass really hits are NAMED by the run and not by me.
    """
    string_rewrite = PatternMatcher([
        (UPat(Ops.STACK, name="x"),
         lambda ctx, x: f"vec{len(x.src)}<{ctx.type_map[x.dtype]}>({','.join(ctx[y] for y in x.src)})"),
    ]) + WGSLRenderer.string_rewrite
    code_for_op = {
        **WGSLRenderer.code_for_op,
        Ops.FDIV: lambda a, b, dtype: f"({a}/{b})",
    }


_renderer = BrowserWGSL(Device["CPU"])


def traced_exec_kernel(ctx, call, ast, devices=None):
    from tinygrad.codegen import to_program
    resolved = RZ.resolve_params(call, ctx.input_uops)
    rec = {"names": [], "global": None, "local": None, "wgsl": None, "entry": None, "bufs": []}
    to_program_src = None
    for device, (bufs, device_vars) in zip(devices or RZ.to_tuple(call.src[1].device),
                                           RZ.unwrap_multi(call, [resolved[i] for i in ast.arg.globals])):
        var_vals = {**ctx.var_vals, **device_vars}
        prg_bufs = [b.ensure_allocated() for b in bufs]
        g, l = ast.arg.launch_dims(var_vals)
        rec["global"], rec["local"] = list(g), list(l)
        try:
            prg = to_program(ast.src[0], _renderer)
            src = [str(u.arg) for u in prg.src if u.op is Ops.SOURCE]
            rec["wgsl"] = src[0] if src else None
            # THE ENTRY POINT IS READ OUT OF THE WGSL, because that string is
            # what the browser hands `createComputePipeline`. The fallback is
            # the KernelInfo's own name -- **⇒ AND IT IS `ast.arg.name`, NOT
            # `ProgramInfo.function_name`**: MEASURED, `ProgramInfo` now carries
            # `global_size, local_size, params, globals, outs, ins, target` and
            # nothing else.
            m = ENTRY_RE.search(rec["wgsl"] or "")
            rec["entry"] = m.group(1) if m else str(getattr(ast.arg, "name", "kernel"))
        except Exception as e:
            # A renderer that cannot express a uop the schedule built is a fact
            # about the PROGRAM, so the launch is NAMED rather than dropped.
            rec["wgsl"], rec["entry"] = None, None
            rec["wgslError"] = f"{type(e).__name__}: {e}"
            print(f"  !! WGSL render failed on global={list(g)}: {type(e).__name__}: {e}", file=sys.stderr)
        # THE DTYPE COMES OFF THE CALL, BY SLOT. `ast.arg.globals[i]` is the
        # slot the i-th bound buffer fills, and `call.src[1+slot]` is the UOp
        # that owns it -- so the dtype is READ, not guessed.
        for pos, b in enumerate(prg_bufs):
            n = name_of(b)
            if n not in buffers:
                slot = ast.arg.globals[pos] if pos < len(ast.arg.globals) else None
                u = call.src[1 + slot] if slot is not None and 1 + slot < len(call.src) else None
                dt = dt_of(u) if u is not None else None
                payload = bits_of(b)
                buffers[n] = {"size": len(raw_of(b)),
                              "dtype": str(dt) if dt is not None else "-",
                              "f32": dt is not None and getattr(dt, "itemsize", 0) == 4,
                              # **⇒ AND `w32` IS WHAT THE SNAPSHOTS FILTER ON, NOT
                              # `f32`, AND THE DIFFERENCE IS A MEASURED BUG.** The
                              # filter was `itemsize == 4`, which is TRUE FOR i32 AND
                              # u32 TOO -- **⇒ BUT THE FIRST VERSION ASKED FOR `f32`
                              # AND SO RECORDED **NO SNAPSHOT AT ALL** FOR AN INT32
                              # BUFFER.** MEASURED: the MNIST training step's LABEL is
                              # an i32 buffer, so it was never uploaded, the
                              # cross-entropy kernel's gate `-1 < label < 10` read a
                              # different element, and the loss came back `0` where
                              # CPython had `2.7735066413879395`.
                              "w32": dt is not None and getattr(dt, "itemsize", 0) == 4,
                              "b64": payload}
            rec["bufs"].append(n)
        # **⇒ AND THE `vals` UNIFORMS **ARE** RECORDED, AND DROPPING THEM WAS A
        # MEASURED BUG.** `ProgramInfo` has no `vals` any more (the 2026-10-20
        # re-vendor, upstream `a6addc2d4`), so the first version of this tracer
        # recorded none -- **⇒ AND THE PAGE THEN BUILT BIND GROUPS WITH TOO FEW
        # ENTRIES, SO EVERY KERNEL THAT TAKES A SCALAR `vals` DID NOT RUN AND ITS
        # OUTPUT BUFFER KEPT ITS FILL.** MEASURED: 26 of 50 buffers agreed and the
        # rest held `0` or `1.0f`.
        #
        # **⇒ AND THE READING IS `exec_kernel`'s OWN** (`realize.py:164-166`): the
        # kernel's params in SLOT ORDER, and a param is a `vals` scalar iff its
        # addrspace is ALU. Its value is the bound variable's value, or the
        # resolved `call.src[1+slot]`'s constant.
        vals = []
        for prm in ast.kernel_params:
            if prm.addrspace is not AddrSpace.ALU:
                continue
            if prm.is_variable:
                vals.append(int(var_vals[prm.expr]))
            else:
                vals.append(int(RZ.resolve_params(call, ctx.input_uops)[prm.arg.slot].val))
        rec["vals"] = vals
        rec["_bufs"] = prg_bufs
        out_slots = set(ast.arg.outs)
        rec["outs"] = [pos for pos, slot in enumerate(ast.arg.globals) if slot in out_slots]
    launches.append(rec)
    # THE PAGE'S INPUTS: every bound buffer no EARLIER launch wrote. A buffer an
    # earlier launch wrote is already correct on the GPU, so re-uploading it
    # would turn the replay into a memory dump instead of a computation.
    for i, b in enumerate(rec["_bufs"]):
        if i in rec["outs"]:
            continue
        if buffers.get(name_of(b), {}).get("w32"):
            rec.setdefault("in", {})[name_of(b)] = bits_of(b)
    ets = _orig_exec_kernel(ctx, call, ast, devices)
    for b in rec["_bufs"]:
        if buffers.get(name_of(b), {}).get("w32"):
            rec.setdefault("after", {})[name_of(b)] = bits_of(b)
    _written.update(rec["bufs"][i] for i in rec["outs"])
    return ets


_written: set = set()


def install() -> None:
    """Put the hook on. **⇒ AND THE RETURNED `restore` MUST BE CALLED**, or every
    later realize in the process is traced too."""
    RZ.exec_kernel = traced_exec_kernel


def restore() -> None:
    RZ.exec_kernel = _orig_exec_kernel


def reset() -> None:
    launches.clear()
    buffers.clear()


def normalize_sizes(buffers: dict, frames: list, final: dict) -> int:
    """Make ONE allocation SIZE per buffer name: the longest payload seen.

    **⇒ AND A BASE ALLOCATION CAN BE **REALLOCATED BIGGER** DURING A TRACE**, so
    one name can carry two payload lengths -- MEASURED: `Write range (size:
    4816896) does not fit in [Buffer] size (1605632)` on EfficientNet's replay,
    because the first-bind view was 1605632 bytes and a later snapshot of the SAME
    allocation was 4816896.

    **⇒ AND ONLY THE **SIZE** MOVES. THE PAYLOADS ARE LEFT ALONE**, because a
    `Queue.writeBuffer` of FEWER bytes than the buffer is legal and leaves the
    rest at whatever they were -- which for a freshly created `GPUBuffer` is
    zero. **⇒ PADDING THE PAYLOADS INSTEAD WAS MEASURED TO BE WRONG: it rewrote
    215 payloads and took the JSON past `RangeError: Invalid string length`, so a
    transport detail became a file nobody can read.**
    """
    import base64 as _b
    def nbytes(b64: str) -> int:
        return len(_b.b64decode(b64))
    want = {}
    for n, b in buffers.items():
        if "b64" in b:
            want[n] = max(want.get(n, 0), nbytes(b["b64"]))
        elif "size" in b:
            want[n] = max(want.get(n, 0), b["size"])
    for fr in frames:
        for key in ("in", "after"):
            for n, v in (fr.get(key) or {}).items():
                want[n] = max(want.get(n, 0), nbytes(v))
    for n, v in final.items():
        want[n] = max(want.get(n, 0), nbytes(v))
    grown = 0
    for n, b in buffers.items():
        if b.get("size") != want.get(n, b.get("size")):
            grown += 1
        b["size"] = want.get(n, b["size"])
    return grown


def intern_payloads(buffers: dict, frames: list, final: dict):
    """Replace every base64 payload with an INDEX into one deduplicated table.

    **⇒ AND THE DUPLICATION IS THE WHOLE SIZE PROBLEM.** MEASURED: EfficientNet-0's
    training step is **13 154 launches** and its trace was **5.5 GB** at 224x224
    and **610 MB** at 64x64 -- and the launch count did not move with the input
    size, because the WEIGHTS are re-uploaded by every launch that reads them and
    they are BYTE-IDENTICAL every time. **⇒ SO THE FILE WAS ONE ARRAY OF THE SAME
    WEIGHTS COPIED TWENTY THOUSAND TIMES.**

    **⇒ AND AN INDEX IS THE RIGHT SPELLING**: the page resolves
    `typeof v === "number" ? payloads[v] : v`, so the trace keeps its shape and
    only the transport changes. Returns `(payloads, buffers, frames, final)`.
    """
    table: list = []
    index: dict = {}

    def put(b64: str):
        i = index.get(b64)
        if i is None:
            i = len(table)
            table.append(b64)
            index[b64] = i
        return i

    for n, b in list(buffers.items()):
        if "b64" in b:
            b["b64"] = put(b["b64"])
    for fr in frames:
        for key in ("in", "after"):
            d = fr.get(key)
            if not d:
                continue
            for n in list(d):
                d[n] = put(d[n])
    for n in list(final):
        final[n] = put(final[n])
    return table


def frames(rec) -> dict:
    """One launch, with the strong refs stripped -- the JSON shape the page reads."""
    return {k: v for k, v in rec.items() if not k.startswith("_")}


# --------------------------------------------------------------------------
# THE SELF-CHECK: one forward, and the launch count is the verdict.
# --------------------------------------------------------------------------
def deterministic(model, seed: int = 0xC0FFEE) -> None:
    """Fix the weights so the oracle is reproducible, WITHOUT touching BatchNorm's
    running statistics: an untrained BatchNorm has `running_mean=0,
    running_var=1`, and eval-mode BatchNorm divides by `sqrt(running_var+eps)`,
    so a random NEGATIVE `running_var` makes the whole forward pass NaN."""
    from tinygrad import Tensor
    rng = np.random.RandomState(seed)
    from tinygrad.nn.state import get_state_dict
    for name, p in get_state_dict(model).items():
        if "running_" in name or not dtypes.is_float(p.dtype):
            continue
        v = rng.randn(p.numel()).astype(np.float32) * np.float32(0.1) + np.float32(0.01 * (1 + rng.randint(0, 3)))
        p.assign(Tensor(v.reshape(p.shape).copy()))


def main() -> int:
    from beautiful_mnist import Model
    from tinygrad import Tensor, Context

    m = Model()
    deterministic(m)
    x = Tensor(np.linspace(-0.5, 0.5, 784, dtype=np.float32).reshape(1, 1, 28, 28))
    reset()
    install()
    try:
        with Context(TRAINING=0):
            out = m(x).realize()
    finally:
        restore()
    print(f"forward launches={len(launches)}  buffers={len(buffers)}  out={list(out.shape)}")
    unrendered = [i for i, r in enumerate(launches) if not r.get("wgsl")]
    print(f"WGSL-unrendered={len(unrendered)} of {len(launches)}")
    # A COUNT OF ZERO IS THE FAILURE MODE THE FORWARD UNIT NAMED: a warm cache
    # leaves the traced pass with zero launches and it reads exactly like a model
    # that computes nothing.
    return 0 if launches and not unrendered else 1


if __name__ == "__main__":
    raise SystemExit(main())
