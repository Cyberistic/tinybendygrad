# BendCover — Port-Op / Corpus-Op Coverage Audit

**Date:** 2026-10-06  
**Task:** Measure the port's `Ops` enum against the pin and the corpus.  
**Pin:** `ad117c928^` = `6c3d401cf324` (the pre-revendor `tinygrad/uop/__init__.py`).  
**Port enum:** `tinybendygrad/uop/ops.bend:169-280` (the `type Op is Data` block).  
**Corpus measurement:** `runs/graphcmp/D/D0-coverage-census.txt:55` ("NOT REACHED (16 of 77)") and `:29` ("61 distinct ops").

## Four populations

| # | Population | Value | Source |
|---|------------|-------|--------|
| 77 | **All enum members** (the total) | 77 | Pin's `Ops(FastEnum)` — 7 `= auto()` lines in `__init__.py` |
| N1 | **Defined by the port** | **77** | `tinybendygrad/uop/ops.bend:169-280` — all 77 constructors present |
| N2 | **Reached by the corpus** | **61** | `D0-coverage-census.txt:55`: 77 op names probed, 16 unreached |
| N3 | **Defined AND reached** | **61** | Every corpus-reached op is also defined by the port |

### The two differences

| Difference | Value | Meaning |
|------------|-------|---------|
| **N1 − N3** | **16** | **Ops the port implements that the 25-graph corpus never exercises** — code with no evidential test coverage |
| **N2 − N3** | **0** | Impossible direction confirmed zero: no corpus-reached op is missing from the port |

## The 16 ops defined by the port but NOT REACHED by the corpus

Every one of these is a real `Ops<NAME>{}` constructor in `ops.bend`. The corpus never produces a node carrying it.

| # | Op | Section | Port line |
|---|-----|---------|-----------|
| 1 | `REWRITE_ERROR` | 2 — non op uops | ops.bend:179 |
| 2 | `PROGRAM` | 2 — non op uops | ops.bend:185 |
| 3 | `SOURCE` | 2 — non op uops | ops.bend:187 |
| 4 | `GETADDR` | 2 — non op uops | ops.bend:197 |
| 5 | `WMMA` | 4 — math | ops.bend:207 |
| 6 | `THREEFRY` | 4 — math | ops.bend:232 |
| 7 | `MULACC` | 4 — math | ops.bend:240 |
| 8 | `CUSTOM` | 5 — control flow / consts / custom | ops.bend:253 |
| 9 | `CUSTOMI` | 5 — control flow / consts / custom | ops.bend:254 |
| 10 | `INS` | 5 — control flow / consts / custom | ops.bend:256 |
| 11 | `STAGE` | 6 — ops not in programs | ops.bend:262 |
| 12 | `MSELECT` | 6 — ops not in programs | ops.bend:264 |
| 13 | `MSTACK` | 6 — ops not in programs | ops.bend:265 |
| 14 | `CUSTOM_FUNCTION` | 6 — ops not in programs | ops.bend:266 |
| 15 | `UNSHARD` | 6 — ops not in programs | ops.bend:274 |
| 16 | `PYLITERAL` | 7 — pattern compiler IR | ops.bend:280 |

**The finding: N1 − N3 = 16.** The `61 of 77` figure commonly cited as "completeness" is actually **the corpus coverage fraction**, not the port completeness fraction. The port defines **all 77** (100%), and `77 − 61 = 16` ops have no corpus exercise.

### Why the 16 are unreached — classification by reason

- **Render/codegen machinery** (never appear in tensor-graph UOps): `PROGRAM`, `SOURCE`, `BINARY` (kernel format wrappers), `CUSTOM`/`CUSTOMI` (inline codegen strings), `INS` (machine instruction), `REWRITE_ERROR` (failure marker).
- **Hardware-specific**: `GETADDR` (HCQ addressing), `WMMA` (tensor-core matmul), `THREEFRY` (transducer — unused in CPU path), `MULACC` (fused multiply-accumulate).
- **Buffer/state ops** (scheduler-only, not in graph): `STAGE`, `MSELECT`, `MSTACK`, `CUSTOM_FUNCTION`.
- **Port-only but corpus exercises the pin tree** (CPython runs, not Bend): `UNSHARD` — a movement op that the corpus's `--graph lin` never emits.
- **Pattern-compiler IR**: `PYLITERAL` — only used in `upat.py` (pattern-matcher compile), not in any graph.

These are not port defects: they are real enum members no upstream graph happens to construct. But they **are** missing both from the port's test coverage and from the upstream test suite's graph coverage for this device.

## Cross-check: port enum vs pin enum

**Verdict: IDENTICAL.**  

- The port's `type Op is Data` block (ops.bend:169–280) declares all 77 constructors in the same sections and the same order as the pin's `class Ops(FastEnum)`.
- `Ops.name.of` ladder (ops.bend:291–367) covers all 77 names.
- `Ops.value` ladder (ops.bend:377–453) assigns values 1–77, matching the pin's `FastEnum` numbering.
- `GroupOp.unary`/`.binary`/`.ternary`/`.defines`/`.irreducible`/`.movement`/`.commutative`/`.associative`/`.idempotent`/`.reduce`/`.comparison`/`.opaque_call_bodies` — all match CPython's `GroupOp` frozensets exactly.

**No member the port has that the pin does not. No member the pin has that the port does not.**

The five `*.staged-blob-*` files in `tinybendygrad/uop/` are copies of `ops.bend` at various edit stages and do not alter the enum; they are excluded from consideration per the task rules.

## Files produced

- `COVERAGE.tsv` — one row per op: op name, section, port-defined (yes), file:line, corpus-reached (yes/no).
- `REPORT.md` — this file.