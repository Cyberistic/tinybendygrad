# movement: nine rules on a rewrite engine whose rules return the arena

`movement.py` is 29 lines. `mop_cleanup` is nine `UPat`s, and this unit is about
the shape a *rewriter* needs, which is not the shape `spec.py` needed. The file
is `tinybendygrad/uop/movement.bend`; `mop_len=9` says the whole table is there.

## What we gain

- **The difference between a validator and a rewriter is one data type.**
  `spec.py` answers True/False/None for one node and a verdict is enough. This
  answers a NEW UOP, so a rule returns a node and the pass has to say WHICH one.
  `Hop{ar, at}` is that, and `at == 0` is Python's `None` — which is not a new
  convention, it is `ops.bend`'s existing reserved index 0.
- **A rule RETURNS THE ARENA, not a pair**, which is what leaves one recursive
  def and no `match` on a computed value. Thirteen shapes failed before that one;
  the failure is always the same, and `spec/engine.md` has the list.
- **The one catch unique to this unit: the Hop carries the index alongside the
  arena.** `mp_hit` is the single place a freshly interned node becomes a `Hop`,
  so none of the nine rules spells `Found.ar`/`Found.i` itself.
- **A rule that does not fire must not grow the arena.** In Python the pattern
  is matched before the lambda runs, so a body returning `None` never constructs
  anything. Here the tests and the construction sit in one `match` with the
  construction in the TAKEN arm, so `grow_new=0` and `grow_same=1` pin both cases
  as two lines of difference.
- **The table's cost from `spec/engine.md` does not exist here, and the reason is
  a representation choice.** That note records that a closure in a datatype field
  forces `Type`, not `Data`, so `Rule is Data` is refused and the table is
  LINEAR and a second pass rebuilds it. `ops.bend`'s `PMEntry` is a `Data`
  record holding a TAG, so the rules are top-level defs selected by a `match` on
  the tag. The table is a `List<PMEntry>`, which is COPYABLE. `twice=1` is that
  claim, measured: the same table value, run twice, gives the same answer.
- **The price of that is nine `case` arms instead of a closure**, which is the
  price `spec.bend` already pays 84 times and argues for.
- **`ler` is computed once per pass, and here that is the cache.** `ops.bend`'s
  `pm_ler` recomputes per rule and names that as the one place the port is
  slower. In Python `ler` is `uop.__dict__['_src_ops']`. Here it is a `+`
  parameter, and not a pessimisation: the node under examination is FIXED for the
  whole pass, because every rule returns either a freshly interned node or a
  strict ancestor, and neither changes `self`'s srcs.
- **The table's `Data` and the fold's `Table` travel apart.** `F.Folded` is
  `{ar, tb}` because the fold reads its table once per SRC of every node it
  answers. Here the arena GROWS mid-pass while the table must not — a `tb` built
  on the pre-pass arena is still the right answer for every node a rule can ask
  about — so a rule takes `+tb` and the arena separately.
- **26 gate rows, both lanes byte-identical.** `mop_len=9` is a COUNT so a missing
  rule shows, and `rej_pair` is the only rule whose reject set can be longer than
  the number of srcs the arena has.

## Two facts that are easy to invert

- **`early_reject` is a NECESSARY CONDITION, not a veto, despite the name.**
  `ops.py:1609` is `if not early_reject.issubset(ler): continue`, so a rule FIRES
  when the op set IS a subset of `ler`. Eight of the nine sets here are non-empty
  and **every non-empty set is implied by its own pattern's op test**, so no
  verdict in this file is decided by the subset test. The mutation table records
  the `and`→`or` flip moving NOTHING, which is the measured proof of "implied"
  rather than an assertion about it.
- **No rule here binds a name twice, so there is no identity check to write.**
  `rg -n 'name="' movement.py` shows none twice. Adding one would be a bug: `x2`
  in `mp_1`, `mp_2` and `mp_3` is three different patterns, not a conjunction.
  (`symbolic.bend` is where the two-sided `U32.is_eq` fixtures live.)

## The wall is structural, not a missing import

`marg` (ops.py:813) and `_mop` (ops.py:821) — rule 0. `marg` needs `as_shape`,
whose middle arm is `(ssimplify(self),)` for anything that is neither a CONST nor
a STACK, and `ssimplify` is `graph_rewrite(self, symbolic)`. A rule that called
`graph_rewrite` would be the rewrite engine calling itself, which is the mutual
recursion Bend refuses. **The wall is structural.**

What IS ported is the part that needs none of it: `as_shape` restricted to CONST
and STACK-of-CONST (the two arms that never reach `ssimplify`), the `zip`, the
`(o+p, n)` arithmetic, and `_mop`'s NODE for the case where
`UOp.sink(*usrcs).simplify()` is ops.py:515's EARLY RETURN — which holds exactly
when both `shape_to_shape_arg` results are CONSTs, that is, one axis per side. So
`mp_0` fires at rank 1 and SKIPS at rank >= 2.

That is why so many rows read 0: the fixtures that would need `x.marg` and
`x.storage_base` cannot be stated, and they say so in the file rather than
printing a plausible wrong answer. `shrink2=1` and `grow_same=1` are the rows
where Python and this port differ ON PURPOSE, and `idx_shaped_bad=1` /
`unclaimed=1` are the two rows that assert absence.

Three smaller divergences, all recorded: `a.src[i.val]` is an `IndexError` Python
raises and `O.Arena.src` answers 0, which is this port's existing spelling of
exactly that; `x2.arg[i] for i in x.arg` is the same question and is unreachable
on a legal arena because `spec.py` requires a PERMUTE's arg to be a permutation
of its operand's rank; and a FLOAT CONST where an int is wanted fires in Python
(`1.0 == 1`) but not here, because `const_i64` answers `None` for a `CFloat`.

## Not done

- `movement.py:7`, rank >= 2 — `UOp.sink(*usrcs).simplify()` there sees a SINK of
  STACKs and calls `graph_rewrite`, i.e. `symbolic.py`. Measured on this repo's
  Python: at rank 2 that `simplify()` is the identity on a pure-CONST fixture,
  which is not a proof about `symbolic`, so the case is not ported.
- **THE SIX MOVEMENT SHAPES**, and this is the big one. `mp_2` tests
  `x2._shape is not None and x2.shape == x.shape` where `x` is a RESHAPE, so it
  needs a RESHAPE's `_shape`. `fold.bend`'s ladder DEFERS RESHAPE, and PERMUTE,
  EXPAND, PAD, SHRINK and FLIP with it, for the `marg → as_shape → ssimplify`
  reason above. `mp_2`'s test therefore cannot be evaluated for any node whose
  op is a movement op. It is reachable only when `x2` is something else — a
  BUFFER, an INDEX, an ALU — and `reshape_noop` is that fixture and it fires.
  What cannot be said is the case the rule was written for, a RESHAPE over a
  RESHAPE of the same shape; `mp_1` covers that one instead, which is why the
  first-wins story is about `mp_1` and not `mp_2`.
- `UOp.index` (ops.py:581) — three of the nine rules call it and it is a `TODO(p3)`
  in ops.bend.
- `dtypes.from_py` (dtype.py:100), for the float-offset-in-a-STACK case.
- `ret is not uop` (ops.py:1611) is PORTED, in `hop_self`, and **not reachable
  from any of these nine rules**: every return is a freshly interned node or a
  strict ancestor, and the arena is a DAG by construction. `ret_self`/`ret_new`
  exercise it directly because the next ported rewriter needs it.
- No mutation table — no room.

`rg "TODO\(p3\)" tinybendygrad/uop/movement.bend` is the work queue: 4 markers.