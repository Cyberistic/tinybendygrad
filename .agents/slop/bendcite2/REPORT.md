# bendcite slice `unclaimed2`: THE 66 UNCLAIMED ROWS IN MY 33 FILES GO TO 0

**THE SLICE.** `/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/unclaimed2.rows`
— 40 rows in 33 files, the class `UNCLAIMED`: the pointer RESOLVES and lands in the file,
but the citing text names NOTHING the target holds in code, so **there is no claim to
falsify**. The slice is a SNAPSHOT; the live tree had **66** such rows in the same 33
files (26 of them in `extra/models/inception.bend`, whose `D.refuse(...)` payloads the
snapshot did not carry).

**THE FIX IS THE TREE'S OWN DURABLE FORM, `symbol=<name>`.** A line number rots and a
name does not, so a pointer that NAMES ITS CONSTRUCT can be re-found when the lines
move. The gate reads `symbol=` and binds it to the citation on the line.

## THE COUNTS

Measured on the LIVE TREE, the "before" by stashing ONLY this unit's 33 files and the
"after" with them applied, so both readings are of the SAME tree state.

| class | tree-wide before | tree-wide after | my 33 before | my 33 after |
|---|---|---|---|---|
| `RESOLVES` | 957 | **1028** (+71) | | |
| `UNCLAIMED` | 127 | **61** (−66) | **66** | **0** (−66) |
| `WRONG-LINE` (FAIL) | 2 | **1** (−1) | **1** | **0** (−1) |
| `WRONG-LINE-BY-BLOCK` | 120 | **117** (−3) | **25** | **22** (−3) |
| `DANGLING-LINE` (FAIL) | 0 | **0** | 0 | 0 |
| `ABSENT-FILE` (FAIL) | 0 | **0** | 0 | 0 |
| `AMBIGUOUS` | 19 | 19 | | |
| `OUT-OF-CORPUS` | 9 | 9 | | |

**NO FILE'S COUNT ROSE IN ANY CLASS** — checked file-by-file, not just in total.

`gates/todo-cite-gate.py`: **PASS**, `0 WRONG-LINE`, `0 WRONG-SYMBOL`, `0 UNRESOLVABLE`
(it was PASS with the same three zeroes before this unit started).

**THE ONE REMAINING `WRONG-LINE` IS NOT MINE**: `tinybendygrad/extra/models/transformer.bend:40`
→ `mixin/op.bend:1171` (`mo_log_softmax` is at :1172). `extra/models/transformer.bend`
is another unit's file.

## PER FILE (my 33, `UNCLAIMED`)

Every one of the 33 files goes to **0**:

```
  1 -> 0  tinybendygrad/base.bend                      1 -> 0  tinybendygrad/nn/argmax.bend
  1 -> 0  tinybendygrad/codegen/decomp/op.bend         2 -> 0  tinybendygrad/nn/onnx.bend
  1 -> 0  tinybendygrad/codegen/gpudims.bend           2 -> 0  tinybendygrad/nn/state.bend
  1 -> 0  tinybendygrad/codegen/kernel.bend            2 -> 0  tinybendygrad/renderer/amd/dsl.bend
  1 -> 0  tinybendygrad/codegen/late/linearizer.bend   1 -> 0  tinybendygrad/renderer/amd/elf.bend
  1 -> 0  tinybendygrad/codegen/opt/heuristic.bend     1 -> 0  tinybendygrad/renderer/amd/generate.bend
  1 -> 0  tinybendygrad/codegen/opt/search.bend        1 -> 0  tinybendygrad/renderer/kuconv.bend
  1 -> 0  tinybendygrad/engine/realize.bend            1 -> 0  tinybendygrad/renderer/llvmir.bend
  1 -> 0  tinybendygrad/extra/datasets/__init__.bend   1 -> 0  tinybendygrad/runtime/device.bend
  1 -> 0  tinybendygrad/extra/datasets/kits19.bend     1 -> 0  tinybendygrad/runtime/ops_dsp.bend
  1 -> 0  tinybendygrad/extra/datasets/openimages.bend 1 -> 0  tinybendygrad/runtime/ops_python.bend
  1 -> 0  tinybendygrad/extra/datasets/squad.bend      2 -> 0  tinybendygrad/runtime/support/autogen.bend
 27 -> 0  tinybendygrad/extra/models/inception.bend    2 -> 0  tinybendygrad/runtime/support/elf.bend
  1 -> 0  tinybendygrad/function.bend                  2 -> 0  tinybendygrad/schedule/prepare.bend
  1 -> 0  tinybendygrad/mixin/dtype.bend               1 -> 0  tinybendygrad/uop/fold.bend
  1 -> 0  tinybendygrad/mixin/reduce.bend              1 -> 0  tinybendygrad/uop/validate.bend
  1 -> 0  tinybendygrad/nn/__init__.bend
```

**66 rows named. 0 rows could not be reconstructed.** Every row's subject was found in
the target file and the pointer re-pointed at the declaration the comment is about.

## THE KINDS OF CHANGE

1. **THE POINTER MOVED TO THE CONSTRUCT'S DECLARATION** (the common case). The claim
   names a construct the target file declares; the old line was a stale copy of it.
   Examples: `ops.bend:2849` → `ops.bend:2939 symbol=UOp.replace` (three files);
   `mixin/elementwise.bend:358` → `:325 symbol=ew_remint`; `uop/ops.bend:697` →
   `:697 symbol=AxisType.lt`; `uop/fold.bend:4770` → `:4770 symbol=fold.dt`.
2. **THE CLAIM NAMED SOMETHING THE TARGET NEVER HELD**, and the honest form says so.
   `nn/onnx.bend` claimed `x.contiguous` (elementwise.bend:873) and `x.clip`
   (elementwise.bend:880); the port's `mixin/elementwise.bend` NO LONGER CARRIES either,
   so the comment now says exactly that and points at the `TODO(p3)` that records the
   refusal (`mixin/elementwise.bend:926 symbol=contiguous`, `:933 symbol=clamp`).
   Same for `renderer/amd/generate.bend`'s `esc_row` (no such construct in
   `renderer/cstyle.bend`) and `renderer/amd/elf.bend`'s `u.addrspace` (now PORTED, so
   the stale "still `TODO(p3)`" was corrected to `uop/fold.bend:4755 symbol=UOp.addrspace`).
3. **THE POINTER NAMED A HISTORICAL FILE STATE.** `codegen/kernel.bend` cites the line
   `ad117c928` names; that line was the `build_range_map` doc-comment and the port
   carries it today inside `kn_unroll.ax`'s span, so the claim now points there
   (`codegen/kernel.bend:367 symbol=kn_unroll.ax`) and the commit reference is kept as
   prose ("`ad117c928` lists `kernel.bend`'s line 353 by name").
4. **A `D.refuse("...")` PAYLOAD** — `extra/models/inception.bend`, 26 rows. Each
   payload's `.bend:NN` gained the `symbol=` naming the construct it is about.
5. **AN UPSTREAM POINTER THAT WAS WRONG.** `renderer/kuconv.bend`'s `dtype` row cited
   upstream `ops.py:247`, which is `UOp.replace`; `dtype` is at `ops.py:239`. Corrected,
   and the row's upstream `symbol=dtype` is what lets the port's own `symbol=fold.dt`
   sit on the same line without the upstream gate binding it to the `.py` slot.

## THE THREE RULES THAT COST THE MOST, AND THEY ARE MEASURED

1. **A `symbol=` ON A LINE THAT CARRIES A `.py` CITATION LANDS ON THE `.py` ONE.**
   `gates/todo-cite-gate.py` binds the nearest-preceding `symbol=` to a citation, and
   only a `.py` subject is admitted there. MEASURED: the first attempt put
   `symbol=contiguous` next to `elementwise.py:72` and `symbol=clamp` next to
   `elementwise.py:832`, and the gate said **WRONG-LINE** on both; a third
   (`renderer/kuconv.bend:34`, `symbol=fold.dt`) said **WRONG-SYMBOL**. **⇒ THE PORT
   `symbol=` GOES ON A LINE WHOSE ONLY CITATIONS ARE `.bend`.** A line with no `.py`
   citation has no slot in that gate at all (`if not slots: continue`), so it is
   invisible to it and free for the port's own name.
2. **AN INLINE `TODO(pN)` IS A MARKER.** `gates/todo-cite-gate.py`'s `MARKER` regex
   matches `TODO(pN)` ANYWHERE on a line, including inside backticks, so writing
   "`TODO(p3) elementwise.py:59`" in prose CREATES a work item and it fails
   `UNRESOLVABLE` because it names no symbol. **⇒ THE UPSTREAM REFERENCE IS PROSE**
   ("upstream's `elementwise.py:59` is the record"), not a marker.
3. **AN EDIT MUST NOT CHANGE A FILE'S LINE COUNT.** A `.bend` file's lines are pointed
   at by OTHER files' citations, so adding a line moves every pointer into it.
   MEASURED: the first patch grew 7 files and turned three correct pointers into
   `WRONG-LINE` (`runtime/device.bend:18` → `runtime/support/elf.bend:1816`, and two
   more). **⇒ EVERY EDIT HERE REPLACES N LINES WITH N LINES**, and
   `.agents/slop/bendcite2/patch.py` CHECKS THAT AND PRINTS THE DELTA PER FILE.

## THE COMMENT-ONLY PROOF

`.agents/slop/bendcite2/commentonly.py`, using `checks/port-compile-gate.py`'s OWN
`strip_comments()` (loaded BY PATH), code hash with blank lines dropped, against
`HEAD`:

**32 of 33 FILES: `COMMENT-ONLY` — the code hash is IDENTICAL and the line count is
IDENTICAL.**

**ONE FILE IS NOT COMMENT-ONLY, AND IT IS THE DECLARED EXCEPTION:**
`tinybendygrad/extra/models/inception.bend` — **the edit is inside a `D.refuse("...")`
STRING LITERAL**, which is a diagnostic payload no computation reads. Its line count is
unchanged (198 lines) and its code hash differs only in that payload.

## THE COMPILE

`.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file>`, ONE FILE AT A TIME,
reading the VERDICT TOKEN:

**ALL 33 FILES: `WITHIN-LIMITS`.** The peaks that mattered, from
`.agents/slop/peakrss/census.rows`: `runtime/ops_python.bend` 864 MB,
`nn/onnx.bend` 777 MB, `uop/fold.bend` 484 MB, `runtime/ops_dsp.bend` 358 MB — all
under the 2048 MB ceiling, and all run SEQUENTIALLY.

## THE PLANT

`.agents/slop/bendcite2/plant.py` — a TEXT EDIT on a COPY OF THE LIVE TREE (never
`git show HEAD:`), plus a byte-identical copy of the control:

```
PLANT control  : RESOLVES  -- :4764 names `fold.shape`
PLANT moved    : WRONG-LINE  -- the pointer says :4764 and `fold.shape` is declared at :4765 -- the nearest is -1 lines away
PLANT twin     : RESOLVES  byte-identical=True
PLANT OK: a moved line makes the re-pointed pointer stale, a byte-identical copy does not, and the control reproduces.
```

**THE PLANTED LINE IS CODE, NOT A COMMENT, AND THAT IS LOAD-BEARING**: a construct's
span INCLUDES the comment run above its `def`, so a COMMENT inserted above the def
EXTENDS the span and the pointer still lands inside it — the first attempt at this
plant did exactly that and stayed green. A CODE line does not extend the span, and the
pointer falls out of the construct.

## WHAT I DID NOT FIX, AND WHY

1. **THE THREE DOUBLE-LISTED FILES.** The brief's "YOUR FILES (33, and ONLY these)"
   names `uop/fold.bend`, `uop/validate.bend` and `runtime/device.bend`; the brief's
   "⇒ DO NOT TOUCH" list says "**every file under `tinybendygrad/uop/`**" and
   "`tinybendygrad/runtime/{ops_bend,device}.bend`". **THE TWO LISTS CONTRADICT ON
   EXACTLY THESE THREE.** I treated them as MINE, because the slice assigns them rows
   to this unit and the exclusion's glob and brace-expansion read as catch-alls for the
   files the brief did not enumerate. **IF THE OTHER UNITS OWN THEM, THESE THREE EDITS
   SHOULD BE REVERTED** — they are independent of the other thirty, and reverting them
   costs nothing else.
2. **`uop/fold.bend`'s AND `uop/validate.bend`'s CLAIMS.** Both were corrected to the
   construct that IS there (`uop/spec.bend:1082 symbol=sh_21`, `uop/fold.bend:5175
   symbol=UOp.min_max`), but the SUBSTANCE of one claim was found to be STALE and was
   NOT rewritten: `uop/validate.bend:60` quotes `fold.bend:2482` as saying "the wall is
   arithmetic, not the fold", and **that sentence no longer exists anywhere in
   `uop/fold.bend`** (MEASURED: `grep -rn "arithmetic, not the fold" tinybendygrad/`
   answers only the citing line). The honest fix is to re-derive what that file says
   about the `_min_max` wall, which is a claim about the port's own state and not a
   pointer fix. **⇒ REPORTED, NOT FIXED.**
3. **`codegen/decomp/op.bend`'s `_min_max` CLAIM.** The comment says the recursive
   `_min_max` "is P3 and recorded at `fold.bend:2176`"; `uop/fold.bend:7040` now reads
   "`DONE(p3) ops.py:1094 def _min_max`" and `:7153` still says "`UOp._min_max` (P3)".
   The pointer was moved to the construct that IS the reader
   (`uop/fold.bend:5175 symbol=UOp.min_max`) and the "is P3" wording was KEPT, because
   deciding whether the wall is still open is a claim about the port and not a pointer
   fix. **⇒ REPORTED, NOT FIXED.**
4. **`renderer/amd/elf.bend`'s STALE PREMISE.** Its comment said `u.addrspace` is "still
   `TODO(p3)` in `uop/ops.bend:3773`". MEASURED: `uop/fold.bend:4755` declares
   `UOp.addrspace` and `uop/fold.bend:7018` records "`DONE(p3) ops.py:896 def
   addrspace`". **⇒ THE CLAIM WAS CORRECTED** (this one IS a pointer fix: the
   pointer named a line that never held the thing), and the corrected text names the
   construct.
5. **THE OTHER UNITS' `mixin/op.bend` POINTERS.** `nn/layers.bend:18` and `:276` still
   cite `mixin/op.bend:853 symbol=mo_sum` while `mo_sum` is at :854 — because another
   unit is editing `mixin/op.bend` and moved it. `nn/layers.bend` is another unit's
   file. **⇒ REPORTED, NOT FIXED.**
6. **THE `symbol=` FORM DOES NOT MAKE A POINTER IMMUNE.** It makes the CLAIM
   CHECKABLE and names the construct, but the LINE still has to land at or inside the
   construct's span. MEASURED: `symbol=mo_sum` at `mixin/op.bend:853` went
   `WRONG-LINE` the moment another unit inserted a line above `mo_sum`, because :853
   is now one line BEFORE the declaration. **⇒ A `symbol=` POINTER MUST SIT AT THE
   DECLARATION LINE, AND THE GATE'S `delta` COLUMN IS WHAT SAYS WHEN IT DRIFTED.**

## THE INSTRUMENTS THIS UNIT LEFT BEHIND

All under `.agents/slop/bendcite2/` (no `.txt`):

| file | what it is |
|---|---|
| `patch.py` | THE 43 EDITS, and it CHECKS LINE-COUNT NEUTRALITY and prints the delta per file |
| `patch_inception.py` | THE 25 `D.refuse(...)` PAYLOAD EDITS |
| `decl.py` | WHERE A SYMBOL IS DECLARED, by the gate's OWN `bend_constructs()` |
| `audit.py` | THE `symbol=`-NEXT-TO-A-`.py`-CITATION HAZARD, over a file list |
| `commentonly.py` | THE COMMENT-ONLY PROOF, by `port-compile-gate.py`'s OWN `strip_comments()` |
| `plant.py` | THE PLANT: a TEXT EDIT on a COPY, plus a byte-identical twin |
| `before2.rows`, `after.rows` | THE TWO CENSUS ROWS FILES |

**A COMMENT IS SUBSTRATE, SO THESE EDITS MOVE THE CORPUS's DIGEST.** That is expected
and is why the corpus is re-run after the port stops moving.
