# NONSHAPE — two `None`s that meant one thing, and an `Arg` that cannot hold an `Op`

Unit `NONSHAPE`, 2026-10-05. **Edited one file: `tinybendygrad/uop/fold.bend`** (+68 lines,
md5 `e372ca226461fe2295b49a9990db0165` -> `310c3975393ad37ea1c3c5caf9822756`). Nothing else
in the tree. Nothing committed.

Substrate pins at every measurement: `graphcmp.py` `4a0d2467b7e70d701afac68091394f40`,
`graphcmp.bend` `184f7edd80404c8b7aedb33beb28bcd8`, `fold.bend` as above.

Files, all mine: `noneshape/ns-pyarg.py` (what upstream answers, on CPython),
`noneshape/ns-fix.bend` (EIGHT separate port-side questions, one graph each),
`noneshape/ns-patir.bend` (the pattern IR alone, so the verdict compares one graph to one
graph), `noneshape/ns-corpus.py` (blast radius, split, two-sided verdict),
`noneshape/ns-revert.py` (reverse-the-edit + md5, for the baseline),
`noneshape/ns-argplant.py` (which spelling of the pair should win),
`noneshape/ns-oparg.bend` (**does not compile, and that is its output**).
Transcripts: `pyarg-run0.txt`, `ns-fix-run1.txt`, `patir-run0.txt`, `patir-run1.txt`,
`corpus-run1.txt`, `corpus-run2.txt` (byte-equal), `argplant-run0.txt`, `oparg-run0.txt`,
`foldrun-BEFORE.txt`, `foldrun-AFTER.txt` (byte-equal).

---

## 1. WHAT `None` AND `None{}` MEAN AT EACH SITE UPSTREAM

**Two different questions, and the port answered both of them the same way.**

`tinygrad/uop/ops.py:455` is `.shape`, a property: `if (ret:=self._shape) is None: raise
RuntimeError(...)`. So **`None` at that site means "this op HAS NO SHAPE"**, and the
differ's faithful spelling is `R` (`graphcmp.bend`'s `shape_str`: outer `None` -> `?`,
`Some{None{}}` -> `R`).

`None{}` in `fold.bend` is the outer `Maybe` of `dt_shape` — **"this file produced NO
`Derived` for this node"**, which is a PORT-ONLY state. `derived.put` (fold.bend) turns
`dt_shape`'s `None{}` into no table entry, `F.Kahn.settled` then reads `False`, and the
differ prints `?` in the dtype AND the shape column.

So at `fold.bend:2296-2297` (`case O.OpsCUSTOM{}: None{}` / `case O.OpsCUSTOMI{}: None{}`)
the port was answering **"I know nothing"** where upstream answers **"no shape"** — and
the two are two different letters, `?` and `R`.

### Every upstream `None` in the `_shape` arm under test, with `file:line`

| `file:line` | the line | what `None` means there |
|---|---|---|
| `ops.py:336` | the ten "late ops don't have shape" `return None` | no shape |
| `ops.py:340` | `if self.dtype is dtypes.void: return None` (INS) | no shape |
| `ops.py:349` | `return self.src[0]._shape if len(self.src) >= 1 else None` (NOOP) | no shape |
| **`ops.py:371`** | **`if self.dtype is dtypes.void: return None` (CUSTOM/CUSTOMI)** | **no shape** |
| **`ops.py:372`** | **`return _broadcast_shape(*input_shapes) if input_shapes else None`** | **no shape** |
| `ops.py:374` | `CUSTOM_FUNCTION: return None if void else ()` | no shape |
| `ops.py:375` | `PYLITERAL: return None` | no shape |
| `ops.py:399` | `UNSHARD if len(self.src) == 0: return None` | no shape |
| `ops.py:392` | `if ps is None: return None` (BITCAST) | no shape |
| `ops.py:455` | `.shape`'s `if (ret:=self._shape) is None: raise` | **the raise**, i.e. no shape |
| **`ops.py:444`** | **`assert ... all(x is not None ...)`** | **NOT a `None` — an ASSERT.** The port's `all_shapes` refuses the same list. Unchanged. |

**Ten sites answer `None` and every one of them means "no shape".** There is no site in
this arm where `None` means "no answer". The conflation was the port's, at one line.
(`ops.py`'s `None`s cited in this table were re-read at the pin above; `:392` is BITCAST's
`if ps is None: return None` — a first draft of this note said `:432`, which is REDUCE's
`num_axes = self.arg[1]`. **My own stale citation, caught by reading the line.**)

### The two proofs, measured separately (`pyarg-run0.txt` §E)

```
CUSTOM dtype=void        : _shape=None  shape-raises=True
CUSTOM dtype=uint32, 0src: _shape=None  shape-raises=True
CUSTOM dtype=uint32, 1 SRC: _shape=(2,)  shape-raises=False
CUSTOM dtype=void,   1 SRC: _shape=None  shape-raises=True
CUSTOM uint32, SHAPELESS+shaped src     : _shape=(2,)
```

Rows 1 and 2 are `ops.py:371` and `ops.py:372` — **two lines, two proofs, one
conclusion**, which is why the arm has to be two lines and not one. Row 3 is the
broadcast. Row 4 says **`ops.py:371` runs FIRST**: a void CUSTOM over shaped srcs still has
no shape, and the srcs are never read. Row 5 says **`ops.py:372` FILTERS** the shapeless
src (`[x._shape for x in self.src if x._shape is not None]`) where the Broadcastable arm's
`assert` at `ops.py:444` refuses it.

---

## 2. THE FIX

**Three insertions into `tinybendygrad/uop/fold.bend`, +68 lines, no signature of any
existing def touched, no existing row moved.**

1. **`some_shapes` (fold.bend:916-932)** — `ops.py:372`'s filter, beside `all_shapes`
   (fold.bend:907) so the contrast is one screen apart. `shapes_of.acc` turns a shapeless
   src into the OUTER `None`; `some_shapes.acc2` keeps the accumulator and carries on.
   Four defs (`put`/`acc2`/`go`/`some_shapes`) because Bend spends a list when it reads
   it and `match` may not scrutinise a computed value.
2. **`custom_ds` (fold.bend:1164-1179)** — `case S.Dt{_,_,S.CVoid{},_}: late()` and
   `case _: Some{DtShape{dt, bcast_shape(some_shapes(ss))}}`, with `ins_dt(arg)` for the
   dtype. **The void arm is `late()` and not a new spelling**, because `cfun_ds.shape`
   (fold.bend:1133) already arms on the identical upstream test (`ops.py:374` and
   `ops.py:371` are the same line) and `late()` (fold.bend:1064) is
   `Some{DtShape{S.void(), None{}}}`. `Some{None{}}` is the `R`. The `None{}` on the
   non-`AInk` arm stays a refusal: that is `ops.py:137`'s assert on a WRONG FIXTURE, not a
   shapeless op.
3. **The ladder arms (fold.bend:2364-2365)** — `custom_ds(arg, ss)`.

**The old comment on those arms was wrong twice and both corrections are recorded in
place.** It claimed the arm needed "its own `_broadcast_shape` oracle and its own rows".
The void half needed neither (`_broadcast_shape` was already here as `where_ds` and
`alu_ds` use it, and the void half is `cfun_ds.shape`'s arm verbatim); and it described the
shape half as "`all_shapes` + `bcast_shape`", which is the half that was wrong, because
`ops.py:372` filters where `all_shapes` asserts. **What the arm actually wanted was a
second WALK, not a second oracle.**

### EIGHT graphs, one question each (`ns-fix.bend` -> `ns-fix-run1.txt`)

`settled=True` on **8 of 8** after; `settled=False` on 7 of 8 before.

| # | graph | before | after | upstream |
|---|---|---|---|---|
| Q1 | `AND` over two shaped CONSTs (the control) | `True` `7:weakint 2:()` | `True` | unchanged — the port HAS an `AND` rule (`fold.bend:2327`) |
| Q2 | `CUSTOMI` void, 0 srcs | `False` `1:? 1:?` | **`True` `4:void 1:R`** | `None` |
| Q3 | `CUSTOM` void, 0 srcs | `False` `1:? 1:?` | **`True` `4:void 1:R`** | `None` |
| Q4 | `PYLITERAL` 0 srcs | `True` `4:void 1:R` | `True` `4:void 1:R` | `None` |
| Q5 | `CUSTOM` u32, **0** srcs | `False` `1:? 1:?` | **`True` `3:u32 1:R`** | `None` (line 3) |
| Q6 | `CUSTOM` u32, 1 shaped src | `False` `1:? 1:?` | **`True` `3:u32 6:(l0:2)`** | `(2,)` |
| Q7 | `CUSTOM` u32, **shapeless**+shaped src | `False` `1:? 1:?` | **`True` `3:u32 6:(l0:2)`** | `(2,)` — the FILTER |
| Q8 | `CUSTOM` **VOID**, 1 shaped src | `False` `1:? 1:?` | **`True` `4:void 1:R`** | `None` — **void wins** |

**Q7 against Q6 is the pair that separates the filter from the assert** (`all_shapes`
would refuse Q7; upstream answers it). **Q8 against Q6 is the pair that separates
"void is checked first" from "void is checked last"** (Q8 must NOT broadcast). Neither
row can be produced by an arm that just answers `late()` everywhere, and neither by one
that answers `alu_ds`.

### The baseline was taken by reversing the edit, and the reversal is proven

`ns-revert.py` reverses the three insertions and prints the md5:
`e372ca226461fe2295b49a9990db0165 == PIN`. Without that md5 the baseline is a claim; with
it, the BEFORE and AFTER verdicts below differ by `fold.bend` and by nothing else. No VCS
checkout of a file six units read.

---

## 3. ITEM 2: `Arg`. **ONE SPELLING CHANGE AND ONE TYPE CHANGE, AND THEY ARE NOT THE SAME KIND.**

### 3a. `n(` vs `in(` — a MISSING ARM in `carg`. Not a port defect.

`graphcmp.py`'s `carg` (graphcmp.py:487) has **eleven** per-op arms — CONST, RANGE, REDUCE,
WMMA, INS, ALLREDUCE, COPY, CUSTOM_FUNCTION, CALL, SINK, PROGRAM — and **none of them is
CUSTOM/CUSTOMI**, so a `(str, DType)` falls to the generic `_carg` tuple grammar. MEASURED
(`pyarg-run0.txt` §A):

```
carg(Ops.CUSTOM, ('{0}.op is {1}', void)) = n(s{0}.op is {1},Dvoid)
carg(Ops.INS,     ('{0}.op is {1}', void)) = in(s{0}.op is {1},Dvoid)
graphcmp.bend argstr(AInk{ins, dt})        = in(s{0}.op is {1},Dvoid)
```

**One value, two PY-side spellings chosen by which op holds it**, and one bend-side
spelling. `carg`'s own docstring says it "Mirrors `argstr` in graphcmp.bend character for
character". **MEASURED: it does not, and the arm it is missing is one line.**

`graphcmp.py`'s OWN precedent is the COPY arm (ADEV-1, `carg`'s comment): `Ops.COPY`'s arg
is `str|tuple[str,...]` stored verbatim, with no arm it fell to the generic tuple grammar
while ALLREDUCE went through `dev`, "so ONE graph spelled the SAME value two ways two
nodes apart … no third option existed: exactly one of the two spellings could have been
right", and the fix that shipped was **to add an arm**. Same class. And
`graphcmp.py`'s `COMPOSITE` tuple registers `in(` as a composite form the census decodes,
so `in(` is a first-class spelling and `n(` is the generic one.

**PLANTED AND MEASURED (`argplant-run0.txt`), as a monkeypatch — nothing on disk:**

```python
if op in (Ops.CUSTOM, Ops.CUSTOMI): return f"in({bstr(x[0])},{dt(x[1])})"
```

| | field mismatches / 24 |
|---|---|
| P0, no arm | **5** |
| P1, the one arm | **3** |

and **P1 moves 0 of the live corpus's py rows** — inert on `GRAPHS` because the pattern
compiler IR is not in it. So P1 is cheap AND right, which is the combination a widening
usually is not.

**Answer: `in(` should win, by ONE ARM in `graphcmp.py`. It is not a port change at all,
and it is not mine to land.**

### 3b. A BARE `Op` — a HOLE IN THE TYPE. Yes, it is a type change.

`O.Arg` (uop/ops.bend:1054) has **nineteen** constructors. Exactly **two** hold an `Op` and
**both pair it**: `AReduce{rop: Op, num_axes: U32}` and `AAllred{rop: Op, dev: S.Dev}`.
There is no constructor holding an unpaired `Op`. `ns-oparg.bend` is the demonstration and
it does not compile:

```
SOME PROOFS FAIL
Error:
- expected : O.Arg
- observed : O.Op
```

**This is not a naming disagreement and no arm in `carg` can fix it** (P1 leaves node 2 at
`OADD` vs `rd(OADD,i0)`). The cshape probe spelled it `AReduce{OpsADD, 0}` and got
`rd(OADD,i0)` — the differ's own text admitting a graph it could not build.

**AND `ops.bend`'s `Arg` block MIS-TRANSCRIBES IT.** ops.bend:1032 lists
`tuple[int, ...]  ATuple  PERMUTE/FLIP arg, UNSHARD arg, MSELECT arg, PYLITERAL arg`.
`tinygrad/uop/__init__.py:101` says **"PYLITERAL carries a Python literal as an arg for
CUSTOM predicates"**, and the four values `upat.py` builds are an `Ops` (`:26`), a `DType`
(`:39`), a `str` (`:44`) and `self.arg` (`:29`) — **never a `tuple[int, ...]`**.

Coverage of `upat.py`'s own construction sites, measured on CPython
(`pyarg-run0.txt` §B):

| literal | site | py spelling | port `Arg` | verdict |
|---|---|---|---|---|
| bare `Ops` | `upat.py:26` | `OADD` | **none** | **HOLE** |
| `DType` | `upat.py:39` | `Df32` | `ADt{dt}` | covered, prints bare on both sides |
| `str` | `upat.py:44` | `sWEAK` | `AStr{s}` | covered |
| `Any` (a tuple) | `upat.py:29` | `n(sa,Dvoid)` | `AInk` / `ATuple` | covered |
| `frozenset[...]` | `upat.py:25,36,43` | **`raw(frozenset)`** | **none** | **HOLE** — and the py side already refuses it BY NAME |

**The one variant that fixes the named defect is `AOpLit{op: Op}`**, for `upat.py:26`.
`frozenset` is **out of scope and stated as out of scope**, for a reason and not a shrug:
`upat.py` frozensets `self.op` (Ops) at `:25`, `self.match_dtype` (DType) at `:36` and
`self.match_tag` (str) at `:43`, so **three element types under one Python type**, and
covering it needs a UNION element type — which is the `Arg` redesign its 19 leaf
constructors exist to avoid. The py side's own answer is already the honest one
(`raw(frozenset)`), and no corpus `UPat` uses the multi-match arm.

**Answer: item 2b is a TYPE CHANGE, one variant, in `uop/ops.bend` — not this unit's file,
and not landable here.**

### 3c. WHAT ITEM 2 ACTUALLY GATES — and it is narrower than the brief says

**MEASURED: item 2 gates ONE COLUMN of ONE of the three ops, and gates none of their
settling.** `fold.bend`'s `OpsPYLITERAL -> late()` arm does not read the arg, so
**PYLITERAL already read `4:void 1:R` at the BEFORE pin** (`patir-run0.txt`) — CSHAPE's own
Q4 said `settled=True`. So `AOpLit` is needed for the `arg` column to COMPARE, not for the
op to settle. The three ops are gated by item 1 alone, and item 1 is now fixed.

---

## 4. WHICH OF THE THREE OPS SETTLE

| op | before | after | why |
|---|---|---|---|
| `CUSTOM` | `1:? 1:?` | **`4:void 1:R`** | item 1, `fold.bend:2364` |
| `CUSTOMI` | `1:? 1:?` | **`4:void 1:R`** | item 1, `fold.bend:2365` |
| `PYLITERAL` | `4:void 1:R` | `4:void 1:R` | **already settled** by `late()` (`fold.bend:2278`); never was gated by item 1 |

The `AND` root stays `?` — see §5.

---

## 5. THE CORPUS, BEFORE AND AFTER, AGAINST 77, BOTH SIDES, WITH THE SPLIT

`corpus-run1.txt`, `corpus-run2.txt`, **byte-equal** (`76d22d5b7a9822baf09dfc526a3367ad`),
so the run is deterministic and not a single lucky sample.

```
denominator (measured len(list(Ops)))         : 77
graphs   live                                 : 25      (+1 patir = ceiling)
reached PY      live 61    +patir 4     union 64
reached BEND    live 61    +patir 4     union 64
reached BOTH    live 61    +patir 64
py-only         live []    +patir []
bend-only       live []    +patir []
NEITHER         live 16    +patir 13
  ['CUSTOM_FUNCTION','GETADDR','INS','MSELECT','MSTACK','MULACC','PROGRAM',
   'REWRITE_ERROR','SOURCE','STAGE','THREEFRY','UNSHARD','WMMA']
ledger live PY   {z:2, y:2, q:1, E:1, ?:1, R:43}
ledger live BEND {z:1, y:1, q:1, ?:1, R:21}
```

**BLAST RADIUS: 0 of 624 rows moved, 0 of 22 graphs [SUPERSEDED: was 25; see CORPUS.md]' row counts moved**, diffed by WHOLE
`name=value` LINE. And `fold.bend`'s OWN 335-line row output is **byte-identical** before
and after (`foldrun-BEFORE.txt` / `foldrun-AFTER.txt`).

**The live corpus is UNCHANGED at 61/77 both sides.** `patir` still cannot be added to it —
the `GRAPHS` dict and the dispatch arm are `graphcmp.py`'s and `graphcmp.bend`'s.

### THE VERDICT, which is the headline and not the census

Same py rows, same probe (`ns-patir.bend`), `fold.bend` the only thing that moved:

```
VERDICT BEFORE: DISAGREE -- 9 field mismatches (of 24 field-records; 15 agree)
VERDICT AFTER : DISAGREE -- 5 field mismatches (of 24 field-records; 19 agree)
   nodes 1 CUSTOMI, 2 PYLITERAL, 3 CUSTOM : dtype and shape now AGREE
   node 4 AND                           : dtype+shape still disagree, `?` vs `R`
   3 of the remaining 5                  : the `arg` column (item 2, the differ's)
   with P1's one arm (§3a)               : 3 mismatches
   with P1 AND the `AOpLit` type change : 2 mismatches, and BOTH are upstream's assert
```

**Read the verdict, not `64/64/64` with `py-only=[]`.** The census still counts
`CUSTOM`/`CUSTOMI`/`PYLITERAL` as REACHED on both sides, and it still would on the
BEFORE pin's arm for `PYLITERAL` alone, because it counts the `op` column, which is
printed even when dtype AND shape both read `?`. `?=1` on the bend side is the AND and
nothing else — item 1 took the bend ledger's `?` from 3 to 1.

---

## 6. THE THIRD BLOCKER: UNTOUCHED, AND THE REFUSAL IS THE RESULT

**`AND`'s shape has no correct answer on either side, and I did not widen it.**

* py side: `ops.py:444` `assert len(self.src) > 0 and all(x is not None for x in
  input_shapes)` **fires** — upstream calls the graph invalid. Under the widening it prints
  `R`.
* port side: `all_shapes` (fold.bend:907) refuses the same list, the node has no `Derived`,
  and the differ prints `?`.
* `R` would claim a shape upstream does not claim. **2 of the 5 remaining field mismatches
  are exactly this, and they are upstream's answer, not a port gap.**

The `AssertionError` widening this corpus needs **in order to EMIT the py rows at all** is
re-derived in `ns-corpus.py` as CSHAPE's **W1s** (`except RuntimeError`, plus
`AssertionError` whose message starts `"None input shape not supported for "`, nothing
else — so `ops.py:438`/`:137`/`:141`, which are WRONG FIXTURES, still refuse). **It is an
in-process monkeypatch and nothing on disk carries it.** It is needed to run §5's verdict
and is **not** part of this fix.

---

## 7. RULES (fresh prefix `NON-`, append-only)

* **NON-1. `None` and `None{}` are TWO facts and there is no site where the first means
  the second.** Ten sites in the CUSTOM arm's neighbourhood (`ops.py:336, 340, 349, 371,
  372, 374, 375, 399, 432, 455`) answer `None` and **every one means "no shape"**; the
  outer `None` in `fold.bend` means "this file produced no `Derived`" and has no upstream
  counterpart. The differ already spent letters on the distinction (`R` vs `?`), so the
  ladder must not collapse them again. **A `Maybe` in a port's fold is not
  automatically upstream's `|None`; check which of the two it is before matching on it.**
* **NON-2. THE PORT ALREADY HAD THE ANSWER ON ITS OWN OP.** `OpsPYLITERAL -> late()`
  (`fold.bend:2278`) rendered `4:void 1:R` from `ops.py:375`'s identical `return None`,
  while `CUSTOM`/`CUSTOMI` rendered `1:? 1:?` from `ops.py:371-372`'s identical `None`.
  **Two ops, one upstream rule, two port answers — and that is the cheapest possible proof
  that the arm is a missing arm rather than a missing capability.** Look for the sibling
  that already answers before calling anything unreachable.
* **NON-3. `if x: return None` THEN `... if xs else None` IS TWO LINES BECAUSE THE FIRST
  ONE IS CHECKED FIRST, AND THE ORDER IS THE WHOLE ARM.** `ops.py:371` before `:372`:
  measured, a void `CUSTOM` over a SHAPED src has `_shape = None`, not `(2,)`. A fix that
  arms "no shape" without arming the order answers the wrong thing on the void-with-srcs
  graph, and no all-same fixture can see it.
* **NON-4. A MISSING ARM AND A MISSING CONSTRUCTOR LOOK IDENTICAL FROM THE OUTPUT AND NEED
  OPPOSITE FIXES.** `n(` vs `in(` is one line in `carg`; `OADD` vs `rd(OADD,i0)` is a hole
  in `Arg` that no arm can fill. **Separate them by asking the compiler**: a probe that
  passes a bare `Op` where an `Arg` is wanted fails with `expected : O.Arg / observed :
  O.Op`, which is a TYPE claim, where a spelling question has no such witness. `Arg` has 19
  constructors and TWO hold an `Op` and both PAIR it.
* **NON-5. "IT GATES THE OP" AND "IT GATES THE COLUMN" ARE DIFFERENT CLAIMS.**
  `PYLITERAL`'s arm does not read its arg, so it settled BEFORE any of this. Measure the
  settle flag before attributing an op to a blocker — a blocker that is claimed to gate
  three ops and actually gates one column of one of them gets the same number and none of
  the credit.
* **NON-6. A BASELINE TAKEN FROM A FILE YOU HAVE ALREADY CHANGED IS A CLAIM UNTIL ITS MD5
  IS CHECKED.** Reverse the edit, print the md5, compare against the pin. This unit's
  reversal reproduced `e372ca226461fe2295b49a9990db0165` exactly, and that is the only
  reason the two verdicts above are attributable to `fold.bend` and to nothing else.
* **NON-7. A SEPARATOR INSIDE YOUR OWN ROW IS A SEPARATOR YOU MUST ESCAPE.** A baseline
  written as `graph + ",".join(rows)` and read back with `split(",")` shredded **2230 rows
  into 611 fragments** and reported **every one of 24 graphs** as having moved its row
  count. That is a blast radius of 611 on a change that moved **0**. A row's own text
  contains commas — `P(i0,Df32,i12,…)`, `rg(i0,XDEVICE,n(i0))` — so one row per line is
  the format, and a harness that cannot parse its own baseline will report a huge diff
  that looks exactly like a plant.
* **NON-8. `--check-only`'s `ALL PROOFS CHECK` IS NOT A GATE AND THE PROBE IS.** The
  three insertions typechecked on the first `--check-only` run and the arm was still wrong
  in the first version (two Bend rejects: a match on a value computed from a parameter, and
  a match on a call). `ALL PROOFS CHECK` also passes an EMPTY file. What settled it was
  eight graphs whose `settled` flag and rendered rows are the answer.

---

## 8. WHAT I DID NOT FIX

* **`graphcmp.py`'s missing CUSTOM/CUSTOMI arm (§3a)** — another unit's file. **One line**,
  measured inert on the live corpus and worth **2 of the 5** remaining field mismatches.
  Recommend: `if op in (Ops.CUSTOM, Ops.CUSTOMI): return f"in({bstr(x[0])},{dt(x[1])})"`
  before the `return _carg(x)` fallthrough in `carg` (graphcmp.py:487). Also add `"n("` to
  `COMPOSITE` if the intent is that the generic tuple grammar is a composite form.
* **`O.Arg`'s missing bare-`Op` variant (§3b)** — `uop/ops.bend` is not this unit's.
  Recommend `AOpLit{op: Op}` plus the matching `argstr` arm, AND the correction of
  `ops.bend:1032`'s `ATuple  ... PYLITERAL arg` line, which `tinygrad/uop/__init__.py:101`
  contradicts. `frozenset` literals deliberately left uncovered; see §3b for why.
* **`fold.bend`'s `case O.OpsSTAGE{}: None{}`** — `ops.py:377-379`'s
  `tuple([int(r.vmax+1) for r in self.src[1:]]) + self.src[0].shape` still needs `vmax`
  (`_min_max`). Untouched.
* **`fold.bend`'s `case O.OpsUNSHARD{}: None{}`** — `ops.py:432`'s movement arm, needs
  `vmax` and an `arg.index` search. Untouched.
* **`tinygrad/uop/ops.py:444`'s assert and `fold.bend:907`'s `all_shapes`** — untouched by
  design, §6.
* **`patir` added to `GRAPHS`** — needs `graphcmp.py`'s dict and `graphcmp.bend`'s dispatch
  arm. Not landed, so the live corpus stays 61/77.
* **`.agents/slop/substrate-check.sh`** — **it does not run**: `syntax error near unexpected
  token 'done'` at line 245, i.e. another unit is mid-edit. I substituted a direct
  `--check-only` pass on `fold.bend` plus six importers
  (`mixin/elementwise`, `schedule/rangeify`, `renderer/cstyle`,
  `codegen/late/linearizer`, `tensor`, `mixin/gradient`) — all `ALL PROOFS CHECK`, plus the
  25-graph census through `graphcmp.bend`, which imports `fold.bend` and is an end-to-end
  signal `--check-only` is not. **Reported, not edited.**
* **`.agents/slop/cshape/**` and `.agents/slop/graphcmp*`** — read only. `graphcmp.py`'s
  md5 is the pin CSHAPE recorded and did not move under this unit.
* **Nothing committed.**