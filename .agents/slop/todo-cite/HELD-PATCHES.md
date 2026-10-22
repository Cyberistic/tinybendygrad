# HELD-FILE PATCHES -- the `TODO(pN)` citations this unit could NOT re-point

Produced by `gates/todo-cite-gate.py` (the census) at the pin `5c2bf39d6c4b`. These files were HELD by other units when the fixer ran, so the
citations below are STILL FALSE in them. Every hunk is the gate's own rewrite:
the cited line becomes the line the marker's symbol is DECLARED at, or the ONE
line the marker's quoted snippet is on. Nothing else in the file changes.

Measured 2026-10-22T07:51:30+00:00.

**71 citations** in **9 files**.


## `tinybendygrad/engine/realize.bend` -- 2 citations

```diff
--- a/tinybendygrad/engine/realize.bend
+++ b/tinybendygrad/engine/realize.bend
@@ -1148,3 +1148,3 @@
 #
-# TODO(p3) realize.py:107  runtime_cache -- a module-level `dict[tuple[bytes,str],
+# TODO(p3) realize.py:105  runtime_cache -- a module-level `dict[tuple[bytes,str],
 #   Any]`. WALL: there is no `Device` to build a value for it and a Bend program
@@ -1162,3 +1162,3 @@
 #
-# TODO(p3) realize.py:116  capturing -- a module-level list of Python CLASSES
+# TODO(p3) realize.py:114  capturing -- a module-level list of Python CLASSES
 #   with an `add_linear` method, commented "put classes with an add_linear method
```


## `tinybendygrad/extra/models/convnext.bend` -- 1 citations

```diff
--- a/tinybendygrad/extra/models/convnext.bend
+++ b/tinybendygrad/extra/models/convnext.bend
@@ -46,3 +46,3 @@
 #   eps=1e-6)`. `Tensor.layernorm` does not exist. The port says so in its own
-#   words at `nn/__init__.bend:230`: "TODO(p3) mixin/op.py:1644 x.layernorm --
+#   words at `nn/__init__.bend:230`: "TODO(p3) mixin/op.py:1661 x.layernorm --
 #   SIDE B, not built", and that line is still true even though the conv2d and
```


## `tinybendygrad/extra/models/resnet.bend` -- 1 citations

```diff
--- a/tinybendygrad/extra/models/resnet.bend
+++ b/tinybendygrad/extra/models/resnet.bend
@@ -43,3 +43,3 @@
 #   :231  `TODO(p3) mixin/op.py  x.conv2d           -- SIDE B, not built.`
-#   :229  `TODO(p3) mixin/op.py:1662  x.batchnorm   -- SIDE B, not built.`
+#   :229  `TODO(p3) mixin/op.py:1678  x.batchnorm   -- SIDE B, not built.`
 # -- both are now BUILT, and that list is kept above ONLY as the record of what was true on
```


## `tinybendygrad/extra/models/vit.bend` -- 1 citations

```diff
--- a/tinybendygrad/extra/models/vit.bend
+++ b/tinybendygrad/extra/models/vit.bend
@@ -43,3 +43,3 @@
 #   `Tensor.layernorm` does not exist. `nn/__init__.bend:230` names it as an
-#   open wall -- "TODO(p3) mixin/op.py:1644 x.layernorm -- SIDE B, not built" --
+#   open wall -- "TODO(p3) mixin/op.py:1661 x.layernorm -- SIDE B, not built" --
 #   and that line is STILL TRUE even though the `x.conv2d` (:231), `x.batchnorm`
```


## `tinybendygrad/function.bend` -- 4 citations

```diff
--- a/tinybendygrad/function.bend
+++ b/tinybendygrad/function.bend
@@ -250,3 +250,3 @@
 # SECTION B -- `UOp.buf_uop` (ops.py:925). `ops.bend` carries it as
-# `# TODO(p3) ops.py:925  def buf_uop`, and it is not optional here: it is the
+# `# TODO(p3) ops.py:911  def buf_uop`, and it is not optional here: it is the
 # identity `add_to_ctx` refuses on and the value `invalid_outputs` collects. It
@@ -1072,3 +1072,3 @@
 #
-# TODO(p3) ops.py:1239  `UOp.param_like` -- `x.param_like(len(ctx[0]))`. The SLOT
+# TODO(p3) ops.py:1228  `UOp.param_like` -- `x.param_like(len(ctx[0]))`. The SLOT
 #   is answered by `fn_add` and the NODE is not built. Owner: `uop/ops.bend`, and
@@ -1077,3 +1077,3 @@
 #   in a caller.
-# TODO(p3) ops.py:532   `UOp.substitute` -- `uret.substitute(subs)` and
+# TODO(p3) ops.py:514   `UOp.substitute` -- `uret.substitute(subs)` and
 #   `uret.substitute({b: ...})`. It IS `graph_rewrite`, so it needs the matcher
@@ -1109,3 +1109,3 @@
 #   the gate does and what the seam forces.
-# TODO(p3) ops.py:925  `buf_uop`'s MSELECT and MSTACK arms -- the multi-device
+# TODO(p3) ops.py:911  `buf_uop`'s MSELECT and MSTACK arms -- the multi-device
 #   cluster (`mselect`, per-shard buffers). Neither op is reachable from a
```


## `tinybendygrad/nn/onnx.bend` -- 8 citations

```diff
--- a/tinybendygrad/nn/onnx.bend
+++ b/tinybendygrad/nn/onnx.bend
@@ -1914,5 +1914,5 @@
 #   `Tensor(pathlib.Path)` for the external-data path (:226-232).
-# TODO(p3) onnx.py:361  _to_python_const -- `t.data().tobytes()` / `t.tolist()`.
+# TODO(p3) onnx.py:282  _to_python_const -- `t.data().tobytes()` / `t.tolist()`.
 #   WALL: a host read of a realized buffer.
-# TODO(p3) onnx.py:367  OnnxRunner.__init__ / _init_from_graph / _from_subgraph /
+# TODO(p3) onnx.py:294  OnnxRunner.__init__ / _init_from_graph / _from_subgraph /
 #   _parse_input / to / _get_python_const / __call__ -- :374-470.
@@ -1927,3 +1927,3 @@
 # WALL(p3) onnx.py:601  Not / Clip / IsInf -- BLOCKED: needs x.clip (elementwise.bend:880) and x.isinf (:832) (NOT defs); x.logical_not IS ported (ew_logical_not).
-# TODO(p3) onnx.py:606  softmax_1 / softmax_13 / HardSigmoid / Gelu / BiasGelu /
+# TODO(p3) onnx.py:526  softmax_1 / softmax_13 / HardSigmoid / Gelu / BiasGelu /
 #   FastGelu / PRelu / LeakyRelu / ThresholdedRelu / LogSoftmax / Hardmax /
@@ -1933,3 +1933,3 @@
 #   BitwiseXor / BitwiseNot / Mod
-# TODO(p3) onnx.py:643  Cast / CastLike -- `OnnxDataType(to).to_dtype()` is
+# TODO(p3) onnx.py:563  Cast / CastLike -- `OnnxDataType(to).to_dtype()` is
 #   PORTED (`onx_odt_dt`), so only `x.cast` is missing.
@@ -1947,5 +1947,5 @@
 #   EmbedLayerNormalization / MeanVarianceNormalization / LpNormalization / OneHot
-# TODO(p3) onnx.py:963  DepthToSpace / SpaceToDepth -- `X.rearrange` is a REWRITE
+# TODO(p3) onnx.py:875  DepthToSpace / SpaceToDepth -- `X.rearrange` is a REWRITE
 #   of the whole index expression and has no mixin method of its own.
-# TODO(p3) onnx.py:969  dropout_7 / dropout_6 -- legacy `numpy.random.RandomState`,
+# TODO(p3) onnx.py:881  dropout_7 / dropout_6 -- legacy `numpy.random.RandomState`,
 #   which is a NUMPY seeding requirement the port cannot state.
@@ -1960,3 +1960,3 @@
 #   QLinearGlobalAveragePool / ConvInteger / MatMulInteger
-# TODO(p3) onnx.py:1265 Adagrad / Adam / Momentum -- the `@_onnx_training`
+# TODO(p3) onnx.py:1177 Adagrad / Adam / Momentum -- the `@_onnx_training`
 #   decorator (:532-540) SPLITS a variadic `*inputs` into `groups` slices and
@@ -1966,3 +1966,3 @@
 #   (`___wrapper` for all three) is PORTED and GATED.
-# TODO(p3) onnx.py:1305 Gradient -- `intermediate_tensors[y].gradient(*inputs)`.
+# TODO(p3) onnx.py:1216 Gradient -- `intermediate_tensors[y].gradient(*inputs)`.
 
```


## `tinybendygrad/renderer/wgsl.bend` -- 3 citations

```diff
--- a/tinybendygrad/renderer/wgsl.bend
+++ b/tinybendygrad/renderer/wgsl.bend
@@ -14,5 +14,5 @@
 #   TODO(p3) wgsl.py:15  packed_store -- ditto, plus `.load`/`.store`
-#   TODO(p3) wgsl.py:23  packed_load  -- ditto, plus `.index`
-#   TODO(p3) wgsl.py:34  is_nan       -- ditto (`.bitcast` and the compare)
-#   TODO(p3) wgsl.py:41  wgsl_matcher -- ditto; the seven RULES return arenas,
+#   TODO(p3) wgsl.py:24  packed_load  -- ditto, plus `.index`
+#   TODO(p3) wgsl.py:35  is_nan       -- ditto (`.bitcast` and the compare)
+#   TODO(p3) wgsl.py:42  wgsl_matcher -- ditto; the seven RULES return arenas,
 #                                  so a rule table here would have nothing to
```


## `tinybendygrad/uop/ops.bend` -- 50 citations

```diff
--- a/tinybendygrad/uop/ops.bend
+++ b/tinybendygrad/uop/ops.bend
@@ -5069,3 +5069,3 @@
 # the foot of this file, where the reason is longer.
-# TODO(p3) ops.py:74  def srender
+# TODO(p3) ops.py:76  def srender
 #   `x.render()` is render.bend's and `str(x)` is its `const_repr`. Both live in
@@ -5081,3 +5081,3 @@
 #   be stored, passed and returned, and `Maybe.map` already takes one.)
-# TODO(p3) ops.py:224  def __get__
+# TODO(p3) ops.py:216  def __get__
 #   `recursive_property` stores a FUNCTION in a record field (`self.fxn = fxn`),
@@ -5099,3 +5099,3 @@
 #   file has no process boundary to pickle across.
-# TODO(p3) ops.py:269  def key
+# TODO(p3) ops.py:261  def key
 #   `hashlib.sha256` over `str((op, dtype, arg))` and the srcs' keys concatenated.
@@ -5110,3 +5110,3 @@
 #   `frozenset[UOp]` is a deduped index list and needs no hash.
-# TODO(p3) ops.py:295  def bool_slice
+# TODO(p3) ops.py:287  def bool_slice
 #   A `recursive_property` over the srcs, gated on `self.dtype is dtypes.bool`.
@@ -5123,4 +5123,4 @@
 #   feeds. `repr(arg)` is render.bend's `arg_repr`, so this is three files deep.
-# TODO(p3) ops.py:459  def shard_shape
-# TODO(p3) ops.py:465  def max_shard_shape
+# TODO(p3) ops.py:444  def shard_shape
+# TODO(p3) ops.py:450  def max_shard_shape
 #   `shard_shape` reads `self.device` (fold), `self.axis` (fold) and `self.shape`
@@ -5134,3 +5134,3 @@
 # with a membership test, and `ended_ranges` is ported too (fold.bend:4059).
-# TODO(p3) ops.py:495  def ranges
+# TODO(p3) ops.py:479  def ranges
 #   Dict set algebra over the fold's memo: union every src's ranges, then `pop` the
@@ -5141,3 +5141,3 @@
 
-# TODO(p3) ops.py:511  def simplify
+# TODO(p3) ops.py:495  def simplify
 #   # *** uop evaluation ***
@@ -5168,15 +5168,15 @@
 #   ONE documented divergence.
-# TODO(p3) ops.py:527  def __bool__   -- DONE, same gate (`bool_true`, `bool_false`,
+# TODO(p3) ops.py:511  def __bool__   -- DONE, same gate (`bool_true`, `bool_false`,
 #   `bool_on_i32`).
-# TODO(p3) ops.py:528  def __int__    -- DONE, same gate (`int_weakint`, `int_i32`,
+# TODO(p3) ops.py:512  def __int__    -- DONE, same gate (`int_weakint`, `int_i32`,
 #   `int_on_range`).
-# TODO(p3) ops.py:529  def __float__  -- DONE, same gate (`float_weakfloat`,
+# TODO(p3) ops.py:513  def __float__  -- DONE, same gate (`float_weakfloat`,
 #   `float_on_i32`).
 
-# TODO(p3) ops.py:530  def substitute
-
-# TODO(p3) ops.py:537  def __index__
+# TODO(p3) ops.py:514  def substitute
+
+# TODO(p3) ops.py:521  def __index__
 #   # NOTE: this is not called by Tensor slice (Tensor handles UOps directly), but satisfies SupportsIndex for type checking
 
-# TODO(p3) ops.py:542  def trace_num
+# TODO(p3) ops.py:526  def trace_num
 
@@ -5212,3 +5212,3 @@
 
-# TODO(p3) ops.py:600  def const_like
+# TODO(p3) ops.py:581  def const_like
 
@@ -5220,5 +5220,5 @@
 
-# TODO(p3) ops.py:622  def ins
-
-# TODO(p3) ops.py:623  def contract
+# TODO(p3) ops.py:603  def ins
+
+# TODO(p3) ops.py:604  def contract
 
@@ -5227,7 +5227,7 @@
 
-# TODO(p3) ops.py:640  def cconst
-
-
-
-# TODO(p3) ops.py:649  def wmma
+# TODO(p3) ops.py:621  def cconst
+
+
+
+# TODO(p3) ops.py:630  def wmma
 
@@ -5235,3 +5235,3 @@
 
-# TODO(p3) ops.py:663  def invalid
+# TODO(p3) ops.py:644  def invalid
 
@@ -5256,3 +5256,3 @@
 
-# TODO(p3) ops.py:665  def get_idx
+# TODO(p3) ops.py:646  def get_idx
 
@@ -5261,3 +5261,3 @@
 
-# TODO(p3) ops.py:680  def overflows
+# TODO(p3) ops.py:661  def overflows
 #   `def overflows(self, dtype: DType) -> bool: return self.vmin < dtype.min or
@@ -5307,3 +5307,3 @@
 
-# TODO(p3) ops.py:748  def _shard
+# TODO(p3) ops.py:728  def _shard
 
@@ -5314,7 +5314,7 @@
 #   `def param_like` IS ABSENT, and `store_call`'s body is two of them:
-# TODO(p3) ops.py:766  def store_call  -- BLOCKED, and is `self.param_like(0).store(...).call(self, src)`.
+# TODO(p3) ops.py:746  def store_call  -- BLOCKED, and is `self.param_like(0).store(...).call(self, src)`.
 
 #   A DEVICE IS A `U32` TAG HERE, NOT A STRING: `type Dev is Data: D1{tag: U32}`. So a device NAME has no prefix to test, and the two below are exactly a `startswith`:
-# TODO(p3) ops.py:775  def on_disk  -- BLOCKED, and is `device.startswith("DISK")`.
-# TODO(p3) ops.py:776  def on_creation_device  -- BLOCKED, and is `device.startswith(...)`.
+# TODO(p3) ops.py:755  def on_disk  -- BLOCKED, and is `device.startswith("DISK")`.
+# TODO(p3) ops.py:756  def on_creation_device  -- BLOCKED, and is `device.startswith(...)`.
 #   # little helpers
@@ -5329,9 +5329,9 @@
 
-# TODO(p3) ops.py:850  def new_buffer
-
-# TODO(p3) ops.py:857  def from_buffer
+# TODO(p3) ops.py:835  def new_buffer
+
+# TODO(p3) ops.py:843  def from_buffer
 
 #   `def canonicalize_device` and `def is_disk_device` ARE BOTH ABSENT, and both start with one:
-# TODO(p3) ops.py:861  def empty_like  -- BLOCKED, and opens `canonicalize_device(...)`.
-# TODO(p3) ops.py:879  def clone  -- BLOCKED, and opens `canonicalize_device(...)` then tests `is_disk_device`.
+# TODO(p3) ops.py:849  def empty_like  -- BLOCKED, and opens `canonicalize_device(...)`.
+# TODO(p3) ops.py:867  def clone  -- BLOCKED, and opens `canonicalize_device(...)` then tests `is_disk_device`.
 
@@ -5354,10 +5354,10 @@
 #   `def contiguous_view` IS ABSENT, and both of these ask it first:
-# TODO(p3) ops.py:952  def contiguous_view_offset  -- BLOCKED, and is `None if (view := self.contiguous_view()) is None`.
-# TODO(p3) ops.py:968  def _buffer_view  -- BLOCKED, and raises on `self.contiguous_view() is None`.
+# TODO(p3) ops.py:941  def contiguous_view_offset  -- BLOCKED, and is `None if (view := self.contiguous_view()) is None`.
+# TODO(p3) ops.py:957  def _buffer_view  -- BLOCKED, and raises on `self.contiguous_view() is None`.
 
 # WALL(p3) -- STORAGE, DEVICE AND ALLOC. NO LIVE `Buffer` -- there is no `type Buffer is Data` anywhere in the port and ZERO `Buffer{` constructors. tinygrad's Buffer is an ALLOCATED OBJECT with a `realized` field and a `memory`
-# TODO(p3) ops.py:961  def _base_buffer_is_realized  -- BLOCKED, and walks the AFTER chain then reads `u.base.realized`.
+# TODO(p3) ops.py:950  def _base_buffer_is_realized  -- BLOCKED, and walks the AFTER chain then reads `u.base.realized`.
 # TODO(p3) ops.py:999  def realized  -- BLOCKED, and ANSWERS a Buffer.
-# TODO(p3) ops.py:1010  def is_realized  -- BLOCKED, and is `self.base.realized is not None`.
-# TODO(p3) ops.py:777  def needs_storage  -- BLOCKED, and is `not is_virtual and (storage_base.op is ALLOC or base.realized)`.
+# TODO(p3) ops.py:999  def is_realized  -- BLOCKED, and is `self.base.realized is not None`.
+# TODO(p3) ops.py:757  def needs_storage  -- BLOCKED, and is `not is_virtual and (storage_base.op is ALLOC or base.realized)`.
 
@@ -5451,3 +5451,3 @@
 
-# TODO(p3) ops.py:1060  def const_factor
+# TODO(p3) ops.py:1048  def const_factor
 #   # *** uop symbolic stuff ***
@@ -5465,9 +5465,9 @@
 
-# TODO(p3) ops.py:1085  def gcd
-
-# TODO(p3) ops.py:1091  def divide_exact
-
-# TODO(p3) ops.py:1102  def vmin
-
-# TODO(p3) ops.py:1104  def vmax
+# TODO(p3) ops.py:1073  def gcd
+
+# TODO(p3) ops.py:1079  def divide_exact
+
+# TODO(p3) ops.py:1090  def vmin
+
+# TODO(p3) ops.py:1092  def vmax
 
@@ -5484,6 +5484,6 @@
 #   `def view_as` IS ABSENT, and the alloc family ends in one:
-# TODO(p3) ops.py:1198  def alloc  -- BLOCKED, and ends `ret.view_as(shape)`.
-# TODO(p3) ops.py:1203  def alloc_like  -- BLOCKED, and delegates to `alloc`.
+# TODO(p3) ops.py:1227  def alloc  -- BLOCKED, and ends `ret.view_as(shape)`.
+# TODO(p3) ops.py:1194  def alloc_like  -- BLOCKED, and delegates to `alloc`.
 # TODO(p3) ops.py:1206  def placeholder  -- BLOCKED, and ends `view_as`.
-# TODO(p3) ops.py:1219  def placeholder_like  -- BLOCKED, and delegates to `placeholder`.
+# TODO(p3) ops.py:1208  def placeholder_like  -- BLOCKED, and delegates to `placeholder`.
 
@@ -5547,5 +5547,5 @@
 
-# TODO(p3) ops.py:1241  def param_like
-
-# TODO(p3) ops.py:1250  def view_as
+# TODO(p3) ops.py:1228  def param_like
+
+# TODO(p3) ops.py:1236  def view_as
 
@@ -5578,5 +5578,5 @@
 
-# TODO(p3) ops.py:1318  def to_elf
-
-# TODO(p3) ops.py:1331  def uopfunc
+# TODO(p3) ops.py:1312  def to_elf
+
+# TODO(p3) ops.py:1319  def uopfunc
 
@@ -8138,3 +8138,3 @@
 
-# TODO(p3) ops.py:1060  def const_factor
+# TODO(p3) ops.py:1048  def const_factor
 #   `def const_factor(self) -> int: """largest known int that divides self"""` --
@@ -8177,3 +8177,3 @@
 
-# TODO(p3) ops.py:1085  def gcd
+# TODO(p3) ops.py:1073  def gcd
 #   `zip(*[u.pop_const(Ops.MUL) for u in uops])`, a `Counter` intersection of
@@ -8182,3 +8182,3 @@
 
-# TODO(p3) ops.py:1091  def divide_exact
+# TODO(p3) ops.py:1079  def divide_exact
 #   Recurses over ADD/MUL srcs and calls `divides`, `const_like` and `__floordiv__`.
```


## `tinybendygrad/uop/render.bend` -- 1 citations

```diff
--- a/tinybendygrad/uop/render.bend
+++ b/tinybendygrad/uop/render.bend
@@ -1912,3 +1912,3 @@
 #
-# TODO(p3) render.py:6   def pretty_print
+# TODO(p3) render.py:7   def pretty_print
 # PARTIAL, AND THE GATE IS NOT LANDED, so nothing here claims to be ported.
```
