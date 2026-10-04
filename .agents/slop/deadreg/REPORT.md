# DEADREG — the 10 + 1 registrations, and stage 8's true denominator

Owns `tinybendygrad/runtime/dtype.c` and `tinybendygrad/runtime/dtype.js` and nothing
else. **Not committed.** Every `bend` run is under
`checks/bounded.py --seconds 900 --mb 2048`; measured peak RSS 228–507 MB, so the
ceiling was never raised. Compiler Bend 2.0.34.

Reproduce:

```sh
.venv/bin/python .agents/slop/deadreg/build4.py    # the four configurations
.venv/bin/python .agents/slop/deadreg/plant.py     # plant + disarm, five configurations
```

---

## 1. THE COUNT IS **10 + 10**, NOT 10 + 1

The brief says "10 registrations in `dtype.c` and 1 in `dtype.js`". `dtype.js` has
**ten**, at `:199-210`, and all ten are exactly as dead as the C lane's ten.
`jsstage.py` says so itself, on its own line, and I measured it independently:

```
CIDs `dtype.js` registers that `dtype.bend` no longer calls   10
  bf16, fp16, fp8_from, fp8_to, i64_cdiv, i64_ceildiv, i64_cmod, i64_floor_div,
  i64_floor_mod, i64_trunc
```

The brief's line numbers were right (`dtype_fp8_to` is at `:162`, registered at
`:202`). The count was not: it counted the one function the brief happened to name.

## 2. STAGE 8's TRUE DENOMINATOR: **0**, AND IT SHOULD BE RETIRED

`dtype.bend` declares **0** `IO(` laws and **0** `import "./runtime/dtype.*"` lines.
All ten `Dt.*` laws are pure. And **0 `.bend` files in the tree import
`runtime/dtype.c` or `runtime/dtype.js`** — the six textual hits are all comments, in
`dtype.bend`, `helpers.bend`, `base.bend`, `mixin/dtype.bend`,
`runtime/support/nv/nvdev.bend`, `runtime/autogen/libclang.bend`.

**So the JS lane's denominator is not "the 8 rows that do not reach it". It is 0.** The
strongest form of the proof is not about CIDs at all: `runtime/dtype.js` is not one
byte of the emitted bundle.

```
$ node all10.js        # a program calling ALL TEN Dt.* laws
JS8 i64_trunc = 7:0            JS8 bf16     = 1.5
JS8 i64_floor_div = 4294967294:0   JS8 fp16  = 1.5
… all ten rows, rc 0 …
grep -c 'function i64_of\|fp8_encode\|dtype_bf16\|FP8_CFG\|pack64' all10.js
0        # not one of dtype.js's functions is in the emit
grep -c 'CID_' all10.js
0        # the JS lane uses string keys, per the brief's fact 2
grep -n 'io_eff' all10.js
145:function io_eff(k, run, need) {        # the emitted runtime's own definition
160:io_eff("IO.print", io_print);          # and its ONE registration: IO.print
```

**Retire, do not re-point.** There is nothing to re-point *at*: the 20 rows now measure
`dtype.bend`'s pure arithmetic, and `.agents/slop/lastlaw/run.py` already measures
**exactly that** at **1330/1330** (102 i64 + 1228 fp8) against the same CPython
callables. Stage 8's remaining claim is a **19-row echo of a 1330-row gate**. It is red
because it is honest, not because it is broken: `jsstage.py`'s plant
(`p.hi`/`p.lo` → `p.fst`/`p.snd`, the ABI-2 bug that shipped) moves 0 rows precisely
*because* no row reaches the function it plants. Re-pointing would require re-declaring
a `Dt.*` law as a seam — the thing the brief forbids, and the thing that would undo
LASTLAW. **The change to stage 8 is therefore: retire it, and re-point it only if a
`Dt.*` law becomes a seam again.** `jsstage.py` and `e2e.sh` are not mine; this is the
recommendation, and `.agents/TODO.md` carries it as an open item against
`e2e-js-lane`.

## 3. THE CLASSIFICATION, AGAINST THAT DENOMINATOR

| law | `dtype.bend` | C registration | JS registration | status |
|---|---|---|---|---|
| `bf16` | `def Dt.bf16(+bits: U32) -> F32` | `dtype.c:309` | `dtype.js:225` | DEAD |
| `fp16` | `def Dt.fp16(+x: F32) -> F32` | `:314` | `:226` | DEAD |
| `fp8_from` | `def Dt.fp8_from(bits, +kind) -> U32` | `:319` | `:227` | DEAD |
| `fp8_to` | `def Dt.fp8_to(bits, +kind) -> F32` | `:324` | `:228` | DEAD |
| `i64_trunc` | `def Dt.i64_trunc(x: H.I64) -> H.I64` | `:329` | `:229` | DEAD |
| `i64_floor_div` | `def Dt.i64_floor_div(a, b) -> H.I64` | `:334` | `:230` | DEAD |
| `i64_floor_mod` | `def Dt.i64_floor_mod(a, b) -> H.I64` | `:339` | `:231` | DEAD |
| `i64_cdiv` | `def Dt.i64_cdiv(+a, +b) -> H.I64` | `:344` | `:232` | DEAD |
| `i64_cmod` | `def Dt.i64_cmod(+a, +b) -> H.I64` | `:349` | `:234` | DEAD |
| `i64_ceildiv` | `def Dt.i64_ceildiv(+a, +b) -> H.I64` | `:354` | `:236` | DEAD |

**These line numbers are the ones MY EDIT left behind, not the brief's.** The brief's
(283, 293, 298, 303, 308, 313, 318) were right against the file as I received it; my
two comment blocks sit above them and move each by **+36** (`dtype.c`) and **+26**
(`dtype.js`). That is the brief's own warning about citing across two namespaces, and
it now applies to me: **§7 lists every citation into these two files with its current
line, so the next reader is not left with mine or the brief's.** The registrations
themselves are untouched — they are still the last 53 and last 12 lines.

**A name existing is not reachability, and I did not take a name for it.** Two
structural facts carry the classification:

- **Intra-file census: there is no dead code inside either file.** Every `static`
  function in `dtype.c` is referenced by exactly one `*_run` handler, every `*_run`
  handler by exactly one registration. The deadness is *entirely at the registration
  boundary* — which is where it belongs, and which is why the fix is not a deletion
  inside the arithmetic.
- **`CID` is a textual substitution at emit time, so `#ifdef` is resolved by the
  preprocessor against a `#define` bend emits — and bend emits it only for a law some
  build reaches.** Measured: `bend -o` rewrites `CID(Dt.bf16)` inside the pasted
  `dtype.c` to `CID____TREE_TINYBENDYGRAD_DTYPE_DT_BF16` and `#define`s it to `14`, so
  `cc` sees `io_eff(14, bf16_run, 0)`. **No `CID_` token survives into `cc -E` output.**

## 4. THE FOUR CONFIGURATIONS, WITH REGISTERED-EFFECT COUNTS

`szlane`'s shape: reach nothing / one law / the other law / everything — plus the
control that makes their zeros mean something. `cc -E` counts the C lane because
`bend -o` is not a build; the JS lane is read off the emit, since it has no `#ifdef`.

| configuration | `bend` | C lines | `cc` | **C regs** | JS rc | JS bytes | **JS regs** | JS fns | `dtype.c` |
|---|---|---|---|---|---|---|---|---|---|
| `probe-none` (reach nothing) | 0 | 2899 | 0 | **0** | 0 | 12632 | **0** | 0 | NOT pasted |
| `probe-bf16` (one law) | 0 | 3124 | 0 | **0** | 0 | 13811 | **0** | 0 | NOT pasted |
| `probe-ceildiv` (other law) | 0 | 5136 | 0 | **0** | 0 | 28224 | **0** | 0 | NOT pasted |
| `probe-all` (all ten) | 0 | 9009 | 0 | **0** | 0 | 56546 | **0** | 0 | NOT pasted |
| **CONTROL** `probe-ctl-seam` (1 law re-seamed) | 0 | 3363 | 0 | **1** | 0 | 24224 | **10** | 4 | pasted, CID defined |
| **DISARM** `probe-ctl-disarm` (guard → unreached law) | 0 | 3363 | 0 | **0** | 0 | 24226 | **10** | 4 | pasted, CID defined |

**FOUR REAL CONFIGURATIONS: 0 C and 0 JS registrations landed, of 10 and 10 declared.**

Three things this table needed to be trustworthy, each a defect I had to fix first:

1. **The control is not optional.** `0,0,0,0` on its own is *identical* to a guard that
   never fires. The control re-declares `Dt.bf16` as an `IO` seam **in the scratch
   tree's own `dtype.bend`** and gets 1 C / 10 JS — so the zeros read UNREACHABLE.
   It has to be that file: a CID is mangled with the *defining* file's path, so **no
   file outside `dtype.bend`'s own path can ever make these ten guards fire.**
2. **A raw `io_eff(` count is not a count of this lane.** It reads **2 in
   `probe-none`**, because the emitted runtime defines `io_eff` and registers
   `IO.print` for itself. Counting must be keyed on `dtype.c`'s own ten run functions.
3. **The predecessor's control never ran.** It applied its `dtype.bend` patch in the
   caller for one arm and not the other, so `probe-ctl-seam` printed an emit
   byte-identical to `probe-bf16` (3124 lines each). A positive control that patched
   nothing is the one failure this gate cannot have.

The asymmetry, as a number: `dtype.c` guards each registration with `#ifdef CID(...)`
and registers **one law at a time**; `dtype.js` has **no guard** and registers **all
ten** from any single reached law. One law re-seamed: **1 C, 10 JS**. Zero laws reached:
**0 and 0**. That is a real latent defect, recorded in both files' headers, and **not
fixed** — fixing it means editing a file nothing reads.

## 5. PLANT AND DISARM

Five configurations × three arms. `cc` is the build; `exe` is the built binary run.

| arm | `none` | `bf16` | `all` | `ctl-seam` (1 law reached) | `ctl-disarm` |
|---|---|---|---|---|---|
| **shipped** | exe 0 | exe 0 | exe 0 | exe **0**, node **0** | exe **1** alien request, node 0 |
| **DISARM** whitespace-only in all 20 | exe 0 | exe 0 | exe 0 | exe **0**, node **0** | exe **1**, node 0 |
| **PLANT** the 20 registrations deleted | exe 0 | exe 0 | exe 0 | exe **1**, node **1** | exe **1**, node **1** |

- **DISARM** — every space after a comma inside the twenty `io_eff(CID(Dt.…` calls is
  removed. Same program, same twenty registrations, and it counts identically in all
  five configurations. **This is what makes the plant's zero a measurement and not a
  no-op**: without it, "deleting them moved nothing" is also what an irrelevant
  deletion produces.
- **PLANT** — the registrations deleted. `stdout` is byte-identical in all three
  reachable configurations. In the one configuration that reaches the lane it replaces
  a working program with a **named** failure: `bend: an alien request` (C) and
  `Error: bend: no effect registers …/dtype.Dt.bf16` (node). Note *where* it fails:
  `bend` exits 0, `cc` exits 0, and the program dies at **run** time.

## 6. WHAT I REMOVED, AND WHY IT IS NOT THE REGISTRATIONS

**Removed: documentation that describes ten retired foreign laws as existing.**
Comment-only, **+76 / −14**, `git diff HEAD -- tinybendygrad/runtime/dtype.c
tinybendygrad/runtime/dtype.js | grep -v '^[+-]//'` is empty.

- `dtype.c:3-9` "**WHY AN EFFECT AT ALL** … cannot build an F32 from a bit pattern …
  without this seam none of them is expressible". False since `F32.from_bits`
  (`base.bend:54-56`) landed: all ten conversions are expressible, and are Bend.
- `dtype.c:29-31` "**ONE FILE, BOTH LANES** … for the interpreted lane". The lanes do
  not exist; replaced with the measured asymmetry.
- `dtype.js:1` "the interpreted-lane half of the `runtime/dtype.c` **seam**".
- `dtype.js:20-26` "Which of the two a given helper answers is `dtype.bend`'s
  declaration … `Dt.bf16(bits: U32) -> IO(F32)` and `Dt.fp8_to(..) -> IO(F32)` owe a
  value out". **None of those three declarations exists any more.**

**Kept: all ten `#ifdef` registrations, all ten `io_eff` registrations, and every line
of arithmetic.** Three reasons, each measured:

1. **They cost nothing.** 0 registered effects in all four real configurations.
2. **They are the lane's only entry point.** Removing them does not make the file
   tidier; it makes it **un-runnable**, and quietly so — `cc` still exits 0.
3. **Any deletion *inside* the file body falsifies a live citation.** `dtype.bend`
   cites `runtime/dtype.c` by `file:line` in eight places, including `:262-263` for
   the zero branch and `:44-87` for `fp8_encode` ("arm for arm"), which `LASTLAW.md`
   records as the source the pure Bend encoder was ported from. Those are in a file I
   do not own. The registrations happen to be the **last** 53 and 13 lines of their
   files, so removing *only* them renumbers nothing — which is the sole reason they
   were ever a candidate, and the plant shows it buys no measurable effect anyway.

A law becoming pure retires the foreign registrations that existed to serve it. It does
not retire the arithmetic the port cites, and it does not retire the entry point that
makes the retirement reversible. **The disposition here is: dormant, kept, and now
documented as dormant — not deleted.**

## 7. WHAT I COULD NOT REMOVE, WITH `file:line`

1. **`dtype.c`'s ten registrations** — `dtype.c:309 314 319 324 329 334 339 344 349
   354` (the `#ifdef` block is `:306-358`, the file's last 53 lines). Dead by
   measurement; kept per §6.
2. **`dtype.js`'s ten registrations** — `dtype.js:225 226 227 228 229 230 231 232 234
   236` (the file's last 12 lines). Dead by measurement; kept per §6. **And `dtype.js`
   has no `#ifdef`, so these are all-or-nothing** — the asymmetry in §4. Recorded, not
   fixed.
3. **Neither file is imported by anything.** 0 of 137+ `.bend` files import
   `runtime/dtype.{c,js}`. Retiring the *files* is coherent with `dtype.bend`'s state
   and incoherent with its eight citations into them, so it is the owner's call, and the
   numbers for it are in §6.
4. **`bf16_run` still has no `isfinite` guard** that `dtype.py:230` has — now
   `dtype.c:229-237`. And `fp8_encode`'s saturation prose still reads as if e5m2 were
   the only saturating format — `dtype.c:69-78`. Both were reported by `LASTLAW.md`
   §6.5 at `:168-176` and `:97-98`, **which my comment blocks have now moved to
   `:229-237` and `:69-78`**; LASTLAW's numbers were already stale when I received the
   file, and I have not rewritten them because that note is not mine.
   `dtype.bend:594` says the guard is not optional and that `dtype.c` lacks it, so the
   **Bend** law is the guarded one and the C lane's gap is inert while the lane is
   dormant.
4b. **Every OTHER citation into these two files has moved by +36 (`dtype.c`) and +26
   (`dtype.js`)**, for the same reason. The ones that matter:
   `dtype.bend:1093` cites `runtime/dtype.c:262-263` for the zero branch, now
   `dtype.c:300`; `dtype.bend` and `helpers.bend:2697` cite `runtime/dtype.c:205` for
   `ctr_take`, now `dtype.c:268`. **AND ONE WAS ALREADY WRONG BEFORE I STARTED:**
   `dtype.bend:932` and `LASTLAW.md` §8 both cite `runtime/dtype.c:44-87` for
   `fp8_encode`, which is `:99-145` even in the file as I received it — that citation
   predates the `fp8_ovf` threshold fix documented at `dtype.c:69-78`. **So a
   `file:line` citation into a `.c` file is not a durable identifier, and `dtype.bend`
   is not mine to edit: all of these are reported rather than fixed, and the concrete
   cost of even a comment-only edit is stated here rather than hidden.**
5. **Stage 8's red** is *correct* and is not mine to change: `jsstage.py` and `e2e.sh`
   are outside my ownership. Re-run under bounds after my edit, it is unchanged —
   20/20 rows present, **19/19** vs CPython, 0/20 reaching `dtype.js`, plant 0/20,
   `VERDICT: FAIL` on the plant line alone.
6. **`.agents/slop/substrate-check.sh` does not exist in this tree** (only under
   `.agents/slop/differverdict/root/.agents/slop/`, another unit's slop tree). So the
   import-graph and cold-file sweep was not run. It would have nothing to say here:
   my diff is two comment blocks in two files no `.bend` imports.

## 8. THE PORT IS NOT CLEAN, AND NONE OF IT IS MINE

`git diff HEAD --name-only -- tinybendygrad/` lists **35** files. **Two are mine**
(`runtime/dtype.c`, `runtime/dtype.js`); the other **33** are foreign, across
`codegen/`, `renderer/`, `schedule/`, `uop/` (including five `*.staged-blob-*` and one
`*.sweep`) and `runtime/support/`. **No foreign edit inside my two files**: before I
touched them, `jj diff --git -- tinybendygrad/runtime/dtype.c tinybendygrad/runtime/dtype.js`
printed nothing — which is the check the brief warns is needed, because `jj diff -- PATH`
prints nothing regardless. `tinybendygrad/helpers.bend` is **125668 bytes**, untouched.