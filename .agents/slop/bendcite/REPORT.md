# `.bend` -> `.bend` LINE CITATIONS: the measurement, and the instrument

Read 2026-10-25T16:28:54Z. The port tree was being edited by another unit while this was
taken, so the NUMBERS move; re-derive them with

    .venv/bin/python gates/bendcite-gate.py --report --rows OUT.rows

## THE GAP, AND WHAT WAS MEASURED

`gates/todo-cite-gate.py` admits only `TODO(pN)` markers and `symbol=` fields on `.py`
subjects. `gates/pin-cite-gate.py` reads the upstream **header** blocks.
`gates/header-census-gate.py` reads the port's own **header** blocks. **NOT ONE INSTRUMENT
IN THIS TREE READS A `.bend`-TO-`.bend` LINE CITATION.**

MEASURED on the tree this report was taken against:

| | |
|---|---|
| `.bend` source files under `tinybendygrad/` | **166** (3 scratch copies excluded) |
| `.bend`-to-`.bend` line citations | **1,251**, in **110** files |
| ... in a comment line | 1,052 |
| ... in a code line (a string literal) | 199 |
| distinct cited subjects | 111 |
| the citations that name a `fold.bend` | 78 |
| the files that cite `fold.bend` by LINE | 28 |
| the files that mention `fold.bend` at all | 52 |
| rows whose citing text names NOTHING | 233 (183 of them `UNCLAIMED`) |

## THE VERDICTS, AND WHICH OF THEM IS A FAILURE

| verdict | count | a failure? |
|---|---|---|
| `RESOLVES` | 351 | no |
| `WRONG-LINE` | **276** | **YES** |
| `WRONG-LINE-BY-BLOCK` | 107 | no -- reported, and why below |
| `DANGLING-LINE` | **23** | **YES** |
| `AMBIGUOUS` | 19 | no -- a refusal to guess |
| `UNCLAIMED` | 467 | no -- no claim to falsify |
| `OUT-OF-CORPUS` | 8 | no -- not a port file |

**299 of 1,251 internal pointers do not hold.** `gates/bendcite-gate.py` exits 1 (FAIL)
on this tree, and says so rather than hiding it.

### WHY THE CLAIM'S STRENGTH IS THE VERDICT'S NAME

A claim read off the **pointer's own line** is a claim about that pointer.
A claim read off the **enclosing comment block** is a claim about the paragraph, and a
paragraph names things the pointer is not about.

MEASURED, 12 sampled tier-two rows: at least 4 are pointers that are RIGHT --
`tinybendygrad/uop/render.bend:422` cites `ops.bend:1036-1090` and says "ops.bend:1036-1090
already has the `ops.ParamArg` pattern with 13 fields", and `ops.bend:1036` IS inside the
`ParamArg` arm; the block's names include `ParamArg`, whose DECLARATION is at :869, and
the pointer was called stale on it. MEASURED, 12 sampled tier-one rows: 0 were wrong.

**A FALSE FAILURE IS WORSE THAN A MISSED ROW**, so the two strengths are two verdicts and
only the strong one fails. The 107 `WRONG-LINE-BY-BLOCK` rows are printed with their
names so a reader can see how many a stronger reading would add.

### WHY ONLY A CONSTRUCT THE TARGET DECLARES CAN FALSIFY A POINTER

MEASURED: `tinybendygrad/nn/layers.bend:533` cites `mixin/op.bend:60-70` and says
"(W4) calls it 'BUILDABLE but not CHECKABLE'", and `mixin/op.bend:60-70` SAYS EXACTLY
THAT -- the pointer is RIGHT. The block's names included `Maybe`, a type
`mixin/op.bend` does not declare, and the pointer read as stale on it. A name the target
merely MENTIONS -- a local, a type from another module, an English word in a comment --
is not "the thing the pointer is about", so it is REPORTED and not verdicted.

## THE STALE ONES, BY THE FILE THAT MAKES THE CLAIM

    28  tinybendygrad/runtime/support/hcq2.bend      16  tinybendygrad/tensor.bend
    13  tinybendygrad/extra/models/clip.bend        13  tinybendygrad/uop/ops.bend
    12  tinybendygrad/extra/models/mask_rcnn.bend   12  tinybendygrad/extra/models/t5.bend
    11  tinybendygrad/extra/models/llama.bend       11  tinybendygrad/extra/models/transformer.bend
    10  tinybendygrad/extra/models/rnnt.bend        10  tinybendygrad/nn/layers.bend
     9  tinybendygrad/extra/models/bert.bend         8  tinybendygrad/schedule/prepare.bend
     8  tinybendygrad/uop/validate.bend              6  tinybendygrad/extra/models/convnext.bend
     6  tinybendygrad/extra/models/resnet.bend       6  tinybendygrad/extra/models/retinanet.bend
     6  tinybendygrad/mixin/creation.bend            5  tinybendygrad/extra/models/unet.bend
     5  tinybendygrad/nn/item.bend                   4  tinybendygrad/extra/models/vit.bend
     4  tinybendygrad/mixin/elementwise.bend         4  tinybendygrad/mixin/op.bend
     4  tinybendygrad/mixin/reduce.bend              4  tinybendygrad/renderer/tc_ptx.bend
     4  tinybendygrad/schedule/__init__.bend         4  tinybendygrad/uop/fold.bend
     3  each of: codegen/decomp/transcendental_f32.bend, helpers.bend,
                mixin/gradient.bend, nn/pool.bend, renderer/amd/dsl.bend,
                renderer/amd/generate.bend, runtime/ops_bend.bend,
                runtime/ops_python.bend, schedule/indexing.bend, schedule/multi.bend
     2  each of: base.bend, codegen/__init__.bend, codegen/decomp/dtype.bend,
                codegen/late/regalloc.bend, engine/realize.bend, mixin/movement.bend,
                schedule/memory.bend, uop/render.bend, uop/weak.bend
     1  each of: codegen/decomp/op.bend, codegen/decomp/transcendental.bend,
                codegen/kernel.bend, codegen/opt/heuristic.bend, codegen/rewriter.bend,
                dtype.bend, engine/worker.bend, examples/test_pkl_imagenet.bend,
                examples/train_resnet.bend, extra/models/efficientnet.bend,
                extra/models/inception.bend, extra/models/unet3d.bend, function.bend,
                mixin/rand.bend, nn/onnx.bend, renderer/isa/x86.bend,
                renderer/llvmir.bend, renderer/wgsl.bend,
                runtime/autogen/libclang.bend, runtime/ops_cpu.bend,
                runtime/support/c.bend, runtime/support/compiler_amd.bend,
                runtime/support/compiler_cpu.bend, runtime/support/compiler_mesa.bend,
                runtime/support/compiler_qcom.bend, runtime/support/nv/nvdev.bend,
                schedule/rangeify.bend, uop/spec.bend

## THE STALE ONES, BY THE FILE THAT IS POINTED AT

    59  tinybendygrad/uop/ops.bend                37  tinybendygrad/mixin/op.bend
    33  tinybendygrad/nn/layers.bend              26  references/bend/bend2/base.bend
    22  tinybendygrad/runtime/ops_nv.bend         19  tinybendygrad/mixin/creation.bend
    17  tinybendygrad/uop/fold.bend               12  tinybendygrad/mixin/elementwise.bend
    11  tinybendygrad/tensor.bend                 10  tinybendygrad/mixin/movement.bend
    10  tinybendygrad/mixin/rand.bend              7  tinybendygrad/device.bend
     6  tinybendygrad/helpers.bend                 3  each of: dtype.bend, mixin/dtype.bend
     2  each of: nn/state.bend, runtime/ops_python.bend, uop/spec.bend,
                uop/symbolic.bend, uop/weak.bend
     1  each of: LAWS/spec.bend, engine/jit.bend, engine/realize.bend,
                extra/models/resnet.bend, extra/models/vit.bend, mixin/gradient.bend,
                nn/pool.bend, renderer/__init__.bend, renderer/cstyle.bend,
                renderer/ptx.bend, runtime/support/system.bend, schedule/memory.bend,
                schedule/rangeify.bend, uop/render.bend

`runtime/ops_nv.bend` is 94 lines and 22 pointers name lines 181..3691 of it: the file was
replaced by a stub and every pointer into it rotted at once.

## THE KNOWN-STALE ONES THE BRIEFING NAMED, AND WHAT THE INSTRUMENT SAYS

| pointer | briefing | instrument |
|---|---|---|
| `fold.bend:999` | is blank | `WRONG-LINE` -- the claim `F.alu_ds` is declared at `fold.bend:1011`, the pointer says 999 (**-12**) |
| `fold.bend:1537` | is `pre_all` | `WRONG-LINE` -- the claim `reshape_ds` is declared at `fold.bend:2188`, the pointer says 1537 (**-651**) |
| `fold.bend:1620-1626` | is `sym_dim.end` | `UNCLAIMED` -- the citing text names nothing `fold.bend` holds in code, so there is no claim to falsify; **the construct AT the cited line is reported as `sym_dim.end`** |
| `ops.bend:823` | claims `SInt.uop`, which is at 815 | `WRONG-LINE` -- `SInt.uop` is declared at :815, the pointer says 823 (**+8**); **the construct AT the cited line is `SInt.uop_of`** |
| `ops.bend:940` | claims `AInk`, which is at 1248 | `WRONG-LINE` -- two rows cite it: `mixin/creation.bend:367` claims `Arena.next` (declared at :1361) and `uop/fold.bend:2741` claims `Arg`/`AInk` (declared at :1219 / :1248) |
| `ops.bend:3036` | -- | `UNCLAIMED` -- the construct AT the cited line is `shape_to_shape_arg.of` |

`fold.bend:1620-1626` is the one the briefing calls stale and the instrument calls
UNCLAIMED, and the difference is honest: the paragraph names `marg`, `as_shape` and
`ssimplify`, and **`fold.bend` declares none of them** -- the port supplies those arms in
`mixin/movement.bend` instead. There is no construct for the pointer to point at, so
there is nothing to falsify; the row reports the construct that IS at the cited line,
which is the information a `symbol=` conversion needs.

## THE POPULATION, AND HOW IT IS DISCOVERED

* **THE CITING POPULATION**: `os.walk` over `tinybendygrad/` plus `endswith(".bend")`.
  `glob('*.bend')` returns `[]` when the files ARE on disk -- the trap `AGENTS.md` records.
* **THE SCRATCH RULE IS THE TREE's OWN, LOADED BY PATH**:
  `gates/header-census-gate.py`'s `is_scratch()`, loaded by `importlib` and NOT
  re-spelled. MEASURED: it excludes **3** files on this tree --
  `tinybendygrad/codegen/decomp/dtype-mut.bend`,
  `tinybendygrad/codegen/decomp/op-mut.bend` and
  `tinybendygrad/codegen/late/.linearizer-mut.bend`. A scratch copy is NOT a source
  file, and a census that counted one would report a false citation nobody could fix.
* **THE CITED CORPUS IS BIGGER**: the port's 166 files PLUS
  `references/bend/bend2/base.bend`, the Bend COMPILER's own source, which the port
  cites (`base.bend:1542` claims `U32.is_even`, and the port's `base.bend` is 56 lines
  while the compiler's is 3,191). The compiler's tree is a RESOLUTION corpus and not a
  population, and it is reported as its own stratum.

## HOW A CITED FILE IS RESOLVED

Seven basenames in the corpus are NOT unique (`spec.bend` is `LAWS/spec.bend` AND
`uop/spec.bend`; `op.bend` is `codegen/decomp/op.bend` AND `mixin/op.bend`; and
`__init__.bend`, `dtype.bend`, `movement.bend`, `elf.bend`, `ip.bend`, `memory.bend` are
also shared). The order of evidence:

1. an exact path (`tinybendygrad/uop/ops.bend`);
2. a path suffix (`uop/ops.bend`, `LAWS/spec.bend`);
3. a subject spelled relative to the citing file (`../base.bend:54`);
4. a unique basename;
5. **the only candidate that HAS the cited line** -- a pointer at line N cannot be about
   a file with fewer than N lines, and that is a fact about the file rather than a guess
   about the prose. MEASURED: `dtype.bend:658` cites `base.bend:1251` and the import rule
   picked the port's 56-line `base.bend` and reported a DANGLING line for a pointer that
   is about the compiler's; the range rule picks the right one;
6. **the citing file's OWN IMPORTS** -- the port writes `import ./../uop/ops.bend as O`,
   so the import NAMES the path a bare `ops.bend` means;
7. otherwise `AMBIGUOUS` -- a refusal to guess, counted and not failed.

## HOW A CLAIM IS READ, AND WHAT IS LOADED BY PATH

* `gates/header-census-gate.py`'s `is_scratch` -- the scratch rule.
* `gates/pin-cite-gate.py`'s `claim_tokens` -- the claim-token filters (a backticked
  span that IS a citation is the citation; the subject's own stem is not a claim).
* `gates/todo-cite-gate.py`'s `comment_blocks` -- the enclosing comment block.

**THE NEAREST-CITATION RULE IS IMPLEMENTED HERE, AND THE SHARED ONE IS NOT COPIED
BECAUSE IT IS NOT THE RULE.** `gates/pin-cite-gate.py`'s `window_tokens` says in its own
docstring "A BACKTICKED NAME BELONGS TO THE NEAREST CITATION" and implements the
opposite: it keeps a name for citation `i` when the name is within 40 characters of some
OTHER citation, so on a line with two citations the name goes to the FARTHER one.
MEASURED: `tinybendygrad/extra/models/clip.bend:105` reads
`"mixin/elementwise.bend:772 has the CONSTANT ew_k.gelu and :1217 has `def
ew_quick_gelu`"` -- and the shared rule gave `ew_quick_gelu` to `:772`, which is TRUE of
neither, and the pointer read as stale. `gates/pin-cite-gate.py` is NOT edited by this
work.

**THE DOTTED CLAIM NAME IS KEPT WHOLE.** The port writes `SInt.uop` for a
`def SInt.uop(...)`, and the components alone lose it: the component `SInt` is a word on
`def SInt.uop_of(...)`, so splitting the name made `ops.bend:823` READ AS RESOLVES when
`SInt.uop` is declared at :815 and the pointer names :823.

**THE PORT's IMPORT ALIAS IS THE FIRST COMPONENT OF THE NAME.** The port writes
`import ./../uop/ops.bend as O` and then says `O.Sint.uop`; the alias is DISCOVERED from
the citing file's own import lines and stripped, and a name whose alias points at ANOTHER
file is about that other file and is dropped.

## THE PLANT, AND ITS OUTPUT

    .venv/bin/python gates/bendcite-gate.py --plant

    PLANT arm-one control : ['RESOLVES']
    PLANT arm-one moved   : ['WRONG-LINE']
    PLANT arm-one twin    : ['RESOLVES']  byte-identical=True
    PLANT arm-two the pointer moved is tinybendygrad/nn/item.bend:152 -> mixin/op.bend:281,
      and the construct it names is declared at tinybendygrad/mixin/op.bend:281; 1 lines are
      inserted above it
    PLANT arm-two control : RESOLVES  (the pointer holds)
    PLANT arm-two moved   : WRONG-LINE
    PLANT arm-two control : {'DANGLING-LINE': 59, 'UNCLAIMED': 465, 'WRONG-LINE': 250, ...}
    PLANT arm-two moved   : {'DANGLING-LINE': 59, 'UNCLAIMED': 466, 'WRONG-LINE': 252, ...}
    PLANT arm-two twin    : reproduces the control exactly
    PLANT OK: a moved line makes the pointer stale, a byte-identical copy does not, and both
      arms agree with their controls

**ARM ONE** is a synthetic port with ONE pointer, so the verdict is decidable from
literals. **ARM TWO** is a COPY OF THE REAL PORT with a text edit that moves the line the
pointer names -- **never `git show HEAD:`** -- and the pointer the plant moves is
DISCOVERED (the first row that resolves BY A DECLARATION, on the pointer's own line).
**THE CONTROL IS A SECOND COPY OF THE SAME SNAPSHOT, NOT THE LIVE TREE**: the live tree
moves under the gate's feet, and a control taken from it would compare two different
trees.

## THE COMMITS

    0832ac87a  bendcite-gate: MEASURE the port's internal `.bend` -> `.bend` line pointers
                4 files changed, 2544 insertions: the gate, this report, the rows, the sampler
    3886f5bf1  bendcite-gate: drop the DEAD vocabulary test, the dead window_tokens,
                and the dead port_set
                1 file changed, 7 insertions, 34 deletions -- NO VERDICT MOVES

Both committed with `git commit --only -F <msgfile> -- <paths>` after `git add -- <path>`
for each NEW path (a bare `--only` refuses an untracked path on this git). `git show
--stat` and `git fsck --no-progress` were run in the SAME command as each commit;
`git fsck` names the THREE PRE-EXISTING malformed trees (`d57bc484`, `d83cf685`,
`3a60f33f`) and nothing else. No `tinybendygrad/` file was touched.

## THE CORPUS DIGEST

`checks/differ.py`'s `SUBSTRATE_INPUTS` are `checks/differ.py`, `checks/devpin.py`,
`bin/bend` and eight `.agents/slop/graphcmp*` files. **This work touches none of them**,
so the corpus digest is unchanged:

    before: bcd163e8143531d364cee703d48c379a1ed629d481094e1f47c040e4308a54d8
    after : bcd163e8143531d364cee703d48c379a1ed629d481094e1f47c040e4308a54d8

    .venv/bin/python -c "import sys; sys.path.insert(0,'checks'); import differ; \
        print(differ.substrate_digest())"

## WHAT I COULD NOT MEASURE, AND WHY

* **THE 467 `UNCLAIMED` ROWS ARE NOT MEASURED, AND THEY ARE THE BIGGEST GAP.** A pointer
  whose citing text names nothing the target holds in code makes no claim to falsify.
  MEASURED: **233** of the 1,251 rows name nothing at all -- the citing line is a bare
  `` `fold.bend:1620-1626` `` with no name beside it -- and 183 of those are
  `UNCLAIMED`. The instrument can only report the construct AT the cited line for them.
  **A POINTER THAT NAMES ITS CONSTRUCT IS THE DURABLE FORM, AND THESE ARE THE POINTERS
  THAT STILL NEED ONE.**
* **THE 107 `WRONG-LINE-BY-BLOCK` ROWS ARE NOT VERDICTED.** Their claim comes from the
  enclosing paragraph, and a paragraph names things the pointer is not about; at least 4
  of 12 sampled rows are pointers that are RIGHT.
* **A MENTION-POINTER DOES NOT BREAK WHEN THE FILE MOVES.** The instrument's
  "the cited line names the token" test is insensitive to a one-line shift, so a pointer
  of the shape "the fold mentions `x` here" survives a move that a pointer of the shape
  "the construct is at line N" does not. The plant measures the second shape.
* **THE 199 CITATIONS IN CODE (a string literal) ARE COUNTED AND READ.** They are real
  citations -- `D.refuse("... (tensor.bend:680) EXISTS ...")`. They are in the
  population, and their claims are read by the same rules.
* **THE 27 CITATIONS ON A LINE WITH AN UNBALANCED BACKTICK ARE READ AT TIER TWO ONLY.**
  Their own line's spans are misaligned (a span opens on the previous line and closes
  here), so the tight reading is skipped and the enclosing block is read instead.
* **THE COMPILER'S `references/bend/bend2/base.bend` IS A RESOLUTION CORPUS AND NOT A
  POPULATION.** Its 26 stale pointers are counted, and they rot when the Bend compiler is
  updated -- a different cause from the port's own rot.
* **`.agents/TODO.md` AND `.agents/TOOLS.md` WERE NOT TOUCHED.** Both are shared,
  high-traffic files another unit may be holding, and the brief for this work was to
  commit only its own files. The TODO entry for this work is THIS file.

## WHAT A LATER UNIT CAN DO WITH IT

Every failing row names the construct the pointer claims AND the line that construct is
declared at, and every row -- failing or not -- names the construct AT the cited line.
**CONVERTING A POINTER TO A `symbol=` IS A MECHANICAL EDIT**, and `gates/todo-cite-gate.py`
already owns the patch machinery for the `TODO(pN)` population; this gate supplies the
same information for the pointers that carry no marker.
