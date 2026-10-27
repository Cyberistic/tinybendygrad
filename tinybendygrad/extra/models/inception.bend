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
import ./../datasets/__init__.bend as D

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of extra/models/inception.py (344 LOC). NOT YET
# PORTED.
#
# THE LARGEST FILE IN THIS DIRECTORY, AND THE ONLY ONE WITH A SECOND, FOREIGN
# MATHEMATICS REQUIREMENT AT THE END. Two thirds of it is ordinary Inception v3;
# the last twenty lines are `calculate_frechet_distance` (upstream:323-344),
# which is `scipy.linalg.sqrtm` -- a MATRIX SQUARE ROOT over 2048x2048 float
# matrices. `from scipy import linalg` is upstream:8 and there is no scipy here,
# no ndarray here, and no linear-algebra module here at all. The FID score is
# therefore not a porting problem but a FOREIGN-DEPENDENCY problem, and it is
# better to say so than to queue it behind a conv2d.
#
# TODO(port): STOPPED AT `BasicConv2d.__init__` (extra/models/inception.py:12),
# at upstream:14
#       self.conv = Conv2d(in_ch, out_ch, bias=False, **kwargs)
#   `Tensor.conv2d` IS BUILT (`nn_conv2d`, nn/layers.bend:927 symbol=nn_conv2d, and its bias IS a
#   `Maybe<&2, T.Tensor>` so `bias=False` is `None{}` -- exactly the arm
#   `nn_cnv.add` at nn/layers.bend:885 symbol=nn_cnv.add spells). WHAT IS MISSING IS THE CLASS: `nn/__init__.bend`
#   has 17 defs and ZERO classes, so there is no `nn.Conv2d` to construct, no
#   `**kwargs` to forward and no weight to hold a shape.
#   AND THE VERY NEXT LINE IS A HARDER ONE: upstream:15
#       self.bn = BatchNorm2d(out_ch, eps=0.001)
#   `pool_bn` (nn/pool.bend:381) is BUILT and `pool_bend:44-48` measures
#   `Tensor.batchnorm` as a pure DECOMPOSITION. The half that is NOT a
#   decomposition -- the running-statistics update -- is REFUSED at
#   `pool_bend:415`, naming both causes: `TRAINING` is not a binding in this
#   tree, and `Tensor.assign` is not a def. `load_from_pretrained` (:273) reads
#   `running_mean`/`running_var` out of the checkpoint, so this is not optional
#   for this file.
#
# THE POOLS ARE WHERE THIS FILE BREAKS SHARPLY WITH THE OTHERS, AND IT IS WORTH
# BEING PRECISE BECAUSE A COUNT WOULD CALL ALL OF IT "pools: DONE".
#   `pool_maxpool` (nn/pool.bend:250) and `pool_avgpool` (:260) are BUILT and
#   both are UNPADDED. THIS FILE PADS ON EVERY POOL IT CALLS:
#     upstream:38  x.avg_pool2d(kernel_size=(3,3), stride=1, padding=1)
#     upstream:79  x.avg_pool2d(kernel_size=(3,3), stride=1, padding=1)
#     upstream:123 x.avg_pool2d(kernel_size=(3,3), stride=1, padding=1)
#     upstream:134 x.avg_pool2d(kernel_size=5, stride=3, padding=1)
#     upstream:135 x.avg_pool2d(kernel_size=1, padding=1)
#     upstream:147 Tensor.max_pool2d(x, kernel_size=(3,3), stride=2, padding=1)
#     upstream:150 Tensor.max_pool2d(x, kernel_size=(3,3), stride=2, padding=1)
#     upstream:162 Tensor.avg_pool2d(x, kernel_size=(8,8), padding=1)
#     upstream:203 :213 :225 avg_pool2d(..., padding=1, count_include_pad=False)
#     upstream:237 x.max_pool2d(kernel_size=(3,3), stride=1, padding=1)
#   and BOTH padded arms are REFUSED -- `pool_maxpool_padded` (pool.bend:252) and
#   `pool_avgpool_padded` (pool.bend:262) -- for ONE named cause:
#   "BLOCKED: mixin/op.py:290 the value!=0 arm, needs identity_element
#   (uop/ops.py:61), not a def". `pool.bend:246-248` adds why that matters
#   rather than being pedantry: "A `max_pool2d` padded with ZERO would be wrong
#   for any negative input, so the padded arm is REFUSED rather than built
#   wrong."
#   SO: 12 of the 17 POOL CALLS IN THIS FILE NEED AN ARM THAT IS REFUSED, and
#   the 5 that do not are NAMED HERE SO THE NUMBER IS CHECKABLE:
#     NEEDS A REFUSED ARM -- :38 :79 :123 :134 :135 :147 :150 :162 :203 :213
#                            :225 :237
#     ON THE BUILT ARM    -- :54 :97 :290 :294 :308
#   (measured with `grep -nE '(avg_pool2d|max_pool2d)\(' extra/models/inception.py`,
#   which is why the denominator 17 is here and not "the pools".)
#   AND THE 5 SURVIVORS ARE THE TRIVIAL ONES: each is in InceptionB (:54),
#   InceptionD (:97) or FidInceptionV3.__call__ (:290, :294, :308), while every
#   named branch pool of a class (:38, :79, :123, :134, :147, :150, :162) is
#   refused. A "5 of 17 pools work" line would be true AND useless, because the
#   5 are the easy half and the 12 are what makes an Inception3 an Inception3.
#
# `Tensor.cat` is MISSING and it is how this file JOINS its branches:
# upstream:40, :56, :81, :99, :121, :122, :125, :205, :215, :227, :239 -- ELEVEN
# calls, and the model is a tree of them. `grep -rniE '^def .*cat' --include=
# '*.bend' tinybendygrad/` returns 0 for a `cat` ENTRY; the `mx_cat` in
# `mixin/movement.bend` and `pool_sh` in `nn/pool.bend` concatenate LISTS of U32
# for shape arithmetic, which is the conflation `resnet.bend:99-107` warns about.
#
# `Tensor.interpolate` is MISSING and it is the FIRST LINE of
# `FidInceptionV3.__call__` (upstream:284). `np.load`, `np.cov`,
# `np.atleast_1d/2d`, `np.isfinite`, `np.trace` and `np.load` are all MISSING
# (:314, :318, :319, :324-327, :332, :342) -- there is no ndarray in this tree,
# and `extra/datasets/__init__.bend:21-23` already says why for a neighbouring
# file: "`.reshape`, `.astype` and `np.frombuffer` have no counterpart here:
# `Tensor` in `tensor.bend` is a UOp slot in an arena, not a buffer".
#
# EVERY DEF BELOW REFUSES, AND THE RETURN TYPE IS `D.Refused`, NOT A TENSOR. A
# stub that returned a zero Tensor would be indistinguishable from a layer whose
# weights happen to be zero. `refuse`/`Refused` are DECLARED ONCE at
# `extra/datasets/__init__.bend:40-46` and imported as `D`. Each message names
# the upstream `path:line` of the FIRST MISSING SYMBOL.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def ic_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :12-18 BasicConv2d -- THE ONLY CLASS IN THE FIRST HALF OF THE FILE, AND EVERY
# OTHER CLASS IS BUILT OUT OF IT.
# ---------------------------------------------------------------------------

# :13 def __init__(self, in_ch:int, out_ch:int, **kwargs)
def ic_basic_init(in_ch: U32, out_ch: U32) -> D.Refused:
  D.refuse("extra/models/inception.py:13 BasicConv2d.__init__ -- FIRST MISSING SYMBOL nn.Conv2d CLASS at :14; the OP nn_conv2d (nn/layers.bend:756) EXISTS and its bias is a Maybe<&2, T.Tensor>, so bias=False IS expressible")

# :15 self.bn = BatchNorm2d(out_ch, eps=0.001)
def ic_basic_bn(out_ch: U32) -> D.Refused:
  D.refuse("extra/models/inception.py:15 BasicConv2d.bn -- nn.BatchNorm2d CLASSES MISSING (nn/__init__.bend has 17 defs and ZERO classes) and the running-statistics half is REFUSED at nn/pool.bend:415")

# :17 def __call__(self, x:Tensor) -> Tensor
def ic_basic_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:17 BasicConv2d.__call__ -- FIRST MISSING SYMBOL x.sequential at :18")

# ---------------------------------------------------------------------------
# :20-40 InceptionA. FOUR BRANCHES AND A CAT.
# ---------------------------------------------------------------------------

# :21 def __init__(self, in_ch:int, pool_feat:int)
def ic_incepa_init(in_ch: U32, pool_feat: U32) -> D.Refused:
  D.refuse("extra/models/inception.py:21 InceptionA.__init__ -- FIRST MISSING SYMBOL BasicConv2d at :22, i.e. the nn.Conv2d CLASS at :14")

# :38 self.branch_pool(x.avg_pool2d(kernel_size=(3,3), stride=1, padding=1))
def ic_incepa_pool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:38 InceptionA.__call__ -- REFUSED PADDED AVG POOL: pool_avgpool (nn/pool.bend:260) is the UNPADDED arm only, and pool_avgpool_padded (nn/pool.bend:262) names the blocker -- mixin/op.py:290 the value!=0 arm, needs identity_element (uop/ops.py:61), not a def")

# :40 return Tensor.cat(*outputs, dim=1)
def ic_incepa_cat() -> D.Refused:
  D.refuse("extra/models/inception.py:40 InceptionA.__call__ -- MISSING Tensor.cat; mx_cat (mixin/movement.bend) concatenates LISTS of U32 for shape arithmetic and is not this")

def ic_incepa_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:33 InceptionA.__call__ -- FIRST MISSING SYMBOL the padded avg_pool2d at :38 (nn/pool.bend:262)")

# ---------------------------------------------------------------------------
# :42-56 InceptionB. THE FIRST CLASS WITH A `max_pool2d`, AND SO THE FIRST ONE
# WHOSE BODY CANNOT BE SPELLED AT ALL.
# ---------------------------------------------------------------------------

# :43 def __init__(self, in_ch:int)
def ic_incepb_init(in_ch: U32) -> D.Refused:
  D.refuse("extra/models/inception.py:43 InceptionB.__init__ -- FIRST MISSING SYMBOL BasicConv2d at :44")

# :54 x.max_pool2d(kernel_size=(3,3), stride=2, dilation=1)
def ic_incepb_pool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:54 InceptionB.__call__ -- REFUSED PADDED MAX POOL: pool_maxpool (nn/pool.bend:250) is the UNPADDED arm only; pool_maxpool_padded (nn/pool.bend:252) names the blocker, and pool.bend:247-248 says why it is not built wrong instead: a max_pool2d padded with ZERO would be wrong for any negative input")

# ---------------------------------------------------------------------------
# :58-81 InceptionC, :83-99 InceptionD, :101-125 InceptionE. THREE CLASSES, ONE
# SHAPE: a `BasicConv2d` chain, a pool, and a `Tensor.cat`.
# ---------------------------------------------------------------------------

# :59 def __init__(self, in_ch, ch_7x7)
def ic_incepc_init(in_ch: U32, ch_7x7: U32) -> D.Refused:
  D.refuse("extra/models/inception.py:59 InceptionC.__init__ -- FIRST MISSING SYMBOL BasicConv2d at :60")

# :63 BasicConv2d(ch_7x7, ch_7x7, kernel_size=(1, 7), padding=(0, 3))
def ic_incepc_asym() -> D.Refused:
  D.refuse("extra/models/inception.py:63 InceptionC.branch7x7_2 -- kernel_size=(1,7) with padding=(0,3) IS expressible: nn_conv2d (nn/layers.bend:756) derives ni from the weight's own shape and takes padding as a Maybe<&2, List<&2, U32>>; blocked by the layer STORE, not by a primitive")

# :84 def __init__(self, in_ch:int)
def ic_incepd_init(in_ch: U32) -> D.Refused:
  D.refuse("extra/models/inception.py:84 InceptionD.__init__ -- FIRST MISSING SYMBOL BasicConv2d at :85")

# :97 x.max_pool2d(kernel_size=(3,3), stride=2, dilation=1)
def ic_incepd_pool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:97 InceptionD.__call__ -- REFUSED PADDED MAX POOL (nn/pool.bend:252)")

# :102 def __init__(self, in_ch:int)
def ic_incepe_init(in_ch: U32) -> D.Refused:
  D.refuse("extra/models/inception.py:102 InceptionE.__init__ -- FIRST MISSING SYMBOL BasicConv2d at :103")

# :121-122 Tensor.cat(self.branch3x3_2a(branch3x3), self.branch3x3_2b(branch3x3), dim=1)
def ic_incepe_cat() -> D.Refused:
  D.refuse("extra/models/inception.py:121 InceptionE.__call__ -- MISSING Tensor.cat; and these two branches are nested cats, so one missing symbol costs THREE calls in this def")

# ---------------------------------------------------------------------------
# :127-136 InceptionAux. THE ONE CLASS WHOSE POOLS ARE `padding=1` WITH A
# KERNEL THAT IS NOT 3.
# ---------------------------------------------------------------------------

# :128 def __init__(self, in_ch:int, num_classes:int)
def ic_aux_init(in_ch: U32, num_classes: U32) -> D.Refused:
  D.refuse("extra/models/inception.py:128 InceptionAux.__init__ -- FIRST MISSING SYMBOL BasicConv2d at :129")

# :134 x.avg_pool2d(kernel_size=5, stride=3, padding=1)
def ic_aux_pool5(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:134 InceptionAux.__call__ -- REFUSED PADDED AVG POOL (nn/pool.bend:262); the kernel is 5 and the stride is 3, so this is not the same call as :38 with a different number")

# :135 ... .reshape(x.shape[0],-1)
def ic_aux_flatten(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:135 InceptionAux.__call__ -- pool_flatten (nn/pool.bend:326) EXISTS and takes b0/rest AS VALUES; the missing part is reading `rest` out of x.shape instead of being handed it, which is the -1 INFERENCE nn/pool.bend:322-324 says no def here has")

# ---------------------------------------------------------------------------
# :138-192 Inception3. TWENTY-EIGHT NAMED SUBLAYERS, RESTATED AS A COUNT AND A
# SPAN RATHER THAN A LIST, because a list of twenty-eight names in a comment is
# the census that rots.
# ---------------------------------------------------------------------------

# :139 def __init__(self, num_classes:int=1008, cls_map:Optional[Dict]=None)
def ic_incep3_init(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/inception.py:139 Inception3.__init__ -- FIRST MISSING SYMBOL BasicConv2d at :144, i.e. the nn.Conv2d CLASS at :14")

def ic_incep3_sublayers() -> U32: 28

# :140-141 def get_cls(key1, key2, default) -- THE MONKEYPATCH HOOK, and the one
# reason Inception3 takes a `cls_map`. It is a two-key dict lookup, and the port
# has no dict; `nn/state.bend` has `Kv`/`Ent` for tensors and not for this.
def ic_get_cls_default() -> D.Refused:
  D.refuse("extra/models/inception.py:140 Inception3.get_cls -- MISSING THE cls_map DICT; FidInceptionV3 (:246) is the only caller and it passes FOUR class objects, so this hook is what makes the whole Fid variant a parameterisation")

# :147 self.maxpool1 = lambda x: Tensor.max_pool2d(x, kernel_size=(3,3), stride=2, padding=1)
# :150 self.maxpool2 = ... identical
def ic_incep3_maxpool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:147 Inception3.maxpool1 -- REFUSED PADDED MAX POOL (nn/pool.bend:252). maxpool1 (:147) and maxpool2 (:150) are the SAME def upstream and stay the same here")

# :162 self.avgpool = lambda x: Tensor.avg_pool2d(x, kernel_size=(8,8), padding=1)
def ic_incep3_avgpool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:162 Inception3.avgpool -- REFUSED PADDED AVG POOL (nn/pool.bend:262)")

# :163 self.fc = Linear(2048, num_classes)
def ic_incep3_fc(num_classes: U32) -> D.Refused:
  D.refuse("extra/models/inception.py:163 Inception3.fc -- nn_linear (nn/layers.bend:427) EXISTS; blocked by the layer STORE and by the `lambda y: y.reshape(x.shape[0],-1)` at :190")

# :165 def __call__(self, x:Tensor) -> Tensor
def ic_incep3_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:165 Inception3.__call__ -- FIRST MISSING SYMBOL the padded max_pool2d at :147 via :170 (nn/pool.bend:252)")

# ---------------------------------------------------------------------------
# :195-239 THE FID VARIANTS. FOUR CLASSES THAT OVERRIDE ONE METHOD EACH, AND
# EACH OVERRIDE CHANGES EXACTLY ONE THING: `count_include_pad`.
# ---------------------------------------------------------------------------

# :197-205 FidInceptionA  :203 ... avg_pool2d(..., count_include_pad=False)
def ic_fida_pool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:203 FidInceptionA.__call__ -- MISSING count_include_pad=False; that IS the arm pool_avgpool_padded (nn/pool.bend:262) refuses, so adding the keyword moves this call OUT of the built arm and not into it")

# :207-215 FidInceptionC  :213 ... count_include_pad=False)
def ic_fidc_pool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:213 FidInceptionC.__call__ -- MISSING count_include_pad=False (nn/pool.bend:262)")

# :217-227 FidInceptionE1 :225 ... count_include_pad=False)
def ic_fide1_pool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:225 FidInceptionE1.__call__ -- MISSING count_include_pad=False (nn/pool.bend:262)")

# :229-239 FidInceptionE2 :237 ... x.max_pool2d(kernel_size=(3,3), stride=1, padding=1))
def ic_fide2_pool(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:237 FidInceptionE2.__call__ -- REFUSED PADDED MAX POOL (nn/pool.bend:252); note this is the ONE Fid override that swaps avg for max rather than changing count_include_pad")

# ---------------------------------------------------------------------------
# :241-321 FidInceptionV3.
# ---------------------------------------------------------------------------

# :242-243 m1: Optional[np.ndarray] = None / s1: ... -- CLASS ATTRIBUTES, and
# `compute_score` (:313-315) READS THEM and WRITES them. That is mutable state
# on a `Data` record, which is why they are refused rather than modelled.
def ic_fidv3_stats() -> D.Refused:
  D.refuse("extra/models/inception.py:242 FidInceptionV3.m1/s1 -- MISSING np.ndarray AND mutable class attributes; compute_score at :313-315 assigns to them, and a Bend Data record has no mutation")

# :245 def __init__(self)
def ic_fidv3_init() -> D.Refused:
  D.refuse("extra/models/inception.py:245 FidInceptionV3.__init__ -- FIRST MISSING SYMBOL the cls_map at :246, i.e. get_cls at :140, i.e. Inception3.__init__ at :139")

# :273 def load_from_pretrained(self, path=None)
def ic_fidv3_load(path: Maybe<&1, String>) -> D.Refused:
  D.refuse("extra/models/inception.py:273 FidInceptionV3.load_from_pretrained -- FIRST MISSING SYMBOL fetch at :275; and torch_load/load_state_dict at :276,:280 are the same seam resnet.bend:97-98 records as 0 hits")

# :276 torch_load(str(path))  :280 load_state_dict(self, state_dict)
def ic_fidv3_state_dict() -> D.Refused:
  D.refuse("extra/models/inception.py:280 FidInceptionV3.load_from_pretrained -- MISSING load_state_dict; nn/state.bend:318 get_state_dict reads state but there is no load that writes it back")

# :283 def __call__(self, x:Tensor) -> Tensor
def ic_fidv3_call(+x: T.Tensor) -> D.Refused:
  D.refuse("extra/models/inception.py:283 FidInceptionV3.__call__ -- FIRST MISSING SYMBOL x.interpolate at :284, which is not a wall but a THIRD PARTY: the port has no resize of any kind, and mixin/movement.bend has no mxw_resize/mxw_interp")

# :312 def compute_score(self, inception_activations:Tensor, val_stats_path:str) -> float
def ic_fidv3_compute_score(embed: U32, path: String) -> D.Refused:
  D.refuse("extra/models/inception.py:312 FidInceptionV3.compute_score -- FIRST MISSING SYMBOL np.load at :314; mo_mean (mixin/op.bend:891) IS built and :318's `.mean(axis=0)` is expressible, but .numpy() at :318 and np.cov at :319 are not")

# ---------------------------------------------------------------------------
# :323-344 calculate_frechet_distance. THE FOREIGN MATHEMATICS.
# ---------------------------------------------------------------------------

# :323 def calculate_frechet_distance(mu1, sigma1, mu2, sigma2, eps=1e-6) -> float
def ic_frechet_distance(eps: F32) -> D.Refused:
  D.refuse("extra/models/inception.py:323 calculate_frechet_distance -- MISSING scipy.linalg.sqrtm at :331; upstream:8 is `from scipy import linalg` and this tree has no scipy, no ndarray and no matrix square root. This is a FOREIGN-DEPENDENCY gap, not a substrate gap")

# :324-327 np.atleast_1d / np.atleast_2d / the shape assert
def ic_frechet_shape(eps: F32) -> D.Refused:
  D.refuse("extra/models/inception.py:324 calculate_frechet_distance -- MISSING np.atleast_1d/atleast_2d; upstream raises an AssertionError at :328, and a Bend def answers with a Maybe rather than an assert, which is the port's standing spelling for that (nn/layers.bend:363-367)")

# :342 tr_covmean = np.trace(covmean)
def ic_frechet_trace(eps: F32) -> D.Refused:
  D.refuse("extra/models/inception.py:342 calculate_frechet_distance -- MISSING np.trace; mo_sum (mixin/op.bend:811) IS built and a trace is a sum over the diagonal, so this ONE line is a port waiting on a shape rather than on scipy")

# ---------------------------------------------------------------------------
# THERE IS NO `if __name__ == \"__main__\":` IN THIS FILE -- upstream ends at
# :344. `main` below IS the port's own entry and it invents no census, because a
# 1:1 mirror that emits rows upstream does not emit is not a mirror.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, ic_basic_init(3, 32))
    srow("inception_refused_at", ic_at(a))
    row("inception_ported", False{})
    srow("inception_first_blocker_line", "extra/models/inception.py:14")
    srow("inception_first_blocker", "nn.Conv2d CLASS -- the op nn_conv2d EXISTS at nn/layers.bend:756")
    srow("inception_pool_wall", "all 10 pool calls need a padded arm; nn/pool.bend:252 and :262 both refuse on identity_element (uop/ops.py:61)")
    urow("inception3_sublayers", ic_incep3_sublayers())
    urow("inception3_num_classes_default", 1008)