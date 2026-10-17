# REMOVING `Ops.GROUP` AND `Ops.FLIP` FROM THE PORT -- CENSUS AND PLAN

**Nothing under `tinybendygrad/` was edited. `tinygrad/` was not touched.** Instrument:
`gates/opsref-census.py`, which regenerates every number below. Re-run:
`.venv/bin/python gates/opsref-census.py`.

---

## 0. THE STATE, RE-MEASURED (not relayed)

| claim | measurement | how |
|---|---|---|
| upstream has no `GROUP`/`FLIP` | `git show upstream:tinygrad/uop/__init__.py \| grep -cE '\b(GROUP\|FLIP)\s*=\s*auto\(\)'` = **0** | yes |
| upstream's enum is **75** | `tn_minimum-gate.py` `cpython_ops_count=75` | yes, ran it |
| the port's enum is **77** | `tn_minimum-gate.py` `port_ops_count=77` | yes |
| `HEAD:tinygrad` == `upstream:tinygrad` | both `62319c8ae612e51102916000d401d601a090353f` | yes |
| the behaviour was REIMPLEMENTED, not dropped | `UOp.group` -> `UOp(Ops.STACK).after(...)` at `tinygrad/uop/ops.py:536`; `Tensor.flip` -> a `transpose`/`PAD`/`reshape`/`SHRINK` loop at `tinygrad/mixin/movement.py:233` | yes |
| **`gates/tn_minimum-gate.py` IS ALREADY RED** | `rc=1`, `missing_from_port=0`, `extra_in_port=['FLIP','GROUP']` | yes, ran it |

**THREE CORRECTIONS TO THE BRIEF, each measured:**

1. **`tinygrad/movement.py` DOES NOT EXIST.** `Tensor.flip` is at **`tinygrad/mixin/movement.py:233`**
   (the brief says `tinygrad/movement.py:249-265`). The brief's path resolves to nothing, exactly
   the failure `AGENTS.md` records for `LAWS.bend` / `PROOF.bend`.
2. **The `gates/opseven-gate.py` closure carries THREE refs, not two.** Measured closure = **6
   files** (`gates/opseven.bend` + `helpers.bend`, `LAWS/spec.bend`, `uop/ops.bend`, `uop/fold.bend`,
   `uop/spec.bend`), and **3 of the 6** contain `Ops.GROUP`/`Ops.FLIP`: `ops.bend`, `fold.bend`,
   `spec.bend`. The brief names `fold.bend` and `spec.bend` and misses the file that *declares* the
   ops.
3. **The population is 141 on disk / 131 tracked, not 134.** `os.walk` finds **141** `.bend` under
   `tinybendygrad/`; `git ls-tree -r HEAD -- tinybendygrad` finds **131**. The gap is **10 untracked
   mutation-harness copies** (`dtype-mut.bend`, `op-mut.bend`, `.linearizer-mut.bend`,
   `.regalloc-mut.bend`, `realize-mut.bend`, `.wgsl-mut.bend`, `cstyle-mut.bend`, `_p6.bend`,
   `test/_probe/v5.bend`, `probe-mmcore.bend`). **Two of them carry a duplicate of these refs**
   (`dtype-mut.bend`, `.regalloc-mut.bend`), which is why a raw walk reads **20 files / 74
   occurrences** and only the tracked intersection reads **18 / 70**.

---

## 1. THE 70, REPRODUCED -- AND THE CLASS COUNTS

The prior **70** is **occurrences** (not lines, not files) in **18 tracked** `.bend` files. I
reproduced it by two independent mechanisms: a `grep -o | wc -l` over the tracked set, and the
classifier. **70 = 66 lines + 4 lines carrying a second occurrence.**

| class | sites | GROUP | FLIP | what deleting one changes |
|---|---:|---:|---:|---|
| **`EMIT`** | **17** | 9 | 8 | a GRAPH |
| **`CONSUME`** | **20** | 13 | 7 | a DECISION |
| **`SHAPE`** | **33** | 14 | 19 | an INDEX / enumeration |
| **`PROSE`** | **0** | 0 | 0 | nothing |
| total | **70** | 36 | 34 | |

**`PROSE` IS ZERO, AND THAT IS THE HEADLINE.** The brief warned that "grep will find hundreds of
these [prose citations] and they are not sites". **It does not, for this pair of ops.** Measured:
`grep -roE '\b(GROUP|FLIP|group|flip|Group|Flip)\b' --include='*.bend' tinybendygrad` = **416**
matches, and **none of them is a `OpsGROUP{}`/`OpsFLIP{}` occurrence inside a comment** -- the
classifier's comment/string stripper found zero. Every prose mention of `GroupOp.defines`,
`spec_full` or `Ops.GROUP` in this tree is spelled **without** the `Ops`-prefixed constructor, so
it never enters the census at all. **So the honest plan for prose is vacuous here: there is
nothing to leave and say why.** (Had the classifier found prose, the plan would still have been
"leave it" -- deleting a prose citation costs a `file:line` that `gates/citations-census-gate.py`
grades, for no behaviour change.)

### The discriminator, stated so a reader can re-derive every label

> **`EMIT`** the op is the **operand of a node constructor**. **`CONSUME`** the op is a **key of a
> `match`/`op_in`/`is_*`/`sp_op`/`lt_op_is`/name-string test**. **`SHAPE`** the op is an **item of
> an enumeration** the file returns as data. Two ordering hazards were found by running this and
> being wrong: (a) `case O.OpsFLIP{}: mm.lift.mv(srcs)` matches a constructor regex on `mm.lift`
> and reads as `EMIT` -- it is `CONSUME`, `mm.lift.mv` being the reader *the arm selects*; (b) an
> enclosing-`def` locator that accepts a same-indent sibling returns `<module>` for **every** site
> in the tree. Both are fixed in the instrument and both are recorded in its docstring.

The four enumeration tables in `ops.bend` are **not** guessed: the instrument imports
`gates/opseven-gate.py` **by path** and asks its own `_declared_ops` / `_value_arms` / `_name_arms`
/ `_all_ops`. That is the same discipline the file's `_body()` docstring demands ("a locator that a
rename invalidates is not a locator"). The generator answers **`declared=77, Ops.value=77,
Ops.name.of=77, all_ops=77`, `GROUP` at position 14, `FLIP` at position 73.**

---

## 2. EVERY `EMIT` (17) -- what it constructs

| # | file:line | def | what it builds | is it production or a proof fixture? |
|---|---|---|---|---|
| 1 | `uop/ops.bend:2802` | `UOp.group.of` | `UOp.new(nar, OpsGROUP{}, srcs, ...)` -- the 2+-src arm of `UOp.group` | **production** (`ops.py:561`) |
| 2 | `uop/ops.bend:2805` | `UOp.group` | `UOp.make(ar, OpsGROUP{}, ...)` -- interning a GROUP | **production** |
| 3 | `mixin/movement.bend:1557` | `mxw_flip_new` | `FLIP(t, flags)` for the `Tensor.flip` path | **production** (`movement.py:233`) |
| 4 | `mixin/movement.bend:1004` | `G.flip` | `FLIP(base, flags)` | fixture (`mxm_marg`'s arg reader) |
| 5 | `schedule/prepare.bend:278` | `pr_flip` | the `apply_movement_op` FLIP case | **DEAD vs upstream** -- see below |
| 6 | `uop/fold.bend:5526` | `g_mv_flip` | `FLIP(RESHAPE(6), (1,0))` | fixture |
| 7 | `uop/fold.bend:6355` | `main` | `lf_row("mv_flip", mm.lift(OpsFLIP{}, ...))` | proof row |
| 8 | `tensor.bend:2431` | `t_mop_flip` | `tn_mop(..., OpsFLIP{}, AOrder{[0]})` | proof row |
| 9 | `uop/render.bend:2561` | `rnd_ar` | an `O.Node{OpsGROUP{}, [1], ...}` in the renderer arena | fixture |
| 10 | `uop/validate.bend:2200` | `dv_unsup_two.of` | `GROUP(STACK, STACK)` for the unsupported-two test | fixture |
| 11 | `uop/symbolic.bend:2366` | `fx_group` | `GROUP(CONST(7))` | fixture for tag 11 |
| 12 | `uop/symbolic.bend:2376` | `fx_sink` | `GROUP(STACK(...))` | fixture for tag 12 |
| 13 | `uop/symbolic.bend:2392` | `fx_sinkgrp` | `SINK(GROUP(a), b)` | fixture; exists **only** for the GROUP rules |
| 14 | `uop/symbolic.bend:2427` | `fx_two` | `GROUP(SINK(CONST(7)))` | fixture; exists **only** to make tags 11 and 12 disagree |
| 15 | `renderer/ptx.bend:940` | `f14_skips_ss` | a `Wk{OpsGROUP{}, ...}` in the skip fixture | fixture |
| 16 | `schedule/indexing.bend:1407` | `g_ds` | `ix_g3(O.OpsFLIP{})` -> `UOp.new(ar, FLIP, [3 srcs])` (**2 occurrences on one line**) | fixture + row key |

**EMIT COUNT BY KIND: 3 production (`ops.bend` x2, `movement.bend` x1), 1 dead-against-upstream
(`prepare.bend:pr_flip`), 13 proof/gate fixtures.** Only **3** of 17 are on a path upstream still
has; and one of those three (`pr_flip`) is on a path upstream **deleted**.

**`pr_flip` IS DEAD, MEASURED.** `apply_movement_op` moved upstream to
`tinygrad/schedule/indexing.py:165` and its `match op:` has exactly **five** cases --
`SHRINK, PERMUTE, EXPAND, PAD, RESHAPE` -- then `case _: raise RuntimeError(f"{op} is not a
MovementOp")`. **There is no FLIP case.** So `pr_flip` is not "a rule to port", it is a port of a
rule upstream removed.

---

## 3. EVERY `CONSUME` (20) -- what it decides, and what upstream did to the rule

| # | file:line | def | the test | upstream now | action |
|---|---|---|---|---|---|
| 1 | `uop/ops.bend:518` | `GroupOp.movement` | 6-arm `True` ladder | `GroupOp.Movement` = **5** (measured, `tinygrad/uop/__init__.py:118`) | drop the FLIP arm |
| 2 | `mixin/movement.bend:539` | `mxm_arg_op` | `op_in([PERMUTE, FLIP], op)` | `ops.py:793`/`805` keep only `case Ops.PERMUTE` | set becomes `[PERMUTE]` |
| 3 | `mixin/movement.bend:1287` | `mxw_mv` | `op_in([6 movement ops], op)` | Movement = 5 | 6 -> 5 |
| 4 | `schedule/indexing.bend:1168` | `ix_mv_ops` | the written-out Movement set | Movement = 5 | 6 -> 5 |
| 5 | `schedule/multi.bend:273` | `mu_move_ops` | Movement, and it is `ra_4`'s **pdict key** (`multi.py:41`) | Movement = 5 | 6 -> 5 |
| 6 | `codegen/late/regalloc.bend:167` | `ra_is_pseudo3` | 4-arm pseudo-op ladder | `PSEUDO_OPS` = **7** (`codegen/late/regalloc.py:8`) | 4 -> 3 arms |
| 7 | `codegen/late/regalloc.bend:148` | `ra_pseudo_tbl` | the `PSEUDO_OPS` table | 7 | **the COUNT row `ra_pseudo_n` goes 8 -> 7** |
| 8 | `renderer/ptx.bend:386` | `arm.of` | `is_any3(op, [NOOP, GROUP, CONST])` -> `A_SKIP` | `ptx.py:187` is `if u.op in {Ops.NOOP, Ops.CONST}` = **2** | drop GROUP; `is_any3` no longer fits |
| 9 | `runtime/ops_python.bend:503` | `op_of` | `case "GROUP": Some{O.OpsGROUP{}}` | `upstream:tinygrad/runtime/ops_python.py` has **0** matches for `GROUP\|FLIP` | drop the arm |
| 10 | `runtime/ops_python.bend:1344` | `opname` | `case OpsGROUP{}: "GROUP"` | same | drop the arm |
| 11 | `runtime/ops_python.bend:2039` | `Prog.dispatch` | `case OpsGROUP{}: Prog.next(p)` | same | drop the arm |
| 12 | `uop/fold.bend:2363` | `addrspace_of` | `case OpsGROUP{}: one_addr(ss)` | `ops.py:899-901` addrspace lists `{INDEX,CAST,AFTER,REDUCE,STORE,MSTACK,MSELECT,END,UNSHARD}` + Movement -- **no GROUP** | drop the rung |
| 13 | `uop/fold.bend:2559` | `dt_shape` | `case OpsFLIP{}: flip_ds(...)` | `ops.py:388` Movement ladder has no FLIP arm | drop the rung **and `flip_ds`** |
| 14 | `uop/fold.bend:2571` | `dt_shape` | `case OpsGROUP{}: Late{}` | void/late ladder, no GROUP | drop the rung |
| 15 | `uop/fold.bend:4267` | `mm.lift.rest` | `case OpsFLIP{}: mm.lift.mv(srcs)` | same as #13 | drop the rung |
| 16 | `uop/spec.bend:1032` | `sh_19` | `sp_op(fx, self, OpsGROUP{}) and dt is void` | **`spec.py:98` is GONE** (measured: `grep 'Ops.GROUP' upstream` = 0) | **delete `sh_19` and its defs** |
| 17 | `uop/spec.bend:1184` | `sh_31.tri.of` | Movement 6 -> `None` | Movement = 5 | 6 -> 5 |
| 18 | `uop/symbolic.bend:1523` | `sym_11.pat` | `UPat(Ops.GROUP, src=(x,))` | **`symbolic.py:444` rule is GONE** | **delete `sym_11` and its defs** |
| 19 | `uop/symbolic.bend:1534` | `p_sink_like` | `sy_op_in(x, s, [NOOP, STACK, SINK, GROUP])` | **`REMOVE_FROM_SINK_LIKE` is now `{NOOP, STACK, SINK, AFTER}`** | **GROUP -> AFTER. NOT A DELETION** |
| 20 | `uop/symbolic.bend:1553` | `sym_12.pat` | `sy_op_in(x, u, [SINK, GROUP])` | upstream's pattern is `UPat(Ops.SINK, name="root")` -- **single-op now** | set becomes `[SINK]` |

Plus, in `viz/serve.bend`, the two colour rows `main:1806` (`op_color.GROUP`) and `main:1865`
(`op_color.FLIP`), and in `uop/symbolic.bend:3479` `fz_op`'s `case "group": O.OpsGROUP{}` name
parser. (`serve.bend`'s two are classed `SHAPE` by the instrument because `op_row(` is not in the
CTOR/TEST regexes -- they are **rows of a table**, so `SHAPE` is the honest label and they behave
like table entries.)

### 3a. THE ONE THAT IS NOT A DELETION -- `REMOVE_FROM_SINK_LIKE`

Measured: `upstream:tinygrad/uop/symbolic.py:439` reads
`REMOVE_FROM_SINK_LIKE = {Ops.NOOP, Ops.STACK, Ops.SINK, Ops.AFTER}`.
The port has `{NOOP, STACK, SINK, GROUP}`. **The fourth member changed identity.** A mechanical
"remove GROUP" leaves a 3-member set where upstream has a 4-member one and silently changes which
nodes get flattened. **This is the single site where a deletion is a behaviour regression.**

---

## 4. EVERY `SHAPE` (33) -- and WHICH ARE THE `58`-SHIFT

### 4a. THE `58`-SHIFT IS REAL **AND INCOMPLETE: 62 ARMS MOVE, NOT 58**

Measured through `opseven-gate`'s own `_value_arms()`, removing declared positions **14** (`GROUP`)
and **73** (`FLIP`) from a 77-arm `Ops.value`:

| band | arms | positions | example |
|---|---:|---|---|
| unchanged | **13** | 1..13 | `SPECIAL: 1 -> 1` |
| **shift by exactly one** | **58** | **15..72** | `STACK: 15 -> 14` |
| **shift by two** | **4** | **74..77** | `UNSHARD: 74 -> 72` |
| deleted | 2 | 14, 73 | `GROUP: 14`, `FLIP: 73` |
| | **77** | | **62 renumbered** |

**So "58" is the shift-by-one band alone and quoting it alone undercounts by 4.** `Ops.name.of` and
`all_ops` lose **one entry each** (77 -> 75) and are **keyed, not positional**, so nothing else in
them moves.

**Which SHAPE sites are the 58-shift:** **only `uop/ops.bend:390` (`Ops.value`) and
`uop/ops.bend:449`.** Everything else in `ops.bend` and every list in every other file is a
*length* edit with no renumbering.

### 4b. **FOUR TAG-INDEX SHIFTS THE `58`-SHIFT FRAMING MISSES ENTIRELY**

`O.PMEntry{tag, [ops]}` carries the tag as an explicit **field**, so deleting a tag renumbers every
tag above it -- and **those numbers are load-bearing**: `spec.bend` has **81** `sh_NN` defs with a
`case 19: sh_19(...)` dispatch at `:1290`, `symbolic.bend` has **81** `sym_NN` defs with
`case 11: sym_11(x, u)` at `:2159`, and `gradient.bend` has rows literally named `t_rej27` /
`t_rej29`.

| table | file:line | tags | the hit | tags above that shift |
|---|---|---:|---|---:|
| `gr_table` | `mixin/gradient.bend:935` | 0..32 (33) | **22 = `[FLIP]`** | **10** |
| `pr_ear_table` | `schedule/prepare.bend:343` | 0..28 (29) | 26 (carries both) | **2** |
| `shared_table` | `uop/spec.bend:1231` | 0..32 (33) | **19 = `[GROUP]`** (= `sh_19`, the deleted `spec.py:98` rule) | **13** |
| `sym_table` | `uop/symbolic.bend:2086` | 0..22 (23) | **11 and 12, both GROUP** | **10**, by **−2** |

### 4c. THE PROOF THAT ONE UPSTREAM DELETION IS ALREADY VISIBLE IN A CITATION BLOCK

`mixin/gradient.bend`'s `gr_table` rows end in a trailing `# NN` that cites the upstream line.
Measuring each cited line against where that op's `UPat` actually is **today**:

| tags | skew (`port_cite - upstream_actual`) |
|---|---:|
| 0..21 | **+1** (uniform) |
| **22 -- the FLIP row** | its own cite `90` now lands on `Ops.COPY`; **upstream has no FLIP `UPat` at all** |
| 23..27 | **+2** |

**The skew jumps from +1 to +2 exactly at the FLIP row.** Upstream deleted one line -- the FLIP
rule -- and every citation below it drifted one further. This is a falsifiable statement about what
the removal must do in `gr_table`: delete tag 22 **and** shift the `# NN` citations of tags 23..32
by −1.

### 4d. The remaining SHAPE sites

Enumeration only, no per-op decision. `uop/ops.bend:193`/`:272` (the `type Op is Data:` block),
`:304`/`:363` (`Ops.name.of` arms), `:4152`/`:4157` (`all_ops`); `codegen/decomp/dtype.bend:1989`
(`dd_ops.all`, **77 -> 75**); `schedule/prepare.bend:370` (`pr_ear_table`'s 77-op set) and `:446`
(`pr_ear_keys`, 77 -> 75); `schedule/rangeify.bend:862`/`:872` (`GS_ALL`, **76 -> 74**) and `:914`
(`MOPS_FB`, 6 -> 5); `uop/spec.bend:1037` (`OP_AFTER20`), `:1656` (`OP_PERMFLIP`, **the whole rule
is gone upstream**), `:2134` (`OP_ALL`, 76 -> 74), `:2144`/`:2147` (`OP_MOVE`), `:2551`
(`OP_AFTER12`); `uop/symbolic.bend:2098`/`:2099` (`sym_table` tags 11, 12); `viz/serve.bend:1488`
/`:1496` (`op_list`, 77 -> 75); `mixin/gradient.bend:958` (`gr_table` tag 22);
`schedule/multi.bend:304` (`mu_own` tag 7).

---

## 5. COMPOSITES -- BEFORE AND AFTER

Every one of the 33 `SHAPE` sites and 8 of the 20 `CONSUME` sites is a **COMPOSITE**: the op is one
tag among several in a list or ladder. Removing one tag changes the table's **meaning**, so each is
named here with its before and after.

| composite | before | after | the change in MEANING |
|---|---|---|---|
| `ops.bend:518 GroupOp.movement` | 6 arms `True` | 5 | `GroupOp.Movement` = 5 upstream -- **the set's IDENTITY changes** |
| `movement.bend:539 mxm_arg_op` | `[PERMUTE, FLIP]` | `[PERMUTE]` | no longer "the two ops whose `marg` is an `ATuple`"; now "the one op" |
| `movement.bend:1287 mxw_mv` | `[RESHAPE,EXPAND,PAD,SHRINK,PERMUTE,FLIP]` | 5 | = upstream Movement |
| `indexing.bend:1168 ix_mv_ops` | 6 | 5 | = upstream Movement |
| `multi.bend:273 mu_move_ops` | 6 | 5 | **is `ra_4`'s pdict key** -- the key changes, so the dict's buckets change |
| `prepare.bend:914`(`rangeify`) `MOPS_FB` | 6 | 5 | child-set of `.f`/`after`/`end` receivers |
| `regalloc.bend:148 ra_pseudo_tbl` | `PSEUDO_OPS` 8 | 7 | **`ra_pseudo_n`'s COUNT row 8 -> 7** -- a literal `8` here is a row no predicate mutation can move |
| `regalloc.bend:167 ra_is_pseudo3` | 4 arms | 3 | must stay equal to the table |
| `ptx.bend:386 arm.of` | `is_any3([NOOP,GROUP,CONST])` | 2 | `is_any3` is named for 3; the call site must change shape |
| `symbolic.bend:1534 p_sink_like` | `[NOOP,STACK,SINK,GROUP]` | **`[NOOP,STACK,SINK,AFTER]`** | **not a deletion -- GROUP is REPLACED by AFTER** |
| `symbolic.bend:1553 sym_12.pat` | `[SINK, GROUP]` | `[SINK]` | upstream's pattern is single-op `UPat(Ops.SINK)` |
| `symbolic.bend:2098 sym_table` tag 11 | `[GROUP]` | **row deleted** | and **10 tags below renumber** |
| `symbolic.bend:2099 sym_table` tag 12 | `[SINK, GROUP]` | `[SINK]` | **and 10 tags below renumber by −2** |
| `spec.bend:1251 shared_table` tag 19 | `[GROUP]` | **row deleted** (`sh_19` dies) | **13 tags renumber** |
| `spec.bend:1656 OP_PERMFLIP` | `[PERMUTE, FLIP]` | `[PERMUTE]` | `spec.py:166`'s `(PERMUTE, FLIP)` rule is **gone upstream** |
| `ops_python.bend:503/1344/2039` | one arm of a name/op/route table | arm removed | each is a `case` in a longer match |
| `viz/serve.bend:1806/1865` | `op_color` rows | rows removed | `op_color_len`'s `\|65` row must be re-measured |
| the five enumeration lists | 77 / 76 / 6 / 8 | 75 / 74 / 5 / 7 | length only |

---

## 6. `checks/substrate.py` HALF 2 -- **RAN IT, TWICE, AND IT IS THE POST-DELETION DETECTOR**

**I ran it, and it is green today.** `substrate.half2()` over the walk population (141 files):

```
TOTALS refs=41832 exact=41832 suffix=0 unresolved=0 unseen=47333 missing_module=0 dead_import=44
BAD 0
HALF2_lines_naming_OpsGROUP_or_OpsFLIP = 0
```

**HALF 2 names ZERO `OpsGROUP`/`OpsFLIP` today, because today the names exist.** It is not a
pre-deletion detector; it is a **post-deletion** one. So I measured what it would catch, by
copying the tree **outside the repo**, deleting **only** the two variants from
`ops.bend`'s `type Op is Data:` block, and re-running:

```
TOTALS refs=41832 exact=41769 suffix=0 unresolved=63 unseen=47333 missing_module=0 dead_import=44
BAD 62
HALF2_after_deletion: lines naming OpsGROUP/OpsFLIP = 62  (GROUP=33, FLIP=29)
files named: 19 of 20
```

**WHAT HALF 2 CATCHES: 62 of the 63 cross-module sites, in 19 of 20 files.** The accounting closes
exactly:

- `74` occurrences (walk) `− 11` in `ops.bend` = **`63` unresolved** occurrences;
- `indexing.bend:1407` carries `OpsFLIP` **twice on one line**, so `63` occurrences dedupe to
  **`62`** `BAD` sites.

**WHAT HALF 2 CANNOT CATCH -- measured, not assumed: `uop/ops.bend` ITSELF.** HALF 2 resolves only
*cross-module aliased* references (`pool` is built from `IMPORT` aliases), so same-module
references are invisible to it. **`ops.bend` is the ONE file of the 20 that HALF 2 cannot name**,
and it is the file that *declares* the ops. A HALF-2-only completion check would therefore pass
with `ops.bend` entirely untouched. **`checks/substrate.py` HALF 1 (`bend --check-only`) is what
covers `ops.bend`.**

---

## 7. THE REMOVAL ORDER, AND WHY

Ordered so that **no intermediate state is a silent behaviour change**, and so the two gates that
already exist go green as early as possible.

**Step 0 -- FREEZE THE CLAIM.** `gates/opsref-census.py` is committed and re-runnable. Every
number above has a command behind it. (Done.)

**Step 1 -- THE PRODUCTION PATHS, BOTH ENUMS AT ONCE. (3 `EMIT` + 2 `CONSUME`)**
`uop/ops.bend:2802,2805` (`UOp.group` -> upstream's `UOp(Ops.STACK).after`), and
`mixin/movement.bend:1557` + `mxm_arg_op:539` + `mxw_mv:1287` (`Tensor.flip` -> upstream's
transpose/PAD/SHRINK loop).
*Why first:* these are the only three `EMIT`s on a path upstream still has. Doing them first means
the **only** behaviour the port exposes afterwards is behaviour upstream also exposes. Everything
after this is bookkeeping.

**Step 2 -- THE FIVE WRITTEN-OUT `GroupOp.Movement` SETS, 6 -> 5.**
`movement.bend:1287`, `indexing.bend:1168`, `multi.bend:273`, `rangeify.bend:914`,
`spec.bend:1037`/`2144`/`2147`/`2551`, `ops.bend:518`.
*Why now:* they are the **common factor** of steps 3-5 (every remaining rule that tests "is this a
movement op"). Fixing them once means the later deletions are single-tag deletions in tables
whose op sets are already correct. **Do NOT renumber `Ops.value` yet** -- see step 6.

**Step 3 -- THE RULES UPSTREAM DELETED WHOLESALE. (4 sites, and they are the EXPENSIVE ones)**
`spec.bend` `sh_19` + tag 19 of `shared_table`; `symbolic.bend` `sym_11` + tag 11 of `sym_table`;
`OP_PERMFLIP` (`spec.bend:1656`); `prepare.bend:pr_flip` (`fold.bend`'s `flip_ds` with it).
*Why here and not first:* each deletes a tag, so each triggers a **local renumbering** (§4b). Doing
them in one step means the four renumberings are four diffs instead of four interleaved ones, and
the next agent reads one commit per table rather than one commit per table-per-site.
*These are the ones that need upstream re-reading, not port editing:* `spec.py:98`, `spec.py:166`
and `symbolic.py:444` no longer exist.

**Step 4 -- `REMOVE_FROM_SINK_LIKE`: GROUP -> AFTER, NOT A DELETION.**
`symbolic.bend:1534` (`p_sink_like`) and `:1553` (`sym_12.pat`).
*Why isolated:* it is the only site where "delete the op" is **wrong**. It deserves its own commit
and its own diff review, because a reviewer scanning for "did they drop GROUP?" will otherwise
approve the wrong edit.

**Step 5 -- THE BACKEND / RENDERER / VIZ TABLES.**
`runtime/ops_python.bend:503,1344,2039`; `renderer/ptx.bend:386` (+ its fixture `:940`);
`codegen/late/regalloc.bend:148,167` (**and the `ra_pseudo_n` COUNT row 8 -> 7**);
`codegen/decomp/dtype.bend:1989`; `viz/serve.bend:1488,1496,1806,1865` (+ `op_color_len`'s `|65`);
`mixin/gradient.bend:958` (+ the `# NN` citation shift of §4c); `uop/fold.bend:2363,2559,2571,4267`;
`runtime/ops_python.bend`; `uop/symbolic.bend:3479` (`fz_op`'s name parser).

**Step 6 -- THE DECLARATION AND THE FOUR ENUMERATION TABLES, LAST.**
`uop/ops.bend:193,272` (`type Op is Data:`), `:304,363` (`Ops.name.of`), `:390,449` (`Ops.value` --
**the 62 renumbered arms**), `:4152,4157` (`all_ops`); `schedule/prepare.bend:370,446`;
`schedule/rangeify.bend:862,872`; `uop/spec.bend:2134`; `viz/serve.bend:1488,1496`.
*Why last, and this is the load-bearing reason:* **HALF 2 names nothing until the variants leave
`type Op is Data:`, and `bend --check-only` (HALF 1) is red for every step 1-5 the moment any
remaining `OpsFLIP{}`/`OpsGROUP{}` loses its constructor.** Deleting the declaration first turns
every un-migrated site into a compile error at once and destroys the ability to bisect. Deleting it
last means **each step is independently compilable**, and the final step is the one that makes
HALF 2 go from `BAD 0` to `BAD 0`-with-62-caught-then-0 again.

**Step 7 -- REFRESH THE TWO GATES THAT GO RED ON PURPOSE.**
`gates/opseven-gate.py --refresh` (its four `value_*` pins are stale **by construction** -- its own
header says so: "when the re-vendor removes them from `ops.bend` these pins go stale ON PURPOSE and
the gate goes RED until `--refresh`"), and `gates/tn_minimum-gate.py` should go from today's measured
`rc=1, extra_in_port=['FLIP','GROUP']` to `rc=0`. **Those two reds are the work being done, not
work outstanding.**

---

## 8. FOUND BUT NOT DONE

1. **`GS_ALL` and `OP_ALL` are 76, not 77 -- they omit `CONST`** (measured, by set difference
   against `ops.bend`'s own `all_ops`). Upstream's `GroupOp.All = set(Ops)` **includes** `CONST`.
   So this work takes them **76 -> 74** against upstream's **75**: **the `CONST` gap is PRE-EXISTING
   and is NOT fixed by removing GROUP/FLIP.** Flagged, not fixed -- it is outside the grant.
2. **`mixin/gradient.bend`'s `# NN` citation block is already +1 stale everywhere**, independent of
   GROUP/FLIP (§4c measures the uniform `+1`). Only the extra `+1` below the FLIP row is this
   task's.
3. **I did not run `bend` at all** -- not `--check-only`, not anything. Other units are working and
   `bend` is memory-heavy; no step of this plan was validated by execution.
4. **`gates/opseven-gate.py`'s header prose is STALE** in a way this work will make worse: it says
   "the seven members ... that the 34-graph corpus does not build" and "upstream declares **75**"
   while the file still declares 77. `tn_minimum-gate.py`'s header likewise says "the port's `Ops`
   and CPython's `Ops` are the SAME 77 members" -- **measured false today** (75 vs 77). Two
   governing-document claims that are already wrong.
5. **The two untracked `-mut.bend` copies** (`dtype-mut.bend`, `.regalloc-mut.bend`) each carry a
   duplicate of these refs and are **outside HEAD**. They are mutation-harness scratch; whoever
   deletes the op must delete it there too or the harness will report a phantom pass.
6. **`symbolic.bend`'s `fx_sinkgrp0` and the `sym_12` M20/M22 mutation rows** are about a rule whose
   op set changes meaning (`GROUP` -> `AFTER`). The pinned slots (`eq_u(..., 6)` vs `3`) in
   `fx_sinkgrp`'s own comment may move. **Not measured** -- that needs `bend`.
7. **`.agents/TODO.md` was not touched**, per instruction. This task is not on it.

---

## 9. THE TREE MOVED UNDER THIS REPORT -- AND IT MOVED THE RIGHT WAY

**Every count in §1-§5 is a reading of `tinybendygrad/` at the moment `gates/opsref-census.py` last
printed 70. A concurrent unit then landed, and the census now reads 68.** Recorded here rather than
silently re-run, because a number that was true and is quietly replaced is the failure this tree's
own doctrine is about.

Measured delta, `gates/opsref-census.py` re-run, `git diff -- tinybendygrad/uop/ops.bend`:

| | was | now |
|---|---:|---:|
| SITES | 70 | **68** |
| EMIT | 17 | **15** |
| CONSUME / SHAPE / PROSE | 20 / 33 / 0 | 20 / 33 / 0 (unchanged) |
| files | 18 | 18 |

The **two** sites that left are **`uop/ops.bend:2802` (`UOp.group.of`) and `:2805` (`UOp.group`)** --
and they left because the other unit **replaced `UOp.group` with `UOp(Ops.STACK).after(...)`**,
quoting `ops.py:536-538` and the `if len(srcs) == 1 ... return srcs[0]` guard, with `OpsGROUP{}`
still present in the `type Op is Data:` block and in `all_ops` (`:4160`).

**That is §7's Step 1, arrived at independently, and it confirms the ordering:** the declaration and
the four enumeration tables were left for LAST, so every intermediate state is still compilable and
HALF 1 is not red mid-flight. `all_ops` moved `:4152 -> :4160` and `:4157 -> :4165` (+8 lines) with
no op removed from it, which is why **line numbers in §2-§5 are only valid against the commit
`0fd4e2f9229bfdaaf0ff059b076b7fe92de135be`**; the **def names** in §2-§5 are the durable locators
and are unaffected.

**What this means for a next agent: re-run `gates/opsref-census.py` before planning, and treat the
def NAME, not the line number, as the locator.** An instrument that printed a number is worth
nothing if the number's subject has moved and the instrument cannot say so.

**And it is a second measured instance of the point the brief opened with** -- a reference is not a
site. `UOp.group.of` was an `EMIT` at 70 and is not one at 68, for a reason that has nothing to do
with the census and everything to do with the tree.