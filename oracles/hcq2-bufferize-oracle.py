#!/usr/bin/env python
"""THE ORACLE for `bufferize_buf` -- upstream's OWN function, driven on the port's fixtures.

    .venv/bin/python oracles/hcq2-bufferize-oracle.py                  # the rows
    .venv/bin/python oracles/hcq2-bufferize-oracle.py --compare ROWS     # the verdict

WHAT THIS IS. `tinygrad/runtime/support/hcq2.py:483-494` at the vendored pin
(upstream `5c2bf39d6c4b`) carries `bufferize_buf`, the ONE consumer of the link
mechanism `device.py:377` (`Compiled.link_bufs`) and `device.py:411`
(`Compiled.link_buffer`). This file drives THAT function -- not a
re-implementation of it -- with a real `Ops.ALLOC` UOp, and OBSERVES the answer.

THE LEVEL IS OBSERVED, NOT ASSERTED. Every candidate answer is a SENTINEL
`Buffer` nobody else holds, so the level is whichever sentinel came back:

    0  the alloc has NO name        -> `UOp.new_buffer(...)`  (a FRESH buffer)
    1  the registry, PLAIN name     -> `link_bufs[b.arg.name]`
    2  the registry, DEVICE-SCOPED  -> `link_bufs[to_name(b.device, b.arg.name)]`
    3  the device's `link_buffer`   -> `dev.link_buffer(b)`
    4  nothing                      -> allocate

and the KIND is upstream's own `isinstance(owned, Buffer)` discriminator:
0 the entry IS a Buffer, 1 the entry is a CALLABLE that upstream called with the
alloc (`owned(b)`), 2 neither.

THE SENTINEL IDS ARE THE PORT'S ARENA SLOTS, so the two lanes are compared BY
THE NUMBER and not by a name only this file knows:

    1 PLAIN   2 DEV   3 CALL   4 DEVCALL   5 FIRST   6 SECOND   7 HOOK   8 FRESH

`8` is the buffer the ALLOCATION path makes: it is in nobody's registry, so it
is reported as the slot the port's arena appends it to.

THE SIZE IS THE POINT. `bz_bytes_*` is the byte count of the buffer that came
back, and for a LINKED buffer that is the REGISTRY'S size -- upstream never
resizes a registered buffer to fit the alloc:

    owned = Compiled.link_bufs.get(b.arg.name, ...)
    if owned is not None: r = owned if isinstance(owned, Buffer) else owned(b)

There is no `max_numel` anywhere on that path. A port that resized a linked
buffer to the alloc would answer 16 where this answers 64.

THE DEVICE OF THE RESULT is upstream's `UOp.from_buffer(r, b.dtype,
HCQ_RUNTIME_DEV.device)` -- the linked buffer is RE-PLACED on the runtime
device -- against the unnamed path's `UOp.new_buffer(b.device, ...)`, which
keeps the alloc's own device. `bz_dev_*` is that string.

THE TWO DEVICE STRINGS, AND WHY THEY DIFFER. The `tn_*` rows are the
`to_name` FOLDS and they use "PYTHON", because `device.bend`'s own rows
(`tn_plain`, `tn_colon`, `tn_lower`) use that device and this file re-checks
them. The `bz_*` rows use "CPU" and "NULL", because `device.bend`'s device
table (`dev_name`) has no index for "PYTHON" and a buffer the port ALLOCATES
lands in an arena slot that carries a device INDEX.

THE REGISTRY IS A CLASS ATTRIBUTE and `|=` mutates it IN PLACE, so a case
installs its own entries and then RESTORES the class attribute, or the next
case sees the previous case's answer. A name registered TWICE is installed by
TWO UPDATES, because `dict.update` OVERWRITES and the second registration is
the one that survives.
"""
import sys

from tinygrad import dtypes
from tinygrad.device import Buffer, Compiled, Device
from tinygrad.helpers import HCQ_RUNTIME_DEV, to_name
from tinygrad.runtime.support.hcq2 import LinkCtx, bufferize_buf
from tinygrad.uop.ops import Ops, ParamArg, UOp

PLAIN, DEV, CALL, DEVCALL, FIRST, SECOND, HOOK, FRESH, TIMELINE = 1, 2, 3, 4, 5, 6, 7, 8, 8

# THE PORT'S DEVICE TABLE HAS NO "PYTHON", so the alloc's device is one the
# port can name: "CPU" (index 7) for the cases the BASE class answers and
# "NULL" (index 11) for the one whose `link_buffer` answers.
CPU, NULL = "CPU", "NULL"
CPU0 = "CPU:0"  # the SAME device, a DIFFERENT string: the device-scoped key folds it

# the sentinel's byte count: a REGISTERED buffer's own size, which is NOT the
# alloc's 16
SENT_BYTES = 64

LEVEL_OF = {PLAIN: (1, 0), DEV: (2, 0), CALL: (1, 1),
            DEVCALL: (2, 1), FIRST: (1, 0), SECOND: (1, 0), TIMELINE: (1, 1)}


def alloc(name, dev, n=16, dt=dtypes.uint8):
    """A real `Ops.ALLOC` UOp -- the node upstream's rule matches."""
    return UOp(
        Ops.ALLOC,
        src=(UOp.const(n, dt),),
        arg=ParamArg(0, dt, name=name, device=dev),
    )


def run(b, use_rt=False):
    """Upstream's own resolution, through upstream's own function."""
    ctx = LinkCtx(inputs=[], use_rt=use_rt, refs=[])
    return bufferize_buf(ctx, b)


def sentinel(dev, nbytes):
    """A Buffer nobody else holds, so `is` identifies the level."""
    return Buffer(dev, nbytes, options=None, initial_value=bytes(nbytes))


def observe(out, sents):
    """`(level, kind, which, nbytes)` -- all four READ OFF THE ANSWER."""
    buf = out.arg.buffer
    nb = buf.nbytes
    for tag, s in sents.items():
        if buf is s:
            level, kind = LEVEL_OF[tag]
            return level, kind, tag, nb
    # the NULL device's `link_buffer` returns a HOST buffer with
    # `external_ptr=1`; a plain allocation never has one, and nothing else is
    # ever on the NULL device.
    if buf.device == NULL and (buf.options.external_ptr or 0):
        return 3, 2, HOOK, nb
    # the unnamed path returns `UOp.new_buffer(b.device, ...)` DIRECTLY, so the
    # answer carries the ALLOC's own device; every other path goes through
    # `UOp.from_buffer(..., HCQ_RUNTIME_DEV.device)`.
    if out.arg.device != HCQ_RUNTIME_DEV.device:
        return 0, 2, FRESH, nb
    return 4, 2, FRESH, nb


def case(nm, regs, name, dev, sents, use_rt=False, n=16):
    """ONE case: install the registry, run upstream, and yield the five rows."""
    Compiled.link_bufs.clear()
    for k, v in regs:
        Compiled.link_bufs[k] = v
    out = run(alloc(name, dev, n=n), use_rt=use_rt)
    lvl, kind, which, nb = observe(out, sents)
    yield (f"bz_lvl_{nm}", lvl)
    yield (f"bz_kind_{nm}", kind)
    yield (f"bz_buf_{nm}", which)
    yield (f"bz_bytes_{nm}", nb)
    yield (f"bz_dev_{nm}", out.arg.device)


def rows():
    """THE CASES, in the port's order. Each installs its own registry."""
    saved = dict(Compiled.link_bufs)
    try:
        yield from case_rows()
    finally:
        Compiled.link_bufs.clear()
        Compiled.link_bufs.update(saved)


def case_rows():
    # ---- the two NAME FOLDS, in `device.bend`'s device ----------------------
    yield ("tn_plain", to_name("PYTHON", "timeline"))
    yield ("tn_colon", to_name("METAL:0", "handles"))
    yield ("tn_lower", to_name("AMD", "Scratch"))

    # ---- the DEVICE STRINGS the port's device table has to agree with ------
    yield ("bz_devname_cpu", Device[CPU].device)
    yield ("bz_devname_null", Device[NULL].device)

    # ---- 1: the registry, PLAIN name, holding a BUFFER ---------------------
    s1 = sentinel(CPU, SENT_BYTES)
    yield from case("plain", [("mine", s1)], "mine", CPU, {PLAIN: s1})

    # ---- 2: the registry, DEVICE-SCOPED name -------------------------------
    s2 = sentinel(CPU, SENT_BYTES)
    yield from case("dev", [(to_name(CPU, "mine"), s2)], "mine", CPU, {DEV: s2})

    # ---- 2b: BOTH keys present -- the PLAIN one wins -----------------------
    s2b = sentinel(CPU, SENT_BYTES)
    s1b = sentinel(CPU, SENT_BYTES)
    yield from case("both", [(to_name(CPU, "mine"), s2b), ("mine", s1b)], "mine", CPU,
                    {DEV: s2b, PLAIN: s1b})

    # ---- 1c: the registry, PLAIN name, holding a CALLABLE ------------------
    s3 = sentinel(CPU, SENT_BYTES)
    yield from case("call", [("call", lambda b, s=s3: s)], "call", CPU, {CALL: s3})

    # ---- 2c: the registry, DEVICE-SCOPED name, holding a CALLABLE ----------
    s4 = sentinel(CPU, SENT_BYTES)
    yield from case("devcall", [(to_name(CPU, "call"), lambda b, s=s4: s)], "call", CPU,
                    {DEVCALL: s4})

    # ---- the DUPLICATE: a name registered TWICE ---------------------------
    sA = sentinel(CPU, SENT_BYTES)
    sB = sentinel(CPU, SENT_BYTES)
    yield from case("dup", [("dup", sA), ("dup", sB)], "dup", CPU,
                    {FIRST: sA, SECOND: sB})

    # ---- 4: nothing ------------------------------------------------------
    yield from case("none", [], "mine", CPU, {})

    # ---- 0: the alloc has NO name ------------------------------------------
    # The device is "NULL" and NOT the alloc's usual "CPU", and that is the
    # POINT: upstream's unnamed path returns `UOp.new_buffer(b.device, ...)`
    # DIRECTLY, so the answer carries the ALLOC's device, while every other
    # path goes through `UOp.from_buffer(..., HCQ_RUNTIME_DEV.device)`. On the
    # same device the two would be indistinguishable.
    yield from case("unnamed", [], None, NULL, {})

    # ---- 3: the device's `link_buffer` (the NULL device overrides it) -----
    yield from case("hook", [], "mine", NULL, {})

    # ---- THE SHADOW: the registry AND the hook both answer -----------------
    # upstream asks the REGISTRY FIRST, so the registry shadows the device's
    # own hook.
    s5 = sentinel(CPU, SENT_BYTES)
    yield from case("shadow", [("mine", s5)], "mine", NULL, {PLAIN: s5})

    # ---- the WRONG DEVICE: the device-scoped key is a FOLD of the device --
    s6 = sentinel(CPU, SENT_BYTES)
    yield from case("wrongdev", [(to_name(CPU, "mine"), s6)], "mine", CPU0, {DEV: s6})

    # ---- THE REGISTRY ENTRY upstream's `hcq2.py:477` sets ------------------
    #   `Compiled.link_bufs |= {"timeline": lambda b: Device[b.device].timeline}`
    # The alloc is 64 bytes and the timeline is 16, so the SIZE row says which
    # one won. Upstream's entry is a PLAIN name with a CALLABLE value, so the
    # level is 1 and the kind is 1.
    tl = Device[CPU].timeline
    yield from case("timeline", [("timeline", lambda b: Device[b.device].timeline)],
                    "timeline", CPU, {TIMELINE: tl}, n=64)


def compare(path):
    """THE VERDICT: the port's rows against upstream's, over the shared keys."""
    port = {}
    for ln in open(path):
        ln = ln.strip()
        if "=" in ln:
            k, v = ln.split("=", 1)
            port[k] = v
    up = {k: str(v) for k, v in rows()}
    shared = sorted(set(up) & set(port))
    bad = [(k, up[k], port[k]) for k in shared if up[k] != port[k]]
    print(f"shared={len(shared)} agree={len(shared) - len(bad)} differ={len(bad)}")
    for k in shared:
        print(f"{'OK  ' if up[k] == port[k] else 'DIFF'} {k}: cpython={up[k]} port={port[k]}")
    only_up = sorted(set(up) - set(port))
    # the port prints its OWN rows too, so the port-only class is reported by
    # COUNT and by the `bz_`/`tn_` NAMES -- the ones this comparison is about.
    only_port = sorted(set(port) - set(up))
    mine = [k for k in only_port if k.startswith(("bz_", "tn_"))]
    if only_up:
        print(f"CPYTHON-ONLY: {only_up}")
    print(f"PORT-ONLY    : {len(only_port)} row(s), of which the bufferize ones are {mine}")
    return 1 if bad else 0


def main(argv):
    if len(argv) > 1 and argv[0] == "--compare":
        return compare(argv[1])
    for k, v in rows():
        print(f"{k}={v}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
