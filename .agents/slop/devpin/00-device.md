# 00 — WHAT DEVICE `runs/graphcmp/D` WAS TAKEN UNDER, AND HOW I KNOW

**ANSWER: `DEV=CPU`, on BOTH sides, by the `graphcmp.py` argparse default `--dev CPU`
(`.agents/slop/graphcmp.py:2839`) which `:2853` writes into `os.environ["DEV"]` BEFORE
`load_tinygrad()` — and, independently, because 52 of the 139 artifacts under
`runs/graphcmp/D/` carry the line `# devices py=['sCPU'] bend=['sCPU']`, and every
`ParamArg` row in all 50 `D2-canon-*.txt` files spells its eighth field `sCPU`.**

This is NAMED and it is CORROBORATED TWICE by two methods that share no code path: one
reads the harness's own source, the other reads the run's own bytes.

## EVIDENCE 1 — THE HARNESS SOURCE (a static fact, and it is decisive)

`checks/differ.py` calls graphcmp **exactly one way**, and never passes `--dev`:

```
checks/differ.py:283  def gc(*args, **kw):
checks/differ.py:284      return subprocess.run([PY, GCMP, *args], cwd=ROOT, env=ENV, **kw)
checks/differ.py:452            gc("emit", "--side", side, "--graph", g, stdout=f, ...)
```

`rg -n -- '--dev' checks/differ.py` returns **one** line, and it is a comment
(`differ.py:46`), not an argument. So `--dev` is never supplied, and:

```
.agents/slop/graphcmp.py:2839   ap.add_argument("--dev", default="CPU", ...)
.agents/slop/graphcmp.py:2853   os.environ["DEV"] = a.dev
.agents/slop/graphcmp.py:2854   load_tinygrad()
```

`tinygrad.helpers.DEV` is resolved at IMPORT (`graphcmp.py:277-280` says so and cites the
measurement), and `:2853` runs before `:2854`, so `Device.DEFAULT == "CPU"` for every one
of differ.py's children. **`DEV=NULL` in `differ.py:47`'s `ENV` is dead**: `:2853`
overwrites it in the child before tinygrad is imported.

MEASURED, by calling `graphcmp.py emit --side py --graph lin` under three values of the
**flag** (setting the `DEV` env var proves nothing — `:2853` overwrites it, which is why
my first measurement attempt returned identical output three times):

| invocation                                | rows | `ParamArg` device field |
|-------------------------------------------|------|-------------------------|
| `... --graph lin --dev CPU`               | 46   | `SGLOBAL,sCPU`          |
| `... --graph lin --dev METAL`             | 44   | `SGLOBAL,sMETAL`        |
| `... --graph lin --dev NULL`              | 46   | `SGLOBAL,sNULL`         |

## EVIDENCE 2 — THE RUN'S OWN BYTES (independent of the source read)

`sorted(devnames(...))` reaches the report at `graphcmp.py:2377`, and
`devnames()` (`:1990`) reads `ParamArg`'s eighth field. MEASURED over all 139 `.txt`
artifacts:

```
$ grep -h '^# devices' runs/graphcmp/D/*.txt | sort | uniq -c
  38  # devices py=['sCPU'] bend=['sCPU']  ...
   5  # devices py=['sCPU'] py=['sCPU']     ...   (controls: py against py)
   5  # devices bend=['sCPU'] bend=['sCPU'] ...   (controls: bend against bend)
   4  # devices py=[] bend=[]                ...   (the fixtures that name no PARAM)
   4  # devices py=['N','sCPU'] bend=['N','sCPU'] ...
   1  # devices py range=[] py allred=['sCPU'] ...
   1  # devices bend range=[] bend allred=['sCPU'] ...
```

**`sCPU` is `Scalar[CPU]`, and it is the device of `dtypes.float`, i.e. of the DEFAULT
FLOAT dtype — so it follows `DEV`.** Corroboration from my own measurement, same table:
the field is `sMETAL` under `--dev METAL` and `sNULL` under `--dev NULL`. A run on a
different backend could not have printed `sCPU`.

**COVERAGE OF THE RECORDED SET — the gap, and it is why `corpus-figure.py` cannot read the
device off the run.** Two independent readings, because one regex that matched either would
pass when one of them is empty:

| reading | artifacts |
|---------|-----------|
| carry the `# devices …` header | **52** |
| carry `SGLOBAL,sCPU` inside a `ParamArg` | **52** |
| carry **either** | **99** |
| carry **NEITHER** | **40** |
| total `.txt` under `runs/graphcmp/D` | 139 |

**The 40 that carry nothing include `D0-run-summary.txt`, `D1-verdicts.txt`,
`D0-selfcheck.txt`, `D0-coverage-census.txt`, `D10-zerorow-guard.txt`, `D7-conf.txt`, all
three `D8-*`, `D9-stability.txt`, and — the sharp one — **all 25 `D2-cmp-*.txt`, which are
the files the differ reports its verdicts FROM.**

`D2-canon-*.txt` carry the device anyway, but only *inside the data*:
`45:P(i0,Df32,i20,N,N,N,SGLOBAL,sCPU,b0,N,N,b0,N)`. That is a **derived** record — it is
the thing under test, not a statement about the conditions it was produced under. A gate
that derives the pin from the artifact it is pinning is the thing `AGENTS.md` already
names: *a pin no code consults cannot fail*.

## AND THE THIRD CONFIRMATION: REPRODUCTION, NOT INFERENCE

```
$ for D in CPU NULL METAL PYTHON; do ... emit --side py --graph lin --dev $D | cmp - D2-canon-py-lin.txt; done
--dev CPU     rows=46  IDENTICAL
--dev NULL    rows=46  DIFFERS
--dev METAL   rows=44  DIFFERS
--dev PYTHON  rows=41  DIFFERS
```

**The recorded `lin` artifact is re-emitted BYTE FOR BYTE by `--dev CPU` and by nothing
else.** That is not a reading of the harness and not a reading of the artifacts; it is the
artifact re-deriving itself from the declared flag.

## WHAT IS NOT RECORDED ANYWHERE: THE `--dev` SPELLING

Nothing in `runs/graphcmp/D/` says `DEV=CPU`, `--dev CPU`, or `CPU`. The run records the
device only as the CONSEQUENCE `sCPU`, in two of the five artifact classes, and
`D0-run-summary.txt` — the file `checks/README.md` calls "the run's verdict" — records
nothing about it:

```
$ grep -i 'dev\|cpu\|metal\|device' runs/graphcmp/D/D0-run-summary.txt ; echo rc=$?
rc=1
```

**AND THE SUMMARY IS WHAT `checks/corpus-figure.py:72` READS.** So the instrument already
consults a file that cannot answer the question, and the answer lives only in a default
argument in a file it does not own.

## AND THE PLACE THAT IS ACTUALLY UNPINNED: `checks/corpus-figure.py`

`corpus-figure.py:39-55` imports `graphcmp.py` **BY PATH** and calls `gc.load_tinygrad()`
DIRECTLY. It never goes through `main()`, so `:2853` never runs, so
`os.environ["DEV"]` is whatever the caller's shell happened to hold. **That is the
unpinned comparison, and it is not a hypothetical — MEASURED:**

```
$ for D in CPU NULL METAL; do DEV=$D checks/corpus-figure.py; done
DEV=CPU     CPYTHON-SIDE UNION : 61 of 77      per-graph SUM : 181
DEV=NULL    CPYTHON-SIDE UNION : 60 of 77      per-graph SUM : 182
DEV=METAL   CPYTHON-SIDE UNION : 60 of 77      per-graph SUM : 181
```

**60 on METAL, 61 on the differ's CPU.** Two units flagged this independently and both
were right. `D0-run-summary.txt`'s `RUN HEALTH` line printed **OK in all three**, because
`not-comparable=0` is about *whether the run compared anything* and has nothing to say
about *what it compared against*. **The health verdict is a DIFFERENT QUESTION and it
agrees across all three devices — which is precisely why it cannot be reused as the pin.**

Per-graph, MEASURED (`ops_census` union per graph, plus row count):

| graph   | rows CPU/NULL/METAL | op-set moves? | what moves |
|---------|---------------------|---------------|------------|
| `lin`   | 46 / 46 / **44**     | **YES**       | CPU+NULL: `END,RANGE`; METAL: `SPECIAL` and **no** `END`/`RANGE` |
| `late`  | 12 / **13** / **13** | **YES**       | CPU: `FDIV`; NULL+METAL: `RECIPROCAL`+`MUL`, **no** `FDIV` |
| the other 23 | unchanged    | op-set: no    | **the `ParamArg.device` field moves on 18 of 25** (every `Tensor.empty`) |

**THE 61-vs-60 UNION MOVEMENT IS ENTIRELY `g_late`**: the corpus contains `FDIV` iff the
device's renderer has an `FDIV` arm. `graphcmp.py:1441-1448` already says this in its own
body — "`supported_ops` IS THE DEVICE'S OWN TABLE … **the corpus figure is
device-dependent** — `checks/corpus-figure.py` never pins `DEV`, and this file's `g_late`
is the graph that shows it" — and it was written down and never acted on.
