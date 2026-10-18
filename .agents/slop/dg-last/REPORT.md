# `dg-last` — the corpus state as of 2026-10-18T18:51Z: **0 DISAGREE, 1 REFUSED**

**STATIC DIAGNOSIS ONLY.** No `bend`, no `graphcmp`, nothing under `gates/`, no `checks/differ.py`,
no `checks/e2e*`, no `checks/sweep.py`, no `checks/bounded.py`, no `checks/cites-census.py`, no corpus
loop, no pytest/mypy/ruff. Every number below comes from reading artifact TEXT and from one
`ast.parse` of `.agents/slop/graphcmp.py` and one of `checks/differ.py`, via
`.agents/slop/dg-last/census.py` under `.venv/bin/python`. **No existing file was edited.**

| | |
|---|---|
| State read at | **2026-10-18T18:51:03Z** (census re-run), artifacts read 18:49:29Z–18:51:17Z |
| HEAD at 18:49:27Z | `e92adbb5cc1023eb6e2b7e2801a0a7c5e5cd27de` |
| HEAD at 18:51:17Z | `cea5fc2ac5d35010b193840b3617112251e71b13` — *"lanes: a member that PRINTED its own rows as evidence is not a DEAD lane"* |
| Summary artifact | `runs/graphcmp/D/D0-run-summary.txt`, **mtime 2026-10-18T18:22:18Z**, 563 B |
| Run window | the 34 `D1-graph-*.txt` span **18:19:08Z → 18:19:49Z**; the 34 `D2-cmp-*.txt` span **18:19:50Z → 18:20:34Z**; `D2-bytediff.txt` 18:20:34Z |
| Run idle? | newest artifact in `runs/graphcmp/D` is 18:22:18Z, **27 min before the first read**. The run was **not** in flight. |
| Deliverables | `graphs.rows` (34 data rows) · `control.rows` · `summary.rows` · `census.py` |

## 0. THE HEAD MOVED UNDER THIS READING, AND SO DID THE CORPUS

Both are recorded because the brief's premise is that the tree moves.

**HEAD moved inside this unit's own session**: `e92adbb5…` at 18:49:27Z → `cea5fc2a…` at 18:51:17Z.

**The three harness files are AHEAD OF HEAD AND UNCOMMITTED** — `git status --porcelain` (with
`env -u GIT_INDEX_FILE`) answers `MM` for **all three**:

```
MM checks/differ.py
MM .agents/slop/graphcmp.py
MM .agents/slop/graphcmp.bend
```

So the artifacts under `runs/graphcmp/D` were produced by **working-tree** versions of the corpus
harness, not by the versions at `cea5fc2a`. Every finding below is a statement about **that
working tree**, dated. It is not a statement about `cea5fc2a`, and `git status` is the instrument
that says so.

**The git index is ARMED** — `git ls-tree -r HEAD --name-only | wc -l` = **7719** against
`git ls-files | wc -l` = **8806**, i.e. **1087 paths staged beyond the HEAD tree**. Per this
repo's own doctrine an armed index is a wrong tool, not a wrong tree. It does not affect any
number here (every command in this unit was read-only and prefixed `env -u GIT_INDEX_FILE`), but
a reader must know the index was armed when the census was taken.

**Side effect disclosed:** one `jj log -r 'heads(::)'` was run at 18:49:27Z to name the HEAD
symbol. `jj` snapshot the working copy as a side effect of that command. No further `jj` command
was run, and no git command issued here mutates anything.

---

## 1. THE STATE, RE-TAKEN

`runs/graphcmp/D/D0-run-summary.txt`, verbatim:

```
graphs=34            graphs-refused=1     selfcheck=# SELFCHECK: OK
graphs-answered=34   graphs-agree=33      conflations=4 of 4
graphs-unset=0       graphs-disagree=0    controls=5 of 5
expect-moved=0       byte-identical=33    oracle-selfcheck=# ORACLE SELFCHECK: FAIL
not-comparable=0     stable-pairs=5 of 5  census-rc=rc=1
                     stable-failed=0 of 5 stable-differ=0 of 5
                     plants-disagree=7 of 7  cross=1 of 1  dev=CPU  lc_all=C
                     noopt=0  pythonhashseed=0
substrate-start=0ddf34d0da47ce78108337f4a9caddd3f9e49d450c56d5301f3e790b8983dc12
substrate-end=0ddf34d0da47ce78108337f4a9caddd3f9e49d450c56d5301f3e790b8983dc12
```

**The brief's premise — "exactly ONE graph is not agreeing" — holds, and the state has moved off
both prior readings.** The two prior units read `31/2` and `4/29`; the brief quoted `33/1`.
**Today's reading is `33 agree / 0 disagree / 1 refused`.** `expect-moved` is now **0**, where the
prior run reported 3.

**THE ANSWER IS A REFUSAL, NOT A DISAGREEMENT.** `graphs-disagree=0` means **no graph is in the
disagreement set at all.** The single non-agreeing graph is the one the run **REFUSED**, which is
the fifth verdict and not a subset of PASS or FAIL.

**THE RUN IS NOT GREEN OVERALL, AND THE GREEN PART IS NOT THE WHOLE VERDICT.** `oracle-selfcheck=
# ORACLE SELFCHECK: FAIL` and `census-rc=rc=1` are **two red pins of the 17** `checks/differ.py`
counts, while `selfcheck=# SELFCHECK: OK`, `controls=5 of 5`, `conflations=4 of 4`,
`plants-disagree=7 of 7`, `cross=1 of 1` and all three `stable-*` rows are green. The positive
`substrate-start == substrate-end` (both `0ddf34d0…`) is worth recording because the 17:26Z run
that `dg-gate` and `dg-lin` read had them **differ** (`9528bb…` vs `a842e8…`). **So this run's
substrate was stable, and the two prior readings were not.** Neither red pin was investigated —
that is out of scope here and is stated as unexamined, not as benign.

---

## 2. WHICH GRAPH IS NOT AGREEING: **`loop`, AND IT IS REFUSED**

**MEASURED over all 34 artifacts, by exact whole-token label** (never a substring):

- **33** files carry exactly one `# VERDICT: AGREE`
- **0** files carry `# VERDICT: DISAGREE`
- **1** file — `D1-graph-loop.txt` — carries **no verdict line at all**

`gate` reads `AGREE` and `lin` reads `AGREE`. **Both are byte-identical** (§5).

`runs/graphcmp/D/D1-graph-loop.txt` in full, 1074 B, mtime 18:19:08+ Z:

```
# bend attempt 1: 25 rows, ANSWER, rc=0, # root=25 nodes=26 settled=True, stderr: (empty)
# rows py=52 bend=25  CALL nodes py=4 bend=1  device tokens only on py=['N'] only on bend=[]
# PARTIAL FIXTURE: the bend side models 25 of the 52 nodes CPython's graph has (27 unmodelled),
#   and it carries 1 of the 4 `CALL` nodes. A fixture that models part of a graph and emits rows
#   without saying so is a fixture that reports a DIFFERENCE it manufactured, so this is stated
#   here and NOT compared: fix the fixture, or drop the graph, but do not read this artifact as a
#   verdict about the port.
# devices py=['N', 'sCPU'] bend=['sCPU'] -- NOT WELL-POSED, and this is NOT a verdict (exit 2).
#   The port's graph fixture is pinned at the arena tag 0 and the py graph is on ['N', 'sCPU'], so
#   every consumer of the ALLOC would carry a different `core` and the report would be a cascade of
#   `src` differences with the cause in none of them. Re-run with --dev <the name the port
#   resolved> -- or, if the name is not in the port's table at all, that is a port gap to report,
#   not a flag to set.
rc=2
```

**There is no verdict to be wrong, because the run never got to a verdict.** `loop` is not a
port defect and not a disagreement: it is a graph the corpus **cannot compare**.

---

## 3. DOES TODAY'S SINGLE NON-AGREEING GRAPH MATCH EITHER PRIOR DIAGNOSIS? **NO — AND THE ANSWER IS STRONGER THAN "NO"**

The brief asked whether today's single disagreement matches `dg-gate` (`gate`) or `dg-lin` (`lin`),
or is a third cause they missed. **Neither, on two separate counts.**

### 3.1 There is no disagreement today. There is a refusal.

`dg-gate` reported `gate` as `VERDICT: DISAGREE` and `dg-lin` reported `lin` as `VERDICT:
DISAGREE`, both off the 17:26Z run (`graphs-agree=31 graphs-disagree=2`). Today's run reads
**`graphs-disagree=0`** and `gate`/`lin` both read `AGREE` and both are byte-identical. **The
third cause is `loop`, a REFUSED — a state neither prior report diagnosed.** `dg-gate` explicitly
declined it (`loop`'s refusal is out of scope and **UNREAD**); `dg-lin` named it in one clause
(`loop REFUSES`) and did not diagnose it.

### 3.2 Both prior diagnoses were acted upon, in the FIXTURE — verified statically, not assumed

I did not take the green `33/34` as evidence that anything was fixed. I read the two files.

**`dg-gate`'s prescription (Option 1: mint the shape const and name it) — LANDED.**
`.agents/slop/graphcmp.bend:1118` `def g_gate()`, with a comment naming the very defect:

> *"THE SIZE CONST IS A ROW, AND IT IS ALSO ONE OF THE LINEAR'S LINES. CPython's LINEAR is
> `src=n(i1,...,i14)` -- FOURTEEN refs, and `i1` is the `weakint l0:16` that `p0`'s size interns.
> This fixture built that node implicitly, through `UOp.new.param`'s `shape_to_shape_arg`
> (`ops.bend:3036`), so it had no name to put in the LINEAR's src list and the list read THIRTEEN.
> MEASURED: 46 chars of refs against 49, and the ONLY byte difference in the whole graph
> (`runs/graphcmp/D/D2-cmp-gate.txt`, one row)."*

```
+c16 = O.UOp.const(ar, O.CInt{H.i64_of_i32(16)})
+p0   = O.UOp.new.param(O.Found.ar(c16), O.OpsPARAM{}, Some{16}, ...)
```

and the LINEAR's `src` now leads with `O.Found.i(c16)`. `D2-cmp-gate.txt` reads
`gate CANONICAL BYTE-IDENTICAL (py=911 bytes bend=911 bytes)`.

**`dg-lin`'s two prescriptions — BOTH LANDED.** `.agents/slop/graphcmp.bend:1014`:

```
+af = O.UOp.new(O.Found.ar(off), O.OpsAFTER{}, [O.Found.i(c5i), O.Found.i(ra)], O.ANone{}, O.TNone{})
```

and the `g_lin` SINK now ends `O.TNone{}`, carrying the report's own words:

> *"This arm spelled it `O.TInt{1}`, which renders `i1` -- a field difference the differ pairs on
> and which made `lin` DISAGREE for a reason that is the FIXTURE and not the port. Found while
> fixing the split range two stanzas up, and it is the same defect: a hand-built node that does not
> match the row it is supposed to model."*

### 3.3 AND THE PORT-SIDE DEFECT `dg-lin` PRESCRIBED IS **STILL THERE**

This is the finding that matters more than the green row, and it is why `33/34` must not be read as
"the port is fixed".

`dg-lin` §7 prescribed **two** edits for the split range: the fixture (Fix 1.2) **and** the port's
own rule (Fix 1.1). Only the first landed. `tinybendygrad/codegen/late/linearizer.bend:1617-1620`,
read at 18:51Z, still **appends**:

```bend
def cfg_rewrite.new(+ar: O.Arena, ed: RaTb, +x: U32) -> Cg:
  cfg_rewrite.put(O.UOp.new(ar, O.OpsRANGE{},
                            List.append(&2, U32, O.Arena.srcs(ar, x), [tb_get(ed, x)]),
                            O.Arena.arg(ar, x), O.Arena.tag(ar, x)))
```

against `tinygrad/codegen/late/linearizer.py:85`, whose rule wraps the bound:

```python
(UPat(Ops.RANGE, name="x"), lambda ctx,x: x.replace(src=(x.src[0].after(y),)) if (y:=ctx.edges.get(x)) is not None else None),
```

`List.append(srcs, [edge])` — **append, not wrap**. There is still no `O.OpsAFTER{}` anywhere in
`linearizer.bend`. `dg-lin` predicted this exact shape in its own §7:

> *"A fix that moves only `g_lin` will NOT turn the `linearizer_census` gate green, and a fix that
> moves only `cfg_rewrite` will not change `D2-cmp-lin.txt` -- the fixture is hand-written and the
> rule is never driven by the corpus. **They are two defects that happen to agree, which is
> precisely why their agreement was never evidence.**"*

**So `lin`'s green row today measures the FIXTURE, not the port.** The corpus harness transcribes
`g_lin` by hand; `cfg_rewrite` is never driven by it, so no corpus run can see the port-side
defect. `D2-cmp-lin.txt` being byte-identical is **not** evidence that the port's linearizer
matches upstream, and nothing in `runs/graphcmp/D` is.

**I did not run `gates/linearizer_census-gate.py` and I make no claim about its verdict.** The
static claim is narrower and is a derivation from two sources, not a measurement: the rule in
`linearizer.bend` appends where `linearizer.py` wraps.

---

## 4. DIAGNOSIS OF THE THIRD GRAPH: `loop`

`loop` is the third graph, so it is diagnosed the way `dg-gate` and `dg-lin` were: diff
`D2-cmp-<graph>.txt`, find the first semantic difference, locate both definitions, classify.

### 4.1 There is no first semantic difference, and saying so is the finding

`runs/graphcmp/D/D2-cmp-loop.txt`, 2423 B:

```
loop RAW-DIFFERS (py=3086 bytes bend=1482 bytes)
2,3c2,3      … rows 2/3 swapped (PARAM `stl` ↔ `slots` ordering)
5c5          … i5 INDEX src=n(i3,i4) vs n(i2,i4)
8,9c8,9      … py i8 BUFFER / i9 PARAM  vs  bend i8 RANGE / i9 AFTER
11,52c11,25  … py rows 11..52  vs  bend rows 11..25
loop CANONICAL DIFFERS (py=3103 bytes bend=1490 bytes)
1,52c1,25    … the whole canonical file, 52 rows against 25
```

**52 rows against 25. That is a difference of 27 nodes, and it is MANUFACTURED BY THE FIXTURE,
not found in the port.** The first three hunks are renumbering and ordering; the whole of the
divergence is the row-count gap the artifact states itself:

> *"the bend side models 25 of the 52 nodes CPython's graph has (**27 unmodelled**), and it carries
> **1 of the 4** `CALL` nodes."*

There is consequently **no first semantic difference to locate**, and reporting one would be
inventing a subject.

### 4.2 Both definitions

**CPython — `.agents/slop/graphcmp.py:1238` `def g_loop():`**, whose own docstring is the
authoritative statement of the gap:

> *"`hcq_fence(tv, tv, 0)` from tinygrad/runtime/support/hcq2.py:405-413 -- MEASURED at **52** nodes
> on THIS tree (2026-10-18, `runs/graphcmp/D/D2-canon-py-loop.txt`) with the census `CALL=4
> BACKEDGE=1 LOAD=2 STORE=2 INDEX=7 RANGE=1 PARAM=6 BUFFER=3 AFTER=7 CONST=8 CUSTOM_FUNCTION=1
> FLOORDIV=1 AND=1 ADD=2 MUL=2 CMPLT=2 NOOP=1 SINK=2`.*
>
> ***THE `25` THIS USED TO SAY WAS THE BEND FIXTURE's CENSUS, NOT CPYTHON's -- THE SAME DEFECT AS THE
> STALE `34`/`77` PROSE CLAIMS, WITH THE SIDES SWAPPED.** `.agents/slop/graphcmp.bend`'s `g_loop`
> models `hcq_fence`'s own loop body (25 rows, one `CALL`), while CPython's tree carries three more
> `@uopfunc` bodies under three more `CALL`s. The number written next to the graph here was read off
> the FIXTURE and filed as the oracle's, and `cmd_diff` then refused the graph on the device
> precondition and wrote nothing but `rc=2` to `D1-graph-loop.txt`, so `D1-verdicts.txt` printed
> `loop: VERDICT= EXPECTED=AGREE` with an EMPTY cell. The refusal is now printed to stdout with the
> measured gap in it (`# rows py=52 bend=25`, `CALL nodes py=4 bend=1`), and `checks/differ.py`'s
> `graphs-refused` counts it as a REFUSAL rather than as a verdict that moved."*

**the port — `.agents/slop/graphcmp.bend`, `def g_loop() -> O.Found:`**, 25 arena rows ending in
`O.OpsCALL{}` — the fixture for the loop body only.

### 4.3 The refusal mechanism, quoted from the generator

`.agents/slop/graphcmp.py:3366-3393`, `cmd_diff`:

```python
  pdev, bdev = sorted(devnames(py)), sorted(devnames(bd))
  if pdev != bdev:
    …
    print(f"# devices py={pdev} bend={bdev} -- NOT WELL-POSED, and this is NOT a verdict "
          f"(exit 2). …")
    return 2
  rc, txt = report(py, bd, a.plant, equiv=a.equiv)
```

**`report()` is never reached for `loop`, so no `VERDICT:` line is ever printed.** That is the
whole mechanical reason the artifact has an empty verdict cell, and it is why
`checks/differ.py:730`

```python
refused = [g for g in graphs if g in WANT and not verdict(f"D1-graph-{g}.txt")]
```

counts `loop` in `graphs-refused` and **not** in `graphs-disagree` and **not** in `expect-moved`
(`moved` at `:731-732` requires a non-empty `verdict(...)`).

The immediate precondition is a **device-set mismatch**: `py=['N','sCPU']` against
`bend=['sCPU']`, where `N` is the absence token carried only on rows the py side has. The stated
reason it is refused rather than compared is that an `ALLOC` on a different device carries a
different `core`, "which propagates to every consumer and reports as a cascade of `src`
differences **with the cause in none of them**".

### 4.4 Classification

**The refusal itself: `DELIBERATE`, and correct.** `graphcmp.py:250` states the exit contract:
*"Exit status: 0 when the two sides agree … 1 when they do not, **2 when the comparison was NOT
WELL-POSED or a side produced nothing -- which is a FAILURE and never a verdict**"*, and the same
file records the defect this replaced — the 0-row emit that once made `BYTE-IDENTICAL` print for
graphs having compared nothing. Refusing on a precondition it can measure and naming the gap on
stdout is the right shape. **`SKIP IS NOT PASS`, and this is a `REFUSED`: it measured nothing.**

**The underlying cause: `MISSING_CASE`, in the corpus fixture.** Evidence:

1. **27 of 52 nodes unmodelled and 3 of 4 `CALL` bodies absent**, counted by the run itself
   (`# rows py=52 bend=25  CALL nodes py=4 bend=1`) — a gap in the fixture, quantified.
2. **`g_loop` in `graphcmp.bend` models `hcq_fence`'s own loop body only**, stated by
   `graphcmp.py:1238` — a missing case in the transcription.
3. **`checks/differ.py`'s `WANT` expects `loop` to be `AGREE`.** MEASURED by AST: `WANT` holds
   **34 entries and every one is `AGREE`** — `WANT['loop'] == 'AGREE'`. A graph the corpus
   declares comparable is not comparable, so the fixture is incomplete against its own expectation.
4. **It is NOT DELIBERATE as a partial fixture.** `graphcmp.py:3371` calls `loop` *"the corpus's
   one declared-partial fixture"*, and the `g_loop` docstring calls the `25` "the BEND FIXTURE's
   CENSUS … read off the FIXTURE and filed as the oracle's" — both describe the partial state as a
   **defect to correct**, and the artifact's own instruction is *"fix the fixture, or drop the
   graph"*. A deliberate divergence in this corpus carries a marker (`graphcmp.bend:728` marks a
   value "DELIBERATELY 7 and means nothing"; `:778` names `sym` as "disagrees on purpose").
   **`g_loop` carries no such marker.** Being *named* a partial fixture is not being *marked*
   deliberate.
5. **It is NOT `UNKNOWN`.** The cause is three hops from the artifact — row count, `CALL` count,
   the two `g_loop` definitions — and needs no run to establish.

**One sentence: `loop` is REFUSED because the corpus's `g_loop` fixture transcribes 25 of
CPython's 52 `hcq_fence` nodes, which leaves the device sets unequal (`N` on py alone) and trips a
precondition the generator refuses on rather than reporting a manufactured difference; the refusal
is DELIBERATE and correct, and the gap under it is a `MISSING_CASE` in the fixture.**

---

## 5. THE CONTROL — `PASS`, ON ALL SIX CHECKS, WITH DENOMINATORS

`.agents/slop/dg-last/control.rows`, produced by `census.py`:

| check | mine | summary claims | match |
|---|---|---|---|
| population.walked (directory walk of `D1-graph-*.txt`) | **34** | — | — |
| population.declared (`graphcmp.GRAPHS` keys, via `ast.parse`) | **34** | — | **identical sets** |
| `graphs` | 34 | 34 | ✅ |
| `graphs-agree` | 33 | 33 | ✅ |
| `graphs-disagree` | 0 | 0 | ✅ |
| `graphs-refused` | 1 | 1 | ✅ |
| `byte-identical` (aggregate `D2-bytediff.txt` lines, the file the summary counts) | 33 | 33 | ✅ |
| `byte-identical` (independently, per-graph `D2-cmp-*.txt`) | 33 | 33 | ✅ |

`VERDICT control: PASS` (`census.py` exit 0).

**Why this counts as a control and not a restatement.** The population is discovered by a
**directory walk** (`D.rglob("D1-graph-*.txt")`), never by a hand list (doctrine 1), and is then
checked against the **generator's own declaration** — `graphcmp.GRAPHS`, read out of the AST
without importing the module (it is a `Dict` whose values are `Name(id='g_<graph>')` references, so
only the constant string keys are lifted out). The two populations are **equal as sets**, with
`only_in_walk=-` and `only_in_declared=-`. **`34 graphs of 34 declared, 33 agree, 0 disagree,
1 refused, 33 byte-identical — every count has a denominator.**

### 5.1 The substring trap, resolved — and it is NOT in this instrument's needles

The brief warned that `VERDICT: AGREE` is a substring of `VERDICT: DISAGREE`. **MEASURED, that
specific claim is FALSE for these two labels:**

```
'VERDICT: AGREE' in 'VERDICT: DISAGREE'  ->  False
'VERDICT: DISAGREE' in 'VERDICT: AGREE'  ->  False
```

The `DIS` prefix sits between the space and `AGREE`, so neither contains the other. **The
orchestrator's substring error was real but its stated mechanism does not hold for this pair of
labels**, and I checked rather than repeated it.

**What IS true, and is a live latent defect:** `checks/differ.py:962-963` counts with

```python
f"graphs-agree={files_with('D1-graph-*.txt', 'VERDICT: AGREE')}",
f"graphs-disagree={files_with('D1-graph-*.txt', 'VERDICT: DISAGREE')}",
```

and `files_with` (`:497`) is **substring containment over the whole file**:

```python
return sum(needle in f.read_text(errors="replace") for f in D.glob(pattern))
```

So it counts a graph as AGREE if the string appears **anywhere in the file**, including in prose,
and it ignores the operative-label rule that `verdict()` (`:1256`) implements separately — *"The
LAST one, because a report carries the verdict twice and the operative line is the one at the
bottom."* **At this reading the two semantics coincide, and that is measured, not assumed:** the
occurrence histogram over all 34 artifacts is `(agree_hits, disagree_hits) → files` =
**`(1,0) → 33`** and **`(0,0) → 1`** (`loop`), with no file carrying both needles and no file
carrying more than one hit. So substring and exact give the same 33/0 today. **A future artifact
that carried a `DISAGREE` label plus a prose mention of `AGREE` would make the two counters
disagree with each other and with `verdict()`.** That is a derivation from the instrument's source,
not an observed failure.

### 5.2 One coherent run, no mixed generations

All 34 `D1-graph-*.txt` mtimes fall in **18:19:08Z–18:19:49Z**, strictly increasing, one file every
1–2 s; all 34 `D2-cmp-*.txt` fall in **18:19:50Z–18:20:34Z**, strictly after; `D2-bytediff.txt` is
18:20:34Z, the last of the D2 loop; the summary is 18:22:18Z. The census therefore reads **one
run's 34 artifacts**, not a mixture of generations — which matters because `runs/graphcmp/D` also
holds a file from 2026-10-16T22:50:09Z that this unit did **not** read.

---

## 6. THE FULL 34-ROW CENSUS

`.agents/slop/dg-last/graphs.rows`, TAB-separated `graph <TAB> state <TAB> evidence_file`,
**34 data rows**. States are doctrine-2 verdicts: `AGREE`, `REFUSED`. **No `DISAGREE` row exists
because `graphs-disagree=0`.**

```
allred           AGREE     D1-graph-allred.txt          lin              AGREE     D1-graph-lin.txt
alu              AGREE     D1-graph-alu.txt             loop             REFUSED   D1-graph-loop.txt
binblob          AGREE     D1-graph-binblob.txt         matmul           AGREE     D1-graph-matmul.txt
bit              AGREE     D1-graph-bit.txt             move             AGREE     D1-graph-move.txt
buffer           AGREE     D1-graph-buffer.txt          mselect          AGREE     D1-graph-mselect.txt
bw               AGREE     D1-graph-bw.txt              mstack           AGREE     D1-graph-mstack.txt
cast             AGREE     D1-graph-cast.txt            mulacc           AGREE     D1-graph-mulacc.txt
cdiv             AGREE     D1-graph-cdiv.txt            range            AGREE     D1-graph-range.txt
commute          AGREE     D1-graph-commute.txt         rangeflat        AGREE     D1-graph-rangeflat.txt
custom_function  AGREE     D1-graph-custom_function.txt reduce           AGREE     D1-graph-reduce.txt
flip             AGREE     D1-graph-flip.txt            sink             AGREE     D1-graph-sink.txt
gate             AGREE     D1-graph-gate.txt            special          AGREE     D1-graph-special.txt
getaddr          AGREE     D1-graph-getaddr.txt         stage            AGREE     D1-graph-stage.txt
group            AGREE     D1-graph-group.txt           sym              AGREE     D1-graph-sym.txt
indexed          AGREE     D1-graph-indexed.txt         threefry         AGREE     D1-graph-threefry.txt
late             AGREE     D1-graph-late.txt            unshard          AGREE     D1-graph-unshard.txt
                                                            where            AGREE     D1-graph-where.txt
                                                            wmma             AGREE     D1-graph-wmma.txt
```

**Denominators, stated once: 34 graphs declared and 34 walked; 33 `AGREE` of 34; 0 `DISAGREE` of
34; 1 `REFUSED` of 34; 33 `BYTE-IDENTICAL` of 34.**

Per-graph byte-identity was checked independently of the summary: **33 of the 34 `D2-cmp-*.txt`
files carry `CANONICAL BYTE-IDENTICAL`, and `loop`'s has no non-comment line at all.**

---

## 7. LIMITS OF THIS REPORT — WHAT IS *NOT* ESTABLISHED

- **Nothing was run.** No `bend`, no corpus, no gate. Every claim about the port's runtime behaviour
  is a **reading of source**, not a measurement. The `linearizer.bend:1617-1620` claim in §3.3 is a
  derivation from two files; I did not run `gates/linearizer_census-gate.py` and I have no verdict
  for it.
- **Two red pins unexamined.** `oracle-selfcheck=# ORACLE SELFCHECK: FAIL` and `census-rc=rc=1`.
  Neither was investigated and neither is claimed benign. **The green `33/34` is the verdict count,
  not the run's health.**
- **The corpus harness is uncommitted.** `checks/differ.py`, `graphcmp.py` and `graphcmp.bend` are
  all `MM`, so these artifacts describe a working tree, **not** `cea5fc2a`.
- **The index was armed** (8806 staged vs 7719 in HEAD) when the census was taken.
- **One run, one moment.** Every number is stamped 2026-10-18T18:51Z against artifacts written
  18:19–18:22Z, and HEAD moved twice inside this session. `dg-gate` and `dg-lin` each had their
  reading invalidated by exactly this; so has nothing here been *proven* durable, and the honest
  claim is that it is **true now**.
- **`loop` is not a port verdict.** It is `REFUSED` — it measured nothing about the port at all,
  and no row in this report asserts anything about `hcq_fence`'s port-side fidelity.

---

## 8. FILES WRITTEN BY THIS UNIT — all under `.agents/slop/dg-last/`, no `.txt`

| file | what it is |
|---|---|
| `graphs.rows` | **34 data rows.** `graph <TAB> state <TAB> evidence_file` |
| `control.rows` | the control's 14 rows: population, the six count comparisons, the substring check, the verdict |
| `summary.rows` | the full parsed `D0-run-summary.txt` key/value set, so the comparison has its input beside it |
| `census.py` | the instrument; `.venv/bin/python`, `ast.parse` + text reads only, imports nothing from the project |
| `REPORT.md` | this file |

**No `.txt` was created and no existing file anywhere in the tree was edited.**