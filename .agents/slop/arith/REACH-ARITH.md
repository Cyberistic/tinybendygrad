# arith-unit — the six arithmetic ops. 53 -> 59 of 77, both sides.

2026-10-04. Nothing committed. Claim on the three contested files: `.agents/slop/arith/CLAIM.md`.

## 1. RE-MEASURED FIRST, both sides, with the split

Instrument: `.agents/slop/arith/both-census.py`. The previous instrument
(`.agents/slop/reach/census.py`) **only counted the py side**, so "both sides read 53" in
`REACH.md` was not produced by anything that could have found the two sides differing. This
one emits every graph on both sides and prints the split.

```
                              BEFORE            AFTER
graphs in corpus              22                24
ops UPSTREAM (denominator)    77                77      measured len(list(Ops)), not transcribed
reached PY                    53                59
reached BEND                  53                59
reached BOTH                  53                59   <- the honest coverage number
py-only  (bend MISSING)       []                []
bend-only (py MISSING)        []                []
reached by NEITHER            24                18
WALLS                        []                []
```

The split is still empty, and it is the split that makes this a coverage statement: both
sides grew by the same six and neither grew alone. **BEFORE is recomputed from the run-1 row
cache on disk** (`rows-<graph>-py.txt`, written before any edit), not from my memory of a
terminal line — re-running `both-census.py` with `cdiv`/`late` excluded prints 53.

The 18 left: `ALLREDUCE COPY CUSTOM CUSTOMI CUSTOM_FUNCTION GETADDR INS MSELECT MSTACK MULACC
PROGRAM PYLITERAL REWRITE_ERROR SOURCE STAGE THREEFRY UNSHARD WMMA`.

**A NUMBER HERE IS NOT MINE ALONE.** `flip` read DISAGREE 6/7 when this unit took its
baseline and reads **AGREE 6/6** now, because another unit added `canon_flip` to
`graphcmp.py` *after* my baseline copy was taken (`grep -c canon_flip`: 0 in
`arith/baseline/graphcmp.py.BASELINE`, 6 in the current file). That unit and this one edited
the same contested file inside the same window. The merge is clean and everything below is
measured on the merged tree: `bend --check-only` = `ALL PROOFS CHECK`, `selfcheck` = OK, and
all 22 pre-existing graphs keep their prior verdicts (`lin`/`loop` still DISAGREE, `flip` now
AGREE, everything else AGREE). The collision was real and it is reported rather than papered
over.

## 2. WHICH OF THE SIX, AND BY WHOSE CODE

All six. **CDIV and CMOD from the EAGER path; SUB, NEG, CMPEQ and FDIV only from a REWRITE.**
That split is the finding, and it is measured by CALLING CPython through the differ's own
emitter, not by reading `Ops`:

| op | eager construction | eager census (MEASURED) | how it is reached |
|---|---|---|---|
| CDIV | `a.div(b, rounding_mode="trunc")`, int | `CDIV 1` | **eager** |
| CMOD | `a.fmod(b)`, int | `CMOD 1` | **eager** |
| SUB | `a - b` | `ADD=1 MUL=1 CONST=3` — no SUB | rewrite |
| NEG | `a.neg()` | `MUL=1 CONST=3` — no NEG | rewrite |
| CMPEQ | `a.eq(b)` | `CMPNE=2 CONST=3` — no CMPEQ | rewrite |
| FDIV | `a.reciprocal()` | `RECIPROCAL=1` — no FDIV | rewrite |

**Each of the four eager spellings is exactly the left-hand side of the upstream rule that
mints the op**, which is why they are rewrite-only and not merely hard:

- `tinygrad/mixin/elementwise.py:123` — `sub` is `a.alu(Ops.ADD, -b)`
- `tinygrad/mixin/elementwise.py:82` — `neg` is `self * (-1)`
- `tinygrad/mixin/elementwise.py:336-337` — `eq` is `ne(x).logical_not()`
- `tinygrad/mixin/elementwise.py:255` — float `div` is `a.alu(Ops.MUL, b.reciprocal())`

against

- `tinygrad/codegen/decomp/op.py:105` — `x * -1` -> `NEG x`
- `tinygrad/codegen/decomp/op.py:106` — `x + (-y)` -> `SUB x y`
- `tinygrad/codegen/decomp/op.py:117` — `x.ne(y).logical_not()` -> `CMPEQ x y`
- `tinygrad/codegen/decomp/op.py:124-125` — `reciprocal x` -> `FDIV(1.0, x)`, then
  `a * FDIV(1.0, b)` -> `FDIV(a, b)`

and the two eager ones are constructed by the eager module itself:

- `tinygrad/mixin/elementwise.py:226` — `a.alu(Ops.CMOD, b)`
- `tinygrad/mixin/elementwise.py:251` — `a.alu(Ops.CDIV, b)`

`g_commute`'s docstring says CMPEQ is "NOT reachable from an eager graph at all". That is
**true and was true, and it was true because nobody had tried the REWRITE route** — which is
the route that reaches it. Reported back rather than reconciled, per `agent-core.md`.

**WHICH four the rewrite reaches is the BACKEND's, not mine.** `supported_ops` is read exactly
as `tinygrad/codegen/__init__.py:350` reads it — `tuple(Device.default.renderer.code_for_op.keys())`
— and `disable_fast_idiv` is upstream's own `bool(DISABLE_FAST_IDIV)` (`tinygrad/helpers.py:250`,
default 1). MEASURED: CPU's `ClangRenderer` wants all four; `NullRenderer` wants three (no
FDIV), and under `DEV=NULL` the same eager graph emits 13 nodes with `MUL(a, RECIPROCAL(b))`
where the CPU run emits 12 with `FDIV(a, b)`. That per-backend dependence is measured on the
**emission** and cannot be measured on a verdict — see wall 5.

## 3. THE TWO GRAPHS

| graph | verdict | nodes / fields / cores | ops reached | ledger |
|---|---|---|---|---|
| `cdiv` | **AGREE** | 10/10, 6 fields, 60 field-records, shared-cores=10 | 7/7 of 77 | `z y u q X! BAD E ?` all `0/0` |
| `late` | **AGREE** | 12/12, 6 fields, 72 field-records, shared-cores=12 | 9/9 of 77 | `z y u q X! BAD E ?` all `0/0` |

`RESIDUALS IN THIS RUN: none` on both. `ONLY-PY=0 ONLY-BEND=0 field-mismatches=0
rung2-pairs=0 rung3.5-crossrefs=0 zip-truncated=0` on both. `control` = OK on both (each side
against itself), `cross` = "it disagrees". `SELFCHECK: OK`, `ALL PROOFS CHECK`.

`cdiv` = `UOp.group(a.fmod(b), a.div(b, rounding_mode="trunc"))`, two `Tensor.empty(4,3,int)`.
census `ALLOC 2 CDIV 1 CMOD 1 CONST 2 GROUP 1 RESHAPE 2 STACK 1`.
`late` = `UOp.group(a-b, a.neg(), a.eq(b), a/b)` over two `Tensor.empty(4,3,f32)` through
upstream's own `get_late_rewrite_patterns`.
census `ALLOC 2 CMPEQ 1 CONST 2 FDIV 1 GROUP 1 NEG 1 RESHAPE 2 STACK 1 SUB 1`.

**`late` is the post-rewrite graph and the PORT DOES NOT PRODUCE IT BY REWRITING.** The py
side is upstream's matcher on upstream's eager graph; the bend side builds the rewritten graph
directly in its arena. The claim is that the port's op surface, dtype rules and arena
reproduce upstream's rewritten graph — **not** that the port can rewrite, and not that any
rewrite rule has been ported. Same shape as `g_gate` (`graphcmp.py:1183-1229`), which takes
`pm_linearize_cleanups`' output and never runs the matcher.

### `?=0` IS OMISSION, NOT CORRECTNESS — three mutations, both modes

| mutation | graph | ordered | `--equiv` | what moved |
|---|---|---|---|---|
| M1 `SUB` children swapped | `late` | DISAGREE, 2 | DISAGREE, 2 | rung-2 pair on `SUB py#8 vs bend#8`, names `src` |
| M2 `CMOD`/`CDIV` swapped in the GROUP | `cdiv` | DISAGREE, 1 | DISAGREE, 1 | rung-2 pair on `GROUP py#10 vs bend#10`, names `src` |
| M3 `CDIV` built with ONE child | `cdiv` | DISAGREE | DISAGREE | `shared-cores 10 -> 8`, `ONLY-PY=1 ONLY-BEND=1`, `rung2-pairs=1`, `rung3.5-crossrefs=1`, and `field-mismatches=0` |

M3 is the interesting one and it is the `flip` lesson one level down: **the mutation is in the
CDIV and `field-mismatches` still reads 0**, because a unary CDIV is not a missing field — it
is a different node with a different core, so `CDIV#9` goes one-sided on BOTH sides and the
report's headline mismatch is on the GROUP. The cause is named anyway, in the rung-2 body:
`src py=['60f3293c','456e0870'] bend=['60f3293c','983d6863']`. "Nothing is missing" is not
"nothing is wrong", and the headline op was not the mutated node.

No mutation was rescued by `--equiv`, which is expected and is a fact about the four ops
rather than a credit: `tinygrad/uop/__init__.py:121` puts only `CMPEQ` of the new four in
`Commutative`, and M1/M2 move non-commutative nodes.

`graphcmp.bend` was reverted **byte-for-byte** after every mutation run (md5 asserted in the
script, not by eye).

## 4. THE CLAIM NOT MADE

This does **not** mean the corpus compares training graphs. `bw` is the gradient of **one
eager expression**, and `schedule -> render -> compile` is still **forward-only**: `lin` and
`loop` DISAGREE on purpose, for named measured reasons, and `late` is a graph the port cannot
*produce* — only reproduce. 59 of 77 is coverage of the **emitter** and says nothing about
coverage of the rest of the pipeline.

## 5. WALLS, with `file:line`

1. **`.agents/slop/graphcmp.py`** — `emit_py(graph: str, plant: str | None)` takes a graph
   **NAME**, so a probe that has built its own AST cannot emit it. Either add the graph to
   `GRAPHS` or copy `emit_py`'s last two lines.
   ⚠ **CITATIONS CORRECTED 2026-10-04 by `notes-sweep`: `:1686` and `:1703-1705` were both
   WRONG.** Verified by name: `def emit_py` is at **`:1794`**, and its last two lines are
   **`:1812-1813`** (`ix = {id(n): i + 1 ...}` then `return [row_of(...)]`). `:1686` is a
   comment about not sharing an arena, and `:1703` is a `plant_dsexpand` comment. **This is
   the third wrong citation in this one section and it is the one that would have been
   hardest to notice, because the wall is about a function you cannot easily grep.** My probe copied them
   and **asserts them byte-equal against `emit_py` on `matmul`** — an unasserted copy of the
   differ's row loop is a fiction generator. First attempt reached for a
   `graphcmp.emit_py_rows_of` that does not exist: a symbol invented from the function's
   intent rather than read out of the file.
2. **`.agents/slop/reach/census.py:24`** — `recs = {r[1:]: G.unchunks(r) for r in rows}`. `r[1:]` drops the
   ✅ **CITATION VERIFIED CORRECT 2026-10-04 by `notes-sweep`** — `reach/census.py:24` is
   exactly `recs = {r[1:]: G.unchunks(r) for r in rows}`, with `unchunks` receiving `r`, as
   this wall says. **Recorded because three of the four neighbours in this section were
   wrong and a reader deserves to know which one was not.**
   first CHARACTER (the first chunk's `N:LEN:` header) and is the **dict key**; `unchunks`
   receives `r`. Passing the truncated string instead gives
   `ValueError: invalid literal for int() with base 10: ''` on **every** candidate, which reads
   as six walls and is really one wrong argument. Cost this unit a full probe cycle.
3. **`graphcmp.py:2977`** (`os.environ["DEV"] = a.dev`) and **`graphcmp.py:1820-1825`**
   (`clean_env`) — `DEV` must be set **before tinygrad is imported**.
   ⚠ **BOTH CITATIONS IN THIS WALL WERE WRONG, IN THE WALL THAT REPORTED THEM, and are
   corrected 2026-10-04 by `notes-sweep`.** This wall said `graphcmp.py:2769` and
   `graphcmp.py:1712-1717`. Verified against the file: **`:2769` is `continue` inside
   `split_debug`** (nothing to do with `DEV`), and **`:1712-1717` is a prose comment about
   the `dsexpand`/`disarm` plants**, not `clean_env`. By name: `os.environ["DEV"] = a.dev`
   is at **`:2977`** with `load_tinygrad()` at **`:2978`**, and `def clean_env` is at
   **`:1820`**. **The wall's substance is CORRECT and independently confirmed** —
   `HERMETIC.md` re-measured `--dev CPU` -> `sCPU` and `--dev NULL` -> `sNULL`, so the
   ordering claim holds; only the two line numbers were fiction. **Cite by NAME from here:
   `graphcmp.py` is edited by several units and its line numbers move.** A probe with
   `from tinygrad import ...` at module scope gets `sMETAL` on every ALLOC while believing it
   asked for CPU. `graphcmp.load_tinygrad()` exists to make the import order load-bearing.
4. **`tinygrad/uop/ops.py:1619`** — `PatternMatcher.rewrite` returns **`None`** on no match.
   It is not a rewrite pass; `graph_rewrite` (`tinygrad/uop/ops.py:1888`) is.
   ✅ **BOTH CITATIONS VERIFIED CORRECT 2026-10-04 by `notes-sweep`** — `:1619` is a bare
   `return None` at the end of `PatternMatcher.rewrite` and `:1888` is the `def graph_rewrite`
   signature. **The two `ops.py` citations in this section that were wrong were both
   off-by-small on lines that had moved; these two had not.** A probe that
   calls `pm.rewrite(ast)` and toposorts the result dies on `NoneType.toposort`, which looks
   like a broken graph rather than a misused API.
5. **`graphcmp.py:3082-3084` (the well-posedness precondition)** — `diff --graph late --dev NULL`
   exits **2** with `# devices py=['sNULL'] bend=['sCPU'] -- NOT WELL-POSED`, because the port's
   ⚠ **CITATION CORRECTED 2026-10-04 by `notes-sweep`: this wall said `:2869`, which is a
   `CONFLATION 1` verdict line inside `cross`, not the precondition.** Verified by name:
   `pdev, bdev = sorted(devnames(py)), sorted(devnames(bd))` and `if pdev != bdev:` are at
   **`:3082-3083`**, the message prints at **`:3084`**, and the comment block above it names
   itself "THE PRECONDITION" at **`:3077-3081`**.
   fixture is pinned at arena tag 0 = `sCPU`. **CAPTURED, IT PRODUCED 0 BYTES ON STDOUT** —
   the brief's trap reproduced exactly, and `rc=0` in a captured pipeline would have read as a
   pass. The backend dependence of section 2 is therefore measured on the EMISSION only. My
   first docstring draft claimed `diff --dev NULL` would "say so"; that was **wrong** and is
   corrected in place in both files.
6. **`tinygrad/uop/ops.py:839`** (`UOp.unique_num`, "must never be reset") — `Tensor.empty`
   ⚠ **CITATION CORRECTED 2026-10-04 by `notes-sweep`: this wall said `:842`, and `:842` is
   `def getaddr`.** The declaration is `unique_num = itertools.count(0)` at **`:839`**. The
   wall's substance is unaffected and stands.
   mints a fresh `ParamArg.slot` per call. Building BOTH new graphs in one process gives
   `cdiv` slots 0/1 and `late` slots **4/5**; in a **fresh** process each gets 0/1. `emit_bend`
   runs one graph per subprocess (`graphcmp.py:1741`), so the fresh-process value is the one
   that matters — but any census that emits every graph in one process (`both-census.py`, like
   `reach/census.py`) reads the wrong slots. Precedent and hazard: `g_binblob`,
   `graphcmp.py:915-932`.
7. **My own error, one compile cycle** — the `Bool.pick` chain in `rows.pick3` needed one
   closing paren per `Bool.pick(`: I added two rungs and added one paren, and
   `bend --check-only` said `SOME PROOFS FAIL / expected : a term (the keyword 'def' cannot
   head one)` at the line AFTER the chain — a paren-count error reported at the following
   definition, so it reads as an unrelated parse fault.
8. **A `0` on a ledger marker is a fact about the FIXTURE before it is a fact about the port.**
   `buffer` reads `z=1/1` and `binblob` reads `y=1/1` while both AGREE; a new graph reading
   `z=0/0` is not thereby better covered, it simply has no realized BUFFER and no blob.