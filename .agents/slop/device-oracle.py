#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/device.bend.

Calls Device._canonicalize (device.py:26), ALL_DEVICES (device.py:20), and the
allow/disk predicates at device.py:31 and device.py:70. Registry lengths that
scan the filesystem (`stem_len`, `reg_len`) are omitted: they count files in
this checkout, not a function's answer, and a second checkout disagrees.
"""
from tinygrad.device import Device, ALL_DEVICES


def row(name, value):
    print(f"{name}={value}")


def canon(s):
    return Device._canonicalize(s)


def allowed(usage, ix):
    # device.py:31. The stem compare is case-sensitive; `python:1` is not PYTHON.
    return usage or ix.split(":")[0] in ("DISK", "NPY", "PYTHON")


def is_disk(ixs):
    # device.py:70.
    return any(d.split(":", 1)[0].upper() == "DISK" for d in ixs)


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
    row("allow_py", int(allowed(False, "PYTHON:1")))
    row("allow_lower", int(allowed(False, "python:1")))
    row("allow_metal", int(allowed(False, "METAL")))
    row("allow_on", int(allowed(True, "METAL")))
    row("disk_one", int(is_disk(["CPU:1"])))
    row("disk_two", int(is_disk(["CPU:1", "disk:0"])))
    row("disk_no", int(is_disk([])))


if __name__ == "__main__":
    main()
