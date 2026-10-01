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
| P5 | `codegen/` `renderer/` | 30 | [##.......] 5/30 |
| P6 | `runtime/` | 36 | [..........] 2/36 |
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
- [x] `renderer/wgsl.bend` — `tinygrad/renderer/wgsl.py`. 1062 lines, 168 string-diff
      rows, `ALL PROOFS CHECK` (`eb020720`). `is_packed` shipped with its third clause
      INVERTED, so the entire packed path was dead code while 100+ rows stayed green;
      the 40 `is_packed`/`buf_map` rows exist because of that finding. Two rows differ
      and are left printing (the f64 nan mask and threshold — a U32 cannot hold either,
      and neither is reachable from a WGSLRenderer).
- [x] `codegen/{kernel,rewriter}.bend` — 2105 lines, 70 rows diffed against a Python
      oracle, `ALL PROOFS CHECK` (`e68fcedc`). **The Python files named in the brief
      do not exist in this fork**: `codegen/` is a package, `codegen/__init__.py` (518
      lines) IS the kernel, and the lowerer is split across `simplify.py`,
      `late/coalesce.py` and `gpudims.py`. The oracle found three real bugs (a `ctx[0]-1`
      off-by-one, the INS dispatch, `ab_miss` reading a count instead of a bool), and
      the one real finding in the PYTHON: `pm_to_program` rule 3 is unreachable because
      rule 2's unconstrained `LINEAR` arm shadows it.
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
      three-lane gate here: **25 shared rows, CPython == interpreted == native**. Four
      walls named at their Python lines, and two substrate defects ROUTED AROUND
      rather than fixed: `fold.bend:1621` defers a PERMUTEs dtype (so the 2-D dot
      prints 11 nodes against CPythons 15, recorded as `unverified_lin2`), and
      `mixin/op.bend`'s `mo_permute` builds in `Tensor.ar(t)` then wraps in that same
      arena, landing the PERMUTE one node short of the `AOrder` tuple. Both are filed
      under the fold wall rather than worked around silently.

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
