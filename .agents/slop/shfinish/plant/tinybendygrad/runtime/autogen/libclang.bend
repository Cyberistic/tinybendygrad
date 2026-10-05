# GENERATED FILE, THEN HAND-EDITED, AND BOTH PARTS ARE WRITTEN DOWN.
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
import Base

type Ty is Data:
  Ty{name: String, spellings: String}


type CVoidP is Data:
  CVoidP{}

type CXDiagnostic is Data:
  CXDiagnostic{}

type CXDiagnosticSet is Data:
  CXDiagnosticSet{}

type CXTokenKind is Data:
  CXTokenKind{}

type Ptr_CXIdxCXXClassDeclInfo is Data:
  Ptr_CXIdxCXXClassDeclInfo{}

type Ptr_CXIdxIBOutletCollectionAttrInfo is Data:
  Ptr_CXIdxIBOutletCollectionAttrInfo{}

type Ptr_CXIdxObjCCategoryDeclInfo is Data:
  Ptr_CXIdxObjCCategoryDeclInfo{}

type Ptr_CXIdxObjCContainerDeclInfo is Data:
  Ptr_CXIdxObjCContainerDeclInfo{}

type Ptr_CXIdxObjCInterfaceDeclInfo is Data:
  Ptr_CXIdxObjCInterfaceDeclInfo{}

type Ptr_CXIdxObjCPropertyDeclInfo is Data:
  Ptr_CXIdxObjCPropertyDeclInfo{}

type Ptr_CXIdxObjCProtocolRefListInfo is Data:
  Ptr_CXIdxObjCProtocolRefListInfo{}

type F64 is Data:
  F64{}

type I64 is Data:
  I64{}

type U64 is Data:
  U64{}

def ty_CVoidP() -> Ty: Ty{"CVoidP", "ctypes.c_void_p,ctypes.c_void_p"}

type CXClientData is Data:
  CXClientData{}

def ty_CXClientData() -> Ty: Ty{"CXClientData", "CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData,CXClientData"}

type CXCompletionString is Data:
  CXCompletionString{}

def ty_CXCompletionString() -> Ty: Ty{"CXCompletionString", "CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString,CXCompletionString"}

type CXCursor is Data:
  CXCursor{}

def ty_CXCursor() -> Ty: Ty{"CXCursor", "CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor,CXCursor"}

type CXCursorAndRangeVisitor is Data:
  CXCursorAndRangeVisitor{}

def ty_CXCursorAndRangeVisitor() -> Ty: Ty{"CXCursorAndRangeVisitor", "CXCursorAndRangeVisitor,CXCursorAndRangeVisitor,CXCursorAndRangeVisitor,CXCursorAndRangeVisitor,CXCursorAndRangeVisitor,CXCursorAndRangeVisitor,CXCursorAndRangeVisitor,CXCursorAndRangeVisitor"}

type CXCursorAndRangeVisitorBlock is Data:
  CXCursorAndRangeVisitorBlock{}

def ty_CXCursorAndRangeVisitorBlock() -> Ty: Ty{"CXCursorAndRangeVisitorBlock", "CXCursorAndRangeVisitorBlock,CXCursorAndRangeVisitorBlock,CXCursorAndRangeVisitorBlock,CXCursorAndRangeVisitorBlock,CXCursorAndRangeVisitorBlock,CXCursorAndRangeVisitorBlock,CXCursorAndRangeVisitorBlock,CXCursorAndRangeVisitorBlock"}

type CXCursorSet is Data:
  CXCursorSet{}

def ty_CXCursorSet() -> Ty: Ty{"CXCursorSet", "CXCursorSet,CXCursorSet,CXCursorSet,CXCursorSet,CXCursorSet,CXCursorSet,CXCursorSet,CXCursorSet,CXCursorSet,CXCursorSet"}

type CXCursorVisitor is Data:
  CXCursorVisitor{}

def ty_CXCursorVisitor() -> Ty: Ty{"CXCursorVisitor", "CXCursorVisitor,CXCursorVisitor"}

type CXCursorVisitorBlock is Data:
  CXCursorVisitorBlock{}

def ty_CXCursorVisitorBlock() -> Ty: Ty{"CXCursorVisitorBlock", "CXCursorVisitorBlock,CXCursorVisitorBlock,CXCursorVisitorBlock,CXCursorVisitorBlock"}

type CXEvalResult is Data:
  CXEvalResult{}

def ty_CXEvalResult() -> Ty: Ty{"CXEvalResult", "CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult,CXEvalResult"}

type CXFieldVisitor is Data:
  CXFieldVisitor{}

def ty_CXFieldVisitor() -> Ty: Ty{"CXFieldVisitor", "CXFieldVisitor,CXFieldVisitor,CXFieldVisitor,CXFieldVisitor"}

type CXFile is Data:
  CXFile{}

def ty_CXFile() -> Ty: Ty{"CXFile", "CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile,CXFile"}

type CXIdxClientContainer is Data:
  CXIdxClientContainer{}

def ty_CXIdxClientContainer() -> Ty: Ty{"CXIdxClientContainer", "CXIdxClientContainer,CXIdxClientContainer,CXIdxClientContainer,CXIdxClientContainer"}

type CXIdxClientEntity is Data:
  CXIdxClientEntity{}

def ty_CXIdxClientEntity() -> Ty: Ty{"CXIdxClientEntity", "CXIdxClientEntity,CXIdxClientEntity,CXIdxClientEntity,CXIdxClientEntity"}

type CXIdxLoc is Data:
  CXIdxLoc{}

def ty_CXIdxLoc() -> Ty: Ty{"CXIdxLoc", "CXIdxLoc,CXIdxLoc,CXIdxLoc,CXIdxLoc,CXIdxLoc,CXIdxLoc"}

type CXInclusionVisitor is Data:
  CXInclusionVisitor{}

def ty_CXInclusionVisitor() -> Ty: Ty{"CXInclusionVisitor", "CXInclusionVisitor,CXInclusionVisitor"}

type CXIndex is Data:
  CXIndex{}

def ty_CXIndex() -> Ty: Ty{"CXIndex", "CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex,CXIndex"}

type CXIndexAction is Data:
  CXIndexAction{}

def ty_CXIndexAction() -> Ty: Ty{"CXIndexAction", "CXIndexAction,CXIndexAction,CXIndexAction,CXIndexAction,CXIndexAction,CXIndexAction,CXIndexAction,CXIndexAction,CXIndexAction,CXIndexAction"}

type CXModule is Data:
  CXModule{}

def ty_CXModule() -> Ty: Ty{"CXModule", "CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule,CXModule"}

type CXPrintingPolicy is Data:
  CXPrintingPolicy{}

def ty_CXPrintingPolicy() -> Ty: Ty{"CXPrintingPolicy", "CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy,CXPrintingPolicy"}

type CXRemapping is Data:
  CXRemapping{}

def ty_CXRemapping() -> Ty: Ty{"CXRemapping", "CXRemapping,CXRemapping,CXRemapping,CXRemapping,CXRemapping,CXRemapping,CXRemapping,CXRemapping,CXRemapping,CXRemapping"}

type CXSourceLocation is Data:
  CXSourceLocation{}

def ty_CXSourceLocation() -> Ty: Ty{"CXSourceLocation", "CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation,CXSourceLocation"}

type CXSourceRange is Data:
  CXSourceRange{}

def ty_CXSourceRange() -> Ty: Ty{"CXSourceRange", "CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange,CXSourceRange"}

type CXString is Data:
  CXString{}

def ty_CXString() -> Ty: Ty{"CXString", "CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString,CXString"}

type CXTUResourceUsage is Data:
  CXTUResourceUsage{}

def ty_CXTUResourceUsage() -> Ty: Ty{"CXTUResourceUsage", "CXTUResourceUsage,CXTUResourceUsage,CXTUResourceUsage,CXTUResourceUsage"}

type CXTargetInfo is Data:
  CXTargetInfo{}

def ty_CXTargetInfo() -> Ty: Ty{"CXTargetInfo", "CXTargetInfo,CXTargetInfo,CXTargetInfo,CXTargetInfo,CXTargetInfo,CXTargetInfo,CXTargetInfo,CXTargetInfo,CXTargetInfo,CXTargetInfo,CXTargetInfo,CXTargetInfo"}

type CXToken is Data:
  CXToken{}

def ty_CXToken() -> Ty: Ty{"CXToken", "CXToken,CXToken,CXToken,CXToken,CXToken,CXToken,CXToken,CXToken,CXToken,CXToken,CXToken,CXToken,CXToken,CXToken,CXToken,CXToken"}

type CXTranslationUnit is Data:
  CXTranslationUnit{}

def ty_CXTranslationUnit() -> Ty: Ty{"CXTranslationUnit", "CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit,CXTranslationUnit"}

type CXType is Data:
  CXType{}

def ty_CXType() -> Ty: Ty{"CXType", "CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType,CXType"}

type Fn_Unit_CVoidP is Data:
  Fn_Unit_CVoidP{}

def ty_Fn_Unit_CVoidP() -> Ty: Ty{"Fn_Unit_CVoidP", "c.CFUNCTYPE[None, [ctypes.c_void_p]],c.CFUNCTYPE[None, [ctypes.c_void_p]]"}

type I32 is Data:
  I32{}

def ty_I32() -> Ty: Ty{"I32", "ctypes.c_int32,int,ctypes.c_int32,int,ctypes.c_int32,int,int,int,int,int,int,int,int,int,int,ctypes.c_int32,int,int,int,ctypes.c_int32,int,int,int,int,ctypes.c_int32,int,int,int,ctypes.c_int32,int,int,int,int,int,int,int,int,ctypes.c_int32,int,ctypes.c_int32,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,int,ctypes.c_int32,int,int,int,int,int,int,ctypes.c_int32,int,int,int,int,int,int"}

type Ptr_CChar is Data:
  Ptr_CChar{}

def ty_Ptr_CChar() -> Ty: Ty{"Ptr_CChar", "c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char],c.POINTER[ctypes.c_char]"}

type Ptr_CXCodeCompleteResults is Data:
  Ptr_CXCodeCompleteResults{}

def ty_Ptr_CXCodeCompleteResults() -> Ty: Ty{"Ptr_CXCodeCompleteResults", "c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults],c.POINTER[CXCodeCompleteResults]"}

type Ptr_CXCompletionResult is Data:
  Ptr_CXCompletionResult{}

def ty_Ptr_CXCompletionResult() -> Ty: Ty{"Ptr_CXCompletionResult", "c.POINTER[CXCompletionResult],c.POINTER[CXCompletionResult]"}

type Ptr_CXCursor is Data:
  Ptr_CXCursor{}

def ty_Ptr_CXCursor() -> Ty: Ty{"Ptr_CXCursor", "c.POINTER[CXCursor],c.POINTER[CXCursor],c.POINTER[CXCursor],c.POINTER[CXCursor],c.POINTER[CXCursor],c.POINTER[CXCursor],c.POINTER[CXCursor],c.POINTER[CXCursor]"}

type Ptr_CXFile is Data:
  Ptr_CXFile{}

def ty_Ptr_CXFile() -> Ty: Ty{"Ptr_CXFile", "c.POINTER[CXFile],c.POINTER[CXFile],c.POINTER[CXFile],c.POINTER[CXFile],c.POINTER[CXFile],c.POINTER[CXFile],c.POINTER[CXFile],c.POINTER[CXFile],c.POINTER[CXFile],c.POINTER[CXFile]"}

type Ptr_CXFileUniqueID is Data:
  Ptr_CXFileUniqueID{}

def ty_Ptr_CXFileUniqueID() -> Ty: Ty{"Ptr_CXFileUniqueID", "c.POINTER[CXFileUniqueID],c.POINTER[CXFileUniqueID],c.POINTER[CXFileUniqueID],c.POINTER[CXFileUniqueID]"}

type Ptr_CXIdxAttrInfo is Data:
  Ptr_CXIdxAttrInfo{}

def ty_Ptr_CXIdxAttrInfo() -> Ty: Ty{"Ptr_CXIdxAttrInfo", "c.POINTER[CXIdxAttrInfo],c.POINTER[CXIdxAttrInfo],c.POINTER[CXIdxAttrInfo],c.POINTER[CXIdxAttrInfo]"}

type Ptr_CXIdxClientFile is Data:
  Ptr_CXIdxClientFile{}

def ty_Ptr_CXIdxClientFile() -> Ty: Ty{"Ptr_CXIdxClientFile", "c.POINTER[CXIdxClientFile],c.POINTER[CXIdxClientFile]"}

type Ptr_CXIdxContainerInfo is Data:
  Ptr_CXIdxContainerInfo{}

def ty_Ptr_CXIdxContainerInfo() -> Ty: Ty{"Ptr_CXIdxContainerInfo", "c.POINTER[CXIdxContainerInfo],c.POINTER[CXIdxContainerInfo],c.POINTER[CXIdxContainerInfo],c.POINTER[CXIdxContainerInfo],c.POINTER[CXIdxContainerInfo],c.POINTER[CXIdxContainerInfo]"}

type Ptr_CXIdxDeclInfo is Data:
  Ptr_CXIdxDeclInfo{}

def ty_Ptr_CXIdxDeclInfo() -> Ty: Ty{"Ptr_CXIdxDeclInfo", "c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo],c.POINTER[CXIdxDeclInfo]"}

type Ptr_CXIdxEntityInfo is Data:
  Ptr_CXIdxEntityInfo{}

def ty_Ptr_CXIdxEntityInfo() -> Ty: Ty{"Ptr_CXIdxEntityInfo", "c.POINTER[CXIdxEntityInfo],c.POINTER[CXIdxEntityInfo],c.POINTER[CXIdxEntityInfo],c.POINTER[CXIdxEntityInfo],c.POINTER[CXIdxEntityInfo],c.POINTER[CXIdxEntityInfo]"}

type Ptr_CXIndexOptions is Data:
  Ptr_CXIndexOptions{}

def ty_Ptr_CXIndexOptions() -> Ty: Ty{"Ptr_CXIndexOptions", "c.POINTER[CXIndexOptions],c.POINTER[CXIndexOptions],c.POINTER[CXIndexOptions],c.POINTER[CXIndexOptions]"}

type Ptr_CXPlatformAvailability is Data:
  Ptr_CXPlatformAvailability{}

def ty_Ptr_CXPlatformAvailability() -> Ty: Ty{"Ptr_CXPlatformAvailability", "c.POINTER[CXPlatformAvailability],c.POINTER[CXPlatformAvailability],c.POINTER[CXPlatformAvailability],c.POINTER[CXPlatformAvailability],c.POINTER[CXPlatformAvailability],c.POINTER[CXPlatformAvailability]"}

type Ptr_CXSourceRange is Data:
  Ptr_CXSourceRange{}

def ty_Ptr_CXSourceRange() -> Ty: Ty{"Ptr_CXSourceRange", "c.POINTER[CXSourceRange],c.POINTER[CXSourceRange],c.POINTER[CXSourceRange],c.POINTER[CXSourceRange]"}

type Ptr_CXSourceRangeList is Data:
  Ptr_CXSourceRangeList{}

def ty_Ptr_CXSourceRangeList() -> Ty: Ty{"Ptr_CXSourceRangeList", "c.POINTER[CXSourceRangeList],c.POINTER[CXSourceRangeList],c.POINTER[CXSourceRangeList],c.POINTER[CXSourceRangeList]"}

type Ptr_CXString is Data:
  Ptr_CXString{}

def ty_Ptr_CXString() -> Ty: Ty{"Ptr_CXString", "c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString],c.POINTER[CXString]"}

type Ptr_CXStringSet is Data:
  Ptr_CXStringSet{}

def ty_Ptr_CXStringSet() -> Ty: Ty{"Ptr_CXStringSet", "c.POINTER[CXStringSet],c.POINTER[CXStringSet],c.POINTER[CXStringSet],c.POINTER[CXStringSet]"}

type Ptr_CXToken is Data:
  Ptr_CXToken{}

def ty_Ptr_CXToken() -> Ty: Ty{"Ptr_CXToken", "c.POINTER[CXToken],c.POINTER[CXToken],c.POINTER[CXToken],c.POINTER[CXToken]"}

type Ptr_CXTranslationUnit is Data:
  Ptr_CXTranslationUnit{}

def ty_Ptr_CXTranslationUnit() -> Ty: Ty{"Ptr_CXTranslationUnit", "c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit],c.POINTER[CXTranslationUnit]"}

type Ptr_I32 is Data:
  Ptr_I32{}

def ty_Ptr_I32() -> Ty: Ty{"Ptr_I32", "c.POINTER[ctypes.c_int32],c.POINTER[ctypes.c_int32],c.POINTER[ctypes.c_int32],c.POINTER[ctypes.c_int32]"}

type Ptr_IndexerCallbacks is Data:
  Ptr_IndexerCallbacks{}

def ty_Ptr_IndexerCallbacks() -> Ty: Ty{"Ptr_IndexerCallbacks", "c.POINTER[IndexerCallbacks],c.POINTER[IndexerCallbacks],c.POINTER[IndexerCallbacks],c.POINTER[IndexerCallbacks],c.POINTER[IndexerCallbacks],c.POINTER[IndexerCallbacks]"}

type Ptr_Ptr_CChar is Data:
  Ptr_Ptr_CChar{}

def ty_Ptr_Ptr_CChar() -> Ty: Ty{"Ptr_Ptr_CChar", "c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]],c.POINTER[c.POINTER[ctypes.c_char]]"}

type Ptr_Ptr_CXCursor is Data:
  Ptr_Ptr_CXCursor{}

def ty_Ptr_Ptr_CXCursor() -> Ty: Ty{"Ptr_Ptr_CXCursor", "c.POINTER[c.POINTER[CXCursor]],c.POINTER[c.POINTER[CXCursor]]"}

type Ptr_Ptr_CXToken is Data:
  Ptr_Ptr_CXToken{}

def ty_Ptr_Ptr_CXToken() -> Ty: Ty{"Ptr_Ptr_CXToken", "c.POINTER[c.POINTER[CXToken]],c.POINTER[c.POINTER[CXToken]]"}

type Ptr_U32 is Data:
  Ptr_U32{}

def ty_Ptr_U32() -> Ty: Ty{"Ptr_U32", "c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32],c.POINTER[ctypes.c_uint32]"}

type Ptr_U64 is Data:
  Ptr_U64{}

def ty_Ptr_U64() -> Ty: Ty{"Ptr_U64", "c.POINTER[size_t],c.POINTER[size_t],c.POINTER[size_t],c.POINTER[size_t]"}

type Ptr_struct_CXUnsavedFile is Data:
  Ptr_struct_CXUnsavedFile{}

def ty_Ptr_struct_CXUnsavedFile() -> Ty: Ty{"Ptr_struct_CXUnsavedFile", "c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile],c.POINTER[struct_CXUnsavedFile]"}

def ty_U32() -> Ty: Ty{"U32", "ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32"}

def ty_Unit() -> Ty: Ty{"Unit", "None,None"}

law clang_createIndex:
  I32 -> I32 -> IO(CXIndex)

def clang_createIndex(excludeDeclarationsFromPCH, displayDiagnostics):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeIndex:
  CXIndex -> IO(Unit)

def clang_disposeIndex(index):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_createIndexWithOptions:
  Ptr_CXIndexOptions -> IO(CXIndex)

def clang_createIndexWithOptions(options):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXIndex_setGlobalOptions:
  CXIndex -> U32 -> IO(Unit)

def clang_CXIndex_setGlobalOptions(_0, options):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXIndex_getGlobalOptions:
  CXIndex -> IO(U32)

def clang_CXIndex_getGlobalOptions(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXIndex_setInvocationEmissionPathOption:
  CXIndex -> Ptr_CChar -> IO(Unit)

def clang_CXIndex_setInvocationEmissionPathOption(_0, Path):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isFileMultipleIncludeGuarded:
  CXTranslationUnit -> CXFile -> IO(U32)

def clang_isFileMultipleIncludeGuarded(tu, file):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getFile:
  CXTranslationUnit -> Ptr_CChar -> IO(CXFile)

def clang_getFile(tu, file_name):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getFileContents:
  CXTranslationUnit -> CXFile -> Ptr_U64 -> IO(Ptr_CChar)

def clang_getFileContents(tu, file, size):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getLocation:
  CXTranslationUnit -> CXFile -> U32 -> U32 -> IO(CXSourceLocation)

def clang_getLocation(tu, file, line, column):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getLocationForOffset:
  CXTranslationUnit -> CXFile -> U32 -> IO(CXSourceLocation)

def clang_getLocationForOffset(tu, file, offset):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getSkippedRanges:
  CXTranslationUnit -> CXFile -> IO(Ptr_CXSourceRangeList)

def clang_getSkippedRanges(tu, file):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getAllSkippedRanges:
  CXTranslationUnit -> IO(Ptr_CXSourceRangeList)

def clang_getAllSkippedRanges(tu):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getNumDiagnostics:
  CXTranslationUnit -> IO(U32)

def clang_getNumDiagnostics(Unit):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getDiagnostic:
  CXTranslationUnit -> U32 -> IO(CXDiagnostic)

def clang_getDiagnostic(Unit, Index):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getDiagnosticSetFromTU:
  CXTranslationUnit -> IO(CXDiagnosticSet)

def clang_getDiagnosticSetFromTU(Unit):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTranslationUnitSpelling:
  CXTranslationUnit -> IO(CXString)

def clang_getTranslationUnitSpelling(CTUnit):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_createTranslationUnitFromSourceFile:
  CXIndex -> Ptr_CChar -> I32 -> Ptr_Ptr_CChar -> U32 -> Ptr_struct_CXUnsavedFile -> IO(CXTranslationUnit)

def clang_createTranslationUnitFromSourceFile(CIdx, source_filename, num_clang_command_line_args, clang_command_line_args, num_unsaved_files, unsaved_files):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_createTranslationUnit:
  CXIndex -> Ptr_CChar -> IO(CXTranslationUnit)

def clang_createTranslationUnit(CIdx, ast_filename):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_createTranslationUnit2:
  CXIndex -> Ptr_CChar -> Ptr_CXTranslationUnit -> IO(U32)

def clang_createTranslationUnit2(CIdx, ast_filename, out_TU):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_defaultEditingTranslationUnitOptions:
  IO(U32)

def clang_defaultEditingTranslationUnitOptions():
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_parseTranslationUnit:
  CXIndex -> Ptr_CChar -> Ptr_Ptr_CChar -> I32 -> Ptr_struct_CXUnsavedFile -> U32 -> U32 -> IO(CXTranslationUnit)

def clang_parseTranslationUnit(CIdx, source_filename, command_line_args, num_command_line_args, unsaved_files, num_unsaved_files, options):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_parseTranslationUnit2:
  CXIndex -> Ptr_CChar -> Ptr_Ptr_CChar -> I32 -> Ptr_struct_CXUnsavedFile -> U32 -> U32 -> Ptr_CXTranslationUnit -> IO(U32)

def clang_parseTranslationUnit2(CIdx, source_filename, command_line_args, num_command_line_args, unsaved_files, num_unsaved_files, options, out_TU):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_parseTranslationUnit2FullArgv:
  CXIndex -> Ptr_CChar -> Ptr_Ptr_CChar -> I32 -> Ptr_struct_CXUnsavedFile -> U32 -> U32 -> Ptr_CXTranslationUnit -> IO(U32)

def clang_parseTranslationUnit2FullArgv(CIdx, source_filename, command_line_args, num_command_line_args, unsaved_files, num_unsaved_files, options, out_TU):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_defaultSaveOptions:
  CXTranslationUnit -> IO(U32)

def clang_defaultSaveOptions(TU):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_saveTranslationUnit:
  CXTranslationUnit -> Ptr_CChar -> U32 -> IO(I32)

def clang_saveTranslationUnit(TU, FileName, options):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_suspendTranslationUnit:
  CXTranslationUnit -> IO(U32)

def clang_suspendTranslationUnit(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeTranslationUnit:
  CXTranslationUnit -> IO(Unit)

def clang_disposeTranslationUnit(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_defaultReparseOptions:
  CXTranslationUnit -> IO(U32)

def clang_defaultReparseOptions(TU):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_reparseTranslationUnit:
  CXTranslationUnit -> U32 -> Ptr_struct_CXUnsavedFile -> U32 -> IO(I32)

def clang_reparseTranslationUnit(TU, num_unsaved_files, unsaved_files, options):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTUResourceUsageName:
  U32 -> IO(Ptr_CChar)

def clang_getTUResourceUsageName(kind):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCXTUResourceUsage:
  CXTranslationUnit -> IO(CXTUResourceUsage)

def clang_getCXTUResourceUsage(TU):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeCXTUResourceUsage:
  CXTUResourceUsage -> IO(Unit)

def clang_disposeCXTUResourceUsage(usage):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTranslationUnitTargetInfo:
  CXTranslationUnit -> IO(CXTargetInfo)

def clang_getTranslationUnitTargetInfo(CTUnit):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_TargetInfo_dispose:
  CXTargetInfo -> IO(Unit)

def clang_TargetInfo_dispose(Info):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_TargetInfo_getTriple:
  CXTargetInfo -> IO(CXString)

def clang_TargetInfo_getTriple(Info):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_TargetInfo_getPointerWidth:
  CXTargetInfo -> IO(I32)

def clang_TargetInfo_getPointerWidth(Info):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getNullCursor:
  IO(CXCursor)

def clang_getNullCursor():
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTranslationUnitCursor:
  CXTranslationUnit -> IO(CXCursor)

def clang_getTranslationUnitCursor(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_equalCursors:
  CXCursor -> CXCursor -> IO(U32)

def clang_equalCursors(_0, _1):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isNull:
  CXCursor -> IO(I32)

def clang_Cursor_isNull(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_hashCursor:
  CXCursor -> IO(U32)

def clang_hashCursor(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorKind:
  CXCursor -> IO(U32)

def clang_getCursorKind(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isDeclaration:
  U32 -> IO(U32)

def clang_isDeclaration(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isInvalidDeclaration:
  CXCursor -> IO(U32)

def clang_isInvalidDeclaration(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isReference:
  U32 -> IO(U32)

def clang_isReference(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isExpression:
  U32 -> IO(U32)

def clang_isExpression(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isStatement:
  U32 -> IO(U32)

def clang_isStatement(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isAttribute:
  U32 -> IO(U32)

def clang_isAttribute(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_hasAttrs:
  CXCursor -> IO(U32)

def clang_Cursor_hasAttrs(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isInvalid:
  U32 -> IO(U32)

def clang_isInvalid(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isTranslationUnit:
  U32 -> IO(U32)

def clang_isTranslationUnit(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isPreprocessing:
  U32 -> IO(U32)

def clang_isPreprocessing(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isUnexposed:
  U32 -> IO(U32)

def clang_isUnexposed(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorLinkage:
  CXCursor -> IO(U32)

def clang_getCursorLinkage(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorVisibility:
  CXCursor -> IO(U32)

def clang_getCursorVisibility(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorAvailability:
  CXCursor -> IO(U32)

def clang_getCursorAvailability(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorPlatformAvailability:
  CXCursor -> Ptr_I32 -> Ptr_CXString -> Ptr_I32 -> Ptr_CXString -> Ptr_CXPlatformAvailability -> I32 -> IO(I32)

def clang_getCursorPlatformAvailability(cursor, always_deprecated, deprecated_message, always_unavailable, unavailable_message, availability, availability_size):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeCXPlatformAvailability:
  Ptr_CXPlatformAvailability -> IO(Unit)

def clang_disposeCXPlatformAvailability(availability):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getVarDeclInitializer:
  CXCursor -> IO(CXCursor)

def clang_Cursor_getVarDeclInitializer(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_hasVarDeclGlobalStorage:
  CXCursor -> IO(I32)

def clang_Cursor_hasVarDeclGlobalStorage(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_hasVarDeclExternalStorage:
  CXCursor -> IO(I32)

def clang_Cursor_hasVarDeclExternalStorage(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorLanguage:
  CXCursor -> IO(U32)

def clang_getCursorLanguage(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorTLSKind:
  CXCursor -> IO(U32)

def clang_getCursorTLSKind(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getTranslationUnit:
  CXCursor -> IO(CXTranslationUnit)

def clang_Cursor_getTranslationUnit(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_createCXCursorSet:
  IO(CXCursorSet)

def clang_createCXCursorSet():
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeCXCursorSet:
  CXCursorSet -> IO(Unit)

def clang_disposeCXCursorSet(cset):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXCursorSet_contains:
  CXCursorSet -> CXCursor -> IO(U32)

def clang_CXCursorSet_contains(cset, cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXCursorSet_insert:
  CXCursorSet -> CXCursor -> IO(U32)

def clang_CXCursorSet_insert(cset, cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorSemanticParent:
  CXCursor -> IO(CXCursor)

def clang_getCursorSemanticParent(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorLexicalParent:
  CXCursor -> IO(CXCursor)

def clang_getCursorLexicalParent(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getOverriddenCursors:
  CXCursor -> Ptr_Ptr_CXCursor -> Ptr_U32 -> IO(Unit)

def clang_getOverriddenCursors(cursor, overridden, num_overridden):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeOverriddenCursors:
  Ptr_CXCursor -> IO(Unit)

def clang_disposeOverriddenCursors(overridden):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getIncludedFile:
  CXCursor -> IO(CXFile)

def clang_getIncludedFile(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursor:
  CXTranslationUnit -> CXSourceLocation -> IO(CXCursor)

def clang_getCursor(_0, _1):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorLocation:
  CXCursor -> IO(CXSourceLocation)

def clang_getCursorLocation(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorExtent:
  CXCursor -> IO(CXSourceRange)

def clang_getCursorExtent(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorType:
  CXCursor -> IO(CXType)

def clang_getCursorType(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTypeSpelling:
  CXType -> IO(CXString)

def clang_getTypeSpelling(CT):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTypedefDeclUnderlyingType:
  CXCursor -> IO(CXType)

def clang_getTypedefDeclUnderlyingType(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getEnumDeclIntegerType:
  CXCursor -> IO(CXType)

def clang_getEnumDeclIntegerType(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getEnumConstantDeclValue:
  CXCursor -> IO(I64)

def clang_getEnumConstantDeclValue(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getEnumConstantDeclUnsignedValue:
  CXCursor -> IO(U64)

def clang_getEnumConstantDeclUnsignedValue(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isBitField:
  CXCursor -> IO(U32)

def clang_Cursor_isBitField(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getFieldDeclBitWidth:
  CXCursor -> IO(I32)

def clang_getFieldDeclBitWidth(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getNumArguments:
  CXCursor -> IO(I32)

def clang_Cursor_getNumArguments(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getArgument:
  CXCursor -> U32 -> IO(CXCursor)

def clang_Cursor_getArgument(C, i):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getNumTemplateArguments:
  CXCursor -> IO(I32)

def clang_Cursor_getNumTemplateArguments(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getTemplateArgumentKind:
  CXCursor -> U32 -> IO(U32)

def clang_Cursor_getTemplateArgumentKind(C, I):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getTemplateArgumentType:
  CXCursor -> U32 -> IO(CXType)

def clang_Cursor_getTemplateArgumentType(C, I):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getTemplateArgumentValue:
  CXCursor -> U32 -> IO(I64)

def clang_Cursor_getTemplateArgumentValue(C, I):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getTemplateArgumentUnsignedValue:
  CXCursor -> U32 -> IO(U64)

def clang_Cursor_getTemplateArgumentUnsignedValue(C, I):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_equalTypes:
  CXType -> CXType -> IO(U32)

def clang_equalTypes(A, B):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCanonicalType:
  CXType -> IO(CXType)

def clang_getCanonicalType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isConstQualifiedType:
  CXType -> IO(U32)

def clang_isConstQualifiedType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isMacroFunctionLike:
  CXCursor -> IO(U32)

def clang_Cursor_isMacroFunctionLike(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isMacroBuiltin:
  CXCursor -> IO(U32)

def clang_Cursor_isMacroBuiltin(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isFunctionInlined:
  CXCursor -> IO(U32)

def clang_Cursor_isFunctionInlined(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isVolatileQualifiedType:
  CXType -> IO(U32)

def clang_isVolatileQualifiedType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isRestrictQualifiedType:
  CXType -> IO(U32)

def clang_isRestrictQualifiedType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getAddressSpace:
  CXType -> IO(U32)

def clang_getAddressSpace(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTypedefName:
  CXType -> IO(CXString)

def clang_getTypedefName(CT):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getPointeeType:
  CXType -> IO(CXType)

def clang_getPointeeType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getUnqualifiedType:
  CXType -> IO(CXType)

def clang_getUnqualifiedType(CT):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getNonReferenceType:
  CXType -> IO(CXType)

def clang_getNonReferenceType(CT):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTypeDeclaration:
  CXType -> IO(CXCursor)

def clang_getTypeDeclaration(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getDeclObjCTypeEncoding:
  CXCursor -> IO(CXString)

def clang_getDeclObjCTypeEncoding(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getObjCEncoding:
  CXType -> IO(CXString)

def clang_Type_getObjCEncoding(_type):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTypeKindSpelling:
  U32 -> IO(CXString)

def clang_getTypeKindSpelling(K):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getFunctionTypeCallingConv:
  CXType -> IO(U32)

def clang_getFunctionTypeCallingConv(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getResultType:
  CXType -> IO(CXType)

def clang_getResultType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getExceptionSpecificationType:
  CXType -> IO(I32)

def clang_getExceptionSpecificationType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getNumArgTypes:
  CXType -> IO(I32)

def clang_getNumArgTypes(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getArgType:
  CXType -> U32 -> IO(CXType)

def clang_getArgType(T, i):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getObjCObjectBaseType:
  CXType -> IO(CXType)

def clang_Type_getObjCObjectBaseType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getNumObjCProtocolRefs:
  CXType -> IO(U32)

def clang_Type_getNumObjCProtocolRefs(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getObjCProtocolDecl:
  CXType -> U32 -> IO(CXCursor)

def clang_Type_getObjCProtocolDecl(T, i):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getNumObjCTypeArgs:
  CXType -> IO(U32)

def clang_Type_getNumObjCTypeArgs(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getObjCTypeArg:
  CXType -> U32 -> IO(CXType)

def clang_Type_getObjCTypeArg(T, i):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isFunctionTypeVariadic:
  CXType -> IO(U32)

def clang_isFunctionTypeVariadic(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorResultType:
  CXCursor -> IO(CXType)

def clang_getCursorResultType(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorExceptionSpecificationType:
  CXCursor -> IO(I32)

def clang_getCursorExceptionSpecificationType(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isPODType:
  CXType -> IO(U32)

def clang_isPODType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getElementType:
  CXType -> IO(CXType)

def clang_getElementType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getNumElements:
  CXType -> IO(I64)

def clang_getNumElements(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getArrayElementType:
  CXType -> IO(CXType)

def clang_getArrayElementType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getArraySize:
  CXType -> IO(I64)

def clang_getArraySize(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getNamedType:
  CXType -> IO(CXType)

def clang_Type_getNamedType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_isTransparentTagTypedef:
  CXType -> IO(U32)

def clang_Type_isTransparentTagTypedef(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getNullability:
  CXType -> IO(U32)

def clang_Type_getNullability(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getAlignOf:
  CXType -> IO(I64)

def clang_Type_getAlignOf(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getClassType:
  CXType -> IO(CXType)

def clang_Type_getClassType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getSizeOf:
  CXType -> IO(I64)

def clang_Type_getSizeOf(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getOffsetOf:
  CXType -> Ptr_CChar -> IO(I64)

def clang_Type_getOffsetOf(T, S):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getModifiedType:
  CXType -> IO(CXType)

def clang_Type_getModifiedType(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getValueType:
  CXType -> IO(CXType)

def clang_Type_getValueType(CT):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getOffsetOfField:
  CXCursor -> IO(I64)

def clang_Cursor_getOffsetOfField(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isAnonymous:
  CXCursor -> IO(U32)

def clang_Cursor_isAnonymous(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isAnonymousRecordDecl:
  CXCursor -> IO(U32)

def clang_Cursor_isAnonymousRecordDecl(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isInlineNamespace:
  CXCursor -> IO(U32)

def clang_Cursor_isInlineNamespace(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getNumTemplateArguments:
  CXType -> IO(I32)

def clang_Type_getNumTemplateArguments(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getTemplateArgumentAsType:
  CXType -> U32 -> IO(CXType)

def clang_Type_getTemplateArgumentAsType(T, i):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_getCXXRefQualifier:
  CXType -> IO(U32)

def clang_Type_getCXXRefQualifier(T):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isVirtualBase:
  CXCursor -> IO(U32)

def clang_isVirtualBase(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getOffsetOfBase:
  CXCursor -> CXCursor -> IO(I64)

def clang_getOffsetOfBase(Parent, Base):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCXXAccessSpecifier:
  CXCursor -> IO(U32)

def clang_getCXXAccessSpecifier(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getBinaryOpcode:
  CXCursor -> IO(U32)

def clang_Cursor_getBinaryOpcode(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getBinaryOpcodeStr:
  U32 -> IO(CXString)

def clang_Cursor_getBinaryOpcodeStr(Op):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getStorageClass:
  CXCursor -> IO(U32)

def clang_Cursor_getStorageClass(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getNumOverloadedDecls:
  CXCursor -> IO(U32)

def clang_getNumOverloadedDecls(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getOverloadedDecl:
  CXCursor -> U32 -> IO(CXCursor)

def clang_getOverloadedDecl(cursor, index):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getIBOutletCollectionType:
  CXCursor -> IO(CXType)

def clang_getIBOutletCollectionType(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_visitChildren:
  CXCursor -> CXCursorVisitor -> CXClientData -> IO(U32)

def clang_visitChildren(parent, visitor, client_data):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_visitChildrenWithBlock:
  CXCursor -> CXCursorVisitorBlock -> IO(U32)

def clang_visitChildrenWithBlock(parent, block):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorUSR:
  CXCursor -> IO(CXString)

def clang_getCursorUSR(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_constructUSR_ObjCClass:
  Ptr_CChar -> IO(CXString)

def clang_constructUSR_ObjCClass(class_name):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_constructUSR_ObjCCategory:
  Ptr_CChar -> Ptr_CChar -> IO(CXString)

def clang_constructUSR_ObjCCategory(class_name, category_name):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_constructUSR_ObjCProtocol:
  Ptr_CChar -> IO(CXString)

def clang_constructUSR_ObjCProtocol(protocol_name):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_constructUSR_ObjCIvar:
  Ptr_CChar -> CXString -> IO(CXString)

def clang_constructUSR_ObjCIvar(name, classUSR):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_constructUSR_ObjCMethod:
  Ptr_CChar -> U32 -> CXString -> IO(CXString)

def clang_constructUSR_ObjCMethod(name, isInstanceMethod, classUSR):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_constructUSR_ObjCProperty:
  Ptr_CChar -> CXString -> IO(CXString)

def clang_constructUSR_ObjCProperty(property, classUSR):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorSpelling:
  CXCursor -> IO(CXString)

def clang_getCursorSpelling(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getSpellingNameRange:
  CXCursor -> U32 -> U32 -> IO(CXSourceRange)

def clang_Cursor_getSpellingNameRange(_0, pieceIndex, options):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_PrintingPolicy_getProperty:
  CXPrintingPolicy -> U32 -> IO(U32)

def clang_PrintingPolicy_getProperty(Policy, Property):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_PrintingPolicy_setProperty:
  CXPrintingPolicy -> U32 -> U32 -> IO(Unit)

def clang_PrintingPolicy_setProperty(Policy, Property, Value):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorPrintingPolicy:
  CXCursor -> IO(CXPrintingPolicy)

def clang_getCursorPrintingPolicy(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_PrintingPolicy_dispose:
  CXPrintingPolicy -> IO(Unit)

def clang_PrintingPolicy_dispose(Policy):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorPrettyPrinted:
  CXCursor -> CXPrintingPolicy -> IO(CXString)

def clang_getCursorPrettyPrinted(Cursor, Policy):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTypePrettyPrinted:
  CXType -> CXPrintingPolicy -> IO(CXString)

def clang_getTypePrettyPrinted(CT, cxPolicy):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorDisplayName:
  CXCursor -> IO(CXString)

def clang_getCursorDisplayName(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorReferenced:
  CXCursor -> IO(CXCursor)

def clang_getCursorReferenced(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorDefinition:
  CXCursor -> IO(CXCursor)

def clang_getCursorDefinition(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isCursorDefinition:
  CXCursor -> IO(U32)

def clang_isCursorDefinition(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCanonicalCursor:
  CXCursor -> IO(CXCursor)

def clang_getCanonicalCursor(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getObjCSelectorIndex:
  CXCursor -> IO(I32)

def clang_Cursor_getObjCSelectorIndex(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isDynamicCall:
  CXCursor -> IO(I32)

def clang_Cursor_isDynamicCall(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getReceiverType:
  CXCursor -> IO(CXType)

def clang_Cursor_getReceiverType(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getObjCPropertyAttributes:
  CXCursor -> U32 -> IO(U32)

def clang_Cursor_getObjCPropertyAttributes(C, reserved):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getObjCPropertyGetterName:
  CXCursor -> IO(CXString)

def clang_Cursor_getObjCPropertyGetterName(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getObjCPropertySetterName:
  CXCursor -> IO(CXString)

def clang_Cursor_getObjCPropertySetterName(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getObjCDeclQualifiers:
  CXCursor -> IO(U32)

def clang_Cursor_getObjCDeclQualifiers(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isObjCOptional:
  CXCursor -> IO(U32)

def clang_Cursor_isObjCOptional(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isVariadic:
  CXCursor -> IO(U32)

def clang_Cursor_isVariadic(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_isExternalSymbol:
  CXCursor -> Ptr_CXString -> Ptr_CXString -> Ptr_U32 -> IO(U32)

def clang_Cursor_isExternalSymbol(C, language, definedIn, isGenerated):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getCommentRange:
  CXCursor -> IO(CXSourceRange)

def clang_Cursor_getCommentRange(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getRawCommentText:
  CXCursor -> IO(CXString)

def clang_Cursor_getRawCommentText(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getBriefCommentText:
  CXCursor -> IO(CXString)

def clang_Cursor_getBriefCommentText(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getMangling:
  CXCursor -> IO(CXString)

def clang_Cursor_getMangling(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getCXXManglings:
  CXCursor -> IO(Ptr_CXStringSet)

def clang_Cursor_getCXXManglings(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getObjCManglings:
  CXCursor -> IO(Ptr_CXStringSet)

def clang_Cursor_getObjCManglings(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_getModule:
  CXCursor -> IO(CXModule)

def clang_Cursor_getModule(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getModuleForFile:
  CXTranslationUnit -> CXFile -> IO(CXModule)

def clang_getModuleForFile(_0, _1):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Module_getASTFile:
  CXModule -> IO(CXFile)

def clang_Module_getASTFile(Module):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Module_getParent:
  CXModule -> IO(CXModule)

def clang_Module_getParent(Module):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Module_getName:
  CXModule -> IO(CXString)

def clang_Module_getName(Module):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Module_getFullName:
  CXModule -> IO(CXString)

def clang_Module_getFullName(Module):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Module_isSystem:
  CXModule -> IO(I32)

def clang_Module_isSystem(Module):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Module_getNumTopLevelHeaders:
  CXTranslationUnit -> CXModule -> IO(U32)

def clang_Module_getNumTopLevelHeaders(_0, Module):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Module_getTopLevelHeader:
  CXTranslationUnit -> CXModule -> U32 -> IO(CXFile)

def clang_Module_getTopLevelHeader(_0, Module, Index):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXConstructor_isConvertingConstructor:
  CXCursor -> IO(U32)

def clang_CXXConstructor_isConvertingConstructor(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXConstructor_isCopyConstructor:
  CXCursor -> IO(U32)

def clang_CXXConstructor_isCopyConstructor(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXConstructor_isDefaultConstructor:
  CXCursor -> IO(U32)

def clang_CXXConstructor_isDefaultConstructor(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXConstructor_isMoveConstructor:
  CXCursor -> IO(U32)

def clang_CXXConstructor_isMoveConstructor(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXField_isMutable:
  CXCursor -> IO(U32)

def clang_CXXField_isMutable(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXMethod_isDefaulted:
  CXCursor -> IO(U32)

def clang_CXXMethod_isDefaulted(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXMethod_isDeleted:
  CXCursor -> IO(U32)

def clang_CXXMethod_isDeleted(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXMethod_isPureVirtual:
  CXCursor -> IO(U32)

def clang_CXXMethod_isPureVirtual(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXMethod_isStatic:
  CXCursor -> IO(U32)

def clang_CXXMethod_isStatic(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXMethod_isVirtual:
  CXCursor -> IO(U32)

def clang_CXXMethod_isVirtual(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXMethod_isCopyAssignmentOperator:
  CXCursor -> IO(U32)

def clang_CXXMethod_isCopyAssignmentOperator(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXMethod_isMoveAssignmentOperator:
  CXCursor -> IO(U32)

def clang_CXXMethod_isMoveAssignmentOperator(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXMethod_isExplicit:
  CXCursor -> IO(U32)

def clang_CXXMethod_isExplicit(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXRecord_isAbstract:
  CXCursor -> IO(U32)

def clang_CXXRecord_isAbstract(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_EnumDecl_isScoped:
  CXCursor -> IO(U32)

def clang_EnumDecl_isScoped(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_CXXMethod_isConst:
  CXCursor -> IO(U32)

def clang_CXXMethod_isConst(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTemplateCursorKind:
  CXCursor -> IO(U32)

def clang_getTemplateCursorKind(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getSpecializedCursorTemplate:
  CXCursor -> IO(CXCursor)

def clang_getSpecializedCursorTemplate(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorReferenceNameRange:
  CXCursor -> U32 -> U32 -> IO(CXSourceRange)

def clang_getCursorReferenceNameRange(C, NameFlags, PieceIndex):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getToken:
  CXTranslationUnit -> CXSourceLocation -> IO(Ptr_CXToken)

def clang_getToken(TU, Location):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTokenKind:
  CXToken -> IO(CXTokenKind)

def clang_getTokenKind(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTokenSpelling:
  CXTranslationUnit -> CXToken -> IO(CXString)

def clang_getTokenSpelling(_0, _1):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTokenLocation:
  CXTranslationUnit -> CXToken -> IO(CXSourceLocation)

def clang_getTokenLocation(_0, _1):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getTokenExtent:
  CXTranslationUnit -> CXToken -> IO(CXSourceRange)

def clang_getTokenExtent(_0, _1):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_tokenize:
  CXTranslationUnit -> CXSourceRange -> Ptr_Ptr_CXToken -> Ptr_U32 -> IO(Unit)

def clang_tokenize(TU, Range, Tokens, NumTokens):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_annotateTokens:
  CXTranslationUnit -> Ptr_CXToken -> U32 -> Ptr_CXCursor -> IO(Unit)

def clang_annotateTokens(TU, Tokens, NumTokens, Cursors):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeTokens:
  CXTranslationUnit -> Ptr_CXToken -> U32 -> IO(Unit)

def clang_disposeTokens(TU, Tokens, NumTokens):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorKindSpelling:
  U32 -> IO(CXString)

def clang_getCursorKindSpelling(_Kind):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getDefinitionSpellingAndExtent:
  CXCursor -> Ptr_Ptr_CChar -> Ptr_Ptr_CChar -> Ptr_U32 -> Ptr_U32 -> Ptr_U32 -> Ptr_U32 -> IO(Unit)

def clang_getDefinitionSpellingAndExtent(_0, startBuf, endBuf, startLine, startColumn, endLine, endColumn):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_enableStackTraces:
  IO(Unit)

def clang_enableStackTraces():
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_executeOnThread:
  Fn_Unit_CVoidP -> CVoidP -> U32 -> IO(Unit)

def clang_executeOnThread(fn, user_data, stack_size):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionChunkKind:
  CXCompletionString -> U32 -> IO(U32)

def clang_getCompletionChunkKind(completion_string, chunk_number):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionChunkText:
  CXCompletionString -> U32 -> IO(CXString)

def clang_getCompletionChunkText(completion_string, chunk_number):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionChunkCompletionString:
  CXCompletionString -> U32 -> IO(CXCompletionString)

def clang_getCompletionChunkCompletionString(completion_string, chunk_number):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getNumCompletionChunks:
  CXCompletionString -> IO(U32)

def clang_getNumCompletionChunks(completion_string):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionPriority:
  CXCompletionString -> IO(U32)

def clang_getCompletionPriority(completion_string):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionAvailability:
  CXCompletionString -> IO(U32)

def clang_getCompletionAvailability(completion_string):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionNumAnnotations:
  CXCompletionString -> IO(U32)

def clang_getCompletionNumAnnotations(completion_string):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionAnnotation:
  CXCompletionString -> U32 -> IO(CXString)

def clang_getCompletionAnnotation(completion_string, annotation_number):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionParent:
  CXCompletionString -> Ptr_U32 -> IO(CXString)

def clang_getCompletionParent(completion_string, kind):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionBriefComment:
  CXCompletionString -> IO(CXString)

def clang_getCompletionBriefComment(completion_string):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorCompletionString:
  CXCursor -> IO(CXCompletionString)

def clang_getCursorCompletionString(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionNumFixIts:
  Ptr_CXCodeCompleteResults -> U32 -> IO(U32)

def clang_getCompletionNumFixIts(results, completion_index):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCompletionFixIt:
  Ptr_CXCodeCompleteResults -> U32 -> U32 -> Ptr_CXSourceRange -> IO(CXString)

def clang_getCompletionFixIt(results, completion_index, fixit_index, replacement_range):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_defaultCodeCompleteOptions:
  IO(U32)

def clang_defaultCodeCompleteOptions():
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_codeCompleteAt:
  CXTranslationUnit -> Ptr_CChar -> U32 -> U32 -> Ptr_struct_CXUnsavedFile -> U32 -> U32 -> IO(Ptr_CXCodeCompleteResults)

def clang_codeCompleteAt(TU, complete_filename, complete_line, complete_column, unsaved_files, num_unsaved_files, options):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_sortCodeCompletionResults:
  Ptr_CXCompletionResult -> U32 -> IO(Unit)

def clang_sortCodeCompletionResults(Results, NumResults):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeCodeCompleteResults:
  Ptr_CXCodeCompleteResults -> IO(Unit)

def clang_disposeCodeCompleteResults(Results):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_codeCompleteGetNumDiagnostics:
  Ptr_CXCodeCompleteResults -> IO(U32)

def clang_codeCompleteGetNumDiagnostics(Results):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_codeCompleteGetDiagnostic:
  Ptr_CXCodeCompleteResults -> U32 -> IO(CXDiagnostic)

def clang_codeCompleteGetDiagnostic(Results, Index):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_codeCompleteGetContexts:
  Ptr_CXCodeCompleteResults -> IO(U64)

def clang_codeCompleteGetContexts(Results):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_codeCompleteGetContainerKind:
  Ptr_CXCodeCompleteResults -> Ptr_U32 -> IO(U32)

def clang_codeCompleteGetContainerKind(Results, IsIncomplete):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_codeCompleteGetContainerUSR:
  Ptr_CXCodeCompleteResults -> IO(CXString)

def clang_codeCompleteGetContainerUSR(Results):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_codeCompleteGetObjCSelector:
  Ptr_CXCodeCompleteResults -> IO(CXString)

def clang_codeCompleteGetObjCSelector(Results):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getClangVersion:
  IO(CXString)

def clang_getClangVersion():
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_toggleCrashRecovery:
  U32 -> IO(Unit)

def clang_toggleCrashRecovery(isEnabled):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getInclusions:
  CXTranslationUnit -> CXInclusionVisitor -> CXClientData -> IO(Unit)

def clang_getInclusions(tu, visitor, client_data):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Cursor_Evaluate:
  CXCursor -> IO(CXEvalResult)

def clang_Cursor_Evaluate(C):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_EvalResult_getKind:
  CXEvalResult -> IO(U32)

def clang_EvalResult_getKind(E):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_EvalResult_getAsInt:
  CXEvalResult -> IO(I32)

def clang_EvalResult_getAsInt(E):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_EvalResult_getAsLongLong:
  CXEvalResult -> IO(I64)

def clang_EvalResult_getAsLongLong(E):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_EvalResult_isUnsignedInt:
  CXEvalResult -> IO(U32)

def clang_EvalResult_isUnsignedInt(E):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_EvalResult_getAsUnsigned:
  CXEvalResult -> IO(U64)

def clang_EvalResult_getAsUnsigned(E):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_EvalResult_getAsDouble:
  CXEvalResult -> IO(F64)

def clang_EvalResult_getAsDouble(E):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_EvalResult_getAsStr:
  CXEvalResult -> IO(Ptr_CChar)

def clang_EvalResult_getAsStr(E):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_EvalResult_dispose:
  CXEvalResult -> IO(Unit)

def clang_EvalResult_dispose(E):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getRemappings:
  Ptr_CChar -> IO(CXRemapping)

def clang_getRemappings(path):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getRemappingsFromFileList:
  Ptr_Ptr_CChar -> U32 -> IO(CXRemapping)

def clang_getRemappingsFromFileList(filePaths, numFiles):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_remap_getNumFiles:
  CXRemapping -> IO(U32)

def clang_remap_getNumFiles(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_remap_getFilenames:
  CXRemapping -> U32 -> Ptr_CXString -> Ptr_CXString -> IO(Unit)

def clang_remap_getFilenames(_0, index, original, transformed):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_remap_dispose:
  CXRemapping -> IO(Unit)

def clang_remap_dispose(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_findReferencesInFile:
  CXCursor -> CXFile -> CXCursorAndRangeVisitor -> IO(U32)

def clang_findReferencesInFile(cursor, file, visitor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_findIncludesInFile:
  CXTranslationUnit -> CXFile -> CXCursorAndRangeVisitor -> IO(U32)

def clang_findIncludesInFile(TU, file, visitor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_findReferencesInFileWithBlock:
  CXCursor -> CXFile -> CXCursorAndRangeVisitorBlock -> IO(U32)

def clang_findReferencesInFileWithBlock(_0, _1, _2):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_findIncludesInFileWithBlock:
  CXTranslationUnit -> CXFile -> CXCursorAndRangeVisitorBlock -> IO(U32)

def clang_findIncludesInFileWithBlock(_0, _1, _2):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_isEntityObjCContainerKind:
  U32 -> IO(I32)

def clang_index_isEntityObjCContainerKind(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_getObjCContainerDeclInfo:
  Ptr_CXIdxDeclInfo -> IO(Ptr_CXIdxObjCContainerDeclInfo)

def clang_index_getObjCContainerDeclInfo(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_getObjCInterfaceDeclInfo:
  Ptr_CXIdxDeclInfo -> IO(Ptr_CXIdxObjCInterfaceDeclInfo)

def clang_index_getObjCInterfaceDeclInfo(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_getObjCCategoryDeclInfo:
  Ptr_CXIdxDeclInfo -> IO(Ptr_CXIdxObjCCategoryDeclInfo)

def clang_index_getObjCCategoryDeclInfo(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_getObjCProtocolRefListInfo:
  Ptr_CXIdxDeclInfo -> IO(Ptr_CXIdxObjCProtocolRefListInfo)

def clang_index_getObjCProtocolRefListInfo(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_getObjCPropertyDeclInfo:
  Ptr_CXIdxDeclInfo -> IO(Ptr_CXIdxObjCPropertyDeclInfo)

def clang_index_getObjCPropertyDeclInfo(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_getIBOutletCollectionAttrInfo:
  Ptr_CXIdxAttrInfo -> IO(Ptr_CXIdxIBOutletCollectionAttrInfo)

def clang_index_getIBOutletCollectionAttrInfo(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_getCXXClassDeclInfo:
  Ptr_CXIdxDeclInfo -> IO(Ptr_CXIdxCXXClassDeclInfo)

def clang_index_getCXXClassDeclInfo(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_getClientContainer:
  Ptr_CXIdxContainerInfo -> IO(CXIdxClientContainer)

def clang_index_getClientContainer(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_setClientContainer:
  Ptr_CXIdxContainerInfo -> CXIdxClientContainer -> IO(Unit)

def clang_index_setClientContainer(_0, _1):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_getClientEntity:
  Ptr_CXIdxEntityInfo -> IO(CXIdxClientEntity)

def clang_index_getClientEntity(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_index_setClientEntity:
  Ptr_CXIdxEntityInfo -> CXIdxClientEntity -> IO(Unit)

def clang_index_setClientEntity(_0, _1):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_IndexAction_create:
  CXIndex -> IO(CXIndexAction)

def clang_IndexAction_create(CIdx):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_IndexAction_dispose:
  CXIndexAction -> IO(Unit)

def clang_IndexAction_dispose(_0):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_indexSourceFile:
  CXIndexAction -> CXClientData -> Ptr_IndexerCallbacks -> U32 -> U32 -> Ptr_CChar -> Ptr_Ptr_CChar -> I32 -> Ptr_struct_CXUnsavedFile -> U32 -> Ptr_CXTranslationUnit -> U32 -> IO(I32)

def clang_indexSourceFile(_0, client_data, index_callbacks, index_callbacks_size, index_options, source_filename, command_line_args, num_command_line_args, unsaved_files, num_unsaved_files, out_TU, TU_options):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_indexSourceFileFullArgv:
  CXIndexAction -> CXClientData -> Ptr_IndexerCallbacks -> U32 -> U32 -> Ptr_CChar -> Ptr_Ptr_CChar -> I32 -> Ptr_struct_CXUnsavedFile -> U32 -> Ptr_CXTranslationUnit -> U32 -> IO(I32)

def clang_indexSourceFileFullArgv(_0, client_data, index_callbacks, index_callbacks_size, index_options, source_filename, command_line_args, num_command_line_args, unsaved_files, num_unsaved_files, out_TU, TU_options):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_indexTranslationUnit:
  CXIndexAction -> CXClientData -> Ptr_IndexerCallbacks -> U32 -> U32 -> CXTranslationUnit -> IO(I32)

def clang_indexTranslationUnit(_0, client_data, index_callbacks, index_callbacks_size, index_options, _5):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_indexLoc_getFileLocation:
  CXIdxLoc -> Ptr_CXIdxClientFile -> Ptr_CXFile -> Ptr_U32 -> Ptr_U32 -> Ptr_U32 -> IO(Unit)

def clang_indexLoc_getFileLocation(loc, indexFile, file, line, column, offset):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_indexLoc_getCXSourceLocation:
  CXIdxLoc -> IO(CXSourceLocation)

def clang_indexLoc_getCXSourceLocation(loc):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Type_visitFields:
  CXType -> CXFieldVisitor -> CXClientData -> IO(U32)

def clang_Type_visitFields(T, visitor, client_data):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_visitCXXBaseClasses:
  CXType -> CXFieldVisitor -> CXClientData -> IO(U32)

def clang_visitCXXBaseClasses(T, visitor, client_data):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getBinaryOperatorKindSpelling:
  U32 -> IO(CXString)

def clang_getBinaryOperatorKindSpelling(kind):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorBinaryOperatorKind:
  CXCursor -> IO(U32)

def clang_getCursorBinaryOperatorKind(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getUnaryOperatorKindSpelling:
  U32 -> IO(CXString)

def clang_getUnaryOperatorKindSpelling(kind):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCursorUnaryOperatorKind:
  CXCursor -> IO(U32)

def clang_getCursorUnaryOperatorKind(cursor):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getCString:
  CXString -> IO(Ptr_CChar)

def clang_getCString(string):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeString:
  CXString -> IO(Unit)

def clang_disposeString(string):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeStringSet:
  Ptr_CXStringSet -> IO(Unit)

def clang_disposeStringSet(set):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getNullLocation:
  IO(CXSourceLocation)

def clang_getNullLocation():
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_equalLocations:
  CXSourceLocation -> CXSourceLocation -> IO(U32)

def clang_equalLocations(loc1, loc2):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_isBeforeInTranslationUnit:
  CXSourceLocation -> CXSourceLocation -> IO(U32)

def clang_isBeforeInTranslationUnit(loc1, loc2):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Location_isInSystemHeader:
  CXSourceLocation -> IO(I32)

def clang_Location_isInSystemHeader(location):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Location_isFromMainFile:
  CXSourceLocation -> IO(I32)

def clang_Location_isFromMainFile(location):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getNullRange:
  IO(CXSourceRange)

def clang_getNullRange():
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getRange:
  CXSourceLocation -> CXSourceLocation -> IO(CXSourceRange)

def clang_getRange(begin, end):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_equalRanges:
  CXSourceRange -> CXSourceRange -> IO(U32)

def clang_equalRanges(range1, range2):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_Range_isNull:
  CXSourceRange -> IO(I32)

def clang_Range_isNull(range):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getExpansionLocation:
  CXSourceLocation -> Ptr_CXFile -> Ptr_U32 -> Ptr_U32 -> Ptr_U32 -> IO(Unit)

def clang_getExpansionLocation(location, file, line, column, offset):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getPresumedLocation:
  CXSourceLocation -> Ptr_CXString -> Ptr_U32 -> Ptr_U32 -> IO(Unit)

def clang_getPresumedLocation(location, filename, line, column):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getInstantiationLocation:
  CXSourceLocation -> Ptr_CXFile -> Ptr_U32 -> Ptr_U32 -> Ptr_U32 -> IO(Unit)

def clang_getInstantiationLocation(location, file, line, column, offset):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getSpellingLocation:
  CXSourceLocation -> Ptr_CXFile -> Ptr_U32 -> Ptr_U32 -> Ptr_U32 -> IO(Unit)

def clang_getSpellingLocation(location, file, line, column, offset):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getFileLocation:
  CXSourceLocation -> Ptr_CXFile -> Ptr_U32 -> Ptr_U32 -> Ptr_U32 -> IO(Unit)

def clang_getFileLocation(location, file, line, column, offset):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getRangeStart:
  CXSourceRange -> IO(CXSourceLocation)

def clang_getRangeStart(range):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getRangeEnd:
  CXSourceRange -> IO(CXSourceLocation)

def clang_getRangeEnd(range):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_disposeSourceRangeList:
  Ptr_CXSourceRangeList -> IO(Unit)

def clang_disposeSourceRangeList(ranges):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getFileName:
  CXFile -> IO(CXString)

def clang_getFileName(SFile):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getFileTime:
  CXFile -> IO(I64)

def clang_getFileTime(SFile):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_getFileUniqueID:
  CXFile -> Ptr_CXFileUniqueID -> IO(I32)

def clang_getFileUniqueID(file, outID):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_File_isEqual:
  CXFile -> CXFile -> IO(I32)

def clang_File_isEqual(file1, file2):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

law clang_File_tryGetRealPathName:
  CXFile -> IO(CXString)

def clang_File_tryGetRealPathName(file):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

# ---- THE FILL: what replaced the 324 `None{}` bodies, and how it is measured.
#
# Every trampoline above is now a `law` with its ONE ABI parameter types and its
# ONE return type, over the SAME names `ag-emit.bend` emitted, with a body that is
# one `import` of `.agents/slop/clangshim/libclang-tramp.c`.  That file is
# GENERATED by `.agents/slop/clangfill/fill.py` from the SAME
# `.agents/slop/ag-libclang.tramp` rows, so a bend signature and a C declaration
# have one source; `--check` on both scripts says `IN SYNC` or neither happened.
#
# ONE WORD IS NOT ENOUGH FOR A STRUCT, so `CXCursor`, `CXType`, `CXString`,
# `CXSourceLocation`, `CXSourceRange`, `CXIdxLoc`, `CXToken` and `CXTUResourceUsage`
# travel as a C-heap BOX whose address is a bend HANDLE.  A `const char*` is a
# WALK in both directions -- `io_cbuf` out of a bend String, `io_str` back into
# one -- and both are bend RUNTIME code, already in every emitted program.
#
# 320 of the 324 names are EXPORTED by the pinned dylib (`nm -gU`) and got a real
# call.  The other FOUR are not, and a declaration of one would not link:
# `clang_getOffsetOfBase`, `clang_getTypePrettyPrinted`, `clang_visitCXXBaseClasses`
# and `clang_isBeforeInTranslationUnit`.  Their `_run` REFUSES and says so.  That
# is version skew against libclang 17.0.0, not a language wall.
#
# THE ONE EXTRA LAW.  `Tramp_anchor` is the row where bend hands over a real
# `String` filename, so the `const char*` walk runs on bytes bend made and a real
# `clang_parseTranslationUnit` answers with a real translation unit.

law Tramp_anchor:
  String -> IO(String)

def Tramp_anchor(name):
  import "../../../.agents/slop/clangshim/libclang-tramp.c"

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
