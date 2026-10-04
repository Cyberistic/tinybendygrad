import Base
import ./../../tinybendygrad/helpers.bend as H
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/uop/fold.bend as F
import ./../../tinybendygrad/uop/weak.bend as W

# THE GATE for `wk_commit_dtype` (weak.bend) -- the node-level reader that NINE of that
# file's markers said was missing.
#
# CPython, `tinygrad/mixin/dtype.py:16`:
#     commit_int(self._uop.vmin, self._uop.vmax, default_int) if self.dtype is weakint
#     else self.dtype
# and the oracle below calls the real `Tensor.commit_dtype` on real PARAMs.
#
# THE FIXTURE MUST BE A **weakint** PARAM, and that is the whole first round of this gate:
# a PARAM with dtype int32 answers `dtypes.i32` on EVERY row, because the weakint branch is
# not taken and `commit_dtype` returns `self.dtype`. Seven rows of `i32` would have been a
# gate that proves nothing, and the row that discriminates is a range int32 cannot hold.
#
# THE DISCRIMINATING ROWS ARE THE BIG ONES. `commit_int`'s ladder is
# `(default_int, dtypes.int, dtypes.long, ...)`, and with `default_int = int32` the first
# rung holds every range inside int32 -- so `cd_0_10`, `cd_neg5_5` and `cd_i32full` all
# answer `i32` and say nothing. `cd_big_2p40` and `cd_one_2p40` do NOT fit and fall through
# to int64, and `cd_none` (a weakint PARAM with no bounds) reports weakint's whole range
# and lands on int64 too. A gate without those three rows would pass a reader that always
# answered `i32`.
def p(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

# MATCHED RATHER THAN PASSED ON, and that is the port's idiom for a lifetime mismatch:
# `D.commit_dtype` answers `Maybe<&1, S.Dt>` and `F.dt_str` takes `Maybe<&2, S.Dt>`. There
# is no `retag` helper in the tree, and `fold.bend`'s own rows do the same thing -- matching
# the `Maybe` and handing the INNER value to the printer, which rebinds at whatever lifetime
# the scope wants. A retag def would be the wrong answer to a question the tree has already
# answered three times.
def show(nm: String, m: Maybe<&1, S.Dt>) -> String:
  match m:
    case Some{d}: String.concat([nm, "=", F.dt_nm(d)])
    case _: String.concat([nm, "=None"])

# A PARAM carrying bounds, then the SWEEP, then the reader. `min_maxed` is the same call
# fold.bend's own `mmk_vmin` row makes, so the gate reads the sweep the port already has
# rather than a hand-built bound.
def one(nm: String, vmm: Maybe<&2, O.PyRange>, dt: S.Dt) -> IO(Unit):
  +ar = O.Arena.empty()
  +f = O.UOp.new(ar, O.OpsPARAM{}, Nil{}, O.AParam{F.mw_pa(dt, vmm)}, O.TNone{})
  +med = F.min_maxed(O.Found.ar(f))
  IO.print(show(nm, W.wk_commit_dtype(F.folded(F.MMed.ar(med)), F.MMed.bt(med), O.Found.i(f))))

def rows() -> IO(Unit):
  do IO<Unit>:
    # the DISCRIMINATING rows first, so a reader that always answered i32 fails here
    a : Unit <- one("cd_big_2p40", Some{O.PyRange{H.i64_of_hi_lo(4294967040, 0), H.i64_of_hi_lo(256, 0)}}, S.weakint())
    b : Unit <- one("cd_one_2p40", Some{O.PyRange{H.i64_of_hi_lo(256, 0), H.i64_of_hi_lo(256, 0)}}, S.weakint())
    c : Unit <- one("cd_none", None{}, S.weakint())
    d : Unit <- one("cd_0_10", Some{O.PyRange{H.i64_of_i32(0), H.i64_of_i32(10)}}, S.weakint())
    e : Unit <- one("cd_neg5_5", Some{O.PyRange{H.i64_of_i32(4294967291), H.i64_of_i32(5)}}, S.weakint())
    f : Unit <- one("cd_i32full", Some{O.PyRange{H.i64_of_hi_lo(0, 2147483648), H.i64_of_i32(2147483647)}}, S.weakint())
    one("cd_strong", Some{O.PyRange{H.i64_of_i32(0), H.i64_of_i32(10)}}, S.int32())

def main() -> IO(Unit): rows()
