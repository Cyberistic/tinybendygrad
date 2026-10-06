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

def clang_createIndex(excludeDeclarationsFromPCH: I32, displayDiagnostics: I32) -> Maybe<&2, CXIndex>:
  None{}

def clang_disposeIndex(index: CXIndex) -> Maybe<&2, Unit>:
  None{}

def clang_createIndexWithOptions(options: Ptr_CXIndexOptions) -> Maybe<&2, CXIndex>:
  None{}

def clang_CXIndex_setGlobalOptions(_0: CXIndex, options: U32) -> Maybe<&2, Unit>:
  None{}

def clang_CXIndex_getGlobalOptions(_0: CXIndex) -> Maybe<&2, U32>:
  None{}

def clang_CXIndex_setInvocationEmissionPathOption(_0: CXIndex, Path: Ptr_CChar) -> Maybe<&2, Unit>:
  None{}

def clang_isFileMultipleIncludeGuarded(tu: CXTranslationUnit, file: CXFile) -> Maybe<&2, U32>:
  None{}

def clang_getFile(tu: CXTranslationUnit, file_name: Ptr_CChar) -> Maybe<&2, CXFile>:
  None{}

def clang_getFileContents(tu: CXTranslationUnit, file: CXFile, size: Ptr_U64) -> Maybe<&2, Ptr_CChar>:
  None{}

def clang_getLocation(tu: CXTranslationUnit, file: CXFile, line: U32, column: U32) -> Maybe<&2, CXSourceLocation>:
  None{}

def clang_getLocationForOffset(tu: CXTranslationUnit, file: CXFile, offset: U32) -> Maybe<&2, CXSourceLocation>:
  None{}

def clang_getSkippedRanges(tu: CXTranslationUnit, file: CXFile) -> Maybe<&2, Ptr_CXSourceRangeList>:
  None{}

def clang_getAllSkippedRanges(tu: CXTranslationUnit) -> Maybe<&2, Ptr_CXSourceRangeList>:
  None{}

def clang_getNumDiagnostics(Unit: CXTranslationUnit) -> Maybe<&2, U32>:
  None{}

def clang_getDiagnostic(Unit: CXTranslationUnit, Index: U32) -> Maybe<&2, CXDiagnostic>:
  None{}

def clang_getDiagnosticSetFromTU(Unit: CXTranslationUnit) -> Maybe<&2, CXDiagnosticSet>:
  None{}

def clang_getTranslationUnitSpelling(CTUnit: CXTranslationUnit) -> Maybe<&2, CXString>:
  None{}

def clang_createTranslationUnitFromSourceFile(CIdx: CXIndex, source_filename: Ptr_CChar, num_clang_command_line_args: I32, clang_command_line_args: Ptr_Ptr_CChar, num_unsaved_files: U32, unsaved_files: Ptr_struct_CXUnsavedFile) -> Maybe<&2, CXTranslationUnit>:
  None{}

def clang_createTranslationUnit(CIdx: CXIndex, ast_filename: Ptr_CChar) -> Maybe<&2, CXTranslationUnit>:
  None{}

def clang_createTranslationUnit2(CIdx: CXIndex, ast_filename: Ptr_CChar, out_TU: Ptr_CXTranslationUnit) -> Maybe<&2, U32>:
  None{}

def clang_defaultEditingTranslationUnitOptions() -> Maybe<&2, U32>:
  None{}

def clang_parseTranslationUnit(CIdx: CXIndex, source_filename: Ptr_CChar, command_line_args: Ptr_Ptr_CChar, num_command_line_args: I32, unsaved_files: Ptr_struct_CXUnsavedFile, num_unsaved_files: U32, options: U32) -> Maybe<&2, CXTranslationUnit>:
  None{}

def clang_parseTranslationUnit2(CIdx: CXIndex, source_filename: Ptr_CChar, command_line_args: Ptr_Ptr_CChar, num_command_line_args: I32, unsaved_files: Ptr_struct_CXUnsavedFile, num_unsaved_files: U32, options: U32, out_TU: Ptr_CXTranslationUnit) -> Maybe<&2, U32>:
  None{}

def clang_parseTranslationUnit2FullArgv(CIdx: CXIndex, source_filename: Ptr_CChar, command_line_args: Ptr_Ptr_CChar, num_command_line_args: I32, unsaved_files: Ptr_struct_CXUnsavedFile, num_unsaved_files: U32, options: U32, out_TU: Ptr_CXTranslationUnit) -> Maybe<&2, U32>:
  None{}

def clang_defaultSaveOptions(TU: CXTranslationUnit) -> Maybe<&2, U32>:
  None{}

def clang_saveTranslationUnit(TU: CXTranslationUnit, FileName: Ptr_CChar, options: U32) -> Maybe<&2, I32>:
  None{}

def clang_suspendTranslationUnit(_0: CXTranslationUnit) -> Maybe<&2, U32>:
  None{}

def clang_disposeTranslationUnit(_0: CXTranslationUnit) -> Maybe<&2, Unit>:
  None{}

def clang_defaultReparseOptions(TU: CXTranslationUnit) -> Maybe<&2, U32>:
  None{}

def clang_reparseTranslationUnit(TU: CXTranslationUnit, num_unsaved_files: U32, unsaved_files: Ptr_struct_CXUnsavedFile, options: U32) -> Maybe<&2, I32>:
  None{}

def clang_getTUResourceUsageName(kind: U32) -> Maybe<&2, Ptr_CChar>:
  None{}

def clang_getCXTUResourceUsage(TU: CXTranslationUnit) -> Maybe<&2, CXTUResourceUsage>:
  None{}

def clang_disposeCXTUResourceUsage(usage: CXTUResourceUsage) -> Maybe<&2, Unit>:
  None{}

def clang_getTranslationUnitTargetInfo(CTUnit: CXTranslationUnit) -> Maybe<&2, CXTargetInfo>:
  None{}

def clang_TargetInfo_dispose(Info: CXTargetInfo) -> Maybe<&2, Unit>:
  None{}

def clang_TargetInfo_getTriple(Info: CXTargetInfo) -> Maybe<&2, CXString>:
  None{}

def clang_TargetInfo_getPointerWidth(Info: CXTargetInfo) -> Maybe<&2, I32>:
  None{}

def clang_getNullCursor() -> Maybe<&2, CXCursor>:
  None{}

def clang_getTranslationUnitCursor(_0: CXTranslationUnit) -> Maybe<&2, CXCursor>:
  None{}

def clang_equalCursors(_0: CXCursor, _1: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_isNull(cursor: CXCursor) -> Maybe<&2, I32>:
  None{}

def clang_hashCursor(_0: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getCursorKind(_0: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_isDeclaration(_0: U32) -> Maybe<&2, U32>:
  None{}

def clang_isInvalidDeclaration(_0: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_isReference(_0: U32) -> Maybe<&2, U32>:
  None{}

def clang_isExpression(_0: U32) -> Maybe<&2, U32>:
  None{}

def clang_isStatement(_0: U32) -> Maybe<&2, U32>:
  None{}

def clang_isAttribute(_0: U32) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_hasAttrs(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_isInvalid(_0: U32) -> Maybe<&2, U32>:
  None{}

def clang_isTranslationUnit(_0: U32) -> Maybe<&2, U32>:
  None{}

def clang_isPreprocessing(_0: U32) -> Maybe<&2, U32>:
  None{}

def clang_isUnexposed(_0: U32) -> Maybe<&2, U32>:
  None{}

def clang_getCursorLinkage(cursor: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getCursorVisibility(cursor: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getCursorAvailability(cursor: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getCursorPlatformAvailability(cursor: CXCursor, always_deprecated: Ptr_I32, deprecated_message: Ptr_CXString, always_unavailable: Ptr_I32, unavailable_message: Ptr_CXString, availability: Ptr_CXPlatformAvailability, availability_size: I32) -> Maybe<&2, I32>:
  None{}

def clang_disposeCXPlatformAvailability(availability: Ptr_CXPlatformAvailability) -> Maybe<&2, Unit>:
  None{}

def clang_Cursor_getVarDeclInitializer(cursor: CXCursor) -> Maybe<&2, CXCursor>:
  None{}

def clang_Cursor_hasVarDeclGlobalStorage(cursor: CXCursor) -> Maybe<&2, I32>:
  None{}

def clang_Cursor_hasVarDeclExternalStorage(cursor: CXCursor) -> Maybe<&2, I32>:
  None{}

def clang_getCursorLanguage(cursor: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getCursorTLSKind(cursor: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_getTranslationUnit(_0: CXCursor) -> Maybe<&2, CXTranslationUnit>:
  None{}

def clang_createCXCursorSet() -> Maybe<&2, CXCursorSet>:
  None{}

def clang_disposeCXCursorSet(cset: CXCursorSet) -> Maybe<&2, Unit>:
  None{}

def clang_CXCursorSet_contains(cset: CXCursorSet, cursor: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXCursorSet_insert(cset: CXCursorSet, cursor: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getCursorSemanticParent(cursor: CXCursor) -> Maybe<&2, CXCursor>:
  None{}

def clang_getCursorLexicalParent(cursor: CXCursor) -> Maybe<&2, CXCursor>:
  None{}

def clang_getOverriddenCursors(cursor: CXCursor, overridden: Ptr_Ptr_CXCursor, num_overridden: Ptr_U32) -> Maybe<&2, Unit>:
  None{}

def clang_disposeOverriddenCursors(overridden: Ptr_CXCursor) -> Maybe<&2, Unit>:
  None{}

def clang_getIncludedFile(cursor: CXCursor) -> Maybe<&2, CXFile>:
  None{}

def clang_getCursor(_0: CXTranslationUnit, _1: CXSourceLocation) -> Maybe<&2, CXCursor>:
  None{}

def clang_getCursorLocation(_0: CXCursor) -> Maybe<&2, CXSourceLocation>:
  None{}

def clang_getCursorExtent(_0: CXCursor) -> Maybe<&2, CXSourceRange>:
  None{}

def clang_getCursorType(C: CXCursor) -> Maybe<&2, CXType>:
  None{}

def clang_getTypeSpelling(CT: CXType) -> Maybe<&2, CXString>:
  None{}

def clang_getTypedefDeclUnderlyingType(C: CXCursor) -> Maybe<&2, CXType>:
  None{}

def clang_getEnumDeclIntegerType(C: CXCursor) -> Maybe<&2, CXType>:
  None{}

def clang_getEnumConstantDeclValue(C: CXCursor) -> Maybe<&2, I64>:
  None{}

def clang_getEnumConstantDeclUnsignedValue(C: CXCursor) -> Maybe<&2, U64>:
  None{}

def clang_Cursor_isBitField(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getFieldDeclBitWidth(C: CXCursor) -> Maybe<&2, I32>:
  None{}

def clang_Cursor_getNumArguments(C: CXCursor) -> Maybe<&2, I32>:
  None{}

def clang_Cursor_getArgument(C: CXCursor, i: U32) -> Maybe<&2, CXCursor>:
  None{}

def clang_Cursor_getNumTemplateArguments(C: CXCursor) -> Maybe<&2, I32>:
  None{}

def clang_Cursor_getTemplateArgumentKind(C: CXCursor, I: U32) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_getTemplateArgumentType(C: CXCursor, I: U32) -> Maybe<&2, CXType>:
  None{}

def clang_Cursor_getTemplateArgumentValue(C: CXCursor, I: U32) -> Maybe<&2, I64>:
  None{}

def clang_Cursor_getTemplateArgumentUnsignedValue(C: CXCursor, I: U32) -> Maybe<&2, U64>:
  None{}

def clang_equalTypes(A: CXType, B: CXType) -> Maybe<&2, U32>:
  None{}

def clang_getCanonicalType(T: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_isConstQualifiedType(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_isMacroFunctionLike(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_isMacroBuiltin(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_isFunctionInlined(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_isVolatileQualifiedType(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_isRestrictQualifiedType(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_getAddressSpace(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_getTypedefName(CT: CXType) -> Maybe<&2, CXString>:
  None{}

def clang_getPointeeType(T: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_getUnqualifiedType(CT: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_getNonReferenceType(CT: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_getTypeDeclaration(T: CXType) -> Maybe<&2, CXCursor>:
  None{}

def clang_getDeclObjCTypeEncoding(C: CXCursor) -> Maybe<&2, CXString>:
  None{}

def clang_Type_getObjCEncoding(_type: CXType) -> Maybe<&2, CXString>:
  None{}

def clang_getTypeKindSpelling(K: U32) -> Maybe<&2, CXString>:
  None{}

def clang_getFunctionTypeCallingConv(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_getResultType(T: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_getExceptionSpecificationType(T: CXType) -> Maybe<&2, I32>:
  None{}

def clang_getNumArgTypes(T: CXType) -> Maybe<&2, I32>:
  None{}

def clang_getArgType(T: CXType, i: U32) -> Maybe<&2, CXType>:
  None{}

def clang_Type_getObjCObjectBaseType(T: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_Type_getNumObjCProtocolRefs(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_Type_getObjCProtocolDecl(T: CXType, i: U32) -> Maybe<&2, CXCursor>:
  None{}

def clang_Type_getNumObjCTypeArgs(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_Type_getObjCTypeArg(T: CXType, i: U32) -> Maybe<&2, CXType>:
  None{}

def clang_isFunctionTypeVariadic(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_getCursorResultType(C: CXCursor) -> Maybe<&2, CXType>:
  None{}

def clang_getCursorExceptionSpecificationType(C: CXCursor) -> Maybe<&2, I32>:
  None{}

def clang_isPODType(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_getElementType(T: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_getNumElements(T: CXType) -> Maybe<&2, I64>:
  None{}

def clang_getArrayElementType(T: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_getArraySize(T: CXType) -> Maybe<&2, I64>:
  None{}

def clang_Type_getNamedType(T: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_Type_isTransparentTagTypedef(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_Type_getNullability(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_Type_getAlignOf(T: CXType) -> Maybe<&2, I64>:
  None{}

def clang_Type_getClassType(T: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_Type_getSizeOf(T: CXType) -> Maybe<&2, I64>:
  None{}

def clang_Type_getOffsetOf(T: CXType, S: Ptr_CChar) -> Maybe<&2, I64>:
  None{}

def clang_Type_getModifiedType(T: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_Type_getValueType(CT: CXType) -> Maybe<&2, CXType>:
  None{}

def clang_Cursor_getOffsetOfField(C: CXCursor) -> Maybe<&2, I64>:
  None{}

def clang_Cursor_isAnonymous(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_isAnonymousRecordDecl(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_isInlineNamespace(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Type_getNumTemplateArguments(T: CXType) -> Maybe<&2, I32>:
  None{}

def clang_Type_getTemplateArgumentAsType(T: CXType, i: U32) -> Maybe<&2, CXType>:
  None{}

def clang_Type_getCXXRefQualifier(T: CXType) -> Maybe<&2, U32>:
  None{}

def clang_isVirtualBase(_0: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getOffsetOfBase(Parent: CXCursor, Base: CXCursor) -> Maybe<&2, I64>:
  None{}

def clang_getCXXAccessSpecifier(_0: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_getBinaryOpcode(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_getBinaryOpcodeStr(Op: U32) -> Maybe<&2, CXString>:
  None{}

def clang_Cursor_getStorageClass(_0: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getNumOverloadedDecls(cursor: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getOverloadedDecl(cursor: CXCursor, index: U32) -> Maybe<&2, CXCursor>:
  None{}

def clang_getIBOutletCollectionType(_0: CXCursor) -> Maybe<&2, CXType>:
  None{}

def clang_visitChildren(parent: CXCursor, visitor: CXCursorVisitor, client_data: CXClientData) -> Maybe<&2, U32>:
  None{}

def clang_visitChildrenWithBlock(parent: CXCursor, block: CXCursorVisitorBlock) -> Maybe<&2, U32>:
  None{}

def clang_getCursorUSR(_0: CXCursor) -> Maybe<&2, CXString>:
  None{}

def clang_constructUSR_ObjCClass(class_name: Ptr_CChar) -> Maybe<&2, CXString>:
  None{}

def clang_constructUSR_ObjCCategory(class_name: Ptr_CChar, category_name: Ptr_CChar) -> Maybe<&2, CXString>:
  None{}

def clang_constructUSR_ObjCProtocol(protocol_name: Ptr_CChar) -> Maybe<&2, CXString>:
  None{}

def clang_constructUSR_ObjCIvar(name: Ptr_CChar, classUSR: CXString) -> Maybe<&2, CXString>:
  None{}

def clang_constructUSR_ObjCMethod(name: Ptr_CChar, isInstanceMethod: U32, classUSR: CXString) -> Maybe<&2, CXString>:
  None{}

def clang_constructUSR_ObjCProperty(property: Ptr_CChar, classUSR: CXString) -> Maybe<&2, CXString>:
  None{}

def clang_getCursorSpelling(_0: CXCursor) -> Maybe<&2, CXString>:
  None{}

def clang_Cursor_getSpellingNameRange(_0: CXCursor, pieceIndex: U32, options: U32) -> Maybe<&2, CXSourceRange>:
  None{}

def clang_PrintingPolicy_getProperty(Policy: CXPrintingPolicy, Property: U32) -> Maybe<&2, U32>:
  None{}

def clang_PrintingPolicy_setProperty(Policy: CXPrintingPolicy, Property: U32, Value: U32) -> Maybe<&2, Unit>:
  None{}

def clang_getCursorPrintingPolicy(_0: CXCursor) -> Maybe<&2, CXPrintingPolicy>:
  None{}

def clang_PrintingPolicy_dispose(Policy: CXPrintingPolicy) -> Maybe<&2, Unit>:
  None{}

def clang_getCursorPrettyPrinted(Cursor: CXCursor, Policy: CXPrintingPolicy) -> Maybe<&2, CXString>:
  None{}

def clang_getTypePrettyPrinted(CT: CXType, cxPolicy: CXPrintingPolicy) -> Maybe<&2, CXString>:
  None{}

def clang_getCursorDisplayName(_0: CXCursor) -> Maybe<&2, CXString>:
  None{}

def clang_getCursorReferenced(_0: CXCursor) -> Maybe<&2, CXCursor>:
  None{}

def clang_getCursorDefinition(_0: CXCursor) -> Maybe<&2, CXCursor>:
  None{}

def clang_isCursorDefinition(_0: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getCanonicalCursor(_0: CXCursor) -> Maybe<&2, CXCursor>:
  None{}

def clang_Cursor_getObjCSelectorIndex(_0: CXCursor) -> Maybe<&2, I32>:
  None{}

def clang_Cursor_isDynamicCall(C: CXCursor) -> Maybe<&2, I32>:
  None{}

def clang_Cursor_getReceiverType(C: CXCursor) -> Maybe<&2, CXType>:
  None{}

def clang_Cursor_getObjCPropertyAttributes(C: CXCursor, reserved: U32) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_getObjCPropertyGetterName(C: CXCursor) -> Maybe<&2, CXString>:
  None{}

def clang_Cursor_getObjCPropertySetterName(C: CXCursor) -> Maybe<&2, CXString>:
  None{}

def clang_Cursor_getObjCDeclQualifiers(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_isObjCOptional(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_isVariadic(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_isExternalSymbol(C: CXCursor, language: Ptr_CXString, definedIn: Ptr_CXString, isGenerated: Ptr_U32) -> Maybe<&2, U32>:
  None{}

def clang_Cursor_getCommentRange(C: CXCursor) -> Maybe<&2, CXSourceRange>:
  None{}

def clang_Cursor_getRawCommentText(C: CXCursor) -> Maybe<&2, CXString>:
  None{}

def clang_Cursor_getBriefCommentText(C: CXCursor) -> Maybe<&2, CXString>:
  None{}

def clang_Cursor_getMangling(_0: CXCursor) -> Maybe<&2, CXString>:
  None{}

def clang_Cursor_getCXXManglings(_0: CXCursor) -> Maybe<&2, Ptr_CXStringSet>:
  None{}

def clang_Cursor_getObjCManglings(_0: CXCursor) -> Maybe<&2, Ptr_CXStringSet>:
  None{}

def clang_Cursor_getModule(C: CXCursor) -> Maybe<&2, CXModule>:
  None{}

def clang_getModuleForFile(_0: CXTranslationUnit, _1: CXFile) -> Maybe<&2, CXModule>:
  None{}

def clang_Module_getASTFile(Module: CXModule) -> Maybe<&2, CXFile>:
  None{}

def clang_Module_getParent(Module: CXModule) -> Maybe<&2, CXModule>:
  None{}

def clang_Module_getName(Module: CXModule) -> Maybe<&2, CXString>:
  None{}

def clang_Module_getFullName(Module: CXModule) -> Maybe<&2, CXString>:
  None{}

def clang_Module_isSystem(Module: CXModule) -> Maybe<&2, I32>:
  None{}

def clang_Module_getNumTopLevelHeaders(_0: CXTranslationUnit, Module: CXModule) -> Maybe<&2, U32>:
  None{}

def clang_Module_getTopLevelHeader(_0: CXTranslationUnit, Module: CXModule, Index: U32) -> Maybe<&2, CXFile>:
  None{}

def clang_CXXConstructor_isConvertingConstructor(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXConstructor_isCopyConstructor(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXConstructor_isDefaultConstructor(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXConstructor_isMoveConstructor(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXField_isMutable(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXMethod_isDefaulted(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXMethod_isDeleted(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXMethod_isPureVirtual(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXMethod_isStatic(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXMethod_isVirtual(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXMethod_isCopyAssignmentOperator(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXMethod_isMoveAssignmentOperator(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXMethod_isExplicit(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXRecord_isAbstract(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_EnumDecl_isScoped(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_CXXMethod_isConst(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getTemplateCursorKind(C: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getSpecializedCursorTemplate(C: CXCursor) -> Maybe<&2, CXCursor>:
  None{}

def clang_getCursorReferenceNameRange(C: CXCursor, NameFlags: U32, PieceIndex: U32) -> Maybe<&2, CXSourceRange>:
  None{}

def clang_getToken(TU: CXTranslationUnit, Location: CXSourceLocation) -> Maybe<&2, Ptr_CXToken>:
  None{}

def clang_getTokenKind(_0: CXToken) -> Maybe<&2, CXTokenKind>:
  None{}

def clang_getTokenSpelling(_0: CXTranslationUnit, _1: CXToken) -> Maybe<&2, CXString>:
  None{}

def clang_getTokenLocation(_0: CXTranslationUnit, _1: CXToken) -> Maybe<&2, CXSourceLocation>:
  None{}

def clang_getTokenExtent(_0: CXTranslationUnit, _1: CXToken) -> Maybe<&2, CXSourceRange>:
  None{}

def clang_tokenize(TU: CXTranslationUnit, Range: CXSourceRange, Tokens: Ptr_Ptr_CXToken, NumTokens: Ptr_U32) -> Maybe<&2, Unit>:
  None{}

def clang_annotateTokens(TU: CXTranslationUnit, Tokens: Ptr_CXToken, NumTokens: U32, Cursors: Ptr_CXCursor) -> Maybe<&2, Unit>:
  None{}

def clang_disposeTokens(TU: CXTranslationUnit, Tokens: Ptr_CXToken, NumTokens: U32) -> Maybe<&2, Unit>:
  None{}

def clang_getCursorKindSpelling(_Kind: U32) -> Maybe<&2, CXString>:
  None{}

def clang_getDefinitionSpellingAndExtent(_0: CXCursor, startBuf: Ptr_Ptr_CChar, endBuf: Ptr_Ptr_CChar, startLine: Ptr_U32, startColumn: Ptr_U32, endLine: Ptr_U32, endColumn: Ptr_U32) -> Maybe<&2, Unit>:
  None{}

def clang_enableStackTraces() -> Maybe<&2, Unit>:
  None{}

def clang_executeOnThread(fn: Fn_Unit_CVoidP, user_data: CVoidP, stack_size: U32) -> Maybe<&2, Unit>:
  None{}

def clang_getCompletionChunkKind(completion_string: CXCompletionString, chunk_number: U32) -> Maybe<&2, U32>:
  None{}

def clang_getCompletionChunkText(completion_string: CXCompletionString, chunk_number: U32) -> Maybe<&2, CXString>:
  None{}

def clang_getCompletionChunkCompletionString(completion_string: CXCompletionString, chunk_number: U32) -> Maybe<&2, CXCompletionString>:
  None{}

def clang_getNumCompletionChunks(completion_string: CXCompletionString) -> Maybe<&2, U32>:
  None{}

def clang_getCompletionPriority(completion_string: CXCompletionString) -> Maybe<&2, U32>:
  None{}

def clang_getCompletionAvailability(completion_string: CXCompletionString) -> Maybe<&2, U32>:
  None{}

def clang_getCompletionNumAnnotations(completion_string: CXCompletionString) -> Maybe<&2, U32>:
  None{}

def clang_getCompletionAnnotation(completion_string: CXCompletionString, annotation_number: U32) -> Maybe<&2, CXString>:
  None{}

def clang_getCompletionParent(completion_string: CXCompletionString, kind: Ptr_U32) -> Maybe<&2, CXString>:
  None{}

def clang_getCompletionBriefComment(completion_string: CXCompletionString) -> Maybe<&2, CXString>:
  None{}

def clang_getCursorCompletionString(cursor: CXCursor) -> Maybe<&2, CXCompletionString>:
  None{}

def clang_getCompletionNumFixIts(results: Ptr_CXCodeCompleteResults, completion_index: U32) -> Maybe<&2, U32>:
  None{}

def clang_getCompletionFixIt(results: Ptr_CXCodeCompleteResults, completion_index: U32, fixit_index: U32, replacement_range: Ptr_CXSourceRange) -> Maybe<&2, CXString>:
  None{}

def clang_defaultCodeCompleteOptions() -> Maybe<&2, U32>:
  None{}

def clang_codeCompleteAt(TU: CXTranslationUnit, complete_filename: Ptr_CChar, complete_line: U32, complete_column: U32, unsaved_files: Ptr_struct_CXUnsavedFile, num_unsaved_files: U32, options: U32) -> Maybe<&2, Ptr_CXCodeCompleteResults>:
  None{}

def clang_sortCodeCompletionResults(Results: Ptr_CXCompletionResult, NumResults: U32) -> Maybe<&2, Unit>:
  None{}

def clang_disposeCodeCompleteResults(Results: Ptr_CXCodeCompleteResults) -> Maybe<&2, Unit>:
  None{}

def clang_codeCompleteGetNumDiagnostics(Results: Ptr_CXCodeCompleteResults) -> Maybe<&2, U32>:
  None{}

def clang_codeCompleteGetDiagnostic(Results: Ptr_CXCodeCompleteResults, Index: U32) -> Maybe<&2, CXDiagnostic>:
  None{}

def clang_codeCompleteGetContexts(Results: Ptr_CXCodeCompleteResults) -> Maybe<&2, U64>:
  None{}

def clang_codeCompleteGetContainerKind(Results: Ptr_CXCodeCompleteResults, IsIncomplete: Ptr_U32) -> Maybe<&2, U32>:
  None{}

def clang_codeCompleteGetContainerUSR(Results: Ptr_CXCodeCompleteResults) -> Maybe<&2, CXString>:
  None{}

def clang_codeCompleteGetObjCSelector(Results: Ptr_CXCodeCompleteResults) -> Maybe<&2, CXString>:
  None{}

def clang_getClangVersion() -> Maybe<&2, CXString>:
  None{}

def clang_toggleCrashRecovery(isEnabled: U32) -> Maybe<&2, Unit>:
  None{}

def clang_getInclusions(tu: CXTranslationUnit, visitor: CXInclusionVisitor, client_data: CXClientData) -> Maybe<&2, Unit>:
  None{}

def clang_Cursor_Evaluate(C: CXCursor) -> Maybe<&2, CXEvalResult>:
  None{}

def clang_EvalResult_getKind(E: CXEvalResult) -> Maybe<&2, U32>:
  None{}

def clang_EvalResult_getAsInt(E: CXEvalResult) -> Maybe<&2, I32>:
  None{}

def clang_EvalResult_getAsLongLong(E: CXEvalResult) -> Maybe<&2, I64>:
  None{}

def clang_EvalResult_isUnsignedInt(E: CXEvalResult) -> Maybe<&2, U32>:
  None{}

def clang_EvalResult_getAsUnsigned(E: CXEvalResult) -> Maybe<&2, U64>:
  None{}

def clang_EvalResult_getAsDouble(E: CXEvalResult) -> Maybe<&2, F64>:
  None{}

def clang_EvalResult_getAsStr(E: CXEvalResult) -> Maybe<&2, Ptr_CChar>:
  None{}

def clang_EvalResult_dispose(E: CXEvalResult) -> Maybe<&2, Unit>:
  None{}

def clang_getRemappings(path: Ptr_CChar) -> Maybe<&2, CXRemapping>:
  None{}

def clang_getRemappingsFromFileList(filePaths: Ptr_Ptr_CChar, numFiles: U32) -> Maybe<&2, CXRemapping>:
  None{}

def clang_remap_getNumFiles(_0: CXRemapping) -> Maybe<&2, U32>:
  None{}

def clang_remap_getFilenames(_0: CXRemapping, index: U32, original: Ptr_CXString, transformed: Ptr_CXString) -> Maybe<&2, Unit>:
  None{}

def clang_remap_dispose(_0: CXRemapping) -> Maybe<&2, Unit>:
  None{}

def clang_findReferencesInFile(cursor: CXCursor, file: CXFile, visitor: CXCursorAndRangeVisitor) -> Maybe<&2, U32>:
  None{}

def clang_findIncludesInFile(TU: CXTranslationUnit, file: CXFile, visitor: CXCursorAndRangeVisitor) -> Maybe<&2, U32>:
  None{}

def clang_findReferencesInFileWithBlock(_0: CXCursor, _1: CXFile, _2: CXCursorAndRangeVisitorBlock) -> Maybe<&2, U32>:
  None{}

def clang_findIncludesInFileWithBlock(_0: CXTranslationUnit, _1: CXFile, _2: CXCursorAndRangeVisitorBlock) -> Maybe<&2, U32>:
  None{}

def clang_index_isEntityObjCContainerKind(_0: U32) -> Maybe<&2, I32>:
  None{}

def clang_index_getObjCContainerDeclInfo(_0: Ptr_CXIdxDeclInfo) -> Maybe<&2, Ptr_CXIdxObjCContainerDeclInfo>:
  None{}

def clang_index_getObjCInterfaceDeclInfo(_0: Ptr_CXIdxDeclInfo) -> Maybe<&2, Ptr_CXIdxObjCInterfaceDeclInfo>:
  None{}

def clang_index_getObjCCategoryDeclInfo(_0: Ptr_CXIdxDeclInfo) -> Maybe<&2, Ptr_CXIdxObjCCategoryDeclInfo>:
  None{}

def clang_index_getObjCProtocolRefListInfo(_0: Ptr_CXIdxDeclInfo) -> Maybe<&2, Ptr_CXIdxObjCProtocolRefListInfo>:
  None{}

def clang_index_getObjCPropertyDeclInfo(_0: Ptr_CXIdxDeclInfo) -> Maybe<&2, Ptr_CXIdxObjCPropertyDeclInfo>:
  None{}

def clang_index_getIBOutletCollectionAttrInfo(_0: Ptr_CXIdxAttrInfo) -> Maybe<&2, Ptr_CXIdxIBOutletCollectionAttrInfo>:
  None{}

def clang_index_getCXXClassDeclInfo(_0: Ptr_CXIdxDeclInfo) -> Maybe<&2, Ptr_CXIdxCXXClassDeclInfo>:
  None{}

def clang_index_getClientContainer(_0: Ptr_CXIdxContainerInfo) -> Maybe<&2, CXIdxClientContainer>:
  None{}

def clang_index_setClientContainer(_0: Ptr_CXIdxContainerInfo, _1: CXIdxClientContainer) -> Maybe<&2, Unit>:
  None{}

def clang_index_getClientEntity(_0: Ptr_CXIdxEntityInfo) -> Maybe<&2, CXIdxClientEntity>:
  None{}

def clang_index_setClientEntity(_0: Ptr_CXIdxEntityInfo, _1: CXIdxClientEntity) -> Maybe<&2, Unit>:
  None{}

def clang_IndexAction_create(CIdx: CXIndex) -> Maybe<&2, CXIndexAction>:
  None{}

def clang_IndexAction_dispose(_0: CXIndexAction) -> Maybe<&2, Unit>:
  None{}

def clang_indexSourceFile(_0: CXIndexAction, client_data: CXClientData, index_callbacks: Ptr_IndexerCallbacks, index_callbacks_size: U32, index_options: U32, source_filename: Ptr_CChar, command_line_args: Ptr_Ptr_CChar, num_command_line_args: I32, unsaved_files: Ptr_struct_CXUnsavedFile, num_unsaved_files: U32, out_TU: Ptr_CXTranslationUnit, TU_options: U32) -> Maybe<&2, I32>:
  None{}

def clang_indexSourceFileFullArgv(_0: CXIndexAction, client_data: CXClientData, index_callbacks: Ptr_IndexerCallbacks, index_callbacks_size: U32, index_options: U32, source_filename: Ptr_CChar, command_line_args: Ptr_Ptr_CChar, num_command_line_args: I32, unsaved_files: Ptr_struct_CXUnsavedFile, num_unsaved_files: U32, out_TU: Ptr_CXTranslationUnit, TU_options: U32) -> Maybe<&2, I32>:
  None{}

def clang_indexTranslationUnit(_0: CXIndexAction, client_data: CXClientData, index_callbacks: Ptr_IndexerCallbacks, index_callbacks_size: U32, index_options: U32, _5: CXTranslationUnit) -> Maybe<&2, I32>:
  None{}

def clang_indexLoc_getFileLocation(loc: CXIdxLoc, indexFile: Ptr_CXIdxClientFile, file: Ptr_CXFile, line: Ptr_U32, column: Ptr_U32, offset: Ptr_U32) -> Maybe<&2, Unit>:
  None{}

def clang_indexLoc_getCXSourceLocation(loc: CXIdxLoc) -> Maybe<&2, CXSourceLocation>:
  None{}

def clang_Type_visitFields(T: CXType, visitor: CXFieldVisitor, client_data: CXClientData) -> Maybe<&2, U32>:
  None{}

def clang_visitCXXBaseClasses(T: CXType, visitor: CXFieldVisitor, client_data: CXClientData) -> Maybe<&2, U32>:
  None{}

def clang_getBinaryOperatorKindSpelling(kind: U32) -> Maybe<&2, CXString>:
  None{}

def clang_getCursorBinaryOperatorKind(cursor: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getUnaryOperatorKindSpelling(kind: U32) -> Maybe<&2, CXString>:
  None{}

def clang_getCursorUnaryOperatorKind(cursor: CXCursor) -> Maybe<&2, U32>:
  None{}

def clang_getCString(string: CXString) -> Maybe<&2, Ptr_CChar>:
  None{}

def clang_disposeString(string: CXString) -> Maybe<&2, Unit>:
  None{}

def clang_disposeStringSet(set: Ptr_CXStringSet) -> Maybe<&2, Unit>:
  None{}

def clang_getNullLocation() -> Maybe<&2, CXSourceLocation>:
  None{}

def clang_equalLocations(loc1: CXSourceLocation, loc2: CXSourceLocation) -> Maybe<&2, U32>:
  None{}

def clang_isBeforeInTranslationUnit(loc1: CXSourceLocation, loc2: CXSourceLocation) -> Maybe<&2, U32>:
  None{}

def clang_Location_isInSystemHeader(location: CXSourceLocation) -> Maybe<&2, I32>:
  None{}

def clang_Location_isFromMainFile(location: CXSourceLocation) -> Maybe<&2, I32>:
  None{}

def clang_getNullRange() -> Maybe<&2, CXSourceRange>:
  None{}

def clang_getRange(begin: CXSourceLocation, end: CXSourceLocation) -> Maybe<&2, CXSourceRange>:
  None{}

def clang_equalRanges(range1: CXSourceRange, range2: CXSourceRange) -> Maybe<&2, U32>:
  None{}

def clang_Range_isNull(range: CXSourceRange) -> Maybe<&2, I32>:
  None{}

def clang_getExpansionLocation(location: CXSourceLocation, file: Ptr_CXFile, line: Ptr_U32, column: Ptr_U32, offset: Ptr_U32) -> Maybe<&2, Unit>:
  None{}

def clang_getPresumedLocation(location: CXSourceLocation, filename: Ptr_CXString, line: Ptr_U32, column: Ptr_U32) -> Maybe<&2, Unit>:
  None{}

def clang_getInstantiationLocation(location: CXSourceLocation, file: Ptr_CXFile, line: Ptr_U32, column: Ptr_U32, offset: Ptr_U32) -> Maybe<&2, Unit>:
  None{}

def clang_getSpellingLocation(location: CXSourceLocation, file: Ptr_CXFile, line: Ptr_U32, column: Ptr_U32, offset: Ptr_U32) -> Maybe<&2, Unit>:
  None{}

def clang_getFileLocation(location: CXSourceLocation, file: Ptr_CXFile, line: Ptr_U32, column: Ptr_U32, offset: Ptr_U32) -> Maybe<&2, Unit>:
  None{}

def clang_getRangeStart(range: CXSourceRange) -> Maybe<&2, CXSourceLocation>:
  None{}

def clang_getRangeEnd(range: CXSourceRange) -> Maybe<&2, CXSourceLocation>:
  None{}

def clang_disposeSourceRangeList(ranges: Ptr_CXSourceRangeList) -> Maybe<&2, Unit>:
  None{}

def clang_getFileName(SFile: CXFile) -> Maybe<&2, CXString>:
  None{}

def clang_getFileTime(SFile: CXFile) -> Maybe<&2, I64>:
  None{}

def clang_getFileUniqueID(file: CXFile, outID: Ptr_CXFileUniqueID) -> Maybe<&2, I32>:
  None{}

def clang_File_isEqual(file1: CXFile, file2: CXFile) -> Maybe<&2, I32>:
  None{}

def clang_File_tryGetRealPathName(file: CXFile) -> Maybe<&2, CXString>:
  None{}

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
