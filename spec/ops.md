# ops: the UOp arena

## What ops.py does

It hash-conses UOps. `UOpMetaClass.__call__` keys a dict on
`(op, src, arg, tag, type(arg))` and hands back the cached object, which is why
`UOp.__eq__` is identity and why the test suite uses `assertIs`. The graph is
**cyclic** — a SPECIAL's end is a symbolic uop, an END's `src[0]` is the body it
closes over — and every derived property is a `recursive_property` that
memoises on `node.__dict__`.

`ops.py` is 1928 lines: the op enum, the dtype and shape production rules, ~100
syntactic-sugar constructors, the symbolic helpers (`divides`, `gcd`,
`divide_exact`, `_min_max`, `const_factor`), the pattern matcher, and the graph
rewrite engine.

## What the Bend file does instead

A UOp is a `U32` index into an append-only `List<Node>`, threaded through every
function that touches the graph as its first parameter. The store is a `List`
because `Array<T>` masks its index (`Array.get` computes `i & (n-1)`), so
`Array.set` cannot grow a table, and `Array.fork` / `Array.atomic.*` are
`@unsafe` or unfilled laws. Index 0 is reserved for the arena's bottom, which is
the port's `None` UOp and its `IndexError`. Hash-consing is a linear scan for a
node with the same key, which is the same information as the dict and the same
observable behaviour, computed in O(n) instead of O(1).

The two `Any` fields became datatypes: `Arg` names all eighteen things `arg`
holds, `Tag` names the five it holds. That is the one place this encoding is
strictly better than Python — every read of `self.arg` is now a match the
compiler checks against the full set.

## The gate

```
$ ./bin/bend tinybendygrad/uop/ops.bend
hashcons=True
dtype_key=True
cycle=True
toposort=True
cycle_terminates=True
key_eq=True
$ ./bin/bend tinybendygrad/uop/ops.bend -o /tmp/ops && /tmp/ops
hashcons=True
dtype_key=True
cycle=True
toposort=True
cycle_terminates=True
key_eq=True
```

**The arena works.** A cyclic graph in a Bend arena, with identity, sharing and
back-edges, and no `@unsafe`.

## What we gain

- `UOp.__eq__` identity is a `U32` comparison instead of a reference compare.
- Node identity is free to copy: a `U32` is `Data`, so a handle into the arena
  costs nothing, where a Python UOp costs a refcount.
- The `arg` and `tag` unions are compiler-checked. A wrong arm is a type error,
  not an `AttributeError` at 3am on a GPU.
- A `UOp.MetaClass` cycle in the graph is representable, so the range graph's
  back-edges need no `weakref` bookkeeping and no `__del__`.
- The `Ops` enum's declaration order is the toposort order, and it is one list
  of constructors rather than an `auto()` chain plus a dict of letter names.
- A topologically-ordered walk is a fuel countdown on a worklist, and the
  budget that bounds it is a `Nat` in the signature rather than a hidden
  recursion limit.

## What we do NOT claim

- **The property folds are not ported.** `dtype`, `_shape`, `device`,
  `addrspace`, `_ranges`, `_min_max`, `key`, `axis`, `marg`, `ended_ranges`,
  `bool_slice`, `backward_slice`, `trace_num`, `tuplize` and `vmin`/`vmax` are
  inventoried as `# TODO(p3) ops.py:N`, not written. Two Bend rules stop them,
  and both are measured:
  1. a self-call must pass a **field of its own parameter**, and the arena's
     field is a `U32` read back out of a store, which the checker cannot see as
     a subterm; and
  2. mutual recursion is refused, and `dtype_from_uop` ↔ `_shape` ↔
     `simplify()` → `graph_rewrite` → the rules → `dtype` is a cycle that
     Python only breaks with the `recursive_property` memo.
- **`UOp.const` is partial.** The `dtype=` resolution, the `truncate`, and the
  `.cast` on top are not ported, so a CONST of int32 is one node here and two in
  Python. The def says so.
- **The `recursive_property` memo is dropped.** Recomputing a diamond DAG is
  exponential in its depth. That cost is real and it is why (1) and (2) above
  cannot be fixed by putting the memo back: the cycle is in the *code*, not in
  the cache.
- **A `RuntimeError` is a value, not a raise.** Every `raise` site in ops.py has
  its exact message on a comment and becomes a `Maybe`, a `Bool`, or a `Found`
  carrying the old arena. Nothing is silently swallowed, and nothing is silently
  different: each is a comparison-table row.
- **`graph_rewrite` is not ported**, so `simplify`, `ssimplify`, `substitute`,
  `contiguous_view`, `contract` and `_rop` are not either. The engine is P3 and
  it is where the cycle above has to be broken.
- **`./../dtype.bend` is not imported.** The gate says "must reach zero errors",
  and importing `dtype.bend` makes that impossible for any file: its fp16 /
  bf16 / fp8 / i64 C effects are foreign code, so the checker prints
  "14 defs rely on unsafe or foreign code" and exits 1 whatever the importer
  does — a two-line file that imports it and does nothing else prints the same
  fourteen lines. So `Dt` comes from `./LAWS/spec.bend`, which is the ONE
  datatype and is what `dtype.bend` itself uses. The two `dtype.py` functions
  `ops.py` needs and `dtype.bend` has — `least_upper_dtype` and `DType.min` /
  `DType.max` — land with the folds that call them, and the import comes back
  with the notice. There are no `@unsafe` defs here; the only two occurrences of
  the word in the file are in prose.
- **The oracle for this unit is not tinygrad's pytest.** ops.py's tests are
  Python-object tests (`assertIs`, `id()`, `repr` strings), and this port has no
  Python objects. The six printed answers are the gate; tinygrad's suite becomes
  the oracle when `test/` can drive a Bend build, which is P9.

## What the plan has to decide next

The cycle is real and it is a **module** problem, not a file problem:
nothing in the rewrite engine may call back into the property fold, and the fold
must answer dtype and shape together because they are mutually recursive. So:

- one fold, `Derived{dt, shape}`, driven by a Kahn worklist over the arena —
  the same shape `toposort` already has, whose recursion *is* on list fields;
- `graph_rewrite` and the pattern matcher in a **separate module** from that
  fold, with rules as top-level defs dispatched by an explicit tag, so the
  dependency is one-way (rules → fold, never fold → rules); and
- if `simplify()` inside the fold is still wanted, the memo comes back as a
  second parallel store and the fold stops being a fold. That is the trade, and
  it is P3's to take.

## Files

| file | what |
| --- | --- |
| `tinybendygrad/uop/ops.bend` | the arena, `Ops`/`GroupOp`/`AxisType`/`ParamArg`/`Arg`/`Tag`, the ucache, the graph walks, the sugar, the gate |
| `.agents/slop/notes/compare/uop-ops.md` | the def-by-def table, 189 Python rows |
| `.agents/slop/notes/bend2-constraints.md` | the Bend rules that shaped all of it |
| `spec/laws.md` | the pure spec half, which is a tree and therefore does reach the checker |
