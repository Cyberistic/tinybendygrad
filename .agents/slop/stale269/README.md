# stale269 — 326 broken `file:line` citations, adjudicated one at a time

**NOTHING HERE IS COMMITTED.** The 182 restored numbers are in the working copy of 58 `.bend` files
and are comment lines only.

    .venv/bin/python checks/citation-gate.py                       # the census
    CITEGATE_ROWS=100000 .venv/bin/python checks/citation-gate.py  # every row, not 60
    .venv/bin/python .agents/slop/stale269/plants.py               # 3 arms, tree never modified

## 1. THE HEADLINE, AND IT IS NOT THE NUMBER THE BRIEF GAVE

**326 is the census's count. 182 of them were broken. 144 were not, and the instrument cannot tell
you which is which from its own output.**

| action | n | what it is |
|---|---:|---|
| `RESTORE-LINE` | 140 | the line moved. retyped to the line that says the thing. |
| `RESTORE` (other classes) | 42 | the FILE or the class was wrong. retyped the file **and** the number. |
| `NOT-BROKEN` (range) | 35 | a **range** citation `dtype.py:236-241` whose text sits inside the range. The gate adjudicates only the range START. |
| `NOT-BROKEN/MIS-PIN` | 25 | the gate pinned **the wrong backtick span on the citation's own line**. |
| `NAMED-NOT-BROKEN` | 17 | same, hand-confirmed with a pasted line. |
| **`FENCED`** | **57** | `ops.bend` (37), `fold.bend` (17), `helpers.bend` (3). **named, not edited.** |
| **`DECLINED`** | **10** | restoring would require **inventing** something. |
| **total** | **326** | |

### 2. THREE FALSE-POSITIVE MODES, ALL MEASURED, AND **THE THIRD IS NEW**

1. **RANGE.** `CITE` matches `name.py:A-B` and adjudicates only `A`. 78 rows are range citations;
   **36 of them carry the text inside the range.** `dtype.py:236-241` quoting `_fp8_cfg` at 237 is
   not broken.
2. **MIS-PIN — the `Allocator` class.** The gate takes **the longest backtick span on the citation's
   line**. A citation line often carries several spans and is about one of them:

       # `_render_fn` -- llvmir.py:156-160, the AMD barrier rule, and `_render_footer`.

   `_render_footer` is longer than `_render_fn`, so the gate compared `_render_footer` against
   `llvmir.py:156` — which **is** `def _render_fn` — and called it `STALE-LINE`, 53 lines off.
   **THE CITATION IS EXACTLY RIGHT.** 26 rows are multi-span; **25 are mis-pinned.**
3. **THE PREFIX CLASS, and it is the one that produced a wrong number in MY OWN restore path.**
   `UOp.device` occurs in `tinygrad/uop/ops.py` as `UOp.device_range_src(device)` on 1199 **and** as
   the property `def device(self)` on 890. A boundary-less pin accepted the first; `engine/jit.bend:1214`
   cites **890**, which is correct. `audit.py` flagged it as `PREFIX`, I read it, and the restore was
   **withdrawn**. That is `abi4_gate.py`'s `S.Dt`/`S.DtX` trap, live, and the audit caught it.

## 3. THE RESTORE WAS NOT "PUT THE CURRENT NUMBER BACK"

**A LINE NUMBER IS ONLY DEFINED RELATIVE TO A BLOB.** So the anchor is the blob the comment was
written against: `git log -L<line>:<port>` names the commits that wrote the port line, and the cited
`.py` at any of them is a file the author demonstrably had.

    blob.py, decide the historical line, then find its CURRENT address by WHOLE-LINE TEXT.

The whole-line text, not the token, is the key — and **168 of 172 whole-line matches were EXACT
(score 1.000)**, which is the strongest evidence available for "the line moved and this is where it
went". **NEAREST-OCCURRENCE IS NOT USED ANYWHERE IN THE RESTORE PATH**, because it is the pin that
read `Allocator` inside `BumpAllocator`.

**177 of the 269 `STALE-LINE` were `MISNUMBERED` — the number was WRONG WHEN IT WAS WRITTEN.** The
brief's story ("the line moved") is right for 92 and wrong for two thirds of the population. A tool
that reports "the line moved" for all 269 describes a defect that does not exist in 177 of them.

## 4. `git diff -U0`: **0 CODE LINES**

    58 files, 181 changed line pairs, 0 non-comment lines.

Measured by diffing each touched file against a pre-write snapshot and rejecting any changed line
that is not `#`-prefixed or blank. **TWO WRITER BUGS WERE CAUGHT BY THIS CHECK AND FIXED IN THE
WRITER, NOT EXPLAINED AWAY:**

* **trailing newlines.** Five files ended without one and the writer appended `\n` — a byte nobody
  asked it to change, which showed up as a diff on a *code* line. The condition was **inverted**.
* **the wrong-file writes.** The first pass retyped only the NUMBER, leaving 12 rows naming the right
  line in the wrong file. **That is the worst outcome available, because it looks done.** The writer
  now retypes the file token too.

## 5. THE WRITER REFUSED 26 OF ITS OWN ROWS

`write.py` re-verifies every target against the **current bytes** before writing and refuses rather
than writing: the target does not exist, the target line does not carry the claim's span, the port
line is not a comment, or **the claim line names more than one citation**. The last one is the class
that produced `(reduce.py:44/:71)` → `(reduce.py:71/:71)` — a list that now reads as checked and says
nothing. 16 multi-citation rows were adjudicated by hand (11 are `cstyle.py` class-attribute lists
whose base-class block moved by a constant **−3**).

## 6. THE TEN DECLINED — RESTORING WOULD HAVE MEANT INVENTING

| row | why |
|---|---|
| `mixin/rand.bend:603` `dtypes.is_int(dtype)` | **NEVER**: in no `tinygrad/mixin/*.py`; the only hit is `dtype.py:176`. Which file is meant is an author's decision. |
| `runtime/ops_cuda.bend:232` `HWQueue.q` | **PREFIX**: not defined anywhere. The only hit is `HWQueue.q_rewrite`. Naming that line would make a false citation true by retyping. |
| `runtime/ops_python.bend:300` `offset is None` | **FALSE**: `ops_python.py:19` tests `i`, not `offset`. The quote and the citation disagree about the variable. |
| `uop/spec.bend:173` `x.shape == ()` | **STALE-RULE, not a retype**: `spec.py` writes it nowhere at HEAD. The rule moved out or was deleted. |
| `uop/symbolic.bend:385` `UOp.const(b, dtype)` | **FALSE**: upstream spells it `def const(b:ConstLike, dtype:DType\|None=None)`. |
| `engine/realize.bend:216` `call.body` | **FALSE**: `tinygrad/uop/ops.py` has no `def body`. Every hit is a READ of it. |
| `renderer/isa/x86.bend:1584` `name index size` | **PROSE**: three field names, not source text. The number (19 vs 17) is readable off the pasted line; a retype would be indistinguishable from a guess. |
| `runtime/ops_bend.bend:1356` `has_local = False` | **WEAK**: in no `opt/heuristic.py` — that file only READS `k.ren.has_local`. The quote is a DECLARATION in six renderer files. |
| `uop/validate.bend:2594`/`:2607` `ops-501-oracle.py` | **FALSE + DELETED**: the file exists nowhere and `git log --all -S` finds it on **no ref**. It is a PRUNED ORACLE under `.agents/slop/` — recreating it means recreating an oracle. |

### `NO-FILE` RESOLVED TO "NEVER EXISTED" — PROVEN ACROSS **ALL** REFS

`git log --all -S'<quote>' -- '*<name>'` (all refs, unanchored pathspec, not one commit and not one
path — the `canon.py` lesson) returned **NOTHING, ON ANY REF** for: `MTLResourceStorageModeShared := 0`,
`PCIIfaceBase.peer_group`, `name index size`, `repr(Register)`, `f"dtypes.{...}"`, `dtypes.{name}`,
`DType.const`, `bool: [weakint]`, `lowest(0) = U32.log2(0) = 0`, `eq_addr(Aalu, AReg)`,
`ConstFloat.__hash__`, `ops-501-oracle.py`, `(support/hcq2.py:63) --`, `dtype.py:140-142`.
**16 of the 26 `NO-FILE` are a RESOLVER LIMIT, not absence:** `dtype.py` is ambiguous (3 files),
`isa/__init__.py` and `support/hcq2.py` resolve only through the MIRROR which `resolve()` skips for a
name containing `/`, and `PYROOTS` has no `tinygrad/runtime/...` or `test/`. **In 12 of them the
cited NUMBER WAS ALREADY RIGHT.**

## 7. THE TWO PLANTS — `.agents/slop/stale269/plants.py`, 3/3, tree never modified

| arm | shows |
|---|---|
| `CONTROL` | the live bytes, 23 adjudicable rows |
| **`PLANT-A`** | the census calls `device.py:390` **HOLDS, 0 off, 1 in the file** — for a claim about the `PatternMatcher([` RULE TABLE that `4c5ec4602` moved to `runtime/support/hcq2.py:547`. **Every pin available says the citation holds and the claim is about a different line.** |
| **`PLANT-B`** | `(reduce.py:44/:71)` → `(reduce.py:71/:71)`: the list-collapse a restore causes, planted because `write.py`'s guard for it had never fired before. |

`PLANT-A` is `PLANT-2` from `.agents/slop/speccite/README.md` §3 one class up: **the evidence is
invariant under the edit that broke it**, and "the substring occurs exactly once" is not evidence
that the once is the right once.

## 8. THE CENSUS, BEFORE AND AFTER

| class | before | after |
|---|---:|---:|
| `HOLDS` | 424 | **593** |
| `STALE-LINE` | 269 | **109** |
| `WRONG-FILE` | 27 | **20** |
| `NO-FILE` | 26 | **23** |
| `PAST-EOF` | 4 | **3** |
| `STALE-RULE` | **5** | **5** (untouched) |
| `PROSE` | 557 | 560 |
| adjudicable | 1,312 | 1,313 |

**187 of the 326 rows left the broken classes. 0 regressions in the 58 files I touched** (checked by
row-set difference, not by count). 16 apparent new breaks are in `fold.bend`/`ops.bend`/`weak.bend`
at **different line numbers than before** — other units are editing those files live.

## 9. WHAT I DID NOT SETTLE

1. **The 57 `FENCED` are not restored.** `ops.bend` 37, `fold.bend` 17, `helpers.bend` 3. Their
   verdicts are computed and in `FINAL.tsv`; the numbers are not written.
2. **`ops.py:1610` vs `:1618` vs `:1724`** — three lines carry `ret is not uop` and two of them are
   different METHODS (`PatternMatcher.rewrite` vs the tracking variant). Resolved to 1618 by reading
   the claim; a different reader could pick 1724.
3. **`schedule/memory.bend:240`** — the claim quotes `prod(to_max_shape(shape))` (which is at 1200
   and 1247) and names `to_max_shape` (at 1894). I restored to the DEF because the claim says
   "`to_max_shape` (ops.py:1886)"; the USE is arguably the better target. Named.
4. **THE SIBLING NUMBERS.** 30-odd claims name several lines (`cstyle.py:125, :285, :324`, `:82`
   beside `:74`). One writer pass changes one number, so every stale sibling is **named in
   `resolutions.tsv` and left**, which means those claims still carry wrong numbers and the census
   still sees them.
5. **`checks/citation-gate.py` HAS ONE LINE CHANGED BY ME** — `shown = int(os.environ.get("CITEGATE_ROWS", "60"))`,
   so the census can print every row instead of 60. Proved behaviour-identical (`CITEGATE_ROWS=0`
   reproduces the default counts exactly). **The three false-positive modes are NOT fixed in the
   instrument**: they are described here and detected by `readjudicate.py` / `spans.py`. Fixing the
   gate would move 60 rows out of its own findings, which is a decision about the gate and not mine.