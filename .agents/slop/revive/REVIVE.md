# REVIVE.md — what was dead, what now runs, and what each fix cost

Companion to `.agents/slop/LANE-LIVENESS.md`. That file is the census; this one records the
repair pass over it and **re-measures every number it touches**. Nothing here is transcribed.

Every measurement below is one of:

| instrument | what it is |
|---|---|
| `rebase-gate.py --port <p>` | the tree's real instrument, live both sides, cross-process |
| `liveness/measure39.py` | runs all 39 `BASE_ORACLES` lanes, imports `rebase-gate.py`'s own `row`/`rows` |
| `.agents/slop/dsl_gate.py` | LIVE-vs-LIVE for `renderer/amd/dsl.bend`, oracle run twice |
| `.agents/slop/drift-gate.py` | three-lane generic driver, cache keyed on the port's sha256 |

Raw captures: `revive/measure39-BEFORE.txt` (after obstacle 1, before the reader fix),
`revive/measure39-AFTER.txt`, `revive/plant-*.txt`, `revive/p6-zerorow.txt`.

Plants were applied to a **copy** at `$TMPDIR/opencode/revive/repo` (`tinybendygrad` +
`tinygrad` + `bin` + `.venv` + `.agents/slop` minus `xd1`, with the editable-install finder
repointed at the copy because `oracle_py.resolve()` refuses otherwise). **The live tree was
never patched from a harness.** Every restored file's sha256 is in the table below.

---

## 1. THE TWO COUNT NUMBERS, BEFORE AND AFTER

Three columns, because the census's "before" and this pass's "before" are **different
measurements** and collapsing them would be the exact error this file exists to prevent. The
census ran with `uop/ops.bend`'s oracle dead (0 shared names); `BEFORE` here was measured
**after** obstacle 1 was fixed but **before** the reader fix, so the ops lane contributes 112.

| | census | BEFORE (this pass) | AFTER | denominator |
|---|---|---|---|---|
| lanes `BASE_ORACLES` enumerates | 39 | 39 | **39** | — |
| port AND oracle both LIVE, cross-process | 37 | 38 | **38** | of 39 |
| …byte-identical, so `disagree` is a tautological zero | 7 | 7 | **7** | of 38 live |
| …a row-value comparison that can actually fail | 30 | 31 | **31** | of 38 live |
| lanes that compared ZERO rows on either side | 2 | 1 | **1** | of 39 |
| lanes RED | 1 | 1 | **1** | of 39 — `codegen/decomp/dtype.bend`, row `c7` |
| shared row names over all 39 | 7,809 | 7,921 | **7,917** | measured, never from a comment |
| …over the 7 byte-identical lanes | 1,408 | 1,408 | **1,408** | of the row above |
| …over the 31 real-value lanes | 6,401 | 6,513 | **6,509** | of the row above |

**38 of 39 wired lanes now run both sides; 31 of those 38 compare values that can differ.**
The 39th is `dtype.bend` and it is a PORT defect, not a wiring one — §5.

The three totals move by exactly the amounts claimed, and both are accounted for:
`7,921 − 7,809 = 112` = the ops lane's shared set going from **0** to **112** (obstacle 1), and
`7,921 − 7,917 = 4` = the four `#shared_axis_*` rows `row()` no longer counts (§3). **Nothing
else moved**, which is the claim §3 has to earn.

---

## 2. OBSTACLE 1 — `uop/ops.bend`'s lane HAD NEVER RUN. Two walls, not one.

**Wall A — `rebase-oracle-ops.py:54`, `NameError`.** The line called
`importlib.util.spec_from_file_location(...)`; the file imported only `os, pathlib,
subprocess, sys`. Measured before the fix:

```
$ DEV=NULL .venv/bin/python .agents/slop/rebase-oracle-ops.py [DANGLING: this instrument was DELETED by the 2026-10-05 prune and is not in git]
NameError: name 'importlib' is not defined. Did you forget to import 'importlib'?   rc=1   0 rows
```

**Wall B — the next line, `NotADirectoryError`.** Not named in the census, found by running the
fix. `pathlib.Path(__file__).resolve() / "rebase-gate.py"` joins a **file** to a name and
yields `…/rebase-oracle-ops.py/rebase-gate.py`. `HERE` on line 39 is already that directory.
**One import fix alone would have left the lane dead with a different message.**

### WHAT THE LANE ACTUALLY PRODUCES, AGAINST THE `# 62` COMMENT

`rebase-gate.py:1771` carried `#  62` next to this oracle. **62 was never measured** — it
described a lane that had never emitted a row. Measured twice, 2026-10-04:

| | value | instrument |
|---|---|---|
| port rows (`interpreted`, `native`) | **315** at load1≈15, 319 idle | `rebase-gate.py --port` |
| oracle rows | **108** | `rebase-gate.py --port`, `rows cpython:rebase-oracle-ops=108` |
| **shared row names** | **108** | both instruments agree |
| disagreements | **0** | both instruments agree |
| verdict | **UNCHANGED**, rc=0 | both instruments agree |

So: **62 → 108**, and the 108 is a set of *distinct names*, all of which the port also prints.

**Where the other numbers come from, because they were the interesting part.** The oracle's own
provenance line, reproduced on every run:

```
#rebase_inner=ops-oracle.py  inner_rows=139 bend_only_families=54 filtered=31 kept=108
```

`ops-oracle.py` prints **198** lines; **139** are `name=value` rows and **59** are `#` comments
(54 of them the `#bend_only_<family>=<reason>` declarations the oracle prints so its filter can
be derived from its own output, 5 others). Of the 139 rows, **31** belong to filtered
`rngarg_*`-style families and **108** survive. `bend_only_families=54` and `filtered=31` were
identical on every one of the 15+ runs; `kept` was 108 on every run after the reader fix.

**`uop/ops.bend` is the root of the import closure for much of this tree**, so every other
lane's denominator inherits from it. It had never been measured at all.

---

## 3. OBSTACLE 2 — `row()` READ 60 COMMENT LINES AS ROWS, AND REPORTED A PORT CHANGE

Found while measuring obstacle 1, not looked for. `rebase-oracle-ops.py` prints its provenance
as `#rebase_inner=…` plus one `#bend_only_<family>=<reason>` per filtered family, and `row()`
split those on their `=` like any other row.

**(a) A count wrong for a structural reason** — the failure `rows()`'s own docstring is about.
The oracle's lane reported **168** rows when the oracle prints **108**.

**(b) Worse: a RE-PORTED verdict that no port change produced.** With the reader as shipped:

```
RE-PORTED  tinybendygrad/uop/ops.bend
           MOVED #rebase_inner: 'ops-oracle.py  inner_rows=82 … kept=67'
                                 -> 'ops-oracle.py  inner_rows=198 … kept=167'
```

The port did not move. **The gate reported a port change it had read off a comment about the
oracle's filter** — and the recorded baseline's value of that comment (`kept=67`) is itself a
measurement of a lane that never ran, so the gate had been comparing provenance text all along.
After the fix the same lane reports **UNCHANGED**.

**Blast radius, measured over all 39 lanes** (`measure39-BEFORE.txt` vs `measure39-AFTER.txt`):

| lane | oracle rows before → after | shared before → after | disagreements |
|---|---|---|---|
| `uop/ops.bend` | 168 → **108** | 112 → **108** | 0 → 0 |
| `uop/spec.bend` | 16 → 11 | **11 → 11** | 0 → 0 |
| `codegen/opt/search.bend` | 20 → 12 | **10 → 10** | 0 → 0 |
| `runtime/ops_cpu.bend` | 20 → 19 | **3 → 3** | 0 → 0 |
| the other 35 lanes | unchanged | unchanged | unchanged (lane 33 still red on `c7`) |

**No lane's disagreement count changed and no lane went red.** The safe direction is structural:
removing a `#`-named key can only shrink the intersection, and a pair whose only shared key
disappears becomes BROKEN ("share NO row names"), never agreement.

**The 4 lost shared rows are named, not assumed**: `#shared_axis_count`,
`#shared_axis_members`, `#shared_axis_sorted`, `#shared_axis_values`. `ops-oracle.py:13-14`
already excludes them with `grep -v '^#shared'`, so the reader now applies **the project's own
established convention** rather than a new judgement. They agreed while they were counted.

---

## 4. OBSTACLE 3 — "0 DISAGREEMENTS" IS NOT A COVERAGE STATEMENT, AND ONLY ONE LANE SAID SO

`rebase-gate.py` never reported byte-identity. Measured on 7 of 38 live lanes, both sides print
**the same sha256**, so `disagree` compares a string with itself and is 0 **whatever the port
prints** — 1,408 shared row names whose green cannot be earned by a value comparison. Only
`llvmir-gate.py:24-32` said so, and only inside its own gate; the instrument that runs all seven
said nothing.

`stamp_text()` now gives every lane its own `sha256` / byte count / line count, and the verdict
prints, on **green and red runs alike**:

- `⚠ TAUTOLOGICAL <cpython lane> vs <port lane>` — byte-identical, `disagree` cannot fail here;
- `SELF-IDENTICAL <port> vs <port>` — the compiled lane reproduces the interpreter. Reported
  separately because **it is not a corroboration**: both sides are the same port, so no CPython
  claim is involved. Counting those names was a defect in my own first version of the stamp and
  is corrected here — see §7.
- `⚠ N of M shared row name(s) … green is BY CONSTRUCTION`.

---

## 5. OBSTACLE 4 — `dtype.bend`: A PORT DEFECT, REPORTED AND NOT PAPERED OVER

`./bin/bend tinybendygrad/dtype.bend` → **rc=1, 0 stdout lines**, stderr:

```
SOME PROOFS FAIL
Error: 14 defs rely on unsafe or foreign code:
- Dt.bf16  - Dt.fp16  - Dt.fp8_from  - Dt.fp8_to  - Dt.i64_trunc  - Dt.i64_floor_div
- Dt.i64_floor_mod  - Dt.i64_cdiv  - Dt.i64_cmod  - Dt.i64_ceildiv
- float_to_bf16  - float_to_fp16  - float_to_fp8  - fp8_to_float
```

**This is a PORT gap and no harness change can fix it.** `tinybendygrad/dtype.bend` is under
single ownership and was not edited. The 14 names are `Dt.*` and the four `float_*`/`fp8_*`
conversions, i.e. exactly the `F16`/`I64`/`F64`/`U64` constructors Bend 2.0.34 has no syntax
for. `dtype.bend` is the LANE, and its oracle
(`.agents/slop/oracle/dtype_tables.py`) emits **14,774 TAB-separated lines** so `rows()` finds 0
by the whitespace rule — that part is deliberate and correct, and
`rebase-gate-selftest.py`'s PART 3b asserts it.

**So `dtype.bend`'s lane compares nothing for two independent reasons, one on each side.** The
honest statement is the one above, not a workaround.

**The wall that cost an agent ten minutes is now named precisely.** `agent-core.md` said
"`--check-only` exits 1 even when the file is fine … The file run itself exits 0." Measured over
all 136 `.bend` files: **14 exit 1, 122 exit 0**, and the split is not the one the sentence
implied.

| files | `--check-only` | plain run | why |
|---|---|---|---|
| `dtype.bend` | 1 | **1** | its own 14 unfilled laws |
| `sz.bend` | 1 | **1** | its own 7 foreign defs (`Sz.read_dir`, `Sz.is_dir`, …) |
| `runtime/autogen/libclang.bend` | 1 | **1** | `duplicate declaration: U32` — a real defect |
| `LAWS.bend` (34 TODOs) · `PROOF.bend` (18) · `PROOF2.bend` (16) | 1 | **1** | unfinished proof |
| `nn/__init__.bend` · `nn/optim.bend` · `nn/state.bend` · `nn/onnx.bend` · `runtime/ops_python.bend` · `runtime/zzprobe2.bend` · `test/dtype_oracle.bend` · `test/_probe/v5.bend` | 1 | **0** | `../dtype.Dt.bf16 …` inherited |

**The old sentence is true for those 8 and wrong for those 6.** Three of the 8 are
`BASE_ORACLES` ports (`nn/__init__.bend`, `nn/onnx.bend`, `runtime/ops_python.bend`), so any
harness that reads a non-zero bend exit as a dead lane calls three LIVE lanes dead.
`rebase-gate.py` reads stdout rows and is unaffected.

**Also corrected: the bend in this tree is 2.0.34, and 2.0.35 is AVAILABLE, not installed.**
`bin/bend` execs `references/bend/bend2/main.ts`; `--help` prints `Bend 2.0.34` and every
failing run prints `bend 2.0.35 is available: run bend update`.

---

## 6. THE FOUR `*-gate.py` FILES THAT ARE NOT GATES

| file | what it really is | what was done |
|---|---|---|
| `helpers-tc-gate.py` | **not a program.** 199 lines of recorded `name=value` rows (`trange_0_len=0`), raising `SyntaxError: invalid syntax` at `trange_0_seq=`. It is the *output* of `helpers-tc-gate.sh`, whose `GT=` prefix made it write `$GT.py` **into the repo**. | **RENAMED** to `oracles/helpers-tc-gate.rows` (+ `.rows.err`), and `helpers-tc-gate.sh` now writes `$GT.rows`. Re-ran the driver: `helpers-tc-gate: 237 shared rows, 3 lanes identical`, rc=0. `.bd`/`.bn` keep their names — those extensions name no language. |
| `drift-gate.py` | a real driver that **served `$TMPDIR/drift-gate-cache/<stem>.{native,cpython}.txt` by default**, so a default run compared a live port against rows a different revision produced. | Cache is now **keyed on the port's sha256**, so a stale entry is unreachable; every served-from-cache lane says so on stdout; `--no-cache` forces a live run; `-r` also rebuilds. Also pinned through `oracle_py.resolve()` so it inherits the L-11 refusal instead of using `sys.executable`, and its `--check-only` note was corrected to the 14/122 table above. |
| `nv_gate.py` | **appends a gate body from `$TMPDIR` into the live port** (`GATE = $TMPDIR/opencode/gate.bend`, `:8,19`). A mutator with a scratch-dir payload. | **NOT MINE — reported, not edited.** Shortest honest path: put the block in `.agents/slop/` (oracles live there per `agent-core.md`) and make it idempotent on a content hash, not a sentinel row. |
| `checks/reorder-gate.py` | **rewrites a `.bend`** (`open(path,'w')`, `:109`). A code-mover wearing a gate's name. | **NOT MINE — reported, not edited.** It should be renamed; a file called `-gate` that rewrites the port invites exactly this miscount. |

**Six emitters have no driver at all** — `mm-gate`, `mm-bl-gate`, `mm-dt-gate`, `mm-walk-gate`,
`state-gate`, `nn-gate`. `.agents/slop/LANE-LIVENESS.md:190,194` already records each as
**NOT A GATE**, which is the accurate place for that and is left as-is.

---

## 7. THE PLANT / DISARM MATRIX FOR THIS PASS

Every plant was applied to the `$TMPDIR` copy. **Every plant must move a number and every
disarm must not.**

| # | change | PLANT | moved? | DISARM | moved? | ARMED |
|---|---|---|---|---|---|---|
| 1 | `row()` refuses a `#`-named row | `dsl_oracle`/`ops-oracle` provenance comment is read as a row | **YES** — oracle 168 → 108 rows, and the phantom `MOVED #rebase_inner` RE-PORTED verdict **disappeared** (that is the plant: the port never moved and the gate said it had) | a lane whose oracle has no `#` rows (`device.bend`) | **NO** — 23 shared, 0 disagree, identical | **ARMED** |
| 2 | tautology stamp in `rebase-gate.py` | `llvmir.bend:981` `r_lt("lt f32", S.single(), "float")` → `S.double()` | **YES** — `BROKEN / DISAGREE 'lt f32'`, and **both oracle `⚠ TAUTOLOGICAL` lines and the `470 of 470 BY CONSTRUCTION` line VANISHED**. The stamp is a measurement, not a list. | value restored + a comment appended | **NO** — sha back to `258d7de0cf72f6bf…`, both lines and `470 of 470` RETURN | **ARMED** |
| 3 | `dsl_gate.py` zero-row guard | `dsl.bend:1734` → `nat_text(reg_names_n() + 1n)`, which does **not compile** — the census's own lane-E red-for-the-wrong-reason | **YES** — the old gate said `rows port=0 mismatched=1576`; the new one says `THE PORT PRODUCED ZERO ROWS … rc=1 … NOT A DISAGREEMENT`, prints the offending line, **rc=2** | pristine restored | **NO** — back to `VALUES-DIFFER=0`, rc=0 | **ARMED** |
| 4 | `dsl_gate.py` still compares values | `dsl.bend:1734` → `"99"` | **YES** — rc 0 → 1, `VALUES-DIFFER=0 → 1`, `MISMATCH names_count` named | value restored + a comment appended | **NO** — rc=0, `VALUES-DIFFER=0` | **ARMED** |
| 5 | `drift-gate.py` cache keyed on the port sha256 | a **comment** appended to `device.bend` — changes the bytes and nothing else | **YES** — `CACHE KEY edc4d46b… → d32673ea…`, both cached lanes went `ran LIVE`, and the previous revision's entries became unreachable. Under the old code this same edit served the **old revision's rows silently**. | re-run with no edit | **NO** — key identical, lanes `served from cache edc4d46b403ff317`, verdict byte-identical | **ARMED** |

### A correction to my own stamp, found by the plant

The first version counted `interpreted` vs `native` toward "green by construction". Under the
llvmir plant it printed `470 of 470 shared row name(s) are green BY CONSTRUCTION` **while
`lt f32` was disagreeing**. Two runs of the same port corroborate each other; they do not
corroborate the port. The stamp now counts only pairs containing a `cpython:` lane, and reports
the port-vs-port case separately as `SELF-IDENTICAL`.

**A caveat that survives the event it is a caveat about is a caveat about nothing.**

### One plant that was vacuous, and the gate was right

While measuring `uop/ops.bend` I read `inner_rows=198` and `inner_rows=139` from two runs and
took it for nondeterminism in `ops-oracle.py`. It was not: both numbers were the same
measurement through two different **row readers** — the second run went through the fixed `row()`.
The oracle was deterministic throughout. Had I reported "the ops oracle drops 59 rows under
load" it would have been a false finding, and I only caught it because the two counts had a
mechanism I could name.

### Restored files, sha256

| file | sha256 | note |
|---|---|---|
| `…/revive/repo/tinybendygrad/renderer/llvmir.bend` | `a358a2050ce54983…` → plant → restored + comment → `4896c5ab45614323…` | the disarm state |
| `…/revive/repo/tinybendygrad/renderer/amd/dsl.bend` | `202de0e8ac053481…` → plant ×2 → **restored to `202de0e8ac053481…`** | exact |
| `…/revive/repo/tinybendygrad/device.bend` | `edc4d46b403ff317…` → comment → restored to **`edc4d46b403ff317…`** | exact, and equal to the live tree's |
| `.venv/…/__editable___tinygrad_0_14_0_finder.py` | repointed at the copy, then **restored**; `oracle_py.py` re-accepts | verified both directions |

---

## 8. `dsl_gate.py` — A LANE THAT WAS VALUE-GREEN AND REPORTED VALUE-RED

The old summary line read `rows port=1161 oracle=1576 matched=617 mismatched=1503`, and
1503 > 617, so it could not be read as a disagreement count. Measured against a **live** oracle:

```
port 1161 · oracle 1576 · 617 shared · 0 of the 617 differ · 959 oracle-only · 544 port-only
```

`959 + 544 = 1503`. The lane was **value-green and set-red**, and one number hid it. It is now
three numbers with three names, and the verdict line says the set differences are not
agreement about them.

`dsl_gate.py` also compares against a **live** oracle run **twice** now, and excludes any row
whose value differs between the two launches — which catches `oracles/dsl_oracle.txt:1604`'s
`fixed_hilo=<…FixedBitField object at 0x10911a510>.hi,0` heap address with **no name list**.
MEASURED: the live oracle differs from the recorded file on exactly one line, `fixed_hilo`, and
two consecutive launches differ from each other on that same one line and on no other. That is
the generalisation of `BASE_ORACLES`' name-based `elf_built_*` exclusion, done by measurement.

---

## 9. WHAT I DID NOT DO, AND WHY

* **No `.bend` under `tinybendygrad/` was edited.** Every plant was applied to
  `$TMPDIR/opencode/revive/repo` and restored; sha256 above.
* **Nothing committed.** Working copy only.
* **`nv_gate.py`, `checks/reorder-gate.py`, `dtype_tables.py`, `dtype.bend`** are other units'
  files. Reported with `file:line` and the shortest honest path, not edited.
* **`codegen/decomp/dtype.bend` is still RED on `c7`** (`refused:unported` vs `F(2139095040)`),
  reproducibly, on a plant of its own. Untouched here.
* **`renderer/llvmir.bend`'s lane reads RE-PORTED at rest**, before and after this pass. That
  is pre-existing baseline drift against `oracles/rebase/baseline.json`, not a consequence of anything
  in this file; it is recorded rather than explained because I did not run it down.
* **Row counts on `uop/ops.bend` are lower bounds**: load1 was 15–26 for most of this pass, so
  every verdict carrying it printed its own `STARVED` marker and said so.