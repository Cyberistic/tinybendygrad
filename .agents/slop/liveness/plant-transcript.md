# plant-transcript.md — the six (seven) plant/disarm pairs, verbatim

Every plant was applied to a **COPY** of the tree:

```
$TMPDIR/opencode/liveness/repo = { tinybendygrad, tinygrad, bin, .venv, .agents/slop }
```

`.agents/slop/{xd1,dd-cone-wt,proof-close,opstree,render-wt,ddcheck,blobrows,__pycache__}`
were excluded for size. The copy's
`.venv/lib/python3.12/site-packages/__editable___tinygrad_0_14_0_finder.py` `MAPPING` was
repointed at the copy, because `oracle_py.resolve()` **refuses to run** when the pinned
interpreter resolves `tinygrad` to a different tree — it printed

```
ORACLE PYTHON IMPORTS THE WRONG tinygrad: …/liveness/repo/.venv/bin/python
  resolved /Users/cyberistic/src/tries/2026-09-30-tinybendygrad/tinygrad/__init__.py
  wanted  …/liveness/repo/tinygrad/__init__.py
  Every row this gate prints would be measured against a tree that is not the one
  the port is ported from. Refusing.
```

which is the gate being correct and is worth recording on its own: a `.venv` copied
out of the tree silently points the oracle at the ORIGINAL `tinygrad`.

**The live tree was never patched from a harness.** A pristine copy of each port file was
taken immediately before each mutation and restored after; the restored sha256 is printed
under each lane and matched the pristine sha256 every time.

---

## LANE A — `device.bend` through `rebase-gate.py` — ARMED

```
=== BASELINE ===
AGREE-UNRECORDED tinybendygrad/device.bend  [STARVED]
   compared clean and UNRECORDED over 110 shared row name(s) in 3 lane pair(s)
     ([('cpython:device-oracle','interpreted',23),
       ('cpython:device-oracle','native',23),
       ('interpreted','native',110)]), every shared row agreed
   rows interpreted=110  rows native=110  rows cpython:device-oracle=23
TALLY AGREE-UNRECORDED=1
```

### PLANT v1 — **VACUOUS. THE GATE WAS RIGHT TO IGNORE IT.**

`device.bend:1326` `device_usage(False{}, "python:1")` → `device_usage(True{}, …)`

```
AGREE-UNRECORDED tinybendygrad/device.bend          <- unchanged, and CORRECTLY so
```
```
port stdout sha256 with plant:    42a884a9ea3e33e8d3e502cc905faa19d871d31faa55884cf6d1acd47db5cc93
port stdout sha256 without plant: 42a884a9ea3e33e8d3e502cc905faa19d871d31faa55884cf6d1acd47db5cc93
```

**Identical.** `device.bend:348` is
`allowed(allow, ix) = Bool.or(allow, U32.is_ne(tag_of(head(ix)), 0))`, and for
`ix = canon("python:1")` the second operand is already `True`. So `Bool.or(True, True)` and
`Bool.or(False, True)` are the same answer. **The plant changed the source and not the
output.** Had the unchanged verdict been read as "the gate is blind", it would have been a
false finding. (`agent-core.md`: "a memoized answer is measured by its cache" — the same
shape, as "an OR is not a function of its first argument".)

### PLANT v2 — the one that counts

`device.bend:348` `Bool.or(allow, …)` → `Bool.not(Bool.or(allow, …))`
port file sha 1898ce827dc05a6c

```
port allow_* WITH plant:
  allow_py=1  allow_lower=0  allow_metal=1  allow_on=0  allow_cpu=1
  allow_disk=0  allow_npy=0  allow_cpu_l=1  allow_mixed=0
port stdout sha: 8b3545bff2ff3679526f500d5cf4548755aa8e1d86b0a9f1f5476d52e53842be

BROKEN       tinybendygrad/device.bend  [STARVED]
   cause=DISAGREE [DEFECT]
   9 of 110 shared row name(s) disagree with CPython (156 counted once per lane pair,
   18 pair-instance(s) of the same 9 name(s)): 'allow_cpu', 'allow_cpu_l',
   'allow_disk', 'allow_lower', 'allow_metal', 'allow_mixed' (+3 more)
```

### DISARM — append `# liveness-audit disarm: a comment and a blank line.`

```
port stdout sha: 42a884a9ea3e33e8d3e502cc905faa19d871d31faa55884cf6d1acd47db5cc93   <- unchanged
AGREE-UNRECORDED tinybendygrad/device.bend  [STARVED]
   compared clean and UNRECORDED over 110 shared row name(s) in 3 lane pair(s) …
   rows interpreted=110  rows native=110  rows cpython:device-oracle=23
```

restored `edc4d46b403ff317…` == pristine `edc4d46b403ff317…`

---

## LANE B — `renderer/llvmir.bend` through `llvmir-gate.py` — ARMED, AND TAUTOLOGICAL

```
=== BASELINE ===
live port rc=0 md5=74e3e832   live oracle rc=0 md5=74e3e832
port rows (rows_strict): 470   oracle rows (rows_strict): 470
  the two lanes are BYTE-IDENTICAL: True   <- the value comparison below is therefore
                                                a TAUTOLOGICAL ZERO
gated 470   agree 470   disagree []
STALE-LITERAL 0
BROKEN
  - port:   1/471 row(s) share a key with another row of the SAME name: ['lt 1 ptr f32']
  - oracle: 1/471 row(s) share a key with another row of the SAME name: ['lt 1 ptr f32']
```

### PLANT — `llvmir.bend:981` `r_lt("lt f32", S.single(), "float")` → `S.double()`

port file sha 6496f8f07cc7cf72

```
live port rc=0 md5=1bc05717   live oracle rc=0 md5=74e3e832
the two lanes are BYTE-IDENTICAL: False
gated 470   agree 469   disagree ['lt f32']
STALE-LITERAL 0
BROKEN
```

### DISARM — append an unreachable comment

```
port stdout sha 258d7de0cf72f6bfe2c869d7a1ca317abbd7faf534ac46aed8be714ecf00eb7d
live port rc=0 md5=74e3e832   live oracle rc=0 md5=74e3e832
the two lanes are BYTE-IDENTICAL: True
gated 470   agree 470   disagree []
```

### The sub-finding: `STALE-LITERAL` cannot see a wrong Bend value here

```
planted port row:  lt f32 = [double]   py=[float]
live oracle row:   lt f32 = [float]    py=[float]
STALE-LITERAL 0
```

The `py=` literal was generated from the pin, so it stays right when the port's computation
goes wrong. That is the documented intent (`llvmir-gate.py:377-379`, `rebase-gate.py:425-435`)
and it means the `py=` column is not a second reader of the port.

### And: the same lane under `rebase-gate.py` is tautological too

```
$ .venv/bin/python .agents/slop/llvmir-oracle.py > orc.txt      # DEFAULT argv, as BASE_ORACLES passes it
$ ./bin/bend tinybendygrad/renderer/llvmir.bend > port.txt
port lines=472  orc lines=472
port sha 258d7de0cf72f6bfe2c869d7
orc  sha 258d7de0cf72f6bfe2c869d7
BYTE-IDENTICAL under rebase-gate's own default argv
```

Only `llvmir-gate.py`'s header says this. `rebase-gate.py` does not, for llvmir or for any of
the other six byte-identical lanes.

---

## LANE C — `renderer/cstyle.bend` through `cstyle-gate.py` — ARMED

```
=== BASELINE ===
live port lane rc=0   live oracle lane rc=0
gated 221   agree 221   disagree []
STALE-LITERAL 0
UNREPORTED-REFUSALS 0
AGREE
COVERAGE 221/227 port rows compared to a live CPython call, 0 disagreeing;
  4 of those are rows where `_render_dtype` REFUSES and the port answers the `.get` reading;
  6 declared exclusions.
```

### PLANT — `cstyle.bend:565` `type_map.base`: `Kv{"f32","float",` → `Kv{"f32","flt",`

port file sha 52a0970f94b9364b

```
live port lane rc=0   live oracle lane rc=0
gated 221   agree 157   disagree ['acc  BASE  stk4', 'buf2 BASE  LOC', … ]
BROKEN
  - 64 gated row(s) DISAGREE with a live CPython call, and every one is NAMED:
    ['acc  BASE  stk4','buf2 BASE  LOC','buf2 CUDA  GLOB','buf2 CUDA  LOC','buf2 HIP   LOC',
     'buf2 METAL GLOB','buf2 METAL LOC','buf2 OPENCLGLOB','buf2 OPENCLLOC','buft BASE',
     'buft CLANG','buft CUDA','buft HIP','buft OPENCL','hipocml','kern2 BASE', … 64 names]
```

### DISARM — append an unreachable comment

```
port stdout sha 4ab4cadfc0827c0daa10fed47a3c7116aee08400a41188035b1b9b06299ada53
live port lane rc=0   live oracle lane rc=0
gated 221   agree 221   disagree []
AGREE
COVERAGE 221/227 … 0 disagreeing … 6 declared exclusions.
```

restored `07ae2766f891e9a8…` == pristine

**This is the counter-example to the brief's third named instance.** `cstyle.bend`'s lanes are
NOT byte-identical (227 port rows vs 224 oracle rows, 221 gated), so its value comparison is
real — and it is now *shown* to be real by a plant that moved 64 rows.

---

## LANE D — `uop/fold.bend` through `rebase-gate.py` — ARMED

```
=== BASELINE ===
UNCHANGED    tinybendygrad/uop/fold.bend  [STARVED]
   CAUSE: 240 shared row name(s) across 3 lane pair(s), every one agreeing
   rows interpreted=240  rows native=240  rows cpython:mm-lift-gate=130
```

### PLANT — `fold.bend:3731` `mm.where`: lo bound `bnd.min` → `bnd.max`

port file sha 159cd1536a25369d

```
BROKEN       tinybendygrad/uop/fold.bend  [STARVED]
   cause=DISAGREE [DEFECT]
   3 of 240 shared row name(s) disagree with CPython (492 counted once per lane pair,
   6 pair-instance(s) of the same 3 name(s)): 'lf_where1 lo', 'lf_where2 lo', 'lf_where3 lo'
```

### DISARM — append an unreachable comment

```
UNCHANGED    tinybendygrad/uop/fold.bend  [STARVED]
   CAUSE: 240 shared row name(s) across 3 lane pair(s), every one agreeing
   rows interpreted=240  rows native=240  rows cpython:mm-lift-gate=130
```

restored `e8c7bdc8c27e2272…` == pristine

---

## LANE E — `renderer/amd/dsl.bend` through `dsl_gate.py` — ARMED on the port, RECORDED on the oracle

```
=== BASELINE ===
rows port=1161 oracle=1576 matched=617 mismatched=1503 missing=959 extra=544
DUPLICATE/MISMATCH lines are printed for each; the harness exits 1
```

### PLANT v1 — **A COMPILE ERROR, NOT A VALUE PLANT. THE LANE IS RED FOR THE WRONG REASON.**

`dsl.bend:1734` `nat_text(reg_names_n() + 1n)` →

```
SOME PROOFS FAIL
Error:
- message  : a type for this operator (write (a + b : Nat))
Location: 1734 |     srow("names_count", nat_text(reg_names_n() + 1n))

rows port=0 oracle=1576 matched=0 mismatched=1576 missing=1576 extra=0
```

**`dsl_gate.py` has no zero-row guard.** A dead port lane reads as "every single row
mismatches", which is how a lane teaches its reader to ignore it. Red for the wrong reason is
worse than no red.

### PLANT v2 — a VALUE plant that compiles

`dsl.bend:1734` `srow("names_count", nat_text(reg_names_n()))` → `srow("names_count", "99")`

port file sha 0e0a8ff28a16092e

```
names_count=99
MISMATCH names_count
  port   99
  oracle 32
rows port=1161 oracle=1576 matched=617 mismatched=1504 missing=959 extra=544
```

### DISARM — append an unreachable comment

```
rows port=1161 oracle=1576 matched=617 mismatched=1503 missing=959 extra=544
```

restored `202de0e8ac053481…` == pristine

### The oracle side, and why it is not live

`dsl_gate.py:24`  `ORACLE = ROOT / "oracles/dsl_oracle.txt"`
`dsl_gate.py:54`  `orc = parse(ORACLE.read_text())` — **nothing is executed.**

```
-rw-r--r--  44383  Oct  2 22:48  oracles/dsl_oracle.txt     <- the recorded oracle
-rw-r--r-- 174628  Oct  4 14:16  tinybendygrad/renderer/amd/dsl.bend   <- the live port
```

And re-recording it does not fix it, because the recorded file is **not reproducible**:

```
$ .venv/bin/python .agents/slop/dsl_oracle.py [DANGLING: this instrument was DELETED by the 2026-10-05 prune and is not in git] > dsl_oracle_live.txt    # the documented command
recorded sha: 02a3b49cd616f262b25c587b
live     sha: 165381d2ef10160c78a1eb85
DIFFER:
1604c1604
< fixed_hilo=<tinygrad.renderer.amd.dsl.FixedBitField object at 0x10911a510>.hi,0
---
> fixed_hilo=<tinygrad.renderer.amd.dsl.FixedBitField object at 0x1099ce810>.hi,0
```

**The recorded oracle embeds a heap address.** ASLR changes it on every process launch, so
that row can never match and re-recording it on a new process changes it again. Same species as
the 14 `elf_built_*` rows `BASE_ORACLES` already excludes from `elf.bend` for exactly this
reason — and it is one row that was not noticed.

---

## LANE F — `runtime/support/nv/nvdev.bend` through `nv_nvdev_gate.py` — ARMED

```
=== BASELINE ===
oracle exit=0 stdout_rows=2176
oracle distinct name= rows: 2176
interpreted lane exit=0 rows=820
compiled lane exit=0 rows=820
LANES BYTE-IDENTICAL: True
gate distinct name= rows: 799
DISAGREEMENTS OUTSIDE A DOCUMENTED WALL: 0
DISAGREEMENTS: 0
GATE PASS
rc=0
```

(820 physical lines → 812 carrying `=` → **811 match `nv_nvdev_gate.rows()`'s
`[A-Za-z_][A-Za-z_0-9]*` key regex** (the one line it drops is `nvdev-done=1`, the sentinel
`nv_gate.py` appends to the port) **→ 799 distinct keys: 12 rows lost to 6 duplicate names.**
That is the reader unit's column, not this unit's — named here, not adjudicated.)

### PLANT — `nvdev.bend:1562` `nv_boot42_merext_lo` field index `0` → `1`

(the exact transposition commit `b8897fd4` fixed — `COMMIT-MISATTRIBUTION.md`)

port file sha 42b6aa6bffed3495

```
LANES BYTE-IDENTICAL: True
gate distinct name= rows: 799
DISAGREEMENTS OUTSIDE A DOCUMENTED WALL: 1
DISAGREEMENTS: 1
  nv_boot42_merext_lo
GATE FAIL
rc=1
```

### DISARM — append an unreachable comment

```
LANES BYTE-IDENTICAL: True
gate distinct name= rows: 799
DISAGREEMENTS OUTSIDE A DOCUMENTED WALL: 0
DISAGREEMENTS: 0
GATE PASS
rc=0
```

restored `d00afaf6628bfa6d…` == pristine

**The harness that "hid all 15 disagreements behind a traceback" does not crash today.** It
runs, and it reports. The 3-value-unpack-of-4-tuples defect is not present in the current file.

---

## LANE G — `dtype.bend` through `dtype-gate.py` — **DISARMED**

```
=== BASELINE ===
DECLARED DEVIATION (rows):
  cpython: u64 … 0:0  4294967295:4294967295  -
  bend   : u64 … 0:0  2147483647:4294967295  -
  reason : the I64 is a signed pair of U32s, so 2^64-1 has no image and `i64_max_u`
           answers int64's max; pre-dates the rename
14766 rows compared, 1 declared, 0 unexpected
rc=0
```

### PLANT — `dtype.bend:381` `i64_max_u case 32`: `H.i64_of_hi_lo(0, 4294967295)` → `(12345, 4294967295)`

A genuinely wrong answer for the port's arithmetic. port file sha ab8530205c398764

```
$ diff <(grep -v '^$' .agents/slop/dt-bend.txt) \
       <(./bin/bend tinybendygrad/test/dtype_oracle.bend 2>/dev/null | grep -v '^$')
11c11
< u32  6  32  4  True  False  True  False  0:0  0:4294967295      -
---
> u32  6  32  4  True  False  True  False  0:0  12345:4294967295   -

$ .venv/bin/python .agents/slop/dtype-gate.py          # the DEFAULT invocation, no --write
14766 rows compared, 1 declared, 0 unexpected
rc=0
```

**The port's live output changed and the gate did not move.** `dtype-gate.py:66` is

```python
if write or not (os.path.exists(BEND_OUT) and os.path.exists(PY_OUT)):
```

and both lane files are committed, so the lanes are **never run** on a normal invocation:

```
-rw-r--r-- 431337  Oct  3 10:57  .agents/slop/dt-bend.txt
-rw-r--r-- 431337  Oct  3 10:57  .agents/slop/dt-py.txt
-rw-r--r--  11204  Oct  4 14:16  tinybendygrad/test/dtype_oracle.bend   <- the live port
```

### DISARM — append an unreachable comment

```
14766 rows compared, 1 declared, 0 unexpected
rc=0
```

restored `5cd93b94eec4cbb5…` == pristine

### And the companion lane, for the same file, is dead on the PORT side too

```
$ .venv/bin/python .agents/slop/rebase-gate.py --port tinybendygrad/dtype.bend
BROKEN       tinybendygrad/dtype.bend  [STARVED]
   cause=LANE-DEATH [INSTRUMENT]
   rows interpreted=0  rows cpython:dtype_tables=0

$ ./bin/bend tinybendygrad/dtype.bend ; echo rc=$?
rc=1
SOME PROOFS FAIL
Error: 14 defs rely on unsafe or foreign code:
- Dt.bf16
```

0 rows on BOTH sides, so the lane compares nothing. `agent-core.md` records "The file run
itself exits 0" — **measured, for this file, it does not.**