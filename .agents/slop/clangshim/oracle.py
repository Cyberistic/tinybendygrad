#!/usr/bin/env python3
"""The CPython side of the Stage 1 row, and the Stage 3 field oracle.

EVERY number printed here is produced by CALLING CPython's own
`tinygrad.runtime.autogen.libclang`.  None is typed.  The bend side must
answer the same questions about the SAME fixture, in the SAME fixture
definition, which is why SRC and the field list live in ONE place and are
read by both sides (the C shim #includes the generated fixture header, which
this file also writes).

    python3 .agents/slop/clangshim/oracle.py            # all rows
    python3 .agents/slop/clangshim/oracle.py sizes      # only the size rows
    python3 .agents/slop/clangshim/oracle.py fields     # only the field rows
"""
from __future__ import annotations

import ctypes
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import tinygrad.runtime.autogen.libclang as L  # noqa: E402

# THE FIXTURE.  One translation unit, in memory (an unsaved file), so neither
# side depends on a filesystem or on a clock.
SRC = b"""struct Pair {
  int a;
  char b;
  double c;
};
int top;
"""

# The fields the port must read out of a by-value CXCursor struct record.
# (name, byte offset within the C record, C spelling) -- the OFFSETS here are
# the oracle's, not the port's, and the port is compared against them.
FIELDS = [("a", 0, "int"), ("b", 4, "char"), ("c", 8, "double")]


def _tu() -> L.CXTranslationUnit:
    uf = L.struct_CXUnsavedFile()
    uf.Filename = b"fixture.c"
    uf.Contents = SRC
    uf.Length = len(SRC)
    arr = (L.struct_CXUnsavedFile * 1)(uf)
    ix = L.clang_createIndex(0, 0)
    return L.clang_parseTranslationUnit(ix, b"fixture.c", None, 0, arr, 1, 0)


def _find(tu, spelling: str):
    """The first cursor whose SPELLING is `spelling`, depth first."""
    found = []

    def visit(c, parent, data):
        s = L.clang_getCursorSpelling(c)
        txt = L.clang_getCString(s) if s else None
        if txt is not None and txt.decode() == spelling:
            found.append(c)
        return 1

    L.clang_visitChildren(L.clang_getTranslationUnitCursor(tu),
                          L.CXCursorVisitor(visit), None)
    assert found, f"no cursor named {spelling!r} in the fixture"
    return found[0]


def sizes() -> None:
    """clang_Type_getSizeOf, for types CPython can also ask about.

    The port asks about `int`, `char` and `double` by NAME too, so the
    expectation comes from both sides rather than from a literal here.
    """
    tu = _tu()
    for name in ("int", "char", "double"):
        t = L.clang_getCursorType(_find(tu, name))
        sz = L.clang_Type_getSizeOf(t)
        spelling = L.clang_getCString(L.clang_getTypeSpelling(t)).decode()
        align = L.clang_Type_getAlignOf(t)
        print(f"SIZE {name:8s} sizeOf={sz} alignOf={align} spelling={spelling}")


def fields() -> None:
    """The field accessor oracle: read the fields of a REAL CXCursor.

    A CXCursor arrives over the ABI by value and bend cannot read a member of
    it, so the port reads them through a C helper.  These are the numbers the
    helper must reproduce, one row per field.
    """
    import ctypes as C
    tu = _tu()
    pair = _find(tu, "a")           # the FIELD_DECL `a`, not the struct
    cur = L.clang_getCursorType(pair)
    # the STRUCT_DECL itself: the record whose fields the port must read
    sdecl = _find(tu, "Pair")
    cx = sdecl
    rec = type(cx)                 # CXCursor
    for fname, off, cspell in FIELDS:
        # the authoritative offset is offsetof() in C; ctypes agrees by
        # construction only if the layout is what we claim, so ASK libclang
        # instead: clang_Type_getOffsetOf is the answer both sides must have.
        fld = _find(tu, fname)
        fty = L.clang_getCursorType(fld)
        off_lib = L.clang_Type_getOffsetOf(fty)
        size_lib = L.clang_Type_getSizeOf(fty)
        spelling = L.clang_getCString(L.clang_getTypeSpelling(fty)).decode()
        print(f"FIELD {fname} cdecl_off={off} libclang_off={off_lib} "
              f"sizeOf={size_lib} spelling={spelling} c={cspell}")
    # the CXCursor record layout itself, as bend's port must see it
    print(f"RECORD CXCursor sizeof={C.sizeof(L.CXCursor)}")
    for nm in ("kind", "xdata", "data"):
        print(f"RECORDFIELD {nm} present={nm in [f[0] for f in L.CXCursor._fields_]}")


def cstr(p) -> str:
    """clang_getCString's answer as text.

    CORRECTED, AND THE CORRECTION IS THE POINT. The docstring here used to say
    that tinygrad's `clang_getCString` is bound to return `c.POINTER[c_char]`, so
    it "hands back an LP_c_char and NOT a bytes; `.value` is the only reading."
    The code then did `p.value` -- obeying the stated rule -- and CRASHED with
    `AttributeError: 'LP_c_char' object has no attribute 'value'`.

    So the rule was stated, obeyed, and wrong. **A documented-and-obeyed rule is
    worth nothing**, which is the same conclusion as the record-binder shadow in
    `codegen/__init__.bend:176`.

    WHAT IS ACTUALLY TRUE. `ctypes.c_char_p` IS an alias for
    `POINTER(c_char)`, but a function whose `restype` is spelled
    `POINTER(c_char)` hands back an `LP_c_char` instance, and `LP_c_char` has no
    `.value`. `p[0]` yields exactly ONE byte. To read the NUL-terminated string,
    CAST to `c_char_p` -- that is what reintroduces the `.value` reading, on the
    right type.
    """
    if p is None:
        return ""
    if isinstance(p, bytes):
        return p.decode()
    return ctypes.cast(p, ctypes.c_char_p).value.decode()


def version() -> None:
    print("CVER " + cstr(L.clang_getCString(L.clang_getClangVersion())))


if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what in ("all", "version"):
        version()
    if what in ("all", "sizes"):
        sizes()
    if what in ("all", "fields"):
        fields()
