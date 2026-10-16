# `assertlit` — a census of SELF-ASSERTING LITERALS

`.venv/bin/python gates/assertlit-census.py` · `--plant` · writes `gates/assertlit.rows`

## 1. The denominator, and how it was discovered

**A WALK AND A GENERATOR'S DECLARATION. NOT A LIST.**

`gates/gates-pop.py` is LOADED BY PATH for `_homes()` — `gates/gate-surface.py:76`: *"the population
is not a second list, it is `gates/gates-pop.py:discover()`, loaded by path"* — and each home is then
`iterdir()`'d. MEASURED homes: `('checks', 'gates')`.

| class | predicate | count |
|---|---|---|
| ORACLE | `*.py` whose stem carries `oracle` | **78** |
| of which CLAIMED | imports `tinygrad` | **69** |
| of which NOT-APPLICABLE | imports nothing from `tinygrad` | **9** |
| GATE | `*.py` whose stem carries `gate`, ∪ every file whose AST constructs `Gate(` | **98** (97 by stem, +`gates/gatekit.py` by AST) |
| PINS | every `*.rows` in a home | **160** |

Three reads, three shapes, reported separately because merging them is how a denominator becomes a
coincidence. The `Gate(`-by-AST arm is a CONTROL with a number: **1 of 98** — `gates/gatekit.py`, the
shared plumbing every gate imports, whose stem carries no `gate` — was found by the AST and not by the
stem, so the arm earns its place and is a check rather than a correction.

The `NOT-APPLICABLE` nine are named in `gates/assertlit.rows` under the `NOT-APPLICABLE` class.
They are `gates/oracleblind-census.py`, `gates/oracle-census-gate.py`, `checks/oracle-txt-census.py`
and six more: **instruments that CENSUS oracles**. MEASURED, the first full run reported 45 of 78
UNSOURCED, and a third of that was these files' own progress lines being read as expected values.
A census that names an oracle by its FILENAME admits a report about oracles; the discriminator that
matches the question is `tinygrad` in the imports, because an oracle's reason to exist is that it
calls CPython. The leak is named: `gates/autogen-oracle.py` is a real oracle and it imports nothing
from `tinygrad` (its subject is a C header), so the census claims nothing about it. Claiming nothing
is the price of one mechanism instead of a per-file exemption list.

## 2. The table

**ORACLE, 69 claimed, verdict / asserted / computed / unsourced.** Read `asserted` as *"value-region
components not derived from CPython"* and `computed` as *"value-region components that are"*, so a
half-derived row is visible as a row and not hidden behind a boolean.

| verdict | count |
|---|---|
| UNSOURCED | 45 |
| DERIVED | 21 |
| NO-ROWS | 3 |

The 45 split into two classes that must not be added together:

### 2a. CONTROL — 22 oracles, 33 components. NOT DEFECTS.
Every asserted component in these is a bare `int(1)` and nothing else. `gates/tn_sqrt-oracle.py:34`:

```python
print(f"sqrt_is_reachable={int(1)}")   # line 17: "the def is callable (the wall was 0 defs)"
```

The claim is **about the PORT** — that `sqrt` has a reachable `def` — and no CPython expression can
produce it by construction. `gates/runner.py`'s plant precedent applies: a control row must exist or
"every row moved" is unfalsifiable. **22 of 22 files carry one; 11 carry more than one**
(`tn_sin_log2_exp2_rsqrt-oracle.py` has 4). They are the tree's deliberate C-VALUE class.

### 2b. WITH A REAL ASSERTED LITERAL — 23 oracles, 185 components.

| oracle | asserted | computed | unsourced |
|---|---|---|---|
| `checks/render-gate-oracle.py` | 39 | 25 | 35 |
| `gates/beautiful-mnist-oracle.py` | 29 | 17 | 14 |
| `checks/oracle_f64.py` | 23 | 9 | 15 |
| `gates/autogen-oracle.py` | 15 | 1 | 6 |
| `gates/amd_dsl_census-oracle.py` | 13 | 46 | 13 |
| **`gates/op_graph_census-oracle.py`** | **1** | **32** | **1** |
| `gates/fold_graph_census-oracle.py` | 9 | 28 | 2 |
| `gates/state_census-oracle.py` | 9 | 20 | 8 |
| `gates/tn_nodes-oracle.py` | 9 | 0 | 5 |
| `gates/qcom_cache-oracle.py` | 8 | 1 | 7 |
| `gates/realize_graph_census-oracle.py` | 7 | 1 | 7 |
| `gates/onnx_census-oracle.py` | 7 | 91 | 7 |
| `gates/gr_graph_census-oracle.py` | 6 | 11 | 6 |
| `gates/ptx_render_census-oracle.py` | 6 | 17 | 3 |
| `gates/tc_ptx_render-oracle.py` | 5 | 54 | 4 |
| `gates/wgsl_render_census-oracle.py` | 9 | 47 | 4 |
| `gates/linearizer_census-oracle.py` | 4 | 9 | 4 |
| `gates/mixin-op-oracle.py` | 3 | 30 | 3 |
| `gates/ew-explog-oracle.py` | 2 | 0 | 2 |
| `gates/regalloc_census-oracle.py` | 2 | 2 | 2 |
| `checks/rw-gate-oracle.py` | 1 | 54 | 1 |
| `gates/crp_graph_census-oracle.py` | 1 | 13 | 1 |
| **`gates/rand_census-oracle.py`** | **1** | **17** | **1** |

### 2c. GATE divergence literals and PINS — 8 gates / 1425 tokens; 160 `.rows` / 5002 tokens.

A **gate's `print` calls are NOT its expected values** and are not scanned — MEASURED, the first
version did scan them and reported `gates/realize_graph_census-gate.py` with **490** asserted
components, all of them `print(f"--refresh: {PINS.name} rewritten -- {len(rows)} divergences")` and
its siblings. A gate's stdout is a REPORT about its run. A gate's expected values are its `diverges`
and its `.rows` file, and those are what this measures:

| surface | tokens | spelled by CPython | UNSOURCED |
|---|---|---|---|
| 8 gates' inline `DIVERGES` | 1425 | 622 | **803** |
| 160 `.rows` pins files | 5002 | 1354 | **3648** |

**4 451 of 5 427 pin tokens are numbers no CPython expression spells** — node arities and f32 bit
patterns. That is not a defect: a divergence IS a recorded disagreement, and its value cannot be
derived by definition. It is the reason the pins belong in a **diffable file**, which is §4.

## 3. Every `UNSOURCED` value, and what it is

**FOUND A DERIVATION — the value is redundant, not unsourced.** `SOURCED-BY-SUBJECT`: identifier-
shaped and spelled in `tinygrad/**.py`. **NO DERIVATION FOUND — stronger verdict.** The census prints
the holder it found, so "nameable" is checkable rather than asserted.

### THE NAMED INSTANCE, AND IT IS WORSE THAN "TYPED"

`gates/op_graph_census-oracle.py:97`

```python
print("nop=%s," % ",".join("%s:%d" % ("Nzs", x.numel()) for x in o._new_optim_param()))
```

MEASURED, three commands:

```
$ grep -rn "Nzs" tinygrad/ | wc -l
0
$ grep -rn "Nzs" tinygrad/nn/optim.py | wc -l
0
$ .venv/bin/python -c "from tinygrad import Tensor; from tinygrad.nn import optim; \
    print([(x.dtype.name, x.numel()) for x in optim.Optimizer([Tensor([1.0,2.0])],lr=0.1)._new_optim_param()])"
[('f32', 2)]
```

**`Nzs` occurs ZERO times in all of `tinygrad/`.** It is a PORT-ONLY tag —
`tinybendygrad/nn/optim.bend:1059` `case Nzs{sz}: "Nzs"` — and CPython's own derivable name is
`x.dtype.name` = **`f32`**. So:

* `:2` — **COMPUTED** from `x.numel()`. The caller's reading is confirmed.
* `Nzs` — **UNSOURCED**. Driver and oracle agree on a letter **neither computed**, and the correct
  CPython answer is a **different string**. This row is green and is wrong.

The census reads this row as **1 asserted / 32 computed / 1 unsourced** for the whole file.

### THE SECOND `UNSOURCED`, AND IT IS A HOST MODEL

`gates/rand_census-oracle.py:72` — `v &= 0xFFFFFFFFFFFFFFFF` inside `i64pair`, a **host** helper that
projects a Tensor pair to a legible string. MEASURED: `grep -n "0xFFFFFFFFFFFFFFFF\|<< 64\|1 << 64" tinygrad/tensor.py`
returns **nothing**; upstream masks with `num & 0xffffffff` at `tinygrad/tensor.py:466-469` and never
with a 64-bit mask, because its `low`/`high` are `uint32` **tensors** and need no host-side mask.
**UNSOURCED**, and the derivation is not merely missing — the value belongs to a model CPython does
not have.

### THE RESIDUAL, WHICH IS A DIFFERENT SHAPE AND I DID NOT RESOLVE IT

`checks/render-gate-oracle.py:180` and 34 siblings:

```python
row("arg_repr ANone", lambda: repr(None))
```

The oracle *does* run `repr`; the fixture is a **port-shaped literal** rather than a tinygrad value,
so the taint does not fire and the census counts an assertion. `int(1)` and `repr(None)` are both
`Builtin(Constant)` and **statically indistinguishable**, and the difference between them is exactly
the difference between a defect and a fixture. Same shape in `gates/autogen-oracle.py` (6),
`gates/qcom_cache-oracle.py` (7), `gates/realize_graph_census-oracle.py` (7), `state_census` (8),
`linearizer_census` (4), `gr_graph_census` (6), `beautiful-mnist` (14), `ew-explog` (2),
`tn_nodes` (5), `mixin-op` (3). **This is a "found, not done" item, not a finding**, and the 23-row
table above should be read with it attached.

## 4. The pins file, and the provenance of its values

**`gates/op_graph_census-pins.rows` — ADDED. GENERATED, NOT TYPED.**

Provenance, word for word from the file's own header:

> `# op_graph_census-pins.rows -- GENERATED by 'op_graph_census-gate.py --refresh', which is`
> `# its ONLY writer. One TAB-separated TRIPLE per declared divergence:`
> `# '<row>\t<CPython's line>\t<the port's line>'.`
> `# 2 DIVERGENCES of 28 ROWS, 26 OF WHICH AGREE EXACTLY. Both sides are MEASURED from a fresh`
> `# pair of lanes by the refresh that wrote this file; nothing here is transcribed.`

**"DO NOT CREATE ONE WHOSE VALUES YOU DERIVED YOURSELF" — so the values were not derived by me.**
`--refresh` ran both lanes (`op_graph_census-oracle.py` and `bin/bend op_graph_census.bend`) and wrote
whatever DISAGREED. Then the "not a transcription" check, which is the only thing that makes the file
trustworthy:

```
$ git show HEAD:gates/op_graph_census-gate.py > /tmp/old-opgate.py
$ # fold the inline DIVERGES out of the OLD file's AST, compare to the refreshed file
BYTE-IDENTICAL : True
rows: ['mstep', 'vstep'] both sides
```

The measured pins are **byte-identical to the literals the gate asserted inline at HEAD**. Moving them
to a file changed nothing about what the gate believes and everything about whether a reader can see a
moved pin.

**PIN COUNT ASSERTIONS — all updated.** `compared=len(ROWS) - len(DIVERGES)` now reads the LOADED
dict; `no_noop_unpinned()`'s `rows <= set(DIVERGES)` likewise; and `_pins()` refuses when the file and
the declared population disagree. Measured, all three states:

| state | behaviour |
|---|---|
| file present | `compared = 28 - 2 = 26` |
| file MISSING | `REFUSED, NOT A VERDICT … Run --refresh.` **rc=3** |
| `mstep` de-pinned | `REFUSED … declared but not pinned ['mstep']` **rc=3** |
| full run | `rc=0`, `28 rows, 3 lanes, 2 DECLARED divergences`, `WITHIN-LIMITS peak-RSS=1169 MB` |

The full run is `gates/op_graph_census-gate.py` under `checks/bounded.py --mb 2048`, verdict token
read from the token and not the exit code, as `AGENTS.md` requires. `bounded.py` also printed
`MACHINE: **VIOLATED** — loadavg 16.0 on 12 cores`: other units are working, so a time bound here
would not be attributable to this child.

**AND THE CENSUS NOTICED.** `op_graph_census-gate.py` dropped out of the GATE table (80 tokens, 50
unsourced) and `op_graph_census-pins.rows` appeared in the PINS table (+34 tokens, +34 unsourced);
the GATE arm went **9 → 8 files, 1505 → 1425 tokens**. The instrument moved because the tree changed,
in the direction the change was for.

## 5. The plant, and the proof it goes red

`gates/assertlit-census.py --plant` — **12 cases, every one calling the SHIPPED `census_source`,
`verdict` and `component_verdict`**, per `gates/runner.py`'s precedent (its first version reached
past the shipped function into its helpers, and breaking `preconditions`' branch left the plant green).
Plus **2 mutations of real oracles**, because a census that cannot go red on a literal inserted into
a file in this tree is the class it exists to measure.

```
$ .venv/bin/python gates/assertlit-census.py --plant
  control-derived            DERIVED     asserted=0 computed=2   components=-
  asserted-typed-name        UNSOURCED   asserted=1 computed=1   components=UNSOURCED
  asserted-constant          UNSOURCED   asserted=1 computed=0   components=UNSOURCED
  half-derived               UNSOURCED   asserted=1 computed=1   components=UNSOURCED
  fixture-is-not-asserted    DERIVED     asserted=0 computed=1   components=-
  no-equals-row              LITERAL-ONLY asserted=0 computed=0  components=-
  subject-token              ASSERTED    asserted=1 computed=2   components=SOURCED-BY-SUBJECT
  no-tinygrad                UNSOURCED   asserted=1 computed=0   components=UNSOURCED
  bit-pattern                UNSOURCED   asserted=1 computed=1   components=UNSOURCED
  long-asserted              UNSOURCED   asserted=6 computed=1   components=UNSOURCED,SOURCED-BY-SUBJECT,UNSOURCED,UNSOURCED,SOURCED-BY-SUBJECT,UNSOURCED
  compare-is-computed        DERIVED     asserted=0 computed=1   components=-
  label-is-not-asserted      DERIVED     asserted=0 computed=1   components=-
  mutate gates/op_graph_census-oracle.py    UNSOURCED a=1 -> UNSOURCED a=2
  mutate gates/rand_census-oracle.py        UNSOURCED a=1 -> UNSOURCED a=2
--plant: all 12 cases and both mutations OK
```

**THE PLANT CAUGHT THREE REAL DEFECTS IN THE CENSUS, AND EVERY FIX IS A MEASUREMENT:**

1. **It called the named instance wrong.** `asserted-typed-name` first read `2 asserted`, the second
   component being `x.numel()` — the taint did not bind a comprehension's loop variable, so the
   `numel()` the caller measured as COMPUTED read as a typed literal. **The census was wrong about
   the one row two other agents had already read.**
2. **`sourced-in-file` was a branch that could not fire.** It needed to learn what `Ops.CAST.name`
   *evaluates to*, which needs execution, and this census runs **0 subprocesses**. **DELETED** —
   `gates/gatekit.py` spends a paragraph on why ("a constant nothing in this file names is not a
   constant nothing can produce"), and a dead branch reads as coverage on a line that covers nothing.
3. **`int(1)` read `NO-ROWS`.** The unresolved-name predicate counted `int` — a **builtin** — as a
   name the census could not resolve. A census whose blindness list contains the language's own
   vocabulary is measuring its parser.

Four further false positives were found by reading the table rather than by relaxing it: `GATE`
prints read as answers (53 of 98), gates' *own census output* admitted by a filename predicate
(45 of 78), the first `=`-bearing segment not split at the `=` (so `f"typed=CAST"` reported
`0 asserted`), and unresolved names reported as assertions.

## 6. Disjointness from `gates/oracleblind*`

**Static versus dynamic, and the questions are opposites.**

| | `gates/oracleblind-census.py` | `gates/assertlit-census.py` |
|---|---|---|
| method | **DYNAMIC** — perturb a literal, RUN the oracle, diff rows | **STATIC** — read the AST, 0 subprocesses |
| question | does the oracle **DISTINGUISH** two inputs? | does the oracle **COMPUTE** the value at all? |
| population | 98 oracles × gates, GATE-DECLARED ∪ WALK-ONLY | 78 walked, 69 claimed, + 98 gates' `diverges` + 160 pins |
| failure it names | two valid inputs give one answer | the answer is typed, not derived |

`gates/oracleblind.rows`'s `ALL VALID INPUTS AGREE` class is the FIRST question. Mine is the second.
**Neither counts the other, and neither claims it.** An oracle blind to a perturbed input can derive
every value it prints; an oracle that derives every value it prints can still be blind.

The measured overlap is **zero by construction**: oracleblind's verdicts are `SENSITIVE` /
`ALL VALID INPUTS AGREE` / `CANNOT BE PERTURBED` / `IGNORES ITS INPUT`, and this census's are
`UNSOURCED` / `ASSERTED` / `DERIVED` / `NO-ROWS` / `LITERAL-ONLY` / `NO-TINYGRAD` / `UNREADABLE`. No
word is shared, because no question is shared.

One honest caveat: this census did **not** run oracleblind. A full run exceeded 280 s in the caller's
shell, so I read `gates/oracleblind.rows` as committed and did not re-take it. **The disjointness
argument is structural, not a cross-check of two tables I ran together.**

## 7. Found and NOT done

1. **`repr(<port-shaped fixture>)` vs `int(1)`** — §3's residual, ~85 components across 10 oracles.
   Statically indistinguishable, so I left them counted and named them rather than guessing.
2. **`Nzs` is not repaired.** The fix is `x.dtype.name` in `gates/op_graph_census-oracle.py:97` and it
   would make the row go **RED against the port** (`Nzs` vs `f32`), which is a port-side question
   outside this unit's grant. **The oracle and the driver agree and both are wrong; this unit
   measured it and did not move either.**
3. **`checks/render-gate-oracle.py` has 39 asserted, the largest single oracle** — §3's residual.
4. **`Taint` is not scoped.** `bound` is file-wide, so a shadowed name in a nested scope reads as
   defined. It errs by UNDER-counting `asserted`, which is the safe direction and is stated on the
   code. A scoped fixpoint is the fix and was not worth the budget against the residual in (1).
5. **`divergence_literals` is a NAME SHAPE** (`*DIVERGE*`) plus a `Gate(diverges=…)` inline read. It
   is admitted as a lower bound: a gate that hardcodes its expected value in a shape this misses
   contributes **zero**, which under-claims rather than inventing.
6. **`4 451 of 5 427 pin tokens are UNSOURCED and that is not a defect** — §2c. I did not add a
   pins-file census arm beyond the token count, and `crp`/`decomp`/`rand`/`linearizer`/`amd_dsl`/
   `ops_python`/`decomp_value` pins files were not individually attributed.
7. **`.agents/TODO.md` was not touched** (per instruction). The two items for it: repair
   `op_graph_census-oracle.py:97`'s `Nzs`, and the `repr`-fixture class.