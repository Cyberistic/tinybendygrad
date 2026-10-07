# ---- THE FFI LANE: the measurements this file makes of libclang --------------
#
# Eight laws.  Two of them build a whole ROW's value string and four of them are
# the numeric and label columns around them.  They are NOT named after the
# libclang functions they call, because they are not those functions: each takes
# a field SELECTOR instead of a `CXType`, because a `CXType` is a 24-byte
# by-value struct that bend cannot hold across two calls.  The 324 trampolines
# keep their own names and signatures and this lane does not collide with them.
#
# WHY EVERY LAW REPEATS THE WHOLE CHAIN.  Every value in bend is LINEAR -- `Nat`
# and `U32` alike, measured: `U32.show(i) ++ U32.show(i)` fails with
# `consumed more than once`.  So createIndex, then parseTranslationUnit, then
# getTranslationUnitCursor, then getCursorType, then getSizeOf is five uses of
# four handles and is not expressible from bend at all.  Each `_run` performs the
# chain and returns ONE value.  A wall on callers, not on bindings.
#
# `offof_bits` and `offof_bytes` are ONE MEASUREMENT and TWO READERS: the `_run`
# calls `clang_Type_getOffsetOf` once, keeps the answer in one `long`, and derives
# both columns from it, exactly as `oracle.py` does.  Linearity is why the
# division cannot live in this file; `.agents/slop/clangshim/cl-port-gate.sh`
# re-derives `offof_bytes * 8 == offof_bits` from the PRINTED row, which is what
# makes the division falsifiable from outside the process.

law Type_report:
  U32 -> IO(String)

def Type_report(field):
  import "../../../.agents/slop/clangshim/libclang-ffi.c"

law Field_report:
  U32 -> IO(String)

def Field_report(field):
  import "../../../.agents/slop/clangshim/libclang-ffi.c"

law Field_offset_unknown:
  IO(Nat)

def Field_offset_unknown():
  import "../../../.agents/slop/clangshim/libclang-ffi.c"

law Field_name:
  U32 -> IO(String)

def Field_name(field):
  import "../../../.agents/slop/clangshim/libclang-ffi.c"

law Field_spell:
  U32 -> IO(String)

def Field_spell(field):
  import "../../../.agents/slop/clangshim/libclang-ffi.c"

law Record_report:
  IO(String)

def Record_report():
  import "../../../.agents/slop/clangshim/libclang-ffi.c"

law Record_words:
  IO(String)

def Record_words():
  import "../../../.agents/slop/clangshim/libclang-ffi.c"

law Pair_size:
  IO(Nat)

def Pair_size():
  import "../../../.agents/slop/clangshim/libclang-ffi.c"

law Clang_version:
  IO(String)

def Clang_version():
  import "../../../.agents/slop/clangshim/libclang-ffi.c"

law Loaded_dylib:
  IO(String)

def Loaded_dylib():
  import "../../../.agents/slop/clangshim/libclang-ffi.c"

# ---- main: the oracle's ten rows, in its order ------------------------------
#
# `bend <file>` prints nothing without a `main`, and `bend -o` emits NO CID for a
# law `main` never calls, so every law above is called here directly, once each.
# The row count is therefore a property of THIS function and not of the gate.
#
# The oracle's `%-12s` column padding is deliberately NOT reproduced: a column
# width is a layout, and reproducing one here would be an assertion about layout
# wearing a row's clothes.  The gate normalises runs of spaces, and nothing else.

def main() -> IO(Unit):
  do IO<Unit>:
    lib : String <- Loaded_dylib()
    IO.print("CLIB " ++ lib)
    cver : String <- Clang_version()
    IO.print("CVER " ++ cver)
    n0 : String <- Field_spell(0)
    v0 : String <- Type_report(0)
    IO.print("SIZE " ++ n0 ++ " " ++ v0)
    n1 : String <- Field_spell(1)
    v1 : String <- Type_report(1)
    IO.print("SIZE " ++ n1 ++ " " ++ v1)
    n2 : String <- Field_spell(2)
    v2 : String <- Type_report(2)
    IO.print("SIZE " ++ n2 ++ " " ++ v2)
    n3 : String <- Field_spell(3)
    v3 : String <- Type_report(3)
    IO.print("SIZE " ++ n3 ++ " " ++ v3)
    f0 : String <- Field_name(0)
    w0 : String <- Field_report(0)
    IO.print("FIELD " ++ f0 ++ " " ++ w0)
    f1 : String <- Field_name(1)
    w1 : String <- Field_report(1)
    IO.print("FIELD " ++ f1 ++ " " ++ w1)
    f2 : String <- Field_name(2)
    w2 : String <- Field_report(2)
    IO.print("FIELD " ++ f2 ++ " " ++ w2)
    rec : String <- Record_report()
    IO.print("RECORD CXCursor " ++ rec)
    # ---- port-only rows, AFTER the shared ten and on rows the oracle does not
    # ---- claim.  The oracle's `opaque=_mem_` is a ctypes artefact with no C
    # ---- counterpart: `tinygrad/runtime/support/c.py`'s `Struct` exposes ONE
    # ---- byte-array member and keeps the real ones in `_real_fields_`.
    pair : Nat <- Pair_size()
    IO.print("PORT Pair_size " ++ Nat.show(pair))
    nope : Nat <- Field_offset_unknown()
    IO.print("PORT offof_unknown_refused " ++ Nat.show(nope))
    words : String <- Record_words()
    IO.print("PORT RECORD_words CXCursor " ++ words)