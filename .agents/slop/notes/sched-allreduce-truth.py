"""Truth for schedule/allreduce.py -- the SELECTION and the CHUNK arithmetic."""
import sys, itertools, functools
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
from tinygrad.helpers import all_int, prod, getenv, RING, ALL2ALL, ALLREDUCE_CAST
from tinygrad.uop.ops import Ops
from tinygrad.dtype import dtypes

print("== flags ==")
print("RING", RING, "ALL2ALL", ALL2ALL, "ALLREDUCE_CAST", ALLREDUCE_CAST)
print("ALLREDUCE_NODE_NDEVS", getenv("ALLREDUCE_NODE_NDEVS", 0))
print("RING_ALLREDUCE_THRESHOLD", getenv("RING_ALLREDUCE_THRESHOLD", 256_000))

def select(ndev, shape, ring, all2all, thr=256_000):
  """allreduce.py:13-15, verbatim with the flags as parameters."""
  numel = prod(shape)
  concrete = all_int(shape)
  use_all2all = concrete and (all2all >= 2 or (ndev > 2 and numel > thr and all2all >= 1))
  use_ring = concrete and not use_all2all and (ring >= 2 or (ndev > 2 and numel > thr and ring >= 1))
  mode = "ALL2ALL" if use_all2all else "RING" if use_ring else "NAIVE"
  return mode, use_all2all, use_ring, concrete

print("== selection: mode for (ndev, numel, RING, ALL2ALL) ==")
for ndev, shape, ring, a2 in [(2, (100,), 1, 0), (4, (100,), 1, 0), (4, (300000,), 1, 0),
                             (4, (300000,), 0, 0), (4, (300000,), 0, 1), (4, (300000,), 0, 2),
                             (4, (300000,), 2, 0), (4, (300000,), 2, 2), (3, (300000,), 1, 0),
                             (4, (s for s in [1, 2]), 1, 0)]:
  try:
    print(f"  ndev={ndev} shape={shape} RING={ring} ALL2ALL={a2} ->", select(ndev, shape, ring, a2)[:3])
  except Exception as e:
    print(f"  ndev={ndev} shape={shape} RING={ring} ALL2ALL={a2} -> raises {type(e).__name__}")

print("== chunking: allreduce.py:36-38 ==")
def chunks(numel, ndev):
  factor = next((f for f in [32, 16, 8, 4, 2] if numel % f == 0), 1)
  base, left = divmod(numel // factor, ndev)
  cs = list(itertools.pairwise(itertools.accumulate([(base + 1) * factor] * left + [base * factor] * (ndev - left), initial=0)))
  return factor, base, left, cs

for numel, ndev in [(100, 4), (128, 4), (96, 4), (64, 4), (1000, 3), (100, 7), (256, 4), (320, 8)]:
  f, b, l, cs = chunks(numel, ndev)
  print(f"  numel={numel} ndev={ndev} factor={f} base={b} left={l} n={len(cs)} chunks={cs}")

print("== the node-local branch, allreduce.py:22-28 ==")
def hdev_branch(ndev, numel, hdev, shape):
  if not (hdev > 0 and ndev % hdev == 0): return None
  boxes = [range(b, b + hdev) for b in range(0, ndev, hdev)]
  cs = [(numel * k // hdev, numel * (k + 1) // hdev) for k in range(hdev)]
  return len(boxes), hdev, cs
for ndev, numel, hdev in [(8, 1000, 4), (8, 1000, 2), (8, 1000, 3), (4, 100, 4)]:
  print(f"  ndev={ndev} numel={numel} hdev={hdev} ->", hdev_branch(ndev, numel, hdev, None))

print("== ALLREDUCE_CAST, allreduce.py:116 ==")
print("  bfloat16, half in the cast set:", dtypes.bfloat16 in (dtypes.bfloat16, dtypes.half), dtypes.half in (dtypes.bfloat16, dtypes.half))