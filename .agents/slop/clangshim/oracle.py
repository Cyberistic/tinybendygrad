#!/usr/bin/env python3
"""The CPython side of the Stage 1 row, and the Stage 3 field oracle.

EVERY number printed here is produced by CALLING CPython's own
`tinygrad.runtime.autogen.libclang`.  None is typed.  The bend side must
answer the same questions about the SAME fixture, in the SAME fixture
definition, which is why SRC and the field list live in ONE place and are
read by both sides (the C shim #includes the generated fixture header, which
this file also writes).

A row's LABEL is the QUESTION and lives in FIELDS; every value on the row is
libclang's ANSWER.  Plant a fixture edit and the label stays put while the
answer moves -- which is what makes "the label is not the answer" checkable
instead of merely asserted.

    python3 .agents/slop/clangshim/oracle.py            # all rows
    python3 .agents/slop/clangshim/oracle.py sizes      # only the size rows
    python3 .agents/slop/clangshim/oracle.py fields     # only the field rows

`char *` IS AN ADDRESS, NOT A STRING, and ctypes enforces that in three
different ways that do not agree with each other.  Measured here, on
CPython 3.14.6 / the pinned dylib:

    site                        bytes in    c_char_p in    cast(buf) in
    struct field  POINTER(char)  refused    REFUSED       accepted
    struct field  c_char_p       accepted    accepted      REFUSED
    function arg  POINTER(char)  accepted    accepted      accepted

So there is no coercion that makes the pair agree, and the failures are not
symmetric: `LP_c_char` and `c_char_p` are DISTINCT classes (ctypes rejects
`c_char_p` instances for an `LP_c_char` field and vice versa), `bytes` is
accepted only at the ARGUMENT boundary, where ctypes converts it for you.
The rule this file follows is therefore the only one that covers all three:

    a char* is a real pointer everywhere EXCEPT the argument list;
    c_char_p is a READING cast on top of LP_c_char, never a carrier.

`tinygrad/runtime/support/c.py` refuses `bytes` at the WRITE end, and it is
right to: accepting them would mean ctypes allocated a temporary buffer that
nothing keeps alive for the length of the FFI call.  See the report -- the
oracle casts instead, and no upstream change is needed.
"""
from __future__ import annotations

import ctypes, functools, os, sys
from pathlib import Path

# THE PIN, and it is a pin rather than a preference.  Unpinned, ctypes resolves
# libclang by SEARCH PATH: `/opt/homebrew/opt/llvm@21/.../llvm@14` on OSX, so the
# oracle answered "Homebrew clang version 20.1.8" while the shim linked Apple's
# "Apple clang version 17.0.0" (s1.sh/s3.sh: -L/Library/Developer/CommandLineTools
# /usr/lib -lclang -Wl,-rpath,...).  Two builds, one fixture, and a version-ambiguous
# oracle is worse than a slower one.  Set BEFORE the import, because the binding
# resolves the library once at import time.
#
# LIBCLANG_PATH is tinygrad's own escape hatch (`c.py:95`, `getenv(nm.upper()+"_PATH")`),
# so this needs no monkeypatch and no upstream change -- and it deliberately
# OVERRIDES any inherited value, since the fixture must not depend on the caller's shell.
PIN = "/Library/Developer/CommandLineTools/usr/lib/libclang.dylib"
if not os.path.isfile(PIN): raise SystemExit(f"pinned libclang is not a file: {PIN}")
os.environ["LIBCLANG_PATH"] = PIN

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
import tinygrad.runtime.autogen.libclang as L  # noqa: E402

# `findlib` falls back to the SEARCH PATH when LIBCLANG_PATH is not a file, so a
# missing or renamed dylib would otherwise load a DIFFERENT BUILD SILENTLY.  The
# whole oracle is only reproducible if the load is verified, not requested.
if getattr(L.dll, "_name", None) != PIN: raise SystemExit(f"libclang pin FAILED, loaded {getattr(L.dll, '_name', None)!r}, want {PIN!r}")

LP = ctypes.POINTER(ctypes.c_char)

# THE FIXTURE.  One translation unit, in memory (an unsaved file), so neither
# side depends on a filesystem or on a clock.
SRC = b"""struct Pair {
  int a;
  char b;
  double c;
};
int top;
"""
FNAME = b"fixture.c"

# The fields the port must read out of a by-value CXCursor struct record.
# (name, byte offset within the C record, C spelling) -- the OFFSETS here are
# the oracle's, not the port's, and the port is compared against them.
FIELDS = [("a", 0, "int"), ("b", 4, "char"), ("c", 8, "double")]


@functools.cache
def _tu() -> L.CXTranslationUnit:
    """The fixture parsed ONCE, in memory.

    Cached rather than rebuilt per mode: libclang keeps reading the unsaved
    buffers, so their lifetime has to be the process's, not this function's.
    """
    nb, cb = ctypes.create_string_buffer(FNAME), ctypes.create_string_buffer(SRC)
    uf = L.struct_CXUnsavedFile()
    uf.Filename, uf.Contents = ctypes.cast(nb, LP), ctypes.cast(cb, LP)
    uf.Length = len(SRC)
    ix = L.clang_createIndex(0, 0)
    return L.clang_parseTranslationUnit(ix, FNAME, None, 0, (L.struct_CXUnsavedFile * 1)(uf), 1, 0)


def text(s) -> str:
    """A CXString as text.

    Two steps, and the second is the one that is easy to get wrong.
    `clang_getCString` has its restype SPELLED `POINTER[c_char]`, so it hands
    back an `LP_c_char` -- which has no `.value`, and whose `p[0]` is exactly
    ONE byte.  Reading the string means CASTING to `c_char_p`, which is what
    puts `.value` back on the right type.

    So `s` is a CXString and never a `char*`: casting one to `c_char_p` fails
    with "cannot be interpreted as ctypes.c_void_p", which is what this file
    did for one revision.
    """
    p = ctypes.cast(L.clang_getCString(s), ctypes.c_char_p).value
    return p.decode() if p is not None else ""


def _find(spelling: str) -> L.CXCursor:
    """The first cursor whose SPELLING is `spelling`, depth first.

    The visitor returns `CXChildVisit_Recurse`, which is 2.  This used to
    return 1, which is `CXChildVisit_Continue`: the walk never left the
    translation unit's own children, so `Pair`'s fields were invisible and the
    search for them could only ever fail.
    """
    found = []

    def visit(c, parent, data):
        if text(L.clang_getCursorSpelling(c)) == spelling: found.append(c)
        return L.CXChildVisit_Recurse

    L.clang_visitChildren(L.clang_getTranslationUnitCursor(_tu()), L.CXCursorVisitor(visit), None)
    assert found, f"no cursor named {spelling!r} in the fixture"
    return found[0]


def version() -> None:
    """Which build answered, and whether it is the one that was pinned."""
    print(f"CLIB {L.dll._name}")
    print(f"CVER {text(L.clang_getClangVersion())}")


def sizes() -> None:
    """clang_Type_getSizeOf / clang_Type_getAlignOf, for the types the fixture names.

    The three types are asked for BY NAME -- the C spellings in FIELDS -- and
    each is reached through the cursor of a field that libclang gave it, so the
    expectation comes from both sides rather than from a literal here.
    """
    for name, _, cspell in FIELDS:
        t = L.clang_getCursorType(_find(name))
        print(f"SIZE {cspell:12s} sizeOf={L.clang_Type_getSizeOf(t)} alignOf={L.clang_Type_getAlignOf(t)} "
              f"spelling={text(L.clang_getTypeSpelling(t))}")
    # the RECORD's own size, so the field offsets in `fields()` have something to
    # sum to: a partial field list cannot tell a right layout from a short one.
    rec = L.clang_getCursorType(_find("Pair"))
    print(f"SIZE {'struct Pair':12s} sizeOf={L.clang_Type_getSizeOf(rec)} alignOf={L.clang_Type_getAlignOf(rec)} "
          f"spelling={text(L.clang_getTypeSpelling(rec))}")


def fields() -> None:
    """The field accessor oracle: read the fields of a REAL CXCursor.

    A CXCursor arrives over the ABI by value and bend cannot read a member of
    it, so the port reads them through a C helper.  These are the numbers the
    helper must reproduce, one row per field.

    `clang_Type_getOffsetOf` is given the RECORD type and the field NAME -- its
    second argument is the field name, and passing the field's own type (which
    is what this used to do) answers a question about nothing.  It reports BITS,
    measured: 0/32/64 for a/b/c, and -5 for a name the record does not have.
    """
    rec = L.clang_getCursorType(_find("Pair"))
    for name, off, cspell in FIELDS:
        bits = L.clang_Type_getOffsetOf(rec, name.encode())
        assert bits == off * 8, f"offsetof({cspell} {name}): C says {off}B, libclang says {bits}b"
        t = L.clang_getCursorType(_find(name))
        print(f"FIELD {name} cdecl_off={off} offof_bits={bits} offof_bytes={bits // 8} "
              f"sizeOf={L.clang_Type_getSizeOf(t)} spelling={text(L.clang_getTypeSpelling(t))} c={cspell}")
    # the CXCursor record layout itself, as bend's port must see it: ctypes sees
    # ONE opaque blob, and the members exist only as Field descriptors -- which is
    # why a C helper is required and not merely convenient.
    print(f"RECORD CXCursor sizeof={ctypes.sizeof(L.CXCursor)} opaque={L.CXCursor._fields_[0][0]} "
          f"fields={','.join(f'{n}@{o}' for n, _, o in L.CXCursor._real_fields_)}")


MODES = {"all": (version, sizes, fields), "version": (version,), "sizes": (sizes,), "fields": (fields,)}

if __name__ == "__main__":
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    # an unknown mode used to print nothing and exit 0, which reads as a pass
    if what not in MODES: raise SystemExit(f"unknown mode {what!r}; want one of {sorted(MODES)}")
    for mode in MODES[what]:
        mode()
