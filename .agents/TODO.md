# TODO

The port's state. Progress bars are `[###.....] n/m`.

```
spec-as-laws    [#########] 9/9      python-to-bend  [..........] 0/96
proofs          [###.....] 3/32     oracle-green     [..........] 0/1
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
- [x] `AFFINITY.tsv` — every `@unsafe` and every `+`, with its reason
- [x] `LAWS/spec.bend` — the spec IR and its five derived properties
- [x] `LAWS/alu.bend` — tinyspec's decomposed-elementwise-ops table
- [x] `LAWS.bend` — 32 laws
- [ ] **Audit against tinyspec**: coverage gaps, vacuous laws, stubs
- [x] `PROOF.bend` — shape half: reshape/permute/flip/pad/shrink/stack/detach
      (10/10 proven; 8 shape-column mutations each killed by their own law.
      Re-verify once `LAWS/spec.bend`'s fuel rewrite compiles)
- [x] `PROOF2.bend` — ALU/dtype half (16/16 proven)
- [ ] `PROOF-ALL.bend` green

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

- [ ] **Turing completeness needs approval.** 19 `@unsafe` defs in
      `LAWS/spec.bend` are mutually recursive structural folds over a finite
      tree, so they terminate and are not a while-loop in disguise. But
      `@unsafe` lifts the termination check in general, and the project rule says
      any Turing completeness must be approved first. Awaiting a decision on
      whether the fold group is in bounds; if not, the alternative is an explicit
      fuel argument threaded through every derived property.
- [ ] Whether `Sp` (the spec IR) stays a pure tree with the compilation arena
      separate, or the two are unified. Currently separate, because the
      compilation graph has back-edges and the test suite depends on identity.