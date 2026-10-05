# CSTYLE2 — `renderer/cstyle.bend`'s 227 rows, in four columns, and 30 of them running

Unit **cstyle2**. Slot: re-measure the recorded state (`227 rows: 216 text · 11 C · cc accepts 6
· 2 executed · 226 still text`), say what a *text* row is, and convert as many as the case
allows. **Nothing committed. `renderer/cstyle.bend` was not edited** — sha256
`07ae2766f891e9a85bed84c416bab21f9a17c143730aa26383d685998c97eb7f` before and after, asserted by
`run-all.sh` and again by `plant.sh`.

One command, from a clean `$TMPDIR`, whole tree snapshotted:

```
zsh checks/run-all.sh
```

Verified end to end at rc=0. Apple clang 21.0.0 (arm64), `bend` 2.0.34 (2.0.35 available).

---

## 1. THE FOUR COLUMNS, against 227

`TEXT` is **not** a structural guess. It is `cc`'s own exit status on the unescaped value in the
dialect the row's device names, with *no toolchain blamed for it*. An earlier unit's structural
`is_tu` test disagreed with `cc` on **8 of 227** rows, so it was replaced rather than kept.

### As emitted — nothing added, nothing wrapped

| column | n/227 | what it is |
|---|---|---|
| **TEXT** | **161** | `cc` rejected the value |
| **COMPILES** | **3** | `cc` exited 0 — `buf2 BASE LOC`, `buf2 HIP LOC`, `buf2 OPENCL GLOB` |
| **EXECUTES** | **0** | nothing links and runs, because nothing is a program |
| **AGREES** | **0** | — |
| *TOOLCHAIN-ABSENT* | *63* | *CUDA 41 + METAL 22: no front end on this machine. Kept OUT of TEXT on purpose.* |

161 + 3 + 63 = 227. **The recorded "216 text fragments · 11 C" does not reproduce under either
of these definitions and has no definition attached**, so it is not comparable to this table.

### After conversion — a TU built around each row's own value, declaring only what upstream declares

| column | n/227 | what it is |
|---|---|---|
| **TEXT** | **193** | 227 − 34 |
| **COMPILES** | **34** | 31 wrapped by `convert2.py` + 3 `buf2` declarations that were already C |
| **EXECUTES** | **30** | it linked and ran, printing bit patterns |
| **AGREES** | **29** | its output equalled tinygrad's own, from a live CPython call |

**The one that does not agree is `cfo BASE SIN f32`, and THE PORT IS RIGHT AND tinygrad's CPU
BACKEND IS 1 ulp OFF.** port `d55b7f3f` = 0.99749499559 (the correctly rounded float32 of
`sin(1.5f)`); tinygrad `CPU` `d45b7f3f` = 0.99749493599; tinygrad `PYTHON` `d55b7f3f`. And the
reason is structural: `Ops.SIN not in Device["CPU"].renderer.code_for_op` — **`ClangRenderer`
deletes `EXP2, SIN, LOG2, TRUNC, RECIPROCAL` from the table** (`tinygrad/renderer/cstyle.py:291`),
so no `cfo` row describes what the CPU backend emits for SIN, and `cfo BASE SIN f32` pins a
rendering no real device ever runs. **This is the first measurement in this port that has produced
a NUMBER a real tinygrad device disagrees with**, and it took four columns to see it: the string
gate is green on this row.

---

## 2. THE DENOMINATOR, DERIVED

`renderer/cstyle.bend`'s `main` is a flat sequence of row-emitting calls, one call one row, so
the expected count is **counted from the source** (`derive.py`) and never typed:

```
STATIC  row-emitting calls in cstyle.bend's main()   227
OBSERVED rows parsed by cstyle-gate.py's rows_strict  227
        lines the reader shredded (not rows)          0
        duplicate row NAMES the reader saw            0 []
static family multiset == observed family multiset   (21 families, per-family delta +0)
```

**Rows-present against rows-expected is a SET comparison, not a count** — 227 agreeing while one
family were swapped would print one number and hide the swap. Per-family: `cfo` 70, `rd` 42,
`kern2` 30, `idx` 20, `kern` 8, `buf2` 9, `tmap`/`buft`/`witem` 6 each, `type` 5, `opt`/`wmma` 4,
`under`/`leg`/`img` 3, `ptr`/`acc`/`cast` 2, `hipockl`/`hipocml` 1 each.

### THE EMPTY-FILE TRAP — 5 of a naive "cc accepts" count are refusals

An **empty C file is a valid translation unit**, so `cc` exits 0 on a row whose value is `""`:

```
rows whose value is the empty string AND whose cc exited 0   5/227
  cfo BASE  FDIV f32 · cfo CLANG EXP2/LOG2/RECIPROCAL/SIN f32
COMPILES above excludes them; a naive cc-accepted count reports 8/227.
```

`cc` accepting zero bytes is not the port's answer compiling. **This is a count of a different
thing and it is the same shape as every other one in this project's history.**

---

## 3. WHAT A *TEXT* ROW ACTUALLY IS — and which cause dominates

Assigned BY RULE, printed BY ROW NAME so the rule can be checked (`measure.py`,
`four-col.tsv`).

| cause | n/227 | families | what it is |
|---|---|---|---|
| **(a) STRING BY DESIGN** | **187** | `cfo` 63+7, `rd` 42, `idx` 20, `kern` 8, `buf2` 9, `tmap` 6, `buft` 6, `witem` 6, `type` 5, `opt` 4, `wmma` 4, `under` 3, `leg` 3, `img` 3, `acc` 2, `cast` 2, `ptr` 2, `hipockl` 1, `hipocml` 1 | upstream's function under test RETURNS a string for someone else to splice. 64 of the 187 are **JOINED** — the gate itself concatenated 7 or 16 or 5 values with `|`/`,`/` / `,` (`cstyle-gate.py`'s `cells()`), so the row is not even one C value |
| **(b) NEVER REACHED THE RENDERER** | **30** | `kern2` | **the only family whose value is a whole translation unit, and every one of its 30 rows splices `g_kernel()`, a two-line literal.** `cstyle.bend`'s own words: *"THE KERNEL BODY, two lines, verbatim from the oracle"*. `render_kernel`'s framing is exercised; nothing inside the body is |
| **(c) DISPATCH NOT COVERED** | **7** | `cfo` | upstream REFUSES and the row pins the refusal. **Verified live, not read off the `py=` literal** (`empty-probe.py`): `Ops.FDIV` is in no `code_for_op` table except `ClangRenderer`'s, which adds it at `cstyle.py:292`; the other 4 are the ops `ClangRenderer` deletes at `cstyle.py:291`. The port's `""` is a faithful `KeyError` |
| compiles | 3 | `buf2` | |

> ## **(a) DOMINATES: 187 of 227, and 187 of the 224 that are not C.**
> **"226 still text" is overwhelmingly (a) — the row's output is a string by design and no
> compiler will ever accept it standing alone.** The genuinely actionable remainder is
> **30 (b) + 7 (c) = 37 rows**, and the 63 toolchain-absent rows are not a port problem at all:
> of those 63, **52 are inside (a)**, 9 inside (b), 2 inside (c).

**And a fourth thing the recorded 226 hid completely:** 6 of the `cfo` rows name an **integer op
on a float dtype tag** (`AND`, `CMOD`, `OR`, `SHL`, `SHR`, `XOR` on `f32`), and `cc` refuses them
with *"invalid operands to binary expression ('float' …)"*. Upstream never renders those
pairings, so those fixtures are un-instantiable on any host. 4 more (`CDIV`, `FDIV`, `CMPEQ`,
`CMPNE`) compile and run but compute a FLOAT operation, so they agree while testing nothing
about the integer semantics they name — labelled in `agree.py`, not counted silently.

---

## 4. THE CONVERSION — every row gated THREE ways

`convert2.py` never edits a row's value. It builds a TU around it and records every added line in
the row's `added` column. **The flags are tinygrad's** (`compiler_cpu.py:14-17`), not mine.

| gate | n/227 | |
|---|---|---|
| **GATE 1 `cc` accepts** | **31** | 6 `kern2` + 25 `cfo` |
| **GATE 2 links and runs** | **30** | 6 `kern2` + 24 `cfo` |
| **GATE 3 equals tinygrad** | **29** | 1 disagreement, and the port is right (§1) |

**What was supplied, and where it came from**

- `kern2` (30 rows): **one line** — the vector prefix upstream's `_render_defines` emits, captured
  LIVE from `Device["CPU"].renderer.render_vector_prefix(float32, 4)` (`preamble-oracle.py`):
  `typedef float float4 __attribute__((aligned(16),ext_vector_type(4)));`. This re-measures
  `CSTYLE-LIVE`'s `b5a0753d` prefix rather than quoting it.
- `cfo`: the variables the row's own value names (`cc` decides the arity — no op table), plus
  `#include <math.h>` because the BASE tables emit **bare** `sqrt(X)`/`sin(X)` and no real device
  compiles them (`ClangRenderer` replaces them with `__builtin_*`, `cstyle.py:293-294`), plus
  `#define half _Float16` for `f16`, which the port's own HIP `kern2` rows carry.
- `cfo HIP`: the `__ocml_*` declarations **taken from this same run's `hipocml` row** — the port's
  own output is the preamble for the port's own output. It compiles (gate 1) and then **cannot
  link**, because those are declarations with no definition. Two of three gates, honestly.

**The driver is derived from the row's own text**: the parameter list is copied out of the row
with names replaced, the buffer size from the highest `val0[k]` its body reads, `aligned_alloc`
so the compiler cannot drop the store, and a `-12345.0f` sentinel no lane of `in+1` can produce.

**Which `kern2` rows still will not compile, and why** (24 of 30; `kern2` splits
BASE 5 / CLANG 3 / CUDA 6 / HIP 10 / METAL 3 / OPENCL 3):

| n | first error | rows |
|---|---|---|
| 10 | `'amdgpu_flat_work_group_size' attribute only applies to kernel functions` | all 10 `kern2 HIP*`. `-x c++` is present; the attribute is a hard error off an AMD target and **`-Wno-error` does not downgrade it** (measured twice) |
| 9 | *no CUDA installation / no `-x metal`* | 6 `kern2 CUDA*`, 3 `kern2 METAL*` |
| 3 | `casting '__global float *' to type '__private float4 *' changes address space` | `kern2 OPENCL{,f16,pref2}`. **`-x cl` WORKS on Apple clang 21** and genuinely rejects this — and **this is the FIXTURE's body, not the port**: `g_kernel()` casts a `__global` pointer to a private one, which CPython never renders because `uops=[]` |
| 2 | `use of undeclared identifier 'data1_4'` | `kern2 BASE alu`, `kern2 CLANG alu` — **the fixture's `g_bs_alu()` declares scalar parameters while `g_kernel()` reads buffers**, so the row's body names identifiers its own signature does not declare. `cc` found a defect in the fixture, not in the renderer. The driver also declines them independently, for the same reason by a different route: a signature with no pointer parameter leaves nothing a host could observe |

---

## 5. PLANT AND DISARM — twice, and the live tree untouched

`plant.sh`, in `$TMPDIR`, hash-asserted before and after. `plant.log`.

**PLANT 1 — aimed at GATE 3, because GATES 1 AND 2 CANNOT SEE IT.** One token in the port's own
fixture, `g_kernel()`: `val0[0]+1.0f` → `val0[0]-1.0f`.

```
BASELINE   GATE 1 31/227   GATE 2 30/227   AGREE 29  DISAGREE 1
PLANTED    GATE 1 31/227   GATE 2 30/227   AGREE 23  DISAGREE 7
DISARMED   GATE 1 31/227   GATE 2 30/227   AGREE 29  DISAGREE 1
```

Rows moved, **by name**: exactly **6** — `kern2 BASE`, `kern2 BASE pref0`, `kern2 BASE pref2`,
`kern2 BASE vol`, `kern2 CLANG`, `kern2 CLANG vol` — and the only column that changed is `bits`.
**`four-col.tsv` records differing: 0 of 227.** A correct arithmetic defect is invisible to
`cc`, to the link, and to the whole four-column table. That is the whole argument for the fourth
column, measured rather than asserted.

**PLANT 2 — aimed at GATE 1.** `sig_args` joins the kernel's parameters with `", "`; changed to
`"; "`. `GATE 1 31→25`, `GATE 2 30→24`, **19 rows moved**, disarm restores 31/30 and 29/1.

**The guard refused a 31-row plant before it happened.** The first anchor was `val0[0]+1.0f`,
which occurs **31** times — 30 of them in `kern2_row`'s own `py=` oracle literals. The guard
counted, printed `anchor occurs 31 times, expected 1. REFUSING.`, and the run stopped. The
anchor is now the whole `g_kernel` list literal, which occurs **once**. **A plant that moves
100k rows is a strong plant filed under the wrong heading; a plant that moves nothing because
the anchor missed is worse, and only a count catches it.**

---

## 6. WHAT REMAINS TEXT — 193 rows, by name and cause

Full per-row table: **`four-col.tsv`** (227 lines, header, `cause` and `first_error` per row) and
`convert2.tsv` (227 lines, `gate1_cc`/`gate2_run`/`bits`/`note`).
`renderer/cstyle.bend` is cited **by NAME** below; the line numbers are this snapshot's and the
file is one a generator once damaged, so they are a convenience and not an identity.

Split of the 193: **63 have no front end on this machine, 130 are rejected by a front end that
is present.** By family, with the cause:

| emitter in `renderer/cstyle.bend` | line | rows still text | cause | first error, grouped |
|---|---|---|---|---|
| `cfo_row` / `cfo_where_row` | 1746 / 1752 | **45** of 70 | (a) 38 · (c) 7 | 21 toolchain-absent (CUDA/METAL); **7 refusals, correctly never wrapped**; 6 integer-op-on-float; 7 HIP `half`/`__ocml_*` needing `#define half _Float16` in the row's own preamble; 2 `bf16` with no host C type; 2 `OPENCL` (`pointers to functions are not allowed`); 2 `WHERE` rows whose name carries no dtype tag |
| `rd_row` | 1711 | 42 | (a) JOINED, 7 cells | `unknown type name 'fp8e4m3'`, `a type specifier is required`, +38 |
| `kern2_row` | 1891 | **24** of 30 | (b) | see §4 — 10 HIP, 9 CUDA/METAL, 3 OPENCL, 2 `alu` |
| `idx_row` | 1940 | 20 | (a) single | `unknown type name 'B'` ×5, `use of undeclared identifier 'R'` ×3, +12 |
| `buf_row` / `buf_sz_row` | 1724 / 1729 | 9 of 9 | (a) single | `unknown type name 'half'` ×3, `unknown type name '__local'`, +5 — **3 of the 9 already compile as emitted** and are counted in COMPILES, not here |
| `kern_row` | 1770 | 8 | (a) single | a PREFIX (`extern "C" __global__ void __launch_bounds__(1)`), so `expected identifier or '('` — correct: upstream's `kernel_typedef` returns only the prefix and `render_kernel` splices it |
| `tmap_row` / `buft_row` / `witem_row` / `opt_row` | 1695 / 2080 / 1734 / 1816 | 6 / 6 / 6 / 4 | (a) JOINED | 16, 5, 2 and 6 cells respectively — **not one C value each** |
| `type_row` | 1950 | 5 | (a) single | `unknown type name '__global'`, `unknown type name 'fp8e4m3'` |
| `ptr_row` / `acc_row` / `cast_row` | 1953 / 1827 / 1956 | 6 | (a) single | `expected ')'`, `expected function body after function declarator`, … |
| `wmma_row` / `under_row` / `img_row` / `legacy_row` | 1780 / 1786 / 1794 / 1959 | 13 | (a) single | macro names and type names — strings by design |
| `hipockl_row` / `hipocml_row` | 1834 / 1847 | 2 | (a) single | `extern "C" …` is C++, and the BASE lane is `-x c`. **`-x c++` accepts both** — a one-line dialect fix in the harness, recorded here rather than done, because no number in this report depends on it |

---

## 7. WHAT THIS DOES NOT CLAIM

1. **`cstyle-gate.py` and `renderer/cstyle.bend` were NOT touched.** The one edit `CSTYLE-LIVE`
   §7 asks for — `emit_min()` carrying the vector prefix — is still unmade, because it changes
   the gate's expectations and that is the coordinator's call. §4 shows it is worth exactly
   **6 rows** of the 30 that compile now, and it would make the gate's own `kern2 CLANG` row a
   regression test instead of a rescue.
2. **The 63 toolchain-absent rows are not "wrong text".** 22 `kern2` rows are byte-for-byte with
   a live CPython call; the compilers are absent. Calling that 22 rows of port defect is the
   exact move §4's OPENCL entry shows to be wrong in the other direction: for OpenCL the text is
   right, the front end is present, and it **rejects** — because the *fixture's* body is invalid
   OpenCL C.
3. **30 rows executing is not "the renderer works".** 6 of them are `kern2`, whose body is a
   fixture literal, so what runs is `render_kernel`'s framing. The interior of a kernel has still
   never been rendered by the port and executed. **`(b) 30/227` is the number that says that, and
   it is the next thing worth converting.**
4. **`agree.py`'s op map is the one thing written by hand** — the oracle's own knowledge of what
   a reference implementation does. A wrong entry makes a row **disagree**, never agree; the one
   disagreement found was in the *reference*, not the port.

---

## 8. THE RULES, appended as **CS2-1 … CS2-6** to `.agents/slop/notes/bend2-constraints.md`

Append-only at the end, nothing renumbered, cited by NAME (rule NUMBERS repeat across units —
`agent-core.md`).

- **CS2-1 — AN EMPTY C FILE IS A VALID TRANSLATION UNIT, SO `cc` EXITS 0 ON A REFUSAL.** A
  "cc accepts" count over rows whose answer can be `""` counts the empties as compiling. Here
  **5 of 8** naive acceptances were refusals. Any compile count over rows that can be empty must
  subtract them, and say how many it subtracted.
- **CS2-2 — `aligned_alloc(64, n)` REQUIRES `n` TO BE A MULTIPLE OF 64** (C11 7.22.3.1). Asking
  for 16 bytes of 64-byte alignment returns NULL; every kernel row then died on `SIGSEGV`
  (`rc=-11`), which reads as "the kernel crashed" and is really "the harness asked illegally".
- **CS2-3 — A KERNEL THAT STORES THROUGH `float4*` INTO A `float buf[N]` STACK ARRAY HAS ITS
  STORE DROPPED BY `-O2`.** Two causes at once: `buf` is not 16-byte aligned so the store is UB,
  and nothing in the TU says the callee's store reaches the later read of `buf[0]`, so clang may
  answer that read from the register the initialiser left there. The observed symptom is the
  INPUT's own bits coming back. `aligned_alloc` removes the whole class.
- **CS2-4 — `-ffreestanding` REMOVES THE C BUILTINS, AND `CStyleLanguage` EMITS BARE
  `sqrt(X)`.** Upstream's CPU flags include `-ffreestanding`, and its own CPU renderer replaces
  the base table's math with `__builtin_*`, so **no real device ever compiles a bare `sqrt(X)`**
  and `render_kernel` emits no `#include` for it. A harness instantiating a BASE `cfo` row must
  supply `math.h`, and should say that it did.
- **CS2-5 — A ROW'S VALUE CAN NAME IDENTIFIERS ITS OWN SIGNATURE DOES NOT DECLARE.**
  `g_bs_alu()` builds scalar parameters while `g_kernel()` reads `data1_4`/`data0_4`; `cc` finds
  it as `use of undeclared identifier`. A row can be byte-identical with CPython and still
  describe a program that does not exist.
- **CS2-6 — A ROW'S OP AND ITS DTYPE TAG CANNOT MEET.** `AND`, `CMOD`, `OR`, `SHL`, `SHR`,
  `XOR` on an `f32` tag: `cc` says *"invalid operands to binary expression ('float' …)"*.
  Upstream never renders those pairings, so the fixture is un-instantiable on any host, and the
  five that *do* compile and run (`CDIV`, `FDIV`, `CMPEQ`, `CMPLT`, `CMPNE`) compute a FLOAT
  operation while appearing to test an integer one. **A row that agrees because both sides
  computed something else is a row that tests nothing** — label it, do not count it silently.

---

## 9. THE TREE GATE, AND ONE CORRECTION TO THE BRIEF

```
zsh .agents/slop/substrate-check.sh tinybendygrad/renderer/cstyle.bend
WARM   tinybendygrad/renderer/cstyle.bend  (2373 lines)  [bend --check-only]
ROUTE  bend=1  cc=0  node=0  no-instrument=0  (of 1 file(s))
NAMES  (5 modules, 522 refs, 522 exact, 0 suffix-only, 0 unresolved, 250 unseen, 1 unused-import)
SUBSTRATE CLEAN
```

⚠ **THE BRIEF'S TRAP LIST IS ONE STEP BEHIND: THE `.c` LANE IS NO LONGER `NO INSTRUMENT`.**
The brief says it "is currently `NO INSTRUMENT` because `dtype.bend:687` fails typecheck"; on
this tree the route prints **`cc=0`**, i.e. the C instrument ran and was green, and
`no-instrument=0`. Either `dtype.bend` was fixed or the route changed. `cc` is the gate used
here regardless, so nothing in this unit depends on the answer.

Also recorded, because the instrument prints its own blind spot and `unseen=250` is the number
to read rather than the verdict: the name check is scoped to the **import graph** and cannot see
the unaliased `import Base` surface (`List.` `String.` `U32.`), which is most qualified refs in
the tree.

---

## 10. THE FILES

| file | what it is |
|---|---|
| `run-all.sh` | the one command. Snapshot (hash-asserted identical) → 8 steps → plant/disarm. |
| `derive.py` | the DERIVED denominator: 227 static calls, compared to 227 rows as a SET. |
| `measure.py` | the four columns + the cause of every non-C row, assigned by rule. |
| `convert2.py` | the conversion and gates 1–2. Driver derived from each row's own signature. |
| `agree.py` | gate 3. Two reference devices (`CPU`, `PYTHON`), numbers, never a typed `py=`. |
| `preamble-oracle.py` | the one withheld declaration, captured live from `render_vector_prefix`. |
| `empty-probe.py` | are the 7 empties refusals? live CPython, `code_for_op`'s own dict. |
| `plant.sh` | two plants, both disarmed, live tree hash-asserted untouched. |
| `four-col.tsv` / `convert2.tsv` | the per-row evidence, 227 lines each, headered. |
| `four-col.txt` / `convert2.txt` / `agree.txt` / `derive.txt` / `plant.log` | the transcripts these numbers come from. |