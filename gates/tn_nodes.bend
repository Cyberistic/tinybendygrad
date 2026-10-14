# tn_nodes.bend -- EVERY NODE of `tn_isfinite`, as one row per node, in toposort order.
#
#   .venv/bin/python gates/tn_nodes-gate.py
#
# WHY THIS FILE EXISTS. `gates/tn_isfinite.bend` asks six questions about the TOP node
# only -- op, arg, nsrc, reachability, `src[1]` is CONST, `src[1]` is not self -- and
# `gates/tn_graph_census.bend` asks one question about the WHOLE graph, which
# `Rng.sig` spells `15 Ops.CMPNE/2 Ops.OR Ops.CONST`: a COUNT, the root's op, the
# root's src count, and the root's DIRECT src ops. Every other node is one undifferentiated
# unit of that `15`.
#
# THE DEFECT BOTH MISSED, MEASURED. `tn_isfinite.isinf_part` compared the positive arm's
# bool MUL against `-inf`, so node 7 was `CMPNE(MUL, CONST)` where CPython has
# `CMPNE(CONST, CONST)`: **the same count, the wrong srcs, four levels down.** Both gates
# read it as agreement -- the count was right, the root was right, the root's srcs were
# right. `.agents/slop/tnisf/dump2.bend` caught it and nothing else ever did, which is why
# this file exists and why its inputs sit in `gates/` rather than under `.agents/slop/`.
#
# THE ROW, AND WHY THESE FOUR FIELDS.
#   n<k>       the node's TOPOSORT POSITION, and the row's name. Both lanes run the same
#              DFS postorder, so position k on the port is position k on the oracle.
#   <op>/<n>   the node's op and its src count.
#   srcs=...   its srcs as TOPOSORT POSITIONS, IN SLOT ORDER, `|`-separated.
#   arg=, dt=  the node's own `Arg` and its dtype.
#
# WHY `srcs=` NAMES POSITIONS AND NOT OPS. `Rng.srcops` already prints src op NAMES, and
# op names would have caught this graph's defect -- `Ops.MUL` against `Ops.CONST`. They
# would NOT catch `ADD(mul_a, mul_b)` spelled `ADD(mul_b, mul_a)`, or `MUL` reading
# `src[1]` where CPython reads `src[0]`: same ops, same multiset, same count, wrong graph.
# A POSITION is a node's identity, so a swap moves a number even when both sides of the
# swap are the same op. This is the whole difference between a census that compares
# counts and one that compares wiring.
#
# WHY NOTHING IS SORTED, DEDUPED OR CANONICALISED HERE. `gatekit` diffs two ORDERED lists
# of lines, so row k is compared with row k. There is no multiset step anywhere on this
# path, which is why the gate cannot reproduce the `tn_isfinite` pin's own failure: that
# pin blamed an extra CAST because three extra casts and one missing const CANCELLED to
# +2. Per-node rows cannot cancel -- a substitution changes the row it lands in.
#
# THE INPUT IS `CInt{4}`, and so is the oracle's (`tn_graph_census`'s `t4`), so the two
# lanes build the same graph. `O.CFloat{4.0}` puts `bend` over its elaboration limit here
# -- `tn_isfinite.bend`'s header records it -- and is not needed: `isfinite`'s arms are
# `eq(±inf)`, so the graph holds both float consts either way.

import Base
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/weak.bend as W
import ./../tinybendygrad/tensor.bend as T

def t4() -> T.Tensor:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  t : T.Tensor = T.Tensor{O.Found.ar(c), O.Found.i(c), True{}, 0}
  t

# THE PORT'S OWN CONST SPELLING, and it is the port's because it is what the arena holds:
# `CFloat`/`CInt`/`CBool` are the three `Const` variants, and `H.i64_text` is `hi:lo`.
# The oracle MIRRORS these glyphs and nothing else -- see `tn_nodes-oracle.py`'s header,
# which says why a glyph translation is safe here and a structural one would not be.
def cstr(c: O.Const) -> String:
  match c:
    case O.CFloat{f}: String.concat(["f", F32.show(f)])
    case O.CInt{i}: String.concat(["i", H.i64_text(i)])
    case O.CBool{b}: String.concat(["b", U32.show(Bool.to_u32(b))])
    case _: "?"

# Every non-CONST node carries `ANone`, so `-` is both the null glyph and the empty-srcs
# glyph in `srcpos` below. They cannot collide: a node with srcs prints its srcs.
def argstr(a: O.Arg) -> String:
  match a:
    case O.APy{v}: cstr(v)
    case _: "-"

def dtnm.go(dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: nm

def dtnm(+ar: O.Arena, +h: U32) -> String:
  dtnm.go(W.wk_dt(F.folded(ar), h))

# THE POSITION OF A HANDLE in the toposort. `Arena` indices are an allocation ORDER and
# CPython's are object identities, so neither side can print the other's -- but both can
# print the same DFS postorder, and position k of that order is the one name the two
# graphs provably share. MEASURED on this graph, the port's arena indices come out
# `2 3 4 5 6 7 8 9 10 11 12 1 13 14 15` while CPython's are `0..14`: the input CONST is
# allocated first and VISITED eleventh. This fold is what removes that difference, and
# `srcs=` is why it is here at all -- see the header's `WHY srcs= NAMES POSITIONS`.
#
# IT IS A RUNNING-BEST FOLD AND NOT A `Bool.pick` OF TWO RECURSIONS because `Bool.pick`
# evaluates BOTH arms. MEASURED, the `Bool.pick` spelling answers
#   - expected : t / observed : t (consumed more than once)
# for the target that is already `+h` of the match, and the fix is the `+` on `t` and `k`
# below: a `+`-prefixed param is DUPLICABLE, a bare one is consumed once per arm. That is
# the whole rule, and it is why `dump2.bend`'s `dump.go` can carry `+ar` through fifteen
# iterations while a bare `ar` could not.
#
# THE SEED IS `n`, THE NODE COUNT, and not `0n`. A handle absent from the list would then
# print a number no node has, so it is a DISAGREEMENT rather than a silent alias of the
# real position 0. Every call site passes the src of a node that is IN the list, so the
# seed is never printed; this says what happens if that ever stops being so.
def pos.go(+t: U32, xs: List<&2, U32>, +k: Nat, +best: Nat) -> Nat:
  match xs:
    case Nil{}: best
    case h <> r: pos.go(t, r, 1n+k, Bool.pick(Nat, U32.is_eq(h, t), k, best))

def pos(all: List<&2, U32>, n: Nat, t: U32) -> Nat:
  pos.go(t, all, 0n, n)

def srcpos.go(+ar: O.Arena, +all: List<&2, U32>, +n: Nat, ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: srcpos.go(ar, all, n, t, List.append(&2, String, acc, [Nat.show(pos(all, n, s))]))

def srcpos(+ar: O.Arena, all: List<&2, U32>, n: Nat, ss: List<&2, U32>) -> List<&2, String>:
  match ss:
    case Nil{}: ["-"]
    case _: srcpos.go(ar, all, n, ss, Nil{})

def one(+ar: O.Arena, +h: U32, all: List<&2, U32>, n: Nat) -> String:
  String.concat([O.Ops.name(O.Arena.op(ar, h)), "/", U32.show(O.Arena.nsrc(ar, h)),
                 " srcs=", String.join(srcpos(ar, all, n, O.Arena.srcs(ar, h)), "|"),
                 " arg=", argstr(O.Arena.arg(ar, h)), " dt=", dtnm(ar, h)])

# ONE STRING, ONE PRINT, FIFTEEN LINES. `gatekit` counts LINES, so the rows are lines
# whether they arrive from fifteen prints or one, and a single fold keeps `arena`, `all`
# and the index linear instead of threading an `IO` chain.
def rows.go(+ar: O.Arena, ts: List<&2, U32>, +all: List<&2, U32>, +n: Nat, +k: Nat, +acc: String) -> String:
  match ts:
    case Nil{}: acc
    case h <> t:
      rows.go(ar, t, all, n, 1n+k, acc ++ "n" ++ Nat.show(k) ++ "=" ++ one(ar, h, all, n) ++ "\n")

def rows(+ar: O.Arena, +all: List<&2, U32>, n: Nat) -> String:
  rows.go(ar, all, all, n, 0n, "")

def main() -> IO(Unit):
  +r = T.tn_isfinite(t4())
  +ar = T.Tensor.ar(r)
  +ts = O.UOp.toposort(O.Arena.budget(ar), ar, T.Tensor.u(r))
  do IO<Unit>:
    IO.print(rows(ar, ts, List.length(&2, U32, ts)))
    return Unit{}