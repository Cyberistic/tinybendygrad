#!/usr/bin/env python3
"""Dump the libclang AST that autogen.py walks, as a canonical FIXTURE text
tree.  This is INPUT, not an expectation: the Bend port reads this tree and
must emit what the REAL `gen()` emits.

A node is one line:
    T <kind> <nm>          a CXType
    C <kind> <nm> ...      a CXCursor, with its own type as a child
    f <name> <tykind> <off> <bw> <isbf>   a field (from all_fields)

Nothing here is a judgement. `nm` is autogen.py's own `nm()` (== the
clang_get*Spelling string), so a spelling difference is a generator difference.
"""
import sys, os
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
os.environ.setdefault("CLANG", "/opt/homebrew/opt/llvm@20/lib/libclang.dylib")

import ctypes, importlib.util
import tinygrad.runtime.autogen.libclang as clang

spec = importlib.util.spec_from_file_location("ag",
    "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/runtime/support/autogen.py")
ag = importlib.util.module_from_spec(spec); spec.loader.exec_module(ag)

hdr = sys.argv[1]
out = sys.argv[2]

def tstr(t): return f"{int(t.kind)}|{ag.nm(t)}"
def cstr(c): return f"{int(c.kind)}|{ag.nm(c)}"

def esc(s): return s.replace("\\", "\\\\").replace("\n", "\\n").replace(" ", "~")

L = []
idx = clang.clang_createIndex(False, 0)
aa = None
tu = clang.clang_parseTranslationUnit(idx, os.fspath(hdr).encode(), aa, 0, None, 0,
                                      clang.CXTranslationUnit_DetailedPreprocessingRecord)

def dump_t(t, indent, depth):
  if depth > 6: return
  pad = "  " * indent
  L.append(f"{pad}T {int(t.kind)} {esc(ag.nm(t))}")
  # a type's DECLARATION is where its children live, for records/enums.
  if t.kind in (clang.CXType_Record, clang.CXType_Enum):
    decl = clang.clang_getTypeDeclaration(t)
    dump_c(decl, indent + 1, depth + 1)

def dump_c(c, indent, depth):
  if depth > 6: return
  pad = "  " * indent
  L.append(f"{pad}C {int(c.kind)} {esc(ag.nm(c))}")
  if c.kind in (clang.CXCursor_StructDecl, clang.CXCursor_UnionDecl, clang.CXCursor_TypedefDecl,
               clang.CXCursor_EnumDecl, clang.CXCursor_FieldDecl, clang.CXCursor_FunctionDecl,
               clang.CXCursor_VarDecl, clang.CXCursor_ParmDecl, clang.CXCursor_MacroDefinition,
               clang.CXCursor_EnumConstantDecl):
    dump_t(clang.clang_getCursorType(c), indent + 1, depth + 1)
  if c.kind in (clang.CXCursor_StructDecl, clang.CXCursor_UnionDecl, clang.CXCursor_EnumDecl,
               clang.CXCursor_FunctionDecl, clang.CXCursor_VarDecl):
    for ch in ag.children(c): dump_c(ch, indent + 1, depth + 1)

root = ag.unwrap_cursor(clang.clang_getTranslationUnitCursor(tu))
# autogen.py:230 skips any cursor whose file is not the one being generated.
for c in ag.children(root):
  if ag.loc_file(ag.loc(c)) == str(hdr): dump_c(c, 0, 0)

open(out, "w").write("\n".join(L) + "\n")
print(f"{len(L)} nodes -> {out}")
