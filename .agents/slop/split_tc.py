#!/usr/bin/env python3
"""Split renderer/tc_ptx.bend into renderer/tc.bend + a thinner renderer/tc_ptx.bend.

`renderer/tc.py` (141 lines) is the tensor-core TABLE -- the `TensorCore` dataclass,
its six derived quantities and the fourteen arch tables -- and it is what
`renderer/tc_ptx.bend` (a port of `renderer/ptx.py`) CONSUMES. The two were merged
into one file; the 1:1 ruling separates them. `renderer/ptx.bend` imports
`tc_ptx.bend as P` and needs no repoint, because `tc_ptx.bend` stays and now imports
`tc.bend as T`.

Rows: 620 before the split. The old `main` printed `r_stage1() <> r_stage2()` as ONE
`IO.print`, so the union is the same 620 lines with one frame line between the two
stages -- which is the only byte `diff` will report.
"""
import os, sys, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qualify import declared, qualifier, hits, entries

ROOT = 'tinybendygrad/renderer'
ORIG = f'{ROOT}/tc_ptx.bend' if os.path.exists(f'{ROOT}/tc_ptx.bend') \
    else '.agents/slop/tc_ptx-pre-split.bend'
src = open(ORIG).read().split('\n')

def L(a, b):
    assert 1 <= a <= b <= len(src), f'BAD SLICE {a}..{b} of {len(src)}'
    return src[a-1:b]

HDR      = L(1, 70)      # the unit header + the imports
TC_BODY  = L(71, 1047)   # the gate primitives, the coord tables, `TensorCore`,
                         # `__post_init__`, the fourteen tables, `r_stage1`
PTX_BODY = L(1048, 1923) # `Px`, the emitters, the grid rows, `r_stage2`
MAIN     = L(1924, 1926)
MUT      = L(1928, len(src))
assert MAIN[0].startswith('def main'), MAIN[0]

IMPORTS = ['import Base', 'import ./../LAWS/spec.bend as S', 'import ./../uop/ops.bend as O']

shared = declared(TC_BODY)
print('tc.bend names tc_ptx.bend reaches for:', hits(shared, '\n'.join(PTX_BODY)))
PTX_BODY = qualifier(shared, 'T')(PTX_BODY)

TC_HDR = '''# renderer/tc.bend -- port of tinygrad/renderer/tc.py
#
# ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This was `renderer/tc_ptx.bend`,
# which held `tc.py` (141 lines) AND `ptx.py`; the 1:1 ruling separates them, and
# `renderer/tc_ptx.bend` is now the thinner half that CONSUMES this one. Nothing in
# `renderer/ptx.bend` needs repointing: it imports `tc_ptx.bend as P` and that file
# stays, with `import ./tc.bend as T` added.
#
# tc.py is the tensor-core TABLE: the `TensorCore` dataclass, the six quantities
# derived from it in `__post_init__` (`dims`, `used`, `base_upcast_axes`, `relabel`,
# `frag_coords`, `threads`), and the fourteen per-arch `TensorCore` values. Every one
# of those is a PURE FUNCTION of its eleven fields, which is why this half can be
# gated against CPython with no GPU, no driver and no codegen cache in the way -- 267
# of the 620 rows.
#
# THE MUTATION TABLE for tc.py's own rules (M1-M18) is in this file; the ptx.py half
# (M19-M50) is in `tc_ptx.bend`'s tail.
#
'''

PTX_HDR = '''# renderer/tc_ptx.bend -- port of tinygrad/renderer/ptx.py
#
# ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This file used to hold
# `renderer/ptx.py` AND `renderer/tc.py`; the 1:1 ruling separates them and
# `renderer/tc.bend` is the other half. Rows: 620 before the split, 620 after -- the
# old `main` printed `r_stage1() <> r_stage2()` as ONE `IO.print`, so the two files'
# union is the same 620 lines with one frame line between the stages, which is the
# only byte `diff` reports.
#
# THE TENSOR-CORE TABLES ARE IMPORTED, NOT COPIED: `renderer/ptx.py` calls
# `get_nvidia`/`get_amd` for its warp-level `wmma` and `mma` shapes, and those are
# `tc.py:96-141`. They live in `tc.bend` and every use here is `T.`. `renderer/ptx.bend`
# imports this file as `P` and is unaffected.
#
''' + '\n'.join(L(1048, 1058)) + '\n' + '''import Base
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../uop/ops.bend as O
import ./tc.bend as T

'''

# the measured-mutation block, filed by which half each entry mutates
MUT_ENTS = entries(MUT[4:], 1928)
ent_re = re.compile(r'\b(tc_pairs|get_nvidia|get_amd|get_gc|frag_coords|frag_a|frag_b|'
                    r'frag_c|axis_coords|base_upcast_axes|relabel|threads|used|mnk|'
                    r'Tc\.|pow2|supports_half|doesnt_support_half|tensor_cores|'
                    r'supported_dtypes|__post_init__)')

open(f'{ROOT}/tc.bend', 'w').write(
    TC_HDR + '\n'.join(HDR[13:66] + IMPORTS) + '\n\n' + '\n'.join(TC_BODY) + '\n' +
    'def main() -> IO(Unit):\n  do IO<Unit>:\n    IO.print(r_stage1())\n\n' +
    '\n'.join(l for e in MUT_ENTS if ent_re.search(' '.join(e)) for l in e))

open(f'{ROOT}/tc_ptx.bend', 'w').write(
    PTX_HDR + '\n'.join(PTX_BODY) + '\n' +
    'def main() -> IO(Unit):\n  do IO<Unit>:\n    IO.print(r_stage2())\n\n' +
    '\n'.join(l for e in MUT_ENTS if not ent_re.search(' '.join(e)) for l in e))

print('mutation entries filed: tc=%d tc_ptx=%d of %d' %
      (sum(1 for e in MUT_ENTS if ent_re.search(' '.join(e))),
       sum(1 for e in MUT_ENTS if not ent_re.search(' '.join(e))), len(MUT_ENTS)))
