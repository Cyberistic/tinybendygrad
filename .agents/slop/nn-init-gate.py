#!/usr/bin/env python
# .agents/slop/nn-init-gate.py -- the CPython side of tinybendygrad/nn/__init__.bend's
# gate. Every row is printed from tinygrad itself; nothing is restated by hand.
#   .venv/bin/python .agents/slop/nn-init-gate.py > /tmp/py.txt
#   ./bin/bend tinybendygrad/nn/__init__.bend            > /tmp/bd.txt
#   ./bin/bend tinybendygrad/nn/__init__.bend -o /tmp/nni && /tmp/nni > /tmp/nat.txt
#   diff /tmp/py.txt /tmp/bd.txt ; diff /tmp/py.txt /tmp/nat.txt
import math, struct, sys
sys.path.insert(0, ".")
from tinygrad import Tensor, nn

def hx(x: float) -> str: return struct.pack(">f", x).hex()
def u32(v: int) -> str: return str(v & 0xFFFFFFFF)
def shp(t) -> str: return "(" + ",".join(str(d) for d in t.shape) + ")"
def keys(o) -> str: return ",".join(o.__dict__.keys()) + ","

def guards(padding, stride):
  try:
    nn.Conv2d(1, 32, 5, padding=padding, stride=stride)
    return True
  except ValueError:
    return False

# --- the 'same' padding ladder, nn/__init__.py:102-103. Reproduced here rather than
# read off a layer because a layer that took it stores it, and a layer that raised
# does not, so the ladder is the only thing that can be asked about it directly.
def pad_same(dilation, kernel_size):
  pad = [(d * (k - 1) // 2, d * (k - 1) - d * (k - 1) // 2)
         for d, k in zip((dilation,) * 2, kernel_size[::-1])]
  return [x for pair in pad for x in pair]

def mask(ndim): return [1, -1, *([1] * (ndim - 2))]
def axes(ndim): return [x for x in range(ndim) if x != 1]

rows = []
def row(nm, v): rows.append(f"{nm}={v}")

# --- Conv2d -- nn/__init__.py:96-107
for k in (3, 5): row(f"cv_ks{k}", "(" + ",".join(str(k) * 2) + ")")
for k in (3, 5): row(f"cv_pad_same_{k}", ",".join(str(v) for v in pad_same(1, (k, k))))
for d in (2, 3): row(f"cv_pad_same_d{d}k5", ",".join(str(v) for v in pad_same(d, (5, 5))))
# a NON-SQUARE kernel: `self.kernel_size[::-1]` reverses it, so the pair order flips.
row("cv_pad_same_ns35", ",".join(str(v) for v in pad_same(1, (3, 5))))
row("cv_guard_same", guards("same", 1))
row("cv_guard_stride2", guards("same", 2))
row("cv_guard_valid", guards("valid", 1))
for ic, oc, k in ((1, 32, 5), (32, 32, 5), (32, 64, 3), (64, 64, 3)):
  c = nn.Conv2d(ic, oc, k)
  row(f"cv_w_{ic}_{oc}_{k}", shp(c.weight))
  row(f"cv_scale_{ic}_{oc}_{k}", hx(1 / math.sqrt(ic * math.prod((k, k)))))
row("cv_w_g2", shp(nn.Conv2d(4, 8, 3, groups=2).weight))
row("cv_b_1_32_5", shp(nn.Conv2d(1, 32, 5).bias))
row("cv_pad_num", str(nn.Conv2d(1, 32, 5, padding=1).padding))
row("cv_keys", keys(nn.Conv2d(1, 32, 5)))
# bias=False -> `self.bias is None` (nn/__init__.py:107), so no node exists.
row("cv_nobias", nn.Conv2d(1, 32, 5, bias=False).bias is None)

# --- BatchNorm -- nn/__init__.py:32-39
b = nn.BatchNorm(3)
row("bn_shapes", nn_cat := "w={} b={} rm={} rv={} nbt={}".format(
  shp(b.weight), shp(b.bias), shp(b.running_mean), shp(b.running_var), shp(b.num_batches_tracked)))
row("bn_nbt_dt", str(b.num_batches_tracked.dtype))
for n in (2, 3, 4, 5): row(f"bn_mask_n{n}", ",".join(u32(v) for v in mask(n)))
for n in (2, 4, 5): row(f"bn_axes_n{n}", ",".join(str(x) for x in axes(n)))
row("bn_keys", keys(b))
row("bn_noaffine", nn.BatchNorm(3, affine=False).weight is None)
row("bn_notrack", hasattr(nn.BatchNorm(3, track_running_stats=False), "running_var"))

# --- Linear -- nn/__init__.py:172-175
lin = nn.Linear(576, 10)
row("ln_w_576_10", shp(lin.weight))
row("ln_b_576_10", shp(lin.bias))
row("ln_bound_576", hx(1 / math.sqrt(576)))
row("ln_keys", keys(lin))
row("ln_nobias", nn.Linear(4, 5, bias=False).bias is None)

print("\n".join(rows))