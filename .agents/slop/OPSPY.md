# OPSPY — `runtime/ops_python.bend`: the bitcast dedup, and what its coldness was

Unit: `.agents/slop/opspy/`. **Nothing committed.** Owns
`tinybendygrad/runtime/ops_python.bend` + these notes. Compiler **Bend 2.0.34** via
`./bin/bend`. Rule prefix `OPS-` (appended to `notes/bend2-constraints.md`).
Co-ordinating file's own note: **OPSPY.md**.

## HEADLINE: THE COLDNESS WAS 100% INHERITED, AND IT WAS RETIRED UNDER ME

`runtime/ops_python.bend` declared **zero laws of its own**. Every red def it
reported was `../dtype.*`, and the name list was **identical member for member** to
`dtype.bend`'s own 8. Mid-measurement the unit owning `dtype.bend` filled all
eight; the file went **COLD -> WARM**, and took `nn/{__init__,optim,state,onnx}`,
`runtime/zzprobe2`, `test/dtype_oracle`, `test/_probe/v5` and `dtype.bend` itself
out of the cold set with it. **The tree's cold set is now 6 of 137, not the 14
agent-core.md records.**

---

## 1. THE DEDUPLICATION

`F32.from_bits` (`tinybendygrad/base.bend:54-56`) imported; the local pair deleted.

| was | now |
|---|---|
| `ops_python.bend:257-262` six imports | `+ import ../base.bend as F` at **:258** |
| `ops_python.bend:274-276` `def w32` | **deleted** |
| `ops_python.bend:278` `def f32_of` | **deleted** |
| `ops_python.bend:550` `O.CFloat{f32_of(b)}` | **`O.CFloat{F.F32.from_bits(b)}`** (`:551`) |
| `ops_python.bend:607` `f32_of(b)` | **`F.F32.from_bits(b)`** (`:611`) |
| `ops_python.bend:264-272` the hand-written bitcast note | **:265-280**, states both directions |

`+2 imports become 6`, and the 5-line comment now says WHY the local pair is gone
and that `U32.to_f32` is not this. **`F32.bits` — the inverse — was already the
`law` at `base.bend:1697` and needed no change**: one name per direction, so the
file cannot disagree with `base.bend` about either. **Net −7 lines.**

### Rows passed against rows expected

Two lanes, whole `name=value` lines, never row names. Before/after of the *device*,
not of the two functions.

| lane | rows expected | passed | note |
|---|---|---|---|
| the file's own `gate()` | 85 | **85** | BYTE-IDENTICAL |
| `.agents/slop/nested/gate.py` (compiled executor vs CPython oracles, whole output buffers, bit-for-bit) | 10 | **6** | BYTE-IDENTICAL on all 10 case lines; the 4 fails are the pre-existing nested-`RANGE` wall documented at `ops_python.bend:20-25`, unchanged |

`zsh .agents/slop/opspy/verify-dedup.sh` puts the pre-dedup spelling back in place,
measures, and compares. **The e2e diff is empty except line 1, which echoes the
exe's own path and is not an answer.**

---

## 2. THE COLDNESS, SPLIT

### ITS OWN LAWS: **none. Zero.**

`--check-only` on the file named 8, every one prefixed `../dtype.`; the same 8
names, unprefixed, on `dtype.bend`. Nothing in `ops_python.bend` is a `law`.

### INHERITED: 8, and **7 of the 8 had ZERO call sites**

Measured by grepping `tinybendygrad/**/*.bend` and **subtracting the declaration
line** — every other hit for these names is prose in another file's header.

| law | call sites |
|---|---|
| `Dt.i64_trunc` `dtype.bend:1064` | **0** |
| `Dt.i64_floor_div` `:1067` | **0** |
| `Dt.i64_floor_mod` `:1070` | **0** |
| `Dt.i64_cdiv` `:1073` | **0** |
| `Dt.i64_cmod` `:1076` | **0** |
| `Dt.i64_ceildiv` `:1103` | **0** |
| `float_to_fp8` `:1128` | **0** |
| `Dt.fp8_from` `:1060` | **1** — and it is from *inside* `float_to_fp8` |

**Seven of the eight were an unused door, and the eighth door was behind them:**
`float_to_fp8` is called by nothing, and `Dt.fp8_from`'s single caller is inside
it. **One island, one root, eight names — not eight walls.** This file is the
opposite object from `dtype.bend`'s 14-law wall, and the two have opposite
remedies: the wall wanted bodies, the island wanted reachability.

### WHAT I RETIRED, AND HOW MUCH

**0 laws, 0 defs, 0 `IO` added.** The cause was `dtype.bend`'s, and `dtype.bend`
is not this unit's file — its owner retired all eight while I measured. I made no
fold effectful to make a gate pass. What this unit retired is the **duplicate**:
5 lines of def plus a 9-line hand-written note, replaced by one import line.

### WHAT I COULD NOT FIX

- `ops_python.bend:20-25` — the nested-`RANGE` wall: `Prog.loop`/`Prog.rng` walk
  `loop_ends` and the nested END at `ops_python.py:70` jumps to the inner head.
  4 of 10 E2E cases, all `depth>=2`. Untouched.
- `ops_python.bend:2370` (`compile`, WALL 5) — the base64 quartet fold, still
  wrong against CPython. Untouched; no `pyc_*` rows exist because a row that
  encodes a bug is worse than no row.
- `ops_python.bend:255` — the KNOWN-FAIL `SQRT` over an int32 element.

---

## 3. PLANT AND DISARM

`zsh .agents/slop/opspy/mutate.sh`. **Disarm first.**

```
BASE                                        own 0/85   e2e 6/10   red 0
DISARM D1  from_bits(b) -> the inline        own 0/85   e2e 6/10   COMPILES
           destructuring + constructor
PLANT  P1  F32.from_bits -> U32.to_f32       own 0/85   e2e 1/10   COMPILES CLEAN
```

**D1 is a real disarm**: the destructuring plus the constructor spelled longhand is
the same function, and it moved nothing. FROMBITS' two failed disarms each turned
"the same test" into "the other test" and moved 116 984 and 215 288 rows.

**P1 compiles clean and moves the E2E lane 6 → 1**, which is FROMBITS' documented
trap restated in this file: `U32.to_f32(3)` is 3.0, so the wrong primitive answers
a plausible float. Five cases lost, including `sumall3`, which is **depth 0**.

**AND THE FINDING NOBODY ASKED FOR: the file's own 85-row gate moved 0 under P1.**
Those rows are all `pyr_*`/`pyc_*`/`pywma_*`/`pyd_*` — the renderer/device half —
and none reaches `f_of` or `elem_c`. **85 rows wide, half a file.** The only lane
that can see the bitcast is the E2E one.

**The plant and disarm were disarmed twice by my own harness before they worked**,
and both times it printed a number: `bend -o` on a file that does not compile
leaves the PREVIOUS exe, so the E2E lane ran the baseline build and reported 6/10
for a mutation that never ran; and `--check-only` naming 4 red defs instead of 8
was counted as "moved=85 of 85". Fixed by `rm -f` on the exe, a **derived**
baseline red count, and a non-empty assertion before every comparison. Restore is
`cmp`-asserted and trap-guarded on all signals, because a `$TMPDIR` copy cannot
resolve this file's four relative imports.

---

## 4. THE TWO FIGURES I WAS TOLD NOT TO TRUST, RE-MEASURED

- **Corpus: 60 of 77 [SUPERSEDED - see CORPUS.md: a union over ZERO graphs that built], not 61.** `.agents/slop/opspy/corpus.py`, over the 22 graphs [SUPERSEDED: was 25; see CORPUS.md]
  `graphcmp.GRAPHS` declares, by set UNION — the per-graph sum is **182** and is
  wrong, it counts `BUFFER` once per graph. Denominator `len(Ops) = 77` holds.
- **`bw` reaches 10/10 of 77 [SUPERSEDED - see CORPUS.md: a union over ZERO graphs that built], not 35.** `bw-census.txt`'s "35 of 77" was a
  17-graph corpus figure quoted as the graph's own. `AGREE`, 0 residuals.
- **`backward`: still byte-identical.** `bwd-oracle.py` output == `bwd-oracle.txt`,
  and `oracle-cg.py`'s 20 reachable rows reproduce byte-identically; `rc=1` is the
  oracle's own second fixture dying at `oracle-cg.py:116`.
  `walk-row.txt:50`'s **`AGREE 15 / 15 rows`** is real and stands.

**AND A NEAR-MISS WORTH RECORDING: I nearly reported `graphcmp.py:1506`
(`g_allred`, `NameError: name 'dtypes'`) as another unit's live defect. It is not.
`graphcmp` defers every tinygrad import into `load_tinygrad()` and injects the
names into ITS OWN `globals()`; without that call all 22 graphs [SUPERSEDED: was 25; see CORPUS.md] raise and my union
printed "0 of 77 [SUPERSEDED - see CORPUS.md: a union over ZERO graphs that built]" beside a healthy denominator.** A defect in a measurement is not
a defect in the substrate until it survives a second instrument.

---

## 5. REPRODUCE

```sh
zsh .agents/slop/opspy/verify-dedup.sh   # the dedup, both spellings, two lanes
zsh .agents/slop/opspy/mutate.sh         # disarm first, then the plant
env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/opspy/corpus.py
```

## 6. FILES

`tinybendygrad/runtime/ops_python.bend` (live, −7 net lines, WARM) ·
`.agents/slop/opspy/verify-dedup.sh` · `mutate.sh` · `corpus.py` ·
`.agents/slop/OPSPY.md` · `notes/bend2-constraints.md` (**OPS-1 … OPS-6**, appended)