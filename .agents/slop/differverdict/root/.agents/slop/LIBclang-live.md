# LIBclang-live — `tinybendygrad/runtime/autogen/libclang.bend` ANSWERS THE ORACLE

**One sentence.** `tinybendygrad/runtime/autogen/libclang.bend` now calls libclang for
real and prints all ten of `.agents/slop/clangshim/oracle.py`'s rows, byte-equal to the
oracle's on the same fixture bytes and the same pinned dylib — and the file, which was
**red** (`duplicate declaration: U32`) and could not be compiled at all, compiles.

```
python3 .agents/slop/clangshim/cl-port-gate.py --plants
FAILURES: 0
```

Four runs, every one with a row census. **Nothing is planted in the live tree.**

## The two sides, side by side

Port = `libclang.bend` + `main`, compiled with `-o`, linked against the pinned dylib.
Oracle = `oracle.py`, `LIBCLANG_PATH` pinned, CPython 3.14.6.
Whitespace is normalised (the oracle pads `%-12s`; a column width is layout, not fact)
and one token is dropped from the oracle's side only — `opaque=_mem_`, a ctypes
mechanism with no C counterpart (see "THE ONE TOKEN").

```
CLIB /Library/Developer/CommandLineTools/usr/lib/libclang.dylib
CVER Apple clang version 17.0.0 (clang-1700.6.3.2)
SIZE int          sizeOf=4 alignOf=4 spelling=int
SIZE char         sizeOf=1 alignOf=1 spelling=char
SIZE double       sizeOf=8 alignOf=8 spelling=double
SIZE struct Pair  sizeOf=16 alignOf=8 spelling=struct Pair
FIELD a cdecl_off=0 offof_bits=0 offof_bytes=0 sizeOf=4 spelling=int    c=int
FIELD b cdecl_off=4 offof_bits=32 offof_bytes=4 sizeOf=1 spelling=char   c=char
FIELD c cdecl_off=8 offof_bits=64 offof_bytes=8 sizeOf=8 spelling=double c=double
RECORD CXCursor sizeof=32 opaque=_mem_ fields=kind@0,xdata@4,data@8
```

`DIFF 0 port-only, 0 oracle-only -- all 10 rows equal`, on every run.

## ROWS-PRESENT AGAINST ROWS-EXPECTED, ON EVERY RUN

| run | port shared | oracle shared | port-only | rc (port / oracle) | stderr |
|---|---|---|---|---|---|
| base | **10/10** | **10/10** | 3/3 | 0 / 0 | 2225 B / 0 B |
| plant-long-a | **10/10** | **10/10** | 3/3 | 0 / 0 | 2241 B / 0 B |
| disarm-comment | **10/10** | **10/10** | 3/3 | 0 / 0 | 2225 B / 0 B |
| plant-div | **10/10** | n/a (port only) | 3/3 | 0 / – | – |

Determinism, measured: the port's stdout and stderr are **byte-identical across two
runs** of one binary, and the gate's own output is **byte-identical across two runs**
(`diff -q` clean). 13 stdout rows, 10 of them shared.

### THE CENSUS IS NOT A CLAIM — it was caught missing one

The control for the census, and the only reason to believe it: **the law is still
called, so `bend` still emits its `CID`, the build is green, rc is 0 and stderr is
unchanged — and only its `IO.print` is deleted.**

```
BASE: rc port=0 oracle=0  port stderr=2225B oracle stderr=0B
BASE: ROWS shared port=9/10 oracle=10/10   port-only=3/3
  ORACLE-ONLY RECORD CXCursor sizeof=32 fields=kind@0,xdata@4,data@8
FAILURES: 2
  BASE: port printed 9 shared rows, expected 10
```

A missing row does not read as a pass. (A first attempt at the same control, which
also *stopped calling* the law, failed the build instead — `use of undeclared
identifier 'CID_RECORD_REPORT'` — a stronger failure but a different one, so it does
not count.)

## STEP 1 — `clang_Type_getSizeOf` on `int`

Both sides, and both derivations, on the same four types:

```
                      PORT                          ORACLE
SIZE int          sizeOf=4 alignOf=4 spelling=int    identical
SIZE char         sizeOf=1 alignOf=1 spelling=char   identical
SIZE double       sizeOf=8 alignOf=8 spelling=double identical
SIZE struct Pair  sizeOf=16 alignOf=8 spelling=struct Pair   identical
```

`clang_Type_getSizeOf` **links, is called, and returns.** Its C return type is
`long long`, which bend has no type for — it is one of the 16 in STAGE4.md's 4a list —
so the `_run` narrows it at the boundary and **refuses** rather than truncates: on
`v < 0` it writes `NEGATIVE_ANSWER raw=<v>` to stderr and returns `CL_REFUSED =
0x7FFFFFFF`, which is not a bit offset or a size of any record on this target. Same
rule for `clang_Type_getAlignOf` and `clang_Type_getOffsetOf`.

**No binding was unproven, so nothing stopped the work.** All four that the rows need
(`getSizeOf`, `getAlignOf`, `getTypeSpelling`, `getOffsetOf`) linked and returned.

## STEP 2 — `FIELD b`, the hard one

```
PORT   FIELD b cdecl_off=4 offof_bits=32 offof_bytes=4 sizeOf=1 spelling=char c=char
ORACLE FIELD b cdecl_off=4 offof_bits=32 offof_bytes=4 sizeOf=1 spelling=char c=char
```

- `offof_bits=32` is `clang_Type_getOffsetOf(<struct Pair>, "b")` — **the RECORD type
  and the field NAME**, which is CL-5's warning against passing the field's own type.
- `offof_bytes=4` is `bits / 8` from the **same `long`**, in the same `_run`. See
  "ONE MEASUREMENT, TWO READERS" for the control that says the division is a division.
- `cdecl_off=4` is `offsetof(struct Pair, b)` from the C declaration — a *different*
  measurement on purpose, and the `plant-div` control uses the gap between the two.
- `c=char` is the C declaration's spelling; `spelling=char` is libclang's. **Two
  derivations of the same fact**, so a row cannot be internally consistent over a
  measurement that never happened.

### THE -5 TRAP, MADE INTO A ROW

```
PORT offof_unknown_refused 2147483647        <- CL_REFUSED
stderr: NEGATIVE_ANSWER raw=-5 -> CL_REFUSED
```

`clang_Type_getOffsetOf(rec, "nope")` answers **-5**, a number, not a failure. It is
asked for on purpose and it must refuse, or a wrong argument would read as an offset.

## STEP 3 — `RECORD CXCursor` LANDED, AND `sizeof=32` IS THE REAL ABI

```
PORT   RECORD CXCursor sizeof=32 fields=kind@0,xdata@4,data@8
ORACLE RECORD CXCursor sizeof=32 opaque=_mem_ fields=kind@0,xdata@4,data@8
```

**I was wrong about this one before I measured it, and the measurement is the finding.**
`sizeof(CXCursor)` looks like a `ctypes` artefact — tinygrad spells `data` as
`c.Array[c_void_p, Literal[3]]` (`tinygrad/runtime/autogen/libclang.py:178`), so 8+24=32
looks like a choice rather than a measurement. It is the real ABI:

```
otool -tvV -p _clang_getCursorSpelling libclang.dylib
  movq 0x18(%rcx), %rdi        rcx = 0x10(%rbp)  -> OFFSET 24 of the cursor argument
otool -tvV -p _clang_Type_getSizeOf libclang.dylib
  movq 0x8(%rax), %r14 ; movq 0x10(%rax), %rax   -> offsets 8 and 16 of a 24-byte CXType
otool -tvV -p _clang_Type_getOffsetOf libclang.dylib
  movaps 0x10(%rbp), %xmm0     -> 16 of the 24 CXType bytes
  movq 0x20(%rbp), %rax       -> the const char* is the SECOND argument
```

So `CXCursor` is `{int kind; int xdata; const void *data[3]}` = **32 bytes**, and
`data[3]` is why. Declaring it `const void *data` (16 bytes) **segfaults inside libclang
with no message at all** — measured, and indistinguishable from STAGE4.md:119's
`bend: memory fault (machine stack overflow?)`. The port says so in the extra row:

```
PORT RECORD_words CXCursor sizeof=32 data_words=3 at=8,16,24
```

**THE ONE TOKEN.** `opaque=_mem_` is not emitted and cannot be: `_mem_` is the single
`c_byte_Array_32` member that `tinygrad/runtime/support/c.py`'s `Struct` exposes while
keeping the real ones in `_real_fields_`. It is a ctypes mechanism, and the C ABI has no
counterpart. It is dropped from the ORACLE's side only, it is the ONLY token dropped,
and it is named in the gate's source.

## THE PLANTS, AND THE DISARM

Both plants move **all four copies of the fixture fact** — `oracle.py` `SRC`,
`oracle.py` `FIELDS`, `fixture.h` `CL_FIXTURE_SRC`, `fixture.h` `struct Pair` +
`CL_FIELD_SPELL` — or the gate refuses to run. That is not theoretical: the first
attempt planted only the source text and got **CL-9 exactly**, with the numbers.

### `plant-long-a`: `int a;` → `long a;`

```
plant-long-a: rc port=0 oracle=0   ROWS shared port=10/10 oracle=10/10
plant-long-a: DIFF 0 port-only, 0 oracle-only -- all 10 rows equal
  moved SIZE long sizeOf=8 alignOf=8 spelling=long
  moved SIZE struct Pair sizeOf=24 alignOf=8 spelling=struct Pair
  moved FIELD a cdecl_off=0 offof_bits=0 offof_bytes=0 sizeOf=8 spelling=long c=long
  moved FIELD b cdecl_off=4->8  offof_bits=32->64  offof_bytes=4->8   sizeOf=1 spelling=char c=char
  moved FIELD c cdecl_off=8->16 offof_bits=64->128 offof_bytes=8->16  sizeOf=8 spelling=double c=double
```

**5 of 10 rows moved, the same 5 on both sides, and the two sides still agree under the
plant.** The labels did not move (`FIELD b` is still `FIELD b`); the answers did. The
division carried: 64→8 and 128→16.

### CL-9, MEASURED, NOT QUOTED — the half-plant

Planting `int a;` → `long a;` in the source text ALONE:

```
plant-long-a: rows port=10 oracle=7   moved port=5 oracle=3
  UNDER-PLANT DISAGREE FIELD b ...      <- the row is GONE, not wrong
  UNDER-PLANT DISAGREE FIELD c ...
  UNDER-PLANT DISAGREE RECORD CXCursor ...
```

**The oracle printed 7 of its 10 rows and exited 1** — no `FIELD b`, no `FIELD c`, no
`RECORD` — because its `FIELDS` offset column states the C declaration and now
contradicts libclang, and `assert bits == off * 8` fires first. A disagreement there
becomes a **vanishing**, and a vanishing reads as a pass unless the row count is part
of the result. That is the whole argument for the census above.

### `disarm-comment`: `int a;` → `int a; /* 8 */` — THE DISARM MOVED NOTHING

Same line, same size of edit, opposite outcome:

```
disarm-comment: ROWS shared port=10/10 oracle=10/10   port-only=3/3
disarm-comment: DIFF 0 port-only, 0 oracle-only -- all 10 rows equal
disarm-comment: DERIV spelling==c and offof_bytes*8==offof_bits on 3/3 FIELD rows: yes
disarm-comment: DISARM same lever, same line, opposite outcome -- the row set is
                byte-identical to the unplanted run
```

The port's stderr is **2225 B, the same 2225 B** as the unplanted run — byte for byte.
Nothing moved, and the gate now says so in those words. (CL-8 records that this
project's *first* disarm moved `SIZE struct Pair` 16→24 because it was a second plant
wearing a disguise; that is why this disarm is the same line and the same granularity,
and why the record-size row is in the census at all.)

### `plant-div`: ONE MEASUREMENT, TWO READERS

`bits / 8` → `bits / 4` in the port's C only, **2 sites**:

```
plant-div: sites patched in the C = 2   rc=0   rows=10/10
  THEOREM FIELD a offof_bytes cannot move: 0/n == 0 for every n
  ONE MEASUREMENT TWO READERS  FIELD b  offof_bits stayed 32  while  offof_bytes moved 4 -> 8
  ONE MEASUREMENT TWO READERS  FIELD c  offof_bits stayed 64  while  offof_bytes moved 8 -> 16
```

**`offof_bits` did not move and `offof_bytes` did.** That is the only control here that
can say the bytes column is a *division* of the bits column and not a second, independent
reading. The gate fails if `offof_bits` moves.

**A theorem, reported as a theorem.** `FIELD a` sits at bit 0, and `0/8 == 0/4 == 0`, so
no divisor and no fixture can separate it. It is a **zero that cannot be fixed**, not a
coverage claim, and the gate prints it as such instead of closing it with a row that
encodes the bug.

### THE GATE IS NOT DISARMED — three of its own controls, by construction

| control | what it would look like if the gate were disarmed | measured |
|---|---|---|
| the census | a removed row still gives 0 disagreements | 9/10, rc 1 |
| the derivation check | `spelling=` and `c=` are the same derivation | they are libclang's vs C's, and they disagree under a plant |
| `plant-div` | `offof_bits` moves with `offof_bytes` | it did not move |

## THE FOUR FIXES THAT MADE THE FILE COMPILE AT ALL

The committed file was **red**, and `bend --check-only` stops a batch parse at the first
error, so these came from iterating to a fixed point, not from reading a header.

| # | defect | fix |
|---|---|---|
| 1 | `type U32 is Data: U32{}` and `type Unit is Data: Unit{}` **redeclare Base's own types** — the `duplicate declaration: U32` in `agent-core.md` | dropped; Base's are the real ones (`references/bend/bend2/base.bend:57`), the `ty_` rows stay |
| 2 | `Ty` is the return type of all **60** `ty_*` defs and was **declared nowhere** | `type Ty is Data: Ty{name: String, spellings: String}` |
| 3 | **13** ABI type names are used in signatures and are not in the enumerated table | declared. `F64`/`I64`/`U64` are among them and are the 16 defs bend has no type for, so they still **cannot be executed** |
| 4 | `type` and `Kind` are bend keywords and were parameter names | `_type` on `clang_Type_getObjCEncoding`, `_Kind` on `clang_getCursorKindSpelling` |

After the four: `bend --check-only` prints only
`Error: 11 defs rely on unsafe or foreign code` — which is the **success** message for a
file with a foreign lane (STAGE1.md), not an error.

The edits are applied by `.agents/slop/clangshim/apply-port-lane.py`, which is
**idempotent** and self-checking (`--check` prints `IN SYNC`), so "regeneration is
byte-identical, committed-equals-fresh" survives as a property. They are **not** in
`.agents/slop/ag-emit.bend`: regenerating without re-running the script puts the file
back to its earlier, non-compiling state, and the header says so.

## WHAT IS STILL NOT COVERED

Unchanged from the audit, and not claimed:

- **311 of the 324** trampolines are still `None{}`. What is verified about all 324 is
  the FUNCTION TRAMPOLINE: name, arity, ordered parameter names, ABI type, return type.
- The other **40** struct records and their fields. `CXCursor` is now measured; `CXType`
  (24 bytes, `kind@0 data@8,16`) and `CXString` (16) were measured on the way and are
  in `libclang-ffi.c`'s comments, but no *row* is emitted for them.
- The **47** enum dicts and their **845** constants; the **32** `TypeAlias` lines.
- The **16** defs whose C return is `long long`/`double`: no bend type, so no law.
- `clang_getOffsetOfBase`, which takes a `const char *` **parameter** — the ~12-line
  `bend_cstr` cons walk is still unbuilt (STAGE3.md, THE STRING LANE). Every law here
  takes a field SELECTOR or nothing.
- `bend <file>` **interpreted** cannot run the lane: `Error: a foreign def without a .js
  import: Loaded_dylib`. A `.c`-imported lane needs `-o`. Every run here used `-o`.

## REPRODUCE

```
B=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
python3 $B/.agents/slop/clangshim/oracle.py                       # the ten rows
python3 $B/.agents/slop/clangshim/cl-port-gate.py --plants        # 0 failures

# and the four working commands, by hand:
cd $TMPDIR/cl-port-gate
$B/bin/bend libclang.bend -o port.gen.c                          # ~149 KB
cc -I. port.gen.c -L/Library/Developer/CommandLineTools/usr/lib -lclang \
   -Wl,-rpath,/Library/Developer/CommandLineTools/usr/lib -o port.out
./port.out
```

## FILES

| file | what it is |
|---|---|
| `tinybendygrad/runtime/autogen/libclang.bend` | **the port.** 324 trampolines (untouched) + 4 fixes + a 10-law FFI lane and `main`. `md5 4c0b6a89cfd82716b1354de91330ac97` |
| `.agents/slop/clangshim/libclang-ffi.c` | the C helper. 10 laws, 280 lines, every ABI declaration annotated with the `otool` line that measured it |
| `.agents/slop/clangshim/fixture.h` | the fixture, twice: the bytes (`CL_FIXTURE_SRC`) and the C declaration, plus the shared `CL_FIELD_NAMES`/`CL_FIELD_SPELL` |
| `.agents/slop/clangshim/ffi-lane.bend` | the lane's text, in ONE place, so the header comment cannot drift from the code |
| `.agents/slop/clangshim/apply-port-lane.py` | applies the four fixes and appends the lane. idempotent, `--check` |
| `.agents/slop/clangshim/cl-port-gate.py` | the gate: the join, the census, the two derivations, two plants and a disarm |