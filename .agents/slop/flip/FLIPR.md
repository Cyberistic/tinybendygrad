# FLIPR -- the one real DISAGREE, `flip` at 6/7, located and closed

Rule prefix **`FLIPR`**. Claims `.agents/slop/graphcmp.py`, `graphcmp.bend`,
`graphcmp-oracle.py` (see `CLAIM.md`). Nothing committed. Nothing outside those
three files touched.

---

## 1. THE TWO `file:line`s

| # | difference | where it is minted | whose defect |
|---|---|---|---|
| **A** | the extra `GROUP` wrapper | **`.agents/slop/graphcmp.bend:1274`** | **the differ's fixture** |
| **B** | `FLIP`'s arg atom `b` vs `i` | **`.agents/slop/graphcmp.bend:1273`** (spelling) over **`tinybendygrad/uop/ops.bend:1066`** (the vocabulary) | **neither the graph's** — a port vocabulary gap, over-reported |

### A. The GROUP

**CPython has no GROUP here, and that is not a presentation choice — it is a rule.**
`tinygrad/uop/ops.py:558-560`:

```python
def group(*srcs:UOp|None, **kwargs):
  if len(srcs) == 1 and isinstance(srcs[0], UOp): return srcs[0]
  return UOp(Ops.GROUP, src=tuple([x for x in srcs if x is not None]), **kwargs)
```

**THE PORT HAS THE SAME RULE, COMMITTED, AT `tinybendygrad/uop/ops.bend:2486-2495`:**

```
def UOp.group.of(srcs, ar, nar) -> Found:
  match srcs:
    case Nil{}: Found{nar, 0}
    case s <> t:
      match t:
        case Nil{}: Found{ar, s}          <-- the elision
        case _ <> _: UOp.new(nar, OpsGROUP{}, srcs, ANone{}, TNone{})
```

So the port was never wrong. **The fixture was**: `g_flip` built the root with
`O.UOp.new(..., O.OpsGROUP{}, [fl], ...)` — reaching past the port's own `UOp.group`
to the raw constructor, so the singleton arm never ran.

MEASURED (`.agents/slop/flip/py-probe.py`), calling CPython:

```
UOp.group(a.flip(0).uop).op        -> Ops.FLIP      (root is the FLIP itself)
UOp.group(fl, fl).op               -> Ops.GROUP
UOp.group().op                     -> Ops.GROUP  nsrc 0
len(UOp.group(fl).toposort())      -> 6, GROUP count in census: 0
```

**AND THE TWO IN-CODE CENSUSES THAT SAY `GROUP=1` ARE BOTH STALE.**
`.agents/slop/graphcmp.py:1355` and `.agents/slop/graphcmp.bend:1241-1242` both print
``census `ALLOC=1 CONST=2 FLIP=1 GROUP=1 RESHAPE=1 STACK=1` ``. Measured: **there is
no GROUP**. That stale number is where the `7` in `nodes=6/7` came from, and it is why
the task brief's "make it read AGREE at 7/7" cannot be the target: **the py side has 6
nodes and always did.** The corrected denominator is **6/6**.

### B. The `arg` atom

**First: the brief's reading of this one is wrong, and the correction matters.**
The brief says py `n(b1,b0)` is "two **Buffer** refs". It is not. `ATOMS` is
`graphcmp.py:324-326`; `bool -> b`, `buf -> z`, `u32 -> i`. So `n(b1,b0)` is **two
booleans**, `(True, False)` — the flip-axis flag tuple — and `n(i1,i0)` is the **same
two values** spelled `u32`. **The shape is not involved at all**: `shape=(l0:4,l0:3)`
agrees on both sides. Nothing is "reading bounds from index refs where CPython reads
buffers".

MEASURED (`py-probe2.py`):

```
a.flip(0).uop.arg      -> (True, False)      types ['bool','bool']
tuple(int(x) for x in arg) == (1, 0)         -> True
```

Upstream types it `tuple[bool, ...]` (`mixin/movement.py:253`,
`flip_arg = tuple([i in axis_arg for i in range(len(self.shape))])`) and **refuses
anything else** at `tinygrad/uop/ops.py:428`:

```
UOp(Ops.FLIP,(au,),(0,)).shape         -> ValueError: bad flip on (4, 3), (0,)
UOp(Ops.FLIP,(au,),(1, 0)).shape       -> ValueError: bad flip on (4, 3), (1, 0)
UOp(Ops.FLIP,(au,),(True, False)).shape-> (4, 3)
```

The port cannot spell a bool: `tinybendygrad/uop/ops.bend:1066`
`ATuple{ys: List<&2, U32>}`, its own table at `:1031` reading `tuple[int, ...]
PERMUTE/FLIP arg`. `graphcmp.bend:1273` writes `O.ATuple{[1, 0]}`, which is all the
type allows. `uop/fold.bend:6488-6492` **already records this**, by name.

**THE MEASUREMENT THAT SETTLES WHETHER THIS IS A DIFFERENCE AT ALL**
(`py-probe5.py`, calling CPython, on fresh arenas both request orders):

```
FLIP    (True, False) then (1, 0): p is q = True   stored = (True, False)
FLIP    (1, 0) then (True, False): p is q = True   stored = (1, 0)
PERMUTE (1, 0) then (True, False): p is q = True   stored = (1, 0)
```

**`UOp(Ops.FLIP, src, (True, False)) is UOp(Ops.FLIP, src, (1, 0))` — ONE NODE.**
The ucache key hashes the tuple's **values**, and `True == 1` in Python, so the two
spellings are not merely equal, they are **the same object**, and the spelling that is
*stored* is decided by which request reached the ucache first.

**So `ops.py:428`'s bool guard is INSERTION-ORDER DEPENDENT.** Intern `(1, 0)` first
and that same node raises `ValueError`; intern `(True, False)` first and it answers
`(4, 3)`. A "difference" whose sign depends on request order is not a difference in
the graph, and a differ that separates them is reporting one that **the reference
implementation denies**.

---

## 2. DEFECT, OR PRESENTATION CHOICE — they are not the same thing, and the brief was right about that

### A. the GROUP: **A DEFECT — in the differ's fixture, not in the port.**

Reason, and it is a strong one: the port **agrees with upstream** here, in committed
code, at `uop/ops.bend:2486`. The rule `GROUP(x) == x` for a singleton is upstream's
own, and the port implements it. The fixture did not use the API that implements it.
Nothing about this is a "legal-but-different arena shape": `GROUP(FLIP(a))` and
`FLIP(a)` are two different graphs over the same node, and upstream picks the second
deterministically. Calling this a presentation choice would be calling a bypassed
function a style preference.

### B. the arg atom: **A PORT VOCABULARY GAP, NOT A DEFECT IN THE GRAPH — and the differ over-reported it.**

Not a hedge; here is the whole of it. The gap is real and I am not hiding it:
`ops.bend:1066` cannot express `tuple[bool, ...]`, and the consequence is named at
`uop/fold.bend:6488-6492` — **`ops.py:428`'s `isinstance(x, bool)` half is
unimplementable**. But that gap is **one-directional and cannot change an answer**:

* `ops.py:428` is a guard whose only effect is to turn an answer into a **REFUSAL**;
* a port that cannot raise the refusal is strictly **MORE PERMISSIVE**;
* a refusal it cannot raise **cannot change an answer it gives** — `_shape`'s FLIP arm
  is `if <bad>: raise` then `return ps`, and `ps` is untouched by the guard.

The port's length half *is* implemented (`uop/fold.bend:5121-5124`). So there is no
node the port builds that is wrong, and no node CPython builds that the port cannot
answer. What the port lacks is a **spelling**, not a **semantics**. And upstream,
measured above, cannot hold the two spellings apart either.

So: **a port vocabulary gap, reported by the differ as a structural disagreement. The
verdict was wrong; the gap is real and stays on the port's own wall.**

---

## 3. WHAT I CHANGED — and the corpus-wide before/after

Two edits, both in the three files I claim.

1. **`.agents/slop/graphcmp.bend:1274`** — `O.UOp.new(..., OpsGROUP{}, [fl], ...)` →
   **`O.UOp.group(ar, [fl])`**. The port's own elision now runs.
2. **`.agents/slop/graphcmp.py`** — **`FLIPR-1`, `canon_flip(op, arg)`**: a FLIP's
   flag tuple is canonicalised to the `u32` atom on both sides, counted per node, and
   printed in a new ledger row `B`.

**`canon_flip` is SCOPED TO `Ops.FLIP`**, it is a **no-op on every other op**, and
every rewrite is counted:

```
# RESIDUALS IN THIS RUN: B=2/0 (a bool ATOM in a FLIP arg, CANONICALISED to the u32
#   atom: CONTENT compared) -- agreement below does NOT cover these.
```

`B` is declared in a new `INJECTED` set because it is **not a wire spelling** — it
counts a *transformation*, so the text scan can never find it and `report` injects it
from the nodes. `selfcheck` REJECTED `B` for exactly that reason
(`ledger marker 'B' is neither an atom letter nor a declared literal`) and the check
is now satisfied by declaring the distinction rather than by renaming the marker.
**The other half of the claim is asserted where the text exists**: `report` raises if
an `INJECTED` marker ever appears as text, so "the scan never finds `B`" is falsifiable
and cannot decay into two disagreeing counts.

Scope measured, not assumed: `n(b<digits>` occurs in **exactly one graph of the 22** —
`flip` — over every graph, both sides.

### THE DENOMINATOR, BEFORE AND AFTER

```
BEFORE  flip  nodes=6/7  shared-cores=5  ops-reached=5/6 of 77  VERDICT: DISAGREE
        SHARED cores=5  ONLY-PY=1  ONLY-BEND=2  field-mismatches=0  rung3.5-crossrefs=1
AFTER   flip  nodes=6/6  shared-cores=6  ops-reached=5/5 of 77  VERDICT: AGREE
        SHARED cores=6  ONLY-PY=0  ONLY-BEND=0  field-mismatches=0  rung3.5-crossrefs=0
```

**It is `6/6`, not `7/7`.** The `7` in `nodes=6/7` was the fixture's own extra GROUP,
and the `GROUP=1` in the two in-code censuses that would have made `7/7` the target
never existed upstream. The py side of `flip` is 6 nodes and has always been 6.

### THE OTHER 21 GRAPHS DID NOT MOVE — measured, by swapping my baselines in

`.agents/slop/flip/runs/BEFORE.txt` vs `AFTER.txt`, whole-line diff:

```
$ diff runs/BEFORE.txt runs/AFTER.txt
8c8
< flip … nodes=6/7 … ops-reached=5/6 … VERDICT: DISAGREE
> flip … nodes=6/6 … ops-reached=5/5 … VERDICT: AGREE
```

**One line. `flip`. Every other denominator and verdict byte-identical.**
20 AGREE, 2 DISAGREE (`lin`, `loop` — REACH.md records those as disagreeing **on
purpose**, for named measured reasons).

`selfcheck`: `# SELFCHECK: OK` before, and after the `INJECTED` fix (see §5 for the
one failure it caught in between).

---

## 4. THE `?` LEDGER, and why it was never the point

`flip` read `?=0` on both sides while DISAGREEing, and still reads `?=0` now that it
AGREEs. That is the correct behaviour of that row and the reason `?=0` is not a
verdict: it measures **omission**, and the corpus is now clean on omission *and* on
structure. The new `B` row is the same shape of evidence pointed the other way — it
counts what the comparison **did not** take at face value.

---

## 5. WALLS, with `file:line`

### FLIPR-W1 — a differ that flags what the reference implementation merges is a FALSE POSITIVE, and it is a class

`graphcmp.py:canon_flip`. CPython's own node identity (`is` → `True`) says two args are
one node. A differ that renders the *Python type* of a value as part of the node's
identity will manufacture a disagreement the reference denies — **and the sign of it is
set by interning order, so it is not even stable.** The general lesson: before making a
type tag load-bearing in a normal form, ask what the reference does with the two
spellings. Here the answer was measured in one line and it settled the whole case.

### FLIPR-W2 — a *fixture* that builds a graph by hand can disagree with the port it is testing, and the port will be blamed

`graphcmp.bend:1274`. Every `g_*` here constructs the arena node by node rather than
calling the port's `Tensor` path, so a fixture can be wrong **in a way no port test can
see** — here it re-implemented `UOp.group` incorrectly while `uop/ops.bend:2486` had it
right all along. **`graphcmp.bend` should call the port's own API wherever one exists;
reaching past it to the raw constructor is how a fixture stops being a fixture.**

### FLIPR-W3 — a stale number inside the file that quotes the measurement

`graphcmp.py:1355` and `graphcmp.bend:1241-1242` both print a py-side census containing
`GROUP=1`. Measured: `GROUP=0`, root is the FLIP. Both are transcribed-from-memory
comments that nobody re-ran, and they are the sole origin of the "7" that the brief
inherited as a target. Same failure as the `35 -> 53` staleness in `REACH.md`: **a
number that was once true, or once believed, survives until somebody re-measures it.**

### FLIPR-W4 — a swap-and-restore in a file two agents share cost a false alarm, and the alarm was not mine

I swapped `graphcmp.{py,bend}` to their baseline to measure BEFORE, then restored. On
restore, `selfcheck` failed with `emit bend: 0 rows` at **`graphcmp.bend:1375`**:

```
# `match` may scrutinise a PARAMETER or a PATTERN binder, never a computed value
```

`graphcmp.bend:1373-1375` is `def rows.pick(name: String) -> O.Found: rows.pick3(name)`
feeding `rows.pick3(+name: String)` — **the callee CONSUMES the name and the caller
does not offer a `+`**. Not my line and not my edit: a concurrent unit added
`g_cdiv`/`g_late` and reshaped `rows.pick3` between my `cp` and my restore. **I did not
touch it** — `agent-core.md` says a read-only file's bug gets reported, not fixed.
Two units are in `graphcmp.bend` at once; a restore-from-copy is a blind spot here.

### FLIPR-W5 — `--check-only` was not the instrument; the run was

`.agents/slop/graphcmp.py:1740-1752`. `emit bend` **retries five times and raises
`SystemExit` on 0 rows**, printing each attempt's rc and stderr tail. That is why the
W4 failure is legible at all: an instrument that produced nothing said so loudly,
instead of the `rc=0`-with-no-bytes shape the brief warns about. **A differ that
refuses to return a verdict on 0 rows is a differ that cannot silently pass.**

---

## 6. ORACLES

`.agents/slop/flip/py-probe.py`, `py-probe2.py`, `py-probe3.py`, `py-probe4.py`,
`py-probe5.py` — all numbers above are their output, not transcribed.
`.agents/slop/flip/runs/{BEFORE,AFTER}.txt`, `SELFCHECK-BEFORE.txt`.
Baselines: `.agents/slop/flip/*.BASELINE`, md5 in `CLAIM.md`.

## 7. NOT CLAIMED

* Not a claim that the port can rewrite, or that any rewrite rule is ported. `g_flip`
  is an eager graph; `lin`/`loop` still DISAGREE on purpose.
* Not a claim of corpus coverage beyond **the emitter**. 53 of 77 ops, and nothing here
  says anything about `schedule -> render -> compile`.
* Not a claim that the port's bool gap is closed. **It is not.** `ATuple` is still
  `List<&2, U32>` and `ops.py:428`'s `isinstance` half is still unimplementable. What
  changed is that the differ no longer reports that gap as a wrong graph — which is the
  only thing that was ever wrong about it.