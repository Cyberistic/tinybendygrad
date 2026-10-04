# F64-KERNEL — an `f64` kernel through the port, end to end

Unit: `.agents/slop/f64/`. **Nothing committed.** Compiler: **Bend 2.0.34** via
`./bin/bend` (the `2.0.35 is available` line is an upgrade nag).

```sh
zsh .agents/slop/f64/run-f64.sh          # the lane, its controls, and the artifact
```

It is wired into `.agents/slop/e2e.sh` as **stage 7**, additively: `jj diff` on
`e2e.sh` is **0 lines removed, 45 added**, and stages 1–6 are byte-unchanged. The
whole artifact was run: **7 stages, `0 failed, 0 skipped`, exit 0.**

---

## The claim, and how much of it is the port

The port's `renderer/cstyle.bend:2475` `render_kernel` was handed four `BArg`s
carrying `S.double()` and returned:

```c
void mm(double* restrict data0_4, double* restrict data1_4, double* restrict data2_4, double* restrict data3_4)
```

`cc -Wall -Werror` compiled that text alone. **Bend** then allocated three buffers,
filled them from u32 word lists, **launched the kernel by pointer**, and read 64
`U32` words back. No Node, no browser, no `navigator.gpu`, no tinygrad scheduler.

Not claimed: that the port *scheduled* anything. `cstyle.bend` has no `_render`, so
the loop nest is `emit-f64.bend`'s fixture, exactly as `g_kernel()` at
`cstyle.bend:1879` is one. This is `portexec`'s claim, one dtype wider.

## The 64/64 bar — words, diff bytes, and CPython side by side

| | |
|---|---|
| words port | **64** |
| words expected | **64** |
| **diff bytes (external `diff`)** | **0** |
| differing lines | **0** |
| first 8 port | `4096 1072693248 1024 1075314688 512 1076625408 256 1077280768` |
| first 8 CPython | `4096 1072693248 1024 1075314688 512 1076625408 256 1077280768` |

The diff is recomputed **out of the lane**, in `run-f64.sh` section 3, by
`awk` + the external `diff` — a number read out of the instrument that produced it
is not a second witness (`e2e_port/run-port-mm.sh:118-131`).

**Bonus row, free, and it is the strongest one here:** the port's emitted C is
`diff`ed against **upstream's own `ClangRenderer.render_kernel`** on the same body
lines and `dtypes.f64` — **diff bytes = 0**. Two independently written sources (the
Bend file and `oracle_f64.py`) that agree byte for byte.

64 words is 32 doubles: an f64 element is **two `U32` words at the 4-byte stride
`fill.go`/`dump.go` already walk**, so `NBYTESn = len(words) * 4` was already right
and **no `double` ever crossed the FFI**. That is `W64.md`'s two-`U32` route, now on
a kernel rather than on a scalar.

## The value `f32` cannot hold

`out[0] = (A@B)@D[0][0] + 2**-40 = 1.0 + 2**-40`.

| | out[0] | CPython |
|---|---|---|
| **f64** | `(lo=0x00001000, hi=0x3ff00000)` = **`0x3FF0000000001000`** | `struct.pack('<d')` → `0x3ff0000000001000` |
| **f32 twin** | **`0x3F800000`** = **`1.0` exactly** | `np.float32(1.0 + np.float32(2**-40)) == 1.0` → `True` |

Same kernel shape, same harness, same launch, different width, different answer. The
width is real and is not a label.

**The constant is a fixture literal, and the brief's known soft spot is answered
rather than dodged.** The port emits **no float literal at all** — there is no
`_render` — so `+ 9.094947017729282e-13` is a `String` in the body, exactly as the
matmul loop nest is. It survives because `oracle_f64.py:177` re-derives
`repr(2.0**-40)` and **refuses to emit an oracle** if the committed literal disagrees,
and because the proof is not the literal but the **output word**: a dropped or
truncated constant gives `0x3FF0000000000000` and the lane goes red.

## My plant and my disarm

| | what | outcome |
|---|---|---|
| **C0** | the copy, unplanted | **GREEN** — mandatory, or nothing below means anything |
| **inherited ×2** | `run-kernel.sh`'s own `fill B into A's buffer` and `never call the kernel` | **RED**, verbatim on the f64 text |
| **inherited ×1** | `k < 8` → `k < 7` | **THEOREM**, see below |
| **P1** | `2**-40` → `2**-39` **in the kernel** | **REFUSED** — the oracle's two CPython paths stopped agreeing |
| **P1b** | the same shift **in the oracle**, kernel untouched | **REFUSED** — the paired disarm |
| **P1c** | one bit of expected **word 37** | **RED** — `MISMATCH at 1/64 words, first 5: [(37, 1078427648, 1078427649)]` |
| **P2** | `S.double()` → `S.single()`, so the port emits `float*` | **REFUSED** — and the log names `void mm(float* restrict data0_4, …)` |

**P1 and P1b are the pair.** P1 alone cannot distinguish a correct lane from one that
reads its expectation out of its own output, because a self-read passes *any* kernel
plant. P1b has the kernel **right** and the expectation wrong by one binade; only a
real comparison goes red.

**P2 is the discriminator that makes section 4 non-vacuous.** Same harness, same
oracle, same launch, and the port's dtype narrowed — if that were not caught, the lane
would be checking a *word count* and not the width.

**The theorem, and its price.** `run-kernel.sh:205`'s `k < 8` → `k < 7` plant went
GREEN here, and it is a theorem of the **fixture**: `B` is `[I_4 ; 0]`, so
`B[k][j] = 0` for every `k ≥ 4` and `A[i][k]·B[k][j] = 0` for every `k ≥ 4` **for any
`A`**. Making `A` dense forces `B` dense, which stops `A@B = diag(2,1,1,1)`, which is
what makes `out[0]` **exact** instead of the root of a rounded solve. The exactness of
the discriminating value and the viability of that inherited control are in direct
trade. The committed harness already sets the precedent (`run-kernel.sh:215-222`,
"A control that cannot fail is reported as a theorem, not quietly counted towards the
three"), so `run-f64.sh` replaces the `ctl` line with a `THEOREM` line **in the copy**,
in the open, uncounted.

## Harness reuse: three edits inside a copy, and the committed harness untouched

`portexec/` is committed and **never written to**. `run-f64.sh` copies
`tinybendygrad` + `portexec`, symlinks `bin/ references/ tinygrad/ .venv/` (as
`e2e_port/run-port-mm.sh:147` does), copies `emit-f64.bend` over the one filename
`run-kernel.sh` knows, applies **three** `e2e_port/plant.py` edits, and calls
`run-kernel.sh mm` **unchanged** — so all seven named steps, the 220-row substrate
floor, the deterministic-rerun and buffer-distinctness checks, the `MISMATCH at N/64`
string and the mm-mode plants are the committed ones.

The edits, all in the copy, all refusing a vacuous target:

- **E1a** `gen_ffi.py` merges in `oracle_f64.build()`'s keys. Needed because
  `run-kernel.sh` runs `oracle.py` *before* it emits the f64 kernel.
- **E1b** `gen_ffi.py`'s `spread` casts to the **parsed** parameter type instead of a
  literal `(float*)`. **This is FK-1 and it is a real wall in a live harness.**
- **E2** `run-kernel.sh` re-derives `ROOT` from `$0`.
- **E3** replaces the theorem `ctl` line.

## Walls, with `file:line`

1. **`gen_ffi.py:188` casts every buffer to a literal `(float*)`.** The prototype
   (:186), the typedef and the launch order all come from parsing the port's own
   signature, so they follow `S.double()` to `double*` — and the one hard-coded
   literal does not. The cast is a no-op on the *address*, so the call still ran and
   the lane failed **on the answer**, not on the mismatch. `run-kernel.sh:100`
   compiles `run.c` **without `-Werror`**, so its four
   `-Wincompatible-pointer-types` warnings stopped nothing. Three dtype-aware sites
   and one hard-coded literal in the same function; the odd one out is invisible until
   the answer is wrong. `run-f64.sh` now prints that warning count as a row
   (**0 required**).
2. **`renderer/cstyle.bend:2984-3015` calls `rd_row` for seven dtypes and `f64` is not
   one of them.** All 227 rows are silent about `double*`. `tmap CLANG` carries the
   *name* `double` and six `port.txt` lines mention f64, so a reader scanning for
   "f64" can reasonably conclude it is covered. It was not — this lane is the first
   execution of `render_dtype` on `S.double()` in the project. **FK-5.**
3. **A foreign-def `def` carrying a `.c` import must be untuned** (`W64.md:165`) —
   inherited, and it is why the shim is a generated `.c` and not a `.bend` law.
4. **`--check-only` says `ALL PROOFS CHECK` for an empty file.** `.agents/slop/
   substrate-check.sh` checks size first; `run-f64.sh` uses it and **exits 3** — a
   refusal, which `e2e.sh` reports as **`SKIP`, never `PASS`** — if the port's own
   rows cannot be reproduced.

## The substrate moved under me, and it is not my file

`renderer/cstyle.bend` is at `sha256 07ae2766…` and is WARM now, but **it was at
`bed462b6…` (3205 lines) and would not compile**: nine verbatim copies of every
derived-fact reader block (`BArg.name`, `Uses.half`, `Emit_.uses`, `RkIn.pref` — all
nine times) and `bend` refused it with `duplicate declaration: BArg.name`, then
`duplicate declaration: Uses.half`. `.agents/slop/proof-close/mut/tinybendygrad/
renderer/cstyle.bend` is modified in the working copy, so a mutation script is the
likely writer, and `agent-core.md` records "A scripted block move must assert
`end > start`." **Reported, not fixed — it is a do-not-touch file.**

`repair-dupes.py` deletes only *adjacent byte-identical* blocks, smallest first, so
it cannot invent, reorder or reword a line, and it **checks itself two ways**:
`bend` must compile the result (227 rows) **and** the rows must be byte-identical to
the committed good run `cstyle-live/port.txt` (46291 bytes, taken at `07ae2766…`) —
**diff bytes 0**. It touches the snapshot only; `run-f64.sh` prints both hashes.

## Two bugs that were mine, both silent, both worth keeping

**FK-2 — `(lo, hi)` is not `(hi, lo)`.** My first `oracle_f64.py` returned high-word
first with a comment asserting "on this host the HIGH word is the even one", which is
false for little-endian. Every operand became a denormal (`A[0]` read back as
`5.3e-315`), every product was zero, and the kernel returned **exactly `DELTA` for all
32 elements** — 32 plausible doubles, not an error. Caught in one run only because
"the answer is the additive constant and nothing else" is a shape no correct matmul
has. The fix is a round-trip assert, and the comment was the thing that was wrong.

**A freed pointer.** My first `cpython_exec` built its input arrays inside a
generator: `*(p(np.array(v, ...)) for v in (a, b, d))`. The temporaries are collected
when the generator is exhausted, so tinygrad's `prog` got three freed addresses. It did
not crash — it returned 32 plausible garbage floats (`-308074.375, 392869.75, …`).
A reference that outlives the call is not a style choice.

## Files

| file | what |
|---|---|
| `emit-f64.bend` | the f64 fixture: `portexec/emit-mm.bend` with `S.double()` and `double` |
| `oracle_f64.py` | the expectation. port C vs CPython's `render_kernel`; numpy float64 **and** real tinygrad `DEV=CPU`, which must agree; the fixture's constant re-derived |
| `run-f64.sh` | the lane: copy, 3 plants, `run-kernel.sh mm`, external diffs, controls, the artifact |
| `repair-dupes.py` | snapshot-only, self-checking repair of the duplicated blocks |

Artifact rows land in `$W/f64-rows.txt` and are whole `name=value` lines —
`agent-core.md:133` records a name-comparing harness reporting 0 for all 30 mutations
in one unit and 0 for all 68 in another, so a harness must diff whole lines.

Reproduced twice, byte-identical apart from ASLR addresses.