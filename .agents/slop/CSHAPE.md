# CSHAPE — widening `cshape`'s `except` arm, one exception at a time

Unit `CSHAPE`, 2026-10-04/05. **No file outside `.agents/slop/cshape/` was edited.**
`graphcmp.py` and `graphcmp.bend` are another unit's and were not touched; `cshape` is
inside `graphcmp.py`, so every widening below is applied **in-process by monkeypatch** and
nothing on disk carries it.

**Substrate pin.** `graphcmp.py` md5 `4a0d2467b7e70d701afac68091394f40`,
`graphcmp.bend` `184f7edd80404c8b7aedb33beb28bcd8`, `uop/fold.bend`
`e372ca226461fe2295b49a9990db0165`. **`graphcmp.py`'s md5 MOVED under this unit**, from
`026c1cd8c25e395c6ca8ded9b8b81374` at first read to the pin above, and one `selfcheck` run
died with `NameError: name 'dev' is not defined` at `graphcmp.py:734` before that unit's
`ADev` edit landed (`paramarg` now spells `_carg(pa.device)`). That is another agent
mid-edit, so every number below was re-measured at the pin and the census was re-run
twice with a byte comparison. **A note that cites a line number into a file that is being
rewritten is a note that will be wrong by the time it is read** — `DENOMINATOR.md` §3 cites
`ops.py:442` for the assert and the assert is at **`ops.py:444`**.

Files: `cs-arms.py` (per-arm yield and per-arm admitted set), `cs-rows.py` (py rows per
widening), `cs-opshape.py` (what each exception means over all 77 ops),
`cs-androot.py` (the AND-root rule), `cs-patir.bend` / `cs-plantir.bend` (the port side,
built with the port's own constructors, rendered by the **differ's own** renderer via
`import ./../graphcmp.bend as GC`), `cs-plant.py` (plant and disarm, ledger, corpus).
Transcripts: `arms-run0.txt`, `rows-run0.txt`, `opshape-run0.txt`, `androot-run0.txt`,
`patir-bend.txt`, `plantir-bend.txt`, `plant-run0.txt`.

---

## 1. WHICH WIDENING BOUGHT WHICH OP, AND WHAT EACH COST

Over the **25 live corpus graphs plus the pattern IR** — 316 nodes — the entire outcome
census (`cs-arms.py`, `arms-run0.txt` §2) is:

```
290x  ok
 25x  RuntimeError      tinygrad/uop/ops.py:455   shape requested, but Ops.X doesn't have a shape
  1x  AssertionError    tinygrad/uop/ops.py:444   None input shape not supported for Ops.AND
```

**That is all.** One new exception class, one new raising site, one node.

| arm | nodes rendered | graphs fully rendered | NEW ops | what it admits |
|---|---|---|---|---|
| **W0** `except RuntimeError` (LIVE) | 315/316 | 25/26 | — | ops.py:455 only |
| **W1** `+ AssertionError` | **316/316** | **26/26** | **CUSTOM CUSTOMI PYLITERAL** | ops.py:455 + **ops.py:444** |
| **W1s** `+ AssertionError`, ops.py:444's message only | 316/316 | 26/26 | CUSTOM CUSTOMI PYLITERAL | ops.py:455 + ops.py:444 — **nothing else** |
| **W2** `+ NotImplementedError` | 316/316 | 26/26 | **none** | nothing new |
| **W3** `+ ValueError` | 316/316 | 26/26 | **none** | nothing new |
| **W4** bare `except Exception` | 316/316 | 26/26 | **none** | nothing new, **and 4 more sites** |

**W1 buys all three of `CUSTOM CUSTOMI PYLITERAL`, and W2/W3/W4 buy nothing at all.** The
brief's premise — one `except` arm gates three ops — is **confirmed, and the arm is
`AssertionError` and only `AssertionError`.**

**Costs, measured (`cs-opshape.py`, `opshape-run0.txt`).** The cost of a widening is what
it swallows, so the price is per *site*, over all 77 ops at two arities:

* `except AssertionError` (W1) admits **four** `AssertionError` sites, and only one of
  them is a real fact:
  * **ops.py:444** `None input shape not supported for X` — **21 ops.** A `GroupOp.Broadcastable`
    op with shapeless srcs. **This is a fact about the graph, and it is the one the pattern
    compiler produces.**
  * **ops.py:438** `assert len(self.src) == 1, "unary ops must have 1 src"` — **8 ops.** A
    **wrong fixture**, not a shapeless op.
  * **ops.py:137** `CUSTOM/CUSTOMI arg must be (str, DType)` — **2 ops** (`CUSTOM`, `CUSTOMI`). A
    **wrong fixture.**
  * **ops.py:141** `INS arg must be (instruction, DType)` — **1 op.** A **wrong fixture.**
* `except Exception` (W4) additionally admits **22 more op-slots** whose only fault is that
  the probe built them wrong: 11 `IndexError` (ops.py:345/354/378/382/388/391/404),
  4 `AttributeError` (ops.py:135/368), 1 `TypeError` (ops.py:365). And over the 77 ops at
  one src each, `except Exception` would swallow **77 of 77** — every one of them a
  `CTOR:`-class mistake. **A bare `except` here would turn "I built this node wrong" into
  "this op has no shape", spelled `R`.** That is the instrument-made-permissive hazard,
  measured rather than feared.
* **ops.py:451** `NotImplementedError: no shape handling for X with Y` — the third fact,
  the one `R` would be a **lie** about ("upstream has no rule at all"). **MEASURED 0
  occurrences** over the corpus *and* over all 77 ops × 2 arities. So `W2` buys nothing and
  `W4` is not merely unused, it is a live lie waiting for a node nobody has built yet.

**The priced widening is therefore W1s, not W1**, and it is one predicate:

```python
except (RuntimeError, AssertionError) as e:
  if isinstance(e, AssertionError) and not str(e).startswith("None input shape not supported for "):
    raise          # ops.py:438/137/141 -- a wrong fixture, not a shapeless op
  return "R"
```

W1 and W1s are **identical over all 316 nodes** and differ on **exactly one** row, PLANT-A
below. That is the attribution, and a control carrying both edits would have measured their
sum.

### A STALE LIST, third instance, and it is the one `R`'s meaning rests on

`cshape`'s docstring and `graphcmp.bend`'s `shape_str` comment both say `R` is for "the ten
ops that have no shape (**ops.py:331-338**)". ops.py:331-334 does list exactly those ten,
and **MEASURED at zero srcs, thirteen ops answer through ops.py:455**:

```
transcribed  BACKEDGE BARRIER ENDIF GROUP IF LINEAR PROGRAM REWRITE_ERROR SINK SOURCE
MEASURED     BACKEDGE BARRIER ENDIF GROUP IF LINEAR NOOP PROGRAM PYLITERAL REWRITE_ERROR SINK SOURCE UNSHARD
missing      NOOP  PYLITERAL  UNSHARD        <- reached through their OWN `_shape` arms
```

`NOOP` (ops.py:344's "special case for RESHAPE on NOOP"), `PYLITERAL` (ops.py:375) and
`UNSHARD` answer `None` from arms of their own. **`R` is still the faithful spelling of
`.shape` raises — but the list behind it is incomplete, and it is a comment nobody voted
on, which is the same failure as `flip`'s stale 7/7.** (`DENOMINATOR.md`'s own §3 already
lists a `PYLITERAL` as one of the twelve it probed; the comment is the stale thing, not
the measurement.)

---

## 2. IS THE `AND`-ROOTED RULE UPSTREAM'S OR THE DIFFER'S? **UPSTREAM'S, AND IT ASSERTS.**

`cs-androot.py` calls `_get_clause` for **18 `UPat` shapes — one per clause branch of
`upat.py:25-64`** (`androot-run0.txt`):

```
ROOT HISTOGRAM over 18 patterns: {'AND': 17, 'CUSTOMI': 1}
  roots that are OR: 0    patterns whose IR CONTAINS an OR: 2 (upat.py:20 is_any, upat.py:63 fork)
  and in both cases the OR is a CHILD of the AND -- never a root
  the 1 CUSTOMI root is upat.py:66's own else-arm: `else UOp(Ops.CUSTOMI, arg=("True", void))`
```

Four upstream sites make the root `AND`, and the **fourth is an `assert`**:

| `file:line` | what it says |
|---|---|
| `tinygrad/uop/upat.py:66` | `return UOp(Ops.AND, src=tuple(and_clause)) if and_clause else UOp(Ops.CUSTOMI, arg=("True", dtypes.void))` |
| `tinygrad/uop/upat.py:20` | `if self.is_any: ... return UOp(Ops.AND, src=(UOp(Ops.OR, ...),))` — the OR is wrapped |
| `tinygrad/uop/upat.py:118` | `pm_proc = PatternMatcher([(UPat(Ops.AND, name="a"), do_process_and)], compiled=False)` — matching is **dispatched on `Ops.AND`** |
| **`tinygrad/uop/upat.py:140`** | **`assert x.op is Ops.AND`** — after `if x.op is Ops.CUSTOMI: x = UOp(Ops.AND, (x,))` at `:139` |

**So the restriction is upstream's, it is load-bearing for matching and not merely a
representation choice, and it is enforced by an assertion rather than by a convention. A
graph whose root is `OR`, or an atom, cannot be expressed through upstream's own pattern
compiler at all — and the differ imposes nothing here. This closes the question
permanently: there is nothing in `graphcmp.py` to widen for it.**

---

## 3. REACHING THE THREE. THE WIDENING IS NECESSARY AND NOT SUFFICIENT.

py side: upstream's own construction, `tinygrad/uop/upat.py:66`,
`_get_clause(UPat(Ops.ADD), UOp(Ops.CUSTOMI, arg=("uop", dtypes.void)))` — 4 nodes,
`CUSTOMI PYLITERAL CUSTOM AND`. Never hand-written.

**W0 (live): the emitter DIES.** Not "no row" — `row_of` raises out of the whole graph:

```
py 2:i1 7:CUSTOMI    4:void 1:R 2:i0 1:N 13:n(suop,Dvoid) 3:n()
py 2:i2 9:PYLITERAL  4:void 1:R 2:i0 1:N 4:OADD 3:n()
py 2:i3 6:CUSTOM     4:void 1:R 2:i0 1:N 23:n(s{0}.op is {1},Dvoid) 8:n(i1,i2)
py !! DIED AssertionError: None input shape not supported for Ops.AND
```

**W1/W1s/W4 emit all four, and emit them IDENTICALLY** (`rows-run0.txt`): 1 of 4 rows
changed, and it changed from *died* to *emitted*.

bend side: `cs-patir.bend`, built with `O.UOp.new` and the port's own `Arg` constructors,
rendered by `graphcmp.bend`'s own `rows.of` so the port is on trial and not my fixture.

```
# root=4 nodes=5 settled=False
bd 2:i1 7:CUSTOMI   1:? 1:? 2:i0 1:N 14:in(suop,Dvoid) 3:n()
bd 2:i2 9:PYLITERAL 4:void 1:R 2:i0 1:N 11:rd(OADD,i0) 3:n()
bd 2:i3 6:CUSTOM    1:? 1:? 2:i0 1:N 24:in(s{0}.op is {1},Dvoid) 8:n(i1,i2)
bd 2:i4 3:AND       1:? 1:? 2:i0 1:N 1:N 5:n(i3)
```

**VERDICT: DISAGREE — 9 field mismatches out of 24 field-records; 15 agree.** Per node:

| node | mismatching fields | py | bend |
|---|---|---|---|
| 1 `CUSTOMI` | dtype, shape, **arg** | `void` / `R` / `n(suop,Dvoid)` | `?` / `?` / `in(suop,Dvoid)` |
| 2 `PYLITERAL` | **arg** only | `OADD` | `rd(OADD,i0)` |
| 3 `CUSTOM` | dtype, shape, **arg** | `void` / `R` / `n(s{0}.op is {1},Dvoid)` | `?` / `?` / `in(...)` |
| 4 `AND` | dtype, shape | `void` / `R` | `?` / `?` |

`depth`, `tag` and `src` agree on **4 of 4**; `op` agrees on **4 of 4**. Ledger on the bend
side: **`?=3`**. Ledger on the py side: all eight markers 0.

### The three blockers are NOT the `except` arm

`cs-plantir.bend` asks four separate questions so one unsettled node cannot be mistaken
for a missing rule:

| # | graph | `settled` | rendered | what it settles |
|---|---|---|---|---|
| Q1 | `AND` over two **shaped** CONSTs | **True** | `7:weakint 2:()` | **the port HAS an `AND` rule** (`uop/fold.bend:2265`) |
| Q2 | `CUSTOMI`, **no srcs** | **False** | `1:? 1:?` | the port has **no dtype/shape rule** for it |
| Q3 | `CUSTOM`, **no srcs** | **False** | `1:? 1:?` | same |
| Q4 | `PYLITERAL`, no srcs | **True** | `4:void 1:R` | the **same upstream fact, a different port answer** |

1. **`tinybendygrad/uop/fold.bend:2296-2297` is a port defect, and it is not the assert.**
   Upstream `tinygrad/uop/ops.py:370-372`:
   ```python
   case Ops.CUSTOM | Ops.CUSTOMI:
     if self.dtype is dtypes.void: return None
   ```
   That is a **real `_shape` of `None`**, and `.shape` then raises at ops.py:455 — which is
   why the py side says `void`/`R`. The port's arms answer `None{}`, which means **"this
   node has no `Derived` at all"**, i.e. the port-only state `?`. Q2/Q3 have **zero srcs**,
   so upstream's Broadcastable `assert` is not even reached: this is the ladder conflating
   *"no shape"* with *"no answer"* — the exact conflation `shape_str`'s `?`/`R` split was
   created to undo, one level down in the ladder instead of in the renderer.
   **Q4 is the fix, already present in the port:** `OpsPYLITERAL -> late()` and
   `late() = Some{DtShape{S.void(), None{}}}` (fold.bend:1040-1041) renders `4:void 1:R` —
   **the exact letters the py side produces for `CUSTOM`/`CUSTOMI`, from the port's own
   arm, on the port's own op.** Two ops, one upstream rule, two port answers.
   The arm's own comment (`fold.bend:2286-2298`) says the non-void half is "NOT PORTED,
   deliberately: it needs its own `_broadcast_shape` oracle and its own rows" — and that
   reading is **wrong for the void case**: the void case is upstream's first line and needs
   no oracle.

2. **The `AND` root's shape has no answer on either side, and that is upstream's fault.**
   Q1 proves the port can fold an `AND`; on the pattern IR it cannot, because `all_shapes`
   (`fold.bend:875`) refuses a shapeless operand exactly as upstream's assert does. Under
   **any** widening the py side must print *something* where upstream's answer is "this is
   a bug". So `R` would be a claim upstream does not make, and the port's `?` is the honest
   letter. **This blocker cannot be widened away, and it should not be: `AND` over
   shapeless srcs is not a tensor graph, and the differ's `R` means "the op has no shape"
   (ops.py:331-338), not "upstream would like you to stop".**

3. **`Arg` has no home for the matcher IR's args, on either spelling.** py
   `n(suop,Dvoid)` vs bend `in(suop,Dvoid)`; py `OADD` vs bend `rd(OADD,i0)`. The port's
   `AInk{ins, dt}` IS the `(String, DType)` pair — `uop/spec.bend:1043-1047` says so
   explicitly ("`AInk` IS that pair, and it is the only constructor that is") — but
   `argstr` renders it under **INS's** prefix `in(`, and the py side's generic `_carg`
   tuple grammar renders it as `n(...)`. And a **bare `Op`** (PYLITERAL's literal,
   `Ops.ADD`) has no `Arg` variant at all: `AReduce` is the only one holding an `Op` and it
   holds it paired with a count. **A third blocker, and it is a normal-form decision inside
   `graphcmp.bend`'s `argstr` — which is the other unit's file.**

### What the widening admits that is invalid — stated plainly

**Yes, and it is measured, not argued.** Under **W1 (unscoped)** the emitter prints `R`
for `UOp(Ops.NEG, src=())`, a node upstream rejects at **ops.py:438** with `unary ops must
have 1 src`. The graph is malformed, `R` says its shape is merely *absent*, and a differ
cannot tell those apart. Under **W1s** it refuses. Under **PLANT-B** — `UOp(Ops.ADD, src=(
CUSTOMI(...),))`, upstream **ops.py:444** — W0 dies, W1/W1s/W4 all print `R`, and that one
*is* upstream's own pattern-compiler fact, so it is admitted correctly.

**So: `R` under W1 conflates two upstream facts, and the ledger rule this differ rests on
is that a letter is ONE fact.** The honest widening renders the ops.py:444 case under a
**different letter** — "upstream ASSERTS on `.shape`" — which the bend side can also
spell, since the port's fold refuses for exactly the same reason. **That needs a new atom
in `graphcmp.py`'s `ATOMS`/`LEDGER`, which is the other unit's file, so it is proposed and
not applied.** Note what this costs: with `R` reused, the widening is inert on the existing
corpus (**0 of 312 rows moved, under all four arms**) — so it is cheap and it is *wrong*,
which is the worst combination.

---

## 4. CORPUS, BEFORE AND AFTER, AGAINST 77, BOTH SIDES, WITH THE SPLIT

Live corpus, re-measured at the pin (`plant-run0.txt` §5, and
`graphcmp-oracle.py` unchanged: `# TOTAL: 25 graphs, 313 nodes per side, 61 distinct ops`,
`ORACLE SELFCHECK: OK`):

```
                              BEFORE    AFTER (ceiling)
denominator                       77        77      (measured len(list(Ops)))
graphs                            25        26      (+ patir)
reached PY                        61        64
reached BEND                      61        64
reached BOTH                      61        64
py-only                           []        []
bend-only                         []        []
NEITHER (either side)             16        13
```

`NEITHER` after: `CUSTOM_FUNCTION GETADDR INS MSELECT MSTACK MULACC PROGRAM REWRITE_ERROR
SOURCE STAGE THREEFRY UNSHARD WMMA`.

**THE LIVE NUMBER IS UNCHANGED AT 61/77 both sides, `py-only=[] bend-only=[]`.** `patir`
cannot be added to the live corpus: the `GRAPHS` entry and the `graphcmp.bend` dispatch arm
belong to the `ADev` unit, and this unit may not edit either file. The 64/64/64 above is a
**ceiling measured from this unit's own probe**, and it is not a claim of agreement either.

**And the 64/64/64 with `py-only=[] bend-only=[]` is exactly the number this brief warns
about.** On the very same graph the verdict is **DISAGREE at 9 field mismatches** with
**`?=3` on the bend side**. The op census counts an op REACHED from the row's `op` column,
which is printed even when the row reads `?` in dtype *and* shape. **`?=0` on both sides
with `py-only=[]` and a clean 64/64/64 would have shipped.** That is `flip`, reproduced on
purpose, and it confirms `?` measures omission and not agreement.

**`MULACC`** is untouched by any of this: device-gated at `codegen/decomp/op.py:118`
`if Ops.MULACC in ops:`, listed by exactly one renderer, `tinygrad/renderer/ptx.py:33`.

---

## 5. PLANT AND DISARM, DISARM FIRST

**DISARM FIRST** (`plant-run0.txt` §1). This unit edited **nothing** outside its own
directory, so the disarm is "remove the probes" and it must move nothing:

```
md5 .agents/slop/graphcmp.py at entry : 4a0d2467b7e70d701afac68091394f40
census run twice, byte-equal          : True   (sha1 bca5e35dfb5dd696)
graphs 25   rows 312   SHAPE_NONE_HITS 0
md5 after two censuses                : 4a0d2467b7e70d701afac68091394f40  (unchanged=True)
THE DISARM'S VERDICT: PASS -- moved nothing
```

The comparison is between two runs, not a claim that the baseline agrees: `lin` and `loop`
disagree **on purpose**. And the whole point of "disarm first" is that it is measured
*before* the plant exists, so a disarm that quietly carries a second mutation cannot hide
behind the plant.

**PLANT-A — the attribution, ONE edit per arm.** `UOp(Ops.NEG, src=())`, upstream
**ops.py:438**:

```
W0  except RuntimeError                       cshape -> !! DIED AssertionError: unary ops must have 1 src
W1  + AssertionError, UNSCOPED                cshape -> R            <-- the widening admitted a bug
W1s + AssertionError, ops.py:444 only         cshape -> !! DIED AssertionError: unary ops must have 1 src
W4  bare except Exception                     cshape -> R
```

W1 and W1s differ by **one predicate** and the difference is **exactly this row**. Asking
`cshape` directly, not through `row_of`: `row_of` reaches `.dtype` first and a zero-src
`NEG` dies in `promo_dtype(())` at ops.py *before* `cshape` is called — a plant driven
through `row_of` would have measured `promo_dtype`.

**PLANT-B — the invalid graph, `UOp(Ops.ADD, src=(CUSTOMI(...),))`, upstream ops.py:444.**
W0 dies; W1, W1s and W4 all print `R`. Detected — it changes what the emitter says — so the
widening is not silent.

**PLANT-C — the pattern IR, both sides.** Reported in §3. `VERDICT: DISAGREE`, 9/24 field
records, ledger `?=0/3`.

**Blast radius, measured** (`plant-run0.txt` §2): under **W1, W1s and W4 alike, 0 of 312
rows changed and 0 graphs were lost.** The whole corpus diff is by whole
`name=value` **line**, not by row name.

**Ledger over the live 25-graph corpus, live `cshape`, per row, by the differ's own
`G.LEDGER` + `G.at_value`:** `binblob y=1`, `buffer z=1`, `lin E=1`, everything else 0;
`SHAPE_NONE_HITS 0`. A first version of that table scanned every field for the marker's
**text** and printed all zeros on a corpus the differ's own census reports as carrying
`z y q E ?` — a ledger that reads 0 everywhere is indistinguishable from a ledger that is
not connected.

---

## 6. THE CLAIM I DID NOT MAKE

**Nothing here says the corpus compares training graphs.** `bw` is the gradient of one eager
expression; `schedule -> render -> compile` is still forward-only; `late` and `g_allred`
are graphs the port **reproduces and does not produce**. `patir` is likewise
**reproduced, not produced**: its py side is upstream's `_get_clause`, but nothing in the
port's pipeline *emits* a pattern IR, and the port's own `late_rewrite_patterns` path
compiles patterns rather than running them. **A widening that lets the differ canonicalise
matcher IR is not a step toward `schedule -> render -> compile`; it is a step toward
comparing a data structure the pipeline does not pass through.**

**And the refusal is the result.** Three ops stay unreached: two behind a **port** defect
in `fold.bend:2296-2297` that Q4 proves is fixable with the port's own `late()`, one
behind upstream's `assert` at `ops.py:444` that has no correct answer to compare, and
`MULACC` behind its device gate. **A silently widened `except` would have taken the corpus
from 61 to 64 with `py-only=[]` and `?=0` on the py side, and every one of those three
would have been a `?` and a rung-1 mismatch underneath.**

---

## 7. RULES (fresh prefix `CSH-`, append-only)

* **CSH-1. A widening's cost is the set of SITES it swallows, and one exception CLASS is
  rarely one site.** `except AssertionError` over all 77 ops admits four sites — ops.py:444
  (21 ops, a real fact), ops.py:438 (8), ops.py:137 (2), ops.py:141 (1) — and only the
  first is about shapes. `except Exception` admits **22 more** whose only fault is a
  malformed fixture, and at one src each it swallows **77 of 77**. A widening must be
  priced per raising site, which means running it over the op space and not over the corpus.
* **CSH-2. `except AssertionError` is NECESSARY and NOT SUFFICIENT, and the sufficiency
  failure is two PORT defects, not the arm.** `uop/fold.bend:2296-2297` answers `None{}`
  ("no `Derived`") where upstream `ops.py:370-372` answers `None` ("no shape"), and Q4
  proves the fix is the port's own `late()` — `OpsPYLITERAL` already renders `4:void 1:R`
  from the same upstream fact. **Separate "the port has no rule" from "the port refuses the
  same assert" with a graph whose srcs are SHAPED; one settled control settles it.**
* **CSH-3. An op census counts an op REACHED from a row's `op` column, which is printed
  even when dtype AND shape both read `?`.** So a graph that DISAGREes at 9 field
  mismatches with `?=3` on one side still adds that op to BOTH sides' reach counts, with
  `py-only=[]` and `bend-only=[]`. **A reach count is not agreement, and `?=0` is not
  agreement** (`flip` read `?=0` on both sides while disagreeing at 6/7). Report the
  verdict first; a clean 64/64/64 here is the `flip` pattern reproduced on purpose.
* **CSH-4. "EVERY PATTERN IR IS `AND`-ROOTED" IS UPSTREAM'S RULE, enforced by an assert,
  and the question is closed.** `tinygrad/uop/upat.py:66` returns `AND` (or `CUSTOMI` for
  an empty clause), `:20` wraps the `OR`, `:118` dispatches `pm_proc` on `UPat(Ops.AND)`,
  and **`:140` is `assert x.op is Ops.AND`**. Measured over 18 `UPat` shapes: 17 roots
  `AND`, 1 `CUSTOMI`, **0 roots `OR`**. There is nothing in the differ to widen.
* **CSH-5. `R` means "the op is in upstream's NO-SHAPE LIST", and the list in the two
  comments (`cshape`'s docstring, `graphcmp.bend`'s `shape_str`) is INCOMPLETE.** Ten ops
  are transcribed from ops.py:331-334; **thirteen** answer through ops.py:455 when measured.
  `NOOP`, `PYLITERAL` and `UNSHARD` reach it through their own arms. The letter is right;
  the list behind it is a stale comment nobody voted on, and it is the third instance of
  that family in this brief.
* **CSH-6. THE EMITTER DYING IS NOT A MISSING ROW, AND BOTH READ AS "EMITTED".** Under the
  live arm the pattern IR kills `row_of` with an `AssertionError` out of the whole graph;
  under every widened arm it emits 4 rows of which **3 carry a field the other side cannot
  produce**. A count of rows, and a `py-only`/`bend-only` pair, are silent about both.
  **Print the op count per `except` arm and the per-field mismatch list, or the
  instrument's permissiveness is invisible.**
* **CSH-7. A monkeypatch is the right instrument for a file another unit is editing, and it
  needs the md5 PINNED.** `graphcmp.py`'s md5 moved `026c1cd8…` → `4a0d2467…` under this
  unit and a `selfcheck` run died with `NameError: name 'dev' is not defined` at `:734`
  mid-edit. Pin the md5, re-run the census **twice with a byte comparison**, and say which
  pin a number belongs to. Relatedly: **`DENOMINATOR.md` §3 cites `ops.py:442` for the
  assert and it is `ops.py:444`** — a line number in a file that is being rewritten is a
  claim with a shelf life.
* **CSH-8. `import "./graphcmp.bend" as GC` WORKS, and it is how a probe gets the
  DIFFER's own renderer.** `cs-patir.bend` and `cs-plantir.bend` use it, so every bend-side
  row quoted above is `graphcmp.bend`'s text and not a re-implementation. Two Bend traps on
  the way: a relative import from `.agents/slop/cshape/` needs **`../../../tinybendygrad`**
  (a `$TMPDIR` copy or a wrong depth produces `no such file`), and `def show(name: String,
  +f: O.Found)` — the linear binder is `+f`, **not** `+name`, or the compiler reports
  `expected : f / observed : f (consumed more than once)`.
* **CSH-9. `bend` writes its upgrade notice to STDOUT, and a probe that reads a transcript
  must drop it.** `bend 2.0.35 is available: run bend update` parses as neither a comment
  nor a row: `ValueError: invalid literal for int() with base 10: 'bend 2.0.35 is
  available'`. The same class as `graphcmp.py`'s `--dev NULL` 0-bytes-when-captured.

---

## 8. WHAT I DID NOT DO

Did not edit `graphcmp.py` or `graphcmp.bend` (**including `cshape` itself** — the
widening is a proposal, and it is wrong as `R`, so applying it would have been a
false theorem). Did not add `patir` to `GRAPHS` or add its dispatch arm. Did not touch
`fold.bend:2296-2297` (read-only files are reported, not fixed) and did not add the
`ATOMS`/`LEDGER` letter an assert-shaped fact would need. Did not touch `MULACC`'s PTX
gate. Did not answer the `ADev` normal-form question, which is what the `in(` vs `n(`
mismatch above is waiting on. Did not commit anything.
