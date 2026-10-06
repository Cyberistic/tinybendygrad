# CORPUS — the ONE figure, and the instrument that produces it

**Regenerate with `checks/corpus-figure.py`.** Nothing else in this tree may state a corpus
coverage figure without pointing here.

<!-- CORPUS.md FIGURE BLOCK — regenerate with checks/corpus-figure.py; REQUIRES `DEV=CPU` -->
- **61 of 77 ops** reached, by set UNION over **25 graphs** (25 built, 0 failed), **`DEV=CPU`**
- the per-graph SUM is **181** and is **not** this figure
- not reached: REWRITE_ERROR PROGRAM SOURCE GETADDR WMMA THREEFRY MULACC CUSTOM CUSTOMI INS STAGE MSELECT MSTACK CUSTOM_FUNCTION UNSHARD PYLITERAL

### THE NUMBER ABOVE IS WRONG BY ONE OP IF YOU RUN THE INSTRUMENT WITHOUT `DEV=CPU`

`checks/corpus-figure.py` **NEVER PINS `DEV`** (it calls `load_graphcmp()` at `:51`, which resolves
the device from the environment). MEASURED 2026-10-05, same tree, same command, same instrument:

| invocation | union | the difference |
|---|---|---|
| `DEV=CPU .venv/bin/python checks/corpus-figure.py` | **61 of 77** | `FDIV` reached |
| `.venv/bin/python checks/corpus-figure.py` (this host → `METAL`) | **60 of 77** | **`FDIV` MISSING** |

`g_late`'s `a / b` becomes `FDIV` only when the device's OWN renderer table lists it —
`ClangRenderer` does (`tinygrad/codegen/decomp/op.py:123 if Ops.FDIV in ops`), `MetalRenderer` and
`NullRenderer` do not, and `a / b` then stays `MUL(a, RECIPROCAL(b))`. **A COVERAGE FIGURE WHOSE
VALUE IS DECIDED BY AN ENVIRONMENT VARIABLE NOBODY SET IS NOT A COVERAGE FIGURE; IT IS A
MEASUREMENT OF THE HOST.** The fix is one line in the instrument (pin `DEV` before
`load_graphcmp()`), which is not this file's to make.

### AND NEITHER 61 NOR 60 IS A STATEMENT ABOUT THE PORT

**THE PORT-SIDE UNION OVER ALL 25 GRAPHS IS `0 of 77`.** `.agents/slop/graphcmp.bend:373`
`argstr` has 19 of the 20 `Arg` arms and is missing `AOpLit`
(`tinybendygrad/uop/ops.bend:1079`), so the port's differ emitter **does not compile**
(`bend: expected : cases for …AOpLit / observed : \{\}`) and every one of the 25 emits **0 rows**.
`not-comparable=16` is therefore **not a disagreement — there was nothing to disagree with**, and
`D0-run-summary.txt`'s `graphs=16` is `len(WANT)`, a hand-written 16-name table at
`checks/differ.py:89-103` that the run loop at `checks/differ.py:250` iterates **instead of**
`graphcmp.GRAPHS`. Measurement: `.agents/slop/graphrestore/RESTORE.md`.

## WHY THIS FILE HAS TO EXIST: THE FIGURE EXISTED IN NINE FORMS AT ONCE

Measured across `.agents/slop/*.md`, `.agents/TODO.md`, `AGENTS.md` and `checks/*.md`:
`13`, `34`, `35`, `43`, `54`, `59`, `60`, `61`, `73` and `77 of 77`. And `22 graphs` against a
measured `25`.

> **THE `22` WAS NOT A SUPERSEDED `25`. IT WAS A `25` THAT WAS LOST, AND THE TWO ARE ONLY BEING
> TOLD APART NOW.** `allred`, `cdiv` and `late` were in `graphcmp.GRAPHS` in commit `db95da7bf`
> (2026-10-04) and in **no commit that is an ancestor of HEAD**, so the corpus lost them and the
> union fell **61 → 53** — exactly the eight ops those three graphs carry. They are restored
> (`graphcmp.py:1388`, 25 entries) and the measurement is `.agents/slop/graphrestore/RESTORE.md`.
> **A NUMBER THAT WAS TRUE WHEN WRITTEN IS NOT THEREBY STILL TRUE; NEITHER IS ONE THAT WAS TRUE
> ONCE AND THEN STOPPED BEING MEASURED AT ALL.**

**THREE OF THEM WERE ARITHMETICALLY IMPOSSIBLE AS A COVERAGE CLAIM:**

| figure | occurrences | what it is |
|---|---|---|
| **`588 of 77`** | 1 | **a per-graph SUM compared against a set** |
| **`372 of 77`** | 1 | **ditto** |
| **`0 of 77`** | 1 | **a union over ZERO graphs that built, beside a healthy denominator** |

> **A FIGURE LARGER THAN ITS DENOMINATOR IS A PER-GRAPH SUM COMPARED AGAINST A SET. SUMMING
> `ops-reached` ACROSS GRAPHS COUNTS `BUFFER` ONCE PER GRAPH THAT HAS ONE. MEASURED HERE: THE SUM IS
> 157 AGAINST A UNION OF 53 — A FACTOR OF ~3, WHICH IS EXACTLY HOW MANY GRAPHS CARRY A COMMON OP.**

**AND `0 of 77` HAS ITS OWN NAMED CAUSE, WRITTEN IN A UNIT'S OWN SOURCE:** `graphcmp.py` defers every
tinygrad import into `load_tinygrad()`, so **importing the module is not enough** — without that
call every graph raises `NameError` and the union prints `0 of 77` beside a denominator that looks
perfectly healthy. **A HOLLOW FIGURE BESIDE A HEALTHY DENOMINATOR IS THE MOST DANGEROUS SHAPE A
MEASUREMENT CAN TAKE, BECAUSE IT READS AS A RESULT.**

## THE RULES THIS ESTABLISHES

1. **A COVERAGE FIGURE IS A SET UNION OR IT IS NOT A COVERAGE FIGURE.** Per-graph counts may be
   summed only when the question is "how many op-instances does the corpus exercise", which is a
   different question with a different answer.
2. **A FIGURE NINE DOCUMENTS DISAGREE ABOUT IS NOT DOCUMENTATION.** This file is the only authority;
   the others point here.
3. **A FIGURE NOBODY CAN REPRODUCE IS NOT A MEASUREMENT** — hence the instrument, and hence its
   non-zero exit when a graph fails to build.
4. **THE DENOMINATOR IS READ LIVE** (`len(Ops)` off the running `tinygrad.uop.ops`), so a new
   upstream op cannot age the answer silently. **That is exactly how the 34/35 pair happened: the
   denominator moved and the numerator was not re-measured.**
5. **THE WALLRULE UNIT'S CLOSING LINE IS THE BEST ARGUMENT FOR ALL OF THIS:**
   *"the note that corrected the wall was itself stale."* **A CORRECTION IS ALSO A MEASUREMENT, AND
   MEASUREMENTS AGE — WHICH IS WHY THE FIX IS AN INSTRUMENT AND NOT A NUMBER.**

## WHAT IS STILL TRUE ABOUT COVERAGE, AND IS NOT A COVERAGE FIGURE

**`77 of 77` IS ALSO IN THE TREE AND IS **NOT** A COVERAGE CLAIM** — it is `emittable`/`reachable`
in the *unport* sense: the summary line reads *"77 of 77 reachable as a `UOp` graph; 73 of 77
emittable"*. **THOSE ARE DIFFERENT MEASUREMENTS WITH DIFFERENT INSTRUMENTS, AND WRITING THEM AS
`of 77` PUTS THEM IN THE SAME COLUMN AS THE COVERAGE FIGURE, WHERE THEY HAVE BEEN COUNTED AS
CONTRADICTIONS TO IT.** *** TWO NUMBERS WITH THE SAME DENOMINATOR AND DIFFERENT INSTRUMENTS ARE NOT
IN DISAGREEMENT; THEY ARE ANSWERING DIFFERENT QUESTIONS. ***
