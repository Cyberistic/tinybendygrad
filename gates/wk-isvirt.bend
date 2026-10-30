# wk-isvirt.bend -- the GATE DRIVER for `wk_is_virtual` (uop/weak.bend), ops.py:902.
#
#   .venv/bin/python gates/wk-isvirt-gate.py
#
# WHAT IS UNDER TEST. `UOp.is_virtual` is ONE LINE in CPython:
#
#     return self.device is None or self.dtype in dtypes.weaks
#
# and the port spells it as TWO claims (uop/weak.bend:268): the device half and the dtype
# half, joined by `Bool.or`. The device half is the NESTED `Maybe` -- the outer is "does
# this node carry a device at all" and the inner is "is it there" -- and flattening them
# first would lose the one case `is_virtual` is asking about.
#
# WHY THIS GATE EXISTS, and the reason is a STALE CLAIM. `uop/ops.bend:5345` says
# "PORTED BUT UNGATED, AND THE REASON IS A FIXTURE, NOT A DEF ... fold.bend's `mw_pa`
# hard-codes `ParamArg`'s device field to `None{}` and no def in the port sets it, so
# EVERY node is virtual and the reader has no negative witness. MEASURED: both candidate
# rows came out `True`, and two rows that are always `True` cannot fail."
#
# THAT REASON IS NOW FALSE. MEASURED 2026-10-30: `renderer/__init__.bend:450` builds a
# `ParamArg` with `device = Some{S.D1{0}}`, and `fold.bend`'s `device_of.param` reads
# `O.ParamArg.device(pa)` -- so a node that CARRIES a device is reachable, and
# `wk_is_virtual` has a negative witness for the first time.
#
# THE FOUR CELLS, and they are a CROSS of two independent questions, so a reader that
# answered one of them correctly by accident cannot pass all four:
#
#              device PRESENT            device ABSENT
#   strong dtype   False                    True
#   weak dtype     True                     True
#
# THE TWO `True` CELLS ON THE WEAK ROW ARE THE POINT: a reader that only ever asked the
# device question would answer `False` for a weak node with a device, and a reader that
# only ever asked the dtype question would answer `False` for a strong node without one.
# Only the disjunction answers all four, and only the disjunction is `ops.py:902`.
#
# THE DEVICE-BEARING FIXTURE IS BUILT WITH `O.ParamArg.device` SPELLED OUT, not through
# `F.mw_pa`, because `mw_pa` hard-codes the device to `None{}` -- which is the very thing
# the stale claim rested on. The row that carries a device is the FIRST one, so a reader
# that ignored the device field would fail on it rather than on the last.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/weak.bend as W

def p(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))

# A PARAM with an EXPLICIT device field and an EXPLICIT dtype. The device is `None{}` or
# `Some{S.D1{0}}` and the dtype is the one under test; the two are the cross's axes.
#
# `O.ParamArg`'s FIELD ORDER IS NOT THE PROSE ORDER (bend2-constraints.md rule 33): the
# fields are slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image,
# buffer, bind_on_realize, val.
def pa_with(dt: S.Dt, dev: Maybe<&2, S.Dev>) -> O.ParamArg:
  O.ParamArg{0, dt, None{}, None{}, None{}, S.AGlobal{}, dev,
    False{}, None{}, None{}, False{}, None{}}

def one(nm: String, dt: S.Dt, dev: Maybe<&2, S.Dev>) -> IO(Unit):
  +ar = O.Arena.empty()
  +f = O.UOp.new(ar, O.OpsPARAM{}, Nil{}, O.AParam{pa_with(dt, dev)}, O.TNone{})
  +med = F.min_maxed(O.Found.ar(f))
  p(nm, W.wk_is_virtual(F.folded(F.MMed.ar(med)), O.Found.i(f)))

def rows() -> IO(Unit):
  do IO<Unit>:
    # THE DEVICE-BEARING STRONG NODE: the one cell that is `False`, and the one that has
    # no witness at all under the stale claim.
    a : Unit <- one("iv_dev_strong", S.int32(), Some{S.D1{0}})
    # THE DEVICE-BEARING WEAK NODE: `True` because of the DTYPE half, so a reader that
    # dropped the `or` would answer `False` here.
    b : Unit <- one("iv_dev_weakint", S.weakint(), Some{S.D1{0}})
    # THE DEVICE-LESS STRONG NODE: `True` because of the DEVICE half, so a reader that
    # dropped the device test would answer `False` here.
    c : Unit <- one("iv_nodev_strong", S.int32(), None{})
    # THE DEVICE-LESS WEAK NODE: `True` twice over. This is the cell that agrees with a
    # reader that ignores BOTH halves, and it is here so the OTHER three are read against
    # it rather than in isolation.
    d : Unit <- one("iv_nodev_weakint", S.weakint(), None{})
    # A SECOND STRONG DTYPE, so the `False` cell is not a fact about int32 alone.
    one("iv_dev_single", S.single(), Some{S.D1{0}})

def main() -> IO(Unit): rows()
