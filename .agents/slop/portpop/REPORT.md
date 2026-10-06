# Port Population Census Reconciliation

**Measured 2026-10-06 17:00 UTC**. All commands use `.venv/bin/python` for portability.

---

## 1. The Four Numbers and Their Rules

### Number 1: `138` = `find tinybendygrad -name '*.bend'`

**Rule:** Suffix filter `.bend` on the port directory only.

This is the port's own `.bend` source files. It excludes all non-`.bend` files anywhere in the tree, and excludes `.bend` files outside `tinybendygrad/`.

### Number 2: `2459` (now `2463` on disk) = `find . -name '*.bend'`

**Rule:** Suffix filter `.bend` on the entire repo.

This counts every `.bend` file under the root, including `references/` (a gitignored clone of upstream bend tests — 1,616 files), `.agents/slop/` (agent scratch — 679 files, 347 tracked), `gates/`, `checks/`, `oracles/`, `langs/`, `examples/`, plus the port's own 138. The `2459→2463` drift is new untracked files appearing on disk (1 in `gates/`, others in gitignored directories).

### Number 3: `138` = what `checks/substrate.py` runs `bend` on

**Rule:** `os.walk(tinybendygrad)` + `POP_SUFFIXES = (".bend", ".c", ".js", ".mjs")` — 144 total. The `.c`/`.js`/`.mjs` files (6) go through different instruments (`cc`, `node`). The `138` is the `bend=` count: the files `instrument_for()` routes to `bend`.

### Number 4: `2459` (now `2463`) = "A walk returns 2459" — a prior unit's claim

**Claimed rule:** `os.walk` of `.` with no suffix filter.

**But an unfiltered `os.walk` of `.` (excluding `.git`) returns ≈44,099 files.** The `2459` the prior unit cited is `find . -name '*.bend'` — a **suffix-filtered** walk, not a full walk. The claim conflated "a walk" with "a suffix-filtered walk."

| # | Value | Rule | Current |
|---|---|---|---|
| 1 | 138 | `tinybendygrad/**/*.bend` | 138 — stable |
| 2 | 2459 | `find . -name '*.bend'` | 2463 — drifted (+4) |
| 3 | 138 | `substrate.discover()` bend-instrumented count | 144 total, 138 `.bend` |
| 4 | 2459 | "walk returns" (actually suffix-filtered walk) | 2463 — was a misnamed census |

---

## 2. Port Population Under Both Rules

### Rule A: `.bend`-suffixed only — 138 files

```text
 11 tinybendygrad
  3 tinybendygrad/LAWS
  5 tinybendygrad/codegen
  5 tinybendygrad/codegen/decomp
  5 tinybendygrad/codegen/late
  4 tinybendygrad/codegen/opt
  4 tinybendygrad/engine
  9 tinybendygrad/mixin
  6 tinybendygrad/nn
  9 tinybendygrad/renderer
  4 tinybendygrad/renderer/amd
  1 tinybendygrad/renderer/isa
 23 tinybendygrad/runtime
  1 tinybendygrad/runtime/autogen
 18 tinybendygrad/runtime/support
  3 tinybendygrad/runtime/support/am
  2 tinybendygrad/runtime/support/nv
  1 tinybendygrad/runtime/support/rdma
  7 tinybendygrad/schedule
  1 tinybendygrad/test
  1 tinybendygrad/test/_probe
 12 tinybendygrad/uop
  3 tinybendygrad/viz
TOTAL .bend: 138
```

### Rule B: Full `os.walk` (no suffix filter) — 152 files

Same as above plus 14 non-`.bend` files (the "DELTA" set).

### The Delta: 14 files invisible to Rule A

| File | Size (bytes) | Lines | Tracked? | Read by |
|---|---|---|---|---|
| `uop/ops.staged-blob-36145` | 286,404 | 6,297 | TRACKED | (no census) |
| `uop/ops.staged-blob-64022` | 287,092 | 6,306 | TRACKED | (no census) |
| `uop/ops.staged-blob-66397` | 286,321 | 6,297 | TRACKED | (no census) |
| `uop/ops.staged-blob-97648` | 287,092 | 6,306 | TRACKED | (no census) |
| `runtime/support/memory.staged-mem-40079` | 153,558 | 2,634 | TRACKED | (no census) |
| `runtime/support/memory.staged-mem-68409` | 153,558 | 2,634 | TRACKED | (no census) |
| `runtime/support/memory.staged-mem-98861` | 153,558 | 2,634 | TRACKED | (no census) |
| `runtime/support/elf.bend.mut` | 255,934 | 3,433 | TRACKED | (no census) |
| `runtime/dtype.c` | 14,348 | 328 | TRACKED | `substrate.py`, `abi_gate.py`, `wallcheck.py` |
| `runtime/dtype.js` | 8,884 | 211 | TRACKED | `abi_gate.py`, `gate.py` |
| `runtime/sz.c` | 4,343 | 119 | TRACKED | (no census) |
| `runtime/sz.js` | 950 | 32 | TRACKED | (no census) |
| `runtime/webgpu_call.js` | 28,271 | 502 | TRACKED | `e2e.py`, `e2e.sh` |
| `runtime/webgpu_call.mjs` | 277,775 | 6,963 | TRACKED | `webgpu_call.bend` (imports it) |
| **TOTAL** | **~2.80 MB** | **44,696** | 14/14 tracked | |

**Key finding:** The 4 `ops.staged-blob-*` files (25,206 lines total) and the 3 `memory.staged-mem-*` files (7,902 lines total) and `elf.bend.mut` (3,433 lines) are ALL valid bend code — they start with `#` comments, have `def`/`type`/`law` blocks, and would compile through `bend` — but **NO CENSUS READS THEM**. They are invisible to every suffix-based discovery (`*.bend` glob, `POP_SUFFIXES`, `SUFFIXES` set), and no tool in `checks/` or `gates/` references them by path.

**The untracked file:** 1 file is on disk but not in git: `tinybendygrad/test/_probe/v5.bend`. All 14 non-`.bend` files are git-tracked (the staged blobs were committed as part of agent work).

---

## 3. Every Non-`.bend`, Non-`.py` File Under `tinybendygrad/`

See table above. Notable:

- **All 14 are git-tracked.** The 8 `staged-*` and `.mut` files are scratch/work files that survived commits. They are valid bend code without the `.bend` suffix.
- **Only 5 of 14 are referenced by any census tool.** The 4 `dtype.*`/`sz.*`/`webgpu_call.*` files (not `.bend`) are read by various gates. The 4 `ops.staged-blob-*`, 3 `memory.staged-mem-*`, and `elf.bend.mut` have ZERO references in `checks/` or `gates/`.
- **8 files are dead weight in the index** — committed, never read, no suffix-based census can find them.

---

## 4. Volume Ratio

Measured by `.venv/bin/python` reading every line:

| Measure | Port (`.bend` only) | Pin (`tinygrad/**.py` excl `test/`) | Ratio |
|---|---|---|---|
| Non-comment lines | 94,777 | 235,885 | **40.2%** |
| Total lines | 204,513 | 243,515 | 84.0% |

The claimed **41%** is within measurement variance (comment-detection methodology; different runs landed 40.2%–41.9%).

**If the 14 non-`.bend` files are included** (as they would be by a full walk measuring "all port code"):

| Measure | Port (all 152 files) | Pin | Ratio |
|---|---|---|---|
| Non-comment lines | 120,254 | 235,885 | **51.0%** |
| Total lines | 249,185 | 243,515 | **102.3%** |

**The 25,206-line staged-blob quartet alone adds 26.6% to the non-comment count.** If a volume ratio claim includes them, it is measuring scratch copies, not the port.

---

## 5. Census Tools That Walk `tinybendygrad/`

| File | Method | Suffix filter | Sees | Misses |
|---|---|---|---|---|
| `checks/substrate.py` | `os.walk(tinybendygrad)` + `POP_SUFFIXES` | `.bend`, `.c`, `.js`, `.mjs` | 144 | 8 (`staged-*`, `.mut`) |
| `checks/wallcheck.py` | `os.walk` of `WALK_ROOTS` (includes `tinybendygrad`) + `SUFFIXES` set | `.bend`, `.c`, `.js`, `.mjs`, `.py`, `.sh`, `.md`, ... | 144 | 8 (`staged-*`, `.mut`) — `SUFFIXES` excludes them by extension |
| `checks/marker-audit.py` | `rglob('*.bend')` on `tinybendygrad/` | `.bend` only | 138 | 14 (all non-`.bend`) |
| `checks/stage1-census.py` | `glob('tinybendygrad/**/*.bend', recursive=True)` | `.bend` only | 138 | 14 (all non-`.bend`) |
| `checks/no-shrink.py` | `git diff HEAD --numstat -- tinybendygrad/` | Any changed file | Depends on working tree | Committed-only; sees all dirty files including `staged-*` |
| `checks/no-strays.py` | Does NOT walk `tinybendygrad/` | — | N/A | N/A (watches repo root only) |

**Eight files are invisible to every suffix-filtered census** — the 4 `ops.staged-blob-*`, 3 `memory.staged-mem-*`, and `elf.bend.mut`. They are tracked in git but no census reads them.

---

## 6. AGENTS.md Corrections

No AGENTS.md line carries a literal port population count that is in error. The closest:

- Line 71: `"43 of 138 under 50 MB"` — the `138` is correct for the `.bend`-suffix rule on `tinybendygrad/`. No change needed.

The "41%" volume ratio appears in the task prompt, not in AGENTS.md itself. No paste-ready replacement is needed.

---

## Summary

- **Two 138s:** both correct for their respective scopes (`.bend`-only on `tinybendygrad/`).
- **The 2459/2463:** correct for `find . -name '*.bend'` but was misnamed as "a walk returns" — an unfiltered walk of `.` returns 44,099 files.
- **The true delta between suffix and unsuffix:** 14 files (8 of them census-invisible stagers, 5 compiler-assisted files, 1 `.mjs` import target).
- **Volume ratio 40.2%** (not 41%, but within measurement variance).
- **8 committed, tracked files are dead to every census**, holding 36,541 lines of valid bend code that no tool measures.