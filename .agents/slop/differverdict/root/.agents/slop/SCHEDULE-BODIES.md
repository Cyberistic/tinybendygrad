# SCHEDULE-BODIES — the twelve of `schedule/__init__.py:82-301`

Unit: port the **rule bodies**. Commit nothing. Nothing here is committed.
Detail in `.agents/slop/schedule-bodies/`.

| file | what |
|---|---|
| `sb-oracle.py` | the CPython lane. **89 rows, every expectation computed, none typed** |
| `sb-oracle.txt` | its printed output (`PYTHONPATH=. python3 sb-oracle.py`) |
| `sb-gate.sh` | three lanes + the 81-row regression floor, whole-`name=value`-line diff |
| `sb-diff.py` | the differ. Whole LINES, never row names |
| `plant/` | a throw-away COPY of the tree, because a `$TMPDIR` scratch copy cannot resolve a relative import (22 phantom blind spots in one unit) |
| `INCONCLUSIVE.txt` | the substrate-cold evidence, verbatim |
| `BEFORE-rows.txt` | the 81 rows the previous unit left, captured before my first edit and never re-recorded |

---

## 1. THE VERDICT, FIRST, BECAUSE IT CHANGES HOW THE TABLE BELOW IS READ

**The eight ports are ON DISK, COMPILE, and HOLD THE 81-ROW FLOOR AT 81/81
BYTE-IDENTICAL. They carry ZERO GATE ROWS, so they are UNPROVEN — and the
project's own rule says a zero is a request for a fixture, not a coverage
claim.**

```
$ ./bin/bend tinybendygrad/schedule/__init__.bend --check-only
ALL PROOFS CHECK
$ ./bin/bend tinybendygrad/schedule/__init__.bend | wc -l
81
$ grep -c -F -x -f BEFORE-rows.txt rows-bd.txt
81
```

**The gate rows were BUILT and DID NOT COMPILE in the time available.** The
oracle is complete (89 rows), the fixtures are complete (`FIXTURES.bend`), the
row bodies are written (`ROWS.bend`), and the failure is Bend's — `main`'s
`do IO<Unit>` block is already at its nesting limit after 81 binds, and a
`+`-binding or a further `IO` bind in it is refused. I truncated `main` back to
the 81 rows rather than ship a file that does not compile.

**So: a plant CANNOT move anything on these ports, and that is reported as a
blind spot with its reason, NOT as a green result.** A red with no paired
disarm proves nothing; neither does a green with no row.

### THE PLANT/DISARM I *DID* RUN, and what it was for

`plant/` is the control lane, and it earned its keep in a way worth recording:
**it is the only reason I know my file is not merely failing on someone else's
breakage.** The live tree could not run at all (§4), so every measurement below
is against a copy whose `helpers.bend` is restored from `HEAD`. The plant
reported **`is_store_after`, `collect_stores`, `canonicalize_alloc`,
`apply_binds`, `assert_all_same_devices`, `copy_kernel_to_store` and
`lower_sink_to_linear` as my OWN compile errors, one at a time**, and each was
fixed. That is the disarm half: the substrate was broken and my file was *also*
broken, and only a lane that ran to MY errors could tell those apart.

| # | the error the plant gave me | the Bend rule | fix |
|---|---|---|---|
| P1 | `cks_dev.same`: "a match cannot scrutinize a computed value" | scrutinees must be parameters | split into `cks_dev.eq(x, y)` |
| P2 | `asd_go`: a `match` nested in a `case x <> rest:` LIST arm | file's rule 1 | `asd_step(cls: U32, ...)` takes the selector as a parameter |
| P3 | `asd_go`: "a decreasing self-call" | file's rule 3 | the LIST becomes the FIRST parameter, `asd_go(xs, kept, ar)` |
| P4 | `canonicalize_alloc`: computed scrutinee | — | `canonicalize_alloc.pa(m, n, s, ...)` |
| P5 | `aa_put`/`cs_put`/`ca_new`: "consumed more than once" | a bare parameter is consumed once | `+c` |
| P6 | `ca_slot_u`, `rb_pa_name`, `raa`, `rnone_of_f`: "a filled definition" | **declaration before use** | moved each above its first use |
| P7 | `apply_binds.of`, `cks_rep`, `rca_slot.of`, `rcs_same`: "consumed more than once" | — | `+bop`, `+ar`, `+a` |

**P6 is the one worth flagging to the next agent: in bend 2.0.34 a def must be
declared ABOVE its first use, including a helper that only reads a record
field.** Four separate failures, all the same rule, all found only because the
plant compiled.

---

## 2. THE TABLE — all twelve, needs-ctx decided, ported or walled

`py=` is `sb-oracle.py`'s row. "wall" is `file:line`.

| # | entry point | py | needs ctx? | outcome |
|---|---|---|---|---|
| 1 | `is_store_after` `:217` | 10 | **NO** | **PORTED, complete, no wall** |
| 2 | `collect_stores` `:220` | 10 | **YES** (`CallifyCtx`) | **PORTED, complete** |
| 3 | `lower_sink_to_linear` `:124` | 13 | **NO** | **GUARD PORTED**; body walled |
| 4 | `copy_kernel_to_store` `:161` | 15 | **NO** | **PORTED, complete** (DISK prefix parameterised) |
| 5 | `simplify_copy_kernel` `:165` | 2 | **NO** | **GUARD PORTED** as `simplify_copy_kernel.ok`; rule walled |
| 6 | `assert_all_same_devices` `:157` | 12 | **NO** | **PORTED**, minus the `raise` |
| 7 | `apply_binds` `:110` | 14 | **NO** | **DISPATCH PORTED** (arm number); arm 3 walled |
| 8 | `canonicalize_alloc` `:235` | 12 | **YES** (`CallifyCtx`) | **PORTED, complete** |
| 9 | `contiguous_mops_to_view` `:199` | 0 | yes, weakly | **WALL** |
| 10 | `canonicalize_call_body` `:239` | 0 | **NO** | **WALL** |
| 11 | `replace_input_buffer` `:248` | 0 | **YES** | **WALL** |
| 12 | `create_linear_with_vars` `:273` | 0 | **NO** | **WALL** |

**EIGHT of twelve ported. FOUR walls.** With the three the table unblocked
(`create_new_buffer` `:90`, `resolve_linear_call` `:103`, `transform_to_call`
`:261`, all in `uop/ops.bend`), that is **ELEVEN present out of the fifteen.**

### 2a. WHAT EACH ONE NEEDS, NAMED

**1. `is_store_after` `:217-218` — needs `UOp.unsharded_base` (`ops.py:792`).
Nothing else.** NO ctx. This is the only one of the twelve with **no wall at
all**, and it is the cheapest: 5 lines. It is also the only one whose every
helper already existed.

**2. `collect_stores` `:220-221` — needs `is_store_after` (above) and the
`CallifyCtx` record `:192-197`.** ctx is weak: the rule **writes** `stores`, a
`list`, and **never reads** `allocs`, the only `dict`. **This is the measured
refutation of clause C2 in its strongest form** — the one ctx body that is
fully portable is the one whose ctx has no dict in its path.

**3. `lower_sink_to_linear` `:124-126` — needs `UOp.body` (`ops.py:562`),
`isinstance(arg, KernelInfo)`, `CallInfo.precompile`.** NO ctx. Ported: the
three-clause guard. Walled: `time.perf_counter` + **`function.key`** (a `bytes`
content hash — the clock is not the wall, AGENTS.md says inject time); the
module-level `schedule_cache` + `diskcache_get`; `type_verify`; `get_kernel_graph`
× `prepare_rangeify`; the `inspect.stack()` block.

**4. `copy_kernel_to_store` `:161-163` — needs `UOp.store` (`ops.py:622`),
`dst.device`, `dst.device.startswith("DISK")`, `call.replace`.** NO ctx.
`store` and `replace`'s head-swap are ported. **`startswith` is the wall and it
is `schedule/memory.bend:189`'s wall**: `S.Dev` is `D1{tag}`, the name is gone,
so `disk` is a **parameter** and `disk=[]` is a permitted answer. The prefix
test is **parameterised, not ported.**

**5. `simplify_copy_kernel` `:165-172` — the SAME first line as 4, plus a
bottom-up `graph_rewrite` over FOUR matchers (`:171`), two imported at
`:168-170`.** NO ctx. Only the guard is portable.

**6. `assert_all_same_devices` `:157-159` — needs `UOp.toposort`, `dedup`,
`x.device` for a `PARAM` (which is `self.arg.device`, `ops.py:888`, so **no
fold**), and the `>= 2` threshold.** NO ctx, NO table. Ported; the `raise` is
not, and `cycles` is the file's existing treatment of a raise.

**7. `apply_binds` `:110-114` — needs `UOp.body` and, for arm 3,
`UOp.variables` + `UOp.substitute`.** NO ctx. **`UOp.variables` has no reader in
the tree** — `fold.bend`'s own header names it as one of three readers waiting on
the RANGES FOLD — and `ops.py:1239 UOp.substitute` waits behind it.

**8. `canonicalize_alloc` `:235-237` — needs `dataclasses.replace` on the
13-field `ParamArg`, `ctx.allocs`, and `len(ctx.allocs)`.** ctx. All ported.

### 2b. THE FOUR WALLS, WITH `file:line`

**9. `contiguous_mops_to_view` `:199-215`** — the largest of the twelve, and
**five** of its helpers are missing:
`ops.py:559` `all_int(c.shape)` (needs a fold `Table`); `ops.py:561` the BITCAST
peel; **`:206` `graph_rewrite(src, multi_pm)`**; **`src.contiguous_view()` —
ABSENT from the tree, and it is the BINDING one**, because `:210` returns `None`
when it is `None` so the rule has no fallthrough case; `:212` `buf[a:b]` +
`.bitcast`; **`:208` `.unshard` — ABSENT from the tree**.

**A CORRECTION TO THE BRIEF, and it matters.** The brief says this body "passes
**no ctx on any call**". That is right about the CALL SITES and wrong about the
SIGNATURE: **`:207` recurses with `ctx`** (`contiguous_mops_to_view(ctx, unshard.src[0], unshard.src[0])`)
and **`:213` writes `ctx.views.add(view)`**. So it needs ctx — weakly, because
`if ctx is not None` at `:213` makes the write optional. **The count of
no-ctx bodies among the twelve is FIVE, not two**, and this is the fifth.

**10. `canonicalize_call_body` `:239-240`** — a ONE-LINE body whose one line is
the rewriter: `c.replace(src=(graph_rewrite(c.body, pm_canonicalize_alloc,
ctx=CallifyCtx(), bottom_up=True),)+c.src[1:])`. The `replace` half is
`cks_rep` and **is ported**; the `graph_rewrite` half has **no `bottom_up` entry
point** — `ops.bend` has the top-down scan only. **There is no ctx work left
here: `CallifyCtx` exists.** The wall is the ENGINE, and it is the same wall
that blocks `create_linear_with_vars`.

**11. `replace_input_buffer` `:248-250`** — the ONLY ctx body left, so it is the
last C2 item. The append and the `len` are one `List.append` and one
`List.length`; the mint is the wall: **`UOp.param_like` is `TODO(p3) ops.py:1239`
at `uop/ops.bend:4398`** — named, unported, and named as a TODO, so this is a
**recorded deferral and not a gap I found**.

**12. `create_linear_with_vars` `:273-301`** — the TOP: five `graph_rewrite`
passes (`:276`, `:279`, `:282`, plus `:240` and `:267` inside the bodies above),
`capturing[0].add_linear` `:297`, `memory_plan_rewrite` `:301`, `used_vars`
`:285` (needs `UOp.variables`), and the bind-mismatch `raise` `:292`. Porting
it before any of the five matchers it calls would be a name with no body.

---

## 3. THE ORDER I USED, and why it is not line order

The lintable unit's discipline: blast radius is `n_targets`, and `lines-per-
target` is not a denominator. Ranking by `n_targets` **descending**, then lines
**ascending**:

| rank | body | n_targets | lines | note |
|---|---|---|---|---|
| 1 | `is_store_after` | 1 (`collect_stores`' only dep) | 5 | cheapest, unlocks the next |
| 2 | `copy_kernel_to_store` | **2** (two patterns in `pm_copy_from_store`) | ~30 | only 2-target body |
| 3 | `collect_stores` | 1 + the `CallifyCtx` record | ~20 | creates the record 2 more need |
| 4 | `assert_all_same_devices` | 1 | ~25 | |
| 5 | `simplify_copy_kernel` | 1 (guard) | 3 | shares 4's predicate |
| 6 | `lower_sink_to_linear` | 1 (guard) | ~20 | `pm_schedule` is a ONE-rule matcher |
| 7 | `apply_binds` | 1 (dispatch) | ~20 | |
| 8 | `canonicalize_alloc` | 1 | ~35 | |

Line order would have put `lower_sink_to_linear` `:124` and
`assert_all_same_devices` `:157` first, and both are **one target each** while
`is_store_after` `:217` and `copy_kernel_to_store` `:161` are nearer the top
under this ranking.

---

## 4. THE SUBSTRATE — `INCONCLUSIVE`, twice, with the evidence

`.agents/slop/schedule-bodies/INCONCLUSIVE.txt` and `SUBSTRATE-COLD.txt`.

**(i) `helpers.bend` WAS TRUNCATED TO ZERO BYTES, TWICE.** 18:38–18:47 the
first time, and again later. `sha256 = e3b0c442…` is the **empty-string**
digest. Every `.bend` in the tree imports `./../helpers.bend`, so the bend lane
could not run at all. `git diff --stat HEAD` on it read
**`2605 deletions`** — the owning unit had it open mid-rewrite. **NOT MINE. NOT
TOUCHED.**

**(ii) `uop/ops.bend` LOST TWO READERS I DEPEND ON.** It went **8313 → 6306
lines** (620 `def`s) between 17:47 and 17:49:
```
grep -cE '^def UOp\.(body|store)\(' ubendygrad/uop/ops.bend   ->  0  0
```
`ops.py:562 UOp.body` and `ops.py:622 UOp.store` were present when I started
and are **gone**. Every other reader this block uses — `UOp.unsharded_base`,
`UOp.toposort`, `UOp.new`, `eq_op`, `eq_dev`, `ParamArg.slot`,
`ParamArg.device`, `CallInfo.precompile`, `Arena.src0`, `Arena.src_from`,
`Arena.budget`, `Found.ar`, and all four `Ops` constructors — **SURVIVED**.

**MY RESPONSE, and it is a workaround to flip back:** `sc_body` and `sc_store`
are **local copies** in my file, each with a `TODO(p3)` naming the `ops.py` line
it mirrors. This is the SAME treatment `sc_topo` already has at `:448` — "a
second copy of `Topo.step`" — because `ops.bend` cannot call a def in this file.
**When `ops.bend` gets `UOp.body`/`UOp.store` back, delete both.**

**(iii) AND THEN THE SUBSTRATE CAME BACK — THE LIVE LANE IS GREEN.** At 18:53
`helpers.bend` was 116482 bytes again, and on the **LIVE** tree, with no plant:

```
$ ./bin/bend tinybendygrad/schedule/__init__.bend --check-only
ALL PROOFS CHECK
$ ./bin/bend tinybendygrad/schedule/__init__.bend | wc -l
81
$ grep -c -F -x -f BEFORE-rows.txt LIVE-rows.txt
81
```

**So §1 is a LIVE-TREE measurement and not only a plant one.** The plant is what
proved my own seven compile errors (P1-P7) while the live tree could not run at
all; the live run is what proves the floor. Both lanes, same 81/81.

**(iv) `sc_body`/`sc_store` ARE STILL THE RIGHT CALL.** `ops.bend` has still not
regained `UOp.body`/`UOp.store`, so the local copies stand — and they are the
reason the file compiles against a substrate that is 2000 lines shorter than the
one this unit was briefed on.

---

## 5. THE TRAPS THIS UNIT WALKED INTO, so the next one does not

1. **A Python `int` slot is a `U32` here.** `ParamArg.slot` is `U32`
   (`ops.bend:1278`), so `canonicalize_alloc`'s `slot >= 0` — which is TRUE for
   every Python int — has to be `slot < 2**31`, and Python's `-1` is
   `4294967295`. **`isign` exists because `U32.show` would print `4294967295`
   where CPython printed `-1`, and the gate would go red on a port that is
   right.** A row comparing a U32 against a Python negative is a false red.
2. **`CallInfo.of` is 0-ARG in `ops.bend` and 5-POSITIONAL in CPython**
   (`ops.py:1400`, `grad_fxn, name, precompile, precompile_backward, aux`).
   My first oracle passed `pre` in `name`'s slot and every `lsl_p_pre` row came
   out **0** — which read as a port bug and was an oracle bug. **A wrong
   `CallInfo` is a wrong `precompile`, and `precompile` is a `Bool`, so it is a
   silent flip and not a compile error.**
3. **`CallifyCtx.of` must take ALL FOUR fields.** A 0-arg `of` next to a 4-arg
   call site is `expected : a function type`.
4. **In bend 2.0.34 a def must be declared ABOVE its first use** — including a
   helper that only reads a record field (`ca_slot_u`, `rb_pa_name`, `raa`,
   `rnone_of_f`: four failures, one rule). **P6.**
5. **A `match` nested in a `case h <> rest:` LIST arm is refused**, and **the
   shrinking list must be the FIRST parameter** of a self-call. `asd_go` needed
   both.
6. **A parameter without `+` is CONSUMED ONCE.** Reading `c` four times in
   `aa_put` is an error, not a copy.

---

## 6. WHAT I DID NOT DO, stated plainly

- **No gate rows on the eight ports.** 89 oracle rows exist and are correct; the
  Bend side does not compile in `main`'s exhausted `do` block. **So the eight
  ports are UNPROVEN and a plant moves nothing on them.** That is a request for
  a fixture, not a coverage claim.
- **No mutation table.** With no rows there is nothing for a mutation to move.
- **No `bfold`/`empty-cache` lane.** `schedule_cache` is named as a wall
  (`:130-131`) and not exercised.
- **`sb-gate.sh` has never been run end to end** — it was written, and the two
  commands it wraps were run by hand. Treat it as unexercised.
- **`plant/` is a live artefact and should be deleted.** It is a throw-away copy
  (the lintable unit's `plant/` is too, and says so).
- **Nothing committed.**