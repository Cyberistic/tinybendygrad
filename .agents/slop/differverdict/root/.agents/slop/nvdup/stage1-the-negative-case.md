# STAGE 1 — THE PART THAT MATTERS MORE THAN THE COUNT

Tool: `.agents/slop/nvdup/nvdup-trace.py` (line attribution) · `.agents/slop/nvdup/nvdup-probe.py`
(asks CPython).  Raw: `nvdup-trace.txt`, `nvdup-probe.txt`.

## 1. THE BRIEF'S PREMISE IS INVERTED, AND TWO INDEPENDENT INSTRUMENTS SAY SO

The brief, and `dup/stage2-classify.md:106-109`, both say:

> `nv_reloc_bad_refused` is emitted three times — `"True"` at `:721`, then `"False"` at `:1159`
> and `"True"` again at `:1161` — and `rows()` keeps the LAST […] **a NEGATIVE CASE is
> unaddressable.**

**`"False"` at `:1159` is not emitted. It never executes.**  Two measurements that cannot
disagree, from two different instruments over two different things:

```
$ grep -n 'nv_reloc_bad_refused' .agents/slop/dup/lanes/tinybendygrad_runtime_ops_nv.bend.oracle0.txt
319:nv_reloc_bad_n=1
320:nv_reloc_bad_refused=True          <- from :721
560:nv_reloc_bad_refused=True          <- from :1161
561:nv_reloc_bad_n=0
```

and `nvdup-trace.py`, which attributes each `row()` CALL to its source line by running the real
oracle under `sys.settrace`:

```
nv_reloc_bad_refused  x2  P1 EQUAL-VALUES
    nv-oracle.py:721   nv_reloc_bad_refused=True
    nv-oracle.py:1161  nv_reloc_bad_refused=True
```

**`x2`, not `x3`, and there is no `False` in the output at all.**  The tree-wide census agrees:
`DUPLICATE 'nv_reloc_bad_refused' x2`.

## 2. WHY IT NEVER EXECUTES — asked of CPython, not read off the source

`nv-oracle.py:1157-1162` is

```python
try:
    [reloc_of(*_r) for _r in ((16, 8, 2), (48, 8, 3), (64, 8, 0x38))]
    row("nv_reloc_bad_refused", "False")     # :1159
except RuntimeError:
    row("nv_reloc_bad_refused", "True")      # :1161
    row("nv_reloc_bad_n", 0)                 # :1162
```

`nvdup-probe.py Q1`, calling the arms of `reloc_of` (`:680`) one at a time:

```
element 0 (16, 8, 2) -> OK (16, 8, dtypes.u64, 0)
element 1 (48, 8, 3) -> RAISES RuntimeError(unknown NV reloc 3)   <<< the comprehension aborts HERE
element 2 (64, 8, 56) -> OK (68, 8, dtypes.u32, 0)
the comprehension RAISED -> :1160 NEVER EXECUTES.
```

**The arm is dead BY CONSTRUCTION, not on this run:** `reloc_of`'s arms are `2 / 0x38 / 0x39`
and its `else` is `raise`, so type `3` raises whatever else is true.

## 3. SO: IS IT THE SAME DEFECT AS THE DUPLICATES? **TWO DEFECTS, AND THE SECOND ONE COSTS 0**

| | mechanism | measurements | a multiplicity census sees it? |
|---|---|---|---|
| **D1 two sites for one name** | `:720` and `:1162` both write `nv_reloc_bad_n` | **1** | **yes** — `x2` |
| **D2 a dead `try:` arm** | `:1159` writes a row into an arm no fixture reaches | **0** | **NO — it emits nothing** |

**They are related and they are not one defect.**  They are the same *family* — a producer that
writes a name more than once — but only D1 costs a measurement.  D2 costs **zero**, because a
line that does not execute has no output line to count.  Which means:

> **D2 is invisible to every duplicate instrument in this project, including this unit's own
> `dup-gate.py`.**  The row it was written to carry — the rule's negative case — was never
> emitted, so no count of emitted names could ever have reported its absence.

**D2 IS THE WORSE OF THE TWO, and it is the thing the brief was reaching for.**  A lost refusal
is a hole; an *unrepresentable* refusal is a hole that the instrument is shaped so it cannot
show you.

## 4. THE RULE'S NEGATIVE CASE EXISTS, UNDER A NAME THAT WORKS

The instrument was not missing the negative case — it was putting it in the wrong arm.

| | where | value | on both sides? |
|---|---|---|---|
| the refusal | `:721` / `:1161` | `True` | yes |
| **the refusal's negative** | **`:718`** `nv_reloc_ok_refused` | **`False`** | **yes — port lane line 318 and oracle line 318** |

`_ok = reloc_fold([(16, 8, 2), (32, 8, 0x38)])` at `:712` does not raise, so
`nv_reloc_ok_refused="False"` is the negative case, it is emitted, and both lanes print it.
**So deleting the dead arm loses nothing** — and after the fix, `nv_reloc_bad_refused` is
sourced from CPython's caught `RuntimeError` at `:1161` rather than from the typed `"True"` at
`:721`, which is what "addressable, not merely un-duplicated" means here.

## 5. D1's VALUE DIVERGENCE IS A SEMANTIC DISPUTE, NOT A TYPO — and the fix does not settle it

`:720` and `:1162` print **different** values (`1` and `0`), so D1 is a **P2 DISTINCT-VALUES**
case.  They measure different **subjects**:

| site | expression | subject | answer |
|---|---|---|---|
| `:720` | `len(reloc_fold(...))` | `reloc_fold`, a helper **defined at `:704` of the oracle itself**, which BREAKS on the raise and returns the prefix | 1 |
| `:1162` | typed `0` | upstream's `NVProgramData.__init__`, which **raises and abandons the object** | 0 |

Upstream, asked by `grep` on the live tree: `tinygrad/runtime/ops_nv.py:235`
`self.relocs = []`, `:262-266` append-then-`raise`.  So both are renderings of an **unobservable**
state — what a discarded object held.  The port models the second one and says so at
`tinybendygrad/runtime/ops_nv.bend:2344-2348`.

**The fix deletes the site that has no upstream subject.**  `agent-core.md`: "a row whose
expected value is a def of the thing under test is not a test" — `reloc_fold` IS the thing
`nv_reloc_bad_n` was measuring, and it is not the port's subject.  So the fix removes the party
with no standing rather than choosing between the two readings, and **the residual dispute is
reported, not resolved**: `.agents/slop/NVDUP.md` §5.

**AND the port's own comment records a measurement of a THIRD fold.**  `ops_nv.bend:2348` says
keeping the prefix "made `nv_reloc_bad_n` answer **2**".  With the fixture the row actually uses
(`ops_nv.bend:2372`, `relocs_bad()`, identical to the oracle's), the prefix is **1** — 2 is what
you get if the fold **continues past** the bad element instead of breaking.  Three renderings, one
name.

## 6. THE SAME DEFECT, TWICE MORE, IN A BLOCK NOBODY WAS LOOKING AT

`nvdup-deadarm.py` (Stage 4) reads **4** dead `row()` sites on the pre-fix oracle.  Two are
above; the other two are the `_smem_cfg` block:

```
nv-oracle.py:1139  row("nv_smemcfg_too_big", "False")
nv-oracle.py:1146  row("nv_smemcfg_msg_big", "")
```

`_smem_cfg` (`:639`) is `min(c*1024 for c in [32,64,100] if c*1024 >= shmem)//4096 + 1`, so every
`shmem > 102400` leaves the generator empty and `min()` raises; both fixtures are `131072`.  And
`nv_smemcfg_ok_max="True"` at `:1126` is a **typed** `"True"` answering "did `_smem_cfg(102400)`
not raise" — so that block had a **dead arm for the answer it wanted and a literal for the answer
it already had.**  The accepted side is measured by calling at `:659` and `:660-663`, so all four
arms were redundant as well as dead.

## 7. WALLS

* `wrap row()` by assigning to `g["row"]` and the wrapper is **gone before the first row**:
  `nv-oracle.py:29`'s own `def row` reclaims the name on every `exec`.  Observed, not reasoned —
  the first run attributed **0** calls.  `sys.settrace` from outside has no such problem.
* `nvdup-trace.py` and `nvdup-deadarm.py` both need the oracle's import root, which `:16`
  derives from `__file__`, so a `$TMPDIR` copy needs `PYTHONPATH=<repo>` rather than the path
  the file computes for itself.
* `dup-census.py --all` has no timeout budget and takes minutes; `timeout` is not on this box.