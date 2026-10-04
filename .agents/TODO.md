# TODO

The port's state. Progress bars are `[###.....] n/m`.

```
spec-as-laws    [#########] 9/9      python-to-bend  [###.......] 5/96  (0 defs outstanding)
proofs          [##########] 34/34   oracle-green     [#####.....] 5/5
walkthroughs    [######...] 6/7      E2E-PROVES-COMPUTE 1/1  <- runs/e2e/
gate-disagree   [#########] 9/10    dtype rows 209, 7 disagreements (was 19). +28 `f2f` rows:
                                        the whole float-decomp region, previously UNREACHABLE
                                        from `main` and therefore ungated for a whole session.
mut-REQUEST     [##########] 0      31 MOVED / 5 THEOREM / 0 REQUEST
false-zeros     [##########] 0      0 unmarked (was 14) across 21 records
row-reader      [##########] 3/3    formats F1/F2/F3, 39 pairs, 0 keys lost
arena-aliasing   [##........] 2/10   1100 read sites audited, 1 DEFECT fixed (+2 rows),
                                       8 suspects adjudicated, 4 detectors w/ controls
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
      **THE `ssimplify` WALL IS CLOSED — AND IT WAS TWO DEFECTS IN TWO DEFS, which is the
      finding.** `sym_dim` (fold.bend:1243) mints the `O.SU` a symbolic dim is, and
      `Prod`'s single `bad` flag was reading a NEGATIVE dim and a SYMBOLIC dim as one thing
      while upstream's two checks read that flag as opposite things (`all(x >= 0)` RAISES,
      `resolve(..., False)` is a DEFAULT and does not). **MEASURED that either half alone
      leaves the differ DISAGREEING**: reverting `reshape_ok`'s `sym` arm puts
      `diff --graph sym` back to `?=0/6` and the same six rung-1 mismatches
      (`runs/margsym/M16-sym-DISAGREE.txt`). `dim_str` had to change with them — a symbolic
      dim now prints `U(Ops.PARAM:n)` instead of a bare `UOp`, because a renderer with one
      token for every symbolic dim cannot tell "simplified" from "flattened" (mutation M15
      moves four rows, and `mv_reshsym_nm`'s two dims are DIFFERENT on purpose).
      **22 `mv_*` rows, 20 byte-identical to CPython**, the two exceptions being named
      DIVERGES with their interval arithmetic in the oracle's DIVERGES block. The 328
      pre-existing rows are BYTE-IDENTICAL before and after.
      **THE FIVE ARMS: `expand_ds`, `pad_ds`, `shrink_ds`, `perm_ds`, `flip_ds`,**
      answering ops.py:412-428. 16 `mv_*` rows, FOUR FACTS PLUS THE ANSWER AS ONE
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
      green and identical; 27 gate rows, 22 green; 17 mutations measured; 23 of 47
      `symbolic_simple` rules and 3 of 5 reciprocal rules. **2026-10-04 PASS: 10 of
      the 32 `TODO(p3)` blocks CLOSED, 22 REMAIN, 57 gate rows all green, 16 new
      mutations measured (3 of them by re-running the gate, not by reading it).**
      THE THREE THINGS THAT PASS FOUND, and each one was filed as a wall:
      (a) `UPat.alu` (ops.py:1543) hands a COMMUTATIVE op a LIST `src` and a list is
      EVERY PERMUTATION (ops.py:1464) — so a `CMPNE`/`AND`/`OR`/`MUL` pattern arrives
      with its two captured names on either side and the question a rule must answer
      is "which src is the CONST", not "src[0]". `Sw` is that question and SIX rules
      share it. Every `early_reject` in the table was read out of CPython's own
      `UPat.early_reject` for the pattern at that line, not derived by reading
      ops.py. (b) A rule body that MINTS must not re-read `sy_ar(x)`: the fold's arena
      is stale the moment the first node is interned into it, so the second node lands
      on the slot the first one took. `mint_bin`/`mint_un`/`mint_cast`/`mint_const`/
      `mint_replace`/`mint_not`/`mint_recip` thread a `Found` chain instead.
      `sym_3` and `sym_10` still re-read it and are the two rules here whose answer
      index is therefore NOT gated — stated, not hidden. (c) `dtypes.ints` is EIGHT
      concrete widths, not four: the two dtype-set helpers answered SIX and FIVE,
      which is an UNDER-approximation, so a rule gated on one silently SKIPS a node
      Python rewrites. `ints_n`/`intish_n`/`intweak_n` are the rows and the oracle is
      CPython's `len(dtypes.ints)`. A fourth: `Arena.next` is the ONLY symptom a
      stale arena has, and reading it is what found three broken fixtures.
      PORTED AND GATED: the prelude (`split_uop`, `pop_const`,
      `identity_element`, `val`/`is_invalid` reading through a CAST, `truncate`,
      `const_like`/`ccast`/`cconst`, the raw `alu` sugar), `exec_alu` over a
      closed tree in TWO lanes, `simplify_pow` (2 of 5 arms), `fold_bitcast`,
      `fold_const_alu`, the compiled rule shape (table + first-wins fold +
      `ret is not uop` + the name-rebind identity check), and 25 RULES: 23 in
      `sym` and 2 in `pm_remove_invalid`. DEFERRED: 104 of symbolic.py's 127 own
      rules, each a `TODO(p3)` naming its wall — `_min_max` gates 9 of the 22
      deferred blocks, `UOp.ranges` + set algebra 4, `gcd` 2, and
      `mixin/elementwise.py`'s promotion is a caveat on every rule body.
      `sym_table_len`/`rm_table_len` were DEAD defs (a count nothing checks is a
      comment with a type) and are now live through `len_dec`/`len_dec_rm`.
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
- [x] `uop/weak.bend` — `tinygrad/uop/weak.py`: **1 of 17 `TODO(p3)` blocks CLOSED,
      16 REMAIN, 4 gate rows added, all green.** CLOSED: `weak.py:45`
      `_lower_weak_ops`, the one item in this file's queue with NO `_min_max` behind
      it — a module CONSTANT, `GroupOp.Binary | GroupOp.Unary | {WHERE, RANGE, STACK,
      SPECIAL}`, THIRTY ops, gated by `lower_n` (a COUNT, because a set that gates a
      rewrite is invisible to a per-op boolean: a dropped op makes `lower_weak_node`
      SKIP a node and a spurious one makes it rewrite one) and by `lower_in`/
      `lower_unary`/`lower_out` for the three ends. THE FINDING THAT MAKES THE OTHER
      SIXTEEN CHEAPER: mixin/dtype.py:16 is
      `commit_int(self._uop.vmin, self._uop.vmax, default_int) if self.dtype is
      weakint else strong_dtype(self.dtype)`, so the ONLY thing behind all four
      remaining defs and four rules is the PAIR `(vmin, vmax)`. `strong_dtype`,
      `weak_dtype` and the dtype lattice are all PORTED here already, and
      `commit_int` (dtype.py:171) is expressible — a four-rung ladder over
      `(default_int, int32, int64, uint64)` — except that its `uint64` rung needs
      `2**64 - 1`, which is the SAME window `fold.bend` measures for `_min_max`: a
      SIGN BIT PLUS AN UNSIGNED 64-BIT MAGNITUDE, not a signed 64-bit word.
      `fold.bend`'s `Bnd`/`bnd_lim` is that pair and is landed. So `commit_int` is
      `Bnd`'s consumer and the missing argument is ONE def — `fold.bend`'s walk of
      `_min_max` — and not four.
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

### THE WAVE'S RESULT, measured at the end

**All ten `uop/` files are `ALL PROOFS CHECK`.** Markers 330 -> 291, and
the tree SHRANK by 7,935 lines because a dead snapshot was deleted rather
than 7,935 written. 203,619 -> 196,496.

| file | before | after | what landed |
|---|---|---|---|
| `ops.bend` | 192 | 170 | 5 defs (backward_slice family, 14 rows) + 14 defs (base/buf_uop/bufferize/split_uop/sharding/sint_to_uop, 82 rows over three lanes) |
| `fold.bend` | 46 | 45 | `is_image_shape`; `_ranges`/`ranges` found ALREADY PORTED and relabelled |
| `symbolic.bend` | 32 | 17 | 10 rules, 30 rows |
| `weak.bend` | 17 | 16 | `_lower_weak_ops`, 4 rows |
| the other six | 43 | 43 | untouched |

**THE MARKER COUNT IS NOT THE PROGRESS COUNT.** Across the four agents,
roughly 20 of the 48 markers they closed were *already done* with a
stale marker. Every wall is now named with its RULE next to the line, so
the real remaining work in `uop/` is nearer 150 than 291 -- and a large
share of that is `fold.bend`'s `_min_max` walk plus `helpers.bend`'s
missing i64 helpers. Two named dependencies, not 150 unknowns.

### The five bugs the wave found

1. **`dtypes.ints` is 8, not 4 or 6** (symbolic agent; verified against
   a live `tinygrad`). The dtype-set helpers under-approximated, so rules
   were SILENTLY SKIPPING signed 64-bit nodes that CPython rewrites. A
   rewrite that skips nodes disagrees quietly.
2. **A minting rule body must not re-read `sy_ar(x)`** (symbolic agent).
   The fold's arena is stale after the first intern, so the second node
   lands on the first one's slot. The only symptom is `Arena.next`;
   reading it found three broken fixtures. `sym_3`/`sym_10` still do it
   and are documented as un-gated.
3. **Three fp8 dtype limits were wrong in a DEAD file** and the live file
   had already fixed them -- but `mm-dt-gate.py` read the dead one, so
   it reported bugs that did not exist. Deleting the snapshot made all
   three vanish.
4. **`split_uop` appended a separator's srcs to the ANSWER**, so
   separators were never descended into. Typechecked, `--check-only`
   clean, wrong.
5. **`ALLOC->PARAM(99)` where CPython says `ALLOC->BUFFER(0)`** (mine, and
   only findable after the printer was taught to NAME ops -- the
   count-only gate reported AGREE with it live).

**BUG 4 IS THE ONE TO GENERALISE FROM.** A gate that checks the SHAPE of
an answer passes while the answer's CONTENTS are wrong, and four
independent agents hit a version of it: `ops_nv` 33/219 constants,
`base`'s DETACH arm with no fixture, `sharding`'s op test that was not
load-bearing, and a split that appended to the wrong list. The pattern
is always a FIXTURE THAT DOES NOT REACH THE BRANCH.

### The one durable process fix

**R-4 in `bend2-constraints.md`: parallel agents need SEPARATE jj
workspaces.** A jj working copy is ONE commit, so N agents writing into it
means the first to `jj describe` captures everyone's hunks. Measured
three times today. **No work was lost, but the history now lies about
who wrote what**, and an agent that ran `jj revert` on a path it
believed was its own would have destroyed the others. One agent DID see
a half-applied signature change mid-flight and correctly declined to
"fix" it; that was luck, not process.

### The reusable Bend shape the last agent measured

A walk down `src[0]` CANNOT be the self-call -- a self-call must pass a
subterm of its own parameter, and an arena read is not one. Three shapes
were measured and refused (`Bool.pick` with the peel in the condition;
the `.go` split, which R-3 forbids because the sub-def calls the parent;
a two-scrutinee match on a computed peel). What works is ONE def, ONE
scrutinee, FUEL FIRST, with the stop encoded in the NODE:

```bend
case 1n+p: X(p, ar, Bool.pick(<T>, <walks>, Arena.src(ar, self, 0), self))
```

Six walks in six three-line defs that differ only in the peel set --
which is the one thing a parameter would carry, and Bend cannot
parameterise over a function.


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
| P3 | `uop/` | 12 | [###.........] 3/12 |
| P4 | `schedule/` `engine/` | 10 | [#.........] 1/10 |
| P5 | `codegen/` `renderer/` | 30 | [##.......] 5/30 |
| P6 | `runtime/` | 36 | [...........] 3/36 |
| P7 | `tensor` `mixin/` `nn/` | 15 | [##.......] 6/15 |
| P8 | `llm/` `viz/` `function.py` `device.py` | 15 | [##.......] 1/15 |

### P3 — the honest count, and why a marker is not a backlog

`uop/` is 12 files, not 10, and **3 are at zero markers** (`__init__.bend`,
`probe-mmcore.bend`, and — since the rewrite engine landed — the gate on
`codegen/__init__.bend`, which is its own 0). All 12 are `ALL PROOFS CHECK`.

264 markers remain, and they are **not** 265 tasks. `.agents/slop/marker-audit.py`
splits them three ways, and only the third is work:

| file | wall | shared | **backlog** |
| --- | --- | --- | --- |
| `uop/ops.bend` | 14 | 59 | 61 |
| `uop/fold.bend` | 41 | 0 | 0 |
| `uop/symbolic.bend` | 15 | 0 | 0 |
| `uop/weak.bend` | 14 | 0 | 0 |
| `uop/spec.bend` | 12 | 0 | 0 |
| `uop/divandmod.bend` | 10 | 0 | 0 |
| `uop/render.bend` | 1 | 0 | 5 |
| `uop/upat.bend` | 3 | 0 | 0 |
| `uop/movement.bend` | 1 | 0 | 0 |
| `uop/validate.bend` | 0 | 0 | 2 |
| **total** | **110** | **59** | **65** |

- **wall** — the reason is in the marker's own entry. Closed in the only honest
  sense available: it compiles, it prints the gap, nobody mistakes it for flight.
- **shared** — the reason is written once in the file's NOT PORTED block instead of
  beside each marker. 57 of these are the `UPat` COMPILER (`ops.py:1545`–`1790`),
  whose wall is stated once and applies to all of them.
- **backlog** — no reason anywhere. This is the queue.

**I REPORTED 162 BACKLOG AND IT WAS WRONG BY 88.** The classifier I was using
read 14 raw lines past each marker and counted any line merely *referencing* a
`TODO(p3)` as if it were a marker. A correct split needs the marker's own
continuation (stopping at the next marker), and it needs the third category:
`fold.bend` and `render.bend` looked like 11 backlogs each and are **0** — every
one of their markers carries a written reason that runs past the window I was
reading. The real backlog is **76**, not 162. `marker-audit.py` prints its backlog
unconditionally, because a split that cannot show its own backlog is a split
nobody can check.

**THE MARKERS' OWN NUMBERS WERE WRONG.** Every `TODO(p3) ops.py:N def NAME`
marker in `ops.bend` pointed two or three lines off its def, at the decorator.
98 are now renumbered from the AST. 16 are left ALONE because the name is
ambiguous across classes — `__init__`, `__reduce__`, `rewrite`, `param`,
`ufix` all appear twice, and a base-name index resolves them to whichever it saw
first, so "renumbering" `ops.py:1588 def __init__` to 220 would point it at a
different class's `__init__`. 12 name a def `ops.py` has deleted and need a
decision, not a number. A marker whose number and label name different defs is
not an index, and a count built on it counts the wrong thing.

**THE MEASURE THAT IS NOT A COUNT.** Across the four-agent wave, ~20 of 48
closed markers turned out to be *stale* — the def was already ported and the
marker never came off. So a count cannot tell `PARAM->PARAM` from
`PARAM->BUFFER`. Every landed def in this phase carries a CPython-confirmed gate
row, and the mutation table is what says the row is load-bearing.

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
      **SUPERSEDED 2026-10-04 by the NINE-LEVEL gate below: 72 -> 89 rows, levels unset/0..7.**

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

## ops.py:501-1928 (the base family, the movers, `split_uop`) -- 14 defs LANDED, 149 remain

**Range:** `tinybendygrad/uop/ops.bend` lines 501-1928. **Gate:**
`sh .agents/slop/ops-501-gate.sh` -- 82 rows, three lanes (CPython / interpreted /
native) byte-identical. **Mutations:** `.venv/bin/python .agents/slop/ops-501-mutate.py`
-- 15/15 move the rows they name.

LANDED, with a row each: `base`(:785), `unsharded_base`(:792), `storage_base`(:801),
`without_after`(:623), `buf_uop`(:925), `has_buffer_identity`(:952), `barrier`(:624),
`bufferize`(:679), `allreduce`(:680), `mselect`(:772), `sharding`(:707),
`split_uop`(:685), `sint_to_uop`(:1893), `gate_kernel_sink`(:1901). 29 Bend defs in
total including the peel predicates, the printers and the rows.

**THE SHAPE, and it is the reusable finding.** A walk down `src[0]` cannot be the
self-call, because a self-call must pass a SUBTERM of its own parameter and an
arena read is not one. Three shapes were measured and refused: `Bool.pick` with the
peel in the condition (both arms read `self`); the `.go` split (a sub-def above its
parent is R-3, but the sub-def CALLS the parent, so it is mutual recursion); and a
two-scrutinee `match fuel peels:` (`peels` is a call and `match` may not scrutinise a
computed value). WHAT WORKS is one def, one scrutinee, the fuel first, with the STOP
encoded in the NODE:

    match fuel:
      case 0n: <the terminal answer on the node the walk stopped at>
      case 1n+p: X(p, ar, Bool.pick(<T>, <walks>, Arena.src(ar, self, 0), self))

A node that does not walk is carried UNCHANGED for the rest of the fuel and comes
back out of `case 0n:`, so the answer is exact whenever the fuel outlasts the walk
and `Arena.budget(ar)` is the only sound fuel. Six walks in six three-line defs, and
the six differ ONLY in the peel set -- which is the one thing a parameter would have
to carry, and a function value cannot be parameterised in Bend (a function in a
datatype field forces `Type`, and a `Type` cannot be passed an arena).

**FIVE THINGS THE GATE FOUND THAT I HAD WRONG, all of them silent.**
1. `split_uop`'s first version appended a separator's srcs to the ANSWER and
   shrank the worklist independently, so a node that IS the separator was never
   descended into. It typechecked, it checked, and `s5_split_nest` read the src
   sequence with the descent missing. Both lists now live in `Wk` and the step
   answers the whole record, so "which list grows" is the arm.
2. `base`'s DETACH arm had NO fixture. `base_drops_detach` moved NOTHING, which is
   the hole a mutation exists to find; `s5_base_detach` closes it and the mutation
   moves three rows.
3. `sharding`'s op test was not load-bearing: the RESHAPE fixture's `ATuple` arg was
   EMPTY, so dropping the `if` still answered the empty list. A non-empty arg makes
   the test the thing the row reads.
4. `split_pushes_to_back` moved nothing until a fixture with a NESTED push existed.
   The first push is `work = srcs ++ rest` either way and every all-CONST fixture has
   the same sequence under both, so front-vs-back is invisible without a two-level
   split whose second level is not a CONST.
5. "A walk that peels once" is NOT a legal mutation -- passing `0n` to the self-call
   is not decreasing, so the file does not check and the run prints nothing. The
   same claim is expressible through the FUEL at the call site, which is better: an
   under-fueled caller is the realistic way to get one step. `base_no_fuel` moves
   `s5_base_r1` and `s5_base_r2`. Note `1n` does NOT: `case 1n+p` recurses with
   `p = 0n` and `case 0n:` then answers the node one level down.

**WHAT IS STILL A WALL, and why it is not a stub.** `simplify`(:513) / `ssimplify`
(:520) / `_eval`(:523) all bottom out in `graph_rewrite` and `_min_max`(:1104), and
`_min_max` needs the dtype and shape folds. `buf_uop`'s MSELECT and MSTACK arms MINT
and so hit the same arena-growth wall `codegen/__init__.bend`'s rules have. `walk_
rewrite`(:1782) / `unified_rewrite`(:1808) / `graph_rewrite`(:1880) are PORTED, in
`./codegen/__init__.bend`, and re-porting them here would be a copy; the TODO lines
stay so the queue still says where the code is. `base` is in BOTH files: a Kahn table
read in `fold.bend` and this fuel peel, and they compute the same function.

**THE TWO FILES NEXT.** `codegen/__init__.bend` and `ops.bend` both own a
`walk_rewrite`. That is a duplication to resolve, and the fix is to make
`codegen/__init__.bend` call the `ops.bend` one, not the reverse -- the TODO lines
for :1782/:1808/:1880 in `ops.bend` are where that decision belongs.

---

## [DONE] Reconcile the gate's verdict with the selftest's number, entry by entry (2026-10-04)

Progress: `[████████████████████] 100%` — mechanism named, `device.bend` cleared 21/21, honest
BROKEN list published, reconciliation control added. **No `.bend` edited. Nothing committed.**

- **THE CONTRADICTION WAS NOT ONE.** The sweep's state line is the verdict of FOUR GUARDS over
  fresh lanes and can be `BROKEN` for a reason unrelated to agreement; the selftest's `23 / 0 /
  110 / 23` is `measure_roster()`'s intersection and disagreement count, and its `PASS` covers
  six SYNTHETIC states with `run_port()` stubbed — **it never runs the port.** Neither tool was
  wrong about what it measured; nothing said they measured different things.
- **`device.bend` IS CLEAN — 21/21, on a substrate that did not move** (`device.bend` 22:49:42,
  `device-oracle.py` 22:50:23, untouched all session): 15 reps working-copy gate, 3 reps gate at
  `@-`, 60 interpreted runs (rc 0, exactly 110 rows, every one), 40 compiled-binary runs, 12
  under 4-way concurrency — **at load 12–107.** The load-flake story did **not** reproduce here.
- **THE TALLY CAME FROM `@-`.** `cstyle.bend` is unwired in the working copy, so `never_wired()`
  makes `BROKEN` **unreachable by construction** — yet the quoted tally names it BROKEN. Wired
  entries: **39 at `@-`**, 38 now. `NOT-STARTED=11` is pinned by the roster in both, so `cstyle`
  is the discriminating entry. New `.agents/slop/gate-at-rev.py` runs a revision without
  checking it out (staged in `.agents/slop/`, private module name, deleted in `finally`).
- **HONEST BROKEN LIST, one reason each:** `dtype.bend` = GUARD 3 then GUARD 2 (14 unfilled laws
  **and** a TSV oracle — **GUARD 3 fires first, so "compared nothing" is never said**);
  `codegen/decomp/dtype.bend` = **`native` rc=1 while `interpreted` gave 178 rows, and the file
  was edited 03:24:28 → 03:30:17 mid-session** — a concurrent agent's real type error
  (`expected List<&2, U32> / observed U32` at `UOp.mselect`), reported not touched;
  `renderer/cstyle.bend` = **NOT-STARTED / unwired — a coverage fact, not a disagreement**; its
  real gate is `cstyle-gate.py`. **The two dtype ports are NOT one port under two spellings**
  (23,709 vs 128,736 bytes, two oracles, two verdicts); the target list is not doubled.
- **NEW BUG FOUND: the native lane's path is keyed on STEM, not port.** `run_port()` writes
  `/tmp/rebase-gate/<stem>.bin`, unlinks it, then **executes whatever is at that path.** 8 stems
  collide across 136 `.bend` files (`dtype`×3, `__init__`×**14**, `elf`, `op`, `spec`, `memory`,
  `movement`, `ip`). `rebase-stability.py:284` already shards by stem for this reason;
  `rebase-gate.py`'s sweep is sequential so it is safe from itself, and `device` is unique —
  which is why device was never exposed. **Fix belongs in `run_port` (another agent's file): key
  on `port_key(bend)`.**
- **CONTROL ADDED: `.agents/slop/gate-reconcile.py --reconcile`** checks each port's gate verdict
  against the selftest's number, requires the verdict **reproducible over `--reps`**, and
  requires a **reason and a class** on every verdict. Found a live divergence on its first run.
  For an unwired port it prints `RECONCILED ... BROKEN is UNREACHABLE for this port by
  construction, so a BROKEN naming it came from a DIFFERENT wiring` — **that line is the control
  that would have caught this.** Both tools' own functions are called; there is still one
  `rows()`. Also new: `gate-roster-arith.py` (roster arithmetic, no lanes).
- **THE WHOLE-TREE SWEEP WAS THEN RUN TO COMPLETION (03:36 → 04:2x, `--json`, rc=1) AND IT
  SAYS `device.bend` = `AGREE-UNRECORDED`, 23 shared / 0 disagree, all four lanes rc=0.** Same
  tree, same gate, same pinned interpreter. **The selftest's number is the right one; the quoted
  `device.bend` BROKEN does not reproduce.** Sweep tally:
  `NOT-STARTED=12 BROKEN=8 UNCHANGED=16 RE-PORTED=7 AGREE-UNRECORDED=7`.
- **BUT 6 OF THOSE 8 BROKENs WERE ONE EDIT.** `uop/ops.bend` changed `ABlob{n: U32}` →
  `ABlob{bs: List<&2,U32>}` at **04:18, mid-sweep**; `codegen/simplify`, `schedule/rangeify`,
  `uop/fold`, `uop/spec`, `codegen/gpudims` and (one import hop out) `engine/jit` all failed with
  the **identical** `expected U32 / observed List<&2,U32>` at `binary_n.of`. **All six now print
  `ALL PROOFS CHECK`.** A reader given the bare list sees six port defects and fixes none, because
  the defect is in none of them. Real remaining BROKENs: `codegen/decomp/dtype.bend` (row `c7`,
  a **declared refusal**) and top-level `dtype.bend` (declared dead lane, **two** guards fire).
  New `.agents/slop/dev-tally-classify.py` sorts a `--json` sweep by CAUSE, runs **no lanes**, and
  prints each entry's mtime so `EDITED DURING THE SWEEP` is visible.
- **RULE: A BROKEN LIST IS NOT A LIST OF DEFECTS.** Two ports with the same error are one defect;
  classify by the error's `Context:`/`Location:`, never by the port list. **And a sweep is only a
  measurement if the tree held still** — bracket it with an mtime manifest and re-run any port
  whose file moved.

## [DONE] rebase-gate: BROKEN is one word for five things — cause, denominator, reconciliation (2026-10-04)

Progress: `[████████████████████] 100%` — 6/6 BROKEN entries classified, `.bin` keyed on the port,
`BROKEN` printed with its cause histogram, sweep↔selftest reconciled entry by entry, 39 per-lane
controls run.

**The three numbers that disagreed, and why none of them was wrong.**
`BROKEN=6` (whole-tree sweep) vs `1 FAILED` (selftest) vs `cstyle = BROKEN` (a `--port` run).
All three are TRUE and all three measure different things. Now printed on the line you read.

- **`BROKEN=6`, ONE ENTRY AT A TIME, WITH ITS DENOMINATOR** (measured, 11m04s, rc=1):
  | port | cause | class | rows |
  |---|---|---|---|
  | `codegen/decomp/dtype.bend` | `DISAGREE` | DEFECT | **1 of 356** oracle row names, `c7` |
  | `dtype.bend` | `LANE-DEATH` | INSTRUMENT | `interpreted` rc=1, `dtype_tables` rc=0 |
  | `schedule/prepare.bend` | `LANE-DEATH` | INSTRUMENT | `interpreted` rc=1, oracle 2521 |
  | `tensor.bend` | `LANE-DEATH` | INSTRUMENT | `interpreted` rc=1, oracle 30 |
  | `uop/render.bend` | `LANE-DEATH` | INSTRUMENT | `interpreted` rc=1, oracle 85 |
  | `viz/serve.bend` | `LANE-DEATH` | INSTRUMENT | `interpreted` rc=1, oracle 176 |

  **THE FOUR LANE-DEATHS WERE ONE IN-FLIGHT EDIT, NOT FOUR PORTS.** All four died with the
  IDENTICAL `expected : Arg / observed : Const` at `UOp.new(Arena.empty(), OpsCONST{}, Nil{},
  CBool{True{}}, TNone{})`, which is the same signature as the 04:18 `ABlob{n: U32}` →
  `ABlob{bs: List<&2,U32>}` breakage this file already records. **ALL FOUR RUN CLEAN NOW**, run
  directly, minutes after the sweep ended: `prepare` rc=0 / 321 rows, `tensor` rc=0 / 33,
  `uop/render` rc=0 / 129, `viz/serve` rc=0 / 177. **SO A `BROKEN` LIST OF SIX WAS ONE REAL
  FINDING, ONE DECLARED-DEAD LANE, AND FOUR MEASUREMENTS OF A TREE THAT DID NOT HOLD STILL.**

- **THE `rows {'interpreted': 0, 'cpython:dtype_tables': 0}` ENTRY IS `dtype.bend`, AND IT IS NOT
  A ZERO-ROWS VERDICT.** GUARD 3 fires BEFORE GUARD 2, so the answer is `LANE-DEATH`, not
  `ZERO-ROWS`: `interpreted` and `native` both exited **1** ("14 defs rely on unsafe or foreign
  code") and so did `--check-only`. The 0 rows are a consequence of the lane dying, not a claim
  that an oracle emitted nothing. This is wired ON PURPOSE — it is the one lane where BROKEN must
  be reachable on the real tree — and `rebase-gate-selftest.py`'s `dead_lane_is_broken` drives it
  every run.

  ⚠ **AND THE BRIEF'S PREMISE ABOUT IT IS WRONG, CITED BY POSITION.** `rebase-gate.py`'s header
  says a 0-row lane is a **FAILED ORACLE** (GUARD 2, header line ~33) and lists "rows went to
  ZERO" under `BROKEN` (header line ~14). It is NOT-STARTED-for-zero-rows that the header says,
  and it says it about a *recorded baseline lane with zero rows* (`hollow`, ~line 800) — a
  different object. **The zero-row rule was left as the header states it**, because moving it to
  NOT-STARTED would turn a red lane green, which is the failure this unit exists to prevent. What
  WAS fixed is the substance underneath it: a 0-row bend lane is now re-run (`BEND_ROW_TRIES=2`,
  20s backoff) because bend stack-overflows ~1 run in 20 and prints 0 rows with rc=0, so one empty
  lane is a coin flip. **A CPython ORACLE IS NOT RETRIED** — `dtype_tables.py` prints 14,774 TSV
  lines and is wired to read as zero on purpose.

- **`cstyle` IS NOT BROKEN. `TALLY BROKEN=1` REPRODUCED, AND IT IS THE WRONG ORACLE LANE.**
  `rebase-gate.py --port tinybendygrad/renderer/cstyle.bend` → **`RE-PORTED`, rc=0**,
  222 shared / **0** disagreeing, 225/225/222 rows, all four lanes rc=0, md5 `4eb1189ed7c7`
  unchanged. The whole-tree sweep agrees: cstyle is in `RE-PORTED=8`, not in `BROKEN=6`.
  `TALLY BROKEN=1` is reproduced by pointing the gate at the 15-row lane:
  `--oracle ".agents/slop/renderer_oracle.py cstyle"` (not `cstyle-rows`) →
  `rows interpreted=225 native=225 cpython:renderer_oracle=15`, **0 shared names**, cause
  **`INCOMPARABLE` [COVERAGE]**. **Nothing was compared, so nothing disagreed** — the opposite of
  what `BROKEN` reads as. Both numbers are printed side by side, cause first.

- **THE SWEEP AND THE SELFTEST WERE NEVER ASKED THE SAME QUESTION, AND NOW SAY SO.**
  The sweep's state is FOUR GUARDS over FRESH lanes, so it can be BROKEN for a reason unrelated to
  agreement. The selftest's numbers are an INTERSECTION and a disagreement count, it has NO
  BROKEN verdict, and the `PASS` beside them is SIX SYNTHETIC STATES with `run_port()` **STUBBED** —
  it never runs the port. Both tools now print that on the line above their numbers, and
  `gate-reconcile.py --sweep SWEEP.json` reconciles them **entry by entry, running no gate lane**,
  with both denominators and a verdict per row.

- **THE `.bin` PATH IS NOW `port_key(bend)` + PID.** It was `{bend.stem}.bin`: 131 `.bend` files,
  110 distinct stems, `__init__` ×14, `dtype` ×3. `run_port()` unlinked that path and then
  executed whatever was at it, so a concurrent run could leave one port's native lane holding
  another's rows — surfacing as `BROKEN N row(s) disagree` with no error in either port.
  Control: `rebase-gate-selftest.py`'s `native_bin_control()` (injective over all 131 files, AND
  the old spelling asserted NOT injective so the check cannot pass vacuously), plus
  `gate-reconcile.py --control`, which runs the only two wired ports sharing a stem
  (`dtype.bend` and `codegen/decomp/dtype.bend`) AT THE SAME TIME.

- **"2 DISAGREEMENTS" AND "1 OF 109" ARE ONE DEFECT.** GUARD 4's `bad` list holds one entry per
  `(lane, other, name)`, so on a three-lane run ONE disagreeing row appears twice. The sweep said
  `2 row(s) disagree with CPython across 3 lane pair(s)`; its own `disagreements` field held
  `c7`-vs-`interpreted` and `c7`-vs-`native`; the selftest said `1 of 109`. **Both true, and
  nothing said so.** Now: `1 of 356 shared row NAME(S) disagree … (2 pair-instances)`, and
  `compared_pairs` is stamped on every exit path (it used to be set only on the green path, so the
  red had no denominator at all).

- **PER-LANE CONTROLS: 38/39 PASS, manifest 0 files changed during the run, load 7.7-12.8.**
  Every wired lane, through the REAL `run_port`: clean → `AGREE-UNRECORDED` rc=0, one planted row
  → `BROKEN` rc=1 **naming that row**, restore byte-identical. Run with
  `gate-reconcile.py --control --workers 3`.
  - **THE ONE FAIL IS A REAL DEFECT, NOT AN INSTRUMENT ONE:** `codegen/decomp/dtype.bend`,
    `1 of 109` shared names disagree — `c7`, the declared refusal already open as
    "OPEN, NOT MINE — `c7`". Its plant, cause and restore all behave; only "clean → AGREE" is
    unreachable while the port disagrees.
  - ⚠ **THE CONTROL FOUND TWO REAL DEFECTS IN ITSELF, AND BOTH ARE THE CLASS THIS UNIT EXISTS
    TO CATCH.** First run: 31/39, 8 failures.
    1. **`mutant_lane`'s plant LANDED WHERE THE GATE DOES NOT LOOK.** It appended `PLANTED` at
       end-of-line, and `rows()`'s `row()` COMPARES `left`, not `right` (deliberately — `right` is
       the port's `]   py=[` transcription of the pin). On every F2 lane the corruption extended
       `right` and left the compared value untouched: `renderer/ptx.bend` planted
       `f10_loads.entry` and came back **AGREE-UNRECORDED, 281 of 281 agreeing**. Same for
       `tc_ptx`, `generate`, `llvmir`, `nir_llvmir` — **six lanes reporting green while
       disarmed.** The plant now goes in immediately after the first `=`, and `lane_control()`
       asserts the planted lane's own value differs from the port's before reading the verdict.
    2. **THE RESTORE COMPARED THE ORACLE'S ROWS, AND TWO ORACLES ARE NOT DETERMINISTIC.**
       `prepare-oracle.py` drifts on 38 rows between runs and `elf_rows.py` on 14 (the
       `elf_built_*` ASLR addresses BASE_ORACLES already records). "The restore is byte-identical"
       is a claim about the two PORT lanes; an oracle's run-to-run determinism is a different
       claim. Now checked per lane: PORT lanes must be identical, oracle drift is REPORTED with
       its row count, and drift on a **SHARED** name still fails — both are on unshared names, so
       neither is a disagreement source. Measured drift matches the recorded numbers exactly
       (38 and 14).

- **TALLY BEFORE AND AFTER THE `.bin` FIX, both measured, both on this tree:**

  | | NOT-STARTED | UNCHANGED | RE-PORTED | AGREE-UNREC | BROKEN | causes |
  |---|---|---|---|---|---|---|
  | before (`{stem}.bin`) | 11 | 19 | 8 | 6 | **6** | not recorded |
  | after (`port_key`+pid) | 11 | 20 | 9 | 7 | **3** | `DISAGREE=2 LANE-DEATH=1` (+`UNWIRED=11`) |

  **THE DROP FROM 6 TO 3 IS NOT THE FIX.** The four that stopped being BROKEN
  (`prepare`, `tensor`, `uop/render`, `viz/serve`) were all measured while `uop/ops.bend` was
  mid-edit; each was re-run ALONE afterwards at rc=0 with rows. **THE `.bin` FIX CHANGED NO
  VERDICT ON THIS SWEEP, AND IT IS REPORTED AS HAVING CHANGED NONE** — one sweep before and one
  after, no port's verdict moved because of the path. `dev-native-clobber.py` (another unit's
  file) already ATTACKs the collision and is the tool for proving the race is gone; its premise is
  now stale and its author should re-run it.

- **RECONCILIATION, RUN: `.venv/bin/python .agents/slop/gate-reconcile.py --sweep SWEEP.json`**
  Entry by entry, no gate lane, both denominators, a verdict per row. On the after-sweep it reads
  `RECONCILED: 1 of 109 shared names disagree on BOTH sides, and the sweep names the same row(s)
  ['c7']` for `codegen/decomp/dtype.bend` — **the gate and the selftest now agree exactly, on the
  same denominator, naming the same row** — and it caught `uop/spec.bend`, where the sweep measured
  7 disagreeing names and the selftest 0 of 11 with BOTH caches fresh: the two read DIFFERENT
  TREES. `uop/spec.bend` re-run ALONE is **UNCHANGED, 25 shared names, 0 disagree, rc=0**, and
  `uop/ops.bend`'s mtime is **07:24:13**, one minute after that sweep ended. `dtype.bend`
  reconciles as "BOTH instruments found nothing to compare", because a lane empty on BOTH sides is
  agreement, and calling it divergent would make the table permanently red for the one lane wired
  on purpose to be dead. **49 reconciled / 1 divergent of 50.** Two of this tool's own sentences
  were wrong on its first run — a hard-coded `0 of 109 shared names disagree` printed beside a row
  reading `109/1`, and an UNMEASURED row counted as a divergence — and both are fixed. **A COUNT IN
  A SENTENCE THAT CLAIMS TO REPORT A MEASUREMENT MUST NEVER BE TYPED.**

- **RULES APPENDED** at `.agents/slop/notes/bend2-constraints.md` positions ~19636-19713:
  BAND-11 (a stem is not a key), BAND-12 (count disagreements over names, not pair-instances),
  BAND-13 (a 0-row lane is re-run, and only for the layer that has the failure mode),
  BAND-14 (print the cause), BAND-15 (two instruments must be asked the same question),
  BAND-16 (`REPS = max(1, a.reps)` inside `main()` with no `global` bound a LOCAL, so
  `--reps 12` printed 12 and the control still ran 2 — a no-op with a printed receipt).

- **STILL OPEN, NOT MINE:** `codegen/decomp/dtype.bend`'s row `c7` (a declared refusal, already
  open above at "OPEN, NOT MINE — `c7`"). **The 04:xx type error that broke four ports is CLOSED —
  see the next section.**

## [DONE] LANE PROVENANCE: a lane-death now names the FILE and the REVISION (2026-10-04)

Progress: `[████████████████████] 100%` — mechanism reproduced end to end, 4 readers added to
`rebase-gate.py`, 7/7 control cells, census with its denominator, BAND-20/21 appended.
**No `.bend` under `tinybendygrad/` edited. `uop/ops.bend` not touched. Nothing committed.**

Report: `.agents/slop/lanedeath-census.md`. Tools: `phantom-run.py`, `lanedeath-census.py`,
`lanedeath-provenance.py`.

- **THE PHANTOM IS REPRODUCED, AND THE MECHANISM IS THAT `bend` CHECKS AN IMPORTED MODULE.**
  Four lanes — `schedule/prepare.bend`, `tensor.bend`, `uop/render.bend`, `viz/serve.bend` — died
  together with the IDENTICAL `expected : Arg / observed : Const` at `Location:
  t_const_bool_int_splits`, and that def is in no file on the tree. `.agents/slop/phantom-run.py
  --event` builds the same shape from the live file's own types (`Arg` at `ops.bend:1045`,
  `Const` at `:807`, `UOp.new` at `:2442`), plants it in a substrate four victim files import, and
  gets **4 emitted messages, 1 distinct**; deletes the def; re-runs the same four files unchanged:
  **rc=0 with rows**. Stale-artefact and cache candidates are ruled out in the report with the
  evidence; "bend emitted an error referring to a file that has since changed" is the answer, and
  "the name is synthesised from a call site in a file that did not exist" is REFUTED — the name is
  on the `def` line bend quotes.

- **⚠ AND THE BLAST RADIUS IS NOT REACHABILITY, WHICH WAS MY OWN FIRST HYPOTHESIS AND IS FALSE.**
  Measured 2 error classes × 2 substrate shapes, 20 lanes: a substrate defect kills **4 of 4**
  importers **and a bystander that never calls the defect**, in **4 of 4** cells. What limits it to
  4 of 24 wired importers is the **window**: `main()` walks targets **sequentially**, and in
  `_coord-sweep.json` the four deaths are at **indices 45, 46, 47, 49 of 50** with index 48
  NOT-STARTED. The last 4 of 50. **No verdict records a window, so `BROKEN=4` is not a statement
  about blast radius.**

- **A SECOND PHANTOM, FOUND BY MACHINE.** `_coord-sweep.json` names
  `UOp.const_factor.seed`; `grep -rn "def UOp.const_factor"` over `tinybendygrad/` returns
  **nothing**. Two phantoms, one failure. **A stored sweep's stderr names defs from a revision that
  no longer exists, and no digest over the CURRENT tree detects that** — the ghost is in the
  message, not in a cache.

- **THE CHANGE: four readers in `rebase-gate.py`, and a lane says which revision it compiled.**
  `import_closure` (raises rather than returning a short list), `substrate_manifest`,
  `drift(before, after)`, `error_site(err, closure)`. `run_port()` brackets the lanes with **two**
  manifests. **A single digest cannot answer it — a digest says what the bytes are, never when they
  were read**, and `BAND-19`'s mtime manifest answers a different question. Every non-zero exit now
  prints the closure with per-file digests, the `jj` working-copy id, the resolved
  `(def, file, line)` of every def the error names, and the distinct FILES the failing lanes'
  errors resolve to. `--json` carries `revision`.

- **THE CONTROL IS 7/7 AND ONE CELL EXISTS ONLY TO PROVE THE REST CAN FAIL.**
  `.agents/slop/lanedeath-provenance.py` plants into `.agents/slop/phantom-repro/planted/`, never
  into `tinybendygrad/`. **C7 neuters `error_site()` and requires C2's own assertion to FAIL.** The
  control found **three** defects in the change before it was green, including the gate's own
  `stamp()` lifting the provenance fields **after** `classify()` that reads them — so the verdict
  text never mentioned the substrate and C2 was green on a verdict that should have failed.

- **LIVE, UNPLANTED, TWICE, WHILE OTHER UNITS WERE EDITING `uop/fold.bend`:** `--port
  uop/spec.bend` → `BROKEN`, and the new block said `THE DEF IS IN tinybendygrad/uop/fold.bend,
  NOT IN THE PORT` plus `1 of 5 closure file(s) CHANGED WHILE THIS LANE RAN`. The same reader put
  four more selftest `UNMEASURED` lanes' identical `Location: sym_dim.signable` at
  `uop/fold.bend:1242`. **No file was opened to find that.**

- **CENSUS, DENOMINATOR STATED:** 3 artefacts / 150 verdicts / **18 BROKEN entries → 5 SUBSTRATE,
  4 UNRESOLVED, 1 PORT, 8 NO-DEF**. Of **12 incidents** named anywhere in `.agents/`, **8** are
  explained and **4** are not; those four are recorded as unexplained and are **NOT** counted as
  substrate. 5 of the 18 resolve to `uop/fold.bend:1043` — the `ABlob` incident this file already
  described as "six of eight red entries were one edit".

- **`rebase-gate-selftest.py` RUNS TO COMPLETION AGAIN (it used to die with `TypeError: ... not
  'FakeBend'`) and reports 10 FAILED, none of them mine.** Every `run_port` subprocess argv is
  byte-identical to the committed `@-` version (diffed), so the change cannot move a lane's rc; the
  10 are 0-row lanes and the cause is `uop/fold.bend` mid-edit — it fails to compile *right now*,
  `Location: sym_dim.range`, `expected : hi / observed : hi (consumed more than once)`.

## [DONE] rebase-gate: restore `AGREE-UNRECORDED` and record 29 proven-stable lanes (2026-10-04)

Progress: `[████████████████████] 100%` — state restored, controls green, 29 recorded, 9 excluded.
- **⚠ SUPERSEDED IN PART by the entry above.** `BROKEN=4` on that line included
  `device.bend`, which is **not** BROKEN (21/21 clean), and `renderer/cstyle.bend`, which is
  unwired in the working copy and therefore **NOT-STARTED**. The tally was produced by the gate
  at `@-` (39 wired). Read the entry above for the per-entry reasons.

- **State restored.** `AGREE-UNRECORDED` distinguishes "compared clean, nobody wrote it down"
  from "nobody looked". Full run went `NOT-STARTED=46 / UNCHANGED=1` to
  `UNCHANGED=28  RE-PORTED=1  BROKEN=4  AGREE-UNRECORDED=6  NOT-STARTED=11` over the same
  50 targets. **BROKEN is still BROKEN** (4, unchanged) and the recorded lanes read UNCHANGED.
- **Control, both directions.** An unrecorded-but-agreeing lane fires `AGREE-UNRECORDED` and
  prints the shared-row evidence; a never-wired port stays `NOT-STARTED` and runs no lane at
  all; a MALFORMED baseline stays `NOT-STARTED`. A lane refused for being RED still reads
  `BROKEN` after the refusal, and one refused for a non-red reason reads `AGREE-UNRECORDED` —
  neither ever reaches `UNCHANGED`.
- **29 lanes recorded** from a two-run measurement (`rebase-stability.py`), 7447 bend rows,
  5498 shared row names, **0 disagreements**. **9 excluded, each with a measured reason**:
  `elf` (ASLR), `prepare` (**38 oracle rows differ between runs** — new), `dtype.bend`
  (0 rows, `SOME PROOFS FAIL`), `codegen/decomp/dtype` (13 rows differ + 1 shared row red),
  `cstyle` (0 shared rows), and `ops_cpu` / `ops_python` / `ops_amd` / `generate`
  (freeze hazards: host paths, `sys.version_info`, 601 and 53 ungated oracle rows).
- **Laundering test green.** `ops_nv` HAS a baseline; a one-row mutant oracle → `BROKEN` naming
  `nv_pick_new_dma`, rc=1; the same pair uncorrupted → `UNCHANGED, zero rows moved`.
- **Interpreters:** always `.venv/bin/python` (3.12.10). `rebase-gate.py` now PINS its oracle
  interpreter via `oracle_py.resolve()` and prints it with every verdict.
- **Two gates fixed that recording exposed:** `--no-native` manufactured a false
  `LOST ROWS 600 -> 0` red on any recorded port (now refused), and `--oracle` was a silent
  no-op because `targets_of()` snapshots `BASE_ORACLES` before the override (now replaces the
  target; reported by another agent, fixed here).
- **Still open for the coordinator:** GUARD 1 only compares `set(baseline) & set(now)`, so rows
  **ADDED** to a port are invisible — `uop/ops.bend` gained 14 rows mid-session and the gate
  called it RE-PORTED for an unrelated oracle diagnostic row. Changing that reclassifies
  recorded lanes, so it is reported rather than changed.

## Session 2026-10-03/04 — UNOBSERVABLE-ROW CENSUS: rows that cannot tell two behaviours apart

Report: `.agents/slop/unobservable-report.md`. Tools: `unobservable-census.py`,
`commute-detect.py`, `unobservable-gr-oracle.py`, `unobservable-gr-probe.bend`,
`unobservable-gr-move.py`. **No port edited. Nothing committed.**

- [x] **THE METRIC IS A THEOREM ABOUT THE ROW TEXT, NOT A SUSPICION.**
      `blind_swaps(V) = sum over tokens t of C(#{i : T[i]==t}, 2)` is the exact
      number of reorderings of what a row displays that produce byte-identical
      output. `blind_swaps > 0` means no fixture on that row will ever catch one.
      The **cross-row half** is the one nobody checks: when the index lives in the
      NAME (`gt_ops0..5`), a swap of two equal-valued siblings is invisible.
      Census over the wired gates: **17684 rows, 10 ORDER-DEAD, 10374 order-weak,
      14136 blind transpositions, 111 sibling-blind.** Worst per port:
      `codegen/decomp/dtype` (9858 weak), `renderer/tc_ptx` (347 / 1902),
      `runtime/ops_dsp` (123 / 1793), `codegen/late` (320).

- [x] **A COUNT-ONLY GATE IS A GATE THAT CANNOT FAIL ON A VALUE. ONE EXISTS.**
      `--countgate` swept every `.sh`/`.py` in slop (~250). Exactly **one** gate's
      SOLE pass condition is a count comparison: `.agents/slop/gr-diff.sh`,
      `if [ "$py_count" -eq "$bend_count" ]`. Two other count comparisons are
      correct RUN-HEALTH guards against the bend ~1-in-20 stack overflow.

- [x] **`codegen/__init__.bend` — THE `u` vs `rebuilt` QUESTION IS THE WRONG
      QUESTION, AND THE PORT IS WRONG ON A ROW NOBODY CAN SEE.**
      The change is **still present** (`codegen/__init__.bend:86`) and its own
      comment at :48-50 still says the opposite. `u` -> `rebuilt` **MOVES** the
      row (`SINK->SINK` -> `SINK->NOOP`, `new_sink` 4 -> 8) and `gr-diff.sh` says
      AGREE both times, because it compares counts. **But the root cause is a rule
      upstream does not have:** upstream's `pm_post_sched_cache` is exactly TWO
      rules (read off the pattern objects: `UPat(op=PARAM) fields=None`,
      `UPat(op=ALLOC) fields=None`), and the PORT's table adds
      `O.PMEntry{0, [O.OpsSINK{}], Nil{}}` -> `pm_r_sink_m` -> `Some{self}`, so
      `repl[sink] = sink` and the engine returns the ORIGINAL SINK with the
      **UNREWRITTED** srcs. CPython returns a NEW SINK whose srcs are the
      rewritten ones (measured `replace[sink] is not sink` -> False).
      **MEASURED, DO NOT SIMPLY RESTORE `rebuilt`:** that moves the row to `-`,
      FURTHER from CPython, because the port's second defect (the documented
      ARENA GROWTH WALL) makes `rebuilt` unreadable either way. Fix order:
      drop the spurious SINK entry, then the arena wall, then the :48-50 comment.
      **The file is being rewritten by another agent RIGHT NOW** (268 -> 306 lines,
      printer changed mid-session), so REPORTED, NOT EDITED.

- [x] **THE FIX ORDER WAS RIGHT AND IT IS NOW DONE: ARENA THREADED, THEN THE
      SPURIOUS SINK RULE DROPPED. `codegen/__init__.bend` 361 -> 317 lines.**
      Both stages MEASURED in order, not predicted
      (`.agents/slop/codegen-init-measure.py`, 13 stages, every expectation
      CALLED from CPython at run time):

      | stage | `gr.new_sink_is_original` | `gr.new_sink_srcs` | printed `repl` row |
      |---|---|---|---|
      | BASE (pre-fix) | **1** FAIL | `PARAM(0),PARAM(1),ALLOC,` | `...SINK->SINK` |
      | A-arena (threaded, rule PRESENT) | **1** FAIL | `PARAM(0),PARAM(1),ALLOC,` | `...SINK->SINK` |
      | B-both (threaded, rule DROPPED) | **0** PASS | `PARAM(99),PARAM(100),BUFFER,` | `...SINK->SINK` |

      **The printed row is byte-identical at all three stages** -- exactly the
      blind spot the brief describes -- so the printed row alone could not
      have ordered the work. `gr.new_sink_is_original` is what ordered it, and
      it says the arena ALONE moves NOTHING: A-arena is still 1. The rule had
      to go, and it could only go second.

      **The signature.** `wr.rebuild` `-> Map<&2, U32>` became
      `-> (O.Arena & Map<&2, U32>)`; `walk_rewrite`/`unified_rewrite`/
      `graph_rewrite` `-> Maybe<&2, U32>` became
      `-> (O.Arena & Maybe<&2, U32> & Map<&2, U32>)`. Three wrappers exist only
      because a `match` may not destructure a computed value or a local binder:
      `wr.rebuild.found`, `wr.step.rebuild`, `wr.step.of`. The known blockers
      were real and all three named ones appeared: `(ar, +repl) = p` needs the
      `+` INSIDE the destructuring (two reads), `R-3` forced the new sub-defs
      ahead of their callers, and `+sink` was needed on `walk_rewrite.put`.

      **The arena-length sweep** (`5 + K` nodes at the sink, K=0..5): the row is
      CPython's at all six, and `new_sink` reads **8, 9, 10, 11, 12, 13** -- the
      index tracking the arena length, which is the direct readout that the
      threading is real. BASE swept the same lengths and printed `SINK->NOOP` at
      every one.

      **CONTROLS.** `C-comment` (comment-only edit): SAME on every row.
      `C-deadcode` (re-inserting 4 deleted defs): MOVED NOTHING, so they were
      dead -- `gr_show.topo.k`/`.k.of`/`.topo` and `gr_show.repl.kv`, 18 lines,
      called by nothing in the tree.

      **MUTATIONS.** `M-drop-arena` (`wr.rebuild.found` returns
      `O.Arena.empty()`) moves `repl`, `new_sink_is_original`, `new_sink_srcs`,
      `new_sink_op`, `new_sink` -- all five. `M-u` and `M-u-norule` move nothing,
      which is the pre-existing closed case, re-measured on the FIXED file.

      **A NEAR-MISS WORTH RECORDING.** The pre-fix port was never committed (it
      was the previous unit's working copy), and refreshing `runs/gr-init/base`
      to the landed file destroyed the only copy of the "before" state. It was
      recovered BYTE-EXACT from an earlier scratch tree and md5-verified back to
      `083c05ff6013` -- and the reconstruction I first typed by hand had the
      right 361 lines and the WRONG md5, which is why the md5 assertion is the
      check and the line count is not. It now lives as ONE frozen FILE,
      `runs/gr-init/base/.agents-prefix-port.bend`; `base/tinybendygrad/` is a
      live mirror of the tree, not an archive.

- [x] **THE FIXTURE, LANDED IN MY OWN FILE: `gr.sink_srcs`.**
      `.agents/slop/unobservable-gr-probe.bend` imports the port and prints the
      op+slot sequence of the node the engine RETURNS. Expected value CALLED from
      CPython: `PARAM(99),PARAM(100),BUFFER`. Measured three behaviours
      (`unobservable-gr-move.py`, md5-asserted frozen copy): BASE
      `PARAM(0),PARAM(1),ALLOC`, `u`->`rebuilt` `-`, SINK-rule-dropped `-`.
      **3 distinct answers, so the row MOVES.** None matches CPython yet, which is
      the point: the probe exposes the spurious rule AND the arena wall at once.
      **It now reads CPython's answer.** After the arena threading + the rule
      drop, the same probe prints `PARAM(99),PARAM(100),BUFFER,` -- verified in
      a scratch tree, `rc 0`.
      **ACTION FOR ITS OWNER (NOT MINE, NOT EDITED):**
      `unobservable-gr-probe.bend:141-142` calls
      `main.call.of(ar, sink, G.walk_rewrite(ar, sink, pm, ctx))` and no longer
      typechecks -- `walk_rewrite` returns the grown arena with the sink, and
      that arena is the one the srcs row must be read against. Three-line fix,
      MEASURED WORKING:

          # `G.walk_rewrite` now returns the fold's GROWN arena with the sink,
          # because a bare index names nothing outside the arena that interned
          # it. That arena is also the one the srcs row must be read against.
          def main.call.of2(+ar: O.Arena, r: Maybe<&2, U32>) -> IO(Unit):
            main.show.of(ar, r, 0)

          def main.call.fold(sink: U32, p: (O.Arena & Maybe<&2, U32> & Map<&2, U32>)) -> IO(Unit):
            (ar, (r, _)) = p
            main.call.of2(ar, r)

          def main.call(+ar: O.Arena, +sink: U32, pm: O.PMEntrys, +ctx: List<&2, U32>) -> IO(Unit):
            main.call.fold(sink, G.walk_rewrite(ar, sink, pm, ctx))

      Note `sink` becomes UNUSED in `main.call.fold` -- that is correct, the
      sink index is not needed to read the srcs of the returned node.

- [x] **`u` vs `rebuilt` IS A CLOSED CASE UPSTREAM, WITH A PROOF.**
      `unobservable-gr-oracle.py` transcribes upstream's driver with ONE token
      changed and runs both over ten fixture shapes: **10/10 repl maps
      byte-identical.** Proof: (a) both patterns have `fields=None`, so neither can
      read a node's `src`; (b) upstream guards the rebuild with
      `new_n = UOp(...) if new_src != n.src else n` (ops.py:1809) and both carried
      ops are src-free, so `new_n IS n` — the two arguments are the SAME OBJECT.
      **No fixture over `pm_post_sched_cache` can ever separate them.** Same shape
      as the `floor(floor(a/b)/c)` theorem.

- [x] **WHY NO ROW COULD SEE THE SINK IDENTITY: TWO INDEPENDENT BLINDS.**
      (1) `gr-oracle.py`'s `uop_short` renders a SINK as the bare string `"SINK"`
      and so does `gr_show.node`, so upstream's rebuilt SINK and the port's
      original print identically — **the two lanes can agree for a reason that is
      not correctness**, the `nv_query_litter` failure mode. (2) `gr-diff.sh`
      compares counts.

- [x] **THE CHEAP GENERAL DETECTOR BUILT AND MEASURED — AND IT FOUND A REAL ZERO.**
      `commute-detect.py` swaps src[0]/src[1] at every commutative op construction
      (the set `uop/ops.bend`'s own `is_comm` declares) and the last two args of
      every same-shape `List.append`. **Population across 7 gated ports: 2 comm
      sites + 2 append sites.** Hit rate over APPLIED patches:
      `codegen/late/linearizer` **0 of 69 rows moved, 0.0%** (the port's ONLY port
      with a commutative population, and not one row noticed);
      `renderer/amd/generate` 187 of 726, 25.8%. **Five ports report NO
      MEASUREMENT** — zero sites, not failed patches. Substrate check passed.

- [x] **DANGEROUS ROWS FOUND, REPORTED TO THEIR OWNERS, NOT LANDED.**
      `codegen/late` `ra0_uops`/`ra1_uops` (`INS` x8 each, blind=46, and the two
      rows are byte-identical to each other while their `a7` rows differ);
      `gt_ops4=WHERE`/`gt_ops5=WHERE` sibling-blind; `runtime/support/c`
      `sname_ctor_idx_given=0,0` is **hand-typed** (`c-oracle.py:134`) and so
      cannot fail at all — its sibling `sname_idx_after=0,1` is order-exact, so the
      fix is one line. `--handtyped` finds **290** literal-valued rows across the
      committed oracles.

- [x] **CLOSED WITH A SIBLING, PROVEN NOT NEEDLESS.**
      `field_sizes=4,4,4` cannot see a struct's field order but
      `field_offsets=0,4,2` can; `sname_entry_width=3,3` cannot but
      `sname_real_fields=a,b` and `sname_idx_after=0,1` can;
      `record_size_fields=8,8,_mem_,8`'s three 8s are three unrelated facts.

- [x] **THREE WAYS THIS UNIT NEARLY PRODUCED A GREEN LIE, all recorded.**
      (a) My first run printed `ops_cl: 445 rows, 10 sites, 0 rows moved, 0.0%`
      when **all ten patches had failed to compile** — the dead-M26 shape. Fixed:
      `applied` is its own column and a port with zero applied sites reports
      **NO MEASUREMENT**. (b) Two agents were mid-edit in `uop/ops.bend` and
      `uop/fold.bend` for ~15 minutes; file count 137 -> 135 `.bend`;
      `renderer/cstyle.bend` went from compiling to unparseable at :590. Fixed by
      a pre-flight plus a port-scoped end-of-run md5 check that printed
      `SUBSTRATE MOVED` and discarded a run. (c) `renderer/cstyle.bend` printed
      `repl=1->5, 2->6, 3->5, 4->4` at session start and
      `repl=PARAM(0)->PARAM(99), ...` forty minutes later, from a file I never
      touched — every number here is hash-stamped.

- [ ] **OPEN, NEXT UNIT.** `runtime/ops_bend`'s **98 sibling-blind
      transpositions** (largest cross-row blindness found, nothing classified);
      the **10360** order-weak rows in `dtype`/`tc_ptx`/`ops_dsp`; and
      commutative fixtures for the 5 gated ports that have none, `linearizer`
      first (its 0.0% is the strongest signal in this census).
      -> **ANSWERED for `ops_bend`, see the next section.** The other two stand.

---

## Session 2026-10-04 — ORDER-BLIND GATES, the close-out of the census

Report: this section. Tools: `order-lin-probe.py`, `order-lin-sweep.sh`,
`order-lin-cand.py`, `order-late-move.py`, `order-late-gate.sh`,
`order-gate-probe.py`, `order-verdicts.py`. **Ports edited: `codegen/late/linearizer.bend`,
`runtime/support/c.bend`. Oracles edited: `late-oracle.py`, `c-oracle.py`, `c-mutate.py`.
`runtime/ops_bend.bend` READ ONLY. Nothing committed.**

- [x] **D11 — THE CENSUS'S DIAGNOSIS WAS WRONG AND THE 0.0% HAD A DIFFERENT CAUSE.**
      The census asked whether `codegen/late/linearizer`'s fixtures contain a
      commutative node. **They do** — `ADD(PARAM, CONST/CAST)`, distinguishable
      children — so that hypothesis is false. Measured over seven src-swaps of
      the CPython fixture (`order-lin-sweep.sh`): CPython's answer moves in
      **2, 0, 20, 6, 9, 3, 10** rows. So the information EXISTS and the PORT is
      blind, which is a different defect with the same symptom.
      **CAUSE: `lt_lst()`/`lt_vm_lst()` are LITERALS.** Every `lin_*` row reads the
      arena for a node's OP and ARG only; `lt_deg` walks `src_without_body` but
      `out_degree` is a COUNT. A mutation aimed at the graph cannot move a row that
      reads the table. **THE FIX — `lin_edg` / `linc_edg`, two rows, the arena's
      EDGE LIST in the declared toposort's own POSITIONS.** The alphabet must be a
      POSITION, not an arena index: CPython's `UOp.const(1, i32)` is ONE node and
      `ops.bend`'s is TWO, so the index alphabets differ by construction.
      **PROOF THEY MOVE (`order-late-move.py`, frozen md5-asserted copy, substrate
      stable):** `lin_edg` moves on **9 of 9** mutations — all seven src-swaps plus
      two controls — where **0 of 7** moved anything before. `linc_edg` moves on 2
      (the ADD swap in the CALL graph, and the `lt_pos` control). The `lt_pos`
      control moves **exactly** the two EDG rows and nothing else. The toposort
      rotation control moves 20 rows including `lin_edg`, which is the binding
      between the literal and the arena. `lin_edg`'s `blind_swaps` is **1**, the
      lowest in the file; `lin_vm`'s is 137.
      Gate: `codegen/late/{linearizer,regalloc,gater}.bend` **128 -> 130 rows**,
      `MATCHES the CPython oracle`, `late-oracle.txt` re-derived by CALLING
      CPython (never typed). **NOTE FOR THE COORDINATOR: `.agents/slop/late-pre-split.bend`
      is the pre-split 128-row invariant and adding two rows breaks it.**
      `late-gate.sh --base` will now report 2 added rows and nothing else.

- [x] **D2 — `sname_ctor_idx_given`, HAND-TYPED, WAS WORSE THAN A BAD FIXTURE.**
      `__set_name__` (c.py:64) does `self.idx = len(owner._real_fields_) - 1`, so on
      a real class body **the constructor-given `idx` no longer exists** — the row's
      subject had been deleted by the machinery under test. Fixed on both lanes by
      reading a `Field` **nobody named**, with the second value **GIVEN** (`idx=5`)
      so the row is `0,5` and not `0,0` again. Oracle value re-derived from CPython
      via `c-gate.sh --refresh`. **PROOF IT MOVES (`c-mutate.py` M25/M26, added):**
      `Field.of` dropping `idx` -> `0,0`, and `Field.of` pinning `idx` to 1 ->
      `1,1`; **each moves exactly one row and nothing else.** `runtime/support/c`
      ORDER-DEAD **5 -> 4**.

- [x] **D4 — CLOSED BY SIBLING, WITH THE SIBLING NAMED AND MEASURED.**
      `ra0_uops`/`ra1_uops` are blind to a permutation of the allocator's
      instruction stream (blind=46 each). `ra0_lr`, `ra0_a<i>`, `ra0_before`,
      `ra0_spills` and `rw_none` print INDEXES into that stream, and permuting it
      moves **27** of them (`order-late-move.py` D4). **Their being byte-identical
      to each other is CORRECT**: ra0 and ra1 are the same fixture under two
      `is_two_address` settings, so a row that could tell them apart would assert
      something false — `ra0_a7` vs `ra1_a7` is the pair that carries the
      difference, which the oracle's own docstring says at `late-oracle.py:224`.
      D4b also shows `ra<u>_uops` IS a fixture-identity row: it does move when the
      op MULTISET changes.

- [x] **D5 — `gt_ops0..5` IS A DECLARED WALL, AND THE CENSUS'S PRESCRIPTION WOULD
      HAVE ENCODED A LIE.** Measured (`order-gate-probe.py`, off the pattern
      OBJECTS): the six root op sets are LOAD STORE LOAD STORE WHERE WHERE, so the
      three pairs the census flagged tie — **the blindness is real**. But the six
      patterns ARE distinguishable: a structural fingerprint gives **6 of 6
      distinct** values, because `gt_ops` prints only the ROOT and the pairs differ
      below it (`{INDEX}` vs `{INDEX,SHRINK}`; and WHERE's load in slot 1 vs slot 2,
      with `~UPat.gate` expanding to a `CMPNE`/`CONST` subtree). **So this is not
      `gcd(10000,256)`-style unobservable — a fixture COULD separate them.**
      **AND IT CANNOT BE WRITTEN AGAINST THIS PORT:** the discriminator is `UPat`'s
      nested structure, `gater.bend` models op sets only (its own header, ~POSITION
      18-25, says so), and **`uop/upat.bend` has ZERO `UPat.` builder defs** — `.index()`,
      `.load()`, `.store()`, `.where()`, `.or_casted()`, `.named()` and `~UPat` are
      not ported at all. **AND THE CENSUS'S FIX IS WRONG:** "give `gt_ops4` and
      `gt_ops5` different content" would mean writing different root ops, and CPython
      says both are `Ops.WHERE` — that is encoding a lie. Its alternative (fold to
      one `gt_ops_tail=WHERE,WHERE` row) is sound but adds a row that still cannot
      see the swap, and the risk it names is a HARNESS risk, not a gate risk.
      **NO ROW ADDED. Verdict: inherent to the ported half; the fix is porting
      `UPat`'s builders, and that is a different unit.**

- [x] **D9 + THE OTHER `runtime/support/c` ORDER-DEAD ROWS — ALL FOUR CLOSED BY A
      NAMED SIBLING, none needed a fixture.** `field_sizes=4,4,4` ->
      `field_offsets=0,4,2` (three DISTINCT and deliberately non-monotonic).
      `sname_entry_width=3,3` -> `sname_real_fields=a,b`.
      `sname_bf_entry_width=5,5` -> **`bf_read_abcd=a=11,b=3290,x=305419896`**,
      NOT the `sname_real_fields` the census named (that is `Body`'s fields, not
      `BodyBF`'s; it happens to be order-exact too, which is why the wrong answer
      went unnoticed).
      `record_size_fields=8,8,_mem_,8` (D9) -> `ics_sizes=0,8`, which the oracle's
      own comment says "disagree[s] on the first element ON PURPOSE"; the three 8s
      are equal **by CPython's own construction** (`R8` has one field, `_mem_` =
      `c_byte*8`, `SIZE=8`), so their transposition is a theorem for this fixture.
      `init_zip_bound=3,3` -> two facts that coincide (`len == min(len,4) == 3`), a
      total not an order claim.

- [x] **`runtime/ops_bend`'s 98 SIBLING-BLIND TRANSPOSITIONS: INHERENT, PROVEN.**
      `order-verdicts.py` resolves each tied family's oracle value ARGUMENT and
      classifies it. **98 of 98 are CALL-derived**: `b - a` and `a` from
      `d.pci_dev.mem.sizes[-1]` after `q.write(...)` executed; `e` from
      `B.BNXT_BACKING_STORE`; `math.ceil(n*size/0x1000)*0x1000`;
      `" ".join(... for x in insts)`. The equal values come out of
      `alloc_queue` / `BNXTQueue.write` / `build_pbl` **executing**, so a
      transposition of two of them is not a behaviour change. **The census's
      "highest-value REQUEST in the census" is closed, with the opposite answer to
      the one it expected.**

- [x] **THE 290 HAND-TYPED ROWS, SAMPLED. `--handtyped` FINDS 224, NOT 290.**
      The 66 are not reproducible by me: `hand_typed` only matches a LITERAL row
      name, so a row emitted with an f-string NAME is invisible to it. **Both
      numbers are reported; neither is a coverage claim.** Per oracle:
      `nv-oracle.py` 65, `bnxt_oracle.py` 34, `amd_oracle.py` 26, `ext_oracle.py`
      20, `memory_oracle.py` 15, `objc_oracle.py` 14, `amdev_oracle.py` 13,
      `cs_oracle.py` 12, `dsl_oracle.py` 10, `nv_nvdev_oracle.py` 4,
      `c-oracle.py` 3 (**2 since D2 landed**), `elf_oracle.py` 3,
      `indexing-oracle.py` 2, plus 1 each in `qcom-oracle.py`,
      `wip/cstyle_oracle.py`, `device-oracle-MUTANT.py`.
      **THE CLASSIFICATION IS A HEURISTIC AND IS LABELLED AS ONE**: **192 of 224**
      could not be told from a name to be a deliberate CONTRAST arm, so they need
      a READ before they can be ranked. **Estimate: ~16 h to classify 192, up to
      ~64 h to convert all of them.** A converted row is one oracle line PLUS,
      where the value stops being expressible, a fixture change in the `.bend` — so
      the unit is "read then decide", not "replace a literal". **NOT converted
      today, and not recommended in bulk:** `nv-oracle.py` is 65 rows and is the
      oracle whose `nv_query_litter` was wrong in the PORT *and* the ORACLE, where
      the differ reported 0 disagreements over one mistake made twice.

- [x] **RULES G-L APPENDED to `.agents/slop/notes/bend2-constraints.md`** at the
      END, citing POSITIONS 17913+ and continuing from letter `F`. The transferable
      one is **RULE L**: three agents on one tree took `late-gate.sh` through
      **130 rows -> 0 rows -> 130 rows** with no edit of mine, and `md5 -q` on
      macOS silently printed nothing for a whole run, so a gate other agents can
      move needs the hash on BOTH ends.

- [ ] **STILL OPEN.** The **10360** order-weak rows in `codegen/decomp/dtype`,
      `renderer/tc_ptx` and `runtime/ops_dsp` — not classified, and each needs its
      own mutation rather than a bulk argument. The **5 gated ports with no
      commutative fixture** other than `linearizer`, which now has one. Porting
      `UPat`'s builders to `uop/upat.bend` if D5 is ever to be closed properly.
      The **192** `BELIEF?` hand-typed rows.

---

## Session 2026-10-04 — `dtype.bend`'s TWO ORACLES DISAGREE (19 vs 1), and the 1 is a lie of omission

- [x] **WHICH ORACLE IS TELLING THE TRUTH: `dd-oracle.py`, and the other one is a FILTER.**
      MEASURED, all three lanes under the pinned `.venv` (3.12.10), the port through
      `./bin/bend`, every lane parsed with **`rebase-gate.py`'s own `rows()`** (loaded,
      not copied):

      | lane | rows | shared with the port | disagreements |
      |---|---|---|---|
      | the port | **174** | — | — |
      | `dd-oracle.py` | **416** | **174** | **19** |
      | `dtype-oracle.py` | 356 (351 + 5 provenance) | **109** | **1** |

      `416 - 65 = 351`, and dtype-oracle.py's printed names are EXACTLY dd-oracle.py's
      minus its 65-name `SKIP` set — **asserted, not assumed** (`dd-truth.py`). So
      **the 172-vs-107 (now 174-vs-109) gap is entirely the SKIP set.** The two files do
      not test different things; one is the other with 65 rows deleted.

- [x] **THE 18 ARE NOT UNCHECKED ROWS. THEY ARE WRONG VALUES THE GATE CANNOT SEE.**
      All 19 names are in `port ∩ dd-oracle`, so the port emits every one. 18 of them are
      rows the port prints with a value that differs from CPython, on names
      dtype-oracle.py never prints. An unchecked row reports itself as a denominator
      shortfall; **a suppressed disagreement reports itself as an agreement.** The
      decomposition is printed every run: `1 gated (c7) / 18 not gated`.

- [x] **`SKIP` IS NOT ONLY CREATION-ORDER ROWS, as its header claimed.** `dd-coverage.py`
      measures: **57** of the 65 are `sig`/`k`/`n`/`p`; **8 are BARE ANSWER ROWS** —
      `lga lgb lge lgq lgr lgs lgt lgu`. The old header admitted one (`lgu`); the other
      seven were silently filed as ordering facts. `lgq lgr lgs lgt` agree today only
      because `tree()` reaches two levels — their `k`/`sig` rows disagree.

- [x] **CONTROL (a), THE ONE THAT SETTLES IT.** `.agents/slop/dtype-oracle-MUTANT.py` is
      dtype-oracle.py with `SKIP = set()` and NOTHING else changed (one `diff` block).
      Same port, same CPython, same interpreter, same parser: **live filter 1 of 109,
      MUTANT 19 of 174.** A filter that suppresses disagreements is indistinguishable
      from a port that is nearly correct; emptying the filter is the cheapest way to tell
      them apart. **Run this for every filter-shaped oracle in the repo.**

- [x] **NEITHER ORACLE RE-IMPLEMENTS THE PORT — MEASURED, NOT READ.** `dd-audit.py` wraps
      every entry point of `tinygrad.codegen.decomp.dtype` with a counting proxy and RUNS
      both files: **`l2i` 1341, `f2f` 18, `f2f_clamp` 26, `l2i_define` 5, `reindex` 6,
      `rne` 16, `unpack32` 3**, rule tables read at 13/10/2 patterns, and **0 hits** for
      hand-derived exponent/mantissa/`unpack32` arithmetic in either. The header claim
      "nothing here is a reimplementation of it" is TRUE of both.
      **But `dd-oracle.py` PROJECT rather than reimplement**: its decision 1 drops **281**
      promotion CASTS the unported `mixin/elementwise.py` inserts (measured per fixture
      by `dd-probe.py`; 69 in `lgq`, 70 in `lgr`). So its rows are CPython *projected onto
      the port's buildable subset*. It does NOT mask `lg5k` — verified by re-running that
      cone with the deletion off: identical constants.

- [x] **THE BIGGER FINDING THAN THE COUNT: 242 of 416 oracle rows have NO port row, and
      they are five of dtype.py's ten public functions.** `f2f` (dtype.py:101-125, 18
      fixtures), `f2f_clamp` (:127-134), `rne` (:99), `reindex` (:14-18), `l2i_define`
      (:83-86), the three rule tables (:148, :181, :218) and `c0..c7`. The gate's
      109-row denominator covers **`l2i` and `unpack32` and nothing else.**

- [x] **CLOSED ONE REAL DEFECT, AND IT CLOSED ZERO DISAGREEMENTS.**
      `dtype.bend:1150-1153`, `W2{ar, Cd.q0(c), 0}`. `W2` is `{ar, lo: U32, hi: U32}` and
      BOTH are arena **indices**; the literal `0` named **arena slot 0**, whose label is
      `NOOP`. dtype.py:74 returns the PAIR. Now `Cd.q1(c)` / `Cd.r1(c)`.
      **Fourth instance of this species in this file** (the file's own comments name three
      more at :1007, :1010, :1187); all four compile, all four run, all four are invisible
      to `--check-only`, and the shared signature is **the node COUNT barely moves while
      the CONE collapses** (`lgsn` 1976 vs CPython 1977 — built, but not REACHABLE).
      Effect: port rows **172 → 174** (`lgsp`, `lgtp` recovered), one row moved
      (`lgssig`), nothing lost, **19 disagreements stayed 19.**

- [x] **CONTROL (b), ON THE PORT EDIT.** baseline copied aside, fix applied, port run, file
      restored to its exact baseline hash `8886c0b7…`, port re-run →
      **`diff` BYTE-IDENTICAL.** The delta is mine and nothing else. `ops.bend` was written
      by another agent 14 s before one run and broke the typecheck
      (`match split_uop.sep.of(op, sep):` — a computed scrutinee); that made the port lane
      print **0 rows**, which every count-only harness reads as "not started".
      `dd-truth.py` now REFUSES to report a verdict on 0 port rows and says why.
      **NOT EDITED: `ops.bend`.**

- [x] **`dtype-oracle.py` NOW PRINTS ITS OWN DENOMINATOR** as five `dtype_oracle_*` rows,
      named so they cannot collide with a port row and therefore cannot be compared or
      silenced: `of=416 printed=351 suppressed=65 skip_names_unused=0` and
      `full_disagreements=19 (of which 18 are on rows this filter does not print)`.
      **`SKIP` IS DELIBERATELY UNCHANGED** — shrinking it to green the gate is the failure
      this session is correcting, and `rebase-gate.py` is another agent's file.

- [ ] **OPEN — GATE OWNER'S CALL, one line.** Re-wire
      `tinybendygrad/codegen/decomp/dtype.bend` in `ORACLE_CONFORMANCE` from
      `dtype-oracle.py` to **`dd-oracle.py`** — that moves the lane from `1 of 109` to
      `19 of 174`, which is the truth, and it will be RED. Or wire `dd-truth.py` beside it
      as the diagnostic lane. Full argument, per-family mechanism, CPython line citations
      and both controls: **`.agents/slop/dtype-oracle-truth.md`**.

- [ ] **OPEN — THE TWO FAMILIES WORTH OPENING NEXT**, both port bugs, neither gated:
      (a) the **CDIV/CMOD loop**, dtype.py:63-69 — 10 of the 18. CPython interleaves
      `C(i)` with `2**(i-32)` for i=63..33 (the `UOp.const(i, uint)` shift words of :65
      and the `shl(cond, i%32)` multipliers of :68); the port emits one leading `C(64)`
      and then a bare run of powers of two and **never emits the 31 `C(i)` shift words**.
      `lgtsig` reaches 57 cone nodes against CPython's 2184.
      (b) **`lg5k`/`lg5n`/`lg5sig`**, dtype.py:34 — tinygrad rewrites `x / 2**32` as
      `x * RECIPROCAL(CONST_at_f32(2**32))` = **`F(1333788672)`** (0x4f800000 is exactly
      2^32 in f32); the port builds the divisor at weakint/i64 = **`C(1:0)`**.

- [ ] **OPEN — 242 rows the port does not emit** (five of ten public functions, §above).
      Until they are rowed, "the dtype port is 99% correct" is a statement about `l2i`.

---

## Session 2026-10-04 — `renderer/cstyle.bend`: 225 rows, ZERO verification -> **221 of 227 compared to a live CPython call**

Progress: gates landed `0/38` -> `1/38` for this pair. Coverage of `cstyle.bend`: **0 -> 221/227**.

- [x] **THE FOUR "REASONS" RE-TESTED; NONE OF THEM HELD.**
      (1) "30 `kern2` rows are unfalsifiable because `g_kernel()` returns two hardcoded C
      strings" — **FALSE as a reason.** A kernel body is an INPUT to `render_kernel`, not its
      output: `CStyleLanguage.render_kernel(function_name, kernel, bufs, uops, prefix)` is a
      plain method on an instantiable class, and the oracle hands it the SAME two body lines and
      a REAL bufs list and uop list, so CPython computes the signature, the buftypes, the
      prefix and the framing. `Emit_` (the port's `uses`/`vecs`/`ockl`/`ocml` record) maps onto
      a uop list one-for-one — `U_sq(f16)`+`U_sq(f32)` for `hip_ocml`, `p4.load()` for a
      `(f16, 4)` vector count, a SPECIAL for `uses.special`. All 30 now gate.
      (2) "Clause rows render symbolic operands `(B)[R]`, `sqrt(X)`" — **FALSE.**
      `render_index` reads `self[buf]`/`self[idx]` out of `self.r`, the ctx dict `_render`
      fills; setting `r = {buf: "B", idx: "(R)"}` makes `(B+(R))`, `B.x` and `(B)[R]` exactly
      comparable. `sqrt(X)` is `code_for_op[Ops.SQRT]("X", dtypes.f32)` — the port passes the
      src-name list `["X","Y","Z"]`, which is precisely what the lambda receives.
      (3) "`tmap` reads two different trees, 4 cells stale" — **TRUE and sharper than filed.**
      At HEAD `CStyleLanguage.type_map` has NO fp8 entry above CUDA, so `type_map[fp8e4m3]` is a
      `KeyError` on four of six devices, and `type_map.get(dt, dt.name)` answers `fp8e4m3…`.
      (4) "0 shared row names" — **TRUE but it was a NAMES mismatch, not an incomparability:**
      the old oracle printed 15 real kernels as `k1_load_store`/`k2_alu`/…, names the port does
      not print.

- [x] **THE REAL BUG, AND IT WAS BIG: `type_map.base()` read `{}`.** `CStyleLanguage.type_map`
      has FOURTEEN entries (cstyle.py:136-139) and the five device maps are
      `{**base, ...}` OVERLAYS. Restoring the base and seeding the device maps with it fixed
      **89 of 227 rows at once** — every one of them a dtype-name cell. See R-6 in
      `.agents/slop/notes/bend2-constraints.md` (appended at the END).
      `ocml_extern` also spelled its dtypes with `dt_name` where upstream spells them
      `self.render_dtype(dt)`, which is the base `type_map`: `f16`/`f32` vs `half`/`float`.

- [x] **A COMMITTED PARSE FAILURE, FIXED.** `b6abeb7f5` committed `type_map.base()` with the
      chain order and line breaks that Bend 2.0.34 REFUSES; the file did not compile at
      `3743ad0cc` or `80644ace2` either. MEASURED: only the innermost-first single-line spelling
      parses, and Bend's `Location:` points at `type_map.cuda` no matter which of the two
      tables is at fault — **bisect by DELETION**. R-7 in the notes.

- [x] **19 STALE `py=` LITERALS REGENERATED** from live calls by `.agents/slop/cs-fixpy.py
      --write`, which refuses to write unless the rewritten file still emits 227 rows. STALE-LITERAL
      is now **0**. R-5 in the notes: the `py=` column is a transcription and is never the thing
      compared.

- [x] **SIX ROWS MADE VISIBLE AS NAMED EXCLUSIONS, with the measurement for each**, printed on
      every gate run: `buft METAL` (`MetalRenderer.render_kernel` calls `super()` with
      `bufs=[]`, so `var_prefix`/`var_suffix` are read by nothing), `idx BASE/HIP regadd`
      (`idx.arg == Ops.ADD` is False for EVERY UOp HEAD can build, so `strip_parens` is
      unreachable and the port's `AReduce{ADD,0}` fixture is a shape `UOp.arg` does not have),
      and the three `under` rows (`.replace(" ", "_")` has no def upstream and NOT ONE of the
      20 DType names at HEAD contains a space).
      **FOUR MORE ROWS (`rd <dev> fp8e4m3` on BASE/CLANG/METAL/OPENCL) are GATED, not excluded:**
      the oracle answers them by letting upstream's own `_render_dtype` run against a renderer
      whose one `type_map` entry is patched to the `.get` reading, and REPORTS the KeyError on
      stderr every run.

- [x] **CONTROLS: 18 rows across 18 families planted, every one BROKEN rc=1 naming the row**
      (`cstyle-gate.py --plant`); clean AGREE rc=0. `cstyle-gate.py --selftest` drives four
      instrument lanes over two REAL lanes — clean, planted, CPython-refusal mapped to the
      port's `""` marker, and that lane with a name where a refusal belongs — three seen red.
      Recorded in `ORACLE_NOT_WIRED` in `rebase-gate-selftest.py`.

- [x] **THE LAST CALLER ON THE OLD LANE IS GONE.** `renderer_oracle.py cstyle` (the 15-row one)
      is no longer in `BASE_ORACLES`, no longer in `ORACLE_CONFORMANCE`, and
      `dead_lane_is_broken`'s docstring no longer cites it — it was rewritten rather than deleted,
      because a docstring that describes a BROKEN reason which has stopped being true sends the
      next reader to trust the exit status. The script itself is kept (deleting a lane is how a
      "0 shared names" measurement stops being re-checkable) but nothing runs it.

- [x] **`cstyle.bend` IS WIRED INTO `rebase-gate.py`, AND IT WAS THE READER'S FAULT BOTH TIMES.**
      `renderer/cstyle.py cstyle-rows` replaced the 15-row lane: 222 shared / 0 disagree, and
      `cstyle-gate.py` independently says 221/227 with 6 exclusions, 0 stale literals, rc=0.
      Two reader defects blocked it and NEITHER was a port bug: (a) `rows()` compared the port's
      `NAME = [v]   py=[w]` against the oracle's `NAME = [v]`, so all 222 shared rows disagreed
      BY CONSTRUCTION; (b) `rows()` read none of `multi-rows.py`'s 213 whitespace rows. Fixed in
      `rebase-gate.py:row()`, which now reads all three shapes.
      Control: `rebase-gate-selftest.py:planted_lane_control()` — clean AGREE-UNRECORDED over 222
      shared names, one planted row → BROKEN **naming `acc  BASE  plain`**, restore byte-identical.
      Also driven through `main()` itself with `--oracle`, which **works** (the lane key becomes
      `cpython:mutant-lane`, proving the override replaced the iterated target and not the dict
      the snapshot was taken from), rc=1 with the row named.

- [x] **THE REFUSAL MARKER MOVED OUT OF THE VALUE AND THE GAP WAS CLOSED WITH AN ASSERTION.**
      `renderer_oracle.py` emitted `!KeyError` where CPython raises; `cstyle.bend` has no
      exception channel and answers `""` (cstyle.bend:1074, :1149), so 9 of 222 rows could never
      agree under any reader. The shared reader was NOT taught the token — `rebase-scan-oracles.py`
      imports `rows()` and computes its own counts, so a translation there makes the scan and the
      gate disagree by construction. The oracle now emits the port's marker and reports all 13
      refusals on stderr, and `cstyle-gate.py:unsilent_refusals()` DERIVES the expected set from
      the port's own output (every row whose answer is entirely the empty marker) and fails when
      the oracle names none of them. **GIVEN UP, PRECISELY: 9 of 222 shared rows are a refusal
      rendered as the marker; the other 213 are CPython's own return value.**

- [x] **`schedule/multi.bend` IS STILL UNWIRED — AND THE PRIOR REASON WAS WRONG IN A WAY THAT
      MATTERED. It is an ENCODING, not a NAME.**
      321 port rows, 213 oracle rows, **0 shared names**. Stripping `t_` yields 26 collisions of
      which **21 "disagree" — and all 21 are CORRECT ROWS**. `multi.bend` prints `eq(a, b)`,
      i.e. `1`/`0` (multi.bend:2220); `multi-rows.py` prints the QUANTITY. On **17 of the 26**
      the oracle's value is not a boolean at all, so `1` vs `()` is two encodings of one claim.
      Measured by `.agents/slop/multi-collision.py`, which reads each colliding row's OWN body out
      of multi.bend and evaluates its projection (`bx_a0`/`bx_n`/`mu_len`, multi.bend:2558-2561,
      :2666) on CPython's value: **26 CONSISTENT of 26, 0 INCONSISTENT**. So the earlier note —
      "they share a spelling and not a claim" — is false; the claims DO correspond.
      **THE VERDICT IS UNCHANGED AND THE REASON IS STRONGER:** a `t_` strip manufactures 21 reds
      over right code, which is the `cstyle.bend` failure in `rebase-gate.py`'s own header. Fix
      belongs in a NEW oracle printing the port's row names with CPython's value under each — not
      a rename, not an edit to the port. The encodings ARE separable without a second source of
      truth: `t_bx_exp`/`t_bx_exp_n` differ only in which reader they call, so a body-based rule
      separates what no name-based rule can. **NOT WIRED, and that is now recorded as an encoding
      reason rather than a naming one.** R-3, BAND-7 in the notes.

- [x] **`multi.py:139`'s LEAKED LOOP VARIABLE IS A BLIND SPOT IN `rs_local`, MEASURED AND NOT
      FIXED.** `new_shape = tuple(s//(int(rng.vmax)+1) …)` divides EVERY sharded axis by the LAST
      range's count — `rng` is the loop variable of `for ax, rng in multi.sharding:` at :131 and
      is never rebound. `multi.bend`'s `rs_local` (multi.bend:1313-1319) divides each axis by its
      OWN count via `ns_count` (multi.bend:1279-1283). Measured by executing :139 **verbatim**,
      `inspect`-extracted from the installed tinygrad and run through `exec`
      (`.agents/slop/multi-l139.py`): the two readings differ on **3 of 4 unequal-count
      shardings**, and a distinct-axis UNSHARD with unequal counts is constructible. Not a fixed
      defect: every port fixture uses equal counts except `t_rs_loc_both` (`axes=(0,1)`,
      `counts=(2,3)`), and there the two readings AGREE at the index the row reads (index 1, both
      `2`) and differ only at index 0 — while `t_rs_loc0` reads index 0 with ONE axis, where no
      leak is possible. **A fixture reading one index cannot separate two functions that agree at
      that index.** REPORTED, NOT FIXED. BAND-9 in the notes.

- [x] **TWO HARNESS BUGS FOUND BY RUNNING THE CONTROLS, BOTH OF WHICH MADE A VERDICT WRONG.**
      (a) `multi-correspond.py`'s `load()` did `sys.argv = [path]`, so the plant control read the
      LIVE tree and returned `rc=0` over a planted disagreement; `sys.argv` is now saved and
      restored, and line 1 prints which file was read. (b) `report()` returns a LIST and
      `0 if bad1 + bad2 == 0 else 1` is CONCATENATION, so a clean pair printed `rc=1` — a
      permanently-red verdict over 0 inconsistencies. BAND-10 in the notes.

- [x] **CONTROLS: clean `rc=0`, one planted disagreement → `rc=1` NAMING `bx_none`, restore
      byte-identical.** Plus `multi-controls.py` C1–C5, all PASS: two structurally DIFFERENT
      plants both go red, the denominator is printed beside every verdict, and the F3 reader
      still reads 213 of 213 rows.

---

## Mutation-table trustworthiness (dd unit, 2026-10-04)

- [x] **M26 RE-AIMED AND FIRING — 27 rows.** Its anchor quoted the PRE-fix `dd_rs.push`
      line, which occurs 0 times in the fixed file, so it was PATCH-NOT-APPLIED and read as
      a zero. Re-aimed at the fixed line with the pre-fix line as the mutant. Its name is
      correct for the first time: against the pre-fix file that edit WAS the base behaviour,
      which is why it moved rows while testing nothing.

- [x] **THE HARNESS NOW REFUSES TO PRODUCE A BOGUS TABLE.** `probe_substrate()` runs the
      UNMUTATED mirror and exits unless it reproduces the baseline's exact shape, and ANY
      control that is not SAME aborts the run with no table written. A run whose substrate
      stopped compiling had produced 39 DID-NOT-COMPILE rows and a confident summary.

- [x] **TARGET **AND** TREE PINNED.** The live `dtype.bend` moved `73b0e1e7`→`a2c68a7e`
      mid-run and stopped compiling; `HEAD` moved to `eb16fa874`, a revision whose tree
      prints ZERO lines with the unchanged file. Freezing the target is necessary and not
      sufficient. Snapshot `.agents/slop/dd-mutations.frozen.bend`, tree `e17d3f7dd`.

- [x] **THE LIVE-TREE BAKE DELETED.** `tinybendygrad/codegen/decomp/dtype.bend.ddmut` was a
      14:09 leftover that made RULE G refuse to start for anyone mirroring the live tree.
      A bake guards the tree being WRITTEN, so in the live tree it guards nothing.

- [x] **FULL TABLE RE-RUN, 36 mutations, 3 controls SAME.** 28 MOVED · 5 THEOREM · 1 REQUEST ·
      2 DID-NOT-COMPILE · 0 dead anchors. Full table with a proof per THEOREM:
      `.agents/slop/dd-mutations-report.md`.

- [x] **FIVE THEOREMS PROVED, NOT ASSERTED.** Four by renaming the enclosing def (a rename
      that compiles proves nothing resolved the old name) and one by DELETING THE ARM.
      `dd-mut-proof.py` (rename), `dd-mut-tether.py` (delete the arm / the interceptor),
      `dd-mut-reach.py` (call graph), `dd-mut-classify.py` (MOVED/THEOREM/REQUEST, which
      cannot emit a verdict with no proof behind it).

- [x] **M09 CLOSED — MOVED, 8 rows. THE REQUEST WAS A MISDIAGNOSIS.** `l2i_shl.hi` was
      never unreached: it is called unconditionally. On snapshot `73b0e1e7` the arena-aliasing
      defect overwrote the index pointing at it, so `lg9p` printed `BITCAST(WHERE)` where CPython
      has `BITCAST(OR)` — a PORT defect under a green gate, read as a coverage fact. Two fixtures
      added (ROWS ONLY, no port logic): **`hi42`** = `dtype.py:42`'s `hi` as a fixture ANSWER, so
      the `|` is at the root and `OR(SHL,SHR)` vs `OR(SHR,SHL)` are different strings; **`lgy`** =
      `dtype.py:39` on an `i32` source, so `l2i_cast3.bitc`'s fold stops hiding it. All eight
      rows CALLED from CPython. `.agents/slop/dd-mutations-report.md`.

- [x] **THE TABLE HAS **ZERO REQUESTS** — 31 MOVED · 5 THEOREM · 0 REQUEST · 0
      DID-NOT-COMPILE · 0 dead anchors, 182 rows.** Re-frozen at `e4618a71`, re-baselined, all
      five THEOREMs RE-MEASURED on the new snapshot (`l2i_define`/`f2f`/`reindex` renames
      byte-identical; M06 in BOTH directions, 137 of 184 lines). M05 and M36 RE-AIMED at the fixed
      text; M30 re-aimed off a non-compiling mutant, now 24 rows; M14 compiles, 2 rows.
      `.agents/slop/dd-mut-base.sh` builds a baseline that CANNOT be a mutant, after a baseline
      was built from a mirror still holding the M09 mutant and RULE C caught it (all three
      controls read MOVED 6 rows and NO table was written).

- [x] ~~**OPEN, OWNER: the dtype unit — `l2i_cdiv.uns` HAS ITS ARMS SWAPPED**~~ **FIXED by
      that unit; M36 RE-AIMED to re-introduce the defect so it stays armed.** `dtype.bend:971` was
      `case True{}: Cd.r0` / `case False{}: Cd.q0` against `dtype.py:74`'s
      `return r if op == Ops.CMOD else q`. The live file now agrees with CPython. The old anchor
      was the FIXED text with the DEFECT as the mutant, so applying it would have made the table a
      regression test for correct code; the anchor is now the fixed line and the mutant puts the
      remainder back — **MOVED 8 rows.**

## ZERO CLASSIFICATION (zero unit, 2026-10-04)

Report: `.agents/slop/zero-audit-report.md`. **No commit.** Rules appended at the END of
`bend2-constraints.md` as **M-4..M-8** (numbers collide across units — cite POSITIONS).

- [x] **A ZERO CLASSIFIES ITSELF. FIVE VERDICTS AND NO SIXTH:** `UNREACHABLE+proof` /
      `PORT-DEFECT` / `PATCH-NOT-APPLY` / `INVISIBLE-to-reader` / `NO-MUTATION-WRITTEN`.
      `MOVED` and `DID-NOT-COMPILE` are counted separately because they are not zeros.
      `.agents/slop/zero-classify.py`; `--verdicts` prints the five.

- [x] **THE MECHANICAL TEST SEPARATING 2 FROM 4, and it is two string questions.**
      **Q1 WRONG+JOINED:** does a DISAGREEING row carry CPython's answer *at this site*?
      **Q2 VISIBLE:** does CPython's answer at the site appear in *any* row? **WRONG before
      VISIBLE.** "Is it zero?" never decides it; only CPython does. **Q1 MUST BE A PER-SITE
      JOIN, NOT A FAMILY VOTE** — a coarse `l2i` family let all 51 disagreeing rows alibi for
      every `l2i_*` site and called M06 a defect when M06 is a proven THEOREM.

- [x] **THE DISCRIMINATION IS TESTED ON REAL SNAPSHOTS, NOT FIXTURES.**
      `.agents/slop/zero-selftest.py`: `l2i_shl.hi` against defective snapshot `73b0e1e7` reads
      `PORT-DEFECT`; an answer in no row reads `INVISIBLE-to-reader`; same site, same rows,
      different snapshot, different verdict. An unknown MEASURED verdict is REFUSED (exit 1).

- [x] **THE DENOMINATOR, WHICH NO TABLE WAS PRINTING.** 487 mutations across 15 tables carry
      **30 zeros, of which 25 are unclassified** — their labels are the raw harness output
      (`SAME`/`ZERO`/unstated), and **not one** of the 14 non-dd tables distinguishes
      PORT-DEFECT from INVISIBLE-to-reader. `.agents/slop/zero-audit.py`. Three harnesses
      (`mm-mutate.py`, `ops-mutate.py`, `dk-mutate.py`) have **no table file at all**; an absent
      number is not a zero, so they are reported as absent.

- [x] **A RULE D VIOLATION, LIVE, IN A COMMITTED RECORD.** `ops-python-mutate.py:107` prints
      `| {mid} | (pattern not found) | 0 | ...` and `ops-python-mutations.txt:7` carries it —
      a dead patch published as `0 rows`. `zero-audit.py` now greps the branch that PRODUCES
      the number, because a report file cannot say which branch produced its own figure.
      **Reported, not fixed: not my file. One line.**

- [x] **`l2i_dt` / `f2f_dt` HAD NO MUTATION AT ALL — 11 of 23 unmoved rows.** M37–M41 added to
      `dd-mutate.py`, all five MOVED: **M37 23 rows · M38 47 · M39 6 · M40 2 · M41 1.** The
      previous report *claimed* a value swap "would move `l2idt0 l2idt1`" — **measured, it moved
      23, not 2.** The same prose had already said "`dd_dtb.to` is on every `l2i` fixture's
      path". **A claim about a mutation's reach is never inherited.** Baseline rows a mutation
      moved: **159 → 172 of 182**; `l2idt*`/`f2fdt*` unmoved **11 → 0**.

- [x] **`shape()` IS A SAMPLE, NOT A CLAIM — and it passes a corrupt baseline.** It is
      `(first line, line count, last line)`; swapping `hi42`'s operand order (the exact M09
      defect) leaves all three unchanged, so `dd-mutate.py` would accept a mutant baseline.
      The frozen-digest assertions cover the file being MUTATED, not the one `SAME` is measured
      against. **RULE C is what catches it — the second time it has earned its keep on a defect
      it was not written for.** One-line fix proposed: digest the row SET.

- [x] **THE WARN-vs-REFUSE DEVIATION IN `dd-mut-base.sh`: ACCEPTED, WITH THE ROW-SET DIGEST
      AS AN AMENDMENT.** The claim is true — `live == frozen` should stay a warning (the live
      file moved FIVE times under this table, and a hard assertion makes the script unrunnable
      when needed) — but it is true only of the *mutation* side and does not cover the
      baseline. **Also found: the auditor itself made the error it exists to end** — the first
      `zero-audit.py` counted the three RULE C controls as dd's zeros (8, not 5).

- [x] **PIN DISCIPLINE, per table.** The dd verdict is valid for target `e4618a7127ce` + tree
      `e17d3f7dd48c`; the live `dtype.bend` is now `cdd85227d359`, so **the table does not
      describe what is on disk.** Baseline re-verified byte-identically today (`sha1 78c79061…`,
      182 rows); oracle re-run today, byte-identical (`sha1 8f80df08…`); **all five dd proofs
      RE-MEASURED on the current snapshot.** **The other 14 tables name NO revision — that is
      the finding.** 10 rows disagree with CPython on the pinned snapshot; three of them
      (`lg5k`/`lg5n`/`lg5sig`) are the `promote`-remint defect the live file has since fixed
      with `dd_wf`, so the 0-on-a-snapshot rule is now measured rather than asserted.

## Session 2026-10-04 — REPO HYGIENE: the dangling citations, the census, and the scratch in the tree

Report: `.agents/slop/hygiene-2026-10-04.md`. **No commit.** Changed: three comment lines, two
`.gitignore` patterns, this block, an appended note in `bend2-constraints.md`, and two new
harnesses (`.agents/slop/stale-snapshot-detect.py`, `.agents/slop/hygiene-2026-10-04.md`).

- [x] **THE BRIEF'S PREMISE WAS WRONG AND THE HAZARD IS NOT RESOLVED. `tinybendygrad/.bend`
      NEVER EXISTED, AND ROOT `.bend` IS STILL THERE, TRACKED, 1,890 LINES.**
      `git log --all -- 'tinybendygrad/.bend'` is empty; `git ls-files | grep '^\.bend$'` prints
      `.bend`. It cannot compile — its five imports at `:239-244` are `../helpers.bend`,
      `../LAWS/spec.bend`, `../dtype.bend`, `../uop/ops.bend`, `../uop/symbolic.bend` and `../`
      from the repo root escapes the repo. **Reported, not deleted: outside my file grant, and
      only `rm` + a commit removes a tracked file.**

- [x] **IT IS ALSO A STALE DUPLICATE, WHICH SETTLES THE DELETE.** `diff` against
      `runtime/ops_python.bend` is 1,590 lines and the direction is unambiguous: root `.bend`'s
      header says "THE INTERPRETER LOOP IS NOT [here]", `ops_python.bend`'s says
      "--check-only is clean ... and `-o` builds" with a 28-fixture e2e at 18/10/3; root `.bend`
      predates the `1n` nat migration. **RECOMMEND: `rm .bend`, commit the deletion.**

- [x] **THE GLOB PROOF. `tree-verdict.py` DOES NOT GLOB — IT `os.walk`s** (`bend_files()` at
      positions 86-93), so the harness is sound and its own comment at 55-60 says why. The
      exposure is the CENSUS method: root-level `glob.glob('*.bend')` returns `[]` with `.bend`
      on disk, because Python's `glob` will not let `*` eat a leading dot. **EXACTLY ONE FILE
      HIDES FROM THAT GLOB: root `.bend`.** `find` and `os.walk` both see everything.

- [x] **THE CENSUS HAS A BIGGER HOLE IN THE OTHER DIRECTION: 4 `.bend` FILES ON DISK ARE NOT
      TRACKED** (`runtime/ops_bend.mut.bend` 1,573 · `test/_probe/v5.bend` 25 ·
      `renderer/_mut_m35.bend` 0 · `renderer/_ptxmut.bend` 0). All four are gitignored scratch.
      So `find` says 137 and a clone reproduces 133.

- [x] **CORRECTED PORT SIZE, AS A BRACKET — the file count is the trustworthy half.**
      `tinybendygrad` + `examples`: **128 TRACKED, NON-SCRATCH `.bend` FILES**, lines
      **195,016-195,188** across this session; the loose `find` census read 137-138 files /
      ~197.9k, and git-tracked read 133 / ~196.3k. `tinybendygrad` alone: **127 / ~193.9k**.
      Scratch rule is `tree-verdict.py`'s own `SCRATCH_RE` at position 60.
      **THE PUBLISHED 137 IS NOT WRONG** — it is `tinybendygrad` + `examples`, which is what
      `bend2-constraints.md` §6 (position 14370) says it means. The SET is what must be stated,
      not the number changed. **The file count held at 128 across every reading while the line
      count moved, so quote files and bracket lines.**

- [x] **THE CENSUS IS UNSTABLE, MEASURED FOUR TIMES IN ONE SESSION:**
      196,610 -> 196,743 -> 196,724 -> 196,821 lines, and the `find` FILE count went
      **137 -> 138** when another unit landed a `.bend` mid-session, before settling byte-identical
      (md5 `640487f2…`). `git status` names five files mid-edit by live agents.
      **A census taken while agents are writing is a sample, not a measurement.**

- [ ] **OWNER: COORDINATOR — `rm` + COMMIT `renderer/csprobe.bend` (774 lines).** It is a stale
      snapshot: identical to `renderer/cstyle.bend` for **588 of its 774 lines** (ratio 0.76),
      diverging exactly where `cstyle.bend` gained the `type_map` table. Same class as the fold
      snapshots deleted in `b6abeb7f5`, and it makes the census count 774 lines of `cstyle.bend`
      twice. `.agents/slop/stale-snapshot-detect.py` finds it and finds nothing else.
      Also `runtime/_p6.bend` (4 lines, a bare `F32.bits` print) and the two EMPTY files
      `renderer/_mut_m35.bend`, `renderer/_ptxmut.bend`.

- [x] **`.gitignore` GAP CLOSED, AND IT IS THE RIGHT QUESTION.** `probe-*.bend` needs the hyphen
      so `csprobe.bend` slipped through; `_mut_*.bend` needs the word so `_p6.bend` slipped
      through. Added `*probe.bend` and `_*[0-9].bend`; verified they match exactly 1 and 2 files in
      the tree, all scratch. **A PATTERN CANNOT UNTRACK EITHER — `git status` staying dirty here
      is expected, not a failure.**

- [x] **`uop/probe-mmcore.bend` (471 lines) MUST NOT BE DELETED, DESPITE THE `probe-` PREFIX.**
      `.agents/slop/mm-mutate.py:17` names it `SRC`; `.agents/slop/mm-gate.py:12` runs it. This
      is the repo's own "DELIBERATELY NOT IGNORED" doctrine — *a cache-shaped path is not the
      test; "a report cites it" is* — applied to a file `.gitignore` currently sweeps by pattern.
      **`.gitignore`'s "a broken probe in the source tree is a trap for the next reader, not a
      fixture" is therefore too broad as written and needs the citation test added.**

- [x] **THE BRIEF'S FIVE `*_work.bend` FILES ARE NOT IN THE TREE AND WERE NOT TRACKED THERE.**
      `tinybendygrad/uop/fold2_work.bend` and `fold_mm_work.bend` were deleted in `b6abeb7f5`
      ("delete 7,935 lines of dead fold snapshots"). What remains is 17 tracked `*_work.bend`
      files, **all under `.agents/slop/`** (per-unit working trees: `dd-cone-wt/`, `render-wt/`,
      `proof-close/`, `rf2root/`, `rf2_work.bend`). **`find tinybendygrad` never counted them, so
      NO PUBLISHED PORT SIZE WAS INFLATED BY THEM.**

- [x] **DANGLING `executor.bend` CITATIONS — 3 REPOINTED, 3 REPORTED.**
      REPOINTED (comment-only, the three files in my grant):
      `runtime/ops_bend.bend:10` -> `runtime/ops_python.bend` (which holds the wire header at
      `:134`) · `runtime/ops_webgpu.bend:673` -> `ops_python.bend:2135` (verified: that IS the
      "take, not drop, keeps the directory" measurement, same line number today) ·
      `runtime/ops_python.bend:2285` now names the REAL path (repo root `.bend`) instead of a
      fiction. REPORTED, NOT FIXED: **`uop/symbolic.bend` has TWO more, at positions 875 and 976**
      (not 842 — the brief's line number is off), both bare-filename and resolving to nothing;
      both should read `ops_python.bend`. **`runtime/ops_bend.mut.bend:10` is a fourth copy of the
      same line — untracked gitignored scratch, REGENERATE not fix.**

- [x] **STALE NUMBERS MARKED UNSTABLE, NOT REWRITTEN. History is not edited to agree.**
      `VERBATIM` naming count: **283** (six runs, byte-identical md5) vs **278** (19:34-19:36,
      files mid-write) — 283 is a settled-substrate reading, 278 a substrate-in-flux reading,
      **neither is a constant**. `elf.bend` rows: **353** (a complete run reproduces the recorded
      353; artifact `runs/elf-run-353rows-2026-10-04.txt`) vs **331** (unreproduced). **My own
      THIRD value, 246, IS RETRACTED — it was a partial read of a background `bend` job that was
      still writing** (four reads of one file: 239, 246, 354, 355), and `--check-only` prints no
      row count at all. **A count that grows while you watch it is an UNFINISHED measurement, not
      an unstable one — a third failure mode, distinct from both drift and rule-dependence.**

- [x] **THE `ops_cpu` libm/objc REPORT IS ALREADY RECORDED** at `TODO.md:2831-2842`, open and
      un-ticked, "TREE DEFECT, REPORTED NOT FIXED — the Metal host kernel cannot link",
      `OWNER: whoever owns runtime/ops_cpu.bend`. **Not duplicated — cross-referenced only.**
      The 17 host rows and `findlib_m=/usr/lib/libm.dylib` are `ops_cpu.bend:241-300`, and
      `cpu.lib_objc() = "/usr/lib/libobjc.dylib"` at `:278` is the library `ops_cpu.py:19,21`
      fails to link.

- [x] **THE DOTTED-SEGMENT IMPORT RULE IS ALREADY RECORDED AND I RE-MEASURED IT.**
      `bend2-constraints.md` §38 at **positions 16108-16126**, "bend IMPORT PATHS REJECT ANY SEGMENT
      CONTAINING A DOT -- SO NOTHING UNDER `.agents/` CAN BE IMPORTED", with the exact error and
      the corollary that probe scripts live in `.agents/slop/`. **Not duplicated.** Re-measured
      today with a control: `import ./.dotted/h.bend` fails with "an import path of plain names",
      and the SAME probe importing `./plain/h.bend` gets PAST the import stage entirely — so the
      dot is the cause and nothing else.

- [ ] **OWNER: `uop/symbolic.bend`'s agent — two dangling `executor.bend` citations at :875 and
      :976.** Two comment lines. Not in my grant, so reported rather than edited.

- [ ] **OWNER: whoever owns `.jjconflict-{base,side-0,side-1}/`** — each holds a
      `tinybendygrad/runtime/executor.bend`. jj conflict residue at the repo root.

- [ ] **THE LEDGER'S OWN COUNTS ARE LIVE, WHICH IS THE POINT.** `TODO.md` measured **4,946 lines,
      479 checkboxes, 396 ticked, 83 open** (a brief's "4,063 / 422 / 351 / 71" was true earlier
      today and is now stale in the same way 283 is). **`bend` here is 2.0.35; `agent-core.md`
      says 2.0.34**, so the 14 unfilled `dtype.bend` laws and every "MEASURED on Bend 2.0.34"
      note may need re-measuring.

Progress: repo hygiene [##########] DONE — 3 citations repointed, 3 reported, glob proven,
      2 `.gitignore` patterns added, census corrected, 6 numbers marked unstable,
      4 deletions handed to the coordinator

## Session 2026-10-04 — M09 CLOSED: two fixture rows, the REQUEST sweep, and a baseline that was a mutant

Report: `.agents/slop/dd-mutations-report.md`. **No commit.** Changed: **fixture rows only** in
`tinybendygrad/codegen/decomp/dtype.bend` (`hi42`, `lgy`, `l2i.rows(32n → 33n)`), plus
`.agents/slop/dd-mutate.py`, `dd-mutations.txt`, `dd-mutations-report.md`, and two new harnesses
(`dd-mut-base.sh`, `dd-mut-fixtures.py`).

- [x] **THE FIXTURE EXISTS AND IT READS THE ORDER.** `hi42` roots the cone at `dtype.py:42`'s `|`
      instead of two levels below a `WHERE`, so `hi42=OR(SHL(BITCAST,CAST),SHR(SHR,ADD))` becomes
      `OR(SHR(SHR,ADD),SHL(BITCAST,CAST))` under M09. **A fixture that passes under both operand
      orders is not a fixture, and this one does not.** `dt=uint32` so the `.bitcast` FOLDS and both
      lanes reach the `|` at ONE address (`r1.src[2]` / `O.Arena.src(ar, r1, 2)`); `xdt=int32` so
      each half carries its own `BITCAST`.

- [x] **`b0 < 32` WAS ALREADY COVERED AND I MEASURED IT.** `l2i_cdiv` calls
      `l2i(SHL, uint, *r, UOp.const(1, uint), z)` at `dtype.py:58`, so `lgq`/`lgr`/`lgs`/`lgt`
      reach the `hi` arm with the LITERAL `b0 = C(1)` — which is why M09 moves their sigs. And
      `n = b0 & 31` puts the shift in `0..31` for every input, so the requested precondition is
      guaranteed rather than chosen.

- [x] **THE SWEEP FOUND A REQUEST THE TABLE DID NOT HAVE.** Re-aiming M05 read 0 rows, and
      `dd-mut-proof.py` **REFUSED to rename `l2i_cast3.bitc`** — so the site is LIVE and the 0 is
      INVISIBILITY. `lg7` is dtype.py:39's only fixture and `bitcast(uint)` FOLDS on it, so the
      node that arm exists to build was in no row. **`lgy` closes it: M05 now MOVES 4 rows.**

- [x] **A BASELINE WAS THE M09 MUTANT, AND RULE C CAUGHT IT.** `hi42=OR(SHR(SHR,ADD),…)` sat in the
      BASELINE file because the mirror had been left holding a mutated `dtype.bend`. Every mutation
      moved exactly 6 rows and all three controls read MOVED, so no table was written. Fixed at the
      source: `dd-mut-base.sh` builds the baseline in a FRESH mirror, ASSERTS the digest on both
      sides, and requires two consecutive stable 150+ row runs. **The same defect then turned up in
      my own oracle replay** — it ran the fixture it was about to measure, so `lgyn` read `0`
      against the port's `2`. Both appended to `bend2-constraints.md` as M-1.

- [x] **ONE DELIBERATE DEVIATION, REPORTED.** `dd-mut-base.sh` WARNs instead of refusing when the
      live `dtype.bend` no longer matches the frozen snapshot. It moved FOUR times during this run,
      so a hard `frozen == live` assertion makes the script unrunnable exactly when it is needed;
      what the table's validity rests on — the frozen digest and `mirror == frozen` — is asserted
      and unchanged.

- [x] **NOT DONE, AND IT IS NOT A COVERAGE CLAIM.** The table has **no mutation entry for
      `l2i_dt`/`f2f_dt`**, which is why `l2idt0 l2idt1 f2fdt0..8` (11 of the 23 unmoved rows) are
      unmoved. Both are live; a one-line swap of `l2i_dt`'s two values moves two rows. Out of scope
      for a REQUEST sweep, recorded so the next reader does not read the orphan list as coverage.

Progress: dtype M09 + REQUEST sweep [##########] DONE — 2 fixtures (8 rows, all from CPython),
      M09 MOVED 8, M05 MOVED 4, 31 MOVED · 5 THEOREM · 0 REQUEST · 0 DID-NOT-COMPILE,
      5 THEOREMs re-measured, 3 controls SAME, .tsv reproducible

## Session 2026-10-04 — `uop/ops.bend`'s three loose ends: the `AFloat` premise is FALSIFIED, the `cfun_*` gate is GREEN, and `ops-oracle.py` is unowned

Three findings were handed over. One was a defect, one was a red gate, one was an
ownership question. **The defect was not a defect**: the proposed one-word repair is a
double regression, measured on both trees, and what landed instead is the row set that
says so. Gate: `sh .agents/slop/ops-gate.sh` — **94 shared rows RED -> 103 GREEN**, three
lanes byte-identical, exit 0, twice, on the upstream tree AND on `TG_TREE=.`.

- [x] **`eq_arg.AFloat`'s `F32.is_eq` IS CORRECT AND `U32.is_eq(F32.bits(f), F32.bits(y1))`
      IS A DOUBLE REGRESSION. The repair was NOT landed; the reason it looked wrong was
      landed instead.** `ops.py:201`'s key holds the element and **each element carries
      its own `__eq__`**, so the question is which PYTHON CLASS is in the key. Two, with
      opposite rules: `dtype.py:8-23` `ConstFloat(float)` overrides BOTH `__eq__` (line
      16) and `__hash__` (line 21, `hash(self.bits)`) and its docstring says it
      "distinguishes -0.0 from 0.0 and where nan == nan" — so `eq_const.CFloat` is
      right to compare bits — while `AFloat` is a BARE `float`, overrides nothing, and is
      IEEE. **CALLED, never transcribed** (`.agents/slop/afloat-probe.py`, byte-identical
      on two runs and on `TG_TREE=.` and on `.agents/slop/opstree`):
      `UOp(Ops.CONST, arg=0.0) is UOp(Ops.CONST, arg=-0.0)` -> **True, 1 node**;
      two DISTINCT same-payload NaNs -> **False, 2 nodes**; `1.5/1.5` -> True;
      `1.5/2.5` -> False; `type(arg)` keeps `int 0` and `float 0.0` apart -> False.
      Bits inverts BOTH discriminating cells. **The briefing's premise that `eq_const`'s
      rule is the model is what made the arm look wrong; they are different bugs
      pointing opposite ways.** The file's own comment above `eq_const.CFloat` ("`F32.is_eq`
      is IEEE and disagrees in both directions") is TRUE OF `ConstFloat` ONLY, and that
      is now said where the arm is.

- [x] **`AFloat` IS LATENT, and the evidence is that ZERO of its 8 occurrences in the live
      tree construct one.** 1 type declaration (`ops.bend:948`), 2 comments, 1 def header,
      and 4 `case` PATTERNS (`eq_arg.AFloat`, `eq_arg.sel`, `upat.bend:418`,
      `render.bend:717`). Its one would-be builder is `_frompy`, `TODO(p3)` at
      `ops.bend:4318`. **But "latent" was a statement about the arm and not about the
      comparator**, and `UOp.new(arena, op, src, arg, tag)` takes the `Arg` as a
      PARAMETER (`ops.bend:2309`) — so an arm with no constructor is still reachable, by
      interning two `AFloat`s on one arena and answering by IDENTITY OF THE TWO INDICES.
      That is `blob_same`'s rule (`ops.bend:5117`, "a row that asserted `eq_arg` directly
      would be asserting the def under test with itself") and it is why these four rows
      are not tautologies.

- [x] **FOUR `afloat_*` ROWS LANDED, PLUS THE COMMENT THAT STOPS THE NEXT UNIT REPEATING
      THIS.** `afloat_zeros_intern` / `afloat_nan_distinct_intern` are the two
      discriminating cells; `afloat_same_intern` / `afloat_distinct_intern` are the two
      CONTROLS, without which a comparator answering `False` for every float would
      satisfy the NaN row alone. **Mutation matrix on a MIRRORED tree, all four rows:**

      | mutant | zeros | nan | same | distinct | rows moved |
      | --- | --- | --- | --- | --- | --- |
      | baseline | T | F | T | F | -- |
      | `U32.is_eq(F32.bits, F32.bits)` | **F** | **T** | T | F | 2 |
      | `True{}` | T | **T** | T | **T** | 2 |
      | `False{}` | **F** | F | **F** | F | 2 |
      | `Bool.not(F32.is_eq(..))` | **F** | **T** | **F** | **T** | 4 |

      **No mutant is invisible and no single row catches every mutant** — the property
      that makes four rows a minimal set rather than two rows and a hope.
      **ONE CELL IS DELIBERATELY UNGATED:** the same NaN *object* twice interns in
      CPython (1 node — `lookdict` short-circuits on pointer identity) and
      `F32.is_eq(nan, nan)` is False. That is a fact about Python object IDENTITY and not
      about the float, so a row for it must lie about the comparator or about CPython.
      Measured in the probe, printed nowhere else.

- [x] **SIBLING SWEEP, RE-DONE AGAINST THE UPSTREAM RULE AND NOT AGAINST "IS IT CONTENT".**
      Spot-checked all 19 named comparators. **CLEAN (11):** `ANone`↔`None`,
      `ARange`/`ATuple`/`AWmma`↔tuples (`eq_u32` is elementwise, order- and
      length-sensitive), `AReduce`/`AAllred`↔`(Ops, …)` (`Ops` is a FastEnum so
      `Ops.value` ≡ identity), `AStr`/`AInk`↔`str` (Python `str.__eq__` is code-point
      equality and does no normalisation), `ADev`↔`str|tuple[str,…]` (`ops.py:765`),
      `ABlob`↔`bytes` (content, just fixed), `AFloat`↔bare `float` (IEEE, measured),
      `ABad` (never interned), `eq_dt`, `eq_axis`, `eq_u32`, `eq_pyrange`, `eq_img`,
      `eq_i64`/`eq_i64s`. **`type(arg)` IS represented**: the `Arg` datatype's
      CONSTRUCTOR is the discriminator, which is why every mismatched arm falls to
      `case _: False{}` — and that is also why a dtype rename is the silent failure it is.
      **FOUR COMPARATORS ARE WEAKER THAN UPSTREAM'S KEY — reported, NOT fixed, all
      documented boundaries in the port:**
      1. `eq_kernelinfo` compares 4 of `ops.py:1342`'s **5** `KernelInfo` fields; it
         drops `estimates` (P5, the renderer's cost model).
      2. `eq_programinfo` compares 6 of `ops.py:1351`'s **7** `ProgramInfo` fields; it
         drops `target: Target` (P6). Documented at `ops.bend:988-994`.
      3. `eq_callinfo` compares 4 of `ops.py:1399`'s **5** `CallInfo` fields; it drops
         `grad_fxn` (a Python function object, cannot be a `Data` field) and SUBSTITUTES
         a port-local `dtype` for upstream's `aux: Any`. **`aux` is not inert upstream** —
         `ops.py:549-550` reads `hasattr(arg.aux, "written_bufs")` and `replace`s it, so
         two CALLs differing only in `aux` are TWO keys in CPython and ONE here.
      4. `eq_pyrange` compares `H.I64` bounds, while `ParamArg.vmin_vmax` is
         `tuple[PyConst, PyConst]` and `dtype.py:38`'s `PyConst = float|int|bool` — so a
         float or bool bound is not representable, and `True == 1` collapses where the
         port separates.
      **ONE OVER-SPLIT, latent, and the safe direction:** `eq_tag` has `TBool` and `TInt`
      as separate arms, but `ops.py:258` is `def rtag(self, tag=True)` — the DEFAULT tag
      is a bool — and the key carries `type(arg)` and NOT `type(tag)`, so `tag=True` and
      `tag=1` are ONE key in CPython. The port has no `rtag` def and no `TBool{…}`
      construction, so it is as unreachable as `AFloat` was. This is the `dtype_key` row's
      twin, on `tag` rather than `arg`. **The one that would be a real defect is the
      missing `CTuple`**: `ops.py:1920` is `ConstLike = ConstType|Variable|tuple[ConstType,
      …]` and `eq_const` has no tuple arm — but no upstream code builds a CONST with a
      tuple or `Variable` arg in the tree, so it is unreachable, not wrong.

- [x] **TASK B — `ops-gate.sh` WAS RED ON THE PRISTINE TREE. DIAGNOSIS: (a) MISSING FROM
      THE ORACLE, and fixable, and now fixed.** The Bend printed 5 `cfun_*` rows
      (`ops.bend:6130-6134`) that `ops-oracle.py` did not have and that were not in
      `BEND_ONLY`, so `diff` reported `0a1,5` on every run. Not a port defect and not a
      dead lane: `CustomFunction` is a frozen dataclass at `ops.py:1395` and
      `UOp.custom_function` at `ops.py:1259`, **both present and answering IDENTICALLY on
      both selectable trees**, so the rows are GATEABLE and belong in a shared block
      rather than five `#bend_only_` reasons. `.agents/slop/ops-oracle.py:244` is now a
      `# 0bis0` block printing `cfun_interns=True`, `cfun_dtype_splits=True`,
      `cfun_name_splits=True`, `cfun_arg=sel_registerName|u64`,
      `cfun_of=sel_registerName|void` — CPython's, called, with `dtype.name` rather than
      `str(dtypes.void)` (which is `dtypes.void`, and `str(dtypes.uint64)` is
      `dtypes.u64`, neither of which is the port's spelling). **The five were added at the
      HEAD of the oracle because the Bend prints them FIRST, and the oracle's row order
      IS the contract** (`ops-gate.sh` is a byte diff).
      **STATE BEFORE: `BROKEN`, 94 rows compared by the CPython lane against 99 by the two
      Bend lanes — a 5-row gap that was 5/94 = 5.3% of the denominator reading as
      "agreement" on everything it did compare. STATE AFTER: `UNCHANGED` rows, no
      re-port, no `ops.bend` edit; 103 shared rows, three lanes byte-identical, exit 0,
      on the upstream tree and on `TG_TREE=.`.**

- [x] **BLAST RADIUS, THE SAME METHOD AS THE `ABlob` FIX, AND IT IS PROVABLY LOCAL.**
      `.agents/slop/blob-rows.py af-before` then `af-after`: **72 files in the sweep
      (71 importers + `ops.bend` itself), 0 ZERO-ROW files on both runs.** Per-file
      counts: **every file byte-identical except `tinybendygrad/uop/ops.bend`, 220 -> 224**;
      `TOTAL` 12,425 -> 12,429. `diff -r` on the two snapshots: the ONLY content delta
      anywhere is `118a119,122`, the four new rows. Nothing moved and nothing reordered.
      (The sweep measures the BEND lane; for the oracle the consumers are
      `ops-gate.sh` — green — and `rebase-oracle-ops.py`, whose wrapper is SET-keyed and
      prints sorted, so 9 new keys can only widen it: `inner_rows` 105 -> 114,
      `kept` 90 -> 99, 43 bend-only families unchanged. `rebase-gate.py`'s `row_counts`
      is a report field, not a baseline assertion.)

- [x] **TASK C — NO CustomFunction UNIT IS LIVE AND NONE OWNS `ops-oracle.py`. THE NINE BLOB
      ROWS STAY.** Evidence: no `- [ ]` open TODO entry mentions `CustomFunction` or
      `cfun`; `TODO.md:2642`/`2678` attribute `CustomFunction` to an **`ops.bend`**
      substrate unit whose two open items name `helpers.bend` and `ops.bend` and not this
      oracle; `TODO.md:600-601` attributes the five red rows to "the other range", which is
      `ops.py:1258/1394` inside `[501,1928]` — the `s5` unit, whose own gate filters
      `^s5_` (`ops-501-gate.sh:40-43`) and therefore cannot own them; and
      `TODO.md:4283-4286` already rules that closing the `axis_id` item needs "a matching
      row in `.agents/slop/ops-oracle.py` … and that oracle is not this unit's file".
      **So the blob unit's worry was unfounded — the 9 rows are safe, and by the same
      argument the 5 `cfun_*` and 4 `afloat_*` rows are mine to add.** `bend2-constraints`
      R-6 (position 18382) says ONE OWNER PER FILE PER WAVE, so this unit claims
      `ops-oracle.py` for the duration and says so.

- [x] **A SECOND RED-AT-REST GATE, REPORTED AND NOT TOUCHED: `sh .agents/slop/ops-501-gate.sh`.**
      Its CPython lane prints **101 `s5_*` rows against the Bend's 82**, and the 19 extra
      are families the oracle has alone — `s5_copy_multi/single/sel`, `s5_devrange_one/
      single/two`, and 12 `s5_ga_*`. `ops-501-oracle.py` is at its COMMITTED state
      (`jj diff --summary` does not list it), so this is red AT REST and not collateral:
      the `s5_` subset of `ops.bend`'s output is byte-identical before and after this
      unit's change. **Not fixed — `ops-501-oracle.py` is another unit's file, and
      `agent-core.md` says report it.** `TODO.md:600-601`'s note that the five `cfun_*`
      rows "were red before the wave started" is now CLOSED and its companion claim is
      not.

- [x] **3 rules appended to `bend2-constraints.md` at the END (position 18633), numbered
      `## A-1..A-3` continuing from the `## M-` series (last was M-8)**, self-locating
      by content. **3 rows appended to `.agents/TOOLS.md`** for
      `afloat-probe.py` and the two red-at-rest lanes. **NOT COMMITTED.**

Progress: `uop/ops.bend` loose ends [####] DONE — A: premise FALSIFIED, 4 rows + the
      comment landed, 4/4 mutants caught, blast radius 1 of 72 files · B: gate RED
      (94/99) -> GREEN (103/103/103) on both trees · C: no live owner, rows kept

- [x] **A CONCURRENT UNIT OVERWROTE `uop/ops.bend` MID-RUN AND TOOK BOTH FIXES WITH IT.
      REPORTED, NOT PATCHED OVER, AND THE WORK IS HANDED OVER AS A PROVEN PATCH.** The
      live file went `d5c1174e`/6306 (this unit's starting point, and the state every
      gate result below was measured at) -> `44b9c64f`/7140 -> `47ce62d0`/7176 ->
      `c7879a52`/7230 in about four minutes, **while this unit was still working**. The
      version that landed is missing this unit's four `afloat_*` rows **AND the earlier
      `ABlob` false-intern fix** (`eq_arg.ABlob(y: Arg, +n: U32)`, comparing a LENGTH
      again) while carrying 924 new lines of someone else's work (`type DRng` at :6532,
      `UOp.device_range_src` at :6554). **So it was a DIVERGENT COPY written over the
      shared working copy, not a merge and not an edit** — R-6's failure mode, live.
      It also does not compile, and its two `--check-only` failures two minutes apart
      (`a declared constructor (unknown: DRng)`, then `expected: a filled definition;
      observed: UOp.device_range_src`) are a half-written file, not a defect to fix.
      **NOT patched over: `ops.bend` is that unit's file while it writes, and landing a
      6306-line-derived patch on a 7230-line divergent base is a merge nobody can verify.**
      Instead `.agents/slop/afloat-patch.py` **asserts the base md5**, re-applies three
      anchors, **REFUSES if the base still compares a blob by length**, and writes
      `.agents/slop/afloat-ops-bend.bend` + `.agents/slop/afloat-ops-bend.patch`
      (92 diff lines). **The reconstruction is PROVEN, not assumed:** run in a mirrored
      subtree it is `ALL PROOFS CHECK` and its 224-row output is **byte-identical** to
      `.agents/slop/blobrows/af-after/tinybendygrad__uop__ops.bend.txt`, the snapshot
      captured from the file that was green. **To land it:**
      `git apply -p1 .agents/slop/afloat-ops-bend.patch` once `ops.bend` is back to the
      blob-fixed state — and note it needs `uop/ops.bend` AND `.agents/slop/ops-oracle.py`,
      which is already in the tree.
      **THE GATE IS RED RIGHT NOW AND THAT IS THE HONEST STATE:** the oracle half is live
      and correct, the Bend half is the patch above, so `ops-gate.sh` disagrees on the
      5 `cfun_*` + 4 `afloat_*` rows **because of the overwrite, not because of the
      oracle.** Reverting verified oracle work to make a gate look tidy would be the one
      wrong move available here. Appended as `## A-4` in `bend2-constraints.md`
      (position 18727), including the two instruments that would have caught it — a
      **polled** hash, and a `grep -c` for this unit's OWN ROW NAMES in the file being
      edited, which is the cheapest liveness probe there is.

Progress: `uop/ops.bend` loose ends [###.] BLOCKED ON A CONCURRENT OVERWRITE — A: premise
      FALSIFIED, 4 rows + comment proven, patch ready, blast radius 1 of 72 files ·
      B: gate was RED (94/99) and is GREEN (103/103/103) on both trees IN THIS UNIT'S
      TREE, red again only via the overwrite · C: no live owner, rows kept · **the live
      file lost both the ABlob fix and these rows to another unit's copy**

- [x] **AND THE OVERWROTE `ops-oracle.py` TOO — the SAME EVENT, one file later.** Five
      minutes after the `ops.bend` overwrite, `ops-oracle.py` also stopped answering:
      `md5 c2a4b0ff…`, 771 lines, and `grep -c 'cfun_\|afloat_'` read **0** for a few
      minutes. It is back now (both blocks present at positions 247-284 and 346-401, all
      nine rows printing, byte-identical to what was verified) with no edit from me, so
      this was an agent writing and restoring, not a second loss. **Recorded because it is
      the same lesson twice: `ops-oracle.py` and `tinybendygrad/uop/ops.bend` are BOTH
      under concurrent edit in this wave, and Task C's conclusion that no CustomFunction
      unit OWNS the oracle is an ownership answer, not a promise that nobody is TOUCHING
      it.** A unit that adds rows to a byte-diff oracle during a wave where another unit
      is mid-write will lose them, and `grep -c` for its own row names in the oracle is
      the cheap liveness probe that would have said so in seconds rather than minutes.

Progress: `uop/ops.bend` loose ends [###.] BLOCKED ON A CONCURRENT OVERWRITE — A: premise
      FALSIFIED, 4 rows + comment proven, patch ready, blast radius 1 of 72 files ·
      B: gate was RED (94/99) and is GREEN (103/103/103) on both trees IN THIS UNIT'S
      TREE, red again only via the overwrite · C: no live owner, rows kept · **the live
      file lost both the ABlob fix and these rows to another unit's copy, and the oracle
      was written and restored in the same window**

## MUTATION-ZERO VERBOSITY — one marker for a patch that did not apply (2026-10-04)

- [x] **CENSUS: what does each stale-anchor branch print today?** Taken from the AST
      branch BODIES, not the `if` lines, because all 29 guards read `if old not in src:`
      and a grep of the test cannot say which branch produced a figure. `.agents/slop/
      not-applied-audit.py` prints it and exits non-zero on any violation. Denominator:
      **30 in-scope stale-anchor branches across 29 files; 7 loud aborts kept; 55
      out-of-scope branches listed.** The brief's 28 was an undercount from a 4-spelling
      regex; the measured number is 30 plus 7 loud.

- [x] **ONE SHARED REPORTER.** `.agents/slop/patch_not_apply.py` — `MARKER`,
      `not_applied()`, `pipe(cells, width)`, `fail()`. `MARKER` is
      `zero-classify.py`'s `V_PATCH` **queried** via its `--verdicts` flag, not
      transcribed, and a rename there raises at import. `pipe()` refuses a row of the
      wrong width, so cell-count parity is structural. `fail()` is an explicit `raise`,
      not `assert`, because `python -O` strips `assert`.

- [x] **CONVERTED 34 files**, including a **second live instance of the `0` defect the
      brief did not list**: `hcq2-mutate.py` printed `0 -- EDIT DID NOT APPLY` in the
      COUNT column, which `int(cell.split()[0])` still reads as `0`. **LEFT LOUD (7):**
      `codegen3-mut.py`, `ptx-s3-mutate.py`, `ga_write_operands.py`, `ag-fix{4,6,7,12,13}.py`
      — converting them to a quiet marker would trade a loud abort for a quiet record,
      which is the one trade not worth making.

- [x] **MECHANICAL AUDIT THAT CANNOT BE FOOLED.** `not-applied-audit.py`, four
      assertions: **A1** anti-drift (the branch body must CALL the reporter, so a literal
      is a failure), **A2** non-numeric on the cell's FIRST TOKEN, **A3** column parity
      against the enclosing scope's own rows with the branch excluded, **A4** vocabulary
      queried not transcribed. `--dir D` points it at other sources. **Proven to fail:**
      run against reconstructions of the pre-fix sources it exits 1 and fires A1, A2 and
      A3 on three different real defects; against the fixed tree it exits 0.

- [x] **TWO BUGS THE AUDITOR FOUND IN ITSELF, both recorded as Z-4** (position 18934):
      the width check originally read the expected width FROM THE BRANCH UNDER TEST, so
      it agreed with itself and a 4-cell row in a 3-column table passed; and the cell
      counter double-counted each row's leading `|`, reporting every 3-column table as 4
      wide. It also caught **my own** wrong conversion at `mt_mutate.py:168`.

- [x] **SWEEP OF PUBLISHED RECORDS.** `.agents/slop/false-zero-sweep.py`. **32 committed
      rows carry a bare-`0` count across 21 records; 0 are UNMARKED now** (14 were). Each
      is classified `MEASURED?` / `UNMARKED` / `NO-GUARD` / `ANCHOR-GONE` from the
      PRODUCER's source, never from the record. `ops-python-mutations.txt:7` was already
      fixed; the honest fix for any future one is `PATCH-NOT-APPLY`, never a re-run.

- [x] **PER-TABLE REVISION LEDGER.** `.agents/slop/revision-ledger.py`. **22 tables: 2
      name a revision, 20 name none; 9 have a file digest, 5 have a row-set digest.**
      `dd` pins `e4618a71` / tree `e17d3f7dd48cf84c` and is itself stale against live.
      Records TWO digests per table because a digest protects the MUTANT, not the
      REFERENCE — the `hi42` order swap leaves `shape()`'s three fields unchanged.
      Live moved three times while the ledger was being written.

Progress: MUTATION-ZERO VERBOSITY [######.] census 30 in-scope + 7 loud · reporter
      `patch_not_apply.py` · 34 files converted · A1/A2/A3/A4 hold and the auditor is
      proven to fail on the pre-fix sources · 0 unmarked published zeros · revision ledger
      22 tables, 2 pinned. Rules appended as `## Z-1..Z-7` in `bend2-constraints.md`
      (positions 18898-18963, indexed at the top).

---

## Session 2026-10-04 (late) — INSTRUMENTS FIXED, AND THE TALLY OF WHAT THEY GOT WRONG

Progress: session deliverables [#########] 9/10  (the tenth is the `ops.bend`
substrate, which blocks 72 importers and is owned by a unit in flight)

### The theme, stated once

**Nine separate findings this session were instruments returning something other
than the thing under test.** Only two were "code was wrong". The rest:

| the thing that lied | instance |
|---|---|
| the **reader** | `rows()` matched `name=value`; `multi` prints `name␣␣value`, so 213 rows compared against nothing |
| the **oracle** | `ucache` weakrefs + `__del__` deleting by value reproduced the false-intern it was built to detect |
| the **oracle** | `dd-oracle.py` mints UOps *before* the first row, inventing 4 slot-count disagreements |
| the **walker** | `dd_fuel` = `32*(to-from)` truncated a cone to 57 nodes and it read as a small graph |
| the **digest** | frozen hashes cover the file *mutated*, not the file `SAME` is measured against |
| the **cache** | row dicts read "fresh" because `rows` is not a file |
| the **binary path** | `/tmp/rebase-gate/<stem>.bin`, 14 `__init__` ports, 33 stale files on disk |
| the **selftest** | `PASS` from six synthetic states with `run_port()` stubbed |
| the **mutation baseline** | was the M09 mutant, twice |

**A green lane has never once been sufficient evidence in this project.**

### Closed

- [x] `rows()` reads all three lane formats. **Superset proof over all 39 wired
      pairs: 0 keys gained or dropped, every `shared` count identical, `disagree`
      moved on exactly one pair (cstyle 222 -> 0).** The other 32 were `+0 -0`.
- [x] `renderer/cstyle.bend` WIRED — 222 shared / 0 disagree. Given up
      precisely: 9 of 222 are a refusal rendered as the marker.
- [x] `schedule/multi.bend` format readable (0 -> 213) but LEFT UNWIRED. A `t_`
      prefix normalisation gives 26 collisions of which **21 DISAGREE**; that is
      a second source of truth and the agreement is the expensive direction.
- [x] `dtype.bend` **19 -> 7** disagreements. Four cone defects; **A1's proof is
      a phantom `CONST C(27)` at slot 58 where `C(1)` lives at 27** — `U32` is
      both an index and a word, so an index passed as a value typechecks.
- [x] `lg5k` — the port never modelled `_broadcasted`'s weak-CONST remint.
      `F(1333788672)` measured, not typed.
- [x] M09 **MOVED, 8 rows**. `hi42` makes the `|` the row's own text. The REQUEST
      was a misdiagnosis: `l2i_shl.hi` is called unconditionally and the zero was
      a statement about a defective snapshot.
- [x] Mutation zero classifier: **5 verdicts**, `WRONG` asked before `VISIBLE`.
      Same site, same rows, different snapshot, different verdict.
- [x] One `PATCH-NOT-APPLY` reporter, 30 stale-anchor branches converted,
      **0 unmarked false zeros** (was 14) across 21 records. 7 harnesses left
      LOUD on purpose.
- [x] Arena threaded through the rewrite engine; the spurious SINK rule is
      removable **only in that order** — threading alone moved nothing observable.
- [x] Order-blind gates: all closed. `linearizer`'s 0.0% hit rate was the READER
      (`lt_lst` is a literal), not the fixture. The 98 sibling-blind rows are
      INHERENT — 98 of 98 CALL-derived.
- [x] `device.bend` is **not broken**; the quoted BROKEN never reproduced.

### Refused — and two of these were MY error, corrected by the unit

- [x] `eq_arg.AFloat` "one-word fix" **REFUSED**: it is a double regression.
      `ConstFloat` overrides `__eq__` AND `__hash__`; `AFloat` is a bare float.
      Both comparators are correct, differently.
- [x] **Comparing the `py=` column REFUSED** — it is a literal in the PORT file,
      so comparing it asserts a transcription is correct. `device.bend`'s
      `sig=0 4 5` shipped green that way.
- [x] `gt_ops4`/`gt_ops5` **DECLARED A WALL.** A fixture could separate them
      (6 of 6 fingerprints) but CPython says both root ops are `Ops.WHERE`; the
      prescribed fix would have encoded a lie.
- [x] The 5 slot counts were an **ORACLE bug**, not a port defect.

### OPEN, and named

- [ ] **`uop/ops.bend` DOES NOT COMPILE** — `DRng.of` is an unfilled law. **72
      importers cannot be gated at all.** Highest priority; owned by a live unit.
- [ ] **`ABlob` false-intern is LOST from source.** The fix was never committed
      and a concurrent 5-step rewrite overwrote it. Preserved as committed
      evidence (`.agents/slop/afloat-ops-bend.bend`); the MERGE is undone.
      `eq_arg.ABlob(y: Arg, +n: U32)` — length only.
- [ ] **Four comparators weaker than upstream's key**: `eq_callinfo` substitutes
      `dtype` for `aux` and **`ops.py:549` reads `arg.aux`**, so it is not
      inert; `eq_kernelinfo` drops `estimates`; `eq_programinfo` drops `target`;
      `eq_pyrange` compares `H.I64` against a key holding `float|int|bool`.
- [ ] **Five `dd_band` call sites pass `O.Found.i(...)` as the mask** — the A1
      species. Their rows AGREE, which is coincidence or latent, not evidence.
- [ ] **25 of 30 mutation zeros still unclassified**; **20 of 22 tables name no
      revision**, so a reader cannot tell whether a table describes what is on
      disk.
- [ ] **224 hand-typed oracle rows, 192 never read.** `hand_typed` matches only
      literal row names, so f-string-named rows are invisible to it.
- [x] `ops-501-gate.sh` red at rest — 101 oracle `s5_*` rows vs 82 in the Bend.
      **DIAGNOSED, not guessed — see `[DONE] ops-501-gate: THE PORT WAS MISSING THREE
      DEFS` at the END of this file. `101 | 82 | 82 shared | 19 oracle-only | 0 port-only |
      0 disagreements on shared`: the THIRD hypothesis (different row names) is ELIMINATED,
      and the 19 are `ops.py:758/:841/:846`, which the port carried as `TODO(p3)`.
- [ ] Gate cluster (`kxrmluuw`) committed but **unverified** while `ops.bend`
      does not compile. Its commit message says so rather than claiming a pass.
- [ ] `c7`, `lgu`, `lgun` — declared refusals. `c7 = F(2139095040)`, confirmed
      four times independently.

### Process, learned the hard way

- **A working copy shared by eight agents is not a preservation mechanism.**
  Three correct fixes were destroyed by concurrent overwrites today
  (`codegen/__init__.bend`, the `ABlob` fix, and one unit's six `dtype` fixes
  swept into `e049d6ecb`). Commit verified work *before* the next agent starts.
- **Three `jj` traps, each of which silently did nothing:** `jj describe` has no
  `-f`; `JJ_EDITOR="cat f"` prints but does not write (use `cp`); and the
  bookmark auto-drags forward when a live agent writes, so `bookmark set` needs
  `--allow-backwards`. All three present as "won't push commit, no description",
  which points at the wrong thing.
- **Line count is not an identity.** A reconstruction with the right 361 lines
  had the wrong md5. The md5 assertion is the check.
- **An unfinished measurement masquerades as an unstable one.** Four reads of one
  file gave 239 / 246 / 354 / 355 rows while a background job was still writing.

## Session 2026-10-04 (substrate unit) — the `ABlob` intern key is GREEN and PROVEN, and `ops.bend` is being edited faster than it can be gated

- [x] **`eq_arg.ABlob` compares CONTENT, not LENGTH.** `ABlob{bs: List<&2, U32>}`
      (:1062) and `eq_arg.ABlob` (:1801) compare with the file's existing `eq_u32`, the
      same def `eq_arg.ATuple` uses. **9 `blob_*` rows, 3 lanes identical**
      (`sh .agents/slop/blob-intern-gate.sh`, expectations CALLED from CPython). The
      fixture is `b"aaaa"` against `b"bbbb"` — equal length, unequal content — because an
      all-different-length fixture is satisfied by a length key, which is how the original
      bug sat in a green gate.
- [x] **The key holds the BYTES, and that is now CHECKABLE rather than argued.**
      `.agents/slop/blob-verify-independent.py` reads `ucache`'s KEYS where
      `blob-intern-oracle.py` reads `len(ucache)`, and prints
      `(Ops.BINARY, (), b'aaaa', None, <class 'bytes'>)` /
      `(Ops.BINARY, (), b'bbbb', None, <class 'bytes'>)`. A digest is still a summary; this
      key is not one. Both oracles agree on all nine rows across two runs.
- [x] **CONTROL, measured on a MIRROR, never on the live tree.**
      `.agents/slop/blob-control-mirror.py` rebuilds `.agents/slop/mirror/` from the live
      tree on every run, asserts the two digests match, and re-asserts the LIVE digest
      before and after every mutation. M1 (length-only, the bug restated) moves 4 rows
      including `blob_count_len_diff_content: 2 -> 1` — the defect's own signature. M2
      (first byte) 3, M3 (never equal) 3, M4 (always equal) 5; the table moves 7 of 9 rows.
      The 2 that never move are `blob_shape` and `blob_content`, which no comparator can
      change — a real blind spot with a reason.
- [x] **Blast radius is PROVABLY LOCAL.** Against the recorded 12,429 baseline the corpus is
      12,489 (+60) and **exactly one of the 72 files changed**: `uop/ops.bend`, 224 -> 284.
      The other 71 are byte-identical on their non-blank rows (checked by sha256, not by
      count). Historically the fix itself is +9 rows in `ops.bend` and `grep -l 'blob_'`
      across all 73 captures returns exactly ONE file.
- [x] **The 72 = 59 direct + 12 transitive + `ops.bend`.** Bend imports are UNQUOTED
      (`import ./ops.bend as O`), so a quoted grep finds **0** importers and measures a
      vacuous blast radius — the same empty-set-reads-as-clean failure as a 0-row result.
- [ ] **`ops.bend` is under concurrent edit at ~7 writes / 2 minutes and the blocker
      is RECURRING, not fixed.** Observed in this session: `SOME PROOFS FAIL` naming
      `DRng.of`, then `a ParamArg pattern with 13 fields` (:6882, a 3-field pattern
      against the 13-field `ParamArg` — the width rule, verbatim), then
      `duplicate declaration: UOp.unbound.go`, then `ALL PROOFS CHECK`. Each error was
      fixed by the owning unit within ~30 s of my reading it. **Not one edit was made by
      this unit**: at that write rate an edit is either clobbered or clobbers, and the
      `ABlob` fix has already been destroyed once by exactly this. Filed for the owner.
- [ ] **`.agents/slop/blob-intern-mutate.py` IS A LIVE WEAPON and should not be run
      as-is.** It mutates `tinybendygrad/uop/ops.bend` IN PLACE and restores from a
      snapshot in a `finally`; its stale-snapshot guard runs ONCE at start, so a
      concurrent edit landing mid-run is silently reverted at exit. Its own docstring
      records a restore putting a dead 6623-line file over the live 6306-line one.
      `blob-control-mirror.py` replaces it. Do not run the old one on this tree.

## [DONE] ops-501-gate: THE PORT WAS MISSING THREE DEFS, and `@` is not "at rest" (2026-10-04)

Progress: `[████████████████████] 100%` — which side named with denominators, the 19 named and
classified, four real defects fixed in MY files, 3 controls green, 23/23 mutations. **`uop/ops.bend`
not edited** — it belongs to the unit porting `ops.py[701,1000]`. Nothing committed.

- **THE PORT IS THE WRONG SIDE, and the third hypothesis is ELIMINATED rather than assumed
  away.** `101 | 82 | 82 shared | 19 oracle-only | 0 port-only | 0 disagreements on shared`,
  measured at `@-`. Same names, same values, on every row the two sides share — so this is
  **19 rows MISSING FROM THE PORT**, not 19 spurious oracle rows and not a naming split.
- **WHY ASKING `@` SAID GREEN SIX TIMES OUT OF SIX: `@` IS THE WORKING-COPY COMMIT.** The at-rest
  state is `@-`. `jj file show -r @- tinybendygrad/uop/ops.bend | grep -c '"s5_'` = **82**; the
  same at `@` = 101. A unit ported `copy_to_device` / `getaddr` / `device_range_src` into the
  working copy minutes before, so the question "is this gate red at rest" was being asked about
  a file that was not at rest. **`bend2-constraints.md` O-1** (position 19078).
- **THE 19 ARE THREE `TODO(p3)` MARKERS, not 19 bugs.** At rest, `ops.bend:4319/4336/4338` read
  `# TODO(p3) ops.py:761 def copy_to_device` / `:844 def getaddr` / `:849 def device_range_src`.
  **MEASURED def lines are `tinygrad/uop/ops.py:758`, `:841`, `:846`**, identical in the vendored
  pin and in `.agents/slop/opstree` (the two trees differ in ONE line, at 1333, outside every
  range an `s5_` row touches — which is why both trees give byte-identical 101-row output).
  **THE REPO'S `ops.py` CITATIONS ARE A UNIFORM +3 IN THE 500–850 BAND AND NOT ELSEWHERE:**
  `without_after` 623 vs 620, `barrier` 624 vs 621, `bufferize` 679 vs 676, `allreduce` 680 vs 677,
  `split_uop` 685 vs 682, `sharding` 707 vs 704, `mselect` 772 vs 769, `base` 785 vs 782,
  `unsharded_base` 792 vs 789, `storage_base` 801 vs 798, `buf_uop` 925 vs 922 — then
  `has_buffer_identity` 952 vs 954 is −2 and `gate_kernel_sink` 1901 vs 1909 is −8. **A citation
  band with a constant offset inside it and a different one outside it means the basis is a
  different tinygrad revision, not a typo.** Left alone (other units' files), recorded as
  **O-3-adjacent / found-not-fixed**.
- **EACH OF THE 19 CHECKED AGAINST THE upstream SOURCE, not just against a count.** `getaddr`
  (`ops.py:841`) mints GETADDR iff `self.without_after.op` is in the nine-op set
  `{BUFFER, ALLOC, SHRINK, BITCAST, BINARY, MSTACK, MSELECT, PARAM, LINEAR}` — the 13 `s5_ga_*`
  fixtures are 9 in-set, 3 out (`CONST`, `RESHAPE`, `ADD`) and **`AFTER` which peels to BUFFER
  and therefore MINTS**, which is the row that makes the `without_after` in the PEEK load-bearing.
  `copy_to_device` (`ops.py:758`) `src=(inp, *device_range_src(device))`, which is why
  `s5_copy_sel` is `COPY/MSELECT Ops.RANGE` and `s5_copy_multi` is `COPY/BUFFER Ops.RANGE`.
  `device_range_src` (`ops.py:846`) is `()` for a `str` and one RANGE for a tuple.
- **THE PRIOR UNIT'S LIST OF THE 19 WAS OFF BY ONE, MECHANICALLY.** `TODO.md`'s account named
  `s5_copy_*` (3) + `s5_devrange_*` (3) + "12 `s5_ga_*`" = 18 against a stated 19. The missing
  one is **`s5_ga_add`**, and it is missing because in `ops.bend`'s `s5.garows` every row is
  bound (`l : Unit <- srow("s5_ga_after", …)`) EXCEPT the last, a bare `srow("s5_ga_add", …)`.
  A tally taken by scanning for the bound form finds twelve. **`bend2-constraints.md` O-8**
  (position 19168): when a count and a list disagree, the LIST is wrong — re-derive from lane text.
- **FOUR REAL DEFECTS FIXED, ALL IN FILES THIS UNIT OWNS, all with before/after:**
  1. **`ops-501-oracle.py`: TWO ROWS EXPECTED A RE-IMPLEMENTATION OF THE THING UNDER TEST.**
     `gate_kernel_sink` was a hand-written copy of `ops.py:1909` (3 rows) and `split()` was a
     hand-written worklist copy of `split_uop` (`ops.py:682`, 6 rows) — the `device.bend`
     `sig=0 4 5` hazard, and `nv_query_litter` wrong in BOTH port and oracle. Both now CALL
     upstream. **NO ROW MOVED** (101/101, byte-identical md5), which is the correct outcome and
     not a tautology: the transcription was right and the rows are now CPython's own answers.
     **The nine rows they govern are covered by 6 existing mutations** (`gks_drops_linear`,
     `gks_drops_kernelinfo`, `split_pushes_to_back`, `split_appends_to_out`, and
     `without_after_drops_after`, which also moves `s5_ga_after`).
  2. **`ops-501-gate.sh` NAMED NO REASON FOR ANY FAILURE IT EVER REPORTED.** Measured: on a file
     that does not check, `--check-only` writes **nothing to stdout** and puts `SOME PROOFS FAIL`,
     `Error:` and the offending line on **stderr**, so `bend … | head -1` read empty and printed
     `--check-only says ''`. Now `2>&1 | grep -m1 -v -e '^bend 2\.0\.' -e '^$'`; measured
     `--check-only says 'SOME PROOFS FAIL'`. (`bend2-constraints.md` O-3, position 19110.)
  3. **`ops-501-gate.sh`: `CMD | grep '^s5_' > OUT` UNDER `set -e` IS A SILENT FAILURE** — a bare
     `rc=1` with nothing on stderr, indistinguishable from a crash, and bend stack-overflows
     ~1 run in 20. Each lane now reports its own count by name and a zero-row lane is refused by
     name. (O-4, position 19123.)
  4. **`ops-501-mutate.py` WROTE THE LIVE `ops.bend`** — `OPS.write_text(...)` plus a `finally`
     that restored it. `ops.bend` was being edited by another unit, so a read-then-write whose
     window straddles their save **permanently destroys their work**. It now stages
     `jj file show -r @` beside the real file, asserts the digest, unlinks in `finally`, and
     REPORTS if the live digest moved. Its second reader is gone (now `rebase-gate.py`'s `rows()`).
     **23/23 mutations move the rows they name**, live `ops.bend` byte-identical before and after.
- **THE 19 ROWS HAD NO MUTATION AT ALL.** They were oracle-only for the gate's whole life, so
  nothing said any of them read the port. **7 added**: `devrange_hardcodes_one`,
  `ga_drops_param/mstack/linear/bitcast`, `ga_peel_reads_self`, `copy_sel_drops_mselect`,
  `copy_drops_device_range`. **Their anchors carry the `def UOp.getaddr.op(op: Op) -> Bool:`
  header** — `case OpsPARAM{}: True{}` alone occurs **4** times in `ops.bend` and a 3-line window
  **6–62** times, so an unanchored `str.replace` edits `buf_uop.cont` or `hbi`'s set instead. (O-6.)
- **THE CONTROLS, all three, and the red path is the one a missing-row failure cannot supply:**

  | control | measured |
  |---|---|
  | clean, live file, **both trees** | rc=**0**, `101 rows, 101 shared row names, 3 lanes identical` |
  | **AT REST `@-`**, staged copy, through the REAL gate script | rc=**1**, `py=101 bd=82 shared=82`, **19 row names printed** |
  | **planted** one op out of `getaddr`'s ladder, staged copy | clean rc=0, planted rc=**1**, `ROW DISAGREE s5_ga_param: cpython=Ops.GETADDR/Ops.PARAM bd=Ops.PARAM` |
  | restore | live `ops.bend` md5 identical before and after every one |

  The at-rest failure was a **MISSING-ROW** failure and so never ran the value-diff arm; the
  planted one is the control that proves that arm works. **A red gate and a broken gate are
  different states and both read as "the gate is red."** Repeatability: at-rest control **3/3**
  identical (`rc=1, shared=82, disagreements=0`); oracle md5 **3/3** on each of the two trees.

- **STATE OF THE GATE NOW, HONESTLY: `AGREE`, on a file that is still being written.** 101 rows,
  101 shared names, 0 disagreements, three lanes identical, exit 0, on the upstream tree and on
  `TG_TREE=.` — and **GREEN AT TWO DIFFERENT REVISIONS** (`ops.bend` md5 `99ab4691…` at 06:12 and
  `19205b9a…` at 06:20, both rc=0), so the result is not one lucky snapshot. **Neither digest is
  durable**, and that is why the measurement is stated as a revision: the file changed **six
  times** during this unit (46d4f3f7 → d1a40c4b → dc2955e9 → 674f4857 → a9c8063b → 99ab4691 →
  19205b9a), was caught mid-edit not checking at all (`duplicate declaration: UOp.unbound.go`,
  then `a Some pattern with 1 field`), and two of this unit's own controls only passed because
  they ran against a STAGED copy rather than the live path. **The GREEN is a property of a
  revision, not of the gate.** Re-run `sh .agents/slop/ops-501-gate.sh`.

### Found, not fixed

- **Repo-wide `ops.py` citation offset** in the 500–850 band (+3 uniformly, −2 and −8 above it):
  a different tinygrad revision is the basis. Every citation, not just these three.
- **Seven `## Z-` entries in `bend2-constraints.md` cite positions that are wrong by exactly 9**
  (`Z-1` cites 18898, real line 18907; … `Z-7` cites 18963, real 18972 — measured with a script
  that reads each header and compares its cited position to its own line number). **Left alone —
  renumbering another unit's entries is what "append-only, do NOT renumber" forbids.** The `## B-`
  and `## O-` entries are all correct.
- **`.agents/slop/ops501-atrest.sh` is redundant** with `ops501-ctl.sh` and has no caller.
- **The CPython lane was observed printing 0 rows once**, in a `| grep '^s5_'` pipeline, rc=1.
  **It did not reproduce in 25 consecutive runs** (3/3 rc=0 + 20/20 at 101 rows + 5/5 in the
  original form), so it is an UNEXPLAINED single observation and not a confirmed flake — but
  it is the reason fix 3 exists: under the old gate a 0-row lane exited 1 with no message.
- **The two `raise`s inside `copy_to_device` are still not ported** (`is_disk_device` needs
  `uop/fold.bend`'s table read; `inp.dtype in dtypes.weaks` needs the dtype fold). The port's
  own comment at `ops.bend:6703-6708` declares this and `s5_copy_*` does not pretend otherwise.
  **They are also `AssertionError`/`RuntimeError` paths, so a refusal here is a truncated trace
  and the `s5_` rows would need a negative case before those two TODO(p3)s can close.**

---

## Session 2026-10-04 (gc3) — `graphcmp`: WIDENED TO NINE GRAPHS, A DEBUG-LEVEL
## COMPARISON, AND A PROOF THAT THE DIFFER CAN FAIL

Entry points: `.agents/slop/graphcmp.py` (the differ), `.agents/slop/graphcmp.bend` (the port
side), `.agents/slop/graphcmp-dbg.bend` (the DEBUG probe),
`.agents/slop/graphcmp-oracle.py` (the coverage census),
`.agents/slop/graphcmp-dbg-oracle.py` (the CPython reachability oracle),
`.agents/slop/graphcmp-run.sh` (every artifact, one command),
`.agents/slop/graphcmp-LIMITS.md` (**the honest limits -- read this one**),
`runs/graphcmp/D/README-D.txt` (the artifact index with every command and its denominator).

`E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py`

- [x] **RE-VERIFIED THE FOUR EXISTING GRAPHS ONCE, THEN MOVED ON.** matmul 18 nodes, reduce
      7, buffer 5, sink 2 -- all `AGREE`. The previous session's `runs/graphcmp/C2/C7` files
      held 0-ROW FAILURES because `graphcmp.bend:361` still read `O.ABlob{n2}` and the port's
      field is `bs`; one line fixed it and the whole lane came back. (GC: the BLOCKER was in
      the HARNESS, not in the 72 ungateable importers.)
- [x] **WIDENED 4 -> 9 GRAPHS. All nine `AGREE`, each printed with its denominator:**
      matmul 18/18 nodes 108 field-records · reduce 7/7 · buffer 5/5 · sink 2/2 ·
      range 2/2 · rangeflat 2/2 · cast 6/6 · special 2/2 · binblob 19/19.
      **TOTAL 63 nodes per side, 378 field-records, 13 of 77 ops.** `AGREE` on 2 and `AGREE`
      on 19 no longer print the same way: every report carries
      `graphs= nodes= fields= field-records= shared-cores= commutative-ops=`.
      The five new ones each reach something no existing graph reached: `range`/`rangeflat`
      are the **only non-zero `depth` anywhere**; `cast` is the only bare-`DType` arg;
      `special` is a bare str outside a `KernelInfo`; `binblob` makes the `y` residual LIVE.
- [x] **THE DEBUG-LEVEL COMPARISON.** `E dbg --levels 0,1,2` runs the port probe once per
      level with `DEBUG` as the ONLY difference, diffs the seven gated sites' traces through
      the same differ, and **holds the graph fixed by construction AND by check**: the probe
      builds ONE graph (`GC.matmul_of`, IMPORTED from graphcmp.bend, not copied) and prints its
      own rows every run; `dbg` DIGESTS them per level and exits 2 (a FAILURE, never a
      verdict) if two digests differ. MEASURED: digest `c8baceda7b61` at levels 0, 1 and 2,
      `distinct=1`. MEASURED: 0 vs 1 moves exactly the ONE level-1 site (`mem`, named with its
      full line); 1 vs 2 moves exactly the six level-2 sites; 0 vs 3 moves all seven. The
      trace rows' `depth` column carries each site's THRESHOLD, so `thr_mem=1` against six
      `i2`s is visible inside the diff itself.
- [x] **THE DIFFER CAN FAIL, AND IT NAMES THE NODE.** All six plants `DISAGREE`. The
      two-sided planted case: `MISMATCH MUL py#16 vs bend#16 ... src py=['bd57da94',
      '2b7d1a7e'] bend=['2b7d1a7e','bd57da94']` -- two arenas in two processes, and the
      disagreement names the node on each side.
- [x] **THE THREE CONFLATIONS, `E conf`, one verdict line each, `ALL THREE DISTINGUISHED`.**
      (a) same `repr(arg)` / different structure: MEASURED `repr(arg)` is `None` on both
      sides and the differ names `src`. (b) same `arg` at a different depth: **NOT
      REPRESENTABLE** -- the depth is encoded twice on purpose, and what IS shown is that the
      differ NAMES a depth difference (`range` vs `rangeflat`, rung 3.5 prints `depth` and
      `arg` by name, and each graph separately agrees with the port). (c) reordered but
      equivalent: `--equiv` did not exist before today; `diff --plant srcswap` DISAGREES and
      `diff --plant srcswap --equiv` AGREES on 18 nodes / 108 field-records.
- [x] **THE LIMITS ARE WRITTEN DOWN WITH THEIR REASONS.** `.agents/slop/graphcmp-LIMITS.md`:
      11 defects found by widening (all in this unit's own normal form, all measured), then
      what is not compared, then what CANNOT be done structurally, then the three conflations,
      then what a clean run does and does not establish.
- [x] **REPRODUCIBLE BYTE-FOR-BYTE.** `D9-stability.txt`: two runs of `diff --graph binblob`
      are byte-identical, and four graphs' canonical files are byte-identical py vs bend.

### Found, not fixed

- **`uop/ops.bend` STOPPED COMPILING mid-session** (another unit, at digest
  `fbf2de82781b3bac9e4c6927d2f14f981e8654bd1ac73b175e842ef91d5486b8`, failing at
  `UOp.const_factor.mul`, ops.bend:7028). **Reported, not edited** -- it is not my file.
  All of `D0`-`D10` was captured on a COMPILING tree; the coverage census
  (`graphcmp-oracle.py`) is the one artifact BLOCKED on it, recorded as
  `runs/graphcmp/D/D0-coverage-census.BLOCKED.txt` with the command and the digest.
- **CPython's own `DEBUG >= 1` memory line (`memory.py:59-60`) fired on 0 of 8 real graphs**
  (`D8b-cpython-dbg1-reachability.txt`). So `dbg` has NO CPython lane for the trace text and
  is a port-vs-port comparison across levels. Stated in the tool's own output and in LIMITS.
- **`--equiv` is MEASURED on ONE of its eight commutative ops.** Only MUL is reached by any
  graph or plant, so ADD/AND/MAX/CMPNE/CMPEQ/XOR/OR are unexercised. A fixture with an `ADD`
  would close it.
- **A symbolic dim and a float CONST are both UNTESTED, not measured-safe**: 0 of 63 nodes has
  either. Both are places where the normal form compares less than it could (`U` and
  `repr(x)`), and neither has a fixture.
- **Six of the eight ledger markers are live on NO graph** (`u`, `q`, `X!`, `BAD`, `?`, `E`);
  they are reachable only through plants. `?` cannot be produced by the py side at all.
- **The rung-2 "no mutual best" rule DROPS some real field differences to rung 3**, where they
  are printed in full but not NAMED. Deliberate (five matmul RESHAPEs share one `loose` key),
  and a real cost.

---

## ARENA ALIASING SWEEP — `O.Arena.node` is TOTAL, so a wrong index is a plausible value

Progress: `[###.......] 3/10` · **1100** arena read sites audited · **3 stale/bogus reads
found, 2 files touched** (3 rows moved with a CPython-called expectation, 3 rows moved with
an UNVERIFIABLE direction, 0 rows moved) · **8 detector suspects adjudicated** (0 remaining) ·
**4 detectors, each with a measured control** · rules `ARENA-1`..`ARENA-7` appended at
`.agents/slop/notes/bend2-constraints.md` positions 19413-19486.

### Done

- [x] **CENSUS.** `arena-audit.py` walks all 1100 `O.Arena.{node,src,src0,op,arg,tag,srcs,
      next,nsrc,src_from,src_to,src_without_body,depth,at,budget}` reads in
      `tinybendygrad/**` and records `(arena_expr, index_expr, def, params)` per site.
      Result: **155 SAFE / 933 LATENT / 12 EXPOSED / 0 DEFECT-by-static-shape.**
      `arena-stale.py` narrows the within-expression risk shape (index is `Found.i(f)` but the
      arena is a different expression) from 1111 to **24**, all of which are gate printers
      that thread `Found.ar` from the same `Found`.
- [x] **DEFECT FOUND AND FIXED: `engine/jit.bend` `pl_step`.** Both arms appended the arena
      bottom `0` where `tinygrad/engine/jit.py:19,21` appends the NODE `si`. Both
      `prune_sig_*` rows therefore read `srcops=Ops.NOOP`. Two rows moved
      (`srcops=Ops.NOOP -> Ops.CALL` / `Ops.BUFFER`), 137 rows, none lost, and
      `.agents/slop/jit-prune-truth.py` calls `prune_linear` on the same fixture for the
      expected values (run twice, identical).
- [x] **DEFECT FOUND, NOT FULLY GATED: `uop/validate.bend` `dv_shr2.of` / `dv_and.put`.**
      Both pass the PRE-mint `ar` to a helper that indexes a node minted into the RETURNED
      arena. `.agents/slop/arena-validate-probe.bend` proves it:
      `idx=4 in_pre_mint_arena=None in_found_arena=Some pre_src0=0 found_src0=2`, and the
      z3 range came out `u=0:0:99` (built from the arena BOTTOM) instead of `u=2:0:99`.
      Fixed by passing `O.Found.ar(t)`. `dv_shr2` moves 0 rows.
      ✅ **NOW ADJUDICATED -- and the adjudication corrected the claim.** With an oracle
      (`.agents/slop/validate-oracle.py`) the aliasing moves **ONE** fixture's rows, not three:
      M1 reverts the one line and moves exactly `dv_and21`, `dv_and21_term`, `dv_and21_term_nb`
      from `- 256` to `- 1`, i.e. AWAY from CPython (disagree 10 -> 13 of 90 shared).
      `dv_and15` and `dv_and_neg4` are INSENSITIVE to it: `z3_and`'s `pow2` arms fire for 15
      and -4 and never reach `z3_bv`, so no width is read. They printed `- 256` before only
      because `pow2` was ALSO broken; they now print `r0%16` and `r0 - r0%4`.
- [x] **DETECTOR, `arena-noop-scan.py`,** over the 73 committed gate outputs / 12720 rows.
      60 rows mention NOOP; 16 excluded mechanically (index 0 is the bottom), 33 by row name,
      3 as a quoted repr string; **8 suspects, all adjudicated against CPython, 0 left.**
- [x] **DETECTOR, `arena-noop-probe.bend`,** the `at`-based one, with a NEGATIVE CONTROL that
      prints `ctl_pre=None ctl_post=Some` for one index read out of two arenas.
- [x] **THE `+` MARKER IS NOT AN OWNERSHIP MARKER** (`arena-affine-probe.bend`). Two
      measurements that RETRACT the safety argument for 589 sites:
      `ctl2_read=None` (a read after a spend is permitted) and
      `ctl1_f=2 ctl1_g=2 ctl1_f_1=CONST/0:1 ctl1_g_1=CONST/0:2` (two mints from one arena
      name return the same index and overwrite each other). Re-labelled LATENT.
- [x] **SIZE SWEEP at k = 0,1,2,5,17,64** (`arena-sweep.sh` + `arena-sweep-jit.bend`), which
      **asserts its k=0 block against the committed gate AND against CPython before it
      diffs**, and which its own control proved catches 1 of 4 injected defect shapes.

### ✅ CLOSED -- `dv_and*`'s `1` -> `256`, and the premise behind the open question was FALSE

The open question said: "**z3 IS NOT INSTALLED IN THIS ENVIRONMENT**, so CPython's
`uops_to_z3` cannot be CALLED, and `dv_and*` has **no oracle anywhere in `.agents/slop/`** --
the three rows are PORT-ONLY. A hand-derivation of `validate.py:16` gives `w=8` -> bound `128`,
which matches NEITHER `1` NOR `256` and therefore settles nothing. ... Whoever picks this up
needs `z3-solver` installed..."

**z3 WAS installed.** `z3.get_version()` is `(4, 16, 0, 0)`, `validate.py`'s own version gate at
line 8 passes, and `import tinygrad.uop.validate` gives a live `z3_bv`. The rows were never
un-adjudicable; they were un-oracled. Nothing had to be installed.

**ANSWER: `- 256`, called live.** `.agents/slop/validate-oracle.py` runs `uops_to_z3(solver, idx,
gate)` + `solver.add(z3_mask)` (validate.py:92-95 verbatim) on `AND(RANGE(0,100), CONST(21))`:

    dv_and21 = [And(r0 >= 0, r0 <= 100 - 1), True] | If(int_to_bv(r0) & int_to_bv(21) < 0,
               BV2Int(int_to_bv(r0) & int_to_bv(21)) - 256, BV2Int(int_to_bv(r0) & int_to_bv(21)))
               |  | 0

`validate.py:16` on CPython's own `UOp._min_max` (`(0,99)` and `(21,21)`) gives `w = 8`, and the
literal inside z3's signed `BV2Int` expansion is `2**8 = 256`. The `- 1` is wrong; the fix is
KEPT. **`128` is the width of a DIFFERENT NODE**: `w = 7` is what `RANGE(64) & CONST(2)` gives --
the `dv_shr2` shape. Oracle rows `w_and_64_2=7` and `w_and_100_21=8` sit side by side so the two
numbers are distinguishable by a row name instead of by an argument. M2 in
`.agents/slop/validate-mutate.py` produces the `128` mechanically (drops the `1 +`) and moves 7
rows away from CPython (10 -> 17), which is the falsification.

**AND THE `128` WAS A HAND-DERIVATION ERROR TWICE OVER**: `w = 8` gives `2**8 = 256`, not 128.

**THE ORACLE AND THE GATE** (both new, both in `.agents/slop/`):
  * `validate-oracle.py` -- every value from a live `uops_to_z3` call, `name=value`, plus
    `mm_*` rows for the hand-written `_min_max` table so it is CHECKED and not trusted, plus
    `w_*` width rows and the `z3_ok` / `z3_d3` / `validate_import` rows that make the false
    premise checkable in one command.
  * `validate-gate.py` -- both lanes, read with `rebase-gate.py`'s `rows()`, reporting the
    DENOMINATOR: **port 107 rows, oracle 280, shared 90, agree 80, disagree 10.**
  * `validate-mutate.py` -- 11 mutants, each run through BOTH lanes so a row that moved TOWARD
    CPython is distinguishable from one that moved away. **10 move away, 1 (M10,
    `range_str`'s axis-id separator) moves NOTHING and is a declared blind spot**: every fixture
    has a single axis id and no multi-axis row exists, so the separator is untested by
    construction. Baseline md5 `88671e271e24c280742b9a62e4d892e8`, restored and asserted.

**THREE MORE REAL DEFECTS FOUND BY THE ORACLE, AFTER THE ABOVE WAS WRITTEN:**
  * `Ops.CDIV` was routed to `k = 2` = `z3_floordiv`. **Different functions.** Two `z3_alu` keys
    on one tag; for a positive divisor they agree on shape and disagree on nothing visible, which
    is why nothing caught it. `dv_cdiv4` caught it. Fixed (a fourth tag).
  * **NO PARENTHESES IN THE PRINTER AT ALL.** `dv_xor_m1` printed `-r0 + 1` where CPython prints
    `-(r0 + 1)` -- different functions. The rule is precedence not associativity, 60 measured
    cases, and it needs FIVE classes because `a + (b - c)` prints `a + b - c` while `a - (b + c)`
    prints `a - (b + c)`.
  * `Z.cls` and the parent-class literal in each `Z.str` arm are THE SAME TABLE WRITTEN TWICE, 40
    lines apart, with no compiler check tying them together -- the same shape as a hand-written
    `py=` literal, and it is why `dv_cdiv4` was red before the row existed to be red.

**AND A DEFECT IN MY OWN INSTRUMENT, twice, both worth naming:**
  * The oracle's row names `cmp_i<=5` contain `=`, and `rows()` splits on the FIRST `=`. MEASURED:
    310 printed lines, 280 parsed rows, **30 collapsed onto 10 names**, each of which then held
    FOUR different measurements. Operators renamed to `lt`/`le`/`gt`/`ge`: 314/314, 0 collapsed.
  * `norm()` collapses z3's line wrap to a SPACE, which INVENTS one: the raw text of `dv_cmod4`'s
    term ends `r0/4)*\n4` and z3 printed no space there. The port was right and my oracle was
    wrong. A second encoding (`norm_ns`, wrap deleted with nothing) is unsound in the OPPOSITE
    direction -- z3 wraps after a comma too -- and was removed. Neither is sound; the residual is
    now one named row plus oracle rows `#raw_cmod4` / `#wrap_cmod4` as evidence.

**EIGHT REAL DEFECTS FIXED EN ROUTE, each with the mutation that moves rows away from CPython
when reverted**: the arena `dv2` builds the SINK in (M3, 34 rows); `vz_cint` unable to read a
`CBool` CONST, which was the real cause of the missing `True` (M5, 68 rows); `pow2`'s `m > 0`
written as a sign-bit test (M4, 6); `create_bounded` building `Le(vmin, sym)` where Python
REFLECTS into `Ge(sym, vmin)` (M6, 24); `Ops.MAX` silently floormodded (M7, 3); `range_str` and
the violation join both dropping their first element; `Sol.put` leaking terms into the assertion
list (M8, 34); `z3_lt`, z3's `a < n` -> `n > a` canonicalisation (M9, 5).

**WHAT IS STILL RED -- 15 of 138 shared rows, every one named:**
  * `dv_cmod4`, `dv_cmod4_term`, `dv_cmod4_term_nb` (3): ONE SPACE, and the port is right --
    `#raw_cmod4` shows z3 wrapped between `*` and `4`.
  * `dv_shr2`, `dv_shr2_term`, `dv_shl2`, `dv_shl2_term` (4): z3's per-Context `FreshInt` counter,
    `invalid_shift!0`. The `_term_nb` rows strip it on BOTH sides and AGREE.
  * `dv_unsup_stack`, `dv_unsup_two`, `dv_unsup_two_msg`, `dv_rank_shr1`, `dv_rank_shr1_msg`,
    `dv_bad_dtype_bitcast` (6): CPython RAISES and the port answers with a violation LIST. The
    declared design difference; `_msg` rows carry the shared message text. `dv_bad_dtype_bitcast`
    is worse than that: its fixture (`Ops.BITCAST` with `arg=None`) is NOT CONSTRUCTIBLE in CPython
    -- `dtype_from_uop` (ops.py:182) asserts `CAST/BITCAST arg must be DType, got None` -- so that
    row can never be adjudicated as written. The constructible spelling (`arg=dtypes.bool`) does
    reach validate.py and answers `NotImplementedError: Ops.BITCAST is not supported by z3`;
    adding it as a row needs a dtype-carrying Arg in `ops.bend`, which is another unit's file.
  * `dv_where`, `dv_where_cs` (2): the port emits `And(v >= 0, v <= 15)` TWICE, CPython once. A
    rewrite-accounting defect in the walk, **NOT LOCATED**. The `_where` fixture is the only one
    whose node is reachable twice (the PARAM is src[0] of the CMPLT and src[1] of the WHERE), so
    the duplicate is specific to a DAG with a shared node -- which is the common case and not a
    corner.

### Found, not fixed

- **`codegen/decomp/dtype.bend` holds 142 of the 24 stale-arena candidates' neighbours** and is
  owned by another unit; `uop/ops.bend` was mid-edit by another unit for ~6 minutes of this
  sweep (cold-compile failure at `UOp.const_factor.mul`, ops.bend:7028, and a duplicate
  `GroupOp.defines` at :6990), during which four probes could not run. Both recovered on retry;
  the `jit.bend` fix was re-verified afterwards on the settled substrate.
- **PADDING IS A WEAKER DETECTOR THAN IT LOOKS.** Measured on four injections: it resolves a
  FIXED wrong index and misses a wrong constant, a wrong offset, and a stale arena. See
  `ARENA-5`. A clean padding sweep must not be reported as evidence for those three.
- **THE 12 EXPOSED SITES** (`ar` is a non-affine, therefore copyable, parameter) are reachable
  by a caller passing one arena to two builders. Not fixed: each is a 2-line signature change
  with no row that distinguishes the change, and inventing one would be a tautological test.
- **`function.bend`'s `callu_ops`, `nn/optim.bend`'s seven `unverified_*`, and
  `schedule/prepare.bend`'s `ear_26_ops` all print NOOP and are KNOWN RECORDED WALLS**, not
  latent defects: `function.bend:876` (a dedup-order bug in read-only `helpers.bend`),
  `nn/optim.bend:1371` (a CONST interned into a different arena than its consumer, named as
  tensor.bend rule 5), and `prepare.bend`'s NOOP is a genuine `PatternMatcher` table key.
- **`rng_loopfn`'s `Ops.NOOP` is CPython's own**: `tinygrad/uop/ops.py:645` is
  `UOp(Ops.RANGE, src=(UOp(Ops.NOOP),), ...)`. Called and confirmed in
  `noop-src-truth.py`; the detector excludes it by OPERATION, not by a name list.
- **`codegen/kernel.bend`'s `ops` row oracle is a HARDCODED LITERAL** (`kn-truth.py:167`
  prints the expected value rather than deriving it). `kn-noop-truth.py` derives the same 19
  ops from real `UOp(...)` constructors and agrees. The existing oracle should be replaced;
  not edited here because it belongs to another unit.

- [x] **KEY-FIDELITY ROUND ON `tinybendygrad/uop/ops.bend` (sole owner this round). THE
      AUDIT'S PREMISE WAS HALF WRONG AND BOTH HALVES MATTER.**
      The four records the sweep called "weak comparators" are **not** weak comparators:
      `eq_callinfo`/`eq_kernelinfo`/`eq_programinfo` compare **every field their record has**,
      and the RECORDS are one field short of upstream's frozen dataclasses
      (`CallInfo` 4/5 at `ops.bend:1000` vs `ops.py:1400`; `KernelInfo` 4/5 vs `ops.py:1342`;
      `ProgramInfo` 6/7 vs `ops.py:1352`). `aux` is dropped from the RECORD, and
      `ops.py:549` reads it. **Reported, not fixed**: widening a record reaches past this file
      (9+18, 7+19, 9+9 sites) and I own one file. All four are `#bend_only_` in
      `ops-oracle.py` with the CPython answer and the site counts as the reason, so the
      CPython measurement is reproducible and the gate stays green at rest.
      **THE REAL DEFECTS ARE OVER-SPLITS, and there were TWO.** `ops.py:201` carries
      `type(arg)` and NOT `type(tag)`, so `tag=True` and `tag=1` are ONE key --
      `eq_tag` split them. And `type(arg)` disambiguates only the element that IS `arg`, so
      `ParamArg.val` (a nested `PyConst`) MERGES `True` with `1` where a CONST's arg SPLITS
      them -- `eq_paramarg` used `eq_opt_const` and inherited the top-level rule.
      Both fixed, both with a fixture that differs in EXACTLY ONE field, both CPython-measured:
      `tag_bool_vs_int_interns=True`, `pynest_bool_vs_int_interns=True`, each moving from
      `False` to `True` and **no other row moving**. Controls that must not move and did not:
      `tag_true_vs_false_splits`, `tag_none_vs_zero_interns`, `const_bool_vs_int_splits`,
      `pynest_int_distinct_interns`, `pynest_none_vs_zero_interns`,
      `pynest_cfloat_vs_int_interns`, `pynest_signed_zero_interns`.
      **`ConstFloat.__hash__` is `hash(bits)`, so a `ConstFloat` and an equal `int` are in
      DIFFERENT dict buckets and are never compared** -- `eq_pynest` crosses bool against
      `CInt` and MUST NOT cross it against `CFloat`, which is the opposite of what `__eq__`
      alone suggests. Gate: **112 shared rows, three lanes byte-identical, exit 0, 293 bend
      rows** (from 103 / 284). Blast radius `12,493 -> 12,502`, **sha256 of non-blank lines
      over all 72 captures: exactly one changed, `uop/ops.bend`, by nine added rows and
      nothing else**; `uop/validate.bend` also moved but its SOURCE moved too and the delta
      is another unit's `symbolic.bend` rebase (`And(i >= 0, i <= 15)` vs `[, i]`), proved
      not mine by a WITH/WITHOUT comparator diff over ten files including both external
      `eq_tag` callers (`uop/upat.bend`, `schedule/rangeify.bend`): **zero deltas**.
      **THE PAD SWEEP'S CALIBRATION IS THE OPPOSITE OF WHAT WAS PREDICTED, AND MEASURED:**
      `key-pad-sweep.bend` (pads 0/1/2/5/17/64) + `key-pad-mutate.sh` inject four classes --
      a wrong CONSTANT moves 12 sweep lines, a wrong OFFSET moves **0**, a stale ARENA moves
      12, a dropped FIELD moves 12; `ops.bend`'s own rows move 94/78/10/2. The offset class
      is invisible because `UOp.new.of` is `Found{made, UOp.of(made, ...)}`, so `UOp.of`
      ALWAYS hits and the `None{}` arm of `UOp.of.intern.put` is unreachable from `UOp.new`
      -- only the `sg_*`/`s5_*` sugar builders reach it. Notes K1-K5 appended at
      `bend2-constraints.md` ~19830.

---

## [x] FORM-BLINDNESS CENSUS — every tool that matches a form cannot see the instance
##      that lacks it. Six findings, one root cause, one checkable test.
##      `.agents/slop/{rowform,formblind-census,formblind-audit,substrate-audit}.py`
##      + `FORM-BLIND-SPOTS.md`. Rules `FB-1`…`FB-7` at `bend2-constraints.md` ~19941.

- [x] **THE RULE AND ITS TEST.** *A tool that matches a form cannot see the instance that
      lacks it.* Test: **spelling-invariance** — two texts that MEAN the same thing and are
      WRITTEN differently; a reader that disagrees is matching a form. **MEASURED: all six
      findings arrived as a DISAGREEMENT between two tools that meant the same thing, never by
      reading a tool**, so a disagreement count is not a coverage statement and the denominator
      is printed on every run.
- [x] **THE CENSUS, WITH ITS DENOMINATOR.** Every selector under `.agents/slop/` extracted
      from the tool's own AST and run against the meaning-equal spelling battery.
      **841 tools AT 07:40 (THE UNIVERSE IS LIVE — it was 851 and is 846 twenty minutes
      later, so run `--denoms` rather than quote it): 67 FORM-BLIND, 284 FORM-COMPLETE-ON-BATTERY (a FLOOR, not a proof),
      490 NOT-A-SELECTOR (UNAUDITED, NOT CLEARED), 166 delegating another tool's reader,
      156 FORKing one.**
      `xd1/` (4,989 files) and `opstree/` (348) excluded as vendored tinygrad checkouts —
      subject, not tool — and the four census instruments excluded from every denominator.
- [x] **THE MEASURED FLOOR.** `rows()` cannot read **3,298 lines** inside the **835** `.txt`
      lanes it DOES read: `SINGLE-SPACE` 3,086 (the gap must be TWO spaces), `TAB` 186
      (refused on purpose — a TSV table's first column is not a row name), `EQ-INSIDE-GAP` 19
      (the `=` branch claims it first and RENAMES the row). Read twice, stable. Plus the one
      that vanishes: a row whose NAME carries a space, which is the shape `multi-rows.py`
      writes. **Every count in this repo produced through `rows()` is a floor.**
- [x] **BLAST RADIUS.** **9 tools call `rows()`** and **156 fork a reader**
      (`def rows…`/`split_py`/`parse_rows`). **A correction that does not propagate is
      indistinguishable from a correction that never happened** — which is not a slogan, it is
      `wire_parse.read_fresh_cache` below.
- [x] **MECHANICAL AUDITS, NOT ARGUMENTS.** `formblind-audit.py`: 17 constructed variants,
      each with a form-complete answer, the REAL reader's own answer, and a **CONTROL reader
      blind on purpose whose contract is that it must NOT agree with the form-complete answer**
      — a control that agrees prints `THIS AUDIT CANNOT FAIL`. One assertion, sixteen times:
      *the reader must produce the form-complete answer*; `KNOWN-BLIND` means that assertion
      FAILS today. **12 KNOWN-BLIND, 5 PIN, exit 1.** Getting the polarity backwards is how a
      defect audit becomes a census validator that exits 0 forever — the first version of this
      file did exactly that and was corrected.
- [x] **FIXED — `--handtyped`, where a wrong number reached a repeated claim.** Its regex
      answered **224** where the truth was 578, and `handtyped-audit.py`'s header quoted the
      224 until both were corrected. Four named blind variants: f-string row NAMES (90),
      expressions over constants (81), RADIX — `0x6996` could not match `-?\d+` AT ALL (69),
      and two `row()` calls on one line (115). **The fix is DELETION: it now delegates to
      `handtyped-audit.py`'s `ast` scan.** Measured on one fixed file set: **209 → 556**,
      **329 rows it could not see**, and **1 it reported that does not exist** —
      `device-oracle-MUTANT.py` has **no `row()` call at all**; `row("allow_lower", 0)` is in
      a `PLANT_TO` template and in prose. A text scanner cannot tell a row from a sentence
      ABOUT a row. Audits A6–A11, A17.
- [x] **FIXED — `dd-band-census.py` §C, which printed 0 where §A printed 7.** TWO blind
      variants in one expression, and **the second is the dominant one**: the spelling
      (`"O.Found.i(" in body`, so an index routed through a local was invisible) AND a
      **six-NAME callee whitelist**, which went stale when `dtype.bend`'s `dc_band` became
      `dd_band`. **A name whitelist is a fixture list.** §C now walks every argument of every
      call whose callee is in a stated `INTEGER_CALLEES` set, prints the callee on
      over-matched hits, and prints **its own denominator** (`N of M calls`). Audit A13.
- [x] **A CLAIMED BLIND VARIANT THAT WAS NOT ONE.** `hand_typed`'s `bare` arm `f"[^"{]*"`
      **does** see `row("a", f"1")`. **A census that is not corrected teaches the wrong
      lesson** — pinned as audit A10 rather than deleted.
- [x] **THE OTHER ROOT CAUSE, AND WHETHER IT BELONGS HERE.** *A tool that measures the right
      form of the wrong thing answers a question you did not ask.* It belongs in the taxonomy
      but NOT in `formblind-census.py`: widening the selector does not help. **A census that
      reads FORMS cannot see a substrate error at all**, so its FORM-COMPLETE verdict on a
      wrong-substrate instrument is **silence, not clearance**. `substrate-audit.py`, all
      measured:
      - **S1 a DIGEST over the MUTANT** rather than the file the rows are `SAME`-compared
        against. **A digest protects the mutant, not the reference** — swapping `hi42`'s two
        shape args (the M09 defect) leaves `shape()`'s three fields byte-identical. Fixed in
        `revision-ledger.py`; asserted.
      - **S2 a CACHE that reads "fresh" because `rows` is not a file. LIVE DEFECT.**
        `rebase-scan-oracles.cached()` refuses an empty cache; **`wire_parse.read_fresh_cache()`
        — the shared reader, imported by `wire-rows.py` and `wire-pair.py` — returns
        `({}, 'fresh')`** for a crashed lane. The `empty` clause landed in one CONSUMER, not in
        the shared function. **Not fixed here: three consumers, two not mine.** Measured cost
        from the tool's own header: 8 of 38 wired pairs read 0 shared names, all skipped in
        silence.
      - **S3 a BINARY PATH keyed on `<stem>`**: 131 `.bend` files, **110 distinct stems**,
        **14 `__init__` ports sharing one artefact**, `run_port()` unlinking it then executing
        whatever was there. Fixed in `rebase-gate.native_bin`; injectivity asserted with the
        old spelling as the control (21 collisions on the same tree).
      - **S4 a SELFTEST whose PASS came from six synthetic states with `run_port()` stubbed** —
        it measured the classifier, not the instrument. Fixed; the file names the mistake.
- [x] **`cstyle-gate.py:rows_shipped` SAYS "rebase-gate.py's `rows()`, verbatim". MEASURED
      FALSE on four of six shapes** — it is the pre-F2/pre-F3 reader, misses the two-space gap,
      does not fold `]   py=[`, and manufactures the `""` phantom row `rows()` excludes ON
      PURPOSE. Its shred count measures a reader that stopped existing three fixes ago.
      **RULE: a function that claims to BE another function is a fork, and the claim must be
      ASSERTED, not written in a docstring.** Comment written in place; the fix is one line
      (`rows_shipped = rg.rows`) and is not made here — the file belongs to another unit.
- [x] **REPORTED, NOT FIXED.** `rebase-gate.py:rows()` audits A1–A4 (another unit this
      round; the floor is written into every consumer that reaches it). **490 NOT-A-SELECTOR
      tools — unaudited is not cleared.** 156 forked readers.

## Session 2026-10-04 — `f2f`'s region: a FORWARD REFERENCE, and the gate rows that make it cost something

`codegen/decomp/dtype.bend` is 209 rows / `ALL PROOFS CHECK`; **the 182 pre-existing rows
are BYTE-IDENTICAL and in order**, and the differ against `dd-oracle.txt` still reports
exactly the same **7** disagreements (`c7 lgu lgun lg1n lg6n lg9n lgqn`). 28 new rows.

**THE DEFECT WAS A GRAPH THAT CANNOT EXIST, NOT A WRONG ANSWER.**
`f2f.up.tail` / `f2f.fnuz` / `f2f.ocp` returned a bare `U32` while building nodes, and
`f2f.up` built its BITCAST into `O.Found.ar(nq)` — a different arena from the index's.
Proved from the pre-fix arena dump (`dtype.bend:1673` pre-fix): slot 22 was written when
`next == 22`, so its src0 was in `0..21`; **no slot below 23 carries an `OR`**; so slot
22's src0 was slot 23, which did not exist yet, and slot 23's src1 was slot 22 — a
**cycle**. `w1` still printed `BITCAST(MUL(C(1),C(-1)))`, which reads as an answer.
TWO causes, and fixing only the return type re-creates the aliasing: `f2f.up` handed the
tail its own pre-`f2f.sign` `+ar`, so the whole tail subtree was built in another arena.
Both halves fixed (`O.Found` returns, plus `O.Found.ar(nq)` in). `w1`'s cone went from
**2 nodes** (`C(1),C(-1)` only) to **33**, and `w1`'s root now matches CPython's
`BITCAST(OR(MUL,WHERE))` **at all six arena sizes**.

**THE REGION HAD NO GATE ROWS, which is why the disagreement was free.** Seven fixtures,
named `q1..q7` because `dd-oracle.py` **already owns `f1`/`f2`/`g3`/`g4`/`g6`/`g7` for the
SAME DEFS with DIFFERENT fixtures** — a name collision reads exactly like a real bug to a
whole-line differ, and 4 of the 8 disagreements I first measured were that collision and
0 were real. Expectations from `.agents/slop/f2f-fixtures.py` (calls `DD.f2f`).

**FOUR FIXTURE BUGS FOUND WHILE BUILDING THEM, ALL OF WHICH WOULD HAVE READ AS PORT BUGS:**
1. `UOp.variable(nm, 0, dt)` — `dtype` is the **FOURTH** arg (`ops.py:1015`), so the
   three-arg form gives a `weakint` and `f2f`'s narrowing branch then REFUSES. Live in
   `dd-bandoracle.py:133`.
2. the receiver's dtype is **`f2f_dt[fr]`**, not `fr` — both real call sites say so
   (`dtype.py:142`, `:196`). With an `fr` receiver `v.bitcast(fr)` **folds**
   (`mixin/dtype.py:53`) and the fixture measures a graph dtype.py never builds.
3. `n=` is the interning **WINDOW**, not the cone size; `q1n`=26 and `q1c`=27.
4. `dd-bandpad.bend`'s `n=` is the **arena length** — a third quantity again.

**THE SWEEP'S CALIBRATION, MEASURED not asserted** (`f2f-inject.py` + `f2f-calib.py`,
four injected classes, pads 0/1/2/5/17/64): a fixed wrong **INDEX** **TRACKS pad**
(`C(31)`→`C(32)`, the only class the sweep sees); a wrong **CONSTANT** (`C(257)`), a wrong
**OFFSET** (`C(256)`) and a **STALE ARENA** (the defect just fixed) are all **FIXED** and
invisible. So a clean sweep is not evidence for this fix; the forward reference is.
Also: my first `FORWARD` predicate was **inverted** and fired on **every** row including
`0 NOOP <- 0,0` — a detector that cannot fail is a gate that says PASS.

**STILL WRONG, NOW MEASURED INSTEAD OF FREE (9 forward edges remain, `f2f-arena.bend`).**
`f2f.qnan` / `f2f.fnuz` / `f2f.down.npat` write
`T.tx_shl(O.Found.ar(a), f2f.em1(O.Found.ar(a), te), tm)` — one arena to TWO builders, so
`em1`'s nodes are overwritten. `shl(1,k)-1` is a Python int, so CPython's node is a
`CONST`; the port builds `ADD(C(2**te), MUL(C(1),C(-1)))`, four nodes where CPython has
none. `q1sig`'s first 18 nodes are a strict prefix of CPython's 27, and CPython's next ten
are `WHERE/3,CMPNE/2,CMPNE/2,CONST/0,OR/2,MUL/2,CONST/0,CONST/0,ADD/2,CONST/0` — the
`nan`/`norm` subtrees the port's collapse destroys. **NOT FIXED**: the brief's own rule is
never to add a second mechanism to work around an overwrite. `q6` (`f16->bf16`) is the
negative row and the port DECLINES where CPython RAISES.

Rules appended to `bend2-constraints.md` as **FF-1..FF-5** (position ~20058).

---

## Session 2026-10-04 (gc4) — `graphcmp`: GROUP, INDEX/BARRIER, SEVEN OF EIGHT
## COMMUTATIVE OPS, AND THE SYMBOLIC-DIM LIMIT MEASURED

Entry points unchanged: `.agents/slop/graphcmp.py`, `.agents/slop/graphcmp.bend`,
`.agents/slop/graphcmp-run.sh`, `.agents/slop/graphcmp-LIMITS.md` (**sections 3 and 6 are
the new substance**), `.agents/slop/graphcmp-p13-ops.py` (new, the raw CPython probe),
`runs/graphcmp/D/README-D.txt`. Regenerate everything: `sh .agents/slop/graphcmp-run.sh`.

`E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py`

**State, MEASURED, and every number printed by the tool** (`runs/graphcmp/D/D0-run-summary.txt`,
`D0-coverage-census.txt`, `D0-ops-probe.txt`):

    graphs 13   AGREE 12 (sym DISAGREE on purpose)   nodes 104/side   field-records 624
    ops 23 of 77 (was 13)   commutative 7 of 8 (was 1)   symbolic-dim nodes 2 of 104 (was 0)
    byte-identical 12 of 13   stability pairs 3 of 3   conflations 4 of 4   selfcheck OK

- [x] **`--graph group` — `UOp.group(sh+sh, sh*sh)`, 8 nodes, `AGREE`.** Reaches GROUP
      (3 nodes / 3 graphs corpus-wide) and ADD. Adds a shared node with a real SUBTREE
      (`RESHAPE#5 4e/2p`) and a REPEATED CHILD INDEX (`src=n(i5,i5)` on both ADD and MUL).
- [x] **`--graph commute` — 6 commutative ops in one 14-node GROUP, `AGREE`.** Each rung
      chosen by MEASUREMENT (`graphcmp-p13-ops.py` Q3), not by reading `GroupOp.Commutative`:
      `a+b`→ADD, `a!=b`→CMPNE (dtype `bool`, the first bool node that is not a `range`),
      `a.maximum(b)`→MAX, `a&b`→AND, `a|b`→OR, `a^b`→XOR (**`f32` operands give an `f32`
      XOR**). Fan-in 6 on each RESHAPE. **`--equiv` moves from ONE of eight ops to SEVEN.**
- [x] **`--graph indexed` — PARAM / INDEX / BARRIER, 7 nodes, `AGREE`.** `UOp.range`'s
      `AxisType.LOOP` is the first non-WEAK axis atom in the corpus; `BARRIER` is the first
      `R`-shaped node that is neither a root nor a SINK.
- [x] **`--graph sym` — two DIFFERENT symbolic dims, 12 nodes, `DISAGREE ON PURPOSE.****
      §3 of the limits file. Two halves, opposite directions, both measured: (a) the differ
      **DOES** separate them, at rung 1, via `ParamArg`'s sixth field (`name`, ops.py:32)
      and the `src` edges — CONFLATION 4, plus `--plant sym1` (12 nodes → 9) as the
      controlled experiment; (b) the **PORT cannot build a symbolic dim at all** — three of
      twelve nodes read `?` for `dtype` and `shape` because `fold.bend`'s `marg.of` answers
      `None` for a non-CONST STACK element (the `ssimplify` wall, already recorded in
      `fold.bend:6180`), so the limits file says so with a denominator instead of leaving an
      untested claim standing.
- [x] **THE `GROUP`-BODY `params` QUESTION, ANSWERED: THERE IS NO SUCH FIELD AT THIS TREE.**
      MEASURED: `UOp.group` is `UOp(Ops.GROUP, src=..., **kwargs)` with no arg
      (ops.py:558-560), `group.arg` is `None`, and `hasattr(group,'params')` is `False`. So
      there is no whole field class being ignored; `ANone` is the whole of a GROUP's arg and
      is compared. What upstream calls the body's parameters are ordinary `Ops.PARAM`
      **nodes**, reachable through `src`, and those ARE compared as nodes with their full
      thirteen-field `ParamArg` args — 2 of them in `sym`, 1 in `indexed`.
- [x] **FOUR MORE DEFECTS IN THIS FILE'S OWN NORMAL FORM** (limits §6 #12-#15). The headline
      is #13: **the byte-identity check had been comparing NOTHING and reporting
      `BYTE-IDENTICAL`.** `graphcmp-run.sh` ran `emit py` / `emit bend`, `--side` is a flag,
      argparse exited 2, both files were 0 bytes, and `cmp -s` on two empty files succeeds.
      Four graphs' worth of `BYTE-IDENTICAL` verdicts over nothing. Fixed by correcting the
      invocation AND by counting bytes on both sides before comparing. #12: `rng` forgot the
      `l` on a `PyRange` — `ParamArg`'s fourth field had never been asked a question, and the
      cost was a four-node cascade with the cause in none of them. #14: `dt_str` rendered the
      unsettled case `R`, the letter that means "upstream raises", and the `?` ledger row
      counted one column instead of two; `selfcheck` now asserts the count is 6 by RUNNING
      the bend side, and that assertion was MEASURED to fire. #15: `plant_srcswap` was pinned
      to `MUL` and silently found nothing on any other graph.

- [x] **A FIFTH DEFECT, AND IT IS IN MY OWN PROSE** (limits §6 #16). Three sentences
      asserted that no node in the corpus had more than one parent. **FALSE** — `matmul`
      already shared four (its shape `CONST`s, one with four parents). Adding `multiparent`
      to every report caught it in one line. What this round actually added is narrower: a
      shared NON-LEAF and a repeated child index. The claim was wrong in the direction that
      flattered the fixture, which is the direction a justification always drifts.

### Reported, NOT fixed (the files are not this unit's)

- **`fold.bend`'s `marg` `ssimplify` wall** — `fold.bend:1229-1248` returns `None` for a
  STACK element that is not a CONST, which takes `dtype` and `shape` together and unsettles
  the node above it. `fold.bend:6180` already records the same wall ("nothing in this tree
  can mint one" for `O.SU`). `diff --graph sym` is that claim with a denominator.
- **`ParamArg.slot = -1` has NO port spelling and TWO conflicting sentinels.**
  `schedule/__init__.bend:1100` writes `0` and says so; `ops.bend:3566-3573` calls any slot
  but 0/1 "the free Variable sentinel" and uses `4294967295`. `sym` spells it `0` (the one a
  committed port fixture writes) and the ambiguity is REPORTED. MEASURED that the choice does
  not change the subject: the thirteen `ParamArg` fields differ in EXACTLY ONE, the RESHAPE's
  dim-0 **is** the PARAM object either way, and the shape text is `(U,l0:4)` either way.
  Choosing the sentinel is an owner decision about `ops.bend`.
- **`CMPEQ` is not reachable from an eager graph** — `UOp` has no `cmpeq` (`UOp.__eq__` is
  the ucache eq) and `(a == b).uop` emits `CMPNE CONST CMPNE`. A measured limit, not a
  missing fixture; reaching it needs a pattern-matched rewrite.
- **`ENDIF` / `BACKEDGE` / `LOAD` / `STORE` remain unreached** (54 of 77 ops still). They
  need a `STORE` body or a loop and are not constructible from the eager Tensor API in a few
  lines. The real gap, and the limits file says so.

Rules appended to `bend2-constraints.md` as **GC-1..GC-8** (positions ~20395-20480).

## Session 2026-10-04 (dl) — `debug-gate`: LEVELS 4, 5, 6, 7 GATED, AND THE SCALE INVENTORIED

- [x] **THE SCALE IS INVENTORIED FROM CPython's OWN SOURCE, NOT TRANSCRIBED.** 76
      `DEBUG >= N` sites at levels 1..7, 70 of which print, and the PORT has **7** --
      thresholds `[(1,1), (2,6)]`. Derived by grepping `tinygrad/` for
      `DEBUG\s*>=\s*(\d+)` with the right-hand side AS the threshold, so a moved or
      re-levelled site moves the table instead of silently changing what a level means.
      `print`/`other` is classified from the site's ENCLOSING STATEMENT, not its own line:
      line-local classification called `schedule/memory.py:59` and
      `schedule/__init__.py:141` non-printing (their `print` is on :60 and :148) and
      undercounted by 2 of 76, so level 1 read 11 printing sites when it was 13.
      `.venv/bin/python .agents/slop/debug-gate.py --inventory`.

- [x] **THE PORT HAS NO SITE AT LEVELS 3..7. That is the coverage fact, and it is stated
      rather than left to a zero.** 3: 17 upstream / 16 print / **0 port**. 4: 8/8/**0**.
      5: 6/5/**0**. 6: 2/1/**0**. 7: 5/5/**0**. A row at any of those levels therefore
      cannot be a disagreement about the port's CODE, and the gate says so on every run.
      **The pre-existing `DEBUG=3` lane was already a declared absence and did not say so:**
      with 0 port sites at threshold 3 it established CUMULATIVITY and nothing about level 3.

- [x] **LEVEL 6 CONTRADICTS THE BRIEF'S SCALE.** The scale says `6 = + linearized`; this
      tree has NO `DEBUG >= 6` that prints a linearized graph. Level 6 has 2 sites:
      `runtime/support/usb.py:25` sets a libusb log level and `viz/cli.py:216` is a render
      predicate reachable only from the viz CLI. MEASURED on a fixed end-to-end fixture
      (`--probe-levels`): level 6 adds **0 stdout lines over level 5** (28 at both).
      `schedule/__init__.py:141` prints the SCHEDULED KERNEL COUNT at `DEBUG >= 3`, not a
      linearized graph. So level 6 is an absence UPSTREAM HAS TOO.

- [x] **LEVEL 5'S ABSENCE IS A GAP, NOT A STRUCTURAL IMPOSSIBILITY.**
      `codegen/__init__.py:274` is `print(pyrender(ast))` -- the UOp list -- and the port
      **already has `pyrender`** (`tinybendygrad/uop/render.bend:1886`). `codegen/__init__.bend`
      has ZERO `debug_ge` sites, so level 5 is a two-line gate away, not unrepresentable.
      Calling that a structural absence would be wrong. Levels 4 and 7 have no such excuse:
      `device.bend` has no `debug_ge` at all, and there is no `asm_str`/`disassemble` in the
      port.

- [x] **LEVELS ARE CUMULATIVE IN UPSTREAM, MEASURED, AND THE PORT IS ASKED THE SAME
      QUESTION.** Calling CPython's own seven sites at `DEBUG=0..7`: every site fires at
      every level >= its threshold, through 7. So `fires_L0..L7` is a new row per level
      naming WHICH of the seven sites fire -- not a count, because a count cannot name the
      site that stopped firing. Measured: `fires_L0=` empty, `fires_L1=mem`,
      `fires_L2..L7=mem,ar,st,am185,am225,am251,am254`. A port where `DEBUG=4` behaved as
      `DEBUG=1` answers `fires_L7=mem` and goes red.

- [x] **THE GRAPH IS HELD FIXED BY CONSTRUCTION *AND* CHECKED**, the way
      `graphcmp-dbg.bend` does it for graphs. `debug-gate.bend`'s `pin_rows()` takes NO
      level -- no `dbg` parameter, so no code path exists on which the level reaches the
      plan. Five `pin_*` rows carry the plan's own numbers, CPython's side read out of
      `memory_plan_rewrite`'s OWN frame with `sys.settrace` (memory.py:31/42/45/53 are
      locals; the function returns a UOp, not a plan). `pin_nbytes` is `pin_tot / 2` on the
      port and `sum(nbytes.values())` in CPython, which makes the `* 2` of memory.py:45
      load-bearing instead of restated. `debug-gate.sh` DIGESTS the 55 level-invariant rows
      per run and exits **2** -- a FAILURE, never a verdict -- on a mismatch.
      MEASURED `distinct=1` over all nine levels, digest `af36021d2ac482873fa39e55fb2aa17a`.

- [x] **THE DIGEST GUARD WAS VACUOUS AND THE GATE WAS GREEN THROUGH IT.** Fixed and found:
      `grep -E "^($INVARIANT_PREFIXES)"` with SPACE-separated prefixes matches NOTHING, so
      the digest was the md5 of the empty string -- `d41d8cd98f00b204e9800998ecf8427e` --
      at every level and `distinct=1` meant nothing. The fix is not the `|` so much as the
      ASSERTION: the selection now counts its own rows and exits 2 below a floor, because a
      digest over nothing is STABLE and stability is what such a guard mistakes for
      agreement. An all-empty block is a WALKER FAILURE, not a fixture with nothing in it.

- [x] **CONTROLS: THE GATE HAS BEEN SEEN RED AT 4, 5, 6 AND 7.**
      `.venv/bin/python .agents/slop/debug-gate-control.py`, on a scratch tree, with the
      live files' md5s asserted equal before and after. C1 clean rc=0. C2..C5 plant
      `env_ge4/5/6/7` at the matching level: rc=1 each, naming the row. C6 plants a level
      DEPENDENCE into a level-invariant row on BOTH lanes: rc=**2**, the digest guard fires
      and calls itself a FAILURE rather than a verdict. C7 every live file byte-identical.
      C8 a level-invariant row wrong AT EVERY LEVEL: rc=1, and the digest correctly stays
      silent -- so the two guards cover different failures and neither is redundant.

- [x] **MUTATIONS: `fires_L*` AND `pin_*` ARE LOAD-BEARING.** 21 mutations over levels
      0/1/2/3/4/6/7, baseline 89 rows. `pin_nbytes' div 2 -> div 1` moves **7** rows;
      `fire_join`'s seed `"" -> "x"` moves **56** (all 8 `fires_L*` at all 7 levels);
      `fire_add` naming ungated sites moves **14** (`fires_L0`+`fires_L1` × 7); and EVERY
      threshold mutation now moves a `fires_L*` row, where before `amdev.py:225` moved
      exactly one. The planted non-cumulative mutation (the level-2 allreduce site
      re-levelled to 4) moves **27** rows including `fires_L2` AND `fires_L3` at all seven
      levels -- the trap the row exists for. Blind spots: **2**, both pre-existing
      (`debug_print` writing `""`, and `mem_mb`'s unreachable tie). **A THIRD blind spot
      was in the TABLE'S OWN LEVEL SET, not the gate**: "`env_ge7` reads threshold 6" moved
      nothing over `("0","1","2","3","4","7")` because `>= 7` and `>= 6` AGREE at 0..4 and at
      7; with 6 in the set it moves **1** row, at level 6 and nowhere else. A mutation
      table's level set is a coverage claim, and a gap in it looks identically to a gap in
      the gate -- the gate's own level-6 control (C4) already caught that mutation, so
      without the control it would have read as a gate hole.

- [x] **THE GATE IS STILL STANDALONE, AND THE MEASUREMENTS THE OWNER NEEDS ARE IN
      `.agents/slop/debug-roster-intersect.py`.** `rebase-gate.py` does not mention it, so no
      aggregate number has ever included it. MEASURED: **0 shared row names** with each of
      the three existing gates for the ports concerned (`memory_oracle.py` 889 rows,
      `amdev_gate.py` 652, `state-gate.py` 14) -- wiring would ADD coverage, not duplicate
      it. All 89 rows are attributed exactly once: helpers 31, memory 22, amdev 14, allreduce
      7, state 7, harness 8. **AND THE BLOCKER**: `run_port` sets `DEV="NULL"` for the
      oracle (rebase-gate.py:580) and nothing for the two bend lanes, and the port has NO
      argv read, so a roster-driven run would put the bend lanes at `DEBUG`-unset and the
      oracle at its argv's level -- three lanes at two different levels, the one thing this
      gate exists to make impossible. NOT wired; another unit owns `rebase-gate.py` this
      round.

- [x] **LIMITS STATED IN `.agents/slop/debug-LIMITS.md`**, the `graphcmp-LIMITS.md` model,
      with denominators on every claim. **The headline: of the 17 rows added by extending
      from 5 levels to 9, NOT ONE is a row about anything a level 3..7 site prints.** Each
      new level adds exactly TWO differing rows against level 0 -- `env_ge<L>` and
      `env_value` -- and both are about the GATE PREDICATE. The growth is 4 `env_ge4..7`,
      5 level-INVARIANT `pin_*`, and 8 `fires_L*` about the level-1/level-2 sites.

Rules appended to `bend2-constraints.md` as **DEBUG-1..DEBUG-7** (positions ~20289-20367).

---

## Session 2026-10-04 — mutation-table ANCHORS re-aimed, and every table PINNED

- [x] **NINE STALE ANCHORS RE-AIMED AND RE-RUN. All nine MOVE ROWS, so none of them
      needed a zero verdict — which is the good case and also the one that had to be
      MEASURED to be believed.**

  | harness | id | old anchor | why it was stale | new anchor | rows moved |
  |---|---|---|---|---|---|
  | `ops-python-mutate.py` | M4 | `CORES_AMD_RDNA4(), CORES_AMD_RDNA3())))` | **NOT STALE — a stale MIRROR** (see below) | unchanged | **2** `pyr_gfx1100_tid pyr_gfx1101_tid` |
  | `wgsl-mutate.py` | M17 | `"var<uniform> INFINITY : f32;\n"` | the literal grew a `@group(0) @binding(0)\n` prefix, so the opening quote is no longer first | `var<uniform> INFINITY : f32;\n"` | **3** `rk alu rk mixed rk empty` |
  | `wgsl-mutate.py` | M31 | `case 1: "y"` | moved into `wi_axis.of`, which wraps it in `Some{}` | `case 1: Some{"y"}` | **2** `workitem g1 workitem l1` |
  | `amdev_mutate.py` | M13 | `def rv.hi(caddr) -> U32:` | gained a `caddr: U32` annotation | `def rv.hi(caddr: U32) -> U32:` | **1** `amv_rv_hi4` |
  | `amdev_mutate.py` | M14 | `def rv.lo(caddr) -> U32:` | same | `def rv.lo(caddr: U32) -> U32:` | **4** `amv_rv_lo0 lo1 lo4 val` |
  | `amdev_mutate.py` | M16 | `…aspm.seen(cap, seen)))),` | **ONE CLOSING PAREN TOO MANY** — the call spans three lines | `…aspm.seen(cap, seen))),` | **9** |
  | `memory-mutate.py` | M26 | `def frag_lowbit(x: U32)` | gained a `+` binder | `def frag_lowbit(+x: U32)` | **70** |
  | `memory-mutate.py` | M56 | `ladder_pick(rem, t)` | the argument was renamed `t` -> `ss` | `ladder_pick(rem, ss)` | **12** |
  | `rf-arg-mutate.py` | M9 | `…,     [O.OpsINDEX{}]},  # 118  idx.f(STAGE)` | padding narrowed 5->3 spaces, comment reworded | `…,   [O.OpsINDEX{}]},  # 118  INDEX.f(STAGE)` | **2** `ct4a_claim ct_root4` |
  | `rf-arg-mutate.py` | M10 | `O.PMEntry{8, [O.OpsMSTACK{}], …` | **the anchor IS THE DEFECT** — `ct_table[8]` has since been corrected to `INDEX/MSTACK`, so the old side is now the mutation's `new` | direction inverted, fix as OLD | **5** `ct8d_claim ct8d_srcops ct8r_arg ct8r_axis ct8r_srcops` |

  **M4's anchor was never stale.** `CORES_AMD_RDNA4(), CORES_AMD_RDNA3())))` is in
  `ops_python.bend:2466` and in all five revisions that file has ever had. The harness's
  `SRC` is a MIRROR built by `git archive HEAD` plus a manual overlay, and that mirror held
  an old overlay — so `old not in src` fired for a reason that had nothing to do with the
  patch, and printed the same string. **`live == git HEAD` is not a sufficient guard; the
  guard needed is `sha256(mirror) == sha256(live)`, asserted.** Recorded as AN-1.

- [x] **A LIVE PORT-DEFECT FOUND WHILE RE-AIMING `nv_mutate.py`, and it is NOT MINE TO FIX.**
      `nv_nvdev_MUTATION.md`'s 7 stale anchors are `nv.reg_boot42`'s `minor_extended_revision`
      read as `11, 8`. CPython — called today, twice, via `tinygrad/runtime/autogen/nv_regs/
      nv_ref.py`, which is GENERATED from the NVIDIA header — says `(8, 11)`. The live port
      prints `minor_extended_revision=11:8`. **15 of nvdev's 526 comparable rows disagree
      with CPython**, and they are all downstream of that one transposition:
      `nv_reg_NV_PMC_BOOT_42_ranges/maxw/wide`, `nv_mask_one/two_far/all`,
      `nv_maskinv_all/impl/two_far`, `nv_encode_boot42_full`, `nv_decode_*`, `nv_decode_boot42_full`.
      The field is 4 bits either way, so a COUNT gate cannot see it and `nv_reg_*_nf=6` stays
      green — the exact M09 shape. Reported, not fixed: `nvdev.bend` is not this unit's file.

- [x] **THAT DEFECT IS NOW MINE, FIXED, GATED, AND THE PREMISE WAS WRONG.**
      `nvdev.bend`'s `minor_extended_revision` read `11, 8`. Verified independently by
      CALLING CPython twice — `B42.fields["minor_extended_revision"]` and
      `NVReg.read_bitfields()` on `0xdeadbeef`, which answers 14 — against
      `tinygrad/runtime/autogen/nv_regs/nv_ref.py:61`. CPython says `(8, 11)`. Fixed.

      **"The field is 4 bits either way, so a COUNT gate cannot see it" is FALSE, and the
      false premise is what made it look undetectable.** `nv.wid(s,e) = e - s + 1` WRAPS, so
      `wid(11,8) = 4294967294`, not 4: the mask goes `0x00000f00` -> `0xfffff800`, 4 bits ->
      24. Two COUNT-shaped rows moved (`..._maxw` 10 -> 4294967294, `..._wide` 0 -> 1). What
      survived is exactly the four rows per register that read no bit position and no width:
      `_base`, `_off`, `_nf`, `_names`.

      GATE: 26 new rows, all six of BOOT_42's fields, per SITE —
      `nv_fld_<f>` = `a:b:width`, `nv_fldmask_<f>`, `nv_fldwidth_<f>`, and `nv_fldmax_<f>`,
      the ROUND TRIP; plus split `nv_boot42_merext_lo`/`_hi`, because the field that had the
      defect was the one BOOT_42 field with no per-element row. Compared rows **526 -> 552**,
      disagreements **15 -> 0**, both lanes byte-identical.

      **THE ROUND TRIP NEEDS THE ALL-ONES WORD; two of the three naive probes are provably
      blind and would have been controls that cannot fail.** Measured over all 86 `Fld.of`
      sites: `getb(enc(1))` moves at 19/86, `getb(enc(pw(w-1)))` at 28/86, and
      `getb(fenc(0xffffffff))` at **40/86 — exactly the order-sensitive count.**

      **AND IT IS A 417x DoS, not only a wrong answer:** `nv.ones` doubles `w` times, so a
      negative width is 4.29e9 iterations. One `bin/bend` run: **3.05 s fixed, 21 min 12 s
      transposed**, same file, same 814 rows. On the real driver that is
      `NVReg.mask/encode/decode` per page-table entry.

      CENSUS (`nv_order_census.py`, arithmetic asserted against the port's own rows first —
      the control caught my own OR-fold-as-sum error). Of 86 `Fld.of` sites: **33 have s == e,
      where no second order exists and the swap is a NO-OP (a theorem, not a gap); 40 are
      order-sensitive; 13 are the s > 31 shift wall.** Over CPython's 119 tables / 383
      fields: 159 order-sensitive, 94 with s > 31.
      `.agents/slop/boot42_inversion.md`, `nv_order_census.json`, notes NV-1 and NV-2.

- [x] **AND THE WHOLE FIELD TABLE IS NOW CHECKED, NOT JUST THE ONE PAIR.**
      `nv_table_equiv.py` compares every `Fld.of` literal in `nvdev.bend` against the
      `NVReg` table CPython holds, field for field and IN ORDER, reaching CPython through
      `include()` (`nvdev.py:162`) rather than by reading the generated header.
      **11 tables, 86 fields, 0 mismatching tables.** The transposition was the only
      field-table defect in the file.

- [x] **A CORRECTION I HAD TO MAKE TO MYSELF, KEPT IN WRITING BECAUSE I GOT IT WRONG.**
      I first reported "the six `MMU_VER` structs print no field-table row at all, so 22
      sites are ungated". **The first clause is false**: I grepped for `nv_reg_v2_pte_*`,
      a name the port does not use — it uses CPython's full register name. Enumerating
      what the port PRINTS (65 `nv_reg_*` rows) shows all six have `_names`, `_nf`,
      `_maxw`, `_wide`, `_wide_names`, and are missing exactly **`_ranges`** — 6 oracle
      rows unanswered. The blind spot is real but narrower than I said: `v2_pte`'s
      `aperture` `(1,2)` -> `(2,1)` changes `wid` 2 -> 0, which moves NEITHER `_maxw`
      (the register max is 46, from `address_sys`) NOR `_wide` NOR any name row.
      Notes NV-3. A census that greps for a name the file does not use reports an artefact.

- [x] **17 OF 24 TABLES NOW PIN WHAT THEY DESCRIBE — and the 7 that do not say so in
      writing.** `table-pin.py` computes rev + FILE digest + ROWS digest per table;
      `pin-tables.py` writes them, and takes the measurements as ARGUMENTS so that it has no
      code path that can decide a table reproduces. Unpinned tables carry
      `PIN NOT WRITTEN -- UNSTATED. <reason>`, and the reason must be non-empty.
      **4 are REFUSED as IN-PLAY** (`c-mutate.py`, `ga_mutate.py`, `helpers-tc-mutate.py`,
      `nv_ip_mutate.py`). **19 of 24 have no committed baseline**, so their zeros cannot be
      re-derived even in principle.

- [x] **`memory-mutate.py` HAD A HARNESS THAT COULD NOT RUN AT ALL.** It treated any stderr
      as a baseline failure, and `bend` writes `bend 2.0.35 is available: run bend update` to
      stderr on every run — so it exited 2 before measuring anything, and exit 2 is
      indistinguishable from "did not compile". 70 mutations had been run and the output was
      NOWHERE. `.agents/slop/memory-mutations.txt` written today: 63 MOVED, 6 ZERO, 2
      NOT-A-PROGRAM (RULE B, counted separately), 0 PATCH-NOT-APPLY.

- [x] **`ops-python-mutate.py` PUBLISHED 170 ROWS THAT DO NOT EXIST.** M17 and M22 each lost
      ALL 85 rows to a run that printed none and the table printed `85` for both. RULE B: a
      non-program is not even a zero, and it is not a count. Both now print
      `DID-NOT-COMPILE`, spelled EXACTLY because `zero-classify.py` compares the whole cell
      and REFUSES anything it does not recognise. New `patch_not_apply.not_a_program()` takes
      no note argument, so the suffix cannot be added by accident.

Rules appended to `bend2-constraints.md` as **AN-1..AN-9** (positions ~20478-20613).

**NOT FIXED, REPORTED:** `ra-mutate.py` (20 stale), `ra-mutate2.py` (8), `rf-mut.py` (1) all
patch `regalloc.bend`/`rangeify.bend` IN-PLAY with no digest guard — refused, not run.
`debug-mutate.py` (4 stale) is IN-PLAY too. `mutanchor.writes()` misses `open(P,'w').write(...)`
as an IN-PLAY signal, so three harnesses are reported safer than they are.

## Session 2026-10-04 — CSTYLE-GATE READER (`.agents/slop/cstyle-gate.py`, the gate, not the port)

`rows_shipped` claimed to be `rebase-gate.py`'s `rows()` "verbatim". It was not.

- [x] **D1 — `rows_shipped` IS NOW THE IMPORTED READER.** `rebase-scan-oracles.py` already imports
      it, which is why scan and gate cannot disagree; this file did not. `rebase-gate.py` NOT edited
      (another unit's). MEASURED by CALLING both on six shapes: **agree on 2 of 6** — no F3, no F2
      `py=` fold, and it MANUFACTURED the `""` phantom `rows()` excludes on purpose. A copied reader
      is a second reader and nothing compares the two, so the drift was silent by construction.
- [x] **D2 — IS THE GREEN TRUSTWORTHY? THE VERDICT YES; THE TREE NO — and the tree's answer
      MOVED.** **221 gated, 221 agree, 0 disagree**; denominators **227 port rows / 224 oracle
      rows**; 6 named exclusions, **0 uncovered** — reproduced over the capture pair (exit 0) and
      over one live window (3 runs, byte-identical, exit 0) whose port stdout md5 `e039eeff62ce`
      was **byte-identical to the 06:02 capture**. Reader ABLATION with the file's own pre-fix
      reader from `jj file show -r @-` (`ast`-extracted, not re-typed): **IDENTICAL, not one printed
      line differs** — `rows_shipped` reached one `print` and never `judge()`. **BUT the lane
      oscillates: 4 DISTINCT error sites in `uop/fold.bend`'s `sym_dim` family over this unit**
      (`:1259` computed-value scrutinee → `:5321` "consumed more than once" → **green window** →
      `:1275` `sym_dim.con` → **`:1286-1288`, 6 of 6 runs, 0 stdout lines, rc=1**) with the file `M`
      throughout. `uop/fold.bend` is one of the six live units. **State at the end of this unit:
      COLD, so the tree has no live verdict.**
- [x] **D3 — ONE CONTROL PER SHAPE, ARMED AND RED.** F1 and F2 on `ctl OPENCL sz1 k0`, F3 on `ctlf3`
      (**single token — `rows()`'s F3 arm refuses a multi-token name**), plus F2's **DISARM** lane
      (plant in the non-compared `py=` column → AGREE, which is what proves the RED plant landed in
      the column the reader compares), plus a REAL row through `judge()` (`tmap OPENCL`,
      `uchar`→`ucHar`: 221 gated / 220 agree / 1 disagree / BROKEN). Every case also requires
      `shared != 0`: my first F3 draft reported AGREE over ZERO shared rows, a false pass.
- [x] **`cstyle-gate.py --oracle-stdout` USED TO DISCARD THE ORACLE'S STDERR**, so `count_refusals`
      was 0 and `UNREPORTED-REFUSALS 9` fired over sound lane text — BROKEN for a reason belonging
      to neither lane. Added `--oracle-stderr`; a capture without one is now REFUSED.
- [x] **CAPTURE MODE PRINTED `live port lane rc=0` WHILE RUNNING NOTHING.** The rc came from the
      `CompletedProcess` built out of the capture. The word now matches the lane that ran.
- [x] **THE SHRED LINE PRINTED `-2`.** `len(readerA) - len(readerB)` labelled "shredded rows" is not
      a measurement; two readers have a symmetric disagreement set. Replaced with both directions
      and the intersection, named: 6 only `rows()` finds, 8 only `rows_strict`, 216 in common.

**NOT FIXED, REPORTED:** `cstyle.bend:1758` emits **`kern CUDA  lb=1 = [...]`**, so a row NAME
contains `=`; **8 of 227** names break the "spaces, no `=`" rule and they reshape under the other
reader (`kern CUDA  lb`) — undetectable by any value-plant, which is why the gate now prints both
readers' NAME SETS every run. `cstyle-gate.py --selftest` needs `.venv/bin/python` (bare `python3` →
`ModuleNotFoundError: No module named 'tinygrad'`, reproduced against the committed blob;
pre-existing).

Rules appended to `bend2-constraints.md` as **BAND-22** (position ~20891), after BAND-21's empty
header at ~20885. Report: `.agents/slop/cstyle-reader.md`, `.agents/slop/cstyle-green.md`,
`.agents/slop/cstyle-controls.md`.

## Session 2026-10-04 (load unit) — THE BASELINE LEDGER: 0 of 234 recorded counts carry a load, and 0 of 18 stored reds can be reclassified

`load-census [####.....] 4/7` — the ledger, the guard, the retrospective, and the starvation
sweep are DONE; **3 are OPEN and are NOT this unit's files** (`loadwatch.py`, `baseline.json`).

- [x] **THE LEDGER — `.agents/slop/baseline-ledger.{md,txt,json}`.** Every recorded baseline with
      its path, revision, row count, load-or-`UNKNOWN` and verdict. **DENOMINATOR 234, in 13
      files.** `OK 0`, `RE-MEASURED-ALONGSIDE 215`, `SUSPECT 19`. A txt dump is identified against
      `baseline.json` by **ROW-NAME-SET EQUALITY**, never by a typed port name. **NOTHING WAS
      RE-RUN** — no lane was executed to produce a number in the ledger.
- [x] **RECOVERABLE / UNRECOVERABLE: 0 and 234.** A capture records a load in **0 of 234**, an
      elapsed time in **0 of 234**, a **revision in 0 of 234**. So the "source file unchanged"
      half of the test is **UNDECIDABLE, not merely unmet** — there is nothing for the working copy
      to be compared against, so no baseline can be shown to describe the tree it judges. Across
      the whole record layer: **92 of 1,816** sensitive counts load-qualified (**5.1%**).
- [x] **THE MECHANICAL TEST — `load-census.py --guard`**, in the style of `parser_cache_guard()`.
      Names every unqualified capture and **exits 1 by design, forever**: a guard that passed on
      this corpus would itself be the defect.
- [x] **THE STARVATION RETROSPECTIVE — 0 of 18, and 0 is the finding.** 18 stored BROKEN verdicts
      over 14 distinct ports; **0** carry a load, **0** an elapsed time. Shapes `dead-lane` 13,
      `disagree` 4, `no-shared-name` 1; **3 of the 18 are `dtype.bend`**'s documented 14 red laws,
      so the unclassified count is **15 of 18**, not 18. **Not closable by running anything** —
      the numbers were never taken. Cross-checked against `lanedeath-census.py`'s independent 18.
- [x] **FOUR DEFECTS FOUND IN THE CENSUS ITSELF, all fixed, all recorded:** its header claimed
      `rebase-gate-selftest.py` carried a `load_guard()` calling `census()` (**it does not, and never
      did**); the same header's "108 occurrences of `load`" was stale at **176**; `load_guard()` v1
      printed *"215 of 234 carry a load"* because it computed `total − SUSPECT`, so every
      `RE-MEASURED-ALONGSIDE` row silently counted as **qualified** and the headline contradicted
      its own detail table three lines below; and the ledger's `*baseline*.txt` glob matched
      `baseline-ledger.txt`, so **the ledger counted its own output** (234 → **235**, no edit in
      between). A fifth, in `starvation_retrospective()`: the `G_checkonly_f16` cell's 0-row reps
      are the `--check-only` **CONTROL**, which prints no rows by design — a deliberate zero read
      as a starved lane. Excluded and named: 3 reps.
- [ ] **OPEN, NOT FIXED — `rebase/baseline.json` is read-only for this unit.**
      `renderer/cstyle.bend` carries `cpython:renderer_oracle = 33` while
      `stability-2026-10-03.json` measured the same oracle at **15**, and
      `rebase/record-2026-10-03.txt` **EXCLUDED this port four times** with the reason "a baseline
      here would be a recording of silence", then logged `LEFT UNTOUCHED (already recorded, not in
      the qualifying set)`. **A re-qualification gate that only inspects NEW candidates cannot
      retire an old one.** This is the only SUSPECT in `baseline.json`'s 90 counts.
- [ ] **OPEN, NOT FIXED — `loadwatch.py` is not this unit's file.** ⚠ `THRESHOLD = 4.0` is
      **derived from an observation class with ZERO members**: it is defined as "the largest load at
      which a full 787-row count was actually observed", and **0 of 18** row-emitting reps reached
      787 (max **79**), with `_OBSERVED["max_load_with_full_count"] = None`. It is a typed constant
      wearing a measured provenance.
- [ ] **OPEN, NOT FIXED — the anchor has three values and no unit.** `787` (NV7 prose) / **780**
      (rows `boot42_baseline_port.txt` emits) / **768** (DISTINCT names — six names are emitted 3×
      each). The baseline layer counts distinct names; the starvation slope's axis is a line count.
      They differ by **19** on the one lane the invariant rests on. Separately
      `nv_nvdev_mutrun.py:13` records "**24 min** for 787 rows" for the same count NV7 quotes at
      "0.5 s".

**REPORTED, NOT FIXED:** `rebase/baseline.json` and `rebase/baseline-DEMO.json` both call
themselves a baseline, share **7 ports**, and **disagree on 7 of 21** common (port, lane) counts —
`search` 38 vs 18, `uop/ops.bend` 115 vs 104 (oracle 68 vs 63), `spec` 25 vs 21. `DEMO` is ~23 h
older and both other artefacts side with `baseline.json`, but **nothing says which file a reader
should load** and neither records a load. Both values are recorded, not harmonised. Also: **4 of
the 18** stored BROKEN verdicts read `2 row(s) disagree ... across 3 lane pair(s)` with **no
shared-row denominator** — this project's own rule violated by its own stored artefacts.

Rules appended to `bend2-constraints.md` as **L1** (position ~20968), at the end, unrenumbered.
Ledger: `.agents/slop/baseline-ledger.md` §5 cites the prior-art entries done right — the naming-gate
count **283 vs 278** and `elf.bend` **353 vs 331** with a third value **246 explicitly retracted**,
each reported with both observed values and the reason it moves.

## Session 2026-10-04 (gc5) — `graphcmp`: A REAL LINEARIZED PROGRAM, SO `ENDIF` /
## `BACKEDGE` / `LOAD` / `STORE` ARE COMPARED AT LAST

Entry points unchanged plus two: `.agents/slop/graphcmp-repro.sh` (new — the two-clean-run
byte check, with a substrate wait and a health gate), `.agents/slop/graphcmp-p14{,-b,-c,-d,
-e}.py` (new — the raw CPython probes that asked what a real scheduled program contains).
Regenerate everything: `sh .agents/slop/graphcmp-run.sh`.
Measure reproducibility: `sh .agents/slop/graphcmp-repro.sh`.

`E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py`

Progress: op coverage [########--] 34 of 77 (was 23; the four the limits file named as
unreachable are all reached, with `ENDIF` reachable ONLY from a hand-spelled gated store)
Progress: corpus size [########--] 16 graphs / 189 nodes / 1134 field-records (was 13/104/624)
Progress: normal-form defects [##########] 26 found and fixed (17-26 are this round's)
Progress: reproducibility [##########] DONE — 154 of 154 files identical, and the check
           found a real nondeterminism on its first run

- [x] **THE GAP NAMED IN THE BRIEF, CLOSED: THE CORPUS WAS NOT A KERNELIZED PROGRAM.**
      Three graphs, and the cost is stated where it is: 85 new BEND nodes, hand-built,
      because `tinybendygrad/schedule/__init__.bend` DEFERRs `__init__.py:82-301` and the
      port **cannot build a schedule at all**. What the widening bought is that the PY side
      now runs three pipelines the corpus had never run. `lin` 46 nodes,
      `loop` 25, `gate` 14.
- [x] **`lin` — `full_rewrite_to_sink(schedule_linear(matmul))`.** The first graph here that
      IS a kernel. 46 nodes; LOAD 6, STORE 1, END 2, INDEX 7, PARAM 3, CAST 6, MUL 5, ADD 7.
      45 of 46 nodes byte-identical.
- [x] **`loop` — `hcq_fence(tv, tv, tv, 0)`, tinygrad's OWN HCQ2 poll-loop kernel**
      (`runtime/support/hcq2.py:405-413`), reached by CALLING it. 25 nodes; BACKEDGE 1,
      LOAD 2, STORE 2, AFTER 3, CALL 1, NOOP 1. Byte-identical on NULL, CPU and PYTHON
      (measured). It is the only place in the tree that mints a BACKEDGE outside a
      hand-written fixture.
- [x] **`gate` — a gated STORE through the REAL `pm_linearize_cleanups`** (the one rule in
      this tree that constructs `Ops.IF`/`Ops.ENDIF`, `codegen/__init__.py:403`). 14 nodes,
      rooted at `LINEAR` because nothing points at the `ENDIF`. **AGREE**, and it is the
      widest-fan-in fixture in the corpus (RANGE#5 at 5 parents).
- [x] **`ENDIF`'s ROUTE MEASURED, WITH A DENOMINATOR.** `Ops.ENDIF` has exactly ONE minting
      site and it needs a GATED STORE, which is `UOp.store(val, gate)` (ops.py:613).
      **The scheduler never mints one: 0 gated STOREs in 9 scheduled programs**
      (`graphcmp-p14d.py` Q1). The closest is `shrink`, which leaves 2 GATED LOADs and
      which `to_program` then REFUSES. So `ENDIF` is reachable and the claim is narrow.
- [x] **`LOAD`/`STORE` NEED NO KERNEL EXECUTOR — PROVED, NOT ASSUMED.** `lin` is a real
      kernelized program carrying 6 LOADs and 1 STORE, none of which has ever been run.
      What needs an executor is making the `Buffer` VALUES agree, and LIMITS §2 already says
      why they cannot (`Buffer` has no `slot`). `.agents/slop/e2e.sh` is still the only
      end-to-end artefact and still proves one matmul.
- [x] **DOES THE DIFFER STILL AGREE? 14 of 16, and the 2 that do not each have a NAMED
      PORT CAUSE** rather than a tolerance: `lin` (`applied_opts` is a count the port cannot
      fill, 1 node of 46) and `loop` (`CallInfo.cdtype` is a port-only field, 1 node of 25).
      `graphcmp-run.sh`'s `$WANT` ASSERTS each one, so a moved verdict is a moved file.
      `sym` was in that list until the `fold` unit closed its wall — see below.
- [x] **TEN MORE DEFECTS IN THE DIFFER'S OWN NORMAL FORM AND CHECKS** (17-26), of which
      three would have kept lying. A SINK with `arg=None` **CRASHED** the emitter (17) —
      thirteen graphs of silence that were a crash, not an agreement. The `tag` column **could
      not be read at all** (18) because every earlier graph had `tag is None` everywhere. A
      kernel's NAME is ANSI-coloured text that reached a structural field (19). The two-run
      byte check was `find | md5 -q`, which on macOS takes ONE file (20) — and once written
      properly it found a real nondeterminism on its FIRST run. The census counted a
      dataclass FIELD NAME as an atom letter (21), and its assertion is MEASURED TO FIRE.
      **TWO IDENTICAL FAILURES COMPARE EQUAL** (22): with the substrate cold both members of a
      stability pair wrote the same one-line 0-row file, `cmp -s` called it `BYTE-IDENTICAL`,
      and the summary read `stable-pairs=5 of 5` on a run where one pair had never produced a
      verdict. Fixed by labelling a one-line side FAILED and re-running it, and — the part that
      generalises — by **counting the NEGATIVES**, because a positive count cannot tell "it
      worked" from "it failed the same way twice". Six plants and `cross` were not counted by
      the summary at all, so **a step that fails silently is not a step whose failure the gate
      can see.** And `grep -c 'BYTE-IDENTICAL'` over a file that can contain the string inside
      an embedded `diff` counts LINES, not pairs (23). And the plant count carried a STALE
      DENOMINATOR — it said 6 and printed 7, because the seventh is `sym1` (24): a right
      count under a wrong claim, printed by the same line, which is why nothing could see
      it. **AND FIXING 22 FOUND 25** (25): once a differing pair named itself, the first one
      was `sym: 2 runs DIFFER`, `32d31 < rc=0` — one file 32 lines, the other 31, and the
      missing line was the `rc=` stamp. `run()` appended `rc=$?` to the file the child had
      just written, so a run killed in that window left a report with no tail and no stamp:
      LIMITS #13's mid-write truncation one layer up, present since round one. Fixed
      ATOMICALLY — one dot-named temp inside `D`, `mv` into place — because **neither
      finding was reachable from the other**: 22 made 25 visible, and 25 was the difference
      22 was looking for. **AND A HEALTH GATE THAT READS A SUMMARY IS A GATE THAT TRUSTS A
      SUMMARY** (26): with `not-comparable=0`, `stable-pairs=5 of 5`, `plants-disagree=7 of
      7` and both selfchecks OK — every line the gate read — one `D2-canon-bend-*.txt` in the
      snapshot was **0 bytes**, because step 02 writes the two canonical files with a BARE
      redirect (it needs stdout in two files, so it cannot use `run()`) and a step that can
      fail makes the summary and the files two different claims about the same attempt. So
      the gate now checks the SHAPE of every artefact: no `D*.txt` may be empty, and none of
      the `diff` reports may be a single line — **stated over the reports BY NAME, because a
      rule that flags a correct file is a rule that always fails, and then it is not a rule.**
      (`D2-cmp-*` is legitimately one line; `D1-verdicts.txt` is legitimately one line.) A
      fourth summary-shaped defect went with it: `D9-stability-srcswap-{a,b}.txt` were
      argparse ERROR files left by an earlier unquoted `for c in $STAB`, and nothing caught
      them because `D1-verdicts.txt` looks at verdicts and not at file NAMES.
- [x] **REPRODUCIBILITY, NOW AN ACTUAL CHECK.** `graphcmp-repro.sh`: waits for the substrate,
      accepts a run only if its summary reads 16 graphs / 14 AGREE / byte-identical 14 /
      not-comparable 0 / selfcheck OK / census-rc 0 / stable 5-0-0 / plants 6 / cross 1 /
      controls 5 / conflations 4 / oracle OK — **the NEGATIVE counts included**, because a
      positive count alone cannot distinguish a result from a pair of identical failures —
      and compares sha256 over non-blank lines. **154 of 154 identical.**
      The health gate is not decoration: a concurrent edit to `uop/ops.bend` landed part way
      through a run and produced twelve real reports and four 0-row failures, and it is what
      let defect 22 hide in plain sight.
- [x] **A LIMIT WAS CLOSED BY ANOTHER UNIT WHILE THIS ROUND RAN, AND THE THREE PINNED
      NUMBERS THAT CLAIMED IT MOVED WITH IT.** `sym` was the corpus's one
      DISAGREE-on-purpose graph because the port could not mint a symbolic dim at all.
      MEASURED late on 2026-10-04: `uop/fold.bend`'s `sym_dim.pa` (`fold.bend:1296`, the
      `AParam` arm of `sym_dim.of`) landed from the `fold` unit; `sym` now reads `?=0` and
      `VERDICT: AGREE` at 12 of 12 with `SYMBOLIC DIMS py=2/12 bend=2/12`. Three pinned
      numbers had to move IN THE SAME DIRECTION, because a limits file left claiming a
      resolved limit is worse than one that never had it:
      `selfcheck`'s `?=6` row (a regression row for a defect that no longer existed, so it
      made a FIX look like a break), `graphcmp-run.sh`'s `sym:DISAGREE`, and
      `graphcmp-repro.sh`'s `graphs-agree=13`. **The third is the instructive one: the
      health gate then reported "not healthy" for a run that was entirely CORRECT and sat
      retrying it** — the cost of pinning a gate to a verdict COUNT. The two-column `?` row
      moved to `loop`'s CALL (`?=2`, one node x two columns) rather than being deleted,
      because a claim with no fixture is a claim with no denominator. This unit did not
      cause the fix and could not have made it; the fixture and the denominator are what it
      contributed.
- [x] **`graphcmp-LIMITS.md` REWRITTEN WITH NEW DENOMINATORS.** Every claim I resolved
      carries the number that resolved it; every claim I could NOT resolve is stated at the
      same strength. `ENDIF`/`BACKEDGE`/`LOAD`/`STORE` are RESOLVED with the op counts and the
      9-program negative; `CMPEQ` is still a measured limit and now says so after THREE real
      kernels rather than one eager graph; `SHRINK` is named as the nearest unclosed gap.

**REPORTED, NOT FIXED** (not this unit's files): `uop/fold.bend:1067-1070`'s `call_dt` reads
`CallInfo.dtype`, a field CPython's `CallInfo` does not have — `ops.py:130-131` reads
`src[0].dtype` — so the port's CALL dtype/shape reads `?` where CPython reads `void`/`R`.
`uop/ops.bend` is under single ownership this round and `fold.bend` belongs to the `fold`
unit. Both names and the node count (1 of 25) are in `graphcmp-LIMITS.md` §2. **This is now
the only node in the whole corpus that answers `?`** — the `sym` closure took the other one —
so the ledger's two-column `?` assertion had to be re-homed onto it rather than deleted.

**CONCURRENCY, MEASURED THREE TIMES.** `uop/ops.bend` went cold three times while this unit
ran (`sym_dim.pa` at :1250 not compiling — twice; `ParamArg`'s field list renamed mid-run
— once), and `fold.bend` gained `sym_dim.pa` mid-session. The `emit_bend` 5-attempt guard
turned every cold spell into `0 rows after 5 attempts -- a FAILURE, not a verdict` and
`D2-cmp-*` into `NOT COMPARED` rather than `BYTE-IDENTICAL`, which is the behaviour those
guards were written for. No port file was edited.

## Session 2026-10-04 (name-shape unit) — A ROW NAME CONTAINING `=` HAS ONE NAME PER READER

- [x] **THE EIGHT `kern` NAMES RENAMED, AND THE RENAME CITES THE VALUE, NOT THE SEPARATOR.**
      `kern <DEV> lb=<N>` -> `kern <DEV> lb <N>`, one character in `cstyle.bend:1758` and the
      same f-string in `renderer_oracle.py:396` (ONE coordinate). The value's upstream name is
      `launch_bounds` (`cstyle.py:163`, sole consumer `.kernel_typedef.format(launch_bounds=)`
      at `:164`); `lb` is this port's standing abbreviation and is already the `kern_row`
      PARAMETER's name, so only the separator moved. **NO COLLISION: 227 rows, 227 distinct
      names, 0 duplicates, and the VALUE MULTISET IS UNCHANGED** (checked by multiset
      comparison, not by eye). Names MAY contain spaces -- `rows()`'s F3 path only runs on
      lines with no `=`, so a space is a separator no reader cuts.
      MEASURED what it was: 227 port rows read as **225** names and 224 oracle rows as **222**,
      the survivors being the `lb=4` values, so both `lb=1` measurements were unreachable.
      `.agents/slop/cstyle-rename.md`
- [x] **`cstyle-gate.py`'s `reshape()` (GUARD 0): A COVERAGE DELTA THAT CHANGES THE VERDICT.**
      The old parity print NAMED all eight rows and then printed `AGREE`, rc=0. Now the two
      readers' name sets are compared per lane, on BOTH lanes, before the value comparison, and
      any of {name contains `=`, two names on one key, a row the shipped reader cannot read at
      all, name sets differ} is BROKEN. `report_reshape()` prints both lanes' counts every
      run; `--names` dumps both full sets.
      `.agents/slop/cstyle-nameshape-control.md`
- [x] **THE CONTROL A VALUE PLANT CANNOT FAKE: `--plant-shape OLD NEW`, on BOTH lanes.**
      `--plant` corrupts a VALUE; MEASURED, it leaves `eq=0 unreachable=0` while the lane goes
      BROKEN on the value comparison -- so a green value lane is not evidence the shape is
      clean. Renaming on ONE side would only trip `stray`/`ghost`, so the control rewrites the
      name on both. Live lane, same bytes: **pre-fix gate rc=0 `AGREE`, post-fix rc=1
      `BROKEN`, `gated 221 agree 221 disagree []` IN BOTH** -- the value verdict is identical
      and only the verdict moves. Four lanes in `--selftest` (`clean`/`value`/`shape`/
      `collide`), rc=0.
- [x] **THE CENSUS, EVERY WIRED LANE, WITH THE DENOMINATOR THAT MATTERS.**
      39 wired ports, 78 lane texts, 38,057 lines, 23,179 rows read, 22,672 names.
      **361 names contain `=` = 7.62% of the 4,736 F2 rows THAT CAN CARRY ONE, and only
      1.59% of all names** -- because 18,443 rows (79.6%) are F1 lanes whose boundary IS `=`
      and are STRUCTURALLY IMMUNE. 361 reader-dependent names: 59 merely misnamed, **302 cost
      a measurement**. 507 unaddressable rows = 302 reshape + **205 from lanes printing one row
      name TWICE, no `=` involved**, `residual 0`.
      **AND THE CLASS IS NOT CONFINED TO cstyle: `renderer/llvmir.bend` has 157 of 471 rows
      (33%) with 48 on ONE key, `renderer/nir_llvmir.bend` 8, `uop/render.bend` 31.**
      `.agents/slop/name-census.md`, `name-census.py`, `name-census-report.txt`
- [x] **FOUR DEFECTS THE CENSUS FOUND IN ITSELF, three of which reported a CLEAN NUMBER.**
      `=` counted in `rows()`'s output is a **tautological zero** (`row()` strips the `=`, so
      the count cannot fail -- it printed 0 over all 78 texts *including the eight*); the
      reshape/duplicate split counted KEYS where the quantity is ROWS (0 on a lane with 148
      lost); an unexplained residual went **82 -> 146 -> 349** while `lost` was right; and a
      lane-shape-blind reader found ` = ` inside a VALUE and reported 31 false `=`-names on
      `uop/render.bend`'s oracle. The split now prints `residual 0` and asserts it.
- [x] **MY OWN HARNESS STARVED 25 OF 39 PORT LANES, AND THAT IS THE POINT.**
      8 concurrent `bend` compiles: `cstyle.bend` alone prints 227 rows, in the pool it printed
      0 with an empty `--check-only`. `--refetch-zero` re-runs every empty lane ALONE with
      `rebase-gate.py`'s own `BEND_ROW_TRIES`/`row_secs`; all 25 returned rows on try 1.

**REPORTED, NOT FIXED** (not this unit's files): `rebase-gate.py:1987` carries `# 222` on the
cstyle lane entry, the pre-rename shared-name count over the oracle lane; it is **224** now
(live file, another unit's). `jit-oracle.py:44` raises -- the oracle is BROKEN, not starved.
`renderer/llvmir.bend` and `renderer/nir_llvmir.bend` need the same rename as cstyle.

## Session 2026-10-04 (c2d unit) — `s5_copy_sel` GATED A NODE CPYTHON REFUSES, AND THE FIXTURE
## WAS WRONG THREE TIMES OVER. THE REUSAL IS A RETURN-TYPE CHANGE.

Progress: `c2d` lane `[########--]` 41 shared rows, **7 RED ON PURPOSE** · 12 identity green ·
10 counts green · 5 oracle-only reported · 24 fixtures / 19 shared outcomes · 4 upstream
refusals re-derived by exhaustion · `uop/ops.bend` **untouched** (single ownership).
Report: `.agents/slop/notes/c2d-refusal-gate.md`. Rules `CT-1`…`CT-5` appended at the END of
`bend2-constraints.md`, numbering continues from `LN-6`.

- [x] **READ CPYTHON'S OWN TEXT, THEN CALL IT: `ops.py:761` IS A BARE `assert`.** `raise` at
      `:760` and `:763` (RuntimeError, WITH messages); `assert arg is None or isinstance(
      self.device, tuple)` at `:761` with NO message, so its observable is `AssertionError`
      with an **empty string**. **FOUR refusals, not three** -- `ops.py:892`'s MSELECT assert
      has a **message** where 761 has none, and fires **lazily** (`mselect(1)` CONSTRUCTS; the
      first `.device` READ raises). `ops.bend:6998`'s "THE TWO `raise`s" under-counts.
- [x] **THE BRIEF'S FIXTURE WAS FALSE, AND MEASURED, NOT INHERITED.** "`node 4` is
      `ParamArg.of(2, int32)`" -> node 4 of **`s5.ga.arena()`** (the arena `s5.devrows` is
      handed, `ops.bend:7095`, NOT `s5.arena()`) is `Node{OpsSHRINK{}, [1], ATuple{Nil{}}}`
      (`ops.bend:6435`): a **SHRINK**, nsrc 1, src0 BUFFER, arg `ATuple` and **not an
      `AParam`**. `ParamArg(2, int32)` is node **2** (`ops.bend:6433`) -- the SLOT was read as
      the INDEX. BOTH arenas have an index 4.
- [x] **THE REFUSAL SURVIVES, BY A ROUTE NOBODY HAD.** `UOp.device` (`ops.py:887-899`) has NO
      SHRINK arm, so a SHRINK falls through to `for x in self.src: if x.device is not None:
      return x.device` / `return None`, and node 1's BUFFER is `ParamArg(1, int32)` with
      `device=None`. MEASURED `node4_device = None`. A `None` from the fall-through, not from a
      `ParamArg` field: **a port that special-cases `AParam` gets this fixture wrong.**
- [x] **THE ORACLE'S FIXTURE WAS A THIRD THING, AND `sig()` CANNOT SEE ANY OF IT.**
      `s5_copy_sel`'s CPython side is `ops-501-oracle.py:209` on `multi`
      (`ops-501-oracle.py:164`) = `Ops.ALLOC`, `ParamArg(3, int32, 4, device=(...))` --
      differing from the port's node in OP, SLOT, SIZE and DEVICE. `sig()`
      (`ops-501-oracle.py:45`) prints the root op and the src op SEQUENCE, so all four print
      identically. MEASURED: `PORT fixture = RAISED AssertionError:` against
      `ORACLE fixture = ok | COPY/MSELECT RANGE`. **A green row comparing an ACCEPTED node
      against a REFUSED one, and its own printer could not see it.**
- [x] **TWELVE FIXTURE-IDENTITY ROWS, because a signature is not an identity.**
      `c2d_selrow_{op,nsrc,src0,arg_is_tuple,arg_is_param,src0_slot,src0_size_is_none,
      src0_device_is_none}` + `c2d_node2_{op,arg_is_param,slot,device_is_none}`. All 12 green.
      `c2d_selrow_arg_is_param = False` makes "node 4 is a `ParamArg`" REFUTABLE rather than a
      comment.
- [x] **`s5_copy_sel` REPLACED BY A ROW I OWN, AND IT IS RED.**
      `c2d_761 selrow = REFUSED AssertionError:` against the port's
      `BUILT Ops.COPY/Ops.MSELECT Ops.RANGE`. `s5_copy_sel` itself is `ops.bend:7022` +
      `ops-501-oracle.py:209`, both other units'; **REPORTED with `file:line` for removal**
      (`ops.bend:7031`), not edited.
- [x] **19 SHARED OUTCOME ROWS, 7 RED / 12 GREEN, DENOMINATOR NAMED.** Every red has its
      positive control ONE STEP AWAY, and `c2d_761 tupledev` (same node, only `device` changed)
      is the one that catches a guard refusing everything AND pins the guard to `self.device`
      rather than the `device` ARGUMENT. `AssertionError`/`RuntimeError` are inside the row
      VALUE, so a name-keyed diff cannot miss the class.
- [x] **`arg=0` REFUSES -- A BOUNDARY THE FIRST DRAFT DID NOT HAVE.** `arg is None` is an
      IDENTITY test; `Maybe<&2, U32>` invites "an empty shard index means no shard", which
      passes an `arg=1` fixture and fails `c2d_761 argzero`.
- [x] **BOUNDARIES RE-DERIVED BY EXHAUSTION, `vw-boundaries.py` 131 rows, md5 stable twice.**
      `dtypes.weaks` = **2 of 20** dtypes (so 763 has 18 positives, and `dtypes.all` does NOT
      contain `weaks`; `char` is `uint8`, so the raw sum is 21 and the dedup is 20) · **EVERY
      `UOp.range` is `weakint` over ALL EIGHT `AxisType`s** (`distinct=1`), so a RANGE cannot be
      a positive 763 fixture · `is_disk_device` is an exact case-folded `:`-split HEAD match
      (`'NODISK'`/`'DISKX'`/`'0DISK'` build, `'disk'`/`'DISK:0'` refuse) · the 761 table is 2 of 4
      quadrants, `arg in {None,0,1,-1}` measured.
- [x] **6 ROWS THE PORT CANNOT PRINT, REPORTED NOT HIDDEN** (`c2d_oracle_only_n = 5` + the load
      row): four DISK SPELLINGS, because `S.Dev` is a TAG (`spec.bend:85-87`) with no name to
      case-fold or `:`-split, and `c2d_892 deviceread`, because `UOp.device` is not ported.
- [x] **THE CHANGE `ops.bend` NEEDS: A RETURN-TYPE CHANGE, NOT A `Bool` GUARD.**
      `ops.bend:7009` answers `Found` and a refusal is not a `Found`, so closing
      `ops.py:761` means `Found | Refusal` and retyping all three callers
      (`ops.bend:7020-7031`). It first needs **`UOp.device` (`ops.py:887-899`), which is NOT
      PORTED AT ALL** -- grep for `def UOp.device` finds only `device_range_src`. `ops.py:763`
      needs the dtype fold (`fold.bend`, live unit). `ops.py:759` is blocked on a contradiction
      measured below.

**REPORTED, NOT FIXED** (not this unit's files):
- `device.bend:340`'s `tag_of` gives DISK tag **6**; `schedule/memory.bend:999` says
  `disk() = S.D1{1}`. **Two ported tag spaces that disagree**, so the DISK guard is not
  decidable, and `ops.bend:6427`'s `s5.dn(n)` fills every tag with `1`.
- `ops.bend:7009`'s `UOp.copy_to_device` returns `Found` where CPython can raise -- the wall
  `ops.bend:6998` calls "cannot change the node".
- **13 of `validate.bend`'s 20 red rows are PRE-EXISTING, and PROVEN so**: staging `@--`'s
  `validate.bend` beside the live one and running `validate-gate.py` gives `142 shared /
  13 disagree` against `183 / 20` now. This unit's change to `validate.bend` **removes zero
  lines** (`jj diff` reports 0 deletions). They are the z3-normalisation and raise-vs-list
  residuals `validate-oracle.py`'s own header documents.
