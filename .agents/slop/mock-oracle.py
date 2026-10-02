#!/usr/bin/env python3
"""MOCK oracle: run programs on tinygrad's hardware-free device emulators.

`DEV=MOCK` is NOT a device. `DEV` parses as `<iface>+<dev>:<renderer>:<arch>`
(tinygrad/helpers.py:206 `Target.parse`), so MOCK is an *interface* and needs a
real device after the `+`. There is no `tinygrad/runtime/ops_mock.py`, upstream or
ever -- `Device.get_class` (tinygrad/device.py:37) imports `ops_{target}` with no
validation, so an unknown target surfaces as a ModuleNotFoundError naming a module
nobody wrote.

This is the real-execution oracle the brief asked for: it drives the mockgpu
emulators in test/mockgpu/ and prints `name=value` lines a Bend port can gate on.

Usage:  DEV=MOCK+AMD python3 .agents/slop/mock-oracle.py
"""
import sys

from tinygrad import Tensor

FIXTURES = {}


def fixture(fn):
  FIXTURES[fn.__name__[2:]] = fn
  return fn


@fixture
def k_add():
  return (Tensor([1.0, 2.0, 3.0]) + Tensor([10.0, 20.0, 30.0])).tolist()


@fixture
def k_mul():
  return (Tensor([1.5, 2.5, 3.5]) * Tensor([2.0, 4.0, 8.0])).tolist()


@fixture
def k_relu():
  return Tensor([-1.0, 0.0, 2.5]).relu().tolist()


@fixture
def k_sum():
  return Tensor([1.0, 2.0, 3.0, 4.0]).sum().item()


@fixture
def k_max():
  return Tensor([1.0, 9.0, 3.0, 4.0]).max().item()


@fixture
def k_rowsum():
  return Tensor([[1.0, 2.0], [3.0, 4.0]]).sum(axis=1).tolist()


@fixture
def k_axis0():
  return Tensor([[1.0, 2.0], [3.0, 4.0]]).sum(axis=0).tolist()


@fixture
def k_matmul():
  a = Tensor([[1.0, 2.0], [3.0, 4.0]])
  return (a @ a).tolist()


@fixture
def k_reshape():
  return Tensor([1.0, 2.0, 3.0, 4.0]).reshape(2, 2).tolist()


@fixture
def k_permute():
  return Tensor([[1.0, 2.0], [3.0, 4.0]]).permute(1, 0).tolist()


@fixture
def k_flip():
  return Tensor([[1.0, 2.0], [3.0, 4.0]]).flip(0).tolist()


@fixture
def k_shrink():
  return Tensor([[1.0, 2.0], [3.0, 4.0]]).shrink(((0, 0), (0, 1))).tolist()


@fixture
def k_cast():
  return Tensor([1.7, 2.2, 3.9]).cast("float16").cast("float32").tolist()


@fixture
def k_where():
  a, b = Tensor([1.0, 5.0, 3.0]), Tensor([4.0, 2.0, 6.0])
  return Tensor.where(Tensor([True, False, True]), a, b).tolist()


@fixture
def k_mulacc():
  a = Tensor([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])
  return (a * a).sum(axis=1).tolist()


@fixture
def k_gemm2():
  a = Tensor([[1.0, 2.0], [3.0, 4.0], [5.0, 6.0]])
  return (a @ Tensor([[1.0, 0.0], [0.0, 1.0]])).tolist()


@fixture
def k_repeat():
  return Tensor([1.0, 2.0]).repeat(2).tolist()


@fixture
def k_cumsum():
  return Tensor([[1.0, 2.0], [3.0, 4.0]]).cumsum(axis=1).tolist()


def main() -> int:
  from tinygrad.device import DEV
  print(f"# oracle DEV={DEV!r}", file=sys.stderr)
  for name, fn in FIXTURES.items():
    try:
      print(f"{name}={fn()}")
    except Exception as e:
      print(f"{name}=ERROR:{type(e).__name__}:{e}")
  print(f"# rows={len(FIXTURES)}", file=sys.stderr)
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
