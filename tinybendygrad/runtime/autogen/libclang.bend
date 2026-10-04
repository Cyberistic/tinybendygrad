# GENERATED FILE -- DO NOT EDIT.  Emitted by `.agents/slop/ag-emit.bend` from
# `tinygrad/runtime/autogen/libclang.py` via `.agents/slop/ag-libclang.tramp`.
# Regenerate:
#   ./bin/bend .agents/slop/ag-emit.bend -o .agents/slop/ag-emit.bin
#   .agents/slop/ag-emit.bin > tinybendygrad/runtime/autogen/libclang.bend
#
# Port of `tinygrad/runtime/autogen/libclang.py`: the 324 `@dll.bind`
# trampolines `tinygrad/runtime/support/autogen.py:240-241` emits, over 60 distinct ABI
# types, driven from the ENUMERATED LIST rather than from a live libclang AST.
# One template, applied 324 times.
#
# COVERAGE, NOT FUNCTION.  No def below executes a libclang call.  Every body
# is `None{}` and the refusal is in the TYPE, so a caller cannot read a refused
# call as a returned value.  bend has no per-function FFI: its only form is a
# whole-operation effect -- a `def` returning IO plus an `import` of a C file --
# which for this header would mean 324 C files and 324 hand-written shims.
# See `tinybendygrad/runtime/support/autogen.bend` WALL 1.
#
# NOT COVERED, and not claimed: the 41 struct RECORDS and their 130 fields --
# field ORDER, OFFSETS and bitfield slices; the 47 enum dicts and their 845
# constants; the 32 `TypeAlias` lines.  What is checked here is the FUNCTION
# TRAMPOLINE template and nothing else.  A name-and-arity check cannot see a
# wrong field offset.
import Base


type CVoidP is Data:
  CVoidP{}

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

type U32 is Data:
  U32{}

def ty_U32() -> Ty: Ty{"U32", "ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32,ctypes.c_uint32"}

type Unit is Data:
  Unit{}

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

def clang_Type_getObjCEncoding(type: CXType) -> Maybe<&2, CXString>:
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

def clang_getCursorKindSpelling(Kind: U32) -> Maybe<&2, CXString>:
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

