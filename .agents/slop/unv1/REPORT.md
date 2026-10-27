# unv1 -- the citations that named the PORT's own symbols, and the pointers that rotted

## WHAT THIS SLICE WAS

`unv1.rows` carried 158 rows over 27 files: 63 of them `unverifiable_no_claim_about_the_file`
(the citation's claim tokens occur NOWHERE in the cited upstream file, so the port's prose
named a construct upstream does not contain -- a PORT symbol) and 95 of them
`WRONG-LINE`/`DANGLING-LINE` (the port's `.bend` files cite EACH OTHER by line number and the
pointer is stale).

## THE COUNTS, BEFORE AND AFTER, MEASURED WITH THE SAME INSTRUMENTS

`gates/pin-cite-gate.py --rows` over the same tree state, restricted to the 27 files of this
slice:

| class | BEFORE | AFTER |
|---|---|---|
| `unverifiable` | **63** | **0** |
| `dangling` (the FAIL class) | 0 | **0** |
| `at_no_revision` | 4 | 4 (all four PRE-EXISTING, unchanged, not in this slice's rows) |
| `only_older_revision` | 6 | 21 (pre-existing rows whose claim gained an upstream name) |
| `at_pin` | 319 | 366 |
| `uncheckable_no_claim_token` | 217 | 218 |

`gates/bendcite-gate.py --rows` over the same tree state, restricted to the 27 files:

| verdict | BEFORE | AFTER |
|---|---|---|
| `WRONG-LINE` | **95** | **0** |
| `DANGLING-LINE` | 0 | **0** |
| `ABSENT-FILE` | 0 | **0** |
| `RESOLVES` | 70 | 161 |
| `WRONG-LINE-BY-BLOCK` (reported, not failed) | 22 | 26 |

`gates/todo-cite-gate.py --rows`, restricted to the 27 files: `RESOLVES` 289, `NO-CITATION` 3,
`PORT-CITATION` 3, and **0 WRONG-LINE / 0 WRONG-SYMBOL / 0 UNRESOLVABLE** -- IDENTICAL before and
after. The gate's tree-wide rc is 1 because of 4 `WRONG-SYMBOL` rows in files this slice does
NOT own (`examples/test_pkl_imagenet.bend`, `mixin/elementwise.bend`, `uop/ops.bend`).

**WHICH KIND DOMINATED: the PROSE, by 63 to 95.** The `unverifiable` class was the larger
class and it was the one that needed the prose rewritten; the `WRONG-LINE` class was a
mechanical re-point (the gate's own `decl` column says where the construct is now, and the
pointer is corrected to it).

## THE KINDS OF CHANGE

1. **PROSE REWRITTEN (63 rows).** The port's backticked claim named a PORT symbol
   (`pra_len`, `fds_of`, `attrs_of`, `prog.too_many`, `mrender.*`, `cl_err_code`, `arch_of`,
   `q_init`, `stream_slot`, `encode_pick`, `encode_tags`, `wait_signal`, `hp_err_of`,
   `prog_init`, `prog_del`, `cgs_create`, `host_offset`, `icb_keep`, `cns_string`, `magic_ok`,
   `shstrtab`, `Sec.is_progbits`, `Sec.prealloc_of`, `vol`, `ivol`, `volsp`, `lidx`, `run`,
   `cerr_depth`, `rb_1`, `t_gap_ok`, `tn_rop`, `dedup`, `Scheduler`, `names`, `AssertionError`,
   `data`, `F64`, `IndexError`, `max_pool`, `Spec`, ...). Each was rewritten so the prose names
   what UPSTREAM ACTUALLY DOES, in upstream's own vocabulary, with the upstream construct
   named in backticks -- because `gates/pin-cite-gate.py` reads the BACKTICKED SPANS as the
   claim and nothing else. `symbol=` is NOT read by that gate; it is `gates/todo-cite-gate.py`'s
   vocabulary, and it is used there.

2. **BASENAME DISAMBIGUATED (7 rows).** `device.py` -> `tinygrad/device.py`;
   `search.py` -> `tinygrad/codegen/opt/search.py`; `codegen/__init__.py` ->
   `tinygrad/codegen/__init__.py`; `mixin/op.py` -> `tinygrad/mixin/op.py`;
   `ops_python.py` -> `tinygrad/runtime/ops_python.py`; `rangeify.py` ->
   `tinygrad/schedule/rangeify.py`; `mixin/movement.py` -> `tinygrad/mixin/movement.py`.

3. **ABSENCE STATED (8 rows).** Where upstream's construct is GONE at this pin, the prose now
   says so and names the SURVIVING construct: `CUDAQueue` and `pm_bufferize` (removed when
   CUDA lost its hwqueue -- `c0c13ea51`), `HIPProgram` and `HIPProgram.__del__` (removed by
   `d33d97ca7`, hipify cuda), and the HIP `check` (HIP imports CUDA's).

4. **STALE PORT-TO-PORT POINTERS RE-POINTED (95 rows).** Every `WRONG-LINE` row's cited line
   now holds the construct the comment means. The gate's own `decl` column says where the
   construct is; the pointer was corrected to it and the bare `:N` forms were made explicit
   full paths so they resolve.

5. **THE `D.refuse("...")` STRING LITERALS (4 rows).** `extra/models/clip.bend:105,131,155` and
   `extra/models/mask_rcnn.bend:226` carry a stale `.bend:NN` citation INSIDE a refusal
   message. A refusal message is a human-readable diagnostic address -- no gate parses it --
   so the stale line number inside it was corrected. **THIS IS THE ONLY EDIT THAT IS NOT A
   COMMENT**, and it is why `tinybendygrad/extra/models/clip.bend` and
   `tinybendygrad/extra/models/mask_rcnn.bend` do not strip to the same code hash as HEAD.
   The refusal still fires, on the same arm, with the same count -- only the address in the
   message moved. Everything else in the 27 files strips to the SAME code hash as HEAD.

## THE COMMENT-ONLY PROOF

`checks/port-compile-gate.py`'s `strip_comments()` imported BY PATH, blank lines dropped,
`git show HEAD:<path>` against the working tree:

```
files checked: 27
CODE-HASH MISMATCHES: 2
  tinybendygrad/extra/models/clip.bend
  tinybendygrad/extra/models/mask_rcnn.bend
```

Both mismatches are the 4 `D.refuse("...")` diagnostic strings described above. The other 25
files are byte-identical after the comment strip.

## THE COMPILE TOKENS

`.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file>`, ONE bend at a time, the
verdict TOKEN read and not the exit code. ALL 27 FILES: `WITHIN-LIMITS`.

```
ops_dsp.bend            WITHIN-LIMITS  peak-RSS=386 MB
ops_cl.bend             WITHIN-LIMITS  peak-RSS=198 MB
ops_metal.bend          WITHIN-LIMITS  peak-RSS=212 MB
support/elf.bend        WITHIN-LIMITS  peak-RSS=720 MB  (105s)
support/compiler_llvm   WITHIN-LIMITS  peak-RSS=27 MB
ops_cuda.bend           WITHIN-LIMITS  peak-RSS=198 MB
ops_python.bend         WITHIN-LIMITS  peak-RSS=988 MB
renderer/llvmir.bend    WITHIN-LIMITS  peak-RSS=533 MB
codegen/opt/search.bend WITHIN-LIMITS  peak-RSS=167 MB
nn/item.bend            WITHIN-LIMITS  peak-RSS=580 MB
nn/pool.bend            WITHIN-LIMITS  peak-RSS=834 MB
mixin/creation.bend     WITHIN-LIMITS  peak-RSS=847 MB
mixin/movement.bend     WITHIN-LIMITS  peak-RSS=576 MB
tensor.bend             WITHIN-LIMITS  peak-RSS=720 MB
schedule/rangeify.bend  WITHIN-LIMITS  peak-RSS=737 MB
schedule/indexing.bend  WITHIN-LIMITS  peak-RSS=206 MB
codegen/__init__.bend   WITHIN-LIMITS  peak-RSS=314 MB
codegen/late/regalloc   WITHIN-LIMITS  peak-RSS=385 MB
engine/worker.bend      WITHIN-LIMITS  peak-RSS=33 MB
extra/models/clip.bend  WITHIN-LIMITS  peak-RSS=587 MB
extra/models/mask_rcnn  WITHIN-LIMITS  peak-RSS=692 MB
extra/models/transform  WITHIN-LIMITS  peak-RSS=609 MB
function.bend           WITHIN-LIMITS  peak-RSS=608 MB
renderer/amd/dsl.bend   WITHIN-LIMITS  peak-RSS=373 MB
runtime/ops_bend.bend   WITHIN-LIMITS  peak-RSS=331 MB
uop/fold.bend           WITHIN-LIMITS  peak-RSS=599 MB
uop/weak.bend           WITHIN-LIMITS  peak-RSS=622 MB
```

The peak-RSS table is `.agents/slop/peakrss/census.rows`; every file here is under 1 GB and the
sum of any pair is under 60% of `hw.memsize`, so the one-at-a-time rule was the only one
honoured and it was honoured.

## THE PLANTS -- a TEXT EDIT ON A COPY, NEVER `git show HEAD:`

Three trees under `.agents/slop/unv1/plant/`, each a COPY of the working tree:

* `arm/` -- the byte-identical CONTROL.
* `broken2/` -- one upstream construct NAME broken:
  `runtime/ops_dsp.bend`'s "upstream builds the fd vector in `fds`" -> "`fdz`".
* `broken3/` -- one re-pointed PORT-TO-PORT pointer broken:
  `extra/models/clip.bend`'s "nn/layers.bend:937 `nn_conv2d`" -> ":756".

The pin-cite plant, on the copy, restricted to the 27 files:

```
CONTROL : at_pin=366 uncheckable_no_claim_token=218 only_older_revision=21 at_no_revision=4 upstream_removed=1
PLANT   : at_pin=365 uncheckable_no_claim_token=218 only_older_revision=21 at_no_revision=4 upstream_removed=1 unverifiable=1
```

The bendcite plant, on the copy, restricted to the 27 files:

```
CONTROL : RESOLVES=154 UNCLAIMED=115 WRONG-LINE-BY-BLOCK=26 DANGLING-LINE=4 AMBIGUOUS=2 ABSENT-FILE=2 OUT-OF-CORPUS=1
PLANT   : RESOLVES=153 UNCLAIMED=115 WRONG-LINE-BY-BLOCK=26 DANGLING-LINE=4 AMBIGUOUS=2 ABSENT-FILE=2 WRONG-LINE=1 OUT-OF-CORPUS=1
```

The CONTROL's 4 `DANGLING-LINE` and 2 `ABSENT-FILE` are OTHER UNITS' in-flight edits, present
in the copy because the copy is of the moving working tree; the LIVE tree measures 0 for the
27 files of this slice. The PLANT adds exactly ONE row in the failing class and the row is the
one whose citation was broken -- the class MOVED, and it is named.

## THE CORPUS DIGEST

Before this slice's edits: `986410b5760b02d95d17975c86795398886cc2e587db316f5a04da5091635863`
(measured at the start of the session, `1523eb428`).

After: `04d720185285bf83a04710291d644b9b1a05801cbf9eac9c569f654a1fddce06`.

**THE DIGEST MOVED BY MORE THAN THIS SLICE.** Other units were editing `.bend` files
throughout the session (`tinybendygrad/uop/fold.bend`, `mixin/op.bend`, `runtime/webgpu_call.bend`
and forty more, per `AGENTS.md`'s own note), so the digest is NOT a witness of THIS slice's
edits alone. The per-file code-hash proof above is the witness.

## WHAT WAS NOT FIXED, AND WHY

1. **4 `at_no_revision` rows in `renderer/llvmir.bend` and `tensor.bend`.** These were
   `at_no_revision` in the BEFORE reading and are `at_no_revision` in the AFTER reading --
   they are NOT in `unv1.rows` (they are `unverifiable`-class problems in OTHER rows' files
   that the slice's row set does not cover), and fixing them is a different slice's work.
   They are the `tinygrad/renderer/llvmir.py:231 _render_fn`, `:169 CPULLVMCompiler`,
   `tinygrad/tensor.py:422 new_buffer`, and `llvmir.py:20 lconst` pointers.

2. **21 `only_older_revision` rows.** These hold at an OLDER upstream revision but not at the
   pin. They were 6 in the BEFORE reading and are 21 in the AFTER reading: the 15 that grew are
   rows whose prose gained an upstream construct name, so the gate can now SEE that the
   pointer names a construct upstream has but not AT THIS PIN. They are a real class and they
   are NOT this slice's class.

3. **The tree-wide `gates/todo-cite-gate.py` rc is 1.** Four `WRONG-SYMBOL` rows in
   `examples/test_pkl_imagenet.bend`, `mixin/elementwise.bend` and `uop/ops.bend` -- files this
   slice does NOT own. This slice's 27 files read 0 false rows BEFORE and 0 false rows AFTER.

4. **`tinybendygrad/nn/datasets.bend`** -- NOT touched, as instructed.

5. **No `symbol=` was ADDED by this slice.** Every upstream construct this slice names is named
   in BACKTICKS, because `gates/pin-cite-gate.py` reads backticks and `gates/todo-cite-gate.py`
   reads `symbol=`. Writing a `symbol=` next to an upstream citation makes the gate resolve the
   SYMBOL and RE-POINT the line itself, and a `symbol=` that names a PORT symbol -- or a
   builtin, or a construct declared in a DIFFERENT upstream file -- is a NEW way to be wrong.
   The tree's own `symbol=` rows were left alone.
