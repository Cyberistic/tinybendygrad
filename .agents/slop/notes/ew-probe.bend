import Base
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/uop/weak.bend as W
import ./../../../tinybendygrad/mixin/dtype.bend as M
import ./../../../tinybendygrad/tensor.bend as T

def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b), "\n"]))

def show(nm: String, s: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", s, "\n"]))

def ALL_DTS() -> List<&2, S.Dt>:
  [S.void(), S.weakint(), S.boolean(), S.int8(), S.uint8(), S.int16(), S.uint16(),
   S.int32(), S.uint32(), S.int64(), S.uint64(), S.weakfloat(), S.fp8e4m3(),
   S.fp8e4m3fnuz(), S.fp8e5m2(), S.fp8e5m2fnuz(), S.half(), S.bfloat16(),
   S.single(), S.double()]

def nat_of(b: Bool) -> Nat:
  match b:
    case True{}: 1n
    case _: 0n

# R1 is `wk_sealed(weak_dtype(d))` ever true? (remint's dt is always a weak_dtype)
def sealed_wd.go(ds: List<&2, S.Dt>, n: Nat) -> Nat:
  match ds:
    case Nil{}: n
    case d <> t: sealed_wd.go(t, (Nat.add(n, nat_of(W.wk_sealed(W.weak_dtype(d)))) : Nat))

def sealed_wd() -> Nat:
  sealed_wd.go(ALL_DTS(), 0n)

def r1() -> IO(Unit):
  show("r1_sealed_weakdtype", U32.show(U32.from_nat(sealed_wd())))

# R2 `dt_weak` count over the twenty
def weak_n.go(ds: List<&2, S.Dt>, n: Nat) -> Nat:
  match ds:
    case Nil{}: n
    case d <> t: weak_n.go(t, (Nat.add(n, nat_of(W.dt_weak(d))) : Nat))

def r2() -> IO(Unit):
  show("r2_weak_count", U32.show(U32.from_nat(weak_n.go(ALL_DTS(), 0n))))

# R3 `M.cast_at` on a weakint CONST to int32 -- is the NODE a CAST?
def r3() -> IO(Unit):
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})
  +m = M.cast_at(F.folded(O.Found.ar(c)), O.Found.i(c), S.int32())
  show("r3_cast_op", O.Ops.name(O.Arena.op(O.Found.ar(m), O.Found.i(m))))

# R4 `md_dt_min/max` on int8
def i64show(x: H.I64) -> String:
  H.i64_text(x)

def r4() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- show("r4_i8_min", i64show(Maybe.default(&1, H.I64, M.md_dt_min(S.int8()), H.i64_of_i32(0))))
    b : Unit <- show("r4_i8_max", i64show(Maybe.default(&1, H.I64, M.md_dt_max(S.int8()), H.i64_of_i32(0))))
    c : Unit <- show("r4_u8_min", i64show(Maybe.default(&1, H.I64, M.md_dt_min(S.uint8()), H.i64_of_i32(0))))
    IO.print("")

# R5 `Arenas.budget` on an empty arena, and `F.folded`
def r5() -> IO(Unit):
  show("r5_budget_empty", U32.show(U32.from_nat(O.Arena.budget(O.Arena.empty()))))

# R6 a weakint CONST's `wk_dt_const` at single -- is it Some?
def r6() -> IO(Unit):
  row("r6_dtconst_single", ew_is_some(W.wk_dt_const(S.single(), O.CInt{H.i64_of_i32(3)})))
  row("r6_dtconst_half", Bool.not(ew_is_some(W.wk_dt_const(S.half(), O.CInt{H.i64_of_i32(3)}))))

def ew_is_some(a: -A: Kind(a, &2, Maybe<&2, a>), m: Maybe<&2, a>) -> Bool:
  match m:
    case Some{x}: True{}
    case _: False{}

# R7 `base` of a movement node and of a DETACH
def r7() -> IO(Unit):
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(3)})
  +m = O.UOp.new(O.Found.ar(c), O.OpsDETACH{}, [O.Found.i(c)], O.ANone{}, O.TNone{})
  show("r7_detach_base", U32.show(Maybe.default(&2, U32, F.fold.base(O.Found.ar(m), F.UOp.fold(O.Found.ar(m)), O.Found.i(m)), 99)))

# R8 `O.Arena.src_from`
def r8() -> IO(Unit):
  +a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(5)})
  +b = O.UOp.const(O.Found.ar(a), O.CInt{H.i64_of_i32(7)})
  +n = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  show("r8_nsrc", U32.show(O.Arena.nsrc(O.Found.ar(n), O.Found.i(n))))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- r1()
    b : Unit <- r2()
    c : Unit <- r3()
    d : Unit <- r4()
    e : Unit <- r5()
    f : Unit <- r6()
    g : Unit <- r7()
    h : Unit <- r8()
    IO.print("")
