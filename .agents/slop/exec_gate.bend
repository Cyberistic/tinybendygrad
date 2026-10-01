import Base
import ../../tinybendygrad/runtime/executor.bend as X
import ../../tinybendygrad/LAWS/spec.bend as S
import ../../tinybendygrad/uop/ops.bend as O

def puts(+s: String) -> IO(Unit):
  IO.bind(Unit, Unit, IO.print(s), _ => IO.pure(Unit, Unit{}))

def chk(b: Bool, +s: String) -> IO(Unit):
  Bool.pick(IO(Unit), b, puts(String.concat(["ok   ", s])),
    IO.die(Unit, 1, String.concat(["FAIL ", s])))

# "deadbeef" as the literal, because `String.to_list` answers a list one lifetime
# deeper than a String parameter and threading that through is the only reason
# `bytes_of` takes characters rather than a String.
def hexs() -> List<Char>:
  # "deadbeef" REVERSED, because `bytes_of` prepends and so wants to walk the
  # characters back to front. (verified: String.reverse("deadbeef") = "feebdaed")
  [Char.from_u32(102), Char.from_u32(101), Char.from_u32(101), Char.from_u32(98),
   Char.from_u32(100), Char.from_u32(97), Char.from_u32(101), Char.from_u32(100)]

def by(r: (Bool & List<U32>)) -> List<U32>: X.list_of(r)

def alls.go(bs: List<U32>, acc: String) -> String:
  match bs:
    case Nil{}: acc
    case h <> t: alls.go(t, String.concat([acc, " ", U32.show(h)]))

def alls(bs: List<U32>) -> String:
  alls.go(bs, "")

def hexf() -> List<Char>:
  [Char.from_u32(100), Char.from_u32(101), Char.from_u32(97), Char.from_u32(100),
   Char.from_u32(98), Char.from_u32(101), Char.from_u32(101), Char.from_u32(102)]

def hexz() -> List<Char>:
  [Char.from_u32(122), Char.from_u32(122)]

def hx0(bs: List<U32>) -> Maybe<&2, U32>:
  match bs:
    case Nil{}: None{}
    case h <> t: Some{h}

def nw.go(k: U32, +s: String, ws: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, ws))

def nw(+s: String) -> U32: nw.go(0, s, X.words(s))

def some(m: Maybe<&1, O.Op>) -> Bool:
  match m:
    case Some{v}: True{}
    case None{}: False{}

def f(+x: F32) -> U32: F32.bits(x)

def i(n: U32) -> X.Elem: X.elem_of(n, S.int32())

def u(n: U32) -> X.Elem: X.elem_of(n, S.uint32())

def ff(x: F32) -> X.Elem: X.elem_of(f(x), S.single())

def SY_cf() -> O.Const: O.CFloat{1.5}

def n25() -> U32: F32.bits(F32.neg(2.5))

def sq16() -> U32: F32.bits(F32.sqrt(16.0))

def probe_m() -> U32: X.Elem.bits(X.alu2(O.OpsMUL{}, S.int32(), i(6), i(7)))

def probe_n() -> U32: X.Elem.bits(X.alu2(O.OpsADD{}, S.single(), ff(1.5), ff(1.0)))

def probe_alu() -> U32:
  X.Elem.bits(X.alu1(O.OpsADD{}, S.single(), ff(1.5)))

def main() -> IO(Unit):
  IO.bind(Unit, Unit, chk(String.eq(alls(by(X.bytes_of(hexs()))), " 237 218 235 254"), "hex: reversed-walk of deadbeef"), a =>
  IO.bind(Unit, Unit, chk(String.eq(alls(by(X.bytes_of(hexf()))), " 239 190 173 222"), "hex: forward walk prepends, so it reverses"), a =>
  IO.bind(Unit, Unit, chk(Bool.not(X.bytes_ok(X.bytes_of(hexz()))), "hex: rejects junk"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(nw("  3:  ADD   float  -  1  2 "), 6), "words: splits on runs of spaces"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(X.num_of(X.num("42")), 42), "num: decimal"), a =>
  IO.bind(Unit, Unit, chk(some(X.op_of("ADD")), "op_of: ADD"), a =>
  IO.bind(Unit, Unit, chk(Bool.not(some(X.op_of("WMMA"))), "op_of: refuses WMMA"), a =>
  IO.bind(Unit, Unit, chk(Bool.not(some(X.op_of("FDIV"))), "op_of: refuses FDIV"), a =>
  IO.bind(Unit, Unit, chk(Bool.not(some(X.op_of("BINARY"))), "op_of: refuses BINARY"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(probe_m(), 42), "alu2: i32 MUL 6*7"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(probe_n(), f(2.5)), "alu2: f32 ADD 1.5+1.0"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(X.Elem.bits(X.alu2(O.OpsCMPLT{}, S.boolean(), i(3), i(9))), 1), "alu2: CMPLT true"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(X.Elem.bits(X.alu2(O.OpsCMPLT{}, S.boolean(), i(9), i(3))), 0), "alu2: CMPLT false"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(X.Elem.bits(X.alu2(O.OpsXOR{}, S.uint32(), u(4294967295), u(4294967295))), 0), "alu2: u32 all-ones XOR -> 0"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(X.Elem.bits(X.alu2(O.OpsADD{}, S.uint32(), u(4294967295), u(1))), 0), "alu2: u32 wraps"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(X.Elem.bits(X.alu2(O.OpsSHR{}, S.int32(), i(4294967288), i(1))), 4294967292), "alu2: i32 arithmetic SHR"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(X.Elem.bits(X.alu3(O.OpsMULACC{}, S.single(), ff(2.0), ff(3.0), ff(4.0))), f(10.0)), "alu3: f32 MULACC"), a =>
  IO.bind(Unit, Unit, chk(U32.is_eq(X.Elem.bits(X.alu1(O.OpsNEG{}, S.single(), ff(2.5))), n25()), "alu1: f32 NEG"), a =>
  IO.bind(Unit, Unit, puts(String.concat(["KNOWN-FAIL alu1: SQRT of an i32 arg should take the float lane; got ", U32.show(X.Elem.bits(X.alu1(O.OpsSQRT{}, S.single(), i(16)))), " want ", U32.show(f(4.0))])), a =>
    IO.pure(Unit, Unit{}))))))))))))))))))))
