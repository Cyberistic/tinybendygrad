# BACKWARD WALK — `compute_gradient`, step 1 of 3

**What this is.** `tinygrad/mixin/gradient.py:116`'s `compute_gradient` and
`:109`'s `_deepwalk`, ported into `tinybendygrad/mixin/gradient.bend`, gated against
CPython. Steps 2 and 3 (`grad_set`, the `bw` graph) are **not** here and are not mine.

- Row: `.agents/slop/backward/walk-row.txt`
- Plant/disarm: `.agents/slop/backward/walk-plant.md`
- Harness: `.agents/slop/backward/walk-mutate.sh`
- Oracle (pre-existing, `58344623cd`): `.agents/slop/backward/oracle-cg.{py,txt}`

---

## THE HEADLINE, SIDE BY SIDE

```
                       CPython (oracle-cg.txt)                    PORT (gradient.bend)
walk_row          =     MUL/2 ADD/2 ADD/2 | grads_n=6         ==  MUL/2 ADD/2 ADD/2 | grads_n=6
                   (oracle_dag_walk  +  oracle_dag_grads_n)
```

and the rest, **15 / 15 rows agree**, all of them transcribed BY SCRIPT from
`oracle-cg.txt` and none of them typed:

| row | CPython | port |
|---|---|---|
| `walk_sig` | `MUL/2 ADD/2 ADD/2` | same |
| `walk_n_toposort` | 6 | 6 |
| `walk_walk_n` | 3 | 3 |
| `walk_inpath` | `0 0 1 0 1 1` | same |
| `walk_n_inpath` | 3 | 3 |
| `walk_grads_n` | 6 | 6 |
| `walk_keys` | `ADD/2 MUL/2 ADD/2 BUFFER/0 BUFFER/0 BUFFER/0` | same |
| `walk_skip_n` | 0 | 0 |
| `walk_hole_n` | 0 | 0 |
| `walk_grad_a` | `5 root=ADD/2 …` | same (2 of 3 fields) |
| `walk_grad_b` | `4 root=MUL/2 …` | same |
| `walk_grad_c/_p/_q/_r` | `2 root=CAST/1 …` | same |

**72 pre-existing rows are byte-identical before and after.** `claims=33`,
`recip_n=12`, `keep_pair=12`, everything.

---

## THE PLANT / DISARM, IN ONE LINE EACH

| arm | change | rows moved | `walk_row` |
|---|---|---|---|
| `plant_reverse` | `reversed(walk)` → `walk` (gradient.py:119) | **7** | moves, names itself |
| `plant_noguard` | `in_target_path[node]` → `True{}` (gradient.py:114) | **3** | moves, names itself |
| `disarm_comment` | one comment's text | 0 | correctly still |
| `disarm_name` | `dag_join`'s `tok` → `tok_renamed_for_disarm` | 0 | correctly still |

**`plant_noguard` leaves `walk_grads_n` AT 6.** The count is genuinely right under a
dropped inpath guard, so a count-only gate would have called that mutant green. That is
the measured reason the row is signature **+** count and not count.

---

## WHAT LANDED

`Itp` (the `in_target_path` lattice), `dw_read`/`dw_src`/`dw_any`/`dw_flags`/`dw_walk`
(`_deepwalk`), `Deep`, `_deepwalk`, `Grads`/`GSlot`/`gslot`/`gput` (the `grads` dict),
`CState`, `cg_puts`/`cg_hole`/`cg_sum`/`cg_ctx`/`cg_turn`/`cg_fire`/`cg_step`
(`compute_gradient`'s loop), and `compute_gradient` itself with upstream's name and
argument order.

Upstream's control flow, piece by piece:

| upstream | port |
|---|---|
| `root.topovisit(visitor, in_target_path)` | `O.UOp.toposort` + `dw_flags`, one forward pass |
| `any(in_target_path[x] or x in targets for x in u.src)` | `dw_any.go` / `dw_src` |
| `[node for node in in_target_path if op is not DETACH and flag]` | `dw_walk.go` / `dw_keep_test` |
| `grads = {root: root_grad}` | `gput.new(Grads{Nil{},Nil{}}, root, root_grad)` |
| `for t0 in reversed(walk)` | `cg_step(List.reverse(...), …)` |
| `if t0 not in grads or grads[t0].op is NOOP: continue` | `cg_turn` / `cg_ctx` / `CState.one_skip` |
| `pm_gradient.rewrite(t0, ctx=grads[t0])` | `gr_rewrite` (the table's own driver) |
| `if v is None: continue` | `cg_hole.of` / `CState.one_hole` |
| `if k in grads and grads[k].op is not NOOP: grads[k] = grads[k]+v else: grads[k]=v` | `cg_sum.*` / `gadd` / `gput.at` |

The two that are not a `def`-per-line: `_deepwalk` returns a `Data` pair (`Deep`) because
Bend has no tuple, and the shaped-edge reduce and the metadata pass are **named omissions**.

---

## THE WALLS, AT `file:line`

| what | where | why |
|---|---|---|
| shaped-edge reduce | `tinygrad/mixin/gradient.py:132-133`, ported note at `tinybendygrad/mixin/gradient.bend`'s `TODO(p3) mixin/gradient.py:132` | needs `broadcast_axes` (`ops.py:89`, reads `resolve` on a `Sint`) and `sum_acc_dtype` (`dtype.py:220`, reads `Config`). **And it is a place CPython ITSELF raises** — the oracle's second fixture dies there with `RuntimeError: cannot broadcast … into ()`, so there is no CPython answer to gate against. |
| backward metadata | `tinygrad/mixin/gradient.py:140-144` | reads `all_metadata`, a module-level dict in `ops.py`. No effect on `grads`, so no row can see it. **Named omission.** |
| `call_gradient` | `tinygrad/mixin/gradient.py:20-50` | five subsystems (`CallArg.grad_fxn`, `renumber_invalid_outputs`, `view_as`/`shard_shape`/`sharding`, two `substitute(walk=True)`). A CALL in the walk reaches gradient.py:127's refusal instead. |
| `GSkip` → `raise` | `tinygrad/mixin/gradient.py:127` | Bend cannot raise, so a node no rule claims **STOPS** the walk. Named divergence. |
| `osig`'s `srcs=` multiset | `oracle-cg.py:70-71` | the oracle sorts **alphabetically**; `Ops.value` is **declaration** order (`BUFFER` is 2, `ADD` is late) and is not a substitute. Would need an alphabetical rank for 60 ops. **Named loss**: 2 of `osig`'s 3 fields are gated. |
| the oracle's own unreachable rows | `oracle-cg.py:116` | `main()` dies at the second fixture, so `oracle_pmul`, `oracle_pmul0/1`, `oracle_seed`, `oracle_fwdwalk_n`, `oracle_fwdwalk_skipped`, `oracle_fwdwalk_a` are **never emitted**. Seven rows, named. |
| the comparator `ops.bend` was mid-edit on | `tinybendygrad/uop/ops.bend:3972` | another unit; produced one `INCONCLUSIVE` that was NOT reported as a wall. |

---

## FIVE THINGS MEASURED THAT THE PORT NOW SAYS OUT LOUD

1. **`case _ _:` FIRST IS DEAD CODE AND BENDS DOES NOT SAY SO.** `cg_puts` had its cover
   arm first; it caught every pair, the descent never ran, and `walk_grads_n` answered
   **1** with `walk_skip_n` **2** instead of 6 and 0. A wrong walk and a dead arm are the
   same silence. Notes rule at position 1620 already said so; the two counters are what
   told them apart.
2. **`size1` IS NOT A TOPOSORT COUNT.** `size` is `1 + sum(size(s))`, so a SHARED subtree
   is counted once per path; `len(u.toposort())` counts it once. They agree on every
   `*_n` row already in this file **because every one of those fixtures is a tree**, and
   they part company exactly where the ACCUMULATE creates sharing: `grads[a] = seed +
   (b*seed)` read **7** where CPython reads **5**, with the right `root=ADD/2` either way.
   The new rows count `O.UOp.toposort`.
3. **THE WALK'S VALUES LIVE IN THE WALK'S ARENA, NOT THE FIXTURE'S.** `walk_grad_a` and
   `walk_grad_b` read their value indices out of the FIXTURE arena, so `Arena.at` missed
   and `size1` answered `Arena.bottom()` → `1 root=NOOP/0`. Two rows that looked like
   signatures and were a wrong arena (notes T-4).
4. **A `case Some{sl}:` BINDER CANNOT CALL A DEF DECLARED LATER IN THE FILE.** MEASURED in
   six lines; the error is "expected : a filled definition (an unfilled law is a dead
   claim)", which names the CALLER's condition and mentions no recursion. The rule is
   absolute — callees before callers, always — so `cg_sum` had to be written
   `done → grow → noop → add → put`.
5. **A TWO-SCRUTINEE `match`'s SCRUTINEES MUST BE IN PARAMETER ORDER.** `match ns fs:` over
   `(fs, ns, …)` is "a match on a parameter or field (this name is a def or a consumed
   binder)", naming the second scrutinee. And with the flag lists in LOCKSTEP the position
   index is not needed at all — the head **is** `flags[i]`.

---

## WHAT IS *NOT* CLAIMED

- The **EXPAND** fixture is not here. It is the one that would exercise gradient.py:130's
  HOLE and gradient.py:120's SKIP for real, and **CPython cannot compute it** (the
  `RuntimeError` above). `walk_hole_n=0` and `walk_skip_n=0` are facts about the DAG
  fixture and are not a coverage statement about the other.
- `walk_grad_*` pins the count and the root, not the `srcs=` multiset. Two thirds of
  CPython's `osig`.
- Nothing outside `tinybendygrad/mixin/gradient.bend`, `.agents/slop/backward/`, and the
  two append-only note files was touched. **Nothing was committed.**
---
---

# BACKWARD ZIP -- `backward`, step 2 of 3. `tinybendygrad/tensor.bend`.

**What landed.** `tensor.py:951`'s `TODO(p3)` is gone. `backward`'s zip is ported, it
calls `mixin/gradient.bend`'s `compute_gradient`, and **`Tensor.grad_set` now has a
caller** — it was dead for the whole session.

| | |
|---|---|
| Row | `.agents/slop/backward/bwd-row.txt` (35 rows) |
| CPython lane | `.agents/slop/backward/bwd-oracle.py` -> `bwd-oracle.txt` |
| Plant/disarm | `.agents/slop/backward/bwd-mutate.sh <arm>` |
| Mutation table | `tensor.bend`'s footer, M18-M20 |

---

## THE ROW, AND ITS CPYTHON VALUE, SIDE BY SIDE

```
                     CPython (bwd-oracle.txt)                                       PORT (tensor.bend)
tn_bwd_row      =  CONST/0 BUFFER/0 MUL/2 ADD/2 BUFFER/0 CONST/0 MUL/2 CONST/0      ==  (byte identical)
                   | writes=3                                                             | writes=3
tn_bwd_grad     =  CONST/0                                                          ==  CONST/0
```

Both lanes `diff` clean. **33 pre-existing rows are byte-identical**, `ALL PROOFS CHECK`,
interpreted and native lanes agree. **35 rows total.**

`tn_bwd_row` is TWO-PART and it is the shape of the walk's `MUL/2 ADD/2 ADD/2 | grads_n=6`:
a **signature** (which gradients came back, in what order) and a **count** (how many
`.grad` writes the zip performed). They are two different objects — `Bwd.gs` is built by
`tn_bwd_gs` from `grads` and `tensors_need_grad`; `Bwd.ts` is built by `tn_bwd_pair`
walking the zip — and the harness prints **each half's verdict separately**.

---

## THE MUTANT THAT SEPARATES THE HALVES, MEASURED

| arm | the edit | `writes` | signature | verdict |
|---|---|---|---|---|
| `base` | -- | **3** | `CONST/0 BUFFER/0 MUL/2 ADD/2 BUFFER/0 CONST/0 MUL/2 CONST/0` | -- |
| `plant_revzip` | `tn_bwd_gs.go`: `[slot] ++ tail` -> `tail ++ [slot]` | **3** (UNCHANGED) | **PERMUTED** | **the COUNT half is BLIND** |
| `plant_nowrite` | `tn_bwd_write.go`: drop the `grad_set` answer | **0** | **UNCHANGED** | **the SIGNATURE half is BLIND** |
| `plant_nogradu` | `tn_need_grad.is_float.go` -> `True{}` | **4** | 4th slot appears | both halves move |
| `disarm_comment` | a comment's text | 3 | unchanged | 0, as designed |
| `disarm_name` | `tn_bwd_last.sig`'s `ws` -> `ws_renamed_for_disarm` | 3 | unchanged | 0, as designed |

**`plant_revzip` is `List.append(a, A, acc, [x])`'s own trap**, and the two arms are the
proof it is worth a row's second field: a count-only row calls `plant_revzip` green (3 is
3), and a signature-only row calls `plant_nowrite` green (the answer list is built BEFORE
the zip and is untouched by it). Neither half alone does.

**`plant_nowrite` IS THE BUG THIS UNIT EXISTED TO FIX.** It is a `Tensor.grad_set` that is
called and whose answer is dropped — precisely the state the file shipped in: a def for
setting `.grad`, no caller, and no reader.

---

## `INCONCLUSIVE`, not PASS/FAIL

`bwd-mutate.sh` carries the fourth verdict forward and adds a fifth.

* **`INCONCLUSIVE (T-1)` — the substrate moved.** A sha256 ledger over five closure files
  (`mixin/gradient.bend`, `uop/ops.bend`, `uop/fold.bend`, `helpers.bend`, `LAWS/spec.bend`)
  is taken before the copy and re-checked twice per arm, before and after the run. Any
  difference prints `INCONCLUSIVE (T-1)`, the offending file, and the stderr. **This fired
  for real**: the live tree carried a leaked M2 plant in `tensor.bend` while this unit ran
  (below).
* **`INCONCLUSIVE (T-3)` — an unproven plant.** A `plant_*` arm whose edit is verified on
  the bytes but produces **no row diff** is reported as INCONCLUSIVE, not as a `0`. A
  mutation that moves nothing is a result only once the plant is proven; the two are
  different sentences. A `disarm_*` arm with no diff is the EXPECTED result and is
  reported as one.
* **Byte assertion, on the bytes.** Every edit asserts `back != s` AND `new` occurs once on
  disk AND `new` did not occur before. **The harness's second version asserted
  `old not in back` and was WRONG for a comment disarm** — `new` extends `old`, so a
  perfectly good replace left `old` inside `new` and the assertion refused a good edit.
  It fired for real and is recorded in the script's comment, because that is the same
  class of error as the walk harness's `s.count(old)`-without-`s.replace`.

---

## WHAT IS PORTED, AND WHAT IS NOT

| upstream | port | state |
|---|---|---|
| `tensor.py:487` `tensors_need_grad` | `tn_need_grad` | **pre-existing.** 2 of 3 `and` terms: `uop in all_uops` and `is_floating_point`. **`t.device is not None` is NOT PORTED** — a port `Tensor` has no device field. Unseeable by any row here, because every fixture is device-less. **Named gap.** |
| `mixin/op.py:471` `grads[x] if x in grads else x.const_like(0)` | `tn_bwd_slot` | **ported**, `x in grads` is `G.gslot`, `grads[x]` is `G.GSlot.v_of`. |
| `mixin/op.py:471`'s comprehension over `target_uops` | `tn_bwd_gs` | **ported**, in target order. |
| `tensor.py:490` `zip(...)` | `tn_bwd_pair` | **ported**, two-scrutinee `match`, three terminating arms because `zip` stops at the shorter list. |
| `tensor.py:493` `t.grad = g` | `tn_bwd_write` -> `Tensor.grad_set` | **ported. THE WRITER NOW HAS A CALLER.** |
| `tensor.py:492` `g.clone(device=t.device)` | -- | WALL 2, `UOp.clone` is ops.py:882 |
| `tensor.py:494` `t.grad.assign(t.grad + g.to(...))` | -- | `assign`'s other eight arms + `__add__` |
| `mixin/op.py:468` `const_like(1.0)` seed | `root_grad` is a PARAMETER | float CONST, tensor.bend's second wall |
| `mixin/op.py:465-467` the three guards | -- | refusals; `tn_len`'s `Maybe` shape |

---

## THREE THINGS MEASURED THAT THE PORT NOW SAYS OUT LOUD

1. **`mixin/op.py:471`'s `else x.const_like(0)` ARM IS NOT EXERCISED BY ANY ROW HERE.**
   On this fixture all three targets have gradients, so `tn_bwd_slot`'s `case _: 0` never
   fires and the `ZERO` token never prints. It is a **request for a fixture, not coverage**:
   a float target whose gradient is a HOLE. MEASURED dead ends, not guesses: a DETACH
   target (`x.detach().sum()`) does produce the substitute in CPython, but the port's walk
   keeps the DETACH where CPython's drops it, so the two lanes cannot be compared there;
   and a non-folding BITCAST's source is a hole but the source is `weakint` or `int64`, so
   the filter drops it first. **Named blind spot.**
2. **A SCALAR SEED OVER A SHAPED GRAPH IS A PLACE CPython ITSELF DIES**, so the fixture is
   scalar-shaped. `x = Tensor([1.,2.,3.,4.])`, `t = (x*3).sum()` raises
   `RuntimeError: cannot broadcast (4,) into ()` at `gradient.py:133` — the same
   shaped-edge wall the port names, and the reason `g_sbuf` (a size-less scalar BUFFER)
   exists alongside `g_buf`. Scalar shapes are the only place **both** lanes answer.
3. **THE WRITE LIST'S ORDER IS A BUG NO COUNT CAN SEE, AND `tn_bwd_grad` CAUGHT IT.**
   `tn_bwd_pair.go` built `acc ++ [new]`, which is the write list **reversed**: `writes`
   stayed 3 and `tn_bwd_row`'s signature was untouched, because the signature comes from the
   ANSWER list and never reads `ts`. `tn_bwd_grad` reads the last written `.grad` and
   printed the wrong node. Two of the three bugs this unit wrote into its own file were
   invisible to the row's count field — which is the argument for the third row.

---

## THE WALLS, AT `file:line`

| what | where | why |
|---|---|---|
| `t.device is not None` | `tinygrad/tensor.py:488` | a port `Tensor` has no device field; every fixture is device-less so no row can see it. **The filter is 2 of 3 terms.** |
| shaped-edge reduce | `tinygrad/mixin/gradient.py:132-133` | `broadcast_axes` (ops.py:89). **And CPython raises there** on a scalar seed over a shaped graph — measured, `cannot broadcast (4,) into ()`. |
| the `ZERO` substitute | `tinygrad/uop/ops.py:600` (`const_like`) | `UOp.const(0, f32)` needs a float literal; `F32{data: Word(32n)}` has no reachable constructor from `tensor.bend`. |
| `g.clone(device=...)` | `tinygrad/tensor.py:492` | WALL 2, `UOp.clone` is ops.py:882 |
| the accumulate arm | `tinygrad/tensor.py:494` | `assign`'s other eight arms + `__add__` |
| the seed | `tinygrad/mixin/op.py:468` | `const_like(1.0)`; `root_grad` is a parameter instead. MEASURED: the gradient graph is IDENTICAL for a float `1.0` seed and an int `1` seed on a fixture with no f32 CONST — both read `CONST/0`. |

### TWO WALLS REPORTED AGAINST OTHER UNITS, NOT FIXED

* **`dw_keep_test` does not drop a DETACH.** `mixin/gradient.bend:1188`'s
  `Bool.and(f, Bool.not(O.op_is(ar, x, O.OpsDETACH{})))` reads `True and False` on a real
  DETACH, so the walk is `[DETACH, REDUCE]` where CPython's is `['REDUCE']` — MEASURED on
  both sides, and the primitives were measured too (`Bool.and(True{}, Bool.not(True{}))` is
  `False`). `dw_keep_test`'s DETACH term is **not exercised by the walk unit's own gate**,
  whose fixture has no DETACH. That is why the `backward` fixture cannot be the DETACH one.
  **NOT FIXED — the file is another unit's and committed.**
* **A LEAKED PLANT WAS LIVE IN `tensor.bend` WHILE THIS UNIT RAN.**
  `tensor.bend:593` read `case _: tn_shape_arg.k(ys, ar, False{})` — that is mutation **M2**
  of `.agents/slop/tensor-mutate.py`, planted and never reverted: no `tensor-mutate`
  process was running, the mtime was 27 minutes old, and the hash was stable across a
  45-second re-read. `tn_mop_exp` and `tn_mop_shr` were printing
  `BUFFER/0 CONST/0 STACK/1 EXPAND/2` and `BUFFER/0 CONST/0 STACK/1 CONST/0 STACK/1 SHRINK/3`
  where CPython reads 3-node and 4-node graphs. **The hash this unit was told to confirm
  did not match the tree.** Copying this unit's file over it restored the line AND landed
  the zip; if a `tensor-mutate.py` run was in flight, it will now re-plant.
