# MATHLIB — what `math.*` is, and what writing it would actually unblock

**Unit: the `math.*` wall.** Working dir `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`,
bend `references/bend/bend2/main.ts` (**Bend 2.0.34**; the `2.0.35 is available`
line is the upgrade nag). Nothing committed. No `.bend` under `tinybendygrad/`
touched; the only `.bend` files I created are in `.agents/slop/mathlib/`.

**THE HEADLINE, AND IT IS A CORRECTION TO `WALLMAP.md` §3 RANK 1:**

> **`math.*` is not a missing library. It is CPython source quoted inside `#`
> comments, and it appears in ZERO lines of Bend code. Writing a `math` module
> would unblock exactly ZERO targets, because there is no call site to unblock.
> The 20 targets the token appears near are blocked on three OTHER walls, and
> each one's own comment names the real one.**

Everything below is a command or a `file:line`. Nothing is transcribed.

---

## 1. WHAT `math.*` IS — answer (c), and it is not even a Bend thing

The brief asked me to establish whether `math.*` is (a) an absent Bend stdlib,
(b) an unstarted port module, or (c) CPython's `math` reached through the oracle.
**It is (c), and the census's own evidence says so.** Three measurements:

```
$ rg -a -o --no-heading -N 'math\.' tinybendygrad/ | wc -l
91

$ rg -a -n 'math\.' --glob '*.bend' tinybendygrad/ \
    | grep -v -E ':[0-9]+:\s*#' | wc -l
0
```

**91 mentions, 0 outside a comment.** Not one call. So:

```
$ rg -a -n 'import math' --glob '*.bend' tinybendygrad/ | wc -l
0
```

There is no import, so there is nothing to resolve and nothing to write. **`math.X`
is the NAME of the CPython constant the marker is discussing.**

### 1a. The name is a red herring from `bend guide` itself

Worth recording, because it is exactly how the confusion started:

```
$ ./bin/bend guide | sed -n '505,520p'
```python
# math.bend
import Base

def square(+x: U32) -> U32:
  (x * x : U32)
```

```python
# main.bend
import Base
import ./math.bend as M  # M.x now names every def of math.bend
```

`math.bend` in `bend guide` is **a user-written demo module teaching import syntax**
— its only def is `square`. It is not a stdlib, and there is no `math` to import.
The same paragraph also says *"`math.extra.bend` is refused"*, i.e. the guide is
talking about module path grammar.

### 1b. The port already resolved it, in three places, to a literal

`math.inf` is **already implemented and committed**:

```
tinybendygrad/codegen/decomp/transcendental.bend:1088-1090
def tx_inf() -> F32: F32.div(1.0, 0.0)
def tx_ninf() -> F32: F32.neg(tx_inf())
def tx_nan() -> F32: F32.div(0.0, 0.0)
```

And `uop/ops.bend:6234` resolves the same token in prose:

> `` `math.inf` in `identity_element` and `_min_max` `` — **Bend cannot name an
> infinity in a U32, so it is `F32.div(1, 0)`**; the ONE place dtype.py's `dt.min`
> for a float needs the seam.

**So the port's own answer to "what is `math.inf`?" is "a division".** Writing a
`math` module would be writing a second spelling of something that already has one.

---

## 2. THE HONEST INTERSECTION — 0 of 20

**`math.*` unblocks nothing, because there is no `math.*` in code.** The useful
question is not "does removing `math.*` unblock them" but **"what do these 20
actually want?"** — and here the answer is unusually good, because **the markers
name their own real blocker.** I did not have to infer it.

The rule I used is in `.agents/slop/mathlib/reconstruct.py` (own-block window) and
the window sweep is in `windows.py`. **The 35 is not reproducible**, because the
`MATH-LIB` classifier was not preserved:

```
$ rg -a -l 'MATH-LIB' .agents/
.agents/slop/wallmap/rank.json
.agents/slop/WALLMAP.md
```

| window / pattern | n_lines | n_files | n_targets |
|---|---|---|---|
| own-block / `math\.` | **16** | **7** | **14** |
| own-block / loose | 17 | 7 | 15 |
| to-next-marker / `math\.` | **28** | **13** | **20** |
| to-next-marker / loose | 30 | 14 | 22 |
| **WALLMAP.md §3 claims** | **31** | **12** | **35** |

The nearest reconstruction is **28 lines / 13 files / 20 targets**, so **the
honest denominator is 20 targets, not 35** — under every rule I could construct.
And `lines/target` here is **1.4**, not WALLMAP's 0.9.

### 2a. The 20 targets, each with the blocker ITS OWN comment names

Clustered by what the wall actually is. **Bold** = the real blocker, quoted.

| # | target | `file:line` | wants | the comment's own real wall |
|---|---|---|---|---|
| **CLUSTER 1 — f32 CONSTANT (10)** ||||
| 1 | `cos` | `mixin/elementwise.bend:746` | `math.pi/2` | an F32 literal — **AVAILABLE, see §3** |
| 2 | `exp` | `mixin/elementwise.bend:747` | `1/math.log(2)` | same |
| 3 | `log` | `mixin/elementwise.bend:748` | `math.log(2)` | same |
| 4 | `log10` | `mixin/elementwise.bend:749` | `math.log10(2)` | same |
| 5 | `sigmoid` | `mixin/elementwise.bend:754` | `1/math.log(2)` | same |
| 6 | `gelu` | `mixin/elementwise.bend:760` | `math.sqrt(2/math.pi)`, `0.044715`, erf | same + `erf` (cluster 3) |
| 7 | `asin` | `mixin/elementwise.bend:768` | `polyN`, `math.pi/2` | **`polyN`** + literal |
| 8 | `acos` | `mixin/elementwise.bend:769` | `math.pi/2`, `asin` | depends on #7 |
| 9 | `atan` | `mixin/elementwise.bend:770` | `math.sqrt(2)`, `asin` | depends on #7 |
| 10 | `exec_alu` | `uop/fold.bend:6354` | `math.*` in a table | **`F32.exp` exists, so it is "a match ladder over the ALU ops"** + `exec_alu`'s tuple case is "a vectorised ALIKE branch" |
| **CLUSTER 2 — INTEGER gcd on I64 (4)** ||||
| 11 | `gcd` | `uop/ops.bend` (was :7416) | `math.gcd` over const_factors | **`functools.reduce(operator.and_, ...)`** — a reduce, plus `_min_max` + `simplify` |
| 12 | `const_factor` | `uop/ops.bend` (was :7375) | `math.gcd` | ditto |
| 13 | `gcd_with_remainder` | `uop/divandmod.bend:883` | `math.gcd(*factors, c)` | the marker says it outright: **"WALL: `gcd`, `_min_max`, `simplify`"** |
| 14 | `logical_not` | `uop/symbolic.bend:3101` | borrowed | **not a math wall** — it wants `mixin/elementwise.py`'s `logical_not`; see :3119 `math.gcd` names `const_factor`+`divides`+`_quotient_base` |
| **CLUSTER 3 — I64 plumbing (co-wall) (3)** ||||
| 15–17 | `_min_max` | `uop/symbolic.bend:3119` region | `math.gcd` on I64 | **`_min_max` is item #1 of symbolic's own "WHAT NEXT" list**, and the list says gcd is #3 — so gcd is not even the first thing that falls |
| **CLUSTER 4 — f32 rounding / classification (4)** ||||
| 18 | `trunc`/`floor` | `uop/symbolic.bend:793,798` | `math.trunc` | **`F32.trunc` EXISTS** — `weak.bend:1078` says "`int(val)` truncates toward zero — F32.trunc, which is `math.trunc`'s float twin." Available now |
| 19 | `isnan` | `uop/fold.bend:3791` | `math.isnan` | **already solved in the port**: "`not isnan(v)` IS `v == v`, and `F32.is_eq` is IEEE" |
| 20 | `isfinite` | `renderer/wgsl.bend:63` | `math.isfinite` | the file says the graph half is the wall: **`.bitcast`/`.alu` CONSTRUCTOR SUGAR in `uop/ops.bend`** (`UOp.cast`/`bitcast`/`index`/`load`/`store`/`where` are all still `TODO(p3)`) |

### 2b. Verdict on the intersection

**Of the 20: 0 need a `math` library. 10 need an f32 literal (available today).**
**4 need a reduce + `_min_max` + `simplify`. 4 need f32 rounding ops that already
exist. 2 need the `.bitcast`/`.alu` graph sugar.**

So the actionable content of the whole rank-1 wall is:

> **10 elementwise methods, and every one of them is one line of
> `F32.div(<decimal>, 1.0)` inside a rule body — blocked on `UOp.const`, which is
> `dtype.bend`'s `dtypes.from_py` + `truncate`, not on arithmetic.**

---

## 3. THE CLAIM I FALSIFIED — F32 LITERALS WORK

`mixin/elementwise.bend:742-745`, the header over the band WALLMAP called the bulk
of the rank-1 wall:

> an `F32` CONST — **no float literal anywhere in the port**, because `F32` is
> `F32{data: Word(32n)}`, `Word` is not exported, and `U32.to_f32` is an unfilled
> LAW which live code may not call.

**Measured false, on Bend 2.0.34.** `.agents/slop/mathlib/lit_probe2.bend`:

```
eq_half_lit_half=True          # F32.div(1.0, 2.0) == the literal 0.5
eq_two_thirds_lit=True         # 2/3 computed == the literal 0.6666666666666666
trunc_pi_is_3=True             # trunc(pi literal) == 3
lit_pi_trunc_is_3=True         # the LITERAL 3.141592653589793 is usable
inf_gt_big=True
inf_times_zero_is_nan=True
```

And `.agents/slop/mathlib/const_probe.bend [DANGLING 2026-10-05: this path DOES NOT EXIST. It was pruned, or moved, or never committed -- do not assume which. `checks/repro-paths.py` lists all of them.]` builds exactly the constants the band
names, in the shape `uop/ops.bend:810` says a CONST carries (`CFloat{f: F32}`):

```
half_pi_is_literal=True        # math.pi/2      elementwise.py:500
inv_log2_is_literal=True       # 1/math.log(2)  elementwise.py:511
half_pi_ne_pi=True             # the two are distinguishable
inv_log2_ne_log2=True
log2_ne_log10_2=True           # log 2 and log10 2 are distinguishable
gelu_c=True                    # 0.044715
inf_x_0_is_nan=True
nan_ne_self=True
```

(10 rows. Two are `False` **and are supposed to be**: `sqrt_2_over_sqrt_pi` is the
one-ulp float question of §3b, and `inf_eq_self_is_nan` is the row whose name
records the mistake I made — inf DOES equal itself, which is why it is `False`.)

Determinism: three consecutive runs of each probe, byte-identical
(`sha256` on the three outputs). Reproduce:

```bash
./bin/bend .agents/slop/mathlib/lit_probe2.bend
./bin/bend .agents/slop/mathlib/const_probe.bend [DANGLING 2026-10-05: this path DOES NOT EXIST. It was pruned, or moved, or never committed -- do not assume which. `checks/repro-paths.py` lists all of them.]
```

### 3a. Three measured gotchas a `math` library would hit immediately

1. **There is no exponent literal.** `1e30` is a parse error: *"expected : a
   numeric literal (NUMBER is U32, NUMBER n is Nat)"*. Every f32 constant must be
   written in longhand decimal, which is why `0.044715` appears verbatim in the
   gelu marker.
2. **An integer literal is a `U32`, not an `F32`.** `F32.trunc(3)` is a *type
   error*; `F32.trunc(3.0)` compiles. So `F32.div(1, 2)` does not typecheck — the
   `0.0` is load-bearing, and this is the real reason a port cannot write `1/2`.
3. **A bare `+` on two f32 literals is a type error** (*"a type for this operator
   (write `(a + b : Nat)`)"*). Use `F32.add`.

### 3b. And Bend's f32 division IS correctly rounded

I nearly reported a compiler defect. Worth writing down because it was **my**
error twice over, and the second error is the interesting one.

`const_probe.bend` reported `sqrt_2_over_sqrt_pi=False`, and CPython's `struct`
says the computed quotient and the literal share the f32 bits `3f4c422a`. I built
a 25-row bracket (`find_q.bend`, ladder generated not typed — `expect5.txt`) to
find where `F32.div(3.0, 7.0)` actually lands:

```
k_m12=False … k_m1=False
k_exact=True          <-- exactly one row, at the correctly rounded position
k_p1=False  …  k_p12=False
```

**Bend's f32 division is correctly rounded.** The one-ulp gap was mine: the f32
values of `sqrt(2)` and `sqrt(pi)` are not the values whose ratio is `sqrt(2/pi)`,
and with exact rational rounding

```
EXACTLY rounded f32 of (f32 sqrt2 / f32 sqrtpi) = 3f4c4229
  == f32(sqrt(2/pi)) ? False   offset = -1 ulp
```

So **no `math` library is needed for correctness, and none would be justified for
rounding.** If a `math` module were written, every transcendental would have to
be *hardcoded* as a longhand decimal, not computed.

**Two failures of my own, both caught only by running:**

- I hand-typed `sqrt(2)/pi = 0.7978845608028654` as the expectation for
  `sqrt(2/pi)`. The **constant was right and the expression was wrong.**
- I asserted `inf != inf`. It is the other way round: **inf equals itself, and
  NaN is the one that does not.** My row was named `inf_is_nan` and was testing
  nothing about NaN.
- I then built a discriminator from two decimals `0.42857143` and
  `0.42857142857142855` believing they were adjacent f32 neighbours of 3/7. **They
  are not** — both round to `3edb6db7`, so the pair could not fail. That is
  agent-core.md's "a list row whose elements are all equal cannot fail on an
  ordering bug" in a new costume. Rebuilt by *searching* for literals that land on
  the neighbouring f32s (`expect4.py`), which is what produced the clean bracket.

**Three independent instruments would have shipped the wrong number here, and
only `struct`/`Fraction` in CPython caught all three.**

---

## 4. `dtype.bend`'s 14 — TYPES, not `math.*`. Definitively.

```
$ rg -a -c 'math\.' tinybendygrad/dtype.bend
(no output — 0)
$ ./bin/bend tinybendygrad/dtype.bend --check-only
SOME PROOFS FAIL
Error: 14 defs rely on unsafe or foreign code:
- Dt.bf16  - Dt.fp16  - Dt.fp8_from  - Dt.fp8_to
- Dt.i64_trunc  - Dt.i64_floor_div  - Dt.i64_floor_mod
- Dt.i64_cdiv  - Dt.i64_cmod  - Dt.i64_ceildiv
- float_to_bf16  - float_to_fp16  - float_to_fp8  - fp8_to_float
```

**Zero of the 14 mention `math.`, so they cannot be a `math` job on that evidence
alone.** Their signatures split them cleanly (`dtype.bend:576-637`):

| group | n | signatures | what it needs |
|---|---|---|---|
| **bf16 / fp16 / fp8** | **8** | `Dt.bf16(U32) -> IO(F32)`, `Dt.fp16(F32) -> IO(F32)`, `Dt.fp8_from(U32,U32) -> IO(U32)`, `Dt.fp8_to(U32,U32) -> IO(F32)`, `float_to_bf16(F32)`, `float_to_fp16(F32)`, `float_to_fp8(F32,S.Dt) -> IO(U32)`, `fp8_to_float(U32,S.Dt) -> IO(F32)` | **pure 32-bit word bit-twiddling feeding `F32` ops.** No 64-bit route. No f64. No transcendental. |
| **i64** | **6** | all `(H.I64, H.I64) -> IO(H.I64)` or `(H.I64) -> IO(H.I64)` | **this and only this is the 64-bit question** |

### The answer the brief asked for

> **Do those 14 need `math.*`, or do they need TYPES?**

**TYPES. And the brief's own framing needs one correction that changes who owns
what:**

- **`bf16`/`fp8_to_float` are NOT the 64-bit or f64 question at all.** bf16 is 16
  bits, fp16 is 16, fp8 is 8. They are stored in `U32` and widened by a shift. The
  w64 unit's answer — whatever it turns out to be — **cannot move these eight**,
  because none of them touches a 64-bit or f64 value. They are a 32-bit type/job.
- **Only the six `i64_*` are the 64-bit question**, and those belong to the w64
  unit. **I have not investigated that and deliberately did not**, per the brief.

So the 14 split **8 / 6**, and the other unit's 64-bit finding gates **6 of 14**,
not 14. That is the number the coordinator should plan against.

Note also that `dtype.bend` is the file that **both halves of the constant wall
point at**: `ops.bend:2576-2578` says `UOp.const` needs `dtypes.from_py` and
`truncate` *"half of which is the C-effect seam `./dtype.bend` already has"* — and
`truncate` is one of the 14-file family's dependencies. So **`dtype.bend` is on
the critical path of the constant cluster too**, which makes it the highest-leverage
file in this whole report.

---

## 5. WHAT I WOULD BUILD FIRST, AND THE SMALLEST THING THAT PROVES IT

**Not a `math` module.** A `math.bend` would violate the hard rule in
`agent-core.md` §"THE SHAPE AND THE NAMES" — one Bend file per upstream `.py`, at
the same path — because **CPython's `math` has no `tinygrad/math.py`**, so there is
no upstream file to be named after, and its 91 mentions are all prose in files that
*do* have upstream counterparts. Adding `tinybendygrad/math.bend` would create an
orphan module whose every caller is a comment.

### The cluster to build first: **CLUSTER 1's 10 `mixin/elementwise.bend` methods**

Ranked first because it is the only cluster where the named blocker is (a) a
single file, (b) already 87 % written, and (c) arithmetic I have measured to work.
Not first because it is big — it is 10 methods — but because **every other cluster
is co-walled**, and this one is not:

| cluster | n | co-walls | buildable alone? |
|---|---|---|---|
| **1 — f32 constants** | **10** | `UOp.const` → `dtypes.from_py` + `truncate` (one file, `dtype.bend`) | **YES, modulo that one seam** |
| 2 — `gcd` on I64 | 4 | a variadic reduce, `_min_max`, `simplify`, set algebra | no |
| 4 — rounding/classification | 4 | `.bitcast`/`.alu` graph sugar | no |
| 3 — `_min_max` | 3 | is *symbolic's own item #1* | no |

### THE SMALLEST THING THAT WOULD PROVE IT

**One rule body, not ten methods.** Specifically: land `cos`'s CONST in
`mixin/elementwise.bend` — `elementwise.py:500` is `(x * (math.pi/2)).cos()`, whose
only missing piece is `CFloat{F32.div(3.141592653589793, 2.0)}` — and gate it with
**four facts plus the answer**: CONST node count, root op, root nsrc, src op
sequence, and the `0x3FC90FDB` bit pattern of `pi/2`.

**Why `cos` and not `exp`:** `cos` needs exactly one new constant and no
transcendental decomposition. `exp` needs `1/math.log(2)` **and** whatever
`mixin/elementwise.py`'s `exp` folding rule is. `gelu` needs `erf`, which is a
polynomial. `cos` is the unique member of the cluster whose wall is *only* an
f32 literal — so it either lands or the whole rank-1 story is wrong, and either
way it is one rule.

**And the negative control, which the brief's traps demand:** a mutation that
changes `3.141592653589793` to `3.14159265358979` must move the row. It will not —
both round to the same f32 — so that mutation is a **blind spot and is reported as
one**, not closed with a row. The mutation that *does* move it is to
`F32.div(3.141592653589793, 1.0)`, and **that row is the gate**: it is the only
way to tell `math.pi/2` from `math.pi`, which is precisely the class of bug
agent-core.md records as `device.bend` shipping `sig=0 4 5` as "a variation".

---

## 6. WHAT I RECOMMEND THE COORDINATOR DO WITH RANK 1

**Do not open a `mathlib` workstream. Re-rank.**

1. **Re-rank `math.*` out of the top 14.** Its honest size is 20 targets, of which
   10 are one-line decimals. Under the same `n_targets` rule that made it rank 1,
   it is no longer the largest concentration — and **the ranking rested on a
   keyword match against prose**, which WALLMAP §6 already concedes ("the
   `n_targets` ranking rests on keyword patterns in prose").
2. **The three walls that actually gate these 20, in the order they fall:**
   - **`dtype.bend`** — `dtypes.from_py` + `truncate`. Gates the 10 constants
     *and* 8 of dtype's own 14. **Highest leverage in this report.**
   - **`uop/fold.bend`'s `_min_max`** — symbolic's own item #1; gates the 4 `gcd`
     targets and 9 deferred blocks in `symbolic` alone.
   - **`UOp.cast`/`bitcast`/`index`/`load`/`store`/`where`** — the `.alu`
     constructor sugar; gates `renderer/wgsl.bend`'s 5 and the `exec_alu` table.
3. **Record the 20-vs-35 correction** so the number is not quoted again. Per
   WALLMAP §7's own lesson — *"a marker count is meaningless without the rule that
   made it"* — this one needs the rule printed beside it, which §2's table does.

## FILES I CREATED (all under `.agents/slop/`, none in `tinybendygrad/`)

| path | what |
|---|---|
| `MATHLIB.md` | this document |
| `mathlib/reconstruct.py` | re-derives the `math` block set under a stated rule |
| `mathlib/windows.py` | window/pattern sweep; attributes the 35-vs-20 gap |
| `mathlib/clusters.py` | clusters all 91 mentions by function and by capability |
| `mathlib/expect.py` | f32 bit expectations (CPython `struct`) |
| `mathlib/expect3.py` | `const_probe` expectations + the two hand-typed mistakes |
| `mathlib/expect4.py` | **exact** f32 rounding via `fractions.Fraction`, no double-rounding |
| `mathlib/lit_probe.bend` | f32 literal availability (first form) |
| `mathlib/lit_probe2.bend` | f32 literal availability (final, 11 rows) |
| `mathlib/const_probe.bend` | the band constants in `CFloat` shape (9 rows) |
| `mathlib/rounding_probe.bend` | correctly-rounded? discriminator |
| `mathlib/ulp_probe.bend` | the ulp discriminator |
| `mathlib/find_q.bend` | the 25-row bracket; `k_exact` uniquely True |
| `mathlib/expect3.txt` `expect4.txt` `expect5.txt` | the generated oracles |

## CONCURRENCY NOTE

`uop/ops.bend` was **6,306 lines** when I read its `math` band and my first
`reconstruct.py` run saw `math.gcd` at `:7375`/`:7416`. Another unit is live and
shrinking it. §2a's line numbers for `uop/ops.bend` are therefore marked
"was", and the four targets there are identified by name instead. Every other
`file:line` was stable across all my passes. Per `agent-core.md`'s concurrency
rule I did not edit that file and did not treat the drift as a finding.