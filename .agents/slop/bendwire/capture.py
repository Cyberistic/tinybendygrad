"""Capture one DEV=BEND launch for byte-identity diffing: PACKET.in, the executor path, and PACKET.out.

Run under DEV=BEND; also prints the realized tensor's digest so the same run can be checked against
DEV=PYTHON. Nothing outside .agents/slop/bendwire/.

usage: DEV=BEND .venv/bin/python capture.py <op> <n>
       ops: matmul | ones
"""
import hashlib
import json
import pathlib
import subprocess
import sys

import tinygrad.runtime.ops_bend as ob

HERE = pathlib.Path(__file__).resolve().parent
_orig = subprocess.run


def run(cmd, *a, **k):
    r = _orig(cmd, *a, **k)
    d = HERE / "launch"
    d.mkdir(exist_ok=True)
    (d / "EXE").write_text(str(cmd[0]) + "\n")
    (d / "ARGV").write_text(json.dumps([str(x) for x in cmd]) + "\n")
    pkt = pathlib.Path(str(cmd[1]))
    (d / "PACKET.in").write_text(pkt.read_text())
    out = pkt.parent / "PACKET.out"
    if out.exists():
        (d / "PACKET.out").write_text(out.read_text())
    return r


ob.subprocess.run = run

from tinygrad import Tensor  # noqa: E402

OP = sys.argv[1] if len(sys.argv) > 1 else "matmul"
N = int(sys.argv[2]) if len(sys.argv) > 2 else 16

a = Tensor.ones(N, N).contiguous()
if OP == "matmul":
    r = (a @ a).contiguous()
elif OP == "ones":
    r = a
else:
    raise SystemExit(f"unknown op {OP}")
r.realize()
print("digest", hashlib.sha256(r.numpy().tobytes()).hexdigest()[:16])
print("total", float(r.numpy().sum()))
