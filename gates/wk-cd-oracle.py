#!/usr/bin/env python3
"""CPython oracle for `wk_commit_dtype` (uop/weak.bend). Calls the REAL method.

    .venv/bin/python .agents/slop/wk-cd-oracle.py

CPython, `tinygrad/mixin/dtype.py:16`:

    def commit_dtype(self, default_int=None):
      return commit_int(self._uop.vmin, self._uop.vmax, default_int) if self.dtype is dtypes.weakint else self.dtype

and `commit_int` walks `(default_int, dtypes.int, dtypes.long, ...)` for the first rung that
contains `[lo, hi]`.

THE FIXTURE MUST BE A weakint PARAM, and that is the whole first lesson of this gate. A PARAM
whose dtype is int32 answers `dtypes.i32` on EVERY row, because the weakint branch is not
taken and `commit_dtype` returns `self.dtype` -- so seven rows of `i32` would be a gate that
proves nothing at all. The first version of this file had exactly that and was rewritten.

THE DISCRIMINATING ROWS ARE THE BIG ONES. With `default_int = int32` the ladder's first rung
holds every range inside int32, so `cd_0_10`, `cd_neg5_5` and `cd_i32full` all answer i32
and say nothing. The three that matter are the ranges int32 CANNOT hold, and they answer
int64:
  cd_big_2p40   [-2**40, 2**40]   does not fit int32
  cd_one_2p40   [2**40, 2**40]    a POINT range too wide for int32, which also exercises
                                 commit_int's `lo == hi` arm
  cd_none       a weakint PARAM with NO bounds at all

`cd_none` IS THE KNOWN DIVERGENCE and it is named in the gate rather than hidden: CPython
answers `i64` and the port answers nothing, because a PARAM with no `vmin_vmax` gives the
port's bounds sweep no interval to report. `wk_commit_dtype` is faithful to the sweep here --
it reports exactly what `UOp.vmin`/`UOp.vmax` gave it -- so the gap is in the sweep's
PARAM-with-no-bounds arm, not in the reader. That is a real, located difference and the gate
pins both sides' content so it cannot change unnoticed.

SPELLING. CPython prints `dtypes.i32`; the port's `F.dt_nm` prints `i32`. The oracle
normalises with `removeprefix('dtypes.')` so the two lanes are compared on the VALUE and not
on a prefix -- a diff that is really a spelling convention is a diff nobody reads.
"""
import sys

from tinygrad import Tensor, dtypes
from tinygrad.uop.ops import UOp, Ops, ParamArg, AddrSpace


def param(lo, hi, dt):
    vm = None if lo is None else (lo, hi)
    return Tensor(UOp(Ops.PARAM, (), ParamArg(-1, dt, vmin_vmax=vm, addrspace=AddrSpace.ALU)))


# (row, lo, hi, dtype) -- lo/hi are None for "no bounds".
CASES = [
    ("cd_big_2p40", -(2**40), 2**40, dtypes.weakint),
    ("cd_one_2p40", 2**40, 2**40, dtypes.weakint),
    ("cd_none", None, None, dtypes.weakint),
    ("cd_0_10", 0, 10, dtypes.weakint),
    ("cd_neg5_5", -5, 5, dtypes.weakint),
    ("cd_i32full", -(2**31), 2**31 - 1, dtypes.weakint),
    ("cd_strong", 0, 10, dtypes.int32),
]

DIVERGES = ""


def main():
    for nm, lo, hi, dt in CASES:
        t = param(lo, hi, dt)
        try:
            out = str(t.commit_dtype(dtypes.int32))
        except Exception as e:                       # a lane that raises must still print
            out = type(e).__name__
        print(f"{nm}={out.removeprefix('dtypes.')}")
    print(f"# DIVERGES={DIVERGES}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
