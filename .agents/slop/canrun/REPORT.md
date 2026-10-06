# canrun -- which gates CANNOT RUN, and what each one costs to cover

Unit brief: establish which gates are dead, why, and what covering each costs. Nothing here is
committed. Two `checks/` files were edited and both are **executed** below; everything else is
measurement.

Everything is measured under `.venv/bin/python` (bare `python3` is 3.14 here and has no `tinygrad`;
that single fact moved 9 of my own first-pass readings from "broken" to "my harness"). No gate that
compiles `bend` was executed -- 33 of the 92 entry points invoke it and `sz.bend` alone measures
1,383-1,547 MB against a 2,048 MB ceiling.

---

## 1. THE TABLE. Executed, not parsed.

Population: the 92 entry points `gates/gates-pop.py` discovers (I ran it, read its output, changed
nothing; `gates/gates-pop.ledger.tsv` restored). Of 92: **33 invoke `bend` and were NOT run**, 59 were
executed. The 33 are listed in section 7 and are *my* constraint, not a verdict about those gates.

| # | gate | rc | state | exact missing input / cause | still covered by? | answer |
|---|---|---|---|---|---|---|
| 1 | `.agents/slop/helpers-tc-gate.sh` | **1** (was 2) | **CANNOT PASS BY CONSTRUCTION** | none missing. `diff` at `:64` compares a row the oracle emits *expecting* it to differ | no -- nothing asserts `i64_dec` | **4** (needs a design change, see §3) |
| 2 | `checks/gate.py` | **3** | REFUSED | `checks/drive.mjs`, swept `371cc64c9`, recoverable `371cc64c9^:.agents/slop/jsfp8/drive.mjs` | **NO caller at all** (§5) | 3 |
| 3 | `checks/hermetic-census.py` | **3** | REFUSED | `.agents/slop/hermetic/isolate.py`, swept `371cc64c9`, recoverable | no | 3 (already right) |
| 4 | `checks/dup-census.py` | **3** | REFUSED | `.agents/slop/eq/eq-census2.py`, swept `371cc64c9`, recoverable | no | 3 (already right) |
| 5 | `checks/dup-gate.py` | **1 -> 3** | REFUSED (I fixed the caller) | two: `eq/eq-census2.py` swept, **and** `rebase-gate.py:164` imports `loadwatch`, swept from `.agents/slop/loadwatch.py` | no | 2 then 3 |
| 6 | `checks/norm_check.py` | **1 -> 0** | **GREEN** (I fixed the caller) | none -- `.agents/slop/jslane2/gen_f32_seam.py` was present all along | n/a | 2 |
| 7 | `checks/coverage.py` | 1 | cannot run | `portexec/` **does not exist**; `from census import PREAMBLE` falls through to `checks/census.py`, which has no `PREAMBLE` | no | **not mine -- see §9** |
| 8 | `checks/fw_live.py`, `romless.py` | 1 | cannot run | `ModuleNotFoundError: No module named 'common'` -- never a sibling in this tree | no | not gates (drivers) |
| 9 | `checks/cli.py` | 1 | cannot run | `RuntimeError: empty profile` in upstream's viz CLI | n/a | not a gate |
| 10 | `checks/compile.py`, `run.py`, `sz.py`, `llama.py` | 1 | cannot run | `llvmlite` / `hexdump` / `tabulate` / `extra` absent from `.venv` | n/a | not gates (drivers) |
| 11 | `checks/gate_dtype.py` | 2 | cannot run | `error: the following arguments are required: --lane` | n/a | not a gate (driver) |
| 12 | `checks/oracle_f64.py` | 1 | cannot run | `IndexError: list index out of range` -- a real crash, cause not settled | no | **unsettled** |

**Rows 8-11 are not gates.** They are drivers, oracles and wrappers, and they are in the 92 only
because `gates-pop.py`'s `HOMES` is `("checks", "gates")` -- a hand list, which its own author
admits. **That is 9 of 59 executed entries that were never in the population at all**, and it is the
strongest single reason the instrument needed a *run* column rather than another *path* column.

---

## 2. `helpers-tc-gate.sh` -- why it was `rc=2`, and why it is now `rc=1` and still not green

`rc=2` was measured **before** `5bf27ad2f` restored `.agents/slop/helpers-oracle.py`. It is
**Python's exit code for "cannot open the file"**, and I reproduced it exactly:

```
$ .venv/bin/python .agents/slop/helpers-oracle.py.missing ; echo $?
2
```

So `rc=2` was the generator's absence, nothing else. `set -e` (`:27`) stopped the script at `:42`,
the first command that touches it.

The generator is now restored **byte-exact** -- `sha256 776a3fd2f79f4affef02f63ac21fb1602036bf211e38311640dbd856042a70ae`,
identical to `371cc64c9^` -- and runs `rc=0` emitting **237 rows**.

**The gate is not dead. It cannot pass.** All three lanes exist at 237 rows, `bd == bn` byte-identical,
and `rows != bd` on exactly one row:

```
rows:237  d_i64min_d=2147483648:0
bd:237    d_i64min_d=-9223372036854775808
```

And that divergence is **deliberate, in the oracle's own words** (`helpers-oracle.py:286-291`):
CPython's `str(-2**63)` is `-9223372036854775808`, Bend's `I64` cannot hold the magnitude 2^63, so
the oracle prints the port's bit pattern through `dec_limit` (`:315-317`, used at `:324`) *rather
than skipping the row*, "so the disagreement is visible in the diff instead of living in a comment."

`diff "$GT.rows" "$GT.bd"` at **`helpers-tc-gate.sh:64`** therefore returns 1 forever. Under `set -e`
the script exits there.

**Consequence nobody had noticed:** `:66` is
`echo "helpers-tc-gate: $(wc -l < "$GT.rows" ...) shared rows, 3 lanes identical"` -- and
`REVIVE.md:217` cites **`"Re-ran the driver: helpers-tc-gate: 237 shared rows, 3 lanes identical",
rc=0`** as proof the rename was verified against the driver. **That line is unreachable.** A document
reports the output of a line that cannot execute, and three documents cited each other about it.

This is Answer 4, and the exclusion precedent is exact: this row is a `NO BASELINE`, except the
project already has a better-named third state -- `gatekit.py:59` `DEAD = 5`. It is not a failure of
the port, and it must not be counted as 0 agreements either. **Cost to cover:** exempt one row from
the diff by name, or compare with an exclusion list. That is a gate-design decision, not a rename,
and not mine to take.

---

## 3. `gate_norm.py` -- I did NOT take this fix. It is already applied.

`a0e36527b988` ("offrepo") already made it Answer 2, and correctly:
`REPO = HERE.parents[0]` (`:50`), `NORM` at `:51`, `refuse()` at `:54-61` **before** `sys.path`
manipulation and before any import, with the root *proved* by a `pyproject.toml` + `tinybendygrad`
marker check at `:66-68` and the input asserted at `:69-72`. The comment at `:43-49` names the trap
(`parents[1]` is also wrong) and the reason (an assertion downstream of what it asserts cannot make
an exception into a refusal). The instrument reports it `asserts_root=1` on re-run.

**One residue, reported not edited, because I cannot execute the gate (it compiles `bend`):**
`checks/gate_norm.py:199` prints `f"  helper            {HERE / 'canon.py'}"`, i.e. `checks/canon.py`
-- which does not exist. The real helper is `NORM / "canon.py"`. So the gate's own report *names the
wrong helper* in the line that exists to name it. Same class, one level down, in prose.

---

## 4. The THREE dependents of `gate.py` / `jsfix_gate.py` / `both-census.py` -- CONFIRMED, AND TWO ARE DORMANT

| dependent | site | live? |
|---|---|---|
| `checks/abi4_gate.py` | `:93` `OTHER_GATES` -> `:501` `rc_of(REPO / g)` -> **`:541` `("jsfix_gate.py exits 0 against this tree", jg[0] == 0)`** | **DORMANT.** Executed: `abi4_gate.py` exits at **`:305`** (`sys.exit("no backend for arm ...")`) -- 0 bytes of stdout. Lines 501 and 541 never execute. The assertion is real code and is unreachable. |
| `checks/hermetic-census.py` | `:84` `_spec = importlib.util.spec_from_file_location("both_census", _BOTH)`, `ops_of = _bc.ops_of` at `:87` | **DORMANT.** Executed: rc=3 at the `:71-74` refusal, which precedes the `sys.path`/`import` block at `:76-87`. |
| `checks/gate.py` | -- | **NO CALLER EXISTS.** `grep` for a code caller of `checks/gate.py` returns only `gate.py:4`'s own usage line and the prior unit's census tooling (`offrepo/callers.py`, `plants.py`, `where.py`). |

So the brief's "cannot be deleted" holds for **`jsfix_gate.py`** (asserted by `abi4_gate.py:541`) and
for **`both-census.py`** (loaded by path by `hermetic-census.py:84`) -- and both dependents are
themselves broken upstream, so the constraint is currently carrying nothing. **`checks/gate.py` is not
constrained by anything.** It cannot be deleted either, but not for the reason given: it is
unreferenced, so deleting it would be free -- which makes its rc=3 refusal a live cost with no
counterweight, and is worth a decision rather than a shrug.

I did not delete it. Deleting a gate is Answer 3's job and a refused gate is the correct state.

---

## 5. `hermetic-census.py:107,119`'s `rows-*.txt` -- REACHABLE? **NO. Measured.**

Both writes are inside functions (`census()` `:108`, `check()` `:120`). The refusal at **`:71-74`** is
**module-level** and calls `sys.exit(3)`, so it fires at *import* time, before `main()` can reach
either. Executed:

```
$ .venv/bin/python checks/hermetic-census.py --help ; echo $?
== REFUSED, NOT A VERDICT: input absent: isolate.py (... deleted by the sweep 371cc64c9;
   recoverable from git at 371cc64c9^:.agents/slop/hermetic/isolate.py). ...
3
```

`git cat-file -e 371cc64c9^:.agents/slop/hermetic/isolate.py` succeeds, so the provenance is proven.

**So the `.txt` rule is not violated, by luck of ordering, and a file can violate a rule invisibly.**
The correct reading: the writes are latent violations, correctly unreachable. If `isolate.py` were
ever restored without renaming those two writes, `checks/no-txt.py` would fire on a file produced by a
gate that has never been able to run. That is the state the brief describes -- and it is worth a
`TODO` comment in the source rather than a fix here, since editing this file is not my call.

---

## 6. `dup-gate.py:46` -- and the stacking that Answer 2 alone does not fix

`SLOP = HERE.parent` resolved to the **repo root**, so `:56-57` asked for `<root>/rebase-gate.py` and
`<root>/eq/eq-census2.py`. Executed before the fix: **rc=1**, traceback naming the measured path
`<root>/rebase-gate.py`.

It was **not** among the twelve, because it names no `parents[N]` -- the fifth variant, confirmed.

**Fixed (Answer 2):** `REPO = HERE.parents[0]` proved by the `pyproject.toml` + `tinybendygrad`
marker, `SLOP = REPO / ".agents" / "slop"`, `refuse()` before `load()`, both inputs asserted, and the
swept one annotated with its provenance. Now **rc=3**, byte-for-byte the same refusal its
already-fixed twin `checks/dup-census.py` prints.

**The measurement that matters, and it is the argument for the fix being necessary-but-not-sufficient:**
with the root corrected, the *first* input still will not import. `rebase-gate.py:164` does
`import loadwatch`, and `loadwatch.py` was swept too (it was at `.agents/slop/loadwatch.py` at
`371cc64c9^`; only that one line imports it). So:

| layer | input | state |
|---|---|---|
| 1 | the stale root | **fixed by Answer 2** -- was a traceback, now a refusal |
| 2 | `eq/eq-census2.py` | swept, recoverable |
| 3 | `loadwatch.py`, *inside* `rebase-gate.py` | swept, recoverable -- **invisible until layer 1 stopped hiding it** |

Each layer was only visible once the one above it stopped raising. **That is the strongest evidence in
this unit that "the file exists" is not a check: `rebase-gate.py` exists at layer 1, 2 and 3.**

---

## 7. What I touched, and whether it NOW RUNS. Executed, with a two-direction belt.

| gate | before | after | verdict |
|---|---|---|---|
| `checks/norm_check.py` | **rc=1**, `FileNotFoundError: <root>/jslane2/gen_f32_seam.py` | **rc=0** | **GREEN.** `FIXED 5/5 assertions hold   PLANT (repr(float(s)) with no round trip) 4/5` |
| `checks/dup-gate.py` | **rc=1**, `FileNotFoundError: <root>/rebase-gate.py` | **rc=3** | **REFUSED, naming `eq/eq-census2.py` and the commit that swept it.** Still no verdict, and now that is honest. |

`norm_check.py:29` was `HERE.parent / "jslane2"` -- the same depth, a **sixth spelling**. `:69` had it
a second time (`relative_to(HERE.parents[1])`, the repo's *parent*), which did not raise because
`parents[1]` still encloses the path -- so one file carried the off-by-one twice and failed once.

**The belt, two methods that share no regex, on both gates:**

1. **Absent input** -- rename `gen_f32_seam.py`, run: **rc=3**, message names the *input* and its
   git provenance. Restored.
2. **Relocation** -- copy the gate one level deeper (the move that broke it), run: **rc=3**, message
   names the *directory* and says `is not the repo root`.

Both are rc=3, and **the two rc=3s are distinguishable by message**, which is precisely the belt fault
the prior unit recorded in its own `where.py` ("same code, same empty message, opposite verdicts").
Direction 3 is the gate's **own built-in plant**, which fails 1/5 -- so the fixed gate is *shown able
to fail*, and "5/5 hold" is not an assertion that has never failed.

`py_compile` clean on both. `git status checks/` shows only my two files among the concurrent churn.

---

## 8. A `CAN FAIL` column: YES it separates DEAD from GREEN. Measured, and here is the number.

`gates/gatekit.py:59` already owns the vocabulary -- `PASS, FAIL, REFUSED, SKIP, DEAD = 0, 1, 3, 4, 5`
-- so nothing needs inventing. I ran the 59 executable entries once each (`.agents/slop/canfail.py`,
`.agents/slop/canfail.tsv`) and classified each RED by whether a traceback / missing module / missing
file / usage message appears:

```
GREEN 27 · REFUSED 3 · RED 27
RED split:  17 "RAN, verdict is RED"   vs   10 "CANNOT RUN"
```

**A raw `rc` column cannot tell those two apart -- they are both 1.** That is the whole finding: the
number 27 means two incompatible things, and the table in §1 is what separates them.

**And `DEAD = 5` has an exit with no emitter in the population that needs it.** Only the 14 gates that
`import gatekit` can emit it; **all 10 dead gates are not gatekit-based and exit 1 or 2.** So the
vocabulary is defined one layer above the population that would use it.

**Who adds it: `gendirs`** -- it owns `gates/gates-pop.py` and `gates/gatekit.py`. Two constraints,
both measured here:
- it must be a **run**, not a parse. Every number in the existing ledger counts *files*; the 17-vs-10
  split required executing 59 gates.
- **33 of 92 invoke `bend`**, so a population-wide run is gated on the memory ceiling. The honest
  form is a `can_fail` column holding a last-observed `(rc, one-line reason)`, where **an unmeasured
  entry is `SKIP`, never `GREEN`** -- which is the rule `e2e.py:510` (`return 4`) already follows and
  the one the ledger currently has no way to express.

---

## 9. Why five units discovered these by hand, when the instrument exists

This is the finding I was asked for, and it is four things, none of them "the instrument was red":

1. **The instrument has nothing left to say.** Its only defect column, `on_root` ("does the root
   resolve inside the repo?"), now reads **0 across all 92** -- because the twelve were fixed. A unit
   that consults it is told *no problem*.
2. **The column that could have found these fires 21 times to find 3.** `asserts_root=0` has **63
   negatives across 92 entries**, of which **21 name a root**. Measured: exactly **3** of those 21 are
   broken (`dup-gate.py`, `norm_check.py`, `coverage.py`); 18 are healthy. That is the same reasoning
   that excluded `bc-u32`/`wk-cd` as `NO BASELINE` -- *an instrument that fires on everything measures
   nothing* -- and it is why nobody reads the column.
3. **Two of the three are invisible for a *spelling* reason.** Neither names `parents[N]`; both spell
   the same depth as `HERE.parent` / `HERE.parent / "jslane2"`. **I found both by executing every
   gate, not by reading the ledger.** That is the direct argument for §8.
4. **The deepest one.** Every number the instrument reports is a count of *what exists*: 92 paths, 38
   roots, 17 asserts, 196 generated directories. Nothing in it is a count of *what works*. The class
   this whole project keeps hitting is a gate whose **input** was deleted while the gate still named
   it -- and a census of paths cannot see a deleted input, because the path is still there. **The
   instrument records existence; the failure mode is absence.** That is Answer 5's fifth variant, one
   level up, and it is why the number that mattered (17 vs 10) needed 59 executions to produce.

---

## 10. Unsettled, and named so it is not lost

- **33 gates I did not run**, because they compile `bend`. That includes every interesting one:
  `gate_norm.py`, `jsfix_gate.py`, `hermetic-census.py`, `e2e.py`, `differ.py`, `census.py`,
  `both-census.py`. **Their "cannot run" is my memory constraint, not a verdict.** I report no
  defect in any of them.
- **`checks/gate_norm.py:199`** names `checks/canon.py`, which does not exist (§3). I believe it is a
  stale citation and I could not print the line to confirm.
- **`checks/coverage.py` is a new sub-class and I did not touch it.** `:39` inserts
  `HERE.parent / "portexec"` on `sys.path`, and **`portexec/` does not exist** -- the file is at
  `.agents/slop/portexec/census.py`. So `from census import PREAMBLE` falls through to
  `checks/census.py`. **There are 7 files named `census.py` in this tree**, and import resolves by
  path order, not by intent. It fails loudly *only because* `checks/census.py` happens to lack
  `PREAMBLE`; had it had one, `coverage.py` would have silently imported the wrong file. **That is
  strictly more dangerous than a traceback** -- the "gate that will agree with you" shape, one level
  down from `jsfix_gate.py`. The fix is a path fix whose correct destination is a swept tree, so it is
  a call for the `sweep`-owner, not mine.
- **`checks/oracle_f64.py`** dies `IndexError: list index out of range` and I did not settle the cause.
  It compiles `bend`, so I could not run it either way.
- **`dup-gate.py` past layer 3**: whether it produces a verdict if `eq-census2.py` **and**
  `loadwatch.py` are both restored is **not measured**. I did not restore them -- two restorations is
  Answer 1, not Answer 2, and the brief reserves it.