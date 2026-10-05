# TENSOR SURFACE -- the port's Tensor surface, measured, and the shortest path to a backward pass

**VERDICT ON THE PREMISE: the premise was TRUE as a name search and FALSE as a
conclusion, and the brief's own fallback reading ("I don't know") was the right
one. Both halves of the brief's suspicion were correct and the correction was
also correct: 6 of the 7 names really are absent from `tensor.bend` -- but three
of them (`mul`, `add`, `matmul`) are not `tensor.py` methods at all, `zero_grad`
is not a `Tensor` method in any file, and `backward` is PRESENT under the name
`tn_need_grad`.** See §1.

**AND: my own load-bearing claim from Stage 1-3 was FALSIFIED by measurement.
The port CAN build a backward graph. See §4 — 5 of 5 signature fields agree
with CPython, reproduced twice.**

Everything below is produced by CALLING, never transcribed. Regenerate:

```
.venv/bin/python  checks/stage1-census.py
.venv/bin/python  .agents/slop/tensor-surface/stage2-exercised.py
env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/tensor-surface/stage3-path.py
.venv/bin/python  .agents/slop/tensor-surface/stage4-falsify.py
```

The first line of the brief's Stage-1 question -- *which is it, heavily renamed
or a different surface?* -- is answered by measurement in §0, and the answer is
**neither**.

---

## 0. THE 2.7x ASYMMETRY, RESOLVED. IT IS COMMENT, NOT SURFACE.

The brief asked whether `tensor.bend` being 2.7x upstream's line count means it
is "heavily renamed/spelled out, or not the same surface". Measured, by
classifying every line of both files:

| file | total | blank | comment | **code** |
|---|---|---|---|---|
| `tinygrad/tensor.py` | 591 | 81 | 47 | **463** |
| `tinybendygrad/tensor.bend` | 1,584 | 211 | **1,225** | **148** |

**The port is 148 code lines against upstream's 463 -- it is 3.1x SMALLER, not
bigger.** The 1,583 lines are 77% documentation. So the asymmetry is not a
renaming story and not a surface story; it is a *prose* story, and the
prose is unusually good: the file's own header documents four walls, five
learned Bend rules, and a 17-entry mutation table with the rows each one moved.

This matters for the census because it means **`tensor.bend`'s line count is
close to zero evidence about its surface**, and a name search over it is
close to zero evidence too. Both of the brief's two false premises came from
the same move: reading a file's *shape* and reporting it as its *contents*.

---

## 1. STAGE 1 -- THE CENSUS. DENOMINATOR 57.

### 1.1 The denominator, and how it was computed

`ast.parse` on the real `tinygrad/tensor.py` gives **57 `def`s in `class Tensor`**
(`tensor.py:44-564`): 28 public, 8 private, 21 dunder. Plus 4 module-level defs
and 3 in `_ContextVar`.

**A WARNING ABOUT THE OBVIOUS WAY TO COUNT THIS.** `Tensor.__dict__`'s public
list is **226**, not 24. `tensor.py:588-591` is a `TRACEMETA` loop that does
`setattr(Tensor, name, ...)` for `inspect.getmembers(Tensor, inspect.isfunction)`
-- i.e. for every **inherited** member too. Filtering on
`v.__module__ == 'tinygrad.tensor'` gives **24 public + 7 private = 31**, which is
the right answer and is 7 short of the AST's 28+8=36 because `@property` and
`@rewrite_group` methods lose `__module__`. **The AST is the denominator here
because it does not depend on which attributes Python's reflection happens to
have copied back onto the class.**

### 1.2 The mapping table, all 57

Every counterpart was found by **reading** `tensor.bend` and following its own
`TODO(p3) tensor.py:<line> <name>` markers and `def` bodies -- not by looking for
a def with the upstream name. Full output: `stage1-census.txt`.

**PRESENT (18 of 57, 32%).** Three are full ports, one is full-with-a-known-gap,
three are partial, and the rest are structural halves.

| upstream | L | port counterpart | port L | state |
|---|---|---|---|---|
| `alu` | 116 | `tn_alu` / `.of` / `.put` | 255-287 | **FULL** |
| `_uop` | 118 | `Tensor.u` | 194 | **FULL** |
| `_wrap_uop` | 120 | `tn_wrap_uop` | 300 | **FULL** |
| `is_param_` | 124 | `tn_is_param_` | 316 | **FULL** (returns a new record; documented divergence) |
| `__repr__` | 128 | `tn_repr` + 8 helpers | 365-422 | **FULL** |
| `__hash__` | 134 | `tn_hash` | 323 | **FULL** (rule differs; documented) |
| `__len__` | 138 | `tn_len` / `.of` / `.first` | 335-346 | **FULL**, as a `Maybe` |
| `device` | 143 | `tn_device` / `tn_dev` | 198-245 | **FULL** |
| `shape` | 146 | `tn_shape` / `tn_dims` | 201-226 | **FULL** |
| `dtype` | 149 | `tn_dtype` | 204 | **FULL** |
| `replace` | 227 | `tn_replace` + 4 | 517-536 | **FULL** |
| `_mop` | 499 | `tn_mop` + 16 (hoisted from `ops.py:821`) | 645-730 | **FULL** |
| `_rop` | 500 | `tn_rop` + 15 (hoisted from `ops.py:655`) | 766-869 | **FULL with a gap** (WALL 5) |
| `__init__` | 57 | `tn_init.arm/.none/.keep` + `tn_cast` | 448-507 | **PARTIAL** -- 13 defs, all dead (§2) |
| `_apply_uop` | 104 | `tn_alu` / `tn_new` / `tn_wrap_uop` | 286-301 | **PARTIAL** -- the tail only; `fxn` is `TODO(p3)` at :295 |
| `const` | 122 | `tn_const` | 311 | **PARTIAL** -- bare CONST, no dtype (`:304`) |
| `assign` | 236 | `tn_assign_store` + `tn_ib_walk` | 889-905 | **PARTIAL** -- the SPINE only; 8 of 9 arms are `TODO(p3)` at :907 |
| `backward` | 475 | `tn_need_grad` + 8 | 920-949 | **PARTIAL** -- the SCOPE FILTER only; the zip is `TODO(p3)` at :951 |

**ABSENT (39 of 57, 68%).** By name, as asked:

```
as_param  call  custom_kernel  linear_with_vars  schedule_linear  realize
_buffer  _data  data  tolist  numpy  clone  to  to_  shard  shard_  shard_like
from_blob  from_url  manual_seed  _next_counter  decode_hevc_frame
__bool__  __setitem__  __delitem__  __eq__
__iadd__  __isub__  __imul__  __itruediv__  __ifloordiv__  __ipow__
__iand__  __ior__  __ixor__  __ilshift__  __irshift__  __imatmul__
```

Restricted to **public** methods only: **9 of 28 present, 19 absent**
(`as_param call clone custom_kernel data decode_hevc_frame from_blob from_url
linear_with_vars manual_seed numpy realize schedule_linear shard shard_ shard_like
to to_ tolist`).

Plus 4 module-level: `_apply_map_to_tensors` (scope walk ported via
`Tensors.holds`/`Tensors.member`; the substitution is WALL 3), `_tensor_holds`
-> `Tensors.holds` **FULL**, `_fromnp` absent, `_metadata_wrapper` absent, and
`all_metadata`'s writer absent.

### 1.3 THE SEVEN NAMES IN THE BRIEF -- and why the name search was the wrong instrument

This is the part the brief was right to be suspicious about, and the answer is
that **a name search of `tensor.bend` cannot find these names even if they are
there**, for three different and independent reasons:

| name | where it actually lives upstream | port counterpart | verdict |
|---|---|---|---|
| `matmul` | **`mixin/op.py:394`**, not tensor.py | W8 wall, `mixin/op.bend:84` | not a tensor.py method |
| `mul` | **`mixin/elementwise.py:125`**, not tensor.py | **`ew_mul`, `mixin/elementwise.bend:544`** | **present, renamed** |
| `add` | **`mixin/elementwise.py:84`**, not tensor.py | **`ew_add`, `mixin/elementwise.bend:543`** | **present, renamed** |
| `backward` | `tensor.py:475` | **`tn_need_grad`, `tensor.bend:920-949`** | **present, renamed, partial** |
| `zero_grad` | **not a `Tensor` method at all** -- it is `tinygrad/nn/optim.py:29,70` | **`op_zero_grad.of`, `nn/optim.bend:395`** | **present, renamed** |
| `realize` | `tensor.py:219` | none; `TODO(p3)` at `tensor.bend:1036` | **genuinely absent** |
| `schedule_linear` | `tensor.py:212` | none; `TODO(p3)` at `:1031` | **genuinely absent** |
| `assign` | `tensor.py:236` | `tn_assign_store`, `:889` (spine) | present, renamed, partial |

So: **2 of the 7 are genuinely absent from the port's `Tensor` layer
(`realize`, `schedule_linear`), 4 exist under other names (2 of them in a
different FILE), and 1 (`zero_grad`) was never a `Tensor` method -- searching
`Tensor` for it is a phantom, and `hasattr(Tensor,'zero_grad')` is `False`.**

The brief's own error #1 -- grepping a name against a port that renames -- is
exactly what produced the "0" here. The brief's error #2 -- a phantom `Ops.DIV`
-- has the same shape: a name that is not where the search looked.

---

## 2. STAGE 2 -- PRESENT vs EXERCISED, WITH THE DENOMINATOR

**A count of defs is def-coverage, not executability.** Three denominators, all
printed by the tool (`stage2-exercised.txt`).

### D1 -- the port's own def graph

| | |
|---|---|
| `tensor.bend` defs | **174** |
| reachable from `main()` | 154 |
| **not reachable (dead in-file)** | **19** |
| exercised by another `.bend` file | 15 (229 references) |

**The 19 dead defs, and they are not random:**

- **13** = the *entire* `__init__` counterpart: `tn_init`, `.arm`, `.none`,
  `.keep`, `.of`, and all eight `tn_cast*`. So `Tensor.__init__` is **written
  and never executed by anything**, including its own gate.
- **2** = `tn_ib_walk`, `.of` -- the `assign` spine's `ib` descent.
- **4** = `Tensor.grad_set` (**the grad WRITER -- and it is dead**), `Tensors.of`,
  `g_t4a`, `tn_wrap_uop`.

`Tensor.grad_set` being dead is the one that matters for Stage 3: the port has
a def for setting `.grad` and nothing calls it.

### D2 -- upstream methods with a port counterpart, and whether the gate runs them

Denominator **17** counterpart roots:

| verdict | n | which |
|---|---|---|
| **EXERCISED by the gate** | **15** | `__hash__ __len__ __repr__ _apply_uop _mop _rop alu assign backward const device dtype is_param_ replace shape` |
| **PRESENT, NEVER RUN** | **2** | `__init__`, `_wrap_uop` |

**But `backward` needs a qualifier or it is a lie.** `tn_need_grad` IS in
`main()`'s graph -- reached through `t_needgrad`, which prints a COUNT
(`tn_needgrad=2`) of the scope filter. `backward`'s own zip
(`self.gradient(*tensors_need_grad, ...)` and `t.grad.assign(...)`,
`tensor.py:490-494`) is `TODO(p3)` at `tensor.bend:951`. So **`backward` is
exercised as a FILTER, 1 of 2 halves.** That is not a pass.

**And 1 of the 15 is only half-present:** `assign` is exercised through
`tn_assign_store`, which is the AFTER/STORE spine (one row, `tn_assign`). The
other eight of its nine arms are `TODO(p3)`.

### D3 -- the ops enum, which is NOT the gap

| | |
|---|---|
| upstream `list(Ops)` (called, not read) | **77** |
| port `Ops*` enum cases in `uop/ops.bend` | **77** |
| missing in port | **0** |
| extra in port | **0** |

**The enum is complete.** The "not reached" figure in `graphcmp-LIMITS.md` §5
is a COVERAGE number over the differ's *corpus*, not an enum gap. Reading the
two numbers as the same kind of thing is the same mistake as the brief's #2.

⚠ **BOTH THE FIGURE AND THE CITATION AGED — re-measured 2026-10-04 by `notes-sweep`.**
This said *"43 of 77 not reached"* in **`graphcmp-LIMITS.md:422`**; the corpus is now
**18 of 77 not reached** (59 reached, denominator 77 measured as `len(list(Ops))`), and
**`:422` is not the line the figure is on** — §5's coverage headline is elsewhere in the
file. **The distinction this paragraph draws is UNAFFECTED and still worth making:** 0
missing and 0 extra in the port's `Ops*` enum is a statement about *declaration
completeness*, and 18 unreached is a statement about *what the corpus exercises*. Those
are different questions and were never the same number. **`enum 77/77/0/0` was not
re-measured by this unit; STALE by construction, since `uop/ops.bend` is live code.**

### The gradient driver, measured

| symbol | callers in the whole port tree |
|---|---|
| `compute_gradient` | **0** |
| `_deepwalk` | **0** |
| `reduce_gradient` | **0** |
| `call_gradient` | **0** |
| `partial_store_gradient` | **0** |
| `pm_gradient` rules ported as `gr_0`..`gr_32` | **33 of 33** |

`mixin/gradient.bend` is 1,761 lines and 252 defs. **The rule table is 33/33 and
gated; the driver that walks the graph applying it has zero defs and zero
callers.** That is precisely the shape this project has already been burned by:
4,868 generated defs read as progress.

---

## 3. STAGE 3 -- WHAT A FIRST REAL BACKWARD PASS NEEDS

### 3.0 The path the brief asked me to check

**`tinygrad/engine.py` does not exist at this tree revision.** It is the
**package** `tinygrad/engine/` (`__init__.py jit.py realize.py worker.py`), and
the import on `tensor.py:13` is `from tinygrad.engine.realize import run_linear`,
with `run_linear` at `tinygrad/engine/realize.py:280`. The port mirrors it at
`tinybendygrad/engine/realize.bend`.

**And `backward`'s callee is not in `engine/` at all.** It is
`tinygrad/mixin/gradient.py:116 compute_gradient`, reached through
`mixin/op.py:464 OpMixin.gradient` -- confirmed by a traceback, not by reading.

### 3.1 THE MEASUREMENT THAT SETS THE SCOPE. CALLING CPython.

`a=Tensor([2.,3.]); b=Tensor([4.,5.]); (a*b).sum().gradient(a,b)` on
`DEV=NULL` -- **no device, no Buffer, no realize**:

```
forward graph : n=6  ops=['BUFFER','COPY','MUL','REDUCE']
gradient(a,b) : 2 grads, grad[0] n=7
ops the BACKWARD graph has that the forward did NOT: ['CAST','CONST','EXPAND']
```

**A first real backward pass needs exactly three ops the forward corpus never
reaches, and nothing else. All three are already in the port's enum (§2/D3).**
So the gap is not ops. It is (a) the driver and (b) reachability.

### 3.2 The missing pieces, each with its file

| piece | upstream | port file | why it is missing |
|---|---|---|---|
| `compute_gradient`'s walk | `mixin/gradient.py:116-145` | `mixin/gradient.bend` | writable as a fold-shaped `Data` table; **not** a wall by the file's own account |
| `_deepwalk` | `:109-114` | `mixin/gradient.bend` | `topovisit`'s visitor is a Python callable closing over a dict |
| shaped-edge reduce | `:132-133` | `uop/symbolic.py` (**not ported**) | `broadcast_axes` (`ops.py:89`) reads `resolve` on a `Sint` |
| `sum_acc_dtype` | `dtype.py:220` | `tinygrad/dtype.py` | reads `getenv("SUM_DTYPE")`; Config is P6 |
| `Tensor.gradient` | `mixin/op.py:464` | `mixin/op.bend` | **absent** (measured) |
| `backward`'s zip | `tensor.py:490-494` | `tensor.bend:951` | `TODO(p3)` |
| `.grad` writer | `optim.py:33` uses it | `tensor.bend:279` | **present but DEAD** (§2/D1) |
| `realize` / `run_linear` | `engine/realize.py:280` | `engine/realize.bend` | **not needed** for a graph-level backward |

### 3.3 THE THREE ORDERED STEPS

**STEP 1 -- `tinybendygrad/mixin/gradient.bend`.**
Write `compute_gradient`: a `walk` list from `O.UOp.toposort` in reverse, a
`grads` association over arena indices, dispatch through the file's **existing**
`gr_rewrite`, and the accumulate with its **existing** `gs_is_skip`/`gs_get`/
`gs_hole`/`gs_solid`/`gs_len`/`gs_ar`.
*Smallest proof:* one row comparing the toposort signature and the solid-gradient
COUNT against CPython's `pm_gradient.rewrite` on the same fixture. **§4 shows
this step is already writable in ~30 lines and produces a byte-identical
signature, so this step's remaining content is the multi-node walk and the
shaped-edge reduce -- not the loop's feasibility.**

**STEP 2 -- `tinybendygrad/tensor.bend:951`.**
Replace the `backward` zip `TODO(p3)` with the call into Step 1, and wire
`Tensor.grad_set` (`:279`, already a def, currently dead) to it. `t.grad.assign`
needs the `assign` spine, which is ported (`tn_assign_store`, `:889`).
*Smallest proof:* a `tn_backward` row over a `BUFFER->MUL->REDUCE` fixture
printing the same scope COUNT (`tn_needgrad` already pins that half) and the same
grad ROOT OP. The pair is what makes it falsifiable.

**STEP 3 -- `mixin/elementwise.bend` + the `graphcmp` corpus.**
Land `CAST`/`CONST`/`EXPAND` reachability (`tn_cast` exists at `tensor.bend:463`
and is dead), then add a training graph to the corpus.
*Smallest proof:* one `graphcmp` graph whose py side is `compute_gradient` over a
hand-built `BUFFER/CONST/MUL/REDUCE`, run under `sh .agents/slop/graphcmp-run.sh`,
`AGREE` at the field-record level. That is the owner's standing ask.

**Why this order.** Step 1 is the capability and the only piece with no port file
behind it. Step 2 is ~12 lines in a file that already has the scope filter and the
assign spine. Step 3 is reachability and corpus, and it is LAST because a
backward graph that disagrees for a reason that is not the driver's is the
failure mode that costs most: it looks like a driver bug and sends you into
`gradient.bend`.

**What is deliberately NOT a step: `realize`, `run_linear`, `Buffer`.** Measured
in §3.1: `compute_gradient` runs to completion on `DEV=NULL` with no device
state. A first real backward pass is a GRAPH claim. Folding `realize` in would
make the step untestable.

---

## 4. STAGE 4 -- THE FALSIFICATION. **MY CLAIM WAS WRONG.**

### 4.1 The claim, and the plant

The most load-bearing claim in this census is the one in §2/D2 and §3:

> "No port file calls `compute_gradient` (0 callers), and `mixin/gradient.bend`
> has zero driver defs. **Therefore the port cannot build a backward graph.**"

The plant is the strongest available falsifier: **write `compute_gradient`'s
reverse walk myself**, in `$TMPDIR`, against the port's own `gr_rewrite` and
`gr_12`, and see whether a backward graph appears. It imports the real substrate
by relative path from a `cp -R` mirror of the tree; the repo tree is never
written; a control probe proves the substrate compiles before any verdict.

### 4.2 THE RESULT. **5 of 5 signature fields AGREE, REPRODUCED TWICE.**

```
control (import resolution + substrate compiles): OK
plant_rule=FIRED n=2 solid=2
plant_fw=3     CONST/0 CONST/0 MUL/2
plant_grad0=3  CONST/0 CONST/0 MUL/2
plant_grad1=3  CONST/0 CONST/0 MUL/2
plant_grads_n=2

oracle_fw=3     CONST/0 CONST/0 MUL/2        <- CALLED, tinygrad, DEV=NULL
oracle_rule=FIRED n=2 solid=2
oracle_grad0=3  CONST/0 CONST/0 MUL/2
oracle_grad1=3  CONST/0 CONST/0 MUL/2

agreement: 5 of 5 signature fields
```

**The port CAN build a backward graph.** The claim was **TRUE as a census and
FALSE as a conclusion.** The missing piece is not a missing file; it is the
LOOP, and the loop is short.

### 4.3 What this changes, and what it does not

**It does NOT give the port a backward pass.** The rows above are a **one-step**
walk over **one hand-built node** with an INT seed. Not the reverse walk, not
the shaped-edge reduce, not the zip, no `backward`, no E2E. Stage 3's three steps
are unchanged, because they were derived from what is **MISSING**, not from an
estimate of effort.

**It DOES change Stage 3's Step 1.** The rule table (33/33), the first-wins
dispatcher, **and every reader the accumulate needs** (`gs_is_skip`, `gs_get`,
`gs_hole`, `gs_solid`, `gs_len`, `gs_ar`) were already in `mixin/gradient.bend`
and already gated. The honest headline is:

> **"the reverse-mode RULE TABLE is 33/33 ported and gated; the WALK is absent"** --
> not "backward is absent".

### 4.4 THE FOUR PLANT FAILURES THAT WERE NOT RESULTS, and one that was

A plant that fails for a reason that is my own harness is not a finding. Each of
these produced a plausible-looking wall, and each is a rule the port already
records:

1. **`import` must be `./helpers.bend`, not absolute.** And a **symlink** mirror
   defeats hub detection -- "an import path of plain names" is raised on
   `./helpers.bend` when every substrate file is a symlink. A real `cp -R` of the
   11M tree fixes both. *This is the brief's own `$TMPDIR` trap.*
2. **`Bool.pick` is strict**, so a tail spent in both arms is
   `t (consumed more than once)` -- and a `Nat`/`U32` spent twice needs `+`.
3. **`Bool.pick(T, cond, a, b)` returns `a` when cond is TRUE** (proved from
   `tensor.bend:766 tn_rop.ins`, an insertion sort). I had the hole guard
   **backwards**, so the accumulate ran on a hole and skipped on a real gradient,
   and it printed `plant_grads_n=0` on a rule that had just fired twice. **A zero
   from an inverted guard is indistinguishable from a broken driver** -- only the
   oracle says which it was.
4. **`List.index_of` does not exist**; `List.foldl`'s lambda **cannot capture a
   runtime variable** ("a template applied to closed `~` arguments"); and a
   self-call carrying a match result through `Bool.pick` is refused with
   "expected : a decreasing self-call", because the pick hides the shrink.

**And the one that WAS a result, because it was a real disagreement I had to
root-cause: a stale arena.** The plant read `plant_seed=4` and `plant_gs0=4` --
the gradient and its own seed were the SAME node, and `plant_grad0` printed a
1-node graph against CPython's 3. Cause: I passed `ar(m)` (next=4) while the seed
was interned at index 4, so `G.gmul` **interned the gradient MUL at index 4 and
clobbered the seed**. That is `tensor.bend`'s own rule 5 ("THE ARENA A BUILD
RETURNS IS NOT THE ARENA THAT WENT IN") wearing my bug. It typechecks and it runs.
**The port's own rows do not have it** -- `rw(fx_ar(fix()), ...)` reads the arena
after `fix()` has interned every fixture node.

### 4.5 TWO CONCURRENCY OBSERVATIONS, for the coordinator

**`tinybendygrad/helpers.bend` was mid-edit TWICE while this unit ran** (14:25 and
again after 14:30) and failed at `helpers.bend:2552` and `helpers.bend:1830`
("an unfilled law is a dead claim: live code cannot use it", naming `divmod_r`
and `i64_is_zero`). Those are **another agent's** unfinished edits. **I report
them and did not touch the file.** The Stage 4 harness's control probe is what
caught them, and it refuses to print a verdict when the substrate itself does not
compile -- without that probe both would have been reported as walls on the
gradient path, which would have been the single most expensive false result this
census could have produced.

---

## 5. WHAT I DID NOT DO, AND WHAT IS STILL TRUE

- **I did not edit any `.bend` file.** `tensor.bend` was read-only, as instructed.
  The brief says to report the mapping and ask for the file; **§1.2 is that
  mapping, and I am asking for the file rather than taking it.**
- **I did not touch** `runtime/portexec/**`, `graphcmp*`, `e2e*`, `rebase-gate.py`,
  `cstyle-gate.py`, `reader-guard.py`, `sched-*`, `helpers.bend`, `LAWS/**`, or
  any `PROOF*.bend`.
- **The 64/64 u32 WebGPU E2E is untouched** and its `navigator.gpu` gap is the
  other unit's; I did not duplicate it.
- **Still true after §4:** `realize` and `schedule_linear` are genuinely absent
  from the port's Tensor layer; `backward` has no zip; `Tensor.grad_set` is dead;
  the port has no reverse-mode walk; and **no gate in the tree exercises a
  backward graph end to end.** §4 falsifies "the port cannot build one"; it does
  not falsify "the port has never been shown to build one".
- **Still unmeasured, and I will not guess:** whether the plant's
  `Data`-over-parallel-lists `Grads` table is the right shape for the FULL walk,
  where each key is written at most once per node but a node can have many srcs.
  §4's plant is one node deep, so it does not test the accumulation across nodes
  at all. **That is the first thing Step 1 must gate.**

## 6. FILES

| file | what |
|---|---|
| `checks/stage1-census.py` / `.txt` | the 57-row mapping table, the denominator, the seven names |
| `.agents/slop/tensor-surface/stage2-exercised.py` / `.txt` | the def graph, the 19 dead defs, 15/17 exercised, 77/77 ops, 0 gradient callers |
| `.agents/slop/tensor-surface/stage3-path.py` / `.txt` | the `engine/` path, the `DEV=NULL` measurement, the 8 missing pieces, the 3 steps |
| `.agents/slop/tensor-surface/stage4-falsify.py` / `.txt` | the plant, the oracle, the 5-of-5 diff, the control probe |

All four `.txt` are captured output. The Stage 4 run needs `helpers.bend` to be
mid-edit-free; the control prints `BROKEN` and refuses a verdict when it is not.