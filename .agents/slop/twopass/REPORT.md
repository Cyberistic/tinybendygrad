# twopass — SHAPE C, judged, measured, and a NARROWER reader landed in its place

**Verdict: LANDED, and NOT the shape I was told to build.** `tinybendygrad/uop/fold.bend`
grows **6819 → 7007 lines (+188)**, `--check-only` reads **`ALL PROOFS CHECK`**, the file's
own **334-row gate is BYTE-IDENTICAL**, and **`graphs-disagree` is 2 → 1**.

| measurement | instrument | reading |
|---|---|---|
| `fold.bend --check-only` | `checks/bounded.py --mb 2048 --` | `ALL PROOFS CHECK`, **`WITHIN-LIMITS`**, rc=0, 455 MB |
| `fold.bend` own gate, 334 rows | `bend fold.bend`, diffed against the same file with `fold.bend.PRE` restored | **IDENTICAL** |
| corpus, all **34** graphs | `twopass-regress.py`, before = `runs/graphcmp/D/` | **33 `same`, 1 MOVED** (`unshard`) |
| `unshard` | `graphcmp.py diff --graph unshard` | `DISAGREE` → **`AGREE`**, `field-mismatches` **2 → 0**, `settled` `False` → `True` |
| `graphs-disagree` | same lane | **2 → 1**, the survivor is `flip` |

`fold.bend` was **IDLE** before I edited it (md5 `a1482775…`, three reads 32 s apart,
identical, `pgrep -f bin/bend` empty) and the **+188 lines are all mine** — a def-name diff
against the restored `fold.bend.PRE` reports **0 defs added by anyone else**.

---

## 1. THE HEADLINE QUESTION — DOES THE SECOND PASS SEE A COMPLETE TABLE, OR MERELY A LARGER ONE?

**It sees a LARGER one — and the second pass would still have had the input it needs.
MEASURED, not assumed.**

`.agents/slop/twopass/probe.bend` builds graphcmp.py's `g_unshard` node for node and prints,
for every node, the **pass-1** main fold's dtype and the **pass-1** `mm.sweep` interval:

```
i=6 op=-      dt1=weakint  vmax1=+0:2
i=7 op=RANGE  dt1=weakint  vmax1=+0:1     <-- Shape C's INPUT EXISTS
i=8 op=-      dt1=NONE     vmax1=NONE    <-- the UNSHARD node, unanswered in pass 1
```

**SO SHAPE C'S PREMISE HOLDS**: `mm.sweep` does put a NUMBER on the RANGE, and
`int(r.vmax)+1 = int(1)+1 = 2` against `UOp.range(2, …)`. **Shape C is not a fix that moves
the `?`.** The prior unit's worry was unfounded *on this question*.

**AND YET THE SECOND PASS IS NOT COMPLETE, IN TWO SEPARATE WAYS, AND BOTH ARE MEASURED:**

1. **Its own output is not in its input.** `BTable` is `mm.sweep(ar, pass1_table)`, and
   `mm.node.of` answers a node only if `fold.dt(pass1, i)` is `Some` — so the UNSHARD node
   has **no interval** in the table that pass 2 reads (row `i=8`, `vmax1=NONE`). **That does
   not block UNSHARD or STAGE**, because neither reads its *own* interval: both read
   `src[1:][…]`'s. It is a bound on what pass 2 could be extended to, not on these two arms.
2. **A second pass would be a FIXED POINT, and that is provable rather than lucky.** Pass 2's
   arms read a RANGE's interval, and a RANGE's interval is `mm.range` over its CONST src —
   a row pass 1 already answers. Nothing pass 2 newly answers feeds back into the quantity
   it reads, so `T3 = T2`. **One extra pass is enough, and it is enough for a reason.**

## 2. THE HONESTY LINE — WHICH SIDE, STATED BEFORE THE CHANGE

`unshardtable` drew it: a fix that closes the four own-walls **and** settles the 49 cascades
is over-reaching; a correct fix is **53 → 51**, and a graph with a symbolic src still reads `?`.

**I am on the REFUSING side, and I state it as three commitments rather than one:**

- `rng_width` returns **`None{}`** for any range whose `src[0]` is not an integer CONST. No
  field is defaulted and no width is guessed.
- `unshard_scaled` returns **`None{}`** for an `SU` (symbolic) dim rather than dropping the
  scale or keeping the dim unscaled — both of which are wrong shapes.
- **The 49 cascade arms are not touched.** Cascade refusal is `Kahn.go.of` refusing when any
  src is unresolved, and nothing in this change makes a `marg` answer.

**AND MEASURED, NOT ASSUMED — the line held. §4 (b) is four separate refusal fixtures.**

## 3. WHY I DID NOT BUILD SHAPE C, AND WHAT IT WOULD HAVE COST

**Shape C's premise is sound. Its COST is not local, and the brief's "no 680-line
relocation" is true only in the narrow sense that C needs ~0 lines of relocation — it needs
the FOLD ITSELF rewritten.** Measured:

* `dt_shape` is at `fold.bend:2412`; `mm.sweep` at `:5027`, `BTable.get` at `:4990`,
  `UOp.vmax` at `:5042`. **All below it.** Only `@unsafe` may call downward
  (`references/bend/guide/GUIDE.md:113-121`) and **there is no `@unsafe` in this file** —
  so a `BTable` cannot be read inside `dt_shape` at all, and the thread is not the cost, the
  READ is.
* `UOp.fold` (`:4660`) cannot call `mm.sweep`, so `UOp.fold` + `folded` + `Ranged` would have
  to **move below the `mm` block**.
* That would make **every `F.folded(ar)` / `F.UOp.fold(ar)` call site pay a SECOND Kahn walk
  per arena**, and every `ranges`/`min_max` sweep would read a different table than today —
  with `render.bend` among those call sites and `render.bend` off-limits to me.

**So I built `rng_width`: the SAME number, read from the arena, at ONE-TENTH the blast
radius.** The arithmetic is not a substitute for `_min_max`, it is `_min_max` specialised,
and the specialisation is an identity:

> ops.py:1147 gives a RANGE/SPECIAL `0, (self.src[0]-1).vmax`; ops.py:1110's SUB arm gives
> `s0_vmin-s1_vmax, s0_vmax-s1_vmin`; so for `r.src[0]` an integer CONST `c` the interval is
> `(c-1, c-1)`, `.vmax` is `c-1`, and **`int(r.vmax)+1` is `c` exactly**. The port's own
> `mm.range` is the same subtraction (`bnd.sub(Bnd2.hi(mm.s0(srcs)), bnd_one())`).

**AND THE COST IS ZERO RELOCATION, NOT 680 LINES.** `rng_width` is placed immediately after
`const_i64` (`fold.bend:1400`), which is ABOVE `dt_shape`; it calls only `const_i64` and
`O.Arena.*`, and `O` is an **import** (order-free across files). **Nothing moved, no
signature grew except `stage_ds`/`stage_shape`, and no file outside `fold.bend` changed.**

## 4. THE PLANT, BOTH HALVES, WITH CPython's COLUMN

`twopass-oracle.py` builds the same four fixtures through CPython; `plant.bend` builds them
through the port. The (b) rows are **divergences on purpose** and CPython's column is what
makes them readable rather than merely absent.

| fixture | CPython | port | state |
|---|---|---|---|
| **(a1)** `UNSHARD(a, range(2,0,DEVICE)), arg=(0,)` — corpus `g_unshard` | `f32` `(8, 3)` | `f32` `(8, 3)` | **AGREE** — was `?`/`?` |
| **(a2)** `STAGE(a, range(3,0,DEVICE)), arg=None` — **the corpus does not have this** | `f32` `(3, 4, 3)` | `f32` `(3, 4, 3)` | **AGREE** — was `None{}` |
| **(b1)** `RANGE(SPECIAL)` — `rng_width`'s own refusal | `f32` `(0, 3)` | `dtype=NONE shape=NONE` | **REFUSES — labelled divergence** |
| **(b3)** `arg=(9,)` — an axis a `(4,3)` shape lacks | `f32` `(4, 3)` | `f32` `(4, 3)` | **AGREE** (nothing scales) |
| **(b4)** `EXPAND` onto a symbolic marg, under a `STAGE` | `f32` `(2, 0, 3, 4, 3)` | `f32` `(2, 0, 3, 4, 3)` | **AGREE** |

**(b) IS NOT ONE FIXTURE. One `?` does not say WHICH reader refused, so there are four:**

```
== (b1) RANGE(SPECIAL) -- rng_width refuses
  node#9  op=Ops.UNSHARD dtype=NONE shape=NONE          <-- rng_width REFUSED
== (b2) RESHAPE onto a SYMBOLIC marg
  node#6  op=Ops.RESHAPE  dtype=NONE shape=NONE          <-- marg REFUSED
  node#9  op=Ops.UNSHARD  dtype=NONE shape=NONE          <-- the CASCADE, unchanged
== (b3) arg names an axis the shape lacks
  node#8  op=Ops.UNSHARD  dtype=f32   shape=(4,3)        <-- CPython agrees
```

**`rng_width` REFUSING ON (b1) IS THE POINT OF THE WHOLE EXERCISE.** CPython answers `(0,3)`
there (the SPECIAL's `_min_max` is `(0, 0)`, a point); the port reads `?`. **That is a
divergence and it is declared, not disguised** — which is the line between a fix and a lie.

## 5. THE HONESTY LINE — WHAT I MEASURED, AND A CORRECTION TO THE BRIEF'S NUMBER

**THE BRIEF'S `53 → 51` IS NOT REPRODUCIBLE BY THE INSTRUMENT THAT PRODUCED IT, AND ONE OF
ITS FOUR MEMBERS IS MEASURABLY WRONG IN THIS TREE.**

`refusal_population.py:108` is a **hard-coded literal**:
`OWN_WALL_OPS = {"OpsUNSHARD", "OpsSTAGE", "OpsRESHAPE", "OpsEXPAND"}`. **That is doctrine
1's failure — a hand list standing in for a population — inside the census of doctrine 1**,
and it cannot move: re-run after landing, it still prints `own-wall-refuse 4` and names
`OpsUNSHARD` (`refusal-after.rows`).

**MEASURED, ARM BY ARM:**

| named own-wall | before | after | evidence |
|---|---|---|---|
| `UNSHARD` | `None{}`, unconditional | **answers** | (a1), CPython agrees |
| `STAGE` w/ ranges | `None{}` whenever the tail is non-empty | **answers** | (a2), CPython agrees |
| `RESHAPE` | refuses | **STILL REFUSES** | (b2) `dtype=NONE` |
| **`EXPAND`** | **already answered** | answered | (b4) `(0,3,4,3)`, CPython agrees |

**`EXPAND` WAS NEVER A WALL.** `sym_dim` answers a POINT interval as its int
(ops.py:269-270's `x.const_like(x.vmin) if x.vmin == x.vmax`), the SPECIAL "N" has
`_min_max == (0, 0)` — MEASURED, calling CPython — so `expand_ds` has been answering all
along and the census over-counts the own-walls by **at least one**.

**SO: I AM NOT REPORTING A CORRECTED DENOMINATOR, BECAUSE I CANNOT MEASURE ONE.** What is
measured is the thing that matters: **two arms moved from unconditional-refuse to
conditional-answer, one named own-wall (`RESHAPE`) still refuses, and the 49 cascade arms are
untouched by construction.** Anyone wanting the integer should fix
`OWN_WALL_OPS` into a measurement first; re-running the census as it stands would report
`53 → 51` and be **right by coincidence and for the wrong reason**, which is the failure
mode `unshardtable` spent its whole report documenting.

## 6. `diff --graph stage` — AND THE FIXTURE THE CORPUS CANNOT REACH

**`stage` is `AGREE`, `field-mismatches=0`, `settled=True`, and it was `AGREE` BEFORE. My
change moved zero rows of it.**

**AND THAT IS EXACTLY THE TRAP `unshardtable` NAMED, CONFIRMED A SECOND TIME.** `g_stage`
is `(Tensor.empty(4,3) + 1).contiguous().uop` — a **one-src, no-range** STAGE, so its prepend
is empty and the arm was **already total**. MEASURED from the file's own gate:

```
mmkx_stage  n=2 op=Ops.STAGE nsrc=1 srcops=Ops.CONST
mmkx_sibling_stage n=2 op=Ops.STAGE nsrc=1 srcops=Ops.CONST
```

`nsrc=1`. **The corpus CANNOT TEST THE CASE THIS CHANGE EXISTS FOR.**

**AND THE FILE'S OWN 334-ROW GATE CANNOT EITHER — one level down, and this is the finding I
did not expect.** `grep -c unshard fold-gate.rows` is **0**: there is **no UNSHARD row at
all**, and all three STAGE rows are `nsrc=1`. **That is why the gate came back
BYTE-IDENTICAL: it cannot see this change.** A gate that is identical before and after a
change has not verified the change; it has verified that it does not look at it.

**WHAT WOULD HAVE TO BE ADDED** — two sides, because the differ needs both:

```python
# .agents/slop/graphcmp.py, GRAPHS
def g_stage_range():
  """(a2) `UOp(Ops.STAGE, src=(a.uop, UOp.range(3, 0, AxisType.DEVICE)), arg=None)` -- the
  multi-device `bufferize` shape, which is the ONLY STAGE whose prepend is non-empty and so
  the only STAGE the width reader is load-bearing for. MEASURED census: `BUFFER=1 CONST=2
  RANGE=1 RESHAPE=1 STACK=1 STAGE=1`; the row is `STAGE dtype=f32 shape=(l0:3,l0:4,l0:3)`."""
  from tinygrad import Tensor
  a = Tensor.empty(4, 3, dtype=dtypes.float).uop
  return UOp(Ops.STAGE, src=(a, UOp.range(3, 0, AxisType.DEVICE)), arg=None)
```
plus `"stage_range": g_stage_range` in `GRAPHS`, **and** the matching `def g_stage_range()`
in `.agents/slop/graphcmp.bend` (which builds its own arena at `graphcmp.bend:1557` for
`g_stage`) — **one side alone would compare against nothing.**

**AND ONE MORE, which nobody has asked for and which the census says is worth more:** a
`g_unshard_sym` carrying a `RANGE(SPECIAL)` src, because that is the only fixture that would
hold (b1) in the corpus and keep `?` a **measured** state instead of a note.

## 7. `graphs-disagree` 2 → 1 — AND IS THE SURVIVOR A ONE-LINER?

**2 → 1. The survivor is `flip`, and it is NOT a one-liner and NOT a vocabulary change.**

* `field-mismatches` for `flip` is **0 before and 0 after** — so its disagreement is **not on
  the dtype/shape axis at all**. Both `diff-flip.out` and the recorded
  `runs/graphcmp/D/D1-graph-flip.txt` carry the identical line `# arg py=n(b1,b0) bend=n(i1,i0)`
  — a **Bool-tuple arg printed by identity on one side and by value on the other**.
* So my change did **not** touch it, and the answer is measured rather than argued.
* `flipblock`'s figure stands: **`fold.bend:1850` `order_arg` needs 2–3 edits, not one line**,
  plus `prepare.bend:277` and `tensor.bend:950` "so the differ does not stop modelling what
  the port builds". **It is an arg-ENCODING divergence — a representation disagreement about
  what a `Bool` tuple is — and the honest one-word answer is: NEITHER. It is a vocabulary
  change AND it is not one line.**

## 8. WHAT ONLY `bend` SETTLED, AND WHAT I RAN

**`bend` IS AVAILABLE AT `./bin/bend` — THE PRIOR UNIT'S "ABSENT FROM PATH" WAS PATH-ONLY.**
`command -v bend` is empty and `./bin/bend` is a 2 097-byte shim onto
`references/bend/bend2/main.ts`. **Everything below ran.** Every `bend` invocation went
through `checks/bounded.py --mb 2048 --` and every verdict is read off the **TOKEN**:
**`WITHIN-LIMITS` on all of them**, peak 193–832 MB, 1–4 s each.

| what only `bend` settled | how |
|---|---|
| the patch compiles **with proofs intact** | `fold.bend --check-only` → **`ALL PROOFS CHECK`** |
| the second pass's input exists | `probe.bend` → `i=7 op=RANGE vmax1=+0:1` |
| the two `(a)` arms answer, the four `(b)` states refuse | `plant.bend` → 5 arenas, one row per node |
| `unshard` reaches parity, 33 graphs do not move | `twopass-regress.py` over all 34 |
| the file's own gate does not move | 334-row `diff` = IDENTICAL |

**WHAT IS NOT SETTLED, AND CANNOT BE BY THIS UNIT:**
* **`(b1)` is a divergence CPython does not have** and only `mm.sweep` closes. That is the
  remaining `rng_width` wall, and it needs the `BTable` thread — §3's cost.
* **STAGE-with-ranges has no denominator** (§6). My change is **unreached by both the corpus
  and the file's own gate**, and the only fixture that exercises it is `plant.bend`, which is
  a scratch file under `.agents/slop/`. **Per `AGENTS.md`, that is a gate input in a swept
  tree: it should be promoted beside the thing it tests.**
* **No full `differ.py run`.** I ran `graphcmp.py diff --graph` per graph against the
  recorded run dir, which is a per-graph comparison and **not** the 17-pin run health
  `AGENTS.md` describes.

## 9. THE INSTRUMENT THAT WAS DEAD, AND THE LINE THAT MOVED

**My own regression lane was DEAD on its first run and I would have reported 34 regressions
had I not keyed on the token.** `twopass-regress.py` built a minimal `ENV`
(`PATH=/usr/bin:/bin:/usr/local/bin`) to be deterministic; that **dropped `bun`**, which is
what `bin/bend` execs, so **all 34 graphs printed no verdict**, every row read `?`, and the
table printed **`MOVED 34`**. **A rebuilt PATH IS WHAT MADE IT DEAD.** Fixed by
`env -u PYTHONPATH`-shaped inheritance; and the lane now prints **`DEAD`** rather than
`MOVED` when a verdict is missing, so a lane that measures nothing **cannot print a movement
count**. That is doctrine 2's `DEAD` state, and it is the second time in this unit's
history that a *green-looking* row count would have been a lie.

---

### Instruments (this unit; all `.py`/`.bend`, `.venv/bin/python`, `./bin/bend`)

* `.agents/slop/twopass/probe.bend` — pass-1 `Table` + `BTable` per node. **The headline.**
* `.agents/slop/twopass/plant.bend` — 5 arenas, one row per node: `(a1)` `(a2)` and four
  distinct `(b)` refusals. The population is `O.Arena.nodes(ar)`, walked by the compiler.
* `.agents/slop/twopass/twopass-oracle.py` — **CPython's** column for the same fixtures.
* `.agents/slop/twopass/twopass-regress.py` — all 34 graphs, before = `runs/graphcmp/D/`.
  Keys on the VERDICT TOKEN and `field-mismatches`, never on row index or line count;
  **never compares two of its own runs.**
* `.agents/slop/twopass/fold.bend.PRE` — the 6 819-line tree, the "before" for the 334-row gate.
* Rows: `plant.out` `probe.out` `oracle.rows` `regress.rows` `fold-gate{,-PRE}.rows`
  `refusal-after.rows` `base-check.out` `land-check.out`; stderr carries the bounded token.