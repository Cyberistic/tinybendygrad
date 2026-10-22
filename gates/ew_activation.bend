# ew_activation.bend -- THE PORT LANE of the ACTIVATION FAMILY comparison.
#
#   ./bin/bend gates/ew_activation.bend > gates/artifacts/ew_activation-gate/bd.out
#
# IT PRINTS THE GRAPH EACH PORTED ACTIVATION BUILDS, NODE BY NODE, FOR EVERY
# FIXTURE.  The CPython lane is `gates/ew_activation-oracle.py`, the canonical
# graph diff and the value are `gates/ew_activation-compare.py`, and the
# mutation harness is `gates/ew_activation-plant.py`.
#
# WHY IT LIVES IN `gates/` AND NOT IN `.agents/slop/`.  `gates/README.md`: "a
# gate's `.bend` driver and its CPython oracle sit in `gates/`, named by the
# gate that needs them", because a sweep of `.agents/slop/` deleted seven of
# nine driver/oracle files out from under gates that were still naming them.
# THIS DRIVER FOUND TWO REAL PORT DEFECTS -- `uop/fold.bend`'s missing
# `CWeakFloat` arm and `mixin/elementwise.bend`'s `ew_tanh` operand order --
# and the instrument that found them was untracked in a directory that is
# being pruned.  It is beside its gate now.
#
# WHY A FLAT, ID-BEARING DUMP AND NOT A NESTED S-EXPRESSION.  A nested printer
# has to recurse over the GRAPH, and Bend's termination check wants a SMALLER
# PART of an input -- so a nested printer over a DAG is either mutual recursion
# (which Bend forbids: "two mutually recursive functions become one def with an
# extra argument selecting which to run") or a fuel.  The flat form needs
# NEITHER: the toposort is already computed by `O.UOp.toposort`, and each node
# is printed once with its srcs as ARENA INDICES.  The ids are the port's own,
# so the comparison has to be CANONICAL rather than positional -- and
# `ew_activation-compare.py` builds the canonical form on both sides.
#
# WHAT A ROW CARRIES, per node: the node's ARENA INDEX (the id), the OP, the
# DTYPE, the ARGUMENT (the f32 BITS of a float constant, the integer of an int
# constant, the target dtype of a CAST) and the srcs IN SLOT ORDER.
#
# WHY ALL OF THAT, AND NOT JUST THE OPS.  `gates/ew_graph_census.bend`'s
# `Rng.sig` prints the op SEQUENCE and the ROOT's src ops, and that is enough
# for a row whose claim is "the same ops in the same order".  The activations
# this lane covers are exactly the family where the STRONGER claim is the one
# that matters: `asin` is a Horner polynomial of EIGHT coefficients, and a
# wrong ORDER of them changes no op and no node COUNT -- it changes WHICH
# CONSTANT is added when.  The CONSTANT BITS are the only thing that sees it,
# and the DTYPE is what sees a wrong PROMOTION.  `ew_tanh`'s operand order is
# the second instance: the census's `ew_tanh` row prints the ROOT's src ops,
# and the root is the ADD of `sub` either way -- `Ops.MUL Ops.MUL` -- so the
# signature was IDENTICAL for the right graph and the wrong one.
#
# THE FIXTURES ARE THE EDGES, and they are HERE and not in the oracle, so the
# oracle needs no list of its own: it reads the fixture's f32 BITS out of the
# row this lane prints and builds CPython's tensor from THOSE.  One list, one
# source.
#
#   0.0 and -0.0      the zero, and the SIGNED zero (they are different CONSTs)
#   1.0 and -1.0      the DOMAIN BOUNDARIES of `asin`/`acos`
#   0.5 and -0.5      the interior, and the sign
#   2.0 and -2.0      OUTSIDE the domain: `sqrt(1 - 2)` is NaN and the port must say so
#   3.0 and -3.0      further out
#   0.001 and -0.001  near zero
#   1e6 and -1e6      very large
#   +inf and -inf     the infinities
#   NaN               the NaN, which is the answer for `asin` of an out-of-domain value
#
# AND THE PARAMETERS ARE IN THE ROW, so the oracle can call `Tensor.elu(alpha)`
# with the SAME alpha the port used -- including a NON-DEFAULT one, because "a
# wrong alpha default" is a failure mode that a default-only fixture cannot
# see.  THAT FIXTURE IS NOT COSMETIC: MEASURED, the plant "celu calls elu with
# celu's own alpha" was MISSED with the default rows alone, because `celu`'s
# default alpha IS 1.0 and so at the default the plant changes nothing.  A
# plant that does not move the comparison is a hole in the PLANT.
#
# THE CONSTANTS ARE COMMITTED AT `float32` ON BOTH LANES, AND THAT IS NOT A
# CONVENIENCE -- IT IS A MEASURED JUSTIFICATION, AND IT LOOKS WRONG ON THE
# PYTHON DEVICE, SO A READER WHO "FIXES" IT WILL BREAK THE GATE.  Upstream's
# `asin` names `math.pi / 2`, a DOUBLE; the port has no F64 and names
# `f32(math.pi / 2)`.  MEASURED: with the constant left in DOUBLE the two
# differ by EXACTLY ONE ULP at some inputs (`atan` at x = +-1 and +-3) -- 29 of
# 255 rows on the double-precision PYTHON device -- and swapping the constant's
# value in CPython's OWN graph is what moves it.  MEASURED TOO: tinygrad's own
# generated float32 kernel writes `1.5707963705062866f`, the f32-exact value
# with an `f` suffix, so on a REAL float32 device upstream's constant and the
# port's are THE SAME NUMBER.  The comparison therefore commits the weak float
# constants at `float32` on BOTH lanes, which is what a float32 device does.
# See `gates/ew_activation-compare.py`'s `commit()`.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/weak.bend as W
import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/mixin/elementwise.bend as E

def dr.dt.of(dt: S.Dt) -> String:
  match dt:
    case S.Dt{pri, bits, cls, nm}: nm

def dr.op.of(op: O.Op) -> String: O.Ops.name.of(op)

# THE ARGUMENT OF A NODE.  `cf:` IS THE f32's BITS IN DECIMAL -- the BITS and not the
# decimal, because the port has no F64 and a decimal comparison would pass a value
# that rounds differently, which is exactly what a mistyped coefficient is.
def dr.arg.of(a: O.Arg) -> String:
  match a:
    case O.APy{O.CFloat{f}}: String.concat(["cf:", U32.show(F32.bits(f))])
    case O.APy{O.CInt{i}}: String.concat(["ci:", H.i64_text(i)])
    case O.APy{O.CBool{b}}: String.concat(["cb:", Bool.show(b)])
    case O.ADt{dt}: String.concat(["dt:", dr.dt.of(dt)])
    case _: "-"

# THE SRC IDS, IN SLOT ORDER, SPACE SEPARATED.  The fold appends a SPACE to EVERY
# element, so a node with no srcs has no trailing field and a node with two has two.
def dr.ids.go(xs: List<&2, U32>, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +h <> t: dr.ids.go(t, acc ++ U32.show(h) ++ " ")

# ONE NODE: `<id> <op> <dtype> <arg> <src ids...>`.
def dr.node.at(+ar: O.Arena, +fx: F.Folded, +u: U32) -> String:
  String.concat([U32.show(u), " ", dr.op.of(O.Arena.op(ar, u)), " ", dr.dt.of(W.wk_dt(fx, u)),
    " ", dr.arg.of(O.Arena.arg(ar, u)), " ", dr.ids.go(O.Arena.srcs(ar, u), "")])

# THE METHODS, AS A SUM, because a `Bool.pick` over the ten rows would build all ten
# graphs for every fixture and the node COUNT of the fixture would be ten graphs.
type Meth is Data:
  MAsin{}
  MAcos{}
  MAtan{}
  MElu{a: F32}
  MCelu{a: F32}
  MSelu{a: F32, g: F32}
  MRelu{}
  MSigmoid{}
  MTanh{}
  MQuickGelu{}
  MSwish{}
  MSilu{}

def dr.build(+m: Meth, +t: T.Tensor) -> T.Tensor:
  match m:
    case MAsin{}: E.ew_asin(t)
    case MAcos{}: E.ew_acos(t)
    case MAtan{}: E.ew_atan(t)
    case MElu{a}: E.ew_elu(t, a)
    case MCelu{a}: E.ew_celu(t, a)
    case MSelu{a, g}: E.ew_selu(t, a, g)
    case MRelu{}: E.ew_relu(t)
    case MSigmoid{}: E.ew_sigmoid(t)
    case MTanh{}: E.ew_tanh(t)
    case MQuickGelu{}: E.ew_quick_gelu(t)
    case MSwish{}: E.ew_swish(t)
    case _: E.ew_silu(t)

# THE PARAMETERS, IN THE ROW, so the oracle can call the CPython method with the SAME
# alpha the port used.  `-` is "this method has no such parameter".
def dr.alpha.of(+m: Meth) -> String:
  match m:
    case MElu{a}: U32.show(F32.bits(a))
    case MCelu{a}: U32.show(F32.bits(a))
    case MSelu{a, g}: U32.show(F32.bits(a))
    case _: "-"

def dr.gamma.of(+m: Meth) -> String:
  match m:
    case MSelu{a, g}: U32.show(F32.bits(g))
    case _: "-"

def dr.nodes(xs: List<&2, U32>, +ar: O.Arena, +fx: F.Folded, acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +u <> t: dr.nodes(t, ar, fx, acc ++ dr.node.at(ar, fx, u) ++ "\n")

# ONE GRAPH: the HEADER, the ROOT, and then the nodes in toposort order.  THE FOLD IS
# TAKEN ONCE, AFTER THE GRAPH IS BUILT: `wk_dt` reads a FOLD, and a fold over an arena
# is the arena's own topological read -- taking one per node would fold the arena once
# per node.
def dr.graph(+m: Meth, nm: String, +f: F32) -> String:
  +t = E.ew_ct(E.ew_cf(O.Arena.empty(), f))
  +r = dr.build(m, t)
  +ar = T.Tensor.ar(r)
  +fx = F.folded(ar)
  +xs = O.UOp.toposort(O.Arena.budget(ar), ar, T.Tensor.u(r))
  String.concat(["M ", nm, " ", dr.alpha.of(m), " ", dr.gamma.of(m), " ",
    U32.show(F32.bits(f)), "\n", "R ", U32.show(T.Tensor.u(r)), "\n",
    dr.nodes(xs, ar, fx, "")])

# THE FIXTURES.  THE INFINITY IS `F32.div(1.0, 0.0)` AND NOT A LITERAL because Bend
# has no infinity literal and the division IS the infinity (0x7F800000); THE NaN IS
# `F32.div(0.0, 0.0)` for the same reason.  The signed zero is `F32.neg(0.0)` and not
# `-0.0` so the sign is a SPELLING and not a parse.
def dr.fixtures() -> List<&2, F32>:
  [0.0, F32.neg(0.0), 1.0, F32.neg(1.0), 0.5, F32.neg(0.5), 2.0, F32.neg(2.0),
   3.0, F32.neg(3.0), 0.001, F32.neg(0.001), 1000000.0, F32.neg(1000000.0),
   F32.div(1.0, 0.0), F32.div(F32.neg(1.0), 0.0), F32.div(0.0, 0.0)]

def dr.rows(+m: Meth, +nm: String, xs: List<&2, F32>) -> String:
  match xs:
    case Nil{}: ""
    case +f <> t: dr.graph(m, nm, f) ++ dr.rows(m, nm, t)

# THE FIFTEEN ROW SETS.  THREE OF THEM ARE A METHOD WITH A NON-DEFAULT PARAMETER, and
# that is the point: a method whose parameter is IGNORED prints the SAME graph for
# both, and a method whose default is WRONG prints a graph no default-only row can
# compare against.  FIFTEEN TIMES SEVENTEEN FIXTURES IS 255 GRAPHS.
def dr.all() -> String:
  dr.rows(MAsin{}, "asin", dr.fixtures()) ++
  dr.rows(MAcos{}, "acos", dr.fixtures()) ++
  dr.rows(MAtan{}, "atan", dr.fixtures()) ++
  dr.rows(MElu{E.ew_k.elu_alpha()}, "elu", dr.fixtures()) ++
  dr.rows(MElu{0.5}, "elu_alpha", dr.fixtures()) ++
  dr.rows(MCelu{E.ew_k.elu_alpha()}, "celu", dr.fixtures()) ++
  dr.rows(MCelu{0.5}, "celu_alpha", dr.fixtures()) ++
  dr.rows(MSelu{E.ew_k.selu_alpha(), E.ew_k.selu_gamma()}, "selu", dr.fixtures()) ++
  dr.rows(MSelu{0.5, 2.0}, "selu_alpha", dr.fixtures()) ++
  dr.rows(MRelu{}, "relu", dr.fixtures()) ++
  dr.rows(MSigmoid{}, "sigmoid", dr.fixtures()) ++
  dr.rows(MTanh{}, "tanh", dr.fixtures()) ++
  dr.rows(MQuickGelu{}, "quick_gelu", dr.fixtures()) ++
  dr.rows(MSwish{}, "swish", dr.fixtures()) ++
  dr.rows(MSilu{}, "silu", dr.fixtures())

def main() -> IO(Unit):
  IO.print(dr.all())
