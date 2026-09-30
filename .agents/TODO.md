# TODO

The port's state. Progress bars are `[###.....] n/m`.

```
spec-as-laws    [#########] 9/9      python-to-bend  [..........] 0/96
proofs          [##.......] 2/32     oracle-green     [..........] 0/1
walkthroughs    [###.....] 3/7
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
- [ ] `uop/ops.bend` — the UOp arena. **The gate: if the arena does not work
      here, the 30k-line plan changes and we say so rather than limping along.**

## Phases P3–P8 — the port

96 handwritten Python files, 25,591 lines by `sz.py`, in dependency order.

| phase | directory | files | status |
| --- | --- | --- | --- |
| P3 | `uop/` | 10 | [..........] 0/10 |
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
- [ ] Whether `Sp` (the spec IR) stays a pure tree with the compilation arena
      separate, or the two are unified. Currently separate, because the
      compilation graph has back-edges and the test suite depends on identity.
- [ ] **The empty-Stack case has no law.** tinyspec plus `Nil{} -> None{}` mean
      an empty Stack has no shape; the stack law covers only the non-empty case.
      Worth its own law.