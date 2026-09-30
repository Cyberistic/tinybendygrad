# Master plan: tinygrad in Bend 2 ("tinybendygrad")

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked

## 0. Ground rules (Bun methodology, applied to Bend 2)

1. **Mechanical port first.** Reproduce tinygrad's *behaviour*, file for file, before
   refactoring toward idiomatic Bend. The port is not an excuse to redesign.
2. **The test suite is the oracle.** tinygrad's tests are Python and pytest-based;
   they are language-independent, exactly like Bun's TypeScript suite. We re-run
   them against the Bend build, unchanged, before we translate any test into
   Bend. *No test is deleted, skipped, or weakened to make the port pass.*
3. **Prep work before code.** `PORTING.md` (Python→Bend pattern map) and
   `LAWS.bend` (tinygrad's `spec/tinyspec.tex` as machine-checked laws) come
   first. Agents read both; they do not re-derive them.
4. **1 implementer + ≥2 adversarial reviewers per unit.** Reviewers only look for
   behavioural divergence from the Python original, missing cases, wrong
   arithmetic, and affinity/ownership bugs. The implementer never reviews itself.
5. **Compiler errors are the work queue.** `bend --check-only` output, grouped by
   file, is the to-do list. Nothing gets stubbed to make a checker happy.
6. **No `git` games.** No `git stash`, no `git reset --hard`. Commit one file at a
   time. No worktrees (disk), no global builds in the middle of a fan-out.
7. **Rejection rule for reviewers**: *if you need a paragraph to justify a
   workaround, the code is wrong — fix the code.* (lifted verbatim from the Bun
   rewrite; it stopped 6,000 lines of hand-waving comments in two days.)

## 1a. HARD RULE: the port stays 1:1 with the original

**A reader who knows tinygrad must be able to read the Bend tree the same way
they read the Python tree.** This is not a style preference; it is the whole
reason the rewrite is reviewable. Concretely, for every `tinygrad/**/*.py`
there is a `bendgrad/tinygrad/**/*.bend` with:

* **the same file split and the same directory layout** — `tinygrad/uop/ops.py`
  becomes `bendgrad/tinygrad/uop/ops.bend`, not something regrouped;
* **the same definitions in the same order**, with the same names where Bend
  allows it (`dt_max_signed`, `Sp.add` → `SpAdd`, `ShapeTracker` → …);
* **the same comments, adapted not rewritten.** Keep the original's `#` comment
  text and its WHY. If the Python says `# the extents here do not intersect,
  we're not in the nonzero region`, the Bend says the same thing in the same
  place. Do not replace upstream's prose with your own;
* **the same upstream caveats quoted**, e.g. `# NOTE: this should be frozen,
  but frozen is slower`, `# NOTE: __eq__ isn't overridden, and means the same
  thing as is by default`. Those notes are the specification;
* **no new abstractions to hide a gap.** Where Bend cannot express something,
  leave a comment saying exactly what the Python did and what Bend does instead
  — do not invent a cleaner design and call it a port.

Refactoring toward idiomatic Bend happens in a **separate, later commit**, the
way Bun did. Phase order in §3 makes P3–P8 pure translation, and a distinct
phase does the idiomatisation.

Exceptions, and only these:

| situation | what to do |
| --- | --- |
| Bend has no `I64`/`F64`/`f16` | keep the Python name; the Bend def carries the width as data and a comment names the C effect that interprets it |
| a Python `RuntimeError` | comment the exact message text; the Bend def is an `IO.die` with that text |
| a Python `None` | comment the sentinel; the Bend type is `Maybe` |
| a Python metaclass / `__getattr__` / operator overload | comment the Python mechanism verbatim, then the Bend encoding. The mechanism note is the most valuable part. |
| the file needs a helper Bend does not have (`List.sum`, `Deque`, `rotl`) | put it in `bendgrad/tinygrad/runtime/` with a comment naming exactly which Python/Bend file needed it |

**A reviewer must reject a diff that is hard to line up against the Python.**
If finding the counterpart of a Python def in the Bend tree takes more than a
minute, the port is off-ratio.


## 1. Bend 2 facts that shape the whole port (measured, not guessed)

| Fact | Consequence for the port |
| --- | --- |
| Affine: every value used **at most once** | tinygrad reuses `x` constantly. Every reuse site needs `+x` in the *pattern*, and the type must be `is Data`. This is the #1 source of port friction and the #1 source of review findings. |
| Only `Nat`, `U32`, `F32` numerics. **No** `I32`/`I64`/`U64`/`F16`/`F64`. | tinygrad's 22 dtypes (incl. `bf16`, `f16`, `i64`, `u64`) are not representable natively. `f16`/`bf16` get a Bend-level software emulation over `U32`; `i64`/`u64` are two `U32` halves. Documented in `PORTING.md §5`. |
| `Array<T>` is a **persistent balanced tree** (`ALeaf`/`ANode`), not a flat buffer | Tensor storage must NOT use `Array`. tinygrad's flat-buffer model is preserved via the C-effect arena (see `PORTING.md §6`). |
| No `if`. Only `match` on a parameter or pattern-bound var. | Python `if` → `match` on a `Bool` parameter. The `bool_adapter` idiom in `PORTING.md §3`. |
| No `match` inside a `do` block; a `match` must head a def body. | Any error handling inside IO needs the "hoist the match, return a `do` block per arm" shape. |
| Termination check is mandatory; recursion must be structurally decreasing. | Almost all tinygrad loops (index arithmetic, fixpoint iteration, graph rewriting) get `@unsafe` on its own line above `def`. The reviewer rule: `@unsafe` is a *budget*, not a licence — flag any new `@unsafe` that is not in `AFFINITY.tsv`. |
| No mutual recursion. | tinygrad's `A ↔ B` def pairs collapse into one `def` with a `Sel` tag argument (documented in `PORTING.md §4`). |
| A closure is callable **once**; only top-level defs are freely callable. | No Python callback objects. Higher-order tinygrad code (`lambda`, `fn` in `Linearizer`) becomes either a template (`~f`) or an explicit `Sel` tag. |
| `do`/`IO` for all effects. | `File`, `Process.run`, `File.*` map 1:1. Everything else is a custom C effect. |
| `bend f.bend` runs interpreted; `bend f.bend -o f` compiles to native C. | We use **native** for anything with real work. The interpreted lane is for tests. |

## 2. Target architecture (mirrors tinygrad's own layering)

```
bendgrad/
  LAWS.bend            <- spec/tinyspec.tex as Bend laws. Read-only to agents.
  PROOF.bend           <- the gate. bend PROOF.bend must print ALL PROOFS CHECK.
  PORTING.md           <- Python→Bend pattern map. The port contract.
  AFFINITY.tsv         <- per-def ownership decisions: affine / +reusable / arena.
  sz.bend / tools/sz   <- Bend's answer to tinygrad's sz.py (token line count).
  tinygrad/
    dtype.bend  shape.bend  helpers.bend
    uop/        ops.bend spec.bend symbolic.bend metadata.bend
    schedule/   prepare.bend rangeify.bind indexing.bend multi.bend
    engine/     realize.bend
    codegen/    index.bend decomp/ opt/ late/ gpudims.bend
    renderer/   cstyle.bend llvmir.bend ...
    runtime/    device.bend  <- C effects: memory, process, compile
    nn/         ...
    mixin/      ...
  test/               <- thin harnesses that run the ORIGINAL pytest suite
```

The split that matters: **everything above `runtime/` is pure Bend and is where
the laws apply.** Everything in `runtime/` is a C effect, because that is
exactly what tinygrad does with ctypes + a C compiler.

## 3. Phases

- **P0 — toolchain & tooling** `[~]`
  Working `bend`; `tools/sz` line counter; `test/` harness that runs the original
  pytest suite against the Bend build; a `bend --check-only` sweep script.
- **P1 — prep documents** `[~]`
  `PORTING.md`, `AFFINITY.tsv`, `LAWS.bend`, `PROOF.bend` skeleton.
- **P2 — trial run** `[ ]`
  3 files end to end (see §5). Gate: all 3 behave identically to Python, and
  `PROOF.bend` passes for their laws.
- **P3 — core front end** `[ ]`
  `helpers`, `dtype`, `shape`, `uop/ops`, `uop/spec`, `uop/symbolic`. The UOp
  arena lands here. Everything downstream depends on it, so it is the slowest,
  most-reviewed phase.
- **P4 — schedule + engine** `[ ]`
- **P5 — codegen + renderer** `[ ]`
- **P6 — runtime (CPU + NULL devices)** `[ ]`
  CPU device compiles with `clang` (not LLVM). NULL device is pure Bend.
- **P7 — tensor / mixin / nn** `[ ]`
- **P8 — llm / viz / renderer isa** `[ ]`
- **P9 — test suite green** `[ ]`
  Every tinygrad test that passes on `CPU` or `NULL` on this machine must pass.
- **P10 — translate the tests into Bend** `[ ]`
  Only starts once P9 is green, per the task brief.

Explicitly **out of scope** (needs hardware we do not have, per the brief):
`tinygrad/runtime/ops_am.py`, `ops_nv.py`, `ops_cuda.py`, `ops_hip.py`,
`ops_metal.py`, `ops_qcom.py`, `ops_dsp.py`, all of `runtime/autogen/`,
`renderer/amd/`, `runtime/support/am/`, `runtime/support/nv/`,
`llm/kernels/amd.py`. These get a documented `not-ported` stub and their tests
are excluded by the *existing* hardware markers, not by us.

## 4. How correctness is measured

The oracle is **tinygrad's own pytest suite, run unchanged**, against the Bend
runtime. Concretely, for each `test/` file that touches only CPU/NULL:

1. `tinygrad/test/...py` drives a small generated Python shim that speaks the
   same API as `tinygrad` but routes every call into the Bend binary over
   stdin/stdout JSON-lines. The shim is *the only* Python we write, and it is
   written once, not per test.
2. A test passes when the shim's output equals the original's.

This is deliberately Bun's trick: **the test suite does not depend on the port's
language.** We never rewrite a test to make it pass; we make the port behave.

## 5. Trial run (P2) — the 3 files, chosen deliberately

| File | Why this one |
| --- | --- |
| `tinygrad/helpers.py` | Mostly dicts/lists/strings/enums. No deps. Teaches the base-library idioms, string building, and `Map` vs `Array`. |
| `tinygrad/dtype.py` | A closed enum + tables + casts. Teaches the U32-indexed-enum encoding and the `match`-instead-of-`switch` cost. |
| `tinygrad/uop/ops.py` (head) | The `UOp` dataclass and the `Ops` enum. This is where the arena decision gets proven or killed. If the arena works here, the port is feasible; if not, stop and re-plan. |

P2 is a real gate. If `uop/ops.py` cannot be represented, the whole 30k-line
plan changes and we say so rather than limping along.

## 6. Agent protocol

Each unit of work = **one Python file** (or one coherent group, ≤400 Python
lines). For each unit, in order:

0. **Implementer reads the whole Python file first.** Every def, every branch,
   every comment. A port written from a summary diverges.
1. **Implementer** writes the `.bend` file 1:1 with it (see §1a), runs
   `bend --check-only`, iterates to zero errors.
2. **Implementer runs a COMPARISON PASS** — this is mandatory, not optional, and
   it is the step that catches most real bugs:
   - Go through the Python file **top to bottom**, def by def, and for each one
     locate its counterpart in the Bend file. If you cannot find it, that is a
     finding: either you dropped it or you renamed it without reason.
   - Produce a written table: `python def` → `bend def` → `verdict`
     (faithful / adapted / **MISSING** / extra).
   - Re-read every Python comment and check the Bend file carries the same
     *information* (see §1a). A dropped `# NOTE:` is a finding.
   - Check every Python edge case survives: `None`, `RuntimeError`, zero divisor,
     negative index, empty input, single-element input, `assert` that documents
     an invariant.
   - **Then FIX every discrepancy you found** and re-run the checker. A
     comparison pass that ends in a report but no fix is a failed pass.
   - Save the table to `.agents/slop/notes/compare/<file>.md` so the reviewers
     start from it rather than from zero.
3. **Reviewer A (behavioural)** — the only job is to find where the `.bend`
   diverges from the `.py`: dropped branch, wrong constant, inverted condition,
   Python's late binding that must be early, silent integer truncation,
   `//` vs `/` vs `%` signedness, aliasing that Python had but Bend does not
   (or vice versa), a `+` that should not be there. Reviews the comparison
   table too, and distrusts any row it cannot verify in the source.
4. **Reviewer B (affinity & memory)** — the only job is to find ownership bugs:
   values consumed twice, missing `+`, `Array` used where a flat buffer is
   meant, a DAG edge silently dropped by an arena reuse, reference counting that
   can leak or double-free, a `@unsafe` that hides a real non-termination.
5. **Fixer** applies the union of findings, re-runs the checker and the
   comparison pass, commits.


Adjudication: if the two reviewers disagree, the finding with a concrete failing
input wins. If neither can produce one, it is dropped and recorded in
`.agents/slop/notes/rejected-findings.md` so we stop re-litigating it.

## 7. Definition of done

- `bend PROOF.bend` → `ALL PROOFS CHECK`.
- `bend --check-only` on every ported file → clean.
- `tools/sz` reports ≥ the Python original's line count per file, and the
  aggregate is in the same ballpark (30k).
- The original pytest suite passes on CPU and NULL.
