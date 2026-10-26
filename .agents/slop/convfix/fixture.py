#!/usr/bin/env python3
"""THE CONV FIXTURE, IN THE TREE'S OWN `PACKET.in` SPELLING.

    .venv/bin/python .agents/slop/convfix/fixture.py

IT WRITES `.agents/slop/convfix/fixture-conv.rows` -- ONE record, in the exact
spelling `gates/ops_python_exec-fixtures.rows` uses:

    @ <name> <gx> <gy> <gz> <vals...>
    bendexec1 <nuops> <nbuffers>
    <idx>: <OP> <dtype> <arg> <src1> <src2> ...
    <nbytes> <hex-bytes>

**THE POPULATION FILE IS NOT MINE AND I DID NOT EDIT IT.** `gates/ops_python_exec-
fixtures.rows` belongs to `gates/ops_python_exec-gen.py`, and the gate's
`population_hold` compares the file's NAMES against the generator's re-harvest,
so a record in the file that the generator does not produce is a RED run. **⇒
WIRING THIS FIXTURE INTAKES TWO EDITS, BOTH IN THE OTHER INSTRUMENT'S FILES:**
the seed in `gates/ops_python_exec-gen.py`'s `SEEDS` and the record in
`gates/ops_python_exec-fixtures.rows`. **THIS UNIT DID NOT MAKE EITHER.**

THE SHAPE IS CHOSEN, NOT TYPED: `.agents/slop/convfix/scan.py` renders eight
conv shapes and reports which kernel carries a LOCAL scratch `BUFFER`, and the
scratch is what the port's byte-shift defect lived in. `(1,3,8,8)x(4,3,3,3)`
padding=1 is the SMALLEST conv whose kernel has one -- **140 uops and 2,224
bytes of buffers, against the 580 uops and 45,920 bytes of the port's own conv
shape.** The two convs without a scratch (`(1,1,3,3)` and `(1,1,4,4)`) MATCHED
BEFORE THE FIX, so they pin nothing about it.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from tinygrad import Tensor, Context  # noqa: E402
from tinygrad.dtype import dtypes  # noqa: E402
from tinygrad.helpers import to_mv  # noqa: E402

import ops_bend as OB  # noqa: E402

sys.modules['tinygrad.runtime.ops_bend'] = OB

OUT = pathlib.Path(__file__).resolve().parent
CAP = []

_orig_render = OB.BendRenderer.render
_orig_call = OB.BendProgram.__call__


def render(self, uops):
    CAP.append(list(uops))
    return _orig_render(self, uops)


def call(self, *bufs, global_size=(1, 1, 1), local_size=(1, 1, 1), vals=(), wait=False, **kw):
    CAP.append({'packet': self.src,
                'bufs': [bytes(to_mv(b, nb)) for b, nb in zip(bufs, self.in_bufs)],
                'gsize': tuple(global_size), 'lsize': tuple(local_size)})
    return _orig_call(self, *bufs, global_size=global_size, local_size=local_size, vals=vals, wait=wait, **kw)


OB.BendRenderer.render = render
OB.BendProgram.__call__ = call

XSHAPE, WSHAPE, PAD = (1, 3, 8, 8), (4, 3, 3, 3), 1


def vals(n, seed=1.0):
    return [((i * 37) % 11 - 5) * seed + 0.5 for i in range(n)]


def main():
    xn = 1
    for d in XSHAPE:
        xn *= d
    wn = 1
    for d in WSHAPE:
        wn *= d
    with Context(DEV='BEND'):
        x = Tensor(vals(xn), dtype=dtypes.float32).reshape(*XSHAPE).realize()
        w = Tensor(vals(wn, 0.25), dtype=dtypes.float32).reshape(*WSHAPE).realize()
        x.conv2d(w, padding=PAD, stride=1).realize()
    cap = CAP[-1]
    name = "f32.conv2d.0"
    rec = [f"@ {name} {' '.join(str(v) for v in cap['gsize'])}", cap['packet'].rstrip('\n')]
    for b in cap['bufs']:
        rec.append(f"{len(b)} {b.hex()}")
    text = "\n".join(rec) + "\n"
    (OUT / "fixture-conv.rows").write_text(text)
    (OUT / "fixture-conv.PACKET.in").write_text(
        cap['packet'] + "".join(f"{len(b)} {b.hex()}\n" for b in cap['bufs']))
    print(f"# wrote {OUT/'fixture-conv.rows'}: {len(text)} bytes, "
          f"{len(cap['packet'].splitlines())} packet lines, {len(cap['bufs'])} buffers, "
          f"grid={cap['gsize']}")
    print(f"# the scratch BUFFER is present: "
          f"{any(' BUFFER ' in l for l in cap['packet'].splitlines())}")


if __name__ == '__main__':
    sys.exit(main())
