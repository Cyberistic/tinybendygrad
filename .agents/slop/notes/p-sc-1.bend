import Base
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F

def b2u(b: Bool) -> U32:
  match b:
    case True{}: 1
    case False{}: 0

# (a) two-scrutinee match on COMPUTED values passed as params, plus a def call in
# the arm's value position.
def gate.k(arg: O.Arg) -> Bool:
  match arg:
    case O.AKernel{ki}: True{}
    case _: False{}

def gate.of(op: O.Op, arg: O.Arg) -> Bool:
  match op arg:
    case O.OpsLINEAR{} _ : False{}
    case O.OpsSINK{} a   : Bool.not(gate.k(a))
    case _ _              : True{}

def gate(+ar: O.Arena, +i: U32) -> Bool:
  gate.of(O.Arena.op(ar, i), O.Arena.arg(ar, i))

# (b) `+` reuse of `ar` across a self-call and a construction, with the recursive
# call bound to a local first.
def dw.go(fuel: Nat, +ar: O.Arena, +s: U32) -> U32:
  match fuel:
    case 0n: s
    case 1n+p:
      b = dw.go(p, ar, O.Arena.src0(ar, s))
      +f = O.UOp.new(ar, O.OpsMSELECT{}, [b], O.Arena.arg(ar, s), O.TNone{})
      O.Found.i(f)

def dw(+ar: O.Arena, s: U32) -> U32:
  dw.go(O.Arena.budget(ar), ar, s)

# (c) fixtures
def pa(slot: U32, nm: String, val: Maybe<&2, O.Const>, vm: Maybe<&2, O.PyRange>) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), None{}, vm, None{}, Some{nm}, S.Aalu{}, None{}, False{}, None{}, None{}, False{}, val}

def body(n: U32) -> O.Found:
  +c0 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  +cn = O.UOp.const(O.Found.ar(c0), O.CInt{H.i64_of_i32(n)})
  +st = O.UOp.new(O.Found.ar(cn), O.OpsSTORE{}, [O.Found.i(c0), O.Found.i(cn)], O.ANone{}, O.TNone{})
  O.UOp.sink(O.Found.ar(st), [O.Found.i(st)])

# A BUFFER of four int32 on device tag 0, with a SPECIAL naming its size. `b` and
# `buf` are the two distinct buffers; `b` is interned first so the fixture is
# stable.
def fb(+slot: U32, +nm: String, +ar: O.Arena) -> U32:
  +sp = O.UOp.special(ar, O.Found.i(O.UOp.const(ar, O.CInt{H.i64_of_i32(1)})), nm)
  O.Found.i(O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, [O.Found.i(sp)], O.AParam{pa(slot, nm, None{}, None{})}, O.TNone{}))

def fx1() -> O.Found:
  +e = O.Arena.empty()
  +a = fb(0, "a", e)
  +bd = fb(1, "b", e)
  +b1 = body(1)
  +b2 = body(2)
  +k1 = O.UOp.new(O.Found.ar(b1), O.OpsCALL{}, [O.Found.i(b1), a], O.ANone{}, O.TNone{})
  +k2 = O.UOp.new(O.Found.ar(b2), O.OpsCALL{}, [O.Found.i(b2), bd], O.ANone{}, O.TNone{})
  +e2 = O.UOp.new(O.Found.ar(k2), O.OpsEND{}, [O.Found.i(k2)], O.ANone{}, O.TNone{})
  +f1 = O.UOp.new(O.Found.ar(e2), O.OpsAFTER{}, [a, O.Found.i(k1)], O.ANone{}, O.TNone{})
  +f2 = O.UOp.new(O.Found.ar(f1), O.OpsAFTER{}, [O.Found.i(f1), O.Found.i(e2)], O.ANone{}, O.TNone{})
  O.UOp.sink(O.Found.ar(f2), [O.Found.i(f2)])

def fx1.ar() -> O.Arena: O.Found.ar(fx1())
def fx1.top() -> U32: O.Found.i(fx1())

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("next", O.Arena.next(fx1.ar()))
    b : Unit <- row("gate_top", b2u(gate(fx1.ar(), fx1.top())))
    c : Unit <- row("gate_c1", b2u(gate(fx1.ar(), O.Arena.src0(fx1.ar(), fx1.top()))))
    d : Unit <- row("budget", U32.from_nat(O.Arena.budget(fx1.ar())))
    e : Unit <- row("part_len", U32.from_nat(List.length(&2, U32, H.part_yes(H.partition(0, [1,2,3])))))
    f : Unit <- row("p0", U32.from_nat(List.length(&2, O.Sint, F.param_shape(O.AParam{pa(0,"a",None{},None{})}))))
    row("alive", 0)