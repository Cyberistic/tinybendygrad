import Base
import ./../tensor.bend as T
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../nn/state.bend as ST
import ./../nn/onnx.bend as ONNX
import ./../engine/jit.bend as JIT
import ./../extra/datasets/__init__.bend as D

# NOT YET PORTED.
#
# this is the eval path and it is the first milestone toward imagenet,
# because it is the one of the three files that needs no backward pass. Every
# other thing about it is bad news, and the news is measured rather than felt.
# Measured 2026-10-19 03:46-04:15Z at HEAD 80d329a33.
#
# WHY EVAL AND NOT TRAIN. The forward corpus is 34 of 34 byte-identical
# (`unhealthy() -> 0`, `artefacts_ok() -> 0`, `repro_bad() -> 0`, `310 of 310
# files identical across two clean runs`) and every one of those 34 graphs is a
# FORWARD graph. `mixin/gradient.bend`'s 61 rules and `tensor.bend:1988
# tn_backward` exist and NOTHING CALLS THEM. So the forward pass is exercised,
# the backward pass is not, and this file is the one that only needs the
# forward pass. `train_resnet.bend` is the mirror image and is blocked twice
# over. That asymmetry is the entire reason this file is the milestone.
#
# but "needs no backward pass" is not "needs nothing", and the headline finding
# is that the eval path and the model path converge on the same wall.
# This file LOOKS like it dodges ResNet entirely, because it runs a
# PRE-EXECUTED pickle instead of building the graph. It does not dodge it. The
# pickle's bytes CONTAIN a ResNet-50 ONNX graph, and executing that graph needs
# the same Conv/Gemm/MaxPool/Relu/BatchNormalization bodies that
# `extra/models/resnet.bend` needs -- and those bodies are `mixin/op.bend`
# SIDE B, whose last line, mixin/op.bend:1502, reads `# SIDE B's SECTION GOES
# BELOW THIS LINE.`. What the eval path genuinely does NOT need is the
# BACKWARD pass, and that is the whole and ONLY difference between the two
# milestones. "First milestone toward ImageNet" is therefore right, and
# "nearly done" would be a lie told by subtraction.
#
# THE SYMBOL CENSUS. Every symbol :1-19 names, with its instrument:
#
#   EXISTS
#     `GlobalCounters`      (:2,:14)  helpers.bend:2523 symbol=GlobalCounters.init, :2585 `.reset`.
#         Both TYPED -- `reset` takes and returns a `Counters` value rather than
#         mutating an ambient one, which is the port's convention.
#     `getenv`              (:3,:13)  helpers.bend:148 `getenv_str`, :304
#         `getenv_int`. `getenv("CNT", 100)` is `getenv_int` verbatim.
#     `Tensor.shape`        (:16)     tensor.bend:211 `tn_shape` -- for the half
#         that has an object to inspect.
#     `captured.expected_input_info` (:10)  PARTIAL-EXISTS: `engine/jit.bend`
#         :380-401 `InInfo` IS `(view, variables, dtype, device)`, which is
#         jit.py:55 (upstream's `CapturedJit`), and the port says it is ported "IN FULL":
#         `jit.bend:399` symbol=ii_vars
#         :403 is the name list. The RECORD EXISTS. The object that carries it
#         does not -- see `pickle` below.
#     `TinyJit`             (:15, indirectly, via the pickle's payload)
#         PARTIAL-EXISTS, and this one deserves the nuance rather than a MISS:
#         `engine/jit.bend` IS a real port. THE PORT's `engine/jit.bend` WHAT IS PORTED LIST
#         `_TinyJit.__init__` :104-123 and `_TinyJit.__call__` :125-178 as
#         PORTED with "all four arms and both refusals", plus `CapturedJit.__call__`
#         :70-75 and `_prepare_jit_inputs` :84-102 "IN FULL". What is absent is
#         the NAME and the DECORATOR: jit.bend:24 says `function.bend` will want
#         `tiny_jit.of3(f)` and there is no `tiny_jit` def.
#
#   MISSING
#     `sys.argv`            (:7)      MISSING. No argv reader.
#     `pickle`              (:1,:8)   MISSING.  NO UNPICKLER EXISTS. 
#         This is the deepest wall in the file and it is worth being exact,
#         because the name LOOKS like it is covered. `engine/jit.bend:259` has
#         a def called `m_pickle` and it is NOT a codec: it is the MESSAGE
#         STRING `"can't pickle an uncaptured JIT"`. A `.pkl` here is not a
#         tensor dump; it is a Python OBJECT GRAPH containing a live
#         `run_onnx_jit` with a `captured` record, and decoding it means
#         INSTANTIATING CLASSES. The port's own header says it in as many
#         words, `tinybendygrad/helpers.bend:3119`: "The sqlite disk cache is a
#         persistent object store with pickle values. Bend has no pickle and no
#         object graph to store, so the cache becomes the C-effect arena of P6
#         and this is replaced rather than ported."
#     `fetch`               (:3,:7)   MISSING. `grep -rnE "^def fetch\("
#         --include='*.bend' tinybendygrad/` = 0, and helpers.bend:3122 gives
#         the reason in the port's own words: "The HTTP machinery (fetch,
#         fetch_fw, _ensure_downloads_dir) is urllib plus a temp file plus an
#         atomic rename. It is I/O of exactly the kind the master plan puts in
#         runtime/, and its only callers are the weight downloaders."
#         NOTE: a naive `grep -rnE "^def .*fetch"` answers 2, and BOTH are the
#         siblings at `extra/datasets/__init__.bend:49,:53` (`fetch_mnist`,
#         `fetch_cifar`) -- which are themselves REFUSALS. A grep that reads the
#         prefix and calls it a hit is the failure this tree already has a name
#         for.
#     `open(..., "rb")`     (:7)      MISSING, and it is the SAME wall twice.
#         `nn/state.bend:480` is `# TODO(p3) state.py:8 TensorIO -- io.RawIOBase;
#         readinto (:17) needs ...` and `nn/onnx.bend` names the same wall in
#         its own words: "Nothing in this port can read a byte out of a tensor".
#         So there is no byte source for the pickle OR for the images.
#     `imagenet_dataloader` (:25,:53)  MISSING. It is `examples/test_onnx_imagenet.py:25`
#         upstream and the port has no such file. Note that `nn/datasets.bend`
#         (469 lines) has the MNIST AND CIFAR URL TABLES and no ImageNet one:
#         `grep -c imagenet tinybendygrad/nn/datasets.bend` = 0.
#     `OnnxRunner`          (:9,:10,:15)  MISSING. STAGE 3 of `nn/onnx.bend`,
#         and STAGE 3 is "NOT DONE": nn/onnx.bend:36-37 lists
#         `OnnxRunner.__init__` :374-376 through `__call__` :441-470 as
#         unwritten, and :57-58 gives the reason -- "`OnnxRunner.__call__
#         (:441-470) -- the interpreter loop, and it dispatches into the op
#         table, so it is unreachable before the op bodies exist."
#     the 167 onnx op bodies (:15)   missing. stage 4, nn/onnx.bend:38 -- "not
#         DONE. The 167 op BODIES (:475-1307), the node-shape arithmetic that
#         goes with them, and the quantization family." And the PROTOBUF READER
#         they need is blocked too, THE PORT's `nn/onnx.bend` NOT PORTED BLOCK: "`PBBufferedReader`
#         (:73-119) and all of `OnnxPBParser` (:121-349). WALL: a protobuf reader
#         OVER A TENSOR".
#     `Tensor.argmax`       (:17)     MISSING. `grep -rnE "^def mo_argmax"
#         --include='*.bend' tinybendygrad/` = 0. THE PORT's `mixin/op.bend` SIDE A INVENTORY lists
#         `argmax` inside SIDE A but no def carries it, and `rc_arg`
#         mixin/reduce.bend:203 symbol=rc_arg.of is a REDUCTION INTERNAL, not `Tensor.argmax`.
#         So the eval loop has no way to produce a PREDICTION, which is the one
#         thing an eval script exists to produce.
#     `Tensor.to`           (:15,:17) MISSING. `mixin/movement.bend`'s wall list
#         says it outright: "`to` is `tensor.py:353`" -- not in the file
#         movement owns -- "and they are reported rather than ported".
#     `Tensor.item`         (:17)     MISSING. `grep -rnE "^def .*item"
#         --include='*.bend' tinybendygrad/` -- every hit is a renderer or an
#         ELF symbol reader (`renderer/*`, `Lds.item`). None is `Tensor.item`.
#     `hit += y == t`       (examples/test_pkl_imagenet.py:18)  host integer arithmetic over a REALIZED
#         value. Blocked by `.item()`, and by nothing else.
#
#   4 of the 16 upstream symbols are present, 11 are missing and 1 is
#   partial. THE TWO BIGGEST WALLS, in order:
#     1. NO UNPICKLER, and no byte source to feed one.
#     2. `OnnxRunner` STAGE 3 AND 167 OP BODIES STAGE 4, which need
#        `conv2d`/`batchnorm`/the pools -- i.e. `mixin/op.bend` SIDE B, the
#        EMPTY HALF of a 1523-line file.
#   WALL 2 IS THE SAME WALL `extra/models/resnet.bend` STOPS AT. That is the
#   finding. Wall 1 is the only thing that is UNIQUELY the eval path's.

# THE GATE MOVED TO `gates/test_pkl_imagenet-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Every expectation in the driver is generated by calling CPython, so no row
# there is typed by hand.
