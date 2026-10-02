#!/usr/bin/env python3
"""UPSTREAM COMMENT RECALL: of the comment lines tinygrad ships in the file this
bend file ports, how many appear in the bend file at all?  This is the number
that says whether rule (1) 'upstream comments stay verbatim' has anything to act
on."""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from upstream import norm, content_tokens

MAP = {
 'nn/__init__.bend': 'tinygrad/nn/__init__.py',
 'nn/datasets.bend': 'tinygrad/nn/datasets.py',
 'nn/onnx.bend': 'tinygrad/nn/onnx.py',
 'nn/optim.bend': 'tinygrad/nn/optim.py',
 'nn/state.bend': 'tinygrad/nn/state.py',
 'nn/torch.bend': 'tinygrad/nn/torch.py',
 'mixin/creation.bend': 'tinygrad/mixin/creation.py',
 'mixin/dtype.bend': 'tinygrad/mixin/dtype.py',
 'mixin/elementwise.bend': 'tinygrad/mixin/elementwise.py',
 'mixin/gradient.bend': 'tinygrad/mixin/gradient.py',
 'mixin/movement.bend': 'tinygrad/mixin/movement.py',
 'mixin/op.bend': 'tinygrad/mixin/op.py',
 'mixin/rand.bend': 'tinygrad/mixin/rand.py',
 'mixin/reduce.bend': 'tinygrad/mixin/reduce.py',
 'tensor.bend': 'tinygrad/tensor.py',
 'device.bend': 'tinygrad/device.py',
 'engine/jit.bend': 'tinygrad/engine/jit.py',
 'engine/realize.bend': 'tinygrad/engine/realize.py',
 'engine/worker.bend': 'tinygrad/engine/worker.py',
 'schedule/__init__.bend': 'tinygrad/schedule/__init__.py',
 'schedule/allreduce.bend': 'tinygrad/schedule/allreduce.py',
 'schedule/indexing.bend': 'tinygrad/schedule/indexing.py',
 'schedule/memory.bend': 'tinygrad/schedule/memory.py',
 'schedule/multi.bend': 'tinygrad/schedule/multi.py',
 'schedule/prepare.bend': 'tinygrad/schedule/prepare.py',
 'schedule/rangeify.bend': 'tinygrad/schedule/rangeify.py',
}
ROOT = '.agents/slop/commentpass/before/tinybendygrad/'

def main():
    tot_up = tot_hit = 0
    print(f"{'bend file':28s} {'py cmt':>7s} {'substr':>7s} {'>=15ch':>7s} {'>=3tok':>7s}")
    for b, p in sorted(MAP.items()):
        with open(p, encoding='utf-8', errors='replace') as fh:
            upl = [norm(l) for l in fh.read().split('\n') if l.strip().startswith('#')]
        with open(ROOT + b, encoding='utf-8', errors='replace') as fh:
            body = norm(fh.read())
        hits = [u for u in upl if u and u in body]
        sub = sum(1 for u in upl if len(u) >= 8 and u in body)
        sig = sum(1 for u in upl if len(u) >= 15 and len(content_tokens(u)) >= 3)
        tot_up += len(upl); tot_hit += len(hits)
        print(f"{b:28s} {len(upl):7d} {sub:7d} {sig:7d} {len(hits):7d}")
    print(f"{'TOTAL':28s} {tot_up:7d} {'':7s} {'':7s} {tot_hit:7d}   "
          f"({100.0*tot_hit/max(1,tot_up):.1f}% of tinygrad comment lines appear verbatim-ish)")

if __name__ == '__main__':
    main()