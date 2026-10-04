# CLANGFILL — the 324 `None{}` trampoline bodies, and what they are worth

Unit: `.agents/slop/clangfill/`. Prefix **`CF-`**. Nothing committed.

```
python3 .agents/slop/clangfill/fill.py --check     # IN SYNC   (the generated C)
python3 .agents/slop/clangshim/apply-port-lane.py --check   # IN SYNC  (the product)
python3 .agents/slop/clangfill/gate.py --plants    # the census + 4 controls
```

## 1. THE FILL, THROUGH THE GENERATOR

**`None{}` bodies: 324 → 0, denominator 324.** Before: `grep -c '^  None{}$'` =
**324 of 324** — the brief's "311" is off by 13; there were no filled ones. After:
**0**, and `grep -c '^law '` = **335** = 324 trampolines + `Tramp_anchor` + the ten
FFI-lane laws.

Every body is a `law` + one `import`, spliced by `.agents/slop/clangfill/fill.py`
(`.bodies()`) which `.agents/slop/clangshim/apply-port-lane.py` calls. The `_run` it
pairs with is in `.agents/slop/clangshim/libclang-tramp.c`, GENERATED from the SAME
`.agents/slop/ag-libclang.tramp` rows — so a bend signature and a C declaration have
one source.

```
$ .agents/slop/ag-emit.bin > tinybendygrad/runtime/autogen/libclang.bend   # 63334 B raw
$ python3 .agents/slop/clangshim/apply-port-lane.py                       # 98944 B
$ python3 .agents/slop/spelling/roundtrip.py
BASE     PASS   rebuilt=baa107683faaf56badbd683737960052/98944B  product=same
```

**`abi.cross_check()`: 324 law signatures read out of the PRODUCT, 0
disagreements** against an independent re-derivation. It found one before it passed:
`Fn_Unit_CVoidP` vs `Fn_Unit_[ctypes.c_void_p]`, `ag-emit.bend`'s `enc_arg` strips
the brackets. Two derivations that were never compared.

## 2. THE CENSUS — 320 EXECUTED, 4 UNGATED

```
ROWS 324   EXECUTED 320   ungated 4 (faulted 4, rc0-no-row 0)
ANSWER CLASSES  void 41  int 144  box 90  ptr 40  cstr 4  double 1
ANSWER a refusal sentinel 175   a non-sentinel value 145
ROWS called with at least one NULL argument 256
```

Each row runs in its OWN process (`clang_getCursorKind` on a NULL handle segfaults,
and a fault in row 200 would take the other 199 with it). **EXECUTED means the row's
own `SAW` line is on stderr, NOT `rc == 0`** — several rows print before a later
fault and `rc` alone called them unexecuted.

**THE 4 UNGATED, named:** `clang_createIndexWithOptions`, `clang_Cursor_getReceiverType`,
`clang_EvalResult_isUnsignedInt`, `clang_remap_getNumFiles`. All four take an object
the fixture cannot build (`CXIndexOptions`, `CXCursor`, `CXEvalResult`, `CXRemapping`).

**320 of the 324 names are EXPORTED by the pinned dylib** (`nm -gU` on
`/Library/Developer/CommandLineTools/usr/lib/libclang.dylib`). The other FOUR are
not, and a declaration of one does not LINK: `clang_getOffsetOfBase`,
`clang_getTypePrettyPrinted`, `clang_visitCXXBaseClasses`,
`clang_isBeforeInTranslationUnit`. **Version skew against 17.0.0, not a language
wall — and the brief named one of the four, not four.**

**THE SECOND NUMBER, THE HONEST ONE: 256 of the 320 ran with at least one NULL
argument**, and 175 answered a refusal sentinel. A filled body that is called with a
null object and answers NULL has executed; it has not been shown to bind.

## 3. THE `const char*` WALK — BUILT, AND IT IS A CALL

**It was never missing. It is bend RUNTIME code, already in every emitted program:**

| direction | the call | where |
|---|---|---|
| `String` → `char*` | `io_cbuf(e, f[i], &n, CID(SCon))` | `references/bend/bend2/comp.ts:5591` |
| `char*` → `String` | `io_str(e, p, n)` | `references/bend/bend2/comp.ts:5640` |

Measured end to end by `Tramp_anchor`, the one row where bend hands over a real
`String`: bend's filename → `io_cbuf` → `clang_parseTranslationUnit` → a real
`CXTranslationUnit` → `clang_getCString` → `io_str` → back into bend.

```
SAW anchor name=fixture.c tu=0xb0945caf0
SAW anchor spelling=fixture.c
ANCHOR fixture.c
```

21 `cstr` PARAMETERS and 4 `cstr` RETURNS. `io_cbuf` **consumes** the cons list, so
it is a one-way door, exactly as a bend `String` is a one-way value.

## 4. WHAT A `Term` IS, AND WHY THE RECORDS ARE BOXED

A `Term` is ONE WORD. `CXCursor` is 32 bytes and `CXType` is 24, so a by-value record
travels as a C-heap **BOX** whose address is a bend **HANDLE** (`io_hand`/`io_hand_v`,
`comp.ts:5440`). 193 of the 324 rows take a record; 225 take a pointer; 89 take a
scalar; 21 take a `const char*`.

## 5. CONTROLS — 2 plants that move, 1 blind spot, 1 disarm

```
DETERMINISM rows moved between two runs of ONE binary: 0
PLANT-scalar    PASS  rows moved 2    (one row: line=2 column=3 -> line=3 column=3)
PLANT-sel       PASS  rows moved 42   (the fixture's selector a -> nosuchfield)
PLANT-transpose PASS  rows moved 0    BLIND SPOT, expected
DISARM-comment  PASS  rows moved 0
```

**A ROW IS NOT DETERMINISTIC UNTIL ITS ADDRESSES ARE MASKED.** A box answer is a
`malloc` address and a handle answer is a libclang pointer; unmasked, `DISARM-comment`
"moved" **186 rows**. `clang_hashCursor` is a third class: it answers a hash of a heap
pointer, and a decimal of nine digits or more is masked for that reason.

**`PLANT-transpose` IS A REAL BLIND SPOT, NOT A PASS.** The row prints the ARGUMENTS
(libclang never sees those), so swapping two arguments AT THE CALL SITE leaves the
row byte-identical. `fill.py`'s `run_body` emits the row from the locals. Swapping the
two DECLARATIONS is worse — a no-op by construction. No argument transposition at the
call site is falsifiable from outside this process.

## 6. WALLS, WITH `file:line`

| # | wall | where |
|---|---|---|
| **CF-1** | **bend emits a `CID` ONLY for a law something CALLS.** 324 `io_eff(CID(clang_*), ...)` answered **324 undeclared `CID_CLANG_*`** and the file did not compile; `grep -c '^#define CID_'` on a build whose main reaches two laws is **24**, and the only two law ids in it are those two. The fix is the one bend's own guide documents — `#ifdef CID(name)`, `references/bend/guide/EFFECTS.md:39` — so an unreached law is UNREGISTERED, and **a body executes only where something reaches its law** | `.agents/slop/clangfill/fill.py` `regs`; `references/bend/bend2/comp.ts:5685` |
| **CF-2** | **`io_eff`'s THIRD ARGUMENT IS THE NEED, NOT THE ARITY.** `io_eff(cid, run, 1)` = `IO_READ`, which parks on `f[0]` read as a file descriptor. A `String` argument parked **forever** (`io_loop` → `io_wait` → `__select`) and a Data-with-fields argument answered **`bend: the poller failed`** — `select()` on a garbage fd. Arity comes from `cid_arity(c)` | `references/bend/bend2/comp.ts:5990-5997`, `:5769` |
| **CF-3** | a bend value is LINEAR: `a <- L1(7); L1(a)` is `a (consumed more than once)`. A real `CXTranslationUnit` therefore cannot be handed to two laws from bend, which is why the fixture supplies handles and the row names the substitution | measured, `.agents/slop/clangfill/gate.py` |
| **CF-4** | a law's signature is over TYPES. `law c: excludeDeclarationsFromPCH -> displayDiagnostics -> IO(CXIndex)` is `expected : a defined name` | `.agents/slop/clangfill/fill.py` `bodies` |
| **CF-5** | three spellings of zero and all three are TYPE errors: `0n` is `Nat`, `0` is `U32`, and `I32`/`I64`/`U64`/`F64` are NULLARY Data this product mints, so their value is the CONSTRUCTOR | `.agents/slop/clangfill/gate.py` `gate_arg` |
| **CF-6** | `match k` on a `Nat` demands a case for every constructor: without a final `case Succ{p}` the answer is `expected : cases for Succ` | `.agents/slop/clangfill/gate.py` `dispatch` |
| **CF-7** | **`IO.args()` HAS `argv[0]` IN IT** — `args.c` loops `i = io_argc .. 1` and reads `io_argv[i-1]`, so the head of the list is the PROGRAM PATH. The anchor parsed a file called `port.out` and `clang_parseTranslationUnit` answered NULL, which reads as a refusal | `references/bend/bend2/effs/args.c` |
| **CF-8** | the generated `.c` cannot be syntax-gated with plain `cc`: it is SPLICED into the program bend emits, so `Term`/`Env`/`io_str`/`CID` are already in scope there. `.agents/slop/clangfill/cf-runtime-stub.h` declares the SEAM and nothing else, which is what lets the gate see the file's OWN mistakes instead of stopping at `unknown type name 'Term'` | `cf-runtime-stub.h` |

### THREE DEFECTS OF MY OWN, all found by a number and not by reading

1. **The fixture substitution keyed on the PARAMETER NAME and fired ZERO times.**
   No name in the 324 is `CXTranslationUnit` — they are `tu`, `CIdx`, `Unit`, `_0`.
   Every substituted argument was silently a zero Term and the census said
   `ROWS called with at least one NULL argument 278`. Nobody read that line as a
   defect in the FILL. Keyed by ABI TYPE now, and the count is **256**.
2. **A trailing space.** `c_proto_n` returned `"CXCursor "` for a zero-star record,
   so `FIXTURE_BOX.get("CXCursor ")` MISSED — every record argument stayed the zero
   record, 312 rows executed, and not one saw the fixture's cursor. A whitespace
   mismatch disabled the whole fixture and every row still looked like a row.
3. **Two `file:line` traps, both cited by NAME above and in §5**: the row printer
   emitted `(void *)&r` and printed the FRAME, so a real transposition was invisible
   to a real instrument.

## 7. NOT MINE

`.agents/slop/spelling/roundtrip.py` was RUN and is unmodified; it is what measures
`emitter → fix → product` byte-for-byte. `libclang-ffi.c` and `ffi-lane.bend` are
untouched. The product's own `main` still prints its thirteen rows, byte for byte.