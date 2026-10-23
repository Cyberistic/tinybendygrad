# THE CLASS -- CITATIONS NO INSTRUMENT READS, AND WHAT WAS DONE ABOUT IT

Unit: citeclass. Date: 2026-10-23. Tree at: `a5a7d38fa` (the tree MOVED twice under
this unit -- `5dc19a5cf` removed the scratch-file population and `a5a7d38fa` fixed 50
citations in nn/mixin/schedule/codegen -- so every number below names the HEAD it was
taken at).

## 1. THE CENSUS

Two instruments, two populations:

| instrument | population | how it is discovered |
|---|---|---|
| `gates/pin-cite-gate.py` | every citation in a `.bend` file's **HEADER BLOCK** | `os.walk` + `gates/header-census-gate.py`'s parser, loaded BY PATH |
| `gates/todo-cite-gate.py` | the citations carried by a **`TODO(pN)` marker** | `os.walk` over `tinybendygrad/` |

The marker population is a SUBSET. Measured with `gates/pin-cite-gate.py --rows` and
classified by whether the citation's own source line carries a marker:

```
total citations                     2624
tagged (marker on the source line)   302
OUTSIDE the tagged population        2322
  of those, FALSE at the pin          603   <- only_older_revision 365 + at_no_revision 220
                                                 + dangling 11 + ambient_relocated 4
  of those, unverifiable             1084   <- no claim token 854 + no claim about the file 230
```

And by the gate's OWN population (`todo-cite-gate.py`'s rows): **314** measured,
**2310** not, of which **600** are false at the pin.

The densest files by false count among the citations the todo-cite gate does not
measure -- `tinybendygrad/runtime/support/hcq2.bend` 33, `mixin/movement.bend` 27,
`nn/onnx.bend` 21, `runtime/ops_webgpu.bend` 19, `mixin/op.bend` 17,
`runtime/ops_metal.bend` 16, `runtime/ops_dsp.bend` 16, `runtime/ops_rdma.bend` 16,
`renderer/llvmir.bend` 16, `runtime/ops_qcom.bend` 15, `mixin/creation.bend` 14,
`runtime/ops_amd.bend` 13, `runtime/ops_bend.bend` 13, `extra/models/llama.bend` 12,
`runtime/ops_npy.bend` 12.

**A NEGATIVE RESULT IS A RESULT:** `only_older_revision` (365) is the pin-cite gate's
own "a ROW and not a failure" class -- the port's header was pinned to the revision it
was written against -- so the 600 are the gate's VERDICTED failures, and the gate's own
FAIL class (`dangling`: holds at NO upstream revision and names one file outright) is
**11** of them, 14 of 2624 tree-wide.

## 2. WHAT WAS NOT MEASURED AT ALL

`gates/pin-cite-gate.py` reads the HEADER BLOCK. `gates/todo-cite-gate.py` reads the
lines a marker touches. **`tinybendygrad/uop/ops.bend` had fourteen stale upstream
citations in neither population** -- in the BODY, in the comment that explains a rule
and points at the upstream line it came from. Fourteen false claims in the largest file
of the port, and nothing in the tree could see them.

MEASURED by `gates/header-census-gate.py`'s own parser over the WHOLE file
(`.agents/slop/citeclass/probe.py`): 533 citations, 435 upstream, of which 39 hold at no
upstream revision, 1 is dangling and 1 is ambient-relocated. The 14 named in the brief
were the SYMBOL-level failures; the token-level census finds 41 hard ones.

## 3. THE FIX -- `tinybendygrad/uop/ops.bend`, 17 re-points

Every line is COMMENT-ONLY and the file's LINE COUNT IS UNCHANGED (9806 -> 9806):
**156** citations in other files name a line of `ops.bend`, so the file's line numbers
are an interface.

| line | before | after | symbol= |
|---|---|---|---|
| 805 | `ops.py:1925` | `ops.py:1923` | `sint` |
| 2341 | `ops.py:196-212` | `ops.py:193` | `UOpMetaClass.__call__` |
| 4245 | `ops.py:1896, 1897, 1904, 1907` | `ops.py:1898` / `ops.py:1899` / `ops.py:1908` / `tinygrad/uop/spec.py:207` | `_substitute` / `_pm_resolve_params` / `pm_drop_after` / `spec_program` |
| 4257 | `ops.py:1602-1606` | `ops.py:1591-1593` | `PatternMatcher.__init__` |
| 4265 | `ops.py:1614` | `ops.py:1601` | `PatternMatcher.rewrite` |
| 4269 | `ops.py:1480-1483` | `ops.py:1469-1470` | `UPat.__init__` |
| 4272 | `ops.py:1617` | `ops.py:1604` | `PatternMatcher.rewrite` |
| 4277 | `ops.py:1896` | `ops.py:1898` | `_substitute` |
| 4278 | `ops.py:1904` | `tinygrad/uop/spec.py:207` | `spec_program` |
| 4280 | `tinygrad/uop/__init__.py:135` | `tinygrad/uop/__init__.py:134` | `GroupOp.All` |
| 4297 | `ops.py:1904` | `tinygrad/uop/spec.py:207` | `spec_program` |
| 4308 | `ops.py:1907` | `ops.py:1908` | `pm_drop_after` |
| 4319 | `ops.py:1897` | `ops.py:1899` | `_pm_resolve_params` |
| 4395 | `ops.py:1888` | `ops.py:1600` and `ops.py:1698` | `PatternMatcher.rewrite` / `TrackedPatternMatcher.rewrite` |
| 4405 | `ops.py:253-257` | `ops.py:245-249` | `UOp.replace` |
| 4418 | `ops.py:1904` | `tinygrad/uop/spec.py:207` | `spec_program` |
| 4422 | `ops.py:253-257` | `ops.py:245-249` | `UOp.replace` |
| 4440 | `ops.py:1904` | `tinygrad/uop/spec.py:207` | `spec_program` |
| 4451 | `ops.py:1896` | `ops.py:1898` | `_substitute` |
| 4454 | `ops.py:530` | `ops.py:514` | `UOp.substitute` |
| 4944 | `ops.py:1893` | `ops.py:1895` | `sint_to_uop` |
| 4955 | `ops.py:1901` | `ops.py:1915` | `gate_kernel_sink` |
| 5436 | `ops.py:530` | `ops.py:514` | `UOp.substitute` |
| 8187 | `ops.py:1899` | `ops.py:1901` | `resolve_returned_after` |
| 8561 | `ops.py:1828-1835` | `ops.py:1826-1837` | `RewriteContext.unified_rewrite` |

`remove_all_tags` IS NOT IN upstream's `ops.py` AT ALL -- `git grep remove_all_tags
5c2bf39d6c4b -- tinygrad/` returns nothing -- so the port's rule is named as the port's
own and the SURVIVING upstream construct is cited: `tinygrad/uop/spec.py:207`,
`UPat(GroupOp.All-{Ops.CONST}, dtypes.weaks)`.

**TWO OF THE BRIEF'S NUMBERS ARE WRONG AT THE PIN, AND THE MEASUREMENT WINS.**
`ops.py:1888` is `if init_ctx is not None:`, and the `ctx=None` signature is
`PatternMatcher.rewrite` at 1600 and `TrackedPatternMatcher.rewrite` at 1698 -- as the
brief says. But `unified_rewrite` is at **1814**, not 1780: 1780 is the COMMENT
`# no cache needed: pm_rewrite is called at most once per UOp due to the replace dict
check in unified_rewrite`. The fixpoint the port cites is 1826-1837 (`test_n: UOp|None`
is at 1826, the cited 1828-1835 held the loop but not the annotation). The
`tinygrad/uop/__init__.py:135` citation was ALSO stale -- that file has 134 lines and
`GroupOp.All` is at 134 -- and the gate caught it.

## 4. THE POPULATION CHANGE -- `gates/todo-cite-gate.py`

**THE GATE IS A SHARED INSTRUMENT AND ITS POPULATION IS CHANGED.** A citation that
carries an explicit `symbol=` field is now in the population, with or without a
`TODO(pN)` marker. The binding is per line and nearest-preceding: the `symbol=` that
FOLLOWS a citation and PRECEDES the next citation is that citation's symbol; a citation
with no `symbol=` after it is NOT measured. A line with a marker is read ONCE, by the
marker path, exactly as before.

**NO CHECK IS WEAKENED.** The change ADDS rows; every added row is judged by the same
`judge()` at the same verified pin. `fix_citation()` learned the markerless shape too,
so a row the gate can name a fix for is a row the gate can fix.

```
BEFORE (the same tree, the PRE-EDIT ops.bend): 754 rows -- 721 RESOLVES, 0 WRONG-*, 0 UNRESOLVABLE
AFTER  (the same tree, the re-pointed ops.bend): 783 rows -- 750 RESOLVES, 0 WRONG-*, 0 UNRESOLVABLE
                                              = 754 marker rows + 29 symbol-field rows
```

All 29 added rows are RESOLVES: 17 `symbol-decl` and 12 `symbol-body`.

## 5. THE PLANT

`.agents/slop/citeclass/plant.py` -- a TEXT EDIT on a COPY (never `git show HEAD:`), a
byte-identical control, and the LIVE tree for the record.

```
CONTROL : a frozen copy of the tree -> 783 rows (rc=0)
PLANT   : ops.bend:805   ops.py:1923 symbol=sint        -> ops.py:1924 symbol=sint
PLANT   : ops.bend:4944  ops.py:1895 symbol=sint_to_uop  -> ops.py:1896 symbol=sint_to_uop
PLANT   : the planted copy -> rc=1
   NEW  ('uop/ops.bend', '4944', 'ops.py', '1896', 'WRONG-LINE', 'sint_to_uop')
   NEW  ('uop/ops.bend', '805', 'ops.py', '1924', 'WRONG-SYMBOL', 'sint')
LIVE    : the live tree -> 783 rows (rc=0); 0 rows differ from the frozen base
PLANT OK: the byte-identical control is unchanged (783 rows, rc=0), the planted copy is
RED (rc=1) and says so on 2 row(s): ['WRONG-LINE', 'WRONG-SYMBOL']
```

The gate's OWN `--plant` still passes all three arms and its control.

**THE PLANT MEASURED A WEAKNESS, AND IT IS NOT FIXED HERE.** A `PatternMatcher([...])`
TABLE's span runs to the next top-level statement and the lines between are BLANK, so a
citation moved INTO that span still HOLDS: `ops.py:1908 symbol=pm_drop_after` moved to
`:1909` still RESOLVES (`how=symbol-body`). The plant therefore targets `def`
citations, whose span is tight when the body is one line. **A CITATION OF A TABLE MUST
NAME ITS DECLARATION LINE** -- which is what every re-point here does.

**AND `enclosing()` IS BROKEN, PRE-EXISTING.** MEASURED:
`enclosing(lines, 1924)` returns `('gate_kernel_sink', 1915, 1915, 1926)` -- the LAST
slot is `len(lines)`, because the stack's `_last` is never updated, so the
`for other in stack: if other[0] == name: return other` branch always returns the stack
element instead of the computed end. Every `enclosing()` call therefore reports a span
that runs to the END OF THE FILE. It only reaches the `symbol-vs-snippet` and
`no-symbol` FALLBACK arms (the `symbol-decl` arm is checked first and is exact), so it
mislabels a reason rather than changing a verdict -- but it is why the planted 805 row
says WRONG-SYMBOL instead of WRONG-LINE.

## 6. THE COMPILE

`.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend tinybendygrad/uop/ops.bend`
-- one bend process at a time:

```
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=371 MB (ceiling 2048)  1s
```

THE VERDICT TOKEN IS `WITHIN-LIMITS`, not the exit code.

## 7. WHAT WAS NOT FIXED, AND WHY

- **`ops.bend`'s remaining citation debt.** The token-level census of the whole file
  finds 41 hard failures that are NOT the 14 named in the brief (see
  `ops-probe-BEFORE.out`). They are in OTHER units' territory or in blocks this unit
  did not rewrite, and fixing them is a second, larger job. The file's citation health
  is NOT clean; it is 14 better.
- **`enclosing()`'s span bug** (above): a fix would change existing rows' verdicts in
  files other units hold.
- **The 603 false citations outside the tagged population**: the census names them and
  ranks the files; fixing them is a per-file job for the units that own those files.
- **`tinybendygrad/codegen/late/.linearizer-mut.bend`** and the other `*-mut.bend`
  scratch copies were in the todo-cite population until `5dc19a5cf` (another unit)
  removed them with `is_scratch()`. Not this unit's change.
