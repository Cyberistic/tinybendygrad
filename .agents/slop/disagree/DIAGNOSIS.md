# THE SIX DISAGREEMENTS — what each one is, and whose fault

`runs/graphcmp/D` says `graphs-disagree=6`. This says which six, where each starts, and
why. Everything below is **re-derived from the artifacts on disk** by
`.agents/slop/disagree/names.py` and **pinned** by `checks/disagree-gate.py`
(`--help` before you trust it). Not committed. Owned: those two files, and nothing else.

Read the run with:

    python3 .agents/slop/disagree/names.py      # the six, first row, field, cause
    python3 checks/disagree-gate.py             # the same six, pinned; rc 0/1

---

## 1. THE SIX

| graph | first disagreeing row | fields | class | fault |
|---|---|---|---|---|
| `allred` | canon line **6**, `py#6 CONST` | `arg` | NOT A ROW | harness |
| `cdiv` | canon line **1**, `py#1 ALLOC` | `dtype`, `arg` | NOT A ROW | harness |
| `late` | canon line **6**, `py#6 ALLOC` | `dtype`, `shape`, `arg` | NOT A ROW | harness |
| `flip` | canon line **6**, `py#6 FLIP` (+ bend-only `GROUP#7`) | `arg` | BOTH | harness **and** port |
| `lin` | canon line **46**, `py#46 SINK` | `arg` | WRONG SHAPE | port |
| `loop` | canon line **25**, `py#25 CALL` | `dtype`, `shape`, `arg` | WRONG SHAPE | port |

**FOUR ARE THE HARNESS'S AND TWO ARE THE PORT'S.** `graphs-disagree=6` is not a count of
port defects and reading it as one is the mistake this report exists to prevent.

### THE CLASSES, AND WHY THEY ARE DIFFERENT FIXES

- **NOT A ROW** — the bend side was never asked the question. Its canonical file is
  byte-identical to a *different* graph's, so no field comparison happened at all.
- **WRONG SHAPE** — both sides built the same node, and the disagreeing chunk **cannot
  agree at any value**: the port emits a marker (`q`), a different number of fields
  (`CallInfo`'s 4th), or `?`. This is `field-mismatches=0` with the values unreadable,
  and it is invisible to a reader who trusts the count.
- **WRONG VALUE** — one field's value differs and both sides could express it.
  **No disagreement in this corpus is in this class.** `spine` reported
  `field-mismatches=0` on `lin` and `loop` and called the values wrong; they are the
  *shape*, which is a different bug with a different fix.

---

## 2. THE CHEAP HYPOTHESIS, TESTED FIRST: **FALSIFIED**

The brief's hypothesis was that the **canonical serialisation** differs, which would let
the port be correct and the comparison still disagree.

**It does not.** The wire is `N:i<id>` then **seven length-prefixed chunks** — the op
name plus the six the `DENOMINATOR` line counts as `fields=6` — and `names.py` parses
**every row of both sides of all 25 graphs** and requires each to consume itself
exactly. **0 malformed rows.** A missing field, a reordered field or a bad prefix all
fail that parse; a differing *value* never does. The serialisation is not the cause.

**AND THE NAIVE VERSION OF THAT TEST IS WRONG**, which is why it is worth recording.
My first wire test counted spaces and reported `py/binblob:19: 9 tokens, not 8`. Line
19 is `3:i19 6:BINARY 2:u8 6:(l0:4) 2:i0 1:N 24:y n(i116,i105,i110,i121) 6:n(i18)` — the
bytes arg spells `y ` + a list, so it carries a space **by design**. That is the whole
reason the wire is length-prefixed, and it is `graphcmp-LIMITS.md` §1.5's defect
(`unchunks` required the space, so whitespace was structural). **Counting separators on
a length-prefixed wire measures the prefix, not the payload.**

---

## 3. `allred`, `cdiv`, `late` — **THE PORT WAS NEVER ASKED**

`sha256` of the three bend canonical files is **one digest**, and it is
`D2-canon-bend-matmul.txt`:

    D2-canon-bend-allred.txt  =  9f39a6e3ee7a0e30…
    D2-canon-bend-cdiv.txt    =  9f39a6e3ee7a0e30…
    D2-canon-bend-late.txt    =  9f39a6e3ee7a0e30…
    D2-canon-bend-matmul.txt  =  9f39a6e3ee7a0e30…

**CAUSE, at `.agents/slop/graphcmp.bend:1312`** — `rows.pick3` has **no arm** for any of
the three, and its default arm is `g_matmul()`. `Bool.pick` chooses an arm, so asking
for `allred` falls off the end and hands back the matmul. The py side runs
`g_allred`/`g_cdiv`/`g_late` (`graphcmp.py:1393`/`:1412`/`:1457`) and gets the right
graph; the bend side is asked for a graph it does not have and answers with a different
one. **18 valid rows, no error, no warning.**

**THIS IS THE STANDING TRAP, ONE LEVEL UP.** `graphcmp-LIMITS.md` §6.22 records that
"a 0-row result is indistinguishable from not started". Here it is worse: **an 18-row
result is indistinguishable from a correct one.** `not-comparable=0` went to zero and
the run reports itself healthy.

**NOT A PORT DEFECT AND NOT A STALE `WANT`.** It is a missing fixture, and the `DISAGREE`
verdict is *true* — the two files really do differ — but **vacuous**: it says the matmul
differs from `allred`, which is not a fact about the port.

**THE FINDING NOBODY WAS LOOKING FOR — IT IS NOT ONLY THESE THREE GRAPHS.** Eight ops
are reached by the py side and by **nothing else in the corpus**, and **every one of them
is reached only by a substituted graph**:

    ALLREDUCE COPY   (allred)     CDIV CMOD   (cdiv)     CMPEQ FDIV NEG SUB   (late)

So `commit b104786b3`'s headline *"53 OF 77 OPS, **BOTH SIDES**, ZERO ASYMMETRY"* is
true only because the bend side was handed a matmul three times and never had to reach
them. **The bend side reaches ZERO of these eight.** Two claims inherit the artefact:

1. **`graphcmp-LIMITS.md` §5's "the corpus now reaches EIGHT of eight commutative ops,
   and `CMPEQ` is reached — by the `late` graph"** is a **py-side** fact. `CMPEQ` is the
   eighth commutative op and `late` is substituted, so the **bend side reaches 7 of 8**.
2. **`commutative-ops=8` on every `DENOMINATOR` line is a CONSTANT, not a measurement.**
   Measured: `commutative-ops=` reads `8` on **all 25** reports including `sink`'s
   2-node one. It is the size of `GroupOp.Commutative`. So the "eight of eight" claim
   has **no denominator on any report**, and `CMPEQ` appears in **no** `D6-*.txt` — the
   `--equiv` lane measures the other seven (`graphcmp-LIMITS.md` §5 says so itself).

**AND EVERY ONE OF THOSE EIGHT REPORTS PRINTS `ops-reached=n/n` AND LOOKS SYMMETRICAL**,
because the numerator and the denominator are the *same graph* while the two sides built
*different* graphs. `D1-graph-late.txt` reads `ops-reached=9/9`.

---

## 4. `flip` — **TWO CAUSES, AND ONLY ONE OF THEM WAS PREDICTED**

**(a) bend-only `GROUP#7` — a FIXTURE bug, and the one that moved the verdict.**
`graphcmp.py:1385` is `return UOp.group(a.flip(0).uop)` — a **ONE-element** group — and
`tinygrad/uop/ops.py:559` is `if len(srcs) == 1 and isinstance(srcs[0], UOp): return
srcs[0]`. **CPython therefore builds no GROUP at all** (py has 6 rows, root = FLIP).
`graphcmp.bend:1304` hand-builds one anyway, bypassing `UOp.group` — which at
`tinybendygrad/uop/ops.bend:2507-2513` **implements the collapse correctly**
(`case Nil{}: Found{nar, 0}` / `case s <> t: case Nil{}: Found{ar, s}`). The port is
right; the fixture does not use it. **One line, and it is in a SETTLED file.**

**(b) `arg` `n(b1,b0)` vs `n(i1,i0)` — a real PORT gap, correctly predicted.**
Upstream's FLIP arg is `tuple[bool, ...]` (`ops.py:428` asserts every element is a
bool); the port has ONE spelling for PERMUTE and FLIP, `ATuple{ys: List<&2, U32>}`
(`ops.bend:1081`), which is the *int* one. A bool has no representation.

**A STALE CLAIM, WORTH CORRECTING WHILE I AM HERE.** `graphcmp-LIMITS.md` §4 says `flip`
"differs in its canonical rows yet still **AGREEs**, because `canon_flip` normalises the
bool/u32 spelling difference that made its md5 move." **There is no `canon_flip` on this
tree** (`grep` finds none) and `flip` **DISAGREEs**. The cause of the move is (a), the
extra node — not (b), which was always there. **That sentence is wrong and should be
deleted rather than re-measured.**

---

## 5. `lin` — WRONG SHAPE, PORT, AND THE COUNT IS RIGHT

Row **46**, `arg`, and nothing else:

    py   … 66:kI(sr_4_5_3,n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))),N,i0) 6:n(i45)
    bend … 22:kI(sr_4_5_3,n(q),N,i0)                                              6:n(i45)

`ops.bend:919` types `applied_opts: List<&2, U32>`; upstream's elements are `Opt`
dataclasses. So the port emits the ledger **marker** `q`, one per option — the **COUNT
agrees (1 = 1)** and the payload has no spelling. **Wrong shape, not a wrong value**, and
exactly what `WANT` predicts, so **not a stale expectation.**

---

## 6. `loop` — WRONG SHAPE, PORT, **AND A STALE CITATION**

Row **25**, three fields at once:

    py   3:i25 4:CALL 4:void 1:R 2:i0 1:N 20:cI(shcq_fence,b0,b0)         18:n(…)
    bend 3:i25 4:CALL 1:?    1:?  2:i0 1:N 26:cI(shcq_fence,b0,b0,Dvoid) 18:n(…)

The port's `CallInfo` (`ops.bend:1010`) has **four** fields:
`{name, precompile, precompile_backward, dtype: S.Dt}`. Upstream's (`ops.py:1400-1405`)
has **five** and **none of them is `dtype`**: `grad_fxn, name, precompile,
precompile_backward, aux`. The port dropped `grad_fxn` and `aux` (documented and
deliberate, `ops.bend:999`) and **invented `dtype`**.

**The citation that invented it is stale, and that is the finding.** `ops.bend:1007`
says *"`dtype: DType = dtypes.void` … IS read: by `dtype_from_uop`'s CALL arm"*, and
`ops.bend:984` says *"upstream MOVED `CallInfo.dtype` here to make it so"*. Measured:

- `tinygrad/uop/ops.py:130-132` is `case Ops.CALL:` / *"a call has the dtype of its body,
  void for opaque bodies"* / **`return src[0].dtype`** — it reads the **BODY**. It never
  reads `CallInfo`.
- `git log -S'dtype: DType = dtypes.void' -- tinygrad/uop/ops.py` returns exactly one
  commit, `6f4bfde23` *"restrict allowed call bodies (#17925)"*, 2026-09-02 — and that
  commit **ADDS** the field. It is **absent at HEAD**. **The port is pinned to a commit
  upstream has since moved past.**
- `fold.bend:1144` is `case O.ACall{ci}: O.CallInfo.dtype(ci)` — the port reading the
  field upstream does not have.

So the `?` is not a wrong value; it is **the fold producing no `Derived` at all**, and it
is the corpus's **only** live `?`. Fixing it deletes a field from a data type, drops the
4th argument from `CallInfo.of` (`:1091`) and `sg.ci` (`:6931`), and repoints
`fold.bend:1144` at the body.

---

## 7. IS ANY OF IT A STALE `WANT`? **NO — AND THAT IS THE ANSWER**

Every one of the six is either UNSET or correctly pinned `DISAGREE`:

- `allred` `cdiv` `late` `flip` — `EXPECTED=UNSET`. `D1-verdicts.txt` already says
  *"RUN AND RECORDED, NOT COMPARED … the run cannot say whether that verdict is right"*
  and line 10 says **`RUN INCOMPLETE -- 9 HAVE NO EXPECTATION`**. The differ is honest.
- `lin` `loop` — `differ.py:121-133` pins them `DISAGREE` **on purpose, with the cause in
  a comment**, and they do.

**So `graphs-disagree=6` is a count of UNSET-plus-pinned, not a count of port defects.**
The differ counts a graph it explicitly labels NOT COMPARED as a disagreement in the same
`graphs-disagree=6` as two real port gaps, and that conflation is the reporting defect.
`D1-graph-*.txt` is honest per-graph; `D0-run-summary.txt` is not.

**One stale claim found, and it is not in `WANT`:** `graphcmp-LIMITS.md` §4's `flip`
"still AGREEs … because `canon_flip` normalises" (§4 above), plus §5's "eight of eight
commutative ops" read on the bend side (§3 above).

---

## 8. THE FIX PER GRAPH — **AND WHY NONE OF THEM CAN LAND HERE**

Every real fix either **is** the frozen fixture, or **changes a port type whose renderer
is** the frozen fixture. Measured, not guessed:

| # | graph | the fix | lands in | blocked by |
|---|---|---|---|---|
| 1 | `allred` `cdiv` `late` | add `g_allred`/`g_cdiv`/`g_late` arms to `rows.pick3` | `graphcmp.bend:1312` | **SETTLED — owner's** |
| 2 | `flip` (a) | **delete `graphcmp.bend:1304`**, the hand-built GROUP | `graphcmp.bend` | **SETTLED — owner's.** One line. |
| 3 | `flip` (b) | split `ATuple` into PERMUTE-int and FLIP-bool (`ops.bend:1081`) | `tinybendygrad/` | needs a new `graphcmp.bend` bool-tuple arm |
| 4 | `lin` | model `Opt` for `applied_opts` (`ops.bend:919`) | `tinybendygrad/` | `graphcmp.bend:327` emits `q` from it, so the marker's meaning changes |
| 5 | `loop` | delete `CallInfo.dtype` (`ops.bend:1010`), repoint `fold.bend:1144`, drop the 4th field at `:1091` and `:6931` | `tinybendygrad/` | `graphcmp.bend:301` renders `cI(name,pre,preb,dt(cdtype))` **from that exact field** |

**#5 IS THE SHARPEST**: the correct fix for the port's only live `?` **breaks a frozen
file** until its owner re-renders one line. So `loop` is not independently fixable while
`graphcmp.bend` is frozen — that coupling is worth stating explicitly, because "fix the
port" is otherwise a one-line job.

**PLANT AND DISARM, for each fix — MEASURED, in `checks/disagree-gate.py`.** The plant
lane copies the tree to a temp directory (**never writes `runs/graphcmp/D`**) and runs two
plants, one per belt, because a belt that reads nothing and a belt that reads the other
belt both pass a self-consistent check:

- **PLANT A** — make the bend canon agree with the py canon on `lin`'s last row.
  **BELT 2 MUST MOVE** (46 → nothing; it recomputes with `difflib` over the canonical
  files). **BELT 1 MUST NOT MOVE** (it parses the differ's own `diff` record, which this
  plant does not touch). The two halves moving in **opposite** directions is the proof
  they read different bytes.
- **DISARM A** — restore the byte; the pinned answer must return **exactly**.
- **PLANT B** — rewrite `D2-cmp-lin.txt`; **BELT 1 MUST MOVE** and **BELT 2 MUST NOT**.
  If both move, they share a source and this is one check wearing two hats.

**ALL FOUR LANES HAVE BEEN MEASURED TO FAIL**, which is the only thing that makes a green
gate mean anything:

| lane | the negative I actually ran | result |
|---|---|---|
| `PIN` | `graphs-disagree=6` → `7` in a **copy** of the run | FAIL rc=1 |
| `CITATIONS` | `dtype: S.Dt` → `dtype: S.DtX` in `ops.bend` | FAIL rc=1 |
| `CITATIONS` | `OpsGROUP` → `OpsSINK` in `graphcmp.bend:1304` | FAIL rc=1 |
| `COVERAGE` | drop `CMPEQ` from the pin | FAIL rc=1 |
| `PLANT` | assertions inverted — see §2, they fired | FAIL rc=1 |

**THE `CITATIONS` LANE HAD A REAL BUG AND THE NEGATIVE CAUGHT IT.** Plain
`needle in line` let `dtype: S.DtX` **pass** for the pin `dtype: S.Dt` — a superset
resolved the citation, so nothing moved and the sentence the citation backs went stale.
That is `checks/abi4_gate.py`'s trap in miniature. Fixed with a `(?![\w])` boundary
(`cited()`), and **the fix is why the table above has two `CITATIONS` rows.**

---

## 9. WHAT I COULD NOT SETTLE

1. **I did not re-run the differ.** Not mine to run (a unit is auditing what a run may
   write), and a half-written `runs/graphcmp/D` is worse than a stale one. Every number
   above is read back out of it, and **it is left exactly as I found it** — verified:
   `git status --porcelain runs/graphcmp` is empty and the newest mtime is still
   `Oct 6 00:31`.
2. **Whether `flip`'s GROUP was added on purpose.** `git log -S` puts `g_flip` **and** its
   GROUP line in the same commit `b104786b3` (*"reach: 53 OF 77 OPS"*). If it was a
   deliberate coverage choice it is wrong for the measured reason in §4(a) — a fixture
   that adds a node upstream does not build cannot raise coverage honestly — but I cannot
   tell intent from a commit message.
3. **`oracle-selfcheck=# ORACLE SELFCHECK: FAIL` and `census-rc=rc=1`** in
   `D0-run-summary.txt`. Unchanged by anything here; `spine` §5.1 already declined it.
4. **`checks/corpus-figure.py` cannot print `OK` while it demands `agree == total`** and
   two graphs must disagree (`spine` §4). Not mine, and unchanged.
5. **How much of the coverage figure the three substitutions inflate.** I measured that
   the **eight ops are** artefacts. I did **not** re-run `checks/hermetic-census.py` to
   get the corpus's total down to a bend-only count, and I did not touch either census —
   both are another unit's and both need a run I am not allowed to make.
6. **`UOp.group`'s zero-src case.** `ops.py:560` and `ops.bend:2509` both make a GROUP for
   zero srcs and I read them, but no corpus graph has one, so it stays untested.
