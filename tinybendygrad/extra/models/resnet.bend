import Base
import ./../../tensor.bend as T
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../dtype.bend as DT
import ./../../nn/__init__.bend as NN
import ./../../nn/state.bend as ST
import ./../../mixin/op.bend as MO
import ./../../mixin/movement.bend as MX
import ./../../mixin/reduce.bend as RC
import ./../datasets/__init__.bend as D

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of extra/models/resnet.py (170 LOC). NOT YET PORTED.
#
# This is the ResNet DEFINITION and the first thing that has to exist before
# any ImageNet-shaped number can be produced, so the header states the distance
# exactly rather than rounding it to "not done".
# Measured 2026-10-19 03:46-04:05Z at HEAD 80d329a33, all by reading the port.
#
# THE HEADLINE, CORRECTED 2026-10-20 -- **AND THE CORRECTION IS THE POINT.** This used to read
# "`nn.Conv2d`, `nn.BatchNorm2d` AND `nn.Linear` ARE ALL MISSING", and **THREE UNITS REPORTED IT AS
# STALE WHILE IT WAS STILL TRUE-ISH**: `nn/layers.bend` and `nn/pool.bend` landed and CLOSED IT, and a
# wall that has FALLEN is still NAMED as a wall. Measured now, by NAME, not by count --
#   nn_conv2d     nn/layers.bend:756      nn_linear    nn/layers.bend:427
#   nn_relu       nn/layers.bend:262      pool_bn      nn/pool.bend:381
#   pool_maxpool  nn/pool.bend:250
# **WHAT IS ACTUALLY STILL MISSING**, named and checked, and the distinction MATTERS: `vt_sequential`
# and `vt_layernorm` DO exist -- at `extra/models/vit.bend:153` and `:157` -- **but both are STUB
# REFUSALS inside another model's stub, not ported layers.** So "the name is absent" and "the layer is
# absent" are DIFFERENT QUESTIONS, and a census that answers the first while being read as the second
# is the same defect as this headline was. Genuinely ABSENT everywhere, 0 defs:
# `scaled_dot_product_attention` and `identity_element` (the latter is why BOTH padded pool arms
# refuse), plus `Tensor.cat` and reshape's `-1` inference. **ZERO nn LAYER CLASSES** --
# `nn/__init__.bend` is 429 lines of shape arithmetic and still holds no class.
# `nn/__init__.bend:230` still reads "`x.layernorm -- SIDE B, not built`", which is TRUE, so it is
# deliberately NOT touched.
# `nn/__init__.bend` holds the SHAPE ARITHMETIC the layers need and nothing else:
#   nn_mt      :151   `make_tuple`                        nn_groups :175  `in_channels//groups`
#   nn_same    :196   `padding='same'`                    nn_scale  :209  `1/sqrt(in_c*prod(ks))`
#   nn_bound   :210   `1/sqrt(n)`                         nn_glorot :217  `(6/(fan_in+fan_out))**0.5`
# Its own wall list named the three this file needs first:
#   :231  `TODO(p3) mixin/op.py  x.conv2d           -- SIDE B, not built.`
#   :229  `TODO(p3) mixin/op.py:1662  x.batchnorm   -- SIDE B, not built.`
# -- both are now BUILT, and that list is kept above ONLY as the record of what was true on
# 2026-10-19, because a deleted blocker is how the NEXT reader thinks nothing was ever missing.
#   :227  `TODO(p3) mixin/op.py:1254  x.linear       -- ...`
#
# AND `tinybendygrad/mixin/op.bend:1523` IS THE LAST LINE OF THAT FILE and reads
# `# SIDE B's SECTION GOES BELOW THIS LINE.` -- so SIDE B IS THE EMPTY HALF.
# `mixin/op.bend:13-15` enumerates it: "sequential, linear, the pools, the
# convolutions, layernorm, batchnorm, the losses, qr, svd, keccak, hash". The
# file is 1523 lines and every `def` in it is on SIDE A. THAT IS THE WALL.
#
# THE SYMBOL CENSUS, EVERY UPSTREAM SYMBOL THIS FILE NAMES, WITH ITS INSTRUMENT:
#
#   EXISTS
#     `Tensor`            tensor.bend (Tensors, tn_*)
#     `dtypes`            dtype.bend:518 `to_dtype` (upstream:2)
#     `Tensor.relu`       tensor.bend:774 `tn_relu`                      (:29,:32,:57,:58,:61,:62,:109)
#     `Tensor.cast`       tensor.bend:1389 `tn_cast.put`                (:121)
#     `Tensor.shape`      tensor.bend:216 `tn_shape`                    (:148,:152)
#     `Tensor.dtype`      tensor.bend:219 `tn_dtype`                    (:153)
#     `Tensor.device`     tensor.bend:213 `tn_device`                   (:153)
#     `Tensor.mean`       mixin/op.bend:891 `mo_mean`                    (:120)
#     `Tensor.sequential` SIDE B -- see MISSING
#     `get_state_dict`    nn/state.bend:318                              (indirectly, :141)
#     `GlobalCounters.reset` helpers.bend:2584                           (:168)
#     `Context`           helpers.bend:407 `Context.arg`                 (:165)
#     `fetch`             MISSING -- see MISSING
#
#   PARTIAL
#     `Tensor.reshape`    `mxw_reshape` mixin/movement.bend:1431 and
#                         `mo_reshape` mixin/op.bend:664 EXIST (:153) but the
#                         upstream call is `reshape(obj.shape)` on a shape list
#                         read back out of the layer, and there is no layer.
#     `Tensor.pad`        `mxw_pad` mixin/movement.bend:1520 EXISTS. The
#                         `:110` call `out.pad([1,1,1,1])` needs the layer first.
#     `Tensor.max_pool2d` `mx_pool_f` mixin/movement.bend:297 and
#                         `mx_pool_shape` :902 are the POOL SHAPE ARITHMETIC and
#                         the pool BODIES are SIDE B, so there is nothing to call.
#
#   MISSING, with the instrument that says so
#     `nn.Conv2d`         `grep -rnE "^def .*conv2d" --include='*.bend'
#                         tinybendygrad/` = 1, and that one hit IS THIS FILE'S
#                         OWN `rs_conv2d_alias` refusal at :151. The instrument
#                         is SELF-REFERENTIAL and the disclosure is the point:
#                         before this unit ran, that grep returned 0. A grep
#                         whose only hit is the refusal it is justifying proves
#                         nothing on its own, so the real evidence is the one
#                         that does not move: `nn/__init__.bend` has EXACTLY 17
#                         `def`s and all 17 are shape arithmetic --
#                         `nn_app nn_len nn_neg1 nn_i64_app nn_mt nn_mt_seq
#                         nn_half nn_prod nn_groups nn_k1 nn_pair nn_pair
#                         nn_pad nn_same nn_scale nn_bound nn_glorot` -- and
#                         ZERO layer classes.                   (:8,:17,:19,:24,:43,:45,:47,:52,:87)
#     `nn.BatchNorm2d`    same instrument, same disclosure: `grep -rnE "^def
#                         .*batchnorm" --include='*.bend'` = 1 and it is this
#                         file's own `rs_batchnorm_alias` at :148.
#                                                               (:7,:18,:20,:25,:26,:44,:46,:48,:53,:54,:88)
#     `nn.Linear`         nn/__init__.bend:227, mixin/op.bend SIDE B.     (:9,:93)
#     `Tensor.sequential` mixin/op.bend:14 lists it in SIDE B; `grep -rnE
#                         "^def .*sequential" --include='*.bend'` -> 0.   (:31,:60,:111,:113,:115,:117)
#     `Tensor.argmax`     `grep -rnE "^def mo_argmax" --include='*.bend'
#                         tinybendygrad/` = 0. mixin/op.bend:11 lists `argmax`
#                         inside SIDE A but NO def carries it, and `rc_arg`
#                         mixin/reduce.bend:208 is a reduction internal, not
#                         `Tensor.argmax`.                                 (:17)
#     `Tensor.item`       `grep -rnE "^def .*item" --include='*.bend'
#                         tinybendygrad/` -> every hit is a renderer or an ELF
#                         symbol reader. None is `Tensor.item`.            (:17)
#     `torch_load`        `grep -rn "torch_load" --include='*.bend'
#                         tinybendygrad/` = 0.                            (:3,:139)
#     `fetch`             MISSING. `grep -rnE "^def fetch\(" --include='*.bend'
#                         tinybendygrad/` = 0. (A LOOSER `grep -rnE "^def
#                         .*fetch"` answers 2 and BOTH are sibling REFUSALS at
#                         `extra/datasets/__init__.bend:49,:53`. A grep that
#                         reads a PREFIX and calls it a hit is the failure this
#                         tree already has a name for, so the instrument here
#                         is anchored to `fetch\(`. ALSO, helpers.bend:3193
#                         says why in the port's own words: "The HTTP machinery
#                         (fetch, fetch_fw, _ensure_downloads_dir) is urllib
#                         plus a temp file plus an atomic rename. It is I/O of
#                         exactly the kind the master plan puts in runtime/,
#                         and its only callers are the weight downloaders."
#                                                                     (:4,:139)
#     `get_child`         `grep -rnE "^def .*get_child" --include='*.bend'
#                         tinybendygrad/` = 0.                            (:4,:141)
#     `Tensor.rand`       `mixin/rand.bend` has `rd_rand` :650 and
#                         `rd_randint` :843 but no `Tensor.rand` spelling. (:167,:169,:170)
#     `TinyJit`           PARTIAL, and worth the nuance: `engine/jit.bend` IS a
#                         real port -- `InInfo` :370-389 is `expected_input_info`
#                         (jit.py:55) "IN FULL" and jit.bend:38-41 lists
#                         `_TinyJit.__call__` :125-178 "all four arms and both
#                         refusals" as PORTED. What is missing is the `TinyJit`
#                         NAME and the DECORATOR: jit.bend:24 says what
#                         function.bend will need, `tiny_jit.of3(f)`, and there
#                         is no `tiny_jit` def.                            (:166)
#
# THE ARITHMETIC HALF IS DONE AND THE EXECUTION HALF IS NOT. So the shapes of a
# ResNet18 can be computed today -- `nn_scale`, `nn_bound`, `nn_groups`,
# `nn_same` and `nn_mt` are all callable and all gated upstream -- and not one
# activation can be produced. A port that could print the shape of
# `conv1.weight` and not run `conv1` is exactly half of ResNet, and this header
# is where that half is recorded.
#
# EVERY DEF BELOW REFUSES, AND THE RETURN TYPE IS `D.Refused`, NOT A TENSOR. A
# stub that returned a zero Tensor or an empty list would be indistinguishable
# from a layer whose weights happen to be zero, and a model file that reports
# silence instead of absence is the one lie this file must not tell. `refuse`
# and the `Refused` type are DECLARED ONCE at `extra/datasets/__init__.bend:40-46`
# and imported here as `D`, so the refusal is one definition and not one per
# file. Each message names the upstream `path:line` of the FIRST MISSING SYMBOL
# in that def's body, so a refusal carries the address of the work.
#
# SIGNATURE TRANSLITERATION. Python classes have no Bend spelling and the port
# already settled it (nn/__init__.bend:22-33): "each layer here is a def over
# its CONSTRUCTOR ARGUMENTS ... plus a `*_st` def that answers the ordered
# `(name, tensor)` list that IS `__dict__`". So `BasicBlock.__init__` is
# `rs_basic_block_init` over its five arguments with the two defaults spelled
# out, and `__call__` is `rs_basic_block_call`. `self` does not survive: a Bend
# `Data` record has no reflection (nn/__init__.bend:25), so the state a Python
# `self` carries is the argument list here.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

# the `Refused` accessor, in nn/state.bend:227's shape, so `main` can print the
# address the refusal carries rather than discarding it.
def rs_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :7-9 the three module-level aliases. They exist so `load_from_pretrained` can
# monkeypatch a layer implementation, and the monkeypatch is part of the
# file's contract even though upstream never uses it in this file.
# ---------------------------------------------------------------------------
def rs_batchnorm_alias() -> D.Refused:
  D.refuse("extra/models/resnet.py:7 BatchNorm = nn.BatchNorm2d -- mixin/op.py:1662 is SIDE B")

def rs_conv2d_alias() -> D.Refused:
  D.refuse("extra/models/resnet.py:8 Conv2d = nn.Conv2d -- mixin/op.py conv2d is SIDE B")

def rs_linear_alias() -> D.Refused:
  D.refuse("extra/models/resnet.py:9 Linear = nn.Linear -- mixin/op.py:1254 is SIDE B")

# ---------------------------------------------------------------------------
# :12-33 BasicBlock. `expansion = 1` (:13) is a CLASS CONSTANT and it is a
# U32 here; it is the one number in this file that is already KNOWN.
# ---------------------------------------------------------------------------
def rs_basic_block_expansion() -> U32: 1

# :15  def __init__(self, in_planes, planes, stride=1, groups=1, base_width=64)
def rs_basic_block_init(in_planes: U32, planes: U32, stride: U32, groups: U32,
  base_width: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:15 BasicBlock.__init__ -- FIRST MISSING SYMBOL Conv2d (:17)")

# :28  def __call__(self, x)
def rs_basic_block_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/resnet.py:28 BasicBlock.__call__ -- FIRST MISSING SYMBOL x.batchnorm (:29)")

# ---------------------------------------------------------------------------
# :36-62 Bottleneck. `expansion = 4` (:38), `stride_in_1x1` defaults False (:40).
# `width = int(planes * (base_width / 64.0)) * groups` (:41) is plain float
# arithmetic over U32 and is PORTABLE; it is listed as a gap in the report, not
# here, because the def cannot reach its second line without Conv2d.
# ---------------------------------------------------------------------------
def rs_bottleneck_expansion() -> U32: 4

# :40  def __init__(self, in_planes, planes, stride=1, stride_in_1x1=False,
#                   groups=1, base_width=64)
def rs_bottleneck_init(in_planes: U32, planes: U32, stride: U32, stride_in_1x1: Bool,
  groups: U32, base_width: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:40 Bottleneck.__init__ -- FIRST MISSING SYMBOL Conv2d (:43)")

# :56  def __call__(self, x)
def rs_bottleneck_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/resnet.py:56 Bottleneck.__call__ -- FIRST MISSING SYMBOL x.batchnorm (:57)")

# ---------------------------------------------------------------------------
# :64-153 ResNet.
# ---------------------------------------------------------------------------

# :65  def __init__(self, num, num_classes=None, groups=1, width_per_group=64,
#                   stride_in_1x1=False)
def rs_resnet_init(num: U32, num_classes: Maybe<&2, U32>, groups: U32, width_per_group: U32,
  stride_in_1x1: Bool) -> D.Refused:
  D.refuse("extra/models/resnet.py:65 ResNet.__init__ -- FIRST MISSING SYMBOL Conv2d (:87)")

# :95  def _make_layer(self, block, planes, num_blocks, stride, stride_in_1x1)
def rs_resnet_make_layer(block_expansion: U32, planes: U32, num_blocks: U32, stride: U32,
  stride_in_1x1: Bool) -> D.Refused:
  D.refuse("extra/models/resnet.py:95 ResNet._make_layer -- FIRST MISSING SYMBOL BasicBlock/Bottleneck")

# :106 def forward(self, x)
def rs_resnet_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/resnet.py:106 ResNet.forward -- FIRST MISSING SYMBOL x.max_pool2d (:110)")

# :125 def __call__(self, x: Tensor) -> Tensor
def rs_resnet_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/resnet.py:125 ResNet.__call__ -- FIRST MISSING SYMBOL x.max_pool2d (:110)")

# :128 def load_from_pretrained(self)
def rs_resnet_load_from_pretrained() -> D.Refused:
  D.refuse("extra/models/resnet.py:128 ResNet.load_from_pretrained -- FIRST MISSING SYMBOL torch_load/fetch (:139)")

# ---------------------------------------------------------------------------
# :155-160 the six constructors. Python spells them as lambdas returning a
# `ResNet`, so each refuses exactly as `rs_resnet_init` does with its `num` and
# `num_classes` already filled in.
# ---------------------------------------------------------------------------
def rs_resnet18(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:155 ResNet18 -- FIRST MISSING SYMBOL Conv2d (:87)")
def rs_resnet34(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:156 ResNet34 -- FIRST MISSING SYMBOL Conv2d (:87)")
def rs_resnet50(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:157 ResNet50 -- FIRST MISSING SYMBOL Conv2d (:87)")
def rs_resnet101(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:158 ResNet101 -- FIRST MISSING SYMBOL Conv2d (:87)")
def rs_resnet152(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:159 ResNet152 -- FIRST MISSING SYMBOL Conv2d (:87)")
def rs_resnext50_32x4d(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/resnet.py:160 ResNeXt50_32X4D -- FIRST MISSING SYMBOL Conv2d (:87)")

# ---------------------------------------------------------------------------
# :162-170 `if __name__ == "__main__":` -- TinyJit over ResNet18 at 224x224,
# `GlobalCounters.reset()`, then ten more captures. `main` below is this block
# and NOTHING ELSE. There is deliberately no invented census printed here: a
# 1:1 mirror that emits rows upstream does not emit is not a mirror, and the
# census belongs in the report where a reader looks for it.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, rs_resnet18(1000))
    srow("resnet_refused_at", rs_at(a))
    row("resnet_ported", False{})