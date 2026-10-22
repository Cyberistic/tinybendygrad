# HELD-FILE PATCHES -- the `TODO(pN)` citations that are FALSE at the pin

Produced by `gates/todo-cite-gate.py --patches`. Every hunk is the gate's own
rewrite: the cited line becomes the line the marker's SYMBOL is declared at, or
the ONE line the marker's quoted snippet is on. Nothing else in the file changes.

Pin `5c2bf39d6c4b` -- tinygrad/ tree 6c91e8977790, 230 blobs match the vendored copy, 360 local-only

Measured 2026-10-22T22:46:32+00:00.

**143 citations** in **42 files**.

## `tinybendygrad/codegen/kernel.bend` -- 4 citations

```diff
--- a/tinybendygrad/codegen/kernel.bend
+++ b/tinybendygrad/codegen/kernel.bend
@@ -99 +99 @@
-# carries the `# TODO(p3) ops.py:581 def index` marker (581 is the `return`
+# carries the `# TODO(p3) ops.py:559 def index` marker (581 is the `return`
# tinybendygrad/codegen/kernel.bend:472  __init__.py:226  -- NO MECHANICAL FIX: the cited line is inside `maybe_load` (declared at :222) and the marker names no symbol this file declares
#   # `shp_same` is the reader that would answer it. `# TODO(p3) __init__.py:226
# tinybendygrad/codegen/kernel.bend:539  __init__.py:229  -- NO MECHANICAL FIX: the cited line is inside `maybe_load` (declared at :222) and the marker names no symbol this file declares
#   # ops and `ops.bend`'s `Op` is a closed enumeration. `# TODO(p3) __init__.py:229
# tinybendygrad/codegen/kernel.bend:595  __init__.py:255  -- NO MECHANICAL FIX: the cited line is inside `add_raw_barrier` (declared at :247) and the marker names no symbol this file declares
#   # `# TODO(p3) __init__.py:255  UOp.sink(...).toposort(gate=...)` -- BOTH bodies open
```

## `tinybendygrad/codegen/late/.linearizer-mut.bend` -- 1 citations

```diff
--- a/tinybendygrad/codegen/late/.linearizer-mut.bend
+++ b/tinybendygrad/codegen/late/.linearizer-mut.bend
# tinybendygrad/codegen/late/.linearizer-mut.bend:402  linearizer.py:50  -- NO MECHANICAL FIX: the cited line is inside `linearize` (declared at :8) and the marker names no symbol this file declares
#   # `# TODO(p3) linearizer.py:50  the DEBUG_LINEARIZE print reads `extra` -- the one
```

## `tinybendygrad/codegen/late/linearizer.bend` -- 1 citations

```diff
--- a/tinybendygrad/codegen/late/linearizer.bend
+++ b/tinybendygrad/codegen/late/linearizer.bend
# tinybendygrad/codegen/late/linearizer.bend:402  linearizer.py:50  -- NO MECHANICAL FIX: the cited line is inside `linearize` (declared at :8) and the marker names no symbol this file declares
#   # `# TODO(p3) linearizer.py:50  the DEBUG_LINEARIZE print reads `extra` -- the one
```

## `tinybendygrad/codegen/opt/search.bend` -- 3 citations

```diff
--- a/tinybendygrad/codegen/opt/search.bend
+++ b/tinybendygrad/codegen/opt/search.bend
# tinybendygrad/codegen/opt/search.bend:154  search.py:138  -- NO MECHANICAL FIX: the cited line is inside `beam_search` (declared at :105) and the marker names no symbol this file declares
#   # TODO(p3) search.py:138-141 the 1000x compute filter
# tinybendygrad/codegen/opt/search.bend:171  search.py:108  -- NO MECHANICAL FIX: the cited line is inside `beam_search` (declared at :105) and the marker names no symbol this file declares
#   # TODO(p3) search.py:108-111 `diskcache_get`/`diskcache_put` -- a persistent
# tinybendygrad/codegen/opt/search.bend:174  search.py:116  -- NO MECHANICAL FIX: the cited line is inside `beam_search` (declared at :105) and the marker names no symbol this file declares
#   # TODO(p3) search.py:116-122 `get_worker_pool` / `terminate_worker_pool` --
```

## `tinybendygrad/device.bend` -- 1 citations

```diff
--- a/tinybendygrad/device.bend
+++ b/tinybendygrad/device.bend
# tinybendygrad/device.bend:483  device.py:23  -- NO MECHANICAL FIX: the cited line does not hold the claim and no symbol in the marker is declared in `device.py`
#   # TODO(p3) device.py:23  _Device._devices -- `pathlib.Path(...).iterdir()`.
```

## `tinybendygrad/engine/realize.bend` -- 1 citations

```diff
--- a/tinybendygrad/engine/realize.bend
+++ b/tinybendygrad/engine/realize.bend
@@ -1163 +1163 @@
-# TODO(p3) realize.py:116  capturing -- a module-level list of Python CLASSES
+# TODO(p3) realize.py:114  capturing -- a module-level list of Python CLASSES
```

## `tinybendygrad/extra/models/convnext.bend` -- 1 citations

```diff
--- a/tinybendygrad/extra/models/convnext.bend
+++ b/tinybendygrad/extra/models/convnext.bend
@@ -47 +47 @@
-#   words at `nn/__init__.bend:230`: "TODO(p3) mixin/op.py:1644 x.layernorm --
+#   words at `nn/__init__.bend:230`: "TODO(p3) mixin/op.py:1661 x.layernorm --
```

## `tinybendygrad/extra/models/resnet.bend` -- 1 citations

```diff
--- a/tinybendygrad/extra/models/resnet.bend
+++ b/tinybendygrad/extra/models/resnet.bend
@@ -44 +44 @@
-#   :229  `TODO(p3) mixin/op.py:1662  x.batchnorm   -- SIDE B, not built.`
+#   :229  `TODO(p3) mixin/op.py:1678  x.batchnorm   -- SIDE B, not built.`
```

## `tinybendygrad/extra/models/vit.bend` -- 1 citations

```diff
--- a/tinybendygrad/extra/models/vit.bend
+++ b/tinybendygrad/extra/models/vit.bend
@@ -44 +44 @@
-#   open wall -- "TODO(p3) mixin/op.py:1644 x.layernorm -- SIDE B, not built" --
+#   open wall -- "TODO(p3) mixin/op.py:1661 x.layernorm -- SIDE B, not built" --
```

## `tinybendygrad/function.bend` -- 4 citations

```diff
--- a/tinybendygrad/function.bend
+++ b/tinybendygrad/function.bend
@@ -251 +251 @@
-# `# TODO(p3) ops.py:925  def buf_uop`, and it is not optional here: it is the
+# `# TODO(p3) ops.py:911  def buf_uop`, and it is not optional here: it is the
@@ -1073 +1073 @@
-# TODO(p3) ops.py:1239  `UOp.param_like` -- `x.param_like(len(ctx[0]))`. The SLOT
+# TODO(p3) ops.py:1228  `UOp.param_like` -- `x.param_like(len(ctx[0]))`. The SLOT
@@ -1078 +1078 @@
-# TODO(p3) ops.py:532   `UOp.substitute` -- `uret.substitute(subs)` and
+# TODO(p3) ops.py:514   `UOp.substitute` -- `uret.substitute(subs)` and
@@ -1110 +1110 @@
-# TODO(p3) ops.py:925  `buf_uop`'s MSELECT and MSTACK arms -- the multi-device
+# TODO(p3) ops.py:911  `buf_uop`'s MSELECT and MSTACK arms -- the multi-device
```

## `tinybendygrad/mixin/creation.bend` -- 1 citations

```diff
--- a/tinybendygrad/mixin/creation.bend
+++ b/tinybendygrad/mixin/creation.bend
# tinybendygrad/mixin/creation.bend:93  dtype.py:84  -- NO MECHANICAL FIX: the cited line is inside `float` (declared at :79) and the marker names no symbol this file declares
#   #      TODO(p3) dtype.py:84  `DType.const`'s `truncate` -- THE INT ARM ONLY. THE FLOAT
```

## `tinybendygrad/mixin/elementwise.bend` -- 2 citations

```diff
--- a/tinybendygrad/mixin/elementwise.bend
+++ b/tinybendygrad/mixin/elementwise.bend
@@ -837 +837 @@
-# TODO(p3) elementwise.py:840  log  -- math.log(2) is `ew_k.log2()`, bit-exact. nothing else was named; UNDIAGNOSED
+# TODO(p3) elementwise.py:828  log  -- math.log(2) is `ew_k.log2()`, bit-exact. nothing else was named; UNDIAGNOSED
@@ -838 +838 @@
-# TODO(p3) elementwise.py:852  log10  -- math.log10(2) is `ew_k.log10_2()` = 0.30103, bit-exact -- NOT 0.30102999, which is one ulp low
+# TODO(p3) elementwise.py:840  log10  -- math.log10(2) is `ew_k.log10_2()` = 0.30103, bit-exact -- NOT 0.30102999, which is one ulp low
```

## `tinybendygrad/mixin/gradient.bend` -- 7 citations

```diff
--- a/tinybendygrad/mixin/gradient.bend
+++ b/tinybendygrad/mixin/gradient.bend
# tinybendygrad/mixin/gradient.bend:615  mixin/gradient.py:83  -- NO MECHANICAL FIX: the cited line is inside `partial_store_gradient` (declared at :52) and the marker names no symbol this file declares
#   # TODO(p3) mixin/gradient.py:83  ctx.contiguous -- needs `has_buffer_identity`
# tinybendygrad/mixin/gradient.bend:699  mixin/gradient.py:92  -- NO MECHANICAL FIX: the cited line is inside `partial_store_gradient` (declared at :52) and the marker names no symbol this file declares
#   # TODO(p3) mixin/gradient.py:92  COPY -- `copy_to_device` (ops.py:761) needs a device
# tinybendygrad/mixin/gradient.bend:711  mixin/gradient.py:93  -- NO MECHANICAL FIX: the cited line is inside `partial_store_gradient` (declared at :52) and the marker names no symbol this file declares
#   # TODO(p3) mixin/gradient.py:93  UNSHARD -- `_shard` (ops.py:751) reads `int(rng.vmax)`,
# tinybendygrad/mixin/gradient.bend:744  mixin/gradient.py:98  -- NO MECHANICAL FIX: the cited line is inside `partial_store_gradient` (declared at :52) and the marker names no symbol this file declares
#   # TODO(p3) mixin/gradient.py:98  ordering-only AFTER -- `buf_uop` (ops.py:925) walks
@@ -813 +813 @@
-# TODO(p3) mixin/gradient.py:102  partial_store_gradient -- the body RE-ENTERS
+# TODO(p3) mixin/gradient.py:52  partial_store_gradient -- the body RE-ENTERS
@@ -897 +897 @@
-# TODO(p3) mixin/gradient.py:102  partial_store_gradient -- the body calls
+# TODO(p3) mixin/gradient.py:52  partial_store_gradient -- the body calls
# tinybendygrad/mixin/gradient.bend:1082  mixin/gradient.py:132  -- NO MECHANICAL FIX: the cited line is inside `compute_gradient` (declared at :114) and the marker names no symbol this file declares
#   # file (see the `TODO(p3) mixin/gradient.py:132` note below, which is RETAINED):
```

## `tinybendygrad/mixin/op.bend` -- 1 citations

```diff
--- a/tinybendygrad/mixin/op.bend
+++ b/tinybendygrad/mixin/op.bend
# tinybendygrad/mixin/op.bend:292  mixin/op.py:62  -- NO MECHANICAL FIX: the cited line is inside `__getitem__` (declared at :34) and the marker names no symbol this file declares
#   # TODO(p3) mixin/op.py:62  self.shape[k] for a SYMBOLIC dim -- `O.SU` needs
```

## `tinybendygrad/mixin/rand.bend` -- 1 citations

```diff
--- a/tinybendygrad/mixin/rand.bend
+++ b/tinybendygrad/mixin/rand.bend
# tinybendygrad/mixin/rand.bend:11  examples/beautiful_mnist.py:25  -- NO MECHANICAL FIX: `examples/beautiful_mnist.py` names no upstream file at the pin (absent)
#   # `examples/beautiful_mnist.bend:78` records `TODO(p3) examples/beautiful_mnist.py:25` for
```

## `tinybendygrad/nn/__init__.bend` -- 2 citations

```diff
--- a/tinybendygrad/nn/__init__.bend
+++ b/tinybendygrad/nn/__init__.bend
# tinybendygrad/nn/__init__.bend:223  mixin/rand.py:190  -- NO MECHANICAL FIX: the cited line is inside `scaled_uniform` (declared at :176) and the marker names no symbol this file declares
#   # TODO(p3) mixin/rand.py:190  Tensor.uniform / Tensor.glorot_uniform -- `creation.py`'s
# tinybendygrad/nn/__init__.bend:237  mixin/reduce.py:20  -- NO MECHANICAL FIX: the cited line is inside `_reduce` (declared at :13) and the marker names no symbol this file declares
#   # TODO(p3) mixin/reduce.py:20 x.mean / x.sum    -- `mo_sum`/`mo_mean` EXIST in
```

## `tinybendygrad/nn/datasets.bend` -- 5 citations

```diff
--- a/tinybendygrad/nn/datasets.bend
+++ b/tinybendygrad/nn/datasets.bend
# tinybendygrad/nn/datasets.bend:81  nn/datasets.py:6  -- NO MECHANICAL FIX: the cited line is inside `mnist` (declared at :4) and the marker names no symbol this file declares
#   #    TODO(p3) nn/datasets.py:6   -- Tensor.from_url(..., gunzip=True).
# tinybendygrad/nn/datasets.bend:82  nn/datasets.py:11  -- NO MECHANICAL FIX: the cited line is inside `cifar` (declared at :10) and the marker names no symbol this file declares
#   #    TODO(p3) nn/datasets.py:11  -- the cifar tarball, and tar_extract with it.
# tinybendygrad/nn/datasets.bend:86  nn/datasets.py:12  -- NO MECHANICAL FIX: the cited line is inside `cifar` (declared at :10) and the marker names no symbol this file declares
#   #    TODO(p3) nn/datasets.py:12  -- tt["cifar-10-batches-bin/data_batch_i.bin"].
# tinybendygrad/nn/datasets.bend:93  nn/datasets.py:7  -- NO MECHANICAL FIX: the cited line is inside `_mnist` (declared at :6) and the marker names no symbol this file declares
#   #    TODO(p3) nn/datasets.py:7   -- reshape(-1,1,28,28).to(device).
# tinybendygrad/nn/datasets.bend:94  nn/datasets.py:14  -- NO MECHANICAL FIX: the cited line is inside `cifar` (declared at :10) and the marker names no symbol this file declares
#   #    TODO(p3) nn/datasets.py:14  -- train[:, 1:] and train[:, 0].
```

## `tinybendygrad/nn/onnx.bend` -- 8 citations

```diff
--- a/tinybendygrad/nn/onnx.bend
+++ b/tinybendygrad/nn/onnx.bend
@@ -1915 +1915 @@
-# TODO(p3) onnx.py:361  _to_python_const -- `t.data().tobytes()` / `t.tolist()`.
+# TODO(p3) onnx.py:281  _to_python_const -- `t.data().tobytes()` / `t.tolist()`.
@@ -1917 +1917 @@
-# TODO(p3) onnx.py:367  OnnxRunner.__init__ / _init_from_graph / _from_subgraph /
+# TODO(p3) onnx.py:294  OnnxRunner.__init__ / _init_from_graph / _from_subgraph /
@@ -1928 +1928 @@
-# TODO(p3) onnx.py:606  softmax_1 / softmax_13 / HardSigmoid / Gelu / BiasGelu /
+# TODO(p3) onnx.py:526  softmax_1 / softmax_13 / HardSigmoid / Gelu / BiasGelu /
@@ -1934 +1934 @@
-# TODO(p3) onnx.py:643  Cast / CastLike -- `OnnxDataType(to).to_dtype()` is
+# TODO(p3) onnx.py:563  Cast / CastLike -- `OnnxDataType(to).to_dtype()` is
@@ -1948 +1948 @@
-# TODO(p3) onnx.py:963  DepthToSpace / SpaceToDepth -- `X.rearrange` is a REWRITE
+# TODO(p3) onnx.py:875  DepthToSpace / SpaceToDepth -- `X.rearrange` is a REWRITE
@@ -1950 +1950 @@
-# TODO(p3) onnx.py:969  dropout_7 / dropout_6 -- legacy `numpy.random.RandomState`,
+# TODO(p3) onnx.py:881  dropout_7 / dropout_6 -- legacy `numpy.random.RandomState`,
@@ -1961 +1961 @@
-# TODO(p3) onnx.py:1265 Adagrad / Adam / Momentum -- the `@_onnx_training`
+# TODO(p3) onnx.py:1177 Adagrad / Adam / Momentum -- the `@_onnx_training`
@@ -1967 +1967 @@
-# TODO(p3) onnx.py:1305 Gradient -- `intermediate_tensors[y].gradient(*inputs)`.
+# TODO(p3) onnx.py:1216 Gradient -- `intermediate_tensors[y].gradient(*inputs)`.
```

## `tinybendygrad/nn/state.bend` -- 1 citations

```diff
--- a/tinybendygrad/nn/state.bend
+++ b/tinybendygrad/nn/state.bend
@@ -498 +498 @@
-# TODO(p3) state.py:8   TensorIO        -- `io.RawIOBase`; `readinto` (:17) needs
+# TODO(p3) state.py:8   TensorIO        -- `io.RawIOBase`; `readinto` (:17) needs
```

## `tinybendygrad/nn/torch.bend` -- 1 citations

```diff
--- a/tinybendygrad/nn/torch.bend
+++ b/tinybendygrad/nn/torch.bend
# tinybendygrad/nn/torch.bend:69  nn/torch.py:4  -- NO MECHANICAL FIX: the cited line does not hold the claim and no symbol in the marker is declared in `nn/torch.py`
#   #    TODO(p3) nn/torch.py:4  the import -- `sys.modules` and the module search.
```

## `tinybendygrad/renderer/__init__.bend` -- 8 citations

```diff
--- a/tinybendygrad/renderer/__init__.bend
+++ b/tinybendygrad/renderer/__init__.bend
# tinybendygrad/renderer/__init__.bend:70  ops.py:1886  -- NO MECHANICAL FIX: the cited line is inside `label` (declared at :1878) and the marker names no symbol this file declares
#   #     SYMBOLIC `vmax` -- a WALL (`TODO(p3) ops.py:1886` in the port, at
# tinybendygrad/renderer/__init__.bend:176  ops.py:513  -- NO MECHANICAL FIX: the cited line is inside `__int__` (declared at :512) and the marker names no symbol this file declares
#   # `mults` (`UOp.simplify` is `# TODO(p3) ops.py:513`; the `vmax` under
# tinybendygrad/renderer/__init__.bend:177  ops.py:1886  -- NO MECHANICAL FIX: the cited line is inside `label` (declared at :1878) and the marker names no symbol this file declares
#   # `to_max_shape` is `# TODO(p3) ops.py:1886`) is unreachable from that call site,
# tinybendygrad/renderer/__init__.bend:394  __init__.py:26  -- NO MECHANICAL FIX: the cited line is inside `simplify` (declared at :24) and the marker names no symbol this file declares
#   #   substrate. `TODO(p3) __init__.py:26`.
# tinybendygrad/renderer/__init__.bend:408  __init__.py:83  -- NO MECHANICAL FIX: the cited line is inside `__reduce__` (declared at :82) and the marker names no symbol this file declares
#   #   answer and nothing else can be true of it. `TODO(p3) __init__.py:83`, `:84`.
# tinybendygrad/renderer/__init__.bend:408  __init__.py:84  -- NO MECHANICAL FIX: the cited line is inside `render` (declared at :83) and the marker names no symbol this file declares
#   #   answer and nothing else can be true of it. `TODO(p3) __init__.py:83`, `:84`.
# tinybendygrad/renderer/__init__.bend:413  __init__.py:77  -- NO MECHANICAL FIX: the cited line is inside `Renderer` (declared at :63) and the marker names no symbol this file declares
#   #   `match` is `cstyle.bend`'s `code_for_op.of`. `TODO(p3) __init__.py:77`.
# tinybendygrad/renderer/__init__.bend:415  __init__.py:75  -- NO MECHANICAL FIX: the cited line is inside `Renderer` (declared at :63) and the marker names no symbol this file declares
#   #   which is not this unit's file and has no port. `TODO(p3) __init__.py:75`.
```

## `tinybendygrad/renderer/amd/elf.bend` -- 1 citations

```diff
--- a/tinybendygrad/renderer/amd/elf.bend
+++ b/tinybendygrad/renderer/amd/elf.bend
# tinybendygrad/renderer/amd/elf.bend:45  elf.py:16  -- NO MECHANICAL FIX: the cited line is inside `assemble_linear` (declared at :15) and the marker names no symbol this file declares
#   # TODO(p3) elf.py:16,38-42,43,103-109  the four blockers above.
```

## `tinybendygrad/renderer/cstyle.bend` -- 5 citations

```diff
--- a/tinybendygrad/renderer/cstyle.bend
+++ b/tinybendygrad/renderer/cstyle.bend
# tinybendygrad/renderer/cstyle.bend:60  ops.py:1886  -- NO MECHANICAL FIX: the cited line is inside `label` (declared at :1878) and the marker names no symbol this file declares
#   #       SYMBOLIC `vmax` (`TODO(p3) ops.py:1886`). `max_numel` below is the
# tinybendygrad/renderer/cstyle.bend:1351  ops.py:1886  -- NO MECHANICAL FIX: the cited line is inside `label` (declared at :1878) and the marker names no symbol this file declares
#   #     `TODO(p3) ops.py:1886` wall again. It is a `U32` PARAMETER here, and the
# tinybendygrad/renderer/cstyle.bend:1363  ops.py:1886  -- NO MECHANICAL FIX: the cited line is inside `label` (declared at :1878) and the marker names no symbol this file declares
#   # the SYMBOLIC maximum that is `TODO(p3) ops.py:1886`. The SPECIAL filter itself
# tinybendygrad/renderer/cstyle.bend:1367  cstyle.py:157  -- NO MECHANICAL FIX: the cited line is inside `render_kernel` (declared at :155) and the marker names no symbol this file declares
#   #   TODO(p3) cstyle.py:157, :160 -- BLOCKED. needs `local_dims` and `launch_bounds` -- two kernel-shape helpers: MEASURED, both NO DEF under `cstyle.b
# tinybendygrad/renderer/cstyle.bend:1367  cstyle.py:160  -- NO MECHANICAL FIX: the cited line is inside `render_kernel` (declared at :155) and the marker names no symbol this file declares
#   #   TODO(p3) cstyle.py:157, :160 -- BLOCKED. needs `local_dims` and `launch_bounds` -- two kernel-shape helpers: MEASURED, both NO DEF under `cstyle.b
```

## `tinybendygrad/renderer/isa/x86.bend` -- 20 citations

```diff
--- a/tinybendygrad/renderer/isa/x86.bend
+++ b/tinybendygrad/renderer/isa/x86.bend
# tinybendygrad/renderer/isa/x86.bend:66  x86.py:761  -- NO MECHANICAL FIX: the cited line is inside `render` (declared at :760) and the marker names no symbol this file declares
#   #     NOT PORTED). `TODO(p3) x86.py:761`.
# tinybendygrad/renderer/isa/x86.bend:89  x86.py:90  -- NO MECHANICAL FIX: the cited line is inside `X86GroupOp` (declared at :56) and the marker names no symbol this file declares
#   #   different program. `TODO(p3) x86.py:90`.
# tinybendygrad/renderer/isa/x86.bend:91  x86.py:156  -- NO MECHANICAL FIX: the cited line is inside `flag_gate` (declared at :152) and the marker names no symbol this file declares
#   # * `pre_isel_matcher` (py:156-168, 13 lines) -- same wall. `TODO(p3) x86.py:156`.
# tinybendygrad/renderer/isa/x86.bend:94  x86.py:312  -- NO MECHANICAL FIX: the cited line is inside `copy_op` (declared at :309) and the marker names no symbol this file declares
#   #   `TODO(p3) x86.py:312`.
# tinybendygrad/renderer/isa/x86.bend:100  x86.py:458  -- NO MECHANICAL FIX: the cited line is inside `flag_rematerialize` (declared at :456) and the marker names no symbol this file declares
#   #   is a `Ref`-per-field context record. `TODO(p3) x86.py:458`, `:466`, `:478`,
# tinybendygrad/renderer/isa/x86.bend:100  x86.py:466  -- NO MECHANICAL FIX: the cited line is inside `alloc_buffer` (declared at :464) and the marker names no symbol this file declares
#   #   is a `Ref`-per-field context record. `TODO(p3) x86.py:458`, `:466`, `:478`,
# tinybendygrad/renderer/isa/x86.bend:100  x86.py:478  -- NO MECHANICAL FIX: the cited line is inside `lower_range` (declared at :476) and the marker names no symbol this file declares
#   #   is a `Ref`-per-field context record. `TODO(p3) x86.py:458`, `:466`, `:478`,
# tinybendygrad/renderer/isa/x86.bend:105  x86.py:126  -- NO MECHANICAL FIX: the cited line is inside `is_regbuf` (declared at :90) and the marker names no symbol this file declares
#   #   `TODO(p3) x86.py:126`.
# tinybendygrad/renderer/isa/x86.bend:110  x86.py:137  -- NO MECHANICAL FIX: the cited line is inside `scratch_buffer` (declared at :135) and the marker names no symbol this file declares
#   #   `TODO(p3) x86.py:137`, `:144`.
# tinybendygrad/renderer/isa/x86.bend:110  x86.py:144  -- NO MECHANICAL FIX: the cited line is inside `gated_load` (declared at :137) and the marker names no symbol this file declares
#   #   `TODO(p3) x86.py:137`, `:144`.
# tinybendygrad/renderer/isa/x86.bend:116  x86.py:152  -- NO MECHANICAL FIX: the cited line is inside `gated_store` (declared at :144) and the marker names no symbol this file declares
#   #   1502 records three such defs in `schedule/indexing.bend`). `TODO(p3) x86.py:152`.
# tinybendygrad/renderer/isa/x86.bend:120  x86.py:162  -- NO MECHANICAL FIX: the cited line is inside `flag_gate` (declared at :152) and the marker names no symbol this file declares
#   #   register it wraps is ported. `TODO(p3) x86.py:162`.
# tinybendygrad/renderer/isa/x86.bend:141  x86.py:200  -- NO MECHANICAL FIX: the cited line is inside `to_int` (declared at :199) and the marker names no symbol this file declares
#   #   differ only in the tag. `TODO(p3) x86.py:200`.
# tinybendygrad/renderer/isa/x86.bend:147  x86.py:219  -- NO MECHANICAL FIX: the cited line is inside `mask` (declared at :212) and the marker names no symbol this file declares
#   #   `TODO(p3) x86.py:219`.
# tinybendygrad/renderer/isa/x86.bend:157  x86.py:293  -- NO MECHANICAL FIX: the cited line is inside `_xmm_sz_m` (declared at :287) and the marker names no symbol this file declares
#   #   MINTS a `Register` with `itertools.count()`. `TODO(p3) x86.py:293`.
# tinybendygrad/renderer/isa/x86.bend:159  x86.py:689  -- NO MECHANICAL FIX: the cited line is inside `insert_linearized` (declared at :688) and the marker names no symbol this file declares
#   #   `lock` / `stack_allocated` / `stack_size` state above. `TODO(p3) x86.py:689`.
# tinybendygrad/renderer/isa/x86.bend:163  x86.py:720  -- NO MECHANICAL FIX: the cited line is inside `X86Renderer` (declared at :709) and the marker names no symbol this file declares
#   #   PROCESS SPAWN. FFI. `TODO(p3) x86.py:720`.
# tinybendygrad/renderer/isa/x86.bend:169  x86.py:728  -- NO MECHANICAL FIX: the cited line is inside `copy` (declared at :726) and the marker names no symbol this file declares
#   #   class the gate ports. The node build is not. `TODO(p3) x86.py:728`.
# tinybendygrad/renderer/isa/x86.bend:172  x86.py:761  -- NO MECHANICAL FIX: the cited line is inside `render` (declared at :760) and the marker names no symbol this file declares
#   #   change. `TODO(p3) x86.py:761`.
# tinybendygrad/renderer/isa/x86.bend:1585  x86.py:752  -- NO MECHANICAL FIX: the cited line is inside `_mem_adress` (declared at :743) and the marker names no symbol this file declares
#   # `TODO(p3) x86.py:752`.
```

## `tinybendygrad/renderer/nir.bend` -- 7 citations

```diff
--- a/tinybendygrad/renderer/nir.bend
+++ b/tinybendygrad/renderer/nir.bend
# tinybendygrad/renderer/nir.bend:1660  nir.py:50  -- NO MECHANICAL FIX: the cited line is inside `go` (declared at :45) and the marker names no symbol this file declares
#   #   ABSENT on this tree (mesa.py:989). `TODO(p3) nir.py:50`.
# tinybendygrad/renderer/nir.bend:1667  nir.py:121  -- NO MECHANICAL FIX: the cited line is inside `NIRRenderer` (declared at :115) and the marker names no symbol this file declares
#   #   `TODO(p3) nir.py:121`, `:145`, `:290`.
# tinybendygrad/renderer/nir.bend:1667  nir.py:145  -- NO MECHANICAL FIX: the cited line is inside `NIRRenderer` (declared at :115) and the marker names no symbol this file declares
#   #   `TODO(p3) nir.py:121`, `:145`, `:290`.
# tinybendygrad/renderer/nir.bend:1667  nir.py:290  -- NO MECHANICAL FIX: the cited line is inside `nload_img` (declared at :286) and the marker names no symbol this file declares
#   #   `TODO(p3) nir.py:121`, `:145`, `:290`.
# tinybendygrad/renderer/nir.bend:1672  nir.py:169  -- NO MECHANICAL FIX: the cited line is inside `NIRRenderer` (declared at :115) and the marker names no symbol this file declares
#   #   diff. `TODO(p3) nir.py:169`.
# tinybendygrad/renderer/nir.bend:1679  nir.py:69  -- NO MECHANICAL FIX: the cited line is inside `nchannel` (declared at :62) and the marker names no symbol this file declares
#   #   `renderer/__init__.bend`'s convention 11 note). `TODO(p3) nir.py:69`.
# tinybendygrad/renderer/nir.bend:1689  nir.py:312  -- NO MECHANICAL FIX: the cited line is inside `prerender` (declared at :305) and the marker names no symbol this file declares
#   #   over `itertools.count`. `TODO(p3) nir.py:312`.
```

## `tinybendygrad/renderer/ptx.bend` -- 1 citations

```diff
--- a/tinybendygrad/renderer/ptx.bend
+++ b/tinybendygrad/renderer/ptx.bend
# tinybendygrad/renderer/ptx.bend:28  ptx.py:42  -- NO MECHANICAL FIX: the cited line is inside `render_val` (declared at :11) and the marker names no symbol this file declares
#   #     `TODO(p3) ptx.py:42`-`56` block.
```

## `tinybendygrad/renderer/tc_ptx.bend` -- 2 citations

```diff
--- a/tinybendygrad/renderer/tc_ptx.bend
+++ b/tinybendygrad/renderer/tc_ptx.bend
# tinybendygrad/renderer/tc_ptx.bend:75  ptx.py:145  -- NO MECHANICAL FIX: the cited line is inside `__init__` (declared at :142) and the marker names no symbol this file declares
#   #   TODO(p3) ptx.py:145  self.compiler -- NVPTXCompiler / PTXCompiler
# tinybendygrad/renderer/tc_ptx.bend:92  ptx.py:145  -- NO MECHANICAL FIX: the cited line is inside `__init__` (declared at :142) and the marker names no symbol this file declares
#   #   TODO(p3) ptx.py:145  self.compiler -- NVPTXCompiler / PTXCompiler
```

## `tinybendygrad/runtime/ops_metal.bend` -- 3 citations

```diff
--- a/tinybendygrad/runtime/ops_metal.bend
+++ b/tinybendygrad/runtime/ops_metal.bend
# tinybendygrad/runtime/ops_metal.bend:188  runtime/ops_metal.py:41  -- NO MECHANICAL FIX: the cited line is inside `__init__` (declared at :38) and the marker names no symbol this file declares
#   #    TODO(p3) runtime/ops_metal.py:41  -- `__reduce__`.
# tinybendygrad/runtime/ops_metal.bend:201  runtime/ops_metal.py:190  -- NO MECHANICAL FIX: the cited line is inside `_offset` (declared at :183) and the marker names no symbol this file declares
#   #    TODO(p3) runtime/ops_metal.py:190  -- `encode_submit(MetalQueue(submit))`.
# tinybendygrad/runtime/ops_metal.bend:202  runtime/ops_metal.py:193  -- NO MECHANICAL FIX: the cited line is inside `_offset` (declared at :183) and the marker names no symbol this file declares
#   #    TODO(p3) runtime/ops_metal.py:193  -- `mtl_poll(tl) if …timeline…`.
```

## `tinybendygrad/runtime/ops_npy.bend` -- 1 citations

```diff
--- a/tinybendygrad/runtime/ops_npy.bend
+++ b/tinybendygrad/runtime/ops_npy.bend
@@ -88 +88 @@
-#    TODO(p3) helpers.py:573  to_mv -- `memoryview((ctypes.c_uint8*sz).from_address(ptr))`.
+#    TODO(p3) helpers.py:575  to_mv -- `memoryview((ctypes.c_uint8*sz).from_address(ptr))`.
```

## `tinybendygrad/runtime/support/compiler_amd.bend` -- 1 citations

```diff
--- a/tinybendygrad/runtime/support/compiler_amd.bend
+++ b/tinybendygrad/runtime/support/compiler_amd.bend
@@ -114 +114 @@
-#   TODO(p3) compiler_amd.py:21-23 -- the two `amd_comgr_get_data` calls.
+#   TODO(p3) compiler_amd.py:35-37 -- the two `amd_comgr_get_data` calls.
```

## `tinybendygrad/runtime/support/compiler_cuda.bend` -- 1 citations

```diff
--- a/tinybendygrad/runtime/support/compiler_cuda.bend
+++ b/tinybendygrad/runtime/support/compiler_cuda.bend
@@ -115 +115 @@
-#   TODO(p3) compiler_cuda.py:28-35 -- `re.sub` x6.
+#   TODO(p3) compiler_cuda.py:55-62 -- `re.sub` x6.
```

## `tinybendygrad/runtime/support/compiler_llvm.bend` -- 1 citations

```diff
--- a/tinybendygrad/runtime/support/compiler_llvm.bend
+++ b/tinybendygrad/runtime/support/compiler_llvm.bend
@@ -80 +80 @@
-#   TODO(p3) compiler_llvm.py:4  -- `from tinygrad.runtime.autogen import llvm`.
+#   TODO(p3) compiler_llvm.py:13  -- `from tinygrad.runtime.autogen import llvm`.
```

## `tinybendygrad/runtime/support/compiler_mesa.bend` -- 5 citations

```diff
--- a/tinybendygrad/runtime/support/compiler_mesa.bend
+++ b/tinybendygrad/runtime/support/compiler_mesa.bend
@@ -77 +77 @@
-#   TODO(p3) compiler_mesa.py:59-60 -- `nak_compiler_create` / `nak_nir_options`.
+#   TODO(p3) compiler_mesa.py:67-68 -- `nak_compiler_create` / `nak_nir_options`.
@@ -85 +85 @@
-#   TODO(p3) compiler_mesa.py:131  -- `v.imm_state.count` (same).
+#   TODO(p3) compiler_mesa.py:111  -- `v.imm_state.count` (same).
@@ -86 +86 @@
-#   TODO(p3) compiler_mesa.py:133  -- `self.dev_id.gpu_id` (same).
+#   TODO(p3) compiler_mesa.py:111  -- `self.dev_id.gpu_id` (same).
@@ -97 +97 @@
-#   TODO(p3) compiler_mesa.py:16 -- `base64.b64decode`.
+#   TODO(p3) compiler_mesa.py:22 -- `base64.b64decode`.
@@ -99 +99 @@
-#   TODO(p3) compiler_mesa.py:78 -- `f.write(lib[sizeof(struct_nak_shader_info):])`.
+#   TODO(p3) compiler_mesa.py:67 -- `f.write(lib[sizeof(struct_nak_shader_info):])`.
```

## `tinybendygrad/runtime/support/objc.bend` -- 1 citations

```diff
--- a/tinybendygrad/runtime/support/objc.bend
+++ b/tinybendygrad/runtime/support/objc.bend
@@ -89 +89 @@
-#     TODO(p3) runtime/support/objc.py:71 -- `classmethod(...)` wrapping.
+#     TODO(p3) runtime/support/objc.py:13 -- `classmethod(...)` wrapping.
```

## `tinybendygrad/runtime/support/system.bend` -- 1 citations

```diff
--- a/tinybendygrad/runtime/support/system.bend
+++ b/tinybendygrad/runtime/support/system.bend
@@ -89 +89 @@
-#    TODO(p3) runtime/support/system.py:58  -- `os.system(cmd)`.
+#    TODO(p3) runtime/support/system.py:137  -- `os.system(cmd)`.
```

## `tinybendygrad/schedule/__init__.bend` -- 10 citations

```diff
--- a/tinybendygrad/schedule/__init__.bend
+++ b/tinybendygrad/schedule/__init__.bend
# tinybendygrad/schedule/__init__.bend:1514  __init__.py:167  -- NO MECHANICAL FIX: the cited line is inside `simplify_copy_kernel` (declared at :161) and the marker names no symbol this file declares
#   #   TODO(p3) __init__.py:167  the four-matcher rewrite -- THE WALL.
# tinybendygrad/schedule/__init__.bend:1549  __init__.py:155  -- NO MECHANICAL FIX: the cited line is inside `assert_all_same_devices` (declared at :153) and the marker names no symbol this file declares
#   #   TODO(p3) __init__.py:155  the RuntimeError -- a raise.
# tinybendygrad/schedule/__init__.bend:1617  __init__.py:114  -- NO MECHANICAL FIX: the cited line is inside `apply_binds` (declared at :107) and the marker names no symbol this file declares
#   #   TODO(p3) __init__.py:114  `s.substitute`   -- no reader in the tree.
# tinybendygrad/schedule/__init__.bend:1733  __init__.py:240  -- NO MECHANICAL FIX: the cited line is inside `canonicalize_call_body` (declared at :235) and the marker names no symbol this file declares
#   #     TODO(p3) __init__.py:240  `graph_rewrite(..., bottom_up=True)` -- no
# tinybendygrad/schedule/__init__.bend:1741  ops.py:1239  -- NO MECHANICAL FIX: the cited line is inside `view_as` (declared at :1236) and the marker names no symbol this file declares
#   #     mint is the wall. `UOp.param_like` is `TODO(p3) ops.py:1239` in
# tinybendygrad/schedule/__init__.bend:1753  ops.py:559  -- NO MECHANICAL FIX: the cited line is inside `unbound_outputs` (declared at :556) and the marker names no symbol this file declares
#   #     TODO(p3) ops.py:559  `all_int(c.shape)` -- `c.shape` needs `fold.bend`'s
# tinybendygrad/schedule/__init__.bend:1765  __init__.py:214  -- NO MECHANICAL FIX: the cited line is inside `is_store_after` (declared at :213) and the marker names no symbol this file declares
#   #     TODO(p3) __init__.py:214  `.reshape` -- `mixin/movement.bend`'s.
# tinybendygrad/schedule/__init__.bend:1766  __init__.py:208  -- NO MECHANICAL FIX: the cited line is inside `contiguous_mops_to_view` (declared at :195) and the marker names no symbol this file declares
#   #     TODO(p3) __init__.py:208  `.unshard` -- ABSENT from the tree.
# tinybendygrad/schedule/__init__.bend:1781  __init__.py:285  -- NO MECHANICAL FIX: the cited line is inside `create_linear_with_vars` (declared at :268) and the marker names no symbol this file declares
#   #     TODO(p3) __init__.py:285  `used_vars` -- `UOp.variables`.
# tinybendygrad/schedule/__init__.bend:1782  __init__.py:301  -- NO MECHANICAL FIX: the file has 296 lines and the marker cites :301
#   #     TODO(p3) __init__.py:301  `memory_plan_rewrite` -- `schedule/memory.py`.
```

## `tinybendygrad/schedule/multi.bend` -- 2 citations

```diff
--- a/tinybendygrad/schedule/multi.bend
+++ b/tinybendygrad/schedule/multi.bend
# tinybendygrad/schedule/multi.bend:16  ops.py:1104  -- NO MECHANICAL FIX: the cited line is inside `_min_max` (declared at :1094) and the marker names no symbol this file declares
#   # `copy_multi`. `fold.bend` lists it as `TODO(p3) ops.py:1104` and it is not a fold at
# tinybendygrad/schedule/multi.bend:3452  ops.py:646  -- NO MECHANICAL FIX: the cited line is inside `valid` (declared at :645) and the marker names no symbol this file declares
#   #   TODO(p3) ops.py:646 multi.py:12   `_apply_shrink`, SHRINK  -- BLOCKED.-- BLOCKED. needs `UOp._mop` -- which is PORTED as `tn_mop` in `tensor.bend:
```

## `tinybendygrad/tensor.bend` -- 8 citations

```diff
--- a/tinybendygrad/tensor.bend
+++ b/tinybendygrad/tensor.bend
# tinybendygrad/tensor.bend:1211  tensor.py:74  -- NO MECHANICAL FIX: the cited line is inside `__init__` (declared at :56) and the marker names no symbol this file declares
#   # TODO(p3) tensor.py:74  a float `ConstType` -- `F32{data: Word(32n)}` has no
# tinybendygrad/tensor.bend:1350  tensor.py:73  -- NO MECHANICAL FIX: the cited line is inside `__init__` (declared at :56) and the marker names no symbol this file declares
#   # TODO(p3) tensor.py:73  UOp.const(0.0, _dtype) -- an F32 literal.
# tinybendygrad/tensor.bend:1583  ops.py:821  -- NO MECHANICAL FIX: the cited line is inside `_mop` (declared at :799) and the marker names no symbol this file declares
#   # this file and carries both as `TODO(p3) ops.py:821` and `TODO(p3) ops.py:655`. A
# tinybendygrad/tensor.bend:1583  ops.py:655  -- NO MECHANICAL FIX: the cited line is inside `reduce` (declared at :652) and the marker names no symbol this file declares
#   # this file and carries both as `TODO(p3) ops.py:821` and `TODO(p3) ops.py:655`. A
# tinybendygrad/tensor.bend:1863  ops.py:616  -- NO MECHANICAL FIX: the cited line is inside `const` (declared at :610) and the marker names no symbol this file declares
#   # as `TODO(p3) ops.py:616` -- written here for the same reason `tn_mop` is.
@@ -2110 +2110 @@
-# TODO(p3) tensor.py:547  __imatmul__     assign + mixin/op.py:394 -- a WMMA, not an alu
+# TODO(p3) tensor.py:545  __imatmul__     assign + mixin/op.py:394 -- a WMMA, not an alu
@@ -2171 +2171 @@
-# TODO(p3) tensor.py:285  _data        -- `memoryview`
+# TODO(p3) tensor.py:283  _data        -- `memoryview`
# tinybendygrad/tensor.bend:2204  tensor.py:106  -- NO MECHANICAL FIX: the cited line is inside `_apply_uop` (declared at :103) and the marker names no symbol this file declares
#   # TODO(p3) tensor.py:106  all_metadata     -- ops.bend has the READER
```

## `tinybendygrad/uop/divandmod.bend` -- 6 citations

```diff
--- a/tinybendygrad/uop/divandmod.bend
+++ b/tinybendygrad/uop/divandmod.bend
# tinybendygrad/uop/divandmod.bend:854  divandmod.py:13  -- NO MECHANICAL FIX: the cited line is inside `fold_divmod_general` (declared at :8) and the marker names no symbol this file declares
#   # TODO(p3) divandmod.py:13 the RANGE HALF of `x//y` being a point -- PORTED for
# tinybendygrad/uop/divandmod.bend:863  divandmod.py:13  -- NO MECHANICAL FIX: the cited line is inside `fold_divmod_general` (declared at :8) and the marker names no symbol this file declares
#   # TODO(p3) divandmod.py:13-15 a FLOAT CONST -- `_min_max` returns PyConst and
# tinybendygrad/uop/divandmod.bend:875  divandmod.py:41  -- NO MECHANICAL FIX: the cited line is inside `fold_divmod_general` (declared at :8) and the marker names no symbol this file declares
#   # TODO(p3) divandmod.py:37 `Shared decomposition for folding rules` and :41-48
# tinybendygrad/uop/divandmod.bend:885  divandmod.py:50  -- NO MECHANICAL FIX: the cited line is inside `fold_divmod_general` (declared at :8) and the marker names no symbol this file declares
#   # TODO(p3) divandmod.py:50-55 `gcd_with_remainder: factor out common gcd from
@@ -901 +901 @@
-# TODO(p3) divandmod.py:77-81 `divide_by_gcd: x//y -> (x//gcd)//(y//gcd)` and :83-96
+# TODO(p3) divandmod.py:77-90 `divide_by_gcd: x//y -> (x//gcd)//(y//gcd)` and :83-96
# tinybendygrad/uop/divandmod.bend:906  divandmod.py:11  -- NO MECHANICAL FIX: the cited line is inside `fold_divmod_general` (declared at :8) and the marker names no symbol this file declares
#   # TODO(p3) divandmod.py:11 the `raise` itself -- Python's
```

## `tinybendygrad/uop/movement.bend` -- 2 citations

```diff
--- a/tinybendygrad/uop/movement.bend
+++ b/tinybendygrad/uop/movement.bend
@@ -235 +235 @@
-# the next time that file is edited (`# TODO(p3) ops.py:581  def index`).
+# the next time that file is edited (`# TODO(p3) ops.py:559  def index`).
# tinybendygrad/uop/movement.bend:432  movement.py:7  -- NO MECHANICAL FIX: the cited line does not hold the claim and no symbol in the marker is declared in `uop/movement.py`
#   # TODO(p3) movement.py:7  rank >= 2: `UOp.sink(*usrcs).simplify()` there sees a
```

## `tinybendygrad/uop/spec.bend` -- 5 citations

```diff
--- a/tinybendygrad/uop/spec.bend
+++ b/tinybendygrad/uop/spec.bend
# tinybendygrad/uop/spec.bend:3213  spec.py:286  -- NO MECHANICAL FIX: the file has 280 lines and the marker cites :286
#   # TODO(p3) spec.py:286 def pyrender_globals -- imports `tinygrad.codegen.opt`,
# tinybendygrad/uop/spec.bend:3217  spec.py:292  -- NO MECHANICAL FIX: the file has 280 lines and the marker cites :292
#   # TODO(p3) spec.py:292 def eval_pyrender -- `exec` of GENERATED SOURCE. WALL: the
# tinybendygrad/uop/spec.bend:3221  spec.py:296  -- NO MECHANICAL FIX: the file has 280 lines and the marker cites :296
#   # TODO(p3) spec.py:296 def test_pyrender -- renders a UOp to source and compares
# tinybendygrad/uop/spec.bend:3231  spec.py:7  -- NO MECHANICAL FIX: the cited line does not hold the claim and no symbol in the marker is declared in `uop/spec.py`
#   # TODO(p3) spec.py:7   is_disk_device -- `from tinygrad.device import is_disk_device`
# tinybendygrad/uop/spec.bend:3255  spec.py:133  -- NO MECHANICAL FIX: the cited line is inside `matches_dtype` (declared at :45) and the marker names no symbol this file declares
#   # TODO(p3) spec.py:133 lambda x: `b := x.storage_base` -- a `while` over BITCAST,
```

## `tinybendygrad/uop/symbolic.bend` -- 5 citations

```diff
--- a/tinybendygrad/uop/symbolic.bend
+++ b/tinybendygrad/uop/symbolic.bend
# tinybendygrad/uop/symbolic.bend:19  ops.py:483  -- NO MECHANICAL FIX: the cited line is inside `ranges` (declared at :479) and the marker names no symbol this file declares
#   #                                            TODO(p3) ops.py:483)
@@ -3667 +3667 @@
-# TODO(p3) symbolic.py:209 def canonicalize_simplex -- `u.vmin >= 0` and
+# TODO(p3) symbolic.py:214 def canonicalize_simplex -- `u.vmin >= 0` and
# tinybendygrad/uop/symbolic.bend:3673  symbolic.py:236  -- NO MECHANICAL FIX: the cited line is inside `fold_where_closure` (declared at :233) and the marker names no symbol this file declares
#   # TODO(p3) symbolic.py:236-323 table `symbolic` -- ALL 47. Every one of the 47
# tinybendygrad/uop/symbolic.bend:3691  symbolic.py:452  -- NO MECHANICAL FIX: the cited line is inside `gated_given_valid` (declared at :427) and the marker names no symbol this file declares
#   # TODO(p3) symbolic.py:452 the `xpow` rule -- `xpow` is
# tinybendygrad/uop/symbolic.bend:3701  symbolic.py:466  -- NO MECHANICAL FIX: the cited line is inside `gated_given_valid` (declared at :427) and the marker names no symbol this file declares
#   # TODO(p3) symbolic.py:466-468 the three `1 - d` reciprocal rules -- and the wall is
```

