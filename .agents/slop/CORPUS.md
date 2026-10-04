# CORPUS — the ONE figure, and the instrument that produces it

**Regenerate with `checks/corpus-figure.py`.** Nothing else in this tree may state a corpus
coverage figure without pointing here.

<!-- CORPUS.md FIGURE BLOCK — regenerate with checks/corpus-figure.py -->
- **53 of 77 ops** reached, by set UNION over **22 graphs** (22 built, 0 failed)
- the per-graph SUM is **157** and is **not** this figure
- not reached: REWRITE_ERROR PROGRAM SOURCE GETADDR WMMA NEG CDIV CMOD CMPEQ THREEFRY SUB FDIV MULACC CUSTOM CUSTOMI INS STAGE COPY MSELECT MSTACK CUSTOM_FUNCTION UNSHARD ALLREDUCE PYLITERAL

## WHY THIS FILE HAS TO EXIST: THE FIGURE EXISTED IN NINE FORMS AT ONCE

Measured across `.agents/slop/*.md`, `.agents/TODO.md`, `AGENTS.md` and `checks/*.md`:
`13`, `34`, `35`, `43`, `54`, `59`, `60`, `61`, `73` and `77 of 77`. And `22 graphs [SUPERSEDED: was 25; see CORPUS.md]` against a
measured `22`.

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
