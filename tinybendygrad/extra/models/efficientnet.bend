import Base
import ./../../tensor.bend as T
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../dtype.bend as DT
import ./../../nn/__init__.bend as NN
import ./../../nn/layers.bend as LN
import ./../../nn/pool.bend as PL
import ./../../nn/state.bend as ST
import ./../../mixin/op.bend as MO
import ./../../mixin/movement.bend as MX
import ./../../mixin/rand.bend as RD
import ./../../mixin/elementwise.bend as E
import ./../datasets/__init__.bend as D

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of extra/models/efficientnet.py (164 LOC). NOT YET
# PORTED.
#
# THE ONLY MODEL HERE THAT STORES ITS WEIGHTS AS BARE `Tensor`s RATHER THAN IN
# LAYER CLASSES, and that single design decision removes this file's most
# obvious blocker and creates a different one. `self._expand_conv =
# Tensor.glorot_uniform(oup, input_filters, 1, 1)` (upstream:11) is a TENSOR,
# not a `Conv2d`, so `nn.Conv2d` is NEVER NAMED in this file -- and therefore
# this is the only model in the directory whose first constructor line resolves
# to an existing def.
#
# TODO(port): STOPPED AT `MBConvBlock.__init__` (extra/models/efficientnet.py:7),
# at upstream:11
#       self._expand_conv = Tensor.glorot_uniform(oup, input_filters, 1, 1)
#   and that line IS BUILT: `rd_glorot_uniform` (mixin/rand.bend:861) over the
#   bound `nn_glorot` (nn/__init__.bend:217). THE FIRST LINE THAT IS NOT is
#   upstream:12
#       self._bn0 = BatchNorm2d(oup, track_running_stats=track_running_stats)
#   and the blocker is NOT the normalisation -- `pool_bn` (nn/pool.bend:381) IS
#   BUILT and `pool.bend:44-48` measures `Tensor.batchnorm` as a pure
#   DECOMPOSITION (`x - mean`, `* weight`, `.mul(invstd)`, `+ bias`). The blocker
#   is the HALF OF BatchNorm THAT IS NOT A DECOMPOSITION: the running-statistics
#   update, refused at `pool.bend:415`, whose two causes are NAMED there --
#   "`TRAINING` is not a binding in tinybendygrad (comments only)" and
#   "`Tensor.assign` is not a def (tensor.bend:2539 states the immutability
#   divergence)".
#
#   AND HERE THAT HALF IS NOT OPTIONAL. Upstream:39 is
#       x = self._bn0(x.conv2d(self._expand_conv)).swish()
#   which takes BatchNorm's EVAL branch (nn/__init__.py:43,
#   `track_running_stats and not TRAINING`) -- the branch `pool.bend:412-414`
#   calls "the ONLY path ResNet INFERENCE takes" and "buildable". So an
#   EfficientNet at INFERENCE needs the built half and could use it. But this
#   constructor's `track_running_stats=True` (:8) is the TRAINING default, and
#   `load_from_pretrained` (:134) reads `running_mean`/`running_var` OUT of the
#   checkpoint. A model that cannot be trained and cannot be loaded is a model
#   that can only ever produce its own random initialisation.
#
# `avg_pool2d` IS BUILT (`pool_avgpool`, nn/pool.bend:260) BUT NOT FOR THE CALLS
# THIS FILE MAKES, and that is worth stating precisely because it is the kind of
# near-miss a count hides:
#   upstream:44  x.avg_pool2d(kernel_size=x.shape[2:4])     -- UNPADDED, BUILT
#   upstream:130 x.avg_pool2d(kernel_size=x.shape[2:4])     -- UNPADDED, BUILT
#   upstream:134-163 `count_include_pad` never appears here, so this file is
#                UNAFFECTED -- and `inception.py` is not.
# Both of the calls are `kernel_size = the whole spatial extent`, i.e. an
# ADAPTIVE-to-1x1 pool with a DYNAMIC kernel read out of the tensor's own shape.
# `pool_adaptive_avg` (nn/pool.bend:312) takes an `AP` RECORD with the input
# dims as `U32` values, so a caller must already have projected the shape --
# `nn_shape` (nn/layers.bend:94) answers a `Maybe<&2, List<&2, U32>>`, and on
# the `SU` arm it answers `None`. THAT IS THE SEAM, and it is a `Maybe` rather
# than a wall.
#
# EVERY DEF BELOW REFUSES, AND THE RETURN TYPE IS `D.Refused`, NOT A TENSOR. A
# stub that returned a zero Tensor would be indistinguishable from a weight that
# happens to be zero -- and in THIS file that is not a hypothetical, because
# every weight IS a bare Tensor and a zeroed Tensor is exactly what a failed
# initialiser looks like. `refuse`/`Refused` are DECLARED ONCE at
# `extra/datasets/__init__.bend:40-46` and imported as `D`.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def ef_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :7-52 MBConvBlock.
# ---------------------------------------------------------------------------

# :8  def __init__(self, kernel_size, strides, expand_ratio, input_filters,
#                   output_filters, se_ratio, has_se, track_running_stats=True)
def ef_mbconv_init(kernel_size: U32, sx: U32, sy: U32, expand_ratio: U32,
  input_filters: U32, output_filters: U32, se_ratio: F32, has_se: Bool,
  track_running_stats: Bool) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:8 MBConvBlock.__init__ -- FIRST MISSING SYMBOL BatchNorm2d at :12, whose running-statistics half is REFUSED at nn/pool.bend:415 (TRAINING is not a binding, Tensor.assign is not a def)")

# :9  oup = expand_ratio * input_filters -- PURE ARITHMETIC, and the ONE number
# this constructor has already decided before it refuses.
def ef_oup(expand_ratio: U32, input_filters: U32) -> U32: U32.mul(expand_ratio, input_filters)

# :11 self._expand_conv = Tensor.glorot_uniform(oup, input_filters, 1, 1)
def ef_expand_conv(oup: U32, input_filters: U32) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:11 MBConvBlock._expand_conv -- rd_glorot_uniform (mixin/rand.bend:861) EXISTS; this is the WEIGHT-STORE question, not the initialiser")

# :17-20 the two pad arms. `self.pad = [(k-1)//2-1, (k-1)//2]*2` when
# `strides == (2,2)`, else `[(k-1)//2]*4`. SPELLED, because it is integer
# arithmetic over U32 that needs nothing from the port and it is the clearest
# possible contrast with the lines below it.
def ef_pad_half(kernel_size: U32) -> U32: U32.div(U32.sub(kernel_size, 1), 2)
def ef_pad_stride2(kernel_size: U32) -> U32: U32.sub(ef_pad_half(kernel_size), 1)

# :22 self._depthwise_conv = Tensor.glorot_uniform(oup, 1, kernel_size, kernel_size)
def ef_depthwise(oup: U32, kernel_size: U32) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:22 MBConvBlock._depthwise_conv -- rd_glorot_uniform EXISTS; blocked by Tensor.conv2d's `groups=` at :40, whose value is read off this weight's own shape")

# :27-31 the four squeeze/excitation weights
def ef_se_reduce(oup: U32, input_filters: U32, se_ratio: F32) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:28 MBConvBlock._se_reduce -- max(1, int(input_filters*se_ratio)) is F32 arithmetic and Tensor.int IS BUILT; blocked by Tensor.sigmoid at :47 (ew_sigmoid, mixin/elementwise.bend:1196, EXISTS) being unreachable behind x.sequential at :41")

# :33 self._project_conv = Tensor.glorot_uniform(output_filters, oup, 1, 1)
def ef_project_conv(output_filters: U32, oup: U32) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:33 MBConvBlock._project_conv -- rd_glorot_uniform EXISTS; blocked by BatchNorm2d at :34, i.e. by nn/pool.bend:415")

# :36 def __call__(self, inputs)
def ef_mbconv_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:36 MBConvBlock.__call__ -- FIRST MISSING SYMBOL Tensor.silu/swish is BUILT (ew_silu, mixin/elementwise.bend:1209); the first MISSING one is x.avg_pool2d at :44, whose kernel_size is read off x.shape[2:4] -- pool_avgpool (nn/pool.bend:260) takes WINDOW DIMENSIONS AS VALUES and nn_shape (nn/layers.bend:94) answers a Maybe<&2, List<&2, U32>>")

# :44 x_squeezed = x.avg_pool2d(kernel_size=x.shape[2:4])
def ef_se_avgpool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:44 MBConvBlock.__call__ -- pool_avgpool (nn/pool.bend:260) EXISTS unpadded, which is the right arm; the missing part is reading kernel_size OUT OF x.shape[2:4] rather than being handed it")

# :50 if x.shape == inputs.shape -- A SHAPE EQUALITY, and `x.shape` is a
# `Maybe<&2, List<&2, U32>>` on this port (nn/layers.bend:94), so this
# comparison is the first thing in the file that is a TWO-arm decision on
# possibly-absent data. NOT a wall; named so it is not mistaken for one.
def ef_skip_equal(+a: T.Tensor, +b: T.Tensor) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:50 MBConvBlock.__call__ -- tn_add (tensor.bend:680) EXISTS and the fold answers the broadcast (uop/fold.bend:999); blocked only by upstream:49's BatchNorm2d, i.e. by nn/pool.bend:415")

# ---------------------------------------------------------------------------
# :54-132 EfficientNet. THE `global_params` TABLE IS PURE DATA AND IS RESTATED,
# because a reader of this stub should not have to open Python to learn that
# `b7` is 2.0 x 3.1 and `l2` is 4.3 x 5.3.
# ---------------------------------------------------------------------------

# :57-69 global_params[max(number,0)] -- TEN (width, depth) pairs.
def ef_global_width(n: U32) -> F32:
  match n:
    case 0: 1.0
    case 1: 1.0
    case 2: 1.1
    case 3: 1.2
    case 4: 1.4
    case 5: 1.6
    case 6: 1.8
    case 7: 2.0
    case 8: 2.2
    case _: 4.3

def ef_global_depth(n: U32) -> F32:
  match n:
    case 0: 1.0
    case 1: 1.1
    case 2: 1.2
    case 3: 1.4
    case 4: 1.8
    case 5: 2.2
    case 6: 2.6
    case 7: 3.1
    case 8: 3.6
    case _: 5.3

# :55 def __init__(self, number=0, classes=1000, has_se=True,
#                   track_running_stats=True, input_channels=3, has_fc_output=True)
def ef_effnet_init(number: U32, classes: U32, has_se: Bool,
  track_running_stats: Bool, input_channels: U32, has_fc_output: Bool) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:55 EfficientNet.__init__ -- FIRST MISSING SYMBOL BatchNorm2d at :85, whose running-statistics half is REFUSED at nn/pool.bend:415")

# :71-78 round_filters -- SPELLED. It is F32 arithmetic and `int()` truncates
# toward zero, which is what makes the +divisor/2 worth having, and a reader
# deserves to see it rather than be told it is "math".
def ef_round_filters(filters: U32, multiplier: F32) -> U32:
  +f = F32.mul(U32.to_f32(filters), multiplier)
  +base = U32.max(8, U32.div(F32.to_u32(F32.add(f, 4.0)), 8))
  Bool.pick(U32, F32.is_lt(U32.to_f32(base), F32.mul(f, 0.9)), U32.add(base, 8), base)

# :80-81 round_repeats -- `int(math.ceil(global_params[1] * repeats))`. `ceil` is
# a def in Base; the F32 multiply is upstream's. `U32.to_f32`/`F32.to_u32` is
# the conversion PAIR this tree actually has (helpers.bend:929), and there is no
# `F32.from_f64` -- which is why these two are written in `U32` at all.
def ef_round_repeats(repeats: U32, depth: F32) -> U32:
  F32.to_u32(F32.ceil(F32.mul(depth, U32.to_f32(repeats))))

# :83 out_channels = round_filters(32)   :84 self._conv_stem = Tensor.glorot_uniform(...)
def ef_conv_stem(out_channels: U32, input_channels: U32) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:84 EfficientNet._conv_stem -- rd_glorot_uniform (mixin/rand.bend:861) EXISTS; blocked by Tensor.conv2d at :127, whose padding=(0,1,0,1) is a 4-ELEMENT List and nn_conv2d (nn/layers.bend:756) takes it as Some{p}, which IS expressible")

# :108-114 the block loop
def ef_blocks(number: U32, has_se: Bool, track_running_stats: Bool) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:108 EfficientNet._blocks -- FIRST MISSING SYMBOL BatchNorm2d via MBConvBlock.__init__ at :8, i.e. nn/pool.bend:415")

# :121-124 the fc half. `self._fc = None` at :124 IS the Maybe arm and needs no
# refutation; the `has_fc_output=False` shape is the reason :132 is a
# conditional expression rather than a call.
def ef_fc(out_channels: U32, classes: U32, has_fc_output: Bool) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:121 EfficientNet._fc -- rd_glorot_uniform and cr_zeros EXIST; blocked by Tensor.sequential at :128")

# :126 def forward(self, x)
def ef_forward(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:126 EfficientNet.forward -- FIRST MISSING SYMBOL Tensor.sequential at :128; grep -rniE '^def .*sequential' --include='*.bend' tinybendygrad/ returns 0")

# :130 x = x.avg_pool2d(kernel_size=x.shape[2:4])
def ef_head_avgpool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:130 EfficientNet.forward -- pool_avgpool (nn/pool.bend:260) EXISTS; blocked by reading kernel_size off x.shape[2:4], which nn_shape (nn/layers.bend:94) answers as a Maybe")

# :132 return x.linear(self._fc, self._fc_bias) if self._fc is not None else x
def ef_forward_linear(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:132 EfficientNet.forward -- nn_linear (nn/layers.bend:427) EXISTS and takes bias as a Maybe<&2, T.Tensor>, which IS this line's `if ... is not None`; blocked by Tensor.sequential at :128")

# ---------------------------------------------------------------------------
# :134-163 load_from_pretrained. EIGHT URLs, restated as a def so the table is
# not a list of strings in a comment that nothing reads.
# ---------------------------------------------------------------------------

# :135-144 model_urls[number]
def ef_url(n: U32) -> String:
  match n:
    case 0: "efficientnet-b0-355c32eb.pth"
    case 1: "efficientnet-b1-f1951068.pth"
    case 2: "efficientnet-b2-8bb594d6.pth"
    case 3: "efficientnet-b3-5fb3a3c3.pth"
    case 4: "efficientnet-b4-6ed6700e.pth"
    case 5: "efficientnet-b5-b6417697.pth"
    case 6: "efficientnet-b6-c76e70fd.pth"
    case _: "efficientnet-b7-dcc49843.pth"

# :134 def load_from_pretrained(self)
def ef_load_pretrained(number: U32) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:134 EfficientNet.load_from_pretrained -- FIRST MISSING SYMBOL torch_load(fetch(...)) at :146; helpers.bend:3193 records the fetch seam as unported and resnet.bend:97-98 records torch_load as 0 hits")

# :148 if k.endswith("num_batches_tracked"): continue -- SPELLED, AND IT IS
# THE UN-DOTTED FORM UPSTREAM USES HERE. That is worth saying because
# `inception.py:278` spells the SAME guard WITH a leading dot
# (`k.endswith(".num_batches_tracked")`), and a reader who has read one of these
# files will half-remember the other's spelling.
def ef_skip_num_batches(k: String) -> Bool: False{}

# :161 mv.replace(vnp.to(mv.device))
def ef_load_replace(+mv: T.Tensor, +v: T.Tensor) -> D.Refused:
  D.refuse("extra/models/efficientnet.py:161 EfficientNet.load_from_pretrained -- MISSING Tensor.replace and Tensor.to; and note this branch is UNREACHABLE above, because mv.shape == vnp.shape at :160 is a shape equality on x.shape (a Maybe<&2, List<&2, U32>>) and :163 prints the mismatch")

# ---------------------------------------------------------------------------
# THERE IS NO `if __name__ == \"__main__\":` IN THIS FILE -- upstream ends at
# :163. `main` below IS the port's own entry and it invents no census, because a
# 1:1 mirror that emits rows upstream does not emit is not a mirror.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, ef_mbconv_init(3, 1, 1, 6, 32, 32, 0.25, True{}, True{}))
    srow("efficientnet_refused_at", ef_at(a))
    row("efficientnet_ported", False{})
    srow("efficientnet_mbconv_init_line", "extra/models/efficientnet.py:8")
    srow("efficientnet_first_blocker", "BatchNorm2d running stats -- nn/pool.bend:415")
    urow("efficientnet_pad_half_k3", ef_pad_half(3))
    urow("efficientnet_pad_stride2_k3", ef_pad_stride2(3))
    urow("efficientnet_oup_b0_expand6", ef_oup(6, 32))
    urow("efficientnet_global_rows", 10)