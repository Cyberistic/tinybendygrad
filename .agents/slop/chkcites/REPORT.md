# `chkcites` — every `.bend:<N>` citation in `checks/*.{py,sh,bend}`, resolved

Unit `chkcites`, 2026-10-06. **STATIC-ONLY: `bend` was NOT run.** Python only, `.venv/bin/python`,
no `.txt`, no commit, no `git add`, no `@`. HEAD `b4dc69094` (2026-10-06 15:28:52).

## 0. The count question, answered first

The brief handed me two numbers and asked which is right. **Both are right for their own population,
and neither is the `.bend:<N>` population.**

| source | count | population it walked | what the 9/4 actually are |
|---|---|---|---|
| `citetruth` `2358182ff` (`cites.rows:40-48`) | **9** | `checks/*.py`/`*.sh` prose naming the **port FILE-COUNT** (`138`/`144`) | **NOT line cites.** Nine file-count numbers: `sweep.py:579`, `substrate.py:118,133,548`, `no-strays.py:95,106,133`, `demo.sh:8,25`. No `.bend:<N>` in any of them. |
| `awmma` `REPORT.md` §4 | **4** | `checks/*.py` `.bend:<N>` cites its own `ops.bend` edit shifted | Four cite *locations*: `nl-gate.py:39,40,477` (→ `ops.bend:7837`/`:7874`) and `gates/ops-core-gate.py:12` (→ `ops.bend:5044-5045`). |
| **this unit, by discovery** | **34** | `checks/*.py` + `*.sh` + `*.bend`, regex `<name>.bend:<N>`, resolved against the tree | the real `.bend:<N>` population |

**Union / difference.** `awmma`'s 4 ⊂ my 34 (3 of them inside `checks/`, 1 in `gates/`, which is
outside this unit's write scope). `citetruth`'s 9 ⊄ my 34: they are a **different population** —
file-count prose, not line citations. So they are neither a subset nor a superset; the two
populations are disjoint. **The `.bend:<N>` population is 34, not 9 and not 4.**

**AND `awmma`'s DELTA IS WRONG.** The brief repeats `awmma`'s measured correction *"`ops.bend:7837`/`:7874`
→ now `:7844`/`:7881`; `:5044-5045` → `:5051-5052`"* — a flat `+7`, `awmma`'s own uncommitted edit
at `ops.bend:1635`. But the cites were never a 7-line pointer:
`def vd_text(` is at `ops.bend:8407` today, not `7844`, and `vd_dbg` has **never existed in
`ops.bend` in any commit** (`git log --all -S 'vd_dbg'` over the file: 0 hits). The `5044` region is
the `vmin`/`vmax` three-valued-predicate wall, not a CONST-identity cluster, so `5051-5052` is as
unsupported as `5044-5045`. **A `+7` arithmetic on a cite that had drifted `+575` is the same defect
one level up.**

## 1. Population by DISCOVERY

`checks/*.py` (62) + `checks/*.sh` (17) + `checks/*.bend` (3) = 82 files walked by `os.walk`
(`.agents/slop/chkcites/scan.py`), every line matched for `(?P<ref>[A-Za-z0-9_./-]+\.bend):(?P<num>\d+)`,
each `<ref>` resolved by basename walk under `tinybendygrad/` (and `checks/`, `.agents/slop/` for
`ag-emit.bend`). **34 citations across 14 files:**

```
12  checks/rn-gate.py       3  checks/run-port-mm.sh    1  checks/unowned.py
 6  checks/nl-gate.py       3  checks/nvrows-deadrow-gate.py  1 checks/stage1-census.py
 3  checks/run-port-mm.sh   1  checks/run-f64.sh        1  checks/gate_norm.py
 1  checks/env-precond.py   1  checks/e2e.sh            1  checks/e2e.py
 1  checks/disagree-gate.py 1  checks/differ.py         1  checks/abi_gate.py
```

No cite uses a looser form (`<name>.bend : N`, or a bare `:N` carrying a prior filename on the line):
checked with two wider regexes, 0 hits. `checks/*.bend` (`gate.bend` 370 lines, `gate_dtype.bend` 76,
`gate_norm.bend` 60) contain **0** `.bend:<N>` cites.

## 2. The table — every cite, its reading, its disposition

Legend: **OK** token present at the cited line · **DRIFT** file exists, token is elsewhere ·
**DELETED** the target content was removed from the file · **LIVE** target file under live edit
(`tinybendygrad/uop/{ops,fold,render}.bend`) → **report only** · **NARR** a narrative line, no
resolvable token.

### (a) RESOLVES — 11 (10 before the one correction, +1 corrected)

| `check:line` | cite | token expected | actual | note |
|---|---|---|---|---|
| `abi_gate.py:94` | `dtype.bend:1064` | `def Dt.i64_trunc` | `1064` = `def Dt.i64_trunc(x: H.I64) -> H.I64:` | OK |
| `env-precond.py:48` | `helpers.bend:308,342-345` | DEBUG, NO_COLOR, DEFAULT_FLOAT, DEFAULT_INT, SUM_DTYPE | `308` `getenv_int("DEBUG",0)`; `342-345` `NO_COLOR/DEFAULT_FLOAT/DEFAULT_INT/SUM_DTYPE` | OK, all five |
| `gate_norm.py:242` | `tinybendygrad/base.bend:42` | the NaN-payload measurement | `42` = `from_bits(0xFFC00001) reads back 0xFFC00001` (section `38-48`) | OK |
| `nl-gate.py:16` | `nir_llvmir.bend:125` | `String.concat([nm, " = ["…` | `125` = exactly that | OK |
| `nl-gate.py:91` | `nir_llvmir.bend:125` | same | same | OK |
| `nvrows-deadrow-gate.py:95` | `ip.bend:371` | an import resolving package-relative | `runtime/support/nv/ip.bend:371` = `import Base` (the `am/` twin is blank at 371) | OK — resolves to the **nv** file |
| `nvrows-deadrow-gate.py:96` | `LAWS/spec.bend:48` | `import Base` | `48` = `import Base` | OK |
| `nvrows-deadrow-gate.py:213` | `nvdev.bend:1770` | `def emit(xs: List<&2, String>)` | `1770` = exactly that | OK |
| `run-port-mm.sh:27` | `cstyle.bend:49` | the `Ops.SHRINK`-has-no-dtype note | `49` names `Ops.SHRINK` | OK |
| `unowned.py:66` | `ag-emit.bend:32` | the quoted `bend2-constraints.md` path | `.agents/slop/ag-emit.bend:32` = exactly that | OK (file is under `.agents/slop/`, not `checks/`) |
| **`stage1-census.py:204`** | **`elementwise.bend:543-544`** | `ew_mul`/`ew_add` | **`542`=ew_add, `543`=ew_mul** | **CORRECTED → `542-543`; re-resolved** |

### (b) DRIFT / DELETED / NARRATIVE — 23

| `check:line` | cite | token expected | actual number | disposition | edit that moved it |
|---|---|---|---|---|---|
| `nl-gate.py:39` | `ops.bend:7837` | `vd_text` | **8407** | DRIFT **LIVE ops.bend** | cumulative growth; matched at `8fc031b5b` (vd_text=7832); now +575 |
| `nl-gate.py:477` | `ops.bend:7837` | `vd_text` | **8407** | DRIFT **LIVE** | same |
| `nl-gate.py:40` | `ops.bend:7874` | `vd_dbg.of` | **no such token** | **token NEVER EXISTED in `ops.bend`** **LIVE** | 0 hits in every commit of `ops.bend` (`git log --all -S`); tree-wide `rg` finds it only in the `checks/` prose that cites it |
| `nl-gate.py:477` | `ops.bend:7874` | `vd_dbg.of` | **no such token, ever** | same **LIVE** | same |
| `disagree-gate.py:93` | `ops.bend:1057` | `CustomFunction.dtype` field (`ops.py:1398`) | record at **1075** (`name` bullet 1057, `dtype` bullet 1060) | DRIFT **LIVE** | `777fa2edf` inserted the datatype at 1041; cumulative growth |
| `differ.py:149` | `ops.bend:1066` | `ATuple{ys: List<&2,U32>}` | type **1198**, eq def **2042** | DRIFT **LIVE** (also `run34`'s file) | cumulative; `ATuple` is not the `CallInfo` comment at 1066 |
| `rn-gate.py:10,26,98,171,250` | `render.bend:2148` | `py_row` (row shape) | def **2019**, print **2021** | DRIFT **LIVE render.bend** | matched at `356e59ffa` (py_row 2147); rewritten repeatedly since |
| `rn-gate.py:51,172` | `render.bend:2693` | `rnd_row` | def **2557** | DRIFT **LIVE** | matched at `356e59ffa` (rnd_row 2687) |
| `rn-gate.py:164` | `render.bend:2763` | `pu_line` | def **2751** | DRIFT **LIVE** | rewritten |
| `rn-gate.py:40,133,251,399` | `render.bend:2809-2819` | five rows as two `IO.print`s (`AKern`…`AParam3`) | **3014-3024** | DRIFT **LIVE** — the five pairs still exist | matched at `356e59ffa` (2809-2819) |
| `e2e.py:55` | `renderer/cstyle.bend:2984-3015` | seven-dtype `rd_row` dispatch | **DELETED**; was `2152-2193` pre-deletion; `2984` was **never** in range (file max 2373) | DELETED | `e51904b04` deleted 1058 lines of `cstyle.bend` |
| `e2e.sh:228` | `renderer/cstyle.bend:2984-3015` | same | same | DELETED | `e51904b04` |
| `run-f64.sh:411` | `cstyle.bend:1879` | `g_kernel()` fixture | **DELETED**; was `1878` pre-deletion | DELETED | `e51904b04` |
| `run-port-mm.sh:29` | `cstyle.bend:1879` | `g_kernel()` fixture | **DELETED**; was `1878` pre-deletion | DELETED | `e51904b04` |
| `run-port-mm.sh:87` | `helpers.bend:2551` | a concurrent edit at that line | `2551` = a `GlobalCounters.reset` comment | NARR (historical) | no token named; not resolvable |

**The single edit that did the most damage is `e51904b04`** (2026-10-06, *"four singleton markers"*):
`1 file changed, 1 insertion(+), 1058 deletions(-)` for `cstyle.bend` alone, and
`4 files changed, 4 insertions(+), 6804 deletions(-)` across `engine/jit.bend`, `nn/__init__.bend`,
`renderer/cstyle.bend`, `runtime/ops_nv.bend`. It removed `def rd_row(…)`, `def g_kernel()`, and the
seven-dtype dispatch block from `cstyle.bend`. **The four cstyle cites are not number drift; their
subject was deleted.**

### (c) FILE GONE — 0

**No `.bend:<N>` cite in `checks/*.{py,sh,bend}` points at a file that does not exist.** The one
`scan.py` flagged (`GONE-FILE`, `unowned.py:66` → `ag-emit.bend`) resolves to
`.agents/slop/ag-emit.bend:32`, content-identical to the citation — a basename that lives outside
`checks/`, not a missing file. Broader denominator, for scale: `AGENTS.md`'s own census counts
**180 of 333** `.agents/TOOLS.md`-named paths gone (96 under `.agents/slop/`), of which 14 are
instruments. **This population is 0 of 34** — cite targets in `checks/` are almost all live tree files.

## 3. Corrections landed (one edit)

| file | before | after | re-resolved |
|---|---|---|---|
| `checks/stage1-census.py:204` | `mixin/elementwise.bend:543-544` | `mixin/elementwise.bend:542-543` | `542`=ew_add, `543`=ew_mul — both names now inside the range |

**Why exactly one.** The other 23 non-resolving cites cannot be corrected by a number edit:
* **18 target files under live edit** (`ops.bend` 6, `render.bend` 12) → the brief's
  "report, do not edit", because the correct number moves again in the same commit that moves it.
  (A further one, `gates/ops-core-gate.py:12`, is live-targeted too but outside this unit's scope.)
* **4 target content DELETED** by `e51904b04` (`cstyle.bend` ×4) → a number edit would point into a
  file where the token no longer exists. The repair is re-point-or-delete, a semantic decision for
  the owner of `e2e.py`/`e2e.sh`/`run-f64.sh`/`run-port-mm.sh`.
* **1 narrative cite** (`run-port-mm.sh:87`) names no token to check against.

## 4. Reported, not edited — cite targets under live edit (name + SHOULD-BE)

| `check:line` | cite | SHOULD BE (as of HEAD `b4dc69094`) |
|---|---|---|
| `checks/nl-gate.py:39`, `:477` | `ops.bend:7837` | `ops.bend:8407` (`def vd_text`) — but `ops.bend` is live |
| `checks/nl-gate.py:40`, `:477` | `ops.bend:7874` | **no target**: `vd_dbg` never existed. Re-point or delete the claim |
| `checks/disagree-gate.py:93` | `ops.bend:1057` | `ops.bend:1075` (`CustomFunction{name, dtype}`), or `1060` for the `dtype` bullet |
| `checks/differ.py:149` | `ops.bend:1066` | `ops.bend:1198` (type) / `2042` (eq). **`differ.py` is `run34`'s** |
| `checks/rn-gate.py:10,26,98,171,250` | `render.bend:2148` | `render.bend:2019` (`py_row`) |
| `checks/rn-gate.py:51,172` | `render.bend:2693` | `render.bend:2557` (`rnd_row`) |
| `checks/rn-gate.py:164` | `render.bend:2763` | `render.bend:2751` (`pu_line`) |
| `checks/rn-gate.py:40,133,251,399` | `render.bend:2809-2819` | `render.bend:3014-3024` (the five two-print wraps) |

### Outside this unit's write scope (reported)

* `gates/ops-core-gate.py:12` → `ops.bend:5044-5045`: the line is the `vmin`/`vmax` three-valued
  predicate wall, **not** the CONST-identity cluster the prose claims, and `awmma`'s `5051-5052` is
  the same region. The correct target is undetermined from the cited content — flag for the
  `gates/` owner. (This is the 4th of `awmma`'s "4".)

## 5. Residual

* `.bend:<N>` cites at a **gone file**: **0 / 34**.
* `<name>.bend` cites resolving through **ambiguous basenames**: 1 — `ip.bend` exists at
  `runtime/support/am/ip.bend` and `runtime/support/nv/ip.bend` (plus two `.agents/slop/` copies);
  the cite resolves correctly to the **nv** copy.
* Prose cites at **deleted content** (token gone, file present): 4 (`cstyle.bend` ×4).
* Untraceable narrative cites: 1 (`run-port-mm.sh:87`).

Artifacts: `.agents/slop/chkcites/scan.py` (the discovery walk), `.agents/slop/chkcites/cites.tsv`
(raw 34 rows), `.agents/slop/chkcites/scan.err` (counts: `total=34 resolves=29 gone=1 out_of_range=4`,
pre-token-check).
