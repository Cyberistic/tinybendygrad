#!/usr/bin/env python3
"""realize_kernel_args-oracle.py -- CPython's answer for `get_call_kernel_args`, in the
PORT's OWN row spelling.

    .venv/bin/python gates/realize_kernel_args-oracle.py

**WHAT THIS IS.** THE CPython HALF OF `gates/realize_kernel_args-gate.py`. THE PORT's
`tinybendygrad/engine/realize.bend` ANSWERS `get_call_kernel_args` OVER ITS PLANT
FIXTURE AND PRINTS NINETEEN `ka_*` ROWS; THIS ANSWER THE SAME NINETEEN QUESTIONS OVER
THE SAME FIXTURE, FROM THE VENDORED `tinygrad/engine/realize.py` -- WHICH IS BYTE-
IDENTICAL TO THE PIN `5c2bf39d6c4b` -- SO THE TWO LANES ARE COMPARING THE SAME
FUNCTION.

**WHY IT IS A SEPARATE GATE AND NOT A DRIVER OF THE BIG CENSUS.** THE BIG CENSUS's
`var` DRIVER CANNOT COMPARE THIS FUNCTION, AND THE REASON IS THE FIXTURE, NOT THE
FUNCTION. MEASURED: THE PIN's `get_call_kernel_args` READS `s.is_bound_var` OVER
`call.src[1:]`, AND `ops.py:1011`'s `is_variable` READS `self._shape`, WHICH FOR A PARAM
IS `self.src[0].as_shape` -- SO A PARAM WITH NO `src` RAISES IndexError. THE BIG
CENSUS's FIXTURE MIRRORS THE PORT's `main_arena`, WHOSE PARAMS HAVE NO `src`, SO 21 OF
THE 23 `var_*` ROWS ARE `raise=IndexError` THERE. THE PORT's OWN `is_variable` CANNOT
READ `_shape` AT ALL -- THAT IS THE `marg` WALL `realize.bend` RECORDS -- SO THE PORT
ANSWERS AND CPython CANNOT, AND THE BIG CENSUS's `var` ROWS ARE A DECLARED DIVERGENCE
INSTEAD OF A COMPARISON. **THE FIXTURE BELOW IS BUILT WITH `UOp.param`, WHICH ALWAYS
GIVES A PARAM A SRC, AND EVERY PROGRAM HAS THE PIN's COMPILED SHAPE `src=(sink,
linear)` -- BECAUSE THE PIN's `UOp.kernel_params` READS `self.src[1].src` AND A ONE-SRC
PROGRAM RAISES IndexError THERE.** SO THE FUNCTION IS COMPARED HERE, WHERE IT CAN BE.

**WHERE THIS CAME FROM.** IT IS THE PORT UNIT'S OWN UNTRACKED INSTRUMENT,
`.agents/slop/realizepin/plants-oracle.py`, MOVED INTO GIT BESIDE THE GATE THAT NEEDS
IT AND REWRITTEN TO PRINT THE PORT's ROW SPELLING. `.agents/slop/` IS THE DIRECTORY
THIS TREE IS PRUNING, AND THE TREE HAS ALREADY LOST AN INSTRUMENT THAT WAY
(`worker_oracle.py`, RECOVERED FROM A BLOB). **A GATE'S REQUIRED INPUT BELONGS BESIDE
THE GATE IN GIT.**

**THE DEVICE.** THE PIN TAKES A DEVICE **TUPLE** (`devs`) AND THE PORT TAKES ONE
`S.Dev`, AND THE BRIDGE IS THE CALL's OWN DEVICE: THE PIN's OWN
`get_call_kernels` READS IT FROM `to_tuple(call.src[1].device)` (`realize.py:41`), AND
THE PORT's `get_call_kernel_args` IS CALLED WITH THE SAME DEVICE. EVERY PLANT HERE IS
ON "CPU", SO THE TUPLE IS `("CPU",)` AND THE PORT's IS `cpu_dev()` -- AND THE PORT's
PLANT ROWS DO NOT CARRY THE DEVICE, SO A WRONG DEVICE IS INVISIBLE IN THIS GATE. THE
DEVICE IS COMPARED WHERE IT IS COMPARABLE AT ALL: THE BIG CENSUS's `var` DRIVER, OVER
THE TWO-DEVICE BUFFER `rs_x64`/`rs_x65`, WHERE THE DEVICE's COUNT IS IN THE GETADDR's
PAYLOAD. THAT RESIDUAL IS STATED HERE RATHER THAN LEFT IMPLICIT.
"""

from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.uop.ops import UOp, Ops, ParamArg, KernelInfo, ProgramInfo, CallInfo
import tinygrad.engine.realize as RZ

# THE DEVICE TUPLE THE PIN's CALLERS PASS. `tinygrad/runtime/ops_{cuda,amd,nv,cl,metal,
# qcom,null}.py` ALL PASS `self.devs`, THE RUNTIME's DEVICE RANGE, AND EVERY PLANT HERE
# IS ON "CPU". THE PORT's COUNTERPART IS `tinybendygrad/engine/realize.bend`'s
# `cpu_dev()`, WHICH IS `S.D1{0}`.
DEVS = ("CPU",)


# ------------------------------------------------------------------ THE FIXTURE
# `UOp.param` GIVES EVERY PARAM A SRC, WHICH IS WHAT MAKES `is_variable` READABLE: SEE
# THE HEADER. `ops.py:1225`'s `UOp.param` ALWAYS GIVES `src=(shape_to_shape_arg(...),)`,
# AND FOR A SCALAR THAT IS `UOp(Ops.STACK, src=())`.
def _buf(slot, nm):
    return UOp.param(slot, dtypes.int32, 16, "CPU", name=nm)


def _var(slot, nm):
    return UOp.param(slot, dtypes.int32, None, None, vmin_vmax=(0, 4), multiple_of=1,
                     name=nm, addrspace=AddrSpace.ALU)


def _bnd(slot, nm):
    # THE BOUND VARIABLE. `UOp.param` HAS NO `val` KWARG (`ops.py:1218`), SO IT IS BUILT
    # THE WAY `ops.py:1026`'s `bind` BUILDS IT: THE SAME ParamArg WITH `val` SET.
    return UOp(Ops.PARAM, src=(UOp(Ops.STACK, src=()),),
               arg=ParamArg(slot, dtypes.int32, vmin_vmax=(0, 4), multiple_of=1, name=nm,
                            addrspace=AddrSpace.ALU, val=4))


def _ki(nm, beam):
    return KernelInfo(nm, (), None, None, beam)


def _pi(params, gs, os_, is_):
    return ProgramInfo((4, 1, 1), (1, 1, 1), tuple(params), tuple(gs), tuple(os_), tuple(is_))


def _call(nm, *s):
    return UOp(Ops.CALL, src=s, arg=CallInfo(None, nm, False, False, None))


# THE SIX PLANTS, IN THE PORT's ORDER (`Pl.call`'s `cNone, cZero, cUnb, cArgFirst,
# cBufFirst, cShadow`).
#
#   cNone      A PROGRAM WITH NO VARIABLE AT ALL. THE ANSWER IS ONE ADDRESS PER BUFFER
#              PARAM AND NOTHING ELSE.
#   cZero      A VARIABLE BOUND TO ZERO. THE BOUND VALUE IS A CONST 0 AND THE LOOKUP MUST
#              NOT READ 0 AS "ABSENT".
#   cUnb       AN UNBOUND VARIABLE. THE ANSWER IS THE SLOTLESS VAR READ, AND THE ARGUMENT
#              LIST DROPS IT (`get_call_arg_uops` FILTERS `is_variable`).
#   cArgFirst  AN ARG PRECEDES A BUFFER: THE KERNEL's PARAMS ARE (VAR SLOT 0, BUFFER SLOT
#              1) AND THE ANSWER MUST BE IN THAT ORDER.
#   cBufFirst  THE MIRROR -- (BUFFER SLOT 0, VAR SLOT 1) -- AND THE ANSWER MUST BE THE
#              OTHER WAY ROUND.
#   cShadow    A VARIABLE WHOSE NAME IS A GLOBAL's NAME. `bound` IS KEYED ON THE NAME, SO
#              THE LOOKUP MUST STILL ANSWER THE VARIABLE's OWN VALUE AND NOT THE GLOBAL's.
c3 = UOp.const(3)
gb = _buf(0, "g0")
va0 = _var(0, "a0")
va1 = _var(1, "a1")
vz = _bnd(0, "z0")
vs = _bnd(1, "g0")
ks = UOp(Ops.SINK, src=(), arg=_ki("kp", 0))
lin = UOp(Ops.LINEAR, src=(), arg=None)

pNone = UOp(Ops.PROGRAM, src=(ks, lin), arg=_pi((gb,), (0,), (0,), ()))
cNone = _call("pn", pNone, gb)
pZero = UOp(Ops.PROGRAM, src=(ks, lin), arg=_pi((vz,), (0,), (0,), ()))
cZero = _call("pz", pZero, vz)
pUnb = UOp(Ops.PROGRAM, src=(ks, lin), arg=_pi((va0,), (0,), (0,), ()))
cUnb = _call("pu", pUnb, va0)
pAF = UOp(Ops.PROGRAM, src=(ks, lin), arg=_pi((va0, gb), (1,), (1,), ()))
cAF = _call("pa", pAF, va0, gb)
pBF = UOp(Ops.PROGRAM, src=(ks, lin), arg=_pi((gb, va1), (0,), (0,), ()))
cBF = _call("pb", pBF, gb, va1)
pSh = UOp(Ops.PROGRAM, src=(ks, lin), arg=_pi((gb, vs), (0,), (0,), ()))
cSh = _call("ps", pSh, gb, vs)

CASES = [("cNone", cNone, pNone), ("cZero", cZero, pZero), ("cUnb", cUnb, pUnb),
         ("cArgFirst", cAF, pAF), ("cBufFirst", cBF, pBF), ("cShadow", cSh, pSh)]


# ------------------------------------------------------------------ THE FACTS
# EACH FACT IS ONE OF THE PORT's OWN `t_ka_*` READERS, SPELLED OUT. THE PORT's READERS
# ARE: `t_ka_len` (THE COUNT), `t_ka_addr` (IS ENTRY `i` A GETADDR), `t_ka_param` (IS
# ENTRY `i` A PARAM), `t_ka_cast` (IS ENTRY `i` A CAST), `t_ka_slotless` (IS ENTRY `i`'S
# SLOT THE PIN's `-1`) AND `t_ka_arglen` (THE LENGTH OF `get_call_arg_uops`).
def _facts(case):
    nm, call, prg = case
    ka = RZ.get_call_kernel_args(call, prg, DEVS)
    n = len(ka)

    def is_op(i, op):
        return 1 if i < n and ka[i].op is op else 0

    def slotless(i):
        if i < n and ka[i].op is Ops.PARAM:
            return 1 if ka[i].arg.slot == -1 else 0
        return 0

    return {
        "len": n,
        "addr0": is_op(0, Ops.GETADDR),
        "addr1": is_op(1, Ops.GETADDR),
        "param0": is_op(0, Ops.PARAM),
        "param1": is_op(1, Ops.PARAM),
        "cast0": is_op(0, Ops.CAST),
        "cast1": is_op(1, Ops.CAST),
        "slotless0": slotless(0),
        "slotless1": slotless(1),
        "arglen": len(RZ.get_call_arg_uops(call)),
    }


# THE NINETEEN ROWS, IN THE PORT's OWN ORDER AND SPELLING. THE ORDER MATTERS: `gatekit`
# DIFFS THE LANES LINE BY LINE.
ROWS = [
    ("ka_none_len", "cNone", "len"), ("ka_none_addr", "cNone", "addr0"),
    ("ka_zero_len", "cZero", "len"), ("ka_zero_cast", "cZero", "cast0"),
    ("ka_unb_len", "cUnb", "len"), ("ka_unb_param", "cUnb", "param0"),
    ("ka_unb_slotless", "cUnb", "slotless0"), ("ka_unb_arglen", "cUnb", "arglen"),
    ("ka_af_len", "cArgFirst", "len"), ("ka_af_p0", "cArgFirst", "param0"),
    ("ka_af_a1", "cArgFirst", "addr1"), ("ka_af_slotless", "cArgFirst", "slotless0"),
    ("ka_bf_len", "cBufFirst", "len"), ("ka_bf_a0", "cBufFirst", "addr0"),
    ("ka_bf_p1", "cBufFirst", "param1"), ("ka_bf_slotless", "cBufFirst", "slotless1"),
    ("ka_sh_len", "cShadow", "len"), ("ka_sh_cast", "cShadow", "cast1"),
    ("ka_sh_a0", "cShadow", "addr0"),
]


def main():
    by_name = {c[0]: c for c in CASES}
    for row, case, what in ROWS:
        print("%s=%d" % (row, _facts(by_name[case])[what]))


if __name__ == "__main__":
    main()
