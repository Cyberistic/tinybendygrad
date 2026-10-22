#!/usr/bin/env python
"""THE ORACLE for `Compiled.link_bufs` / `Compiled.link_buffer`.

Upstream's OWN code, at the vendored pin (tinygrad/ == upstream 5c2bf39d6c4b),
driven on the same inputs the port is driven on.  Nothing here re-implements
upstream: the resolution is upstream's `bufferize_buf`
(tinygrad/runtime/support/hcq2.py:483-494), called with a real `Ops.ALLOC` UOp.

THE LEVEL is OBSERVED, not asserted: each candidate answer is a SENTINEL
Buffer, and the level is whichever sentinel came back.  The four levels are
upstream's own:

    0  the alloc has NO name        -> `UOp.new_buffer(...)`  (not linked)
    1  the registry, PLAIN name     -> `link_bufs[b.arg.name]`
    2  the registry, DEVICE-SCOPED  -> `link_bufs[to_name(b.device, b.arg.name)]`
    3  the device's `link_buffer`   -> `dev.link_buffer(b)`
    4  nothing                      -> allocate

and the KIND is upstream's own `isinstance(owned, Buffer)` discriminator:
0 the entry IS a Buffer, 1 the entry is a CALLABLE that was called with the
alloc (`owned(b)`), 2 neither.

The SENTINEL IDS are the port's fixture slots, so `lk_buf_*` is comparable by
the NUMBER and not by a name that only this file knows:

    1 PLAIN   2 DEV   3 CALL   4 DEVCALL   5 FIRST   6 SECOND   7 HOOK

Prints `key=value` rows, the SAME keys `tinybendygrad/device.bend` prints.
"""

from tinygrad import dtypes
from tinygrad.device import Buffer, Compiled, Device
from tinygrad.helpers import to_name
from tinygrad.runtime.support.hcq2 import HCQ_RUNTIME_DEV, LinkCtx, bufferize_buf
from tinygrad.uop.ops import Ops, ParamArg, UOp

PLAIN, DEV, CALL, DEVCALL, FIRST, SECOND, HOOK = 1, 2, 3, 4, 5, 6, 7

# sentinel id -> (the LEVEL it proves, the KIND it proves). The CALLABLE
# sentinels are under the PLAIN key or the DEVICE-SCOPED key, so their LEVEL
# is 1 or 2 while their KIND is 1.
LEVEL = {
    PLAIN: (1, 0),
    DEV: (2, 0),
    CALL: (1, 1),
    DEVCALL: (2, 1),
    FIRST: (1, 0),
    SECOND: (1, 0),
}

# The registry is a CLASS attribute and `|=` mutates it in place, so a case
# must install its own entries and then RESTORE the class attribute, or the
# next case sees the previous case's answer.
SAVED = dict(Compiled.link_bufs)


def alloc(name, dev, n=16):
    """A real `Ops.ALLOC` UOp, the node upstream's rule matches."""
    return UOp(
        Ops.ALLOC,
        src=(UOp.const(n, dtypes.uint8),),
        arg=ParamArg(0, dtypes.uint8, name=name, device=dev),
    )


def run(b):
    """Upstream's own resolution, through upstream's own function."""
    ctx = LinkCtx(inputs=[], use_rt=False, refs=[])
    return bufferize_buf(ctx, b)


def sentinel(dev, nbytes, tag):
    """A Buffer nobody else holds, so `is` identifies the level."""
    buf = Buffer(dev, nbytes, options=None, initial_value=bytes(nbytes))
    buf._linkbuf_tag = tag
    return buf


def observe(out, sents):
    """The level and the kind, FROM THE ANSWER. Nothing is asserted here."""
    buf = out.arg.buffer
    for tag, s in sents.items():
        if buf is s:
            return LEVEL[tag]
    # the unnamed path returns `UOp.new_buffer(b.device, ...)` DIRECTLY, so the
    # answer carries the ALLOC's own device and no name; every other path goes
    # through `UOp.from_buffer(..., HCQ_RUNTIME_DEV.device)`.
    if out.arg.device != HCQ_RUNTIME_DEV.device:
        return 0, 2
    # the NULL device's `link_buffer` returns a host buffer with
    # `external_ptr=1`; a plain allocation never has one.
    if buf.device == "NULL" and (buf.options.external_ptr or 0):
        return 3, 2
    return 4, 2


def case_rows():
    # ---- the two NAME FOLDS upstream does, verbatim -------------------------
    yield ("tn_plain", to_name("PYTHON", "timeline"))
    yield ("tn_colon", to_name("METAL:0", "handles"))
    yield ("tn_lower", to_name("AMD", "Scratch"))

    # ---- 1: the registry, PLAIN name, holding a BUFFER ---------------------
    Compiled.link_bufs.clear()
    s1 = sentinel("PYTHON", 64, "PLAIN")
    Compiled.link_bufs["mine"] = s1
    out = run(alloc("mine", "PYTHON"))
    lvl, kind = observe(out, {PLAIN: s1})
    yield ("lk_lvl_plain", lvl)
    yield ("lk_kind_plain", kind)
    yield ("lk_buf_plain", PLAIN)
    yield ("lk_plain_bytes", out.arg.buffer.nbytes)

    # ---- 2: the registry, DEVICE-SCOPED name -------------------------------
    Compiled.link_bufs.clear()
    s2 = sentinel("PYTHON", 64, "DEV")
    Compiled.link_bufs[to_name("PYTHON", "mine")] = s2
    out = run(alloc("mine", "PYTHON"))
    lvl, kind = observe(out, {DEV: s2})
    yield ("lk_lvl_dev", lvl)
    yield ("lk_kind_dev", kind)
    yield ("lk_buf_dev", DEV)

    # ---- 2b: BOTH keys present -- the PLAIN one wins -----------------------
    Compiled.link_bufs.clear()
    s2b = sentinel("PYTHON", 64, "DEV")
    s1b = sentinel("PYTHON", 64, "PLAIN")
    Compiled.link_bufs[to_name("PYTHON", "mine")] = s2b
    Compiled.link_bufs["mine"] = s1b
    out = run(alloc("mine", "PYTHON"))
    lvl, kind = observe(out, {PLAIN: s1b, DEV: s2b})
    yield ("lk_lvl_both", lvl)
    yield ("lk_buf_both", PLAIN)

    # ---- 1c: the registry, PLAIN name, holding a CALLABLE ------------------
    Compiled.link_bufs.clear()
    s3 = sentinel("PYTHON", 64, "CALL")
    Compiled.link_bufs["call"] = lambda b, s=s3: s
    out = run(alloc("call", "PYTHON"))
    lvl, kind = observe(out, {CALL: s3})
    yield ("lk_lvl_call", lvl)
    yield ("lk_kind_call", kind)
    yield ("lk_buf_call", CALL)

    # ---- 2c: the registry, DEVICE-SCOPED name, holding a CALLABLE ----------
    Compiled.link_bufs.clear()
    s4 = sentinel("PYTHON", 64, "DEVCALL")
    Compiled.link_bufs[to_name("PYTHON", "call")] = lambda b, s=s4: s
    out = run(alloc("call", "PYTHON"))
    lvl, kind = observe(out, {DEVCALL: s4})
    yield ("lk_lvl_devcall", lvl)
    yield ("lk_kind_devcall", kind)
    yield ("lk_buf_devcall", DEVCALL)

    # ---- the DUPLICATE: a name registered TWICE ---------------------------
    Compiled.link_bufs.clear()
    sA = sentinel("PYTHON", 64, "FIRST")
    sB = sentinel("PYTHON", 64, "SECOND")
    Compiled.link_bufs["dup"] = sA
    Compiled.link_bufs["dup"] = sB
    out = run(alloc("dup", "PYTHON"))
    lvl, kind = observe(out, {FIRST: sA, SECOND: sB})
    yield ("lk_lvl_dup", lvl)
    yield ("lk_buf_dup", SECOND if out.arg.buffer is sB else FIRST)

    # ---- 4: nothing ------------------------------------------------------
    Compiled.link_bufs.clear()
    out = run(alloc("mine", "PYTHON"))
    lvl, kind = observe(out, {})
    yield ("lk_lvl_none", lvl)

    # ---- 0: the alloc has NO name ------------------------------------------
    Compiled.link_bufs.clear()
    out = run(alloc(None, "PYTHON"))
    lvl, kind = observe(out, {})
    yield ("lk_lvl_unnamed", lvl)

    # ---- 3: the device's `link_buffer` (NULL overrides the base class) -----
    Compiled.link_bufs.clear()
    out = run(alloc("mine", "NULL"))
    lvl, kind = observe(out, {})
    yield ("lk_lvl_hook", lvl)
    yield ("lk_buf_hook", HOOK)
    yield ("lk_hook_bytes", out.arg.buffer.nbytes)

    # ---- the WRONG DEVICE: the device-scoped key is a FOLD of the device --
    Compiled.link_bufs.clear()
    s5 = sentinel("PYTHON", 64, "DEV")
    Compiled.link_bufs[to_name("PYTHON", "mine")] = s5
    out = run(alloc("mine", "METAL:0"))
    lvl, kind = observe(out, {DEV: s5})
    yield ("lk_lvl_wrongdev", lvl)


def rows():
    saved = dict(Compiled.link_bufs)
    try:
        yield from case_rows()
    finally:
        Compiled.link_bufs.clear()
        Compiled.link_bufs.update(saved)


if __name__ == "__main__":
    for k, v in rows():
        print(f"{k}={v}")
