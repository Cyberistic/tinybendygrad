#!/usr/bin/env python3
"""Diff the ABI ladder row against the libclang oracle.

KEYED BY NAME, not by value: libclang ALIASES several constants to the same
integer (CXCursor_FirstRef and CXCursor_ObjCSuperClassRef are both 40;
CXCursor_FirstAttr and CXCursor_UnexposedAttr are both 400). Keying on the
number collapses 78 constants onto 58 keys and then reports a silent pass over
the wrong pairs. This is the same harness trap as keying a `tmap` row on its
first token, in a second disguise."""
import sys
bend = [l for l in open(sys.argv[1]).read().split("\n") if l.startswith("abi ")]
orc  = [l[2:].strip() for l in open(sys.argv[2]).read().split("\n") if l.startswith("A ")]
if len(bend) != 1:
    print(f"expected ONE abi row, got {len(bend)}"); sys.exit(1)
def pairs_b(s):   # "2=CXType_Void 3=CXType_Bool ..." -> {name: kind}
    return {p.split("=", 1)[1]: p.split("=", 1)[0] for p in s.split()}
def pairs_o(s):   # oracle lines are "kind=name"
    return {p.split("=", 1)[1]: p.split("=", 1)[0] for p in s}
b, o = pairs_b(bend[0][4:]), pairs_o(orc)
bad = 0
for k in sorted(set(b) | set(o)):
    if b.get(k) != o.get(k):
        print(f"DIFF {k}: bend {b.get(k)!r} libclang {o.get(k)!r}"); bad += 1
print(f"--- {len(o)} libclang-resolved constants, {len(b)} in the bend row, {bad} disagreements")
sys.exit(1 if bad else 0)
