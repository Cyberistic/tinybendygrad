# `nn_dot.xshape` IS A HEAD DROP WHERE CPython TAKES A TAIL — THE FIX IS NOT "ONE ARGUMENT"

**HEAD `1e0a0a19a9b996d8e73e988e9929906c5ba65180` (`1e0a0a19a`, 2026-10-20T19:21:33+03:00).
MEASURED 2026-10-20T16:22Z–16:23Z. `tinybendygrad/nn/layers.bend` WAS BYTE-IDENTICAL
TO THE SCRATCH "BEFORE" COPY AT THAT HEAD (`diff -q` → identical), SO `dot.diff` APPLIES
CLEANLY TO IT (`patch -p1 --dry-run` → rc=0).**

THE PATCH IS `dot.diff`. IT IS **NOT** LANDED — I DID NOT EDIT ANY FILE OUTSIDE
`.agents/slop/dotfix/`. THE ORCHESTRATOR LANDS IT.

---

## 1. THE DEFECT, CONFIRMED

### CPython — `tinygrad/mixin/op.py:386-392` (the vendored upstream, `002630241`)

```python
    x, dx, dw = self, self.ndim, w.ndim
    if not (dx > 0 and dw > 0): raise RuntimeError(f"both tensors need to be at least 1D, got {dx}D and {dw}D")
    if x.shape[-1] != w.shape[axis_w:=-min(w.ndim,2)]: raise RuntimeError(f"cannot dot {x.shape} and {w.shape}")
    x = x.reshape(*x.shape[0:-1], *[1]*min(dx-1, dw-1, 1), x.shape[-1])
    w = w.reshape(*w.shape[0:-2], *[1]*min(dx-1, dw-1, 1), *w.shape[axis_w:]).transpose(-1, axis_w)
    return (x*w).sum(-1, dtype=dtype).cast(least_upper_dtype(x.dtype, w.dtype) if dtype is None else dtype)
```

`x.shape[0:-1]` KEEPS EVERY DIM **BUT THE LAST**. IT IS A **TAIL** SLICE.

> **THE `axis_w` SUBTLETY, WHICH THE PORT'S OWN HEADER COMMENT GETS WRONG.** THE PORT'S
> COMMENT AT `layers.bend:278-281` SAYS *"`axis_w = -w.ndim if w.ndim > 1 else 0` (:383)"*.
> THE VENDORED UPSTREAM SAYS `-min(w.ndim, 2)`, AND IT HAS SINCE AT LEAST
> `86c4f1343^` (THE RE-VENDOR'S PARENT) — `git show 86c4f1343^:tinygrad/mixin/op.py` HAS
> THE **IDENTICAL** `dot` BODY, SO THIS IS NOT A RE-VENDOR DRIFT; THE COMMENT WAS STALE
> WHEN WRITTEN.
>
> AND THE GUARD LINE IS NOT WHAT IT LOOKS LIKE. `w.shape[axis_w:=-min(w.ndim,2)]` IS A
> **NAMED EXPRESSION** IN A SLICE: PYTHON'S GRAMMAR MAKES `axis_w := -min(w.ndim,2)` THE
> SLICE'S **LOWER BOUND** WITH NO UPPER BOUND, SO THE GUARD READS `w.shape[axis_w]` — **A
> SINGLE DIM** — NOT `w.shape[axis_w:]`. MEASURED, `.venv/bin/python`:
> `w.shape[axis_w:=-min(w.ndim,2)]` → `2` (not `(2, 2)`), and `axis_w` afterwards → `-2`.
> **LINE 391 IS A DIFFERENT EXPRESSION** — `axis_w` IS A PLAIN NAME THERE, SO
> `w.shape[axis_w:]` **IS** A SLICE AND ANSWERS THE LAST `min(dw,2)` DIMS. THE TWO ARE
> NOT THE SAME SHAPE AND THE PORT MUST SPELL BOTH.

### THE PORT — `tinybendygrad/nn/layers.bend:290-294`

```bend
# `x.shape[0:-1]` ++ `[1]*k` ++ `[x.shape[-1]]` -- :387.
def nn_dot.xshape(+xs: List<&2, U32>, k: U32) -> List<&2, U32>:
  List.append(&2, U32, List.concat(&2, U32,
    [List.drop(&2, U32, xs, 1n), H.make_tuple_rep(1, k)]),
    [Maybe.default(&2, U32, List.last(&2, U32, xs), 0)])
```

`List.drop(xs, 1n)` IS A **HEAD** DROP. **CONFIRMED.**

---

## 2. `List.drop`'s SEMANTICS, QUOTED — IT IS A HEAD DROP, AND **NO TAIL-DROP HELPER EXISTS**

`references/bend/bend2/base.bend:984-1000` (THE PRELUDE `import Base` RESOLVES TO):

```bend
def List.take(a, -A: Kind(a), xs: List<a, A>, n: Nat) -> List<a, A>:
  match xs n:
    case Nil{} _:
      Nil{}
    case h <> t 0n:
      Nil{}
    case h <> t 1n+p:
      h <> List.take(a, A, t, p)

def List.drop(a, -A: Kind(a), xs: List<a, A>, n: Nat) -> List<a, A>:
  match xs n:
    case Nil{} _:
      Nil{}
    case h <> t 0n:
      h <> t
    case h <> t 1n+p:
      List.drop(a, A, t, p)
```

`List.drop` RECURSES ON THE **TAIL** (`List.drop(a, A, t, p)`) — IT CONSUMES THE HEAD AND
KEEPS THE REST: IT ANSWERS **`xs[n:]`**. `List.take` KEEPS THE HEAD AND ANSWERS
**`xs[:k]`**. THEY ARE COMPLEMENTS.

**MEASURED** (`.agents/slop/dotfix/sem.bend`, `./bin/bend`, 0.1 s, ONLY `import Base`):

```
xs            = 2,4,3,
take(xs,0)    =            take(xs,1)    = 2,          take(xs,2)    = 2,4,       take(xs,3)    = 2,4,3
drop(xs,0)    = 2,4,3,     drop(xs,1)    = 4,3,        drop(xs,2)    = 3,         drop(xs,3)    =
length(xs)    = 3          Nat.sub(0,1)  = 0           Nat.sub(3,1)  = 2
```

**`drop(xs,1)` = `[4,3]`. IT IS A HEAD DROP. THERE IS NO `List.drop_last`, NO
`List.drop_tail`, NO `List.rdrop` IN THE PRELUDE, AND NO TAIL-DROP HELPER ANYWHERE IN
`tinybendygrad/`** (THE ONLY TAIL-DROP IDIOMS IN THE TREE ARE `uop/fold.bend`'s
`take_n`/`drop_last` ON `O.Sint`, `renderer/isa/x86.bend`'s `Asm.droplast` ON A STRING,
AND `runtime/support/system.bend`'s `pcibus[:-1]` ON A STRING).

### **SO THE PRIOR UNIT'S "THE FIX IS ONE ARGUMENT" IS REFUTED.**

`List.drop` DROPS FROM THE FRONT **FOR EVERY ARGUMENT**. NO VALUE OF `n` MAKES IT A TAIL
DROP. THE FIX IS **NOT** AN ARGUMENT — IT IS A **DIFFERENT HELPER**.

THE PRIOR UNIT'S CONTROL WAS, IN ITS OWN REPORT'S WORDS (`resnetwork/REPORT.md:180`),
**`| U1 | the same reshape with `[2,1,3]` |`** — I.E. THE WHOLE TERM WAS REPLACED BY THE
LITERAL, NOT AN ARGUMENT CHANGED. THE REPORT'S "REPRODUCED BY CHANGING ONE ARGUMENT"
IS A MIS-DESCRIPTION OF "ONE TERM".

### THE TREE'S OWN IDIOM FOR A TAIL SLICE (SO THE FIX IS NOT INVENTED HERE)

- `tinybendygrad/uop/fold.bend:480-486` — **THE SAME IDIOM, ON `O.Sint`**:
  ```bend
  # `xs[n:]` and `xs[:n]` -- `List.drop` and `List.take`
  def take_n(xs: List<&2, O.Sint>, +n: Nat) -> List<&2, O.Sint>:
    List.take(&2, O.Sint, xs, n)

  # `a.shape[:-1]`, and a `Sized` because WMMA's operands feed the same broadcast walk
  # that `_align_left` feeds.
  def drop_last(+x: Sized) -> Sized:
    sized(take_n(Sized.s(x), Nat.sub(Sized.n(x), 1n)))
  ```
- `tinybendygrad/runtime/support/system.bend:1540-1543` — `pcibus[:-1]` → `String.take(pcibus, len - 1)`.
- `tinybendygrad/renderer/isa/x86.bend:1473-1477` — `Asm.droplast` → reverse, drop the head, reverse back.

**`List.take(xs, Nat.sub(len, n))` IS THE TREE'S OWN SPELLING.** `Nat.sub` SATURATES AT 0
(`base.bend:657-664`, MEASURED `Nat.sub(0,1) = 0`), SO A SHAPE SHORTER THAN `n` ANSWERS
`Nil{}` — WHICH IS WHAT `xs[0:-2]` ANSWERS FOR A 1-D OR A 2-D `w`.

---

## 3. THE FIX (`dot.diff`)

```bend
# `xs[0:-n]` -- CPython's TAIL SLICE, WHICH `List.drop` CANNOT SPELL.
# ... (the full comment is in the diff) ...
def nn_tail_drop(+xs: List<&2, U32>, n: Nat) -> List<&2, U32>:
  List.take(&2, U32, xs, Nat.sub(List.length(&2, U32, xs), n))

# `x.shape[0:-1]` ++ `[1]*k` ++ `[x.shape[-1]]` -- :387.
def nn_dot.xshape(+xs: List<&2, U32>, k: U32) -> List<&2, U32>:
  List.append(&2, U32, List.concat(&2, U32,
    [nn_tail_drop(xs, 1n), H.make_tuple_rep(1, k)]),
    [Maybe.default(&2, U32, List.last(&2, U32, xs), 0)])
```

**TWO LINES OF CODE CHANGED, ONE DEF ADDED.** `nn_dot.xshape`'s **SIGNATURE IS UNCHANGED**
(`(+xs: List<&2, U32>, k: U32) -> List<&2, U32>`), SO NOTHING DOWNSTREAM CAN BREAK ON IT.

**WHY THE HELPER IS `+xs` AND NOT `xs`:** BEND'S BINDERS ARE LINEAR. A PLAIN BINDER IS
**LONE** — CONSUMED **EXACTLY ONCE** — AND `List.length` **AND** `List.take` BOTH CONSUME
THE LIST. THE FIRST ATTEMPT (`xs: List<&2, U32>`) FAILED THE CHECKER:

```
- expected : xs
- observed : xs (consumed more than once)
Location: nn_tail_drop
```

`+xs` RELAXES THE **ELEMENTS** TO *MANY* (`&2`), WHICH IS WHAT LETS THE LIST BE READ TWICE.
`references/bend/bend2/bend.ts:76` — `Plus | "+" D ("<" [A ","?] ">")? | D<&2.., A..>` — AND
`bend.ts:197` — *"&1 (Lone) or &2 (Many); Type is Kind(&1), Data is Kind(&2)"*.
**`./bin/bend --check-only` ON THE SCRATCH FIXED TREE: `ALL PROOFS CHECK`.**

**WHY THE HELPER IS FILE-LOCAL IN `layers.bend` AND NOT HOISTED:** `uop/fold.bend`'s
`take_n`/`drop_last` ARE THE SAME IDIOM BUT ON `O.Sint`, AND THE PRELUDE'S `List.take` IS
**ALREADY PARAMETRIC IN THE ELEMENT TYPE** (`def List.take(a, -A: Kind(a), xs: List<a, A>, n: Nat)`),
SO A THIRD, GENERIC COPY WOULD BE A SECOND SPELLING OF SOMETHING THE STDLIB ALREADY
SPELLS. `layers.bend` HAS EXACTLY TWO `List<&2, U32>` TAIL-SLICE SITES, BOTH IN `nn_dot`.

---

## 4. THE PROOF — `cases.rows`

EVERY CELL IS AN INSTRUMENT READ, NOT A TRANSCRIPTION. RE-RUN EVERYTHING WITH:

```
sh .agents/slop/dotfix/collect.sh
```

WHICH RUNS, IN ORDER: `.venv/bin/python cpython_oracle.py`, `./bin/bend probe.bend`,
`./bin/bend probe_fix.bend`, `./bin/bend scratch/nn/layers.bend`,
`./bin/bend scratchfix/nn/layers.bend`, AND THEN `mkrows.py` WRITES `cases.rows`.

| case | x · w | CPython x' | PORT BEFORE x' | PORT AFTER x' | CPython result | PORT BEFORE | PORT AFTER |
|---|---|---|---|---|---|---|---|
| A | (2,3)·(3,4) | `(2,1,3)` | `3,1,3` ✗ | `2,1,3` ✓ | `(2,4)` | `<EMPTY>` | `2,4` ✓ |
| B | (2,4,3)·(3,4) | `(2,4,1,3)` | `4,3,1,3` ✗ | `2,4,1,3` ✓ | `(2,4,4)` | `<EMPTY>` | `2,4,4` ✓ |
| C | (8,64,7,7)·(7,16) | `(8,64,7,1,7)` | `64,7,7,1,7` ✗ | `8,64,7,1,7` ✓ | `(8,64,7,16)` | `<EMPTY>` | `8,64,7,16` ✓ |
| D | (2,3)·(3,) | `(2,3)` | `3,3` ✗ | `2,3` ✓ | `(2,)` | `<EMPTY>` | `2` ✓ |
| E | (2,3,4)·(3,4,5) | `(2,3,1,4)` | `3,4,1,4` ✗ | `2,3,1,4` ✓ | CPython **raises** `IndexError` | `<EMPTY>` | `<EMPTY>` |
| F | (2,3,4)·(3,4,1) | `(2,3,1,4)` | `3,4,1,4` ✗ | `2,3,1,4` ✓ | CPython **raises** `IndexError` | `<EMPTY>` | `<EMPTY>` |
| G | (3,3,4)·(3,4,1) | `(3,3,1,4)` | `3,4,1,4` ✗ | `3,3,1,4` ✓ | `(3,3,1)` | `<EMPTY>` | `<EMPTY>` |

`<EMPTY>` IS WHAT THE PORT ANSWERED — AN EMPTY SHAPE READ, NOT A MISSING ROW.

**THE PORT'S OWN ROWS IN `tinybendygrad/nn/layers.bend`** (THE FILE'S OWN ASSERTIONS):

| row | BEFORE | AFTER | want |
|---|---|---|---|
| `dot_2d` | `<EMPTY>` | **`2,4`** | `(2,4)` |
| `dot_1d` | `<EMPTY>` | **`2`** | `(2,)` |
| `linear` | `<EMPTY>` | **`2,10`** | `(2,10)` |
| `linear_nobias` | `<EMPTY>` | **`2,10`** | `(2,10)` |
| `dbg_dot_sig` | `n=20 op=Ops.CAST` | **`n=20 op=Ops.REDUCE`** | (empty in the file) |

**THE PRIOR UNIT'S CONTROL IS NOW PRODUCED BY `nn_dot` ITSELF.** THEY MEASURED
`n=20 op=Ops.REDUCE` ON A **HAND-BUILT** CHAIN (THE FILE'S OWN `fold_*` ROWS); AFTER THE
FIX, `nn_dot`'s **OWN** ROOT OP IS `Ops.REDUCE` WITH `n=20`. BEFORE THE FIX `nn_dot`'s OWN
ROOT WAS `Ops.CAST` OVER A `PERMUTE` — THE CAST SAT ON TOP OF A GRAPH WHOSE SHAPE DID NOT
FOLD.

**WHY IT WAS EMPTY AND NOT WRONG:** `x(2,3)` HAS PRODUCT 6; THE WRONG TARGET `3,1,3` HAS
PRODUCT 9. THE RESHAPE'S PRODUCT DOES NOT MATCH, THE FOLD REFUSES, AND EVERY SHAPE READ
OF THE DOT GRAPH IS EMPTY. **THE EMPTY READ WAS THE SYMPTOM; THE WRONG TARGET WAS THE
CAUSE.**

**THE ROWS THAT DID **NOT** MOVE, AND WHY (SO NOBODY READS THIS PATCH AS A CONV2D FIX):**
`conv_p1_s1`, `conv_p0_s1`, `conv_p1_s2`, `conv_seq`, `conv_bias` ARE STILL EMPTY, AND
`fold_smk` (THE **KEEPDIM** SUM) IS STILL EMPTY. THOSE ARE THE **OTHER** DEFECTS — THE
`nn_expand`/`cr_expand` ONE AND THE `mo_at` ONE — AND THE PRIOR UNIT'S REPORT NAMES BOTH.

---

## 5. INDEPENDENCE OF THE `mo_at` / `mo_reduced` FIXES IN FLIGHT — **YES, INDEPENDENT, BOTH WAYS**

**MEASURED, NOT ARGUED:** THE AFTER TREE'S `tinybendygrad/mixin/op.bend` IS **BYTE-IDENTICAL**
TO THE REAL ONE (`diff -q` → identical). **`mo_at` (`mixin/op.bend:316`) AND `mo_reduced`
(`mixin/op.bend:876`) ARE THEREFORE STILL EXACTLY AS DEFECTIVE AS BEFORE — AND `dot_2d`
NOW READS `(2,4)`, WHICH IS CPYTHON'S ANSWER. THE DOT PATH THEREFORE DEMONSTRABLY DOES
NOT DEPEND ON EITHER FIX.**

THE CODE SAYS WHY:

- `mo_at` IS CALLED FROM `mixin/op.bend:696` (`mo_squeeze.go`), `:779` (`mo_keep_ds.go`)
  AND `:874` (`mo_reduced.go`). **`nn_dot`'s REDUCE IS `nn_sum(False{}, ...)` →
  `nn_reduce(..., kd=False)` → `M.mo_reduce.keep(kd=False, ...)` → `mixin/op.bend:793`'s
  `case _: r` — THE `mo_keep_ds` ARM IS NOT TAKEN.** THE KEEPDIM ARM
  (`mixin/op.bend:792`) IS WHERE `mo_at` ENTERS, AND THAT IS WHY THE FILE'S OWN
  `fold_smk` ROW (KEEPDIM) IS STILL EMPTY WHILE `fold_sm` (NO KEEPDIM) READS `2,4`.
- `mo_reduced` IS CALLED FROM **EXACTLY TWO PLACES**: `mixin/op.bend:894` (`mo_mean`) AND
  `:921` (`mo_var`). IT IS THE `mean`/`var` **DENOMINATOR**, AND `nn_dot` SUMS, IT DOES
  NOT MEAN. **`mo_reduced` IS NOT ON `nn_dot`'s PATH AT ALL.**

**MY FIX DOES NOT DEPEND ON THEIRS. THEIR FIXES DO NOT DEPEND ON MINE.** AND NEITHER FIX
IS SUFFICIENT FOR `conv2d`: THE PRIOR UNIT'S OWN ORDERING STANDS —
*"LANDING 1+2+3 WITHOUT 4 GIVES A CONV THAT READS A SHAPE AND A `bn` THAT DOES NOT;
LANDING 4 WITHOUT 1+2+3 GIVES NOTHING AT ALL."*

---

## 6. THE BLAST RADIUS

**WHAT THE PATCH TOUCHES:** `nn_dot.xshape` (`layers.bend:291-294`) AND ONE NEW DEF
`nn_tail_drop` BESIDE IT. NOTHING ELSE.

- `nn_dot.xshape`'s **ONLY** CALLER IS `nn_dot.pair` (`layers.bend:356`). VERIFIED:
  `grep -rn "nn_dot.xshape" tinybendygrad/ gates/ checks/` FINDS **NOTHING** OUTSIDE
  `layers.bend`. **THE SIGNATURE IS UNCHANGED**, SO NO CALLER CAN BREAK.
- `nn_dot` → `nn_linear` (`layers.bend:429`) → `tinybendygrad/extra/models/{resnet,bert,vit,llama,t5,inception,transformer,retinanet,mask_rcnn}.bend`.
  `--check-only` ON THE FIXED SCRATCH TREE: `resnet.bend` → `ALL PROOFS CHECK`,
  `vit.bend` → `ALL PROOFS CHECK`. (THE CHANGE CANNOT AFFECT THEM ANYWAY: NO SIGNATURE
  MOVED.)

**DOES ANYTHING RELY ON THE CURRENT (WRONG) BEHAVIOUR? NO.** THE OLD VALUE WAS A RESHAPE
TARGET WHOSE PRODUCT DID NOT MATCH ITS SOURCE, SO EVERY CONSUMER READ **EMPTY** — A
SHAPE READ IS NOT A VALUE ANYBODY CAN HAVE COME TO DEPEND ON. CONCRETELY:

- `grep -rn "nn_dot|xshape|dot_2d" tinybendygrad/LAWS.bend tinybendygrad/PROOF.bend tinybendygrad/LAWS/spec.bend gates/*.py checks/*.py`
  → **NO HITS.** NO LAW, NO PROOF AND NO GATE NAMES THE OLD BEHAVIOUR. `LAWS.bend` AND
  `PROOF.bend` DO NOT EVEN IMPORT `nn/layers.bend` (THE ONLY IMPORTERS ARE
  `extra/models/*.bend`).
- THE FILE'S OWN ROWS ASSERT THE **CPYTHON** ANSWERS (`dot_2d want=(2,4)`), SO THEY
  **AGREE WITH THE FIX AND OPPOSE THE BUG** — FOUR ROWS WERE **FAILING** AND NOW PASS.

**THE RESIDUAL EMPTY ROWS AFTER THE FIX, NAMED:** `conv_p1_s1`, `conv_p0_s1`, `conv_p1_s2`,
`conv_seq`, `conv_bias` (THE `nn_expand`/`cr_expand` DEFECT) AND `fold_smk` (THE `mo_at`
DEFECT). **NEITHER IS `nn_dot.xshape`'S FAULT** — THEY WERE EMPTY BEFORE AND AFTER.

---

## 7. THE PRIOR UNIT'S OTHER CLAIM, CHECKED RATHER THAN ACCEPTED: **`nn_dot.wshape` AND `nn_dot.order` ARE CORRECT — TRUE FOR `dw ≤ 2`, FALSE FOR `dw ≥ 3`**

THE PRIOR UNIT MEASURED `nn_dot.wshape` → `1,3,4` AND `nn_dot.order` → `0,2,1`, BOTH OF
WHICH ARE THE **`dw = 2`** ANSWERS, AND BOTH ARE **CORRECT**. **BUT THE CLAIM IS SILENT
ON `dw ≥ 3`, AND THERE IT IS WRONG.** MEASURED:

| case | CPython w' target | PORT `nn_dot.wshape` | CPython result | PORT result |
|---|---|---|---|---|
| A/B/C (`dw=2`) | `(1,3,4)` / `(1,7,16)` | `1,3,4` / `1,7,16` ✓ | `(2,4)` / `(8,64,7,16)` | ✓ after the fix |
| D (`dw=1`) | `(3,)` | `3` ✓ | `(2,)` | ✓ after the fix |
| E (`dw=3`) | `(3,1,4,5)` | **`5,1,3,4,5`** ✗ | CPython **raises** | `<EMPTY>` |
| F (`dw=3`) | `(3,1,4,1)` | **`1,1,3,4,1`** ✗ | CPython **raises** | `<EMPTY>` |
| G (`dw=3`) | **`(3,1,4,1)`** | **`1,1,3,4,1`** ✗ | **`(3,3,1)`** | **`<EMPTY>`** |

**CASE G IS THE ONE CPYTHON DOES NOT REFUSE**, SO THE `dw ≥ 3` DIVERGENCE HAS A
**WELL-FORMED** CPYTHON ANSWER `(3,3,1)` TO BE COMPARED AGAIN — NOT ONLY AN `IndexError`.

**THREE INDEPENDENT WRONGS IN THE `dw ≥ 3` ARM, ALL NAMED:**

1. `nn_dot.wshape` USES `List.drop(ws, 2n)` WHERE CPython HAS **`ws[0:-2]`** — A **TAIL**
   DROP. **THE SAME HEAD/TAIL DEFECT AS `xshape`.** (`ws[0:-2]` FOR `dw=3` IS `(3,)`; THE
   HEAD DROP ANSWERS `(5,)`.)
2. `nn_dot.wshape`'S LAST TERM IS THE **WHOLE** `ws`, WHERE CPython HAS **`ws[axis_w:]`**
   — THE LAST `min(dw,2)` DIMS — `(4,1)`, NOT `(3,4,1)`. **THE PORT'S HEADER COMMENT AT
   `layers.bend:296-302` ASSERTS THAT `w.shape[axis_w:]` "IS `w.shape` ON BOTH ARMS" —
   THAT IS TRUE ONLY OF THE **OBSOLETE** `axis_w = -w.ndim if w.ndim > 1 else 0`, AND
   **FALSE** OF THE VENDORED `-min(w.ndim, 2)`.**
3. `nn_dot.order` EXCHANGES POSITIONS `len-dw` AND `len-1`, WHERE CPython'S
   `.transpose(-1, axis_w)` EXCHANGES `len-1` AND **`len-min(dw,2)`**. FOR `dw=2` THE TWO
   COINCIDE; FOR `dw=3` THEY DO NOT.

**AND CPYTHON'S `:386` GUARD IS NOT PORTED AT ALL.** `nn_dot.rd` (`layers.bend:371-372`)
IMPLEMENTS ONLY `dx > 0 and dw > 0`; THE `x.shape[-1] != w.shape[axis_w]` REFUSAL IS
**ABSENT**, DESPITE THE FILE'S HEADER COMMENT AT `layers.bend:274-276` SAYING *"AND THE
TWO RAISES AT :385-386 ARE PORTED AS A `Maybe`"*. **ONE OF THE TWO IS NOT.**

**THIS IS **NOT** IN `dot.diff`.** IT IS A **DIFFERENT, BIGGER** DEFECT: FIXING IT NEEDS
(1) A TAIL DROP OF 2 — WHICH `nn_tail_drop` NOW SUPPLIES, (2) THE `ws[axis_w:]` TERM, (3)
`order`'s AXIS, AND (4) THE MISSING `:386` GUARD, SO THAT WHAT CPYTHON **REFUSES** THE
PORT **REFUSES** TOO. **LANDING IT TOGETHER WITH THE `xshape` FIX WOULD MAKE THE PATCH
UN-REVIEWABLE, SO IT IS REPORTED HERE, MEASURED, AND LEFT OUT.** THE ORCHESTRATOR OWNS
THE CALL.

**THE GOOD NEWS: THE `xshape` FIX DOES NOT MAKE THE `dw ≥ 3` ARM WORSE.** IT FIXES THE
`x` SIDE (`G_xshape` MOVES `3,4,1,4` → `3,3,1,4`, WHICH **IS** CPYTHON'S `(3,3,1,4)`),
AND THE `w` SIDE IS STILL WRONG, SO `G_result` IS STILL `<EMPTY>` — **AS IT WAS BEFORE.**

---

## 8. WHAT I DID **NOT** DO, AND WHY

- **NO FILE OUTSIDE `.agents/slop/dotfix/` WAS EDITED.** NO COMMIT. NO MUTATING GIT.
  `git rev-parse HEAD` AND `date -u` ARE THE ONLY GIT COMMANDS I RAN, PLUS
  `git show 86c4f1343^:tinygrad/mixin/op.py` (A READ) AND `git log` (READS).
- **I DID NOT RUN** `checks/differ.py`, ANYTHING UNDER `gates/`, `checks/e2e*`,
  `checks/sweep.py`, `checks/bounded.py`, ANY CORPUS-WIDE RUN, `pytest`, `mypy` OR `ruff`.
- **I DID NOT FIX `mo_at` OR `mo_reduced`** — THEY ARE IN FLIGHT IN PARALLEL, AND MY FIX
  DOES NOT NEED THEM.
- **I DID NOT FIX THE `dw ≥ 3` ARM** — SEE §7.
- **I DID NOT FIX THE `nn_expand`/`cr_expand` DEFECT OR THE REDUCE FAMILY** — NOT MINE.
- **NO `.txt` FILE WAS CREATED.** THE CAPTURED INSTRUMENT OUTPUTS ARE
  `.out` (`cpython.out`, `port_before.out`, `port_after.out`, `rows_before.out`,
  `rows_after.out`).

---

## 9. THE FILES

| file | what |
|---|---|
| `dot.diff` | **THE PATCH.** `a/tinybendygrad/nn/layers.bend` → `b/tinybendygrad/nn/layers.bend`. `patch -p1 --dry-run` → rc=0. |
| `cases.rows` | THE PROOF TABLE. EVERY CELL AN INSTRUMENT READ. |
| `REPORT.md` | THIS FILE. |
| `cpython_oracle.py` | THE CPYTHON ORACLE. PRINTS x' / w' / THE RESULT, AND **WHY** `axis_w` IS `-min(dw,2)`. |
| `sem.bend` | THE `List.drop` / `List.take` / `Nat.sub` SEMANTICS PROBE. `import Base` ONLY. |
| `probe.bend` / `probe_fix.bend` | THE PORT PROBE. **ONE LINE DIFFERS BETWEEN THEM** (THE IMPORT PATH) — `diff` SAYS SO. |
| `collect.sh` | RUNS ALL FIVE INSTRUMENTS AND REBUILDS `cases.rows`. |
| `mkrows.py` | TURNS THE CAPTURED OUTPUTS INTO `cases.rows`. **TYPES IN NOTHING.** |
| `scratch/` | A COPY OF THE WHOLE PORT, **BEFORE**. |
| `scratchfix/` | A COPY OF THE WHOLE PORT, **AFTER**. |
| `*.out` | THE CAPTURED INSTRUMENT OUTPUTS. |

**COMMANDS (ALL CHEAP, ALL SEQUENTIAL, ALL UNDER 2 s AND UNDER 200 MB):**

```
./bin/bend .agents/slop/dotfix/sem.bend
.venv/bin/python .agents/slop/dotfix/cpython_oracle.py
./bin/bend .agents/slop/dotfix/probe.bend
./bin/bend .agents/slop/dotfix/probe_fix.bend
./bin/bend .agents/slop/dotfix/scratch/nn/layers.bend
./bin/bend .agents/slop/dotfix/scratchfix/nn/layers.bend
./bin/bend --check-only .agents/slop/dotfix/scratchfix/nn/layers.bend     # ALL PROOFS CHECK
sh .agents/slop/dotfix/collect.sh
```
