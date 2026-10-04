# STAGE 2 — 308 laws, ONE `.c`, ONE import, ONE `cc`

Reproduce: `zsh $TMPDIR/clangshim/s2.sh` (nothing touches the repo tree)
Generator: `.agents/slop/clangshim/clangshim-gen.py`
Cost: `.agents/slop/clangshim/clang-cost.py`

## The working commands

```
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
CLIB=/Library/Developer/CommandLineTools/usr/lib
cd $TMPDIR/clangshim

python3 $REPO/.agents/slop/clangshim/clangshim-gen.py --out g --probe
$REPO/bin/bend g/shim.bend -o g/shim.gen.c
cc -c g/shim.gen.c -o g/shim.o
cc g/shim.gen.c -L$CLIB -lclang -Wl,-rpath,$CLIB -o g/shim.out
./g/shim.out
```

## THE REFUSAL, AND BOTH HALVES OF IT

`tinybendygrad/runtime/autogen/libclang.bend:15-16`:

> bend has no per-function FFI: its only form is a whole-operation effect — a
> `def` returning IO plus an `import` of a C file — which for this header would
> mean **324 C files and 324 hand-written shims**.

**Half one, "324 C files": false, measured.** The unit of work is **one** `.c`:

```
shim.c    2170 lines, 305 bindings, ONE file
shim.bend 2164 lines, 305 laws,    ONE file, ONE `import "./shim.c"`
```

**Half two, "324 hand-written shims": false as a count, TRUE as a shape, and the
shape is the interesting half.** There are **zero hand-written shims** here — all
305 `_run` bodies come out of `clangshim-gen.py`. What is true is that each
binding *does* need its own law and its own `_run`: 6 Bend lines and ~7 C lines.
That is 12.7 lines per binding, not one.

## THE COUNTS, with the denominator

| quantity | count | denominator |
|---|---|---|
| bindings in the port's own trampoline | 324 | 552 `clang_*` exported by Apple's libclang (nm, measured) |
| laws emitted | **308** | 324 |
| laws emitted that **link** | **305** | 308 |
| shims that **called** libclang and returned | **290** | 305 |
| shims whose forked child died | 15 | 305 |
| laws emitted that were **never reached from `main`** | 0 | 308 |
| gate agreement on names / arity / parameter order | 324/324 | 324 (`clang-analyze.py`) |
| named and not emitted | 16 | 324 |

**324/324 bindings, 308 laws emitted, 305 linked, 290 called.** Every one of those
numbers is a count with its denominator, and the three drops are attributed
individually below.

## THE PER-FUNCTION COST, MEASURED AGAINST THE ESTIMATE

`ffi-port-cost.py` predicted `LAW_LINES_PER_FN = 3` and `C_LINES_PER_FN = 3`, i.e.
**6 lines per function**, from one three-function experiment.

| | predicted | MEASURED (plain) | MEASURED (censused) |
|---|---|---|---|
| Bend lines per law | 3 | **6.00** | 6.00 |
| C lines per binding | 3 | **6.66** (min 6, median 7, max 8) | **16.16** (min 14, median 16, max 19) |
| marginal total | 6 | **12.7** | **22.2** |
| all-in, every shared line | — | **14.21** | 26.46 |
| shared, written once | — | 139 C + 334 Bend | 351 C + 960 Bend |

**The estimate is 2.1× low for the plain shim and 3.7× low for the censused one.**
Two reasons, both measured:

* **The 3 Bend lines are 6.** A law block is `law X:` / the type / a blank /
  `def X(a, b):` / `import "./shim.c"` / a blank. `LAW_LINES_PER_FN = 3` was
  `3 = (2-line signature + 2-line def/import) / 1 fn` — an average, and the block
  is six lines.
* **The 3 C lines are 6.66, not 3, because the extern declaration is a third
  line the estimate did not count**, and because a by-value-struct or
  `const char*` parameter costs one more `pre` line. Histogram:
  `{6: 116, 7: 177, 8: 12}`.
* **The extra 9.5 lines in the censused form are the fork** (`fork` + `pipe` +
  `_exit` + the three join helpers' call + the attribution store), and it is not
  optional: without it the plain form **builds and then dies on the first law
  that needs a live handle** (`bend: memory fault`, rc=1, measured). The fork is
  what buys all 305 rows instead of the length of the prefix before the first
  segfault.

So the honest answer to "is the next 300 affordable": **yes, at 12.7 lines each
and zero hand-written shims** — 3,872 lines of generated code from one script.
The next 300 are not the thing that is expensive.

## WHAT THE FOUR STEPS DID, WHEN THEY FAILED, AND WHAT I GOT WRONG

Four distinct step failures, each named, because "324 C files and 324
hand-written shims" is a claim about a mechanism and a mechanism is four steps:

| step | what broke | the fix |
|---|---|---|
| `bend -o` | `expected : a name / observed : '>'` — a nullary law emitted ` -> IO(Nat)` | a nullary law has **no domain and no arrow**: `law cver: IO(String)` |
| `bend -o` | `def clang_Type_getObjCEncoding(type)` — `type` is a Bend keyword | measured over all 138 distinct parameter names: **exactly one collides**, `type`. The parameter name is only a Bend binder (C reads `f[]` positionally), so it is `_type` on the Bend side only |
| `bend -o` | `Error: an arity over 247` | **a limit on LIVE BINDERS, not on foreign defs.** Holding 308 `s{i}` binders at once makes `main`'s frame wider than `WIDE=247`; one live binder at a time compiles |
| `cc` | my classifier emitted `extern void* clang_getFile(..., ctypes.c_char*)` | `Types.resolve` leaves `ctypes.*` spellings for primitives it has no alias for. **One spelling table, or the classifier reports a clean 308 while emitting C no compiler accepts** — the exact "unexplained success" the brief warns about. Found only because step 2 was run separately from step 3 |
| link | 3 symbols undefined | see Stage 4 |

## TWO REAL DEFECTS FOUND IN THE COMMITTED COST TOOL

Both are in `ffi-port-cost.py`'s `Types.resolve`, **not** in the bindings.

1. **`c.POINTER[X]` where `X` is itself a pointer alias resolves with a
   COMMA-SEPARATED TAIL.** The CFUNCTYPE branch is
   `re.match(r"^c\.CFUNCTYPE\[.*\[(?P<x>.+)\]\]$", t)` — for a *multi-argument*
   CFUNCTYPE that group is the **argument list**, not the return type, so
   ```
   T.resolve("CXInclusionVisitor")
     == "CB:ctypes.c_void_p, c.POINTER[CXSourceLocation], ctypes.c_uint32, ctypes.c_void_p"
   ```
   which is not a C type. It only looks right for `clang_executeOnThread`, whose
   callback has exactly one argument. **Its counts are unaffected** (`CB` was
   never blocked), so the 307/17 it reports still stands — its per-argument
   *spelling* is unusable. `clangshim-gen.py` parses `c.CFUNCTYPE[R, [A, B]]`
   itself.
2. **A `c.POINTER[c_char]` PARAMETER is silently typed `Nat`, not `String`.**
   `classify` tested `t == "*char"`, and `Types.resolve` never produces `*char`
   — it produces `*ctypes.c_char`, which fell through to the pointer arm. So all
   ~30 string parameters and all 30 string returns came out as pointers and
   `bend_cstr`/`io_str` were **never emitted at all** (the first generated
   `shim.c` contained 3 hits for either name; it should have had hundreds).

I chased a third one — `c.POINTER[CXTranslationUnit]` resolving to
`**struct_CXTranslationUnitImpl` — and it is **correct**: `CXTranslationUnit` is
itself `c.POINTER[struct_CXTranslationUnitImpl]`, so a pointer to it is a double
pointer. Recording it because "the resolver double-counts the star" was my
conclusion for ten minutes and it was wrong.

## WHAT IS STILL NOT TRUE AFTER STAGE 2

* These are **signatures that link and return values.** They are not a device
  runtime, and `e2e.sh` still proves exactly one matmul on real hardware.
* **Every `Nat` in Bend is linear**, so a handle cannot be printed *and* passed,
  and **no libclang round trip is expressible from Bend** — two calls on one
  handle need the handle twice. Stage 3 does the round trip inside one foreign
  call for exactly this reason.
* The by-value-struct convention is an **opaque union of the right size**: a shim
  can pass and return a libclang struct over the ABI and **cannot read a field
  of it.** 9 struct typedefs, sizes taken from the binding's `SIZE =` lines.
* A shim's Bend law uses `Nat`/`String`/`Unit` — **three types for 60 C types.**
  The port's own 60 `libclang.bend` types are all `type X is Data: X{}`, a
  nullary constructor, so they are **singletons and cannot carry a handle**; that
  is a type-level fact, not a measurement. The cost of collapsing them: a wrong
  argument type is not caught by Bend's typechecker, it is caught by the process
  dying.