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
# ---- fix 5: the 324 `None{}` bodies ------------------------------------------
# The trampolines arrived as one template applied 324 times with `None{}` in it,
# and a body that returns `None` is not a binding.  The FILL is generated from
# the SAME `.agents/slop/ag-libclang.tramp` rows by `.agents/slop/clangfill/`, so
# a bend signature and the C declaration beside it have one source.  This step is
# the splice, and it lives HERE rather than in `ag-emit.bend` for the same reason
# fixes 1-4 live here: `ag-emit.bend` states the SIGNATURE column and this file
# already owns everything that is applied on top of it.
sys.path.insert(0, str(SHIM.parent / "clangfill"))
import fill  # noqa: E402

# ---- fix 1: every ABI type name that REDECLARES one of BASE's own -----------
# The emitter mints ONE NULLARY `type X is Data: X{}` per ctypes spelling, and it
# has no way to know that `U32` and `Unit` are already spoken for: Base declares
# them (references/bend/bend2/base.bend:9 `Unit`, :57 `U32{data: Word(32n)}`), and
# a second `type U32 is Data` is `duplicate declaration: U32`.  That wall shipped
# once, and it was closed with a TWO-ENTRY LITERAL LIST -- a list the next ABI
# width will not be on.
#
# So the rule is a RULE and not a list: a name Base declares is never minted, and
# the check runs LAST, after the `EXTRA` block below has had its chance to mint
# one.  Running it first would have been a hole, not a fix.
def base_types() -> set[str]:
    b = REPO / "references" / "bend" / "bend2" / "base.bend"
    assert b.is_file(), f"cannot read Base's declarations from {b}"
    return set(re.findall(r"^type (\w+)", b.read_text(), re.M))


def drop_base_types(text: str) -> str:
    """Erase every minted nullary placeholder whose name Base already declares.
    Sorted so the result does not depend on set iteration order."""
    for n in sorted(base_types()):
        text = re.sub(rf"(?m)^type {n} is Data:\n  {n}\{{\}}\n\n", "", text)
    left = sorted(base_types() & set(re.findall(r"(?m)^type (\w+) is Data", text)))
    assert not left, f"still redeclaring Base's own types: {left}"
    return text

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

# The DENOMINATOR, asserted on every run.  It is the ROW COUNT OF THE INPUT the
# emitter reads, not a number written beside the thing it measures: a row added to
# `.agents/slop/ag-libclang.tramp` that the fill does not notice fails HERE.
N_TRAMPOLINES = sum(1 for ln in (REPO / ".agents" / "slop" / "ag-libclang.tramp")
                    .read_text().splitlines() if ln.strip())

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
# the file back to its earlier, non-compiling state.  `.agents/slop/spelling/roundtrip.py`
# runs BOTH steps and compares the result to this file by md5, so "the generator
# made this" is a measurement and not a claim.
#
# THE FOUR FIXES, and why each was needed (`bend --check-only` stops at the first
# error, so these came from iterating to a fixed point, not from reading):
#   1. Every ABI type name that REDECLARES one of Base's own is dropped -- DERIVED
#      from `references/bend/bend2/base.bend`, not listed.  `type U32 is Data`
#      beside Base's `U32{data: Word(32n)}` was the `duplicate declaration: U32`
#      that made this file red, and the two-name literal list that first closed
#      it was a list the next ABI width would not have been on.
#   2. `Ty` is the return of all 60 `ty_*` defs and was declared nowhere -> declared.
#   3. 13 ABI type names are used in signatures and are not in the enumerated
#      table -> declared.  `F64`/`I64`/`U64` are among them.
#   4. `type` and `Kind` are bend keywords and were used as parameter names -> `_type`, `_Kind`.
#
# THE 64-BIT SPELLING IN THIS FILE, because `I64` HERE AND `I64` IN `helpers.bend`
# ARE DIFFERENT TYPES WITH ONE NAME.  `helpers.bend:1639` is the tree's 64-bit
# value -- `I64{hi: U32, lo: U32}`, 678 uses in 41 files, 40 defs of arithmetic on
# it, and it is what `runtime/dtype.c:205` opens with `ctr_take`.  The `I64{}` here
# is NULLARY: a placeholder for a width bend has no type for, on 13 signatures
# whose bodies are all `None{}`.  It is an ABI annotation on a column that never
# executes, it is not a value, and it has no constructor that carries one.  See
# `.agents/slop/SPELLING.md`; the three of them cannot all be canonicalised
# (`helpers.bend:1636` -- an `I64` is a SIGNED pair, so `U64` has no image).
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
# THIS FILE DOES NOT RUN.  `bend <file>` and `bend <file> -o out.js` both fail with
# `a foreign def without a .js import: Loaded_dylib`: every one of the 11 lane laws
# imports only `libclang-ffi.c`, and `references/bend/bend2/comp.ts:3385` asks for a
# `.js` import for every foreign def.  Add one and it becomes `bend: no effect
# registers <k>`.  `bend -o out.c` is rc=0 and `cc` links and runs it -- so the file
# COMPILES as C and CANNOT BE RUN.  See `.agents/slop/SPELLING.md`.
#
# STILL NOT COVERED, and not claimed: the other 40 struct RECORDS and their fields,
# the 47 enum dicts and their 845 constants, the 32 `TypeAlias` lines, and the 311
# trampolines that the lane does not call.
'''


def fix(text: str) -> str:
    # idempotent by construction: every step tests for its own output first, so
    # re-running on an already-fixed file is a no-op and `--check` can say so.
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
    # fix 5.  The assert is on what is LEFT, not on how many were filled: re-running
    # on an already-filled file fills nothing and is a no-op, so "filled 324" cannot
    # be the invariant or `--check` would fail on a correct file.  A `None{}` that
    # survives is a trampoline whose body nobody generated, and silently skipping it
    # reads as tidy.
    text, filled = fill.bodies(text)
    left = fill.DEF_RE.findall(text)
    assert not left, f"{len(left)} trampolines still have a None{{}} body: {left[:3]}"
    # LAST, because it is the only step that can be undone by a later one.
    text = drop_base_types(text)
    # the header, up to and including `import Base`
    text = NEW_HDR + "import Base" + text.split("import Base", 1)[1]
    # the lane BEFORE the fill laws: `fill.with_drive` anchors on the lane, and the
    # anchor has to exist on the first pass for the two passes to agree.
    if "# ---- THE FFI LANE" not in text:
        text = text.rstrip("\n") + "\n\n" + LANE.read_text().rstrip("\n") + "\n"
    text = fill.with_drive(text)
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