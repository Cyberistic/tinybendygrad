# THE THREE VARIABLES, IN THE RUN THAT EXISTS, AND HOW WE KNOW

`checks/env-precond.py` is the instrument. This file is the measurement that justifies it.
Every number here was measured on this tree, on this device, with no `bend` and without
writing to `runs/graphcmp/D/`.

## 1. THE VALUES, AND THE EVIDENCE FOR EACH

Not read from this shell's environment. A shell's env is not a run's env, and the run
happened under a different `DEV` than any shell here has. Each value is read from the
ARTIFACT, so the answer survives the process that produced it.

| variable | value in the run that exists | how we know |
|---|---|---|
| `DEV` | **`NULL` for the census, `CPU` for every graph artifact** | `D0-coverage-census.txt`'s `late` row reads `13/18` and its op-difference set holds `RECIPROCAL`. `D2-canon-py-late.txt` holds **12** rows reaching `FDIV`. Measured directly: `DEV=NULL` makes `late` 13 rows reaching `RECIPROCAL`; `DEV=CPU` makes it 12 rows reaching `FDIV`. One run produced both, so the run is internally split. |
| `PYTHONHASHSEED` | **not set; randomized per process** | Nothing records it — that is the finding. What is knowable: `runs/graphcmp/D` and `.agents/slop/rerun/D-before/` are the same tree and differ on `D0-coverage-census.txt` and on 2 bookkeeping files, and the census difference is 4 `PY-BEND OPs DIFFER` lines differing ONLY in set order. A fixed seed cannot do that. |
| `NOOPT` | **`0`** | The census's `lin` row and `D2-canon-py-lin.txt` both carry the 46-node spelling and the `n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST)))` SINK arg. Measured: `NOOPT=1` emits 45 nodes and `n()`. |
| `LC_ALL` | `C` | `checks/differ.py:47` and `.agents/slop/graphcmp.py:1800` both set it. |

## 2. `DEV` IS NOT LATENT. THIS IS THE FINDING THAT CHANGED THE SHAPE OF THE WORK.

The brief holds that `DEV` "cannot produce a second verdict" because the port fixture pins
`sCPU` and a mismatch exits 2 (`graphcmp.py:2957-2966`). That refusal is real and it works.
It is also **not the only route**, and the route it does not cover is the one that is live:

- `checks/differ.py:47` builds `ENV` with `DEV: "NULL"` and passes it to every child.
- `graphcmp-oracle.py:91` writes `os.environ.setdefault("DEV", "CPU")`. **`setdefault` against
  a key that is already set is a no-op**, and `NULL` is already set — so the census runs on
  `DEV=NULL`.
- Every graph artifact is produced by `graphcmp.py`, which does `os.environ["DEV"] = a.dev`
  at `:2853` with `a.dev` defaulting to `CPU`.

So `D0-coverage-census.txt` is a measurement of a **different graph** than the one the
verdicts are about, and the census is the file that carries the coverage denominator:

```
census   late: 13 nodes, RECIPROCAL   TOTAL 313
DEV=CPU  late: 12 nodes, FDIV         TOTAL 312
```

**The device precondition check at `graphcmp.py:2957` cannot see this**, because the census
calls `emit_py` directly (`graphcmp-oracle.py:108`) and never reaches the device comparison
that `diff` does at `:2958`. A check that runs on one lane and not another is a check whose
coverage is the lane it runs on.

This is also why `graphcmp-oracle.py:148`'s `ORACLE SELFCHECK: FAIL` on the unmapped letter
`C` has a twin: `C` is the letter of the device name `CPU`, and under `DEV=NULL` the letter
is `N`, which is already a mapped atom (`"none"`), so the census reads `N` and the
selfcheck passes. **The census is currently self-checking against the wrong device.**

### WHERE `DEV` IS RECORDED

`runs/graphcmp/D/D0-run-summary.txt`, as four `key=value` lines: `dev=`, `pythonhashseed=`,
`noopt=`, `lc_all=`. That file is already parsed as `key=value` by `gates/retention-check.py`
CLAUSE IV, is read by name by `oracle-repro.sh:61` and `checks/corpus-figure.py:72`, and is
the one file every consumer already opens. A new parser is therefore not needed anywhere, and
the precondition becomes readable by every gate that already reads the run — which is the
property the brief asks for and the reason it is not recorded somewhere private.

## 3. THE SEED LINE, AND WHERE

**`checks/differ.py:47`** — named, not edited (it is not this unit's, and another unit is
re-running it):

```python
ENV = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"LC_ALL": "C", "DEV": "CPU", "PYTHONHASHSEED": "0", "NOOPT": "0"}
```

Two changes on one line, and the `DEV` half is the one that matters: `"NULL"` → `"CPU"`.

**`.agents/slop/graphcmp.py:1800`** — the same declaration in `clean_env`, which is the
environment the **bend** subprocess is launched under, so without it the port side is
unpinned even when the Python side is pinned:

```python
e.update(LC_ALL="C", DEV=dev, PYTHONHASHSEED="0", NOOPT="0")
```

**`.agents/slop/graphcmp-oracle.py:91`** — `setdefault` → assignment, so the oracle stops
depending on its caller's env for the one variable that changes what it measures.

### WHY THE PIN AND THE SORT ARE NOT REDUNDANT

`.agents/slop/preconds/pin-vs-sort.py` measures it, over 5 seeds, on the exact set at
`graphcmp-oracle.py:119`:

```
distinct `set(...)` renderings over 5 seeds : 5
distinct sorted renderings over 5 seeds    : 1
```

- **The pin is a seed.** It makes the line deterministic *on this interpreter*. Pinning to
  `0` fixes this line only by accident of how CPython happens to lay this set out, and
  nothing in the tree would say so or notice it change.
- **The sort is a law.** `sorted(...)` makes the line identical under every seed and every
  interpreter — a property of the output rather than of the machine.

With the sort and no pin, *this* line is stable and the **next** unsorted set print is not.
With the pin and no sort, *this* line is stable only under one interpreter. Both, for
different failures.

## 4. THE SORT AT `graphcmp-oracle.py:119` — DECLARED NOT MINE

That file is a pinned oracle read by artifact name, so it is not this unit's to edit. The
line, and the change:

```python
# :119, today
same = "same" if py["ops"] == bd["ops"] else f"PY-BEND OPs DIFFER: {py['ops'] ^ bd['ops']}"
# :119, wanted
same = "same" if py["ops"] == bd["ops"] else f"PY-BEND OPs DIFFER: {sorted(py['ops'] ^ bd['ops'])}"
```

The file's own comment at `:151-160` claims "Every OTHER iteration of a set in this file is
already `sorted(...)`". That claim is now false and the comment should be corrected in the
same commit, because the comment is what made the omission look like an oversight of
reading rather than the one line it is.

## 5. `NOOPT`: PIN, NOT SCRUB

**`NOOPT` CHANGES WHAT IS BEING COMPARED, so pinning it is right and scrubbing it would be
wrong.**

Measured, with no `bend`:

```
NOOPT unset : lin 46 nodes, SINK arg = n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST)))
NOOPT=1     : lin 45 nodes, SINK arg = n()
```

`n()` is **what the port already prints** for that field. So `NOOPT=1` does not reveal a
disagreement — it *removes the object the disagreement is about*, making `lin` agree by
deleting the `Opt` rather than by the port producing one. `NOOPT=1` on a corpus whose one
recorded DISAGREE on `lin` is exactly that field buys a green run by changing the subject.
That is the argument against scrubbing: a scrub makes `NOOPT=1` *impossible*, which removes
the ability to measure the flag at all, and this project has a rule that a flag whose reach
is unmeasured is a limit that has to be stated rather than deleted.

**Pinned to `0`.** Not deleted, not scrubbed: `NOOPT=0` is the value the corpus's verdicts
were computed under, so pinning it *records the subject*. A scrub would say "this flag does
not exist here" and would be false.

**AND `NOOPT=` (EMPTY) IS A THIRD THING, AND IT IS A CRASH.** `tinygrad/helpers.py:163` is
`type(default)(os.getenv(key, default))`, so an empty string is `int("")`:

```
ValueError: invalid literal for int() with base 10: ''
```

at import. So there are three states — unset, `0`, `1` — plus a fourth that is not a state at
all. Pinning to the literal `"0"` closes all four.

## 6. INJECTIVITY OF THE CANONICAL FORM — MEASURED, AND THE ANSWER IS **INJECTIVE**

`.agents/slop/preconds/injectivity.py`, over all 25 graphs, py side, no `bend`:

```
graphs emitted          : 25 of 25
rows                    : 312
dataclass renderings    : 11
distinct ''-joined strs : 5
distinct ','-structures : 5
COLLISIONS              : 0
```

**The canonical form is injective over every row the corpus reaches.** The `""` join at
`graphcmp.py:672` is a latent defect and not a live one, and the measurement says so with a
denominator rather than by assertion.

The latent defect is nevertheless real, and the grammar probe prints it on the corpus's own
`Opt` spelling:

```
Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))   <- {'op': 'EOptOps.SPLIT', 'axis': 'i2', 'arg': 'n(...)'}
Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))   <- {'op': 'EOptOps.SPLITax', 'is': 'i2', 'arg': 'n(...)'}
```

One string, two field maps. **Nothing in the corpus reaches it**, because no `Opt` field
value is a string that can swallow a field name — the field values are atoms (`E…`, `i2`,
`n(…)`) and the atom alphabet contains no `=`. So this is a **fix-before-it-is-reached**
item, ranked **below** the two pins, and the fix is one character at `graphcmp.py:672`
(`"".join` → `",".join`).

**RANKING, because the brief asked.** The pins rank *above* this, on measured evidence:
`DEV` and `NOOPT` each move a number in an artifact that exists today; the non-injectivity
moves nothing in any artifact that exists today. But it is the only one of the four that
would make a comparison **unsound** rather than merely **non-reproducible**, so it is the
one to fix first once the pins are in.

## 7. WHERE THE PRECONDITIONS LIVE, AND WHY THE OBVIOUS PLACES ARE WRONG

**`checks/env-precond.py`** — one table, `PRECONDS`, read by every consumer.

- **`checks/differ.py` is wrong because it is not mine and it is being re-run right now.**
  It also has the right *shape*: its `ENV` at `:47` is already the single place every child
  environment comes from. So the fix belongs there and is one line; this unit names it and
  does not touch it.
- **`checks/corpus-figure.py` is wrong because it is a CONSUMER.** A precondition declared by
  a consumer is a precondition nobody enforces when the consumer is not run — and
  `corpus-figure.py` is not run by `differ.py run`. It is, however, the right place to
  *report* the declaration next to the figure it qualifies.
- **`gates/retention-check.py` is wrong because another unit owns it** — and because
  CLAUSE IV already reads the run summary, so it gains the check by *parsing one more line
  format it already parses*, not by importing anything.

So: declared in `checks/env-precond.py`, pinned in `differ.py:47` and `graphcmp.py:1800`
(named, not edited), enforced by `checks/env-precond.py --check`, and **recorded** in
`D0-run-summary.txt` so a run can say what produced it. The instrument refuses on the
current tree, which is correct: the tree does not satisfy its own declaration.

```
$ .venv/bin/python checks/env-precond.py --check
METHOD A -- the source lines that build the child environments:
    MISSING  checks/differ.py:47 lacks PYTHONHASHSEED,NOOPT
    MISSING  checks/differ.py:509 lacks PYTHONHASHSEED,NOOPT
    MISSING  .agents/slop/graphcmp.py:1800 lacks PYTHONHASHSEED,NOOPT
METHOD B -- what the run recorded, read with partition('='), no regex:
    MISSING  dev= is not recorded
    MISSING  pythonhashseed= is not recorded
    MISSING  noopt= is not recorded
    MISSING  lc_all= is not recorded
rc=1
```

## 8. THE PLANTS — BOTH HALVES, TWO METHODS

Two gates here failed the second half in opposite directions, so this instrument ships
**three plants with FIXED expectations**, and `--plant satisfied` / `--plant moved` select
which run, never what is asserted:

```
$ .venv/bin/python checks/env-precond.py --plant satisfied   # rc 0
PLANT satisfied      -- MUST exit 0     -> exit 0: CORRECT
PLANT moved-summary  -- MUST exit != 0  -> exit 1: CORRECT
PLANT moved-pin      -- MUST exit != 0  -> exit 1: CORRECT

$ .venv/bin/python checks/env-precond.py --plant moved       # rc 0, same three
```

Two mutation kinds, because **one tokenizer ate a full stop in this project and its own belt
missed the same defect by sharing the assumption**:

- `moved-summary` moves a value **METHOD B** reads (`NOOPT=1` in the summary) → caught by B.
- `moved-pin` **deletes a pin METHOD A** reads (the `NOOPT` pin from `differ.py:47`) → caught by A.

Neither method alone can see the other's defect. METHOD A reads the source lines that *make*
the pins; METHOD B reads the summary's `key=value` lines with `partition("=")` and **no
regex**. A check running only one of them could be satisfied by a lie in the other.

**The plants fabricate BOTH inputs**, and that is a fix: the first version fabricated only
the summary and read the real sources, so `satisfied` could not pass until `differ.py`'s
owner applied the pins — which measures the owner's schedule, not the instrument.

## 9. WHAT COULD NOT BE SETTLED

1. **`PYTHONHASHSEED` for the run that exists is not recoverable as one integer.**
   `.agents/slop/preconds/seed-recovery.py` reconstructs the insertion order from the
   canonical files and searches seeds 0–599. `allred` gives exactly `[329]`; `cdiv` gives
   `[189, 218, 271]`; `flip` is a one-element set so it constrains nothing; and `late`
   returns **NONE**, because the census was made under `DEV=NULL` and the canonical files
   under `DEV=CPU` (see §2) so its two sides are not the sets the census took. **The
   intersection is empty, and that is a finding rather than a failed search**: the artifact
   records a set *print*, a set's order is fixed by seed AND insertion order, and here the
   two disagree about the input. What is established is the thing the pin needs — the seed
   was not pinned, and the tree's two censuses prove it.
2. **`differ.py repro`'s `repro` lane is not measured here.** The brief states it will report
   `D0-coverage-census.txt: 2 runs DIFFER`, 1 of 196. Not re-run: it needs `bend`, and other
   units are compiling. The census diff above is the same fact measured without `bend`.
3. **Whether `DEV=CPU` is the right census device, or whether the port's `sCPU` fixture is
   the thing that should move.** The refusal at `graphcmp.py:2957` says the port is pinned
   at the arena tag 0 and the py side must come to it; on that reading `CPU` is correct for
   both and the oracle's `setdefault` is simply the bug. Settling it needs the port's own
   view, which is another unit's.