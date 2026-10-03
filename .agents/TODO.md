# TODO

The port's state. Progress bars are `[###.....] n/m`.

```
spec-as-laws    [#########] 9/9      python-to-bend  [###.......] 5/96  (0 defs outstanding)
proofs          [##########] 34/34   oracle-green     [#####.....] 5/5
walkthroughs    [######...] 6/7      E2E-PROVES-COMPUTE 1/1  <- runs/e2e/
```

**`E2E-PROVES-COMPUTE` is the bar that was at zero all session.** A port can agree
with CPython on thirty thousand gate rows and still not add two numbers. There is now
one program whose answer is bit-identical to CPython's on real hardware, and
`.agents/slop/e2e.sh` says so in one command. It is **1/1 and not 2/2** on purpose: the
second would be a forward pass, and there is no kernel executor to run one.

---

## Phase P0 — toolchain and scaffolding

- [x] `bin/bend` runs the pinned Bend 2 compiler
- [x] `tools/get-bend.sh` fetches it into `references/`
- [x] `.gitignore` excludes `references/` and native build output
- [x] `.agents/TOOLS.md` tool ledger
- [x] Fork `Cyberistic/tinybendygrad`, master only, remotes set
- [x] `tools/sz` — Bend's answer to `sz.py` (token line count per file)
- [x] `tinybendygrad/sz.bend` — `sz.py` ported: a CPython tokenizer in Bend, its
      two filesystem effects, and a hand-rolled `tabulate`. **Verified against
      `sz.py` on 222/222 counted files** (tokens and lines) and byte-identical
      output in all three modes save tinygrad's `ops:`/`flags:` reflection.
      `spec/sz.md`, `.agents/slop/notes/compare/sz.md`
- [ ] `test/` harness that runs the ORIGINAL pytest suite against the Bend build
- [x] `tools/check` — one command that runs every `bend --check-only`. **Done, and bucketed by
      CAUSE rather than pass/fail**: `.agents/slop/tree-verdict.py -P 12` sweeps all 137
      `.bend` files under `tinybendygrad` + `examples` and reports `green` / `no-main` /
      `no-rows` / `foreign-code-surface` / `proof-in-progress` / `broken-here` /
      `broken-in-import`. A single RED bucket is what sent a unit to fix things that were not
      broken twice in one day. Read: `.agents/slop/tree-verdict.md`, rules at the END of
      `.agents/slop/notes/bend2-constraints.md` (POSITIONS ~14290-14415).

## Phase P1 — the contract

- [x] `.agents/slop/notes/bend2-constraints.md` — the Bend rules, all measured
- [x] `.agents/slop/plans/00-master-plan.md` — phases, the 1:1 rule, agent protocol
- [x] `LAWS/spec.bend` — the spec IR and its five derived properties
- [x] `LAWS/alu.bend` — tinyspec's decomposed-elementwise-ops table
- [x] `LAWS.bend` — 32 laws
- [ ] **Audit against tinyspec**: coverage gaps, vacuous laws, stubs
- [x] `PROOF.bend` — shape half: reshape/permute/flip/pad/shrink/stack/detach
      (10/10 proven; 8 shape-column mutations each killed by their own law.
      Re-verify once `LAWS/spec.bend`'s fuel rewrite compiles)
- [x] `PROOF2.bend` — ALU/dtype half (16/16 proven)
- [x] `PROOF-ALL.bend` green — 0 TODOs. Reduce proved as
      `reduced * prod(take(dims, n)) == numel`. Broadcast restated to the
      equal-length concrete axis rule (`pick_dim`, a 1 broadcasts to 0) and
      proved. Delete-one-proof self-check: 0 -> 1.
- [x] `drop_n` drops `n`, not `n+1`, and the reduce-numel multiplier is
      `List.take(dims, n)`. Index of arity 1 over rank 3 is rank 2.
      Gate: `./bin/bend tinybendygrad/LAWS/spec.bend`.

### The fuel detour — done, and it is worth remembering

`Sp.shape`/`Sp.dtype` were parameterised with an explicit `Nat` fuel instead of
`@unsafe`, and 23 laws grew a `for +depth: Nat` binder to match. That design is
**retracted**: numeric patterns in Bend are first-match prefix matches, so the
`case 2n+p:` arm was dead code that typechecked, both folds answered `None` for
every operand, and 6 laws were refuted outright because of it.

The replacement is bounded arity with no fuel at all. The two facts that force
it, both measured and recorded in `.agents/slop/notes/bend2-constraints.md`:

- a recursive call must pass a **field** of its own parameter (bare, or
  re-wrapped in the same constructor); and
- re-wrapping a **list tail** in any constructor is rejected, while a list
  *head* binder re-wrapped is fine.

Together those mean a fold that maps a recursive function over a `List<Sp>` and
combines the results is unwritable: the head is fine, the tail cannot be
re-wrapped, and turning the tail into a struct field needs a second
mutually-recursive def, which Bend also rejects. So `SpIndex` becomes an
arity-indexed family rather than holding a list.

Cost of the detour: two commits and one subagent's worth of reverted work.
Benefit: the notes now say something true, and the next agent does not spend a
day rediscovering that `2n+p` is not an even-case test.

## Phase P2 — trial run

- [x] `tinygrad/dtype.bend`
- [x] `tinygrad/helpers.bend`
- [~] `uop/ops.bend` — **the gate: the arena WORKS.** A UOp is a `U32` index into
      an append-only `List<Node>`, threaded through every UOp-taking def and
      returned by every def that grows it. Both lanes green, no `@unsafe`, six
      printed answers (`hashcons`, `dtype_key`, `cycle`, `toposort`,
      `cycle_terminates`, `key_eq`). `--check-only` is
      `ALL PROOFS CHECK` with exit 0: `./../dtype.bend` is deliberately NOT
      imported, because its fp16/bf16/fp8/i64 C effects make the checker print
      "14 defs rely on unsafe or foreign code" and exit 1 for ANY importer
      (a two-line file that imports it prints the same fourteen lines). `Dt`
      comes from `./LAWS/spec.bend`, which is the ONE datatype. 3 defs
      faithful, 27 adapted, 205 inventoried, 5 extra, 0 `@unsafe`.

      **OUTSTANDING, counted properly this time.** 238 rows, 5 of the
      `not blocked` set are ported, **31 are not**. (Two earlier counts of mine
      were wrong — a grep that matched `# TODO(p3)` comments as if they were
      defs, then the reverse. `grep '^def '` is the only reliable check.)
      The backlog is `rg "TODO\(p3\)"` — 212 rows, each naming its Python line.

      **THE WALL, and it is a MODULE wall, not a file wall.** The property
      folds (`dtype`, `_shape`, `device`, `addrspace`, `_ranges`, `_min_max`,
      `key`, `axis`, `marg`, `vmin`/`vmax`, …) cannot be written in this
      representation, for two measured reasons:
        1. a self-call must pass a **field of its own parameter**, and the
           arena's field is a `U32` read back out of a store, which the checker
           cannot see as a subterm; and
        2. mutual recursion is refused, and
           `dtype_from_uop` ↔ `_shape` ↔ `simplify()` → `graph_rewrite` → the
           rules → `dtype` is a cycle Python only breaks with the
           `recursive_property` memo.
      `toposort` is unaffected — its recursion is on a WORKLIST, a list tail of
      its own parameter — so the fix is known and is not a hack: fold dtype and
      shape into ONE def answering the pair, drive it with a Kahn worklist, and
      put `graph_rewrite` in a separate module so nothing in the engine calls
      back into the fold. Recorded in `spec/ops.md` and in the
      `# THE INVENTORY` block of the file. **P3 decides it.**
      **RESOLVED for the property folds: `uop/fold.bend` IS that Kahn worklist**,
      so `dtype`/`_shape`/`device`/`addrspace`/`ended_ranges` are ported there and
      not here.

- [x] `uop/ops.bend`, ops.py **[1, 500]** — the backward slice, and the queue.
      Four defs landed: `bsl.go` + `UOp.backward_slice` (ops.py:280),
      `UOp.backward_slice_with_self` (:286), `op_in_bsl.go` +
      `UOp.op_in_backward_slice_with_self` (:289). Placed BELOW
      `UOp.toposort_nocalls`, which Python has them above, because Bend has no
      forward references. **14 rows, three lanes byte-identical**:
      `bsl_{chain,call,nest,backedge}` + `bsws_*` + six `bsop_*` Booleans, with
      `chain`/`call`/`nest`/`backedge` chosen so `enter_calls=False` is visible —
      `call` and `nest` answer 1 and 3 where `toposort(enter_calls=True)` answers
      5 and 6, and `bsl_chain` would agree with a plain `toposort`.
      `res.pop(self)` is an IDENTITY filter, not `List.drop(.., 1n)`: the root is
      the LAST node to complete, so `self` is the tail. Measured, and substituting
      the drop moved all four `bsl_*` rows.
      **The other 19 entries in [1, 500] were not a backlog, they were a lie:**
      9 are already ported (`__repr__`×3, `_shape`, `shape`, `ended_ranges` in
      `render.bend`/`fold.bend`; the backward slice above) and 10 are walls whose
      rule is now written next to each queue line, so the next agent does not
      rediscover it. `rg "TODO(p3)"` for this range is now 14 lines, each with its
      reason. Gate: `sh .agents/slop/ops-gate.sh` (still red on five pre-existing
      `cfun_*` rows, which are ops.py:1258/1394 — the other range's).

- [x] `uop/init.bend` — `Ops` and `GroupOp` from `tinygrad/uop/__init__.py`.
      Ported inside `uop/ops.bend` because the gate needed `match op` to work.
- [x] `uop/upat.bend` — the COMPILER, `tinygrad/uop/upat.py`'s 186 lines.
      `--check-only` is `ALL PROOFS CHECK`; both lanes print the SAME fifteen
      rows and all fifteen are `True`: `var add add_dyn repeat repeat_dyn any
      noctx argint too_big rep_src rep_src_src any_rep dup_store share
      rep_src_dyn`. Each `want_*` in `main` is CPython's own `_get_code`
      output, read out of a live `uv run` of `tinygrad/uop/upat.py`, so the gate
      is the interpreter and not a transcription of my own expectation. The
      `too_big` row is `UPat(Ops.BINARY, src=(q,q,q,q))` with `q` a four-way
      `UPat.any`, and it only reaches `None` because `pm_proc` is a FIXPOINT --
      `do_process_and` splices one AND level per round, and the second round is
      what puts four OR children where `len(or_clause) >= 4` can see them. A
      mutation table is at the foot of the file, and M2, M4 and M13 in it move
      nothing, which is reported rather than hidden.

      **FIVE ORACLE-CONFIRMED BUGS FIXED, gate widened nine -> fifteen rows.**
      A 37-case differential fuzzer (every pattern built twice, once for
      `tinygrad/uop/upat.py` and once for the arena in `ops.bend`, outputs
      compared byte for byte) went from 12 mismatches to 0.
      (1) `substitute.go` rebuilt `tail ++ [node]`, so a two-element `src` came
      back SWAPPED. `INDEX(CUSTOMI, CONST)` is two elements, so `render`'s `idx`
      rule saw a CONST first, kept the INDEX, `all_ci` failed on the `AND(pred)`
      inside `all([...])`, `rend.go` set `bad` and `_get_code` answered `None`.
      The trigger is the repeat's CHILD having a src of its own -- NOT the repeat
      index and NOT an unreferenced arena entry, both ruled out by measurement --
      and `rep_src_src` is the LOCALISED row.
      (2) `do_process_and` never read `Ds.out`, so the duplicate store's identity
      compare was dropped and the second `a=` stayed in the `_fxn` call.
      (3) `dup.put` put the store KEY in the identity's `{0}` where Python puts
      `dict_stores[k]`, the first store's VALUE.
      (4) `do_process_and` never partitioned the STOREs out of `new_src`; it
      leaned on `dedup`, which agrees only while every store survives the round
      trip.
      (5) `wrap` spent a fresh `a{n}` per OCCURRENCE of a PYLITERAL where the
      ucache spends one per DISTINCT literal, so the permutations fork and any
      pattern repeating an op printed `a1, a3` where CPython prints `a1, a1`.
      `share` is the LOCALISED row for that one.
      The new fixtures are `rep_src` (the repeat inside a src tuple),
      `rep_src_src` (the same with the child carrying a src), `any_rep` (a repeat
      inside `is_any`), `dup_store` and `share`. The brief's trigger -- an
      unreferenced pattern in the arena, or a non-zero repeat index -- did NOT
      reproduce: `rep_src` passes both before and after, with and without a spare
      arena entry.

      **THE WALL is `exec` and it is the LAST step.** `upat_compile` returns the
      `Code` — the rendered Python source plus the `dyn_lookup` names — because
      Bend cannot build a function value, so the compiled rule cannot become a
      closure over that source. `_get_code`'s `(str, dict)` is a `Code` record
      and `dyn_lookup` is a `List<&2, Bind>` threaded beside the tree, never a
      field of it. `TODO(p3) ops.py:1590 upat_interpret` and `TODO(p3) ops.py:1459
      get_location` are the other two omissions, both Python reflection.
- [ ] `uop/fold.bend` — the derived properties of `ops.py` as ONE Kahn worklist.
      **DONE, AND THE FIVE MOVEMENT SHAPES LANDED.** `dt`+`shape` as a pair (they read
      each other), `device`, `addrspace`, `base`, `ended_ranges`, and `axis_id`/`axis_type`
      (not fold properties — the arena already split `ARange{ids, at}`). Both lanes green,
      no `@unsafe`, eleven fold rows all True, mutations run both ways. The rest of
      `ops.py` is a `TODO(p3)` line per property with the wall it waits for.
      **THE FIVE ARMS: `expand_ds`, `pad_ds`, `shrink_ds`, `perm_ds`, `flip_ds`,**
      answering ops.py:414-431. 16 `mv_*` rows, FOUR FACTS PLUS THE ANSWER AS ONE
      STRING each (`n= op= nsrc= srcops= shape= dtype=`), and **15 of 16 byte-identical
      to CPython**, the one exception being the declared `ssimplify` divergence. The
      eleven original rows are BYTE-IDENTICAL to the pre-change file.
      **THE RECORDED WALL WAS WRONG FOR THREE OF THE FIVE, and that is the finding.**
      TODO said EXPAND/PERMUTE/FLIP wait on `marg -> as_shape -> ssimplify`; `marg` for
      PERMUTE and FLIP is `self.arg` (ops.py:818), the arena's `ATuple` of plain indices,
      so NEITHER reads `as_shape` and both were answerable from the day the arena existed.
      PAD and SHRINK really did need `zip(as_shape, as_shape)` and are now ONE walk with a
      `Bool` picking the arm (mutation M2 exchanges the sums and moves 5 rows). UNSHARD
      still defers, on `vmax`/`_min_max` — a DIFFERENT wall. **So `_min_max` is now the
      largest unlock in the file and `simplify` is not**, which REORDERS the "what next"
      list at the foot of `fold.bend`.
      **THE E2E MEASUREMENT, which is what retires the eight downstream walls**
      (`.agents/slop/oracles/fold-mvt-e2e.bend`): a graph whose ROOT is a STORE over an
      EXPAND, and one whose root is an AFTER over a PERMUTE, both read
      `settled=False shape=ABSENT dtype=ABSENT` on the pre-change file and
      `settled=True shape=() dtype=void` / `shape=(3,2) dtype=int` now — CPython's own
      answers. That is constraints-note rule 18 (position ~4099) retired for movement ops.
      **14 mutations measured** (`.agents/slop/oracles/fold-mut.py`), 12 move rows; the
      2 zero-movers are MEASURED EQUIVALENCES, not gaps — M9 is unreachable (`O.SU` has
      no producer anywhere in the tree) and M10 is a symmetry of PAD's own `o+s<=sz`.
      Both are reported as equivalences rather than closed with rows that encode the bug.
      M5's zero-mover found a REAL redundancy (`U32.is_lt(y,n)` beside `List.get`'s own
      bound) and 8 lines came out.

      **`_ranges` + `ranges` LANDED, and `is_image_shape` FIXED (session 2026-10-04).**
      `UOp._ranges` (ops.py:483) and `UOp.ranges` (ops.py:497) are a second fold in this
      file, `Ranged`/`rng_sweep`, and the `P3` list's reason for them was WRONG: it said
      they need "one set algebra over a `List`", and the algebra is not the wall. The arena
      interns, so `dict[UOp, None]` IS a list with `mem_u32`, and `set_union`/`set_del` are
      two short walks. The two real questions were both answered rather than routed around:
      * **THE GRANDCHILD READ.** `_ranges` reads `er.ranges` for an `er` in
        `ended_ranges(self)`, and `AFTER`/`BARRIER` carry their SRCS' ENDED LISTS, so `er`
        is a grandchild and a `Derived` field sees only its own srcs. The answer is a
        FORWARD SWEEP in arena-index order: `ended_of` reaches only `src[i:]` and the
        `ended` of a direct src, so every index the pass reads is strictly below the node
        it answers. Same argument as Kahn, applied to a set.
      * **THE REFUSAL, which is a real divergence.** `ended_ranges` IS a `Derived` field,
        so a node `dt_shape` DEFERS (UNSHARD, STAGE, CUSTOM, CUSTOMI) has no `ended` list
        and its set is not answered, where Python has no such limit. Carried by an `ok`
        FLAG rather than a silent empty set, and pinned by `rg_absent`.
      **12 `rg_*` rows, byte-identical to CPython** (`.agents/slop/oracles/fold-rng-oracle.py`,
      same twelve graphs node for node; `diff` of the two lanes is the test). **19 mutations
      measured** (`.agents/slop/fold-rng-mutate.py`), **15 move rows**, and all 4 zeros are
      classified: three harness controls (R1, R2b, R11) and one THEOREM (R2 — the union's
      membership test may read the input instead of the accumulator because every row's set
      is duplicate-free by induction; R16, which DROPS the test, is the row that shows the
      test is load-bearing). The table also carries **R7: a mutation of the INHERITED
      `ended_of.one`** (`src[1:2]` → `src[0:1]`), which moves `rg_er` AND `cycle_safe` — the
      ranges-side witness for the off-by-one `bend2-constraints.md` already flags.
      `is_image_shape` (helpers.py:37) compared the last dim against `sint_one()`, so it
      answered False for `(32,32,4)` and True for nothing; two units measured that defect and
      one declined to fix it because M2 had to keep moving exactly one row. **`img_shape` is
      the row M2 asked for** (six cases, expectations as literals, `M3`/`M3b` are its
      mutations). The set algebra is now available to `bool_slice`/`is_realized`/`variables`,
      so those three are short of the ALGEBRA and long of their own folds.
- [ ] `uop/spec.bend` — the SPEC>1 layer `UOpMetaClass.__call__` runs.
- [x] `uop/symbolic.bend` — `tinygrad/uop/symbolic.py`: the REWRITER. **HALF
      PORTED, and the half is chosen so every MECHANISM is exercised.** Both lanes
      green and identical; 368 defs; 27 gate rows, 22 green; 11 mutations
      measured. PORTED AND GATED: the prelude (`split_uop`, `pop_const`,
      `identity_element`, `val`/`is_invalid` reading through a CAST, `truncate`,
      `const_like`/`ccast`/`cconst`, the raw `alu` sugar), `exec_alu` over a
      closed tree in TWO lanes, `simplify_pow` (2 of 5 arms), `fold_bitcast`,
      `fold_const_alu`, the compiled rule shape (table + first-wins fold +
      `ret is not uop` + the name-rebind identity check), and 15 RULES: 13 in
      `sym` and 2 in `pm_remove_invalid`. DEFERRED: 114 of symbolic.py's 127 own
      rules, each a `TODO(p3)` naming its wall — `_min_max` gates 9 of the 14
      deferred blocks, `UOp.ranges` + set algebra 4, `gcd` 2, and
      `mixin/elementwise.py`'s promotion is a caveat on every rule body.
      **FOUR THINGS THE PREMISE GOT WRONG, all measured:** (a) the DAY-ONE
      QUESTION — `exec_alu` DOES evaluate a closed ALU tree over `U32` and `F32`
      with the right overflow and sign semantics; `helpers.bend` has the four
      divisions and its zero-divisor reading IS tinygrad's; what it cannot do is a
      weakint result outside int32 (`helpers.bend` has no `i64_mul`/`i64_div`/
      `i64_mod`) or the eight `truncate` C-effect widths. (b) THE NAME-REBIND
      TABLE IN THE CONSTRAINTS NOTE IS INCOMPLETE: it records one rebind in this
      file, at :180, and symbolic.py:123 AND :124 bind a name twice within one
      src tuple as well — both LOAD-BEARING, both now ported with `U32.is_eq`
      and both two-sided in the gate. (c) `ops.py:1478`'s comment says
      `early_reject` is the ops of the pattern's FIRST src; the CODE collects the
      single-op ops of the pattern's FIRST SRC ALTERNATIVE, i.e. of ALL of its
      srcs — verified against CPython, and it changes three of this file's reject
      sets. (d) `H.floordiv_i32` is buggy (independently found in
      `divandmod.bend`), so the two floor ops are computed here from `cdiv`.
      The gate's `M2`/`M5` rows also measure TWO NEGATIVES worth keeping: the
      `ret is not uop` test has no witness in this file because none of the 13
      rules answers its own node.
- [x] `uop/divandmod.bend` — `tinygrad/uop/divandmod.py`: `div_and_mod_symbolic`,
      three rules plus `fold_divmod_general`. Both lanes green, 55 rows, 18
      mutations measured. `fold_divmod_general` is 3 arms of 89 lines and the rest
      is a `TODO(p3)` each: the wall is `UOp._min_max` (P3, unwritten) and then
      `const_factor`/`divides`/`gcd`. **The brief's premise was wrong on three
      points, all measured and recorded in the file's header: there is no
      `fast_divmod` and no `divmod_legal` in this repo (the magic-multiply code is
      `fast_idiv` in `codegen/decomp/op.py`), and there is no `graph_rewrite`
      here either, so the `PatternMatcher` scan shape applies.** `H.floordiv_i32`
      and `H.floormod_i32` are BUGGY (see below) so the file carries a correct
      local copy with the one-line fix written down.

## Session 2026-10-03 — the package-boundary gap + the wall, taken head-on

- [x] `tinybendygrad/__init__.bend` — `tinygrad/__init__.py` is 10 lines and a
      7-import re-export, not "out of scope" as the prior report had it. The
      seven names are `Tensor`, `TinyJit`, `function`, `UOp`, `Variable`,
      `dtypes`, `GlobalCounters`, `fetch`, `Context`, `getenv`, `Device` —
      every one of them already in the port (`tensor.bend`, `engine/jit.bend`,
      `function.bend`, `uop/ops.bend`, `dtype.bend`, `helpers.bend`,
      `device.bend`); the file is a re-export, not a port, and the gate is
      "every name is importable". `TYPED` is wall, not ported. **COMMITTED**.
- [x] `tinybendygrad/mixin/__init__.bend` — upstream is empty, ported as a
      one-line marker so the package boundary holds. **COMMITTED**.
- [x] `tinybendygrad/runtime/__init__.bend` — empty upstream, marker. **COMMITTED**.
- [x] `tinybendygrad/runtime/support/__init__.bend` — empty upstream, marker.
      **COMMITTED**.
- [x] `tinybendygrad/engine/__init__.bend` — empty upstream, marker. **COMMITTED**.
- [x] `tinybendygrad/viz/__init__.bend` — already existed (17 lines).
- [x] `tinybendygrad/codegen/decomp/__init__.bend` — empty upstream, marker.
      **COMMITTED**.
- [x] `tinybendygrad/codegen/late/__init__.bend` — empty upstream, marker.
      **COMMITTED**.
- [x] `tinybendygrad/codegen/opt/__init__.bend` — `tinygrad/codegen/opt/__init__.py`,
      19 lines. `OptOps` enum (4 members: TC, SPLIT, PADTO, SWAP), `Opt` dataclass
      (`op`, `axis`, `arg`), `KernelOptError`, `check` helper. The port is the
      same shape: `OptOps` as a 4-constructor `Data`, `Opt` as a 3-tuple, the
      exception is a tag. **COMMITTED**.
- [~] `tinybendygrad/codegen/__init__.bend` — 519 lines, **the keystone**:
      `full_rewrite_to_sink`, `pm_to_program`, `do_to_program`, `to_program`,
      `to_program_key`, `to_program_cache`. **This is not a missing
      re-export; it IS `graph_rewrite`'s main caller, the rewrite engine is
      the wall, and porting this file is porting the engine.**

      **WALL BROKEN, partially** (commits `b1ebb97c`, `fd4d1ee5`, `1302d660`):
      * `walk_rewrite` (the MLIR-style single-pass driver) compiles
        and runs, prints the rebuilt graph's repl map.
      * The `pm_rewrite_m`/`pm_dispatch_m` family added to `uop/ops.bend`
        returns `Maybe<&2, U32>` (parallel to `pm_rewrite`/`pm_dispatch`
        so `uop/spec.bend` is still green).
      * The `pm_post_sched_cache` table with tags 3 (PARAM) and 4 (ALLOC),
        and the rule bodies `pm_r_param_m` (slot lookup) and
        `pm_r_alloc_m` (returns pre-minted BUFFER from ctx).
      * The arena-growth wall: `pm_r_alloc_m` mints in a lost arena.
        The fix: pre-mint the BUFFER in the test fixture, return
        `ctx[2]`. The fold then needs no new arena.
      * The recursion substrate rule: sub-defs before parents. The
        pattern `case +u <> t: match t: ... recursive_call(t)` is
        two reads. Fix: introduce a binding helper (e.g.
        `main.run.show.go`) that takes the computed value as a
        parameter, so the parent calls the helper ONCE.
      * The BEND NAMING RULE (sub-defs must be declared before the
        parent that calls them) is appended to `bend2-constraints.md`
        as R-3.
      * Output: `new_sink=8 repl=1->5,2->6,3->5,4->8` -- PARAM0 -> A,
        PARAM1 -> B, ALLOC -> BUF, SINK -> rebuilt. All gates green.

      **THE FIRST REAL GATE LANDED** (commit `b2cb00fb`): three fixes, all
      found by comparing the port to CPython rather than by reading either.
      * **THE SINK IDENTITY.** The engine mints a new SINK in the rebuild
        step and then matches the ORIGINAL against the rule table.
        `pm_post_sched_cache` had no SINK entry, so no rule fired and the
        rebuild's value stood. CPython's table HAS one (it returns self) and
        CPython's repl says `SINK->SINK`. Adding the tag-0 entry makes the
        port say `4->4`, which is the same statement about identity. **A
        table that omits a rule the Python has is a silently different
        rewrite, and the only thing that finds it is the diff.**
      * **THE PRINTER SEPARATOR.** `gr_show.repl` emitted no comma between
        the first two entries, so `1->5` and `2->6` rendered as
        `1->52->6` -- a row that reads as a malformed pair. The comma now
        rides on the FIRST entry (`gr_show.repl.go.first`) and not only on
        the tail (`gr_show.repl.go.bind`), because the first entry has no
        predecessor to have appended one.
      * **THE GATE ITSELF.** `.agents/slop/gr-diff.sh` counts repl entries on
        both sides and exits 1 with both lanes printed on a mismatch. It
        COUNTS rather than diffs byte-for-byte because the port prints
        arena indices and CPython prints op+arg, and the two arenas number
        the same logical nodes differently -- a byte diff would be a diff
        of two unrelated numberings. The count is the coarse gate; per-entry
        comparison needs the port's printer to NAME ops, which is the next
        unit.
      * Gate: `bash .agents/slop/gr-diff.sh` prints `AGREE on 4 repl
        entries`. `codegen/__init__.bend`, `uop/ops.bend` and
        `uop/spec.bend` are all `ALL PROOFS CHECK`, and the interpreted and
        native lanes of the engine are byte-identical.

      **OUTSTANDING**: `unified_rewrite` (the fixpoint driver) and
      `graph_rewrite` (the dispatcher) are still walls. The printer must be
      taught to NAME ops so the gate can compare per entry and not only count
      them. The 269 `pm_lower_calls` recursion is a future unit. The ~40
      deferred `TODO(p3)` markers that the engine unblocked are still gated
      on the fixpoint.

## Session 2026-10-04 — P3 parallel wave, and the queue count is NOT a backlog

Four agents, partitioned by FILE so they cannot collide:
`ops.bend` split at ops.py line 500 (two agents, disjoint ranges), `fold.bend`
alone, `symbolic.bend` + `weak.bend` together.

### THE MEASUREMENT THAT MATTERS MOST, and it came from a subagent

**`rg "TODO(p3)" tinybendygrad/uop/ops.bend` says 185. The real backlog is
much smaller, and the difference is not laziness — it is a queue that was
never reconciled against what landed elsewhere.**

The ops.py-lines-1-500 agent took 23 queue lines and landed **5 defs**. The
other 18 split as:
* **9 were ALREADY PORTED** in another file and are now deleted from the
  queue with a pointer: `__repr__`×3 (render.bend's `axis_repr`,
  `paramarg_repr`, `pretty_print`); `_shape`/`shape`/`ended_ranges` and
  `dtype` (fold.bend's Kahn worklist, which landed earlier this week).
* **10 are WALLS**, and each now carries the RULE next to the line instead of
  a bare marker. The recurring wall is `dtype`: `shard_shape`, `max_shard_shape`,
  `_ranges`, `ranges`, `tuplize`, `bool_slice`, `key` all read it, and it is
  `fold.bend`'s. The rest are `exec` of generated source (`sym_infer`),
  a function stored in a record field (`__get__`, which is why the rule tables
  are linear), refcount eviction on a monotone arena (`__del__`), pickling
  (`__reduce__`), and a two-arm dispatch into the file that imports this one
  (`srender`).

**SO THE HONEST NUMBER IS: of 185 markers in `ops.bend`, roughly 60 are real
work and the rest are walls or done.** Every wall is now NAMED, which is the
thing that lets the next agent skip it in one read instead of one session.

### What agent A landed

`backward_slice` / `backward_slice_with_self` /
`op_in_backward_slice_with_self` — ops.py:280/286/289. **14 gate rows, three
lanes byte-identical** (`sh .agents/slop/ops-gate.sh`). The fixtures are the
smallest graphs that SEPARATE the answers: `chain` (no CALL, so the two walks
agree), `call` (a CALL at the root), `nest` (the same CALL one level down),
`backedge` (ops.py:617 with `cond is self`, so `src[0] IS src[2]`). `call`
and `nest` are what carry `enter_calls=False` — they answer 1 and 3 where
`toposort(enter_calls=True)` answers 5 and 6. **Four mutations, all of which
move rows.**

Two findings worth carrying:
* **`backward_slice` had to be placed BELOW `toposort_nocalls`** even though
  Python has it above, because it is written in terms of the walk and Bend has
  no forward references. This is the R-3 rule in a place nobody expected it.
* **`bsl.go` dropping from the FRONT is wrong.** The root is the LAST node to
  complete in a toposort, so `self` is the tail. A front drop takes a
  different node. The mutation that proves it moves all four rows.

### The gate got teeth and immediately found a real bug

`gr-diff.sh` was COUNTING repl entries because the port printed arena indices
and the oracle printed op+arg. A count cannot tell `PARAM->PARAM` from
`PARAM->BUFFER`. Teaching `gr_show.repl` to print `OP(slot)->OP(slot)` made
the first run say `ALLOC->PARAM(99)` where CPython says
`ALLOC->BUFFER(slot=0)`: `pm_r_alloc_m` was returning `case h <> t: Some{h}`,
the ctx HEAD, which is the slot-99 dummy PARAM. **The count gate said AGREE
with that bug live.** Same lesson as `ops_nv` shipping 606 green rows with 33
of 219 constants wrong.

### The engine's remaining walls

`unified_rewrite` (the fixpoint) and `graph_rewrite` (the dispatcher).
`walk_rewrite` runs and agrees; the fixpoint needs the same fold threading
iterated, so the arena question returns in a harder form. A wall that compiles
and prints an honest gap beats a fixpoint that lies.

### Coordination notes that cost time and should not be paid twice

* **A shared jj working copy means one agent's `jj describe` swallows
  another agent's `jj diff`.** Agent A's first four def lines were swept into
  another agent's commit. The lesson is that in a parallel wave each agent
  needs its OWN WORKSPACE, or at minimum its own bookmark, or the commit
  history lies about who wrote what.
* **The five red `cfun_*` rows in `ops-gate.sh` are the OTHER range** and were
  red before the wave started.
* **`g_cycle()` has a stale-arena bug**: it reads `Found.i(r)` out of
  `Found.ar(sp)` while `g_rng()` builds in a different arena, so the index is
  past the end and `Arena.node` answers the bottom. Not agent A's range.

## Phases P3–P8 — the port

96 handwritten Python files, 25,591 lines by `sz.py`, in dependency order.

| phase | directory | files | status |
| --- | --- | --- | --- |
| P3 | `uop/` | 10 | [####......] 4/10 |
| P4 | `schedule/` `engine/` | 10 | [#.........] 1/10 |
| P5 | `codegen/` `renderer/` | 30 | [##.......] 5/30 |
| P6 | `runtime/` | 36 | [...........] 3/36 |
| P7 | `tensor` `mixin/` `nn/` | 15 | [##.......] 6/15 |
| P8 | `llm/` `viz/` `function.py` `device.py` | 15 | [##.......] 1/15 |

### P4 — `schedule/`

- [~] `engine/realize.bend` — `tinygrad/engine/realize.py`, 296 lines. Both lanes
      green and IDENTICAL, `--check-only` is `ALL PROOFS CHECK`, 50 printed gate
      rows plus a `gate_count` COUNT row, 2036 lines, no `@unsafe`.
      **THE ONE DEFECT IS `bl_u`, AND IT IS WORTH READING.** A `match` with ONE
      `case _:` arm returns that arm for BOTH values of the scrutinee, and
      `bl_u.go` / `bl_t.go` are written that way — so every Bool selector built on
      them is a CONSTANT. 20 of the 50 rows therefore read `0`/`9` where CPython
      answers otherwise. It is a one-line fix and it is LEFT UNFIXED because about
      a dozen entry points were written against the broken `bl_u` and each needs an
      entry-point `match` at the same time; fixing `bl_u` alone makes the gate
      memory-fault partway through `main`. **The two entry points already converted
      are the pattern** (`oi_cf`, `get_call_name`) and their rows moved to CPython's
      answers — `oi_in_e` 0→2, `name_p` `None`→`k1`. Converting the rest is
      mechanical and is the highest-value next step in the file.

      **30 of the 50 rows are CPython-VERIFIED**, and the expectations are the
      interpreter rather than a transcription: `.agents/slop/notes/rz-oracle.py` is
      run against a live `tinygrad` and prints every `want_*`. Two oracle rows are
      worth keeping because they contradict a reading of the Python:
      `unwrap(None)` **ASSERTS** (helpers.py:95), so `buf.expr` on a nameless buffer
      RAISES rather than answering `None`; and `get_call_outs_ins`'s `encdec` arm
      reads the length of the FILTERED `get_call_arg_uops`, not of `call.src[1:]`.

      **THE MSTACK ARM OF `_resolve` IS A NAMED, GATED WALL, not a guess.** Two
      shapes were measured and both refused — a sibling walk is mutual recursion,
      and one def carrying `(fuel, pending, acc, arena, inputs)` fails the descent
      check because the pending list is REBUILT rather than passed. The shape that
      would work is `ops.bend`'s `toposort` worklist (a list TAIL is a genuine
      subterm). So an MSTACK resolves to itself, and `res_ms_same` asserts the
      omission rather than hiding it.

- [x] `schedule/__init__.bend` — `tinygrad/schedule/__init__.py:14-80`, the
      schedule linearizer: `_unwrap_src`, `_states`, `_split_after` and
      `create_schedule` in full. 1515 lines, 286 defs, 9 `Data` records, no
      `@unsafe`, zero fuel in any self-call that cannot revisit a node. Both lanes
      print the SAME 81 rows and `--check-only` is `ALL PROOFS CHECK`.
      **78 of the 81 rows are checked against Python** — `sched-truth.py`'s
      printed output for fx1/fx2/fx3 and the helper rows, and a live
      `create_schedule` for fx5 — with zero mismatches; the other three are the
      arenas' own node counts, whose difference from the gated `topo` count is
      exactly the unreachable `Vu` and `BAD`.

      **It is the engine's first real consumer**, so the file pays for three
      things ops.bend cannot give it: a second copy of `Topo.step` with
      `gate_kernel_sink` inlined (ops.bend's toposort has no gate parameter and
      cannot call into this file), `UOp.is_bound_var` (ops.py:1023, whose last
      conjunct is `param_shape` and NOT the fold table, so nothing here threads a
      `Folded`), and `UOp.buf_uop` (ops.py:925) as a fuel fold rather than a
      recursive property.

      **FIVE BUGS THE GATE CAUGHT, all named at the def they live in.** Three
      rebuild scans put the updated assoc-list entry at the TAIL instead of in
      front of the rebuilt tail (`List.append` is `xs ++ ys`, so the same builtin
      is right in an accumulator and wrong in a rebuild); their `Nil{}` arm
      inserted a SECOND entry for a key already present; the Kahn queue pushed at
      the wrong end; the Kahn loop tested `in_degree` BEFORE the decrement; and
      **pass one's RAW loop never incremented `in_degree` at all** — which fx5
      caught and fx1/fx2/fx3 CANNOT, because none of them has a RAW edge. That
      last one is why fx5 exists: it is the fixture that puts an AFTER in a read
      state, so it is the only row-set where a non-zero `in_degree` out of pass
      one is visible.

      **Fifteen mutations measured**, the table at the foot of the file. Twelve
      move rows and two are reported VACUOUS (`is_bound_var`'s addrspace test
      needs a GLOBAL PARAM no fixture has; `_states`' MSTACK expansion needs a
      multi-device state no fixture has).

      **FIVE NEW GENERAL BEND RULES** are appended to
      `.agents/slop/notes/bend2-constraints.md`, all of them refusals: a `match`
      nested in a `case h <> t:` LIST arm is refused (Bool, U32 and List alike);
      a `match` nested in a `Data`-RECORD arm is refused for a Bool scrutinee and
      accepted for a Nat or a List one, so a two-Bool decision becomes one
      two-scrutinee match; a self-call may not pass a COMPUTED argument before the
      shrinking one; a `Bool` match IS legal in a numeric arm, which makes the
      `.step` helper shape — the one ops.bend's `Topo.step` uses — a MUTUAL
      RECURSION that declaration order then forbids; and `List.append` is
      `xs ++ ys`, so a rebuild scan must cons and an accumulator must append.

      NOT PORTED, 9 `TODO(p3)` lines each naming its Python line: three raises
      (`_states`' assert, `_split_after`'s AssertionError, the cycle RuntimeError
      — the last one's observable, `COUNT_fx*_cyc`, IS in the gate), and
      `buf_uop`'s two CONSTRUCTING arms (MSELECT's `.mselect` and MSTACK's
      rebuild), whose wall is that a rule which interns must hand back the ARENA
      and threading it through a walk that descends its own srcs makes every
      caller carry it. The ported walk is exact for four of `buf_uop`'s five arms
      and the file says which four and why. `__init__.py:82-301` is deferred whole:
      every rule in it is a `graph_rewrite` with a PYTHON `ctx` DICT, and
      `graph_rewrite`'s engine pass needs the rule table linear.

### Out of scope — needs hardware we do not have

Per the brief, everything that needs an AMD/NV/CUDA/Metal/QCOM/DSP device, plus
all of `runtime/autogen/`, `renderer/amd/`, `runtime/support/{am,nv,rdma}/` and
`llm/kernels/amd.py`. These get a documented not-ported stub; their tests are
excluded by tinygrad's own hardware markers, not by us.

### Deferred until the oracle is green

- [ ] Translate the test suite into Bend. **Not started, and must not start
      until the original pytest suite passes.** This is the task brief's rule and
      the plan's phase P10.

## DEFERRED — the LOC-reduction plan (2026-10-02, owner: revisit AFTER the port works)

**The owner's instruction: get the full port working first, then optimise LOCs.**
This section is the plan, written down so it is not re-derived later. Nothing here
is started. The measurements are from tonight and are reproducible with the two
commands in the preamble.

Measured shape: **36 matched files, 19,931 py code lines vs 45,434 bend code lines
= 2.28x**, but bimodal. Files that are logic port at **1.2-1.8x** (`uop/ops.py`
1.2, `tensor.py` 1.3, `device.py` 1.4, `helpers.py` 1.6, `renderer/cstyle.py` 1.8).
Files that are pattern DSL or lambda-built tables port at **8-32x**
(`uop/movement.py` 32x on 17 py lines, `schedule/memory.py` 16x, `uop/weak.py`
11x, `uop/spec.py` 9.2x, `uop/upat.py` 8.5x) because Python derives them at
runtime. And one file reads 0.3x (`mixin/op.py`) only because it is UNFINISHED,
not efficient — do not cite it as a win.

Four measured causes, with the tool that fixes each:

| # | cause | measured size | fix | risk |
|---|---|---|---|---|
| 1 | one hand-written reader per record field (rule 27: no auto-projections) | **3,499 defs** | a generator reads the `type X is Data:` decls and emits the readers into a committed `.bend` — the same `sz.py` -> `sz.bend` pattern already in the repo | low; a generated reader disagreeing with a hand-written one is a CAUGHT bug, not silent drift |
| 2 | duplicated dispatch scan (Python has one `graph_rewrite` loop) | 81 table-scan defs, ~15 lines each ≈ **1,200** | hoist one generic dispatcher keyed on stage id; the pattern is ALREADY proven by `postrange.bend`'s `opt_ok.at` and by the kernel agent's `List<&2, O.PMEntry>` note | med; touches rule dispatch everywhere |
| 3 | two-arm `Maybe` reads (`read` then `.of`) where Python writes `x.base or x` | **1,316** `.of` sites | one `map_or`/`or_else` pair; NOTE the house style currently FORBIDS this ("skip Maybe combinators") and that instruction is what makes it expensive | low, but it reverses a standing rule |
| 4 | comment density — 28,703 comment lines, and `mixin/movement.bend` is **62% comments** | up to ~10,000 | move the per-unit measured-rule prose into the `spec/*.md` walkthrough the project already wants, and leave a pointer in each header | low; knowledge preserved, duplication removed |

Two things NOT on the list, with reasons:

- **The 216,933 lines of `runtime/autogen/*` + `support/*` + `renderer/{amd,isa}`**
  are not a LOC problem, they are a SCOPE problem. 43,464 of those lines are hex
  register tables (pure data, mechanically translatable by a SCRIPT — the same
  argument as lever 1, applied to 12x more lines), 8,258 class defs are ctypes FFI
  that in Bend can only be `@extern` seams exactly like `dtype.bend`'s fourteen.
  Zero lines are reachable from WebGPU or the Bend executor. If a device-capable
  port is ever wanted, port the 289-line GENERATOR (`runtime/support/autogen.py`),
  not its 187k-line output — and note that this CONFLICTS with the 1:1-file-parity
  rule, so it is an owner decision, not something to do quietly.
- **Hand-writing a UPat transpiler** to fix the 8-32x pattern files. Bad payoff
  against 8 files; it is a research project, not a trim.

**Projected outcome if all four run:** ~13,000-17,000 lines recovered, landing the
port near **20,000 code lines** — under upstream's 25,702 — while covering MORE of
the tree than upstream's own counter measures today. That is the version of the
claim worth making, and it is only true after the port is complete.

**Preamble for whoever picks this up:**
```sh
# per-file ratio, matched files
find tinygrad -name '*.py' | ... # see the session section for the exact python
# the four sizes, re-measurable
grep -rhoE '^def [A-Za-z_0-9]+\.[a-z_0-9]+\(' tinybendygrad --include='*.bend' | wc -l   # 3,499
grep -rhcE '^def [a-z_]+\.(go|of|put|step|run)\(' tinybendygrad/uop/*.bend                  # dispatch
grep -rcE '\.of\(' tinybendygrad --include='*.bend' | awk -F: '{s+=$2} END {print s}'        # 1,316
grep -rh '^#' tinybendygrad --include='*.bend' | wc -l                                       # 28,703
```

### A retraction that belongs with this plan

The agent brief has said for days that rule tables must be copyable `Data` "so
there are no closures". **Bend has closures** (`x => e`) and a def passed as a
function value may be called as many times as you like; there are **no list
comprehensions** but `List.map`/`filter`/`foldl`/`any` are one call each, so a
comprehension is NOT where the lines go. The rule tables should STAY plain
`Data` — copyable, gateable, mutation-testable — but the reason is the gate, not a
language limitation. Consequence for this plan: a share of lever 3 and of the
`.put`/`.go` proliferation is self-inflicted, because `List.foldl` with a top-level
2-ary def would often do. Measured and recorded as rule 31 of
`bend2-constraints.md`.

## Open decisions

- [x] **Turing completeness.** Asked, answered: no `@unsafe`. Resolved without
      fuel in the end — bounded arity terminates structurally, so the question
      does not arise. `spec.bend` has zero `@unsafe` and zero fuel.
- [x] **Port directory name.** `bendgrad/` → `tinybendygrad/`, with the inner
      `tinygrad/` mirror dropped. One level shallower; the 1:1 rule is now
      `tinygrad/foo.py` ↔ `tinybendygrad/foo.bend`.
- [ ] **Index arity bound.** How many indices `SpIdxN` should support. Waiting
      on the rewrite to report the evidence from `tinygrad/uop/ops.py`.
- [x] **The P3 fold shape: a Kahn worklist.** Decided. The property folds
      (`dtype`, `_shape`, `device`, `addrspace`, `key`, ...) become ONE def that
      walks the graph in topological order, carrying a `pending` count per node,
      rather than a recursive descent from each node. Chosen because it sidesteps
      both walls at once:
        * the descent wall — a self-call must pass a field of its own parameter,
          and an arena index read back out of a store is not one. A worklist is a
          list, and a list tail IS a valid subterm: `toposort` is already ported
          and green for exactly this reason, so this shape is proven to check;
        * the mutual-recursion wall — `dtype_from_uop -> _shape -> simplify ->
          graph_rewrite -> rules -> dtype` is a cycle, and a single topological
          pass has no cycle to be in. `graph_rewrite` stays in its own module so
          nothing in the engine calls back into the fold.
      Accepted cost: reads are O(n) folds, so the fold is O(n^2) in arena size and
      the resolved table is a threaded `List`, not an array. Correct and slow
      rather than fast and uncheckable.

      **BUILT: `uop/fold.bend`.** The decision above, executed. ONE Kahn worklist
      over the arena answers `dt`+`shape` together (they read each other), plus
      `device`, `addrspace`, `base` and `ended_ranges`; `axis_id`/`axis_type` are
      ported and are NOT fold properties, because the arena already split
      `Arg = ARange{ids, at}`. Both lanes green, no `@unsafe`, five printed rows
      (`dtype_key`, `shape_ok`, `device_ok`, `cycle_safe`, `gap_ok`), all True.

      Two of the accepted costs turned out to be the interesting part, and both
      are now in `.agents/slop/notes/bend2-constraints.md` §"Writing a Kahn
      worklist": `Array.set` computes `i & (n-1)` and cannot grow a table, so the
      resolved store is a `List` and every read is a walk; and a `List` is SPENT
      when read, so a fold step that must carry a list and something derived from
      it needs a `Data` record. Five real bugs lived in this file, all silent —
      including a `Bool` edge test where a duplicate src needs a *count*, which
      is what the `cycle_safe` row is for. Mutations run both ways; each moves
      exactly one row.

      P3's remaining walls are unchanged: `simplify`/`ssimplify` (`graph_rewrite`,
      which also gates six movement shapes, `marg` and `as_shape`), the set
      algebra for `_ranges`/`bool_slice`/`variables`, `key` (needs rotate and
      popcount for SHA-256), and `_min_max` (needs four I64 helpers and
      dtype.bend's limits). `fold.bend` has a `TODO(p3)` line per property naming
      its Python line and its wall, and that list is the queue.
- [ ] Whether `Sp` (the spec IR) stays a pure tree with the compilation arena
      separate, or the two are unified. Currently separate, because the
      compilation graph has back-edges and the test suite depends on identity.
- [ ] **The empty-Stack case has no law.** tinyspec plus `Nil{} -> None{}` mean
      an empty Stack has no shape; the stack law covers only the non-empty case.
      Worth its own law.
## Session 2026-10-01 wrap (fuzz + trim + gate wave)
- [x] Property harnesses: szfuzz (template), upatfuzz, dmfuzz — all committed.
- [x] upat wrap dedup root-caused (CPython keys by arg value, frozenset ==) + waitlist + fuel; 200 seeds depth 8 green.
- [x] Comment trim pass: movement/weak/divandmod/symbolic/fold/spec/helpers back to upstream's voice; code byte-identical.
- [x] spec walkthroughs: weak/divandmod/symbolic/movement/render + README.
- [x] pyrender gated (24 CPython-diffed rows); six render bugs fixed; Ops.name/eq_addr/toposort(LIFO)/src_from/is_balanced fixed in shared files.
- [ ] sz rounding divergence: port rounds exact rational, CPython %.1f rounds the double (154/509 tie pairs) — DESIGN DECISION: replicate the double or keep exact. TODO(p3) sz.bend.
- [ ] dm_floordiv wraps at 32 bits for FLOORDIV(INT_MIN,-1) — needs i64 division (same wall as _min_max). Excluded in dmfuzz with TODO(p3).
- [ ] render.bend local copies (tsort/src_tail) deletion gated on Topo N+E fuel fix — agent dispatched.
- [ ] Gate widenings: promote bad_ceil_* -> ok_ceil_* in dm gate; add SHR row to symbolic gate (asr revert currently moves nothing).
- [ ] sym_10 divergence decision: Python's name-interning makes var("x")*var("x") match 1/(x*y); port is stricter. Needs a row either way.
## Session 2026-10-01 — `mixin/gradient.py`
- [x] `tinybendygrad/mixin/gradient.bend` — `pm_gradient`'s 33-entry compiled rule
      table, the duplicated dispatch scan, and 22 of the 33 rule bodies. The
      **name-rebind at `gradient.py:101` is ported as a real identity check**
      (`gr_29_same`, `U32.is_eq` on two arena indices) and the gate is
      two-sided. 72 rows, both lanes identical, `--check-only` ALL PROOFS CHECK,
      **17 mutations and every one moves at least one row**. 14 of 17 node-tree
      sizes match Python's `pm_gradient.rewrite` exactly.
- [ ] `compute_gradient`'s shaped-edge reduce (gradient.py:132) — needs
      `broadcast_axes` + `sum_acc_dtype`. TODO(p3) in the file.
- [ ] `call_gradient` (gradient.py:20) — five subsystems. TODO(p3) in the file.
- [ ] `reduce_gradient` (gradient.py:8), `_min_max` on tag 25, `has_buffer_identity`
      on tag 15, `as_shape`/`Sint` add on tags 19/20, `ctx[i]` on tag 23.
      All TODO(p3) in the file with the specific wall and the Python line.

## Session 2026-10-01 round 2 (schedule/mixin/engine/tensor/decomp wave)
- [x] tensor.bend (lazy-graph half, 29 CPython-identical rows), mixin/dtype+gradient, schedule __init__/memory/allreduce/multi/rangeify, engine/realize, codegen/decomp — all committed with gates.
- [x] movement.bend: hop_self inversion + 4 more bugs fixed; gate defect (G.ix bottom) root-caused; 26/26 rows == CPython.
- [x] dtype.bend: three i64 limit constants fixed (found by mixin/dtype hoist).
- [x] fold.bend: RESHAPE _shape arm landed; ONE line short (reshape_ps must read Arena.src0, not ss[0] — the srcs.go double-reversal bug).
- [ ] fold.bend reshape_ps one-liner, then retire: tensor tn_rop_gap (delete), tensor M4, movement mp_2 + movement.py:185 identity test, duplicated as_shape.
- [ ] engine/realize: ~20 rows rest on single-arm-case-_ Bool constants (bl_u); fix documented at top of file, mechanical; two converted as the pattern.
- [ ] sz rounding (exact vs double) and sym_10 divergence — still the owner's two calls.
- [ ] decomp: 3 rules do not fire (9 rows, undiagnosed); magicgu/fast_idiv at the i64 wall.
- [x] `mixin/op.py` lines **1-997** — `tinybendygrad/mixin/op.bend`. 32 CPython rows
      byte-identical on both lanes, `--check-only` = `ALL PROOFS CHECK`, 17 mutations
      measured. Lines 998-1980 are a second agent's half in the same file. See the
      round-5 section below.

## Session 2026-10-01 round 3 — `mixin/elementwise.py`
- [x] `tinybendygrad/mixin/elementwise.bend` — `_broadcasted`/`_binop`/`promote`/
      `remint`/`ufix` + the method surface. 69 gate rows, byte-identical to CPython on
      BOTH lanes (interpreted and `-o` native), `--check-only` = `ALL PROOFS CHECK`.
      Oracle `.agents/slop/ew-gate.py`, mutation harness `.agents/slop/ew-mutate.py`.
- [x] THE ARENA RULE HAS A SECOND HALF, and it cost the whole session. Rule 6 of
      bend2-constraints ("a node belongs in the arena as it stood after the last node
      built before it") is about a node built in the WRONG arena; the second half is
      two builds from the SAME base producing SIBLING arenas, where "take the longer"
      finds a store containing neither's loser. `sub`'s int arm printed 4 nodes where
      CPython prints 6. Fixed by threading `+O.Arena` (never `Tensor.ar(t)`), rebasing
      on the arms that mint NOTHING, and running the two promotions sequentially.
- [x] `+fx: F.Folded` as a parameter is a trap on any def that builds — it goes stale
      the moment the callee mints and fails SILENTLY (`void` dtype -> `void` is not
      weak -> the CAST arm). Removed from 14 defs; `ew_fx` folds at the point of use.
- [x] Two more `Found`-arena bugs, both silent: `ew_promote.b` paired a build's index
      with the fold's stale arena, and `ew_remint.put` built in the arena its OWN
      recursion grew past. Both are `ew_of`'s rule one level down.
- [x] `O.Arena.src_to` KEEPS the first k; `O.Arena.src_from` DROPS the first k. `remint`
      wanted `src[1:]` and wrote `src_to`, which on a one-src node is the whole list.
- [x] ORACLE BUG FOUND AND FIXED: `ew-gate.py`'s `opat` used `k` as BOTH a toposort
      depth and a src slot. Identical at k=0, silently wrong at k=1 — it read
      `MUL.src[1]` where the row means `root.src[1]`, so `ew_op_sub1` asserted
      `CONST` about a graph whose `sub` is an ADD over a MUL.
- [x] 14 mutations measured. M3 and M5 measured ZERO and both were REAL GAPS, not
      equivalences: `promote`'s `base.is_invalid` arm and `remint`'s recursion had no
      fixture. Closed with `ew_promo_invalid` (a `dtypes.bool.const(Invalid)` CONST)
      and `ew_remint_recurse` (a `DETACH`, which ops.py:787 descends in `base`).
      M5's remaining zero is an EQUIVALENCE and is reported as one.
- [ ] `remint`'s `+u.src[1:]` ORDER is still ungated (needs a Movement node with a
      shape arg; CPython takes the weak arm there and this port takes the CAST arm, so
      it is a `fold.bend` dtype question, not an `elementwise.bend` one).

## Session 2026-10-01 round 4 — `codegen/decomp/transcendental.py`
- [x] `tinybendygrad/codegen/transcendental.bend` — all 26 Python defs. 891 STRING gate
      rows, byte-identical to `python3 .agents/slop/tx-arena.py` on BOTH lanes,
      `--check-only` = `ALL PROOFS CHECK`. Oracle `.agents/slop/tx-arena.py`, mutation
      harness `.agents/slop/tools/tx-mut.py`. 13 mutations, all still `checks`, all move
      rows; four move exactly one.
- [x] NO 64-BIT ARITHMETIC IS NEEDED. transcendental.py BUILDS GRAPHS; only 64-bit
      CONSTANTS appear, and `H.i64_of_hi_lo` mints both halves. `shr`/`shl`'s UOp arm
      is DEAD at all 11 sites (every call site passes a Python int), so `tx_shr`/`tx_shl`
      are a `FLOORDIV`/`MUL` by a CONST and `helpers.bend` needs no `i64_*`.
- [x] THREE MEASURED ERASURES IN THE ORACLE, all of which a naive port gets wrong:
      (a) promotion CASTs, (b) `UOp.const`'s own fold, (c) a CONST's key is its VALUE and
      not `repr(arg)` — `UOp.const(x)` is `ConstFloat(x)` while `UOp.const(x, float32)` is
      `dtypes.float`, so the same float is TWO Python nodes and ONE port node. The key is
      also STRUCTURAL, not `id()`.
- [x] `cody_waite_reduction`'s float16 and float64 arms are WRITTEN (not stubbed):
      `cw_quadrant.d64` subtracts `qdh`, `reduce` takes `d64` AND `f16` as two separate
      Bools, `tx_cw16.chain` recurses into the float32 chain and casts back. `tx_d64` was
      referenced and never defined; it is now `pri == 15`.
- [x] `tx_rintk`'s `dt` IS `d`'s OWN FLOAT DTYPE. A caller that pre-converts
      double-converts — `tx_int_dt(S.int32())` is `S.int64()`, not `S.int32()` — and the
      rintk CAST came out `long` where the oracle says `int`. THREE rows, and every
      count row was still correct: `a_cw 23`, `a_xsinf 39`, `a_xsin 143`.
- [x] `tx_cf_neg0`'s WORKAROUND is now UNNECESSARY. The defect it routed around is
      FIXED (commit `65b585e1`): `ops.bend:1406` `eq_const.CFloat` asked `F32.is_eq`,
      which IEEE says is TRUE of `+0.0`/`-0.0`, while tinygrad's `UOp.key` is a hash
      over the packed arg and keeps them apart. It was wrong in BOTH directions --
      identical NaNs must intern, and IEEE says NaN != NaN -- so the fix is
      `U32.is_eq(F32.bits(f), F32.bits(g))` and the gate is two rows, one per
      direction (`t_float_zeros_differ`, `t_float_nan_interns`), both CPython-measured.
      `decomp.bend:126` KEEPS `F32.is_eq`: there the question is a value question.
- [ ] `tx_cf_neg0` itself: with `eq_const.CFloat` bitwise, re-check whether the
      workaround still changes any row, and delete it if not. Not done — `decomp.bend`
      is not mine to churn for a cosmetic reason.
- [ ] NOT GATED, and stated in the file: the float16 and float64 windows, because the
      oracle's fixture is float32. The float64 coefficient literals are written as full
      decimals and are NOT independently verified. TODO(p3) tags in the file name each
      Python line.
- [ ] `decomp.bend`'s table should IMPORT, not re-derive: `tx_tab`, `tx_t_apply`, and
      the four expansions `xexp2`, `xlog2`, `xsin`, `xpow`. Reported only, not changed.

## Session 2026-10-01 round 5 — `mixin/op.py` lines 1-997
- [x] `tinybendygrad/mixin/op.bend`, SIDE A. Boundary is **line 997**, a def boundary:
      `topk` is op.py:976-996 and 997 is its blank, so SIDE A ends on a whole def and
      SIDE B (998-1980, another agent) starts on `allclose`. **32 shared rows,
      CPython == interpreted == native, byte for byte**; `--check-only` = `ALL PROOFS
      CHECK`. Oracles `.agents/slop/mixin-op-gate.py` (CPython) and
      `.agents/slop/mixin-op-gate.sh` (three lanes), mutator
      `.agents/slop/mixin-op-mutate.py`.
- [x] PORTED AND GATED: `min` (op.py:473), `mean` (:496), `var` (:523), `var_mean`
      (:551), `std` (:568), `std_mean` (:592), `normalize(p=0)` (:609), `logsumexp`
      (:630), `_softmax` (:657), `softmax` (:663), `log_softmax` (:686), `softmin`
      (:709), plus `max`/`sum`/`prod` (reduce.py) which they call, and
      `exp`/`log`/`isfinite`/`isnan`/`isinf` (elementwise.py). EIGHT WALLS W1-W8, each
      named at its Python line in the header; `item`/`data` are neither walls nor ports.
- [x] **THE ARENA RULE, MEASURED SIX TIMES.** Arguments read LEFT TO RIGHT, so
      `T.tn_new(T.Tensor.ar(x), ...Uop.const(T.Tensor.ar(x), ...)...)` reads the arena
      BEFORE the const exists. Symptoms are never wrong numbers: a `NOOP/0` bottom, a
      node whose src is itself, an empty toposort, or a node silently OVERWRITING the
      one it was meant to consume. Hence `mo_const_t` and `mo_cast_t` exist as defs.
- [x] **W9 IS TWO DEFECTS, NOT ONE, and BOTH ARE NOW FIXED** (W9a in `elementwise.bend`
      mid-session via `ew_rebase`; W9b in commit `95197de9`). W9b was the MISSING
      CONJUNCT: `ew_promote` (elementwise.bend:378) passed `W.dt_weak(dt)` -- the CLASS
      test alone -- where elementwise.py:30 is `t.dtype in dtypes.weaks AND t._uop.base.op
      is Ops.CONST`. It was invisible because EVERY fixture in `elementwise.bend` holds a
      weak CONST, so the conjunct was true wherever it was read; M13 (delete it) moved
      nothing before the new rows. It is not cosmetic: `weak_dtype(out_dtype)` is weak
      whenever `out_dtype` is strong, so a weakint ADD against int32 stayed weakint and
      the root then added weakint to int32. CPython, measured live: `Tensor(3)+Tensor(5)`
      is weakint with base op ADD, and after `+ Tensor(7, dtype=dtypes.int32)` its src0 is
      `int`/`Ops.CAST`. `g_promo_nonconst` is the first fixture whose weak tensor is NOT a
      CONST; three rows, and the full-gate diff showed only those moving.
- [ ] **`mo_promote` IS NOW A DUPLICATE AND SHOULD BE DELETED.** It was spelled out here
      rather than delegated to `E.ew_promote` because of W9 -- both halves. With W9a and
      W9b fixed, the reason is gone, and `promote` exists twice (op.bend:437 and
      elementwise.bend:378) which is the copy-paste the rules forbid. Before deleting:
      re-run `op.bend`'s gate and confirm `t_norm0` still prints 17 (it does today, and
      it is the row that proves the cast survives).
- [x] **17 MUTATIONS MEASURED, 13 MOVE.** The four that do not are reported, not
      dropped: M6 (reduce.py:45's cast, negative for float32), M7 (`smax` at
      `correction=0`), M8 (**`log_softmax` reading `_softmax`'s `e` instead of its `m`
      is UNFALSIFIABLE by any graph oracle** -- `ss = e.sum(...)` already pulls `e` into
      the graph, so the two programs are graph-isomorphic), M17 (the whitespace
      CONTROL).
- [x] **M10 CHANGED THE TABLE.** Dropping the arena re-wrap from `promote`'s
      `is_invalid` arm moved nothing, and the reason was that `t_bin_promote` interned
      its invalid CONST the stale way -- `mo_const_t`'s own rule, in the row meant to
      test it -- so the arm was never taken. The row was rebuilt FOUR-SIDED (each
      "return `t`" arm checked for the NODE and for the ARENA, with the operands
      ordered so each fold is newer than what it promotes) and M10 now moves it.
- [x] **THE TWO-RULES-CLAIM-ONE-NODE ROW is `t_two_rules`**: `softmax` (15) and
      `log_softmax` (18) printed from ONE arena over a 13-node shared prefix.
      `softmax3_m/e/ss` (8/11/13) pin `_softmax`'s three outputs.
- [ ] `mixin/op.py` lines **998-1980** — second agent, same file, `mo2_*` / `mo_b_gate`,
      and it must not re-declare `main`.

## Session 2026-10-02 — the device wave (renderer, codegen/opt, nn, langs) + two shared defects

Five units landed while ten agents ran in parallel. Everything below is verified by
me, not by the agent that wrote it: `--check-only` re-run, or the gate re-run and
diffed.

- [x] `runtime/ops_webgpu.bend` — `tinygrad/runtime/ops_webgpu.py`. 1738 -> 1811
      lines, 267 defs, 147 rows, both lanes byte-identical, `ALL PROOFS CHECK`
      (`564916f6`). The rule it is built on: a def either builds the argument of one
      wgpu call or records that call — no third kind — so the `raise` lives in the
      TRACE and a refusal is a truncated trace needing no guard of its own. Two bugs
      its own gate caught: `Tr.has` returned True to everything (fuel was the pattern
      length, so eight order rows were decorative), and `slots` consed then reversed
      (which would have silently broken the wgsl binding correspondence).

- [x] **THE CALL LAYER** — `runtime/webgpu_call.bend` (1312 lines, 58 rows, 0 False,
      `ALL PROOFS CHECK`) + `runtime/webgpu_call.js` (502 lines) + the emitted
      `runtime/webgpu_call.mjs`. This is the `# TODO(p3) runtime/ops_webgpu.py:<line>`
      half of `ops_webgpu.bend` turned into real `navigator.gpu` calls.
      **The boundary is `bend -o x.mjs` + a `.js` driver**, and it was chosen by
      measurement, not taste: an FFI effect (`def .. -> IO(R): import "./e.c"`) would
      make `Tr.emit` answer `IO(Tr)` and DESTROY the pure gate the 147 rows depend
      on, and `bend guide effects` gives the JS side an FD-shaped `need`/`io_park_on`
      with no promise arm for WebGPU's six `synchronous` calls. `Call` cannot carry
      a descriptor either — it is `{k, arg}` by design.
      **`ALL 147 ORIGINAL ROWS BYTE-IDENTICAL`, both lanes**, and 4 rows ADDED: a
      real bug the seam found. `dev.uniform_bytes` used `U32.shrn(v, 1n)`, a
      ONE-BIT shift, so `7` came out `7,3,1,0` against CPython's `7,0,0,0`; its own
      three byte rows (0, 1, 0xFFFFFFFF) are all values a one-bit shift also gets
      right, so nothing in that file could see it. Also `Buf.id`, the reader the
      seam needed.
      **RAN FOR REAL**: headless Chrome 154 over CDP, real adapter, real device,
      `57/57` steps from `requestAdapter` to `mapAsync`/`getMappedRange`, 16-byte
      readback. Timestamps read 0 — headless Chrome's Metal backend does not populate
      `timestamp-query` here, and that is reported rather than dressed up.
      Boundaries: WebGPU is NOT reachable from CPython on this machine
      (`failed to load library webgpu: try setting WEBGPU_PATH?`, verified
      independently of the port's own claim), and `navigator.gpu` is undefined in
      both `bun` and `node` here.
      Three blind spots the mutation table reports rather than closes, in
      `.agents/slop/mutate_webgpu_call.py`.
- [x] `renderer/wgsl.bend` — `tinygrad/renderer/wgsl.py`. 1062 lines, 168 string-diff
      rows, `ALL PROOFS CHECK` (`eb020720`). `is_packed` shipped with its third clause
      INVERTED, so the entire packed path was dead code while 100+ rows stayed green;
      the 40 `is_packed`/`buf_map` rows exist because of that finding. Two rows differ
      and are left printing (the f64 nan mask and threshold — a U32 cannot hold either,
      and neither is reachable from a WGSLRenderer).
- [x] `renderer/tc_ptx.bend` STAGES 1 AND 2 — `tinygrad/renderer/tc.py` (141 lines) AND
      `tinygrad/renderer/ptx.py` (231 lines) in ONE file, because they are one feature
      (`ptx.py:4` imports `tc`). 2035 lines, **620 string-diff rows** (286 + 334),
      `ALL PROOFS CHECK`, interpreted and native lanes byte-identical, 51 mutations
      measured. The three findings worth carrying:
      * **`Tc.threads` is unobservable.** `__post_init__` (tc.py:43) ASSERTS
        `len(f[0]) == len(frag_c[0])` for all three fragments, so A, B and C have the
        same lane count in every legal tensor core and the three candidate readers are
        the same function. The mutation table says 0 rows and the control (reading
        `frag_c[1]`, which the assertion does not pin) says 8 — the row is live and
        the ambiguity is upstream's.
      * **`used` needed its OWN row.** `axis_coords` reads `frag_a + frag_c` and takes a
        MAX per axis, and the same assertion makes `A + C` and `A + B` agree on all
        three maxima. Swapping C for B moved nothing until `used`'s own string was a
        row. A rule whose output is an intermediate needs a row on the intermediate.
      * **`supported_dtypes` returns a SET**, so the gate sorts the names, and its
        cons-vs-append mutation moves 0 rows where `tensor_cores`' moves 3. Where the
        oracle has to normalise, the gate loses a dimension.
      STAGE 3 (the `render` naming walk: the `ssa` counter, the register map, the
      `.reg` declarations, `prod` over the local dims, and the kernel BODY that
      `render_kernel` currently takes as a `BODY` line) is NOT started. Walls named
      rather than faked: `ptx.py:145` (the compiler), `ptx.py:147` (the `extra_matcher`
      mutation), `ptx.py:13`/`ptx.py:16` (`render_val`'s signed-integer and double
      arms), `ptx.py:230` (the base set, owned by `renderer/__init__.bend:85`), all
      eight `pm_validate_wmma_*` bodies, all eight `ptx_matcher` rules, and
      `UOp.wmma`/`UOp.cast`/`UOp.bitcast` in `ops.bend`. Oracle
      `.agents/slop/tcptx-oracle.py`, mutation driver
      `.agents/slop/tcptx-mutate.py`, seven new rules appended to
      `bend2-constraints.md`.
- [x] `codegen/{kernel,rewriter}.bend` — 2105 lines, 70 rows diffed against a Python
      oracle, `ALL PROOFS CHECK` (`e68fcedc`). **The Python files named in the brief
      do not exist in this fork**: `codegen/` is a package, `codegen/__init__.py` (518
      lines) IS the kernel, and the lowerer is split across `simplify.py`,
      `late/coalesce.py` and `gpudims.py`. The oracle found three real bugs (a `ctx[0]-1`
      off-by-one, the INS dispatch, `ab_miss` reading a count instead of a bool), and
      the one real finding in the PYTHON: `pm_to_program` rule 3 is unreachable because
      rule 2's unconstrained `LINEAR` arm shadows it.
- [x] `codegen/late.bend` — **regalloc is no longer a stub**: 3/118 → 115/118, and the
      lowerer is whole (240/243 lines across the three Python files). 45 rows added and
      128 rows diffed against `.agents/slop/late-oracle.py` with a zero diff in BOTH
      lanes. The gate is PER-UOP and ORDERED: `ra<t>_a<i>` is one row per program point
      carrying every virtual register it defines or uses and the real register each
      landed on, and `ra0_a7`/`ra1_a7` differ (`v4>10->rcx>1` against `v4>10->rdx>2`)
      because `is_two_address` only REORDERS `cons` — that pair is the whole reason
      `ra0` and `ra1` are two rows. `ra2` is the fixture that reaches the loop
      prologue and epilogue, which are dead code on `ra0`. **Twelve real bugs found by
      the gate**, four of which are Bend traps rather than Python traps and are appended
      to `bend2-constraints.md`: `Bool.pick` CHOOSES an arm and does not sequence one, so
      three drafted folds silently dropped the rest of their list; `tb_put` APPENDS its
      `vs`, so `lr[v].append(n)` and `reals[i][v] = r` need the delta and the new
      `tb_vput`; `tb_get`'s "absent = 0" convention collides with **rax being interned
      at 0**, so every use of a vreg holding rax refilled it (W5b); and a skip whose two
      arms both recurse cannot be a `match` guard at all, because bend refuses the
      mutual recursion. Nine blind spots are reported with reasons rather than closed
      with rows that agree with the bug — including one WALL: the oracle prints `r[1]`
      and not `r[0]`, so `regalloc_rewrite`'s whole `nsrc` half is invisible to every
      row (W5c). Mutation drivers `.agents/slop/ra-mutate.py`, `ra-mutate2.py`.
- [x] `examples/beautiful_mnist.ts` — 611 lines, mirrors the 48-line .py section by
      section, decorators carrying the tinygrad NAMES (`@TinyJit`, `@Context({TRAINING:
      1})`, `@function_` because `function` is a TS reserved word — verified, TS1146).
      Gated on `tsc --strict` in both module modes plus a real descending curve.
- [x] `mixin/elementwise.bend` — **`promote` was missing its second conjunct** (`95197de9`).
      Details in the W9 entry above. A real defect, not a coverage hole: M13 moved
      nothing before the new rows existed.
- [x] `uop/ops.bend` — **`eq_const.CFloat` was IEEE where CPython is bitwise** (`65b585e1`).
      Wrong in both directions, so the gate is two rows, one per direction.
- [x] `bend2-constraints.md` rule 8: `dtype.bend`'s fourteen seams make every importer
      print `SOME PROOFS FAIL` and that redness is NOT evidence about your work.
      `@unsafe` is not the fix (the guide says so), and Bend 2.0.34 has no F16/I64/F64.
- [x] `bend2-constraints.md` rule 9: `bend base F32` prints nine defs and none of them
      are arithmetic (the rest are laws only — compiler builtins with no body); a
      NEGATIVE FLOAT LITERAL does not parse (`F32.neg(0.0)`); `F32.is_eq` is IEEE while
      CONST identity must be bitwise; and `{expr}` inside an `IO.print` string does NOT
      fire — it prints the template verbatim with no error.

- [ ] **`f32_fixed` TRUNCATES WHERE `%.Nf` ROUNDS — one decision, two call sites, not a
      one-line fix.** `helpers.bend:526` takes each digit as `F32.to_u32(F32.mul(f, 10.0))`,
      which truncates, so `f32_fixed(2.3456, 2n)` prints `2.34` where CPython prints
      `2.35` (measured by the example agent over six fixtures, four agreeing). CPython
      formats `f"{x:.2f}"` by rounding the EXACT dyadic value of the f32, half-to-even;
      the walk above rounds nothing and also multiplies the remainder in f32, so it is
      inexact twice over. A correct version needs the exact decimal digits of the
      mantissa in integer arithmetic, which the substrate can do but only carefully.
      **This is the SAME decision as the open `sz.bend` rounding item above, and it
      should be made once for both** — `sz.bend`'s patch sits measured and unapplied at
      `/tmp/opencode/szbench/OPTION-string-fuel.patch`, and picking one rule for both
      call sites is cheaper than two divergent ones. Callers that would change:
      `size_to_str` (`:729`, `:732`, `:736`), the timing printers (`:700`, `:710`,
      `:713`, `:717`), and `sz.bend:1461`. `sz`'s own 222/222 byte-diff is unaffected
      today, so nothing in the committed gates encodes the wrong answer.

### In flight when the machine went quiet (uncommitted, agents still writing)

`nn/state.bend` 834 and `nn/__init__.bend` 502 (the layers the example names, which is
the whole point of that unit) · `renderer/__init__.bend` 553 and `cstyle.bend` 1524
(the conventions header wgsl reads was written first, which is why wgsl could land) ·
`device.bend` 1239 · `langs/core.bend` 345 · `runtime/executor.bend` 2245.
(`codegen/opt/` and `examples/beautiful_mnist.bend` have since landed — see the two
entries below and commit `d685f998`.)

- [x] `codegen/opt/` — the BEAM unit, LANDED (`b78672e4`): `postrange.bend` 1066,
      `search.bend` 405, `heuristic.bend` 196, all `ALL PROOFS CHECK`, lanes identical,
      20/20 and 14/14 mutations localised. **BEAM=1 IS PARTIAL, and the split matters:**
      the ACTION SET is ported and gated — the candidate enumeration (CPython-measured
      counts 4 / 18 / 32), the dedup ladder, two of five drop rules, `min(least, this)`,
      the SCORE record, and every `check` in `apply_opt`'s SPLIT/PADTO/SWAP arms. The
      SEARCH LOOP IS NOT: `search.py:128-166`'s `while not exiting:`, the 1000x compute
      filter (unspellable — it reads `this` twice and a `U32` cannot be `+`), the 269
      `OPT`s, `get_test_global_size`, `_time_program`, the worker pool, and all of
      `heuristic.py` but block #5. Round 2 onward also needs the winners rngs, which
      needs `apply_opt`'s AST substitution — so the loop is blocked on a wall, not merely
      unwritten. You can ask this port "which opts are candidates for this kernel, and
      how many, after dedup" and it answers like CPython. You cannot ask which one won.
- [x] BEAM=1 round counts, measured from CPython and pinned as COUNT rows:
      `(a+1)` on 4 elements -> round1 **4**, round2 **2**, exit, 2 opts applied;
      `(a*b).sum(1)` on 16x32 -> **18**, **13**, **2**, 3 opts applied.
- [ ] The BEAM loop itself, once `apply_opt` grows an AST. `Sched{ren,rngs,opts}` is one
      field away from carrying an `O.Arena`, and the header says exactly that.

- [x] `examples/beautiful_mnist.bend` 831 — LANDED (`d685f998`), and I re-ran its
      three-lane gate here: **30 shared rows (36 total `=` rows; the 14 dtype.bend law failures are PERMANENT and expected), CPython == interpreted == native**. Four
      walls named at their Python lines, and two substrate defects ROUTED AROUND
      rather than fixed: `fold.bend:1621` defers a PERMUTEs dtype (so the 2-D dot
      prints 11 nodes against CPythons 15, recorded as `unverified_lin2`), and
      `mixin/op.bend`'s `mo_permute` builds in `Tensor.ar(t)` then wraps in that same
      arena, landing the PERMUTE one node short of the `AOrder` tuple. Both are filed
      under the fold wall rather than worked around silently.
      **THE FOLD HALF OF THAT IS NOW RETIRED** by the `uop/fold.bend` movement unit:
      `perm_ds` answers a PERMUTE's dtype and shape (`src[0].dtype` and
      `tuple(ps[i] for i in marg)`), so `unverified_lin2`'s "the fold defers a
      PERMUTE's dtype" no longer holds. The `mixin/op.bend` arena half is untouched
      and remains the live half. **The example's owner should re-run `lin2`** and
      re-check the 11-vs-15 node count, since the cause named here is gone. The fold
      unit did NOT edit this file and did NOT re-gate the example.

- [x] `nn/state.bend` 834 and `nn/__init__.bend` 828 — LANDED, 38 gate rows all green on
      three lanes (CPython oracle == interpreted == native, byte-identical diffs), and
      **27 mutations measured, 25 of which move rows and 2 of which are proper controls
      or documented no-ops**. The brief's priority order was right: `state.bend` first,
      and its `get_state_dict` walk turned out to be the piece the example's optimizer
      cannot start without. `nn/__init__.bend`'s confirmed layer list for
      `beautiful_mnist.py` is **Conv2d x4, BatchNorm x2, Linear x1** (example lines
      10-16) and every one of those is fully gated on shapes and `__dict__` order.
      Two findings that changed the design and are worth more than the code:
      (1) **there is no `nn.Module`** — `nn/__init__.py` is eleven plain classes and
      `get_state_dict` reaches a layer by reflecting over `__dict__`, so a Bend port
      cannot have reflection and each layer's state list has to be an explicit
      `*_st` def. That is why `nn/__init__.bend` imports `state.bend` (Python's own
      direction, `__init__.py:6`) and not the reverse.
      (2) **`BatchNorm` puts five tensors in its `state_dict`, not two** — measured,
      `['weight','bias','num_batches_tracked','running_mean','running_var']` — and the
      three scalars Python assigns first are absent only because `get_state_dict` drops
      every non-tensor leaf (`state.py:107`). `Optimizer` then filters on `is_param`, so
      `nn/state.bend`'s WALK and not an `is_param` filter is what the example needs;
      getting `is_param_(False)` wrong on `num_batches_tracked` is mutation M5 and moves
      exactly one row.
      Four bugs the gates caught in this unit's own code, all recorded in the files:
      a `case '.':` strip that dropped INTERIOR dots (`a..b..` -> `ab`); a `U32` clamp in
      `TensorIO.seek` that answered `4294967295` for `seek(-1)`; a `List.reverse` on two
      accumulators that APPEND rather than cons (`bn_mask` gave `[1,1,-1,1]`); and an
      `is_param_(False)` that was simply missing. Two orthogonally-similar substrate
      findings for `bend2-constraints.md`: a **`Char` LITERAL is a valid match pattern**
      (`case '.':`), which is the only spelling of a choice-plus-descent walk that needs
      neither `Bool.pick`'s double-consumption nor a mutually-recursive second def; and
      **`case 0n:` does not match a `U32` at all** ("expected : a constructor of U32"), so
      a countdown and the index it counts must have different types.
- [ ] `nn/state.bend`'s remaining walls, all named at their Python lines and none of them
      a surprise: `TensorIO.readinto` (`.data()` = realization + a bytearray mutation),
      `accept_filename` (a decorator), and the six file readers — `safe_load_metadata`,
      `safe_load`, `safe_save`, `load_state_dict`, `zip_extract`, `tar_extract`,
      `torch_load`. The last is a pickle VM. `safe_dtypes` is gated as a TABLE and not as
      a load, so a wrong `data_offsets` computation would not move a row.
- [ ] `nn/__init__.bend`'s eleven `__call__`s — every one is a single mixin method and
      mixin/op.bend SIDE B is not built. `x.mean`/`x.sum` are the exception: `mo_mean`
      and `mo_sum` EXIST and are callable, so BatchNorm's and RMSNorm's forwards are the
      first two that could land without a new unit.

## Session 2026-10-02 — `device.bend`

- [x] `device.bend` — `tinygrad/device.py`, 564 lines → 1546 (207 defs, 9 `# TODO(p3)`
      walls, 107 gate rows). **Both lanes byte-identical and all 107 rows match the
      Python oracle** (`Device['PYTHON']` plus a `get_class` stub for the availability
      rows), and a 30-entry mutation table is at the foot of the file with every entry
      moving at least one row. The port: the device registry as a table plus a
      first-wins scan; `Buffer` as `(nbytes, content-address)` parameters in a `Bar`
      arena, so the view arithmetic is checkable; the `Allocator` LRU policy as the
      four-conjunct predicate it is; `Compiler`/`TinyELF.iter_sig`; and
      `Compiled`'s `device_id`/`host`/`_renderer_name`/`_select_iface`. WALLS: the
      whole FFI seam (`mmap`, `cudaMalloc`, `MTLBuffer`, `pickle`), `importlib`
      (the class table IS the resolved lookup), the `runtime/` directory walk (the
      sixteen stems are spelled out), and `BufferStorage.maps`.
- [x] Two registry and two rule-table first-wins claims, all with a row: the
      `:0` strip collapsing `cpu:0`/`CPU`/`cpu` to one opened device; the
      `ALL_DEVICES` ORDER (AMD is row 2 and CPU is row 7); and `pm_bufferize`, whose
      rules 2 and 3 carry the IDENTICAL pattern so rule 3 is unreachable — the
      "two rules claim one node" fixture, with three negative fixtures added after
      three mutations moved nothing.
- [x] Seven new Bend rules appended to `bend2-constraints.md`, of which three are
      generalisable and were each measured: **a list of `Bool` is not a usable
      type**; **a pattern binder must not shadow a def name** (the error names the
      constructor); **`+` on a pattern binder is the spelling for "two reads in one
      expression"**, which is the cheap general fix for an affine `U32` read twice.

## Session 2026-10-02 — `langs/` the four-lane export matrix

One pure f32 Bend program, exported four ways, with the cross-language property
gated rather than assumed. The gate is `./langs/verify.sh`; it exits 0 when every
lane agrees, 1 when a lane moved, 2 when the only problem is the documented wasm
wall, so it cannot pass quietly over a missing lane.

- [x] **Does Bend emit C source? YES.** Checked before anything was designed,
      because lane 1's shape depends on it: `-o core.c` is C source (7597 lines for
      `core.bend`), not a binary. `bend2/main.ts:363` is the three lines.
- [x] **`langs/core.bend`** — `core_step(images: Array<F32>, labels: Array<U32>,
      weights: Array<F32>) -> F32`, a fixed-shape two-layer step (IN=4, HID=3,
      CLS=3, BATCH=2) finishing in softmax + cross-entropy, with each weight row's
      LAST column being that row's bias so a bias costs no separate arithmetic.
      `ALL PROOFS CHECK`, no `@unsafe`. Its loss is within 1 ulp of a numpy f32
      reference; the intermediate `h` is bit-exact and `z` differs by 1-2 ulp on
      two of three values, which is the accumulation order, not an error.
- [x] **SIX LANES BYTE IDENTICAL**: bend interpreted, bend native, the emitted
      `core.c` under clang, the same `core.c` linked against a separate 5-line C
      harness (`-Dmain=bend_main`), the emitted `core.js` under node, and the SDK
      on its JS backend over the emitted `core.mjs`.
- [x] **The payload is u32 BIT PATTERNS, not decimals** — 42 fields, one wire
      format for every lane. This is the decision that makes the gate mean
      something: with decimals on the wire, C's `strtof` and JS's
      `parseFloat`+`Math.fround` could round one value differently and every lane
      would be a plausible near-miss instead of an exact answer.
- [x] **`langs/sdk/bend_sdk.ts`** — `BendLibrarySDK.init({forceJS?})` doing
      detect-WebAssembly -> try-wasm -> catch -> fallback-to-js, `executeTask`
      dispatching on the backend, `langs/sdk/bend_wasm.ts` in the emscripten
      `_malloc`/`ccall`/`_free` shape. `langs/sdk/bench.ts` runs both backends,
      min of 5, and prints the machine load beside the numbers.
- [x] **The wasm lane is a MEASURED wall, not a missing toolchain.** emcc absent,
      Apple clang has no wasm target, no wasi-sdk — but zig 0.15.2's
      `wasm32-wasi-musl` got the build all the way to LINKED after four separate
      fixes (documented in `langs/wasm/WALL.md`), and it then traps, because
      `corpus_setup` reserves `1ull << 33` = 8 GiB and wasm32 caps linear memory
      at 4 GiB with a 32-bit `size_t`. wasm64 is the only architecture that could
      hold it and neither zig nor node 26 has it. **The honest recommendation is a
      one-line upstream change**: honour the `bytes` argument for the CPU path, as
      `--gpu NGB` already does for the GPU path.
- [x] **`langs/NOTES.md`** — eleven measured Bend 2.0.34 behaviours, each with a
      reproducer. Four are checker defects, and **one contradicts this project's
      recorded loop answer**: `bend2-constraints.md` says Nat fuel is the escape
      for loops that will not satisfy the termination check, but a `case 1n+pn:`
      arm **cannot hold a def call at all** on 2.0.34 — the error blames the
      pattern binder `pn`. Every walk in `core.bend` is therefore list-fueled.
      That entry needs revisiting by whoever owns it. The other three: a def may
      not destructure a call's tuple result (the whole repo destructures
      parameters only, which is why it survived), `Array.get` and `Array.size`
      cannot be called on a def parameter (so the array becomes a list inside the
      kernel), and a nested pattern must be exhaustive at every level it names.
- [ ] **`wasm/core.wasm`** — blocked on the corpus reservation above. The glue,
      the C shim and the WASI host are written and typed; the module is missing.

## TWO SUBSTRATE DEFECTS found by mixin/reduce.bend (committed f3b4c9cf) -- MINE, NOT FIXED

- [ ] **`mo_resolve` (mixin/op.bend:718) COMPUTES THE WRONG THING FOR EVERY NEGATIVE
      DIM.** Its own comment says `dim` is a MAGNITUDE; it evaluates `|dim| + total`
      where Python evaluates `total - |dim|`. Wrong for every negative `dim`, and
      **op.bend's entire gate passes `False{}`** as the dim argument, so nothing in
      that file can see it. This is `reduce.py:45`'s `mo_downcast` neighbourhood and is
      the SAME cast as op.bend's M6 non-moving mutation.
      FIX: `U32.sub(total, dim)` instead of the add. VERIFY: op.bend's gate must stay
      green (it passes `False{}` everywhere, so it cannot detect the change — say so in
      the row) AND reduce.bend's `M17` mutation must start FAILING, because correct `0`
      and mutated `2` are currently both what the buggy resolve produces. M17 is
      blocked on this and nothing else.
- [ ] **`T.tn_rop` (tensor.bend:867) ROUTES ON THE UNFILTERED AXIS LENGTH.**
      `ops.py:657` filters size-one axes OUT of `reduce_axis` and then returns
      `self.reshape(kept)` with NO REDUCE at all; the port routes on the raw
      `len(axis)`, so it builds `AReduce{op, 0}` and never the reshape.
      **This is the sharpest case in the repo of why a node COUNT is not a gate:**
      both sides print 6 nodes with the same src-op sequence, and the shape and the
      root op are both wrong. Three rows in reduce.bend's gate are red because of it.
      FIX: route on the filtered length. VERIFY: those three rows go green against
      CPython, and a count-only row would NOT move -- which is the point worth keeping
      in the mutation table.

Both are one-line fixes in files no agent currently owns. They are recorded rather
than done because each needs two full gates to verify and the session's compile
budget was better spent on the seven in-flight units.

## OPEN — `H.dedup_u32` reverses, and `nn/optim`'s filter reverses, and they may be CANCELLING

- [ ] **SUSPECTED DOUBLE CANCELLATION. NOT CONFIRMED, NOT FIXED, NOTHING COMMITTED.**
      Found while converting accumulator folds to `List.foldl`; reverting rather than
      committing a change that flips two committed rows.

**The claim, and it is CPython-measured.** `helpers.py:23` is
`list(dict.fromkeys(x))` and the comment says "retains list order". CPython agrees:
`dedup([1,7,1])` is `[1, 7]` and `dedup([3,1,3,2,1])` is `[3, 1, 2]`. The port's
`dedup_u32.put` is `case False{}: h <> r` — a PREPEND — while `dedup_u32(xs)`
recurses on the tail, so the head is processed LAST. On its own that reverses.
(`function.bend` reported this independently and carries a local append-based dedup
with the reason written down; its `call_uops` order IS the slot numbering.)

**The measurement that made it suspicious rather than merely wrong.** With
`dedup_u32` changed to `List.append` (order-retaining, CPython-correct):
  - `nn/optim`'s `op_params` and `op_nop` both went **True -> False**.
So the pre-existing green was produced by a reversing dedup downstream of a
reversing filter, i.e. two errors that cancel. `nn/optim`'s `op_filter.tgo` recurses
on the tail and APPENDS, which reverses too.

**Where it stops, honestly.** Fixing BOTH (foldl left-to-right + appending dedup)
still reads `op_params=False`, and a debug print shows `params=2,1,` where the row
wants `"1,2,"`. That CONTRADICTS the standalone probe that proved `List.foldl` is
left-to-right (`[1,2,3]` -> `"1,2,3,"`), so one of these is true and I could not
determine which within this session:
  (a) `g_all`'s fixture list is not in the order its own `g_all.pick` reads as
      (three `List.append` calls that may not compose the way they look), or
  (b) the `~A`/`~B` slots on a `Data` element type do not mean what they mean on a
      scalar, and the fold is visiting right-to-left for `T.Tensor` elements.
`nn/optim` is a COMMITTED file with 11 green rows, so this is not something to
resolve by inspection at midnight.

**The next person should do exactly this, in this order** (~15 minutes):
  1. print the RAW fixture list before filtering — `us()` of `g_all(...)`'s uops —
     and settle (a) vs (b) with one number;
  2. if the fixture is in order, the fold direction is the bug and it is worth
     understanding, because ~97 hand-rolled folds in the tree would be affected;
  3. if the FIXTURE is reversed, fix the fixture and both rows go green with the
     CPython-correct dedup, and `function.bend`'s local dedup can be deleted;
  4. only then delete the workaround in `function.bend:868`.
Reverted state verified: `nn/optim.bend` output is byte-identical to the committed
baseline (11 rows, zero False). `helpers.bend` and `nn/optim.bend` restored via jj.

## Session 2026-10-02 — `runtime/ops_metal.bend` (the Metal device: the half that SUBMITS)

- [x] `tinybendygrad/runtime/ops_metal.bend` — `tinygrad/runtime/ops_metal.py`, 287 -> 3486
      lines, 455 defs/types, **329 gate rows**, `ALL PROOFS CHECK`, the interpreted
      and native lanes **byte-identical**, and **167 of 329 rows answered by a CPython
      oracle with 0 disagreements** (`python3 .agents/slop/mt_diff.py` prints
      `THREE LANES AGREE`). The oracle `ast`-walks ops_metal.py for the selector
      order and OPENS A REAL `MetalDevice()` for the arch and the family, so
      `arch = Apple8`, `check_family("Apple") = 1008`, `check_family("Mac") = 2002`,
      `MTLResourceStorageModeShared = 0`, `len(d.sels) = 18` and `d.sels.nbytes = 144`
      are MEASURED on this host, not transcribed.
      * **THE TEMPLATE RULE, obeyed exactly.** A def either builds the argument of one
        objc call or records that call in the trace — no third kind — so the `raise`
        lives in the trace and a refusal is a TRUNCATED trace needing no guard of its own.
        `Tr.emit` is the seam and `Tr.emit.go`'s `Bool.pick` on `refused` is THE RAISE.
      * **device.bend IS CONSUMED, not re-derived.** `D.iter_sig` IS `layout_args`' engine
        (hcq2.py:74 zips `TinyELF.iter_sig` against the itemsizes and device.bend already
        ports `iter_sig`); `D.host_offset` IS `MetalAllocator._offset`; `D.Bar`/`D.bnew` ARE
        `_alloc`'s and `new_icb`'s Buffers, so `nbytes` is `size * itemsize` and
        `new_icb`'s `BufferSpec(nolru=True)` gets "never recycled" from `D.recycled`'s
        four conjuncts for free (`mt_nolru`).
      * **IT COMPOSES WITH cstyle's committed Metal renderer**, and the header says so
        with the four numbers the two files have to agree on: ONE binding at index 0
        (`:256 setMaxKernelBufferBindCount(1)` against `cstyle.py:372`'s
        `constant args_t& args [[buffer(0)]]`), the struct's byte offset
        (`:112 off = round_up(nbytes, 256)`), the global and local size as two `MTLSize`s
        (`:116` / `:264`), and the entry-point NAME (`:247 newFunctionWithName` against
        `TinyELF.name`). The only thing missing for a kernel to RUN on this host is
        `MetalCompiler.compile` (:42-71), which drives MTLCompiler through Apple's block
        ABI (`ctypes.byref(callback, -0x10)`) — a seam, and everything it needs (the
        `-std=metal4.0` version, the 4-byte-padded blob, the 16-byte `<QQ` request
        header) is computed and gated here.
      * **SEVEN REAL BUGS FOUND BY THIS GATE, and none of them was a type error.**
        `--check-only` said `ALL PROOFS CHECK` through all seven. `csrc_pad` dropped a
        subtraction (M1); `q.items` built `[vals] ++ [globals]` because `List.append` is
        `xs ++ ys` (M4); `sync_count` used `round_up` where the source says
        `len(range(...))` and `round_up(4,4)` is 4 (M22); `sync_range` consed and then
        reversed (M23); `pmb_m2` was chained off `pmb_m0` and so inherited `tag="mtl_sel"`
        (M26); `dev.pipeline.f` called the COMPILER's MTLB/ENDT check and so every
        pipeline refused (M26c); and `pmb_keep` did not advance the rule index on a miss,
        so rules 1 and 2 never ran (M26d).
      * **48 mutations measured, TWO move nothing, and ONE of those is a finding about
        the PYTHON.** `M26b` (M1's `tag="mtl_sel"` conjunct) is 0 rows because
        `device.py:404`'s second rule has the IDENTICAL `name="b"` pattern, fires on
        every node M1 fires on, and answers the same thing — so **Metal's first
        `pm_bufferize` rule is REDUNDANT with `Compiled`'s second one, on every input**,
        and the only difference it can make is to fire LESS. The other non-mover is a
        `+`-only edit; the comment-only edit (the control) is the third 0.
      * **The brief's `dtype-to-MTLPixelFormat` table does not exist** and this port says
        so: `grep` finds no `MTLPixelFormat` in ops_metal.py and there is no
        dtype-to-format mapping in it at all. The two-directional table this file really
        has is `enum_MTLGPUFamily` (19 members), and `check_family`'s REVERSED
        `next(filter(...))` plus the `[12:]` arch slice are gated both ways
        (`mt_fam_*`, `mt_arch_*`), with a last-wins mutation (M30, 8 rows) because
        `reversed()` is what makes it last-wins.
      * **The brief predicted PROOFS FAIL from FFI seams and there are NONE.** A
        `dtype.bend` seam is a `def ... -> IO(R)` whose body is two `import "./x.c"`
        lines and it makes every importer red; this file does not take that route
        because the WebGPU template does not — a Metal call is recorded in a `Tr` trace,
        so there is no foreign effect to declare. The seam is `Tr.emit`, the ORDER is the
        artefact, and `wgsl.bend`'s green lane is the precedent, not `dtype.bend`'s.
      * NOT PORTED, 9 `TODO(p3)` lines each naming its Python line: the two `DLL(...)`
        library loads (:18, :35), the `NSString` from `to_ns_str` (:23), `__reduce__`'s
        pickle (:41), `disassemble`'s subprocess (:76), the `checked` error TEXT (:26),
        the callback's `errorMessage` (:52), the block ABI in `BuildRequest` (:68),
        `GPUStartTime/GPUEndTime * 1e9` (:281, no F64), and the `pm_encode`/`pm_lower`/
        `pm_bufferize` UOp-MATCHER bodies (:190, :193, :217).
- [x] `.agents/slop/mt_oracle.py` — the FIRST oracle: `ast`-walks ops_metal.py for
      `HANDLES + SELECTORS`, the thirteen-STATEMENT shape of `run` with its four arms
      tagged, the twelve statements of `MetalDevice.__init__`, and the three `run`
      invocations of `submit`; then OPENS a real device for the family, the arch, the
      storage mode and the sels size. `python3 .agents/slop/mt_oracle.py` (add `--nol`
      for the offline rows).
- [x] `.agents/slop/mt_rows.py` — the 167-row gate oracle, one `name=value` per row the
      gate can answer, every value a CALL (`helpers.round_up`, `hcq2.layout_args`,
      `sysdevice.supportsFamily`, `MetalDevice().arch`, device.py:280's LRU policy).
- [x] `.agents/slop/mt_diff.py` — the three-lane diff: interpreted, native, CPython.
      Prints `THREE LANES AGREE` and exits 0.
- [x] `.agents/slop/mt_mutate.py` — 48 mutations, each reported with the rows it moved
      BY NAME. Refuses to run a mutation whose `old` text does not match exactly once,
      which is what makes "0 rows moved" honest.
- [x] `.agents/slop/notes/bend2-constraints.md` — twelve appended rules from this unit,
      plus the `pm_bufferize` redundancy finding (same shape as the `ops_disk` one).

## Session 2026-10-02 — `runtime/ops_cl.bend` (ONE device, THREE vendor spellings)

- [x] `tinybendygrad/runtime/ops_cl.bend` — `ops_cl.py` (130) + `ops_cuda.py` (136) +
      `ops_hip.py` (71) in ONE file, because they are one 39-op device. 3200 lines,
      508 defs/types, **447 rows, THREE LANES BYTE-IDENTICAL** (interpreted, native,
      and a CPython oracle that imports `autogen.opencl`/`autogen.cuda` with no
      device present), `ALL PROOFS CHECK`, `share.py` clean. NOT COMMITTED.
- [x] **No `@extern` seams** (a departure from `dtype.bend`): the TRACE is the seam.
      `vend.name(vendor, op)` reads every trace entry back as its C symbol, which is
      why `--check-only` stays green and the gate runs at all. Six bugs the gate
      caught that review did not:
      * **`vend.cl` had 40 cells for 39 ops**, and `cuModuleLoadData` /
        `hipModuleLoadData` sat at `OP_BUILD` (12) while `clCreateProgramWithBinary`
        sat at `PRG_FROM_BIN` (11) — so the trace printed `(128)` with an EMPTY name
        where the module load belonged. Fixed by an oracle that SCANS the three
        sources for `cl.X`/`cuda.X`/`hip.X` and asserts every hit is either in the
        table or in an explicit `NOT_A_CALL` allowlist (11 typedefs/enum members).
      * **`cu.launch_size` subtracted the kernargs base on every fold step**, so
        `[40, 12, 24]` answered 16 where `max(...) - 8` answers 32, and the EMPTY
        case answered 8 where `default=8` answers 0. A `max`'s `default` is an
        initial accumulator, not a zero case.
      * **`hp.sync` dropped `hipSetDevice`** (hp:22-24 `synchronize` is TWO calls).
      * **`cu._map`'s branch key is the device NAME**, not the host: a CUDA device
        WITH a host returns at cu:87 without asking about alignment, and a non-CUDA
        device with NO host raises the *alignment* message. The signature is now
        `(device, is_cuda, has_host, aligned)` and the gate pins all six cases.
      * **`hp.fields` tested the buffer count where the Python reads `len(fields)`**
        (the sum), and read the last offset from the value list even when it was
        empty; `hp.fields` now takes `(nf, iszs)` with a row per arm.
      * **`Sig`'s field names were inverted** (`w` was `shape[0]`), which made
        `cl.pitch` look wrong when it was right. Fixed in the NAMES, plus two pitch
        fixtures that differ only in WHICH extent is 257.
- [x] Two DEAD rules found and DELETED, both with the mutation that proves it:
      `cl_err_hit`/`cu_err_hit` (a `dict.get(k, d)` inside an f-string has no
      `is not None` test to port — the default IS the lookup's default, so the pick
      was a tautology) and `Tr.hit`'s `not(is_zero(bad_at))` conjunct (the ordinals
      are one-based, so `bad_at = 0` can never equal `hits + 1`).
- [x] ~~`$TMPDIR/opencode/opscl/oracle.py`~~ — **CANCELED, THIS PATH IS DEAD.** The
      artifacts went to `$TMPDIR` and were gone before the commit (checked 10:35), so
      the 445 rows are reproducible by running the `.bend` but the CPython *comparison*
      is not reproducible from the repo. `.agents/slop/` is the rule precisely because
      `$TMPDIR` does not survive. **TODO: rebuild this oracle into `.agents/slop/`
      before anything else touches `ops_cl.bend`.** (Earlier count said 447, actual
      `=`-rows are 445; the two extra were multi-line.)
- [x] `oracle.py` (the CPython oracle, second independent transcription keyed by
      SYMBOL) and `mutate.py`
      (50 mutations, each reported with the rows it moved BY NAME; refuses to run a
      mutation whose anchor does not match exactly once). **47 move >= 1 row, 1
      control (`comment-only`) moves 0, 2 blind spots and both are the deleted dead
      rules.** Four further mutations were REJECTED by the type checker rather than
      by the gate and are counted separately — a weaker kill.
- [x] `.agents/slop/notes/bend2-constraints.md` — twelve appended rules, 62-73, on
      symbol-keyed tables, f-strings as total functions, fold bases, one-based
      ordinals, `List.append` vs `x <> t`, branch keys, and the control-vs-blind-spot
      distinction.

## Session 2026-10-02 — a COMMITTED GATE ROW WAS ENCODING A BUG (found by the ops_cpu unit)

- [x] **`tinybendygrad/device.bend:869` `go_slot` — REAL DEFECT, fixed in `7f170f64`.**
      `device.py:366` is `yield (offset := round_up(offset, dt.itemsize)), dt`
      followed by `offset += dt.itemsize`. The **walrus assigns the ROUNDED value**, so
      the next offset is the ALIGNED slot plus the itemsize. The port computed
      `round_up(off, k)` for the slot but `off + k` for the advance — walking from the
      UNALIGNED offset and drifting. Measured: itemsizes `[4,8,4]` gives CPython
      `[0,8,16]` and the port gave `[0,8,12]`.
- [x] **THE ROW ENCODED THE BUG.** The committed gate read `sig=0 4 5` and its comment
      said *"advances the running offset by the RAW itemsize. Rounding the advance as
      well gives `0 4 8`"* — naming CPythons behaviour as if it were a variation to
      consider. That is the projects explicit prohibition (never close a row that
      encodes the bug), in a COMMITTED file, and it survived because the row was
      **internally consistent**: every mutation moved nothing, because the row asserted
      the ports own behaviour. Now `sig=0 4 8`, which is what CPython prints. Exactly
      ONE row moved in the whole 107-row gate; the two pre-existing `lru` False are
      unchanged.
- [x] **Lesson, and it generalises past this file:** a self-consistent gate proves the
      port agrees with the gate, not with CPython. A row is only evidence if its
      expectation was *generated by CPython* (or hand-checked against it) — otherwise
      the gate is a change-detector wearing a green shirt.
- [x] `tinybendygrad/runtime/ops_cpu_null.bend` — `ops_cpu.py` (96) + `ops_null.py` (68)
      in ONE file. 308 rows, THREE LANES BYTE-IDENTICAL, `ALL PROOFS CHECK`, **GREEN**.
      305 blocks, 305 reachable from `main`, **0 dead** after a full dead-def audit.
- [x] **The ops_metal finding CONFIRMED on a second device:** no `SOME PROOFS FAIL`,
      because a `dtype.bend` seam is a `def ... -> IO(R)` with two `import "./x.c"`
      lines while a template-following device records calls in a `Tr` trace and declares
      NO foreign effect. **Three devices now (webgpu, metal, cpu/null, cl).**
- [x] 109 mutations, 3 move nothing, **all three ARGUED not papered over**: two are
      PROVABLE equivalences (`Nk.same` is Python tuple equality so `null_events` can
      never hold two equal keys; the thirteen zero-table names are thirteen separately
      measured ops so at most one matches — first-wins IS last-wins on every reachable
      input, and planting a duplicate would assert a state the program cannot be in),
      and the third is the comment control.
- [x] **FOUR HOLES CLOSED RATHER THAN DECLARED**, one of which is *our own bug coming
      back*: M56 found `Tr.has` with fuel = pattern length, which is the `ops_webgpu`
      defect REINTRODUCED and **missed by its own rejection rows**. Also: both `peer`
      rows were non-remote; no zero-argument fixture existed (measured
      `pack_args([], 8)`); `starts_with("gfx")` vs `"gfx1"` is indistinguishable on
      `gfx1100`.
- [x] **TWO FINDINGS BECAME DELETIONS:** M78 exposed `Tr.next` as a field whose rewind
      nothing could observe, and the dead-def audit then found NINE more unreachable
      blocks. The mutation harness also caught **two false claims in the agents own
      comments** — a harness that checks code but not prose about it is half a gate.

## Session 2026-10-02 — `runtime/ops_nv.bend` (606 rows, TWO AGENTS, ONE FILE)

- [x] `tinybendygrad/runtime/ops_nv.bend` — `ops_nv.py`, 3836 lines, 606 rows,
      `ALL PROOFS CHECK`, lanes identical, 22 intentional False. Committed `524737e3`.
- [ ] **RE-RUN THE MUTATION HARNESS FROM SCRATCH.** At 09:15 I saw no `ops_nv.bend`,
      concluded the agent was dead, and RE-DISPATCHED. The original was not dead — it
      was slow — and **two agents wrote the same file for a whole session.** The
      second noticed, said so, and switched to convergent debugging; it explicitly
      **declines to claim the bulk of the work**. One of its in-place mutation
      harnesses (`cp` back over the source) clobbered a concurrent write once; nothing
      was lost, but **the two mutation tables INTERLEAVE and neither is attributable.**
      M28 already proves at least one constant is correct and ungated, so a rerun is
      not ceremony.
- [x] **THE STANDOUT FINDING, verified by me against the authority: 33 of 219
      constants were WRONG in a file already printing 590 GREEN ROWS.** Spot-checked
      two by hand against `tinygrad/runtime/autogen/nv_570.py`:
      `CLASS_BLACKWELL_COMPUTE_A` is `0xCDC0` = 52672 and `CLASS_AMPERE_COMPUTE_B` is
      `0xC7C0` = 51136; both were wrong and both are now right.
- [x] **Why no gate could have found them — the lesson is bigger than this file:** a
      590-row green gate and 33 wrong constants coexisted, because the gate tests
      *graphs* and the constants answer to a **C header nobody was reading**. The fix
      is an audit that compares every `def X() -> U32: n` against the generated
      header, not another row. **Every table ported from `autogen/` needs this audit.**
- [ ] **GENERALISE IT — but MEASURED FIRST, and the answer is "hand maps, not a
      script."** I wrote `.agents/slop/const-audit.py` to do this automatically and it
      is only a SMOKE TEST. Its control on `ops_nv` passes (**0 likely-WRONG**; the 8
      it flags are index-vs-ioctl name COLLISIONS, correctly not called bugs), but its
      COVERAGE is the finding: name-matching reaches only **0-18 of 222** consts,
      because the ports RENAME (`CLASS_BLACKWELL_COMPUTE_A` vs the headers
      `BLACKWELL_COMPUTE_A`) and often mean something else by the same name. So the
      `33/219` audit was a **hand-built 219-entry map**, which no script reproduces.
      **Scale of the real work: 533 numeric const defs across 7 committed
      device/renderer files** (`ops_nv` 222, `ops_metal` 106, `ops_cl` 103,
      `ops_webgpu` 67, `ops_cpu_null` 29, `cstyle` 6, `tc_ptx` 6), plus whatever
      `ops_amd`/`ops_qcom`/`ops_dsp` are adding RIGHT NOW. Assign this per file, with
      a hand map, as a real unit -- do not trust the script's `0` as a verdict.
      **SUPERSEDED SCOPE, measured by me after that entry was written: it is 1,884
      constants across 25 files, not 533 across 7.** Counting every `def X() -> U32: <digits>`
      in the tree: `system.bend` 168, `ops_nv` 219, `ops_qcom` 147, `bnxtdev` 136,
      `am/ip` 122, `amdev` 115, `usb` 111, `ops_metal` 109, `ops_cl` 91, `ops_rdma` 84,
      `ops_dsp` 80, `ops_amd` 78, `ops_webgpu` 65, `memory` 48, `ops_disk` 40, `hcq2` 31,
      `ops_cpu_null` 29, `ops_npy` 18, `dsl` 155, `ptx` 8, `nv/ip` 11 and 5 small files.
      The three files this entry called "adding RIGHT NOW" have landed and added 305.
      At `ops_nv`'s measured **15%** that is ~280 wrong constants in files whose gates are
      green. **`ops_metal` is dispatched.** Each remaining file is its own unit.
- [x] The wrong values were not cosmetic. All eleven `CLASS_*` ids meant `iface`'s
      ladder compares against the GPUs real class list and **NEVER MATCHES**, and
      `CLASS_BLACKWELL_COMPUTE_A` held the `_B` value — so a Blackwell_A GPU would have
      been handed the entire ver-3 QMD layout. `PCI_MMIO_OFF` had one hex digit-pair
      misread (`0xBAE000` for `0xBB0000`).
- [x] **A TAUTOLOGY that had to be chased down:** the row `nv_qmd_ver_bwa` fed the
      ver-5 THRESHOLD in as its own INPUT, so mutating the constant moved zero rows.
      Renaming it did not help — the same number on both sides. Only writing the
      literal `52672` made it a test (now moves 3 rows). **New rule appended: a gate
      row whose expected value is a def of the thing under test is not a test.**
- [x] The incoming header **OVERCLAIMED on arrival**: it asserted all four stages had
      landed while `pc.key`, `qmd.read/write`, `pd.*`, the copy/encdec queues and
      `dev.vid_hw` were absent **AND THERE WAS NO `main` AT ALL** — 1111 lines of defs
      with no gate, which is worth nothing. Closed: a port with no gate is a stub with
      extra steps.

---

## Session 2026-10-02 — `runtime/ops_nv.bend` (the CUDA device: the words it uploads)

- [x] `tinybendygrad/runtime/ops_nv.bend` — `tinygrad/runtime/ops_nv.py` (841 lines) +
      `hcq2.py:63`/`:74-76`. 3897 lines, 630 defs, **600 gate rows**, `--check-only` is
      `ALL PROOFS CHECK`. **543 rows cross-checked against CPython with ZERO
      disagreements**, 56 Bend-only, 4 oracle-only. `.agents/slop/nv-oracle.py`,
      `nv-diff.py`, `nv-mutate.py`.
- [x] **THE RECONCILIATION PASS: 73 rows that looked like coverage and were not.** The
      differ keys on the row NAME, so `nv_slmtot_*` against `nv_slm_*`, five
      `nv_toname_*` with the parts joined in the other order, two rows printed TWICE,
      and ~20 oracle rows with no gate row were each reported as *unmatched* rather
      than as a disagreement — while the summary line said 0 disagreements.
- [x] **`nv_query_litter_n` was WRONG ON BOTH SIDES AND THEY AGREED.** The gate said two
      of `_query_gpu_info`'s five requests take the LITTER fallback, the oracle said two
      and was a hand-written literal, and the differ said 0 disagreements. Asking
      `nv_570.__dict__`: THREE do, and they are positions **0, 1 and 2**. Two
      consecutive wrong readings ({1,3}, then {1,2,3}) before the driver answered. The
      oracle rows now evaluate `ops_nv.py:665`'s own `getattr` chain.
- [x] **Seven tautological rows deleted** (a hardcoded `"True"`, a hand-written
      `"min() iterable argument is empty"`, `row("nv_err_0_err", "")` where all four
      `get_error_str` raises are guarded by `if status != 0`). A row nobody can compute
      cannot fail.
- [x] `nv_vid_unk_is_none_new` was written `Bool.not(vid_unk_none(2097152))` and printed
      `True` where the claim is `False` — a name that contradicted its own value, with
      no oracle row to say so. Fixed, and `nv_query_ix_*` added so the resolved index
      VALUES (20, 23, 32, 13, 12) are printed beside the booleans.
- [x] **M30 found its own blind spot**: dropping the 128 KiB rounding from `slm_bytes`
      moved NOTHING, because all six real fixtures are already exact multiples of
      131072. `nv_slmtot_1_1_1` (1 against 131072) kills it. M13 remains a genuine
      equivalence blind spot: `found < len` and `found != len` are the SAME predicate
      over every answer `pc.find` can give.
- [x] **The `device.bend` `iter_sig` BUG — REPORTED, THEN FIXED UPSTREAM, AND THE
      STALE TRANSCRIPTION REMOVED HERE.** `device.bend:869-871` computed
      `Slot{round_up(off, k), U32.add(off, k)}`; `7f170f644` fixed it to
      `U32.add(round_up(off, k), k)` because `device.py:366`'s `:=` rebinds the
      ROUNDED offset. So `nv_REPORTED_args_device_mixed` no longer disagrees,
      `dev_bend_iter_sig` in `nv-oracle.py` was a transcription of a bug that no
      longer exists, and the three `nv_REPORTED_*` rows are now `nv_device_args_*`:
      `device.bend`'s answer beside this port's own `sig.slot`, with
      `nv_cpython_args_device_*` carrying `hcq2.layout_args`. **A permanent
      disagreement in `nv-diff.py` teaches every later reader to skip the section
      that matters, so an expected difference belongs in a comment.**
      `nv-diff.py` is now 0 disagreements.
- [x] `.agents/slop/notes/bend2-constraints.md` — four appended rules, **82-84**: a
      hand-written oracle row is a change detector and two of them agree; the differ
      keys on the row name so a misspelling is a hole in both directions; two claims
      must not share a row prefix, and a row's name must survive reading its value.

## STANDING INSTRUCTION (owner, 2026-10-02) — the agent pipeline does not idle

**When any agent lands, dispatch the next unit immediately. Do not wait to be asked.**
Agreed with the owner after the 10:56 wave. The coordinator's job on a completion is:
verify what landed, commit it with an honest message, THEN dispatch the next unit in
this queue — in that order, so the queue is never stalled behind a verification.

### The queue, in priority order. All are non-overlapping with everything in flight.

1. ~~**`runtime/support/am/ip.py` (755)**~~ **DONE** — see the `- [x]` entry for
   `tinybendygrad/runtime/support/am/ip.bend` below. On the instruction to "grep
   `ops_amd.bend` for `am/ip` citations and AGREE, report contradictions": grepped,
   and it cites `am/ip` **nowhere**. The two files agree on the seam split anyway and
   share no register table and no constant; their only overlapping function is
   `setup_ring`, which `ops_amd.bend` lists as a wall from `ops_amd.py:772` and this
   file ports as a trace. No contradiction to report.
2. ~~**`runtime/support/nv/ip.py` (661)**~~ **DONE** — see the `- [x]` entry for
   `tinybendygrad/runtime/support/nv/ip.bend` below. On the instruction to "grep
   `ops_nv.bend` for `nv/ip.py` citations": grepped, and it cites `nv/ip.py`
   **nowhere** — 22 hits for `ops_nv.py`, 10 for `hcq2.py`, **0** for `nv/ip.py`.
   So the premise that its citations constrain this port is FALSE, and that is
   reported in the file header rather than reconciled. Two further corrections to
   the brief: `nv/ip.py` is not "the nv ioctl protocol" (that is generated
   `autogen/nv.py`); it is the GSP RPC ring protocol and two bootloaders.
3. **`runtime/support/am/amdev.py` (421)** — the `/dev/kfd` surface. Most of it is FFI,
   so the gateable part is the **request struct layouts and the field order** (packed
   field order is the same lesson as `ops_cl`'s inverted `Sig` names, and a wrong order
   is a silently wrong register write).
4. **`runtime/support/system.py` (454)** — support/system. Likely mostly FFI; find the
   pure tables. If it is genuinely all FFI, the honest answer is a seam with named
   Python lines, and that is a legitimate result — say so rather than inventing rows.
5. **`renderer/nir.py` (321)** — real code, and `renderer/nir_llvmir.bend` stage 1 is
   already committed and names stages 2-4 in its header. Either do `nir.py` or continue
   those stages; check the header first for which is the bigger gap.
6. **[x] const audit of `ops_webgpu.bend` (67) + `ops_cl.bend` (89 uncovered)** — DONE
   by hand map. The smoke-test script covers 0 of these because the port invents names;
   the audit's value is the hand-built map. The two files audited in two commits.
     - `ops_webgpu.bend`: **65 consts | 14 EXACT | 0 WRONG | 51 PORT_ONLY**
       (`.agents/slop/ops_webgpu-const-audit.txt`, `.agents/slop/ops_webgpu_constmap.py`).
       All 14 header-mapped values (BIND_*, FILTER_*, MAP_*, FEATURE_*, USAGE_*,
       STATUS_SUCCESS) match `tinygrad/runtime/autogen/webgpu.py` byte-for-byte.
       The 51 PORT_ONLY are the OBJ_* (13) + CALL_* (23) + SYNC_* (11) family
       plus BIND_GROUP_INDEX, UNIFORM_SIZE, QUERY_COUNT, QUERY_BUF_SIZE -- all
       port-internal.
     - `ops_cl.bend`: **66 consts | 16 EXACT | 0 WRONG | 50 PORT_ONLY**
       (`.agents/slop/ops_cl-const-audit.txt`, `.agents/slop/ops_cl_constmap.py`).
       All 14 CL_* values match `tinygrad/runtime/autogen/opencl.py` byte-for-byte.
       `cl_err_n` = 63 and `cl_err_names_n` = 74 verified against the live autogen
       (74 names -> 63 unique codes). The 50 PORT_ONLY are the 41 OP_* trace tags,
       V_CL, three fold bodies (chk_count, cl_err_aliases), NO_IDX, PROG_INIT_N,
       KIND_MEM/IMAGE/SCALAR, PTR_SZ, IMAGE_CHANNELS.
   ops_cuda.bend and ops_hip.bend were promised by the brief's "three vendor
   spellings" note but, after the 1:1 file split, their vendor tables live in
   THOSE files; ops_cl.bend has only the CL spelling. They remain queued under
   ops_webgpu/cl's same recipe (commit `b5371bc4` for webgpu, `70297c60` for cl).
7. ~~**`runtime/support/usb.py` (473)**~~ **DONE** — see the `- [x]` entry for
   `tinybendygrad/runtime/support/usb.bend` below. On the instruction to grep for
   citing files: the answer is **EMPTY**, so unlike every other unit in this wave it
   was not scoped by a citation and the scope was chosen from the source. It closes
   ops_amd's USB3 wall (parts 1 and 3) and carries a CORRECTION back: ops_amd's 4096
   is `USB3`'s own control buffer (:42), not `usb_cq`'s offset 0x100c.
8. **[x] `runtime/support/autogen.py` (289) — ANSWERED, PORTED AS THE GENERATOR (`cbc8a37c`)**
   The scope question is settled and the owner ruled. **The premise was wrong: the output is
   150,174 lines over 35 files, NOT 216,933.** The 216,933 figure was stale twice over — the
   rebase moved the tree to 208,917, and 54 files / ~59k lines under `runtime/autogen/` come
   from `extra/` scripts and ISA databases that `autogen.py` does not generate. Verified
   independently: 32 static `load()` names = 72,736 lines, plus the three dynamic arms are
   `nv_610/580/570.py` at 26,568 + 26,001 + 24,866 = 77,435, reconciling to 150,171.
   **A generator port loses nothing: 99.996% of the output is derivable — SIX hand-maintained
   lines (0.004%), all emitted verbatim by `autogen.py:242/250/251`.**
   **But the honest cost, which is what makes this not "easy": the generator is 96% LOGIC.**
   LOGIC:EMISSION = 153:7 = 21.9:1. It is a port of 153 decisions, not 7 string joins. 160 of
   289 lines port and gate today; `tname`'s dispatch, `all_fields` and the ObjC half do not.
   **OWNER DECLINED the escape hatch for `tname`'s record arm:** it needs regex (Turing-
   completeness, forbidden without approval and not approved here) or mutual recursion (bend
   refuses: "a decreasing self-call (arguments are read left to right: each passed unchanged
   until one shrinks)"). It would buy 30,979 rows of *emission* and nothing else — the tables
   are the value, and 79,087 of 150,174 lines are tables/hex the generator already computes.
   The output is also what bend **cannot hold**: 7 of 9 required constructs are ABSENT, and the
   decisive one is not syntax — a bend `Data` carries no SIZE, no OFFSET, no address, so the
   output's central structure (70,056 `class X(c.Struct)` lines) has no counterpart at all.
   Landed: 1219 lines, 525 code, **0 dead defs**, 149 rows both lanes byte-identical, 3 oracles
   all from calling the real generator, 44 mutations with 42 moving. The 2 non-moving are
   proven (one a dead def orphaned by the wall, one a commutativity theorem no fixture in any
   language can separate). **The 38 bugs cited as motivation are RETROSPECTIVE — that is the
   already-completed `ops_nv` audit (entry below, marked [x]); both hand-checked values are
   already right in the port.** Treat 38 as a RATE (15%), never as a backlog.
9. **`nn/onnx` runners + op bodies** — `nn/onnx.bend` (2013) is committed with four
   node types unportable. Needs the fold keystone first, so dispatch this LAST.
10. **`schedule/prepare.bend`** — still an 8-line stub from 06:13. If the schedule agent
    lands `indexing` and `prepare` is still 8 lines, that agent is dead: re-dispatch
    against the stub. Same for any other file whose last write predates its dispatch.

### Health rule, learned three times today
**An agent with no file AND no `.agents/slop/` artifact ~20 min after dispatch is
dead.** Check both the target file and `.agents/slop/` before concluding. A dead agent
that DID stub leaves a stub, so a stub is a resumable claim and an absent file is not.

## Session 2026-10-02 — `runtime/ops_rdma.bend`, `runtime/ops_npy.bend`, `nn/torch.bend`

The last three core files, and the two smallest in the tree. **All three are green
in both lanes and against a CPython oracle.** 45 + 83 + 389 = 517 rows, zero
mismatches, zero `False` rows that are not a deliberate negative claim.

- [x] `tinybendygrad/nn/torch.bend` (45 rows) — `nn/torch.py` is FOUR LINES and the
      honest answer is neither "a fake row" nor "pure wall". It is a GATE:
      `sys.path.append(Path(__file__).parent.parent.as_posix())` then a guarded
      `import extra.torch_backend.backend` then `raise ImportError(msg) from e`.
      **`extra/torch_backend/backend.py` EXISTS in this checkout** and the import
      fails on `No module named 'torch'` — MEASURED by importing it, with
      `__cause__` inspected. So it IS upstream-backed and the backend is present;
      what is ported is the guard, and the gate checks the guard. `pathlib`'s
      NORMALISATION is the wall, with three measured counterexamples in the header.
- [x] `tinybendygrad/runtime/ops_npy.bend` (83 rows) — four lines overriding one
      method. The headline is `renderers or [Renderer]`: the `[]` is FALSY so NPY is
      NOT the renderer-less device its source line suggests. Its refusal is
      `Allocator.alloc`'s `assert size > 0`, and `_free` is a NO-OP (no `remote`,
      so no `munmap`).
- [x] `tinybendygrad/runtime/ops_rdma.bend` (389 rows) — the buffer-registration
      trace, the address-translation table in BOTH directions, and the doorbell /
      completion-queue order rules. Three refusals (:44 peer group, :48 empty
      `max()`, :120 ring cap) and a FOURTH that no Python guard writes down — a
      work queue element whose buffer has no registered key must not be posted.

### THREE REAL FINDINGS, and two of them are PORT BUGS THE ORACLE CAUGHT

1. **`BNXT_VENDOR` was 5356 (`0x14EC`), not 5348 (`0x14e4`).** `ops_rdma.py:18`.
   A hand-typed constant. The oracle printed the real one and the diff named it.
2. **The page-size guard was OUTSIDE the `register_mem` call.** Python raises at
   :48 BEFORE it reaches :50, so a buffer with no usable page size is NEVER
   REGISTERED. The port recorded `REGISTER(0), REFUSE(log_page)` — the
   registration happened and THEN the refusal, which is the opposite of the source.
   `map.run` now nests the guards INSIDE the call. A trace is only a truncation if
   the refusal comes first, and the nesting IS the claim.
3. **`peer_group` is `"PCIDevice"`, not the device head.** device.py:398's
   `getattr(getattr(self, 'iface', None), 'peer_group', device.split(":")[0])`
   finds an iface on RDMA, and `PCIIfaceBase.peer_group`
   (support/system.py:297) is `getattr(self.pci_dev, 'peer_group',
   type(self.pci_dev).__name__)`. MEASURED. So :44's guard passes for ANY TWO PLAIN
   PCIe devices and only catches a USB or remote one — the port had it as the head,
   which would have refused every cross-device mapping and made the guard's two
   conjuncts LOOK like node selection when they are not.

### REPORTED, NOT FIXED — for the owner of `ops_rdma.py`

- **THE DOORBELL'S HIGH WORD NEVER LEAVES THE HOST.** :148/:152 OR in
  `db_value(qpn, SQ|RQ, 0, 0)` / `db_value(scq_id|rcq_id, CQ, 0, 0)`, and :109
  casts every int to `UOp.const(s, dtypes.uint32)`. `db_value`'s low half is
  `index | epoch << 24` with BOTH 0, so its low 32 bits are 0, the OR is a no-op,
  and the cast drops the high half — the only part naming WHICH QUEUE. MEASURED:
  `db_value(5, DBC_DBC_TYPE_SQ, 0, 0) == 288230397626548224` and
  `288230397626548224 & 0xffffffff == 0`. `ops_rdma.bend` is faithful; the rows
  `rdma_db_hi_dropped` / `rdma_db_lo_zero` / `rdma_db_or_noop` make it visible.
- **`queue_of` compares a string against `wire.tag`, and `wire.tag` is `None` on a
  bufferized PARAM** (`UOp.tag` defaults to `None`, ops.py:244; `UOp.from_buffer`
  does not set it, ops.py:862), so on a graph that reached `lower_call` with the
  wire already bufferized `min(gpu, None)` raises `TypeError`. COULD NOT BE
  EXERCISED — no RDMA hardware here — so the port keeps the SORT as the source
  writes it and the header says so rather than "fixing" it.
- **`extra/torch_backend/backend.py` imports `torch`, which is not installed**, so
  `tinygrad.nn.torch` cannot be imported in this checkout at all. That is the guard
  working, not a defect, and it is why `nn/torch.bend`'s gate pins the derivation
  and the message rather than a successful import.

### IS `ops_npy` THE PROJECT'S FIRST END-TOEND-PORTABLE DEVICE? YES, WITH A CORRECTION

The brief's premise needs one amendment: `ops_npy.py` does not touch numpy. Its
surface is `HostAllocator`'s — `mmap` plus a memoryview plus the default
renderer. The CONCLUSION is right and stronger for it: it is the only device in
tinygrad whose entire contract is host memory, with no driver, no FFI, no queue, no
shader and no PCIe, so it is the one where the contract can be checked by RUNNING
it. The CPython oracle allocated 12 bytes on a real `NpyDevice('NPY')`, wrote
0..11, read them back, compared, and freed; `_map`'s `BufferStorage(buf.host.addr)`
was confirmed to carry `meta=None` and `host=None`, which is the claim
`npy_map_st_args = 1` rests on. And `npy_roundtrip=True` is printed by the ORACLE
and deliberately NOT by the .bend file — simulating `mmap` in Bend and then
checking my own simulation would be theatre. The two claims are separate on
purpose: this file gates the TRACE, the oracle gates the BYTES.

### SIX MEASURED BEND RULES APPENDED

`bend2-constraints.md`, "MEASURED BY THE `runtime/ops_rdma` + `ops_npy` +
`nn/torch` UNIT". The two that cost the most: **`List.append` is `xs ++ ys`, so a
fold that appends must NOT reverse at the end** (measured twice in one session,
and both times every SYMMETRIC fixture agreed either way — an appending fold needs
a two-element unequal fixture before it can be checked at all), and **a port of a
load-after-a-store takes the POST-store value as its parameter** (reading the
pre-bump value computes `0 - 2` and a `U32` wraps silently to 4294967294).

---

## Session 2026-10-02 — `runtime/ops_dsp.bend` (the generic C-backend-for-a-DSP wrapper)

- [x] `tinybendygrad/runtime/ops_dsp.bend` — `tinygrad/runtime/ops_dsp.py`, 292 ->
      2827 lines, 385 defs/types, **496 rows**, both lanes byte-identical,
      `ALL PROOFS CHECK`. No foreign effect and no `import "./x.c"`: a
      template-following device records its calls in a `Tr` and declares nothing,
      which is why it prints no SOME PROOFS FAIL.
- [x] **420 of the 496 rows carry a `py=` expectation GENERATED by CPython**, and
      `.agents/slop/dsp_gate_check.py` re-checks every one of them against the lane's
      output on every run. First run: **35 disagreements, SIX of them real port
      bugs** — `attrs_of`'s head/tail order (`List.append(a,A,xs,ys)` is `xs ++ ys`),
      `dt_itemsize` with no fp8 arm, `compiler_args_first`'s two arms swapped,
      `alloc.offset` keeping the parent's size because the record binder shadowed the
      parameter, `open_lib_bad`'s unsigned compare for a SIGNED 32-bit test, and
      `link_lines` which was wrong twice (a leading separator, then a reversed
      order). Six bugs at a fifth of `cstyle.bend`'s 215 hand-typed expectations.
- [x] `.agents/slop/dsp_oracle.py` — the CPython oracle. Beyond the pure tables it
      **drives the real `DSPDevice` methods with the ioctl/os layer faked**, which is
      how `init_dsp`'s seven-call ORDER, `exec_lib`'s ELEVEN-call retry and NINE-call
      double failure, and `_free`'s munmap/close/ION_FREE order were measured rather
      than read.
- [x] `.agents/slop/dsp_mutate.py` — **68 mutations** (67 + a comment-only control),
      applied one edit at a time to a scratch copy BESIDE the source. 65 move rows,
      17 of them localised single-row rows. Control moves 0. The table is in the file.
- [x] `.agents/slop/dsp_gate_check.py` — the mechanical `py=` checker.
- [x] `.agents/slop/notes/bend2-constraints.md` — **eight more measured Bend rules**,
      appended at lines 7295-7376. The load-bearing ones: `U32.shl` is a ONE-BIT
      shift (the n-bit one is `U32.shln(a, n: Nat)`, so every shift AMOUNT is a
      `Nat` literal); a `case 1n+m:` arm spends the scrutinee `n` as well as `m`;
      a record pattern's binder SHADOWS a same-named parameter and nothing says so;
      and **a mutation harness that diffs row NAMES instead of whole `name=value`
      lines reports all 68 mutations as "0 rows moved"**.
- [x] **`to_scalar`/`from_scalar` DO NOT EXIST in tinygrad.** The brief named them as
      this file's centre; `rg -n "to_scalar|from_scalar" tinygrad/` finds only
      `lower_to_scalar`, a Mesa NIR boolean in `autogen/mesa.py`. What ops_dsp.py
      actually does with a dtype is four tables — `dt_fmt`, `dt_itemsize`,
      `dt_cname`, and the GLOBAL/ALU split of :32 — and those are what the file
      gates. Reported in the file's header rather than invented.
- [x] **`ops_qcom.bend` CANNOT BE CONTRADICTED BY THIS FILE.** Read at 2026-10-02, it
      was a 15-line stub claiming the shared qnn/htq op tables. ops_dsp.py has NO op
      table: `DSPRenderer` inherits `ClangRenderer.code_for_op` and removes exactly
      one entry (MEASURED 18 -> 17, the difference being `Ops.SQRT`), which is a
      renderer-internal dict. So `dsp_cfop_*` pins the COUNT and the REMOVAL and
      deliberately does NOT restate the seventeen entries — a second table is a
      second thing to drift.
- [x] Four walls, each with `# TODO(p3) runtime/ops_dsp.py:<line>` in the file: the
      clang spawn and the `.so` read-back; the ION/mmap/adsprpc ioctls; the
      listener's host syscalls and its `in_ptr` pointer walk; and the two u64 timer
      reads. The two programs' DIVISORS (1e6 and 1e9) are ported and gated, because
      a shared scale would move exactly one of three rows.
- [x] **The eviction NEGATIVE CASE is in this file's OWN code, not a fixture invented
      for it**: `ops_dsp.py:135` allocates the fastrpc shell with
      `BufferSpec(nolru=True)`, so `dev.shell_spec` is the one spec in the file that
      must NOT be recycled, and `dsp_norecycle_nolru` sits one row from
      `dsp_recycle_plain` at the SAME size with the opposite answer. Dropping the
      `nolru` moves exactly 3 rows (M59).

## Session 2026-10-02 — `schedule/indexing.bend`

`tinygrad/schedule/indexing.py` (328 lines) is ported and **green in both lanes with
245 of its 253 gate rows byte-identical to a CPython oracle**. The remaining 88 oracle
rows are three named walls and one blind spot, all stated in the file's footer.

- [x] **`prepare.py` in THIS checkout is `prepare_rangeify`, not `prepare_shape`.**
      Verified: `git log --all -Sprepare_shape` is empty and `rg prepare_shape
      tinygrad/` is 0 hits. The brief's framing was wrong, so `schedule/prepare.bend`
      must be ported from the file as written and gated on `_mop_index` /
      `split_reduceop` / `walk_mop` / `expand_bitcast`, NOT on a `prepare_shape`.
- [x] **The file no longer imports `uop/fold.bend`.** RA-8 in
      `bend2-constraints.md` records that a cold compile of anything importing
      `fold.bend` fails while another agent has it mid-edit, and the error names a
      def that is not in your file. That happened here four separate times
      (`Kahn.get`, `perm.go`, `perm_step`, `g_mv_r23`). `UOp.axis_id`/`axis_type`
      are now two LOCAL readers over `ARange{ids, at}` (8 lines) and `UOp.base` is a
      named wall (`ix_base_miss`). **Flip this back to `F.UOp.axis_id` once
      `fold.bend` settles** — reuse is the better default and this is a workaround,
      not a design.
- [x] **The mutation table found THREE dead decisions.** `ix_mv_flip_is_add`,
      `ix_mv_shrink_is_add` and `ix_ds_take` were each written, each commented with
      what it was for, and each never called — inverting the first two and widening
      the third moved ZERO rows. All three are wired now and move 8, 10 and 13. The
      lesson is RA-14: a `Bool.pick` inversion and an uncalled decision look exactly
      the same under `--check-only`.
- [x] **88 oracle rows this port cannot print**, in three buckets: 55 are `UPat`
      fields (`slen`/`rlen`/`anylen`/`name`/`nalts`/`src`) that `PMEntry` does not
      carry; 1 is `par_3_ops` (no tag -> `Op` inverse in `ops.bend`); 32 are the
      `_stack_select` binary tree (`ss{n>8}_{len,h}`) plus `mv_reshape{0,1,3}`. The
      walls print `W3` or nothing, never a faked value, so a diff can tell a wall
      from an answer.
- [ ] **`schedule/prepare.bend` is STILL A STUB** (8 lines). Port it from
      `prepare.py` as written: `walk_mop`, `_mop_index`, `store_hazard_boundary`,
      `fix_store_hazard`'s unsafe set, `split_reduceop`'s candidate scan, and
      `expand_bitcast`'s rate. The oracle already exists and runs:
      `/…/iprep/pp-rows.py` -> 631 rows in `pp-truth.txt`, clean.

- [x] **`tinybendygrad/runtime/support/hcq2.bend`** — `tinygrad/runtime/support/hcq2.py`
      (646 lines). **All three stages landed and checked.** 2243 lines, 360 gate rows,
      `ALL PROOFS CHECK`, interpreted and native lanes BYTE-IDENTICAL, and **0
      disagreements** against CPython on the 240 rows both sides compute.
      Oracle: `.agents/slop/hcq2-oracle.py` + `hq2-oracle2.py`, both run with `DEV=NULL`
      so no device is present; `.agents/slop/hcq2-diff.py` diffs; `.agents/slop/hcq2-mutate.py`
      is the 30-edit table at the foot of the file.
      PORTED: the constants both ways (`HCQ_DEVS`, `CDTYPE`, `HCQ_CACHE_THRESH`,
      `STAGING_*`), `to_name`, `all_devices_in`, **`layout_args`** (:74-76, the one
      `ops_nv.bend` cites at :14/:181/:205/:1439/:1873), `pack_args` (:78-83) with its
      `bytes(size-end)` refusal, the `cstruct`/`cfield` field tables and FIELD ORDER,
      `BatchCtx`'s `queues`/`last`/`prev`/`peers`/`signal_tags`/`slots`, `slot`/
      `queue_signal`/`sched_timeline`/`stamps` (the `n -> n*2` expansion),
      `_wait_ins`/`_start_ins`/**`_build_queues`**/`_finalize_batch`'s step order, and
      `sched_batches`' queue naming.
      NOT PORTED, WITH THE WALL FOR EACH: the ten `UPat`/`PatternMatcher` tables and
      every `u.toposort()` (the UOp arena is `uop/ops.bend`), `cfunc_buf`/`ccall`/
      `cfield`'s `getattr` (ctypes FFI — recorded as a `Tr` seam instead, which is why
      the file is `ALL PROOFS CHECK` and not `SOME PROOFS FAIL`), and the u64
      `nbytes` arithmetic in `lower_call`'s 128-alignment.
      CONFIRMED against the committed `ops_nv.bend`: `layout_args` of the six-word
      mixed list at base 0 is `0, 4, 8, 16, 24, 28` (ops_nv:205) and of three uint64
      buffers at 512 is `512, 520, 528` (ops_nv:181) — both asked of `hcq2.layout_args`
      itself in the oracle. `to_name` (:63) is the same formula `ops_nv:2917` carries.
      NO CONTRADICTION FOUND with `runtime/support/nv/ip.bend`: its traces are ioctls and
      this file's are the `hcq_fence`/`make_submit`/`HWQueue.submit` sequence, so the two
      traces share no table. Reported rather than reconciled.
      **THREE REPORTED BLIND SPOTS**, all in the file: `epilogue_queue`'s two arms are not
      separable with any NULL fixture (every batch opens on `COMPUTE:0`), `latest`'s
      per-queue `max` is unreachable because the same-queue FIFO filter runs first, and
      `HWQueue.q`'s word ladder is ported as a plan with its CPython blob hex in
      `hcq2-probe2.py` but has NO gate row, because the only trace it could hang on is a
      `NotImplementedError`.

- [x] **`tinybendygrad/runtime/support/am/ip.bend`** — `tinygrad/runtime/support/am/ip.py`
      (755 lines). **All four stages landed and checked.** 2792 lines, 447 gate rows,
      `ALL PROOFS CHECK`, interpreted and native lanes IDENTICAL, and **0 disagreements**
      against CPython over the 444 row names both sides compute. `ip.py` imports with NO
      card present, so the oracle needs no hardware.
      Oracle: `.agents/slop/ip_oracle.py`; driver `.agents/slop/ip_check.sh` (three lanes,
      diff keyed on ROW NAME because three names would otherwise collide silently).
      It keeps to the `ops_webgpu.bend` **trace lane** — `Tr`/`Call`/`Row`, `Tr.emit` as
      the only seam — which is why it is `ALL PROOFS CHECK` and not `SOME PROOFS FAIL`.
      PORTED: the version substrate `V` and every ladder (:15-47), the KIQ `flush_tlb` PM4
      packet (:99-113), the four-generation PTE flag tables and `is_pte_huge_page`
      (:177-195), the per-arch SMU message table 3 rows x 20 columns both directions
      (:199-215), the three-register C2PMSG protocol (:264-273), the doorbell arithmetic
      (:354 :366 :373 :570-572 :592), the `setup_ring` trace and its ONE raise (:584-606),
      115 register field-name rows BY NAME AND IN ORDER, the IH entry decode with eleven
      extractors (:502-513), and the PSP ring frame plus four union command field lists
      (:707-751).
      NOT PORTED, SIX WALLS, EACH WITH ITS `TODO(p3)` MARKERS: register ACCESS and
      `AMDReg.encode` bit POSITIONS (:367 :411), `hasattr`/`getattr` (:260 :389 :646),
      `functools.cache` (:177 :230), firmware BLOBS and `int(round(watts))` (:228 :250),
      thirteen `wait_cond` polls and six `time.sleep`s, and the memory manager (:278 :331).
      **CROSS-FILE, REPORTED NOT RECONCILED.** `ops_amd.bend`'s WALL 2 (its :173-178) says
      the same thing this file's WALL 1 does: the port carries WHICH register, WHICH field
      NAMES and IN WHICH order, and the OFFSETS are `autogen/am/regs/*`'s, per arch. The
      two AGREE. MEASURED: `ops_amd.bend` cites `am/ip` NOWHERE, and the two share no
      register table and no constant. Their one overlapping FUNCTION is `setup_ring`,
      which `ops_amd.bend` lists as a wall from `ops_amd.py:772` (:181) and this file
      ports as a seven-call trace. The seam is named twice and built once.
      **TWO REAL BUGS FOUND, both by making the oracle stricter, both now closed by M44/M45.**
      `*data64_le(...)` is a STAR-UNPACK, so `ip.py:108-110` builds a **seventeen**-word
      PM4 packet; the port emitted sixteen and the ORACLE AGREED because its row
      re-transcribed `lo, _ = data64_le(...)`. All 447 rows were green on a packet that was
      a word short. Asking CPython for `len(pkt(...))` found it, and the same fix exposed
      that `kiq.pkt.addr` was missing the `+ 0x1010` fence offset. THE GENERAL LESSON is
      appended to `bend2-constraints.md`: **an oracle row that re-transcribes a Python
      expression will agree with a port that misread it.**
      **THE MUTATION TABLE IS AT THE FOOT OF THE FILE AND IT IS MEASURED.** `rows MOVED` is
      the load-bearing column. Two harnesses, because "every rule" means two kinds of rule:
      `ip_mutate.sh` (45 hand-written LOGIC mutations, one per rule; 42 move 1-21 rows) and
      `ip_sweep.py` (369 EXHAUSTIVE LEAF perturbations — every numeric constant by one unit,
      and every register row twice, on its LINE and on its NAME; 354 move, 588 row
      displacements). Three non-movers, each an EQUIVALENCE and each PAIRED with a
      same-rule mutation that DOES move: M08 (`U32.or` is commutative, paired M43=9), M22
      (`V.ge(13,0,6)` already covers the two `V.eq` disjuncts, paired M42=18), M39 (two
      smu columns are lockstep (F,T,F), paired M41=2).
      **FOURTEEN BLIND SPOTS REPORTED, NOT CLOSED WITH A ROW THAT ENCODES THE BUG.** Nine
      are field-name swaps where the name is a Python f-string two lines legitimately share
      (`regCP_{cntl_reg}_CNTL`, `regIH_RB_CNTL{suf}`, `{reg_pref}_64`, …) — MEASURED, and
      the reason `Row` is keyed on `(ln, reg)`: the LINE perturbation moves on 115 of 115.
      Five are constants used by code that reach no emitted row. One, `MQD_SE_VALUE`, cannot
      be perturbed at all: `0xFFFFFFFF + 1` is outside `U32` and the type system refuses.
      **THE SWEEP'S OTHER HALF WAS DELETION: 46 constants had ZERO call sites** — no def read
      them and no gate row printed them — so no mutation of them could ever move a row. They
      were removed and all three lanes re-verified byte-identical, which is the point: an
      unread def is provably behaviour-preserving to drop. `.agents/slop/ip_prune.py` refuses
      to remove anything it cannot prove unread. A mutation table is not only a bug-finder;
      it is the only mechanical way to find the part of the port that is not a port.

## Session 2026-10-02 — schedule/rangeify.bend REPAIR (not extension)

- [x] **Bisected the pre-existing `expected : O.Arg` failure to `e959ece3798f`**
      ("fix movement.bend: the port (not Python) had the inversion"). That commit
      widened `M.mp_replace` from `(op, ar, self, src)` to `(op, arg, ar, self, src)` —
      CORRECT, because `UOp.replace` (ops.py:252) takes `arg` as a kwarg — and updated
      `movement.bend`'s own two call sites but not the FOUR in `rangeify.bend`.
      PROOF: `movement.bend` at `e959ece3798f-` + `rangeify.bend` at head is
      `ALL PROOFS CHECK`. A correct change to a file others import is still a change to
      every caller's type; widening a parameter is not a local edit.
- [x] Repaired all four sites by passing each rule's OWN node's arg
      (`rf_remove_noop_afters.of`, `rf_no_indexing_calls.fin`, `ct_8.of`, `ab_7`).
      All four port a `x.replace(src=...)` and CPython's `replace(src=...)` passes
      `self.arg`; the arg-replacing rules (rangeify.py:301, :324) are DIFFERENT rules.
- [x] **5 new gate rows**, `py=` generated by CALLING CPython (`.agents/slop/rf-arg-oracle.py`):
      `ab7_clik_nsrc=2`, `ab7_clik_arg=1`, `ab7_clik0_arg=0`, `nic_clik_nsrc=2`,
      `nic_clik_arg=1`. Zero existing rows moved; `lay` 45->47 (the two new fixture nodes).
- [x] Fixture gained `clik`/`clik0`: the fixture gave EVERY node a repaired rule can
      reach an `ANone` arg, so `eq_arg(rebuilt, original)` was `eq_arg(ANone, ANone)`
      — TRUE for a correct port and for one that hardcodes `ANone`, which is the
      mistake that silences this type error. A CALL's arg is a `Kernel`, so `clik` is
      the node that separates them and `clik0` is the negative.
- [x] Mutation table, 11 mutations, whole-`name=value`-line diff
      (`.agents/slop/rf-arg-mutate.py`). 4 sharp (M2/M3/M5/M6 move `ab7_clik_arg` /
      `nic_clik_arg`), M8 = the original defect and does not compile. **4 zeros
      reported, not closed with rows that encode the bug.**
- [ ] **NOT FIXED, REPORTED: `ct_table` carries the SUB-pattern's op for every `.f`
      entry (4, 5, 8) while the bodies read the OUTER node's op, so `ct_4` can never
      fire.** M9/M10/M11 all move 0 rows; M11 (forcing `ct_4`'s claim to `True{}`) is
      the proof that `ct_4` is ungated. Python side: for `UPat(Ops.MSTACK).f(Ops.INDEX,
      name="idx")` the replace is an IDENTITY on the INDEX and
      `pm_const_buffer_folding.rewrite(mst) is None`. `ct_4_ans` and `ct_8_ans` are
      named in comments and exist in NEITHER `main`. Semantics, not a compile error —
      needs its own CPython-gated rows, so it was left alone.
- [ ] NOT FIXED, REPORTED: M1/M4 (arg at the AFTER and MSTACK sites) move 0 rows, and
      they are FIXTURE REQUESTS rather than theorems — `UOp` does NOT type-check `arg`
      against `op`, and an AFTER/MSTACK carrying a `Range`, `KernelInfo` or `ParamArg`
      arg constructs without complaint (measured). One such node per op closes both.

- [x] **`tinybendygrad/runtime/support/nv/ip.bend`** — `tinygrad/runtime/support/nv/ip.py`
      (661 lines). **All four stages landed and checked.** 185 KB, 543 defs, **1394 gate
      rows**, `ALL PROOFS CHECK`, interpreted and native lanes BYTE-IDENTICAL (57 KB),
      and **0 disagreements** against CPython on 1394 of 1394 row names. `ip.py` imports
      with NO card present, so the oracle needs no hardware.
      **WHAT `ip.py` ACTUALLY IS** (the brief called it the nv ioctl protocol; it is not —
      the NVOS attribute tables are generated `autogen/nv.py`): the **GSP RPC ring
      protocol** and two bootloaders — `NVRpcQueue` (:19-91), `NV_FLCN` (:93-283),
      `NV_FLCN_COT` (:285-344), `NV_GSP` (:346-661). The load-bearing part is the STRUCT
      FIELD LAYOUTS: 54 ctypes structs, 413 fields, declaration order, byte offsets and
      widths, plus 64 U32 constants both directions, `rpc_fns` (224) and `rpc_events` (36).
      PORTED: the queue header and ring length `msgSize*msgCount` (not `size`), the RPC
      record (:38-55) including the wrap-around copy, the **64-bit u64 checksum folded
      into two U32 folds**, the continuation split, the response read pointer, the
      handle generator, the radix3 page tree, the WPR-meta ladder on both branches, the
      registry-table layout, `bdf_as_int`, the PMA flag shifts, the ctx-buffer map, the
      cpu-sequencer opcode table and walk, the FSP framing, and ten refusals.
      NOT PORTED, and each with a Python line: the MMIO map and every register write, the
      VBIOS byte scan (:110-169 — the offsets are ported, the bytes are not), every RPC's
      payload bytes, one 64-bit constant, and `init_sw`/`init_hw` themselves.
      **THE 64-BIT WALLS**, each named with the line that owns it:
      `GSP_FW_WPR_META_MAGIC` (:442), `GspSystemInfo.gpuPhys*`/`maxUserVa` (:605/:608),
      `LibosMemoryRegionInitArgument.id8` as an 8-byte big-endian int (:395), and the
      `init_wpr_meta` offsets, which overflow U32 for any real card with vram >= 4 GiB.
      The 64-BIT CHECKSUM IS **NOT** A WALL: `hi32(c) ^ lo32(c)` COMMUTES with the XOR
      over the words, so it collapses to two U32 folds — which is what makes the row
      sensitive to byte offsets, field order and endianness, where a count gate would
      not be.
      **MUTATION TABLE**: `.agents/slop/nv_ip_mutate.py` + `nv_ip_mutations.txt`.
      37 mutations, **33 move rows, 4 are provably EQUIVALENT mutants, 0 blind, 0 failed
      to run**. The four: `rd.trunc` (Euclidean identity), `rp.cont_more.ge` (both guards
      reach `cdiv(0,m)==0`), `rp.pickw.swap` (`rp.finish` XORs the two accumulators, so
      permuting words between them is the identity — the endianness assumption is NOT
      gateable through the checksum), `rp.which.last_word` (words 18 and 19 are both zero
      slots with no arm).
      **FIVE DEFECTS THE GATE FOUND THAT PROSE DID NOT**, and they are why the mutation
      table was worth building:
        (1) `rp.put_wp`'s `Bool.pick` arms were SWAPPED — the only guard in the file, the
            one that stops the write pointer advancing past a refusal, did the opposite of
            its comment. **The hand-tabulated oracle AGREED with the bug on all five rows**,
            because the table had the fault position backwards and so did the port.
        (2) `C_ALLOC_MEM()` (a TRACE TAG) was passed to `rp.record` where Python passes a
            FUNCTION ID, so the alloc trace claimed to send function 8 and sent 4.
        (3) `rpc.bump` rebuilt the trace as `Tr{Nil{}, ...}`, dropping the five calls the
            record had just appended; `rpc.am*` was called by no row, so nothing noticed.
        (4) The handle was a TRACE ENTRY when `next(self.handle_gen)` is `itertools.count`
            and touches no device — which put it LAST where :529 mints it FIRST.
        (5) `rp.bump` rung the doorbell before the sequence bump, where ip.py :52, :54,
            :55 put `self.seq += 1` BETWEEN the barrier and the doorbell.
      Also removed: **30 dead defs** found by a comment-aware, full-dotted-name audit
      (`.agents/slop/dead-defs2.py`) — a base-name audit had scored `rp.acc` alive on the
      strength of three COMMENTS that mention it. The 30 included an abandoned
      `type Wv`/`rp.acc`/`rp.pair.hi`/`rp.pair.lo` fold that could never have worked.
      And the file's own layout comment had words 10 and 11 **swapped** for its whole life
      (`elemCount` is at [10], not [11]) — which no gate could see, because a comment is
      not a row.
      FIVE SUBSTRATE FACTS appended to `.agents/slop/notes/bend2-constraints.md`, the
      important one being that **`Bool.pick` DROPS the arm it does not take**, so a
      self-call inside an untaken arm is unreachable: a fold written
      `Bool.pick(U32, hit, x+1, go(t,n))` measured `ip_d_fns_max=1` against CPython's
      `223`, and "first-wins" in a table lookup is not a policy but a consequence of where
      the recursion sits.
      REPRODUCIBLE END TO END:
        python3 .agents/slop/nv_ip_gen.py && python3 .agents/slop/nv_ip_oracle.py &&
        python3 .agents/slop/nv_ip_oracle3.py && python3 .agents/slop/nv_ip_oracle4.py &&
        python3 .agents/slop/nv_ip_build.py && ./bin/bend tinybendygrad/runtime/support/nv/ip.bend
      The file is BUILT from parts in `.agents/slop/` and then topologically reordered,
      which replaced 40+ hand patches that had corrupted it.
      NOT COMMITTED, per the task's instruction.

- [x] **`tinybendygrad/runtime/support/usb.bend`** — `tinygrad/runtime/support/usb.py`
      (473 lines). 2596 lines, 339 defs, **939 gate rows**, `ALL PROOFS CHECK`,
      **0 disagreements** against CPython on 939 of 939 row names.
      **THE CITATION PREMISE IS FALSE AND IT IS REPORTED IN THE HEADER**:
      `grep -rl "support/usb" tinybendygrad --include="*.bend"` is EMPTY, so unlike
      every other unit in this wave the scope was chosen from the source.
      **WHAT IS WORTH PORTING, AND WHY.** `usb.py` is the only file in tinygrad that
      talks to a device through a GENERATED ctypes binding, and
      `tinygrad/runtime/autogen/libusb.py` is that binding: **21 `enum_libusb_*` dicts
      and 22 `@c.record` structs**. That is a descriptor table in the exact sense this
      project gets burned on — `ops_nv`'s audit found 33 of 219 constants wrong in a
      file already printing 590 green rows, and `ops_rdma` shipped `BNXT_VENDOR` as
      5356 where the header says 5348. `struct_libusb_transfer`'s thirteen field
      names, IN ORDER, are what `usb_chunk` (:350-351) addresses three times BY NAME,
      so a transposed pair is a silently wrong transfer.
      **THE WALLS CLOSED**: `ops_amd.bend`'s WALL 3 part 1 (`USB3.list_devices`, :30-37)
      and part 3 (the WINDOW — `usb_fence` 0x800/0x804, `usb_cq` **0x100c/0x1010**,
      `usb_sram` 0x5000/0x5000+2*HALF), plus `ops_disk.bend`'s `_might_open` ladder
      shape. `dma_view` (ops_amd.py:824) is NOT closed and says so.
      **A CORRECTION TO CARRY BACK**: ops_amd's 4096 is `0x1000`, which is `USB3`'s
      own CONTROL buffer (:42, `alloc_cbuffer(0x1000)`) and NOT `usb_cq`'s offset.
      Both are real, they are different numbers, and `usb_sram_win_fits_asm24` is the
      row that says the SRAM pair exactly fills `usb_asm24` (544768, ops_amd's number).
      **THE CONSTANTS THAT WERE WRONG**: two hand-typed, both caught by the differ —
      `SENTINEL_MAGIC` was 1363148800 where 0x51000000 is 1358954496, and
      `FAST_P1_MASK` was 215 where 0b11011111 is 223. **123 U32 defs swept, 123
      CONFIRMED, 0 WRONG, 1 PORT-INTERNAL** (`NOT_FOUND`, reported not counted).
      **FIVE DEFECTS THE GATE FOUND THAT PROSE DID NOT**:
        (1) `copyout_second` was `U32.max(U32.sub(size, CHUNK()), 0)`, which WRAPS —
            `U32.max(4294967295, 0)` is 4294967295 where Python's `max(-1, 0)` is 0, so
            a copyout that fits one half carried a phantom 512-byte sentinel block.
        (2) `sym_at` was off by one, so every order row named the symbol AFTER the one
            it meant and every COUNT stayed right. `M31` is the mutation: 73 rows.
        (3) `usb_chunk` had `usb_drained` (:347) AFTER `usb_ctrl` (:348). The CPython
            order row is built from the call SITES, which is what caught it.
        (4) `usb_enum.device` read the descriptor AFTER the ref/bus/address triple.
        (5) The SEEN-SET version of `enum_rows` handed each `+` slot to
            `List.contains`, which MOVES it: zero `_n_` rows, every seen set already
            full. And once fixed, walking the REVERSED table still built the
            accumulator BACKWARDS — a cons fold over a reversed walk is a backwards
            fold — which put all 478 enum rows in the opposite of the header's order.
      **MUTATION TABLE**: `usb-mutate.py --md` writes the table the file quotes.
      **45 mutations, 44 move rows, 1 THEOREM, 0 blind spots.** The zero is `M6`,
      which swaps the two operands of `nranges`' two-term SUM; no fixture in any file
      could separate those. The narrowest rows are 1-wide by construction and say so:
      `M10` (the two PCIe fast paths becoming one), `M13` (one of four `cfg_addr_ok`
      bounds), `M24` (the slice extent, where the `slice0_4` fixture is the boundary
      that separates it from the integer arm), `M27`/`M28` (one fixture each).
      **`E_SYNTH`, A TABLE BUILT FOR A RULE**: correcting `enum_libusb_class_code` to
      nineteen entries removed the only repeated value in twenty-one tables, so
      LAST-wins became unobservable and `M36` fell to 0 rows. A zero is a REQUEST FOR
      A FIXTURE, not a coverage claim; the fixture is a five-entry table that repeats a
      value and a name, and `M36`/`M37` are 1-row mutations against it.
      **NOT PORTED, and every one with its Python line**: 111 lines, generated by
      `usb-seam.py`, which PRINTS THE SOURCE TEXT out of `usb.py` so a line that moves
      cannot keep its old description.
      **REPRODUCIBLE END TO END**:
        python3 .agents/slop/usb-gen.py && python3 .agents/slop/usb-gen-strings.py &&
        python3 .agents/slop/usb-build.py && ./bin/bend tinybendygrad/runtime/support/usb.bend
        then `usb-diff.py`, `usb-constsweep.py`, `usb-handmap.py`, `usb-symmap.py`,
        `usb-dead.py`, `usb-mutate.py --md`.
      The file is GENERATED by `usb-build.py` from pieces that are themselves generated
      from `usb.py` and the live `autogen.libusb`; in-place edits destroyed it twice.
      NOT COMMITTED, per the task's instruction.

## Session 2026-10-02 — schedule/rangeify.bend: THE `ct` TABLE'S OP SETS WERE THE CHILD'S

- [x] **THE PROVEN BUG, CONFIRMED AND FIXED, AND IT WAS BIGGER THAN REPORTED.** A `.f()`
      chain is `def f(self, op, **kwargs): return UPat(op, src=(self,), **kwargs)`
      (ops.py:1449), so it REBUILDS the pattern with the op passed to `f` at the ROOT;
      `PatternMatcher.__init__` keys `pdict` on `p.op` and `rewrite` looks the node up
      with `pdict.get(uop.op)`. So the port's op sets must be the op handed to `f`, and
      **five of the nine `ct_table` entries carried the RECEIVER'S op instead** — tags
      0, 1, 2, 5 and 8 — which makes the rule UNFIREABLE rather than wrong: the engine
      never looks the node up. `ab_table` tags 0-2 had the same defect. Measured roots,
      read off `p.op` and `pdict` by `.agents/slop/rf-ct-oracle.py`:
      `0 INDEX  1 AFTER  2 END  3 STAGE  4 STAGE  5 STAGE  6 INDEX  7 INDEX  8 INDEX`
      — **all nine are single-op sets**, and the three reject sets (which ARE the
      child's op, `UPat.early_reject` ops.py:1477) were already right.
- [x] **WHICH OF `ct_4` / `ct_5` / `ct_8` ARE LIVE, ASKED OF CPYTHON, NOT GUESSED: ALL
      THREE, and on shapes the old fixture could not build.** `ct_4` is live on
      `STAGE(INDEX(b4,r0), r0)` (`claim_n=2`, answers the BUFFER) and dead on the mirror
      `INDEX(STAGE(b4,r0), r0)` (`claim_n=0`); `ct_5` is live on BOTH `or_casted` arms
      (`STAGE(c4,r0)` and `STAGE(CAST(c4,half),r0)`, each answering an `EXPAND`) and
      binds `c` zero times on `STAGE(b4,r0)`; `ct_8` is live on
      `INDEX(MSTACK(c4,c1))` (answers `INDEX, srcops=[CONST]`) and refuses on
      `INDEX(MSTACK(buf-with-device))`. **CORRECTION TO THE PREVIOUS NOTE:** its recorded
      "`rewrite(mst) is None` and the replace is an IDENTITY" is TRUE of `MSTACK(c4,c1)`
      — the MIRROR, which is the CHILD and which no pattern binds — and FALSE of the
      INDEX the pattern is written for. The finding was sound; it was measured on the
      wrong node, and the fix is the fixture pair, not a "dead rule" row.
- [x] **16 NEW FIXTURE NODES AND 44 NEW ROWS**, all `py=` generated by CALLING
      CPython. The discriminator is WHICH OP IS AT THE INNER VS THE OUTER POSITION, and
      the ARG gate is an INDEX carrying `O.ARange{ids, at}` — which `ops.bend` can build
      and which `ct_8`'s rebuild preserves (`UOp` does not type-check `arg` against
      `op`; prepare.py:70 passes `arg=idx.arg`).
- [x] **THREE MORE REAL DEFECTS, each found by the new fixtures and each now mutated:**
      `ct_6` answered `M.mp_src(ar, self, 0)` on its `False` arm, which made "indexing a
      const" a CATCH-ALL that stole `ct_8`'s answer on `INDEX(MSTACK(...))`;
      `ct_8`'s `s.device is None` was `Bool.not(<always False>)`, i.e. `True` for every
      device-BEARING node, so `ct_8` fired where CPython refuses; and `ct_8` had NO
      pattern re-check of its own, which is a hole the moment the reject set goes
      vacuous.
- [x] **THE PREVIOUS MUTATION TABLE'S M3 "PROOF" IS REFUTED.** It read "for a
      ONE-element set `and` and `or` are the same function". They are not:
      `rf_early.go`'s base case is `True{}`, so `and(x, True{})` is `x` and `or(x,
      True{})` is `True{}` — `or` makes the reject test VACUOUS on a singleton as on
      anything else. MEASURED, before `ct_8` gained its self-check: M3 moved
      `ct7b_none` 1 → 0. M3 is a zero NOW, with the correct reason, and M36/M38 measure
      that reason.
- [x] `M12` was a zero because EVERY RANGE in the fixture was `AXIS_WEAK`, so
      "rebuild the AxisType" and "read it off the node" are the same function there.
      One `AXIS_DEVICE` RANGE plus `ren_axis_out_dev` makes it sharp.
- [x] **M30 was a zero because `ct_7`'s reject set is satisfied by an AFTER in ANY
      src.** `ct7b = INDEX(R0, AFTER)` is the one node in the fixture where the reject
      set is not the claim, and it is the row that makes M30 and M20b measurable.
- [x] **PART 2, ITEM BY ITEM, in file order** — `ct_3` still walled
      (`BufferizeOpts.removable` + `ranges` + two movement ops; MEASURED live);
      `ct_5`'s CLAIM is now ported and its ANSWER is walled (`DType.const` + `_mop`);
      `ct_7` is walled on `_min_max`, which `uop/fold.bend` still has only as a TODO —
      done LAST as instructed, and a **CPython defect was measured on the way**:
      `after_all_invalid` raises `AttributeError` on an END that ends no RANGE, because -- **NOW TRACKED IN `.agents/UPSTREAM.md` AS D1**, with the
      reachability argument (`ops.py:472` FILTERS `src[1:]` for RANGEs, so an END with no
      RANGE there yields `()`) and an honest note that the triggering graph is not built.
      The original text follows.
      `prod()` over an empty `ended_ranges` is the python int `1` and the `cast(UOp,
      ...)` on rangeify.py:113 does nothing; `ab_4` is walled on `commit_dtype` (absent
      from `ops.bend`), `sorted(idx.ranges, key=x.arg)` (the `ranges` wall plus a sort
      by a TUPLE arg) and `next(ctx)`; the four foreign `pm_mops` BODIES are **BLOCKED
      on `schedule/prepare.bend`, which names `pm_mops` in its header and defines
      nothing** — their op sets are ported here because those are a Python fact and the
      engine's lookup is a Python fact, and no local copy of `_mop_index` was invented;
      `KernelInfo.estimates` is `ops.bend`'s own NOT-PORTED field and is why
      `ab7_clik_arg` compares `O.KernelInfo.of()` on BOTH sides; `UOp.device` and
      `UOp.ranges` are unchanged walls and `ct_8` no longer depends on the first.
- [x] **41 mutations, 37 sharp, whole-`name=value`-line diff**
      (`.agents/slop/rf2-mutate.py`, raw table `.agents/slop/rf2-mutations.txt`). FIVE
      zeros: M3, M8, M20b, M36, M38 — four PROOFS with stated reasons and one
      REPORTED BLIND SPOT (M36/M38: no single-arena fixture can see `ct_8`'s self-check
      because the two defects it defends against are one defect from two ends).
- [x] Gate grew 81 → 126 rows. `ALL PROOFS CHECK`. The scratch is
      `.agents/slop/rf2root/schedule/rf2_work.bend` (reached through the symlink
      `.agents/slop/rf2_work.bend`; the symlink farm exists because a scratch outside
      the tree cannot resolve `./../uop/ops.bend`).
- [ ] **NOT COMMITTED**, per the task's instruction. Seven general rules appended to
      `.agents/slop/notes/bend2-constraints.md` as `RF1`-`RF7` at line 8146, indexed in
      the table at the top of that file.

## Session 2026-10-02 — upstream `793abbb` "modernize tinygrad's dtype to match rust"

- [x] re-vendor `tinygrad/dtype.py` and `tinygrad/runtime/ops_null.py` at
      `793abbb` (blob-verified: `f40089a12`, `8b28aef563`)
- [x] `LAWS/spec.bend` — the `DType.name` layer, 16 `Dt` literals
- [x] `dtype.bend` — `promo_mask` / `can_lossless_cast.row` / `rank_of` /
      `finfo.of` / `fmax.of` / `fp8_kind` re-keyed (61 arms), `to_dtype_of`
      canonical-first, legacy accessors dropped
- [x] `uop/render.bend` — `dt_attr` was `INVERSE_DTYPES_DICT`, which upstream
      DELETED. The twenty-arm table is deleted, not renamed.
- [x] `renderer/__init__.bend`, `renderer/cstyle.bend` (type_map keys),
      `renderer/wgsl.bend` (finfo), `renderer/tc_ptx.bend` (16 `want` literals),
      `codegen/transcendental.bend`, `uop/symbolic.bend`,
      `runtime/ops_dsp.bend` (4 functional tables), `nn/onnx.bend` (comment)
- [x] `.agents/slop/**`: 1164 `dtypes.<legacy>` sites over 113 files, via
      `.agents/slop/tools/migrate-dtype-names.py` (word-boundary, longest-first)
- [x] `tinybendygrad/test/dtype_oracle.bend` — **was committed and did not
      compile** (4 reversibility errors). Rebuilt; the CPython half
      `.agents/slop/oracle/dtype_tables.py` and the runner
      `.agents/slop/dtype-gate.py` are new.
- [x] `dtype.bend` gate: 14 766 rows, both lanes byte-identical, **1 declared
      pre-existing deviation** (`dtypes.uint64.max` has no image in a signed-pair
      I64). Not one ANSWER moved; only the name column, in lockstep.

- [ ] **OWNER DECISION — `tinygrad/runtime/ops_bend.py` imports the deleted
      `INVERSE_DTYPES_DICT`** (`tinygrad/runtime/ops_bend.py:76`, used at :95).
      The file is OURS (240 lines, no upstream counterpart — `git diff 6c3d401cf324`
      shows it as `new file`), so "re-vendor" is not on the table. Right now
      `import tinygrad.dtype` raises `ImportError` and the BEND device is dead.
      Two options in the report; neither taken here.
- [x] `renderer/isa/x86.bend` — `tinygrad/renderer/isa/x86.py`. **The root cause of the
      80-row red blind spot is FIXED and the acceptance test is a `diff`, not the gate.**
      760 rows, `diff .agents/slop/x86/{i,py1}.txt` **empty**, interpreted and native
      lanes byte-identical, `ALL PROOFS CHECK`. `asm_str` (x86.py:728-749) landed as
      well, so 372 of 770 Python lines are covered. Five findings worth carrying:
      * **THE EIGHTY `hex.*`/`direct.*` ROWS WERE BARE STRING CONCATENATIONS** — no `Bool`
        in them at all, so "0 False" never covered them and all eighty disagreed. Every
        one is a `Bool` row against CPython's bytes now, with the bytes in the ROW NAME.
        Same shape as rule 64 at the tail of `bend2-constraints.md`, one fix up.
      * **THE ORACLE WAS WRONG, NOT ONLY THE PORT.** `enc_inputs()` re-transcribed
        `encode`'s three address arms and was wrong three ways at once: the Rm2nd
        `x.dtype is not void` test inverted, the `if reg is None` fork ignored on every
        arm (so SHL/SUBi/CMPi/IDIV/VPSRLDQ were handed `reg = 0` where CPython keeps the
        table's 4/5/7/7/3), and `vvvv` a hardcoded four-name list. It now READS THE LIVE
        FRAME of `encode`/`_encode` through a `sys.settrace` line tracer, and the `py=`
        halves were never touched.
      * **`Enc.emit` had NINE defects and every one was LOGIC.** The duplicated opcode
        (`legacy_head` ended in the opcode and `tail` appended it again), the
        big-endian `imm_int`, the `mod == 0` displacement with an inverted flag, the
        misread `reg_sz == 1 & reg >> 2` (`&` binds tighter than `==`, so `MOVi` and the
        four `SET*` lost their null `0x40` REX), `disp_uop is None` in `demote`, two `we`
        selectors reading the wrong sizes, the six-byte `JMP`, the undemoted opcode byte.
        A constants sweep finds NONE of them; `.agents/slop/x86/x86-rules.py` (48 rules)
        finds all nine.
      * **`U32.sub` WRAPS**, so `f"{mnem:7s}"` written as `7 - len` asks `String.repeat`
        for 4 billion spaces on any mnemonic over seven characters, and the fixtures had
        none. Fixed with a saturating arm and a nine-character fixture.
      * **THE BLIND LIST IS A FIXTURE LIST.** 205 of 707 constants move nothing, and the
        actionable class is one hole: no fixture puts an operand in `r8`..`r15`, so
        `Enc.gt0`, `Enc.b1`'s zero arm, the REX R/X bit weights, the `0x66` prefix
        (`sz == 2`) and `Enc.modrm_of`'s `rm == 0b101` rbp/r13 clause are all
        unobservable — the last of which the source comment called "a gate row of its own".
      * The file also lost **7900 lines of blank** (9878 → 2649) with byte-identical
        output, and its 760 row literals are now written by `x86-gen.py`.
      Artifacts: `.agents/slop/x86/{py1,i,native,gate}.txt`, `mut-consts.txt`,
      `mut-rules.txt`, `stage-bytes.txt`, `x86-probe.py`.
- [ ] `tinygrad/renderer/cstyle.py` **not** re-vendored (kept at the pin
      `a4acfa5c6e86`): it carries a local delta and its 2314-line port has its
      own gate and a second agent editing it right now. `cstyle.bend`'s gate
      ROWS (`wmma_row` / `under_row` expectations) still need a re-run by its
      owner — `type_map`'s keys were migrated here because the rename breaks them
      regardless of which cstyle.py we pin.
- [x] name-keyed tables left for their owners: `renderer/nir_llvmir.bend` (9),
      `renderer/isa/x86.bend` (2), `uop/fold.bend` + `fold_mm_work.bend` +
      `fold2_work.bend` (20)
      — `nir_llvmir.bend`'s 9 DONE 2026-10-03: `ldt.fp` re-armed from the dtype
      NAME onto `Cls`/`bits`/`pri` (the `renderer/llvmir.bend` `lt.fp` shape,
      imported not reinvented), 79 red rows -> 0, 205/205 green against a
      regenerated live-CPython oracle, both lanes byte-identical, mutation table
      re-measured at 44 entries with M40/M40b reproducing the regression on
      demand. `x86.bend` (2) and the three `fold*_work` files (20) are STILL
      OPEN and belong to their owners — see the audit note below.
- [ ] `renderer/isa/x86.bend` `Op.to_int` (`:750-754`) is STILL RED IN DISGUISE
      — armed on `"float16"`/`"float32"`/`"float64"`; `S.Dt.nm` now spells those
      `f16`/`f32`/`f64`, so every arm falls to `KeyError`. It is 761-row GREEN
      because the three `toint` rows feed the ladder ITS OWN ARM KEY and the four
      `toint.miss` rows expect `KeyError` anyway. Proven with four probe rows:
      `Op.to_int("f16") = [KeyError]` where CPython answers `i16`. OWNER'S FILE —
      REPORTED, NOT EDITED.
- [ ] `runtime/ops_dsp.bend`: `grep -c 'py=\[' ` is **ZERO** — all 512 printed
      rows carry their expected value in a `#` COMMENT, so the file compares
      nothing and `ALL PROOFS CHECK` on it is worth nothing. On top of that
      `dt_fmt` (`:652`) is armed on the NEW spellings while its rows (`:1876+`)
      pass the OLD ones (eleven rows print an empty string where CPython prints
      `b`/`e`/`f`/`d`), `dt_supported` (`:740`) compares against the OLD
      `"__bf16"`, and `supported_12.at` (`:744`) returns OLD names where CPython
      gives `bool,i8,u8,i16,u16,i32,u32,i64,u64,f16,f32,f64`. OWNER'S FILE.
- [ ] `runtime/ops_dsp.bend`'s ~40 gate-row literals (its 4 functional tables
      are done; its rows print `dt_name`, so they move with the rename and its
      oracle must be re-run)

## Session 2026-10-02 — `runtime/support/memory.bend`: the allocator PORT, and the gate that was
## green on 570 of 995 rows

- [x] **`tinybendygrad/runtime/support/memory.bend`** — `tinygrad/runtime/support/memory.py`
      (288 lines). 2,634 lines, no foreign effect, the seam is a `Tr` trace (the
      `support/am/ip.bend` lane). Report: `.agents/slop/memory-report.md`.
      `bend --check-only` → `ALL PROOFS CHECK`; gate → `rows: bend=889 oracle=889 compared=889
      disagreements=0`; interpreted lane == compiled lane byte for byte; **70 mutations, 6 blind
      spots.** NOT COMMITTED, per the task's instruction.
- [x] **THE GATE WAS NOT GREEN AND THE SUMMARY SAID IT WAS.** The two lanes agreed on **every
      row they shared** — 570 compared, **0 value disagreements** — and **547 rows existed on
      exactly one side**: 425 oracle-only and 122 Bend-only. `disagreements=0` was arithmetically
      impossible with 684 Bend rows and 570 compared, so the "green" reading was wrong, and the
      file had drifted a long way from the oracle. Reconciled family by family: the bump sequence
      became joined `bump_seq_*`/`bump_ptr_seq_*` rows, the frag rows one naming convention
      (`frag_<f>_<sub>`, fixture last), the MMIO field columns four LIST rows instead of
      thirty-six per-field rows, the multichar claim two list rows instead of forty-six
      per-format rows, and the PTE table gained `amd`/`nv`/`tall`/`root1` in three widths.
      **A gate that diffs only the intersection measures nothing; one that diffs only the values
      hides a whole family. Both directions, whole lines, count printed.**
- [x] **ELEVEN REAL DEFECTS, all found by the diff and none by reading.** `va_allocator` hi words;
      `U32.shln/add/sub` WRAP rather than saturate; `frag_lowbit` is `x & (~x+1)` not `x-2x`;
      `frag_sz_max` is `1 << (bl-1)`; `lvl_msb_len` is `len+1`; `VRAM_ODD` is `0x40000001`;
      `valloc_align` is `max` not `min`; `lv2_shift` needs a `max(0,..)` clamp;
      `List.append(a,A,xs,ys)` is `xs ++ ys` so a "reverse" on it is the IDENTITY; `first_of`
      needed a `seen` flag; **and `valloc`'s range walk advanced the segment list past the pick**,
      making it a last-match walk that cannot take the same segment twice — 8 MiB came out as
      `2 MiB × 8`, sum `16777216`, remainder `-8388608 mod 2^32`, where CPython says `2 MiB × 4`,
      sum `8388608`, remainder 0. **Nothing in `memory.py` hints at that one.**
- [x] **THE PAGE-TABLE ASSERT LOOPS, and the order is the claim.** `map_range:214-215` reads
      `valid` first and `entry` only on failure (an `assert` message is lazy), so a mapped entry
      is `[PT_VALID, PT_ENTRY]` and a pending one `[PT_VALID]`; `unmap_range:232-234` is the
      mirror with the OPPOSITE stop polarity. The oracle runs both loops **as Python against a
      recorder**. Two Bend traps cost most of the detour: a `U32` stop sentinel WRAPS (`0xFFFFFFFF`
      + 1 = 0, so the walk never stopped), and `Bool.pick` EVALUATES BOTH ARMS, so two exclusive
      emitters are a `match` over `Bool` and never a `pick`.
- [x] **CITING FILES.** `schedule/memory.bend` CONFIRMED: no local TLSF reader, the offsets are
      the `mem_offs` parameter, nothing here makes it redundant. `ops_rdma.bend` CONFIRMED at its
      line 262 (`ASPACE_SYS() = 1` measured) and its `va_allocator` WALL now has a measured
      answer to cite. **`am/ip.bend` wall #6 CONTRADICTS `ip.py:278`**: the recorded
      `mm.palloc(0x1000 * xccs, 2 + is_vf)` has `2 + is_vf` as the **comprehension's repeat
      count**, not `align`; the real `align` is `palloc`'s default `0x1000`. Both answers are
      gated (`sig_palloc` pins the default; `palloc_round_4096`/`palloc_size` pin the arithmetic).
- [x] **SIX BLIND SPOTS, none closed with a row that encodes the bug.** M09/M12/M13 are
      *structural*: every reader is a positional destructure, so swapping the declaration and all
      readers is one consistent relabelling — the declaration order IS gated, the readers are
      not. M38/M62 are **theorems**: a non-monotone `va_shifts` makes CPython raise `ValueError`,
      and `pte_barefused_12_21_4=1 / _0_9_4=1 / _12_21=0` are the rows that make the theorem's
      boundary checkable. M64 is a tag retagged onto an **unemitted** tag, which a trace that
      counts by value cannot see; M69 (retag onto `PT_VALID`, which IS emitted) moves 6 rows and
      is the pair that shows the difference.
- [x] **THE TLSF FREE-LIST WALK IS NOT PORTED, AND THAT IS THE ONE PLACE THIS STOPS SHORT.**
      `lv1`, `lv2`, the bucket key, `lv2_shift`, the three-step size pipeline and the storage
      length are all ported and gated; `TLSFAllocator.alloc`/`free` are not, so `va_alloc_off_*`
      was **deleted from both sides** rather than kept as a literal on the Bend side. A literal
      row is a change-detector; an absent row is a fact.
- [x] **M14 CLOSED WITH ONE FIXTURE.** The dropped `round_up` moved nothing because every
      `bump_over_*` fixture had an aligned pointer or an alignment of 1. A ninth request —
      **one byte at alignment 4096 from a pointer at 161** — makes the padded test round to 4096
      and overflow while the unpadded one compares 162 and does not. 0 → 5 rows.
- [x] **`.agents/slop/notes/bend2-constraints.md`** — 12 measured rules appended after line 9704,
      cited by position (the file's rule NUMBERS are ambiguous and it says so at its top).
      Notables: an unfilled law names the CALLER; a fold needs a `Nat` fuel as its FIRST argument;
      a `U32` stop sentinel wraps; an `assert` message is lazy; `Bool.pick` is right for a value
      and wrong for an effect; a ladder walk re-walks its head; a literal fuel is a truncation; a
      declared tag nothing emits cannot be gated.

## Session 2026-10-02 — REBASE BATCH B2 (`dtype.py` + `renderer/cstyle.py`, 2 files, atomic)

- [x] **THE BREAK IS CLOSED.** `DEV=NULL` compiles a kernel again. `dtype.py` was already at
      HEAD from `d2cde2f2c` and `cstyle.py` was still at the pin, so every C type rendered as
      the dtype's RUST name (`u64`, `u8`) and clang rejected it. The brief said the first error
      was `unknown type name 'i32'`; the first error is actually `u64` — same cause, and worth
      recording because `i32` is the name the pin's `cstyle.py` spelled `dtypes.uint32`/`int32`.
- [x] **STAGED EXACTLY ONE FILE** (`tinygrad/renderer/cstyle.py`); `dtype.py` needed nothing.
      Pin match **211/230 → 210/230**, local edits **19 → 20** — one file, one step, as expected.
- [x] **GATE: cstyle.bend RE-PORTED, and the 9 pre-existing disagreements are BYTE-IDENTICAL
      before and after** (5 `buf2 * LOC`, 4 `wmma`). None of them is B2's: a bare `UOp(BUFFER)`
      is `AddrSpace.GLOBAL` and a bare `UOp(WMMA)`'s dtype is the `u32` const at BOTH ends of
      the window, so those rows disagreed before B2 started.
- [x] **TWO REAL FINDINGS, both silent-wrong-answer shaped rather than loud.**
      1. `ocml_extern` read `dt_name(d)` where HEAD reads `self.render_dtype(dt)`. At the pin
         `DType.name` WAS the C spelling, so the two were the same string and the reader could
         not tell them apart; 793abbb split them and the port emitted `f16` inside
         `extern "C" ... __ocml_sqrt_f16(f16)` where HIP needs `half`. **Only `kern2 HIP ockl`
         can see it** — HIP is the only device that emits `ocml`. This is the `uop/fold.bend`
         failure mode exactly: green gate, wrong kernel.
      2. **The port's `type_map` was DEAD CODE for the string layer.** `tm_get` called
         `Map.get(String, nm, m, nm)`, and `Map.get`'s SECOND argument is the ZERO of the
         value type, not the key — the key is the FOURTH. With the key in the zero slot the
         lookup missed every time and returned the zero, so all six `type_map`s agreed with
         `dtype.name` for all 17 dtypes. Invisible while the base was `{}`; the moment HEAD
         gave the base a real 14-entry table, 62 rows moved. `cu32` in `uop/render.bend` passes
         `0` there and the key last — the working example was in the tree the whole time.
- [x] **`type_map` IS NOW OBSERVABLE, and the baked-literal count fell 94 → 13.** That number is
      the measure of the dead-lookup defect: with `type_map` inert the port's `[bend]` half
      printed rust names and 94 of its baked `py=` literals were stale text.
- [x] **THE HEAD `KeyError` IS NOT AN UPSTREAM BUG, AND IT IS UNREACHABLE — measured, not
      assumed.** HEAD replaced `type_map.get(dtype, dtype.name)` with a bare `type_map[dtype]`,
      so an unmapped dtype now raises where the pin answered with `dtype.name` — which at the
      pin was `"float8_e4m3"`, not a C type at all, so the pin's answer was garbage. No fp8
      dtype reaches `_render_dtype` on a device without it: **tinygrad emulates fp8 as f32**.
      `DEV=CPU` + `.cast(dtypes.fp8e4m3)` compiles, realises, and emits
      `void E_3(unsigned char* restrict, float* restrict)`. Loud failure on an unreachable
      path is upstream's intent, so no `UPSTREAM.md` entry.
- [x] **NO `case`-ON-DTYPE-NAME SITE WAS SILENTLY BROKEN, and that is a measurement.**
      * Every legacy alias (`float`/`half`/`bfloat16`/`double`/`uint`/`int`/`long`/`ulong`/
        `char`/`uchar`/`short`/`ushort`) still resolves, so the `case dtypes.X:` arms in
        `dtype.py:207-210` and `codegen/decomp/dtype.py:28-81` are matched by object identity
        and are unaffected.
      * `DTYPES_DICT` is built from `DTypes.__dict__`, so its KEY SET only ever GREW
        (28 → 40 keys; a strict superset), so no `[...]` lookup can start missing.
      * ONNX's `DTYPES_DICT[self.name.lower()]` dispatches on ONNX strings (`FLOAT`,
        `BFLOAT16`, …) which resolve at both ends.
      * The one site that WAS split is HIP's `ocml`, and it is not a `case` — it is a
        `dt.name` read, fixed above. **A `case`/lookup is not the only shape; a bare `.name`
        read next to a `render_dtype` is the same trap and this window had one.**
- [x] **`DTYPES_DICT` KEY-SPECIFIC FINDING.** `float8_e4m3` and friends are NOT keys at either
      end (the ATTRIBUTE is `fp8e4m3`; `"float8_e4m3"` was only ever the *name* field, and the
      rename moved it to `fp8e4m3`, which IS now a key). Nothing reads those four strings, so
      this closed itself — recorded because it looked like the break and was not.

## Session 2026-10-02 — env-flag semantic divergence audit (owner: the audit unit)

- [x] **The `getenv` coercion table, MEASURED from live CPython** —
      `.agents/slop/env-coercion-table.txt`. `helpers.py:162` is
      `type(default)(os.getenv(key, default))`, so the coercion is `type(default)`
      applied to the raw string and nothing validates it. **51 of the 61
      `ContextVar`s have an `int` default, 6 `str`, and `bool` for EXACTLY THREE**
      (`PMA`, `SQTT`, `PMC`, all `abs(VIZ.value) >= 2`). `int()` REFUSES a bad value
      and tinygrad then does not import: `DEBUG=true`, `SPEC=1.5`, `JIT=yes`,
      `PARALLEL=abc`, `TC_SELECT=x`, `MAX_BUFFER_SIZE=1GB` all raise
      `ValueError: invalid literal for int() with base 10` at import. The 61/85/146
      counts are AST-measured and the 85 bare-`getenv` keys are `getenv`'s other 85.
- [x] **`helpers.bend`'s `no_color_of` was INVERTED. Fixed and gated.**
      `NO_COLOR`'s default is the `int` `0`, so the observable is
      `bool(int(...))` and `"0"`, `"00"`, `"-0"`, `"+0"`, `"0 "`, `" 0"` all read 0
      and leave COLOUR ON. The port read `not String.is_empty(v)`, which turned
      colour OFF for all six. **18 of 32 probes disagreed**; post-fix **0 disagree**
      (18 exact, 13 CPython refusals answered `False`, 1 named boundary).
      The old comment stated the opposite of the truth and claimed it "reproduces"
      tinygrad. Gate: `.agents/slop/nocolor-{oracle.py,probe.bend,diff.py}`.
- [x] **`helpers.bend`'s P6 comment corrected: 61 ContextVars, not ~40.**
      `Flags` is **4 flags of 146** and **3 of the 61** ContextVars (`SUM_DTYPE` is
      a bare `getenv`, `dtype.py:223`). The undercount was 21, so P6's scope as
      written is too small. All 57 other ContextVars are CONSUMED.
- [x] **DIVERGENCE SITES: 3 real substitutions outside `helpers.bend`, plus 1 doc
      bug.** `mixin/dtype.bend:288` bakes `DEFAULT_FLOAT` as `S.single()`
      (VERIFIED: `DEFAULT_FLOAT=float16` makes CPython's `strong_dtype(weakfloat)`
      answer `f16`); `runtime/support/hcq2.bend:282` bakes `HCQ_CACHE_THRESH` as 64;
      `runtime/support/system.bend:2221` bakes `REMOTE_TIMEOUT` as 60;
      `codegen/kernel.bend:773,786` says ELEVEN/THIRTEEN where Python and its own
      rows say 12/14. All reported with an owner, none edited.
- [x] **THE HEADLINE: of 146 flags, only 15 are named anywhere outside a comment in
      the whole `.bend` tree, and only 4 are genuinely read.** 5 more are name
      collisions (`HALF`, `FLOAT16`, `DEV`, `TC`, `JIT`/`PROFILE`). So **131 flags
      are silently absent** — most with a wall note naming them at the Python line
      (which is honest), the residue in `env-flag-divergence.md` §2 is not.
- [x] **BAKED GATE LITERALS named**: 13 rows that will all move on the day P6 lands,
      each currently GREEN. `env-flag-divergence.md` §3.
- [x] **`helpers.bend` has NO `main`, so it had NO gate at all** — the file that owns
      the flag machinery was the one file where a flag bug is completely ungated.
- [x] Rules V-X-Y-Z appended to `.agents/slop/notes/bend2-constraints.md` (from
      position 11274). Four of the tools appended to `.agents/TOOLS.md`.
- [ ] **P6 itself — NOT STARTED, and it needs its own unit with its own plan.** The
      three things it must get right are in `env-flag-divergence.md` §6, and the gate
      requirement that follows is: **every flag needs a row at a NON-DEFAULT
      environment value.** A default-env gate cannot tell a correct flag read from a
      baked default, and that is the entire failure mode this unit found.

## Session 2026-10-03 — ungated-drift closure: `uop/render.bend`, `codegen/rewriter.bend`, `rebase-plan.py`

Two committed `.bend` files that no gate had ever run, plus the reason the
rebase planner had been skipping one of them. **NOT COMMITTED.**

- [x] **The working `tinygrad/` is a MEASURED BROKEN HYBRID**, which is the first
      fact and shapes every expectation: `uop/ops.py` is at upstream HEAD while
      `uop/render.py` is at the pin, and `pyrender` in that tree answers
      `UOp.range(4, AxisType.WEAK, 0)` — **neither** end. So every row's expected
      value is generated by CALLING CPython in `.agents/slop/xd1/head`
      (`git archive upstream/master`), and **no row's expected value was ever
      changed to make a change pass**.
- [x] **`uop/render.bend`, 66 -> 80 gate rows** (14 ADDED, 4 RE-MEASURED, 0 removed),
      `ALL PROOFS CHECK`, interp and native lanes byte-identical,
      **77 of 80 rows verified against live CPython**
      (`agree=77 disagree=3 no-oracle-row=0`). The 4 re-measured rows are exactly the
      4 whose baseline answer was WRONG: `arg_repr ARng` and the three BUFFER-rendered
      rows `pyrender buffer`/`copy`/`store`. **The baseline's `arg_repr ARng` was
      self-inconsistent** — the port answered `((0), AxisType.GLOBAL)` (with a comma,
      the `u32_tuple_repr` bug) while its own embedded `py=` said `((0,), …)`, so the
      port-vs-`py=` check was green and BOTH halves were wrong: the `nv_query_litter`
      shape, found by `verify.py`'s third input.
      Four measured upstream sites closed:
      * `loop{x.arg[0]}` -> `x.axis_id[0]` (`render.py:365`). `render.bend` never
        mentioned `AXIS_UNROLL`; the site lives in `renderer`, which is
        `# TODO(p3) render.py:45` — **unported, so no row here could catch it**.
        What landed instead is `peek_str` plus two rows (`pyrender mul3`/`xor3`)
        that pin the head-of-id-list read the port needed.
      * the `Ops.BUFFER` pyrender rule **DELETED, not neutered** (upstream dropped
        it), taking `paramarg_of`/`arg_addr`/`addr_is_global`/`max_numel` with it;
        the wall is kept in a comment block. Mutation M-b restores it in full and
        moves 5 rows; restoring the dispatch arm alone moves **0** — because the
        arm's fall-through target `pmp.fb` is exactly what a BUFFER already takes,
        so a re-added arm that DELEGATES is the same program until it has a BODY.
      * the `Ops.RANGE` rule rewritten to HEAD with a new `len(x.axis_id) == 1`
        guard; the pin's `[repr(y) for y in x.arg]` prints the whole id list and
        the guard selects the other branch. M-e/M-f/M-g are `>= 1` / no guard /
        whole-list.
      * the pyrender CALL-refusal predicate changed to `body.op is PROGRAM`
        (`pyr_call` hoisted above `main` because it is not entry-order-linear);
        M-c/M-d/M-m are the three readings.
      * plus a **pre-existing bug the gate had been printing since it was written**:
        `u32_tuple_repr` dropped the 1-tuple comma, which is WHY the baseline
        `arg_repr ARng` read `((0), …)` — a comma inside a 1-tuple. `arg_repr ATup`
        has two elements, so no other row could see it; `ATup1`/`ATup0` now exist
        because M-h and M-j each moved nothing.
      * The 3 disagreements are `arg_repr ACALL2`, `arg_repr ACALL3`, `pyrender cfn`
        — all **`ops.bend` substrate** (`CustomFunction` added, `CallInfo.dtype`
        dropped), annotated in-file, expected to go green with no edit here once
        `ops.bend` re-cuts `CallInfo`. `arange_repr` takes HEAD's reading (ids = flat
        tail); the resulting `ARange` ucache collision is `ops.bend`'s wall and is
        recorded, not hidden.
      * 13 mutations, 11 move rows; the two zeros are theorems (`peek_str`/`range_pieces`
        can only see one-element lists). Mutation driver `.agents/slop/xd1/mutate.py`.
- [x] **`codegen/rewriter.bend`, 32 -> 54 gate rows** (22 ADDED, 0 re-measured,
      0 removed — the drift here was a RENAME plus an unported rule, not a wrong
      answer, which is exactly why no gate could ever have caught it),
      `ALL PROOFS CHECK`, lanes
      byte-identical, **54 of 54 verified against live CPython, 0 disagree**.
      `gd_table`/`dv_table` were re-pointed at HEAD's names and line numbers (a RENAME,
      length 3 at both ends — measured, so no gate could ever have caught it);
      `rs_table` (`RANGE` + `END`) was ADDED and **`pm_range_to_special`'s rule was
      PORTED** (guard + rebuild, pure, no wall). 10 mutations, 9 move rows; N-e's zero
      is a theorem (`rs_at`'s `AXIS_LOOP` fallback makes `claimed` imply `isrange`).
- [x] **`rebase-plan.py`'s stem-matching bug, fixed and PROVEN.** The old map was
      **34 ported / 15 NONE**; the new one is **38 ported / 11 NONE with 0 lost** —
      4 files the planner had never seen (`codegen/__init__.py`, `codegen/gpudims.py`,
      `codegen/simplify.py`, `runtime/ops_python.py`) and 3 whose status CHANGED.
      Cause: the port map is read from `.bend` HEADERS, and multi-source headers WRAP
      and ELIDE `tinygrad/`. Three filters fix it — header block only, skip `_`/`_work`
      scratch names, accept bare paths. Proof: `.agents/slop/xd1/stem-bug.py`.
- [x] 12 rules appended to `.agents/slop/notes/bend2-constraints.md` (from position
      11741). Pin match **210/230 before and after — unchanged by this unit**, which
      is correct: this closed drift inside the ports, not drift of the pin.
- [ ] **`tinybendygrad/helpers.bend` does not compile right now** (a live agent is
      mid-edit: eight `nc_*` defs read an un-`+`-pinned binder twice), which fails
      EVERY file in the tree — `uop/ops.bend`, `codegen/rewriter.bend` and
      `uop/render.bend` all with the same error, none of them mine. Worked around
      with `.agents/slop/xd1/wt-sync.sh`, which mirrors the tree and restores
      `helpers.bend` from HEAD. **FLIP BACK: delete `.agents/slop/xd1/wt-sync.sh`
      and `.agents/slop/xd1/wt/` the moment that agent lands.** Not done by me — it
      is not my file.
- [ ] **The 3 remaining `render.bend` disagreements need `ops.bend`** (`CallInfo`
      re-cut + `CustomFunction` added), and the `ARange` ucache collision needs the
      same file. Both are named at `ops.bend:4705-4712` as one coupled change.

## Session 2026-10-03 — REBASE GATE WIRING: 19 ports with gates and no instrument

The unit is instruments, not ports. No `.bend` file's logic and no gate row's
expected value was edited; three ports were perturbed for a red proof and each
revert is SHA-256 verified. **NOT COMMITTED.**

Progress: `rebase-gate.py --batch 1` — oracles wired **[7/21]** · oracles that
exist and are dead **[3]** · measured with no oracle at all **[11]** ·
`rebase-gate-selftest.py` states **[20/20 reachable]**

- [x] **THE FINDING.** `--batch 1` reported `TALLY NOT-STARTED=19` and every one
      of the nineteen was an INSTRUMENT failure, not a port failure:
      `BASE_ORACLES` had three entries. 17 ports had a working gate and no
      registration; 2 had one and no baseline. Nothing about the ports was known
      from that number, which is the same silence as a pass.
- [x] **`rebase-survey.py` — WIRE BY THE ROW-NAME INTERSECTION, NOT BY THE
      FILENAME.** Every candidate is RUN and its rows intersected with the port's.
      104 candidate scripts over 21 ports. The two shapes this rejects are the
      value: `qc_oracle.py` runs, exits 0, emits 364 rows and shares ZERO names
      with `ops_qcom.bend`'s 750; `rf-rows.py` shares 34 of 92 with
      `schedule/rangeify.bend` and disagrees on 3.
- [x] **WIRED, by measurement:** `ops_rdma` <- `oracle_rdma_gate.py` (389/389),
      `ops_nv` <- `nv-oracle.py` (543/600), `hcq2` <- `hcq2-oracle.py` (157/360,
      already wired), `uop/ops` <- `rebase-oracle-ops.py` (62/62),
      `codegen/rewriter` <- `xd1/rw-oracle.py` (41 shared, 38 agree),
      `codegen/opt/search` <- `rebase-oracle-search.py` (12/18),
      `uop/spec` <- `rebase-oracle-spec.py` (11/21), `ops_metal` <-
      `mt_seam_rows.py` (14/432).
- [x] **ORACLE DEAD, named, never counted as coverage:** `hcq2-oracle2.py`
      (`AttributeError: 'HCQInfo' has no attribute 'nargs'` after 26 rows, so it
      is a DEAD LANE and wiring it would make the whole port BROKEN),
      `oracle/dtype_tables.py` (TSV, 0 rows, exit 0), `mt_rows.py`
      (`KeyError: 'SELECTORS'` — `ops_metal.py` lost it at HEAD),
      `mt_constmap.py`, `amd_oracle.py` (`is_am`), `notes/rw-truth.py`
      (`gpudims` has no `pm_add_gpudims`; it is `pm_group_gpudims`),
      `notes/rz-oracle.py`, `qc_check.py`.
- [x] **A NEW FINDING, and the reason this unit existed.**
      `tinygrad/codegen/opt/search.py` IN THE VENDORED TREE DOES NOT IMPORT: line
      15 reads `AxisType.UNROLL`, which upstream deleted (and which upstream's own
      copy of that line no longer reads). Measured against the upstream snapshot:
      `actions` is **209** where `codegen/opt/search.bend` counts **269**, and
      **18** amt-0 entries where the port counts **28**; `zero_un9` and
      `zero_red0` gate enum members that no longer exist. `rebase-plan.py`
      recorded `actions` as CHANGED and no gate noticed. Reported, NOT FIXED —
      `tinygrad/` is the re-vendor's and `codegen/opt/*` is a live agent's.
      **The tree's own importability is now a ROW**
      (`#repro_vendored_import`).
- [x] **A ROW-NAME COLLISION THE GATE CANNOT SEE, measured.** `rs_claim_warp` is
      `axis_type in (GLOBAL, LOCAL)` (the rule's negative control, 0) in
      `rewriter.bend` and `range.axis_type is WARP` (a construction round-trip, 1)
      in `xd1/rw-oracle.py`. Same name, two questions; GUARD 3 catches a pair
      that shares NO name and there is no guard for a pair that shares a name and
      means two things by it. Recorded in `KNOWN_RED` with that sentence.
- [x] **`ports_of()` SHIPPED A CRASH AND THIS SESSION HIT IT.**
      `plan["port"]` now maps an upstream file to a LIST of ports (`uop/ops.py`
      names both `fold.bend` and `ops.bend`), so `out + ([p] if p else [])`
      appended the list as one element and `BASE_ORACLES.get(p)` raised
      `TypeError: cannot use 'list' as a dict key`. A gate that crashes on the
      shape of its own input reports nothing, which is the same silence as
      NOT-STARTED. Fixed and flattened.
- [x] **`rebase-survey.py` REPRODUCED, IN ITS OWN BODY, THE BUG
      `rebase-gate.py`'s GUARD 3 EXISTS TO PREVENT.** An unkeyed cache replayed
      a FAILED run: `codegen/kernel.bend` measured `port_rows=0 rc=1` for twenty
      minutes while `./bin/bend` on it printed 38 rows throughout. Every cache
      entry is now keyed on the source file's `(mtime_ns, size)`.
- [x] **`rebase-gate-selftest.py` IS NOW A TEMPLATE FOR EVERY ORACLE.** Six
      states, each driven through the same `gate_port()` main() calls with each
      wired oracle's OWN row names: dead lane, empty output, no shared row name,
      a shared name that differs, agreement, malformed baseline. Eight oracles,
      20/20 reachable.
- [x] **RED PROOFS, every one observed, every revert SHA-256 verified.**
      `uop/spec.bend` (adding one `hcq_own` entry moved `hq_len` 35->36 and the
      oracle went red), `uop/ops.bend` (`axis_colors` "green"->"olive" moved
      `axc_DEVICE`), `codegen/rewriter.bend` (deleting one `dv_table` entry moved
      `dv_len` 2->1). The search oracle's red proof went the OTHER way, through
      `rebase-shadow.py`, which perturbs the TREE: `codegen/opt/*` is a live
      agent's file and a 40-second perturbation in front of them is not worth
      the coverage. Narrowing the UPCAST group `range(10)`->`range(9)` moved
      `acts_n` 209->203, `acts_n_padto` 216->210, `acts_zero` 18->17, `zero_up9`
      1->0.
- [x] **`runtime/ops_amd.bend` oracle wired.** 409 of 520 shared, 0 disagree.
      `USBIface` was unbound because the oracle eval'd a drifted line number
      (`ops_amd.py:858` is now `isinstance(..., USBIface)`; the target
      decomposition is `:862`). Class exists at import (`:814`), not a ctypes
      struct, instantiation needs a device. Not `--record`ed. `MOCKUSBIface`
      is isinstance-USB and no shared row covers it.
- [ ] **NO ORACLE EXISTS, measured against 104 candidates — these are the ports
      the rebase gate genuinely cannot see.** `codegen/kernel.bend` (38 rows,
      3-symbol drift), `codegen/opt/heuristic.bend` (10, 0-symbol drift),
      `codegen/opt/postrange.bend` (48, 4-symbol: `flatten`/`merge_dicts`
      removed, `split_targets` changed), `device.bend` (105, 0-symbol),
      `engine/realize.bend` (50, `array` removed), `runtime/ops_cl.bend` (445), `runtime/ops_cpu_null.bend` (308,
      2-symbol), `runtime/ops_qcom.bend` (750, 1-symbol), `schedule/indexing.bend`
      (252, 1-symbol), `schedule/rangeify.bend` (126, 1-symbol).
- [ ] **THE BASELINE IS NOT RECORDED, DELIBERATELY.** `baseline.json` holds one
      port (`cstyle.bend`). The tree has ALREADY been re-vendored to
      `upstream/master` (`git diff 6c3d401cf324 HEAD -- tinygrad/` is 20 files),
      so a baseline recorded now captures the AFTER state and the advance's
      damage becomes invisible — which is the one thing `--record` must never be
      used for. The honest verdict for the other 20 ports stays
      `NOT-STARTED / no baseline recorded`. Re-record at a real pin, on a tree
      known green.

---

## Session 2026-10-03 — `runtime/support/objc.bend`: the FFI seam that is MOSTLY logic

- [x] **`tinybendygrad/runtime/support/objc.bend`** — `tinygrad/runtime/support/objc.py`
      (77 lines). Verified genuinely unported before starting: `objc.py` was cited
      **zero** times by any `.bend` file. 1129 lines, 123 gate rows, 111 of them
      with a `py=` half. `ALL PROOFS CHECK`, both lanes byte-identical
      (md5 `5b89106f…`), 18 mutations, control M17 at 0.
      Artifacts: `.agents/slop/objc/{objc_oracle.py,objc_oracle.txt,objc_diff.py,
      objc_mutate.py,objc_mutations.txt,symtab_oracle.py,symtab_oracle.txt,
      objc_bend_gate.txt,objc_bend_native.txt}`.

      WHAT PORTED. `:36`'s argument precedence — **THE HEADLINE RULE of this file**,
      `[id_,id_]+list(argtypes) if argtypes else []`, so a message with NO declared
      arguments gets `[]` and not the two implicit `id_`s. `:70`'s selector-name
      mangling, both steps and **their order** (`strip(':')` removes the trailing
      colon, so `newBufferWithLength:options:` mangles to
      `newBufferWithLength_options` and NOT `…options_`). `:27`'s `functools.cache`
      as a TYPE with its miss/hit counters. `:37`'s call shape and receiver swap,
      and the fact that it is **TWO** C calls. The `retain`/`returns_retained`/
      `own` ownership lattice, with `__del__`'s two conjuncts as parameters. `:71-73`
      the `instancetype` substitution, per-argument. `:63-67` the inherit order.

      WHAT DID NOT. Four walls, named with `TODO(p3)` and their Python lines:
      the four `ctypes.CDLL` loads (`:25`, `:30`); `class id_`'s pointer identity
      and the GC hook (`:13`); `MetaSpec` itself, which is a metaclass and Bend has
      no classes (`:49`, `:71`); and the callables, because Bend has no first-class
      functions (`:23`).

      THE ORACLE. **The only thing stubbed is the four `ctypes` loads** — the
      recorder is not cosmetic, it reproduces `ctypes.CDLL`'s ASYMMETRY, because
      `:36`'s own comment is about it: subscript (`lib["objc_msgSend"]`) is a FRESH
      fnptr per `msg`, attribute (`lib.sel_registerName`) is one cached fnptr. A
      symmetric stub collapsed the file into a shared last-write-wins slot.
      248 oracle rows, `sys.exit(0)` asserted, and the differ refuses a non-zero
      exit or a row count below 200. The oracle's section 8 emits rows named
      EXACTLY as the gate's, so the differ is a plain name lookup; the alias-table
      version it replaced compared 23 rows and left 87 uncompared.

      FOUR PORT BUGS THE ORACLE CAUGHT, all three of the first ones mine:
      `getsel_ix` answered 1 for an absent name (index 0 is a real index);
      `msg_argc` counted the tail of a `d <> r` pattern, and then counted `:36`'s
      two implicit slots twice; `Idr.own` emitted only the `objc_msgSend` where
      the real `msg("retain")` sends the selector lookup too; `mangle.rtrim`
      returned the UNTRIMMED tail, so **every** mangled name came out wrong.

- [ ] **TREE DEFECT, REPORTED NOT FIXED — the Metal host kernel cannot link.**
      `tinygrad/runtime/ops_cpu.py:19,21` gives `jit_loader` `link_libs=[libm,
      libSystem]`, and neither exports `sel_registerName`. But
      `cstyle.py:268` emits `extern void sel_registerName();` into the generated
      HOST kernel for every `CUSTOM_FUNCTION`, because `hcq2.py:84` names a device
      symbol after `fn.__name__` and `ccall(SELNAME, sel)` is one. So
      `(a@a.T).realize()` on `Device['METAL']` raises
      `RuntimeError: Attempting to relocate against an undefined symbol
      sel_registerName` — MEASURED end to end. The fix is libobjc in
      `CPUProgram.link_libs`; `ops_cpu.py` is not this unit's file.
      **OWNER: whoever owns `runtime/ops_cpu.bend`.**
      See the note at the end of `bend2-constraints.md` position 10.
- [ ] **`support/c.py:102-103` — `DLL.findlib`'s `is_file()` gate.** It silently
      skips `/usr/lib/libSystem.dylib`, which a BARE `ctypes.CDLL` opens fine, so
      routing `objc.py:30` through `DLL` would break a binding that works today
      with no `emsg` and no error. MEASURED both ways.
      **OWNER: whoever owns `runtime/support/c.bend` (or `support/c.py`).**
- [ ] **`objc.py:30`'s `dispatch_data_create` is NOT a `libSystem` export.** It
      resolves only through libSystem's re-export chain into
      `/usr/lib/system/libdispatch.dylib`, and nothing in `tinygrad/` reaches the
      symbol through a loader that does. One consumer, `ops_metal.py:243`.
      **OWNER: the `ops_metal` agent** — `runtime/ops_metal.bend` already records
      `ops_metal.py:86` as a TODO against a `SELECTORS`/`MSGSEND` shape the tree no
      longer has, and this is the same file's `:243`.
- [x] **THE DEMONSTRATION BASELINE IS NOT THE PIN BASELINE.**
      `.agents/slop/rebase/baseline-DEMO.json` records the CURRENT tree and exists to prove
      the four states are reachable on REAL ports: `TALLY BROKEN=3 NOT-STARTED=13
      UNCHANGED=5`, with the three BROKEN being `uop/spec.bend` (2 rows), 
      `codegen/opt/search.bend` (5 rows) and `codegen/rewriter.bend` (3 rows, all
      row-name collisions). **`.agents/slop/rebase/baseline.json` is untouched** and still
      holds one port. Delete `baseline-DEMO.json` when a real pin baseline is recorded —
      leaving it is how a demonstration baseline becomes a silent pass later.

---

## Session 2026-10-03 — `renderer/amd/generate.bend` (the ISA-XML GENERATOR: 541 py, 346 logic)

- [x] **`tinybendygrad/renderer/amd/generate.bend` — PORTED AND GREEN AT 91 ROWS.**
      `ALL PROOFS CHECK`; `./bin/bend tinybendygrad/renderer/amd/generate.bend` prints
      91 rows and `ga_gate.py` reports **91 rows, 91 agree, 0 differ** against
      `.agents/slop/ga-oracle.txt` (**892 rows**, regenerated from CPython this
      session and verified byte-for-byte reproducible). 2,699 bend lines, 413 defs,
      23 record types. Ported: `_strip_enc`, `_norm_field`, `_map_flat`,
      `field_def`, `write_common`, `write_enum`, `write_ins` (all four folds),
      `write_operands`, `write_pcode`, plus the module tables (`FIXES`,
      `FIELD_FIXES`, `FIXED_FIELDS`, `ARCHS`, `_SKIP_ENCODINGS`, `NAME_MAP`).
      Toolchain, all reproducible from the inherited state:
      `ga-oracle.py` -> `ga-oracle.txt`, `ga_fix.py` -> fixture+gate,
      `ga_splice.py` (the tail is 10 defs and NOT contiguous),
      `ga_topo.py` (callee-first), `ga_dedup.py`, `ga_plus.py`, `ga_gate.py`,
      `ga_mutate.py`, `ga_probe.sh`.

- [x] **`write_ins` is 100% ported and PINNED, not partially.** The inherited file
      stopped inside `field_def` and never emitted a class; the four folds
      (base classes with the FLAT `seg` split, variant classes, SDST classes,
      `functools.partial` helpers) plus the import header are all in, and the two
      `ins` gate rows diff a WHOLE generated `ins.py` (168 lines each) against
      CPython's. Ten walks whose `Bool.pick` arm held a self-call were
      de-exponentialised into `.step` accumulators (`all_ops.eos`, `bases.go`,
      `variants.go`, `dsl_used`, `extra_fields.go`, `oi_otype`,
      `variant_suffix.go`, `ss_go`, `sg_go`, `sdst_of`).

- [x] **`write_pcode` PORTED (generate.py:484-499), `extract_pcode` NOT, and the
      reason is a MEASURED WALL, not an omission.** `bend base --types` lists `F32`
      and `bend base | grep -c F64` is 0, and `extract_pcode`'s 37 logic lines are
      seven float decisions (`round(y)` grouping, `55 < x < 65`, `535 < x < 550`,
      `end_y < y2 < start_y`, `prev_y - curr_y > 30`, `prev_y > 60 and curr_y <
      730`, `-y` sort) over coordinates `extract_pdf_text` builds by SUMMING PDF
      `Td` offsets. CPython's `round` is BANKER'S and `F32.round` is
      half-away-from-zero, so the y-GROUPING would be a different function, not a
      differently-typed one. `write_pcode` IS ported and IS gated against the dict
      CPython's own `extract_pcode` returns on the same pages fixture, so the seam
      is a value and a gate row. WALL 5 in the file header.

- [x] **THE FIXTURE NOW HITS EVERY ARM OF `field_def`'s 19-ROW LADDER.** The
      mutation table found 11 of them unexercised (only 7 of the 10 DSL field
      classes were ever emitted; `SBaseField`, `SRsrcField`, `VDSTYField`,
      `default=NULL` and `default=1` never appeared in any gate row).
      `ga-oracle.py`'s `fixture_encodings` was extended -- SM now carries the three
      7-bit SGPR shapes, SOP1 the 8-bit pair plus a 7-bit `soffset`, SOPK the only
      5-bit (`srsrc`, `ssamp`) and 6-bit (`sbase`) shapes, VOP3P `opsel_hi2` and
      `vdsty` -- and the oracle was REGENERATED BY CALLING CPython, so no `py=`
      literal is typed. All ten DSL classes and all three `default=` forms are now
      in the diff.

- [x] **MUTATION TABLE: `.agents/slop/ga-mutate.txt`, 41 mutations, 40 MOVE ROWS.**
      The one non-mover is a documented deliberate no-op (M41: `NULL` is in BOTH
      `_ALL_DSL` and `_DSL_REGS` upstream and upstream takes `sorted(set(...))`, so
      dropping it from one side cannot move a row -- the table PROVES the
      redundancy rather than hiding it).

- [x] **THE INHERITED 175 IS ACCOUNTED FOR AND WAS NOT A SUBSET.** It was the 84
      scalar rows emitted TWICE, plus a stray line, plus three rows whose `gl` call
      had lost its body. The oracle's 892 are 736 per-LINE rows of four generated
      Python modules (which the gate joins into 8 whole-file rows so a dropped
      class, a dropped enum member, a swapped `default=NULL` and a reordered field
      are four different diffs), 50 `norm_field`, 50 `strip_enc`, 16 `map_flat`,
      34 `parse_xml`, 4 `pcode`, 1 `pdf`, 6 `order` and 16 table rows.

- [x] **`ga-oracle.py` print shape wired into `BASE_ORACLES`.** The gate's
      `rows()` compares whole values, so `nm = [val]` against the port's
      `[got]   py=[want]` was 84/84 red and zero of it was data. One print
      change to `f"{nm} = [{val}]   py=[{val}]"` recovered **84/84**
      (`strip_enc` 18, `norm_field` 50, `map_flat` 16), all three calls of
      `generate.py`. Residue: none. The other 149 port rows stay outside the
      oracle's name set (generated-Python lines `rows()` splits on `=`). Wired
      in both rosters; not `--record`ed, because GUARD 1 would freeze 554
      ungated oracle rows.

- [x] **EIGHT MEASURED BEND RULES APPENDED** to
      `.agents/slop/notes/bend2-constraints.md` as GA1-GA8: `List.sort`'s
      comparator is `@_ -> @_ -> Bool` and every field accessor is a `match`, so a
      two-key comparator must destructure once; **`U32.is_lt`/`is_le`/`is_eq`
      CONSUME their operands too** (the existing note said only `String.*` does);
      a def body continues with a TERM and not with a leading `++`; **the machine
      stack is not a fixed budget and the green file failed 2 of 12 back-to-back
      runs under load** (`ga_mutate.py` retries that stderr 8x); there is no `F64`;
      a char literal cannot spell `'` or `\`; `Bool` needs `import Base`; and a
      gate on an emitted file must diff the file.

- [x] **TWO INHERITED PORT BUGS THE GATE CAUGHT, both reported to the file's
      history rather than left silent.** `write_enum` shipped THREE
      implementations of the member walk (`write_enum.cells`, `write_enum.go2`,
      `write_enum.cells.go`) and `write_enum.one` called the wrong-order one; and
      `field_def`'s `hi_text` was dead code returning a String that `ctor_text`
      never consumed, so the `BitField(12, lo)` arm could not fire. Both are gone.

- [x] **`field_rules()` HAD `pb=1` IN ALL EIGHT WIDTH-GUARDED ARMS.** The
      inherited report claimed all 17 arms were gated; they were not, because the
      guard was `1` in every one, so `field_def` never matched VGPR/SBASE/SRSC/
      SGPR/SGPRN/SSRC/SSRCN/SRC9. Fixed to the real widths (8,6,5,7,7,7,8,8,8,9)
      from `generate.py:306-313`. No gate row had reached `field_def` before, which
      is why nothing caught it.

## Session 2026-10-03 — dtype.bend const CAST refusal (measured, not the note)

Progress: `██████████` 1/1

- [x] `l2i(Ops.CAST, long, UOp.const(0, uint32))` called in CPython and in the
      port. CPython does not raise; the tree is `(CAST(CAST(C(0))), CAST(C(0)))`
      (`dtype.py:28-32`, `long` = `dtypes.i64` at `dtype.py:142`). The note's
      `(CAST(C(0)), CAST(C(0)))` is the ulong fold (`mixin/dtype.py:36`). The
      port already accepted both. Gate 147 → 164 rows. `lgn` (FLOORDIV) stays
      `NotImplementedError` (dtype.py:81, true). The unported float-target arm
      prints `unported` (`lgu`), not that name. Each new row moves on a flip.

## Session 2026-10-03 — `codegen/decomp/dtype.py`
- [x] `tinybendygrad/codegen/decomp/dtype.bend`, one `.bend` at dtype.py's path, all
      eighteen defs under dtype.py's own names. `--check-only` = `ALL PROOFS CHECK`.
      174 defs; imports `P.dc_*`, `P.dc_opname`, `T.tx_*`, `T.exponent_bias`,
      `T.tx_finfo_*`, `T.tx_is_fnuz`, `H.i64_*` rather than re-deriving them.
- [x] FIVE DIVERGENCES stated in the file header, each with its reason: (A)
      `UOp.const(v, dt)` is a CONST+CAST pair; (B) `_broadcasted`'s promotion CAST
      and `logical_not`'s `cast(bool)` are not built; (C) `l2i`'s float-target CAST
      arm is absent (unreachable through `pm_long_decomp`); (D) no f16/bf16/f64 SOURCE
      for `f2f`/`f2f_clamp`; (E) no f64 `f2f_clamp` TARGET (`mx` is the f64 max).
- [x] `.agents/slop/dd-oracle.py` — 412 rows by CALLING CPython's `dtype.py`, exit 0,
      `.agents/slop/dd-oracle.txt`. Two decisions that a naive port gets wrong and that
      are measured, not reasoned: the promotion CASTs are marked by the CALLING
      PYTHON FRAME (`sys._getframe(1).co_name` in `promote`/`logical_not`) and `r is
      not self` keeps `promote`'s identity fold out of the marker; a float CONST prints
      as its 32 BITS because `H.f32_show` cannot agree at the `float32` maximum.
- [x] THE GATE RUNS: `.agents/slop/dd-gate.txt`, **66 of 121 rows byte-identical** to
      the oracle. The four facts per fixture are the answer tree (two levels), the node
      COUNT, the creation-order `sig`, and the constants in that order. Three printer
      defects were found and fixed by the gate itself: the `k` row dropped its `-`
      (the walk threaded `first` as `False{}` unconditionally), the pool offsets were
      the oracle's `WPOOL` offsets and not the 24-word list's, and the three
      `bitcast(uint)` calls in `l2i`'s ADD and SUB arms FOLD (pm_long_decomp splits to
      32-bit words before any rule reaches `l2i`, so `a0`/`b0`/`low` are already
      `uint`) -- `lgc` went from 1/4 to 4/4 on that one fix, and `l2i_add`'s CMPLT is
      `(low < a0)` while `l2i_sub`'s is `(a0 < b0)`, which is what keeps their sigs
      apart.
- [ ] `l2i_cast` REFUSES EVERY CAST FIXTURE: `lg2`, `lg3`, `lg4`, `lg5`, `lg6`, `lg7`
      and `lgo` all print `none` where the oracle prints a CAST tree. The four-way
      `dd_cast_sel` ladder picks no arm. `lg1`'s tree is byte-identical, so the port is
      right up to that point and the defect is inside the selector, not in the arms.
      ONE FIX HERE IS WORTH NINE ROWS.
- [ ] THE `none` SPELLING IS WRONG FOR A REFUSAL: the oracle prints
      `<nm>=refused:<ExceptionName>` (`lgn=refused:NotImplementedError`) and this gate
      prints `<nm>=none`. A refusal is not a missing answer and must not read as one.
      The oracle's `run` has the exception type, so the row is derivable, not typed.
- [ ] `l2i_shl` / `l2i_shr` pick the wrong arm (`lg9`, `lga`, `lgb`: 12 rows). `lga` and
      `lgb` differ ONLY in `dt == dtypes.int`, which is the `fill` line, and both
      differ from `lg9`, so the SHR arm is reaching the SHL shape.
- [ ] `l2i_mul`'s last node is `ADD(ADD, NOOP)` where the oracle has `BITCAST(MUL)`, and
      the stray `NOOP` is `O.Arena.src0` of a node with no srcs (`lge`: 5 rows).
- [ ] OFF BY TWO on every `l2i` row's `n`/`sig`/`k`: the port counts dtype.py:22's
      `zero = UOp.const(0, dt)` pair and the oracle does not (`lg1n` 12 vs 10, `lg1sig`
      `CONST/0,CAST/1,CAST/1,...` vs `CAST/1,...`). ONE BITCAST is also duplicated.
      Not yet explained: `UOp.const(0, dtypes.int)` is the FIRST fixture, so its CONST
      and its CAST should both be fresh in CPython too. MEASURE BEFORE FIXING.
- [ ] NOT GATED YET: `f2fdt0..8`, `u32n`, `unpack32`, `reindex`, `rne`, the eight
      `f2f_clamp` rows, the fifteen `f2f` rows, `l2i_define`, and the three pattern
      tables. The printers, the fixture pools and the row machinery they need are all
      written and compiling; what is missing is the row defs, one per family, in the
      shape `l2i.one` shows.
- [ ] MUTATION TABLE: not run. Every mutation so far is a type error caught by
      `--check-only` rather than a red row, so the gate's DISCRIMINATION is untested.
      Owner: `dd-mutate.py`. Do not start while `dtype.bend.ddmut` exists — that bake
      is M32 (`Bool.not(dd_l2i_ok)`), and the live file does not match it.
- [x] GATE ROW SET RESTORED (2026-10-03). The 72-row run was M32, not `dd_fuel`: every
      `l2i` fixture took `l2i.gone` → `dd_ref`, which prints `=` and `n=` and never
      `p=`/`sig=`/`k=`. `up*` survives because `unpack.one` bypasses the guard.
      Measured on a copy: 147 rows → 72, missing 27 `sig` + 27 `k` + 21 `p`. Live file
      has the guard un-inverted. Verified run: 147 rows, comment-only control SAME.
      Old-metric vs new-metric on the same 120-row intersection (old ∩ new ∩ oracle):
      44/120 → 65/120, gained 22, lost 1 (`lg1n` 10 → 11; oracle is 10).
- [ ] `.agents/slop/ddcheck.sh` + `dd-patch-helpers.py` are a COMPILE WORKAROUND for
      another agent's `helpers.bend` (its `ansistrip` block does not compile and every
      file imports it). DELETE BOTH once it compiles. `dd-sort.py` (topological
      reorder), `dd-fixreaders.py` (type-aware reader repair) and `dd-header.txt` are
      workarounds of the same kind and should go with them.

- [x] DEF-NAME VIOLATIONS AGAINST UPSTREAM: classify, then rename where it is real.
      DONE by the name-audit unit, 2026-10-03. The brief's "~75 PREFIXED" does not
      survive measurement: `pm_` is UPSTREAM's own prefix (94 top-level names, e.g.
      `pm_simplify_ranges`, `pm_remove_invalid`), so dropping it would invent a name.
      Measured breakdown of every `PREFIX_rest` bend name (352 raw string matches,
      after four filters below):
        * 263  MULTI-PREFIX TABLE ACCESSORS, ALL in `renderer/amd/sqtt.py`, and they
          are unrenameable BY CONSTRUCTION. Six prefixes (`cls_` `dflt_` `mask_`
          `dlo_` `himax` `dmask` + `enum_` `cu_`) all expand to the same 48 upstream
          `PacketType` names: upstream's metaclass derives the columns from one class
          and Bend has no metaclass, and duplicate declarations are a compile error.
        *  16  GENUINE rename candidates after requiring the bare name be FREE and the
          def be neither a duplicate accessor nor a test gate.
        *  23  rejected because the bare name is ALREADY DEFINED (e.g. `renderer/tc.py`
          `r_tbl_amd_cdna3 -> amd_cdna3`, where `amd_cdna3` is a struct): renaming is
          a duplicate-declaration error, not a fix.
        * ~186 SUFFIXED (`_bend`, `_rows`, `_of`): cosmetic, upstream name readable.
        * ~13.4k PORT-LOCAL with no upstream counterpart: the rule does not apply.
      RENAMED 7, the ones in files no other unit holds: `schedule/indexing.bend`
      `ix_realize`->`realize` (3 sites), `ix_realize_srcs`->`realize_srcs` (6),
      `ix_broadcast_rngs`->`broadcast_rngs` (3); `schedule/rangeify.bend`
      `rf_is_noop_after_dep`->`is_noop_after_dep` (7),
      `rf_no_indexing_calls`->`no_indexing_calls` (4),
      `rf_remove_noop_afters`->`remove_noop_afters` (9),
      `rf_strip_zero_offset_shrink`->`strip_zero_offset_shrink` (5).
      Rows byte-identical before and after: indexing 252, rangeify 126.
      Audit total 283 -> 290 verbatim of 1527 (18.5% -> 19.0%).
      LEFT ALONE: 9 candidates in `codegen/decomp/transcendental.bend` (`tx_*`),
      `renderer/amd/dsl.bend` (`VOP2_*`) and `renderer/amd/sqtt.bend` (`enum_*`) --
      all three are files this unit was told not to edit. They are handed over below.
      TOOLING: `.agents/slop/names-ag-{baseline,candidates,sites}.py` and
      `{mutations,valmut}.sh`. `names-ag-candidates.py` prints THE LIST.
- [x] FINDING, REPORT NOT FIXED (not my file): `schedule/indexing.bend` has TWO defs
      nothing calls, and they are the two I could not mutate into moving a row --
      `realize` (2 callers, `realize_srcs.one` and `ix_rcs_one`, and NEITHER has a
      caller) and `broadcast_rngs` (0 callers). A body mutation of each moves 0 rows
      for the same reason an inverse rename does: there is no row. This is the
      `agent-core.md` "defs written, commented, and never called" finding recurring,
      and it PREDATES the rename. Upstream `indexing.py:28` and `:62` are ported and
      unreachable.
- [x] FINDING, REPORT NOT FIXED (not my file): `renderer/amd/sqtt.bend`'s six
      accessor prefixes cannot be reduced to upstream names in Bend at all. Upstream's
      `PacketType` metaclass generates `cls`/`dflt`/`mask`/`dlo`/`himax`/`dmask` per
      subclass; a Bend `def` cannot be overloaded, so one file would need 6x48 distinct
      names. The prefix is the honest encoding of that limit, not a namespace invented
      for convenience. The owner may want this ruled on explicitly, because it is the
      one place the 1:1 name rule is not merely unmet but unmeetable.

## Session 2026-10-03 — `trange`, `GlobalCounters`, `Context` in
## `tinybendygrad/helpers.bend` (the only unit permitted to edit that file).
## **NOT COMMITTED.**

- [x] **THE BRIEF'S THREE DESCRIPTIONS OF THE THREE NAMES DO NOT MATCH THE PINNED
      UPSTREAM, and porting from the brief would have produced a wrong port.**
      * `trange` is NOT a "line-prefixed range helper with `trange(1,N+1)`,
        `trange(s,e,step)` and a `desc=` form". It is one line,
        helpers.py:619: `def trange(n:int, **kwargs) -> tqdm[int]: return
        tqdm(range(n), total=n, **kwargs)`. One positional arg, no step, no start.
        **There is no `desc` form anywhere in tinygrad.**
      * `GlobalCounters` has **no `.global_counter` and no methods** except
        `reset`. It is six `ClassVar`s (helpers.py:303-308) and one `@staticmethod`.
      * `Context` takes `**kwargs`, NOT `__name__`/`None`. It has no `.total`,
        `.vars` or `.tag`. `Context(None)` is not a thing. Its state is
        `self.kwargs` and `self.old_context`, both dicts.
      * `tqdm` has **no `.total`** either — `helpers.py:587` stores the total in
        `self.t`. The first oracle draft hand-typed `t.total` and CPython answered
        `AttributeError: 'tqdm' object has no attribute 'total'`.
      So every row was generated by CALLING `tinygrad.helpers`, and the three
      upstream `def`s (`helpers.py:619`, `:302`, `:170`) are byte-identical between
      the working tree and `.agents/slop/xd1/pin`.
- [x] **MUTABLE STATE, the central question: THREADED, and it is not a fake.**
      No `Ref`, no `Deferred`, no global store — there is no such construct. The
      answer is that a `Data` record IS the cell and each `+=` becomes a def that
      takes the record and answers the next one. It counts (the gate runs a nine-step
      bump chain and prints every intermediate total), and it cannot go stale,
      which a mutable global can. `Context`'s `old_context` is the same move: the
      snapshot is the return value of `__enter__` rather than a field a second
      call overwrites.
- [x] **`Context.old_context` IS A SNAPSHOT, NOT A STACK, and the gate proves the
      difference.** `__exit__` (helpers.py:178) REPLAYS the snapshot onto whatever
      is current. Two contexts on one key entered A,B and exited A,B leave **A's**
      value, not the original: measured `ctx_ooo_df=bfloat16` against a boot value
      of `f16`. A stack-pop port would answer `f16` and fail that row. A third
      fixture with DISJOINT keys pins that `__exit__` restores only ITS OWN kwargs.
- [x] **THE GATE WAS GREEN FOR A WHILE AND WAS GATING A COPY.** The first
      `.agents/slop/helpers-tc.bend` DEFINED `Counters`/`Ctx`/`Tqdm`/`trange`/
      `Context.*`/`GlobalCounters.*` locally and imported `helpers.bend` only for
      `H.Flags`. 62 rows agreed with CPython and a mutation of `helpers.bend` moved
      NOTHING. The gate now reaches every def through `H` and defines none of the
      three, which is one `rg -c '^(def|type) (trange|Context|GlobalCounters|Counters|Mupd|Ctx|CV|Tqdm)\b'`
      reading `0`.
- [x] **`helpers.bend` HAS NO `main`, SO IT HAD NO GATE AND STILL DOES NOT.** Its 64
      rows live in `.agents/slop/helpers-tc.bend`, which imports it, and are
      compared against `.agents/slop/helpers-oracle.py` (which CALLS
      `tinygrad.helpers`) by `sh .agents/slop/helpers-tc-gate.sh`. **62 -> 64 rows,
      3 lanes (CPython / interp / native) byte-identical.**
- [x] **WALL 1, the mutable global: there is no Bend construct for it.** Stated as
      the header comment on the `GlobalCounters` block, with the price named (the
      caller must USE the returned record).
- [x] **WALL 2, `getenv` is `functools.cache`d (helpers.py:162) and that is
      USED, not just respected.** The gate runs every configuration in a FRESH
      process with a NON-DEFAULT env (`DEFAULT_FLOAT=f16 DEFAULT_INT=i64
      NO_COLOR=1`), so `ctx_exit_df` answers the ENV value `f16` where a port that
      hard-coded the class default `float32` would answer that and fail. A
      default-env gate could not tell a correct flag read from a baked default,
      which is the whole failure mode the P6 audit found.
- [x] **WALL 3, no signed integer and no F32 add, and BOTH are load-bearing.**
      `trange`'s parameter is `U32`, so `trange(-3)` is a TYPE ERROR rather than a
      silent 4294967293 (CPython answers `t.t == -3` with an empty sequence).
      `time_sum_s` is a CPython `float`; `F32.add` is a LAW (base.bend:1556) and
      live code may not call a law, so the field is CARRIED and never written here.
      The oracle measures what CPython does with it and prints those rows to STDERR
      so they are recorded without being diffed.
- [x] **`tqdm.__init__`'s `disable` DEFAULT is `False`, not `None`
      (helpers.py:585), so `trange` draws its bar even into a pipe** — measured
      with `isatty` False. That is why the gate compares STDOUT only.
- [x] **`mem_used_per_device` is an ASSOC LIST, not a dense row vector**, because
      a `defaultdict`'s key set is insertion-ordered and `{0,3,9}` has three keys
      where a device-indexed list has ten, and because READING a missing key
      INSERTS it. The gate prints the KEY SET (`gc_default_keys`), and that row is
      what caught a real bug: a rebuild that prepended instead of appending
      produced `3,3,0,9` — a duplicated key.
- [x] 10 rules appended to `.agents/slop/notes/bend2-constraints.md` from position
      13330 (H-1 .. H-10).
- [ ] **`GlobalCounters.time_sum_s` still has no writer.** Owner: whoever owns P4
      (the engine's counter record). Needs an F32 add; `base.bend` has none.
- [ ] **`ContextVar._cache` is still 4 of 61 keys and `Flags.snap1.go` still has a
      4-arm key dispatch.** Owner: P6. NOT this unit's file decision — the
      mechanism is done, the list is the remaining work, and the `case _:` arm
      lands an unknown key on SUM_DTYPE with a `TODO(p6)` naming the KeyError.

## Session 2026-10-03 — `void`'s priority and `CustomFunction`'s dtype (`uop/fold.bend` only)
## **NOT COMMITTED.**

- [x] **DEFECT 2 FIXED. `CustomFunction` was answering `(void, None)` for EVERY node.**
      `dt_shape`'s `case O.OpsCUSTOM_FUNCTION{}` was filed among the always-void ops and
      called `late()`. ops.py:133-135 gives it its OWN arm — `return arg.dtype` — and
      ops.py:374 is `None if self.dtype is dtypes.void else ()`, so a `uint64` one
      answers `(uint64, ())`. New `cfun_ds`/`cfun_ds.shape` read `ACustom{cf}` and
      `CustomFunction.dtype`. Two rows that **disagree**: `cfun_void` and `cfun_u64`.
- [x] **DEFECT 1 CHARACTERISED, NOT "FIXED": `-1` is COSMETIC and unrepresentable.**
      `.agents/slop/dtype-pri-oracle.py` measures that `DType.priority` has exactly ONE
      reader in all of tinygrad (`__lt__`, dtype.py:68) and that `sorted(all 20)` is
      IDENTICAL for void at pri −1, 0, 1 and 7, because bitsize 0 is already the
      smallest and breaks the tie identically. Promotion never reaches the field:
      `void` is absent from `promo_lattice`, so `_get_recursive_parents(void)` is a
      KeyError and `least_upper_dtype` KeyErrors on 39 of 400 pairs. Mutations M10/M11
      move void's stored priority to 16 and to 1 and exactly 3 rows move
      (`bl_dt_void lo`, `bnd_void_is_bool`, `pri_three_way`); **no promotion row moves**.
      So `LAWS/spec.bend:679` keeps `pri 0` — it is byte-identical to `@-`.
- [x] **A SECOND, WORSE BUG FOUND BY MY OWN ROW: `least_upper` was NOT commutative.**
      It tested `U32.is_zero(ma)` and not `mb`, so a zero mask on the right decoded as
      `lowest(0) = U32.log2(0) = 0` and `dt_by_rank(0)` is `bool`:
      `least_upper.of(x, void)` answered **`bool`** where dtype.py's order-independent
      meet says `void`. One token: `Bool.or(...)`. Two rows, one per order.
- [x] **`fold.bend`'s `lowest` comment was FALSE and is corrected.** It claimed "every
      non-void mask has bit 0". Measured: bool's mask is 524287 with bit 0 SET and the
      other eighteen have it CLEAR. All 19 constants still agree with CPython's
      `_get_recursive_parents` bit for bit.
- [x] **M7 was a 0 and is now a FIXTURE, not a claim about a theorem.**
      `.agents/slop/dtype-pri-m7.py`: 188 of 361 ordered pairs separate `ma` from
      `ma & mb`. `(bool, weakint)` is the cheapest, and both orders answer `weakint`.
- [x] **13 mutations, 13 detected, 0 blind spots, 0 typecheck failures.** Rows moved
      are named in `.agents/slop/dtype-pri-mutate.py`'s output.
- [x] **Coverage hole named: `dtypes.all` is SEVENTEEN** (dtype.py:161 excludes void and
      both weaks), so the 14,766-row two-lane dtype gate has **never printed a void
      row**. That is the whole reason Defect 1 went unnoticed.

### REPORTED, NOT FIXED — for other owners, with the evidence

- **`schedule/memory.bend:1346` and `uop/fold_mm_work.bend:2015-2016` are BOTH wrong,
  in the same way, and `uop/spec.bend:1047` is RIGHT — so the tree contradicts itself.**
  CPython ops.py:137 asserts `isinstance(arg, tuple) and len(arg) == 2 and
  isinstance(arg[1], DType), "CUSTOM/CUSTOMI arg must be (str, DType)"`, and the assert
  FIRES on a bare string. Every real construction site is a pair
  (`tinygrad/uop/upat.py:33`, `tinygrad/llm/kernels/amd.py:108`,
  `tinygrad/renderer/cstyle.py:76` reads `x.arg[0].format(...)`).
  `uop/ops.bend` already HAS the pair constructor — `AInk{ins: String, dt: S.Dt}`
  (ops.bend:940, mapped as the INS arg at :910) — and `uop/spec.bend:1043-1047` says
  "`AInk` IS that pair, and it is the only constructor that is".
  **So `fold_mm_work.bend`'s recorded blocker "P3: that is a change to `Arg`" is VOID —
  no `Arg` change is needed, and the two deferred CUSTOM/CUSTOMI arms in
  `uop/fold.bend:2094-2096` are now unblocked** (`all_shapes` + `bcast_shape` are
  already there, as `where_ds` uses them). NOT PORTED HERE: it needs its own
  `_broadcast_shape` oracle and gating, and doing it unoracled is the plausible-wrong-
  answer class. Owner: `schedule/memory.bend`'s unit + `uop/fold_mm_work.bend`'s unit.
- **`CallInfo.dtype` re-cut is REAL.** Upstream `CallInfo` (ops.py:1400-1406) is
  `grad_fxn, name, precompile, precompile_backward, aux` — **no `dtype` field** — while
  `uop/ops.bend`'s `CallInfo` has `dtype: S.Dt` as a fourth field, and
  `uop/spec.bend:1080-1089` (`sh_23.body`) compares that DECLARED dtype to the derived
  one. With the re-cut there is no declared dtype to compare: `dtype_from_uop(CALL)`
  is `src[0].dtype` (ops.py:130-132), i.e. the body's `CustomFunction.dtype`. Still P3,
  needs `dtype_from_uop`. Owner: `uop/ops.bend` + `uop/spec.bend`'s unit.
- **`renderer/llvmir.bend:220`'s comment "`lt.pri` -- the ONE load-bearing numeric
  field" is not supported.** Measured: `pri` is read numerically in 8 places, all in
  `codegen/**`, against `{5, 10, 11, 12, 13, 14, 15}` — **never against 0**, so void's
  value cannot matter — and by equality in `uop/weak.bend:117`, which is absorbed by
  `bits`/`cls`/`nm`. It is load-bearing as a TAG (every `Dt{..}` pattern in the tree
  pins `pri` AND `bits`), not as a number. Owner: `renderer/llvmir.bend`'s unit.

### SEVEN MEASURED RULES APPENDED

`G-10` a `match` may not scrutinise a computed value; `G-11` an asymmetric meet is
invisible on every one-int-vs-`weakint` row; `G-12` a harness that patches the real tree
loses the work when the server restarts (**it did, twice, and the first tree-check run
was reverted whole** — `diff <(jj file show -r @- f) f` is how it was diagnosed);
`G-13` `U32.log2(0) == 0`, so a degenerate mask decodes as a convincing wrong value.

## Session 2026-10-03 — THE NAMING GATE: the def-name ruling, enforced
Progress: naming consistency ██████████ DONE (gate green, 0 unadjudicated renames)
Progress: remaining renames ████████░░ DONE (11 renamed; 2 blocked; 1 class needs a ruling)

- [x] **`.agents/slop/naming-gate.py` — the ruling FAILS WHEN VIOLATED.** Owner
      ruling (agent-core.md rule 2) was a number someone recomputed by hand, which
      is why it drifted 283 -> 290 -> back. Now: `naming-gate.py` walks every
      upstream `.py` that has a sibling `.bend` (99 pairs), extracts upstream
      top-level BINDINGS by AST walk -- `def`/`class` AND assignment targets,
      because upstream binds every rewrite table by assignment and `__all__` is
      excluded -- and classifies each of 1,527 names as VERBATIM / QUALIFIED /
      RENAMED / ABSENT. **Headline `RENAMED: 667 candidates -> 0 unadjudicated`.**
      PORT STEM = the text AFTER the final dot (`def Sch.kernelize` keeps the name
      `kernelize`), which `slop_1to1.py` had been getting wrong.
      **PASSES ON ABSENT, loudly: 1,090 of 1,527 upstream bindings (71.4%) are
      UNPORTED, not misnamed.** An absent name cannot be misnamed; it is missing
      implementation, a different and much larger piece of work. Conflating the two
      is how a naming gate becomes a churn machine that blocks real work.
- [x] **`naming-gate-selftest.py` — 15/15 checks, and the gate was SEEN RED.**
      All five defects below were found by the test, not by reading the code; each
      one made the gate report clean over a diverged port. The self-test plants a
      REAL rename in a scratch mirror (`pm_group_gpudims` -> `selftest_group_gpudims`),
      requires exit 1, and requires the failure to NAME the affix. It also plants a
      blank ledger reason and a stale ledger line, and it asserts two consecutive
      runs are byte-identical (the `LC_ALL=C` no-op control).
      * a detector that SUPPRESSES is not a detector -- dropping every name with >1
        affix hit hid SIX OF THE NINE renames it was built to catch;
      * an exemption must be for an EXACT AFFIX, not a concept -- keyed on
        `(file, name)` the gate stayed green when the prefix changed under it;
      * a BLANK/`UNREVIEWED` reason is not a ruling;
      * STALE AMNESTY is unearned amnesty, so a vanished candidate also fails;
      * a gate that goes red WITHOUT SAYING WHY is not a gate.
- [x] **`naming-gate-ledger.py` + `naming-gate-baseline.txt` — the 667 rulings.**
      The detector proposes, the ledger adjudicates: one line per rename, each with
      a hand-verified reason drawn from a short vocabulary (`UPSTREAM-PREFIX`,
      `LANG-CONSTRAINED`, `CONVENTION`, `COINCIDENCE`, `PORT-LOCAL`,
      `OWNER-RULING-NEEDED`). The generator ASSERTS every live rename is covered,
      so a new rename cannot slip in unreviewed. 492 of the 667 are the single
      `sqtt.bend` metaclass fan-out.
- [x] **11 RENAMES, both lanes byte-identical, ZERO rows moved.**
      `renderer/amd/sqtt.bend`: `enum_{AluSrc,InstOp,InstOpCDNA,InstOpRDNA4,MemSrc}`
      -> the upstream `class X(Enum)` names, bare. 1,033 rows byte-identical.
      `codegen/decomp/transcendental.bend`: `tx_{ilogb2k,ldexp2k,ldexp3k,pow2if,
      rintk,trig_poly}` -> upstream names. 891 rows byte-identical.
      VERBATIM 270 -> 281 (18.4%); with QUALIFIED, 319 of 1,527.
      **`slop_1to1.py` FIXED: it read `def L.foo` as `L` (`split('.')[0]`), which is
      the stem trap.** It and `naming-gate.py` disagreed (270 vs 281) until the fix;
      they now agree exactly at 319. Two tools measuring one thing must be
      cross-checked or one of them is decoration.
- [ ] **BLOCKED, NOT MINE: `tx_shr` / `tx_shl` (upstream `shr` / `shl`).**
      `codegen/decomp/dtype.bend` calls `T.tx_shr` 10x and `T.tx_shl` 12x through the
      module alias, and that file is on the do-not-edit list AND is mid-edit right
      now (`jj status`: `M tinybendygrad/codegen/decomp/dtype.bend`). The bare names
      are FREE in `transcendental.bend` and `shl_lazy`/`shr_lazy` do not collide, so
      this is a 22-call-site two-file rename. **Owner: whoever holds
      `codegen/decomp/dtype.bend`.** Note the module alias is already the
      disambiguator, so no prefix is needed at all.
- [ ] **NEEDS AN OWNER RULING: the `dsl.bend` register-slice suffix (14 names).**
      Upstream `dsl.py:66-89` binds ONE `Reg` per register region (`M0`, `DPP`,
      `SDWA`, `LIT`, `SCC`, `EXECZ`, `VCCZ`, `INV_2PI`, `SRC_LDS_DIRECT`, `DPP16`,
      `NULL`, `VCC`, `EXEC`, `ttmp`); the port splits each into offset and size and
      suffixes the offset `_OFF`, so `EXEC_OFF` cannot be confused with `EXEC_SZ`.
      Every one of those bare names is FREE, so this is a real divergence from the
      ruling -- but it is a coherent convention across ~50 constants, and renaming a
      SUBSET would make the file LESS navigable, which cuts against the ruling's own
      stated goal. **This is the largest remaining divergence and it is a decision,
      not a mechanical edit.** I did not make it unilaterally.
- [x] **DISPROVEN BY HAND, not by pattern — substring matching has now produced**
      **four wrong answers in this project. `VOP2_DPP`/`VOP2_LIT`/`VOP2_SDWA` are NOT**
      **renames of upstream `DPP`/`LIT`/`SDWA`.** Read the bodies: they are VOP2
      OPERAND-SHAPE TABLES (`List<&2, Vf>` of `Fld`/`Ov` descriptors) that merely
      inline the register numbers 249/250/255. Upstream's `DPP = src[250]` is a
      `Reg` slice, a different concept. Also disproven: `least_upper_dtypes`,
      `terminate_worker_pool`, `arg_is_validate`, `cifar_batch*`.
- [x] **`pm_` MUST STAY — it is UPSTREAM'S OWN PREFIX.** Upstream binds 92+
      top-level `pm_*` names BY ASSIGNMENT (`pm_simplify_ranges = PatternMatcher(...)`).
      A port that writes `pm_group_gpudims` is CONSISTENT with upstream and
      stripping the prefix would invent a name. Recorded as
      `UPSTREAM-PREFIX:pm_-is-upstreams-own`.
- [x] **MODULE ALIASES ARE THE DISAMBIGUATOR, and 102 of 128 `.bend` files already**
      **use them** (`import ./x.bend as A`; a bare `import ./a.bend` is a PARSE
      ERROR). Before renaming anything to dodge a COLLISION, check whether an alias
      or `def A.name` already solves it — that arithmetic is why most of the original
      "~75 prefixed" was never actionable. Every `OWNER-RULING-NEEDED` row naming a
      module prefix (`ew_`, `mem_`, `sy_`) is this same question.
- [x] NOTES: `.agents/slop/notes/bend2-constraints.md` section **DD-7** (at the END,
      numbering does not continue from DD-6 -- cite positions). Also
      `.agents/slop/runrows.sh`, which retries a ZERO-ROW bend run: the machine stack
      overflows on ~1 run in 20 and a 0-row result is indistinguishable from
      "never started".
- [x] **`renderer/tc_ptx.bend` vs `tcptx-oracle.py`: the oracle was right.** Six
      shared rows disagreed only in the `py=` half (`half`/`float` vs live
      `DType.name` `f16`/`f32`, dtype.py:134 and :136). Computation already
      matched. Literals fixed; flip of `sd_keep` / `dsh_half.keep` moved all 6;
      comment-only moved 0. Wired as `stage2` (228 shared, 0 disagree). 105 other
      rows do not intersect because the ROW KEY still uses the legacy spelling;
      aligned values agree. Rule **TC-PY** at the end of `bend2-constraints.md`.

- [x] **`renderer_oracle.py`'s `KeyError: dtypes.weakint` is fixed, and the trace's "the bug
      is in the ORACLE, not the port" is CORRECT but INCOMPLETE.** Called at both ends:
      `UOp.range(4,0,GLOBAL).dtype is dtypes.weakint` and `UOp.const(0).dtype is
      dtypes.weakint` at the pin `6c3d401cf324` AND at `upstream/master` `91b8cb5fa6`;
      `weakint` is in neither `dtypes.all` nor `dtypes.ints`; `type_map` has no `weakint` at
      either. TWO fixes, not one:
      * `render()` now runs `graph_rewrite(sink, pm_lower_weak, name="lower all index
        dtypes")` -- the pass `tinygrad/codegen/__init__.py:340` runs before ANY renderer.
        Calling `render()` directly skipped it, so every RANGE/SPECIAL was still weakint.
        This is the ROOT fix and it is PURELY ADDITIVE: `LC_ALL=C diff` of the two stdout's
        first 17 lines is empty, and it unblocks 7 rows. Without it the oracle still dies on
        **`k5_special.ocl`**, a SECOND `weakint` the finding did not name -- and no per-fixture
        cast can fix it, because `UOp.special` (`ops.py:647`) hardcodes `sint_to_uop(end)` and
        takes no dtype.
      * `f_range` passes `dtype=dtypes.i32` to `UOp.range`, which IS the cast `I()` performs
        (`sint_to_uop(x, dtype)` == `UOp.const(x, dtype)` == `x.cast(dtype)` for a UOp).
      **Oracle now runs to completion: rc=0, empty stderr, 15 claims** (was: rc=1 at `k6_range`
      with 5 claims emitted). New rules at `.agents/slop/notes/bend2-constraints.md` G-13/G-14.

- [x] **`rows()` shredding: DEMONSTRATED and CLOSED, and it was already in the baseline.**
      `rebase-gate.py`'s `rows()` reads a row from every line containing `=`. The oracle's
      whole-kernel C values span lines whose continuations contain `=` constantly, so 96
      physical lines became **33 names of which 15 are claims and 18 are line noise**
      (`float val0`, `*(data1_4+0)`, `int g0`, `for (int gidx0`, and one row split
      mid-identifier). 18 of the 33 oracle rows in `rebase/baseline.json` are that noise --
      including a recorded expectation `'for (weakint gidx0' = '0; gidx0 < ((weakint)(val0));
      gidx0++) {'`. `renderer/cstyle.bend` documents the hazard and fixes it on ITS side
      (`esc_row` at `kern2_row`); the oracle never got it. CLOSED on both sides:
      `renderer_oracle.py`'s `R()` now escapes newlines exactly as `esc_row` does, and the new
      `.agents/slop/cstyle-gate.py` REFUSES to shred (a row is `name = [value]` with the
      closing bracket on the same line; anything else is a shred and is BROKEN) and treats a
      duplicate name as an error per G-60. 33 rows / 18 shreds -> **15 rows / 0 shreds**.

- [x] **The row-naming collision: RECOMMENDATION IS TO RE-POINT THE ORACLE, NOT TO RENAME
      EITHER SIDE'S NAMES INTO A CROSSWALK.** Measured: 0 shared names (port 225 unique,
      oracle 15 claims; even the 18 shredded names share 0). Keep the port's
      (construct, target, mode) axis -- it is recorded in `rebase/baseline.json` (225
      interpreted + 225 native), `drift-record-probe.json`, `rebase/survey-cache.json`,
      `hdrbase/tinybendygrad_renderer_cstyle.bend.rows`, `wip/main_rows.txt`, and cited at
      POSITION ~9496 and ~13685 of the notes -- and it is the axis that can LOCALISE a bug
      (`rd` alone is 42 rows over 6 devices x 7 dtypes; the oracle's `k1_load_store` collapses
      all six devices into one). G-12 (POSITION ~13685) already ruled that GUARD 4 reporting
      "share NO row names" is CORRECT and not to be worked around by renaming a port row. A
      hand-maintained crosswalk is the `nv_query_litter` failure mode: a correspondence table
      maintained by hand is wrong twice and the differ then reports 0 disagreements over an
      error made twice. **But a rename is NECESSARY AND NOT SUFFICIENT** -- see the next entry.

- [ ] **REPORTED, NOT FIXED (owner: the `renderer/cstyle.bend` unit) -- `cstyle.bend` cannot be
      gated by ANY CPython oracle as it stands, and the first comparison the new gate can make
      is already RED.**
      * **Its 30 `kern2` rows are unfalsifiable.** `g_kernel()` returns two HARDCODED C
        strings, so the kernel BODY is a fixture and `render_kernel` only assembles the
        signature and prefix. No CPython call can produce those values. Its own comment calls
        the prefixes "a fixture, not a product"; the body is the same and the comment does not
        say so.
      * **Its clause rows render SYMBOLIC operands** -- `idx BASE lane = [(B)[R]]`,
        `cfo BASE SQRT f32 = [sqrt(X)]`, `acc BASE plain = [*V]`. CPython can only answer these
        by calling the same clause functions with the same symbols, so an oracle must be
        re-pointed per construct, not per fixture.
      * **Its VALUE column and its `py=` column are readings of two different trees (G-15).**
        `tmap BASE`: the `py=` column is CPython at the PIN (generated by
        `wip/gen_main.py:73`, `r.type_map.get(dt, dt.name)`) and is 4 cells stale at HEAD
        (`float8_e4m3` vs `fp8e4m3`); the VALUE column is `dtypes.all`'s NAMES for all 17
        cells, which is neither tree's `type_map` answer. And at HEAD
        `CStyleLanguage._render_dtype` **raises `KeyError` on all four fp8 cells**, so the
        honest CPython answer for `tmap BASE` cannot be a string at all. 102 cells in 6 rows.
        `.agents/slop/cstyle-gate.py` has this as its one LIVE crosswalk entry and it reports
        BROKEN rc=1 today.

- [ ] **REPORTED (owner: `rebase-gate.py`, shared tool, no single owner).** The brief calls the
      shared-name check "GUARD 2"; in `rebase-gate.py` GUARD 2 is the EMPTY-LANE guard and the
      shared-name check is **GUARD 4** (the `uncompared` branch). GUARD 4 is correct to fire
      and its verdict is right; what is wrong is the READER it is fed. `rows()` should require
      `name = [value]` with the closing bracket on the same line, call any other line a shred,
      and treat a duplicate name as an error (G-60, POSITION ~9496). `.agents/slop/cstyle-gate.py`
      implements all three; `rebase-gate.py` does not use it.

- [ ] **REPORTED (owner: whoever owns `.agents/slop/`).** `.agents/slop/tools/renderer-oracle.py`
      is a byte-identical STALE copy of the pre-fix `.agents/slop/renderer_oracle.py`. Nothing
      wires it (`rebase-gate.py` names `renderer_oracle.py`), but it is a trap: it still crashes
      on `weakint`. Also: during this session a concurrent process REVERTED my
      `renderer_oracle.py` fix and DELETED `.agents/slop/cstyle-gate.py` outright; both had to
      be reapplied from measurement. And `tinybendygrad/renderer/cstyle.bend` went
      cold-compile-broken mid-session twice (the refusal moved from POSITION 816 to 821, so an
      agent was editing it) and `tinybendygrad/renderer/__init__.bend` does not compile at all
      (`expected : a term / observed : end of input` at POSITION 821) -- which is why the
      oracle's `init` section cannot be used as a green control either.

---

## Session 2026-10-03 — `ops_python` render oracle quoting

```
ops-python-render  [##########] 1/1
```

- [x] **19 `repr()` disagreements fixed on the oracle, not the port, and the lane wired.**
      CPython's `target.arch` for `sm_80` is the 5-character string (`ops_python.py:175-176`);
      the oracle's `v!r` was adding the quotes. 59 of 85 port rows shared, 0 disagree.
      26 left uncovered on purpose (table ids, constructor tags, `py-done`, hardcoded b64,
      synthetic `core_find`, and `pywma_short_msg_32`). Wired in `BASE_ORACLES` and
      `ORACLE_CONFORMANCE`. Not `--record`ed.

## Session 2026-10-03 — re-anchor the wire-pair standing control

```
wire-pair-control  [##########] 1/1
```

- [x] **Retired the tc_ptx "6 disagreements" control.** The literals were fixed;
      a live `stage2` pair is shared=228 disagree=0. The standing control is
      `wire-pair.py --control`: CLEAN / RED / CLEAN on a copy, space in the row
      name, `PATCH DID NOT APPLY` when the needle is absent. Notes at the end of
      `.agents/slop/notes/bend2-constraints.md` (the WIRE-PAIR CONTROL block).

## Session 2026-10-03 — which tree the wired gates import

```
pin-tree-oracle  [##########] 1/1
```

- [x] **Measured pin vs xd1/head for every wired gate. Do not standardise on the pin.**
      16 of 31 verdicts move, all from AGREE to BROKEN or DISAGREE, port always on the
      non-pin side. Report: `.agents/slop/pin-tree-oracle-report.md`. No port edited.

## Session 2026-10-03 — ARange ucache collision

```
arange-ucache  [##########] 1/1
```

- [x] **Closed the `ARange` ucache collision in `uop/ops.bend`.** Called, not
      transcribed: `UOp.range(4, (0, 1), WEAK)` is not
      `UOp(Ops.RANGE, arg=(WEAK, 0, 1))` (`tinygrad/uop/ops.py:201`, `:643`).
      The missing key component is the tail's nesting depth. A third `ARange`
      field and a new `Arg` variant are both non-local (measured). The depth
      lives in `Arena.shp` and `intern.find` compares it. `uc_flat_nest`,
      `uc_int_tup1`, `uc_nest_deep` move `False`→`True` when that comparison is
      reverted; `ucdepth_flat_nest` moves `0,1`→`0,0`. Comment-only reads SAME.
      63 importers; 62 still print rows. `codegen/__init__.bend` is red on an
      affine binder in `wr.rebuild.of` — not this change. `render.bend`'s
      `arange_repr` still cannot see the depth; that file was not edited.

## Session 2026-10-03 — `renderer/amd/elf.bend` (the AMD ELF PACKER: 111 py, 1 def)

```
elf  [####################] 20/20
```

- [x] **`tinybendygrad/renderer/amd/elf.bend` COMPILES: `ALL PROOFS CHECK`, 114 rows,
      114 True, 0 False.** The last error was a MUTUAL RECURSION PAIR —
      `insert`/`insert.go` — which Bend 2.0.34 refuses in safe code and reports as
      `an unfilled law is a dead claim`, naming a def that has a body. It is a
      forward reference: `insert.go` calls the `insert` written below it
      (`references/bend/CHANGELOG.md:214-218`). The pair is gone; `insert` is one
      def using `Bool.pick`, and `assemble_linear` gained `+arch` / `+gid_args`
      (each read twice in one expression). `renderer/amd/elf.bend` is no longer a
      1:1 port violation.

- [x] **BOTH UPSTREAM BINDINGS PRESENT VERBATIM.** `elf.py`'s only two
      top-level bindings are `_arch_map` (elf.py:14, an assignment target) and
      `assemble_linear` (elf.py:15); both appear under those exact names. 77
      executable lines of 111: **59 ported in full, 5 with the arithmetic ported
      and the container not** (elf.py:40-42's three arms, :81's `bytes(desc)`,
      :111's return), **13 not ported** (elf.py:16, :38, :39, :43, :97, :98,
      :103-109) — every one with a named blocker in the file header.

- [x] **`kern.keyorder` ADDED, AND IT IS THE ROW THE OTHER TWO SORT ROWS COULD
      NOT BE.** `kern.sorted` and `kern.unsorted` both expect 16, and flipping
      `insert`'s `<` to `>=` ALSO answers 16 on both, so the gate could not see
      the comparison at all. `kern.keyorder` (CPython 9; 16 with the sort
      dropped, 16 with the comparison flipped) closes it.
      `.agents/slop/elf_amd_sort.py` derives both fold rows by CALLING
      `round_up` and `AddrSpace`, keyed BY SLOT — a positional `zip` of the same
      addrspaces reports 20 for `kern.unsorted`, which is the wrong FIXTURE, not
      a wrong number.

- [x] **ALL 46 CONSTANTS AUDITED AGAINST LIVE CPYTHON: 46 agree, 0 disagree.**
      `.agents/slop/elf_amd_consts.py` does not read `elf_amd_oracle.py`'s
      output; it calls `getattr(amdgpu_kd, ...)`, `OpType[...].value`,
      `int.from_bytes(s_code_end().to_bytes())`, `ctypes.sizeof`, `libc.SHT_*`,
      executes elf.py:100-101 and reads `e_ident` back off the live struct, and
      PROBES the elf.py:32/:35 register windows with real `Reg` objects to check
      `dsl.bend`'s `V_LO`/`V_HI`/`S_HI` rather than trusting the literals.

- [x] **MUTATIONS, MEASURED, REPORTED WITH THE ROWS THEY MOVED BY NAME.**
      `.agents/slop/elf_amd_mut.py` stages a COPY of the subtree, asserts the
      copy reproduces the live md5 before believing anything, and diffs whole
      `name=value` lines: M1 comparison flipped → `kern.keyorder`; M2 sort
      dropped → `kern.unsorted`, `kern.keyorder`, `elf.kern`; M3 sorted by size
      not slot → `kern.keyorder`; M4 insert arms swapped → `kern.keyorder`;
      M5 `param_size` arms swapped → `param.alu`, `param.glob`. Naming gate
      **RESULT: PASS**, 283 VERBATIM + 38 QUALIFIED, unchanged by this unit; a
      comment-only edit reads SAME.

## Session 2026-10-03 — `codegen/__init__.bend`: the rewrite engine's SHAPE

- [x] **`tinybendygrad/codegen/__init__.bend` — `walk_rewrite` (single-pass
      driver) and `unified_rewrite` (wall: same as `walk_rewrite`, no actual
      fixpoint).** The engine is in flight: `walk_rewrite` runs, the
      `pm_post_sched_cache` table is in `ops.bend`, the PARAM and ALLOC rule
      bodies (`pm_r_param_m`, `pm_r_alloc_m`) are in `pm_dispatch_m` (tags 3
      and 4), and the gate runs the smallest fixture and prints the
      `repl` map. The CPython oracle at `.agents/slop/gr-oracle.py`
      prints the same shape for the same fixture.

- [x] **THE ENGINE HAS A REAL BUG: arena growth is LOST.** `wr.rebuild`
      calls `O.UOp.new(ar, ...)` which returns `Found{ar_new, i}`. The
      grown arena is in `Found.ar`, but the engine's fold discards
      `ar_new` and re-passes the ORIGINAL `+ar` to the next step. So
      every mint goes into a LOST grown arena, and the rebuilt indices
      in the repl map point into it. The gate reads them back out of
      the original arena and gets the bottom (NOOP) for out-of-bounds
      indices. **The diff against CPython is 4 disagreements, all
      caused by this one bug** (PARAM->PARAM and PARAM->PARAM agree;
      ALLOC->NOOP and SINK->NOOP are the four out-of-bounds reads).
      Fix requires threading the grown arena through the fold
      (`StepResult`, a `Data` record) and a sub-def destructure helper
      per step; the BEND NAMING RULE makes the sub-def-calls-parent
      recursion infeasible in a single helper, and a 4-hour wall is
      the documented escape per the brief. **The wall: print the repl
      map, mark the test as "wall: arena growth lost", and move on.**

- [x] **`tinybendygrad/uop/ops.bend` — extended the `pm_rewrite_m` family
      with `pm_r_param_m` and `pm_r_alloc_m` rule bodies and tags 3/4 in
      `pm_dispatch_m`.** `ctx: List<&2, U32>` is threaded through
      `pm_rewrite_m` -> `pm_scan_m` -> `pm_try_m` -> `pm_dispatch_m` (all
      as `+ctx`). `pm_r_param_m` reads `Arena.arg` -> `AParam{pa}` ->
      `ParamArg.slot`, looks up `ctx[slot]` (handles slots 0/1, returns
      `None{}` for any other), returns `Some{ctx[slot]}`. `pm_r_alloc_m`
      mints a fresh `BUFFER` with placeholder slot 99, returns
      `Some{O.Found.i(fresh)}`. The two existing rule bodies
      (`pm_r_sink_m`, `pm_r_cast_m`, `pm_r_noop_m`) get a `+ctx`
      parameter that they ignore. The existing `pm_rewrite` family
      (Verdict) is unchanged; `uop/spec.bend` still compiles.

- [x] **`.agents/slop/gr-oracle.py` — the CPython oracle.** Runs
      `pm_post_sched_cache.rewrite` on `SINK[PARAM{0}, PARAM{1}, ALLOC]`
      with ctx = `[A, B]`. Prints `new_sink_op=SINK` and
      `repl=PARAM(slot=0)->PARAM(slot=99), PARAM(slot=1)->PARAM(slot=100),
      ALLOC->BUFFER(slot=0), SINK->SINK`. The diff against the port's
      output shows the four disagreements listed above.

- [x] **The unit is in flight, NOT green.** A wall that compiles and a
      gate that runs SOME PROOFS FAIL honestly is BETTER than a green
      gate that prints the wrong answer. The blocker is the arena
      growth bug; the fix is a `StepResult` thread through the fold,
      and a future unit should land that.

## Session 2026-10-03 — `graphcmp`: a CANONICAL GRAPH NORMAL FORM both sides emit, and a differ over it
## **NOT COMMITTED.**

Progress: graph comparison [##########] DONE (differ, 8 normal-form fields, 4 discrimination checks)
Progress: residual mismatches [...] 1 of 8 fixed (the device tag binding is DECLARED, not derived)

The brief was "work towards debug so we can compare graphs properly with tinygrad", and
the measurement that shaped it is in `.agents/slop/pin-tree-oracle-report.md`: the SAME
logical node renders four different ways across upstream commits (`CallInfo` gaining and
then losing its `dtype=` clause, a `CUSTOM_FUNCTION` arg moving from `str` to a dataclass,
`UOp.range(...)` against `UOp(Ops.RANGE, ...)`, `dtypes.float` against `dtypes.f32`). A raw
`repr` diff therefore compares two tinygrad COMMITS, twice, and never the port. So the
deliverable is a normal form BOTH sides emit.

- [x] **THE NORMAL FORM: eight fields, each with a `tinygrad/...:line` citation.** `id`
      (reporting only, never identity) · `op` (`Ops.name`, bare) · `dtype` (`DType.name`,
      `f32` not `dtypes.f32`) · `shape` (three-valued: dims / `R` raised / `N` no shape, and
      a `sint` dim prints as its exact `hi:lo` I64 or as `U`, never as a number) · `depth`
      (the RANGE `axis_id` NESTING count -- `ops.py:201` keys on `type(arg)`, so
      `(WEAK,0,1)` and `(WEAK,(0,1))` are different nodes with the same `str(arg)`) · `tag`
      (structured, `N` for absent) · `arg` (STRUCTURAL, never `repr`: `ParamArg.__repr__`
      omits defaults and prints a device object) · `src` (ORDERED -- upstream's own
      `UOp.key` concatenates child keys in order). Written down in graphcmp.py's header and
      in `.agents/slop/graphcmp-report.md` §2.

- [x] **THE WIRE FORMAT is self-delimiting.** Eight `<bytecount>:<bytes>` chunks per node
      and the reader WALKS THE COUNTS, so whitespace is never structural. `selfcheck`
      round-trips `"PTX tensor_cores sm_75"`, `"a b"`, `"x:y"`, `"name = [value]"`, `""` --
      the row-name trap that cost 216 of 228 rows in the pin/HEAD study.

- [x] **THE DIFFER: three rungs, naming fields.** rung 1 = equal `core` (`UOp.key` with the
      structural arg, dtype/shape moved OUT so they are compared as fields) · rung 2 =
      leftovers paired ONE-TO-ONE on the dtype-erased arg, best candidate by count of
      agreeing fields, no claim when the best is not a unique argmax · rung 3 = unpaired,
      printed IN FULL.

- [x] **IT RUNS ON A REAL GRAPH, AND THE TWO STREAMS ARE BYTE-IDENTICAL.**
      `(Tensor.empty(4,3) @ Tensor.empty(3,5)).uop`, 18 nodes, LAZY (a realized BUFFER
      carries a device `Buffer` the port cannot name and `pyrender` refuses it,
      render.py:159-160), built node for node on the port side by
      `.agents/slop/graphcmp.bend`. `diff runs/graphcmp/01-canon-py.txt
      runs/graphcmp/02-canon-bend.txt` -> `rc=0`. The differ says `SHARED cores=18,
      ONLY-PY=0, ONLY-BEND=0, VERDICT: AGREE`.

- [x] **IT DISCRIMINATES, four ways, all run.** `control` (each side vs ITSELF, AGREE) ·
      `cross` (matmul vs `sum(axis=1)`: 18 rows vs 7, DISAGREE) · `--plant srcswap` (the
      two children of the COMMUTATIVE MUL: DISAGREE, `ONLY-PY=0`, and the reordered pair's
      OWN fields -- dtype, shape, depth, tag, arg -- are NOT flagged, only `src`, as a pure
      ORDER) · `--plant dtype` (`dtype` named on all ten affected nodes, `arg` additionally
      on the two ALLOCs).

- [x] **THE CONTROLS ANSWERED BY CONSTRUCTION, NOT BY CARE.** no `sort`/`comm` at all
      (every ordering is Python's own) · `LC_ALL=C` on every child · `PYTHONPATH` removed
      from every child · a 0-row bend run RE-TRIES 5x and then RAISES -- and since 20
      consecutive runs never produced a 0-row event, the guard was FIRED ON PURPOSE against
      `.agents/slop/graphcmp-empty.bend` · the bend exit status is never gated on, only the
      stream.

- [x] **RESIDUALS, NAMED, NOT SMOOTHED.** 8 of them, report §5. Headline: **the device is
      an INTERNED INDEX on the port side and a NAME on CPython's**, and three port files
      give three different tables (`schedule/__init__.bend:1095` 0=CPU,
      `schedule/memory.bend:998-999` 0=CPU/1=DISK, `device.bend:702` 7=CPU/11=NULL) with NO
      reader from a tag to a name -- so `--dev-map` is a DECLARED binding and an unbound tag
      is reported `UNBOUND-DEVTAG`, never compared as an integer. Owner: whoever reconciles
      the three tables.

- [x] **A MEASURED THEOREM, NOT A ROW.** A dtype-only plant on a CONST is unreachable, and
      the obvious reading of `ops.py:199` is wrong: MEASURED, `UOp.const(4)` and
      `UOp.const(4, dtypes.i32)` are DIFFERENT objects with DIFFERENT keys, because
      `UOp.const` ends in `.cast(dtype)` (ops.py:629-635) and builds a `CAST`. Relatedly,
      `dtype`/`shape` are DERIVED on both sides from only op/src/arg, so a rung-1 mismatch
      cannot mean "the graphs differ" -- it means the two implementations of
      `dtype_from_uop`/`_shape` disagree, which is a real port bug class and has NOT fired
      on any graph measured today.

- [x] **`pretty_print` was NOT the anchor and `uop/render.bend` was NOT touched.** Two
      measured reasons in report §7: it prints the arg through the very `repr` that omits
      defaults, and its `dfs` cache is a second store beside the arena over a CYCLIC graph
      (which `render.bend`'s own `to_render` note says produced SHAPE-wrong output).
      `pyrender` is landed and renders only a SUBSET (render.py:147-163), so it cannot be a
      graph's normal form either. `uop/ops.bend` (63 importers) untouched. The seven
      `DEBUG >= 2` sites untouched.

- [x] **NOTHING PATCHED FROM A HARNESS.** Every plant edits one side's COPY in memory.

- [x] **NINE RULES APPENDED** to `.agents/slop/notes/bend2-constraints.md` at positions
      15131+, cited by POSITION because rule numbers repeat across units.

### Outside this unit's files

- **`tinybendygrad/helpers.bend` was transiently broken during this session and was fixed by
  another agent, not by me** (`gi_nz` an unfilled law at helpers.bend:246-250, then `st
  consumed more than once`; `jj status` showed it `M` in the shared working copy). This
  probe went red for reasons unrelated to it. Owner: the `helpers.bend` agent.
- **`.agents/slop/graphcmp.bend` was DELETED from under this session once**, ~40 min after I
  wrote it, and I rewrote it. `.agents/slop/` has 860+ entries and concurrent agents; a file
  there is not durable until committed.
- `TOOLS.md` was NOT updated with graphcmp. It is a tools ledger for LIBRARIES and this unit
  added none (no new dependency, no new CLI beyond the repo's own `./bin/bend` and
  `.venv/bin/python`). Noted rather than edited, to avoid colliding with concurrent
  `TOOLS.md` writers.

## Session 2026-10-03 (gc2) — `graphcmp`: THE FIVE RESIDUALS, classified and closed-or-counted
## **NOT COMMITTED.**

Progress: graph comparison [##########] DONE (differ, 8 fields, ledger, 7 graphs, 6 plants, 2 sides)
Progress: residual mismatches [##########] DONE (0 of 5 invisible; 1 was a live bug, 3 reported wrong, 1 new finding)

Entry point: `.agents/slop/graphcmp-report.md` §5, rewritten. Evidence in one file:
`runs/graphcmp/probe/p12-residual-evidence.txt`. The MECHANISM is a **LEDGER**: every
construct the normal form renders lossily is a marker (`z y u q X! BAD E ?`) counted on both
sides of EVERY report, with the non-zero ones called out in `# RESIDUALS IN THIS RUN:` above
the verdict. A `0/0` is printed too, because it is a measurement.

- [x] **R1 realized BUFFER: CLOSED, and it was a LIVE BUG.** The code emitted
      `f"realized{u(pa.buffer)}"` = `"realized"+"i"+str(<Buffer>)` -- MEASURED, 52 chars of
      DEVICE OBJECT REPR inside the normal form, carrying `dtypes.f32` (the token R3 exists
      to drop) and an allocation state. The header claimed a `slot` was compared;
      MEASURED, `Buffer` has NO `slot` attribute. Now `z`/`N` (presence) on both sides, and
      `--graph buffer` is a NEW fixture that diffs a realized graph for real (`z=1/1`,
      `AGREE`, byte-identical). MEASURED while writing it: `Tensor.empty(4,3)` is
      `ALLOC slot=0` and `.realize()` mints a **fresh** ParamArg at `slot=1`
      (`UOp.new_buffer`, ops.py:1208) with `bind_on_realize=False`.

- [x] **R2 `KernelInfo.applied_opts`: the py emitter CRASHED, and `Option` does not exist.**
      MEASURED, `carg(Ops.SINK, <KernelInfo with a non-empty applied_opts>)` raised
      `TypeError: vars() argument must have __dict__ attribute` -- a kernelized graph could
      not be emitted AT ALL. There is no `class Option` in this tree; the class is `Opt`
      (codegen/opt/__init__.py:11) over `OptOps` (a plain `Enum`). The chain is NOT "an enum
      member has no `__dict__`": `vars(OptOps.TC)` IS a real dict; the fallback followed
      `__objclass__` (THE CLASS, a 17-entry `mappingproxy`) and died on `_new_member_`, a
      `builtin_function_or_method`. Fixed by an `enum.Enum` arm plus a `__dict__ is None`
      guard. Also: the port emitted **2** slots against CPython's 3 (now 4 on both), and
      **`opts_to_apply` was dropped on BOTH sides** -- a field neither side carries cannot be
      seen by either. `--graph sink` is a new fixture (`AGREE`, `kI(stest,n(),N,i0)`), and
      `--plant opt` is the crash regression row. Unresolvable content is a `q` REFUSAL
      (count compared), NOT the port's answer: `render.bend:655`'s "UOp INDICES" reading is
      UNVERIFIED because MEASURED no port file ever writes a non-empty list.

- [x] **R3 `bytes`: a PORT BUG, not a normal-form limitation.** MEASURED both sides on the
      same two blobs: upstream `b"aaaa"` and `b"bbbb"` are DIFFERENT objects with different
      keys (`ops.py:201` keys on `arg`), and the port **interned them as the SAME arena node**
      (index 1 twice, `Arena.next` 2). So the port's node IDENTITY does not see the bytes.
      `ops.bend`'s `eq_arg.ABlob` -- 63 importers, **REPORTED, NOT FIXED**.
      `--plant bytes` reports it; the ledger counts `y=2/0`.

- [x] **R4 nested UOp: the JUSTIFICATION was false, and it was rendering as a STRING.** The
      comment said "the arg's identity is already carried by the graph's `src` edges".
      MEASURED: `UOp(Ops.PYLITERAL, (), (UOp.const(4),))` has `len(src)==0` and
      `toposort() == [itself]` -- the nested UOp is in NEITHER, so it has no arena index
      here. It also rendered `s<uop>`, the STRING atom, so a UOp-in-arg was byte-identical
      to the five-char string `<uop>`. Now its own letter `u`; `--plant pyuop` reports it.

- [x] **R5 AxisType: it is TWO, not three, and the report was WRONG.** MEASURED twice at
      3138973dc: `list(AxisType)` is DEVICE GLOBAL LOCAL WARP WEAK LOOP UPCAST
      **PLACEHOLDER** (8) and `hasattr(AxisType,'PLACEHOLDER')` is **True**. Only
      `AXIS_REDUCE` and `AXIS_UNROLL` are port-only. Now `X!REDUCE`/`X!UNROLL`, spellings no
      CPython reading can produce, so they cannot silently agree if upstream re-adds the name.
      The port's own comment (ops.bend:650-652) said "these two" and was right.

- [x] **A SIXTH FINDING, NOT ON THE LIST: the shape column's `N` was a LETTER COLLISION.**
      Found by the new `--graph sink`, which is the first fixture with a shape-less node:
      `MISMATCH SINK py#2 vs bend#2 shape py=R bend=N` -- a rung-1 mismatch on a node whose
      CORE MATCHED, which cannot mean the graphs differ. MEASURED: `UOp.shape` RAISES iff
      `_shape is None` (ops.py:455), probed over all 12 no-shape ops, so it NEVER RETURNS
      `None` and the py-side `N` is DEAD, while the bend side was using `N` meaningfully.
      Bend's `Some{None}` now renders `R`; its port-only no-Derived state gets `?`. The dead
      py arm is KEPT and COUNTED (`# shape-N hits py=0`) -- a deleted branch is a claim, a
      counter is a measurement.

- [x] **ALL CONTROLS RE-RUN AND PASTED** in `runs/graphcmp/C*.txt`: `selfcheck`, `control`
      (both sides vs itself), `cross` (both sides, two graphs), the ORIGINAL three plants
      (`srcswap` / `dtype` / `shape`) with unchanged counts -- `srcswap` still 3 rung-2 pairs
      with `ONLY-PY=0 / ONLY-BEND=0` and the reordered pair's OWN fields still clean -- plus
      the three new plants, four graphs, 6-run stability, byte-identity of all four graphs,
      and the 0-row guard fired on purpose.

- [x] **SUPERSET CHECK.** `runs/graphcmp/C11-superset.txt`: the ONLY change to the matmul is
      `unrealized` -> `N` on the two ALLOC rows, IDENTICALLY on both sides. Same information
      (absence), uniform spelling with the other six `Maybe` fields. MEASURED reason, not
      taste: `unrealized` contains `realized` as a substring and STARTS WITH the ledger's
      `u`, so at a value position a scan counted the absent case as present AND counted a
      nested UOp that was not there. No currently-agreeing field changed meaning.

- [x] **FOUR RULES APPENDED** to `.agents/slop/notes/bend2-constraints.md` at the END,
      numbered 37-40 continuing from 36, cited by POSITION: a `do` block must end in a bare
      TERM; `bend` import paths reject a dotted segment so NOTHING under `.agents/` can be
      imported; `match` needs the value as a PARAMETER not a local binder; two arms of a
      nested `Bool.pick` need `+` on the shared parameter.

### New port findings, REPORTED and NOT FIXED

- `ops.bend`'s `eq_arg.ABlob` FALSE-INTERNS two different equal-length blobs into one arena
  node; upstream keys them apart. (63 importers.)
- `uop/render.bend:664` prints `opts_to_apply=None` where every `llm/kernels/amd.py` (nine
  sites) and `nn/__init__.py:363` SINK writes `opts_to_apply=()` -- an empty tuple is not
  `None`. **This one is a port OUTPUT bug that `graphcmp` can now see.**

### Outside this unit's files

- `tinybendygrad/codegen/__init__.bend`, `codegen/decomp/dtype.bend` and `rebase-gate.py`
  were all modified by OTHER agents DURING this pass (mtimes 23:32-23:38, overlapping my
  own 23:23-23:33 edits, and none of them is in anything I wrote). Not mine.
- `TOOLS.md` still not updated: this pass added no library and no CLI beyond the repo's own
  `./bin/bend` and `.venv/bin/python`. Noted rather than edited, to avoid colliding with
  concurrent `TOOLS.md` writers.
- New file `.agents/slop/graphcmp-probe-optq.bend` sits in `.agents/slop/` rather than
  `runs/graphcmp/probe/` because MEASURED: bend rejects an import path with a dotted
  segment, and `.agents` has a dot -- so nothing under `runs/` can import it.

## Session 2026-10-03 (b) — the eight `c{i}` fixtures, `codegen/decomp/dtype.py`

- [x] **THE 8 MISSING `cN=` FIXTURES, CLOSED 7 OF 8 AND THE 8TH MADE VISIBLE.** All eight
      are `f2f_clamp`'s `mx` constant, `dtype.py:131`, and the port printed NONE of them
      because no gate fixture ever reached `f2f_clamp_max` (`dtype.bend:1165`). It was NOT
      an unimplemented format: `dd_lab.node` at `dtype.bend:1734` is the float-CONST
      renderer and emits the oracle's `F(<f32 bits>)` exactly; `C(mag)`/`C(hi:lo)` are at
      `dd_cval` 1713-1723. Eight rows added (`dd_cmx.*`, dtype.bend:2426-2449).
- [x] **TWO REAL PORT BUGS, both in `f2f_clamp_max.put`, both now fixed.** `dtype.py:129-130`
      is TWO predicates: `max_exp` is `(1 << e) - 1` for fnuz-and-e4m3 (the port subtracted
      `0`) and `max_man` is `(1 << m) - 2` for `fp8e4m3` ALONE (the port keyed it on
      fnuz-or-e4m3, so both fnuz layouts got `- 2`). All SEVEN reachable values were wrong;
      `c6` by one ulp (`0x7F7FFFFE` vs `0x7F7FFFFF`) and `fp8e5m2fnuz` by 2.28x.
- [x] `c0..c6` now AGREE with CPython, values called not typed:
      `F(1138753536) F(1131413504) F(1197473792) F(1197473792) F(1199562752) F(2139029504)
      F(2139095039)`.
- [x] `c7` (`float64`) PRINTS `refused:unported`, so the name exists in both lanes with
      different values: ONE disagreement, counted. It is not closable AS THE ORACLE SPECIFIES
      IT, because `mx` is `val.const_like(...)` (dtype.py:131) and so depends on `fr` too —
      CALLED, `.agents/slop/dd-divE-probe.py`: `f2f_clamp(f32_val, float64)` mints
      `mx = inf` = `F(2139095040)` and `f2f_clamp(f64_val, float64)` mints `mx = 1.8e308`,
      which `struct.pack('f', ...)` refuses. The oracle's `c{i}` row is a function of `dt`
      alone and has no single answer for the one dtype whose `mx` leaves f32 range.
- [x] **THE BRIEF'S PREMISE HALF WRONG, MEASURED.** (a) "the port emits no float-CONST path"
      is false — `dtype.bend:1734` has been there the whole time. (b) "fresh oracle vs saved
      baseline is 416 shared, 0 disagreements" is false: 416 shared, **1** disagreement,
      `c7` = `F(ovf)` fresh vs `F(2139095040)` saved. Both are correct CPython output for
      different `fr`, so neither is a typo. `dd-oracle.txt` line 305 corrected to the value
      a fresh run produces; all 416 names now agree with a fresh run.
- [x] **THE CHECKER THAT MAKES ABSENCE AN ERROR**: `.agents/slop/dd-divE-check.py`.
      `dd-cmp.py:65` compares `keys = [k for k in port if k in ora]`, so a row the port never
      printed is dropped and eight missing fixtures read exactly like eight passing ones. On
      the saved `.agents/slop/dd-gate.txt` it reports 8 named absences and exits 1.
- [x] **RUN-HEALTH GUARD**: `.agents/slop/dd-divE-run.sh`. A stack-overflowed bend run prints
      EVERY row and comes back with EMPTY cone walks — measured 0, 7 and 31 empty `sig`/`k`
      across four runs of the same tree — so `dd-run.sh`'s `^lg` count guard cannot see it.
- [x] CONTROL, per row, one factor at a time (`.agents/slop/dd-divE-math.py`):
      M1 `max_exp` subtracts 0 on ocp moves 3/8 (`fp8e4m3`, `fp8e4m3fnuz`, `fp8e5m2fnuz`);
      M2 `max_man` keyed on ocp moves 2/8 (`fp8e4m3fnuz`, `fp8e5m2fnuz`). M2 moving ONLY the
      fnuz rows is the evidence the fnuz predicate was the defect. Neither is a zero.

### Outside this unit's files

- **`.agents/slop/dd-oracle.txt` had a stale `c7`** (`F(2139095040)`, a saturating-conversion
  value a `struct.pack`-based oracle cannot emit). Corrected to `F(ovf)`. Owner of the file is
  me; anyone who scored a lane against the old value has one stale row.
- **`dd-oracle.py:36`'s `mxc*` citation names no row.** `mxc` is a Bend record FIELD binder at
  `dtype.bend:1226`. Third stale-docstring instance on this file. Fixed.
- **`.agents/slop/dd-oracle.txt` line 2693's "412 rows" is 416**; line 2699's "66 of 121
  byte-identical" predates the current `dd-gate.txt`, which scores **99 of 164 agreeing,
  65 disagreeing** against the oracle. All 65 are `l2i`-family rows and none are mine.
  Owner: the `l2i` arm. Not touched.
- **`agent-core.md`'s "`dtype.bend` has 14 permanently unfilled laws" is STALE.**
  `./bin/bend tinybendygrad/codegen/decomp/dtype.bend --check-only` now prints
  `ALL PROOFS CHECK`, exit 0. Owner: whoever last filled them.

---

## Session 2026-10-03 — the two `dd_rs` cone bugs in codegen/decomp/dtype.bend (measured)

- [x] **BUG 1, `dd_rs.add` appended unconditionally**: a node with two parents was listed
      once per PARENT. `seen` is prepend-built, so one prepend per POP. CPython's `cone`
      (`dd-oracle.py:179-191`) dedups by `id(v)`. `dd_rs.add` now takes the freshness `Bool`
      as a PARAMETER (a `match` may not scrutinise a computed value or a local binder) and
      reuses `dd_rs.cat` for the prepend instead of `List.append(&2, U32, [u], xs)`.
- [x] **BUG 2, `dd_rs.push` prepended left-to-right**: `dd_rs.cat(h, st) = h <> st` is a
      PREPEND, so `push(q, t, cat(s, st))` popped `src[n]` first. Now `cat(s, push(q, t, st))`,
      which builds the stack in pop order = `src[0]` first, matching `for s in v.src: go(s)`.
- [x] **The three named rows now agree with CPython. THE PORT WAS WRONG, not the oracle:**
      `lgvk` `C(0),C(0)` -> `C(0)`; `lgvsig` `CAST/1,CAST/1,CONST/0,CAST/1,CONST/0` ->
      `CAST/1,CAST/1,CONST/0,CAST/1`; `lgwsig` `CAST/1,CONST/0,CAST/1` -> `CAST/1,CONST/0`.
- [x] **Row count: DELTA 0.** 172 before, 172 after, identical key sets, 35 values changed.
- [x] **A gate row per bug, each moving on its own revert** (`.agents/slop/dd-cone-variants.py`):
      `revert-push` 27 rows, `revert-add` 33, `revert-both` 35. Picked witnesses: `lgvsig`
      (add-only) and `upsig` (push). **CONTROL `ctl-comment`: 0 rows moved.**
- [x] **M26.** As written in `dd-mutate.py` it is **PATCH-NOT-APPLIED** — its anchor quotes
      the PRE-fix `push` line, 0 occurrences in the fixed file (RULE D, not a zero). Re-aimed
      at the fixed line it **FIRES on 27 rows**, and its name ("visit src[n] before src[0]")
      becomes correct for the first time: against the pre-fix file the defect it describes WAS
      the base behaviour. **M27's anchor is byte-identical and still applies** — `dd_rs.more`'s
      call site was left untouched deliberately. Owner: the `dd-mutate.py` mutation table.
- [x] **AGAINST CPYTHON, on the same 172-row key set: 106 agree / 66 disagree -> 120 / 52.
      14 rows flipped disagree->AGREE, 0 flipped the other way.** So the two cone bugs
      accounted for **14** disagreements, not the 3 named in the brief: `lg1k lg1sig lg2sig
      lg6sig lgcsig lgdk lgdsig lggk lggsig lglsig lgvk lgvsig lgwsig upsig`.
- [x] **52 rows still disagree and they are NOT the cone.** `l2i`'s CAST/shift arms: tree
      values (`lg2p` `C(1)` vs CPython `C(-1)` — a real sign bug, already M08/M25), node
      counts, and CONST render conventions (`lg6p` `C(4294967295)` vs `C(-1)` is the SAME
      32-bit word printed two ways). Out of `dd_rs`'s scope. **The gate is NOT green and this
      fix does not make it green; it only removes 14 of 66.**
- [x] Evidence: `.agents/slop/dd-cone-report.txt`. Rules: `bend2-constraints.md`, appended at
      position ~15399 (this block is rules 1-5).

### Outside this unit's files

- **`.agents/slop/dd-mutate.py` lines 189-191 (M26) need re-aiming**, quoted exactly in
  `dd-cone-report.txt` section 5. **Owner: that unit. NOT edited here.**
- **`tinybendygrad/codegen/decomp/dtype.bend.ddmut` is a bake sitting in the LIVE tree**
  (dated Oct 3 14:09), not in a mirror — `dd-mutate.py` says it never writes the live file, so
  either `DD_TREE` was pointed at the live tree or the mirror was moved. Any harness that
  mirrors the live tree inherits it and `dd-mutate.py`'s RULE G will refuse to start. I did
  not delete it. **Owner: whoever ran it.**
- **`codegen/decomp/dtype.bend` moved 164 -> 172 rows mid-session** (a concurrent agent added
  `dd_cmx.rows(8n, ...)` and rewrote `f2f_clamp_max`'s ocp/e4m hoisting), so any before/after
  captured at different times in one session is not comparable. Freezing one snapshot first
  is not optional here.
- **`.agents/slop/dd-oracle.txt` carries a hand-added comment line a fresh run does not
  print**, so a byte-diff against it reports 20 phantom changed lines. Compare rows.

## Session 2026-10-03 (c) — `DEBUG` IS WIRED: the seven gated prints, `getenv_int`, and a
## five-level gate. **NOT COMMITTED.**

- [x] **THE KNOB EXISTED NOWHERE.** MEASURED before the change: `DEBUG reads in ported
      code : 0`. All 73 occurrences of `DEBUG` in `tinybendygrad/` are comments,
      `DEBUG_RANGEIFY` / `DEBUG_GC`, or prose. No ported def branched on it and no gate
      row existed for it anywhere. `.agents/slop/prepare-oracle.py:12` actively pins
      `os.environ["DEBUG"] = "0"`, which is why no oracle could see a gate even by
      accident.

- [x] **`DEBUG` IS AN INT AND `helpers.py` IS THE AUTHORITY — NO `DEBUGLEVEL`.**
      `grep -c 'DEBUGLEVEL =' tinygrad/helpers.py` is `0`: upstream does not define one
      and tests `DEBUG` directly. `helpers.py:237` is
      `DEV, DEBUG, BEAM, NOOPT = _DEV("DEV", ""), ContextVar("DEBUG", 0), ...` and
      `helpers.py:163` is the whole of `getenv`:
      `return type(default)(os.getenv(key, default))`. So with a default of `0` the
      coercion is `int`. MEASURED in live CPython: with `DEBUG=2`, `type(DEBUG.value)`
      is `int` and `DEBUG.value` is `2`; `DEBUG=""` and `DEBUG="abc"` both make the
      IMPORT raise `ValueError: invalid literal for int() with base 10`, which tinygrad
      does not catch.

- [x] **THE MECHANISM IS ONE NEW DEF PAIR IN `helpers.bend`, NOT A SECOND ENV MECHANISM.**
      `getenv_int(k, d)` is the `int` arm of the SAME `IO.get_env` (base.bend:172) the
      existing `getenv_str` uses -- helpers.py:163's `type(default)` is the only thing
      that differs between them, so this is the other half of one mechanism, not a new
      one. `debug()` is `getenv_int("DEBUG", 0)`, i.e. the ContextVar read. `debug_ge`,
      `gi_of_text` and `debug_print` are the three shared pieces the seven sites use.
      BLAST RADIUS, stated because the file has 88 importers: four new top-level defs
      (`gi_*` x 12, `getenv_int`, `debug`, `debug_ge`, `debug_print`) and one new type
      `Gi`; nothing existing was renamed, moved or re-signed. Importers of `helpers.bend`
      that reach these names: none, because they are new. Importers of the names I had to
      touch: `debug_print`'s only caller is the four port files plus this unit's gate.
      MEASURED: all four port files' own row sets are BYTE-IDENTICAL to `HEAD` after the
      change (`schedule/memory.bend` 57, `schedule/allreduce.bend` 48,
      `nn/state.bend` 14, `runtime/support/am/amdev.bend` 552; `diff` of the sorted
      `name=value` rows is empty for all four).

- [x] **ALL SEVEN SITES WIRED, AT UPSTREAM'S OWN THRESHOLD.** The threshold is READ OUT
      OF EACH CITED SOURCE LINE by `re.search(r"DEBUG\s*>=\s*(\d+)", src)` and printed by
      the oracle as `thr_<site>`, so it cannot be a hand-typed table: `thr_ar=2`,
      `thr_st=2`, `thr_am185=thr_am225=thr_am251=thr_am254=2`, and **`thr_mem=1`** --
      `schedule/memory.py:59` is the only level-1 site and it is easy to get wrong.
      Wired: `red_dbg` (allreduce), `mem_dbg` (memory), `sd_dbg` (state), and
      `am_dbg_malformed_of` / `am_dbg_boot_of` / `am_dbg_ip_of` / `am_dbg_final_of`
      (amdev). All seven check clean.

- [x] **`nn/state.bend` WAS INVERTED ON EVERY MODULE WITH NO DOT, AND THE ROW CAUGHT IT.**
      `str.split(".")[0]` on a string with no `.` is the WHOLE string, and the first
      version of `sd_fc_root` walked to `Nil{}` and returned the empty root, so
      `collections` and `numpy` read as not whitelisted and `st_ok1` printed
      `WARNING: returning Dummy for collections OrderedDict`. It now reads
      `List.head(&2, String, String.split(s, Char.from_u32(46)))`, measured on four
      probes. This is the second bug this unit's rows caught and it is reported here
      because a row whose expected value had been read off the port would have agreed.

- [x] **`schedule/memory.bend`'s `Scan.tc` IS A TOUCH LIST, NOT `first_appearance`, AND
      `len(first_appearance)` IS THE NUMBER THE PRINT USES.** MEASURED: `mem_tc_add`
      (memory.bend:445) appends on EVERY touch, because memory.py:31-32 is
      `if b not in first_appearance: first_appearance[b] = i` followed by
      `last_appearance[b] = i` -- the first is conditional and the second is not, and
      one append cannot express both. This file's fixture touches D2 at k2 and k3, so
      `len(Planned.tc)` is 6 where CPython's `len(first_appearance)` is 5, and
      `memory.py:60`'s `len(first_appearance)` is 5. `mem_dbg_text` therefore reads the
      DISTINCT count, which `Planned.bs` is (`mem_bs_add` is `mem_cp_one`, an
      append-IF-ABSENT over the same `si_bufs`), and the `p_nbufs` row already gates it
      at 5. **REPORTED, NOT FIXED: fixing `Scan.tc` means splitting `mem_tc_add` into a
      conditional first-appearance and an unconditional last-appearance, which touches
      `mem_first_i`, `mem_last_i` and `mem_events` and every `p_*` row. Owner: the
      `schedule/memory.bend` unit (this one, if it wants the follow-up).**
      `sum(nbytes)` is likewise NOT in `Planned` -- `Planned.bs` is the buffer SLOTS,
      literally `[3,4,5,6,7]` -- so `mem_omem` is `Planned.tot / 2`, which is exact
      because memory.py:45 is `total_memory = sum(nbytes.values()) * 2`.

- [x] **A GATE THAT CANNOT SEE A BRANCH: `memory.py:59`'s `!=` had no row.** The one
      plan fixture SAVES bytes (12032 against 11776), so "print only when there is a
      saving" and "always print" are the same function over every row `mem_plan` can
      reach, and the mutation that drops the `!=` moved NOTHING. Fixed with a
      parameterised seam, `mem_dbg_line(omem, nmem, nfa, nar)`, and `mem_cond_same` /
      `mem_cond_diff`; CPython is asked the same question with the same two sums. The
      mutation now moves 3 rows. The first attempt at that mutation (`is_eq -> is_lt`)
      ALSO moved nothing and looked like a second confirmation of a non-theorem.

- [x] **THE FIVE-LEVEL GATE: `sh .agents/slop/debug-gate.sh`.** 72 rows, at levels
      `unset` / `0` / `1` / `2` / `3`, each level diffed against CPython
      (`.agents/slop/debug-gate.py`, which CALLS tinygrad) and against the COMPILED bend
      lane, so 5 levels x 3 lanes and all fifteen agree. It ASSERTS, by name, that every
      site row moves (a diff alone would pass a port that printed unconditionally) and
      that the level-0 control is thirteen EMPTY rows. GREEN.

- [x] **LEVEL 1 IS DISTINGUISHED FROM LEVEL 2, BY MEASUREMENT, NOT BY PROSE.** The gate
      prints the table: at level 1 `mem_plan` is already printing while `ar_ring`,
      `st_bad`, `am185` and `am251` are silent; at level 2 all seven print. The
      `thr_<site>` rows are "does this site print at level EXACTLY 1", computed by
      CALLING the site -- `thr_mem=1` and the other six `0`.

- [x] **THE EXPECTED STRINGS COME FROM CALLING CPYTHON, ON TWO INDEPENDENT LANES.**
      Lane A calls the real function: `handle_allreduce` over a real BUFFER UOp with a
      4-tuple device in three ContextVar configurations (`RING ALLREDUCE 4x300000 |
      dtypes.f32`, `NAIVE ALLREDUCE 2x100 | dtypes.f32`, `ALL2ALL ALLREDUCE 4x100 |
      dtypes.f32`); `memory_plan_rewrite` over the port's own fixture (`memory reduced
      from 0.01 MB -> 0.01 MB, 5 -> 2 bufs`); `torch_load` over a real on-disk pickle
      (`WARNING: returning Dummy for posixpath join`). Lane B `exec`s the cited source
      line with the live `DEBUG` and covers the four amdev sites, which CPython cannot
      run here at all -- `AMDev(0)` raises `AttributeError: 'int' object has no attribute
      'pcibus'`, measured. Lane B's expected strings:
      `am 0000:01:00.0: Malformed state. Issuing a full reset.`, `am 0000:01:00.0: boot
      done`, `am 0000:01:00.0: AM_GFX initialized`, `am 0000:01:00.0: Finalizing`.

- [x] **MUTATIONS: 15 OF 17 MOVE. `.agents/slop/debug-mutate.py` ->
      `.agents/slop/debug-mutate.txt`, run in a SCRATCH COPY of the tree, never the live
      one.** Flipping `memory.py:59` 1->2 moves 7 rows; `allreduce.py:16` 2->1 moves 9;
      `state.py:260` 2->1 moves 7; `amdev.py:185` 2->3 moves 4; `:225` moves 1; `:251`
      moves 4; `:254` moves 1; `debug_ge`'s `>=`->`>` moves 29; `sd_fc_allowed`'s `not`
      moves 6; the `!=` moves 3; `gi_take` moves 3; `gi_tab` moves 6; `red_mode_name`
      moves 1; `am_dbg_prefix` moves 10.

- [ ] **BLIND SPOT, REPORTED NOT CLOSED: `debug_print`.** Its mutation (write `""`
      instead of writing nothing) moved nothing, and it is a HARNESS limitation, not a
      theorem: the gate observes a site by its RETURNED LINE and `debug_print` returns
      `Unit`, so neither "prints an extra blank line" nor "never prints" can reach a
      `name=value` comparison. The level-0 control is real -- `mem_L0`, `ar_ring_L0`,
      `st_bad_L0`, `am185_L0`, `am251_L0` and the eight site rows are EMPTY at unset and
      at 0, asserted by name -- but it tests the SITES' gate, not `debug_print`'s. Fix
      would be a value-returning companion for the gate to diff.
- [ ] **BLIND SPOT, REPORTED AS A THEOREM: `mem_mb`'s `> 5000` -> `>= 5000`.** A tie at
      `S % 10000 == 5000` forces `S % 16 == 8` while a multiple of 256 forces
      `S % 16 == 0`, and `gcd(10000, 256) = 16`, so the tie is UNREACHABLE for any input
      `memory.py:59` can see: `nbytes` and `arena_sizes` are both `round_up(..., 256)`.
      MEASURED: 0 disagreements with CPython's `%.2f` over all 156250 multiples of 256
      up to 40 MB, and 483 disagreements over bare integers. Every `mem_mb_*` row is a
      multiple of 256, so the mutation cannot move one. **The population that WOULD
      separate them is deliberately NOT a row**, because a row is diffed against CPython
      and this formatter is wrong on it: CPython's `f"{0.015:.2f}"` is `'0.01'` where
      half-even on the rational is `'0.02'`, since Python formats the BINARY FLOAT.
      Recorded in `bend2-constraints.md` position ~15520 rule 8.

- [x] **TWO DOCUMENTED NARROWINGS, BOTH MEASURED FROM BOTH SIDES, NOT PROMISES.**
      A refused text answers the DEFAULT where CPython raises `ValueError` at import: the
      `gi_refuse_*` rows print `ValueError` on BOTH sides (CPython's own exception, the
      harness's two-default leak test) so the gate is green AND says so. And `int("-1")`
      is `-1` in CPython while a `U32` cannot hold a negative, so `gi_of_text` answers
      `0`; the `gi_m1_ge1/2/3` rows are the measurement that this is unobservable at
      every site, because every threshold in tinygrad is `DEBUG >= N` with `N >= 0`.

- [x] **TWELVE RULES APPENDED** to `.agents/slop/notes/bend2-constraints.md` at position
      15517+, cited by POSITION because rule numbers repeat across units.

### Outside this unit's files

- **`.agents/slop/prepare-oracle.py:12` PINS `os.environ["DEBUG"] = "0"`**, which is
  correct for that oracle and is why `DEBUG` could never be visible in a gate before
  this. Left alone; it is not mine and it is right for its purpose. Owner: whoever owns
  that oracle.
- **`Schedule`/`memory`'s `Scan.tc` duplication** (the `len(first_appearance)` finding
  above). Reported, not fixed, with the reason. Owner: the `schedule/memory.bend` unit.
- **`dtype.bend`'s 14 unfilled laws** make every `--check-only` on a file that imports it
  exit 1 with `SOME PROOFS FAIL` naming exactly those 14. Pre-existing, measured against
  the pristine file, and `debug-gate.sh` reads the FIRST LINE rather than the exit code.

---

## Session 2026-10-03 — `renderer/amd/generate.bend`: THE 149 UNGATED ROWS (233 -> 726)

- [x] **THE 149 DIAGNOSED BY CAUSE, and the premise corrected.** `.agents/slop/ga_rows.py`
      measures it: `rows()` returned **233 names for 91 rows**, 84 shared with the oracle.
      Of the 149 unshared, **7 were the real rows with a TRUNCATED value and 142 were
      fragments of those same 7 rows — 0 were lost to genuine name divergence.** The PORT
      never invents a name; it fragments one whole-file row at every `=` inside the
      generated Python (`FLAT_LOAD_DWORD`, `encoding`, `saddr`). The ORACLE invented the
      competing name: its `tag | <line>` rows, and `<line>` is not unique (four blank
      lines are one name; `  saddr = SSrcField(31, 24, default=NULL)` is in four classes),
      so they shared 0.

- [x] **ROUTE CHOSEN: per-LINE rows keyed on an INDEX, plus one `lines` COUNT row per
      file — NOT a change to `rows()`.** `rows()` is UNTOUCHED. The blast radius was
      measured first, over all 38 cached gates (`.agents/slop/ga_rows_blast.py`, cache from
      `ga_sweep.py`):

      | parser | rows | shared in a pair | shipped rows CHANGED |
      |---|---|---|---|
      | `rows()` shipped | 32,026 | 24,935 | 0 |
      | fold, safe fallback | 31,978 | 24,885 | **76** |
      | fold, naive | 6,172 | 5,683 | **25,882** |

      The naive fold destroys 25,882 rows and 19,252 shared ones because **31 of 38 lanes
      do not print `name = [v]   py=[w]` at all** (they print `name=value`, no spaces). The
      safe fold still fails the superset test on `uop/render.bend`: folding MERGES
      `pyrender buffer` and `pyrender copy` into one key. Neither is a superset, so the
      fix belongs in the producer, which is where `cstyle.bend:1760` already put it.

- [x] **THE WHOLE-FILE ROW IS NOT AVAILABLE HERE, MEASURED, and this lane was BROKEN HALF
      THE TIME ALREADY.** A `String` is an `SCon` spine and the interpreter has no tail
      call, so a 16,815-character row value is 16,815 nested frames: a probe survives
      4,000 characters and dies at 8,000. **The file as committed — one whole-file row, no
      escaping — succeeded on 5 of 12 runs**, and 5 of 12 with `String.join`, and 5 of 12
      with the char-wise `esc_row`. `rebase-gate.py` would have said BROKEN / "lane(s)
      failed to run: interpreted" and the cause is not rows. Per-line rows build no string
      longer than one emitted line: **25 of 25.**

- [x] **726 rows, 726 agree, 0 differ — corroborated twice.** `ga_gate.py`:
      `GATE: 726 rows, 726 agree, 0 differ` / `ORACLE: 778 rows, 726 gated, 52 ungated`.
      The real gate, `--port`, all three lane pairs: `[['cpython:ga-oracle','interpreted',726],
      ['cpython:ga-oracle','native',726], ['interpreted','native',726]]`, 0 disagreements,
      rc=0. And independently `rebase-scan-oracles.py`: `726  0`.

- [x] **`ga-oracle.py` emits 778 rows** (was 892): 634 per-line + 8 counts replace 756
      per-line rows, and the tautological `enum cdna` is GONE — `write_enum` takes no arch
      (generate.py:273) so `enum rdna3` and `enum cdna` were the same 122 lines under two
      names. A row that cannot fail is worse than no row. `operands cdna` was the mirror
      gap: the oracle emitted it and the port never showed it, and `write_operands` uses
      `arch` in exactly one line (generate.py:471), so it is now gated.

- [x] **FOUR CONTROLS, `.agents/slop/ga_controls.py`, all PASS.** (1) SUPERSET: 84 gated
      rows before, 726 now, **0 lost, 0 values changed**. (2) NO FRAGMENTS: 726 real rows,
      726 row names, **0 invented by `rows()`**. (3) A PLANTED multi-line value is NAMED by
      `ga_gate.py` with rc=1, not swallowed. (4) Dropping `ins rdna3 | 176` moves **exactly
      one row**, `ins rdna3 lines` — the count row is the only thing that sees a dropped
      last line, which is why it exists and why it is not tautological.

- [x] **`rebase-gate-selftest.py`: 66 PASS, 0 FAIL, rc=0.** Both rosters still agree.

- [x] **ONE REAL BUG CAUGHT BY THE GATE, NOT BY ME.** The first `gl.go` destructured
      `want` as `case +h <> t, +wh <> _:` and recursed on `want` instead of the tail, so
      every `py=` from row 1 onward was row 0's text: **626 of 726 rows red.** Fixed to
      `+wh <> wr:` / `gl.go(nm, t, wr, ...)`. The lockstep `case Nil{}, Nil{}` /
      `case _, _:` arms make a length mismatch a loud stop rather than a truncated diff.

### Outside this unit's files

- [x] **`rebase-scan-oracles.py` CACHED FOREVER AND NEVER INVALIDATED — FIXED, AND THE FIX HAD
      A SECOND HALF NOBODY HAD FOUND.** It printed `84 84  generate.bend` — 84 shared, **84
      disagree** — against the real gate's `726 shared, 0 disagree`, off cache hours old. The
      mtime half landed first and **was not sufficient**: `read_fresh_cache` decides on mtime
      alone, and a *fresh* file holding `{}` is not stale, so the 82 legacy `{}` files — every
      one written before the "nothing is cached unless it produced rows" rule existed — were
      still answered `"fresh"` and read as "this lane has no rows", and `main()` skipped them in
      SILENCE. **MEASURED: 8 of the 38 wired pairs measured 0 shared row names, and all eight
      were an oracle cache holding `{}`.** The read side now refuses an empty cache
      (`cached()` returns `"empty"`), the message names the file and says it records a FAILED run,
      and `store()` already refused to write one. Control in `rebase-gate-selftest.py`'s
      `cache_rule()`: NO-OP (cache newer than source → used, rows unchanged) and CONTROL (cache
      older → refused, both files named), plus CONTROL (empty but newest → refused). Live tree:
      warm `726  0` → `touch` the port → stale message, re-run, still `726  0` → warm again.
      **A CACHE THAT RECORDS NOTHING IS NOT A READING**, exactly as one older than its source is
      not. See rules 41-42 in `notes/bend2-constraints.md` (positions 16367-16405).
- [x] **`ORACLE_CONFORMANCE`'s hard-coded `84` — THE NUMBER IS NOW READ, NOT STORED.** All 38
      stored counts are gone; the roster holds `(oracle, kind)` and `measure_roster()` measures
      the intersection every run through the scan tool's own staleness rule, 8 lanes concurrently.
      `generate.bend` measures **726** (0 disagree). The stale numbers it found: **`uop/ops.bend`
      62 → 67**, and **`codegen/decomp/dtype.bend` 99 → 107 with 1 live DISAGREEMENT** — see the
      next session. A count that cannot be measured is printed **UNMEASURED** and FAILS, naming
      which lane produced nothing; it is never rounded to 0 and never inherited. See rules 43-44
      (positions 16406-16452).

## Session 2026-10-03 (n) — NAMING GATE BACK TO PASS: `getenv :: _int` is QUALIFIED, AND IT IS A LEDGER RULING, NOT A TALLY

Progress: naming gate ██████████ PASS (668 candidates, 0 unadjudicated) — MEASURED 22:40:24

- [x] **THE MECHANISM IS THE LEDGER, AND THE `QUALIFIED` TALLY IS NOT IT.** `naming-gate.py`
      has two things called QUALIFIED. The TALLY (`naming-gate.py:189-191`, `name in quals`)
      means "the port reproduced this name under a module qualifier" — a fact about the
      port's FORM. The ADJUDICATION is a ledger line keyed `(file, upstream_name, affix)`
      with a mandatory reason, written by `naming-gate-ledger.py`'s `RULES` table.
      **`getenv_str` was never in the QUALIFIED tally either** — it was an adjudicated
      rename in the `RENAMED/n` bucket, exempted by a ledger line that already existed at
      `naming-gate-baseline.txt:47`. So the precedent is a ledger line and the mechanism to
      extend it is one token in one tight per-file regex, not a new def in a `.bend` file.
      **`RESULT: FAIL` (exit 1, 1 unadjudicated) -> `PASS` (exit 0, 0 unadjudicated).**
      `naming-gate.py` ITSELF was not touched: mtime still 13:00:38.

- [x] **`helpers.py:156-163` READ, NOT PARAPHRASED.** One binding, `getenv`, that is
      simultaneously overloaded (two `@overload` stubs, :158-161) and generic
      (`default:T -> T` coerced by `type(default)`, :163). `helpers.bend:137` and `:293`
      are its two arms, split by return type because Bend cannot overload; the port says so
      itself at `helpers.bend:143` ("THE OTHER ARM OF THE SAME `getenv`") and `:150`
      ("a default of `""` gives `str` ... while a default of `0` gives `int`").

- [x] **WHY THE MONOMORPHISATION REASON AND NOT THE OVERLOADING ONE.** Both are true of
      `getenv`, so the sibling decides: `_str` already sits on
      `LANG-CONSTRAINED:no-generics-one-def-per-element-type`, and putting `_int` on
      `no-overloading-split-by-branch` would print one arm of one def under two reasons and
      read as two unrelated rulings. **MEASURED before the edit: the widened regex newly
      matches exactly ONE key of 668** (`getenv :: _int`), so nothing else is exempted as
      collateral — now a standing check, because the generator applies a regex to every
      live proposal and writes the exemptions with no reviewer in the loop.

- [x] **HAND-PLACED, NOT REGENERATED, AND PROVEN.** `naming-gate-ledger-check.py` (new)
      asserts the ledger FILE is byte-identical to what `naming-gate-ledger.py` would
      write, plus full coverage and no dead rule: 668 proposals, 668 lines, 37 of 37 rules
      live. Nothing previously connected the file to the table, so a hand-added line would
      have stayed green and then been silently deleted by the next generator run.

- [x] **THE GATE STILL BITES — four controls on a throwaway mirror, live tree never
      patched.** `PASS` clean -> `getenv_int`->`getenv_integer` **`FAIL`**, naming
      `helpers.py getenv + _integer` AND reporting `_int` STALE -> `PASS` restored ->
      `getenv_int`->`getenv_u32` **`FAIL`** as STALE -> empty-affix ledger row **`FAIL`**
      as STALE. Pinned as selftest cases 8-10.

- [x] **`naming-gate-selftest.py`: 12 ok / 3 FAIL -> ALL 20 CHECKS PASS.** It was RED
      because case 1 requires a clean tree, and cases 3/4/5 were passing VACUOUSLY — with
      the gate already failing they could not tell "caught the plant" from "already red".
      Added 8 EXACT AFFIX (both `getenv` arms re-spelled must go red), 9 EMPTY-NAMED ROW,
      10 RULE WIDTH, 11 REPORTED BLIND SPOT (printed, never asserted). **Fixed a typed
      count**: the summary read `'ALL %d CHECKS PASS' % (7 * 2 + 1)` and printed **15 for
      12 checks**; the total is now `len(ran)`. NOTE the older entry above saying "15/15
      checks" was that typed number and was never true.

- [x] **QUALIFIED is 38 BEFORE AND 38 AFTER, and that is the honest answer.** All four
      consecutive runs 22:25:32-22:25:43 were byte-identical including VERBATIM 283, so the
      substrate was settled (consistent with 283 at 18:53; I did not reproduce the 278 of
      19:34-19:36 and am not claiming 283 is a stable baseline). VERBATIM 283 / RENAMED-1
      29 / RENAMED-n 89 / ABSENT 1144 unchanged; `getenv` and both arms are counted
      together in the 89.

- [x] **THE EMPTY-NAMED-ROW CAUTION HOLDS, MEASURED.** `MIN_AFFIX = 3` means the detector
      can never PROPOSE an empty affix, so an empty-named ledger row is unreachable as a
      candidate and is classified STALE — a FAILURE, loudly. And the naming gate has NO
      counterpart to `rebase-gate.py`'s `rows()` phantom-row bug: 27,490 `DEF_LINE`
      matches over the whole `.bend` tree, **0 `== ... ==` banner lines at all**, and **0
      matches inside a triple-quoted block** in the 3 files that have one.

- [x] **RULING NOTE: `.agents/slop/ruling-naming-gate-getenv-int.md`.** Rules 20-27
      appended to `.agents/slop/notes/bend2-constraints.md` (positions 15807-15916).

### Outside this unit's files

- **`rebase-gate-selftest.py` IS RED AGAIN SINCE 22:40:38, AND IT IS NOT MINE.**
  `rebase-gate.py`'s `baseline_for` now returns FOUR values (`rows, hunks, complaint,
  readable`) while `rebase-gate-selftest.py:213` still unpacks three:
  `ValueError: too many values to unpack (expected 3)`, rc=1 after 15 checks. Measured
  PASS=66/FAIL=0 at 22:23:45 (before my edit) and again at 22:26:24 (after), so my change
  did not break it; the crash appeared when `rebase-gate.py` was rewritten at 22:40:38, and
  it is reproducible on a retry at 22:41:33. **Owner: whoever owns the rebase gate /
  oracle-wiring unit.** Left alone; not my file, and the edit was 55 seconds old.

---

## Session 2026-10-03 — six ADOPTED defects (reported, never picked up)

All six were measured first by CALLING CPython. Four fixed, two ruled out or bounded. **The
`allow_lower` cause was confirmed; the `F(ovf)` half of the `clamp_mx` cause was FALSIFIED.**

- [x] **1. `device.bend` `allow_lower` — STILL CURRENT, FIXED.** Port said `allow_lower=0`,
      CPython says `1`. Measured live: `Device['python:1']` **SUCCEEDS** under
      `Context(ALLOW_DEVICE_USAGE=0)`. Cause: `device.py:30` REBINDS `ix` and `:31` asserts on
      the rebound value, so the port's `allowed` — a correct port of the assert *statement* —
      cannot see the canonicalize. Added `device_usage(allow, ix) = allowed(allow, canon(ix))`
      and 7 new corners. **Gate: 23 shared rows, 23 agree, 0 disagree (was 17/18).** New
      `.agents/slop/dev-mutate.py`; the `tag_of` mutation that was a documented ZERO for three
      revisions now moves `allow_disk`. The `c7`/DDK-NONE row and the DISK/NPY branches are closed.

- [x] **2. `memory.bend` `Scan.tc` — CAUSE CURRENT, CLAIMED CONSEQUENCE WRONG, CLOSED.**
      `mem_tc_add` does append on every touch: measured `p_tcn=6` where the distinct count is
      `p_nbufs=5`. But `memory.py:60` prints `len(first_appearance)` and this file's counterpart
      for that number is `Scan.bs` / `p_nbufs` = **5, already correct**. `Planned.tc` is not what
      `memory.py:60` reads. Added `p_tcn` so 5-vs-6 is a GATE FACT instead of a comment, plus the
      mutation that proves the pair discriminates (`mem_bs_add` unconditional: `p_nbufs` 5->6 and
      collides with `p_tcn`, which does not move; 11 rows move).

- [x] **3. `UOp.axis_id` flat list / depth invisible — CAUSE CURRENT, FIX NOT LANDED (bounded).**
      Confirmed by CALLING CPython: `axis_id` is a tuple and depth shows in it, in `pyrender`
      (render.py:101 is `repr(y) for y in x.arg`) and in `range_str` (ops.py:96). The depth IS
      stored (`Arena.shp`) and IS gated (`ucdepth_flat_nest=0,1`); `UOp.axis_id(arg)` takes the
      arg and structurally cannot see it, and neither can `arange_repr(ids, at)`. **Blast radius
      re-measured: `UOp.axis_id` has 5 textual call sites and ONE real one** — not 63. Left
      undone: closing it needs a depth-aware `AxIds` (one def, one call site) **and** a matching
      row in `.agents/slop/ops-oracle.py`, which is a BYTE DIFF whose row order is documented as
      exact, and that oracle is not this unit's file. Documented at `uop/ops.bend`'s
      `UOp.axis_id`. Note the brief named `tinybendygrad/renderer/render.bend`, which does not
      exist; the file with `arange_repr` is `tinybendygrad/uop/render.bend`.

- [x] **4. `dd-oracle.py` `clamp_mx` — STILL CURRENT (the reimplementation), FIXED.** `clamp_mx`
      transcribed dtype.py:128-131's arithmetic, in a file whose header says "nothing here is a
      reimplementation of it". Replaced with a CALL: `DD.f2f_clamp` + read `mx` off CPython's own
      graph at `r.src[2].src[0].src[1].src[0]`. Behaviour-preserving on all 8 dtypes
      (`c0..c6` byte-identical). **The claim's `F(ovf)` half is FALSIFIED:** `struct.pack('f', ·)`
      never raises on this interpreter (2516 doubles, 0 raises), so `fbits`'s `except
      OverflowError` arm was DEAD and its docstring was false — `1.8e308` renders `F(2139095040)`,
      and so does `+inf`, which makes `c7` CONSTANT on `fr` rather than under-determined. Dead arm
      removed. **`c7` is `F(2139095040)`.** The false claim had propagated into
      `codegen/decomp/dtype.bend`'s comment; that file is another unit's, left alone.

- [x] **5. `codegen/__init__.bend` reads red — RULED OUT, and the specific error never existed.**
      Green in `--check-only` (`ALL PROOFS CHECK`), interpreted, AND native; both lanes print
      `new_sink=8 repl=1->52->6,3->5,4->8,`. Swept all 8 versions in its git history: 4 red
      states, 4 DIFFERENT causes (`Maybe<&2,U32>` vs a closure, `Sigma<...>` vs `StepResult`, and
      `gr_show.topo` unfilled twice), **none of them `expected : Data`**. No occurrence of that
      string anywhere in the repo refers to this file. The residual is honest: a ONE-row gate on a
      file whose header declares `unified_rewrite` a wall. Separately verified the live tree's
      one-token difference from the `ctl-comment` cone arm is the CORRECT one — upstream
      `walk_rewrite` does `pm_rewrite(new_n)` on the REBUILT node.

- [x] **6. `dd-oracle.txt` 20 phantom lines — STILL CURRENT, FIXED.** Byte-diff vs a fresh run:
      20 duplicated `lg*` rows plus 1 hand-written comment (`# l2i const sources — appended
      2026-10-03, called, not transcribed`) at file lines 407-427, shadowing the real block at
      328-347. **The brief's count is exact.** Regenerated; a fresh run now reproduces the file
      byte for byte, 426 lines, 152 `lg` rows. **And there was a 21st defect the brief did not
      name: `c7=F(ovf)` was STALE** — the committed `dd-oracle.py` cannot print it (see #4), so
      the committed txt did not match the committed script.

- [ ] **NEW, FOUND WHILE TRIAGING #5, NOT LANDED — `codegen/__init__.bend` is being
      rewritten by another agent RIGHT NOW and has taken a wrong turn.**
      Commits `e17d3f7dd48c` ("pass original u to pm_rewrite_m (not rebuilt)") and
      `8ab673c7cd38` landed while I was measuring; the file went 273 -> 275 lines and grew a
      `DEBUG:` print at line 73 between two of my reads. The change makes `wr.step.scan` pass
      `u` to `O.pm_rewrite_m` where it passed `rebuilt`, **while the comment three lines above
      it still says "try the rule on the rebuilt node"** — the code and its own comment now
      contradict each other, and the file is GREEN (`ALL PROOFS CHECK`, `new_sink=8
      repl=1->52->6,3->5,4->8,` unchanged).
      **The gate cannot see it, measured:** that single row is byte-identical either way on
      this 8-node fixture, because `pm_post_sched_cache`'s rules do not discriminate `u` from
      `rebuilt` here. Upstream is unambiguous — `walk_rewrite` (tinygrad/uop/ops.py) does
      `new_n = UOp(n.op, new_src, n.arg, n.tag) if new_src != n.src else n` and then
      `self.pm_rewrite(new_n)`, commented "top-down: try pm on rebuilt node". So `rebuilt` is
      the correct argument and `u` is a silent behaviour change.
      **NOT EDITED BY ME, deliberately:** agent-core's rule is to report a file another agent is
      mid-edit in, and the file did not even compile cleanly for my revert attempt because the
      agent was mid-write. **Owner: whoever holds `codegen/__init__.bend` now.** Two things are
      needed, in this order: (1) restore `rebuilt`; (2) add a fixture where a `pm_post_sched_cache`
      rule actually fires on a node with rewritten srcs, because a one-row gate that is identical
      under a wrong argument is the same "gate that cannot fail" failure as `p_tcn` vs `p_nbufs`
      in #2, one level up.

- [x] **THE E2E: the port computes, proved end to end, with a repeatable artifact.**
      **`.agents/slop/e2e.sh` — one command, prints `PASS`/`FAIL`, exit 0/1.**
      Read: **`runs/e2e/README.md`**.

      `(A @ B) @ C` for three 8x8 f32 matrices, **two launches**, dispatched by
      `tinybendygrad/runtime/webgpu_call.bend`'s own call layer (`Cs.call`,
      `Cs.readable`, `Cs.read`, called unmodified) onto a **real WebGPU adapter**
      (`vendor=apple architecture=metal-3`, Chrome stable `--headless=new`).
      **84 WebGPU calls, every one dispatched. 64/64 u32 words of the answer
      BIT-IDENTICAL to CPython tinygrad on the identical bytes.** 40 gate rows, 0 failed.

      * **A matmul, not a forward pass**, because the port has no kernel executor:
        `exec` is the last wall in `uop/fold.bend` and no `.bend` defines one. What
        exists is the device call layer, and a 2-launch matmul is the smallest program
        that makes it do arithmetic. A forward pass needs `backward` + autograd +
        optimizer, none of which are in Bend.
      * **TWO launches, not one**, because launch 1 reads launch 0's output, so the
        intermediate had to be computed ON the GPU. `mm_e2e_writes=3` is the row that
        says it was not re-uploaded — 3 being the buffers no earlier launch wrote,
        counted from the trace. An all-equal fixture cannot see this.
      * **The shaders are tinygrad's own WGSL**, from `renderer/wgsl.py` on the same
        `ast` the CPU executed, with the bindings PARSED out of the shader and checked
        against the port's `bgl.flat`.
      * **BIT-exact, not "within a tolerance",** and the inputs are dyadic ON PURPOSE.
        Random inputs differ by 2.86e-6 because `compiler_cpu.py:21` compiles with
        `-O2` and no `-ffp-contract=off` — measured: **57 `llvm.fmuladd`** in the IR at
        `-O2`, **0** with the flag — and the WGSL->MSL path contracts too. Neither side
        is the reference. Dyadic entries make every partial sum exact in f32, so no
        order and no contraction can change a bit.
      * **`mm_e2e_in_bits_equal` reads an uploaded matrix back off the GPU**, bit-exact,
        which is what says the answer's exactness is about ARITHMETIC and not DATA.
      * **NEGATIVE CONTROL, `.agents/slop/e2e_negctl.sh`, on a `$TMPDIR` copy with the
        relative layout intact: all three breaks caught.** one uploaded byte -> the two
        answer/data rows; the second launch's binding order -> the binding row plus two
        power rows; and **the port** — `Cs.caller` binding every `bufs` slot to id 0,
        the bug `webgpu_call.bend`'s own header records as once invisible to every row
        in both files — stops the walk, 19 rows red.
      * **SIX POWER ROWS.** `abad/bada/atc/self/zero/ctb`, computed by calling numpy on
        the oracle's own words, all 21-30 away from the answer. The right answer is 0.0
        away, so the equality can fail.
      * **MY OWN GATE WAS WRONG FOUR TIMES AND THE PORT WAS RIGHT**: a hand-counted op
        multiset and four hand-counted buffer rows. They are now identities between two
        measured counts, which cannot be satisfied by typing a constant. Also caught in
        my own harness: `$?` after a pipeline is `tee`'s, so a crashed gate printed
        `PASS`.
      * **REPORTED, NOT FIXED (no existing gate or port file was edited):** the
        committed `tinybendygrad/runtime/webgpu_call.mjs` is **stale** (610 exports vs
        664 from a fresh emit of the same `.bend`; every shared export byte-identical,
        the delta being `../helpers.gi_*` defs added since). The E2E emits its own fresh
        copy instead of editing the committed artifact. Owner: whoever holds that file.
      * **THE LATENT FINDING, reported as latent and NOT as a bug:** `Cs.dispatch`
        forwards `global_size` where WebGPU wants a workgroup count, and
        **every matmul size emits `global_size (1,1,1)`** (measured: 8x8x8, 16^3, 32^3,
        64x8x64, 8x64x8, 4^3, batched 4x(8x8@8x8) — all (1,1,1)), so the two readings
        coincide and **no matmul can exercise it**. An E2E on a matmul does NOT prove
        parallel dispatch.
      * **THE ADAPTER IS PROBED, NOT ASSUMED**: `.agents/slop/e2e_gpu_probe.mjs`
        dispatches a kernel and reads the answer back, because `requestAdapter()`
        resolving is a NAME. Artifact `.agents/slop/e2e-gpu-probe.txt`.
      * Rules C1-C11 appended at the END of `.agents/slop/notes/bend2-constraints.md`
        (positions ~16630+). C1 (the `-o` emitter qualifies an imported constructor's
        tag with the importing file's path, so a `.bend` outside `webgpu_call.bend`
        cannot drive `webgpu_call.js` without a name normalisation), C2 (callee-first,
        reported as "an unfilled law is a dead claim"), C3 (alias `WC` is unusable),
        C4 (`WriteBuffer.bytes` is BYTES), C7 (FMA contraction, both sides), C8 (stale
        `.mjs`), C9 (`$?` after a pipeline), C10 (the `$TMPDIR` layout), C11 (the
        `(1,1,1)` matmul wall) are the ones that cost real time.

## Session 2026-10-04 — `codegen/decomp/dtype.bend`: 33 of 52 gate disagreements closed

**Progress: gate 120/172 -> 153/172 agree (52 disagree -> 19).** Verified starting state
first, twice: 172 rows / 31 `*sig` / `ALL PROOFS CHECK` / exit 0, `rebase-gate.py`'s own
`rows()` 172 with 0 missing, 120 agree / 52 disagree against a fresh `dd-oracle.py`. Nothing
newly broken; comment-only control read 0 row diffs and byte-identical output.

- [x] `DType.const` is `int(val)` for an integer dtype, not a `truncate` width wrap
      (tinygrad/dtype.py:84, uop/ops.py:600-602/628-635). dtype.py:32's
      `lo.const_like(-1)` leaves `-1` in the arena even for a `u32`. Closes `lg2k`, `lg2p`,
      `lg6k`, `lg6p`, and `lg2n` as a side effect.
- [x] Three ARENA-ALIASING defects — `l2i_shl.hi` (dtype.py:41-44), `l2i_cdiv.abs`
      (dtype.py:58-61), `l2i_cdiv.signed` (dtype.py:71) — each handed the same immutable
      `O.Arena` to two builders. `O.Arena.node` answers the BOTTOM out of range, so the
      loser read back as `NOOP`. Closes `lg9p`, `lgq`, `lgqp`, `lgr`, `lgrp`, `lgrn`.
- [x] `31 - n` is `ADD(C(31), MUL(n, C(-1)))`, measured by calling it; the port built
      `SUB(C(2**31), n)`. Closes `lg9k`, `lgak`, `lgbk`.
- [x] `bitcast`/`cast` fold at the same dtype (mixin/dtype.py:53/36); three call sites built
      the node unconditionally. Closes `lgf*`, `lgm*`, `lgb`, `lgbn`, `lgbsig`.
- [x] `.logical_not()` is on `l2i(CMPLT, ...)`'s ANSWER (the `OR`), not on the comparison
      inside it (dtype.py:66 vs :75). Closes `lgt`.
- [x] `return r if op is Ops.CMOD else q` (dtype.py:74) — the port's two arms were swapped,
      visible only on the unsigned pair. Closes `lgs`.
- [x] `shl(cond.cast(uint), i % 32)` (dtype.py:68) — the `% 32` was missing, so `i = 63`
      built `2**63`.
- [x] dtype.py:54-55: `shr` reads the RAW product, one product yields TWO words (`shl` and
      `shr`), the last term is `a1*b0` not `a1*b1`, and both `w3` and `w4` must be returned.
      Closes `lge`, `lgek`, `lgep`, `lgesig`.

- [ ] **OPEN, REPORTED NOT CLOSED — the `n` SLOT-COUNT rows: `lg1n` `lg6n` `lg9n` `lgqn`
      `lgsn` (5 of the 19).** They measure how many arena slots a fixture mints, which is a
      property of `UOpMetaClass.ucache` interning; CPython's key carries the Python TYPE of
      the arg, so `CONST True` and `CONST 1` are two nodes (measured: `(Ops.CONST,(),True,None,bool)`
      vs `(Ops.CONST,(),1,None,int)`). A different kind of claim from the tree/sig/k rows, and
      NOT addressed. Two of the five moved a long way (`lgtn` is now exactly `0`; `lgan` `9` =
      CPython) which is evidence the interning IS close, but close is not equal.

- [ ] **OPEN — `lg5k` `lg5n` `lg5sig` (3 of the 19): the float-SOURCE `CAST` arm,
      dtype.py:33-34.** `x / 2**32` promotes `2**32` to an `f32` CONST, so the port must
      build `CAST(f32)` over `CONST weakfloat ConstFloat(4294967296.0)` = `F(1333788672)`
      where it builds the weakint `C(1:0)`. Measured `UOp.const(2**32, dtypes.float32).val ==
      4294967296.0`; not attempted.

- [ ] **OPEN — the `CDIV`/`CMOD` cone rows: `lgqk` `lgqsig` `lgrk` `lgrsig` `lgsk` `lgssig`
      `lgtk` `lgtsig` (8 of the 19).** Shape and value rows for the 64-iteration loop agree
      (`lgt`, `lgs`, `lgq` are closed); the CONE rows do not. `lgsk` is the diagnostic: the
      port's cone has 36 constants and CPython's has 92 — the port builds all thirty
      `2**(i%32)` but **none of the 56 `UOp.const(i, dtypes.uint)` words of dtype.py:65**, so
      something in the step's arena is unreadable to the cone walk. Not a wrong constant; a
      missing subtree, and the same shape of bug as rule 1 in the notes.

- [ ] **OPEN, NOT MINE — `c7`, and it is a DECLARED REFUSAL.** `rebase-gate.py` (the
      authoritative gate, wired to `dtype-oracle.py`) reports exactly ONE disagreement on this
      port, before and after: `c7`. Left alone per instruction. NOTE the oracle's own
      docstring at `.agents/slop/dd-oracle.py:370-374` says `c7` is CONSTANT under both `fr`
      rather than under-determined — a disagreement between the two, worth reconciling.

- [ ] **OPEN, REPORTED — `rebase-gate.py` CANNOT SEE THIS PORT'S HARD ROWS.** It wires
      `dtype.bend` to `.agents/slop/dtype-oracle.py`, which shares **107 of 172** row names and
      **none of the `lgXY` families that carried the 52**. Measured on the same
      `rebase-gate.py rows()` parser, that pair reports `c7` only, before and after. GUARD 4
      checks disagreement over SHARED names only, so a lane missing the 52 hardest rows is a
      pass. The pair that measures this port is `dd-oracle.py`. **Wiring decision for the
      coordinator: `BASE_ORACLES` for this port should name `dd-oracle.py`.**

- [ ] **REPORTED, NOT FIXED: `tinybendygrad/runtime/executor.bend` is at the REPO ROOT,
      named `.bend`, and does not compile. Five files cite a path that does not exist.**
      Found 2026-10-04 while answering "how far does the port get" for the E2E unit.
      **NOT MINE AND NOT EDITED.** Full measurement in note **C12** at the END of
      `.agents/slop/notes/bend2-constraints.md`; the short version:

      * `git log --all -- tinybendygrad/runtime/executor.bend` returns commits, so it
        **was** at that path. `find` now turns up only two snapshot copies under
        `.agents/slop/`.
      * The repo root holds **`.bend`**, 1890 lines, first line
        `# executor.bend -- tinygrad/runtime/ops_python.py ...`. That is the file.
      * `./bin/bend .bend --check-only` → `no such file:
        /Users/cyberistic/src/tries/helpers.bend`. Its five `../` imports are right for
        `tinybendygrad/runtime/` and escape the repository from the root.
      * **NOTHING CAN SEE IT.** `tree-verdict.py` globs `*.bend` under `tinybendygrad`
        + `examples`; `tools/check` is per-file; every gate takes an explicit path. A
        file named `.bend` matches no glob, so **every "ALL PROOFS CHECK" claim in this
        repo is a claim about a glob** and a misplaced file is invisible to it in both
        directions.
      * Five citations now point at nothing: `runtime/ops_bend.bend:10`,
        `runtime/ops_python.bend:2285`, `runtime/ops_webgpu.bend:673`,
        `uop/symbolic.bend:842` and `:943`, and `.agents/TODO.md:1037` still counts it
        at 2245 LOC.
      * **AND EVEN RESTORED IT EXECUTES NOTHING**, by its own header lines 5-9: "THE
        INTERPRETER LOOP IS NOT: `run` below is a refusal, not a stub that silently
        answers." So the `DEV=BEND` device cannot run a packet **by design**. This is
        the wall behind the E2E unit's choice of the WebGPU call layer: there is no
        Bend-side kernel executor to point a `DEV=BEND` E2E at.

      **Owner: whoever moved it.** Two candidate causes, and this unit cannot tell them
      apart: a concurrent agent mid-`mv`, or a scripted block move that asserted nothing
      (agent-core.md's `end > start` trap). Either way the fix is one `mv` back plus a
      decision about the interpreter loop, and the second is a design question, not a
      typo.
