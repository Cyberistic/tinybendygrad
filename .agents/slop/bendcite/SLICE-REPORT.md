# THE `bendcite` SLICE -- 58 `WRONG-LINE` ROWS IN 17 FILES, FIXED

THE SLICE IS `/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/wl.rows`
(58 rows, 17 files). THE INSTRUMENT IS `gates/bendcite-gate.py`, WHICH READS THE PORT'S OWN
`.bend` -> `.bend` LINE CITATIONS AND JUDGES EACH ONE AGAINST THE CONSTRUCT THE TARGET
FILE DECLARES.

## THE COUNTS

| | before | after |
|---|---|---|
| **MY 17 FILES** | **58** | **0** |
| TREE-WIDE | 61 | 1 |
| FILES I DID NOT TOUCH | 3 | 1 |

PER FILE, `WRONG-LINE` ONLY (there were **0** `DANGLING-LINE` and **0** `ABSENT-FILE`
in the slice, and there are **0** after):

| file | before | after |
|---|---|---|
| `tinybendygrad/base.bend` | 2 | 0 |
| `tinybendygrad/codegen/kernel.bend` | 1 | 0 |
| `tinybendygrad/engine/realize.bend` | 2 | 0 |
| `tinybendygrad/extra/models/bert.bend` | 7 | 0 |
| `tinybendygrad/extra/models/inception.bend` | 5 | 0 |
| `tinybendygrad/extra/models/rnnt.bend` | 4 | 0 |
| `tinybendygrad/extra/models/t5.bend` | 5 | 0 |
| `tinybendygrad/extra/models/vit.bend` | 2 | 0 |
| `tinybendygrad/mixin/gradient.bend` | 3 | 0 |
| `tinybendygrad/mixin/rand.bend` | 1 | 0 |
| `tinybendygrad/nn/layers.bend` | 9 | 0 |
| `tinybendygrad/nn/mnist_cnn.bend` | 1 | 0 |
| `tinybendygrad/renderer/kuconv.bend` | 6 | 0 |
| `tinybendygrad/renderer/wgsl.bend` | 1 | 0 |
| `tinybendygrad/runtime/support/nv/nvdev.bend` | 2 | 0 |
| `tinybendygrad/schedule/prepare.bend` | 1 | 0 |
| `tinybendygrad/uop/validate.bend` | 6 | 0 |

## THE KINDS OF CHANGE

**1. `symbol=` CONVERSION (the DURABLE form).** THE ROW ALREADY NAMED THE CONSTRUCT AND
THE CITATION ALREADY CARRIED A `symbol=`; THE LINE NUMBER HAD ROT. THE FIX IS THE
CURRENT DECLARATION LINE, AND THE `symbol=` STAYS. 30 ROWS.

**2. `symbol=` ADDED WHERE THERE WAS NONE.** THE CITATION NAMED A CONSTRUCT IN PROSE
(`\`mxw_stk\``, `\`Arena.empty\``, `\`UOp.is_none\``, `\`UOp.axis_id\``) AND THE LINE
HAD MOVED. THE FIX NAMES IT. 12 ROWS.

**3. A CITATION SPLIT INTO TWO, ONE PER CONSTRUCT.** `engine/realize.bend:1583` NAMED
`beam_rewrite` AND `bm_new` IN ONE POINTER; `codegen/kernel.bend:408` NAMED
`UOp.axis_id` AND `UOp.axis_type` IN ONE RANGE. A RANGE THAT SPANS TWO DECLARATIONS
CANNOT HOLD EITHER, SO EACH GETS ITS OWN POINTER. 4 ROWS.

**4. THE CITED LINE RE-POINTED AT A DIFFERENT CONSTRUCT.** THE COMMENT WAS ABOUT
SOMETHING ELSE AND NAMED IT: `renderer/kuconv.bend`'s TABLE NAMED THE *READER*, SO THE
READER'S DECLARATION IS NOW THE POINTER. `uop/validate.bend`'s ROWS NAMED THE ARENA'S
NODE 2 AND NODE 4, WHICH ARE `uop/ops.bend:7288` AND `:7290`. 12 ROWS.

**5. ABSENCE STATED.** NONE. EVERY CONSTRUCT THE COMMENTS NAMED STILL EXISTS; NO CLAIM
HAD TO BE WEAKENED.

**6. `D.refuse("...")` DIAGNOSTIC STRING CORRECTED.** **THE EXCEPTION CLAUSE.** 34 STALE
`.bend:NN` ADDRESSES IN 5 FILES. **SEE THE SECTION BELOW.**

## THE `D.refuse("...")` EXCEPTION -- THE FILES THAT ARE **NOT** COMMENT-ONLY

**THE 5 MODEL FILES CARRY 34 STALE ADDRESSES IN THEIR `D.refuse("...")` PAYLOADS.** A
`D.refuse` STRING IS A PAYLOAD NO COMPUTATION READS, AND A STALE ADDRESS IN IT IS A
FALSE CLAIM, SO THE TASK'S EXCEPTION APPLIES. **THESE 5 FILES ARE COUNTED AS NOT
COMMENT-ONLY** -- BUT SEE THE MEASUREMENT BELOW, WHICH IS STRONGER.

THE ADDRESSES THAT WERE WRONG, AND WHAT THEY ARE NOW:

| file | was | is | construct |
|---|---|---|---|
| `bert.bend` | `nn/layers.bend:427` | `:530` | `nn_linear` |
| `bert.bend` | `nn/layers.bend:383` | `:486` | `nn_dot` |
| `bert.bend` | `helpers.bend:3193` | `:3194` | the HTTP-machinery paragraph |
| `inception.bend` | `nn/layers.bend:756` | `:937` | `nn_conv2d` |
| `inception.bend` | `nn/pool.bend:250` | `:251` | `pool_maxpool` |
| `inception.bend` | `nn/pool.bend:252` | `:253` | `pool_maxpool_padded` |
| `inception.bend` | `nn/pool.bend:260` | `:261` | `pool_avgpool` |
| `inception.bend` | `nn/pool.bend:262` | `:263` | `pool_avgpool_padded` |
| `inception.bend` | `nn/pool.bend:326` | `:327` | `pool_flatten` |
| `inception.bend` | `nn/pool.bend:322-324` | `:323-325` | the `-1`-inference comment |
| `inception.bend` | `pool.bend:247-248` | `:248-249` | the "not built wrong" comment |
| `inception.bend` | `nn/layers.bend:427` | `:530` | `nn_linear` |
| `inception.bend` | `mixin/op.bend:891` | `:953` | `mo_mean` |
| `inception.bend` | `mixin/op.bend:811` | `:853` | `mo_sum` |
| `rnnt.bend` | `mixin/rand.bend:836` | `:921` | `rd_uniform` |
| `rnnt.bend` | `nn/layers.bend:427` | `:530` | `nn_linear` |
| `rnnt.bend` | `helpers.bend:3193` | `:3194` | the HTTP-machinery paragraph |
| `t5.bend` | `mixin/creation.bend:487` | `:559` | `cr_ones` |
| `vit.bend` | `mixin/rand.bend:836` | `:921` | `rd_uniform` |
| `vit.bend` | `mixin/creation.bend:446` | `:518` | `cr_zeros` |
| `vit.bend` | `mixin/creation.bend:487` | `:559` | `cr_ones` |
| `vit.bend` | `mixin/elementwise.bend:1217` | `:1229` | `ew_quick_gelu` |
| `vit.bend` | `nn/layers.bend:756` | `:937` | `nn_conv2d` |
| `vit.bend` | `mixin/movement.bend:1431` | `:1434` | `mxw_reshape` |
| `vit.bend` | `mixin/movement.bend:1449` | `:1452` | `mxw_permute` |
| `vit.bend` | `tensor.bend:680` | `:685` | `tn_add` |
| `vit.bend` | `mixin/rand.bend:392` | `:477` | `rd_slice` |

**AND `vit.bend:112`'s `elementwise.bend:43` WAS LEFT ALONE: IT IS NOT STALE.** LINE 43
IS THE FLOAT-CONST WALL PARAGRAPH AND IT NAMES `erf`; THE CITATION IS A MENTION AND IT
STILL HOLDS.

### **THE MEASUREMENT THAT SUPERSEDES THE "NOT COMMENT-ONLY" LABEL**

**ALL 17 FILES PASS THE COMMENT-ONLY PROOF, INCLUDING THE 5 WITH CORRECTED
`D.refuse` PAYLOADS.** THE PROOF IS `checks/port-compile-gate.py`'s OWN
`strip_comments()` -- **LOADED BY PATH**, BECAUSE A SECOND COPY OF THE STRIPPER IS A
CONTRACT WITH NO GENERATOR -- FOLLOWED BY A SHA-256 OF THE CODE WITH THE BLANK LINES
DROPPED, COMPARED AGAINST `HEAD`:

```
COMMENT-ONLY  tinybendygrad/base.bend  live=c9dd75590c64a293 head=c9dd75590c64a293
COMMENT-ONLY  tinybendygrad/codegen/kernel.bend  live=3329bc140313e016 head=3329bc140313e016
COMMENT-ONLY  tinybendygrad/engine/realize.bend  live=380f9a548a4a0d28 head=380f9a548a4a0d28
COMMENT-ONLY  tinybendygrad/extra/models/bert.bend  live=dd7c3099b92b61a4 head=dd7c3099b92b61a4
COMMENT-ONLY  tinybendygrad/extra/models/inception.bend  live=8bed2b8d9555f3e2 head=8bed2b8d9555f3e2
COMMENT-ONLY  tinybendygrad/extra/models/rnnt.bend  live=16684a21ec011125 head=16684a21ec011125
COMMENT-ONLY  tinybendygrad/extra/models/t5.bend  live=ac01a88d49dc6e66 head=ac01a88d49dc6e66
COMMENT-ONLY  tinybendygrad/extra/models/vit.bend  live=7546696528faf1b8 head=7546696528faf1b8
COMMENT-ONLY  tinybendygrad/mixin/gradient.bend  live=e9f9d52d524309e9 head=e9f9d52d524309e9
COMMENT-ONLY  tinybendygrad/mixin/rand.bend  live=e10c16886ba697a8 head=e10c16886ba697a8
COMMENT-ONLY  tinybendygrad/nn/layers.bend  live=f3f512be821cee24 head=f3f512be821cee24
COMMENT-ONLY  tinybendygrad/nn/mnist_cnn.bend  live=e9ab111f5db5e01b head=e9ab111f5db5e01b
COMMENT-ONLY  tinybendygrad/renderer/kuconv.bend  live=5cbe464a90b01c53 head=5cbe464a90b01c53
COMMENT-ONLY  tinybendygrad/renderer/wgsl.bend  live=b95c5db1f2165c5b head=b95c5db1f2165c5b
COMMENT-ONLY  tinybendygrad/runtime/support/nv/nvdev.bend  live=1e2ead639fa56d79 head=1e2ead639fa56d79
COMMENT-ONLY  tinybendygrad/schedule/prepare.bend  live=184c75603836ef4b head=184c75603836ef4b
COMMENT-ONLY  tinybendygrad/uop/validate.bend  live=062640220c237195 head=062640220c237195
```

**WHY THE 5 MODEL FILES PASS IT: THE STRIPPER BLANKS STRING LITERALS FIRST.** A
`D.refuse("...")` LINE STRIPS TO `  D.refuse(                    )` -- THE PAYLOAD IS GONE
AND THE CODE IS IDENTICAL. **SO THE PROOF IS STRONGER THAN THE "NOT COMMENT-ONLY"
LABEL: NO COMPUTATION READS THE PAYLOAD, AND THE PROVE THAT WITH A HASH.**
**THE 5 FILES ARE LISTED HERE BECAUSE THE TASK ASKS FOR THEM TO BE, NOT BECAUSE THE
HASH SAYS THEY ARE NOT.**

## THE COMPILE TOKENS

ONE `bend` AT A TIME, UNDER `checks/bounded.py --mb 2048`, **READING THE VERDICT TOKEN
AND NOT THE EXIT CODE**. ALL 17: **`WITHIN-LIMITS`**.

```
tinybendygrad/base.bend                            WITHIN-LIMITS
tinybendygrad/codegen/kernel.bend                  WITHIN-LIMITS
tinybendygrad/engine/realize.bend                  WITHIN-LIMITS
tinybendygrad/extra/models/bert.bend               WITHIN-LIMITS
tinybendygrad/extra/models/inception.bend          WITHIN-LIMITS
tinybendygrad/extra/models/rnnt.bend               WITHIN-LIMITS
tinybendygrad/extra/models/t5.bend                 WITHIN-LIMITS
tinybendygrad/extra/models/vit.bend                WITHIN-LIMITS
tinybendygrad/mixin/gradient.bend                  WITHIN-LIMITS
tinybendygrad/mixin/rand.bend                      WITHIN-LIMITS
tinybendygrad/nn/layers.bend                       WITHIN-LIMITS
tinybendygrad/nn/mnist_cnn.bend                    WITHIN-LIMITS
tinybendygrad/renderer/kuconv.bend                 WITHIN-LIMITS
tinybendygrad/renderer/wgsl.bend                   WITHIN-LIMITS
tinybendygrad/runtime/support/nv/nvdev.bend        WITHIN-LIMITS
tinybendygrad/schedule/prepare.bend                WITHIN-LIMITS
tinybendygrad/uop/validate.bend                    WITHIN-LIMITS
```

THE PEAKS CAME FROM `.agents/slop/peakrss/census.rows`: THE BIGGEST OF THE 17 IS
`renderer/wgsl.bend` AT 627 MB AND `mixin/gradient.bend` AT 558 MB, SO NO TWO OF THEM
WERE RUN AT ONCE. ONE AT A TIME IS UNDER THE SUM-PRECEDITION BY A WIDE MARGIN.

## THE PLANT

**A TEXT EDIT ON A COPY -- NEVER `git show HEAD:`** -- THAT MOVES A CITED LINE, AND A
BYTE-IDENTICAL COPY THAT DOES NOT. THE SUBJECT IS A ROW **THIS SLICE REWROTE**:
`nn/mnist_cnn.bend`'s POINTER AT `nn/layers.bend:937` (`nn_conv2d`).

```
PLANT control   : [('layers.bend', 937, 'RESOLVES')]
PLANT moved     : [('layers.bend', 937, 'WRONG-LINE')]
PLANT twin      : [('layers.bend', 937, 'RESOLVES')]  byte-identical=True
PLANT OK: a moved line makes the pointer stale, a byte-identical copy does not.
```

**THE GATE'S OWN PLANT ALSO PASSES** (`gates/bendcite-gate.py --plant`, BOTH ARMS).

## THE ONE ROW THAT IS STILL RED, AND WHY IT IS NOT MINE

```
tinybendygrad/mixin/creation.bend:228 -> weak.bend:613  WRONG-LINE
  the pointer says :613 and `wk_cast_at` is declared at :616
```

**`mixin/creation.bend` IS NOT IN THIS SLICE** AND IS **UNMODIFIED BY ME**
(`git diff --numstat tinybendygrad/mixin/creation.bend` IS EMPTY). **THE CAUSE IS
ANOTHER UNIT'S CONCURRENT EDIT**: `uop/weak.bend` GAINED 3 LINES (THEIR OWN
`symbol=promo_dtype` WORK), WHICH MOVED `wk_cast_at` FROM :613 TO :616.

**AND IT IS MEASURED, NOT ASSERTED: STASHING THIS SLICE'S 17 FILES AND RE-RUNNING THE
GATE GIVES 59 BAD -- THE SAME 58 PLUS THIS ONE.** THE ROW IS NOT A PRODUCT OF THIS
SLICE.

## WHAT ELSE WAS FOUND, AND NOT FIXED

**`helpers.bend:3193` IS STALE IN 15 FILES, AND THIS SLICE FIXED 3 OF THEM.** THE
HTTP-MACHINERY PARAGRAPH IS AT `helpers.bend:3194`; `:3193` IS THE TAIL OF THE PREVIOUS
ONE. **THE OTHER 12 FILES THAT CITE IT ARE NOT IN THIS SLICE AND ARE NOT TOUCHED:**
`examples/test_pkl_imagenet.bend`, `examples/train_resnet.bend`,
`extra/datasets/__init__.bend`, `extra/datasets/imagenet_download.bend`,
`extra/datasets/kits19.bend`, `extra/datasets/openimages.bend`,
`extra/datasets/squad.bend`, `extra/models/clip.bend`, `extra/models/convnext.bend`,
`extra/models/efficientnet.bend`, `extra/models/resnet.bend`, `extra/models/unet3d.bend`.
**THEIR OWNING UNIT SHOULD RE-POINT THEM AT `:3194`.**

**`tinybendygrad/extra/models/llama.bend` AND `tinybendygrad/nn/datasets.bend` WERE
NOT TOUCHED**, PER THE BRIEF. `llama.bend` IS UNMODIFIED; `datasets.bend`'s 194 ADDED
LINES ARE ANOTHER UNIT'S `.npy` PATH WORK.

## THE TWO SHAPE FACTS THIS SLICE LEARNED

**1. A COMMENT-ONLY EDIT THAT ADDS A LINE MOVES EVERY LATER CITATION IN THAT FILE, AND
THE TREE CITES ACROSS FILES.** MEASURED TWICE IN THIS SLICE: `tinybendygrad/base.bend`
GAINED ONE LINE, WHICH MOVED `F32.from_bits` FROM :54 TO :55 AND BROKE
`runtime/ops_python.bend:293`'s POINTER AT `../base.bend:54` -- **A FILE THIS SLICE DOES
NOT OWN.** THE FIX WAS TO MAKE THE EDIT LINE-COUNT-NEUTRAL, WHICH IS ALSO WHY
`tinybendygrad/mixin/rand.bend` AND `tinybendygrad/base.bend` ARE NET-0 IN LINE COUNT.
**THE `symbol=` FORM IS THE REAL CURE, AND A LINE-COUNT-NEUTRAL EDIT IS THE STOPGAP.**

**2. A `symbol=` CANNOT NAME A TWO-DOT NAME.** `gates/bendcite-gate.py`'s
`SYMBOL_FIELD` ALLOWS ONE DOT, AND `gates/pin-cite-gate.py`'s `claim_tokens` DROPS A
COMPONENT SHORTER THAN 3 CHARACTERS -- SO `_render.one.go` (LAST COMPONENT `go`) CAN BE
NEITHER A `symbol=` NOR A CLAIM TOKEN. **THE CONSEQUENCE FOR `renderer/kuconv.bend`'s
`AKERNEL` -> `KASINK` ROW: THE CELL NAMES `KUArg.sink_name`, THE FUNCTION THAT
DESTRUCTURES `KASink` IN `renderer/cstyle.bend`, AND THE PROSE NAMES `_render.one.go`
AS ITS CALLER.** THE READER IS *MORE* PRECISE THAN BEFORE, NOT LESS.

## THE INSTRUMENTS THIS SLICE ADDED

UNDER `.agents/slop/bendcite/`:

| file | what it is |
|---|---|
| `probe.py` | re-judges ONE file's citations under the LIVE tree, so a candidate edit can be judged without touching it |
| `comment_only.py` | THE COMMENT-ONLY PROOF. `strip_comments()` LOADED BY PATH FROM `checks/port-compile-gate.py`, THEN A SHA-256 OF THE CODE WITH THE BLANK LINES DROPPED, COMPARED AGAINST `HEAD` |
| `plant.py` | THE PLANT: A TEXT EDIT ON A COPY THAT MOVES A CITED LINE, AND A BYTE-IDENTICAL COPY THAT DOES NOT |

**THE SEED ROWS AND THE TREES ARE THE SLICE'S OWN:** `wl.before.rows` (61 BAD),
`wl.final.rows` (1 BAD), AND THE SLICE FILE `wl.rows` (58 BAD, 17 FILES).

## THE GATES, AND THEIR VERDICTS

```
gates/bendcite-gate.py   FAIL -- 1 of 1297 internal pointers do not hold
                          (the 1 is `mixin/creation.bend`, NOT THIS SLICE'S)
gates/todo-cite-gate.py  PASS
                          1127 RESOLVES / 0 WRONG-LINE / 0 WRONG-SYMBOL / 0 UNRESOLVABLE
                          1160 citations in 99 `.bend` files: 753 by a `TODO(pN)` marker,
                          407 by an explicit `symbol=` field
```

**`todo-cite-gate.py` IS THE REASON THE `symbol=` FORM HAS ITS RULES.** IT READS A
`symbol=` FIELD ONLY ON A LINE THAT CARRIES A **`.py`** SUBJECT -- A `.bend` SUBJECT IS
THE PORT'S OWN FILE AND IS NOT AN UPSTREAM CITATION -- **AND THE BINDING IS PER LINE AND
NEAREST-PRECEDING.** SO A PORT `symbol=` ON A LINE THAT ALSO CARRIES AN UPSTREAM `.py`
CITATION IS ATTRIBUTED TO THE `.py` ONE. **THIS SLICE PUT NO PORT `symbol=` ON ANY LINE
THAT CARRIES A `.py` CITATION; WHERE A PORT `symbol=` WAS NEEDED NEXT TO A `.py`
CITATION, THE TWO WERE PUT ON SEPARATE LINES.**
