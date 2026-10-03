"""Measure ClangRenderer.code_for_op vs WGSLRenderer.code_for_op from REAL CPython.

Defect 1 claims the two key sets differ by exactly Ops.FDIV. Measure, do not trust.
Run:  python3 .agents/slop/wgsl-keysets.py
"""
import os, sys, difflib
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tinygrad.renderer.cstyle import CStyleLanguage, ClangRenderer
from tinygrad.renderer.wgsl import WGSLRenderer

base = set(CStyleLanguage.code_for_op.keys())
clang = set(ClangRenderer.code_for_op.keys())
wgsl = set(WGSLRenderer.code_for_op.keys())

print("CStyleLanguage.code_for_op  n=%d" % len(base))
print("ClangRenderer.code_for_op    n=%d" % len(clang))
print("WGSLRenderer.code_for_op     n=%d" % len(wgsl))
print("clang == base               %s" % (clang == base))
print("clang - base                %s" % sorted(str(o) for o in clang - base))
print("base - clang                %s" % sorted(str(o) for o in base - clang))
print("wgsl - clang                %s" % sorted(str(o) for o in wgsl - clang))
print("clang - wgsl                %s" % sorted(str(o) for o in clang - wgsl))
print("symmetric difference size   %d" % len(wgsl ^ clang))
print()
print("sorted clang keys:")
print("\n".join("  " + o.name for o in sorted(clang, key=str)))
print("sorted wgsl keys:")
print("\n".join("  " + o.name for o in sorted(wgsl, key=str)))
print()

# the claim, checked structurally rather than by set arithmetic
print("=== the FDIV arm, called ===")
from tinygrad.uop.ops import Ops
if Ops.FDIV in clang:
    print("clang[FDIV](a,b,dtype) ->", repr(ClangRenderer.code_for_op[Ops.FDIV]("A", "B", None)))
else:
    print("clang has NO FDIV key")
if Ops.FDIV in wgsl:
    print("wgsl [FDIV](a,b,dtype) ->", repr(WGSLRenderer.code_for_op[Ops.FDIV]("A", "B", None)))
else:
    print("wgsl  has NO FDIV key -> KeyError")
print("wgsl[WHERE](a,b,c,dtype) ->", repr(WGSLRenderer.code_for_op[Ops.WHERE]("A", "B", "C", None)))
print("clang[WHERE](a,b,c,dtype) ->", repr(ClangRenderer.code_for_op[Ops.WHERE]("A", "B", "C", None)))

# supports_float4 read sites
print()
print("=== supports_float4 ===")
print("CStyleLanguage.supports_float4  ", CStyleLanguage.supports_float4)
print("WGSLRenderer.supports_float4    ", WGSLRenderer.supports_float4)
print("CStyleLanguage.float4           ", repr(CStyleLanguage.float4))
print("WGSLRenderer.float4            ", repr(WGSLRenderer.float4))
print("CStyleLanguage.float4_style     ", CStyleLanguage.float4_style)
