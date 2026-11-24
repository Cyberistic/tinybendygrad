# .agents/slop/browser/tstep.bend -- ONE TRAINING STEP's GRAPH, and the FIRST question about it:
# does `tn_backward` reach weights through conv -> relu -> pool -> linear at all?
#
# The forward is `fchain_prog`'s, with two changes forced by training: the weights stay TENSORS
# (a backward pass needs them in scope), and the output is compared to a TARGET through
# `sum((y-t)^2)` -- the loss whose gradient is `2*(y-t)`, which a longhand reference can check.
#
# WHAT IT PRINTS, and each row is a separate claim:
#   tstep.chain   -- the forward's op names, so the fixture is the chain and not something else
#   tstep.gw1/w2  -- the SIGNATURE of the gradient `tn_backward` answered for each weight
#   tstep.gnone   -- whether the gradient is the arena bottom (0), i.e. NOTHING WAS ANSWERED
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/tensor.bend as T
import ./../../../tinybendygrad/mixin/movement.bend as MX
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/helpers.bend as H
import ./../../../tinybendygrad/mixin/gradient.bend as G
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/schedule/realize.bend as RZ

# conv2x2 -> relu -> pool -> linear, then `sum((y-t)^2)`, then `tn_backward` for BOTH weights.
# ONE def and no tuple returns: `compute_gradient` GROWS the arena (tensor.bend's rule 5), so every
# step reads the arena the previous one produced -- which is exactly what a linear body says.
def rows() -> String:
  # THE FORWARD, with no stores: a training GRAPH is value flow, and the chain's shape is the
  # only thing this row is about. `tn_rop` answers a `Found`, so each stage is re-wrapped by
  # `tn_new` -- the same idiom `fchain_prog` uses.
  +x = RZ.rz_input(O.Arena.empty(), 1, 784, [1, 1, 28, 28])
  +w1 = RZ.rz_input(T.Tensor.ar(x), 2, 4, [1, 1, 2, 2])
  +c1 = T.tn_mul(MX.mxw_reshape.go(x, [1, 1, 14, 2, 14, 2]), MX.mxw_reshape.go(w1, [1, 1, 1, 2, 1, 2]))
  +f1 = T.tn_rop(T.Tensor.ar(c1), T.Tensor.u(c1), O.OpsADD{}, [3, 5])
  +v1 = MX.mxw_reshape(T.tn_new(O.Found.ar(f1), O.Found.i(f1)), [1, 1, 14, 14])
  +a2 = T.tn_relu(v1)
  +v2 = MX.mxw_reshape.go(a2, [1, 1, 7, 2, 7, 2])
  +f3 = T.tn_rop(T.Tensor.ar(v2), T.Tensor.u(v2), O.OpsMAX{}, [3, 5])
  +p3 = T.tn_new(O.Found.ar(f3), O.Found.i(f3))
  +w2 = RZ.rz_input(T.Tensor.ar(p3), 6, 490, [49, 10])
  +lhs = MX.mxw_reshape.go(p3, [1, 1, 49])
  +rhs = MX.mxw_permute.go(MX.mxw_reshape.go(w2, [1, 49, 10]), [0, 2, 1])
  +c4 = T.tn_mul(lhs, rhs)
  +f4 = T.tn_rop(T.Tensor.ar(c4), T.Tensor.u(c4), O.OpsADD{}, [2])
  +out = T.tn_new(O.Found.ar(f4), O.Found.i(f4))
  # loss = sum((out - t)^2)
  +t = RZ.rz_input(T.Tensor.ar(out), 7, 10, [1, 10])
  +d = T.tn_sub(out, t)
  +sq = T.tn_square(d)
  +loss = T.tn_rop(T.Tensor.ar(sq), T.Tensor.u(sq), O.OpsADD{}, [1])
  +lt = T.tn_new(O.Found.ar(loss), O.Found.i(loss))
  # THE WALK ITSELF, and its own counters. `skip` is "a turn the outer loop passed over";
  # `hole` is a node the rule table did not claim. Upstream RAISES on a hole; the port STOPS,
  # so a hole count of 1 with `grads=ZERO` names the node class whose rule is missing.
  +tg: List<&2, U32> = [T.Tensor.u(w1), T.Tensor.u(w2)]
  +root = T.Tensor.u(lt)
  +dw = G._deepwalk(root, tg, T.Tensor.ar(lt))
  +wk = G.Deep.walk_of(dw)
  +seed = O.UOp.const(T.Tensor.ar(lt), O.CInt{H.i64_of_i32(1)})
  +cs = G.compute_gradient(root, O.Found.i(seed), tg, T.Tensor.ar(lt))
  String.concat(["tstep.walk=", U32.show(U32.from_nat(List.length(&2, U32, wk))),
                 " skip=", U32.show(G.CState.skip_of(cs)),
                 " hole=", U32.show(G.CState.hole_of(cs)),
                 " rootop=", RF.eng_op_name(O.Arena.op(T.Tensor.ar(lt), root)),
                 " grads=", T.tn_bwd_grad.of(T.tn_backward(O.Found.ar(seed), T.Tensor.u(lt), T.Tensors.of_list(tg), O.Found.i(seed)))])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(rows())
