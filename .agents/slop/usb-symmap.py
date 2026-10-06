#!/usr/bin/env python3
"""CHECK THAT THE TRACE'S `K_*` -> `SYMS()` MAPPING IS INJECTIVE.

The `K_*` ladder and `SYMS()` are both port-invented -- no line of `usb.py` says
"K_INIT is 0" -- so the constant sweep cannot compare them to a header. What IS a
real property, and what a transposed ladder would break, is that the mapping is a
BIJECTION onto the seam's symbols: 24 kinds, 24 names, no repeats and no
extras. And every name must be a REAL libusb export.

This is the check that would catch `K_SET_CONFIG` and `K_CLAIM_IFACE` swapped.
"""
import io
import os
import re
import sys

sys.path.insert(0, os.getcwd())
from tinygrad.runtime.autogen import libusb  # noqa: E402

P = "tinybendygrad/runtime/support/usb.bend"
src = io.open(P).read()

kinds = dict((m.group(1), int(m.group(2)))
            for m in re.finditer(r"^def (K_[A-Z_]+)\(\) -> U32: (\d+)$", src, re.M))
i = src.index("def SYMS() -> List<&2, String>:")
j = src.index("libusb_strerror\"]", i) + len('libusb_strerror"]')
syms = re.findall(r'"([^"]+)"', src[i:j])

# `memcpy` is libc, not libusb; it is the one name with no `libusb.` prefix.
LIBC = {"memcpy"}

print(f"kinds={len(kinds)} syms={len(syms)}")
bad = 0
if len(kinds) != len(syms):
    print(f"  WRONG: {len(kinds)} kinds and {len(syms)} symbols -- not injective")
    bad += 1
inv = dict((v, k) for k, v in kinds.items())
if len(inv) != len(kinds):
    dup = sorted(v for v in kinds if list(kinds.values()).count(v) > 1)
    print(f"  WRONG: two K_* share a value: {[k for k in kinds if kinds[k] in dup]}")
    bad += 1
for i, sy in enumerate(syms):
    if i not in inv:
        print(f"  WRONG: no K_* for SYMS()[{i}] = {sy}")
        bad += 1
    elif sy in LIBC:
        continue
    elif not hasattr(libusb, sy):
        print(f"  WRONG: SYMS()[{i}] = {sy} is not a libusb export")
        bad += 1
for k, v in sorted(kinds.items(), key=lambda kv: kv[1]):
    print(f"  {v:2d} {k:18s} -> {syms[v] if v < len(syms) else 'MISSING'}")
print(f"injective={bad == 0} all_symbols_real={bad == 0}")
sys.exit(1 if bad else 0)