#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/device.bend.

Calls, and only calls:
  * `Device._canonicalize`           device.py:26
  * `ALL_DEVICES`                    device.py:20
  * `is_disk_device`                 device.py:69-70  <- the function, not a copy of it
  * `Device[ix]`                     device.py:29-32  <- the assert at :31, not a copy
  * `Context(ALLOW_DEVICE_USAGE=..)` helpers.py:170-176, the knob device.py:31 reads

Registry lengths that scan the filesystem (`stem_len`, `reg_len`) are omitted: they
count files in this checkout, not a function's answer, and a second checkout
disagrees.

MEASURED 2026-10-03: 18 shared of the port's 105, and `allow_lower` DISAGREES.
CPython says 1, the port says 0, and CPython is right:

    device.py:29   def __getitem__(self, ix:str) -> Compiled:
    device.py:30     ix = self.canonicalize(ix)          # canonicalizes FIRST
    device.py:31     assert ALLOW_DEVICE_USAGE or ix.split(":")[0] in [...]

`_canonicalize` upper-cases the stem (device.py:26), so by the time line 31 reads
`ix` the input is already `PYTHON:1` and the assert PASSES. Called under
`Context(ALLOW_DEVICE_USAGE=0)`: `Device['PYTHON:1']` -> 1, `Device['python:1']`
-> 1, `Device['METAL']` -> AssertionError -> 0. Measured at pin 6c3d401cf324, at
HEAD and at upstream/master: the ordering is not rebase drift, it is a long-standing
port bug.

device.bend:329-341 asserts the opposite twice -- "`__getitem__` asserts before it
canonicalizes" and "compares the head exactly as it arrived" -- while citing :30 as
the canonicalize and :31 as the assert, which is the order it then denies. Its
`allowed` therefore omits line 30. Reported, NOT fixed, and it is why device.bend
is left UNWIRED: a lane that disagrees on every run trains the reader to read
BROKEN as normal, which is the exact failure BASE_ORACLES warns about for elf.bend.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from tinygrad.device import Device, ALL_DEVICES, is_disk_device
from tinygrad.helpers import Context


def row(name, value):
    print(f"{name}={value}")


def canon(s):
    return Device._canonicalize(s)


def allowed(usage, ix):
    """device.py:29-31, CALLED. `Context` (helpers.py:170) writes
    `ContextVar._cache[key].value` and `ALLOW_DEVICE_USAGE` is a ContextVar whose
    `__bool__` is `bool(self.value)` (helpers.py:192), so this sets the very object
    device.py:31 tests. Allowed is the assert NOT firing; a name that passes goes
    on to open a device, which is why both allowed corners use PYTHON."""
    with Context(ALLOW_DEVICE_USAGE=int(usage)):
        try:
            Device[ix]
        except AssertionError:
            return 0
        return 1


def is_disk(ixs):
    """device.py:69-70, CALLED. It takes `str | tuple`, so a one-element port list
    is a one-tuple and the port's `Nil{}` is `()`."""
    return is_disk_device(tuple(ixs))


def main():
    row("all_len", len(ALL_DEVICES))
    row("canon_cpu0", canon("cpu:0"))
    row("canon_cpu00", canon("cpu:0:0"))
    row("canon_wg2", canon("WEBGPU:2"))
    row("canon_nv00", canon("nv:00"))
    row("canon_x00", canon("x:0:0"))
    row("canon_a", canon("a:b"))
    row("canon_dev", canon("cpu:0"))
    row("multi", ",".join(canon(s) for s in ("cpu:0", "CPU", "cpu:1")))
    # Opening cpu:0, CPU and cpu is one canonical device. cpu and cpu:1 are two.
    row("open_one", len({canon(s) for s in ("cpu:0", "CPU", "cpu")}))
    row("open_two", len({canon(s) for s in ("cpu", "cpu:1")}))
    row("allow_py", allowed(False, "PYTHON:1"))
    row("allow_lower", allowed(False, "python:1"))
    row("allow_metal", allowed(False, "METAL"))
    row("allow_on", allowed(True, "METAL"))
    # device.bend reads `device_usage` -- `__getitem__`'s TWO lines -- so these five
    # go through the same `allowed`, and they are here to cover the two allow-list
    # branches `tag_of` never had a fixture for. Measured by CALLING, 2026-10-03.
    row("allow_cpu", allowed(False, "CPU:1"))
    row("allow_disk", allowed(False, "disk:1"))
    row("allow_npy", allowed(False, "npy:1"))
    row("allow_cpu_l", allowed(False, "cpu:1"))
    row("allow_mixed", allowed(False, "PyThOn:0"))
    row("disk_one", int(is_disk(["CPU:1"])))
    row("disk_two", int(is_disk(["CPU:1", "disk:0"])))
    row("disk_no", int(is_disk([])))


if __name__ == "__main__":
    main()