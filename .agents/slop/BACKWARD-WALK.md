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