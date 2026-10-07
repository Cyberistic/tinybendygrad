# BW-GRAPH — a BACKWARD graph in the differ, at `?=0/0`

**One job, one graph, one verdict.** `bw` is registered in `.agents/slop/graphcmp.py`'s
`GRAPHS`, built node-for-node in `.agents/slop/graphcmp.bend`, and it reaches **`AGREE` at
field-record level with every ledger entry at 0/0**. All 17 graphs re-run; the corpus is
**35 of 77 ops**.
**⚠ THAT LAST FIGURE IS A 17-GRAPH BASELINE AND THE CORPUS IS NOW 24 GRAPHS / 59 of 77**
(re-measured 2026-10-04 by `notes-sweep`; see `../notes-sweep/01-GROUND-TRUTH.md`). `bw`
itself re-measured **AGREE 32/32** and is unchanged; only the corpus-wide figure beside it
aged. **The command below still reproduces this graph's own numbers exactly.**

    $ env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/graphcmp.py diff --graph bw
    # py rows=32  bend rows=32  plant=none  mode=ORDERED
    # RESIDUALS IN THIS RUN: none -- every ledger entry is 0 on both sides.
    # SHARED cores=32  ONLY-PY=0  ONLY-BEND=0  field-mismatches=0  rung2-pairs=0
    #   rung3.5-crossrefs=0  zip-truncated=0
    # DENOMINATOR: graphs=2 (1 py + 1 bend)  nodes=32/32  fields=6  field-records=192
    #   shared-cores=32  commutative-ops=8  ops-reached=10/10 of 77  symbolic-dims=0/0
    #   multi-parent-nodes=7/7
    # VERDICT: AGREE                                                       rc=0

**AND THE TWO CANONICAL FILES ARE BYTE-IDENTICAL**, which is a strictly stronger claim than
`AGREE` — 32 rows each, `cmp` clean, and stable across two runs on each side:

    run1 py=32 bend=32   -> BYTE-IDENTICAL-1
    run2 py=32 bend=32   -> BYTE-IDENTICAL-2
    py run1 vs run2, bend run1 vs run2 -> STABLE 2/2 each side

---

## 1. THE NUMBERS THE BRIEF ASKED FOR

| what | value | where it is measured |
|---|---|---|
| **nodes per side** | **32 / 32** | `# DENOMINATOR` on every `diff --graph bw` |
| **field-records per side** | **192** (32 nodes x 6 compared fields) | same line; `id` is R1 reporting-only |
| **`?` count** | **0 / 0** — REACHED | `?` ledger row, and `RESIDUALS IN THIS RUN: none` |
| **every other ledger entry** | `z y u q X! BAD E` all **0 / 0** | the same line — **not one unresolved field** |
| **ops reached, before** | **34 of 77** | `graphcmp-LIMITS.md` §5, and re-measured by the census |
| **ops reached, after** | **35 of 77** | `bw-census.txt`: `# TOTAL: 17 graphs, 221 nodes per side, 35 distinct ops` |
| **corpus nodes per side** | 189 -> **221** (+32) | same |
| **corpus field-records per side** | 1134 -> **1326** (+192) | `# FIELD-RECORDS PER SIDE`, same file |
| `bw`'s own op census | 11 distinct ops, 32 nodes | `ALLOC 2 CAST 1 CONST 4 EXPAND 2 GROUP 1 MUL 2 PERMUTE 4 REDUCE 2 RESHAPE 8 STACK 6` |
| `bw`'s symbolic dims | 0 / 0 | `# SYMBOLIC DIMS` |
| `bw`'s multi-parent nodes | 7 / 7, **identical lists on both sides** | `# MULTI-PARENT NODES` |

**THE `?` COUNT REACHED 0/0, AND THE BRIEF'S FAILURE MODE IS THE ONE I HIT.** `?` is the
port's "the fold produced no `Derived`", and it is PORT-ONLY: `UOp.shape` always raises or
returns a tuple (ops.py:455) and `dtype_from_uop` (ops.py:123-190) is total over `Ops`, so the
py side cannot produce it at all. A graph whose `?` count is non-zero is not AGREE, it is
*unexamined*. Mine is 0 on both sides **and every other marker is 0 too**, so nothing in this
graph is AGREE-by-omission.

---

## 2. WHICH OF `CAST` / `CONST` / `EXPAND` BECAME REACHABLE — **ONE of three, not three**

The brief named three ops and the honest answer is that **two were already reached**:

| op | in the 16 forward graphs? | corpus count before -> after | what `bw` did |
|---|---|---|---|
| `CAST` | **YES** — `cast 8/3` graphs, `lin` too | 8 -> **9** nodes, 3 -> **4** graphs | re-covered, added 1 node |
| `CONST` | **YES** — `CONST 36/16`, i.e. on **every** graph | 36 -> **40** nodes, 16 -> **17** graphs | re-covered, added 4 nodes |
| `EXPAND` | **NO** — in the 43 NOT REACHED | 0 -> **2** nodes, 0 -> **1** graph | **THE ONLY NEW OP** |

So **the census moves 34 -> 35 of 77, by exactly one op, and the honest count of what this
graph adds is one op.** Reporting it as three would have been the flattering reading. The
`bw` row of the census says it in the file's own words —
`bw 32/32 ok 10 DNOSbfilrs 13 1 0/0 - [same]`
— 10 ops on the `bw` graph itself and `[same]` for the py/bend op SETS.

**WHERE THE `EXPAND`s COME FROM, and it is the gradient, not a fixture choice.** `sum()`'s
gradient is a broadcast of a scalar seed, and that broadcast is an `Ops.EXPAND`
(`ops.py:816` `case Ops.RESHAPE | Ops.EXPAND: return self.src[1].as_shape`; the shape is
`tuple(self.marg) + ps`, ops.py:412-415). MEASURED, the seed chain is nodes 10-14:

    i10  CONST    weakfloat  ()            f1065353216          <- UOp.const(1.0), dtype weakfloat
    i11  CAST     f32        ()            Df32                 <- gradient.py:67's retype
    i12  STACK    weakint    (l0:2)        n(i3,i3)
    i13  EXPAND   f32        (l0:4,l0:4)   n(i11,i12)           <- marg (4,4) over a () seed
    i14  EXPAND   f32        (l0:3,l0:4,l0:4) n(i13,i2)          <- marg (3,) -> (3,4,4)

and the second EXPAND's shape is what makes the MUL below it broadcast.

---

## 3. DEFECT 27 — THE CORPUS'S FIRST FLOAT CONST, AND BOTH SIDES' SPELLINGS WERE WRONG

`graphcmp-LIMITS.md` §2 said, in its own words: *"A float CONST's structure … MEASURED: still
0 of the 189 nodes across 16 graphs has a float CONST, so the choice remains untested rather
than measured."* `bw` is that measurement, and **it failed on both sides at once**:

    py    konst -> "f" + repr(x)          ->  fConstFloat(1.0)
    bend  konst -> "f" + F32.show(f2)     ->  f1

Two independent defects in one column:

1. **`repr` on a SUBCLASS.** `x` is not a `float`, it is a `ConstFloat`
   (`tinygrad/dtype.py:12-25`, `class ConstFloat(float)` with
   `__repr__ = f"ConstFloat({float.__repr__(self)})"`). So `repr` here was the SUBCLASS's
   repr — Python's repr doing the work inside a structural field, which is the exact thing
   R7 exists to forbid.
2. **`F32.show` is text and lossy.** It is seven-significant-digit shortest-roundtrip
   (base.bend:1697), so it cannot separate two floats that agree to seven digits, and it
   spells an integral float with no point: `F32.show(1.0)` is `1`.

**THE FIX IS THE BITS, and both sides can produce them — MEASURED, not argued:**

    F32.bits(1.0)                             ->  1065353216     (a `law`, base.bend:1701)
    struct.unpack('<I', struct.pack('<f', 1.0)) ->  1065353216

so `graphcmp.py`'s new `f32bits` (graphcmp.py:414) and `graphcmp.bend`'s `konst` arm
(graphcmp.bend:200) now both emit **`f1065353216`**, and the column is **exact** rather than
textual. It is also the only spelling that separates two different NaNs, which is one of the
two distinctions `ConstFloat` documents itself as existing for (*"distinguishes -0.0 from 0.0
and where nan == nan"*). **BINARY32 and not BINARY64** is a measured choice, not a
preference: the port's `Const` carries `CFloat{f: F32}` (ops.bend:810), so a f64 column would
be one only the py side could fill — which is the `bytes CONST` defect in §2 exactly.

`_carg`'s float arm (graphcmp.py:621) was changed to the same helper, because a float can
reach `_carg` outside a CONST (`ProgramInfo.global_size` is `tuple[int|float, ...]`,
ops.bend:1352) and would otherwise keep the subclass `repr`.

---

## 4. THE PLANT AND ITS PAIRED DISARM

`--plant dsexpand` / `--plant disarm`. Evidence: `bw-p2.py`, transcript `bw-p2.txt`.

`dsexpand` takes the **second EXPAND** — named by its margin's VALUE (`CONST 3`), not by
toposort index, and `n.shape` cannot name it because a CONST's shape is `()` for every value
(ops.py:331) — and swaps that margin for the `CONST 1` already in the graph, so the seed
reads `(1,4,4)` where it read `(3,4,4)`. It plants **the op the graph exists to reach**.

| | clean | `dsexpand` | `disarm` |
|---|---|---|---|
| nodes | 32 | 32 | 32 |
| field-records | 192 | 192 | 192 |
| ops reached | 10 | 10 | 10 |
| stream vs clean | — | **differs** | **BYTE-IDENTICAL** |
| `VERDICT` | — | **DISAGREE** rc=1 | **AGREE** rc=0 |
| named field | — | **`shape`** (EXPAND#14, PERMUTE#15) + `src` (EXPAND#14) | none |

**The pair, in one line:**

    clean-vs-dsexpand  DISAGREE rc=1 names_shape=True      clean-vs-disarm  AGREE rc=0
    same graph, same 32 nodes, same 192 field-records

A red with no paired disarm proves only that the differ is not the identity. The disarm is the
same edit with the meaning removed — it re-references the same `CONST 3` through `UOp.const(3)`,
which the ucache (ops.py:201) collapses to the same object — and it must read AGREE. MEASURED,
its emitted stream is byte-identical to the clean one, so the plant's red is attributable to
the VALUE change and not to the rebuild. `bw-p2.py` asserts all three preconditions before it
reports anything, because `plant_srcswap`'s own docstring records the version that returned
`pl is ast` and reported AGREE.

### 4a. THE FIRST PLANT **DIED**, AND THE DEATH IS THE FINDING

The first `dsexpand` replaced that margin with the first EXPAND's own `STACK(4,4)`, which
drops a dim rather than changing one. The seed became `(4,4)`, the `PERMUTE (1,2,0)` above it
became an invalid permutation of len 2, and **upstream raised from inside `cshape`**:

    ValueError: invalid permutation (1, 2, 0) of len 4        (ops.py:415)
    ... in row_of -> cshape -> n.shape, for EVERY node

So the emitter **died** rather than reporting. That is LIMITS defect 13 (`BYTE-IDENTICAL` over
two 0-byte files) and defect 17 (the `arg=None` SINK that crashed the emitter) at a **third**
site: *an emitter that dies is indistinguishable, in a row-counting harness, from one with
nothing to say.* Hence the margin changes to a value of the **same arity**.

---

## 5. THE TWO NEW `selfcheck` ROWS ARE ARMED — MEASURED BY BREAKING THEM

**An assertion that cannot fail is not an assertion**, so both rows were shown firing.
Evidence: `bw-p3.py`, transcript `bw-p3.txt`. Every arm is built by monkeypatching the
loaded module in-process on rows the probe fabricates; **no `.bend` under `tinybendygrad/` is
touched**, because five units are live and `uop/ops.bend` is under single ownership.

| arm | what is broken | result |
|---|---|---|
| baseline | nothing | `SELFCHECK: OK` rc=0 |
| **A** | one `bw` node's dtype column reads `?` (what the identity PERMUTE did) | **FIRED** rc=1, names `?=1` |
| **B1** | py's float CONST reverts to `repr` (`fConstFloat(1.0)`) | **FIRED** rc=1, names the literal |
| **B2** | py keeps the bits and bend reverts to `F32.show` (`f1`) | **FIRED** rc=1, names the bend side |
| restored | patches undone | `SELFCHECK: OK` rc=0 |

B1 and B2 are **different defects** and the row must catch both: a check that only compared
py against a literal would have passed B2. That is `nv_query_litter` — one mistake copied —
so each side is now asserted against the **literal** `f1065353216`, not merely against the
other side.

### 5a. ROW A IS A ROW THAT **DID** CATCH A REAL BUILDER BUG

The first `g_bw` wrote the seed's PERMUTE as the identity `[0,1,2]` instead of `[1,2,0]`.
That version **compiled**, emitted **32 rows**, and had the **same 11-op census** — so every
count in this file read it as the same graph. What caught it was the `?` row: the identity
leaves the MUL broadcasting `(4,3)` against `(4,4,3)`, the port's fold does not settle, and
`?` came out live on **17 of the 32 nodes**. A ledger entry that is only ever printed is a
claim; this one is asserted, and it is asserted *because it once fired on a real error*.

### 5b. MY OWN PROBE HAD TWO BUGS, BOTH OF WHICH THE EVIDENCE STANDARD CAUGHT

Recorded because the brief's own rule — *a vacuous check is worse than no check* — applies to
the instrument that measures the instrument.

1. **`retitle` conflated two indices.** It took one `idx` and used it as BOTH the row
   subscript and the field subscript, so it patched the **`id`** field of row 0 instead of
   `dtype`. MEASURED consequence: arm A printed `# SELFCHECK: OK` on a patch that had changed
   nothing the `?` row reads (`at_value` scans fields 2 and 3 only). Caught by **reading the
   field back** rather than trusting the verdict; the probe now asserts the read-back
   (`q3_armA_readback=dtype column now reads '?'`) before it believes any arm.
2. **`selfcheck` read two different accessors for the same graph.** The `?` row read
   `py_bw_rows()` and the float row read `emit_py("bw", None)` directly, so arm B1 patched one
   and the other never saw it. MEASURED: B1 reported OK. Fixed to one named accessor per side.

---

## 6. THE WHOLE CORPUS RE-RUN — MY `konst` CHANGE TOUCHED EVERY GRAPH

`konst` is shared, so a graph-only verification would have been the wrong scope. All 17:

    matmul AGREE   reduce AGREE    buffer AGREE   sink AGREE     range AGREE
    rangeflat AGREE  cast AGREE    special AGREE  binblob AGREE  group AGREE
    commute AGREE  indexed AGREE   sym AGREE     lin DISAGREE   loop DISAGREE
    gate AGREE     bw AGREE

`lin` and `loop` DISAGREE for **their own documented port gaps and not because of this unit**,
confirmed by reading the named field rather than assuming:

* `lin`, 1 node of 46: `arg py=kI(sr_4_5_3,n(Opt(op=EOptOps.SPLIT…)),N,i0) bend=kI(sr_4_5_3,n(q),N,i0)`
  — the `applied_opts` residual, `graphcmp-LIMITS.md` §2.
* `loop`, 1 node of 25: `dtype py=void bend=?` — the CALL dtype, `fold.bend`'s `call_dt` reading
  a `CallInfo.dtype` CPython does not have. **This is the corpus's only live `?` and it is
  `loop`, not `bw`.**

`graphcmp-oracle.py`: **rc=0, `ORACLE SELFCHECK: OK`**, `OP NAMES ALL IN Ops: 35/35`, and the
census's own vocabulary check is what makes "35 of 77" a count over a verified vocabulary.

---

## 7. WHAT LANDED, AND WHERE

| file | what |
|---|---|
| `.agents/slop/graphcmp.py` | `g_bw` (:1270), `GRAPHS += "bw"` (:1284), `f32bits` (:414) + `_carg`'s float arm (:621), `plant_disarm` (:1478), `plant_dsexpand` (:1519), `PLANTS` (:1575), `py_bw_rows`/`bend_bw_rows`, **three** new `selfcheck` rows (:2350ff) |
| `.agents/slop/graphcmp.bend` | `konst`'s float arm (:200), `g_bw` (:1037), the `Bool.pick` rung (:1104) |
| `.agents/slop/backward-graph/` | NEW — `bw-p1.py` (the CPython measurement), `bw-p2.py`+`.txt` (plant + disarm), `bw-p3.py`+`.txt` (the three arms), `bw-census.txt`, `fs-probe.bend` |

**NOT TOUCHED, and stated because two units collided in `graphcmp.py` earlier this session:**
no `.bend` under `tinybendygrad/`; not `graphcmp-LIMITS.md` (corrections are §8 below, for its
owner to apply); not `graphcmp-run.sh`, `graphcmp-repro.sh` (its `$ALL`/`$WANT` need `bw` added
— see §8); not `.agents/slop/backward/`. **Nothing committed.** The coordination record is
`.agents/slop/GRAPHCLAIM-bw.txt`.

### 7a. ONE BEND LINE TOOK THREE PASSES, AND THE ERROR NAMED NEITHER

`+p102 = O.UOp.new(…, O.ATuple{[1, 0, 2]}, O.ANone{}, O.TNone{})` had **six** arguments where
every other call has five (`ar, op, src, arg, tag`). The extra `ANone` pushed `TNone` off the
end, and the checker said `expected : O.Tag / observed : O.Arg` with the whole binder context
dumped and no location inside the expression. **The port's `arg`/`tag` SPLIT is what turned an
arity mistake into a type error rather than a silent field swap** — a builder with one `arg`
field would have taken six arguments happily and written a wrong graph.

---

## 8. FOR THE FILE'S OWNER — corrections and the two pins that must move

`graphcmp-LIMITS.md` is another unit's live edits, so these are **reported, not applied**:

1. **§2's float-CONST entry is now RESOLVED and its text is wrong the moment it is read.**
   It says the arm is untested; it is measured, and both sides were wrong. Replace with §3
   above and the `f32bits` docstring.
2. **§5's "34 of 77" is now 35 of 77, 189 -> 221 nodes, 1134 -> 1326 field-records, 16 -> 17
   graphs.** `EXPAND` moves out of NOT REACHED into REACHED at `2/1`. The new NOT-REACHED
   list is 42 entries and is printed by `bw-census.txt`.
3. **§2's "THREE of the eight ledger markers are live on NO graph: `u`, `X!` and `BAD`" still
   holds** — the census reprints `['u', 'X!', 'BAD']`.
4. **§0's "TWO GRAPHS DISAGREE" still holds** (`lin`, `loop`), and `bw` is a THIRD AGREE.
5. **`graphcmp-run.sh`'s `$ALL` needs `bw:AGREE` and its graph loop needs `bw`** — a graph in
   `GRAPHS` that `$ALL` does not enumerate is a graph no run asserts.
6. **⚠ SUPERSEDED HANDOFF ITEM — do not act on "must become 15".** Re-measured 2026-10-04
   by `notes-sweep`: the pin's correct value is **`22`**, not 15 and not 14 (22 AGREE of 24
   graphs; DISAGREE on `lin` and `loop` only). **The pin also has two siblings that are
   equally wrong** — `graphs=16` (now **24**) and `byte-identical=14` (now **21**) — so the
   gate refuses a correct run for three reasons at once.
   **`graphcmp-repro.sh`'s health gate reads `graphs-agree=14`** and must become **15**, and
   its "sixteen graphs" text becomes seventeen. MEASURED in §6 that all 17 re-run correctly
   with `bw` in place.

---

## 9. WHAT IS *NOT* CLAIMED

- **`bw` is ONE fixture, and `AGREE` on 32 nodes over 10 ops is a claim about 32 nodes.** It
  is the **strongest single backward fixture in the corpus and it is still 2 nodes per
  `EXPAND`** — `END`, `ENDIF`, `BACKEDGE`, `IF` and `CALL` are all at exactly 1 node and remain
  so. `gate` (14 nodes, 12 ops) is still the strongest single fixture overall.
- **A backward graph is not a training loop.** `bw` is the gradient of ONE eager expression.
  The scheduler-and-codegen direction (`lin`, `loop`, `gate`) is still forward-only, so
  "the corpus now compares training graphs" would be false — what is now true is that the
  differ compares a graph that **gradients** produced.
- **No `--plant-side`**, deliberately: planting the bend side means writing DAG rewrites in
  Bend against a graph the port builds node for node. Every plant is py-side, as before.
- **`?` is 0 on `bw` and `?` is STILL live on `loop`** (1 node, the CALL dtype). This unit did
  not close that and `fold.bend` is not this unit's file.
- **Two runs is not a reproducibility study.** `graphcmp-repro.sh` over the whole `D`
  directory is that, and it is the other unit's script.
- **The `EXPAND` coverage is a count of 2 nodes in 1 graph.** `EXPAND 2/1` is the weakest
  coverage there is and the table says so; `END` and `ENDIF` have the same denominator.
- **Nothing was committed**, and `GRAPHCLAIM-bw.txt` is the record of what was held and when.