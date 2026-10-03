# `LAWS.bend` induction unit — six open laws, measured

**Gate:** `./bin/bend tinybendygrad/LAWS/PROOF-ALL.bend --check-only`, read the FIRST LINE.
`--check-only` exits 1 on a clean file, so the exit code is never the verdict.

| | first line | second line |
|---|---|---|
| before | `SOME PROOFS FAIL` | `Error: 6 TODOs found.` |
| after  | `SOME PROOFS FAIL` | `Error: 2 TODOs found.` |

`6 -> 2`. Stable over six consecutive runs and under `--verdict` (the Lean kernel).

## The four closed

| law | closed by |
|---|---|
| `stack_numel_is_the_leading_axis_times_the_operands` | `stack_numel_go(k, m)` applied at `k = 1n + \|rest\|` |
| `add_is_elementwise` | `%premise` rewrite, then `zip_maybe_idem` |
| `mul_is_elementwise` | same two steps |
| `max_is_elementwise` | same two steps |

All four keep their ORIGINAL quantifiers and conclusions — `LAWS.bend` and
`LAWS/spec.bend` are byte-identical to `HEAD` (`git diff --stat HEAD` is empty for
both, and `PROOF2.bend` is untouched). Only `tinybendygrad/PROOF.bend` changed.

## The chain

```
nat_max_idem            Nat.max(v, v) == v                     induction on Nat
  L.max_dim_idempotent  Shape.max_dim(x, x) == x               SS reflexive, SN via ^
    L.zip_max_idempotent  zip_max(s, s) == s                   induction on the dim list
      zip_maybe_idem       dims_zip_max(m, m) == m             2 congruences, above
        add/mul/max_is_elementwise
nat_mul_zero_r          Nat.mul(k, 0n) == 0n                   induction on Nat
  stack_numel_go        dims_prod(stack(m,k)) == k * dims_prod(m)
    stack_numel_is_the_leading_axis_times_the_operands
```

## Why a helper and not a better motive

A law's binder is symbolic and `match` may not scrutinise a call, so
`dims_zip_max(Sp.shape(a), Sp.shape(b))` and
`dims_prod(on_shape(Sp.shape(t), sh => ...))` never reduce. Moving the induction
into a def whose parameter IS the shape lets its body `match` it, and the law body
becomes one application. That is the whole fix; the motives did not move.

## The two left open — both FALSE as written, not stuck

`p3-counterexamples.txt`, from `p3.bend`, which mirrors `LAWS.bend`'s helper
bodies verbatim and evaluates both sides on concrete nodes:

```
  reduce_numel_divides_by_the_reduced_axes, AS WRITTEN --
  t=(4,)     n=0n    LHS=1   RHS=4      False
  t=(4,5,6) n=1n    LHS=36  RHS=120    False
-- the same law with the multiplier the NAME describes --
  t=(4,)     n=0n    LHS=4   RHS=4      True
  t=(4,5,6) n=1n    LHS=120 RHS=120    True
-- broadcast_is_elementwise_max --
  a=(2,3) b=(3,3)    LHS=9   RHS=9      True
  a=(SS,5) b=(3,7)   LHS=21  RHS=0      False
  a=(5,0) b=(3,)     LHS=3   RHS=0      False
```

* `reduce_...`: the multiplier is the count of the axes that were KEPT. Swap that
  one term and it is true.
* `broadcast_is_elementwise_max`: `dim_of(SS{x}) = 0n` and the law quantifies over
  all of `Sp`, so a symbolic axis or a zero breaks it.

Both fixes are `LAWS.bend` edits: **owner ruling.** Neither was closed by weakening.

## Bonus finding, no law covers it

`LAWS/spec.bend`'s `drop_n(ds, n)` drops `n + 1` dims, not `n` (`p3.bend` measures
2, 1, 0 dims kept on (4,5,6) at n = 0, 1, 2; `List.drop` keeps 3, 2, 1). So
`Shape.drop(sh, 0n)` removes an axis against tinyspec's "Reduce the first n axes",
and an `Index` of arity 1 over a rank-3 base has rank **1**, not 2. **Spec change:
owner ruling.**

## Mutation table

`mutation-table.txt`, from `mutate.py`, run against the byte-identical copy in
`mut/` so the live tree was never opened for writing.

| id | mutation | gate |
|---|---|---|
| C1 | CONTROL: reword one comment, touch no code | **SAME** (must be) |
| M1 | `nat_max_idem` base case claims `max(0n,0n) == 1n` | RED |
| M2 | `nat_max_idem` step motive drops the `+1n` | RED |
| M3 | `max_dim_idempotent` SN case stops reaching `nat_max_idem` | RED |
| M4 | `zip_max_idempotent` BASE case (Nil) asserted, not proved | RED |
| M5 | `zip_max_idempotent` step congrues `x`, not `max_dim(x,x)` | RED |
| M6 | `of_shape` drops one dim instead of wrapping | RED |
| M7 | `zip_maybe_idem` Some case replaced by bare `{==}` | RED |
| M8 | `nat_mul_zero_r` claims `k*0n == 1n` | RED |
| M9 | `stack_numel_go` statement drops the leading-axis factor | RED |
| M10 | stack law: leading axis becomes `\|rest\|`, not `1n + \|rest\|` | RED |
| M11 | `add_is_elementwise`: premise rewrite deleted | RED |
| M12 | `mul_is_elementwise`: lemma applied to `b`'s shape | RED |
| M13 | `max_is_elementwise`: premise rewrite aims at the wrong side | RED |
| M14 | **one of the 28 pre-existing proofs deleted** | count 2 → **3** |

`RESTORED: 'SOME PROOFS FAIL' 2 TODOs -- matches baseline: True`

M14 is the row that certifies the other 31: the TODO counter is one per unfilled
law, so `2 TODOs` together with `34 laws, 32 defs` is what says the 28 that were
green before this unit are still accepted.

## Files

| file | what it is |
|---|---|
| `mutate.py` | the harness; asserts bend printed rows and that C1 does not move |
| `mutation-table.txt` | its output |
| `mut/` | byte-identical copy of the 5-file proof set (`md5`-checked) + `PROOF.pristine.bend.txt` |
| `p3.bend`, `p3-counterexamples.txt` | the counterexamples and the `drop_n` measurement |
| `p6.bend`, `p6-open-goals.txt` | bend's elaboration of the reduce law's goal |
| `p7.bend`, `p7-open-goals.txt` | bend's elaboration of the broadcast law's goal |
| `p8.bend`, `p8-broadcast-attempt.txt` | the natural attempt at the broadcast law, refused |
| `base.txt` | the `6 TODOs found` line, captured before any edit |

`jj diff --summary` lists `C {tinybendygrad => .../mut}/PROOF.bend`: that is jj's
copy detection on identical bytes in `.agents/slop`, not a move. `PROOF.bend` is
present and modified in place.