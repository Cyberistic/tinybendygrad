import Base
import ./LAWS/spec.bend as S

def buf(n: Nat) -> S.Sp: S.SpBuffer{n, S.int32(), S.D1{1}, S.AGlobal{}}
def rng(n: Nat) -> S.Sp: S.SpRange{S.SpBinary{n}}

def both(a: Bool, b: Bool) -> Bool:
  match a:
    case True{}: b
    case False{}: False{}

def go(ds: List<&2, S.Sdim>, want: List<&2, S.Sdim>) -> Bool:
  match ds:
    case Nil{}:
      match want:
        case Nil{}: True{}
        case _ <> _: False{}
    case S.SN{v} <> r:
      match want:
        case S.SN{w} <> ws: both(Nat.is_eq(v, w), go(r, ws))
        case _ <> _: False{}
        case Nil{}: False{}
    case S.SS{x} <> _:
      match want:
        case _ <> _: False{}
        case Nil{}: False{}

def chk(m: Maybe<&2, S.Shape>, want: List<&2, S.Sdim>) -> Bool:
  match m:
    case Some{sh}: go(S.Shape.to_dims(sh), want)
    case None{}: False{}

def chkd(m: Maybe<&2, S.Dt>, pri: U32, bits: U32) -> Bool:
  match m:
    case Some{+x}: both(U32.is_eq(S.Dt.pri(x), pri), U32.is_eq(S.Dt.bits(x), bits))
    case None{}: False{}

def is_none(m: Maybe<&2, S.Shape>) -> Bool:
  match m:
    case Some{_}: False{}
    case None{}: True{}

# Index(T(4), I(2)) -> the index shape (2,), the base loses one dim -> (2,)
def t1() -> Bool: chk(S.Sp.shape(S.SpIdx1{buf(4n), buf(2n)}), [S.SN{2n}])
# Index(T(4), I(2), I(3)) -> (2, 3)
def t2() -> Bool: chk(S.Sp.shape(S.SpIdx2{buf(4n), buf(2n), buf(3n)}), [S.SN{2n}, S.SN{3n}])
def t3() -> Bool: chk(S.Sp.shape(S.SpIdx3{buf(4n), buf(2n), buf(3n), buf(4n)}), [S.SN{2n}, S.SN{3n}, S.SN{4n}])
def t4() -> Bool: chk(S.Sp.shape(S.SpIdx4{buf(4n), buf(1n), buf(2n), buf(3n), buf(4n)}), [S.SN{1n}, S.SN{2n}, S.SN{3n}, S.SN{4n}])
# a ()-shaped index removes a dim: Index(T(4), Range(3)) -> ()
def t5() -> Bool: chk(S.Sp.shape(S.SpIdx1{buf(4n), rng(3n)}), Nil{})
# Stack of three (4,) -> (3, 4)
def t6() -> Bool: chk(S.Sp.shape(S.SpStack{[buf(4n), buf(4n), buf(4n)]}), [S.SN{3n}, S.SN{4n}])
# Stack of one -> (1, 4)
def t7() -> Bool: chk(S.Sp.shape(S.SpStack{[buf(4n)]}), [S.SN{1n}, S.SN{4n}])
# an empty Stack has no shape
def t8() -> Bool: is_none(S.Sp.shape(S.SpStack{Nil{}}))
# Reduce drops the first axis of (4,) -> ()
def t9() -> Bool: chk(S.Sp.shape(S.SpReduce{buf(4n), Nil{}, S.SpInvalid{}, 1n}), Nil{})
# dtype threads through Index, from src[0]
def t10() -> Bool: chkd(S.Sp.dtype(S.SpIdx2{S.SpCast{buf(4n), S.int8()}, S.SpBinary{1n}, S.SpBinary{1n}}), 1, 8)
# dtype of Stack is the head's
def t11() -> Bool: chkd(S.Sp.dtype(S.SpStack{[S.SpCast{buf(4n), S.int16()}, buf(4n)]}), 3, 16)
# a broadcast Max of (2,) and (2,2) is (2,2)
def t12() -> Bool: chk(S.Sp.shape(S.SpMax{buf(2n), S.SpReshape{buf(4n), S.SpInvalid{}, [S.SN{2n}, S.SN{2n}]}}), [S.SN{2n}, S.SN{2n}])
# the element count of Stack is the operand count times the head's count
def t13() -> Bool: Nat.is_eq(S.dims_prod(S.Sp.shape(S.SpStack{[buf(4n), buf(4n), buf(4n)]})), 12n)
# the element count survives Permute
def t14() -> Bool:
  Nat.is_eq(S.dims_prod(S.Sp.shape(S.SpPermute{buf(4n), [1n, 0n]})), S.dims_prod(S.Sp.shape(buf(4n))))

def main() -> Bool: t11()
