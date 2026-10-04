# COLDNESS — one number, and the definition it is allowed to travel with

Unit `.agents/slop/coldness/`. **Nothing committed.** Owns this directory,
`agent-core.md` §2's table, and this file. No `.bend` was touched.
Compiler **Bend 2.0.34** via `./bin/bend`. **Measured 2026-10-05 14:19**, on a tree
four units were editing concurrently — every number below is a timestamped snapshot
and `sweep.sh` re-measures it.

---

## 0. THE ONE TRUE NUMBER, WITH ITS DEFINITION

> **The port has 0 cold files.**
>
> **Definition.** A `.bend` file is **COLD** iff **(a)** no other `.bend` file in the
> port imports it, **and (b)** it declares no `def main` / `def gate`, so `bend` has
> nothing to run it on. A file failing (a) is *unreferenced*; a file passing (a) is
> *wired*; a file passing (b) is *driven*. COLD is neither.
>
> **Measured over the 138 `.bend` files on disk: 9 files satisfy the definition, and
> all 9 are the empty `__init__.bend` package markers, with 0 defs and 0 laws each.**
> So the cold **surface** is 0 files and 0 defs. 41 of 138 are WIRED, 120 of 138 are
> DRIVEN.

This is the number to quote, because it is the only one of the four that is a
property of the file it is printed against: **editing a neighbour cannot move it.**
Every other coldness number in circulation here counts things a neighbour's
contents decide.

---

## 1. WHAT `COLD` MEANS IN THE GUARD — quoted from `.agents/slop/substrate-check.sh`

Lines 199-206, HALF 1, the `bend` route:

```zsh
  bend) n_bend=$((n_bend+1))
    v=$(perl -e 'alarm 300; exec @ARGV' "$BEND" "$f" --check-only 2>&1 | head -1)
    if [ "$v" = "ALL PROOFS CHECK" ]; then
      print -r -- "WARM        $f  ($lines lines)  [$tag]"
    else
      print -r -- "COLD        $f  ($lines lines)  [$tag]  :: $v"
      fail=$((fail+1))
    fi ;;
```

`COLD` is **exactly**: the first line of `bend --check-only <f>` (stdout+stderr merged)
is not the literal string `ALL PROOFS CHECK`. It is a **per-file string compare**.
The exit code is **discarded** (line 200 never reads `$?`). It says nothing about
importers, and `--check-only` loads the file's **whole transitive import closure**, so
a red file is very often red because of something *somewhere else*.

Two neighbouring verdicts that are **NOT** `COLD` — lines 171-174 and 196-198:

```zsh
  if [ "$lines" -eq 0 ] || [ "$bytes" -eq 0 ]; then
    print -r -- "EMPTY       $f  ($lines lines, $bytes bytes)  <-- THE VERDICT IS MEANINGLESS"
  ...
  none) n_none=$((n_none+1))
    print -r -- "NO INSTRUMENT  $f  ($lines lines)  :: $why -- **NOT JUDGED, AND NOT COLD**"
```

**Zero arguments exits 3** (lines 257-263) and prints `REFUSED: no files given.` — so
a bare `zsh substrate-check.sh` is not a measurement and cannot be quoted as `COLD 0`.

`BAD` / `UNRESOLVED` (lines 434-445) are **HALF 2, a different question**: does every
`<alias>.<name>` a file references exist in a module that file imports. `BAD` counts
deduped problem **sites**, not files.

### The five error shapes `COLD` actually stands for (measured over all 138)

`Error: N TODOs found.` is not prose — it is `book.hols`, `references/bend/bend2/main.ts:815`:

```ts
    if (book.hols > 0) {
      throw "Error: " + String(book.hols) + " TODO" + (book.hols === 1 ? "" : "s")
        + " found.\nThe code is incomplete, and not a valid proof yet.";
```

`Bend.book_load(book, file, …)` on line 811 loads the **closure** — which is why
`book.hols` is inherited, and why `grep -c TODO` finds **0** in `PROOF.bend` while the
compiler reports 18. **A red-law count taken with grep is 0 and wrong.**

| shape | count of the 35 |
|---|---|
| `Error: N TODOs found.` (unproven obligations, `book.hols > 0`) | 3 |
| `Error: N defs rely on unsafe or foreign code:` | 2 |
| `- expected : a defined name / observed : A.b` | 20 |
| `- expected : a fresh name (duplicate declaration: X)` | 4 |
| `- message : a declared constructor (unknown: X)` | 3 |
| `- expected : T / observed : U` (type mismatch) | 2 |
| `- expected : 'def','type' or 'law' / observed : ','` | 1 |

---

## 2. THE DENOMINATOR: FOUR NUMBERS, NOT TWO

| number | what it counts | how to get it |
|---|---|---|
| **138** | `.bend` files **on disk** under `tinybendygrad/` now | `find tinybendygrad -name '*.bend' \| wc -l` |
| **137** | `.bend` files **in the git index** | `git ls-files 'tinybendygrad/**/*.bend' \| wc -l` |
| **113** | `.bend` files that are **1:1 with an upstream `.py`** — the guard's strict `port=` | `substrate-check.sh` PROVENANCE block |
| **139** | **arguments the guard's last run was handed** — not a file count at all | — |

**138 is my measurement, and 139 is not a `.bend` count.** The guard's own last output
reported `COLD 35` + `WARM 104` = 139; my run over 138 `.bend` files reports
**`COLD 35` + `WARM 103`**. Same 35, one extra **WARM** argument, and the tree holds
exactly **4** `.js`/`.mjs` and **2** `.c` files that the guard routes to `node`/`cc`
(`substrate-check.sh:179-187`). `139 = 138 .bend + 1 foreign file`.

Confirmation that the `.bend` population was identical: the guard's quoted
`unresolved=50`, `dead_import=37`, `BAD 46` are reproduced **exactly** by my run.

The two probe files: `probe_f32lit.bend` is **gone from the tree**; but
`tinybendygrad/runtime/support/am/ip_scratch_sweep.bend` is **still in the tree and
still in the index**. The one `.bend` on disk that is *not* in the index is
`tinybendygrad/test/_probe/v5.bend` — a probe, still there, still counted.

**This denominator has moved four times today**, and the tree moved under a completed
census in this very directory: `guard-run.txt` (05:47) records `.bend handed=136`,
`coldness/census.txt` (06:16) records `on_disk=137`, and it is **138** now.

---

## 3. THE THREE NUMBERS IN CIRCULATION, EACH WITH ITS DEFINITION

| source | claim | what it counts | verdict |
|---|---|---|---|
| `agent-core.md` §2 | **14** of **137** | the guard's HALF 1 `COLD` set, over `.bend` only, on 2026-10-04 | **STALE.** Of its 14 members, **3 are WARM and 11 are still COLD.** Also: 137 was the *index* count, and `COLD`'s denominator was `.bend`-on-disk. |
| `OPSPY.md` | **6** of **137** | the **same** criterion, measured mid-session after `dtype.bend`'s 8 laws were filled | **WRONG, twice.** (i) Its own list removes **9** of the 14 (`ops_python` + `nn/{__init__,optim,state,onnx}` + `zzprobe2` + `dtype_oracle` + `v5` + `dtype`), leaving **5**, not 6. (ii) **6 of those 9 are COLD again — for a different reason.** |
| `substrate-check.sh` | **COLD 35** of **139**, `BAD 46` | `COLD` = HALF 1 string compare; `BAD` = HALF 2 deduped unresolved-name **sites** | **CORRECT on both counts.** `35` reproduces member for member. `139` is a mixed population. |
| `coldness/census.txt` (05:47, this dir) | `red_law (guard COLD)` **97** of 137 | **not** the guard's `COLD`; a graph property mislabelled | **WRONG.** The guard's own `guard-run.txt` from the same hour says `COLD 6`. |

### The sharpest one: `COLD` is not a property of the file it is printed against

`dtype.bend` declared **no `law` at column 0** (0 today, 0 then). Its 8 red items were
its own `def`s' unproven obligations, seen under the name `../dtype.*` from every file
that imported it. When its owner filled them, **9 files went WARM**. Today **6 of
those 9 are COLD again**, because `O.ParamArg.no_slot` is missing from `uop/ops.bend`:

| of agent-core's 14 | today |
|---|---|
| WARM now | `dtype.bend`, `test/dtype_oracle.bend`, `test/_probe/v5.bend` |
| COLD, **same cause as before was retired** | `LAWS.bend` (34 holes), `PROOF.bend` (18), `PROOF2.bend` (16), `runtime/autogen/libclang.bend` (336 foreign defs), `sz.bend` (7) |
| COLD, **new cause** | `nn/{__init__,optim,state,onnx}`, `runtime/ops_python`, `runtime/zzprobe2` — all `O.ParamArg.no_slot` |

**A `COLD` count is a count of red *closures*, so its value is decided by other
files' contents. That is why three units measured 14, 9, 6 and 35 and none of them
was wrong about the day it measured.**

---

## 4. THE TABLE

Full 138 rows × 13 columns: **`.agents/slop/coldness/TABLE.tsv`**. Header:

```
file  imports  importers  reaches_live  imports_nothing  reached_by_nothing
      defs  laws  driven  verdict  shape  symbol  cause_owner
```

| property | count of 138 | definition |
|---|---|---|
| `COLD` (guard HALF 1) | **35** | first line of `--check-only` ≠ `ALL PROOFS CHECK` |
| `reached_by_nothing` | **97** | no other `.bend` file imports it |
| `imports_nothing` | **34** | it imports no sibling `.bend` file |
| `reaches_live` > 0 | **104** | imports ≥1 file that is itself imported by ≥1 file |
| declares ≥1 `law` | **2** | `^law NAME` at column 0: `LAWS.bend` (34), `runtime/autogen/libclang.bend` (335) |
| neither importer nor import | **31** | `indeg == 0 ∧ imports == 0` |
| `driven` | **120** | declares `def main` or `def gate` |
| **COLD (§0's definition)** | **9** | `indeg == 0 ∧ imports == 0 ∧ ¬driven` — all 9 are `__init__.bend` markers with 0 defs |

`reached-by-nothing (97)` and `imports-nothing (34)` are **not** each other, and
neither is `COLD`: `runtime/autogen/libclang.bend` has 335 laws, imports nothing and
is imported by nothing, and it is neither cold nor a defect — it is a driver.

---

## 5. 35 RED FILES COME FROM **15** CAUSES

```
19 file(s)  MISSING-DEF   O.ParamArg.no_slot     declared in uop/ops.bend
 3 file(s)  DUPLICATE     VOP2_ALL               declared in renderer/amd/dsl.bend
 1          HOLES 34 / 18 / 16                   LAWS.bend / PROOF.bend / PROOF2.bend
 2          UNKNOWN-CTOR  AOpLit (x2), Nil       uop/ops.bend / renderer/amd/generate.bend
 1          DUPLICATE     BArg.name               renderer/cstyle.bend
 2          TYPE-MISMATCH S.Dt / Char            renderer/isa/x86.bend, runtime/support/autogen.bend
 1          SYNTAX        ','                    runtime/support/nv/nvdev.bend
 2          FOREIGN       336 / 7                runtime/autogen/libclang.bend, sz.bend
 1          MISSING-DEF   O.s5.d1                 uop/ops.bend
```

**The unit of work is a cause, not a file.** `O.ParamArg.no_slot` is declared
nowhere in the tree; 19 files call it. That is **one** missing def.

### The same law, applied to HALF 2: `BAD 46` is **1 problem**

Every one of the 46 `UNRESOLVED` sites reads `NOT DECLARED IN tinybendygrad/uop/ops.bend`.
**41 of the 46 sites are in `tinybendygrad/uop/validate.bend`, which nothing imports**
(`importers == 0`) — so per this project's own law, **41 findings from one cold file
is 1 problem, and 5 more of the same 1 problem appear in wired files.** The brief
quoted 20 from `validate.bend`; it is **41** now. Either way the denominator is the
point: **46 findings, 1 owner, 2 distinct defects** (`ParamArg.no_slot` + `s5.*`
missing from `uop/ops.bend`; `AOpLit` missing from `uop/ops.bend`).

---

## 6. SO: WHICH NUMBERS WERE WRONG?

- **`COLD 35`** — correct, and it reproduces member for member. Its denominator `139`
  is not a `.bend` count; `138` is.
- **`14 of 137`** — was true on 2026-10-04 and is **11 members still true, 3 dead**.
  A stale snapshot, and its denominator mixed the index count with an on-disk
  population. It is now replaced by §0.
- **`6 of 137`** — **wrong**, against its own arithmetic (5, not 6) and against the
  tree (6 of the 9 it removed are red again for a new cause).
- **`97 "red_law (guard COLD)"`** in `census.txt` — **wrong**; that is a graph
  property wearing the compiler's name, and its own `guard-run.txt` contradicts it.
- **`82 findings`** quoted for the guard — **matches no run in this tree.**
  `guard-run.txt` says `54 finding(s)`; a `-n` run of mine today says `47`.

## 7. THE RULE THAT STOPS THIS RECURRING

**A coldness number may never be written without the sentence that defines it, and
the definition must name (a) the population, (b) the instrument, and (c) whether the
count is over FILES or over CAUSES.** Every disagreement in this file was one of
those three being implicit. The three that bit hardest:

1. **Files or causes.** `35` is files, `15` is causes, and the second is the number
   of things to fix. A count whose value depends on a neighbour's contents is
   measuring the wrong thing.
2. **`--check-only` is not a coldness instrument.** It resolves the whole closure, it
   reports `ALL PROOFS CHECK` for an **empty file**, and it passes a
   collectively-incomplete one. `COLD` is a per-file *parse/proof* verdict.
3. **A denominator taken from a tree under concurrent edit is a timestamp.** 136 →
   137 → 138 in nine hours, all three printed by this project.

---

## 8. REPRODUCE

```sh
zsh .agents/slop/coldness/sweep.sh                                   # 138 bounded --check-only runs
.venv/bin/python .agents/slop/coldness/coldness.py                    # the table + the causes
zsh .agents/slop/substrate-check.sh -n $(cat .agents/slop/coldness/population.txt)   # HALF 2 only
```

`sweep.sh` runs bend through `checks/bounded.py --mb 2048` at `-P 3`. It does **not**
run `substrate-check.sh` itself for HALF 1: that guard invokes bend with
`perl -e 'alarm 300'` (line 200), **a time bound and no memory bound** — the
invocation that took this machine down twice on 2026-10-05. `-n` is safe because it
`continue`s at line 193, before any compiler call.

## 9. FILES

`coldness.py` (one instrument: graph + compiler join + cause collapse) · `sweep.sh`,
`one.sh` (bounded compiler runs) · `TABLE.tsv` (138 rows) · `half2.txt` (the guard's
own HALF 2, today) · `population.txt` · `raw/` (per-file compiler output) ·
`measurements.txt` (today's console output) · `RAW.md` (first-pass notes) ·
`guard-run.txt`, `census.*` (pre-existing in this dir, **superseded** — see §3).