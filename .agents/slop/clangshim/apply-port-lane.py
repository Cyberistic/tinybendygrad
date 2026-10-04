#!/usr/bin/env python3
"""Apply the three compile fixes and the FFI lane to `tinybendygrad/runtime/autogen/libclang.bend`.

Kept as a script, not as hand edits, because the file's header says GENERATED and
because "regeneration is byte-identical, committed-equals-fresh, all three times"
was the property that made it a machine-readable input in the first place.  A
transformation that is written down is one that can be re-run and diffed.

    python3 .agents/slop/clangshim/apply-port-lane.py            # the real file
    python3 .agents/slop/clangshim/apply-port-lane.py --check    # report, change nothing

The FFI lane is read from `ffi-lane.bend` beside this script, so the lane's text
lives in ONE place and the header comment above cannot drift from the code.
"""
import argparse, re, sys
from pathlib import Path

SHIM = Path(__file__).resolve().parent
REPO = SHIM.parents[2]
PORT = REPO / "tinybendygrad" / "runtime" / "autogen" / "libclang.bend"
LANE = SHIM / "ffi-lane.bend"

# ---- fix 1: two ABI type names that REDECLARE Base's own types -------------
# `type U32 is Data: U32{}` is `duplicate declaration: U32`, and `Unit` likewise.
# Base's are the real ones (Base.bend:57 `U32{data: Word(32n)}`), so the local
# declaration goes and the `ty_` row stays.
DROPPED = ["type U32 is Data:\n  U32{}\n\n", "type Unit is Data:\n  Unit{}\n\n"]

# ---- fix 2: `Ty` is returned by all 60 `ty_*` defs and was declared NOWHERE ---
TY_DECL = "type Ty is Data:\n  Ty{name: String, spellings: String}\n"

# ---- fix 3: 13 ABI type names the enumerated table never had -----------------
# Used in a signature, absent from `ag-libclang.tramp`, and not a Base builtin.
# `F64`, `I64` and `U64` are in this list and they are the 16 defs that cannot be
# EXECUTED -- bend has no such type -- so a nullary Data type is both legal and
# the file's own convention for an ABI type name.
EXTRA = ["CXDiagnostic", "CXDiagnosticSet", "CXTokenKind",
         "Ptr_CXIdxCXXClassDeclInfo", "Ptr_CXIdxIBOutletCollectionAttrInfo",
         "Ptr_CXIdxObjCCategoryDeclInfo", "Ptr_CXIdxObjCContainerDeclInfo",
         "Ptr_CXIdxObjCInterfaceDeclInfo", "Ptr_CXIdxObjCPropertyDeclInfo",
         "Ptr_CXIdxObjCProtocolRefListInfo", "F64", "I64", "U64"]

# ---- fix 4: two parameter names that are bend keywords -----------------------
# `bend` stops a batch parse at the first of them, so this list came from
# iterating `--check-only` to a fixed point, not from reading a header.
KEYWORD_PARAMS = [("clang_Type_getObjCEncoding", "type"), ("clang_getCursorKindSpelling", "Kind")]

HDR = Path(__file__).read_text().split("# ---- THE FFI LANE")[0].split("import Base")[0]
NEW_HDR = '''# GENERATED FILE, THEN HAND-EDITED, AND BOTH PARTS ARE WRITTEN DOWN.
#
# The 324 `@dll.bind` trampolines below are still emitted by `.agents/slop/ag-emit.bend`
# from `tinygrad/runtime/autogen/libclang.py` via `.agents/slop/ag-libclang.tramp`:
#   ./bin/bend .agents/slop/ag-emit.bend -o .agents/slop/ag-emit.bin
#   .agents/slop/ag-emit.bin > <this file>
# ...after which `.agents/slop/clangshim/apply-port-lane.py` applies the four fixes
# and appends the FFI lane.  Both steps are deterministic and re-runnable; the
# edits are NOT in the emitter, so regenerating WITHOUT re-running the script puts
# the file back to its earlier, non-compiling state.
#
# THE FOUR FIXES, and why each was needed (`bend --check-only` stops at the first
# error, so these came from iterating to a fixed point, not from reading):
#   1. `type U32` and `type Unit` REDECLARED Base's own types -> dropped.  This was
#      the `duplicate declaration: U32` that made the committed file red.
#   2. `Ty` is the return of all 60 `ty_*` defs and was declared nowhere -> declared.
#   3. 13 ABI type names are used in signatures and are not in the enumerated
#      table -> declared.  `F64`/`I64`/`U64` are among them and are the 16 defs
#      bend has no type for, so they still CANNOT be executed.
#   4. `type` and `Kind` are bend keywords and were used as parameter names -> `_type`, `_Kind`.
#
# COVERAGE OF THE TRAMPOLINES: unchanged and still what it always was.  A name, an
# arity, ordered parameter names, an ABI type, a return type.  No def among the 324
# executes a libclang call; their bodies are `None{}` and the refusal is in the type.
#
# WHAT IS NEW, AND IT IS MEASURED.  The FFI lane at the foot of this file calls
# libclang for real and answers `.agents/slop/clangshim/oracle.py`'s ten rows --
# sizes, field offsets in BITS and in bytes, and the CXCursor record -- against the
# SAME fixture bytes and the SAME pinned dylib.  `.agents/slop/clangshim/cl-port-gate.py`
# is the gate; `.agents/slop/LIBclang-live.md` has the numbers and the walls.
#
# STILL NOT COVERED, and not claimed: the other 40 struct RECORDS and their fields,
# the 47 enum dicts and their 845 constants, the 32 `TypeAlias` lines, and the 311
# trampolines that the lane does not call.
'''


def fix(text: str) -> str:
    # idempotent by construction: every step tests for its own output first, so
    # re-running on an already-fixed file is a no-op and `--check` can say so.
    for d in DROPPED:
        text = text.replace(d, "")
    if TY_DECL not in text:
        text = text.replace("import Base\n", "import Base\n\n" + TY_DECL, 1)
    have = set(re.findall(r"^type (\w+) is Data", text, re.M))
    add = [n for n in EXTRA if n not in have]
    if add:
        block = "\n".join(f"type {n} is Data:\n  {n}{{}}\n" for n in add)
        text = text.replace("\ndef ty_CVoidP()", f"\n{block}\ndef ty_CVoidP()", 1)
    for defname, kw in KEYWORD_PARAMS:
        text, n = re.subn(rf"(def {defname}\([^)]*?)(?<![\w]){kw}(?=\s*[:,)])", rf"\1_{kw}", text, count=1)
        assert n in (0, 1), f"{defname} lost its single {kw!r} parameter"
    # the header, up to and including `import Base`
    text = NEW_HDR + "import Base" + text.split("import Base", 1)[1]
    # the lane
    if "# ---- THE FFI LANE" not in text:
        text = text.rstrip("\n") + "\n\n" + LANE.read_text().rstrip("\n") + "\n"
    return text


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    want = fix(PORT.read_text())
    if a.check:
        print("IN SYNC" if want == PORT.read_text() else "OUT OF SYNC")
        sys.exit(0 if want == PORT.read_text() else 1)
    before = len(PORT.read_text())
    PORT.write_text(want)
    print(f"{PORT.relative_to(REPO)}: {before} -> {len(want)} bytes")