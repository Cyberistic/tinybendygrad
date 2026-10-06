# `.agents/TODO.md` — characterisation BY DISCOVERY

Instrument: `.agents/slop/todo2/discover.py` (Python, reads the file once).
SHA256: `a66cb972697d2e8c225ce36984b1e109d55b62951509158a95be824dc80fca33`

## 1. Size

| quantity | value | denominator |
|---|---|---|
| bytes | 992659 | file |
| lines (`wc -l`) | 13477 | file |
| blank lines | 1301 | of 13477 lines |
| non-blank lines | 12176 | of 13477 lines |

## 2. Heading census

Total heading lines: **266** of 13477 lines.

| level | count |
|---|---|
| `#` | 1 |
| `##` | 183 |
| `###` | 82 |

## 3. Checkbox states

| pattern | lines | of |
|---|---|---|
| task items `- [ ]`/`- [x]`/`- [~]` | 1317 | 13477 lines |
| `[ ]` unchecked | 239 | 1317 items |
| `[x]` checked (lower) | 1074 | 1317 items |
| `[X]` checked (upper) | 0 | 1317 items |
| `[~]` indeterminate | 4 | 1317 items |
| completion | 81.55% | 1074/1317 items |

Raw `grep -c '[ ]'` = 246 lines; `grep -c '[x]'` = 1111 lines; sum = 1357, vs 1317 task lines. The raw greps over-count because prose embeds `[ ]`/`[x]` tokens.
Checkbox TOKENS anywhere (prose incl.): 1361 on 1361 lines.

## 4. Progress bars

`AGENTS.md` claims `rg -c '[█▓▒░]' .agents/TODO.md` = **12 lines**.
VERIFIED: **12 lines** carry a bar glyph; **191 total bar glyphs** on 13477 lines.

Bar-bearing lines (1-based):

```
3743: Progress: `██████████` 1/1
4030: Progress: naming consistency ██████████ DONE (gate green, 0 unadjudicated renames)
4031: Progress: remaining renames ████████░░ DONE (11 renamed; 2 blocked; 1 class needs a ruling)
4952: Progress: naming gate ██████████ PASS (668 candidates, 0 unadjudicated) — MEASURED 22:40:24
5361: Progress: `[████████████████████] 100%` — mechanism named, `device.bend` cleared 21/21, honest
5421: Progress: `[████████████████████] 100%` — 6/6 BROKEN entries classified, `.bin` keyed on the port,
5571: Progress: `[████████████████████] 100%` — mechanism reproduced end to end, 4 readers added to
5640: Progress: `[████████████████████] 100%` — state restored, controls green, 29 recorded, 9 excluded.
6996: Progress: `[████████████████████] 100%` — which side named with denominators, the 19 named and
8462: component. `[███████░░░] 70%`** (the 4 fixable findings below are not yet landed.)
11786: [JSFP8 ## fp8 lanes](../../.agents/slop/JSFP8.md) 9/9 |███████████████████| 100%
13451: Progress: ops.bend backlog `████░░░░░░░░░░░░░░░░░░` **7/43** (36 remaining, from a start of 43)
```

## 5. Duplication

| quantity | value | denominator |
|---|---|---|
| distinct lines (byte-exact) | 12057 | 13477 lines |
| distinct lines (whitespace-stripped) | 12048 | 13477 lines |
| duplicated line instances | 1420 | 13477 lines |
| repeated-line variety | 25 | 12057 distinct |

### Top repeated single lines

| count | line |
|---|---|
| 1301 | `` |
| 40 | `---` |
| 23 | `      ```` |
| 21 | ````` |
| 7 | `### Outside this unit's files` |
| 6 | `      |---|---|---|` |
| 4 | `## **NOT COMMITTED.**` |
| 4 | `      |---|---|---|---|` |
| 3 | `      **COMMITTED**.` |
| 3 | `|---|---|---|---|` |
| 3 | `### Found, not fixed` |
| 3 | ``E = env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py`` |
| 3 | `      | int const | port | CPython |` |
| 2 | `| --- | --- | --- | --- |` |
| 2 | `      exactly one row.` |
| 2 | `      NOT COMMITTED, per the task's instruction.` |
| 2 | `  |---|---|---|---|` |
| 2 | `Progress: `uop/ops.bend` loose ends [###.] BLOCKED ON A CONCURRENT OVERWRITE — A: premise` |
| 2 | `      FALSIFIED, 4 rows + comment proven, patch ready, blast radius 1 of 72 files ·` |
| 2 | `      B: gate was RED (94/99) and is GREEN (103/103/103) on both trees IN THIS UNIT'S` |
| 2 | `      TREE, red again only via the overwrite · C: no live owner, rows kept · **the live` |
| 2 | `- [x] **NOT COMMITTED**, per brief.` |
| 2 | ``.agents/slop/notes/bend2-constraints.md`.` |
| 2 | `**Nothing committed.**` |
| 2 | `      v = ((c2 * 2**24) + c1) * 2**24 + c0` |

### Top repeated contiguous blocks (non-blank, len 2-6)

- **x3** (2 lines):
    - `      | int const | port | CPython |`
    - `      |---|---|---|`
- **x2** (2 lines):
    - `Progress: `uop/ops.bend` loose ends [###.] BLOCKED ON A CONCURRENT OVERWRITE — A: premise`
    - `      FALSIFIED, 4 rows + comment proven, patch ready, blast radius 1 of 72 files ·`
- **x2** (2 lines):
    - `      FALSIFIED, 4 rows + comment proven, patch ready, blast radius 1 of 72 files ·`
    - `      B: gate was RED (94/99) and is GREEN (103/103/103) on both trees IN THIS UNIT'S`
- **x2** (2 lines):
    - `      B: gate was RED (94/99) and is GREEN (103/103/103) on both trees IN THIS UNIT'S`
    - `      TREE, red again only via the overwrite · C: no live owner, rows kept · **the live`
- **x2** (2 lines):
    - `      v = ((c2 * 2**24) + c1) * 2**24 + c0`
    - `      ````
- **x2** (3 lines):
    - `Progress: `uop/ops.bend` loose ends [###.] BLOCKED ON A CONCURRENT OVERWRITE — A: premise`
    - `      FALSIFIED, 4 rows + comment proven, patch ready, blast radius 1 of 72 files ·`
    - `      B: gate was RED (94/99) and is GREEN (103/103/103) on both trees IN THIS UNIT'S`
- **x2** (3 lines):
    - `      FALSIFIED, 4 rows + comment proven, patch ready, blast radius 1 of 72 files ·`
    - `      B: gate was RED (94/99) and is GREEN (103/103/103) on both trees IN THIS UNIT'S`
    - `      TREE, red again only via the overwrite · C: no live owner, rows kept · **the live`
- **x2** (4 lines):
    - `Progress: `uop/ops.bend` loose ends [###.] BLOCKED ON A CONCURRENT OVERWRITE — A: premise`
    - `      FALSIFIED, 4 rows + comment proven, patch ready, blast radius 1 of 72 files ·`
    - `      B: gate was RED (94/99) and is GREEN (103/103/103) on both trees IN THIS UNIT'S`
    - `      TREE, red again only via the overwrite · C: no live owner, rows kept · **the live`

## 6. Sections (`##` and above) — checkbox rollup

| section | line | items | done | open | `[~]` | bar lines |
|---|---|---|---|---|---|---|
| TODO | 1 | 49 | 39 | 10 | 0 | 0 |
| Phase P0 — toolchain and scaffolding | 603 | 9 | 8 | 1 | 0 | 0 |
| Phase P1 — the contract | 625 | 10 | 9 | 1 | 0 | 0 |
| Phase P2 — trial run | 671 | 11 | 8 | 2 | 1 | 0 |
| Session 2026-10-03 — the package-boundary gap + the wall,... | 952 | 19 | 18 | 0 | 1 | 0 |
| Session 2026-10-04 — P3 parallel wave, and the queue coun... | 1156 | 0 | 0 | 0 | 0 | 0 |
| Phases P3–P8 — the port | 1326 | 3 | 1 | 1 | 1 | 0 |
| DEFERRED — the LOC-reduction plan (2026-10-02, owner: rev... | 1499 | 0 | 0 | 0 | 0 | 0 |
| Open decisions | 1567 | 6 | 3 | 3 | 0 | 0 |
| Session 2026-10-01 wrap (fuzz + trim + gate wave) | 1623 | 10 | 5 | 5 | 0 | 0 |
| Session 2026-10-01 — `mixin/gradient.py` | 1634 | 4 | 1 | 3 | 0 | 0 |
| Session 2026-10-01 round 2 (schedule/mixin/engine/tensor/... | 1649 | 9 | 5 | 4 | 0 | 0 |
| Session 2026-10-01 round 3 — `mixin/elementwise.py` | 1663 | 8 | 7 | 1 | 0 | 0 |
| Session 2026-10-01 round 4 — `codegen/decomp/transcendent... | 1696 | 9 | 6 | 3 | 0 | 0 |
| Session 2026-10-01 round 5 — `mixin/op.py` lines 1-997 | 1737 | 9 | 7 | 2 | 0 | 0 |
| Session 2026-10-02 — the device wave (renderer, codegen/o... | 1792 | 19 | 15 | 4 | 0 | 0 |
| Session 2026-10-02 — `device.bend` | 2016 | 3 | 3 | 0 | 0 | 0 |
| Session 2026-10-02 — `langs/` the four-lane export matrix | 2042 | 8 | 7 | 1 | 0 | 0 |
| TWO SUBSTRATE DEFECTS found by mixin/reduce.bend (committ... | 2096 | 2 | 0 | 2 | 0 | 0 |
| OPEN — `H.dedup_u32` reverses, and `nn/optim`'s filter re... | 2124 | 1 | 0 | 1 | 0 | 0 |
| Session 2026-10-02 — `runtime/ops_metal.bend` (the Metal ... | 2168 | 6 | 6 | 0 | 0 | 0 |
| Session 2026-10-02 — `runtime/ops_cl.bend` (ONE device, T... | 2252 | 6 | 6 | 0 | 0 | 0 |
| Session 2026-10-02 — a COMMITTED GATE ROW WAS ENCODING A ... | 2308 | 8 | 8 | 0 | 0 | 0 |
| Session 2026-10-02 — `runtime/ops_nv.bend` (606 rows, TWO... | 2354 | 8 | 6 | 2 | 0 | 0 |
| Session 2026-10-02 — `runtime/ops_nv.bend` (the CUDA devi... | 2417 | 8 | 8 | 0 | 0 | 0 |
| STANDING INSTRUCTION (owner, 2026-10-02) — the agent pipe... | 2465 | 0 | 0 | 0 | 0 | 0 |
| Session 2026-10-02 — `runtime/ops_rdma.bend`, `runtime/op... | 2563 | 3 | 3 | 0 | 0 | 0 |
| Session 2026-10-02 — `runtime/ops_dsp.bend` (the generic ... | 2656 | 10 | 10 | 0 | 0 | 0 |
| Session 2026-10-02 — `schedule/indexing.bend` | 2713 | 7 | 6 | 1 | 0 | 0 |
| Session 2026-10-02 — schedule/rangeify.bend REPAIR (not e... | 2843 | 9 | 7 | 2 | 0 | 0 |
| Session 2026-10-02 — schedule/rangeify.bend: THE `ct` TAB... | 3017 | 11 | 10 | 1 | 0 | 0 |
| Session 2026-10-02 — upstream `793abbb` "modernize tinygr... | 3100 | 15 | 10 | 5 | 0 | 0 |
| Session 2026-10-02 — `runtime/support/memory.bend`: the a... | 3201 | 0 | 0 | 0 | 0 | 0 |
| green on 570 of 995 rows | 3202 | 9 | 9 | 0 | 0 | 0 |
| Session 2026-10-02 — REBASE BATCH B2 (`dtype.py` + `rende... | 3268 | 8 | 8 | 0 | 0 | 0 |
| Session 2026-10-02 — env-flag semantic divergence audit (... | 3323 | 9 | 8 | 1 | 0 | 0 |
| Session 2026-10-03 — ungated-drift closure: `uop/render.b... | 3371 | 7 | 5 | 2 | 0 | 0 |
| Session 2026-10-03 — REBASE GATE WIRING: 19 ports with ga... | 3457 | 13 | 11 | 2 | 0 | 0 |
| Session 2026-10-03 — `runtime/support/objc.bend`: the FFI... | 3562 | 5 | 2 | 3 | 0 | 0 |
| Session 2026-10-03 — `renderer/amd/generate.bend` (the IS... | 3642 | 10 | 10 | 0 | 0 | 0 |
| Session 2026-10-03 — dtype.bend const CAST refusal (measu... | 3741 | 1 | 1 | 0 | 0 | 1 |
| Session 2026-10-03 — `codegen/decomp/dtype.py` | 3753 | 16 | 8 | 8 | 0 | 0 |
| Session 2026-10-03 — `trange`, `GlobalCounters`, `Context... | 3869 | 0 | 0 | 0 | 0 | 0 |
| `tinybendygrad/helpers.bend` (the only unit permitted to ... | 3870 | 0 | 0 | 0 | 0 | 0 |
| **NOT COMMITTED.** | 3871 | 13 | 11 | 2 | 0 | 0 |
| Session 2026-10-03 — `void`'s priority and `CustomFunctio... | 3952 | 0 | 0 | 0 | 0 | 0 |
| **NOT COMMITTED.** | 3953 | 7 | 7 | 0 | 0 | 0 |
| Session 2026-10-03 — THE NAMING GATE: the def-name ruling... | 4029 | 17 | 12 | 5 | 0 | 2 |
| Session 2026-10-03 — `ops_python` render oracle quoting | 4217 | 1 | 1 | 0 | 0 | 0 |
| Session 2026-10-03 — re-anchor the wire-pair standing con... | 4230 | 1 | 1 | 0 | 0 | 0 |
| Session 2026-10-03 — which tree the wired gates import | 4242 | 1 | 1 | 0 | 0 | 0 |
| Session 2026-10-03 — ARange ucache collision | 4252 | 1 | 1 | 0 | 0 | 0 |
| Session 2026-10-03 — `renderer/amd/elf.bend` (the AMD ELF... | 4270 | 5 | 5 | 0 | 0 | 0 |
| Session 2026-10-03 — `codegen/__init__.bend`: the rewrite... | 4322 | 5 | 5 | 0 | 0 | 0 |
| Session 2026-10-03 — `graphcmp`: a CANONICAL GRAPH NORMAL... | 4376 | 0 | 0 | 0 | 0 | 0 |
| **NOT COMMITTED.** | 4377 | 11 | 11 | 0 | 0 | 0 |
| Session 2026-10-03 (gc2) — `graphcmp`: THE FIVE RESIDUALS... | 4478 | 0 | 0 | 0 | 0 | 0 |
| **NOT COMMITTED.** | 4479 | 9 | 9 | 0 | 0 | 0 |
| Session 2026-10-03 (b) — the eight `c{i}` fixtures, `code... | 4586 | 8 | 8 | 0 | 0 | 0 |
| Session 2026-10-03 — the two `dd_rs` cone bugs in codegen... | 4644 | 9 | 9 | 0 | 0 | 0 |
| Session 2026-10-03 (c) — `DEBUG` IS WIRED: the seven gate... | 4695 | 0 | 0 | 0 | 0 | 0 |
| five-level gate. **NOT COMMITTED.** | 4696 | 15 | 13 | 2 | 0 | 0 |
| Session 2026-10-03 — `renderer/amd/generate.bend`: THE 14... | 4857 | 10 | 10 | 0 | 0 | 0 |
| Session 2026-10-03 (n) — NAMING GATE BACK TO PASS: `geten... | 4950 | 9 | 9 | 0 | 0 | 1 |
| Session 2026-10-03 — six ADOPTED defects (reported, never... | 5033 | 8 | 7 | 1 | 0 | 0 |
| Session 2026-10-04 — `codegen/decomp/dtype.bend`: 33 of 5... | 5187 | 14 | 8 | 6 | 0 | 0 |
| ops.py:501-1928 (the base family, the movers, `split_uop`... | 5287 | 0 | 0 | 0 | 0 | 0 |
| [DONE] Reconcile the gate's verdict with the selftest's n... | 5359 | 0 | 0 | 0 | 0 | 1 |
| [DONE] rebase-gate: BROKEN is one word for five things — ... | 5419 | 0 | 0 | 0 | 0 | 1 |
| [DONE] LANE PROVENANCE: a lane-death now names the FILE a... | 5569 | 0 | 0 | 0 | 0 | 1 |
| [DONE] rebase-gate: restore `AGREE-UNRECORDED` and record... | 5638 | 0 | 0 | 0 | 0 | 1 |
| Session 2026-10-03/04 — UNOBSERVABLE-ROW CENSUS: rows tha... | 5674 | 12 | 11 | 1 | 0 | 0 |
| Session 2026-10-04 — ORDER-BLIND GATES, the close-out of ... | 5869 | 9 | 8 | 1 | 0 | 0 |
| Session 2026-10-04 — `dtype.bend`'s TWO ORACLES DISAGREE ... | 6011 | 12 | 9 | 3 | 0 | 0 |
| Session 2026-10-04 — `renderer/cstyle.bend`: 225 rows, ZE... | 6116 | 13 | 13 | 0 | 0 | 0 |
| Mutation-table trustworthiness (dd unit, 2026-10-04) | 6255 | 9 | 9 | 0 | 0 | 0 |
| ZERO CLASSIFICATION (zero unit, 2026-10-04) | 6313 | 9 | 9 | 0 | 0 | 0 |
| Session 2026-10-04 — REPO HYGIENE: the dangling citations... | 6378 | 17 | 13 | 4 | 0 | 0 |
| Session 2026-10-04 — M09 CLOSED: two fixture rows, the RE... | 6505 | 6 | 6 | 0 | 0 | 0 |
| Session 2026-10-04 — `uop/ops.bend`'s three loose ends: t... | 6553 | 11 | 11 | 0 | 0 | 0 |
| MUTATION-ZERO VERBOSITY — one marker for a patch that did... | 6777 | 7 | 7 | 0 | 0 | 0 |
| Session 2026-10-04 (late) — INSTRUMENTS FIXED, AND THE TA... | 6836 | 24 | 16 | 8 | 0 | 0 |
| Session 2026-10-04 (substrate unit) — the `ABlob` intern ... | 6948 | 7 | 5 | 2 | 0 | 0 |
| [DONE] ops-501-gate: THE PORT WAS MISSING THREE DEFS, and... | 6994 | 0 | 0 | 0 | 0 | 1 |
| Session 2026-10-04 (gc3) — `graphcmp`: WIDENED TO NINE GR... | 7114 | 0 | 0 | 0 | 0 | 0 |
| COMPARISON, AND A PROOF THAT THE DIFFER CAN FAIL | 7115 | 7 | 7 | 0 | 0 | 0 |
| ARENA ALIASING SWEEP — `O.Arena.node` is TOTAL, so a wron... | 7195 | 8 | 8 | 0 | 0 | 0 |
| [x] FORM-BLINDNESS CENSUS — every tool that matches a for... | 7405 | 0 | 0 | 0 | 0 | 0 |
| that lacks it. Six findings, one root cause, one checkabl... | 7406 | 0 | 0 | 0 | 0 | 0 |
| `.agents/slop/{rowform,formblind-census,formblind-audit,s... | 7407 | 0 | 0 | 0 | 0 | 0 |
| + `FORM-BLIND-SPOTS.md`. Rules `FB-1`…`FB-7` at `bend2-co... | 7408 | 11 | 11 | 0 | 0 | 0 |
| Session 2026-10-04 — `f2f`'s region: a FORWARD REFERENCE,... | 7496 | 0 | 0 | 0 | 0 | 0 |
| Session 2026-10-04 (gc4) — `graphcmp`: GROUP, INDEX/BARRI... | 7554 | 0 | 0 | 0 | 0 | 0 |
| COMMUTATIVE OPS, AND THE SYMBOLIC-DIM LIMIT MEASURED | 7555 | 7 | 7 | 0 | 0 | 0 |
| Session 2026-10-04 (dl) — `debug-gate`: LEVELS 4, 5, 6, 7... | 7640 | 11 | 11 | 0 | 0 | 0 |
| Session 2026-10-04 — mutation-table ANCHORS re-aimed, and... | 7752 | 10 | 10 | 0 | 0 | 0 |
| Session 2026-10-04 — CSTYLE-GATE READER (`.agents/slop/cs... | 7906 | 6 | 6 | 0 | 0 | 0 |
| Session 2026-10-04 (load unit) — THE BASELINE LEDGER: 0 o... | 7953 | 8 | 5 | 3 | 0 | 0 |
| Session 2026-10-04 (gc5) — `graphcmp`: A REAL LINEARIZED ... | 8018 | 0 | 0 | 0 | 0 | 0 |
| `BACKEDGE` / `LOAD` / `STORE` ARE COMPARED AT LAST | 8019 | 11 | 11 | 0 | 0 | 0 |
| Session 2026-10-04 (name-shape unit) — A ROW NAME CONTAIN... | 8155 | 6 | 6 | 0 | 0 | 0 |
| Session 2026-10-04 (c2d unit) — `s5_copy_sel` GATED A NOD... | 8211 | 0 | 0 | 0 | 0 | 0 |
| WAS WRONG THREE TIMES OVER. THE REUSAL IS A RETURN-TYPE C... | 8212 | 11 | 11 | 0 | 0 | 0 |
| Session 2026-10-04 (reader-fork unit) — 156 FORKED READER... | 8293 | 5 | 5 | 0 | 0 | 0 |
| Session 2026-10-04 — `schedule/__init__.py:82-301` (the "... | 8343 | 4 | 4 | 0 | 0 | 0 |
| Session 2026-10-04 (portexec unit) — THE PORT'S C RAN. 2 ... | 8414 | 8 | 8 | 0 | 0 | 0 |
| AUDIT-CAN-FAIL — "can this headline number go RED?" (2026... | 8459 | 9 | 5 | 4 | 0 | 1 |
| Session 2026-10-04 — tensor-surface census (read-only; `.... | 8505 | 14 | 14 | 0 | 0 | 0 |
| Session 2026-10-04 — `cstyle-live`: `renderer/cstyle.bend... | 8635 | 11 | 10 | 1 | 0 | 0 |
| Session 2026-10-04 round 2 — `i64_dec`, the signed-decima... | 8709 | 1 | 1 | 0 | 0 | 0 |
| Session 2026-10-04 — the four headline numbers (owner: th... | 8764 | 6 | 5 | 0 | 1 | 0 |
| Session 2026-10-04 — e2e-through-port: `e2e.sh` STAGE 6, ... | 8857 | 7 | 7 | 0 | 0 | 0 |
| Session 2026-10-04 round 3 — `print_uops` GATED, and thre... | 8912 | 1 | 1 | 0 | 0 | 0 |
| slop(wallmap) — a census and a RANKING of every refusal r... | 8961 | 0 | 0 | 0 | 0 | 0 |
| Session 2026-10-04 (mathlib unit) — RANK 1 IS NOT A MISSI... | 9144 | 0 | 0 | 0 | 0 | 0 |
| Session 2026-10-04 (BW) — `graphcmp`: A BACKWARD GRAPH, `... | 9267 | 13 | 8 | 5 | 0 | 0 |
| [x] **DEAD-ARM CENSUS — the parts of the tree NO instrume... | 9354 | 21 | 10 | 11 | 0 | 0 |
| Session 2026-10-04 round 4 — the RANGE COLUMN, and a colo... | 9494 | 1 | 1 | 0 | 0 | 0 |
| M — the last 64-bit mile. `.agents/slop/W64-MILE.md` | 9560 | 6 | 3 | 3 | 0 | 0 |
| SUB — collective completeness: does a PARSING file still ... | 9583 | 6 | 5 | 1 | 0 | 0 |
| F — the f64 KERNEL, not the f64 scalar. `.agents/slop/F64... | 9614 | 14 | 12 | 2 | 0 | 0 |
| JSL2 — the JS dtype lane gate (unit `JSL2`, 2026-10-04) | 9707 | 17 | 13 | 4 | 0 | 0 |
| 2026-10-04 — `arith`: the six arithmetic ops. Ops reached... | 9783 | 15 | 11 | 4 | 0 | 0 |
| S- — SPELLING: one 64-bit spelling for the tree | 9853 | 11 | 8 | 3 | 0 | 0 |
| Session 2026-10-04 round 5 — an F32 CONSTANT WALL THAT WA... | 9905 | 1 | 1 | 0 | 0 | 0 |
| `notes-sweep` unit, 2026-10-04 — the notes' numbers were ... | 9964 | 0 | 0 | 0 | 0 | 0 |
| TRIAGE — the 21 stray `.bend` copies (2026-10-04) | 10019 | 8 | 4 | 4 | 0 | 0 |
| `DENOM` — the 77 denominator (unit `DENOM`, 2026-10-04). ... | 10079 | 10 | 8 | 2 | 0 | 0 |
| GUARDFIX — `substrate-check.sh` half 1 ROUTES BY WHAT THE... | 10122 | 11 | 11 | 0 | 0 | 0 |
| `DTB-` dtype.bend's red laws — 14 -> 6. Full write-up in ... | 10193 | 9 | 9 | 0 | 0 | 0 |
| Session 2026-10-04 round 6 — the method surface was 71/71... | 10253 | 1 | 1 | 0 | 0 | 0 |
| `DEVG` — is `DEV` a SETTING or a COMMENT? (unit `DEVG`, 2... | 10307 | 9 | 8 | 1 | 0 | 0 |
| Session 2026-10-04 round 7 — the FIRST method landed sinc... | 10362 | 1 | 1 | 0 | 0 | 0 |
| Session 2026-10-04 — unit `ADEV`: the `COPY`/device NORMA... | 10407 | 8 | 8 | 0 | 0 | 0 |
| Session 2026-10-04 round 8 — `swish` and `silu`: THREE me... | 10452 | 1 | 1 | 0 | 0 | 0 |
| SZLANE — `runtime/sz.c`'s bare registrations (unit `szlan... | 10503 | 7 | 5 | 2 | 0 | 0 |
| libclang trampolines: the 324 `None{}` bodies  [CF] | 10543 | 6 | 3 | 3 | 0 | 0 |
| NVROWS — the 313 dead `nvdev.bend` gate rows (unit `NVROW... | 10588 | 7 | 5 | 2 | 0 | 0 |
| Session 2026-10-04/05 round 9 — one method landed, one HE... | 10635 | 2 | 1 | 1 | 0 | 0 |
| `CSH` — widen `cshape`'s `except`, or prove it cannot be ... | 10691 | 0 | 0 | 0 | 0 | 0 |
| Progress: [#########.] 9/10 | 10692 | 14 | 13 | 1 | 0 | 0 |
| Session 2026-10-05 — `tanh`'s blocker, characterised rath... | 10776 | 0 | 0 | 0 | 0 | 0 |
| i64mul unit (IM-1..IM-6) -- `i64_mul` DERIVED, GATED, LAN... | 10835 | 6 | 6 | 0 | 0 | 0 |
| Session 2026-10-05 round 2 — the promotion matrix's MISSI... | 10901 | 1 | 0 | 1 | 0 | 0 |
| MUT- (2026-10-05) — the mutated-copy hazard: labelled, me... | 10966 | 9 | 5 | 4 | 0 | 0 |
| CIDSWEEP — the rest of the tree after `libclang.bend`'s 3... | 11000 | 9 | 7 | 2 | 0 | 0 |
| Session 2026-10-05 round 3 — the promotion defect ISOLATE... | 11048 | 1 | 0 | 1 | 0 | 0 |
| PROBES — a probe or a plant in `tinybendygrad/` now annou... | 11120 | 21 | 16 | 5 | 0 | 0 |
| `e2e-js-lane` — STAGE 8 OF `e2e.sh`, THE JS LANE (JS8-1..7) | 11257 | 11 | 11 | 0 | 0 | 0 |
| [DONE] noneshape: `None` vs `None{}`, and an `Arg` that c... | 11327 | 11 | 11 | 0 | 0 | 0 |
| FP8FIX (2026-10-05) — the C lane of `runtime/dtype.c`: 3 ... | 11429 | 18 | 18 | 0 | 0 | 0 |
| Session 2026-10-05 round 4 — the "promotion defect" was M... | 11541 | 2 | 1 | 1 | 0 | 0 |
| Session 2026-10-05 round 5 — `wk_i64_to_f32`'s FORMULA is... | 11600 | 1 | 0 | 1 | 0 | 0 |
| LASTLAW (2026-10-05) — `tinybendygrad/dtype.bend`'s 8 red... | 11662 | 13 | 13 | 0 | 0 | 0 |
| JSFP8 — the JS fp8 lane (`runtime/dtype.js` + a decode ga... | 11784 | 23 | 15 | 8 | 0 | 1 |
| Session 2026-10-05 round 6 — the conversion is FIXED and ... | 11920 | 2 | 2 | 0 | 0 | 0 |
| NORM — one float normaliser for every gate, and the four ... | 11988 | 9 | 9 | 0 | 0 | 0 |
| Session 2026-10-05 — CSTYLE2: `renderer/cstyle.bend`'s 22... | 12078 | 9 | 7 | 2 | 0 | 0 |
| Session 2026-10-05 — `opspy`: `runtime/ops_python.bend` b... | 12135 | 8 | 7 | 1 | 0 | 0 |
| DIFFPY — the two shell drivers, ported to Python (`checks... | 12166 | 5 | 4 | 1 | 0 | 0 |
| Session 2026-10-05 round 7 — FIVE GATES COULD LIE, and a ... | 12185 | 1 | 1 | 0 | 0 | 0 |
| Session 2026-10-05 round 8 — three walls RETIRED, and the... | 12251 | 1 | 1 | 0 | 0 | 0 |
| Session 2026-10-05 round 9 — the PRIMARY gate could not r... | 12288 | 2 | 1 | 1 | 0 | 0 |
| Session 2026-10-05 round 10 — FOUR FILES ARE 0 BYTES IN T... | 12344 | 2 | 1 | 1 | 0 | 0 |
| Session 2026-10-05 round 11 — the 0-byte files are REPAIR... | 12398 | 1 | 1 | 0 | 0 | 0 |
| deadreg (2026-10-05) — `e2e.sh` STAGE 8's DENOMINATOR IS ... | 12451 | 0 | 0 | 0 | 0 | 0 |
| TO RETIRE THE STAGE, NOT TO REACH THE ROWS | 12452 | 6 | 5 | 1 | 0 | 0 |
| 2026-10-05 — WALLRULE unit: a wall names its prerequisite... | 12512 | 6 | 3 | 3 | 0 | 0 |
| Session 2026-10-05 round 12 — a wall that is TRUE and att... | 12552 | 1 | 0 | 1 | 0 | 0 |
| 2026-10-05 — E2EPY unit: `checks/e2e.sh` ported to `check... | 12608 | 10 | 7 | 3 | 0 | 0 |
| Session 2026-10-05 — `bitcastrow`: `bitcast_dims`' RANGE ... | 12705 | 6 | 5 | 1 | 0 | 0 |
| 2026-10-05 — WALLCHECK REBUILD: the checker was pruned wi... | 12745 | 9 | 6 | 3 | 0 | 0 |
| Session 2026-10-05 — the 103 `.txt` under `runs/graphcmp/D/` | 12794 | 6 | 4 | 2 | 0 | 0 |
| 2026-10-05 — STALEFIX unit: `gates/gatekit.py` left the P... | 12840 | 11 | 6 | 5 | 0 | 0 |
| FIX3 — stage 3's and stage 5's fixtures were deletable wh... | 12908 | 10 | 6 | 4 | 0 | 0 |
| 2026-10-06 — the lane-file rename, and the rule I broke t... | 12976 | 6 | 4 | 2 | 0 | 0 |
| clearfix — a gate's pre-run `sys.exit` strands the last g... | 13016 | 16 | 11 | 5 | 0 | 0 |
| 2026-10-06 — UNSETEXP unit: the NINE graphs that ran with... | 13084 | 9 | 6 | 3 | 0 | 0 |
| 2026-10-06 — which claims are REACHED, not which are written | 13125 | 3 | 2 | 1 | 0 | 0 |
| 2026-10-06 — the FIRST ops.bend gate, and the oracles com... | 13148 | 4 | 3 | 1 | 0 | 0 |
| 2026-10-06 — the arg-type lane, 14 rows, and the FOURTH f... | 13175 | 4 | 2 | 2 | 0 | 0 |
| SPECCITE — `file:line` CITATIONS, AND THE TENTH CLASS WAS... | 13207 | 10 | 7 | 3 | 0 | 0 |
| devpin — the DEVICE is a declared precondition of the gra... | 13270 | 30 | 24 | 6 | 0 | 0 |
| 2026-10-06 — the ops.bend marker campaign, and the fifth ... | 13449 | 5 | 4 | 1 | 0 | 1 |

`##`+ sections: 184 (denominator: level<=2 headings).

## 7. Subsections (`###`) with items or bars — the category candidates

| subsection | line | items | done | open | bar lines |
|---|---|---|---|---|---|
| Coldness — the three numbers, and the one that is allowed... | 254 | 5 | 5 | 0 | 0 |
| Tooling — the substrate gate is Python, and the shell sur... | 287 | 7 | 7 | 0 | 0 |
| Lane liveness — how many of the gated lanes actually RAN ... | 322 | 15 | 13 | 2 | 0 |
| The duplicate-row-name class — `usb` FIXED, and the censu... | 423 | 9 | 6 | 3 | 0 |
| The duplicate class, continued — `ops_nv`'s ORACLE closed... | 508 | 32 | 25 | 7 | 0 |
| The fuel detour — done, and it is worth remembering | 645 | 21 | 17 | 2 | 0 |
| `graph_rewrite` — the dispatcher, DONE. Both walls above ... | 1043 | 9 | 9 | 0 | 0 |
| P4 — `schedule/` | 1395 | 2 | 1 | 0 | 0 |
| Deferred until the oracle is green | 1493 | 1 | 0 | 1 | 0 |
| A retraction that belongs with this plan | 1554 | 67 | 45 | 22 | 0 |
| In flight when the machine went quiet (uncommitted, agent... | 1930 | 57 | 48 | 9 | 0 |
| Health rule, learned three times today | 2558 | 3 | 3 | 0 | 0 |
| SIX MEASURED BEND RULES APPENDED | 2644 | 150 | 123 | 27 | 1 |
| SEVEN MEASURED RULES APPENDED | 4021 | 42 | 37 | 5 | 2 |
| Outside this unit's files | 4464 | 9 | 9 | 0 | 0 |
| Outside this unit's files | 4574 | 8 | 8 | 0 | 0 |
| Outside this unit's files | 4627 | 9 | 9 | 0 | 0 |
| Outside this unit's files | 4679 | 15 | 13 | 2 | 0 |
| Outside this unit's files | 4843 | 8 | 8 | 0 | 0 |
| Outside this unit's files | 4923 | 11 | 11 | 0 | 1 |
| Outside this unit's files | 5020 | 127 | 111 | 16 | 4 |
| Closed | 6860 | 11 | 11 | 0 | 0 |
| Refused — and two of these were MY error, corrected by th... | 6890 | 4 | 4 | 0 | 0 |
| OPEN, and named | 6903 | 9 | 1 | 8 | 0 |
| Process, learned the hard way | 6932 | 7 | 5 | 2 | 1 |
| Found, not fixed | 7092 | 7 | 7 | 0 | 0 |
| Done | 7203 | 7 | 7 | 0 | 0 |
| Found, not fixed | 7336 | 19 | 19 | 0 | 0 |
| Reported, NOT fixed (the files are not this unit's) | 7618 | 121 | 112 | 8 | 1 |
| Walls, and what I did not touch | 8833 | 8 | 8 | 0 | 0 |
| [x] **ONE `bw` GRAPH IN THE DIFFER, `AGREE` AT FIELD-RECO... | 9274 | 8 | 8 | 0 | 0 |
| [ ] **FOR `graphcmp`'s OWNER — six pins that must move, R... | 9322 | 5 | 0 | 5 | 0 |
| [ ] **TWO SUBSTRATE MOVES UNDER THIS RUN, BOTH ANOTHER UN... | 9343 | 5 | 5 | 0 | 0 |
| [ ] **NOT MEASURED, and the reason** | 9395 | 5 | 1 | 4 | 0 |
| [x] **THE PORT CALLS: `runtime/autogen/libclang.bend` ans... | 9419 | 46 | 30 | 16 | 0 |
| FLIPR — `flip`'s DISAGREE located, split into two causes,... | 9750 | 136 | 112 | 24 | 0 |
| TWO OF MY OWN MISTAKES, RECORDED BECAUSE BOTH NEARLY SHIPPED | 10890 | 10 | 5 | 5 | 0 |
| Progress: [#########.] 9/10 | 11004 | 23 | 17 | 6 | 0 |
| S2 — Tensor surface: which missing methods a RUNTIME DEVI... | 11216 | 51 | 47 | 4 | 0 |
| Progress: [##########] 10/10 | 11665 | 154 | 113 | 41 | 1 |
| Shell roots — every `checks/*.sh` now proves which tree i... | 13029 | 48 | 33 | 15 | 0 |
| Meta-instruments — the twelfth generated directory, and t... | 13305 | 13 | 11 | 2 | 0 |
| graphcmp-oracle: the three defects that made `retention-c... | 13372 | 13 | 10 | 3 | 1 |

`###` subsections with content: 43 (denominator: 82 level-3 headings).

