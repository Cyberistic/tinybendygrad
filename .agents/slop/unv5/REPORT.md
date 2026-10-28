# unv5 -- the `unverifiable_no_claim_about_the_file` slice, 30 rows in 11 files

**THE SLICE.** `/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/unv5.rows`
-- 30 rows, 11 files. Every row's claim tokens occur NOWHERE in the cited upstream
file, so the citation makes no claim about that file and no re-point can make it
hold. **THE FIX IS THE PROSE.**

**THE COMMIT.** `1bf99383a` -- 12 files, +86/-63. Eleven port files plus
`.agents/slop/mnist/gen_mnist_cnn.py`, the GENERATOR of one of them.

## THE MEASUREMENT, AND WHY IT IS ON ONE FROZEN TREE

The port tree is owned by other units and MOVES: the first baseline reading was
`cite.total=2618` and the last was `cite.total=2800`, with no edit of mine
between them. A before/after taken at two different moments compares two
different trees, so BOTH readings were taken on ONE COPY with `--tree`.

**THE COPY CARRIES `references/`.** `references/` is gitignored, so a
`git archive` of HEAD has no compiler: the 3,191-line
`references/bend/bend2/base.bend` is absent and every `base.bend` pointer
resolves into the port's own 56-line one. The copy was made with `rsync` from
the LIVE tree, not from HEAD, because the files this slice does not own move.

    rsync -a --exclude=.git --exclude=.venv --exclude=runs --exclude=node_modules ./ $FROZEN/

    $ wc -l $FROZEN/references/bend/bend2/base.bend
       3191 $FROZEN/references/bend/bend2/base.bend

## THE COUNTS, APPLES TO APPLES (the SAME frozen tree, the 11 files reverted vs fixed)

    .venv/bin/python gates/pin-cite-gate.py --tree $FROZEN --rows OUT.rows

| class                                   | BEFORE | AFTER  |
|-----------------------------------------|--------|--------|
| `cite.total`                            | 2796   | 2800   |
| `cite.checkable`                        | 1687   | 1695   |
| `cite.at_pin`                           | 1573   | 1611   |
| `cite.only_older_revision`              | 53     | 53     |
| `cite.at_no_revision`                   | 59     | 29     |
| `cite.at_no_revision_dangling`          | 0      | 0      |
| `cite.unverifiable_no_claim_about_the_file` | **36** | **6** |
| `cite.upstream_removed`                 | 2      | 2      |

**THE 6 THAT REMAIN ARE ALL IN `tinybendygrad/nn/datasets.bend`**, which another
unit is holding. This slice did not touch it.

**`cite.total` MOVED BY 4** because the slice ADDED four citations (the
`ops_qcom.bend` tables gained explicit subjects, `ops_null.bend` gained two).
**NO FILE THIS SLICE DOES NOT TOUCH GAINED A ROW.** Per-file `unverifiable`:

    BEFORE                                          AFTER
    2  tinybendygrad/mixin/rand.bend               0
    6  tinybendygrad/nn/datasets.bend               6   <- another unit's file
    1  tinybendygrad/nn/mnist_cnn.bend             0
    4  tinybendygrad/renderer/nir_llvmir.bend      0
    1  tinybendygrad/renderer/wgsl.bend            0
    2  tinybendygrad/runtime/ops_null.bend         0
   12  tinybendygrad/runtime/ops_qcom.bend         0
    3  tinybendygrad/runtime/ops_webgpu.bend       0
    1  tinybendygrad/runtime/support/compiler_cuda.bend  0
    2  tinybendygrad/runtime/support/rdma/bnxtdev.bend   0
    1  tinybendygrad/schedule/__init__.bend        0
    1  tinybendygrad/viz/serve.bend                0

## WHAT UPSTREAM ACTUALLY HAS, PER FILE

| file | port's citation | upstream's truth at the pin |
|---|---|---|
| `mixin/rand.bend:12` | `mixin/rand.py:50` | `:50` DECLARES `rand`. `tinygrad/examples/` is EMPTY (`git ls-tree` lists nothing). The port's own `examples/beautiful_mnist.bend` is not upstream's. |
| `mixin/rand.bend:58` | `movement.py:256` | `:256` is inside `flip`. `stack` is at `:270`; the STACK arm that calls `dtype_from_uop` (`ops.py:116`) and `ccast` (`ops.py:618`) is `ops.py:809-812` (`_mop`). |
| `nn/mnist_cnn.bend:43` | `datasets.py:5` | `:5` declares `base_url` = the `storage.googleapis.com/cvdf-datasets/mnist` URL. `.npy` is the PORT'S OWN format; upstream ships `.gz`. |
| `renderer/nir_llvmir.bend:119-121` | `nir.py:156-160/210/77-144/161-202` | `_render_fn`, `_render_footer`, `base_rewrite`, `_render_kernel` are **LLVMIR** constructs: `llvmir.py:173`, `:232`/`:281`, `:81-156`, `:178`. `nir.py` has NONE of them. |
| `renderer/wgsl.bend:60` | `wgsl.py:17` | `patterns` is `PatternMatcher.patterns` (`uop/ops.py:1585`), NOT in `wgsl.py`. The 17 rules are `wgsl.py:67-92`; `base_rewrite` is imported at `:3` and used at `:93`. ALSO: `patterns[:17]` was being parsed as a bare `:17` citation. |
| `runtime/ops_null.bend:28` | `ops_cpu.py:70` | `:70` is `CPUDevice.__init__`. The slot walk the kernargs layout shares with is `struct.pack_into` at `ops_cpu.py:58-59`. |
| `runtime/ops_null.bend:39` | `ops_null.py:29-30` | `:29-30` are `NullQueue.cmd`/`event`. The kernargs are built through `pack_args` at `ops_null.py:33`; the import is at `:9`. |
| `runtime/ops_qcom.bend` (12 rows) | bare `:N` in two tables | EVERY bare `:N` was off by one (the port was written against an upstream one line shorter), and EVERY claim token was the PORT'S OWN name. Real lines: `BUFTYPE_BUF` `:19`, `_qreg_exec`/`qreg` `:35-40`, `ctz` `:42`, `parity` `:44-46`, `pkt7_hdr` `:48`, `pkt4_hdr` `:50`, `_read_lib` `:52`, `cmd`/`reg` `:62`/`:64`, `_cache_flush` `:66-73`, `memory_barrier` `:75`, `gpu_id` guard `:79`, the `kgsl`/`mesa`/`libc` import `:8`. |
| `runtime/ops_webgpu.bend:18/23/38` | `:10`, `:23`, `:71` | `backend_types` is at `:11`, `synchronous` at `:24`, the `wait` flag at `:71`. |
| `runtime/support/compiler_cuda.bend:112` | `compiler_cuda.py:93-97` | `\bnvJitLink\b` does NOT match `nvJitLinkCreate`. The module alias upstream writes on EVERY one of those six lines is `jitlink`. |
| `runtime/support/rdma/bnxtdev.bend:73/74` | `:102`, `:107` | `:102` is the `init[...]` write; the sweep STARTS at `:100` (`if caps.ctx_init_value:`). `:107` is upstream's `flags=...`; `ALL_DONE` alone does NOT match `..._BS_CFG_ALL_DONE`. |
| `schedule/__init__.bend:51` | `__init__.py:28` | `:28` IS `raise AssertionError(...)`. The claim tokens were `upstream`/`RAISES`, from a backtick span running ACROSS TWO LINES. |
| `viz/serve.bend:81` | `uop/ops.py:76` | `:76` IS `def srender`. The token `word_wrap` is NOT in `uop/ops.py`; upstream's is in `tinygrad/helpers.py`, imported by `tinygrad/viz/serve.py:9`. |

## THE THREE MECHANICAL RULES, AND THEY COST THE MOST ITERATION

1. **THE UPSTREAM CONSTRUCT'S NAME MUST BE ON THE SAME LINE AS THE CITATION.**
   `collect()` reads the claim tokens from `c["line"]` -- THE LINE THE CITATION
   IS ON -- and `window_tokens()` gives each backticked name to the NEAREST
   citation ON THAT LINE. A name on the NEXT line belongs to no citation.
   This is why several fixes are line-break fixes and not content fixes.
2. **A PORT SYMBOL MUST NOT BE BACKTICKED ON A CITATION'S LINE EITHER.** The
   gate takes EVERY backticked ident on the line, so the port's own names must
   go in as PROSE ("the port's own `buftype_names`" becomes "the port's own
   buftype_names"). This is the same rule as "a PORT SYMBOL MUST NOT BE WRITTEN
   AS `symbol=` NEXT TO AN UPSTREAM `.py` CITATION", one level up.
3. **A `symbol=` MUST NAME A CONSTRUCT DECLARED IN THE CITED FILE AT THE
   CITED LINE.** `symbol=pack_args` on `ops_null.py:33` would be a
   WRONG-SYMBOL for `todo-cite-gate.py` (`pack_args` is an IMPORT there, not a
   declaration), so it was NOT used; the prose names `pack_args` and cites the
   lines where it occurs.

## THE VERIFICATIONS

### 1. `pin-cite-gate.py`

    .venv/bin/python gates/pin-cite-gate.py --tree $FROZEN --rows OUT.rows

36 -> 6 tree-wide; 30 -> 0 for the eleven files. `# pin-cite-gate: PASS`.

### 2. `todo-cite-gate.py`

Every row in the eleven files still `RESOLVES`. The four failures in the tree
are in OTHER units' IN-FLIGHT files -- `mixin/op.bend`,
`runtime/support/hcq2.bend`, `schedule/indexing.bend`, `uop/divandmod.bend` --
and they were measured BEFORE this slice started (at HEAD, with those files
reverted, the gate reports 10 failures; the other units are removing them as
they go). **NOTHING IN THIS SLICE'S ELEVEN FILES IS RED.**

### 3. COMMENT-ONLY PROOF

`checks/port-compile-gate.py`'s OWN `strip_comments()`, LOADED BY PATH, blank
lines dropped, compared with `git show HEAD:<path>`:

    SAME  tinybendygrad/mixin/rand.bend                    e10c16886ba697a8
    SAME  tinybendygrad/nn/mnist_cnn.bend                  e9ab111f5db5e01b
    SAME  tinybendygrad/renderer/nir_llvmir.bend           599b55d3a8189d36
    SAME  tinybendygrad/renderer/wgsl.bend                 b95c5db1f2165c5b
    SAME  tinybendygrad/runtime/ops_null.bend              41a569ff38c3333f
    SAME  tinybendygrad/runtime/ops_qcom.bend              b5484f5af2e7e7ad
    SAME  tinybendygrad/runtime/ops_webgpu.bend            1f387dfa2bfdd668
    SAME  tinybendygrad/runtime/support/compiler_cuda.bend 232efe61cfd9f018
    SAME  tinybendygrad/runtime/support/rdma/bnxtdev.bend  16ad2be2b47440b9
    SAME  tinybendygrad/schedule/__init__.bend             173083d9271a8552
    SAME  tinybendygrad/viz/serve.bend                     399b34783ea15985

**NO `D.refuse("...")` DIAGNOSTIC STRING WAS TOUCHED** -- this slice changed
NO CODE AT ALL, so the "except the `D.refuse` files" list is EMPTY.

### 4. COMPILE

`.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file>`, ONE AT A
TIME, VERDICT TOKEN read (never the exit code):

    tinybendygrad/mixin/rand.bend                     WITHIN-LIMITS   1026 MB
    tinybendygrad/nn/mnist_cnn.bend                   WITHIN-LIMITS    933 MB
    tinybendygrad/renderer/nir_llvmir.bend            WITHIN-LIMITS    638 MB
    tinybendygrad/renderer/wgsl.bend                  WITHIN-LIMITS    728 MB
    tinybendygrad/runtime/ops_null.bend               WITHIN-LIMITS    219 MB
    tinybendygrad/runtime/ops_qcom.bend               WITHIN-LIMITS    574 MB
    tinybendygrad/runtime/ops_webgpu.bend             WITHIN-LIMITS    221 MB
    tinybendygrad/runtime/support/compiler_cuda.bend  WITHIN-LIMITS    168 MB
    tinybendygrad/runtime/support/rdma/bnxtdev.bend   WITHIN-LIMITS     32 MB
    tinybendygrad/schedule/__init__.bend              WITHIN-LIMITS    440 MB
    tinybendygrad/viz/serve.bend                      WITHIN-LIMITS    436 MB

Peak RSS read from `.agents/slop/peakrss/census.rows` first: the largest of
the eleven is `schedule/__init__.bend` at 671 MB, so all eleven are far under
the 2048 MB ceiling and no two were run at once.

### 5. THE PLANT

**THE PLANT IS A TEXT EDIT ON A COPY OF THE LIVE TREE.** The copy is the live
tree WITH `references/` (see above), so the compiler's `base.bend` is there.

    $PLANT/tinybendygrad/viz/serve.bend:
    -#     `srender` is the def at `uop/ops.py:76`.
    +#     `srender` is the def at `uop/ops.py:1`.

`uop/ops.py:1` is `from __future__ import annotations`; `srender` IS in that
file (at `:76`), so the row makes a claim about it and the census's ambient
cannot explain the miss -- a DANGLING claim.

    $ .venv/bin/python gates/pin-cite-gate.py --tree $PLANT --rows PLANT.rows
    THE DANGLING CLAIMS, the ones whose subject names ONE upstream file outright:
      tinybendygrad/viz/serve.bend:81  uop/ops.py:1  -- the cited line is 'from __future__ import annotations'
    cite.at_no_revision_dangling=1
    cite.unverifiable_no_claim_about_the_file=7
    # pin-cite-gate: FAIL -- 1 citations name ONE upstream file and hold at NO upstream revision (a dangling claim)

**THE CONTROL IS A BYTE-IDENTICAL COPY OF THE SAME LIVE TREE:**

    $ for f in <the eleven>; do cmp -s "$f" "$CONTROL/$f"; done   # all SAME
    $ .venv/bin/python gates/pin-cite-gate.py --tree $CONTROL --rows CONTROL.rows
    cite.at_pin=1493
    cite.at_no_revision_dangling=0
    cite.unverifiable_no_claim_about_the_file=7
    # pin-cite-gate: PASS
    tinybendygrad/viz/serve.bend:81 uop/ops.py:76 at_pin

**THE PLANT FAILS AND THE CONTROL PASSES, AND THE DIFFERENCE IS ONE LINE.**

## WHAT I DID NOT FIX, AND WHY

* **`tinybendygrad/nn/datasets.bend` -- SIX `unverifiable` rows remain.** Another
  unit is editing that file RIGHT NOW; the brief says do not touch it. They are
  `mn_base_url`, `mn_entries`, `CIFAR_URL`, `cifar_batch`, `cifar_batches`,
  `cifar_test`, `x10` -- all the PORT'S OWN names on `tinygrad/nn/datasets.py`
  citations, and they want exactly the treatment this slice gave
  `mnist_cnn.bend`: the upstream construct (`base_url`, `_mnist`, the `cifar`
  URLs, the four `.gz` names) on the citation's line.
* **`runtime/ops_qcom.py`'s header still says "396 lines"** (upstream is 386 at
  the pin), and a few of the port's own table rows still carry off-by-one line
  numbers that are NOT claim tokens (the `qregs`/`qfields`/`flush.of`/
  `exec.of` rows). Those are LINE claims, a different class from TOKEN claims.
  This slice fixed the class it was given.
* **`compiler_cuda.bend:51/64` (`helpers.py:39`) and `schedule/__init__.bend:123`
  (`ops.py:107`) are `at_no_revision`** and were `at_no_revision` BEFORE this
  commit. Not this slice's class.
* **`viz/serve.bend`'s `word_wrap` claim**: upstream's `word_wrap` is in
  `tinygrad/helpers.py` and I did NOT find its declaration line to cite it
  precisely, so the prose says where it LIVES ("upstream's lives in
  tinygrad/helpers.py") and cites the IMPORT (`tinygrad/viz/serve.py:9`) whose
  line DOES name it. I did not invent a `helpers.py:NN` I had not measured.
* **I DID NOT EDIT ANY GATE**, `checks/differ.py` or `checks/devpin.py`.
* **`checks/differ.py` WAS NEVER RUN.** The substrate digest was not needed by
  this slice and was not computed.
