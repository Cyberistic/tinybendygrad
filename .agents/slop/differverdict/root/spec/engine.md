# The engine shape: what a rewrite rule table costs in Bend

`uop/spec.py` is the critical path. `schedule/` is 1500 lines written against the
rewrite engine, and VIZ is a debugger for it. Its shape was the last big unknown,
so I built a runnable model instead of designing it in my head.

The model is `.agents/slop/notes/engine-shape.bend`. It checks clean and runs.

## The shape

```bend
type Arena is Type: Nodes{items: List<&2, U32>}
type Rule  is Type: R{use: (Arena -> Arena)}

def engine_pass(rules: List<Rule>, a: Arena) -> Arena:
  match rules:
    case Nil{}: a
    case R{use} <> rest: engine_pass(rest, use(a))
```

**One recursive def. No helper. No ctx.**

## What we gain

**`spec.py` is close to a 1:1 transliteration.** The rules stay lambdas, the
patterns stay a datatype, `graph_rewrite` stays a def. An earlier draft of this
project prescribed restructuring every rule into a top-level def threading an
explicit context, on the belief that closures cannot capture affine values. That
belief is false — a closure captures an affine `Nat` perfectly well — and acting
on it would have cost the thing that makes the port tractable.

**The rules mutate the arena, and ownership says so.** The arena is `Type`, so a
rule consumes it and returns the new one. That is not a workaround: applying a
rule *grows* the arena, so ownership should move with it. In Python the arena is
a shared list and nobody thinks about this; here the type system states it.

**Verified, not asserted.** The model's rules genuinely grow the arena. Two
passes leave it as `[2, 7]`, so threading works, the table really is rebuilt, and
the engine really is re-runnable — which is exactly what `graph_rewrite`'s
fixpoint loop needs.

## The one cost

**The table is linear, so a second pass rebuilds it.** A function value in a
datatype field forces `Type`, not `Data` — `Rule is Data` is rejected outright.
So `graph_rewrite` cannot take the table as a parameter; it builds one, or takes
a thunk. One call site.

## Why the obvious shape fails

Thirteen shapes failed before this one, and they all failed the same way. A rule
returning `(Arena & U32)` *works* — but then the pass must `match` on the rule's
result, and:

- `match apply(r, a):` — refused, a match may not scrutinise a computed value
- giving it a helper def — the helper must call back into the pass, which is
  mutual recursion, also refused
- ordering the helper above the pass — moves the error to
  `expected a filled definition ... observed use_go`

Returning the arena deletes the destructuring, so there is no helper and no
cycle. The lesson is narrow and worth keeping: **when a value's *fields* are what
you need to recurse on, don't pack it into a pair.**

Three more measured rules, all in the constraints notes:

- a rule destructures as `case R{use} <> rest:`, not a nested `match`
- a `match` cannot head a *lambda body* either, so a rule with a body calls a
  named helper declared above it
- a def may only call defs above it, which fixes the helper order

## What we do not claim

**This is a model, not a port.** It has two rules and no patterns. `UPat` matching,
the `spec` dictionary, `PatternMatcher`, and `graph_rewrite`'s fixpoint loop are
all still to be written, and each may hit a wall this shape does not expose. What
is settled is the *cost*: one recursive def and one rebuilt table, not a
restructured rule language.

**No O(1) lookup.** Unrelated to the above and still open: the arena is a `List`,
so indexed reads are O(n) and the Kahn fold is O(n²). `Map` exists but is
string-keyed and O(log n), so it is not a free win. Measured and left alone until
there is a profile in front of us.

## The actual port (2026-10-03)

The model above is the SHAPE that was ported, not the SHAPE that
shipped. The first port tried a `Type`-with-rule-body shape and got
blocked by the third of the "thirteen shapes" above. What shipped
instead is a different machine: the rule body's *tag* selects a
top-level def, and the table itself is a `Data` record of tags, ops
and reject sets.

```bend
type PMEntry is Data:
  PMEntry{tag: U32, ops: List<&2, Op>, rej: List<&2, Op>}

type PMEntrys is Data:
  PMEntrys{es: List<&2, PMEntry>}

def pm_r_sink_m(ar: Arena, self: U32) -> Maybe<&2, U32>:
  Some{self}

def pm_dispatch_m(tag: U32, ar: Arena, self: U32) -> Maybe<&2, U32>:
  match tag:
    case 0: pm_r_sink_m(ar, self)
    case 1: pm_r_noop_m(ar, self)
    case 2: pm_r_cast_m(ar, self)
    case _: None{}
```

**The rule body is a top-level def.** Three consequences, all of them
things the interpreter could not do:

* THE TABLE IS `Data`, SO IT IS COPYABLE. `PMEntry` is read by the scan
  and by `early_reject` in the same pass, with no `+` and no linear-table
  workaround. A table of closures forces `Type`; a table of tags does
  not.
* A RULE MAY READ THE ARENA AS OFTEN AS IT LIKES. A closure cannot take
  a shared argument -- there is no spelling of one in a function type
  -- so an interpreter rule could not receive `+Arena`. A def can.
* A RULE'S CAPTURES ARE ITS OWN PARAMETERS. No store, no `setdefault`,
  no cartesian product, and `is_any` is a DISJUNCTION rather than a
  flatten.

The cost is the dispatch: Bend has no first-class functions, so a tag
selects a top-level def through a `match`. One `case` per rule. For
`spec.py`'s 82 rules that is 82 cases, which is the trade the master
plan's LOC rule cares about -- more lines, in exchange for rules that
are individually readable and individually gateable.

The engine that drives the dispatch is `walk_rewrite` in
`tinybendygrad/codegen/__init__.bend`: a fold over a toposorted list
threading a `+Arena` and a `+Map<&2, U32>` replace store, with a
per-node "seen? scan? mint? rebuild?" step. The fold's shape is the
`consumers.go`/`consumers.step` pair in `uop/render.bend:1787`, which
proved that a `+` on the list head and the next-node call on the tail
satisfies Bend's descent check.

**OUTSTANDING.** The fixpoint driver (`unified_rewrite`) and the
dispatcher (`graph_rewrite`) are still walls. A `pm_post_sched_cache`
table with its two rules (`UPat(Ops.PARAM, ...)` and
`UPat(Ops.ALLOC, ...)`) is the smallest test case; a CPython oracle
that runs the same fixture through CPython's `graph_rewrite` and
diffes the op/src/arg of each node is the gate, and it is not built.

**BEND NAMING RULE, observed during this port and worth its own section
in the constraints notes (R-3).** A sub-namespace def (`name.subname`)
must be declared BEFORE the parent `def name` that calls it. The
reverse order compiles, but every call to the sub-def is reported as
"an unfilled law is a dead claim: live code cannot use it" -- a
useful error once you know what it means, hostile until you do.
`uop/fold.bend` obeys it (`fold.dt.of` at line 713, `fold.dt` at
4041); the engine in `codegen/__init__.bend` obeys it (leaves first,
parents last). When you need a helper, declare it BEFORE the caller.
