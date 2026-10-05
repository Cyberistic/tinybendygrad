# `graph_rewrite` — STAGE 2 and STAGE 3: what was implemented, and what it is armed against.

The file: `tinybendygrad/codegen/__init__.bend`. Nothing else in the tree was
edited except the two harnesses this unit owns the contract of
(`oracles/gateport/oracles/gr-diff.sh`) and the notes.

## THE UPSTREAM DISPATCH RULE, READ FROM THE SOURCE

`tinygrad/uop/ops.py:1888-1890`, verbatim:

```python
def graph_rewrite(sink, pm, ctx=None, bottom_up=False, name=None, bpm=None, walk=False, enter_calls=False) -> UOp:
  rewrite_ctx = RewriteContext(pm if not bottom_up else None, pm if bottom_up else bpm, ctx, enter_calls)
  return rewrite_ctx.walk_rewrite(sink) if walk else rewrite_ctx.unified_rewrite(sink)
```

Two statements, and **only the second is the dispatch**: a ternary on one
`Bool`. That is what is ported:

```bend
def graph_rewrite(+ar, +sink, +pm, +ctx, walk: Bool) -> Rewritten:
  Bool.pick(Rewritten, walk, walk_rewrite.counted(ar, sink, pm, ctx), unified_rewrite(ar, sink, pm, ctx))
```

The first statement is TABLE SELECTION — `bottom_up=True` puts `pm` in
`self.bpm` and `None` in `self.pm`, and both drivers then run only the bottom-up
table. It is **not ported**, and the reason is a file this unit does not own:
`uop/ops.bend` has no `bpm` and no per-entry bottom-up marker
(`rg "bpm|bottom_up" tinybendygrad/uop/ops.bend` → no hits), so there is no
second table for the dispatcher's other half to select. `pm_post_sched_cache` is
top-down in both ports, so this is invisible on the gate's fixtures; it is a
wall upstream and it is named at `unified_rewrite`'s header with the line number.

## WHAT ELSE IS NOT PORTED, BY NAME

| upstream | line | why |
|---|---|---|
| `bottom_up` / `bpm` table selection | ops.py:1889 | no second table exists (`uop/ops.bend`) |
| `enter_calls` | ops.py:1833/1841 | both drivers skip `n.src[1:]` of a CALL; the port's neither does, so the two upstream call sites that pass `enter_calls=True` (`schedule/__init__.py:276`, `codegen/__init__.py:492`) would be wrong here |
| per-node `seen` set, `BottomUpGate` | ops.py:1810-1821 | they bound the BOTTOM-UP loop the port does not have |
| the `waitlist` / `on_stack` 3-stage worklist | ops.py:1830-1885 | the port's driver is the same fold re-run; `wr.go` over a fresh toposort IS stages 0/1 with the waitlist pre-resolved by the toposort |
| `name` | ops.py:1888 | `rewrite_group` tracing; no equivalent here |

## THE FIXPOINT, AND WHY ITS STOP TEST IS SOUND

The stop is "the sink index did not move". That is sound **because the arena
interns**: `uop/ops.bend`'s `UOp.make` calls `intern.find` and a HIT returns the
arena UNTOUCHED, so two passes handing back the same sink INDEX handed back the
same `Node{op, src, arg, tag}`. The reachable graph is identical,
`pm_rewrite_m` is a pure function of that graph and of `ctx`, and the next pass
rebuilds nothing. Index equality here is the interning invariant, not a
coincidence — and this is the load-bearing dependency of the whole driver, so it
is named at the def rather than left implicit.

## FAILURE MODE 2 — THE OBSERVABLE, DECIDED

Upstream raises for both non-success outcomes: `REWRITE_STACK_LIMIT` at
ops.py:1821 and the stalled waitlist at ops.py:1883. A Bend def returns a value,
so the port **reports** the distinction instead of raising it:

* `Rewritten.passes: U32` — how many passes ran.
* `Rewritten.capped: Bool` — the pass bound ran out with the sink still moving.

**`capped=True` IS NOT A FIXPOINT and is never read as one.** And here is what
it does NOT separate, stated rather than glossed: a genuine rewrite CYCLE
(`R(n)=m, R(m)=n`) from a chain that merely needs more than `FIXPOINT_PASSES`
passes. Both are "the sink was still moving when the bound ran out", and the
port cannot tell them apart because it has no `seen` set. **`capped=True` means
NOT-CONVERGED, and nothing finer.**

**`cycles == 0` is NOT claimed and does not certify a complete linearization.**
The port has no cycle detector and no `seen` set, so it cannot certify one; the
honest statement is the bound plus the flag.

**The cap is REACHED by a gate row, not merely asserted.**
`grw_cap_*` enters `unified_rewrite.go` with zero fuel and a `prev` of 0, so the
pass it runs cannot confirm anything and the cap arm is the one taken. Without
that row a cap flag no fixture can reach is a comment with a type.

## FAILURE MODE 1 — RE-ENTRY, PROVEN

`walk_rewrite` (the thing being iterated) is called **directly**, once per pass,
from `unified_rewrite.next` — never through `graph_rewrite` and never through
anything memoised. The `create_schedule` cache shape from the brief cannot apply
here: this driver holds no cache and reads no module state. Proven by the pass
count itself: the fixture answers `passes=2`, which is only reachable if the
second call actually RAN. `grw-mut.py` M1 (the stop test inverted) collapses it
to `passes=1` and moves five rows, which is the same evidence read from the other
side.

## FAILURE MODE 3 — SILENTLY DROPPED RULES

Not applicable to the driver and worth saying why: `walk_rewrite` calls
`pm_rewrite_m` once per node and `try_rule` takes a `Maybe`, so a rule that does
not fire is an explicit `None{}` that becomes the rebuilt node. There is no path
on which a pattern-match entry is skipped without being recorded. The rule TABLE
is the thing that can be incomplete, and the one completion bug this unit found
is upstream: CPython's `pm_post_sched_cache` is a two-pattern `PatternMatcher`
and the port's `pm_alloc_only` deliberately drops the PARAM pattern for fixture
F2, which is stated at the table rather than left for a reader to infer.

## THE FIVE BEND REFUSALS THIS COST, ALL MEASURED

`.agents/slop/grw-loop-probe.bend` is the record. Every one of these is a
constraint the substrate places on any fixpoint driver here, not a style choice:

1. **a `+` destructured binder cannot be passed into a `Data` record
   CONSTRUCTOR** — `cannot infer`, observed `_ => Map<&2, U32>` under `Pair`.
   Reproduced on a five-field record and not on a three-field one.
2. **`+` on a TUPLE parameter is refused outright** — `expected: Data,
   observed: Type`. A tuple parameter may be read exactly once; a `+` `Data`
   record parameter may be read as many times as the arms need. **The fixpoint
   state is therefore a record, not a tuple.**
3. **a `match` on a parameter is refused after ANY other statement** — "this name
   is a def or a consumed binder". So the `Nat` match is the body's FIRST
   statement and the `Bool.pick` sits inside its arms.
4. **a TWO-DEF cycle is refused in either declaration order** — `go -> more ->
   next -> go` reports "an unfilled law" whichever way round it is written. So
   the Bool driver and the Nat driver are ONE def.
5. **a record binder SHADOWS a same-named parameter and nothing says so.** This
   one cost the pass counter: `Rewritten.cap(w, passes)` with
   `case Rewritten{ar, sink, repl, passes, capped}` compiles, typechecks, prints
   `capped=1` correctly, and answers `passes=1` for **every** value of `done`.
   `unified_rewrite.go(0n, 5, 0, ...)` answered `passes=1`; renamed to `n` the
   same call answers `passes=5`. **The green gate could not see it either,
   because the rows did not exist yet.** Mutation M3 reproduces exactly this
   spelling and moves two rows, so the trap is now gated rather than remembered.

A sixth, found by measurement rather than by the compiler: **a `Nat` literal
arm is a RANGE, not an equality.** `case 0n` is exact ONLY when the other arms
are `1n+`-shaped; with a `case 4n:` arm present and legal, `case 0n` swallowed 0
and 2. So the bound is tested with `case 0n` on a countdown (the shape
`ops.bend`'s `toposort` already uses) and never with a literal.

## STAGE 3 — THE GATE, AND ITS DEMONSTRATED ABILITY TO FAIL

27 rows, every one of them calling **`graph_rewrite` itself** — never a caller of
it, never a driver directly. A row that gates `walk_rewrite` cannot see the
dispatcher's ternary, and a mutation there would move nothing.

```
grw_f1_walk_{passes,capped,sink,n,mapn,repl}
grw_f1_fix__{passes,capped,sink,n,mapn,repl}
grw_f2_walk_{passes,capped,sink,n,mapn,repl}
grw_f2_fix__{passes,capped,sink,n,mapn,repl}
grw_cap__{passes,capped,sink}
```

Two fixtures, because **CPython's `unified_rewrite` RAISES on F1**:
`IndexError: tuple index out of range` at `tinygrad/schedule/__init__.py:98` —
after the first pass the graph holds the dummy `PARAM(99)`, the rule reads
`ctx[1][x.arg.slot]` with slot 99, and the ctx has two entries. Without F2 the
fixpoint arm would have no CPython expectation at all. F2 is `SINK[ALLOC]` with
the ALLOC rule alone.

### The rows compared against CPython, with the denominator

`bash .agents/slop/grw-gate.sh` — exit 0.

| | |
|---|---|
| comparable facts | **6 of 8** (2 fixtures × 2 arms × 2 facts) |
| AGREE | **6 / 6** |
| NO ORACLE | 2 — `f1_fix_{n,repl}`, because CPython raises |
| DECLARED DIVERGENCE | 2 — `f2_fix_mapn` (CPython 4, port 2) |
| port-only, no upstream counterpart | `passes`, `capped`, `*_sink` |

`mapn` is a second declared divergence and it is a real difference, not a
formatting one: upstream's worklist keys `replace` with every node it touched,
INTERMEDIATE rebuilds included, so it records 4 nodes for F2's fixpoint where the
port's LAST PASS — which starts from an empty map — records 2, on the same final
graph whose repl string the two sides print byte-identically.

The gate exits **2** if it compared zero rows, so a green that compared nothing
cannot read as a pass.

### The mutation set — 9 mutations, 0 blind spots

`python3 .agents/slop/grw-mut.py`

| id | moved | rows | what |
|---|---|---|---|
| **CANARY** | **8** | 27 | the dispatcher's two arms are exchanged |
| M1 | 5 | 27 | the stop test is INVERTED, so pass 1 counts as converged |
| M2 | 2 | 27 | the converged arm reports `done+1` |
| M3 | 2 | 27 | `passes` reads the record's field (the shadowing trap) |
| M4 | 6 | 27 | the pass bound is 1, and the fixture needs 2 passes |
| M5 | 1 | 27 | the cap arm reports the FIXPOINT outcome |
| M6 | 7 | 27 | the total read of the sink falls back instead of reading the `Maybe` |
| M7 | 2 | 27 | the walk arm claims TWO passes |
| M8 | 4 | 27 | the fixpoint feeds the PREVIOUS sink into the next pass |

**9 of 9 move rows. 0 blind spots.** Every mutation is checked four ways before
its number is printed: the pattern must be PRESENT, it must be ABSENT after the
replace, the mutant must print `ALL PROOFS CHECK`, and the mutant must print the
SAME SET OF ROW NAMES.

### The harness has been shown to fail — three ways

`python3 .agents/slop/grw-mut-selftest.py` — `SELFTEST PASS`.

| | expected rejection | result |
|---|---|---|
| D1 | `PATTERN NOT PRESENT` | REJECTED, rc=2, file restored |
| D2 | `MUTANT DOES NOT TYPECHECK` | REJECTED, rc=2, file restored |
| D3 | `DIFFERENT SET OF ROW NAMES` | REJECTED, rc=2, file restored |

**D2 IS A CHECK THIS HARNESS WAS MISSING, and finding it is the point.** The
first version gated on the mutant's `--check-only` output CONTAINING this file's
name; a mutant with an undefined callee reported the error somewhere else, the
check passed, and the mutant's EMPTY output was counted as "moved 0 rows" — a
blind spot where the truth was "did not run". That is failure mode 1's cousin and
it would have been reported as a coverage number. The gate is now on
`ALL PROOFS CHECK` being PRINTED.

D2 also caught the substrate going cold twice for real: while
`uop/render.bend` was mid-edit by another unit, the baseline check printed
`FATAL: baseline does not print ALL PROOFS CHECK -- the whole run is void`
instead of reporting 9 zero-moving mutations.

## THE REGRESSION FLOOR

| set | before | after |
|---|---|---|
| `schedule/__init__.bend`'s own 81 rows | `7a3aa4a4…` | **BYTE-IDENTICAL** |
| `.agents/slop/sched-fixture.bend`'s 60 rows | `9e048c3b…` | **BYTE-IDENTICAL** |
| the port's original single row (`new_sink=8 repl=…`) | — | same mapping, now `grw_f1_walk_repl`, byte-identical to CPython |

Baselines captured BEFORE the first edit: `.agents/slop/grw-base-sched81.txt`,
`.agents/slop/grw-base-fixt60.txt`, `.agents/slop/grw-baseline.sha256`.

## `oracles/gateport/oracles/gr-diff.sh` HAD TO CHANGE, AND WHY

The port used to print one line; it now prints 27. `gr-diff.sh` counted `->`
across the WHOLE output, so adding a gate row would have turned a green gate red
for a reason that has nothing to do with the rewrite. It now SELECTS
`grw_f1_walk_repl` by name and compares BYTES rather than counting.

**The byte comparison found a format mismatch the count had been hiding for the
life of the gate**: the old oracle printed `PARAM(slot=0)` and the port prints
`PARAM(0)`, so the two have always agreed on COUNT (4) and differed on every
PARAM pair. That is this project's own `ALLOC->PARAM(99)` lesson arriving one
level down. One oracle now exists (`grw-oracle.py`), it prints the port's
format, and `gr-diff.sh` selects from it.