# TODO

The port's state. Progress bars are `[###.....] n/m`.

```
spec-as-laws    [#########] 9/9      python-to-bend  [#.........] 1/96  (1 file, 31 defs outstanding)
proofs          [########.] 28/34    oracle-green     [..........] 0/1
walkthroughs    [####....] 4/7
```

---

## Phase P0 — toolchain and scaffolding

- [x] `bin/bend` runs the pinned Bend 2 compiler
- [x] `tools/get-bend.sh` fetches it into `references/`
- [x] `.gitignore` excludes `references/` and native build output
- [x] `.agents/TOOLS.md` tool ledger
- [x] Fork `Cyberistic/tinybendygrad`, master only, remotes set
- [x] `tools/sz` — Bend's answer to `sz.py` (token line count per file)
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
- [ ] `uop/fold.bend` — the derived properties of `ops.py` as ONE Kahn worklist.
      **DONE.** `dt`+`shape` as a pair (they read each other), `device`,
      `addrspace`, `base`, `ended_ranges`, and `axis_id`/`axis_type` (not fold
      properties — the arena already split `ARange{ids, at}`). Both lanes green, no
      `@unsafe`, five rows all True, mutations run both ways. The rest of `ops.py`
      is a `TODO(p3)` line per property with the wall it waits for.
- [ ] `uop/spec.bend` — the SPEC>1 layer `UOpMetaClass.__call__` runs.
- [ ] `uop/symbolic.bend` — `python_alu`, `exec_alu`, `const_factor`, `divides`,
      `gcd`, `divide_exact`, `_min_max`, `_sym_fxn`/`sym_infer`.

## Phases P3–P8 — the port

96 handwritten Python files, 25,591 lines by `sz.py`, in dependency order.

| phase | directory | files | status |
| --- | --- | --- | --- |
| P3 | `uop/` | 10 | [##........] 2/10 |
| P4 | `schedule/` `engine/` | 10 | [..........] 0/10 |
| P5 | `codegen/` `renderer/` | 30 | [..........] 0/30 |
| P6 | `runtime/` | 36 | [..........] 0/36 |
| P7 | `tensor` `mixin/` `nn/` | 15 | [..........] 0/15 |
| P8 | `llm/` `viz/` `function.py` `device.py` | 15 | [..........] 0/15 |

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