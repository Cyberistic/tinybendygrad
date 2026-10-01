# TODO

The port's state. Progress bars are `[###.....] n/m`.

```
spec-as-laws    [#########] 9/9      python-to-bend  [##........] 3/96  (0 defs outstanding)
proofs          [########.] 28/34    oracle-green     [###.......] 3/3
walkthroughs    [######...] 6/7
```

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
- [ ] `tools/check` — one command that runs every `bend --check-only`

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
- [ ] `PROOF-ALL.bend` green

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
      **DONE.** `dt`+`shape` as a pair (they read each other), `device`,
      `addrspace`, `base`, `ended_ranges`, and `axis_id`/`axis_type` (not fold
      properties — the arena already split `ARange{ids, at}`). Both lanes green, no
      `@unsafe`, five rows all True, mutations run both ways. The rest of `ops.py`
      is a `TODO(p3)` line per property with the wall it waits for.
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

## Phases P3–P8 — the port

96 handwritten Python files, 25,591 lines by `sz.py`, in dependency order.

| phase | directory | files | status |
| --- | --- | --- | --- |
| P3 | `uop/` | 10 | [####......] 4/10 |
| P4 | `schedule/` `engine/` | 10 | [#.........] 1/10 |
| P5 | `codegen/` `renderer/` | 30 | [..........] 0/30 |
| P6 | `runtime/` | 36 | [..........] 0/36 |
| P7 | `tensor` `mixin/` `nn/` | 15 | [#.........] 1/15 |
| P8 | `llm/` `viz/` `function.py` `device.py` | 15 | [..........] 0/15 |

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
- [ ] mixin/op.py (1980 lines) + elementwise.py + decomp/transcendental.py + nn/ unported.
