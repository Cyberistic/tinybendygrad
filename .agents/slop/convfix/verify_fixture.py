#!/usr/bin/env python3
"""THE FIXTURE, ON BOTH EXECUTORS AND ON UPSTREAM.

    .venv/bin/python .agents/slop/convfix/verify_fixture.py <before-exe> <after-exe>

THE FIXTURE IS RUN THREE TIMES: ON THE PRE-FIX EXECUTOR, ON THE POST-FIX
EXECUTOR, AND ON UPSTREAM'S OWN INTERPRETER (`tinygrad/runtime/ops_python.py`),
ON THE SAME PACKET AND THE SAME BUFFERS.

**THE PRE-FIX EXECUTOR IS THE WITNESS THAT THE FIXTURE MEASURES SOMETHING.**
A fixture that both executors pass pins nothing.
"""
import ctypes
import pathlib
import pickle
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad.helpers import Target  # noqa: E402
from tinygrad.runtime import ops_python as OPY  # noqa: E402

HERE = pathlib.Path(__file__).resolve().parent


class Elf:
    def __init__(self, uops, target):
        self.lib, self.target = pickle.dumps(uops), target


def run_exe(exe, pkt, gsize):
    d = pkt.parent / f"run-{pkt.stem}-{exe.stem}"
    d.mkdir(parents=True, exist_ok=True)
    (d / "PACKET.in").write_text(pkt.read_text())
    r = subprocess.run([str(exe), str(d / "PACKET.in"), *[str(v) for v in gsize]],
                       capture_output=True, text=True)
    if r.returncode != 0:
        return None, f"rc={r.returncode} {r.stderr.strip()[:110]}"
    out = (d / "PACKET.out").read_text().splitlines()
    return [l.split()[1] for l in out], "rc=0"


def uops_of_the_conv():
    """THE UOPS THE PACKET WAS ENCODED FROM, re-derived from the tree's own
    renderer on the BEND device -- the packet carries the WIRE, not the uops.

    THE RENDER IS HOOKED AND THE LAUNCH IS ABORTED, so this costs the scheduler
    and not an executor run.
    """
    from tinygrad import Tensor, Context
    from tinygrad.dtype import dtypes
    import ops_bend as OB
    sys.modules['tinygrad.runtime.ops_bend'] = OB
    got = []
    orig = OB.BendRenderer.render

    def render(self, uops):
        got.append(list(uops))
        raise RuntimeError("SCAN")

    OB.BendRenderer.render = render
    xn, wn = 1 * 3 * 8 * 8, 4 * 3 * 3 * 3
    v = lambda n, s=1.0: [((i * 37) % 11 - 5) * s + 0.5 for i in range(n)]
    try:
        with Context(DEV='BEND'):
            x = Tensor(v(xn), dtype=dtypes.float32).reshape(1, 3, 8, 8).realize()
            w = Tensor(v(wn, 0.25), dtype=dtypes.float32).reshape(4, 3, 3, 3).realize()
            x.conv2d(w, padding=1, stride=1).realize()
    except RuntimeError as e:
        if "SCAN" not in str(e):
            raise
    return got[-1]


def main():
    before, after = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    pkt = HERE / "fixture-conv.PACKET.in"
    lines = pkt.read_text().splitlines()
    n, nb = int(lines[0].split()[1]), int(lines[0].split()[2])
    bufs = [bytearray(bytes.fromhex(l.split()[1])) for l in lines[1 + n:1 + n + nb]]

    # UPSTREAM'S ANSWER, on the same packet and the same buffers.
    uops = uops_of_the_conv()
    b2 = [bytearray(b) for b in bufs]
    prog = OPY.PythonProgram.__new__(OPY.PythonProgram)
    prog.__init__(None, Elf(uops, Target(renderer="PYTHON")))
    from tinygrad.dtype import AddrSpace
    from tinygrad.uop.ops import Ops
    from ops_bend import buf_extent, is_buf, wire_arg
    plan = []
    for u in uops:
        if u.op is not Ops.PARAM:
            continue
        arg = wire_arg(u)
        if is_buf(arg):
            plan.append(("buf", buf_extent(arg)))
        elif u.addrspace is AddrSpace.ALU:
            plan.append(("word", 0))
    addrs = [ctypes.addressof(ctypes.c_char.from_buffer(b)) for b in b2]
    args, ai, wi = [], 0, 0
    for kind, _e in plan:
        if kind == "buf":
            args.append(addrs[ai])
            ai += 1
        else:
            args.append(0)
            wi += 1
    prog(*args, global_size=(1, 1, 1), local_size=(1, 1, 1))
    oracle = [bytes(b).hex() for b in b2]

    for label, exe in (("BEFORE", before), ("AFTER", after)):
        rows, verdict = run_exe(exe, pkt, (1, 1, 1))
        if rows is None:
            print(f"{label}: {verdict}")
            continue
        same = [f"b{i}:{'SAME' if rows[i] == oracle[i] else 'DIFFER'}" for i in range(min(len(rows), len(oracle)))]
        print(f"{label}: {verdict}  vs upstream: {' '.join(same)}")


if __name__ == '__main__':
    sys.exit(main())
