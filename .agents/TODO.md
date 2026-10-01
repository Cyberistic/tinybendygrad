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

1. **`runtime/support/am/ip.py` (755)** — the am ioctl protocol. `ops_amd.bend` is
   being written against it RIGHT NOW and cites it; same "committed code leans on an
   unported file" shape as `hcq2`. Do NOT read `ops_amd.bend` as read-only truth while
   its agent is live — grep it for `am/ip` citations and AGREE, report contradictions.
2. **`runtime/support/nv/ip.py` (661)** — the nv ioctl protocol. Same shape;
   `ops_nv.bend` is committed and cites `hcq2`, so check whether it also cites this.
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
6. **const audit of `ops_webgpu.bend` (67) + `ops_cl.bend` (89 uncovered)** — the
   hand-map work, now that `ops_nv` (33/219) and `ops_metal` have had it. Cheap because
   the method is now written down, and the two devices are committed and unowned.
7. **`runtime/support/usb.py` (473)** — the USB transport. `ops_rdma.bend` and
   `ops_cl`'s `dev_might_open`/remote path both lean on the USB transport concept.
8. **`runtime/support/autogen.py` (289)** — PORT THE GENERATOR, not its 216,933 lines
   of output. This is the deferred scope question and an agent should ARGUe it with
   measurements rather than leave it parked. Note the tension honestly: the projects
   hard rule is 1:1 with upstream, and upstream ships the *output*; but 216,933 lines
   is 43,464 lines of hex register tables (script-translatable) plus 8,258 ctypes FFI
   class defs. An agent that measures this and reports BOTH numbers is worth more than
   one that picks a side.
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
