# tinygrad broadcast numel, same shapes as p9-measure.bend.
# PYTHONPATH=. .venv/bin/python .agents/slop/ind/p9-tinygrad.py
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from tinygrad import Tensor
from tinygrad.uop.ops import UOp, Ops

def numel(shape):
    n = 1
    for s in shape:
        n *= s
    return n

def try_add(sa, sb):
    try:
        a = Tensor.ones(*sa) if sa else Tensor.ones(())
        b = Tensor.ones(*sb) if sb else Tensor.ones(())
        c = a + b
        return f"shape={c.shape} numel={numel(c.shape)} b={numel(sb) if sb else 1} ge={numel(c.shape) >= (numel(sb) if sb else 1)}"
    except Exception as e:
        return f"ERR {type(e).__name__}: {e}"

cases = [
    ("23_33", (2, 3), (3, 3)),
    ("13_23", (1, 3), (2, 3)),
    ("23_41", (2, 3), (4, 1)),
    ("20_11", (2, 0), (1, 1)),
    ("50_3", (5, 0), (3,)),
    ("2_22", (2,), (2, 2)),
    ("3_23", (3,), (2, 3)),
    ("5_37", (5,), (3, 7)),
    ("11_20", (1, 1), (2, 0)),
    ("0_1", (0,), (1,)),
    ("1_0", (1,), (0,)),
    ("scalar_33", (), (3, 3)),
    ("red0", None, None),
]
base = Tensor.ones(4, 5, 6).uop
print("reduce_n0", UOp(Ops.REDUCE, src=(base,), arg=(Ops.ADD, 0)).shape)
print("reduce_n1", UOp(Ops.REDUCE, src=(base,), arg=(Ops.ADD, 1)).shape)
print("reduce_n3", UOp(Ops.REDUCE, src=(base,), arg=(Ops.ADD, 3)).shape)
for name, sa, sb in cases:
    if sa is None:
        continue
    print(name, try_add(sa, sb))
