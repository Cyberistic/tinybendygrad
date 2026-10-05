# 01 — GROUND TRUTH, measured by this unit, 2026-10-04

Every number below was produced by a RUN in this window, not read from a note. Method matters,
so it is stated. Scratch: `$TMPDIR/nsweep`.

## A. The corpus coverage number

Instrument: `checks/hermetic-census.py --no-publish` — one process per graph,
no cache on the verdict path, `--no-publish` so the measurement writes nothing. rc=0.

```
graphs in corpus       : 24
ops UPSTREAM (denom)  : 77   (measured len(list(Ops)), not read off the enum)
reached PY             : 59
reached BEND           : 59
reached BOTH           : 59
py-only  (bend MISSING): []
bend-only (py MISSING) : []
WALLS                  : []
```

**NOT REACHED, 18 of 77**, derived by me from the census's own per-graph op dicts and
`{o.name for o in list(Ops)}` — NOT transcribed from the brief:

    ALLREDUCE COPY CUSTOM CUSTOMI CUSTOM_FUNCTION GETADDR INS MSELECT MSTACK MULACC
    PROGRAM PYLITERAL REWRITE_ERROR SOURCE STAGE THREEFRY UNSHARD WMMA

18 named, 18 counted, 59 + 18 = 77. The brief's list matches this one exactly, and that is
recorded as a check that passed, not as a source.

## B. The verdicts

Instrument: `env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py diff
--graph <g>`, once per graph, 24 graphs. **`VERDICT: AGREE` on 22, `DISAGREE` on 2** —
`lin` and `loop`, both forward-only on purpose.

`flip` measured: `nodes=6/6`, `ops-reached=5/5 of 77`, `shared-cores=6`, `ONLY-PY=0`,
`ONLY-BEND=0`, `RESIDUALS B=2/0`, `VERDICT: AGREE`. **So `graphs-agree` is 22, and the pin
in `graphcmp-repro.sh` reads 14.**

Per-graph row counts and md5s: 21 of 24 byte-identical, 3 differ — `flip` (AGREE anyway,
`canon_flip` normalises it), `lin`, `loop`.

## C. `--check-only` census over `tinybendygrad/**/*.bend`

```
find tinybendygrad -name '*.bend' | xargs -P 6 -I{} sh -c './bin/bend {} --check-only >/dev/null 2>&1; echo {} $?'

total 137   rc=1: 14   rc=0: 123   (no other rc)
```

The **14 cold files are exactly the 14 in `agent-core.md`'s table**, member for member. So the
numerator and the membership are both CORRECT and only the denominators moved: the bullet said
"14 of the 136 ... and 0 for the other 122".

## D. Commutative ops — a claim that inverted

`[o.name for o in Ops if o in GroupOp.Commutative]` measured = 8: `ADD AND CMPEQ CMPNE MAX MUL
OR XOR`. The corpus's `DENOMINATOR` line now reads `commutative-ops=8` on every graph, and
`CMPEQ` is reached — `late` carries it (`'CMPEQ': 1` in its op dict). `graphcmp-LIMITS.md` §5
says **"SEVEN of the eight"** and asserts *"`CMPEQ` is not reachable from an eager graph at
all ... `CMPEQ` is still 0"*. Both halves are now false: **8 of 8.**

## E. What I did NOT re-measure, and therefore will not restate

`2,419 of 2,421` bend identifiers · `24,583` port defs / `724` upstream-named / `t_` 1,813 ·
`late.bend` 502 defs · `cstyle.bend` "43 reads + 22 hand-written readers" · `5,503` emitted
lines from `bend -o` · `22` phantom blind spots · `841` lines lost · `324`/`323`/`311`
libclang bindings/laws/trampolines · `190+` rules in `bend2-constraints.md` · the e2e stage
count · the ABI-1..7 closure state. These get **STALE**, not a guessed replacement. A note that
was right about `dt_real` is not made wrong by my not re-measuring it, and a plausible number
is worse than an honest one.