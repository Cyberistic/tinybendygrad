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
