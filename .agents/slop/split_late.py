#!/usr/bin/env python3
"""Split codegen/late.bend into codegen/late/{linearizer,regalloc,gater}.bend.

ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. Every def body moves VERBATIM, so
a row is a row: the three files' rows CONCATENATE IN PYTHON'S ORDER to the 128 the
one file printed, which is the invariant `.agents/slop/late-gate.sh` checks.

After the split `codegen/late.bend` is GONE -- that deletion is the point -- so this
script reads the pre-split snapshot, which is checked in beside it.
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qualify import declared, qualifier, hits

ROOT = 'tinybendygrad/codegen'
ORIG = f'{ROOT}/late.bend' if os.path.exists(f'{ROOT}/late.bend') \
    else '.agents/slop/late-pre-split.bend'
src = open(ORIG).read().split('\n')

def L(a, b):
    assert 1 <= a <= b <= len(src), f'BAD SLICE {a}..{b} of {len(src)}'
    return src[a-1:b]

os.makedirs(f'{ROOT}/late', exist_ok=True)

SHARED = L(189, 374)     # RaTb/RaEn/tb_*/u32_none/b2u/at/nlen/range_tuple/u32s
LIN    = L(375, 1838)    # lt_*, cfg_*, se_*
REG    = L(1839, 3143)   # ra_*, rw_*
GAT    = L(3154, 3316)   # gt_*
MUTTAB = L(3393, len(src))  # the mutation table + the blind spots (all regalloc rows)

# `main`'s body, cut on LINES not on patterns so the interleaved comments follow the
# rows they describe.
M_LIN = L(3319, 3365)
M_REG = L(3366, 3376)
M_GAT = L(3377, 3391)
assert sum(len(x) for x in (M_LIN, M_REG, M_GAT)) == len(L(3319, 3391))

sub_names   = declared(LIN)
shared_names = declared(SHARED)

# THE 1:1 FUNCTION PORTS ARE RENAMED TO THE UPSTREAM NAMES by this split, because the
# split is the moment the file's identity is fixed and the port now has somewhere to
# BE the upstream thing. Three of them, all 1:1 with no judgement call:
#     linearize     was lt_linearize
#     do_split_ends was se_split
#     move_where_load was gt_w.*        (gater.py:5-7)
# NOT renamed, on purpose: `rw_one` is NOT `regalloc_rewrite` -- it is one row's
# projection of that function -- and `gt_mwl` builds the whole WHERE-load trace, not
# the alt value. Renaming a def to a name it is not the port of would be worse than
# the prefix the ruling complains about.
RENAME = [(r'\blt_linearize\b', 'linearize'), (r'\bse_split\b', 'do_split_ends'),
          (r'\bgt_w\b(?![\w.])', 'move_where_load'), (r'\bgt_w\.', 'move_where_load.')]
def renamed(lines):
    out = []
    for l in lines:
        for rx, rep in RENAME: l = re.sub(rx, rep, l)
        out.append(l)
    return out

LIN, M_LIN, GAT = renamed(LIN), renamed(M_LIN), renamed(GAT)

print('linearizer names regalloc reaches for:',
      hits(shared_names + sub_names, '\n'.join(REG + M_REG)))
print('linearizer names gater reaches for:', hits(sub_names, '\n'.join(GAT + M_GAT)))

q_reg = qualifier(shared_names + sub_names, 'LT')
q_gat = qualifier(sub_names, 'LT')
REG, M_REG = q_reg(REG), q_reg(M_REG)
GAT, M_GAT = q_gat(GAT), q_gat(M_GAT)

def main_of(rows):
    """the LAST row is UNBOUND: it is the `do IO<Unit>` block's final expression, so
    there is no trailing IO.print("") and the file ends with that row's newline --
    exactly what the oracle's `print("\\n".join(out))` does."""
    last = re.sub(r'^(\s*)\w+(\s*:\s*Unit\s*<-\s*)', r'\1', rows[-1].strip())
    body = '\n'.join(rows[:-1])
    note = ("    # THE LAST ROW IS UNBOUND and IS the `do IO<Unit>` block's final\n"
            "    # expression, so there is no trailing `IO.print(\"\")` and the file ends\n"
            "    # with the LAST ROW's newline -- what the oracle's `print(\"\\n\".join(out))`\n"
            "    # does. A trailing empty line is a one-line diff a reader must notice.\n")
    return f'def main() -> IO(Unit):\n  do IO<Unit>:\n{body}\n{note}    {last}\n'

# ---------------------------------------------------------------- linearizer
lin_hdr = '''# codegen/late/linearizer.bend -- port of tinygrad/codegen/late/linearizer.py
#
# ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This was `codegen/late.bend`
# until the 1:1 ruling; `codegen/late/regalloc.bend` and `codegen/late/gater.bend` are
# the other two slices, the rows are the SAME rows, and 128 before the split is 128
# across the three after it.
#
# THIS FILE ALSO CARRIES THE SHARED SUBSTRATE. `linearizer.py` needs an assoc list
# (`out_degree`, `priorities`, `nkey`, `CFGContext.deps`, `CFGContext.nesting`) and so
# does every other table in the lowerer, and Bend's `Map` is string-keyed only while
# all seven of regalloc's dicts are `U32`-keyed -- so ONE `RaTb` serves them all. It
# has no upstream counterpart, so it lives in the FIRST of the three files in Python's
# order and `regalloc.bend` imports it as `LT`. `gater.bend` needs none of it.
#
# THE DEF-BY-DEF MAP FOR ALL THREE FILES follows, whole; each of the other two points
# back at it rather than repeating it.
#
''' + '\n'.join(L(4, 82)) + '\n' + '\n'.join(L(83, 131)) + '\n' + '\n'.join(L(153, 158)) + '''
# The per-UOP gate shape and the two identity rows are described here; regalloc's
# half of the same paragraph is in `regalloc.bend`'s header.
#
import Base
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../uop/ops.bend as O
import ./../../uop/fold.bend as F
import ./../kernel.bend as KER

'''
open(f'{ROOT}/late/linearizer.bend', 'w').write(
    lin_hdr + '\n'.join(SHARED) + '\n\n' + '\n'.join(LIN) + '\n' + main_of(M_LIN))

# ---------------------------------------------------------------- regalloc
reg_hdr = '''# codegen/late/regalloc.bend -- port of tinygrad/codegen/late/regalloc.py
#
# ONE OF THREE SLICES. `codegen/late.bend` held `linearizer.py`, `regalloc.py` and
# `gater.py` together and the 1:1 ruling gives each upstream .py its own file at its
# own path. Nothing moved but the file it lives in: the rows are the rows. The
# DEF-BY-DEF MAP for all three is `linearizer.bend`'s head and the FOUR WALLS (W1-W4)
# are named there.
#
# THE SHARED SUBSTRATE IS IMPORTED, NOT COPIED. `RaTb`, `RaEn` and the `tb_*` readers
# and writers stand in for Python's `dict` and `defaultdict`, which have no Bend
# equivalent that is `U32`-keyed; they are declared in `linearizer.bend` (first in
# Python's order) and every use here is `LT.tb_*`. A TYPE MENTION needs the alias as
# well as a call -- an unqualified imported `type` name is not in scope.
#
''' + '\n'.join(L(132, 152)) + '\n' + '\n'.join(L(159, 172)) + '''
import Base
import ./../../helpers.bend as H
import ./../../uop/ops.bend as O
import ./../kernel.bend as KER
import ./linearizer.bend as LT

'''
open(f'{ROOT}/late/regalloc.bend', 'w').write(
    reg_hdr + '\n'.join(REG) + '\n' + main_of(M_REG) + '\n' + '\n'.join(MUTTAB))

# ---------------------------------------------------------------- gater
gat_hdr = '''# codegen/late/gater.bend -- port of tinygrad/codegen/late/gater.py
#
# ONE OF THREE SLICES. `codegen/late.bend` held `linearizer.py`, `regalloc.py` and
# `gater.py` together and the 1:1 ruling gives each upstream .py its own file at its
# own path. The other two are `linearizer.bend` and `regalloc.bend` beside this one,
# the rows are the rows, and the DEF-BY-DEF MAP for all three is
# `linearizer.bend`'s head.
#
# W4 APPLIES HERE AND IS NOT RESTATED: `gater.py:6-7` compares
# `a.src[0].dtype == l.dtype` and `gater.py:25-28` annotates `dtype=dtypes.bool`, and
# a dtype cannot be CARRIED in bend 2.0.34. Every rule below takes its dtype predicate
# as a `Bool` PARAMETER, the shape `linearizer.bend`'s W4 paragraph prescribes.
#
''' + '\n'.join(L(3154, 3166)) + '''
import Base
import ./../../LAWS/spec.bend as S
import ./../../uop/ops.bend as O
import ./../kernel.bend as KER
import ./linearizer.bend as LT

'''
open(f'{ROOT}/late/gater.bend', 'w').write(
    gat_hdr + '\n'.join(GAT) + '\n' + main_of(M_GAT))

print('main rows: lin=%d reg=%d gat=%d' % (len(M_LIN), len(M_REG), len(M_GAT)))
