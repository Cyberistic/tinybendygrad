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
# MEASURED 2026-10-17, AND THIS BLOCK WAS DEAD (doctrine 2's fifth verdict: it ran and
# emitted a value, so nothing looked red). It read the population with
# `re.finditer(r"^CXType_(\w+) = (\d+)$", <libclang.py>, re.M)`, and `libclang.py` does not
# spell its enums that way: it generates
# `enum_CXTypeKind: dict[int, str] = {(CXType_Invalid:=0): 'CXType_Invalid', ...}`.
# That pattern matched **0 of the 256 `CXType_` occurrences in the file**, so
# `cxkind_count` printed `0` -- the length of an empty list, reported as a census of
# libclang. `names` was built from the same 0-match scan and never read.
# The population is read now from the generator's OWN declarations, BY ATTRIBUTE, which is
# the shape doctrine 1 asks for (`differ.declared()`): `clang.enum_CXTypeKind` is libclang's
# own enumeration, already imported. `cxkind_names` is printed beside it because libclang
# ALIASES -- 128 `CXType_*` names over 122 distinct kinds, MEASURED -- and the same trap
# is written down at `autogen.bend:1195-1200` ("Keyed on the integer, 78 constants collapse
# onto 58 keys and the diff passes over the wrong pairs"), so both numbers are here rather
# than one.
# `typehint` itself is NOT printed: it takes a `clang.CXType`, not a kind, and its
# fall-through arm calls `tname` -> `clang_getTypeDeclaration` on the value it is given.
# That is WALL 1 and it is why the census is a COUNT and not a table.
print("### TYPEHINT over every CXType_ kind")
print(f"cxkind_count {len(clang.enum_CXTypeKind)} cxkind_names {sum(k.startswith('CXType_') for k in vars(clang))}")

# ---- the real end-to-end run ----------------------------------------------
print("### GEN output")
hdr = sys.argv[1]
out = ag.gen("agtest", [hdr], dll="'c'")
for line in out.split("\n"):
    print("gen|" + line)
