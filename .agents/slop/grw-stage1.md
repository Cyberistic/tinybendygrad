# `graph_rewrite` — the dispatcher. STAGE 1: what the stub costs, from data.

Every number here is produced by a script in `.agents/slop/`, and every script
reads the source rather than a transcription of it.

```
python3 .agents/slop/grw-census.py      > .agents/slop/grw-census.txt
env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python .agents/slop/grw-ctxclaim.py \
                                       > .agents/slop/grw-ctxclaim.txt
```

## 1. HOW MANY CALL SITES DOES THE PORT'S `graph_rewrite` HAVE?

**ZERO.** And that is not a rounding of "a few": the census resolves each call by
IMPORT CLOSURE, not by name.

| | count |
|---|---|
| `.bend` files scanned | 132 |
| non-comment lines naming `graph_rewrite` | 11 |
| — of those, `def`s | 2 |
| — of those, calls that resolve to `codegen/__init__.bend`'s def | **0** |
| — of those, calls that resolve to a LOCAL def of another file | 9 |

The five bare calls at `codegen/decomp/dtype.bend:2081,2088,2093,2098,2111` are
the trap. A classifier that matches the NAME reports five call sites for
`codegen/__init__.bend`'s def. All five are in a file that imports
`./op.bend`, `./transcendental.bend`, `uop/ops.bend`, `helpers.bend` and
`LAWS/spec.bend` and **not** `codegen/__init__.bend`, so they resolve to
`dtype.bend`'s own four-argument `graph_rewrite(x, pm, ctx, bottom_up)`. A name
is not a binding.

**SO THE BRIEF'S "10 FILES DEPEND ON IT" IS NOT A CALL COUNT.** Those ten files
mention `graph_rewrite` in 86 COMMENT lines and in 22 `TODO(p3)` markers.
Denominator: 884 `TODO(p3)` markers in the tree, 22 of which name
`graph_rewrite`/`unified_rewrite` as their wall, across 14 files. That is the
real number, and it is a count of WALLS, not of callers.

| file | markers | grw-walled | of those, reason mentions ctx/dict |
|---|---|---|---|
| `function.bend` | 12 | 3 | 2 |
| `uop/symbolic.bend` | 15 | 3 | 1 |
| `codegen/kernel.bend` | 11 | 2 | 1 |
| `tensor.bend` | 49 | 2 | 0 |
| `uop/movement.bend` | 2 | 2 | 1 |
| `uop/ops.bend` | 95 | 2 | 2 |
| `engine/jit.bend` | 1 | 1 | 1 |
| `mixin/rand.bend` | 37 | 1 | 0 |
| `renderer/wgsl.bend` | 5 | 1 | 1 |
| `schedule/__init__.bend` | 7 | 1 | 1 |
| `schedule/multi.bend` | 55 | 1 | 0 |
| `uop/fold.bend` | 39 | 1 | 1 |
| `uop/upat.bend` | 3 | 1 | 1 |
| `uop/weak.bend` | 14 | 1 | 0 |
| **total** | **884** | **22** | **12** |

## 2. WHAT WOULD HAPPEN IF A CALLER GOT `(None{}, Map{})`?

The stub returns `(None{}, Map{})`. With **zero** call sites there is nothing to
misbehave in the port, so the question moves upstream, where the census is over
`tinygrad/`'s 99 call sites, classified by what the CALLER does with the value:

| use | count |
|---|---|
| THREADED (the value becomes the next sink / next input) | 46 |
| CHECKED (`.op is`, `.vmin`, `.shape`, `is None`, `.shrink_to`) | 33 |
| DISCARDED (VIZ-only, `PatternMatcher([])`) | 13 |
| OTHER | 7 |

A `None` sink is fatal to 79 of the 99 and inert to 13. So the stub is not a
"returns nothing rewritten" wall with a cosmetic cost — **it is a wrong-answer
wall for 46 threaded call sites**, and every one of them is currently walled
individually rather than by one dispatcher.

## 3. THE FIXPOINT'S PASS COUNT HAS NO UPSTREAM COUNTERPART

CPython's driver is ONE worklist. It has no notion of a pass, so the port's
`passes` row is **port-only** and is gated by mutation (`grw-mut.py`), not by
an oracle. Saying so is cheaper than inventing an oracle.

## 4. THE HEADER'S DEFERRAL REASON, MEASURED

`schedule/__init__.bend:7-13` justifies deferring `__init__.py:82-301` — fifteen
top-level defs/classes, counted from the AST — with one sentence. It contains
three separable claims, and `grw-ctxclaim.py` reads the source for each:

| claim | verdict |
|---|---|
| **C1** "every rule in it is a `graph_rewrite` over the arena" | **FAILS: 9 of 15 do not.** 6 of 15 call `graph_rewrite` themselves; 5 of 15 call nothing and write no ctx; 4 of 15 (`assert_all_same_devices`, `copy_kernel_to_store`, `CallifyCtx`, `is_store_after`) contain no rewrite at all. |
| **C2** "…with a PYTHON `ctx` DICT" | **FAILS: 2 of 15 pass no ctx at all** — `contiguous_mops_to_view` (1 call, `ctx=` absent) and `create_linear_with_vars` (3 calls, all with `ctx=` absent). |
| **C3** "these rules need the ctx to be a MUTABLE accumulator" | **FAILS for 7 of 15** on the direct reading, and for 7 of 15 on a TRANSITIVE one (following the matcher tables to their rule bodies). |

The seven the reason does not cover:

| line | name | why the reason does not apply |
|---|---|---|
| 124 | `lower_sink_to_linear` | calls no `graph_rewrite` |
| 157 | `assert_all_same_devices` | calls no `graph_rewrite` |
| 161 | `copy_kernel_to_store` | calls no `graph_rewrite` |
| 165 | `simplify_copy_kernel` | ctx is an **empty dict literal**, not an accumulator |
| 193 | `CallifyCtx` | calls no `graph_rewrite` |
| 217 | `is_store_after` | calls no `graph_rewrite` |
| 273 | `create_linear_with_vars` | passes **no ctx** on any of its three calls |

The eight for which the reason **is** the question, by name: `create_new_buffer`,
`resolve_linear_call`, `collect_stores`, `canonicalize_alloc`,
`canonicalize_call_body`, `replace_input_buffer`, `transform_to_call`,
`contiguous_mops_to_view`.

### WHAT THIS CONFIRMS AND WHAT IT CORRECTS

**CONFIRMED — a previous unit's measurement.** Those two dispatchers block all
fifteen *regardless of their `ctx`*. The dispatcher's absence is upstream of the
ctx question for every one of them, because a `graph_rewrite` that returns
nothing cannot be rescued by a better ctx. Implementing the dispatcher FIRST is
the right order.

**CORRECTED — the header's wording, and it is not softened.** The header says
"every rule in it is a `graph_rewrite` over the arena with a PYTHON `ctx` DICT".
That is false for 9 of 15 on the first clause and for 2 of 15 on the second. The
defence of those fifteen is therefore **TWO walls, not one**, and they must be
stated as two:

1. no dispatcher (`graph_rewrite` was a wall) — removed by this unit;
2. no MUTABLE-ACCUMULATOR ctx — true for **8 of 15**, and it is a SEPARATE wall
   that this unit does not touch.

**AND ONE HEADER CLAIM IS TOO WEAK.** The header's own second clause is the
stronger blocker and it is not the one being argued: `graph_rewrite`'s engine
pass needs the rule table LINEAR. That is `uop/ops.bend`'s `UPat` compiler, and
it binds a strictly larger share of the fifteen than ctx does — 57 `UPat`
COMPILER blocks are already recorded as "shared" in `.agents/slop/marker-audit.py`'s
split. So the honest priority order is: **linear rule table, then dispatcher,
then ctx** — and the header argues for the third.

## 5. WHAT A "COUNT" GETS WRONG HERE, THREE TIMES

1. **Name matching reported 5 call sites for `codegen/__init__.bend`'s def; the
   true number is 0.** Import closure, not the name.
2. **`rg "TODO\(p3\)" | wc -l` counts 1009 mentions and 884 markers**, because
   125 of them are prose (`` `# TODO(p3)` line ``) or the header of a NOT-PORTED
   table. The marker test is "unquoted, at the start of a comment".
3. **The first version of `grw-ctxclaim.py` MISSED all six bare-name rules**
   (`create_new_buffer`, `collect_stores`, `canonicalize_alloc`,
   `simplify_copy_kernel`, `copy_kernel_to_store`, `assert_all_same_devices`) —
   a bare name in a rule tuple is an `ast.Name`, not an `ast.Call` — while
   collecting every `UPat(...)` as if it were a rule. It reported C3 as 5 of 15;
   the structural read (`PatternMatcher` call → list → 2-tuple → `elts[1]`)
   reports 8 of 15. **A classifier that is wrong in the direction that makes the
   wall look smaller is the dangerous direction.**