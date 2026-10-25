# THE 78 FALSE CITATIONS OUTSIDE `runtime/**` -- THE SLICE THAT IS NOW 1

Unit: citefix9. Date: 2026-10-25. One commit: `9c5961b99` (32 files).

## 1. THE MEASUREMENT, ON TWO FROZEN COPIES OF THE PORT TREE

The port tree is owned by other units and MOVES, so both readings were taken on a COPY
(`cp -R tinybendygrad`), with the SAME instruments:

```
.venv/bin/python gates/pin-cite-gate.py --tree $FRZ/{before,after} --rows OUT.rows
.venv/bin/python gates/todo-cite-gate.py --port $FRZ/{after}/tinybendygrad --rows OUT.rows
.venv/bin/python .agents/slop/citeclass/census.py --pin OUT.rows --todo OUT.rows --out OUT.rows
```

`gates/pin-cite-gate.py` is a SHARED instrument and it CHANGED under this unit (another
unit was editing it), so the BEFORE reading was RE-TAKEN with the instrument as it stood
at the end. **The BEFORE is 78 either way**, so the comparison is two trees and not two
instruments.

| | BEFORE | AFTER |
|---|---|---|
| **FALSE citations outside `tinybendygrad/runtime/`** | **78** | **1** |
| `gates/todo-cite-gate.py` rows | 1131, 0 false | 1140, 0 false |
| `gates/todo-cite-gate.py` WRONG-LINE / WRONG-SYMBOL / UNRESOLVABLE | 0 / 0 / 0 | 0 / 0 / 0 |
| `gates/pin-cite-gate.py` | PASS | PASS |

**THE ONE THAT REMAINS IS `tinybendygrad/uop/fold.bend:132`** -- `dtype.py:193` -- and that
file is ANOTHER UNIT'S, so it is NOT touched here. The fix is the FULL PATH
`tinygrad/dtype.py:193`: the port's `least_upper_dtype` IS at that line at the pin, and
`dtype.py` alone names THREE upstream files (`tinygrad/dtype.py`,
`tinygrad/mixin/dtype.py`, `tinygrad/codegen/decomp/dtype.py`), so the bare basename
resolves to nothing.

## 2. PER FILE

`78 -> 1`. Every file that went to zero:

| file | before | after | | file | before | after |
|---|---|---|---|---|---|---|
| `codegen/decomp/dtype.bend` | 1 | 0 | | `nn/__init__.bend` | 1 | 0 |
| `codegen/decomp/transcendental.bend` | 1 | 0 | | `nn/layers.bend` | 2 | 0 |
| `engine/jit.bend` | 1 | 0 | | `nn/onnx.bend` | 4 | 0 |
| `examples/test_pkl_imagenet.bend` | 1 | 0 | | `nn/optim.bend` | 1 | 0 |
| `examples/train_resnet.bend` | 6 | 0 | | `renderer/isa/x86.bend` | 2 | 0 |
| `extra/datasets/preprocess_imagenet.bend` | 1 | 0 | | `renderer/llvmir.bend` | 4 | 0 |
| `extra/models/bert.bend` | 5 | 0 | | `renderer/ptx.bend` | 1 | 0 |
| `extra/models/clip.bend` | 1 | 0 | | `renderer/tc_ptx.bend` | 1 | 0 |
| `extra/models/convnext.bend` | 1 | 0 | | `renderer/wgsl.bend` | 2 | 0 |
| `extra/models/llama.bend` | 12 | 0 | | `schedule/multi.bend` | 1 | 0 |
| `extra/models/mask_rcnn.bend` | 1 | 0 | | `tensor.bend` | 1 | 0 |
| `extra/models/retinanet.bend` | 1 | 0 | | `uop/render.bend` | 2 | 0 |
| `extra/models/rnnt.bend` | 8 | 0 | | `uop/symbolic.bend` | 2 | 0 |
| `extra/models/transformer.bend` | 6 | 0 | | `uop/weak.bend` | 1 | 0 |
| `extra/models/vit.bend` | 1 | 0 | | **`uop/fold.bend`** | **1** | **1** |
| `function.bend` | 1 | 0 | | | | |
| `mixin/creation.bend` | 2 | 0 | | | | |
| `mixin/op.bend` | 2 | 0 | | | | |

## 3. THE THREE KINDS OF CHANGE

**THE SUBJECT WAS AMBIGUOUS.** A bare basename names several upstream files and the
census resolved none of them: `dtype.py` is 3, `helpers.py` is 7, `op.py` is 2, `bert.py`
is 2, `llama.py` is 2, `optim.py` is 2, `transformer.py` is 2, `kits19.py` is 2. Each
citation now spells the file it means.

**THE CLAIM NAMED A PORT SYMBOL, so NO RE-POINT COULD MAKE IT HOLD.** The prose now says
what upstream does at the pin:

- upstream DELETED `_written_uops` (and realize.py's `get_call_written_bufs`) in
  `a26c50b01`; `engine/jit.py:67` is `_jit_bufs` now, and the PORT's copy of
  `get_call_written_bufs` has NO upstream counterpart at the pin;
- upstream DELETED the whole `pyrender` round-trip in `81157efb0`; `uop/spec.py:41` PRINTS
  `render_uir(lst)` under `DEBUG >= 3` and there is no `exec` to port;
- upstream's `scaled_dot_product_attention` is `tinygrad/mixin/rand.py:298`, and
  `op.py:1177` is `masked_select`'s body;
- upstream's `self.running_mean.assign(...)` is `tinygrad/nn/__init__.py:56`;
- `examples/train_resnet.py` is the file the port's symbol census is OF -- the ambient had
  aimed it at `extra/training.py` -- and `numpy` is used at :24,:25,:36,:38 there;
- the PORT'S OWN ORACLE (`llvmir-oracle.py`, lines 647-648) is named as prose instead of
  being cited as if it were upstream;
- `const_like` reads `self._shape` at `tinygrad/uop/ops.py:581-583`.

**THE LINE MOVED.** Every re-pointed line is the pin's line: `float_to_fp8` is
`tinygrad/dtype.py:238`, `truncate` is `:289`, `least_upper_dtype` is `:193`,
`_softmax` is `tinygrad/mixin/op.py:657`, `log_softmax` is `:686`, `linear` is `:1254`,
`dot` is `:367`, `arange` is `:166`, `_jit_bufs` is `tinygrad/engine/jit.py:67`,
`param_like` is `tinygrad/uop/ops.py:1228-1234`, `new_buffer` is `:835`, `_frompy` is
`:855`, `alloc_vregs` is `tinygrad/renderer/isa/x86.py:293`, `X86LinearContext` is
`:681-707`, `packed_store` is `tinygrad/renderer/wgsl.py:15`, `packed_load` is `:24`,
`sqrt` is `tinygrad/mixin/elementwise.py:479`, `run_branch` is `tinygrad/nn/onnx.py:468`.

## 4. TWO CONSTRAINTS, AND BOTH ARE GEOMETRY

**`gates/header-census-gate.py`'s `declared_target` IS THE FIRST `tinygrad/...py` PATH IN
A HEADER BLOCK, AND EVERY BARE `:N` IN THAT BLOCK RESOLVES AGAINST IT.** So a
`tinygrad/...py` path can silently RE-AIM every bare citation in the file. MEASURED: the
first edit set put `tinygrad/nn/optim.py` into `extra/models/llama.bend` and the file's
bare `:53`, `:44`, `:158` -- citations about `extra/models/llama.py` -- were RE-AIMED at
`tinygrad/nn/optim.py`, and 9 NEW false rows appeared. The spelling `dir/name.py`
(`nn/optim.py`, `mixin/op.py`, `mixin/rand.py`, `nn/__init__.py`) is unique in BOTH
instruments and moves NO ambient, so that is what is used where the target is something
else; the full `tinygrad/...py` path is used where the file IS the target.

**`gates/pin-cite-gate.py` BINDS A BACKTICKED CLAIM TOKEN TO THE NEAREST CITATION**, and a
token more than 40 CHARACTERS from every OTHER citation on the line belongs to none of
them. So on a line with two citations the names have to sit BETWEEN them, which is why
several lines read "`_from_subgraph` `_init_from_graph` onnx.py:298 ...". **THE
INSTRUMENT WAS NOT CHANGED** -- it is a shared gate.

## 5. THE COMMENT-ONLY PROOF

`.agents/slop/citefix/commentproof.py` (which imports `checks/port-compile-gate.py`'s own
`strip_comments()`) against `HEAD`:

```
COMMENT-ONLY PROOF: 32 file(s) pass
```

**EVERY FILE'S LINE COUNT IS UNCHANGED**: a `.bend` file's line numbers are an INTERFACE
(32 of these files are cited by other files), and a line added or removed would break a
citation somewhere else. **THE EOF-NEWLINE CONVENTION IS PART OF THAT**: 17 of these
files have NO trailing newline at `HEAD`, and the edit set restores it byte for byte.

## 6. THE COMPILE

32 files, ONE `bend` process at a time, under `checks/bounded.py --mb 2048`, reading the
VERDICT TOKEN and never the exit code:

```
.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend <file>
-> [bounded] WITHIN-LIMITS  rc=0  peak-RSS=445 MB (ceiling 2048)  1s
```

**32 of 32 `WITHIN-LIMITS`.** Peaks 208 MB - 1482 MB against the 2048 MB ceiling; the
list is `.agents/slop/citefix9/compile-tokens.rows`. The peaks were taken from
`.agents/slop/peakrss/census.rows` before starting (`nn/onnx.bend` 777 MB,
`uop/symbolic.bend` 745 MB, `codegen/decomp/dtype.bend` 699 MB) and nothing was run
concurrently with a `bend` process. **THE `MACHINE: VIOLATED` LINE IS NOT ATTRIBUTABLE TO
THE CHILD** -- it is the machine's loadavg, and the verdict token is the child's.

## 7. THE PLANT

`.agents/slop/citefix9/plant.py` -- a TEXT EDIT on a COPY (never `git show HEAD:`) that
breaks ONE re-pointed citation, plus a BYTE-IDENTICAL control copy of the same tree:

```
PLANT    : tinybendygrad/renderer/llvmir.bend:188  tinygrad/dtype.py:238 -> tinygrad/dtype.py:239
CONTROL  : a byte-identical copy -> rc=0 GREEN
PLANTED  : the edited copy       -> rc=1 RED (1 dangling claim)
CENSUS   : control 1 false row(s); planted 2 false row(s)
PLANT OK
```

The control is asserted BYTE-IDENTICAL to the live tree before the gate runs, so a plant
whose control differs would be measuring the difference between two trees and not the
gate.

## 8. THE CORPUS DIGEST

```
.venv/bin/python -c "import sys; sys.path.insert(0,'checks'); import differ; print(differ.substrate_digest())"
BEFORE  4254260b227af49dcb32e27aac905a1ee7c012323b8c6048107c321b82e2f344   (HEAD's tree)
AFTER   bcd163e8143531d364cee703d48c379a1ed629d481094e1f47c040e4308a54d8   (the live tree)
```

The digest MOVES, and it must: a comment IS part of the substrate, and this commit
changed 92 comment lines. `checks/differ.py run` was NOT run -- it is the corpus run, and
the brief forbids it.

## 9. WHAT IS NOT FIXED, AND WHY

**ONE: `tinybendygrad/uop/fold.bend:132`** -- `dtype.py:193`. Another unit owns that file
(its own commits landed DURING this slice), so it is not touched here. The fix is the
FULL PATH `tinygrad/dtype.py:193`: the port's `least_upper_dtype` IS at that line at the
pin, and the bare `dtype.py` names three upstream files.

**AND THE 19 ROWS THE QUEUE DID NOT NAME.** `.agents/slop/citefix/left-tok9.rows` has 59
rows, and the slice is 78: the queue is 19 SHORT. The 19 are in
`examples/train_resnet.bend` (6), `nn/onnx.bend` (4), `mixin/op.bend` (2),
`renderer/isa/x86.bend` (2), `renderer/wgsl.bend` (2), `function.bend` (1),
`nn/optim.bend` (1) and `tensor.bend` (1). **THEY ARE FIXED TOO** -- the target was the
SLICE, and a queue that is 19 short of the slice is not the slice.

## 10. THE INSTRUMENTS THIS SLICE USED

All under `.agents/slop/citefix9/`: `analyse.py` (which upstream file a subject names and
whether the claim holds there), `check.py` (every citation on every line of a file, with
its tokens and its verdict), `try.py` (one candidate line), `edits.py` .. `edits4.py` (the
edit sets), `plant.py`, `compile-tokens.rows`, `touched.txt`.
