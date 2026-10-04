#!/usr/bin/env python3
"""cstyle-numbers.py -- CPython's OWN numbers for the program `cstyle.bend`'s emitted
kernel computes, read from `tinygrad/` and nowhere else.

WHY HEX AND NOT `printf("%g")`. A decimal print rounds, and two rounded strings can agree
while the bits differ. The emitted kernel stores four `float`s, so the comparison is over
the raw 16 bytes, `struct.pack('<4f', ...).hex()` and agreement is bit-exact.

THE INPUT IS A HEX STRING, because the host driver reads the same 16 bytes off disk and the
two must not be two transcriptions of one another.

THREE READINGS, ON PURPOSE, and the reason is the sharpest trap in the brief: an oracle
that agrees with the port because both made the SAME mistake is not corroboration, it is
one mistake copied. So:

  CPU    tinygrad's real CPU backend -- ClangRenderer emits C, ClangCompiler compiles it, it
         is mmap'd and CDLL'd and called (tinygrad/runtime/ops_cpu.py:29-72). This is the
         reading that goes through cstyle.py, upstream's OWN cstyle.
  PYTHON tinygrad's reference device: no compiler anywhere in the path. NOT `NULL` -- on
         this machine `DEV=NULL` opens (it is an amdgpu device, ops_null.py) and returns
         `[0.0, 0.0, 0.0, 0.0]` for this program with no error at all. A device that cannot
         run reads as ZERO, so had the emitted kernel also produced zeros this would have
         been reported as agreement.
  f64    plain Python floats, packed as float64 (`<4d`) so they are NOT rounded onto the f32
         grid -- otherwise this third reading would agree with CPU BY CONSTRUCTION and be
         worthless.

`--all` runs CPU and PYTHON in SEPARATE PROCESSES with their own DEV: a device is created
once per process (device.py:33-40) and re-reading a second `.to()` of the same name in one
process reads the FIRST device's buffer.

  usage: cstyle-numbers.py [--in <f32-hex>] [--all]
"""
import argparse, os, struct, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
# HERE = <repo>/.agents/slop/cstyle-live, so THREE dirnames up is the repo root, not two.
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
sys.path.insert(0, REPO)

IN = [1.0, 0.1, -2.5, 3.75]
"""The DEFAULT fixture. DISTINCT, and one of them (0.1) is not representable in float32.
Four equal values would hide a lane-ordering bug (trap 2: a row whose elements are all equal
cannot fail on an ordering bug); here out[i] != out[j] for every i != j, so reversing the
four lanes changes the hex string, and the hex string is the whole comparison."""


def readings(device):
  from tinygrad import Tensor
  # `Device[name]` returns an INSTANCE (Device.__getitem__ -> __get_canonicalized_item,
  # device.py:29-40) and `Tensor.to()` wants the NAME -- handing it the object raises
  # `'CPUDevice' object has no attribute 'split'` from Device._canonicalize (device.py:26),
  # and `str()` of the instance is not the name either. So the name goes straight through.
  a = Tensor(IN).contiguous().to(device)
  out = (a + 1.0).contiguous().to(device)
  out.realize()
  # `realize()` returns None (it is a side effect), so the tensor is kept and read after.
  return out.numpy().tolist()


def in_subprocess(device, argv):
  env = dict(os.environ, DEV=device, PYTHONPATH=REPO)
  r = subprocess.run([sys.executable, __file__, *argv], env=env, capture_output=True, text=True)
  if r.returncode:
    raise SystemExit(f"cstyle-numbers: DEV={device} failed\n{r.stderr}")
  return r.stdout.strip()


def unpack_f32(h):
  b = bytes.fromhex(h)
  assert len(b) == 16, f"expected 16 bytes of float32, got {len(b)}"
  return list(struct.unpack("<4f", b))


if __name__ == "__main__":
  ap = argparse.ArgumentParser()
  ap.add_argument("--in", dest="hex", default=None, help="16 bytes of float32, as hex")
  ap.add_argument("--all", action="store_true")
  a = ap.parse_args()
  if a.hex:
    IN = unpack_f32(a.hex)
  passthru = ["--in", a.hex] if a.hex else []
  if not a.all:
    print(struct.pack("<4f", *readings(os.environ.get("DEV", "CPU"))).hex())
  else:
    for d in ("CPU", "PYTHON"):
      h = in_subprocess(d, passthru)
      print(f"{d:<6} {h}  {unpack_f32(h)}")
    h = struct.pack("<4d", *[x + 1.0 for x in IN]).hex()
    print(f"{'f64':<6} {h}  {[x + 1.0 for x in IN]}")