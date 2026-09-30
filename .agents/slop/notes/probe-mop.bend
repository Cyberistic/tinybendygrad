import Base
import ../../../tinybendygrad/helpers.bend as H
import ../../../tinybendygrad/LAWS/spec.bend as S
import ../../../tinybendygrad/uop/ops.bend as O
import ../../../tinybendygrad/uop/fold.bend as F

# 1. does a PAIR work as a list element?
type Marg is Data:
  Marg{off: O.Sint, sz: O.Sint}

def margs() -> List<&2, Marg>:
  [Marg{O.SInt.of(H.i64_of_i32(0)), O.SInt.of(H.i64_of_i32(4))}]

def marg_pairs() -> List<&2, O.Sint & O.Sint>:
  [(O.SInt.of(H.i64_of_i32(0)), O.SInt.of(H.i64_of_i32(4)))]

def t_pairs() -> U32:
  U32.from_nat(List.length(&2, O.Sint & O.Sint, marg_pairs()))

# 2. the Hop shape: a rule result is an arena plus the answer index, and 0 is
# ops.bend's existing spelling of Python's `None` UOp.
type Hop is Data:
  Hop{ar: O.Arena, at: U32}

def hop_ar(h: Hop) -> O.Arena:
  match h:
    case Hop{ar, at}: ar

def hop_ix(h: Hop) -> U32:
  match h:
    case Hop{ar, at}: at

# `if b: v else None` for the index
def hop_first.of(b: Bool, hold: U32, r: U32) -> U32:
  match b:
    case True{}: r
    case False{}: hold

def hop_first(+hold: U32, r: U32) -> U32:
  hop_first.of(O.UOp.is_none(hold), hold, r)

# THE FOLD: first non-None wins, and the arena is threaded to the rule that fires
def hop_next(h: Hop, r: Hop) -> Hop:
  match h r:
    case Hop{ha, hn} Hop{ra, rn}: Hop{ra, hop_first(hn, rn)}

# the rule. a BUFFER that becomes a STACK of its own first src
def hop_stack2(+fx: F.Folded, +self: U32) -> Hop:
  +f = O.UOp.alu(F.Folded.ar(fx), O.OpsSTACK{}, [O.Arena.src(F.Folded.ar(fx), self, 0), O.Arena.src(F.Folded.ar(fx), self, 1)])
  Hop{O.Found.ar(f), O.Found.i(f)}

def mp_r7.of(b: Bool, +fx: F.Folded, self: U32) -> Hop:
  match b:
    case True{}: hop_stack2(fx, self)
    case False{}: Hop{F.Folded.ar(fx), 0}

def mp_r7(+fx: F.Folded, +self: U32) -> Hop:
  mp_r7.of(O.eq_op(O.Arena.op(F.Folded.ar(fx), self), O.OpsCONST{}), fx, self)

def mp_dispatch.go(tag: U32, +fx: F.Folded, +self: U32) -> Hop:
  match tag:
    case 7: mp_r7(fx, self)
    case _: Hop{F.Folded.ar(fx), 0}

def mp_dispatch(tag: U32, +fx: F.Folded, +self: U32) -> Hop:
  mp_dispatch.go(tag, fx, self)

# THE ONE RECURSIVE DEF
def mp_scan(rs: List<&2, O.PMEntry>, +fx: F.Folded, +self: U32, +h: Hop) -> Hop:
  match rs:
    case Nil{}: h
    case e <> t: mp_scan(t, fx, self, hop_next(h, mp_dispatch(O.PMEntry.tag(e), fx, self)))

def mp_rewrite(rs: List<&2, O.PMEntry>, +fx: F.Folded, self: U32) -> Hop:
  mp_scan(rs, fx, self, Hop{F.Folded.ar(fx), 0})

def table() -> List<&2, O.PMEntry>:
  [O.PMEntry{7, [O.OpsINDEX{}], Nil{}}]

def build() -> F.Folded:
  +z = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(0)})
  +one = O.UOp.const(O.Found.ar(z), O.CInt{H.i64_of_i32(1)})
  F.folded(O.Found.ar(one))

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def t_marg() -> U32:
  U32.from_nat(List.length(&2, Marg, margs()))

def t_marg_pairs() -> U32:
  t_pairs()

def t_fires() -> U32:
  +fx = build()
  hop_ix(mp_rewrite(table(), fx, 1))

def t_none() -> U32:
  +fx = build()
  hop_ix(mp_rewrite(table(), fx, 2))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("marg", t_marg())
    b : Unit <- row("mpairs", t_marg_pairs())
    c : Unit <- row("fires", t_fires())
    row("none", t_none())
