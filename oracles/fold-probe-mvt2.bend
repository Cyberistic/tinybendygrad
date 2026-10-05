# P6..P10 -- the exact walk shapes the five movement arms need, probed before
# fold.bend is edited. P1..P5 are in fold-probe-mvt.bend.
import Base
import ../../../tinybendygrad/uop/ops.bend as O
import ../../../tinybendygrad/helpers.bend as H

# ---------------------------------------------------------------------------
# A DIM AS A COUNT, or a refusal. Python's `resolve(sz>=0)` and friends read a
# `sint` as a NUMBER; an `O.SU` is an arena index and is not one, so it is None.
# ---------------------------------------------------------------------------
def some_i64(ok: Bool, +x: U32) -> Maybe<&1, U32>:
  match ok:
    case True{}: Some{x}
    case False{}: None{}

def d6.of(+i: H.I64) -> Maybe<&1, U32>:
  some_i64(Bool.not(H.i64_is_neg(i)), H.lo32(i))

def d6(d: O.Sint) -> Maybe<&1, U32>:
  match d:
    case O.SU{u}: None{}
    case O.SI{i}: d6.of(i)

# THE THREE HEADS OF ONE LOCKSTEP STEP, and `None` if any of them is symbolic.
type T3 is Data:
  T3{s: U32, o: U32, z: U32}

def T3.of3(s: U32, o: U32, c: Maybe<&1, U32>) -> Maybe<&1, T3>:
  match c:
    case Some{z}: Some{T3{s, o, z}}
    case None{} : None{}

def T3.put3(s: U32, o: U32, z: O.Sint) -> Maybe<&1, T3>:
  T3.of3(s, o, d6(z))

def T3.of2(s: U32, b: Maybe<&1, U32>, z: O.Sint) -> Maybe<&1, T3>:
  match b:
    case Some{o}: T3.put3(s, o, z)
    case None{} : None{}

def T3.put2(s: U32, o: O.Sint, z: O.Sint) -> Maybe<&1, T3>:
  T3.of2(s, d6(o), z)

def T3.put(a: Maybe<&1, U32>, o: O.Sint, z: O.Sint) -> Maybe<&1, T3>:
  match a:
    case Some{s}: T3.put2(s, o, z)
    case None{}  : None{}

def T3.of(p: O.Sint, o: O.Sint, z: O.Sint) -> Maybe<&1, T3>:
  T3.put(d6(p), o, z)

# `resolve(sz>=0) and resolve(0<=o) and resolve(o+s<=sz)` -- and SHRINK's
# `o+sz<=s`. `pad` picks the arm; both need the three heads twice each, which is
# what the `Data` record plus `+` binders is for.
def T3.le(t: T3, pad: Bool) -> Bool:
  match t:
    case T3{+s, +o, +z}:
      Bool.pick(Bool, pad, U32.is_le(U32.add(o, s), z), U32.is_le(U32.add(o, z), s))

# ---------------------------------------------------------------------------
# THE LOCKSTEP WALK. `zip(self.src[1].as_shape, self.src[2].as_shape)` paired
# with `zip(ps, marg)` -- one walk, and the answer rides along.
# ---------------------------------------------------------------------------
type Z6 is Data:
  Z6{szs: List<&2, O.Sint>, ok: Bool}

def Z6.szs(x: Z6) -> List<&2, O.Sint>:
  match x:
    case Z6{szs, ok}: szs

def Z6.ok(x: Z6) -> Bool:
  match x:
    case Z6{szs, ok}: ok

def z6.ok_of(t: Maybe<&1, T3>, pad: Bool, good: Bool) -> Bool:
  match t:
    case Some{v}: Bool.and(good, T3.le(v, pad))
    case None{}  : False{}

def z6.go(ps: List<&2, O.Sint>, os: List<&2, O.Sint>, szs: List<&2, O.Sint>, +pad: Bool, +x: Z6) -> Z6:
  match ps os szs:
    case Nil{} Nil{} Nil{}        : x
    case p <> pt, o <> ot, +z <> zt : z6.go(pt, ot, zt, pad, Z6{List.append(&2, O.Sint, Z6.szs(x), [z]), z6.ok_of(T3.of(p, o, z), pad, Z6.ok(x))})
    case _ _ _                    : Z6{Z6.szs(x), False{}}

def z6(ps: List<&2, O.Sint>, os: List<&2, O.Sint>, szs: List<&2, O.Sint>, pad: Bool) -> Z6:
  z6.go(ps, os, szs, pad, Z6{Nil{}, True{}})

def one4() -> O.Sint: O.SI{H.i64_of_i32(4)}
def one0() -> O.Sint: O.SI{H.i64_of_i32(0)}
def one6() -> O.Sint: O.SI{H.i64_of_i32(6)}
def one1() -> O.Sint: O.SI{H.i64_of_i32(1)}
def one3() -> O.Sint: O.SI{H.i64_of_i32(3)}
def two2() -> O.Sint: O.SI{H.i64_of_i32(2)}

def q1() -> Bool: Z6.ok(z6([one4()], [one0()], [one6()], True{}))
def q2() -> Bool: Z6.ok(z6([one4()], [one1()], [one3()], True{}))
def q3() -> Bool: Z6.ok(z6([one4(), one3()], [one0()], [one6()], True{}))
def q4() -> Bool: Z6.ok(z6([one4()], [one1()], [two2()], False{}))
def q5() -> Bool: Z6.ok(z6([one4()], [one1()], [one4()], False{}))
def q6() -> Bool: Nat.is_eq(List.length(&2, O.Sint, Z6.szs(z6([one4()], [one0()], [one6()], True{}))), 1n)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["q1=", Bool.show(q1())]))
    IO.print(String.concat(["q2=", Bool.show(q2())]))
    IO.print(String.concat(["q3=", Bool.show(q3())]))
    IO.print(String.concat(["q4=", Bool.show(q4())]))
    IO.print(String.concat(["q5=", Bool.show(q5())]))
    IO.print(String.concat(["q6=", Bool.show(q6())]))
