#!/usr/bin/env python3
"""Print every CXType_/CXCursor_/CXToken_/CXLinkage_ constant, resolved by
CALLING libclang, not by reading its source."""
import sys, os, re
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
os.environ.setdefault("CLANG", "/opt/homebrew/opt/llvm@20/lib/libclang.dylib")
import tinygrad.runtime.autogen.libclang as c

src = open(c.__file__).read()
out = []
for m in re.finditer(r"^(CX\w+)\s*=\s*(\d+)\s*$", src, re.M):
  out.append((m.group(1), int(m.group(2))))
seen = {}
for n, v in out: seen[n] = v
for n in sorted(seen): print(f"{n} {seen[n]}")
