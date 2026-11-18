# shaders/shader.bend -- A FRAGMENT SHADER BUILT AS A TENSOR PROGRAM.
#
# THE CLAIM THIS FILE EXISTS TO TEST: Shadertoy's expression vocabulary is expressible in
# the port's UOps WITHOUT EXTENDING THE IR. Not "a shader renders" -- that is the runtime
# half, and this folder does not have it. This file answers the compiler question only:
# what graph does a fragment shader BUILD, and does the port build the same one as CPython.
#
# THE SHADER is the smallest anti-aliased shape that uses the four vocabulary items a
# Shadertoy author reaches for and a tensor model does not have on the shelf:
#
#   length(p)     sqrt(x*x + y*y)                    -- two CHANNELS, not a vec2
#   fwidth(d)     |d - neighbour(d)| summed per axis -- screen-space derivatives
#   smoothstep    clamp((x - e0) / (e1 - e0), 0, 1)  -- composed, it is GLSL not tensor
#   mix/step      maximum / where                    -- the port has these
#
# AND `fwidth` IS THE POINT. It is the one the tensor model is supposed to be missing, and
# it needs NO NEW OP: a neighbour is `pad` then `shrink`, which are movement ops the port
# already has, and the difference is one `sub` and one `abs`. WHAT THIS FILE MEASURES is
# that claim, node for node, against the CPython side in `shader-oracle.py`.
#
# IT IS NOT A RASTERIZER. There is no geometry, no coverage and no perspective divide: a
# fragment shader's inputs ARE buffers, so the two coordinate grids below are the inputs,
# which is what a fragment stage actually receives.
#
# THE ROW FORMAT is a preorder unfolding of the graph, one line per node:
#
#   <depth> <op> <dtype> <arg>
#
# DEPTH AND NOT AN INDEX, because the port's ids are ARENA INDICES and CPython's are
# creation-order ids: the same graph is two different numberings, so a diff over ids would
# be a diff of conventions. A DAG is printed as its UNFOLDING -- a shared node appears once
# per path -- which is deterministic on both sides and needs no visited set.
#
# A `?` IN THE ARG COLUMN IS A REFUSAL AND NOT A VALUE: it means an `Arg` variant this
# fixture has no rendering for. The gate fails on it rather than letting two unknown args
# agree, because two unknowns agreeing is the "0 disagreements over 0 comparisons" defect.

import ../tinybendygrad/uop/ops.bend as O
import ../tinybendygrad/uop/fold.bend as F
import ../tinybendygrad/uop/render.bend as R
import ../tinybendygrad/helpers.bend as H
import ../tinybendygrad/LAWS/spec.bend as S
import ../tinybendygrad/tensor.bend as T
import ../tinybendygrad/mixin/creation.bend as CR
import ../tinybendygrad/mixin/elementwise.bend as E
import ../tinybendygrad/mixin/movement.bend as MX

# THE CANVAS. Two grids and not one vec2: a tensor has no tuple element type, so the two
# channels of `fragCoord` are two buffers. 16x16 is a power of two so the quad neighbour
# arithmetic below has no ragged edge to explain.
def SHN() -> U32: 16

# THE ONE PARAMETER THE GATE PLANTS ON. `--plant` rewrites THIS line in a COPY of this file
# (so the port's own graph moves, rather than the oracle's), and a gate that plants only on
# the oracle side proves the comparer and not the port.
def SH_R() -> F32: 0.5

# A float constant, as the `Ew` the elementwise mixin takes. `E.CFloat` and not `E.CInt`
# because every arithmetic node in this shader is f32 -- an integer constant here would
# promote the whole graph to int and the dtype column would say so.
def sh_kf(x: F32) -> E.Ew: E.ECon{O.CFloat{x}}

# `abs` -- there is no `Ops.ABS`: upstream writes it as `maximum(x, -x)` and so does this,
# which is why the node count is three and not one.
def sh_abs(+t: T.Tensor) -> T.Tensor:
  E.ew_maximum(t, E.ETen{E.ew_neg(t)}, False{})

# THE NEIGHBOUR, and it is a MOVEMENT OP. `pad` then `shrink` is `x[i+1]`.
#
# `mxw_pad` TAKES UPSTREAM's PAIR FORM AND NOT AFTER-AMOUNTS: the second list is `(offset,
# END)` with `END = s + before + after`, which is what `Tensor.pad` COMPUTES before it calls
# `_mop` (`movement.py:186-190`: `tuple((x[0], s+x[0]+x[1]) ...)`). MEASURED, and it cost
# this file a false defect report: `mxw_pad(t, [0,0], [0,1])` on a `(16,16)` answers a `?`
# dtype because the fold correctly rejects `0 + 16 <= 1`, and `mxw_pad(t, [0,0], [16,17])`
# answers `f32`. So the after-amount is `1` and the END is `s+1`, and the port is right.
def sh_right(+t: T.Tensor) -> T.Tensor:
  MX.mxw_shrink(MX.mxw_pad(t, [0, 0], [16, 17]), [0, 1], [16, 16])

def sh_down(+t: T.Tensor) -> T.Tensor:
  MX.mxw_shrink(MX.mxw_pad(t, [0, 0], [17, 16]), [1, 0], [16, 16])

# THE SHADER.
#
#   d      = length(p) - RADIUS                the signed distance field
#   fw     = |d - right(d)| + |d - down(d)|    the screen-space derivative
#   t      = clamp((d + fw) / (2*fw + eps), 0, 1)     smoothstep(-fw, +fw, d)
#   alpha  = 1 - t
#
# `smoothstep(e0, e1, x)` IS `clamp((x - e0) / (e1 - e0), 0, 1)` with `e0 = -fw` and
# `e1 = +fw`, so the numerator is `d + fw` and the denominator is `2*fw`. That is the whole
# reason `fwidth` exists: the edge is one `fw` wide whatever the canvas, and dividing by it
# is what makes the outline one pixel.
#
# THE `+ EPS` under the divide is the shader author's guard against a zero derivative, and it
# is kept rather than dropped because dropping it is a shader that divides by zero.
#
# `clamp` IS NOT `maximum(maximum(x, 0), 1)` and the first draft of this file had exactly
# that, which is why the next three nodes are what they are: the port has `OpsMAX` and NO
# `OpsMIN` (upstream has no MIN either), so the upper bound is the identity
# `min(x, 1) = x - max(x - 1, 0)`, which holds for every `x >= 0` and costs three nodes.
# THE FIRST DRAFT'S `maximum(maximum(t, 0), 1)` SATURATES TO 1 EVERYWHERE -- a graph diff
# would not have caught it, because both sides would have to be given the same wrong
# formula, and that is the defect class this folder is about.
def sh_graph() -> O.Found:
  +ar = O.Arena.empty()
  +xv = CR.cr_empty(ar, Some{S.single()}, [16, 16], S.D1{0})
  +yv = CR.cr_empty(T.Tensor.ar(xv), Some{S.single()}, [16, 16], S.D1{0})
  +xx = E.ew_mul2(xv, xv, False{})
  +yy = E.ew_mul2(yv, yv, False{})
  +sq = E.ew_add(xx, E.ETen{yy}, False{})
  +rr = E.ew_sqrt(sq)
  +dd = E.ew_sub(rr, sh_kf(SH_R()), False{})
  +dx = sh_abs(E.ew_sub(dd, E.ETen{sh_right(dd)}, False{}))
  +dy = sh_abs(E.ew_sub(dd, E.ETen{sh_down(dd)}, False{}))
  +fw = E.ew_add(dx, E.ETen{dy}, False{})
  +nm = E.ew_add(dd, E.ETen{fw}, False{})
  +dn = E.ew_add(E.ew_add(fw, E.ETen{fw}, False{}), E.ECon{O.CFloat{0.0001}}, False{})
  +tt = E.ew_div(nm, E.ETen{dn}, False{}, E.RNone{})
  +lo = E.ew_maximum(tt, E.ECon{O.CFloat{0.0}}, False{})
  +hi = E.ew_maximum(E.ew_sub(lo, E.ECon{O.CFloat{1.0}}, False{}), E.ECon{O.CFloat{0.0}}, False{})
  +cl = E.ew_sub(lo, E.ETen{hi}, False{})
  +al = E.ew_sub(cl, E.ECon{O.CFloat{1.0}}, True{})
  O.Found{T.Tensor.ar(al), T.Tensor.u(al)}

# THE ARG COLUMN. Four arms and a refusal, because this fixture builds four kinds: a
# `BUFFER`'s param, a `CONST`'s value, a `CAST`'s dtype (there is none here), and `ANone`
# for every arithmetic node.
def sh_dt(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: R.dt_repr(d)
    case None{}: "?"

def sh_arg(a: O.Arg) -> String:
  match a:
    case O.ANone{}: "-"
    case O.APy{v}: R.const_repr(v)
    case O.ADt{d}: R.dt_repr(d)
    case O.AParam{p}: String.concat(["P", U32.show(O.ParamArg.slot(p))])
    case _: "?"

def sh_row(+ar: O.Arena, +tb: F.Table, +k: U32, +d: U32) -> String:
  String.concat([U32.show(d), " ", O.Ops.name(O.Arena.op(ar, k)), " ",
    sh_dt(F.UOp.dtype(ar, tb, k)), " ", sh_arg(O.Arena.arg(ar, k))])

# THE WALK. `fuel` is the arena's node count, which bounds the unfolding because every
# printed node consumes one; the `case 0n` arm is unreachable on a well-formed graph and is
# what makes the walk total, not a limit on it.
#
# IT RECURSES ON THE SOURCE LIST and not on a node, because bend checks defs in FILE ORDER
# and so a mutually recursive pair (`walk` calls `srcs`, `srcs` calls `walk`) does not
# compile. One def over a list, with the node's own children pressed in front of its
# siblings, IS the preorder walk: children, then siblings, at the same depth.
def sh_walk(fuel: Nat, +ar: O.Arena, +tb: F.Table, ss: List<&2, U32>, +d: U32) -> IO(Unit):
  match fuel:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+ +p:
      match ss:
        case Nil{}: IO.pure(Unit, Unit{})
        case +s <> rest:
          do IO<Unit>:
            h : Unit <- IO.print(sh_row(ar, tb, s, d))
            c : Unit <- sh_walk(p, ar, tb, O.Arena.srcs(ar, s), U32.add(d, 1))
            r : Unit <- sh_walk(p, ar, tb, rest, d)
            IO.pure(Unit, r)

def main() -> IO(Unit):
  do IO<Unit>:
    +f : O.Found <- IO.pure(O.Found, sh_graph())
    +x : F.Folded <- IO.pure(F.Folded, F.folded(O.Found.ar(f)))
    h : Unit <- IO.print("# shader=aa-circle")
    r : Unit <- sh_walk(U32.to_nat(O.Arena.next(O.Found.ar(f))), F.Folded.ar(x),
      F.Folded.t(x), [O.Found.i(f)], 0)
    IO.pure(Unit, r)
