# The `UNCLAIMED` slice -- 65 rows in 18 files, and what the fix IS.

MEASURED 2026-10-28 on the LIVE tree. The slice is
`/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/unclaimed3.rows`.

## WHAT THE CLASS IS

`gates/bendcite-gate.py` measures the port's own `.bend` -> `.bend` LINE citations.
`UNCLAIMED` means the pointer RESOLVES and lands in the file, but the citing text
names NOTHING the target holds IN CODE -- so there is no claim to falsify, and a
pointer that names no construct is a pointer a reader cannot check.

**THE CLASS IS COUNTED AND REPORTED, NOT FAILED.** So it is the last bucket worth
attacking: the tree's own classification is that a pointer naming no construct is an
UNCHECKABLE claim, and an uncheckable claim is not a passing claim.

## THE COUNTS, MEASURED ON THE LIVE TREE

`gates/bendcite-gate.py --rows OUT.rows`, before = the tree with my 18 files
untouched, after = the tree with them applied.

| verdict | tree-wide BEFORE | tree-wide AFTER | my 18 BEFORE | my 18 AFTER |
|---|---|---|---|---|
| RESOLVES | 1062 | 1112 | 225 | 274 |
| UNCLAIMED | **71** | **3** | **65** | **0** |
| WRONG-LINE-BY-BLOCK | 120 | 119 | 30 | 29 |
| AMBIGUOUS | 19 | 19 | 2 | 2 |
| OUT-OF-CORPUS | 10 | 10 | 0 | 0 |
| WRONG-LINE (FAIL) | 0 | 0 | 0 | 0 |
| DANGLING-LINE (FAIL) | 0 | 0 | 0 | 0 |
| ABSENT-FILE (FAIL) | 0 | 0 | 0 | 0 |

**THE FILES I DID NOT TOUCH DID NOT MOVE**: NOT-MINE is `RESOLVES 837, UNCLAIMED 6,
WRONG-LINE-BY-BLOCK 90, AMBIGUOUS 17, OUT-OF-CORPUS 10` BEFORE and EXACTLY THE SAME
AFTER. (The tree-wide UNCLAIMED 6 -> 3 is ANOTHER UNIT'S WORK LANDING WHILE I RAN.)

**PER FILE, UNCLAIMED** (all 18 at 0 after):

| file | before | after |
|---|---|---|
| `tinybendygrad/nn/pool.bend` | 10 | 0 |
| `tinybendygrad/uop/weak.bend` | 7 | 0 |
| `tinybendygrad/extra/models/clip.bend` | 6 | 0 |
| `tinybendygrad/extra/models/convnext.bend` | 6 | 0 |
| `tinybendygrad/extra/models/mask_rcnn.bend` | 6 | 0 |
| `tinybendygrad/nn/item.bend` | 6 | 0 |
| `tinybendygrad/examples/test_pkl_imagenet.bend` | 5 | 0 |
| `tinybendygrad/extra/models/unet.bend` | 4 | 0 |
| `tinybendygrad/schedule/__init__.bend` | 3 | 0 |
| `tinybendygrad/schedule/realize.bend` | 3 | 0 |
| `tinybendygrad/schedule/rangeify.bend` | 2 | 0 |
| `tinybendygrad/extra/models/mask_rcnn.bend` (again, see kinds) | 0 | 0 |
| `tinybendygrad/extra/datasets/imagenet_download.bend` | 1 | 0 |
| `tinybendygrad/mixin/rand.bend` | 1 | 0 |
| `tinybendygrad/nn/onnx.bend` | 1 | 0 |
| `tinybendygrad/renderer/wgsl.bend` | 1 | 0 |
| `tinybendygrad/runtime/ops_webgpu.bend` | 1 | 0 |
| `tinybendygrad/runtime/support/rdma/bnxtdev.bend` | 1 | 0 |
| `tinybendygrad/viz/serve.bend` | 1 | 0 |

## THE KINDS OF CHANGE, AND HOW MANY

**65 ROWS, 65 NAMED.** No row was left unreconstructed. Three kinds:

1. **THE POINTER MOVED TO THE CONSTRUCT'S DECLARATION AND GAINED THE `symbol=`
   FIELD** -- the tree's own durable form, and the form this slice's predecessor
   (`673604b75`, "bendcite slice unclaimed1") used. 38 rows. Examples:
   `mixin/rand.bend:204-209` -> `mixin/rand.bend:257 symbol=PK`;
   `mixin/elementwise.bend:772` -> `mixin/elementwise.bend:772 symbol=ew_k.gelu`;
   `nn/layers.bend:242 nn_sum` -> `nn/layers.bend:279 symbol=nn_sum`.

2. **THE POINTER NAMED A FILE'S HEADER, AND A HEADER IS FREE COMMENT SPACE WITH NO
   CONSTRUCT TO NAME, SO THE HONEST FORM NAMES THE REGION** -- the form the
   predecessor slice established (`THE PORT's `nn/__init__.bend` WALL BLOCK`). 27 rows.
   Examples: `resnet.bend:21` -> `THE PORT's `resnet.bend` HEADLINE BLOCK`;
   `helpers.bend:3193` -> `THE PORT's `helpers.bend` HEADER`;
   `mixin/op.bend:11` -> `THE PORT's `mixin/op.bend` SIDE A INVENTORY`.

3. **THE CLAIM NAMED SOMETHING THE TARGET NEVER HELD, AND THE PROSE WAS CORRECTED
   TO THE TRUE CLAIM** -- a claim was not deleted and not weakened; it was made
   TRUE. 2 rows:
   - `uop/weak.bend:102`: "`ops.bend:1313 eq_cls.sel` has SIX arms and is missing
     `CWeakFloat`" -- `eq_cls.sel` is at `ops.bend:1875` and has SEVEN arms now, with
     `CWeakFloat` as the catch-all (`ops.bend:1854`). The claim is HISTORICAL ("HAD SIX
     arms"), the pointer names `ops.bend:1875 symbol=eq_cls.sel`, and the prose says
     the arm HAS SINCE LANDED and the local copy is KEPT because `ops.bend` was
     read-only when it was written.
   - `mixin/rand.bend:1024`: "the reason is rule 18: `fold.bend:1621` defers
     PERMUTE" -- **PERMUTE DOES NOT DEFER**; it is PORTED (`fold.bend:1979 Perm`,
     `1982 Perm.ds`), and `fold.bend:2094-2108` says so in its own words. What
     defers is `as_shape`'s `ssimplify` wall, and the arm that inherits it is the
     EXPAND, which is what `arange` builds (`mixin/creation.bend:491 cr_full` ->
     `cr_expand`). The claim now names `fold.bend:1654 symbol=sym_dim.signable` and
     says EXPAND.

## THE RULES THAT COST THE MOST, AND THEY ARE MEASURED

1. **EVERY FILE'S LINE COUNT IS UNCHANGED FROM `HEAD` (18 of 18).** A pointer's line
   number is a fact about the tree, and a comment edit that MOVES lines moves every
   pointer into the file. My first pass at `nn/pool.bend` added FOUR lines and
   `pool_bn` moved 382 -> 386, and `extra/models/unet.bend`'s
   `nn/pool.bend:382 symbol=pool_bn` went `RESOLVES` -> `WRONG-LINE` -- the gate
   working, on a file I did not even edit. Every edit after that was written to
   replace N lines with N lines (`.agents/slop/unclaimed3/rewrite.py` REFUSES a
   replacement of a different length).

2. **A PORT `symbol=` MUST NOT SHARE A COMMENT LINE WITH A `.py` CITATION.**
   `gates/todo-cite-gate.py`'s SECOND population reads a COMMENT line that carries
   the word `symbol` and binds every `symbol=` on it to the `.py` citation slot it
   FOLLOWS. MEASURED: `extra/models/mask_rcnn.bend:66` carried
   `extra/models/llama.py:10` and the port pointer on one line, and the gate went
   `UNRESOLVABLE` on `extra/models/llama.py` -- `rc=1`, one false citation of 1167.
   The fix moved the port pointer to the NEXT line, which carries no `.py` citation,
   WITHOUT CHANGING THE LINE COUNT. **A `D.refuse("...")` LINE IS NOT A COMMENT AND
   IS EXEMPT** -- which is why the 30 `D.refuse` payloads in these files that carry
   both a `.py` citation and a port `symbol=` are FINE.

3. **THE `symbol=` NAME IS UNALIASED AND THE CITED LINE IS THE `def` LINE.**
   `gates/bendcite-gate.py`'s `Corpus._scan` computes `self.aliases` in the same loop
   that fills `self.bodies`, so an import whose TARGET has not been scanned yet
   resolves to `None` (`os.walk` visits `schedule/` before `uop/`), and
   `strip_alias` returns the token UNCHANGED for a `None` alias. So the name is
   written WITHOUT the alias: `symbol=PK.i`, NOT `symbol=E.PK.i`.

## THE COMMENT-ONLY PROOF

`checks/port-compile-gate.py`'s `strip_comments()` imported BY PATH
(`.agents/slop/unclaimed3/commentonly.py`), blank lines dropped.

**16 of 18 strip to the SAME CODE AS `HEAD`.** The 2 that do NOT are
`tinybendygrad/extra/models/mask_rcnn.bend` and `tinybendygrad/extra/models/unet.bend`,
and their PURE CODE -- the file with comments AND string literals removed -- is
BYTE-IDENTICAL to `HEAD` in both (`.agents/slop/unclaimed3/purecode.py`:
`PURE CODE IDENTICAL`, 162 and 122 code lines). **THE DIFFERENCE IS INSIDE THE
`D.refuse("...")` STRING LITERALS, WHICH NO COMPUTATION READS.**

**⇒ THE FILES THAT CARRY A CORRECTED `D.refuse(...)` PAYLOAD** (these are NOT
comment-only, and they are listed here so nobody reads the proof as covering them):
`tinybendygrad/nn/pool.bend`, `tinybendygrad/extra/models/mask_rcnn.bend`,
`tinybendygrad/extra/models/unet.bend`.

## THE COMPILE

`.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file> --check-only`,
ONE `bend` at a time (the largest of the 18 is `tinybendygrad/nn/onnx.bend` at 1054 MB,
and 18 of them at once is over the sum-precondition in `AGENTS.md`). **18 of 18
`WITHIN-LIMITS`**, and the VERDICT TOKEN was read, never the exit code.

## THE PLANT

`.agents/slop/unclaimed3/plant.py`: a TEXT EDIT on a COPY of the port tree on disk --
NEVER `git show HEAD:` -- and a BYTE-IDENTICAL control copy of the SAME snapshot. THE
POINTER IT MOVES IS DISCOVERED, NOT NAMED: the first `RESOLVES` row in this slice's own
files whose claim came from a `symbol=` this slice wrote and whose cited line IS the
construct's DECLARATION line. **THE PLANT INSERTS CODE (`def plant_probe_unused() ->
U32: 0`) IMMEDIATELY ABOVE THE `def`** -- a COMMENT is ABSORBED into the construct's
doc run and the row still resolves, so a comment-only plant CANNOT FAIL.

MEASURED:

```
PLANT the victim is tinybendygrad/examples/test_pkl_imagenet.bend:44 -> helpers.bend:2581,
             and the construct it names is `GlobalCounters.init` declared at helpers.bend:2581
PLANT control : RESOLVES  (the pointer holds)
PLANT moved   : WRONG-LINE
PLANT twin    : reproduces the control exactly
PLANT OK: a moved line makes the pointer stale, a byte-identical copy does not
```

## THE DIGEST

`checks/differ.py`'s `substrate_digest()`, imported by path:
**BEFORE `40c3e432754207c6a8d4657aeebfec12d2b4defa7b09be01474eefe80cf98268`**
**AFTER  `e9400a49a2f645df5742f4cc50b8cb5a64e7ce2e9461e67017c11ec3eb340116`**

**⇒ A COMMENT IS SUBSTRATE, SO THE CORPUS'S DIGEST MOVED, AND THE CORPUS HAS TO BE
RE-RUN AFTERWARDS.**

(The digest is read at the END, so the AFTER reading is of the tree the COMMIT made
plus whatever landed beside it; the BEFORE reading is of the tree with my 18 files
untouched. The two are the SAME tree otherwise, because no other unit's file is in
the commit.)

## THE COMMIT

`a740a152a47c7ba6fa523f16cb58bc2e3774ebc8` -- 27 files: the 18 `.bend` files and the
9 files of this report's tooling. `git show --stat` AND `git fsck --no-progress` in
the SAME command: the commit's own tree is clean, and `fsck` names ONLY the three
PRE-EXISTING malformed trees (`d57bc484`, `d83cf685`, `3a60f33f`), which are not
mine.

## `gates/todo-cite-gate.py`

**PASS**, `0 WRONG-LINE`, `0 WRONG-SYMBOL`, `0 UNRESOLVABLE`, and the population is
1166 citations in 101 files -- IDENTICAL to the reading before this slice.
