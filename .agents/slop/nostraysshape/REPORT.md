# `checks/no-strays.py` — the deep scratch shape, measured

Owner: this session's unit. Read-only on everything but `checks/no-strays.py`.
Every number below was produced by a named instrument under `.agents/slop/nostraysshape/`.

Population (discovery, doctrine 1b): `os.walk` over `tinybendygrad/`.
**144 files** (138 `.bend` + 3 `.js` + 2 `.c` + 1 `.mjs`) when this began; **140 now**, because a
concurrent unit deleted four of the strays mid-run (`git status`: `D runtime/zzdiag.bend`,
`D runtime/zzsplit.bend`, `D runtime/support/zz_objc_mutant.bend`,
`D runtime/support/am/ip_scratch_sweep.bend`). Counts are given at **144** (the brief's number) and
re-stated at 140 where they differ.

---

## 1. What the five (six) have in common — MEASURED, `file:line`

| file | bytes / lines | verdict | evidence |
|---|---|---|---|
| `runtime/zzdiag.bend` | 583 / 19 | **PROBE** | `:1 import Base`; `:3 def row(...) -> IO(Unit): IO.print(...)`; `:18 def main() -> IO(Unit): go()`; no port header |
| `runtime/zzread.bend` | 350 / 15 | **PROBE** | `:1 import Base`; `:4 def dd(...)` tests `U32.read`; `:14 def main() -> IO(Unit): go()` |
| `runtime/zzsplit.bend` | 1008 / 26 | **PROBE** | `:1 import Base`; `:25 def main() -> IO(Unit): go()`; prints rows |
| `runtime/support/zz_objc_mutant.bend` | 64412 / 1130 | **MUTANT** | `:1 "# tinybendygrad/runtime/support/objc.bend -- port of tinygrad/runtime/support/objc.py"` — the header names **`objc.bend`**, not itself; name says `_mutant` |
| `runtime/support/am/ip_scratch_sweep.bend` | 152454 / 2792 | **MUTANT** | `:1 "# tinybendygrad/runtime/support/am/ip.bend -- port of tinygrad/runtime/support/am/ip.py"` — names **`ip.bend`**, not itself; name says `_scratch_sweep` |
| `runtime/zzprobe2.bend` | 2611 / 63 | **PROBE** (6th, the brief did not name it) | `:1 "# scratch probe -- DELETE."` — it declares itself |

So: **three probes** print rows and exit; **two mutants** are copies of a real module whose header
names the original; the shape is not `probe`-vs-`mutant`, it is **a scratch token in the name**
(`zz` prefix, or `_mutant` / `_scratch_sweep` / `_diag`).

`zzprobe2.bend` is a **sixth** file with the same shape. `runtime/_p6.bend` (204 B) is a seventh:
tinybendygrad's own scratch regex and `.gitignore` both call it scratch
(`.agents/slop/hygiene-2026-10-04.md:148,166`).

---

## 2. Which candidate SEPARATES them — measured over `tinybendygrad/`

| candidate | fires | of the 5 | false positives |
|---|---|---|---|
| HAS `def main` | 116/138 | 5/5 | 111 |
| NOTHING IMPORTS IT | 97/138 | 5/5 | 92 |
| IMPORTS NOTHING | 35/138 | 4/5 | 31 |
| **ORPHAN** (nothing imports **and** imports nothing) | 32/138 | **4/5** | **28** |
| header names another `.bend` | 63/138 | 2/5 | 61 |
| no self-port header | 78/138 | 5/5 | 73 |
| `zz` prefix | 5/138 | 4/5 | 1 = `zzprobe2` (itself a stray) |
| **scratch token** (`^zz` \| `_mutant`\|`_scratch`\|`_sweep`\|`_diag`) | **6/138** | **5/5** | **1 = `zzprobe2` (itself a stray)** |

**Only the name shape separates: 5/5, and the one "false positive" is `zzprobe2`, which is a sixth
true stray.** Every structural candidate either misses a stray or buries it in real modules.

### THE STRUCTURAL TEST'S 28 FALSE POSITIVES, BY NAME (why it was rejected)

`ORPHAN` fires on 32 files; 28 are **real ports the `.bend` wiring does not reach yet**:
`runtime/support/c.bend`, `runtime/support/objc.bend`, `runtime/support/hcq2.bend`,
`runtime/support/elf.bend`, `runtime/support/system.bend`, `runtime/support/usb.bend`,
`runtime/support/autogen.bend`, `runtime/support/amd.bend`,
`runtime/support/compiler_{amd,cpu,cuda,llvm,mesa,qcom}.bend`,
`runtime/support/compileserver.bend`, `runtime/support/rdma/bnxtdev.bend`,
`runtime/autogen/libclang.bend`, `runtime/ops_nv.bend`, `renderer/amd/generate.bend`,
`engine/worker.bend`, `sz.bend`, `viz/__init__.bend`, and every `__init__.bend` hub
(`__init__`, `codegen/decomp`, `codegen/late`, `codegen/opt`, `engine`, `mixin`, `runtime`,
`runtime/support`, `viz`) and `codegen/decomp/transcendental_f32.bend`.
`runtime/_p6.bend` is also in that list — the structural test cannot tell a stray from a walled
port, which is the whole reason it is not a discriminator.

---

## 3. SHAPE or POPULATION — the decision, and the rule REJECTED

The brief's structural definition — *"a `.bend` file NOTHING imports and that does not import
anything"* — was **measured and rejected**: 28 false positives, named above. The `.bend` port's
import graph is **incomplete by construction** (device backends are walls, `c.bend`/`objc.bend`/
`compiler_*.bend` are written but not wired), so **"unreferenced" is not "not source"** in this
tree. A structural test here would flag the port, not the debris.

The header test was also rejected: 78/138 hits, because header formats vary (`alu.bend --` names no
path; every `__init__.bend` has none).

**So it is a SHAPE, admitted as a regex over the tree (doctrine 1c), and it is the honest answer
rather than a failure to find a population.** The improvement is that the shape is now the shape
the six actually ARE, not the residue arms the first deep version guessed. It also carries the
tree's own scratch rule into the deep lane.

---

## 4. The landed guard, and the two states

`checks/no-strays.py`: `RESIDUE_NAME` → `SCRATCH_SHAPE` (widened), walk scoped to
`SOURCE_TREES = ("tinybendygrad",)`.

```python
SCRATCH_SHAPE = re.compile(
    r"\.staged-(mem|blob)-\d+$|\.mut$|~\d*$|\.(bak|orig|rej|swp)$"   # residue anywhere
    r"|^zz"                                                          # this project's scratch prefix
    r"|(?:_|\.)(mutant|scratch|sweep|diag)(?:\.|_|$)"                # _mutant / _scratch_sweep
    r"|^_[^_]"                                                       # _p6, a lone leading underscore
)
```

Two decisions inside it, both measured:

- **`^\.` and `^_` from `SCRATCH_NAME` are still not reused at depth** — at depth they catch
  `.gitignore` and `__init__.py`.
- **`probe` is deliberately NOT a bare token**: `uop/probe-mmcore.bend` matches a bare `probe`
  and a gate cites it — `.agents/slop/mm-mutate.py:17` names it `SRC`
  (`.agents/slop/hygiene-2026-10-04.md:145,157` records the KEEP). Including `probe` would cost
  that false positive, so it is excluded and this line is why.
- **The walk is scoped to `tinybendygrad/`**: over the whole repo the same regex hits upstream's
  own `test/amd/hw/test_scratch.py`. `test/` is tinygrad's oracle, not this project's source.

### PLANT — two states (`checks/no-strays.py`, live)

```
STATE 1 (plant `runtime/support/zz_plant.bend` present):
  STRAY-SHAPE  tinybendygrad/runtime/_p6.bend          204 B
  STRAY-SHAPE  tinybendygrad/runtime/support/zz_plant.bend  350 B
  STRAY-SHAPE  tinybendygrad/runtime/zzprobe2.bend    2611 B
  STRAY-SHAPE  tinybendygrad/runtime/zzread.bend       350 B
  ... 4 scratch-shaped in source trees          rc=1
STATE 2 (plant removed):
  ... 3 scratch-shaped in source trees          rc=1
```
The plant fired and then stopped firing when removed. (rc stays 1 in state 2 because three real
strays the guard now correctly sees are still on disk.)

---

## 5. Counts — 144 port files, OLD vs NEW, difference BY NAME

At **144 files** (the brief's population, measured before the concurrent deletion):

- **OLD** (`RESIDUE_NAME`): **0 flagged.** Identical to `checks/no-strays.py`'s old output.
- **NEW** (`SCRATCH_SHAPE`): **7 flagged.**
- **Difference (NEW − OLD), by name — 7:**
  - `runtime/zzdiag.bend`
  - `runtime/zzread.bend`
  - `runtime/zzsplit.bend`
  - `runtime/zzprobe2.bend`  ← sixth stray, undeclared by the brief
  - `runtime/support/zz_objc_mutant.bend`
  - `runtime/support/am/ip_scratch_sweep.bend`
  - `runtime/_p6.bend`  ← seventh scratch file, the tree's own rule flags it

At **140 files** (after the concurrent unit deleted four of the five):
`old=0`, `new=3` — `runtime/_p6.bend`, `runtime/zzprobe2.bend`, `runtime/zzread.bend`.

Artifact: `.agents/slop/nostraysshape/counts.rows` (per-file `old_residue`, `new_shape`,
`tree_scratch_re`), regenerable with `.venv/bin/python .agents/slop/nostraysshape/counts.py`.

Sanity cross-check: tinybendygrad's **own** scratch regex (`tree-verdict.py:60`,
`SCRATCH_RE = (^_[^_]|probe|_work|\.mut\.)`) flags only **3** of the six — it misses
`zzdiag`/`zzread`/`zzsplit` and both mutants. The tree's own shape was incomplete too; the new
`SCRATCH_SHAPE` is `tree-SCRATCH_RE`-compatible and closes its three misses.

---

## 6. What stops version four being a fourth shape

- **Rejected by measurement:** the import-graph ORPHAN test (28 named false positives: the port's
  unwired backends) and the no-self-header test (78 hits). Neither is a population.
- **The rule that landed is the tree's own name vocabulary, not mine:** `zz` (this project's
  scratch prefix), `_mutant`/`_scratch`/`_sweep`/`_diag` (residue tokens), plus the tree's own
  `^_[^_]`.
- **Two carve-outs are named with their witness**, not tuned: `probe` excluded for a gate-cited
  file, `test/` excluded because the shape belongs to the tree it was written for.
- **The residual gap is written down, not hidden:** `test/_probe/v5.bend` (25 lines) and
  `uop/probe-mmcore.bend` are probes the shape does not flag — the first because it lives in a
  declared `_probe/` home, the second because a gate cites it. A future revision that widens the
  shape must answer to those two names in this file.
