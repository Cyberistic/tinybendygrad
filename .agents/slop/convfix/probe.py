#!/usr/bin/env python3
"""THE CONV A/B. Does the port's BEND executor compute a convolution correctly?

    .venv/bin/python .agents/slop/convfix/probe.py

ONE MEASUREMENT, THREE ANSWERS, ON THE SAME PACKET AND THE SAME BUFFERS:

  bend   -- the port's executor (`tinybendygrad/runtime/ops_python.bend`, reached
            through `ops_bend.py`'s `BendDevice`), on the captured launch.
  oracle -- UPSTREAM's own `tinygrad/runtime/ops_python.py` `PythonProgram.__call__`
            on the SAME packet and the SAME buffers and the SAME global size.
  python -- CPython's PYTHON device, building ITS OWN inputs.

THE ORACLE BUILDS ITS OWN INPUTS: the e2e gate's own header records that an oracle
which re-uses the subject's buffers compares the wrong answer with itself. So
`python` is a third, independent answer, not a re-run of `oracle`.

THE `local_size` IS CARRIED, NOT ASSUMED. `BendRenderer.has_local = False`, so the
scheduler never splits an axis to LOCAL on the BEND device and every `lidx` reads as
0 -- but the PYTHON renderer has no such rule, so the SAME expression renders a
DIFFERENT packet there, with `lidx` SPECIALs and a real local size. An oracle run
with a guessed `local_size` is not the launch it claims to be. MEASURED: the two
devices render 580 and 581 uops for the same conv.
"""
import ctypes
import pathlib
import pickle
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.helpers import Target, to_mv  # noqa: E402
from tinygrad.runtime import ops_python as OPY  # noqa: E402

import ops_bend as OB  # noqa: E402
from ops_bend import encode  # noqa: E402

sys.modules['tinygrad.runtime.ops_bend'] = OB

OUT = pathlib.Path(__file__).resolve().parent
CAP = []


class Elf:
    """`PythonProgram.__init__` reads `obj.lib` (the pickled uops) and `obj.target`."""

    def __init__(self, uops, target):
        self.lib, self.target = pickle.dumps(uops), target


def _install_hooks():
    """CAPTURE THE BEND LAUNCH, at the boundary where the packet and the buffers
    are both in hand."""
    UOPS = []
    _render = OB.BendRenderer.render
    _call = OB.BendProgram.__call__

    def render(self, uops):
        UOPS.append(list(uops))
        return _render(self, uops)

    def call(self, *bufs, global_size=(1, 1, 1), local_size=(1, 1, 1), vals=(), wait=False, **kw):
        CAP.append({
            'packet': self.src,
            'bufs': [bytes(to_mv(b, nb)) for b, nb in zip(bufs, self.in_bufs)],
            'gsize': tuple(global_size),
            'lsize': tuple(local_size),
            'vals': tuple(vals),
            # THE UOPS THE ORACLE NEEDS. The packet carries the WIRE, not the
            # uops, so the oracle's uops come from the renderer's own list --
            # and `encode(uops)` IS the packet, so the two are the same thing.
            'uops': UOPS[-1] if UOPS else None,
        })
        return _call(self, *bufs, global_size=global_size, local_size=local_size, vals=vals, wait=wait, **kw)

    OB.BendRenderer.render = render
    OB.BendProgram.__call__ = call


_install_hooks()


def callee_args(uops, addrs, words):
    """The launch's positional args in the callee's own order: one per popped
    PARAM -- a buffer address for addrspace g/l, an ALU word for addrspace a.
    `gates/ops_python_exec-gen.py:callee_args` is the tree's own reader."""
    from tinygrad.dtype import AddrSpace
    from tinygrad.uop.ops import Ops
    from ops_bend import buf_extent, is_buf, wire_arg
    out, ai, wi = [], 0, 0
    for u in uops:
        if u.op is not Ops.PARAM:
            continue
        arg = wire_arg(u)
        if is_buf(arg):
            out.append(addrs[ai])
            ai += 1
        elif u.addrspace is AddrSpace.ALU:
            out.append(words[wi])
            wi += 1
    return out


def py_run(uops, bufs, gsize, lsize, words):
    """UPSTREAM'S OWN INTERPRETER, on the packet's own buffers."""
    b2 = [bytearray(b) for b in bufs]
    prog = OPY.PythonProgram.__new__(OPY.PythonProgram)
    prog.__init__(None, Elf(uops, Target(renderer="PYTHON")))
    addrs = [ctypes.addressof(ctypes.c_char.from_buffer(b)) for b in b2]
    prog(*callee_args(uops, addrs, words), global_size=gsize, local_size=lsize)
    return [bytes(b) for b in b2]


def packet_uops(packet_text):
    """The uops of a PACKET.in, for the oracle.

    THE PACKET DOES NOT CARRY THE UOPS -- it carries the wire. So the oracle's
    uops are read back out of the CAPTURE, not out of the packet: the capture
    IS the `UOp` list the renderer was handed, and `encode(uops)` is the packet.
    """
    raise NotImplementedError("the capture keeps the uops; see main()")


def vals(n, seed=1.0):
    return [((i * 37) % 11 - 5) * seed + 0.5 for i in range(n)]


CASES = [
    ("conv1x1x3x3_k1x1x3x3_p0", (1, 1, 3, 3), (1, 1, 3, 3), 0, 1),
    ("conv1x1x4x4_k1x1x3x3_p0", (1, 1, 4, 4), (1, 1, 3, 3), 0, 1),
    ("conv1x1x4x4_k1x1x3x3_p1", (1, 1, 4, 4), (1, 1, 3, 3), 1, 1),
    ("conv1x3x32x32_k8x3x3x3_p1", (1, 3, 32, 32), (8, 3, 3, 3), 1, 1),
]


def maker(xshape, wshape, padding, stride):
    xn = 1
    for d in xshape:
        xn *= d
    wn = 1
    for d in wshape:
        wn *= d
    xv, wv = vals(xn), vals(wn, 0.25)

    def mk():
        x = Tensor(xv, dtype=dtypes.float32).reshape(*xshape).realize()
        w = Tensor(wv, dtype=dtypes.float32).reshape(*wshape).realize()
        return lambda: x.conv2d(w, padding=padding, stride=stride)

    return mk


def brief(v, n=8):
    flat = []

    def walk(x):
        if isinstance(x, list):
            for y in x:
                walk(y)
        else:
            flat.append(x)

    walk(v)
    return f"n={len(flat)} head={flat[:n]} tail={flat[-n:] if len(flat) > n else []}"


def ab_one(cap, d, k):
    """THE A/B ON ONE CAPTURED LAUNCH: the port's executor and upstream's own
    interpreter, on the SAME packet, the SAME buffers, the SAME grid.

    THE PORT'S VERDICT IS ITS OWN: the executor is run on the PACKET.in, and its
    exit status and stderr are the verdict. THE ORACLE'S VERDICT IS UPSTREAM'S:
    `PythonProgram.__call__` raises or does not.
    """
    import struct
    import subprocess
    pk = d / f"PACKET-{k}.in"
    exe = OB.executor()
    r = subprocess.run([str(exe), str(pk), *[str(v) for v in cap['gsize']]],
                       capture_output=True, text=True)
    port = (f"rc={r.returncode}" + (f" stderr={r.stderr.strip()[:160]}" if r.returncode else ""))
    try:
        out = py_run(cap['uops'], cap['bufs'], cap['gsize'], cap['lsize'], cap['vals'])
        oracle = f"ran, {len(out)} buffers"
        same = None
        po = d / "PACKET.out"
        if po.exists() and r.returncode == 0:
            plines = po.read_text().splitlines()
            same = []
            for i in range(min(len(plines), len(out))):
                ph, oh = plines[i].split()[1], out[i].hex()
                if ph == oh:
                    same.append(f"b{i}: SAME")
                    continue
                # THE ELEMENTS, so a difference is a measurement and not a label.
                pb, ob = bytes.fromhex(ph), bytes.fromhex(oh)
                nf = len(pb) // 4
                pf = struct.unpack(f"<{nf}f", pb[:nf * 4])
                of = struct.unpack(f"<{nf}f", ob[:nf * 4])
                diff = [j for j in range(nf) if pf[j] != of[j]]
                same.append(f"b{i}: DIFFER ({len(diff)}/{nf} elements, first {diff[:8]}, "
                            f"port[0:4]={list(pf[:4])} oracle[0:4]={list(of[:4])})")
    except Exception as e:  # noqa: BLE001
        oracle = f"REFUSED {type(e).__name__}: {str(e)[:160]}"
        same = None
    return port, oracle, same


def main():
    exe = OB.executor()
    print(f"# executor: {exe}")
    ok = bad = 0
    for name, xs, ws, pad, stride in CASES:
        mk = maker(xs, ws, pad, stride)
        CAP.clear()
        bend_err = None
        try:
            with Context(DEV='BEND'):
                got = mk()().tolist()
        except Exception as e:  # noqa: BLE001
            got = None
            bend_err = f"{type(e).__name__}: {str(e)[:300]}"
        # THE THIRD ANSWER: CPython's PYTHON device, building ITS OWN inputs.
        try:
            with Context(DEV='PYTHON'):
                want = mk()().tolist()
        except Exception as e:  # noqa: BLE001
            want = None
            print(f"== {name}: the PYTHON oracle FAILED {type(e).__name__}: {str(e)[:200]}")
            bad += 1
            continue
        print(f"== {name}")
        print(f"#   python: {brief(want)}")
        if bend_err is not None:
            print(f"#   bend:   REFUSED/FAILED -- {bend_err.splitlines()[0][:200]}")
        else:
            print(f"#   bend:   {brief(got)}")
        d = OUT / "packets" / name
        d.mkdir(parents=True, exist_ok=True)
        for k, cap in enumerate(CAP):
            with (d / f"PACKET-{k}.in").open("w") as fh:
                fh.write(cap['packet'])
                for b in cap['bufs']:
                    fh.write(f"{len(b)} {b.hex()}\n")
            (d / f"packet-{k}.rows").write_text(cap['packet'])
            print(f"#   launch {k}: gsize={cap['gsize']} lsize={cap['lsize']} "
                  f"nbuf={len(cap['bufs'])} -> {d}/PACKET-{k}.in")
            port, oracle, same = ab_one(cap, d, k)
            print(f"#     port:   {port}")
            print(f"#     oracle: {oracle}")
            if same is not None:
                print(f"#     bytes:  {' '.join(same)}")
        if bend_err is None and repr(got) == repr(want):
            ok += 1
            print("#   VERDICT: MATCH")
        else:
            bad += 1
            print("#   VERDICT: MISMATCH-or-REFUSED")
    print(f"# {ok} match, {bad} mismatch-or-refused")
    return 0 if bad == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
