#!/usr/bin/env python3
"""Oracle for autogen.py: run the REAL generator on a real header and capture
every internal it computes. Nothing here is transcribed.

Usage: ag-oracle.py <header.c> > ag-oracle.txt
"""
import sys, os, ctypes, pathlib
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
os.environ.setdefault("CLANG", "/opt/homebrew/opt/llvm@20/lib/libclang.dylib")

import tinygrad.runtime.autogen.libclang as clang

# ---- the generator's own tables, read from the module under test -------------
import importlib.util
spec = importlib.util.spec_from_file_location("ag",
    "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/runtime/support/autogen.py")
ag = importlib.util.module_from_spec(spec)
# autogen.py imports `from tinygrad.helpers import unwrap` and libclang; both fine.
spec.loader.exec_module(ag)

print("### TMAP (CXType kind -> ctypes name)")
for k, v in sorted(ag.tmap.items()):
    print(f"tmap {int(k)} = {v}")

print("### UINTS / INTS (CXType kinds)")
print("uints " + " ".join(str(int(k)) for k in ag.uints))
print("ints " + " ".join(str(int(k)) for k in ag.ints))
print("fps " + " ".join(str(int(k)) for k in ag.fps))
print("specs " + " ".join(str(int(k)) for k in ag.specs))

print("### ARC_FAMILIES")
print("arc " + " ".join(ag.arc_families))

print("### BASE_RULES")
for i, (pat, rep) in enumerate(ag.base_rules):
    print(f"rule {i} : {pat} => {rep}")

# ---- typehint over every CXType kind libclang knows -------------------------
print("### TYPEHINT over every CXType_ kind")
import re
src = open(clang.__file__).read()
kinds = sorted(int(m.group(2)) for m in re.finditer(r"^CXType_(\w+) = (\d+)$", src, re.M))
names = {int(m.group(2)): m.group(1) for m in re.finditer(r"^CXType_(\w+) = (\d+)$", src, re.M)}
print("cxkind_count " + str(len(kinds)))

# ---- the real end-to-end run ----------------------------------------------
print("### GEN output")
hdr = sys.argv[1]
out = ag.gen("agtest", [hdr], dll="'c'")
for line in out.split("\n"):
    print("gen|" + line)
