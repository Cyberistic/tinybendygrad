import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from tinygrad.uop.ops import UOp, Ops, ParamArg
from tinygrad import dtypes
from tinygrad.uop.divandmod import fold_divmod_general

PARAM_SIZE = 4


def mk_param(name):
    sz = UOp(Ops.CONST, (), PARAM_SIZE)
    return UOp(Ops.PARAM, (sz,), ParamArg(0, dtypes.weakint, name=name))


def const(v):
    return UOp(Ops.CONST, (), v)


def form(u):
    if u.op is Ops.CONST:
        return "Ops.CONST(%d)" % u.arg
    if u.op is Ops.PARAM:
        return "P" + (u.arg.name or "")
    return "Ops.%s(%s)" % (u.op.name, ",".join(form(s) for s in u.src))


def answer(root):
    try:
        got = fold_divmod_general(root)
    except Exception as e:
        return "RAISED %s" % type(e).__name__
    if got is None:
        return "nofold"
    return "ANSWERED %s" % form(got)


# THE `factor_remainder` SHAPES: `(d*x + y) // d` AND `(d*x + y) % d`, WHERE
# `d` IS A CONST AND `d` DOES **NOT** DIVIDE `y`.
x = mk_param("x")
y = mk_param("y")
z = mk_param("z")

c2 = const(2)
c3 = const(3)
c4 = const(4)

CASES = [
    ("FR_DIV_2x3_2", x.alu(Ops.MUL, c2).alu(Ops.ADD, c3).alu(Ops.DIV, c2)),
    ("FR_DIV_4x2_4", x.alu(Ops.MUL, c4).alu(Ops.ADD, c2).alu(Ops.DIV, c4)),
    ("FR_DIV_2xy_2", x.alu(Ops.MUL, c2).alu(Ops.ADD, y).alu(Ops.DIV, c2)),
    ("FR_DIV_4x4y_4", x.alu(Ops.MUL, c4).alu(Ops.ADD, y.alu(Ops.MUL, c4)).alu(Ops.DIV, c4)),
    ("FR_MOD_2x3_2", x.alu(Ops.MUL, c2).alu(Ops.ADD, c3).alu(Ops.MOD, c2)),
    ("FR_MOD_4x2_4", x.alu(Ops.MUL, c4).alu(Ops.ADD, c2).alu(Ops.MOD, c4)),
    ("FR_MOD_2xy_2", x.alu(Ops.MUL, c2).alu(Ops.ADD, y).alu(Ops.MOD, c2)),
    ("FR_DIV_2x2y_2", x.alu(Ops.MUL, c2).alu(Ops.ADD, y.alu(Ops.MUL, c2)).alu(Ops.DIV, c2)),
    ("FR_DIV_2xyz_2", x.alu(Ops.MUL, c2).alu(Ops.ADD, y).alu(Ops.ADD, z).alu(Ops.DIV, c2)),
    ("FR_DIV_6x3_6", x.alu(Ops.MUL, const(6)).alu(Ops.ADD, c3).alu(Ops.DIV, const(6))),
    ("FR_DIV_6x3_2", x.alu(Ops.MUL, const(6)).alu(Ops.ADD, c3).alu(Ops.DIV, c2)),
    ("FR_MOD_6x3_6", x.alu(Ops.MUL, const(6)).alu(Ops.ADD, c3).alu(Ops.MOD, const(6))),
]

for nm, root in CASES:
    print("%-16s %-12s -> %s" % (nm, form(root), answer(root)))
