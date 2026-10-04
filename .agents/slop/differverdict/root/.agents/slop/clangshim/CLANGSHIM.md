# CLANGSHIM — the 324 C files and 324 hand-written shims, measured

`tinybendygrad/runtime/autogen/libclang.bend:15-16` says bend's FFI form
"would mean **324 C files and 324 hand-written shims**". This unit exists to
refute that with a running binary. It did, and the numbers behind the framing
changed. **`libclang.bend` itself is untouched** — it is a read-only input here,
and other units cite its hash.

## The one-line answer

**One** `.c`, **one** `import`, **one** `cc`, **zero hand-written shims**,
**12.7 lines per binding** out of a generator. 324 bindings → **308 laws** →
**305 link** → **290 call libclang and return a value**.

| | count | denominator |
|---|---|---|
| bindings in the port's own trampoline | 324 | 552 `clang_*` in Apple's libclang (nm) |
| laws emitted | 308 | 324 |
| **linked** | **305** | 308 |
| **called and returned** | **290** | 305 |
| named and not emitted (64-bit / double) | 16 | 324 |
| absent from this dylib (version skew) | 3 | 308 |
| died on a zero argument, leaf-confirmed SIGSEGV | 15 | 305 |
| Stage 3 falsifiable rows | **8/8** | 8 |

## Reproduce

```
zsh .agents/slop/clangshim/s1.sh   # ONE function, four named steps
zsh .agents/slop/clangshim/s2.sh   # 308 laws; a link loop that names what it drops
zsh .agents/slop/clangshim/s3.sh   # the falsifiable row, run TWICE
```

The scripts `cd` to `$TMPDIR/clangshim` and write nothing in the repo tree.
`$TMPDIR/clangshim/s{1,2,3}.sh` are copies of the files beside them.

| file | what it is |
|---|---|
| `STAGE1.md` | one binding, from the committed file to a linked, called binary |
| `STAGE2.md` | the generator, the counts, the per-function cost vs the estimate |
| `STAGE3.md` | the falsifiable row: same-process C-vs-Bend, plant and disarm |
| `STAGE4.md` | all 19 drops, attributed; and what is still blocked |
| `clangshim-gen.py` | the generator: 324 bindings → `shim.c` + `shim.bend` |
| `clang-cost.py` | splits the generated lines into shared and marginal |
| `clang-analyze.py` | the type/arity census, and the 324/324 signature cross-check |
| `leaf.c` | the census failures' leaf cause, with **no bend in the process** |

## The two things a reader should not skip

**1. The estimate was 2.1× low, and it is the only number here that changed the
cost picture.** `ffi-port-cost.py` predicts 3 law + 3 C = 6 lines per function.
Measured: **6 Bend** (a law block is `law` / type / blank / `def` / `import` /
blank) and **6.66 C** (the `extern` declaration is a third line nobody counted).
12.7 marginal, 14.2 all-in. The censused form is 22.2, because the fork is 9.5
lines per binding and is not optional — without it the plain form builds and then
**dies at the first law that needs a live handle**.

**2. These are signatures that link and return values, NOT a device runtime.**
`E2E-PROVES-COMPUTE` is still **1/1** and `e2e.sh` still proves exactly one
matmul on real hardware. What the FFI wall was made of is now known: **the 16
that cannot be emitted are a missing Bend TYPE (`F64`, `I64`), not a missing
INTERFACE.** The other wall is on *callers*, not bindings — **every `Nat` in bend
2.0.35 is linear**, so one handle cannot serve two calls and no libclang round
trip is expressible from Bend.

## Three findings the units that wrote the input should see

1. **`ffi-port-cost.py`'s `Types.resolve` expands a multi-argument `c.CFUNCTYPE`
   into its ARGUMENT LIST**, so `T.resolve("CXInclusionVisitor")` is a
   comma-separated string. Its counts are unaffected, so 307/17 still stands; its
   per-argument spelling is unusable. `clangshim-gen.py` parses `c.CFUNCTYPE[R,
   [A, B]]` itself.
2. **`c.POINTER[ctypes.c_char]` never canonicalises to `*char`**, so a
   `const char*` parameter is silently typed `Nat` and `bend_cstr`/`io_str` are
   never emitted. A classifier must be verified by **compiling** its output, not
   by counting: the first run reported a clean 308 and emitted
   `extern void* clang_getFile(..., ctypes.c_char*)`.
3. **`clang_getTypePrettyPrinted`, `clang_isBeforeInTranslationUnit` and
   `clang_visitCXXBaseClasses` are in the bindings and NOT in Apple's libclang
   17.0.0.** The bindings are `CINDEX_VERSION_MINOR = 64`. `s2.sh` drops exactly
   the symbols the linker names and prints them.

## The harness defects this unit hit, all of which produced a FAKE GREEN first

Recorded because they are the same shapes as the ones `agent-core.md` warns
about, and each one is a rule now in `bend2-constraints.md` as `S-` 2, 5, 9, 10, 11:

* a stale `shim.gen.c` from a failed build **printed like a pass**;
* a status array that **starts at 0 where 0 means success** reported 305/305
  green next to 15 `bend: memory fault` lines;
* an attribution written **after** `return` — dead code — so nothing was recorded;
* `fork()` duplicating an unflushed stdout buffer, 2,129 lines where 264 were
  expected;
* `Nat.show` aborting the whole run on the first answer above 2^51, so a 305-row
  census printed 13 rows and stopped.