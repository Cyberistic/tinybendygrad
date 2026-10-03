# Expectations for spec.bend's drop_n. There is no CPython drop_n.
# These rows are tinygrad's own _shape, not a reimplementation of the slice.
#
#   PYTHONPATH=. python3 .agents/slop/ind/dropn-oracle.py
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from tinygrad import Tensor
from tinygrad.uop.ops import Ops, UOp

base = Tensor.ones(4, 5, 6).uop
red0 = UOp(Ops.REDUCE, src=(base,), arg=(Ops.ADD, 0))
red1 = UOp(Ops.REDUCE, src=(base,), arg=(Ops.ADD, 1))
idx = base.index(UOp.const(0))

print(f"reduce_n0={red0.shape}")
print(f"reduce_n1={red1.shape}")
print(f"index_arity1={idx.shape}")
print(f"index_arity1_rank={len(idx.shape)}")
print(f"index_nidx={len(idx.src) - 1}")
