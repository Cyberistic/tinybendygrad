# THE CITATIONS OUTSIDE THE `TODO(pN)` POPULATION -- THE SLICE THAT IS NOT `runtime/**`

Unit: citefix. Date: 2026-10-23. Two commits: `5f2eeaf1a` (mixin/movement.bend) and
`52c9f5ce5` (the other 60 files).

## 1. THE MEASUREMENT, ON TWO FROZEN TREES

The tree MOVED under this unit (other units committed five times), so the before/after is
measured on TWO FROZEN COPIES -- `git archive` of the base commit and of the fix -- with
the SAME instruments, so the two readings compare two trees and not two moments.

```
git archive 65b333037 tinybendygrad | tar -x -C $FRZ/before    # the base
git archive 52c9f5ce5 tinybendygrad | tar -x -C $FRZ/after     # the fix
.venv/bin/python gates/pin-cite-gate.py --tree $FRZ/{before,after} --rows OUT.rows
.venv/bin/python gates/todo-cite-gate.py --port $FRZ/{before,after}/tinybendygrad --rows OUT.rows
.venv/bin/python .agents/slop/citefix/slice.py --tree $FRZ/{before,after} --pin ... --todo ... --out ...
```

| | BEFORE `65b333037` | AFTER `52c9f5ce5` |
|---|---|---|
| citations in my slice | 1211 | 1212 |
| **FALSE at the pin** | **331** | **78** |
| of those, not measured by `todo-cite-gate.py` | 313 | 65 |
| `runtime/**` (another unit's) | 269 | 269 |
| `cite.at_pin` (tree-wide) | 769 | 1020 |
| `cite.only_older_revision` | 352 | 164 |
| `cite.at_no_revision` | 483 | 419 |
| `cite.ambient_relocated` | 2 | 1 |
| `todo-cite-gate.py` | PASS | PASS, 0 WRONG-LINE / 0 WRONG-SYMBOL / 0 UNRESOLVABLE |

**`runtime/**` IS 269 BEFORE AND 269 AFTER: another unit's slice, and I did not touch a
byte of it.** The `cite.at_pin` move (769 -> 1020) is smaller than the live tree's
(820 -> 1284) because the other unit's UNCOMMITTED work in `runtime/**` is not in the
frozen trees -- which is exactly why the frozen measurement is the one that counts.

## 2. PER FILE

`331 -> 78`. The files that went to zero: `mixin/movement.bend` 11->0,
`mixin/rand.bend` 11->0, `mixin/creation.bend` 16->2, `schedule/__init__.bend` 10->0,
`schedule/prepare.bend` 8->0, `codegen/simplify.bend` 7->0, `device.bend` 5->0,
`engine/realize.bend` 10->0, `helpers.bend` 2->0, `schedule/indexing.bend` 7->0,
`schedule/memory.bend` 4->0, `schedule/multi.bend` 7->1, `uop/divandmod.bend` 3->0,
`uop/fold.bend` 5->1, `viz/serve.bend` 1->0 and 35 more. The whole table is
`.agents/slop/citefix/slice-FROZEN-{BEFORE,AFTER}.rows`.

## 3. THE KINDS OF CHANGE

**LINE MOVED (the bulk).** Upstream's files grew and shrank between the revision the port
was written against and the pin `5c2bf39d6c4b`, so the port's line numbers are a
REVISION, not a fact. `movement.py`: `_pool` 598 -> 614, `stack` 256 -> 270,
`split` 423 -> 438, `chunk` 449 -> 464, `squeeze` 287 -> 301, `unsqueeze` 308 -> 323,
`flatten` 345 -> 360, `unflatten` 361 -> 376, `transpose` 328 -> 343, `pad_to` 279 -> 293,
`shrink_to` 276 -> 290, `view` 283 -> 297, `diag` 501 -> 516, `diagonal` 512 -> 527,
`roll` 536 -> 551, `unfold` 618 -> 634, `repeat_interleave` 560 -> 575,
`meshgrid` 474 -> 489, `rearrange` 378 -> 393, `repeat` 576 -> 591, `max_shape` 19 -> 50.
`ops.py`: `as_shape` 812 -> 786, `marg` 814-819 -> 792, `UOp` 609 -> 233,
`UOp.simplify` 513 -> 495, `graph_rewrite(self, symbolic)` 515 -> 501.
`onnx.py`: `_resolve_pool_pads` 495 -> 415, `_auto_pad` 491 -> 411,
`_onnx_pads_to_tiny_pads` 481 -> 402, `_axes` 479 -> 399, `ImageDecoder` 578 -> 498,
`Gradient` 1305 -> 1216, `Gemm` 769 -> 687, `GlobalAveragePool` 766 -> 684,
`Attention` 1011, `EmbedLayerNormalization` 929 -> 841, `RotaryEmbedding` 1106 -> 1017.
`device.py`: `ALL_DEVICES` 20 -> 18, `get_available_devices` 46 -> 48,
`_select_device` 58 -> 56, `_canonicalize` 26 -> 28, `Buffer` 167 -> 111.
`simplify.py`: `flatten_range` 14 -> 8, `pm_load_collapse` 152 -> 153.
`llama.py`, `clip.py`, `bert.py`: `extra/models/*.py` are at `extra/models/`, not under
`tinygrad/`, and their line numbers moved too (`default_bpe` 15, `fetch` 17,
`bytes_to_unicode` 37, `gzip.open` 60, `re.compile` 75, `RMSNorm` 53/54/137/138/200).

**SYMBOL NAMED (the durable form).** A re-pointed citation now says
`ops.py:792 symbol=marg`: a line number moves when upstream moves and a name does not.
`gates/todo-cite-gate.py` judges a `symbol=` row by the name, so the row is `symbol-decl`
and not a coincidence of text. **THE FIELD IS ONLY ADDED WHERE THE GATE CAN RESOLVE THE
SUBJECT** -- that gate's corpus is `tinygrad/` only, so a citation to
`examples/llama.py` or to an ambiguous basename (`dtype.py`, three files) would be
UNRESOLVABLE, which is a RED row; those keep the port's compact form.

**UPSTREAM GONE, AND SAID SO.** `mixin/movement.bend` said `_shape`'s movement arms are
"RESHAPE, EXPAND, PERMUTE, PAD, SHRINK and FLIP". At this pin **`Ops.FLIP` IS NOT IN
upstream at all** -- `GroupOp.Movement` is FIVE ops -- and upstream's `flip` is built from
PAD/SHRINK/TRANSPOSE. The header now says FIVE arms and names the missing one, and the
cited range is the five arms' real range (`ops.py:395-414`).

**CLAIM WAS WRONG ABOUT UPSTREAM, CORRECTED.** `mixin/movement.bend`'s header also said
the vendored `tinygrad/nn/onnx.py` has 1319 lines; at the pin it has 1230.

**THE BARE NUMBERS BECAME CITATIONS.** `(:604)` resolved to the DECLARED TARGET by the
census's ambient, and `(:576)` resolved to `mixin/op.bend` because a filename on the same
line won -- so the port's own shorthand was pointing at the wrong file. Each is now an
explicit `movement.py:N` with a name.

## 4. THE COMMENT-ONLY PROOF

```
.venv/bin/python .agents/slop/citefix/commentproof.py <the 61 files>
-> COMMENT-ONLY PROOF: 61 file(s) pass
```

`checks/port-compile-gate.py`'s own `strip_comments()`, imported BY PATH, compared
against `HEAD` read with `git show HEAD:<path>` -- NOT the working copy and NOT the
index, because this tree's index is armed. **Every file's LINE COUNT is unchanged**:
a `.bend` file's line numbers are an INTERFACE (61 of these files are cited by other
files), so an edit that added or removed a line would break a citation somewhere else.

## 5. THE COMPILE

61 files, ONE `bend` process at a time, under `checks/bounded.py --mb 2048`, reading the
VERDICT TOKEN and never the exit code:

```
.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file>
-> [bounded] WITHIN-LIMITS  rc=0  peak-RSS=676 MB (ceiling 2048)  1s
```

**61 of 61 `WITHIN-LIMITS`.** The list is `.agents/slop/citefix/compile-tokens.rows`.
The peak-RSS numbers were taken from `.agents/slop/peakrss/census.rows` before starting
(`movement.bend` 375 MB, `dtype.bend` 683-699 MB, `nn/onnx.bend` 777 MB), and nothing was
run concurrently with a `bend` process.

## 6. THE PLANT

`.agents/slop/citefix/plant.py` -- a TEXT EDIT on a COPY (never `git show HEAD:`) that
breaks ONE re-pointed citation, plus a BYTE-IDENTICAL control and the LIVE tree:

```
PLANT    : tinybendygrad/mixin/movement.bend:22  ops.py:792 -> ops.py:793 symbol=marg
CONTROL  : a byte-identical copy -> rc=0 GREEN (0 bad row(s))
LIVE     : the live tree        -> rc=0 GREEN (0 bad row(s))
PLANTED  : the edited copy       -> rc=1 RED (1 bad row(s))
    tinybendygrad/mixin/movement.bend:22  ops.py:793  symbol=marg  how=symbol-absent
PLANT OK
```

The control is a copy of the LIVE tree (`copytree`), and the assertion
`control/.../movement.bend == ROOT/.../movement.bend` is checked byte for byte, so a
plant whose control differs is measuring the difference between two trees and not the
gate.

## 7. THE COMMITS

```
5f2eeaf1a  mixin/movement.bend: 27 upstream citations re-pointed at the pin's constructs
52c9f5ce5  the upstream citations OUTSIDE the TODO(pN) population, re-pointed at the pin's constructs
```

Both by `git commit --only -F <msgfile> -- <path>`, on the SHARED index, never
`git add -A` and never `git add <dir>`. `git show --stat` and `git fsck --no-progress`
were run in the SAME command; `git fsck` reports the three PRE-EXISTING malformed trees
(`d57bc484`, `d83cf685`, `3a60f33f`) and nothing else.

## 8. THE CORPUS DIGEST

```
.venv/bin/python -c "import sys; sys.path.insert(0,'checks'); import differ; print(differ.substrate_digest())"
BEFORE  67036f66a3d2520418d894677db8a588ad082239908db0a3f8189d7c20cf0cdb
AFTER   12e25d429c50d01430f77db59a955c1b175ee2f8cbd5fc00106f34c475c77c8a
```

The digest MOVES, and it must: a comment IS part of the substrate, and this commit
changed 237 comment lines. `checks/differ.py run` was NOT run (the brief forbids it); the
digest is the instrument the brief names.

## 9. WHAT IS NOT FIXED, AND WHY

**78 citations remain false, and they are a CLASS, not a scattering.** 65 of them are
`at_no_revision`, 12 `only_older_revision`, 1 `ambient_relocated`. **59 of the 78 have
NO CLAIM TOKEN THAT OCCURS ANYWHERE IN THE CITED FILE** -- the port's prose names a PORT
symbol (`mxm_marg`, `mo_eqmul`, `scaled_dot_product_attention`, `ew_k`, `ufix`) and the
upstream file does not contain that name AT ANY REVISION, so **no re-point can make the
claim hold**. The fix for those is the PROSE: naming the upstream construct the claim is
about, next to the citation. Each one is a reading of the upstream file, not a line
number, and 59 readings do not fit in the time this unit had.

The queue is `.agents/slop/citefix/left-tok9.rows`:
**40** rows whose subject is an AMBIGUOUS basename (2 upstream files),
**7** rows whose subject names 3 upstream files, **7** rows whose subject names 7, **4**
more of the 2-file kind, and **1** whose subject names no file at all.

**OTHER THINGS FOUND AND NOT FIXED, WITH THE REASON.**

- `gates/pin-cite-gate.py`'s `_NEAREST = 40` GEOMETRY is a CONSTRAINT, not a style: a
  backticked name is a claim token of a citation only if it is within 40 CHARACTERS of
  every OTHER citation on the line. So a line with three citations cannot carry a
  `symbol=` on each of them without the attribution moving, and several re-points had to
  put the descriptive words BEFORE the citation. I did not change the instrument -- it is
  a shared gate and the brief forbids editing it.
- `gates/todo-cite-gate.py`'s `symbol=` binding is PER LINE and NEAREST-PRECEDING, and
  its SLOT LIST is `CITEs` first and then `BAREs` -- so a line that mixes an explicit
  subject with bare continuations binds the bare ones' fields to the wrong citation.
  Every such line in my slice was written so that each citation carries its own field,
  but the instrument's rule is worth knowing.
- `gates/todo-cite-gate.py`'s CORPUS IS `tinygrad/` ONLY. A citation to
  `examples/llama.py`, `extra/models/clip.py` or `examples/test_onnx_imagenet.py` is
  UNRESOLVABLE there, and a `symbol=` on one of those is a RED row. `gates/pin-cite-gate.py`
  reads the WHOLE repository, so the two gates do not see the same population.
- `mixin/movement.bend`'s `Ops.FLIP` finding has a CONSEQUENCE this unit did not chase:
  `uop/fold.bend` still carries FLIP arms ported from an OLDER upstream revision
  (`ops.py:415-428`, `ops.py:429-431` are cited there), and `Ops.FLIP` does not exist at
  this pin. That is a PORT-SEMANTICS question about `uop/fold.bend`, not a citation, and
  `uop/fold.bend` is cited by 29 other files.
- `tinybendygrad/codegen/decomp/dtype-mut.bend` and `codegen/late/.linearizer-mut.bend`
  are SCATCH COPIES (`*-mut.bend`), which the tree's own `.gitignore` and the census's
  `is_scratch()` exclude. Their 5 false citations are not the port's and are not mine.
- `examples/train_resnet.bend`'s 6 false rows are one line carrying SIX citations to
  `extra/training.py` with the token `numpy`; the fix is the prose, and the line is
  190 characters long.
