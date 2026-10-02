#!/usr/bin/env python3
"""Oracle for the ABI ladder: resolve EVERY constant by CALLING libclang
through tinygrad.runtime.autogen.libclang, not by reading a header and not by
memory. `ops_nv`'s audit found 33 of 219 wrong; this is 74 constants and the
whole point is that none of them is typed."""
import os, sys
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
os.environ.setdefault("CLANG", "/opt/homebrew/opt/llvm@20/lib/libclang.dylib")
import tinygrad.runtime.autogen.libclang as c
import re
NAMES = re.findall(r'abi_kd\(\s*[a-z0-9_]+\(\),\s*"(CX\w+)"',
         open("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinybendygrad/runtime/support/autogen.bend").read())
for n in NAMES:
    print(f"A {int(getattr(c, n))}={n}")
