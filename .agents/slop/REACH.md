# REACH — the corpus-wide ops denominator, both sides, and one honest DISAGREE

The unit that took this job changed the differ (684 insertions across `graphcmp.py`,
`graphcmp.bend`, `graphcmp-oracle.py`) and then **completed without a text response**,
leaving 268 KB of probes and no report. Everything below was **measured by the
coordinator afterwards**, against the tree as it stands. Nothing is transcribed.

## The headline, with its denominator

```
graphs in corpus      : 22
ops UPSTREAM (denom) : 77   (measured len(list(Ops)))
reached PY            : 53
reached BEND          : 53
reached BOTH          : 53   <- the honest coverage number
py-only  (bend MISSING): []
bend-only (py MISSING) : []
reached by NEITHER    : 24
```

**35 -> 53, both sides, zero asymmetry.** A coverage number with no
`py-only`/`bend-only` split is not a coverage statement: it cannot distinguish "the
port reaches everything CPython reaches" from "both reach the same wrong subset".
Measured here, both are empty.

The 24 not reached, named:
`ALLREDUCE CDIV CMOD CMPEQ COPY CUSTOM CUSTOMI CUSTOM_FUNCTION FDIV GETADDR INS
MSELECT MSTACK MULACC NEG PROGRAM PYLITERAL REWRITE_ERROR SOURCE STAGE SUB THREEFRY
UNSHARD WMMA`

## AND THE +18 IS NOT THE FIVE NEW GRAPHS — that is the finding

The five graphs added (`alu`, `bit`, `where`, `move`, `flip`) were measured against the
union of what the corpus already reached, op by op:

```
# alu     rows=14  ops=13  NEW=[]
# bit     rows=10  ops=9   NEW=[]
# where   rows=8   ops=7   NEW=[]
# move    rows=22  ops=?   NEW=[]
# UNION of the four: 0 new -> 53+0=53 of 77
```

**Zero new ops from all four candidate families.** So the move from 35 to 53 is
**not** attributable to this unit's work — it came from graphs landed by earlier units
(`bw`, `sym`, `gate`, `lin`, `loop`, `group`, `indexed`, `commute`) whose arrival the
quoted 35 predates.

> **THE 35 WAS STALE, NOT WRONG.** It was a true measurement of an older corpus. This is
> the ordinary failure of a quoted number: nothing about adding graphs invalidates the
> figure, so it survives in notes, in a brief, and in a `LIMITS.md` section until
> somebody re-measures. **A number that was true when written is not thereby still true,
> and a corpus number ages every time the corpus grows.**

## The five new graphs, one verdict and one denominator each

| graph | verdict | nodes | `?` ledger |
|---|---|---|---|
| `alu` | **AGREE** | 14/14 | `?=0 ?=0/6` |
| `bit` | **AGREE** | 10/10 | `?=0 ?=0/6` |
| `where` | **AGREE** | 8/8 | `?=0 ?=0/6` |
| `move` | **AGREE** | 22/22 | `?=0 ?=0/6` |
| `flip` | **DISAGREE** | **6/7** | `?=0 ?=0/6` |

### The field-level `?` ledger is not redundant with the verdict — `flip` is the proof

**All five read `?=0` on both sides and one of them still DISAGREEs.** The ledger
measures *omission* — a field that was never filled — and a graph can be complete and
still wrong. It is the same reason `shared-cores=5` coexists with
`field-mismatches=0` here:

```
# SHARED cores=5  ONLY-PY=1  ONLY-BEND=2  field-mismatches=0  rung2-pairs=0
#   rung3.5-crossrefs=1  zip-truncated=0
```

Every field of every *matched* node agrees, and the graph still has a node on one side
with no counterpart on the other. **"Nothing is missing" is not "nothing is wrong."**

### `flip`'s actual divergence, from the two canonical sides

```
py   6c6,7
< 2:i6 4:FLIP 3:f32 11:(l0:4,l0:3) 2:i0 1:N 8:n(b1,b0) 5:n(i5)
---
> 2:i6 4:FLIP 3:f32 11:(l0:4,l0:3) 2:i0 1:N 8:n(i1,i0) 5:n(i5)
> 2:i7 5:GROUP 4:void 1:R 2:i0 1:N 1:N 5:n(i6)
```

**Two differences, both structural, neither a field mismatch:**

1. **`FLIP`'s shape argument points at a different node class.** CPython: `n(b1,b0)` —
   two *Buffer* refs. The port: `n(i1,i0)` — two *index* refs. The shape is
   `(l0:4,l0:3)` on both sides, but the elements it points at are not the same kind of
   thing, so the port's `FLIP` is reading its bounds from somewhere CPython is not.
2. **The port wraps the `FLIP` in a `GROUP`; CPython emits it bare.** 7 nodes against
   6. This is the `nodes=6/7` denominator and the sole cause of `DISAGREE`.

`file:line` for both is **not yet established** — the differ reports the divergence in
the canonical stream, not in the port source, so locating it is the next step and is
**not** claimed here.

## The claim NOT made

This does **not** mean the corpus compares training graphs, and it must not be
stretched to say so. `bw` is the gradient of **one eager expression**, and the
scheduler/codegen direction is still **forward-only**: `lin` and `loop` DISAGREE on
purpose, for named measured reasons. 53 of 77 is coverage of the **emitter**; it says
nothing about coverage of `schedule -> render -> compile`.

## And the traps this differ has already fallen into, all of which are still live

- **Row counts cannot distinguish two graphs that differ only in which op produced
  them.** The first `g_bw` was the identity PERMUTE: same 32 rows, same 11-op census,
  **every count read it as the same graph.** The ledger caught it (`?` live on 17 of 32).
- **The first float `CONST`** failed on both sides at once — `repr(ConstFloat(1.0))`
  against `F32.show(1.0)` = `1`. Fixed to IEEE-754 bits on both sides, **which is also
  the only spelling that separates two NaNs.**
- **Two identical failures compared equal**, and making differing pairs visible then
  found a truncated file and a 0-byte artefact a summary had called `not-comparable`.
- **`34 of 77` once accepted a non-`Ops` name** — an invented one took it to 35,
  SELFCHECK OK. It now rejects unresolvable names. **Keep that.**
- **`$ALL` still needs `bw:AGREE`**; `graphs-agree=14` should read **15**;
  `LIMITS.md` §2/§5 still carry stale numbers. **None of these six pins is applied.**

## One instruction-level trap, for whoever runs this next

`graphcmp.py` **cannot be run with a bare `python3`**, and the failure is silent:

```
$ python3 .agents/slop/graphcmp.py diff --graph alu
ModuleNotFoundError: No module named 'tinygrad'
```

`sys.path[0]` is the **script's** directory, not the cwd, so the repo-root `tinygrad/`
is not on the path. The runner's own invocation is `P=.venv/bin/python`. Under `zsh`,
`$E`/`$P` do **not** word-split (`command not found: env -u PYTHONPATH ...`), and
`timeout` is **not installed** on this macOS — both failures produce **empty output and
a misleading `rc=0`** when captured to a file. Use `perl -e 'alarm N; exec @ARGV'`.

> **AN INSTRUMENT THAT PRODUCED NOTHING MUST NOT BE REPORTED AS A PASS.** Five runs came
> back `rc=0` with zero bytes on both streams here, and only running the command
> **plainly, in the terminal**, surfaced the `ModuleNotFoundError` underneath. This is
> the same defect as `--check-only` passing an empty file, one layer out.
