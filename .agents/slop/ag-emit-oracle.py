#!/usr/bin/env python3
"""Oracle for the EMISSION TEMPLATES. Every expectation is produced by CALLING
CPython with the SAME f-string autogen.py writes, and the SAME arguments the
Bend rows use. Nothing here is typed.

The f-strings below are copied CHARACTER FOR CHARACTER out of autogen.py, so a
disagreement is a disagreement about the TEMPLATE, not about the oracle.
"""
import sys, importlib.util, os, ctypes
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
os.environ.setdefault("CLANG", "/opt/homebrew/opt/llvm@20/lib/libclang.dylib")
import tinygrad.runtime.autogen.libclang as clang
spec = importlib.util.spec_from_file_location("ag",
    "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/runtime/support/autogen.py")
ag = importlib.util.module_from_spec(spec); spec.loader.exec_module(ag)
def show(l): print("E " + l)

tnm, size, f, args, ty, rt = "struct_Pair", 8, "b", ("u32", "4"), "ctypes.c_int32", "ctypes.c_int32"
EMPTY: list = []
# :143
show(f"emit.pass class {tnm}(c.Struct): pass")
# :151
show("emit.head " + " | ".join(["@c.record", f"class {tnm}(c.Struct):", f"  SIZE = {size}"]))
# :151
show(f"emit.field " + f"  a: int")
# :153 -- a plain field, args = (type, offset)
show("emit.cell " + f"('{f}', {', '.join(str(a) for a in args)})")
# :153 -- a BITFIELD, args = (type, offset, bitwidth, offset % 8)
show("emit.cellbf " + f"('hi', {', '.join(str(a) for a in ('ctypes.c_uint32', 0, 5, 3))})")
# :153
show(f"emit.regf {tnm}.register_fields([" + ", ".join(f"('{n}', {', '.join(str(a) for a in a2)})"
     for n, a2 in (("a", ("u32", 0)), ("b", ("u32", 4)))) + "])")
# :160
show("emit.enumcell " + f"(BLUE:=7): 'BLUE'")
# :160
show("emit.enumdict " + f"enum_Col: dict[int, str] = {{" + ", ".join(f"({n}:={v}): '{n}'" for n, v in (("RED",1),("BLUE",7))) + "}")
# :160 -- a NEGATIVE constant, which is `clang_getEnumConstantDeclValue`
show(f"emit.enumneg " + f"(N1:=-1): 'N1'")
# :145
show(f"emit.alias " + f"PairAlias: TypeAlias = {tnm}")
# :240
show("emit.bind " + f"@dll.bind({', '.join(['ctypes.c_int32', 'ctypes.c_int32', 'ctypes.c_uint32'])})")
# :241
show("emit.def " + f"def addfn({', '.join(f'{a}:{h}' for a, h in (('a','int'),('b','int')))}) -> int: ...")
# :241 -- no parameters
show(f"emit.def0 " + f"def vfn() -> None: ...")
# :242
show(f"emit.retained " + f"MTLCreateSystemDefaultDevice = objc.returns_retained(MTLCreateSystemDefaultDevice)")
# :122
show("emit.ptr " + f"c.POINTER[{tnm}]")
# :119
show("emit.cfn0 " + f"c.CFUNCTYPE[None, [" + ', '.join(['ctypes.c_int32', 'ctypes.c_uint32']) + "]]")
# :119 -- an empty argument list
show("emit.cfn1 " + f"c.CFUNCTYPE[{rt}, [" + ', '.join([]) + "]]")
# :163
show("emit.arr " + f"c.Array[u32, Literal[{4}]]")
# :251
show(f"emit.macro " + f"ONE = {1}")
# :250 -- `' ' * bool(_args)`
show("emit.macrof " + "ADDER = lambda" + " " * True + ",".join(["a","b"]) + ": " + "((a)+(b))")
# :250 -- no arguments
# the macro BODY is the SOURCE TEXT `readext` copied out of the header, not a
# Python value -- so it is the literal `1 + 2` and evaluating it to 3 would be
# exactly the transcription bug this oracle exists to prevent.
show("emit.macrof0 " + "BODY = lambda" + " " * False + ",".join([]) + ": " + "1 + 2")
# :264
show(f"emit.indll " + f"try: stdin = c.POINTER[struct__IO_FILE].in_dll('c', 'stdin') # type: ignore\n"
                       f"except (ValueError,AttributeError): pass")
# :273 the prologue, first six lines
show("prolog.head " + " | ".join(['# mypy: disable-error-code="empty-body"', "from __future__ import annotations",
     "import ctypes", "from typing import Literal, TypeAlias",
     "from tinygrad.runtime.support.c import _IO, _IOW, _IOR, _IOWR", "from tinygrad.runtime.support import c"]))
# :275
show("prolog.objc " + " | ".join(["from tinygrad.runtime.support import objc"]))
show("prolog.objc0 " + " | ".join([]))
# :276 -- no paths, no errno
# `{dll}` is the SOURCE TEXT of gen's dll argument, i.e. the four characters
# 'c' in quotes -- not a Python object.
show("emit.dll " + "dll = c.DLL('agtest', " + "'c'" + "" + "" + ")")
# :276 -- with paths and errno, in THAT order
show("emit.dllerr " + "dll = c.DLL('libc', " + "'c'" + ", " + repr(['/usr/lib/x86_64-linux-gnu']) + ", use_errno=True" + ")")
# :140 / :158 -- the ONE shared anonymous counter
show(f"anon0 " + f"_anon{''}struct{0}")
show(f"anon1 " + f"_anon{''}enum{1}")
# :128 -- the `::`-to-`_` rewrite, applied to the three fixtures
# `colons_to_underscores` ALONE -- only the `::` rewrite -- so the SPACE in
# `a::b c::d` must SURVIVE. The combined rewrite is the `nm.pair` group below.
for i, t in enumerate(("a::b c::d", "::x", "x::", "x:y", "x:", ":")):
    show(f"nm.cpp{i} " + f"{t.replace('::', '_')}")
# :142 -- space FIRST, then `::`
for i, t in enumerate(("struct foo bar", "ns::foo", "a::b c::d")):
    show(f"nm.pair{i} " + f"{t.replace(' ', '_').replace('::', '_')}")

# :151 the five-line join that REPLACES the `pass` line. Newlines are real, so
# this row is the one that pins the ORDER of the fields -- `ops_cl`'s unit found
# `Sig`'s field names INVERTED behind a green gate, and an inverted pair here is
# the same bug in miniature.
show("emit.block " + "\n".join(["@c.record", f"class {tnm}(c.Struct):", f"  SIZE = {size}"] +
     [f"  {n}: int" for n in ("a", "b")]))
