# 05 — "222 rows" on cstyle

**VERDICT: NOT-A-COUNT as stated. The gate itself is CAN-FAIL, with a real
selftest control.**

## The number is retired

`cstyle-gate.py` no longer produces 222 anywhere. Live, run twice:

```
live port lane rc=0   live oracle lane rc=0
port rows (rows_strict): 227   oracle rows (rows_strict): 224
lane    rows read  names (gate)  names (shipped)  `=`  unreachable  unreadable   name sets
port          227           227              227    0            0           0   IDENTICAL (227 shared)
oracle        224           224              224    0            0           0   IDENTICAL (224 shared)
gated 221   agree 221   disagree []
COVERAGE 221/227 port rows compared to a live CPython call, 0 disagreeing;
         6 declared exclusions.
AGREE
```

**222 appears only in `cstyle-gate.py`'s own docstring**, at lines 180, 209 and
448, and in all three places it is the *retired* parity-reader number:

- line 180: *"the fork's number was `222` against `rows_strict`'s `224`"*
- line 209: *"224 oracle rows as 222, because `kern CUDA  lb=1` and `kern CUDA  lb=4`
  both read as `kern CUDA  lb`"* — the two-`=`-names collision that was fixed by
  renaming.
- line 448: *"can interpret put 9 of the 222 shared rows into disagreement"*

So `222` is a **historical intermediate produced by a reader that has since been
replaced**. The correct current figures are **227 port rows / 224 oracle rows /
221 gated / 6 excluded**.

This is the brief's named trap in its purest form — but inverted from the
instances already on file: here the stale number is *lower* than the truth and
nobody noticed, because 222 was a number the tool once printed and no longer
does. **A count that has been superseded is still quotable until something
scrubs it.**

## The gate's own verdict IS CAN-FAIL, and it carries a control

`cstyle-gate.py --selftest` fires in **both directions**, which is what a control
is for:

```
probe --check-only FIRST LINE: 'ALL PROOFS CHECK'  rc=0  (the exit status is NOT the verdict)
  clean    -> AGREE   gated=['st BASE'] agree=['st BASE'] disagree=[]
  planted  -> BROKEN  gated=['st BASE'] agree=[] disagree=['st BASE']
  refusal  -> AGREE   gated=['st FP8'] disagree=[]  (!KeyError -> "")
  refusal+ -> BROKEN  disagree=['st FP8']  (a name where a refusal was)
SELFTEST OK
  clean    -> AGREE   names eq=0 unreachable=0 disagree=[]
  value    -> BROKEN  names eq=0 unreachable=0 disagree=['st A']
  shape    -> BROKEN  names eq=2 unreachable=0 disagree=[]
  collide  -> BROKEN  names eq=2 unreachable=2 disagree=[]
SELFTEST OK: a planted VALUE leaves the name sets identical ... and a planted NAME
is BROKEN with every value agreeing
```

Two things worth keeping:

- **`--plant st_BASE`** on the live lane → `BROKEN`.
- **The value lane and the name lane are separate checks.** A planted value
  leaves `names eq=0`; a planted name moves `names eq=2` with every value still
  agreeing. That is the fix for the `kern lb=` collision, and it is *proved able to
  fire* rather than asserted.

## Two structural things the gate already gets right, and one it does not

**Right — the oracle is live.** `STALE-LITERAL 0 port `py=` literal(s) disagree
with the live call` and `ORACLE-REFUSALS 13 CPython KeyError(s)`: this lane calls
CPython, it does not read a snapshot. Contrast `sched-cmp.py` (audit 03), which
reads `sched-port.txt` and never runs the port.

**Right — refusals are named.** `UNREPORTED-REFUSALS 0`: every port row that
answers the empty string is one the oracle named on stderr. 13 refusals, 4 of the
compared rows map a CPython `_render_dtype` refusal onto the port's `.get`, and
both are reported rather than absorbed.

**Not established — the 6 exclusions are prose, and prose is not a measurement.**
The six `EXCLUDED` rows are each justified in a sentence, and the justifications
are specific and look right (`buft METAL` needs `bufs=[]` on Metal; the `idx`
`regadd` arm is unreachable because `UOp.arg == Ops.ADD` is False for every
constructible `UOp`; `under` is `str.replace(" ", "_")` and no `DType.name`
contains a space at HEAD). **But there is no assertion that those six are still
excluded for those reasons**, and an exclusion is the cheapest possible way for a
row to stop being compared. `--plant under_float` — planting a row that is
*excluded* — returns `BROKEN`, which is the right answer but for the wrong reason
(the row is absent, not wrong).

That is the one place this lane could go quietly blind, and it is a coverage
claim with no plant.

## Reproduce

```
.venv/bin/python .agents/slop/cstyle-gate.py
.venv/bin/python .agents/slop/cstyle-gate.py --selftest
.venv/bin/python .agents/slop/cstyle-gate.py --plant st_BASE
grep -n '222' .agents/slop/cstyle-gate.py     # the three docstring sites
```