import Base
import ./../tensor.bend as T
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../nn/state.bend as ST
import ./../nn/onnx.bend as ONNX
import ./../engine/jit.bend as JIT
import ./../extra/datasets/__init__.bend as D

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of examples/test_pkl_imagenet.py (19 LOC).
# NOT YET PORTED.
#
# THIS IS THE EVAL PATH AND IT IS THE FIRST MILESTONE TOWARD IMAGENET,
# BECAUSE IT IS THE ONE OF THE THREE FILES THAT NEEDS NO BACKWARD PASS. Every
# other thing about it is bad news, and the news is measured rather than felt.
# Measured 2026-10-19 03:46-04:15Z at HEAD 80d329a33.
#
# WHY EVAL AND NOT TRAIN. The forward corpus is 34 of 34 byte-identical
# (`unhealthy() -> 0`, `artefacts_ok() -> 0`, `repro_bad() -> 0`, `310 of 310
# files identical across two clean runs`) and every one of those 34 graphs is a
# FORWARD graph. `mixin/gradient.bend`'s 61 rules and `tensor.bend:2015
# tn_backward` exist and NOTHING CALLS THEM. So the forward pass is exercised,
# the backward pass is not, and this file is the one that only needs the
# forward pass. `train_resnet.bend` is the mirror image and is blocked twice
# over. That asymmetry is the entire reason this file is the milestone.
#
# BUT "NEEDS NO BACKWARD PASS" IS NOT "NEEDS NOTHING", AND THE HEADLINE FINDING
# IS THAT THE EVAL PATH AND THE MODEL PATH CONVERGE ON THE SAME WALL.
# This file LOOKS like it dodges ResNet entirely, because it runs a
# PRE-EXECUTED pickle instead of building the graph. It does not dodge it. The
# pickle's bytes CONTAIN a ResNet-50 ONNX graph, and executing that graph needs
# the same Conv/Gemm/MaxPool/Relu/BatchNormalization bodies that
# `extra/models/resnet.bend` needs -- and those bodies are `mixin/op.bend`
# SIDE B, whose last line, mixin/op.bend:1523, reads `# SIDE B's SECTION GOES
# BELOW THIS LINE.`. What the eval path genuinely does NOT need is the
# BACKWARD pass, and that is the whole and ONLY difference between the two
# milestones. "First milestone toward ImageNet" is therefore right, and
# "nearly done" would be a lie told by subtraction.
#
# THE SYMBOL CENSUS. Every symbol :1-19 names, with its instrument:
#
#   EXISTS
#     `GlobalCounters`      (:2,:14)  helpers.bend:2580 `.init`, :2582 `.reset`.
#         Both TYPED -- `reset` takes and returns a `Counters` value rather than
#         mutating an ambient one, which is the port's convention.
#     `getenv`              (:3,:13)  helpers.bend:150 `getenv_str`, :304
#         `getenv_int`. `getenv("CNT", 100)` is `getenv_int` verbatim.
#     `Tensor.shape`        (:16)     tensor.bend:216 `tn_shape` -- for the half
#         that has an object to inspect.
#     `captured.expected_input_info` (:10)  PARTIAL-EXISTS: `engine/jit.bend`
#         :380-401 `InInfo` IS `(view, variables, dtype, device)`, which is
#         jit.py:55 (upstream's `CapturedJit`), and the port says it is ported "IN FULL":
#         `jit.bend:403` symbol=ii_vars
#         :403 is the name list. The RECORD EXISTS. The object that carries it
#         does not -- see `pickle` below.
#     `TinyJit`             (:15, indirectly, via the pickle's payload)
#         PARTIAL-EXISTS, and this one deserves the nuance rather than a MISS:
#         `engine/jit.bend` IS a real port. jit.bend:38-41 lists
#         `_TinyJit.__init__` :104-123 and `_TinyJit.__call__` :125-178 as
#         PORTED with "all four arms and both refusals", plus `CapturedJit.__call__`
#         :70-75 and `_prepare_jit_inputs` :84-102 "IN FULL". What is absent is
#         the NAME and the DECORATOR: jit.bend:24 says `function.bend` will want
#         `tiny_jit.of3(f)` and there is no `tiny_jit` def.
#
#   MISSING
#     `sys.argv`            (:7)      MISSING. No argv reader.
#     `pickle`              (:1,:8)   MISSING. ** NO UNPICKLER EXISTS. **
#         This is the deepest wall in the file and it is worth being exact,
#         because the name LOOKS like it is covered. `engine/jit.bend:261` has
#         a def called `m_pickle` and it is NOT a codec: it is the MESSAGE
#         STRING `"can't pickle an uncaptured JIT"`. A `.pkl` here is not a
#         tensor dump; it is a Python OBJECT GRAPH containing a live
#         `run_onnx_jit` with a `captured` record, and decoding it means
#         INSTANTIATING CLASSES. The port's own header says it in as many
#         words, `tinybendygrad/helpers.bend:3190`: "The sqlite disk cache is a
#         persistent object store with pickle values. Bend has no pickle and no
#         object graph to store, so the cache becomes the C-effect arena of P6
#         and this is replaced rather than ported."
#     `fetch`               (:3,:7)   MISSING. `grep -rnE "^def fetch\("
#         --include='*.bend' tinybendygrad/` = 0, and helpers.bend:3193 gives
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
#         `nn/state.bend:498` is `# TODO(p3) state.py:8 TensorIO -- io.RawIOBase;
#         readinto (:17) needs ...` and `nn/onnx.bend` names the same wall in
#         its own words: "Nothing in this port can read a byte out of a tensor".
#         So there is no byte source for the pickle OR for the images.
#     `imagenet_dataloader` (:25,:53)  MISSING. It is `examples/test_onnx_imagenet.py:25`
#         upstream and the port has no such file. Note that `nn/datasets.bend`
#         (469 lines) has the MNIST AND CIFAR URL TABLES and no ImageNet one:
#         `grep -c imagenet tinybendygrad/nn/datasets.bend` = 0.
#     `OnnxRunner`          (:9,:10,:15)  MISSING. STAGE 3 of `nn/onnx.bend`,
#         and STAGE 3 is "NOT DONE": nn/onnx.bend:37-38 lists
#         `OnnxRunner.__init__` :374-376 through `__call__` :441-470 as
#         unwritten, and :57-58 gives the reason -- "`OnnxRunner.__call__
#         (:441-470) -- the interpreter loop, and it dispatches into the op
#         table, so it is unreachable before the op bodies exist."
#     THE 167 ONNX OP BODIES (:15)   MISSING. STAGE 4, nn/onnx.bend:39 -- "NOT
#         DONE. The 167 op BODIES (:475-1307), the node-shape arithmetic that
#         goes with them, and the quantization family." And the PROTOBUF READER
#         they need is blocked too, nn/onnx.bend:53-58: "`PBBufferedReader`
#         (:73-119) and all of `OnnxPBParser` (:121-349). WALL: a protobuf reader
#         OVER A TENSOR".
#     `Tensor.argmax`       (:17)     MISSING. `grep -rnE "^def mo_argmax"
#         --include='*.bend' tinybendygrad/` = 0. `mixin/op.bend:11` lists
#         `argmax` inside SIDE A but no def carries it, and `rc_arg`
#         mixin/reduce.bend:208 is a REDUCTION INTERNAL, not `Tensor.argmax`.
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
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def pkl_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :7   with open(fetch(sys.argv[1]), "rb") as f:
# TWO MISSING SYMBOLS IN ONE LINE, IN THIS ORDER: `sys.argv` (no argv reader)
# and `fetch` (no def). The second is the wall that also blocks the unpickler,
# because there is no byte source either.
# ---------------------------------------------------------------------------
def pkl_open(path: String) -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:7 FIRST MISSING SYMBOL fetch -- grep -c '^def fetch(' = 0; helpers.bend:2758 symbol=lines is that file's ONLY I/O construct, so the HTTP machinery (fetch, fetch_fw, _ensure_downloads_dir) is NOT ported")

# :8   run_onnx_jit = pickle.load(f)
def pkl_load() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:8 FIRST MISSING SYMBOL pickle -- NO UNPICKLER EXISTS; helpers.bend:2758 symbol=lines is that file's ONLY I/O construct and it reads LINES, so the sqlite disk cache (whose values are pickle) is NOT ported: Bend has no pickle and no object graph")

# :9   input_name = run_onnx_jit.captured.expected_names[0]
# The RECORD EXISTS (InInfo engine/jit.bend:380 symbol=InInfo, ii_vars engine/jit.bend:387
# symbol=InInfo.vars); the object does not.
def pkl_input_name() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:9 BLOCKED ON pickle.load; engine/jit.bend:380 symbol=InInfo and engine/jit.bend:391 symbol=InInfo.dt hold expected_input_info but the object does not")

# :10  device = run_onnx_jit.captured.expected_input_info[0][-1]
def pkl_device() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:10 BLOCKED ON pickle.load; InInfo.dev engine/jit.bend:395 symbol=InInfo.dev exists but the object does not")

# :13  for i,(img,y) in enumerate(imagenet_dataloader(cnt=getenv("CNT", 100))):
# `getenv("CNT", 100)` IS PORTED -- helpers.bend:307 symbol=getenv_int `getenv_int` is the typed
# spelling of exactly this call -- and the dataloader is not.
def pkl_dataloader(cnt: U32) -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:13 FIRST MISSING SYMBOL imagenet_dataloader (examples/test_onnx_imagenet.py:25); nn/datasets.bend has no imagenet table")

# :15  p = run_onnx_jit(**{input_name: img.to(device)})
def pkl_run() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:15 BLOCKED ON OnnxRunner -- nn/onnx.bend STAGE 3 NOT DONE, and STAGE 4's 167 op bodies NOT DONE. THE PORTED HALF IS nn/onnx.bend:515 symbol=onx_dom (the STAGE 2 Domain table); THERE IS NO `OnnxRunner` DEF IN THE PORT -- IT IS ONNX.py:294 symbol=OnnxRunner.__init__ UPSTREAM")

# :17  t = p.to('cpu').argmax().item()
def pkl_predict() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:17 FIRST MISSING SYMBOL Tensor.argmax -- grep -c '^def mo_argmax' = 0; the eval loop cannot produce a prediction")

# :18  hit += y == t
def pkl_score() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:18 BLOCKED ON Tensor.item (0 non-renderer defs) and Tensor.to (mixin/movement.bend wall list)")

# ---------------------------------------------------------------------------
# :6-19 `if __name__ == "__main__":`. `main` below mirrors it and NOTHING ELSE.
# The bodies are in upstream line order, so the first refusal a caller sees is
# the FIRST missing symbol (:7 `fetch`) and not the biggest one (:8 `pickle`).
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, pkl_load())
    srow("test_pkl_imagenet_refused_at", pkl_at(a))
    row("test_pkl_imagenet_ported", False{})