# THE PORT BRIEF

Read this whole file before writing any code. It is the shared half of six
concurrent port tasks; your own unit is appended to it.

## Repo and rules

Repo: `/Users/cyberistic/src/tries/2026-09-30-tinybendygrad`. This is a mechanical
1:1 port of tinygrad from Python to Bend 2.

- `tinygrad/foo.py` <-> `tinybendygrad/foo.bend`. SAME split, same def order, same
  comments.
- Keep upstream's `# NOTE:` comments. Adapt comments; do NOT rewrite them into prose.
- No new abstractions. If a Python function is a function, it is a def. LOCs is a
  measure of quality: fewer is better.
- **Create ONLY the one .bend file named in your unit.** Other agents and I are in
  the same tree RIGHT NOW. `ops.bend`, `fold.bend`, `spec.bend`, `sz.bend` are
  READ-ONLY to you. If you believe one is wrong, REPORT it — do not edit it.
- Do NOT commit. Leave the file in the working copy.

## Build and check

    cd /Users/cyberistic/src/tries/2026-09-30-tinybendygrad
    ./bin/bend <yourfile> --check-only            # must print ALL PROOFS CHECK
    ./bin/bend <yourfile>                         # interpreted
    ./bin/bend <yourfile> -o /tmp/x && /tmp/x      # native

Both lanes must run and print identical output. `bin/bend` wraps bend 2.0.34.

## The substrate is BUILT and PROVEN. Read before writing.

- `tinybendygrad/uop/ops.bend` (~3800 lines, green) — `Arena{nodes: List<&2,
  Node>}`, UOps as `U32` indices threaded through everything. `Node{op, dt, arg}`.
  `type UPat`/`UpAlt`/`SrcArg`/`Pat`/`PatFound` with 23 of 28 methods ported. And
  `PatternMatcher` in its COMPILED form: `PMEntrys`, `PMEntry{tag, ops, rej}`,
  `pm_rewrite`, `pm_scan`, `pm_try`, `pm_dispatch`, `pm_when(cond, v)` (=
  `if cond: v else None`), `pm_keep`, `op_is`, `op_in`, `src_op`, `pm_ler`,
  `type Verdict` (`VTrue`/`VFalse`/`VSkip`). Import: `import ./ops.bend as O`.
- `tinybendygrad/uop/fold.bend` (2208 lines, green) — derived properties as a
  Kahn worklist: `type Table`, `Resolved`, `Derived{dt, shape, dev, addr, base,
  ended}`, readers `fold.dt(ar, tb, i)`, `fold.shape`, `fold.base`, `fold.ended`,
  `fold.device`, `fold.addr`. Also `least_upper_dtype` hoisted in as a bitmask
  lattice. Import: `import ./fold.bend as F`.
- `tinybendygrad/LAWS/spec.bend` — the pure spec IR (shapes, dtypes, AxisType,
  AddrSpace). From `uop/`: `import ./../LAWS/spec.bend as S`.
- `tinybendygrad/uop/spec.bend` (3186 lines, green) — a WORKED EXAMPLE of the
  whole pattern: six rule tables, 84 rules, one `match` case per rule, six
  duplicated scans. Read its header. It shows the conventions for a rule table, a
  dispatch, `+` params, and the gate.
- `.agents/slop/notes/bend2-constraints.md` — the measured Bend rules. Long. Read
  at least: the compiled-form section, the `early_reject` section, the name-rebind
  section, "THE ENGINE SHAPE", and the general-rules sections.
- `.agents/slop/notes/engine-shape.bend` — the rewrite-engine model, runnable.

## THE ARCHITECTURE: rules are TOP-LEVEL DEFS, not closures

A compiled rule is a def named by a tag. The rule table is a plain `Data` record,
so it is COPYABLE. There are NO closures, NO store, NO `setdefault`, NO cartesian
product. A rule's captures are its own parameters, and it may read the arena as
many times as it wants.

- `PMEntrys` / `PMEntry` come from ops.bend; you dispatch with your OWN
  `<name>_dispatch(tag, ar, self)` and your OWN `<name>_rewrite`, because ops.bend
  cannot call into your file. That ~15-line scan duplication is the honest cost of
  not having first-class functions — `spec.bend` does it six times and says so in
  its header. DO NOT invent a generic dispatch abstraction; if you want one, that
  is the signal to stop and write down why you cannot.
- `PMEntry.rej` is `early_reject`. **It is a NECESSARY CONDITION, not a veto,
  despite the name**: the rule FIRES when the op set IS a subset of the node's src
  ops. Empty set is a subset of everything, which is why most rules always fire.
- **A name bound twice MUST emit an identity check** (`U32.is_eq` on two arena
  indices). This is load-bearing: `mixin/gradient.py:101` binds `dest` to two
  different nodes and the rule only matches when they are the same node. Without
  the check the rule matches strictly more nodes than intended, and it typechecks.

## THE REWRITER (if your unit rewrites rather than judges)

`graph_rewrite`'s shape is settled after thirteen failed attempts. **A rule
RETURNS THE ARENA, NOT A PAIR.** A rule returning `(Arena & U32)` works, but then
the engine must `match` on the rule's result, and a match may not scrutinise a
computed value. A helper def does not rescue it — the helper must call back into
the pass, which is mutual recursion and is refused. Returning the arena deletes the
destructuring, leaving ONE recursive def:

    def engine_pass(rules: List<Rule>, a: Arena) -> Arena:
      match rules:
        case Nil{}: a
        case R{use} <> rest: engine_pass(rest, use(a))

A rule is `Type` here (it holds a function), so the rule TABLE is linear and a
second pass rebuilds it. That is the structural cost and it is one call site.
`.agents/slop/notes/engine-shape.bend` is the runnable model, and it is verified
with rules that genuinely grow the arena.

## MEASURED Bend 2.0.34 rules — do not rediscover these

1. A def may only call defs declared ABOVE it. No forward references.
2. A `match` may only scrutinise a PARAMETER or a pattern binder — never a call,
   never a projection (`n.f` is a NAME lookup and fails), never a `let`. Compute a
   Bool in the arm and pass it to a def as a parameter.
3. A parameter is affine unless prefixed `+`. **A `Data` record parameter still
   needs `+` for two reads in ONE body** — `Data` makes a record shareable ACROSS
   functions, not the parameter readable twice. A `let` is affine too, so recompute
   a pure call rather than binding it.
4. `+` CANNOT be spelled in a closure TYPE, and cannot be spelled on a `Maybe`
   parameter. Avoid closures entirely.
5. Mutual recursion is refused. A self-call must be DECREASING and read LEFT TO
   RIGHT, so any fuel is the FIRST parameter of every self-recursive def. The same
   fuel may not feed two self-calls in one arm.
6. Re-wrapping a list TAIL in any constructor is rejected. A head is fine
   (`[x] ++ rest` via `List.append` is a prepend). `List.append(a, A, xs, ys)` is
   `xs ++ ys`.
7. A wildcard `case _ <> _:` is CONS-only. A `Data` match must name every
   remaining constructor. A two-scrutinee `match` needs `case _ _:` not `case _:`.
8. `True{}`/`False{}` — bare `True`/`False` in VALUE position is a parse error.
   Only `case True{}:` is a pattern.
9. Every operator needs an explicit type: `(a + b : Nat)`. `Nat` and `U32` are
   different types; only `Nat` binds in `case 0n:`.
10. A numeric `case 0n:` is a PREFIX match and claims its successors, so it is not
    exhaustive. Use `List.get(a, A, xs, n)` — quantifier, then element type, then
    the list. `List.get` returns a `Maybe`; `Maybe.default(&2, U32, m, 0)` unwraps.
11. `def` with no return type is parsed as a law proof. `match` and `equal` are
    KEYWORDS — you cannot name a def either of them.
12. `case p <> t` on a `String` gives the first CHARACTER. `String.concat` hides a
    dropped literal.
13. Removing the last use of a parameter can be a compile error.
14. A one-field record's pattern must NAME its field. A three-scrutinee `match` with
    a `Nat` countdown has no `0n` arm.
15. A `Data` record cannot hold a `Maybe` field — flatten to `Bool`s plus a third
    `Data` type.

## TWO THINGS THAT WILL SAVE YOU HOURS

**`ops.bend` ALREADY HAS `Arena.op(ar, i) -> Op`, `Arena.src(ar, i, n) -> U32` and
`Arena.nsrc(ar, i) -> U32`, and they return BARE values, not `Maybe`.** Look them
up before writing a reader. Four compile cycles were lost to this once.

**TOOLS** — DRIVERS only, never one-shot editors:

    python3 .agents/slop/tools/hoist.py <file> ./bin/bend   # move a def above its caller
    python3 .agents/slop/tools/share.py <file> ./bin/bend   # add + to a consumed-twice param

Alternate until both say `clean after`. A scripted splice once silently deleted 44
defs from `ops.bend`, so after every non-trivial edit check:

    python3 -c "
    import re
    L=open('<file>').read().split(chr(10))
    print(sum(1 for l in L if re.match(r'^(def|type) ', l)), 'defs')"

and compare against your own count. Never run them on the shared files.

## GATE DISCIPLINE — this is what makes the work trustworthy

End your file with `main` that PRINTS one row per claim. The gate is that both
lanes print the same rows. Bend has no assertion form.

Then **mutate your own code and re-run**, and record which rows moved, in a table
at the foot of the file. A row that only one mutation moves is a LOCALISED row;
say so, because the table is not one-row-per-bug.

Pick claims DERIVABLE FROM PYTHON, so a row can actually be wrong. A row that
merely restates your code is worthless.

**Two traps, both hit for real, so build against them:**

- If your table has no node that TWO rules both claim, a first-wins-vs-conjunction
  bug moves NOTHING and your gate cannot see it. Build that fixture.
- All-True tells you the cases you covered and nothing about the rest. A real bug
  shipped through ten green rows because it only appeared at FOUR srcs where every
  fixture had two. Include a row that pins a COUNT, not just a boolean.

## What to report

- Def-by-def mapping; for each omission the WALL (what specifically Bend cannot
  express), the `<file>.py:<line>`, and the phase that owns it. Mark omissions
  `# TODO(p3) <file>.py:<line>  <name>` in the file, matching `ops.bend`.
- Exact output of check + both lanes.
- Your MEASURED mutation table.
- Any NEW general Bend rule you discover — append it to
  `.agents/slop/notes/bend2-constraints.md` (shared, append only, keep the style).
- Anything you believe is wrong in a shared file. Do not fix it — report it.

Be honest about what is not done. A row that prints `False` is information; hiding
it makes the work worse than not doing it.
