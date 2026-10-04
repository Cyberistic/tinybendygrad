# W64-MILE — the last 64-bit mile, taken

Unit: `.agents/slop/w64mile/`. **Nothing committed, nothing in the live tree.**
Compiler: **Bend 2.0.34** via `./bin/bend` (the `2.0.35 is available` line is an
upgrade nag).

```sh
W=$TMPDIR/w64mile; mkdir -p "$W"; cd "$W"
cp -R /Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinybendygrad tree/ 2>/dev/null || \
  { mkdir tree; cp -R /Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinybendygrad tree/; }
git -C /Users/cyberistic/src/tries/2026-09-30-tinybendygrad show HEAD:tinybendygrad/helpers.bend \
  > tree/tinybendygrad/helpers.bend
cp /Users/.../.agents/slop/w64mile/{patch_dtype.py,i64-pure.bend.txt,gen_i64.py} .
python3 patch_dtype.py tree && python3 gen_i64.py ; echo "M-1 exit $?"
export LIBCLANG_PATH=/Library/Developer/CommandLineTools/usr/lib/libclang.dylib
python3 gen_halves.py  > halves.txt      ; echo "M-2 census exit $?"
python3 emit_halves.py > halves.txt      ; echo "M-2 build  exit $?"
```

## What `W64.md` said, and what held

Everything in `W64.md` held. `H.I64` is `I64{hi: U32, lo: U32}`
(`helpers.bend:1639`), two `U32` halves carry a `double` across the FFI bit for
bit, and `Nat` is not the answer to anything 64-bit. **One premise in it is now
wrong, in the direction that matters:** the six `Dt.i64_*` were never blocked on
`H.I64`. They were blocked on **being `IO(..)`**, and the pure 64-bit ALU they
needed was already in `helpers.bend`. A type that exists and a body that does not
look identical from outside a `--check-only` run.

## M-1 — `dtype.bend`'s six `Dt.i64_*`, pure Bend, 172 rows against CPython

| | before | after |
|---|---|---|
| `--check-only` on `tinybendygrad/dtype.bend` | **14** defs rely on unsafe or foreign code | **8** |
| the 8 that remain | `Dt.bf16`, `Dt.fp16`, `Dt.fp8_from`, `Dt.fp8_to` + 4 fp8/f16 wrappers | 32-bit, another unit |
| signature | `IO(H.I64)` — unreachable from a pure fold | `H.I64` — a pure function |

`mixin/dtype.bend:52-60` records the cost of leaving them as effects:
`UOp._min_max` is a pure fold in a Kahn worklist, so it cannot call an effect,
and that is why it is not total. **That note's wall is now half-closed**: div and
mod are pure, and `i64_mul` and a shift are still not.

```
BASE   PASS   rows present 173 / 173   pass=170  diverge=2  fail=0  control ok
PLANT  PASS   7 rows moved, every one of them a `cmod` row
DISARM PASS   0 rows moved
```

**Port beside CPython**, the asked-for add's neighbours (`hi:lo` is the pattern,
the decimal is the value):

| `a`, `b` | CPython `cdiv` | port | CPython `cmod` | port |
|---|---|---|---|---|
| `7, 4` | `1` | `0:1` | `3` | `0:3` |
| `-7, 4` | `-1` | `4294967295:4294967295` | `-3` | `4294967295:4294967293` |
| `7, -4` | `-1` | `4294967295:4294967295` | `3` | `0:3` |
| `-7, -4` | `1` | `0:1` | `-3` | `4294967295:4294967293` |
| `-8, 4` | `-2` | `4294967295:4294967294` | `0` | `0:0` |
| `5, 0` | `0` | `0:0` | `5` | `0:5` |
| `-9223372036854775808, 4` | `-2305843009213693952` | `3758096384:0` | `0` | `0:0` |
| `-9223372036854775808, -4` | `2305843009213693952` | `536870912:0` | `0` | `0:0` |
| `-9223372036854775808, 3` | `-3074457345618258602` | `3579139413:1431655765` | `-2` | `4294967295:4294967294` |

**The plant** drops the `- b` in `Dt.i64_cmod.put`, so the remainder keeps the
floor's sign. It moves exactly **7** rows and every one names `cmod` — checked
against the mutation site, not against a transcribed list, because a moved set
that is not exactly the rows the edit can reach means the lane is not the one
under test. The rows that do **not** move are the ones that must not: `8,4` and
`-8,4` (exact, so `fix` is false), `7,4` and `2^62,3` (same sign), and the three
other defs.

**The disarm** rewrites `Dt.i64_trunc` from `x` to `H.i64_or(x, H.i64_zero())` —
a different expression for the same function. Zero rows move. Without it, the
plant's seven could have been seven rows that move for a reason the harness
invented.

**`H.i64_dec` has no image for `int64.min`** (`helpers.bend:2050` answers the
`hi:lo` pattern there). So the three `int64.min` decimal rows are **not printed**
rather than asserted with the port's own fallback — a row asserting that would
encode the port's behaviour as though Python had said so. They are covered by the
bit-pattern family instead, which is why rows expected is 173 and not 193.

### The gate caught one of my own bugs, and it is worth naming

`Dt.i64_ceildiv` first read `H.i64_neg(H.i64_is_neg(b), b)` where it needed
`H.i64_neg(True{}, b)`. `i64_neg(neg, x)` negates `x` **when** `neg`, so that
expression is `|b|`. `i64_ceildiv(7,4)` printed `-1` where CPython says `2`.
Every other row was already green when it happened — the fixture that separates
the floor from the truncated quotient on same-sign input is what caught it.

## M-2 — the 16 blocked libclang bindings, 15 of 16 now compile, link and run

`clangshim-gen.py` is **imported, never edited** (another unit's slop tree), and
its own `plan()` is where "which row is blocked, and on what" comes from.

| | count |
|---|---|
| trampoline rows | 324 |
| laws `clangshim-gen.py` emits | 308 |
| blocked on a Bend type | **16** (15 `I64`, 1 `F64`) |
| **64 bits on the RETURN only** | **16 / 16** — no blocked binding has a 64-bit PARAMETER |
| emitted by M-2, compiled, linked, **run** | **15 / 16** |
| port line == CPython's ctypes line | **15 / 15** |
| laws that compile, link and run | **308 + 15 = 323 / 324** |

```
BASE   PASS   built 15/16   rows present 15   port == CPython 15 of 15
PLANT  PASS   1 row moved -> ['clang_getEnumConstantDeclValue']
                 derived from the mutation's algebra: rows with hi != lo = the same one
DISARM PASS   0 rows moved
```

**The one port-beside-CPython comparison, three answers in one.** The fixture is a
null handle, so libclang answers sentinels, and all three come back over two
halves:

```
clang_Type_getSizeOf(0)                port hi=4294967295 lo=4294967295   CPython hi=4294967295 lo=4294967295
clang_getEnumConstantDeclValue(0)      port hi=2147483648 lo=0            CPython hi=2147483648 lo=0
clang_EvalResult_getAsDouble(0)        port hi=0 lo=0                     CPython hi=0 lo=0
```

`0xFFFFFFFF_FFFFFFFF` is `-1` and `0x8000000000000000` is `int64.min`, so the high
word is not always 0 and a harness that only ever saw `0:0` would have proved
nothing. **The plant is thin and that is the measurement.** libclang's null-handle
answers are `0`, `-1` and `int64.min`; `0` and `-1` have `hi == lo`, so a transpose
is *invisible* on 14 of the 15 — the `a b c a` trap in 64-bit dressing. The
moved set is asserted to be exactly the asymmetric rows rather than to be
non-empty, and the fixture set is reported as the thing that would need widening
before a second swap-based mutation could be read.

### The 16th is not a Bend-type wall

`clang_getOffsetOfBase` compiles, links as far as the symbol, and then

```
Undefined symbols for architecture arm64:  "_clang_getOffsetOfBase"
nm -gU libclang.dylib | grep -c _clang_getOffsetOfBase$   ->  0
```

The bindings are `CINDEX_VERSION_MINOR = 64` and the dylib is 17.0.0, so that is
**version skew**, the class `clangshim/STAGE4.md` already names for three other
symbols. It is not the 64-bit problem and cannot be fixed in Bend.

### Three build facts, each one a compile round

1. **`#ifdef CID(x)` does not work**, and `runtime/dtype.c:246` uses it. `CID` is
   a macro and the preprocessor does not expand an `#ifdef` operand that looks
   like an invocation, so the guard is false for every binding and the file
   fails `CID(...) names no constructor or def`. `clangshim-gen.py` escapes this
   only because it declares all 308 laws in one `.bend`, so all 308 `CID`s exist.
   **M-2 gives each binding its own `.c` for that reason**, and the guard form in
   `dtype.c` is reported, not fixed — that file is read-only here.
2. **Pass the imported `.c` to `cc` twice and it stops compiling.** Bend
   *inlines* it into the emitted C after the runtime typedefs; handing it to `cc`
   as a second translation unit is where `unknown type name 'Env'` comes from.
3. **`Nat` and `U32` are not interchangeable at a call site.** The zero argument
   is spelled in the law's own parameter type: `0n` for a `Nat`, `""` for a
   `String`. Passing `U32.from_nat(0n)` to a `Nat` parameter is
   `expected : Nat / observed : U32`.

## M-2 census — what the callers actually do with 64 bits

**7 call sites, 5 of the 16 bindings, 11 with no call site at all.** `libclang.bend`
declares a law for all 16, so the 16 are *named* everywhere and *called* almost
nowhere; the scan is over the bare name, not `name(`, because `autogen.py:159`
picks one of the two enum accessors with a conditional and calls the result — a
`name(` scan misses both and would understate the wall.

| site | operation on the answer | covered by |
|---|---|---|
| `tinygrad/runtime/support/autogen.py:33,34` | `// 8` | `i64_div` — gated in M-1 |
| `tinygrad/runtime/support/autogen.py:148` | `% 8` | `i64_mod` — gated in M-1 |
| `autogen.py:151,159,164` | rendered as decimal into generated source | `i64_dec` (`helpers.bend:2060`) |

**So 16/16 are transports and 0/16 need `double` arithmetic.** The one `F64` of
the 16, `clang_EvalResult_getAsDouble`, has **zero call sites** in `tinygrad/` and
`tinybendygrad/`. That is the `math.pi` shape `W64.md` found for `math.*`: a
blocked name with nothing behind it.

## What is left, with `file:line`

1. **`i64_mul` does not exist.** `mixin/dtype.bend:56`. Upstream `cmod` is
   `x - cdiv(x,y)*y`, so the port's `cmod` is an identity over the floor pair
   rather than the upstream expression. The identity is swept against CPython on
   16 fixtures, but it is not the upstream spelling and a caller that wants the
   multiplication still cannot have it.
2. **`i64_shr` does not exist**; `helpers.bend:1819` has `i64_shl` only.
   `mixin/dtype.bend:58` says "SHL/SHR NOWHERE" and that is now half stale. Every
   shift a call site needs today is a constant `// 8` or `% 8`, so nothing blocks
   on it — a variable 64-bit shift does.
3. **`clang_getOffsetOfBase` is absent from libclang 17.0.0.** Library version,
   not a language wall. `tinygrad/runtime/autogen/libclang.py` is
   `CINDEX_VERSION_MINOR = 64`.
4. **`runtime/dtype.c`'s `#ifdef CID(...)` guards cannot compile** (M-2 build fact
   1). Reported, not fixed: that file is read-only for this unit. The C lane of
   the dtype seam has therefore never been built, which is worth knowing before
   anyone reads a green `--check-only` as a green C lane.
5. **`runtime/autogen/libclang.bend` still declares `I64` / `U64` / `F64`** at
   `libclang.bend:617,620,644,647,746,752,764,770,773,782,806,1121,1151,1157,1160,1334`.
   That is a *third* route beside M-1's pure `H.I64` and M-2's two `U32` halves,
   and it is the one that makes the emitted file fail (`duplicate declaration:
   U32`). The emitter mints one `type` row per ctypes spelling, which is the known
   recorded defect, but the **declarations** are still there. Someone should decide
   which of the three routes is the port's.
6. **`W64.md`'s claim that a 64-bit pair cannot be returned from one foreign def
   is contradicted by `runtime/dtype.c:210`**, which returns `io_tup(e, hi, lo)` —
   a tuple Term. M-2 uses the two-def shape because that is the shape W-4 ran, and
   a one-def form would halve the cost. **Not measured.** That is the cheapest
   open question in this unit.
7. **`ceildiv(x, 0)` is a divergence, not a pass.** `tinygrad/helpers.py:66-69`
   has no zero guard, so CPython raises `ZeroDivisionError`; `runtime/dtype.c:236`
   and `runtime/dtype.js:171` answer 0 and so do the new pure defs. Counted as
   `diverge`, checked against the port's own 0, never counted as a pass.

## Bookkeeping

- `.agents/TODO.md` — appended, `M-` prefix (not in the taken list).
- `.agents/slop/notes/bend2-constraints.md` — appended, `M-` continues there.
- **LIVE TREE NOT TOUCHED.** The patch is `dtype-i64.patch` beside this file and
  `dtype.patched.bend` is the whole result; `tinybendygrad/dtype.bend` is still 638
  lines and untouched by this unit.
- **WHY IT DID NOT RUN IN PLACE, and the hazard it hid.** For a large part of this
  session `tinybendygrad/helpers.bend` was **0 bytes** in the working copy — another
  agent had emptied it, and `jj status` inferred a rename
  `{tinybendygrad/helpers.bend => .agents/slop/nested/baseline-probe.err}` between two
  empty files. Every `.bend` in the tree could not be checked in place, so the work ran
  on a `$TMPDIR` copy with `helpers.bend` restored from `HEAD`. It was back at
  116,479 bytes (HEAD is 116,482) by the end, so **the hazard was a live agent's and
  it cleared** — but `jj` reporting a `helpers.bend` RENAME when the file is merely
  EMPTY is a trap worth naming, because a reader sees a move that was never intended.
  The same restore-from-HEAD recipe is what let this unit keep going.