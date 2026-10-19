# `tn_rop.perm` — CANDIDATE, MEASURED, LANDED NOWHERE

**HEAD at measurement: `d3fbede230c48aa7c9a943db931fec8f1c5b3012`** (2026-10-19T16:36:43Z).
The session STARTED at `0273fe4286e2446c28865eaa155ec09e3052a41f` (16:24:50Z) and HEAD
**moved underneath it** — `8b406d2a1` and `d3fbede23` landed in those twelve minutes.
`git diff --stat 0273fe42 HEAD -- tinybendygrad/tensor.bend tinybendygrad/uop/fold.bend
tinybendygrad/mixin/op.bend tinybendygrad/mixin/reduce.bend tinybendygrad/nn/layers.bend
tinybendygrad/nn/optim.bend` is **empty**, so every reading below is a reading of the
current tree, not of a stale one.

**NOTHING WAS LANDED.** `tinybendygrad/` is byte-identical to HEAD — verified by
content hash, not by `git status`, which is unreadable on this tree because the index is
armed by design: `git hash-object tinybendygrad/tensor.bend` equals `git rev-parse
HEAD:tinybendygrad/tensor.bend` (also checked for `mixin/op.bend` and `uop/fold.bend`).
`patch --dry-run -p1 -f < candidate.diff` says `patching file
'tinybendygrad/tensor.bend'` against the CURRENT tree, i.e. the patch is unapplied. No
commit, no `git add`, no index write. Everything lives under `.agents/slop/ropfix/`, and
the substrate under measurement is `ropfix/tinybendygrad/`, a `cp -R` of the live tree.

---

## 1. THE READING: CPython's `_rop` vs the port's `tn_rop`

`tinygrad/uop/ops.py:630-639`, MEASURED by reading the vendored source:

```python
def _rop(self, op:Ops, axis:tuple[int, ...]):
  axis = tuple(sorted(axis))
  reduce_axis = tuple(x for x in axis if resolve(self.shape[x] != 1))
  if not len(reduce_axis):
    return self.reshape(tuple(s for i,s in enumerate(self.shape) if i not in axis))
  # permute so reduced axes are at the front
  perm = reduce_axis + tuple(i for i in range(len(self.shape)) if i not in reduce_axis)
  ret = UOp(Ops.REDUCE, src=(self.permute(perm),), arg=(op, len(reduce_axis)))
  return ret.reshape(...) if axis != reduce_axis else ret
```

and `tinygrad/mixin/movement.py:214`, whose LAST line is **:231**:

```python
return self._mop(Ops.PERMUTE, arg=order_arg) if order_arg != tuple(range(self.ndim)) else self
```

**The identity test the port was missing is `order_arg != tuple(range(self.ndim))` on
:231 — NOT `sorted(order_arg) != list(range(self.ndim))` on :230**, which is the line the
old `tensor.bend:1811` comment cited. :230 is a *validity* check that **RAISED** in
CPython; :231 is the one that returns `self`. The old port comment cited the raise, and
then hoisted *that* as "the TEST" and answered `self` in both arms — so the comparison
decided nothing.

The port's own `mo_permute` (`tinybendygrad/mixin/op.bend:673-681`) is the same function
done correctly, and it is where the shape of the answer was available all along:

```bend
def mo_permute.pick(isid: Bool, +t: T.Tensor, +ys: List<&2, U32>) -> T.Tensor:
  match isid:
    case True{}: t
    case _:
      +n = T.tn_mop(T.Tensor.ar(t), T.Tensor.u(t), O.OpsPERMUTE{}, T.AOrder{ys})
      T.tn_alu.put(n)
```

`tn_rop.perm.of` had the identical `isid` short-circuit and the identical missing FALSE
arm. That is the defect, and nothing else.

**WHY IT IS A SIGNATURE CHANGE AND NOT A ONE-LINE ARM.** `perm.of(is_id, self)` receives
no `rn` and no `ndim`, so it cannot compute `perm`. Worse, `tn_rop.perm` returned a
`U32`, and `tn_mop.order` **interns a node**, so the index it answers names a node in an
arena one longer than the `ar` the caller held — precisely the hazard `tensor.bend:284`
warns about ("a LEGAL but WRONG index … which is why no gate caught it"). The REDUCE
would then be built in the stale arena. So `perm` and `red2.of` had to change to `O.Found`
and to read the REDUCE's src out of `O.Found.ar(p)`. That is why this needed measuring
before landing rather than after.

---

## 2. `--check-only`

```
$ ./bin/bend .agents/slop/ropfix/tinybendygrad/tensor.bend --check-only
ALL PROOFS CHECK
Use --verdict for mathematical validity.
```

**First line: `ALL PROOFS CHECK`** — and the SAME command on the unpatched live tree
prints the same first line, so `--check-only` was green before and after. It is a
**typecheck and a proof-closure check, not a behavioural one**: it could not see this
defect and it cannot see the fix. `checkonly-after.rows`.

Also green on the patched copy: `mixin/movement.bend`, `mixin/dtype.bend`,
`codegen/opt/postrange.bend`, and the four caller files below, which run (not just
typecheck) — so the transitive closure over `ops.bend`/`fold.bend`/`helpers.bend`/
`LAWS/spec.bend` compiles.

---

## 3. THE PROOF, ON THE CASE THAT IS CURRENTLY WRONG

**Fixture: `(2, 4, 3)`**, `BUFFER(24)` `RESHAPE`d — the port's node for node image of
CPython's `Tensor.empty(2,4,3)`.

**ONE probe file, TWO targets.** `probe.bend` imports `./tinybendygrad/…` (the patched
copy). `probe-live.bend` is byte-identical except its six import lines point at
`./../../../tinybendygrad/…` — the **live, unpatched tree**. Both readings are therefore
the same rows from the same code, and the difference can only be the substrate.

### CPython oracle — `.venv/bin/python`, upstream `tinygrad`, `DEV=NULL`

```
Tensor.empty(2,4,3).sum(axis=-1).shape            == (2, 4)
Tensor.empty(2,4,3).sum(axis=1).shape             == (2, 3)
Tensor.empty(2,4,3).sum(axis=0).shape             == (4, 3)
Tensor.empty(2,4,3).sum(axis=[0,2]).shape         == (4,)
Tensor.empty(2,4,3).sum(axis=-1,keepdim=True).shape== (2, 4, 1)
```

### BEFORE (live tree, `d3fbede2`) vs AFTER (patched copy) — `shape=` column

| row | axis | CPython | **BEFORE** | **AFTER** | |
|---|---|---|---|---|---|
| `rop_ax0` | `[0]` | `(4,3)` | `(4)(3)` | `(4)(3)` | **UNMOVED — the control** |
| `rop_ax1` | `[1]` | `(2,3)` | `(4)(3)` | `(2)(3)` | FIXED |
| `rop_ax2` | `[2]` | `(2,4)` | `(4)(3)` | `(2)(4)` | FIXED |
| `rop_ax02` | `[0,2]` | `(4,)` | `(3)` | `(4)` | FIXED |
| `sum_ax0` | `[0]` | `(4,3)` | `(4)(3)` | `(4)(3)` | **UNMOVED — the control** |
| `sum_ax1` | `[1]` | `(2,3)` | `(4)(3)` | `(2)(3)` | FIXED |
| **`sum_ax2`** | **`[2]`** | **`(2,4)`** | **`(4)(3)`** | **`(2)(4)`** | **THE CASE — FIXED** |
| `sum_ax2kd` | `[2]` kd | `(2,4,1)` | `(1)(4)(3)` | *(empty)* | **REFUSED — see §5** |

`axis=[2]` **IS** `axis=-1` over a rank-3 source: `mo_resolve` on a negative dim is
`dim + ndim` (`mixin/op.bend:719`), and this candidate does not touch it. So `sum_ax2` is
the `sum(-1)` row.

`rop_ax0` / `sum_ax0` are the **CONTROL and they did not move**, byte for byte, including
the node count (8) and the absence of a `PERMUTE`. That is the identity test doing its
job: reducing a leading axis needs no permute in CPython either.

### The node sequence, `sum(-1)` over `(2,4,3)`

```
BEFORE  8  CONST/0 BUFFER/1 CONST/0 CONST/0 CONST/0 STACK/3 RESHAPE/2 REDUCE/1
AFTER   9  CONST/0 BUFFER/1 CONST/0 CONST/0 CONST/0 STACK/3 RESHAPE/2 PERMUTE/1 REDUCE/1
```

and node-by-node (`probe2-after.rows`), the AFTER graph is exactly CPython's:

```
node  2 BUFFER  shape=[(24)]
node  8 RESHAPE  shape=[(2)(4)(3)]
node  9 PERMUTE  shape=[(3)(2)(4)]     <- perm = (2,0,1), ops.py:636
node 10 REDUCE   shape=[(2)(4)]        <- num_axes = len(reduce_axis) = 1
```

CPython builds `REDUCE(PERMUTE(RESHAPE(BUFFER,(2,4,3)), (2,0,1)), (ADD, 1))` with shape
`(2,4)`. Same nodes, same order, same arg.

`rop_ax02` → `PERMUTE((0,2,1))`, `num_axes=2`, result `(4)`, which is also CPython's.

---

## 4. BLAST RADIUS — MEASURED BY READING, NOT BY RUNNING THE CORPUS

### 4a. The 34-graph corpus **cannot see this defect at all**, before or after

`grep -c 'T\.tn_' .agents/slop/graphcmp.bend` → **1**, and that one call is
`T.tn_wrap_uop` at `graphcmp.bend:1605`. **`T.tn_rop` is never called by the corpus's
bend side.** Every graph in `graphcmp.bend` is built **node for node by hand** —
`g_reduce` is nine literal `O.UOp.new` calls, not a `sum`. So:

* **ZERO of the 34 corpus graphs would change.** Not "probably few" — **zero, and for a
  structural reason you can check in one grep.**
* The corpus's **py** side does go through real `Tensor.sum`, and the corpus is green at
  34/34 today *while every reduce over a non-leading axis in the port is wrong*. **The
  corpus's greenness is not evidence about this defect in either direction.** That is the
  honest reading and I am not going to soften it into a count.

I did **not** run `checks/differ.py`, `gates/`, `e2e`, `sweep.py`, `bounded.py`, or the
corpus.

### 4b. Every real caller of `T.tn_rop`, run before/after on ONE file each

There are exactly **four** call sites in the tree (`grep -rn 'T\.tn_rop' --include='*.bend'
tinybendygrad`, minus comments):

| caller | rows | result |
|---|---|---|
| `mixin/op.bend:799` `mo_reduce` | 36 | **ONE row moves** |
| `mixin/reduce.bend:170` | 33 | **33/33 BYTE-IDENTICAL** |
| `nn/layers.bend:190` `nn_reduce.two` | 31 | **31/31 BYTE-IDENTICAL** |
| `nn/optim.bend:751` `op_sum` | 13 | **13/13 BYTE-IDENTICAL** |

The single moving row, named:

```
< norm0=18 CONST/0 BUFFER/1 CONST/0 STACK/2 RESHAPE/2 CONST/0 CMPNE/2 CAST/1 REDUCE/1 ...
> norm0=19 CONST/0 BUFFER/1 CONST/0 STACK/2 RESHAPE/2 CONST/0 CMPNE/2 CAST/1 PERMUTE/1 REDUCE/1 ...
```

`t_norm0` is `mixin/op.bend:1304`, and it reduces **axis 1 of a `(2,2)` fixture** — a
non-leading axis, i.e. exactly the case the defect covers. It gains `PERMUTE/1` and goes
18 → 19 nodes. **Its shape does not change** (`sh_norm0=(2)(2)`, because `(2,2)` is
square), which is the port's own recurring warning about "a legal shape of the
rank-adjacent size". A row that counts nodes could not see the bug this fixes; a row that
counts nodes WILL see this fix. **That is a gate that has to move, and it should be
re-pinned in the same commit as the landing, not after.**

### 4c. `nn/layers.bend` staying byte-identical is a RESULT, not a null row

`nn/layers.bend:112-135` documents a **workaround**: `nn_reduce.two` builds
`mo_permute(t, reduce_axis ++ rest)` and then hands `T.tn_rop` the axis
`[0, …, len(reduce_axis)-1]`. So the patch could easily have **double-permuted**. It does
not, and the reason is structural: with `axis = [0..k-1]` and `rn = [0..k-1]`,
`perm = [0..k-1] ++ [k..n-1] == range(ndim)`, the identity test fires, and no second
`PERMUTE` is minted. **31/31 rows identical is the evidence that the identity test is the
RIGHT test and not merely a passing one.**

**Consequence for landing:** with this patch in, `nn_reduce`'s hand-built permute becomes
dead weight, and `nn/layers.bend:112-135`'s whole "THIS IS THE ONE PLACE A LAYER CANNOT
USE THE PORT'S OWN REDUCE" block becomes false. **I did not touch `nn/layers.bend`** — that
is a second land, after this one, and it should be its own commit.

### 4d. What I cannot tell you, and am refusing rather than guessing

* **I did not run the corpus**, so I do **not** claim a byte-identical corpus run. My
  claim is narrower and is checkable: the corpus's bend side never calls `T.tn_rop`.
* I did **not** run anything under `gates/`. **Any gate whose driver reduces a
  non-leading axis through `mo_reduce` will move**, and I have no census of those and am
  not going to invent one. `gates/tn_binop-gate.py`-style arena assertions and any gate
  pinning a `REDUCE` signature over a permuted source are the exposure.
* **`DEFECT 1` (`mixin/reduce.bend:36`) is NOT closed by this patch.** `tn_rop` still
  routes on `tn_rop.len(axis)` — the length **before** the `ne1` filter — so an all-size-1
  axis still builds `REDUCE` with `num_axes=0` where CPython builds no `REDUCE`. Three
  rows (`max_ax0_14`, `any_ax0_14`, `all_ax0_14`) stay red. **This patch removes one
  defect and leaves that one; do not read the green check-only as closing it.**

---

## 5. THE ONE ROW THAT GOT WORSE-LOOKING: `sum(-1, keepdim=True)`, AND WHY

**Symptom.** After the patch `sum_ax2kd` prints `shape=` (EMPTY). Before, it printed
`(1)(4)(3)`. **CPython says `(2,4,1)`. So BEFORE was WRONG and AFTER is SILENT — an
observability regression on that one row, and I am not presenting it as anything else.**

**Cause, MEASURED in three steps, not guessed.**

1. It is **not** the fold's inability to read a `PERMUTE` under a `REDUCE`.
   `probe3.bend` builds, in ONE arena (see §7 for why one arena matters),
   `RESHAPE(REDUCE(PERMUTE(RESHAPE(BUFFER,(2,4,3)),(2,0,1)),(ADD,1)), STACK(2,4,1))`
   and the fold **reads it**: `axis2__target241__prod_8_vs_8 root_shape=[(2)(4)(1)]`.
   Its control `RESHAPE(REDUCE(RESHAPE(B,(2,4,3))),(1,4,3))` reads `(1)(4)(3)`, and a
   deliberate product-mismatch case `…(2,4,1)` reads `[]`. So the fold's arm is fine.
2. It is a **product mismatch**, and the mismatch is on the TARGET side.
   `mixin/op.bend:781` `mo_keep_ds` is reduce.py:18's
   `1 if i in axis else s for i,s in enumerate(self.shape)`. It is the one keepdim input
   this candidate does **not** touch. `probe2.bend` prints it directly
   (`probe2-after.rows`):

   | `mo_keep_ds` over `(2,4,3)` | port | CPython `keepdim` |
   |---|---|---|
   | axis `[0]` | `(2)(4)(1)` | `(1,4,3)` |
   | axis `[1]` | `(2)(1)(3)` | `(2,1,3)` |
   | axis `[2]` | `(1)(4)(3)` | `(2,4,1)` |

   **`mo_keep_ds` answers the keepdim for the MIRRORED axis** — axis 0 and axis 2 give
   the SAME list, and axis 1 is the only one that is self-symmetric. The cause is
   `mixin/op.bend:316` `mo_at`, which is `U32.from_nat(List.length(&2, O.Sint, t))` on
   the TAIL: over a 3-list the head reads `2`, the middle `1`, the tail `0`. So the index
   counts **from the end**. `mixin/op.bend:305-315`'s own comment says the previous
   version (`len(ds) - len(t)`) was "off by one" and that `sh_sum0kd` caught it — but
   `len(ds) - len(t)` is `len(t) + 1`, so that version was ALSO wrong, and `t_sh_sum0kd`
   reduces axis 0 of a **1-D** tensor, where `len(t) == 0` and the two spellings agree.
   **That is a THIRD defect, in `mixin/op.bend`, independent of this one, and this
   candidate neither causes nor fixes it.**
3. **Why it used to look fine.** BEFORE, `tn_rop` reduced axis 0, so the REDUCE's shape
   was `(4,3)` — product 12 — and the mirrored target `(1,4,3)` is also 12.
   `fold.bend:2110`'s `reshape_ok` (used at `fold.bend:2145`) accepts it and the row reads
   `(1)(4)(3)`. AFTER, the REDUCE's shape is `(2,4)` — product 8 — against a target of 12,
   and `reshape_ok` refuses, which is **exactly what CPython does** (`resolve(prod(ps) != prod(self.marg),
   False)` RAISES). **Two defects were cancelling into a self-consistent wrong answer.
   Fixing one made the other's error visible.** The port is now *refusing* where it was
   *lying*, which by this project's own doctrine is the better of the two states — but it
   is still a missing row and it still needs `mo_keep_ds` fixed.

**So: landing this alone will turn one keepdim row from a wrong reading into an absent
one.** That is the honest cost, and it is why the orchestrator should land
**`tn_rop.perm` and `mo_at`/`mo_keep_ds` in the same commit or in immediate sequence.**

---

## 6. THE PATCH

`candidate.diff` — 114 lines, `+79 / -20`, one hunk, against
`tinybendygrad/tensor.bend:1803-1835`. Applies cleanly to `d3fbede2`
(`patch --dry-run -p1 -f` → `patching file 'tinybendygrad/tensor.bend'`).

Five new defs (`tn_rop.range.go`/`.range`, `tn_rop.in_rn.go`/`.in_rn`,
`tn_rop.rest.go`/`.rest`), one renamed arm (`tn_rop.perm.node`, which is the old
`perm.of` with a real FALSE arm), and one fold-aware dispatch (`tn_rop.perm.of`). Three
signatures change: `tn_rop.perm.of`, `tn_rop.perm` (loses `axis`, which had exactly one
reader and it was the wrong comparison), and `tn_rop.red2.of`/`tn_rop.red2`
(`U32` → `O.Found`, because the PERMUTE grows the arena).

**No caller outside `tensor.bend` changes.** `grep` for `tn_rop.perm`, `tn_rop.red2` and
`tn_rop.reduce` across the tree returns two hits and **both are comments**
(`nn/layers.bend:122`, `mixin/op.bend:1212`). The signature change is contained.

**Two comments in the port that this patch makes FALSE, and that a landing must fix in
the same commit** (otherwise the tree will cite a wrong thing, which is this project's
first doctrine):
* `nn/layers.bend:112-135` — "THIS IS THE ONE PLACE A LAYER CANNOT USE THE PORT'S OWN
  REDUCE".
* `mixin/op.bend:1210-1213` (`t_rop_gap`) and `mixin/reduce.bend:36-45` (`DEFECT 1`) —
  `DEFECT 1` stays true; `t_rop_gap`'s claim that `tn_rop.reduce` hands `self` back
  UNCHANGED is still true and still measured `False`.

---

## 7. FILES, AND TWO BROKEN INSTRUMENTS I AM NOT HIDEING

| file | what it is |
|---|---|
| `candidate.diff` | **the deliverable patch** |
| `probe.bend` | the shape/signature harness, pointed at the patched copy |
| `probe-live.bend` | the SAME file with six import lines repointed at the live tree |
| `probe2.bend` | node-by-node dump + the `mo_keep_ds` reading (§5) |
| `probe3.bend` | the one-arena isolation of the keepdim gap (§5 step 1) |
| `tinybendygrad/` | `cp -R` of the live tree, `tensor.bend` patched, **nothing else touched** |
| `probe-live-BEFORE.rows`, `probe-after.rows`, `probe2-after.rows`, `probe3-after.rows`, `checkonly-after.rows`, `op-{before,after}.rows`, `reduce-{before,after}.rows`, `layers-{before,after}.rows`, `optim-{before,after}.rows`, `STAMP.rows` | every reading quoted above |

**TWO OF MY OWN INSTRUMENTS WERE WRONG AND I AM RECORDING IT RATHER THAN THE RESULT.**

`probe3.bend`'s first two versions each built the RESHAPE in one arena and its `src` in a
**SIBLING** one (`base243()`, `keep241()`, `red_over_reshape()` each started from
`O.Arena.empty()`). The fold cannot resolve that, so both versions printed `reshaped=[]`
**for every case including the control** — and I nearly reported "the fold cannot read a
PERMUTE under a REDUCE", which the second version did NOT support. `tensor.bend`'s own
rule is "an index is legal only in an arena DESCENDING FROM the one that minted it", and
`O.Arena.merge` is the sanctioned way out; the third version builds everything in ONE
arena (`graphcmp.bend`'s `matmul_of(+ar: O.Arena)` shape) and reads `(2)(4)(1)`.

**A negative result from a broken instrument is not a result**, and the only reason I
know the fold is fine here is that I caught my own harness. Anyone re-checking §5 must
check the arena before believing the shape column.

**No `.txt` was written** — `find .agents/slop/ropfix -name '*.txt' | wc -l` → `0`.

---

## 8. WHAT I DID NOT DO, STATED AS A VERDICT

* **LANDED NOTHING.** No commit, no index write, no `git add -A`, no `reset`, no
  `rebase`. Verified the way AGENTS.md says to on this tree — `git status --porcelain` is
  unreadable here because the index is armed by design — by comparing content hashes:
  `git hash-object tinybendygrad/tensor.bend` **equals**
  `git rev-parse HEAD:tinybendygrad/tensor.bend`, and likewise for
  `tinybendygrad/mixin/op.bend` and `tinybendygrad/uop/fold.bend`. **UNCHANGED** on all
  three.
* Did not run `checks/differ.py`, anything under `gates/`, `checks/e2e*`,
  `checks/sweep.py`, `checks/bounded.py`, the 34-graph corpus, `pytest`, `mypy`, `ruff`.
* Ran `./bin/bend` one process at a time, never in the background, each well under 20s.
* **REFUSED** to state a corpus verdict. The structural claim ("the corpus's bend side
  never calls `T.tn_rop`, so zero of the 34 can change") is one grep and is the strongest
  thing I can say without running the corpus.
* **Did not fix** `mo_at`/`mo_keep_ds` (§5), **did not fix** `DEFECT 1` (§4d), **did not
  delete** `nn_reduce`'s now-redundant permute (§4c). Each is a named, separate land.
