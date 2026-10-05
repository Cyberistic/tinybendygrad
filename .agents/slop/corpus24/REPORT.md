# corpus24 — the 24 ops outside the corpus UNION, classified

**Figure reproduced first, from the one authority.** `checks/corpus-figure.py` prints
`22 graphs / 22 built / 0 failed · denominator 77 · UNION 53 of 77 · per-graph SUM 157 ·
NOT reached (24)`. Identical to `CORPUS.md`. **No new figure is added here.**

Instruments, both re-runnable, both in this directory:
`env -u PYTHONPATH .venv/bin/python .agents/slop/corpus24/{mints,prior-census}.py`

---

## THE COUNTS, AGAINST 24

| class | n |
|---|---|
| **CORPUS GAP** | **21** |
| **NOT PORTABLE** | **1** |
| **PORT GAP** | **0** |

**CORPUS GAP dominates, and not narrowly: 21 of 24.** But the 21 are not one condition, and
the split inside them is the finding — see §THE 21 ARE THREE DIFFERENT PROBLEMS.

---

## PER OP

`enum` = the `Ops.<NAME>` member in `tinygrad/uop/__init__.py`. `mint` = the `def UOp.<…>`
in `tinygrad/uop/ops.py` that builds it, where one exists; ALU ops and pattern IR have no
per-op method and are minted by `UOp.alu` / `_get_clause` respectively.

| op | verdict | upstream `file:line` | evidence |
|---|---|---|---|
| **REWRITE_ERROR** | **NOT PORTABLE** | `uop/__init__.py:25`; payload built at `uop/ops.py:1722` and `viz/serve.py:197` | Its **entire payload is a Python traceback string** (`traceback.format_exc()`, `f"{type(e).__name__}\n{sys.exc_info()[1]}"`), and both production sites are viz/debug. Measured: the port has **0 construction sites** against 15 table/match/colour lines — it has the recognizer (`spec.bend:2270`, `:2307`) and no producer, because a Bend pattern match that does not apply returns `Nothing` and there is no traceback to carry. |
| PROGRAM | CORPUS GAP | `uop/__init__.py:31`; built `codegen/__init__.py:468-471` (`pm_to_program`) | port constructs it 13× (`codegen/kernel.bend:1017-1024`), `to_program` PORTED IN SHAPE (`kernel.bend:82`) |
| SOURCE | CORPUS GAP | `uop/__init__.py:31`; built `codegen/__init__.py:455`, `:459` | port constructs it (`engine/realize.bend:1632`, `uop/spec.bend:2788`) |
| GETADDR | CORPUS GAP | `uop/ops.py:841` `def getaddr` | port has `def UOp.getaddr` (`uop/ops.bend:7241`) and 3 construction sites; the port does model HCQ |
| WMMA | CORPUS GAP | `uop/ops.py:649` `def wmma` | port has `def UOp.wmma` (`ops.bend:6873`), 1 construction site, `tc_ptx.bend` arms |
| NEG | CORPUS GAP † | `uop/__init__.py:58` | reached by the `late` graph in the prior census; port mints via `UOp.alu` (`ops.bend:2519`) |
| CDIV | CORPUS GAP † | `uop/__init__.py:61` | reached by `cdiv`; 76 port references incl. `codegen/decomp/op.bend` rule table |
| CMOD | CORPUS GAP † | `uop/__init__.py:61` | reached by `cdiv`; `uop/ops.bend` fold arm |
| CMPEQ | CORPUS GAP † | `uop/__init__.py:62` | reached by `late`; 58 port references |
| SUB | CORPUS GAP † | `uop/__init__.py:64` | reached by `late`; constructed `uop/fold.bend:5399` |
| FDIV | CORPUS GAP † | `uop/__init__.py:64` | reached by `late`; 47 port references |
| MULACC | CORPUS GAP ‡ | `uop/__init__.py:68` | port has the rules (`codegen/decomp/op.bend:818-824`, `dc_alu3`) but they sit behind upstream's `op.py:118 if Ops.MULACC in ops:`, and `renderer/ptx.py:33` is the only backend that lists it |
| THREEFRY | CORPUS GAP | `uop/__init__.py:64` | port carries one of the deepest bodies of the 24 — a full `threefry2x32` (`dc_tf_*`, `TFP`/`TFK`) at `codegen/decomp/op.bend:1205-1213` |
| CUSTOM | CORPUS GAP ‡ | `uop/__init__.py:80`; built `uop/upat.py:25-26` | port's own pattern compiler builds it — `C{OpsCUSTOM{}, LText{…}, …}` (`uop/upat.bend:383`, `:425`, `:703`) |
| CUSTOMI | CORPUS GAP ‡ | `uop/__init__.py:80`; built `uop/upat.py:25` | port builds it at `schedule/memory.bend:1515`, `upat.bend:448` |
| PYLITERAL | CORPUS GAP ‡ | `uop/__init__.py:102` (doc comment `:101`); built `uop/upat.py:25-43` | port gives it a **finite typed payload**: upstream's is `frozenset(self.op)` / `self.op[0]` / `self.arg` / `frozenset(self.match_dtype)` (`upat.py:25,26,29,36,39,43`), and the port's `Lit` datatype (`upat.bend:106`, `LOps`/`LDt`/`LTag`) holds exactly those |
| INS | CORPUS GAP | `uop/ops.py:622` `def ins` | port has `def UOp.ins.of` (`ops.bend:6865`) + `codegen/kernel.bend:1019`. **`ops.bend:4658`'s `# TODO(p3) ops.py:622 def ins` is STALE** — see §A STALE MARKER IN THE PORT |
| STAGE | CORPUS GAP | `uop/ops.py:676` `def bufferize` | port has `def UOp.bufferize` (`ops.bend:4292`), 11 construction sites |
| COPY | CORPUS GAP † | `uop/ops.py:758` `def copy_to_device` | reached by `allred`; port has `def UOp.copy_to_device` (`ops.bend:7184`), 4 construction sites |
| MSELECT | CORPUS GAP | `uop/ops.py:769` `def mselect` (bare `int`) | port has `def UOp.mselect` (`ops.bend:4319`), 5 construction sites |
| MSTACK | CORPUS GAP | `uop/ops.py:770` `def mstack` | port has `def UOp.mstack` (`ops.bend:2558`), 11 sites |
| CUSTOM_FUNCTION | CORPUS GAP | `uop/ops.py:1258` | port has `def UOp.custom_function` (`ops.bend:4943`), 7 sites |
| UNSHARD | CORPUS GAP | `uop/ops.py:689` `def unshard` | port builds it 7× (`schedule/multi.bend:2316-2320`, `engine/jit.bend:1244`). **`ops.bend:4718`'s `# TODO(p3) ops.py:689 def unshard` is ACCURATE about the method and MISLEADING about the op** |
| ALLREDUCE | CORPUS GAP † | `uop/ops.py:677` `def allreduce` | reached by `allred`; port has `def UOp.allreduce` (`ops.bend:4305`) + 21 references |

† = **corpus regression** (§ below). ‡ = blocked by the **differ**, not the port.

### `IT DEPENDS`, said as the condition

- **MULACC** — CORPUS GAP **iff** the graph runs on a backend whose `code_for_op` lists it.
  Upstream's rule is gated at `codegen/decomp/op.py:118` (`if Ops.MULACC in ops:`) and
  `renderer/ptx.py:33` is the **only** registrant, so on CPU the rule does not fire and a
  `mulacc` graph emits **zero** `MULACC`. The condition is *a graph on an NVIDIA-class
  renderer*, not a different graph.
- **CUSTOM / CUSTOMI / PYLITERAL** — CORPUS GAP **iff** `cshape` can render a shapeless
  `AND`. Upstream `ops.py:444` **asserts** (`AssertionError`, "None input shape not
  supported") while `graphcmp.py:749` catches only `RuntimeError`, and
  `issubclass(AssertionError, RuntimeError)` is `False` (measured). `upat.py:66` makes
  every pattern-compiler IR `AND`-rooted, so that one arm gates all three at once.

---

## THE 21 ARE THREE DIFFERENT PROBLEMS, AND ONLY ONE IS LAZINESS

**† 8 of the 24 are a CORPUS REGRESSION, not a wall.** `prior-census.py` reads the recorded
census in `.agents/slop/denom/rows-*.txt`, which is a **25**-graph corpus. Three of those
graphs are no longer in `graphcmp.GRAPHS`: **`allred`, `cdiv`, `late`.** They carried exactly
`NEG CMOD SUB FDIV` (late), `CDIV CMPEQ` (cdiv), `COPY ALLREDUCE` (allred) — **8 ops, and
`61 − 53 = 8` exactly.** A recorded run says these eight were reached, so they are provably
portable *and* emittable through the differ. **They are missing because three graphs were
dropped, not because anything is unimplemented.** This is the `bw` failure mode recurring in
a new costume: a corpus number that moved and a numerator nobody re-measured.

**‡ 4 of the 24 are blocked by the INSTRUMENT.** `CUSTOM CUSTOMI PYLITERAL MULACC` — two
`AssertionError`/`RuntimeError` mismatches and one backend gate, listed above. The port has
every one of them.

**9 of the 24 are simply unexercised.** `REWRITE_ERROR`(→NOT PORTABLE), `PROGRAM SOURCE
GETADDR WMMA THREEFRY INS STAGE MSELECT MSTACK CUSTOM_FUNCTION UNSHARD` — the port builds
each one and no graph asks.

---

## §A STALE MARKER IN THE PORT, AND §B A STALE CITATION SET IN THE PRIOR UNIT

**A. `tinygrad/uop/uop/ops.bend`'s not-ported inventory has aged.** `ops.bend:4658`
(`TODO(p3) ops.py:622 def ins`) and `:4669` (`TODO(p3) ops.py:649 def wmma`) are both
**stale**: `ops.bend:6865` and `:6873` implement exactly those two, documented against the
same `ops.py:622` / `ops.py:649` lines. A third method really is missing — `ops.bend:4718`,
`def unshard` — but the op is still built at `multi.bend:2316`. **So "the port has a
`TODO(p3)` for it" is not a PORT GAP oracle, and my own first test believed it and got two
wrong.** The correct oracle is the construction-site census (`mints.py`), which required
distinguishing a construction from a membership table: `schedule/prepare.bend:369` names all
77 ops on one line and constructs none of them.

**B. Five of `DENOMINATOR.md` §2's ten `file:line` citations are stale by 2-3 lines.**
Measured against `ops.py`: `getaddr` **841** not 844, `wmma` **649** not 651, `unshard`
**689** not 701, `copy_to_device` **758** not 765, `allreduce` **677** not 679. Its blocker
citations (§3, `ops.py:444`, `op.py:118`, `ptx.py:33`) all check out. Its `emittable.py` is
**gone** — `.agents/slop/denom/` now holds only `census.py` — so its `73 of 77` and its
`NEITHER` list are not reproducible and are not used here.

---

## SHOULD THE FIGURE BE RESTATED?

**Yes — not in value, in kind.** `53 of 77` is arithmetically correct and it is not a
statement about the port. Of the 24 it does not reach, the port **constructs 23**, and a
recorded corpus run **reached 8 of them** before three graphs were dropped. A reader who
takes `53 of 77` as "the port implements 53 ops" is wrong in the direction that matters.

The restatement, in the `CORPUS.md` figure block's own idiom:

> **`53 of 77` is a CORPUS figure, not a PORT figure.** The port constructs 23 of the 24 it
> misses (`mints.py`); `REWRITE_ERROR` is the one it cannot, because its payload is a Python
> traceback string. **8 of the 24 were reached by the 25-graph corpus recorded in
> `.agents/slop/denom/rows-*.txt` and are lost with the three graphs `allred`, `cdiv` and
> `late`, which are no longer in `GRAPHS`** — a regression of exactly `61 − 53 = 8`.

**Restoring the three dropped graphs is the highest-value single move**, and it is a corpus
edit, not a port edit. It is not this unit's job, and nothing here has been committed.

---

## WHAT I DID NOT DO

Did not add a graph (the evidence points at three **missing** ones, and adding a fourth to
prove `WMMA` is constructible would be the change-detector test `AGENTS.md` forbids). Did not
fix `ops.bend:4658`/`:4669`/`:4718` — a real hygiene bug, but `uop/**` is not this unit's
tree. Did not restore `emittable.py`. Did not touch `CORPUS.md`, and did not write a tenth
figure anywhere.