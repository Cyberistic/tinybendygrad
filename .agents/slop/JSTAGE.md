# JSTAGE — `e2e.sh` stage 8, and the only stage that ever ran the JS lane

Rule prefix for this unit: **`JS8-`**. Files: `.agents/slop/jstage/`.
Nothing committed. `runtime/dtype.js`, `runtime/dtype.c`, `dtype.bend`,
`helpers.bend`, `base.bend` and every `.bend` in the tree are **byte-unchanged**;
every mutation ran on a `$TMPDIR` copy and no plant was ever written into the live
tree.

```
.venv/bin/python .agents/slop/jstage/jsstage.py          # the stage. rc 0 / 1 / 3
.venv/bin/python .agents/slop/jstage/jsstage.py --tree D # read another substrate
```

## 1. THE CLAIM, IN ONE SENTENCE, WITH ITS DENOMINATOR

> `node` runs `tinybendygrad/runtime/dtype.js` through `bend -o`, exits 0, prints
> all **20** rows the gate asks for, and agrees with CPython on the **19** of them
> CPython can answer.

Measured on the live tree, 2026-10-05: **19/19, node rc 0, 20/20 rows present.**

**AND 12 OF THOSE 20 REACH `dtype.js`. THE OTHER 8 DO NOT.** `dtype.bend` had been
rewritten so `Dt.bf16`, `Dt.fp16` and `Dt.fp8_to` are **pure defs**, so the three
CIDs `dtype.js` registers for them are **DEAD — registered and never called** — and
those eight rows measure `dtype.bend`'s arithmetic. The gate derives the split from
the substrate's declarations on every run and prints it, so a tree that moves back
is counted correctly without an edit here.

**`JS8-1` — a stage's denominator is not its row count.** `rows asked for 20` and
`rows that REACH dtype.js 12` are both true and only the second is the claim. The
first number is the fixture; the second is the lane. A stage that prints one of them
is quoting the wrong one.

## 2. WHAT THE STAGE'S HEADER STATES AS ITS LIMIT, AND A MISATTRIBUTION CORRECTED

The brief this unit was handed put the census "**320 executed, 256 with at least
one NULL argument, 175 answering a refusal sentinel**" into the mouth of the JS
lane. **Those numbers are not the JS lane's.** They are `.agents/slop/CLANGFILL.md`
§2, and they are `clangfill/gate.py`, which drives **`cc` against `libclang`**.
`clangshim/apply-port-lane.py:130` records that the libclang lane **cannot be
emitted to JS at all** — `bend -o out.js` answers `a foreign def without a .js
import: Loaded_dylib`. So there is no JS lane with 320 rows to have run with NULL
arguments.

**`JS8-2` — "executed is not bound" is a real caution with a real census, and
attaching it to the wrong lane does not make it stronger, it makes it checkable.**
The stage borrows the SHAPE of the caution and states its own limit in the terms it
can measure: every argument in it is a bend literal, so **there is no NULL-argument
class to count here**, and the one row CPython refuses on is counted `diverge`.

## 3. THE THREE OUTCOMES, ALL THREE RUN

| substrate | rc | what e2e.sh prints |
|---|---|---|
| live tree | **0** | `stage 8 js lane …: PASS` |
| ABI-2 planted as shipped | **1** | `stage 8 js lane …: FAIL (rc=1)`, script exits 1 |
| 0-byte `helpers.bend` planted | **3** | `stage 8 js lane …: SKIP -- jsstage.py REFUSED (rc 3)`, script exits 0, `PASS WITH 1 SKIP(S)` |
| `--tree` at a directory with no `tinybendygrad` | **3** | same SKIP |

**The refusal is real, not hypothetical.** With a **0-byte `helpers.bend`** planted
in a `$TMPDIR` copy, `bend -o` answers `expected : a defined name / observed :
H.I64` at `i64_max_u`, no JS is emitted, node never runs, and the gate exits 3
having measured nothing. That is exactly the `run-f64.sh` exit-3 case, and it is
mapped to `SKIP` — **not** to `PASS`.

**`JS8-3` — a missing substrate is a REFUSAL and a reverted seam is a FAILURE, and
the two must not share an exit code.** A `--tree` pointing at a directory without a
`tinybendygrad` under it *crashed* on `copytree`, and a crash read as `FAIL`, which
is a claim that the lane is wrong and is not what happened — now `rc 3`. But a
`runtime/dtype.js` whose `i64_of` no longer reads `p.hi`/`p.lo` is **the ABI-2 bug
shipping again**, and reporting that as `SKIP` would launder a live defect into
"this stage could not run". That is `rc 1`.

## 4. THE PLANT AND THE DISARM, AND WHY THE FAIL IS NOT A ROW-SET ARTEFACT

```
PLANT  `p.hi`/`p.lo` -> `p.fst`/`p.snd` (ABI-2 as shipped)   moved  8/20
DISARM `<<32n |` -> `* 2**32n +`, BigInt, same function      moved  0/20   0 is the only correct count
PLANT  the same in NUMBER arithmetic (NOT a disarm)          moved  5/20
```

**`node` EXITS 0 ON THE PLANTED BUG.** MEASURED: with `p.fst`/`p.snd` in place the
report reads `node exit status 0`, `ROWS PRESENT == ROWS EXPECTED yes (20/20)`,
`node agrees with CPython on 11/19`. **A full row set over a lane that is wrong on
8 rows is not a partial success** — which is why the row set and the CPython
comparison are separate obligations from node's status, and why this stage fails on
the third.

The disarm is run **and** a second plant is run, because JSL2-5 records
`h * 2**32 + l` in **Number** arithmetic being mistaken for a disarm and moving 15 of
30 rows. Here it moves 5 of 20. **A disarm is only a disarm after it has moved 0 in
fact.**

**The plant's 12 unmoved rows are attributed, and each class is a theorem:**

- **8** never reach `dtype.js` (pure `dtype.bend`) — §1.
- **1** reaches `dtype.js` by a seam the plant does not touch (`fp8from_1p5` goes
  through `fp8_encode`; `i64_of` is one function of seven registered CIDs).
- **3** go through `i64_of` but already answer `0:0` — `floormod_neg`, `cdiv_by0`,
  `ceildiv_by0` — and a planted seam that answers `0` cannot move a row that is
  already `0`.

## 5. THE DENOMINATOR IS NOT NODE'S EXIT STATUS — THE LESSON, PAID TWICE

`abi4_gate.py` once passed **98/98** and `abi_gate.py` once reported *"node agrees
with CPython on 12/12"* while `node` had exited **1 with empty stdout**, because
`vs()` excludes absent rows from `bad`. **A dead lane counted as a lane never
wrong.** So this stage:

- **reads node's rc**, and
- makes an **absent row a FAILURE**, reported on its own line as
  `ROWS PRESENT == ROWS EXPECTED`, never folded into the agreement count.

**`JS8-4` — `present == expected` is an obligation with its own line.** Folded into
the agreement count it becomes `19/19 - absent`, which reads as a smaller success
rather than as a hole.

## 6. E2E.SH STAGE 8 IS ADDITIVE, AND THAT WAS VERIFIED NOT ASSUMED

```
stages 1-7 byte-identical : True   (12449 bytes, sha256 e3a0edf00bee66a1…)
exit block byte-identical : True
delta bytes               : +6879, 0 removed
```

The temp-and-move discipline from `graphcmp-run.sh:38-56` is kept: one temp, one
write, one atomic `mv` inside `$RUN`, `rm -f` of dot-temps first, and the gate's
own status appended **to the temp** before the move — never to the file the child
just wrote.

**`JS8-5` — the gate's status is read from the report's last line, not from a
pipe.** Stage 8 does `grep`/`sed` for display and reads the status with
`sed -n 's/^rc=\([0-9]*\)$/\1/p' | tail -1`, for the reason stage 4 does not pipe
its gate into `tee`: **POSIX sh has no `PIPESTATUS`**, so `$?` after a pipe is the
last command's status and a gate that CRASHED would print PASS. The stamp count is
also checked (`rc= stamps == 1`): a report with no stamp means the run was killed
and is `SKIP`, not a verdict.

## 7. TWO FIXTURE BUGS OF MY OWN, BOTH FOUND BY A NUMBER

1. **A hand-typed `-8`.** I wrote `i64_of_hi_lo(0, 4294967288)` for `-8`. That is
   **`+4294967288`**: `BigInt.asIntN(64, x)` leaves a 32-bit value alone, because
   **the sign lives in the HIGH word**. Four rows went red. **Both lanes were right
   and the fixture was wrong** — found by running the *same* rows through `cc` and
   getting byte-identical output, which is the only thing that distinguishes a lane
   bug from an expectation bug. `hi_lo()` now generates the words.
2. **`F32.show` prints SEVEN significant digits** — `1.0996094` where CPython
   prints `1.099609375`. Comparing as floats still misses. Both sides now round
   through `f32()`. **`jslane2/gen_f32_seam.py`'s own `norm` is `repr(float(s))` with
   no round-trip and would call `fp16(1.1)` a lane disagreement for that reason**;
   `fp16_1p1` is in this row set so the defect cannot hide here.

**`JS8-6` — a FIXTURE literal is a TYPED CONSTANT, and agent-core.md's table already
has five units that shipped one.** Generate the words, call CPython for the answer.

Also measured while writing this: `-2.25` is not a literal this grammar takes
(`expected : a term, observed : '-'`), a bare `-` operator is a `Nat` one unless
annotated, a bend value is **linear** (`bf16_m1p5 (consumed more than once)`), and
`IO.pure`'s FIRST argument is the value type — `IO.pure(F32, e)`, not
`IO.pure(Unit, e)`.

## 8. `dtype.bend` IS MOVING UNDER THIS STAGE, AND THE FIXTURE FOLLOWS IT

`Dt.bf16`, `Dt.fp16` and `Dt.fp8_to` were `-> IO(_)` laws and are now pure defs, so
a row that binds with `<-` in a `do IO<Unit>` block stops type-checking for them.
The emitter **reads the declaration** (`SEAM_DECL`) and lifts a pure one with
`IO.pure`, so the gate is correct on either side of that change. **A hard-coded
seam shape is a stage that refuses on whichever side of a refactor the tree happens
to be on**, and a refusal is a stage that measures nothing.

**`JS8-7` — which of the two a helper answers is the DECLARATION's business, not the
caller's guess.** `agent-core.md` says so for the lane; it is equally true of the
harness that drives it.

## 9. NOT MINE

`abi_gate.py`, `abi4_gate.py`, `jsfix_gate.py`, `gen_js_seam.py` and
`gen_f32_seam.py` are other units' and are untouched. This stage **re-derives
nothing** from them; it builds its own rows from `tinygrad` called.
`.agents/slop/CLANGFILL.md` §2 is the census cited in §2 above and is not a JS
census — see that correction.
