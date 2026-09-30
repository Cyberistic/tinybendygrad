import Base

# The answer to the wall: a rule table field can only take an AFFINE argument, so
# the engine cannot hand a rule the arena (a rule needs several nodes). It hands
# the rule a SNAPSHOT -- one node, flattened, `Data` -- and the rule DESTRUCTURES
# it once. The binders are then separate values, each usable once, and each
# readable field by field. So a rule CAN reach several nodes, as long as they
# arrive in one record and the rule matches it at the top.

type Snap is Data:
  Snap{k: U32, lhs: U32, rhs: U32, extra: U32}

type V is Data:
  VTrue{}
  VFalse{}
  VSkip{}

type Rule is Type:
  Rv{test: (Snap -> V)}

# `when(cond, v)` IS `if cond: v else None` and `when_bad(cond, v)` is
# `if not cond: v else None` -- the two shapes most of spec.py's rule bodies
# have. Both are leaves, and they are what keep a rule one def instead of three,
# because a `match` may not scrutinise a call.
def when_bad(b: Bool, v: V) -> V:
  match b:
    case True{}: VSkip{}
    case False{}: v

def when(b: Bool, v: V) -> V:
  match b:
    case True{}: v
    case False{}: VSkip{}

# reads FOUR values out of the snapshot and still gets the table to accept it
def same(lhs: U32, rhs: U32, extra: U32) -> V:
  when(U32.is_eq(lhs, rhs), VTrue{})

def alu.of(k: U32, lhs: U32, rhs: U32, extra: U32) -> V:
  when(U32.is_eq(k, 1), same(lhs, rhs, extra))

def alu(s: Snap) -> V:
  match s:
    case Snap{k, lhs, rhs, extra}: alu.of(k, lhs, rhs, extra)
def other.of(lhs: U32, rhs: U32) -> V:
  when(U32.is_eq(U32.add(lhs, rhs), 0), VFalse{})




def other(s: Snap) -> V:
  match s:
    case Snap{k, lhs, rhs, extra}: other.of(lhs, rhs)


# A THIRD rule, claiming a NARROWER condition than `alu` and answering False.
# Without a node that TWO rules both match, the gate cannot tell first-wins from
# "every rule must agree", and a mutation that changes one into the other moves
# NOTHING. Narrower matters: a rule claiming everything `alu` claims would make
# every `alu` node a collision and the two rows the same test.
def clash.of(k: U32, extra: U32) -> V:
  when(Bool.and(U32.is_eq(k, 1), U32.is_eq(extra, 9)), VFalse{})

def clash(s: Snap) -> V:
  match s:
    case Snap{k, lhs, rhs, extra}: clash.of(k, extra)


def r_clash() -> Rule:
  Rv{clash}

def r_alu() -> Rule:
  Rv{alu}

def r_other() -> Rule:
  Rv{other}

def table() -> List<Rule>:
  [r_alu(), r_other(), r_clash()]

def keep.skip(v: V) -> V:
  match v:
    case VSkip{}: VSkip{}
    case VTrue{}: VTrue{}
    case VFalse{}: VFalse{}

def keep(+acc: V, v: V) -> V:
  match acc:
    case VSkip{}: keep.skip(v)
    case VTrue{}: VTrue{}
    case VFalse{}: VFalse{}

def spec_pass(rules: List<Rule>, +s: Snap, +acc: V) -> V:
  match rules:
    case Nil{}: acc
    case Rv{test} <> rest: spec_pass(rest, s, keep(acc, test(s)))

# src 7 == 7 and extra 0 -> the ALU rule says True and the other cannot undo it
def show(v: V) -> U32:
  match v:
    case VTrue{}: 1
    case VFalse{}: 0
    case VSkip{}: 9

def t_true() -> U32: show(spec_pass(table(), Snap{1, 7, 7, 0}, VSkip{}))
# the ALU rule SKIPS (lhs != rhs) and the SECOND rule says False -- so this row is
# what proves the pass keeps looking past a Skip instead of stopping
def t_false() -> U32: show(spec_pass(table(), Snap{9, 0, 0, 1}, VSkip{}))
# a node no rule wants
def t_skip() -> U32: show(spec_pass(table(), Snap{9, 1, 1, 1}, VSkip{}))


# a node TWO rules claim: `alu` says True, `clash` says False. First-wins makes
# this True; a conjunction makes it False. That is the row the gate was missing.
def t_clash() -> U32: show(spec_pass(table(), Snap{1, 7, 7, 9}, VSkip{}))

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("true", t_true())
    b : Unit <- row("false", t_false())
    c : Unit <- row("skip", t_skip())
    row("clash", t_clash())

# ---------------------------------------------------------------------------
# THE GATE. `main` prints one row per claim and the gate is that both lanes
# print these four lines. A `9` is a Skip, which is a real answer and not a
# failure: it is what a rule says when the pattern does not apply.
#
#   true=1  the ALU rule claims a node and answers True, and neither later rule
#           may undo it
#   false=0 the ALU rule SKIPS and a later rule answers False, so the pass kept
#           looking past a Skip
#   skip=9  no rule claims the node
#   clash=1 two rules claim the SAME node -- `alu` says True, `clash` says False
#           -- and FIRST wins
#
# MUTATIONS, both re-run 2026-09-30 against this file:
#
# | mutation | rows that moved |
# | --- | --- |
# | `keep` keys on `v`: last-non-skip wins instead of first | `clash` |
# | `keep` becomes a conjunction: "every rule must agree" | `clash` |
#
# Both move `clash` and nothing else, which is the POINT of the row: `clash` is
# the only node two rules claim, so it is the only row that can see the
# difference between first-wins and anything else.
#
# That row was added because the conjunction mutation moved NOTHING without it.
# With no node that two rules both match, a gate cannot tell first-wins from a
# conjunction -- and adding the row then found a SECOND bug, because the `keep`
# I had written really was last-wins while `PatternMatcher.rewrite` returns the
# FIRST non-None. Two of the four claims in this file were wrong on first run.
