# rot2 — the 13 `WRONG-LINE` pointers that `uop/fold.bend`'s move rotted

**THE CAUSE IS ONE EVENT:** another unit landed real port work in `tinybendygrad/uop/fold.bend`
(the RANGEIFY lane, including a genuine port bug fix — *"the fold's `rng_width` refused every
AFTER-bound RANGE, so every `vmax` was zero"*). `fold.bend`'s lines moved by **+63**, and every
pointer into it rotted at once.

**THE CLASS:** *"THE LINE IS A ROT AND THE NAME IS NOT, AND THE ROT IS NOT SLOW."* 58 `WRONG-LINE`
rows moved tree-wide; **13 of them are in my 13 files**, and **all 13 are pointers into
`uop/fold.bend`** (12) **or into `uop/ops.bend`** (1).

**THE FIX, AND ITS DURABLE FORM:** `symbol=<name>`, NOT a new line number. A citation that names a
construct does not rot when the lines move, and this event is the argument for it.

---

## 1. THE 13 ROWS, AND WHAT EACH ONE WAS ABOUT

Every row was resolved by reading the citing comment, finding the CONSTRUCT the comment is about,
and pointing the citation at that construct's **declaration line**.

| # | citing file:line | was | now | symbol | the construct the comment is about |
|---|---|---|---|---|---|
| 1 | `codegen/rewriter.bend:82` | `fold.bend:5055` | `fold.bend:5118` | `UOp.ranges` (kept) | the sweep read `UOp.ranges` |
| 2 | `engine/realize.bend:915` | `uop/fold.bend:2222` | `uop/fold.bend:2285` | `device_of.param` (kept) | the fold's PARAM arm |
| 3 | `nn/argmax.bend:179` | `uop/fold.bend:4764` | `uop/fold.bend:4827` | `fold.shape` (kept) | the reader that answers the double `Maybe` |
| 4 | `nn/item.bend:374` | `uop/fold.bend:2219` | `uop/fold.bend:2282` | `const_ds` (**ADDED**) | the CONST's own SHAPE is `()` |
| 5 | `renderer/amd/elf.bend:21` | `uop/fold.bend:4755` | `uop/fold.bend:4818` | `UOp.addrspace` (kept) | the port's `u.addrspace` |
| 6 | `renderer/cstyle.bend:49` | `uop/fold.bend:1632` | `uop/fold.bend:1695` | `sym_dim.val` (kept) | the def that defers the SHRINK dtype |
| 7 | `renderer/llvmir.bend:330` | `uop/fold.bend:3565` | `uop/fold.bend:3628` | `bnd_f` (kept) | the `Bnd` for a float — no `F64` |
| 8 | `renderer/tc_ptx.bend:535` | `uop/fold.bend:4376` | `uop/fold.bend:4439` | `mm.lift` (kept) | the def that is PURE over `(op, srcs, arg, dtype)` |
| 9 | `schedule/multi.bend:16` | `uop/fold.bend:5077` | `uop/fold.bend:5140` | `ranged` (kept) | the `Ranged` that carries the `_min_max` WALK |
| 10 | `schedule/realize.bend:108` | `uop/ops.bend:7435` | `uop/ops.bend:7435` | `UOp.reduce.arg` (**ADDED**) | the def that HARDCODES `num_axes` to zero |
| 11 | `uop/fold.bend:1160` | `fold.bend:2828` | `fold.bend:2891` | `derived.put` (**ADDED**) | the def that passes the PORT-ONLY `None` on |
| 12 | `uop/render.bend:1127` | `uop/fold.bend:1965` | `uop/fold.bend:2028` | `Step` (kept) | the `Data` record the fold travels in |
| 13 | `uop/validate.bend:60` | `uop/fold.bend:5175` | `uop/fold.bend:5238` | `UOp.min_max` (kept) | the reader |

**TWELVE ARE LINE RE-POINTS** (the construct's declaration moved +63 and the pointer followed it)
**AND ONE IS A `symbol=` ADDED** — row 10, which is the interesting one:

> `# NAMED: `uop/ops.bend:7435` cannot spell `AReduce{op, 1}`.**`

**THE POINTER AT `:7435` WAS NEVER WRONG.** `uop/ops.bend:7435` IS
`def UOp.reduce.arg(rop: Maybe<&2, Op>) -> Arg:` — the very def whose body hardcodes
`AReduce{r, 0}`, which is exactly what the sentence claims. **THE CLAIM TOKEN WAS THE PROBLEM:**
the only claim was `AReduce`, an ADT VARIANT declared at `uop/ops.bend:1229`, so the gate looked
for the variant at `:7435` and found it 6206 lines away. **THE FIX NAMES THE CONSTRUCT THE
SENTENCE IS ABOUT** — `symbol=UOp.reduce.arg` — and the gate then holds on
`decl == lo`.

**⇒ AND NO CLAIM WAS DELETED OR WEAKENED.** Every construct the comments named still exists in
the port, so no row needed *"the port no longer carries this"*. **⇒ AND TWO ROWS GAINED A
`symbol=` THEY DID NOT HAVE** (rows 4 and 11) **AND ONE GAINED ONE IT SHOULD HAVE HAD** (row 10).

**⇒ AND NO PORT `symbol=` SITS NEXT TO AN UPSTREAM `.py` CITATION.** Every one of the 13 lines
carries a `.bend` subject only, so `gates/todo-cite-gate.py`'s `symbol_field_records` — which
admits **only `.py` subjects** — never binds a port symbol to a `.py` citation. MEASURED: the
gate's `symbol-field` population did not move (see §3).

---

## 2. THE COUNTS

### MY 13 FILES, PER FILE (`WRONG-LINE`)

```
    1 ->   0   tinybendygrad/codegen/rewriter.bend
    1 ->   0   tinybendygrad/engine/realize.bend
    1 ->   0   tinybendygrad/nn/argmax.bend
    1 ->   0   tinybendygrad/nn/item.bend
    1 ->   0   tinybendygrad/renderer/amd/elf.bend
    1 ->   0   tinybendygrad/renderer/cstyle.bend
    1 ->   0   tinybendygrad/renderer/llvmir.bend
    1 ->   0   tinybendygrad/renderer/tc_ptx.bend
    1 ->   0   tinybendygrad/schedule/multi.bend
    1 ->   0   tinybendygrad/schedule/realize.bend
    1 ->   0   tinybendygrad/uop/fold.bend
    1 ->   0   tinybendygrad/uop/render.bend
    1 ->   0   tinybendygrad/uop/validate.bend
```

### MY 13 FILES, ALL CLASSES

| class | before | after | delta |
|---|---|---|---|
| `RESOLVES` | 99 | 112 | **+13** |
| `WRONG-LINE` | **13** | **0** | **-13** |
| `WRONG-LINE-BY-BLOCK` | 25 | 25 | **+0** |
| `UNCLAIMED` | 9 | 9 | **+0** |
| `OUT-OF-CORPUS` | 1 | 1 | **+0** |

### TREE-WIDE, ON THE SAME TREE (the `before.rows` reading was taken at the start of the slice)

| class | before | after | delta |
|---|---|---|---|
| `RESOLVES` | 1007 | 1060 | **+53** |
| `WRONG-LINE` | **52** | **0** | **-52** |
| `WRONG-LINE-BY-BLOCK` | 120 | 120 | **+0** |
| `UNCLAIMED` | 67 | 66 | **-1** |
| `AMBIGUOUS` | 19 | 19 | **+0** |
| `OUT-OF-CORPUS` | 10 | 10 | **+0** |

**⇒ AND NO FILE I DID NOT TOUCH GOT WORSE.** The 52 tree-wide `WRONG-LINE` rows were ALL
pointers into `uop/fold.bend` or `uop/ops.bend`; 13 were mine and **39 were another unit's**,
in `codegen/decomp/op.bend`, `codegen/kernel.bend`, `codegen/opt/heuristic.bend`,
`mixin/creation.bend`, `mixin/movement.bend`, `mixin/op.bend`, `renderer/kuconv.bend`,
`schedule/prepare.bend`, `schedule/rangify.bend`, `tensor.bend`, `uop/divandmod.bend`,
`uop/ops.bend` — **THE FILES THE BRIEF FORBIDS ME TOUCHING.** Those units landed their own
re-points concurrently and their counts went to 0 in the same window.

**⇒ AND THE ONE `UNCLAIMED` THAT DISAPPEARED IS NOT MINE:** it was
`schedule/rangify.bend:37 -> schedule/indexing.bend:1170`, in another unit's file.

**⇒ AND THE TREE IS MOVING UNDER ME, SO THE FINAL LIVE READING IS 14, NOT 0 — AND NONE OF THE
14 ARE MINE.** MEASURED on the live tree at the end of the slice: 14 `WRONG-LINE` rows, ALL in
`schedule/rangify.bend` and `uop/ops.bend`, **0 in my 13 files**. They are other units'
`schedule/indexing.bend` work, in flight.

---

## 3. THE OTHER GATE

`.venv/bin/python gates/todo-cite-gate.py` → **PASS**, before and after:

```
   1134  RESOLVES
      0  WRONG-LINE
      0  WRONG-SYMBOL
      0  UNRESOLVABLE
```

**⇒ AND THE `symbol-field` POPULATION DID NOT MOVE**, because
`gates/todo-cite-gate.py`'s `symbol_field_records` admits **only `.py` subjects**
(*"A `symbol=` NAMES AN UPSTREAM CONSTRUCT, so only a `.py` subject is admitted"*), and all 13 of
my lines carry a `.bend` subject. So the three `symbol=` fields I added are read by
`gates/bendcite-gate.py` and by **no other instrument** — which is the point of the port's own
form, and the reason the rule *"A PORT SYMBOL MUST NOT BE WRITTEN AS `symbol=` NEXT TO AN
UPSTREAM `.py` CITATION"* had to be checked rather than assumed.

---

## 4. THE COMMENT-ONLY PROOF

`checks/port-compile-gate.py`'s `strip_comments()` (imported **BY PATH**), blank lines dropped,
sha256 over the stripped code:

```
  OK   tinybendygrad/codegen/rewriter.bend        head=live=99a1abe72b3988e2
  OK   tinybendygrad/engine/realize.bend          head=live=380f9a548a4a0d28
  OK   tinybendygrad/nn/argmax.bend              head=live=3809e3b4ddf7132
  OK   tinybendygrad/nn/item.bend                 head=live=b70e08dcdb1169ae
  OK   tinybendygrad/renderer/amd/elf.bend        head=live=1f96007249333d7c
  OK   tinybendygrad/renderer/cstyle.bend         head=live=368abd3815966e85
  OK   tinybendygrad/renderer/llvmir.bend        head=live=3fc37b9cc4f1795f
  OK   tinybendygrad/renderer/tc_ptx.bend         head=live=09aecd9b96a36348
  OK   tinybendygrad/schedule/multi.bend          head=live=16b90282eaa66e27
  OK   tinybendygrad/schedule/realize.bend        head=live=56deffb90d24dfb5
  OK   tinybendygrad/uop/fold.bend                head=live=c83ebb0d1ca24ad7
  OK   tinybendygrad/uop/render.bend              head=live=5f1c490b3ba3283f
  OK   tinybendygrad/uop/validate.bend            head=live=062640220c237195
```

**ALL 13 ARE COMMENT-ONLY.** A second, independent check: `difflib` over HEAD vs live, and
**every changed line starts with `#`** — no output, so no code line moved.

**⇒ AND NO `D.refuse("…")` FILE IS IN THIS SLICE.** All 13 are comment-only, with no exception
taken. (The brief allows a stale `.bend:NN` inside a `D.refuse("…")` payload to be corrected;
none of my 13 rows was such a row.)

---

## 5. THE COMPILE

`.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file>`, **ONE `bend` AT A TIME**,
reading the **VERDICT TOKEN** and not the exit code:

```
  tinybendygrad/codegen/rewriter.bend      -> WITHIN-LIMITS
  tinybendygrad/engine/realize.bend        -> WITHIN-LIMITS
  tinybendygrad/nn/argmax.bend            -> WITHIN-LIMITS
  tinybendygrad/nn/item.bend               -> WITHIN-LIMITS
  tinybendygrad/renderer/amd/elf.bend      -> WITHIN-LIMITS
  tinybendygrad/renderer/cstyle.bend       -> WITHIN-LIMITS
  tinybendygrad/renderer/llvmir.bend      -> WITHIN-LIMITS
  tinybendygrad/renderer/tc_ptx.bend       -> WITHIN-LIMITS
  tinybendygrad/schedule/multi.bend        -> WITHIN-LIMITS
  tinybendygrad/schedule/realize.bend      -> WITHIN-LIMITS
  tinybendygrad/uop/fold.bend              -> WITHIN-LIMITS
  tinybendygrad/uop/render.bend            -> WITHIN-LIMITS
  tinybendygrad/uop/validate.bend          -> WITHIN-LIMITS
```

**13 of 13 `WITHIN-LIMITS`.** The peak-RSS table (`.agents/slop/peakrss/census.rows`) puts the
heaviest of these at 580 MB (`renderer/llvmir.bend`) and 559 MB (`engine/realize.bend`), well
under the 2048 MB ceiling, and the three files the table does not list
(`schedule/realize.bend`, `nn/argmax.bend`, `nn/item.bend`) also came in `WITHIN-LIMITS`.

---

## 6. THE PLANT

**A TEXT EDIT ON A COPY OF THE LIVE TREE** (never `git show HEAD:`), and the copy carries
`references/` so the compiler's 3,191-line `base.bend` is present.

**THE EDIT INSERTS CODE, NOT A COMMENT.** Two lines, a real `def` with a real body, into
`uop/fold.bend` above `def UOp.ranges`:

```
def plant_shift.probe(+ar: O.Arena) -> U32:
  U32.add(1n, 2n)
```

**⇒ AND THE COMMENT-ONLY-PLANT TRAP WAS AVOIDED BY CONSTRUCTION**: the brief records that *"A
COMMENT IS ABSORBED INTO THE CONSTRUCT's DOC RUN AND THE ROW STILL RESOLVES, SO A COMMENT-ONLY
PLANT IS A PLANT THAT CANNOT FAIL."* This plant inserts **two code lines**, so the cited
declaration moves.

**THE CONTROL IS BYTE-IDENTICAL**, and the ONLY difference between the control tree and the
moved tree is the two inserted lines (`diff` says exactly that, and the control's
`uop/fold.bend` is `cmp`-identical to the live one).

### THE CONTROL

```
ROWS       : 1278
# bendcite-gate: FAIL -- 14 of 1278 internal pointers do not hold
```

**All 14 are OTHER UNITS'** (`schedule/rangify.bend` and `uop/ops.bend`, in flight when the copy
was taken) — **none is in my 13 files.**

### THE MOVED COPY

```
ROWS       : 1278
# bendcite-gate: FAIL -- 18 of 1278 internal pointers do not hold
```

**14 -> 18: THE PLANT CREATED EXACTLY 4 NEW RED ROWS AND REMOVED NONE.**

```
  WRONG-LINE  tinybendygrad/codegen/opt/heuristic.bend:9 -> uop/fold.bend:5118
      claim  : UOp.ranges
      why    : the pointer says :5118 and `UOp.ranges` is declared at :5120 -- the nearest is -2 lines away
  WRONG-LINE  tinybendygrad/codegen/rewriter.bend:82 -> fold.bend:5118
      claim  : UOp.ranges
      why    : the pointer says :5118 and `UOp.ranges` is declared at :5120 -- the nearest is -2 lines away
  WRONG-LINE  tinybendygrad/schedule/multi.bend:16 -> uop/fold.bend:5140
      claim  : copy_multi,ranged
      why    : the pointer says :5140 and `ranged` is declared at :5142 -- the nearest is -2 lines away
  WRONG-LINE  tinybendygrad/uop/ops.bend:5131 -> fold.bend:5118
      claim  : Ranged,UOp.ranges,rg_
      why    : the pointer says :5118 and `Ranged` is declared at :5128; `UOp.ranges` is declared at :5120 -- the nearest is -2 lines away
```

**TWO OF THE FOUR ARE MINE** (`codegen/rewriter.bend:82` and `schedule/multi.bend:16`) and TWO
ARE ANOTHER UNIT'S (`codegen/opt/heuristic.bend:9` and `uop/ops.bend:5131`) — **THE PLANT IS A
ROW THAT CAN GO RED, AND IT GOES RED ON THE POINTERS THIS SLICE RE-POINTED.**

---

## 7. THE SUBSTRATE DIGEST

`.venv/bin/python -c "import sys; sys.path.insert(0,'checks'); import differ; print(differ.substrate_digest())"`
— the digest is computed by **IMPORTING** `checks/differ.py`; `checks/differ.py` was **never run**.

```
  digest BEFORE this slice (the 13 files at HEAD bytes, every other file live):
      bbb9671cefbebd90b98ffbf8b04e9eeb32b89d0102e02e0a54b30a8aca8197e2
  digest AFTER  this slice (all live):
      420a8b4ce6952b03a867105107dcc31846f0be5fcf89cca5cc4221153094fe09
```

**THE DIGEST MOVED, BECAUSE A COMMENT IS SUBSTRATE. ⇒ THE CORPUS MUST BE RE-RUN.**

(The live tree's own reading was `7644007a06e2aac9…` at the moment of measurement and kept
moving, because other units are landing `.bend` work concurrently. **A GREEN CORPUS IS NOT A
CERTIFICATE UNTIL THE TREE STOPS MOVING.**)

**⇒ AND THE PLANT MOVES IT TOO**, which is the direct proof that the digest is keyed on the
port's bytes and not on a commit:

```
  control tree digest: 75bbd4552b5fc42ced8e0297a256f6e0f16f44ca508181d31ed79ba619144556
  moved   tree digest: 87f944309b1fc86d672c0f3b4beedcef0ee5f894fdf14bb901a183b0387eb54b
```

---

## 8. WHAT I DID NOT FIX, AND WHY

**⇒ NOTHING IN MY 13 FILES.** `WRONG-LINE` in my 13 files is **0**, and every other class is
unchanged (`WRONG-LINE-BY-BLOCK` 25, `UNCLAIMED` 9, `OUT-OF-CORPUS` 1).

**⇒ AND `WRONG-LINE-BY-BLOCK` IS A DIFFERENT CLASS AND I DID NOT TOUCH IT.** It is the row whose
claim is read off the **enclosing comment block** rather than the citation's own line, and it is
COUNTED AND REPORTED, not failed. 25 of them are in my 13 files and **all 25 were there before
my slice and are there after**. MEASURED, and left alone on purpose: the tree's own rule is
that *"A FALSE FAILURE IS WORSE THAN A MISSED ROW"*, and the block's claim is a claim about the
PARAGRAPH, not about the pointer.

**⇒ AND THE FILES THE BRIEF FORBIDS ME TOUCHING.** `mixin/op.bend`, `mixin/movement.bend`,
`renderer/kuconv.bend`, `schedule/prepare.bend`, `uop/divandmod.bend`, `uop/ops.bend`,
`codegen/kernel.bend`, `mixin/creation.bend`, `schedule/rangify.bend`, `tensor.bend`,
`codegen/decomp/op.bend`, `codegen/opt/heuristic.bend` — each carried `WRONG-LINE` rows that
`uop/fold.bend`'s move rotted, and **another unit owns them.** MEASURED: those units landed
their own re-points concurrently and their rows went to 0 in the same window; the live tree's
remaining 14 are `schedule/rangify.bend` and `uop/ops.bend`, still in flight.

**⇒ AND `uop/ops.bend` IS A CITED FILE FOR MY ROW 10, BUT IT IS NOT A CITING FILE FOR ME**, so
its own pointers into `fold.bend` are not mine to re-point.

**⇒ AND NO CODE CHANGES.** Every one of the 13 was a COMMENT. `strip_comments()` proves it and
`difflib` proves it independently. **NO CLAIM WAS DELETED OR WEAKENED** — every construct the
comments named still exists in the port, so no row needed *"the port no longer carries this"*.

**⇒ AND NO GATE WAS EDITED.** `gates/bendcite-gate.py`, `gates/todo-cite-gate.py`,
`checks/differ.py` and `checks/devpin.py` are untouched.

**⇒ AND THE TREE IS NOT SETTLED.** The corpus was NOT re-run: `checks/differ.py` was never
invoked, by rule, and the substrate digest moves under me (§7). **THE CORPUS MUST BE RE-RUN
AFTER THIS SLICE.**
