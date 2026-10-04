# STAGE 4 — what still fails, and whether the failure is the predicted one

`ffi-port-cost.py` predicts **17 blockers, "all int64/uint64/double"**. Measured,
the prediction is **16 of 16 correct and 1 wrong**. Every one of the 19 drops from
324 is below, attributed to a step.

## The three drops, in order

```
324  bindings in .agents/slop/ag-libclang.tramp
-16  no law emitted          <- Stage 4a
=308  laws emitted
- 3  symbol absent from Apple's libclang 17.0.0   <- Stage 4b
=305  laws LINKED
-15  forked child died      <- Stage 4c
=290  shims that CALLED libclang and returned a value
```

**Reproduce the whole chain and the census twice:**

```
zsh $TMPDIR/clangshim/s2.sh
#   run 1: CALL=305 ok=290 FAILED=15   P-rows=305
#   run 2: CALL=305 ok=290 FAILED=15   P-rows=305
#   diff of the two stderr files: IDENTICAL, and the same 15 rows.
```

## 4a — THE 16 NOT EMITTED: THE PREDICTED BLOCKER, NAME FOR NAME

```
  F64                      1
  I64                     15
  clang_Cursor_getOffsetOfField                     I64
  clang_Cursor_getTemplateArgumentUnsignedValue     I64
  clang_Cursor_getTemplateArgumentValue             I64
  clang_EvalResult_getAsDouble                      F64
  clang_EvalResult_getAsLongLong                    I64
  clang_EvalResult_getAsUnsigned                    I64
  clang_Type_getAlignOf                             I64
  clang_Type_getOffsetOf                            I64
  clang_Type_getSizeOf                              I64
  clang_codeCompleteGetContexts                     I64
  clang_getArraySize                                I64
  clang_getEnumConstantDeclUnsignedValue            I64
  clang_getEnumConstantDeclValue                    I64
  clang_getFileTime                                 I64
  clang_getNumElements                              I64
  clang_getOffsetOfBase                             I64
```

**Every one of these 16 is a 64-bit integer or a double, which is exactly the
predicted blocker, and the prediction's 16-name list matches this one name for
name.** The cause is a missing Bend type (`F64`, `I64`, `U64` — Bend 2.0.35 has
`U32 F32 Nat Bool String`), not the 2^51-1 `Nat` window: a `Nat` is a working
`U64` to 2^51-1 and every one of these is a *return*, where even a window breach
would be a value problem and not a typing one.

**The prediction's 17th entry is WRONG, and its stated reason is an artefact.**
`ffi-port-cost.py` also blocked `clang_executeOnThread`, on
`c.CFUNCTYPE[None -> typedef of an int is free; anything else needs the struct;
[ctypes.c_void_p]]` — i.e. its own resolver failed to expand a CFUNCTYPE (see
STAGE2.md defect 1). I derive the stub's signature from the raw
`c.CFUNCTYPE[R, [A, B]]` spelling and **emit it**, so `clang_executeOnThread` is
in the 305. A callback parameter is mechanically derivable: one `Nat` holding a
shim-owned stub's address, one stub per distinct signature, and the stub reports
`Continue` so the call's own answer still comes back on the ordinary return
channel.

**So 308 = 307 + 1.** The +1 is that one. If the CFUNCTYPE resolver is fixed, the
prediction's 307 becomes 308 and the two numbers agree exactly.

## 4b — THE 3 THAT DO NOT LINK: NOT THE PREDICTED BLOCKER

```
step3 LINK: 3 symbol(s) absent from /Library/Developer/CommandLineTools/usr/lib/libclang.dylib:
  _clang_getTypePrettyPrinted
  _clang_isBeforeInTranslationUnit
  _clang_visitCXXBaseClasses
CINDEX_VERSION in the bindings: CINDEX_VERSION_MINOR=64
```

Confirmed against the binary, not against the linker's word:

```
nm -gU $CLIB/libclang.dylib | awk '$2~/^[TDBR]$/{print $3}' | grep -c '^_clang_'   -> 552
nm -gU $CLIB/libclang.dylib | grep -c '_clang_getTypePrettyPrinted$'                  -> 0
nm -gU $CLIB/libclang.dylib | grep -c '_clang_isBeforeInTranslationUnit$'             -> 0
nm -gU $CLIB/libclang.dylib | grep -c '_clang_visitCXXBaseClasses$'                   -> 0
```

**This is a VERSION SKEW IN THE INPUT, not a Bend limit and not the predicted
blocker.** The bindings were generated against `CINDEX_VERSION_MINOR = 64`;
Apple's dylib here is clang **17.0.0**, and these three symbols postdate it. All
three are excluded **by name, printed, and only after the linker named them** —
`s2.sh` greps the undefined symbols out of `g/link.err` and passes them back as
`--exclude`, so nothing is dropped silently. A fourth consequence worth stating:
`324` bindings against `552` exported symbols means the bindings are a *subset*
of this dylib's surface, and the 3 are where the subset and this dylib disagree.

## 4c — THE 15 THAT WERE CALLED AND DIED: NOT THE PREDICTED BLOCKER, AND NOT
## ANONYMOUS

```
290 ok                              15 FAILED-child-nonzero-exit
```

```
clang_createIndexWithOptions        clang_getUnqualifiedType
clang_disposeCXPlatformAvailability clang_getNonReferenceType
clang_getCursorTLSKind              clang_Type_getObjCEncoding
clang_getAddressSpace               clang_Cursor_getSpellingNameRange
clang_getTypedefName                clang_getCursorPrintingPolicy
clang_Cursor_getReceiverType        clang_getDefinitionSpellingAndExtent
clang_EvalResult_isUnsignedInt      clang_remap_getNumFiles
clang_disposeStringSet
```

`FAILED-child-nonzero-exit status=0x100 sig=0` — the child exited 1, with no
signal, and stderr carries 15 copies of `bend: memory fault (machine stack
overflow?)`. That message is **bend's SIGSEGV handler running inside the child**,
so the attribution needed one more step: **the leaf cause, measured with no bend
runtime in the process at all.**

```
$ ./leaf.out getAddressSpace ; echo rc=$?
calling getAddressSpace with a ZEROED struct / NULL pointer
rc=139                      <- SIGSEGV, bend absent
```

Sampled five of the fifteen, all SIGSEGV (rc=139), with the census's own argument
policy — `0` for every pointer, a **zeroed block** for every by-value struct:

```
getAddressSpace            rc=139  SIGSEGV
getUnqualifiedType         rc=139  SIGSEGV
getCursorTLSKind           rc=139  SIGSEGV
createIndexWithOptions     rc=139  SIGSEGV
getCursorPrintingPolicy    rc=139  SIGSEGV
```

**So the 15 are libclang dereferencing a handle it was handed as 0.** They are not
a marshalling failure: the marshalling delivered the argument faithfully and
libclang did not like it. The fix is an argument policy, not a shim change, and
the honest denominator for "callable with no fabricated state" is
**290/305 with a zero policy — not 305/305.**

## WHAT IS STILL `None{}`, AND WHY

`tinybendygrad/runtime/autogen/libclang.bend` is **untouched**. Its 324 bodies are
still `None{}`, and the refusal in its header at **:15-16** is still there. This
unit did not edit a file it was told to read, and every artefact of this unit
lives under `.agents/slop/clangshim/`. What changed is that the refusal is now
**measured** rather than argued: 305 of its signatures link and 290 of those call
libclang and return, from one generated `.c`.

The things that are still blocked, and none of them is "the FFI":

1. **16 laws, 64-bit and double returns.** A missing Bend type. `F64` and `I64`
   are the whole list.
2. **No libclang round trip from Bend.** Every `Nat` is linear, so one handle
   cannot serve two calls. Stage 3 does the round trip inside one foreign call;
   a Bend program that wants `set` then `get` needs the shim to fuse them.
3. **No field access.** The by-value-struct convention is an opaque union of the
   right size: a shim passes and returns `CXCursor` correctly over the ABI and
   **cannot read a field of it.** Field offsets are a separate unit of work, and
   `libclang.bend:19-23` already says its 41 records and 130 fields are not
   covered.
4. **A wrong argument type is not caught by Bend's typechecker.** The laws use
   `Nat`/`String`/`Unit` — three types for 60 C types — because
   `type CXIndex is Data: CXIndex{}` is a nullary constructor and therefore a
   singleton that cannot carry a handle. The price is that the failure mode is a
   process death, not a type error.
5. **`clang_executeOnThread`'s callback is a stub.** The call is real and the
   answer is right; the function body libclang would run on a new thread is
   `shim_cb`'s default stub, which returns `Continue` and reports nothing.

## ON THE COVERAGE FRAMING THE AUTOGEN UNIT STATED

It said: *"These are device FFI trampolines. None can execute. e2e.sh still
proves exactly one matmul on real hardware. This is not progress toward
execution."*

**That framing was correct for the state it inherited and it is still correct
now, and the number behind it has changed.** Restated honestly:

* **324 bindings are signatures. 305 of them link. 290 of those call libclang and
  return a value. 16 have no Bend type. 3 are newer than this dylib. 15 die on a
  null argument that the shim delivered correctly.**
* **This is not a device runtime.** `clang_createIndex` handing back a pointer is
  not a kernel launch; `.agents/slop/e2e.sh` still proves exactly one matmul on
  real hardware and `E2E-PROVES-COMPUTE` is still 1/1.
* **What did change is that the FFI wall is not a wall.** The claim was 324 C
  files and 324 hand-written shims. It is one file, one import, one `cc`, and
  **zero hand-written shims** — 12.7 lines per binding out of a generator, and
  the remaining 16 are a *type* gap in Bend, not an interface gap in the FFI.
* **What did not change is that a handle is not composable in Bend.** Every
  `Nat` is linear, so the 290 callable shims are 290 *entry points*, not a
  library a Bend program can drive. Fusing a two-call sequence into one law is
  the next unit, and it is a compiler-shaped decision, not a shim-shaped one.